// The words of what the operator picked — queue items, the Preview — as
// passages for "Combine into one slide" and "Copy" (lib/slides/combine):
//
//   await passagesFor(sources, { translation: "KJV" })
//     → [{ bookName, chapter, translation, verses: [{ c, n, text }] }]
//
// A source is { kind: "scripture", reference } (words from the downloaded
// Bible first, else GET /verse_passage) or a scripture set's data
// ({ kind: "scripture_set", data }) whose words travel with it. Sources it
// can't read are skipped; `missing` lists them.
import { warmLocal, localState } from "../offline/local_pane"
import { bookText, downloadedBibles } from "../offline/store"
import { passageVerses } from "../offline/pane_renderer"
import { quickFetch, isNetworkSlow } from "../offline/network"

const PASSAGE_TIMEOUT_MS = 4000
const MAX_VERSES = 80

export async function passagesFor(sources, { translation = null } = {}) {
  await warmLocal().catch(() => {})
  const parse = localState().parse
  const passages = []
  const missing = []
  for (const source of sources || []) {
    if (source?.data?.refs?.length) {
      source.data.refs.forEach((ref) => {
        const verses = (ref.verses || []).map((v) => ({ c: v.c || 0, n: v.n || 0, text: String(v.text || "") }))
        if (!verses.length) return
        const p = parse?.(ref.reference || ref.label || "")
        passages.push({
          bookName: p?.valid ? p.bookName : String(ref.label || ref.reference || "").replace(/\s*\d.*$/, ""),
          chapter: verses[0].c || (p?.valid ? p.chapter : 0),
          translation: ref.translation || "",
          own: !!ref.own, // pasted from the pastor's own Bible (NKJV…): stays marked so
          verses
        })
      })
      continue
    }
    const reference = source?.reference
    const found = reference ? await scriptureWords(reference, translation, parse) : null
    if (found) passages.push(found)
    else missing.push(reference || source?.label || "?")
  }
  return { passages, missing }
}

async function scriptureWords(reference, code, parse) {
  const p = parse?.(reference)
  if (p && !p.valid) return null
  if (p?.valid && code) {
    try {
      const here = (await downloadedBibles()).some((d) => d.code === code)
      const record = here ? await bookText(code, p.osis) : null
      const verses = record ? passageVerses(record, p) : []
      if (verses.length) {
        return { bookName: p.bookName, chapter: p.chapter, translation: code,
                 verses: verses.slice(0, MAX_VERSES).map((v) => ({ c: v.chapter, n: v.num, text: v.text })) }
      }
    } catch { /* the server, below */ }
  }
  if (navigator.onLine === false || isNetworkSlow()) return null
  try {
    const url = `/verse_passage?q=${encodeURIComponent(reference)}&translation=${encodeURIComponent(code || "")}`
    const { res, body } = await quickFetch(url, { headers: { Accept: "application/json" } }, { timeoutMs: PASSAGE_TIMEOUT_MS, read: "json" })
    if (!res.ok || !body?.ok || !body.verses?.length) return null
    const bookName = p?.valid ? p.bookName : String(body.label || reference).replace(/\s*\d.*$/, "")
    return { bookName, chapter: body.verses[0].c, translation: body.translation || code || "", verses: body.verses.slice(0, MAX_VERSES) }
  } catch { return null }
}

// The clipboard, with the old way when the async one is refused.
export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.className = "ps-copy-buffer"
    document.body.append(area)
    area.select()
    let ok = false
    try { ok = document.execCommand("copy") } catch { ok = false }
    area.remove()
    return ok
  }
}
