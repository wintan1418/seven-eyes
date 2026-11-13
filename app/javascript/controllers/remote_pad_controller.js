import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const PING_MS = 4000
// No "here" from the console within ~2 ping intervals → show it as unreachable
// (the laptop slept, the console tab closed, or Wi-Fi dropped).
const PRESENCE_TIMEOUT_MS = PING_MS * 2 + 1000

// The phone side of the remote clicker (/remote/CODE?t=TOKEN). Sends
// next/prev/chase commands over the pairing stream; the operator console
// answers a presence ping so the pad can show whether anyone is listening.
export default class extends Controller {
  static targets = ["status", "dot", "input", "screen"]
  static values = { code: String, token: String }

  connect() {
    this._connected = false
    this._lastHere = 0
    this._consumer = createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "RemoteChannel", code: this.codeValue, token: this.tokenValue },
      {
        connected: () => this._ping(),
        disconnected: () => this._setConnected(false),
        rejected: () => this._setExpired(),
        received: (data) => {
          if (data.type !== "here") return
          this._lastHere = Date.now()
          this._setConnected(true)
          this._showScreen(data.value)
        }
      }
    )
    // Keep pinging even once connected — presence is only as good as the
    // last answer, so a console that disappears flips the pad back.
    this._pingTimer = setInterval(() => {
      if (this._connected && Date.now() - this._lastHere > PRESENCE_TIMEOUT_MS) this._setConnected(false)
      this._ping()
    }, PING_MS)
  }

  disconnect() {
    clearInterval(this._pingTimer)
    this._sub?.unsubscribe()
    this._consumer?.disconnect()
  }

  next(event) {
    event?.preventDefault?.()
    this._command("next")
  }

  prev(event) {
    event?.preventDefault?.()
    this._command("prev")
  }

  back(event) {
    event?.preventDefault?.()
    this._command("back")
  }

  // Black / Clear / Logo — the same live controls as the console's bar.
  screen(event) {
    event?.preventDefault?.()
    const command = event.currentTarget.dataset.screenCommand
    if ([ "blank", "clear", "logo" ].includes(command)) this._command(command)
  }

  // Light the button for what the big screen shows now.
  _showScreen(mode) {
    const lit = mode === "black" ? "blank" : mode
    this.screenTargets.forEach((b) => {
      const on = b.dataset.screenCommand === lit
      b.classList.toggle("is-on", on)
      b.setAttribute("aria-pressed", String(on))
    })
  }

  chase(event) {
    event?.preventDefault?.()
    const value = this.inputTarget.value.trim()
    if (!value) return
    this._command("chase", value)
    this.inputTarget.value = ""
    this.inputTarget.blur()
  }

  // `command`, not `action`: Action Cable's perform() overwrites data.action
  // with the channel method name ("relay").
  _command(command, value = "") {
    this._sub?.perform("relay", { type: "command", command, value })
    if (navigator.vibrate) navigator.vibrate(12)
  }

  _ping() {
    this._sub?.perform("relay", { type: "ping" })
  }

  _setConnected(on) {
    this._connected = on
    if (this.hasDotTarget) this.dotTarget.classList.toggle("is-on", on)
    if (this.hasStatusTarget) this.statusTarget.textContent = on ? "Connected to the console" : "Reaching the console…"
  }

  _setExpired() {
    clearInterval(this._pingTimer)
    this._connected = false
    if (this.hasDotTarget) this.dotTarget.classList.remove("is-on")
    if (this.hasStatusTarget) this.statusTarget.textContent = "Pairing expired — scan the QR again"
    this.element.classList.add("is-unpaired")
  }
}
