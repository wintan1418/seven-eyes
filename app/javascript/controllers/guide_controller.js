import { Controller } from "@hotwired/stimulus"

// Toggles the discovery panel ("What's at your desk") for guests, who don't
// have a user record to store the preference. For authenticated users the
// dismissal is persisted server-side; this controller still keeps the topbar
// button label in sync. Mounted on <body> so it's reachable from the topbar
// button regardless of which view is in the workspace.
const KEY = "bibliorata.guideHidden"

export default class extends Controller {
  static targets = ["label"]

  connect() {
    if (localStorage.getItem(KEY) === "1") {
      this.applyHidden(true)
    }
  }

  toggle() {
    const willHide = !this.panel() || this.panel().style.display !== "none"
    if (willHide && localStorage.getItem(KEY) === "1") {
      // already hidden — clicking should show
      this.applyHidden(false)
      localStorage.removeItem(KEY)
    } else if (willHide) {
      this.applyHidden(true)
      localStorage.setItem(KEY, "1")
    } else {
      this.applyHidden(false)
      localStorage.removeItem(KEY)
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
