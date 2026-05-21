import { Controller } from "@hotwired/stimulus"

// Per-pane UI: toggles the notes popover so notes don't permanently occupy the pane.
export default class extends Controller {
  static targets = ["notes"]

  toggleNotes(event) {
    event?.preventDefault()
    if (!this.hasNotesTarget) return
    const open = this.notesTarget.classList.toggle("is-open")
    if (open) this.notesTarget.querySelector("textarea")?.focus()
  }

  closeNotes() {
    this.notesTarget?.classList.remove("is-open")
  }
}
