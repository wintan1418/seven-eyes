// Hold a word, see the original: the pure part of the reader's word reveal
// (no DOM, no network — test/javascript/word_reveal_test.mjs).
//
// A long-press on a phone (or a double-click) selects one word. When that word
// sits in a verse, the Hebrew or Greek behind it rises just below it: the
// original word, how to say it, and what it means. Any translation works —
// the word is matched against the verse's Strong's-tagged KJV tokens.
import { verseWords, tokenForWord, languageOf, languageLabel, readableTranslit, sayIt, gloss, occurrencesLabel } from "./root_words.js"

// The selected text as one word ("loved," → "loved"), or null when it is
// several words, a number or a single letter.
export function pickedWord(text) {
  const s = String(text || "").trim().replace(/^[^\p{L}]+|[^\p{L}]+$/gu, "")
  if (s.length < 2 || s.length > 30) return null
  return /^[\p{L}][\p{L}'’-]*$/u.test(s) ? s : null
}

// What the card shows for +word+ in a verse's root words ({ tokens, entries }),
// or null when the word isn't tagged ("the", "and") or its entry is missing.
export function revealFor(found, word) {
  if (!found || !word) return null
  const token = tokenForWord(verseWords(found.tokens), word)
  const entry = token && found.entries?.[token.s]
  if (!entry || !(entry.lemma || entry.translit)) return null
  const s = String(entry.s || token.s).toUpperCase()
  return {
    s,
    lang: languageOf(s),
    language: languageLabel(s),
    lemma: entry.lemma || "",
    translit: readableTranslit(entry.translit, s),
    say: sayIt(entry.translit, s, entry.pron),
    gloss: gloss({ ...entry, s }),
    english: word,
    count: occurrencesLabel(entry.n)
  }
}

// Where the card goes: centred under the word, flipped above when there is no
// room below (+bottomInset+ keeps clear of a bottom bar), held inside the
// viewport. arrow is the word's centre measured from the card's left edge.
export function placeCard({ rect, width, height, viewWidth, viewHeight, bottomInset = 0, gap = 10, pad = 12 }) {
  const centre = rect.left + rect.width / 2
  const maxLeft = Math.max(pad, viewWidth - width - pad)
  const left = Math.round(Math.min(maxLeft, Math.max(pad, centre - width / 2)))
  const roomBelow = viewHeight - bottomInset - rect.bottom - gap
  const below = roomBelow >= height || rect.top - gap - height < pad
  const top = Math.round(below ? rect.bottom + gap : rect.top - gap - height)
  const arrow = Math.round(Math.min(width - 18, Math.max(18, centre - left)))
  return { left, top, below, arrow }
}
