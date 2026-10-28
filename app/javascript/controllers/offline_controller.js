import { Controller } from "@hotwired/stimulus"
import { downloadedBibles, clearPersonal } from "../lib/offline/store"
import { pendingCount, flushOutbox, subscribe } from "../lib/offline/outbox"
import { clearSavedPages } from "../lib/offline/page"

// The calm offline layer on every page (wrapper near the top of <body>):
//   • a badge while the device is offline — "Offline · reading from your
//     downloads" when Bibles are on the device,
//   • a sync pill — "3 changes waiting to sync" / "Syncing…" / "All changes saved",
//   • a gentle "needs internet" message instead of a silent failure when an
//     online-only feature (AI, cross-references, commentary, live, remote…)
//     is tapped while offline,
//   • on sign-out (any DELETE form to /session): send queued changes first,
//     then drop saved pages, cached highlights and the outbox, so nothing from
//     this reader stays on a shared device.
const NEEDS_INTERNET = [
  [ ".ps-vnum, a[data-turbo-frame='xref_drawer'], [data-action~='verse-actions#crossRefs'], [data-action~='xref#open']", "Cross-references need" ],
  [ "a[data-turbo-frame='commentary_drawer'], [data-action~='verse-actions#commentary']", "The commentary needs" ],
  [ "[data-action*='rabbi#'], [data-action~='verse-actions#rabbi']", "The AI Rabbi needs" ],
  [ "[data-action*='ai-search#']", "AI Find a Verse needs" ],
  [ "[data-action~='search#open']", "Bible search needs" ],
  [ "[data-action~='live#toggle']", "Live follow-along needs" ],
  [ "[data-action~='remote#toggle']", "The phone remote needs" ],
  [ "[data-action~='reader#toggle']", "The audio Bible needs" ],
  [ "[data-action*='lexicon#open'], [data-action~='verse-actions#wordStudy']", "Word study needs" ],
  [ "[data-action~='pane#share'], [data-action~='verse-actions#share']", "Share pictures need" ],
  [ "[data-action~='pane#prayer']", "Chapter prayers need" ],
  [ "[data-action~='share#copy']", "Share links need" ],
  [ "[data-action~='new-study#open'], form.ui-menu-new-form button", "New studies need" ],
  [ "[data-tour='panes'], [data-action~='diff#toggle']", "Changing the layout needs" ],
  [ "a[href$='/sermon'], a[href*='/sermon?']", "The sermon manuscript needs" ]
]

export default class extends Controller {
  static targets = ["badge", "label", "sync"]

  connect() {
    this._update = () => this.render()
    this._onSubmit = (e) => this._maybeSignOut(e)
    this._onClick = (e) => this._guard(e)
    window.addEventListener("online", this._update)
    window.addEventListener("offline", this._update)
    document.addEventListener("submit", this._onSubmit, true)
    document.addEventListener("click", this._onClick, true)
    this._unsubscribe = subscribe((m) => this._onMessage(m))
    this.render()
    this.renderSync()
  }

  disconnect() {
    window.removeEventListener("online", this._update)
    window.removeEventListener("offline", this._update)
    document.removeEventListener("submit", this._onSubmit, true)
    document.removeEventListener("click", this._onClick, true)
    this._unsubscribe?.()
  }

  async render() {
    const online = navigator.onLine
    if (this.hasBadgeTarget) this.badgeTarget.hidden = online
    if (!online && this.hasLabelTarget) {
      const have = (await downloadedBibles()).length > 0
      const live = document.querySelector(".ps-root.is-live-session")
      this.labelTarget.textContent = live
        ? "Offline · live follow-along paused"
        : (have ? "Offline · reading from your downloads" : "Offline")
    }
    this.renderSync()
  }

  async renderSync(pending) {
    if (!this.hasSyncTarget) return
    const count = pending ?? await pendingCount()
    if (count > 0) {
      clearTimeout(this._syncTimer)
      this._syncTimer = null
      this.syncTarget.textContent = `${count} change${count === 1 ? "" : "s"} waiting to sync`
      this.syncTarget.hidden = false
      this._hadPending = true
    } else if (this._hadPending) {
      // Everything queued has reached the server: say so, briefly.
      this._hadPending = false
      this.syncTarget.textContent = "All changes saved"
      this.syncTarget.hidden = false
      clearTimeout(this._syncTimer)
      this._syncTimer = setTimeout(() => { this.syncTarget.hidden = true; this._syncTimer = null }, 5000)
    } else if (!this._syncTimer) {
      this.syncTarget.hidden = true
    }
  }

  _onMessage(message) {
    if (message?.type === "outbox") this.renderSync(message.pending)
    else if (message?.type === "notes-synced" && message.conflict) {
      this.toast("Your offline note was added below the newer copy — look for “Offline edit”.")
    } else if (message?.type === "sync-problem") this.toast(message.message)
  }

  _guard(event) {
    if (navigator.onLine) return
    const target = event.target instanceof Element ? event.target : null
    if (!target) return
    for (const [ selector, what ] of NEEDS_INTERNET) {
      if (target.closest(selector)) {
        event.preventDefault()
        event.stopImmediatePropagation()
        this.toast(`${what} internet — you're offline.`)
        return
      }
    }
  }

  toast(text) {
    let el = document.querySelector(".ui-offline-toast")
    if (!el) {
      el = document.createElement("div")
      el.className = "ui-offline-toast"
      el.setAttribute("role", "status")
      document.body.appendChild(el)
    }
    el.textContent = text
    el.classList.add("is-on")
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => el.classList.remove("is-on"), 3500)
  }

  _maybeSignOut(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || form.dataset.offlineCleared) return
    const method = (form.querySelector("input[name='_method']")?.value || form.method || "").toLowerCase()
    let path = ""
    try { path = new URL(form.action, window.location.href).pathname } catch { return }
    if (method !== "delete" || path !== "/session") return

    // Hold the sign-out a moment: send what's queued, then forget this reader.
    event.preventDefault()
    event.stopImmediatePropagation()
    form.dataset.offlineCleared = "1"
    const timeout = new Promise((resolve) => setTimeout(resolve, 5000))
    const flushed = navigator.onLine ? flushOutbox().catch(() => {}) : Promise.resolve()
    Promise.race([ flushed, timeout ])
      .then(() => clearPersonal({ outbox: true }))
      .catch(() => {})
      .finally(() => {
        clearSavedPages()
        form.requestSubmit ? form.requestSubmit(event.submitter || undefined) : form.submit()
      })
  }
}
