import { Controller } from "@hotwired/stimulus"
import { getMeta, setMeta } from "../lib/offline/db"
import { quickFetch, isNetworkSlow } from "../lib/offline/network"
import { queueRecordSave, queueRecordRemove, flushOutbox, newTempId } from "../lib/offline/outbox"
import { owner } from "../lib/offline/page"
import { songSlides } from "../lib/song_sheet"
import { setLabel, setPages } from "../lib/slides/scripture_set"

// Service templates: keep a whole service order ("Sunday Service",
// "Midweek") and reuse it — add it to this queue, or start a new service from
// it. Lives on its dialog ([data-controller=service-templates]); opened by the
// queue's "Templates" tool.
//
// The list is kept on the device (IndexedDB meta "serviceTemplates") so the
// picker opens and "Add to this queue" works with no signal; saving goes
// through the outbox (PUT /service_templates/:id upserts the whole template).
// Starting a new service makes a study on the server, so it needs a connection.
// Accounts only: a guest is asked to sign up (auth:required).
const META = "serviceTemplates"
const URL_BASE = "/service_templates"

export default class extends Controller {
  static targets = [ "name", "list", "status", "save" ]

  connect() {
    this.templates = []
    this._open = (e) => { if (e.detail?.tool === "templates") this.open() }
    window.addEventListener("queue-tool:open", this._open)
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  get signedIn() {
    return owner() !== "guest"
  }

  async open() {
    this.element.hidden = false
    this.nameTarget.value ||= suggestName()
    this.nameTarget.focus()
    this.nameTarget.select()
    this.templates = this._keepPending((await getMeta(this._metaKey()).catch(() => null)) || [])
    this._paint()
    if (!this.signedIn) { this._status("Sign in to keep service templates — they follow you to any computer."); return }
    const fresh = await this._refresh()
    if (fresh) { this.templates = this._keepPending(fresh); this._paint() } else if (navigator.onLine === false || isNetworkSlow()) this._status("Offline — showing the templates saved on this computer.")
  }

  close(event) {
    event?.preventDefault?.()
    this.element.hidden = true
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  key(event) {
    event.stopPropagation()
    if (event.key === "Escape") { event.preventDefault(); this.close() }
  }

  nameKey(event) {
    if (event.key === "Enter") { event.preventDefault(); this.saveCurrent() }
  }

  _metaKey() {
    return `${META}:${owner()}`
  }

  async _refresh() {
    if (navigator.onLine === false || isNetworkSlow()) return null
    try {
      const { res, body } = await quickFetch(URL_BASE, { headers: { Accept: "application/json" } }, { timeoutMs: 4000, read: "json" })
      if (!res.ok || !Array.isArray(body?.templates)) return null
      const merged = this._keepPending(body.templates)
      await setMeta(this._metaKey(), merged).catch(() => {})
      return merged
    } catch { return null }
  }

  // A list read from the device or the server, plus any template saved here
  // that it doesn't know yet (saved while it was loading, or not synced).
  _keepPending(list) {
    const ids = new Set(list.map((t) => t.id))
    return [ ...this.templates.filter((t) => t.pending && !ids.has(t.id)), ...list ]
  }

  // ---- save the queue as a template ------------------------------------------------------

  async saveCurrent(event) {
    event?.preventDefault?.()
    if (!this.signedIn) { window.dispatchEvent(new CustomEvent("auth:required")); return }
    const name = this.nameTarget.value.trim()
    if (!name) { this._status("Give the template a name — e.g. Sunday Service"); this.nameTarget.focus(); return }
    const items = this._queueItems().filter((i) => i.kind !== "picture").map(snapshot)
    if (!items.length) { this._status("The queue is empty — line up the service first, then save it."); return }
    const existing = this.templates.find((t) => t.name.toLowerCase() === name.toLowerCase())
    if (existing && !window.confirm(`Replace the “${existing.name}” template with this order?`)) return
    const template = { id: existing?.id || newTempId().replace(/^tmp-/, "tpl-"), name, items, updated_at: new Date().toISOString(), pending: true }
    this.templates = [ template, ...this.templates.filter((t) => t.id !== template.id) ]
    await setMeta(this._metaKey(), this.templates).catch(() => {})
    await queueRecordSave("service-template", `${URL_BASE}/${template.id}`, { service_template: { name, items } }, owner())
    flushOutbox().catch(() => {})
    this._paint()
    this._status(`Saved “${name}” — ${items.length} item${items.length === 1 ? "" : "s"}${navigator.onLine === false ? " (will sync when online)" : ""}`)
  }

  _queueItems() {
    let items = []
    window.dispatchEvent(new CustomEvent("setlist:request-items", { detail: { reply: (list) => { items = list } } }))
    return items
  }

  // ---- use a template ---------------------------------------------------------------------

  apply(event) {
    const t = this._templateFor(event)
    if (!t) return
    window.dispatchEvent(new CustomEvent("setlist:add-items", { detail: { items: t.items.map(queueFields) } }))
    this._status(`Added “${t.name}” to this queue`)
    this.close()
  }

  async start(event) {
    const t = this._templateFor(event)
    if (!t) return
    if (navigator.onLine === false) { this._status("Starting a new service needs a connection — “Add to this queue” works offline."); return }
    this._status(`Starting “${t.name}”…`)
    await flushOutbox().catch(() => {}) // a template saved a moment ago reaches the server first
    try {
      const res = await fetch(`${URL_BASE}/${encodeURIComponent(t.id)}/start`, {
        method: "POST", credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
      })
      if (res.status === 401) { window.dispatchEvent(new CustomEvent("auth:required")); return }
      const body = await res.json()
      if (!res.ok || !body.url) throw new Error()
      window.location.assign(body.url)
    } catch {
      this._status("Couldn't start it just now — try again, or use “Add to this queue”.")
    }
  }

  async remove(event) {
    const t = this._templateFor(event)
    if (!t || !window.confirm(`Delete the “${t.name}” template? Services already made from it keep their queue.`)) return
    this.templates = this.templates.filter((x) => x !== t)
    await setMeta(this._metaKey(), this.templates).catch(() => {})
    await queueRecordRemove("service-template", `${URL_BASE}/${t.id}`, owner())
    flushOutbox().catch(() => {})
    this._paint()
  }

  _templateFor(event) {
    const id = event.currentTarget.closest("[data-id]")?.dataset.id
    return this.templates.find((t) => t.id === id)
  }

  // ---- painting ------------------------------------------------------------------------------

  _paint() {
    if (!this.templates.length) {
      this.listTarget.replaceChildren(el("li", "empty", this.signedIn
        ? "No templates yet. Line up a service, name it above and save — next week it's one click."
        : "Sign in to save your service order as a template."))
      return
    }
    this.listTarget.replaceChildren(...this.templates.map((t) => {
      const li = el("li", "tpl-row")
      li.dataset.id = t.id
      const main = el("div", "main")
      main.append(el("span", "t", t.name), el("span", "m", summary(t)))
      const acts = el("div", "acts")
      acts.append(button("Add to this queue", "service-templates#apply", "add"), button("New service", "service-templates#start", "start"),
        button("✕", "service-templates#remove", "op", "Delete this template"))
      li.append(main, acts)
      return li
    }))
  }

  _status(text) {
    this.statusTarget.textContent = text || ""
  }
}

// What a template keeps of a queue item.
function snapshot(item) {
  const out = { kind: item.kind }
  ;[ "reference", "title", "body", "arrangement" ].forEach((k) => { if (item[k]) out[k] = item[k] })
  if (item.data) out.data = item.data
  return out
}

// A template item → the fields the queue adds.
export function queueFields(item) {
  const fields = { kind: item.kind, reference: item.reference || null, title: item.title || null, body: item.body || null,
    arrangement: item.arrangement || null, data: item.data || null }
  if (item.kind === "scripture") fields.label = item.reference
  else if (item.kind === "scripture_set") fields.label = item.title || setLabel(item.data)
  else fields.label = item.title || String(item.body || "").split("\n").find((l) => l.trim()) || ""
  if (item.kind === "song" || item.kind === "thought") fields.stanzas = songSlides(item.body || "", item.arrangement || "").slides.length
  else if (item.kind === "scripture_set") fields.stanzas = setPages(item.data).length
  else if (item.kind === "presentation") fields.stanzas = Number(item.data?.pages || 0)
  else if (item.kind === "seminar") fields.stanzas = item.data?.slides?.length || 0
  else fields.stanzas = 0
  return fields
}

function summary(t) {
  const counts = {}
  ;(t.items || []).forEach((i) => { counts[i.kind] = (counts[i.kind] || 0) + 1 })
  const names = { scripture: "scripture", scripture_set: "scripture slide", song: "song", thought: "thought", presentation: "presentation", seminar: "seminar" }
  const parts = Object.entries(counts).map(([ k, n ]) => `${n} ${names[k] || k}${n === 1 ? "" : "s"}`)
  return `${parts.join(" · ")}${t.pending ? " · not synced yet" : ""}`
}

function suggestName() {
  const day = new Date().getDay()
  return day === 0 ? "Sunday Service" : (day === 3 ? "Midweek Service" : "Sunday Service")
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

function button(label, action, className, title) {
  const b = el("button", className, label)
  b.type = "button"
  b.dataset.action = action
  if (title) b.title = title
  return b
}
