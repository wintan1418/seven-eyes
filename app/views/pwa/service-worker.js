// Parallel Scripture service worker.
//
// Conservative caching:
//   • App shell (CSS, JS, fonts, icons): cache-first, no-query only. Rails
//     fingerprints assets so new deploys naturally land under fresh URLs.
//   • Top-level HTML pages (no query string): network-first with cache fallback.
//     We always try fresh first so users never get stuck on stale HTML; the
//     cache only kicks in when the network is unreachable (mid-sermon Wi-Fi drop).
//   • Everything else (POST/PATCH/DELETE, query-string URLs, cross-origin):
//     pass straight through, no caching.
//
// Versioned cache name — bumping CACHE_VERSION on deploy retires old caches.
// Bump this on every deploy that ships CSS/JS changes so old caches are
// retired by the activate handler below.
const CACHE_VERSION = "ps-2026-05-26-2"
const STATIC_CACHE  = `${CACHE_VERSION}-static`
const PAGES_CACHE   = `${CACHE_VERSION}-pages`

self.addEventListener("install", () => {
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => !k.startsWith(CACHE_VERSION)).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  if (/\/assets\//.test(url.pathname) ||
      /\.(css|js|png|jpg|jpeg|svg|woff2?|ttf|ico)$/i.test(url.pathname)) {
    // Stale-while-revalidate so fresh CSS/JS lands on the very next visit,
    // even for un-fingerprinted asset paths.
    event.respondWith(staleWhileRevalidate(request, STATIC_CACHE))
    return
  }

  const acceptsHTML = (request.headers.get("Accept") || "").includes("text/html")
  if (acceptsHTML && !url.search) {
    event.respondWith(networkFirst(request, PAGES_CACHE))
  }
})

async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName)
  const cached = await cache.match(request)
  const fetchPromise = fetch(request).then((fresh) => {
    if (fresh.ok && fresh.type !== "opaque") cache.put(request, fresh.clone())
    return fresh
  }).catch(() => cached || Response.error())
  return cached || fetchPromise
}

async function networkFirst(request, cacheName) {
  const cache = await caches.open(cacheName)
  try {
    const fresh = await fetch(request)
    if (fresh.ok) cache.put(request, fresh.clone())
    return fresh
  } catch (e) {
    const cached = await cache.match(request)
    if (cached) return cached
    return new Response(
      "<!doctype html><meta charset='utf-8'><title>Offline</title>" +
      "<body style='font-family:Georgia,serif; padding:64px; max-width:640px; margin:auto;'>" +
      "<h1>You appear to be offline</h1>" +
      "<p>This page hasn't been cached yet. Reconnect and try again.</p></body>",
      { status: 503, headers: { "Content-Type": "text/html; charset=utf-8" } }
    )
  }
}
