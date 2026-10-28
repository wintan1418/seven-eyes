import { Controller } from "@hotwired/stimulus"

// The "update available" banner inside the apps. Closing it remembers that
// version on this device, so the next release shows the banner again.
const KEY = "ps-app-update-dismissed"

export default class extends Controller {
  static values = { version: String }

  connect() {
    let dismissed = null
    try { dismissed = localStorage.getItem(KEY) } catch { /* storage unavailable */ }
    this.element.hidden = dismissed === this.versionValue
  }

  dismiss() {
    try { localStorage.setItem(KEY, this.versionValue) } catch { /* storage unavailable */ }
    this.element.hidden = true
  }
}
