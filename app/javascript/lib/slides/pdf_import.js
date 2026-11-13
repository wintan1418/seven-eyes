// Turn a PDF (or a handful of pictures) into slide images on the device.
//
// PowerPoint, Keynote and Google Slides all "Save as PDF" / "Download as
// PDF", so a PDF covers every deck the pastor brings on a flash drive. pdf.js
// is vendored (public/vendor/pdfjs-<version>/, Apache-2.0) and loaded only
// when an import starts; the service worker keeps it, so importing works with
// no signal once it has been used (or warmed) online.
//
//   renderPdf(file, { onProgress })    → { pages: [{ blob, thumb, w, h }], title }
//   renderImages(files, { onProgress }) → same, one page per picture
//   warmPdfjs()                         fetch pdf.js into the cache, quietly
export const PDFJS_VERSION = "4.10.38"
const BASE = `/vendor/pdfjs-${PDFJS_VERSION}`
export const PDFJS_URL = `${BASE}/pdf.min.js`
export const PDFJS_WORKER_URL = `${BASE}/pdf.worker.min.js`

export const MAX_PAGES = 300
export const MAX_FILE_BYTES = 80 * 1024 * 1024
const MAX_W = 1920
const MAX_H = 1080
const THUMB_W = 320
const QUALITY = 0.86

let loading = null

export function loadPdfjs() {
  if (loading) return loading
  const url = PDFJS_URL // a variable, so esbuild leaves the import to the browser
  loading = import(/* webpackIgnore: true */ url).then((lib) => {
    lib.GlobalWorkerOptions.workerSrc = PDFJS_WORKER_URL
    return lib
  }).catch((e) => { loading = null; throw e })
  return loading
}

export function warmPdfjs() {
  if (navigator.connection?.saveData) return
  ;[ PDFJS_URL, PDFJS_WORKER_URL ].forEach((u) => fetch(u, { credentials: "same-origin" }).catch(() => {}))
}

export async function renderPdf(file, { onProgress = () => {}, signal } = {}) {
  if (file.size > MAX_FILE_BYTES) throw new Error("That PDF is over 80 MB — save it smaller (File → Reduce file size) and try again")
  const pdfjs = await loadPdfjs()
  const data = new Uint8Array(await file.arrayBuffer())
  const doc = await pdfjs.getDocument({ data, isEvalSupported: false, disableFontFace: false }).promise
  const count = Math.min(doc.numPages, MAX_PAGES)
  const pages = []
  try {
    for (let n = 1; n <= count; n++) {
      if (signal?.aborted) throw new Error("Import cancelled")
      const page = await doc.getPage(n)
      const base = page.getViewport({ scale: 1 })
      const scale = Math.min(MAX_W / base.width, MAX_H / base.height)
      const viewport = page.getViewport({ scale })
      const canvas = document.createElement("canvas")
      canvas.width = Math.round(viewport.width)
      canvas.height = Math.round(viewport.height)
      const ctx = canvas.getContext("2d")
      ctx.fillStyle = "#fff"
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      await page.render({ canvasContext: ctx, viewport }).promise
      pages.push(await encode(canvas))
      page.cleanup()
      onProgress(n / count, n, count)
    }
  } finally {
    doc.destroy()
  }
  return { pages, title: titleOf(file.name), truncated: doc.numPages > MAX_PAGES }
}

export async function renderImages(files, { onProgress = () => {} } = {}) {
  const list = [ ...files ].filter((f) => /^image\//.test(f.type)).slice(0, MAX_PAGES)
  const pages = []
  for (let i = 0; i < list.length; i++) {
    const bitmap = await loadBitmap(list[i])
    const scale = Math.min(1, MAX_W / bitmap.width, MAX_H / bitmap.height)
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#000"
    ctx.fillRect(0, 0, canvas.width, canvas.height)
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close?.()
    pages.push(await encode(canvas))
    onProgress((i + 1) / list.length, i + 1, list.length)
  }
  return { pages, title: list.length === 1 ? titleOf(list[0].name) : `${list.length} pictures` }
}

// One picture for a seminar slide: { blob, thumb }.
export async function renderPicture(file) {
  const { pages } = await renderImages([ file ])
  return pages[0] || null
}

async function loadBitmap(file) {
  if (globalThis.createImageBitmap) {
    try { return await createImageBitmap(file) } catch { /* fall through */ }
  }
  const url = URL.createObjectURL(file)
  try {
    const img = new Image()
    img.src = url
    await img.decode()
    return img
  } finally {
    URL.revokeObjectURL(url)
  }
}

async function encode(canvas) {
  const blob = await toBlob(canvas, "image/jpeg", QUALITY)
  const t = document.createElement("canvas")
  const ratio = THUMB_W / canvas.width
  t.width = THUMB_W
  t.height = Math.max(1, Math.round(canvas.height * ratio))
  t.getContext("2d").drawImage(canvas, 0, 0, t.width, t.height)
  const thumb = await toBlob(t, "image/jpeg", 0.75)
  return { blob, thumb, w: canvas.width, h: canvas.height }
}

function toBlob(canvas, type, quality) {
  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("Couldn't draw the page"))), type, quality))
}

function titleOf(name) {
  return String(name || "Presentation").replace(/\.[a-z0-9]{2,5}$/i, "").replace(/[_]+/g, " ").trim() || "Presentation"
}
