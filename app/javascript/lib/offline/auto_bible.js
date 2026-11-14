// The KJV downloads by itself, so the Bible opens with no data — the way a
// native Bible app works. On the first page load with internet (and after a
// deploy changes its version), for guests and signed-in readers alike:
//   • inside the iOS/Android apps (Hotwire Native) always, and first;
//   • on the web only when Data Saver (navigator.connection.saveData) is off.
// Progress is announced by store.downloadBible (`offline:bible-download`) and
// shown on the Offline Bibles page. The decision lives in ready_plan.js.
import { fetchManifest, storedManifest, downloadedBibles, downloadBible, requestPersistence, getMeta, setMeta } from "./store"
import { isNetworkSlow } from "./network"
import { warmLocal } from "./local_pane"
import { autoBibleToDownload, autoBibleDelay } from "./ready_plan"

const FAILED_KEY = "autoBibleFailedAt"
export const OPT_OUT_KEY = "autoBibleOptOut" // set when the reader removes it on Offline Bibles
const LOCK = "ps-auto-bible"

export const isNativeApp = () => typeof navigator !== "undefined" && /(Hotwire|Turbo) Native/.test(navigator.userAgent)
const saveData = () => !!navigator.connection?.saveData
const isScreen = () => /[?&](output|stage)=1\b/.test(window.location.search)

let running = null

export function autoDownloadBible() {
  running ||= withLock(run).catch(() => null).finally(() => { running = null })
  return running
}

// One tab at a time (Web Locks where there are any).
function withLock(fn) {
  if (navigator.locks?.request) return navigator.locks.request(LOCK, { ifAvailable: true }, (lock) => (lock ? fn() : null))
  return fn()
}

async function run() {
  const base = { native: isNativeApp(), saveData: saveData(), online: navigator.onLine !== false, slow: isNetworkSlow(), screen: isScreen() }
  // Cheap checks first: no manifest request on Data Saver, offline…
  if (!autoBibleToDownload({ ...base, manifest: { translations: [ { code: "KJV" } ] }, downloaded: [] })) return null
  const lastFailedAt = Number(await getMeta(FAILED_KEY).catch(() => 0)) || 0
  let manifest
  try { manifest = await fetchManifest() } catch { manifest = await storedManifest().catch(() => null) }
  const optedOut = !!(await getMeta(OPT_OUT_KEY).catch(() => false))
  const want = autoBibleToDownload({ ...base, manifest, downloaded: await downloadedBibles(), lastFailedAt, optedOut })
  if (!want) return null
  try {
    const record = await downloadBible(want)
    await setMeta(FAILED_KEY, 0).catch(() => {})
    requestPersistence()
    warmLocal({ force: true })
    return record
  } catch (e) {
    await setMeta(FAILED_KEY, Date.now()).catch(() => {})
    return null
  }
}

let started = false
function boot() {
  if (started) return
  started = true
  setTimeout(() => autoDownloadBible(), autoBibleDelay({ native: isNativeApp() }))
  window.addEventListener("online", () => setTimeout(() => autoDownloadBible(), 1500))
}

document.addEventListener("turbo:load", boot)
if (document.readyState !== "loading") boot()
