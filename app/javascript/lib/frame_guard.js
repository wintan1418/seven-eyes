// Never let a failed Turbo Frame request wipe Scripture off the screen — and
// never fail silently either.
//
// When a frame navigation gets back a response without the matching
// <turbo-frame> — a 502 while a deploy restarts the server, an error page,
// a lost guest session (404) — Turbo's default is to blank the frame and print
// "Content missing". Mid-sermon that erases the projected text. Instead:
// keep whatever the frame already shows, put a visible notice INSIDE that
// frame (a toast can hide behind drawers), and let a redirect to sign-in
// proceed as a real page visit. Network failures (no response at all) get
// the same treatment.

const NOTICE_CLASS = "ps-frame-error"

function messageFor(status) {
  if (status === 404) {
    return {
      text: "Couldn't load that — your guest session may have expired. Reload to continue.",
      reload: true
    }
  }
  if (status === 0) return { text: "Couldn't reach the server — check your connection and try again.", reload: false }
  if (status >= 500) return { text: "The server hiccuped — kept the text as it was. Try again in a moment.", reload: true }
  return { text: "Couldn't load that — kept the text as it was.", reload: false }
}

function showFrameNotice(frame, status) {
  const { text, reload } = messageFor(status)
  frame.removeAttribute("busy")
  frame.removeAttribute("aria-busy")

  frame.querySelectorAll(`:scope > .${NOTICE_CLASS}`).forEach(el => el.remove())
  const notice = document.createElement("div")
  notice.className = `${NOTICE_CLASS} relative z-50 m-2 flex flex-wrap items-center gap-2 border border-rubric ` +
    "bg-vellum-0 px-3 py-2 font-serif text-sm text-rubric shadow"
  notice.setAttribute("role", "alert")

  const label = document.createElement("span")
  label.className = "flex-1"
  label.textContent = `⚠ ${text}`
  notice.appendChild(label)

  if (reload) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "cursor-pointer border border-gold px-2 py-0.5 font-display text-[10px] uppercase tracking-[0.18em]"
    btn.textContent = "Reload"
    btn.addEventListener("click", () => window.location.reload())
    notice.appendChild(btn)
  }

  const close = document.createElement("button")
  close.type = "button"
  close.className = "cursor-pointer px-1 text-sepia-mute"
  close.setAttribute("aria-label", "Dismiss")
  close.textContent = "✕"
  close.addEventListener("click", () => notice.remove())
  notice.appendChild(close)

  frame.prepend(notice)
  clearTimeout(frame._frameGuardTimer)
  if (!reload) frame._frameGuardTimer = setTimeout(() => notice.remove(), 10000)
}

// A fresh, successful render of the frame replaces its content (and any notice).
document.addEventListener("turbo:frame-missing", (event) => {
  event.preventDefault()

  const response = event.detail && event.detail.response
  const location = response && response.url ? new URL(response.url, window.location.origin) : null

  // A redirect to sign-in must actually go there, not die inside the frame.
  if (location && location.pathname.startsWith("/session")) {
    if (event.detail.visit) event.detail.visit(location.href)
    else window.Turbo.visit(location.href)
    return
  }

  showFrameNotice(event.target, response ? response.status : 0)
})

// No response at all (offline, DNS, server down mid-restart).
document.addEventListener("turbo:fetch-request-error", (event) => {
  const target = event.target instanceof Element ? event.target : null
  const frame = target && (target.closest("turbo-frame") ||
    (target.dataset && target.dataset.turboFrame && document.getElementById(target.dataset.turboFrame)))
  if (frame && frame.tagName === "TURBO-FRAME") showFrameNotice(frame, 0)
})
