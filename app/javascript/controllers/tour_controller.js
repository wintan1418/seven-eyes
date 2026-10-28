import { Controller } from "@hotwired/stimulus"

// First-run guided tour: a sequence of spotlight "coachmarks" over the real
// controls in the workspace. Auto-starts once (per user server-side, per browser
// for guests), is replayable via a `tour#start` action or `?tour=1`, and falls
// back to a centered card when a step's target isn't on screen yet (e.g. a pane
// has no verse loaded). Pure DOM — no library.
const KEY = "scriptorium.tourDone"

const STEPS = [
  { title: "Welcome to BiblioRata", body: "A 20-second tour of the reader. Skip anytime." },
  { sel: '[data-tour="reference"]', title: "Go to any passage", body: "Tap here to pick a book and chapter — or type a reference like Jn 3:16. ⌘K opens it from anywhere." },
  { sel: '[data-tour="translation"]', title: "Choose a version", body: "Switch between the KJV, BSB, WEB and more." },
  { sel: '[data-tour="verses"]', title: "Tap a verse", body: "Tap verses to highlight, note, copy, share or compare them. Select words to ask the AI Rabbi.",
    fallback: "Once a chapter is open, tap a verse to highlight, note, copy or share it." },
  { sel: '[data-tour="search"]', title: "Search the whole Bible", body: "Find any phrase — “love your enemies” — and jump to it." },
  { sel: '[data-tour="view"]', title: "Make it comfortable", body: "Text size, light / sepia / dark, and one-verse-per-line live under Aa." ,
    fallback: "Text size, theme and layout live in More → Reading settings." },
  { sel: '[data-tour="panes"]', title: "Compare", body: "Read the same passage in two to four translations side by side.",
    fallback: "Compare translations side by side from More → Compare." },
  { sel: '[data-tour="preach"]', title: "Preach", body: "One tap puts the passage on the projector verse by verse — with live follow-along and a phone remote.",
    fallback: "Preach mode, the queue, Go Live and the phone remote are all under More." },
  { sel: '[data-tour="more"]', title: "Everything else", body: "Queue, sermon manuscript, AI find, sharing — and the ☰ menu holds your studies, plans and the full guide." },
  { title: "You're all set", body: "Now go study the Word. ✢", final: true }
]

export default class extends Controller {
  static values = {
    authenticated: Boolean,
    done: Boolean,        // server truth for signed-in users
    url: String           // preferences_path — persists completion
  }

  connect() {
    this._onKey = (e) => { if (e.key === "Escape") this.finish() }
    this._onResize = () => this.position()
    this._onStart = () => this.start()
    window.addEventListener("tour:start", this._onStart)

    const forced = new URLSearchParams(window.location.search).get("tour") === "1"
    if (forced || !this.alreadyDone()) {
      // let the workspace paint first
      this._autoStart = setTimeout(() => this.start(), forced ? 0 : 600)
    }
  }

  disconnect() {
    clearTimeout(this._autoStart) // navigated away before the tour began
    window.removeEventListener("tour:start", this._onStart)
    this.teardown()
  }

  alreadyDone() {
    if (this.authenticatedValue) return this.doneValue
    try { return localStorage.getItem(KEY) === "1" } catch { return false }
  }

  start() {
    this.teardown()
    this.index = 0
    this.build()
    this.render()
    document.addEventListener("keydown", this._onKey)
    window.addEventListener("resize", this._onResize)
  }

  // ---- DOM scaffold ----

  build() {
    const root = document.createElement("div")
    root.className = "ps-tour"
    root.innerHTML = `
      <div class="ps-tour-spot" data-tour-el="spot"></div>
      <div class="ps-tour-card" data-tour-el="card" role="dialog" aria-modal="true">
        <div class="ps-tour-step" data-tour-el="step"></div>
        <div class="ps-tour-title" data-tour-el="title"></div>
        <div class="ps-tour-body" data-tour-el="body"></div>
        <div class="ps-tour-actions">
          <button type="button" class="ps-tour-skip" data-tour-el="skip">Skip</button>
          <div class="ps-tour-nav">
            <button type="button" class="ps-tour-back" data-tour-el="back">Back</button>
            <button type="button" class="ps-tour-next" data-tour-el="next">Next</button>
          </div>
        </div>
      </div>`
    document.body.appendChild(root)
    this.root = root
    this.el = (n) => root.querySelector(`[data-tour-el="${n}"]`)
    this.el("skip").addEventListener("click", () => this.finish())
    this.el("back").addEventListener("click", () => this.go(-1))
    this.el("next").addEventListener("click", () => this.go(1))
  }

  teardown() {
    document.removeEventListener("keydown", this._onKey)
    window.removeEventListener("resize", this._onResize)
    if (this.root) { this.root.remove(); this.root = null }
  }

  go(delta) {
    const next = this.index + delta
    if (next >= STEPS.length) return this.finish()
    if (next < 0) return
    this.index = next
    this.render()
  }

  // ---- rendering one step ----

  render() {
    const step = STEPS[this.index]
    const target = step.sel ? document.querySelector(step.sel) : null
    const usingFallback = step.sel && !target

    this.el("step").textContent = `Step ${this.index + 1} of ${STEPS.length}`
    this.el("title").textContent = step.title
    this.el("body").textContent = usingFallback ? (step.fallback || step.body) : step.body
    this.el("back").style.visibility = this.index === 0 ? "hidden" : "visible"
    this.el("next").textContent = step.final ? "Done" : "Next"

    this._target = target
    this.position()
  }

  position() {
    if (!this.root) return
    const spot = this.el("spot")
    const card = this.el("card")
    const target = this._target

    if (target && target.getBoundingClientRect().width > 0) {
      const r = target.getBoundingClientRect()
      const pad = 6
      spot.style.display = "block"
      spot.style.left = `${r.left - pad}px`
      spot.style.top = `${r.top - pad}px`
      spot.style.width = `${r.width + pad * 2}px`
      spot.style.height = `${r.height + pad * 2}px`

      // place the card below the target if there's room, else above
      const cw = 320, ch = card.offsetHeight || 180
      let left = Math.min(Math.max(12, r.left), window.innerWidth - cw - 12)
      let top = r.bottom + 14
      if (top + ch > window.innerHeight - 12) top = Math.max(12, r.top - ch - 14)
      card.style.left = `${left}px`
      card.style.top = `${top}px`
      card.classList.remove("is-centered")
    } else {
      // no target — center the card, no spotlight hole
      spot.style.display = "none"
      card.classList.add("is-centered")
      card.style.left = ""
      card.style.top = ""
    }
  }

  finish() {
    this.teardown()
    try { localStorage.setItem(KEY, "1") } catch { /* storage unavailable */ }
    if (this.authenticatedValue && this.urlValue) {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      fetch(this.urlValue, {
        method: "PATCH",
        headers: { "X-CSRF-Token": token, "Content-Type": "application/json" },
        body: JSON.stringify({ tour_completed: "1" })
      }).catch(() => {})
    }
  }
}
