import { Controller } from "@hotwired/stimulus"

// Global keyboard shortcuts for the workspace (scoped on .ps-root):
//   Cmd/Ctrl+K  focus the active pane's reference input
//   1–4         make that pane active and focus its reference (when not typing)
//   Cmd/Ctrl+S  "save" (studies auto-persist) — flash a confirmation, no nav
//   Cmd/Ctrl+D  duplicate the active pane's reference into the next empty pane
//   X           open cross-references for the active pane's first verse
//   Esc         close any open drawer / blur inputs
export default class extends Controller {
  connect() {
    this.activePane = this.panes()[0] || null
    this.markActive()
    this._onKey = this.onKey.bind(this)
    this._onFocus = this.onFocusIn.bind(this)
    document.addEventListener("keydown", this._onKey)
    this.element.addEventListener("pointerdown", this._onFocus, true)
    this.element.addEventListener("focusin", this._onFocus, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }

  panes() {
    return Array.from(this.element.querySelectorAll(".ps-pane"))
  }

  onFocusIn(event) {
    const pane = event.target.closest?.(".ps-pane")
    if (pane) { this.activePane = pane; this.markActive() }
  }

  markActive() {
    this.panes().forEach((p) => p.classList.toggle("is-active-pane", p === this.activePane))
  }

  refInput(pane) {
    return pane?.querySelector("input[name='pane[reference]']")
  }

  typing(target) {
    const t = target.tagName
    return t === "INPUT" || t === "TEXTAREA" || target.isContentEditable
  }

  onKey(event) {
    const mod = event.metaKey || event.ctrlKey

    if (mod && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.refInput(this.activePane)?.focus()
      return
    }
    if (mod && event.key.toLowerCase() === "s") {
      event.preventDefault()
      this.flash("✓ Saved")
      return
    }
    if (mod && event.key.toLowerCase() === "d") {
      event.preventDefault()
      this.duplicateToNextEmpty()
      return
    }
    if (event.key === "Escape") {
      this.closeDrawers()
      if (this.typing(document.activeElement)) document.activeElement.blur()
      return
    }

    // Unmodified single-key shortcuts only when not typing.
    if (mod || this.typing(event.target)) return

    if ([ "1", "2", "3", "4" ].includes(event.key)) {
      const pane = this.panes()[parseInt(event.key, 10) - 1]
      if (pane) { event.preventDefault(); this.activePane = pane; this.markActive(); this.refInput(pane)?.focus() }
    } else if (event.key.toLowerCase() === "x") {
      this.activePane?.querySelector(".ps-vnum")?.click()
    }
  }

  duplicateToNextEmpty() {
    const source = this.refInput(this.activePane)
    if (!source || !source.value.trim()) return
    const target = this.panes().map((p) => this.refInput(p)).find((i) => i && !i.value.trim())
    if (!target) return this.flash("No empty pane")
    target.value = source.value
    target.form?.requestSubmit()
    this.flash("Duplicated →")
  }

  closeDrawers() {
    document.querySelectorAll(".ps-book-drawer.is-open, .ps-ai-drawer.is-open, .ps-xref-host.is-open")
      .forEach((d) => d.classList.remove("is-open"))
  }

  flash(text) {
    let toast = document.querySelector(".ps-toast.js-flash")
    if (!toast) {
      toast = document.createElement("div")
      toast.className = "ps-toast js-flash"
      document.body.appendChild(toast)
    }
    toast.innerHTML = `<span class="check">✦</span> ${text}`
    clearTimeout(this._flash)
    toast.style.opacity = "1"
    this._flash = setTimeout(() => { toast.style.opacity = "0" }, 1400)
  }
}
