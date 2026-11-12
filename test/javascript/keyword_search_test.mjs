// node --test test/javascript — the offline keyword search behind preach
// mode's Go box (app/javascript/lib/offline/keyword_search.js).
import { test } from "node:test"
import assert from "node:assert/strict"
import { searchVerses, keywords, stem } from "../../app/javascript/lib/offline/keyword_search.js"

// Bundle-shaped book records ({ osis, chapters: [{ i, t }] }).
const records = [
  { osis: "Josh", chapters: [ null, null, null, null, null,
    { i: 1, t: [ "Now Jericho was straitly shut up.", "And the LORD said unto Joshua, See, I have given into thine hand Jericho.",
                 "So the people shouted, and the wall fell down flat." ] } ] },
  { osis: "John", chapters: [ null,
    { i: 100, t: [ "And the third day there was a marriage in Cana.",
                   "And when he had made a scourge of small cords, he drove them all out of the temple." ] },
    { i: 200, t: [ "There was a man of the Pharisees.", "For God so loved the world, that he gave his only begotten Son." ] } ] },
  { osis: "Matt", chapters: [ { i: 300, t: [ "Then did they spit in his face, and buffeted him; and others smote him." ] } ] }
]

test("stop words and short words are not keywords", () => {
  assert.deepEqual(keywords("the walls of Jericho").map((k) => k.word), [ "walls", "jericho" ])
  assert.deepEqual(keywords("   "), [])
})

test("stems match simple inflections", () => {
  assert.equal(stem("walls"), stem("wall"))
  assert.equal(stem("scourged"), stem("scourge"))
  assert.equal(stem("loveth"), stem("love"))
})

test("the rarest, best-covered verse ranks first", () => {
  const hits = searchVerses(records, "walls of jericho fell")
  assert.equal(hits[0].osis, "Josh")
  assert.equal(hits[0].chapter, 6)
  assert.equal(hits[0].num, 3) // wall + fell beat a lone "Jericho"
  assert.ok(hits.length >= 2)
})

test("verse numbers follow the chapter's first id offset (1-based)", () => {
  const [ hit ] = searchVerses(records, "God so loved the world")
  assert.deepEqual([ hit.osis, hit.chapter, hit.num ], [ "John", 3, 2 ])
})

test("modern words reach older wording through synonyms", () => {
  const hits = searchVerses(records, "Jesus beat some people")
  const refs = hits.map((h) => `${h.osis} ${h.chapter}:${h.num}`)
  assert.ok(refs.includes("Matt 1:1"), refs.join(", ")) // "smote"
  assert.ok(refs.includes("John 2:2"), refs.join(", ")) // "scourge"
})

test("no keywords, no results; limit is respected", () => {
  assert.deepEqual(searchVerses(records, "the and of"), [])
  assert.equal(searchVerses(records, "and", { limit: 1 }).length, 0)
  assert.equal(searchVerses(records, "jericho", { limit: 1 }).length, 1)
})
