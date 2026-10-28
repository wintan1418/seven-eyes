// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./lib/frame_guard"
import "./controllers"
import { isNativeApp } from "./lib/native_app"

// PWA: register the service worker for offline / installable use. Conservative —
// only on HTTPS or localhost, and a `?sw=off` query bails out so we have a
// safety hatch if the SW ever misbehaves in production.
// Not inside the iOS/Android apps: they load pages from the network themselves
// and show their own offline screen.
if ("serviceWorker" in navigator && !isNativeApp) {
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
