// Where presentation pages and seminar pictures live: a small IndexedDB
// database of its own ("ps-slides"), on this device only. Nothing is uploaded —
// a 40-page PDF costs no hosting and no data, and it projects with no signal.
// The operator, projector (?output=1) and stage (?stage=1) windows are the
// same origin on the same computer, so all three read the same pages.
//
//   decks:  { key, title, pages, source, file, bytes, createdAt }
//   pages:  { deck, n, blob, thumb, w, h }        key [deck, n] (n from 1)
//   images: { key, blob, thumb }                  seminar pictures ("local:<key>" in a slide)
const DB_NAME = "ps-slides"
const DB_VERSION = 1

let opening = null

function open() {
  if (opening) return opening
  opening = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains("decks")) db.createObjectStore("decks", { keyPath: "key" })
      if (!db.objectStoreNames.contains("pages")) db.createObjectStore("pages", { keyPath: [ "deck", "n" ] })
      if (!db.objectStoreNames.contains("images")) db.createObjectStore("images", { keyPath: "key" })
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => { opening = null; reject(req.error) }
  })
  return opening
}

function done(req) {
  return new Promise((resolve, reject) => { req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error) })
}

async function store(name, mode = "readonly") {
  const db = await open()
  return db.transaction(name, mode).objectStore(name)
}

export function newKey(prefix = "deck") {
  const rand = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`
  return `${prefix}-${rand}`
}

// Save a whole deck: pages = [{ blob, thumb, w, h }] in order.
export async function saveDeck(deck, pages) {
  const db = await open()
  await new Promise((resolve, reject) => {
    const tx = db.transaction([ "decks", "pages" ], "readwrite")
    const pageStore = tx.objectStore("pages")
    pageStore.delete(IDBKeyRange.bound([ deck.key, 0 ], [ deck.key, Infinity ]))
    pages.forEach((p, i) => pageStore.put({ deck: deck.key, n: i + 1, blob: p.blob, thumb: p.thumb || null, w: p.w, h: p.h }))
    const bytes = pages.reduce((sum, p) => sum + (p.blob?.size || 0) + (p.thumb?.size || 0), 0)
    tx.objectStore("decks").put({ ...deck, pages: pages.length, bytes, createdAt: Date.now() })
    tx.oncomplete = resolve
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error || new Error("aborted"))
  })
}

export async function getDeck(key) {
  try { return (await done((await store("decks")).get(key))) || null } catch { return null }
}

export async function listDecks() {
  try { return (await done((await store("decks")).getAll())) || [] } catch { return [] }
}

export async function removeDeck(key) {
  const db = await open()
  await new Promise((resolve, reject) => {
    const tx = db.transaction([ "decks", "pages" ], "readwrite")
    tx.objectStore("pages").delete(IDBKeyRange.bound([ key, 0 ], [ key, Infinity ]))
    tx.objectStore("decks").delete(key)
    tx.oncomplete = resolve
    tx.onerror = () => reject(tx.error)
  })
  forget(`${key}|`)
}

export async function saveImage(key, blob, thumb) {
  await done((await store("images", "readwrite")).put({ key, blob, thumb: thumb || null }))
}

// Object URLs, made once per window and reused (a page shown twice doesn't
// read IndexedDB twice).
const urls = new Map()

function forget(prefix) {
  for (const [ k, u ] of urls) if (k.startsWith(prefix)) { URL.revokeObjectURL(u); urls.delete(k) }
}

async function urlFor(cacheKey, read) {
  if (urls.has(cacheKey)) return urls.get(cacheKey)
  let blob = null
  try { blob = await read() } catch { blob = null }
  if (!blob) return null
  const url = URL.createObjectURL(blob)
  urls.set(cacheKey, url)
  return url
}

export function pageUrl(deck, n, { thumb = false } = {}) {
  return urlFor(`${deck}|${n}|${thumb ? "t" : "f"}`, async () => {
    const rec = await done((await store("pages")).get([ deck, n ]))
    return thumb ? (rec?.thumb || rec?.blob) : rec?.blob
  })
}

// "local:<key>" (a seminar picture) → an object URL, or null if it isn't here.
export function imageUrl(ref, { thumb = false } = {}) {
  const key = String(ref || "").replace(/^local:/, "")
  if (!key) return Promise.resolve(null)
  return urlFor(`img|${key}|${thumb ? "t" : "f"}`, async () => {
    const rec = await done((await store("images")).get(key))
    return thumb ? (rec?.thumb || rec?.blob) : rec?.blob
  })
}

// How much this device holds and may hold (for the import dialog).
export async function storageEstimate() {
  try { return await navigator.storage?.estimate?.() } catch { return null }
}

export async function persistStorage() {
  try { return await navigator.storage?.persist?.() } catch { return false }
}
