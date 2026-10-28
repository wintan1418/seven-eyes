// The outbox: writes made with no signal (note autosaves, highlights, reading
// plan ticks, where a pane was moved to) wait here in IndexedDB and are
// replayed to the server, in order, once the network is back — on the
// `online` event, on every page load, and via Background Sync where the
// browser has it (the service worker runs flushOutbox too).
//
// Ops with the same `key` coalesce: ten offline note edits of one pane are one
// request carrying the latest text (and the revision the edits started from).
// A highlight made offline gets a temporary id ("tmp-…"); editing or removing
// it before sync rewrites the queued create instead of queueing more.
//
// Ops are tagged with the reader who made them (owner) and only replayed for
// that reader. Page and worker hear about progress on the "ps-offline"
// BroadcastChannel: { type: "outbox", pending }, { type: "notes-synced", … },
// { type: "highlight-id", tmp, id }, { type: "sync-problem", message }.
import { get, getAll, put, del, transaction, getMeta, setMeta, promisify } from "./db"
import { putHighlight, deleteHighlight, getHighlight } from "./store"

const CHANNEL = "ps-offline"
let channel = null

export function broadcast(message) {
  try {
    channel ||= new BroadcastChannel(CHANNEL)
    channel.postMessage(message)
  } catch { /* no BroadcastChannel (very old browsers) */ }
  // The sending context doesn't hear its own BroadcastChannel messages.
  try { self.dispatchEvent?.(new CustomEvent("offline:message", { detail: message })) } catch { /* worker without CustomEvent */ }
}

export function subscribe(fn) {
  let ch = null
  try { ch = new BroadcastChannel(CHANNEL); ch.onmessage = (e) => fn(e.data) } catch { /* none */ }
  const local = (e) => fn(e.detail)
  self.addEventListener?.("offline:message", local)
  return () => { ch?.close(); self.removeEventListener?.("offline:message", local) }
}

// Changes the reader would call "changes": not where a pane was moved to.
const COUNTED = (op) => op.kind !== "pane"

export async function pendingOps() {
  try { return (await getAll("outbox")).sort((a, b) => a.seq - b.seq) } catch { return [] }
}

export async function pendingCount() {
  return (await pendingOps()).filter(COUNTED).length
}

async function announce() {
  broadcast({ type: "outbox", pending: await pendingCount() })
}

// Insert or coalesce an op by key. `merge(existing)` returns the op to store
// (or null to drop the existing one); without it the new op replaces the old.
async function upsert(op, merge) {
  const now = Date.now()
  await transaction([ "outbox" ], async (tx) => {
    const store = tx.objectStore("outbox")
    const all = await promisify(store.getAll())
    const existing = all.find((o) => o.key === op.key && o.owner === op.owner)
    if (existing) {
      const next = merge ? merge(existing) : { ...existing, ...op, seq: existing.seq }
      if (next) store.put({ ...next, seq: existing.seq, rev: (existing.rev || 0) + 1, updatedAt: now })
      else store.delete(existing.seq)
    } else if (op.kind) {
      store.add({ ...op, rev: 0, createdAt: now, updatedAt: now })
    }
  })
  await announce()
  requestBackgroundSync()
}

async function opsWhere(pred) {
  return (await pendingOps()).filter(pred)
}

// ---- what can be queued ---------------------------------------------------------

// Where a pane was moved to while offline (reference / translation).
export function queuePaneVisit(url, { reference, translationId }, owner) {
  const body = { "pane[reference]": reference ?? "" }
  if (translationId) body["pane[translation_id]"] = translationId
  return upsert({ kind: "pane", key: `pane:${url}`, owner: owner || "guest", url, method: "PATCH", format: "form", body })
}

// A note autosave. baseRevision is the server revision the text was built on;
// it is kept from the first queued edit so the server can spot a conflict.
export function queueNote(url, text, { baseRevision, owner }) {
  const op = {
    kind: "notes", key: `notes:${url}`, owner, url, method: "PATCH", format: "form",
    body: { "pane[notes]": text, autosave: "1", base_revision: String(baseRevision ?? ""), edited_at: new Date().toISOString() }
  }
  return upsert(op, (existing) => ({ ...existing, body: { ...existing.body, "pane[notes]": text, edited_at: op.body.edited_at } }))
}

export async function pendingNote(url, owner) {
  return (await opsWhere((o) => o.key === `notes:${url}` && o.owner === owner))[0] || null
}

export function newTempId() {
  const rand = (globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`)
  return `tmp-${rand}`
}

// highlight: { verse_id, color, char_start, char_end, note }
export async function queueHighlightCreate(highlight, owner) {
  const id = newTempId()
  const record = { ...highlight, id, note: highlight.note || "" }
  await putHighlight(record)
  await upsert({
    kind: "highlight-create", key: `hl:${id}`, owner, url: "/highlights", method: "POST", format: "json",
    body: { highlight: { verse_id: record.verse_id, color: record.color, char_start: record.char_start, char_end: record.char_end, note: record.note } },
    tmpId: id
  })
  return record
}

// A temporary id that already synced is its server id now.
async function serverId(id) {
  if (!String(id).startsWith("tmp-")) return id
  const map = (await getMeta("idMap")) || {}
  return map[id] || id
}

export async function queueHighlightUpdate(rawId, fields, owner) {
  const id = await serverId(rawId)
  const existing = await getHighlight(id)
  if (existing) await putHighlight({ ...existing, ...fields })
  if (String(id).startsWith("tmp-")) {
    return upsert({ key: `hl:${id}`, owner }, (op) => ({ ...op, body: { highlight: { ...op.body.highlight, ...fields } } }))
  }
  return upsert({ kind: "highlight-update", key: `hlu:${id}`, owner, url: `/highlights/${id}`, method: "PATCH", format: "json", body: { highlight: fields } },
    (op) => ({ ...op, body: { highlight: { ...op.body.highlight, ...fields } } }))
}

export async function queueHighlightDelete(rawId, owner) {
  const id = await serverId(rawId)
  await deleteHighlight(id)
  if (String(id).startsWith("tmp-")) {
    // Never reached the server: forget the create.
    return upsert({ key: `hl:${id}`, owner }, () => null)
  }
  await removeOps((o) => o.key === `hlu:${id}`)
  return upsert({ kind: "highlight-delete", key: `hld:${id}`, owner, url: `/highlights/${id}`, method: "DELETE", format: "json" })
}

// Reading plan tick / untick. The opposite queued action cancels out.
export async function queuePlanDay(url, done, owner) {
  const key = `plan:${url}`
  const existing = (await opsWhere((o) => o.key === key && o.owner === owner))[0]
  if (existing && existing.done !== done) return upsert({ key, owner }, () => null)
  return upsert({ kind: "plan-day", key, owner, url, method: done ? "POST" : "DELETE", format: "form", body: {}, done })
}

async function removeOps(pred) {
  for (const op of await opsWhere(pred)) await del("outbox", op.seq).catch(() => {})
}

// ---- replay -----------------------------------------------------------------------

export function requestBackgroundSync() {
  try {
    navigator.serviceWorker?.ready?.then((reg) => reg.sync?.register("ps-outbox")).catch(() => {})
  } catch { /* not in a page, or no Background Sync */ }
}

let flushing = null

// Replay queued ops in order. Resolves to { sent, pending, stopped }.
export function flushOutbox() {
  if (flushing) return flushing
  const run = () => replay().finally(() => { flushing = null })
  flushing = navigator.locks?.request ? navigator.locks.request("ps-outbox", run) : run()
  return flushing
}

async function replay() {
  const owner = await getMeta("owner")
  const token = await getMeta("csrf")
  let sent = 0
  let stopped = null

  for (const op of await pendingOps()) {
    if (!owner || op.owner !== owner) continue
    const url = await resolveIds(op.url)
    let res
    try {
      res = await fetch(url, requestFor(op, token))
    } catch {
      stopped = "offline"
      break
    }

    if (res.status === 401 || res.redirected) { stopped = "signed-out"; break }
    const json = (res.headers.get("Content-Type") || "").includes("json")
    if (res.status === 422 && !json && op.kind !== "plan-day") { stopped = "stale-token"; break } // CSRF: reload refreshes it
    if (res.status >= 500 || res.status === 429) { stopped = "server"; break }

    if (res.ok || res.status === 404 || res.status === 422) {
      await settle(op, res, json).catch(() => {})
      sent++
    }
  }
  await announce()
  if (stopped === "signed-out") broadcast({ type: "sync-problem", message: "Sign in again to finish syncing your offline changes." })
  return { sent, pending: await pendingCount(), stopped }
}

function requestFor(op, token) {
  const headers = { "X-CSRF-Token": token || "", Accept: op.format === "json" ? "application/json" : "application/json, text/html" }
  let body
  if (op.format === "json" && op.body) {
    headers["Content-Type"] = "application/json"
    body = JSON.stringify(op.body)
  } else if (op.body) {
    body = new URLSearchParams(op.body)
  }
  return { method: op.method, headers, body, credentials: "same-origin", redirect: "follow" }
}

async function resolveIds(url) {
  const m = url.match(/tmp-[\w-]+/)
  if (!m) return url
  const map = (await getMeta("idMap")) || {}
  return map[m[0]] ? url.replace(m[0], map[m[0]]) : url
}

// The op reached the server: record what came back, then remove it — unless it
// changed while in flight (the reader kept typing), in which case it stays,
// rebased on the server's new revision.
async function settle(op, res, json) {
  const data = json ? await res.json().catch(() => ({})) : {}
  let rebase = null

  if (op.kind === "notes" && res.ok) {
    rebase = { base_revision: String(data.revision ?? "") }
    broadcast({ type: "notes-synced", url: op.url, notes: data.notes, revision: data.revision, conflict: !!data.conflict })
  } else if (op.kind === "highlight-create" && res.ok && data.id) {
    const map = (await getMeta("idMap")) || {}
    map[op.tmpId] = data.id
    await setMeta("idMap", map)
    const local = await getHighlight(op.tmpId)
    await deleteHighlight(op.tmpId)
    await putHighlight({ ...(local || op.body.highlight), id: data.id, color: data.color || local?.color, note: data.note ?? local?.note ?? "" })
    broadcast({ type: "highlight-id", tmp: op.tmpId, id: data.id })
  }

  const current = await get("outbox", op.seq).catch(() => null)
  if (!current) return
  if ((current.rev || 0) === (op.rev || 0)) {
    await del("outbox", op.seq)
  } else if (rebase) {
    await put("outbox", { ...current, body: { ...current.body, ...rebase } })
  } else {
    await del("outbox", op.seq)
  }
}
