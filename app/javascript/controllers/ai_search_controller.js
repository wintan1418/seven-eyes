import { Controller } from "@hotwired/stimulus"

// Opens/closes the "Find a Verse" AI slide-over. The query form inside posts to
// the suggest endpoint and renders results into the ai_results Turbo Frame.
export default class extends Controller {
  static targets = ["drawer", "input"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

  open() {
    this.drawerTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
    if (this.hasInputTarget) setTimeout(() => this.inputTarget.focus(), 50)
  }

  close() {
    this.drawerTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }
}
