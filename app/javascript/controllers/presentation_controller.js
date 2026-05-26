import { Controller } from "@hotwired/stimulus"

// Drives focus-pane presentation mode and the iPad-friendly preach sub-mode.
//
// States layered on .ps-root:
//   .is-presenting  — focus mode: one pane fills the screen, everything else hidden.
//   .is-preaching   — preach sub-mode (inside focus): one verse at a time, big and centered.
//
// Esc exits one layer at a time: preach → focus → workspace.
export default class extends Controller {
  enter(event) {
    const pane = event.target.closest(".ps-pane")
    if (!pane) return
    event.preventDefault?.()
    this.element.querySelectorAll(".ps-pane.is-presented").forEach(p => p.classList.remove("is-presented"))
    pane.classList.add("is-presented")
    this.element.classList.add("is-presenting")
    this._bindEsc()
  }

  exit(event) {
    event?.preventDefault?.()
    if (this.element.classList.contains("is-preaching")) {
      this.exitPreach()
      return
    }
    this.element.classList.remove("is-presenting")
    this.element.querySelectorAll(".ps-pane.is-presented").forEach(p => p.classList.remove("is-presented"))
    this._unbindEsc()
  }

  enterPreach(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-presenting")) return
    this.element.classList.add("is-preaching")
    this._preachIndex = 0
    this._paint()
    this._bindKeys()
    this._bindSwipe()
  }

  exitPreach(event) {
    event?.preventDefault?.()
    this.element.classList.remove("is-preaching")
    this._clear()
    this._unbindKeys()
    this._unbindSwipe()
  }

  next(event) {
    event?.preventDefault?.()
    const verses = this._verses()
    if (this._preachIndex < verses.length - 1) {
      this._preachIndex++
      this._paint()
    }
  }

  prev(event) {
    event?.preventDefault?.()
    if (this._preachIndex > 0) {
      this._preachIndex--
      this._paint()
    }
  }

  disconnect() {
    this._unbindEsc()
    this._unbindKeys()
    this._unbindSwipe()
  }

  // ----- internals -----

  _verses() {
    const pane = this.element.querySelector(".ps-pane.is-presented")
    return pane ? Array.from(pane.querySelectorAll(".ps-verse")) : []
  }

  _paint() {
    const verses = this._verses()
    if (verses.length === 0) return
    this._preachIndex = Math.max(0, Math.min(this._preachIndex, verses.length - 1))
    verses.forEach((v, i) => v.classList.toggle("is-preach-current", i === this._preachIndex))
    const counter = this.element.querySelector("[data-preach-counter]")
    if (counter) counter.textContent = `${this._preachIndex + 1} / ${verses.length}`
  }

  _clear() {
    this._verses().forEach(v => v.classList.remove("is-preach-current"))
    this._preachIndex = 0
  }

  _bindEsc() {
    if (this._escHandler) return
    this._escHandler = (e) => {
      if (e.key === "Escape" && this.element.classList.contains("is-presenting")) {
        this.exit()
      }
    }
    document.addEventListener("keydown", this._escHandler)
  }

  _unbindEsc() {
    if (!this._escHandler) return
    document.removeEventListener("keydown", this._escHandler)
    this._escHandler = null
  }

  _bindKeys() {
    if (this._keyHandler) return
    this._keyHandler = (e) => {
      if (!this.element.classList.contains("is-preaching")) return
      if (e.key === "ArrowRight" || e.key === " ") { e.preventDefault(); this.next() }
      else if (e.key === "ArrowLeft") { e.preventDefault(); this.prev() }
    }
    document.addEventListener("keydown", this._keyHandler)
  }

  _unbindKeys() {
    if (!this._keyHandler) return
    document.removeEventListener("keydown", this._keyHandler)
    this._keyHandler = null
  }

  _bindSwipe() {
    if (this._touchStartHandler) return
    let start = null
    this._touchStartHandler = (e) => {
      if (!this.element.classList.contains("is-preaching")) return
      start = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now() }
    }
    this._touchEndHandler = (e) => {
      if (!start) return
      const dx = e.changedTouches[0].clientX - start.x
      const dy = e.changedTouches[0].clientY - start.y
      const dt = Date.now() - start.t
      start = null
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5 && dt < 600) {
        dx < 0 ? this.next() : this.prev()
      }
    }
    document.addEventListener("touchstart", this._touchStartHandler, { passive: true })
    document.addEventListener("touchend", this._touchEndHandler, { passive: true })
  }

  _unbindSwipe() {
    if (this._touchStartHandler) {
      document.removeEventListener("touchstart", this._touchStartHandler)
      this._touchStartHandler = null
    }
    if (this._touchEndHandler) {
      document.removeEventListener("touchend", this._touchEndHandler)
      this._touchEndHandler = null
    }
  }
}
