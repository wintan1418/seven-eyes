import { Controller } from "@hotwired/stimulus"

// The operator console — preach mode's default layout on a laptop or desktop.
// Lives on .ps-root (operator window only). It owns LAYOUT, nothing else:
//
//   view       "console" (default) or "focus" — the full-screen slide of before.
//              The toolbar's ⤢ button or F switches; remembered on this device
//              per account (localStorage "ps-preach-view:<owner>").
//              .is-console goes on the root only while preaching, on a screen
//              ≥1100×560 and in console view; otherwise nothing changes at all.
//   geometry   the console partial (_console) draws the regions; each
//              [data-cx-slot] is measured into --cx-<slot>-x/y/w/h on the root
//              and console.css lays the existing pieces (the presented pane,
//              the queue, Preview, the verse list, the song bank…) over them.
//              Their markup, controllers and targets stay where they always
//              were — so Focus view is the very same DOM.
//   tabs       the library tabs (data-cx-tab on the root); a tab whose
//              [data-cx-mount] panel is empty stays hidden until a feature
//              renders into it.
//   sizes      drag the gutters to resize the service list and the library
//              (localStorage "ps-console-sizes").
//   add card   the queue's add/edit form floats in a card over Preview when
//              an Add button is pressed, an item is edited or the form gets focus.
//
// Keys (console view): F Focus/Console · G or / → the library's reference box.
// Window events out: console:on / console:off, console:tour.
const QUERY = "(min-width: 1100px) and (min-height: 560px)"
const SIZES_KEY = "ps-console-sizes"
const LIMITS = { service: [ 220, 460 ], library: [ 170, 560 ] }

export default class extends Controller {
  connect() {
    if (this.element.classList.contains("is-output")) return
    this._mq = window.matchMedia(QUERY)
    this._view = this._loadView()
    this._sizes = this._loadSizes()
    this._applySizes()
    this._onMq = () => this._apply()
    this._mq.addEventListener?.("change", this._onMq)
    this._classes = new MutationObserver(() => this._rootChanged())
    this._classes.observe(this.element, { attributes: true, attributeFilter: [ "class" ] })
    this._wasPreaching = this.element.classList.contains("is-preaching")
    this._resizeObs = new ResizeObserver(() => this._measure())
    this.element.querySelectorAll(".cx [data-cx-slot]").forEach((slot) => this._resizeObs.observe(slot))
    this._onWinResize = () => this._measure()
    window.addEventListener("resize", this._onWinResize)
    this._onKey = (e) => this._key(e)
    window.addEventListener("keydown", this._onKey, true)
    this._onFocusIn = (e) => { if (this._on && e.target.closest?.(".ps-setlist-form")) this._openCard() }
    this.element.addEventListener("focusin", this._onFocusIn)
    this._onPointer = (e) => this._outside(e)
    document.addEventListener("pointerdown", this._onPointer, true)
    this._forms = new MutationObserver(() => this._formChanged())
    const host = this.element.querySelector(".ps-setlist-host")
    if (host) this._forms.observe(host, { subtree: true, attributes: true, attributeFilter: [ "class" ], childList: true })
    // The root-word card lives in the Word study tab: it opens there (W, ℵ),
    // and the library goes back to where it was when it closes.
    this._words = new MutationObserver(() => this._wordsChanged())
    const card = this.element.querySelector(".rw-card")
    if (card) this._words.observe(card, { attributes: true, attributeFilter: [ "hidden" ] })
    this._mounts = new MutationObserver(() => this._paintTabs())
    this.element.querySelectorAll(".cx [data-cx-mount]").forEach((m) => this._mounts.observe(m, { childList: true }))
    this._listeners = {
      "preview:changed": (e) => this._previewChanged(e.detail),
      "preach:state": () => this._syncGoLive()
    }
    Object.entries(this._listeners).forEach(([ name, fn ]) => window.addEventListener(name, fn))
    this._tab = "scripture"
    this._paintTabs()
    this._apply()
  }

  disconnect() {
    this._mq?.removeEventListener?.("change", this._onMq)
    this._classes?.disconnect()
    this._resizeObs?.disconnect()
    this._forms?.disconnect()
    this._mounts?.disconnect()
    this._words?.disconnect()
    window.removeEventListener("resize", this._onWinResize)
    window.removeEventListener("keydown", this._onKey, true)
    this.element.removeEventListener("focusin", this._onFocusIn)
    document.removeEventListener("pointerdown", this._onPointer, true)
    Object.entries(this._listeners || {}).forEach(([ name, fn ]) => window.removeEventListener(name, fn))
    this.element.classList.remove("is-console", "cx-adding")
  }

  // ---- console ⇄ focus ---------------------------------------------------------------

  toggleView(event) {
    event?.preventDefault?.()
    this._view = this._view === "focus" ? "console" : "focus"
    this._saveView()
    this._apply()
  }

  _rootChanged() {
    const preaching = this.element.classList.contains("is-preaching")
    if (preaching !== this._wasPreaching) {
      this._wasPreaching = preaching
      if (preaching) this._view = this._loadView() // another window may have switched it
      this._apply()
    }
    // The song bank opened from the add form: it lives in the Songs tab here.
    const bank = this.element.classList.contains("is-song-bank-open")
    if (this._on && bank && !this._bankOpen && this._tab !== "songs") {
      this._closeCard()
      this._select("songs", { open: false })
    }
    this._bankOpen = bank
  }

  _apply() {
    const on = this.element.classList.contains("is-preaching") && this._mq.matches && this._view !== "focus"
    const changed = on !== this._on
    this._on = on
    this.element.classList.toggle("is-console", on)
    this.element.dataset.cxTab = this._tab
    const toggle = this.element.querySelector("[data-cx-view-toggle]")
    if (toggle) {
      toggle.setAttribute("aria-pressed", String(this._view === "focus"))
      const label = toggle.querySelector("[data-cx-view-label]")
      if (label) label.textContent = this._view === "focus" ? "Console" : "Focus"
    }
    if (!on) this._closeCard()
    if (!changed) return
    if (!on) this._closeBank() // in Focus view the song bank is a dialog again
    if (on) {
      // The queue is always on show in the console.
      window.dispatchEvent(new CustomEvent("setlist:open"))
      this._measure()
      this._syncGoLive()
      // Quick Present opens preach on the Go box: the relayout drops its focus.
      requestAnimationFrame(() => this.element.querySelector(".ps-preach-jump:not([hidden]) input")?.focus())
    }
    window.dispatchEvent(new CustomEvent(on ? "console:on" : "console:off"))
    // The live verse / slide refits to the room it has now.
    requestAnimationFrame(() => window.dispatchEvent(new Event("resize")))
  }

  // ---- geometry ------------------------------------------------------------------------

  _measure() {
    if (!this._on) return
    cancelAnimationFrame(this._measureFrame)
    this._measureFrame = requestAnimationFrame(() => {
      const style = this.element.style
      this.element.querySelectorAll(".cx [data-cx-slot]").forEach((slot) => {
        const name = slot.dataset.cxSlot
        const r = slot.getBoundingClientRect()
        style.setProperty(`--cx-${name}-x`, `${Math.round(r.left)}px`)
        style.setProperty(`--cx-${name}-y`, `${Math.round(r.top)}px`)
        style.setProperty(`--cx-${name}-w`, `${Math.round(r.width)}px`)
        style.setProperty(`--cx-${name}-h`, `${Math.round(r.height)}px`)
      })
    })
  }

  // ---- tabs ------------------------------------------------------------------------------

  selectTab(event) {
    event?.preventDefault?.()
    this._select(event.params?.tab || event.currentTarget?.dataset.tab || "scripture")
  }

  _select(tab, { open = true } = {}) {
    this._tab = tab
    this.element.dataset.cxTab = tab
    this._paintTabs()
    this._measure()
    if (tab === "songs" && open) window.dispatchEvent(new CustomEvent("song-bank:open"))
    if (tab !== "songs") this._closeBank()
    if (tab === "words" && open && this.element.querySelector(".rw-card")?.hidden) {
      this._beforeWords = null
      this.element.querySelector(".cx-words-empty [data-root-words-open='live']")?.click()
    }
    if (tab === "looks") {
      const panel = this.element.querySelector(".ps-screen-panel")
      if (panel?.hidden) this.element.querySelector("[data-action~='presentation#toggleScreenPanel']")?.click()
    }
  }

  _wordsChanged() {
    const open = !this.element.querySelector(".rw-card")?.hidden
    if (!this._on || open === this._wordsOpen) { this._wordsOpen = open; return }
    this._wordsOpen = open
    if (open && this._tab !== "words") {
      this._beforeWords = this._tab
      this._select("words")
    } else if (!open && this._tab === "words" && this._beforeWords) {
      this._select(this._beforeWords)
      this._beforeWords = null
    }
  }

  _closeBank() {
    if (!this.element.classList.contains("is-song-bank-open")) return
    this.element.querySelector(".ps-song-bank [data-action~='song-bank#close']")?.click()
  }

  _paintTabs() {
    this.element.querySelectorAll(".cx-tab").forEach((tab) => {
      const panel = this.element.querySelector(`.cx-panel[data-tab="${tab.dataset.tab}"]`)
      if (panel?.hasAttribute("data-cx-mount")) tab.hidden = panel.children.length === 0
      const on = tab.dataset.tab === this._tab
      tab.classList.toggle("is-on", on)
      tab.setAttribute("aria-selected", String(on))
    })
  }

  // ---- resizing (the gutters) --------------------------------------------------------------

  resize(event) {
    const edge = event.params?.edge
    if (!LIMITS[edge] || event.button > 0) return
    event.preventDefault()
    const start = { x: event.clientX, y: event.clientY, size: this._current(edge) }
    const gutter = event.currentTarget
    gutter.setPointerCapture?.(event.pointerId)
    this.element.classList.add("cx-resizing")
    const move = (e) => {
      const delta = edge === "service" ? e.clientX - start.x : start.y - e.clientY
      const [ min, max ] = LIMITS[edge]
      this._sizes[edge] = Math.round(Math.min(max, Math.max(min, start.size + delta)))
      this._applySizes()
    }
    const up = () => {
      gutter.removeEventListener("pointermove", move)
      gutter.removeEventListener("pointerup", up)
      gutter.removeEventListener("pointercancel", up)
      this.element.classList.remove("cx-resizing")
      this._saveSizes()
      window.dispatchEvent(new Event("resize"))
    }
    gutter.addEventListener("pointermove", move)
    gutter.addEventListener("pointerup", up)
    gutter.addEventListener("pointercancel", up)
  }

  _current(edge) {
    const region = this.element.querySelector(`.cx [data-cx-region="${edge}"]`)
    const r = region?.getBoundingClientRect()
    return edge === "service" ? (r?.width || 300) : (r?.height || 260)
  }

  _applySizes() {
    const s = this._sizes
    if (s.service) this.element.style.setProperty("--cx-service-size", `${s.service}px`)
    if (s.library) this.element.style.setProperty("--cx-library-size", `${s.library}px`)
    this._measure()
  }

  _loadSizes() {
    try { return JSON.parse(localStorage.getItem(SIZES_KEY) || "{}") || {} } catch { return {} }
  }

  _saveSizes() {
    try { localStorage.setItem(SIZES_KEY, JSON.stringify(this._sizes)) } catch { /* private mode */ }
  }

  // ---- the add / edit card ---------------------------------------------------------------

  openAdd(event) {
    event?.preventDefault?.()
    const kind = event?.params?.kind || "scripture"
    const form = this.element.querySelector(".ps-setlist-form")
    if (!form) return
    const radio = form.querySelector(`input[name='setlist_item[kind]'][value='${kind}']`)
    if (radio && !radio.checked) radio.click()
    this._openCard(kind)
    const field = kind === "scripture" ? form.querySelector(".ref-field")
      : kind === "picture" ? form.querySelector("input[type=file].image-field, .image-field[type=file]")
        : form.querySelector(".title-field")
    requestAnimationFrame(() => field?.focus())
  }

  closeAdd(event) {
    event?.preventDefault?.()
    const form = this.element.querySelector(".ps-setlist-form")
    const cancel = form?.querySelector(".cancel-edit")
    if (form?.classList.contains("is-editing") && cancel && !cancel.hidden) cancel.click()
    this._closeCard()
    document.activeElement?.blur?.()
  }

  _openCard(kind = null) {
    if (!this._on) return
    this.element.classList.add("cx-adding")
    const form = this.element.querySelector(".ps-setlist-form")
    const title = this.element.querySelector("[data-cx-add-title]")
    if (title) {
      const k = kind || form?.querySelector("input[name='setlist_item[kind]']:checked")?.value || "scripture"
      const editing = form?.classList.contains("is-editing")
      const noun = { scripture: "scriptures", song: "a song", thought: "a thought", picture: "a picture" }[k] || "an item"
      title.textContent = editing ? "Edit this item" : `Add ${noun} to the service`
    }
  }

  _closeCard() {
    this.element.classList.remove("cx-adding")
  }

  _formChanged() {
    const form = this.element.querySelector(".ps-setlist-form")
    const editing = !!form?.classList.contains("is-editing")
    if (editing && !this._editing) this._openCard()
    else if (!editing && this._editing) this._closeCard() // saved or cancelled
    this._editing = editing
    if (this.element.classList.contains("cx-adding")) this._openCard()
  }

  _outside(event) {
    if (!this.element.classList.contains("cx-adding")) return
    const t = event.target
    if (t.closest?.(".ps-setlist-form, .cx-addcard, .cx-add, .ps-song-bank, .ps-queue-toast")) return
    this.closeAdd()
  }

  // ---- keys ---------------------------------------------------------------------------------

  _key(event) {
    if (!this.element.classList.contains("is-preaching")) return
    if (event.metaKey || event.ctrlKey || event.altKey) return
    const editable = isEditable(event.target)
    if (event.key === "Escape" && this.element.classList.contains("cx-adding")) {
      // Esc in a field cancels an edit first (setlist), then this closes the card;
      // never does it leave preach mode (presentation ignores a prevented Esc).
      event.preventDefault()
      setTimeout(() => this.closeAdd(), 0)
      return
    }
    if (editable || event.defaultPrevented) return
    if ((event.key === "f" || event.key === "F") && this._mq.matches && !this._modalOpen()) {
      event.preventDefault()
      event.stopPropagation()
      this.toggleView()
      return
    }
    if (this._on && (event.key === "g" || event.key === "G" || event.key === "/") && !this._modalOpen()) {
      event.preventDefault()
      event.stopPropagation()
      this._select("scripture")
      const input = this.element.querySelector(".cx-find-input")
      input?.focus()
      input?.select()
    }
  }

  _modalOpen() {
    return !!this.element.querySelector(".ps-preach-jump:not([hidden]), .cx-tour:not([hidden])")
  }

  // ---- Go live in the toolbar ---------------------------------------------------------------

  _previewChanged(detail) {
    this._hasPreview = !!detail?.label
    this._syncGoLive()
  }

  _syncGoLive() {
    const btn = this.element.querySelector("[data-cx-golive]")
    if (!btn) return
    const card = this.element.querySelector(".ps-console-preview")
    btn.disabled = !this._hasPreview || card?.dataset.state === "error"
    btn.classList.toggle("is-ready", !btn.disabled && card?.dataset.state !== "live")
  }

  tour(event) {
    event?.preventDefault?.()
    window.dispatchEvent(new CustomEvent("console:tour", { detail: { force: true } }))
  }

  // ---- prefs --------------------------------------------------------------------------------

  _viewKey() {
    return `ps-preach-view:${document.body?.dataset.offlineOwner || "guest"}`
  }

  _loadView() {
    try { return localStorage.getItem(this._viewKey()) === "focus" ? "focus" : "console" } catch { return "console" }
  }

  _saveView() {
    try { localStorage.setItem(this._viewKey(), this._view) } catch { /* private mode */ }
  }
}

function isEditable(target) {
  if (!target || target === document.body) return false
  if (target.isContentEditable) return true
  const tag = target.tagName
  if (tag === "TEXTAREA" || tag === "SELECT") return true
  if (tag !== "INPUT") return false
  return ![ "button", "checkbox", "radio", "submit", "reset", "range", "color", "file" ].includes((target.type || "").toLowerCase())
}
