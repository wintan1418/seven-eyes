// Song bank collections, worked out on the device — no DOM, so node can test
// it (test/javascript/slides_test.mjs). A collection is { id, name, titles };
// songs belong by title, any case (hymnal songs as well as the account's own).
const key = (t) => String(t || "").trim().toLowerCase()

export function inCollection(collection, song) {
  const k = key(song?.title)
  return !!k && (collection?.titles || []).some((t) => key(t) === k)
}

export function toggleTitle(titles, title) {
  const k = key(title)
  const list = titles || []
  return list.some((t) => key(t) === k) ? list.filter((t) => key(t) !== k) : [ ...list, title ]
}

// Unsynced outbox ops (PUT / DELETE /song_collections/:id) on top of a list.
export function applyCollectionOps(list, ops) {
  let out = (list || []).map((c) => ({ ...c, titles: [ ...(c.titles || []) ] }))
  for (const op of ops || []) {
    const id = decodeURIComponent(String(op.url || "").split("/").pop())
    if (op.method === "DELETE") { out = out.filter((c) => c.id !== id); continue }
    const body = op.body?.song_collection
    if (!body) continue
    const next = { id, name: body.name, titles: body.titles || [] }
    const i = out.findIndex((c) => c.id === id)
    if (i >= 0) out[i] = next
    else out.push(next)
  }
  return out
}
