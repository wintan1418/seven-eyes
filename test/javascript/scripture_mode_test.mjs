// node --test test/javascript — the Auto | Reference | Words switch
// (app/javascript/lib/scripture_mode.js) and the parser reading what
// Reference mode hands it.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readMode, saveMode, modeForKey, tidyReference, validMode, MODE_KEY } from "../../app/javascript/lib/scripture_mode.js"
import { rankVerses } from "../../app/javascript/lib/scripture_search.js"

function memory() {
  const m = new Map()
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), m }
}

test("auto by default; the last choice is remembered; junk falls back to auto", () => {
  const s = memory()
  assert.equal(readMode(s), "auto")
  assert.equal(saveMode("words", s), "words")
  assert.equal(readMode(s), "words")
  s.setItem(MODE_KEY, "nonsense")
  assert.equal(readMode(s), "auto")
  assert.equal(validMode("reference"), "reference")
})

test("storage that throws (private window) still answers", () => {
  const broken = { getItem() { throw new Error("denied") }, setItem() { throw new Error("denied") } }
  assert.equal(readMode(broken), "auto")
  assert.equal(saveMode("reference", broken), "reference")
})

test("Alt+A / Alt+R / Alt+W by key position; other keys and chords are ignored", () => {
  assert.equal(modeForKey({ altKey: true, code: "KeyR" }), "reference")
  assert.equal(modeForKey({ altKey: true, code: "KeyW" }), "words")
  assert.equal(modeForKey({ altKey: true, code: "KeyA" }), "auto")
  assert.equal(modeForKey({ altKey: false, code: "KeyR" }), null)
  assert.equal(modeForKey({ altKey: true, ctrlKey: true, code: "KeyR" }), null)
  assert.equal(modeForKey({ altKey: true, code: "KeyX" }), null)
})

test("tidyReference turns a letter O against a number into a zero, nothing else", () => {
  assert.equal(tidyReference("JOHN 1O:30"), "JOHN 10:30")
  assert.equal(tidyReference("ps 1oo"), "ps 100")
  assert.equal(tidyReference("john 3:O1"), "john 3:01")
  assert.equal(tidyReference("1co13:4-7"), "1co13:4-7")
  assert.equal(tidyReference("hos 1"), "hos 1")
  assert.equal(tidyReference("  jn   3 16 "), "jn 3 16")
})

test("words: a verse holding every typed word (small ones too) leads its tier", () => {
  const records = [
    { osis: "Gen", chapters: Object.assign([], { 1: { t: [ "Therefore shall a man leave his father and his mother: and they shall be one flesh." ] } }) },
    { osis: "John", chapters: Object.assign([], { 9: { t: [ "I and my Father are one." ] } }) }
  ]
  const order = new Map([ [ "Gen", 1 ], [ "John", 43 ] ])
  const { hits } = rankVerses(records, "I AND MY FATHER ONE", { order })
  assert.deepEqual(hits.map((h) => `${h.osis} ${h.chapter}:${h.num}`), [ "John 10:1", "Gen 2:1" ])
  assert.equal(hits[0].exact, undefined, "the flag stays internal")
  // Only the keywords typed: Bible order, as before.
  assert.equal(rankVerses(records, "father one", { order }).hits[0].osis, "Gen")
})
