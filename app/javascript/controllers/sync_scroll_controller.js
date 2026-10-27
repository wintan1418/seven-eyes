import { Controller } from "@hotwired/stimulus"

// When sync-scroll is enabled, scrolling one pane's verses scrolls the others
// proportionally. Uses a capturing listener (scroll doesn't bubble) so it keeps
// working after panes are re-rendered by Turbo.
//
// Echo guard: setting a sibling's scrollTop fires a scroll event on it a frame
// later. A boolean "syncing" flag cleared on the next animation frame could be
// gone by then, so the echo re-propagated back to the source — jitter. Instead
// we remember exactly which elements we moved and swallow their next scroll.
export default class extends Controller {
  static values = { enabled: Boolean }

  connect() {
    this.echoes = new Set()
    this._onScroll = this.onScroll.bind(this)
    this.element.addEventListener("scroll", this._onScroll, true)
  }

  disconnect() {
    this.element.removeEventListener("scroll", this._onScroll, true)
    clearTimeout(this._clear)
    this.echoes.clear()
  }

  onScroll(event) {
    const src = event.target
    if (!src.classList || !src.classList.contains("ps-verses")) return
    if (this.echoes.has(src)) { this.echoes.delete(src); return }
    if (!this.enabledValue) return

    const srcMax = src.scrollHeight - src.clientHeight
    const ratio = srcMax > 0 ? src.scrollTop / srcMax : 0

    this.element.querySelectorAll(".ps-verses").forEach((el) => {
      if (el === src) return
      const max = el.scrollHeight - el.clientHeight
      const target = Math.round(ratio * max)
      // No movement → no scroll event → nothing to swallow.
      if (Math.abs(el.scrollTop - target) < 1) return
      this.echoes.add(el)
      el.scrollTop = target
    })
    // Safety net: an echo that never arrives (clamped, detached) mustn't
    // swallow the user's next real scroll.
    clearTimeout(this._clear)
    this._clear = setTimeout(() => this.echoes.clear(), 150)
  }
}
