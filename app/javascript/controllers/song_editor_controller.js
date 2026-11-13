import { Controller } from "@hotwired/stimulus"
import { songSlides, flowCodes } from "../lib/song_sheet"
import { tidySong } from "../lib/song_import"
import { queueSongSave, flushOutbox } from "../lib/offline/outbox"
import { owner } from "../lib/offline/page"

// The queue form's song editor (on the add form, next to the setlist
// controller, which still owns adding/editing queue items). Only active while
// the form is on "Song":
//   paste        words pasted into an empty lyrics box are tidied at once —
//                title line, "1." verse numbers, "Chorus:", "(Repeat chorus)",
//                "(x2)" (lib/song_import); Ctrl/⌘+Z undoes it
//   .txt         open a text file of the words (same tidy)
//   Tidy         run the tidy on what's typed
//   flow line    how it will project — "V1 C V2 C V3 C" — as the words or the
//                order change, with order names that match nothing flagged
//   Save         "Save to my songs": into the account's song bank by title
//                (works offline — the outbox sends it later)
export default class extends Controller {
  static targets = [ "title", "body", "arrangement", "flow", "file", "saved" ]

  connect() {
    if (this.element.closest(".is-output")) return
    this.refresh()
  }

  _isSong() {
    return this.element.classList.contains("kind-song")
  }

  // ---- paste / import / tidy -----------------------------------------------------------

  paste(event) {
    if (!this._isSong()) return
    const text = event.clipboardData?.getData("text/plain") || ""
    const field = this.bodyTarget
    const replacingAll = !field.value.trim() || (field.selectionStart === 0 && field.selectionEnd === field.value.length)
    if (!replacingAll || !text.includes("\n")) return // a line pasted into a song being written: leave it be
    event.preventDefault()
    this._fill(text, { pasted: true })
  }

  openFile(event) {
    event?.preventDefault?.()
    this.fileTarget.click()
  }

  async fileChosen() {
    const file = this.fileTarget.files?.[0]
    this.fileTarget.value = ""
    if (!file) return
    if (file.size > 200_000) { this._note("That file is too big for a song (200 KB at most)", "error"); return }
    const text = await file.text().catch(() => "")
    if (!text.trim()) { this._note("That file has no words in it", "error"); return }
    this._fill(text, { name: file.name.replace(/\.[^.]+$/, "") })
  }

  tidy(event) {
    event?.preventDefault?.()
    if (!this.bodyTarget.value.trim()) return
    this._fill(this.bodyTarget.value)
  }

  _fill(text, { pasted = false, name = "" } = {}) {
    const { title, body, found } = tidySong(text)
    const field = this.bodyTarget
    field.focus()
    field.select()
    // insertText keeps the browser's undo (Ctrl/⌘+Z gives the raw paste back).
    if (!document.execCommand?.("insertText", false, body)) field.value = body
    if (this.titleTarget.value.trim() === "" && (title || name)) this.titleTarget.value = title || name
    field.setSelectionRange(0, 0)
    field.scrollTop = 0
    this.refresh()
    this._note(`${pasted ? "Pasted and tidied" : "Tidied"} — ${found}${pasted ? " · Ctrl+Z undoes" : ""}`, "ok")
  }

  // ---- the flow line ------------------------------------------------------------------

  refresh() {
    if (!this.hasFlowTarget) return
    this._note(null)
    const body = this.bodyTarget.value
    const arrangement = this.hasArrangementTarget ? this.arrangementTarget.value : ""
    if (!body.trim()) {
      this.flowTarget.replaceChildren(text("Label stanzas with [Verse 1], [Chorus], [Bridge]… on their own line — a chorus typed once repeats after each verse, or set the order below."))
      this.flowTarget.dataset.tone = "hint"
      return
    }
    const { slides, labelled, unknown } = songSlides(body, arrangement)
    const nodes = [ text(`${slides.length} slide${slides.length === 1 ? "" : "s"}`) ]
    if (labelled) {
      nodes.push(text(" · projects as "))
      slides.forEach((s, i) => { if (i) nodes.push(text(" ")); nodes.push(chip(s.code || "·", s.label)) })
    } else if (slides.length > 1) {
      nodes.push(text(" · stanza by stanza"))
    }
    if (unknown.length) nodes.push(text(` · not in this song: ${unknown.join(", ")}`))
    this.flowTarget.replaceChildren(...nodes)
    this.flowTarget.dataset.tone = unknown.length ? "error" : ""
  }

  // ---- save to my songs ------------------------------------------------------------

  async save(event) {
    event?.preventDefault?.()
    const title = this.titleTarget.value.trim()
    const body = this.bodyTarget.value.trim()
    if (!title) { this._note("Give the song a title to save it", "error"); this.titleTarget.focus(); return }
    if (!body) { this._note("Add the words first", "error"); this.bodyTarget.focus(); return }
    if (owner() === "guest") { window.dispatchEvent(new CustomEvent("auth:required")); return }
    const song = { title, body, arrangement: this.hasArrangementTarget ? this.arrangementTarget.value.trim() : "" }
    await queueSongSave(song, owner()).catch(() => {})
    window.dispatchEvent(new CustomEvent("song-bank:saved", { detail: { song } }))
    flushOutbox().catch(() => {})
    this._note(navigator.onLine === false ? `Saved “${title}” to your songs — will sync when online` : `Saved “${title}” to your songs`, "ok")
  }

  _note(message, tone = "") {
    if (!this.hasSavedTarget) return
    this.savedTarget.hidden = !message
    this.savedTarget.textContent = message || ""
    this.savedTarget.dataset.tone = tone
  }
}

function text(t) {
  return document.createTextNode(t)
}

function chip(code, label) {
  const span = document.createElement("span")
  span.className = "chip"
  span.textContent = code
  if (label) span.title = label
  return span
}
