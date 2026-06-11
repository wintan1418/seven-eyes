import { Controller } from "@hotwired/stimulus"

// The "What's New" badge + page pairing.
//   mode "badge" (topbar link): show a glowing dot until this version was seen.
//   mode "seen"  (the page itself): remember that this version has been seen.
const KEY = "ps-whats-new-seen"

export default class extends Controller {
  static values = { mode: String, version: String }

  connect() {
    if (this.modeValue === "seen") {
      try { localStorage.setItem(KEY, this.versionValue) } catch { /* private mode */ }
      return
    }
    // badge mode
    let seen = null
    try { seen = localStorage.getItem(KEY) } catch { /* private mode */ }
    if (seen !== this.versionValue) this.element.classList.add("is-unseen")
  }
}
