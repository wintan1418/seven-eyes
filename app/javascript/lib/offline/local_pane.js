// Local-first Scripture for preach mode and the projector: read references
// and render passages on the device, from the Bibles downloaded to IndexedDB,
// without waiting on the network. EasyWorship-fast: "John 3:16" + Enter is a
// parse, an IndexedDB read and a DOM swap — no round-trip.
//
//   warmLocal()                 load the manifest's canon + the download list once
//   localCheck(raw)             sync: the /reference_check answer, or null if not warm
//   loadPaneLocally(frame, …)   render a pane's Turbo Frame from a download and
//                               swap it in exactly as Turbo would (same events)
//
// The markup is the service worker's offline twin of the pane partial
// (pane_renderer.js), so preach mode can't tell the difference. The reference
// is still saved to the study in the background — straight away when the
// network is fine, through the outbox when it isn't.
import { storedManifest, downloadedBibles } from "./store"
import { makeParser, referenceLabel } from "./reference_parser"
import { renderOfflinePane } from "./offline_pane"
import { queuePaneVisit } from "./outbox"
import { paneContext, owner } from "./page"
import { quickFetch, isNetworkSlow } from "./network"

const SAVE_TIMEOUT_MS = 4000

let local = { parse: null, books: new Map(), translations: [], downloaded: [] }
let warming = null

export function warmLocal({ force = false } = {}) {
  if (warming && !force) return warming
  warming = (async () => {
    const [ manifest, downloaded ] = await Promise.all([ storedManifest(), downloadedBibles() ])
    local = {
      parse: manifest?.canon ? makeParser(manifest.canon) : null,
      books: new Map((manifest?.books || []).map((b) => [ b.osis, b ])),
      translations: manifest?.translations || [],
      downloaded
    }
    return local
  })().catch(() => local)
  return warming
}

export const localReady = () => !!local.parse

// The same answer VersesController#check gives, from the device. null when the
// parser isn't loaded yet (no manifest stored): ask the server instead.
export function localCheck(raw) {
  if (!local.parse) return null
  const p = local.parse(raw)
  if (!p.valid || !local.books.has(p.osis)) return { ok: false }
  return {
    ok: true, osis: p.osis, chapter: p.chapter, verse_start: p.verseStart,
    chapter_reference: `${p.bookName} ${p.chapter}`, label: referenceLabel(p), local: true
  }
}

// Is this pane translation (by id) on the device?
export function translationDownloaded(translationId) {
  const t = local.translations.find((x) => String(x.id) === String(translationId))
  return !!t && local.downloaded.some((d) => d.code === t.code)
}

export const localState = () => local

const seq = new WeakMap()

// Render `frame` (a pane's <turbo-frame>) from the downloaded Bible and swap it
// in. Resolves true when the passage is on screen (or a newer load for the
// same frame superseded this one), false when it couldn't be done locally —
// the caller then submits the pane form as usual.
export async function loadPaneLocally(frame, { mirror = false } = {}) {
  const form = frame?.querySelector("form.rd-pane-form")
  const reference = form?.querySelector("input[name='pane[reference]']")?.value
  if (!form || !reference) return false
  const translationId = form.querySelector("select[name='pane[translation_id]']")?.value || null
  const mine = (seq.get(frame) || 0) + 1
  seq.set(frame, mine)

  const match = form.getAttribute("action")?.match(/^\/studies\/(\d+)\/panes\/(\d+)/)
  if (!match) return false
  const context = paneContext(frame)
  let html = null
  try {
    html = await renderOfflinePane({
      studyId: match[1], paneId: match[2], reference, translationId, context,
      token: document.querySelector("meta[name='csrf-token']")?.content, onlyIfReady: true
    })
  } catch { html = null }
  if (seq.get(frame) !== mine) return true // a newer load for this pane won
  if (!html) return false

  swapFrame(frame, html)
  if (!mirror) savePaneReference(form.getAttribute("action"), { reference, translationId }, context.owner)
  return true
}

// What Turbo's FrameController does with a frame response, minus the fetch:
// the same events, so notes carry-over (page.js), the reader, memorize,
// verse-select and preach mode's _onceLoaded all behave as usual.
export function swapFrame(frame, html) {
  const template = document.createElement("template")
  template.innerHTML = html
  const newFrame = template.content.querySelector("turbo-frame")
  if (!newFrame) return false
  frame.dispatchEvent(new CustomEvent("turbo:before-frame-render", {
    bubbles: true, cancelable: true, detail: { newFrame, render: () => {} }
  }))
  frame.replaceChildren(...newFrame.childNodes)
  frame.dispatchEvent(new CustomEvent("turbo:frame-render", { bubbles: true, detail: { fetchResponse: null } }))
  frame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))
  return true
}

// Remember where the pane went (what the form submit would have saved). Never
// blocks the screen: a slow or absent network queues it in the outbox.
function savePaneReference(url, { reference, translationId }, who) {
  const queue = () => queuePaneVisit(url, { reference, translationId }, who || owner()).catch(() => {})
  if (isNetworkSlow() || navigator.onLine === false) { queue(); return }
  const body = new URLSearchParams({ "pane[reference]": reference })
  if (translationId) body.set("pane[translation_id]", translationId)
  quickFetch(url, {
    method: "PATCH", body,
    headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "", Accept: "text/html" }
  }, { timeoutMs: SAVE_TIMEOUT_MS, read: "text" }).catch(queue)
}
