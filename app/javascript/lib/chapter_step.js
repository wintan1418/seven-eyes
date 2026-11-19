// Preach mode's Next / Prev, EasyWorship-style: walking off the end of a
// chapter carries straight on into the next one (1 Cor 14:40 → 15:1,
// Malachi 4:6 → Matthew 1:1), and Prev on the first verse goes back to the
// last verse of the chapter before. Revelation 22:21 / Genesis 1:1 stop.
//
// The neighbouring chapters come from the pane itself (data-prev-chapter /
// data-next-chapter on .ps-verses, written by panes/_pane and the offline
// pane renderer from the same neighbor_reference rule as the reader's
// chapter buttons), so the pane's own translation and canon are respected.
//
// Pure functions (node-tested in test/javascript/chapter_step_test.mjs).

// What a step does from verse index `index` (showing `group` verses at a time)
// in a pane of `count` verses:
//   { move: "verse", index }                  — within the chapter
//   { move: "chapter", reference, land }      — load `reference`, land on its
//                                               "first" or "last" verse(s)
//   { move: "end" } / { move: "start" }       — the end / start of the Bible
export function stepPlan({ index, group = 1, count, direction, prevRef = null, nextRef = null }) {
  const g = Math.max(1, group || 1)
  if (direction > 0) {
    if (index + g < count) return { move: "verse", index: index + g }
    return nextRef ? { move: "chapter", reference: nextRef, land: "first" } : { move: "end" }
  }
  if (index > 0) return { move: "verse", index: Math.max(0, index - g) }
  return prevRef ? { move: "chapter", reference: prevRef, land: "last" } : { move: "start" }
}

// Where a chapter step lands in the newly loaded chapter of `count` verses:
// the first verse, or the last `group` verses (Prev from 15:1 → 14:40).
export function landingIndex(land, count, group = 1) {
  if (land !== "last" || count <= 0) return 0
  return Math.max(0, count - Math.max(1, group || 1))
}

// Close enough to the edge of the chapter to fetch the neighbour now, so the
// step across is instant on stage.
export const PREFETCH_WITHIN = 3

export function nearEdges({ index, group = 1, count }, within = PREFETCH_WITHIN) {
  const g = Math.max(1, group || 1)
  return { next: index + g >= count - within, prev: index < within }
}

// One rendered pane per reference + translation.
export function prefetchKey(reference, translation) {
  return `${String(reference || "").trim().replace(/\s+/g, " ").toLowerCase()}|${translation || ""}`
}
