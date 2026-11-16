// Turning a tablet: some browsers (Safari on iPad) keep the old horizontal
// scroll after the page gets wider, so it sits shifted to the left. When the
// width changes, put the page back at its left edge.
let lastWidth = window.innerWidth

function settle(force = false) {
  if (!force && window.innerWidth === lastWidth) return
  lastWidth = window.innerWidth
  if (window.scrollX !== 0 || document.documentElement.scrollLeft !== 0 || document.body.scrollLeft !== 0) {
    document.documentElement.scrollLeft = 0
    document.body.scrollLeft = 0
    window.scrollTo(0, window.scrollY)
  }
}

window.addEventListener("resize", () => requestAnimationFrame(() => settle()), { passive: true })
window.addEventListener("orientationchange", () => setTimeout(() => settle(true), 250), { passive: true })
screen.orientation?.addEventListener?.("change", () => setTimeout(() => settle(true), 250))
