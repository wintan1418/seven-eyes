// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./lib/frame_guard"
import "./controllers"
import "./lib/native_app"
import "./lib/offline/page"

// PWA: register the service worker for offline reading / installable use.
// Conservative — only on HTTPS or localhost, and a `?sw=off` query bails out
// so we have a safety hatch if the SW ever misbehaves in production.
// The iOS/Android apps register it too (iOS needs App-Bound Domains for
// WKWebView to expose navigator.serviceWorker); their own offline screen only
// shows when the worker has nothing saved for a page.
if ("serviceWorker" in navigator) {
  const params = new URLSearchParams(window.location.search)
  const safe = location.protocol === "https:" || location.hostname === "localhost" || location.hostname === "127.0.0.1"
  if (safe && params.get("sw") !== "off") {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("/service-worker").catch(() => {})
    })
  } else if (params.get("sw") === "off") {
    navigator.serviceWorker.getRegistrations().then((regs) => regs.forEach((r) => r.unregister()))
  }
}
