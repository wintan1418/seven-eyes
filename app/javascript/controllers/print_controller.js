import { Controller } from "@hotwired/stimulus"

// Opens the browser print dialog (sermon "Print / Save PDF").
export default class extends Controller {
  print() { window.print() }
}
