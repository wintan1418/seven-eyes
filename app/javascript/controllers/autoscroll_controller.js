import { Controller } from "@hotwired/stimulus"

// Auto-scroll for silent reading: the chapter moves up slowly so you can read
// without scrolling. Tap the button to cycle Slow → Medium → Fast → off.
// Touching or scrolling the page pauses it for a moment; it stops at the end
// of the chapter, and while the Audio Bible is reading (that follows along).
const SPEEDS = [
  { name: "Slow", pxPerSecond: 16 },
  { name: "Medium", pxPerSecond: 26 },
  { name: "Fast", pxPerSecond: 40 }
]
const KEY = "bibliorata:autoscroll-speed"

export default class extends Controller {
  static targets = [ "button", "speed" ]

  connect() {
    this.level = -1
    this.onHand = () => { this.handAt = performance.now() }
    this.onFrameRender = (e) => { if (e.target === this.element) this.off() }
    this.element.addEventListener("turbo:frame-render", this.onFrameRender)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this.onFrameRender)
    this.off()
  }

  cycle() {
    if (this.level === -1) {
      let saved = 0
      try { saved = Number(localStorage.getItem(KEY) || 0) } catch {}
      this.level = Math.min(Math.max(saved, 0), SPEEDS.length - 1)
    } else if (this.level < SPEEDS.length - 1) {
      this.level += 1
    } else {
      return this.off()
    }
    try { localStorage.setItem(KEY, String(this.level)) } catch {}
    this.render()
    this.run()
  }

  run() {
    if (this.frame) return
    this.box = this.scrollBox()
    for (const t of [ this.box, window ]) {
      t.addEventListener("wheel", this.onHand, { passive: true })
      t.addEventListener("touchstart", this.onHand, { passive: true })
      t.addEventListener("touchmove", this.onHand, { passive: true })
    }
    this.handAt = 0
    this.carry = 0
    let last = performance.now()
    const step = (now) => {
      const dt = Math.min(now - last, 100) / 1000
      last = now
      const reading = this.element.querySelector(".ps-verse.is-reading")
      if (this.level >= 0 && !reading && now - this.handAt > 2500) {
        // Whole pixels only: fractional scrollTop is dropped on some phones.
        this.carry += SPEEDS[this.level].pxPerSecond * dt
        const px = Math.floor(this.carry)
        if (px >= 1) {
          this.carry -= px
          if (this.atEnd()) return this.off()
          if (this.box === window) window.scrollBy(0, px)
          else this.box.scrollTop += px
        }
      }
      this.frame = requestAnimationFrame(step)
    }
    this.frame = requestAnimationFrame(step)
  }

  off() {
    this.level = -1
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    for (const t of [ this.box, window ].filter(Boolean)) {
      t.removeEventListener("wheel", this.onHand)
      t.removeEventListener("touchstart", this.onHand)
      t.removeEventListener("touchmove", this.onHand)
    }
    this.render()
  }

  atEnd() {
    if (this.box === window) {
      return window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2
    }
    return this.box.scrollTop + this.box.clientHeight >= this.box.scrollHeight - 2
  }

  render() {
    if (!this.hasButtonTarget) return
    const on = this.level >= 0
    this.buttonTarget.classList.toggle("is-on", on)
    this.buttonTarget.setAttribute("aria-pressed", String(on))
    const name = on ? SPEEDS[this.level].name : ""
    if (this.hasSpeedTarget) this.speedTarget.textContent = name
    this.buttonTarget.title = on ? `Auto-scroll: ${name} (tap for ${this.level < SPEEDS.length - 1 ? SPEEDS[this.level + 1].name : "off"})` : "Auto-scroll while you read"
  }

  // Same rule as the reader: the verses box on wide screens, the page on phones.
  scrollBox() {
    const box = this.element.querySelector(".ps-verses")
    if (box && box.scrollHeight > box.clientHeight + 4 && getComputedStyle(box).overflowY !== "visible") return box
    return window
  }
}
