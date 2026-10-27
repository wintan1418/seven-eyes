import { Controller } from "@hotwired/stimulus"

// The translation sheet: a list of the versions we offer, the pane's current
// one ticked. Choosing one sets that pane's (visually hidden) translation
// select and submits the pane form — the same path the old dropdown took.
export default class extends Controller {
  static targets = ["option"]

  // sheet:opened → tick the translation the pane is showing.
  sync(event) {
    this.paneId = event?.detail?.paneId || this.element.dataset.paneId ||
      document.querySelector(".ps-workspace .ps-pane")?.id?.replace("pane_", "")
    const current = this._select()?.value
    this.optionTargets.forEach(o => o.setAttribute("aria-checked", String(o.dataset.translationId === current)))
  }

  choose(event) {
    const select = this._select()
    const id = event.currentTarget.dataset.translationId
    window.dispatchEvent(new CustomEvent("sheet:close", { detail: { id: "translation" } }))
    if (!select?.form || select.value === id) return
    select.value = id
    select.form.requestSubmit()
  }

  _select() {
    return document.getElementById(`pane_${this.paneId}`)?.querySelector("select[name='pane[translation_id]']")
  }
}
