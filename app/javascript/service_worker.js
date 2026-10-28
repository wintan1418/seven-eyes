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
//   • Writes queued offline (outbox) are replayed on Background Sync.
//   • Everything else passes straight through. An uncached page offline gets
//     a small "you're offline" page.
// Redirected, non-200 or opaque responses are never cached as-is.
import { getMeta, setMeta } from "./lib/offline/db"
import { downloadedBibles } from "./lib/offline/store"
import { renderOfflinePane, offlineReferenceCheck } from "./lib/offline/offline_pane"
import { flushOutbox, queuePaneVisit } from "./lib/offline/outbox"

const CONFIG = self.PS_SW || { version: "ps-dev", assets: [] }
const CACHE_PREFIX = "ps-"
const CACHE_VERSION = CONFIG.version
const STATIC_CACHE = "ps-static"
const PAGES_CACHE = "ps-pages"
const FONTS_CACHE = "ps-fonts"
const KEEP = [ STATIC_CACHE, PAGES_CACHE, FONTS_CACHE ]

const PUBLIC_PAGE = /^\/p\/[^/]+\/?$/
const STUDY_PAGE = /^\/studies\/\d+$/
const OWN_PAGES = [ /^\/$/, /^\/read$/, /^\/more$/, /^\/offline$/, /^\/reading_plans$/, /^\/reading_plans\/\d+$/ ]
const PANE_PATH = /^\/studies\/(\d+)\/panes\/(\d+)$/
const FONT_HOSTS = [ "fonts.googleapis.com", "fonts.gstatic.com" ]
const PANE_TIMEOUT_MS = 8000 // only when a downloaded Bible can answer instead
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
    // Sign-out (or someone else signing in): drop every saved page.
    event.waitUntil(
      caches.keys().then((keys) =>
        Promise.all(keys.filter((k) => k.startsWith(CACHE_PREFIX) && k !== STATIC_CACHE && k !== FONTS_CACHE)
          .map((k) => caches.delete(k))))
    )
  } else if (data.type === "precache") {
    event.waitUntil(precache(data.urls || []).then((result) => reply(event, { type: "precached", id: data.id, ...result })))
  } else if (data.type === "status") {
    event.waitUntil(cacheStatus(data.urls || []).then((result) => reply(event, { type: "status", id: data.id, ...result })))
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
  if (url.search) return null
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
  try {
    const fresh = await fetch(request)
    // waitUntil: WebKit may suspend the worker once the response is handed
    // over, before a background save finishes.
    event.waitUntil(savePage(fresh.clone()).catch(() => {}))
    return fresh
  } catch (e) {
    const cached = await caches.open(PAGES_CACHE).then((c) => c.match(key))
    if (cached) return cached
    // /read opens your last study.
    if (new URL(key).pathname === "/read") {
      const last = await getMeta("lastStudyUrl")
      if (last) return Response.redirect(last, 302)
    }
    return offlineFallback(request)
  }
}

async function networkOnly(request) {
  try {
    return await fetch(request)
  } catch (e) {
    return offlinePage()
  }
}

// Turbo Drive visits that fail get a network error, so Turbo (and the
// iOS/Android apps) treat it as "offline"; a real page load gets the page.
function offlineFallback(request) {
  return request.mode === "navigate" ? offlinePage() : Response.error()
}

function offlinePage() {
  return new Response(
    "<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>" +
    "<title>Offline</title>" +
    "<body style='font-family:Georgia,serif; padding:64px 16px; max-width:640px; margin:auto; background:#f4e7c8; color:#2b2017;'>" +
    "<h1>You appear to be offline</h1>" +
    "<p>This page isn't saved on this device. Pages you've opened before, and the Bibles you've downloaded " +
    "(Offline Bibles), keep working without a connection.</p>" +
    "<p><a href='/read' style='color:#8a2418'>Open my Bible</a></p></body></html>",
    { status: 503, headers: { "Content-Type": "text/html; charset=utf-8" } }
  )
}

// ---- panes --------------------------------------------------------------------

function fetchWithTimeout(request, ms) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), ms)
  return fetch(request, { signal: controller.signal }).finally(() => clearTimeout(timer))
}

async function paneRequest(event, url) {
  const request = event.request
  const copy = request.clone()
  // A slow connection still gets its answer from the server — unless a
  // downloaded Bible can answer after a while instead.
  const canAnswer = (await downloadedBibles()).length > 0
  try {
    return await (canAnswer ? fetchWithTimeout(request, PANE_TIMEOUT_MS) : fetch(request))
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
    return await fetch(request)
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
    const url = new URL(raw, self.location.origin)
    try {
      const res = await fetch(url.href, { credentials: "same-origin", headers: { Accept: "text/html" } })
      if (!cacheable(res)) { failed.push(url.pathname + url.search); continue }
      await savePage(res.clone())
      for (const asset of assetUrls(await res.text())) {
        const req = new Request(new URL(asset, self.location.origin).href, asset.startsWith("http") ? { mode: "cors" } : {})
        if (asset.startsWith("http")) await staleWhileRevalidate(req, FONTS_CACHE).catch(() => {})
        else await (asset.startsWith("/assets/") ? cacheFirst(req, STATIC_CACHE) : staleWhileRevalidate(req, STATIC_CACHE)).catch(() => {})
      }
      ok++
    } catch (e) {
      failed.push(url.pathname + url.search)
    }
  }
  return { ok, failed }
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
