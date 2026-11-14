// Ask the service worker to keep the app's core pages on the device (see
// "warm" in service_worker.js): on every page load with a working network —
// the worker itself decides how often it really refetches (every few hours,
// after a deploy, or when a different reader signs in). On the very first
// load the worker wasn't controlling the page yet, so this page's own load
// wasn't saved: send its address too.
import { owner, signedIn, sessionSynced } from "./page"
import { isNetworkSlow } from "./network"

const isScreen = () => /[?&](output|stage)=1\b/.test(window.location.search)

export async function warmPages() {
  if (!("serviceWorker" in navigator) || navigator.onLine === false || isNetworkSlow() || isScreen()) return
  const controlled = !!navigator.serviceWorker.controller
  await sessionSynced()
  const reg = await navigator.serviceWorker.ready
  const worker = navigator.serviceWorker.controller || reg?.active
  worker?.postMessage({ type: "warm", owner: owner(), signedIn: signedIn(), url: controlled ? null : window.location.href })
}

let started = false
function boot() {
  warmPages().catch(() => {})
  if (started) return
  started = true
  window.addEventListener("online", () => warmPages().catch(() => {}))
}

document.addEventListener("turbo:load", boot)
if (document.readyState !== "loading") boot()
