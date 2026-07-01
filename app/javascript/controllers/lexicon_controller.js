import { Controller } from "@hotwired/stimulus"

// Opens/closes the word-study slide-over. A tagged word is a Turbo Frame link
// that loads the lexicon entry into lexicon_drawer; this just reveals the host.
export default class extends Controller {
  static targets = ["host"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

  open(event) {
    // On touch a single tap is for reading and selecting/copying, not opening the
    // root-word drawer — so it doesn't hijack the tap. preventDefault also stops
    // the word-link's Turbo Frame load. Desktop keeps tap-to-open the lexicon.
    if (this._touchCapable()) { event?.preventDefault?.(); return }
    this.hostTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  _touchCapable() {
    return typeof window.matchMedia === "function" && window.matchMedia("(any-pointer: coarse)").matches
  }

  close() {
    this.hostTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }
}
