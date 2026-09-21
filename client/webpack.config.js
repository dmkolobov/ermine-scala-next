// The browser bundle (WP-9).  Two entries, no loaders, nothing else.
//
// TSC-FIRST.  webpack's input is the `tsc` OUTPUT under `dist/src/`, never the
// TypeScript sources, so the closure that a closed network has to carry (WP-17)
// is `webpack` + `webpack-cli` and nothing else -- the design review's D5, and
// the orchestrator's decision for this build on its recommendation (the user has
// been told).  `npm run bundle` is therefore `npm run build && webpack`.
//
// TO SWITCH TO ts-loader, which is what §5's Bundle row originally said: add
// `ts-loader` to devDependencies, set ENTRY_ROOT to "./src" and ENTRY_EXT to
// ".ts", and uncomment the two blocks marked TS-LOADER below.  Nothing else in
// this file, in `package.json`'s `bundle` script or in the tests changes.
//
// devtool: NEVER an `eval` flavour.  `mode: 'development'` DEFAULTS to
// `devtool: 'eval'`, and a webview CSP without `'unsafe-eval'` blocks every one
// of those module wrappers silently (§5; and see Q19 -- the committed
// ermine-writers bundle is exactly such a build).  `client/test/bundle.test.ts`
// pins the static half of that: no `eval(` and no `new Function` in the output.
//
// No `devServer`: a webview cannot load from one under its CSP (§5).
// `bundle:watch` is `node scripts/bundle-watch.js`, which builds once and then
// runs `tsc --watch` and `webpack --watch` together, writing to disk.  A BARE
// `webpack --watch` would watch `dist/src/`, not the TypeScript sources, and
// would fail outright from a clean checkout -- see that script's header.
//
// MODE: `development` only, today.  Nothing here is minified, and whether the
// panel ever wants a `production` build (minified, no `.map`, or a hidden one)
// is NOT decided and is not WP-9's: the preview loads from the developer's own
// workspace over a file:// URI, so bytes on the wire buy nothing, and a
// minified bundle would make WP-10's error boxes harder to read.  Adding it
// later is a `--mode` argument and a second `output.path`; no decision here
// forecloses it.

const path = require("path");

const ENTRY_ROOT = "./dist/src";
const ENTRY_EXT = ".js";

module.exports = {
  mode: "development",
  target: "web",
  devtool: "source-map",

  entry: {
    // the client library the host page renders documents with
    "ermine-client": {
      import: `${ENTRY_ROOT}/index${ENTRY_EXT}`,
      library: { name: "ErmineClient", type: "window" },
    },
    // the host page's own script.  It exists as a SEPARATE entry because under
    // `script-src ${cspSource}` with no nonce the host page may carry no inline
    // <script> at all -- not even `const vscode = acquireVsCodeApi()` (D4).
    // WP-10 fills it in; today it is the presentation reducer only.
    "ermine-host": {
      import: `${ENTRY_ROOT}/host/index${ENTRY_EXT}`,
      library: { name: "ErmineHost", type: "window" },
    },
  },

  output: {
    path: path.resolve(__dirname, "dist", "browser"),
    filename: "[name].js",
    sourceMapFilename: "[file].map",
  },

  // TS-LOADER (1/2): the only rule this config would ever need.
  // module: {
  //   rules: [{ test: /\.ts$/, use: "ts-loader", exclude: /node_modules/ }],
  // },

  // TS-LOADER (2/2): .ts before .js, so an entry resolves to the source.
  // resolve: { extensions: [".ts", ".js"] },

  // `named` ids in development are module PATHS, not content hashes, which is
  // what makes two builds of the same tree byte-identical.
  optimization: { moduleIds: "named", chunkIds: "named", minimize: false },

  // the client ships no CSS and no assets, so there is nothing else to load; a
  // bundle this size needs no performance budget (D7)
  performance: { hints: false },
};
