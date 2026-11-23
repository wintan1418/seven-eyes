import { Controller } from "@hotwired/stimulus"
import { bannerState, longDay, serviceToday } from "../lib/service_day"
import { deviceServedOn, dismissedFor, setDismissed, keepForNextService } from "../lib/offline/served"
import { owner } from "../lib/offline/page"
import { flushOutbox } from "../lib/offline/outbox"

// The queue's "last week" banner (studies/_service_reset, top of the queue):
// "This queue was used on Sunday 22 November. Start fresh for Sunday 29
// November?" — shown when the queue was served on an earlier day (the page's
// data, or what this device sent) and the operator hasn't answered for that
// service yet. Decided on the device, so a page saved for offline use is right
// on Sunday morning too.
//
//   Start fresh   → setlist:start-fresh (the setlist controller archives the
//                   queue, empties it and offers Undo)
//   Keep using it → hidden for this service (device meta + POST …/service/keep)
export default class extends Controller {
  static targets = [ "text" ]
  static values = { study: String, servedOn: String, dismissedFor: String }

  connect() {
    this._items = null
    this._onChanged = (e) => { this._items = e.detail?.keys?.length ?? 0; this._paint() }
    window.addEventListener("setlist:changed", this._onChanged)
    window.dispatchEvent(new CustomEvent("setlist:request-items", {
      detail: { reply: (items) => { if (this._items == null) { this._items = items.length; this._paint() } } }
    }))
    this._load()
  }

  disconnect() {
    window.removeEventListener("setlist:changed", this._onChanged)
  }

  async _load() {
    const [ device, dismissed ] = await Promise.all([ deviceServedOn(this.studyValue), dismissedFor(this.studyValue) ])
    this._device = device
    this._dismissed = dismissed || this.dismissedForValue || null
    this._loaded = true
    this._paint()
  }

  _state() {
    return bannerState({
      servedOn: this.servedOnValue || null, deviceServedOn: this._device, dismissedFor: this._dismissed,
      items: this._items || 0, today: serviceToday()
    })
  }

  _paint() {
    if (!this._loaded) return
    const state = this._state()
    this.element.hidden = !state.show
    if (state.show && this.hasTextTarget) {
      this.textTarget.textContent = `This queue was used on ${longDay(state.servedOn)}. Start fresh for ${longDay(state.nextSunday)}?`
    }
  }

  startFresh() {
    const { servedOn } = this._state()
    this._dismissed = servedOn
    setDismissed(this.studyValue, servedOn)
    this._paint()
    window.dispatchEvent(new CustomEvent("setlist:start-fresh", {
      detail: {
        servedOn,
        undone: () => { this._dismissed = null; setDismissed(this.studyValue, null); this._paint() }
      }
    }))
  }

  keep() {
    const { servedOn } = this._state()
    this._dismissed = servedOn
    this._paint()
    keepForNextService(this.studyValue, servedOn, owner()).then(() => {
      if (navigator.onLine !== false) flushOutbox().catch(() => {})
    })
  }
}
