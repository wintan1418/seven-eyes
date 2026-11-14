// node --test test/javascript — the pages the service worker draws with no
// network (app/javascript/lib/offline/shell.js) and the automatic KJV download
// decision (ready_plan.js). Run by test/javascript/js_units_test.rb.
import { test } from "node:test"
import assert from "node:assert/strict"
import {
  parseShellPath, chapterPath, pickBible, neighbor, renderChapter, renderBooks, renderNoBible, renderOffline
} from "../../app/javascript/lib/offline/shell.js"
import { autoBibleToDownload, AUTO_RETRY_MS, autoBibleDelay } from "../../app/javascript/lib/offline/ready_plan.js"

const books = [
  { osis: "Mal", name: "Malachi", chapters: 4, position: 39 },
  { osis: "Matt", name: "Matthew", chapters: 28, position: 40 },
  { osis: "Gen", name: "Genesis", chapters: 50, position: 1 },
  { osis: "Rev", name: "Revelation", chapters: 22, position: 66 }
]

test("reads the offline reader's addresses", () => {
  assert.deepEqual(parseShellPath("/offline/read"), { kind: "last" })
  assert.deepEqual(parseShellPath("/offline/read/"), { kind: "last" })
  assert.deepEqual(parseShellPath("/offline/read/books"), { kind: "books" })
  assert.deepEqual(parseShellPath("/offline/read/John/3"), { kind: "chapter", osis: "John", chapter: 3 })
  assert.deepEqual(parseShellPath("/offline/read/1Cor/13"), { kind: "chapter", osis: "1Cor", chapter: 13 })
  for (const p of [ "/offline", "/offline/bibles", "/offline/read/John", "/read", "/offline/read/John/x" ]) assert.equal(parseShellPath(p), null, p)
  assert.equal(chapterPath("John", 3), "/offline/read/John/3")
  assert.equal(chapterPath("John", 3, "KJV"), "/offline/read/John/3?t=KJV")
})

test("reads the KJV when it is there, else what is downloaded", () => {
  const kjv = { code: "KJV" }, bsb = { code: "BSB" }
  assert.equal(pickBible([ bsb, kjv ]), kjv)
  assert.equal(pickBible([ bsb, kjv ], "bsb"), bsb)
  assert.equal(pickBible([ bsb ], "WEB"), bsb)
  assert.equal(pickBible([]), null)
})

test("walks chapters across books, in canon order", () => {
  assert.deepEqual(neighbor(books, "Matt", 5, "next"), { osis: "Matt", chapter: 6 })
  assert.deepEqual(neighbor(books, "Matt", 1, "prev"), { osis: "Mal", chapter: 4 })
  assert.deepEqual(neighbor(books, "Mal", 4, "next"), { osis: "Matt", chapter: 1 })
  assert.equal(neighbor(books, "Gen", 1, "prev"), null)
  assert.equal(neighbor(books, "Rev", 22, "next"), null)
  assert.equal(neighbor(books, "Nope", 1, "next"), null)
})

test("draws a chapter with prev/next, versions and the app's own bundle", () => {
  const html = renderChapter({
    bible: { code: "KJV" }, downloaded: [ { code: "KJV" }, { code: "BSB" } ], books, osis: "Matt", chapter: 1,
    verses: [ { num: 1, text: "The book of the generation <of> Jesus" } ],
    assets: { css: "/assets/application-abc.css", js: "/assets/application-abc.js" }, owner: "u-7"
  })
  assert.match(html, /<h1 class='ofr-title'[^>]*>Matthew 1<\/h1>/)
  assert.match(html, /The book of the generation &lt;of&gt; Jesus/)
  assert.match(html, /rel='prev' data-turbo-action='replace' href='\/offline\/read\/Mal\/4\?t=KJV'/)
  assert.match(html, /rel='next' data-turbo-action='replace' href='\/offline\/read\/Matt\/2\?t=KJV'/)
  assert.match(html, /href='\/offline\/read\/Matt\/1\?t=BSB'>BSB/)
  assert.match(html, /<script type='module' src='\/assets\/application-abc\.js'>/)
  assert.match(html, /data-offline-owner='u-7'/, "keeps the reader's offline data (page.js compares owners)")
  assert.match(html, /href='\/reading_plans'/)
})

test("lists every book by testament with its chapters", () => {
  const html = renderBooks({ bible: { code: "KJV" }, books })
  assert.ok(html.indexOf("Genesis") < html.indexOf("Malachi") && html.indexOf("Malachi") < html.indexOf("New Testament"))
  assert.match(html, /href='\/offline\/read\/Rev\/22\?t=KJV'>22</)
})

test("offline pages always link to what works", () => {
  for (const html of [ renderOffline({ path: "/more", tab: true }), renderOffline({ path: "/studies/9" }) ]) {
    assert.match(html, /href='\/read'/)
    assert.match(html, /href='\/'/)
  }
  assert.match(renderNoBible({}), /href='\/offline'/)
  assert.match(renderOffline({ path: "/reading_plans", tab: true }), /Reading plans needs one visit/)
  assert.match(renderOffline({ path: "/studies/9" }), /You appear to be offline/)
})

const manifest = { default_code: "BSB", translations: [ { code: "BSB", version: "b1" }, { code: "KJV", version: "k2" } ] }

test("downloads the KJV by itself, for guests too, once per version", () => {
  assert.equal(autoBibleToDownload({ manifest, downloaded: [] }).code, "KJV")
  assert.equal(autoBibleToDownload({ manifest, downloaded: [ { code: "KJV", version: "k2" } ] }), null)
  assert.equal(autoBibleToDownload({ manifest, downloaded: [ { code: "KJV", version: "k1" } ] }).code, "KJV", "an update")
  assert.equal(autoBibleToDownload({ manifest: { default_code: "BSB", translations: [ { code: "BSB" } ] }, downloaded: [] }).code, "BSB")
  assert.equal(autoBibleToDownload({ manifest: null, downloaded: [] }), null)
})

test("Data Saver stops it on the web, never in the apps", () => {
  assert.equal(autoBibleToDownload({ manifest, downloaded: [], saveData: true }), null)
  assert.equal(autoBibleToDownload({ manifest, downloaded: [], saveData: true, native: true }).code, "KJV")
  assert.ok(autoBibleDelay({ native: true }) < autoBibleDelay({ native: false }))
})

test("not offline, on a dead network, in the screens, after a failure, or once removed by hand", () => {
  for (const off of [ { online: false }, { slow: true }, { screen: true }, { optedOut: true } ]) {
    assert.equal(autoBibleToDownload({ manifest, downloaded: [], native: true, ...off }), null, JSON.stringify(off))
  }
  const now = 100 * AUTO_RETRY_MS
  assert.equal(autoBibleToDownload({ manifest, downloaded: [], lastFailedAt: now - 1000, now }), null)
  assert.equal(autoBibleToDownload({ manifest, downloaded: [], lastFailedAt: now - AUTO_RETRY_MS, now }).code, "KJV")
})

import { renderPane } from "../../app/javascript/lib/offline/pane_renderer.js"

test("an offline-drawn pane carries the phone pager and the verse focus, like the server's", () => {
  const book = { osis: "John", name: "John", chapters: 21, position: 43 }
  const html = renderPane({
    studyId: 1, paneId: 2, position: 0, compare: false, token: "t", reference: "John 3",
    translation: { id: 1, code: "KJV", name: "King James Version", display_name: "King James Version" },
    translations: [], downloaded: [ { code: "KJV" } ], books: [ book ], highlights: [], icon: () => "", focus: "2-4"
  }, { ok: true, book, parsed: { chapter: 3, verseStart: null }, verses: [ { id: 9, chapter: 3, num: 1, text: "x" } ] })
  assert.match(html, /<div class="ps-verses" data-verse-focus="2-4">/)
  assert.match(html, /<nav class="rd-pager" aria-label="Previous and next chapter"><form[^>]*class="rd-pager-form"[^>]*>.*?class="rd-pager-btn is-prev"[^>]*><span>John 2<\/span>/)
  assert.match(html, /class="rd-pager-form is-next".*?class="rd-pager-btn is-next"[^>]*><span>John 4<\/span>/)
})

test("each offline page names the real page to return to once online", () => {
  const books = [ { osis: "John", name: "John", chapters: 21, position: 43 } ]
  const chapter = renderChapter({ bible: { code: "KJV" }, downloaded: [ { code: "KJV" } ], books, osis: "John", chapter: 3,
                                   verses: [ { num: 16, text: "For God so loved the world" } ] })
  assert.match(chapter, /data-online-href='\/read\?ref=John%203&amp;t=KJV'/)
  assert.match(renderBooks({ bible: { code: "KJV" }, books }), /data-online-href='\/read'/)
  assert.match(renderOffline({ path: "/reading_plans", tab: true }), /data-online-href='\/reading_plans'/)
})
