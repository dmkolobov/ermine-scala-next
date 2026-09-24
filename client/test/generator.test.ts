// The node generator (scripts/generate.js, WP-33: the port of generate.sh so the
// client runs on Windows with no shell).  Everything but (gen-jvm-identity) is
// JVM-free and sbt-free: SchemaMain's output and sbt's are stubbed.
//
//   (gen-roundtrip)       parse(committed widgets.ts) re-rendered is the same bytes
//   (gen-header-order)    the header lines, in generate.sh's order
//   (gen-body-hash)       the body hash is over the body bytes, after the final "\n"
//   (gen-generator-hash)  the generator hashes are over the Scala files' raw bytes
//   (gen-java-opts)       ERMINE_JAVA_OPTS splits as bash's `read -r -a` does
//   (gen-sbt-filter)      `sbt export` stdout -> the classpath line
//   (gen-classpath-cache) the cache is rebuilt exactly when missing, empty or stale
//   (gen-win32)           a stubbed win32 picks java.exe and sbt.bat/sbt.cmd
//   (gen-lf)              no CR is ever added, even with os.EOL = "\r\n"
//   (gen-atomic)          the write leaves no temp file behind
//   (gen-final-line)      "generated <out> (N widget names)"
//   (gen-jvm-identity)    a real run reproduces the committed file (skips without a JVM)
//   (gen-check-diff)      check-generated.js's first-difference report
//
// ERMINE_GENERATE_JS names another copy of generate.js (the reverse mutants).

import { test } from "node:test";
import assert from "node:assert/strict";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const client = path.resolve(__dirname, "..", "..");
const repo = path.dirname(client);
const committed = path.join(client, "src", "generated", "widgets.ts");
const modPath = process.env.ERMINE_GENERATE_JS || path.join(client, "scripts", "generate.js");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const load = (): any => require(modPath);
const gen = load();

const sha = (b: Buffer | string): string => crypto.createHash("sha256").update(b).digest("hex");
const hexA = "a".repeat(64), hexB = "b".repeat(64), hexC = "c".repeat(64);
const fakeGens = [
  { hex: hexA, path: "core/src/main/scala/com/clarifi/reporting/ermine/json/Schema.scala" },
  { hex: hexB, path: "core/src/main/scala/com/clarifi/reporting/ermine/json/SchemaMain.scala" },
  { hex: hexC, path: "core/src/main/scala/com/clarifi/reporting/ermine/json/Zod.scala" },
];
const tmpdir = (): string => fs.mkdtempSync(path.join(os.tmpdir(), "gen-test-"));

// a repo with the three generator files (bytes chosen to differ from their text)
function fakeRepo(): string {
  const r = tmpdir();
  for (const rel of gen.GENERATOR as string[]) {
    const p = path.join(r, ...rel.split("/"));
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, Buffer.concat([Buffer.from(`// ${rel}\r\n`), Buffer.from([0xff, 0xfe, 0x00, 0x0a])]));
  }
  return r;
}

test("(gen-roundtrip) the committed widgets.ts parses and re-renders to the same bytes", () => {
  const bytes = fs.readFileSync(committed);
  const p = gen.parse(bytes);
  assert.ok(p, "the committed file has generate.sh's header");
  assert.equal(p.written, gen.WRITTEN);
  assert.deepEqual(p.generators.map((g: { path: string }) => g.path), gen.GENERATOR);
  assert.equal(p.bodyHex, sha(p.body), "the body hash is the sha256 of the bytes below it");
  assert.ok(Buffer.compare(gen.render(p.generators, p.body), bytes) === 0, "render(parse(f)) === f");
});

test("(gen-header-order) the header is Written, three generator lines, body sha256, in that order", () => {
  const out: string = gen.render(fakeGens, Buffer.from("BODY\n")).toString("utf8");
  assert.deepEqual(out.split("\n"), [
    "// Written by client/scripts/generate.sh -- do not edit; run it again instead.",
    `// generator sha256 ${hexA} ${fakeGens[0]!.path}`,
    `// generator sha256 ${hexB} ${fakeGens[1]!.path}`,
    `// generator sha256 ${hexC} ${fakeGens[2]!.path}`,
    `// body sha256: ${sha("BODY\n")}`,
    "BODY",
    "",
  ]);
  const p = gen.parse(Buffer.from(out));
  assert.deepEqual(p.generators, fakeGens);
});

test("(gen-body-hash) the body hash is over the body bytes after the final newline is added", () => {
  const cases: Array<[Buffer, Buffer]> = [
    [Buffer.from("abc"), Buffer.from("abc\n")],             // generate.sh appends "\n"
    [Buffer.from("abc\n"), Buffer.from("abc\n")],           // ... only when missing
    [Buffer.from("x\n\n"), Buffer.from("x\n\n")],
    [Buffer.from(""), Buffer.from("")],                     // `tail -c 1` of nothing: nothing
    [Buffer.from([0xc3, 0xa9, 0x61]), Buffer.from([0xc3, 0xa9, 0x61, 0x0a])], // raw bytes, not text
  ];
  for (const [body, expected] of cases) {
    const p = gen.parse(gen.render(fakeGens, body));
    assert.ok(Buffer.compare(p.body, expected) === 0, `body ${JSON.stringify(body.toString())}`);
    assert.equal(p.bodyHex, sha(expected), `hash of ${JSON.stringify(body.toString())}`);
  }
});

test("(gen-generator-hash) each generator line is the sha256 of that Scala file's raw bytes", () => {
  const r = fakeRepo();
  try {
    const hs = gen.generatorHashes(r);
    assert.deepEqual(hs.map((h: { path: string }) => h.path), gen.GENERATOR);
    for (const h of hs) assert.equal(h.hex, sha(fs.readFileSync(path.join(r, ...h.path.split("/")))), h.path);
  } finally { fs.rmSync(r, { recursive: true, force: true }); }
});

test("(gen-java-opts) ERMINE_JAVA_OPTS: whitespace split, first line, no quote handling (bash read -r -a)", () => {
  assert.deepEqual(gen.splitJavaOpts(undefined), []);
  assert.deepEqual(gen.splitJavaOpts(""), []);
  assert.deepEqual(gen.splitJavaOpts("   "), []);
  assert.deepEqual(gen.splitJavaOpts("  -Xmx1g\t-Da=1  "), ["-Xmx1g", "-Da=1"]);
  assert.deepEqual(gen.splitJavaOpts("-Da='b c'"), ["-Da='b", "c'"]);
  assert.deepEqual(gen.splitJavaOpts("-Dp=C:\\x\\y"), ["-Dp=C:\\x\\y"]);
  assert.deepEqual(gen.splitJavaOpts("-A -B\n-C"), ["-A", "-B"]);
  assert.deepEqual(gen.javaOpts({ ERMINE_JAVA_OPTS: "-Xss4m" }), ["-Dermine.typeCheck=true", "-Xss4m"]);
  assert.deepEqual(gen.javaOpts({}), ["-Dermine.typeCheck=true"]);
});

// The shape of `sbt -batch 'export core/fullClasspath'` stdout under sbt 1.10.7
// (stderr is dropped).  RECONSTRUCTED, not captured: running sbt was out of the
// WP-33 budget; the classpath line is the real target/ermine-classpath shape.
const CP = "/w/core/target/scala-3.3.8/classes:/w/parsers/target/scala-3.3.8/classes:/c/scala3-library_3-3.3.8.jar";
const SBT_SAMPLE = [
  "[info] welcome to sbt 1.10.7 (Eclipse Adoptium Java 21.0.12)",
  "[info] loading settings for project ermine-scala-build from plugins.sbt ...",
  "[info] loading project definition from /w/project",
  "",
  "[info] loading settings for project root from build.sbt ...",
  "[warn] a warning on stdout",
  "[info] set current project to ermine (in build file:/w/)",
  CP,
  "",
].join("\n");

test("(gen-sbt-filter) the classpath is the last non-blank stdout line not starting with [", () => {
  assert.equal(gen.filterSbtExport(SBT_SAMPLE), CP);
  assert.equal(gen.filterSbtExport(SBT_SAMPLE.replace(/\n/g, "\r\n")), CP, "sbt.bat's CRLF");
  assert.equal(gen.filterSbtExport(Buffer.from(SBT_SAMPLE)), CP, "a Buffer, as spawnSync returns");
  assert.equal(gen.filterSbtExport("[info] only info\n\n"), "");
  assert.equal(gen.filterSbtExport("first\nsecond\n[success] done\n"), "second");
});

function stubRun(calls: any[]) {
  return (file: string, args: string[], opts: any) => {
    calls.push({ file, args, opts });
    return { status: 0, stdout: Buffer.from(SBT_SAMPLE), error: undefined };
  };
}

test("(gen-classpath-cache) sbt runs exactly when the cache is missing, empty or older than build.sbt", () => {
  const r = tmpdir();
  try {
    const cache = path.join(r, "target", "ermine-classpath");
    fs.writeFileSync(path.join(r, "build.sbt"), "");
    const old = new Date(Date.now() - 60_000);
    fs.utimesSync(path.join(r, "build.sbt"), old, old);
    const calls: any[] = [];
    const o = { platform: "linux", env: { PATH: "" }, run: stubRun(calls) };
    assert.equal(gen.ensureClasspath(r, o), CP, "missing: built");
    assert.equal(calls.length, 1);
    assert.equal(calls[0].file, "sbt");
    assert.deepEqual(calls[0].args, ["-batch", "export core/fullClasspath"]);
    assert.equal(calls[0].opts.cwd, r);
    assert.equal(calls[0].opts.shell, false);
    assert.equal(fs.readFileSync(cache, "utf8"), CP, "cached with no newline (tr -d '\\n')");
    assert.equal(gen.ensureClasspath(r, o), CP, "fresh: read");
    assert.equal(calls.length, 1);
    fs.writeFileSync(cache, "");
    gen.ensureClasspath(r, o);
    assert.equal(calls.length, 2, "empty: rebuilt");
    const now = new Date(Date.now() + 60_000);
    fs.utimesSync(path.join(r, "build.sbt"), now, now);
    gen.ensureClasspath(r, o);
    assert.equal(calls.length, 3, "build.sbt newer: rebuilt");
    fs.rmSync(cache);
    const failing = () => ({ status: 1, stdout: Buffer.from(""), error: undefined });
    assert.throws(() => gen.ensureClasspath(r, { ...o, run: failing }), /exited 1/);
    assert.ok(!fs.existsSync(cache), "a failed sbt leaves no cache");
  } finally { fs.rmSync(r, { recursive: true, force: true }); }
});

test("(gen-win32) a stubbed win32 chooses java.exe and sbt.bat (sbt.cmd when that is all there is)", () => {
  assert.equal(gen.javaCommand("win32", { JAVA_HOME: "C:\\jdk-21" }), "C:\\jdk-21\\bin\\java.exe");
  assert.equal(gen.javaCommand("linux", { JAVA_HOME: "/opt/jdk" }), "/opt/jdk/bin/java");
  const d1 = tmpdir(), d2 = tmpdir(), r = tmpdir();
  try {
    assert.equal(gen.javaCommand("win32", { PATH: `${d1};${d2}` }), "java.exe", "none on PATH: the bare name");
    fs.writeFileSync(path.join(d2, "java.exe"), "");
    fs.writeFileSync(path.join(d2, "java"), "");
    assert.equal(gen.javaCommand("win32", { Path: `${d1};${d2}` }), path.join(d2, "java.exe"), "Windows' Path");
    assert.equal(gen.javaCommand("linux", { PATH: `${d1}:${d2}` }), path.join(d2, "java"));

    let s = gen.sbtCommand("win32", { PATH: `${d1};${d2}` });
    assert.equal(s.label, "sbt.bat", "none on PATH: sbt.bat");
    assert.equal(s.shell, true);
    fs.writeFileSync(path.join(d1, "sbt.cmd"), "");
    s = gen.sbtCommand("win32", { PATH: `${d1};${d2}` });
    assert.equal(s.label, "sbt.cmd");
    assert.equal(s.file, `"${path.join(d1, "sbt.cmd")}"`);
    fs.writeFileSync(path.join(d2, "sbt.bat"), "");
    s = gen.sbtCommand("win32", { PATH: `${d1};${d2}` });
    assert.equal(s.label, "sbt.bat", "sbt.bat wins over sbt.cmd");
    assert.deepEqual(s.args, ["-batch", '"export core/fullClasspath"'], "quoted: cmd.exe concatenates");
    const l = gen.sbtCommand("linux", { PATH: d2 });
    assert.deepEqual([l.file, l.args, l.shell], ["sbt", ["-batch", "export core/fullClasspath"], false]);

    fs.writeFileSync(path.join(r, "build.sbt"), "");
    const calls: any[] = [];
    gen.ensureClasspath(r, { platform: "win32", env: { PATH: `${d1};${d2}` }, run: stubRun(calls) });
    assert.equal(calls[0].file, `"${path.join(d2, "sbt.bat")}"`);
    assert.equal(calls[0].opts.shell, true);
  } finally {
    for (const d of [d1, d2, r]) fs.rmSync(d, { recursive: true, force: true });
  }
});

test("(gen-lf) no CR is added: the header uses \\n even with os.EOL = \\r\\n; the body is untouched", () => {
  const realOs: any = require("os");   // the module object itself, not the TS namespace wrapper
  const eol = Object.getOwnPropertyDescriptor(realOs, "EOL")!;
  const r = fakeRepo();
  try {
    Object.defineProperty(realOs, "EOL", { ...eol, value: "\r\n" });
    assert.equal(realOs.EOL, "\r\n", "os.EOL stubbed");
    delete require.cache[require.resolve(modPath)];
    const fresh = load();
    const out = path.join(r, "out", "widgets.ts");
    const body = "a\r\nb\n  x: XProps;\r\n";
    fresh.generate(r, out, { schema: () => Buffer.from(body), platform: "win32" });
    const bytes = fs.readFileSync(out);
    const crs = bytes.filter((b) => b === 0x0d).length;
    assert.equal(crs, 2, "exactly the body's two CRs");
    const p = fresh.parse(bytes);
    assert.ok(p, "the header parses");
    assert.equal(p.body.toString("utf8"), body);
    assert.ok(!bytes.subarray(0, bytes.length - p.body.length).includes(0x0d), "no CR in the header");
  } finally {
    Object.defineProperty(realOs, "EOL", eol);
    delete require.cache[require.resolve(modPath)];
    fs.rmSync(r, { recursive: true, force: true });
  }
});

test("(gen-atomic) the write replaces the file and leaves no temp file", () => {
  const d = tmpdir();
  try {
    const out = path.join(d, "sub", "w.ts");
    gen.writeAtomic(out, Buffer.from("one\n"));
    gen.writeAtomic(out, Buffer.from("two\n"));
    assert.equal(fs.readFileSync(out, "utf8"), "two\n");
    assert.deepEqual(fs.readdirSync(path.dirname(out)), ["w.ts"]);
  } finally { fs.rmSync(d, { recursive: true, force: true }); }
});

test("(gen-final-line) generate returns generate.sh's last line, counting `  name: XProps;` lines", () => {
  const r = fakeRepo();
  try {
    const out = path.join(r, "w.ts");
    const body = "export interface WidgetRegistry {\n  a: AProps;\n  bB: BbProps;\n  c: Cprops;\n   d: DProps;\n}";
    const line = gen.generate(r, out, { schema: () => Buffer.from(body) });
    assert.equal(line, `generated ${out} (2 widget names)`);
    assert.equal(gen.countWidgetNames(fs.readFileSync(committed)), 12);
  } finally { fs.rmSync(r, { recursive: true, force: true }); }
});

// one real JVM run: only when java resolves to a file AND the classpath cache is
// already built (a test never starts sbt)
function jvmSkip(): string | false {
  const java = gen.javaCommand(process.platform, process.env);
  if (!path.isAbsolute(java) || !fs.existsSync(java)) return "no java: JAVA_HOME unset and java not on PATH";
  const cache = path.join(repo, "target", "ermine-classpath");
  if (!fs.existsSync(cache) || fs.statSync(cache).size === 0) return "no target/ermine-classpath (a test does not run sbt)";
  if (fs.statSync(path.join(repo, "build.sbt")).mtimeMs > fs.statSync(cache).mtimeMs) return "target/ermine-classpath older than build.sbt (a test does not run sbt)";
  return false;
}

test("(gen-jvm-identity) a real run of generate.js writes the committed file byte-for-byte", { skip: jvmSkip() }, () => {
  const d = tmpdir();
  try {
    const out = path.join(d, "widgets.ts");
    gen.generate(repo, out);
    assert.ok(Buffer.compare(fs.readFileSync(out), fs.readFileSync(committed)) === 0,
      "regenerated != committed: the committed file is stale or the port changed the bytes");
  } finally { fs.rmSync(d, { recursive: true, force: true }); }
});

test("(gen-check-diff) check-generated.js names the first differing line, or null when identical", () => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { firstDifference } = require(path.join(client, "scripts", "check-generated.js"));
  assert.equal(firstDifference(Buffer.from("a\nb\n"), Buffer.from("a\nb\n")), null);
  assert.equal(firstDifference(Buffer.from("a\nb\n"), Buffer.from("a\nc\n")), 'first difference at line 2:\n- "b"\n+ "c"');
  assert.equal(firstDifference(Buffer.from("a\n"), Buffer.from("a\r\n")), 'first difference at line 1:\n- "a"\n+ "a\\r"');
  assert.equal(firstDifference(Buffer.from("a"), Buffer.from("a\nz")), 'first difference at line 2:\n- (end of file)\n+ "z"');
});
