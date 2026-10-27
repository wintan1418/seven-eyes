import { Controller } from "@hotwired/stimulus"

// The phone tab bar's Notes tab: open / close the notes of the active pane
// (the first pane unless another was last touched).
export default class extends Controller {
  notes(event) {
    event.preventDefault()
    const active = document.querySelector(".ps-workspace .ps-pane.is-active-pane")
    const paneId = active?.id?.replace("pane_", "") || null
    window.dispatchEvent(new CustomEvent("notes:toggle", { detail: { paneId } }))
  }
}
