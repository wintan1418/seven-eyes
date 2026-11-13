// The song bank's songs, kept on the device (IndexedDB meta "songLibrary") so
// songs can be found and queued with no signal. GET /studies/:id/setlist/library
// gives the built-in public-domain hymnal plus the songs this account has queued.
// The song bank (song_bank_controller) reads it; "Get ready for Sunday" refreshes it.
import { getMeta, setMeta } from "./offline/db"
import { isNetworkSlow, quickFetch } from "./offline/network"

export { searchSongs } from "./song_search"

const LIBRARY_META = "songLibrary"

export function cachedSongs() {
  return getMeta(LIBRARY_META).catch(() => null)
}

// The server's list (saved on the device), or null when it can't be reached.
export async function refreshSongs(url, { timeoutMs = 4000 } = {}) {
  if (!url || navigator.onLine === false || isNetworkSlow()) return null
  try {
    const { res, body } = await quickFetch(url, { headers: { Accept: "application/json" } }, { timeoutMs, read: "json" })
    if (!res.ok || !Array.isArray(body?.songs)) return null
    await setMeta(LIBRARY_META, body.songs).catch(() => {})
    return body.songs
  } catch {
    return null
  }
}
