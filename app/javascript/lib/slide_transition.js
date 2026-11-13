// How the projector moves from one slide to the next.
//
//   "xfade" — a true crossfade: the old words dissolve into the new over the
//             same background (the View Transitions API snapshots the screen,
//             so nothing has to be drawn twice). Projector window only — on
//             the operator's console a view transition would swallow clicks.
//   "dip"   — the older fade-out / fade-in of the words (operator, and any
//             browser without view transitions).
//   "cut"   — instant. The operator's "Cut" setting, and always when the
//             computer asks for reduced motion.
//
// The look controller (screen_look) writes the setting to the root as
// data-slide-transition="fade|cut" in every window.
export function transitionStyle(root) {
  if (!root) return "dip"
  if (root.dataset.slideTransition === "cut" || prefersReducedMotion()) return "cut"
  if (root.classList.contains("is-output") && !root.classList.contains("is-stage") &&
      typeof document !== "undefined" && typeof document.startViewTransition === "function") return "xfade"
  return "dip"
}

export function prefersReducedMotion() {
  try {
    return typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
  } catch {
    return false
  }
}

// Run `swap` (a synchronous DOM change) as a crossfade. A crossfade asked for
// while one is still playing simply starts from where the screen is.
export function crossfade(swap) {
  if (typeof document === "undefined" || typeof document.startViewTransition !== "function") {
    swap()
    return Promise.resolve()
  }
  try {
    const vt = document.startViewTransition(() => { swap() })
    return vt.finished.catch(() => {})
  } catch {
    swap()
    return Promise.resolve()
  }
}
