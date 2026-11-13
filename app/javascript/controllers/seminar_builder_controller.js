import { Controller } from "@hotwired/stimulus"
import { LAYOUTS, blankSlide, seminarSteps, seminarBody } from "../lib/slides/seminar"
import { paintRichSlide } from "../lib/slides/rich_slides"
import { saveImage, newKey, imageUrl } from "../lib/slides/deck_store"
import { renderPicture } from "../lib/slides/pdf_import"

// Seminar slides, built in the app — for teaching sessions and seminars
// without PowerPoint. A deck of slides, each with a layout (Title · Title +
// points · Title + picture · Big quote / scripture · Section divider) and
// speaker notes; points can reveal one at a time. Lives on its dialog
// ([data-controller=seminar-builder]); opened by the queue's "Seminar" tool or
// Edit on a seminar item. The deck is one queue item (data.slides), so it syncs,
// works offline and steps with Next / Prev like any slide; pictures stay on
// this computer (lib/slides/deck_store).
//
// Also owns "Seminar mode" (queue-tool:open {tool: "seminar-mode"}): the preach
// bar drops the verse-only tools (verses per slide, parallel, split,
// emphasise) and the stage screen becomes a presenter view (notes + timer).
const MODE_KEY = "ps-seminar-mode"

export default class extends Controller {
  static targets = [ "deckTitle", "reveal", "list", "layouts", "title", "text", "textLabel", "cite", "picture", "pictureName", "notes", "preview", "submit", "error" ]

  connect() {
    this._open = (e) => {
      if (e.detail?.tool === "seminar") this.open(e.detail.item)
      else if (e.detail?.tool === "seminar-mode") this.toggleMode()
    }
    window.addEventListener("queue-tool:open", this._open)
    this._applyMode(readMode())
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  // ---- seminar mode ------------------------------------------------------------------

  toggleMode() {
    const on = !this._root()?.classList.contains("is-seminar")
    try { localStorage.setItem(MODE_KEY, on ? "1" : "0") } catch { /* private mode */ }
    this._applyMode(on)
  }

  _applyMode(on) {
    const root = this._root()
    if (!root || root.classList.contains("is-output")) return
    root.classList.toggle("is-seminar", on)
    root.querySelectorAll("[data-tool='seminar-mode']").forEach((b) => b.setAttribute("aria-pressed", String(on)))
  }

  _root() {
    return this.element.closest(".ps-root")
  }

  // ---- open / close --------------------------------------------------------------------

  open(item = null) {
    this._editing = item?.cid || null
    const data = item?.data || {}
    this.slides = (data.slides?.length ? data.slides : [ { ...blankSlide("title") }, blankSlide("bullets") ]).map((s) => ({ ...blankSlide(), ...s }))
    this.revealTarget.checked = !!data.reveal
    this.deckTitleTarget.value = item?.title || ""
    this._at = 0
    this.submitTarget.textContent = this._editing ? "Save changes" : "Add to queue"
    this._error(null)
    this.element.hidden = false
    this._paintList()
    this._load()
    this.titleTarget.focus()
  }

  close(event) {
    event?.preventDefault?.()
    this.element.hidden = true
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  key(event) {
    event.stopPropagation()
    if (event.key === "Escape") { event.preventDefault(); this.close() }
    else if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); this.submit() }
  }

  // ---- the slide list --------------------------------------------------------------------

  pick(event) {
    this._at = Number(event.currentTarget.closest("[data-i]").dataset.i)
    this._paintList()
    this._load()
  }

  addSlide(event) {
    const layout = event?.currentTarget?.dataset.layout || "bullets"
    this.slides.splice(this._at + 1, 0, blankSlide(layout))
    this._at += 1
    this._paintList()
    this._load()
    this.titleTarget.focus()
  }

  duplicate() {
    this.slides.splice(this._at + 1, 0, { ...this.slides[this._at] })
    this._at += 1
    this._paintList()
    this._load()
  }

  remove() {
    if (this.slides.length <= 1) { this.slides = [ blankSlide() ]; this._at = 0 } else {
      this.slides.splice(this._at, 1)
      this._at = Math.min(this._at, this.slides.length - 1)
    }
    this._paintList()
    this._load()
  }

  move(event) {
    const j = this._at + Number(event.currentTarget.dataset.delta)
    if (j < 0 || j >= this.slides.length) return
    ;[ this.slides[this._at], this.slides[j] ] = [ this.slides[j], this.slides[this._at] ]
    this._at = j
    this._paintList()
    this._paintPreview()
  }

  _paintList() {
    this.listTarget.replaceChildren(...this.slides.map((s, i) => {
      const li = el("li", `sem-row${i === this._at ? " is-on" : ""}`)
      li.dataset.i = String(i)
      const b = el("button", "pick")
      b.type = "button"
      b.dataset.action = "seminar-builder#pick"
      b.append(el("span", "n", String(i + 1)), el("span", "t", s.title || (s.layout === "quote" ? s.text : "") || "Untitled slide"),
        el("span", "k", LAYOUTS.find((l) => l.id === s.layout)?.name || ""))
      li.append(b)
      return li
    }))
  }

  // ---- editing the picked slide ----------------------------------------------------------

  _load() {
    const s = this.slides[this._at]
    this.titleTarget.value = s.title
    this.textTarget.value = s.text
    this.citeTarget.value = s.cite
    this.notesTarget.value = s.notes
    this._paintLayout()
    this._paintPreview()
  }

  setLayout(event) {
    this.slides[this._at].layout = event.currentTarget.dataset.layout
    this._paintLayout()
    this._paintList()
    this._paintPreview()
  }

  _paintLayout() {
    const s = this.slides[this._at]
    this.layoutsTarget.querySelectorAll("[data-layout]").forEach((b) => {
      b.classList.toggle("is-on", b.dataset.layout === s.layout)
      b.setAttribute("aria-pressed", String(b.dataset.layout === s.layout))
    })
    this.element.querySelector(".sem-editor").dataset.layout = s.layout
    const labels = { title: "Subtitle", bullets: "Points — one per line", image: "Caption (optional)", quote: "Quote or scripture", section: "Subtitle (optional)" }
    this.textLabelTarget.textContent = labels[s.layout]
    this.textTarget.rows = s.layout === "bullets" ? 6 : 3
    this.pictureNameTarget.textContent = s.image ? "Picture on this computer ✓" : "No picture yet"
  }

  edited() {
    Object.assign(this.slides[this._at], {
      title: this.titleTarget.value, text: this.textTarget.value, cite: this.citeTarget.value, notes: this.notesTarget.value
    })
    const row = this.listTarget.querySelector(`[data-i="${this._at}"] .t`)
    const s = this.slides[this._at]
    if (row) row.textContent = s.title || (s.layout === "quote" ? s.text : "") || "Untitled slide"
    this._paintPreview()
  }

  choosePicture() { this.pictureTarget.click() }

  async pictureChosen() {
    const file = this.pictureTarget.files?.[0]
    this.pictureTarget.value = ""
    if (!file) return
    try {
      const page = await renderPicture(file)
      const key = newKey("img")
      await saveImage(key, page.blob, page.thumb)
      this.slides[this._at].image = `local:${key}`
      if (!this.slides[this._at].title) this.titleTarget.focus()
      this._paintLayout()
      this._paintPreview()
    } catch {
      this._error("Couldn't use that picture — try a JPG or PNG")
    }
  }

  // ---- preview + save ----------------------------------------------------------------------

  _data() {
    return { slides: this.slides.map((s) => ({ ...s })), reveal: this.revealTarget.checked }
  }

  revealChanged() {
    this._paintPreview()
  }

  _paintPreview() {
    const data = this._data()
    // Show the picked slide fully revealed.
    const steps = seminarSteps(data)
    const index = steps.findLastIndex ? steps.findLastIndex((st) => st.slide === this._at) : steps.map((st) => st.slide).lastIndexOf(this._at)
    const screen = el("div", "set-screen sem-screen")
    paintRichSlide(screen, { type: "seminar", data }, Math.max(0, index))
    this.previewTarget.replaceChildren(screen)
    const box = screen.querySelector(".slide-stanza")
    if (box) {
      let size = 18
      box.style.fontSize = `${size}px`
      while (screen.scrollHeight > screen.clientHeight + 1 && size > 7) { size -= 1; box.style.fontSize = `${size}px` }
    }
    // keep the editor's picture thumb fresh
    const s = this.slides[this._at]
    if (s.layout === "image" && s.image) imageUrl(s.image, { thumb: true })
  }

  submit(event) {
    event?.preventDefault?.()
    this.edited()
    const data = this._data()
    data.slides = data.slides.filter((s) => s.title.trim() || s.text.trim() || s.image)
    if (!data.slides.length) { this._error("Give a slide a title or some words first"); return }
    const title = this.deckTitleTarget.value.trim() || data.slides.find((s) => s.title.trim())?.title.trim() || "Seminar"
    const fields = { kind: "seminar", title, body: seminarBody(data), data, reference: null, arrangement: null, label: title, stanzas: data.slides.length }
    if (this._editing) window.dispatchEvent(new CustomEvent("setlist:replace-item", { detail: { cid: this._editing, fields } }))
    else window.dispatchEvent(new CustomEvent("setlist:add-item", { detail: { fields } }))
    this.close()
  }

  _error(message) {
    this.errorTarget.hidden = !message
    this.errorTarget.textContent = message || ""
  }
}

function readMode() {
  try { return localStorage.getItem(MODE_KEY) === "1" } catch { return false }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
