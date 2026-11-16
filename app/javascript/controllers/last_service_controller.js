import { Controller } from "@hotwired/stimulus"
import { quickFetch } from "../lib/offline/network"

// Home's "Your church": the scriptures of the live service this phone last
// followed (live_follow remembers its code), for a week after — so the sermon
// carries on into the week. Nothing shows, and nothing is fetched, for people
// who never followed one.
const KEY = "br:last-service"
const WEEK_MS = 8 * 24 * 3600 * 1000

export default class extends Controller {
  static targets = [ "when", "list" ]

  async connect() {
    let last = null
    try { last = JSON.parse(localStorage.getItem(KEY) || "null") } catch (_) {}
    if (!last?.code || Date.now() - (last.at || 0) > WEEK_MS) return
    try {
      const { res, body } = await quickFetch(`/live/${encodeURIComponent(last.code)}/recap.json`,
        { headers: { Accept: "application/json" } }, { timeoutMs: 2500, read: "json" })
      if (!res.ok || !body?.passages?.length) return
      this.whenTarget.textContent = this._when(body.date)
      this.listTarget.replaceChildren(...body.passages.map((p) => {
        const li = document.createElement("li")
        const a = document.createElement("a")
        a.href = p.url
        a.textContent = p.label
        li.append(a)
        return li
      }))
      this.element.hidden = false
    } catch (_) { /* offline: stays hidden */ }
  }

  _when(iso) {
    const d = new Date(`${iso}T12:00:00`)
    const days = Math.round((Date.now() - d.getTime()) / 86400000)
    const day = d.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })
    return days <= 0 ? `Today · ${day}` : `Preached on ${day}`
  }
}
