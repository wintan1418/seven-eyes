import { Controller } from "@hotwired/stimulus"

// Toggles the discovery panel ("What's at your desk") for guests, who don't
// have a user record to store the preference. For authenticated users the
// dismissal is persisted server-side; this controller still keeps the topbar
// button label in sync. Mounted on <body> so it's reachable from the topbar
// button regardless of which view is in the workspace.
//
// localStorage can throw (Safari private mode, blocked site data), so every
// access is guarded — the panel just won't remember being hidden.
const KEY = "bibliorata.guideHidden"

function stored() {
  try { return localStorage.getItem(KEY) === "1" } catch { return false }
}

function store(hidden) {
  try {
    if (hidden) localStorage.setItem(KEY, "1")
    else localStorage.removeItem(KEY)
  } catch { /* storage unavailable */ }
}

export default class extends Controller {
  static targets = ["label"]

  connect() {
    if (stored()) this.applyHidden(true)
  }

  toggle() {
    const willHide = !this.panel() || this.panel().style.display !== "none"
    if (willHide && stored()) {
      // already hidden — clicking should show
      this.applyHidden(false)
      store(false)
    } else if (willHide) {
      this.applyHidden(true)
      store(true)
    } else {
      this.applyHidden(false)
      store(false)
    }
  }

  applyHidden(hidden) {
    const panel = this.panel()
    if (panel) panel.style.display = hidden ? "none" : ""
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = hidden ? "Show guide" : "Hide guide"
    }
  }

  panel() {
    return document.querySelector(".ps-guide")
  }
}
