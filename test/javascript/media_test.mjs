// node --test test/javascript — pictures kept on the device for offline
// services (app/javascript/lib/offline/media.js): which URLs the ps-media
// cache holds, and what's left to save.
import { test } from "node:test"
import assert from "node:assert/strict"
import { isMediaUrl, mediaPlan, mediaKey } from "../../app/javascript/lib/offline/media.js"

const ORIGIN = "https://bibliorata.com"

test("our own pictures and Cloudinary pictures are media; pages, assets and other hosts aren't", () => {
  assert.equal(isMediaUrl("/rails/active_storage/blobs/redirect/abc/flyer.png", ORIGIN), true)
  assert.equal(isMediaUrl("/rails/active_storage/representations/redirect/abc/def/flyer.png", ORIGIN), true)
  assert.equal(isMediaUrl("https://res.cloudinary.com/demo/image/upload/v1/q/x.jpg", ORIGIN), true)
  assert.equal(isMediaUrl("/rails/active_storage/disk/abc/flyer.png", ORIGIN), false)
  assert.equal(isMediaUrl("/studies/4", ORIGIN), false)
  assert.equal(isMediaUrl("/assets/application-abc.css", ORIGIN), false)
  assert.equal(isMediaUrl("https://evil.example/rails/active_storage/blobs/x.png", ORIGIN), false)
  assert.equal(isMediaUrl("http://res.cloudinary.com/demo/x.jpg", ORIGIN), false)
  assert.equal(isMediaUrl("", ORIGIN), false)
  assert.equal(isMediaUrl(null, ORIGIN), false)
})

test("a picture is keyed by its absolute URL — the one the projector asks for", () => {
  assert.equal(mediaKey("/rails/active_storage/blobs/redirect/a/f.png", ORIGIN), `${ORIGIN}/rails/active_storage/blobs/redirect/a/f.png`)
})

test("the plan: each picture once, minus what's already saved", () => {
  const a = "/rails/active_storage/blobs/redirect/a/f.png"
  const b = "https://res.cloudinary.com/demo/image/upload/b.jpg"
  const plan = mediaPlan([ a, b, a, null, "/studies/1" ], new Set([ b ]), ORIGIN)
  assert.deepEqual(plan, { todo: [ a ], saved: 1, total: 2 })
  assert.deepEqual(mediaPlan([], new Set(), ORIGIN), { todo: [], saved: 0, total: 0 })
})
