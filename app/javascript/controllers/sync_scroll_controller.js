import { Controller } from "@hotwired/stimulus"

// When sync-scroll is enabled, scrolling one pane's verses scrolls the others
// proportionally. Uses a capturing listener (scroll doesn't bubble) so it keeps
// working after panes are re-rendered by Turbo.
export default class extends Controller {
  static values = { enabled: Boolean }

  connect() {
    this.syncing = false
    this._onScroll = this.onScroll.bind(this)
    this.element.addEventListener("scroll", this._onScroll, true)
  }

  disconnect() {
    this.element.removeEventListener("scroll", this._onScroll, true)
  }

  onScroll(event) {
    if (!this.enabledValue || this.syncing) return
    const src = event.target
    if (!src.classList || !src.classList.contains("ps-verses")) return

    const srcMax = src.scrollHeight - src.clientHeight
    const ratio = srcMax > 0 ? src.scrollTop / srcMax : 0

    this.syncing = true
    this.element.querySelectorAll(".ps-verses").forEach((el) => {
      if (el === src) return
      const max = el.scrollHeight - el.clientHeight
      el.scrollTop = ratio * max
    })
    requestAnimationFrame(() => { this.syncing = false })
  }
}
