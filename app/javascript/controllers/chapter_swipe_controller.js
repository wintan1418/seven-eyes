import { Controller } from "@hotwired/stimulus"

// Swipe left / right across the passage for the next / previous chapter
// (single-passage reading on touch). It clicks the pane's own chapter
// buttons, so it loads exactly like tapping them. Stands down while
// presenting or preaching (preach has its own swipes), in Compare, while
// words are selected, and when the gesture is mostly vertical (scrolling).
// Lives on .ps-workspace.
const MIN_DX = 70

export default class extends Controller {
  start(event) {
    if (event.touches.length !== 1 || this._ignored()) { this._from = null; return }
    const t = event.touches[0]
    this._from = { x: t.clientX, y: t.clientY, at: Date.now() }
  }

  end(event) {
    const from = this._from
    this._from = null
    if (!from || this._ignored()) return
    const t = event.changedTouches[0]
    const dx = t.clientX - from.x
    const dy = t.clientY - from.y
    if (Math.abs(dx) < MIN_DX || Math.abs(dx) < Math.abs(dy) * 1.8 || Date.now() - from.at > 700) return
    const pane = this.element.querySelector(".ps-pane")
    pane?.querySelector(`.rd-chapter-nav .rd-fab.${dx < 0 ? "next" : "prev"}`)?.click()
  }

  _ignored() {
    const root = this.element.closest(".ps-root")
    if (!root || root.matches(".is-presenting, .is-preaching, .is-output, .is-compare")) return true
    if (document.querySelector(".ui-sheet.is-open")) return true
    return !window.getSelection()?.isCollapsed
  }
}
