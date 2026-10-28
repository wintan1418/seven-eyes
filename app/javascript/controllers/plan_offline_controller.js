import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { queuePlanDay } from "../lib/offline/outbox"
import { downloadedBibles, getMeta } from "../lib/offline/store"
import { owner, precachePages } from "../lib/offline/page"

// A reading plan with no signal (on the plan page):
//   • "Mark done" / "✓ Done" still work — the tick is queued in the outbox
//     and sent when the connection is back; the row shows it at once.
//   • "Begin today's reading" opens the plan's study (saved on the device)
//     with today's passages (by this device's date) loaded from the
//     downloaded Bibles.
//   • Online, with Bibles downloaded, it saves the plan's study page so the
//     next week's readings open offline.
export default class extends Controller {
  static targets = ["day", "begin"]
  static values = { studyUrl: String }

  connect() {
    this._onSubmit = (e) => this.tick(e)
    this.element.addEventListener("submit", this._onSubmit, true)
    this.saveForOffline()
  }

  disconnect() {
    this.element.removeEventListener("submit", this._onSubmit, true)
  }

  async saveForOffline() {
    if (!navigator.onLine || !(await downloadedBibles()).length) return
    const urls = [ "/reading_plans", window.location.pathname ]
    if (this.studyUrlValue) urls.push(this.studyUrlValue)
    precachePages(urls).catch(() => {})
  }

  // A day's tick while offline: queue it, show it.
  tick(event) {
    if (navigator.onLine) return
    const form = event.target
    const row = form.closest("[data-plan-offline-target='day']")
    if (!row || !form.action.includes("/complete")) return
    event.preventDefault()
    event.stopImmediatePropagation()

    const method = (form.querySelector("input[name='_method']")?.value || form.method).toLowerCase()
    const done = method !== "delete"
    const path = new URL(form.action, window.location.href).pathname
    queuePlanDay(path, done, owner()).catch(() => {})
    this.showTick(row, form, done)
  }

  showTick(row, form, done) {
    row.classList.toggle("is-done", done)
    const button = form.querySelector("button, input[type=submit]")
    const label = done ? "✓ Done" : "Mark done"
    if (button?.tagName === "INPUT") button.value = label
    else if (button) button.textContent = label
    button?.classList.toggle("is-on", done)
    button?.setAttribute("title", "Saved on this device — will sync when you're online")
    // Next press undoes it.
    let override = form.querySelector("input[name='_method']")
    if (done) {
      if (!override) {
        override = document.createElement("input")
        override.type = "hidden"
        override.name = "_method"
        form.prepend(override)
      }
      override.value = "delete"
    } else {
      override?.remove()
    }
  }

  // "Begin today's reading" offline: today's passages into the saved study.
  async begin(event) {
    if (navigator.onLine) return
    event.preventDefault()
    const today = localDate()
    const row = this.dayTargets.find((d) => d.dataset.date === today) ||
      this.dayTargets.find((d) => d.classList.contains("is-today"))
    const refs = (row?.dataset.paneRefs || "").split("|").filter(Boolean)
    const study = this.studyUrlValue || await getMeta("lastStudyUrl")
    if (!refs.length || !study) {
      this.flash(refs.length ? "Open the plan's study once online to read it offline." : "No reading scheduled for today.")
      return
    }
    Turbo.visit(`${study}?refs=${encodeURIComponent(refs.join("|"))}`)
  }

  flash(text) {
    window.dispatchEvent(new CustomEvent("offline:toast", { detail: { message: text } }))
  }
}

function localDate() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}
