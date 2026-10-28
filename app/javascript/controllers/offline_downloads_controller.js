import { Controller } from "@hotwired/stimulus"
import {
  fetchManifest, storedManifest, downloadedBibles, downloadBible, removeBible,
  storageEstimate, requestPersistence, refreshHighlights
} from "../lib/offline/store"
import { precachePages } from "../lib/offline/page"

// The Offline Bibles page: shows which translations are on this device, with
// their sizes, and downloads / removes them (IndexedDB, via lib/offline/store).
// After a download it asks the service worker to save the pages the reader
// needs to open the app with no signal.
export default class extends Controller {
  static targets = ["row", "network", "storage"]
  static values = { manifestUrl: String, returnUrl: String, signedIn: Boolean }

  async connect() {
    this._onNet = () => this.renderNetwork()
    window.addEventListener("online", this._onNet)
    window.addEventListener("offline", this._onNet)
    this.renderNetwork()
    this.busy = new Set()
    await this.refresh()
  }

  disconnect() {
    window.removeEventListener("online", this._onNet)
    window.removeEventListener("offline", this._onNet)
  }

  async refresh() {
    try {
      this.manifest = navigator.onLine ? await fetchManifest() : await storedManifest()
    } catch {
      this.manifest = await storedManifest()
    }
    this.downloaded = await downloadedBibles()
    this.rowTargets.forEach((row) => this.renderRow(row))
    this.renderStorage()
  }

  renderNetwork() {
    if (!this.hasNetworkTarget) return
    this.networkTarget.textContent = navigator.onLine
      ? ""
      : "You're offline — Bibles already on this device still open; downloading needs a connection."
  }

  summary(code) {
    return this.manifest?.translations?.find((t) => t.code === code)
  }

  renderRow(row) {
    const code = row.dataset.code
    const summary = this.summary(code)
    const have = this.downloaded?.find((d) => d.code === code)
    const busy = this.busy.has(code)
    const state = row.querySelector("[data-role='state']")
    const download = row.querySelector("[data-role='download']")
    const remove = row.querySelector("[data-role='remove']")
    const size = summary ? ` · ${mb(summary.size)} download, ${mb(summary.bytes)} on device` : ""

    row.classList.toggle("is-downloaded", !!have)
    if (busy) {
      state.textContent = "Downloading…"
    } else if (have && summary && have.version !== summary.version) {
      state.textContent = `Update available${size}`
    } else if (have) {
      state.textContent = `✓ On this device · ${mb(have.bytes)}`
    } else {
      state.textContent = summary ? `Not downloaded${size}` : (navigator.onLine ? "Not downloaded" : "Not downloaded — connect to download")
    }
    const stale = have && summary && have.version !== summary.version
    download.hidden = busy || (!!have && !stale) || !summary
    download.querySelector("span").textContent = stale ? "Update" : "Download"
    remove.hidden = busy || !have
  }

  async renderStorage() {
    if (!this.hasStorageTarget) return
    const count = this.downloaded?.length || 0
    const total = (this.downloaded || []).reduce((sum, d) => sum + (d.bytes || 0), 0)
    const estimate = await storageEstimate()
    let text = count ? `${count} Bible${count === 1 ? "" : "s"} on this device (about ${mb(total)}).` : "No Bibles downloaded yet."
    if (estimate?.quota) text += ` This browser allows about ${mb(estimate.quota)} for the app.`
    this.storageTarget.textContent = text
  }

  async download(event) {
    const row = event.currentTarget.closest("[data-code]")
    const code = row.dataset.code
    const summary = this.summary(code)
    if (!summary || this.busy.has(code)) return
    if (!navigator.onLine) { this.flash(row, "You're offline — connect to download."); return }

    this.busy.add(code)
    this.renderRow(row)
    const bar = row.querySelector("[data-role='bar']")
    bar.hidden = false
    bar.value = 2
    try {
      await downloadBible(summary, { onProgress: (f) => { bar.value = Math.round(f * 100) } })
      requestPersistence()
      this.savePages()
      if (this.signedInValue) refreshHighlights().catch(() => {})
    } catch {
      this.flash(row, "Download failed — check your connection and try again.")
    } finally {
      this.busy.delete(code)
      bar.hidden = true
      await this.refresh()
    }
  }

  async remove(event) {
    const row = event.currentTarget.closest("[data-code]")
    await removeBible(row.dataset.code).catch(() => {})
    await this.refresh()
  }

  // Pages to keep so the app opens offline: the study the reader came from
  // (or their latest, via /read), this page and More.
  savePages() {
    const urls = [ "/read", "/offline", "/more" ]
    if (this.returnUrlValue) urls.unshift(this.returnUrlValue)
    if (this.signedInValue) urls.push("/")
    precachePages(urls).catch(() => {})
  }

  flash(row, message) {
    const state = row.querySelector("[data-role='state']")
    state.textContent = message
  }
}

function mb(bytes) {
  if (!bytes) return "0 MB"
  const v = bytes / (1024 * 1024)
  return `${v >= 10 ? Math.round(v) : v.toFixed(1)} MB`
}
