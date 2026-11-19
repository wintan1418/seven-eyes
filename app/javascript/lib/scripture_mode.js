// How a scripture search box reads what is typed — EasyWorship's switch
// between searching by reference and searching by words, for live use:
//
//   auto       a reference when it reads as one ("john 3:16"), otherwise the
//              words (the old single-box behaviour, still the default)
//   reference  references only: "jn 3 16", "1cor13:4-7", "john 1O:30" — never
//              a word search, so a reference typed slightly wrong says so
//              instead of listing every verse with "John" in it
//   words      words only: "and he that believeth" — never jumps to a
//              passage, even when the words look like a book ("acts", "job")
//
// The operator's last choice is kept on the device (localStorage, one key for
// the console, the Go box and the /search page) and announced to the other
// boxes on the page with the window event `scripture-mode:change {mode}`.
// Alt+A / Alt+R / Alt+W switch (search_mode controller).
export const MODES = [ "auto", "reference", "words" ]
export const MODE_KEY = "ps-scripture-mode"
export const MODE_EVENT = "scripture-mode:change"
export const MODE_KEYS = { KeyA: "auto", KeyR: "reference", KeyW: "words" }

export function validMode(mode) {
  return MODES.includes(mode) ? mode : "auto"
}

export function readMode(storage = globalStorage()) {
  try { return validMode(storage?.getItem(MODE_KEY)) } catch { return "auto" }
}

export function saveMode(mode, storage = globalStorage()) {
  const m = validMode(mode)
  try { storage?.setItem(MODE_KEY, m) } catch { /* private window: this page only */ }
  return m
}

// Alt+A / Alt+R / Alt+W → that mode; anything else → null. By key position
// (event.code), so a Mac's Option+R ("®") and a French keyboard still work.
export function modeForKey(event) {
  if (!event?.altKey || event.ctrlKey || event.metaKey) return null
  return MODE_KEYS[event.code] || null
}

// Reference mode forgives what fast typing gets wrong before the parser reads
// it: a letter O for a zero next to a number ("john 1O:30", "ps 1o3"), "v"/"vs"
// already handled by the parser. Only touches an O that sits against a digit
// (or a ":" before one), never one inside a book name ("1co13", "hos 1").
export function tidyReference(raw) {
  let s = String(raw ?? "").replace(/\s+/g, " ").trim()
  for (let i = 0; i < 3; i++) s = s.replace(/(\d)[oO]/g, (_, d) => `${d}0`)
  s = s.replace(/(^|[\s:.,-])[oO](?=\d)/g, (_, before) => `${before}0`)
  return s
}

// What the placeholder says in each mode.
export const PLACEHOLDERS = {
  auto: "Type a reference like John 3:16, or words from a verse",
  reference: "Reference — John 3:16 · jn 3 16 · 1cor13:4-7",
  words: "Words — and he that believeth"
}

function globalStorage() {
  try { return typeof localStorage === "undefined" ? null : localStorage } catch { return null }
}
