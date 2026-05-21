import { Controller } from "@hotwired/stimulus"

// The "name your study" modal: choose a title + pane arrangement before creating.
export default class extends Controller {
  static targets = ["modal", "name", "count", "seg"]

  open(event) {
    event?.preventDefault()
    this.modalTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey ||= (e) => { if (e.key === "Escape") this.close() })
    setTimeout(() => this.nameTarget?.focus(), 50)
  }

  close() {
    this.modalTarget.classList.remove("is-open")
  }

  choosePanes(event) {
    const btn = event.currentTarget
    this.countTarget.value = btn.dataset.count
    this.segTargets.forEach((s) => s.classList.toggle("is-on", s === btn))
  }
}
