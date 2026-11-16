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
  // The Bible text scrolls in its own box: back to its left edge too (Safari
  // keeps a sideways offset from the middle of the rotation).
  document.querySelectorAll(".ps-verses, .ps-workspace, .ps-shell").forEach((box) => { if (box.scrollLeft) box.scrollLeft = 0 })
}

window.addEventListener("resize", () => requestAnimationFrame(() => settle()), { passive: true })
// Safari settles its layout a moment after the rotation: check twice.
const afterTurn = () => { setTimeout(() => settle(true), 250); setTimeout(() => settle(true), 700) }
window.addEventListener("orientationchange", afterTurn, { passive: true })
screen.orientation?.addEventListener?.("change", afterTurn)
