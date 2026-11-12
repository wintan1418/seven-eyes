import { Controller } from "@hotwired/stimulus"
import { isPageSaved, networkDown } from "../lib/offline/ready"

// Marks studies in a list (home page, ☰ menu) that are saved on this device:
// "Available offline". With no internet, a study that isn't saved says
// "Needs internet to open" and a tap explains instead of opening a dead page.
// Each study link is a `study` target.
export default class extends Controller {
  static targets = ["study"]

  connect() {
    this._render = () => this.render()
    window.addEventListener("offline:prepared", this._render)
    window.addEventListener("online", this._render)
    window.addEventListener("offline", this._render)
    this.render()
  }

  disconnect() {
    window.removeEventListener("offline:prepared", this._render)
    window.removeEventListener("online", this._render)
    window.removeEventListener("offline", this._render)
  }

  async render() {
    const down = networkDown()
    await Promise.all(this.studyTargets.map(async (link) => {
      const saved = await isPageSaved(new URL(link.href, window.location.origin).pathname)
      link.classList.toggle("is-offline-ready", saved)
      link.classList.toggle("is-offline-missing", down && !saved)
      let mark = link.querySelector(".ui-offline-mark")
      if (!saved && !down) { mark?.remove(); return }
      if (!mark) {
        mark = document.createElement("span")
        mark.className = "ui-offline-mark"
        link.appendChild(mark)
      }
      mark.textContent = saved ? "Available offline" : "Needs internet to open"
    }))
  }

  // click->offline-studies#guard on each link.
  guard(event) {
    const link = event.currentTarget
    if (!networkDown() || link.classList.contains("is-offline-ready")) return
    event.preventDefault()
    window.dispatchEvent(new CustomEvent("offline:toast", {
      detail: { message: "This study needs internet to open — it isn't saved on this device. Present offline still works." }
    }))
  }
}
