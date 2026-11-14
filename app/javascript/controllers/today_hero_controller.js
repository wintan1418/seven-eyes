import { Controller } from "@hotwired/stimulus"
import { owner } from "../lib/offline/page"
import { todayStatus, lagosHour, daypart, greeting } from "../lib/today_state"

// Home's Today hero. The server draws it right for the moment it rendered;
// this keeps it right on a saved (offline) copy and for guests: today done or
// not and the streak come from the server's days merged with this device's
// (lib/today_state.js), and the hour's tint + greeting follow the Lagos clock
// (unless the page was opened with ?at= for a design review).
export default class extends Controller {
  static targets = [ "open", "done", "streak", "streakCount", "doneStreak", "greeting", "part" ]
  static values = { dates: Array, name: String, fixed: Boolean }

  connect() {
    if (!this.fixedValue) this.tint()
    this.refresh()
    this._onShow = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this._onShow)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this._onShow)
  }

  tint() {
    const hour = lagosHour()
    const part = daypart(hour)
    const root = this.element.closest("[data-daypart]")
    if (root && root.dataset.daypart !== part) root.dataset.daypart = part
    if (this.hasGreetingTarget) {
      this.greetingTarget.textContent = `${greeting(hour)}${this.nameValue ? `, ${this.nameValue}` : ""}.`
    }
    if (this.hasPartTarget) this.partTarget.textContent = { dawn: "Dawn", day: "Midday", evening: "Evening" }[part]
  }

  refresh() {
    const status = todayStatus({ owner: owner(), serverDates: this.datesValue })
    this.element.classList.toggle("is-done", status.done)
    if (this.hasOpenTarget) this.openTarget.hidden = status.done
    if (this.hasDoneTarget) this.doneTarget.hidden = !status.done
    if (this.hasStreakTarget) {
      this.streakTarget.hidden = status.streak === 0
      this.streakTarget.setAttribute("aria-label", `${status.streak}-day streak`)
      const fill = this.streakTarget.querySelector(".hm-ring-fill")
      if (fill) {
        const c = 2 * Math.PI * Number(fill.getAttribute("r"))
        fill.setAttribute("stroke-dasharray", `${(c * Math.min(status.streak, 7) / 7).toFixed(2)} ${c.toFixed(2)}`)
      }
    }
    if (this.hasStreakCountTarget) this.streakCountTarget.textContent = status.streak
    if (this.hasDoneStreakTarget) this.doneStreakTarget.textContent = status.streak > 0 ? `· ${status.streak}-day streak` : ""
  }
}
