import { Controller } from "@hotwired/stimulus"

// Text-selection highlighting + per-highlight study notes.
// - Select text in a verse -> a 4-color popover appears.
// - Pick a color -> POST /highlights; we wrap the range and immediately open
//   an edit popover so you can write a note while the thought is fresh.
// - Click an existing highlight -> reopen the edit popover (change color,
//   edit note, or delete).
const COLORS = ["ochre", "sage", "cobalt", "rose"]

export default class extends Controller {
  connect() {
    this.popover = null
    this.editor = null
    this.editing = null
    this._onUp = this.onMouseUp.bind(this)
    this._onDocDown = this.onDocPointerDown.bind(this)
    this.element.addEventListener("mouseup", this._onUp)
    this.element.addEventListener("click", this.onClick.bind(this))
    document.addEventListener("pointerdown", this._onDocDown, true)
  }

  disconnect() {
    this.closeEditor({ save: false })
    this.removePopover()
    document.removeEventListener("pointerdown", this._onDocDown, true)
  }

  onMouseUp() {
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return this.removePopover()

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
        let start, end
        if (c === startC && c === endC) {
          start = base + this.offsetWithin(c, range.startContainer, range.startOffset)
          end = base + this.offsetWithin(c, range.endContainer, range.endOffset)
        } else if (c === startC) {
          start = base + this.offsetWithin(c, range.startContainer, range.startOffset)
          end = base + full
        } else if (c === endC) {
          start = base
          end = base + this.offsetWithin(c, range.endContainer, range.endOffset)
        } else {
          start = base
          end = base + full
        }
        return { verseId: c.dataset.verseId, container: c, start, end }
      })
      .filter((s) => s.end > s.start)
  }

  // Click an existing highlight: open the edit popover for it.
  onClick(event) {
    const span = event.target.closest("[data-highlight-id]")
    if (!span) return
    event.preventDefault()
    this.openEditor(span)
  }

  // ---------------- color popover (new highlight) ----------------

  showColorPopover(rect) {
    this.removePopover()
    const pop = document.createElement("div")
    pop.className = "ps-hl-popover"
    pop.style.position = "fixed"
    pop.style.left = `${Math.max(8, rect.left)}px`
    pop.style.top = `${Math.max(8, rect.top - 44)}px`
    COLORS.forEach((c) => {
      const sw = document.createElement("span")
      sw.className = `ps-hl-swatch ${c}`
      sw.dataset.color = c
      sw.addEventListener("mousedown", (e) => { e.preventDefault(); this.create(c) })
      pop.appendChild(sw)
    })

    // "Ask the Rabbi" — explain the selected words in full context. Reading the
    // selection requires no account, so this is offered to everyone.
    const divider = document.createElement("span")
    divider.className = "divider"
    pop.appendChild(divider)

    const rabbi = document.createElement("span")
    rabbi.className = "x-ref"
    rabbi.textContent = "✢ Rabbi"
    rabbi.addEventListener("mousedown", (e) => { e.preventDefault(); this.askRabbi() })
    pop.appendChild(rabbi)

    // "Share" — turn the selected words into a shareable picture + link.
    const share = document.createElement("span")
    share.className = "x-ref"
    share.textContent = "⤳ Share"
    share.addEventListener("mousedown", (e) => { e.preventDefault(); this.shareSelection() })
    pop.appendChild(share)

    document.body.appendChild(pop)
    this.popover = pop
  }

  askRabbi() {
    const p = this.pending
    this.removePopover()
    if (!p || !p.segments?.length || !p.text.trim()) return
    // The Rabbi reads the whole chapter for context; the first verse anchors it.
    window.dispatchEvent(new CustomEvent("rabbi:ask", {
      detail: { verseId: p.segments[0].verseId, text: p.text }
    }))
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
        q: p.text.trim()
      }
    }))
  }

  removePopover() {
    if (this.popover) { this.popover.remove(); this.popover = null }
  }

  onDocPointerDown(event) {
    if (this.popover && !this.popover.contains(event.target)) this.removePopover()
    if (this.editor && !this.editor.contains(event.target) && !event.target.closest("[data-highlight-id]")) {
      this.closeEditor({ save: true })
    }
  }

  async create(color) {
    const p = this.pending
    this.removePopover()
    if (!p || !p.segments?.length) return

    let made = 0, lastSpan = null
    for (const seg of p.segments) {
      let res
      try {
        res = await this.api("POST", "/highlights", {
          highlight: { verse_id: seg.verseId, color, char_start: seg.start, char_end: seg.end }
        })
      } catch { continue }
      if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); return }
      if (!res.ok) continue
      const { id } = await res.json()
      made++
      const span = this.wrapSegment(seg, p, color, id)
      if (span) lastSpan = span
    }
    window.getSelection()?.removeAllRanges()
    // For a single highlight, jump straight into its note; multi-verse spans
    // are left as-is (they re-render fully on the next load).
    if (made === 1 && lastSpan) this.openEditor(lastSpan)
  }

  // Wrap one verse-segment of the selection in a highlight span. Builds a range
  // bounded by the original selection at the start/end verse, and the whole
  // verse text in between. surroundContents throws across element boundaries
  // (e.g. Strong's word spans) — caught, so it renders on the next load.
  wrapSegment(seg, p, color, id) {
    const c = seg.container
    const r = document.createRange()
    if (c === p.startC) r.setStart(p.range.startContainer, p.range.startOffset)
    else r.setStart(c, 0)
    if (c === p.endC) r.setEnd(p.range.endContainer, p.range.endOffset)
    else r.setEnd(c, c.childNodes.length)

    const span = document.createElement("span")
    span.className = `hl-${color}`
    span.dataset.highlightId = id
    span.dataset.note = ""
    try { r.surroundContents(span); return span } catch { return null }
  }

  // ---------------- edit popover (existing highlight) ----------------

  openEditor(span) {
    this.closeEditor({ save: false })
    this.removePopover()
    const rect = span.getBoundingClientRect()
    const currentColor = (span.className.match(/hl-(\w+)/) || [])[1] || "ochre"
    const currentNote = span.dataset.note || ""

    const box = document.createElement("div")
    box.className = "ps-hl-edit"
    box.innerHTML = `
      <textarea class="ps-hl-note" rows="3" placeholder="Note on this highlight…"></textarea>
      <div class="ps-hl-edit-row">
        <div class="ps-hl-edit-swatches">
          ${COLORS.map(c => `<span class="ps-hl-swatch ${c}${c === currentColor ? " is-on" : ""}" data-color="${c}"></span>`).join("")}
        </div>
        <button type="button" class="ps-hl-del" title="Remove highlight">&#10005;</button>
      </div>
    `
    box.style.position = "fixed"
    box.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - 320))}px`
    box.style.top = `${Math.min(window.innerHeight - 160, rect.bottom + 6)}px`
    document.body.appendChild(box)

    const textarea = box.querySelector(".ps-hl-note")
    textarea.value = currentNote
    setTimeout(() => textarea.focus(), 20)

    // change color = immediate PATCH
    box.querySelectorAll(".ps-hl-swatch").forEach(sw => {
      sw.addEventListener("mousedown", async (e) => {
        e.preventDefault()
        const color = sw.dataset.color
        await this.patchHighlight(span.dataset.highlightId, { color })
        const hasNote = (span.dataset.note || "").length > 0
        span.className = `hl-${color}${hasNote ? " has-note" : ""}`
        box.querySelectorAll(".ps-hl-swatch").forEach(s => s.classList.toggle("is-on", s === sw))
      })
    })

    // delete
    box.querySelector(".ps-hl-del").addEventListener("mousedown", async (e) => {
      e.preventDefault()
      const id = span.dataset.highlightId
      // close the editor first so the outside-click handler doesn't try to save afterward
      this.editor.remove()
      this.editor = null
      this.editing = null
      await this.destroy(id, span)
    })

    this.editor = box
    this.editing = { id: span.dataset.highlightId, span, originalNote: currentNote, textarea }
  }

  async closeEditor({ save }) {
    if (!this.editor || !this.editing) {
      if (this.editor) { this.editor.remove(); this.editor = null }
      return
    }
    if (save) {
      const value = this.editing.textarea.value
      if (value !== this.editing.originalNote) {
        await this.patchHighlight(this.editing.id, { note: value })
        this.editing.span.dataset.note = value
        this.editing.span.classList.toggle("has-note", value.length > 0)
      }
    }
    this.editor.remove()
    this.editor = null
    this.editing = null
  }

  async patchHighlight(id, fields) {
    try {
      const res = await this.api("PATCH", `/highlights/${id}`, { highlight: fields })
      if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); return null }
      if (!res.ok) return null
      return await res.json()
    } catch { return null }
  }

  async destroy(id, span) {
    try {
      const res = await this.api("DELETE", `/highlights/${id}`)
      if (res.ok) span.replaceWith(document.createTextNode(span.textContent))
    } catch { /* no-op */ }
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

  api(method, url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const opts = { method, headers: { "X-CSRF-Token": token, Accept: "application/json" } }
    if (body !== undefined) {
      opts.headers["Content-Type"] = "application/json"
      opts.body = JSON.stringify(body)
    }
    return fetch(url, opts)
  }
}
