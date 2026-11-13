// Root words — the DOM side: the projected Word Study slide (operator,
// projector and stage share it through presentation_controller's slide path),
// the stage display's panels, the live phones' card and the Preview card.
// Data: a word study from lib/root_words.js (buildWordStudy / normalizeWordStudy).
import { languageLabel, occurrencesLabel } from "./root_words"

const MIN_SCALE = 0.45

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

// The original word, in its script: Hebrew right-to-left, each in a font that
// carries it (Noto Serif Hebrew / Noto Serif, bundled — see root_words.css).
export function lemmaNode(word, className = "rw-lemma") {
  const node = el("div", className, word.lemma || word.translit || word.s)
  if (word.lang === "hebrew") { node.lang = "he"; node.dir = "rtl" } else { node.lang = "grc"; node.dir = "ltr" }
  return node
}

// The verse with the chosen English word marked.
export function verseNode(word, className) {
  const p = el("p", className)
  const text = word.verse || ""
  const m = word.mark
  if (m && m[1] <= text.length) {
    p.append(document.createTextNode(text.slice(0, m[0])), el("mark", "rw-mark", text.slice(m[0], m[1])), document.createTextNode(text.slice(m[1])))
  } else {
    p.textContent = text
  }
  return p
}

function eyebrow(word) {
  const lang = languageLabel(word.s)
  return word.english ? `The ${lang} word for “${word.english}”` : `The ${lang} word`
}

// className "slide-stanza" on the projected panel lets a projection theme's
// text colour (preach_queue.css / slide themes) reach the word panel too.
function wordPanel(word, { big = false, className = "rw-word" } = {}) {
  const panel = el("div", className)
  panel.append(el("div", "rw-eyebrow slide-title", eyebrow(word)))
  panel.append(lemmaNode(word))
  if (word.translit) panel.append(el("div", "rw-translit", word.translit))
  if (word.say) {
    const say = el("div", "rw-say")
    say.append(el("span", "rw-say-lbl", "say"), document.createTextNode(word.say))
    panel.append(say)
  }
  panel.append(el("div", "rw-rule"))
  if (word.gloss) panel.append(el("div", "rw-gloss", word.gloss))
  if (word.note) {
    const note = el("div", "rw-note")
    note.append(el("span", "rw-note-lbl", "✦ AI-assisted note"), el("span", "rw-note-txt", word.note))
    panel.append(note)
  }
  const meta = [ `Strong’s ${word.s}`, occurrencesLabel(word.n) ].filter(Boolean).join("  ·  ")
  panel.append(el("div", "rw-meta", meta))
  if (big && (word.english || word.reference)) {
    const foot = [ word.english && `“${word.english}”`, word.reference ].filter(Boolean).join(" — ")
    panel.append(el("div", "rw-foot", foot))
  }
  return panel
}

// The Word Study slide into the preach slide layer. Layout "verse": the verse
// with the word marked beside (wide screens) or above (tall) the word panel;
// "word": the word alone, full screen. Elements reveal in a short stagger.
export function renderWordSlide(layer, word) {
  const slide = el("div", `rw-slide is-${word.layout === "word" ? "word" : "verse"} rw-lang-${word.lang}`)
  slide.dataset.strongs = word.s
  if (word.layout !== "word" && word.verse) {
    const side = el("div", "rw-verse-side")
    const ref = [ word.reference, word.translation ].filter(Boolean).join(" · ")
    if (ref) side.append(el("div", "rw-ref slide-title", ref))
    side.append(verseNode(word, "rw-verse slide-stanza"))
    slide.append(side)
  }
  slide.append(wordPanel(word, { big: word.layout === "word" || !word.verse, className: "rw-word slide-stanza" }))
  layer.replaceChildren(slide)
  fitWordSlide(layer, slide)
  return slide
}

// Shrink the whole slide (one CSS variable) until it fits the layer.
export function fitWordSlide(layer, slide) {
  let scale = 1
  slide.style.setProperty("--rw-fit", "1")
  for (let i = 0; i < 16 && scale > MIN_SCALE; i++) {
    if (layer.scrollHeight <= layer.clientHeight + 1 && slide.scrollWidth <= slide.clientWidth + 1) break
    scale *= 0.92
    slide.style.setProperty("--rw-fit", scale.toFixed(3))
  }
}

// Stage display: NOW = the word, NEXT (the big panel) = its meaning, the AI
// note if projected, and the verse it came from (Esc / Back returns there).
export function renderStageWord({ now, next, ref }, word) {
  if (ref) ref.textContent = `Word study · ${word.reference || ""}`.trim()
  if (now) {
    const wrap = el("div", `txt rw-stage rw-lang-${word.lang}`)
    wrap.append(lemmaNode(word, "rw-stage-lemma"))
    wrap.append(el("div", "rw-stage-line", [ word.translit, word.say && `(${word.say})`, word.s ].filter(Boolean).join("  ")))
    now.replaceChildren(el("div", "lbl", `on screen · word study${word.english ? ` · “${word.english}”` : ""}`), wrap)
  }
  if (next) {
    const txt = el("div", "txt rw-stage")
    if (word.gloss) txt.append(el("div", "rw-stage-gloss", word.gloss))
    if (word.note) txt.append(el("div", "rw-stage-note", word.note))
    txt.append(verseNode(word, "rw-stage-verse"))
    next.replaceChildren(el("div", "lbl", `meaning · then back to ${word.reference || "the verse"} (Esc / Back)`), txt)
  }
}

// A live follower's phone: the word card in place of the passage.
export function renderPhoneWord(container, word, title) {
  const card = el("article", `ps-live-slide rw-phone rw-lang-${word.lang}`)
  card.dataset.strongs = word.s
  card.dataset.title = title || ""
  if (title) {
    card.append(el("div", "ref-title", title))
    card.append(el("div", "rule"))
  }
  card.append(wordPanel(word, { big: true }))
  if (word.verse) card.append(verseNode(word, "rw-phone-verse"))
  container.replaceChildren(card)
  return card
}

// The Preview card in the operator console: a compact word card.
export function renderPreviewWord(container, word) {
  const card = el("div", `rw-preview rw-lang-${word.lang}`)
  card.append(lemmaNode(word, "rw-preview-lemma"))
  card.append(el("span", "rw-preview-line", [ word.translit, word.s, word.gloss ].filter(Boolean).join(" · ")))
  container.replaceChildren(card)
}
