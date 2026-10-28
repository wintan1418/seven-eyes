// JSON calls to /highlights with the CSRF token, shared by the verse action
// bar and the word highlighter. A 401 means a guest tried to save: we raise
// the "create an account" gate (auth:required) and report it so the caller
// can stop.
//
// With no connection a signed-in reader's highlight still "saves": it goes to
// the outbox (lib/offline/outbox.js) with a temporary id ("tmp-…") and into
// the offline highlight cache, and reaches the server when the network is
// back, where it gets its real id. Guests get the auth gate, as online.
import { queueHighlightCreate, queueHighlightUpdate, queueHighlightDelete } from "./offline/outbox"
import { putHighlight, deleteHighlight as forgetHighlight, getHighlight, getMeta } from "./offline/store"
import { owner, signedIn } from "./offline/page"

export function api(method, url, body, { keepalive = false } = {}) {
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  const opts = { method, keepalive, credentials: "same-origin", headers: { "X-CSRF-Token": token || "", Accept: "application/json" } }
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json"
    opts.body = JSON.stringify(body)
  }
  return fetch(url, opts)
}

function unauthorized(res) {
  if (res.status !== 401) return false
  window.dispatchEvent(new CustomEvent("auth:required"))
  return true
}

// No network: only an account can keep it (same rule as online).
function needsAccount() {
  if (signedIn()) return false
  window.dispatchEvent(new CustomEvent("auth:required"))
  return true
}

// A temporary id still waiting in the outbox (not yet given a real id).
async function pendingTempId(id) {
  if (!String(id).startsWith("tmp-")) return null
  const map = (await getMeta("idMap").catch(() => null)) || {}
  return map[id] ? null : id
}

async function realId(id) {
  if (!String(id).startsWith("tmp-")) return id
  const map = (await getMeta("idMap").catch(() => null)) || {}
  return map[id] || id
}

// { verse_id, color, char_start, char_end, note? } →
//   { ok: true, id, offline? } | { unauthorized: true } | { error }
export async function createHighlight(fields) {
  let res
  try {
    res = await api("POST", "/highlights", { highlight: fields })
  } catch {
    if (needsAccount()) return { unauthorized: true }
    const record = await queueHighlightCreate(fields, owner())
    return { ok: true, id: record.id, offline: true }
  }
  if (unauthorized(res)) return { unauthorized: true }
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    return { error: body.error ? `Not saved: ${body.error}` : "Highlight failed" }
  }
  const data = await res.json()
  putHighlight({ ...fields, id: data.id, color: data.color || fields.color, note: data.note || "" })
  return { ok: true, id: data.id }
}

// → the saved highlight ({ id, color, note }), { offline: true }, or null
export async function updateHighlight(rawId, fields, { keepalive = false } = {}) {
  if (await pendingTempId(rawId)) return queuedUpdate(rawId, fields)
  const id = await realId(rawId)
  let res
  try {
    res = await api("PATCH", `/highlights/${encodeURIComponent(id)}`, { highlight: fields }, { keepalive })
  } catch {
    return queuedUpdate(id, fields)
  }
  if (unauthorized(res) || !res.ok) return null
  const data = await res.json().catch(() => ({ id }))
  const cached = await getHighlight(id)
  if (cached) putHighlight({ ...cached, ...fields })
  return data
}

async function queuedUpdate(id, fields) {
  if (needsAccount()) return null
  await queueHighlightUpdate(id, fields, owner())
  return { id, ...fields, offline: true }
}

// → true when removed (or queued for removal)
export async function deleteHighlight(rawId) {
  if (await pendingTempId(rawId)) return queuedDelete(rawId)
  const id = await realId(rawId)
  let res
  try {
    res = await api("DELETE", `/highlights/${encodeURIComponent(id)}`)
  } catch {
    return queuedDelete(id)
  }
  if (unauthorized(res)) return false
  if (!res.ok && res.status !== 404) return false
  forgetHighlight(id)
  return true
}

async function queuedDelete(id) {
  if (needsAccount()) return false
  await queueHighlightDelete(id, owner())
  return true
}

// Highlight whole verses: [{ verseId, length }] → "ok" | "unauthorized" | "failed"
export async function highlightVerses(verses, color) {
  let failed = false
  for (const v of verses) {
    const result = await createHighlight({ verse_id: v.verseId, color, char_start: 0, char_end: v.length })
    if (result.unauthorized) return "unauthorized"
    if (!result.ok) failed = true
  }
  return failed ? "failed" : "ok"
}

// Remove highlights by id → "ok" | "unauthorized" | "failed"
export async function removeHighlights(ids) {
  if (!signedIn()) {
    // Online a guest has no highlights to remove; keep the old behaviour (gate).
    window.dispatchEvent(new CustomEvent("auth:required"))
    return "unauthorized"
  }
  let failed = false
  for (const id of ids) {
    if (!(await deleteHighlight(id))) failed = true
  }
  return failed ? "failed" : "ok"
}
