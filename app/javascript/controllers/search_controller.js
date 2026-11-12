import { Controller } from "@hotwired/stimulus"
import { downloadedBibles, allBookTexts, storedManifest } from "../lib/offline/store"
import { searchVerses } from "../lib/offline/keyword_search"
import { isNetworkSlow, markNetworkSlow } from "../lib/offline/network"

const ROMAN = [ "I", "II", "III", "IV" ]
const SERVER_WAIT_MS = 3000 // then the downloaded Bible answers instead
const LIMIT = 50

// Opens/closes the full-text "Search the Scriptures" slide-over. The form inside
// posts to the search endpoint and renders into the verse_search_results frame.
// With no internet (or a dead one) and a Bible downloaded, the search runs on
// the device instead (lib/offline/keyword_search) and renders the same result
// cards, labelled "Offline search"; loading a result goes through the pane's
// own form, which the downloaded Bible answers.
export default class extends Controller {
  static targets = ["drawer", "input", "results"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
  }

  disconnect() {
    clearTimeout(this._fallback)
  }

  open() {
    this.drawerTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
    if (this.hasInputTarget) setTimeout(() => this.inputTarget.focus(), 50)
  }

  close() {
    this.drawerTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }

  submit(event) {
    const form = event.target
    const query = this.inputTarget.value.trim()
    const translationId = form.querySelector("select[name='translation_id']")?.value
    clearTimeout(this._fallback)
    if (!query) return
    if (navigator.onLine === false || isNetworkSlow()) {
      event.preventDefault()
      this.searchOffline(query, translationId)
      return
    }
    // A request that hangs ("data on but dead"): answer from the device.
    const started = this._serial = (this._serial || 0) + 1
    this.resultsTarget.addEventListener("turbo:frame-load", () => clearTimeout(this._fallback), { once: true })
    this._fallback = setTimeout(async () => {
      if (started !== this._serial || !(await downloadedBibles()).length) return
      markNetworkSlow()
      this.searchOffline(query, translationId)
    }, SERVER_WAIT_MS)
  }

  async searchOffline(query, translationId) {
    const downloaded = await downloadedBibles()
    if (!downloaded.length) {
      this.render([ hint("Bible search needs internet — or a downloaded Bible (Offline Bibles).") ])
      return
    }
    const bible = downloaded.find((b) => String(b.id) === String(translationId)) || downloaded[0]
    this.render([ hint(`Offline search · searching the ${bible.code} on this device…`) ])
    const [ records, manifest ] = await Promise.all([ allBookTexts(bible.code), storedManifest() ])
    const names = new Map((manifest?.canon || []).map((b) => [ b.osis, b.name ]))
    const hits = searchVerses(records, query, { limit: LIMIT }) // ranked: every word first, rarer words weigh more

    if (!hits.length) {
      this.render([ hint(`Offline search · no matches for “${truncate(query, 60)}” in the ${bible.code} on this device. Try fewer or different words.`) ])
      return
    }
    const count = document.createElement("div")
    count.className = "ps-ai-resultcount"
    const other = String(bible.id) !== String(translationId) ? ` (the Bible on this device)` : ""
    count.textContent = `Offline search · ${hits.length}${hits.length === LIMIT ? "+" : ""} verse${hits.length === 1 ? "" : "s"} in ${bible.code}${other} · “${truncate(query, 50)}”`
    this.render([ count, ...hits.map((h) => this.card(h, names.get(h.osis) || h.osis, bible)) ])
  }

  card(hit, bookName, bible) {
    const ref = `${bookName} ${hit.chapter}:${hit.num}`
    const card = document.createElement("div")
    card.className = "ps-xref"
    card.dataset.offlineResult = ""
    const head = document.createElement("div")
    head.className = "ps-xref-head"
    const title = document.createElement("div")
    title.className = "ps-xref-ref"
    title.textContent = ref
    head.appendChild(title)
    const text = document.createElement("div")
    text.className = "ps-xref-text"
    text.textContent = truncate(hit.text, 180)
    const actions = document.createElement("div")
    actions.className = "ps-xref-actions"
    this.paneForms().forEach((form, i) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "ps-xref-load"
      button.textContent = `▸ ${ROMAN[i] || i + 1}`
      button.addEventListener("click", () => this.load(form, ref, bible))
      actions.appendChild(button)
    })
    card.append(head, text, actions)
    return card
  }

  // Through the pane's own form: the service worker (or preach mode's local
  // path) renders it from the downloaded Bible and queues the visit to sync.
  load(form, reference, bible) {
    const input = form.querySelector("input[name='pane[reference]']")
    const select = form.querySelector("select[name='pane[translation_id]']")
    if (!input) return
    input.value = reference
    if (select && [ ...select.options ].some((o) => o.value === String(bible.id))) select.value = String(bible.id)
    form.requestSubmit()
  }

  paneForms() {
    return [ ...document.querySelectorAll(".ps-workspace .ps-pane form.rd-pane-form") ]
  }

  render(nodes) {
    this.resultsTarget.replaceChildren(...nodes)
  }
}

function hint(text) {
  const el = document.createElement("div")
  el.className = "ps-ai-hint"
  el.textContent = text
  return el
}

function truncate(text, length) {
  const s = String(text || "")
  return s.length > length ? `${s.slice(0, length - 1)}…` : s
}
