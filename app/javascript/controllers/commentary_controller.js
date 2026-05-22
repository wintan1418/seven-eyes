import { Controller } from "@hotwired/stimulus"

// Opens/closes the commentary slide-over. A pane's commentary tool loads the
// chapter exposition into the commentary_drawer Turbo Frame and calls open().
export default class extends Controller {
  static targets = ["host"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

  open() {
    this.hostTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    this.hostTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }
}
