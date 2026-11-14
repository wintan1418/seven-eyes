// On a page the service worker drew because there was no connection (the
// offline reader, "needs one visit with internet"), go back to the real page
// as soon as the server answers again — otherwise the Bible tab stayed on the
// offline copy after data came back. The page says where to go in
// <body data-online-href>; the offline reader keeps the chapter you were on.
// Checks when the page comes back into view and every 10 s; inside the apps
// the "online" event often never fires, so it never relies on that alone.
import { markNetworkFine } from "./network"

const EVERY_MS = 10000
const TIMEOUT_MS = 4000

function start() {
  const body = document.body
  if (!body?.hasAttribute("data-offline-shell")) return
  const href = body.dataset.onlineHref || "/read"
  let timer = null
  let leaving = false

  const reachable = async () => {
    const controller = new AbortController()
    const t = setTimeout(() => controller.abort(), TIMEOUT_MS)
    try {
      return (await fetch(`/up?t=${Date.now()}`, { cache: "no-store", signal: controller.signal })).ok
    } catch {
      return false
    } finally {
      clearTimeout(t)
    }
  }

  const check = async () => {
    clearTimeout(timer)
    if (leaving || document.hidden) return schedule()
    if (await reachable()) {
      leaving = true
      markNetworkFine() // the worker stops serving saved copies for a "slow" network
      if (window.Turbo?.visit) window.Turbo.visit(href, { action: "replace" })
      else window.location.replace(href)
      return
    }
    schedule()
  }
  const schedule = () => { timer = setTimeout(check, EVERY_MS) }

  window.addEventListener("online", check)
  window.addEventListener("focus", check)
  window.addEventListener("pageshow", check)
  document.addEventListener("visibilitychange", () => { if (!document.hidden) check() })
  schedule()
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true })
else start()
