// Song bank search, on the device (works offline). No DOM, so node can test it
// (test/javascript/song_sheet_test.mjs).

const fold = (s) => String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  .replace(/[\u2018\u2019`]/g, "'").replace(/[^a-z0-9' ]+/g, " ").replace(/\s+/g, " ").trim()

// Songs matching `query` (every word must appear in the title or the words),
// titles first; `source` "yours" | "hymnal" | "" (all). Each result says which
// line matched so the list can show it.
export function searchSongs(songs, query, { source = "" } = {}) {
  const q = fold(query)
  const words = q ? q.split(" ") : []
  const results = []
  ;(songs || []).forEach((song, order) => {
    if (source && song.source !== source) return
    const title = fold(song.title)
    if (!words.length) { results.push({ song, rank: 3, order, line: null }); return }
    const body = fold(song.body)
    if (!words.every((w) => title.includes(w) || body.includes(w))) return
    let rank = 2
    if (title.startsWith(q)) rank = 0
    else if (title.includes(q) || words.every((w) => title.includes(w))) rank = 1
    let line = null
    if (rank === 2) {
      const lines = String(song.body || "").split("\n").filter((l) => l.trim() && !/^\[.*\]$/.test(l.trim()))
      line = lines.find((l) => fold(l).includes(q)) || lines.find((l) => words.some((w) => fold(l).includes(w))) || null
    }
    results.push({ song, rank, order, line })
  })
  return results.sort((a, b) => a.rank - b.rank || (a.rank === 3 ? a.order - b.order : fold(a.song.title).localeCompare(fold(b.song.title))))
}
