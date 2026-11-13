// Seminar slides built in the app — PowerPoint's five everyday layouts:
//   title    big title + a subtitle line
//   bullets  title + one point per line (optionally revealed one at a time)
//   image    title + a picture (kept on this device, lib/slides/deck_store)
//   quote    a big quote or scripture + who said it
//   section  a divider between parts of the talk
// No DOM, so node can test it (test/javascript/slides_test.mjs).
//
//   seminarSteps(data)        what Next walks through: one step per slide, or
//                             one per bullet when "reveal one by one" is on
//   stepText(data, step)      plain text of a step (stage, live phones)
//   seminarBody(data)         every slide's text — SetlistItem#body
//   bulletsOf(slide)          the slide's points
export const LAYOUTS = [
  { id: "title", name: "Title" },
  { id: "bullets", name: "Title + points" },
  { id: "image", name: "Title + picture" },
  { id: "quote", name: "Big quote / scripture" },
  { id: "section", name: "Section divider" }
]

export const blankSlide = (layout = "bullets") => ({ layout, title: "", text: "", cite: "", image: "", notes: "" })

export function bulletsOf(slide) {
  return String(slide?.text || "").split("\n").map((l) => l.replace(/^\s*(?:[-*•‣▪]|\d+[.)])\s*/, "").trim()).filter(Boolean)
}

export function seminarSteps(data) {
  const steps = []
  ;(data?.slides || []).forEach((slide, i) => {
    const points = slide.layout === "bullets" ? bulletsOf(slide).length : 0
    if (data.reveal && points > 1) {
      for (let k = 1; k <= points; k++) steps.push({ slide: i, shown: k, of: points })
    } else {
      steps.push({ slide: i, shown: points, of: points })
    }
  })
  return steps
}

export function slideText(slide, shown = null) {
  if (!slide) return ""
  const parts = []
  if (slide.title) parts.push(slide.title)
  if (slide.layout === "bullets") {
    const points = bulletsOf(slide)
    parts.push(...points.slice(0, shown ?? points.length).map((p) => `• ${p}`))
  } else if (slide.layout === "quote") {
    if (slide.text) parts.push(`“${slide.text.trim()}”`)
    if (slide.cite) parts.push(`— ${slide.cite}`)
  } else if (slide.text) {
    parts.push(slide.text.trim())
  }
  if (slide.layout === "image" && !parts.length) parts.push("(picture)")
  return parts.join("\n")
}

export function stepText(data, step) {
  return step ? slideText(data?.slides?.[step.slide], step.shown) : ""
}

export function stepLabel(data, step) {
  if (!step) return null
  const n = (data?.slides || []).length
  return step.of > 1 && data.reveal ? `Slide ${step.slide + 1} · point ${step.shown}/${step.of}` : `Slide ${step.slide + 1} of ${n}`
}

export function seminarBody(data) {
  return (data?.slides || []).map((s) => slideText(s)).filter(Boolean).join("\n\n")
}
