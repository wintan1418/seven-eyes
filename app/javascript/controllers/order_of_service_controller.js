import { Controller } from "@hotwired/stimulus"
import { orderLines, orderText } from "../lib/slides/order_of_service"

// The order of service, ready to share: a clean sheet of the queue in order,
// "Copy for WhatsApp" (the text, *bold* heading and all), "Share" (the phone's
// share sheet, else WhatsApp Web) and Print. Built on the device from the
// queue it holds, so it works with no signal. Lives on its dialog
// ([data-controller=order-of-service]); opened by the queue's "Order" tool.
export default class extends Controller {
  static targets = [ "title", "date", "words", "sheet", "status" ]
  static values = { name: String }

  connect() {
    this._open = (e) => { if (e.detail?.tool === "order") this.open() }
    window.addEventListener("queue-tool:open", this._open)
  }

  disconnect() {
    window.removeEventListener("queue-tool:open", this._open)
  }

  open() {
    this.items = []
    window.dispatchEvent(new CustomEvent("setlist:request-items", { detail: { reply: (list) => { this.items = list } } }))
    if (!this.titleTarget.value) this.titleTarget.value = this.nameValue || "Order of Service"
    if (!this.dateTarget.value) this.dateTarget.value = nextServiceDate()
    this.element.hidden = false
    this._status("")
    this.paint()
  }

  close(event) {
    event?.preventDefault?.()
    this.element.hidden = true
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  key(event) {
    event.stopPropagation()
    if (event.key === "Escape") { event.preventDefault(); this.close() }
  }

  paint() {
    const head = el("header", "sheet-head")
    head.append(el("h2", null, this.titleTarget.value.trim() || "Order of Service"))
    if (this.dateTarget.value.trim()) head.append(el("p", "date", this.dateTarget.value.trim()))
    const list = el("ol", "sheet-list")
    const lines = orderLines(this.items)
    lines.forEach((l, i) => {
      const li = el("li", `kind-${l.kind}`)
      li.append(el("span", "icon", l.icon), el("span", "txt", l.text))
      if (l.detail) li.append(el("span", "detail", l.detail))
      const body = this.items[i]?.body
      if (this.wordsTarget.checked && body && (l.kind === "scripture_set" || l.kind === "thought")) li.append(el("p", "words", body))
      list.append(li)
    })
    if (!lines.length) list.append(el("li", "empty", "The queue is empty — add the service items first."))
    this.sheetTarget.replaceChildren(head, list)
  }

  text() {
    return orderText(this.items, { title: this.titleTarget.value, date: this.dateTarget.value.trim(), words: this.wordsTarget.checked })
  }

  async copy(event) {
    event?.preventDefault?.()
    const text = this.text()
    this.element.dataset.copied = text
    let ok = false
    try { await navigator.clipboard.writeText(text); ok = true } catch { ok = legacyCopy(text) }
    this._status(ok ? "Copied — paste it into your WhatsApp group" : "Couldn't copy — select the sheet and copy it")
  }

  async share(event) {
    event?.preventDefault?.()
    const text = this.text()
    if (navigator.share) {
      try { await navigator.share({ text }); return } catch { /* cancelled, or not allowed here */ }
    }
    window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, "_blank", "noopener")
  }

  print(event) {
    event?.preventDefault?.()
    document.documentElement.classList.add("is-printing-order")
    const done = () => { document.documentElement.classList.remove("is-printing-order"); window.removeEventListener("afterprint", done) }
    window.addEventListener("afterprint", done)
    window.print()
    setTimeout(done, 1000)
  }

  _status(text) {
    this.statusTarget.textContent = text || ""
  }
}

// "Sunday, 15 November 2026" — the coming Sunday (today if it is Sunday).
function nextServiceDate(now = new Date()) {
  const d = new Date(now)
  d.setDate(d.getDate() + ((7 - d.getDay()) % 7))
  return d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" })
}

function legacyCopy(text) {
  const area = document.createElement("textarea")
  area.value = text
  area.setAttribute("readonly", "")
  area.className = "ps-offscreen"
  document.body.append(area)
  area.select()
  let ok = false
  try { ok = document.execCommand("copy") } catch { ok = false }
  area.remove()
  return ok
}

function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}
