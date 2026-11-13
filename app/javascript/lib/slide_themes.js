// Projection "Looks" — the slide templates the operator picks for the big
// screen (scripture, songs, thoughts, the logo and countdown slides).
//
// The pixels live in app/assets/stylesheets/slide_themes.css: each look is a
// block of --look-* custom properties on [data-look="<id>"], drawn with CSS
// gradients and inline SVG only, so every look works with no network at all.
// This registry is the list the picker shows plus the few choices CSS can't
// make from a custom property (where the reference sits).
//
// Prefs are kept on the device (localStorage, like the other screen prefs):
// per study (`ps-look:/studies/12`) and as this device's default
// (`ps-look:default`), which a study without its own choice starts from.
// Node-tested: test/javascript/slide_themes_test.mjs.

export const LOOKS = [
  { id: "vellum", name: "Vellum", blurb: "Warm parchment, classic serif", ref: "top", legacy: "vellum" },
  { id: "royal", name: "Royal Blue", blurb: "Deep blue, bold white, gold reference", ref: "bottom" },
  { id: "emerald", name: "Emerald", blurb: "Deep green with a soft sheen", ref: "top" },
  { id: "crimson", name: "Crimson Velvet", blurb: "Rich crimson, cream and gold", ref: "top" },
  { id: "majesty", name: "Royal Purple", blurb: "Purple and gold, for majesty", ref: "bottom" },
  { id: "dawn", name: "Dawn", blurb: "Indigo night breaking into sunrise", ref: "top" },
  { id: "night", name: "Night Sky", blurb: "Stars over deep navy", ref: "top" },
  { id: "glass", name: "Stained Glass", blurb: "Jewel light through leaded glass", ref: "top" },
  { id: "water", name: "Living Water", blurb: "Teal depths, clean modern type", ref: "bottom" },
  { id: "ink", name: "Ink", blurb: "Candle-dark, cream text", ref: "top", legacy: "ink" },
  { id: "paper", name: "Paper", blurb: "Clean white page, dark serif", ref: "top", legacy: "paper" },
  { id: "black", name: "Minimal Black", blurb: "Pure black, white sans — LED walls", ref: "bottom" },
  { id: "contrast", name: "High Contrast", blurb: "Black on white for bright halls", ref: "top" }
]

export const DEFAULT_LOOK = "vellum"
export const BACKGROUNDS = [ "look", "image", "video" ]
export const TRANSITIONS = [ "fade", "cut" ]
const DEFAULT_PREFS = { look: DEFAULT_LOOK, bg: "look", dim: 0.35, transition: "fade" }
const PREFIX = "ps-look:"
const LEGACY_SCREEN_KEY = "ps-screen-prefs" // presentation_controller's theme/scale/weight

export function lookById(id) {
  return LOOKS.find((l) => l.id === id) || null
}

// Any stored/broadcast value → a safe, complete prefs object.
export function normalizePrefs(raw) {
  const p = raw && typeof raw === "object" ? raw : {}
  const dim = Number(p.dim)
  return {
    look: lookById(p.look) ? p.look : DEFAULT_PREFS.look,
    bg: BACKGROUNDS.includes(p.bg) ? p.bg : DEFAULT_PREFS.bg,
    dim: Number.isFinite(dim) ? Math.min(0.8, Math.max(0, Math.round(dim * 100) / 100)) : DEFAULT_PREFS.dim,
    transition: TRANSITIONS.includes(p.transition) ? p.transition : DEFAULT_PREFS.transition
  }
}

function readJSON(storage, key) {
  try {
    const raw = storage?.getItem(key)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

// The study's own choice, else this device's default, else the old
// Vellum/Ink/Paper theme the operator had picked before looks existed.
export function loadPrefs(storage, scope) {
  const own = scope && readJSON(storage, PREFIX + scope)
  if (own) return normalizePrefs(own)
  const fallback = readJSON(storage, PREFIX + "default")
  if (fallback) return normalizePrefs(fallback)
  const legacy = readJSON(storage, LEGACY_SCREEN_KEY)
  return normalizePrefs({ look: legacy?.theme })
}

// A choice is remembered for this study and becomes the device's default.
export function savePrefs(storage, scope, prefs) {
  const clean = normalizePrefs(prefs)
  try {
    if (scope) storage?.setItem(PREFIX + scope, JSON.stringify(clean))
    storage?.setItem(PREFIX + "default", JSON.stringify(clean))
  } catch { /* private mode / quota */ }
  return clean
}

// ---- countdown --------------------------------------------------------------

// When a countdown started at `now` ends: `minutes` from now, or the next time
// the clock reads `until` ("10:30", 24-hour, today or else tomorrow).
export function countdownEnd({ minutes, until } = {}, now = Date.now()) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(until || "").trim())
  if (m) {
    const target = new Date(now)
    target.setHours(Number(m[1]), Number(m[2]), 0, 0)
    if (target.getTime() <= now) target.setDate(target.getDate() + 1)
    return target.getTime()
  }
  const mins = Number(minutes)
  if (!Number.isFinite(mins) || mins <= 0) return null
  return now + Math.round(Math.min(mins, 24 * 60) * 60) * 1000
}

// 299_400 → "05:00" (rounded up, so the screen never shows 00:00 early);
// past an hour → "1:04:59".
export function formatClock(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const pad = (n) => String(n).padStart(2, "0")
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

// ---- alerts -----------------------------------------------------------------

export const ALERT_MAX = 160

export function cleanAlert(text) {
  return String(text || "").replace(/\s+/g, " ").trim().slice(0, ALERT_MAX)
}
