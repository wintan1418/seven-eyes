import { Controller } from "@hotwired/stimulus"
import { readMode, saveMode, modeForKey, validMode, MODE_EVENT, PLACEHOLDERS } from "../lib/scripture_mode"

// The Auto | Reference | Words switch on a scripture search box (console
// library, the preach Go box, the /search page). One job: keep the switch,
// the remembered choice (lib/scripture_mode) and every other switch on the
// page in step, and tell the box's own controller through the window event
// `scripture-mode:change {mode}`. Alt+A / Alt+R / Alt+W switch from the
// keyboard while typing in the box (or with nothing focused).
//
//   <div data-controller="search-mode" data-search-mode-input-value="…css…">
//     <button data-search-mode-target="option" data-mode="reference"
//             data-action="search-mode#pick">Reference</button> …
//     <input type="hidden" data-search-mode-target="field">   (optional: a form's mode param)
export default class extends Controller {
  static targets = [ "option", "field" ]
  static values = { input: String, placeholders: { type: Boolean, default: true } }

  connect() {
    this._onChange = (e) => this._paint(e.detail?.mode)
    this._onKey = (e) => this._key(e)
    window.addEventListener(MODE_EVENT, this._onChange)
    window.addEventListener("keydown", this._onKey)
    this._paint(this.hasFieldTarget && this.fieldTarget.value ? validMode(this.fieldTarget.value) : readMode())
  }

  disconnect() {
    window.removeEventListener(MODE_EVENT, this._onChange)
    window.removeEventListener("keydown", this._onKey)
  }

  pick(event) {
    event.preventDefault()
    this.set(event.currentTarget.dataset.mode)
    this._input()?.focus()
  }

  set(mode) {
    const m = saveMode(mode)
    if (m === this._mode) return
    window.dispatchEvent(new CustomEvent(MODE_EVENT, { detail: { mode: m } }))
  }

  _key(event) {
    const mode = modeForKey(event)
    if (!mode || !this._visible()) return
    const t = event.target
    const typing = t instanceof Element && t.matches("input, textarea, select, [contenteditable]")
    if (typing && t !== this._input()) return
    event.preventDefault()
    if (this._handled === event) return
    this._handled = event
    this.set(mode)
  }

  _paint(mode) {
    this._mode = validMode(mode)
    this.optionTargets.forEach((b) => {
      const on = b.dataset.mode === this._mode
      b.setAttribute("aria-checked", String(on))
      b.classList.toggle("is-on", on)
    })
    if (this.hasFieldTarget) {
      this.fieldTarget.value = this._mode
      this.fieldTarget.disabled = this._mode === "auto" // Auto is the default: keep URLs plain
    }
    this.element.dataset.mode = this._mode
    const input = this._input()
    if (input && this.placeholdersValue) input.placeholder = input.dataset[`placeholder${cap(this._mode)}`] || PLACEHOLDERS[this._mode]
  }

  _input() {
    return this.inputValue ? document.querySelector(this.inputValue) : null
  }

  _visible() {
    return this.element.getClientRects().length > 0
  }
}

function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
