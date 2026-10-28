import { Controller } from "@hotwired/stimulus"

// Turns clicks on sheet buttons into a window `sheet:open` event, so a button
// anywhere on the page can open a sheet rendered anywhere else:
//   <button data-action="sheets#open" data-sheets-id-param="passage"
//           data-sheets-pane-param="123">
// Lives on <body>.
export default class extends Controller {
  open(event) {
    event.preventDefault()
    const { id, pane } = event.params
    window.dispatchEvent(new CustomEvent("sheet:open", {
      detail: { id, paneId: pane ? String(pane) : null, trigger: event.currentTarget }
    }))
  }

  close(event) {
    event?.preventDefault?.()
    window.dispatchEvent(new CustomEvent("sheet:close", { detail: { id: event?.params?.id } }))
  }
}
