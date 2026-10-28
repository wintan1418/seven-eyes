// A tiny promise wrapper over the reader's IndexedDB database, shared by the
// page and the service worker (both run this same module).
//
//   meta       key → value       manifest, csrf token, owner, last study url…
//   bibles     code → summary    downloaded translations (no text)
//   books      [code, osis] → { code, osis, chapters }   the text, one record per book
//   highlights id → highlight   the reader's own highlights (index: verse_id)
//   outbox     seq → op         writes waiting for the network (see outbox.js)
const DB_NAME = "bibliorata-offline"
const DB_VERSION = 1

let opening = null

export function openDb() {
  if (opening) return opening
  opening = new Promise((resolve, reject) => {
    if (typeof indexedDB === "undefined") { reject(new Error("IndexedDB unavailable")); return }
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains("meta")) db.createObjectStore("meta")
      if (!db.objectStoreNames.contains("bibles")) db.createObjectStore("bibles", { keyPath: "code" })
      if (!db.objectStoreNames.contains("books")) db.createObjectStore("books", { keyPath: [ "code", "osis" ] })
      if (!db.objectStoreNames.contains("highlights")) {
        db.createObjectStore("highlights", { keyPath: "id" }).createIndex("verse_id", "verse_id")
      }
      if (!db.objectStoreNames.contains("outbox")) db.createObjectStore("outbox", { keyPath: "seq", autoIncrement: true })
    }
    req.onsuccess = () => {
      const db = req.result
      // Another tab upgraded the schema: let it, and reopen next time.
      db.onversionchange = () => { db.close(); opening = null }
      resolve(db)
    }
    req.onerror = () => { opening = null; reject(req.error) }
    req.onblocked = () => { opening = null; reject(new Error("IndexedDB blocked")) }
  })
  return opening
}

function promisify(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

function done(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error || new Error("transaction aborted"))
  })
}

export async function get(store, key) {
  const db = await openDb()
  return promisify(db.transaction(store).objectStore(store).get(key))
}

export async function getAll(store, query) {
  const db = await openDb()
  return promisify(db.transaction(store).objectStore(store).getAll(query))
}

export async function getAllByIndex(store, index, key) {
  const db = await openDb()
  return promisify(db.transaction(store).objectStore(store).index(index).getAll(key))
}

export async function put(store, value, key) {
  const db = await openDb()
  const tx = db.transaction(store, "readwrite")
  const result = promisify(key === undefined ? tx.objectStore(store).put(value) : tx.objectStore(store).put(value, key))
  await done(tx)
  return result
}

export async function del(store, key) {
  const db = await openDb()
  const tx = db.transaction(store, "readwrite")
  tx.objectStore(store).delete(key)
  return done(tx)
}

export async function clear(store) {
  const db = await openDb()
  const tx = db.transaction(store, "readwrite")
  tx.objectStore(store).clear()
  return done(tx)
}

// Run `fn(tx)` in one readwrite transaction over `stores`; resolves when it commits.
export async function transaction(stores, fn) {
  const db = await openDb()
  const tx = db.transaction(stores, "readwrite")
  const result = fn(tx)
  await done(tx)
  return result
}

export { promisify }

export const getMeta = (key) => get("meta", key).catch(() => undefined)
export const setMeta = (key, value) => put("meta", value, key)
