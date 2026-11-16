// node test/javascript/scripture_scenes_test.mjs
import assert from "node:assert/strict"
import { sceneFor, indexScenes, CARRY } from "../../app/javascript/lib/scripture_scenes.js"
import { readFileSync } from "node:fs"

const scenes = [
  { key: "gen-01-light", osis: "Gen", chapter: 1, verse: 3 },
  { key: "gen-02-eve", osis: "Gen", chapter: 2, verse: 22 },
  { key: "gen-03-tempt", osis: "Gen", chapter: 3, verse: 6 },
  { key: "gen-03-driven", osis: "Gen", chapter: 3, verse: 24 },
  { key: "gen-04-offer", osis: "Gen", chapter: 4, verse: 4 },
  { key: "gen-04-slay", osis: "Gen", chapter: 4, verse: 8 },
  { key: "gen-07-flood", osis: "Gen", chapter: 7, verse: null },
  { key: "rev-21-jerusalem", osis: "Rev", chapter: 21, verse: 10 }
]
const idx = indexScenes(scenes)
const key = (...a) => sceneFor(idx, ...a)?.key ?? null

// In a chapter with plates: the one at or before the verse being read.
assert.equal(key("Gen", 3), "gen-03-tempt")
assert.equal(key("Gen", 3, 1), "gen-03-tempt") // above the first plate: still this chapter's
assert.equal(key("Gen", 3, 10), "gen-03-tempt")
assert.equal(key("Gen", 3, 24), "gen-03-driven")
assert.equal(key("Gen", 4, 8), "gen-04-slay")
assert.equal(key("Gen", 4, 16), "gen-04-slay")
// Chapters between plates carry the last scene a little way…
assert.equal(key("Gen", 5), "gen-04-slay")
assert.equal(key("Gen", 4 + CARRY), "gen-07-flood") // chapter 7 has its own
assert.equal(key("Gen", 7 + CARRY), "gen-07-flood")
// …but not forever, and not before a book's first plate, nor in books without one.
assert.equal(key("Gen", 7 + CARRY + 1), null)
assert.equal(key("Rev", 1), null)
assert.equal(key("Rev", 22), "rev-21-jerusalem")
assert.equal(key("Phlm", 1), null)
assert.equal(key("Gen", null), null)
// The array form works too.
assert.equal(sceneFor(scenes, "Gen", 1)?.key, "gen-01-light")

// The bundled data matches its source and every picture exists.
const data = JSON.parse(readFileSync(new URL("../../app/javascript/lib/scripture_scenes.json", import.meta.url)))
assert.ok(Array.isArray(data) && data.length > 50, "scripture_scenes.json has the plates")
for (const s of data) {
  assert.ok(s.key && s.osis && Number.isInteger(s.chapter), `scene ${JSON.stringify(s)}`)
  readFileSync(new URL(`../../public/scenes/${s.key}.webp`, import.meta.url)) // throws if missing
}
console.log("scripture_scenes: ok")
