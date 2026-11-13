import { Controller } from "@hotwired/stimulus"
import { shatter } from "../lib/shatter"

// A row of cards that snaps one card at a time — the glossary words and the
// readers' testimonials. Every few seconds the card on screen breaks like
// glass to reveal the next (lib/shatter), until the person touches it; a dot
// does the same. Swiping scrolls as usual, and the dots follow what's in
// view. Reduced motion, a hidden tab or a hidden slider: no automatic moving.
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
      this.show((this.index + 1) % this.slideTargets.length, { glass: true })
    }, this.intervalValue)
  }

  pause() {
    clearInterval(this.timer)
    this.timer = null
  }

  go(event) {
    this.stop()
    this.show(Number(event.currentTarget.dataset.index) || 0, { glass: true })
  }

  show(i, { glass = false } = {}) {
    const slide = this.slideTargets[i]
    if (!slide || this.breaking) return
    const left = slide.offsetLeft - this.padLeft()
    if (!glass || Math.abs(left - this.trackTarget.scrollLeft) < 2) {
      this.trackTarget.scrollTo({ left, behavior: "smooth" })
      return
    }
    this.breaking = true
    shatter(this.trackTarget, () => this.trackTarget.scrollTo({ left, behavior: "instant" }))
      .finally(() => { this.breaking = false })
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
