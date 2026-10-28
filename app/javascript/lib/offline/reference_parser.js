// A faithful port of app/services/reference_parser.rb, so references typed
// while offline ("jn 3:16", "1cor13", "phillipians 4", "Matt 5-7") are read
// exactly as the server would read them. The canon (OSIS codes, names,
// chapter counts, aliases) comes from Bible::Canon via the offline manifest.
//
// Kept in step with the Ruby parser by test/services/reference_parser_parity_test.rb,
// which runs both over the same inputs — change them together.
//
//   const parse = makeParser(canon)
//   parse("Jn 3:16") → { valid: true, osis: "John", bookName: "John", chapter: 3,
//                        chapterEnd: 3, verseStart: 16, verseEnd: 16, openEnded: false, chapterCount: 21 }

const RANGE_RE = new RegExp(
  "^(?<book>[1-3]?\\s*[a-z][a-z\\s]*?)" +
  "(?:\\s*(?<chapter>\\d+)" +
    "(?:" +
      "\\s*[:.,]?\\s*(?<v1>\\d+)(?:\\s*-\\s*(?:(?<c2v>\\d+)\\s*[:.]\\s*)?(?<v2>\\d+))?" +
      "|" +
      "\\s*-\\s*(?<c2>\\d+)" +
    ")?" +
  ")?\\s*$"
)

const FUZZY_MIN_LENGTH = 4
const PREFIX_MIN_LENGTH = 3

export function normalizeKey(str) {
  return String(str ?? "").toLowerCase().replace(/[\s.]/g, "")
}

export function makeParser(canon) {
  const books = canon.map((b) => ({ ...b, key: normalizeKey(b.name) }))
  const byOsis = new Map(books.map((b) => [ b.osis, b ]))
  const aliasMap = new Map()
  books.forEach((b) => [ b.osis, b.name, ...(b.aliases || []) ].forEach((k) => aliasMap.set(normalizeKey(k), b.osis)))

  function parse(input) {
    const raw = String(input ?? "").trim()
    if (!raw) return invalid("blank")

    const { text, openEnded } = normalize(raw)
    const m = text.match(RANGE_RE)
    if (!m) return invalid("unknown_book")

    const osis = resolveBook(m.groups.book)
    if (!osis) return invalid("unknown_book")

    const entry = byOsis.get(osis)
    const location = resolveLocation(entry, m.groups)
    if (typeof location === "string") return invalid(location, entry)

    const [ chapter, v1, chapterEnd, v2 ] = location
    const open = openEnded && v1 != null && v2 == null
    return {
      valid: true, error: null, osis, bookName: entry.name, chapter, chapterEnd,
      verseStart: v1 ?? null, verseEnd: open ? null : (v2 ?? v1 ?? null), openEnded: open,
      chapterCount: entry.chapters
    }
  }

  function invalid(error, entry = null) {
    return { valid: false, error, osis: entry?.osis ?? null, bookName: entry?.name ?? null, chapterCount: entry?.chapters ?? null }
  }

  function resolveBook(token) {
    const key = normalizeKey(token)
    if (!key) return null
    return aliasMap.get(key) || prefixMatch(key) || fuzzyMatch(key)
  }

  function prefixMatch(key) {
    if (key.length < PREFIX_MIN_LENGTH) return null
    const hits = books.filter((b) => b.key.startsWith(key))
    return hits.length === 1 ? hits[0].osis : null
  }

  function fuzzyMatch(key) {
    if (key.length < FUZZY_MIN_LENGTH) return null
    const nameAllowance = key.length >= 7 ? 2 : 1
    const scored = []
    for (const b of books) {
      const candidates = [ [ b.key, nameAllowance ],
        ...(b.aliases || []).filter((a) => a.length >= FUZZY_MIN_LENGTH).map((a) => [ normalizeKey(a), 1 ]) ]
      let best = null
      for (const [ text, allowance ] of candidates) {
        const d = editDistance(key, text)
        if (d <= allowance && (best === null || d < best)) best = d
      }
      if (best !== null) scored.push([ b.osis, best ])
    }
    if (!scored.length) return null
    scored.sort((a, b) => a[1] - b[1])
    if (scored.length > 1 && scored[0][1] === scored[1][1]) return null
    return scored[0][0]
  }

  parse.book = (osis) => byOsis.get(osis) || null
  return parse
}

function normalize(str) {
  let s = str.toLowerCase().trim()
  s = s.replace(/[–—‐‒]/g, "-")
  s = s.replace(/[;!?'"()[\]]+/g, " ")
  s = s.replace(/\s+/g, " ")
  s = s.replace(/^(?:saint|st)\b\.?\s*(?=[a-z])/, "")
  s = s.replace(/^(?:1st|first)\b\.?\s*/, "1 ")
  s = s.replace(/^(?:2nd|second)\b\.?\s*/, "2 ")
  s = s.replace(/^(?:3rd|third)\b\.?\s*/, "3 ")
  s = s.replace(/^(iii|ii|i)\.?\s+(?=[a-z])/, (_, r) => ({ i: "1 ", ii: "2 ", iii: "3 " })[r])
  s = s.replace(/\b(?:chapter|chap|ch)\.?\s*(?=\d)/g, " ")
  s = s.replace(/(\d)\s*(?:verses|verse|vv|vs|v)\.?\s*(?=\d)/g, "$1:")
  s = s.replace(/(\D):(\d)/, "$1 $2")
  s = s.replace(/([a-z])\./g, "$1 ")
  s = s.replace(/[.,:\-\s]+$/, "")
  let openEnded = false
  s = s.replace(/(\d)\s*ff?$/, (_, d) => { openEnded = true; return d })
  s = s.replace(/(\d)[abc](?=\s*-|\s*$)/g, "$1") // no lookbehind: older iOS Safari can't parse it
  return { text: s.replace(/\s+/g, " ").trim(), openEnded }
}

function int(v) { return v == null ? null : parseInt(v, 10) }

function resolveLocation(entry, g) {
  if (g.chapter == null) return [ 1, null, 1, null ]

  const n = int(g.chapter)
  let v1 = int(g.v1)
  let v2 = int(g.v2)
  const c2 = int(g.c2)
  const c2v = int(g.c2v)

  if (entry.chapters === 1 && v1 == null && (n > 1 || c2 != null)) {
    v1 = n; v2 = c2
    if (v1 < 1 || (v2 != null && v2 < 1)) return "bad_verse"
    if (v2 != null && v2 < v1) [ v1, v2 ] = [ v2, v1 ]
    return [ 1, v1, 1, v2 ]
  }
  if (n < 1 || n > entry.chapters) return "bad_chapter"
  if ((v1 != null && v1 < 1) || (v2 != null && v2 < 1)) return "bad_verse"

  if (c2 != null) {
    const first = Math.min(n, c2), last = Math.max(n, c2)
    if (first < 1 || last > entry.chapters) return "bad_chapter"
    return [ first, null, last, null ]
  }

  if (c2v != null && c2v !== n) {
    if (c2v < n || c2v > entry.chapters) return "bad_chapter"
    return [ n, v1, c2v, v2 ]
  }

  if (v1 != null && v2 != null && v2 < v1) [ v1, v2 ] = [ v2, v1 ]
  return [ n, v1, n, v2 ]
}

// Damerau–Levenshtein (optimal string alignment), as in the Ruby parser.
function editDistance(a, b) {
  if (!a.length) return b.length
  if (!b.length) return a.length
  const rows = Array.from({ length: a.length + 1 }, (_, i) =>
    Array.from({ length: b.length + 1 }, (_, j) => (i === 0 ? j : (j === 0 ? i : 0))))
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      rows[i][j] = Math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        rows[i][j] = Math.min(rows[i][j], rows[i - 2][j - 2] + 1)
      }
    }
  }
  return rows[a.length][b.length]
}

// "John 3", "John 3:16", "John 3:16-18", "John 3:16ff", "John 3:16-4:2", "Matthew 5-7"
// — ReferenceParser::Result#label.
export function referenceLabel(p) {
  if (!p?.valid) return null
  let base = `${p.bookName} ${p.chapter}`
  const multi = p.chapterEnd > p.chapter
  if (p.verseStart == null) return multi ? `${base}-${p.chapterEnd}` : base
  base += `:${p.verseStart}`
  if (p.openEnded) return `${base}ff`
  if (multi) base += `-${p.chapterEnd}:${p.verseEnd}`
  else if (p.verseEnd != null && p.verseEnd !== p.verseStart) base += `-${p.verseEnd}`
  return base
}
