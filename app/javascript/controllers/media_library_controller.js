import { Controller } from "@hotwired/stimulus"
import { saveMedia, mediaOnDevice } from "../lib/offline/media"

// The My Media page (/media). Cards are server-rendered (media_assets/_asset)
// and changed through Turbo Streams; this controller adds what needs the
// browser:
//   upload      several pictures at once, one request each with a progress row
//               (the response is a Turbo Stream that adds the card); size and
//               type are checked here first so a wrong file never travels
//   filter      search by title, on the device
//   thumbnails  a thumbnail that can't be made (or isn't saved offline) falls
//               back to the picture itself
//   offline     "Save all on this device" — the pictures go into the service
//               worker's ps-media cache (lib/offline/media.js); each card says
//               "On this device"
const MAX_BYTES = 5 * 1024 * 1024
const PARALLEL = 1 // one at a time: kinder to a church connection, and the same file twice in one batch is found, not raced

export default class extends Controller {
  static targets = [ "file", "uploads", "status", "grid", "card", "search", "nomatch", "device", "offlineButton", "offlineLabel" ]

  connect() {
    this._supported = typeof window.caches !== "undefined"
    this._refreshDevice()
  }

  cardTargetConnected(card) {
    const zoom = Number(card.dataset.zoom) || 100
    card.querySelector(".mm-thumb")?.style.setProperty("--pic-zoom", String(zoom / 100))
    clearTimeout(this._deviceTimer)
    this._deviceTimer = setTimeout(() => this._refreshDevice(), 50)
    if (this.hasSearchTarget && this.searchTarget.value) this.filter()
  }

  cardTargetDisconnected() {
    clearTimeout(this._deviceTimer)
    this._deviceTimer = setTimeout(() => this._refreshDevice(), 50)
  }

  // ---- upload --------------------------------------------------------------------

  async upload() {
    const files = [ ...(this.fileTarget.files || []) ]
    this.fileTarget.value = ""
    if (!files.length) return
    this._status("")
    const queue = files.map((file) => ({ file, row: this._row(file) }))
    const work = async () => {
      for (let job = queue.shift(); job; job = queue.shift()) await this._send(job)
    }
    await Promise.all(Array.from({ length: Math.min(PARALLEL, files.length) }, work))
    const failed = this.uploadsTarget.querySelectorAll(".is-error").length
    if (!failed) setTimeout(() => this.uploadsTarget.replaceChildren(), 4000)
  }

  _row(file) {
    const li = el("li", "mm-up")
    li.append(el("span", "nm", file.name), el("span", "st", "Waiting…"))
    const bar = el("progress", "ui-offline-bar")
    bar.max = 100
    bar.value = 0
    li.append(bar)
    this.uploadsTarget.append(li)
    return li
  }

  _set(row, state, text, fraction) {
    row.className = `mm-up is-${state}`
    row.querySelector(".st").textContent = text
    const bar = row.querySelector("progress")
    if (fraction != null) bar.value = Math.round(fraction * 100)
    bar.hidden = state !== "busy"
  }

  async _send({ file, row }) {
    if (!file.type.startsWith("image/")) return this._set(row, "error", "Not a picture — JPG, PNG or WebP please")
    if (file.size > MAX_BYTES) return this._set(row, "error", "Over 5 MB — export it smaller and try again")
    if (navigator.onLine === false) return this._set(row, "error", "You're offline — upload once you're connected")
    this._set(row, "busy", "Uploading…", 0)
    const size = await pictureSize(file)
    const form = new FormData()
    form.append("file", file)
    if (size) { form.append("width", size.width); form.append("height", size.height) }
    const result = await post("/media", form, (f) => this._set(row, "busy", `Uploading… ${Math.round(f * 100)}%`, f))
    if (result.ok) {
      window.Turbo?.renderStreamMessage(result.body)
      this._set(row, "ok", result.created ? "Added ✓" : "Already in My Media — kept once ✓")
    } else {
      this._set(row, "error", result.error || "Couldn't upload it — try again")
    }
  }

  // ---- search ---------------------------------------------------------------------

  filter() {
    const q = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    let shown = 0
    this.cardTargets.forEach((card) => {
      const hit = !q || (card.dataset.title || "").includes(q)
      card.hidden = !hit
      if (hit) shown++
    })
    if (this.hasNomatchTarget) this.nomatchTarget.hidden = !q || shown > 0 || !this.cardTargets.length
  }

  zoomLabel(event) {
    const out = event.target.closest("label")?.querySelector("output")
    if (out) out.textContent = `${event.target.value}%`
  }

  thumbFailed(event) {
    const img = event.target
    if (img.dataset.full && img.getAttribute("src") !== img.dataset.full) img.src = img.dataset.full
  }

  // ---- offline -----------------------------------------------------------------------

  async saveOffline(event) {
    event?.preventDefault?.()
    if (this._saving) return
    if (navigator.onLine === false) { this._status("You're offline — connect to save pictures on this device."); return }
    this._saving = true
    this.offlineButtonTarget.disabled = true
    try {
      const result = await saveMedia(this._urls(), {
        onProgress: ({ done, total }) => { this.offlineLabelTarget.textContent = `Saving ${done} of ${total}…` }
      })
      if (result.unsupported) this._status("This browser can't keep pictures offline — use Chrome, Edge or the app.")
      else if (result.failed) this._status(`Saved ${result.saved} of ${result.total} — ${result.failed} couldn't be saved, try again.`)
      else this._status(`All ${result.total} pictures are on this device — they show with no internet.`)
    } finally {
      this._saving = false
      this.offlineButtonTarget.disabled = false
      await this._refreshDevice()
    }
  }

  _urls() {
    return this.cardTargets.map((c) => c.dataset.url).filter(Boolean)
  }

  async _refreshDevice() {
    if (!this._supported || !this.hasOfflineButtonTarget) return
    const urls = this._urls()
    const saved = await mediaOnDevice(urls)
    this.cardTargets.forEach((card) => {
      const mark = card.querySelector("[data-ondevice]")
      if (mark) mark.hidden = !saved.has(card.dataset.url)
    })
    const total = new Set(urls).size
    this.offlineButtonTarget.hidden = total === 0
    if (this._saving) return
    this.offlineLabelTarget.textContent = saved.size >= total ? "All saved on this device ✓" : "Save all on this device"
    if (this.hasDeviceTarget) this.deviceTarget.textContent = total ? `${saved.size} of ${total} on this device` : ""
  }

  _status(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text || ""
  }
}

// The picture's size in pixels (shown in the library; the server keeps it).
async function pictureSize(file) {
  try {
    const bitmap = await createImageBitmap(file)
    const size = { width: bitmap.width, height: bitmap.height }
    bitmap.close?.()
    return size
  } catch { return null }
}

// POST with upload progress (fetch can't report it). Resolves
// { ok, body, created, error }.
function post(url, form, onProgress) {
  return new Promise((resolve) => {
    const xhr = new XMLHttpRequest()
    xhr.open("POST", url)
    xhr.setRequestHeader("Accept", "text/vnd.turbo-stream.html")
    xhr.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name='csrf-token']")?.content || "")
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) onProgress?.(e.loaded / e.total) }
    xhr.onload = () => {
      const ok = xhr.status >= 200 && xhr.status < 300
      resolve({ ok, body: xhr.responseText, created: xhr.getResponseHeader("X-Media-Created") === "1", error: ok ? null : streamText(xhr.responseText, xhr.status) })
    }
    xhr.onerror = () => resolve({ ok: false, error: "No connection — try again" })
    xhr.send(form)
  })
}

function streamText(html, status) {
  if (status === 401) return "Sign in again to upload"
  if (status === 413) return "That picture is too large"
  try {
    const tpl = new DOMParser().parseFromString(html, "text/html").querySelector("template")
    return tpl?.content.textContent.trim() || null
  } catch { return null }
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
