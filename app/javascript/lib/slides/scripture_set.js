// Scripture sets: several references on one slide, each in its own
// translation — "Col 2:2; Matt 28:19 BSB" → Colossians 2:2 (KJV) + Matthew
// 28:19 (BSB) on one screen, the reference line where the operator wants it.
// No DOM and no IndexedDB, so node can test it (test/javascript/slides_test.mjs).
//
//   splitSetInput(raw, { parse, codes, fallback })  typed text → entries (+ errors)
//   setPages(data)        the passages laid out as slides (auto-split when long)
//   pageText(page, data)  one slide as plain text (stage, live phones, WhatsApp)
//   setBody(data)         every slide's text, blank line between — SetlistItem#body
//   setLabel(data)        "Colossians 2:2 KJV + Matthew 28:19 BSB"
//
// data = { refs: [{ reference, translation, label, verses: [{ c, n, text }] }],
//          ref_position: "top" | "bottom" | "inline", verse_numbers, split: "auto" | "each",
//          ref_style: "gold" | "plain" }

// Roughly what fits on a projector at a readable size; a longer slide is
// split at a verse boundary (a single long verse keeps a slide to itself).
export const SLIDE_BUDGET = 430

export const DEFAULTS = Object.freeze({ ref_position: "top", verse_numbers: true, split: "auto", ref_style: "gold" })

// Split on ";", ",", "+", "&" and new lines; a bare number continues the
// chapter before it ("Jn 3:16, 18"). A piece may end in a Bible's code ("Matt 28:19 AMP").
export function splitSetInput(raw, { parse, codes = [], fallback = null } = {}) {
  const known = new Map(codes.map((c) => [ String(c).toLowerCase(), String(c).toUpperCase() ]))
  const pieces = String(raw ?? "").split(/[\n;+&,]+/).map((s) => s.trim()).filter(Boolean)
  const entries = []
  const errors = []
  let last = null
  for (const raw of pieces) {
    // A bare number after a reference is another verse of that chapter ("Jn 3:16, 18").
    const piece = last && /^\d+(?:\s*[-–]\s*\d+)?(?:\s+[A-Za-z]{2,10})?$/.test(raw) ? `${last.bookName} ${last.chapter}:${raw.replace(/\s*[-–]\s*/, "-")}` : raw
    let text = piece
    let translation = null
    let warning = null
    const m = piece.match(/^(.*\d.*?)[\s,(]+([A-Za-z][A-Za-z0-9]{1,9})\)?$/)
    if (m) {
      const code = m[2].toLowerCase()
      if (known.has(code)) {
        translation = known.get(code)
        text = m[1].trim()
      } else if (looksLikeCode(m[2]) && (!parse || (!parse(piece).valid && parse(m[1]).valid))) {
        // AMP, NIV, NKJV…: copyrighted, so not on BiblioRata. Keep the verse, say so.
        text = m[1].trim()
        warning = `${m[2].toUpperCase()} isn't on BiblioRata (it's copyrighted) — showing ${fallback || "the default Bible"}; change it below`
      }
    }
    if (!parse) { entries.push({ reference: text, label: text, translation: translation || fallback, warning }); continue }
    const p = parse(text)
    if (!p.valid) {
      if (p.error !== "blank") errors.push({ raw: piece, message: `“${piece}” — couldn't read that reference` })
      continue
    }
    last = p
    entries.push({ reference: text, label: labelOf(p), translation: translation || fallback, warning, parsed: p })
  }
  return { entries, errors }
}

// "AMP", "NIV", "NKJV": a trailing all-capitals word.
function looksLikeCode(word) {
  return /^[A-Z]{2,6}$/.test(word)
}

export function labelOf(p) {
  let base = `${p.bookName} ${p.chapter}`
  if (p.verseStart == null) return p.chapterEnd > p.chapter ? `${base}-${p.chapterEnd}` : base
  base += `:${p.verseStart}`
  if (p.openEnded) return `${base}ff`
  if (p.chapterEnd > p.chapter) return `${base}-${p.chapterEnd}:${p.verseEnd}`
  return p.verseEnd != null && p.verseEnd !== p.verseStart ? `${base}-${p.verseEnd}` : base
}

export function withDefaults(data) {
  return { ...DEFAULTS, ...(data || {}), refs: (data?.refs || []).filter((r) => r && r.verses?.length) }
}

// The slides: each is { blocks: [{ label, translation, verses, cont }] }. With
// split "each" every reference starts a slide; with "auto" references share a
// slide while they fit SLIDE_BUDGET.
export function setPages(raw) {
  const data = withDefaults(raw)
  const pages = []
  let page = null
  let size = 0
  const start = () => { page = { blocks: [] }; pages.push(page); size = 0 }
  data.refs.forEach((ref) => {
    if (!page || data.split === "each") start()
    let block = null
    let placed = 0
    ref.verses.forEach((v) => {
      const cost = v.text.length + 8
      if (size > 0 && size + cost > SLIDE_BUDGET) { start(); block = null }
      if (!block) {
        block = { label: ref.label || ref.reference, translation: ref.translation || "", verses: [], cont: placed > 0 }
        page.blocks.push(block)
        size += 30
      }
      block.verses.push(v)
      placed++
      size += cost
    })
  })
  return pages
}

export function refLine(block) {
  return `${block.label}${block.translation ? ` (${block.translation})` : ""}`
}

export function blockWords(block, data) {
  const numbers = withDefaults(data).verse_numbers
  return block.verses.map((v) => (numbers ? `${v.n} ${v.text}` : v.text)).join(" ")
}

export function pageText(page, raw) {
  const data = withDefaults(raw)
  return page.blocks.map((b) => {
    const words = blockWords(b, data)
    if (data.ref_position === "bottom") return `${words}\n— ${refLine(b)}`
    if (data.ref_position === "inline") return `${words} (${refLine(b)})`
    return `${refLine(b)}\n${words}`
  }).join("\n")
}

export function setBody(data) {
  return setPages(data).map((p) => pageText(p, data)).join("\n\n")
}

export function setLabel(data) {
  return (data?.refs || []).map((r) => `${r.label || r.reference}${r.translation ? ` ${r.translation}` : ""}`).join(" + ")
}
