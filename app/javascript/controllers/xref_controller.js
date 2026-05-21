import { Controller } from "@hotwired/stimulus"

// Opens/closes the cross-reference slide-over. The verse-number link both loads
// the refs into the xref_drawer Turbo Frame and calls open() to reveal the drawer.
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
