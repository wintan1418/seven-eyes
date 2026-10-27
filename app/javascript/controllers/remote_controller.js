import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Operator side of the phone remote. Lives on .ps-root beside the presentation
// controller. "Remote" mints a secret pairing code (+ QR + signed console
// token) from the server, subscribes to its stream, and turns incoming pad
// commands into the presentation controller's window event:
//   preach:command {action: "next" | "prev" | "chase", value}
// It also answers the pad's presence pings so the phone shows "Connected".
export default class extends Controller {
  static targets = ["panel", "qr", "code", "url", "button"]
  static values = { url: String }

  disconnect() {
    this._sub?.unsubscribe()
    this._consumer?.disconnect()
  }

  async toggle(event) {
    event?.preventDefault?.()
    if (this._code) { this._openPanel(); return }
    if (this._pending) return // a double-click must not mint two codes
    this._pending = true
    this._setError(null)
    if (this.hasButtonTarget) this.buttonTarget.disabled = true
    try {
      const res = await this.api("POST", this.urlValue)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      this._code = data.code
      if (this.hasButtonTarget) this.buttonTarget.classList.add("is-on")
      if (this.hasQrTarget) this.qrTarget.innerHTML = data.qr_svg
      if (this.hasCodeTarget) this.codeTarget.textContent = data.code
      if (this.hasUrlTarget) this.urlTarget.textContent = data.url.replace(/^https?:\/\//, "").replace(/\?.*$/, "")
      this._subscribe(data.code, data.token)
      this._openPanel()
    } catch {
      this._setError("Couldn't pair a remote — check the connection and try again")
    } finally {
      this._pending = false
      if (this.hasButtonTarget) this.buttonTarget.disabled = false
    }
  }

  unpair(event) {
    event?.preventDefault?.()
    this._code = null
    this._sub?.unsubscribe()
    this._sub = null
    if (this.hasButtonTarget) this.buttonTarget.classList.remove("is-on")
    this.closePanel()
  }

  closePanel(event) {
    event?.preventDefault?.()
    if (this.hasPanelTarget) this.panelTarget.hidden = true
  }

  _openPanel() {
    if (this.hasPanelTarget) this.panelTarget.hidden = false
  }

  // Visible failure: the button turns red (title explains) and the console
  // shows a toast (presentation controller listens for preach:notice).
  _setError(message) {
    if (message) {
      window.dispatchEvent(new CustomEvent("preach:notice", { detail: { message, tone: "error" } }))
    }
    if (!this.hasButtonTarget) return
    const btn = this.buttonTarget
    btn.classList.toggle("is-error", !!message)
    if (message) {
      btn.dataset.okTitle ||= btn.title
      btn.title = message
    } else if (btn.dataset.okTitle) {
      btn.title = btn.dataset.okTitle
    }
  }

  _subscribe(code, token) {
    this._consumer ||= createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "RemoteChannel", code: code, token: token },
      {
        received: (data) => this._received(data),
        rejected: () => this._setError("The remote pairing expired — click Remote to pair again")
      }
    )
  }

  _received(data) {
    if (!data || !data.type) return
    if (data.type === "ping") {
      this._sub?.perform("relay", { type: "here" })
    } else if (data.type === "command") {
      window.dispatchEvent(new CustomEvent("preach:command", {
        detail: { action: data.action, value: data.value }
      }))
    }
  }

  api(method, url) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch(url, { method, headers: { "X-CSRF-Token": token, Accept: "application/json" } })
  }
}
