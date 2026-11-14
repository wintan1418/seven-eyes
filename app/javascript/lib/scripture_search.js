// Bible search on the device, ranked like the server's ScriptureSearch
// (app/services/scripture_search.rb) so a downloaded Bible answers the same
// way with no internet:
//
//   1. phrase  — the words side by side, as typed
//   2. all     — every word somewhere in the verse
//   3. partial — some of the words (more of them first)
//
// then in Bible order. Words match by a simple stem ("rain" finds "rained").
//
//   rankVerses(records, "dew rain", { order, books, limit })
//     → { words, hits: [{ osis, chapter, num, text, tier, matched, parts }], allCount, anyCount }
// `records` are downloaded book records ({ osis, chapters: [{ t, n? }] }),
// `order` maps osis → canonical position, `books` (optional Set) limits the
// search to those books. `parts` is the text split for highlighting:
// [{ text, mark }] — render each part as a text node (never as HTML).
import { keywords, stem } from "./offline/keyword_search.js"

const TIERS = { phrase: 0, all: 1, partial: 2 }

// keyword_search's stem, plus "enemies" → "enemy" (KJV plurals in -ies).
export function root(word) {
  const w = String(word).toLowerCase().replace(/’/g, "'")
  return stem(w.length > 4 && w.endsWith("ies") ? `${w.slice(0, -3)}y` : w)
}

export function queryWords(query) {
  return keywords(query).map((k) => ({ word: k.word, stem: root(k.word) }))
}

function normalise(text) {
  return ` ${String(text || "").toLowerCase().replace(/[’']/g, "").replace(/[^a-z]+/g, " ").trim()} `
}

export function markParts(text, stems) {
  const wanted = new Set(stems)
  const parts = []
  let last = 0
  for (const m of String(text).matchAll(/[A-Za-z’']+/g)) {
    if (!wanted.has(root(m[0]))) continue
    if (m.index > last) parts.push({ text: text.slice(last, m.index), mark: false })
    parts.push({ text: m[0], mark: true })
    last = m.index + m[0].length
  }
  if (last < text.length) parts.push({ text: text.slice(last), mark: false })
  return parts
}

export function rankVerses(records, query, { order = null, books = null, limit = 250 } = {}) {
  const words = queryWords(query)
  if (!words.length) return { words, hits: [], allCount: 0, anyCount: 0 }
  const stems = words.map((w) => w.stem)
  const prefix = stems.map((s) => s.slice(0, Math.max(3, s.length - 1)))
  const phrase = words.length > 1 ? normalise(query) : null

  const hits = []
  for (const record of records || []) {
    if (books && !books.has(record.osis)) continue
    const pos = order?.get(record.osis) ?? 999;
    (record.chapters || []).forEach((c, ci) => {
      if (!c?.t) return
      c.t.forEach((text, k) => {
        const lower = text.toLowerCase()
        if (!prefix.some((s) => lower.includes(s))) return // cheap prefilter
        const verseStems = new Set((lower.match(/[a-z’']+/g) || []).map(root))
        const matched = stems.filter((s) => verseStems.has(s)).length
        if (!matched) return
        const tier = phrase && normalise(text).includes(phrase) ? "phrase" : matched === stems.length ? "all" : "partial"
        hits.push({ osis: record.osis, chapter: ci + 1, num: c.n ? c.n[k] : k + 1, text, tier, matched, pos })
      })
    })
  }
  hits.sort((a, b) => TIERS[a.tier] - TIERS[b.tier] || b.matched - a.matched ||
    a.pos - b.pos || a.chapter - b.chapter || a.num - b.num)
  const allCount = hits.filter((h) => h.tier !== "partial").length
  return {
    words,
    allCount,
    anyCount: hits.length,
    hits: hits.slice(0, limit).map(({ pos, ...h }) => ({ ...h, parts: markParts(h.text, stems) }))
  }
}

// "dew and rain" / "dew, rain and dove" — the words as a reader typed them.
export function wordsLabel(words) {
  const list = words.map((w) => w.word)
  if (list.length < 2) return list.join("")
  return `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`
}
