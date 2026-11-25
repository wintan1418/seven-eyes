// "This queue went live today" — told to the server once per study per day
// (Study::Serving#mark_served!), through the outbox so it works with no signal
// and never holds up the screen. The device remembers the day it last sent it
// (meta "served:<study>"), which also tells the console's Start fresh banner
// that today's service is this one even before the ping has synced.
import { getMeta, setMeta } from "./db"
import { queueServed, queueServiceKeep } from "./outbox"
import { serviceToday } from "../service_day"

const sentToday = new Set() // "study|day": no IndexedDB read for every slide

export const servedKey = (studyId) => `served:${studyId}`
export const dismissedKey = (studyId) => `serviceDismissed:${studyId}`

export async function markServed(studyId, owner, now = new Date(), name = null) {
  if (!studyId || !owner || owner === "guest") return false
  const day = serviceToday(now)
  const memo = `${studyId}|${day}`
  if (sentToday.has(memo)) return false
  sentToday.add(memo)
  try {
    if ((await getMeta(servedKey(studyId))) === day) return false
    await setMeta(servedKey(studyId), day)
    await queueServed(studyId, now.toISOString(), owner, name)
    return true
  } catch {
    sentToday.delete(memo) // no IndexedDB: try again next time
    return false
  }
}

export async function deviceServedOn(studyId) {
  try { return (await getMeta(servedKey(studyId))) || null } catch { return null }
}

export async function dismissedFor(studyId) {
  try { return (await getMeta(dismissedKey(studyId))) || null } catch { return null }
}

// The operator answered the banner for the service on `servedOn` (Keep using
// it, or Start fresh); null forgets it (Undo).
export async function setDismissed(studyId, servedOn) {
  try { await setMeta(dismissedKey(studyId), servedOn || null) } catch { /* no IndexedDB */ }
}

export async function keepForNextService(studyId, servedOn, owner) {
  await setDismissed(studyId, servedOn)
  if (owner && owner !== "guest") await queueServiceKeep(studyId, owner).catch(() => {})
}
