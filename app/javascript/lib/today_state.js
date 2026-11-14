// "Today" (Home's guided daily flow) on the device: which days were finished
// and how far the reader got today. Pure functions plus a thin localStorage
// layer, so Home and the flow page agree with no network at all.
//
// Signed-in readers: the server's days (data-today-dates) merged with the
// device's own (a day finished offline waits in the outbox). Guests: only the
// device — Home invites them to sign up to keep the streak.
//
// One calendar for everyone: the Word for Today turns over in Africa/Lagos.
export const TIME_ZONE = "Africa/Lagos"
const KEY = "bibliorata:today:"
const KEEP_DAYS = 120

// "2026-11-14" for an instant, on the Lagos calendar.
export function lagosDate(now = new Date()) {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit" }).format(now)
  } catch {
    // No time-zone data: Lagos is UTC+1 all year (no daylight saving).
    return new Date(now.getTime() + 3600_000).toISOString().slice(0, 10)
  }
}

export function lagosHour(now = new Date()) {
  try {
    const h = new Intl.DateTimeFormat("en-GB", { timeZone: TIME_ZONE, hour: "2-digit", hourCycle: "h23" }).format(now)
    return Number.parseInt(h, 10) % 24
  } catch {
    return (now.getUTCHours() + 1) % 24
  }
}

// Same boundaries as Daypart (app/services/daypart.rb).
export function daypart(hour) {
  if (hour >= 4 && hour <= 9) return "dawn"
  if (hour >= 10 && hour <= 16) return "day"
  return "evening"
}

export function greeting(hour) {
  if (hour >= 4 && hour <= 11) return "Good morning"
  if (hour >= 12 && hour <= 16) return "Good afternoon"
  return "Good evening"
}

// ISO date arithmetic without time zones.
export function addDays(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

// Consecutive days back from today — or from yesterday while today isn't done
// (a morning visit never shows a broken streak). Matches DailyCompletion.
export function streakFrom(dates, today) {
  const set = new Set(dates)
  let day = set.has(today) ? today : addDays(today, -1)
  let count = 0
  while (set.has(day)) { count++; day = addDays(day, -1) }
  return count
}

export function mergeDates(...lists) {
  return [ ...new Set(lists.flat().filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d))) ].sort().reverse()
}

// ---- the device copy ----------------------------------------------------------

function read(owner) {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY + owner) || "{}")
    return { done: Array.isArray(raw.done) ? raw.done : [], step: raw.step || null }
  } catch {
    return { done: [], step: null }
  }
}

function write(owner, state) {
  try { localStorage.setItem(KEY + owner, JSON.stringify(state)) } catch { /* private mode: still works this visit */ }
}

export function deviceState(owner) { return read(owner) }

export function markDone(owner, date) {
  const state = read(owner)
  state.done = mergeDates(state.done, [ date ]).slice(0, KEEP_DAYS)
  state.step = null
  write(owner, state)
  return state
}

// How far into today's flow the reader got (Home's Continue rail shows it).
export function saveStep(owner, date, index, total) {
  const state = read(owner)
  state.step = { date, index, total }
  write(owner, state)
}

export function stepFor(owner, date) {
  const step = read(owner).step
  return step && step.date === date ? step : null
}

// Everything a page shows: is today done, and the streak.
export function todayStatus({ owner, serverDates = [], today = lagosDate() }) {
  const dates = mergeDates(serverDates, read(owner).done)
  return { today, done: dates.includes(today), streak: streakFrom(dates, today), dates }
}
