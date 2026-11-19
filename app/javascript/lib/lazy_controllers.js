// Stimulus controllers fetched on first use. `loaders` maps an identifier to
// a function returning import("./x_controller") — esbuild (--splitting) puts
// each in its own chunk. When an element naming one appears (on this page,
// after a Turbo visit, in a frame or a sheet added later), its chunk is
// imported and registered; Stimulus then connects every element using it.
// A chunk that fails to load (offline and never saved) is retried the next
// time the identifier shows up.
export function registerLazyControllers(application, loaders) {
  const pending = new Map(Object.entries(loaders))
  const loading = new Set()
  const attribute = application.schema.controllerAttribute
  const selector = `[${attribute}]`

  const load = (identifier) => {
    const loader = pending.get(identifier)
    if (!loader || loading.has(identifier)) return
    loading.add(identifier)
    loader().then((module) => {
      pending.delete(identifier)
      application.register(identifier, module.default)
    }).catch((error) => {
      console.error(`Couldn't load the ${identifier} controller`, error)
    }).finally(() => loading.delete(identifier))
  }

  const loadFor = (element) => {
    for (const identifier of (element.getAttribute(attribute) || "").split(/\s+/)) {
      if (pending.has(identifier)) load(identifier)
    }
  }

  const scan = (root) => {
    if (!pending.size || root.nodeType !== Node.ELEMENT_NODE) return
    if (root.matches(selector)) loadFor(root)
    root.querySelectorAll(selector).forEach(loadFor)
  }

  new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === "attributes") scan(mutation.target)
      else mutation.addedNodes.forEach(scan)
    }
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: [ attribute ] })

  scan(document.documentElement)

  // Tests and the console can ask for one up front.
  application.lazyControllers = { load, pending }
}
