import { Controller } from "@hotwired/stimulus"

// Hides the feature guide panel. For signed-in users the server persists the
// dismissal via a form post; for guests we only have localStorage. On every
// page load this controller checks the local flag and removes the panel
// upfront, so a returning guest doesn't see the guide flash.
const KEY = "bibliorata.guideHidden"

export default class extends Controller {
  connect() {
    if (localStorage.getItem(KEY) === "1") {
      this.element.remove()
    }
  }

  hide() {
    localStorage.setItem(KEY, "1")
    this.element.remove()
  }
}
