import { Controller } from "@hotwired/stimulus"
import { owner } from "../lib/offline/page"
import { stepFor, todayStatus } from "../lib/today_state"

// Home's Continue rail: a Today flow left part-way ("Step 3 of 6") comes
// back first, from this device's copy (lib/today_state.js). Hidden when
// today is done or wasn't started.
export default class extends Controller {
  static targets = [ "meta", "bar" ]

  connect() {
    const status = todayStatus({ owner: owner() })
    const step = stepFor(owner(), status.today)
    const show = !!step && !status.done && step.index > 0
    this.element.hidden = !show
    if (!show) return
    const total = step.total || 6
    this.metaTarget.textContent = `Step ${step.index + 1} of ${total}`
    this.barTarget.max = total
    this.barTarget.value = step.index
  }
}
