import { Controller } from "@hotwired/stimulus"
import { watchFrameErrors } from "../lib/frame_errors"

// Opens/closes the "Find a Verse" AI slide-over. The query form inside posts to
// the suggest endpoint and renders results into the ai_results Turbo Frame.
// A failed search says so (with the query kept for another try); a 401 opens
// the "create an account" gate.
export default class extends Controller {
  static targets = ["drawer", "input"]

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    if (this.hasDrawerTarget) {
      this._unwatch = watchFrameErrors(this.drawerTarget, (frame, kind) => {
        const div = document.createElement("div")
        div.className = "ps-ai-hint is-error"
        div.setAttribute("role", "alert")
        div.textContent = kind === "auth"
          ? "Sign in to search with AI — create a free account to continue."
          : "The search couldn’t finish just now. Your words are kept — press Search again."
        frame.replaceChildren(div)
      })
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
    this._unwatch?.()
  }

  open() {
    this.drawerTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
    if (this.hasInputTarget) setTimeout(() => this.inputTarget.focus(), 50)
  }

  close() {
    this.drawerTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }
}
