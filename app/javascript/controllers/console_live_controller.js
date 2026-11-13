import { Controller } from "@hotwired/stimulus"
import { songSlides } from "../lib/song_sheet"
import { richSlides } from "../lib/slides/rich_slides"

// The console's LIVE column and the toolbar's state pill: what the room sees.
// Lives on the Live region of _console (operator window only).
//
//   state pill   [data-cx-state] in the toolbar — "LIVE John 3:16", "BLACK",
//                "CLEARED", "LOGO", "COUNTDOWN" (the last three when the screen
//                controls set root data-screen-mode).
//   veil         over the live miniature whenever the words aren't what the room
//                sees, so nobody mistakes a dark screen for a live verse.
//   slide list   EasyWorship's live list: the chapter's verses (the passage on
//                screen) or the song's slides in projection order, the current
//                one marked. A click puts that line up — preach:command
//                {action:"verse"|"slide"}, handled by presentation_controller.
//
// Reads preach:state (the presentation controller's broadcast) and the
// presented pane's verses; never changes what is on screen by itself.
const MODES = {
  live: [ "Live", "" ],
  black: [ "Black", "The screen is dark — press . (or Black) to bring the words back" ],
  clear: [ "Cleared", "The words are hidden; the background stays — the next slide brings them back" ],
  logo: [ "Logo", "Your logo is on the screen — press Logo again to go back" ],
  countdown: [ "Countdown", "The countdown is on the screen" ]
}

export default class extends Controller {
  static targets = [ "list", "listTitle", "veil", "veilWord", "veilNote" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root || this.root.classList.contains("is-output")) return
    this._state = null
    this._signature = null
    this._onState = (e) => this._update(e.detail)
    window.addEventListener("preach:state", this._onState)
    this._mode = new MutationObserver(() => this._paintMode())
    this._mode.observe(this.root, { attributes: true, attributeFilter: [ "class", "data-screen-mode" ] })
    this._paintMode()
  }

  disconnect() {
    window.removeEventListener("preach:state", this._onState)
    this._mode?.disconnect()
  }

  // ---- what's on screen ---------------------------------------------------------------

  _update(state) {
    if (!state) return
    this._state = state
    const label = this._label(state)
    const what = this.root.querySelector("[data-cx-state-label]")
    if (what) what.textContent = label
    this._paintMode()
    this._paintList(state)
  }

  _label(state) {
    if (state.slide) return state.slide.title || (state.slide.image ? "Picture" : "Slide")
    const ref = String(state.reference || "").trim()
    if (!ref) return "Nothing on the screen yet"
    const chapter = ref.replace(/\s*[:.]\s*\d.*$/, "")
    const first = state.verseStart
    const last = state.verseEnd ?? first
    if (!first) return chapter
    return `${chapter}:${first}${last && last !== first ? `–${last}` : ""}`
  }

  _paintMode() {
    if (!this.root.classList.contains("is-preaching")) return
    const declared = this.root.dataset.screenMode
    const mode = declared && MODES[declared] && declared !== "live" ? declared
      : (this.root.classList.contains("is-blank") ? "black" : "live")
    const pill = this.root.querySelector("[data-cx-state]")
    if (pill) {
      pill.dataset.cxState = mode
      const word = pill.querySelector("[data-cx-state-word]")
      if (word) word.textContent = MODES[mode][0]
    }
    if (this.hasVeilTarget) {
      this.veilTarget.hidden = mode === "live"
      this.veilTarget.dataset.mode = mode
      this.veilWordTarget.textContent = MODES[mode][0]
      this.veilNoteTarget.textContent = MODES[mode][1]
    }
  }

  // ---- the live slide list --------------------------------------------------------------

  _paintList(state) {
    if (!this.hasListTarget) return
    const rows = state.slide ? this._slideRows(state.slide) : this._verseRows()
    const signature = state.slide
      ? `slide|${state.slide.title}|${state.slide.body}|${state.slide.arrangement}|${state.slide.image}|${JSON.stringify(state.slide.rich || null)}`
      : `verses|${state.reference}|${state.translation}|${rows.length}|${rows[0]?.key}`
    if (signature !== this._signature) {
      this._signature = signature
      this.listTitleTarget.textContent = state.slide ? (state.slide.title || "Slides") : (this._chapterTitle(state) || "On the screen")
      this.listTarget.replaceChildren(...rows.map((r) => this._row(r)))
      if (!rows.length) this.listTarget.replaceChildren(el("li", "cx-empty", "Nothing on the screen yet"))
    }
    const current = state.slide
      ? (n) => n === (state.slide.index || 0)
      : (n) => n >= (state.verseStart ?? -1) && n <= (state.verseEnd ?? state.verseStart ?? -1)
    let first = null
    this.listTarget.querySelectorAll("li[data-n]").forEach((li) => {
      const on = current(Number(li.dataset.n))
      li.classList.toggle("is-live", on)
      if (on && !first) first = li
    })
    if (first && !this.listTarget.matches(":hover")) scrollWithin(first, this.listTarget)
  }

  _chapterTitle(state) {
    const ref = String(state.reference || "").replace(/\s*[:.]\s*\d.*$/, "")
    const pane = this.root.querySelector(".ps-pane.is-presented")
    const code = pane?.querySelector("select[name='pane[translation_id]'] option:checked")?.textContent?.trim()
    return ref ? `${ref}${code ? ` · ${code}` : ""}` : ""
  }

  _verseRows() {
    const pane = this.root.querySelector(".ps-pane.is-presented")
    if (!pane) return []
    return Array.from(pane.querySelectorAll(".ps-verse")).map((v) => {
      const n = Number(v.dataset.verseNum)
      const text = Array.from(v.querySelectorAll(".ps-verse-text")).map((t) => t.textContent).join("").trim()
      return { key: `v${n}`, n, tag: String(n), text, action: "verse" }
    }).filter((r) => r.n)
  }

  _slideRows(slide) {
    if (slide.rich) {
      return (richSlides(slide.rich) || []).map((s, i) => ({ key: `r${i}`, n: i, tag: s.label || String(i + 1), text: s.text, action: "slide" }))
    }
    if (slide.image) return [ { key: "pic", n: 0, tag: "Picture", text: slide.title || "", action: "slide" } ]
    const { slides } = songSlides(slide.body, slide.arrangement)
    return slides.filter((s) => s.text).map((s, i) => ({ key: `s${i}`, n: i, tag: s.label || String(i + 1), text: s.text, action: "slide" }))
  }

  _row(r) {
    const li = el("li", "cx-line")
    li.dataset.n = String(r.n)
    const btn = el("button", "pick")
    btn.type = "button"
    btn.dataset.action = "console-live#go"
    btn.dataset.kind = r.action
    btn.title = r.action === "verse" ? `Put verse ${r.n} on the screen` : "Put this slide on the screen"
    btn.append(el("span", "tag", r.tag), el("span", "txt", r.text))
    li.append(btn)
    return li
  }

  go(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const n = Number(btn.closest("li")?.dataset.n)
    if (Number.isNaN(n)) return
    window.dispatchEvent(new CustomEvent("preach:command", { detail: { action: btn.dataset.kind, value: n } }))
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

// Keep a row in view inside its own scroll box (never scroll the page).
function scrollWithin(row, box) {
  const r = row.getBoundingClientRect()
  const b = box.getBoundingClientRect()
  if (r.top < b.top) box.scrollTop -= b.top - r.top + 4
  else if (r.bottom > b.bottom) box.scrollTop += r.bottom - b.bottom + 4
}
