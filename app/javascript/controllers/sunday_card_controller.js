import { Controller } from "@hotwired/stimulus"
import { getMeta } from "../lib/offline/db"

// This Sunday (pastor mode on Home): the one readiness check only this device
// can answer — has "Get ready for Sunday" (sunday_ready controller) saved this
// service here, and when. On phones the order of service and the checks fold
// away under a one-line summary; toggle() opens them (laptops always show them).
export default class extends Controller {
  static targets = [ "device", "deviceText", "fold" ]
  static values = { url: String }

  async connect() {
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

  toggle() {
    const open = !this.element.classList.contains("is-open")
    this.element.classList.toggle("is-open", open)
    if (this.hasFoldTarget) this.foldTarget.setAttribute("aria-expanded", String(open))
  }
}
