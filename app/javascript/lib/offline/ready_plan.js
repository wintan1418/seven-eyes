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
