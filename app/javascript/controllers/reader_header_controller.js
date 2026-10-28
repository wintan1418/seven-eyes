import { Controller } from "@hotwired/stimulus"

// Keeps the app bar's passage and translation chips in step with the primary
// (first) pane: on connect and whenever a pane frame re-renders.
export default class extends Controller {
  static targets = ["reference", "translation"]

  connect() {
    this._onLoad = () => this.refresh()
    document.addEventListener("turbo:frame-load", this._onLoad)
    this.refresh()
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this._onLoad)
  }

  refresh() {
    const pane = this.element.querySelector(".ps-workspace .ps-pane .rd-pane-meta")
    if (!pane) return
    if (this.hasReferenceTarget && pane.dataset.referenceLabel) {
      this.referenceTarget.textContent = pane.dataset.referenceLabel
    }
    if (this.hasTranslationTarget && pane.dataset.translationCode) {
      this.translationTarget.textContent = pane.dataset.translationCode
      this.translationTarget.closest("button")?.setAttribute("title", pane.dataset.translationName || "")
    }
  }
}
