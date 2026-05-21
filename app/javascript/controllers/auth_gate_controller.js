import { Controller } from "@hotwired/stimulus"

// Shows a "create an account to save" prompt. Other controllers (notes, highlighter)
// dispatch a window "auth:required" event when a guest hits a gated save.
export default class extends Controller {
  static targets = ["modal"]

  connect() {
    this._onRequired = () => this.open()
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    window.addEventListener("auth:required", this._onRequired)
  }

  disconnect() {
    window.removeEventListener("auth:required", this._onRequired)
  }

  open() {
    if (!this.hasModalTarget) return
    this.modalTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    if (!this.hasModalTarget) return
    this.modalTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }
}
