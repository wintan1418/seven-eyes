import { Controller } from "@hotwired/stimulus"

// Dropdown that holds the workspace's "view" preferences — font size, theme,
// diff, interlinear, sync. The panel is position:fixed (so .ps-root's
// overflow:hidden doesn't clip it). On open we measure the trigger and pin
// the panel directly under it, clamped to the viewport.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    console.log("[view-menu] connected")
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
    console.log("[view-menu] toggle, hidden was:", this.panelTarget.hidden)
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.panelTarget.removeAttribute("hidden")
    this.element.classList.add("is-open")
    this._position()
    const rect = this.panelTarget.getBoundingClientRect()
    const style = getComputedStyle(this.panelTarget)
    console.log("[view-menu] open — rect:", rect, "position:", style.position, "z-index:", style.zIndex, "display:", style.display)
    setTimeout(() => {
      document.addEventListener("click", this._outside)
      document.addEventListener("keydown", this._esc)
      window.addEventListener("resize", this._reposition)
      window.addEventListener("scroll", this._reposition, true)
    }, 0)
  }

  close() {
    this.panelTarget.hidden = true
    this.panelTarget.setAttribute("hidden", "")
    this.element.classList.remove("is-open")
    document.removeEventListener("click", this._outside)
    document.removeEventListener("keydown", this._esc)
    window.removeEventListener("resize", this._reposition)
    window.removeEventListener("scroll", this._reposition, true)
  }

  _position() {
    const trigger = this.element.getBoundingClientRect()
    const panel = this.panelTarget
    panel.style.top = `${Math.round(trigger.bottom + 6)}px`
    const desiredRight = window.innerWidth - Math.round(trigger.right)
    panel.style.right = `${Math.max(8, desiredRight)}px`
  }
}
