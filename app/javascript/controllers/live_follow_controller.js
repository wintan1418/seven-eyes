import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// The congregation's "follow along" page (/live/CODE). Subscribes to the live
// session's cable channel and mirrors the pulpit:
//   - same chapter → emphasise the current verse range and glide to it
//   - new chapter/translation → refetch the passage HTML, then emphasise
//   - the reader scrolled away → stop auto-following and offer "Jump to live"
//   - session ended → farewell overlay with a "keep reading" link
export default class extends Controller {
  static targets = ["body", "reference", "jump", "ended"]
  static values = { code: String, passageUrl: String, ended: Boolean }

  connect() {
    if (this.endedValue) return
    this._autoFollow = true
    this._consumer = createConsumer()
    this._sub = this._consumer.subscriptions.create(
      { channel: "LiveSessionChannel", code: this.codeValue },
      { received: (data) => this._received(data) }
    )
    this._onScroll = () => this._scrolled()
    window.addEventListener("scroll", this._onScroll, { passive: true })
    // Glide to wherever the preacher already is (server-rendered .is-now).
    requestAnimationFrame(() => this._scrollToNow())
  }

  disconnect() {
    window.removeEventListener("scroll", this._onScroll)
    this._sub?.unsubscribe()
    this._consumer?.disconnect()
  }

  jumpToLive(event) {
    event?.preventDefault?.()
    this._autoFollow = true
    if (this.hasJumpTarget) this.jumpTarget.hidden = true
    this._scrollToNow()
  }

  _received(data) {
    if (!data || !data.type) return
    if (data.type === "ended") { this._showEnded(); return }
    if (data.type !== "state") return
    this._setReference(data.reference)
    const current = this.bodyTarget.querySelector(".ps-live-passage")
    const samePassage = current &&
        current.dataset.osis === String(data.osis) &&
        current.dataset.chapter === String(data.chapter) &&
        current.dataset.translation === String(data.translation)
    if (samePassage) this._applyRange(data.verse_start, data.verse_end)
    else this._reload(data)
  }

  async _reload(data) {
    let res
    try {
      res = await fetch(this.passageUrlValue, { headers: { Accept: "text/html" } })
    } catch { return }
    if (!res.ok) return
    this.bodyTarget.innerHTML = await res.text()
    this._applyRange(data.verse_start, data.verse_end)
  }

  _applyRange(start, end) {
    if (!start) return
    const last = end || start
    this.bodyTarget.querySelectorAll(".ps-live-verse").forEach(v => {
      const n = parseInt(v.dataset.num, 10)
      v.classList.toggle("is-now", n >= start && n <= last)
    })
    if (this._autoFollow) this._scrollToNow()
  }

  _scrollToNow() {
    const now = this.bodyTarget.querySelector(".ps-live-verse.is-now")
    if (!now) return
    this._programmatic = true
    now.scrollIntoView({ behavior: "smooth", block: "center" })
    clearTimeout(this._progTimer)
    this._progTimer = setTimeout(() => { this._programmatic = false }, 900)
  }

  // Re-reading an earlier verse shouldn't be fought: once the current verse
  // leaves the viewport we pause auto-follow and show the jump pill instead.
  _scrolled() {
    if (this._programmatic) return
    const now = this.bodyTarget.querySelector(".ps-live-verse.is-now")
    if (!now) return
    const rect = now.getBoundingClientRect()
    const away = rect.bottom < 0 || rect.top > window.innerHeight
    this._autoFollow = !away
    if (this.hasJumpTarget) this.jumpTarget.hidden = !away
  }

  _setReference(label) {
    if (label && this.hasReferenceTarget) this.referenceTarget.textContent = label
  }

  _showEnded() {
    if (this.hasEndedTarget) this.endedTarget.hidden = false
    this._sub?.unsubscribe()
  }
}
