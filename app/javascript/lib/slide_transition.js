// How the projector moves from one slide to the next.
//
//   "xfade" — a quick crossfade on the projector (View Transitions API), so the
//             words change the moment the operator taps and blend in briefly.
//   "dip"   — a quick fade-out / fade-in of the words, only on a projector whose
//             browser has no view transitions.
//   "cut"   — instant. The operator's console and the stage display always
//             cut (they are control screens: waiting on a fade there delayed
//             the projector), and so does everything with the "Cut" setting or
//             when the computer asks for reduced motion.
//
// The look controller (screen_look) writes the setting to the root as
// data-slide-transition="fade|cut" in every window.
export function transitionStyle(root) {
  if (!root) return "cut"
  if (root.dataset.slideTransition === "cut" || prefersReducedMotion()) return "cut"
  const projector = root.classList.contains("is-output") && !root.classList.contains("is-stage")
  if (!projector) return "cut"
  if (typeof document !== "undefined" && typeof document.startViewTransition === "function") return "xfade"
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
