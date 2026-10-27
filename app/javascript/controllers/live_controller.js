import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const PUSH_DEBOUNCE_MS = 120
const RETRY_MS = 3000

// Operator side of "Go Live" (congregation follow-along). Lives on .ps-root
// beside the presentation controller and listens for its window event:
//   preach:state — the pulpit's current passage/verse → PATCH to the server,
//                  which rebroadcasts to every follower over Action Cable.
// Leaving preach mode does NOT end the session (an accidental Esc must never
// tell the pews "the service has ended") — only the explicit "End live" button
// does; followers simply keep the last verse meanwhile.
//
// Pushes are serialised (one request in flight, the newest state sent next)
// and stamped with a rising sequence number the server uses to drop any push
// that lands out of order. Also subscribes to the session's operator stream
// (signed token) purely to show the "N following" count on the console.
//
// If the page is re-rendered while a session is active (Turbo navigation away
// and back), data-live-active-code-value re-attaches the console to it.
export default class extends Controller {
  static targets = ["panel", "qr", "code", "url", "count", "button", "joinButton", "chip"]
  static values = { url: String, activeCode: String }

  connect() {
    this._live = false
    this._lastState = null
    this._seq = 0
    this._onState = (e) => this.statePush(e.detail)
    this._onJoinCleared = () => { this._onScreen = false; this._syncJoinButton() }
    window.addEventListener("preach:state", this._onState)
    window.addEventListener("preach:join-cleared", this._onJoinCleared)
    if (this.activeCodeValue) this._resume()
  }

  disconnect() {
    window.removeEventListener("preach:state", this._onState)
    window.removeEventListener("preach:join-cleared", this._onJoinCleared)
    clearTimeout(this._pushTimer)
    clearTimeout(this._retryTimer)
    this._sub?.unsubscribe()
    this._consumer?.disconnect()
  }

  // Go Live (or, when already live, reopen the join panel).
  async toggle(event) {
    event?.preventDefault?.()
    if (this._live) { this._openPanel(); return }
    if (this._pending) return // double-click guard (the server is idempotent too)
    this._pending = true
    if (this.hasButtonTarget) this.buttonTarget.disabled = true
    try {
      const res = await this.api("POST", this.urlValue, this._params(this._lastState))
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      this._attach(await res.json())
      this._setError(null)
      this._openPanel()
    } catch {
      this._setError("Couldn't go live — check the connection and press Go Live again")
    } finally {
      this._pending = false
      if (this.hasButtonTarget) this.buttonTarget.disabled = false
    }
  }

  statePush(detail) {
    this._lastState = detail
    if (!this._live) return
    // Debounce: rapid Next-Next collapses into the final verse.
    clearTimeout(this._pushTimer)
    this._pushTimer = setTimeout(() => this._flush(), PUSH_DEBOUNCE_MS)
  }

  async endLive(event) {
    event?.preventDefault?.()
    if (!this._live) return
    this._detach()
    try {
      const res = await this.api("DELETE", this.urlValue)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
    } catch {
      this._notice("Couldn't reach the server to end the live session — it will close on its own after a few hours")
    }
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
    this._setOnScreen(!this._onScreen)
  }

  closePanel(event) {
    event?.preventDefault?.()
    if (this.hasPanelTarget) this.panelTarget.hidden = true
  }

  // ----- internals -----

  async _resume() {
    try {
      const res = await this.api("POST", this.urlValue, { resume: 1 })
      if (!res.ok) return // ended/expired meanwhile — stay off
      this._attach(await res.json())
    } catch { /* offline: the operator can press Go Live again */ }
  }

  _attach(data) {
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
    this._syncJoinButton()
    this._subscribe(data.code, data.operator_token)
  }

  _detach() {
    this._live = false
    clearTimeout(this._pushTimer)
    clearTimeout(this._retryTimer)
    this._dirty = false
    this.element.classList.remove("is-live-session")
    if (this.hasButtonTarget) this.buttonTarget.classList.remove("is-on")
    if (this._onScreen) this._setOnScreen(false) // pull the join card off the projector
    this._syncJoinButton()
    this._setError(null)
    this._setCount(0)
    this.closePanel()
    this._sub?.unsubscribe()
    this._sub = null
  }

  // One PATCH in flight at a time; whatever arrived meanwhile goes next.
  async _flush() {
    if (!this._live) return
    if (this._inFlight) { this._dirty = true; return }
    this._inFlight = true
    this._dirty = false
    clearTimeout(this._retryTimer)
    let failed = false
    try {
      const res = await this.api("PATCH", this.urlValue, this._params(this._lastState))
      if (res.status === 404) { // ended elsewhere or expired
        this._detach()
        this._notice("The live session has ended — press Go Live to start a new one")
      } else if (res.ok || res.status === 422) {
        // 422 = a reference the server couldn't read; the pews keep the last
        // good verse, and retrying the same state wouldn't help.
        this._setError(null)
      } else {
        failed = true
      }
    } catch {
      failed = true
    } finally {
      this._inFlight = false
    }
    if (failed && this._live) {
      this._setError("Phones aren't receiving updates — retrying…")
      this._retryTimer = setTimeout(() => this._flush(), RETRY_MS)
    } else if (this._dirty) {
      this._flush()
    }
  }

  _setOnScreen(on) {
    this._onScreen = on
    window.dispatchEvent(new CustomEvent("preach:join", {
      detail: on ? { qr_svg: this._qrSvg, code: this._code, url: this._joinUrl } : null
    }))
    this._syncJoinButton()
  }

  _syncJoinButton() {
    if (!this.hasJoinButtonTarget) return
    const btn = this.joinButtonTarget
    btn.classList.toggle("is-on", !!this._onScreen)
    btn.innerHTML = this._onScreen ? "&#9744; Hide from screen" : "&#10697; Show on screen"
  }

  // Visible failure state: the Go Live button + "following" chip turn red and
  // the console shows a toast once per failure streak.
  _setError(message) {
    const wasError = !!this._error
    this._error = message
    ;[this.hasButtonTarget && this.buttonTarget, this.hasChipTarget && this.chipTarget]
      .filter(Boolean)
      .forEach(el => {
        el.classList.toggle("is-error", !!message)
        if (message) {
          if (el.dataset.okTitle == null) el.dataset.okTitle = el.title || ""
          el.title = message
        } else if (el.dataset.okTitle != null) {
          el.title = el.dataset.okTitle
          delete el.dataset.okTitle
        }
      })
    if (message && !wasError) this._notice(message)
  }

  _notice(message) {
    window.dispatchEvent(new CustomEvent("preach:notice", { detail: { message, tone: "error" } }))
  }

  _openPanel() {
    if (this.hasPanelTarget) this.panelTarget.hidden = false
  }

  _nextSeq() {
    // Rising across page reloads too (the server keeps the last applied seq).
    this._seq = Math.max(this._seq + 1, Date.now())
    return this._seq
  }

  _params(state) {
    const seq = this._nextSeq()
    if (!state) return { seq }
    if (state.slide) {
      return {
        seq,
        kind: "slide",
        slide_title: state.slide.title,
        slide_body: state.slide.body,
        slide_image_url: state.slide.image,
        slide_index: state.slide.index
      }
    }
    return {
      seq,
      reference: state.reference,
      translation_id: state.translation,
      verse_start: state.verseStart,
      verse_end: state.verseEnd,
      emphasis: state.emphasis || {}
    }
  }

  _subscribe(code, token) {
    this._sub?.unsubscribe()
    this._consumer ||= createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "LiveSessionChannel", code: code, role: "operator", token: token },
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
