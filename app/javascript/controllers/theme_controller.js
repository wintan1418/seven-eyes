import { Controller } from "@hotwired/stimulus"

// Flips the vellum / candlelight theme by setting data-theme on <body>.
// Persists to localStorage and to a `ps_theme` cookie: the layout renders
// <body data-theme> from the cookie, so the server's HTML already carries the
// reader's theme and Turbo visits don't flash vellum before this connects.
// Lives on <body>; the toggle button is rendered inside the workspace topbar
// but the controller works even on pages where the button isn't present.
const KEY = "ps:theme"
const COOKIE = "ps_theme"
const VELLUM = "vellum"
const CANDLE = "candlelight"

export default class extends Controller {
  static targets = ["label", "icon"]

  connect() {
    const theme = this.read()
    this.apply(theme)
    this.remember(theme) // migrate localStorage-only choices to the cookie
  }

  toggle(event) {
    event?.preventDefault?.()
    const next = this.element.dataset.theme === CANDLE ? VELLUM : CANDLE
    this.apply(next)
    this.remember(next)
  }

  apply(theme) {
    this.element.dataset.theme = theme
    const isCandle = theme === CANDLE
    if (this.hasLabelTarget) this.labelTarget.textContent = isCandle ? "Vellum" : "Candle"
    if (this.hasIconTarget) this.iconTarget.innerHTML = isCandle ? "&#9728;" : "&#128367;"
  }

  remember(theme) {
    try { localStorage.setItem(KEY, theme) } catch (_) {}
    const secure = location.protocol === "https:" ? "; Secure" : ""
    document.cookie = `${COOKIE}=${theme}; path=/; max-age=31536000; SameSite=Lax${secure}`
  }

  read() {
    try {
      const v = localStorage.getItem(KEY)
      if (v === VELLUM || v === CANDLE) return v
    } catch (_) {}
    return this.element.dataset.theme || VELLUM
  }
}
