import { Controller } from "@hotwired/stimulus"

// Flips the vellum / candlelight theme by setting data-theme on <body>.
// Persists to localStorage so the choice survives across pages and sessions.
// Lives on <body>; the toggle button is rendered inside the workspace topbar
// but the controller works even on pages where the button isn't present.
const KEY = "ps:theme"
const VELLUM = "vellum"
const CANDLE = "candlelight"

export default class extends Controller {
  static targets = ["label", "icon"]

  connect() {
    this.apply(this.read())
  }

  toggle(event) {
    event?.preventDefault?.()
    const next = this.element.dataset.theme === CANDLE ? VELLUM : CANDLE
    this.apply(next)
    try { localStorage.setItem(KEY, next) } catch (_) {}
  }

  apply(theme) {
    this.element.dataset.theme = theme
    const isCandle = theme === CANDLE
    if (this.hasLabelTarget) this.labelTarget.textContent = isCandle ? "Vellum" : "Candle"
    if (this.hasIconTarget) this.iconTarget.innerHTML = isCandle ? "&#9728;" : "&#128367;"
  }

  read() {
    try {
      const v = localStorage.getItem(KEY)
      if (v === VELLUM || v === CANDLE) return v
    } catch (_) {}
    return this.element.dataset.theme || VELLUM
  }
}
