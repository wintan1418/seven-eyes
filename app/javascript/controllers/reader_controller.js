import { Controller } from "@hotwired/stimulus"
import { listenOptions } from "./listen_options_controller"
import { listenControls, clearSleep, sleepRemaining, verseIndexAt, verseStartTime } from "../lib/listen_controls"
import { isNetworkSlow } from "../lib/offline/network"

// The Audio Bible. Three ways to read a chapter aloud ("engines"):
//
//   audio  — cached server narration (the human KJV reader or an AI voice)
//            through a real <audio> element: it keeps playing when the phone
//            locks or the app goes to the background, with lock-screen
//            controls (Media Session), and flows into the next chapter
//            (prefetched while the current one plays). Pause/resume are the
//            element's own; verses are found by time (server verse timings,
//            or an estimate by verse length until they exist).
//   speech — the browser's speechSynthesis (the "Phone voice", and the
//            fallback when there's no network or no server voice), and
//   native — the Android app's phone voice (window.BiblioRataNative; its
//            WebView has no speechSynthesis).
//   Both speak one verse at a time, so pause / resume / previous / next /
//   repeat work by verse (resume starts the paused verse again).
//
// The player bar (listen_player controller) and the Listen sheet talk to the
// narrating pane through window events: `listen:play {pane, verse}`,
// `listen:command {action}`, `listen:stop`, `listen:options` (speed), and
// `listen:controls` (repeat / sleep, lib/listen_controls). Every change is
// announced back as `listen:state`.
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
const FADE_MS = 6000 // the sleep timer fades the voice out over this long
// The Android voice reports "end" for a verse it was told to stop; ignore one
// that comes this soon after we started the next verse.
const NATIVE_STALE_END_MS = 1500

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.state = "idle"
    this.engine = null
    this._audio = null
    this._poll = null
    this._armed = null // info ready to play but blocked by autoplay policy
    this._gen = 0 // bumps whenever spoken verses are cut off, so stale callbacks are ignored
    this._verse = -1 // index (in the verse map) of the verse being read
    this._loopVerse = -1 // the verse "Repeat this verse" goes back to
    // This controller sits on the pane's turbo-frame, which survives frame
    // navigations: a new chapter/translation must not keep narrating the old
    // one behind a reset button.
    this._onFrameRender = (e) => {
      if (e.target !== this.element) return
      // We turned the page with the voice (next chapter): keep going.
      if (this._turning && this.state !== "idle") {
        this._turning = false
        if (this.engine === "audio") {
          this.buildMap(this._info)
          this.emit()
        } else {
          // The phone's voice reads the words on screen: read the new page.
          this.buildMap(null)
          this.speakFrom(0)
        }
        return
      }
      this.stop()
    }
    this.element.addEventListener("turbo:frame-render", this._onFrameRender)
    // Play from the Listen sheet starts the pane it names (Compare: the side
    // the listener picked), or else the pane whose Listen button opened it.
    // "Play from here" (verse action bar) names the pane and a verse.
    this._onListenPlay = (e) => {
      const { pane, verse } = e.detail || {}
      if (pane ? pane !== this.element.id : opener !== this) return
      opener = null
      if (verse && active === this && this.goToVerseNumber(verse)) return
      this.start({ verse })
    }
    window.addEventListener("listen:play", this._onListenPlay)
    // Stop from the Listen sheet (Compare: no per-pane button on phones).
    this._onListenStop = () => { if (active === this) this.stop() }
    window.addEventListener("listen:stop", this._onListenStop)
    // A new speed applies straight away to what's playing.
    this._onListenOptions = (e) => { if (active === this) this.applyRate(e.detail?.rate) }
    window.addEventListener("listen:options", this._onListenOptions)
    // The player bar's buttons.
    this._onCommand = (e) => { if (active === this) this.command(e.detail?.action) }
    window.addEventListener("listen:command", this._onCommand)
    // Repeat / sleep timer changed.
    this._onControls = () => { if (active === this) this.armSleep() }
    window.addEventListener("listen:controls", this._onControls)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this._onFrameRender)
    window.removeEventListener("listen:play", this._onListenPlay)
    window.removeEventListener("listen:stop", this._onListenStop)
    window.removeEventListener("listen:options", this._onListenOptions)
    window.removeEventListener("listen:command", this._onCommand)
    window.removeEventListener("listen:controls", this._onControls)
    this.stop()
  }

  toggle() {
    if (this.state === "paused") return this.resume()
    if (this.state !== "idle") return this.stop()
    if (this._armed) {
      const info = this._armed
      this._armed = null
      return this.play(info)
    }
    // Pick a voice, speed and mode first, where the Listen sheet exists.
    if (document.querySelector('[data-sheet-id-value="listen"]')) {
      opener = this
      window.dispatchEvent(new CustomEvent("sheet:open", { detail: { id: "listen", paneId: this.element.id } }))
      return
    }
    this.start()
  }

  async start({ verse } = {}) {
    active?.stop()
    active = this
    this._startVerse = Number(verse) || null
    window.dispatchEvent(new CustomEvent("reader:listening")) // auto-scroll steps aside

    const params = this.chapterParams()
    this._params = params
    // No server voice offline: the phone's own voice reads the page.
    if (!params || chosenVoice() === "device" || navigator.onLine === false || isNetworkSlow()) return this.speakFallback()

    this.setState("loading")
    try {
      const info = await this.fetchInfo(params)
      if (this.state !== "loading") return // stopped while fetching
      if (info.status === "ready") return this.play(info)
      if (info.status === "preparing") return this.pollUntilReady(params)
      this.speakFallback()
    } catch {
      if (this.state === "loading") this.speakFallback()
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

  // ---- The player's commands (listen:command) ----

  command(action) {
    switch (action) {
      case "toggle": return this.state === "playing" ? this.pause() : this.resume()
      case "pause": return this.pause()
      case "resume": return this.resume()
      case "next": return this.stepVerse(1)
      case "prev": return this.stepVerse(-1)
      case "stop": return this.stop()
    }
  }

  pause() {
    if (this.state !== "playing") return
    this.cancelFade()
    if (this.engine === "audio") return this._audio?.pause() // onpause → paused
    this.silenceSpeech()
    this.setPaused(true)
  }

  resume() {
    if (this.state === "idle" && this._armed) return this.toggle()
    if (this.state !== "paused") return
    if (this.engine === "audio") { this._audio?.play().catch(() => this.reset()); return }
    this.setPaused(false)
    this.speakFrom(Math.max(0, this._verse))
  }

  // Previous / next verse. Past the last verse = the chapter is done.
  stepVerse(delta) {
    const map = this._map
    if (!map) {
      // Narration of a chapter that isn't on screen: skip by 15 seconds.
      const a = this._audio
      if (a) a.currentTime = Math.max(0, Math.min(this.duration() || a.currentTime + 15, a.currentTime + 15 * delta))
      return
    }
    const last = map.verses.length - 1
    const from = this._verse < 0 ? (delta > 0 ? -1 : 0) : this._verse
    const to = from + delta
    if (to > last) {
      if (this.engine === "audio") return this.audioEnded(this._info, { skipped: true })
      return this.chapterEnded()
    }
    this.seekVerse(Math.max(0, to))
  }

  // Jump to verse i of the map (online: by time; phone voice: speak from it).
  seekVerse(i) {
    const map = this._map
    if (!map || i < 0 || i >= map.verses.length) return
    this.cancelFade()
    if (this.engine === "audio") {
      const t = verseStartTime(map, i, this.duration())
      if (t == null || !this._audio) return
      this._audio.currentTime = t
      this._loopVerse = i
      this.setVerse(i, true)
      return
    }
    if (this.state === "playing") return this.speakFrom(i)
    this.setVerse(i, true) // paused: resume starts here
  }

  // "Play from here" on the chapter that's already playing.
  goToVerseNumber(number) {
    if (this.state === "idle" || this.state === "loading" || !this._map) return false
    const i = this.indexOfVerse(number)
    if (i < 0) return false
    this.seekVerse(i)
    if (this.state === "paused") this.resume()
    return true
  }

  indexOfVerse(number) {
    if (!number || !this._map) return -1
    return this._map.verses.findIndex((el) => Number(el.dataset.verseNum) === Number(number))
  }

  applyRate(rate) {
    const value = Number(rate) || 1
    if (this.engine === "audio" && this._audio) this._audio.playbackRate = value
    // The phone voice takes a new speed from the next thing it says: say this verse again.
    if (this.engine === "speech" && this.state === "playing") this.speakFrom(Math.max(0, this._verse))
    this.emit()
  }

  // ---- Server narration (<audio>) ----

  async play(info) {
    const audio = audioElement()
    audio.pause()
    this.engine = "audio"
    // Re-point the shared element; handlers are assignments so a previous
    // pane's narration can't keep listening.
    audio.onended = () => { if (this._audio === audio) this.audioEnded(info) }
    audio.onerror = () => { if (this._audio === audio && audio.getAttribute("src")) this.audioFailed() }
    audio.onpause = () => { if (this._audio === audio && !audio.ended && this.state === "playing") this.setPaused(true) }
    audio.onplay = () => {
      if (this._audio !== audio) return
      audio.playbackRate = Number(listenOptions().rate) || 1
      if (this.state === "paused") this.setPaused(false)
    }
    audio.ontimeupdate = () => { if (this._audio === audio) this.onAudioTime(audio) }
    audio.onloadedmetadata = () => { if (this._audio === audio) this.seekPending() }
    audio.src = info.url
    audio.volume = 1
    audio.playbackRate = Number(listenOptions().rate) || 1
    this._audio = audio
    this._info = info
    this._verse = -1
    this._loopVerse = -1
    this.buildMap(info)
    this.awaitTimings(info)
    // Play from a verse: jump there now if we know where it is, else once the length is known.
    this._seekTo = this.indexOfVerse(this._startVerse)
    this._startVerse = null
    this.seekPending()

    try {
      await audio.play()
    } catch {
      if (this._audio !== audio) return // failed to load: audioFailed took over
      // Autoplay policy refused (too long since the tap) — arm it so the very
      // next tap plays instantly.
      this._armed = info
      return this.setState("idle")
    }
    this.setState("playing")
    this.setMediaSession(info)
    this.armSleep()
    if (info.next) this.fetchInfo(info.next).catch(() => {}) // warm the next chapter's cache
  }

  // The narration wouldn't load (lost connection, missing file): carry on with
  // the phone's voice from the verse we'd reached, rather than going quiet.
  audioFailed() {
    const verse = this._map?.verses[this._verse]?.dataset.verseNum
    this.releaseAudio()
    this.clearMediaSession()
    this._startVerse = Number(verse) || null
    this.speakFallback()
  }

  seekPending() {
    if (!(this._seekTo > 0) || !this._audio) return
    const t = verseStartTime(this._map, this._seekTo, this.duration())
    if (t == null) return
    this._audio.currentTime = t
    this._loopVerse = this._seekTo
    this.setVerse(this._seekTo, true)
    this._seekTo = null
  }

  // The stream often doesn't report its length: use the one the server sent.
  duration() {
    const a = this._audio
    if (a && Number.isFinite(a.duration) && a.duration > 0) return a.duration
    return Number(this._info?.duration) || 0
  }

  onAudioTime(audio) {
    if (this.checkSleep()) return
    const map = this._map
    if (!map) return
    const i = verseIndexAt(map, audio.currentTime, this.duration())
    // Repeat this verse = the verse playing when it was switched on (or the
    // one picked with previous / next since): past its end, back to its start.
    const repeatVerse = listenControls().repeat === "verse"
    if (i >= 0 && (!repeatVerse || this._loopVerse < 0)) this._loopVerse = i
    if (repeatVerse && this._loopVerse >= 0 && i > this._loopVerse) {
      const t = verseStartTime(map, this._loopVerse, this.duration())
      if (t != null) { audio.currentTime = t; return }
    }
    if (i < 0) return
    this.setVerse(i)
  }

  // The chapter's narration finished (or Next on its last verse).
  audioEnded(info, { skipped = false } = {}) {
    const audio = this._audio
    const { repeat, sleep } = listenControls()
    if (sleep.mode === "chapter") { clearSleep(); return this.stop() }
    if (repeat === "verse" && !skipped && audio && this._loopVerse >= 0) {
      const t = verseStartTime(this._map, this._loopVerse, this.duration())
      if (t != null) { audio.currentTime = t; audio.play().catch(() => {}); return }
    }
    if (repeat === "chapter" && audio) {
      audio.currentTime = 0
      this._loopVerse = 0
      audio.play().catch(() => {})
      return
    }
    if (this.state === "paused") this.setState("playing") // Next on the last verse while paused
    this.advance(info)
  }

  // Seamless-ish continuation: the next chapter was requested when this one
  // started, so by the time it ends the narration is usually cached and ready.
  async advance(info) {
    if (!info?.next || this.state !== "playing" || !listenOptions().continue) return this.reset()
    this.setState("loading")
    try {
      this._params = info.next
      const next = await this.fetchInfo(info.next)
      if (this.state !== "loading") return
      if (next.status === "ready") {
        this._turning = this.turnPage()
        await this.play(next)
        return
      }
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
    const handlers = {
      play: () => audio()?.play().catch(() => {}),
      pause: () => audio()?.pause(),
      stop: () => this.stop(),
      seekbackward: () => { const a = audio(); if (a) a.currentTime = Math.max(0, a.currentTime - 15) },
      seekforward: () => { const a = audio(); if (a) a.currentTime = Math.min(a.duration || 0, a.currentTime + 15) },
      previoustrack: () => this.stepVerse(-1),
      nexttrack: () => this.stepVerse(1)
    }
    for (const [ action, handler ] of Object.entries(handlers)) {
      try { navigator.mediaSession.setActionHandler(action, handler) } catch {}
    }
  }

  clearMediaSession() {
    if (!("mediaSession" in navigator)) return
    navigator.mediaSession.metadata = null
    navigator.mediaSession.playbackState = "none"
    for (const action of ["play", "pause", "stop", "seekbackward", "seekforward", "previoustrack", "nexttrack"]) {
      try { navigator.mediaSession.setActionHandler(action, null) } catch {}
    }
  }

  // ---- The phone's own voice, one verse at a time ----

  // In the Android app (1.0.3+), WebView has no speechSynthesis, so the app
  // reads aloud with the phone's own voice through window.BiblioRataNative.
  speakFallback() {
    const native = window.BiblioRataNative
    this.engine = native?.speak ? "native" : ("speechSynthesis" in window ? "speech" : null)
    if (!this.engine) {
      this.reset()
      this.notify("Listening isn't available right now. Please try again later.")
      return
    }
    this.buildMap(null)
    if (!this._map) return this.reset()

    if (this.engine === "native") {
      this._onNativeSpeech ??= (e) => this.nativeSpeech(e.detail)
      window.removeEventListener("native:speech", this._onNativeSpeech)
      window.addEventListener("native:speech", this._onNativeSpeech)
    }
    const from = Math.max(0, this.indexOfVerse(this._startVerse))
    this._startVerse = null
    this.setState("playing")
    this.armSleep()
    this.speakFrom(from)
  }

  speakFrom(i) {
    const map = this._map
    const gen = ++this._gen
    if (!map || this.state === "idle") return
    if (i >= map.verses.length) return this.chapterEnded()
    this.setVerse(i, true)
    const text = this.verseText(map.verses[i])
    if (!text) return this.verseSpoken(i)

    if (this.engine === "native") {
      this._nativeSaidAt = Date.now()
      this._nativeWaiting = true
      window.BiblioRataNative.speak(text)
      return
    }

    const synth = window.speechSynthesis
    const busy = synth.speaking || synth.pending
    synth.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = 0.92 * (Number(listenOptions().rate) || 1)
    utterance.pitch = 1
    utterance.onend = () => { if (gen === this._gen) this.verseSpoken(i) }
    utterance.onerror = (e) => {
      if (gen !== this._gen || e.error === "interrupted" || e.error === "canceled") return
      this.reset()
    }
    this._utterance = utterance // Chrome drops callbacks of utterances it garbage-collects
    // Chrome sometimes swallows a speak() that comes straight after cancel().
    const say = () => { if (gen === this._gen && this.state === "playing") synth.speak(utterance) }
    if (busy) setTimeout(say, 80)
    else say()
  }

  // Android's voice: "start" | "end" | "error" for each verse we hand it.
  nativeSpeech(what) {
    if (active !== this || this.engine !== "native") return
    if (what === "start") { this._nativeWaiting = false; return }
    if (what === "error") {
      this.reset()
      this.notify("This phone has no reading voice. Install one in Settings → Text-to-speech.")
      return
    }
    if (what !== "end" || this.state !== "playing") return
    // The verse we cut off to start this one also reports "end".
    if (this._nativeWaiting && Date.now() - this._nativeSaidAt < NATIVE_STALE_END_MS) return
    this._nativeWaiting = false
    this.verseSpoken(this._verse)
  }

  verseSpoken(i) {
    if (this.state !== "playing") return
    if (this._stopAfterVerse || this.checkSleep()) return this.stop()
    if (listenControls().repeat === "verse") return this.speakFrom(i)
    this.speakFrom(i + 1)
  }

  // The phone's voice reached the end of the page.
  chapterEnded() {
    const { repeat, sleep } = listenControls()
    if (sleep.mode === "chapter") { clearSleep(); return this.stop() }
    if (repeat === "chapter") return this.speakFrom(0)
    if (this.state === "paused") this.setState("playing")
    if (listenOptions().continue && this.turnPage({ always: true })) {
      this._turning = true
      this._gen++
      return
    }
    this.reset()
  }

  silenceSpeech() {
    this._gen++
    if (this.engine === "speech" && "speechSynthesis" in window) window.speechSynthesis.cancel()
    if (this.engine === "native") {
      this._nativeWaiting = true
      this._nativeSaidAt = Date.now()
      window.BiblioRataNative?.stopSpeaking?.()
    }
  }

  verseText(el) {
    const text = el.matches(".ps-verse-text") ? el : el.querySelector(".ps-verse-text")
    return text?.textContent.trim() || ""
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

  // ---- Sleep timer ----

  armSleep() {
    clearTimeout(this._sleepTimer)
    this._stopAfterVerse = false
    const { sleep } = listenControls()
    if (sleep.mode !== "time" || this.state === "idle") return
    this._sleepTimer = setTimeout(() => this.checkSleep(), sleepRemaining(sleep) + 50)
  }

  // True when the timer has run out (and the voice is being put to sleep).
  checkSleep() {
    const { sleep } = listenControls()
    if (sleep.mode !== "time" || sleepRemaining(sleep) > 0) return false
    clearSleep()
    this.fallAsleep()
    return true
  }

  // The server voice fades out; the phone's voice finishes its verse, then stops.
  fallAsleep() {
    if (this.engine !== "audio" || !this._audio || this.state !== "playing") {
      if (this.state === "playing" && this.engine !== "audio") { this._stopAfterVerse = true; return }
      return this.stop()
    }
    const audio = this._audio
    const from = audio.volume
    const began = Date.now()
    this.cancelFade()
    this._fade = setInterval(() => {
      const left = 1 - (Date.now() - began) / FADE_MS
      if (left <= 0 || this._audio !== audio) { this.cancelFade(); return this.stop() }
      audio.volume = Math.max(0, from * left)
    }, 100)
  }

  cancelFade() {
    if (!this._fade) return
    clearInterval(this._fade)
    this._fade = null
    if (this._audio) this._audio.volume = 1
  }

  // A chapter played for the first time has no verse timings yet (they are
  // made in the background within about 15 s): ask again until they arrive,
  // then switch from the estimate to the exact times mid-play.
  awaitTimings(info) {
    clearInterval(this._timingsPoll)
    this._timingsPoll = null
    if (info?.timings && Object.keys(info.timings).length) return
    const params = this._params
    if (!params) return
    let tries = 0
    this._timingsPoll = setInterval(async () => {
      if (this._info !== info || this.state === "idle" || ++tries > 12) { clearInterval(this._timingsPoll); this._timingsPoll = null; return }
      try {
        const fresh = await this.fetchInfo(params)
        if (fresh?.timings && Object.keys(fresh.timings).length && this._info === info) {
          info.timings = fresh.timings
          clearInterval(this._timingsPoll); this._timingsPoll = null
          this.buildMap(info)
          if (this._audio) this.onAudioTime(this._audio)
        }
      } catch { /* try again next time */ }
    }, 8000)
  }

  // "Keep going into the next chapter": turn this pane to the next chapter,
  // so the words (and the highlight) move on with the voice. The server voice
  // turns only when following along; the phone's voice always does (it reads
  // the page). Taps the same Next button a reader would, online or offline.
  turnPage({ always = false } = {}) {
    const button = this.element.querySelector("form.rd-pager-form.is-next button, form.rd-next-form button")
    if (!button || (!always && !listenOptions().follow)) return false
    this._turning = true
    button.click()
    return true
  }

  // ---- The verse map + follow along ----
  //
  // Which verses are on screen and where each starts in the narration (see
  // lib/listen_controls). Built for every engine (it drives previous / next /
  // repeat / Play from here); the verse being read lights up and stays in
  // view only with "Highlight and follow along". If the reader scrolls by
  // hand, following pauses for a few seconds.

  followVerses() {
    const chapter = this.hasButtonTarget ? this.buttonTarget.dataset.chapter : null
    const verses = Array.from(this.element.querySelectorAll(".ps-verse"))
      .filter((el) => el.querySelector(".ps-verse-text") && (!chapter || !el.dataset.chapter || el.dataset.chapter === String(chapter)))
    if (verses.length) return verses
    // The Today page: verse texts without verse markup.
    return Array.from(this.element.querySelectorAll(".ps-verse-text"))
  }

  buildMap(info) {
    this.clearMap()
    // Narration of a chapter that isn't on screen (continued without turning the page).
    if (info && this.hasButtonTarget && String(info.chapter) !== String(this.buttonTarget.dataset.chapter)) return
    const verses = this.followVerses()
    if (!verses.length) return
    const PAUSE = 12 // chars' worth of silence between verses
    let total = 0
    const starts = verses.map((el) => {
      const at = total
      total += this.verseText(el).length + PAUSE
      return at
    })
    // The narrator says a heading first ("John, chapter 3. King James Version.").
    const lead = info ? (info.voice === "human" ? `${info.book} chapter ${info.chapter}` : `${info.book}, chapter ${info.chapter}. ${info.translation_name || ""}.`).length + PAUSE : 0
    // Exact verse start times from the server (VerseTimings), when it has them.
    let timed = null
    if (info?.timings && Object.keys(info.timings).length) {
      timed = verses.map((el) => Number(info.timings[el.dataset.verseNum]))
      for (let i = 0; i < timed.length; i++) if (!Number.isFinite(timed[i])) timed[i] = i ? timed[i - 1] : 0
    }
    this._map = { verses, starts, total, lead, timed, highlight: !!listenOptions().follow, lit: -1, handAt: 0 }
    if (this._verse >= verses.length) this._verse = -1
    if (!this._map.highlight) return

    this._onHandScroll ??= () => { if (this._map) this._map.handAt = Date.now() }
    for (const target of [ this.scrollBox(), window ]) {
      target.addEventListener("wheel", this._onHandScroll, { passive: true })
      target.addEventListener("touchmove", this._onHandScroll, { passive: true })
    }
  }

  clearMap() {
    if (!this._map) return
    this._map.verses.forEach((el) => el.classList.remove("is-reading"))
    if (this._onHandScroll) {
      for (const target of [ this.scrollBox(), window ]) {
        target.removeEventListener("wheel", this._onHandScroll)
        target.removeEventListener("touchmove", this._onHandScroll)
      }
    }
    this._map = null
  }

  setVerse(i, force = false) {
    if (i === this._verse && !force) return
    this._verse = i
    this.markVerse(i)
    this.emit()
  }

  markVerse(i) {
    const map = this._map
    if (!map?.highlight || i === map.lit) return
    map.verses[map.lit]?.classList.remove("is-reading")
    map.lit = i
    const el = map.verses[i]
    if (!el) return
    el.classList.add("is-reading")
    if (Date.now() - map.handAt > 6000) this.bringIntoView(el)
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
    if (active === this) {
      this._gen++
      if ("speechSynthesis" in window) window.speechSynthesis.cancel()
      window.BiblioRataNative?.stopSpeaking?.()
    }
    this.reset()
  }

  reset() {
    this.clearMap()
    clearInterval(this._timingsPoll); this._timingsPoll = null
    clearTimeout(this._sleepTimer)
    this.cancelFade()
    this._turning = false
    this._stopAfterVerse = false
    this._gen++
    if (this._poll) { clearTimeout(this._poll); this._poll = null }
    this.releaseAudio()
    if (active === this) { this.clearMediaSession(); clearSleep() }
    this._armed = null
    this._verse = -1
    this._loopVerse = -1
    this._seekTo = null
    if (this._onNativeSpeech) window.removeEventListener("native:speech", this._onNativeSpeech)
    this.setState("idle")
    this.engine = null
    if (active === this) active = null
  }

  // Paused from the player, the lock screen or headphones: reflect it on the
  // button and in the Media Session, so the OS shows a Play control.
  setPaused(paused) {
    this.setState(paused ? "paused" : "playing")
    if (this.engine === "audio" && "mediaSession" in navigator) navigator.mediaSession.playbackState = paused ? "paused" : "playing"
  }

  releaseAudio() {
    if (!this._audio) return
    const audio = this._audio
    this._audio = null
    audio.onended = audio.onerror = audio.onpause = audio.onplay = audio.ontimeupdate = audio.onloadedmetadata = null
    audio.pause()
    audio.removeAttribute("src")
    audio.load()
  }

  setState(state) {
    this.state = state
    this.emit()
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

  // What's playing, for the player bar, the Listen sheet and Compare's pill.
  emit() {
    const d = this.hasButtonTarget ? this.buttonTarget.dataset : {}
    const meta = this.element.querySelector(".rd-pane-meta")?.dataset || {}
    const info = this.engine === "audio" ? this._info : null
    const verseEl = this._map?.verses[this._verse]
    window.dispatchEvent(new CustomEvent("listen:state", { detail: {
      pane: this.element.id,
      state: this.state,
      engine: this.engine,
      book: info?.book || this.element.querySelector(".rd-book")?.textContent.trim() || "",
      chapter: info?.chapter || d.chapter || "",
      verse: verseEl?.dataset.verseNum || null,
      translation: info?.translation || d.translation || meta.translationCode || "",
      canRate: this.engine !== "native",
      canStep: !!this._map || this.engine === "audio"
    } }))
  }
}
