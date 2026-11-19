import { test } from "node:test"
import assert from "node:assert/strict"
import { stepPlan, landingIndex, nearEdges, prefetchKey } from "../../app/javascript/lib/chapter_step.js"

// 1 Corinthians 14 has 40 verses: index 39 is 14:40.
const cor14 = { count: 40, prevRef: "1 Corinthians 13", nextRef: "1 Corinthians 15" }

test("Next inside a chapter moves by the group", () => {
  assert.deepEqual(stepPlan({ ...cor14, index: 38, direction: 1 }), { move: "verse", index: 39 })
  assert.deepEqual(stepPlan({ ...cor14, index: 10, group: 3, direction: 1 }), { move: "verse", index: 13 })
})

test("Next on the last verse carries on into the next chapter", () => {
  assert.deepEqual(stepPlan({ ...cor14, index: 39, direction: 1 }),
    { move: "chapter", reference: "1 Corinthians 15", land: "first" })
  // A group that already shows the last verse (39–40) also moves on.
  assert.deepEqual(stepPlan({ ...cor14, index: 38, group: 2, direction: 1 }).move, "chapter")
})

test("Next crosses books (Malachi 4:6 → Matthew 1) and stops after Revelation 22:21", () => {
  assert.deepEqual(stepPlan({ index: 5, count: 6, direction: 1, prevRef: "Malachi 3", nextRef: "Matthew 1" }),
    { move: "chapter", reference: "Matthew 1", land: "first" })
  assert.deepEqual(stepPlan({ index: 20, count: 21, direction: 1, prevRef: "Revelation 21", nextRef: null }), { move: "end" })
})

test("Prev on verse 1 goes back to the chapter before; Genesis 1:1 stays", () => {
  assert.deepEqual(stepPlan({ index: 0, count: 58, direction: -1, prevRef: "1 Corinthians 14", nextRef: "1 Corinthians 16" }),
    { move: "chapter", reference: "1 Corinthians 14", land: "last" })
  assert.deepEqual(stepPlan({ ...cor14, index: 2, group: 3, direction: -1 }), { move: "verse", index: 0 })
  assert.deepEqual(stepPlan({ index: 0, count: 31, direction: -1, prevRef: null, nextRef: "Genesis 2" }), { move: "start" })
})

test("landing: the first verse, or the last verses of the chapter", () => {
  assert.equal(landingIndex("first", 58), 0)
  assert.equal(landingIndex("last", 40), 39)
  assert.equal(landingIndex("last", 40, 2), 38)
  assert.equal(landingIndex("last", 1, 3), 0)
  assert.equal(landingIndex("last", 0), 0)
})

test("prefetch near either edge of the chapter", () => {
  assert.deepEqual(nearEdges({ index: 20, count: 40 }), { next: false, prev: false })
  assert.deepEqual(nearEdges({ index: 36, count: 40 }), { next: true, prev: false })
  assert.deepEqual(nearEdges({ index: 0, count: 40 }), { next: false, prev: true })
  assert.deepEqual(nearEdges({ index: 0, count: 2 }), { next: true, prev: true })
})

test("prefetch keys ignore case and spacing but not the translation", () => {
  assert.equal(prefetchKey(" 1 Corinthians  15 ", "3"), prefetchKey("1 corinthians 15", "3"))
  assert.notEqual(prefetchKey("1 Corinthians 15", "3"), prefetchKey("1 Corinthians 15", "4"))
})
