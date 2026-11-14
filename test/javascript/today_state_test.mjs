// node --test test/javascript — the Today flow's device state
// (app/javascript/lib/today_state.js): the Lagos calendar, streaks, merging.
import { test } from "node:test"
import assert from "node:assert/strict"
import { lagosDate, lagosHour, daypart, greeting, addDays, streakFrom, mergeDates } from "../../app/javascript/lib/today_state.js"

test("the Lagos calendar turns over at midnight West Africa Time (UTC+1)", () => {
  assert.equal(lagosDate(new Date("2026-11-14T22:59:00Z")), "2026-11-14")
  assert.equal(lagosDate(new Date("2026-11-14T23:00:00Z")), "2026-11-15")
  assert.equal(lagosHour(new Date("2026-11-14T05:30:00Z")), 6)
})

test("dayparts and greetings match the server's Daypart", () => {
  assert.equal(daypart(4), "dawn")
  assert.equal(daypart(9), "dawn")
  assert.equal(daypart(10), "day")
  assert.equal(daypart(16), "day")
  assert.equal(daypart(17), "evening")
  assert.equal(daypart(2), "evening")
  assert.equal(greeting(7), "Good morning")
  assert.equal(greeting(13), "Good afternoon")
  assert.equal(greeting(22), "Good evening")
})

test("a streak runs back from today, or from yesterday while today is open", () => {
  const today = "2026-11-14"
  assert.equal(streakFrom([], today), 0)
  assert.equal(streakFrom([ today ], today), 1)
  assert.equal(streakFrom([ today, "2026-11-13", "2026-11-12" ], today), 3)
  assert.equal(streakFrom([ "2026-11-13", "2026-11-12" ], today), 2, "today not done yet keeps the streak")
  assert.equal(streakFrom([ today, "2026-11-12" ], today), 1, "a gap breaks it")
  assert.equal(streakFrom([ "2026-11-12" ], today), 0)
  assert.equal(streakFrom([ "2026-03-01", "2026-02-28" ], "2026-03-01"), 2, "across a month end")
})

test("server and device days merge without duplicates, newest first", () => {
  assert.deepEqual(mergeDates([ "2026-11-12", "2026-11-14" ], [ "2026-11-14", "2026-11-13", "junk" ]),
    [ "2026-11-14", "2026-11-13", "2026-11-12" ])
  assert.equal(addDays("2026-12-31", 1), "2027-01-01")
})
