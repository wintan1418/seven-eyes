import { Controller } from "@hotwired/stimulus"

// Reading layout on .ps-root: flowing paragraphs (default, like a printed
// Bible) or one verse per line (.is-verse-lines). Remembered per device.
const KEY = "ps:verse-lines"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    let on = false
    try { on = localStorage.getItem(KEY) === "1" } catch (_) {}
    this.apply(on)
  }

  toggle(event) {
    event?.preventDefault?.()
    const on = !this.element.classList.contains("is-verse-lines")
    this.apply(on)
    try { on ? localStorage.setItem(KEY, "1") : localStorage.removeItem(KEY) } catch (_) {}
  }

  apply(on) {
    this.element.classList.toggle("is-verse-lines", on)
    this.buttonTargets.forEach(b => b.setAttribute("aria-pressed", String(on)))
  }
}
