import { Controller } from "@hotwired/stimulus"
import { paintRichSlide } from "../lib/slides/rich_slides"

// The console's PREVIEW miniature: a 16:9 picture of what Go live will put on
// the big screen, drawn in the projection's own type (console.css .cx-mini).
// Lives on the Preview region of _console, operator window only.
//
// It only draws: the preview controller decides what is in Preview and fills
// its slide list (.ps-preview-text); this paints the first slide of it (the
// verses Go live lands on, as many as "verses per slide"), or the slide under
// the pointer while the operator looks down the list. A scripture set,
// presentation or seminar deck is drawn by lib/slides' own painter, the one
// the projector uses.
const MIN_PX = 7

export default class extends Controller {
  static targets = [ "screen", "words", "ref", "title", "empty" ]

  connect() {
    this.root = this.element.closest(".ps-root")
    if (!this.root || this.root.classList.contains("is-output")) return
    this._list = this.root.querySelector(".ps-preview-text")
    this._label = this.root.querySelector(".ps-console-preview [data-preview-target='previewLabel']")
    this._card = this.root.querySelector(".ps-console-preview")
    if (!this._list) return
    this._observer = new MutationObserver(() => this._schedule())
    this._observer.observe(this._list, { childList: true, subtree: true, characterData: true })
    this._onOver = (e) => {
      const slide = e.target.closest?.(".slide")
      if (slide && slide !== this._hover) { this._hover = slide; this._paint() }
    }
    this._onLeave = () => { if (this._hover) { this._hover = null; this._paint() } }
    this._list.addEventListener("mouseover", this._onOver)
    this._list.addEventListener("mouseleave", this._onLeave)
    this._listeners = {
      "preview:changed": (e) => { this._rich = e.detail?.rich || null; this._hover = null; this._schedule() },
      "console:on": () => this._schedule(),
      resize: () => this._schedule()
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    this._groups = new MutationObserver(() => this._schedule())
    this.root.querySelectorAll("[data-preach-group]").forEach((b) => this._groups.observe(b, { attributes: true, attributeFilter: [ "class" ] }))
    this._paint()
  }

  disconnect() {
    this._observer?.disconnect()
    this._groups?.disconnect()
    this._list?.removeEventListener("mouseover", this._onOver)
    this._list?.removeEventListener("mouseleave", this._onLeave)
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
  }

  _schedule() {
    cancelAnimationFrame(this._frame)
    this._frame = requestAnimationFrame(() => this._paint())
  }

  _paint() {
    if (!this.hasScreenTarget) return
    const state = this._card?.dataset.state || "empty"
    const label = this._label?.textContent?.trim() || ""
    const screen = this.screenTarget
    screen.dataset.kind = "empty"
    this.wordsTarget.replaceChildren()
    this.refTarget.textContent = ""
    this.titleTarget.textContent = ""
    screen.querySelector(".cx-mini-img, .cx-mini-rich")?.remove()
    this.emptyTarget.hidden = state !== "empty" && state !== "error"
    if (state === "error") { this.emptyTarget.textContent = label; return }
    if (state === "empty") return

    const slides = Array.from(this._list.querySelectorAll(".slide"))
    if (this._rich) {
      screen.dataset.kind = "rich"
      const layer = document.createElement("div")
      layer.className = "cx-mini-rich"
      screen.append(layer)
      const index = this._hover && slides.includes(this._hover) ? Number(this._hover.dataset.index) || 0 : 0
      const fit = paintRichSlide(layer, this._rich, index)
      if (fit) this._fitBox(layer, fit)
      return
    }
    const img = this._list.querySelector("img.thumb")
    const stanza = this._list.querySelector(".stanza")
    const verses = Array.from(this._list.querySelectorAll(".v"))
    if (img) {
      screen.dataset.kind = "picture"
      const pic = document.createElement("img")
      pic.className = "cx-mini-img"
      pic.src = img.src
      pic.alt = ""
      screen.append(pic)
    } else if (slides.length || stanza) {
      screen.dataset.kind = "slide"
      const pick = this._hover && slides.includes(this._hover) ? this._hover : slides[0]
      this.titleTarget.textContent = label
      this.wordsTarget.textContent = pick ? pick.querySelector(".txt")?.textContent || "" : stanza.textContent
    } else if (verses.length) {
      screen.dataset.kind = "scripture"
      const group = Number(this.root.querySelector("[data-preach-group].is-on")?.dataset.preachGroup || 1)
      verses.slice(0, group).forEach((v) => {
        const line = document.createElement("span")
        line.className = "cx-mini-verse"
        const num = v.querySelector("sup")?.textContent || ""
        const sup = document.createElement("span")
        sup.className = "cx-mini-vnum"
        sup.textContent = num
        line.append(sup, document.createTextNode(v.textContent.replace(num, "").trim()))
        this.wordsTarget.append(line)
      })
      this.refTarget.textContent = this._refFor(label, verses.slice(0, group))
    } else {
      // The words are still loading, or this Bible isn't on the device.
      screen.dataset.kind = "pending"
      this.titleTarget.textContent = label
      this.wordsTarget.textContent = this._list.textContent.trim()
    }
    this._fit()
  }

  _refFor(label, shown) {
    const nums = shown.map((v) => v.querySelector("sup")?.textContent).filter(Boolean)
    const chapter = label.replace(/\s*:\s*\d.*$/, "")
    if (!nums.length || chapter === label && !/\d/.test(label)) return label
    return `${chapter}:${nums[0]}${nums.length > 1 ? `–${nums[nums.length - 1]}` : ""}`
  }

  // As big as the miniature allows, the way the projector fills its screen.
  _fit() {
    if (!this.wordsTarget.textContent) return
    this._fitBox(this.wordsTarget, this.wordsTarget, this.screenTarget.dataset.kind === "scripture" ? 0.06 : 0.05)
  }

  _fitBox(box, target, ratio = 0.05) {
    let size = Math.max(MIN_PX, this.screenTarget.clientWidth * ratio)
    const over = () => box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1
    target.style.fontSize = `${size}px`
    for (let i = 0; i < 30 && size > MIN_PX && over(); i++) {
      size *= 0.92
      target.style.fontSize = `${size}px`
    }
  }
}
