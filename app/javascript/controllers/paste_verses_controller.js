import { Controller } from "@hotwired/stimulus"
import { warmLocal, localState } from "../lib/offline/local_pane"
import { splitPasted, checkSize, cleanVersion, versesText, VERSION_CHOICES } from "../lib/slides/paste_verses"
import { setBody, setLabel, setPages, labelOf } from "../lib/slides/scripture_set"
import { paintRichSlide } from "../lib/slides/rich_slides"

// "Paste your own": the pastor pastes the passage they preach from their own
// Bible app (NKJV, NIV, AMP… — not on BiblioRata, they're licensed) and it
// becomes verse slides with the version credit ("John 3:16-18 (NKJV)").
// Opened by queue-tool:open {tool: "paste-verses", item?}. The words are kept
// only in this service's queue item (a scripture_set whose ref is `own`), so it
// projects offline, on the stage and phones like any scripture slide — and is
// never added to a Bible or a search. Splitting is lib/slides/paste_verses.js.
export default class extends Controller {
  static targets = [ "reference", "version", "other", "text", "hint", "error", "preview", "pager", "submit" ]

  connect() {
    this.options = { per_slide: 0, verse_numbers: true }
    this._page = 0
    this._open = (e) => { if (e.detail?.tool === "paste-verses") this.open(e.detail.item, { live: !!e.detail.live }) }
    window.addEventListener("queue-tool:open", this._open)
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  // live: opened from the Go box — adding also puts it on the screen.
  async open(item = null, { live = false } = {}) {
    this._editing = item?.cid || null
    this._live = live && !this._editing
    const ref = item?.data?.refs?.find((r) => r.own) || null
    this.referenceTarget.value = ref?.reference || ref?.label || ""
    this._setVersion(ref?.translation || this._lastVersion() || "NKJV")
    this.textTarget.value = ref ? versesText(ref.verses) : ""
    this.options = { per_slide: Number(item?.data?.per_slide) || 0, verse_numbers: item?.data?.verse_numbers ?? true }
    this._title = item?.title || null
    this._page = 0
    this._versionTouched = !!ref
    this.submitTarget.textContent = this._editing ? "Save changes" : (this._live ? "Add & show" : "Add to service")
    this.element.hidden = false
    this._error(null)
    ;(this.referenceTarget.value ? this.textTarget : this.referenceTarget).focus()
    this._paintOptions()
    this._update()
    if (!localState().parse) { await warmLocal().catch(() => {}); this._update() }
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
    if (event.key === "Escape") { event.preventDefault(); this.close() }
    else if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); this.submit() }
  }

  // ---- fields -------------------------------------------------------------------------

  changed(event) {
    if (event?.target === this.otherTarget) this._versionTouched = true
    this._page = 0
    this._update()
  }

  versionChanged() {
    this._versionTouched = true
    this.otherTarget.hidden = this.versionTarget.value !== "other"
    if (!this.otherTarget.hidden) this.otherTarget.focus()
    this._update()
  }

  _setVersion(code) {
    const v = cleanVersion(code)
    const known = VERSION_CHOICES.includes(v)
    this.versionTarget.value = known ? v : "other"
    this.otherTarget.hidden = known
    this.otherTarget.value = known ? "" : v
  }

  _version() {
    return this.versionTarget.value === "other" ? cleanVersion(this.otherTarget.value) : this.versionTarget.value
  }

  _lastVersion() {
    try { return localStorage.getItem("ps-paste-version") } catch { return null }
  }

  setOption(event) {
    const { option: name, value } = event.currentTarget.dataset
    this.options[name] = name === "per_slide" ? Number(value) : value === "true"
    this._page = 0
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

  page(event) {
    const pages = setPages(this._data()).length
    this._page = Math.max(0, Math.min(pages - 1, this._page + Number(event.currentTarget.dataset.delta)))
    this._paintPreview()
  }

  // ---- reading the paste ---------------------------------------------------------------

  _parsed() {
    const typed = this.referenceTarget.value.trim()
    const p = typed ? localState().parse?.(typed) : null
    return p?.valid ? p : null
  }

  _update() {
    const p = this._parsed()
    const start = p?.verseStart ? { c: p.chapter, n: p.verseStart, single: p.verseEnd === p.verseStart } : null
    const result = splitPasted(this.textTarget.value, { start, parse: localState().parse })
    // The paste names its reference / version ("John 3:16 NKJV"): fill them in.
    if (!this.referenceTarget.value.trim() && result.reference) {
      this.referenceTarget.value = result.reference
      return this._update()
    }
    if (result.version && !this._versionTouched) this._setVersion(result.version)
    this._verses = result.verses
    const problem = checkSize(result.verses)
    this._problem = problem
    if (!this.textTarget.value.trim()) this._hint("Verse numbers like 16, [16] or ¹⁶ are found for you; Bible app footers and links are taken off.", "")
    else if (problem) this._hint(problem, "error")
    else if (!result.verses.length) this._hint("Nothing to show yet — paste the verse words.", "warn")
    else if (result.verses.length === 1 && result.verses[0].n > 0) this._hint(`Found verse ${result.verses[0].n}`, "ok")
    else if (result.numbered) this._hint(`Found ${result.verses.length} verse${result.verses.length === 1 ? "" : "s"} (${rangeText(result.verses)})`, "ok")
    else this._hint("No verse numbers in the paste — split into slides by sentences.", "ok")
    this._paintPreview()
  }

  _label() {
    const p = this._parsed()
    return p ? labelOf(p) : this.referenceTarget.value.trim().replace(/\s+/g, " ").slice(0, 80)
  }

  _data() {
    const verses = this._problem ? [] : (this._verses || [])
    const reference = this.referenceTarget.value.trim().slice(0, 80)
    return {
      refs: verses.length ? [ { reference, label: this._label(), translation: this._version(), own: true, verses } ] : [],
      ref_position: "top", ref_style: "gold", split: "auto", ...this.options
    }
  }

  _paintPreview() {
    const data = this._data()
    const pages = setPages(data)
    this._page = Math.min(this._page, Math.max(0, pages.length - 1))
    const screen = el("div", "set-screen")
    if (pages.length) paintRichSlide(screen, { type: "set", data }, this._page)
    else screen.append(el("div", "set-empty", "Your slides show here as the congregation will see them."))
    this.previewTarget.replaceChildren(screen)
    this._fit(screen)
    this.pagerTarget.querySelector(".n").textContent = pages.length ? `Slide ${this._page + 1} of ${pages.length}` : ""
    this.pagerTarget.querySelectorAll("button").forEach((b) => { b.disabled = pages.length < 2 })
    this.submitTarget.disabled = !pages.length
  }

  _fit(screen) {
    const box = screen.querySelector(".slide-stanza")
    if (!box) return
    let size = 22
    box.style.fontSize = `${size}px`
    while (screen.scrollHeight > screen.clientHeight + 1 && size > 8) {
      size -= 1
      box.style.fontSize = `${size}px`
    }
  }

  // ---- add to the service ----------------------------------------------------------------

  submit(event) {
    event?.preventDefault?.()
    if (!this.referenceTarget.value.trim()) { this._error("Type the reference you're reading — e.g. John 3:16-18"); this.referenceTarget.focus(); return }
    if (!this._version()) { this._error("Name the version — e.g. NKJV"); this.otherTarget.focus(); return }
    if (this._problem) { this._error(this._problem); return }
    const data = this._data()
    if (!data.refs.length) { this._error("Paste the verse words first"); this.textTarget.focus(); return }
    try { localStorage.setItem("ps-paste-version", this._version()) } catch { /* private mode */ }
    const title = this._title || null
    const fields = { kind: "scripture_set", title, body: setBody(data), data, label: title || setLabel(data), stanzas: setPages(data).length, reference: null, arrangement: null }
    if (this._editing) window.dispatchEvent(new CustomEvent("setlist:replace-item", { detail: { cid: this._editing, fields } }))
    else window.dispatchEvent(new CustomEvent("setlist:add-item", { detail: { fields, live: this._live } }))
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

function rangeText(verses) {
  const first = verses[0]
  const last = verses[verses.length - 1]
  if (verses.length === 1) return `verse ${first.n}`
  return first.c && last.c && first.c !== last.c ? `${first.c}:${first.n}–${last.c}:${last.n}` : `verses ${first.n}–${last.n}`
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
