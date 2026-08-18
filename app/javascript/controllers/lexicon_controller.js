import { Controller } from "@hotwired/stimulus"

// Opens/closes the word-study slide-over. A tagged word is a plain span (a
// real <a> would pop the mobile long-press link menu and block text selection);
// its data-href is loaded into the lexicon_drawer frame here.
export default class extends Controller {
  static targets = ["host"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

  open(event) {
    // On touch a single tap is for reading and selecting/copying, not opening
    // the root-word drawer — so it doesn't hijack the tap. Desktop keeps
    // tap-to-open the lexicon.
    if (this._touchCapable()) { event?.preventDefault?.(); return }
    const url = event?.currentTarget?.dataset?.href
    if (url) {
      const frame = document.getElementById("lexicon_drawer")
      if (frame) frame.src = url
    }
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
