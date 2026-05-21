import { Controller } from "@hotwired/stimulus"

// Text-selection highlighting within a pane's verse body.
// - Select text inside a verse -> a color popover appears.
// - Pick a color -> POST /highlights (verse_id + char offsets) and wrap the range.
// - Click an existing highlight -> delete it and unwrap.
const COLORS = ["ochre", "sage", "cobalt", "rose"]

export default class extends Controller {
  connect() {
    this.popover = null
    this._onUp = this.onMouseUp.bind(this)
    this._onDocDown = this.onDocPointerDown.bind(this)
    this.element.addEventListener("mouseup", this._onUp)
    this.element.addEventListener("click", this.onClick.bind(this))
    document.addEventListener("pointerdown", this._onDocDown, true)
  }

  disconnect() {
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
    this.showPopover(range.getBoundingClientRect())
  }

  // Click an existing highlight span to remove it.
  onClick(event) {
    const span = event.target.closest("[data-highlight-id]")
    if (!span) return
    const id = span.dataset.highlightId
    this.destroy(id, span)
  }

  verseTextOf(node) {
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node
    return el ? el.closest(".ps-verse-text") : null
  }

  // Character offset of (node, offset) measured from the start of container's text.
  offsetWithin(container, node, offset) {
    const pre = document.createRange()
    pre.selectNodeContents(container)
    pre.setEnd(node, offset)
    return pre.toString().length
  }

  showPopover(rect) {
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
  }

  async create(color) {
    const p = this.pending
    this.removePopover()
    if (!p) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const res = await fetch("/highlights", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
        body: JSON.stringify({ highlight: { verse_id: p.verseId, color, char_start: p.start, char_end: p.end } })
      })
      if (!res.ok) return
      const data = await res.json()
      this.wrap(p.range, color, data.id)
      window.getSelection()?.removeAllRanges()
    } catch { /* will appear on reload */ }
  }

  wrap(range, color, id) {
    const span = document.createElement("span")
    span.className = `hl-${color}`
    span.dataset.highlightId = id
    try { range.surroundContents(span) } catch { /* crosses nodes; shows on reload */ }
  }

  async destroy(id, span) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const res = await fetch(`/highlights/${id}`, {
        method: "DELETE",
        headers: { "X-CSRF-Token": token }
      })
      if (res.ok) span.replaceWith(document.createTextNode(span.textContent))
    } catch { /* no-op */ }
  }
}
