// node --test test/javascript — the on-device Bible search page / sheet
// ranking (app/javascript/lib/scripture_search.js), kept in step with the
// server's ScriptureSearch.
import { test } from "node:test"
import assert from "node:assert/strict"
import { rankVerses, markParts, wordsLabel } from "../../app/javascript/lib/scripture_search.js"

const records = [
  { osis: "Job", chapters: Object.assign([], { 37: { t: [ "Hath the rain a father? or who hath begotten the drops of dew?" ] } }) },
  { osis: "Deut", chapters: Object.assign([], { 31: { t: [ "Give ear, O ye heavens.", "My doctrine shall drop as the rain, my speech shall distil as the dew, as the small rain upon the tender herb" ] } }) },
  { osis: "Gen", chapters: [ { t: [ "And God called the dry land Earth.", "the LORD God had not caused it to rain upon the earth" ] } ] },
  { osis: "Matt", chapters: Object.assign([], { 4: { t: [ "Love your enemies, bless them that curse you", "Thou shalt love thy neighbour, and hate thine enemy." ] } }) }
]
const order = new Map([ [ "Gen", 1 ], [ "Deut", 5 ], [ "Job", 18 ], [ "Matt", 40 ] ])

test("verses with every word come first, in Bible order; partial matches after", () => {
  const { hits, allCount, anyCount } = rankVerses(records, "dew rain", { order })
  assert.deepEqual(hits.map((h) => `${h.osis} ${h.chapter}:${h.num} ${h.tier}`),
    [ "Deut 32:2 all", "Job 38:1 all", "Gen 1:2 partial" ])
  assert.equal(allCount, 2)
  assert.equal(anyCount, 3)
})

test("the same order every run, whatever order the books were stored in", () => {
  const a = rankVerses(records, "dew rain", { order }).hits.map((h) => h.osis)
  const b = rankVerses([ ...records ].reverse(), "dew rain", { order }).hits.map((h) => h.osis)
  assert.deepEqual(a, b)
})

test("a phrase as typed ranks above verses that only hold the words", () => {
  const { hits } = rankVerses(records, "love your enemies", { order })
  assert.equal(hits[0].tier, "phrase")
  assert.equal(hits[0].num, 1)
  assert.equal(hits[1].tier, "all") // love … enemy
})

test("a book filter limits the search", () => {
  const { hits } = rankVerses(records, "rain", { order, books: new Set([ "Gen" ]) })
  assert.deepEqual(hits.map((h) => h.osis), [ "Gen" ])
})

test("matched words are marked, as text parts", () => {
  const parts = markParts("rained upon the dew", [ "rain", "dew" ])
  assert.deepEqual(parts.filter((p) => p.mark).map((p) => p.text), [ "rained", "dew" ])
  assert.equal(parts.map((p) => p.text).join(""), "rained upon the dew")
})

test("blank or stop-word queries find nothing", () => {
  assert.equal(rankVerses(records, "  the of ", { order }).hits.length, 0)
  assert.equal(wordsLabel([ { word: "dew" }, { word: "rain" } ]), "dew and rain")
})
