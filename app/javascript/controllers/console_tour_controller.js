import { Controller } from "@hotwired/stimulus"

// First run of the operator console: four short steps — Service → Preview →
// Live → Library — each lighting up its region. Shown once per account on this
// device (localStorage "ps-console-tour:<owner>"), the first time the console
// opens; Skip / Esc / Got it all finish it. The toolbar's "? Tour" replays it
// (console:tour). Lives on .cx-tour in _console, operator window only.
const KEY_PREFIX = "ps-console-tour:"

export default class extends Controller {
  static targets = [ "layer", "spot", "card", "count", "title", "text", "back", "next", "steps" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root) return
    this._steps = Array.from(this.stepsTarget.content.children).map((s) => ({ ...s.dataset }))
    this._listeners = {
      // Not over a Go box that is already open (Quick Present opens on it):
      // the tour waits for the next time the console opens.
      "console:on": () => { if (!this._seen()) setTimeout(() => { if (!this._busy()) this.start() }, 400) },
      "console:off": () => this._hide(),
      "console:tour": () => this.start(),
      resize: () => { if (!this.layerTarget.hidden) this._place() }
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    this._onKey = (e) => this._key(e)
    // Something else needs the operator (the Go box, a slide tool, the keys
    // card): the tour steps aside and comes back another time.
    this._others = new MutationObserver(() => { if (!this.layerTarget.hidden && this._busy()) this._hide() })
    this.root.querySelectorAll(".ps-preach-jump, .ps-tool-dialog, .ps-preach-keys")
      .forEach((el) => this._others.observe(el, { attributes: true, attributeFilter: [ "hidden" ] }))
  }

  disconnect() {
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
    document.removeEventListener("keydown", this._onKey, true)
    this._others?.disconnect()
  }

  start() {
    if (!this.root.classList.contains("is-console") || this._busy()) return
    this._index = 0
    this.layerTarget.hidden = false
    document.addEventListener("keydown", this._onKey, true)
    this._paint()
  }

  next(event) {
    event?.preventDefault?.()
    if (this._index >= this._steps.length - 1) { this.finish(); return }
    this._index++
    this._paint()
  }

  back(event) {
    event?.preventDefault?.()
    if (this._index > 0) { this._index--; this._paint() }
  }

  finish(event) {
    event?.preventDefault?.()
    this._hide()
    try { localStorage.setItem(this._key_(), "1") } catch { /* private mode */ }
  }

  _hide() {
    this.layerTarget.hidden = true
    document.removeEventListener("keydown", this._onKey, true)
  }

  _key(event) {
    if (this.layerTarget.hidden) return
    const handled = { Escape: () => this.finish(), ArrowRight: () => this.next(), Enter: () => this.next(), ArrowLeft: () => this.back() }[event.key]
    // Every other key is swallowed too: nothing reaches the projector mid-tour.
    event.preventDefault()
    event.stopPropagation()
    handled?.()
  }

  _paint() {
    const step = this._steps[this._index]
    this.countTarget.textContent = `${this._index + 1} of ${this._steps.length}`
    this.titleTarget.textContent = step.title
    this.textTarget.textContent = step.text
    this.backTarget.hidden = this._index === 0
    this.nextTarget.textContent = this._index === this._steps.length - 1 ? "Got it" : "Next"
    this._place()
    this.nextTarget.focus({ preventScroll: true })
  }

  // Light up the region and put the card beside it, inside the window.
  _place() {
    const step = this._steps[this._index]
    const region = this.root.querySelector(`.cx [data-cx-region="${step.region}"]`)
    if (!region) return
    const r = region.getBoundingClientRect()
    const pad = 6
    Object.assign(this.spotTarget.style, {
      left: `${r.left - pad}px`, top: `${r.top - pad}px`, width: `${r.width + pad * 2}px`, height: `${r.height + pad * 2}px`
    })
    const card = this.cardTarget.getBoundingClientRect()
    const vw = window.innerWidth
    const vh = window.innerHeight
    let left = r.right + 18
    let top = r.top + 24
    if (left + card.width > vw - 12) left = r.left - card.width - 18 // left of it
    if (left < 12) { left = Math.min(Math.max(12, r.left + 24), vw - card.width - 12); top = r.top - card.height - 18 } // above
    if (top < 12) top = Math.min(r.bottom + 18, vh - card.height - 12)
    top = Math.max(12, Math.min(top, vh - card.height - 12))
    Object.assign(this.cardTarget.style, { left: `${Math.round(left)}px`, top: `${Math.round(top)}px` })
  }

  _busy() {
    return !!this.root.querySelector(".ps-preach-jump:not([hidden]), .ps-tool-dialog:not([hidden]), .ps-preach-keys:not([hidden])")
  }

  _seen() {
    try { return localStorage.getItem(this._key_()) === "1" } catch { return true }
  }

  _key_() {
    return KEY_PREFIX + (document.body?.dataset.offlineOwner || "guest")
  }
}
