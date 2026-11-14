// Always ready offline (imported once by application.js). When a signed-in
// reader opens any page with a working network — at most once a day — the
// device gets, in the background:
//   1. Quick Present: the reader's own always-ready study (POST
//      /offline/prepare makes it once), its page + projector + stage screens
//      saved by the service worker, and its whole Bible downloaded — so
//      "New study" / "Present offline" with no internet opens straight into
//      preach mode;
//   2. the five most recent studies (+ projector screens), so they open
//      offline without pressing "Get ready for Sunday".
// Data Saver (navigator.connection.saveData) skips the downloads and the
// recent studies — only the small Quick Present pages are saved.
import { getMeta, setMeta, fetchManifest, storedManifest, downloadedBibles, downloadBible, requestPersistence } from "./store"
import { owner, signedIn, precachePages } from "./page"
import { quickFetch, isNetworkSlow } from "./network"
import { shouldPrepare, quickPresentPages, recentPages, bibleToDownload, isReady, presentUrl } from "./ready_plan"
// For everyone, guests too: the core pages saved as soon as the service worker
// runs (warm.js) and the KJV downloaded by itself (auto_bible.js).
import "./warm"
import "./auto_bible"

const QUICK_KEY = "quickPresent"   // { owner, id, url, name, reference, translation: { id, code }, readyAt }
const PREPARED_KEY = "offlinePreparedAt" // { owner, at }
const PAGES_CACHE = "ps-pages"
const PREPARE_TIMEOUT_MS = 8000
const START_DELAY_MS = 1500 // let the page itself load first

const saveData = () => !!(typeof navigator !== "undefined" && navigator.connection?.saveData)
const isScreen = () => /[?&](output|stage)=1\b/.test(window.location.search)
export const networkDown = () => navigator.onLine === false || isNetworkSlow()

// Is this page (by path) saved by the service worker?
export async function isPageSaved(path) {
  try {
    const cache = await window.caches.open(PAGES_CACHE)
    return !!(await cache.match(new URL(path, window.location.origin).href))
  } catch { return false }
}

// This reader's Quick Present, as last prepared on this device (or null).
export async function quickPresent() {
  const quick = await getMeta(QUICK_KEY).catch(() => null)
  return quick && quick.owner === owner() ? quick : null
}

// Quick Present when it can be projected with no internet, else null.
export async function readyQuickPresent() {
  const quick = await quickPresent()
  if (!quick) return null
  const [ pageSaved, downloaded ] = await Promise.all([ isPageSaved(quick.url), downloadedBibles() ])
  return isReady(quick, { owner: owner(), pageSaved, downloaded }) ? quick : null
}

// Ask the server for Quick Present (made once) and the recent studies.
async function fetchPlan() {
  const { res, body } = await quickFetch("/offline/prepare", {
    method: "POST",
    headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
  }, { timeoutMs: PREPARE_TIMEOUT_MS, read: "json" })
  return res.ok && body?.quick_present?.url ? body : null
}

let running = null
export function prepareOffline(options = {}) {
  running ||= run(options).catch(() => null).finally(() => { running = null })
  return running
}

async function run({ force = false } = {}) {
  const who = owner()
  const ready = !!(await readyQuickPresent())
  const last = await getMeta(PREPARED_KEY).catch(() => null)
  if (!shouldPrepare({ signedIn: signedIn(), online: navigator.onLine !== false, slow: isNetworkSlow(), screen: isScreen(),
                       last, owner: who, now: Date.now(), ready, force })) return quickPresent()
  if (!("serviceWorker" in navigator) || !window.caches) return null

  const plan = await fetchPlan()
  if (!plan) return null
  let quick = { ...plan.quick_present, owner: who, readyAt: (await quickPresent())?.readyAt || null }
  await setMeta(QUICK_KEY, quick)

  // The parser and book list (small), then the Bible itself (a few MB).
  const manifest = await fetchManifest().catch(() => storedManifest())
  const want = bibleToDownload({ code: quick.translation?.code, manifest, downloaded: await downloadedBibles(), saveData: saveData() })
  if (want) {
    await downloadBible(want)
    requestPersistence()
  }

  await precachePages([ ...quickPresentPages(quick), "/", "/offline" ])
  if (await readyQuickPresent()) {
    quick = { ...quick, readyAt: Date.now() }
    await setMeta(QUICK_KEY, quick)
    announce(quick)
  }

  const recent = recentPages(plan.recent, { saveData: saveData() })
  if (recent.length) await precachePages(recent)
  await setMeta(PREPARED_KEY, { owner: who, at: Date.now() })
  announce(quick)
  return quick
}

function announce(quick) {
  window.dispatchEvent(new CustomEvent("offline:prepared", { detail: { quickPresent: quick } }))
}

// "Present offline" / "New study" with no internet: open Quick Present
// straight into preach mode. Online, it doesn't need to be ready yet — make
// sure it exists and open it fresh. Resolves false (and says why) when it
// can't be opened.
export async function openQuickPresent() {
  const quick = await readyQuickPresent()
  if (quick) { visit(presentUrl(quick)); return true }

  if (!networkDown() && signedIn()) {
    const plan = await fetchPlan().catch(() => null)
    if (plan) {
      await setMeta(QUICK_KEY, { ...plan.quick_present, owner: owner(), readyAt: null }).catch(() => {})
      visit(presentUrl(plan.quick_present, { saved: false }))
      return true
    }
  }
  const message = signedIn()
    ? "Quick Present isn't on this device yet — open BiblioRata once with internet and it gets ready by itself."
    : "Presenting with no internet needs a free account — sign in once with internet and Quick Present gets ready on this device."
  window.dispatchEvent(new CustomEvent("offline:toast", { detail: { message } }))
  return false
}

function visit(url) {
  if (window.Turbo?.visit) window.Turbo.visit(url)
  else window.location.assign(url)
}

function start() {
  setTimeout(() => prepareOffline().catch(() => {}), START_DELAY_MS)
}

let started = false
function boot() {
  start()
  if (started) return
  started = true
  window.addEventListener("online", () => setTimeout(() => prepareOffline().catch(() => {}), START_DELAY_MS))
}

document.addEventListener("turbo:load", boot)
if (document.readyState !== "loading") boot()
