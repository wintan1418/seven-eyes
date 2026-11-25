import { test } from "node:test"
import assert from "node:assert/strict"
import {
  combineParts, combinedLabel, versesToText, textToVerses, emphasisParts, plainText, toggleMark, clipboardText
} from "../../app/javascript/lib/slides/combine.js"
import { setPages, pageText, setBody } from "../../app/javascript/lib/slides/scripture_set.js"

const BEAST1 = "And I stood upon the sand of the sea, and saw a beast rise up out of the sea, having seven heads and ten horns, and upon his horns ten crowns, and upon his heads the name of blasphemy."
const BEAST2 = "And I beheld another beast coming up out of the earth; and he had two horns like a lamb, and he spake as a dragon."
const rev = (n, text) => ({ bookName: "Revelation", chapter: 13, translation: "KJV", verses: [ { c: 13, n, text } ] })

test("Revelation 13:1 and 13:11 combine under one reference line", () => {
  const c = combineParts([ rev(1, BEAST1), rev(11, BEAST2) ])
  assert.equal(c.label, "Revelation 13:1, 11")
  assert.equal(c.translation, "KJV")
  assert.equal(c.multi, false)
  assert.deepEqual(c.verses.map((v) => v.n), [ 1, 11 ])
})

test("labels group book and chapter, and name mixed Bibles per part", () => {
  const parts = [
    { bookName: "Revelation", chapter: 13, translation: "KJV", verses: [ { n: 1 }, { n: 2 }, { n: 3 } ] },
    { bookName: "Revelation", chapter: 13, translation: "KJV", verses: [ { n: 11 } ] },
    { bookName: "Revelation", chapter: 17, translation: "KJV", verses: [ { n: 3 } ] },
    { bookName: "Daniel", chapter: 7, translation: "KJV", verses: [ { n: 3 } ] }
  ]
  assert.equal(combinedLabel(parts), "Revelation 13:1-3, 11; 17:3; Daniel 7:3")
  const mixed = [ rev(1, "a"), { bookName: "John", chapter: 3, translation: "BSB", verses: [ { n: 16, text: "b" } ] } ]
  const c = combineParts(mixed)
  assert.equal(c.translation, "")
  assert.equal(c.label, "Revelation 13:1 KJV; John 3:16 BSB")
  assert.equal(c.multi, true)
})

test("the editor's text goes back to verses; a line without a number joins the verse above", () => {
  const verses = [ { c: 13, n: 1, text: "first" }, { c: 13, n: 11, text: "second" } ]
  const text = versesToText(verses)
  assert.equal(text, "1 first\n11 second")
  assert.deepEqual(textToVerses(`${text}\nmore words`, { chapter: 13 }), [ { c: 13, n: 1, text: "first" }, { c: 13, n: 11, text: "second more words" } ])
  assert.equal(versesToText([ { c: 13, n: 1, text: "a" }, { c: 7, n: 3, text: "b" } ], { multi: true }), "13:1 a\n7:3 b")
  assert.deepEqual(textToVerses("13:1 a\n7:3 b"), [ { c: 13, n: 1, text: "a" }, { c: 7, n: 3, text: "b" } ])
  assert.deepEqual(textToVerses("no number here", { chapter: 2 }), [ { c: 2, n: 0, text: "no number here" } ])
})

test("emphasis marks: bold and highlight, dropped in plain text", () => {
  assert.deepEqual(emphasisParts("saw a **beast** rise, ==seven heads=="), [
    { text: "saw a ", em: null }, { text: "beast", em: "b" }, { text: " rise, ", em: null }, { text: "seven heads", em: "hl" }
  ])
  assert.equal(plainText("saw a **beast** rise, ==seven heads=="), "saw a beast rise, seven heads")
  assert.deepEqual(emphasisParts("2 * 3 == 6"), [ { text: "2 * 3 == 6", em: null } ])
})

test("toggling a mark on a selection, on the word at the caret, and off again", () => {
  const v = "11 And I beheld another beast coming"
  const at = v.indexOf("beast")
  let r = toggleMark(v, at, at + 5, "b")
  assert.equal(r.value, "11 And I beheld another **beast** coming")
  assert.equal(r.value.slice(r.start, r.end), "beast")
  r = toggleMark(r.value, r.start, r.end, "b")
  assert.equal(r.value, v)
  r = toggleMark(v, at + 2, at + 2, "hl") // caret inside the word
  assert.equal(r.value, "11 And I beheld another ==beast== coming")
  r = toggleMark(v, at - 1, at + 6, "hl") // spaces trimmed
  assert.equal(r.value, "11 And I beheld another ==beast== coming")
  r = toggleMark("a b\nc d", 2, 6, "b") // never across a line
  assert.equal(r.value, "a **b**\nc d")
})

test("a combined slide stays one slide, however long, and its plain text has no marks", () => {
  const long = Array.from({ length: 8 }, (_, i) => ({ c: 13, n: i + 1, text: `${BEAST1} **beast**` }))
  const data = { refs: [ { reference: "Revelation 13:1-8", label: "Revelation 13:1-8", translation: "KJV", verses: long } ], split: "one", combined: true }
  assert.equal(setPages(data).length, 1)
  assert.equal(setPages({ ...data, split: "auto" }).length > 1, true)
  assert.doesNotMatch(setBody(data), /\*\*/)
  const multi = { refs: [ { label: "Revelation 13:1; Daniel 7:3", translation: "KJV", verses: [ { c: 13, n: 1, text: "a" }, { c: 7, n: 3, text: "b" } ] } ], split: "one" }
  assert.equal(pageText(setPages(multi)[0], multi), "Revelation 13:1; Daniel 7:3 (KJV)\n13:1 a 7:3 b")
})

test("Copy: the reference, then the verses, no marks", () => {
  const c = combineParts([ rev(1, "saw a **beast**"), rev(11, "another ==beast==") ])
  assert.equal(clipboardText(c), "Revelation 13:1, 11 (KJV)\n1 saw a beast\n11 another beast")
})
