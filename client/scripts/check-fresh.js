#!/usr/bin/env node
// The JVM-free checks on the committed src/generated/widgets.ts (WP-32 S2), run by
// the `generated` gate (commit tier) and the `client` gate (nightly) in
// scripts/gates.sh.  No JVM, no sbt: node and the client's own tsc.
//
//   node client/scripts/check-fresh.js [--file <widgets.ts>] [--repo <repo root>]
//
//   (a) sources:   every `// sha256 <hex> <path>` line bin/ermine-schema wrote
//                  (path under core/src/main/resources/modules) is recomputed over
//                  the repo's module file; AND every .e module the widget scan
//                  covers (Layout/Widgets.e and Layout/Widgets/**/*.e) must be in
//                  that list, so a NEW widget module makes the file stale too.
//   (b) generator: every `// generator sha256 <hex> <path>` line generate.sh wrote
//                  (the Scala that emits the file) is recomputed; the three files
//                  json/{Schema,SchemaMain,Zod}.scala must all be listed.
//   (b2) body:     the `// body sha256: <hex>` line generate.sh wrote is recomputed
//                  over everything below it, so a HAND EDIT of the generated text
//                  fails (the S2 review's M-1: `.strict()` -> `.passthrough()`).
//   (c) exactness: for every recursive declaration `export const X: z.ZodType<X> = E;`
//                  the declared type X must EQUAL zod's inference of E unrolled one
//                  step: assignable in BOTH directions (`[A] extends [B]` and back)
//                  AND identical to tsc (the `<T>() => T extends A` trick), since
//                  mutual assignability misses an extra optional key.  The
//                  annotation alone only proves zod-output assignable to X; a
//                  WIDENED X passes tsc (the S1 review's mutants).  Checked by
//                  writing a probe module and running the client's tsc on it.
//
// Prints ONE line, `generated: ...`; exit 0 fresh and exact, 1 stale or inexact
// (the line names the first offender and says "regenerate: client/scripts/generate.sh"),
// 3 when a precondition is missing (no client/node_modules/typescript for (c)).
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const cp = require("child_process");

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? path.resolve(args[i + 1]) : dflt;
};
const client = path.resolve(__dirname, "..");
const repo = opt("--repo", path.dirname(client));
const file = opt("--file", path.join(client, "src", "generated", "widgets.ts"));
const MODULES = path.join(repo, "core", "src", "main", "resources", "modules");
const GENERATOR = ["Schema.scala", "SchemaMain.scala", "Zod.scala"]
  .map((f) => "core/src/main/scala/com/clarifi/reporting/ermine/json/" + f);
const REGEN = "regenerate: client/scripts/generate.sh";

function done(rc, line) {
  console.log("generated: " + line);
  process.exit(rc);
}
const sha = (p) => crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");

if (!fs.existsSync(file)) done(1, `${path.relative(repo, file)} is missing -- ${REGEN}`);
const src = fs.readFileSync(file, "utf8");

// ------------------------------------------------------------------ (a) sources
const moduleLines = [...src.matchAll(/^\/\/ sha256 ([0-9a-f]{64}) (\S+)$/gm)];
if (moduleLines.length === 0) done(1, `no \`// sha256\` source lines in the header -- ${REGEN}`);
const listed = new Set();
for (const [, hex, rel] of moduleLines) {
  listed.add(rel);
  const p = path.join(MODULES, rel);
  if (!fs.existsSync(p)) done(1, `STALE: ${rel} was read by the generator and no longer exists -- ${REGEN}`);
  if (sha(p) !== hex) done(1, `STALE: ${rel} changed since generation (sha256 differs) -- ${REGEN}`);
}
const scanned = ["Layout/Widgets.e"];
(function walk(dir, rel) {
  if (!fs.existsSync(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    if (e.isDirectory()) walk(path.join(dir, e.name), rel + e.name + "/");
    else if (e.name.endsWith(".e")) scanned.push(rel + e.name);
  }
})(path.join(MODULES, "Layout", "Widgets"), "Layout/Widgets/");
for (const rel of scanned) {
  if (!listed.has(rel)) done(1, `STALE: ${rel} is a widget module the generator has not read -- ${REGEN}`);
}

// ---------------------------------------------------------------- (b) generator
const genLines = [...src.matchAll(/^\/\/ generator sha256 ([0-9a-f]{64}) (\S+)$/gm)];
const genListed = new Set(genLines.map((m) => m[2]));
for (const g of GENERATOR) {
  if (!genListed.has(g)) done(1, `no \`// generator sha256\` line for ${g} -- ${REGEN}`);
}
for (const [, hex, rel] of genLines) {
  const p = path.join(repo, rel);
  if (!fs.existsSync(p)) done(1, `STALE: generator source ${rel} no longer exists -- ${REGEN}`);
  if (sha(p) !== hex) done(1, `STALE: generator source ${rel} changed since generation -- ${REGEN}`);
}

// ------------------------------------------------------------- (b2) body hash
// generate.sh hashes everything below its `// body sha256:` line; a hand edit of
// the generated text (say a `.strict()` made `.passthrough()`, which neither the
// input hashes nor the probe of the recursive declarations can see) fails here.
const bodyLine = src.match(/^\/\/ body sha256: ([0-9a-f]{64})\n/m);
if (!bodyLine || bodyLine.index === undefined) done(1, `no \`// body sha256:\` line in the header -- ${REGEN}`);
const body = src.slice(bodyLine.index + bodyLine[0].length);
if (crypto.createHash("sha256").update(body, "utf8").digest("hex") !== bodyLine[1]) {
  done(1, `EDITED: the generated body does not match its \`// body sha256\` (hand edits are not allowed) -- ${REGEN}`);
}

// ---------------------------------------------------------------- (c) exactness
const annotated = [...src.matchAll(/^export const (\w+): z\.ZodType<(\w+)> = /gm)];
const exact = [...src.matchAll(/^export const (\w+): z\.ZodType<\1> = (.*);$/gm)];
if (annotated.length !== exact.length) {
  const odd = annotated.find((m) => m[1] !== m[2]) || annotated[0];
  done(1, `the annotated const ${odd ? odd[1] : "?"} is not in the probe's form \`export const X: z.ZodType<X> = E;\` -- ${REGEN}`);
}
if (exact.length === 0) done(1, "no recursive declaration found: the probe would be vacuous");
const tscJs = path.join(client, "node_modules", "typescript", "bin", "tsc");
if (!fs.existsSync(tscJs) || !fs.existsSync(path.join(client, "node_modules", "zod"))) {
  done(3, "no client/node_modules (typescript, zod): run npm install in client/");
}
const names = new Set(exact.map((m) => m[1]));
const probe = [
  'import { z } from "zod";',
  "", // the import of the generated module, filled in once the probe directory exists
  // BOTH directions of assignability (the S1 review's eq-probe) AND tsc's identity
  // relation: mutual assignability alone passes an extra OPTIONAL key (`{a} ` and
  // `{a; x?: T}` are assignable both ways -- measured, S2's mutant M4c)
  "type Mutual<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;",
  "type Identical<A, B> = (<T>() => T extends A ? 1 : 2) extends (<T>() => T extends B ? 1 : 2) ? true : false;",
  "type Eq<A, B> = Mutual<A, B> extends true ? Identical<A, B> : false;",
];
for (const [, n, e] of exact) {
  // qualify every reference to a const of the generated module: G.<name>
  const e2 = e.replace(/\b(Layout_\w+)\b/g, "G.$1");
  probe.push(`const raw_${n} = ${e2};`);
  probe.push(`export const eq_${n}: Eq<z.infer<typeof raw_${n}>, G.${n}> = true;`);
}
const dir = fs.mkdtempSync(path.join(client, ".probe-"));
let failure = null;   // decided inside, reported after the probe directory is gone
try {
  const rel = path.relative(dir, file).replace(/\\/g, "/").replace(/\.ts$/, "");
  probe[1] = `import * as G from ${JSON.stringify(rel.startsWith(".") ? rel : "./" + rel)};`;
  fs.writeFileSync(path.join(dir, "eq.ts"), probe.join("\n") + "\n");
  fs.writeFileSync(path.join(dir, "tsconfig.json"), JSON.stringify({
    extends: path.join(client, "tsconfig.json"),
    // rootDir at the filesystem root: --file may name a copy outside the repo
    // and "zod" resolves to the client's copy wherever that file sits
    compilerOptions: {
      noEmit: true, rootDir: path.parse(dir).root,
      baseUrl: client, paths: { zod: ["node_modules/zod"] },
    },
    include: ["eq.ts"],
  }));
  const r = cp.spawnSync(process.execPath, [tscJs, "-p", dir], { encoding: "utf8" });
  if (r.status !== 0) {
    const out = (r.stdout + r.stderr).split("\n").filter((l) => /error TS/.test(l));
    const first = out[0] || (r.stdout + r.stderr).trim().split("\n")[0] || `tsc exited ${r.status}`;
    // eq.ts(<line>,..): the probe line names the declaration
    const line = Number((first.match(/eq\.ts\((\d+),/) || [])[1]);
    const which = line ? ((probe[line - 1] || "").match(/(?:eq|raw)_(\w+)/) || [])[1] : undefined;
    failure = `INEXACT: ${which ? `the declared ${which} is not exactly the type zod infers` : "the exactness probe failed"} ` +
      `(${out.length} tsc error(s); first: ${first.replace(/^.*?error /, "error ")}) -- ${REGEN}`;
  }
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
if (failure) done(1, failure);

done(0, `fresh and exact: ${moduleLines.length} module hashes (${scanned.length} widget modules covered), ` +
  `${genLines.length} generator hashes, body hash, ${names.size} recursive declarations identical to zod's inference`);
