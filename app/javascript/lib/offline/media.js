// Pictures kept on the device for a service with no internet (My Media,
// queue pictures). One Cache Storage cache, "ps-media", keyed by the picture's
// own URL — the one the queue, Preview, the projector (?output=1) and the
// stage use — so the service worker answers those <img> requests from here
// when the network is gone (service_worker.js → mediaResponse). Cleared on
// sign-out with the other personal caches; kept across deploys.
//
//   isMediaUrl(url, origin)          a picture URL this cache can hold
//   saveMedia(urls, {onProgress})    download what isn't saved yet
//   mediaOnDevice(urls)              which of these are saved (Set of the URLs given)
//   mediaPlan(urls, saved)           what's left to save / counts (pure, node-tested)
//
// Pictures come from our own Active Storage (/rails/active_storage/…, a
// redirect to the file — saved as a plain copy under the redirect URL) or
// from Cloudinary (cross-origin: CORS when it allows, else an opaque copy an
// <img> can still show).
export const MEDIA_CACHE = "ps-media"
const MEDIA_PATH = /^\/rails\/active_storage\/(blobs|representations)\//
const MEDIA_HOSTS = [ "res.cloudinary.com" ]
const SAVE_TIMEOUT_MS = 60_000

export function isMediaUrl(raw, origin) {
  let url
  try { url = new URL(raw, origin) } catch { return false }
  if (url.origin === origin) return MEDIA_PATH.test(url.pathname)
  return url.protocol === "https:" && MEDIA_HOSTS.includes(url.hostname)
}

export const mediaKey = (raw, origin) => new URL(raw, origin).href

// urls → { todo: [...], saved: n, total: n } — unique media URLs only.
export function mediaPlan(urls, saved = new Set(), origin = "https://bibliorata.com") {
  const unique = [ ...new Set((urls || []).filter((u) => u && isMediaUrl(u, origin))) ]
  const todo = unique.filter((u) => !saved.has(u))
  return { todo, saved: unique.length - todo.length, total: unique.length }
}

const here = () => (typeof self !== "undefined" && self.location ? self.location.origin : "https://bibliorata.com")

async function openCache() {
  if (typeof caches === "undefined") return null
  try { return await caches.open(MEDIA_CACHE) } catch { return null }
}

export async function mediaOnDevice(urls) {
  const cache = await openCache()
  const saved = new Set()
  if (!cache) return saved
  for (const u of new Set(urls || [])) {
    if (!u || !isMediaUrl(u, here())) continue
    try { if (await cache.match(mediaKey(u, here()))) saved.add(u) } catch { /* ignore */ }
  }
  return saved
}

// Save each picture not yet on the device. onProgress({ done, total, saved, failed }).
// Resolves { saved, failed, total } (saved counts those already there too).
export async function saveMedia(urls, { onProgress, signal } = {}) {
  const cache = await openCache()
  const already = await mediaOnDevice(urls)
  const { todo, saved: have, total } = mediaPlan(urls, already, here())
  if (!cache) return { saved: have, failed: todo.length, total, unsupported: true }
  let saved = have
  let failed = 0
  let done = have
  onProgress?.({ done, total, saved, failed })
  for (const u of todo) {
    if (signal?.aborted) break
    const ok = await saveOne(cache, u, signal)
    if (ok) saved++
    else failed++
    done++
    onProgress?.({ done, total, saved, failed })
  }
  return { saved, failed, total }
}

async function saveOne(cache, raw, signal) {
  const key = mediaKey(raw, here())
  const sameOrigin = new URL(key).origin === here()
  try {
    let res = await timedFetch(key, sameOrigin ? { credentials: "same-origin" } : { mode: "cors", credentials: "omit" }, signal)
    if (!sameOrigin && (!res || !res.ok)) res = await timedFetch(key, { mode: "no-cors", credentials: "omit" }, signal)
    if (!res || !(res.ok || res.type === "opaque")) return false
    if (res.type === "opaque") { await cache.put(key, res); return true }
    // A redirect (Active Storage) can't be replayed for an <img>: keep a plain copy.
    const body = await res.blob()
    if (!body.size || !(body.type || "").startsWith("image/")) return false
    await cache.put(key, new Response(body, { status: 200, headers: { "Content-Type": body.type, "Content-Length": String(body.size) } }))
    return true
  } catch {
    return false
  }
}

async function timedFetch(url, options, signal) {
  const controller = new AbortController()
  const abort = () => controller.abort()
  signal?.addEventListener?.("abort", abort)
  const timer = setTimeout(abort, SAVE_TIMEOUT_MS)
  try {
    return await fetch(url, { ...options, signal: controller.signal })
  } catch {
    return null
  } finally {
    clearTimeout(timer)
    signal?.removeEventListener?.("abort", abort)
  }
}

// Service worker: the saved copy of a picture, else the network (nothing is
// saved here — only "Save for offline" / "Get ready" / entering preach do).
export async function mediaResponse(request) {
  const cache = await openCache()
  const hit = cache ? await cache.match(request.url).catch(() => null) : null
  if (hit) return hit
  try {
    return await fetch(request)
  } catch (e) {
    return Response.error()
  }
}
