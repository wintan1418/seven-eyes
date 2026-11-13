import { Controller } from "@hotwired/stimulus"

// Glossary of the Faith: the two-pane reader. A term chosen in the side pane
// opens in the "ft-content" Turbo Frame, so the side pane (and its scroll)
// stays put. After each frame load this keeps the rest in step: the tab
// title, the side pane's "open term" mark, and the page back at the top.
export default class extends Controller {
  connect() {
    this.mark({ reveal: true })
  }

  loaded(event) {
    if (event.target.id !== "ft-content") return
    const view = event.target.querySelector(".ft-view")
    if (view?.dataset.title) document.title = view.dataset.title
    window.scrollTo({ top: 0 })
    this.mark({ reveal: false })
  }

  // aria-current on the side pane's link to the open term; on first load,
  // scroll the side pane so that term is in view.
  mark({ reveal }) {
    const path = this.element.querySelector("#ft-content .ft-view")?.dataset.path
    let current = null
    this.element.querySelectorAll(".ft-side .ft-item").forEach((link) => {
      const on = link.getAttribute("href") === path
      if (on) { link.setAttribute("aria-current", "page"); current = link } else link.removeAttribute("aria-current")
    })
    if (reveal && current) this.reveal(current)
  }

  reveal(link) {
    const list = link.closest(".ft-side-list")
    if (!list || list.scrollHeight <= list.clientHeight) return
    list.scrollTop = link.offsetTop - list.clientHeight / 3 // .ft-side-list is position: relative
  }
}
