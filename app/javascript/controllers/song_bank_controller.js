import { Controller } from "@hotwired/stimulus"
import { cachedSongs, refreshSongs, searchSongs, cachedCollections, storeCollections } from "../lib/song_library"
import { songSlides, flowCodes } from "../lib/song_sheet"
import { queueSongRemove, flushOutbox, queueRecordSave, queueRecordRemove, pendingOps, newTempId } from "../lib/offline/outbox"
import { inCollection, toggleTitle, applyCollectionOps } from "../lib/song_collections"
import { owner } from "../lib/offline/page"

// The song bank: find a song or hymn and put it in the queue — EasyWorship's
// Songs tab. Lives on .ps-root (the dialog is [data-song-bank-target=dialog]).
//
// Search runs on the device over the cached library (titles and words), so it
// works with no signal once the bank has been opened online (or "Get ready for
// Sunday" ran). Sources: All · My songs (saved + queued before) · Hymnal, with
// counts. Each row shows title, author and copyright; the right-hand side
// previews the words by section with the order they'll project in.
//
//   + Queue (Enter)     adds it to the end of the queue at once
//   Edit first (E)      opens it in the queue's song editor, to change before adding
//   ↑ ↓ pick · Esc close · typing goes to the search box
//
// Collections ("Communion", "Christmas", "Choir") sit under the sources with
// their counts: pick one to see its songs; the preview's chips put the picked
// song in or out of a collection. Kept on the device (meta "songCollections")
// and saved through the outbox (PUT /song_collections/:id, the whole
// collection each time), so they work offline. Accounts only.
//
// Window events: out setlist:add {kind: "song", …, duplicate}, setlist:edit-song;
// in song-bank:open, song-bank:saved {song} (the editor saved one).
const SOURCES = { "": "All songs", yours: "My songs", hymnal: "Hymnal" }
const MAX_ROWS = 200

export default class extends Controller {
  static targets = [ "dialog", "search", "sources", "results", "preview", "status", "collections", "newCollection" ]
  static values = { url: String }

  connect() {
    if (this.element.classList.contains("is-output")) return
    this._songs = []
    this._source = ""
    this._collections = []
    this._collection = null
    this._picked = 0
    this._listeners = {
      "song-bank:open": () => this.open(),
      "song-bank:saved": (e) => this._saved(e.detail?.song)
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
  }

  disconnect() {
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
  }

  // ---- open / close ------------------------------------------------------------------

  async open(event) {
    event?.preventDefault?.()
    if (!this.hasDialogTarget) return
    this.dialogTarget.hidden = false
    this.element.classList.add("is-song-bank-open")
    this.searchTarget.focus()
    this.searchTarget.select()
    this._collections = await this._withPending((await cachedCollections()) || [])
    this._paintCollections()
    if (!this._songs.length) {
      this._songs = (await cachedSongs()) || []
      this._status(this._songs.length ? "" : "Gathering songs…")
      this._paint()
    }
    const fresh = await refreshSongs(this.urlValue)
    if (fresh) {
      this._songs = fresh
      this._collections = await this._withPending((await cachedCollections()) || [])
      this._status("")
      this._paint()
    }
    else if (!this._songs.length) this._status("No songs saved on this device yet — open the song bank once while online.")
    else this._status("Offline — showing the songs saved on this device.")
  }

  close(event) {
    event?.preventDefault?.()
    if (!this.hasDialogTarget) return
    this.dialogTarget.hidden = true
    this.element.classList.remove("is-song-bank-open")
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // ---- search / filter -------------------------------------------------------------

  search() {
    this._picked = 0
    this._paint()
  }

  pickSource(event) {
    this._source = event.currentTarget.dataset.source || ""
    this._collection = null
    this._picked = 0
    this._paint()
    this.searchTarget.focus()
  }

  key(event) {
    const max = this._results.length - 1
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); this.close(); return }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this._picked = Math.max(0, Math.min(max, this._picked + (event.key === "ArrowDown" ? 1 : -1)))
      this._paintPicked()
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (event.shiftKey) this._edit(this._results[this._picked]?.song)
      else this._add(this._results[this._picked]?.song)
    } else if ((event.key === "e" || event.key === "E") && event.target !== this.searchTarget) {
      event.preventDefault()
      this._edit(this._results[this._picked]?.song)
    }
    event.stopPropagation() // the preach-mode keys (arrows, L, N…) stay out of the bank
  }

  // ---- collections ------------------------------------------------------------------------

  pickCollection(event) {
    const id = event.currentTarget.closest("[data-collection]")?.dataset.collection
    this._collection = this._collection === id ? null : id
    this._source = ""
    this._picked = 0
    this._paint()
    this.searchTarget.focus()
  }

  newCollectionKey(event) {
    event.stopPropagation() // Enter here names a collection; it doesn't add a song
    if (event.key === "Enter") { event.preventDefault(); this.createCollection() }
    else if (event.key === "Escape") { event.preventDefault(); this.newCollectionTarget.value = ""; this.searchTarget.focus() }
  }

  createCollection(event) {
    event?.preventDefault?.()
    if (owner() === "guest") { window.dispatchEvent(new CustomEvent("auth:required")); return }
    const name = this.newCollectionTarget.value.trim().slice(0, 60)
    if (!name) { this.newCollectionTarget.focus(); return }
    let collection = this._collections.find((c) => c.name.toLowerCase() === name.toLowerCase())
    if (!collection) {
      collection = { id: newTempId().replace(/^tmp-/, "col-"), name, titles: [] }
      this._collections.push(collection)
      // Make it with the picked song in it — "new collection from this song".
      const song = this._results?.[this._picked]?.song
      if (song && event?.currentTarget?.dataset?.withSong) collection.titles.push(song.title)
      this._saveCollection(collection)
    }
    this.newCollectionTarget.value = ""
    this._collection = collection.id
    this._source = ""
    this._picked = 0
    this._paint()
    this._flash(`Collection “${collection.name}” ready — use the chips beside a song to add it`)
  }

  toggleInCollection(event) {
    event.preventDefault()
    const collection = this._collections.find((c) => c.id === event.currentTarget.dataset.collection)
    const song = this._results?.[this._picked]?.song
    if (!collection || !song) return
    collection.titles = toggleTitle(collection.titles, song.title)
    this._saveCollection(collection)
    const inIt = inCollection(collection, song)
    this._paintSources(this.searchTarget.value)
    this._paintCollections()
    this._paintPreview(song)
    this._flash(inIt ? `Added “${song.title}” to ${collection.name}` : `Took “${song.title}” out of ${collection.name}`)
  }

  async deleteCollection(event) {
    event.preventDefault()
    event.stopPropagation()
    const collection = this._collections.find((c) => c.id === event.currentTarget.closest("[data-collection]")?.dataset.collection)
    if (!collection || !window.confirm(`Delete the “${collection.name}” collection? The songs stay in your bank.`)) return
    this._collections = this._collections.filter((c) => c !== collection)
    if (this._collection === collection.id) this._collection = null
    storeCollections(this._collections)
    await queueRecordRemove("song-collection", `/song_collections/${collection.id}`, owner()).catch(() => {})
    flushOutbox().catch(() => {})
    this._paint()
  }

  _saveCollection(collection) {
    storeCollections(this._collections)
    queueRecordSave("song-collection", `/song_collections/${collection.id}`,
      { song_collection: { name: collection.name, titles: collection.titles } }, owner())
      .then(() => flushOutbox()).catch(() => {})
  }

  // The server's list with this device's unsynced changes on top.
  async _withPending(list) {
    const ops = (await pendingOps().catch(() => [])).filter((o) => o.owner === owner() && /^song-collection/.test(o.kind || ""))
    return applyCollectionOps(list, ops)
  }

  _paintCollections() {
    if (!this.hasCollectionsTarget) return
    const signedIn = owner() !== "guest"
    this.collectionsTarget.closest(".bank-collections")?.classList.toggle("is-guest", !signedIn)
    this.collectionsTarget.replaceChildren(...this._collections.map((c) => {
      const row = el("div", `coll${c.id === this._collection ? " is-on" : ""}`)
      row.dataset.collection = c.id
      const pick = el("button", "pick")
      pick.type = "button"
      pick.dataset.action = "song-bank#pickCollection"
      pick.setAttribute("aria-pressed", String(c.id === this._collection))
      pick.append(el("span", "name", c.name), el("span", "n", String(this._songs.filter((s) => inCollection(c, s)).length)))
      const del = el("button", "del", "✕")
      del.type = "button"
      del.title = `Delete the “${c.name}” collection`
      del.dataset.action = "song-bank#deleteCollection"
      row.append(pick, del)
      return row
    }))
  }

  // ---- actions -------------------------------------------------------------------------

  addRow(event) {
    event.preventDefault()
    event.stopPropagation()
    this._add(this._songAt(event))
  }

  editRow(event) {
    event.preventDefault()
    event.stopPropagation()
    this._edit(this._songAt(event))
  }

  pickRow(event) {
    const i = Number(event.currentTarget.closest("[data-index]")?.dataset.index)
    if (Number.isNaN(i)) return
    this._picked = i
    this._paintPicked()
  }

  addPicked(event) {
    event?.preventDefault?.()
    this._add(this._results[this._picked]?.song)
  }

  editPicked(event) {
    event?.preventDefault?.()
    this._edit(this._results[this._picked]?.song)
  }

  async removePicked(event) {
    event?.preventDefault?.()
    const song = this._results[this._picked]?.song
    if (!song?.saved) return
    if (!window.confirm(`Remove “${song.title}” from your songs? (Queues that already have it keep their copy.)`)) return
    this._songs = this._songs.filter((s) => s !== song)
    this._paint()
    await queueSongRemove(song, owner()).catch(() => {})
    flushOutbox().catch(() => {})
  }

  _add(song) {
    if (!song) return
    window.dispatchEvent(new CustomEvent("setlist:add", {
      detail: { kind: "song", title: song.title, body: song.body, arrangement: song.arrangement || "", duplicate: true }
    }))
    this._flash(`Added “${song.title}” to the queue`)
  }

  _edit(song) {
    if (!song) return
    this.close()
    window.dispatchEvent(new CustomEvent("setlist:edit-song", { detail: { title: song.title, body: song.body, arrangement: song.arrangement || "" } }))
  }

  // The editor saved a song: show it straight away (the server copy follows).
  _saved(song) {
    if (!song?.title) return
    const key = song.title.trim().toLowerCase()
    this._songs = [ { ...song, source: "yours", saved: true }, ...this._songs.filter((s) => s.title.trim().toLowerCase() !== key) ]
    if (this.hasDialogTarget && !this.dialogTarget.hidden) this._paint()
  }

  _songAt(event) {
    const i = Number(event.currentTarget.closest("[data-index]")?.dataset.index)
    return this._results?.[i]?.song
  }

  // ---- painting ---------------------------------------------------------------------

  _paint() {
    if (!this.hasResultsTarget) return
    const query = this.searchTarget.value
    const collection = this._collections.find((c) => c.id === this._collection)
    const pool = collection ? this._songs.filter((s) => inCollection(collection, s)) : this._songs
    this._results = searchSongs(pool, query, { source: this._source }).slice(0, MAX_ROWS)
    this._paintSources(query)
    this._paintCollections()
    if (!this._results.length) {
      const where = collection ? ` in ${collection.name}` : (this._source ? ` in ${SOURCES[this._source]}` : "")
      const empty = el("div", "bank-empty", collection && !query.trim() ? `${collection.name} is empty — pick a song and tap its “${collection.name}” chip.` : (this._songs.length ? `No song matches “${query.trim()}”${where}.` : ""))
      if (this._songs.length) empty.append(el("span", "hint", "Try a line of the words, or paste the song in the queue's song editor."))
      this.resultsTarget.replaceChildren(empty)
      this.previewTarget.replaceChildren()
      return
    }
    this.resultsTarget.replaceChildren(...this._results.map((r, i) => this._row(r, i)))
    this._paintPicked()
  }

  _paintSources(query) {
    if (!this.hasSourcesTarget) return
    const counts = { "": 0, yours: 0, hymnal: 0 }
    searchSongs(this._songs, query).forEach((r) => { counts[""]++; counts[r.song.source] = (counts[r.song.source] || 0) + 1 })
    this.sourcesTarget.querySelectorAll("[data-source]").forEach((btn) => {
      const src = btn.dataset.source
      const on = !this._collection && src === this._source
      btn.classList.toggle("is-on", on)
      btn.setAttribute("aria-pressed", String(on))
      btn.querySelector(".n").textContent = String(counts[src] || 0)
    })
  }

  _row({ song, line }, index) {
    const row = el("div", `bank-row${song.source === "hymnal" ? " is-hymn" : ""}`)
    row.dataset.index = String(index)
    row.dataset.action = "click->song-bank#pickRow dblclick->song-bank#addRow"
    row.setAttribute("role", "option")
    const main = el("div", "main")
    main.append(el("span", "t", song.title))
    if (line) main.append(el("span", "line", line.trim()))
    const author = el("span", "author", song.author || (song.source === "hymnal" ? "" : song.saved ? "Saved song" : "Queued before"))
    const rights = el("span", "rights", song.source === "hymnal" ? (song.copyright || "Public domain") : "Yours")
    const acts = el("span", "acts")
    acts.append(button("+ Queue", "song-bank#addRow", "Add to the end of the queue (Enter)", "add"),
      button("Edit", "song-bank#editRow", "Change it before adding (Shift+Enter)", "edit"))
    row.append(main, author, rights, acts)
    return row
  }

  _paintPicked() {
    const rows = this.resultsTarget.querySelectorAll(".bank-row")
    rows.forEach((r, i) => { r.classList.toggle("is-picked", i === this._picked); r.setAttribute("aria-selected", String(i === this._picked)) })
    rows[this._picked]?.scrollIntoView?.({ block: "nearest" })
    this._paintPreview(this._results[this._picked]?.song)
  }

  _paintPreview(song) {
    if (!this.hasPreviewTarget) return
    if (!song) { this.previewTarget.replaceChildren(); return }
    const { slides, labelled } = songSlides(song.body, song.arrangement)
    const head = el("div", "head")
    head.append(el("div", "t", song.title))
    const meta = [ song.author, song.year, song.source === "hymnal" ? (song.copyright || "Public domain") : null ].filter(Boolean).join(" · ")
    if (meta) head.append(el("div", "meta", meta))
    head.append(el("div", "flow", labelled ? `Projects as ${flowCodes(slides)}` : `${slides.length} slide${slides.length === 1 ? "" : "s"}`))
    const acts = el("div", "acts")
    acts.append(button("+ Add to queue", "song-bank#addPicked", "Enter", "add"), button("Edit first", "song-bank#editPicked", "Shift+Enter", "edit"))
    if (song.saved) acts.append(button("Remove from my songs", "song-bank#removePicked", "", "remove"))
    head.append(acts)
    if (owner() !== "guest") {
      const chips = el("div", "colls")
      chips.append(el("span", "lbl", "Collections"))
      this._collections.forEach((c) => {
        const on = inCollection(c, song)
        const chip = button(`${on ? "✓ " : "+ "}${c.name}`, "song-bank#toggleInCollection", on ? `Take it out of ${c.name}` : `Add it to ${c.name}`, `chip${on ? " is-on" : ""}`)
        chip.dataset.collection = c.id
        chip.setAttribute("aria-pressed", String(on))
        chips.append(chip)
      })
      if (!this._collections.length) chips.append(el("span", "none", "Make one on the left — e.g. Communion"))
      head.append(chips)
    }

    // The words as written, each section once, labels small.
    const seen = new Set()
    const sections = slides.filter((s) => { const k = `${s.label}|${s.text}`; if (seen.has(k)) return false; seen.add(k); return true })
    const words = el("div", "words")
    sections.forEach((s) => {
      const block = el("div", "sec")
      if (s.label) block.append(el("span", "lbl", s.label))
      block.append(el("div", "txt", s.text))
      words.append(block)
    })
    this.previewTarget.replaceChildren(head, words)
    this.previewTarget.scrollTop = 0
  }

  _status(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text || ""
  }

  _flash(text) {
    this._status(text)
    clearTimeout(this._flashTimer)
    this._flashTimer = setTimeout(() => this._status(""), 2500)
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

function button(label, action, title, className) {
  const b = el("button", className, label)
  b.type = "button"
  b.dataset.action = action
  if (title) b.title = title
  return b
}
