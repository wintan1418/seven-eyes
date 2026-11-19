// node --test test/javascript — "Paste your own" verses: tidying what pastors
// copy out of YouVersion, Bible Gateway, Blue Letter Bible (NKJV / NIV / AMP…)
// into verses for a scripture slide.
import { test } from "node:test"
import assert from "node:assert/strict"
import { makeParser } from "../../app/javascript/lib/offline/reference_parser.js"
import { cleanPaste, splitPasted, checkSize, cleanVersion, versesText, chunkSentences, MAX_VERSES } from "../../app/javascript/lib/slides/paste_verses.js"
import { setPages, pageText, withDefaults } from "../../app/javascript/lib/slides/scripture_set.js"

const parse = makeParser([
  { osis: "John", name: "John", chapters: 21, aliases: [ "Jn", "Jhn" ] },
  { osis: "Ps", name: "Psalms", chapters: 150, aliases: [ "Psalm", "Psa" ] },
  { osis: "Rom", name: "Romans", chapters: 16, aliases: [ "Rom" ] },
  { osis: "Phil", name: "Philippians", chapters: 4, aliases: [ "Php" ] },
  { osis: "Isa", name: "Isaiah", chapters: 66, aliases: [ "Isa" ] },
  { osis: "1Cor", name: "1 Corinthians", chapters: 16, aliases: [ "1 Cor" ] }
])
const nums = (r) => r.verses.map((v) => v.n)
const words = (r) => r.verses.map((v) => v.text)

test("Bible Gateway NKJV with verse numbers, headings, footnote marks and the copyright footer", () => {
  const paste = `John 3:16-18 New King James Version

16 For God so loved the world that He gave His only begotten[a] Son, that whoever believes in Him should not perish but have everlasting life.(A) 17 For God did not send His Son into the world to condemn the world, but that the world through Him might be saved.
18 “He who believes in Him is not condemned; but he who does not believe is condemned already, because he has not believed in the name of the only begotten Son of God.

Read full chapter
Footnotes
John 3:16 Or unique
New King James Version (NKJV)
Scripture taken from the New King James Version®. Copyright © 1982 by Thomas Nelson. Used by permission. All rights reserved.`
  const r = splitPasted(paste, { parse })
  assert.equal(r.reference, "John 3:16-18")
  assert.equal(r.version, "NKJV")
  assert.deepEqual(nums(r), [ 16, 17, 18 ])
  assert.equal(r.verses[0].c, 3)
  assert.equal(r.verses[0].text, "For God so loved the world that He gave His only begotten Son, that whoever believes in Him should not perish but have everlasting life.")
  assert.match(r.verses[2].text, /^“He who believes/)
  assert.ok(!words(r).join(" ").match(/Copyright|Read full|Footnotes|unique/))
})

test("Bible Gateway NIV inline numbers; a number inside a verse (40 days) is not a verse", () => {
  const paste = `1 Then Jesus was led by the Spirit into the wilderness to be tempted by the devil. 2 After fasting 40 days and 40 nights, he was hungry. 3 The tempter came to him and said, “If you are the Son of God, tell these stones to become bread.”
New International Version (NIV)
Holy Bible, New International Version®, NIV® Copyright ©1973, 1978, 1984, 2011 by Biblica, Inc.® Used by permission. All rights reserved worldwide.`
  const r = splitPasted(paste, { start: { c: 4, n: 1 } })
  assert.deepEqual(nums(r), [ 1, 2, 3 ])
  assert.equal(r.verses[1].text, "After fasting 40 days and 40 nights, he was hungry.")
  assert.equal(r.version, "NIV")
})

test("AMP keeps its own [amplified] words but drops Bible Gateway's stuck-on footnote marks", () => {
  const paste = `16 “For God so [greatly] loved and dearly prized the world, that He [even] gave His [One and] only begotten Son, so that whoever believes and trusts in Him [as Savior] shall not perish, but have eternal life.[a] 17 For God did not send the Son into the world to judge and condemn the world [that is, to initiate the final judgment of the world], but that the world might be saved through Him.
Amplified Bible (AMP)
Copyright © 2015 by The Lockman Foundation, La Habra, CA 90631. All rights reserved.`
  const r = splitPasted(paste, { start: { c: 3, n: 16 } })
  assert.deepEqual(nums(r), [ 16, 17 ])
  assert.match(r.verses[0].text, /\[greatly\] loved/)
  assert.match(r.verses[0].text, /eternal life\.$/)
  assert.match(r.verses[1].text, /\[that is, to initiate/)
  assert.equal(r.version, "AMP")
})

test("YouVersion share text: no numbers, quotes, reference + version + bible.com link", () => {
  const paste = "“For God so loved the world that He gave His only begotten Son, that whoever believes in Him should not perish but have everlasting life.” ‭‭John‬ ‭3‬:‭16‬ ‭NKJV‬‬\nhttps://bible.com/bible/114/jhn.3.16.NKJV"
  const r = splitPasted(paste, { parse })
  assert.equal(r.reference, "John 3:16")
  assert.equal(r.version, "NKJV")
  assert.equal(r.verses.length, 1)
  assert.equal(r.verses[0].text, "For God so loved the world that He gave His only begotten Son, that whoever believes in Him should not perish but have everlasting life.")
  assert.ok(!r.numbered)
})

test("YouVersion several verses (no numbers) become sentence slides without numbers", () => {
  const paste = "“Be anxious for nothing, but in everything by prayer and supplication, with thanksgiving, let your requests be made known to God; and the peace of God, which surpasses all understanding, will guard your hearts and minds through Christ Jesus.” Philippians 4:6-7 NKJV\nhttps://bible.com/bible/114/php.4.6-7.NKJV"
  const r = splitPasted(paste, { parse })
  assert.equal(r.reference, "Philippians 4:6-7")
  assert.ok(r.verses.length >= 1)
  assert.ok(r.verses.every((v) => v.n === 0))
  assert.ok(!words(r).join(" ").includes("bible.com"))
})

test("YouVersion's bible.com header form: reference + version line first", () => {
  const paste = "Romans 8:28 NIV\nAnd we know that in all things God works for the good of those who love him, who have been called according to his purpose.\nhttps://bible.com/bible/111/rom.8.28.NIV"
  const r = splitPasted(paste, { parse, start: { c: 8, n: 28, single: true } })
  assert.equal(r.reference, "Romans 8:28")
  assert.equal(r.version, "NIV")
  assert.deepEqual(nums(r), [ 28 ])
  assert.match(r.verses[0].text, /^And we know/)
})

test("one verse per line, numbers with a dot, poetry lines join their verse", () => {
  const paste = `1. The LORD is my shepherd;
I shall not want.
2. He makes me to lie down in green pastures;
He leads me beside the still waters.
3. He restores my soul;`
  const r = splitPasted(paste)
  assert.deepEqual(nums(r), [ 1, 2, 3 ])
  assert.equal(r.verses[0].text, "The LORD is my shepherd; I shall not want.")
})

test("[16] bracketed numbers", () => {
  const r = splitPasted("[16] For God so loved the world. [17] For God did not send His Son. [18] He who believes is not condemned.")
  assert.deepEqual(nums(r), [ 16, 17, 18 ])
  assert.equal(r.verses[2].text, "He who believes is not condemned.")
})

test("superscript verse numbers stuck to the words", () => {
  const r = splitPasted("¹⁶For God so loved the world… ¹⁷For God did not send His Son into the world to condemn the world.")
  assert.deepEqual(nums(r), [ 16, 17 ])
  assert.equal(r.verses[0].text, "For God so loved the world…")
})

test("Blue Letter Bible: “Jhn 3:16 - …” per line", () => {
  const paste = `Jhn 3:16 - For God so loved the world, that he gave his only begotten Son.
Jhn 3:17 - For God sent not his Son into the world to condemn the world.`
  const r = splitPasted(paste)
  assert.deepEqual(nums(r), [ 16, 17 ])
  assert.equal(r.verses[1].text, "For God sent not his Son into the world to condemn the world.")
})

test("“John 3:16 For God…” per line (no dash)", () => {
  const r = splitPasted("John 3:16 For God so loved the world.\nJohn 3:17 For God did not send His Son.")
  assert.deepEqual(nums(r), [ 16, 17 ])
})

test("Bible Gateway prints the chapter number in place of verse 1", () => {
  const paste = "3 There was a man of the Pharisees named Nicodemus, a ruler of the Jews. 2 This man came to Jesus by night. 3 Jesus answered and said to him, “Most assuredly, I say to you.”"
  const r = splitPasted(paste, { start: { c: 3, n: 1 } })
  assert.deepEqual(nums(r), [ 1, 2, 3 ])
  assert.match(r.verses[0].text, /^There was a man/)
})

test("a section heading between verses is dropped", () => {
  const paste = "15 that whoever believes in Him should not perish but have eternal life.\nThe Gift of God\n16 For God so loved the world."
  const r = splitPasted(paste)
  assert.deepEqual(nums(r), [ 15, 16 ])
  assert.equal(r.verses[0].text, "that whoever believes in Him should not perish but have eternal life.")
})

test("crossing a chapter", () => {
  const r = splitPasted("5 Weeping may endure for a night. 6 Now in my prosperity I said. 1 Another chapter begins here. 2 And goes on.", { start: { c: 30, n: 5 } })
  assert.deepEqual(r.verses.map((v) => [ v.c, v.n ]), [ [ 30, 5 ], [ 30, 6 ], [ 31, 1 ], [ 31, 2 ] ])
})

test("plain text with no numbers splits at sentences into slide-sized pieces", () => {
  const long = Array.from({ length: 8 }, (_, i) => `This is sentence number ${i + 1} of a long reading that goes on for a while.`).join(" ")
  const r = splitPasted(long)
  assert.ok(r.verses.length > 1)
  assert.ok(r.verses.every((v) => v.text.length <= 520 && v.n === 0))
  assert.equal(r.verses.map((v) => v.text).join(" "), long)
})

test("one very long sentence is still cut", () => {
  const chunks = chunkSentences(Array.from({ length: 80 }, () => "and the word").join(", "))
  assert.ok(chunks.length > 1)
})

test("invisible characters and URLs are stripped; junk-only paste is empty", () => {
  assert.deepEqual(splitPasted("https://www.biblegateway.com/passage/?search=John+3\nRead full chapter").verses, [])
  assert.equal(cleanPaste("Fo​r God‬ so loved").text, "For God so loved")
})

test("version labels are tidied", () => {
  assert.equal(cleanVersion(" nkjv "), "NKJV")
  assert.equal(cleanVersion("<script>TPT"), "SCRIPTTPT".slice(0, 12))
  assert.equal(cleanVersion("Passion Translation 2020"), "PASSION TRAN")
})

test("size limits are friendly", () => {
  assert.equal(checkSize([ { text: "a" } ]), null)
  assert.match(checkSize(Array.from({ length: MAX_VERSES + 1 }, () => ({ text: "x" }))), /up to 200/)
  assert.match(checkSize([ { text: "x".repeat(41_000) } ]), /too long/)
})

test("versesText rebuilds the paste for editing", () => {
  assert.equal(versesText([ { n: 16, text: "A." }, { n: 0, text: "B." } ]), "16 A.\nB.")
})

test("slides: one verse per slide, N per slide, numbers hidden for unnumbered pieces, version in the ref line", () => {
  const data = { refs: [ { reference: "John 3:16-18", label: "John 3:16-18", translation: "NKJV", own: true,
    verses: [ { c: 3, n: 16, text: "A." }, { c: 3, n: 17, text: "B." }, { c: 3, n: 18, text: "C." } ] } ], per_slide: 1 }
  assert.equal(setPages(data).length, 3)
  // Each slide names its own verses, not "(cont.)".
  assert.equal(pageText(setPages(data)[1], data), "John 3:17 (NKJV)\n17 B.")
  assert.deepEqual(setPages({ ...data, per_slide: 2 }).map((p) => p.blocks[0].label), [ "John 3:16-17", "John 3:18" ])
  assert.equal(setPages({ ...data, per_slide: 2 }).length, 2)
  assert.equal(setPages({ ...data, per_slide: 0 }).length, 1)
  const plain = { refs: [ { ...data.refs[0], verses: [ { c: 3, n: 0, text: "Words." } ] } ] }
  assert.equal(pageText(setPages(plain)[0], plain), "John 3:16-18 (NKJV)\nWords.")
  assert.equal(withDefaults({}).per_slide, 0)
})
