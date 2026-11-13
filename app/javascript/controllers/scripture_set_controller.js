import { Controller } from "@hotwired/stimulus"
import { warmLocal, localState } from "../lib/offline/local_pane"
import { bookText, fetchManifest } from "../lib/offline/store"
import { passageVerses } from "../lib/offline/pane_renderer"
import { quickFetch, isNetworkSlow } from "../lib/offline/network"
import { splitSetInput, setBody, setLabel, setPages, withDefaults, DEFAULTS } from "../lib/slides/scripture_set"
import { paintRichSlide } from "../lib/slides/rich_slides"

// The scripture slide composer: several references on ONE slide, each in its
// own translation — what the tester did in EasyWorship by pasting verses into
// a "song". Type "Col 2:2; Matt 28:19 BSB", Enter, and both are on the slide.
// Lives on its dialog ([data-controller=scripture-set]); opened by the queue's
// "Scripture slide" tool (window queue-tool:open {tool: "scripture-set", item?}).
//
// The words come from the Bible downloaded to this device when it can, else
// GET /verse_passage (one short request per reference). They are kept in the
// queue item itself (data.refs[].verses), so the slide projects with no
// signal, on any device, and the stage / live phones get the same text.
//
// Keys: Enter adds the typed references · Ctrl/⌘+Enter adds the slide to the
// queue · Esc closes.
const PASSAGE_TIMEOUT_MS = 4000

export default class extends Controller {
  static targets = [ "input", "hint", "fallback", "refs", "title", "preview", "pager", "submit", "error" ]

  connect() {
    this.refs = []
    this.options = { ...DEFAULTS }
    this._page = 0
    this._open = (e) => { if (e.detail?.tool === "scripture-set") this.open(e.detail.item) }
    window.addEventListener("queue-tool:open", this._open)
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  // ---- open / close -------------------------------------------------------------------

  async open(item = null) {
    this._editing = item?.cid || null
    const data = withDefaults(item?.data)
    this.refs = data.refs.map((r) => ({ ...r, state: "ready" }))
    this.options = { ref_position: data.ref_position, verse_numbers: data.verse_numbers, split: data.split, ref_style: data.ref_style }
    this.titleTarget.value = item?.title || ""
    this.inputTarget.value = ""
    this._page = 0
    this.submitTarget.textContent = this._editing ? "Save changes" : "Add to queue"
    this.element.hidden = false
    this._error(null)
    this.inputTarget.focus()
    await this._loadTranslations()
    this._paintOptions()
    this._paint()
  }

  close(event) {
    event?.preventDefault?.()
    this.element.hidden = true
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  key(event) {
    event.stopPropagation() // preach keys stay out of the composer
    if (event.key === "Escape") { event.preventDefault(); this.close() }
    else if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); this.submit() }
  }

  // ---- translations -------------------------------------------------------------------

  async _loadTranslations() {
    const local = await warmLocal()
    let list = local.translations || []
    if (!list.length && navigator.onLine !== false && !isNetworkSlow()) {
      try { list = (await fetchManifest()).translations || []; warmLocal({ force: true }) } catch { list = [] }
    }
    const downloaded = new Set((local.downloaded || []).map((d) => d.code))
    this.translations = list.map((t) => ({ code: t.code, name: t.name, here: downloaded.has(t.code) }))
    if (!this.translations.length) this.translations = (local.downloaded || []).map((d) => ({ code: d.code, name: d.name, here: true }))
    const current = this._paneTranslation()
    const select = this.fallbackTarget
    select.replaceChildren(...this.translations.map((t) => option(t.code, `${t.code}${t.here ? " · on this device" : ""}`)))
    const pick = this.translations.find((t) => t.code === this._fallback) || this.translations.find((t) => t.code === current) ||
      this.translations.find((t) => t.here) || this.translations[0]
    if (pick) select.value = pick.code
  }

  // The translation the presented pane shows (its <select> holds ids).
  _paneTranslation() {
    const root = this.element.closest(".ps-root")
    const pane = root?.querySelector(".ps-pane.is-presented") || root?.querySelector(".ps-pane")
    const id = pane?.querySelector("select[name='pane[translation_id]']")?.value
    return (localState().translations || []).find((t) => String(t.id) === String(id))?.code || null
  }

  fallbackChanged() {
    this._fallback = this.fallbackTarget.value
  }

  // ---- typing references ----------------------------------------------------------------

  typed() {
    const raw = this.inputTarget.value
    if (!raw.trim()) { this._hint("Separate references with ; — end one with a Bible's code to use it (Matt 28:19 BSB)", ""); return }
    const { entries, errors } = this._split(raw)
    const parts = []
    if (entries.length) parts.push(`↵ adds ${entries.map((e) => `${e.label} ${e.translation || ""}`.trim()).join(" + ")}`)
    if (errors.length) parts.push(errors.map((e) => e.message).join(" · "))
    this._hint(parts.join(" — "), errors.length ? "error" : "ok")
  }

  inputKey(event) {
    if (event.key === "Enter" && !event.metaKey && !event.ctrlKey) {
      event.preventDefault()
      event.stopPropagation()
      if (this.inputTarget.value.trim()) this.addTyped()
      else if (this.refs.length) this.submit()
    }
  }

  _split(raw) {
    return splitSetInput(raw, { parse: localState().parse, codes: this.translations.map((t) => t.code), fallback: this.fallbackTarget.value || null })
  }

  async addTyped(event) {
    event?.preventDefault?.()
    if (!localState().parse) await warmLocal({ force: true })
    const { entries, errors } = this._split(this.inputTarget.value)
    this.inputTarget.value = errors.map((e) => e.raw).join("; ")
    this._error(errors.length ? errors.map((e) => e.message).join(" · ") : null)
    const warnings = entries.map((e) => e.warning).filter(Boolean)
    if (warnings.length) this._hint(warnings.join(" · "), "warn")
    else this.typed()
    const added = entries.map((e) => ({ reference: e.reference, label: e.label, translation: e.translation, verses: [], state: "loading" }))
    this.refs.push(...added)
    this._paint()
    await Promise.all(added.map((r) => this._fetchWords(r)))
    this._paint()
  }

  // ---- the words: this device first, then the server ---------------------------------------

  async _fetchWords(ref) {
    ref.state = "loading"
    ref.problem = null
    const p = localState().parse?.(ref.reference)
    const here = this.translations.find((t) => t.code === ref.translation)?.here
    if (p?.valid && here) {
      try {
        const record = await bookText(ref.translation, p.osis)
        const verses = record ? passageVerses(record, p) : []
        if (verses.length) { ref.verses = verses.slice(0, 80).map((v) => ({ c: v.chapter, n: v.num, text: v.text })); ref.state = "ready"; return }
      } catch { /* fall through to the server */ }
    }
    if (navigator.onLine !== false && !isNetworkSlow()) {
      try {
        const url = `/verse_passage?q=${encodeURIComponent(ref.reference)}&translation=${encodeURIComponent(ref.translation || "")}`
        const { res, body } = await quickFetch(url, { headers: { Accept: "application/json" } }, { timeoutMs: PASSAGE_TIMEOUT_MS, read: "json" })
        if (res.ok && body?.ok && body.verses?.length) {
          ref.verses = body.verses
          ref.translation = body.translation
          ref.label = body.label || ref.label
          ref.state = "ready"
          return
        }
        if (res.ok && body) { ref.state = "error"; ref.problem = body.error === "unknown_translation" ? "That Bible isn't available" : "No such verse"; return }
      } catch { /* offline */ }
    }
    ref.state = "error"
    ref.problem = `${ref.translation} isn't on this device and there's no connection — pick a Bible marked “on this device”`
  }

  // ---- the reference list --------------------------------------------------------------------

  changeTranslation(event) {
    const ref = this.refs[Number(event.target.closest("[data-i]").dataset.i)]
    if (!ref) return
    ref.translation = event.target.value
    this._fetchWords(ref).then(() => this._paint())
    this._paint()
  }

  removeRef(event) {
    this.refs.splice(Number(event.currentTarget.closest("[data-i]").dataset.i), 1)
    this._paint()
  }

  moveRef(event) {
    const i = Number(event.currentTarget.closest("[data-i]").dataset.i)
    const j = i + Number(event.currentTarget.dataset.delta)
    if (j < 0 || j >= this.refs.length) return
    ;[ this.refs[i], this.refs[j] ] = [ this.refs[j], this.refs[i] ]
    this._paint()
  }

  // ---- layout options -------------------------------------------------------------------------

  setOption(event) {
    const { option: name, value } = event.currentTarget.dataset
    this.options[name] = value === "true" ? true : (value === "false" ? false : value)
    this._page = 0
    this._paintOptions()
    this._paintPreview()
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

  // ---- painting ---------------------------------------------------------------------------------

  _paint() {
    this.refsTarget.replaceChildren(...(this.refs.length ? this.refs.map((r, i) => this._row(r, i)) : [ el("li", "empty", "No scriptures yet — type them above and press Enter.") ]))
    this._paintPreview()
  }

  _row(ref, i) {
    const li = el("li", `ref-row is-${ref.state}`)
    li.dataset.i = String(i)
    const main = el("div", "main")
    main.append(el("span", "lbl", ref.label))
    const sub = ref.state === "error" ? ref.problem : (ref.state === "loading" ? "Loading the words…" : ref.verses.map((v) => v.text).join(" "))
    main.append(el("span", "sub", sub))
    const select = el("select", "tr")
    select.setAttribute("aria-label", `Bible for ${ref.label}`)
    select.dataset.action = "change->scripture-set#changeTranslation"
    this.translations.forEach((t) => select.append(option(t.code, t.code)))
    select.value = ref.translation || ""
    const ops = el("span", "ops")
    ops.append(button("↑", "scripture-set#moveRef", "Move up", { delta: "-1" }), button("↓", "scripture-set#moveRef", "Move down", { delta: "1" }),
      button("✕", "scripture-set#removeRef", "Remove"))
    li.append(main, select, ops)
    return li
  }

  _data() {
    return { refs: this.refs.filter((r) => r.state === "ready").map(({ reference, translation, label, verses }) => ({ reference, translation, label, verses })), ...this.options }
  }

  _paintPreview() {
    const data = this._data()
    const pages = setPages(data)
    this._page = Math.min(this._page, Math.max(0, pages.length - 1))
    const screen = el("div", "set-screen")
    if (pages.length) paintRichSlide(screen, { type: "set", data }, this._page)
    else screen.append(el("div", "set-empty", "The slide shows here as the congregation will see it."))
    this.previewTarget.replaceChildren(screen)
    this._fit(screen)
    this.pagerTarget.querySelector(".n").textContent = pages.length ? `Slide ${this._page + 1} of ${pages.length}${pages.length > 1 ? " — split to fit the screen" : ""}` : ""
    this.pagerTarget.querySelectorAll("button").forEach((b) => { b.disabled = pages.length < 2 })
    this.submitTarget.disabled = !pages.length || this.refs.some((r) => r.state === "loading")
  }

  // Shrink the words until the slide fits its little screen (as the projector does).
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

  // ---- add to the queue ---------------------------------------------------------------------------

  submit(event) {
    event?.preventDefault?.()
    const data = this._data()
    if (!data.refs.length) { this._error("Add at least one scripture"); return }
    const title = this.titleTarget.value.trim()
    const fields = { kind: "scripture_set", title: title || null, body: setBody(data), data, label: title || setLabel(data), stanzas: setPages(data).length, reference: null, arrangement: null }
    if (this._editing) window.dispatchEvent(new CustomEvent("setlist:replace-item", { detail: { cid: this._editing, fields } }))
    else window.dispatchEvent(new CustomEvent("setlist:add-item", { detail: { fields } }))
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

function option(value, label) {
  const o = document.createElement("option")
  o.value = value
  o.textContent = label
  return o
}

function button(label, action, title, data = {}) {
  const b = el("button", "op", label)
  b.type = "button"
  b.dataset.action = action
  b.title = title
  Object.assign(b.dataset, data)
  return b
}
