// node --test test/javascript — root-word projection's pure helpers
// (app/javascript/lib/root_words.js): the short meaning, the readable
// transliteration, the say-it guide, the offline pack's verse encoding and
// the word study a slide / queue item / phone carries.
import { test } from "node:test"
import assert from "node:assert/strict"
import {
  gloss, autoGloss, cleanDefinition, kjvRenderings, readableTranslit, simpleHebrew, sayIt, decodeVerse,
  verseWords, findWord, tokenForWord, buildWordStudy, normalizeWordStudy, encodeWordStudy, wordFromDetail,
  wordStudyTitle, wordStudyText, occurrencesLabel, languageOf
} from "../../app/javascript/lib/root_words.js"

test("hand-written glosses win for the words preachers explain most", () => {
  assert.equal(gloss({ s: "G25", def: "to love (in a social or moral sense)" }), "to love; to cherish and seek the good of another")
  assert.equal(gloss({ s: "h1254" }), "to create; to bring into being")
})

test("auto gloss: first clause, cross-references and qualifiers removed", () => {
  assert.equal(autoGloss({ s: "H1", def: "(absolutely) to create; (qualified) to cut down (a wood), select, feed" }), "to create")
  assert.equal(autoGloss({ s: "G1", def: "love, i.e. affection or benevolence; specially (plural) a love-feast" }), "love — affection or benevolence")
  // Open Scriptures put theos' head in the derivation; the definition only continues it.
  assert.equal(autoGloss({ s: "G2", def: "figuratively, a magistrate; by Hebraism, very",
                           deriv: "of uncertain affinity; a deity, especially (with G3588 (ὁ)) the supreme Divinity;" }),
               "a deity, especially the supreme Divinity")
  // ";" inside parentheses doesn't split; a long first clause loses its asides.
  assert.equal(autoGloss({ s: "G3", def: "graciousness (as gratifying), of manner or act (abstract or concrete; literal, figurative or spiritual; especially the divine influence upon the heart, and its reflection in the life; including gratitude)" }),
               "graciousness, of manner or act")
  assert.ok(autoGloss({ s: "G4", def: "x ".repeat(80) }).length <= 85)
  assert.equal(autoGloss({ s: "G5", def: "", kjv: "(be-)love(-ed), dear" }), "love, dear")
  assert.equal(cleanDefinition("from G3982 (πείθω); persuasion"), "from; persuasion")
})

test("KJV renderings without Strong's markup", () => {
  assert.deepEqual(kjvRenderings("(be-)love(-ed)"), [ "love" ])
  assert.deepEqual(kjvRenderings("(feast of) charity(-ably), dear, love"), [ "charity", "dear", "love" ])
  assert.deepEqual(kjvRenderings("angels, [idiom] exceeding, God (gods) (-dess, -ly), [idiom] (very) great, judges, [idiom] mighty."),
                   [ "angels", "exceeding", "God", "great", "judges", "mighty" ])
  assert.deepEqual(kjvRenderings("Jehovah, the Lord. Compare H3050 (יָהּ), H3069 (יְהֹוִה)."), [ "Jehovah", "the Lord" ])
})

test("Hebrew transliteration reads the familiar way", () => {
  assert.equal(simpleHebrew("bârâʼ"), "bara")
  assert.equal(simpleHebrew("ʼĕlôhîym"), "elohim")
  assert.equal(simpleHebrew("chêçêd"), "chesed")
  assert.equal(simpleHebrew("shâlôwm"), "shalom")
  assert.equal(simpleHebrew("Yᵉhôvâh"), "Yehovah")
  assert.equal(simpleHebrew("râʻâh"), "ra'ah")
  assert.equal(readableTranslit("agapáō", "G25"), "agapáō")
  assert.equal(readableTranslit("bârâʼ", "H1254"), "bara")
})

test("say-it guide: syllables, stress in capitals", () => {
  assert.equal(sayIt("agapáō", "G25"), "ah-gah-PAH-oh")
  assert.equal(sayIt("agápē", "G26"), "ah-GAH-pay")
  assert.equal(sayIt("cháris", "G5485"), "KHAH-ris")
  assert.equal(sayIt("eirḗnē", "G1515"), "ay-RAY-nay")
  assert.equal(sayIt("euangélion", "G2098"), "yoo-an-GEH-lee-ohn")
  assert.equal(sayIt("bârâʼ", "H1254", "baw-raw'"), "bah-RAH")
  assert.equal(sayIt("chêçêd", "H2617", "kheh'-sed"), "KHEH-sed")
  assert.equal(sayIt("ʼĕlôhîym", "H430", "el-o-heem'"), "eh-loh-HEEM")
  assert.equal(sayIt("shâmayim", "H8064", "shaw-mah'-yim"), "shah-MAH-yim")
  assert.equal(sayIt("tôwrâh", "H8451"), "toh-RAH") // no pron: last syllable, silent final h
  assert.equal(sayIt("", "G1"), "")
})

test("offline pack verses decode back to the tokens", () => {
  const tokens = decodeVerse("For@1063 God@2316 so@3779 loved@25 the world@2889, that@3754 he gave@1325.", "G")
  assert.deepEqual(tokens.slice(0, 2), [ { w: "For", s: "G1063" }, { w: " God", s: "G2316" } ])
  assert.deepEqual(tokens[tokens.length - 1], { w: "." })
  assert.equal(tokens.map((t) => t.w).join(""), "For God so loved the world, that he gave.")
  assert.deepEqual(decodeVerse("", "H"), [])
  const words = verseWords(tokens)
  assert.deepEqual(words.filter((w) => w.s).map((w) => w.text), [ "For", "God", "so", "loved", "the world", "that", "he gave" ])
  assert.equal(words.map((w) => w.text).join(""), "For God so loved the world, that he gave.")
})

test("finding the word in any translation's wording", () => {
  assert.deepEqual(findWord("For God so loved the world", "loved"), [ 11, 16 ])
  assert.deepEqual(findWord("his one and only Son", "only begotten"), [ 12, 16 ]) // falls back to a word of the phrase
  assert.equal(findWord("For God so loved", "hated"), null)
  const words = verseWords(decodeVerse("For@1063 God@2316 so@3779 loved@25 the world@2889", "G"))
  assert.equal(tokenForWord(words, "Loved,").s, "G25")
  assert.equal(tokenForWord(words, "world").s, "G2889")
  assert.equal(tokenForWord(words, "loves").s, "G25") // a near form in another translation
  assert.equal(tokenForWord(words, "xyz"), null)
})

test("a word study: built, titled, normalised, round-tripped", () => {
  const entry = { s: "G25", lemma: "ἀγαπάω", translit: "agapáō", def: "to love", kjv: "(be-)love(-ed)", n: 143 }
  const w = buildWordStudy({ entry, english: "loved", reference: "John 3:16", verse: "For God so loved the world", translation: "KJV" })
  assert.equal(w.lang, "greek")
  assert.equal(w.say, "ah-gah-PAH-oh")
  assert.deepEqual(w.mark, [ 11, 16 ])
  assert.equal(wordStudyTitle(w), "Word study: agapáō — John 3:16")
  assert.match(wordStudyText(w), /^ἀγαπάω \(agapáō\) G25\nsay: ah-gah-PAH-oh/)
  const round = normalizeWordStudy(encodeWordStudy(w))
  assert.deepEqual(round, normalizeWordStudy(w))
  assert.deepEqual(wordFromDetail({ itemKind: "word", body: encodeWordStudy(w) }), round)
  assert.equal(wordFromDetail({ itemKind: "song", body: "x" }), null)
  assert.equal(normalizeWordStudy({ s: "<script>" }), null)
  assert.equal(normalizeWordStudy("not json"), null)
  assert.equal(normalizeWordStudy({ ...w, mark: [ 5, 999 ] }).mark, null)
  assert.equal(normalizeWordStudy({ ...w, note: "n".repeat(900) }).note.length, 400)
  assert.equal(languageOf("H1254"), "hebrew")
  assert.equal(occurrencesLabel(143), "143 times in the KJV")
  assert.equal(occurrencesLabel(1), "once in the KJV")
})
