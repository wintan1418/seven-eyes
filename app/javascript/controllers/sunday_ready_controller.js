import { Controller } from "@hotwired/stimulus"
import { fetchManifest, downloadedBibles, downloadBible, requestPersistence, refreshHighlights, bookText, bookCount, setMeta, getMeta } from "../lib/offline/store"
import { makeParser } from "../lib/offline/reference_parser"
import { passageVerses } from "../lib/offline/pane_renderer"
import { precachePages } from "../lib/offline/page"
import { refreshSongs } from "../lib/song_library"

// "Get ready for Sunday" (preach queue drawer, and the Preach section of the
// More sheet via [data-sunday-prepare]): makes this study preachable with no
// Wi-Fi. It downloads every Bible the study's panes use, checks every queued
// scripture and pane passage against those downloads, saves the song bank,
// the study page,
// the projector (?output=1) and stage (?stage=1) screens and their assets, and
// shows a checklist — "Whole KJV Bible saved on this device (66 books) ✓",
// then "✓ 12 of this study's passages checked — ready offline".
export default class extends Controller {
  static targets = ["button", "list", "summary"]
  static values = { studyUrl: String, signedIn: Boolean }

  connect() {
    this._onClick = (e) => {
      if (!e.target.closest?.("[data-sunday-prepare]")) return
      window.dispatchEvent(new CustomEvent("sheet:close"))
      this.prepare()
    }
    document.addEventListener("click", this._onClick)
    this.showLastReady()
  }

  disconnect() {
    document.removeEventListener("click", this._onClick)
  }

  async showLastReady() {
    const at = await getMeta(this.metaKey).catch(() => null)
    if (at && this.hasSummaryTarget) this.summaryTarget.textContent = `Last made ready ${new Date(at).toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit" })}.`
  }

  get metaKey() { return `sundayReady:${this.studyUrlValue}` }

  async prepare(event) {
    event?.preventDefault?.()
    if (this.running) return
    this.listTarget.hidden = false
    this.listTarget.replaceChildren()
    if (!navigator.onLine) {
      this.item("warn", "You're offline — connect to the internet to get ready.")
      return
    }
    this.running = true
    this.buttonTarget.disabled = true
    try {
      await this.run()
    } catch {
      this.item("warn", "Something went wrong — check the connection and try again.")
    } finally {
      this.running = false
      this.buttonTarget.disabled = false
    }
  }

  async run() {
    // 1. Bibles the panes use.
    const bibles = this.item("busy", "Checking Bibles…")
    const manifest = await fetchManifest()
    const ids = [ ...new Set([ ...document.querySelectorAll(".ps-workspace .ps-pane select[name='pane[translation_id]']") ].map((s) => s.value)) ]
    const wanted = ids.map((id) => manifest.translations.find((t) => String(t.id) === String(id))).filter(Boolean)
    if (!wanted.length && manifest.translations.length) wanted.push(manifest.translations.find((t) => t.code === manifest.default_code) || manifest.translations[0])
    let have = await downloadedBibles()
    for (const t of wanted) {
      const current = have.find((d) => d.code === t.code)
      if (current && current.version === t.version) continue
      await downloadBible(t, { onProgress: (f) => this.set(bibles, "busy", `Downloading the whole ${t.code} Bible… ${Math.round(f * 100)}%`) })
    }
    requestPersistence()
    have = await downloadedBibles()
    // Whole translations are saved, not just this study's passages — say so
    // plainly (a tester thought only the passage he was on had downloaded).
    bibles.remove()
    for (const t of wanted) {
      const books = have.find((d) => d.code === t.code)?.books || await bookCount(t.code)
      this.item("ok", `Whole ${t.code} Bible saved on this device (${books} books) ✓`)
    }

    // 2. Every passage the service may call for.
    const passages = this.item("busy", "Checking this study's passages…")
    const parse = makeParser(manifest.canon)
    const refs = this.references()
    const missing = []
    for (const ref of refs) {
      if (!(await this.readable(parse, ref, wanted))) missing.push(ref)
    }
    const ready = refs.length - missing.length
    if (missing.length) this.set(passages, "warn", `${ready} of the ${refs.length} passages in this study ready offline — not found: ${missing.join(", ")}`)
    else this.set(passages, "ok", `${ready} passage${ready === 1 ? "" : "s"} in this study checked — ready offline`)

    // 3. The song bank (hymnal + this account's songs), searchable offline.
    const bank = this.item("busy", "Saving the song bank…")
    const songs = await refreshSongs(`${this.studyUrlValue}/setlist/library`, { timeoutMs: 10_000 })
    if (songs) this.set(bank, "ok", `Song bank saved on this device (${songs.length} songs) ✓`)
    else this.set(bank, "warn", "Couldn't save the song bank — songs already in the queue still work offline")

    // 4. The study, projector and stage screens (and their CSS/JS/fonts).
    const screens = this.item("busy", "Saving the study, projector and stage screens…")
    const url = this.studyUrlValue
    const result = await precachePages([ url, `${url}?output=1`, `${url}?stage=1`, "/read", "/offline" ])
    if (!result) {
      this.set(screens, "warn", "This browser can't keep pages offline — keep this window open, or use Chrome/Edge or the app.")
    } else if (result.failed?.length) {
      this.set(screens, "warn", `Couldn't save ${result.failed.join(", ")} — try again`)
    } else {
      this.set(screens, "ok", "Study, projector and stage screens saved for offline use")
    }
    if (this.signedInValue) refreshHighlights().catch(() => {})

    this.item("warn", "Live follow-along and the phone remote need internet; everything else works offline.")
    if (result && !result.failed?.length && !missing.length) {
      await setMeta(this.metaKey, Date.now()).catch(() => {})
      this.showLastReady()
    }
    return have
  }

  // Queued scriptures plus what each pane shows.
  references() {
    const queued = [ ...this.element.closest(".ps-root")?.querySelectorAll(".ps-setlist-item[data-kind='scripture']") || [] ]
      .flatMap((li) => (li.dataset.reference || "").split(/[,;]+/)).map((r) => r.trim()).filter(Boolean)
    const panes = [ ...document.querySelectorAll(".ps-workspace .ps-pane form.rd-pane-form input[name='pane[reference]']") ]
      .map((i) => i.value.trim()).filter(Boolean)
    return [ ...new Set([ ...queued, ...panes ]) ]
  }

  // Readable offline in at least the first pane's translation.
  async readable(parse, ref, translations) {
    const p = parse(ref)
    if (!p.valid) return false
    for (const t of translations) {
      const record = await bookText(t.code, p.osis)
      if (record && passageVerses(record, { ...p, verseStart: null, verseEnd: null, chapterEnd: p.chapterEnd }).length) return true
    }
    return false
  }

  item(state, text) {
    const li = document.createElement("li")
    this.set(li, state, text)
    this.listTarget.appendChild(li)
    return li
  }

  set(li, state, text) {
    li.className = `is-${state}`
    li.textContent = text
  }
}
