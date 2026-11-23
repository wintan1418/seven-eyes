// node --test — the device's half of "a queue is a service that happened on a
// day" (app/javascript/lib/service_day.js): the app's calendar, the coming
// Sunday, and when the preach console offers to start fresh.
import { test } from "node:test"
import assert from "node:assert/strict"
import { serviceToday, nextSunday, laterDay, bannerState, longDay, serviceName } from "../../app/javascript/lib/service_day.js"

test("the app's calendar is Lagos: 23:30 UTC on Saturday is already Sunday there", () => {
  assert.equal(serviceToday(new Date("2026-11-21T23:30:00Z")), "2026-11-22")
  assert.equal(serviceToday(new Date("2026-11-22T22:59:00Z")), "2026-11-22")
  assert.equal(serviceToday(new Date("2026-11-22T23:00:00Z")), "2026-11-23")
})

test("the coming Sunday is today on a Sunday, else the next one (across months and years)", () => {
  assert.equal(nextSunday("2026-11-22"), "2026-11-22")
  assert.equal(nextSunday("2026-11-23"), "2026-11-29")
  assert.equal(nextSunday("2026-11-28"), "2026-11-29")
  assert.equal(nextSunday("2026-12-28"), "2027-01-03")
  assert.equal(nextSunday("nonsense"), null)
})

test("laterDay takes the later date and ignores blanks", () => {
  assert.equal(laterDay("2026-11-15", "2026-11-22"), "2026-11-22")
  assert.equal(laterDay(null, "2026-11-22"), "2026-11-22")
  assert.equal(laterDay("2026-11-22", ""), "2026-11-22")
  assert.equal(laterDay(null, undefined), null)
})

test("the banner shows the day after a service, not on the day itself", () => {
  const base = { servedOn: "2026-11-22", items: 21 }
  assert.equal(bannerState({ ...base, today: "2026-11-22" }).show, false)
  const after = bannerState({ ...base, today: "2026-11-23" })
  assert.equal(after.show, true)
  assert.equal(after.servedOn, "2026-11-22")
  assert.equal(after.nextSunday, "2026-11-29")
})

test("no banner: never served, an empty queue, or already answered for that service", () => {
  assert.equal(bannerState({ servedOn: null, items: 4, today: "2026-11-23" }).show, false)
  assert.equal(bannerState({ servedOn: "2026-11-22", items: 0, today: "2026-11-23" }).show, false)
  assert.equal(bannerState({ servedOn: "2026-11-22", dismissedFor: "2026-11-22", items: 4, today: "2026-11-23" }).show, false)
  // Kept last week, served again since: it asks again after this service.
  assert.equal(bannerState({ servedOn: "2026-11-22", dismissedFor: "2026-11-15", items: 4, today: "2026-11-23" }).show, true)
})

test("a service this device ran today (not synced yet) beats an older date on a saved page", () => {
  const state = bannerState({ servedOn: "2026-11-15", deviceServedOn: "2026-11-22", items: 4, today: "2026-11-22" })
  assert.equal(state.show, false)
  assert.equal(state.servedOn, "2026-11-22")
})

test("dates read the way a church says them", () => {
  assert.equal(longDay("2026-11-22"), "Sunday 22 November")
  assert.equal(longDay("2026-11-29"), "Sunday 29 November")
  assert.equal(serviceName("2026-11-22"), "Service · 22 Nov 2026")
  assert.equal(longDay(null), "")
})
