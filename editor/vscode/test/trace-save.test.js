"use strict";

// DB programme S2f: the render trace as the PARAMETERS of an Ermine report
// (`Ermine: Save Render Trace`, `Ermine: Preview Render Trace`).
//
//     cd editor/vscode && node --test test/trace-save.test.js
//     (and `npm run test:preview`, which runs this file after the other two)
//
// A SEPARATE FILE for the reason test/connect-core.test.js gives (several
// roles edit test/preview-core.test.js); ITS HEADER RULES APPLY HERE
// UNCHANGED, and the one that matters most is restated:
//
//     A MODEL MUST MUTATE, OMIT AND CAPTURE EXACTLY WHAT THE GLUE MUTATES,
//     OMITS AND CAPTURES.
//
// So `saveModel` below takes its source from `m.panelAnswers.last` at the
// moment the glue does, asks the modal only when a file exists, checks
// `core.traceSaveStillApplies` against `m.panelAnswers.last` AFTER the modal,
// re-reads the bytes (`core.skeletonBytesStillApply`), and writes through
// `core.writeStep` with the permission the glue passes (`replace`).  The
// "glue pins" at the bottom read src/extension.js and fail if any of that
// stops being true there.
//
// Each REVERSE MUTANT the brief names is run and must be CAUGHT, by name:
//   "trace saved from a stale generation"  the source is not `panelAnswers.last`,
//                                          or the after-the-modal check is gone
//   "writer bypassing the modal"            an existing file replaced with no modal,
//                                          or the permission passed as `true`
//   "pick bypassing the guard"              the trace report picked by setting
//                                          `picked` and calling `renderNow`
//                                          instead of the picker's `commitPick`
// plus one of this file's own: "whitelist" (`traceParamsOf` spreading the
// server's object, so a planted url or password reaches a committed file).

const { test } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const core = require("../src/preview-core");

const SAMPLE = JSON.parse(fs.readFileSync(
  path.join(__dirname, "..", "..", "..", "core", "src", "test", "resources", "doc", "trace-sample.json"), "utf8"));
const SECRET = "Tr0ub4dor.and_3-ish";
const URL = "jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;user=ermine;password=" + SECRET;
const clone = (x) => JSON.parse(JSON.stringify(x));
const FOLDER = "/w";
const REPORT = "/w/core/src/test/resources/modules/Doc/TraceReport.e";
const PARAMS = "/w/.ermine/preview/Doc.TraceReport/report.params.json";

// ------------------------------------------------------ the projection

test("traceParamsOf: the captured sample is copied key for key, in order", () => {
  const r = core.traceParamsOf(SAMPLE);
  assert.strictEqual(r.problem, undefined);
  assert.strictEqual(JSON.stringify(r.value), JSON.stringify(SAMPLE));
  assert.deepStrictEqual(JSON.parse(core.traceParamsText(r.value)), SAMPLE);
  assert.ok(core.traceParamsText(r.value).endsWith("}\n"));
});

test("traceParamsOf: only Layout.Trace's keys are written; table and database (the Spread keys) survive", () => {
  const t = clone(SAMPLE);
  t.url = URL; t.password = SECRET; t.user = "ermine";
  t.connection.url = URL; t.connection.host = "127.0.0.1"; t.connection.user = "ermine";
  t.queries[0].password = SECRET; t.queries[0].jdbc = URL;
  t.queries[0].setup = [{ kind: "memo", table: "MemoHash_9f2c41", created: false, ms: 0.8, url: URL }];
  t.phases[0].secret = SECRET;
  t.running = { path: "$.fetch[1]", sinceMs: 12, host: "127.0.0.1" };
  t.truncated = { queries: 2, sqlShortened: false, user: "ermine" };
  const text = core.traceParamsText(core.traceParamsOf(t).value);
  assert.ok(!text.includes(SECRET) && !text.includes("jdbc:") && !text.includes("127.0.0.1") && !text.includes('"user"'),
    "a planted url, password, user or host reached the params text: " + text);
  const back = JSON.parse(text);
  assert.strictEqual(back.connection.database, "ErmineSales");
  assert.deepStrictEqual(back.queries[0].setup, [{ kind: "memo", table: "MemoHash_9f2c41", created: false, ms: 0.8 }]);
  assert.deepStrictEqual(Object.keys(back.queries[0]).slice(0, 7),
    ["path", "delivery", "dialect", "sql", "sqlBytes", "statements", "setup"]);
  assert.deepStrictEqual(back.running, { path: "$.fetch[1]", sinceMs: 12 });
  assert.deepStrictEqual(back.truncated, { queries: 2, sqlShortened: false });
});

test("traceParamsOf: an absent optional key stays absent; a missing or mistyped required key is named", () => {
  const t = clone(SAMPLE);
  delete t.queries[0].fetchMs; delete t.queries[0].dialect; delete t.totals.documentBytes; delete t.connection.profile;
  const v = core.traceParamsOf(t).value;
  assert.ok(!("fetchMs" in v.queries[0]) && !("dialect" in v.queries[0]) && !("documentBytes" in v.totals) &&
            !("profile" in v.connection));
  for (const [mutate, where] of [
    [(x) => { delete x.totals.rowsRead; }, "$.totals.rowsRead"],
    [(x) => { x.queries[1].rows = 2.5; }, "$.queries[1].rows"],
    [(x) => { x.phases[3].name = 7; }, "$.phases[3].name"],
    [(x) => { delete x.connection; }, "$.connection"],
    [(x) => { x.v = "1"; }, "$.v"],
    [(x) => { delete x.generation; }, "$.generation"],
    [(x) => { x.queries[0].setup = [{ kind: "memo" }]; }, "$.queries[0].setup[0].ms"],
  ]) {
    const x = clone(SAMPLE); mutate(x);
    const r = core.traceParamsOf(x);
    assert.strictEqual(r.problem && r.problem.reason, "trace-not-decodable", where);
    assert.ok(r.problem.message.includes(where), r.problem.message + " should name " + where);
  }
  assert.strictEqual(core.traceParamsOf(undefined).problem.reason, "no-trace");
});

// ------------------------------------------------------ the decisions

test("traceSaveSource / traceSaveStillApplies: the CURRENT answer, and only while it is still current", () => {
  assert.strictEqual(core.traceSaveSource(null).reason, "no-answer");
  assert.strictEqual(core.traceSaveSource({ ok: false, status: 400, generation: 3 }).reason, "no-trace");
  const a = { ok: true, generation: 110, document: {}, trace: SAMPLE };
  const s = core.traceSaveSource(a);
  assert.strictEqual(s.run, true);
  assert.strictEqual(s.generation, 110);
  assert.deepStrictEqual(JSON.parse(s.text), SAMPLE);
  assert.deepStrictEqual(core.traceSaveStillApplies(s, a), { apply: true, why: null });
  const newer = { ok: true, generation: 111, trace: SAMPLE };
  const still = core.traceSaveStillApplies(s, newer);
  assert.strictEqual(still.apply, false);
  assert.match(still.why, /a newer render answered \(generation 111, the trace was of 110\)/);
  // a failed answer's trace is saved too: it is what the Trace view shows
  assert.strictEqual(core.traceSaveSource({ ok: false, status: 500, generation: 9, trace: SAMPLE }).run, true);
});

test("traceSavePlan + writeStep: the overwrite mode needs the caller's permission as well", () => {
  const paths = core.paramsPaths(core.makePick("file://" + REPORT, REPORT, "report", "Doc.TraceReport", []), FOLDER);
  assert.strictEqual(paths.paramsPath, PARAMS);
  const create = core.traceSavePlan(paths, "{}\n", false);
  assert.deepStrictEqual(create.files.map((f) => [f.what, f.path, f.mode]), [[core.WRITE_PARAMS, PARAMS, "ifAbsent"]]);
  const replace = core.traceSavePlan(paths, "{}\n", true);
  assert.strictEqual(replace.files[0].mode, "explicitOverwrite");
  assert.strictEqual(core.writeStep(replace.files[0], PARAMS, undefined).problem.reason, "overwrite-not-permitted");
  assert.strictEqual(core.writeStep(replace.files[0], PARAMS, true).act, "explicitOverwrite");
  assert.strictEqual(core.traceSavePlan(paths, "{}\n", "yes").files[0].mode, "ifAbsent", "only a strict true replaces");
  assert.strictEqual(core.traceSavePlan({ problem: {} }, "{}", true).problem.reason, "no-params-path");
});

test("traceReportFile / traceReportPick / the modal", () => {
  assert.strictEqual(core.traceReportFile([
    "/w/core/target/scala-3.3.8/test-classes/modules/Doc/TraceReport.e",
    "/w/wt/other/core/src/test/resources/modules/Doc/TraceReport.e",
    REPORT,
    "/w/core/src/test/resources/modules/Doc/TraceReportOld.e",
  ]).fsPath, REPORT);
  assert.strictEqual(core.traceReportFile(["/w/core/target/src/test/resources/modules/Doc/TraceReport.e"]).problem.reason,
    "no-trace-report");
  assert.strictEqual(core.traceReportPick("u", REPORT, "Doc.Other", []).problem.reason, "trace-report-module");
  const p = core.traceReportPick("file://" + REPORT, REPORT, "Doc.TraceReport", ["/w/r"]).pick;
  assert.deepStrictEqual([p.binding, p.module, p.fsPath], ["report", "Doc.TraceReport", REPORT]);
  const q = core.traceSaveConfirmation({ paramsPath: PARAMS }, 110);
  assert.ok(q.message.includes(PARAMS) && q.message.includes("render 110") && q.confirm === "Replace");
  assert.strictEqual(core.traceSaveConfirmed("Replace"), true);
  for (const c of [undefined, "replace", "Cancel", true]) assert.strictEqual(core.traceSaveConfirmed(c), false);
});

// ------------------------------------------------------ the model

/**
 * The glue's `saveRenderTrace`, statement for statement, over a fake disk.
 * `hooks.modal(m)` runs while the modal is open (a new answer, an edit) and
 * returns the button.  Mutant switches reproduce the three named defects.
 */
async function saveModel(m, preview, hooks, mut) {
  const o = mut || {};
  const say = (reason, message) => core.traceSaveResult({ problem: { reason, message } });
  const asked = core.traceSaveSource(o.staleSource ? m.panelAnswers.good : m.panelAnswers.last);
  if (!asked.run) return say(asked.reason, asked.message);
  const file = core.traceReportFile(m.files);
  if (file.problem) return say(file.problem.reason, file.problem.message);
  const target = core.traceReportPick("file://" + file.fsPath, file.fsPath, m.module, []);
  if (target.problem) return say(target.problem.reason, target.problem.message);
  const paths = core.paramsPaths(target.pick, FOLDER);
  const verdict = core.skeletonCommandVerdict(target.pick, paths, true);
  if (!verdict.run) return say(verdict.reason, verdict.message);
  const read = (p) => (m.disk.has(p) ? m.disk.get(p) : null);
  const existing = read(paths.paramsPath);
  const replace = existing !== null;
  if (replace && !o.noModal) {
    const question = core.traceSaveConfirmation(paths, asked.generation);
    m.modals.push(question.message);
    const choice = hooks && hooks.modal ? hooks.modal(m) : undefined;
    if (!core.traceSaveConfirmed(choice)) return core.traceSaveResult({ abandoned: true });
  }
  if (!o.noStillCheck) {
    const still = core.traceSaveStillApplies(asked, m.panelAnswers.last);
    if (!still.apply) return core.traceSaveResult({ abandoned: true });
  }
  const bytes = core.skeletonBytesStillApply(replace, existing, replace ? read(paths.paramsPath) : null, paths.paramsPath);
  if (!bytes.apply) return say(bytes.reason, bytes.message);
  const plan = core.traceSavePlan(paths, asked.text, replace);
  const wrote = [];
  for (const f of plan.files) {
    const step = core.writeStep(f, paths.paramsPath, o.permissionTrue ? true : replace);
    if (step.problem) return say(step.problem.reason, step.problem.message);
    if (step.act === "ifAbsent" && m.disk.has(f.path)) return core.traceSaveResult({ existed: true });
    m.disk.set(f.path, f.text);
    wrote.push(f.what);
  }
  if (preview) {
    if (o.bypassGuard) { m.picked = target.pick; m.renders.push("renderNow"); }
    else m.commitPicks.push(target.pick);
  }
  return core.traceSaveResult({ wrote: true, replaced: replace, target: paths.paramsPath });
}

function world(over) {
  const last = { ok: true, generation: 110, document: {}, trace: SAMPLE };
  return Object.assign({
    panelAnswers: { last, good: last }, files: [REPORT], module: "Doc.TraceReport",
    disk: new Map(), modals: [], commitPicks: [], renders: [], picked: null,
  }, over || {});
}

test("model: no file -> written with no modal, the current trace, and Preview picks through commitPick", async () => {
  const m = world();
  const r = await saveModel(m, true);
  assert.deepStrictEqual([r.wrote, r.replaced, m.modals.length], [true, false, 0]);
  assert.deepStrictEqual(JSON.parse(m.disk.get(PARAMS)), SAMPLE);
  assert.deepStrictEqual(m.commitPicks.map((p) => p.module + "." + p.binding), ["Doc.TraceReport.report"]);
  assert.deepStrictEqual(m.renders, []);
});

test("model: an existing file is replaced only on Replace; a decline leaves it byte for byte", async () => {
  const declined = world(); declined.disk.set(PARAMS, "mine\n");
  const d = await saveModel(declined, false, { modal: () => undefined });
  assert.deepStrictEqual([d.abandoned, declined.disk.get(PARAMS), declined.modals.length], [true, "mine\n", 1]);
  const ok = world(); ok.disk.set(PARAMS, "mine\n");
  const r = await saveModel(ok, false, { modal: () => "Replace" });
  assert.deepStrictEqual([r.wrote, r.replaced], [true, true]);
  assert.deepStrictEqual(JSON.parse(ok.disk.get(PARAMS)), SAMPLE);
  assert.match(ok.modals[0], /Replace \/w\/\.ermine\/preview\/Doc\.TraceReport\/report\.params\.json with the trace of render 110/);
});

test("model: a newer answer while the modal is open -> nothing written; an edit while it is open -> refused", async () => {
  const m = world(); m.disk.set(PARAMS, "mine\n");
  const r = await saveModel(m, true, { modal: (w) => { w.panelAnswers = { last: { ok: true, generation: 111, trace: SAMPLE }, good: null }; return "Replace"; } });
  assert.deepStrictEqual([r.abandoned, m.disk.get(PARAMS), m.commitPicks.length], [true, "mine\n", 0]);
  const e = world(); e.disk.set(PARAMS, "mine\n");
  const r2 = await saveModel(e, false, { modal: (w) => { w.disk.set(PARAMS, "edited\n"); return "Replace"; } });
  assert.deepStrictEqual([r2.problem && r2.problem.reason, e.disk.get(PARAMS)], ["params-changed", "edited\n"]);
});

test("model: the recursion rule -- saving while the trace report is picked replaces its own params, through the modal", async () => {
  // the trace report's own render answered generation 120 with ITS trace
  const own = clone(SAMPLE); own.generation = 120; own.queries = own.queries.slice(2);
  const m = world({ panelAnswers: { last: { ok: true, generation: 120, trace: own }, good: null } });
  m.disk.set(PARAMS, core.traceParamsText(SAMPLE));
  const r = await saveModel(m, false, { modal: () => "Replace" });
  assert.deepStrictEqual([r.replaced, m.modals.length, JSON.parse(m.disk.get(PARAMS)).generation], [true, 1, 120]);
});

// ------------------------------------------------------ reverse mutants (model)

test("mutant 'trace saved from a stale generation' is KILLED (source = panelAnswers.good; no after-modal check)", async () => {
  // the last answer FAILED with a trace; the good document is an older one
  const older = clone(SAMPLE); older.generation = 100;
  const lastFailed = { ok: false, status: 500, generation: 110, trace: SAMPLE };
  const mk = () => world({ panelAnswers: { last: lastFailed, good: { ok: true, generation: 100, trace: older } } });
  const real = mk(); await saveModel(real, false);
  assert.strictEqual(JSON.parse(real.disk.get(PARAMS)).generation, 110);
  // alone, the stale source is caught by the after-modal check (it abandons);
  // with that check gone too, it writes the OLDER generation
  const mut = mk(); const r1 = await saveModel(mut, false, null, { staleSource: true });
  assert.deepStrictEqual([r1.abandoned, mut.disk.has(PARAMS)], [true, false]);
  const mut2 = mk(); await saveModel(mut2, false, null, { staleSource: true, noStillCheck: true });
  assert.strictEqual(JSON.parse(mut2.disk.get(PARAMS)).generation, 100,
    "the stale-source mutant must write another generation, or this test proves nothing");
  const newer = (w) => { w.panelAnswers = { last: { ok: true, generation: 111, trace: SAMPLE }, good: null }; return "Replace"; };
  const m2 = world(); m2.disk.set(PARAMS, "mine\n");
  await saveModel(m2, false, { modal: newer }, { noStillCheck: true });
  assert.notStrictEqual(m2.disk.get(PARAMS), "mine\n", "the no-check mutant writes the superseded trace");
});

test("mutant 'writer bypassing the modal' is KILLED (no modal; permission passed as true)", async () => {
  const m = world(); m.disk.set(PARAMS, "mine\n");
  await saveModel(m, false, { modal: () => undefined }, { noModal: true });
  assert.notStrictEqual(m.disk.get(PARAMS), "mine\n", "the mutant must overwrite, or this test proves nothing");
  assert.strictEqual(m.modals.length, 0);
  const real = world(); real.disk.set(PARAMS, "mine\n");
  await saveModel(real, false, { modal: () => undefined });
  assert.strictEqual(real.disk.get(PARAMS), "mine\n");
});

test("mutant 'pick bypassing the guard' is KILLED in the model (renderNow, no commitPick)", async () => {
  const m = world();
  await saveModel(m, true, null, { bypassGuard: true });
  assert.deepStrictEqual([m.commitPicks.length, m.renders], [0, ["renderNow"]]);
});

// ------------------------------------------------------ glue pins

const SRC = path.join(__dirname, "..", "src", "extension.js");
const REGEX_MAY_START = /[=(,:[!&|?{};+\-*%~^<>]/;
/** test/preview-core.test.js's `codeOf`, copied: comments out, strings and regexes kept. */
function codeOf(text) {
  const s = String(text);
  let out = "";
  let prev = "";
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    const d = s[i + 1];
    if (c === "/" && d === "/") { while (i < s.length && s[i] !== "\n") i++; continue; }
    if (c === "/" && d === "*") { i += 2; while (i < s.length && !(s[i] === "*" && s[i + 1] === "/")) i++; i += 2; continue; }
    if (c === '"' || c === "'" || c === "`") {
      out += c; i += 1;
      while (i < s.length) {
        if (s[i] === "\\") { out += s.slice(i, i + 2); i += 2; continue; }
        out += s[i]; i += 1;
        if (s[i - 1] === c) break;
      }
      prev = c; continue;
    }
    if (c === "/" && REGEX_MAY_START.test(prev)) {
      out += c; i += 1;
      let inClass = false;
      while (i < s.length) {
        if (s[i] === "\\") { out += s.slice(i, i + 2); i += 2; continue; }
        if (s[i] === "[") inClass = true; else if (s[i] === "]") inClass = false;
        out += s[i]; i += 1;
        if (s[i - 1] === "/" && !inClass) break;
      }
      prev = "/"; continue;
    }
    out += c;
    if (!/\s/.test(c)) prev = c;
    i += 1;
  }
  return out;
}

function body(src, from, to) {
  const a = src.indexOf(from);
  if (a < 0) return "";
  const b = to ? src.indexOf(to, a + from.length) : -1;
  return src.slice(a, b < 0 ? undefined : b);
}

/** "trace saved from a stale generation": the source and the after-modal check. */
function stalePins(raw) {
  const src = codeOf(raw);
  const v = [];
  const f = body(src, "async function saveRenderTrace(", "\nmodule.exports");
  if (!f) return ["stale generation: saveRenderTrace is gone"];
  const firstAwait = f.indexOf("await ");
  const source = f.indexOf("const asked = core.traceSaveSource(panelAnswers.last);");
  if (source < 0 || (firstAwait >= 0 && source > firstAwait)) {
    v.push("stale generation: the source is not core.traceSaveSource(panelAnswers.last), decided before the first await");
  }
  if (/panelAnswers\.good|\blastAnswer\b|lastServerAnswer/.test(f)) v.push("stale generation: the command reads panelAnswers.good / lastAnswer");
  const modal = f.indexOf("{ modal: true }");
  const still = f.indexOf("core.traceSaveStillApplies(asked, panelAnswers.last)");
  const write = f.indexOf("applyWritePlan(");
  if (still < 0 || still < modal || still > write) {
    v.push("stale generation: traceSaveStillApplies(asked, panelAnswers.last) is not between the modal and the write");
  }
  if (!/if \(!still\.apply\) \{[\s\S]{0,300}?return core\.traceSaveResult\(\{ abandoned: true \}\);/.test(f)) {
    v.push("stale generation: a failed still-applies check does not return before the write");
  }
  return v;
}

/** "writer bypassing the modal": the modal, the TOCTOU re-read, the permission. */
function modalPins(raw) {
  const src = codeOf(raw);
  const v = [];
  const f = body(src, "async function saveRenderTrace(", "\nmodule.exports");
  if (!/const existing = await readTextIfPresent\(paths\.paramsPath\);\s*const replace = existing !== null;\s*if \(replace\) \{\s*const question = core\.traceSaveConfirmation\(paths, asked\.generation\);\s*const choice = await vscode\.window\.showWarningMessage\(question\.message, \{ modal: true \}, question\.confirm\);\s*if \(!core\.traceSaveConfirmed\(choice\)\) \{/.test(f)) {
    v.push("modal: an existing file is not guarded by the modal (existing -> replace -> if (replace) -> showWarningMessage modal -> traceSaveConfirmed)");
  }
  if ((f.match(/applyWritePlan\(/g) || []).length !== 1 || !/applyWritePlan\(plan\.files, paths\.paramsPath, replace\)/.test(f)) {
    v.push("modal: the write is not exactly applyWritePlan(plan.files, paths.paramsPath, replace) -- the permission must be `replace`");
  }
  if (!/const plan = core\.traceSavePlan\(paths, asked\.text, replace\);/.test(f)) v.push("modal: the plan's mode is not `replace`");
  const bytes = f.indexOf("core.skeletonBytesStillApply(replace, existing, replace ? await readTextIfPresent(paths.paramsPath) : null,");
  const link = f.indexOf("await symlinkProblem(paths, [paths.paramsPath]);");
  const mkdir = f.indexOf("await ensureDirectory(paths.dir);");
  const write = f.indexOf("applyWritePlan(");
  if (bytes < 0 || bytes > write) v.push("modal: the bytes are not re-read (skeletonBytesStillApply) before the write");
  if (link < 0 || link > mkdir) v.push("modal: the symlink check does not come before the directory is made");
  if (/writeTextFile\(|writeFile\(|workspace\.fs\.write/.test(f)) v.push("modal: saveRenderTrace writes the disk directly");
  return v;
}

/** "pick bypassing the guard": Preview picks through commitPick, the picker's own tail. */
function guardPins(raw) {
  const src = codeOf(raw);
  const v = [];
  const f = body(src, "async function saveRenderTrace(", "\nmodule.exports");
  if (!/if \(preview\) \{\s*(?:\/\/[^\n]*\n\s*)?await commitPick\(fileUri, file\.fsPath, core\.TRACE_REPORT_BINDING, listed\.module, listed\);/.test(f)) {
    v.push("guard: Preview does not pick through commitPick(fileUri, file.fsPath, core.TRACE_REPORT_BINDING, listed.module, listed)");
  }
  if (/\brenderNow\(|scheduleRender\(|sendRequest\("ermine\/render"|\bpicked\s*=|applyGuard\(|wedgeMark|mayAutoRender/.test(f)) {
    v.push("guard: saveRenderTrace renders, picks or touches the guard itself instead of going through commitPick");
  }
  const pick = body(src, "async function pickReport(", "async function commitPick(");
  if (!/await commitPick\(fileUri, file\.fsPath, binding, moduleName, listed\);/.test(pick) || /\bpicked = /.test(pick)) {
    v.push("guard: pickReport no longer ends in commitPick (the two picks could drift)");
  }
  const commit = body(src, "async function commitPick(", "async function renderCommand(");
  for (const [re, what] of [
    [/picked = core\.makePick\(fileUri\.toString\(\), fsPath, binding, moduleName, rootsFor\(fileUri\)\);/, "the pick"],
    [/applyGuard\(core\.guardReduce\(wedgeMark, \{ type: "pick", pick: picked \}\)\);/, "WP-22's pick event"],
    [/forgetSchemaAttempts\(\);/, "forgetting the first-pick attempt"],
    [/panelAnswers = core\.initialPanelAnswers\(\);/, "the panel's answers"],
    [/await renderNow\("the report was picked", true, core\.TRIGGER_EXPLICIT\);/, "the explicit render"],
  ]) if (!re.test(commit)) v.push("guard: commitPick lost " + what);
  // the other `picked = core.makePick(` is restorePick's (a window reload
  // restoring the remembered pick, which renders nothing by itself)
  if ((src.match(/\bpicked = core\.makePick\(/g) || []).length !== 2 ||
      !/picked = core\.makePick\(/.test(body(src, "function restorePick(", "function rememberPick("))) {
    v.push("guard: a pick is made somewhere other than commitPick and restorePick");
  }
  return v;
}

test("glue pins (S2f): the real extension.js is clean", () => {
  const raw = fs.readFileSync(SRC, "utf8");
  assert.deepStrictEqual(stalePins(raw), []);
  assert.deepStrictEqual(modalPins(raw), []);
  assert.deepStrictEqual(guardPins(raw), []);
  const src = codeOf(raw);
  assert.ok(src.includes("vscode.commands.registerCommand(core.SAVE_TRACE_COMMAND, () => saveRenderTrace(false)),"));
  assert.ok(src.includes("vscode.commands.registerCommand(core.PREVIEW_TRACE_COMMAND, () => saveRenderTrace(true))"));
  assert.strictEqual((src.match(/saveRenderTrace\(/g) || []).length, 3, "one definition, two registrations");
  const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "package.json"), "utf8"));
  const titles = Object.fromEntries(pkg.contributes.commands.map((c) => [c.command, c.title]));
  assert.strictEqual(titles[core.SAVE_TRACE_COMMAND], "Ermine: Save Render Trace");
  assert.strictEqual(titles[core.PREVIEW_TRACE_COMMAND], "Ermine: Preview Render Trace");
  assert.ok(/test\/trace-save\.test\.js/.test(pkg.scripts["test:preview"]));
});

test("reverse mutants on the SOURCE: each is caught by name", () => {
  const raw = fs.readFileSync(SRC, "utf8");
  const mutants = [
    ["trace saved from a stale generation (panelAnswers.good)", stalePins,
     (s) => s.replace("core.traceSaveSource(panelAnswers.last)", "core.traceSaveSource(panelAnswers.good)"), "stale generation"],
    ["trace saved from a stale generation (no after-modal check)", stalePins,
     (s) => s.replace("const still = core.traceSaveStillApplies(asked, panelAnswers.last);", "const still = { apply: true };"),
     "stale generation"],
    ["writer bypassing the modal (no modal)", modalPins,
     (s) => s.replace("  if (replace) {\n    const question = core.traceSaveConfirmation",
                      "  if (false) {\n    const question = core.traceSaveConfirmation"), "modal"],
    ["writer bypassing the modal (permission true)", modalPins,
     (s) => s.replace("applyWritePlan(plan.files, paths.paramsPath, replace)", "applyWritePlan(plan.files, paths.paramsPath, true)"),
     "modal"],
    ["pick bypassing the guard", guardPins,
     (s) => s.replace("await commitPick(fileUri, file.fsPath, core.TRACE_REPORT_BINDING, listed.module, listed);",
                      "picked = target.pick; await renderNow(\"trace\", true, core.TRIGGER_EXPLICIT);"), "guard"],
  ];
  for (const [name, pins, mutate, tag] of mutants) {
    const mutated = mutate(raw);
    assert.notStrictEqual(mutated, raw, name + ": the mutation did not apply (the source moved)");
    const v = pins(mutated);
    assert.ok(v.length > 0 && v.every((x) => x.startsWith(tag)), name + " SURVIVED: " + JSON.stringify(v));
  }
  // and the whitelist mutant on preview-core: a projection that spreads the object
  const spread = (t) => ({ value: Object.assign({}, t) });
  const planted = clone(SAMPLE); planted.connection.url = URL;
  assert.ok(core.traceParamsText(spread(planted).value).includes(SECRET), "the whitelist mutant must leak");
  assert.ok(!core.traceParamsText(core.traceParamsOf(planted).value).includes(SECRET), "whitelist SURVIVED");
});
