import { Controller } from "@hotwired/stimulus"
import { warmLocal, localState } from "../lib/offline/local_pane"
import { referenceLabel } from "../lib/offline/reference_parser"
import { verseRootWords, ensureWordPack, packInfo, downloadWordPack } from "../lib/offline/word_pack"
import { isNetworkSlow } from "../lib/offline/network"
import { signedIn } from "../lib/offline/page"
import {
  verseWords, tokenForWord, buildWordStudy, wordStudyTitle, encodeWordStudy, findWord,
  readableTranslit, sayIt, gloss, kjvRenderings, occurrencesLabel, languageLabel
} from "../lib/root_words"

// Root-word card (preach mode, operator only). A self-contained popover:
// it reads which verse is live (or in Preview) from the page, shows that
// verse's Strong's-tagged KJV words, and on "Project" hands a word study to
// the presentation controller through the queue's own path (setlist:present),
// so the slide reaches the projector, stage and phones like any song slide.
//
//   open:  ℵ Root word in the preach bar · W (live verse) · Shift+W (Preview)
//          · ℵ in the Preview row · a tagged word clicked on the live verse
//   in the card:  ← →  pick a word   Enter  project beside the verse
//                 Shift+Enter  word only   +  queue   R  ask Rabbi   Esc  close
//   while open:   tap any word of the live verse to pick it (any translation)
//
// Other translations map through the KJV verse with the same reference: its
// tagged words are offered, and the slide marks the word in the projected
// translation when it appears there (else shows the KJV wording).
// Not the word to preselect: very common words and the little ones (for, so,
// that, the, and, him…) — the card opens on the first word worth preaching.
const COMMON_ABOVE = 1000
const PARTICLES = new Set([ "G1063", "G2532", "G3588", "G846", "G3754", "G1161", "G1519", "G1722", "G3361", "G3756",
  "G2443", "G3779", "G235", "G1537", "G575", "G4314", "G1909", "G1223", "G2596", "G3326", "G4012", "G3739", "G3956",
  "G5100", "G1510", "G3767", "G1437", "G1487", "H853", "H413", "H5921", "H3605", "H834", "H3588", "H3808", "H854",
  "H4480", "H5704", "H1931", "H589", "H859", "H3651", "H1571", "H518" ])
const EXPLAIN_TIMEOUT_MS = 20_000
const EXPLAIN_CACHE = "ps-rootword-notes"

export default class extends Controller {
  static targets = [ "card", "title", "mapNote", "words", "detail", "english", "lemma", "translit", "say", "strongs",
    "gloss", "kjv", "count", "rabbiButton", "rabbiBox", "rabbiText", "rabbiInclude", "rabbiStatus", "layoutButton",
    "status", "offlineButton" ]
  static values = { explainUrl: String }

  initialize() {
    this._words = []
    this._entries = {}
    this._selected = null
    this._layout = "verse"
    this._edits = {} // strongs → edited gloss
    this._ctx = null // { osis, chapter, verse, reference, translation, text, kjvText }
    this._preview = null
  }

  connect() {
    this._root = this.element.closest(".ps-root")
    if (!this._root || this._root.classList.contains("is-output")) return
    this._onClick = (e) => {
      const opener = e.target.closest?.("[data-root-words-open]")
      if (opener) { e.preventDefault(); this.open(opener.dataset.rootWordsOpen || "live"); return }
      if (this._isOpen && this._ctx?.source === "live") this._pickFromVerse(e)
    }
    this._onKey = (e) => this._key(e)
    this._onPreview = (e) => this._previewChanged(e.detail)
    this._onEnter = () => { if (signedIn()) ensureWordPack().then(() => this._paintOffline()) }
    this._root.addEventListener("click", this._onClick, true)
    document.addEventListener("keydown", this._onKey, true)
    window.addEventListener("preview:changed", this._onPreview)
    window.addEventListener("preach:enter", this._onEnter)
  }

  disconnect() {
    this._root?.removeEventListener("click", this._onClick, true)
    document.removeEventListener("keydown", this._onKey, true)
    window.removeEventListener("preview:changed", this._onPreview)
    window.removeEventListener("preach:enter", this._onEnter)
  }

  get _isOpen() { return this.hasCardTarget && !this.cardTarget.hidden }
  get _preaching() { return this._root.classList.contains("is-preaching") }

  // ---- opening -------------------------------------------------------------------

  async open(source = "live", { tapped = null } = {}) {
    await warmLocal()
    const ctx = source === "preview" ? this._previewContext() : this._liveContext()
    if (!ctx) {
      this._notice(source === "preview" ? "Preview a single verse first, then pick its root words"
        : "Put a verse on screen first, then pick its root words")
      return
    }
    this._ctx = ctx
    this.cardTarget.hidden = false
    this._root.classList.toggle("is-rootwords", source === "live")
    this.titleTarget.textContent = `${ctx.reference}${ctx.translation ? ` · ${ctx.translation}` : ""}`
    this.wordsTarget.replaceChildren(el("span", "rw-loading", "Finding the original words…"))
    this.detailTarget.hidden = true
    this.mapNoteTarget.hidden = !ctx.translation || ctx.translation === "KJV"
    this._resetRabbi()
    this._paintOffline()
    const seq = (this._seq = (this._seq || 0) + 1)
    const data = await verseRootWords(ctx.osis, ctx.chapter, ctx.verse)
    if (seq !== this._seq) return
    if (!data || !data.tokens.some((t) => t.s)) {
      const stored = await packInfo()
      const cutOff = !data && !stored && (navigator.onLine === false || isNetworkSlow())
      this.wordsTarget.replaceChildren(el("span", "rw-empty", cutOff
        ? "The word data isn't on this device yet — connect once (or tap “Save for offline”) and try again."
        : `The KJV has no Strong’s numbers for ${ctx.reference} — try the verse before or after.`))
      return
    }
    ctx.kjvText = data.tokens.map((t) => t.w).join("").replace(/\s+/g, " ").trim()
    this._entries = data.entries || {}
    this._words = verseWords(data.tokens)
    this._paintWords()
    const pick = (tapped && tokenForWord(this._words, tapped)) ||
      this._words.find((w) => w.s && !PARTICLES.has(w.s) && (this._entries[w.s]?.n || 0) < COMMON_ABOVE && w.text.length > 2) ||
      this._words.find((w) => w.s)
    this._select(pick)
    this.cardTarget.focus({ preventScroll: true })
  }

  close(event) {
    event?.preventDefault?.()
    if (!this.hasCardTarget) return
    this.cardTarget.hidden = true
    this._root.classList.remove("is-rootwords")
    this._seq = (this._seq || 0) + 1
  }

  // The verse on the projector: the presented pane's current verse.
  _liveContext() {
    const pane = this._root.querySelector(".ps-pane.is-presented") || this._root.querySelector(".ps-workspace .ps-pane")
    const verse = pane?.querySelector(".ps-verse.is-preach-current") || pane?.querySelector(".ps-verse")
    if (!verse) return null
    const osis = verse.dataset.osis
    const chapter = parseInt(verse.dataset.chapter, 10)
    const num = parseInt(verse.dataset.verseNum, 10)
    if (!osis || !chapter || !num) return null
    const text = ((verse.querySelector(".ps-dropcap")?.textContent || "") +
      Array.from(verse.querySelectorAll(".ps-verse-text")).map((t) => t.textContent).join("")).replace(/\s+/g, " ").trim()
    return { source: "live", osis, chapter, verse: num, text, reference: this._label(osis, chapter, num, pane), translation: this._translationOf(pane) }
  }

  // The verse in Preview (its first verse).
  _previewContext() {
    const label = this._preview?.label
    const p = label && localState().parse?.(label)
    if (!p?.valid || p.verseStart == null) return null
    const pane = this._root.querySelector(".ps-pane.is-presented") || this._root.querySelector(".ps-workspace .ps-pane")
    const first = this._root.querySelector(".ps-preview-text .v")
    const text = first ? Array.from(first.childNodes).filter((n) => n.nodeName !== "SUP").map((n) => n.textContent).join("").trim() : ""
    return {
      source: "preview", osis: p.osis, chapter: p.chapter, verse: p.verseStart, text,
      reference: referenceLabel({ ...p, verseEnd: p.verseStart, chapterEnd: p.chapter, openEnded: false }),
      translation: this._translationOf(pane)
    }
  }

  _label(osis, chapter, num, pane) {
    const raw = pane?.querySelector("input[name='pane[reference]']")?.value || `${osis} ${chapter}`
    const p = localState().parse?.(raw)
    if (p?.valid && p.osis === osis) return referenceLabel({ ...p, chapter, chapterEnd: chapter, verseStart: num, verseEnd: num, openEnded: false })
    return `${raw.replace(/\s*[:.]\s*\d.*$/, "")}:${num}`
  }

  _translationOf(pane) {
    return pane?.querySelector("select[name='pane[translation_id]'] option:checked")?.textContent?.trim() || ""
  }

  // The Preview row's ℵ button shows only for a single previewed verse.
  _previewChanged(detail) {
    this._preview = detail || null
    const p = detail?.label && localState().parse?.(detail.label)
    const single = !!(p?.valid && p.verseStart != null && (p.verseEnd == null || p.verseEnd === p.verseStart))
    this._root.querySelectorAll("[data-root-words-open='preview']").forEach((b) => { b.hidden = !single })
  }

  // ---- the words -------------------------------------------------------------------

  _paintWords() {
    const nodes = this._words.map((w, i) => {
      if (!w.s) return document.createTextNode(w.text)
      const b = el("button", "rw-chip", w.text)
      b.type = "button"
      b.dataset.i = String(i)
      b.dataset.action = "root-words#pick"
      b.title = `${w.s}${this._entries[w.s]?.translit ? ` · ${this._entries[w.s].translit}` : ""}`
      return b
    })
    this.wordsTarget.replaceChildren(...nodes)
  }

  pick(event) {
    event?.preventDefault?.()
    this._select(this._words[Number(event.currentTarget.dataset.i)])
  }

  _select(word) {
    if (!word?.s) return
    this._selected = word
    this.wordsTarget.querySelectorAll(".rw-chip").forEach((b) => {
      const on = this._words[Number(b.dataset.i)] === word
      b.classList.toggle("is-on", on)
      b.setAttribute("aria-pressed", String(on))
    })
    const entry = this._entries[word.s] || { s: word.s }
    const lang = languageLabel(word.s)
    this.detailTarget.hidden = false
    this.detailTarget.classList.toggle("rw-lang-hebrew", lang === "Hebrew")
    this.detailTarget.classList.toggle("rw-lang-greek", lang === "Greek")
    this.englishTarget.textContent = `“${word.text}” · ${lang}`
    this.lemmaTarget.textContent = entry.lemma || word.s
    this.lemmaTarget.lang = lang === "Hebrew" ? "he" : "grc"
    this.lemmaTarget.dir = lang === "Hebrew" ? "rtl" : "ltr"
    this.translitTarget.textContent = readableTranslit(entry.translit, word.s)
    this.sayTarget.textContent = sayIt(entry.translit, word.s, entry.pron)
    this.strongsTarget.textContent = `Strong’s ${word.s}`
    this.glossTarget.value = this._edits[word.s] ?? gloss(entry)
    const kjv = kjvRenderings(entry.kjv)
    this.kjvTarget.textContent = kjv.length ? `KJV renders it: ${kjv.join(", ")}` : ""
    this.countTarget.textContent = occurrencesLabel(entry.n)
    this._resetRabbi(true)
  }

  editGloss() {
    if (this._selected) this._edits[this._selected.s] = this.glossTarget.value
  }

  setLayout(event) {
    event?.preventDefault?.()
    this._layout = event.currentTarget.dataset.layout === "word" ? "word" : "verse"
    this.layoutButtonTargets.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.layout === this._layout)))
  }

  // While the card is open, a tap on the live verse picks that word — any
  // translation, any rendering (server, offline, emphasised).
  _pickFromVerse(event) {
    const verse = event.target.closest?.(".ps-pane.is-presented .ps-verse")
    if (!verse || event.target.closest(".ps-vnum")) return
    const tapped = event.target.closest(".ps-word, .ps-eword")?.textContent || wordAt(event)
    if (!tapped) return
    event.preventDefault()
    event.stopPropagation()
    const hit = tokenForWord(this._words, tapped)
    if (hit) this._select(hit)
    else this._notice(`“${tapped}” has no Strong’s number in the KJV here — pick one of the underlined words`)
  }

  // ---- the study → screen / queue -----------------------------------------------------

  _study({ layout = this._layout } = {}) {
    const word = this._selected
    if (!word?.s || !this._ctx) return null
    const entry = this._entries[word.s] || { s: word.s }
    const ctx = this._ctx
    // The slide shows the projected translation when the word is in it,
    // otherwise the KJV wording the word was picked from.
    let verse = ctx.text
    let translation = ctx.translation
    if (!verse || (!findWord(verse, word.text) && ctx.kjvText)) { verse = ctx.kjvText; translation = "KJV" }
    const note = this.hasRabbiIncludeTarget && this.rabbiIncludeTarget.checked ? this.rabbiTextTarget.value : ""
    const study = buildWordStudy({ entry, english: word.text, reference: ctx.reference, verse, translation, layout, note })
    const edited = this.glossTarget.value.trim()
    if (edited) study.gloss = edited
    return study
  }

  project(event) {
    event?.preventDefault?.()
    const layout = event?.currentTarget?.dataset?.layout || (event?.shiftKey ? "word" : this._layout)
    const study = this._study({ layout })
    if (!study) return
    if (!this._preaching) { this._notice("Enter Preach mode first, then project the word"); return }
    const title = wordStudyTitle(study)
    window.dispatchEvent(new CustomEvent("setlist:present", {
      detail: { kind: "slide", itemKind: "word", title, body: encodeWordStudy(study), word: study, label: title }
    }))
    this.close()
  }

  queue(event) {
    event?.preventDefault?.()
    const study = this._study()
    if (!study) return
    window.dispatchEvent(new CustomEvent("setlist:add", { detail: { kind: "word", title: wordStudyTitle(study), body: encodeWordStudy(study) } }))
  }

  // ---- Ask Rabbi (optional, online, signed in) ------------------------------------------

  async askRabbi(event) {
    event?.preventDefault?.()
    const word = this._selected
    if (!word?.s || !this._ctx) return
    const key = this._noteKey()
    const cached = readNotes()[key]
    if (cached) { this._showRabbi(cached); return }
    if (navigator.onLine === false || isNetworkSlow()) { this._rabbiState("Rabbi needs the internet — the slide works without it."); return }
    this.rabbiButtonTarget.disabled = true
    this._rabbiState("Asking Rabbi…")
    try {
      // A plain fetch: a slow model must not mark the network "slow" for preach mode.
      const abort = new AbortController()
      const timer = setTimeout(() => abort.abort(), EXPLAIN_TIMEOUT_MS)
      const res = await fetch(this.explainUrlValue, {
        method: "POST", credentials: "same-origin", signal: abort.signal,
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf() },
        body: JSON.stringify({ strongs: word.s, osis: this._ctx.osis, chapter: this._ctx.chapter, verse: this._ctx.verse, word: word.text })
      }).finally(() => clearTimeout(timer))
      const body = await res.json().catch(() => null)
      if (key !== this._noteKey()) return
      if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); this._rabbiState("Sign in to ask Rabbi."); return }
      if (!res.ok || !body?.ok || !body.text) {
        this._rabbiState(body?.error === "no_key" ? "Rabbi isn't set up on this server." : (body?.error === "daily_limit" ? "Today's Rabbi allowance is used up." : "Rabbi couldn't answer just now."))
        return
      }
      writeNote(key, body.text)
      this._showRabbi(body.text)
    } catch {
      this._rabbiState("Rabbi couldn't be reached — the slide works without it.")
    } finally {
      this.rabbiButtonTarget.disabled = false
    }
  }

  _noteKey() {
    const c = this._ctx
    return c && this._selected ? `${this._selected.s}|${c.osis}.${c.chapter}.${c.verse}|${this._selected.text.toLowerCase()}` : ""
  }

  _showRabbi(text) {
    this.rabbiBoxTarget.hidden = false
    this.rabbiTextTarget.value = text
    this.rabbiIncludeTarget.checked = true
    this._rabbiState("")
  }

  _rabbiState(text) {
    this.rabbiStatusTarget.textContent = text
    this.rabbiStatusTarget.hidden = !text
  }

  _resetRabbi(keepCached = false) {
    if (!this.hasRabbiBoxTarget) return
    this.rabbiBoxTarget.hidden = true
    this.rabbiTextTarget.value = ""
    this.rabbiIncludeTarget.checked = false
    this._rabbiState("")
    const cached = keepCached && readNotes()[this._noteKey()]
    if (cached) this._showRabbi(cached)
  }

  // ---- offline -----------------------------------------------------------------------------

  async _paintOffline() {
    if (!this.hasStatusTarget) return
    const info = await packInfo()
    this.statusTarget.textContent = info ? "✓ Word data saved on this device" : "Word data needs the internet"
    this.statusTarget.dataset.state = info ? "ready" : "missing"
    if (this.hasOfflineButtonTarget) this.offlineButtonTarget.hidden = !!info || navigator.onLine === false
  }

  async saveOffline(event) {
    event?.preventDefault?.()
    this.offlineButtonTarget.disabled = true
    this.statusTarget.textContent = "Saving the word data (about 3 MB)…"
    try { await downloadWordPack() } catch { /* the status says so */ }
    this.offlineButtonTarget.disabled = false
    this._paintOffline()
  }

  // ---- keys ----------------------------------------------------------------------------------

  _key(e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return
    const typing = isEditable(e.target)
    if (this._isOpen) {
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); this.close(); return }
      if (typing) return
      const inCard = this.cardTarget.contains(e.target) || e.target === document.body
      if (!inCard) return
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") { stop(e); this._step(e.key === "ArrowRight" ? 1 : -1) }
      else if (e.key === "Enter" && !e.target.closest?.(".rw-act")) { stop(e); this.project({ shiftKey: e.shiftKey, preventDefault() {} }) }
      else if (e.key === "+") { stop(e); this.queue() }
      else if (e.key === "r" || e.key === "R") { stop(e); this.askRabbi() }
      else if (e.key === "w" || e.key === "W") { stop(e); this.close() }
      return
    }
    if (typing || !this._preaching) return
    if (e.key === "w" || e.key === "W") { stop(e); this.open(e.shiftKey ? "preview" : "live") }
  }

  _step(delta) {
    const tagged = this._words.filter((w) => w.s)
    const at = tagged.indexOf(this._selected)
    const next = tagged[Math.max(0, Math.min(tagged.length - 1, at + delta))]
    if (next) {
      this._select(next)
      this.wordsTarget.querySelector(".rw-chip.is-on")?.focus({ preventScroll: true })
    }
  }

  _notice(message) {
    window.dispatchEvent(new CustomEvent("preach:notice", { detail: { message } }))
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

function stop(e) { e.preventDefault(); e.stopPropagation() }

function isEditable(t) {
  return !!t && (t.isContentEditable || t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT")
}

function csrf() {
  return document.querySelector("meta[name='csrf-token']")?.content || ""
}

// The word under a click, from the text itself (works on any verse markup).
function wordAt(event) {
  let node = null
  let offset = 0
  if (document.caretPositionFromPoint) {
    const pos = document.caretPositionFromPoint(event.clientX, event.clientY)
    node = pos?.offsetNode; offset = pos?.offset || 0
  } else if (document.caretRangeFromPoint) {
    const range = document.caretRangeFromPoint(event.clientX, event.clientY)
    node = range?.startContainer; offset = range?.startOffset || 0
  }
  if (!node || node.nodeType !== Node.TEXT_NODE) return ""
  const text = node.textContent
  let a = offset
  let b = offset
  const letter = /[\p{L}\p{N}'’-]/u
  while (a > 0 && letter.test(text[a - 1])) a--
  while (b < text.length && letter.test(text[b])) b++
  return text.slice(a, b)
}

function readNotes() {
  try { return JSON.parse(localStorage.getItem(EXPLAIN_CACHE) || "{}") } catch { return {} }
}

function writeNote(key, text) {
  try {
    const all = readNotes()
    all[key] = text
    const keys = Object.keys(all)
    if (keys.length > 200) keys.slice(0, keys.length - 200).forEach((k) => delete all[k])
    localStorage.setItem(EXPLAIN_CACHE, JSON.stringify(all))
  } catch { /* private mode: no cache */ }
}
