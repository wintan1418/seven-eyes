// node --test test/javascript — the slide tools' pure logic: scripture sets
// (several references, each in its own Bible, on one slide), seminar steps,
// the order of service text and song bank collections.
import { test } from "node:test"
import assert from "node:assert/strict"
import { makeParser } from "../../app/javascript/lib/offline/reference_parser.js"
import { splitSetInput, setPages, setBody, pageText, setLabel, SLIDE_BUDGET } from "../../app/javascript/lib/slides/scripture_set.js"
import { seminarSteps, stepText, stepLabel, bulletsOf, seminarBody } from "../../app/javascript/lib/slides/seminar.js"
import { orderText, orderLines } from "../../app/javascript/lib/slides/order_of_service.js"
import { inCollection, toggleTitle, applyCollectionOps } from "../../app/javascript/lib/song_collections.js"

const canon = [
  { osis: "Matt", name: "Matthew", chapters: 28, aliases: [ "Mt", "Matt" ] },
  { osis: "Mark", name: "Mark", chapters: 16, aliases: [ "Mk", "Mrk" ] },
  { osis: "John", name: "John", chapters: 21, aliases: [ "Jn", "Jhn" ] },
  { osis: "1John", name: "1 John", chapters: 5, aliases: [ "1Jn", "1 Jn" ] },
  { osis: "Col", name: "Colossians", chapters: 4, aliases: [ "Col" ] }
]
const parse = makeParser(canon)
const codes = [ "KJV", "BSB", "WEB" ]

test("one line, several references, each with its own Bible", () => {
  const { entries, errors } = splitSetInput("Col 2:2; Matt 28:19 BSB", { parse, codes, fallback: "KJV" })
  assert.deepEqual(errors, [])
  assert.deepEqual(entries.map((e) => [ e.label, e.translation ]), [ [ "Colossians 2:2", "KJV" ], [ "Matthew 28:19", "BSB" ] ])
})

test("+, commas and new lines separate too; codes are case-blind; a bare number is the same chapter", () => {
  const { entries } = splitSetInput("Mark 1:1 web + John 3:16, 18\n1 Jn 4:8 (bsb)", { parse, codes, fallback: "KJV" })
  assert.deepEqual(entries.map((e) => [ e.label, e.translation ]), [ [ "Mark 1:1", "WEB" ], [ "John 3:16", "KJV" ], [ "John 3:18", "KJV" ], [ "1 John 4:8", "BSB" ] ])
})

test("a copyrighted Bible (AMP) keeps the verse in the default Bible and says why", () => {
  const { entries, errors } = splitSetInput("Matt 28:20 AMP", { parse, codes, fallback: "KJV" })
  assert.deepEqual(errors, [])
  assert.equal(entries[0].label, "Matthew 28:20")
  assert.equal(entries[0].translation, "KJV")
  assert.match(entries[0].warning, /AMP isn't on BiblioRata/)
})

test("unreadable references are reported, the rest kept", () => {
  const { entries, errors } = splitSetInput("Col 2:2; Hezekiah 4:1", { parse, codes, fallback: "KJV" })
  assert.equal(entries.length, 1)
  assert.match(errors[0].message, /Hezekiah 4:1/)
})

const col = { reference: "Col 2:2", label: "Colossians 2:2", translation: "KJV", verses: [ { c: 2, n: 2, text: "That their hearts might be comforted" } ] }
const matt = { reference: "Matt 28:19", label: "Matthew 28:19", translation: "BSB", verses: [ { c: 28, n: 19, text: "Therefore go and make disciples of all nations" } ] }

test("two short passages share one slide, the reference line where it's asked for", () => {
  const data = { refs: [ col, matt ], ref_position: "top", verse_numbers: false }
  const pages = setPages(data)
  assert.equal(pages.length, 1)
  assert.equal(pageText(pages[0], data), "Colossians 2:2 (KJV)\nThat their hearts might be comforted\nMatthew 28:19 (BSB)\nTherefore go and make disciples of all nations")
  assert.equal(setLabel(data), "Colossians 2:2 KJV + Matthew 28:19 BSB")
  assert.match(pageText(pages[0], { ...data, ref_position: "bottom" }), /comforted\n— Colossians 2:2 \(KJV\)/)
  assert.match(pageText(pages[0], { ...data, ref_position: "inline", verse_numbers: true }), /^2 That their hearts might be comforted \(Colossians 2:2 \(KJV\)\)/)
})

test("one each, or a long passage, makes more slides — split at verse boundaries", () => {
  assert.equal(setPages({ refs: [ col, matt ], split: "each" }).length, 2)
  const long = { ...col, verses: Array.from({ length: 8 }, (_, i) => ({ c: 2, n: i + 1, text: "x".repeat(120) })) }
  const pages = setPages({ refs: [ long ] })
  assert.ok(pages.length >= 3)
  pages.forEach((p) => assert.ok(p.blocks.every((b) => b.verses.reduce((s, v) => s + v.text.length, 0) <= SLIDE_BUDGET)))
  assert.equal(pages[1].blocks[0].cont, true)
  assert.equal(setBody({ refs: [ long ] }).split("\n\n").length, pages.length)
})

test("seminar steps: one per slide, or one per point when revealing", () => {
  const data = { slides: [ { layout: "title", title: "Leadership" }, { layout: "bullets", title: "Why", text: "- Serve\n- Model\n- Multiply" } ], reveal: false }
  assert.equal(seminarSteps(data).length, 2)
  assert.deepEqual(bulletsOf(data.slides[1]), [ "Serve", "Model", "Multiply" ])
  const reveal = { ...data, reveal: true }
  const steps = seminarSteps(reveal)
  assert.equal(steps.length, 4)
  assert.equal(stepText(reveal, steps[2]), "Why\n• Serve\n• Model")
  assert.equal(stepLabel(reveal, steps[2]), "Slide 2 · point 2/3")
  assert.equal(seminarBody(data), "Leadership\n\nWhy\n• Serve\n• Model\n• Multiply")
})

test("the order of service reads well on WhatsApp", () => {
  const items = [
    { kind: "song", title: "Blessed Assurance", label: "Blessed Assurance" },
    { kind: "scripture", reference: "John 3:16", label: "John 3:16" },
    { kind: "scripture_set", label: "Colossians 2:2 KJV + Matthew 28:19 BSB", body: "Colossians 2:2 (KJV)\nThat their hearts" },
    { kind: "presentation", title: "Building Project", data: { pages: 12 } }
  ]
  assert.equal(orderLines(items)[3].text, "Presentation: Building Project")
  assert.equal(orderText(items, { title: "Sunday Service", date: "Sunday, 15 November 2026" }),
    "*Sunday Service*\nSunday, 15 November 2026\n\n1. 🎵 Blessed Assurance\n2. 📖 John 3:16\n3. 📖 Colossians 2:2 KJV + Matthew 28:19 BSB\n4. 📊 Presentation: Building Project (12 pages)")
  assert.match(orderText(items, { words: true }), /3\. 📖 .*\n {3}Colossians 2:2 \(KJV\)\n {3}That their hearts/)
})

test("collections hold songs by title, any case, and replay unsynced changes", () => {
  const c = { id: "col-1", name: "Communion", titles: [ "When I Survey the Wondrous Cross" ] }
  assert.ok(inCollection(c, { title: "when i survey the wondrous cross" }))
  assert.deepEqual(toggleTitle(c.titles, "WHEN I SURVEY THE WONDROUS CROSS"), [])
  assert.deepEqual(toggleTitle([], "Silent Night"), [ "Silent Night" ])
  const ops = [
    { method: "PUT", url: "/song_collections/col-2", body: { song_collection: { name: "Christmas", titles: [ "Silent Night" ] } } },
    { method: "DELETE", url: "/song_collections/col-1" }
  ]
  assert.deepEqual(applyCollectionOps([ c ], ops), [ { id: "col-2", name: "Christmas", titles: [ "Silent Night" ] } ])
})
