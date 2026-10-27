import { Controller } from "@hotwired/stimulus"

// Opens/closes the word-study slide-over. A tagged word is a plain span (a
// real <a> would pop the mobile long-press link menu and block text selection);
// its data-href is loaded into the lexicon_drawer frame here.
//
// Touch vs mouse is decided per tap (pointerType), not by sniffing the device,
// so a touchscreen laptop used with a trackpad still opens word study on
// click. Touch users reach it from the selection bar's "Word study" entry,
// which dispatches a window `lexicon:open` event.
export default class extends Controller {
  static targets = ["host"]

  connect() {
    this.pointerType = "mouse"
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    this._onPointer = (e) => { if (e.pointerType) this.pointerType = e.pointerType }
    this._onOpen = (e) => this.load(e.detail?.href)
    document.addEventListener("pointerdown", this._onPointer, true)
    window.addEventListener("lexicon:open", this._onOpen)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this._onPointer, true)
    window.removeEventListener("lexicon:open", this._onOpen)
    document.removeEventListener("keydown", this._onKey)
  }

  open(event) {
    // A tap on touch is for reading and selecting/copying, not opening the
    // root-word drawer. Keyboard (Enter) and mouse clicks open it.
    const pointer = event?.pointerType || (event?.type === "click" ? this.pointerType : "")
    if (pointer === "touch" || pointer === "pen") { event?.preventDefault?.(); return }
    // A highlighted word's click belongs to the highlight's note editor.
    if (event?.target?.closest?.("[data-highlight-id]")) return
    this.load(event?.currentTarget?.dataset?.href)
  }

  load(url) {
    if (url) {
      const frame = document.getElementById("lexicon_drawer")
      if (frame) frame.src = url
    }
    this.hostTarget.classList.add("is-open")
    document.addEventListener("keydown", this._onKey)
  }

  close() {
    this.hostTarget.classList.remove("is-open")
    document.removeEventListener("keydown", this._onKey)
  }
}
