import { Controller } from "@hotwired/stimulus"

// Reads the pane's currently displayed verses aloud using the browser's built-in
// speech synthesis (no network, no API). Toggling re-fires; a second click stops.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.speaking = false
    this._onEnd = () => this.reset()
  }

  disconnect() {
    this.stop()
  }

  toggle() {
    if (!("speechSynthesis" in window)) return
    this.speaking ? this.stop() : this.play()
  }

  play() {
    const text = this.collectText()
    if (!text) return

    window.speechSynthesis.cancel() // stop any other pane mid-read
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = 0.92
    utterance.pitch = 1
    utterance.onend = this._onEnd
    utterance.onerror = this._onEnd
    window.speechSynthesis.speak(utterance)

    this.speaking = true
    this.mark(true)
  }

  stop() {
    if ("speechSynthesis" in window) window.speechSynthesis.cancel()
    this.reset()
  }

  reset() {
    this.speaking = false
    this.mark(false)
  }

  mark(on) {
    if (this.hasButtonTarget) {
      this.buttonTarget.classList.toggle("is-on", on)
      this.buttonTarget.innerHTML = on ? "&#9632;" : "&#9658;" // ■ / ▶
    }
  }

  collectText() {
    return Array.from(this.element.querySelectorAll(".ps-verse-text"))
      .map((el) => el.textContent.trim())
      .filter(Boolean)
      .join(" ")
  }
}
