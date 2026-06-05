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

  // Open the share modal for this pane's displayed passage.
  share(event) {
    event?.preventDefault()
    const d = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("share:open", { detail: {
      osis: d.osis, chapter: d.chapter, verseStart: d.verseStart, verseEnd: d.verseEnd
    } }))
  }

  // Open the share modal straight to a prayer composed from this chapter.
  prayer(event) {
    event?.preventDefault()
    const d = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("prayer:open", { detail: { osis: d.osis, chapter: d.chapter } }))
  }
}
