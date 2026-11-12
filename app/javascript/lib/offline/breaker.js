// The pure parts of the network circuit breaker (network.js wires them to
// IndexedDB, the ps-offline channel and the real fetch). No browser globals,
// so test/javascript/network_test.mjs runs them under node.
export const QUICK_MS = 2000
export const SLOW_FOR_MS = 3 * 60 * 1000

export function createBreaker({ now = () => Date.now(), slowForMs = SLOW_FOR_MS, onChange = () => {} } = {}) {
  let until = 0
  return {
    isSlow: () => now() < until,
    until: () => until,
    trip() { until = now() + slowForMs; onChange(until) },
    reset() { if (until) { until = 0; onChange(0) } },
    // Adopt a mark set elsewhere (another tab, the service worker) — no echo.
    adopt(value) { until = Number(value) || 0 }
  }
}

export class NetworkUnavailable extends Error {
  constructor(reason) { super(`network ${reason}`); this.reason = reason }
}

// fetch() with a deadline that also covers reading the body: `read` is
// "json" | "text" | null. Resolves to { res, body }. Throws NetworkUnavailable
// ("offline" | "slow" | "timeout" | "error") — at once, without touching the
// network, when it is known to be bad. A timeout or network error trips the
// breaker; a fast answer resets it. An HTTP error status is a working network.
export function makeQuickFetch({ breaker, fetchImpl, isOffline = () => false, now = () => Date.now() }) {
  return async function quickFetch(url, options = {}, { timeoutMs = QUICK_MS, read = null, force = false } = {}) {
    if (isOffline()) throw new NetworkUnavailable("offline")
    if (!force && breaker.isSlow()) throw new NetworkUnavailable("slow")
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    const started = now()
    try {
      const res = await fetchImpl(url, { credentials: "same-origin", ...options, signal: controller.signal })
      let body = null
      if (read) {
        const text = await res.text() // an abort mid-body rejects here, like a hung request
        if (read === "text") body = text
        else try { body = JSON.parse(text) } catch { body = null }
      }
      if (now() - started < timeoutMs) breaker.reset()
      return { res, body }
    } catch (e) {
      breaker.trip()
      throw new NetworkUnavailable(controller.signal.aborted ? "timeout" : "error")
    } finally {
      clearTimeout(timer)
    }
  }
}
