// Shrink-to-fit (and grow-to-fill) for projected words. The largest font size
// between `min` and `max` for which `fits(size)` is true, by bisection: a
// long verse never overflows the screen, a short one fills it. `fits` must
// be monotonic (bigger text never fits better). Pure — node-tested in
// test/javascript/fit_text_test.mjs; the DOM side is fitElement() below.
export function fitFontSize({ min, max, fits, precision = 0.5, maxIters = 16 }) {
  const lo0 = Math.max(1, min) // the floor always wins
  let hi = Math.max(lo0, max)
  if (fits(hi)) return hi
  let lo = lo0
  if (!fits(lo)) return lo // even the smallest doesn't fit: the floor, never smaller
  for (let i = 0; i < maxIters && hi - lo > precision; i++) {
    const mid = (lo + hi) / 2
    if (fits(mid)) lo = mid
    else hi = mid
  }
  return Math.floor(lo * 10) / 10
}

// The projection cap: text may grow to ~11% of the screen height (7% of the
// width on a tall window), times the operator's A−/A+ setting.
export function screenCap(width, height, scale = 1, ratio = 0.11) {
  return Math.min(height * ratio, width * (ratio * 0.64)) * scale
}

// Size `targets` (elements) so neither `box` nor they overflow: sets inline font-size.
export function fitElement(box, targets, { min = 18, max }) {
  const list = Array.from(targets)
  if (!box || list.length === 0) return null
  const set = (px) => list.forEach((el) => { el.style.fontSize = `${px}px` })
  // The room inside the box's padding (the safe margins and reference band).
  // Measured on the targets themselves: centred content that overflows
  // spills above the top too, where scrollHeight never sees it.
  const cs = getComputedStyle(box)
  const roomH = box.clientHeight - parseFloat(cs.paddingTop || 0) - parseFloat(cs.paddingBottom || 0)
  const fits = (px) => {
    set(px)
    const height = list.reduce((sum, el) => sum + el.getBoundingClientRect().height, 0)
    return height <= roomH + 1 && box.scrollHeight <= box.clientHeight + 1 && box.scrollWidth <= box.clientWidth + 1 &&
      list.every((el) => textWidth(el) <= el.clientWidth + 1)
  }
  const size = fitFontSize({ min, max, fits })
  set(size)
  return size
}

// How wide the words really are (centred text that overflows spills both
// ways, which scrollWidth doesn't see).
function textWidth(el) {
  if (typeof document === "undefined" || !document.createRange) return el.scrollWidth
  const range = document.createRange()
  range.selectNodeContents(el)
  return Math.max(el.scrollWidth, range.getBoundingClientRect().width)
}
