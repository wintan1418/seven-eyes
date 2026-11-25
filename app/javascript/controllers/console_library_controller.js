import { Controller } from "@hotwired/stimulus"
import { warmLocal, localCheck } from "../lib/offline/local_pane"
import { quickFetch } from "../lib/offline/network"
import { queryWords } from "../lib/scripture_search"
import { readMode, tidyReference, MODE_EVENT } from "../lib/scripture_mode"
import { pictureDisplay, pictureLabel, applyPicture, ZOOM_MIN } from "../lib/picture_fit"
import { makeBookResolver, splitBookScope, bookOfReference } from "../lib/book_scope"

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
//   book scope      search the words inside one book, EasyWorship-style:
//                   type the book first ("heb heavenly jerusalem",
//                   "hebrews: heavenly jerusalem") or pick it in the book
//                   picker (Alt+B; "This book" = the book on screen). A chip
//                   in the box shows the book; × (or Esc) searches every book.
//                   Typed without a colon only in Auto / Reference (Words
//                   takes words literally — "mark of the beast").
//   search mode     Auto | Reference | Words (search_mode controller,
//                   lib/scripture_mode): Reference only reads references and
//                   never searches the words; Words only searches the words
//                   and never jumps to a passage. Auto is the guess above.
//   translation     the translation the presented pane shows: a scripture on
//                   screen reloads in it at the same verse (preach:command chase).
//   songs           a song picked in the song bank (Songs tab) goes to Preview.
//   composer        "Several on one slide" opens the scripture-slide composer
//                   (slide tools, queue-tool:open) with what was typed.
//   kind lists      the Presentations tab lists those items of the service;
//                   click previews, double-click goes live (the queue row's
//                   own actions).
//   picture bank    the Pictures tab: every picture of the service as a big
//                   16:9 thumbnail drawn the way the screen shows it. Click
//                   previews, double-click / Go live puts it up. Fit / Fill /
//                   Stretch and zoom for the selected picture go to the queue
//                   (setlist:picture), which saves them and changes the screen.
export default class extends Controller {
  static targets = [ "input", "hint", "translation", "decks", "pictures",
    "pictureControls", "pictureName", "pictureZoom", "pictureZoomOut",
    "book", "liveBook", "chip", "chipLabel" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root || this.root.classList.contains("is-output")) return
    this._live = null
    this._defaultHint = this.hasHintTarget ? this.hintTarget.innerHTML : ""
    this._mode = readMode()
    this._resolveBook = makeBookResolver(this._canon())
    this._listeners = {
      "preach:state": (e) => { this._live = e.detail || null; this._paintLiveBook() },
      "console:on": () => { this._syncTranslation(); this._paintKinds() },
      "setlist:changed": () => this._paintKinds(),
      "preview:changed": (e) => { this._previewCid = e.detail?.cid || null; this._paintKinds() },
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
    const scope = this._scope(raw)
    this._paintChip(scope)
    if (scope) {
      // Words inside one book: the matching verses list below as you type.
      window.dispatchEvent(new CustomEvent("preview:typing", { detail: {
        raw: scope.words, query: raw, source: "library", mode: "words",
        book: { osis: scope.book.osis, name: scope.book.name, strict: scope.explicit }
      } }))
      if (scope.words) this._hint(`Searching ${scope.book.name} for “${scope.words}” — ↓ walks the verses, Enter previews the first, Shift+Enter puts it on the screen · Esc searches every book`, "search")
      else this._hint(`Searching ${scope.book.name} — type a word or two from the verse`, "wait")
      return
    }
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
    if (event.altKey && event.code === "KeyB" && !event.ctrlKey && !event.metaKey && this.hasBookTarget) {
      event.preventDefault()
      event.stopPropagation()
      this.bookTarget.focus()
      return
    }
    if (event.key === "Escape" && this._scope(this._raw())) {
      // First Esc drops the book (the words stay); the next clears the box.
      event.preventDefault()
      event.stopPropagation()
      this.clearBook()
      return
    }
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
    if (await this._scoped(raw, { live: false })) return
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
    if (await this._scoped(raw, { live: true })) return
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

  // A book-scoped search ("heb heavenly jerusalem"): Enter previews the first
  // verse holding every word, Shift+Enter puts it up. False: not scoped.
  async _scoped(raw, { live }) {
    const scope = this._scope(raw)
    if (!scope) return false
    if (!scope.words) { this._hint(`Searching ${scope.book.name} — type a word or two from the verse`, "wait"); return true }
    const found = await this._wordsMatch(raw)
    if (!found) { this._hint(`No verses with “${scope.words}” in ${scope.book.name} · Esc searches every book`, "error"); return true }
    if (live) found.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
    else found.click()
    this._done()
    return true
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
    const scoped = !!this._scope(raw)
    let reference = this._mode === "words" || scoped ? null : this._reference(raw)
    if (this._mode === "words" || scoped) {
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

  // ---- one book (EasyWorship's "search in Hebrews") --------------------------------------

  // The canon the book picker was rendered with (Bible::Canon): names + aliases.
  _canon() {
    if (!this.hasBookTarget) return []
    return Array.from(this.bookTarget.querySelectorAll("option[data-aliases]")).map((o) => ({
      osis: o.value, name: o.textContent.trim(), aliases: (o.dataset.aliases || "").split(/\s+/).filter(Boolean)
    }))
  }

  // What the box searches in: a book typed first, else the picker's book.
  // → { book: {osis, name}, words, explicit } or null (every book / a reference).
  _scope(raw) {
    const text = String(raw || "").trim()
    if (this._mode !== "words" || /:\s*\S/.test(text)) {
      // A reference ("heb 12", "john 3:16") is never a search.
      const ref = this._mode === "words" ? null : localCheck(this._refText(text))
      if (!ref?.ok) {
        const typed = splitBookScope(text, this._resolveBook)
        if (typed && (this._mode !== "words" || typed.explicit)) return typed
      }
    }
    const picked = this._pickedBook()
    if (!picked) return null
    if (this._mode !== "words" && localCheck(this._refText(text))?.ok) return null
    if (this._mode !== "words" && /^\d+(?:\s*[-–]\s*\d+)?$/.test(text)) return null // a verse of the chapter on screen
    return { book: picked, words: text, explicit: true, picked: true }
  }

  _pickedBook() {
    if (!this.hasBookTarget || !this.bookTarget.value) return null
    if (this.bookTarget.value === "live") return this._liveBook()
    const option = this.bookTarget.selectedOptions[0]
    return option ? { osis: option.value, name: option.textContent.trim() } : null
  }

  _liveBook() {
    if (!this._live || this._live.slide) return null
    return bookOfReference(this._live.reference, this._resolveBook)
  }

  _paintLiveBook() {
    if (!this.hasLiveBookTarget) return
    const book = this._liveBook()
    this.liveBookTarget.hidden = !book
    this.liveBookTarget.textContent = book ? `This book — ${book.name}` : "This book"
    if (this.bookTarget.value === "live" && this._raw()) this._paintChip(this._scope(this._raw()))
  }

  _paintChip(scope) {
    if (!this.hasChipTarget) return
    this.chipTarget.hidden = !scope
    this.element.querySelector(".cx-find")?.classList.toggle("is-scoped", !!scope)
    if (scope) this.chipLabelTarget.textContent = scope.book.name
  }

  bookChanged() {
    this._paintChip(this._scope(this._raw()))
    if (this._raw()) this.typed()
    else if (this._pickedBook()) this._hint(`Searching ${this._pickedBook().name} — type a word or two from the verse`, "wait")
    else this._hint(null)
  }

  // In the book picker: Enter / Esc go back to typing.
  bookKey(event) {
    if (event.key === "Enter" || event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.inputTarget.focus()
    }
  }

  // × on the chip (or Esc in the box): search every book — the words stay.
  clearBook(event) {
    event?.preventDefault?.()
    const scope = this._scope(this._raw())
    if (this.hasBookTarget) this.bookTarget.value = ""
    if (scope && !scope.picked) this.inputTarget.value = scope.words
    this._paintChip(null)
    this.inputTarget.focus()
    this.typed()
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

  // NKJV / NIV / AMP… pasted from the pastor's own Bible app (paste_verses controller).
  pasteOwn(event) {
    event?.preventDefault?.()
    window.dispatchEvent(new CustomEvent("queue-tool:open", { detail: { tool: "paste-verses" } }))
  }

  // ---- what of a kind is in the service (Presentations, Pictures tabs) -------------------

  _paintKinds() {
    if (!this.root.classList.contains("is-console")) return
    this._paintPictures()
    ;[ this.hasDecksTarget && this.decksTarget ].filter(Boolean).forEach((list) => {
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

  // ---- the Picture Bank (Pictures tab) ----------------------------------------------------

  _pictureItems() {
    let items = []
    window.dispatchEvent(new CustomEvent("setlist:request-items", { detail: { reply: (list) => { items = list } } }))
    return items.filter((i) => i.kind === "picture" && i.image)
  }

  // Rebuilt only when the pictures themselves change (the queue repaints
  // every second while something syncs); live / preview marks just toggle.
  _paintPictures() {
    if (!this.hasPicturesTarget) return
    const list = this.picturesTarget
    const pictures = this._pictureItems()
    this._pictures = pictures
    if (!pictures.some((p) => p.cid === this._pictureCid)) {
      const previewed = pictures.find((p) => p.cid === this._previewCid)
      this._pictureCid = (previewed || pictures[0])?.cid || null
    }
    const signature = JSON.stringify(pictures.map((p) => [ p.cid, p.image, p.label || p.title, pictureDisplay(p.data) ]))
    if (signature !== this._pictureSignature) {
      this._pictureSignature = signature
      if (!pictures.length) list.replaceChildren(el("li", "cx-empty", list.dataset.empty || ""))
      else list.replaceChildren(...pictures.map((p) => this._pictureCard(p)))
    }
    const rows = this.root.querySelectorAll(".ps-setlist-items .ps-setlist-item")
    const marks = {}
    rows.forEach((li) => { marks[li.dataset.cid] = { live: li.classList.contains("is-live"), preview: li.classList.contains("is-preview") } })
    list.querySelectorAll(".cx-pcard").forEach((card) => {
      const m = marks[card.dataset.cid] || {}
      card.classList.toggle("is-live", !!m.live)
      card.classList.toggle("is-preview", !!m.preview || card.dataset.cid === this._previewCid)
      card.classList.toggle("is-selected", card.dataset.cid === this._pictureCid)
    })
    this._paintPictureControls()
  }

  _pictureCard(item) {
    const card = el("li", "cx-pcard")
    card.dataset.cid = item.cid
    const btn = el("button", "pick")
    btn.type = "button"
    btn.dataset.cid = item.cid
    btn.dataset.action = "click->console-library#pickPicture dblclick->console-library#livePicture"
    btn.title = "Click to preview · double-click to go live"
    const frame = el("span", "frame slide-img")
    applyPicture(frame, item.data)
    const img = el("img")
    img.src = item.image
    img.alt = ""
    img.loading = "lazy"
    img.decoding = "async"
    frame.append(img)
    const cap = el("span", "cap")
    cap.append(el("span", "lbl", item.label || item.title || "Picture"), el("span", "tag live", "LIVE"),
      el("span", "tag preview", "PREVIEW"), el("span", "meta", pictureLabel(item.data)))
    btn.append(frame, cap)
    card.append(btn)
    return card
  }

  _paintPictureControls() {
    if (!this.hasPictureControlsTarget) return
    const item = this._pictures?.find((p) => p.cid === this._pictureCid)
    this.pictureControlsTarget.hidden = !item
    if (!item) return
    const { fit, zoom } = pictureDisplay(item.data)
    this.pictureNameTarget.textContent = item.label || item.title || "Picture"
    this.pictureControlsTarget.querySelectorAll("[data-fit]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.fit === fit)))
    if (document.activeElement !== this.pictureZoomTarget) this.pictureZoomTarget.value = String(zoom)
    this.pictureZoomOutTarget.textContent = `${zoom}%`
  }

  pickPicture(event) {
    event.preventDefault()
    this._pictureCid = event.currentTarget.dataset.cid
    this._paintPictures()
    this._queueRow(event)?.querySelector(".present")?.click()
  }

  livePicture(event) {
    event.preventDefault()
    this._pictureCid = event.currentTarget.dataset.cid
    this._queueRow(event)?.querySelector(".present")?.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
  }

  pictureFit(event) {
    event.preventDefault()
    this._changePicture({ fit: event.currentTarget.dataset.fit })
  }

  pictureZoom() {
    const zoom = Number(this.pictureZoomTarget.value) || ZOOM_MIN
    this.pictureZoomOutTarget.textContent = `${zoom}%`
    this._changePicture({ zoom })
  }

  picturePreview(event) {
    event.preventDefault()
    this._selectedRow()?.querySelector(".present")?.click()
  }

  pictureLive(event) {
    event.preventDefault()
    this._selectedRow()?.querySelector(".present")?.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
  }

  _changePicture(change) {
    if (!this._pictureCid) return
    window.dispatchEvent(new CustomEvent("setlist:picture", { detail: { cid: this._pictureCid, ...change } }))
    this._paintPictures()
  }

  _selectedRow() {
    const cid = this._pictureCid
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
