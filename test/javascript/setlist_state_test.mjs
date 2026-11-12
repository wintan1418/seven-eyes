// node --test test/javascript — the local-first preach queue's pure logic
// (app/javascript/lib/offline/setlist_state.js): several references typed at
// once, and how the server's list, the device's copy and pending outbox ops
// merge after a reload.
import { test } from "node:test"
import assert from "node:assert/strict"
import { makeParser, referenceLabel } from "../../app/javascript/lib/offline/reference_parser.js"
import {
  splitReferences, mergeQueue, applyOps, moveItem, queueKey, nextUp, arrange, fromServer, serverKey
} from "../../app/javascript/lib/offline/setlist_state.js"

const canon = [
  { osis: "Jer", name: "Jeremiah", chapters: 52, aliases: [ "Jer", "Jr" ] },
  { osis: "Matt", name: "Matthew", chapters: 28, aliases: [ "Mt", "Matt" ] },
  { osis: "John", name: "John", chapters: 21, aliases: [ "Jn", "Jhn" ] },
  { osis: "Rev", name: "Revelation", chapters: 22, aliases: [ "Rev", "Re" ] },
  { osis: "Ps", name: "Psalms", chapters: 150, aliases: [ "Ps", "Psalm", "Psa" ] },
  { osis: "Obad", name: "Obadiah", chapters: 1, aliases: [ "Obad", "Ob" ] }
]
const parse = makeParser(canon)
const split = (raw) => splitReferences(raw, parse, referenceLabel)

test("commas, semicolons and new lines split references; ranges stay one item", () => {
  const { items, errors } = split("Jn 11:35, Rev 12:10; Jer 10:10-11\nmatt 10:10")
  assert.deepEqual(items.map((i) => i.label), [ "John 11:35", "Revelation 12:10", "Jeremiah 10:10-11", "Matthew 10:10" ])
  assert.deepEqual(errors, [])
})

test("a bare number after a reference is another verse of that chapter", () => {
  const { items } = split("Jn 3:16, 18, 20-21")
  assert.deepEqual(items.map((i) => i.label), [ "John 3:16", "John 3:18", "John 3:20-21" ])
})

test("unreadable pieces are explained, the readable ones still come through", () => {
  const { items, errors } = split("Jn 3:16, Blorbity 9, Jer 60:1, ,")
  assert.deepEqual(items.map((i) => i.label), [ "John 3:16" ])
  assert.equal(errors.length, 2)
  assert.match(errors[0].message, /Blorbity 9.*no book/)
  assert.match(errors[1].message, /Jeremiah has 52 chapters/)
  assert.equal(errors[1].raw, "Jer 60:1")
})

test("blank input adds nothing and complains about nothing", () => {
  assert.deepEqual(split("  ,; \n"), { items: [], errors: [] })
})

test("without a parser on the device, pieces are queued as typed for the server to read", () => {
  const { items } = splitReferences("jn 3:16, rev 1", null)
  assert.deepEqual(items.map((i) => i.reference), [ "jn 3:16", "rev 1" ])
})

const srv = (id, label, extra = {}) => ({ id, client_id: null, kind: "scripture", reference: label, label, ...extra })
const create = (cid, label, position) => ({ setlist: { action: "create", cid, position, item: { cid, kind: "scripture", reference: label, label } } })

test("pending creates land at their positions on top of the server list, once", () => {
  const ops = [ create("tmp-a", "John 11:35", 1), create("tmp-b", "Revelation 12:10", 3) ]
  const items = mergeQueue({ server: [ srv(1, "Psalms 23"), srv(2, "Jeremiah 10:10") ], serverTime: 100, ops })
  assert.deepEqual(items.map((i) => i.label), [ "Psalms 23", "John 11:35", "Jeremiah 10:10", "Revelation 12:10" ])
  // Replaying the same ops again changes nothing (idempotent).
  assert.deepEqual(applyOps(items, ops).map((i) => i.cid), items.map((i) => i.cid))
})

test("a create the server already has (by client id) isn't doubled", () => {
  const server = [ srv(5, "John 11:35", { client_id: "tmp-a" }) ]
  const items = mergeQueue({ server, serverTime: 100, ops: [ create("tmp-a", "John 11:35", 0) ] })
  assert.equal(items.length, 1)
  assert.equal(items[0].id, 5)
  assert.equal(items[0].cid, "tmp-a")
})

test("pending update, destroy and order apply in sequence", () => {
  const server = [ srv(1, "A"), srv(2, "B"), srv(3, "C") ]
  const ops = [
    { setlist: { action: "update", cid: "srv-2", fields: { label: "B2" } } },
    { setlist: { action: "destroy", cid: "srv-1", id: 1 } },
    create("tmp-d", "D", 2),
    { setlist: { action: "order", order: [ "tmp-d", "3", "2" ] } }
  ]
  assert.deepEqual(mergeQueue({ server, serverTime: 1, ops }).map((i) => i.label), [ "D", "C", "B2" ])
})

test("a stale saved page loses to the device's newer synced copy", () => {
  const local = { items: [ fromServer(srv(1, "A")), fromServer(srv(4, "New since")) ], syncedAt: 500 }
  const items = mergeQueue({ server: [ srv(1, "A") ], serverTime: 200, local, ops: [] })
  assert.deepEqual(items.map((i) => i.label), [ "A", "New since" ])
})

test("a fresh server list wins over an older device copy (changed elsewhere)", () => {
  const local = { items: [ fromServer(srv(1, "A")), fromServer(srv(2, "Deleted elsewhere")) ], syncedAt: 100 }
  const items = mergeQueue({ server: [ srv(1, "A") ], serverTime: 900, local, ops: [] })
  assert.deepEqual(items.map((i) => i.label), [ "A" ])
})

test("an item the server refused stays (marked failed) so it can be retried", () => {
  const bad = { cid: "tmp-bad", id: null, kind: "scripture", reference: "Hezekiah 1", label: "Hezekiah 1" }
  const local = { items: [ fromServer(srv(1, "A")), bad ], syncedAt: 100, failed: { "tmp-bad": "couldn't be read" } }
  const items = mergeQueue({ server: [ srv(1, "A") ], serverTime: 900, local, ops: [] })
  assert.deepEqual(items.map((i) => i.cid), [ "srv-1", "tmp-bad" ])
})

test("server ids learnt on the device carry onto a server-based merge", () => {
  const local = { items: [ { cid: "tmp-x", id: 9, kind: "thought", label: "Hi" } ], syncedAt: 1 }
  const ops = [ { setlist: { action: "create", cid: "tmp-x", position: 0, item: { cid: "tmp-x", kind: "thought", label: "Hi" } } } ]
  const items = mergeQueue({ server: [], serverTime: 50, local, ops })
  assert.equal(items[0].id, 9)
  assert.equal(serverKey(items[0]), "9")
})

test("moveItem, arrange and nextUp", () => {
  const list = [ "a", "b", "c", "d" ].map((cid) => ({ cid, id: null }))
  assert.deepEqual(moveItem(list, 0, 2).map((i) => i.cid), [ "b", "c", "a", "d" ])
  assert.deepEqual(moveItem(list, 3, 0).map((i) => i.cid), [ "d", "a", "b", "c" ])
  assert.deepEqual(arrange(list, [ "c", "zz", "a" ]).map((i) => i.cid), [ "c", "a", "b", "d" ])
  assert.equal(nextUp(list, null).cid, "a")
  assert.equal(nextUp(list, "b").cid, "c")
  assert.equal(nextUp(list, "d"), null)
})

test("queueKey treats the same passage typed differently as one", () => {
  assert.equal(queueKey({ kind: "scripture", label: "John 11:35" }), queueKey({ kind: "scripture", label: " john  11:35 " }))
  assert.equal(queueKey({ kind: "scripture", label: "Jeremiah 10:10–11" }), queueKey({ kind: "scripture", label: "Jeremiah 10:10-11" }))
  assert.notEqual(queueKey({ kind: "scripture", label: "John 11:35" }), queueKey({ kind: "song", title: "John 11:35" }))
})
