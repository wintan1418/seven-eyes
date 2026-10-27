import { Controller } from "@hotwired/stimulus"

// Renders a small "● Offline" badge whenever the browser reports it's offline.
// Lives on a wrapper near the top of <body>; the badge target is the actual
// pill that shows/hides.
//
// Also: when someone signs out (any DELETE form to /session), tell the service
// worker to drop every cache, so nothing from their session stays on a shared
// device.
export default class extends Controller {
  static targets = ["badge"]

  connect() {
    this._update = () => this._render(navigator.onLine)
    this._onSubmit = (e) => this._maybeSignOut(e.target)
    window.addEventListener("online", this._update)
    window.addEventListener("offline", this._update)
    document.addEventListener("submit", this._onSubmit, true)
    this._update()
  }

  disconnect() {
    window.removeEventListener("online", this._update)
    window.removeEventListener("offline", this._update)
    document.removeEventListener("submit", this._onSubmit, true)
  }

  _render(online) {
    if (this.hasBadgeTarget) this.badgeTarget.hidden = online
  }

  _maybeSignOut(form) {
    if (!(form instanceof HTMLFormElement)) return
    const method = (form.querySelector("input[name='_method']")?.value || form.method || "").toLowerCase()
    let path = ""
    try { path = new URL(form.action, window.location.href).pathname } catch { return }
    if (method !== "delete" || path !== "/session") return
    clearServiceWorkerCaches()
  }
}

export function clearServiceWorkerCaches() {
  try {
    navigator.serviceWorker?.controller?.postMessage({ type: "clear-caches" })
  } catch { /* no worker — nothing cached */ }
  // Belt and braces: the page can reach the same caches directly.
  try {
    window.caches?.keys().then((keys) =>
      keys.filter((k) => k.startsWith("ps-")).forEach((k) => window.caches.delete(k))
    ).catch(() => {})
  } catch { /* caches unavailable (private mode) */ }
}
