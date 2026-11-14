import { Controller } from "@hotwired/stimulus"

// A slow drift on the Home painting as the page scrolls (it moves at a
// fraction of the scroll, so the picture seems to sit deeper than the words).
// Transform only, one write per frame; nothing with reduced motion.
const RATE = 0.28

export default class extends Controller {
  static targets = [ "scroller", "layer" ]

  connect() {
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return
    this._onScroll = () => {
      if (this._frame) return
      this._frame = requestAnimationFrame(() => {
        this._frame = null
        const y = this.scrollerTarget.scrollTop
        for (const layer of this.layerTargets) {
          if (y > layer.offsetHeight * 1.5) continue
          layer.style.transform = `translate3d(0, ${(y * RATE).toFixed(1)}px, 0)`
        }
      })
    }
    this.scrollerTarget.addEventListener("scroll", this._onScroll, { passive: true })
  }

  disconnect() {
    this.scrollerTarget?.removeEventListener("scroll", this._onScroll)
    cancelAnimationFrame(this._frame)
  }
}
