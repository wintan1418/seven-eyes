import { Controller } from "@hotwired/stimulus"

// "Rewrite with AI" on the glossary review desk (faith_term_reviews/_rewriter).
// Before the rewrite form goes out, copies the edit form's current text into
// it (so "make it shorter" works on unsaved edits); afterwards "Use this" /
// "Use all" copy the AI's suggestion into the edit form. Never saves — the
// reviewer presses Save.
export default class extends Controller {
  static targets = ["current", "use", "status"]

  collect() {
    this.currentTargets.forEach((input) => {
      const field = this.#field(input.dataset.field)
      input.value = field ? field.value : ""
    })
  }

  use(event) {
    const button = event.currentTarget
    if (this.#fill(button)) this.#say("Copied into the form below. Press Save to keep it.")
  }

  useAll() {
    const filled = this.useTargets.filter((button) => this.#fill(button)).length
    if (filled) this.#say("All copied into the form below. Read it through, then press Save to keep it.")
  }

  #fill(button) {
    const field = this.#field(button.dataset.field)
    if (!field) return false
    field.value = button.dataset.value
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.classList.add("fr-filled")
    button.textContent = "Used ✓"
    return true
  }

  #field(name) {
    return document.getElementById(`faith_term_${name}`)
  }

  #say(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
