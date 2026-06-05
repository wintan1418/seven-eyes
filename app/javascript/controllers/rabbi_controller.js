import { Controller } from "@hotwired/stimulus"

// The "AI Rabbi" slide-over. Listens for a `rabbi:ask` window event (dispatched
// from the highlighter popover with the selected text + verse id), fills the
// hidden form, opens the drawer with a "consulting…" state, and submits — Turbo
// loads the exposition into the rabbi_drawer frame.
const LOADING = `
  <div class="ps-rabbi-loading">
    <div class="orn">&#10018;</div>
    <div class="lead">The Rabbi is reading the whole chapter…</div>
    <div class="hint">Weighing context and cross-references before a word is said.</div>
  </div>`

export default class extends Controller {
  static targets = ["host", "form", "verseId", "query", "frame"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    this._onAsk = (e) => this.ask(e.detail || {})
    window.addEventListener("rabbi:ask", this._onAsk)
  }

  disconnect() {
    window.removeEventListener("rabbi:ask", this._onAsk)
    document.removeEventListener("keydown", this._onKey)
  }

  open() {
    this.hostTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    this.hostTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }

  ask({ verseId, text }) {
    if (!verseId || !text || !text.trim()) return
    this.verseIdTarget.value = verseId
    this.queryTarget.value = text.trim()
    this.open()
    if (this.hasFrameTarget) this.frameTarget.innerHTML = LOADING
    this.formTarget.requestSubmit()
  }
}
