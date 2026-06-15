import { Controller } from "@hotwired/stimulus"

// The preach queue ("setlist") drawer. Lives on .ps-root.
//
// Opening/closing toggles .is-open on the host; the list itself is a Turbo
// Frame, so add/move/delete re-render server-side. Clicking an item's label
// hands it to the presentation controller via a window event:
//   setlist:present {kind: "scripture", reference} — chase the reference
//   setlist:present {kind: "slide", title, body}   — project a song/thought
export default class extends Controller {
  static targets = ["host", "form", "libraryList", "title", "body"]
  static values = { libraryUrl: String }

  open(event) {
    event?.preventDefault?.()
    if (this.hasHostTarget) this.hostTarget.classList.add("is-open")
  }

  close(event) {
    event?.preventDefault?.()
    if (this.hasHostTarget) this.hostTarget.classList.remove("is-open")
  }

  toggle(event) {
    event?.preventDefault?.()
    if (!this.hasHostTarget) return
    this.hostTarget.classList.toggle("is-open")
  }

  // Radio change on the add form: show only the fields the kind needs.
  kindChanged(event) {
    const form = event.target.closest(".ps-setlist-form")
    if (!form) return
    form.classList.remove("kind-scripture", "kind-song", "kind-thought", "kind-picture")
    form.classList.add(`kind-${event.target.value}`)
    form.querySelectorAll(".kinds label").forEach(l => {
      l.classList.toggle("is-on", l.contains(event.target))
    })
  }

  // ----- song library (reuse a past song / the public-domain hymnal) -----

  toggleLibrary(event) {
    event?.preventDefault?.()
    if (!this.hasLibraryListTarget) return
    if (!this.libraryListTarget.hidden) { this.libraryListTarget.hidden = true; return }
    this.libraryListTarget.hidden = false
    this._loadLibrary()
  }

  // Fetch once, then re-render from cache — the Turbo Frame re-render after every
  // add wipes the list DOM but the controller (and its cache) survive.
  async _loadLibrary() {
    if (this._songs) { this._renderLibrary(this._songs); return }
    if (!this.hasLibraryUrlValue) return
    this.libraryListTarget.innerHTML = `<div class="lib-empty">Gathering songs&hellip;</div>`
    let data
    try {
      const res = await fetch(this.libraryUrlValue, { headers: { Accept: "application/json" } })
      data = await res.json()
    } catch { data = null }
    this._songs = data?.songs || []
    this._renderLibrary(this._songs)
  }

  _renderLibrary(songs) {
    if (!songs.length) {
      this.libraryListTarget.innerHTML =
        `<div class="lib-empty">No saved songs yet &mdash; the ones you queue will show up here next time.</div>`
      return
    }
    this.libraryListTarget.innerHTML = ""
    songs.forEach(s => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = `lib-song${s.source === "hymnal" ? " is-hymn" : ""}`
      btn.dataset.action = "setlist#pickSong"
      btn.dataset.title = s.title
      btn.dataset.body = s.body
      const t = document.createElement("span")
      t.className = "t"
      t.textContent = s.title
      const tag = document.createElement("span")
      tag.className = "tag"
      tag.textContent = s.source === "hymnal" ? "hymnal" : "yours"
      btn.append(t, tag)
      this.libraryListTarget.appendChild(btn)
    })
  }

  pickSong(event) {
    event?.preventDefault?.()
    const d = event.currentTarget.dataset
    if (this.hasTitleTarget) this.titleTarget.value = d.title || ""
    if (this.hasBodyTarget) this.bodyTarget.value = d.body || ""
    if (this.hasLibraryListTarget) this.libraryListTarget.hidden = true
    this.bodyTarget?.focus?.()
  }

  present(event) {
    event?.preventDefault?.()
    const item = event.target.closest(".ps-setlist-item")
    if (!item) return
    const detail = {
      kind: item.dataset.kind,
      reference: item.dataset.reference || null,
      title: item.dataset.title || null,
      body: item.dataset.body || null,
      image: item.dataset.image || null
    }
    this.element.querySelectorAll(".ps-setlist-item.is-live").forEach(i => i.classList.remove("is-live"))
    item.classList.add("is-live")
    window.dispatchEvent(new CustomEvent("setlist:present", { detail }))
    // Mid-service the drawer covers the console — get out of the way.
    if (this.element.classList.contains("is-preaching")) this.close()
  }
}
