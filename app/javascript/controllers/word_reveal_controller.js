import { Controller } from "@hotwired/stimulus"
import { pickedWord, revealFor, placeCard } from "../lib/word_reveal"
import { verseRootWords } from "../lib/offline/word_pack"

// Hold a word, see the original. A long-press on a phone (or a double-click)
// selects one word; when it is a word of Scripture, its Hebrew or Greek rises
// just below it — the original word, how to say it, what it means — with a
// way into the full word study. It rides on the browser's own selection, so
// highlighting, copying and the selection bar work exactly as before (that bar
// sits at the bottom on touch and above the words with a mouse; this card goes
// under the word). Any translation: the word is matched through the verse's
// Strong's-tagged KJV tokens, from the device's word pack when it has one.
// Lives on .ps-root, reading only. "Original words" in Aa turns it off.
const KEY = "ps:word-reveal"
const SETTLE_MS = 380 // after the highlighter's bar (320 ms), so we can keep clear of it

export default class extends Controller {
  static targets = [ "button" ]
  static values = { lexiconUrl: String } // …/lexicon/G0 — G0 is swapped for the word's number

  connect() {
    if (this.element.classList.contains("is-output")) return
    this.cache = new Map()
    this.seq = 0
    let stored = null
    try { stored = localStorage.getItem(KEY) } catch (_) {}
    this._apply(stored !== "0")
    this._onSelection = () => { clearTimeout(this._timer); this._timer = setTimeout(() => this._check(), SETTLE_MS) }
    this._onKey = (e) => { if (e.key === "Escape") this.hide() }
    this._onMove = () => this.hide()
    document.addEventListener("selectionchange", this._onSelection)
    document.addEventListener("keydown", this._onKey)
    window.addEventListener("resize", this._onMove)
    this.element.addEventListener("scroll", this._onMove, { capture: true, passive: true })
  }

  disconnect() {
    this.hide()
    clearTimeout(this._timer)
    document.removeEventListener("selectionchange", this._onSelection)
    document.removeEventListener("keydown", this._onKey)
    window.removeEventListener("resize", this._onMove)
    this.element.removeEventListener("scroll", this._onMove, { capture: true })
  }

  toggle(event) {
    event?.preventDefault?.()
    const on = this.element.classList.contains("no-word-reveal")
    this._apply(on)
    try { localStorage.setItem(KEY, on ? "1" : "0") } catch (_) {}
  }

  hide() {
    this.seq++
    this.shownKey = null
    this.card?.remove()
    this.card = null
  }

  _apply(on) {
    this.element.classList.toggle("no-word-reveal", !on)
    this.buttonTargets.forEach((b) => b.setAttribute("aria-pressed", String(on)))
    if (!on) this.hide()
  }

  async _check() {
    const here = this._selectedWord()
    if (!here) return this.hide()
    const key = `${here.osis}.${here.chapter}.${here.verse}|${here.word}`
    if (key === this.shownKey) return
    const seq = ++this.seq
    const found = await this._lookup(here)
    if (seq !== this.seq) return // the selection moved on while we looked
    const data = revealFor(found, here.word)
    if (!data) return this.hide()
    this._show(data, here.range)
    this.shownKey = key
  }

  // The one word selected in a verse of the reader, or null.
  _selectedWord() {
    const root = this.element
    if (root.classList.contains("no-word-reveal") || root.classList.contains("is-presenting")) return null
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null
    const word = pickedWord(sel.toString())
    if (!word) return null
    const range = sel.getRangeAt(0)
    const node = range.commonAncestorContainer
    const el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
    const verse = el?.closest?.(".ps-verse[data-osis][data-chapter][data-verse-num]")
    if (!verse || !root.contains(verse) || !verse.closest(".ps-verse-body")) return null
    return { word, range, osis: verse.dataset.osis, chapter: Number(verse.dataset.chapter), verse: Number(verse.dataset.verseNum) }
  }

  async _lookup({ osis, chapter, verse }) {
    const key = `${osis}.${chapter}.${verse}`
    if (!this.cache.has(key)) {
      const pending = verseRootWords(osis, chapter, verse)
      this.cache.set(key, pending)
      // A miss (offline, no pack yet) is worth asking again later.
      pending.then((r) => { if (!r) this.cache.delete(key) })
    }
    return this.cache.get(key)
  }

  _show(data, range) {
    this.card?.remove()
    const card = this._build(data)
    document.body.appendChild(card)
    const rects = range.getClientRects()
    const rect = rects.length ? rects[0] : range.getBoundingClientRect()
    const bar = document.querySelector(".ps-hl-popover.is-touch-bar")
    const place = placeCard({
      rect, width: card.offsetWidth, height: card.offsetHeight,
      viewWidth: window.innerWidth, viewHeight: window.innerHeight,
      bottomInset: bar ? Math.max(0, window.innerHeight - bar.getBoundingClientRect().top) : 0
    })
    card.style.setProperty("--wr-x", `${place.left}px`)
    card.style.setProperty("--wr-y", `${place.top}px`)
    card.style.setProperty("--wr-arrow", `${place.arrow}px`)
    card.classList.add(place.below ? "is-below" : "is-above")
    requestAnimationFrame(() => card.classList.add("is-in"))
    this.card = card
  }

  _build(data) {
    const el = (tag, cls, text) => {
      const n = document.createElement(tag)
      if (cls) n.className = cls
      if (text != null) n.textContent = text
      return n
    }
    const card = el("div", `wr-card is-${data.lang}`)
    card.setAttribute("role", "dialog")
    card.setAttribute("aria-label", `${data.language} word behind “${data.english}”`)
    card.dataset.strongs = data.s

    const head = el("div", "wr-head")
    head.append(el("span", "wr-lang", data.language), el("span", "wr-num", data.s))
    const lemma = el("div", "wr-lemma", data.lemma || data.translit)
    lemma.lang = data.lang === "hebrew" ? "he" : "grc"
    if (data.lang === "hebrew") lemma.dir = "rtl"
    const say = el("div", "wr-say")
    say.append(el("b", null, data.translit))
    if (data.say) say.append(el("span", "wr-dot", " · "), el("span", null, data.say))
    card.append(head, lemma, say)
    if (data.gloss) card.append(el("p", "wr-gloss", data.gloss))

    const foot = el("div", "wr-foot")
    foot.append(el("span", "wr-count", data.count ? `“${data.english}” · ${data.count}` : `“${data.english}”`))
    if (this.lexiconUrlValue) {
      const more = el("button", "wr-more", "Word study →")
      more.type = "button"
      more.addEventListener("pointerdown", (e) => e.preventDefault()) // keep the selection until the click
      more.addEventListener("click", () => this._study(data.s))
      foot.append(more)
    }
    card.append(foot)
    return card
  }

  _study(strongs) {
    this.hide()
    window.getSelection()?.removeAllRanges()
    window.dispatchEvent(new CustomEvent("lexicon:open", { detail: { href: this.lexiconUrlValue.replace(/G0$/, strongs) } }))
  }
}
