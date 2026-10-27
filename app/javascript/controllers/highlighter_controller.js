import { Controller } from "@hotwired/stimulus"

// Text-selection highlighting + per-highlight study notes.
// - Select text in a verse -> a 4-color popover appears.
// - Pick a color -> POST /highlights; we wrap the range and immediately open
//   an edit popover so you can write a note while the thought is fresh.
// - Click an existing highlight -> reopen the edit popover (change color,
//   edit note, or delete). Closing it — click away, Esc, or opening another —
//   saves the note; a failed save keeps the editor open so nothing is lost.
//
// Offsets: char_start/char_end index the verse's plain text. Each verse's
// selectable text lives in one .ps-verse-text (data-offset-base says how many
// leading characters — a drop cap — sit outside it), so an offset is
// offset-base + characters of .ps-verse-text's textContent before the point.
// Strong's word spans, highlight spans etc. inside it don't change that.
//
// Touch vs mouse is decided per event (pointerType), not by sniffing the
// device: a touchscreen laptop used with a trackpad behaves like a desktop.
const COLORS = ["ochre", "sage", "cobalt", "rose"]

export default class extends Controller {
  connect() {
    this.popover = null
    this.editor = null
    this.editing = null
    this.creating = false
    this.pointerType = "mouse"
    this._onUp = this.onMouseUp.bind(this)
    this._onClick = this.onClick.bind(this)
    this._onKeyUp = this.onKeyUp.bind(this)
    this._onDocDown = this.onDocPointerDown.bind(this)
    this._onSelChange = this.onSelectionChange.bind(this)
    this._onTouchCheck = () => { if (this.isTouch()) this._scheduleTouchCheck() }
    this.element.addEventListener("mouseup", this._onUp)
    this.element.addEventListener("click", this._onClick)
    this.element.addEventListener("keyup", this._onKeyUp)
    document.addEventListener("pointerdown", this._onDocDown, true)
    // Touch devices don't fire a reliable mouseup after a text selection, so
    // watch selectionchange and, once the selection settles, raise the bar.
    document.addEventListener("selectionchange", this._onSelChange)
    // Belt and braces for Android/iOS, whose long-press event order varies by
    // browser and version: any touch release or long-press (contextmenu) also
    // schedules a check.
    document.addEventListener("touchend", this._onTouchCheck, { passive: true })
    document.addEventListener("contextmenu", this._onTouchCheck)
  }

  disconnect() {
    // The pane is being replaced (chapter / translation switch): keep the note.
    this.closeEditor({ save: true, force: true })
    this.removePopover()
    this.element.removeEventListener("mouseup", this._onUp)
    this.element.removeEventListener("click", this._onClick)
    this.element.removeEventListener("keyup", this._onKeyUp)
    document.removeEventListener("pointerdown", this._onDocDown, true)
    document.removeEventListener("selectionchange", this._onSelChange)
    document.removeEventListener("touchend", this._onTouchCheck)
    document.removeEventListener("contextmenu", this._onTouchCheck)
    clearInterval(this._watchdog)
    clearTimeout(this._selTimer)
  }

  // The last pointer used decides whether we're in touch mode. A touch also
  // starts a slow watchdog that keeps the bottom bar in step with the live
  // selection no matter which events did or didn't fire.
  notePointer(event) {
    if (!event.pointerType) return
    this.pointerType = event.pointerType
    if (this.isTouch() && !this._watchdog) {
      this._watchdog = setInterval(() => this._syncTouchBar(), 600)
    } else if (!this.isTouch() && this._watchdog) {
      clearInterval(this._watchdog)
      this._watchdog = null
    }
  }

  isTouch() {
    return this.pointerType === "touch" || this.pointerType === "pen"
  }

  // Touch path: selectionchange fires as the finger/handles move the selection.
  // Debounce so the bar only appears once the selection settles. Mouse users
  // keep using mouseup so the popover doesn't chase the caret mid-drag.
  onSelectionChange() {
    if (!this.isTouch()) return
    this._scheduleTouchCheck()
  }

  _scheduleTouchCheck() {
    clearTimeout(this._selTimer)
    this._selTimer = setTimeout(() => this._syncTouchBar(), 320)
  }

  // Bring the bottom bar in line with the current selection: show it (once) for
  // a selection inside these verses, drop it when the selection collapses or
  // moves elsewhere. Idempotent, so the watchdog can call it freely.
  _syncTouchBar() {
    const sel = window.getSelection()
    const inside = sel && !sel.isCollapsed && sel.rangeCount > 0 && this._selectionInside(sel)
    if (inside) {
      const key = this._selectionKey(sel)
      if (this.popover && this._barKey === key) return
      this._barKey = key
      this.onMouseUp()
    } else if (this.popover && this.popover.classList.contains("is-touch-bar")) {
      this._barKey = null
      this.removePopover()
    }
  }

  _selectionInside(sel) {
    const node = sel.getRangeAt(0).commonAncestorContainer
    const el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
    return !!el && this.element.contains(el)
  }

  _selectionKey(sel) {
    const r = sel.getRangeAt(0)
    return `${sel.toString()}|${r.startOffset}|${r.endOffset}`
  }

  // Keyboard selection (Shift+arrows in caret browsing) raises the popover too.
  onKeyUp(event) {
    if (event.shiftKey || event.key === "Shift") this.onMouseUp()
  }

  onMouseUp() {
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return this.removePopover()
    if (!this._selectionInside(sel)) return

    const range = sel.getRangeAt(0)
    const startC = this.verseTextOf(range.startContainer)
    const endC = this.verseTextOf(range.endContainer)

    // A selection may span several verses; collect a segment (verse + char
    // offsets) for each verse it touches, so colours/Rabbi/Share all work.
    const segments = this.selectedSegments(range, startC, endC)
    if (segments.length === 0) return this.removePopover()

    this.pending = { segments, text: sel.toString(), range: range.cloneRange(), startC, endC }
    this.showColorPopover(range.getBoundingClientRect())
  }

  // Every .ps-verse-text the range intersects, with per-verse char offsets.
  selectedSegments(range, startC, endC) {
    const all = [ ...this.element.querySelectorAll(".ps-verse-text") ]
    return all
      .filter((c) => range.intersectsNode(c))
      .map((c) => {
        const base = parseInt(c.dataset.offsetBase || "0", 10)
        const full = c.textContent.length
        const start = base + (c === startC ? this.offsetWithin(c, range.startContainer, range.startOffset) : 0)
        const end = base + (c === endC ? this.offsetWithin(c, range.endContainer, range.endOffset) : full)
        return { verseId: c.dataset.verseId, container: c, start, end }
      })
      .filter((s) => s.end > s.start)
  }

  // Click an existing highlight: open the edit popover for it.
  onClick(event) {
    const span = event.target.closest("[data-highlight-id]")
    if (!span || !this.element.contains(span)) return
    // A click that finished a drag-selection isn't a request to edit.
    const sel = window.getSelection()
    if (sel && !sel.isCollapsed && sel.toString().trim()) return
    event.preventDefault()
    this.openEditor(span)
  }

  // ---------------- color popover (new highlight) ----------------

  showColorPopover(rect) {
    this.removePopover()
    const pop = document.createElement("div")
    pop.className = "ps-hl-popover"
    pop.setAttribute("role", "toolbar")
    pop.setAttribute("aria-label", "Selected text")
    pop.style.position = "fixed"
    COLORS.forEach((c) => {
      pop.appendChild(this.button(`ps-hl-swatch ${c}`, "", `Highlight ${c}`, () => this.create(c)))
    })

    const divider = document.createElement("span")
    divider.className = "divider"
    divider.setAttribute("aria-hidden", "true")
    pop.appendChild(divider)

    // "Word study" — the selection is a single Strong's-tagged word. On touch
    // a tap on a word doesn't open the lexicon (taps are for reading and
    // selecting), so this is how phone/tablet users reach it.
    const word = this.singleStrongsWord()
    if (word) {
      pop.appendChild(this.button("x-ref", "✡ Word study", "Word study for this word", () => this.wordStudy(word)))
    }

    // "Ask the Rabbi" — explain the selected words in full context.
    pop.appendChild(this.button("x-ref", "✢ Rabbi", "Ask the Rabbi about the selected words", () => this.askRabbi()))
    // "Copy" — the selected verse text to the clipboard.
    pop.appendChild(this.button("x-ref", "⧉ Copy", "Copy the selected words", () => this.copySelection()))
    // "Share" — turn the selected words into a shareable picture + link.
    pop.appendChild(this.button("x-ref", "⤳ Share", "Share the selected words as a picture", () => this.shareSelection()))

    document.body.appendChild(pop)
    this.popover = pop
    this.positionPopover(pop, rect)
  }

  // A real, keyboard-reachable button. pointerdown is cancelled so a mouse
  // press doesn't collapse the text selection before the click lands.
  button(className, label, ariaLabel, handler) {
    const b = document.createElement("button")
    b.type = "button"
    b.className = className
    b.textContent = label
    b.setAttribute("aria-label", ariaLabel)
    b.title = ariaLabel
    b.addEventListener("pointerdown", (e) => e.preventDefault())
    b.addEventListener("click", (e) => { e.preventDefault(); e.stopPropagation(); handler() })
    return b
  }

  // Place the popover. On touch, pin it to a bottom bar (CSS) so it never stacks
  // on top of the phone's own selection menu. With a mouse, float it above the
  // selection (flipping below when it would clip the top), clamped in the viewport.
  positionPopover(pop, rect) {
    if (this.isTouch()) { pop.classList.add("is-touch-bar"); return }
    const pad = 8
    const w = pop.offsetWidth || 220
    const h = pop.offsetHeight || 40
    const left = Math.min(Math.max(pad, rect.left), window.innerWidth - w - pad)
    let top = rect.top - h - 8
    if (top < pad) top = Math.min(window.innerHeight - h - pad, rect.bottom + 10)
    pop.style.left = `${left}px`
    pop.style.top = `${top}px`
  }

  // The one Strong's-tagged word the selection sits on, if the selection is
  // just that word (give or take surrounding spaces/punctuation).
  singleStrongsWord() {
    const p = this.pending
    if (!p) return null
    const words = [ ...this.element.querySelectorAll(".ps-word[data-strongs]") ]
      .filter((w) => p.range.intersectsNode(w))
    if (words.length !== 1) return null
    const clean = (s) => s.replace(/[^\p{L}\p{N}']+/gu, " ").trim().toLowerCase()
    const picked = clean(p.text)
    return picked && clean(words[0].textContent).includes(picked) ? words[0] : null
  }

  wordStudy(word) {
    this.removePopover()
    window.dispatchEvent(new CustomEvent("lexicon:open", { detail: { href: word.dataset.href } }))
  }

  askRabbi() {
    const p = this.pending
    this.removePopover()
    if (!p || !p.segments?.length || !p.text.trim()) return
    // Pass EVERY verse the selection touched so the Rabbi explains the whole
    // span (John 3:16–18), not just the first verse.
    const verseIds = [...new Set(p.segments.map((s) => s.verseId).filter(Boolean))]
    window.dispatchEvent(new CustomEvent("rabbi:ask", {
      detail: { verseId: verseIds[0], verseIds, text: p.text }
    }))
  }

  // Copy the selected text (with its reference, when we can name it).
  async copySelection() {
    const p = this.pending
    this.removePopover()
    const text = p?.text?.trim()
    if (!text) return
    const ref = this.referenceFor(p.segments)
    const payload = ref ? `${text}\n— ${ref}` : text
    try {
      await navigator.clipboard.writeText(payload)
      this.flash("Copied")
    } catch {
      this.flash("Press and hold to copy")
    }
    window.getSelection()?.removeAllRanges()
  }

  // A human reference for the selected span, e.g. "John 3:16" or "John 3:16–18".
  referenceFor(segments) {
    const verses = segments.map((s) => s.container.closest(".ps-verse")).filter(Boolean)
    if (!verses.length) return null
    const pane = verses[0].closest(".ps-pane")
    const raw = pane?.querySelector("input[name='pane[reference]']")?.value?.trim()
    const base = raw ? raw.replace(/\s*[:.]\s*\d+\s*(?:[-–]\s*\d+)?\s*$/, "") : null
    if (!base) return null
    const first = verses[0].dataset.verseNum
    const last = verses[verses.length - 1].dataset.verseNum
    const range = first === last ? first : `${first}–${last}`
    return `${base}:${range}`
  }

  // The translation code shown in the pane holding these verses ("KJV").
  translationFor(el) {
    const select = el?.closest(".ps-pane")?.querySelector(".ps-trans-select")
    return select?.selectedOptions?.[0]?.textContent?.trim() || null
  }

  flash(text) {
    let toast = document.querySelector(".ps-toast.js-flash")
    if (!toast) {
      toast = document.createElement("div")
      toast.className = "ps-toast js-flash"
      document.body.appendChild(toast)
    }
    toast.innerHTML = `<span class="check">✦</span> `
    toast.appendChild(document.createTextNode(text))
    clearTimeout(this._toastTimer)
    toast.style.opacity = "1"
    this._toastTimer = setTimeout(() => { toast.style.opacity = "0" }, 1500)
  }

  shareSelection() {
    const p = this.pending
    this.removePopover()
    if (!p || !p.segments?.length) return
    const verses = p.segments.map((s) => s.container.closest(".ps-verse")).filter(Boolean)
    if (!verses.length) return
    const first = verses[0], last = verses[verses.length - 1]
    window.dispatchEvent(new CustomEvent("share:open", {
      detail: {
        osis: first.dataset.osis, chapter: first.dataset.chapter,
        verseStart: first.dataset.verseNum, verseEnd: last.dataset.verseNum,
        translation: this.translationFor(first),
        q: p.text.trim()
      }
    }))
  }

  removePopover() {
    if (this.popover) { this.popover.remove(); this.popover = null }
  }

  onDocPointerDown(event) {
    this.notePointer(event)
    if (this.popover && !this.popover.contains(event.target)) {
      // On touch the bar follows the selection itself (see _syncTouchBar): a
      // stray touch must not dismiss it while the words are still selected.
      if (!this.popover.classList.contains("is-touch-bar")) this.removePopover()
    }
    if (this.editor && !this.editor.contains(event.target) && !event.target.closest?.("[data-highlight-id]")) {
      this.closeEditor({ save: true })
    }
  }

  async create(color) {
    const p = this.pending
    this.removePopover()
    if (!p || !p.segments?.length || this.creating) return
    this.creating = true // a double tap must not create the highlight twice
    this.pending = null

    let made = 0, lastSpans = null, failure = null
    try {
      for (const seg of p.segments) {
        let res
        try {
          res = await this.api("POST", "/highlights", {
            highlight: { verse_id: seg.verseId, color, char_start: seg.start, char_end: seg.end }
          })
        } catch { failure = "Highlight failed — check your connection"; continue }
        if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); return }
        if (!res.ok) {
          const body = await res.json().catch(() => ({}))
          failure = body.error ? `Not saved: ${body.error}` : "Highlight failed"
          continue
        }
        const { id } = await res.json()
        made++
        const spans = this.wrapSegment(seg, p, color, id)
        if (spans.length) lastSpans = spans
      }
    } finally {
      this.creating = false
    }
    window.getSelection()?.removeAllRanges()
    if (failure) this.flash(failure)
    // For a single highlight, jump straight into its note.
    if (made === 1 && lastSpans) this.openEditor(lastSpans[0])
  }

  // Wrap one verse-segment of the selection in highlight spans. The range is
  // bounded by the original selection at the start/end verse and the whole
  // verse text in between. Rather than surroundContents (which throws when the
  // range crosses element boundaries such as Strong's word spans), wrap each
  // intersected text node on its own — every piece carries the same id.
  wrapSegment(seg, p, color, id) {
    const c = seg.container
    if (!c.isConnected) return []
    const r = document.createRange()
    try {
      if (c === p.startC && c.contains(p.range.startContainer)) r.setStart(p.range.startContainer, p.range.startOffset)
      else r.setStart(c, 0)
      if (c === p.endC && c.contains(p.range.endContainer)) r.setEnd(p.range.endContainer, p.range.endOffset)
      else r.setEnd(c, c.childNodes.length)
    } catch { return [] }

    const nodes = []
    const walker = document.createTreeWalker(c, NodeFilter.SHOW_TEXT)
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (r.intersectsNode(n)) nodes.push(n)
    }

    const spans = []
    for (const node of nodes) {
      let from = node === r.startContainer ? r.startOffset : 0
      let to = node === r.endContainer ? r.endOffset : node.length
      if (to <= from) continue
      let target = node
      if (to < target.length) target.splitText(to)
      if (from > 0) target = target.splitText(from)
      const span = document.createElement("span")
      span.className = `hl-${color}`
      span.dataset.highlightId = id
      span.dataset.note = ""
      target.parentNode.insertBefore(span, target)
      span.appendChild(target)
      spans.push(span)
    }
    return spans
  }

  spansFor(id) {
    return [ ...document.querySelectorAll(`[data-highlight-id="${CSS.escape(String(id))}"]`) ]
  }

  // ---------------- edit popover (existing highlight) ----------------

  async openEditor(span) {
    if (this.editing?.id === span.dataset.highlightId) return
    if (this.editor) {
      const closed = await this.closeEditor({ save: true })
      if (!closed) return // its note failed to save — leave that editor up
    }
    this.removePopover()
    const id = span.dataset.highlightId
    const rect = span.getBoundingClientRect()
    const currentColor = (span.className.match(/hl-(\w+)/) || [])[1] || "ochre"
    const currentNote = span.dataset.note || ""

    const box = document.createElement("div")
    box.className = "ps-hl-edit"
    box.setAttribute("role", "dialog")
    box.setAttribute("aria-label", "Highlight note")
    box.innerHTML = `
      <textarea class="ps-hl-note" rows="3" placeholder="Note on this highlight…" aria-label="Note on this highlight"></textarea>
      <div class="ps-hl-edit-row">
        <div class="ps-hl-edit-swatches" role="group" aria-label="Highlight colour"></div>
        <span class="ps-hl-edit-status" role="status" aria-live="polite"></span>
        <button type="button" class="ps-hl-del" title="Remove highlight" aria-label="Remove highlight">&#10005;</button>
      </div>
    `
    box.style.position = "fixed"
    box.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - 320))}px`
    box.style.top = `${Math.min(window.innerHeight - 160, rect.bottom + 6)}px`
    document.body.appendChild(box)

    const textarea = box.querySelector(".ps-hl-note")
    textarea.value = currentNote
    setTimeout(() => textarea.focus(), 20)
    // Esc closes the editor — and saves, like clicking away does.
    textarea.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); this.closeEditor({ save: true }) }
    })
    box.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && e.target !== textarea) { e.stopPropagation(); this.closeEditor({ save: true }) }
    })

    // change color = immediate PATCH; only repaint once the server agrees
    const group = box.querySelector(".ps-hl-edit-swatches")
    COLORS.forEach((color) => {
      const sw = this.button(`ps-hl-swatch ${color}${color === currentColor ? " is-on" : ""}`, "",
        `Change colour to ${color}`, async () => {
          const saved = await this.patchHighlight(id, { color })
          if (!saved) return this.setEditorStatus("Colour not saved")
          this.setEditorStatus("")
          this.spansFor(id).forEach((s) => {
            const hasNote = (s.dataset.note || "").length > 0
            s.className = `hl-${color}${hasNote ? " has-note" : ""}`
          })
          group.querySelectorAll(".ps-hl-swatch").forEach((s) => {
            s.classList.toggle("is-on", s === sw)
            s.setAttribute("aria-pressed", String(s === sw))
          })
        })
      sw.setAttribute("aria-pressed", String(color === currentColor))
      group.appendChild(sw)
    })

    // delete
    const del = box.querySelector(".ps-hl-del")
    del.addEventListener("pointerdown", (e) => e.preventDefault())
    del.addEventListener("click", async (e) => {
      e.preventDefault()
      const ok = await this.destroy(id)
      if (!ok) return this.setEditorStatus("Not removed — try again")
      // close without saving: the highlight (and its note) is gone
      if (this.editor === box) { box.remove(); this.editor = null; this.editing = null }
    })

    this.editor = box
    this.editing = { id, span, originalNote: currentNote, textarea }
  }

  setEditorStatus(text) {
    const el = this.editor?.querySelector(".ps-hl-edit-status")
    if (el) el.textContent = text
  }

  // Resolves true once the editor is closed, false if its note failed to save
  // (the editor stays open, saying so, so the words aren't lost). With
  // force (the pane is going away) the editor is removed regardless.
  closeEditor({ save, force = false }) {
    if (this._closing) return this._closing
    if (!this.editor) return Promise.resolve(true)
    this._closing = this._closeEditor({ save, force }).finally(() => { this._closing = null })
    return this._closing
  }

  async _closeEditor({ save, force }) {
    const editor = this.editor
    const editing = this.editing
    if (save && editing) {
      const value = editing.textarea.value
      if (value !== editing.originalNote) {
        this.setEditorStatus("Saving…")
        const saved = await this.patchHighlight(editing.id, { note: value }, { keepalive: force })
        if (!saved && !force) {
          this.setEditorStatus("Save failed")
          return false
        }
        if (saved) {
          editing.originalNote = value
          this.spansFor(editing.id).forEach((s) => {
            s.dataset.note = value
            s.classList.toggle("has-note", value.length > 0)
          })
        }
      }
    }
    editor.remove()
    if (this.editor === editor) { this.editor = null; this.editing = null }
    return true
  }

  async patchHighlight(id, fields, { keepalive = false } = {}) {
    try {
      const res = await this.api("PATCH", `/highlights/${id}`, { highlight: fields }, { keepalive })
      if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); return null }
      if (!res.ok) return null
      return await res.json()
    } catch { return null }
  }

  async destroy(id) {
    try {
      const res = await this.api("DELETE", `/highlights/${id}`)
      if (!res.ok && res.status !== 404) return false
    } catch { return false }
    this.spansFor(id).forEach((s) => {
      const parent = s.parentNode
      s.replaceWith(...s.childNodes)
      parent?.normalize()
    })
    return true
  }

  // ---------------- helpers ----------------

  verseTextOf(node) {
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node
    return el ? el.closest(".ps-verse-text") : null
  }

  offsetWithin(container, node, offset) {
    const pre = document.createRange()
    pre.selectNodeContents(container)
    pre.setEnd(node, offset)
    return pre.toString().length
  }

  api(method, url, body, { keepalive = false } = {}) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const opts = { method, keepalive, headers: { "X-CSRF-Token": token || "", Accept: "application/json" } }
    if (body !== undefined) {
      opts.headers["Content-Type"] = "application/json"
      opts.body = JSON.stringify(body)
    }
    return fetch(url, opts)
  }
}
