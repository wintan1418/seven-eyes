import { Controller } from "@hotwired/stimulus"
import { highlightVerses, removeHighlights } from "../lib/highlight_api"

// The bar that rises when verses are tapped: highlight colours, Note,
// Compare, Copy, Share, and an overflow (cross-references, word study,
// commentary, AI Rabbi). Driven by verse_select's `verses:selected` event.
export default class extends Controller {
  static targets = ["label", "clear", "overflow", "compare"]

  connect() {
    this.selection = { verses: [] }
    this._onSelected = (e) => this.show(e.detail)
    window.addEventListener("verses:selected", this._onSelected)
  }

  disconnect() {
    window.removeEventListener("verses:selected", this._onSelected)
  }

  show(detail) {
    this.selection = detail || { verses: [] }
    const any = this.selection.verses.length > 0
    this.element.hidden = !any
    this.element.classList.toggle("is-open", any)
    document.documentElement.classList.toggle("ui-has-actionbar", any)
    this.closeOverflow()
    if (!any) return
    this.labelTarget.textContent = this.selection.label
    if (this.hasClearTarget) this.clearTarget.hidden = !this.selection.verses.some(v => v.highlightIds.length)
  }

  dismiss() {
    window.dispatchEvent(new CustomEvent("verses:clear"))
  }

  async highlight(event) {
    const color = event.currentTarget.dataset.color
    const verses = this.selection.verses.filter(v => v.verseId)
    if (!verses.length) return
    const result = await highlightVerses(verses, color)
    if (result === "unauthorized") return
    if (result === "failed") this.toast("Highlight failed — check your connection")
    this.refreshPane()
  }

  async unhighlight() {
    const ids = this.selection.verses.flatMap(v => v.highlightIds)
    if (!ids.length) return
    const result = await removeHighlights([...new Set(ids)])
    if (result === "unauthorized") return
    if (result === "failed") this.toast("Couldn't remove the highlight")
    this.refreshPane()
  }

  note() {
    const ref = this.selection.label
    window.dispatchEvent(new CustomEvent("notes:open", { detail: { paneId: this.selection.paneId, insert: `[[${ref}]] ` } }))
    this.dismiss()
  }

  async copy() {
    const verses = this.selection.verses
    const body = verses.length === 1
      ? verses[0].text
      : verses.map(v => `${v.verse} ${v.text}`).join(" ")
    const payload = `${body}\n— ${this.selection.label}${this.selection.translation ? ` ${this.selection.translation}` : ""}`
    try {
      await navigator.clipboard.writeText(payload)
      this.toast("Copied")
    } catch {
      this.toast("Couldn't copy — select the words and copy instead")
    }
    this.dismiss()
  }

  share() {
    const verses = this.selection.verses
    const first = verses[0]
    if (!first) return
    const sameChapter = verses.every(v => v.chapter === first.chapter)
    const nums = verses.map(v => v.verse)
    window.dispatchEvent(new CustomEvent("share:open", { detail: {
      osis: first.osis, chapter: first.chapter,
      verseStart: Math.min(...nums), verseEnd: sameChapter ? Math.max(...nums) : undefined,
      translation: this.selection.translation
    } }))
  }

  toggleOverflow(event) {
    event?.stopPropagation()
    const open = this.overflowTarget.hidden
    this.overflowTarget.hidden = !open
  }

  closeOverflow() {
    if (this.hasOverflowTarget) this.overflowTarget.hidden = true
  }

  crossRefs() {
    const first = this.selection.verses[0]
    this.verseElement(first)?.querySelector(".ps-vnum")?.click()
    this.closeOverflow()
  }

  wordStudy() {
    const root = this.element.closest(".ps-root")
    const ctrl = root && this.application.getControllerForElementAndIdentifier(root, "interlinear")
    ctrl?.toggle()
    this.closeOverflow()
  }

  commentary() {
    this.pane()?.querySelector("a[data-action~='commentary#open']")?.click()
    this.closeOverflow()
  }

  rabbi() {
    const verseIds = this.selection.verses.map(v => v.verseId).filter(Boolean)
    if (!verseIds.length) return
    const text = this.selection.verses.map(v => v.text).join(" ")
    window.dispatchEvent(new CustomEvent("rabbi:ask", { detail: { verseId: verseIds[0], verseIds, text } }))
    this.closeOverflow()
  }

  pane() {
    return this.selection.paneId ? document.getElementById(`pane_${this.selection.paneId}`) : null
  }

  verseElement(v) {
    if (!v) return null
    return this.pane()?.querySelector(`.ps-verse[data-chapter='${v.chapter}'][data-verse-num='${v.verse}']`)
  }

  // Re-render the pane so the new highlights (with their ids) come back from
  // the server, exactly as a fresh page would draw them.
  refreshPane() {
    const form = this.pane()?.querySelector("input[name='pane[reference]']")?.form
    this.dismiss()
    form?.requestSubmit()
  }

  toast(text) {
    let toast = document.querySelector(".ps-toast.js-flash")
    if (!toast) {
      toast = document.createElement("div")
      toast.className = "ps-toast js-flash"
      document.body.appendChild(toast)
    }
    toast.textContent = text
    toast.style.opacity = "1" // same flash the shortcuts / highlighter use
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => { toast.style.opacity = "0" }, 1600)
  }
}
