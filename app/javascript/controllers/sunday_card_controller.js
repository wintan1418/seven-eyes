import { Controller } from "@hotwired/stimulus"
import { getMeta } from "../lib/offline/db"

// This Sunday (pastor mode on Home): the one readiness check only this device
// can answer — has "Get ready for Sunday" (sunday_ready controller) saved this
// service here, and when. On phones the order of service and the checks fold
// away under a one-line summary; toggle() opens them (laptops always show them).
//
// After last Sunday's service (studies/home/_sunday_plan) the card plans the
// next one: templates() folds the template list open, and offline it says
// that making a new service needs a connection.
export default class extends Controller {
  static targets = [ "device", "deviceText", "fold", "templates", "templatesToggle", "offline" ]
  static values = { url: String }

  async connect() {
    this._network = () => this._paintNetwork()
    window.addEventListener("online", this._network)
    window.addEventListener("offline", this._network)
    this._paintNetwork()
    if (!this.hasDeviceTarget) return
    let at = null
    try { at = await getMeta(`sundayReady:${this.urlValue}`) } catch { /* no IndexedDB */ }
    if (!this.element.isConnected) return
    this.deviceTarget.hidden = false
    this.deviceTarget.classList.toggle("is-ok", !!at)
    this.deviceTarget.classList.toggle("is-todo", !at)
    this.deviceTextTarget.textContent = at
      ? `Saved for offline on this device · ${new Date(at).toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit" })}`
      : "Not saved for offline on this device yet"
  }

  disconnect() {
    window.removeEventListener("online", this._network)
    window.removeEventListener("offline", this._network)
  }

  toggle() {
    const open = !this.element.classList.contains("is-open")
    this.element.classList.toggle("is-open", open)
    if (this.hasFoldTarget) this.foldTarget.setAttribute("aria-expanded", String(open))
  }

  templates() {
    if (!this.hasTemplatesTarget) return
    const open = this.templatesTarget.hidden
    this.templatesTarget.hidden = !open
    if (this.hasTemplatesToggleTarget) this.templatesToggleTarget.setAttribute("aria-expanded", String(open))
  }

  _paintNetwork() {
    const offline = navigator.onLine === false
    this.element.classList.toggle("is-offline", offline)
    if (this.hasOfflineTarget) this.offlineTarget.hidden = !offline
  }
}
