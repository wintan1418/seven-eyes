import { Controller } from "@hotwired/stimulus"

// The Audio Bible. Preferred path: cached server-narrated chapter audio played
// through a real <audio> element — it keeps playing when the phone locks or the
// app goes to the background, with lock-screen controls via the Media Session
// API, and flows into the next chapter automatically (prefetched while the
// current one plays). Fallback path (no key, quota, failure): the old on-device
// speech synthesis, which reads the visible verses in the foreground only.
let active = null // one narration at a time across panes

// One <audio> element for the whole page, reused for every chapter. iOS only
// lets an element that was started by a tap keep playing (and auto-advance)
// in the background; a fresh `new Audio()` per chapter is refused there.
let sharedAudio = null
function audioElement() {
  if (!sharedAudio) {
    sharedAudio = new Audio()
    sharedAudio.preload = "auto"
  }
  return sharedAudio
}

const POLL_MS = 4000
const MAX_POLLS = 45 // ~3 minutes — long chapters take a while to narrate

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.state = "idle"
    this._audio = null
    this._poll = null
    this._armed = null // info ready to play but blocked by autoplay policy
    this._onEnd = () => this.reset()
    // This controller sits on the pane's turbo-frame, which survives frame
    // navigations: a new chapter/translation must not keep narrating the old
    // one behind a reset button.
    this._onFrameRender = (e) => { if (e.target === this.element) this.stop() }
    this.element.addEventListener("turbo:frame-render", this._onFrameRender)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this._onFrameRender)
    this.stop()
  }

  toggle() {
    if (this.state === "paused") { this._audio?.play().catch(() => this.reset()); return }
    if (this.state !== "idle") return this.stop()
    if (this._armed) {
      const info = this._armed
      this._armed = null
      return this.play(info)
    }
    this.start()
  }

  async start() {
    active?.stop()
    active = this

    const params = this.chapterParams()
    if (!params) return this.speakFallback()

    this.setState("loading")
    try {
      const info = await this.fetchInfo(params)
      if (this.state !== "loading") return // stopped while fetching
      if (info.status === "ready") return this.play(info)
      if (info.status === "preparing") return this.pollUntilReady(params)
      this.speakFallback()
    } catch {
      this.speakFallback()
    }
  }

  chapterParams() {
    const d = this.hasButtonTarget ? this.buttonTarget.dataset : {}
    if (!d.osis || !d.chapter || !d.translation) return null
    return { osis: d.osis, chapter: d.chapter, translation: d.translation }
  }

  async fetchInfo({ osis, chapter, translation }) {
    const url = `/audio/chapter?osis=${encodeURIComponent(osis)}&chapter=${encodeURIComponent(chapter)}&translation=${encodeURIComponent(translation)}`
    const res = await fetch(url, { headers: { Accept: "application/json" } })
    return res.json()
  }

  pollUntilReady(params, remaining = MAX_POLLS) {
    if (remaining <= 0) return this.speakFallback()
    this._poll = setTimeout(async () => {
      if (this.state !== "loading") return
      try {
        const info = await this.fetchInfo(params)
        if (this.state !== "loading") return
        if (info.status === "ready") return this.play(info)
        if (info.status === "preparing") return this.pollUntilReady(params, remaining - 1)
        this.speakFallback()
      } catch {
        this.pollUntilReady(params, remaining - 1)
      }
    }, POLL_MS)
  }

  async play(info) {
    const audio = audioElement()
    audio.pause()
    // Re-point the shared element; handlers are assignments so a previous
    // pane's narration can't keep listening.
    audio.onended = () => { if (this._audio === audio) this.advance(info) }
    audio.onerror = () => { if (this._audio === audio && audio.getAttribute("src")) this.reset() }
    audio.onpause = () => { if (this._audio === audio && !audio.ended && this.state === "playing") this.setPaused(true) }
    audio.onplay = () => { if (this._audio === audio && this.state === "paused") this.setPaused(false) }
    audio.src = info.url
    this._audio = audio

    try {
      await audio.play()
    } catch {
      // Autoplay policy refused (too long since the tap) — arm it so the very
      // next tap plays instantly.
      this._armed = info
      return this.setState("idle")
    }
    this.setState("playing")
    this.setMediaSession(info)
    if (info.next) this.fetchInfo(info.next).catch(() => {}) // warm the next chapter's cache
  }

  // Seamless-ish continuation: the next chapter was requested when this one
  // started, so by the time it ends the narration is usually cached and ready.
  async advance(info) {
    if (!info.next || this.state !== "playing") return this.reset()
    this.setState("loading")
    try {
      const next = await this.fetchInfo(info.next)
      if (this.state !== "loading") return
      if (next.status === "ready") return this.play(next)
      if (next.status === "preparing") return this.pollUntilReady(info.next)
      this.reset()
    } catch {
      this.reset()
    }
  }

  setMediaSession(info) {
    if (!("mediaSession" in navigator)) return
    navigator.mediaSession.metadata = new MediaMetadata({
      title: info.title,
      artist: info.translation_name || info.translation,
      album: "BiblioRata Audio Bible"
    })
    navigator.mediaSession.playbackState = "playing"
    const audio = () => this._audio
    navigator.mediaSession.setActionHandler("play", () => audio()?.play().catch(() => {}))
    navigator.mediaSession.setActionHandler("pause", () => audio()?.pause())
    navigator.mediaSession.setActionHandler("stop", () => this.stop())
    navigator.mediaSession.setActionHandler("seekbackward", () => { const a = audio(); if (a) a.currentTime = Math.max(0, a.currentTime - 15) })
    navigator.mediaSession.setActionHandler("seekforward", () => { const a = audio(); if (a) a.currentTime = Math.min(a.duration || 0, a.currentTime + 15) })
  }

  clearMediaSession() {
    if (!("mediaSession" in navigator)) return
    navigator.mediaSession.metadata = null
    navigator.mediaSession.playbackState = "none"
    for (const action of ["play", "pause", "stop", "seekbackward", "seekforward"]) {
      try { navigator.mediaSession.setActionHandler(action, null) } catch {}
    }
  }

  // ---- On-device speech synthesis (foreground-only fallback) ----

  speakFallback() {
    const text = this.collectText()
    if (!("speechSynthesis" in window) || !text) return this.reset()

    window.speechSynthesis.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = 0.92
    utterance.pitch = 1
    utterance.onend = this._onEnd
    utterance.onerror = this._onEnd
    window.speechSynthesis.speak(utterance)
    this.setState("playing")
  }

  collectText() {
    return Array.from(this.element.querySelectorAll(".ps-verse-text"))
      .map((el) => el.textContent.trim())
      .filter(Boolean)
      .join(" ")
  }

  // ---- Teardown ----

  stop() {
    // Only silence what this pane started — another pane may be narrating.
    if (active === this && "speechSynthesis" in window) window.speechSynthesis.cancel()
    this.reset()
  }

  reset() {
    if (this._poll) { clearTimeout(this._poll); this._poll = null }
    this.releaseAudio()
    if (active === this) this.clearMediaSession()
    this._armed = null
    this.setState("idle")
    if (active === this) active = null
  }

  // Paused from the lock screen / headphones: reflect it on the button and in
  // the Media Session, so the OS shows a Play control rather than Pause.
  setPaused(paused) {
    this.setState(paused ? "paused" : "playing")
    if ("mediaSession" in navigator) navigator.mediaSession.playbackState = paused ? "paused" : "playing"
  }

  releaseAudio() {
    if (!this._audio) return
    const audio = this._audio
    this._audio = null
    audio.onended = audio.onerror = audio.onpause = audio.onplay = null
    audio.pause()
    audio.removeAttribute("src")
    audio.load()
  }

  setState(state) {
    this.state = state
    if (!this.hasButtonTarget) return
    const btn = this.buttonTarget
    btn.classList.toggle("is-on", state === "playing" || state === "paused")
    btn.classList.toggle("is-loading", state === "loading")
    // Idle shows the button's own (headphones) icon; a re-rendered pane resets
    // to idle and must not swap that icon for a bare ▶.
    if (!btn.dataset.idleIcon && btn.querySelector("svg")) btn.dataset.idleIcon = btn.innerHTML
    btn.innerHTML = state === "idle" && btn.dataset.idleIcon
      ? btn.dataset.idleIcon
      : { idle: "&#9658;", loading: "&#8987;", playing: "&#9632;", paused: "&#9658;" }[state] // ▶ ⌛ ■ ▶
    btn.title = { idle: "Listen to this chapter", loading: "Preparing audio…", playing: "Stop listening", paused: "Resume listening" }[state]
  }
}
