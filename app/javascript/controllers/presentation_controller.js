import { Controller } from "@hotwired/stimulus"

// Drives focus-pane presentation mode plus the iPad-friendly preach sub-mode.
//
// State classes layered on .ps-root:
//   .is-presenting  — focus mode: one pane fills the screen, chrome hidden.
//   .is-preaching   — preach sub-mode (inside focus): one verse at a time, big.
//   .is-parallel    — parallel sub-mode (inside preach): two panes side-by-side
//                     showing the same verse number in different translations.
//
// Esc unwinds one layer at a time: jump-input → preach → focus → workspace.
export default class extends Controller {
  static targets = ["jumpInput"]

  initialize() {
    this._preachIndex = 0
    this._groupSize = 1
  }

  // ----- focus mode (whole pane) -----

  enter(event) {
    const pane = event.target.closest(".ps-pane")
    if (!pane) return
    event.preventDefault?.()
    this.element.querySelectorAll(".ps-pane.is-presented, .ps-pane.is-paired")
        .forEach(p => p.classList.remove("is-presented", "is-paired"))
    pane.classList.add("is-presented")
    this.element.classList.add("is-presenting")
    this._bindEsc()
  }

  exit(event) {
    event?.preventDefault?.()
    if (this._jumpOpen) { this._closeJump(); return }
    if (this.element.classList.contains("is-preaching")) { this.exitPreach(); return }
    this.element.classList.remove("is-presenting", "is-parallel")
    this.element.querySelectorAll(".ps-pane.is-presented, .ps-pane.is-paired")
        .forEach(p => p.classList.remove("is-presented", "is-paired"))
    this._unbindEsc()
  }

  // ----- preach sub-mode (one verse at a time, tap/swipe/keys to advance) -----

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
    this.element.classList.remove("is-preaching", "is-parallel")
    this._closeJump()
    this._clear()
    this._unbindKeys()
    this._unbindSwipe()
    this._groupSize = 1
    this._syncGroupButtons()
    this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
  }

  next(event) {
    event?.preventDefault?.()
    const verses = this._primaryVerses()
    if (this._preachIndex + this._groupSize < verses.length) {
      this._preachIndex += this._groupSize
      this._paint()
    }
  }

  prev(event) {
    event?.preventDefault?.()
    if (this._preachIndex > 0) {
      this._preachIndex = Math.max(0, this._preachIndex - this._groupSize)
      this._paint()
    }
  }

  // ----- group / fusion: 1, 2, or 3 verses per slide -----

  setGroup(event) {
    event?.preventDefault?.()
    const n = parseInt(event.params?.size || event.currentTarget?.dataset?.groupParam || "1", 10)
    this._groupSize = Math.max(1, Math.min(5, n))
    this._syncGroupButtons()
    this._paint()
  }

  _syncGroupButtons() {
    this.element.querySelectorAll("[data-preach-group]").forEach(btn => {
      btn.classList.toggle("is-on", parseInt(btn.dataset.preachGroup, 10) === this._groupSize)
    })
  }

  // ----- parallel translations: pair the next pane with the same reference -----

  toggleParallel(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    const on = !this.element.classList.contains("is-parallel")
    this.element.classList.toggle("is-parallel", on)
    this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
    if (on) {
      const focused = this.element.querySelector(".ps-pane.is-presented")
      if (focused) {
        const focusedRef = this._refSignatureFor(focused)
        const candidates = Array.from(this.element.querySelectorAll(".ps-pane")).filter(p => p !== focused)
        const match = candidates.find(p => this._refSignatureFor(p) === focusedRef) || candidates[0]
        if (match) match.classList.add("is-paired")
      }
    }
    this._paint()
    this._syncParallelButton()
  }

  _syncParallelButton() {
    const btn = this.element.querySelector("[data-preach-parallel]")
    if (btn) btn.classList.toggle("is-on", this.element.classList.contains("is-parallel"))
  }

  _refSignatureFor(pane) {
    const verse = pane.querySelector(".ps-verse")
    if (!verse) return null
    return `${verse.dataset.osis}:${verse.dataset.chapter}`
  }

  // ----- jump-to-verse: press G, type a verse number, Enter -----

  openJump(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    if (!this.hasJumpInputTarget) return
    this._jumpOpen = true
    const wrapper = this.jumpInputTarget.closest(".ps-preach-jump")
    if (wrapper) wrapper.hidden = false
    this.jumpInputTarget.value = ""
    this.jumpInputTarget.focus()
  }

  jumpSubmit(event) {
    event?.preventDefault?.()
    const target = parseInt(this.jumpInputTarget.value, 10)
    this._closeJump()
    if (!Number.isFinite(target)) return
    const verses = this._primaryVerses()
    const idx = verses.findIndex(v => parseInt(v.dataset.verseNum, 10) === target)
    if (idx >= 0) {
      this._preachIndex = idx
      this._paint()
    }
  }

  cancelJump(event) {
    event?.preventDefault?.()
    this._closeJump()
  }

  _closeJump() {
    this._jumpOpen = false
    if (this.hasJumpInputTarget) {
      const wrapper = this.jumpInputTarget.closest(".ps-preach-jump")
      if (wrapper) wrapper.hidden = true
      this.jumpInputTarget.blur()
    }
  }

  // ----- lifecycle -----

  disconnect() {
    this._unbindEsc()
    this._unbindKeys()
    this._unbindSwipe()
  }

  // ----- internals -----

  _primaryVerses() {
    const pane = this.element.querySelector(".ps-pane.is-presented")
    return pane ? Array.from(pane.querySelectorAll(".ps-verse")) : []
  }

  _allActivePanes() {
    return Array.from(this.element.querySelectorAll(".ps-pane.is-presented, .ps-pane.is-paired"))
  }

  _paint() {
    const primary = this._primaryVerses()
    if (primary.length === 0) return
    this._preachIndex = Math.max(0, Math.min(this._preachIndex, primary.length - 1))
    const start = this._preachIndex
    const end = Math.min(primary.length, start + this._groupSize)

    // Track verse-numbers in the current group; mirror onto paired panes.
    const groupNumbers = new Set()
    for (let i = start; i < end; i++) {
      groupNumbers.add(parseInt(primary[i].dataset.verseNum, 10))
    }

    this._allActivePanes().forEach(pane => {
      pane.querySelectorAll(".ps-verse").forEach(v => {
        const num = parseInt(v.dataset.verseNum, 10)
        v.classList.toggle("is-preach-current", groupNumbers.has(num))
      })
    })

    const counter = this.element.querySelector("[data-preach-counter]")
    if (counter) {
      const last = Array.from(groupNumbers).sort((a, b) => a - b).pop()
      const first = Array.from(groupNumbers).sort((a, b) => a - b)[0]
      const range = first === last ? `${first}` : `${first}–${last}`
      counter.textContent = `verse ${range}`
    }
  }

  _clear() {
    this._allActivePanes().forEach(pane => {
      pane.querySelectorAll(".ps-verse").forEach(v => v.classList.remove("is-preach-current"))
    })
    this._preachIndex = 0
  }

  _bindEsc() {
    if (this._escHandler) return
    this._escHandler = (e) => {
      if (e.key === "Escape" && this.element.classList.contains("is-presenting")) this.exit()
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
      // While the jump input is open, let it own keystrokes.
      if (this._jumpOpen) return
      if (e.key === "ArrowRight" || e.key === " ") { e.preventDefault(); this.next() }
      else if (e.key === "ArrowLeft") { e.preventDefault(); this.prev() }
      else if (e.key === "g" || e.key === "G") { e.preventDefault(); this.openJump() }
      else if (e.key === "p" || e.key === "P") { e.preventDefault(); this.toggleParallel() }
      else if (e.key >= "1" && e.key <= "5") { e.preventDefault(); this._groupSize = parseInt(e.key, 10); this._syncGroupButtons(); this._paint() }
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
