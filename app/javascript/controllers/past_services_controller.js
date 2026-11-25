import { Controller } from "@hotwired/stimulus"
import { pendingOps, subscribe } from "../lib/offline/outbox"
import { owner } from "../lib/offline/page"
import { serviceToday } from "../lib/service_day"

// Past services (/services): a service projected with no signal is only on the
// device until its "served" ping syncs (lib/offline/served.js → the outbox),
// so the server's list doesn't have it yet. Add it here from the outbox —
// "Waiting to sync" — and drop it again once the ping has gone (the page then
// lists it after a reload). Rows the server already lists are left alone.
const MONTHS = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]

export default class extends Controller {
  static targets = [ "list", "empty" ]
  static values = { today: String }

  connect() {
    this._paint()
    this._unsubscribe = subscribe((m) => { if (m?.type === "outbox") this._paint() })
  }

  disconnect() {
    this._unsubscribe?.()
  }

  async _paint() {
    const who = owner()
    const ops = (await pendingOps().catch(() => [])).filter((o) => o.kind === "service-served" && o.owner === who && o.studyId)
    if (!this.element.isConnected) return
    this.listTarget.querySelectorAll(".sv-row.is-pending").forEach((row) => row.remove())
    const latest = new Map()
    ops.forEach((op) => {
      const day = serviceToday(new Date(op.body?.at || op.createdAt || Date.now()))
      const listed = this.listTarget.querySelector(`.sv-row[data-study-id="${CSS.escape(op.studyId)}"]:not(.is-pending)`)
      if (listed && listed.dataset.servedOn >= day) return // the server has it (or a later day)
      const have = latest.get(op.studyId)
      if (!have || have.day < day) latest.set(op.studyId, { day, name: op.name })
    })
    const rows = [ ...latest.entries() ].sort((a, b) => (a[1].day < b[1].day ? 1 : -1))
    rows.reverse().forEach(([ studyId, { day, name } ]) => this.listTarget.prepend(this._row(studyId, day, name)))
    const any = !!this.listTarget.querySelector(".sv-row")
    this.listTarget.hidden = !any
    if (this.hasEmptyTarget) this.emptyTarget.hidden = any
  }

  _row(studyId, day, name) {
    const [ , m, d ] = day.split("-").map(Number)
    const el = (tag, cls, text) => {
      const node = document.createElement(tag)
      if (cls) node.className = cls
      if (text != null) node.textContent = text
      return node
    }
    const li = el("li", "sv-row is-pending")
    li.dataset.studyId = studyId
    li.dataset.servedOn = day
    const link = el("a", "sv-open")
    link.href = `/studies/${encodeURIComponent(studyId)}?queue=1`
    const when = el("span", "sv-when")
    when.append(el("span", "d", String(d)), el("span", "m", MONTHS[m - 1] || ""))
    const body = el("span", "sv-body")
    const title = el("span", "sv-name", name || "Service")
    if (day === this.todayValue) title.append(" ", el("span", "sv-tag", "Today"))
    body.append(title, el("span", "sv-meta", "Projected on this device · waiting to sync"))
    link.append(when, body)
    li.append(link, el("span", "sv-wait", "Will sync when online"))
    return li
  }
}
