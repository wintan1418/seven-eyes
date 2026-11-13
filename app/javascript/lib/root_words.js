// Root words (Strong's) for preach mode — the pure part: no DOM, no network,
// so node can test it (test/javascript/root_words_test.mjs).
//
//   "The Greek word here is agapē, which means…" — the operator picks an
//   English word in the live verse; we look up its Strong's entry and project
//   the original word, a readable transliteration, a say-it guide and a short
//   meaning. The raw Strong's text (Open Scriptures, public domain) is long and
//   uneven, so the short meaning is derived here (or taken from a small list of
//   hand-written glosses for the words preachers reach for most).
//
// Entry shape (server JSON and the offline word pack decode to the same):
//   { s: "G25", lemma: "ἀγαπάω", translit: "agapáō", pron: "", def: "…",
//     kjv: "(be-)love(-ed)", deriv: "…", n: 143 }
//
// A word study (what a slide, a queue item and a live phone carry):
//   { v: 1, s, lang: "greek"|"hebrew", lemma, translit, say, gloss, english,
//     reference, verse, translation, mark: [start, end] | null, layout:
//     "verse"|"word", note, n }

export const WORD_STUDY_VERSION = 1

// Hand-written short glosses: what the word means, in a line a congregation
// reads at a glance. Only for the words preachers explain most; everything
// else is derived from the lexicon by autoGloss().
export const GLOSSES = {
  G25: "to love; to cherish and seek the good of another",
  G26: "love; goodwill that seeks another's good",
  G5368: "to love as a friend; to be fond of",
  G5485: "grace; favour freely given, undeserved kindness",
  G4102: "faith; trust, firm conviction, faithfulness",
  G4100: "to believe; to trust in, rely on",
  G1515: "peace; wholeness, harmony, rest",
  G3056: "word; a message, reasoned speech",
  G4151: "spirit; breath, wind",
  G1411: "power; mighty ability, a mighty work",
  G1577: "assembly; those called out — the church",
  G2842: "fellowship; sharing, partnership",
  G3341: "repentance; a change of mind and direction",
  G3340: "to repent; to change one's mind and turn",
  G4991: "salvation; rescue, deliverance, safety",
  G4982: "to save; to rescue, heal, make whole",
  G1343: "righteousness; being right, justice",
  G1344: "to justify; to declare righteous",
  G40: "holy; set apart for God",
  G1391: "glory; splendour, honour, praise",
  G2222: "life; life in its fullness",
  G2889: "world; the ordered universe, humanity",
  G2098: "gospel; good news",
  G3875: "helper; one called alongside — advocate, comforter",
  G266: "sin; missing the mark",
  G859: "forgiveness; release, pardon",
  G863: "to forgive; to release, let go, send away",
  G1680: "hope; confident expectation",
  G5287: "substance; assurance, firm foundation",
  G3439: "only, unique; one of a kind",
  G2316: "God; a god — with the article, the one true God",
  G2962: "Lord; master, owner",
  G5547: "Christ; the Anointed One, the Messiah",
  G166: "eternal; everlasting, of the age to come",
  G3101: "disciple; learner, follower",
  G5590: "soul; life, the self",
  G4561: "flesh; the body, human nature",
  G2588: "heart; the inner self — mind, will, affections",
  G3339: "to transform; to be changed in form",
  G5207: "son; descendant, heir",
  G3962: "father",
  G932: "kingdom; reign, royal rule",
  G4352: "to worship; to bow down in reverence",
  G3870: "to encourage; to call alongside, comfort, urge",
  G1922: "full knowledge; recognition",
  G1097: "to know; to come to know by experience",
  G3306: "to abide; to remain, stay, dwell",
  G5046: "perfect; complete, mature",
  G5055: "to finish; to bring to completion",
  G4416: "firstborn; pre-eminent heir",
  G386: "resurrection; a rising up",
  G4716: "cross",
  G129: "blood",
  G2434: "atoning sacrifice; propitiation",
  G5281: "endurance; steadfast perseverance",
  H430: "God; the Mighty One",
  H3068: "the LORD; God's covenant name",
  H136: "Lord; Master",
  H1254: "to create; to bring into being",
  H2617: "steadfast love; loyal covenant kindness, mercy",
  H7965: "peace; wholeness, well-being, completeness",
  H7307: "spirit; breath, wind",
  H5315: "soul; life, living being, self",
  H3820: "heart; the inner person — mind, will, feeling",
  H3824: "heart; the inner person — mind, will, feeling",
  H8451: "law; instruction, teaching",
  H6944: "holiness; something set apart",
  H6918: "holy; set apart, sacred",
  H3519: "glory; weight, honour, splendour",
  H539: "to believe; to be firm, trustworthy, faithful",
  H530: "faithfulness; firmness, steadiness",
  H571: "truth; faithfulness, reliability",
  H3444: "salvation; deliverance, victory",
  H3467: "to save; to deliver, rescue",
  H7725: "to turn back; to return, repent, restore",
  H1285: "covenant; a binding agreement",
  H6664: "righteousness; what is right and just",
  H6666: "righteousness; justice, right conduct",
  H4941: "justice; judgment, a right ruling",
  H2580: "grace; favour",
  H7356: "compassion; tender mercies",
  H8085: "to hear; to listen and obey",
  H3045: "to know; to know by experience, intimately",
  H3372: "to fear; to revere, stand in awe",
  H1288: "to bless; to kneel, praise",
  H1293: "blessing",
  H7225: "beginning; the first, the best part",
  H8064: "heaven; the sky, the heavens",
  H776: "earth; land, country",
  H4899: "anointed; messiah",
  H5650: "servant; slave, worshipper",
  H2896: "good; pleasant, beautiful, right",
  H157: "to love",
  H160: "love",
  H3477: "upright; straight, right",
  H7462: "to shepherd; to tend, feed",
  H7999: "to be complete; to make whole, repay",
  H2403: "sin; a sin offering",
  H5771: "iniquity; guilt, perversity",
  H3722: "to atone; to cover, make reconciliation",
  H5162: "to comfort; to be sorry, relent",
  H982: "to trust; to feel secure, rely on",
  H6960: "to wait for; to hope, look eagerly",
  H2421: "to live; to revive, keep alive",
  H2416: "living; alive, life",
  H8034: "name; reputation, renown",
  H6635: "host; army — the LORD of hosts",
  H6942: "to sanctify; to make or keep holy"
}

const GLOSS_MAX = 84
const CONTINUATION = /^(?:figuratively|by implication|by extension|specially|specifically|also|by hebraism|or)\b/i

export const languageOf = (strongs) => (/^H/i.test(String(strongs || "")) ? "hebrew" : "greek")
export const languageLabel = (strongs) => (languageOf(strongs) === "hebrew" ? "Hebrew" : "Greek")

// Strip Strong's cross-references ("G3588 (ὁ)", "(with G3588 (ὁ))"), leading
// qualifiers ("(absolutely) "), and tidy spacing/punctuation.
export function cleanDefinition(text) {
  let s = String(text || "")
  s = s.replace(/\((?:[^()]|\([^()]*\))*[GH]\d+(?:[^()]|\([^()]*\))*\)/g, "") // a parenthetical naming another entry
  s = s.replace(/\b[GH]\d+\s*\([^)]*\)/g, "").replace(/\b[GH]\d+\b/g, "")
  s = s.replace(/\(\s*\)/g, "")
  s = s.replace(/,?\s*i\.\s?e\.\s*/g, " — ")
  s = s.replace(/^\s*(?:\([^)]*\)\s*)+/, "") // "(absolutely) to create"
  s = s.replace(/\s*;\s*\([^)]*\)\s*/g, "; ") // "; (qualified) …"
  s = s.replace(/^\s*properly,\s*/i, "")
  s = s.replace(/\s+/g, " ").replace(/\s+([,;:.)])/g, "$1").replace(/\(\s+/g, "(")
  return s.trim().replace(/^[—,;:\s]+/, "").replace(/[—,;:\s]+$/, "")
}

// The concise meaning: a hand-written gloss, else the first clause of the
// Strong's definition (borrowing its head from the derivation when Open
// Scriptures split the sentence there, e.g. G2316 theos).
export function gloss(entry) {
  if (!entry) return ""
  const curated = GLOSSES[String(entry.s || "").toUpperCase()]
  if (curated) return curated
  return autoGloss(entry)
}

export function autoGloss(entry) {
  let def = cleanDefinition(entry.def)
  if (!def || CONTINUATION.test(def)) {
    const tail = String(entry.deriv || "").split(";").slice(1).join(";")
    const head = cleanDefinition(tail)
    if (head && /[a-z]/i.test(head)) def = def ? `${head}; ${def}` : head
  }
  if (!def) return kjvRenderings(entry.kjv).slice(0, 4).join(", ")
  const clauses = splitClauses(def)
  let first = clauses.find((c) => c && !CONTINUATION.test(c)) || clauses[0]
  if (first.length > GLOSS_MAX) {
    const bare = cleanDefinition(first.replace(/\([^()]*\)/g, ""))
    if (bare) first = bare
  }
  return truncateWords(first, GLOSS_MAX)
}

// "How the KJV translates it": the renderings from kjv_def, without Strong's
// markup ("[idiom]", "X", "+", "(-ed)", "(be-)"), most useful first.
export function kjvRenderings(kjv, limit = 6) {
  let s = String(kjv || "")
  s = s.replace(/\bCompare\b.*$/i, "")
  s = s.replace(/\[(?:idiom|phrase)\]/gi, "").replace(/(^|[\s,(])[X×+](?=\s)/g, "$1")
  for (let i = 0; i < 3; i++) s = s.replace(/\([^()]*\)/g, "") // nested hints, innermost first
  const seen = new Set()
  const out = []
  s.split(/[,;]/).forEach((part) => {
    const word = part.replace(/-\s*$/g, "").replace(/\s+/g, " ").replace(/^[\s.\-]+|[\s.\-]+$/g, "").trim()
    if (word.length < 2 || !/[a-z]/i.test(word)) return
    const key = word.toLowerCase()
    if (seen.has(key)) return
    seen.add(key)
    out.push(word)
  })
  return out.slice(0, limit)
}

// Split on ";" outside parentheses.
function splitClauses(text) {
  const out = []
  let depth = 0
  let cur = ""
  for (const ch of String(text || "")) {
    if (ch === "(") depth++
    if (ch === ")") depth = Math.max(0, depth - 1)
    if (ch === ";" && depth === 0) { out.push(cur.trim()); cur = ""; continue }
    cur += ch
  }
  out.push(cur.trim())
  return out.filter(Boolean)
}

function truncateWords(text, max) {
  const s = String(text || "").trim()
  if (s.length <= max) return s
  const cut = s.slice(0, max + 1)
  const at = cut.lastIndexOf(" ")
  return `${(at > max * 0.6 ? cut.slice(0, at) : s.slice(0, max)).replace(/[,;:\s—]+$/, "")}…`
}

// ---- transliteration ----------------------------------------------------------

// A readable transliteration. Greek keeps its accents (agapáō — the accent is
// the stress); Strong's Hebrew transliteration (ʼĕlôhîym, chêçêd, shâlôwm) is
// reduced to the familiar spelling (elohim, chesed, shalom).
export function readableTranslit(translit, strongs) {
  const t = String(translit || "").trim()
  if (!t) return ""
  return languageOf(strongs) === "hebrew" ? simpleHebrew(t) : t.normalize("NFC")
}

export function simpleHebrew(xlit) {
  let s = String(xlit || "").normalize("NFD")
  s = s.replace(/c\u0327/g, "s").replace(/C\u0327/g, "S") // ç = samekh
  s = s.replace(/\u1D49/g, "e").replace(/\u1D43/g, "a").replace(/\u1D52/g, "o") // superscript (reduced) vowels
  s = s.replace(/i\u0302y/g, "i").replace(/o\u0302w/g, "o").replace(/u\u0302w/g, "u") // îy ôw ûw: long vowels
  // aleph / ayin marks: an apostrophe between vowels (ra'ah), else nothing
  s = s.replace(/([aeiou][\u0300-\u036f]*)[\u02BC\u02BB\u02BD\u02BE\u02BF\u2018\u2019'`](?=[aeiou])/gi, "$1'")
  s = s.replace(/[\u02BC\u02BB\u02BD\u02BE\u02BF\u2018\u2019`]/g, "")
  s = s.replace(/[\u0300-\u036f]/g, "")
  s = s.replace(/\s+/g, " ").trim()
  return s
}

// Greek without diacritics, macrons kept (ē, ō) — the base for the say-it guide.
function greekLetters(translit) {
  const nfd = String(translit || "").normalize("NFD")
  const letters = []
  for (const ch of nfd) {
    const code = ch.codePointAt(0)
    if (code >= 0x300 && code <= 0x36f) {
      const last = letters[letters.length - 1]
      if (!last) continue
      if (code === 0x304) last.long = true
      else if (code === 0x301 || code === 0x300 || code === 0x302 || code === 0x342) last.stress = true
      continue
    }
    letters.push({ ch: ch.toLowerCase(), long: false, stress: false })
  }
  return letters
}

const GREEK_DIPHTHONGS = [ "ai", "ei", "oi", "ui", "au", "eu", "ou", "yi" ]
const GREEK_VOWELS = "aeiouy"
const HEBREW_VOWELS = "aeiou"
const CONSONANT_DIGRAPHS = [ "ch", "ph", "th", "ps", "rh", "sh", "ts", "tz", "kh" ]

// Split letters into units: vowel nuclei (with diphthongs) and consonants
// (digraphs kept whole). Each unit: { text, vowel, long, stress }.
function units(letters, vowels, diphthongs) {
  const out = []
  for (let i = 0; i < letters.length; i++) {
    const a = letters[i]
    const b = letters[i + 1]
    if (!/[a-z]/.test(a.ch)) { out.push({ text: a.ch, vowel: false, sep: true }); continue }
    if (vowels.includes(a.ch)) {
      if (b && !a.long && diphthongs.includes(a.ch + b.ch)) {
        out.push({ text: a.ch + b.ch, vowel: true, long: false, stress: a.stress || b.stress })
        i++
      } else {
        out.push({ text: a.ch, vowel: true, long: a.long, stress: a.stress })
      }
      continue
    }
    if (b && CONSONANT_DIGRAPHS.includes(a.ch + b.ch)) {
      out.push({ text: a.ch + b.ch, vowel: false })
      i++
      continue
    }
    out.push({ text: a.ch, vowel: false })
  }
  return out
}

// Group units into syllables: one consonant between vowels starts the next
// syllable; of two or more, the first closes the syllable before.
function syllables(us) {
  const nuclei = us.map((u, i) => (u.vowel ? i : -1)).filter((i) => i >= 0)
  if (nuclei.length === 0) return [ { units: us } ]
  const syls = []
  let start = 0
  nuclei.forEach((n, k) => {
    const next = nuclei[k + 1]
    if (next == null) { syls.push({ units: us.slice(start) }); return }
    const between = next - n - 1
    const cut = between <= 1 ? n + 1 : n + 2
    syls.push({ units: us.slice(start, cut) })
    start = cut
  })
  return syls
}

const GREEK_SAY = { a: "ah", e: "eh", i: "ee", o: "oh", u: "oo", y: "oo", ai: "eye", ei: "ay", oi: "oy", ui: "wee", yi: "wee", au: "ow", eu: "yoo", ou: "oo" }
const HEBREW_SAY = { a: "ah", e: "eh", i: "ee", o: "oh", u: "oo" }
const SAY_CONSONANT = { ch: "kh", kh: "kh", ph: "f", rh: "r", q: "k", c: "k", tz: "ts" }

function sayVowel(u, closed, stressed, map) {
  if (u.long) return u.text === "e" ? "ay" : "oh" // ē, ō
  if (closed && !stressed && (u.text === "a" || u.text === "e" || u.text === "i")) return u.text
  return map[u.text] || u.text
}

// A pronunciation guide in plain English spelling, stressed syllable in
// capitals: agapáō → ah-gah-PAH-oh, bârâʼ → bah-RAH, chêçêd → KHEH-sed.
// Greek stress comes from the accent; Hebrew from Strong's "pron" when we
// have it (baw-raw' marks the stressed syllable), else the last syllable.
export function sayIt(translit, strongs, pron = "") {
  const hebrew = languageOf(strongs) === "hebrew"
  // A Hebrew word-final h after a vowel is silent (torah, Yehovah).
  const base = hebrew ? simpleHebrew(translit).toLowerCase().replace(/([aeiou])h\b/g, "$1") : null
  const letters = hebrew
    ? [ ...base ].map((ch) => ({ ch, long: false, stress: false }))
    : greekLetters(String(translit || "").replace(/gg/g, "ng").replace(/g(?=[kxc])/g, "n"))
  return letters.length ? letters.reduce(splitWords, [ [] ]).filter((w) => w.length)
    .map((word) => sayWord(word, hebrew, pron)).join(" ") : ""
}

function splitWords(acc, l) {
  if (/\s|-/.test(l.ch)) acc.push([])
  else acc[acc.length - 1].push(l)
  return acc
}

function sayWord(letters, hebrew, pron) {
  const us = units(letters, hebrew ? HEBREW_VOWELS : GREEK_VOWELS, hebrew ? [] : GREEK_DIPHTHONGS)
  const syls = syllables(us.filter((u) => !u.sep))
  let stressAt = syls.findIndex((s) => s.units.some((u) => u.stress))
  if (hebrew) stressAt = hebrewStress(syls.length, pron)
  if (stressAt < 0) stressAt = hebrew ? syls.length - 1 : -1
  if (syls.length === 1) stressAt = -1 // one syllable: nothing to stress
  return syls.map((syl, i) => {
    const vowelIdx = syl.units.findIndex((u) => u.vowel)
    const closed = vowelIdx >= 0 && vowelIdx < syl.units.length - 1
    const stressed = i === stressAt
    const text = syl.units.map((u) => {
      if (u.vowel) return sayVowel(u, closed, stressed, hebrew ? HEBREW_SAY : GREEK_SAY)
      return SAY_CONSONANT[u.text] || u.text
    }).join("")
    return stressed ? text.toUpperCase() : text
  }).join("-")
}

// Which syllable Strong's pronunciation stresses ("baw-raw'" → the 2nd of 2),
// mapped onto our syllables counting from the end (Hebrew stress sits on the
// last or the second-to-last syllable).
function hebrewStress(count, pron) {
  const parts = String(pron || "").split(/[-\s]+/).filter(Boolean)
  const at = parts.findIndex((p) => p.includes("'"))
  if (at < 0) return count - 1
  const fromEnd = parts.length - 1 - at
  return Math.max(0, count - 1 - fromEnd)
}

// ---- verses -----------------------------------------------------------------------

// The offline word pack stores a verse's tokens as one string: each tagged
// word followed by "@" and its Strong's number ("For@1063 God@2316 so@3779
// loved@25 the world@2889, …"), the testament giving the H/G prefix.
export function decodeVerse(encoded, prefix) {
  const s = String(encoded || "")
  if (!s) return []
  const parts = s.split(/@(\d+)/)
  const tokens = []
  for (let i = 0; i < parts.length; i += 2) {
    const surface = parts[i]
    const num = parts[i + 1]
    if (num == null) { if (surface) tokens.push({ w: surface }); break }
    tokens.push({ w: surface, s: `${prefix}${num}` })
  }
  return tokens
}

// Tokens → the pieces the card lays out: punctuation and spaces split off a
// tagged word ("," + " that"), so only the word itself is a button.
export function verseWords(tokens) {
  const out = []
  ;(tokens || []).forEach((t, i) => {
    const w = String(t.w || "")
    if (!t.s) { if (w) out.push({ text: w }); return }
    const m = w.match(/^([^\p{L}\p{N}]*)([\s\S]*?)([^\p{L}\p{N}]*)$/u)
    const [ , lead, core, trail ] = m || [ "", "", w, "" ]
    if (lead) out.push({ text: lead })
    if (core) out.push({ text: core, s: t.s, index: i })
    if (trail) out.push({ text: trail })
  })
  return out
}

// Where the English word sits in a verse's text (case-insensitive, whole
// words) — [start, end) or null. Tries the full phrase, then its last word
// ("only begotten" → "begotten"), then its first.
export function findWord(text, english) {
  const hay = String(text || "")
  const phrase = String(english || "").trim()
  if (!hay || !phrase) return null
  const tries = [ phrase ]
  const words = phrase.split(/\s+/).filter((w) => w.length > 2)
  if (words.length > 1) tries.push(words[words.length - 1], words[0])
  for (const t of tries) {
    const re = new RegExp(`(^|[^\\p{L}\\p{N}])(${escapeRe(t)})(?=$|[^\\p{L}\\p{N}])`, "iu")
    const m = re.exec(hay)
    if (m) {
      const start = m.index + m[1].length
      return [ start, start + m[2].length ]
    }
  }
  return null
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// The token the operator meant when tapping a word on the screen: the tagged
// word whose text contains it (any translation — "loved" in the WEB finds
// the KJV's "loved").
export function tokenForWord(words, tapped) {
  const want = String(tapped || "").toLowerCase().replace(/[^\p{L}\p{N}'’-]/gu, "")
  if (!want) return null
  const tagged = (words || []).filter((w) => w.s)
  return tagged.find((w) => w.text.toLowerCase() === want) ||
    tagged.find((w) => w.text.toLowerCase().split(/\s+/).includes(want)) ||
    tagged.find((w) => stem(w.text.toLowerCase()) === stem(want)) || null
}

function stem(w) {
  return w.replace(/(?:eth|est|ed|ing|es|s)$/, "").replace(/e$/, "")
}

// ---- the word study itself ------------------------------------------------------------

export function buildWordStudy({ entry, english, reference, verse, translation, layout = "verse", note = "" }) {
  const s = String(entry?.s || "").toUpperCase()
  const mark = findWord(verse, english)
  return {
    v: WORD_STUDY_VERSION,
    s,
    lang: languageOf(s),
    lemma: entry?.lemma || "",
    translit: readableTranslit(entry?.translit, s),
    say: sayIt(entry?.translit, s, entry?.pron),
    gloss: gloss(entry),
    english: String(english || "").trim(),
    reference: reference || "",
    verse: verse || "",
    translation: translation || "",
    mark,
    layout: layout === "word" ? "word" : "verse",
    note: String(note || "").trim(),
    n: Number(entry?.n) || 0
  }
}

// "Word study: agapáō — John 3:16" (queue label, slide title, phones' header).
export function wordStudyTitle(word) {
  if (!word) return "Word study"
  const name = word.translit || word.lemma || word.s
  return word.reference ? `Word study: ${name} — ${word.reference}` : `Word study: ${name}`
}

// The plain-text version (old phone pages, the stage's next line, copy/paste).
export function wordStudyText(word) {
  if (!word) return ""
  const head = [ word.lemma, word.translit && `(${word.translit})`, word.s ].filter(Boolean).join(" ")
  const lines = [ head ]
  if (word.say) lines.push(`say: ${word.say}`)
  if (word.gloss) lines.push(word.gloss)
  if (word.note) lines.push(word.note)
  if (word.english && word.reference) lines.push(`“${word.english}” — ${word.reference}`)
  return lines.join("\n")
}

const WORD_FIELDS = { s: 12, lang: 8, lemma: 60, translit: 60, say: 80, gloss: 200, english: 60, reference: 60,
  verse: 1200, translation: 12, layout: 8, note: 400 }

// A word study from anywhere (a queue item's JSON body, a broadcast, a live
// phone): only the known fields, as strings of sane length.
export function normalizeWordStudy(raw) {
  let w = raw
  if (typeof w === "string") {
    try { w = JSON.parse(w) } catch { return null }
  }
  if (!w || typeof w !== "object" || !/^[GH]\d{1,5}[a-z]?$/i.test(String(w.s || ""))) return null
  const out = { v: WORD_STUDY_VERSION }
  Object.entries(WORD_FIELDS).forEach(([ k, max ]) => { out[k] = String(w[k] ?? "").slice(0, max) })
  out.s = out.s.toUpperCase()
  out.lang = languageOf(out.s)
  out.layout = out.layout === "word" ? "word" : "verse"
  out.n = Math.max(0, Math.min(1e6, Number(w.n) || 0))
  const m = Array.isArray(w.mark) ? w.mark.map(Number) : null
  out.mark = m && m.length === 2 && m.every(Number.isInteger) && m[0] >= 0 && m[1] > m[0] && m[1] <= out.verse.length ? m : null
  return out
}

export const encodeWordStudy = (word) => JSON.stringify(normalizeWordStudy(word))

// A queue / Preview / setlist:present detail → its word study, or null.
export function wordFromDetail(detail) {
  if (!detail) return null
  if (detail.word) return normalizeWordStudy(detail.word)
  if (detail.itemKind === "word") return normalizeWordStudy(detail.body)
  return null
}

// "143 times in the KJV"
export function occurrencesLabel(n) {
  const count = Number(n) || 0
  if (!count) return ""
  return count === 1 ? "once in the KJV" : `${count.toLocaleString("en-US")} times in the KJV`
}
