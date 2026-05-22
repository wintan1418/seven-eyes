import { Controller } from "@hotwired/stimulus"

// Opens/closes the word-study slide-over. A tagged word is a Turbo Frame link
// that loads the lexicon entry into lexicon_drawer; this just reveals the host.
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
