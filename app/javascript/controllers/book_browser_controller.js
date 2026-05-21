import { Controller } from "@hotwired/stimulus"

// A slide-over to browse books -> chapters -> verses and load a passage into a pane.
// Book/chapter lists are client-side; the verse count is fetched per chapter so we
// can offer a "zero in on a verse" grid (plus a "Whole chapter" option).
export default class extends Controller {
  static targets = ["drawer", "books", "chapters", "chapterGrid", "verses", "verseGrid", "crumb"]

  connect() {
    this.targetPaneId = null
    this.book = null
    this.chapter = null
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

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
    this.crumbTarget.textContent = "Genesis — Revelation"
    this.booksTarget.hidden = false
    this.chaptersTarget.hidden = true
    this.versesTarget.hidden = true
  }

  // Book button -> show its chapter grid.
  selectBook(event) {
    const btn = event.currentTarget
    this.book = { name: btn.dataset.name, count: parseInt(btn.dataset.chapters, 10) }
    this.crumbTarget.textContent = this.book.name
    this.chapterGridTarget.innerHTML = ""
    for (let n = 1; n <= this.book.count; n++) {
      this.chapterGridTarget.appendChild(this.gridButton(n, "book-browser#selectChapter", { chapter: n }))
    }
    this.booksTarget.hidden = true
    this.versesTarget.hidden = true
    this.chaptersTarget.hidden = false
  }

  // Chapter button -> fetch verse count and show a verse grid (+ "Whole chapter").
  async selectChapter(event) {
    this.chapter = parseInt(event.currentTarget.dataset.chapter, 10)
    const single = this.book.count === 1
    const ref = single ? this.book.name : `${this.book.name} ${this.chapter}`
    this.crumbTarget.textContent = ref

    this.verseGridTarget.innerHTML = ""
    // "Whole chapter" first.
    const whole = document.createElement("button")
    whole.type = "button"
    whole.className = "ps-book-back"
    whole.style.gridColumn = "1 / -1"
    whole.textContent = single ? "Open the book" : "Whole chapter"
    whole.dataset.reference = ref
    whole.dataset.action = "book-browser#selectVerse"
    this.verseGridTarget.appendChild(whole)

    this.chaptersTarget.hidden = true
    this.versesTarget.hidden = false

    const count = await this.fetchVerseCount()
    for (let v = 1; v <= count; v++) {
      this.verseGridTarget.appendChild(this.gridButton(v, "book-browser#selectVerse", { reference: `${ref}:${v}` }))
    }
  }

  selectVerse(event) {
    this.loadReference(event.currentTarget.dataset.reference)
  }

  back() { this.showBooks() }
  backToChapters() {
    this.versesTarget.hidden = true
    this.chaptersTarget.hidden = false
    this.crumbTarget.textContent = this.book?.name || ""
  }

  // --- helpers ---

  gridButton(label, action, data) {
    const b = document.createElement("button")
    b.type = "button"
    b.className = "ps-chapter"
    b.textContent = label
    b.dataset.action = action
    Object.entries(data).forEach(([k, val]) => { b.dataset[k] = val })
    return b
  }

  async fetchVerseCount() {
    const osis = this.osisFor(this.book.name)
    const translation = this.targetTranslation()
    try {
      const params = new URLSearchParams({ osis, chapter: this.chapter, translation })
      const res = await fetch(`/verse_count?${params}`, { headers: { Accept: "application/json" } })
      if (!res.ok) return 0
      return (await res.json()).count || 0
    } catch {
      return 0
    }
  }

  osisFor(name) {
    const btn = this.booksTarget.querySelector(`.ps-book[data-name="${CSS.escape(name)}"]`)
    return btn ? btn.dataset.osis : name
  }

  targetTranslation() {
    const frame = document.getElementById(`pane_${this.targetPaneId}`)
    const sel = frame?.querySelector("select[name='pane[translation_id]']")
    return sel ? sel.options[sel.selectedIndex]?.text || "" : ""
  }

  loadReference(reference) {
    const frame = document.getElementById(`pane_${this.targetPaneId}`)
    const input = frame?.querySelector("input[name='pane[reference]']")
    const form = input?.closest("form")
    if (!input || !form) return
    input.value = reference
    form.requestSubmit()
    this.close()
  }
}
