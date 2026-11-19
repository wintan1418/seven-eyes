// yarn build [--watch] — the app's JavaScript (see package.json).
//
// application.js is code-split (--splitting): controllers listed lazily in
// controllers/index.js and the code only they use become chunks fetched on
// first use. Chunks are named "<name>-<hash>.digested.js": Propshaft serves
// files marked ".digested" as they are (the hash is already in the name), so
// the "/assets/…" imports esbuild writes stay valid in production, and each
// deploy's chunks get new names (immutable caching stays correct).
//
// The service worker is a classic script inlined into /service-worker
// (app/views/pwa/service-worker.js.erb), so it's built on its own, unsplit.
import * as esbuild from "esbuild"
import fs from "node:fs"
import path from "node:path"

const outdir = "app/assets/builds"
const watch = process.argv.includes("--watch")

// Chunks from an earlier build would otherwise be precompiled and kept around.
for (const file of fs.readdirSync(outdir)) {
  if (/\.digested\.js(\.map)?$/.test(file)) fs.rmSync(path.join(outdir, file))
}

const common = { bundle: true, sourcemap: true, minify: true, format: "esm", outdir, logLevel: "info" }
const builds = [
  { ...common, entryPoints: [ "app/javascript/application.js" ], splitting: true, publicPath: "/assets", chunkNames: "[name]-[hash].digested" },
  // Unminified: it's one small file, and readable in DevTools / tests.
  { ...common, minify: false, entryPoints: [ "app/javascript/service_worker.js" ] }
]

if (watch) {
  for (const options of builds) await (await esbuild.context(options)).watch()
} else {
  await Promise.all(builds.map((options) => esbuild.build(options)))
}
