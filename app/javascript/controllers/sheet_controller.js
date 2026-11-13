import { Controller } from "@hotwired/stimulus"

// One sheet (menu, passage picker, translations, reading settings, more…).
// Opens on a window `sheet:open` event whose detail.id matches this sheet's
// id (the `sheets` controller turns button clicks into that event), closes on
// the backdrop, Esc, or any [data-action~='sheet#close']. Locks page scroll
// while open and hands focus back to the button that opened it.
//
// The lock is a class on <html>, which Turbo keeps across visits — so it is
// also released whenever a visit starts or a page loads with no sheet open,
// and a sheet left open by a link inside it is closed before Turbo caches the
// page (a Back would otherwise restore an open sheet with no lock owner).
const SCROLL_LOCK = "ui-scroll-lock"
function releaseScrollLock() {
  if (!document.querySelector(".ui-sheet.is-open")) document.documentElement.classList.remove(SCROLL_LOCK)
}
if (!window.__uiSheetTurboBound) {
  window.__uiSheetTurboBound = true
  document.addEventListener("turbo:before-visit", () => document.documentElement.classList.remove(SCROLL_LOCK))
  document.addEventListener("turbo:load", releaseScrollLock)
  document.addEventListener("turbo:before-cache", () => {
    document.querySelectorAll(".ui-sheet.is-open").forEach((sheet) => { sheet.classList.remove("is-open"); sheet.hidden = true })
    document.documentElement.classList.remove(SCROLL_LOCK)
  })
}

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
    document.documentElement.classList.add(SCROLL_LOCK)
    document.addEventListener("keydown", this._onKey, true)
    this.dispatch("opened", { detail })
    // Focus lands inside the sheet — on its scrolling body when nothing asks
    // for focus — so ↑/↓, Page Down and End scroll a long sheet (focus left on
    // the opening button scrolled the locked page instead: nothing moved).
    let focusable = this.element.querySelector("[autofocus], .ui-sheet-panel [tabindex='-1']")
    if (!focusable) {
      focusable = this.element.querySelector(".ui-sheet-body")
      if (focusable && !focusable.hasAttribute("tabindex")) focusable.setAttribute("tabindex", "-1")
    }
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
    releaseScrollLock()
  }
}
