import { Controller } from "@hotwired/stimulus"

// Drives focus-pane presentation mode plus the EasyWorship-style preach sub-mode.
//
// State classes layered on .ps-root:
//   .is-presenting  — focus mode: one pane fills the screen, chrome hidden.
//   .is-preaching   — preach sub-mode: one verse at a time, big, smooth fade.
//   .is-parallel    — two panes side-by-side showing the same verse number.
//
// Esc unwinds one layer at a time: jump-input → preach → focus → workspace.
//
// Transitions: _animate() fades the verse-body out (CSS opacity transition),
// swaps which verses are .is-preach-current, runs _autoFit() to shrink the font
// if the new verse(s) overflow the pane, then fades back in.
//
// Dual-screen projection (EasyWorship-style operator/output split):
//   "Project" opens this same study in a second window with ?output=1 — that
//   window renders ONLY the big verse (.is-output hides all chrome) and is
//   meant to be dragged fullscreen onto the projector. The two windows sync
//   over a BroadcastChannel: the operator broadcasts {pane, index, group,
//   parallel, reference, translation} on every paint; the output window is a
//   pure listener (it even reloads its pane's Turbo Frame if the operator
//   moves to a different passage). While an output is connected the operator
//   window becomes a console: .is-projecting shrinks the live verse and shows
//   a next-verse preview strip above the bottom bar.
const FADE_MS = 160
const AUTOFIT_MAX_ITERS = 24
const AUTOFIT_MIN_PX = 18

export default class extends Controller {
  static targets = ["jumpInput"]

  initialize() {
    this._preachIndex = 0
    this._groupSize = 1
  }

  connect() {
    const params = new URLSearchParams(window.location.search)
    this._isOutput = params.get("output") === "1"
    if ("BroadcastChannel" in window) {
      this._channel = new BroadcastChannel(`ps-preach:${window.location.pathname}`)
      this._channel.onmessage = (e) => this._onMessage(e.data)
    }
    if (this._isOutput) this._enterOutput(parseInt(params.get("pane") || "0", 10))
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

  // ----- preach sub-mode -----

  enterPreach(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-presenting")) return
    this.element.classList.add("is-preaching")
    this._preachIndex = 0
    this._paint()
    requestAnimationFrame(() => this._autoFit())
    this._bindKeys()
    this._bindSwipe()
  }

  exitPreach(event) {
    event?.preventDefault?.()
    if (!this._isOutput) {
      this._send({ type: "exit" }) // the output window closes itself
      this._setProjecting(false)
    }
    this.element.classList.remove("is-preaching", "is-parallel")
    this._closeJump()
    this._clear()
    this._clearAutoFit()
    this._unbindKeys()
    this._unbindSwipe()
    this._groupSize = 1
    this._syncGroupButtons()
    this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
  }

  next(event) {
    event?.preventDefault?.()
    const verses = this._primaryVerses()
    if (this._preachIndex + this._groupSize >= verses.length) return
    this._transition(() => { this._preachIndex += this._groupSize })
  }

  prev(event) {
    event?.preventDefault?.()
    if (this._preachIndex <= 0) return
    this._transition(() => { this._preachIndex = Math.max(0, this._preachIndex - this._groupSize) })
  }

  // ----- group / fusion -----

  setGroup(event) {
    event?.preventDefault?.()
    const n = parseInt(event.params?.size || event.currentTarget?.dataset?.preachGroup || "1", 10)
    this._groupSize = Math.max(1, Math.min(5, n))
    this._syncGroupButtons()
    this._transition(() => {})
  }

  _syncGroupButtons() {
    this.element.querySelectorAll("[data-preach-group]").forEach(btn => {
      btn.classList.toggle("is-on", parseInt(btn.dataset.preachGroup, 10) === this._groupSize)
    })
  }

  // ----- parallel translations -----

  toggleParallel(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    const on = !this.element.classList.contains("is-parallel")
    this.element.classList.toggle("is-parallel", on)
    this._pairForParallel()
    this._transition(() => {})
    this._syncParallelButton()
  }

  // Pick the pane shown beside the presented one: same book+chapter if any
  // sibling has it (a different translation), else the first other pane.
  _pairForParallel() {
    this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
    if (!this.element.classList.contains("is-parallel")) return
    const focused = this.element.querySelector(".ps-pane.is-presented")
    if (!focused) return
    const focusedRef = this._refSignatureFor(focused)
    const candidates = Array.from(this.element.querySelectorAll(".ps-pane")).filter(p => p !== focused)
    const match = candidates.find(p => this._refSignatureFor(p) === focusedRef) || candidates[0]
    if (match) match.classList.add("is-paired")
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

  // ----- jump-to-verse -----

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
    if (idx < 0) return
    this._transition(() => { this._preachIndex = idx })
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

  // ----- dual-screen projection -----

  // Operator: open the output window. Reusing the window name means clicking
  // Project again focuses the existing output instead of spawning another.
  openOutput(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    const pane = this.element.querySelector(".ps-pane.is-presented")
    const url = new URL(window.location.href)
    url.searchParams.set("output", "1")
    url.searchParams.set("pane", String(Math.max(0, this._workspacePanes().indexOf(pane))))
    this._outputWindow = window.open(url.toString(), "ps-preach-output", "popup=yes,width=1280,height=720")
  }

  // Output window: browsers only allow fullscreen from a user gesture, so the
  // output shows a discreet button instead of going fullscreen on load.
  toggleFullscreen(event) {
    event?.preventDefault?.()
    if (document.fullscreenElement) document.exitFullscreen?.()
    else document.documentElement.requestFullscreen?.()
  }

  // Output window boot: display-only — no key/swipe/esc bindings; navigation
  // arrives exclusively as state messages from the operator.
  _enterOutput(paneIndex) {
    this.element.classList.add("is-output")
    const panes = this._workspacePanes()
    const pane = panes[paneIndex] || panes[0]
    if (!pane) return
    panes.forEach(p => p.classList.remove("is-presented", "is-paired"))
    pane.classList.add("is-presented")
    this.element.classList.add("is-presenting", "is-preaching")
    this._paint()
    requestAnimationFrame(() => this._autoFit())
    window.addEventListener("pagehide", () => this._send({ type: "bye" }))
    this._send({ type: "hello" })
  }

  _onMessage(msg) {
    if (!msg || !msg.type) return
    if (this._isOutput) {
      if (msg.type === "state") this._applyState(msg)
      else if (msg.type === "exit") window.close()
    } else {
      if (msg.type === "hello") { this._setProjecting(true); this._broadcast() }
      else if (msg.type === "bye") this._setProjecting(false)
    }
  }

  // Output window: mirror the operator's state. If a state lands mid-fade we
  // park it in _afterFade (applied when the fade ends) so rapid Next-Next from
  // the operator can't desync the two windows.
  _applyState(msg) {
    if (this._fading) { this._afterFade = msg; return }
    const panes = this._workspacePanes()
    const pane = panes[msg.pane] || panes[0]
    if (!pane) return
    if (!pane.classList.contains("is-presented")) {
      panes.forEach(p => p.classList.remove("is-presented", "is-paired"))
      pane.classList.add("is-presented")
    }

    // Operator moved to a different passage/translation: reload our copy of
    // the pane through its own form (Turbo Frame), then re-apply the state.
    const refInput = pane.querySelector("input[name='pane[reference]']")
    const transSelect = pane.querySelector("select[name='pane[translation_id]']")
    const sameRef = !msg.reference || !refInput ||
        refInput.value.trim().toLowerCase() === msg.reference.trim().toLowerCase()
    const sameTrans = !msg.translation || !transSelect || transSelect.value === String(msg.translation)
    if (!(sameRef && sameTrans)) {
      this._afterFade = null
      if (refInput) refInput.value = msg.reference
      if (transSelect && msg.translation) transSelect.value = String(msg.translation)
      pane.addEventListener("turbo:frame-load", () => {
        this._applyState({ ...msg, reference: null, translation: null })
      }, { once: true })
      refInput?.form?.requestSubmit()
      return
    }

    this._groupSize = Math.max(1, Math.min(5, msg.group || 1))
    this.element.classList.toggle("is-parallel", !!msg.parallel)
    this._pairForParallel()
    this._transition(() => { this._preachIndex = msg.index || 0 })
  }

  _broadcast() {
    if (!this._channel || this._isOutput) return
    if (!this.element.classList.contains("is-preaching")) return
    const pane = this.element.querySelector(".ps-pane.is-presented")
    if (!pane) return
    this._send({
      type: "state",
      pane: Math.max(0, this._workspacePanes().indexOf(pane)),
      index: this._preachIndex,
      group: this._groupSize,
      parallel: this.element.classList.contains("is-parallel"),
      reference: pane.querySelector("input[name='pane[reference]']")?.value || null,
      translation: pane.querySelector("select[name='pane[translation_id]']")?.value || null
    })
  }

  _send(msg) {
    try { this._channel?.postMessage(msg) } catch { /* channel closed */ }
  }

  _setProjecting(on) {
    this.element.classList.toggle("is-projecting", on)
    const btn = this.element.querySelector("[data-preach-project]")
    if (btn) btn.classList.toggle("is-on", on)
    // The console layout resizes the live verse area — refit the font.
    requestAnimationFrame(() => this._autoFit())
  }

  _workspacePanes() {
    return Array.from(this.element.querySelectorAll(".ps-workspace .ps-pane"))
  }

  // ----- lifecycle -----

  disconnect() {
    if (this._isOutput) this._send({ type: "bye" })
    this._channel?.close()
    this._channel = null
    this._unbindEsc()
    this._unbindKeys()
    this._unbindSwipe()
  }

  // ----- internals: rendering, transitions, auto-fit -----

  _transition(mutate) {
    if (this._fading) return // ignore rapid taps mid-fade
    const bodies = this._activeBodies()
    if (bodies.length === 0) { mutate(); this._paint(); return }
    this._fading = true
    bodies.forEach(b => b.classList.add("is-changing"))
    setTimeout(() => {
      mutate()
      this._paint()
      requestAnimationFrame(() => {
        this._autoFit()
        bodies.forEach(b => b.classList.remove("is-changing"))
        this._fading = false
        if (this._afterFade) { // output window: state that arrived mid-fade
          const queued = this._afterFade
          this._afterFade = null
          this._applyState(queued)
        }
      })
    }, FADE_MS)
  }

  _activeBodies() {
    return this._allActivePanes()
        .map(p => p.querySelector(".ps-verse-body"))
        .filter(Boolean)
  }

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

    const sorted = Array.from(groupNumbers).sort((a, b) => a - b)
    const first = sorted[0]
    const last = sorted[sorted.length - 1]
    const total = primary.length > 0 ? parseInt(primary[primary.length - 1].dataset.verseNum, 10) : 0
    const counter = this.element.querySelector("[data-preach-counter]")
    if (counter) {
      const range = first === last ? `${first}` : `${first}–${last}`
      counter.innerHTML = `<span class="num">verse ${range}</span><span class="of">of ${total}</span>`
    }

    this._paintNextPreview(primary, end)
    this._broadcast()
  }

  // Operator console: preview of what the NEXT advance will put on the screen.
  _paintNextPreview(primary, end) {
    const box = this.element.querySelector("[data-preach-next]")
    if (!box || this._isOutput) return
    if (end >= primary.length) {
      box.innerHTML = `<span class="lbl">Next</span><span class="txt end">— end of chapter —</span>`
      return
    }
    const upcoming = primary.slice(end, Math.min(primary.length, end + this._groupSize))
    const nums = upcoming.map(v => v.dataset.verseNum)
    const label = nums.length > 1 ? `v${nums[0]}–${nums[nums.length - 1]}` : `v${nums[0]}`
    const text = upcoming.map(v =>
      Array.from(v.querySelectorAll(".ps-verse-text")).map(t => t.textContent).join("")
    ).join("  ").trim()
    box.innerHTML = `<span class="lbl">Next · ${label}</span><span class="txt"></span>`
    box.querySelector(".txt").textContent = text.length > 240 ? `${text.slice(0, 240)}…` : text
  }

  // Iteratively shrink font-size of the active verse(s) until the content fits
  // the .ps-verses container without scrolling. Resets between calls so a short
  // verse after a long one grows back to the natural CSS clamp size.
  _autoFit() {
    this._allActivePanes().forEach(pane => {
      const container = pane.querySelector(".ps-verses")
      const currents = pane.querySelectorAll(".ps-verse.is-preach-current")
      if (!container || currents.length === 0) return

      currents.forEach(v => v.style.fontSize = "")
      if (container.scrollHeight <= container.clientHeight + 1) return

      let fs = parseFloat(getComputedStyle(currents[0]).fontSize) || 64
      let iters = AUTOFIT_MAX_ITERS
      while (container.scrollHeight > container.clientHeight + 1 && iters > 0 && fs > AUTOFIT_MIN_PX) {
        fs *= 0.92
        currents.forEach(v => v.style.fontSize = `${fs}px`)
        iters--
      }
    })
  }

  _clearAutoFit() {
    this.element.querySelectorAll(".ps-verse[style*='font-size']").forEach(v => v.style.fontSize = "")
  }

  _clear() {
    this._allActivePanes().forEach(pane => {
      pane.querySelectorAll(".ps-verse").forEach(v => v.classList.remove("is-preach-current"))
    })
    this._preachIndex = 0
  }

  // ----- input bindings -----

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
      if (this._jumpOpen) return
      if (e.key === "ArrowRight" || e.key === " " || e.key === "PageDown") { e.preventDefault(); this.next() }
      else if (e.key === "ArrowLeft" || e.key === "PageUp") { e.preventDefault(); this.prev() }
      else if (e.key === "Home") { e.preventDefault(); this._transition(() => { this._preachIndex = 0 }) }
      else if (e.key === "g" || e.key === "G") { e.preventDefault(); this.openJump() }
      else if (e.key === "p" || e.key === "P") { e.preventDefault(); this.toggleParallel() }
      else if (e.key >= "1" && e.key <= "5") {
        e.preventDefault()
        this._groupSize = parseInt(e.key, 10)
        this._syncGroupButtons()
        this._transition(() => {})
      }
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
