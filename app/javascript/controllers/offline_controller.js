import { Controller } from "@hotwired/stimulus"

// Renders a small "● Offline" badge whenever the browser reports it's offline.
// Lives on a wrapper near the top of <body>; the badge target is the actual
// pill that shows/hides.
export default class extends Controller {
  static targets = ["badge"]

  connect() {
    this._update = () => this._render(navigator.onLine)
    window.addEventListener("online", this._update)
    window.addEventListener("offline", this._update)
    this._update()
  }

  disconnect() {
    window.removeEventListener("online", this._update)
    window.removeEventListener("offline", this._update)
  }

  _render(online) {
    if (this.hasBadgeTarget) this.badgeTarget.hidden = online
  }
}
