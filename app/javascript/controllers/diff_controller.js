import { Controller } from "@hotwired/stimulus"

// Word-level translation diff: when two or more panes show the same verse,
// highlight the words that aren't shared across all of them.
//
// Trade-off: when diff mode is ON, .ps-verse-text content is replaced with
// word spans, which suppresses Strong's lexicon links inside KJV panes. The
// originals are restored on toggle-off, so this is non-destructive.
const WORD_RE = /[\p{L}\p{N}']+/gu

export default class extends Controller {
  static targets = ["button"]

  connect() {
    // A pane re-rendered (new chapter / translation) while diff mode is on:
    // the comparison changed, so restore everything and paint afresh.
    this._onFrameRender = (e) => {
      if (!this.element.classList.contains("is-diff")) return
      if (!e.target.classList?.contains("ps-pane")) return
      this.restore()
      this.paint()
    }
    this.element.addEventListener("turbo:frame-render", this._onFrameRender)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this._onFrameRender)
  }

  toggle(event) {
    event?.preventDefault?.()
    const on = !this.element.classList.contains("is-diff")
    this.element.classList.toggle("is-diff", on)
    if (this.hasButtonTarget) this.buttonTarget.classList.toggle("is-active", on)
    on ? this.paint() : this.restore()
  }

  paint() {
    const verses = Array.from(this.element.querySelectorAll(".ps-pane .ps-verse"))
    const groups = new Map()
    verses.forEach(v => {
      const key = `${v.dataset.osis}:${v.dataset.chapter}:${v.dataset.verseNum}`
      if (!key || key.includes("undefined")) return
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key).push(v)
    })

    groups.forEach(list => {
      if (list.length < 2) return
      const textNodes = list.map(v => v.querySelector(".ps-verse-text")).filter(Boolean)
      if (textNodes.length < 2) return

      // The drop cap ("I" of "In the beginning") is rendered outside
      // .ps-verse-text; put it back so the first word compares whole.
      const prefixes = textNodes.map(n => this._dropcapOf(n)?.textContent || "")
      const wordSets = textNodes.map((n, i) => new Set(this._tokenize(prefixes[i] + n.textContent)))
      const intersection = new Set([...wordSets[0]].filter(w => wordSets.every(s => s.has(w))))
      if (intersection.size === wordSets[0].size && wordSets.every(s => s.size === intersection.size)) {
        return // identical text across all panes — nothing to mark
      }

      textNodes.forEach((node, i) => {
        if (node.dataset.diffOriginal != null) return
        node.dataset.diffOriginal = node.innerHTML
        node.innerHTML = this._wrap(node.textContent, intersection, prefixes[i])
        if (prefixes[i]) {
          const first = (this._tokenize(prefixes[i] + node.textContent)[0]) || ""
          this._dropcapOf(node)?.classList.toggle("ps-diff-only", !intersection.has(first))
        }
      })
    })
  }

  restore() {
    this.element.querySelectorAll(".ps-verse-text[data-diff-original]").forEach(n => {
      n.innerHTML = n.dataset.diffOriginal
      delete n.dataset.diffOriginal
    })
    this.element.querySelectorAll(".ps-dropcap.ps-diff-only").forEach(d => d.classList.remove("ps-diff-only"))
  }

  _dropcapOf(textNode) {
    const prev = textNode.previousElementSibling
    return prev?.classList.contains("ps-dropcap") ? prev : null
  }

  _tokenize(text) {
    return (text.match(WORD_RE) || []).map(w => w.toLowerCase())
  }

  _wrap(text, intersection, prefix = "") {
    const re = new RegExp(WORD_RE.source, "gu")
    let out = ""
    let i = 0
    let m
    while ((m = re.exec(text)) !== null) {
      if (m.index > i) out += this._escape(text.slice(i, m.index))
      const word = m[0]
      // The first word continues the drop cap's letter when they touch.
      const whole = m.index === 0 && /[\p{L}\p{N}']$/u.test(prefix) ? prefix + word : word
      const cls = intersection.has(whole.toLowerCase()) ? "ps-word" : "ps-word ps-diff-only"
      out += `<span class="${cls}">${this._escape(word)}</span>`
      i = m.index + word.length
    }
    if (i < text.length) out += this._escape(text.slice(i))
    return out
  }

  _escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
