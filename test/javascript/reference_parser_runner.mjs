// Reads {canon, inputs} as JSON on stdin and prints what the offline (JS)
// reference parser makes of each input. Driven by
// test/services/reference_parser_parity_test.rb.
import { readFileSync } from "node:fs"
import { makeParser, referenceLabel } from "../../app/javascript/lib/offline/reference_parser.js"

const { canon, inputs } = JSON.parse(readFileSync(0, "utf8"))
const parse = makeParser(canon)
const out = inputs.map((input) => {
  const r = parse(input)
  return r.valid
    ? { valid: true, osis: r.osis, chapter: r.chapter, chapter_end: r.chapterEnd, verse_start: r.verseStart,
        verse_end: r.verseEnd, open_ended: r.openEnded, label: referenceLabel(r) }
    : { valid: false, error: r.error, osis: r.osis }
})
process.stdout.write(JSON.stringify(out))
