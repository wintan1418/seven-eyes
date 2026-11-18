import { Controller } from "@hotwired/stimulus"

// The Listen sheet's speed and mode choices, remembered on this device. The
// reader controller reads them through listenOptions(); Play asks the pane
// that opened the sheet to start (a window `listen:play` event).
const KEY = "bibliorata:listen"
const DEFAULTS = { rate: 1, follow: true, continue: true }

export function listenOptions() {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") } } catch { return { ...DEFAULTS } }
}

export default class extends Controller {
  static targets = [ "rate", "follow", "continue" ]

  connect() { this.render() }

  pickRate({ currentTarget }) {
    this.store({ rate: Number(currentTarget.dataset.rate) })
  }

  save() {
    this.store({ follow: this.followTarget.checked, continue: this.continueTarget.checked })
  }

  play() {
    window.dispatchEvent(new CustomEvent("sheet:close", { detail: { id: "listen" } }))
    window.dispatchEvent(new CustomEvent("listen:play"))
  }

  store(changes) {
    const next = { ...listenOptions(), ...changes }
    try { localStorage.setItem(KEY, JSON.stringify(next)) } catch {}
    this.render()
    window.dispatchEvent(new CustomEvent("listen:options", { detail: next }))
  }

  render() {
    const o = listenOptions()
    this.rateTargets.forEach((b) => {
      const on = Number(b.dataset.rate) === Number(o.rate)
      b.classList.toggle("is-on", on)
      b.setAttribute("aria-checked", String(on))
    })
    if (this.hasFollowTarget) this.followTarget.checked = !!o.follow
    if (this.hasContinueTarget) this.continueTarget.checked = !!o.continue
  }
}
