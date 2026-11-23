// A queue as a service that happened on a day — the device's half of
// Study::Serving. No DOM, no IndexedDB, so node can test it
// (test/javascript/service_day_test.mjs).
//
// Dates are "YYYY-MM-DD" on the app's calendar (Lagos, like Word for Today —
// there is no per-user time zone yet), so a service at 23:30 and one at 00:30
// fall on the days the church would say.
//
//   serviceToday(now)            today on the app's calendar
//   nextSunday(day)              the coming Sunday (the day itself on a Sunday)
//   laterDay(a, b)               the later of two dates (either may be blank)
//   bannerState({ … })           should the console offer "Start fresh"?
//   longDay(day)                 "Sunday 22 November"
import { lagosDate } from "./today_state.js"

export const serviceToday = (now = new Date()) => lagosDate(now)

const parse = (day) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day || ""))
  return m ? new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]))) : null
}
const iso = (date) => date.toISOString().slice(0, 10)

export function nextSunday(day = serviceToday()) {
  const date = parse(day)
  if (!date) return null
  date.setUTCDate(date.getUTCDate() + ((7 - date.getUTCDay()) % 7))
  return iso(date)
}

export function laterDay(a, b) {
  const x = parse(a) ? a : null
  const y = parse(b) ? b : null
  if (!x) return y
  if (!y) return x
  return x >= y ? x : y
}

// servedOn       the day the server says the queue was last served (page data)
// deviceServedOn the day this device last sent "served" (may not have synced)
// dismissedFor   the served day the operator already answered (Keep / Start fresh)
// items          how many items the queue holds now
export function bannerState({ servedOn = null, deviceServedOn = null, dismissedFor = null, items = 0, today = serviceToday() }) {
  const served = laterDay(servedOn, deviceServedOn)
  const show = !!served && served < today && served !== dismissedFor && items > 0
  return { show, servedOn: served, nextSunday: nextSunday(today) }
}

const WEEKDAYS = [ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" ]
const MONTHS = [ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" ]

export function longDay(day) {
  const date = parse(day)
  if (!date) return ""
  return `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`
}

// "Service · 22 Nov 2026" — the archived copy's name (Study.service_name).
export function serviceName(day) {
  const date = parse(day)
  if (!date) return "Service"
  return `Service · ${date.getUTCDate()} ${MONTHS[date.getUTCMonth()].slice(0, 3)} ${date.getUTCFullYear()}`
}
