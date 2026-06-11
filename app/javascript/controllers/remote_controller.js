import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Operator side of the phone remote. Lives on .ps-root beside the presentation
// controller. "Remote" mints a secret pairing code (+ QR) from the server,
// subscribes to its stream, and turns incoming pad commands into the
// presentation controller's window event:
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
    let res
    try {
      res = await this.api("POST", this.urlValue)
    } catch { return }
    if (!res.ok) return
    const data = await res.json()
    this._code = data.code
    if (this.hasButtonTarget) this.buttonTarget.classList.add("is-on")
    if (this.hasQrTarget) this.qrTarget.innerHTML = data.qr_svg
    if (this.hasCodeTarget) this.codeTarget.textContent = data.code
    if (this.hasUrlTarget) this.urlTarget.textContent = data.url.replace(/^https?:\/\//, "")
    this._subscribe(data.code)
    this._openPanel()
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

  _subscribe(code) {
    this._consumer ||= createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "RemoteChannel", code: code },
      { received: (data) => this._received(data) }
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
