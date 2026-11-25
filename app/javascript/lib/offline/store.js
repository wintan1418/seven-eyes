// The offline library: downloaded Bibles, the manifest (book list, reference
// aliases, icons), the reader's highlights, and who the data belongs to.
// Used by the page (Downloads page, Get ready for Sunday, sync) and by the
// service worker (rendering panes with no signal).
import { get, getAll, getAllByIndex, put, del, clear, transaction, getMeta, setMeta, openDb, promisify } from "./db"

export { getMeta, setMeta }

export const MANIFEST_URL = "/offline/bibles"

// ---- an in-memory copy for preach mode --------------------------------------
// Every Go live renders a passage from here; on a slow laptop each IndexedDB
// read is a round trip to the browser process that can wait behind the
// queue's own writes, so the manifest, the download list and the last few
// books are kept in memory. Stale-while-revalidate: a copy older than
// LIBRARY_FRESH_MS answers at once and is re-read in the background. Any
// download, removal or new manifest (in any tab or the worker) drops it.
const LIBRARY_FRESH_MS = 30_000
const BOOKS_KEPT = 6
const LIBRARY_CHANNEL = "ps-library"
let library = { manifest: null, bibles: null, books: new Map() }
let libraryChannel = null
let libraryGen = 0 // a read that started before a change mustn't store what it read

function forgetLibrary() {
  libraryGen++
  library = { manifest: null, bibles: null, books: new Map() }
}

// Drop the copy here and in every other tab / the worker.
export function libraryChanged() {
  forgetLibrary()
  try { (libraryChannel ||= new BroadcastChannel(LIBRARY_CHANNEL)).postMessage("changed") } catch { /* none */ }
}

try {
  libraryChannel = new BroadcastChannel(LIBRARY_CHANNEL)
  libraryChannel.onmessage = () => forgetLibrary()
} catch { /* no BroadcastChannel */ }

// { value, at } → value, refreshing a stale entry in the background.
function remembered(slot, read) {
  const entry = slot.get()
  if (entry && Date.now() - entry.at < LIBRARY_FRESH_MS) return Promise.resolve(entry.value)
  const gen = libraryGen
  const fresh = read().then((value) => { if (gen === libraryGen) slot.set({ value, at: Date.now() }); return value })
  if (!entry) return fresh
  fresh.catch(() => {})
  return Promise.resolve(entry.value)
}

// ---- manifest -------------------------------------------------------------

export async function fetchManifest() {
  const res = await fetch(MANIFEST_URL, { credentials: "same-origin", cache: "no-cache", headers: { Accept: "application/json" } })
  if (!res.ok) throw new Error(`manifest ${res.status}`)
  const manifest = await res.json()
  await setMeta("manifest", manifest)
  libraryChanged()
  return manifest
}

export const storedManifest = () => remembered(
  { get: () => library.manifest, set: (e) => { library.manifest = e } },
  () => getMeta("manifest"))

// ---- Bibles ---------------------------------------------------------------

export async function downloadedBibles() {
  try {
    return await remembered({ get: () => library.bibles, set: (e) => { library.bibles = e } }, () => getAll("bibles"))
  } catch { return [] }
}

export async function downloadedBible(code) {
  try { return await get("bibles", code) } catch { return undefined }
}

// Download one translation into IndexedDB. onProgress(fraction 0..1).
// Reads the body as a stream so a phone on 3G sees the bar move.
// One download per translation at a time: a second ask (the automatic KJV,
// Quick Present, the Offline Bibles page) joins the one running. Progress is
// also announced on the page as `offline:bible-download` { code, state:
// "progress" | "done" | "failed", fraction } so any screen can show it.
const inflight = new Map()

export function bibleDownloading(code) {
  return inflight.has(code)
}

export function downloadBible(summary, options = {}) {
  const running = inflight.get(summary.code)
  if (running) return running
  const notify = (state, fraction) => {
    try { options.onProgress?.(fraction) } catch { /* the caller's own */ }
    if (typeof window !== "undefined" && window.dispatchEvent) {
      window.dispatchEvent(new CustomEvent("offline:bible-download", { detail: { code: summary.code, state, fraction } }))
    }
  }
  const job = fetchBible(summary, { onProgress: (f) => notify("progress", f), signal: options.signal })
    .then((record) => { notify("done", 1); return record },
      (e) => { notify("failed", 0); throw e })
    .finally(() => inflight.delete(summary.code))
  inflight.set(summary.code, job)
  return job
}

async function fetchBible(summary, { onProgress = () => {}, signal } = {}) {
  const res = await fetch(summary.url, { credentials: "same-origin", signal, headers: { Accept: "application/json" } })
  if (!res.ok) throw new Error(`download ${res.status}`)

  let text
  if (res.body && typeof TextDecoder !== "undefined") {
    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    const parts = []
    let received = 0
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      received += value.byteLength
      parts.push(decoder.decode(value, { stream: true }))
      // The body arrives decompressed; `bytes` is the uncompressed size.
      onProgress(Math.min(0.95, received / (summary.bytes || summary.size || received)))
    }
    parts.push(decoder.decode())
    text = parts.join("")
  } else {
    text = await res.text()
  }

  const bundle = JSON.parse(text)
  const record = {
    code: bundle.code, id: bundle.id, name: bundle.name, display_name: bundle.display_name,
    vulgate: !!bundle.vulgate, version: bundle.version, size: summary.size, bytes: summary.bytes || text.length,
    books: bundle.books.length,
    downloadedAt: new Date().toISOString()
  }
  await transaction([ "books", "bibles" ], (tx) => {
    const books = tx.objectStore("books")
    bundle.books.forEach((b) => books.put({ code: bundle.code, osis: b.osis, chapters: b.chapters }))
    tx.objectStore("bibles").put(record)
  })
  libraryChanged()
  onProgress(1)
  return record
}

export async function removeBible(code) {
  await transaction([ "books", "bibles" ], (tx) => {
    tx.objectStore("books").delete(IDBKeyRange.bound([ code, "" ], [ code, "￿" ]))
    tx.objectStore("bibles").delete(code)
  })
  libraryChanged()
}

export async function bookText(code, osis) {
  const key = `${code}|${osis}`
  const kept = library.books.get(key)
  if (kept) { library.books.delete(key); library.books.set(key, kept); return kept } // most recent last
  const gen = libraryGen
  let record
  try { record = await get("books", [ code, osis ]) } catch { return undefined }
  if (record && gen === libraryGen) {
    library.books.set(key, record)
    while (library.books.size > BOOKS_KEPT) library.books.delete(library.books.keys().next().value)
  }
  return record
}

const bookRange = (code) => IDBKeyRange.bound([ code, "" ], [ code, "\uffff" ])

// Every book of one downloaded translation (the offline keyword search).
export async function allBookTexts(code) {
  try { return await getAll("books", bookRange(code)) } catch { return [] }
}

// How many books of a translation are on the device — "the whole Bible (66
// books)", not just the passage being read.
export async function bookCount(code) {
  try {
    const db = await openDb()
    return await promisify(db.transaction("books").objectStore("books").count(bookRange(code)))
  } catch { return 0 }
}

// Rough device usage for the Downloads page.
export async function storageEstimate() {
  try { return await navigator.storage?.estimate?.() } catch { return null }
}

// Ask the browser not to evict our downloads under storage pressure.
export async function requestPersistence() {
  try { return await navigator.storage?.persist?.() } catch { return false }
}

// ---- highlights -------------------------------------------------------------

// verse_id is always stored as a number: the page reads ids from data
// attributes (strings), the bundles carry numbers, and IndexedDB keys of
// different types never match.
const normalize = (h) => ({ ...h, verse_id: Number(h.verse_id) })

// One read for the whole passage (it was one per verse — 176 round trips for
// Psalm 119): every highlight between the lowest and highest verse id, then
// only those on these verses.
export async function highlightsFor(verseIds) {
  const ids = verseIds.map(Number).filter((n) => Number.isFinite(n))
  if (!ids.length) return []
  const wanted = new Set(ids)
  try {
    const range = IDBKeyRange.bound(Math.min(...ids), Math.max(...ids))
    return (await getAllByIndex("highlights", "verse_id", range)).filter((h) => wanted.has(Number(h.verse_id)))
  } catch { return [] }
}

export async function replaceHighlights(list) {
  await transaction([ "highlights" ], (tx) => {
    const store = tx.objectStore("highlights")
    store.clear()
    list.forEach((h) => store.put(normalize(h)))
  })
}

export const putHighlight = (h) => put("highlights", normalize(h)).catch(() => {})
export const deleteHighlight = (id) => del("highlights", id).catch(() => {})
export const getHighlight = (id) => get("highlights", id).catch(() => undefined)

export async function refreshHighlights() {
  const res = await fetch("/offline/highlights", { credentials: "same-origin", headers: { Accept: "application/json" } })
  if (!res.ok) return false
  const { highlights } = await res.json()
  // Keep highlights made offline that haven't reached the server yet.
  const pending = (await getAll("highlights").catch(() => [])).filter((h) => String(h.id).startsWith("tmp-"))
  await replaceHighlights([ ...highlights, ...pending ])
  await setMeta("highlightsAt", Date.now())
  return true
}

// ---- personal data ------------------------------------------------------------

// Forget everything that belongs to the signed-in reader (highlights, queued
// writes). Downloaded Bibles are public text and stay.
export async function clearPersonal({ outbox = true } = {}) {
  await clear("highlights").catch(() => {})
  if (outbox) await clear("outbox").catch(() => {})
  await setMeta("lastStudyUrl", null).catch(() => {})
  await setMeta("highlightsAt", 0).catch(() => {})
  await setMeta("quickPresent", null).catch(() => {}) // lib/offline/ready.js
  await setMeta("offlinePreparedAt", null).catch(() => {})
}
