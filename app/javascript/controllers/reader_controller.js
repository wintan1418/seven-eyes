import { Controller } from "@hotwired/stimulus"
import { listenOptions } from "./listen_options_controller"

// The Audio Bible. Preferred path: cached server-narrated chapter audio played
// through a real <audio> element — it keeps playing when the phone locks or the
// app goes to the background, with lock-screen controls via the Media Session
// API, and flows into the next chapter automatically (prefetched while the
// current one plays). Fallback path (no key, quota, failure): the old on-device
// speech synthesis, which reads the visible verses in the foreground only.
let active = null // one narration at a time across panes
let opener = null // the pane whose Listen button opened the Listen sheet

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

// The listener's chosen voice ("auto" = best available; "device" = the
// phone's own voice). Picked in Reading settings; see voice_choice_controller.
export const VOICE_KEY = "bibliorata:voice"
export function chosenVoice() {
  try { return localStorage.getItem(VOICE_KEY) || "auto" } catch { return "auto" }
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
    // Play from the Listen sheet starts the pane that opened it.
    this._onListenPlay = () => { if (opener === this) { opener = null; this.start() } }
    window.addEventListener("listen:play", this._onListenPlay)
    // A new speed applies straight away to what's playing.
    this._onListenOptions = (e) => { if (this._audio) this._audio.playbackRate = Number(e.detail.rate) || 1 }
    window.addEventListener("listen:options", this._onListenOptions)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this._onFrameRender)
    window.removeEventListener("listen:play", this._onListenPlay)
    window.removeEventListener("listen:options", this._onListenOptions)
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
    // Pick a voice, speed and mode first, where the Listen sheet exists.
    if (document.querySelector('[data-sheet-id-value="listen"]')) {
      opener = this
      window.dispatchEvent(new CustomEvent("sheet:open", { detail: { id: "listen" } }))
      return
    }
    this.start()
  }

  async start() {
    active?.stop()
    active = this
    window.dispatchEvent(new CustomEvent("reader:listening")) // auto-scroll steps aside

    const params = this.chapterParams()
    if (!params || chosenVoice() === "device") return this.speakFallback()

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
    const url = `/audio/chapter?osis=${encodeURIComponent(osis)}&chapter=${encodeURIComponent(chapter)}&translation=${encodeURIComponent(translation)}&voice=${encodeURIComponent(chosenVoice())}`
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
    audio.onplay = () => {
      if (this._audio !== audio) return
      audio.playbackRate = Number(listenOptions().rate) || 1
      if (this.state === "paused") this.setPaused(false)
    }
    audio.ontimeupdate = () => { if (this._audio === audio) this.followAudio(audio) }
    audio.src = info.url
    audio.playbackRate = Number(listenOptions().rate) || 1
    this._audio = audio
    this.startFollowing(info)

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
    if (!info.next || this.state !== "playing" || !listenOptions().continue) return this.reset()
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
      artist: [info.translation_name || info.translation, info.voice_name].filter(Boolean).join(" · "),
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

  // In the Android app (1.0.3+), WebView has no speechSynthesis, so the app
  // reads aloud with the phone's own voice through window.BiblioRataNative.
  speakFallback() {
    const text = this.collectText()
    if (!text) return this.reset()

    const native = window.BiblioRataNative
    if (native?.speak) {
      this._onNativeSpeech ??= (e) => {
        if (active !== this) return
        if (e.detail === "end") this.reset()
        if (e.detail === "error") { this.reset(); this.notify("This phone has no reading voice. Install one in Settings → Text-to-speech.") }
      }
      window.addEventListener("native:speech", this._onNativeSpeech)
      native.speak(text)
      this.setState("playing")
      return
    }

    if (!("speechSynthesis" in window)) {
      this.reset()
      this.notify("Listening isn't available right now. Please try again later.")
      return
    }

    window.speechSynthesis.cancel()
    this.startFollowing(null)
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = 0.92 * (Number(listenOptions().rate) || 1)
    utterance.onboundary = (e) => { if (active === this) this.followCharIndex(e.charIndex) }
    utterance.pitch = 1
    utterance.onend = this._onEnd
    utterance.onerror = this._onEnd
    window.speechSynthesis.speak(utterance)
    this.setState("playing")
  }

  // A short message, so the button never just does nothing.
  notify(text) {
    let toast = document.querySelector(".ps-toast.js-flash")
    if (!toast) {
      toast = document.createElement("div")
      toast.className = "ps-toast js-flash"
      document.body.appendChild(toast)
    }
    toast.textContent = text
    toast.classList.toggle("is-long", text.length > 40)
    toast.style.opacity = "1"
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => { toast.style.opacity = "0" }, 3200)
  }

  collectText() {
    return Array.from(this.element.querySelectorAll(".ps-verse-text"))
      .map((el) => el.textContent.trim())
      .filter(Boolean)
      .join(" ")
  }

  // ---- Follow along: light the verse being read and keep it in view ----
  //
  // Narrations are one mp3 per chapter with no word timings, so the current
  // verse is estimated from how far through the audio we are, weighted by each
  // verse's length (plus a short pause per verse, and the spoken heading).
  // The phone's own voice reports exact positions (boundary events).
  // If the reader scrolls by hand, following pauses for a few seconds.

  followVerses() {
    const chapter = this.hasButtonTarget ? this.buttonTarget.dataset.chapter : null
    return Array.from(this.element.querySelectorAll(".ps-verse"))
      .filter((el) => el.querySelector(".ps-verse-text") && (!chapter || !el.dataset.chapter || el.dataset.chapter === String(chapter)))
  }

  startFollowing(info) {
    this.stopFollowing()
    if (!listenOptions().follow) return
    // Only follow the chapter that's on screen (auto-advance moves on).
    if (info && this.hasButtonTarget && String(info.chapter) !== String(this.buttonTarget.dataset.chapter)) return
    const verses = this.followVerses()
    if (!verses.length) return
    const PAUSE = 12 // chars' worth of silence between verses
    let total = 0
    const starts = verses.map((el) => {
      const at = total
      total += el.querySelector(".ps-verse-text").textContent.trim().length + PAUSE
      return at
    })
    // The narrator says a heading first ("John, chapter 3. King James Version.").
    const lead = info ? (info.voice === "human" ? `${info.book} chapter ${info.chapter}` : `${info.book}, chapter ${info.chapter}. ${info.translation_name || ""}.`).length + PAUSE : 0
    // Device speech joins verse texts with one space: char offsets per verse.
    let offset = 0
    const charStarts = verses.map((el) => {
      const at = offset
      offset += el.querySelector(".ps-verse-text").textContent.trim().length + 1
      return at
    })
    this._follow = { verses, starts, charStarts, total, lead, index: -1, handAt: 0 }

    this._onHandScroll ??= () => { if (this._follow) this._follow.handAt = Date.now() }
    for (const target of [ this.scrollBox(), window ]) {
      target.addEventListener("wheel", this._onHandScroll, { passive: true })
      target.addEventListener("touchmove", this._onHandScroll, { passive: true })
    }
  }

  stopFollowing() {
    if (!this._follow) return
    this._follow.verses.forEach((el) => el.classList.remove("is-reading"))
    for (const target of [ this.scrollBox(), window ]) {
      target.removeEventListener("wheel", this._onHandScroll)
      target.removeEventListener("touchmove", this._onHandScroll)
    }
    this._follow = null
  }

  followAudio(audio) {
    const f = this._follow
    if (!f || !audio.duration || !Number.isFinite(audio.duration)) return
    const spoken = (audio.currentTime / audio.duration) * (f.lead + f.total) - f.lead
    if (spoken < 0) return
    let i = f.starts.length - 1
    while (i > 0 && f.starts[i] > spoken) i--
    this.markVerse(i)
  }

  followCharIndex(charIndex) {
    const f = this._follow
    if (!f) return
    let i = f.charStarts.length - 1
    while (i > 0 && f.charStarts[i] > charIndex) i--
    this.markVerse(i)
  }

  markVerse(i) {
    const f = this._follow
    if (!f || i === f.index) return
    f.verses[f.index]?.classList.remove("is-reading")
    f.index = i
    const el = f.verses[i]
    el.classList.add("is-reading")
    if (Date.now() - f.handAt > 6000) this.bringIntoView(el)
  }

  // The verse sits about a third of the way down, so what's next is visible.
  bringIntoView(el) {
    const box = this.scrollBox()
    const rect = el.getBoundingClientRect()
    if (box === window) {
      const top = window.scrollY + rect.top - window.innerHeight * 0.33
      window.scrollTo({ top: Math.max(0, top), behavior: "smooth" })
    } else {
      const boxRect = box.getBoundingClientRect()
      const top = box.scrollTop + (rect.top - boxRect.top) - box.clientHeight * 0.33
      box.scrollTo({ top: Math.max(0, top), behavior: "smooth" })
    }
  }

  // The pane's verses scroll inside .ps-verses on wide screens; on phones the page scrolls.
  scrollBox() {
    const box = this.element.querySelector(".ps-verses")
    if (box && box.scrollHeight > box.clientHeight + 4 && getComputedStyle(box).overflowY !== "visible") return box
    return window
  }

  // ---- Teardown ----

  stop() {
    // Only silence what this pane started — another pane may be narrating.
    if (active === this && "speechSynthesis" in window) window.speechSynthesis.cancel()
    if (active === this) window.BiblioRataNative?.stopSpeaking?.()
    this.reset()
  }

  reset() {
    this.stopFollowing()
    if (this._poll) { clearTimeout(this._poll); this._poll = null }
    this.releaseAudio()
    if (active === this) this.clearMediaSession()
    this._armed = null
    if (this._onNativeSpeech) window.removeEventListener("native:speech", this._onNativeSpeech)
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
    audio.onended = audio.onerror = audio.onpause = audio.onplay = audio.ontimeupdate = null
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
