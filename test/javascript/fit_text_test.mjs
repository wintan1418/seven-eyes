// node --test test/javascript — shrink-to-fit for projected words
// (app/javascript/lib/fit_text.js): long verses never overflow, short ones fill.
import { test } from "node:test"
import assert from "node:assert/strict"
import { fitFontSize, screenCap } from "../../app/javascript/lib/fit_text.js"

// A pretend screen: `chars` of text in a box, average glyph 0.5em wide, line
// height 1.3em — the text fits when its wrapped lines fit the height.
function box({ width, height, chars }) {
  return (px) => {
    const perLine = Math.max(1, Math.floor(width / (px * 0.5)))
    const lines = Math.ceil(chars / perLine)
    return lines * px * 1.3 <= height
  }
}

test("a short verse grows to the cap", () => {
  assert.equal(fitFontSize({ min: 18, max: 120, fits: box({ width: 1700, height: 900, chars: 40 }) }), 120)
})

test("a long verse shrinks until it fits — and does fit", () => {
  const fits = box({ width: 1700, height: 860, chars: 600 })
  const size = fitFontSize({ min: 18, max: 120, fits })
  assert.ok(size < 120 && size > 18, `size ${size}`)
  assert.ok(fits(size), "the chosen size fits")
  assert.ok(!fits(size + 1), "and is close to the largest that does")
})

test("never below the floor, even when nothing fits", () => {
  assert.equal(fitFontSize({ min: 18, max: 120, fits: () => false }), 18)
})

test("min above max is handled", () => {
  assert.equal(fitFontSize({ min: 50, max: 30, fits: () => true }), 50)
})

test("the cap follows the screen and the A−/A+ scale", () => {
  assert.equal(Math.round(screenCap(1920, 1080)), 119) // 11% of a 1080p height
  assert.ok(screenCap(1920, 1080, 1.3) > screenCap(1920, 1080))
  assert.ok(screenCap(800, 1080) < screenCap(1920, 1080), "a tall narrow window is capped by its width")
})
