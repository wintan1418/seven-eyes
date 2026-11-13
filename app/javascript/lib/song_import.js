// Pasted (or .txt) song words → the tidy form the song editor keeps:
// "[Verse 1]" / "[Chorus]" labels on their own line, one blank line between
// stanzas. Handles what comes off lyric sites, hymnals and WhatsApp:
//   a title line on top · "1." / "2" verse numbers · "Chorus:" / "Refrain" /
//   "Chorus: words on the same line" · "(Repeat Chorus)" · a stray "(x2)" line ·
//   no blank lines at all but labels · Windows line ends, tabs, odd spaces.
// No DOM, so node can test it (test/javascript/song_sheet_test.mjs).
//
//   tidySong(text) → { title, body, found }   found: "V1 C V2 C" or "3 stanzas"
import { parseLabel, songSlides, flowCodes } from "./song_sheet.js"

const INLINE_LABEL = /^(pre-?chorus|verse|stanza|chorus|refrain|bridge|tag|ending|outro|intro|vamp|v|c|b)\s*(\d+)?\s*[:.]\s+(\S.*)$/i
const VERSE_NUMBER = /^(\d{1,2})\s*[.)]?\s+(?=[A-Za-z'"‘“(])/
// "Matthew 28:20 AMP" — pasted scripture keeps its reference line on the slide.
const SCRIPTURE_REF = /\b\d{1,3}\s*:\s*\d{1,3}\b/
const LONE_REPEAT = /^\(?\s*(?:[x×]\s*\d+|\d+\s*[x×]|repeat|twice)\s*\)?$/i

export function tidySong(text) {
  const lines = String(text ?? "")
    .replace(/\r\n?/g, "\n").replace(/[\u00a0\u2007\u202f\t]/g, " ")
    .split("\n").map((l) => l.replace(/\s+/g, " ").trim())

  let title = ""
  const first = lines.findIndex((l) => l)
  if (first >= 0 && lines[first + 1] === "" && lines.slice(first + 1).some((l) => l) &&
      lines[first].length <= 60 && !parseLabel(lines[first]) && !/[,;:]$/.test(lines[first]) &&
      !VERSE_NUMBER.test(lines[first]) && !SCRIPTURE_REF.test(lines[first])) {
    title = lines[first].replace(/^["“]|["”]$/g, "")
    lines.splice(0, first + 1)
  }

  // Stanza numbers ("1.", "2") only count when they run 1, 2, 3… — pasted
  // scripture starts its verses with numbers too ("20 teaching them…").
  const numbered = numberedStanzas(lines)

  const blocks = [] // { label: "[Chorus]" | null, lines: [] }
  let current = null
  const close = () => { if (current) blocks.push(current); current = null }
  for (const line of lines) {
    if (!line) { close(); continue }
    const label = parseLabel(line)
    if (label) { close(); current = { label: canonical(label), lines: [] }; continue }
    const inline = line.match(INLINE_LABEL)
    const inlineLabel = inline && parseLabel(`[${inline[1]}${inline[2] ? ` ${inline[2]}` : ""}]`)
    if (inlineLabel) { close(); current = { label: canonical(inlineLabel), lines: [ inline[3] ] }; continue }
    if (!current) {
      if (LONE_REPEAT.test(line) && blocks.length) { current = blocks.pop(); current.lines.push(line); continue }
      const number = numbered && line.match(VERSE_NUMBER)
      if (number) { current = { label: `[Verse ${parseInt(number[1], 10)}]`, lines: [ line.slice(number[0].length) ] }; continue }
      current = { label: null, lines: [] }
    }
    current.lines.push(line)
  }
  close()

  // A label alone above its words ("Chorus", blank line, the chorus) belongs to
  // them — unless it names a section already written (then it means "repeat").
  const seen = new Set()
  const merged = []
  blocks.forEach((b) => {
    const prev = merged[merged.length - 1]
    if (prev && prev.label && !prev.lines.length && !b.label && !seen.has(prev.label)) {
      prev.lines = b.lines
    } else {
      merged.push(b)
    }
    if (b.label && b.lines.length) seen.add(b.label)
    if (prev?.label && prev.lines.length) seen.add(prev.label)
  })

  const body = merged.map((b) => [ b.label, ...b.lines ].filter(Boolean).join("\n")).join("\n\n")
  const { slides, labelled } = songSlides(body)
  const found = labelled ? flowCodes(slides) : `${slides.length} stanza${slides.length === 1 ? "" : "s"}`
  return { title, body, found }
}

function numberedStanzas(lines) {
  const numbers = lines.filter((l, i) => l && !lines[i - 1] && !parseLabel(l)).map((l) => l.match(VERSE_NUMBER)?.[1]).filter(Boolean).map(Number)
  return numbers.length > 0 && numbers.every((n, i) => n === i + 1)
}

function canonical(label) {
  if (label.custom) return `[${label.name}]`
  return `[${label.name}${label.number && (label.kind === "verse" || label.number > 1) ? ` ${label.number}` : ""}]`
}
