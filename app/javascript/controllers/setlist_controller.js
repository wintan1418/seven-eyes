import { Controller } from "@hotwired/stimulus"
import { getMeta, setMeta } from "../lib/offline/db"
import { warmLocal, localState } from "../lib/offline/local_pane"
import { referenceLabel } from "../lib/offline/reference_parser"
import {
  queueSetlistCreate, queueSetlistUpdate, queueSetlistDestroy, cancelSetlistDestroy, queueSetlistOrder,
  setlistOps, flushOutbox, subscribe, newTempId
} from "../lib/offline/outbox"
import { isNetworkSlow, quickFetch } from "../lib/offline/network"
import { owner } from "../lib/offline/page"
import { splitReferences, mergeQueue, moveItem, queueKey, nextUp, serverKey } from "../lib/offline/setlist_state"
import { startDrag } from "../lib/setlist_drag"
import { songSlides } from "../lib/song_sheet"
import { richFor } from "../lib/slides/rich_slides"
import { pageUrl } from "../lib/slides/deck_store"

// The preach queue ("setlist"). Lives on .ps-root.
//
// Local-first, like EasyWorship's schedule: every add / edit / remove /
// reorder changes the device's copy (IndexedDB meta "setlist:<study>") and the
// DOM at once, then syncs in the background through the outbox (setlist-*
// ops, lib/offline/outbox.js) — so it works with no signal and survives a
// reload. On load the server's list (rendered into the frame) is merged with
// the device's copy and whatever hasn't synced yet (lib/offline/setlist_state).
// An item never silently disappears: it shows "Will sync when online" while
// waiting and "Couldn't save — retry" if the server refused it.
//
// In preach mode a click previews (the preview controller); double-click,
// Enter on a previewed item, or L sends it live. On a wide screen the queue
// docks as a column of the operator screen instead of covering it.
//
// Window events:
//   out  preview:load {kind, reference|title/body/image, cid, label}  — stage in Preview
//   out  setlist:present {…same}                                       — straight to the screen
//   out  setlist:changed {keys, live, next}                            — for the preview controller
//   in   setlist:present (from anywhere: which queue item is live), setlist:add {kind, reference…},
//        setlist:preview-next, setlist:focus, setlist:open, preview:changed {cid},
//        preach:passage {reference} (auto-add what went on screen), preach:enter,
//        setlist:edit-song {title, body, arrangement} (the song bank's "Edit first")
//
// Songs: the words may carry section labels and an order ("V1 C V2 C") — the
// song editor (song_editor controller) helps write them; lib/song_sheet turns
// them into slides. Finding a song to add is the song bank (song_bank controller).
const AUTO_QUEUE_KEY = "ps-autoqueue"
const DOCK_QUERY = "(min-width: 1100px)"
const WAITING_AFTER_MS = 2500 // a change not saved by then is shown as waiting for the network
const RETRY_EVERY_MS = 10_000
const UNDO_MS = 6000

export default class extends Controller {
  static targets = [ "host", "form", "list", "reference", "hint", "error", "title", "body", "arrangement", "submit", "cancel",
    "nextUp", "autoQueue" ]
  static values = { libraryUrl: String }

  initialize() {
    this.items = []
    this._failed = {}
    this._pending = new Map() // cid → since (ms); "order" for a pending reorder
    this._syncedAt = 0
    this._chain = Promise.resolve()
  }

  connect() {
    this._output = this.element.classList.contains("is-output")
    if (this._output) return
    this._autoQueue = readAutoQueue()
    if (this.hasAutoQueueTarget) this.autoQueueTarget.checked = this._autoQueue
    this._listeners = {
      "setlist:present": (e) => this._wentLive(e.detail),
      "setlist:add": (e) => this._addFromOutside(e.detail),
      "setlist:preview-next": () => this.previewNext(),
      "setlist:focus": () => this.focusQueue(),
      "setlist:open": () => this.open(),
      "setlist:edit-song": (e) => this._editSong(e.detail),
      // The slide tools (scripture set composer, presentation import, seminar
      // builder, service templates, order of service) — lib/slides, *_controller.
      "setlist:add-item": (e) => { const item = this._insert(e.detail.fields, e.detail.at ?? this.items.length); e.detail.done?.(item); this._toast(`Added ${item.label} to the queue`) },
      "setlist:add-items": (e) => this._addMany(e.detail?.items || []),
      "setlist:replace-item": (e) => this._replace(e.detail?.cid, e.detail?.fields),
      "setlist:request-items": (e) => e.detail?.reply?.(this.items.map((i) => ({ ...i }))),
      "preview:changed": (e) => { this._previewCid = e.detail?.cid || null; this._paintMarks() },
      "preach:passage": (e) => this._autoAdd(e.detail?.reference),
      "preach:enter": () => { if (window.matchMedia?.(DOCK_QUERY).matches) this.open() },
      online: () => this._kick({ force: true })
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    this._unsubscribe = subscribe((m) => this._onOutbox(m))
    this._retryTimer = setInterval(() => { if (this._pending.size) this._kick({ force: true }) }, RETRY_EVERY_MS)
    this._tickTimer = setInterval(() => { if (this._pending.size) this._paintMarks() }, 1000)
    warmLocal()
  }

  disconnect() {
    if (this._output) return
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
    this._unsubscribe?.()
    clearInterval(this._retryTimer)
    clearInterval(this._tickTimer)
  }

  // ---- open / close / dock ------------------------------------------------------

  open(event) {
    event?.preventDefault?.()
    if (!this.hasHostTarget) return
    this.hostTarget.classList.add("is-open")
    this._syncDock()
  }

  close(event) {
    event?.preventDefault?.()
    if (!this.hasHostTarget) return
    this.hostTarget.classList.remove("is-open")
    this._syncDock()
  }

  toggle(event) {
    event?.preventDefault?.()
    if (!this.hasHostTarget) return
    this.hostTarget.classList.toggle("is-open")
    this._syncDock()
  }

  // The CSS docks the open queue as a column in preach mode on a wide screen.
  _syncDock() {
    this.element.classList.toggle("is-queue-open", this.hostTarget.classList.contains("is-open"))
    window.dispatchEvent(new Event("resize")) // preach refits the verse to the room it has now
  }

  _docked() {
    return this._preaching() && !!window.matchMedia?.(DOCK_QUERY).matches
  }

  _preaching() {
    return this.element.classList.contains("is-preaching")
  }

  // ---- load: server list + the device's copy + changes not yet synced ----------------

  // (Stimulus calls this before connect().) The server's list is usable at
  // once; the device's copy and pending changes are layered on a moment later.
  listTargetConnected(list) {
    if (this.element.classList.contains("is-output")) return
    let server = []
    try { server = JSON.parse(list.dataset.items || "[]") } catch { server = [] }
    const serverTime = Number(list.dataset.serverTime || 0)
    this.items = mergeQueue({ server, serverTime })
    this._early = new Set() // added before the device's copy was read
    this._hydrated = false
    this._ready = this._hydrate(server, serverTime)
  }

  get studyId() {
    return (this.libraryUrlValue.match(/\/studies\/(\d+)/) || [])[1] || null
  }

  async _hydrate(server, serverTime) {
    const [ local, ops ] = await Promise.all([
      getMeta(this._metaKey()).catch(() => null),
      this.studyId ? setlistOps(this.studyId, owner()).catch(() => []) : []
    ])
    const early = this.items.filter((i) => this._early.has(i.cid))
    this.items = mergeQueue({ server, serverTime, local, ops })
    early.forEach((i) => { if (!this.items.some((x) => x.cid === i.cid)) this.items.push(i) })
    this._hydrated = true
    this._failed = { ...(local?.failed || {}) }
    Object.keys(this._failed).forEach((cid) => { if (!this.items.some((i) => i.cid === cid)) delete this._failed[cid] })
    this._syncedAt = Math.max(local?.syncedAt || 0, serverTime)
    this._liveCid ||= local?.liveCid || null
    this._pendingFrom(ops)
    this._render()
    this._save()
    if (ops.length) this._kick()
  }

  _metaKey() {
    return `setlist:${this.studyId}`
  }

  _save() {
    if (!this.studyId) return
    const record = { items: this.items, syncedAt: this._syncedAt, failed: this._failed, liveCid: this._liveCid || null }
    setMeta(this._metaKey(), record).catch(() => {})
  }

  // ---- background sync ----------------------------------------------------------

  // Queue a change for the server, in order, without holding up the screen.
  _enqueue(fn) {
    this._chain = this._chain.then(fn).catch(() => {}).then(() => this._kick())
    return this._chain
  }

  // Send what's waiting. Right away when the network looks fine; when it is
  // known to be down or dead, the timer (and the `online` event) try again.
  _kick({ force = false } = {}) {
    clearTimeout(this._kickTimer)
    this._kickTimer = setTimeout(() => {
      if (navigator.onLine === false) return
      if (!force && isNetworkSlow()) return
      flushOutbox().catch(() => {})
    }, 40)
  }

  _pendingFrom(ops) {
    const since = new Map()
    ops.forEach((op) => {
      const key = op.setlist.action === "order" ? "order" : op.setlist.cid
      if (op.setlist.action === "destroy") return // gone from the list already
      since.set(key, Math.min(since.get(key) ?? Infinity, op.createdAt || Date.now()))
    })
    this._pending = since
  }

  async _onOutbox(message) {
    if (!this.studyId || !message) return
    if (message.type === "setlist-sync" && message.studyId === String(this.studyId)) {
      const item = this.items.find((i) => i.cid === message.cid)
      if (message.ok) {
        if (item && message.action === "create" && message.id != null) item.id = message.id
        delete this._failed[message.cid]
        if (message.serverTime) this._lastServerTime = Math.max(this._lastServerTime || 0, message.serverTime)
      } else if (message.status === 422 && item && message.action !== "destroy") {
        this._failed[message.cid] = message.error
      }
    }
    if (message.type !== "setlist-sync" && message.type !== "outbox") return
    const ops = await setlistOps(this.studyId, owner()).catch(() => [])
    this._pendingFrom(ops)
    if (!ops.length && this._lastServerTime) this._syncedAt = Math.max(this._syncedAt, this._lastServerTime)
    this._paintMarks()
    this._save()
  }

  // ---- adding -------------------------------------------------------------------

  // The add form: Enter (or "+ Add to queue") adds; the field is cleared and
  // keeps focus for the next one. Pictures still upload through the frame.
  add(event) {
    const kind = this._formKind()
    if (kind === "picture") return // the Turbo Frame form uploads it (needs a connection)
    event.preventDefault()
    if (this._editing) { this._saveEdit(kind); return }

    if (kind === "scripture") {
      const field = this.referenceTarget
      if (!localState().parse) warmLocal({ force: true }) // cold page: these go as typed (the server reads them); later adds parse here
      const { items, errors } = splitReferences(field.value, localState().parse, referenceLabel)
      if (!items.length && !errors.length) { this._showError("Type a reference — e.g. John 3:16"); field.focus(); return }
      items.forEach((i) => this._insert({ kind: "scripture", reference: i.reference, label: i.label }))
      field.value = errors.map((e) => e.raw).join(", ")
      errors.length ? this._showError(errors.map((e) => e.message).join(" · ")) : this._showError(null)
      this._paintHint()
      field.focus()
      return
    }

    const title = this.titleTarget.value.trim()
    const body = this.bodyTarget.value.trim()
    if (!title && !body) { this._showError("Give it a title or some words"); this.titleTarget.focus(); return }
    this._insert(slideItem(kind, title, body, this._arrangement(kind)))
    this._setSongFields("", "", "")
    this._showError(null)
    this.titleTarget.focus()
  }

  _arrangement(kind) {
    return kind === "song" && this.hasArrangementTarget ? this.arrangementTarget.value.trim() : ""
  }

  // Fill (or clear) the song fields; the song editor repaints its hints on input.
  _setSongFields(title, body, arrangement) {
    this.titleTarget.value = title || ""
    this.bodyTarget.value = body || ""
    if (this.hasArrangementTarget) this.arrangementTarget.value = arrangement || ""
    this.bodyTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // The song bank's "Edit first": the song lands in the add form to be changed
  // before it is queued (Enter / "+ Add to queue" adds it).
  _editSong(detail) {
    if (!detail) return
    if (this._editing) this._endEdit()
    this.open()
    this._setFormKind("song")
    this._setSongFields(detail.title, detail.body, detail.arrangement)
    this._showError(null)
    this.bodyTarget.focus()
    this.bodyTarget.setSelectionRange?.(0, 0)
    this.bodyTarget.scrollTop = 0
  }

  _insert(fields, at = this.items.length) {
    const item = { cid: newTempId(), id: null, title: null, body: null, arrangement: null, image: null, reference: null, stanzas: 0, ...fields }
    const index = Math.max(0, Math.min(at, this.items.length))
    this.items.splice(index, 0, item)
    if (!this._hydrated) this._early?.add(item.cid)
    this._pending.set(item.cid, Date.now())
    this._render({ flash: item.cid })
    this._save()
    const order = index < this.items.length - 1 ? this.items.map(serverKey) : null
    this._enqueue(async () => {
      await queueSetlistCreate(this.studyId, item, index, owner())
      if (order) await queueSetlistOrder(this.studyId, order, owner())
    })
    return item
  }

  // "+ Queue" on the live/preview label, a verse in the chapter list, or auto-add.
  _addFromOutside(detail) {
    if (!detail) return null
    const fields = detail.kind === "scripture" ? this._scriptureFields(detail.reference) : slideItem(detail.kind, detail.title, detail.body, detail.arrangement)
    if (!fields) return null
    const existing = !detail.duplicate && this.items.find((i) => queueKey(i) === queueKey(fields))
    if (existing) { if (!detail.quiet) this._toast(`${existing.label} is already in the queue`); return existing }
    const item = this._insert(fields, detail.at ?? this.items.length)
    if (!detail.quiet) this._toast(`Added ${item.label} to the queue`)
    return item
  }

  _scriptureFields(reference) {
    if (!reference) return null
    const parse = localState().parse
    const p = parse?.(reference)
    if (parse && !p?.valid) return null
    return { kind: "scripture", reference, label: p ? referenceLabel(p) : reference }
  }

  // Every scripture that goes live joins the queue (setting, default on), so
  // the queue becomes the service's schedule. It is slotted in right after
  // whatever was live from the queue, so "Next" still points at the plan.
  _autoAdd(reference) {
    if (!this._autoQueue || !reference || !this.studyId) return
    const fields = this._scriptureFields(reference)
    if (!fields) return
    const existing = this.items.find((i) => queueKey(i) === queueKey(fields))
    if (existing) { this._setLive(existing.cid); return }
    const liveIdx = this._liveCid ? this.items.findIndex((i) => i.cid === this._liveCid) : -1
    const item = this._addFromOutside({ ...fields, quiet: true, at: liveIdx + 1 })
    if (item) this._setLive(item.cid)
  }

  toggleAutoQueue() {
    this._autoQueue = this.autoQueueTarget.checked
    try { localStorage.setItem(AUTO_QUEUE_KEY, this._autoQueue ? "1" : "0") } catch { /* private mode */ }
  }

  // Live feedback under the reference field: what Enter will add, or why not.
  referenceTyped() {
    this._paintHint()
    const raw = this.referenceTarget.value
    const last = raw.split(/[\n,;]+/).map((s) => s.trim()).filter(Boolean).pop() || ""
    window.dispatchEvent(new CustomEvent("preview:typing", { detail: { raw: last, source: "queue" } }))
  }

  _paintHint() {
    if (!this.hasHintTarget) return
    const raw = this.referenceTarget.value.trim()
    const parse = localState().parse
    if (!raw || !parse) {
      this.hintTarget.dataset.tone = ""
      this.hintTarget.innerHTML = "Add several at once &mdash; separate with commas (<span class=\"eg\">John 3:16, Rom 8:28, Ps 23</span>). Enter adds; keep typing the next."
      return
    }
    const { items, errors } = splitReferences(raw, parse, referenceLabel)
    const parts = []
    if (items.length) parts.push(`↵ adds ${items.map((i) => i.label).join(" · ")}`)
    if (errors.length) parts.push(errors.map((e) => e.message).join(" · "))
    this.hintTarget.textContent = parts.join(" — ")
    this.hintTarget.dataset.tone = errors.length ? "error" : "ok"
  }

  _showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.hidden = !message
    this.errorTarget.textContent = message || ""
  }

  _formKind() {
    return this.formTarget.querySelector("input[name='setlist_item[kind]']:checked")?.value || "scripture"
  }

  // Radio change on the add form: show only the fields the kind needs.
  kindChanged(event) {
    this._setFormKind(event.target.value)
  }

  _setFormKind(kind) {
    const form = this.formTarget
    form.classList.remove("kind-scripture", "kind-song", "kind-thought", "kind-picture")
    form.classList.add(`kind-${kind}`)
    form.querySelectorAll(".kinds label").forEach((l) => {
      const input = l.querySelector("input")
      if (input.value === kind) input.checked = true
      l.classList.toggle("is-on", input.value === kind)
    })
  }

  // ---- editing --------------------------------------------------------------------

  edit(event) {
    event?.preventDefault?.()
    const item = this._itemFor(event?.target)
    if (item) this._startEdit(item)
  }

  _startEdit(item) {
    if (item.kind === "picture" || item.kind === "word") return // a word study is re-made from its root-word card
    const tool = { scripture_set: "scripture-set", presentation: "presentation", seminar: "seminar" }[item.kind]
    if (tool) { window.dispatchEvent(new CustomEvent("queue-tool:open", { detail: { tool, item: { ...item } } })); return }
    this.open()
    this._editing = item.cid
    this._setFormKind(item.kind)
    this.formTarget.classList.add("is-editing")
    if (item.kind === "scripture") this.referenceTarget.value = item.reference || item.label || ""
    else this._setSongFields(item.title, item.body, item.arrangement)
    this.submitTarget.textContent = "Save changes"
    this.cancelTarget.hidden = false
    this._showError(null)
    this._paintMarks()
    const field = item.kind === "scripture" ? this.referenceTarget : this.titleTarget
    field.focus()
    field.select?.()
  }

  cancelEdit(event) {
    if (event?.type === "keydown") { event.preventDefault(); event.stopPropagation() }
    if (!this._editing) { if (event?.type === "keydown") event.target.blur(); return }
    const cid = this._editing
    this._endEdit()
    this._focusItem(cid)
  }

  _endEdit() {
    this._editing = null
    this.formTarget.classList.remove("is-editing")
    this.referenceTarget.value = ""
    this._setSongFields("", "", "")
    this.submitTarget.innerHTML = "&#43; Add to queue"
    this.cancelTarget.hidden = true
    this._showError(null)
    this._paintHint()
    this._paintMarks()
  }

  _saveEdit(kind) {
    const item = this.items.find((i) => i.cid === this._editing)
    if (!item) { this._endEdit(); return }
    let fields
    if (kind === "scripture") {
      const { items, errors } = splitReferences(this.referenceTarget.value, localState().parse, referenceLabel)
      if (errors.length) { this._showError(errors.map((e) => e.message).join(" · ")); return }
      if (items.length !== 1) { this._showError("One reference per item when editing"); return }
      fields = { kind, reference: items[0].reference, label: items[0].label, title: null, body: null, arrangement: null, stanzas: 0 }
    } else {
      const title = this.titleTarget.value.trim()
      const body = this.bodyTarget.value.trim()
      if (!title && !body) { this._showError("Give it a title or some words"); return }
      fields = { ...slideItem(kind, title, body, this._arrangement(kind)), reference: null }
    }
    Object.assign(item, fields)
    delete this._failed[item.cid]
    this._pending.set(item.cid, Date.now())
    this._endEdit()
    this._render()
    this._save()
    this._enqueue(() => queueSetlistUpdate(this.studyId, item, serverFields(item), owner()))
    this._focusItem(item.cid)
    this._toast(`Updated ${item.label}`)
  }

  // A tool saved its item again (the composer / builder's "Save changes").
  _replace(cid, fields) {
    const item = this.items.find((i) => i.cid === cid)
    if (!item || !fields) return
    Object.assign(item, fields)
    delete this._failed[item.cid]
    this._pending.set(item.cid, Date.now())
    this._render()
    this._save()
    this._enqueue(() => queueSetlistUpdate(this.studyId, item, serverFields(item), owner()))
    this._focusItem(item.cid)
    this._toast(`Updated ${item.label}`)
  }

  // A service template's order, added to the end of this queue.
  _addMany(list) {
    if (!list.length) return
    list.forEach((fields) => this._insert({ ...fields, label: fields.label || fields.reference || fields.title || "" }))
    this._toast(`Added ${list.length} item${list.length === 1 ? "" : "s"} to the queue`)
  }

  // A tool button in the queue (data-tool="…"): its dialog opens.
  openTool(event) {
    event?.preventDefault?.()
    const tool = event?.currentTarget?.dataset.tool
    if (tool) window.dispatchEvent(new CustomEvent("queue-tool:open", { detail: { tool } }))
  }

  // ---- removing (with undo) ---------------------------------------------------------

  remove(event) {
    event?.preventDefault?.()
    const item = this._itemFor(event?.target)
    if (item) this._remove(item)
  }

  _remove(item) {
    const index = this.items.indexOf(item)
    if (index < 0) return
    if (this._editing === item.cid) this._endEdit()
    this.items.splice(index, 1)
    delete this._failed[item.cid]
    this._pending.delete(item.cid)
    if (this._selected === item.cid) this._selected = (this.items[index] || this.items[index - 1])?.cid || null
    this._render()
    this._save()
    this._enqueue(() => queueSetlistDestroy(this.studyId, item, owner()))
    this._lastRemoved = { item, index }
    this._toast(`Removed ${item.label}`, { undo: () => this.undoRemove() })
  }

  undoRemove(event) {
    event?.preventDefault?.()
    const removed = this._lastRemoved
    if (!removed) return
    this._lastRemoved = null
    this._hideToast()
    const item = { ...removed.item }
    const index = Math.min(removed.index, this.items.length)
    this.items.splice(index, 0, item)
    this._pending.set(item.cid, Date.now())
    this._selected = item.cid
    this._render({ flash: item.cid })
    this._save()
    const who = owner()
    this._enqueue(async () => {
      const stillHere = await cancelSetlistDestroy(item, who)
      if (!stillHere || item.id == null) { // the DELETE went (or the create never did): make it again
        item.id = null
        await queueSetlistCreate(this.studyId, item, index, who)
      }
      await queueSetlistOrder(this.studyId, this.items.map(serverKey), who)
    })
    this._focusItem(item.cid)
  }

  // "Couldn't save — retry".
  retry(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    const item = this._itemFor(event?.target)
    if (!item) return
    delete this._failed[item.cid]
    this._pending.set(item.cid, Date.now())
    this._paintMarks()
    this._save()
    const index = this.items.indexOf(item)
    this._enqueue(async () => {
      if (item.id == null) await queueSetlistCreate(this.studyId, item, index, owner())
      else await queueSetlistUpdate(this.studyId, item, serverFields(item), owner())
    })
    this._kick({ force: true })
  }

  // ---- reordering -------------------------------------------------------------------

  moveUp(event) { this._step(event, -1) }
  moveDown(event) { this._step(event, 1) }

  _step(event, delta) {
    event?.preventDefault?.()
    const item = this._itemFor(event?.target)
    if (!item) return
    const from = this.items.indexOf(item)
    this._move(from, from + delta)
  }

  _move(from, to) {
    if (from < 0 || to < 0 || to >= this.items.length || from === to) return
    const cid = this.items[from].cid
    this.items = moveItem(this.items, from, to)
    this._pending.set("order", Date.now())
    this._render()
    this._save()
    const order = this.items.map(serverKey)
    this._enqueue(() => queueSetlistOrder(this.studyId, order, owner()))
    return cid
  }

  // Drag by the ⠿ grip — pointer events, so mouse, pen and touch alike.
  dragStart(event) {
    const li = event.target.closest(".ps-setlist-item")
    if (!li || !this.hasListTarget) return
    startDrag(event, {
      list: this.listTarget, row: li,
      onDrop: (from, to) => { const cid = this._move(from, to); if (cid) this._focusItem(cid) }
    })
  }

  // ---- picking, previewing, going live ---------------------------------------------------

  // Click: Preview in preach mode (the projector doesn't change); before preach
  // mode a scripture is staged in the pane as it always was.
  present(event) {
    event?.preventDefault?.()
    const item = this._itemFor(event?.target)
    if (!item) return
    this._select(item.cid)
    if (this._preaching()) { this._preview(item); return }
    const detail = this._detail(item)
    if (detail.kind === "scripture") this._setLive(item.cid)
    window.dispatchEvent(new CustomEvent("setlist:present", { detail }))
  }

  // Double-click (or Enter on what's already in Preview): straight to the screen.
  presentLive(event) {
    event?.preventDefault?.()
    const item = this._itemFor(event?.target)
    if (!item || !this._preaching()) return
    this._goLive(item)
  }

  _preview(item) {
    window.dispatchEvent(new CustomEvent("preview:load", { detail: this._detail(item) }))
  }

  _goLive(item) {
    window.dispatchEvent(new CustomEvent("setlist:present", { detail: this._detail(item) }))
  }

  _detail(item) {
    return {
      kind: item.kind === "scripture" ? "scripture" : "slide",
      itemKind: item.kind, cid: item.cid, label: item.label,
      reference: item.reference || null, title: item.title || null, body: item.body || null,
      arrangement: item.arrangement || null, image: item.image || null, rich: richFor(item)
    }
  }

  // Something went on screen: if it is a queue item, it is "live" in the queue.
  _wentLive(detail) {
    if (this._preaching() && !this._docked()) this.close() // a covering drawer gets out of the way
    if (detail?.cid) this._setLive(detail.cid)
  }

  _setLive(cid) {
    this._liveCid = cid
    this._paintMarks()
    this._save()
  }

  // N: preview whatever is next after the live item.
  previewNext(event) {
    event?.preventDefault?.()
    const item = nextUp(this.items, this._liveCid)
    if (!item) { this._toast("That's the end of the queue"); return }
    this._select(item.cid)
    if (this._preaching()) this._preview(item)
    else window.dispatchEvent(new CustomEvent("setlist:present", { detail: this._detail(item) }))
  }

  // Q: the keyboard goes to the queue.
  focusQueue() {
    this.open()
    if (!this._selected || !this.items.some((i) => i.cid === this._selected)) {
      this._selected = (nextUp(this.items, this._liveCid) || this.items[0])?.cid || null
    }
    this._paintMarks()
    if (this.items.length) this._focusItem(this._selected)
    else this.referenceTarget.focus()
  }

  // Keys while the queue list has focus. Arrow left/right, Space, L, N, G…
  // fall through to preach mode.
  listKey(event) {
    if (event.target.closest?.("input, textarea, select")) return
    // Enter / Space on a row's own buttons (✎ ↑ ↓ ✕, retry) press that button.
    if ((event.key === "Enter" || event.key === " ") && event.target.closest?.(".ops, .sync")) return
    const idx = this.items.findIndex((i) => i.cid === this._selected)
    const item = this.items[idx]
    const key = event.key
    const handled = () => { event.preventDefault(); event.stopPropagation() }

    if ((key === "ArrowDown" || key === "ArrowUp") && event.altKey) {
      handled()
      if (item) { this._move(idx, idx + (key === "ArrowDown" ? 1 : -1)); this._focusItem(item.cid) }
    } else if (key === "ArrowDown" || key === "ArrowUp") {
      handled()
      const next = this.items[Math.max(0, Math.min(this.items.length - 1, idx + (key === "ArrowDown" ? 1 : -1)))] || this.items[0]
      if (next) this._focusItem(next.cid)
    } else if (key === "Home" || key === "End") {
      handled()
      const next = key === "Home" ? this.items[0] : this.items[this.items.length - 1]
      if (next) this._focusItem(next.cid)
    } else if (key === "Enter") {
      handled()
      if (!item) return
      if (!this._preaching()) window.dispatchEvent(new CustomEvent("setlist:present", { detail: this._detail(item) }))
      else if (this._previewCid === item.cid || event.shiftKey) this._goLive(item)
      else this._preview(item)
    } else if (key === "Delete" || key === "Backspace") {
      handled()
      if (item) this._remove(item)
      if (this._selected) this._focusItem(this._selected)
    } else if (key === "u" || key === "U" || ((event.metaKey || event.ctrlKey) && key === "z")) {
      handled()
      this.undoRemove()
    } else if (key === "e" || key === "E" || key === "F2") {
      handled()
      if (item) this._startEdit(item)
    } else if (key === "a" || key === "A") {
      handled()
      this._setFormKind("scripture")
      this.referenceTarget.focus()
    } else if (key === "Escape") {
      handled()
      this.listTarget.blur()
    }
  }

  _select(cid) {
    this._selected = cid
    this._paintMarks()
  }

  _focusItem(cid) {
    this._select(cid)
    const li = this._rowFor(cid)
    if (!li) return
    this.listTarget.focus({ preventScroll: true })
    li.scrollIntoView?.({ block: "nearest" })
  }

  _itemFor(el) {
    const cid = el?.closest?.(".ps-setlist-item")?.dataset.cid
    return cid ? this.items.find((i) => i.cid === cid) : null
  }

  _rowFor(cid) {
    if (!cid || !this.hasListTarget) return null
    return this.listTarget.querySelector(`.ps-setlist-item[data-cid="${CSS.escape(cid)}"]`)
  }

  // ---- rendering ------------------------------------------------------------------

  _render({ flash = null } = {}) {
    if (!this.hasListTarget) return
    const list = this.listTarget
    if (!this.items.length) {
      const empty = document.createElement("li")
      empty.className = "ps-setlist-empty"
      empty.textContent = "Nothing queued yet — add the first item below."
      list.replaceChildren(empty)
    } else {
      list.replaceChildren(...this.items.map((item, i) => this._itemElement(item, i)))
    }
    if (flash) {
      const row = this._rowFor(flash)
      row?.classList.add("is-new")
      row?.scrollIntoView?.({ block: "nearest" })
    }
    this._paintMarks()
  }

  _itemElement(item, index) {
    const li = el("li", `ps-setlist-item kind-${item.kind}`)
    li.setAttribute("role", "option")
    Object.assign(li.dataset, {
      kind: item.kind === "scripture" ? "scripture" : "slide",
      cid: item.cid, reference: item.reference || "", title: item.title || "", body: item.body || "",
      arrangement: item.arrangement || "", image: item.image || ""
    })
    const grip = el("span", "grip", "⠿")
    grip.dataset.action = "pointerdown->setlist#dragStart"
    grip.title = "Drag to reorder"
    grip.setAttribute("aria-hidden", "true")

    const present = el("button", "present")
    present.type = "button"
    present.dataset.action = "click->setlist#present dblclick->setlist#presentLive"
    present.title = "Click to preview (in preach mode) · double-click to go live"
    if (item.kind === "picture" && item.image) {
      const img = el("img", "thumb")
      img.src = item.image
      img.alt = ""
      img.loading = "lazy"
      present.append(img)
    } else if (item.kind === "presentation" && item.data?.deck) {
      const img = el("img", "thumb")
      img.alt = ""
      pageUrl(item.data.deck, 1, { thumb: true }).then((url) => { if (url) img.src = url; else img.classList.add("is-missing") })
      present.append(img)
    } else {
      present.append(el("span", "icon", KIND_ICONS[item.kind] || "❦"))
    }
    present.append(el("span", "num", String(index + 1)), el("span", "lbl", item.label || item.reference || item.title || ""))
    const count = item.kind === "presentation" ? Number(item.data?.pages || 0) : item.stanzas
    if (item.kind !== "scripture" && item.kind !== "picture" && count > 1) {
      present.append(el("span", "meta", `${count} ${item.kind === "presentation" ? "pages" : "slides"}`))
    }

    const sync = el("span", "sync")
    sync.dataset.sync = ""
    sync.hidden = true

    const ops = el("span", "ops")
    if (item.kind !== "picture" && item.kind !== "word") ops.append(op("✎", "setlist#edit", "Edit (E)"))
    const up = op("↑", "setlist#moveUp", "Move up (Alt+↑)")
    up.disabled = index === 0
    const down = op("↓", "setlist#moveDown", "Move down (Alt+↓)")
    down.disabled = index === this.items.length - 1
    const x = op("✕", "setlist#remove", "Remove (Delete)")
    x.classList.add("danger")
    ops.append(up, down, x)

    li.append(grip, present, sync, ops)
    return li
  }

  // Selection, live / preview / next marks and the per-item sync state —
  // cheap, so it runs on every change and once a second while anything waits.
  _paintMarks() {
    if (!this.hasListTarget) return
    const next = nextUp(this.items, this._liveCid)
    const offline = navigator.onLine === false || isNetworkSlow()
    const now = Date.now()
    this.listTarget.querySelectorAll(".ps-setlist-item").forEach((li) => {
      const cid = li.dataset.cid
      li.classList.toggle("is-selected", cid === this._selected)
      li.setAttribute("aria-selected", cid === this._selected ? "true" : "false")
      li.classList.toggle("is-live", cid === this._liveCid)
      li.classList.toggle("is-preview", cid === this._previewCid)
      li.classList.toggle("is-next", !!next && cid === next.cid)
      li.classList.toggle("is-editing", cid === this._editing)
      const sync = li.querySelector("[data-sync]")
      if (!sync) return
      const failed = this._failed[cid]
      const since = this._pending.get(cid)
      let state = ""
      if (failed) state = "error"
      else if (since != null) state = (offline || now - since > WAITING_AFTER_MS) ? "waiting" : "saving"
      li.dataset.syncState = state
      if (sync.dataset.state === state && state !== "error") return
      sync.dataset.state = state
      // A save that is just in flight shows nothing (the row would jump twice
      // under the pointer); only waiting and refused are worth a line.
      sync.hidden = !state || state === "saving"
      if (state === "error") {
        sync.replaceChildren()
        const btn = el("button", "retry", "Couldn't save — retry")
        btn.type = "button"
        btn.title = failed
        btn.dataset.action = "setlist#retry"
        sync.append(btn)
      } else {
        sync.textContent = state === "waiting" ? "Will sync when online" : (state === "saving" ? "Saving…" : "")
      }
    })
    if (this.hasHostTarget) this.hostTarget.classList.toggle("is-order-waiting", this._pending.has("order") && (offline || now - this._pending.get("order") > WAITING_AFTER_MS))
    this._paintNext(next)
    window.dispatchEvent(new CustomEvent("setlist:changed", {
      detail: { keys: this.items.map(queueKey), live: this._liveCid, next: next ? this._detail(next) : null }
    }))
  }

  _paintNext(next) {
    if (!this.hasNextUpTarget) return
    this.nextUpTarget.textContent = next ? next.label : (this.items.length ? "End of the queue" : "Queue is empty")
    this.nextUpTarget.disabled = !next
  }

  // ---- toasts (with Undo) ----------------------------------------------------------

  _toast(message, { undo = null } = {}) {
    let box = this.element.querySelector(".ps-queue-toast")
    if (!box) {
      box = el("div", "ps-queue-toast")
      box.setAttribute("role", "status")
      box.setAttribute("aria-live", "polite")
      this.element.appendChild(box)
    }
    box.replaceChildren(el("span", "msg", message))
    if (undo) {
      const btn = el("button", "undo", "Undo")
      btn.type = "button"
      btn.title = "Undo (U in the queue)"
      btn.addEventListener("click", undo)
      box.append(btn)
    }
    box.hidden = false
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => this._hideToast(), undo ? UNDO_MS : 2500)
  }

  _hideToast() {
    clearTimeout(this._toastTimer)
    const box = this.element.querySelector(".ps-queue-toast")
    if (box) box.hidden = true
  }
}

function slideItem(kind, title, body, arrangement) {
  const t = (title || "").trim()
  const b = (body || "").trim()
  const a = kind === "song" ? (arrangement || "").trim() : ""
  const stanzas = songSlides(b, a).slides.length
  const label = t || (b.split("\n").find((l) => l.trim() && !/^\[.*\]$/.test(l.trim())) || "").trim().slice(0, 60)
  return { kind, title: t || null, body: b || null, arrangement: a || null, label, stanzas }
}

// What the server keeps for an item (the outbox sends it).
function serverFields(item) {
  const fields = { kind: item.kind, reference: item.reference ?? "", title: item.title ?? "", body: item.body ?? "", arrangement: item.arrangement ?? "" }
  if (item.data) fields.data = item.data
  return fields
}

const KIND_ICONS = { scripture: "§", song: "♫", thought: "❦", scripture_set: "⧉", presentation: "▤", seminar: "▦", word: "ℵ" }

function readAutoQueue() {
  try { return localStorage.getItem(AUTO_QUEUE_KEY) !== "0" } catch { return true }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

function op(label, action, title) {
  const btn = el("button", "op", label)
  btn.type = "button"
  btn.dataset.action = action
  btn.title = title
  return btn
}
