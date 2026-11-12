import { Controller } from "@hotwired/stimulus"
import { openQuickPresent, readyQuickPresent, networkDown } from "../lib/offline/ready"
import { signedIn } from "../lib/offline/page"

// "Present offline" (home page, More sheet, /more, Offline Bibles): one tap
// into the reader's Quick Present study in preach mode — from the copy saved
// on this device, so it works with no internet at all (lib/offline/ready.js
// keeps it ready). The status target says whether it is ready:
// "Quick Present is ready offline".
export default class extends Controller {
  static targets = ["status"]

  connect() {
    this._render = () => this.render()
    window.addEventListener("offline:prepared", this._render)
    window.addEventListener("online", this._render)
    window.addEventListener("offline", this._render)
    this.render()
  }

  disconnect() {
    window.removeEventListener("offline:prepared", this._render)
    window.removeEventListener("online", this._render)
    window.removeEventListener("offline", this._render)
  }

  async open(event) {
    event?.preventDefault?.()
    if (this._opening) return
    this._opening = true
    this.element.setAttribute("aria-busy", "true")
    try {
      await openQuickPresent()
    } finally {
      this._opening = false
      this.element.removeAttribute("aria-busy")
    }
  }

  async render() {
    const ready = await readyQuickPresent().catch(() => null)
    this.element.dataset.ready = ready ? "true" : "false"
    if (!this.hasStatusTarget) return
    let text
    if (ready) text = "✓ Quick Present is ready offline"
    else if (!signedIn()) text = "Sign in once with internet to present offline"
    else if (networkDown()) text = "Not on this device yet — needs internet once"
    else if (navigator.connection?.saveData) text = "Data Saver is on — download your Bible on Offline Bibles to present offline"
    else text = "Getting Quick Present ready for offline…"
    this.statusTarget.textContent = text
  }
}
