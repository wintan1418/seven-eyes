import { Controller } from "@hotwired/stimulus"

// Submits the controller's form when a watched control changes (e.g. the
// translation dropdown), so the pane's Turbo Frame reloads without a button.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
