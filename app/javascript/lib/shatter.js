// Glass-break transition for a horizontal slider: what's on screen cracks
// from a point near the middle into shards that fall away, revealing the
// next card already in place underneath.
//
//   shatter(track, () => track.scrollTo({ left, behavior: "instant" }))
//
// How: copies of the visible cards are laid over the track, one copy per
// shard, each cut to its shard's shape (clip-path). The real track jumps to
// the next card at once; the shards then fly off and fade. Copies carry no
// data-* attributes, so Stimulus never mistakes them for real slides.
// Reduced motion → the caller's move only, no effect.

const RAYS = 9

export function shatter(track, move, { duration = 950 } = {}) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !track.animate) {
    move()
    return Promise.resolve()
  }

  const host = track.parentElement
  if (getComputedStyle(host).position === "static") host.style.position = "relative"
  const width = track.clientWidth
  const height = track.clientHeight
  const left = track.scrollLeft

  const overlay = document.createElement("div")
  overlay.className = "glass-shatter"
  overlay.setAttribute("aria-hidden", "true")
  Object.assign(overlay.style, {
    position: "absolute", left: `${track.offsetLeft}px`, top: `${track.offsetTop}px`,
    width: `${width}px`, height: `${height}px`, overflow: "hidden", pointerEvents: "none", zIndex: 5
  })

  const visible = Array.from(track.children).filter(el =>
    el.offsetLeft + el.offsetWidth > left && el.offsetLeft < left + width)
  const scene = document.createElement("div")
  scene.style.cssText = "position:absolute;inset:0"
  visible.forEach(slide => {
    const copy = slide.cloneNode(true)
    stripData(copy)
    Object.assign(copy.style, {
      position: "absolute", margin: 0, left: `${slide.offsetLeft - left}px`, top: `${slide.offsetTop}px`,
      width: `${slide.offsetWidth}px`, height: `${slide.offsetHeight}px`
    })
    copy.querySelectorAll("img[loading]").forEach(img => img.removeAttribute("loading"))
    scene.append(copy)
  })

  // Impact near the middle of the first visible card.
  const first = visible[0]
  const cx = first ? ((first.offsetLeft - left + first.offsetWidth / 2) / width) * 100 : 50
  const cy = 45 + Math.random() * 10
  const shards = shardPolygons(cx + (Math.random() * 10 - 5), cy)

  shards.forEach(({ points, centre, ring }) => {
    const piece = document.createElement("div")
    piece.className = "glass-shard"
    piece.style.cssText = `position:absolute;inset:0;clip-path:polygon(${points.map(([ x, y ]) => `${x}% ${y}%`).join(",")})`
    piece.append(scene.cloneNode(true))
    overlay.append(piece)

    // Fly away from the impact, falling, turning a little.
    const dx = (centre[0] - cx) * (ring ? 2.2 : 1.2) + (Math.random() * 20 - 10)
    const dy = (centre[1] - cy) * (ring ? 1.6 : 0.9) + 60 + Math.random() * 50
    const turn = (Math.random() * 50 - 25) * (ring ? 1.4 : 1)
    const delay = 160 + Math.hypot(centre[0] - cx, centre[1] - cy) * 2.2
    piece.animate([
      { transform: "translate(0,0) rotate(0deg)", opacity: 1, filter: "brightness(1)" },
      { transform: `translate(${dx * 0.04}%, ${dy * 0.03}%) rotate(${turn * 0.05}deg)`, opacity: 1, filter: "brightness(1.25)", offset: 0.12 },
      { transform: `translate(${dx}%, ${dy}%) rotate(${turn}deg) scale(0.92)`, opacity: 0, filter: "brightness(1)" }
    ], { duration, delay, easing: "cubic-bezier(.35,.05,.6,1)", fill: "forwards" })
  })

  // The cracks: thin bright lines from the impact along every shard edge,
  // shown for a moment before the pieces fall.
  const svgNS = "http://www.w3.org/2000/svg"
  const cracks = document.createElementNS(svgNS, "svg")
  cracks.setAttribute("viewBox", "0 0 100 100")
  cracks.setAttribute("preserveAspectRatio", "none")
  cracks.style.cssText = "position:absolute;inset:0;width:100%;height:100%;z-index:2;overflow:visible"
  shards.forEach(({ points }) => {
    const line = document.createElementNS(svgNS, "polygon")
    line.setAttribute("points", points.map(([ x, y ]) => `${x},${y}`).join(" "))
    line.setAttribute("fill", "none")
    line.setAttribute("stroke", "rgba(255,255,255,0.85)")
    line.setAttribute("stroke-width", "0.35")
    line.setAttribute("vector-effect", "non-scaling-stroke")
    cracks.append(line)
  })
  overlay.append(cracks)
  cracks.animate([ { opacity: 0 }, { opacity: 1, offset: 0.25 }, { opacity: 1, offset: 0.55 }, { opacity: 0 } ],
    { duration: 520, easing: "ease-out", fill: "forwards" })

  host.append(overlay)
  move()

  const total = duration + 420
  return new Promise(resolve => setTimeout(() => { overlay.remove(); resolve() }, total))
}

// Cracks run from the impact out to the edges; each wedge breaks into an
// inner shard and an outer one, so pieces near the impact are small.
function shardPolygons(cx, cy) {
  const edge = []
  for (let i = 0; i < RAYS; i++) {
    const angle = (i / RAYS) * Math.PI * 2 + (Math.random() - 0.5) * 0.45
    edge.push(toEdge(cx, cy, angle))
  }
  edge.sort((a, b) => a.angle - b.angle)
  const inner = edge.map(p => {
    const t = 0.28 + Math.random() * 0.22
    return [ cx + (p.x - cx) * t, cy + (p.y - cy) * t ]
  })
  const shards = []
  for (let i = 0; i < edge.length; i++) {
    const j = (i + 1) % edge.length
    const a = [ edge[i].x, edge[i].y ]
    const b = [ edge[j].x, edge[j].y ]
    const corners = cornersBetween(edge[i].angle, edge[j].angle, cx, cy)
    const innerShard = [ [ cx, cy ], inner[i], inner[j] ]
    const outerShard = [ inner[i], a, ...corners, b, inner[j] ]
    shards.push({ points: innerShard, centre: centroid(innerShard), ring: false })
    shards.push({ points: outerShard, centre: centroid(outerShard), ring: true })
  }
  return shards
}

// Where a ray from (cx, cy) leaves the 0–100 box.
function toEdge(cx, cy, angle) {
  const dx = Math.cos(angle)
  const dy = Math.sin(angle)
  const ts = []
  if (dx > 0) ts.push((100 - cx) / dx)
  if (dx < 0) ts.push(-cx / dx)
  if (dy > 0) ts.push((100 - cy) / dy)
  if (dy < 0) ts.push(-cy / dy)
  const t = Math.min(...ts)
  const a = Math.atan2(dy, dx)
  return { x: cx + dx * t, y: cy + dy * t, angle: a < 0 ? a + Math.PI * 2 : a }
}

// Box corners swept between two ray angles (so outer shards reach the corners).
function cornersBetween(a1, a2, cx, cy) {
  const span = a2 >= a1 ? a2 - a1 : a2 + Math.PI * 2 - a1
  return [ [ 100, 100 ], [ 0, 100 ], [ 0, 0 ], [ 100, 0 ] ]
    .map(([ x, y ]) => {
      let a = Math.atan2(y - cy, x - cx)
      if (a < 0) a += Math.PI * 2
      let d = a - a1
      if (d < 0) d += Math.PI * 2
      return { x, y, d }
    })
    .filter(c => c.d > 0 && c.d < span)
    .sort((p, q) => p.d - q.d)
    .map(c => [ c.x, c.y ])
}

function centroid(points) {
  const n = points.length
  return [ points.reduce((s, p) => s + p[0], 0) / n, points.reduce((s, p) => s + p[1], 0) / n ]
}

function stripData(el) {
  [ el, ...el.querySelectorAll("*") ].forEach(node => {
    Array.from(node.attributes).forEach(attr => {
      if (attr.name.startsWith("data-") || attr.name === "id") node.removeAttribute(attr.name)
    })
  })
}
