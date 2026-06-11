import { Controller } from "@hotwired/stimulus"

// The preach queue ("setlist") drawer. Lives on .ps-root.
//
// Opening/closing toggles .is-open on the host; the list itself is a Turbo
// Frame, so add/move/delete re-render server-side. Clicking an item's label
// hands it to the presentation controller via a window event:
//   setlist:present {kind: "scripture", reference} — chase the reference
//   setlist:present {kind: "slide", title, body}   — project a song/thought
export default class extends Controller {
  static targets = ["host", "form"]

  open(event) {
    event?.preventDefault?.()
    if (this.hasHostTarget) this.hostTarget.classList.add("is-open")
  }

  close(event) {
    event?.preventDefault?.()
    if (this.hasHostTarget) this.hostTarget.classList.remove("is-open")
  }

  toggle(event) {
    event?.preventDefault?.()
    if (!this.hasHostTarget) return
    this.hostTarget.classList.toggle("is-open")
  }

  // Radio change on the add form: show only the fields the kind needs.
  kindChanged(event) {
    const form = event.target.closest(".ps-setlist-form")
    if (!form) return
    form.classList.remove("kind-scripture", "kind-song", "kind-thought")
    form.classList.add(`kind-${event.target.value}`)
    form.querySelectorAll(".kinds label").forEach(l => {
      l.classList.toggle("is-on", l.contains(event.target))
    })
  }

  present(event) {
    event?.preventDefault?.()
    const item = event.target.closest(".ps-setlist-item")
    if (!item) return
    const detail = {
      kind: item.dataset.kind,
      reference: item.dataset.reference || null,
      title: item.dataset.title || null,
      body: item.dataset.body || null
    }
    this.element.querySelectorAll(".ps-setlist-item.is-live").forEach(i => i.classList.remove("is-live"))
    item.classList.add("is-live")
    window.dispatchEvent(new CustomEvent("setlist:present", { detail }))
    // Mid-service the drawer covers the console — get out of the way.
    if (this.element.classList.contains("is-preaching")) this.close()
  }
}
