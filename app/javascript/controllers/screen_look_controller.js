import { Controller } from "@hotwired/stimulus"
import { LOOKS, lookById, loadPrefs, savePrefs, normalizePrefs } from "../lib/slide_themes"
import { putMedia, deleteMedia, mediaUrl } from "../lib/screen_media"

// The projection's Look: slide template, background (the look's own, the
// church's picture, or a looping muted video), Fade/Cut, and the logo slide's
// logo + church name. Lives on the Looks panel (.ps-screen-panel) in every
// window: the operator picks; the projector and stage apply.
//
//   root data-look / data-look-ref / data-look-bg / data-slide-transition
//     → slide_themes.css draws it; presentation_controller reads the
//       transition (lib/slide_transition)
//   [data-look-bg]      the background layer (custom picture / video inside)
//   [data-screen-logo]  the logo slide's contents (screen_live shows it)
//
// Choices are kept on this device per study + as its default (lib/slide_themes);
// pictures, video and logo in IndexedDB (lib/screen_media), so it all works
// offline. The projector reads the same storage on boot (no flash of the
// wrong look) and follows the operator over the preach BroadcastChannel:
//   {type:"look", prefs}  {type:"media"}  {type:"brand", brand}
const BRAND_KEY = "ps-screen-brand"

export default class extends Controller {
  static targets = [ "grid", "preview", "bgButton", "transitionButton", "dim", "logoThumb", "brandName", "brandLine", "note" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root) return
    this.isOutput = this.root.classList.contains("is-output")
    this.studyScope = window.location.pathname
    this.prefs = loadPrefs(this._storage(), this.studyScope)
    this.brand = this._loadBrand()
    if ("BroadcastChannel" in window) {
      this.channel = new BroadcastChannel(`ps-preach:${window.location.pathname}`)
      this.channel.onmessage = (e) => this._onMessage(e.data)
    }
    this._apply({ refit: false })
    this._paintLogo()
    if (!this.isOutput) {
      this._renderGrid()
      this._syncPanel()
      // Fill the thumbnails with what's on screen each time the panel opens.
      this._observer = new MutationObserver(() => { if (!this.element.hidden) this._refreshSamples() })
      this._observer.observe(this.element, { attributes: true, attributeFilter: [ "hidden" ] })
    }
    document.fonts?.ready?.then(() => this._refit())
  }

  disconnect() {
    this._observer?.disconnect()
    this.channel?.close()
    this.channel = null
  }

  // ---- operator: choices ----------------------------------------------------

  pick(event) {
    event?.preventDefault?.()
    const id = event.currentTarget.dataset.lookId
    if (!lookById(id)) return
    this._change({ look: id })
    // Keep the older Vellum/Ink/Paper setting (presentation#setTheme) in step,
    // so its classes never fight the look on the projector.
    const legacy = lookById(id).legacy || "vellum"
    this.element.querySelector(`[data-screen-theme="${legacy}"]`)?.click()
  }

  setBg(event) {
    event?.preventDefault?.()
    const bg = event.currentTarget.dataset.bg
    this._change({ bg })
    if (bg !== "look") this._checkMedia(bg)
  }

  setTransition(event) {
    event?.preventDefault?.()
    this._change({ transition: event.currentTarget.dataset.transition })
  }

  setDim(event) {
    this._change({ dim: parseFloat(event.currentTarget.value) })
  }

  async upload(event) {
    const input = event.currentTarget
    const slot = input.dataset.slot
    const file = input.files?.[0]
    input.value = ""
    if (!file) return
    this._note(slot === "video" ? "Saving the video on this computer…" : "Saving…")
    try {
      await putMedia(slot, file)
    } catch (e) {
      this._note(e.message || "Couldn't save that file", true)
      return
    }
    this._note(slot === "logo" ? "Logo saved on this computer — it works offline." : "Saved on this computer — it works offline.")
    this._send({ type: "media" })
    if (slot === "logo") this._paintLogo()
    else if (this.prefs.bg !== slot) this._change({ bg: slot })
    else this._paintBackground()
  }

  async removeMedia(event) {
    event?.preventDefault?.()
    const slot = event.currentTarget.dataset.slot
    await deleteMedia(slot)
    this._send({ type: "media" })
    if (slot === "logo") this._paintLogo()
    if (this.prefs.bg === slot) this._change({ bg: "look" })
    else this._paintBackground()
    this._note(null)
  }

  setBrand() {
    this.brand = {
      name: this.hasBrandNameTarget ? this.brandNameTarget.value.trim().slice(0, 80) : "",
      line: this.hasBrandLineTarget ? this.brandLineTarget.value.trim().slice(0, 120) : ""
    }
    try { localStorage.setItem(BRAND_KEY, JSON.stringify(this.brand)) } catch { /* private mode */ }
    this._paintLogo()
    this._send({ type: "brand", brand: this.brand })
  }

  _change(patch) {
    this.prefs = savePrefs(this._storage(), this.studyScope, { ...this.prefs, ...patch })
    this._apply()
    this._syncPanel()
    this._send({ type: "look", prefs: this.prefs })
  }

  // ---- every window: draw it -------------------------------------------------

  _apply({ refit = true } = {}) {
    const look = lookById(this.prefs.look) || LOOKS[0]
    const ds = this.root.dataset
    ds.look = look.id
    ds.lookRef = look.ref
    ds.lookBg = this.prefs.bg
    ds.slideTransition = this.prefs.transition
    this.root.style.setProperty("--look-dim", String(this.prefs.dim))
    this._paintBackground()
    if (refit) this._refit()
  }

  _refit() {
    window.dispatchEvent(new CustomEvent("preach:refit"))
  }

  // The church's picture or video under the words (the look's own gradient
  // when there is none — e.g. the file was never saved on this computer).
  async _paintBackground() {
    const layer = this.root.querySelector("[data-look-bg]")
    if (!layer) return
    const bg = this.prefs.bg
    const url = bg === "look" ? null : await mediaUrl(bg)
    if (bg !== this.prefs.bg) return // changed while reading
    this.root.dataset.lookBg = url ? bg : "look"
    const current = layer.querySelector(".media")
    if (!url) { current?.remove(); this._paintPreviewMedia(null, null); return }
    if (current && current.dataset.src === url) return
    const el = document.createElement(bg === "video" ? "video" : "img")
    el.className = "media"
    el.dataset.src = url
    el.setAttribute("aria-hidden", "true")
    if (bg === "video") {
      Object.assign(el, { muted: true, loop: true, autoplay: true, playsInline: true })
      el.setAttribute("muted", "")
      el.setAttribute("playsinline", "")
    } else {
      el.alt = ""
    }
    el.src = url
    current?.remove()
    layer.prepend(el)
    if (bg === "video") el.play?.().catch(() => {})
    this._paintPreviewMedia(bg, url)
  }

  async _paintLogo() {
    const box = this.root.querySelector("[data-screen-logo]")
    const url = await mediaUrl("logo")
    const { name, line } = this.brand || {}
    if (box) {
      box.replaceChildren()
      if (url) box.append(make("img", "logo-img", null, { src: url, alt: name || "Logo" }))
      else if (!name) box.append(make("div", "logo-orn", "✦"))
      if (name) box.append(make("div", "logo-name", name))
      if (line) box.append(make("div", "logo-line", line))
      box.classList.toggle("has-img", !!url)
    }
    if (!this.isOutput && this.hasLogoThumbTarget) {
      this.logoThumbTarget.replaceChildren(url ? make("img", null, null, { src: url, alt: "" }) : make("span", null, "No logo"))
      this.logoThumbTarget.classList.toggle("is-empty", !url)
    }
  }

  // ---- the panel ---------------------------------------------------------------

  _renderGrid() {
    if (!this.hasGridTarget) return
    this.gridTarget.replaceChildren(...LOOKS.map((look) => {
      const btn = make("button", "ps-look-tile", null, { type: "button" })
      btn.dataset.lookId = look.id
      btn.dataset.look = look.id
      btn.dataset.lookRef = look.ref
      btn.dataset.action = "screen-look#pick"
      btn.setAttribute("role", "radio")
      btn.title = `${look.name} — ${look.blurb}`
      const screen = make("span", "lt-screen")
      screen.append(make("span", "lt-text", "For God so loved the world"), make("span", "lt-ref", "John 3:16"))
      btn.append(screen, make("span", "lt-name", look.name))
      return btn
    }))
  }

  _syncPanel() {
    if (this.isOutput) return
    this.gridTarget?.querySelectorAll(".ps-look-tile").forEach((t) => {
      const on = t.dataset.lookId === this.prefs.look
      t.classList.toggle("is-on", on)
      t.setAttribute("aria-checked", String(on))
    })
    this.bgButtonTargets.forEach((b) => b.classList.toggle("is-on", b.dataset.bg === this.prefs.bg))
    this.transitionButtonTargets.forEach((b) => b.classList.toggle("is-on", b.dataset.transition === this.prefs.transition))
    if (this.hasDimTarget) this.dimTarget.value = String(this.prefs.dim)
    if (this.hasPreviewTarget) {
      const look = lookById(this.prefs.look)
      this.previewTarget.dataset.look = look.id
      this.previewTarget.dataset.lookRef = look.ref
      this.previewTarget.querySelector(".lp-name").textContent = look.name
    }
    if (this.hasBrandNameTarget && document.activeElement !== this.brandNameTarget) this.brandNameTarget.value = this.brand?.name || ""
    if (this.hasBrandLineTarget && document.activeElement !== this.brandLineTarget) this.brandLineTarget.value = this.brand?.line || ""
  }

  // Live thumbnails: the words on screen now, in every look.
  _refreshSamples() {
    const slide = this.root.querySelector("[data-preach-slide] .slide-stanza")
    let text = ""
    let ref = ""
    if (this.root.classList.contains("is-slide") && slide) {
      text = slide.textContent
      ref = this.root.querySelector("[data-preach-slide] .slide-title")?.textContent || ""
    } else {
      text = Array.from(this.root.querySelectorAll(".ps-pane.is-presented .ps-verse.is-preach-current .ps-verse-text"))
        .map((t) => t.textContent).join(" ")
      ref = this.root.querySelector("[data-preach-ref]")?.textContent || ""
    }
    text = text.replace(/\s+/g, " ").trim() || "For God so loved the world, that he gave his only begotten Son"
    ref = ref.trim() || "John 3:16"
    const short = text.length > 64 ? `${text.slice(0, 62).replace(/\s+\S*$/, "")}…` : text
    this.gridTarget?.querySelectorAll(".ps-look-tile").forEach((t) => {
      t.querySelector(".lt-text").textContent = short
      t.querySelector(".lt-ref").textContent = ref
    })
    if (this.hasPreviewTarget) {
      this.previewTarget.querySelector(".lp-text").textContent = text.length > 150 ? `${text.slice(0, 148).replace(/\s+\S*$/, "")}…` : text
      this.previewTarget.querySelector(".lp-ref").textContent = ref
    }
    this._syncPanel()
  }

  _paintPreviewMedia(bg, url) {
    if (this.isOutput || !this.hasPreviewTarget) return
    const holder = this.previewTarget.querySelector(".lp-bg")
    if (!holder) return
    holder.replaceChildren()
    if (!url) return
    const el = make(bg === "video" ? "video" : "img", "media", null, { src: url })
    if (bg === "video") Object.assign(el, { muted: true, loop: true, autoplay: true, playsInline: true })
    holder.append(el)
  }

  async _checkMedia(slot) {
    if (await mediaUrl(slot)) { this._note(null); return }
    this._note(slot === "video"
      ? "Choose a video below — it stays on this computer and plays muted on a loop."
      : "Choose a picture below — it stays on this computer, so it works offline.")
  }

  _note(text, error = false) {
    if (!this.hasNoteTarget) return
    this.noteTarget.textContent = text || ""
    this.noteTarget.classList.toggle("is-error", !!error)
  }

  // ---- sync between windows -----------------------------------------------------

  _onMessage(msg) {
    if (!msg?.type) return
    if (this.isOutput) {
      if (msg.type === "look") {
        this.prefs = normalizePrefs(msg.prefs)
        this._apply()
      } else if (msg.type === "media") {
        this._paintBackground()
        this._paintLogo()
      } else if (msg.type === "brand") {
        this.brand = msg.brand || {}
        this._paintLogo()
      }
    } else if (msg.type === "hello") {
      this._send({ type: "look", prefs: this.prefs })
      this._send({ type: "brand", brand: this.brand })
    }
  }

  _send(msg) {
    try { this.channel?.postMessage(msg) } catch { /* closed */ }
  }

  _storage() {
    try { return window.localStorage } catch { return null }
  }

  _loadBrand() {
    try { return JSON.parse(localStorage.getItem(BRAND_KEY) || "{}") || {} } catch { return {} }
  }
}

function make(tag, className, text, attrs = {}) {
  const el = document.createElement(tag)
  if (className) el.className = className
  if (text != null) el.textContent = text
  Object.entries(attrs).forEach(([ k, v ]) => { el[k] = v })
  return el
}
