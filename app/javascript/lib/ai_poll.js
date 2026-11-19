// Waits for an AI answer that is thinking in the background (AiRequest): the
// first request returned at once with a poll URL; this asks that URL until the
// worker has answered. 202 = still thinking. Network blips (or a phone briefly
// offline) just mean another try a moment later — only `maxMs` ends it.
//
//   const out = await pollAiRequest(url, { accept: "text/html", signal })
//   out: { response } | { unauthorized } | { failed } | { timeout } | { aborted }
export async function pollAiRequest(url, { accept = "application/json", headers = {}, signal, maxMs = 150_000 } = {}) {
  const started = Date.now()
  let delay = 500
  for (;;) {
    if (!(await pause(delay, signal))) return { aborted: true }
    if (Date.now() - started > maxMs) return { timeout: true }
    try {
      const res = await fetch(url, { headers: { Accept: accept, ...headers }, signal, credentials: "same-origin" })
      if (res.status === 401) return { unauthorized: true }
      if (res.status === 404) return { failed: true }
      if (res.ok && res.status !== 202) return { response: res }
    } catch {
      if (signal?.aborted) return { aborted: true }
    }
    delay = Math.min(delay + 250, 1500)
  }
}

// What to tell someone who has been waiting `seconds` (the pending state).
export function thinkingHint(kind, seconds) {
  if (kind === "rabbi_illustration") {
    if (seconds >= 60) return "Still painting — this one is taking longer than usual."
    if (seconds >= 25) return "Nearly there — adding the final details."
    return null
  }
  if (seconds >= 45) return "Still thinking — the study assistant is busy, the answer is on its way."
  if (seconds >= 15) return "Still thinking — a careful answer takes a little longer."
  return null
}

function pause(ms, signal) {
  return new Promise((resolve) => {
    if (signal?.aborted) return resolve(false)
    const timer = setTimeout(() => resolve(true), ms)
    signal?.addEventListener("abort", () => { clearTimeout(timer); resolve(false) }, { once: true })
  })
}
