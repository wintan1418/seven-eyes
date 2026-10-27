import { Controller } from "@hotwired/stimulus"

// Reading theme on <body data-theme>: light, dark, sepia — or auto, which
// follows the device's colour scheme (the CSS handles auto with a media query).
// Persisted to localStorage and to the `ps_theme` cookie: the layout renders
// <body data-theme> from the cookie, so the server's HTML already carries the
// reader's theme and Turbo visits never flash the wrong colours.
// Lives on <body>; theme buttons anywhere on the page carry
// data-action="theme#choose" data-theme-choice-param="dark".
const KEY = "ps:theme"
const COOKIE = "ps_theme"
const THEMES = ["auto", "light", "dark", "sepia"]
const LEGACY = { candlelight: "dark", vellum: "auto" } // the old two-theme UI
const COLORS = { light: "#FFFFFF", dark: "#111113", sepia: "#F7F1E3" }

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

  // Quick light ⇄ dark flip (keyboard / single button).
  toggle(event) {
    event?.preventDefault?.()
    const next = this.effective() === "dark" ? "light" : "dark"
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
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light"
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
    return THEMES.includes(rendered) ? rendered : "auto"
  }
}
