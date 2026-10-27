import { Controller } from "@hotwired/stimulus"

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
const DEBOUNCE_MS = 700
const KEEPALIVE_LIMIT = 60000 // browsers cap keepalive bodies at 64KB

export default class extends Controller {
  static targets = ["status"]

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
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this._onBeforeFetch)
    window.removeEventListener("pagehide", this._onPageHide)
    document.removeEventListener("visibilitychange", this._onVisibility)
    window.removeEventListener("notes:flush", this._onFlush)
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
    this.request(value, { keepalive: true }).catch(() => {})
  }

  async send({ explicit }) {
    if (!this.textarea) return "clean"
    const value = this.textarea.value
    if (value === this.saved && !explicit) return "clean"
    if (value === this.saved && !this.guest) { this.setStatus("Saved just now"); return "clean" }

    this.setStatus("Saving…")
    let res
    try {
      res = await this.request(value)
    } catch {
      this.setStatus("Save failed — will retry")
      this.retryLater()
      return "failed"
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
    this.setStatus(this.dirty ? "Editing…" : "Saved just now")
    return "saved"
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
