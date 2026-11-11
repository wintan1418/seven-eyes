import { Controller } from "@hotwired/stimulus"

// Word for Today card: Share opens the existing share-as-image modal (its card
// URL is this day's word), Copy puts the verse, reflection, prayer and link on
// the clipboard. The apps' clipboard bridge wins when present (WebViews often
// refuse navigator.clipboard).
export default class extends Controller {
  static values = { text: String }
  static targets = ["copy"]

  share() {
    window.dispatchEvent(new CustomEvent("share:open", { detail: {} }))
  }

  async copy() {
    try {
      if (window.BiblioRataNative) window.BiblioRataNative.copy(this.textValue)
      else await navigator.clipboard.writeText(this.textValue)
      this.flash("Copied!")
    } catch {
      this.flash("Couldn't copy")
    }
  }

  flash(message) {
    if (!this.hasCopyTarget) return
    const btn = this.copyTarget
    btn.dataset.label ??= btn.innerHTML
    btn.textContent = message
    clearTimeout(this._timer)
    this._timer = setTimeout(() => { btn.innerHTML = btn.dataset.label }, 1400)
  }
}
