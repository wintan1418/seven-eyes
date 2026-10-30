import { Controller } from "@hotwired/stimulus"
import { VOICE_KEY, chosenVoice } from "./reader_controller"

// Listening voice chooser (Reading settings). The choice is remembered on this
// device; the reader sends it with every chapter request. ▶ plays a short
// sample of that voice ("Phone voice" uses the device's own speech).
const SAMPLE = "The Lord is my shepherd; I shall not want."

export default class extends Controller {
  static targets = ["option", "play"]
  static values = { sampleUrl: String }

  connect() {
    this.mark(chosenVoice())
  }

  disconnect() {
    this.stopPreview()
  }

  choose({ params: { id } }) {
    try { localStorage.setItem(VOICE_KEY, id) } catch { /* private mode: this visit only */ }
    this.mark(id)
  }

  mark(id) {
    const known = this.optionTargets.some(o => o.dataset.voiceId === id)
    const current = known ? id : "auto"
    this.optionTargets.forEach(o => {
      const on = o.dataset.voiceId === current
      o.classList.toggle("is-on", on)
      o.querySelector("[role=radio]")?.setAttribute("aria-checked", on)
    })
  }

  preview({ params: { id }, currentTarget }) {
    const wasPlaying = currentTarget.classList.contains("is-playing")
    this.stopPreview()
    if (wasPlaying) return

    currentTarget.classList.add("is-playing")
    currentTarget.innerHTML = "&#9632;"
    const done = () => this.resetButton(currentTarget)

    if (id === "device") return this.previewDevice(done)

    this.audio = new Audio(`${this.sampleUrlValue}?voice=${encodeURIComponent(id)}`)
    this.audio.onended = done
    this.audio.onerror = done
    this.audio.play().catch(done)
  }

  previewDevice(done) {
    const native = window.BiblioRataNative
    if (native?.speak) {
      native.speak(SAMPLE)
      this.nativeTimer = setTimeout(done, 4000)
      return
    }
    if (!("speechSynthesis" in window)) return done()
    const u = new SpeechSynthesisUtterance(SAMPLE)
    u.rate = 0.92
    u.onend = done
    u.onerror = done
    speechSynthesis.cancel()
    speechSynthesis.speak(u)
  }

  stopPreview() {
    if (this.audio) { this.audio.onended = this.audio.onerror = null; this.audio.pause(); this.audio = null }
    clearTimeout(this.nativeTimer)
    if ("speechSynthesis" in window) speechSynthesis.cancel()
    window.BiblioRataNative?.stopSpeaking?.()
    this.playTargets.forEach(b => this.resetButton(b))
  }

  resetButton(button) {
    button.classList.remove("is-playing")
    button.innerHTML = "&#9658;"
  }
}
