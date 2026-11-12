// node --test test/javascript — the "always ready offline" decisions
// (app/javascript/lib/offline/ready_plan.js). Run by test/javascript/js_units_test.rb.
import { test } from "node:test"
import assert from "node:assert/strict"
import { shouldPrepare, quickPresentPages, recentPages, bibleToDownload, isReady, presentUrl, PREPARE_EVERY_MS } from "../../app/javascript/lib/offline/ready_plan.js"

const base = { signedIn: true, online: true, slow: false, screen: false, owner: "u-1", now: 10 * PREPARE_EVERY_MS, ready: true }

test("prepares a signed-in reader's device at most once a day while Quick Present stays ready", () => {
  assert.equal(shouldPrepare({ ...base, last: null }), true)
  assert.equal(shouldPrepare({ ...base, last: { owner: "u-1", at: base.now - 1000 } }), false)
  assert.equal(shouldPrepare({ ...base, last: { owner: "u-1", at: base.now - PREPARE_EVERY_MS } }), true)
  assert.equal(shouldPrepare({ ...base, last: { owner: "u-2", at: base.now } }), true, "someone else signed in")
  assert.equal(shouldPrepare({ ...base, last: { owner: "u-1", at: base.now }, ready: false }), true, "no longer ready")
  assert.equal(shouldPrepare({ ...base, last: { owner: "u-1", at: base.now }, force: true }), true)
})

test("never for guests, offline, a dead network or the projector/stage windows", () => {
  for (const off of [ { signedIn: false }, { online: false }, { slow: true }, { screen: true } ]) {
    assert.equal(shouldPrepare({ ...base, last: null, ready: false, force: true, ...off }), false, JSON.stringify(off))
  }
})

test("Quick Present keeps its study, projector and stage screens", () => {
  assert.deepEqual(quickPresentPages({ url: "/studies/7" }), [ "/studies/7", "/studies/7?output=1", "/studies/7?stage=1" ])
  assert.deepEqual(quickPresentPages(null), [])
})

test("recent studies keep the study and projector screen, none on Data Saver", () => {
  const recent = [ { url: "/studies/1" }, { url: "/studies/2" }, {} ]
  assert.deepEqual(recentPages(recent), [ "/studies/1", "/studies/1?output=1", "/studies/2", "/studies/2?output=1" ])
  assert.deepEqual(recentPages(recent, { saveData: true }), [])
})

test("downloads the Quick Present Bible only when missing or outdated, never on Data Saver", () => {
  const manifest = { translations: [ { code: "KJV", version: "b" }, { code: "WEB", version: "w" } ] }
  assert.equal(bibleToDownload({ code: "KJV", manifest, downloaded: [], saveData: false }).code, "KJV")
  assert.equal(bibleToDownload({ code: "KJV", manifest, downloaded: [ { code: "KJV", version: "a" } ], saveData: false }).version, "b")
  assert.equal(bibleToDownload({ code: "KJV", manifest, downloaded: [ { code: "KJV", version: "b" } ], saveData: false }), null)
  assert.equal(bibleToDownload({ code: "KJV", manifest, downloaded: [], saveData: true }), null)
  assert.equal(bibleToDownload({ code: "NIV", manifest, downloaded: [], saveData: false }), null)
})

test("ready means this reader's page is saved and its Bible is on the device", () => {
  const quick = { owner: "u-1", url: "/studies/7", translation: { code: "KJV" } }
  assert.equal(isReady(quick, { owner: "u-1", pageSaved: true, downloaded: [ { code: "KJV" } ] }), true)
  assert.equal(isReady(quick, { owner: "u-1", pageSaved: false, downloaded: [ { code: "KJV" } ] }), false)
  assert.equal(isReady(quick, { owner: "u-1", pageSaved: true, downloaded: [ { code: "WEB" } ] }), false)
  assert.equal(isReady(quick, { owner: "u-2", pageSaved: true, downloaded: [ { code: "KJV" } ] }), false)
  assert.equal(isReady(null, { owner: "u-1", pageSaved: true, downloaded: [] }), false)
})

test("Present offline opens preach mode from the saved copy", () => {
  assert.equal(presentUrl({ url: "/studies/7" }), "/studies/7?present=1&saved=1")
  assert.equal(presentUrl({ url: "/studies/7" }, { saved: false }), "/studies/7?present=1")
})
