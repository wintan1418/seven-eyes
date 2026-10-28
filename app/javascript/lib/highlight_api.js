// JSON calls to /highlights with the CSRF token, shared by the verse action
// bar. A 401 means a guest tried to save: we raise the "create an account"
// gate (auth:required) and report it so the caller can stop.

export function api(method, url, body) {
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  const opts = { method, credentials: "same-origin", headers: { "X-CSRF-Token": token || "", Accept: "application/json" } }
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json"
    opts.body = JSON.stringify(body)
  }
  return fetch(url, opts)
}

function unauthorized(res) {
  if (res.status !== 401) return false
  window.dispatchEvent(new CustomEvent("auth:required"))
  return true
}

// Highlight whole verses: [{ verseId, length }] → "ok" | "unauthorized" | "failed"
export async function highlightVerses(verses, color) {
  let failed = false
  for (const v of verses) {
    let res
    try {
      res = await api("POST", "/highlights", { highlight: { verse_id: v.verseId, color, char_start: 0, char_end: v.length } })
    } catch { failed = true; continue }
    if (unauthorized(res)) return "unauthorized"
    if (!res.ok) failed = true
  }
  return failed ? "failed" : "ok"
}

// Remove highlights by id → "ok" | "unauthorized" | "failed"
export async function removeHighlights(ids) {
  let failed = false
  for (const id of ids) {
    let res
    try { res = await api("DELETE", `/highlights/${encodeURIComponent(id)}`) } catch { failed = true; continue }
    if (unauthorized(res)) return "unauthorized"
    if (!res.ok && res.status !== 404) failed = true
  }
  return failed ? "failed" : "ok"
}
