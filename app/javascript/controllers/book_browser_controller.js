import { Controller } from "@hotwired/stimulus"

// A slide-over to browse books -> chapters and load a chapter into a pane.
// Browsing is fully client-side; loading reuses the pane's own form + Turbo Frame.
export default class extends Controller {
  static targets = ["drawer", "books", "chapters", "chapterGrid", "crumb"]

  connect() {
    this.targetPaneId = null
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

  // Opened from a pane's "browse" button (data-pane-id on the button).
  open(event) {
    this.targetPaneId = event.currentTarget.dataset.paneId
    this.showBooks()
    this.drawerTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    this.drawerTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }

  showBooks() {
    this.booksTarget.hidden = false
    this.chaptersTarget.hidden = true
  }

  // Clicking a book button reveals its chapter grid.
  selectBook(event) {
    const btn = event.currentTarget
    const name = btn.dataset.name
    const count = parseInt(btn.dataset.chapters, 10)
    this.crumbTarget.textContent = name
    this.chapterGridTarget.innerHTML = ""
    for (let n = 1; n <= count; n++) {
      const c = document.createElement("button")
      c.type = "button"
      c.className = "ps-chapter"
      c.textContent = n
      c.dataset.reference = count === 1 ? name : `${name} ${n}`
      c.dataset.action = "book-browser#selectChapter"
      this.chapterGridTarget.appendChild(c)
    }
    this.booksTarget.hidden = true
    this.chaptersTarget.hidden = false
  }

  back() {
    this.showBooks()
  }

  // Clicking a chapter fills the target pane's reference input and submits it.
  selectChapter(event) {
    const reference = event.currentTarget.dataset.reference
    if (!this.targetPaneId) return
    const frame = document.getElementById(`pane_${this.targetPaneId}`)
    if (!frame) return
    const input = frame.querySelector("input[name='pane[reference]']")
    const form = input && input.closest("form")
    if (!input || !form) return
    input.value = reference
    form.requestSubmit()
    this.close()
  }
}
