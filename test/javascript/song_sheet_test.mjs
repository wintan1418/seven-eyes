// node --test test/javascript — songs → slides (app/javascript/lib/song_sheet.js):
// section labels, the arrangement, the hymn refrain, and the paste tidy-up.
// The shared cases also run against the server's copy (test/services/song_sheet_test.rb).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { songSlides, projectedBody, flowCodes, parseLabel } from "../../app/javascript/lib/song_sheet.js"
import { tidySong } from "../../app/javascript/lib/song_import.js"

const cases = JSON.parse(readFileSync(new URL("../fixtures/files/song_sheet_cases.json", import.meta.url)))

for (const c of cases) {
  test(`song sheet: ${c.name}`, () => {
    const { slides, unknown } = songSlides(c.body, c.arrangement || "")
    if (c.slides) assert.deepEqual(slides.map((s) => [ s.label, s.text ]), c.slides)
    if (c.flow) assert.equal(flowCodes(slides), c.flow)
    assert.deepEqual(unknown, c.unknown || [])
  })
}

test("projectedBody is the slides' words in order, without labels", () => {
  const body = "[Verse 1]\na\n\n[Chorus]\nc\n\n[Verse 2]\nb"
  assert.equal(projectedBody(body), "a\n\nc\n\nb\n\nc")
  assert.equal(projectedBody("one\n\ntwo"), "one\n\ntwo")
})

test("label lines", () => {
  assert.equal(parseLabel("[Verse 2]").number, 2)
  assert.equal(parseLabel("REFRAIN:").kind, "chorus")
  assert.equal(parseLabel("Pre-Chorus").kind, "prechorus")
  assert.equal(parseLabel("V1:").kind, "verse")
  assert.equal(parseLabel("V1"), null) // a short code needs brackets or a colon
  assert.equal(parseLabel("Chorus of angels"), null)
  assert.equal(parseLabel("[Igbo]").name, "Igbo")
})

test("tidy: a pasted song with a title line, numbered verses, a refrain and (x2)", () => {
  const pasted = [
    "Blessed Assurance  ",
    "",
    "1. Blessed assurance, Jesus is mine!",
    "O what a foretaste of glory divine!",
    "",
    "",
    "Refrain:",
    "This is my story, this is my song,",
    "Praising my Saviour all the day long; (x2)",
    "",
    "2 Perfect submission, perfect delight,",
    "Visions of rapture now burst on my sight;",
    "",
    "Refrain"
  ].join("\r\n")
  const { title, body, found } = tidySong(pasted)
  assert.equal(title, "Blessed Assurance")
  assert.equal(body, [
    "[Verse 1]", "Blessed assurance, Jesus is mine!", "O what a foretaste of glory divine!", "",
    "[Chorus]", "This is my story, this is my song,", "Praising my Saviour all the day long; (x2)", "",
    "[Verse 2]", "Perfect submission, perfect delight,", "Visions of rapture now burst on my sight;", "",
    "[Chorus]"
  ].join("\n"))
  assert.equal(flowCodes(songSlides(body).slides), "V1 C V2 C")
  assert.equal(found, "V1 C V2 C")
})

test("tidy: label and words on one line, a lone (x2) joins the stanza above", () => {
  const { title, body } = tidySong("Chorus: Hallelujah\nwe sing\n\n(x2)\n\nVerse 2: Second words")
  assert.equal(title, "")
  assert.equal(body, "[Chorus]\nHallelujah\nwe sing\n(x2)\n\n[Verse 2]\nSecond words")
})

test("tidy: plain stanzas stay plain, extra spacing and odd spaces are cleaned", () => {
  const { title, body } = tidySong("  Line one  \nline two\n\n\n\nline three\t\n")
  assert.equal(title, "")
  assert.equal(body, "Line one\nline two\n\nline three")
})

test("tidy: a song with no blank lines but labels gets split at the labels", () => {
  const { body } = tidySong("Verse 1\na\nb\nChorus\nc\nd\nVerse 2\ne")
  assert.equal(body, "[Verse 1]\na\nb\n\n[Chorus]\nc\nd\n\n[Verse 2]\ne")
})

test("song bank search: titles first, then words; filters by source; ignores case and punctuation", async () => {
  const { searchSongs } = await import("../../app/javascript/lib/song_search.js")
  const songs = [
    { title: "Blessed Assurance", body: "[Verse 1]\nBlessed assurance, Jesus is mine!", source: "hymnal" },
    { title: "It Is Well with My Soul", body: "When peace, like a river,\nIt is well, it is well", source: "hymnal" },
    { title: "Our Anthem", body: "Jesus is mine forever", source: "yours" }
  ]
  assert.deepEqual(searchSongs(songs, "").map((r) => r.song.title), [ "Blessed Assurance", "It Is Well with My Soul", "Our Anthem" ])
  assert.deepEqual(searchSongs(songs, "it is well").map((r) => r.song.title), [ "It Is Well with My Soul" ])
  const mine = searchSongs(songs, "JESUS IS MINE")
  assert.deepEqual(mine.map((r) => r.song.title), [ "Blessed Assurance", "Our Anthem" ])
  assert.equal(mine[0].line, "Blessed assurance, Jesus is mine!")
  assert.deepEqual(searchSongs(songs, "jesus", { source: "yours" }).map((r) => r.song.title), [ "Our Anthem" ])
  assert.deepEqual(searchSongs(songs, "like a river").map((r) => r.song.title), [ "It Is Well with My Soul" ])
  assert.equal(searchSongs(songs, "zebra").length, 0)
})

test("tidy: pasted scripture (a custom slide) keeps its references and verse numbers", () => {
  const pasted = "Matthew 28:20 AMP\n\n20 teaching them to observe everything that I have commanded you;\n\nMark 1:1 BSB\n1 The beginning of the gospel of Jesus Christ, the Son of God."
  const { title, body } = tidySong(pasted)
  assert.equal(title, "")
  assert.match(body, /^Matthew 28:20 AMP\n\n20 teaching them/)
  assert.match(body, /Mark 1:1 BSB\n1 The beginning/)
  const { slides, labelled } = songSlides(body)
  assert.equal(labelled, false)
  assert.equal(slides.length, 3)
})
