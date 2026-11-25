import { Controller } from "@hotwired/stimulus"
import { pictureDisplay } from "../lib/picture_fit"
import { warmLocal, localState } from "../lib/offline/local_pane"
import { referenceLabel } from "../lib/offline/reference_parser"
import { bookText, allBookTexts, storedManifest } from "../lib/offline/store"
import { rankVerses, queryWords } from "../lib/scripture_search"
import { chapterVerses } from "../lib/offline/pane_renderer"
import { quickFetch } from "../lib/offline/network"
import { queueKey } from "../lib/offline/setlist_state"
import { songSlides } from "../lib/song_sheet"
import { richPreviewNodes } from "../lib/slides/rich_slides"
import { wordFromDetail } from "../lib/root_words"
import { renderPreviewWord } from "../lib/root_word_slide"
import { DEFAULTS as SET_DEFAULTS, setLabel } from "../lib/slides/scripture_set"
import { passagesFor, copyText } from "../lib/slides/item_words"
import { combineParts, clipboardText } from "../lib/slides/combine"

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
const RANGE_MAX = 6 // presentation_controller's: a range this long goes up as one slide
const SEARCH_DELAY_MS = 180
const SEARCH_LIMIT = 30

export default class extends Controller {
  static targets = [ "console", "liveLabel", "queueLive", "previewCard", "previewLabel", "previewText", "queuePreview",
    "goLive", "verseList", "verseListTitle", "verseRows", "editPreview", "copyPreview" ]

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
      "preview:typing": (e) => this._typed(e.detail?.raw, e.detail?.mode, e.detail),
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
    if (detail.source !== "list") this._clearPicks()
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
    // (rich: the console's Preview miniature draws a deck / set / seminar slide itself.)
    window.dispatchEvent(new CustomEvent("preview:changed", { detail: { cid: preview.cid || null, label: preview.label, rich: preview.rich || null } }))
    // On a narrow screen the queue is a drawer: open it so the preview shows (it doesn't dim the screen).
    if (!this._visible()) window.dispatchEvent(new CustomEvent("setlist:open"))

    this.previewTextTarget.classList.remove("is-deck")
    this.previewTextTarget.dataset.span = ""
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
    // A range goes up as one slide: the console's miniature shows all of it.
    const range = p.verseStart != null && verses.length > 1 && verses.length <= RANGE_MAX && !p.openEnded
    this.previewTextTarget.dataset.span = range ? String(verses.length) : ""
    const shown = verses.slice(0, PREVIEW_MAX_VERSES)
    const nodes = shown.map((v) => {
      const span = el("span", "v")
      span.append(el("sup", null, String(v.num)), document.createTextNode(` ${v.text} `))
      return span
    })
    if (verses.length > shown.length) nodes.push(el("span", "muted", `… ${verses.length - shown.length} more verse${verses.length - shown.length === 1 ? "" : "s"}`))
    if (chapter.foreign) nodes.push(el("span", "muted tag", chapter.foreign))
    this.previewTextTarget.replaceChildren(...(nodes.length ? nodes : [ el("span", "muted", "No such verse in this chapter") ]))
    // Picked from the search matches: the matches stay (a double-click's second
    // click must land on the same row; the next pick is one click away).
    if (preview.source !== "found") this._showList(chapter, { focus: p.verseStart })
  }

  // A song / thought: every slide in projection order (EasyWorship's slide
  // list), its section label small. Clicking a slide puts the song on screen at
  // that slide; while the song is live, the slide on screen is marked.
  _paintSlide(preview) {
    const word = wordFromDetail(preview)
    if (word) {
      this.previewTextTarget.classList.remove("is-slides")
      renderPreviewWord(this.previewTextTarget, word)
      return
    }
    if (preview.rich) { this._paintRich(preview); return }
    const nodes = []
    if (preview.image) {
      const img = el("img", "thumb")
      img.src = preview.image
      img.alt = ""
      const { fit, zoom } = pictureDisplay(preview.picture)
      img.dataset.fit = fit
      img.dataset.zoom = String(zoom)
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

  // A scripture set, presentation or seminar deck: its slides (a deck's as
  // thumbnails), each one click from the screen.
  _paintRich(preview) {
    const nodes = richPreviewNodes(preview.rich, (i, label, content) => {
      const btn = el("button", "slide")
      btn.type = "button"
      btn.dataset.index = String(i)
      btn.dataset.action = "preview#slideLive"
      btn.title = "Put this slide on the screen"
      const txt = el("span", "txt")
      txt.append(content)
      btn.append(el("span", "lbl", label), txt)
      return btn
    })
    this.previewTextTarget.classList.toggle("is-slides", nodes.length > 0)
    this.previewTextTarget.classList.toggle("is-deck", preview.rich.type === "deck")
    this.previewTextTarget.replaceChildren(...(nodes.length ? nodes : [ el("span", "muted", "No slides yet") ]))
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
    window.dispatchEvent(new CustomEvent("projector:ensure")) // opens it on the second screen if needed
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

  // ---- Edit (combine into one slide) / Copy what is in Preview ---------------------------

  // A scripture or scripture slide in Preview: its words in the combine editor
  // (lib/slides/combine) — edit, emphasise, save as one slide. A slide made
  // there opens again for editing.
  editSlide(event) {
    event?.preventDefault?.()
    const p = this._preview
    const sources = this._previewSources()
    if (!p || !sources) return
    let item = null
    if (p.cid && p.rich?.data?.combined) {
      window.dispatchEvent(new CustomEvent("setlist:request-items", { detail: { reply: (items) => { item = items.find((i) => i.cid === p.cid) || null } } }))
    }
    window.dispatchEvent(new CustomEvent("queue-tool:open", { detail: item
      ? { tool: "combine", item }
      : { tool: "combine", sources, translation: this._translationCode() } }))
  }

  async copy(event) {
    event?.preventDefault?.()
    const sources = this._previewSources()
    if (!sources) return
    const { passages } = await passagesFor(sources, { translation: this._translationCode() })
    if (!passages.length) { this._flashCopy("No words to copy"); return }
    const ok = await copyText(clipboardText(combineParts(passages)))
    this._flashCopy(ok ? "Copied" : "Couldn't copy")
  }

  _flashCopy(text) {
    if (!this.hasCopyPreviewTarget) return
    const btn = this.copyPreviewTarget
    btn.textContent = text
    clearTimeout(this._copyTimer)
    this._copyTimer = setTimeout(() => { btn.textContent = "Copy" }, 1600)
  }

  _previewSources() {
    const p = this._preview
    if (!p) return null
    if (p.kind === "scripture") return [ { kind: "scripture", reference: p.label || p.reference } ]
    if (p.rich?.type === "set") return [ { kind: "scripture_set", data: p.rich.data } ]
    return null
  }

  _translationCode() {
    const pane = this.element.querySelector(".ps-pane.is-presented") || this.element.querySelector(".ps-pane")
    return pane?.querySelector("select[name='pane[translation_id]'] option:checked")?.textContent?.trim() || null
  }

  _paintQueueButtons() {
    const words = !!this._previewSources()
    if (this.hasEditPreviewTarget) this.editPreviewTarget.hidden = !words
    if (this.hasCopyPreviewTarget) this.copyPreviewTarget.hidden = !words
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
      this.liveLabelTarget.textContent = `${state.slide.word ? "ℵ" : "♫"} ${this._live.label}`
    } else {
      const ref = (state.reference || "").trim()
      const p = localState().parse?.(ref)
      const first = state.verseStart
      const last = state.verseEnd ?? first
      let label = ref
      if (p?.valid && first) label = referenceLabel({ ...p, chapterEnd: p.chapter, verseStart: first, verseEnd: last, openEnded: false })
      else if (first) label = `${ref.replace(/\s*[:.]\s*\d.*$/, "")}:${first}${last && last !== first ? `-${last}` : ""}`
      const moved = !this._live || this._live.osis !== p?.osis || this._live.chapter !== p?.chapter
      // The list was showing the live chapter and Next/Prev walked into the
      // neighbouring one: the list turns the page with it, picking or not.
      const turned = moved && !!this._live && this._liveInList()
      this._live = { label, osis: p?.osis, chapter: p?.chapter, first, last, reference: ref }
      this.liveLabelTarget.textContent = label + (state.blank ? " · screen blanked" : "")
      if (moved && p?.valid) this._followLive(ref, { turned })
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
  async _followLive(reference, { turned = false } = {}) {
    const pinned = () => this._listPinnedAt && performance.now() - this._listPinnedAt < 8000
    if (pinned() && !turned) return
    const pinnedAt = this._listPinnedAt
    const chapter = await this._chapter(reference)
    // The operator may have typed a reference while the chapter loaded.
    const typedSince = this._listPinnedAt !== pinnedAt
    if (!chapter || typedSince || (pinned() && !turned)) return
    this._showList(chapter, { pinned: false })
    if (turned) this._flashTitle()
  }

  // A soft glow on the list's chapter label as it turns to the next chapter.
  _flashTitle() {
    const title = this.verseListTitleTarget
    title.classList.remove("is-turned")
    void title.offsetWidth // restart the animation
    title.classList.add("is-turned")
    clearTimeout(this._turnTimer)
    this._turnTimer = setTimeout(() => title.classList.remove("is-turned"), 1600)
  }

  // ---- the chapter verse list -------------------------------------------------------

  // `mode` (lib/scripture_mode): "words" always searches the words,
  // "reference" never does (a text that isn't a reference lists nothing),
  // "auto" (or none, e.g. the Go box) guesses as before.
  // `book` ({osis, name, strict}): the words searched inside that book only
  // (console_library's book scope); `query` is the box's whole text.
  async _typed(raw, mode = "auto", { book = null, query = null } = {}) {
    const text = (raw || "").trim()
    clearTimeout(this._searchTimer)
    this._searchMode = mode
    if (book) {
      this._typedSeq = (this._typedSeq || 0) + 1
      if (queryWords(text).length) this._searchTimer = setTimeout(() => this._searchTyped(text, { book, query: query || text }), SEARCH_DELAY_MS)
      return
    }
    if (!text || (mode !== "words" && /^\d+$/.test(text))) return
    const p = mode === "words" ? null : localState().parse?.(text)
    if (mode === "reference" && p && !p.valid) { this._typedSeq = (this._typedSeq || 0) + 1; return }
    if (mode === "words" || (mode !== "reference" && !p?.valid)) {
      // Words, not a reference: the matching verses list as you type.
      this._typedSeq = (this._typedSeq || 0) + 1
      this._searchTimer = setTimeout(() => this._searchTyped(text), SEARCH_DELAY_MS)
      return
    }
    const seq = (this._typedSeq = (this._typedSeq || 0) + 1)
    const chapter = await this._chapter(text)
    if (seq !== this._typedSeq || !chapter) return
    this._showList(chapter, { focus: p.verseStart, target: p.verseStart })
  }

  _showList(chapter, { focus = null, target = null, pinned = true } = {}) {
    if (!this.hasVerseListTarget) return
    if (pinned) this._listPinnedAt = performance.now()
    const p = chapter.parsed
    delete this.verseListTarget.dataset.mode
    const same = !this._list?.search && this._list && this._list.osis === p.osis && this._list.chapter === p.chapter && this._list.code === chapter.code
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
    if (!this._list || this._list.search || !this.hasVerseRowsTarget) return
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

  // Click previews a verse. EasyWorship's multi-select: Shift+click previews
  // every verse from the last one clicked to this one ("Gen 2:1-3", one
  // slide); Ctrl/⌘+click adds or removes single verses — side by side they
  // make a range, apart they make a scripture slide ("Gen 2:1, 5").
  pickVerse(event) {
    const row = event.currentTarget.closest(".vrow")
    if (!row?.dataset.label) return
    const n = Number(row.dataset.num)
    if (event.shiftKey && this._pickAnchor != null && this._pickChapter === this._listKey()) {
      event.preventDefault()
      const [ a, b ] = [ Math.min(this._pickAnchor, n), Math.max(this._pickAnchor, n) ]
      this._picks = new Set(Array.from({ length: b - a + 1 }, (_, i) => a + i))
    } else if ((event.ctrlKey || event.metaKey) && this._pickChapter === this._listKey() && this._picks?.size) {
      event.preventDefault()
      if (this._picks.has(n) && this._picks.size > 1) this._picks.delete(n)
      else this._picks.add(n)
      this._pickAnchor = n
    } else {
      this._picks = new Set([ n ])
      this._pickAnchor = n
      this._pickChapter = this._listKey()
    }
    this._loadPicks()
  }

  // Double-click: the selection (or just this verse) straight to the screen.
  liveVerse(event) {
    const row = event.currentTarget.closest(".vrow")
    if (!row?.dataset.label) return
    if (!this._picks?.has(Number(row.dataset.num))) {
      this._picks = new Set([ Number(row.dataset.num) ])
      this._pickAnchor = Number(row.dataset.num)
      this._pickChapter = this._listKey()
    }
    this._loadPicks()
    this.goLive()
  }

  _listKey() {
    return this._list ? `${this._list.osis}|${this._list.chapter}|${this._list.code}` : null
  }

  _clearPicks() {
    this._picks = null
    this._pickAnchor = null
    this.hasVerseRowsTarget && this.verseRowsTarget.querySelectorAll(".vrow.is-picked").forEach((r) => r.classList.remove("is-picked"))
  }

  // The picked verses into Preview: one verse, a range, or (verses apart) a
  // scripture slide with all of them.
  _loadPicks() {
    const nums = Array.from(this._picks || []).sort((a, b) => a - b)
    if (!nums.length || !this._list) return
    const { bookName, chapter } = this._list
    this.verseRowsTarget.querySelectorAll(".vrow").forEach((r) => r.classList.toggle("is-picked", nums.length > 1 && this._picks.has(Number(r.dataset.num))))
    const first = nums[0]
    const last = nums[nums.length - 1]
    if (last - first + 1 === nums.length) {
      const reference = `${bookName} ${chapter}:${first}${last > first ? `-${last}` : ""}`
      this.load({ kind: "scripture", reference, source: "list" })
      if (nums.length > RANGE_MAX) this._hintLong(nums.length)
      return
    }
    const verses = nums.map((n) => {
      const row = this._rowFor(n)
      return { c: chapter, n, text: row?.querySelector(".txt")?.textContent || "" }
    })
    const label = `${bookName} ${chapter}:${compactNums(nums)}`
    const data = { ...SET_DEFAULTS, refs: [ { reference: label, label, translation: this._list.code || null, verses } ] }
    this.load({ kind: "slide", itemKind: "scripture_set", label, title: setLabel(data) || label, body: "", rich: { type: "set", data }, source: "list" })
  }

  _hintLong(count) {
    this.previewLabelTarget.textContent += ` · ${count} verses — ${RANGE_MAX} or fewer go up as one slide; Next walks the rest`
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
      if (next) next.querySelector(".pick")?.focus()
      else this._turnListPage(event.key === "ArrowDown" ? 1 : -1) // off the chapter: the one next to it
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

  // ↑ on a chapter's first verse / ↓ on its last: the list turns to the chapter
  // before / after (across books: Matthew 1 ↑ → Malachi 4), the keyboard on
  // its last / first verse — the same continuation as Next / Prev on screen.
  async _turnListPage(direction) {
    if (!this._list || this._list.search) return
    const reference = await neighbourChapter(this._list.osis, this._list.chapter, direction)
    if (!reference) return
    const chapter = await this._chapter(reference)
    if (!chapter?.verses?.length) return
    this._showList(chapter)
    this._flashTitle()
    const rows = this.verseRowsTarget.querySelectorAll(".vrow .pick")
    const target = direction > 0 ? rows[0] : rows[rows.length - 1]
    target?.focus()
    target?.closest(".vrow")?.scrollIntoView?.({ block: "nearest" })
  }

  // ---- search as you type ----------------------------------------------------------------
  // Words that aren't a reference ("neither male nor female") list the
  // matching verses at once — the downloaded Bible first (no network), the
  // server's search when this Bible isn't on the device. Ranked like the
  // Search page: the words side by side, then all of them, then some.
  // Click previews, double-click goes live; Enter in the box previews the
  // first verse holding every word (console_library).

  // In one book (`book`): nothing with all the words there and the book was
  // only guessed from the first word ("mark of the beast") → every book.
  async _searchTyped(text, { book = null, query = null } = {}) {
    if (!this.hasVerseListTarget || !queryWords(text).length) return
    const seq = this._typedSeq
    let found = (await this._searchDevice(text, book)) || (await this._searchServer(text, book))
    if (seq !== this._typedSeq) return
    if (book && found && !book.strict && !found.hits.some((h) => h.tier !== "partial")) {
      const wider = (await this._searchDevice(query, null)) || (await this._searchServer(query, null))
      if (seq !== this._typedSeq) return
      if (wider) { this._showFound(query, wider, { key: query, widened: book }); return }
    }
    if (!found) return
    this._showFound(text, found, { key: query || text, book })
  }

  async _searchDevice(text, book = null) {
    try {
      const local = await warmLocal()
      const downloaded = local.downloaded || []
      if (!downloaded.length) return null
      const t = local.translations?.find((x) => String(x.id) === String(this._translationId()))
      const code = (t && downloaded.find((d) => d.code === t.code)?.code) || null
      if (!code && navigator.onLine !== false) return null // the server has this translation
      const pick = code || downloaded[0].code
      this._bibles ||= new Map()
      if (!this._bibles.has(pick)) {
        const [ records, manifest ] = await Promise.all([ allBookTexts(pick), storedManifest() ])
        const canon = manifest?.canon || []
        this._bibles.set(pick, { records, names: new Map(canon.map((b) => [ b.osis, b.name ])), order: new Map(canon.map((b, i) => [ b.osis, i ])) })
      }
      const bible = this._bibles.get(pick)
      const { hits } = rankVerses(bible.records, text, { order: bible.order, limit: SEARCH_LIMIT, books: book ? new Set([ book.osis ]) : null })
      return {
        translation: pick,
        hits: hits.map((h) => ({ reference: `${bible.names.get(h.osis) || h.osis} ${h.chapter}:${h.num}`, text: h.text, parts: h.parts, tier: h.tier }))
      }
    } catch { return null }
  }

  async _searchServer(text, book = null) {
    try {
      const url = `/search.json?q=${encodeURIComponent(text)}&translation=${encodeURIComponent(this._translationId() || "")}${book ? `&in=${encodeURIComponent(book.osis)}` : ""}`
      const { res, body } = await quickFetch(url, { headers: { Accept: "application/json" } }, { timeoutMs: CHAPTER_TIMEOUT_MS, read: "json" })
      if (!res.ok || !body?.ok) return null
      return { translation: body.translation, hits: body.hits || [] }
    } catch { return null }
  }

  // `key`: the box's text the list answers (console_library waits for it);
  // `book`: searched in that book; `widened`: the book had none, all books shown.
  _showFound(text, { translation, hits }, { key = text, book = null, widened = null } = {}) {
    this._listPinnedAt = performance.now()
    this._list = { search: text }
    this._clearPicks()
    this.verseListTarget.dataset.mode = "search"
    this.verseListTarget.dataset.query = key
    if (book) this.verseListTarget.dataset.book = book.osis
    else delete this.verseListTarget.dataset.book
    const strong = hits.filter((h) => h.tier !== "partial").length
    const where = book ? ` in ${book.name}` : ""
    const note = widened ? `Nothing in ${widened.name} — every book: ` : ""
    this.verseListTitleTarget.textContent = hits.length
      ? `${note}${strong ? `${strong}${hits.length >= SEARCH_LIMIT && strong === hits.length ? "+" : ""}` : "No"} verse${strong === 1 ? "" : "s"} with “${text}”${where}${strong < hits.length ? ` · then some of the words` : ""}${translation ? ` · ${translation}` : ""}`
      : `No verses with “${text}”${where}${translation ? ` · ${translation}` : ""}${this._searchMode === "words" || book ? "" : " — Enter asks the study assistant"}`
    this.verseRowsTarget.replaceChildren(...hits.map((h) => {
      const row = el("li", "vrow is-found")
      row.classList.toggle("is-strong", h.tier !== "partial")
      row.dataset.label = h.reference
      const pick = el("button", "pick")
      pick.type = "button"
      pick.dataset.action = "click->preview#pickFound dblclick->preview#liveFound keydown->preview#rowKey"
      pick.title = `${h.reference} — click to preview, double-click to go live`
      const txt = el("span", "txt")
      if (h.parts?.length) h.parts.forEach((part) => txt.append(part.mark ? el("mark", null, part.text) : document.createTextNode(part.text)))
      else markWords(txt, h.text, text)
      pick.append(el("span", "ref", h.reference), txt)
      const add = el("button", "add", "+")
      add.type = "button"
      add.dataset.action = "preview#queueVerse"
      add.title = `Add ${h.reference} to the queue`
      row.append(pick, add)
      return row
    }))
    this.verseListTarget.hidden = false
    this.verseRowsTarget.scrollTop = 0
    this._paintQueueButtons()
  }

  pickFound(event) {
    const row = event.currentTarget.closest(".vrow")
    if (!row?.dataset.label) return
    this.verseRowsTarget.querySelectorAll(".vrow.is-found.is-preview").forEach((r) => r.classList.remove("is-preview"))
    row.classList.add("is-preview")
    this.load({ kind: "scripture", reference: row.dataset.label, source: "found" })
  }

  liveFound(event) {
    this.pickFound(event)
    this.goLive()
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

// "Malachi 4" before Matthew 1, "Exodus 1" after Genesis 50 — the canon the
// device keeps (offline manifest); null at either end of the Bible.
async function neighbourChapter(osis, chapter, direction) {
  const canon = (await storedManifest().catch(() => null))?.canon || []
  const i = canon.findIndex((b) => b.osis === osis)
  if (i < 0) return null
  const book = canon[i]
  if (direction > 0) {
    if (chapter < book.chapters) return `${book.name} ${chapter + 1}`
    return canon[i + 1] ? `${canon[i + 1].name} 1` : null
  }
  if (chapter > 1) return `${book.name} ${chapter - 1}`
  return canon[i - 1] ? `${canon[i - 1].name} ${canon[i - 1].chapters}` : null
}

function visibleIn(row, box) {
  const r = row.getBoundingClientRect()
  const b = box.getBoundingClientRect()
  return r.top >= b.top && r.bottom <= b.bottom
}

// [1, 2, 3, 5] → "1-3, 5"
function compactNums(nums) {
  const out = []
  for (let i = 0; i < nums.length; i++) {
    let j = i
    while (j + 1 < nums.length && nums[j + 1] === nums[j] + 1) j++
    out.push(j > i ? `${nums[i]}-${nums[j]}` : `${nums[i]}`)
    i = j
  }
  return out.join(", ")
}

// The typed words marked in a verse (server results come as plain text).
function markWords(node, text, query) {
  const words = queryWords(query).map((w) => w.stem.replace(/[^a-z]/gi, "")).filter((w) => w.length > 2)
  if (!words.length) { node.textContent = text; return }
  const re = new RegExp(`\\b(${words.join("|")})[a-z]*`, "gi")
  let last = 0
  for (const m of text.matchAll(re)) {
    node.append(document.createTextNode(text.slice(last, m.index)), el("mark", null, m[0]))
    last = m.index + m[0].length
  }
  node.append(document.createTextNode(text.slice(last)))
}
