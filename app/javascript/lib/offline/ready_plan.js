// The pure decisions behind "always ready offline" (ready.js wires them to
// IndexedDB, the service worker and the network). No browser globals, so
// test/javascript/ready_plan_test.mjs runs them under node.

export const PREPARE_EVERY_MS = 24 * 60 * 60 * 1000 // once a day per reader and device

// Should this page load (re)prepare the device? Not for guests, not with no
// (or a dead) network, not in the projector/stage windows, and at most once a
// day unless Quick Present stopped being ready (a Bible removed, caches wiped).
export function shouldPrepare({ signedIn, online, slow, screen, last, owner, now, ready, force = false }) {
  if (!signedIn || !online || slow || screen) return false
  if (force || !ready) return true
  if (!last || last.owner !== owner) return true
  return now - (Number(last.at) || 0) >= PREPARE_EVERY_MS
}

// Pages that make Quick Present projectable with no internet: the study, its
// projector and stage screens, and the home page it starts from.
export function quickPresentPages(quick) {
  if (!quick?.url) return []
  return [ quick.url, `${quick.url}?output=1`, `${quick.url}?stage=1` ]
}

// Recent studies the device keeps (study + projector screen). None on Data
// Saver: those few pages each are the reader's call there.
export function recentPages(recent, { saveData = false } = {}) {
  if (saveData) return []
  return (recent || []).filter((s) => s?.url).flatMap((s) => [ s.url, `${s.url}?output=1` ])
}

// Download the Quick Present Bible? Only when it isn't on the device (or is an
// older version), and never by itself on Data Saver (the #41 rule).
export function bibleToDownload({ code, manifest, downloaded, saveData }) {
  if (!code || saveData) return null
  const t = manifest?.translations?.find((x) => x.code === code)
  if (!t) return null
  const have = (downloaded || []).find((d) => d.code === code)
  return have && have.version === t.version ? null : t
}

// Ready to project offline: the study page is saved and its Bible is on the device.
export function isReady(quick, { owner, pageSaved, downloaded }) {
  if (!quick || quick.owner !== owner || !pageSaved) return false
  return (downloaded || []).some((d) => d.code === quick.translation?.code)
}

// Where "Present offline" goes: straight into preach mode (?present=1) from
// the saved copy (?saved=1 — the service worker answers from its cache, so a
// "data on but dead" connection can't hold the page up).
export function presentUrl(quick, { saved = true } = {}) {
  return `${quick.url}?present=1${saved ? "&saved=1" : ""}`
}

// ---- the reader's Bible, downloaded by itself (auto_bible.js) -----------------

export const AUTO_BIBLE_CODE = "KJV"
export const AUTO_RETRY_MS = 10 * 60 * 1000 // after a failed try

// Which translation to fetch on first launch, so reading works with no data
// (like a native Bible app): the KJV (else the site default), for everyone —
// guests too. Inside the apps always; on the web not on Data Saver. Nothing
// with no (or a dead) network, in the projector/stage windows, while a recent
// try failed, when the reader removed it from the device themselves, or when
// it is already on the device at the current version.
export function autoBibleToDownload({ manifest, downloaded, native = false, saveData = false, online = true,
                                      slow = false, screen = false, lastFailedAt = 0, optedOut = false, now = Date.now() }) {
  if (!online || slow || screen) return null
  if (saveData && !native) return null
  if (lastFailedAt && now - lastFailedAt < AUTO_RETRY_MS) return null
  const list = manifest?.translations || []
  const t = list.find((x) => x.code === AUTO_BIBLE_CODE) || list.find((x) => x.code === manifest?.default_code)
  if (!t) return null
  const have = (downloaded || []).find((d) => d.code === t.code)
  if (!have && optedOut) return null // removed on Offline Bibles: the reader's call
  return have && have.version === t.version ? null : t
}

// Wait this long after a page loads before starting: soon inside the apps
// (that's where people read with no data), later on the web.
export const autoBibleDelay = ({ native }) => (native ? 800 : 4000)
