import { Controller } from "@hotwired/stimulus"

// The Give form (/give): keeps the preset chips and "other amount" in step,
// and shows what will be given on the button ("Give ₦5,000 monthly").
// Which currency's chips show is plain CSS (:has), so it works without JS.
const SYMBOLS = { NGN: "₦", USD: "$" }

export default class extends Controller {
  static targets = ["preset", "custom", "symbol", "summary"]

  connect() { this.refresh() }

  refresh(event) {
    const target = event?.target
    const currency = this.currency
    if (target && this.presetTargets.includes(target)) this.customTarget.value = ""
    if (target === this.customTarget && this.customTarget.value.trim()) {
      this.presetsFor(currency).forEach((radio) => { radio.checked = false })
    }
    if (target?.name === "donation[currency]" && !this.customTarget.value.trim() && !this.presetsFor(currency).some((r) => r.checked)) {
      const presets = this.presetsFor(currency)
      if (presets[1]) presets[1].checked = true
    }

    this.symbolTarget.textContent = SYMBOLS[currency] || ""
    if (!this.hasSummaryTarget) return
    const amount = this.amount
    const monthly = this.element.querySelector("input[name='donation[frequency]']:checked")?.value === "monthly"
    this.summaryTarget.textContent = amount
      ? `Give ${SYMBOLS[currency]}${amount.toLocaleString("en-US", { maximumFractionDigits: 2 })}${monthly ? " monthly" : ""}`
      : "Give"
  }

  get currency() {
    return this.element.querySelector("input[name='donation[currency]']:checked")?.value || "NGN"
  }

  get amount() {
    const typed = parseFloat(this.customTarget.value.replace(/,/g, ""))
    if (typed > 0) return typed
    const preset = this.presetsFor(this.currency).find((r) => r.checked)
    return preset ? Number(preset.value) : null
  }

  presetsFor(currency) {
    return this.presetTargets.filter((r) => r.name === `donation[amount_${currency.toLowerCase()}]`)
  }
}
