import { Controller } from "@hotwired/stimulus"

// Dropdown that holds the workspace's "view" preferences — font size, theme,
// diff, interlinear, sync. The panel is position:fixed (so .ps-root's
// overflow:hidden doesn't clip it). On open we measure the trigger and pin
// the panel directly under it, clamped to the viewport.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this._outside = (e) => { if (!this.element.contains(e.target)) this.close() }
    this._esc = (e) => { if (e.key === "Escape") this.close() }
    this._reposition = () => { if (!this.panelTarget.hidden) this._position() }
  }

  disconnect() {
    document.removeEventListener("click", this._outside)
    document.removeEventListener("keydown", this._esc)
    window.removeEventListener("resize", this._reposition)
    window.removeEventListener("scroll", this._reposition, true)
  }

  toggle(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.element.classList.add("is-open")
    this._position()
    setTimeout(() => {
      document.addEventListener("click", this._outside)
      document.addEventListener("keydown", this._esc)
      window.addEventListener("resize", this._reposition)
      window.addEventListener("scroll", this._reposition, true)
    }, 0)
  }

  close() {
    this.panelTarget.hidden = true
    this.element.classList.remove("is-open")
    document.removeEventListener("click", this._outside)
    document.removeEventListener("keydown", this._esc)
    window.removeEventListener("resize", this._reposition)
    window.removeEventListener("scroll", this._reposition, true)
  }

  _position() {
    const trigger = this.element.getBoundingClientRect()
    const panel = this.panelTarget
    // Reset so we measure natural size after content settles.
    panel.style.top = `${Math.round(trigger.bottom + 6)}px`
    const desiredRight = window.innerWidth - Math.round(trigger.right)
    // Clamp so the panel never escapes the right edge with a tiny margin.
    panel.style.right = `${Math.max(8, desiredRight)}px`
  }
}
