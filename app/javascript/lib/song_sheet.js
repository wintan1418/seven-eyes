// A song's words → the slides the projector walks through, EasyWorship-style.
// No DOM, so node can test it (test/javascript/song_sheet_test.mjs); the server
// has the same rules in app/services/song_sheet.rb — keep the two in step (the
// shared cases in test/fixtures/files/song_sheet_cases.json run against both).
//
// Blank lines split the words into stanzas; each stanza is one slide. A stanza
// may start with a section label on its own line:
//   [Verse 1]  [Chorus]  [Pre-Chorus]  [Bridge]  [Tag]  [Yoruba]   (brackets: any name)
//   Verse 1   Chorus:   Refrain   (Chorus x2)   V1:   C:           (the usual words)
// A label with no words under it repeats that section there ("[Chorus]" again,
// "Repeat chorus"). A song with no labels at all is projected stanza by stanza,
// exactly as before sections existed.
//
// The order (arrangement), e.g. "V1 C V2 C B C", projects a section as often as
// it is named, so a chorus is typed once. Without one, a hymn-shaped song (verses
// + one chorus/refrain written once) sings the chorus after every verse; any
// other song follows the written order.
//
//   songSlides(body, arrangement) → { slides: [{ label, code, text }], labelled, unknown: [tokens] }
//   projectedBody(body, arrangement) → the slides' words joined by blank lines (no labels)
//   flowCodes(slides) → "V1 C V2 C"

const KINDS = [
  // kind, display name, short code, words that name it (as a label line or in an order)
  [ "prechorus", "Pre-Chorus", "PC", [ "prechorus", "pre", "pc" ] ],
  [ "verse", "Verse", "V", [ "verse", "stanza", "v" ] ],
  [ "chorus", "Chorus", "C", [ "chorus", "refrain", "ch", "c", "r" ] ],
  [ "bridge", "Bridge", "B", [ "bridge", "br", "b" ] ],
  [ "tag", "Tag", "T", [ "tag", "t" ] ],
  [ "ending", "Ending", "E", [ "ending", "end", "outro", "coda", "e", "o" ] ],
  [ "intro", "Intro", "I", [ "intro", "i" ] ],
  [ "vamp", "Vamp", "VP", [ "vamp", "vp" ] ]
]
const BY_WORD = new Map()
KINDS.forEach(([ kind, name, code, words ]) => words.forEach((w) => BY_WORD.set(w, { kind, name, code })))
// Spelled-out words a bare line may use as a label (short codes need a colon: "V1:").
const LONG_WORDS = "pre-?chorus|pre chorus|verse|stanza|chorus|refrain|bridge|tag|ending|outro|coda|intro|vamp"
const REPEAT = String.raw`(?:[x×]\s*\d+|\d+\s*[x×]|\(\s*[x×]?\s*\d+\s*[x×]?\s*\)|\(?\s*repeat\s*\)?)`
const BARE_LABEL = new RegExp(String.raw`^\(?\s*(?:repeat\s+(?:the\s+)?)?(${LONG_WORDS})\s*(\d+)?\s*${REPEAT}?\s*\)?\s*[:.]?$`, "i")
const SHORT_LABEL = /^(pc|v|c|ch|b|br|t|e)\s*(\d+)?\s*:$/i
const BRACKET_LABEL = /^\[\s*([^\]]{1,30}?)\s*\]$/
const BRACKET_INNER = new RegExp(String.raw`^(?:repeat\s+(?:the\s+)?)?(${LONG_WORDS}|pc|v|c|ch|b|br|t|e)\s*(\d+)?\s*${REPEAT}?$`, "i")

// One line → a label { kind, number, name, custom } or null.
export function parseLabel(line) {
  const text = String(line ?? "").trim()
  if (!text || text.length > 40) return null
  const bracket = text.match(BRACKET_LABEL)
  if (bracket) {
    const inner = bracket[1].trim()
    const known = inner.match(BRACKET_INNER)
    if (known) return known_(known[1], known[2])
    return { kind: "other", number: null, name: inner, custom: true }
  }
  const bare = text.match(BARE_LABEL) || text.match(SHORT_LABEL)
  return bare ? known_(bare[1], bare[2]) : null
}

function known_(word, digits) {
  const def = BY_WORD.get(word.toLowerCase().replace(/[\s-]/g, ""))
  if (!def) return null
  const n = digits ? parseInt(digits, 10) : null
  return { kind: def.kind, number: n, name: def.name, custom: false }
}

const blocksOf = (body) =>
  String(body ?? "").replace(/\r\n?/g, "\n").split(/\n[ \t]*\n/).map((b) => b.trim()).filter(Boolean)

// The written sections, in order. A section is { kind, key, label, code, text }
// or a repeat { ref: key }.
export function parseSections(body) {
  const blocks = blocksOf(body)
  const raw = blocks.map((block) => {
    const lines = block.split("\n")
    const label = parseLabel(lines[0])
    return label ? { label, text: lines.slice(1).join("\n").trim() } : { label: null, text: block }
  })
  const labelled = raw.some((b) => b.label)
  if (!labelled) return { labelled, sections: raw.map((b) => ({ kind: null, key: null, label: null, code: null, text: b.text })) }

  const sections = []
  const defined = new Map()
  let verseMax = 0
  let carry = null // a label on its own, waiting for the words below it
  raw.forEach((b) => {
    let label = b.label
    if (label && !b.text) {
      const key = keyOf(label, verseMax, true)
      if (key && defined.has(key)) sections.push({ ref: key })
      else carry = label
      return
    }
    if (!label && carry) label = carry
    carry = null
    if (!label) label = { kind: "verse", number: null, name: "Verse", auto: true }
    const number = label.kind === "verse" ? (label.number || verseMax + 1) : label.number
    if (label.kind === "verse") verseMax = Math.max(verseMax, number)
    const section = describe({ ...label, number }, b.text)
    if (!defined.has(section.key)) defined.set(section.key, section)
    else section.again = true
    sections.push(section)
  })
  return { labelled, sections, defined }
}

// The key a label is found by: "v2", "c", "c2", "b", "other:yoruba".
function keyOf(label, verseMax, lookingUp = false) {
  if (label.kind === "other") return `other:${label.name.toLowerCase()}`
  if (label.kind === "verse") {
    const n = label.number || (lookingUp ? verseMax : verseMax + 1)
    return n ? `v${n}` : null
  }
  const code = KINDS.find((k) => k[0] === label.kind)[2].toLowerCase()
  return label.number && label.number > 1 ? `${code}${label.number}` : code
}

function describe(label, text) {
  if (label.kind === "other") return { kind: "other", key: keyOf(label), label: label.name, code: label.name, text }
  const def = KINDS.find((k) => k[0] === label.kind)
  const numbered = label.kind === "verse" || (label.number && label.number > 1)
  return {
    kind: label.kind, key: keyOf(label, 0),
    label: numbered ? `${def[1]} ${label.number}` : def[1],
    code: numbered ? `${def[2]}${label.number}` : def[2],
    text
  }
}

export function songSlides(body, arrangement = "") {
  const { labelled, sections, defined } = parseSections(body)
  const asSlide = (s) => ({ label: s.label, code: s.code, text: s.text })
  if (!labelled) return { slides: sections.map(asSlide), labelled, unknown: [] }

  const { flow, unknown } = arrangementFlow(arrangement, defined)
  if (flow.length) return { slides: flow.map(asSlide), labelled, unknown }

  const written = sections.map((s) => (s.ref ? defined.get(s.ref) : s)).filter(Boolean)
  return { slides: withRefrain(written, sections).map(asSlide), labelled, unknown }
}

// Hymn shape — verses plus one chorus written once, never repeated by hand —
// sings the chorus after every verse.
function withRefrain(written, sections) {
  const choruses = sections.filter((s) => s.ref || s.kind === "chorus")
  const others = sections.filter((s) => !s.ref && s.kind !== "chorus")
  if (choruses.length !== 1 || choruses[0].ref || !others.length || others.some((s) => s.kind !== "verse")) return written
  const chorus = choruses[0]
  const out = []
  written.forEach((s, i) => {
    out.push(s)
    if (s.kind === "verse" && written[i + 1] !== chorus) out.push(chorus)
  })
  return out
}

// "V1 C V2 C B C" (also "Verse 1, Chorus", "v c v c" = next verse each time).
export function arrangementTokens(arrangement) {
  const cleaned = String(arrangement ?? "").toLowerCase()
    .replace(/pre[\s-]+chorus/g, "prechorus")
    .replace(/\(?\s*[x×]\s*\d+\s*\)?|\b\d+\s*[x×]\b|[*]\s*\d+/g, " ")
  const parts = cleaned.split(/[\s,;|/>→·–—-]+/).filter(Boolean)
  const tokens = []
  parts.forEach((p) => {
    if (/^\d+$/.test(p) && tokens.length && !/\d$/.test(tokens[tokens.length - 1])) tokens[tokens.length - 1] += p
    else tokens.push(p)
  })
  return tokens
}

function arrangementFlow(arrangement, defined) {
  const flow = []
  const unknown = []
  if (!defined) return { flow, unknown }
  let lastVerse = 0
  arrangementTokens(arrangement).forEach((token) => {
    const custom = defined.get(`other:${token}`)
    if (custom) { flow.push(custom); return }
    const m = token.match(/^([a-z]+)(\d*)$/)
    const def = m && BY_WORD.get(m[1])
    if (!def) { unknown.push(token); return }
    let key
    if (def.kind === "verse") {
      const n = m[2] ? parseInt(m[2], 10) : lastVerse + 1
      lastVerse = n
      key = `v${n}`
    } else {
      key = keyOf({ kind: def.kind, number: m[2] ? parseInt(m[2], 10) : null })
    }
    const section = defined.get(key)
    if (section) flow.push(section)
    else unknown.push(token)
  })
  return { flow, unknown }
}

export function projectedBody(body, arrangement = "") {
  return songSlides(body, arrangement).slides.map((s) => s.text).filter(Boolean).join("\n\n")
}

export function flowCodes(slides) {
  return slides.map((s) => s.code || "·").join(" ")
}
