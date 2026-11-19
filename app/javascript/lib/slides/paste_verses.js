// "Paste your own" verses: the pastor copies the passage they preach from
// (NKJV, NIV, AMP…) out of their own Bible app and pastes it here; we tidy the
// paste into verses for a scripture slide. The words stay in that one queue
// item (a scripture_set whose ref is marked `own`) — never in a Translation,
// never searchable, never shared. No DOM, so node tests it
// (test/javascript/paste_verses_test.mjs).
//
//   cleanPaste(raw)                 → { text, reference, version }  (junk off, what the paste says it is)
//   splitPasted(raw, { start, parse }) → { verses: [{ c, n, text }], numbered, reference, version }
//   checkSize(verses)               → null or a friendly "too long" message
//
// Formats it reads: "16 For God… 17 For God…" (Bible Gateway), "16. …",
// "[16] …", superscripts "¹⁶For God…", one verse per line ("16 For…"),
// "John 3:16 For God…" / "Jhn 3:16 - For…" per line (Blue Letter Bible), and
// YouVersion's share text (“…” John 3:16 NKJV https://bible.com/…), which has
// no verse numbers at all — then the words become slides by sentences.

export const MAX_VERSES = 200
export const MAX_BYTES = 40_000
export const VERSION_CHOICES = [ "NKJV", "NIV", "AMP", "AMPC", "ESV", "NLT", "MSG" ]
export const MAX_VERSION = 12
// Unnumbered text is cut into slides of about this many characters, at sentence ends.
const CHUNK = 260

const SUPERSCRIPTS = { "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9" }
const INVISIBLE = /[​-‏‪-‮⁠-⁩﻿­]/g
const VERSION_NAMES = [
  [ /new king james/i, "NKJV" ], [ /amplified bible,? classic/i, "AMPC" ], [ /amplified/i, "AMP" ],
  [ /new international reader/i, "NIRV" ], [ /new international/i, "NIV" ], [ /english standard/i, "ESV" ],
  [ /new living/i, "NLT" ], [ /the message/i, "MSG" ], [ /new american standard/i, "NASB" ],
  [ /christian standard/i, "CSB" ], [ /good news/i, "GNT" ], [ /the passion translation/i, "TPT" ],
  [ /king james/i, "KJV" ]
]
// "John 3:16", "1 Cor 13:4-7", "Jhn 3:16", "Song of Solomon 2:1" — a reference at the start of a line.
const BOOK = "(?:[1-3]\\s?|I{1,3}\\s)?[A-Za-z][A-Za-z.]*(?:\\s(?:of\\s)?[A-Za-z][A-Za-z.]*){0,2}"
const REF = `${BOOK}\\s?\\d{1,3}(?::\\d{1,3}(?:\\s?[-–—]\\s?\\d{1,3}(?::\\d{1,3})?)?)?`
const CODE = "[A-Z][A-Z0-9]{1,5}"
const HEADER_RE = new RegExp(`^(${REF})\\s*(?:[(\\[]?(${CODE})[)\\]]?|(?:-|–|—)?\\s*([A-Z][A-Za-z ]+(?:Version|Bible|Translation|Message)[A-Za-z ,]*?)(?:\\s*\\((${CODE})\\))?)?\\s*$`)
const TRAILER_RE = new RegExp(`[\\s“”"]*(${REF})\\s+(${CODE})\\s*$`)
const LINE_REF_RE = new RegExp(`^(${BOOK})\\.?\\s?(\\d{1,3}):(\\d{1,3})\\s*[-–—:.]?\\s+(?=\\S)`)
const JUNK_LINE = [
  /copyright|©|\(c\)\s*\d{4}|all rights reserved|used by permission|scripture (?:quotations?|taken)|^\s*holy bible\b|®|™/i,
  /^\s*(?:read full chapter|read more|show more|open in app|see more|share|copy|bookmark|highlight|compare|audio bible)\s*$/i,
  /^\s*(?:\d+\s+)?(?:footnotes?|cross references?)\s*:?\s*$/i,
  /\b(?:bible\.com|biblegateway\.com|blueletterbible\.org|youversion|bible app)\b/i
]

export function versionFromName(text) {
  const hit = VERSION_NAMES.find(([ re ]) => re.test(String(text || "")))
  return hit ? hit[1] : null
}

export function cleanVersion(raw) {
  return String(raw ?? "").replace(INVISIBLE, "").replace(/[^\p{L}\p{N} +.\-]/gu, "").trim().toUpperCase().slice(0, MAX_VERSION)
}

// The paste with what Bible apps add around the words taken off, plus the
// reference / version the paste names (to fill the form in for the pastor).
export function cleanPaste(raw) {
  let text = String(raw ?? "").replace(INVISIBLE, "").replace(/\r\n?/g, "\n").replace(/ /g, " ")
  let reference = null
  let version = null
  const note = (ref, code, name) => {
    if (ref && !reference) reference = ref.replace(/\s+/g, " ").replace(/\s?[–—]\s?/g, "-").trim()
    const v = code || versionFromName(name)
    if (v && !version) version = v
  }
  // Bible Gateway's footnotes / cross references sections come last: drop them whole.
  text = text.replace(/\n\s*(?:footnotes?|cross references?)\s*:?\s*\n[\s\S]*$/i, "\n")
  text = text.replace(/https?:\/\/\S+|www\.\S+|\b(?:bible\.com|biblegateway\.com)\/\S*/gi, " ")

  const lines = text.split("\n").map((l) => l.replace(/[ \t]+/g, " ").trim())
  const kept = []
  lines.forEach((line) => {
    if (!line) { kept.push(""); return }
    const versionLine = line.match(/^(.*?(?:version|bible|translation|the message)[^()]*?)\s*(?:\((\w{2,6})\))?\.?$/i)
    if (JUNK_LINE.some((re) => re.test(line))) { note(null, null, line); return }
    const header = line.match(HEADER_RE)
    if (header && (header[2] || header[3] || !/\d\s+\S/.test(line.replace(/^\d\s/, "")))) {
      // "John 3:16-18 NKJV", "John 3:16-18 New King James Version", or just "John 3:16-18".
      note(header[1], header[2] || header[4], header[3])
      return
    }
    if (versionLine && line.length < 70 && !/\d/.test(line) && versionFromName(line)) { note(null, versionLine[2], line); return }
    // YouVersion: “For God so loved…” John 3:16 NKJV — words, then the reference and version.
    const trailer = line.match(TRAILER_RE)
    if (trailer && trailer.index > 0) {
      note(trailer[1], trailer[2])
      const quoted = /^\s*[”"]/.test(trailer[0]) || /[”"]$/.test(line.slice(0, trailer.index).trim())
      line = line.slice(0, trailer.index).trim()
      if (quoted && /^[“"]/.test(line)) line = line.replace(/^[“"]/, "").replace(/[”"]$/, "").trim()
    }
    kept.push(line)
  })
  text = kept.join("\n")
  // Bible Gateway marks: footnotes "only[a] begotten", cross references "life.(A)" —
  // always stuck to the word before. AMP's own [brackets] follow a space, so they stay.
  text = text.replace(/(?<=[^\s[(])\[[a-z]{1,2}\]/g, "").replace(/(?<=[^\s[(])\([A-Z]{1,3}\)/g, "")
  text = text.replace(/\n{3,}/g, "\n\n").trim()
  return { text, reference, version: version ? cleanVersion(version) : null }
}

// Every place a verse number might start: [16], ¹⁶, "16 ", "16. ", "16For", or a
// line that starts "John 3:16 …". Each is { index, end, n, c? }.
function candidates(text) {
  const out = []
  const re = /\[(\d{1,3})\]\s*|⟦(\d{1,3})⟧\s*|(?<=^|[\s"“”'‘’.,;:!?)\]—–-])(\d{1,3})(?:[.:)]\s+|\s+(?=[^\s\d])|(?=[A-Z“"‘'[(]))/gm
  for (const m of text.matchAll(re)) {
    const lineStart = m.index === 0 || /\n\s*$/.test(text.slice(Math.max(0, m.index - 4), m.index))
    const after = text[m.index + m[0].length] || ""
    // Strong: [16], ¹⁶, at a line's start, or followed by a capital / quote.
    const strong = !m[3] || lineStart || /[A-Z“"‘'[(]/.test(after)
    out.push({ index: m.index, end: m.index + m[0].length, n: Number(m[1] || m[2] || m[3]), lineStart, strong })
  }
  return out
}

// Turn per-line references ("John 3:16 For God…") into plain markers and
// superscripts into ⟦16⟧, so one pass can find every number.
function markLines(text) {
  const lines = text.split("\n").map((line) => {
    const m = line.match(LINE_REF_RE)
    if (!m || !/[A-Za-z]{2}/.test(m[1])) return line
    return `⟦${Number(m[3])}⟧${line.slice(m[0].length)}`
  })
  let out = lines.join("\n")
  out = out.replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹]+/g, (s) => ` ⟦${[ ...s ].map((ch) => SUPERSCRIPTS[ch]).join("")}⟧`)
  return out
}

// Pick the verse numbers that make a run (16, 17, 18…); a number in the words
// ("forty days", "40 days") rarely lands on the next expected verse. A new
// chapter restarts at 1 — Bible Gateway prints the chapter number there instead.
function pickRun(text, cands, start) {
  const run = []
  let c = start?.c ?? null
  let expect = start?.n ?? null
  for (const cand of cands) {
    if (!run.length) {
      // The first number opens the words (a heading line may come before it).
      const lead = text.slice(0, cand.index).trim()
      if (!(lead.length === 0 || (cand.lineStart && lead.length <= 120))) continue
      if (expect != null) {
        const ok = cand.n === expect || (expect === 1 && c != null && cand.n === c)
        if (ok) { run.push({ ...cand, n: expect, c }); expect++ }
        continue
      }
      if (cand.n >= 1 && cand.n <= 176) { run.push({ ...cand, c }); expect = cand.n + 1 }
      continue
    }
    if (cand.index < run[run.length - 1].end) continue
    if (cand.n === expect) { run.push({ ...cand, c }); expect++ } else if (cand.strong && (cand.n === 1 || (c != null && cand.n === c + 1))) {
      // a new chapter
      if (c != null) c++
      run.push({ ...cand, n: 1, c })
      expect = 2
    }
  }
  return run
}

function tidy(words) {
  return words.replace(/\s+/g, " ").replace(/\s+([,.;:!?])/g, "$1").trim()
}

// Bible Gateway section headings ("The New Birth") between verses: short, no
// end punctuation, on their own line just before a verse number.
function dropHeading(words) {
  const lines = words.split("\n").map((l) => l.trim()).filter(Boolean)
  while (lines.length > 1) {
    const last = lines[lines.length - 1]
    if (last.length < 70 && !/[.,;:!?”’"')\]]$/.test(last) && /^[A-Z]/.test(last)) lines.pop()
    else break
  }
  return lines.join("\n")
}

export function chunkSentences(text, size = CHUNK) {
  const sentences = tidy(text).match(/[^.!?]+(?:[.!?]+[”’"')\]]*|$)\s*/g) || []
  const chunks = []
  let cur = ""
  sentences.map((s) => s.trim()).filter(Boolean).forEach((s) => {
    if (cur && (cur.length + s.length + 1 > size)) { chunks.push(cur); cur = "" }
    cur = cur ? `${cur} ${s}` : s
  })
  if (cur) chunks.push(cur)
  // A very long sentence alone is cut at a comma or space near the size.
  return chunks.flatMap((ch) => splitLong(ch, size * 2))
}

function splitLong(text, max) {
  const out = []
  let rest = text
  while (rest.length > max) {
    let cut = rest.lastIndexOf(", ", max)
    if (cut < max / 2) cut = rest.lastIndexOf(" ", max)
    if (cut < 1) cut = max
    out.push(rest.slice(0, cut + 1).trim())
    rest = rest.slice(cut + 1).trim()
  }
  if (rest) out.push(rest)
  return out
}

// `start` = { c, n } from the reference the pastor typed (John 3:16 → c 3, n 16),
// or nothing. `parse` (the device's reference parser) lets a reference found in
// the paste fill that in.
export function splitPasted(raw, { start = null, parse = null } = {}) {
  const cleaned = cleanPaste(raw)
  let from = start
  if (!from && cleaned.reference && parse) {
    const p = parse(cleaned.reference)
    if (p?.valid && p.verseStart) from = { c: p.chapter, n: p.verseStart }
  }
  const text = markLines(cleaned.text)
  const cands = candidates(text)
  let run = pickRun(text, cands, from)
  // The numbers don't start where the typed reference does: trust the paste.
  if (!run.length && from) run = pickRun(text, cands, { c: from.c, n: null })
  let verses = []
  if (run.length >= 2 || (run.length === 1 && text.slice(0, run[0].index).trim().length === 0)) {
    run.forEach((mark, i) => {
      const words = text.slice(mark.end, run[i + 1]?.index ?? text.length)
      const body = tidy(dropHeading(words.replace(/⟦\d+⟧/g, " ")))
      if (body) verses.push({ c: mark.c ?? from?.c ?? 0, n: mark.n, text: body })
    })
  }
  const numbered = verses.length > 0
  if (!numbered) {
    const words = text.replace(/⟦\d+⟧/g, " ")
    const chunks = chunkSentences(words)
    // One verse named and one slide of words: that verse, numbered.
    const single = from && chunks.length === 1 && start?.single
    verses = chunks.map((t) => ({ c: from?.c ?? 0, n: single ? from.n : 0, text: t }))
  }
  return { verses, numbered, reference: cleaned.reference, version: cleaned.version }
}

export function checkSize(verses) {
  if (verses.length > MAX_VERSES) return `That's ${verses.length} verses — paste up to ${MAX_VERSES} at a time (split a long reading into two).`
  const bytes = new TextEncoder().encode(verses.map((v) => v.text).join("")).length
  if (bytes > MAX_BYTES) return `That passage is too long to keep in one item (about ${Math.round(bytes / 1000)} KB) — paste up to ${MAX_BYTES / 1000} KB at a time.`
  return null
}

// The plain text a pasted item came from, for editing it again.
export function versesText(verses) {
  return (verses || []).map((v) => (v.n > 0 ? `${v.n} ${v.text}` : v.text)).join("\n")
}
