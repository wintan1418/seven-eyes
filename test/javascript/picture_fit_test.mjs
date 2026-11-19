// node --test test/javascript — how a queue picture fills the projector
// (app/javascript/lib/picture_fit.js; the server's twin is SlideData.picture).
import { test } from "node:test"
import assert from "node:assert/strict"
import { pictureDisplay, samePicture, pictureLabel, applyPicture } from "../../app/javascript/lib/picture_fit.js"

test("a picture with no setting (queued before there was a choice) fits the whole screen", () => {
  assert.deepEqual(pictureDisplay(null), { fit: "fit", zoom: 100 })
  assert.deepEqual(pictureDisplay({}), { fit: "fit", zoom: 100 })
})

test("keeps known fits and clamps zoom to 100–200", () => {
  assert.deepEqual(pictureDisplay({ fit: "fill", zoom: 150 }), { fit: "fill", zoom: 150 })
  assert.deepEqual(pictureDisplay({ fit: "stretch", zoom: "999" }), { fit: "stretch", zoom: 200 })
  assert.deepEqual(pictureDisplay({ fit: "tile", zoom: 40 }), { fit: "fit", zoom: 100 })
})

test("compares and labels", () => {
  assert.ok(samePicture(null, { fit: "fit", zoom: 100 }))
  assert.ok(!samePicture({ fit: "fill" }, { fit: "fit" }))
  assert.equal(pictureLabel({ fit: "fill" }), "Fill")
  assert.equal(pictureLabel({ fit: "fit", zoom: 130 }), "Fit · 130%")
})

test("marks a frame for the CSS", () => {
  const props = {}
  const frame = { dataset: {}, style: { setProperty: (k, v) => { props[k] = v } } }
  applyPicture(frame, { fit: "fill", zoom: 120 })
  assert.equal(frame.dataset.fit, "fill")
  assert.equal(props["--pic-zoom"], "1.2")
})
