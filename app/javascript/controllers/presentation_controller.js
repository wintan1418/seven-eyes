import { Controller } from "@hotwired/stimulus"

// Drives focus-pane presentation mode plus the EasyWorship-style preach sub-mode.
//
// State classes layered on .ps-root:
//   .is-presenting  — focus mode: one pane fills the screen, chrome hidden.
//   .is-preaching   — preach sub-mode: one verse at a time, big, smooth fade.
//   .is-parallel    — two panes side-by-side showing the same verse number.
//   .is-split       — up to four panes side-by-side, each showing a DIFFERENT
//                     passage at its own verse. One region is "active"
//                     (.is-presented); Next/Prev/Go step only the active region.
//                     Frozen regions carry .is-paired (so they reuse the same
//                     big-verse styling). split-2/3/4 set the grid.
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
const SCREEN_PREFS_KEY = "ps-screen-prefs"

export default class extends Controller {
  static targets = ["jumpInput"]
  static values = { quickFindUrl: String }

  initialize() {
    this._preachIndex = 0
    this._groupSize = 1
    this._slide = null // {title, body, stanzas, index} while a song/thought is projected
    this._history = [] // where we were before each chase/queue/AI jump — for ⟲ Back
    this._blank = false // projector held on a calm blank screen (between segments)
    this._anchor = null // pinned "teaching text" — {reference, index} — for ⌂ Home
    this._emphasis = {} // verse number → emphasised word indices, for the minister's key point
    this._emphArmed = false // operator is arming emphasis: current verse words become clickable
    this._splitIndices = new Map() // split mode: pane element → its own current verse index
    this._join = null // {qr, code, url} while the Go-Live join card is on the projector
  }

  connect() {
    const params = new URLSearchParams(window.location.search)
    this._isStage = params.get("stage") === "1"
    this._isOutput = params.get("output") === "1" || this._isStage
    if ("BroadcastChannel" in window) {
      this._channel = new BroadcastChannel(`ps-preach:${window.location.pathname}`)
      this._channel.onmessage = (e) => this._onMessage(e.data)
    }
    if (this._isOutput) {
      this._enterOutput(parseInt(params.get("pane") || "0", 10))
    } else {
      // Operator: queue items and phone-remote commands arrive as window events.
      this._onSetlist = (e) => this.presentItem(e.detail)
      this._onCommand = (e) => this._runCommand(e.detail)
      this._onJoin = (e) => this._showJoin(e.detail)
      window.addEventListener("setlist:present", this._onSetlist)
      window.addEventListener("preach:command", this._onCommand)
      window.addEventListener("preach:join", this._onJoin)
      this._screen = this._loadScreenPrefs()
    }
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
    if (this._findsOpen) { this._closeFinds(); return }
    if (this._jumpOpen) { this._closeJump(); return }
    if (this._slide) { this._clearSlide(); return }
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
      // The live controller ends any congregation session.
      window.dispatchEvent(new CustomEvent("preach:exit"))
    }
    this._exitSplit({ repaint: false })
    this.element.classList.remove("is-preaching", "is-parallel")
    this._closeJump()
    this._closeFinds()
    this._clearSlide({ repaint: false })
    this._unwrapAll()
    this.element.classList.remove("is-emphasising")
    this._unbindEmphasisClicks()
    this._clear()
    this._clearAutoFit()
    this._unbindKeys()
    this._unbindSwipe()
    this._groupSize = 1
    this._history = []
    this._blank = false
    this._anchor = null
    this._emphasis = {}
    this._emphArmed = false
    if (this._join) this._showJoin(null)
    this._applyBlank()
    this._syncBackButton()
    this._syncAnchorButtons()
    this._syncEmphasisButton()
    this._syncGroupButtons()
    this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
  }

  next(event) {
    event?.preventDefault?.()
    if (this._slide) { this._stepSlide(+1); return }
    if (this._isSplit()) { this._stepActiveRegion(+1); return }
    const verses = this._primaryVerses()
    if (this._preachIndex + this._groupSize >= verses.length) return
    this._transition(() => { this._preachIndex += this._groupSize })
  }

  prev(event) {
    event?.preventDefault?.()
    if (this._slide) { this._stepSlide(-1); return }
    if (this._isSplit()) { this._stepActiveRegion(-1); return }
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
    if (this._isSplit()) this._exitSplit({ repaint: false }) // the two modes are exclusive
    const on = !this.element.classList.contains("is-parallel")
    this.element.classList.toggle("is-parallel", on)
    this._pairForParallel()
    this._transition(() => {})
    this._syncParallelButton()
  }

  // Pick the pane shown beside the presented one: same book+chapter if any
  // sibling has it (a different translation), else the first other pane.
  _pairForParallel() {
    if (this._isSplit()) return // split owns the .is-paired marks; never repair them
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

  // ----- split projection: different passages side-by-side -----
  // The big screen is divided into up to four regions, each holding its OWN
  // reference at its OWN verse. One region is "active" (the operator's focus);
  // Next/Prev/Go/the tap-zones step only that region. Click (or press 1–4) to
  // switch which region is active. Frozen regions carry .is-paired so they reuse
  // the existing big-verse styling; the active region keeps .is-presented.

  _isSplit() { return this.element.classList.contains("is-split") }

  // Workspace panes that actually have a passage loaded — the candidate regions.
  _splitRegions() {
    return this._workspacePanes().filter(p => p.querySelector(".ps-verse"))
  }

  toggleSplit(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    if (this._isSplit()) { this._exitSplit(); this._broadcast(); return }
    const regions = this._splitRegions()
    if (regions.length < 2) {
      alert("Split needs at least two panes with a passage loaded.\n\nBefore entering Preach mode, set up 2–4 panes (top-right pane count) and load a different scripture in each, then press Split.")
      return
    }
    this.element.classList.remove("is-parallel")
    this._syncParallelButton()
    this.element.classList.add("is-split")
    this._setSplitGridClass(regions.length)
    this._groupSize = 1 // each region steps one verse at a time in split
    this._syncGroupButtons()
    // The pane already presented stays active; the rest become frozen regions.
    const active = this.element.querySelector(".ps-pane.is-presented") || regions[0]
    this._splitIndices = new Map()
    regions.forEach(pane => {
      this._splitIndices.set(pane, pane === active ? this._preachIndex : 0)
      pane.classList.toggle("is-presented", pane === active)
      pane.classList.toggle("is-paired", pane !== active)
    })
    this._bindRegionClicks()
    this._paintSplit()
    requestAnimationFrame(() => this._autoFit())
    this._syncSplitButton()
  }

  _exitSplit({ repaint = true } = {}) {
    if (!this._isSplit()) return
    this._unbindRegionClicks()
    const active = this.element.querySelector(".ps-pane.is-presented")
    this._preachIndex = active ? this._splitIndexFor(active) : 0
    this.element.classList.remove("is-split", "split-2", "split-3", "split-4")
    this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
    this._splitIndices = new Map()
    this._syncSplitButton()
    if (repaint && this.element.classList.contains("is-preaching")) {
      this._paint()
      requestAnimationFrame(() => this._autoFit())
    }
  }

  _setSplitGridClass(count) {
    const n = Math.max(2, Math.min(4, count))
    ;["split-2", "split-3", "split-4"].forEach(c => this.element.classList.remove(c))
    this.element.classList.add(`split-${n}`)
  }

  _syncSplitButton() {
    const btn = this.element.querySelector("[data-preach-split]")
    if (btn) btn.classList.toggle("is-on", this._isSplit())
  }

  _splitIndexFor(pane) {
    return this._splitIndices.get(pane) || 0
  }

  _setSplitIndex(pane, idx) {
    this._splitIndices.set(pane, idx)
  }

  // Operator clicked a region — make it the active one (Go/Next now target it).
  activateRegion(event) {
    if (this._isOutput) return
    if (event.target.closest(".ps-eword")) return // emphasis taps own the word
    const pane = event.target.closest(".ps-pane")
    if (!pane || !pane.classList.contains("is-paired") && !pane.classList.contains("is-presented")) return
    event.preventDefault?.()
    this._setActiveRegion(pane)
  }

  _setActiveRegion(pane) {
    if (!pane || pane.classList.contains("is-presented")) return
    this._unwrapAll() // the old active region's emphasis spans go back to normal
    this._splitRegions().forEach(p => {
      p.classList.toggle("is-presented", p === pane)
      p.classList.toggle("is-paired", p !== pane)
    })
    this._paintSplit() // re-marks current verses, then re-applies emphasis to the new active
  }

  _stepActiveRegion(delta) {
    const pane = this.element.querySelector(".ps-pane.is-presented")
    if (!pane) return
    const verses = Array.from(pane.querySelectorAll(".ps-verse"))
    const idx = this._splitIndexFor(pane) + delta
    if (idx < 0 || idx >= verses.length) return
    const body = pane.querySelector(".ps-verse-body")
    this._transition(() => this._setSplitIndex(pane, idx), { bodies: body ? [body] : [] })
  }

  // Highlight every region at its own current verse; the active region also
  // drives emphasis, the reference footer, the counter and the next preview.
  _paintSplit() {
    const regions = this._splitRegions()
    if (regions.length === 0) return
    regions.forEach(pane => this._paintRegion(pane))

    const active = this.element.querySelector(".ps-pane.is-presented")
    const verses = active ? Array.from(active.querySelectorAll(".ps-verse")) : []
    const idx = active ? this._splitIndexFor(active) : 0
    const num = verses[idx] ? parseInt(verses[idx].dataset.verseNum, 10) : null
    this._range = { first: num, last: num } // for live-follower relay (active region)

    this._applyEmphasisToCurrent()
    this._trackAnchor()
    this._paintSplitRef(regions, active)
    this._paintSplitCounter(regions, active)
    this._paintNextPreview(verses, idx + 1)
    if (this._isStage) this._paintStage()
    this._broadcast()
  }

  _paintRegion(pane) {
    const verses = Array.from(pane.querySelectorAll(".ps-verse"))
    if (verses.length === 0) return
    let idx = Math.max(0, Math.min(this._splitIndexFor(pane), verses.length - 1))
    this._setSplitIndex(pane, idx)
    const num = parseInt(verses[idx].dataset.verseNum, 10)
    verses.forEach(v => v.classList.toggle("is-preach-current", parseInt(v.dataset.verseNum, 10) === num))
  }

  // Footer: every region's reference, the active one marked, so the congregation
  // can see which passages are on screen (e.g. "Romans 8:28 · KJV — Jer 29:11 · KJV").
  _paintSplitRef(regions, active) {
    const el = this.element.querySelector("[data-preach-ref]")
    if (!el) return
    el.textContent = regions.map(pane => this._refLabelFor(pane)).filter(Boolean).join("   —   ")
  }

  _paintSplitCounter(regions, active) {
    const counter = this.element.querySelector("[data-preach-counter]")
    if (!counter || this._isOutput) return
    const verses = active ? Array.from(active.querySelectorAll(".ps-verse")) : []
    const idx = active ? this._splitIndexFor(active) : 0
    const num = verses[idx]?.dataset.verseNum
    const pos = this._workspacePanes().indexOf(active)
    const numeral = ["I", "II", "III", "IV"][pos] || (pos + 1)
    counter.innerHTML = `<span class="num">region ${numeral}${num ? ` · v${num}` : ""}</span><span class="of">of ${regions.length}</span>`
  }

  // The reference label for one pane: "John 3:16 · KJV", from its own inputs.
  _refLabelFor(pane) {
    const raw = pane.querySelector("input[name='pane[reference]']")?.value?.trim()
    if (!raw) return ""
    const verses = Array.from(pane.querySelectorAll(".ps-verse"))
    const idx = Math.max(0, Math.min(this._splitIndexFor(pane), verses.length - 1))
    const num = verses[idx]?.dataset.verseNum
    const base = raw.replace(/\s*[:.]\s*\d+\s*(?:[-–]\s*\d+)?\s*$/, "")
    let label = num ? `${base}:${num}` : base
    const trans = pane.querySelector("select[name='pane[translation_id]'] option:checked")?.textContent?.trim()
    return trans ? `${label} · ${trans}` : label
  }

  _bindRegionClicks() {
    if (this._regionClickHandler || this._isOutput) return
    this._regionClickHandler = (e) => this.activateRegion(e)
    this.element.addEventListener("click", this._regionClickHandler)
  }

  _unbindRegionClicks() {
    if (!this._regionClickHandler) return
    this.element.removeEventListener("click", this._regionClickHandler)
    this._regionClickHandler = null
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

  // The Go box takes a bare verse number ("28" → jump within this chapter),
  // any reference the preacher calls out ("rom 8:28" → chase), or a described
  // thought ("the walls of jericho falling" → AI quick search).
  jumpSubmit(event) {
    event?.preventDefault?.()
    const raw = this.jumpInputTarget.value.trim()
    this._closeJump()
    if (!raw) return
    if (/^\d+$/.test(raw)) {
      this._clearSlide({ repaint: false })
      const verses = this._primaryVerses()
      const idx = verses.findIndex(v => parseInt(v.dataset.verseNum, 10) === parseInt(raw, 10))
      if (idx >= 0) this._transition(() => { this._preachIndex = idx })
      return
    }
    this._chase(raw)
  }

  // Quick chase: validate the reference server-side first (a misheard call
  // must never put an error page on the big screen), load the whole chapter
  // through the pane's own Turbo Frame form, then land on the called verse.
  // Preach mode never exits; the output window and live followers pick the
  // move up through the normal broadcast. Text the parser can't read falls
  // through to the AI quick search ("the prodigal son" → references).
  async _chase(raw, { silent = false } = {}) {
    let parsed
    try {
      const res = await fetch(`/reference_check?q=${encodeURIComponent(raw)}`,
                              { headers: { Accept: "application/json" } })
      parsed = await res.json()
    } catch { return }
    if (!parsed.ok) {
      if (silent) return
      // Not a reference — treat it as a question for the AI study assistant
      // ("azusa street", "the crusaders", "walls of jericho"...).
      if (this.hasQuickFindUrlValue) { this._quickFind(raw); return }
      this._flashJumpError(raw)
      return
    }
    this._loadPassage(parsed.chapter_reference, parsed.verse_start)
  }

  // Load a whole chapter through the presented pane's own Turbo Frame form,
  // then land on the given verse. Shared by chase, the queue, and AI finds.
  _loadPassage(chapterReference, verseStart) {
    const pane = this.element.querySelector(".ps-pane.is-presented")
    const input = pane?.querySelector("input[name='pane[reference]']")
    if (!input) return
    this._remember()
    this._clearSlide({ repaint: false })
    input.value = chapterReference
    const split = this._isSplit()
    pane.addEventListener("turbo:frame-load", () => {
      this._pairForParallel()
      const verses = Array.from(pane.querySelectorAll(".ps-verse"))
      let idx = 0
      if (verseStart) {
        const found = verses.findIndex(v => parseInt(v.dataset.verseNum, 10) === verseStart)
        if (found >= 0) idx = found
      }
      if (split) {
        pane.classList.add("is-presented") // a freshly-loaded passage becomes active
        this._setSplitGridClass(this._splitRegions().length)
        this._setSplitIndex(pane, idx)
      } else {
        this._preachIndex = idx
      }
      this._paint()
      requestAnimationFrame(() => this._autoFit())
    }, { once: true })
    input.form?.requestSubmit()
  }

  // Reopen the jump box with the unreadable text kept for correction.
  _flashJumpError(raw) {
    this.openJump()
    this.jumpInputTarget.value = raw
    this.jumpInputTarget.select?.()
    const wrapper = this.jumpInputTarget.closest(".ps-preach-jump")
    if (!wrapper) return
    wrapper.classList.add("is-error")
    setTimeout(() => wrapper.classList.remove("is-error"), 650)
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

  // ----- AI quick search (Go-box fallback: describe a thought, get references) -----

  // The volunteer typed something the parser can't read ("the walls of jericho
  // falling"). Ask the AI for matching references — validated server-side and
  // loaded from our own DB — and offer them as one-tap chips. The big screen
  // never changes until a chip is picked.
  async _quickFind(q) {
    const box = this._findsBox()
    if (!box) return
    this._findsOpen = true
    box.hidden = false
    box.innerHTML = `<div class="head"><span class="lbl">&#10038; Searching the Scriptures&hellip;</span></div>`
    let data
    try {
      const res = await fetch(`${this.quickFindUrlValue}?q=${encodeURIComponent(q)}`,
                              { headers: { Accept: "application/json" } })
      data = await res.json()
    } catch { data = null }
    if (!this._findsOpen) return // the operator moved on while we searched
    if (!data?.ok || (!data.summary && !data.suggestions?.length)) {
      // A genuine miss (e.g. not a biblical subject) — tell the operator plainly
      // instead of a silent flash, so the Go box never feels broken.
      box.innerHTML =
        `<div class="head"><span class="lbl">&#10038; Nothing found</span>` +
        `<button type="button" class="close" data-action="presentation#cancelFinds">&#10005;</button></div>`
      const card = document.createElement("div")
      card.className = "card"
      const sum = document.createElement("div")
      sum.className = "sum"
      sum.textContent = `No Scripture matched “${q}”. Try a fuller phrase — a name, place, story, or theme.`
      card.appendChild(sum)
      box.appendChild(card)
      return
    }
    box.innerHTML = ""
    const head = document.createElement("div")
    head.className = "head"
    head.innerHTML = `<span class="lbl">&#10038; ${data.summary ? "Study assistant" : "Found in the Scriptures"}</span>` +
                     `<button type="button" class="close" data-action="presentation#cancelFinds">&#10005;</button>`
    box.appendChild(head)
    // The answer card: a short explanation the volunteer can project as a slide.
    if (data.summary) {
      const card = document.createElement("div")
      card.className = "card"
      const topic = document.createElement("div")
      topic.className = "topic"
      topic.textContent = data.topic || q
      const sum = document.createElement("div")
      sum.className = "sum"
      sum.textContent = data.summary
      const project = document.createElement("button")
      project.type = "button"
      project.className = "project"
      project.dataset.action = "presentation#projectFind"
      project.dataset.title = data.topic || q
      project.dataset.body = data.summary
      project.innerHTML = "&#10697; Put this on the screen"
      card.append(topic, sum, project)
      box.appendChild(card)
    }
    ;(data.suggestions || []).forEach(s => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "find"
      btn.dataset.action = "presentation#pickFind"
      btn.dataset.chapterReference = s.chapter_reference
      if (s.verse_start) btn.dataset.verseStart = String(s.verse_start)
      const ref = document.createElement("span")
      ref.className = "ref"
      ref.textContent = s.reference
      const preview = document.createElement("span")
      preview.className = "prev"
      preview.textContent = s.preview || ""
      btn.append(ref, preview)
      box.appendChild(btn)
    })
  }

  pickFind(event) {
    event?.preventDefault?.()
    const d = event.currentTarget.dataset
    this._closeFinds()
    this._loadPassage(d.chapterReference, d.verseStart ? parseInt(d.verseStart, 10) : null)
  }

  // Project the AI answer card as a content slide (same path as songs/thoughts).
  projectFind(event) {
    event?.preventDefault?.()
    const d = event.currentTarget.dataset
    this._closeFinds()
    this._presentSlide({ title: d.title, body: d.body, index: 0 })
  }

  cancelFinds(event) {
    event?.preventDefault?.()
    this._closeFinds()
  }

  _closeFinds() {
    this._findsOpen = false
    const box = this._findsBox()
    if (box) { box.hidden = true; box.innerHTML = "" }
  }

  _findsBox() {
    return this.element.querySelector("[data-preach-finds]")
  }

  // ----- the preach queue & content slides (songs / thoughts) -----

  // A queue item was clicked in the setlist drawer.
  presentItem(detail) {
    if (!detail) return
    if (detail.kind === "scripture" && detail.reference) {
      if (this.element.classList.contains("is-preaching")) {
        this._chase(detail.reference)
      } else {
        // Not preaching yet: stage the passage in the presented (or first) pane.
        const pane = this.element.querySelector(".ps-pane.is-presented") || this._workspacePanes()[0]
        const input = pane?.querySelector("input[name='pane[reference]']")
        if (!input) return
        input.value = detail.reference
        input.form?.requestSubmit()
      }
      return
    }
    if (detail.kind === "slide" && this.element.classList.contains("is-preaching")) {
      this._presentSlide({ title: detail.title, body: detail.body, image: detail.image, index: 0 })
    }
  }

  // Project a song/thought/picture instead of the verse. Blank lines in the
  // body split it into stanzas; next/prev walk the stanzas until scripture
  // returns. A picture is a single full-screen slide.
  _presentSlide({ title, body, image, index }) {
    const stanzas = (body || "").split(/\n\s*\n/).map(s => s.trim()).filter(Boolean)
    if (stanzas.length === 0 && !title && !image) return
    this._remember()
    this._slide = {
      title: title || "",
      body: body || "",
      image: image || null,
      stanzas: stanzas.length ? stanzas : [title || ""],
      index: Math.max(0, Math.min(index || 0, Math.max(stanzas.length - 1, 0)))
    }
    this.element.classList.add("is-slide")
    this._paintSlide()
  }

  _stepSlide(delta) {
    const next = this._slide.index + delta
    if (next < 0 || next >= this._slide.stanzas.length) return
    this._slide.index = next
    this._paintSlide(true)
  }

  _paintSlide(fade = false) {
    const layer = this.element.querySelector("[data-preach-slide]")
    if (!layer || !this._slide) return
    const render = () => {
      const { title, image, stanzas, index } = this._slide
      layer.innerHTML = ""
      if (title && !image) {
        const t = document.createElement("div")
        t.className = "slide-title"
        t.textContent = title
        layer.appendChild(t)
      }
      if (image) {
        const wrap = document.createElement("div")
        wrap.className = "slide-img"
        const img = document.createElement("img")
        img.src = image
        img.alt = title || ""
        wrap.appendChild(img)
        layer.appendChild(wrap)
      } else {
        const stanza = document.createElement("div")
        stanza.className = "slide-stanza"
        stanza.textContent = stanzas[index] || ""
        layer.appendChild(stanza)
        this._fitSlide(layer, stanza)
      }
      const counter = this.element.querySelector("[data-preach-counter]")
      if (counter) {
        counter.innerHTML = image
          ? `<span class="num">picture</span>`
          : `<span class="num">stanza ${index + 1}</span><span class="of">of ${stanzas.length}</span>`
      }
      this._paintSlideNextPreview()
      this._paintRef()
      if (this._isStage) this._paintStage()
      this._broadcast()
    }
    if (fade) {
      layer.classList.add("is-changing")
      setTimeout(() => {
        render()
        requestAnimationFrame(() => layer.classList.remove("is-changing"))
      }, FADE_MS)
    } else {
      render()
    }
  }

  _paintSlideNextPreview() {
    const box = this.element.querySelector("[data-preach-next]")
    if (!box || this._isOutput) return
    if (this._slide.image) {
      box.innerHTML = `<span class="lbl">On screen</span><span class="txt end">— picture —</span>`
      return
    }
    const { stanzas, index } = this._slide
    if (index + 1 >= stanzas.length) {
      box.innerHTML = `<span class="lbl">Next</span><span class="txt end">— end —</span>`
      return
    }
    box.innerHTML = `<span class="lbl">Next · stanza ${index + 2}</span><span class="txt"></span>`
    box.querySelector(".txt").textContent = stanzas[index + 1]
  }

  _fitSlide(layer, stanza) {
    stanza.style.fontSize = ""
    let fs = parseFloat(getComputedStyle(stanza).fontSize) || 56
    let iters = AUTOFIT_MAX_ITERS
    while (layer.scrollHeight > layer.clientHeight + 1 && iters > 0 && fs > AUTOFIT_MIN_PX) {
      fs *= 0.92
      stanza.style.fontSize = `${fs}px`
      iters--
    }
  }

  _clearSlide({ repaint = true } = {}) {
    if (!this._slide) return
    this._slide = null
    this.element.classList.remove("is-slide")
    const layer = this.element.querySelector("[data-preach-slide]")
    if (layer) layer.innerHTML = ""
    if (repaint && this.element.classList.contains("is-preaching")) {
      this._paint()
      requestAnimationFrame(() => this._autoFit())
    }
  }

  // ----- ⟲ Back: return to where you were before a chase / queue / AI jump -----
  // The preacher detours ("let me show you something…") and then says "back to
  // our text" — one press restores the exact previous spot: same chapter, same
  // verse, or the same song stanza.

  _snapshot() {
    if (this._slide) {
      return { kind: "slide", title: this._slide.title, body: this._slide.body,
               image: this._slide.image, index: this._slide.index }
    }
    const pane = this.element.querySelector(".ps-pane.is-presented")
    const reference = pane?.querySelector("input[name='pane[reference]']")?.value?.trim()
    if (!reference) return null
    return { kind: "passage", reference, index: this._preachIndex }
  }

  _remember() {
    if (this._isOutput || this._restoring) return
    if (!this.element.classList.contains("is-preaching")) return
    const snap = this._snapshot()
    if (!snap) return
    const top = this._history[this._history.length - 1]
    if (top && JSON.stringify(top) === JSON.stringify(snap)) return
    this._history.push(snap)
    if (this._history.length > 20) this._history.shift()
    this._syncBackButton()
  }

  goBack(event) {
    event?.preventDefault?.()
    const entry = this._history.pop()
    this._syncBackButton()
    if (!entry) return
    this._restore(entry)
  }

  // Restore a snapshot ({kind:"slide"|"passage"}). Shared by ⟲ Back and ⌂ Home.
  // The _restoring flag stops _remember() from snapshotting the move itself.
  _restore(entry) {
    this._restoring = true
    if (entry.kind === "slide") {
      this._presentSlide({ title: entry.title, body: entry.body, image: entry.image, index: entry.index })
      this._restoring = false
      return
    }
    const pane = this.element.querySelector(".ps-pane.is-presented")
    const input = pane?.querySelector("input[name='pane[reference]']")
    if (!input) { this._restoring = false; return }
    if (input.value.trim().toLowerCase() === entry.reference.toLowerCase()) {
      // Same chapter is still loaded (e.g. an AI card over it) — instant return.
      this._clearSlide({ repaint: false })
      this._transition(() => { this._preachIndex = entry.index })
      this._restoring = false
      return
    }
    input.value = entry.reference
    pane.addEventListener("turbo:frame-load", () => {
      this._pairForParallel()
      this._preachIndex = entry.index
      this._paint()
      requestAnimationFrame(() => this._autoFit())
      this._restoring = false
    }, { once: true })
    input.form?.requestSubmit()
  }

  _syncBackButton() {
    const btn = this.element.querySelector("[data-preach-back]")
    if (btn) btn.disabled = this._history.length === 0
  }

  // ----- ⌂ Home: the pinned "teaching text" -----
  // During a long teaching the preacher detours to many places, then says "back
  // to our text". ⟲ Back steps one detour at a time; ⌂ Home snaps straight to the
  // pinned passage no matter how far the wandering went. As the operator reads
  // through the pinned passage the anchor follows the verse, so Home returns to
  // exactly where the teaching paused, not to verse 1.

  pinAnchor(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching") || this._isOutput) return
    // A second press RELEASES the anchor. Without this a mis-pin (e.g. anchoring
    // the wrong scripture mid-service) could never be undone — the home button
    // stayed stuck on the wrong passage. Click the lit pin to clear it, then
    // pin again wherever you actually want home to be.
    if (this._anchor) {
      this._anchor = null
      this._syncAnchorButtons()
      return
    }
    // The teaching text can be a scripture OR a content slide (a song, a thought,
    // an AI card) — whatever is on screen right now. _snapshot() already captures
    // either, so Home can return to a "Morning Teaching" slide, not only verses.
    const snap = this._snapshot()
    if (!snap) return
    this._anchor = snap
    this._syncAnchorButtons()
  }

  goAnchor(event) {
    event?.preventDefault?.()
    if (!this._anchor) return
    this._remember() // so ⟲ Back can return from the jump home
    this._restore({ ...this._anchor })
  }

  // Keep a passage anchor's verse in step while the operator reads through the
  // pinned text (called from _paint). Detours sit on other references and leave
  // it. A slide anchor stays exactly where it was pinned.
  _trackAnchor() {
    if (this._isOutput || !this._anchor || this._anchor.kind !== "passage" || this._slide) return
    const ref = this.element.querySelector(".ps-pane.is-presented input[name='pane[reference]']")?.value?.trim()
    if (ref && ref.toLowerCase() === this._anchor.reference.toLowerCase()) {
      this._anchor.index = this._preachIndex
    }
  }

  // A short label for whatever the anchor holds — a reference or a slide title.
  _anchorLabel() {
    if (!this._anchor) return ""
    if (this._anchor.kind === "slide") return this._anchor.title || "this slide"
    return this._anchor.reference
  }

  _syncAnchorButtons() {
    const pin = this.element.querySelector("[data-preach-anchor-pin]")
    const home = this.element.querySelector("[data-preach-anchor-home]")
    if (pin) {
      pin.classList.toggle("is-on", !!this._anchor)
      pin.title = this._anchor
        ? `Anchored to ${this._anchorLabel()} — click to release`
        : "Anchor what's on screen (a passage or a slide) as your main teaching text"
    }
    if (home) {
      home.disabled = !this._anchor
      home.title = this._anchor
        ? `Jump back to your teaching text — ${this._anchorLabel()} (H)`
        : "Pin a passage or slide as your teaching text first"
    }
  }

  // ----- blank / holding screen -----
  // Between segments (before the service, during prayer, while the band sets up)
  // the operator snaps the projector to a calm holding screen — one press, and
  // again to bring the verse back. The operator can keep cueing the next verse
  // underneath; only the projector (and live followers) go dark.

  toggleBlank(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    this._blank = !this._blank
    this._applyBlank()
    this._broadcast()
  }

  _applyBlank() {
    // On the projector/output the .is-blank class reveals the holding layer and
    // hides the verse; on the operator console it just lights the button so the
    // operator can still see (and pre-cue) what's queued underneath.
    this.element.classList.toggle("is-blank", this._blank)
    const btn = this.element.querySelector("[data-preach-blank]")
    if (btn) btn.classList.toggle("is-on", this._blank)
  }

  // ----- the Go-Live join card on the big screen -----
  // So the whole room can scan from their seats. The live controller hands us
  // the QR (an inline SVG), the short code and the join URL; we push them to the
  // projector as a full-screen overlay. A null detail clears it.

  _showJoin(detail) {
    if (this._isOutput) return
    this._join = detail && detail.qr_svg
      ? { qr: detail.qr_svg, code: detail.code || "", url: detail.url || "" }
      : null
    this._send(this._join ? { type: "join", ...this._join } : { type: "join", clear: true })
  }

  // Output/projector: paint (or clear) the join overlay.
  _applyJoin(msg) {
    const layer = this.element.querySelector("[data-preach-join]")
    if (!layer) return
    if (msg.clear || !msg.qr) {
      layer.hidden = true
      layer.innerHTML = ""
      this.element.classList.remove("is-joining")
      return
    }
    const url = (msg.url || "").replace(/^https?:\/\//, "")
    layer.innerHTML =
      `<div class="join-eyebrow">Follow along on your phone</div>` +
      `<div class="join-qr">${msg.qr}</div>` +
      `<div class="join-code">${msg.code || ""}</div>` +
      `<div class="join-url">${url}</div>` +
      `<div class="join-hint">Scan the code, or open the address and enter the code. No app, no account.</div>`
    layer.hidden = false
    this.element.classList.add("is-joining")
  }

  // ----- ✷ Emphasise: mark the minister's key word on the live verse -----
  // The preacher lands on "peace" or "grace". The operator arms Emphasise, taps
  // the word(s) on the console, and they glow on the projector and on every
  // following phone. Emphasis is keyed by verse number + word index so all three
  // renderers (operator, output, live) agree no matter the screen.

  toggleEmphasis(event) {
    event?.preventDefault?.()
    if (this._isOutput || !this.element.classList.contains("is-preaching")) return
    this._emphArmed = !this._emphArmed
    this.element.classList.toggle("is-emphasising", this._emphArmed)
    if (this._emphArmed) this._bindEmphasisClicks()
    else this._unbindEmphasisClicks()
    this._syncEmphasisButton()
    this._applyEmphasisToCurrent() // wrap (arm) or leave the current verse words
  }

  _syncEmphasisButton() {
    const btn = this.element.querySelector("[data-preach-emph]")
    if (btn) btn.classList.toggle("is-on", this._emphArmed)
  }

  // While armed, one delegated click handler catches taps on any word span.
  // (Binding here rather than a per-span data-action avoids any Stimulus
  // binding-timing question on dynamically rebuilt verse markup.)
  _bindEmphasisClicks() {
    if (this._emphClickHandler || this._isOutput) return
    this._emphClickHandler = (e) => {
      if (e.target.closest(".ps-eword")) this.emphasizeWord(e)
    }
    this.element.addEventListener("click", this._emphClickHandler)
  }

  _unbindEmphasisClicks() {
    if (!this._emphClickHandler) return
    this.element.removeEventListener("click", this._emphClickHandler)
    this._emphClickHandler = null
  }

  // Operator: a word in the live verse was tapped — toggle its emphasis.
  emphasizeWord(event) {
    const span = event.target.closest(".ps-eword")
    if (!span) return
    event.preventDefault?.()
    const verse = span.closest(".ps-verse")
    const num = parseInt(verse?.dataset.verseNum, 10)
    const widx = parseInt(span.dataset.widx, 10)
    if (Number.isNaN(num) || Number.isNaN(widx)) return
    const words = new Set(this._emphasis[num] || [])
    if (words.has(widx)) words.delete(widx)
    else words.add(widx)
    if (words.size) this._emphasis[num] = [ ...words ].sort((a, b) => a - b)
    else delete this._emphasis[num]
    span.classList.toggle("is-emph")
    this._broadcast()
  }

  // Wrap / re-apply emphasis on the verse(s) currently on screen. On the operator
  // the words become clickable while Emphasise is armed; on the output they only
  // glow. A verse with neither emphasis nor arming is restored to its normal
  // (drop-cap, Strong's, highlight) rendering.
  _applyEmphasisToCurrent() {
    const pane = this.element.querySelector(".ps-pane.is-presented")
    if (!pane) return
    const clickable = !this._isOutput && this._emphArmed
    pane.querySelectorAll(".ps-verse.is-preach-current").forEach(verse => {
      const num = parseInt(verse.dataset.verseNum, 10)
      const indices = this._emphasis[num] || []
      if (indices.length || clickable) this._renderVerseWords(verse, indices, clickable)
      else if (verse.dataset.psWrapped === "1") this._unwrapVerse(verse)
    })
  }

  // Rebuild a verse's text as word spans, glowing the emphasised indices. Keeps a
  // .ps-verse-text wrapper (the stage/next-preview read it) and the number link.
  // The original markup is stashed so we can put Strong's/highlights back later.
  _renderVerseWords(verse, indices, clickable) {
    const full = this._verseFullText(verse)
    if (!full) return
    if (verse.dataset.psWrapped !== "1") {
      verse._psOrig = verse.innerHTML
      verse.dataset.psWrapped = "1"
    }
    const set = new Set(indices)
    const textSpan = document.createElement("span")
    textSpan.className = "ps-verse-text"
    let wi = -1
    full.split(/(\s+)/).forEach(token => {
      if (token === "") return
      if (/^\s+$/.test(token)) { textSpan.appendChild(document.createTextNode(token)); return }
      wi += 1
      const word = document.createElement("span")
      word.className = set.has(wi) ? "ps-eword is-emph" : "ps-eword"
      word.dataset.widx = String(wi)
      word.textContent = token
      // Taps are caught by a delegated listener bound while Emphasise is armed
      // (see _bindEmphasisClicks) — more reliable than a per-span Stimulus action
      // on freshly-created nodes, and clickable just gates the cursor styling.
      textSpan.appendChild(word)
    })
    const vnum = verse.querySelector(".ps-vnum")
    verse.replaceChildren(...(vnum ? [ vnum ] : []), textSpan, document.createTextNode(" "))
  }

  // Put a verse's original (server-rendered) markup back — used when its emphasis
  // is cleared, Emphasise is disarmed, or preach mode exits.
  _unwrapVerse(verse) {
    if (verse._psOrig != null) verse.innerHTML = verse._psOrig
    delete verse._psOrig
    delete verse.dataset.psWrapped
  }

  _unwrapAll() {
    this.element.querySelectorAll(".ps-verse[data-ps-wrapped]").forEach(v => this._unwrapVerse(v))
  }

  // The verse's full displayed text, drop cap included (the cap lives in its own
  // span with the first letter, so we stitch it back on for correct word indices).
  _verseFullText(verse) {
    const cap = verse.querySelector(".ps-dropcap")?.textContent || ""
    const text = verse.querySelector(".ps-verse-text")?.textContent || ""
    return (cap + text).trim()
  }

  // ----- the reference banner (so the congregation sees "John 3:16", not "16") -----

  _referenceLabel() {
    const pane = this.element.querySelector(".ps-pane.is-presented")
    const raw = pane?.querySelector("input[name='pane[reference]']")?.value?.trim()
    if (!raw) return ""
    const base = raw.replace(/\s*[:.]\s*\d+\s*(?:[-–]\s*\d+)?\s*$/, "") // drop any typed verse
    let label = base
    const r = this._range
    if (r && r.first) label += r.first === r.last ? `:${r.first}` : `:${r.first}–${r.last}`
    const trans = pane.querySelector("select[name='pane[translation_id]'] option:checked")?.textContent?.trim()
    return trans ? `${label} · ${trans}` : label
  }

  _paintRef() {
    const el = this.element.querySelector("[data-preach-ref]")
    if (el) el.textContent = this._slide ? "" : this._referenceLabel()
  }

  // ----- phone remote commands (relayed by the remote controller) -----

  _runCommand(detail) {
    if (!detail || !this.element.classList.contains("is-preaching")) return
    if (detail.action === "next") this.next()
    else if (detail.action === "prev") this.prev()
    else if (detail.action === "back") this.goBack()
    else if (detail.action === "home") this.goAnchor()
    else if (detail.action === "blank") this.toggleBlank()
    else if (detail.action === "chase" && detail.value) this._chase(detail.value, { silent: true })
  }

  // ----- output screen preferences (theme + text scale) -----

  toggleScreenPanel(event) {
    event?.preventDefault?.()
    const panel = this.element.querySelector(".ps-screen-panel")
    if (!panel) return
    panel.hidden = !panel.hidden
    this._syncScreenPanel()
  }

  setTheme(event) {
    event?.preventDefault?.()
    this._screen.theme = event.currentTarget.dataset.screenTheme || "vellum"
    this._saveScreenPrefs()
    this._sendScreen()
    this._syncScreenPanel()
  }

  bumpScale(event) {
    event?.preventDefault?.()
    const delta = parseFloat(event.currentTarget.dataset.screenScaleDelta || "0")
    const next = (this._screen.scale || 1) + delta
    this._screen.scale = Math.round(Math.min(1.6, Math.max(0.7, next)) * 10) / 10
    this._saveScreenPrefs()
    this._sendScreen()
    this._syncScreenPanel()
  }

  _syncScreenPanel() {
    const panel = this.element.querySelector(".ps-screen-panel")
    if (!panel) return
    panel.querySelectorAll("[data-screen-theme]").forEach(b => {
      b.classList.toggle("is-on", b.dataset.screenTheme === this._screen.theme)
    })
    const lbl = panel.querySelector("[data-screen-scale]")
    if (lbl) lbl.textContent = `${Math.round((this._screen.scale || 1) * 100)}%`
  }

  _loadScreenPrefs() {
    try {
      return { theme: "vellum", scale: 1, ...JSON.parse(localStorage.getItem(SCREEN_PREFS_KEY) || "{}") }
    } catch {
      return { theme: "vellum", scale: 1 }
    }
  }

  _saveScreenPrefs() {
    try { localStorage.setItem(SCREEN_PREFS_KEY, JSON.stringify(this._screen)) } catch { /* private mode */ }
  }

  _sendScreen() {
    if (!this._screen) return
    this._send({ type: "screen", theme: this._screen.theme, scale: this._screen.scale })
  }

  // Output window: restyle the projection (the stage display keeps its own look).
  _applyScreen(msg) {
    if (this._isStage) return
    this.element.classList.toggle("out-theme-ink", msg.theme === "ink")
    this.element.classList.toggle("out-theme-paper", msg.theme === "paper")
    this.element.style.setProperty("--ps-out-scale", String(msg.scale || 1))
    requestAnimationFrame(() => {
      this._autoFit()
      if (this._slide) this._paintSlide()
    })
  }

  // ----- stage display (confidence monitor: NOW small, NEXT big, clock) -----

  openStage(event) {
    event?.preventDefault?.()
    if (!this.element.classList.contains("is-preaching")) return
    const pane = this.element.querySelector(".ps-pane.is-presented")
    const url = new URL(window.location.href)
    url.searchParams.set("stage", "1")
    url.searchParams.set("pane", String(Math.max(0, this._workspacePanes().indexOf(pane))))
    this._stageWindow = window.open(url.toString(), "ps-preach-stage", "popup=yes,width=1100,height=650")
    if (!this._stageWindow) alert("The browser blocked the stage window — allow pop-ups for this site, then click Stage again.")
  }

  _paintStage() {
    const now = this.element.querySelector("[data-stage-now]")
    const next = this.element.querySelector("[data-stage-next]")
    const ref = this.element.querySelector("[data-stage-ref]")
    if (!now || !next) return

    if (this._slide) {
      const { title, image, stanzas, index } = this._slide
      if (image) {
        if (ref) ref.textContent = title || "Picture"
        this._fillStagePanel(now, "on screen", "— picture —")
        this._fillStagePanel(next, "next", "press Back or pick the next item")
        return
      }
      if (ref) ref.textContent = title || "Song"
      this._fillStagePanel(now, `stanza ${index + 1} of ${stanzas.length}`, stanzas[index] || "")
      this._fillStagePanel(next, "next", stanzas[index + 1] || "— end —")
      return
    }

    const verses = this._primaryVerses()
    const start = this._preachIndex
    const end = Math.min(verses.length, start + this._groupSize)
    const pane = this.element.querySelector(".ps-pane.is-presented")
    if (ref) ref.textContent = pane?.querySelector("input[name='pane[reference]']")?.value || ""
    const textOf = (list) => list.map(v =>
      Array.from(v.querySelectorAll(".ps-verse-text")).map(t => t.textContent).join("")
    ).join("  ").trim()
    const numsOf = (list) => list.map(v => v.dataset.verseNum).join("–")

    const current = verses.slice(start, end)
    this._fillStagePanel(now, current.length ? `now · v${numsOf(current)}` : "now", textOf(current))
    const upcoming = verses.slice(end, Math.min(verses.length, end + this._groupSize))
    this._fillStagePanel(next, upcoming.length ? `next · v${numsOf(upcoming)}` : "next",
                         upcoming.length ? textOf(upcoming) : "— end of chapter —")
  }

  _fillStagePanel(panel, label, text) {
    panel.innerHTML = ""
    const lbl = document.createElement("div")
    lbl.className = "lbl"
    lbl.textContent = label
    const txt = document.createElement("div")
    txt.className = "txt"
    txt.textContent = text
    panel.append(lbl, txt)
  }

  _startClock() {
    const tick = () => {
      const el = this.element.querySelector("[data-stage-clock]")
      if (el) el.textContent = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    }
    tick()
    this._clockTimer = setInterval(tick, 10_000)
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
    if (!this._outputWindow) {
      alert("The browser blocked the output window — allow pop-ups for this site, then click Project again.")
    }
    // The projector shows the staged scripture immediately. To start on a calm
    // hold instead, tap Blank — it's an option, not the default.
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
    if (this._isStage) {
      this.element.classList.add("is-stage")
      this._startClock()
    }
    const panes = this._workspacePanes()
    const pane = panes[paneIndex] || panes[0]
    if (!pane) return
    panes.forEach(p => p.classList.remove("is-presented", "is-paired"))
    pane.classList.add("is-presented")
    this.element.classList.add("is-presenting", "is-preaching")
    this._paint()
    requestAnimationFrame(() => this._autoFit())
    const role = this._isStage ? "stage" : "output"
    window.addEventListener("pagehide", () => this._send({ type: "bye", role }))
    this._send({ type: "hello", role })
  }

  _onMessage(msg) {
    if (!msg || !msg.type) return
    if (this._isOutput) {
      if (msg.type === "state") this._applyState(msg)
      else if (msg.type === "screen") this._applyScreen(msg)
      else if (msg.type === "join") this._applyJoin(msg)
      else if (msg.type === "exit") window.close()
    } else {
      // Only the projector output flips the operator into console mode; the
      // stage display is a passive extra.
      if (msg.type === "hello") {
        if (msg.role !== "stage") this._setProjecting(true)
        this._sendScreen()
        this._broadcast()
        if (this._join) this._send({ type: "join", ...this._join }) // survive an output refresh
      } else if (msg.type === "bye") {
        if (msg.role !== "stage") this._setProjecting(false)
      }
    }
  }

  // Output window: mirror the operator's state. If a state lands mid-fade we
  // park it in _afterFade (applied when the fade ends) so rapid Next-Next from
  // the operator can't desync the two windows.
  _applyState(msg) {
    // Holding screen mirrors the operator — including across an output refresh,
    // since the operator re-broadcasts the full state (blank included) on hello.
    this.element.classList.toggle("is-blank", !!msg.blank)
    this._emphasis = msg.emphasis || {}
    if (msg.slide) { this._applySlide(msg.slide); return }
    if (this._slide) this._clearSlide({ repaint: false })
    if (msg.split) { this._applySplitState(msg); return }
    // The operator left split — drop the region layout before single-cursor paint.
    if (this._isSplit()) {
      this.element.classList.remove("is-split", "split-2", "split-3", "split-4")
      this.element.querySelectorAll(".ps-pane.is-paired").forEach(p => p.classList.remove("is-paired"))
      this._splitIndices = new Map()
    }
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

    // If only the emphasis changed (operator tapped a word), re-glow in place
    // instead of fading the whole verse — no flicker on the projector.
    const nextGroup = Math.max(1, Math.min(5, msg.group || 1))
    const nextIndex = msg.index || 0
    const nextParallel = !!msg.parallel
    const sameSpot = this._preachIndex === nextIndex && this._groupSize === nextGroup &&
      this.element.classList.contains("is-parallel") === nextParallel &&
      this.element.querySelector(".ps-verse.is-preach-current")
    this._groupSize = nextGroup
    this.element.classList.toggle("is-parallel", nextParallel)
    this._pairForParallel()
    if (sameSpot) {
      this._applyEmphasisToCurrent()
      this._paintRef()
    } else {
      this._transition(() => { this._preachIndex = nextIndex })
    }
  }

  // Output/stage window: mirror a song/thought slide. Same slide → fade to the
  // new stanza; different slide → render it fresh.
  _applySlide(slide) {
    if (this._slide && this._slide.body === slide.body && this._slide.title === slide.title &&
        (this._slide.image || null) === (slide.image || null)) {
      if (this._slide.index !== slide.index) {
        this._slide.index = slide.index
        this._paintSlide(true)
      }
      return
    }
    this._presentSlide(slide)
  }

  // Output/stage window: mirror split projection. Load any region whose passage
  // differs from what we hold, then lay out every region at its own verse with
  // the active one marked. A region whose verse moved fades; the rest snap.
  _applySplitState(msg) {
    this.element.classList.add("is-split")
    this.element.classList.remove("is-parallel")
    const panes = this._workspacePanes()
    const wanted = (msg.regions || []).filter(r => panes[r.pane])
    if (wanted.length === 0) return
    this._setSplitGridClass(wanted.length)

    let pending = 0
    const finalize = () => {
      panes.forEach(p => p.classList.remove("is-presented", "is-paired"))
      wanted.forEach(r => {
        const pane = panes[r.pane]
        const isActive = r.pane === msg.active
        pane.classList.toggle("is-presented", isActive)
        pane.classList.toggle("is-paired", !isActive)
        const idx = r.index || 0
        const moved = this._splitIndexFor(pane) !== idx
        this._setSplitIndex(pane, idx)
        const body = pane.querySelector(".ps-verse-body")
        if (moved && body) {
          body.classList.add("is-changing")
          setTimeout(() => {
            this._paintRegion(pane)
            requestAnimationFrame(() => body.classList.remove("is-changing"))
          }, FADE_MS)
        } else {
          this._paintRegion(pane)
        }
      })
      this._emphasis = msg.emphasis || {}
      this._applyEmphasisToCurrent()
      this._paintSplitRef(this._splitRegions(), this.element.querySelector(".ps-pane.is-presented"))
      if (this._isStage) this._paintStage()
      requestAnimationFrame(() => this._autoFit())
    }

    wanted.forEach(r => {
      const pane = panes[r.pane]
      const refInput = pane.querySelector("input[name='pane[reference]']")
      const transSelect = pane.querySelector("select[name='pane[translation_id]']")
      const sameRef = !r.reference || !refInput ||
          refInput.value.trim().toLowerCase() === r.reference.trim().toLowerCase()
      const sameTrans = !r.translation || !transSelect || transSelect.value === String(r.translation)
      if (!(sameRef && sameTrans)) {
        pending++
        if (refInput) refInput.value = r.reference
        if (transSelect && r.translation) transSelect.value = String(r.translation)
        pane.addEventListener("turbo:frame-load", () => { if (--pending === 0) finalize() }, { once: true })
        refInput?.form?.requestSubmit()
      }
    })
    if (pending === 0) finalize()
  }

  _broadcast() {
    if (this._isOutput) return
    if (!this.element.classList.contains("is-preaching")) return
    if (this._isSplit()) { this._broadcastSplit(); return }
    const pane = this.element.querySelector(".ps-pane.is-presented")
    if (!pane) return
    const state = {
      type: "state",
      pane: Math.max(0, this._workspacePanes().indexOf(pane)),
      index: this._preachIndex,
      group: this._groupSize,
      parallel: this.element.classList.contains("is-parallel"),
      blank: this._blank,
      emphasis: this._emphasis,
      reference: pane.querySelector("input[name='pane[reference]']")?.value || null,
      translation: pane.querySelector("select[name='pane[translation_id]']")?.value || null,
      verseStart: this._range?.first ?? null,
      verseEnd: this._range?.last ?? null,
      slide: this._slide
        ? { title: this._slide.title, body: this._slide.body, image: this._slide.image, index: this._slide.index }
        : null
    }
    this._send(state)
    // The live controller relays this to the congregation's phones.
    window.dispatchEvent(new CustomEvent("preach:state", { detail: state }))
  }

  // Split: send the projector the full set of regions (each its own passage +
  // verse + which is active), and send live phones a flattened view of the
  // ACTIVE region so a follower's single-passage screen tracks the preacher.
  _broadcastSplit() {
    const panes = this._workspacePanes()
    const regions = this._splitRegions().map(pane => {
      const verses = Array.from(pane.querySelectorAll(".ps-verse"))
      const idx = Math.max(0, Math.min(this._splitIndexFor(pane), verses.length - 1))
      const num = verses[idx] ? parseInt(verses[idx].dataset.verseNum, 10) : null
      return {
        pane: panes.indexOf(pane),
        reference: pane.querySelector("input[name='pane[reference]']")?.value || null,
        translation: pane.querySelector("select[name='pane[translation_id]']")?.value || null,
        index: idx,
        verseStart: num,
        verseEnd: num
      }
    })
    const active = this.element.querySelector(".ps-pane.is-presented")
    const activePos = panes.indexOf(active)
    this._send({
      type: "state", split: true, active: activePos, regions,
      blank: this._blank, emphasis: this._emphasis, slide: null
    })
    const a = regions.find(r => r.pane === activePos) || regions[0] || {}
    window.dispatchEvent(new CustomEvent("preach:state", { detail: {
      type: "state",
      reference: a.reference, translation: a.translation,
      verseStart: a.verseStart, verseEnd: a.verseEnd,
      emphasis: this._emphasis, slide: null
    } }))
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
    if (this._isOutput) this._send({ type: "bye", role: this._isStage ? "stage" : "output" })
    this._channel?.close()
    this._channel = null
    if (this._onSetlist) window.removeEventListener("setlist:present", this._onSetlist)
    if (this._onCommand) window.removeEventListener("preach:command", this._onCommand)
    if (this._onJoin) window.removeEventListener("preach:join", this._onJoin)
    this._unbindRegionClicks()
    this._unbindEmphasisClicks()
    clearInterval(this._clockTimer)
    this._unbindEsc()
    this._unbindKeys()
    this._unbindSwipe()
  }

  // ----- internals: rendering, transitions, auto-fit -----

  _transition(mutate, { bodies } = {}) {
    if (this._fading) return // ignore rapid taps mid-fade
    bodies = bodies || this._activeBodies()
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
    if (this._isSplit()) { this._paintSplit(); return }
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
    this._range = { first, last } // actual verse numbers, for broadcast + live
    const total = primary.length > 0 ? parseInt(primary[primary.length - 1].dataset.verseNum, 10) : 0
    const counter = this.element.querySelector("[data-preach-counter]")
    if (counter) {
      const range = first === last ? `${first}` : `${first}–${last}`
      counter.innerHTML = `<span class="num">verse ${range}</span><span class="of">of ${total}</span>`
    }

    this._applyEmphasisToCurrent()
    this._trackAnchor()
    this._paintRef()
    this._paintNextPreview(primary, end)
    if (this._isStage) this._paintStage()
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
      // Never let preach shortcuts hijack typing. When the operator is in ANY
      // text field — the queue, notes, a pane's reference box, AI search — the
      // keystroke belongs to that field, not to the projector. This is the bug
      // that once sent a Backspace to "⟲ Back" and yanked the live slide off the
      // screen while a wrong letter was being deleted in the queue.
      if (this._isEditableTarget(e.target)) return
      if (this._jumpOpen) return
      if (e.key === "ArrowRight" || e.key === " " || e.key === "PageDown") { e.preventDefault(); this.next() }
      else if (e.key === "ArrowLeft" || e.key === "PageUp") { e.preventDefault(); this.prev() }
      else if (e.key === "Home") { e.preventDefault(); this._transition(() => { this._preachIndex = 0 }) }
      else if (e.key === "g" || e.key === "G") { e.preventDefault(); this.openJump() }
      else if (e.key === "p" || e.key === "P") { e.preventDefault(); this.toggleParallel() }
      else if (e.key === "b" || e.key === "B" || e.key === "Backspace") { e.preventDefault(); this.goBack() }
      else if (e.key === "h" || e.key === "H") { e.preventDefault(); this.goAnchor() }
      else if (e.key === "." || e.key === "0") { e.preventDefault(); this.toggleBlank() }
      else if (e.key >= "1" && e.key <= "5") {
        e.preventDefault()
        // In split, number keys pick which region is active; otherwise they set
        // the verse-group size.
        if (this._isSplit()) {
          const region = this._splitRegions()[parseInt(e.key, 10) - 1]
          if (region) this._setActiveRegion(region)
          return
        }
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

  // True when the keystroke is being typed into an editable field, so the global
  // preach shortcuts (Backspace=Back, b/p/g/h, 0–5…) must stand down and let the
  // character through instead of driving the projector.
  _isEditableTarget(target) {
    const el = target || document.activeElement
    if (!el || !el.tagName) return false
    if (el.isContentEditable) return true
    return el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT"
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
