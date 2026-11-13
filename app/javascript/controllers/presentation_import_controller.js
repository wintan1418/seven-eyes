import { Controller } from "@hotwired/stimulus"
import { renderPdf, renderImages, warmPdfjs } from "../lib/slides/pdf_import"
import { saveDeck, getDeck, listDecks, removeDeck, newKey, pageUrl, persistStorage, storageEstimate } from "../lib/slides/deck_store"

// Presentations: import a PDF (PowerPoint / Keynote / Google Slides → "Save as
// PDF") or a handful of pictures, and step through them page by page from the
// queue like any slide. Lives on its dialog ([data-controller=presentation-import]);
// opened by the queue's "Presentation" tool or Edit on a presentation item.
//
// Pages are drawn on this computer (pdf.js, lib/slides/pdf_import) and kept
// in IndexedDB (lib/slides/deck_store) — nothing is uploaded, so there is no
// hosting cost, no data used, no cap from the 30-picture queue limit, and the
// deck projects with no signal. The queue item (synced like any other) only
// carries the deck key and page count; on another computer it asks for the
// file once ("import it again here").
export default class extends Controller {
  static targets = [ "picker", "pdf", "images", "progress", "bar", "status", "result", "title", "thumbs", "submit", "library", "error" ]

  connect() {
    this._open = (e) => { if (e.detail?.tool === "presentation") this.open(e.detail.item) }
    window.addEventListener("queue-tool:open", this._open)
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  async open(item = null) {
    this._item = item || null
    this._pending = null
    this.element.hidden = false
    this._error(null)
    this.progressTarget.hidden = true
    warmPdfjs() // so importing works later with no signal
    if (item?.data?.deck) {
      this._key = item.data.deck
      this.titleTarget.value = item.title || ""
      const deck = await getDeck(item.data.deck)
      this._showResult(deck ? deck.pages : 0, { stored: !!deck })
      if (!deck) this._status("This presentation's pages are on the computer that imported it. Import the same file here to show it on this one.")
    } else {
      this._key = null
      this.titleTarget.value = ""
      this.resultTarget.hidden = true
      this.pickerTarget.hidden = false
      this._status("")
    }
    this.submitTarget.textContent = item ? "Save changes" : "Add to queue"
    this._paintLibrary()
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
  }

  choosePdf() { this.pdfTarget.click() }
  chooseImages() { this.imagesTarget.click() }

  pdfChosen() {
    const file = this.pdfTarget.files?.[0]
    this.pdfTarget.value = ""
    if (file) this._import(() => renderPdf(file, { onProgress: (f, n, total) => this._progress(f, `Drawing page ${n} of ${total}…`) }), "pdf", file.name)
  }

  imagesChosen() {
    const files = [ ...(this.imagesTarget.files || []) ]
    this.imagesTarget.value = ""
    if (files.length) this._import(() => renderImages(files, { onProgress: (f, n, total) => this._progress(f, `Preparing picture ${n} of ${total}…`) }), "images", files[0].name)
  }

  dragOver(event) {
    event.preventDefault()
    this.element.querySelector(".pres-card")?.classList.add("is-drop")
  }

  dragLeave() {
    this.element.querySelector(".pres-card")?.classList.remove("is-drop")
  }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    const files = [ ...(event.dataTransfer?.files || []) ]
    const pdf = files.find((f) => f.type === "application/pdf" || /\.pdf$/i.test(f.name))
    if (pdf) this._import(() => renderPdf(pdf, { onProgress: (f, n, total) => this._progress(f, `Drawing page ${n} of ${total}…`) }), "pdf", pdf.name)
    else if (files.some((f) => /^image\//.test(f.type))) this._import(() => renderImages(files, { onProgress: (f, n, total) => this._progress(f, `Preparing picture ${n} of ${total}…`) }), "images", files[0].name)
    else if (files.some((f) => /\.(pptx?|key|odp)$/i.test(f.name))) this._error("Save it as a PDF first — PowerPoint: File → Save As → PDF · Keynote: File → Export To → PDF · Google Slides: File → Download → PDF.")
  }

  async _import(render, source, file) {
    this._error(null)
    this.pickerTarget.hidden = true
    this.resultTarget.hidden = true
    this.progressTarget.hidden = false
    this._progress(0, "Opening…")
    try {
      const { pages, title, truncated } = await render()
      if (!pages.length) throw new Error("No pages found in that file")
      this._pending = { pages, source, file }
      if (!this.titleTarget.value.trim() || !this._item) this.titleTarget.value = title
      this.progressTarget.hidden = true
      this._showResult(pages.length, { pending: true })
      this._status(truncated ? "Only the first 300 pages were imported." : "")
    } catch (e) {
      this.progressTarget.hidden = true
      this.pickerTarget.hidden = false
      this._error(/pdf\.min\.js|dynamically imported|Failed to fetch/i.test(String(e?.message)) ? "The PDF reader isn't on this computer yet — connect once and open this again." : (e?.message || "Couldn't read that file"))
    }
  }

  _progress(fraction, text) {
    this.barTarget.value = Math.round(fraction * 100)
    this.progressTarget.querySelector(".msg").textContent = text
  }

  _showResult(count, { pending = false } = {}) {
    this.resultTarget.hidden = false
    this.pickerTarget.hidden = !!count
    const thumbs = []
    for (let i = 0; i < Math.min(count, 300); i++) {
      const fig = el("figure", "thumb")
      const img = document.createElement("img")
      img.alt = `Page ${i + 1}`
      if (pending) img.src = URL.createObjectURL(this._pending.pages[i].thumb)
      else pageUrl(this._key, i + 1, { thumb: true }).then((url) => { if (url) img.src = url })
      fig.append(img, el("figcaption", null, String(i + 1)))
      thumbs.push(fig)
    }
    this.thumbsTarget.replaceChildren(...thumbs)
    this.resultTarget.querySelector(".count").textContent = count ? `${count} page${count === 1 ? "" : "s"} — Next / Prev step through them` : ""
    this.submitTarget.disabled = !count && !this._item
  }

  reimport() {
    this.pickerTarget.hidden = false
  }

  async submit(event) {
    event?.preventDefault?.()
    const title = this.titleTarget.value.trim() || "Presentation"
    let data = this._item?.data ? { ...this._item.data } : null
    if (this._pending) {
      const key = this._key || newKey("deck")
      this.submitTarget.disabled = true
      try {
        await saveDeck({ key, title, source: this._pending.source, file: this._pending.file }, this._pending.pages)
      } catch {
        this.submitTarget.disabled = false
        this._error("This computer is out of room for slides — remove an old presentation below and try again.")
        return
      }
      persistStorage()
      data = { deck: key, pages: this._pending.pages.length, source: this._pending.source, file: this._pending.file }
    }
    if (!data) { this._error("Import a PDF or pictures first"); return }
    const fields = { kind: "presentation", title, body: null, reference: null, arrangement: null, data, label: title, stanzas: data.pages }
    if (this._item) window.dispatchEvent(new CustomEvent("setlist:replace-item", { detail: { cid: this._item.cid, fields } }))
    else window.dispatchEvent(new CustomEvent("setlist:add-item", { detail: { fields } }))
    this.close()
  }

  // Presentations kept on this computer, with what they take up.
  async _paintLibrary() {
    const decks = (await listDecks()).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0))
    const est = await storageEstimate()
    const rows = decks.map((d) => {
      const li = el("li")
      li.dataset.key = d.key
      li.append(el("span", "t", d.title || "Presentation"), el("span", "m", `${d.pages} pages · ${mb(d.bytes)}`))
      const rm = el("button", "op", "Remove")
      rm.type = "button"
      rm.dataset.action = "presentation-import#removeStored"
      rm.title = "Remove its pages from this computer"
      li.append(rm)
      return li
    })
    const head = this.libraryTarget.querySelector(".head")
    head.textContent = decks.length
      ? `On this computer: ${decks.length} presentation${decks.length === 1 ? "" : "s"}${est?.quota ? ` · ${mb(est.quota - est.usage)} free` : ""}`
      : ""
    this.libraryTarget.querySelector("ul").replaceChildren(...rows)
    this.libraryTarget.hidden = !decks.length
  }

  async removeStored(event) {
    const key = event.currentTarget.closest("[data-key]")?.dataset.key
    if (!key || !window.confirm("Remove this presentation's pages from this computer? A queue that still lists it will ask for the file again.")) return
    await removeDeck(key).catch(() => {})
    this._paintLibrary()
  }

  _status(text) {
    this.statusTarget.textContent = text || ""
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

function mb(bytes) {
  const n = Number(bytes) || 0
  return n >= 1e9 ? `${(n / 1e9).toFixed(1)} GB` : `${Math.max(0.1, n / 1e6).toFixed(1)} MB`
}
