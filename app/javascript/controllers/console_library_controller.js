import { Controller } from "@hotwired/stimulus"
import { warmLocal, localCheck } from "../lib/offline/local_pane"
import { quickFetch } from "../lib/offline/network"
import { queryWords } from "../lib/scripture_search"
import { readMode, tidyReference, MODE_EVENT } from "../lib/scripture_mode"

const WORDS_WAIT_MS = 2500 // Enter in Words mode waits this long for the list

// The console library's Scriptures tab (and Songs → Preview). Lives on the
// library region of _console, operator window only.
//
//   reference box   typing lists the chapter in the verse list below (preview
//                   controller, preview:typing). Enter → Preview, Shift+Enter →
//                   straight to the screen, Ctrl/⌘+Enter → the service list.
//                   A bare number is a verse of the chapter on screen; words
//                   that aren't a reference search the Scriptures through the
//                   Go box's own path (AI, or on-device keywords offline) —
//                   results land in Preview, never on the projector.
//   search mode     Auto | Reference | Words (search_mode controller,
//                   lib/scripture_mode): Reference only reads references and
//                   never searches the words; Words only searches the words
//                   and never jumps to a passage. Auto is the guess above.
//   translation     the translation the presented pane shows: a scripture on
//                   screen reloads in it at the same verse (preach:command chase).
//   songs           a song picked in the song bank (Songs tab) goes to Preview.
//   composer        "Several on one slide" opens the scripture-slide composer
//                   (slide tools, queue-tool:open) with what was typed.
//   kind lists      Presentations / Pictures tabs list those items of the
//                   service; click previews, double-click goes live (the queue
//                   row's own actions).
export default class extends Controller {
  static targets = [ "input", "hint", "translation", "decks", "pictures" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root || this.root.classList.contains("is-output")) return
    this._live = null
    this._defaultHint = this.hasHintTarget ? this.hintTarget.innerHTML : ""
    this._mode = readMode()
    this._listeners = {
      "preach:state": (e) => { this._live = e.detail || null },
      "console:on": () => { this._syncTranslation(); this._paintKinds() },
      "setlist:changed": () => this._paintKinds(),
      "song-bank:picked": (e) => this._songPicked(e.detail?.song),
      [MODE_EVENT]: (e) => { this._mode = e.detail?.mode || "auto"; if (this._raw()) this.typed() }
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
  }

  disconnect() {
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
  }

  // ---- the reference box --------------------------------------------------------------

  async typed() {
    await warmLocal() // the parser, before the first keystroke is read
    const raw = this._raw()
    const mode = this._mode
    const text = mode === "words" ? raw : this._refText(raw)
    window.dispatchEvent(new CustomEvent("preview:typing", { detail: { raw: text, source: "library", mode } }))
    if (!raw) { this._hint(null); return }
    if (mode === "words") {
      if (queryWords(raw).length) this._hint("Words — matching verses list below as you type · click to preview, double-click to go live · Enter previews the first", "search")
      else this._hint("Words — type a word or two from the verse (Alt+R to search by reference)", "wait")
      return
    }
    if (/^\d+$/.test(raw)) { this._hint(`↵ Verse ${raw} of the chapter on screen`, "ok"); return }
    const local = localCheck(text)
    if (local?.ok) this._hint(`↵ ${local.label || local.chapter_reference} — Enter to preview, Shift+Enter to put it on the screen`, "ok")
    else if (local && mode === "reference") this._hint("Not a reference yet — try John 3:16, jn 3 16, 1cor13:4-7 · Alt+W searches the words", "error")
    else if (local) this._hint(`Matching verses list below as you type — click to preview, double-click to go live · ↓ to walk them · Enter previews the first`, "search")
    else this._hint("↵ Enter to look it up", "wait")
  }

  key(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      event.stopPropagation()
      if (event.metaKey || event.ctrlKey) this.queue()
      else if (event.shiftKey) this.live()
      else this.preview()
    } else if (event.key === "ArrowDown") {
      const first = this.root.querySelector(".ps-verse-list .vrow.is-preview .pick, .ps-verse-list .vrow.is-target .pick, .ps-verse-list .vrow .pick")
      if (first) { event.preventDefault(); first.focus() }
    } else if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      if (this.inputTarget.value) { this.inputTarget.value = ""; this.typed() } else this.inputTarget.blur()
    }
  }

  async preview(event) {
    event?.preventDefault?.()
    const raw = this._raw()
    if (!raw) { this.inputTarget.focus(); return }
    await warmLocal()
    if (this._mode !== "auto") { await this._explicit(raw, { live: false }); return }
    const reference = this._reference(raw)
    const found = reference ? null : this._topMatch(raw)
    if (reference) window.dispatchEvent(new CustomEvent("preview:load", { detail: { kind: "scripture", reference, source: "library" } }))
    else if (found) found.click()
    else this._viaGoBox(raw, { live: false })
    this._done()
  }

  async live(event) {
    event?.preventDefault?.()
    const raw = this._raw()
    if (!raw) return
    await warmLocal()
    if (/^\d+$/.test(raw) && this._mode !== "words" && this._live && !this._live.slide) {
      window.dispatchEvent(new CustomEvent("preach:command", { detail: { action: "verse", value: Number(raw) } }))
    } else if (this._mode !== "auto") {
      await this._explicit(raw, { live: true })
      return
    } else {
      const reference = this._reference(raw)
      const found = reference ? null : this._topMatch(raw)
      if (reference) {
        window.dispatchEvent(new CustomEvent("preview:load", { detail: { kind: "scripture", reference, source: "library" } }))
        window.dispatchEvent(new CustomEvent("preview:golive"))
      } else if (found) found.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
      else this._viaGoBox(raw, { live: true })
    }
    this._done()
  }

  // Reference or Words mode: only that kind of search, never the other and
  // never the study assistant. A miss says so and keeps the text to fix.
  async _explicit(raw, { live }) {
    if (this._mode === "reference") {
      const reference = this._reference(raw) || (localCheck(raw) ? null : await this._serverReference(raw))
      if (!reference) { this._hint(`“${raw}” isn't a reference — try John 3:16, jn 3 16, 1cor13:4-7 · Alt+W searches the words`, "error"); return }
      window.dispatchEvent(new CustomEvent("preview:load", { detail: { kind: "scripture", reference, source: "library" } }))
      if (live) window.dispatchEvent(new CustomEvent("preview:golive"))
    } else {
      if (!queryWords(raw).length) { this._hint("Words — type a word or two from the verse", "wait"); return }
      const found = await this._wordsMatch(raw)
      if (!found) { this._hint(`No verses with “${raw}” in this translation · Alt+A lets the study assistant try`, "error"); return }
      if (live) found.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
      else found.click()
    }
    this._done()
  }

  // Words mode: the first verse of the list for exactly this text, waiting
  // for the search as you type to land (it runs a moment after the last key).
  async _wordsMatch(raw) {
    const until = performance.now() + WORDS_WAIT_MS
    for (;;) {
      const list = this.root.querySelector(".ps-verse-list[data-mode='search']")
      if (list && list.dataset.query === raw) return list.querySelector(".vrow.is-strong .pick")
      if (performance.now() > until) return null
      await new Promise((r) => setTimeout(r, 40))
    }
  }

  // The parser isn't on the device yet: the server reads the reference.
  async _serverReference(raw) {
    try {
      const { res, body } = await quickFetch(`/reference_check?q=${encodeURIComponent(tidyReference(raw))}`,
        { headers: { Accept: "application/json" } }, { timeoutMs: 2000, read: "json" })
      if (!res.ok || !body?.ok) return null
      return body.label || (body.verse_start ? `${body.chapter_reference}:${body.verse_start}` : body.chapter_reference)
    } catch { return null }
  }

  // What the parser should read: as typed, or tidied ("john 1O:30" → "john
  // 10:30") when only the tidied text is a reference.
  _refText(raw) {
    if (!raw) return raw
    const tidy = tidyReference(raw)
    if (tidy === raw || localCheck(raw)?.ok) return raw
    return localCheck(tidy)?.ok ? tidy : raw
  }

  async queue(event) {
    event?.preventDefault?.()
    const raw = this._raw()
    if (!raw) { this.inputTarget.focus(); return }
    await warmLocal()
    let reference = this._mode === "words" ? null : this._reference(raw)
    if (this._mode === "words") {
      reference = (await this._wordsMatch(raw))?.closest(".vrow")?.dataset.label
      if (!reference) { this._hint(`No verses with “${raw}” to add`, "error"); return }
    }
    window.dispatchEvent(new CustomEvent("setlist:add", { detail: { kind: "scripture", reference: reference || raw } }))
    this.inputTarget.select()
  }

  // A reference the device can read, as a label ("John 3:16"); a bare number is
  // a verse of the chapter on screen. Null: let the Go box path decide.
  _reference(raw) {
    if (/^\d+(?:\s*[-–]\s*\d+)?$/.test(raw)) {
      const chapter = String(this._live?.reference || "").replace(/\s*[:.]\s*\d.*$/, "")
      return chapter && !this._live?.slide ? `${chapter}:${raw.replace(/\s+/g, "")}` : null
    }
    const local = localCheck(this._refText(raw))
    return local?.ok ? (local.label || local.chapter_reference) : null
  }

  // The first verse in the as-you-type list holding every word typed (the
  // list must be for this text). None: the Go box path (the study assistant).
  _topMatch(raw) {
    const list = this.root.querySelector(".ps-verse-list[data-mode='search']")
    if (!list || list.dataset.query !== raw) return null
    return list.querySelector(".vrow.is-strong .pick")
  }

  // What the device can't read goes through the Go box (presentation
  // controller): the server's reference check, then the Scripture search.
  _viaGoBox(raw, { live }) {
    const box = this.root.querySelector(".ps-preach-jump")
    const input = box?.querySelector("input")
    if (!input) return
    input.value = raw
    const button = live
      ? box.querySelector("button[data-action~='presentation#jumpSubmit']")
      : box.querySelector("button[data-action~='presentation#jumpPreviewSubmit']")
    button?.click()
  }

  // Done typing: the keyboard goes back to the screen (arrows, L, Space…);
  // G or / comes back here with the text selected.
  _done() {
    this.inputTarget.select()
    this.inputTarget.blur()
    this._hint("Done — G or / types the next one. L puts Preview on the screen.", "ok")
  }

  _raw() {
    return this.hasInputTarget ? this.inputTarget.value.trim() : ""
  }

  _hint(text, tone = "") {
    if (!this.hasHintTarget) return
    if (text == null) { this.hintTarget.innerHTML = this._defaultHint; this.hintTarget.dataset.tone = ""; return }
    this.hintTarget.textContent = text
    this.hintTarget.dataset.tone = tone
  }

  // ---- translation --------------------------------------------------------------------

  translation() {
    const id = this.translationTarget.value
    const select = this._paneSelect()
    if (!select || select.value === id) return
    select.value = id
    // A scripture on screen comes back in the new translation, same verse.
    const live = this._live
    if (live && !live.slide && live.reference) {
      const chapter = String(live.reference).replace(/\s*[:.]\s*\d.*$/, "")
      const value = live.verseStart ? `${chapter}:${live.verseStart}` : chapter
      window.dispatchEvent(new CustomEvent("preach:command", { detail: { action: "chase", value } }))
    }
    // The verse list follows.
    if (this._raw()) this.typed()
  }

  _syncTranslation() {
    const select = this._paneSelect()
    if (select && this.hasTranslationTarget) this.translationTarget.value = select.value
  }

  _paneSelect() {
    const pane = this.root.querySelector(".ps-pane.is-presented") || this.root.querySelector(".ps-workspace .ps-pane")
    return pane?.querySelector("select[name='pane[translation_id]']") || null
  }

  // ---- several scriptures on one slide ------------------------------------------------

  composer(event) {
    event?.preventDefault?.()
    const raw = this._raw()
    window.dispatchEvent(new CustomEvent("queue-tool:open", { detail: { tool: "scripture-set" } }))
    if (!raw) return
    requestAnimationFrame(() => {
      const input = this.root.querySelector("[data-scripture-set-target='input']")
      if (!input) return
      input.value = raw
      input.dispatchEvent(new Event("input", { bubbles: true }))
      input.focus()
    })
  }

  // ---- what of a kind is in the service (Presentations, Pictures tabs) -------------------

  _paintKinds() {
    if (!this.root.classList.contains("is-console")) return
    ;[ this.hasDecksTarget && this.decksTarget, this.hasPicturesTarget && this.picturesTarget ].filter(Boolean).forEach((list) => {
      const kinds = (list.dataset.kinds || "").split(/\s+/)
      const rows = Array.from(this.root.querySelectorAll(".ps-setlist-items .ps-setlist-item"))
        .filter((li) => kinds.some((k) => li.classList.contains(`kind-${k}`)))
      if (!rows.length) { list.replaceChildren(el("li", "cx-empty", list.dataset.empty || "")); return }
      list.replaceChildren(...rows.map((li) => {
        const item = el("li", "cx-kind-row")
        item.classList.toggle("is-live", li.classList.contains("is-live"))
        item.classList.toggle("is-preview", li.classList.contains("is-preview"))
        const btn = el("button", "pick")
        btn.type = "button"
        btn.dataset.cid = li.dataset.cid
        btn.dataset.action = "click->console-library#pickKind dblclick->console-library#liveKind"
        btn.title = "Click to preview · double-click to go live"
        const thumb = li.querySelector(".present .thumb, .present .icon")
        if (thumb) btn.append(thumb.cloneNode(true))
        btn.append(el("span", "lbl", li.querySelector(".present .lbl")?.textContent || ""))
        const meta = li.querySelector(".present .meta")?.textContent
        if (meta) btn.append(el("span", "meta", meta))
        item.append(btn)
        return item
      }))
    })
  }

  pickKind(event) {
    event.preventDefault()
    this._queueRow(event)?.querySelector(".present")?.click()
  }

  liveKind(event) {
    event.preventDefault()
    this._queueRow(event)?.querySelector(".present")?.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
  }

  _queueRow(event) {
    const cid = event.currentTarget.dataset.cid
    return cid ? this.root.querySelector(`.ps-setlist-items .ps-setlist-item[data-cid="${CSS.escape(cid)}"]`) : null
  }

  // ---- songs ----------------------------------------------------------------------------

  _songPicked(song) {
    if (!song || !this.root.classList.contains("is-console")) return
    window.dispatchEvent(new CustomEvent("preview:load", {
      detail: { kind: "slide", itemKind: "song", label: song.title, title: song.title, body: song.body, arrangement: song.arrangement || "" }
    }))
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
