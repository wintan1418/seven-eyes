import { Controller } from "@hotwired/stimulus"

// Dropdown that holds the workspace's "view" preferences — font size, theme,
// diff, interlinear, sync. The panel is position:fixed; .ps-topbar is bumped
// to z-index:10 in CSS so its descendants (this panel) can paint over .ps-shell
// (which is also a z-index:1 stacking context via the .ps-root > * rule).
// On open we measure the trigger rect and pin the panel directly under it,
// clamped to the viewport edge.
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
    this.panelTarget.removeAttribute("hidden")
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
