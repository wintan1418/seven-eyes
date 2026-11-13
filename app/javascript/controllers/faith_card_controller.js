import { Controller } from "@hotwired/stimulus"

// Home "Word of the day" (Glossary of the Faith): the ✕ hides the card until
// tomorrow on this device. Only the date it was hidden is kept; storage that
// is blocked or cleared just means the card shows again.
const KEY = "ps-faith-card-hidden"

export default class extends Controller {
  static values = { date: String }

  connect() {
    if (this.read() === this.dateValue) this.element.classList.add("is-dismissed")
  }

  dismiss() {
    this.element.classList.add("is-dismissed")
    try { localStorage.setItem(KEY, this.dateValue) } catch { /* private mode: hide for this page only */ }
  }

  read() {
    try { return localStorage.getItem(KEY) } catch { return null }
  }
}
