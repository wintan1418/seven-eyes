import { Controller } from "@hotwired/stimulus"
import { combineParts, versesToText, textToVerses, toggleMark, clipboardText } from "../lib/slides/combine"
import { passagesFor, copyText } from "../lib/slides/item_words"
import { setBody, setLabel, setPages } from "../lib/slides/scripture_set"
import { paintRichSlide } from "../lib/slides/rich_slides"

// "Combine into one slide" (the operator's Revelation 13:1 + 13:11 — the two
// beasts on one screen): the picked scriptures' words in one editable box,
// the reference line made for you ("Revelation 13:1, 11"), words emphasised
// for the preacher (select → Bold / Highlight), saved in the service as one
// scripture slide that projects, streams and works offline like any other.
//
// Opened by queue-tool:open {tool: "combine", sources | item}:
//   sources  [{ kind: "scripture", reference } | { kind: "scripture_set", data }]
//            (the queue's picked items, or what is in Preview)
//   item     a combined queue item to edit again (✎ / E)
// Logic in lib/slides/combine.js; words via lib/slides/item_words.js.
export default class extends Controller {
  static targets = [ "label", "text", "preview", "hint", "error", "submit", "live", "copied" ]

  connect() {
    this.options = { ref_position: "top", verse_numbers: true }
    this._open = (e) => { if (e.detail?.tool === "combine") this.open(e.detail) }
    window.addEventListener("queue-tool:open", this._open)
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  async open({ sources = null, item = null, translation = null, done = null } = {}) {
    this._editing = item?.cid || null
    this._done = done
    this._error(null)
    this.element.hidden = false
    this.submitTarget.textContent = this._editing ? "Save changes" : "Add to service"
    this.liveTarget.hidden = !!this._editing
    if (item) {
      const ref = item.data?.refs?.[0] || {}
      this._translation = ref.translation || ""
      this._own = !!ref.own
      this.labelTarget.value = ref.label || ref.reference || ""
      const verses = ref.verses || []
      this._multi = new Set(verses.map((v) => v.c).filter(Boolean)).size > 1
      this.textTarget.value = versesToText(verses, { multi: this._multi })
      this.options = { ref_position: item.data?.ref_position || "top", verse_numbers: item.data?.verse_numbers ?? true }
    } else {
      this.labelTarget.value = ""
      this.textTarget.value = ""
      this._hint("Getting the words…", "")
      const { passages, missing } = await passagesFor(sources || [], { translation })
      if (!this.element.isConnected || this.element.hidden) return
      const combined = combineParts(passages)
      this._translation = combined.translation
      this._own = combined.own
      this._multi = combined.multi
      this.labelTarget.value = combined.label
      this.textTarget.value = versesToText(combined.verses, { multi: combined.multi })
      if (missing.length) this._error(`Couldn't get the words of ${missing.join(", ")} — no connection and not on this device`)
    }
    this._paintOptions()
    this._update()
    this.textTarget.focus()
  }

  close(event) {
    event?.preventDefault?.()
    this.element.hidden = true
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  key(event) {
    event.stopPropagation() // preach keys stay out of the form
    const mod = event.metaKey || event.ctrlKey
    if (event.key === "Escape") { event.preventDefault(); this.close() }
    else if (mod && event.key === "Enter") { event.preventDefault(); event.shiftKey ? this.submitLive() : this.submit() }
    else if (mod && (event.key === "b" || event.key === "B") && event.target === this.textTarget) { event.preventDefault(); this._mark("b") }
    else if (mod && (event.key === "m" || event.key === "M") && event.target === this.textTarget) { event.preventDefault(); this._mark("hl") }
  }

  // ---- emphasis ------------------------------------------------------------------------

  bold(event) {
    event?.preventDefault?.()
    this._mark("b")
  }

  highlight(event) {
    event?.preventDefault?.()
    this._mark("hl")
  }

  // Keep the selection when a toolbar button is pressed (mousedown would blur it).
  keepSelection(event) {
    event.preventDefault()
  }

  _mark(kind) {
    const area = this.textTarget
    const { value, start, end } = toggleMark(area.value, area.selectionStart, area.selectionEnd, kind)
    if (value === area.value) { this._hint("Select a word or two in the verses first, then Bold or Highlight", "warn"); return }
    area.value = value
    area.focus()
    area.setSelectionRange(start, end)
    this._update()
  }

  // ---- fields --------------------------------------------------------------------------

  changed() {
    this._update()
  }

  setOption(event) {
    const { option: name, value } = event.currentTarget.dataset
    this.options[name] = name === "verse_numbers" ? value === "true" : value
    this._paintOptions()
    this._update()
  }

  _paintOptions() {
    this.element.querySelectorAll("[data-option]").forEach((b) => {
      const on = String(this.options[b.dataset.option]) === b.dataset.value
      b.classList.toggle("is-on", on)
      b.setAttribute("aria-pressed", String(on))
    })
  }

  _verses() {
    return textToVerses(this.textTarget.value)
  }

  _data() {
    const verses = this._verses()
    const label = this.labelTarget.value.trim().replace(/\s+/g, " ").slice(0, 80)
    return {
      refs: verses.length ? [ { reference: label, label, translation: this._translation || "", verses, ...(this._own ? { own: true } : {}) } ] : [],
      split: "one", combined: true, ref_style: "gold", per_slide: 0, ...this.options
    }
  }

  _update() {
    const verses = this._verses()
    if (!this.textTarget.value.trim()) this._hint("The verses show here — one a line, the verse number first.", "")
    else this._hint(`${verses.length} verse${verses.length === 1 ? "" : "s"} on one slide · select words, then Bold (Ctrl+B) or Highlight (Ctrl+M)`, "ok")
    this._paintPreview()
  }

  _paintPreview() {
    const data = this._data()
    const screen = el("div", "set-screen")
    if (data.refs.length) paintRichSlide(screen, { type: "set", data }, 0)
    else screen.append(el("div", "set-empty", "Your slide shows here as the congregation will see it."))
    this.previewTarget.replaceChildren(screen)
    this._fit(screen)
    this.submitTarget.disabled = !data.refs.length
    this.liveTarget.disabled = !data.refs.length
  }

  _fit(screen) {
    const box = screen.querySelector(".slide-stanza")
    if (!box) return
    let size = 22
    box.style.fontSize = `${size}px`
    while (screen.scrollHeight > screen.clientHeight + 1 && size > 7) {
      size -= 1
      box.style.fontSize = `${size}px`
    }
  }

  // ---- out -----------------------------------------------------------------------------

  async copy(event) {
    event?.preventDefault?.()
    const data = this._data()
    const ref = data.refs[0]
    if (!ref) return
    const ok = await copyText(clipboardText({ label: ref.label, translation: ref.translation, verses: ref.verses, multi: this._multi }))
    this.copiedTarget.hidden = false
    this.copiedTarget.textContent = ok ? "Copied" : "Couldn't copy"
    clearTimeout(this._copiedTimer)
    this._copiedTimer = setTimeout(() => { this.copiedTarget.hidden = true }, 1800)
  }

  submit(event) {
    event?.preventDefault?.()
    this._save({ live: false })
  }

  submitLive(event) {
    event?.preventDefault?.()
    this._save({ live: true })
  }

  _save({ live }) {
    const data = this._data()
    if (!data.refs.length) { this._error("Nothing to show yet — the verses box is empty"); this.textTarget.focus(); return }
    if (!data.refs[0].label) { this._error("Give the slide a reference line — e.g. Revelation 13:1, 11"); this.labelTarget.focus(); return }
    const fields = { kind: "scripture_set", title: null, body: setBody(data), data, label: setLabel(data), stanzas: setPages(data).length, reference: null, arrangement: null }
    if (this._editing) window.dispatchEvent(new CustomEvent("setlist:replace-item", { detail: { cid: this._editing, fields } }))
    else window.dispatchEvent(new CustomEvent("setlist:add-item", { detail: { fields, live, preview: !live } }))
    this._done?.()
    this.close()
  }

  _hint(text, tone) {
    this.hintTarget.textContent = text
    this.hintTarget.dataset.tone = tone || ""
  }

  _error(message) {
    this.errorTarget.hidden = !message
    this.errorTarget.textContent = message || ""
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
