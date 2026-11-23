// node --test test/javascript — the Audio Bible player's controls
// (app/javascript/lib/listen_controls.js): speeds, repeat, sleep timer, and
// finding verses in a chapter's narration.
import { test } from "node:test"
import assert from "node:assert/strict"
import {
  RATES, nextRate, rateLabel, nextRepeat, setRepeat, setSleep, clearSleep, listenControls,
  sleepRemaining, clockLabel, verseIndexAt, verseStartTime
} from "../../app/javascript/lib/listen_controls.js"

test("speed cycles 0.75 → 1 → 1.25 → 1.5 → 2 and round again", () => {
  assert.deepEqual(RATES, [ 0.75, 1, 1.25, 1.5, 2 ])
  assert.equal(nextRate(0.75), 1)
  assert.equal(nextRate(1.5), 2)
  assert.equal(nextRate(2), 0.75)
  assert.equal(nextRate("1.25"), 1.5, "stored speeds may be strings")
  assert.equal(nextRate(3), 1, "an unknown speed starts again at normal")
  assert.equal(rateLabel(2), "2×")
  assert.equal(rateLabel(undefined), "1×")
})

test("repeat cycles off → this verse → this chapter → off", () => {
  assert.equal(nextRepeat("off"), "verse")
  assert.equal(nextRepeat("verse"), "chapter")
  assert.equal(nextRepeat("chapter"), "off")
  setRepeat("verse")
  assert.equal(listenControls().repeat, "verse")
  setRepeat("nonsense")
  assert.equal(listenControls().repeat, "off")
})

test("the sleep timer counts down minutes, or waits for the end of the chapter", () => {
  const now = 1_000_000
  setSleep("15", now)
  const { sleep } = listenControls()
  assert.equal(sleep.mode, "time")
  assert.equal(sleep.minutes, 15)
  assert.equal(sleepRemaining(sleep, now + 60_000), 14 * 60_000)
  assert.equal(sleepRemaining(sleep, now + 16 * 60_000), 0)
  setSleep("chapter", now)
  assert.equal(listenControls().sleep.mode, "chapter")
  assert.equal(sleepRemaining(listenControls().sleep, now), 0)
  clearSleep()
  assert.equal(listenControls().sleep.mode, "off")
  setSleep("off", now)
  assert.equal(listenControls().sleep.mode, "off")
})

test("time left reads like a clock", () => {
  assert.equal(clockLabel(0), "0:00")
  assert.equal(clockLabel(4 * 60_000 + 5_000), "4:05")
  assert.equal(clockLabel(59 * 60_000 + 59_500), "1:00:00")
  assert.equal(clockLabel(1500), "0:02", "rounds up so it never shows 0:00 while running")
})

test("with server timings, verses are found (and jumped to) by their exact start", () => {
  const map = { timed: [ 2, 5, 9 ], starts: [ 0, 10, 20 ], total: 30, lead: 0 }
  assert.equal(verseIndexAt(map, 0, 12), -1, "the heading is still being read")
  assert.equal(verseIndexAt(map, 1.9, 12), 0, "lit just before the first word")
  assert.equal(verseIndexAt(map, 6, 12), 1)
  assert.equal(verseIndexAt(map, 11, 12), 2)
  assert.equal(verseStartTime(map, 1, 12), 5)
  assert.equal(verseStartTime(map, 3, 12), null)
})

test("without timings, verse positions are estimated by length after the heading", () => {
  // heading 10 chars, verses of 30 and 60 chars: 100 chars over 100 seconds.
  const map = { timed: null, starts: [ 0, 30 ], total: 90, lead: 10 }
  assert.equal(verseIndexAt(map, 5, 100), -1)
  assert.equal(verseIndexAt(map, 20, 100), 0)
  assert.equal(verseIndexAt(map, 45, 100), 1)
  assert.equal(verseStartTime(map, 0, 100), 10)
  assert.equal(verseStartTime(map, 1, 100), 40)
  assert.equal(verseStartTime(map, 1, 0), null, "unknown length: unknown position")
  assert.equal(verseIndexAt(null, 5, 100), -1)
})
