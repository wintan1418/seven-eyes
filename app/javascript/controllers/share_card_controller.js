import { Controller } from "@hotwired/stimulus"

// Share-as-image: draws a passage (or an AI chapter prayer) onto a canvas in
// the app's manuscript aesthetic, then lets the user Share (Web Share API),
// Download, or Copy the image — plus copy a public link/text that brings people
// to the /p/:slug page. Pure DOM + canvas, no library.
//
// Opened via window events:
//   share:open  { verseId?, osis?, chapter?, verseStart?, verseEnd?, q? }
//   prayer:open { osis, chapter }

const W = 1080
const H = 1080
const MARGIN = 96

const BGS = {
  vellum: { base: ["#f4e7c8", "#e6d2a2"], frame: "#b9912f", ref: "#8a2418", body: "#2b2017", sub: "#7a5e22", fiber: true },
  sepia:  { base: ["#e8d4a6", "#c8a86a"], frame: "#7a5a1f", ref: "#5e1a12", body: "#3a2a17", sub: "#6b4f1c" },
  candle: { base: ["#2a1c0d", "#120c06"], frame: "#caa24a", ref: "#e7c06a", body: "#f1e4c8", sub: "#caa24a" },
  ink:    { base: ["#1b2330", "#0d131c"], frame: "#c7a14a", ref: "#d9b15f", body: "#eef1f5", sub: "#a3b3c6" },
  cream:  { base: ["#fbf5e6", "#f2e8cf"], frame: "#caa24a", ref: "#8a2418", body: "#2b2017", sub: "#8a7038" }
}

export default class extends Controller {
  static targets = [
    "host", "canvas", "status", "bgs", "link",
    "modePassage", "modePrayer", "shareBtn", "copyImage", "copyLink", "copyText", "note"
  ]
  static values = { cardUrl: String, prayerUrl: String }

  connect() {
    this.bg = "vellum"
    this.mode = "passage"
    this.card = null       // { reference, translation, text, slug, url, osis, chapter }
    this.prayer = null     // { reference, prayer, url }
    this._onShare = (e) => this.openPassage(e.detail || {})
    this._onPrayer = (e) => this.openPrayer(e.detail || {})
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    window.addEventListener("share:open", this._onShare)
    window.addEventListener("prayer:open", this._onPrayer)
    this._fontsReady = this.loadFonts()
  }

  disconnect() {
    window.removeEventListener("share:open", this._onShare)
    window.removeEventListener("prayer:open", this._onPrayer)
    document.removeEventListener("keydown", this._onKey)
  }

  loadFonts() {
    if (!document.fonts || !document.fonts.load) return Promise.resolve()
    return Promise.all([
      document.fonts.load("600 48px Cinzel"),
      document.fonts.load("italic 48px 'EB Garamond'"),
      document.fonts.load("500 48px 'EB Garamond'")
    ]).catch(() => {})
  }

  // ---------------- open / close ----------------

  async openPassage(detail) {
    this.open()
    this.mode = "passage"
    this.syncModeButtons()
    this.setStatus("Preparing…")
    const data = await this.fetchCard(detail)
    if (!data) return this.setStatus("Could not load that passage.")
    this.card = data
    this.prayerCtx = { osis: data.osis, chapter: data.chapter }
    this.prayer = null
    await this.render()
  }

  async openPrayer(detail) {
    this.open()
    this.prayerCtx = { osis: detail.osis, chapter: detail.chapter }
    await this.showPrayer()
  }

  open() {
    this.element.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    this.element.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }

  // ---------------- mode switch ----------------

  async showPassage() {
    if (!this.card) return
    this.mode = "passage"
    this.syncModeButtons()
    await this.render()
  }

  async showPrayer() {
    this.mode = "prayer"
    this.syncModeButtons()
    if (!this.prayerCtx?.osis) return this.setStatus("Open a chapter to compose a prayer.")
    if (!this.prayer) {
      this.setStatus("Composing a prayer from the chapter…")
      const data = await this.fetchPrayer(this.prayerCtx)
      if (!data || !data.ok) {
        return this.setStatus(this.prayerError(data))
      }
      this.prayer = data
    }
    await this.render()
  }

  prayerError(data) {
    if (data && data.error === "no_key") return "The prayer needs an AI key configured on the server."
    return "A prayer couldn't be composed right now. Please try again."
  }

  syncModeButtons() {
    this.modePassageTarget.classList.toggle("is-on", this.mode === "passage")
    this.modePrayerTarget.classList.toggle("is-on", this.mode === "prayer")
  }

  // ---------------- data ----------------

  async fetchCard(detail) {
    const q = new URLSearchParams()
    if (detail.verseId) q.set("verse_id", detail.verseId)
    if (detail.osis) q.set("osis", detail.osis)
    if (detail.chapter) q.set("chapter", detail.chapter)
    if (detail.verseStart) q.set("verse_start", detail.verseStart)
    if (detail.verseEnd) q.set("verse_end", detail.verseEnd)
    if (detail.q) q.set("q", detail.q)
    try {
      const res = await fetch(`${this.cardUrlValue}?${q}`, { headers: { Accept: "application/json" } })
      if (!res.ok) return null
      return await res.json()
    } catch { return null }
  }

  async fetchPrayer(ctx) {
    const q = new URLSearchParams({ osis: ctx.osis, chapter: ctx.chapter })
    try {
      const res = await fetch(`${this.prayerUrlValue}?${q}`, { headers: { Accept: "application/json" } })
      if (!res.ok) return null
      return await res.json()
    } catch { return null }
  }

  // ---------------- rendering ----------------

  pickBg(event) {
    this.bg = event.currentTarget.dataset.bg
    this.bgsTarget.querySelectorAll(".ps-share-bg").forEach((b) =>
      b.classList.toggle("is-on", b === event.currentTarget))
    this.render()
  }

  async render() {
    await this._fontsReady
    this.hideStatus()
    const data = this.mode === "prayer" ? this.prayer : this.card
    if (!data) return
    this.linkTarget.value = data.url || ""

    const ctx = this.canvasTarget.getContext("2d")
    const c = BGS[this.bg] || BGS.vellum
    this.paintBackground(ctx, c)
    this.paintFrame(ctx, c)
    this.paintOrnament(ctx, c, MARGIN + 24)

    if (this.mode === "prayer") {
      this.paintPrayer(ctx, c, data)
    } else {
      this.paintPassage(ctx, c, data)
    }
    this.paintFooter(ctx, c, data.url)
  }

  paintBackground(ctx, c) {
    const g = ctx.createLinearGradient(0, 0, W, H)
    g.addColorStop(0, c.base[0])
    g.addColorStop(1, c.base[1])
    ctx.fillStyle = g
    ctx.fillRect(0, 0, W, H)
    if (c.fiber) {
      ctx.strokeStyle = "rgba(120, 90, 40, 0.05)"
      ctx.lineWidth = 1
      for (let y = 0; y < H; y += 9) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y + 3); ctx.stroke()
      }
    }
  }

  paintFrame(ctx, c) {
    ctx.strokeStyle = c.frame
    ctx.lineWidth = 3
    ctx.strokeRect(MARGIN - 30, MARGIN - 30, W - (MARGIN - 30) * 2, H - (MARGIN - 30) * 2)
    ctx.globalAlpha = 0.5
    ctx.lineWidth = 1
    ctx.strokeRect(MARGIN - 22, MARGIN - 22, W - (MARGIN - 22) * 2, H - (MARGIN - 22) * 2)
    ctx.globalAlpha = 1
  }

  paintOrnament(ctx, c, y) {
    ctx.fillStyle = c.sub
    ctx.font = "44px 'EB Garamond', serif"
    ctx.textAlign = "center"
    ctx.fillText("❦", W / 2, y + 30)
  }

  paintPassage(ctx, c, data) {
    this.paintTrackedRef(ctx, c, (data.reference || "").toUpperCase(), MARGIN + 96)

    const maxW = W - MARGIN * 2 - 40
    const bandTop = MARGIN + 150
    const bandBottom = H - MARGIN - 120
    let size = 64
    let lines = []
    while (size >= 30) {
      ctx.font = `italic ${size}px 'EB Garamond', serif`
      lines = this.wrap(ctx, this.quote(data.text), maxW)
      if (lines.length * size * 1.36 <= bandBottom - bandTop) break
      size -= 2
    }
    ctx.fillStyle = c.body
    ctx.textAlign = "center"
    const lh = size * 1.36
    let y = bandTop + (bandBottom - bandTop - lines.length * lh) / 2 + size
    lines.forEach((ln) => { ctx.fillText(ln, W / 2, y); y += lh })

    this.paintRefTag(ctx, c, data.reference, data.translation, bandBottom + 24)
  }

  paintPrayer(ctx, c, data) {
    this.paintTrackedRef(ctx, c, "A PRAYER", MARGIN + 88)

    const maxW = W - MARGIN * 2 - 30
    const bandTop = MARGIN + 140
    const bandBottom = H - MARGIN - 120
    let size = 50
    let lines = []
    while (size >= 26) {
      ctx.font = `${size}px 'EB Garamond', serif`
      lines = this.wrap(ctx, data.prayer, maxW)
      if (lines.length * size * 1.42 <= bandBottom - bandTop) break
      size -= 2
    }
    ctx.fillStyle = c.body
    ctx.textAlign = "center"
    const lh = size * 1.42
    let y = bandTop + (bandBottom - bandTop - lines.length * lh) / 2 + size
    lines.forEach((ln) => { ctx.fillText(ln, W / 2, y); y += lh })

    this.paintRefTag(ctx, c, data.reference, null, bandBottom + 24)
  }

  // reference rendered with manual letter-spacing (canvas has none natively)
  paintTrackedRef(ctx, c, text, y) {
    ctx.font = "600 34px Cinzel, serif"
    ctx.fillStyle = c.ref
    const tracking = 6
    const widths = [...text].map((ch) => ctx.measureText(ch).width + tracking)
    const total = widths.reduce((a, b) => a + b, 0) - tracking
    let x = (W - total) / 2
    ctx.textAlign = "left"
    ;[...text].forEach((ch, i) => { ctx.fillText(ch, x, y); x += widths[i] })
    ctx.textAlign = "center"
  }

  paintRefTag(ctx, c, reference, translation, y) {
    ctx.fillStyle = c.sub
    ctx.font = "500 30px 'EB Garamond', serif"
    ctx.textAlign = "center"
    const label = translation ? `${reference} · ${translation}` : reference
    ctx.fillText(label, W / 2, y)
  }

  paintFooter(ctx, c, url) {
    ctx.fillStyle = c.sub
    ctx.font = "600 22px Cinzel, serif"
    ctx.textAlign = "center"
    let host = "parallel scripture"
    try { host = new URL(url).host } catch { /* keep default */ }
    ctx.fillText(host.toUpperCase(), W / 2, H - MARGIN - 36)
  }

  quote(text) {
    const t = (text || "").trim()
    return `“${t}”`
  }

  wrap(ctx, text, maxW) {
    const words = (text || "").split(/\s+/)
    const lines = []
    let line = ""
    for (const w of words) {
      const test = line ? `${line} ${w}` : w
      if (ctx.measureText(test).width > maxW && line) {
        lines.push(line); line = w
      } else {
        line = test
      }
    }
    if (line) lines.push(line)
    return lines
  }

  // ---------------- actions ----------------

  toBlob() {
    return new Promise((resolve) => this.canvasTarget.toBlob(resolve, "image/png"))
  }

  filename() {
    const data = this.mode === "prayer" ? this.prayer : this.card
    const base = (data?.slug || data?.reference || "passage").toString()
      .toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "")
    return `${this.mode === "prayer" ? "prayer-" : ""}${base || "passage"}.png`
  }

  async download() {
    const blob = await this.toBlob()
    if (!blob) return
    const a = document.createElement("a")
    a.href = URL.createObjectURL(blob)
    a.download = this.filename()
    a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 4000)
  }

  async share() {
    const blob = await this.toBlob()
    const data = this.mode === "prayer" ? this.prayer : this.card
    if (blob && navigator.canShare) {
      const file = new File([blob], this.filename(), { type: "image/png" })
      if (navigator.canShare({ files: [file] })) {
        try {
          await navigator.share({ files: [file], title: data?.reference || "Parallel Scripture", text: data?.url })
          return
        } catch { /* cancelled — fall through */ return }
      }
    }
    this.download() // graceful fallback on desktop
  }

  async copyImage() {
    try {
      const blob = await this.toBlob()
      await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })])
      this.flash(this.copyImageTarget, "Copied!")
    } catch {
      this.flash(this.copyImageTarget, "Use Download")
    }
  }

  async copyLink() {
    try {
      await navigator.clipboard.writeText(this.linkTarget.value)
      this.flash(this.copyLinkTarget, "Copied!")
    } catch { this.linkTarget.select() }
  }

  async copyText() {
    const data = this.mode === "prayer" ? this.prayer : this.card
    const body = this.mode === "prayer" ? data?.prayer : this.quote(data?.text)
    const text = `${body}\n\n${data?.reference || ""}\n${data?.url || ""}`.trim()
    try {
      await navigator.clipboard.writeText(text)
      this.flash(this.copyTextTarget, "Copied!")
    } catch { /* no-op */ }
  }

  flash(btn, msg) {
    const prev = btn.textContent
    btn.textContent = msg
    setTimeout(() => { btn.textContent = prev }, 1400)
  }

  setStatus(msg) {
    this.statusTarget.textContent = msg
    this.statusTarget.hidden = false
  }

  hideStatus() {
    this.statusTarget.hidden = true
  }
}
