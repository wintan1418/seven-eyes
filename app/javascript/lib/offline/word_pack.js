// The offline word pack (RootWordPack on the server): the KJV's Strong's tags
// for every verse and the lexicon they name, kept in IndexedDB so root-word
// projection works with no signal. Books go into the "books" store under the
// pseudo-translation code below (never listed as a downloaded Bible); the
// lexicon and the pack's version sit in "meta".
import { getMeta, setMeta, get, transaction } from "./db"
import { quickFetch, isNetworkSlow } from "./network"
import { decodeVerse } from "../root_words"

export const PACK_CODE = "~strongs"
const META_KEY = "rootWordPack"
const LEXICON_KEY = "rootWordLexicon"
const INFO_URL = "/root_words/pack/info"
const VERSE_TIMEOUT_MS = 2000

let lexicon = null // in memory once read: { G25: [lemma, translit, pron, def, kjv, deriv, n] }
let fields = null

export async function packInfo() {
  try { return (await getMeta(META_KEY)) || null } catch { return null }
}

// Download (or refresh) the pack. Resolves to the stored info, or null.
export async function downloadWordPack({ signal } = {}) {
  const info = await (await fetch(INFO_URL, { credentials: "same-origin", signal, headers: { Accept: "application/json" } })).json()
  const have = await packInfo()
  if (have?.version === info.version) return have
  const res = await fetch(info.url, { credentials: "same-origin", signal, headers: { Accept: "application/json" } })
  if (!res.ok) throw new Error(`word pack ${res.status}`)
  const pack = await res.json()
  await transaction([ "books" ], (tx) => {
    const books = tx.objectStore("books")
    pack.books.forEach((b) => books.put({ code: PACK_CODE, osis: b.osis, prefix: b.prefix, chapters: b.chapters }))
  })
  await setMeta(LEXICON_KEY, { fields: pack.fields, entries: pack.lexicon })
  const stored = { version: pack.version, size: info.size, translation: pack.translation, downloadedAt: new Date().toISOString() }
  await setMeta(META_KEY, stored)
  lexicon = pack.lexicon
  fields = pack.fields
  return stored
}

// Make sure the pack is on the device, quietly: online, not on Data Saver.
let ensuring = null
export function ensureWordPack() {
  if (ensuring) return ensuring
  if (navigator.onLine === false || isNetworkSlow() || navigator.connection?.saveData) return Promise.resolve(null)
  ensuring = downloadWordPack().catch(() => null).finally(() => { ensuring = null })
  return ensuring
}

async function loadLexicon() {
  if (lexicon) return lexicon
  const stored = await getMeta(LEXICON_KEY).catch(() => null)
  if (!stored) return null
  lexicon = stored.entries
  fields = stored.fields
  return lexicon
}

function entryFrom(strongs, row) {
  if (!row) return null
  const e = { s: strongs }
  ;(fields || []).forEach((f, i) => { e[f] = row[i] ?? "" })
  e.n = Number(e.n) || 0
  return e
}

// A verse from the device: { tokens, entries, source: "device" } or null.
export async function localVerse(osis, chapter, verse) {
  try {
    const book = await get("books", [ PACK_CODE, osis ])
    const encoded = book?.chapters?.[chapter - 1]?.[verse - 1]
    if (!encoded) return null
    const lex = await loadLexicon()
    const tokens = decodeVerse(encoded, book.prefix || "G")
    const entries = {}
    tokens.forEach((t) => { if (t.s && !entries[t.s]) entries[t.s] = entryFrom(t.s, lex?.[t.s]) })
    return { tokens, entries, source: "device" }
  } catch { return null }
}

// The verse's root words: the device first, then (briefly) the server.
export async function verseRootWords(osis, chapter, verse) {
  const local = await localVerse(osis, chapter, verse)
  if (local) return local
  try {
    const url = `/root_words/${encodeURIComponent(osis)}/${chapter}/${verse}`
    const { res, body } = await quickFetch(url, { headers: { Accept: "application/json" } }, { timeoutMs: VERSE_TIMEOUT_MS, read: "json" })
    if (!res.ok || !body?.ok) return null
    return { tokens: body.tokens || [], entries: body.entries || {}, text: body.text, source: "server" }
  } catch { return null }
}
