import { Controller } from "@hotwired/stimulus"

// The Listen sheet's speed and mode choices, remembered on this device. The
// reader controller reads them through listenOptions(); Play asks the pane
// that opened the sheet to start (a window `listen:play` event).
//
// Compare (two or more passages on screen): the sheet also asks which passage
// to hear — each labelled with its reference and translation, the first one
// (left / top) by default, or the pane whose own Listen button opened it — and
// Play names that pane (`listen:play {pane}`); that pane's reader controller
// plays it and follows along in its own column. What's playing shows here with
// a Stop button (`listen:state` from the reader, `listen:stop` back).
const KEY = "bibliorata:listen"
const DEFAULTS = { rate: 1, follow: true, continue: true }

export function listenOptions() {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") } } catch { return { ...DEFAULTS } }
}

// Remember new choices (the sheet, or the player bar's speed button) and tell
// the narrating pane and every open control (`listen:options`).
export function storeListenOptions(changes) {
  const next = { ...listenOptions(), ...changes }
  try { localStorage.setItem(KEY, JSON.stringify(next)) } catch {}
  window.dispatchEvent(new CustomEvent("listen:options", { detail: next }))
  return next
}

export default class extends Controller {
  static targets = [ "rate", "follow", "continue", "sides", "sideList", "now", "nowLabel" ]

  connect() {
    this.render()
    this.playing = null // { pane, state } of the pane narrating now
    this._onState = (e) => {
      const { pane, state } = e.detail || {}
      if (state === "idle") { if (this.playing?.pane === pane) this.playing = null }
      else this.playing = { pane, state }
      this.renderNow()
    }
    window.addEventListener("listen:state", this._onState)
    // Speed changed on the player bar: show it here too.
    this._onOptions = () => this.render()
    window.addEventListener("listen:options", this._onOptions)
  }

  disconnect() {
    window.removeEventListener("listen:state", this._onState)
    window.removeEventListener("listen:options", this._onOptions)
  }

  // sheet:opened — offer the passages on screen when there's more than one.
  opened({ detail }) {
    const panes = this.panes()
    if (this.hasSidesTarget) this.sidesTarget.hidden = panes.length < 2
    if (panes.length < 2) { this.chosen = null; this.renderNow(); return }
    const ids = panes.map((p) => p.id)
    const want = [ detail?.paneId, this.playing?.pane, this.chosen ].find((id) => id && ids.includes(id))
    this.chosen = want || ids[0]
    this.renderSides(panes)
    this.renderNow()
  }

  pickSide({ currentTarget }) {
    this.chosen = currentTarget.value
  }

  stop() {
    window.dispatchEvent(new CustomEvent("listen:stop"))
  }

  // Reading panes that can be heard and are on screen (phones show two).
  panes() {
    return Array.from(document.querySelectorAll(".ps-workspace .ps-pane[id]"))
      .filter((el) => el.offsetParent !== null && el.querySelector("[data-reader-target='button'][data-osis]"))
      .map((el) => {
        const meta = el.querySelector(".rd-pane-meta")?.dataset || {}
        return { id: el.id, el, reference: meta.referenceLabel || "", translation: meta.translationCode || "" }
      })
  }

  // "Left" / "Right" side by side, "Top" / "Bottom" when the panes stack.
  where(panes, i) {
    if (panes.length !== 2) return `Passage ${i + 1}`
    const [ a, b ] = panes.map((p) => p.el.getBoundingClientRect())
    const stacked = Math.abs(a.left - b.left) < 4
    return stacked ? [ "Top", "Bottom" ][i] : [ "Left", "Right" ][i]
  }

  renderSides(panes) {
    if (!this.hasSideListTarget) return
    const list = this.sideListTarget
    list.replaceChildren(...panes.map((p, i) => {
      const label = document.createElement("label")
      label.className = "ls-side"
      const input = document.createElement("input")
      Object.assign(input, { type: "radio", name: "listen-side", value: p.id, checked: p.id === this.chosen, className: "ls-side-radio" })
      input.dataset.action = "listen-options#pickSide"
      const text = document.createElement("span")
      text.className = "ls-side-text"
      const ref = document.createElement("span")
      ref.className = "ls-side-ref"
      ref.textContent = [ p.reference, p.translation ].filter(Boolean).join(" · ")
      const where = document.createElement("span")
      where.className = "ls-side-where"
      where.textContent = this.where(panes, i)
      text.append(ref, where)
      label.append(input, text)
      return label
    }))
  }

  renderNow() {
    if (!this.hasNowTarget) return
    const pane = this.playing && document.getElementById(this.playing.pane)
    this.nowTarget.hidden = !pane
    if (!pane) return
    const meta = pane.querySelector(".rd-pane-meta")?.dataset || {}
    this.nowLabelTarget.textContent = [ meta.referenceLabel, meta.translationCode ].filter(Boolean).join(" · ")
  }

  pickRate({ currentTarget }) {
    this.store({ rate: Number(currentTarget.dataset.rate) })
  }

  save() {
    this.store({ follow: this.followTarget.checked, continue: this.continueTarget.checked })
  }

  play() {
    window.dispatchEvent(new CustomEvent("sheet:close", { detail: { id: "listen" } }))
    const pane = this.hasSidesTarget && !this.sidesTarget.hidden ? this.chosen : null
    window.dispatchEvent(new CustomEvent("listen:play", { detail: pane ? { pane } : {} }))
  }

  store(changes) {
    storeListenOptions(changes) // re-renders through listen:options
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
