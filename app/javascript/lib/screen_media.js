// The church's own pictures for the projector — a logo, a background picture
// and a looping background video — kept on THIS device in IndexedDB, so they
// work with no connection and never touch our servers. A separate little
// database (not lib/offline/db) so its version never collides with the
// offline Bible store. The operator, projector and stage windows share it
// (same origin); after a change the operator tells the others over the
// preach BroadcastChannel and they re-read.
const DB_NAME = "ps-screen-media"
const STORE = "files"
export const SLOTS = [ "logo", "image", "video" ]
export const LIMITS = { logo: 8 * 1024 * 1024, image: 25 * 1024 * 1024, video: 300 * 1024 * 1024 }

let dbPromise = null

function open() {
  if (typeof indexedDB === "undefined") return Promise.reject(new Error("no IndexedDB"))
  dbPromise ||= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => { dbPromise = null; reject(req.error) }
  })
  return dbPromise
}

function tx(mode, run) {
  return open().then((db) => new Promise((resolve, reject) => {
    const t = db.transaction(STORE, mode)
    const request = run(t.objectStore(STORE))
    t.oncomplete = () => resolve(request ? request.result : undefined)
    t.onerror = () => reject(t.error)
    t.onabort = () => reject(t.error)
  }))
}

// The file itself (Blob) and when it was saved, or null.
export function getMedia(slot) {
  return tx("readonly", (s) => s.get(slot)).then((r) => r || null, () => null)
}

// Throws a readable Error when the file is the wrong kind or too big.
export async function putMedia(slot, file) {
  if (!SLOTS.includes(slot) || !file) throw new Error("Nothing to save")
  const kind = slot === "video" ? "video/" : "image/"
  if (!String(file.type || "").startsWith(kind)) {
    throw new Error(slot === "video" ? "Choose a video file (MP4 or WebM)" : "Choose a picture (JPG, PNG, WebP or SVG)")
  }
  if (file.size > LIMITS[slot]) {
    throw new Error(`That file is too big — keep it under ${Math.round(LIMITS[slot] / 1024 / 1024)} MB`)
  }
  const record = { blob: file, type: file.type, name: file.name || slot, savedAt: Date.now() }
  await tx("readwrite", (s) => s.put(record, slot))
  return record
}

export function deleteMedia(slot) {
  return tx("readwrite", (s) => s.delete(slot)).catch(() => {})
}

// One object URL per slot per window, swapped when the file changes.
const urls = new Map()

export async function mediaUrl(slot) {
  const rec = await getMedia(slot)
  const held = urls.get(slot)
  if (!rec) {
    if (held) { URL.revokeObjectURL(held.url); urls.delete(slot) }
    return null
  }
  if (held && held.savedAt === rec.savedAt) return held.url
  if (held) URL.revokeObjectURL(held.url)
  const url = URL.createObjectURL(rec.blob)
  urls.set(slot, { url, savedAt: rec.savedAt })
  return url
}
