import { Controller } from "@hotwired/stimulus"

// Toggles the .is-interlinear class on .ps-root. CSS does the rest:
// each Strong's-tagged .ps-word renders its data-gloss (translit · G####)
// stacked beneath the English surface form.
export default class extends Controller {
  static targets = ["button"]

  toggle(event) {
    event?.preventDefault?.()
    const on = this.element.classList.toggle("is-interlinear")
    if (this.hasButtonTarget) this.buttonTarget.classList.toggle("is-active", on)
  }
}
