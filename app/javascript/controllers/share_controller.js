import { Controller } from "@hotwired/stimulus"

// Generates (server-side, lazy) and copies the study's read-only share link.
// On click: POST to the share endpoint, copy the returned URL to the clipboard,
// and flash a confirmation back through the button label.
export default class extends Controller {
  static targets = ["label"]
  static values = { url: String }

  async copy(event) {
    event?.preventDefault?.()
    const csrf = document.querySelector('meta[name="csrf-token"]')
    try {
      const res = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrf ? csrf.content : ""
        }
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      await navigator.clipboard.writeText(data.url)
      this._flash("✓ Link copied")
    } catch (_) {
      this._flash("Copy failed")
    }
  }

  _flash(text) {
    if (!this.hasLabelTarget) return
    // Capture the real label once — a second click mid-flash must not save
    // "✓ Link copied" as the label to restore.
    this._original ??= this.labelTarget.innerHTML
    this.labelTarget.textContent = text
    clearTimeout(this._flashTimer)
    this._flashTimer = setTimeout(() => { this.labelTarget.innerHTML = this._original }, 1600)
  }

  disconnect() {
    clearTimeout(this._flashTimer)
    if (this._original != null && this.hasLabelTarget) this.labelTarget.innerHTML = this._original
  }
}
