// Inside the iOS / Android apps (Hotwire Native). The Android app calls
// window.nativeCloseOverlay() on Back: an open sheet (passage picker, version,
// reading settings, More…) closes first; only when nothing is open does Back
// leave the page. Returns true when it closed something.
export const isNativeApp = /(Hotwire|Turbo) Native/.test(navigator.userAgent)

window.nativeCloseOverlay = () => {
  if (!document.querySelector(".ui-sheet:not([hidden])")) return false
  window.dispatchEvent(new CustomEvent("sheet:close", { detail: {} }))
  return true
}
