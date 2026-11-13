import { Controller } from "@hotwired/stimulus"

// Glossary of the Faith (/faith): filter the A–Z list as you type. Each item
// carries its lower-case search words (name, aliases, definition) in
// data-search; a letter group, and its jump link, hide when nothing in it
// matches.
export default class extends Controller {
  static targets = ["input", "item", "group", "jump", "empty"]

  filter() {
    const words = this.inputTarget.value.toLowerCase().trim().split(/\s+/).filter(Boolean)
    const shown = new Set()
    let any = false

    this.groupTargets.forEach((group) => {
      let groupHas = false
      group.querySelectorAll("[data-glossary-filter-target~='item']").forEach((item) => {
        const text = item.dataset.search || ""
        const match = words.every((word) => text.includes(word))
        item.hidden = !match
        if (match) groupHas = true
      })
      group.hidden = !groupHas
      if (groupHas) shown.add(group.dataset.letter)
      any ||= groupHas
    })

    this.jumpTargets.forEach((jump) => { jump.hidden = !shown.has(jump.dataset.letter) })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = any
  }
}
