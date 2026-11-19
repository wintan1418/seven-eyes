import { Controller } from "@hotwired/stimulus"
import { watchFrameErrors } from "../lib/frame_errors"
import { pollAiRequest, thinkingHint } from "../lib/ai_poll"

// The "AI Rabbi" slide-over. Listens for a `rabbi:ask` window event (dispatched
// from the highlighter popover with the selected text + verse id), fills the
// hidden form, opens the drawer with a "consulting…" state, and submits — Turbo
// loads the exposition into the rabbi_drawer frame. A failed request (server
// error, network drop) replaces the "reading…" state with an error and a
// retry; a 401 opens the "create an account" gate.
//
// The answer itself is worked out in the background (AiRequest): the request
// returns a "thinking" frame at once whose pending target names a poll URL;
// pendingTargetConnected asks it until the answer is in and swaps it into the
// frame (the same swap Turbo does), counting the seconds meanwhile.
const LOADING = `
  <div class="ps-rabbi-loading">
    <div class="orn">&#10018;</div>
    <div class="lead">The Rabbi is reading the whole chapter…</div>
    <div class="hint">Weighing context and cross-references before a word is said.</div>
  </div>`

const FAILED = `
  <div class="ps-rabbi-loading is-error" role="alert">
    <div class="orn">&#10018;</div>
    <div class="lead">The Rabbi couldn&rsquo;t answer just now.</div>
    <div class="hint">The connection or the server faltered. Your question is kept.</div>
    <button type="button" class="ps-tb-btn" data-action="rabbi#retry">Try again</button>
  </div>`

const SIGN_IN = `
  <div class="ps-rabbi-loading is-error" role="alert">
    <div class="orn">&#10018;</div>
    <div class="lead">Sign in to ask the Rabbi.</div>
    <div class="hint">The Rabbi answers for members &mdash; create a free account to continue.</div>
  </div>`

export default class extends Controller {
  static targets = ["host", "form", "verseId", "verseIds", "query", "frame", "pending"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    this._onAsk = (e) => this.ask(e.detail || {})
    window.addEventListener("rabbi:ask", this._onAsk)
    if (this.hasHostTarget) {
      this._unwatch = watchFrameErrors(this.hostTarget, (frame, kind) => this.failed(frame, kind))
    }
  }

  disconnect() {
    window.removeEventListener("rabbi:ask", this._onAsk)
    document.removeEventListener("keydown", this._onKey)
    this._unwatch?.()
  }

  open() {
    this.hostTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    this.hostTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }

  ask({ verseId, verseIds, text }) {
    if (!verseId || !text || !text.trim()) return
    this.verseIdTarget.value = verseId
    if (this.hasVerseIdsTarget) this.verseIdsTarget.value = (verseIds || [verseId]).join(",")
    this.queryTarget.value = text.trim()
    this.open()
    this.submit()
  }

  submit() {
    if (this.hasFrameTarget) this.frameTarget.innerHTML = LOADING
    this.formTarget.requestSubmit()
  }

  // The main answer re-asks the same question; a nested frame (diagram,
  // illustration) reloads its own request.
  retry(event) {
    const frame = event?.currentTarget?.closest("turbo-frame")
    if (!frame || (this.hasFrameTarget && frame === this.frameTarget)) return this.submit()
    if (frame.src) frame.reload()
  }

  pendingTargetConnected(el) {
    const frame = el.closest("turbo-frame")
    if (!frame || !el.dataset.url) return
    const abort = new AbortController()
    const started = Date.now()
    const elapsed = el.querySelector("[data-ai-elapsed]")
    const hint = el.querySelector("[data-ai-hint]")
    const timer = setInterval(() => {
      const seconds = Math.round((Date.now() - started) / 1000)
      if (elapsed && seconds >= 3) elapsed.textContent = `${seconds} s`
      const text = thinkingHint(el.dataset.kind, seconds)
      if (text && hint) hint.textContent = text
    }, 1000)
    this._pending = new Map(this._pending || [])
    this._pending.set(el, () => { abort.abort(); clearInterval(timer) })

    pollAiRequest(el.dataset.url, { accept: "text/html", headers: { "Turbo-Frame": frame.id }, signal: abort.signal })
      .then(async (out) => {
        clearInterval(timer)
        if (out.aborted || !el.isConnected) return
        if (out.unauthorized) {
          window.dispatchEvent(new CustomEvent("auth:required"))
          return this.failed(frame, "auth")
        }
        const html = out.response ? await out.response.text() : null
        const fresh = html && new DOMParser().parseFromString(html, "text/html")
          .querySelector(`turbo-frame#${CSS.escape(frame.id)}`)
        if (!el.isConnected) return
        if (!fresh) return this._pendingFailed(frame, el)
        frame.replaceChildren(...fresh.childNodes)
      })
  }

  pendingTargetDisconnected(el) {
    this._pending?.get(el)?.()
    this._pending?.delete(el)
  }

  // The worker never answered (or the answer couldn't be read): an error with
  // Retry. The main answer re-submits the question; an illustration re-POSTs.
  _pendingFailed(frame, el) {
    const retryUrl = el.dataset.retryUrl
    const main = this.hasFrameTarget && frame === this.frameTarget
    if (main || !retryUrl) return this.failed(frame, "error")
    frame.innerHTML = FAILED
    const button = frame.querySelector("button")
    button.dataset.action = "rabbi#retryPost"
    button.dataset.url = retryUrl
  }

  retryPost(event) {
    const button = event.currentTarget
    const frame = button.closest("turbo-frame")
    if (!frame || !button.dataset.url) return
    const form = document.createElement("form")
    form.method = "post"
    form.action = button.dataset.url
    form.dataset.turboFrame = frame.id
    form.hidden = true
    this.element.appendChild(form)
    form.requestSubmit()
    form.remove()
  }

  failed(frame, kind) {
    const main = this.hasFrameTarget && frame === this.frameTarget
    if (kind === "auth") {
      frame.innerHTML = SIGN_IN
    } else if (main || frame.src) {
      frame.innerHTML = FAILED
    } else {
      frame.innerHTML = FAILED.replace(/<button[\s\S]*<\/button>/, "")
    }
  }
}
