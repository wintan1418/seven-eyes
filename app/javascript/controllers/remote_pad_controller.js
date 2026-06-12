import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// The phone side of the remote clicker (/remote/CODE). Sends next/prev/chase
// commands over the pairing stream; the operator console answers a presence
// ping so the pad can show whether anyone is listening.
export default class extends Controller {
  static targets = ["status", "dot", "input"]
  static values = { code: String }

  connect() {
    this._connected = false
    this._consumer = createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "RemoteChannel", code: this.codeValue },
      {
        connected: () => this._ping(),
        received: (data) => { if (data.type === "here") this._setConnected(true) }
      }
    )
    // Re-check presence now and then — the console may open after the phone.
    this._pingTimer = setInterval(() => { if (!this._connected) this._ping() }, 4000)
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

  chase(event) {
    event?.preventDefault?.()
    const value = this.inputTarget.value.trim()
    if (!value) return
    this._command("chase", value)
    this.inputTarget.value = ""
    this.inputTarget.blur()
  }

  _command(action, value = "") {
    this._sub?.perform("relay", { type: "command", action, value })
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
}
