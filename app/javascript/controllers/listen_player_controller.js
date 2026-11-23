import { Controller } from "@hotwired/stimulus"
import { listenOptions, storeListenOptions } from "./listen_options_controller"
import { listenControls, setRepeat, setSleep, nextRepeat, nextRate, rateLabel, sleepRemaining, clockLabel } from "../lib/listen_controls"

// The player bar (studies/_listen_player). Draws what the narrating pane
// announces (`listen:state`) and sends its buttons back as window
// `listen:command {action}` events; speed is stored with the Listen sheet's
// choices, repeat and the sleep timer in lib/listen_controls. Hidden when
// nothing is playing.
const REPEAT_LABELS = { off: "Repeat: off", verse: "Repeat this verse", chapter: "Repeat this chapter" }

export default class extends Controller {
  static targets = [ "status", "label", "toggle", "playIcon", "pauseIcon", "step", "speed",
                     "repeat", "repeatAll", "repeatOne", "sleep", "sleepLeft", "sleepMenu", "sleepChoice" ]

  connect() {
    this.now = null
    this._onState = (e) => this.update(e.detail)
    this._onOptions = () => this.renderSpeed()
    this._onControls = () => this.renderControls()
    this._onOutside = (e) => { if (!this.sleepMenuTarget.hidden && !e.target.closest?.(".lp-sleep")) this.closeSleepMenu() }
    window.addEventListener("listen:state", this._onState)
    window.addEventListener("listen:options", this._onOptions)
    window.addEventListener("listen:controls", this._onControls)
    document.addEventListener("click", this._onOutside)
    this.renderSpeed()
    this.renderControls()
  }

  disconnect() {
    window.removeEventListener("listen:state", this._onState)
    window.removeEventListener("listen:options", this._onOptions)
    window.removeEventListener("listen:controls", this._onControls)
    document.removeEventListener("click", this._onOutside)
    this.setShown(false)
    clearInterval(this._tick)
  }

  update(detail) {
    if (!detail) return
    // Another pane went quiet while this one plays: not ours to hide.
    if (detail.state === "idle" && this.now && this.now.pane !== detail.pane) return
    this.now = detail.state === "idle" ? null : detail
    this.setShown(!!this.now)
    if (!this.now) { this.closeSleepMenu(); return }

    const { state, book, chapter, verse, translation, canRate, canStep } = this.now
    const passage = [ book, chapter ].filter(Boolean).join(" ") + (verse ? `:${verse}` : "")
    this.labelTarget.textContent = [ passage, translation ].filter(Boolean).join(" · ")
    const busy = state === "loading"
    const paused = state === "paused"
    this.statusTarget.textContent = busy ? "Preparing audio…" : paused ? "Paused" : "Playing"
    this.playIconTarget.hidden = !paused && !busy
    this.pauseIconTarget.hidden = paused || busy
    this.toggleTarget.disabled = busy
    this.toggleTarget.setAttribute("aria-label", paused ? "Play" : "Pause")
    this.toggleTarget.title = paused ? "Play" : "Pause"
    this.stepTargets.forEach((b) => { b.disabled = busy || !canStep })
    this.speedTarget.disabled = canRate === false
    this.speedTarget.title = canRate === false ? "This phone's voice reads at one speed" : "Speed"
    this.renderControls()
  }

  setShown(shown) {
    this.element.hidden = !shown
    document.documentElement.classList.toggle("ui-has-player", shown)
  }

  // ---- Buttons ----

  toggle() { this.send("toggle") }
  prev() { this.send("prev") }
  next() { this.send("next") }
  close() {
    this.closeSleepMenu()
    this.send("stop")
  }

  send(action) {
    window.dispatchEvent(new CustomEvent("listen:command", { detail: { action } }))
  }

  cycleSpeed() {
    storeListenOptions({ rate: nextRate(listenOptions().rate) })
  }

  cycleRepeat() {
    setRepeat(nextRepeat(listenControls().repeat))
  }

  toggleSleepMenu() {
    const open = this.sleepMenuTarget.hidden
    this.sleepMenuTarget.hidden = !open
    this.sleepTarget.setAttribute("aria-expanded", String(open))
    if (open) (this.sleepChoiceTargets.find((b) => b.getAttribute("aria-checked") === "true") || this.sleepChoiceTargets[0])?.focus()
  }

  closeSleepMenu() {
    if (!this.hasSleepMenuTarget || this.sleepMenuTarget.hidden) return
    this.sleepMenuTarget.hidden = true
    this.sleepTarget.setAttribute("aria-expanded", "false")
  }

  pickSleep({ currentTarget }) {
    setSleep(currentTarget.dataset.sleep)
    this.closeSleepMenu()
    this.sleepTarget.focus()
  }

  // ---- Drawing ----

  renderSpeed() {
    const label = rateLabel(listenOptions().rate)
    this.speedTarget.textContent = label
    this.speedTarget.setAttribute("aria-label", `Speed ${label}, change`)
  }

  renderControls() {
    const { repeat, sleep } = listenControls()
    this.repeatTarget.classList.toggle("is-on", repeat !== "off")
    this.repeatTarget.setAttribute("aria-label", REPEAT_LABELS[repeat])
    this.repeatTarget.title = REPEAT_LABELS[repeat]
    this.repeatTarget.dataset.mode = repeat
    this.repeatAllTarget.hidden = repeat === "verse"
    this.repeatOneTarget.hidden = repeat !== "verse"

    const choice = sleep.mode === "time" ? String(sleep.minutes) : sleep.mode
    this.sleepChoiceTargets.forEach((b) => b.setAttribute("aria-checked", String(b.dataset.sleep === choice)))
    this.sleepTarget.classList.toggle("is-on", sleep.mode !== "off")
    clearInterval(this._tick)
    this._tick = null
    if (sleep.mode === "time") {
      this._tick = setInterval(() => this.renderSleepLeft(), 1000)
    }
    this.renderSleepLeft()
  }

  renderSleepLeft() {
    const { sleep } = listenControls()
    let text = ""
    let label = "Sleep timer: off"
    if (sleep.mode === "chapter") { text = "Ch."; label = "Sleep timer: end of this chapter" }
    if (sleep.mode === "time") {
      text = clockLabel(sleepRemaining(sleep))
      label = `Sleep timer: ${text} left`
    }
    this.sleepLeftTarget.textContent = text
    this.sleepLeftTarget.hidden = !text
    this.sleepTarget.setAttribute("aria-label", label)
    this.sleepTarget.title = label
  }
}
