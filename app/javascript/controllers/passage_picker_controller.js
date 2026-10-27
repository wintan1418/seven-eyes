import { Controller } from "@hotwired/stimulus"

// The passage sheet: Old/New Testament tabs, a filter box, tap a book → its
// chapter grid → that chapter loads in the pane (one-chapter books load at
// once). Typing a full reference ("jn 3:16", "rom 8") and pressing Enter loads
// it directly — the server's ReferenceParser does the reading.
// Loading reuses the pane's own form: set pane[reference], requestSubmit().
export default class extends Controller {
  static targets = ["query", "books", "book", "chapters", "chapterGrid", "bookTitle", "tab", "testament", "empty"]

  // sheet:opened → start fresh on the books of the current testament.
  reset(event) {
    this.paneId = event?.detail?.paneId || this.element.dataset.paneId || this._primaryPaneId()
    this.queryTarget.value = ""
    this.filter()
    const current = this._currentBook()
    this.showTestament(current?.dataset.testament || "old")
    this.bookTargets.forEach(b => b.classList.toggle("is-current", b === current))
    this.chaptersTarget.hidden = true
    this.booksTarget.hidden = false
    if (current) requestAnimationFrame(() => current.scrollIntoView({ block: "center" }))
  }

  tab(event) {
    this.showTestament(event.currentTarget.dataset.testament)
  }

  showTestament(testament) {
    this.tabTargets.forEach(t => t.setAttribute("aria-selected", String(t.dataset.testament === testament)))
    this.testamentTargets.forEach(t => { t.hidden = !this._filtering && t.dataset.testament !== testament })
  }

  filter() {
    const q = this._norm(this.queryTarget.value).replace(/\d+[:.]?\d*$/, "").replace(/^(\d)?([a-z]*).*$/, "$1$2")
    this._filtering = q.length > 0
    let shown = 0
    this.bookTargets.forEach(b => {
      const match = !q || b.dataset.keys.split(" ").some(k => k.startsWith(q))
      b.hidden = !match
      if (match) shown++
    })
    this.element.querySelector("[role=tablist]")?.toggleAttribute("hidden", this._filtering)
    if (this._filtering) this.testamentTargets.forEach(t => { t.hidden = !t.querySelector("[data-passage-picker-target='book']:not([hidden])") })
    else this.showTestament(this.tabTargets.find(t => t.getAttribute("aria-selected") === "true")?.dataset.testament || "old")
    this.emptyTarget.hidden = shown > 0
    this.chaptersTarget.hidden = true
    this.booksTarget.hidden = false
  }

  // Enter in the filter box: a full reference loads; a single matching book opens.
  submit(event) {
    event.preventDefault()
    const raw = this.queryTarget.value.trim()
    if (!raw) return
    if (/\d\s*$|\d[:.]\d/.test(raw) && /[a-z]/i.test(raw)) return this.load(raw)
    const visible = this.bookTargets.filter(b => !b.hidden)
    if (visible.length >= 1) this.openBook(visible[0])
  }

  pickBook(event) {
    this.openBook(event.currentTarget)
  }

  openBook(book) {
    const count = parseInt(book.dataset.chapters, 10)
    if (count === 1) return this.load(`${book.dataset.name} 1`)
    this.bookTitleTarget.textContent = book.dataset.name
    const grid = this.chapterGridTarget
    grid.replaceChildren()
    const current = this._currentChapter(book.dataset.name)
    for (let n = 1; n <= count; n++) {
      const b = document.createElement("button")
      b.type = "button"
      b.className = "ui-chapter" + (n === current ? " is-current" : "")
      b.textContent = n
      b.dataset.reference = `${book.dataset.name} ${n}`
      b.dataset.action = "passage-picker#pickChapter"
      grid.appendChild(b)
    }
    this.booksTarget.hidden = true
    this.chaptersTarget.hidden = false
    this.chaptersTarget.scrollTop = 0
    grid.querySelector(".is-current, button")?.focus({ preventScroll: true })
  }

  pickChapter(event) {
    this.load(event.currentTarget.dataset.reference)
  }

  back() {
    this.chaptersTarget.hidden = true
    this.booksTarget.hidden = false
  }

  load(reference) {
    const frame = document.getElementById(`pane_${this.paneId || this._primaryPaneId()}`)
    const input = frame?.querySelector("input[name='pane[reference]']")
    if (!input?.form) return
    input.value = reference
    window.dispatchEvent(new CustomEvent("sheet:close", { detail: { id: "passage" } }))
    input.form.requestSubmit()
  }

  _primaryPaneId() {
    return document.querySelector(".ps-workspace .ps-pane")?.id?.replace("pane_", "")
  }

  _meta() {
    return document.getElementById(`pane_${this.paneId || this._primaryPaneId()}`)?.querySelector(".rd-pane-meta")
  }

  _currentBook() {
    const label = this._meta()?.dataset.referenceLabel || ""
    return this.bookTargets.find(b => label === b.dataset.name || label.startsWith(`${b.dataset.name} `))
  }

  _currentChapter(bookName) {
    const label = this._meta()?.dataset.referenceLabel || ""
    if (!label.startsWith(`${bookName} `)) return null
    return parseInt(label.slice(bookName.length + 1), 10) || null
  }

  _norm(s) { return s.toLowerCase().replace(/[\s.]/g, "") }
}
