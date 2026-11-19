import { Controller } from "@hotwired/stimulus"

// Compare's Listen pill: opens the Listen sheet (sheets#open) and shows when a
// passage is being read (the reader's window `listen:state`).
export default class extends Controller {
  static targets = [ "label" ]

  connect() {
    this.playing = null
    this._onState = ({ detail }) => {
      if (detail?.state === "idle") { if (this.playing === detail.pane) this.playing = null }
      else if (detail?.pane) this.playing = detail.pane
      this.element.classList.toggle("is-on", !!this.playing)
      this.element.setAttribute("aria-pressed", String(!!this.playing))
      if (this.hasLabelTarget) this.labelTarget.textContent = this.playing ? "Listening" : "Listen"
    }
    window.addEventListener("listen:state", this._onState)
  }

  disconnect() { window.removeEventListener("listen:state", this._onState) }
}
