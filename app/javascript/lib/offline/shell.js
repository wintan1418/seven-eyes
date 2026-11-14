// Pages the service worker draws by itself when the server can't be reached
// and nothing is saved for the address asked for — so the apps' Bible tab
// never lands on a dead end:
//   • the offline reader: any book and chapter of a downloaded Bible
//     (/offline/read/:osis/:chapter, the book list at /offline/read/books),
//   • a friendly "you're offline" page that links to what does work.
// Pure string building, no browser globals: test/javascript/offline_shell_test.mjs
// runs it under node. The worker supplies the data (IndexedDB) and the asset
// URLs of the app's own CSS/JS (so Turbo — and the Hotwire Native bridge —
// keep running on these pages).

export const SHELL_ROOT = "/offline/read"
export const DEFAULT_PLACE = { osis: "John", chapter: 3 }
export const PREFERRED_CODE = "KJV"

const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[c])

// "/offline/read", "/offline/read/books", "/offline/read/John/3" → what to show.
export function parseShellPath(pathname) {
  const path = String(pathname || "").replace(/\/+$/, "")
  if (path === SHELL_ROOT) return { kind: "last" }
  if (path === `${SHELL_ROOT}/books`) return { kind: "books" }
  const m = path.match(/^\/offline\/read\/([1-3]?[A-Za-z]+)\/(\d{1,3})$/)
  if (m) return { kind: "chapter", osis: m[1], chapter: Number(m[2]) }
  return null
}

export const chapterPath = (osis, chapter, code) =>
  `${SHELL_ROOT}/${encodeURIComponent(osis)}/${chapter}${code ? `?t=${encodeURIComponent(code)}` : ""}`

// Which downloaded Bible to read: the one asked for, else KJV, else the first.
export function pickBible(downloaded, wanted) {
  const list = downloaded || []
  const by = (code) => code && list.find((d) => String(d.code).toLowerCase() === String(code).toLowerCase())
  return by(wanted) || by(PREFERRED_CODE) || list[0] || null
}

export const orderedBooks = (books) => [ ...(books || []) ].sort((a, b) => a.position - b.position)

// The chapter before / after (across books), as { osis, chapter } or null.
export function neighbor(books, osis, chapter, direction) {
  const list = orderedBooks(books)
  const i = list.findIndex((b) => b.osis === osis)
  if (i < 0) return null
  const book = list[i]
  if (direction === "next") {
    if (chapter < book.chapters) return { osis, chapter: chapter + 1 }
    return list[i + 1] ? { osis: list[i + 1].osis, chapter: 1 } : null
  }
  if (chapter > 1) return { osis, chapter: chapter - 1 }
  return list[i - 1] ? { osis: list[i - 1].osis, chapter: list[i - 1].chapters } : null
}

const STYLE = `
  html { background: var(--ui-bg, #F4EAD2); }
  body.ofr { margin: 0; min-height: 100vh; background: var(--ui-bg, #F4EAD2); color: var(--ui-fg, #231408);
    font-family: var(--ui-font, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif); }
  .ofr a { color: var(--ui-accent, #8A2418); }
  .ofr-bar { position: sticky; top: 0; z-index: 2; display: flex; gap: 8px; align-items: center; justify-content: space-between;
    padding: 10px 16px; background: var(--ui-elevated, #FBF5E6); border-bottom: 1px solid var(--ui-border, #D9C8A0); }
  .ofr-bar strong { font-size: 1.05rem; }
  .ofr-pill { display: inline-block; padding: 6px 12px; border-radius: 999px; border: 1px solid var(--ui-border-strong, #C2AE82);
    text-decoration: none; font-size: .9rem; white-space: nowrap; }
  .ofr-pill.is-on { background: var(--ui-accent, #8A2418); color: var(--ui-accent-fg, #FFF8EA); border-color: transparent; }
  .ofr-main { max-width: 36rem; margin: 0 auto; padding: 16px 16px 120px; }
  .ofr-note { font-size: .9rem; color: var(--ui-fg-muted, #4A3218); background: var(--ui-surface, #EFE3C5);
    border-radius: 10px; padding: 10px 12px; margin: 0 0 16px; }
  .ofr-title { font-family: "Source Serif 4", Georgia, serif; font-size: 1.6rem; margin: 8px 0 16px; }
  .ofr-verses { font-family: "Source Serif 4", Georgia, serif; font-size: 1.15rem; line-height: 1.75; }
  .ofr-verse { margin: 0 0 .35em; }
  .ofr-vnum { color: var(--ui-vnum, #8A2418); font-size: .7em; vertical-align: super; margin-right: .25em; }
  .ofr-nav { position: fixed; left: 0; right: 0; bottom: 16px; display: flex; justify-content: center; gap: 12px; pointer-events: none; }
  .ofr-nav a { pointer-events: auto; background: var(--ui-elevated, #FBF5E6); box-shadow: 0 4px 16px rgba(58,38,22,.18); }
  .ofr-versions { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 12px; }
  .ofr-books h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .08em; color: var(--ui-fg-subtle, #654A2B); margin: 20px 0 8px; }
  .ofr-books details { border-bottom: 1px solid var(--ui-border, #D9C8A0); padding: 10px 0; }
  .ofr-books summary { cursor: pointer; font-weight: 600; }
  .ofr-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(44px, 1fr)); gap: 6px; margin-top: 10px; }
  .ofr-grid a { display: block; text-align: center; padding: 10px 0; border-radius: 8px; background: var(--ui-surface, #EFE3C5); text-decoration: none; }
  .ofr-links { display: flex; flex-wrap: wrap; gap: 8px; margin: 20px 0; }
  .ofr-links a { padding: 10px 16px; }
`

// A whole page. `assets` = { css, js } — the app's own bundle, when cached:
// with it Turbo keeps driving visits (and the Hotwire Native apps stay happy).
export function page({ title, body, assets = {}, owner = "guest" }) {
  return "<!doctype html><html lang='en' data-theme='auto'><head><meta charset='utf-8'>" +
    "<meta name='viewport' content='width=device-width,initial-scale=1,viewport-fit=cover'>" +
    `<title>${esc(title)}</title>` +
    "<meta name='turbo-cache-control' content='no-cache'>" +
    (assets.css ? `<link rel='stylesheet' href='${esc(assets.css)}'>` : "") +
    `<style>${STYLE}</style>` +
    (assets.js ? `<script type='module' src='${esc(assets.js)}'></script>` : "") +
    `</head><body class='ofr' data-theme='auto' data-offline-owner='${esc(owner)}' data-offline-shell>${body}</body></html>`
}

const LINKS = [ [ "/read", "Bible" ], [ "/", "Home" ], [ "/reading_plans", "Plans" ], [ "/offline", "Offline Bibles" ] ]

export function links(except = null) {
  return `<nav class='ofr-links' aria-label='Pages that work offline'>${
    LINKS.filter(([ href ]) => href !== except).map(([ href, label ]) => `<a class='ofr-pill' href='${href}'>${esc(label)}</a>`).join("")
  }</nav>`
}

// One chapter. `verses` = [{ num, text }]. `note` = a line above (e.g. "That
// study isn't on this device yet").
export function renderChapter({ bible, downloaded, books, osis, chapter, verses, note, assets, owner }) {
  const book = (books || []).find((b) => b.osis === osis)
  const name = book?.name || osis
  const code = bible?.code
  const prev = neighbor(books, osis, chapter, "prev")
  const next = neighbor(books, osis, chapter, "next")
  const versions = (downloaded || []).length > 1
    ? `<div class='ofr-versions'>${downloaded.map((d) =>
        `<a class='ofr-pill${d.code === code ? " is-on" : ""}' data-turbo-action='replace' href='${esc(chapterPath(osis, chapter, d.code))}'>${esc(d.code)}</a>`).join("")}</div>`
    : ""
  const text = verses?.length
    ? verses.map((v) => `<p class='ofr-verse' data-verse-num='${esc(v.num)}'><sup class='ofr-vnum'>${esc(v.num)}</sup><span class='ofr-verse-text'>${esc(v.text)}</span></p>`).join("")
    : `<p class='ofr-note'>${esc(name)} ${esc(chapter)} isn&rsquo;t in the ${esc(code)} download.</p>`
  const nav = (place, label, rel) => place
    ? `<a class='ofr-pill' rel='${rel}' data-turbo-action='replace' href='${esc(chapterPath(place.osis, place.chapter, code))}'>${label}</a>`
    : ""
  const body =
    `<header class='ofr-bar'><a class='ofr-pill' href='${SHELL_ROOT}/books${code ? `?t=${esc(code)}` : ""}'>${esc(name)} ${esc(chapter)} &#9662;</a>` +
    `<strong>${esc(code || "")}</strong><a class='ofr-pill' href='/'>Home</a></header>` +
    `<main class='ofr-main'>` +
    (note ? `<p class='ofr-note' role='status'>${note}</p>` : "") +
    `<p class='ofr-note' data-offline-reader-badge>Offline &middot; reading from the Bible on this device</p>` +
    versions +
    `<h1 class='ofr-title' data-offline-reader-title>${esc(name)} ${esc(chapter)}</h1>` +
    `<div class='ofr-verses' data-offline-reader>${text}</div>` +
    links("/read") +
    `</main><nav class='ofr-nav' aria-label='Chapters'>${nav(prev, "&#8249; Previous", "prev")}${nav(next, "Next &#8250;", "next")}</nav>`
  return page({ title: `${name} ${chapter} · BiblioRata (offline)`, body, assets, owner })
}

// Every book, Old and New Testament, each opening onto its chapter grid.
export function renderBooks({ bible, books, assets, owner }) {
  const code = bible?.code
  const list = orderedBooks(books)
  const section = (title, items) => items.length
    ? `<h2>${title}</h2>` + items.map((b) =>
        `<details><summary>${esc(b.name)}</summary><div class='ofr-grid'>${
          Array.from({ length: b.chapters }, (_, k) => `<a href='${esc(chapterPath(b.osis, k + 1, code))}'>${k + 1}</a>`).join("")
        }</div></details>`).join("")
    : ""
  const body =
    `<header class='ofr-bar'><strong>Choose a book</strong><a class='ofr-pill' href='${SHELL_ROOT}'>Back</a></header>` +
    `<main class='ofr-main ofr-books'>` +
    `<p class='ofr-note'>Offline &middot; ${esc(code)} on this device</p>` +
    section("Old Testament", list.filter((b) => b.position <= 39)) +
    section("New Testament", list.filter((b) => b.position > 39)) +
    links() + `</main>`
  return page({ title: "Books · BiblioRata (offline)", body, assets, owner })
}

// No Bible on the device yet (it downloads by itself the first time the app
// opens with internet).
export function renderNoBible({ assets, owner }) {
  const body =
    `<main class='ofr-main'><h1 class='ofr-title'>Your Bible isn&rsquo;t on this device yet</h1>` +
    `<p>BiblioRata downloads the King James Bible by itself the first time it opens with internet, ` +
    `so you can read with no data. Connect once (Wi&#8209;Fi or data) and keep the app open for a minute.</p>` +
    `<p>You can also choose Bibles yourself on <a href='/offline'>Offline Bibles</a>.</p>` +
    links("/read") + `</main>`
  return page({ title: "Offline · BiblioRata", body, assets, owner })
}

// A page that isn't saved on this device. `tab` pages (the apps' start pages)
// get a calm explanation; other pages the classic "not saved" message.
export function renderOffline({ path = "/", tab = false, assets, owner }) {
  const what = {
    "/": "Home", "/reading_plans": "Reading plans", "/more": "More", "/search": "Search", "/faith": "The glossary", "/offline": "Offline Bibles"
  }[path]
  const heading = tab ? `${esc(what || "This page")} needs one visit with internet` : "You appear to be offline"
  const lead = tab
    ? (path === "/reading_plans"
        ? "Your reading plans are saved on this device after you open them once with internet (signed in)."
        : "It is saved on this device the first time you open it with internet.")
    : "This page isn&rsquo;t saved on this device."
  const body =
    `<main class='ofr-main'><h1 class='ofr-title'>${heading}</h1>` +
    `<p>${lead} Your Bible, and the pages you&rsquo;ve opened before, keep working without a connection.</p>` +
    links(path) +
    `<p><a href='${esc(path)}'>Try again</a></p></main>`
  return page({ title: "Offline · BiblioRata", body, assets, owner })
}
