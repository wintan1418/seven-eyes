// node test/javascript/word_reveal_test.mjs
import assert from "node:assert/strict"
import { pickedWord, revealFor, placeCard } from "../../app/javascript/lib/word_reveal.js"

// One word, give or take punctuation and spaces.
assert.equal(pickedWord("loved"), "loved")
assert.equal(pickedWord(" loved, "), "loved")
assert.equal(pickedWord("“Light”"), "Light")
assert.equal(pickedWord("LORD’s"), "LORD’s")
assert.equal(pickedWord("so loved"), null)
assert.equal(pickedWord("16"), null)
assert.equal(pickedWord("a"), null)
assert.equal(pickedWord(""), null)

const john = {
  tokens: [ { w: "For", s: "G1063" }, { w: " God", s: "G2316" }, { w: " so", s: "G3779" }, { w: " loved", s: "G25" },
            { w: " the world", s: "G2889" }, { w: "." } ],
  entries: {
    G25: { s: "G25", lemma: "ἀγαπάω", translit: "agapáō", def: "to love (in a social or moral sense)", kjv: "(be-)love(-ed)", n: 143 },
    G2316: { s: "G2316", lemma: "θεός", translit: "theós", def: "a deity", kjv: "God", n: 1343 }
  }
}

const loved = revealFor(john, "loved")
assert.equal(loved.s, "G25")
assert.equal(loved.lang, "greek")
assert.equal(loved.language, "Greek")
assert.equal(loved.lemma, "ἀγαπάω")
assert.equal(loved.translit, "agapáō")
assert.equal(loved.say, "ah-gah-PAH-oh")
assert.match(loved.gloss, /love/)
assert.equal(loved.count, "143 times in the KJV")

// "world" sits inside a multi-word token; "God" matches regardless of case.
assert.equal(revealFor(john, "God").lemma, "θεός")
// An untagged word, a tagged word with no entry, or nothing to look in.
assert.equal(revealFor(john, "the"), null)
assert.equal(revealFor(john, "world"), null)
assert.equal(revealFor(null, "loved"), null)

// Hebrew: the familiar spelling and the stress from Strong's pron.
const gen = {
  tokens: [ { w: "In the beginning", s: "H7225" }, { w: " God", s: "H430" }, { w: " created", s: "H1254" } ],
  entries: { H1254: { s: "H1254", lemma: "בָּרָא", translit: "bârâʼ", pron: "baw-raw'", def: "(absolutely) to create", kjv: "create", n: 54 } }
}
const created = revealFor(gen, "created")
assert.equal(created.lang, "hebrew")
assert.equal(created.lemma, "בָּרָא")
assert.equal(created.translit, "bara")

// Placement: under the word, centred, inside the viewport.
const view = { width: 300, height: 160, viewWidth: 400, viewHeight: 800 }
let p = placeCard({ ...view, rect: { left: 180, width: 40, top: 300, bottom: 320 } })
assert.deepEqual(p, { left: 50, top: 330, below: true, arrow: 150 })
// Near the right edge: clamped, the arrow still points at the word.
p = placeCard({ ...view, rect: { left: 360, width: 30, top: 300, bottom: 320 } })
assert.equal(p.left, 88)
assert.equal(p.arrow, 282) // kept off the rounded corner
// No room below (a bottom bar takes 70px): flips above.
p = placeCard({ ...view, bottomInset: 70, rect: { left: 180, width: 40, top: 600, bottom: 620 } })
assert.equal(p.below, false)
assert.equal(p.top, 430)
// No room either way: stays below rather than off the top.
p = placeCard({ ...view, viewHeight: 300, rect: { left: 180, width: 40, top: 100, bottom: 120 } })
assert.equal(p.below, true)

console.log("word_reveal: ok")
