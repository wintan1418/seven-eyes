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
    const container = this.verseTextOf(range.startContainer)
    if (!container || container !== this.verseTextOf(range.endContainer)) return this.removePopover()

    const base = parseInt(container.dataset.offsetBase || "0", 10)
    const start = base + this.offsetWithin(container, range.startContainer, range.startOffset)
    const end = start + range.toString().length
    if (end <= start) return this.removePopover()

    this.pending = { verseId: container.dataset.verseId, start, end, range: range.cloneRange() }
    this.showColorPopover(range.getBoundingClientRect())
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
    document.body.appendChild(pop)
    this.popover = pop
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
    if (!p) return
    try {
      const res = await this.api("POST", "/highlights", {
        highlight: { verse_id: p.verseId, color, char_start: p.start, char_end: p.end }
      })
      if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); return }
      if (!res.ok) return
      const data = await res.json()
      const span = this.wrap(p.range, color, data.id)
      window.getSelection()?.removeAllRanges()
      if (span) this.openEditor(span) // jump straight into note entry for the new highlight
    } catch { /* will appear on reload */ }
  }

  wrap(range, color, id) {
    const span = document.createElement("span")
    span.className = `hl-${color}`
    span.dataset.highlightId = id
    span.dataset.note = ""
    try { range.surroundContents(span); return span } catch { return null } // crosses nodes; reload shows it
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
