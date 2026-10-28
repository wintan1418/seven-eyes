// Page-side glue for offline use (imported once by application.js):
//   • tells the service worker what it needs to render a pane offline (the
//     X-Offline-Pane header on every pane frame request),
//   • keeps the notes text when a pane is re-rendered offline,
//   • records who the offline data belongs to and the CSRF token the outbox
//     replays with; wipes saved pages when a different reader signs in,
//   • replays the outbox on load and when the connection comes back,
//   • refreshes the cached highlights now and then.
import { getMeta, setMeta, downloadedBibles, refreshHighlights, clearPersonal } from "./store"
import { flushOutbox, pendingCount, pendingOps, subscribe } from "./outbox"

const HIGHLIGHTS_EVERY_MS = 10 * 60 * 1000

export const owner = () => document.body?.dataset.offlineOwner || "guest"
export const signedIn = () => document.body?.dataset.nativeSignedIn === "true"

// ---- pane requests --------------------------------------------------------------

document.addEventListener("turbo:before-fetch-request", (event) => {
  const headers = event.detail?.fetchOptions?.headers
  const frameId = headers?.["Turbo-Frame"]
  if (!frameId || !frameId.startsWith("pane_")) return
  const frame = document.getElementById(frameId)
  const context = {
    position: Number(frame?.dataset.panePosition || 0),
    compare: !!frame?.closest(".ps-root.is-compare"),
    signedIn: signedIn(),
    owner: owner(),
    translationId: frame?.querySelector("select[name='pane[translation_id]']")?.value || null
  }
  headers["X-Offline-Pane"] = encodeURIComponent(JSON.stringify(context))
})

// An offline-rendered pane doesn't know the notes: carry them over from the
// frame it replaces (the notes controller then layers on any queued edit).
document.addEventListener("turbo:before-frame-render", (event) => {
  const newFrame = event.detail?.newFrame
  if (!newFrame?.querySelector(".rd-pane-meta[data-offline]")) return
  const oldForm = event.target.querySelector("form[data-controller~='notes']")
  const newForm = newFrame.querySelector("form[data-controller~='notes']")
  if (!oldForm || !newForm) return
  const oldArea = oldForm.querySelector("textarea[name='pane[notes]']")
  const newArea = newForm.querySelector("textarea[name='pane[notes]']")
  if (oldArea && newArea) newArea.textContent = oldArea.value
  if (oldForm.dataset.notesRevisionValue) newForm.dataset.notesRevisionValue = oldForm.dataset.notesRevisionValue
  const status = newForm.querySelector("[data-notes-target='status']")
  if (status && oldArea?.value) status.innerHTML = "&mdash; Saved"
  if (oldArea?.value) newFrame.querySelector("[data-action~='pane#toggleNotes'].ps-pane-tool")?.classList.add("has-notes")
})

// ---- who, token, sync ---------------------------------------------------------------

async function syncSession() {
  const current = owner()
  const previous = await getMeta("owner")
  if (previous && previous !== current) {
    // Someone else's pages and highlights must not show for this reader. Their
    // queued writes stay (tagged with them) until they sign out properly.
    await clearPersonal({ outbox: false })
    clearSavedPages()
  }
  await setMeta("owner", current)
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  if (token) await setMeta("csrf", token)
}

async function refreshIfStale() {
  if (!signedIn() || !navigator.onLine) return
  if (!(await downloadedBibles()).length) return
  const at = (await getMeta("highlightsAt")) || 0
  if (Date.now() - at < HIGHLIGHTS_EVERY_MS) return
  await refreshHighlights().catch(() => {})
}

export async function syncNow() {
  if (!navigator.onLine) return null
  if (!(await pendingCount().catch(() => 0)) && !(await hasPaneVisits())) return null
  const result = await flushOutbox().catch(() => null)
  if (result?.sent && signedIn()) await refreshHighlights().catch(() => {})
  return result
}

async function hasPaneVisits() {
  return (await pendingOps()).some((op) => op.kind === "pane")
}

export function clearSavedPages() {
  try { navigator.serviceWorker?.controller?.postMessage({ type: "clear-caches" }) } catch { /* no worker */ }
  try {
    window.caches?.keys().then((keys) =>
      keys.filter((k) => k.startsWith("ps-") && k !== "ps-static" && k !== "ps-fonts").forEach((k) => window.caches.delete(k))
    ).catch(() => {})
  } catch { /* caches unavailable (private mode) */ }
}

// Ask the service worker to save pages (and their assets) for offline use.
export function precachePages(urls) {
  return askWorker({ type: "precache", urls })
}

export function savedPages(urls) {
  return askWorker({ type: "status", urls })
}

async function askWorker(message, timeoutMs = 60000) {
  const reg = await navigator.serviceWorker?.ready
  const worker = navigator.serviceWorker?.controller || reg?.active
  if (!worker) return null
  return new Promise((resolve) => {
    const channel = new MessageChannel()
    const timer = setTimeout(() => resolve(null), timeoutMs)
    channel.port1.onmessage = (e) => { clearTimeout(timer); resolve(e.data) }
    worker.postMessage({ ...message, id: Math.random().toString(36).slice(2) }, [ channel.port2 ])
  })
}

// A highlight made offline got its real id: rename it on the page.
subscribe((message) => {
  if (message?.type !== "highlight-id") return
  document.querySelectorAll(`[data-highlight-id="${CSS.escape(String(message.tmp))}"]`)
    .forEach((el) => { el.dataset.highlightId = message.id })
})

let started = false
function start() {
  syncSession().then(refreshIfStale).then(syncNow).catch(() => {})
  if (started) return
  started = true
  window.addEventListener("online", () => { syncNow().catch(() => {}); refreshIfStale().catch(() => {}) })
}

document.addEventListener("turbo:load", start)
if (document.readyState !== "loading") start()
