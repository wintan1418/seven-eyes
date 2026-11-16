import { Controller } from "@hotwired/stimulus"

// A long text shown in a few lines with "Read all" to open it in place —
// readers' testimonies on Home and the landing page. The button only shows
// when the text is actually cut; opening it stops the card slider moving on.
export default class extends Controller {
  static targets = [ "text", "button" ]

  connect() {
    this.measure = () => {
      if (this.element.classList.contains("is-open")) return
      const cut = this.textTarget.scrollHeight > this.textTarget.clientHeight + 2
      this.buttonTarget.hidden = !cut
    }
    this.observer = new ResizeObserver(this.measure)
    this.observer.observe(this.textTarget)
    this.measure()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const open = !this.element.classList.contains("is-open")
    this.element.classList.toggle("is-open", open)
    this.buttonTarget.textContent = open ? "Show less" : "Read all"
    this.buttonTarget.hidden = false
    // Reading: the slider stays on this card.
    this.element.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }))
  }
}
