// Scene pictures behind the reader: which Doré engraving goes with the
// passage being read. Pure (no DOM), so node tests it
// (test/javascript/scripture_scenes_test.mjs).
//
// scenes: [{ key, title, ref, osis, chapter, verse }] in Bible order — built
// from config/scripture_scenes.yml into scripture_scenes.json (rake scenes:json).
//
//   sceneFor(scenes, "Gen", 4, 9)  → the Cain-and-Abel plate
//
// In a chapter with a plate: the last plate at or before the verse being read
// (Gen 3: Eve tempted, then driven out of Eden); above the first plate's verse
// the chapter's first plate still shows. A chapter without one carries the
// book's last scene for up to CARRY chapters (the story is still there);
// further on, or in a book with no plate before it, nothing.
export const CARRY = 3

export function indexScenes(scenes) {
  const byBook = new Map()
  for (const s of scenes || []) {
    if (!byBook.has(s.osis)) byBook.set(s.osis, [])
    byBook.get(s.osis).push(s)
  }
  for (const list of byBook.values()) list.sort((a, b) => a.chapter - b.chapter || (a.verse ?? 0) - (b.verse ?? 0))
  return byBook
}

export function sceneFor(index, osis, chapter, verse = null) {
  const list = (index instanceof Map ? index : indexScenes(index)).get(osis)
  if (!list?.length || !chapter) return null
  const here = list.filter((s) => s.chapter === chapter)
  if (here.length) {
    if (verse == null) return here[0]
    const upTo = here.filter((s) => (s.verse ?? 0) <= verse)
    return upTo.length ? upTo[upTo.length - 1] : here[0]
  }
  const before = list.filter((s) => s.chapter < chapter)
  const last = before[before.length - 1]
  return last && chapter - last.chapter <= CARRY ? last : null
}

export const sceneUrl = (scene) => `/scenes/${scene.key}.webp`
