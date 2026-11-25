// "Combine into one slide": several scriptures on ONE slide — the two beasts
// of Revelation 13:1 and 13:11 side by side — with the words editable and
// some of them emphasised for the preacher, EasyWorship's copy-to-clipboard-
// and-edit done in one place. The result is an ordinary scripture set
// (lib/slides/scripture_set) with one reference, `split: "one"` (never split
// across slides) and `combined: true` (the queue's ✎ reopens this editor).
//
// Emphasis lives in the verse text as two light marks the editor's buttons
// write and the slide draws:
//   **words**   bold          → <strong class="set-em">
//   ==words==   highlighted   → <mark class="set-hl">
// Plain-text views (stage, live phones, the order of service, Copy) drop them.
//
// Pure functions (node-tested in test/javascript/combine_test.mjs).

// Every verse of the picked passages, in the order picked, with where each
// came from: parts = [{ bookName, chapter, translation, verses: [{ c, n, text }] }].
export function combineParts(parts) {
  const list = (parts || []).filter((p) => p?.verses?.length)
  const codes = [ ...new Set(list.map((p) => p.translation || "")) ]
  const translation = codes.length === 1 ? codes[0] : ""
  const label = combinedLabel(list, { perPart: !translation })
  const multi = new Set(list.map((p) => `${p.bookName}|${p.chapter}`)).size > 1
  const verses = list.flatMap((p) => p.verses.map((v) => ({ c: v.c || p.chapter || 0, n: v.n || 0, text: String(v.text || "") })))
  // Words pasted from the pastor's own Bible (NKJV, NIV…) keep that mark.
  const own = list.some((p) => p.own)
  return { label, translation, verses, multi, own }
}

// "Revelation 13:1, 11" · "Revelation 13:1-3, 11; Daniel 7:3" ·
// with mixed Bibles: "Revelation 13:1 KJV; John 3:16 BSB".
export function combinedLabel(parts, { perPart = false } = {}) {
  const groups = []
  ;(parts || []).forEach((p) => {
    const last = groups[groups.length - 1]
    const nums = (p.verses || []).map((v) => v.n).filter((n) => n > 0)
    if (last && last.bookName === p.bookName && last.chapter === p.chapter && (!perPart || last.translation === p.translation)) {
      last.nums.push(...nums)
    } else {
      groups.push({ bookName: p.bookName, chapter: p.chapter, translation: p.translation || "", nums: [ ...nums ] })
    }
  })
  return groups.map((g, i) => {
    const sameBook = i > 0 && groups[i - 1].bookName === g.bookName && !perPart
    const head = sameBook ? `${g.chapter}` : `${g.bookName} ${g.chapter}`
    const nums = compact([ ...new Set(g.nums) ].sort((a, b) => a - b))
    return `${head}${nums ? `:${nums}` : ""}${perPart && g.translation ? ` ${g.translation}` : ""}`
  }).join("; ")
}

// [1, 2, 3, 11] → "1-3, 11"
export function compact(nums) {
  const out = []
  for (let i = 0; i < nums.length; i++) {
    let j = i
    while (j + 1 < nums.length && nums[j + 1] === nums[j] + 1) j++
    out.push(j > i ? `${nums[i]}-${nums[j]}` : `${nums[i]}`)
    i = j
  }
  return out.join(", ")
}

// ---- the editor's text: one verse a line, its number first ----------------------------

// [{c:13,n:1,text}, {c:13,n:11,text}] → "1 And I stood…\n11 And I beheld…"
// (chapter:verse when the verses come from more than one chapter).
export function versesToText(verses, { multi = false } = {}) {
  return (verses || []).map((v) => {
    const num = v.n > 0 ? (multi && v.c ? `${v.c}:${v.n}` : `${v.n}`) : ""
    return num ? `${num} ${v.text}` : v.text
  }).join("\n")
}

// Back again. A line starting with a number (or chapter:verse) is a verse; a
// line without one carries on the verse above (or stands alone, unnumbered).
export function textToVerses(text, { chapter = 0 } = {}) {
  const verses = []
  String(text || "").split(/\r?\n/).forEach((line) => {
    const t = line.trim()
    if (!t) return
    const m = t.match(/^(?:(\d{1,3})\s*[:.]\s*)?(\d{1,3})\s+(\S.*)$/)
    if (m) {
      const c = m[1] ? Number(m[1]) : (verses[verses.length - 1]?.c || chapter || 0)
      verses.push({ c, n: Number(m[2]), text: m[3] })
    } else if (verses.length) {
      verses[verses.length - 1].text += ` ${t}`
    } else {
      verses.push({ c: chapter || 0, n: 0, text: t })
    }
  })
  return verses
}

// ---- emphasis ------------------------------------------------------------------------

const MARKS = { b: "**", hl: "==" }
const MARK_RE = /\*\*(.+?)\*\*|==(.+?)==/g

// "a **b** c" → [{ text: "a " }, { text: "b", em: "b" }, { text: " c" }]
export function emphasisParts(text) {
  const s = String(text || "")
  const parts = []
  let last = 0
  for (const m of s.matchAll(MARK_RE)) {
    if (m.index > last) parts.push({ text: s.slice(last, m.index), em: null })
    parts.push({ text: m[1] ?? m[2], em: m[1] != null ? "b" : "hl" })
    last = m.index + m[0].length
  }
  if (last < s.length) parts.push({ text: s.slice(last), em: null })
  return parts.filter((p) => p.text)
}

export function plainText(text) {
  return String(text || "").replace(MARK_RE, (_, b, hl) => b ?? hl)
}

export function hasEmphasis(text) {
  return /\*\*(.+?)\*\*|==(.+?)==/.test(String(text || ""))
}

// Bold / highlight the selection [start, end) of `value` (a textarea's).
// Nothing selected: the word under the caret. Already marked that way: the
// marks come off. Returns { value, start, end } — the words stay selected.
export function toggleMark(value, start, end, kind) {
  const mark = MARKS[kind]
  if (!mark) return { value, start, end }
  let s = Math.max(0, Math.min(start, end))
  let e = Math.min(value.length, Math.max(start, end))
  if (s === e) [ s, e ] = wordAt(value, s)
  // Never across a line (a verse): keep to the first line of the selection.
  const nl = value.slice(s, e).indexOf("\n")
  if (nl >= 0) e = s + nl
  // Trim spaces so "**word **" never happens.
  while (s < e && /\s/.test(value[s])) s++
  while (e > s && /\s/.test(value[e - 1])) e--
  if (s === e) return { value, start, end }
  const n = mark.length
  if (value.slice(s - n, s) === mark && value.slice(e, e + n) === mark) {
    return { value: value.slice(0, s - n) + value.slice(s, e) + value.slice(e + n), start: s - n, end: e - n }
  }
  const inner = value.slice(s, e)
  if (inner.startsWith(mark) && inner.endsWith(mark) && inner.length > 2 * n) {
    return { value: value.slice(0, s) + inner.slice(n, -n) + value.slice(e), start: s, end: e - 2 * n }
  }
  return { value: `${value.slice(0, s)}${mark}${inner}${mark}${value.slice(e)}`, start: s + n, end: e + n }
}

function wordAt(value, pos) {
  let s = pos
  let e = pos
  while (s > 0 && /[\w’'-]/.test(value[s - 1])) s--
  while (e < value.length && /[\w’'-]/.test(value[e])) e++
  return [ s, e ]
}

// ---- Copy ------------------------------------------------------------------------------

// What "Copy" puts on the clipboard: the reference line, then the verses.
export function clipboardText({ label, translation, verses, multi = false }) {
  const head = `${label || ""}${translation ? ` (${translation})` : ""}`.trim()
  const body = (verses || []).map((v) => {
    const num = v.n > 0 ? (multi && v.c ? `${v.c}:${v.n}` : `${v.n}`) : ""
    return `${num ? `${num} ` : ""}${plainText(v.text)}`
  }).join("\n")
  return head ? `${head}\n${body}` : body
}
