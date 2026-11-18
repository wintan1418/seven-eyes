import { Controller } from "@hotwired/stimulus"

// Auto-scroll for silent reading. Tap the button to turn it on: a soft gold
// highlight moves verse by verse at a reading pace (timed by each verse's
// words) and the page scrolls gently to keep it a third of the way down.
// A small bar offers Slower / Faster / Stop; tapping the button again also
// stops. Scrolling by hand pauses it; it then carries on from what's on screen.
// It steps aside when the Audio Bible starts (that follows along itself).
const PACES = [
  { name: "Slow", wpm: 120 },
  { name: "Normal", wpm: 165 },
  { name: "Fast", wpm: 220 }
]
const KEY = "bibliorata:autoscroll-pace"

export default class extends Controller {
  static targets = [ "button", "bar", "pace" ]

  connect() {
    this.on = false
    try { this.pace = Math.min(Math.max(Number(localStorage.getItem(KEY) ?? 1), 0), PACES.length - 1) } catch { this.pace = 1 }
    if (!Number.isFinite(this.pace)) this.pace = 1
    this.onHand = () => { if (this.on) this.pauseForHand() }
    this.onListening = () => this.stop()
    this.onFrameRender = (e) => { if (e.target === this.element) this.stop() }
    this.element.addEventListener("turbo:frame-render", this.onFrameRender)
    window.addEventListener("reader:listening", this.onListening)
    this.render()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this.onFrameRender)
    window.removeEventListener("reader:listening", this.onListening)
    this.stop()
  }

  toggle() { this.on ? this.stop() : this.start() }

  slower() { this.setPace(this.pace - 1) }
  faster() { this.setPace(this.pace + 1) }

  setPace(i) {
    this.pace = Math.min(Math.max(i, 0), PACES.length - 1)
    try { localStorage.setItem(KEY, String(this.pace)) } catch {}
    this.render()
    if (this.on) this.schedule() // re-time the current verse
  }

  start() {
    this.verses = Array.from(this.element.querySelectorAll(".ps-verse")).filter((v) => v.querySelector(".ps-verse-text"))
    if (!this.verses.length) return
    this.on = true
    this.box = this.scrollBox()
    for (const t of [ this.box, window ]) {
      t.addEventListener("wheel", this.onHand, { passive: true })
      t.addEventListener("touchmove", this.onHand, { passive: true })
    }
    this.go(this.firstOnScreen())
    this.render()
  }

  stop() {
    if (!this.on && !this.timer) return this.render()
    this.on = false
    clearTimeout(this.timer); this.timer = null
    clearTimeout(this.handTimer); this.handTimer = null
    this.verses?.forEach((v) => v.classList.remove("is-pace"))
    for (const t of [ this.box, window ].filter(Boolean)) {
      t.removeEventListener("wheel", this.onHand)
      t.removeEventListener("touchmove", this.onHand)
    }
    this.render()
  }

  // Light verse i, bring it into view, and time the next step by its words.
  go(i) {
    if (!this.on) return
    if (i >= this.verses.length) return this.stop()
    this.verses[this.index]?.classList.remove("is-pace")
    this.index = i
    const v = this.verses[i]
    v.classList.add("is-pace")
    this.bringIntoView(v)
    this.schedule()
  }

  schedule() {
    clearTimeout(this.timer)
    const v = this.verses?.[this.index]
    if (!v) return
    const words = v.querySelector(".ps-verse-text").textContent.trim().split(/\s+/).length
    const ms = Math.max(2200, (words / PACES[this.pace].wpm) * 60000)
    this.timer = setTimeout(() => this.go(this.index + 1), ms)
  }

  pauseForHand() {
    clearTimeout(this.timer); this.timer = null
    clearTimeout(this.handTimer)
    this.handTimer = setTimeout(() => {
      if (!this.on) return
      const current = this.verses[this.index]
      // Carry on from what's on screen if they scrolled away.
      this.go(this.isOnScreen(current) ? this.index : this.firstOnScreen())
    }, 3000)
  }

  firstOnScreen() {
    const i = this.verses.findIndex((v) => this.isOnScreen(v))
    return i < 0 ? 0 : i
  }

  isOnScreen(el) {
    if (!el) return false
    const r = el.getBoundingClientRect()
    const top = this.box === window ? 0 : this.box.getBoundingClientRect().top
    const bottom = this.box === window ? window.innerHeight : this.box.getBoundingClientRect().bottom
    return r.bottom > top + 40 && r.top < bottom - 80
  }

  bringIntoView(el) {
    const r = el.getBoundingClientRect()
    if (this.box === window) {
      window.scrollTo({ top: Math.max(0, window.scrollY + r.top - window.innerHeight * 0.33), behavior: "smooth" })
    } else {
      const b = this.box.getBoundingClientRect()
      this.box.scrollTo({ top: Math.max(0, this.box.scrollTop + (r.top - b.top) - this.box.clientHeight * 0.33), behavior: "smooth" })
    }
  }

  render() {
    if (this.hasButtonTarget) {
      this.buttonTarget.classList.toggle("is-on", this.on)
      this.buttonTarget.setAttribute("aria-pressed", String(this.on))
      this.buttonTarget.title = this.on ? "Stop auto-scroll" : "Auto-scroll and highlight as you read"
    }
    if (this.hasBarTarget) this.barTarget.hidden = !this.on
    if (this.hasPaceTarget) this.paceTarget.textContent = PACES[this.pace].name
  }

  // The verses box on wide screens, the page on phones.
  scrollBox() {
    const box = this.element.querySelector(".ps-verses")
    if (box && box.scrollHeight > box.clientHeight + 4 && getComputedStyle(box).overflowY !== "visible") return box
    return window
  }
}
