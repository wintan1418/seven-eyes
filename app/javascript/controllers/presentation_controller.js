import { Controller } from "@hotwired/stimulus"

// Drives the "focus a single pane" presentation mode for projector / large-screen use.
// Lives on .ps-root. Pane buttons dispatch `presentation#enter` and the floating
// exit button (or Esc) dispatches `presentation#exit`.
export default class extends Controller {
  enter(event) {
    const pane = event.target.closest(".ps-pane")
    if (!pane) return
    event.preventDefault?.()
    this.element.querySelectorAll(".ps-pane.is-presented").forEach(p => p.classList.remove("is-presented"))
    pane.classList.add("is-presented")
    this.element.classList.add("is-presenting")
    this._bindEsc()
  }

  exit(event) {
    event?.preventDefault?.()
    this.element.classList.remove("is-presenting")
    this.element.querySelectorAll(".ps-pane.is-presented").forEach(p => p.classList.remove("is-presented"))
    this._unbindEsc()
  }

  disconnect() {
    this._unbindEsc()
  }

  _bindEsc() {
    if (this._escHandler) return
    this._escHandler = (e) => {
      if (e.key === "Escape" && this.element.classList.contains("is-presenting")) {
        this.exit()
      }
    }
    document.addEventListener("keydown", this._escHandler)
  }

  _unbindEsc() {
    if (!this._escHandler) return
    document.removeEventListener("keydown", this._escHandler)
    this._escHandler = null
  }
}
