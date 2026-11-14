// Open a verse the way a Bible app does: the WHOLE chapter in the pane,
// scrolled to the verse, the verse marked. Used by search results (sheet and
// /search page), cross-references, AI find, word study, Rabbi — anything that
// "opens" a reference — through the pane's own form, so a downloaded Bible
// answers it offline exactly as it answers the passage picker.
//
//   splitReference("Deuteronomy 32:2-4") → { chapterRef: "Deuteronomy 32", start: 2, end: 4 }
//   splitReference("John 3")             → null  (nothing to focus — open as is)
//   openInPane(frame, "Deuteronomy 32:2", { translationId })
//
// The verse-focus controller (on .ps-workspace) marks the verse once the
// frame has rendered (takeFocus).

const pending = new Map() // frame id → { chapterRef, start, end }

export function splitReference(reference) {
  const m = String(reference || "").trim().match(/^(.+?\S)\s+(\d+):(\d+)(?:\s*[-–]\s*(\d+))?$/)
  if (!m) return null
  const start = parseInt(m[3], 10)
  const end = m[4] ? Math.max(start, parseInt(m[4], 10)) : start
  return { chapterRef: `${m[1]} ${m[2]}`, start, end }
}

export function focusParam({ start, end }) {
  return end > start ? `${start}-${end}` : String(start)
}

export function parseFocus(value) {
  const m = String(value || "").match(/^(\d+)(?:-(\d+))?$/)
  if (!m) return null
  const start = parseInt(m[1], 10)
  return { start, end: m[2] ? Math.max(start, parseInt(m[2], 10)) : start }
}

// Load `reference` into the pane frame. Returns false when the pane form
// isn't there (the caller then does whatever it did before).
export function openInPane(frame, reference, { translationId = null } = {}) {
  const form = frame?.querySelector("form.rd-pane-form")
  const input = form?.querySelector("input[name='pane[reference]']")
  if (!input) return false
  const split = splitReference(reference)
  input.value = split ? split.chapterRef : reference
  const select = form.querySelector("select[name='pane[translation_id]']")
  if (translationId && select && [ ...select.options ].some((o) => o.value === String(translationId))) {
    select.value = String(translationId)
  }
  if (split) pending.set(frame.id, split)
  else pending.delete(frame.id)
  form.requestSubmit()
  return true
}

export function takeFocus(frameId) {
  const focus = pending.get(frameId)
  pending.delete(frameId)
  return focus || null
}

export function primaryPane() {
  return document.querySelector(".ps-workspace .ps-pane.is-active-pane") ||
    document.querySelector(".ps-workspace .ps-pane")
}
