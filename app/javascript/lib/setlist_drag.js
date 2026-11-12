// Drag-to-reorder for the preach queue, on pointer events so a mouse, a pen
// and a finger all work the same. The row follows the pointer; the rows it
// passes slide out of the way; on release onDrop(from, to) gets the indices.
// The ⠿ grip is the only handle (touch-action: none in CSS), so scrolling the
// list with a finger still scrolls.
const EDGE_PX = 36
const SCROLL_STEP = 10

export function startDrag(event, { list, row, onDrop }) {
  if (event.pointerType === "mouse" && event.button !== 0) return
  event.preventDefault()
  const handle = event.currentTarget || event.target
  const rows = Array.from(list.querySelectorAll(".ps-setlist-item"))
  const from = rows.indexOf(row)
  if (from < 0) return
  try { handle.setPointerCapture?.(event.pointerId) } catch { /* synthetic event */ }

  const startY = event.clientY
  const startScroll = list.scrollTop
  const rects = rows.map((r) => r.getBoundingClientRect())
  const step = rows.length > 1 ? Math.abs(rects[Math.min(1, rows.length - 1)].top - rects[0].top) || rects[from].height : rects[from].height
  let to = from
  let moved = false

  row.classList.add("is-dragging")
  list.classList.add("is-sorting")

  const place = (clientY) => {
    const scrolled = list.scrollTop - startScroll
    const dy = clientY - startY + scrolled
    if (Math.abs(dy) > 3) moved = true
    row.style.transform = `translateY(${dy}px)`
    // Where the dragged row's middle now sits among the others.
    const middle = rects[from].top + rects[from].height / 2 + dy
    to = rects.filter((r, i) => i !== from && middle > r.top + r.height / 2).length
    rows.forEach((r, i) => {
      if (i === from) return
      let shift = 0
      if (from < to && i > from && i <= to) shift = -step
      else if (from > to && i >= to && i < from) shift = step
      r.style.transform = shift ? `translateY(${shift}px)` : ""
    })
  }

  let lastY = startY
  const onMove = (e) => {
    lastY = e.clientY
    const box = list.getBoundingClientRect()
    if (e.clientY < box.top + EDGE_PX) list.scrollTop -= SCROLL_STEP
    else if (e.clientY > box.bottom - EDGE_PX) list.scrollTop += SCROLL_STEP
    place(e.clientY)
  }
  const onScroll = () => place(lastY)

  const finish = (commit) => {
    window.removeEventListener("pointermove", onMove)
    window.removeEventListener("pointerup", onUp)
    window.removeEventListener("pointercancel", onCancel)
    list.removeEventListener("scroll", onScroll)
    rows.forEach((r) => { r.style.transform = "" })
    row.classList.remove("is-dragging")
    list.classList.remove("is-sorting")
    if (commit && moved && to !== from) onDrop(from, to)
  }
  const onUp = () => finish(true)
  const onCancel = () => finish(false)

  // On the window, so the drag holds even where pointer capture isn't granted.
  window.addEventListener("pointermove", onMove)
  window.addEventListener("pointerup", onUp)
  window.addEventListener("pointercancel", onCancel)
  list.addEventListener("scroll", onScroll)
}
