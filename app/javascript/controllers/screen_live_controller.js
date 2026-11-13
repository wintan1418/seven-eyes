import { Controller } from "@hotwired/stimulus"
import { countdownEnd, formatClock, cleanAlert } from "../lib/slide_themes"
import { transitionStyle, crossfade } from "../lib/slide_transition"

// EasyWorship-style live controls for the big screen. Lives on the preach bar
// (.ps-preach-bar) in every window: the operator drives, the projector and
// the stage display follow over the preach BroadcastChannel ({type:"live"}).
//
// One thing is on the screen at a time:
//   live       the words (scripture / song / thought)
//   clear  C   words hidden, the look's background stays — until the next
//              slide goes up (any new verse or stanza brings the words back)
//   logo   O   the church logo / name on the look's background (stays up)
//   countdown  T  "Service starts in 04:59" on the look; shows the logo at 00:00
//   black  .   presentation#toggleBlank — the screen fully black (stays up)
// Alerts (A) are separate: a lower-third banner over whatever is live, even
// black, until dismissed or after N seconds. The stage display shows the
// alert and the countdown too. The operator's screen keeps its words and
// shows a state badge ([data-screen-state]) so the volunteer always knows
// what the room sees; the phone remote gets the same state (remote controller).
const TICK_MS = 250

export default class extends Controller {
  static targets = [ "clearButton", "logoButton", "timerButton", "alertButton", "timerPanel", "alertPanel",
    "minutes", "until", "heading", "alertText", "alertSeconds" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root) return
    this.isOutput = this.root.classList.contains("is-output")
    this.mode = "live"
    this.blank = false
    this.countdown = null // {endsAt, heading}
    this.alert = null // {text, until} — until 0 = until dismissed
    if ("BroadcastChannel" in window) {
      this.channel = new BroadcastChannel(`ps-preach:${window.location.pathname}`)
      this.channel.onmessage = (e) => this._onMessage(e.data)
    }
    if (this.isOutput) return
    this._listeners = {
      "preach:state": (e) => this._onState(e.detail),
      "preach:command": (e) => this._onCommand(e.detail),
      "preach:enter": () => this._reset()
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    this._onKey = (e) => this._key(e)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
    if (this._onKey) document.removeEventListener("keydown", this._onKey)
    clearInterval(this._ticker)
    clearTimeout(this._alertTimer)
    this.channel?.close()
    this.channel = null
  }

  // ---- operator: the buttons ------------------------------------------------

  clear(event) {
    event?.preventDefault?.()
    this._setMode(this.mode === "clear" ? "live" : "clear")
  }

  logo(event) {
    event?.preventDefault?.()
    this._setMode(this.mode === "logo" ? "live" : "logo")
  }

  toggleTimer(event) {
    event?.preventDefault?.()
    if (this.mode === "countdown") { this.stopCountdown(); return }
    this._openPanel("timer")
  }

  toggleAlert(event) {
    event?.preventDefault?.()
    this._openPanel(this.hasAlertPanelTarget && !this.alertPanelTarget.hidden ? null : "alert")
  }

  closePanels(event) {
    event?.preventDefault?.()
    this._openPanel(null)
  }

  startCountdown(event) {
    event?.preventDefault?.()
    const until = this.hasUntilTarget ? this.untilTarget.value : ""
    const minutes = this.hasMinutesTarget ? this.minutesTarget.value : ""
    const endsAt = countdownEnd({ minutes, until })
    if (!endsAt) { this.minutesTarget?.focus(); return }
    const heading = (this.hasHeadingTarget ? this.headingTarget.value : "").trim().slice(0, 60) || "Service starts in"
    this.countdown = { endsAt, heading }
    this._openPanel(null)
    this._setMode("countdown")
  }

  stopCountdown(event) {
    event?.preventDefault?.()
    this.countdown = null
    this._setMode("live")
  }

  showAlert(event) {
    event?.preventDefault?.()
    const text = cleanAlert(this.hasAlertTextTarget ? this.alertTextTarget.value : "")
    if (!text) { this.alertTextTarget?.focus(); return }
    const secs = parseInt(this.hasAlertSecondsTarget ? this.alertSecondsTarget.value : "0", 10) || 0
    this.alert = { text, until: secs > 0 ? Date.now() + secs * 1000 : 0 }
    clearTimeout(this._alertTimer)
    if (secs > 0) this._alertTimer = setTimeout(() => this.dismissAlert(), secs * 1000)
    this._openPanel(null)
    this._changed()
  }

  dismissAlert(event) {
    event?.preventDefault?.()
    clearTimeout(this._alertTimer)
    this.alert = null
    this._changed()
  }

  // Enter in the panels' fields submits; Esc closes the panel and stays in
  // preach mode (the field owns the keystroke).
  panelKey(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this._openPanel(null)
    } else if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (event.currentTarget.closest("[data-screen-live-target='alertPanel']")) this.showAlert()
      else this.startCountdown()
    }
  }

  // ---- operator: state --------------------------------------------------------

  _setMode(mode) {
    if (mode !== "countdown") this.countdown = null
    // Clear / Logo / Countdown take the screen out of black.
    if (mode !== "live" && this.blank) window.dispatchEvent(new CustomEvent("preach:command", { detail: { action: "blank" } }))
    this.mode = mode
    this._clearedAt = mode === "clear" ? this._sig : null
    this._changed()
  }

  _reset() {
    this.mode = "live"
    this.countdown = null
    this.alert = null
    clearTimeout(this._alertTimer)
    this._openPanel(null)
    this._changed()
  }

  // presentation_controller's picture of the screen: black, and what's up.
  _onState(state) {
    if (!state) return
    const sig = JSON.stringify([ state.reference, state.translation, state.verseStart, state.verseEnd,
      state.slide ? [ state.slide.title, state.slide.index, state.slide.image ] : null ])
    const blank = !!state.blank
    let changed = blank !== this.blank
    this.blank = blank
    this._sig = sig
    if (blank && this.mode !== "live") { this.mode = "live"; this.countdown = null; changed = true }
    // Clear lasts until the next slide goes up.
    if (this.mode === "clear" && this._clearedAt != null && sig !== this._clearedAt) { this.mode = "live"; changed = true }
    if (changed) this._changed()
  }

  _onCommand(detail) {
    if (!this._preaching()) return
    if (detail?.action === "clear") this.clear()
    else if (detail?.action === "logo") this.logo()
  }

  _key(e) {
    if (!this._preaching() || e.defaultPrevented) return
    if (e.metaKey || e.ctrlKey || e.altKey) return
    const t = e.target
    if (t?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t?.tagName || "")) return
    if (this.root.querySelector(".ps-preach-jump:not([hidden])")) return
    const k = e.key.toLowerCase()
    if (k === "c") { e.preventDefault(); this.clear() }
    else if (k === "o") { e.preventDefault(); this.logo() }
    else if (k === "t") { e.preventDefault(); this.toggleTimer() }
    else if (k === "a") { e.preventDefault(); this.toggleAlert() }
  }

  _changed() {
    this._render()
    this._send(this._message())
    const shown = this.blank ? "black" : this.mode
    this.root.dataset.screenMode = shown
    window.dispatchEvent(new CustomEvent("screen:mode", { detail: { mode: shown, alert: !!this.alert } }))
  }

  _message() {
    return { type: "live", mode: this.mode, countdown: this.countdown, alert: this.alert }
  }

  _openPanel(which) {
    if (this.hasTimerPanelTarget) this.timerPanelTarget.hidden = which !== "timer"
    if (this.hasAlertPanelTarget) this.alertPanelTarget.hidden = which !== "alert"
    const field = which === "timer" ? (this.hasMinutesTarget && this.minutesTarget) : which === "alert" ? (this.hasAlertTextTarget && this.alertTextTarget) : null
    // Into the first field — unless the operator is already typing in the panel.
    if (field) requestAnimationFrame(() => {
      if (field.closest("[hidden]") || field.closest(".ps-live-panel-pop")?.contains(document.activeElement)) return
      field.focus()
      field.select?.()
    })
  }

  _preaching() {
    return this.root.classList.contains("is-preaching")
  }

  // ---- every window: draw it -------------------------------------------------

  _render() {
    const c = this.root.classList
    c.toggle("screen-clear", this.mode === "clear")
    c.toggle("screen-logo", this.mode === "logo")
    c.toggle("screen-countdown", this.mode === "countdown")
    c.toggle("has-alert", !!this.alert)
    this._paintAlert()
    this._paintCountdown()
    this._tick()
    clearInterval(this._ticker)
    if (this.countdown || this.alert?.until) this._ticker = setInterval(() => this._tick(), TICK_MS)
    if (!this.isOutput) this._paintOperator()
  }

  _tick() {
    const now = Date.now()
    if (this.countdown) {
      const left = this.countdown.endsAt - now
      const digits = this.root.querySelector("[data-screen-countdown] .cd-digits")
      if (digits) digits.textContent = formatClock(left)
      if (this.hasTimerButtonTarget) this.timerButtonTarget.querySelector(".lbl").textContent = formatClock(left)
      if (left <= 0) {
        if (this.isOutput) this.root.classList.add("screen-logo") // don't wait for the console
        else { this.countdown = null; this._setMode("logo"); return }
      }
      this._paintBadge()
    }
    if (this.alert?.until && now >= this.alert.until) {
      if (this.isOutput) this.root.classList.remove("has-alert")
      else if (!this._alertTimer) this.dismissAlert()
    }
  }

  _paintAlert() {
    const box = this.root.querySelector("[data-screen-alert]")
    if (!box) return
    box.hidden = !this.alert
    const text = box.querySelector(".al-text")
    if (text) text.textContent = this.alert?.text || ""
  }

  _paintCountdown() {
    const box = this.root.querySelector("[data-screen-countdown]")
    if (!box) return
    const head = box.querySelector(".cd-head")
    if (head) head.textContent = this.countdown?.heading || ""
  }

  _paintOperator() {
    const set = (target, on) => { if (target) { target.classList.toggle("is-on", on); target.setAttribute("aria-pressed", String(on)) } }
    set(this.hasClearButtonTarget && this.clearButtonTarget, this.mode === "clear")
    set(this.hasLogoButtonTarget && this.logoButtonTarget, this.mode === "logo")
    set(this.hasTimerButtonTarget && this.timerButtonTarget, this.mode === "countdown")
    set(this.hasAlertButtonTarget && this.alertButtonTarget, !!this.alert)
    if (this.hasTimerButtonTarget && !this.countdown) this.timerButtonTarget.querySelector(".lbl").textContent = "Timer"
    this._paintBadge()
  }

  // What the congregation sees right now, in words, on the operator's screen.
  _paintBadge() {
    if (this.isOutput) return
    const badge = this.root.querySelector("[data-screen-state]")
    if (!badge) return
    let state = null
    let text = ""
    if (this.blank) { state = "black"; text = "Black — the screen is dark" }
    else if (this.mode === "clear") { state = "clear"; text = "Cleared — words hidden, background showing" }
    else if (this.mode === "logo") { state = "logo"; text = "Logo on screen" }
    else if (this.mode === "countdown" && this.countdown) {
      state = "countdown"
      text = `Countdown ${formatClock(this.countdown.endsAt - Date.now())} on screen`
    }
    badge.dataset.state = state || "live"
    badge.replaceChildren()
    if (state) {
      const pill = document.createElement("span")
      pill.className = "st-mode"
      pill.textContent = text
      badge.append(pill)
    }
    if (this.alert) {
      const al = document.createElement("span")
      al.className = "st-alert"
      al.textContent = `Alert: ${this.alert.text}`
      const x = document.createElement("button")
      x.type = "button"
      x.className = "st-dismiss"
      x.textContent = "Dismiss"
      x.dataset.action = "screen-live#dismissAlert"
      badge.append(al, x)
    }
    badge.hidden = !state && !this.alert
  }

  // ---- sync between windows -----------------------------------------------------

  _onMessage(msg) {
    if (!msg?.type) return
    if (this.isOutput) {
      if (msg.type === "live") {
        const before = this.mode
        this.mode = [ "live", "clear", "logo", "countdown" ].includes(msg.mode) ? msg.mode : "live"
        this.countdown = msg.countdown && Number.isFinite(msg.countdown.endsAt) ? msg.countdown : null
        this.alert = msg.alert?.text ? { text: cleanAlert(msg.alert.text), until: Number(msg.alert.until) || 0 } : null
        // Words ↔ clear ↔ logo ↔ countdown dissolve like any other slide change.
        if (before !== this.mode && transitionStyle(this.root) === "xfade") crossfade(() => this._render())
        else this._render()
      }
    } else if (msg.type === "hello") {
      this._send(this._message())
    }
  }

  _send(msg) {
    if (this.isOutput) return
    try { this.channel?.postMessage(msg) } catch { /* closed */ }
  }
}
