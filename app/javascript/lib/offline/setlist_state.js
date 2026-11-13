// The preach queue's state, worked out on the device — no DOM, no IndexedDB,
// so node can test it (test/javascript/setlist_state_test.mjs).
//
// The queue is local-first: the operator's copy changes at once and each
// change is replayed to the server through the outbox (setlist-create /
// -update / -destroy / -order ops, see outbox.js). An item is
//   { cid, id, kind, reference, label, title, body, arrangement, image, stanzas }
// where `cid` is the id the device gave it ("tmp-…", or "srv-<id>" for an
// item that was made on the server) and `id` the server's, once known.
//
//   splitReferences(raw, parse)   "Jn 11:35, Rev 12:10; Jer 10:10-11" → one entry each
//   mergeQueue({ server, serverTime, local, ops })   what to show after a load
//   applyOps(items, ops)          replay pending changes on top of a list (idempotent)
//   moveItem(items, from, to)     reorder
//   queueKey(item)                "the same thing" for de-duplication
//   nextUp(items, liveCid)        the one-glance "next" item

export const ITEM_FIELDS = [ "kind", "reference", "label", "title", "body", "arrangement", "image", "stanzas" ]

export function fromServer(row) {
  return {
    cid: row.client_id || `srv-${row.id}`, id: row.id ?? null,
    kind: row.kind, reference: row.reference || null, label: row.label || row.reference || row.title || "",
    title: row.title || null, body: row.body || null, arrangement: row.arrangement || null,
    image: row.image || null, stanzas: row.stanzas || 0
  }
}

// The key the server knows an item by: its id when known, else the device's.
export const serverKey = (item) => (item.id != null ? String(item.id) : item.cid)

// ---- several references in one go -------------------------------------------------

const REASONS = {
  unknown_book: (raw) => `“${raw}” — no book by that name`,
  bad_chapter: (raw, p) => `“${raw}” — ${p.bookName} has ${p.chapterCount} chapter${p.chapterCount === 1 ? "" : "s"}`,
  bad_verse: (raw) => `“${raw}” — that verse number doesn't look right`
}

// Split on commas, semicolons and new lines; each piece is its own item, a
// range ("Jer 10:10-11") stays one. A bare number after a reference means
// another verse of the same chapter ("Jn 3:16, 18" → John 3:18).
// `parse` is reference_parser's makeParser(canon) (null: not loaded yet — the
// pieces are then queued as typed and the server reads them).
export function splitReferences(raw, parse, labelOf = defaultLabel) {
  const pieces = String(raw ?? "").split(/[\n,;]+/).map((s) => s.trim()).filter(Boolean)
  const items = []
  const errors = []
  let last = null
  for (const piece of pieces) {
    let text = piece
    if (last && /^\d+(?:\s*[-–]\s*\d+)?$/.test(piece)) text = `${last.bookName} ${last.chapter}:${piece.replace(/\s+/g, "")}`
    if (!parse) { items.push({ reference: text, label: text }); continue }
    const p = parse(text)
    if (!p.valid) {
      if (p.error !== "blank") errors.push({ raw: piece, message: (REASONS[p.error] || REASONS.unknown_book)(piece, p) })
      continue
    }
    last = p
    items.push({ reference: text, label: labelOf(p), parsed: p })
  }
  return { items, errors }
}

function defaultLabel(p) {
  let base = `${p.bookName} ${p.chapter}`
  if (p.verseStart == null) return p.chapterEnd > p.chapter ? `${base}-${p.chapterEnd}` : base
  base += `:${p.verseStart}`
  if (p.openEnded) return `${base}ff`
  if (p.chapterEnd > p.chapter) return `${base}-${p.chapterEnd}:${p.verseEnd}`
  return p.verseEnd != null && p.verseEnd !== p.verseStart ? `${base}-${p.verseEnd}` : base
}

// ---- pending changes on top of a list ----------------------------------------------

const sameItem = (a, b) => a.cid === b.cid || (a.id != null && b.id != null && String(a.id) === String(b.id))

// `ops` are outbox records carrying op.setlist = { action, cid, item, fields,
// position, order }, oldest first. Replaying one twice changes nothing.
export function applyOps(items, ops) {
  let list = items.map((i) => ({ ...i }))
  for (const op of ops) {
    const s = op.setlist || op
    if (s.action === "create") {
      const existing = list.find((i) => i.cid === s.cid)
      if (existing) continue
      const at = Math.max(0, Math.min(s.position ?? list.length, list.length))
      list.splice(at, 0, { ...s.item, cid: s.cid, id: null })
    } else if (s.action === "update") {
      list = list.map((i) => (i.cid === s.cid ? { ...i, ...s.fields } : i))
    } else if (s.action === "destroy") {
      list = list.filter((i) => i.cid !== s.cid && !(s.id != null && String(i.id) === String(s.id)))
    } else if (s.action === "order") {
      list = arrange(list, s.order || [])
    }
  }
  return list
}

// Put `list` in the order `keys` names (server ids or cids); the rest keep
// their relative order after them — SetlistItem.arrange! on the server.
export function arrange(list, keys) {
  const rank = new Map()
  keys.forEach((k, i) => { if (!rank.has(String(k))) rank.set(String(k), i) })
  const at = (item) => {
    if (item.id != null && rank.has(String(item.id))) return rank.get(String(item.id))
    return rank.has(item.cid) ? rank.get(item.cid) : null
  }
  return list.map((item, i) => ({ item, i, r: at(item) }))
    .sort((a, b) => (a.r == null) - (b.r == null) || (a.r ?? 0) - (b.r ?? 0) || a.i - b.i)
    .map((x) => x.item)
}

// What the queue shows after a page load:
//   server      the items the page was rendered with (or fetched)
//   serverTime  when the server produced them (ms)
//   local       the device's copy { items, syncedAt, failed } (or null)
//   ops         this study's pending outbox ops
// The newer of the server list and the device's last synced copy is the base
// (a page saved for offline use can be older than what this device has since
// synced); pending ops go on top; items whose save failed stay, marked, so a
// retry is one tap — nothing the operator added ever silently disappears.
export function mergeQueue({ server, serverTime = 0, local = null, ops = [] }) {
  const serverItems = (server || []).map(fromServer)
  const useLocal = local?.items && (local.syncedAt || 0) > (serverTime || 0)
  let items = applyOps(useLocal ? local.items : serverItems, ops)
  // Server ids learnt by the device carry over onto a local base.
  if (!useLocal) {
    const known = new Map((local?.items || []).map((i) => [ i.cid, i ]))
    items = items.map((i) => (i.id == null && known.get(i.cid)?.id != null ? { ...i, id: known.get(i.cid).id } : i))
  }
  const failed = local?.failed || {}
  ;(local?.items || []).forEach((item, index) => {
    if (failed[item.cid] && !items.some((i) => sameItem(i, item))) items.splice(Math.min(index, items.length), 0, { ...item })
  })
  return items
}

export function moveItem(items, from, to) {
  const list = [ ...items ]
  if (from < 0 || from >= list.length) return list
  const [ item ] = list.splice(from, 1)
  list.splice(Math.max(0, Math.min(to, list.length)), 0, item)
  return list
}

// Two queue entries are "the same" for de-duplication (auto-adding what was
// projected): scripture by its label, songs/thoughts by title.
export function queueKey(item) {
  if (!item) return ""
  if (item.kind === "scripture") return `s:${String(item.label || item.reference || "").toLowerCase().replace(/[–—]/g, "-").replace(/\s+/g, " ").trim()}`
  return `${item.kind}:${String(item.title || item.body || "").toLowerCase().trim()}`
}

// The item after the one that last went live from the queue (else the first).
export function nextUp(items, liveCid) {
  if (!items.length) return null
  const idx = liveCid ? items.findIndex((i) => i.cid === liveCid) : -1
  return items[idx + 1] || null
}
