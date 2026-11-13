import { Controller } from "@hotwired/stimulus"

// Glossary of the Faith (/faith): filter the A–Z list as you type. Each item
// carries its lower-case search words (name, aliases, definition) in
// data-search; a letter group, and its jump link, hide when nothing in it
// matches. A–Z links scroll the list itself (the side pane scrolls on its
// own from 1024px; on a phone the page does).
export default class extends Controller {
  static targets = ["input", "item", "group", "jump", "empty", "list"]

  jump(event) {
    const group = this.groupTargets.find((g) => g.dataset.letter === event.currentTarget.dataset.letter)
    if (!group) return
    event.preventDefault()
    const list = this.hasListTarget ? this.listTarget : null
    if (list && list.scrollHeight > list.clientHeight) {
      list.scrollTo({ top: group.offsetTop, behavior: "smooth" })
    } else {
      group.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }

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
