import { Controller } from "@hotwired/stimulus"

// Shows what CSS keeps folded on small screens: adds a class to the element
// (e.g. the home page's study list shows three on phones until "Show all").
export default class extends Controller {
  show(event) {
    this.element.classList.add(this.element.dataset.revealClass || "is-expanded")
    event?.currentTarget?.remove()
  }
}
