// node --test test/javascript — the preach-mode network circuit breaker
// (app/javascript/lib/offline/breaker.js). Run by test/javascript_test.rb.
import { test } from "node:test"
import assert from "node:assert/strict"
import { createBreaker, makeQuickFetch, NetworkUnavailable } from "../../app/javascript/lib/offline/breaker.js"

function clock(start = 1_000_000) {
  let t = start
  return { now: () => t, advance: (ms) => { t += ms } }
}

const hang = (url, { signal }) => new Promise((_, reject) => {
  signal.addEventListener("abort", () => reject(Object.assign(new Error("aborted"), { name: "AbortError" })))
})
const answer = (body = "{\"ok\":true}", status = 200) => async () => new Response(body, { status })

test("a trip marks the network slow for three minutes, then it clears itself", () => {
  const c = clock()
  const b = createBreaker({ now: c.now })
  assert.equal(b.isSlow(), false)
  b.trip()
  assert.equal(b.isSlow(), true)
  c.advance(3 * 60 * 1000 - 1)
  assert.equal(b.isSlow(), true)
  c.advance(1)
  assert.equal(b.isSlow(), false)
})

test("reset clears the mark and reports the change once", () => {
  const changes = []
  const b = createBreaker({ onChange: (u) => changes.push(u) })
  b.reset() // nothing to clear: no echo
  b.trip()
  b.reset()
  assert.equal(b.isSlow(), false)
  assert.equal(changes.length, 2)
  assert.equal(changes[1], 0)
})

test("adopt takes a mark from another context without echoing it", () => {
  const changes = []
  const c = clock()
  const b = createBreaker({ now: c.now, onChange: (u) => changes.push(u) })
  b.adopt(c.now() + 5000)
  assert.equal(b.isSlow(), true)
  assert.deepEqual(changes, [])
})

test("a hung request times out quickly and trips the breaker", async () => {
  const b = createBreaker()
  const quickFetch = makeQuickFetch({ breaker: b, fetchImpl: hang })
  const started = Date.now()
  await assert.rejects(quickFetch("/reference_check?q=jn", {}, { timeoutMs: 50 }),
    (e) => e instanceof NetworkUnavailable && e.reason === "timeout")
  assert.ok(Date.now() - started < 1000)
  assert.equal(b.isSlow(), true)
})

test("while slow, requests fail at once without touching the network", async () => {
  const b = createBreaker()
  b.trip()
  let calls = 0
  const quickFetch = makeQuickFetch({ breaker: b, fetchImpl: async () => { calls++; return new Response("{}") } })
  await assert.rejects(quickFetch("/x"), (e) => e.reason === "slow")
  assert.equal(calls, 0)
  // ...unless forced (a deliberate retry)
  const { body } = await quickFetch("/x", {}, { force: true, read: "json" })
  assert.deepEqual(body, {})
  assert.equal(calls, 1)
  assert.equal(b.isSlow(), false, "a fast answer resets the mark")
})

test("offline fails at once", async () => {
  const quickFetch = makeQuickFetch({ breaker: createBreaker(), fetchImpl: answer(), isOffline: () => true })
  await assert.rejects(quickFetch("/x"), (e) => e.reason === "offline")
})

test("an HTTP error is a working network: no trip", async () => {
  const b = createBreaker()
  const quickFetch = makeQuickFetch({ breaker: b, fetchImpl: answer("oops", 500) })
  const { res } = await quickFetch("/x", {}, { read: "text" })
  assert.equal(res.status, 500)
  assert.equal(b.isSlow(), false)
})

test("a network error trips the breaker", async () => {
  const b = createBreaker()
  const quickFetch = makeQuickFetch({ breaker: b, fetchImpl: async () => { throw new TypeError("Failed to fetch") } })
  await assert.rejects(quickFetch("/x"), (e) => e.reason === "error")
  assert.equal(b.isSlow(), true)
})
