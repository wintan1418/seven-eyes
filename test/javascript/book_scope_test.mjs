import { test } from "node:test"
import assert from "node:assert/strict"
import { makeBookResolver, splitBookScope, bookOfReference } from "../../app/javascript/lib/book_scope.js"

// A slice of Bible::Canon (app/lib/bible/canon.rb), aliases as there.
const CANON = [
  { osis: "Gen", name: "Genesis", aliases: [ "ge", "gen", "gn" ] },
  { osis: "Job", name: "Job", aliases: [ "jb", "job" ] },
  { osis: "Ps", name: "Psalms", aliases: [ "ps", "psa", "psalm", "psalms", "pss" ] },
  { osis: "Song", name: "Song of Solomon", aliases: [ "song", "sos", "ss", "songofsolomon", "songofsongs", "canticles", "cant" ] },
  { osis: "Matt", name: "Matthew", aliases: [ "mt", "mat", "matt", "matthew" ] },
  { osis: "Mark", name: "Mark", aliases: [ "mk", "mar", "mrk", "mark" ] },
  { osis: "John", name: "John", aliases: [ "jn", "joh", "jhn", "john" ] },
  { osis: "1Cor", name: "1 Corinthians", aliases: [ "1cor", "1co", "1corinthians" ] },
  { osis: "Phil", name: "Philippians", aliases: [ "php", "phi", "phil", "philippians" ] },
  { osis: "Phlm", name: "Philemon", aliases: [ "phm", "phlm", "philem", "philemon" ] },
  { osis: "Heb", name: "Hebrews", aliases: [ "heb", "hebrews" ] },
  { osis: "1John", name: "1 John", aliases: [ "1john", "1jn", "1jo", "1jhn" ] },
  { osis: "Rev", name: "Revelation", aliases: [ "rev", "re", "rv", "revelation", "apocalypse" ] }
]
const resolve = makeBookResolver(CANON)
const scope = (text) => {
  const s = splitBookScope(text, resolve)
  return s && [ s.book.osis, s.words, s.explicit ]
}

test("a book, then words: search those words in that book", () => {
  assert.deepEqual(scope("heb heavenly jerusalem"), [ "Heb", "heavenly jerusalem", false ])
  assert.deepEqual(scope("Hebrews heavenly Jerusalem"), [ "Heb", "heavenly Jerusalem", false ])
  assert.deepEqual(scope("  hebrews   heavenly  jerusalem "), [ "Heb", "heavenly jerusalem", false ])
  assert.deepEqual(scope("rev little book"), [ "Rev", "little book", false ])
})

test("a colon makes it explicit and forgives a typo", () => {
  assert.deepEqual(scope("hebrews: heavenly jerusalem"), [ "Heb", "heavenly jerusalem", true ])
  assert.deepEqual(scope("heb : jerusalem"), [ "Heb", "jerusalem", true ])
  assert.deepEqual(scope("hebrwes: jerusalem"), [ "Heb", "jerusalem", true ])
})

test("numbered and several-word books", () => {
  assert.deepEqual(scope("1 cor love suffereth"), [ "1Cor", "love suffereth", false ])
  assert.deepEqual(scope("1cor charity"), [ "1Cor", "charity", false ])
  assert.deepEqual(scope("1 john little children"), [ "1John", "little children", false ])
  assert.deepEqual(scope("song of solomon rose of sharon"), [ "Song", "rose of sharon", false ])
})

test("references are left alone", () => {
  assert.equal(scope("heb 12"), null)
  assert.equal(scope("john 3:16"), null)
  assert.equal(scope("1 cor 13:4-7"), null)
  assert.equal(scope("hebrews"), null)
  assert.equal(scope(""), null)
})

test("ordinary words aren't taken for books", () => {
  assert.equal(scope("son of man"), null) // not Song of Solomon
  assert.equal(scope("the lamb of god"), null)
  assert.equal(scope("heavenly jerusalem"), null)
  assert.equal(scope("ph grace"), null) // two letters, no colon: too loose
})

test("ambiguous prefixes need more letters", () => {
  assert.deepEqual(resolve("phil"), resolve("philippians")) // an alias
  assert.equal(resolve("phile")?.osis, "Phlm")
  assert.equal(resolve("hebr")?.osis, "Heb")
  assert.equal(resolve("he"), null)
})

test("the book of a live reference", () => {
  assert.equal(bookOfReference("Hebrews 12", resolve)?.osis, "Heb")
  assert.equal(bookOfReference("1 Corinthians 13:4", resolve)?.osis, "1Cor")
  assert.equal(bookOfReference("Song of Solomon 2", resolve)?.osis, "Song")
  assert.equal(bookOfReference("", resolve), null)
})
