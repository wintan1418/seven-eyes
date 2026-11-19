import { Controller } from "@hotwired/stimulus"
import { getMeta, setMeta } from "../lib/offline/db"
import { quickFetch, isNetworkSlow } from "../lib/offline/network"
import { owner, signedIn } from "../lib/offline/page"
import { saveMedia, mediaOnDevice } from "../lib/offline/media"
import { applyPicture, pictureDisplay, pictureLabel } from "../lib/picture_fit"

// The console's Pictures tab, around the Picture Bank (console-library):
//
//   This service | My Media    two views. "This service" is the Picture Bank
//                               as before. "My Media" is the account's library
//                               (GET /media.json, kept on the device in meta
//                               "myMedia:<owner>" so it opens with no signal):
//                               search by title, click → Preview, double-click
//                               or Go live → the screen, "+ Add to service" →
//                               the queue (by library id, through the outbox —
//                               works offline). Upload adds to the library and,
//                               ticked, to the service too.
//   offline                     how many of the view's pictures are on this
//                               device, and "Save for offline" (the service
//                               worker's ps-media cache, lib/offline/media.js).
//                               Entering preach saves the service's pictures
//                               by itself (signed in, not on Data Saver).
const LIST_TIMEOUT_MS = 5000
const UPLOAD_TIMEOUT_MS = 120_000
const MAX_BYTES = 5 * 1024 * 1024

export default class extends Controller {
  static targets = [ "tab", "view", "grid", "search", "status", "also", "controls", "name", "offlineText", "offlineButton", "upload" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root || this.root.classList.contains("is-output")) return
    this.assets = []
    this._view = "service"
    this._selected = null
    this._listeners = {
      "setlist:changed": () => { this._markInService(); this._paintOffline() },
      "preach:enter": () => this._autoSave(),
      "console:on": () => { if (this._view === "library") this._refresh() }
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    this._loadCached()
  }

  disconnect() {
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
  }

  // ---- views ---------------------------------------------------------------------------

  view(event) {
    event?.preventDefault?.()
    this._view = event.currentTarget.dataset.view
    this.tabTargets.forEach((t) => {
      t.setAttribute("aria-selected", String(t.dataset.view === this._view))
      t.setAttribute("aria-pressed", String(t.dataset.view === this._view))
    })
    this.viewTargets.forEach((v) => { v.hidden = v.dataset.pbankView !== this._view })
    if (this._view === "library") this._refresh()
    this._paintOffline()
  }

  // ---- the library: device copy first, then the server ----------------------------------------

  get _metaKey() { return `myMedia:${owner()}` }

  async _loadCached() {
    if (!signedIn()) { this._paint(); return }
    const cached = await getMeta(this._metaKey).catch(() => null)
    if (Array.isArray(cached?.assets)) { this.assets = cached.assets; this._paint() }
  }

  async _refresh() {
    if (!signedIn()) { this._paint(); return }
    if (!this.assets.length) this._status("Loading your pictures…")
    if (navigator.onLine === false || isNetworkSlow()) {
      this._status(this.assets.length ? "Offline — showing the pictures known on this computer." : "Offline — My Media opens once you're connected.")
      return
    }
    try {
      const { res, body } = await quickFetch("/media.json", { headers: { Accept: "application/json" } }, { timeoutMs: LIST_TIMEOUT_MS, read: "json" })
      if (!res.ok || !Array.isArray(body?.assets)) throw new Error("bad list")
      this.assets = body.assets
      await setMeta(this._metaKey, { assets: this.assets, at: Date.now() }).catch(() => {})
      this._status("")
      this._paint()
    } catch {
      this._status(this.assets.length ? "Couldn't refresh — showing the pictures known on this computer." : "Couldn't load My Media — try again in a moment.")
    }
  }

  _paint() {
    if (!this.hasGridTarget) return
    if (!signedIn()) {
      this.gridTarget.replaceChildren(el("li", "cx-empty", "Sign in to keep a picture library — upload once, use it in any service on any computer."))
      this._paintControls()
      return
    }
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    const list = this.assets.filter((a) => !q || String(a.title || "").toLowerCase().includes(q))
    if (!this.assets.length) this.gridTarget.replaceChildren(el("li", "cx-empty", "No pictures in My Media yet — upload some here or on the My Media page, or add one to any service and it is kept here too."))
    else if (!list.length) this.gridTarget.replaceChildren(el("li", "cx-empty", "No picture has that in its title."))
    else this.gridTarget.replaceChildren(...list.map((a) => this._card(a)))
    this._markInService()
    this._paintControls()
    this._paintOffline()
  }

  filter() { this._paint() }

  _card(asset) {
    const card = el("li", "cx-pcard")
    card.dataset.assetId = String(asset.id)
    card.dataset.url = asset.url
    card.classList.toggle("is-selected", asset.id === this._selected)
    const btn = el("button", "pick")
    btn.type = "button"
    btn.dataset.action = "click->console-media#pick dblclick->console-media#live"
    btn.title = "Click to preview · double-click to go live"
    const frame = el("span", "frame slide-img")
    applyPicture(frame, asset.display)
    const img = el("img")
    img.alt = ""
    img.loading = "lazy"
    img.decoding = "async"
    img.addEventListener("error", () => { if (img.getAttribute("src") !== asset.url) img.src = asset.url }, { once: true })
    img.src = asset.thumb || asset.url
    frame.append(img)
    const cap = el("span", "cap")
    cap.append(el("span", "lbl", asset.title || "Picture"), el("span", "tag inservice", "IN SERVICE"),
      el("span", "dot", "●"), el("span", "meta", pictureLabel(asset.display)))
    cap.querySelector(".dot").title = "On this device — shows with no internet"
    btn.append(frame, cap)
    card.append(btn)
    return card
  }

  _asset(event) {
    const id = Number(event.currentTarget.closest("[data-asset-id]")?.dataset.assetId)
    return this.assets.find((a) => a.id === id) || null
  }

  _selectedAsset() { return this.assets.find((a) => a.id === this._selected) || null }

  pick(event) {
    event.preventDefault()
    const asset = this._asset(event)
    if (!asset) return
    this._select(asset)
    window.dispatchEvent(new CustomEvent("preview:load", { detail: this._detail(asset) }))
  }

  live(event) {
    event.preventDefault()
    const asset = this._asset(event)
    if (!asset) return
    this._select(asset)
    this._goLive(asset)
  }

  previewSelected(event) {
    event?.preventDefault?.()
    const asset = this._selectedAsset()
    if (asset) window.dispatchEvent(new CustomEvent("preview:load", { detail: this._detail(asset) }))
  }

  liveSelected(event) {
    event?.preventDefault?.()
    const asset = this._selectedAsset()
    if (asset) this._goLive(asset)
  }

  addSelected(event) {
    event?.preventDefault?.()
    const asset = this._selectedAsset()
    if (asset) this._addToService(asset)
  }

  _goLive(asset) {
    window.dispatchEvent(new CustomEvent("preview:load", { detail: this._detail(asset) }))
    window.dispatchEvent(new CustomEvent("preview:golive"))
  }

  _detail(asset) {
    return { kind: "slide", itemKind: "picture", label: asset.title || "Picture", title: asset.title || null,
      image: asset.url, picture: pictureDisplay(asset.display) }
  }

  _addToService(asset) {
    window.dispatchEvent(new CustomEvent("setlist:add-item", { detail: { fields: {
      kind: "picture", title: asset.title || "Picture", label: asset.title || "Picture", image: asset.url,
      data: pictureDisplay(asset.display), media_asset_id: asset.id, stanzas: 0
    } } }))
  }

  _select(asset) {
    this._selected = asset.id
    this.gridTarget.querySelectorAll(".cx-pcard").forEach((c) => c.classList.toggle("is-selected", Number(c.dataset.assetId) === asset.id))
    this._paintControls()
  }

  _paintControls() {
    if (!this.hasControlsTarget) return
    const asset = this._selectedAsset()
    this.controlsTarget.hidden = !asset
    if (asset) this.nameTarget.textContent = asset.title || "Picture"
  }

  _serviceItems() {
    let items = []
    window.dispatchEvent(new CustomEvent("setlist:request-items", { detail: { reply: (list) => { items = list } } }))
    return items.filter((i) => i.kind === "picture" && i.image)
  }

  _markInService() {
    if (!this.hasGridTarget) return
    const used = new Set(this._serviceItems().map((i) => Number(i.media_asset_id)).filter(Boolean))
    this.gridTarget.querySelectorAll(".cx-pcard").forEach((c) => c.classList.toggle("is-in-service", used.has(Number(c.dataset.assetId))))
  }

  // ---- upload (to the library; ticked: to the service too) --------------------------------------

  async upload(event) {
    const input = event.currentTarget
    const files = [ ...(input.files || []) ]
    input.value = ""
    if (!files.length) return
    if (!signedIn()) { window.dispatchEvent(new CustomEvent("auth:required")); return }
    if (navigator.onLine === false) { this._status("You're offline — uploading needs a connection. Pictures saved on this device still show."); return }
    const also = this.hasAlsoTarget && this.alsoTarget.checked
    let added = 0
    const problems = []
    for (const [ i, file ] of files.entries()) {
      if (!file.type.startsWith("image/")) { problems.push(`${file.name}: not a picture`); continue }
      if (file.size > MAX_BYTES) { problems.push(`${file.name}: over 5 MB`); continue }
      this._status(`Uploading ${i + 1} of ${files.length}…`)
      const form = new FormData()
      form.append("file", file)
      try {
        // Plain fetch: a slow upload mustn't mark the network "slow" for the service.
        const res = await fetch("/media", {
          method: "POST", body: form, credentials: "same-origin", signal: AbortSignal.timeout?.(UPLOAD_TIMEOUT_MS),
          headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
        })
        const body = await res.json().catch(() => null)
        if (!res.ok || !body?.asset) { problems.push(`${file.name}: ${body?.error || "couldn't upload"}`); continue }
        this.assets = [ body.asset, ...this.assets.filter((a) => a.id !== body.asset.id) ]
        added++
        if (also) this._addToService(body.asset)
        this._select(body.asset)
      } catch {
        problems.push(`${file.name}: no connection`)
      }
    }
    await setMeta(this._metaKey, { assets: this.assets, at: Date.now() }).catch(() => {})
    this._paint()
    const done = added ? `Added ${added} picture${added === 1 ? "" : "s"} to My Media${also ? " and this service" : ""}.` : ""
    this._status([ done, problems.join(" · ") ].filter(Boolean).join(" "))
  }

  // ---- offline -------------------------------------------------------------------------------

  _viewUrls() {
    return this._view === "library" ? this.assets.map((a) => a.url) : this._serviceItems().map((i) => i.image)
  }

  async _paintOffline() {
    if (!this.hasOfflineTextTarget) return
    const urls = [ ...new Set(this._viewUrls().filter(Boolean)) ]
    const saved = await mediaOnDevice(urls)
    if (this._view === "library" && this.hasGridTarget) {
      this.gridTarget.querySelectorAll(".cx-pcard").forEach((c) => c.classList.toggle("is-on-device", saved.has(c.dataset.url)))
    }
    if (this._saving) return
    const what = this._view === "library" ? "in My Media" : "in this service"
    if (!urls.length) {
      this.offlineTextTarget.textContent = ""
      this.offlineButtonTarget.hidden = true
      return
    }
    const all = saved.size >= urls.length
    this.offlineTextTarget.textContent = all
      ? `✓ All ${urls.length} picture${urls.length === 1 ? "" : "s"} ${what} available offline`
      : `${saved.size} of ${urls.length} picture${urls.length === 1 ? "" : "s"} ${what} on this device`
    this.offlineTextTarget.dataset.state = all ? "ready" : "missing"
    this.offlineButtonTarget.hidden = all
  }

  async saveOffline(event) {
    event?.preventDefault?.()
    await this._save(this._viewUrls())
  }

  // Entering preach: the service's pictures go on the device by themselves.
  _autoSave() {
    if (!signedIn() || navigator.connection?.saveData || navigator.onLine === false || isNetworkSlow()) { this._paintOffline(); return }
    setTimeout(() => this._save(this._serviceItems().map((i) => i.image), { quiet: true }), 1500)
  }

  async _save(urls, { quiet = false } = {}) {
    if (this._saving) return
    if (navigator.onLine === false) { if (!quiet) this.offlineTextTarget.textContent = "Offline — connect to save pictures on this device"; return }
    this._saving = true
    this.offlineButtonTarget.disabled = true
    try {
      const result = await saveMedia(urls, {
        onProgress: ({ done, total }) => { if (total) this.offlineTextTarget.textContent = `Saving pictures for offline… ${done} of ${total}` }
      })
      if (result.unsupported && !quiet) this._status("This browser can't keep pictures offline — use Chrome, Edge or the app.")
      else if (result.failed && !quiet) this._status(`${result.failed} picture${result.failed === 1 ? "" : "s"} couldn't be saved — try again.`)
    } finally {
      this._saving = false
      this.offlineButtonTarget.disabled = false
      this._paintOffline()
    }
  }

  _status(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text || ""
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
