import { Controller } from "@hotwired/stimulus"

// Dropdown that holds the workspace's "view" preferences — font size, theme,
// diff, interlinear. Each inner control is its own controller; this one only
// opens/closes the panel and handles click-outside / Esc.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this._outside = (e) => { if (!this.element.contains(e.target)) this.close() }
    this._esc = (e) => { if (e.key === "Escape") this.close() }
  }

  disconnect() {
    document.removeEventListener("click", this._outside)
    document.removeEventListener("keydown", this._esc)
  }

  toggle(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.element.classList.add("is-open")
    // Defer listener attach so the click that opens us doesn't immediately close.
    setTimeout(() => {
      document.addEventListener("click", this._outside)
      document.addEventListener("keydown", this._esc)
    }, 0)
  }

  close() {
    this.panelTarget.hidden = true
    this.element.classList.remove("is-open")
    document.removeEventListener("click", this._outside)
    document.removeEventListener("keydown", this._esc)
  }
}
