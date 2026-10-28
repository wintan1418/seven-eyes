import { Controller } from "@hotwired/stimulus"

// Reading theme on <body data-theme>: vellum (default cream), candlelight
// (warm dark), paper (white) — or auto: vellum by day, candlelight when the
// device is in dark mode (the CSS handles auto with a media query).
// Persisted to localStorage and to the `ps_theme` cookie: the layout renders
// <body data-theme> from the cookie, so the server's HTML already carries the
// reader's theme and Turbo visits never flash the wrong colours.
// Lives on <body>; theme buttons anywhere on the page carry
// data-action="theme#choose" data-theme-choice-param="candlelight".
const KEY = "ps:theme"
const COOKIE = "ps_theme"
const THEMES = ["vellum", "candlelight", "paper", "auto"]
const DEFAULT = "vellum"
const LEGACY = { light: "paper", dark: "candlelight", sepia: "vellum" } // first cut of the redesign
const COLORS = { vellum: "#F4EAD2", candlelight: "#17120C", paper: "#FFFFFF" }

export default class extends Controller {
  connect() {
    const theme = this.read()
    this.apply(theme)
    this.remember(theme)
  }

  choose(event) {
    event?.preventDefault?.()
    const theme = event?.params?.choice
    if (!THEMES.includes(theme)) return
    this.apply(theme)
    this.remember(theme)
  }

  // Quick day ⇄ night flip (keyboard / single button).
  toggle(event) {
    event?.preventDefault?.()
    const next = this.effective() === "candlelight" ? "vellum" : "candlelight"
    this.apply(next)
    this.remember(next)
  }

  apply(theme) {
    this.element.dataset.theme = theme
    document.querySelectorAll("[data-theme-choice-param]").forEach((btn) => {
      btn.setAttribute("aria-pressed", String(btn.dataset.themeChoiceParam === theme))
    })
    const color = COLORS[this.effective()]
    document.querySelectorAll("meta[name='theme-color']").forEach((meta) => {
      if (theme === "auto") return // the server rendered one per colour scheme
      meta.removeAttribute("media")
      meta.content = color
    })
  }

  // The theme actually on screen ("auto" resolved against the device).
  effective() {
    const theme = this.element.dataset.theme
    if (theme !== "auto") return theme
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "candlelight" : "vellum"
  }

  remember(theme) {
    try { localStorage.setItem(KEY, theme) } catch (_) {}
    const secure = location.protocol === "https:" ? "; Secure" : ""
    document.cookie = `${COOKIE}=${theme}; path=/; max-age=31536000; SameSite=Lax${secure}`
  }

  read() {
    let stored = null
    try { stored = localStorage.getItem(KEY) } catch (_) {}
    stored = LEGACY[stored] || stored
    if (THEMES.includes(stored)) return stored
    const rendered = LEGACY[this.element.dataset.theme] || this.element.dataset.theme
    return THEMES.includes(rendered) ? rendered : DEFAULT
  }
}
