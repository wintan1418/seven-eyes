// The offline library: downloaded Bibles, the manifest (book list, reference
// aliases, icons), the reader's highlights, and who the data belongs to.
// Used by the page (Downloads page, Get ready for Sunday, sync) and by the
// service worker (rendering panes with no signal).
import { get, getAll, getAllByIndex, put, del, clear, transaction, getMeta, setMeta } from "./db"

export { getMeta, setMeta }

export const MANIFEST_URL = "/offline/bibles"

// ---- manifest -------------------------------------------------------------

export async function fetchManifest() {
  const res = await fetch(MANIFEST_URL, { credentials: "same-origin", cache: "no-cache", headers: { Accept: "application/json" } })
  if (!res.ok) throw new Error(`manifest ${res.status}`)
  const manifest = await res.json()
  await setMeta("manifest", manifest)
  return manifest
}

export const storedManifest = () => getMeta("manifest")

// ---- Bibles ---------------------------------------------------------------

export async function downloadedBibles() {
  try { return await getAll("bibles") } catch { return [] }
}

export async function downloadedBible(code) {
  try { return await get("bibles", code) } catch { return undefined }
}

// Download one translation into IndexedDB. onProgress(fraction 0..1).
// Reads the body as a stream so a phone on 3G sees the bar move.
export async function downloadBible(summary, { onProgress = () => {}, signal } = {}) {
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
    downloadedAt: new Date().toISOString()
  }
  await transaction([ "books", "bibles" ], (tx) => {
    const books = tx.objectStore("books")
    bundle.books.forEach((b) => books.put({ code: bundle.code, osis: b.osis, chapters: b.chapters }))
    tx.objectStore("bibles").put(record)
  })
  onProgress(1)
  return record
}

export async function removeBible(code) {
  await transaction([ "books", "bibles" ], (tx) => {
    tx.objectStore("books").delete(IDBKeyRange.bound([ code, "" ], [ code, "￿" ]))
    tx.objectStore("bibles").delete(code)
  })
}

export async function bookText(code, osis) {
  try { return await get("books", [ code, osis ]) } catch { return undefined }
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

export async function highlightsFor(verseIds) {
  const out = []
  for (const id of verseIds) {
    try { out.push(...await getAllByIndex("highlights", "verse_id", id)) } catch { /* none */ }
  }
  return out
}

export async function replaceHighlights(list) {
  await transaction([ "highlights" ], (tx) => {
    const store = tx.objectStore("highlights")
    store.clear()
    list.forEach((h) => store.put(h))
  })
}

export const putHighlight = (h) => put("highlights", h).catch(() => {})
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
}
