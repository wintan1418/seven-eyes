import { Controller } from "@hotwired/stimulus"
import { downloadedBibles, allBookTexts, storedManifest } from "../lib/offline/store"
import { isNetworkSlow, markNetworkSlow } from "../lib/offline/network"
import { rankVerses, wordsLabel } from "../lib/scripture_search"
import { openInPane } from "../lib/open_verse"

const ROMAN = [ "I", "II", "III", "IV" ]
const SERVER_WAIT_MS = 3000 // then the downloaded Bible answers instead
const LIMIT = 250

// Opens/closes the full-text "Search the Scriptures" slide-over. The form inside
// posts to the search endpoint and renders into the verse_search_results frame.
// With no internet (or a dead one) and a Bible downloaded, the search runs on
// the device instead (lib/offline/keyword_search) and renders the same result
// cards (same ranking: lib/scripture_search), labelled "Offline search".
// Tapping a result opens its whole chapter at the verse (lib/open_verse),
// through the pane's own form, which the downloaded Bible answers.
export default class extends Controller {
  static targets = ["drawer", "input", "results"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    // A result opened the chapter: show it (the sheet covers a phone).
    this._onOpened = () => { if (this.drawerTarget.classList.contains("is-open")) this.close() }
    window.addEventListener("verse:opened", this._onOpened)
  }

  disconnect() {
    clearTimeout(this._fallback)
    window.removeEventListener("verse:opened", this._onOpened)
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
    const canon = manifest?.canon || []
    const names = new Map(canon.map((b) => [ b.osis, b.name ]))
    const order = new Map(canon.map((b, i) => [ b.osis, i ]))
    const { words, hits, allCount, anyCount } = rankVerses(records, query, { order, limit: LIMIT })
    const label = wordsLabel(words) || truncate(query, 50)

    if (!hits.length) {
      this.render([ hint(`Offline search · no verses containing ${label} in the ${bible.code} on this device. Try fewer or different words.`) ])
      return
    }
    const count = document.createElement("div")
    count.className = "ps-ai-resultcount sr-summary"
    const other = String(bible.id) !== String(translationId) ? " (the Bible on this device)" : ""
    count.textContent = allCount
      ? `Offline search · showing ${allCount} verse${allCount === 1 ? "" : "s"} containing ${label} · ${bible.code}${other}`
      : `Offline search · no verse has ${label} together · ${anyCount} with some of the words · ${bible.code}${other}`
    const list = document.createElement("ol")
    list.className = "sr-list"
    hits.forEach((h, i) => {
      if (h.tier === "partial" && words.length > 1 && (i === 0 || hits[i - 1].tier !== "partial")) {
        const divider = document.createElement("li")
        divider.className = "sr-divider"
        divider.textContent = "With some of the words"
        list.appendChild(divider)
      }
      list.appendChild(this.card(h, names.get(h.osis) || h.osis, bible))
    })
    this.render([ count, list ])
  }

  card(hit, bookName, bible) {
    const ref = `${bookName} ${hit.chapter}:${hit.num}`
    const item = document.createElement("li")
    item.className = "sr-hit"
    item.dataset.offlineResult = ""
    const forms = this.paneForms()
    const open = document.createElement("button")
    open.type = "button"
    open.className = "sr-open"
    const title = document.createElement("span")
    title.className = "sr-ref"
    title.textContent = ref
    const text = document.createElement("span")
    text.className = "sr-text"
    hit.parts.forEach((part) => {
      if (part.mark) {
        const mark = document.createElement("mark")
        mark.textContent = part.text
        text.appendChild(mark)
      } else text.appendChild(document.createTextNode(part.text))
    })
    open.append(title, text)
    open.addEventListener("click", () => this.load(forms[0], ref, bible))
    item.appendChild(open)
    if (forms.length > 1) {
      const actions = document.createElement("div")
      actions.className = "ps-xref-actions"
      forms.forEach((form, i) => {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "ps-xref-load"
        button.textContent = `▸ ${ROMAN[i] || i + 1}`
        button.addEventListener("click", () => this.load(form, ref, bible))
        actions.appendChild(button)
      })
      item.appendChild(actions)
    }
    return item
  }

  // The whole chapter at the verse, through the pane's own form: the service
  // worker (or preach mode's local path) renders it from the downloaded Bible.
  load(form, reference, bible) {
    const frame = form?.closest(".ps-pane")
    if (!frame) return
    const presenting = !!frame.closest(".ps-root")?.matches(".is-presenting, .is-preaching, .is-output")
    if (presenting) {
      const input = form.querySelector("input[name='pane[reference]']")
      const select = form.querySelector("select[name='pane[translation_id]']")
      input.value = reference
      if (select && [ ...select.options ].some((o) => o.value === String(bible.id))) select.value = String(bible.id)
      form.requestSubmit()
    } else {
      openInPane(frame, reference, { translationId: bible.id })
      window.dispatchEvent(new CustomEvent("verse:opened", { detail: { reference, paneId: frame.id } }))
    }
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
