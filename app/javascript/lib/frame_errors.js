// Shared failure handling for drawers whose content arrives in a Turbo Frame
// (the Rabbi, AI "Find a verse"). Without it a failed request leaves the
// "reading…" placeholder up forever.
//
//   const stop = watchFrameErrors(hostElement, (frame, kind) => { ... })
//   kind: "auth"  — 401, or a redirect to sign-in: an account is needed
//         "error" — a missing frame (5xx, error page) or a network failure
//
// Handled events stop here, so the global frame_guard toast doesn't also fire.
// The `auth:required` window event (auth_gate controller) is dispatched for
// "auth" before the callback runs. Returns a function that removes the listeners.
export function watchFrameErrors(host, onFailure) {
  const onMissing = (event) => {
    const frame = event.target
    event.preventDefault()
    event.stopPropagation()
    settle(frame)
    const response = event.detail?.response
    onFailure(frame, needsAccount(response) ? auth() : "error")
  }

  const onFetchError = (event) => {
    const frame = frameFor(host, event) || event.target.closest?.("turbo-frame")
    if (!frame || !host.contains(frame)) return
    settle(frame)
    onFailure(frame, "error")
  }

  host.addEventListener("turbo:frame-missing", onMissing)
  host.addEventListener("turbo:fetch-request-error", onFetchError)
  return () => {
    host.removeEventListener("turbo:frame-missing", onMissing)
    host.removeEventListener("turbo:fetch-request-error", onFetchError)
  }
}

function needsAccount(response) {
  if (!response) return false
  if (response.status === 401) return true
  try {
    return response.redirected && new URL(response.url, window.location.origin).pathname.startsWith("/session")
  } catch { return false }
}

function auth() {
  window.dispatchEvent(new CustomEvent("auth:required"))
  return "auth"
}

// The frame a fetch event belongs to: the Turbo-Frame request header names it.
function frameFor(host, event) {
  const id = event.detail?.request?.headers?.["Turbo-Frame"]
  const frame = id ? document.getElementById(id) : null
  return frame && host.contains(frame) ? frame : null
}

function settle(frame) {
  frame.removeAttribute("busy")
  frame.removeAttribute("aria-busy")
}
