import { Controller } from "@hotwired/stimulus"
import { watchFrameErrors } from "../lib/frame_errors"

// The "AI Rabbi" slide-over. Listens for a `rabbi:ask` window event (dispatched
// from the highlighter popover with the selected text + verse id), fills the
// hidden form, opens the drawer with a "consulting…" state, and submits — Turbo
// loads the exposition into the rabbi_drawer frame. A failed request (server
// error, network drop) replaces the "reading…" state with an error and a
// retry; a 401 opens the "create an account" gate.
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
  static targets = ["host", "form", "verseId", "verseIds", "query", "frame"]

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
