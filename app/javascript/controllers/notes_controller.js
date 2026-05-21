import { Controller } from "@hotwired/stimulus"

// Debounced background auto-save for a pane's notes. Submits the notes form via
// fetch (not Turbo) so the pane frame is never re-rendered while typing.
export default class extends Controller {
  static targets = ["status"]

  connect() {
    this.timeout = null
  }

  schedule() {
    clearTimeout(this.timeout)
    this.setStatus("Editing…")
    this.timeout = setTimeout(() => this.save(), 700)
  }

  async save() {
    const form = this.element
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const res = await fetch(form.action, {
        method: "PATCH",
        body: new FormData(form),
        headers: { "X-CSRF-Token": token, "Accept": "text/plain" }
      })
      this.setStatus(res.ok ? "Saved just now" : "Save failed")
    } catch {
      this.setStatus("Save failed")
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
