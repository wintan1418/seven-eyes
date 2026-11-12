// A network circuit breaker for preach mode. In church the worst connection
// is not "offline" (that fails at once) but "data on, nothing coming back":
// navigator.onLine stays true and a plain fetch hangs for 15–20 s. So every
// preach-mode request goes through quickFetch():
//   • a short timeout (2 s by default);
//   • a timeout or network error marks the network "slow" for 3 minutes, and
//     while it is slow quickFetch fails at once without touching the network,
//     so lookups go straight to the downloaded Bibles;
//   • a fast answer, or the browser's `online` event, clears the mark.
// The mark is shared with the service worker (meta "networkSlowUntil" in
// IndexedDB, plus a "network-slow" message on the ps-offline channel) so the
// worker's pane requests skip the network too. Runs in the page and the worker;
// the pure logic lives in breaker.js.
import { getMeta, setMeta } from "./db"
import { broadcast, subscribe } from "./outbox"
import { createBreaker, makeQuickFetch } from "./breaker"

export { QUICK_MS, SLOW_FOR_MS, NetworkUnavailable } from "./breaker"
export const META_KEY = "networkSlowUntil"

const breaker = createBreaker({
  onChange(until) {
    setMeta(META_KEY, until).catch(() => {})
    broadcast({ type: "network-slow", until })
  }
})

getMeta(META_KEY).then((v) => breaker.adopt(v)).catch(() => {})
subscribe((m) => { if (m?.type === "network-slow") breaker.adopt(m.until) })
try { self.addEventListener?.("online", () => breaker.reset()) } catch { /* no events here */ }

export const isNetworkSlow = () => breaker.isSlow()
export const markNetworkSlow = () => breaker.trip()
export const markNetworkFine = () => breaker.reset()

// For the service worker, which may have just woken up: read the stored mark.
export async function networkSlowStored() {
  breaker.adopt(await getMeta(META_KEY).catch(() => 0))
  return breaker.isSlow()
}

export const quickFetch = makeQuickFetch({
  breaker,
  fetchImpl: (...args) => fetch(...args),
  isOffline: () => typeof navigator !== "undefined" && navigator.onLine === false
})
