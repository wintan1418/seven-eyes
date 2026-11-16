import { Controller } from "@hotwired/stimulus"
import { indexScenes, sceneFor, sceneUrl } from "../lib/scripture_scenes"
import SCENES from "../lib/scripture_scenes.json"

// Scene pictures: a faint Doré engraving behind each reading pane showing
// what is happening in the passage — the garden in Genesis 3, Cain and Abel
// in Genesis 4 — changing as you scroll past the verse a plate shows.
// Lives on .ps-root (reader only; hidden while presenting, by CSS). Works the
// same for server- and device-rendered panes (it reads the pane's markup) and
// offline (the list is bundled; the service worker keeps pictures it has
// shown). "Scene pictures" in Aa reading settings turns it off per device.
const KEY = "ps:scenes"
const INDEX = indexScenes(SCENES)
const READING_LINE = 0.3 // the verse at 30% down the pane is "the one being read"

export default class extends Controller {
  static targets = [ "button" ]

  connect() {
    if (this.element.classList.contains("is-output")) return
    let stored = null
    try { stored = localStorage.getItem(KEY) } catch (_) {}
    this._apply(stored !== "0")
    this._refresh = () => this._paintAll()
    this._onScroll = (e) => {
      const box = e.target
      if (!(box instanceof Element) || !box.classList.contains("ps-verses")) return
      if (this._frame) return
      this._frame = requestAnimationFrame(() => { this._frame = null; this._paint(box.closest(".ps-pane")) })
    }
    this.element.addEventListener("turbo:frame-load", this._refresh)
    this.element.addEventListener("scroll", this._onScroll, { capture: true, passive: true })
    // Device-rendered panes (offline) are swapped in without a frame load.
    const workspace = this.element.querySelector(".ps-workspace") || this.element
    this._observer = new MutationObserver(() => { cancelAnimationFrame(this._later); this._later = requestAnimationFrame(this._refresh) })
    this._observer.observe(workspace, { childList: true, subtree: true })
    this._paintAll()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this._refresh)
    this.element.removeEventListener("scroll", this._onScroll, { capture: true })
    this._observer?.disconnect()
    cancelAnimationFrame(this._frame)
    cancelAnimationFrame(this._later)
  }

  toggle(event) {
    event?.preventDefault?.()
    const on = this.element.classList.contains("no-scenes")
    this._apply(on)
    try { localStorage.setItem(KEY, on ? "1" : "0") } catch (_) {}
    if (on) this._paintAll()
  }

  _apply(on) {
    this.element.classList.toggle("no-scenes", !on)
    this.buttonTargets.forEach((b) => b.setAttribute("aria-pressed", String(on)))
  }

  _paintAll() {
    if (this.element.classList.contains("no-scenes")) return
    this.element.querySelectorAll(".ps-workspace .ps-pane").forEach((pane) => this._paint(pane))
  }

  // The pane's passage and the verse being read → its picture.
  _paint(pane) {
    if (!pane || this.element.classList.contains("no-scenes")) return
    const box = pane.querySelector(".ps-verses")
    const head = pane.querySelector("[data-osis][data-chapter]")
    const at = box && this._readingVerse(box)
    const osis = at?.dataset.osis || head?.dataset.osis
    const chapter = Number(at?.dataset.chapter || head?.dataset.chapter) || null
    const verse = at ? Number(at.dataset.verseNum) || null : null
    const scene = osis && chapter ? sceneFor(INDEX, osis, chapter, verse) : null
    this._show(pane, scene)
  }

  _readingVerse(box) {
    const verses = box.querySelectorAll(".ps-verse[data-verse-num]")
    if (!verses.length) return null
    const r = box.getBoundingClientRect()
    const line = r.top + r.height * READING_LINE
    // Binary search: the last verse starting above the reading line.
    let lo = 0, hi = verses.length - 1, found = 0
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      if (verses[mid].getBoundingClientRect().top <= line) { found = mid; lo = mid + 1 } else hi = mid - 1
    }
    return verses[found]
  }

  // Two pictures, crossfaded: the next one fades in once it has loaded.
  _show(pane, scene) {
    let layer = pane.querySelector(":scope > .rd-scene")
    if (!scene) { if (layer) layer.dataset.key = ""; layer?.classList.remove("is-on"); return }
    if (!layer) layer = this._layer(pane)
    if (layer.dataset.key === scene.key) { layer.classList.add("is-on"); return }
    layer.dataset.key = scene.key
    const [ a, b ] = layer.querySelectorAll("img")
    const current = a.classList.contains("is-shown") ? a : b
    const next = current === a ? b : a
    const caption = layer.querySelector(".rd-scene-cap")
    next.onload = () => {
      if (layer.dataset.key !== scene.key) return
      next.classList.add("is-shown")
      current.classList.remove("is-shown")
      layer.classList.add("is-on")
      caption.textContent = `${scene.title} · Gustave Doré`
    }
    next.onerror = () => { if (layer.dataset.key === scene.key) layer.classList.remove("is-on") }
    next.src = sceneUrl(scene)
  }

  _layer(pane) {
    const layer = document.createElement("div")
    layer.className = "rd-scene"
    layer.setAttribute("aria-hidden", "true")
    for (let i = 0; i < 2; i++) {
      const img = document.createElement("img")
      img.className = "rd-scene-img"
      img.alt = ""
      img.decoding = "async"
      layer.append(img)
    }
    const cap = document.createElement("span")
    cap.className = "rd-scene-cap"
    layer.append(cap)
    pane.prepend(layer)
    return layer
  }
}
