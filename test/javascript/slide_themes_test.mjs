// node --test test/javascript — projection Looks (app/javascript/lib/slide_themes.js
// + app/assets/stylesheets/slide_themes.css): the registry, the prefs kept on
// the device, the countdown clock, and every look's legibility — its words and
// its reference line must read from the back of a hall.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import {
  LOOKS, DEFAULT_LOOK, lookById, normalizePrefs, loadPrefs, savePrefs,
  countdownEnd, formatClock, cleanAlert, ALERT_MAX
} from "../../app/javascript/lib/slide_themes.js"

const css = readFileSync(new URL("../../app/assets/stylesheets/slide_themes.css", import.meta.url), "utf8")

function memoryStorage(seed = {}) {
  const data = new Map(Object.entries(seed))
  return {
    getItem: (k) => (data.has(k) ? data.get(k) : null),
    setItem: (k, v) => data.set(k, String(v)),
    data
  }
}

// --look-* tokens of one look's CSS block.
function tokens(id) {
  const m = css.match(new RegExp(`\\[data-look="${id}"\\]\\s*\\{([\\s\\S]*?)\\n\\}`))
  assert.ok(m, `slide_themes.css has no [data-look="${id}"] block`)
  const out = {}
  for (const t of m[1].matchAll(/--([\w-]+):\s*([^;]+);/g)) out[t[1]] = t[2].trim()
  return out
}

function luminance(hex) {
  const h = hex.replace("#", "")
  const full = h.length === 3 ? h.split("").map((c) => c + c).join("") : h
  const [ r, g, b ] = [ 0, 2, 4 ].map((i) => parseInt(full.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

function contrast(a, b) {
  const [ hi, lo ] = [ luminance(a), luminance(b) ].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

test("about a dozen distinct looks, with names, and the old three kept", () => {
  assert.ok(LOOKS.length >= 12, `only ${LOOKS.length} looks`)
  const ids = LOOKS.map((l) => l.id)
  assert.equal(new Set(ids).size, ids.length, "look ids are unique")
  assert.equal(new Set(LOOKS.map((l) => l.name)).size, LOOKS.length, "look names are unique")
  for (const legacy of [ "vellum", "ink", "paper" ]) assert.equal(lookById(legacy)?.legacy, legacy)
  assert.ok(lookById(DEFAULT_LOOK))
  for (const look of LOOKS) {
    assert.ok([ "top", "bottom" ].includes(look.ref), `${look.id}: reference top or bottom`)
    assert.ok(look.blurb.length > 0)
  }
})

test("every look is drawn by CSS, offline (no image URLs but inline SVG)", () => {
  for (const look of LOOKS) {
    const t = tokens(look.id)
    for (const key of [ "look-base", "look-tone", "look-fg", "look-accent", "look-font", "look-num" ]) {
      assert.ok(t[key], `${look.id} sets --${key}`)
    }
  }
  const urls = [ ...css.matchAll(/url\(\s*"([^"]+)"/g) ].map((m) => m[1])
  assert.ok(urls.length > 0)
  for (const url of urls) assert.match(url, /^data:image\/svg\+xml/, `only inline SVG — found ${url}`)
  assert.doesNotMatch(css, /url\(\s*['"]?(https?:|\/)/, "no hotlinked or server images")
})

test("words and reference stay legible on every look (WCAG contrast)", () => {
  for (const look of LOOKS) {
    const t = tokens(look.id)
    const words = contrast(t["look-fg"], t["look-tone"])
    const ref = contrast(t["look-accent"], t["look-tone"])
    const num = contrast(t["look-num"], t["look-tone"])
    assert.ok(words >= 7, `${look.id}: words ${words.toFixed(1)}:1 — want 7:1`)
    assert.ok(ref >= 4.5, `${look.id}: reference ${ref.toFixed(1)}:1 — want 4.5:1`)
    assert.ok(num >= 3, `${look.id}: verse numbers ${num.toFixed(1)}:1 — want 3:1`)
  }
})

test("normalizePrefs keeps only known values", () => {
  assert.deepEqual(normalizePrefs(null), { look: "vellum", bg: "look", dim: 0.35, transition: "fade" })
  assert.deepEqual(normalizePrefs({ look: "royal", bg: "video", dim: 5, transition: "cut" }),
    { look: "royal", bg: "video", dim: 0.8, transition: "cut" })
  assert.deepEqual(normalizePrefs({ look: "nope", bg: "gif", dim: "x", transition: "wipe" }),
    { look: "vellum", bg: "look", dim: 0.35, transition: "fade" })
})

test("a look is kept per study and becomes the device default", () => {
  const storage = memoryStorage()
  savePrefs(storage, "/studies/1", { look: "royal" })
  assert.equal(loadPrefs(storage, "/studies/1").look, "royal")
  assert.equal(loadPrefs(storage, "/studies/2").look, "royal", "another study starts from the default")
  savePrefs(storage, "/studies/2", { look: "emerald", transition: "cut" })
  assert.equal(loadPrefs(storage, "/studies/1").look, "royal", "study 1 keeps its own")
  assert.equal(loadPrefs(storage, "/studies/3").look, "emerald")
  assert.equal(loadPrefs(storage, "/studies/3").transition, "cut")
})

test("the old Ink / Paper theme carries over before any look was picked", () => {
  const storage = memoryStorage({ "ps-screen-prefs": JSON.stringify({ theme: "ink", scale: 1.2 }) })
  assert.equal(loadPrefs(storage, "/studies/9").look, "ink")
  assert.equal(loadPrefs(memoryStorage(), "/studies/9").look, "vellum")
})

test("broken storage never breaks the screen", () => {
  const throwing = { getItem() { throw new Error("denied") }, setItem() { throw new Error("denied") } }
  assert.equal(loadPrefs(throwing, "/studies/1").look, "vellum")
  assert.equal(savePrefs(throwing, "/studies/1", { look: "night" }).look, "night")
  assert.equal(loadPrefs(memoryStorage({ "ps-look:default": "{not json" }), "/x").look, "vellum")
})

test("countdown: minutes from now, or until a time (tomorrow if it has passed)", () => {
  const now = new Date(2026, 10, 15, 9, 55, 0).getTime()
  assert.equal(countdownEnd({ minutes: 5 }, now), now + 5 * 60_000)
  assert.equal(countdownEnd({ minutes: 0.5 }, now), now + 30_000)
  assert.equal(countdownEnd({ minutes: 0 }, now), null)
  assert.equal(countdownEnd({ minutes: "abc" }, now), null)
  assert.equal(countdownEnd({ until: "10:00" }, now), new Date(2026, 10, 15, 10, 0, 0).getTime())
  assert.equal(countdownEnd({ until: "09:00", minutes: 5 }, now), new Date(2026, 10, 16, 9, 0, 0).getTime())
})

test("the clock never shows 00:00 early, and goes past an hour", () => {
  assert.equal(formatClock(300_000), "05:00")
  assert.equal(formatClock(299_001), "05:00")
  assert.equal(formatClock(299_000), "04:59")
  assert.equal(formatClock(500), "00:01")
  assert.equal(formatClock(0), "00:00")
  assert.equal(formatClock(-4000), "00:00")
  assert.equal(formatClock(3_899_000), "1:04:59")
})

test("alerts are one tidy line, capped", () => {
  assert.equal(cleanAlert("  Parent of\n child 12  "), "Parent of child 12")
  assert.equal(cleanAlert("x".repeat(500)).length, ALERT_MAX)
  assert.equal(cleanAlert(null), "")
})
