import { Controller } from "@hotwired/stimulus"

// Memorization aid: blanks out the longer words in the pane's verses so the user
// recites from memory. Click a blank to reveal that word; toggle off to restore
// the original text (including any highlights). Pure DOM, no persistence.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.active = false
    this.originals = new Map()
  }

  toggle() {
    this.active ? this.deactivate() : this.activate()
  }

  activate() {
    this.spans().forEach((span) => {
      this.originals.set(span, span.innerHTML)
      span.innerHTML = this.blank(span.textContent)
    })
    this.active = true
    this.mark(true)
  }

  deactivate() {
    this.originals.forEach((html, span) => { span.innerHTML = html })
    this.originals.clear()
    this.active = false
    this.mark(false)
  }

  // Replace words of 4+ letters with clickable blanks of matching length.
  blank(text) {
    const escaped = text.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]))
    return escaped.replace(/\b[\p{L}']{4,}\b/gu, (word) => {
      const dashes = "_".repeat(Math.min(word.length, 12))
      return `<span class="ps-blank" data-word="${word}" role="button" tabindex="0">${dashes}</span>`
    })
  }

  // Click (event delegation) reveals an individual blank.
  reveal(event) {
    const blank = event.target.closest(".ps-blank")
    if (!blank || !this.active) return
    blank.textContent = blank.dataset.word
    blank.classList.add("is-revealed")
  }

  spans() {
    return Array.from(this.element.querySelectorAll(".ps-verse-text"))
  }

  mark(on) {
    if (this.hasButtonTarget) this.buttonTarget.classList.toggle("is-on", on)
  }
}
