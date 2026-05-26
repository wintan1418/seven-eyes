import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "ps:font-size"
const LABELS = ["S", "M", "L", "XL", "XXL"]

export default class extends Controller {
  static targets = ["slider", "level"]
  static values = { url: String, authenticated: Boolean }

  connect() {
    const level = this.initialLevel()
    this.apply(level)
    if (this.hasSliderTarget) this.sliderTarget.value = String(level)
    if (this.hasLevelTarget) this.levelTarget.textContent = LABELS[level] || "S"
  }

  change(event) {
    const level = this.clamp(parseInt(event.target.value, 10))
    this.apply(level)
    if (this.hasLevelTarget) this.levelTarget.textContent = LABELS[level] || "S"
    try { localStorage.setItem(STORAGE_KEY, String(level)) } catch (_) {}
    if (this.authenticatedValue && this.hasUrlValue) this.persist(level)
  }

  apply(level) {
    this.element.dataset.fontSize = String(level)
  }

  initialLevel() {
    const fromAttr = parseInt(this.element.dataset.fontSize || "", 10)
    if (this.validLevel(fromAttr) && this.authenticatedValue) return fromAttr
    if (typeof localStorage !== "undefined") {
      const stored = parseInt(localStorage.getItem(STORAGE_KEY) || "", 10)
      if (this.validLevel(stored)) return stored
    }
    return this.validLevel(fromAttr) ? fromAttr : 0
  }

  persist(level) {
    const csrf = document.querySelector('meta[name="csrf-token"]')
    fetch(this.urlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrf ? csrf.content : ""
      },
      body: JSON.stringify({ font_size: level })
    }).catch(() => {})
  }

  validLevel(n) {
    return Number.isFinite(n) && n >= 0 && n <= 4
  }

  clamp(n) {
    if (!Number.isFinite(n)) return 0
    return Math.max(0, Math.min(4, n))
  }
}
