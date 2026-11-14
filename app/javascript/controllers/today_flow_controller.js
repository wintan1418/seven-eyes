import { Controller } from "@hotwired/stimulus"
import { owner } from "../lib/offline/page"
import { queueRecordSave, flushOutbox } from "../lib/offline/outbox"
import { lagosDate, markDone, saveStep, stepFor, todayStatus } from "../lib/today_state"

// Today — the guided daily flow (today_flows/show). The steps sit side by
// side in a scroll-snap track, so a swipe moves one step and so do Next /
// Back, the arrow keys and the progress segments; where the reader is gets
// saved on the device (Home offers "Pick up where you paused").
//
// Amen marks today done: on the device at once (lib/today_state.js), then for
// a signed-in reader PUT /today/:date/done — or, with no signal, through the
// outbox, which replays it when the network is back. Then the seal: the
// streak ring fills and a gold light rises (no motion with reduced motion).
const STREAK_GOAL = 7

export default class extends Controller {
  static targets = [ "track", "step", "seg", "count", "prev", "next", "nextLabel", "amen", "ask", "done", "ring", "streak", "streakText", "amenButton" ]
  static values = { date: String, signedIn: Boolean, dates: Array }

  connect() {
    this.index = 0
    this.today = lagosDate()
    this.reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    this._onScroll = () => {
      cancelAnimationFrame(this._frame)
      this._frame = requestAnimationFrame(() => this.sync())
    }
    this.trackTarget.addEventListener("scroll", this._onScroll, { passive: true })

    const status = todayStatus({ owner: owner(), serverDates: this.datesValue, today: this.today })
    if (status.done) {
      this.showDone(status.streak, { animate: false })
      this.go(this.stepTargets.length - 1, { instant: true })
    } else {
      const saved = stepFor(owner(), this.today)
      if (saved && saved.index > 0) this.go(Math.min(saved.index, this.stepTargets.length - 1), { instant: true })
    }
    this.paint()
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this._onScroll)
    cancelAnimationFrame(this._frame)
    clearTimeout(this._targetTimer)
  }

  next() {
    if (this.index >= this.stepTargets.length - 1) return
    this.go(this.index + 1)
  }

  prev() {
    if (this.index > 0) this.go(this.index - 1)
  }

  jump(event) {
    this.go(Number(event.currentTarget.dataset.index) || 0)
  }

  key(event) {
    if (event.defaultPrevented || event.altKey || event.metaKey || event.ctrlKey) return
    if (event.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.prev() }
  }

  go(index, { instant = false } = {}) {
    const step = this.stepTargets[index]
    if (!step) return
    this.index = index
    // While the track glides there, its scroll events aren't the reader swiping.
    this._target = index
    clearTimeout(this._targetTimer)
    this._targetTimer = setTimeout(() => { this._target = null }, 900)
    this.trackTarget.scrollTo({ left: step.offsetLeft, behavior: instant || this.reduced ? "auto" : "smooth" })
    step.scrollTop = 0
    this.paint()
    this.remember()
  }

  // A swipe settled on a step.
  sync() {
    if (!this.element.isConnected) return
    const width = this.trackTarget.clientWidth || 1
    const index = Math.round(this.trackTarget.scrollLeft / width)
    if (this._target != null) {
      if (index === this._target) this._target = null
      return
    }
    if (index === this.index || !this.stepTargets[index]) return
    this.index = index
    this.paint()
    this.remember()
  }

  paint() {
    const total = this.stepTargets.length
    this.segTargets.forEach((seg, i) => {
      seg.classList.toggle("is-on", i <= this.index)
      seg.querySelector("button")?.setAttribute("aria-current", i === this.index ? "step" : "false")
    })
    this.stepTargets.forEach((step, i) => {
      step.setAttribute("aria-hidden", i === this.index ? "false" : "true")
      step.inert = i !== this.index
    })
    if (this.hasCountTarget) this.countTarget.textContent = `${this.index + 1} of ${total}`
    if (this.hasPrevTarget) this.prevTarget.disabled = this.index === 0
    const last = this.index >= total - 1
    if (this.hasNextTarget) this.nextTarget.hidden = last
    if (this.hasNextLabelTarget) this.nextLabelTarget.textContent = this.index === total - 2 ? "Finish" : "Next"
    this.element.dataset.step = this.stepTargets[this.index]?.dataset.step || ""
  }

  remember() {
    if (this.element.classList.contains("is-complete")) return
    saveStep(owner(), this.today, this.index, this.stepTargets.length)
  }

  async amen() {
    if (this.element.classList.contains("is-complete")) return
    const date = this.today
    markDone(owner(), date)
    const status = todayStatus({ owner: owner(), serverDates: this.datesValue, today: date })
    this.showDone(status.streak, { animate: !this.reduced })
    if (this.signedInValue) this.send(date)
  }

  // Signed in: tell the server; with no signal (or a failure) the outbox
  // keeps it and replays it later.
  async send(date) {
    const url = `/today/${date}/done`
    try {
      if (navigator.onLine === false) throw new Error("offline")
      const token = document.querySelector('meta[name="csrf-token"]')?.content || ""
      const res = await fetch(url, { method: "PUT", headers: { "X-CSRF-Token": token, Accept: "application/json" }, credentials: "same-origin" })
      if (res.status >= 500 || res.status === 429 || res.redirected) throw new Error("later")
    } catch {
      try {
        await queueRecordSave("today-done", url, {}, owner())
        flushOutbox().catch(() => {})
      } catch { /* no IndexedDB: the device copy still has it */ }
    }
  }

  showDone(streak, { animate }) {
    this.element.classList.add("is-complete")
    if (animate) this.element.classList.add("is-celebrating")
    this.askTarget.hidden = true
    this.doneTarget.hidden = false
    this.streakTarget.textContent = streak
    this.streakTextTarget.textContent = streak === 1
      ? "Day one. Come back tomorrow to begin a streak."
      : `${streak} days in a row.`
    const fill = Math.min(streak, STREAK_GOAL) / STREAK_GOAL * 100
    const ring = this.ringTarget
    if (animate) {
      ring.style.strokeDashoffset = "100"
      requestAnimationFrame(() => requestAnimationFrame(() => { ring.style.strokeDashoffset = String(100 - fill) }))
    } else {
      ring.style.strokeDashoffset = String(100 - fill)
    }
    if (animate) this.doneTarget.focus({ preventScroll: true })
  }
}
