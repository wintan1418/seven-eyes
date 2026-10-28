// Renders a reading pane's Turbo Frame from a downloaded Bible — the offline
// twin of app/views/panes/_pane.html.erb + ScriptureHelper#scripture_verse.
//
// The service worker answers a pane's form submit with this HTML when the
// network is gone, so Turbo swaps the frame exactly as if the server had
// answered. Everything the reader, the highlighter, verse selection and
// preach mode hang off is reproduced here (see preach_contract_test.rb):
//   turbo-frame#pane_ID.ps-pane > .rd-pane-meta, form.rd-pane-form
//     (pane[reference], select pane[translation_id]), .ps-verses .rd-column,
//   .ps-verse[data-osis][data-chapter][data-verse-num]
//     > a.ps-vnum + span.ps-verse-text[data-verse-id][data-offset-base]
//   prev/next chapter button_to forms, the notes form.
// If you change the pane partial, change this too.
//
// Not reproduced offline: Strong's word links (the bundles carry no tokens)
// and the "verses this translation omits" notice.

const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[c])

const query = (params) => Object.keys(params).sort()
  .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`).join("&")

// ---- content: the offline twin of Pane#content -----------------------------

// Expand a stored chapter ({i, t, n?}) to [{ id, chapter, num, text }].
export function chapterVerses(record, chapter) {
  const c = record?.chapters?.[chapter - 1]
  if (!c) return []
  return c.t.map((text, k) => ({
    id: Array.isArray(c.i) ? c.i[k] : c.i + k,
    chapter,
    num: c.n ? c.n[k] : k + 1,
    text
  }))
}

// Verse.passage for a parsed reference.
export function passageVerses(record, p) {
  const last = p.chapterEnd || p.chapter
  const vEnd = p.openEnded ? Infinity : (p.verseEnd ?? p.verseStart)
  if (last <= p.chapter) {
    const all = chapterVerses(record, p.chapter)
    return p.verseStart == null ? all : all.filter((v) => v.num >= p.verseStart && v.num <= vEnd)
  }
  const out = []
  for (let ch = p.chapter; ch <= last; ch++) out.push(...chapterVerses(record, ch))
  return out.filter((v) => {
    if (p.verseStart != null && (v.chapter < p.chapter || (v.chapter === p.chapter && v.num < p.verseStart))) return false
    if (p.verseStart != null && vEnd !== Infinity && p.verseEnd != null &&
        (v.chapter > last || (v.chapter === last && v.num > p.verseEnd))) return false
    return true
  })
}

// "John 3" / "John 3:16–18" / "Matthew 5–7" — ReaderHelper#passage_label.
export function passageLabel(bookName, verses, p) {
  const chapters = [ ...new Set(verses.map((v) => v.chapter)) ]
  const first = chapters[0] ?? p.chapter
  const last = chapters[chapters.length - 1] ?? p.chapterEnd ?? p.chapter
  let label = `${bookName} ${first}`
  if (last > first) label += `–${last}`
  if (p.verseStart != null && chapters.length <= 1) {
    label += `:${p.verseStart}`
    if (p.verseEnd != null && p.verseEnd !== p.verseStart) label += `–${p.verseEnd}`
  }
  return label
}

// ScriptureHelper#neighbor_reference over the manifest's book list.
export function neighborReference(books, book, chapter, direction) {
  const ordered = [ ...books ].sort((a, b) => a.position - b.position)
  if (direction === "next") {
    if (chapter < book.chapters) return `${book.name} ${chapter + 1}`
    const nxt = ordered.find((b) => b.position > book.position)
    return nxt ? `${nxt.name} 1` : null
  }
  if (chapter > 1) return `${book.name} ${chapter - 1}`
  const prv = [ ...ordered ].reverse().find((b) => b.position < book.position)
  return prv ? `${prv.name} ${prv.chapters}` : null
}

// ---- highlights: ScriptureHelper#highlight_runs / #render_segments ---------

export function highlightRuns(highlights, from, to) {
  const spans = highlights.map((h) => {
    const s = Math.min(Math.max(Number(h.char_start) || 0, from), to)
    const e = Math.min(Math.max(Number(h.char_end) || 0, s), to)
    return e > s ? [ s, e, h ] : null
  }).filter(Boolean)
  const cuts = [ ...new Set([ from, to, ...spans.flatMap(([ s, e ]) => [ s, e ]) ]) ].sort((a, b) => a - b)
  const runs = []
  for (let k = 0; k < cuts.length - 1; k++) {
    const a = cuts[k], b = cuts[k + 1]
    let winner = null, best = null
    for (const [ s, e, h ] of spans) {
      if (s > a || e < b) continue
      // innermost wins; ties go to the newest (largest id; offline ids count as newest)
      const key = [ e - s, -idRank(h.id) ]
      if (!best || key[0] < best[0] || (key[0] === best[0] && key[1] < best[1])) { best = key; winner = h }
    }
    const lastRun = runs[runs.length - 1]
    if (lastRun && lastRun.highlight === winner) lastRun.to = b
    else runs.push({ from: a, to: b, highlight: winner })
  }
  return runs
}

const idRank = (id) => (String(id).startsWith("tmp-") ? Number.MAX_SAFE_INTEGER : Number(id) || 0)

function verseTextHtml(text, highlights) {
  const chars = Array.from(text) // code points, like Ruby's String indexing
  return highlightRuns(highlights, 0, chars.length).map((run) => {
    const inner = esc(chars.slice(run.from, run.to).join(""))
    const h = run.highlight
    if (!h) return inner
    const cls = `hl-${h.color}${h.note ? " has-note" : ""}`
    return `<span class="${esc(cls)}" data-highlight-id="${esc(h.id)}" data-note="${esc(h.note || "")}">${inner}</span>`
  }).join("")
}

// ---- markup ---------------------------------------------------------------

function hiddenFields(method, token) {
  return `<input type="hidden" name="_method" value="${esc(method)}" autocomplete="off">` +
    (token ? `<input type="hidden" name="authenticity_token" value="${esc(token)}" autocomplete="off">` : "")
}

function paneButton(ctx, { reference, translationId, cls, title, aria, nav, formClass, inner }) {
  const fields = `<input type="hidden" name="pane[reference]" value="${esc(reference)}" autocomplete="off">` +
    (translationId ? `<input type="hidden" name="pane[translation_id]" value="${esc(translationId)}" autocomplete="off">` : "")
  return `<form data-turbo-frame="${esc(ctx.frameId)}" class="${esc(formClass)}" method="post" action="${esc(ctx.paneUrl)}">` +
    hiddenFields("patch", ctx.token) +
    `<button class="${esc(cls)}" title="${esc(title)}"${aria ? ` aria-label="${esc(aria)}"` : ""}${nav ? ` data-chapter-nav="${nav}"` : ""} type="submit">${inner}</button>` +
    fields + "</form>"
}

function switchButton(ctx, label, { reference, translationId }) {
  return paneButton(ctx, {
    reference, translationId, title: label, formClass: "inline", inner: esc(label),
    cls: "ps-pane-fix mt-2 cursor-pointer border border-gold px-3 py-1 font-display text-[10px] uppercase tracking-[0.18em] text-rubric hover:bg-vellum-2"
  })
}

function paneForm(ctx) {
  const options = ctx.translations.map((t) =>
    `<option title="${esc(t.display_name)}"${t.id === ctx.translation?.id ? " selected=\"selected\"" : ""} value="${esc(t.id)}">${esc(t.code)}</option>`).join("")
  return `<form class="rd-pane-form" data-controller="auto-submit" action="${esc(ctx.paneUrl)}" accept-charset="UTF-8" method="post">` +
    hiddenFields("patch", ctx.token) +
    `<input value="${esc(ctx.reference)}" autocomplete="off" type="hidden" name="pane[reference]" id="pane_reference">` +
    `<select class="ps-trans-select ui-sr-only" id="pane_${esc(ctx.paneId)}_translation" tabindex="-1" aria-label="Translation" data-action="change->auto-submit#submit" name="pane[translation_id]">${options}</select>` +
    `<button type="submit" class="ui-sr-only" tabindex="-1" aria-hidden="true">Go</button></form>`
}

function compareHead(ctx, label) {
  if (!ctx.compare) return ""
  return `<div class="ps-pane-head rd-pane-head" data-chrome>` +
    `<button type="button" class="ui-chip is-sm" data-action="sheets#open" data-sheets-id-param="passage" data-sheets-pane-param="${esc(ctx.paneId)}" title="Choose a passage for this pane">` +
    `<span class="ui-chip-label">${esc(label || "Choose a passage")}</span>${ctx.icon("chevron_down")}</button>` +
    `<button type="button" class="ui-chip is-sm is-quiet" data-action="sheets#open" data-sheets-id-param="translation" data-sheets-pane-param="${esc(ctx.paneId)}" title="Change this pane's translation">` +
    `<span class="ui-chip-label">${esc(ctx.translation?.code)}</span>${ctx.icon("chevron_down")}</button></div>`
}

function notesForm(ctx) {
  // The notes text isn't known here: page code copies it over from the frame
  // being replaced (and from the outbox) before the new frame is shown.
  return `<form class="ps-notes-form" data-controller="notes" data-turbo="false" data-pane-target="notes" data-offline-notes action="${esc(ctx.paneUrl)}" accept-charset="UTF-8" method="post">` +
    hiddenFields("patch", ctx.token) +
    `<div class="ps-notes"><div class="ps-notes-head"><span>Notes <span class="saving" data-notes-target="status">&mdash; auto-saves as you write</span></span>` +
    `<button type="button" class="ps-notes-close" title="Close notes" data-action="pane#toggleNotes">${ctx.icon("x")}</button></div>` +
    `<textarea name="pane[notes]" class="ps-notes-area" rows="4" placeholder="Write a thought, an outline, a cross-reference to remember… Use [[John 3:16]] to link a verse." data-action="input->notes#schedule"></textarea>` +
    `<input type="hidden" name="autosave" value="1"></div></form>`
}

function verseHtml(ctx, book, v, highlights) {
  const xref = `/studies/${ctx.studyId}/cross_references?${query({ chapter: v.chapter, osis: book.osis, translation: ctx.translation.code, verse: v.num })}`
  return `<span class="ps-verse" data-osis="${esc(book.osis)}" data-chapter="${v.chapter}" data-verse-num="${v.num}">` +
    `<a class="ps-vnum" title="Cross-references" data-turbo-frame="xref_drawer" data-action="xref#open" href="${esc(xref)}">${v.num}</a>` +
    `<span class="ps-verse-text" data-verse-id="${esc(v.id)}" data-offset-base="0">${verseTextHtml(v.text, highlights)}</span> </span>`
}

function okBody(ctx, c) {
  const { book, verses, parsed } = c
  const chapters = [ ...new Set(verses.map((v) => v.chapter)) ]
  const first = chapters[0], last = chapters[chapters.length - 1]
  const multi = chapters.length > 1
  const prevRef = neighborReference(ctx.books, book, first, "prev")
  const nextRef = neighborReference(ctx.books, book, last, "next")
  const number = last > first ? `${first}–${last}` : String(first)
  const t = ctx.translation
  const byVerse = new Map()
  ctx.highlights.forEach((h) => { const k = String(h.verse_id); byVerse.set(k, [ ...(byVerse.get(k) || []), h ]) })

  let body = ""
  verses.forEach((v, i) => {
    if (multi && (i === 0 || verses[i - 1].chapter !== v.chapter)) {
      body += `<div class="ps-chapter-break" role="heading" aria-level="3">${esc(book.name)} ${v.chapter}</div>`
    }
    body += verseHtml(ctx, book, v, byVerse.get(String(v.id)) || [])
  })

  const vEnd = multi ? "" : (parsed.verseEnd ?? "")
  const commentaryUrl = `/studies/${ctx.studyId}/commentary?${query({ chapter: parsed.chapter, osis: book.osis })}`
  const nextInner = (ref) => `<span class="rd-next-label">Next</span><span class="rd-next-ref">${esc(ref)}</span>${ctx.icon("chevron_right")}`

  return `<div class="ps-verses"><div class="rd-column">` +
    `<header class="ref-title rd-chapter-head"><span class="rd-book">${esc(book.name)}</span><span class="rd-chapter-num">${esc(number)}</span><span class="tag rd-trans">${esc(t.display_name)}</span></header>` +
    `<div class="rule" aria-hidden="true"></div>` +
    `<div class="rd-chapter-tools" data-chrome>` +
      `<button type="button" class="ps-pane-tool ui-iconbtn is-sm" title="Listen to this chapter" data-action="reader#toggle" data-reader-target="button" data-osis="${esc(book.osis)}" data-chapter="${parsed.chapter}" data-translation="${esc(t.code)}">${ctx.icon("listen")}</button>` +
      `<button type="button" class="ps-pane-tool ui-iconbtn is-sm" title="Memorize mode" data-action="memorize#toggle" data-memorize-target="button">${ctx.icon("memorize")}</button>` +
      `<button type="button" class="ps-pane-tool ui-iconbtn is-sm" title="Notes" data-action="pane#toggleNotes">${ctx.icon("notes")}</button>` +
    `</div>` +
    (t.vulgate ? `<p class="ps-pane-notice">The ${esc(t.name)} numbers chapters and verses after the Latin Vulgate &mdash; most Psalms run one behind other Bibles (its Psalm 22 is Psalm 23 elsewhere).</p>` : "") +
    `<div class="ps-verse-body" data-controller="highlighter" data-action="click->memorize#reveal" data-tour="verses">${body}</div>` +
    `<footer class="rd-chapter-end" data-chrome><div class="rd-chapter-actions">` +
      `<a class="ui-btn is-quiet" title="Matthew Henry's commentary on this chapter" data-turbo-frame="commentary_drawer" data-action="commentary#open" data-tour="commentary" href="${esc(commentaryUrl)}">${ctx.icon("commentary")} Commentary</a>` +
      `<button type="button" class="ui-btn is-quiet" title="Share this passage as a picture" data-action="pane#share" data-osis="${esc(book.osis)}" data-chapter="${parsed.chapter}" data-verse-start="${esc(parsed.verseStart ?? "")}" data-verse-end="${esc(vEnd)}">${ctx.icon("image")} Share</button>` +
      `<button type="button" class="ui-btn is-quiet" title="A prayer from this chapter, to share" data-action="pane#prayer" data-osis="${esc(book.osis)}" data-chapter="${parsed.chapter}">${ctx.icon("prayer")} Prayer</button>` +
    `</div>` +
    (nextRef ? paneButton(ctx, { reference: nextRef, cls: "rd-next-chapter", title: "Next chapter", formClass: "rd-next-form", inner: nextInner(nextRef) }) : "") +
    `</footer></div></div>` +
    `<nav class="rd-chapter-nav" data-chrome aria-label="Chapters">` +
      (prevRef ? paneButton(ctx, { reference: prevRef, cls: "rd-fab prev", title: `Previous chapter (${prevRef})`, aria: "Previous chapter", nav: "prev", formClass: "contents", inner: ctx.icon("chevron_left") }) : "") +
      (nextRef ? paneButton(ctx, { reference: nextRef, cls: "rd-fab next", title: `Next chapter (${nextRef})`, aria: "Next chapter", nav: "next", formClass: "contents", inner: ctx.icon("chevron_right") }) : "") +
    `</nav>` +
    notesForm(ctx)
}

function emptyBody(ctx) {
  return `<div class="ps-pane-empty"><div class="orn">${ctx.icon("book", "ui-icon is-xl")}</div>` +
    `<div class="lead">Choose a passage</div>` +
    `<div class="hint">Pick a book and chapter &mdash; or type <em>Jn 3:16</em>, <em>Rom 5</em>, <em>1 Cor 13</em>.</div>` +
    `<button type="button" class="ui-btn is-primary" data-action="sheets#open" data-sheets-id-param="passage" data-sheets-pane-param="${esc(ctx.paneId)}">Open the Bible</button></div>`
}

function problemBody(ctx, lead, hint) {
  return `<div class="ps-pane-empty" role="status"><div class="orn">${ctx.icon("help", "ui-icon is-xl")}</div>` +
    `<div class="lead">${lead}</div><div class="hint">${hint}</div>` +
    `<button type="button" class="ui-btn" data-action="sheets#open" data-sheets-id-param="passage" data-sheets-pane-param="${esc(ctx.paneId)}">Choose another passage</button></div>`
}

function errorBody(ctx, c) {
  const p = c.parsed
  const tryForm = "Try a form like <em>John 3:16</em>, <em>Rom 5</em>, or <em>1 Cor 13:1-13</em>."
  switch (c.error) {
    case "not_downloaded": {
      const others = ctx.downloaded.filter((t) => t.code !== ctx.translation?.code)
      const buttons = others.map((t) => `<div>${switchButton(ctx, `Show in ${t.code}`, { reference: ctx.reference, translationId: t.id })}</div>`).join("")
      return problemBody(ctx,
        `You&rsquo;re offline &mdash; the ${esc(ctx.translation?.code)} isn&rsquo;t downloaded`,
        `Download it from <em>Offline Bibles</em> next time you have a connection.${others.length ? " Meanwhile:" : ""}${buttons}`)
    }
    case "verse_not_found":
      return problemBody(ctx, `${esc(c.book.name)} ${p.chapter} has ${c.maxVerse} verse${c.maxVerse === 1 ? "" : "s"}`,
        `&ldquo;${esc(ctx.reference)}&rdquo; asks for more than this chapter holds.` +
        `<div>${switchButton(ctx, `Show ${c.book.name} ${p.chapter}:${c.maxVerse}`, { reference: `${c.book.name} ${p.chapter}:${c.maxVerse}` })}</div>`)
    case "not_found":
      return problemBody(ctx, `This chapter isn&rsquo;t available in the ${esc(ctx.translation.display_name)} yet`,
        `The ${esc(ctx.translation.code)} has no text for ${esc(c.book.name)} ${p.chapter}.`)
    case "unknown_book":
      return problemBody(ctx, `${esc(p.bookName)} isn&rsquo;t loaded yet`, `The text for ${esc(p.bookName)} isn&rsquo;t in this download.`)
    case "unparseable":
      if (p?.error === "bad_chapter") {
        return problemBody(ctx, `${esc(p.bookName)} has ${p.chapterCount} chapter${p.chapterCount === 1 ? "" : "s"}`, `Pick a chapter from 1 to ${p.chapterCount}.`)
      }
      if (p?.error === "bad_verse") return problemBody(ctx, "Verses start at 1", tryForm)
      return problemBody(ctx, `No book called &ldquo;${esc(String(ctx.reference).replace(/\s*\d[\d:.,\-–\s]*$/, ""))}&rdquo;`, tryForm)
    default:
      return problemBody(ctx, "That reference could not be read", tryForm)
  }
}

// ctx: { studyId, paneId, position, compare, token, reference, translation, translations,
//        downloaded, books, highlights, icon(name, css) }
// content: { ok, error, parsed, book, verses, maxVerse }
export function renderPane(ctx, content) {
  ctx.frameId = `pane_${ctx.paneId}`
  ctx.paneUrl = `/studies/${ctx.studyId}/panes/${ctx.paneId}`
  const label = content.ok ? passageLabel(content.book.name, content.verses, content.parsed) : null
  const t = ctx.translation
  const meta = `<span class="rd-pane-meta" hidden="hidden" data-offline="1" data-translation-id="${esc(t?.id)}" ` +
    `data-reference-label="${esc(label || ctx.reference || "Choose a passage")}" data-translation-code="${esc(t?.code)}" data-translation-name="${esc(t?.display_name)}"></span>`

  let body
  if (content.ok) body = okBody(ctx, content)
  else if (content.error === "empty") body = emptyBody(ctx)
  else body = errorBody(ctx, content)

  return `<turbo-frame id="${esc(ctx.frameId)}" class="ps-pane${ctx.position === 0 ? " is-primary" : ""}" data-controller="pane reader memorize" data-pane-position="${esc(ctx.position)}">` +
    meta + paneForm(ctx) + compareHead(ctx, label) + body + `</turbo-frame>`
}
