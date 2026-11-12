// "Offline search (keywords)": when the AI quick find can't be reached, the
// Go box still finds verses for a described thought by scanning the Bibles
// downloaded to the device. No AI, no network — words are scored by how rare
// they are (a verse matching "jericho" beats one matching "people"), with a
// few hand-picked KJV-era synonyms ("beat" also finds "smote", "scourged").
//
//   searchVerses(records, "walls of jericho fell", { limit: 10 })
//     → [{ osis, chapter, num, text, score, matched }]
// `records` are the downloaded book records ({ osis, chapters: [{ i, t, n? }] }).
const STOP = new Set(("a an and are as at be been but by did do does for from had has have he her him his how i if in into is " +
  "it its me my no not of on or our out shall she so some that the their them then there these they this those thou thee thy " +
  "to unto up us was we were what when where which who whom why will with ye you your about verse verses bible scripture " +
  "passage chapter where's story tell find show god's").split(" "))

// Modern word → words the older translations use. Kept small on purpose.
const SYNONYMS = {
  beat: [ "smote", "smite", "scourge", "strike", "struck", "stripes" ],
  hit: [ "smote", "smite", "struck" ],
  whip: [ "scourge" ],
  kill: [ "slay", "slew", "slain" ],
  killed: [ "slew", "slain" ],
  love: [ "charity", "loveth" ],
  money: [ "silver", "mammon", "gold" ],
  worry: [ "anxious", "careful", "thought" ],
  afraid: [ "fear", "dismayed" ],
  fear: [ "afraid", "dismayed" ],
  happy: [ "blessed", "joy", "rejoice" ],
  sad: [ "sorrow", "mourn", "heavy" ],
  angry: [ "wrath", "anger" ],
  temple: [ "house" ],
  church: [ "assembly", "congregation" ],
  people: [ "multitude" ],
  sell: [ "sold", "merchandise" ],
  sellers: [ "sold", "merchandise", "changers" ],
  rest: [ "weary" ],
  forgive: [ "forgiven", "forgiveth", "pardon" ],
  strength: [ "strong", "strengthen" ]
}

export function stem(word) {
  let w = word.toLowerCase().replace(/'s$/, "").replace(/[^a-z]/g, "")
  if (w.length > 5 && w.endsWith("eth")) w = w.slice(0, -3)
  else if (w.length > 5 && w.endsWith("ing")) w = w.slice(0, -3)
  else if (w.length > 4 && w.endsWith("ed")) w = w.slice(0, -2)
  else if (w.length > 4 && w.endsWith("es")) w = w.slice(0, -2)
  else if (w.length > 3 && w.endsWith("s") && !w.endsWith("ss")) w = w.slice(0, -1)
  if (w.length >= 4 && w.endsWith("e")) w = w.slice(0, -1) // scourge / scourged → scourg
  return w
}

// The query's keywords: [{ word, stems: [own stem, ...synonym stems] }].
export function keywords(query) {
  const words = String(query || "").toLowerCase().match(/[a-z']+/g) || []
  const seen = new Set()
  const out = []
  for (const word of words) {
    const clean = word.replace(/'s$/, "").replace(/'/g, "")
    if (clean.length < 3 || STOP.has(clean) || seen.has(clean)) continue
    seen.add(clean)
    out.push({ word: clean, stem: stem(clean), synonyms: (SYNONYMS[clean] || []).map(stem) })
  }
  return out
}

function verseStems(text) {
  return new Set((text.toLowerCase().match(/[a-z']+/g) || []).map(stem))
}

export function searchVerses(records, query, { limit = 10 } = {}) {
  const keys = keywords(query)
  if (!keys.length) return []
  const roots = keys.flatMap((k) => [ k.stem, ...k.synonyms ]).filter(Boolean)

  const hits = []
  let total = 0
  for (const record of records || []) {
    (record.chapters || []).forEach((c, ci) => {
      if (!c?.t) return
      c.t.forEach((text, k) => {
        total++
        const lower = text.toLowerCase()
        if (!roots.some((r) => lower.includes(r))) return // cheap prefilter
        const stems = verseStems(text)
        const matched = keys.map((key) => (stems.has(key.stem) ? 1 : key.synonyms.some((s) => stems.has(s)) ? 0.7 : 0))
        if (!matched.some(Boolean)) return
        hits.push({ osis: record.osis, chapter: ci + 1, num: c.n ? c.n[k] : k + 1, text, matched })
      })
    })
  }
  if (!hits.length) return []

  // Rarer keywords weigh more (inverse document frequency over the hits).
  const df = keys.map((_, i) => hits.filter((h) => h.matched[i]).length)
  const idf = df.map((n) => Math.log(1 + (total || 1) / (1 + n)))
  hits.forEach((h) => {
    h.score = h.matched.reduce((s, m, i) => s + m * idf[i], 0)
    h.count = h.matched.filter(Boolean).length
  })
  hits.sort((a, b) => b.count - a.count || b.score - a.score || a.text.length - b.text.length)
  return hits.slice(0, limit).map(({ osis, chapter, num, text, score, count }) => ({ osis, chapter, num, text, score, matched: count }))
}
