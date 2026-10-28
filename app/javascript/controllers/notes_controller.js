import { Controller } from "@hotwired/stimulus"
import { queueNote, pendingNote, flushOutbox, subscribe } from "../lib/offline/outbox"
import { owner, signedIn } from "../lib/offline/page"

// Debounced background auto-save for a pane's notes. Submits the notes form via
// fetch (not Turbo) so the pane frame is never re-rendered while typing.
//
// Never lose a keystroke:
//   • Saves are serialised (one request in flight at a time, each sending the
//     latest text), so an older save can never land after a newer one.
//   • Any Turbo request that would re-render this pane (translation switch,
//     chapter arrows, book browser, xref "load in pane", a full visit) is held
//     until pending notes are saved — otherwise the frame re-renders with the
//     stale DB copy and the next autosave overwrites the newer text.
//   • pagehide / tab hidden / disconnect flush immediately with a keepalive
//     request, so the last ~700ms of typing survives closing the tab.
//   • A window `notes:flush` event (Cmd/Ctrl+S) saves now and reports back.
//   • No connection: a signed-in reader's text goes to the outbox (IndexedDB)
//     with the notes revision it was built on, and is sent when the network
//     is back. If the notes changed elsewhere meanwhile, the server keeps
//     both (NotesSync) and this textarea shows the merged text. Guests get
//     the usual "create an account to save" prompt.
const DEBOUNCE_MS = 700
const KEEPALIVE_LIMIT = 60000 // browsers cap keepalive bodies at 64KB

export default class extends Controller {
  static targets = ["status"]
  static values = { revision: Number }

  connect() {
    this.timeout = null
    this.textarea = this.element.querySelector("textarea[name='pane[notes]']")
    this.saved = this.textarea ? this.textarea.value : ""
    this.chain = Promise.resolve()
    this.pending = 0     // saves queued or in flight
    this.guest = false   // the server said 401 — stop retrying in the background

    this._onBeforeFetch = (e) => this.holdTurboRequest(e)
    this._onPageHide = () => this.flushNow()
    this._onVisibility = () => { if (document.visibilityState === "hidden") this.flushNow() }
    this._onFlush = (e) => e.detail?.results?.push(this.save({ explicit: true }))

    document.addEventListener("turbo:before-fetch-request", this._onBeforeFetch)
    window.addEventListener("pagehide", this._onPageHide)
    document.addEventListener("visibilitychange", this._onVisibility)
    window.addEventListener("notes:flush", this._onFlush)
    this._unsubscribe = subscribe((m) => this.synced(m))
    this.restorePending()
  }

  get path() {
    try { return new URL(this.element.action, window.location.href).pathname } catch { return this.element.getAttribute("action") }
  }

  // A note typed offline and not yet sent wins over the copy the page came with.
  async restorePending() {
    if (!this.textarea || !signedIn()) return
    const op = await pendingNote(this.path, owner()).catch(() => null)
    if (!op) return
    const text = op.body["pane[notes]"]
    if (!this.dirty && text !== this.textarea.value) this.textarea.value = text
    this.saved = text
    this.setStatus(navigator.onLine ? "Syncing…" : "Saved on this device — will sync when you're online")
  }

  // The outbox delivered this pane's note.
  synced(message) {
    if (message?.type !== "notes-synced" || message.url !== this.path) return
    if (message.revision != null) this.revisionValue = message.revision
    if (message.conflict && message.notes != null && !this.dirty) {
      this.textarea.value = message.notes
      this.saved = message.notes
      this.setStatus("Synced — your offline edit was added below the newer notes")
    } else if (!this.dirty) {
      this.setStatus("Saved just now")
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this._onBeforeFetch)
    window.removeEventListener("pagehide", this._onPageHide)
    document.removeEventListener("visibilitychange", this._onVisibility)
    window.removeEventListener("notes:flush", this._onFlush)
    this._unsubscribe?.()
    this.flushNow()
  }

  get dirty() {
    return !!this.textarea && this.textarea.value !== this.saved
  }

  schedule() {
    clearTimeout(this.timeout)
    this.setStatus(this.guest ? "Sign in to save" : "Editing…")
    if (this.guest) return
    this.timeout = setTimeout(() => this.save(), DEBOUNCE_MS)
  }

  // Queue a save behind any in-flight one. Resolves to
  // "saved" | "clean" | "unauthorized" | "failed".
  save({ explicit = false } = {}) {
    clearTimeout(this.timeout)
    if (this.guest && !explicit) return Promise.resolve("unauthorized")
    this.pending++
    const run = this.chain.then(() => this.send({ explicit }))
    this.chain = run.catch(() => {}).finally(() => { this.pending-- })
    return run
  }

  // Fire-and-forget flush for when the page (or this pane) is going away. Not
  // chained — there may be no event loop left to run the queue — and sent with
  // keepalive so the browser finishes it after the page is gone.
  flushNow() {
    clearTimeout(this.timeout)
    if (!this.dirty || this.guest) return
    const value = this.textarea.value
    this.saved = value
    if (!navigator.onLine) { this.queue(value).catch(() => {}); return }
    this.request(value, { keepalive: true }).catch(() => {})
  }

  async send({ explicit }) {
    if (!this.textarea) return "clean"
    const value = this.textarea.value
    if (value === this.saved && !explicit) return "clean"
    if (value === this.saved && !this.guest) { this.setStatus("Saved just now"); return "clean" }

    // An offline edit is still waiting: this text joins it, so the two are
    // sent as one (and checked against the server copy) — never out of order.
    if (await pendingNote(this.path, owner()).catch(() => null)) return this.queue(value, { flush: true })

    this.setStatus("Saving…")
    let res
    try {
      res = await this.request(value)
    } catch {
      return this.offline(value)
    }
    if (res.status === 401) {
      this.guest = true
      this.setStatus("Sign in to save")
      window.dispatchEvent(new CustomEvent("auth:required"))
      return "unauthorized"
    }
    if (!res.ok) {
      this.setStatus("Save failed — will retry")
      this.retryLater()
      return "failed"
    }
    this.saved = value
    const revision = parseInt(res.headers.get("X-Notes-Revision"), 10)
    if (!Number.isNaN(revision)) this.revisionValue = revision
    this.setStatus(this.dirty ? "Editing…" : "Saved just now")
    return "saved"
  }

  // The request never reached the server.
  async offline(value) {
    if (!signedIn()) {
      this.guest = true
      this.setStatus("Sign in to save")
      window.dispatchEvent(new CustomEvent("auth:required"))
      return "unauthorized"
    }
    return this.queue(value)
  }

  async queue(value, { flush = false } = {}) {
    if (!signedIn()) return this.offline(value)
    try {
      await queueNote(this.path, value, { baseRevision: this.revisionValue, owner: owner() })
    } catch {
      this.setStatus("Save failed — will retry")
      this.retryLater()
      return "failed"
    }
    this.saved = value
    if (flush && navigator.onLine) {
      this.setStatus("Syncing…")
      flushOutbox().catch(() => {})
    } else {
      this.setStatus("Saved on this device — will sync when you're online")
    }
    return "queued"
  }

  retryLater() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => { if (this.dirty) this.save() }, DEBOUNCE_MS * 4)
  }

  request(value, { keepalive = false } = {}) {
    const body = new FormData(this.element)
    body.set("pane[notes]", value)
    body.set("autosave", "1")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch(this.element.action, {
      method: "PATCH",
      body,
      credentials: "same-origin",
      keepalive: keepalive && value.length * 3 < KEEPALIVE_LIMIT,
      headers: { "X-CSRF-Token": token || "", "Accept": "text/plain" }
    })
  }

  // Hold a Turbo request that would replace this pane (its own frame, or a
  // full-page visit) until the notes are safely stored, then let it go.
  holdTurboRequest(event) {
    if (this.guest || (!this.dirty && this.pending === 0)) return
    const headers = event.detail?.fetchOptions?.headers || {}
    const frame = headers["Turbo-Frame"]
    const myFrame = this.element.closest("turbo-frame")?.id
    if (frame && frame !== myFrame) return
    if (typeof event.detail?.resume !== "function") return

    event.preventDefault()
    let resumed = false
    const resume = () => { if (!resumed) { resumed = true; event.detail.resume() } }
    // Never strand navigation behind a hung save.
    const guard = setTimeout(resume, 5000)
    const flushed = this.dirty ? this.save() : this.chain
    flushed.catch(() => {}).finally(() => { clearTimeout(guard); resume() })
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
