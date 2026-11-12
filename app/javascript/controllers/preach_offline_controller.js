import { Controller } from "@hotwired/stimulus"
import { storedManifest, fetchManifest, downloadedBibles, downloadBible, requestPersistence, bookCount } from "../lib/offline/store"
import { warmLocal } from "../lib/offline/local_pane"
import { isNetworkSlow } from "../lib/offline/network"
import { signedIn } from "../lib/offline/page"

const MANIFEST_TIMEOUT_MS = 5000
const STALL_MS = 15_000 // no bytes for this long: give up (the badge says "Not ready")

// The "Ready offline" badge in the preach bar. When a signed-in presenter
// enters preach mode (window "preach:enter"), the Bibles this study's panes
// use are downloaded in the background — whole translations, a few MB each,
// only the ones the study uses — so a dead signal mid-service can't stop
// Scripture going on screen. Guests (and Data Saver) get a tap-to-download
// badge instead. States: checking · downloading · ready · missing.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    if (this.element.closest(".is-output")) return
    this._onEnter = () => this.prepare({ auto: signedIn() && !navigator.connection?.saveData })
    this._onNetwork = () => this.refresh()
    window.addEventListener("preach:enter", this._onEnter)
    window.addEventListener("online", this._onNetwork)
    window.addEventListener("offline", this._onNetwork)
  }

  disconnect() {
    window.removeEventListener("preach:enter", this._onEnter)
    window.removeEventListener("online", this._onNetwork)
    window.removeEventListener("offline", this._onNetwork)
  }

  // Tap: download what's missing now.
  download(event) {
    event?.preventDefault?.()
    if (this.element.dataset.state === "missing") this.prepare({ auto: true })
  }

  async refresh() {
    if (this._busy) return
    const { missing, ready } = await this.status()
    if (!missing.length && ready.length) this.showReady(ready)
    else this.showMissing(missing)
  }

  async prepare({ auto }) {
    if (this._busy) return
    this.element.hidden = false
    let { manifest, missing, ready } = await this.status()
    if (!missing.length && ready.length) { this.showReady(ready); return }
    if (!auto || !this.online) { this.showMissing(missing); return }

    this._busy = true
    try {
      manifest = await this.freshManifest() || manifest
      if (!manifest) { this.showMissing(missing); return }
      for (const code of missing.map(m => m.code)) {
        const t = manifest.translations.find(x => x.code === code)
        if (!t) continue
        this.set("downloading", `Downloading the whole ${t.code} Bible for offline… 0% · ${mb(t.size)}`)
        // A signal that dies mid-download must not leave the badge spinning.
        const controller = new AbortController()
        let stall = setTimeout(() => controller.abort(), STALL_MS)
        try {
          await downloadBible(t, {
            signal: controller.signal,
            onProgress: (f) => {
              clearTimeout(stall)
              stall = setTimeout(() => controller.abort(), STALL_MS)
              this.set("downloading", `Downloading the whole ${t.code} Bible for offline… ${Math.round(f * 100)}% · ${mb(t.size)}`)
            }
          })
        } finally {
          clearTimeout(stall)
        }
      }
      requestPersistence()
      await warmLocal({ force: true })
    } catch {
      /* keep whatever finished; the badge says what's still missing */
    } finally {
      this._busy = false
    }
    await this.refresh()
  }

  // What the study's panes use (by code, read off their translation selects),
  // and which of those are on the device.
  async status() {
    const [ manifest, downloaded ] = await Promise.all([ storedManifest(), downloadedBibles() ])
    const codes = [ ...new Set([ ...document.querySelectorAll(".ps-workspace .ps-pane select[name='pane[translation_id]']") ]
      .map(s => s.selectedOptions?.[0]?.textContent?.trim()).filter(Boolean)) ]
    const ready = []
    const missing = []
    for (const code of codes) {
      const have = downloaded.find(d => d.code === code)
      if (have) ready.push({ code, books: have.books || await bookCount(code) })
      else missing.push({ code, size: manifest?.translations?.find(t => t.code === code)?.size })
    }
    return { manifest, missing, ready }
  }

  async freshManifest() {
    try {
      return await Promise.race([ fetchManifest(), new Promise((_, no) => setTimeout(() => no(new Error("slow")), MANIFEST_TIMEOUT_MS)) ])
    } catch { return null }
  }

  get online() { return navigator.onLine !== false && !isNetworkSlow() }

  showReady(ready) {
    const what = ready.map(r => `${r.code}`).join(" + ")
    const books = ready.map(r => `Whole ${r.code} Bible saved on this device (${r.books} books)`).join(" · ")
    this.set("ready", `✓ Ready offline · whole ${what} Bible${ready.length > 1 ? "s" : ""}`,
      `${books} — Scripture goes on screen with no internet.`)
  }

  showMissing(missing) {
    const what = missing.map(m => `${m.code}${m.size ? ` (${mb(m.size)})` : ""}`).join(", ")
    const action = this.online ? (what ? ` · tap to download ${what}` : "") : " · connect to download"
    this.set("missing", `Not ready offline${action}`,
      "This study's Bible isn't on this device yet: with no signal, references can't go on screen.")
  }

  set(state, text, title = text) {
    this.element.hidden = false
    this.element.dataset.state = state
    this.element.title = title
    if (this.hasLabelTarget) this.labelTarget.textContent = text
  }
}

function mb(bytes) {
  if (!bytes) return "a few MB"
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}
