// The offline twin of Pane#content + the pane partial: given what a pane's form
// asked for, read the downloaded Bible and return the frame's HTML. Runs in
// the service worker. Returns null when nothing is downloaded at all, so the
// caller can fail the request and the page keeps the text it already shows.
import { makeParser, referenceLabel } from "./reference_parser"
import { renderPane, passageVerses, chapterVerses } from "./pane_renderer"
import { storedManifest, downloadedBibles, bookText, highlightsFor } from "./store"

let parserCache = { manifest: null, parse: null }

export async function parserFromManifest() {
  const manifest = await storedManifest()
  if (!manifest?.canon) return { manifest: null, parse: null }
  if (parserCache.manifest !== manifest.translations?.map((t) => t.version).join()) {
    parserCache = { manifest: manifest.translations?.map((t) => t.version).join(), parse: makeParser(manifest.canon) }
  }
  return { manifest, parse: parserCache.parse }
}

// The pane's translation as Pane#effective_translation would pick it.
function effectiveTranslation(manifest, translationId) {
  const list = manifest.translations || []
  return list.find((t) => String(t.id) === String(translationId)) ||
    list.find((t) => t.code === manifest.default_code) || list[0] || null
}

async function content(manifest, parse, downloaded, reference, translation) {
  if (!String(reference || "").trim()) return { ok: false, error: "empty" }
  const parsed = parse(reference)
  if (!parsed.valid) return { ok: false, error: "unparseable", parsed }

  const book = (manifest.books || []).find((b) => b.osis === parsed.osis)
  if (!book) return { ok: false, error: "unknown_book", parsed }
  if (!translation || !downloaded.some((d) => d.code === translation.code)) {
    return { ok: false, error: "not_downloaded", parsed, book }
  }

  const record = await bookText(translation.code, book.osis)
  const verses = passageVerses(record, parsed)
  if (verses.length) return { ok: true, parsed, book, verses }

  const chapter = chapterVerses(record, parsed.chapter)
  if (!chapter.length) return { ok: false, error: "not_found", parsed, book }
  return { ok: false, error: "verse_not_found", parsed, book, maxVerse: chapter[chapter.length - 1].num }
}

// context: { position, compare, signedIn, translationId } — sent by the page
// with every pane request (see page.js) because the form doesn't carry it all.
export async function renderOfflinePane({ studyId, paneId, reference, translationId, context = {}, token }) {
  const { manifest, parse } = await parserFromManifest()
  if (!manifest || !parse) return null
  const downloaded = await downloadedBibles()
  if (!downloaded.length) return null

  const translation = effectiveTranslation(manifest, translationId || context.translationId)
  const result = await content(manifest, parse, downloaded, reference, translation)
  const highlights = result.ok && context.signedIn ? await highlightsFor(result.verses.map((v) => v.id)) : []

  const icon = (name, css) => {
    const svg = manifest.icons?.[name] || ""
    return css ? svg.replace('class="ui-icon"', `class="${css}"`) : svg
  }
  return renderPane({
    studyId, paneId, position: Number(context.position) || 0, compare: !!context.compare, token,
    reference: reference || "", translation: translation && { ...translation, vulgate: !!translation.vulgate },
    translations: manifest.translations || [], downloaded, books: manifest.books || [], highlights, icon
  }, result)
}

// /reference_check, answered offline (preach mode's Go box).
export async function offlineReferenceCheck(q) {
  const { manifest, parse } = await parserFromManifest()
  if (!parse) return null
  const p = parse(q)
  const book = p.valid && (manifest.books || []).find((b) => b.osis === p.osis)
  if (!book) return { ok: false }
  return {
    ok: true, osis: p.osis, chapter: p.chapter, verse_start: p.verseStart,
    chapter_reference: `${p.bookName} ${p.chapter}`, label: referenceLabel(p)
  }
}
