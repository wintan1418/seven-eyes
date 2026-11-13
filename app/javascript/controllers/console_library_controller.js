import { Controller } from "@hotwired/stimulus"
import { warmLocal, localCheck } from "../lib/offline/local_pane"

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
    this._listeners = {
      "preach:state": (e) => { this._live = e.detail || null },
      "console:on": () => { this._syncTranslation(); this._paintKinds() },
      "setlist:changed": () => this._paintKinds(),
      "song-bank:picked": (e) => this._songPicked(e.detail?.song)
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
    window.dispatchEvent(new CustomEvent("preview:typing", { detail: { raw, source: "library" } }))
    if (!raw) { this._hint(null); return }
    if (/^\d+$/.test(raw)) { this._hint(`↵ Verse ${raw} of the chapter on screen`, "ok"); return }
    const local = localCheck(raw)
    if (local?.ok) this._hint(`↵ ${local.label || local.chapter_reference} — Enter to preview, Shift+Enter to put it on the screen`, "ok")
    else if (local) this._hint(`↵ Search the Scriptures for “${raw}” — results go to Preview`, "search")
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
    const reference = this._reference(raw)
    if (reference) window.dispatchEvent(new CustomEvent("preview:load", { detail: { kind: "scripture", reference, source: "library" } }))
    else this._viaGoBox(raw, { live: false })
    this._done()
  }

  async live(event) {
    event?.preventDefault?.()
    const raw = this._raw()
    if (!raw) return
    await warmLocal()
    if (/^\d+$/.test(raw) && this._live && !this._live.slide) {
      window.dispatchEvent(new CustomEvent("preach:command", { detail: { action: "verse", value: Number(raw) } }))
    } else {
      const reference = this._reference(raw)
      if (reference) {
        window.dispatchEvent(new CustomEvent("preview:load", { detail: { kind: "scripture", reference, source: "library" } }))
        window.dispatchEvent(new CustomEvent("preview:golive"))
      } else this._viaGoBox(raw, { live: true })
    }
    this._done()
  }

  async queue(event) {
    event?.preventDefault?.()
    const raw = this._raw()
    if (!raw) { this.inputTarget.focus(); return }
    await warmLocal()
    window.dispatchEvent(new CustomEvent("setlist:add", { detail: { kind: "scripture", reference: this._reference(raw) || raw } }))
    this.inputTarget.select()
  }

  // A reference the device can read, as a label ("John 3:16"); a bare number is
  // a verse of the chapter on screen. Null: let the Go box path decide.
  _reference(raw) {
    if (/^\d+(?:\s*[-–]\s*\d+)?$/.test(raw)) {
      const chapter = String(this._live?.reference || "").replace(/\s*[:.]\s*\d.*$/, "")
      return chapter && !this._live?.slide ? `${chapter}:${raw.replace(/\s+/g, "")}` : null
    }
    const local = localCheck(raw)
    return local?.ok ? (local.label || local.chapter_reference) : null
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
