import { Controller } from "@hotwired/stimulus"

// Reading layout on .ps-root: one verse per line (.is-verse-lines) or flowing
// paragraphs like a printed Bible. Remembered per device ("1" lines / "0"
// paragraphs). With no choice yet, phones read verse per line (like a Bible
// app — CSS already lays it out that way before this connects) and laptops
// in paragraphs. On a phone, paragraphs are an opt-out: .is-verse-paragraphs.
const KEY = "ps:verse-lines"
const PHONE = "(max-width: 767px)"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    let stored = null
    try { stored = localStorage.getItem(KEY) } catch (_) {}
    const phone = window.matchMedia?.(PHONE).matches
    this.apply(stored === "1" || (stored !== "0" && !!phone))
  }

  toggle(event) {
    event?.preventDefault?.()
    const on = !this.element.classList.contains("is-verse-lines")
    this.apply(on)
    try { localStorage.setItem(KEY, on ? "1" : "0") } catch (_) {}
  }

  apply(on) {
    this.element.classList.toggle("is-verse-lines", on)
    this.element.classList.toggle("is-verse-paragraphs", !on)
    this.buttonTargets.forEach(b => b.setAttribute("aria-pressed", String(on)))
  }
}
