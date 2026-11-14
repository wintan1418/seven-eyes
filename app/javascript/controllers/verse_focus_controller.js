import { Controller } from "@hotwired/stimulus"
import { openInPane, takeFocus, parseFocus, splitReference, primaryPane } from "../lib/open_verse"

// "Open at verse": a search result, cross-reference or key verse opens the
// WHOLE chapter, scrolled so the verse sits in the middle, the verse marked
// (a soft wash that fades, then a quiet mark that stays). Lives on
// .ps-workspace.
//
// Ways in:
//   • forms marked data-open-verse="Deut 32:2" (result buttons) — taken over
//     here and sent through the pane's own form as the chapter;
//   • the server's data-verse-focus="2-4" on .ps-verses (/read?ref=…,
//     /p/:slug/open, /studies/:id?verse=2);
//   • ?open=Deut 32:2&tid=1 on the study URL (the /search page offline).
// Preach mode is left alone: it shows verse ranges on purpose.
const FLASH_MS = 2600

export default class extends Controller {
  connect() {
    this._onSubmit = (event) => this.intercept(event)
    this._onLoad = (event) => this.loaded(event)
    window.addEventListener("submit", this._onSubmit, true)
    document.addEventListener("turbo:frame-load", this._onLoad)
    this.element.querySelectorAll(".ps-pane").forEach((frame) => this.applyServerFocus(frame))
    this.openFromUrl()
  }

  disconnect() {
    window.removeEventListener("submit", this._onSubmit, true)
    document.removeEventListener("turbo:frame-load", this._onLoad)
    clearTimeout(this._flash)
  }

  intercept(event) {
    const form = event.target
    const reference = form?.dataset?.openVerse
    if (!reference || this.presenting()) return
    const frame = document.getElementById(form.dataset.turboFrame) || primaryPane()
    if (!frame || !this.element.contains(frame)) return
    event.preventDefault()
    event.stopImmediatePropagation()
    const translationId = form.querySelector("input[name='pane[translation_id]']")?.value || null
    openInPane(frame, reference, { translationId })
    window.dispatchEvent(new CustomEvent("verse:opened", { detail: { reference, paneId: frame.id } }))
  }

  loaded(event) {
    const frame = event.target
    if (!frame?.matches?.(".ps-pane") || !this.element.contains(frame)) return
    const focus = takeFocus(frame.id)
    if (focus) this.apply(frame, focus)
    else this.applyServerFocus(frame)
  }

  applyServerFocus(frame) {
    const focus = parseFocus(frame.querySelector(".ps-verses[data-verse-focus]")?.dataset.verseFocus)
    if (focus) this.apply(frame, focus)
  }

  openFromUrl() {
    const url = new URL(window.location.href)
    const reference = url.searchParams.get("open")
    const hadParams = [ "open", "tid", "verse" ].some((k) => url.searchParams.has(k))
    if (reference && !this.presenting()) {
      const frame = primaryPane()
      const split = splitReference(reference)
      const label = frame?.querySelector(".rd-pane-meta")?.dataset.referenceLabel
      const tid = url.searchParams.get("tid")
      const sameTranslation = !tid || frame?.querySelector(".rd-pane-meta")?.dataset.translationId === tid
      if (split && label === split.chapterRef && sameTranslation) this.apply(frame, split)
      else if (frame) openInPane(frame, reference, { translationId: tid })
    }
    if (hadParams) {
      ;[ "open", "tid", "verse" ].forEach((k) => url.searchParams.delete(k))
      window.history.replaceState(window.history.state, "", url.pathname + url.search + url.hash)
    }
  }

  apply(frame, { start, end }) {
    if (this.presenting()) return
    const all = [ ...frame.querySelectorAll(".ps-verse-body .ps-verse[data-verse-num]") ]
    const chapter = all[0]?.dataset.chapter
    const verses = all.filter((v) => {
      const n = parseInt(v.dataset.verseNum, 10)
      return v.dataset.chapter === chapter && n >= start && n <= end
    })
    if (!verses.length) return
    frame.querySelectorAll(".ps-verse.is-focus").forEach((v) => v.classList.remove("is-focus", "is-focus-flash"))
    verses.forEach((v) => v.classList.add("is-focus", "is-focus-flash"))
    const scroll = () => this.centre(frame, verses)
    requestAnimationFrame(scroll)
    document.fonts?.ready?.then(() => requestAnimationFrame(scroll))
    clearTimeout(this._flash)
    this._flash = setTimeout(() => verses.forEach((v) => v.classList.remove("is-focus-flash")), FLASH_MS)
  }

  centre(frame, verses) {
    const box = frame.querySelector(".ps-verses")
    if (!box) return
    const outer = box.getBoundingClientRect()
    const first = verses[0].getBoundingClientRect()
    const last = verses[verses.length - 1].getBoundingClientRect()
    const height = last.bottom - first.top
    const top = first.top - outer.top + box.scrollTop
    const offset = height < box.clientHeight - 48 ? (box.clientHeight - height) / 2 : 24
    box.scrollTop = Math.max(0, top - offset)
  }

  presenting() {
    return !!this.element.closest(".ps-root")?.matches(".is-presenting, .is-preaching, .is-output")
  }
}
