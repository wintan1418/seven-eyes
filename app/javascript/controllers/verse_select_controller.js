import { Controller } from "@hotwired/stimulus"

// Tap a verse to select it (tap again to let go) — the YouVersion gesture.
// Selected verses get .is-selected; every change is announced as a window
// `verses:selected` event for the action bar. Stands down while presenting /
// preaching, while words are selected (the highlighter owns text selection),
// and for taps on links, buttons, highlights, memorize blanks and — in word
// study mode — Strong's words. Lives on .ps-workspace.
export default class extends Controller {
  connect() {
    this._onKey = (e) => { if (e.key === "Escape" && this.selected().length && !document.querySelector(".ui-sheet.is-open")) this.clear() }
    this._onFrame = () => this.announce()
    this._onClear = () => this.clear()
    document.addEventListener("keydown", this._onKey)
    this.element.addEventListener("turbo:frame-load", this._onFrame)
    window.addEventListener("verses:clear", this._onClear)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
    this.element.removeEventListener("turbo:frame-load", this._onFrame)
    window.removeEventListener("verses:clear", this._onClear)
  }

  click(event) {
    const root = this.element.closest(".ps-root")
    if (!root || root.matches(".is-presenting, .is-preaching, .is-output")) return
    const verse = event.target.closest(".ps-verse-body .ps-verse")
    if (!verse) return
    if (!window.getSelection()?.isCollapsed) return
    const t = event.target
    if (t.closest("a, button, input, textarea, .ps-vnum, [data-highlight-id], .ps-blank, .ps-mem-blank")) return
    if (root.classList.contains("is-interlinear") && t.closest(".ps-word")) return
    if (verse.querySelector(".ps-blank")) return // memorize mode owns the taps
    // One pane at a time: tapping another pane starts a new selection there.
    const pane = verse.closest(".ps-pane")
    this.selected().forEach(v => { if (v.closest(".ps-pane") !== pane) v.classList.remove("is-selected") })
    verse.classList.toggle("is-selected")
    this.announce()
  }

  clear() {
    this.selected().forEach(v => v.classList.remove("is-selected"))
    this.announce()
  }

  selected() {
    return Array.from(this.element.querySelectorAll(".ps-verse.is-selected"))
  }

  announce() {
    const verses = this.selected()
    const pane = verses[0]?.closest(".ps-pane")
    const meta = pane?.querySelector(".rd-pane-meta")
    const detail = {
      paneId: pane?.id?.replace("pane_", "") || null,
      translation: meta?.dataset.translationCode || null,
      label: this.label(verses),
      verses: verses.map(v => {
        const text = v.querySelector(".ps-verse-text")
        return {
          osis: v.dataset.osis,
          chapter: parseInt(v.dataset.chapter, 10),
          verse: parseInt(v.dataset.verseNum, 10),
          verseId: text?.dataset.verseId,
          length: (parseInt(text?.dataset.offsetBase || "0", 10)) + (text?.textContent.length || 0),
          text: text?.textContent.trim() || "",
          highlightIds: Array.from(v.querySelectorAll("[data-highlight-id]")).map(s => s.dataset.highlightId)
        }
      })
    }
    window.dispatchEvent(new CustomEvent("verses:selected", { detail }))
  }

  // "John 3:16–17", "John 3:16, 18", "John 3:16; 4:1"
  label(verses) {
    if (!verses.length) return ""
    const book = verses[0].closest(".ps-pane")?.querySelector(".rd-book")?.textContent?.trim() || verses[0].dataset.osis
    const byChapter = new Map()
    verses.forEach(v => {
      const ch = parseInt(v.dataset.chapter, 10)
      if (!byChapter.has(ch)) byChapter.set(ch, [])
      byChapter.get(ch).push(parseInt(v.dataset.verseNum, 10))
    })
    const parts = [...byChapter.entries()].sort((a, b) => a[0] - b[0]).map(([ch, nums]) => {
      nums.sort((a, b) => a - b)
      const runs = []
      nums.forEach(n => {
        const last = runs[runs.length - 1]
        if (last && n === last[1] + 1) last[1] = n
        else runs.push([n, n])
      })
      return `${ch}:${runs.map(([a, b]) => (a === b ? `${a}` : `${a}–${b}`)).join(", ")}`
    })
    return `${book} ${parts.join("; ")}`
  }
}
