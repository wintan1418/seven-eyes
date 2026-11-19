// How a queue picture fills the projector — EasyWorship's picture "scaling".
// Saved per picture in SetlistItem#data (SlideData.picture keeps the same
// shape on the server) and carried with the slide to the output window,
// Preview, the Live miniature and the Picture Bank thumbnails, so every one
// of them shows exactly what the big screen shows.
//
//   fit      the whole picture, black bars where its shape differs from the
//            screen's (the default: nothing on a flyer is ever cut off)
//   fill     covers the screen edge to edge; the edges that don't fit are cropped
//   stretch  pulled to the screen's shape
//   zoom     100–200 %, enlarged from the centre (the screen crops the rest)
export const PICTURE_FITS = [ "fit", "fill", "stretch" ]
export const FIT_LABELS = { fit: "Fit", fill: "Fill", stretch: "Stretch" }
export const FIT_HINTS = {
  fit: "Whole picture, black bars at the sides or top",
  fill: "Covers the screen edge to edge — the edges are cropped",
  stretch: "Pulled to the screen's shape"
}
export const ZOOM_MIN = 100
export const ZOOM_MAX = 200
export const ZOOM_STEP = 10

export function pictureDisplay(raw) {
  const fit = PICTURE_FITS.includes(raw?.fit) ? raw.fit : "fit"
  const n = Math.round(Number(raw?.zoom))
  const zoom = Number.isFinite(n) && n > 0 ? Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, n)) : ZOOM_MIN
  return { fit, zoom }
}

export function samePicture(a, b) {
  const x = pictureDisplay(a)
  const y = pictureDisplay(b)
  return x.fit === y.fit && x.zoom === y.zoom
}

// A short label for the operator: "Fit", "Fill · 150%".
export function pictureLabel(raw) {
  const { fit, zoom } = pictureDisplay(raw)
  return zoom === ZOOM_MIN ? FIT_LABELS[fit] : `${FIT_LABELS[fit]} · ${zoom}%`
}

// Mark a picture frame (the element holding the <img>) with its display; the
// CSS (picture_fit.css) does the rest, in any frame size.
export function applyPicture(frame, raw) {
  if (!frame) return
  const { fit, zoom } = pictureDisplay(raw)
  frame.dataset.fit = fit
  frame.style.setProperty("--pic-zoom", String(zoom / 100))
}
