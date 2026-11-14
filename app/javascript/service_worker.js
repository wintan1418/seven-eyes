// BiblioRata service worker. Bundled by esbuild and inlined into
// app/views/pwa/service-worker.js.erb, which defines self.PS_SW first:
//   { version: "ps-<digest>", assets: [current application.js/css URLs] }
//
// What it does:
//   • Static assets: fingerprinted /assets/ are cache-first (kept across
//     deploys while a saved page still refers to them); other static files
//     and Google Fonts are stale-while-revalidate.
//   • The reader's own pages — the study (and its ?output=1 projector and
//     ?stage=1 screens), /read, the studies list, More, Offline Bibles, reading
//     plans — and public /p/:slug pages are network-first: a fresh copy is
//     saved on every visit and served when there is no signal. Cleared on
//     sign-out or when someone else signs in on the device.
//   • A pane's form submit (passage picker, version picker, prev/next chapter,
//     preach mode's chase, the projector mirroring) goes to the server first;
//     with no network the pane is rendered from the Bibles downloaded to
//     IndexedDB (lib/offline/offline_pane.js) — same markup as the server.
//   • /reference_check (preach Go box) is answered offline by the JS parser.
//   • Both skip the network entirely while it is marked slow (lib/offline/
//     network.js: a timeout marks it for 3 minutes; the page shares the mark).
//     So do saved pages; a saved page also never waits more than 4 s on a
//     request that hangs, and ?saved=1 ("Present offline") opens the saved
//     copy at once (refreshing it in the background).
//   • Writes queued offline (outbox) are replayed on Background Sync.
//   • Right after it takes control, and again every few hours online (the page
//     asks with a "warm" message, lib/offline/warm.js), it saves the app's core
//     pages — /read (and the study it lands on), /, /reading_plans (+ each
//     plan and its study), /more, /offline, /search, /faith — and the page
//     that registered it, which it wasn't controlling yet. One online visit
//     is enough for the apps' tabs to open with no data.
//   • With nothing saved, no page is a dead end: /read opens the last study,
//     else the newest saved one, else the offline reader (/offline/read,
//     drawn here from the downloaded Bible — lib/offline/shell.js); an unsaved
//     study opens the offline reader too; the tab start pages get a calm
//     "needs one visit" page (200) linking to what works. Other unsaved pages
//     get the friendly offline page with a 503 (the apps' own error screen).
//   • Everything else passes straight through.
// Redirected, non-200 or opaque responses are never cached as-is.
import { getMeta, setMeta } from "./lib/offline/db"
import { downloadedBibles, storedManifest, bookText } from "./lib/offline/store"
import { renderOfflinePane, offlineReferenceCheck } from "./lib/offline/offline_pane"
import { flushOutbox, queuePaneVisit } from "./lib/offline/outbox"
import { networkSlowStored, markNetworkSlow, markNetworkFine } from "./lib/offline/network"
import { chapterVerses } from "./lib/offline/pane_renderer"
import {
  SHELL_ROOT, DEFAULT_PLACE, parseShellPath, pickBible, renderChapter, renderBooks, renderNoBible, renderOffline
} from "./lib/offline/shell"

const CONFIG = self.PS_SW || { version: "ps-dev", assets: [] }
const CACHE_PREFIX = "ps-"
const CACHE_VERSION = CONFIG.version
const STATIC_CACHE = "ps-static"
const PAGES_CACHE = "ps-pages"
const FONTS_CACHE = "ps-fonts"
const KEEP = [ STATIC_CACHE, PAGES_CACHE, FONTS_CACHE ]

const PUBLIC_PAGE = /^\/p\/[^/]+\/?$/
const STUDY_PAGE = /^\/studies\/\d+$/
const OWN_PAGES = [
  /^\/$/, /^\/read$/, /^\/more$/, /^\/offline$/, /^\/search$/, /^\/faith$/, /^\/faith\/[\w-]+$/,
  /^\/reading_plans$/, /^\/reading_plans\/\d+$/
]
// The apps' tab start pages: always something usable offline, never the 503.
const TAB_PAGES = [ "/", "/read", "/reading_plans", "/more", "/search", "/offline", "/faith" ]
// Saved as soon as the worker controls the app, and refreshed while online.
const CORE_PAGES = [ "/read", "/", "/reading_plans", "/more", "/offline", "/search", "/faith" ]
const QUERY_FREE = [ "/read", "/search" ] // keyed without their ?parameters
const WARM_EVERY_MS = 6 * 60 * 60 * 1000
const MAX_WARM_PLANS = 8
const PANE_PATH = /^\/studies\/(\d+)\/panes\/(\d+)$/
const FONT_HOSTS = [ "fonts.googleapis.com", "fonts.gstatic.com" ]
// Only when a downloaded Bible can answer instead: a pane that hasn't come
// back in 2 s comes from the device (preach mode can't wait out a dead signal).
const PANE_TIMEOUT_MS = 2000
const CHECK_TIMEOUT_MS = 1500 // /reference_check — the JS parser can always answer
const PAGE_TIMEOUT_MS = 4000 // a saved page rather than wait on a request that hangs this long
const NO_COPY_TIMEOUT_MS = 15000 // a tab page with nothing saved: the "needs one visit" page after this long
const MAX_SAVED_PAGES = 60

self.addEventListener("install", () => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k.startsWith(CACHE_PREFIX) && !KEEP.includes(k) && !k.startsWith(CACHE_VERSION))
        .map((k) => caches.delete(k)))
    ).then(pruneStaticAssets).catch(() => {}).then(() => self.clients.claim())
  )
})

self.addEventListener("message", (event) => {
  const data = event.data || {}
  if (data.type === "clear-caches") {
    // Sign-out (or someone else signing in): drop every saved page. A warm-up
    // still saving the previous reader's pages stops; the next one waits.
    warmGeneration++
    clearing = caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k.startsWith(CACHE_PREFIX) && k !== STATIC_CACHE && k !== FONTS_CACHE)
        .map((k) => caches.delete(k))))
      .then(() => setMeta(WARM_KEY, null)).catch(() => {})
    event.waitUntil(clearing)
  } else if (data.type === "precache") {
    event.waitUntil(precache(data.urls || []).then((result) => reply(event, { type: "precached", id: data.id, ...result })))
  } else if (data.type === "status") {
    event.waitUntil(cacheStatus(data.urls || []).then((result) => reply(event, { type: "status", id: data.id, ...result })))
  } else if (data.type === "warm") {
    event.waitUntil(warm(data).catch(() => {}))
  } else if (data.type === "flush-outbox") {
    event.waitUntil(flushOutbox().catch(() => {}))
  }
})

self.addEventListener("sync", (event) => {
  if (event.tag === "ps-outbox") event.waitUntil(flushOutbox())
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  const url = new URL(request.url)

  if (url.origin !== self.location.origin) {
    if (request.method === "GET" && FONT_HOSTS.includes(url.hostname)) {
      event.respondWith(staleWhileRevalidate(request, FONTS_CACHE, event))
    }
    return
  }

  if (request.method === "POST" && PANE_PATH.test(url.pathname) && (request.headers.get("Turbo-Frame") || "").startsWith("pane_")) {
    event.respondWith(paneRequest(event, url))
    return
  }
  if (request.method !== "GET") return

  if (url.pathname === "/reference_check") {
    event.respondWith(referenceCheck(request, url))
    return
  }
  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(cacheFirst(request, STATIC_CACHE, event))
    return
  }
  if (/\.(css|js|png|jpg|jpeg|svg|woff2?|ttf|ico)$/i.test(url.pathname) && url.pathname !== "/service-worker") {
    event.respondWith(staleWhileRevalidate(request, STATIC_CACHE, event))
    return
  }

  if (!isPageRequest(request)) return
  if (parseShellPath(url.pathname)) {
    event.respondWith(shellResponse(url))
    return
  }
  const key = pageKey(url)
  if (key) {
    event.respondWith(networkFirst(event, key))
  } else if (request.mode === "navigate") {
    event.respondWith(networkOnly(request))
  }
})

// ---- pages ------------------------------------------------------------------

// A full page load or a Turbo Drive visit — not a Turbo Frame fetch.
function isPageRequest(request) {
  if (request.mode === "navigate") return true
  return (request.headers.get("Accept") || "").includes("text/html") && !request.headers.get("Turbo-Frame")
}

// The cache key for a page we keep, or null. A study keeps only ?output=1 /
// ?stage=1 (the projector and stage screens render differently); other
// parameters (?pane=, ?refs=) are read by page scripts, not the server.
function pageKey(url) {
  const path = url.pathname.replace(/(.)\/$/, "$1")
  if (STUDY_PAGE.test(path)) {
    const key = new URL(path, url.origin)
    if (url.searchParams.get("output") === "1") key.searchParams.set("output", "1")
    else if (url.searchParams.get("stage") === "1") key.searchParams.set("stage", "1")
    return key.href
  }
  // /read?ref=…&t=… (open at a verse) and /search?q=… are /read and /search
  // offline: the device answers them (offlineAnswer, the search_page controller).
  if (url.search && !QUERY_FREE.includes(path)) return null
  if (PUBLIC_PAGE.test(path) || OWN_PAGES.some((re) => re.test(path))) return new URL(path, url.origin).href
  return null
}

function cacheable(response) {
  return response && response.ok && response.status === 200 &&
    response.type === "basic" && (response.headers.get("Content-Type") || "").includes("text/html")
}

// A redirected response can't be replayed for a navigation: store a plain copy.
async function plainCopy(response) {
  if (!response.redirected) return response.clone()
  const body = await response.clone().blob()
  return new Response(body, { status: response.status, statusText: response.statusText, headers: response.headers })
}

async function savePage(response) {
  if (!cacheable(response)) return
  const key = pageKey(new URL(response.url))
  if (!key) return // redirected somewhere we don't keep (sign-in, a guest's expired study…)
  const cache = await caches.open(PAGES_CACHE)
  await cache.delete(key) // re-adding keeps the newest pages last
  await cache.put(key, await plainCopy(response))
  const keys = await cache.keys()
  for (const old of keys.slice(0, Math.max(0, keys.length - MAX_SAVED_PAGES))) await cache.delete(old)
  const path = new URL(key).pathname
  if (STUDY_PAGE.test(path) && !new URL(key).search) await setMeta("lastStudyUrl", path).catch(() => {})
}

async function networkFirst(event, key) {
  const request = event.request
  const path = new URL(key).pathname
  const cached = await caches.open(PAGES_CACHE).then((c) => c.match(key)).catch(() => null)
  // "Present offline" (?saved=1), or a network known to be dead: the saved
  // copy at once, refreshed in the background when there is a network.
  const slow = await networkSlowStored().catch(() => false)
  if (cached && (slow || new URL(request.url).searchParams.get("saved") === "1")) {
    if (!slow) event.waitUntil(fetch(request).then((fresh) => savePage(fresh)).catch(() => {}))
    return cached
  }

  const fresh = fetch(request).then((res) => {
    // waitUntil: WebKit may suspend the worker once the response is handed
    // over, before a background save finishes.
    event.waitUntil(savePage(res.clone()).catch(() => {}))
    return res
  })
  fresh.catch(() => {}) // when the saved copy answered first
  // "Data on but dead": don't wait out a hanging request when the device can
  // answer — a saved copy (or, for /read and a study, a downloaded Bible)
  // after 4 s; a tab page with nothing saved gets its "needs one visit" page
  // after 15 s. Anything else waits for the network as before.
  const alternative = cached || await hasOfflineAnswer(path)
  const waitMs = alternative ? (slow ? PAGE_TIMEOUT_MS / 2 : PAGE_TIMEOUT_MS) : (TAB_PAGES.includes(path) ? NO_COPY_TIMEOUT_MS : 0)
  let timer
  try {
    if (!waitMs) return await fresh
    const TIMED_OUT = Symbol("timeout")
    const winner = await Promise.race([
      fresh,
      new Promise((resolve) => { timer = setTimeout(() => resolve(TIMED_OUT), waitMs) })
    ])
    if (winner !== TIMED_OUT) return winner
    markNetworkSlow()
    return cached || await offlineAnswer(request, path) || offlineFallback(request, path)
  } catch (e) {
    return cached || await offlineAnswer(request, path) || offlineFallback(request, path)
  } finally {
    clearTimeout(timer)
  }
}

const pageMatch = (url) => caches.open(PAGES_CACHE).then((c) => c.match(new URL(url, self.location.origin).href)).catch(() => null)

// The study /read should open offline: the last one opened, else the newest
// study page saved on the device.
async function savedStudyUrl() {
  const last = await getMeta("lastStudyUrl").catch(() => null)
  if (last && await pageMatch(last)) return last
  const keys = await caches.open(PAGES_CACHE).then((c) => c.keys()).catch(() => [])
  for (const req of [ ...keys ].reverse()) {
    const u = new URL(req.url)
    if (STUDY_PAGE.test(u.pathname) && !u.search) return u.pathname
  }
  return null
}

// /read?ref=Deut 32:2&t=KJV offline: the saved study, opening at that verse
// (?open=…&tid=…, read by the verse-focus controller).
async function studyAt(study, params) {
  const url = new URL(study, self.location.origin)
  const ref = (params.get("ref") || "").trim()
  if (!ref) return url.href
  url.searchParams.set("open", ref.slice(0, 80))
  const code = (params.get("t") || "").toUpperCase()
  const manifest = code ? await storedManifest().catch(() => null) : null
  const t = manifest?.translations?.find((x) => x.code === code)
  if (t) url.searchParams.set("tid", String(t.id))
  return url.href
}

const hasBible = async () => (await downloadedBibles().catch(() => [])).length > 0

// Can the device open this page by itself (beyond a saved copy of it)?
async function hasOfflineAnswer(path) {
  if (path === "/read") return !!(await savedStudyUrl()) || await hasBible()
  if (STUDY_PAGE.test(path)) return hasBible()
  return false
}

// What the device shows for a page it has no saved copy of, or null.
async function offlineAnswer(request, path) {
  const isStudy = STUDY_PAGE.test(path) && !/[?&](output|stage)=1\b/.test(new URL(request.url).search)
  if (path === "/read") {
    const study = await savedStudyUrl()
    if (study) return Response.redirect(await studyAt(study, new URL(request.url).searchParams), 302)
    return Response.redirect(new URL(SHELL_ROOT, self.location.origin).href, 302)
  }
  if (isStudy && await hasBible()) return Response.redirect(new URL(`${SHELL_ROOT}?from=study`, self.location.origin).href, 302)
  if (TAB_PAGES.includes(path)) return htmlResponse(renderOffline({ path, tab: true, ...await shellContext() }))
  return null
}
async function networkOnly(request) {
  try {
    return await fetch(request)
  } catch (e) {
    return offlinePage(new URL(request.url).pathname)
  }
}

// Turbo Drive visits that fail get a network error, so Turbo (and the
// iOS/Android apps) treat it as "offline"; a real page load gets the friendly
// page — still a 503, which the apps show as their own offline screen.
async function offlineFallback(request, path = new URL(request.url).pathname) {
  return request.mode === "navigate" ? offlinePage(path) : Response.error()
}

async function offlinePage(path = "/") {
  return htmlResponse(renderOffline({ path, tab: false, ...await shellContext() }), 503)
}

const htmlResponse = (html, status = 200) =>
  new Response(html, { status, headers: { "Content-Type": "text/html; charset=utf-8", "X-Offline-Render": "1" } })

// ---- the offline reader (/offline/read…) ----------------------------------------

// The app's own CSS and JS for the pages drawn here — this version's when
// saved, else any saved copy (an older deploy's bundle still runs Turbo).
async function shellAssets() {
  const statics = await caches.open(STATIC_CACHE).catch(() => null)
  if (!statics) return {}
  const keys = await statics.keys().catch(() => [])
  const find = async (ext) => {
    const current = (CONFIG.assets || []).find((u) => u.split("?")[0].endsWith(ext))
    if (current && await statics.match(new URL(current, self.location.origin).href)) return current
    const any = [ ...keys ].reverse().find((r) => /^\/assets\/application-[\w]+\.\w+$/.test(new URL(r.url).pathname) && new URL(r.url).pathname.endsWith(ext))
    return any ? new URL(any.url).pathname : null
  }
  return { css: await find(".css"), js: await find(".js") }
}

async function shellContext() {
  return { assets: await shellAssets(), owner: (await getMeta("owner").catch(() => null)) || "guest" }
}

async function shellResponse(url) {
  const shell = parseShellPath(url.pathname)
  const context = await shellContext()
  const [ manifest, downloaded ] = await Promise.all([ storedManifest().catch(() => null), downloadedBibles().catch(() => []) ])
  const bible = pickBible(downloaded, url.searchParams.get("t"))
  if (!manifest?.books?.length || !bible) return htmlResponse(renderNoBible(context))
  const books = manifest.books
  if (shell.kind === "books") return htmlResponse(renderBooks({ bible, books, ...context }))

  let place = shell.kind === "chapter" ? shell : await getMeta("shellPlace").catch(() => null)
  const valid = (p) => p && books.some((b) => b.osis === p.osis && p.chapter >= 1 && p.chapter <= b.chapters)
  if (!valid(place)) place = DEFAULT_PLACE
  await setMeta("shellPlace", { osis: place.osis, chapter: place.chapter }).catch(() => {})
  const record = await bookText(bible.code, place.osis)
  const verses = chapterVerses(record, place.chapter)
  const note = url.searchParams.get("from") === "study"
    ? "That study isn&rsquo;t saved on this device yet &mdash; here is your Bible. The study opens once you&rsquo;re back online."
    : null
  return htmlResponse(renderChapter({ bible, downloaded, books, osis: place.osis, chapter: place.chapter, verses, note, ...context }))
}

// ---- panes --------------------------------------------------------------------

function fetchWithTimeout(request, ms) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), ms)
  return fetch(request, { signal: controller.signal }).finally(() => clearTimeout(timer))
}

// fetchWithTimeout that feeds the shared circuit breaker.
async function timed(request, ms) {
  const started = Date.now()
  try {
    const res = await fetchWithTimeout(request, ms)
    if (Date.now() - started < ms) markNetworkFine()
    return res
  } catch (e) {
    markNetworkSlow()
    throw e
  }
}

async function paneRequest(event, url) {
  const request = event.request
  const copy = request.clone()
  // A slow connection still gets its answer from the server — unless a
  // downloaded Bible can answer after a while instead.
  const canAnswer = (await downloadedBibles()).length > 0
  try {
    if (canAnswer && await networkSlowStored()) throw new Error("network marked slow")
    return await (canAnswer ? timed(request, PANE_TIMEOUT_MS) : fetch(request))
  } catch (e) {
    const [ , studyId, paneId ] = url.pathname.match(PANE_PATH)
    let form
    try { form = await copy.formData() } catch { return Response.error() }
    let context = {}
    try { context = JSON.parse(decodeURIComponent(copy.headers.get("X-Offline-Pane") || "")) || {} } catch { context = {} }
    const reference = form.get("pane[reference]")
    const translationId = form.get("pane[translation_id]") || context.translationId
    const html = await renderOfflinePane({
      studyId, paneId, reference, translationId, context, token: form.get("authenticity_token")
    }).catch(() => null)
    if (!html) return Response.error()
    // Remember where the reader went, so the study opens there once back online.
    if (!form.get("mirror")) {
      event.waitUntil(queuePaneVisit(url.pathname, { reference, translationId: form.get("pane[translation_id]") }, context.owner).catch(() => {}))
    }
    return new Response(html, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", "X-Offline-Render": "1" } })
  }
}

async function referenceCheck(request, url) {
  try {
    if (await networkSlowStored()) throw new Error("network marked slow")
    return await timed(request, CHECK_TIMEOUT_MS)
  } catch (e) {
    const body = await offlineReferenceCheck(url.searchParams.get("q") || "").catch(() => null)
    if (!body) return Response.error()
    return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } })
  }
}

// ---- static -----------------------------------------------------------------

// `event` (when given) keeps the worker alive until the cache write lands.
const keepAlive = (event, promise) => { if (event) event.waitUntil(promise.catch(() => {})); return promise }

async function cacheFirst(request, cacheName, event) {
  const cache = await caches.open(cacheName)
  const cached = await cache.match(request)
  if (cached) return cached
  const fresh = await fetch(request)
  if (fresh && fresh.ok && fresh.status === 200 && fresh.type === "basic" && !fresh.redirected) {
    const put = cache.put(request, fresh.clone())
    if (event) keepAlive(event, put)
    else await put
  }
  return fresh
}

async function staleWhileRevalidate(request, cacheName, event) {
  const cache = await caches.open(cacheName)
  const cached = await cache.match(request)
  const fetchPromise = fetch(request).then((fresh) => {
    // Fonts come cross-origin with CORS ("cors"); never store opaque responses.
    if (fresh && fresh.ok && (fresh.type === "basic" || fresh.type === "cors") && !fresh.redirected) {
      return cache.put(request, fresh.clone()).then(() => fresh, () => fresh)
    }
    return fresh
  }).catch(() => cached || Response.error())
  if (event) keepAlive(event, fetchPromise)
  return cached || fetchPromise
}

// Asset URLs a saved page refers to.
function assetUrls(html) {
  const out = new Set()
  for (const m of html.matchAll(/(?:href|src)="(\/assets\/[^"]+|\/icon\.(?:png|svg)|https:\/\/fonts\.googleapis\.com\/[^"]+)"/g)) {
    out.add(m[1].replace(/&amp;/g, "&"))
  }
  return [ ...out ]
}

// Keep fingerprinted assets only while the current version or a saved page uses them.
async function pruneStaticAssets() {
  const keep = new Set((CONFIG.assets || []).map((u) => new URL(u, self.location.origin).href))
  const pages = await caches.open(PAGES_CACHE)
  for (const req of await pages.keys()) {
    const res = await pages.match(req)
    if (!res) continue
    assetUrls(await res.text()).forEach((u) => keep.add(new URL(u, self.location.origin).href))
  }
  const statics = await caches.open(STATIC_CACHE)
  for (const req of await statics.keys()) {
    if (new URL(req.url).pathname.startsWith("/assets/") && !keep.has(req.url)) await statics.delete(req)
  }
}

// ---- precache (Get ready for Sunday, reading plans) --------------------------

// Fetch pages (and everything they load) into the caches. Returns { ok, failed }.
async function precache(urls) {
  let ok = 0
  const failed = []
  for (const raw of urls) {
    if (await saveForOffline(raw) !== null) ok++
    else { const u = new URL(raw, self.location.origin); failed.push(u.pathname + u.search) }
  }
  return { ok, failed }
}

// Save one page and its assets. Resolves to its HTML, or null when it can't
// be kept (offline, an error page, a redirect to sign-in, a 404…).
async function saveForOffline(raw) {
  const url = new URL(raw, self.location.origin)
  try {
    // X-Offline-Precache: saving a study isn't opening it (it keeps its place in "recent").
    const res = await fetch(url.href, { credentials: "same-origin", headers: { Accept: "text/html", "X-Offline-Precache": "1" } })
    if (!cacheable(res) || !pageKey(new URL(res.url))) return null
    await savePage(res.clone())
    const html = await res.text()
    for (const asset of assetUrls(html)) {
      const req = new Request(new URL(asset, self.location.origin).href, asset.startsWith("http") ? { mode: "cors" } : {})
      if (asset.startsWith("http")) await staleWhileRevalidate(req, FONTS_CACHE).catch(() => {})
      else await (asset.startsWith("/assets/") ? cacheFirst(req, STATIC_CACHE) : staleWhileRevalidate(req, STATIC_CACHE)).catch(() => {})
    }
    return html
  } catch (e) {
    return null
  }
}

// ---- warm: the core pages, saved by themselves (lib/offline/warm.js asks) --------

const WARM_KEY = "warmedAt" // { version, owner, at }
let warming = null // { owner, promise }
let warmGeneration = 0 // bumped when saved pages are cleared: a running warm-up stops
let clearing = Promise.resolve()

// data: { owner, signedIn, url } — url is the page that registered the worker
// (not controlled, so its load wasn't saved).
async function warm(data = {}) {
  if (data.url) {
    const key = pageKey(new URL(data.url, self.location.origin))
    if (key && !(await pageMatch(key))) await saveForOffline(data.url)
  }
  const owner = data.owner || "guest"
  if (warming?.owner === owner) return warming.promise
  // Someone else (say, the guest on the sign-in page) is still being warmed:
  // the new reader's pages follow once that run notices it was cleared.
  const before = warming?.promise || Promise.resolve()
  const run = { owner }
  run.promise = before.catch(() => {}).then(() => runWarm({ ...data, owner }))
    .finally(() => { if (warming === run) warming = null })
  warming = run
  return run.promise
}

async function runWarm({ owner = "guest", signedIn = false } = {}) {
  await clearing
  const generation = warmGeneration
  const stale = () => generation !== warmGeneration
  const last = await getMeta(WARM_KEY).catch(() => null)
  if (last && last.version === CACHE_VERSION && last.owner === owner && Date.now() - last.at < WARM_EVERY_MS) return

  let ok = 0
  const htmlOf = {}
  for (const page of CORE_PAGES) {
    if (stale()) return
    const html = await saveForOffline(page)
    if (html !== null) { ok++; htmlOf[page] = html }
  }
  // Each reading plan the reader has, and the study its readings open in.
  if (signedIn && htmlOf["/reading_plans"]) {
    const plans = [ ...new Set([ ...htmlOf["/reading_plans"].matchAll(/href="(\/reading_plans\/\d+)"/g) ].map((m) => m[1])) ]
    const studies = new Set()
    for (const plan of plans.slice(0, MAX_WARM_PLANS)) {
      if (stale()) return
      const html = await saveForOffline(plan)
      const study = html?.match(/data-plan-offline-study-url-value="(\/studies\/\d+)"/)?.[1]
      if (study) studies.add(study)
    }
    for (const study of studies) {
      if (!(await pageMatch(study))) await saveForOffline(study)
    }
  }
  if (ok && !stale()) await setMeta(WARM_KEY, { version: CACHE_VERSION, owner, at: Date.now() }).catch(() => {})
}

// Which of these pages are saved for offline use.
async function cacheStatus(urls) {
  const cache = await caches.open(PAGES_CACHE)
  const saved = []
  for (const raw of urls) {
    const key = pageKey(new URL(raw, self.location.origin))
    if (key && await cache.match(key)) saved.push(raw)
  }
  return { saved }
}

function reply(event, message) {
  if (event.ports?.[0]) event.ports[0].postMessage(message)
  else event.source?.postMessage?.(message)
}
