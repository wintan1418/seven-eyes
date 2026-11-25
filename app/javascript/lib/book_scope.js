// Search inside one book, EasyWorship-style: the operator knows the verse is
// "somewhere in Hebrews" and types the book, then a few words of it —
//
//   "heb heavenly jerusalem"      → Hebrews, "heavenly jerusalem"
//   "hebrews: heavenly jerusalem" → Hebrews, "heavenly jerusalem" (explicit)
//   "1 cor love suffereth"        → 1 Corinthians, "love suffereth"
//   "song of solomon rose"        → Song of Solomon, "rose"
//   "heb 12" / "john 3:16"        → null (a reference, not a search)
//
// Typed without a colon ("implicit") the book must be a name or one of its
// usual abbreviations (Bible::Canon aliases, 3+ letters) or 4+ letters of
// its name, so ordinary words ("son of man", "the lamb") aren't read as
// books. A colon is explicit and forgives more (2 letters, a typo).
//
// Pure functions (node-tested in test/javascript/book_scope_test.mjs). The
// canon is [{ osis, name, aliases }] — the console renders it into its book
// picker, so this works with nothing downloaded.

const MAX_BOOK_WORDS = 3 // "song of solomon"

export function bookKey(str) {
  return String(str ?? "").toLowerCase().replace(/[\s.]/g, "")
}

// (token, { loose }) → { osis, name } | null
export function makeBookResolver(canon) {
  const books = (canon || []).map((b) => ({ osis: b.osis, name: b.name, key: bookKey(b.name), aliases: (b.aliases || []).map(bookKey) }))
  const exact = new Map()
  books.forEach((b) => [ b.osis, b.name, ...b.aliases ].forEach((k) => {
    const key = bookKey(k)
    if (key && !exact.has(key)) exact.set(key, b)
  }))
  const pick = (b) => (b ? { osis: b.osis, name: b.name } : null)

  return function resolve(token, { loose = false } = {}) {
    const key = bookKey(token)
    if (!key || !/[a-z]/.test(key)) return null
    const hit = exact.get(key)
    if (hit && (loose || key.replace(/^\d/, "").length >= 3)) return pick(hit)
    const prefixMin = loose ? 2 : 4
    if (key.replace(/^\d/, "").length >= prefixMin) {
      const hits = books.filter((b) => b.key.startsWith(key))
      if (hits.length === 1) return pick(hits[0])
    }
    if (loose && key.length >= 4) {
      const near = books.filter((b) => editDistance(key, b.key) <= (key.length >= 7 ? 2 : 1))
      if (near.length === 1) return pick(near[0])
    }
    return null
  }
}

// What was typed → { book: {osis, name}, words, explicit } or null when the
// text doesn't start with a book followed by words.
export function splitBookScope(raw, resolve) {
  const text = String(raw ?? "").replace(/\s+/g, " ").trim()
  if (!text || typeof resolve !== "function") return null

  // "hebrews: heavenly jerusalem" / "heb : jerusalem"
  const colon = text.match(/^([1-3]?\s?[a-z][a-z .]*?)\s*:\s*(.+)$/i)
  if (colon && hasWords(colon[2])) {
    const book = resolve(colon[1], { loose: true })
    if (book) return { book, words: colon[2].trim(), explicit: true }
  }

  const tokens = text.split(" ")
  for (let n = Math.min(MAX_BOOK_WORDS, tokens.length - 1); n >= 1; n--) {
    const rest = tokens.slice(n).join(" ")
    if (/^\d/.test(rest) || !hasWords(rest)) continue // "heb 12", "1 cor 13:4" — a reference
    const book = resolve(tokens.slice(0, n).join(" "))
    if (book) return { book, words: rest, explicit: false }
  }
  return null
}

function hasWords(text) {
  return /[a-z]{2,}/i.test(String(text || ""))
}

// The book a reference is in ("Hebrews 12" → Hebrews), for "this book".
export function bookOfReference(reference, resolve) {
  const head = String(reference || "").trim().replace(/\s*\d+(?:\s*[:.]\s*\d.*)?$/, "")
  return head ? resolve(head, { loose: true }) : null
}

function editDistance(a, b) {
  if (Math.abs(a.length - b.length) > 2) return 99
  const row = Array.from({ length: b.length + 1 }, (_, i) => i)
  for (let i = 1; i <= a.length; i++) {
    let prev = row[0]
    row[0] = i
    for (let j = 1; j <= b.length; j++) {
      const tmp = row[j]
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1))
      prev = tmp
    }
  }
  return row[b.length]
}
