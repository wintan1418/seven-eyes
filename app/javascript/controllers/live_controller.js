import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Operator side of "Go Live" (congregation follow-along). Lives on .ps-root
// beside the presentation controller and listens for its window events:
//   preach:state — the pulpit's current passage/verse → PATCH to the server,
//                  which rebroadcasts to every follower over Action Cable.
//   preach:exit  — preach mode closed → end the live session.
// Also subscribes to the session's cable channel (role: operator) purely to
// show the "N following" count on the console.
export default class extends Controller {
  static targets = ["panel", "qr", "code", "url", "count", "button"]
  static values = { url: String }

  connect() {
    this._live = false
    this._lastState = null
    this._onState = (e) => this.statePush(e.detail)
    this._onExit = () => this.endLive()
    window.addEventListener("preach:state", this._onState)
    window.addEventListener("preach:exit", this._onExit)
  }

  disconnect() {
    window.removeEventListener("preach:state", this._onState)
    window.removeEventListener("preach:exit", this._onExit)
    this._sub?.unsubscribe()
    this._consumer?.disconnect()
  }

  // Go Live (or, when already live, reopen the join panel).
  async toggle(event) {
    event?.preventDefault?.()
    if (this._live) { this._openPanel(); return }
    let res
    try {
      res = await this.api("POST", this.urlValue, this._params(this._lastState))
    } catch { return }
    if (!res.ok) return
    const data = await res.json()
    this._live = true
    this._joinUrl = data.url
    this._qrSvg = data.qr_svg
    this._code = data.code
    this._onScreen = false
    this.element.classList.add("is-live-session")
    if (this.hasButtonTarget) this.buttonTarget.classList.add("is-on")
    if (this.hasQrTarget) this.qrTarget.innerHTML = data.qr_svg
    if (this.hasCodeTarget) this.codeTarget.textContent = data.code
    if (this.hasUrlTarget) this.urlTarget.textContent = data.url.replace(/^https?:\/\//, "")
    this._subscribe(data.code)
    this._openPanel()
  }

  statePush(detail) {
    this._lastState = detail
    if (!this._live) return
    // Debounce: rapid Next-Next collapses into the final verse.
    clearTimeout(this._pushTimer)
    this._pushTimer = setTimeout(() => {
      this.api("PATCH", this.urlValue, this._params(detail)).catch(() => {})
    }, 120)
  }

  async endLive(event) {
    event?.preventDefault?.()
    if (!this._live) return
    this._live = false
    clearTimeout(this._pushTimer)
    this.element.classList.remove("is-live-session")
    if (this.hasButtonTarget) this.buttonTarget.classList.remove("is-on")
    if (this._onScreen) { // pull the join card off the projector
      this._onScreen = false
      window.dispatchEvent(new CustomEvent("preach:join", { detail: null }))
    }
    this.closePanel()
    this._sub?.unsubscribe()
    this._sub = null
    try { await this.api("DELETE", this.urlValue) } catch { /* already gone */ }
  }

  copyLink(event) {
    event?.preventDefault?.()
    if (this._joinUrl) navigator.clipboard?.writeText(this._joinUrl)
  }

  // Put the join QR + code up on the projector so the whole room can scan from
  // their seats — no one has to crowd the laptop. Toggles on/off; the
  // presentation controller relays it to the output window.
  projectJoin(event) {
    event?.preventDefault?.()
    if (!this._live) return
    this._onScreen = !this._onScreen
    window.dispatchEvent(new CustomEvent("preach:join", {
      detail: this._onScreen
        ? { qr_svg: this._qrSvg, code: this._code, url: this._joinUrl }
        : null
    }))
    const btn = event.currentTarget
    if (btn) {
      btn.classList.toggle("is-on", this._onScreen)
      btn.innerHTML = this._onScreen ? "&#9744; Hide from screen" : "&#10697; Show on screen"
    }
  }

  closePanel(event) {
    event?.preventDefault?.()
    if (this.hasPanelTarget) this.panelTarget.hidden = true
  }

  _openPanel() {
    if (this.hasPanelTarget) this.panelTarget.hidden = false
  }

  _params(state) {
    if (!state) return {}
    if (state.slide) {
      return {
        kind: "slide",
        slide_title: state.slide.title,
        slide_body: state.slide.body,
        slide_image_url: state.slide.image,
        slide_index: state.slide.index
      }
    }
    return {
      reference: state.reference,
      translation_id: state.translation,
      verse_start: state.verseStart,
      verse_end: state.verseEnd,
      emphasis: state.emphasis || {}
    }
  }

  _subscribe(code) {
    this._consumer ||= createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "LiveSessionChannel", code: code, role: "operator" },
      { received: (data) => { if (data.type === "count") this._setCount(data.followers) } }
    )
  }

  _setCount(n) {
    this.countTargets.forEach(t => { t.textContent = n })
  }

  api(method, url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const opts = { method, headers: { "X-CSRF-Token": token, Accept: "application/json" } }
    if (body !== undefined) {
      opts.headers["Content-Type"] = "application/json"
      opts.body = JSON.stringify(body)
    }
    return fetch(url, opts)
  }
}
