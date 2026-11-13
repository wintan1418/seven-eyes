// The order of service as text — for the WhatsApp group, the choir, the
// sound desk. No DOM, so node can test it (test/javascript/slides_test.mjs).
//
//   orderText(items, { title, date, words })  WhatsApp-ready text (*bold* title)
//   orderLines(items)                          [{ n, icon, kind, text, detail }]
const ICONS = { scripture: "📖", scripture_set: "📖", song: "🎵", thought: "💬", picture: "🖼", presentation: "📊", seminar: "🎓" }
const NAMES = { picture: "Picture", presentation: "Presentation", seminar: "Seminar" }

export function orderLines(items) {
  return (items || []).map((item, i) => {
    const label = (item.label || item.title || item.reference || "").trim()
    let detail = null
    if (item.kind === "presentation" && item.data?.pages) detail = `${item.data.pages} pages`
    else if (item.kind === "seminar" && item.data?.slides) detail = `${item.data.slides.length} slides`
    const text = NAMES[item.kind] ? `${NAMES[item.kind]}: ${label || NAMES[item.kind]}` : label
    return { n: i + 1, icon: ICONS[item.kind] || "•", kind: item.kind, text, detail }
  })
}

export function orderText(items, { title = "Order of Service", date = "", words = false } = {}) {
  const head = [ `*${title.trim() || "Order of Service"}*` ]
  if (date) head.push(date)
  const lines = orderLines(items).map((l, i) => {
    let line = `${l.n}. ${l.icon} ${l.text}${l.detail ? ` (${l.detail})` : ""}`
    const item = items[i]
    if (words && item.body && (item.kind === "scripture_set" || item.kind === "thought")) line += `\n${indent(item.body)}`
    return line
  })
  return [ ...head, "", ...(lines.length ? lines : [ "(nothing in the order yet)" ]) ].join("\n")
}

function indent(text) {
  return String(text).trim().split("\n").filter((l) => l.trim()).map((l) => `   ${l.trim()}`).join("\n")
}
