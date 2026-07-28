// Never let a failed Turbo Frame request wipe Scripture off the screen.
//
// When a frame navigation gets back a response without the matching
// <turbo-frame> — a 502 while a deploy restarts the server, an error page,
// a lost guest session — Turbo's default is to blank the frame and print
// "Content missing". Mid-sermon that erases the projected text. Instead:
// keep whatever the frame already shows, quietly tell the operator, and
// let a redirect to sign-in proceed as a real page visit.
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

  const frame = event.target
  frame.removeAttribute("busy")
  frame.removeAttribute("aria-busy")

  const status = response ? response.status : 0
  const text = status >= 500 || status === 0
    ? "The server hiccuped — kept the page as it was. Try again in a moment."
    : "Couldn't load that — kept the page as it was."

  let toast = document.querySelector(".ps-toast.js-flash")
  if (!toast) {
    toast = document.createElement("div")
    toast.className = "ps-toast js-flash"
    document.body.appendChild(toast)
  }
  toast.innerHTML = `<span class="check">✦</span> ${text}`
  clearTimeout(toast._frameGuardTimer)
  toast.style.opacity = "1"
  toast._frameGuardTimer = setTimeout(() => { toast.style.opacity = "0" }, 4000)
})
