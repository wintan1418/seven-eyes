// The richer content slides — a scripture set, an imported presentation, a
// seminar deck — drawn into the same projection layer songs and thoughts use
// ([data-preach-slide], .slide-stanza / .slide-img), so the screen looks
// (themes, text size, fades, blank) apply to them exactly as to a song.
//
// A queue item hands presentation_controller `rich = { type, data }`:
//   set      data = scripture set (lib/slides/scripture_set)
//   deck     data = { deck, pages, source, file } — pages from this device (deck_store)
//   seminar  data = { slides, reveal } (lib/slides/seminar)
//
//   richSlides(rich)                      → [{ text, label }] one per Next step
//   paintRichSlide(layer, rich, index)    draw step `index`; returns the element to fit (or null)
//   paintPresenter(root, slide, index)    stage (?stage=1) presenter view: notes + timer
//   richPreviewNodes(rich, button)        Preview's slide list (thumbnails for a deck)
import { setPages, pageText, refLine, withDefaults } from "./scripture_set"
import { seminarSteps, stepText, stepLabel, bulletsOf } from "./seminar"
import { pageUrl, imageUrl } from "./deck_store"

export const RICH_TYPES = { scripture_set: "set", presentation: "deck", seminar: "seminar" }

// The `rich` a queue item projects with, or null for an ordinary item.
export function richFor(item) {
  const type = RICH_TYPES[item?.kind || item?.itemKind]
  return type && item.data ? { type, data: item.data } : null
}

export function richSlides(rich) {
  if (!rich?.data) return null
  if (rich.type === "set") {
    const pages = setPages(rich.data)
    return pages.map((p, i) => ({ text: pageText(p, rich.data), label: `Slide ${i + 1}` }))
  }
  if (rich.type === "deck") {
    const n = Math.max(0, Number(rich.data.pages) || 0)
    return Array.from({ length: n }, (_, i) => ({ text: `Page ${i + 1}`, label: `Page ${i + 1}` }))
  }
  if (rich.type === "seminar") {
    return seminarSteps(rich.data).map((step) => ({ text: stepText(rich.data, step), label: stepLabel(rich.data, step) }))
  }
  return null
}

export function sameRich(a, b) {
  if (!a && !b) return true
  if (!a || !b) return false
  return a.type === b.type && JSON.stringify(a.data) === JSON.stringify(b.data)
}

// ---- the projected slide --------------------------------------------------------

export function paintRichSlide(layer, rich, index) {
  if (rich.type === "set") return paintSet(layer, rich.data, index)
  if (rich.type === "deck") { paintDeckPage(layer, rich.data, index); return null }
  if (rich.type === "seminar") return paintSeminar(layer, rich.data, index)
  return null
}

function paintSet(layer, raw, index) {
  const data = withDefaults(raw)
  const page = setPages(data)[index]
  const box = el("div", `slide-stanza is-set ref-${data.ref_position} ref-style-${data.ref_style}`)
  ;(page?.blocks || []).forEach((block) => {
    const b = el("div", "set-block")
    const ref = el("div", "set-ref", `${refLine(block)}${block.cont ? " (cont.)" : ""}`)
    const words = el("div", "set-words")
    block.verses.forEach((v, i) => {
      if (data.verse_numbers) words.append(el("sup", "set-vnum", String(v.n)))
      words.append(document.createTextNode(`${v.text}${i < block.verses.length - 1 ? " " : ""}`))
    })
    if (data.ref_position === "inline") {
      words.append(document.createTextNode(" "), el("span", "set-ref is-inline", refLine(block)))
      b.append(words)
    } else if (data.ref_position === "bottom") {
      b.append(words, ref)
    } else {
      b.append(ref, words)
    }
    box.append(b)
  })
  layer.append(box)
  return box
}

function paintDeckPage(layer, data, index) {
  const wrap = el("div", "slide-img is-deck")
  const img = document.createElement("img")
  img.alt = `Page ${index + 1}`
  wrap.append(img)
  layer.append(wrap)
  pageUrl(data.deck, index + 1).then((url) => {
    if (url) img.src = url
    else wrap.replaceChildren(el("div", "deck-missing", "This presentation's pages are on the computer that imported it — import the file again here."))
  })
  if (index + 2 <= Number(data.pages)) pageUrl(data.deck, index + 2) // warm the next page
}

function paintSeminar(layer, data, index) {
  const step = seminarSteps(data)[index]
  const slide = data.slides?.[step?.slide]
  if (!slide) return null
  const box = el("div", `slide-stanza slide-seminar layout-${slide.layout}`)
  const title = slide.title ? el("div", "sem-title", slide.title) : null
  if (slide.layout === "title" || slide.layout === "section") {
    if (title) box.append(title)
    if (slide.text) box.append(el("div", "sem-sub", slide.text))
  } else if (slide.layout === "bullets") {
    if (title) box.append(title)
    const list = el("ul", "sem-points")
    bulletsOf(slide).forEach((p, i) => {
      const li = el("li", null, p)
      if (data.reveal && i >= step.shown) li.classList.add("is-hidden")
      if (data.reveal && i === step.shown - 1 && step.shown > 1) li.classList.add("is-new")
      list.append(li)
    })
    box.append(list)
  } else if (slide.layout === "quote") {
    box.append(el("blockquote", "sem-quote", slide.text || ""))
    if (slide.cite) box.append(el("div", "sem-cite", `— ${slide.cite}`))
  } else if (slide.layout === "image") {
    if (title) box.append(title)
    const fig = el("div", "sem-figure")
    const img = document.createElement("img")
    img.alt = slide.title || ""
    fig.append(img)
    box.append(fig)
    imageUrl(slide.image).then((url) => { if (url) img.src = url; else fig.classList.add("is-missing") })
    if (slide.text) box.append(el("div", "sem-sub", slide.text))
  }
  layer.append(box)
  return slide.layout === "image" ? null : box
}

// ---- the stage window as a presenter view ------------------------------------------

let timerStart = null
let timerTick = null

export function paintPresenter(root, slide) {
  const stage = root.querySelector(".ps-stage")
  if (!stage) return
  const rich = slide?.rich
  const on = rich?.type === "seminar" || rich?.type === "deck"
  stage.classList.toggle("is-presenter", on)
  let notes = stage.querySelector("[data-stage-notes]")
  let timer = stage.querySelector("[data-stage-timer]")
  if (!on) {
    notes?.remove()
    timer?.remove()
    clearInterval(timerTick)
    timerTick = null
    timerStart = null
    return
  }
  if (!notes) {
    notes = el("div", "ps-stage-notes")
    notes.dataset.stageNotes = ""
    stage.append(notes)
  }
  if (!timer) {
    timer = el("span", "timer")
    timer.dataset.stageTimer = ""
    timer.title = "Time since this presentation went on screen"
    stage.querySelector(".ps-stage-head")?.insertBefore(timer, stage.querySelector("[data-stage-clock]"))
  }
  timerStart ||= Date.now()
  const paintTimer = () => { timer.textContent = `⏱ ${elapsed(Date.now() - timerStart)}` }
  paintTimer()
  if (!timerTick) timerTick = setInterval(paintTimer, 1000)

  const label = el("div", "lbl", "Speaker notes")
  let text = ""
  if (rich.type === "seminar") {
    const step = seminarSteps(rich.data)[slide.index]
    text = rich.data.slides?.[step?.slide]?.notes || ""
  }
  notes.replaceChildren(label, el("div", "txt", text || (rich.type === "deck" ? "Page notes stay in your PDF — this screen shows where you are." : "No notes for this slide.")))
}

export function resetPresenterTimer() {
  timerStart = Date.now()
}

function elapsed(ms) {
  const s = Math.floor(ms / 1000)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const pad = (x) => String(x).padStart(2, "0")
  return h ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`
}

// ---- Preview's slide list ----------------------------------------------------------

// `button(index, label, content)` makes the clickable row; content is a node.
export function richPreviewNodes(rich, button) {
  const slides = richSlides(rich) || []
  if (rich.type === "deck") {
    return slides.map((s, i) => {
      const img = document.createElement("img")
      img.alt = s.label
      img.loading = "lazy"
      pageUrl(rich.data.deck, i + 1, { thumb: true }).then((url) => { if (url) img.src = url; else img.classList.add("is-missing") })
      const b = button(i, String(i + 1), img)
      b.classList.add("is-thumb")
      return b
    })
  }
  return slides.map((s, i) => button(i, s.label || String(i + 1), document.createTextNode(s.text)))
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
