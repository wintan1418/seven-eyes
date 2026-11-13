import { Controller } from "@hotwired/stimulus"
import { warmLocal, localState } from "../lib/offline/local_pane"
import { referenceLabel } from "../lib/offline/reference_parser"
import { bookText } from "../lib/offline/store"
import { chapterVerses } from "../lib/offline/pane_renderer"
import { quickFetch } from "../lib/offline/network"
import { queueKey } from "../lib/offline/setlist_state"
import { songSlides } from "../lib/song_sheet"

// Preview → Live, EasyWorship-style, on the operator screen only (never on the
// ?output=1 projector or the ?stage=1 pulpit screen). Lives on .ps-root.
//
//   LIVE     what the projector shows now (from preach:state) — red
//   PREVIEW  staged, NOT on screen until "Go live" (button, L, Enter in the
//            preview) — amber
//   chapter verse list: the typed / previewed / live chapter, every verse with
//            its full text from the downloaded Bible (the server only when the
//            translation isn't on the device). Click previews, double-click goes
//            live, "+" queues. The live verse stays marked and scrolled to.
//
// Going live reuses the queue's path (setlist:present → presentation#presentItem
// → _chase → _loadPassage), which renders from the device first. Nothing here
// touches the presented pane until Go live, so the projector can't flash.
const PREVIEW_FIRST_KEY = "ps-preview-first"
const CHAPTER_TIMEOUT_MS = 2000
const PREVIEW_MAX_VERSES = 6

export default class extends Controller {
  static targets = [ "console", "liveLabel", "queueLive", "previewCard", "previewLabel", "previewText", "queuePreview",
    "goLive", "verseList", "verseListTitle", "verseRows" ]

  initialize() {
    this._preview = null // {kind, reference, label, title, body, image, cid}
    this._live = null // {label, osis, chapter, first, last, slide}
    this._queued = new Set()
    this._chapters = new Map() // "code|osis|chapter" → verses
    this._list = null // {osis, chapter, title, reference}
  }

  connect() {
    if (this.element.classList.contains("is-output")) return
    this._listeners = {
      "preview:load": (e) => this.load(e.detail),
      "preview:typing": (e) => this._typed(e.detail?.raw),
      "preview:golive": () => this.goLive(),
      "preach:state": (e) => this._liveState(e.detail),
      "setlist:changed": (e) => { this._queued = new Set(e.detail?.keys || []); this._paintQueueButtons() }
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    try {
      const toggle = this.element.querySelector("[data-preview-first]")
      if (toggle) toggle.setAttribute("aria-pressed", String(localStorage.getItem(PREVIEW_FIRST_KEY) === "1"))
    } catch { /* private mode */ }
  }

  disconnect() {
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
  }

  // Go box "Preview first": Enter loads Preview instead of the projector. The
  // focus goes back to the box so the operator just keeps typing.
  togglePreviewFirst(event) {
    const toggle = event.currentTarget
    const on = toggle.getAttribute("aria-pressed") !== "true"
    toggle.setAttribute("aria-pressed", String(on))
    try { localStorage.setItem(PREVIEW_FIRST_KEY, on ? "1" : "0") } catch { /* private mode */ }
    this.element.querySelector(".ps-preach-jump input")?.focus()
  }

  // ---- Preview ------------------------------------------------------------------

  // Stage something. The label shows at once (parsed on the device); the text
  // follows from IndexedDB a moment later.
  load(detail) {
    if (!detail || !this.hasPreviewCardTarget) return
    const preview = { ...detail }
    if (preview.kind === "scripture") {
      const p = localState().parse?.(preview.reference || "")
      if (p && !p.valid) { this._flashInvalid(preview.reference); return }
      preview.parsed = p || null
      preview.label = p ? referenceLabel(p) : (preview.label || preview.reference)
    } else {
      preview.label = preview.label || preview.title || "Picture"
    }
    this._preview = preview
    this._previewSeq = (this._previewSeq || 0) + 1
    this.previewLabelTarget.textContent = preview.label
    this.previewCardTarget.dataset.state = this._isLive(preview) ? "live" : "ready"
    this.goLiveTarget.disabled = false
    this._paintQueueButtons()
    window.dispatchEvent(new CustomEvent("preview:changed", { detail: { cid: preview.cid || null, label: preview.label } }))
    // On a narrow screen the queue is a drawer: open it so the preview shows (it doesn't dim the screen).
    if (!this._visible()) window.dispatchEvent(new CustomEvent("setlist:open"))

    if (preview.kind === "scripture") this._paintScripture(preview, this._previewSeq)
    else this._paintSlide(preview)
  }

  async _paintScripture(preview, seq) {
    this.previewTextTarget.replaceChildren(el("span", "loading", "…"))
    const chapter = await this._chapter(preview.reference)
    if (seq !== this._previewSeq) return
    if (!chapter) {
      this.previewTextTarget.replaceChildren(el("span", "muted", "The words load when it goes live (this Bible isn't on the device)."))
      return
    }
    const p = chapter.parsed
    const first = p.verseStart ?? 1
    const last = p.openEnded ? Infinity : (p.verseEnd ?? p.verseStart ?? Infinity)
    const verses = chapter.verses.filter((v) => v.num >= first && v.num <= last)
    const shown = verses.slice(0, PREVIEW_MAX_VERSES)
    const nodes = shown.map((v) => {
      const span = el("span", "v")
      span.append(el("sup", null, String(v.num)), document.createTextNode(` ${v.text} `))
      return span
    })
    if (verses.length > shown.length) nodes.push(el("span", "muted", `… ${verses.length - shown.length} more verse${verses.length - shown.length === 1 ? "" : "s"}`))
    if (chapter.foreign) nodes.push(el("span", "muted tag", chapter.foreign))
    this.previewTextTarget.replaceChildren(...(nodes.length ? nodes : [ el("span", "muted", "No such verse in this chapter") ]))
    this._showList(chapter, { focus: p.verseStart })
  }

  // A song / thought: every slide in projection order (EasyWorship's slide
  // list), its section label small. Clicking a slide puts the song on screen at
  // that slide; while the song is live, the slide on screen is marked.
  _paintSlide(preview) {
    const nodes = []
    if (preview.image) {
      const img = el("img", "thumb")
      img.src = preview.image
      img.alt = ""
      nodes.push(img)
    }
    const { slides } = songSlides(preview.body, preview.arrangement)
    this.previewTextTarget.classList.toggle("is-slides", slides.length > 1)
    if (slides.length === 1) nodes.push(el("span", "stanza", slides[0].text))
    else {
      slides.forEach((s, i) => {
        const btn = el("button", "slide")
        btn.type = "button"
        btn.dataset.index = String(i)
        btn.dataset.action = "preview#slideLive"
        btn.title = "Put this slide on the screen"
        btn.append(el("span", "lbl", s.label || `${i + 1}`), el("span", "txt", s.text))
        nodes.push(btn)
      })
    }
    this.previewTextTarget.replaceChildren(...nodes)
    this._paintLiveSlide()
  }

  // A slide in Preview's list: that song, live, at that slide.
  slideLive(event) {
    event?.preventDefault?.()
    if (!this._preview || !this.element.classList.contains("is-preaching")) return
    const { parsed, ...detail } = this._preview
    window.dispatchEvent(new CustomEvent("setlist:present", { detail: { ...detail, index: Number(event.currentTarget.dataset.index) || 0 } }))
    this.previewCardTarget.dataset.state = "live"
  }

  _paintLiveSlide() {
    if (!this.hasPreviewTextTarget) return
    const live = this._preview && this._isLive(this._preview) ? this._live?.index : null
    this.previewTextTarget.querySelectorAll(".slide").forEach((b) => {
      b.classList.toggle("is-live", live != null && Number(b.dataset.index) === live)
    })
  }

  // Go live with what's in Preview (button, L, Enter in the preview card).
  goLive(event) {
    event?.preventDefault?.()
    if (!this._preview || !this.element.classList.contains("is-preaching")) return
    const { parsed, ...detail } = this._preview
    this._goneLiveAt = performance.now()
    window.dispatchEvent(new CustomEvent("setlist:present", { detail }))
    this.previewCardTarget.dataset.state = "live"
  }

  previewKey(event) {
    if (event.key === "Enter" || (event.key === "l" && !event.metaKey && !event.ctrlKey)) {
      event.preventDefault()
      event.stopPropagation()
      this.goLive()
    }
  }

  queuePreview(event) {
    event?.preventDefault?.()
    const p = this._preview
    if (!p) return
    window.dispatchEvent(new CustomEvent("setlist:add", { detail: p.kind === "scripture"
      ? { kind: "scripture", reference: p.label || p.reference }
      : { kind: p.itemKind || "thought", title: p.title, body: p.body, arrangement: p.arrangement } }))
  }

  queueLive(event) {
    event?.preventDefault?.()
    if (!this._live?.label || this._live.slide) return
    window.dispatchEvent(new CustomEvent("setlist:add", { detail: { kind: "scripture", reference: this._live.label } }))
  }

  _paintQueueButtons() {
    if (this.hasQueuePreviewTarget) {
      const p = this._preview
      const key = p && queueKey(p.kind === "scripture" ? { kind: "scripture", label: p.label } : { kind: p.itemKind, title: p.title, body: p.body })
      this.queuePreviewTarget.hidden = !p || p.kind !== "scripture" || this._queued.has(key)
    }
    if (this.hasQueueLiveTarget) {
      const l = this._live
      this.queueLiveTarget.hidden = !l?.label || !!l.slide || this._queued.has(queueKey({ kind: "scripture", label: l.label }))
    }
    if (this.hasVerseRowsTarget && this._list) {
      this.verseRowsTarget.querySelectorAll(".vrow").forEach((row) => {
        row.classList.toggle("is-queued", this._queued.has(queueKey({ kind: "scripture", label: row.dataset.label })))
      })
    }
  }

  _flashInvalid(raw) {
    this.previewLabelTarget.textContent = `Can't read “${raw}”`
    this.previewCardTarget.dataset.state = "error"
  }

  _visible() {
    const host = this.element.querySelector(".ps-setlist-host")
    return !!host?.classList.contains("is-open")
  }

  // ---- Live (what the projector shows) ---------------------------------------------

  _liveState(state) {
    if (!state || !this.hasLiveLabelTarget) return
    if (state.slide) {
      this._live = { slide: true, label: state.slide.title || "Slide", index: state.slide.index || 0, body: state.slide.body }
      this.liveLabelTarget.textContent = `♫ ${this._live.label}`
    } else {
      const ref = (state.reference || "").trim()
      const p = localState().parse?.(ref)
      const first = state.verseStart
      const last = state.verseEnd ?? first
      let label = ref
      if (p?.valid && first) label = referenceLabel({ ...p, chapterEnd: p.chapter, verseStart: first, verseEnd: last, openEnded: false })
      else if (first) label = `${ref.replace(/\s*[:.]\s*\d.*$/, "")}:${first}${last && last !== first ? `-${last}` : ""}`
      const moved = !this._live || this._live.osis !== p?.osis || this._live.chapter !== p?.chapter
      this._live = { label, osis: p?.osis, chapter: p?.chapter, first, last, reference: ref }
      this.liveLabelTarget.textContent = label + (state.blank ? " · screen blanked" : "")
      if (moved && p?.valid) this._followLive(ref)
    }
    this.liveLabelTarget.closest(".ps-console-row")?.classList.toggle("is-blank", !!state.blank)
    if (this._preview && this.hasPreviewCardTarget && this.previewCardTarget.dataset.state !== "error") {
      this.previewCardTarget.dataset.state = this._isLive(this._preview) ? "live" : "ready"
    }
    if (this._goneLiveAt) {
      // Preview → live, measured to the first paint of the new state.
      this.element.dataset.previewToLiveMs = String(Math.round(performance.now() - this._goneLiveAt))
      this._goneLiveAt = null
    }
    this._paintListMarks()
    this._paintQueueButtons()
    this._paintLiveSlide()
  }

  _isLive(preview) {
    const l = this._live
    if (!l || !preview) return false
    if (preview.kind !== "scripture") return !!l.slide && l.label === (preview.title || "Slide") && (l.body || "") === (preview.body || "")
    const p = preview.parsed
    if (!p || l.slide) return false
    return l.osis === p.osis && l.chapter === p.chapter && (p.verseStart == null || p.verseStart === l.first)
  }

  // The live passage moved to another chapter: the list follows it, unless the
  // operator is in the middle of picking something else.
  async _followLive(reference) {
    if (this._listPinnedAt && performance.now() - this._listPinnedAt < 8000) return
    const chapter = await this._chapter(reference)
    if (chapter) this._showList(chapter, { pinned: false })
  }

  // ---- the chapter verse list -------------------------------------------------------

  async _typed(raw) {
    const text = (raw || "").trim()
    if (!text || /^\d+$/.test(text)) return
    const p = localState().parse?.(text)
    if (!p?.valid) return
    const seq = (this._typedSeq = (this._typedSeq || 0) + 1)
    const chapter = await this._chapter(text)
    if (seq !== this._typedSeq || !chapter) return
    this._showList(chapter, { focus: p.verseStart, target: p.verseStart })
  }

  _showList(chapter, { focus = null, target = null, pinned = true } = {}) {
    if (!this.hasVerseListTarget) return
    if (pinned) this._listPinnedAt = performance.now()
    const p = chapter.parsed
    const same = this._list && this._list.osis === p.osis && this._list.chapter === p.chapter && this._list.code === chapter.code
    this._list = { osis: p.osis, chapter: p.chapter, code: chapter.code, bookName: p.bookName }
    this.verseListTitleTarget.textContent = `${p.bookName} ${p.chapter}${chapter.translation ? ` · ${chapter.translation}` : ""}`
    if (!same) {
      this.verseRowsTarget.replaceChildren(...chapter.verses.map((v) => {
        const label = `${p.bookName} ${p.chapter}:${v.num}`
        const row = el("li", "vrow")
        row.dataset.num = String(v.num)
        row.dataset.label = label
        const pick = el("button", "pick")
        pick.type = "button"
        pick.dataset.action = "click->preview#pickVerse dblclick->preview#liveVerse keydown->preview#rowKey"
        pick.title = `${label} — click to preview, double-click to go live`
        pick.append(el("span", "ref", `${p.chapter}:${v.num}`), el("span", "txt", v.text))
        const add = el("button", "add", "+")
        add.type = "button"
        add.dataset.action = "preview#queueVerse"
        add.title = `Add ${label} to the queue`
        row.append(pick, add)
        return row
      }))
    }
    this.verseListTarget.hidden = false
    this._targetVerse = target
    this._paintListMarks()
    this._paintQueueButtons()
    const scrollTo = focus ?? (this._liveInList() ? this._live.first : null)
    if (scrollTo != null) this._rowFor(scrollTo)?.scrollIntoView?.({ block: "nearest" })
  }

  _liveInList() {
    return this._list && this._live && !this._live.slide && this._live.osis === this._list.osis && this._live.chapter === this._list.chapter
  }

  _paintListMarks() {
    if (!this._list || !this.hasVerseRowsTarget) return
    const live = this._liveInList() ? this._live : null
    const pp = this._preview?.kind === "scripture" ? this._preview.parsed : null
    const previewHere = pp && pp.osis === this._list.osis && pp.chapter === this._list.chapter ? pp : null
    this.verseRowsTarget.querySelectorAll(".vrow").forEach((row) => {
      const n = Number(row.dataset.num)
      row.classList.toggle("is-live", !!live && n >= live.first && n <= (live.last ?? live.first))
      const pEnd = previewHere ? (previewHere.verseEnd ?? previewHere.verseStart) : null
      row.classList.toggle("is-preview", !!previewHere && previewHere.verseStart != null && n >= previewHere.verseStart && n <= pEnd)
      row.classList.toggle("is-target", this._targetVerse != null && n === this._targetVerse)
    })
    // Keep the live verse in view as the preacher moves through the chapter.
    if (live && !this.verseRowsTarget.matches(":hover")) {
      const row = this._rowFor(live.first)
      if (row && !visibleIn(row, this.verseRowsTarget)) row.scrollIntoView?.({ block: "nearest" })
    }
  }

  _rowFor(num) {
    return this.hasVerseRowsTarget ? this.verseRowsTarget.querySelector(`.vrow[data-num="${num}"]`) : null
  }

  pickVerse(event) {
    const label = event.currentTarget.closest(".vrow")?.dataset.label
    if (label) this.load({ kind: "scripture", reference: label, source: "list" })
  }

  liveVerse(event) {
    const label = event.currentTarget.closest(".vrow")?.dataset.label
    if (!label) return
    this.load({ kind: "scripture", reference: label, source: "list" })
    this.goLive()
  }

  queueVerse(event) {
    event.preventDefault()
    const label = event.currentTarget.closest(".vrow")?.dataset.label
    if (label) window.dispatchEvent(new CustomEvent("setlist:add", { detail: { kind: "scripture", reference: label } }))
  }

  // Arrow keys walk the verse list; Enter previews, Shift+Enter goes live.
  rowKey(event) {
    const row = event.currentTarget.closest(".vrow")
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      event.stopPropagation()
      const next = event.key === "ArrowDown" ? row.nextElementSibling : row.previousElementSibling
      next?.querySelector(".pick")?.focus()
    } else if (event.key === "Enter") {
      event.preventDefault()
      event.stopPropagation()
      this.load({ kind: "scripture", reference: row.dataset.label, source: "list" })
      if (event.shiftKey) this.goLive()
    } else if (event.key === "+") {
      event.preventDefault()
      event.stopPropagation()
      window.dispatchEvent(new CustomEvent("setlist:add", { detail: { kind: "scripture", reference: row.dataset.label } }))
    }
  }

  // ---- chapter text: the downloaded Bible first, the server only if it must ---------------

  async _chapter(reference) {
    const local = await warmLocal()
    const p = local.parse?.(reference)
    if (p && !p.valid) return null
    const translationId = this._translationId()
    const t = local.translations?.find((x) => String(x.id) === String(translationId))
    const downloaded = local.downloaded || []
    const code = t && downloaded.some((d) => d.code === t.code) ? t.code : null
    if (p && code) {
      const verses = await this._localChapter(code, p)
      if (verses.length) return { parsed: p, verses, code, translation: code }
    }
    // Not on the device in this translation: ask the server briefly…
    const remote = await this._serverChapter(reference, translationId)
    if (remote) return remote
    // …and with no network, any Bible that is on the device beats nothing.
    if (p && downloaded.length) {
      const other = downloaded[0].code
      const verses = await this._localChapter(other, p)
      if (verses.length) return { parsed: p, verses, code: other, translation: other, foreign: `Shown in ${other} — this translation isn't on the device` }
    }
    return null
  }

  async _localChapter(code, p) {
    const key = `${code}|${p.osis}|${p.chapter}`
    if (!this._chapters.has(key)) {
      const record = await bookText(code, p.osis)
      this._chapters.set(key, record ? chapterVerses(record, p.chapter) : [])
    }
    return this._chapters.get(key)
  }

  async _serverChapter(reference, translationId) {
    const key = `srv|${reference}|${translationId}`
    if (this._chapters.has(key)) return this._chapters.get(key)
    try {
      const url = `/verse_chapter?q=${encodeURIComponent(reference)}&translation=${encodeURIComponent(translationId || "")}`
      const { res, body } = await quickFetch(url, { headers: { Accept: "application/json" } }, { timeoutMs: CHAPTER_TIMEOUT_MS, read: "json" })
      if (!res.ok || !body?.ok) return null
      const parsed = localState().parse?.(reference) || {
        valid: true, osis: body.osis, chapter: body.chapter, bookName: body.chapter_reference.replace(/\s+\d+$/, ""),
        verseStart: body.verse_start, verseEnd: body.verse_end, openEnded: false
      }
      const result = { parsed, verses: body.verses, code: body.translation, translation: body.translation }
      this._chapters.set(key, result)
      return result
    } catch { return null }
  }

  _translationId() {
    const pane = this.element.querySelector(".ps-pane.is-presented") || this.element.querySelector(".ps-pane")
    return pane?.querySelector("select[name='pane[translation_id]']")?.value || null
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

function visibleIn(row, box) {
  const r = row.getBoundingClientRect()
  const b = box.getBoundingClientRect()
  return r.top >= b.top && r.bottom <= b.bottom
}
