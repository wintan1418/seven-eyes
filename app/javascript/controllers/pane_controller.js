import { Controller } from "@hotwired/stimulus"

// Per-pane UI: the notes card (open/close; also opened from the verse action
// bar's Note and the phone's Notes tab via window events), and the chapter's
// share / prayer pictures.
export default class extends Controller {
  static targets = ["notes"]

  connect() {
    this._onToggle = (e) => { if (this.addressed(e)) this.toggleNotes() }
    this._onOpen = (e) => { if (this.addressed(e)) this.openNotes(e.detail?.insert) }
    window.addEventListener("notes:toggle", this._onToggle)
    window.addEventListener("notes:open", this._onOpen)
  }

  disconnect() {
    window.removeEventListener("notes:toggle", this._onToggle)
    window.removeEventListener("notes:open", this._onOpen)
  }

  // An event names its pane by id; without one it is for the first pane.
  addressed(event) {
    const id = event.detail?.paneId
    if (id) return this.element.id === `pane_${id}`
    return this.element === this.element.closest(".ps-workspace")?.querySelector(".ps-pane")
  }

  toggleNotes(event) {
    event?.preventDefault()
    if (!this.hasNotesTarget) return
    const open = this.notesTarget.classList.toggle("is-open")
    if (open) this.notesTarget.querySelector("textarea")?.focus()
  }

  // Open the notes and append text (a [[John 3:16]] link) where the reader
  // will keep typing.
  openNotes(insert) {
    if (!this.hasNotesTarget) return
    this.notesTarget.classList.add("is-open")
    const area = this.notesTarget.querySelector("textarea")
    if (!area) return
    if (insert) {
      const sep = area.value && !/\s$/.test(area.value) ? "\n" : ""
      area.value += sep + insert
      area.dispatchEvent(new Event("input", { bubbles: true })) // schedules the auto-save
    }
    area.focus()
    area.setSelectionRange(area.value.length, area.value.length)
  }

  closeNotes() {
    this.notesTarget?.classList.remove("is-open")
  }

  // Open the share modal for this pane's displayed passage.
  share(event) {
    event?.preventDefault()
    const d = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("share:open", { detail: {
      osis: d.osis, chapter: d.chapter, verseStart: d.verseStart, verseEnd: d.verseEnd,
      translation: this.translation()
    } }))
  }

  // Open the share modal straight to a prayer composed from this chapter.
  prayer(event) {
    event?.preventDefault()
    const d = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("prayer:open", { detail: {
      osis: d.osis, chapter: d.chapter, translation: this.translation()
    } }))
  }

  // The translation this pane is showing — the card and prayer must quote the
  // version on screen, not a KJV default.
  translation() {
    const meta = this.element.querySelector(".rd-pane-meta")
    if (meta?.dataset.translationCode) return meta.dataset.translationCode
    const select = this.element.querySelector(".ps-trans-select")
    return select?.selectedOptions?.[0]?.textContent?.trim() || null
  }
}
