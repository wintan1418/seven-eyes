// The Audio Bible's player controls that live for one listening session:
// repeat (off / this verse / this chapter) and the sleep timer (off / end of
// the chapter / N minutes). Shared by the reader controller (which acts on
// them) and the player bar (which shows them); a change is announced as a
// window `listen:controls` event. Speed is not here: it is remembered on the
// device with the Listen sheet's other choices (listen_options_controller).
//
// The pure helpers below (verse maps, rates, time labels) are node-tested
// (test/javascript/listen_controls_test.mjs).

export const RATES = [ 0.75, 1, 1.25, 1.5, 2 ]
export const REPEAT_MODES = [ "off", "verse", "chapter" ]
export const SLEEP_MINUTES = [ 5, 10, 15, 30, 45, 60 ]

const state = { repeat: "off", sleep: { mode: "off", until: 0 } }

export function listenControls() {
  return { repeat: state.repeat, sleep: { ...state.sleep } }
}

export function setRepeat(mode) {
  state.repeat = REPEAT_MODES.includes(mode) ? mode : "off"
  announce()
}

// mode: "off" | "chapter" | a number of minutes.
export function setSleep(mode, now = Date.now()) {
  const minutes = Number(mode)
  if (mode === "chapter") state.sleep = { mode: "chapter", until: 0 }
  else if (Number.isFinite(minutes) && minutes > 0) state.sleep = { mode: "time", minutes, until: now + minutes * 60000 }
  else state.sleep = { mode: "off", until: 0 }
  announce()
}

export function clearSleep() {
  if (state.sleep.mode === "off") return
  setSleep("off")
}

// Milliseconds left on a minutes timer (0 when it has run out or isn't set).
export function sleepRemaining(sleep = state.sleep, now = Date.now()) {
  if (sleep?.mode !== "time") return 0
  return Math.max(0, sleep.until - now)
}

export function nextRepeat(mode) {
  const i = REPEAT_MODES.indexOf(mode)
  return REPEAT_MODES[(i + 1) % REPEAT_MODES.length]
}

// 0.75 → 1 → 1.25 → 1.5 → 2 → 0.75; an unknown speed starts again at 1.
export function nextRate(rate) {
  const i = RATES.indexOf(Number(rate))
  return i < 0 ? 1 : RATES[(i + 1) % RATES.length]
}

export function rateLabel(rate) {
  return `${Number(rate) || 1}×`
}

// "4:05", "59:59", "1:00:00"
export function clockLabel(ms) {
  const total = Math.ceil(Math.max(0, ms) / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const pad = (n) => String(n).padStart(2, "0")
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

// ---- Verse maps: where each verse starts in a chapter's narration ----
//
// map = { starts, total, lead, timed }:
//   timed  — exact start seconds per verse from the server (VerseTimings), or null
//   starts — otherwise, each verse's start in characters (plus a pause per
//            verse), total = all of them, lead = the spoken heading first.
// With no timings the position is estimated from how far through the audio
// we are, weighted by verse length.

export function verseIndexAt(map, seconds, duration) {
  if (!map) return -1
  if (map.timed?.length) {
    const now = seconds + 0.15 // light the verse as its first word starts
    if (now < map.timed[0]) return -1
    let i = map.timed.length - 1
    while (i > 0 && map.timed[i] > now) i--
    return i
  }
  if (!duration || !map.starts?.length) return -1
  const spoken = (seconds / duration) * (map.lead + map.total) - map.lead
  if (spoken < 0) return -1
  let i = map.starts.length - 1
  while (i > 0 && map.starts[i] > spoken) i--
  return i
}

// Seconds into the narration where verse i starts (null when unknown).
export function verseStartTime(map, i, duration) {
  if (!map || i < 0) return null
  if (map.timed?.length) {
    if (i >= map.timed.length) return null
    return Math.max(0, map.timed[i])
  }
  if (!duration || i >= map.starts.length) return null
  return Math.max(0, ((map.lead + map.starts[i]) / (map.lead + map.total)) * duration)
}

function announce() {
  if (typeof window === "undefined" || typeof CustomEvent === "undefined") return
  window.dispatchEvent(new CustomEvent("listen:controls", { detail: listenControls() }))
}
