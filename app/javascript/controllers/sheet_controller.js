import { Controller } from "@hotwired/stimulus"

// One sheet (menu, passage picker, translations, reading settings, more…).
// Opens on a window `sheet:open` event whose detail.id matches this sheet's
// id (the `sheets` controller turns button clicks into that event), closes on
// the backdrop, Esc, or any [data-action~='sheet#close']. Locks page scroll
// while open and hands focus back to the button that opened it.
export default class extends Controller {
  static values = { id: String }

  connect() {
    this._onOpen = (e) => {
      if (e.detail?.id === this.idValue) this.open(e.detail)
      else if (this.isOpen) this.close()
    }
    this._onClose = (e) => { if (!e.detail?.id || e.detail.id === this.idValue) this.close() }
    this._onKey = (e) => { if (e.key === "Escape" && this.isOpen) { e.preventDefault(); this.close() } }
    window.addEventListener("sheet:open", this._onOpen)
    window.addEventListener("sheet:close", this._onClose)
  }

  disconnect() {
    window.removeEventListener("sheet:open", this._onOpen)
    window.removeEventListener("sheet:close", this._onClose)
    document.removeEventListener("keydown", this._onKey, true)
    this._unlock()
  }

  get isOpen() { return this.element.classList.contains("is-open") }

  open(detail = {}) {
    if (document.querySelector(".ps-root.is-presenting")) return // never over the pulpit
    this._returnFocus = detail.trigger || document.activeElement
    if (detail.paneId) this.element.dataset.paneId = detail.paneId
    else delete this.element.dataset.paneId
    clearTimeout(this._hideTimer)
    this.element.hidden = false
    requestAnimationFrame(() => this.element.classList.add("is-open"))
    document.documentElement.classList.add("ui-scroll-lock")
    document.addEventListener("keydown", this._onKey, true)
    this.dispatch("opened", { detail })
    const focusable = this.element.querySelector("[autofocus], .ui-sheet-panel [tabindex='-1']")
    setTimeout(() => focusable?.focus({ preventScroll: true }), 60)
  }

  close(event) {
    if (event?.type === "click" && event.currentTarget?.tagName === "A") {
      // let the link navigate; just tidy up
    } else {
      event?.preventDefault?.()
    }
    if (!this.isOpen) return
    this.element.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey, true)
    this._unlock()
    this._hideTimer = setTimeout(() => { this.element.hidden = true }, 220)
    const back = this._returnFocus
    this._returnFocus = null
    if (back && document.contains(back)) back.focus?.({ preventScroll: true })
    this.dispatch("closed")
  }

  _unlock() {
    if (!document.querySelector(".ui-sheet.is-open")) document.documentElement.classList.remove("ui-scroll-lock")
  }
}
