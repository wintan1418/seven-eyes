// A one-shot ?name=1 on arrival: true once, and the address bar loses it (so
// a reload or Back doesn't repeat it).
export function takeArrivalParam(name) {
  const url = new URL(window.location.href)
  if (url.searchParams.get(name) !== "1") return false
  url.searchParams.delete(name)
  history.replaceState(history.state, "", url.pathname + url.search + url.hash)
  return true
}

// Runs fn once when the page was opened with ?name=1. A Turbo visit may update
// the address bar only after the controller connects, so look again on
// turbo:load.
export function onArrival(name, fn) {
  if (takeArrivalParam(name)) return requestAnimationFrame(fn)
  document.addEventListener("turbo:load", () => { if (takeArrivalParam(name)) fn() }, { once: true })
}
