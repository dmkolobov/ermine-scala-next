#!/usr/bin/env node
// `npm run bundle:watch` -- watch the TYPESCRIPT SOURCES and rebuild the browser
// bundle, writing to disk.  No dev server: a webview cannot load from one under
// its CSP (§5).
//
// WHY THIS EXISTS AT ALL.  Webpack's input is the `tsc` output (`dist/src/…js`),
// never the sources -- the TSC-FIRST decision in `webpack.config.js` -- so a bare
// `webpack --watch` watches the WRONG FILES: editing `src/host/index.ts` rebuilds
// nothing, and from a clean checkout it fails outright with
// `Module not found: Can't resolve './dist/src/index.js'` (both MEASURED by the
// WP-9 review).  A watch that silently ignores the files a developer is editing is
// worse than no watch, so `bundle:watch` runs this instead.
//
// What it does, in order:
//   1. one full `tsc` build, so webpack has an input to start from.  A type error
//      aborts here rather than leaving a half-watched tree;
//   2. `tsc --watch` and `webpack --watch` together, output interleaved;
//   3. Ctrl-C (or SIGTERM) stops both; if either dies on its own the other is
//      stopped too and this process exits with that code.
//
// No new dependency: both children are run as `node <their own cli entry>`, which
// also avoids the `.bin`/`.cmd` difference on Windows.

"use strict";

const { spawn, spawnSync } = require("child_process");
const path = require("path");

const CLIENT = path.resolve(__dirname, "..");
const TSC = require.resolve("typescript/bin/tsc");
const WEBPACK = require.resolve("webpack-cli/bin/cli.js");
const TSC_ARGS = ["-p", path.join(CLIENT, "tsconfig.json")];

function run(args) {
  return spawnSync(process.execPath, args, { cwd: CLIENT, stdio: "inherit" });
}

// 1. the one full build webpack's first pass needs
const first = run([TSC, ...TSC_ARGS]);
if (first.status !== 0) {
  console.error("bundle:watch: the initial `tsc` build failed; not starting the watchers");
  process.exit(first.status === null ? 1 : first.status);
}

// 2. both watchers.  --preserveWatchOutput keeps tsc from clearing the screen and
//    taking webpack's output with it.
const children = [
  spawn(process.execPath, [TSC, ...TSC_ARGS, "--watch", "--preserveWatchOutput"],
        { cwd: CLIENT, stdio: "inherit" }),
  spawn(process.execPath, [WEBPACK, "--watch"], { cwd: CLIENT, stdio: "inherit" }),
];

// 3. one exit for the pair, whichever way it comes
let stopping = false;
function stop(signal, code) {
  if (stopping) return;
  stopping = true;
  for (const c of children) {
    if (c.exitCode === null && c.signalCode === null) c.kill(signal || "SIGTERM");
  }
  process.exitCode = code === undefined ? 0 : code;
}

for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(sig, () => stop(sig, 0));
}
for (const c of children) {
  c.on("exit", (code, signal) => {
    // a watcher that ends on its own has failed: watchers do not finish
    if (!stopping) console.error(`bundle:watch: a watcher exited (code ${code}, signal ${signal}); stopping the other`);
    stop("SIGTERM", code === null ? 0 : code);
  });
  c.on("error", (e) => {
    console.error(`bundle:watch: could not start a watcher: ${e.message}`);
    stop("SIGTERM", 1);
  });
}
