// Put the projector window on the second screen (the projector), full screen,
// without dragging. Uses the Window Management API (Chrome / Edge): the first
// time, the browser asks once to "manage windows on all your displays".
// Without a second screen, or in other browsers, it opens as a normal window.

export function hasSecondScreen() {
  try { return window.screen?.isExtended === true } catch { return false }
}

export async function windowManagement() {
  if (!("getScreenDetails" in window) || !navigator.permissions?.query) return "unsupported"
  try {
    const status = await navigator.permissions.query({ name: "window-management" })
    return status.state // "granted" | "prompt" | "denied"
  } catch {
    return "unsupported"
  }
}

// The screen to project on: not the one the operator is using, primary or not.
export async function projectorScreen() {
  try {
    const details = await window.getScreenDetails()
    const others = details.screens.filter((s) => s !== details.currentScreen)
    return others.find((s) => !s.isPrimary) || others[0] || null
  } catch {
    return null // permission refused
  }
}

export function featuresFor(screen, { fullscreen = true } = {}) {
  const f = [
    "popup=yes",
    `left=${screen.availLeft}`, `top=${screen.availTop}`,
    `width=${screen.availWidth}`, `height=${screen.availHeight}`
  ]
  if (fullscreen) f.push("fullscreen") // honoured once window management is allowed
  return f.join(",")
}

// Move an already-open window onto that screen and fill it.
export function moveTo(win, screen) {
  try {
    win.moveTo(screen.availLeft, screen.availTop)
    win.resizeTo(screen.availWidth, screen.availHeight)
    return true
  } catch {
    return false
  }
}
