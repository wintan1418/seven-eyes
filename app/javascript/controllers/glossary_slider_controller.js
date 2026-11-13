import { Controller } from "@hotwired/stimulus"

// The home page's glossary slider (phones): a row of word cards that snaps
// one card at a time. It moves on by itself every few seconds until the
// person touches it, and the dots follow whatever is in view.
// Reduced motion, a hidden tab or a laptop (where the slider is hidden): no
// automatic moving.
export default class extends Controller {
  static targets = [ "track", "slide", "dot" ]
  static values = { interval: { type: Number, default: 5000 } }

  connect() {
    this.index = 0
    this.onScroll = () => { cancelAnimationFrame(this.frame); this.frame = requestAnimationFrame(() => this.sync()) }
    this.stop = () => { this.stopped = true; this.pause() }
    this.trackTarget.addEventListener("scroll", this.onScroll, { passive: true })
    ;[ "pointerdown", "touchstart", "wheel", "keydown", "focusin" ].forEach(e =>
      this.trackTarget.addEventListener(e, this.stop, { passive: true }))
    this.onVisibility = () => (document.hidden ? this.pause() : this.play())
    document.addEventListener("visibilitychange", this.onVisibility)
    this.play()
  }

  disconnect() {
    this.pause()
    this.trackTarget.removeEventListener("scroll", this.onScroll)
    ;[ "pointerdown", "touchstart", "wheel", "keydown", "focusin" ].forEach(e =>
      this.trackTarget.removeEventListener(e, this.stop))
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  play() {
    this.pause()
    if (this.stopped || this.slideTargets.length < 2) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    if (this.trackTarget.offsetParent === null) return // hidden (laptop layout)
    this.timer = setInterval(() => {
      if (document.hidden) return
      this.show((this.index + 1) % this.slideTargets.length)
    }, this.intervalValue)
  }

  pause() {
    clearInterval(this.timer)
    this.timer = null
  }

  go(event) {
    this.stop()
    this.show(Number(event.currentTarget.dataset.index) || 0)
  }

  show(i) {
    const slide = this.slideTargets[i]
    if (!slide) return
    this.trackTarget.scrollTo({ left: slide.offsetLeft - this.padLeft(), behavior: "smooth" })
  }

  padLeft() {
    return parseFloat(getComputedStyle(this.trackTarget).scrollPaddingLeft) || 0
  }

  // Which card is in view → its dot.
  sync() {
    const left = this.trackTarget.scrollLeft + this.padLeft()
    let best = 0
    let bestGap = Infinity
    this.slideTargets.forEach((s, i) => {
      const gap = Math.abs(s.offsetLeft - left)
      if (gap < bestGap) { bestGap = gap; best = i }
    })
    this.index = best
    this.dotTargets.forEach((d, i) => d.classList.toggle("is-on", i === best))
  }
}
