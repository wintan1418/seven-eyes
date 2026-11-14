import { Controller } from "@hotwired/stimulus"
import { downloadedBibles, allBookTexts, storedManifest, getMeta } from "../lib/offline/store"
import { isNetworkSlow, markNetworkSlow } from "../lib/offline/network"
import { rankVerses, wordsLabel } from "../lib/scripture_search"

const SERVER_WAIT_MS = 3000 // then a downloaded Bible answers instead
const LIMIT = 250
const RECENT_MAX = 8

// The /search page: recent searches (kept on this device), and Bible search
// that still answers with no internet. Online the form re-renders the
// results frame (ScriptureSearch on the server); offline or on dead data the
// downloaded Bible is searched here with the same ranking
// (lib/scripture_search). A result opens the reader at the whole chapter —
// /read?ref=… online, or the last study saved on the device with ?open=…
// offline (verse-focus marks the verse there).
export default class extends Controller {
  static targets = [ "form", "input", "scope", "translation", "results", "recent", "recentList" ]
  static values = { recentKey: String }

  connect() {
    const q = this.inputTarget.value.trim()
    if (q && this.resultsTarget.querySelector(".sr-list, [data-search-summary]")) this.remember(q)
    this.renderRecent()
  }

  disconnect() {
    clearTimeout(this._fallback)
  }

  typing() {
    this.renderRecent()
  }

  submit(event) {
    const query = this.inputTarget.value.trim()
    clearTimeout(this._fallback)
    if (!query) { event.preventDefault(); this.inputTarget.focus(); return }
    this.remember(query)
    this.inputTarget.blur() // put the phone keyboard away to show the results
    this.recentTarget.hidden = true
    if (navigator.onLine === false || isNetworkSlow()) {
      event.preventDefault()
      this.searchOffline(query)
      return
    }
    const serial = this._serial = (this._serial || 0) + 1
    this.resultsTarget.addEventListener("turbo:frame-load", () => clearTimeout(this._fallback), { once: true })
    this._fallback = setTimeout(async () => {
      if (serial !== this._serial || !(await downloadedBibles()).length) return
      markNetworkSlow()
      this.searchOffline(query)
    }, SERVER_WAIT_MS)
  }

  // A result: online the link (/read?ref=…) does it; offline, open the last
  // study saved on this device at that chapter.
  async open(event) {
    if (navigator.onLine !== false && !isNetworkSlow()) return
    event.preventDefault()
    const link = event.currentTarget
    const last = await getMeta("lastStudyUrl").catch(() => null)
    if (!last) {
      this.notice("Open the Bible once with internet, then results open here offline too.")
      return
    }
    const url = new URL(last, window.location.origin)
    url.searchParams.set("open", link.dataset.openRef)
    if (link.dataset.translationId) url.searchParams.set("tid", link.dataset.translationId)
    window.Turbo ? window.Turbo.visit(url.pathname + url.search) : (window.location.href = url.href)
  }

  async searchOffline(query) {
    const downloaded = await downloadedBibles()
    if (!downloaded.length) {
      this.notice("Search needs internet — or a downloaded Bible (More → Offline Bibles).")
      return
    }
    const code = this.translationTarget.value
    const bible = downloaded.find((b) => b.code === code) || downloaded[0]
    this.notice(`Searching the ${bible.code} on this device…`)
    const [ records, manifest ] = await Promise.all([ allBookTexts(bible.code), storedManifest() ])
    const canon = manifest?.canon || []
    const names = new Map(canon.map((b) => [ b.osis, b.name ]))
    const order = new Map(canon.map((b, i) => [ b.osis, i ]))
    const { words, hits, allCount, anyCount } = rankVerses(records, query, { order, books: this.books(canon), limit: LIMIT })
    const label = wordsLabel(words) || query

    const summary = document.createElement("div")
    summary.className = "sr-summary"
    summary.dataset.searchSummary = ""
    const note = bible.code === code ? "" : " (the Bible on this device)"
    summary.textContent = allCount
      ? `Offline · showing ${allCount} verse${allCount === 1 ? "" : "s"} containing ${label} · ${bible.code}${note}`
      : hits.length
        ? `Offline · no verse has ${label} together · ${anyCount} with some of the words · ${bible.code}${note}`
        : `Offline · no verses containing ${label} in the ${bible.code}${note}`
    const list = document.createElement("ol")
    list.className = "sr-list"
    hits.forEach((hit, i) => {
      if (hit.tier === "partial" && words.length > 1 && (i === 0 || hits[i - 1].tier !== "partial")) {
        const divider = document.createElement("li")
        divider.className = "sr-divider"
        divider.textContent = "With some of the words"
        list.appendChild(divider)
      }
      list.appendChild(this.item(hit, names.get(hit.osis) || hit.osis, bible))
    })
    this.resultsTarget.replaceChildren(summary, list)
  }

  books(canon) {
    const scope = this.scopeTarget.value
    if (!scope || scope === "all") return null
    if (scope === "ot" || scope === "nt") {
      const testament = scope === "ot" ? "old" : "new"
      return new Set(canon.filter((b) => b.testament === testament).map((b) => b.osis))
    }
    return new Set([ scope ])
  }

  item(hit, bookName, bible) {
    const reference = `${bookName} ${hit.chapter}:${hit.num}`
    const li = document.createElement("li")
    li.className = "sr-hit"
    const link = document.createElement("a")
    link.className = "sr-open"
    link.href = `/read?${new URLSearchParams({ ref: reference, t: bible.code })}`
    link.dataset.turboFrame = "_top"
    link.dataset.openRef = reference
    link.dataset.translationId = bible.id
    link.dataset.action = "click->search-page#open"
    const ref = document.createElement("span")
    ref.className = "sr-ref"
    ref.textContent = reference
    const text = document.createElement("span")
    text.className = "sr-text"
    hit.parts.forEach((part) => {
      if (!part.mark) { text.appendChild(document.createTextNode(part.text)); return }
      const mark = document.createElement("mark")
      mark.textContent = part.text
      text.appendChild(mark)
    })
    link.append(ref, text)
    li.appendChild(link)
    return li
  }

  notice(text) {
    const div = document.createElement("div")
    div.className = "sr-summary"
    div.textContent = text
    this.resultsTarget.replaceChildren(div)
  }

  // -- recent searches (this device only) ------------------------------------

  recent() {
    try { return JSON.parse(localStorage.getItem(this.recentKeyValue) || "[]").filter((r) => r && r.q) } catch (_) { return [] }
  }

  remember(q) {
    const entry = { q, in: this.scopeTarget.value, t: this.translationTarget.value }
    const list = [ entry, ...this.recent().filter((r) => r.q.toLowerCase() !== q.toLowerCase()) ].slice(0, RECENT_MAX)
    try { localStorage.setItem(this.recentKeyValue, JSON.stringify(list)) } catch (_) {}
  }

  clearRecent() {
    try { localStorage.removeItem(this.recentKeyValue) } catch (_) {}
    this.renderRecent()
  }

  useRecent(event) {
    const { q, scope, translation } = event.currentTarget.dataset
    this.inputTarget.value = q
    if (scope && [ ...this.scopeTarget.options ].some((o) => o.value === scope)) this.scopeTarget.value = scope
    if (translation && [ ...this.translationTarget.options ].some((o) => o.value === translation)) this.translationTarget.value = translation
    this.formTarget.requestSubmit()
  }

  renderRecent() {
    const list = this.recent()
    const show = list.length > 0 && !this.inputTarget.value.trim()
    this.recentTarget.hidden = !show
    if (!show) return
    this.recentListTarget.replaceChildren(...list.map((r) => {
      const li = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "sr-recent-item"
      button.dataset.action = "search-page#useRecent"
      button.dataset.q = r.q
      button.dataset.scope = r.in || "all"
      button.dataset.translation = r.t || ""
      const q = document.createElement("span")
      q.className = "sr-recent-q"
      q.textContent = r.q
      const meta = document.createElement("span")
      meta.className = "sr-recent-meta"
      meta.textContent = [ r.t, r.in && r.in !== "all" ? this.scopeLabel(r.in) : null ].filter(Boolean).join(" · ")
      button.append(q, meta)
      li.appendChild(button)
      return li
    }))
  }

  scopeLabel(value) {
    return [ ...this.scopeTarget.options ].find((o) => o.value === value)?.textContent || value
  }
}
