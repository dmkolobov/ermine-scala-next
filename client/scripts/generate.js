#!/usr/bin/env node
// Regenerate client/src/generated/widgets.ts from the Ermine declarations (WP-33:
// the node port of generate.sh, so the client runs on Windows with no shell).  ONE
// JVM (about five seconds) runs SchemaMain --widgets, which scans Layout.Widgets and
// every module under Layout/Widgets/ for `WidgetName T` terms and writes every props
// schema, WidgetRegistry, WidgetName, WIDGET_PROP_SCHEMAS and UNSUPPORTED_WIDGETS;
// Layout.Doc's Node and Tab ride along for the document parser.  Nothing in the
// output is edited by hand.
//
//   node client/scripts/generate.js [<output file>]      (npm run generate)
//
// Needs a JVM: JAVA_HOME/bin/java when JAVA_HOME is set, else `java` on PATH
// (`java.exe` on Windows).  It does NOT go through bin/ermine-schema (bash): it does
// what that launcher does itself --
//   * the classpath cache target/ermine-classpath, rebuilt when missing, empty or
//     older than build.sbt by `sbt -batch "export core/fullClasspath"` (stderr
//     dropped; stdout minus lines starting `[` and blank lines, the LAST line kept).
//     sbt is needed only for that first build.  On Windows sbt is `sbt.bat` or
//     `sbt.cmd` found on PATH (sbt.bat first: the official installer's launcher),
//     run through cmd.exe because node refuses to spawn a .bat/.cmd without a shell;
//   * `-Dermine.typeCheck=true`, then ERMINE_JAVA_OPTS split on spaces and tabs,
//     first line only, no quote handling -- what bash's `read -r -a` does, so a
//     flag containing a space cannot be passed on either;
//   * `java <opts> -cp <cache> com.clarifi.reporting.ermine.json.SchemaMain
//     --widgets Layout.Widgets Layout.Doc:Node=DocNode Layout.Doc:Tab=DocTab`
//     from the repo root.
//
// The file is BYTE-IDENTICAL to what generate.sh wrote (WP-33 proved it with cmp),
// including its first line, which still names generate.sh (now a shim onto this
// script): the sha256 of the generator's own Scala (`// generator sha256 <hex>
// <path from the repo root>`), which scripts/check-fresh.js compares, so a generator
// change makes the committed file stale even though no .e file moved; then
// `// body sha256: <hex>`, the hash of everything below it, so a hand edit of the
// generated text is caught too.  Below them is SchemaMain's own header: the exact
// command and the sha256 of every .e file the run read.  Line endings are "\n"
// everywhere, on Windows too: the body is SchemaMain's stdout bytes untouched (plus
// a final "\n" when it lacks one), the header is joined with "\n", never os.EOL.
// The write is atomic (a temp file next to the output, then rename).
// scripts/check-generated.js regenerates and compares (JVM).
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const cp = require("child_process");

const NL = "\n";
const WRITTEN = "// Written by client/scripts/generate.sh -- do not edit; run it again instead.";
// The generator's own sources: a change to any of these can change the output.
const GENERATOR = ["Schema.scala", "SchemaMain.scala", "Zod.scala"]
  .map((f) => "core/src/main/scala/com/clarifi/reporting/ermine/json/" + f);
const MAIN_CLASS = "com.clarifi.reporting.ermine.json.SchemaMain";
const SCHEMA_ARGS = ["--widgets", "Layout.Widgets", "Layout.Doc:Node=DocNode", "Layout.Doc:Tab=DocTab"];
const SBT_TASK = "export core/fullClasspath";
const WIDGET_LINE = /^  [A-Za-z]*: [A-Za-z]*Props;$/;

const sha256 = (buf) => crypto.createHash("sha256").update(buf).digest("hex");

class GenError extends Error {
  constructor(msg, rc) { super(msg); this.rc = rc === undefined ? 1 : rc; }
}

// ------------------------------------------------------------- the launcher's half

// bash: `read -r -a extra <<< "$ERMINE_JAVA_OPTS"` -- the first line, split on IFS
// whitespace, backslashes and quotes literal.
function splitJavaOpts(s) {
  if (!s) return [];
  return s.split("\n")[0].split(/[ \t]+/).filter((w) => w !== "");
}

function javaOpts(env) {
  return ["-Dermine.typeCheck=true", ...splitJavaOpts(env.ERMINE_JAVA_OPTS)];
}

// bash: `grep -v '^\[' | grep -v '^$' | tail -1 | tr -d '\n'`.  One difference: a
// trailing "\r" is dropped from every line first (sbt.bat's output on Windows).
function filterSbtExport(stdout) {
  const lines = String(stdout).split("\n").map((l) => l.replace(/\r$/, ""))
    .filter((l) => !l.startsWith("[") && l !== "");
  return lines.length ? lines[lines.length - 1] : "";
}

// The first of `names` in any directory of env.PATH (Windows: env.Path too), else null.
function onPath(names, env, platform) {
  const delim = platform === "win32" ? ";" : ":";
  const p = env.PATH !== undefined ? env.PATH : env.Path || "";
  for (const name of names) {
    for (const dir of p.split(delim)) {
      if (!dir) continue;
      const f = path.join(dir.replace(/^"(.*)"$/, "$1"), name);
      try { if (fs.statSync(f).isFile()) return f; } catch (_) { /* not here */ }
    }
  }
  return null;
}

function javaCommand(platform, env) {
  const exe = platform === "win32" ? "java.exe" : "java";
  const home = env.JAVA_HOME;
  if (home) return (platform === "win32" ? path.win32 : path.posix).join(home, "bin", exe);
  return onPath([exe], env, platform) || exe;
}

// {file, args, shell, label}: how to run `sbt -batch "export core/fullClasspath"`.
function sbtCommand(platform, env) {
  if (platform !== "win32") return { file: "sbt", args: ["-batch", SBT_TASK], shell: false, label: "sbt" };
  const found = onPath(["sbt.bat", "sbt.cmd"], env, platform);
  const file = found || "sbt.bat";
  // shell: node >= 18.20.2 refuses to spawn a .bat/.cmd directly (EINVAL); with a
  // shell the command line is concatenated, so the quoting is done here
  return { file: `"${file}"`, args: ["-batch", `"${SBT_TASK}"`], shell: true, label: found ? path.basename(found) : "sbt.bat" };
}

// The classpath, from the cache or (when missing, empty or older than build.sbt)
// from sbt.  `run` is injectable for tests.
function ensureClasspath(repo, opts) {
  const o = opts || {};
  const platform = o.platform || process.platform;
  const env = o.env || process.env;
  const cache = path.join(repo, "target", "ermine-classpath");
  const build = path.join(repo, "build.sbt");
  let stale = true;
  try {
    const c = fs.statSync(cache);
    stale = c.size === 0 || (fs.existsSync(build) && fs.statSync(build).mtimeMs > c.mtimeMs);
  } catch (_) { stale = true; }
  if (stale) {
    const cmd = sbtCommand(platform, env);
    process.stderr.write(`generate: building the classpath cache with ${cmd.label} (first run or build.sbt changed)\n`);
    const r = (o.run || cp.spawnSync)(cmd.file, cmd.args, {
      cwd: repo, shell: cmd.shell, stdio: ["ignore", "pipe", "ignore"], maxBuffer: 1 << 28,
    });
    if (r.error) throw new GenError(`generate: cannot run ${cmd.label}: ${r.error.message}`);
    if (r.status !== 0) throw new GenError(`generate: ${cmd.label} exited ${r.status} building the classpath`, r.status || 1);
    const cpLine = filterSbtExport(r.stdout);
    if (!cpLine) throw new GenError(`generate: ${cmd.label} printed no classpath`);
    fs.mkdirSync(path.dirname(cache), { recursive: true });
    fs.writeFileSync(cache, cpLine);
  }
  return fs.readFileSync(cache, "utf8").replace(/[\r\n]+$/, "");
}

// SchemaMain's stdout (a Buffer), from the repo root; its stderr passes through.
function runSchemaMain(repo, opts) {
  const o = opts || {};
  const platform = o.platform || process.platform;
  const env = o.env || process.env;
  const classpath = ensureClasspath(repo, o);
  const java = javaCommand(platform, env);
  const r = cp.spawnSync(java, [...javaOpts(env), "-cp", classpath, MAIN_CLASS, ...SCHEMA_ARGS], {
    cwd: repo, stdio: ["ignore", "pipe", "inherit"], maxBuffer: 1 << 30,
  });
  if (r.error) throw new GenError(`generate: cannot run ${java}: ${r.error.message} (set JAVA_HOME or put java on PATH)`);
  if (r.status !== 0) throw new GenError(`generate: SchemaMain exited ${r.status}`, r.status || 1);
  return r.stdout;
}

// ------------------------------------------------------------------- the file

// generate.sh: `[ -n "$(tail -c 1 "$body")" ] && printf '\n' >> "$body"`
function terminate(body) {
  return body.length > 0 && body[body.length - 1] !== 0x0a ? Buffer.concat([body, Buffer.from(NL)]) : body;
}

// The whole file from the generator hashes ([{hex, path}]) and the body (Buffer).
function render(generators, body) {
  const b = terminate(Buffer.from(body));
  const header = [WRITTEN, ...generators.map((g) => `// generator sha256 ${g.hex} ${g.path}`),
    `// body sha256: ${sha256(b)}`].join(NL) + NL;
  return Buffer.concat([Buffer.from(header, "utf8"), b]);
}

function generatorHashes(repo) {
  return GENERATOR.map((rel) => ({ hex: sha256(fs.readFileSync(path.join(repo, ...rel.split("/")))), path: rel }));
}

// The inverse of render: {written, generators, bodyHex, body}, or null.
function parse(buf) {
  const b = Buffer.from(buf);
  let at = 0;
  const line = () => {
    const i = b.indexOf(0x0a, at);
    if (i < 0) return null;
    const s = b.subarray(at, i).toString("utf8");
    at = i + 1;
    return s;
  };
  const written = line();
  if (written === null) return null;
  const generators = [];
  for (;;) {
    const s = line();
    if (s === null) return null;
    const g = s.match(/^\/\/ generator sha256 ([0-9a-f]{64}) (\S+)$/);
    if (g) { generators.push({ hex: g[1], path: g[2] }); continue; }
    const h = s.match(/^\/\/ body sha256: ([0-9a-f]{64})$/);
    if (!h) return null;
    return { written, generators, bodyHex: h[1], body: b.subarray(at) };
  }
}

function countWidgetNames(buf) {
  return Buffer.from(buf).toString("utf8").split("\n").filter((l) => WIDGET_LINE.test(l)).length;
}

function writeAtomic(out, buf) {
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${path.basename(out)}.${process.pid}.tmp`);
  try {
    fs.writeFileSync(tmp, buf);
    fs.renameSync(tmp, out);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw e;
  }
}

// Returns the final line.  opts.schema (a function repo -> Buffer) replaces the JVM.
function generate(repo, out, opts) {
  const o = opts || {};
  const body = (o.schema || ((r) => runSchemaMain(r, o)))(repo);
  const file = render(generatorHashes(repo), body);
  writeAtomic(path.resolve(out), file);
  return `generated ${out} (${countWidgetNames(file)} widget names)`;
}

module.exports = {
  WRITTEN, GENERATOR, MAIN_CLASS, SCHEMA_ARGS, SBT_TASK, GenError,
  splitJavaOpts, javaOpts, filterSbtExport, onPath, javaCommand, sbtCommand,
  ensureClasspath, runSchemaMain, terminate, render, generatorHashes, parse,
  countWidgetNames, writeAtomic, generate,
};

if (require.main === module) {
  const client = path.resolve(__dirname, "..");
  const repo = path.dirname(client);
  const out = process.argv[2] || path.join(client, "src", "generated", "widgets.ts");
  try {
    console.log(generate(repo, out));
  } catch (e) {
    if (!(e instanceof GenError)) throw e;
    process.stderr.write(e.message + "\n");
    process.exit(e.rc);
  }
}
