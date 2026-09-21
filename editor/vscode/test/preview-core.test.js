"use strict";

// Unit tests for src/preview-core.js -- the preview loop's decisions.
//
//     cd editor/vscode && node --test test/preview-core.test.js
//
// There is no VS Code here and there is none on any machine that runs the
// gates, so every rule WP-7 could get wrong lives in a pure function and is
// tested here instead: which roots are sent, which answer is stale, whether
// a notification raises the stuck banner, when a save re-renders, and what
// each of the two settings routes carries.
//
// The stuck machine is the part with real ordering hazards (two server
// threads, a `seq` that restarts at 1 in a fresh process), so it gets both
// table tests for the named cases and a generated-sequence test for the
// invariants.

const { test } = require("node:test");
const assert = require("node:assert");
const path = require("node:path");

const core = require("../src/preview-core");

// ------------------------------------------------------------------ roots

test("roots: a relative entry is absolutised against the owning folder", () => {
  const { roots, problems } = core.absoluteRoots(["reports", "./widgets"], path.join("/w", "folder"));
  assert.deepStrictEqual(roots, [path.join("/w", "folder", "reports"), path.join("/w", "folder", "widgets")]);
  assert.deepStrictEqual(problems, []);
});

test("roots: an absolute entry is kept and normalised", () => {
  const { roots } = core.absoluteRoots([path.join("/a", "b", "..", "c")], "/w");
  assert.deepStrictEqual(roots, [path.join("/a", "c")]);
});

test("roots: duplicates collapse and the order the developer wrote is kept", () => {
  const { roots } = core.absoluteRoots(["/b", "/a", "/b"], "/w");
  assert.deepStrictEqual(roots, [path.normalize("/b"), path.normalize("/a")]);
});

test("roots: a bad entry is named and never sent", () => {
  const nonString = core.absoluteRoots(["/a", 7], "/w");
  assert.deepStrictEqual(nonString.roots, [path.normalize("/a")]);
  assert.strictEqual(nonString.problems.length, 1);
  assert.match(nonString.problems[0], /entry that is a number/);

  const empty = core.absoluteRoots(["  "], "/w");
  assert.deepStrictEqual(empty.roots, []);
  assert.match(empty.problems[0], /empty entry/);

  const notArray = core.absoluteRoots("reports", "/w");
  assert.deepStrictEqual(notArray.roots, []);
  assert.match(notArray.problems[0], /not a string/);

  const noFolder = core.absoluteRoots(["reports"], undefined);
  assert.deepStrictEqual(noFolder.roots, []);
  assert.match(noFolder.problems[0], /no workspace folder/);
});

test("roots: absent means no roots and no complaint", () => {
  assert.deepStrictEqual(core.absoluteRoots(undefined, "/w"), { roots: [], problems: [] });
  assert.deepStrictEqual(core.absoluteRoots(null, "/w"), { roots: [], problems: [] });
});

// --------------------------------------------------------------- requests

const PICK = core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc", "/w/lib"]);

test("requests: a render and a schema carry EXACTLY the same roots (section 6, Q7)", () => {
  const render = core.renderParams(PICK, null, 3);
  const schema = core.schemaParams(PICK);
  assert.deepStrictEqual(render.roots, schema.roots);
  assert.deepStrictEqual(render.roots, ["/w/doc", "/w/lib"]);
  assert.strictEqual(render.uri, schema.uri);
  assert.strictEqual(render.binding, schema.binding);
});

test("requests: neither builder can be made to share the pick's array", () => {
  const render = core.renderParams(PICK, null, 1);
  render.roots.push("/tmp/injected");
  assert.deepStrictEqual(PICK.roots, ["/w/doc", "/w/lib"]);
  assert.deepStrictEqual(core.schemaParams(PICK).roots, ["/w/doc", "/w/lib"]);
});

test("requests: WP-7 sends an EMPTY params object, not null, and carries the generation", () => {
  // MEASURED against a real server: `null` answers "expected an object
  // (Query), found null" and names no key, while `{}` answers 'the required
  // key "fromDay" is missing', which is what the ticket's done-when wants.
  assert.deepStrictEqual(core.renderParams(PICK, undefined, 7).params, {});
  assert.deepStrictEqual(core.renderParams(PICK, null, 7).params, {});
  assert.deepStrictEqual(core.renderParams(PICK, { fromDay: "2026-01-05" }, 7).params, { fromDay: "2026-01-05" });
  assert.strictEqual(core.renderParams(PICK, null, 7).generation, 7);
  assert.deepStrictEqual(core.reportsParams(PICK.uri), { uri: "file:///w/doc/Sales.e" });
});

// ------------------------------------------------------------- generation

test("generation: an answer behind the current one is discarded, level and ahead are kept", () => {
  assert.strictEqual(core.isCurrentGeneration(5, { ok: true, generation: 4 }), false);
  assert.strictEqual(core.isCurrentGeneration(5, { ok: true, generation: 5 }), true);
  assert.strictEqual(core.isCurrentGeneration(5, { ok: true, generation: 6 }), true);
});

test("generation: an answer that carries none is kept, because it is a refusal to show", () => {
  assert.strictEqual(core.isCurrentGeneration(5, { ok: false, status: 400, generation: null }), true);
  assert.strictEqual(core.isCurrentGeneration(5, { ok: false, status: 400 }), true);
});

// --------------------------------------------------- the re-render rules

test("invalidated: the picked module matches, anything else does not", () => {
  assert.strictEqual(core.shouldRerenderOnInvalidated(PICK, ["Other", "Sales"]), true);
  assert.strictEqual(core.shouldRerenderOnInvalidated(PICK, ["Other"]), false);
  assert.strictEqual(core.shouldRerenderOnInvalidated(PICK, []), false);
  assert.strictEqual(core.shouldRerenderOnInvalidated(PICK, "Sales"), false);
  assert.strictEqual(core.shouldRerenderOnInvalidated(undefined, ["Sales"]), false);
});

test("invalidated: a pick whose module the server never named matches nothing", () => {
  const typed = core.makePick("file:///w/x.e", "/w/x.e", "report", null, []);
  assert.strictEqual(core.shouldRerenderOnInvalidated(typed, ["Sales", "x"]), false);
});

test("Q11: a placement 404 is the one with a `reason`, and the cached module has nothing to do with it", () => {
  const placement = { ok: false, status: 404, message: "cannot read Sales.e", reason: "unreadable" };
  const runner404 = { ok: false, status: 404, message: "no binding named reprot" };

  // THE CASE THE REVIEW CAUGHT: a report picked while it existed has its
  // module cached and persisted, so gating on "the module is unknown" made
  // Q11's own scenario -- deleted, then restored -- never fire.
  assert.strictEqual(core.shouldRerenderOnFileEvent(PICK, placement), true);
  assert.strictEqual(core.isPlacement404(placement), true);

  // A Runner 404 carries no `reason`: the file reads fine, its module is
  // loaded, and `invalidated` owns it.
  assert.strictEqual(core.shouldRerenderOnFileEvent(PICK, runner404), false);
  assert.strictEqual(core.isPlacement404(runner404), false);

  for (const other of [
    { ok: false, status: 500, message: "does not load" },
    { ok: false, status: 409, message: "shadowed", reason: "shadowed" },
    { ok: false, status: 400, message: "bad roots" },
    { ok: true, document: {} },
    undefined,
  ]) {
    assert.strictEqual(core.shouldRerenderOnFileEvent(PICK, other), false, JSON.stringify(other));
  }

  // An event for another path never renders, whatever the answer was.
  assert.strictEqual(core.shouldRerenderOnFileEvent(PICK, placement, "/w/doc/Other.e"), false);
  assert.strictEqual(core.shouldRerenderOnFileEvent(PICK, placement, PICK.fsPath), true);
});

test("Q11: an old server that sends no `reason` degrades to no trigger, never to a wrong one", () => {
  // The whole vocabulary, and the compatibility rule in one place.
  for (const reason of ["not-ermine-source", "unreadable", "no-module-header",
                        "header-deeper-than-path", "not-placed"]) {
    assert.strictEqual(core.isPlacement404({ ok: false, status: 404, reason }), true, reason);
  }
  assert.strictEqual(core.isPlacement404({ ok: false, status: 404 }), false);
  assert.strictEqual(core.isPlacement404({ ok: false, status: 404, reason: "" }), false);
  assert.strictEqual(core.isPlacement404({ ok: false, status: 404, reason: 7 }), false);
});

// ------------------------------------------------------- the stuck state

function notification(stuck, seq, message) {
  return { type: "notification", stuck, seq, message: message || "wedged" };
}

test("stuck: the rising edge raises and the falling edge clears, re-renders and re-asks the schema", () => {
  let r = core.stuckReduce(core.initialStuckState(), notification(true, 1));
  assert.strictEqual(r.state.stuck, true);
  assert.strictEqual(r.state.highWater, 1);
  assert.strictEqual(r.effects.raised, true);

  r = core.stuckReduce(r.state, notification(false, 2, "recovered"));
  assert.strictEqual(r.state.stuck, false);
  assert.strictEqual(r.state.highWater, 2);
  assert.strictEqual(r.effects.cleared, true, "a banner was shown, so the toast is earned");
  assert.strictEqual(r.effects.rerender, true);
  assert.strictEqual(r.effects.schema, true);
});

test("stuck: INVERTED ORDER -- {stuck:false, seq:2} before {stuck:true, seq:1} -- the highest seq wins AND the clear still re-renders", () => {
  // IM-1's staged collision: the two edges are sent by two threads with
  // nothing ordering them, so the clear really can arrive first.
  let r = core.stuckReduce(core.initialStuckState(), notification(false, 2, "recovered"));
  assert.strictEqual(r.state.stuck, false);
  assert.strictEqual(r.state.highWater, 2);
  // DM-2: this client never saw a rising edge, and it is exactly the client
  // that needs the render -- it has a stuck refusal in its tab and every
  // `invalidate` of the wedge was dropped. No toast, because no banner was
  // ever shown.
  assert.strictEqual(r.effects.rerender, true);
  assert.strictEqual(r.effects.schema, true);
  assert.strictEqual(r.effects.cleared, false);

  r = core.stuckReduce(r.state, notification(true, 1));
  assert.strictEqual(r.state.stuck, false, "the lower seq must not resurrect the banner");
  assert.strictEqual(r.state.highWater, 2);
  assert.strictEqual(r.effects.raised, false);
  assert.strictEqual(r.effects.rerender, false);
});

test("stuck: the whole DM-2 sequence -- answer first, clear second, rise last -- leaves a render asked for", () => {
  // The order the server really produces under a collision: the wedged
  // job's ANSWER (with the marker) is sent before `{stuck:true}`, and
  // `{stuck:false}` from the preview thread can overtake the timer's rise.
  let state = core.initialStuckState();
  let renders = 0;
  const step = (event) => {
    const r = core.stuckReduce(state, event);
    state = r.state;
    if (r.effects.rerender) renders++;
    return r;
  };
  step(notification(false, 2, "the preview recovered; re-render"));
  step({ type: "answer", stuck: true, message: "refused while stuck", seqAtSend: 0 });
  step(notification(true, 1));
  assert.strictEqual(state.stuck, false, "the highest seq (the clear) decides");
  assert.strictEqual(renders, 1, "the user must not be left with a stuck refusal in the tab");
});

test("stuck: a repeated seq is ignored", () => {
  const raised = core.stuckReduce(core.initialStuckState(), notification(true, 4)).state;
  const again = core.stuckReduce(raised, notification(false, 4, "recovered"));
  assert.strictEqual(again.state.stuck, true);
  assert.deepStrictEqual(again.effects.cleared, false);
});

test("stuck: a notification with no seq is applied but does not move the mark", () => {
  const raised = core.stuckReduce(core.initialStuckState(), notification(true, 9)).state;
  const noSeq = core.stuckReduce(raised, { type: "notification", stuck: false, message: "recovered" });
  assert.strictEqual(noSeq.state.stuck, false);
  assert.strictEqual(noSeq.state.highWater, 9);
});

test("stuck: the ANSWER marker is per-request -- applied fresh, ignored when a notification overtook it", () => {
  const fresh = core.stuckReduce(core.initialStuckState(), {
    type: "answer", stuck: true, message: "refused while stuck", seqAtSend: 0,
  });
  assert.strictEqual(fresh.state.stuck, true);
  assert.strictEqual(fresh.effects.raised, true);

  // The request went out at mark 3; a {stuck:false, seq:4} landed while it
  // was in flight; its stuck refusal was decided before that clear.
  const cleared = { stuck: false, message: null, highWater: 4, running: true };
  const stale = core.stuckReduce(cleared, {
    type: "answer", stuck: true, message: "refused while stuck", seqAtSend: 3,
  });
  assert.strictEqual(stale.state.stuck, false);
  assert.strictEqual(stale.effects.raised, false);
});

test("stuck: an answer with no marker says nothing and never clears", () => {
  const raised = core.stuckReduce(core.initialStuckState(), notification(true, 1)).state;
  const ordinary = core.stuckReduce(raised, { type: "answer", stuck: false, seqAtSend: 1 });
  assert.strictEqual(ordinary.state.stuck, true);
  assert.deepStrictEqual(ordinary.effects.cleared, false);
});

test("stuck: a restart RESETS the mark, so the fresh server's seq 1 is honoured (DD-2)", () => {
  let state = core.stuckReduce(core.initialStuckState(), notification(true, 5)).state;
  assert.strictEqual(state.highWater, 5);

  const stopped = core.stuckReduce(state, { type: "clientState", from: "Running", to: "Stopped" });
  assert.strictEqual(stopped.state.running, false);
  assert.strictEqual(stopped.effects.offline, true);
  assert.strictEqual(stopped.state.stuck, true, "the last state is kept while the server is down");

  // vscode-languageclient passes through Starting on the way back.
  const starting = core.stuckReduce(stopped.state, { type: "clientState", from: "Stopped", to: "Starting" });
  assert.strictEqual(starting.state.running, false);

  const running = core.stuckReduce(starting.state, { type: "clientState", from: "Starting", to: "Running" });
  assert.strictEqual(running.state.highWater, 0);
  assert.strictEqual(running.state.stuck, false);
  assert.strictEqual(running.effects.online, true);
  assert.strictEqual(running.effects.rerender, true, "section 5: on Running, re-send the last render");
  assert.strictEqual(running.effects.cleared, true);

  const freshServer = core.stuckReduce(running.state, notification(true, 1));
  assert.strictEqual(freshServer.state.stuck, true, "a kept mark would have ignored this for the session's life");
});

test("stuck: the first Running of a session costs no render", () => {
  const first = core.stuckReduce(core.initialStuckState(), { type: "clientState", to: "Running" });
  assert.strictEqual(first.effects.rerender, false);
  assert.strictEqual(first.effects.online, false);
});

test("stuck: every generated message sequence leaves the state consistent", () => {
  // A small deterministic generator: enough shapes to interleave the two
  // edges, a restart, and stale answer markers, without a dependency.
  let seed = 20260920;
  const rnd = (n) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  const NAMES = ["notification", "answer", "clientState"];
  for (let run = 0; run < 500; run++) {
    let state = core.initialStuckState();
    let seq = 0;
    let lastMark = state.highWater;
    for (let step = 0; step < 24; step++) {
      const kind = NAMES[rnd(3)];
      let event;
      if (kind === "notification") {
        // Sometimes in order, sometimes behind, sometimes with no seq at all.
        const which = rnd(3);
        if (which === 0) seq += 1 + rnd(3);
        const carried = which === 2 ? undefined : which === 1 ? Math.max(0, seq - rnd(4)) : seq;
        event = { type: "notification", stuck: rnd(2) === 0, seq: carried, message: "m" + step };
      } else if (kind === "answer") {
        event = { type: "answer", stuck: rnd(2) === 0, message: "a" + step, seqAtSend: Math.max(0, state.highWater - rnd(2)) };
      } else {
        event = { type: "clientState", to: ["Running", "Stopped", "Starting"][rnd(3)] };
      }
      const r = core.stuckReduce(state, event);
      state = r.state;

      assert.strictEqual(typeof state.stuck, "boolean");
      assert.strictEqual(typeof state.running, "boolean");
      assert.strictEqual(typeof state.highWater, "number");
      assert.ok(state.highWater >= 0);
      if (state.stuck) {
        assert.ok(typeof state.message === "string" && state.message.length > 0,
                  "a stuck state always carries a message to show");
      } else {
        assert.strictEqual(state.message, null, "a cleared state shows no message");
      }
      // The mark only ever rises, except at a Running, which resets it to 0.
      if (event.type === "clientState" && event.to === "Running") {
        assert.strictEqual(state.highWater, 0);
      } else {
        assert.ok(state.highWater >= lastMark, "the high-water mark never falls except on a restart");
      }
      // An effect that asks for a render is always accompanied by a state
      // the extension can render in (never "stuck").
      if (r.effects.rerender) assert.strictEqual(state.stuck, false);
      lastMark = state.highWater;

      // Idempotence: applying the same event again changes nothing.
      const twice = core.stuckReduce(state, event);
      if (event.type === "notification" && typeof event.seq === "number") {
        assert.deepStrictEqual(twice.state, state);
      }
    }
  }
});

// ------------------------------------------------------------- settings

test("stuck: the final state is the highest-seq notification's, over generated sequences", () => {
  // AN INDEPENDENT ORACLE, which is why this generator emits only
  // notifications (every one with a numeric seq) and restarts: the expected
  // answer is then "the stuck of the highest seq seen since the last
  // restart", computed by scanning, not by re-implementing the reducer.
  let seed = 424242;
  const rnd = (n) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  for (let run = 0; run < 400; run++) {
    let state = core.initialStuckState();
    let since = [];
    for (let step = 0; step < 20; step++) {
      if (rnd(7) === 0) {
        state = core.stuckReduce(state, { type: "clientState", to: "Stopped" }).state;
        state = core.stuckReduce(state, { type: "clientState", to: "Running" }).state;
        since = [];
        continue;
      }
      const seq = 1 + rnd(9);
      const stuck = rnd(2) === 0;
      state = core.stuckReduce(state, { type: "notification", stuck, seq, message: "m" }).state;
      since.push({ seq, stuck });
    }
    let best = null;
    for (const n of since) if (best === null || n.seq > best.seq) best = n;
    // Ties: the reducer ignores a seq it has already seen, so the FIRST
    // notification at the highest seq is the one that decided.
    const expected = best === null ? false : since.filter((n) => n.seq === best.seq)[0].stuck;
    assert.strictEqual(state.stuck, expected,
                       "run " + run + " " + JSON.stringify(since) + " -> " + JSON.stringify(state));
  }
});

test("settings: both routes carry the same values in the two spellings the server reads", () => {
  const values = { fastMode: true, timeoutSeconds: 90, maxDocumentBytes: 2048 };
  const init = core.initializationOptions(values);
  const push = core.didChangeConfigurationParams(values);

  // `initializationOptions` is already the server's own object: no wrapper.
  assert.deepStrictEqual(init, { fastMode: true, preview: { timeoutSeconds: 90, maxDocumentBytes: 2048 } });
  // The push is read as `settings.ermine.preview.*` first.
  assert.deepStrictEqual(push, { settings: { ermine: { fastMode: true, preview: { timeoutSeconds: 90, maxDocumentBytes: 2048 } } } });
  assert.deepStrictEqual(init.preview, push.settings.ermine.preview);
});

test("settings: 0 is the off switch and is sent", () => {
  assert.deepStrictEqual(core.previewSettings({ timeoutSeconds: 0 }).preview, { timeoutSeconds: 0 });
});

test("settings: an out-of-range or ill-typed value is named and not sent", () => {
  const high = core.previewSettings({ timeoutSeconds: 3601 });
  assert.deepStrictEqual(high.preview, {});
  assert.match(high.problems[0], /outside 0\.\.3600/);

  const typed = core.previewSettings({ timeoutSeconds: "60" });
  assert.deepStrictEqual(typed.preview, {});
  assert.match(typed.problems[0], /not a string/);

  const small = core.previewSettings({ maxDocumentBytes: 10 });
  assert.deepStrictEqual(small.preview, {});
  assert.match(small.problems[0], /1KiB\.\.1TiB/);

  // Nothing configured sends nothing, and the server keeps its defaults.
  assert.deepStrictEqual(core.initializationOptions({ fastMode: false }), { fastMode: false });
});

test("maxHeap: the launcher's own two tests, refused here instead of on the server's stderr", () => {
  assert.deepStrictEqual(core.heapEnvironment("2g"), { env: { ERMINE_LSP_XMX: "2g" }, problem: null });
  assert.deepStrictEqual(core.heapEnvironment("512m").env, { ERMINE_LSP_XMX: "512m" });
  assert.deepStrictEqual(core.heapEnvironment("64m").env, { ERMINE_LSP_XMX: "64m" });
  assert.deepStrictEqual(core.heapEnvironment("65536k").env, { ERMINE_LSP_XMX: "65536k" });

  const spelling = core.heapEnvironment("lots");
  assert.deepStrictEqual(spelling.env, {});
  assert.match(spelling.problem, /not a JVM heap size/);

  for (const tooSmall of ["32m", "1m", "1k", "65535k"]) {
    const r = core.heapEnvironment(tooSmall);
    assert.deepStrictEqual(r.env, {}, tooSmall);
    assert.match(r.problem, /64m floor/, tooSmall);
  }
  assert.deepStrictEqual(core.heapEnvironment("0g").env, {}, "a zero heap is not a heap size");
  assert.deepStrictEqual(core.heapEnvironment(""), { env: {}, problem: null });
  assert.deepStrictEqual(core.heapEnvironment(undefined), { env: {}, problem: null });
});

// ------------------------------------------------------------------ tab

test("tab: a good answer shows the document, a refusal shows the whole answer", () => {
  const ok = core.tabContent({ ok: true, document: { widget: "table" }, generation: 1 });
  assert.strictEqual(ok, JSON.stringify({ widget: "table" }, null, 2));

  const bad = {
    ok: false, status: 400,
    message: "no value for the required key",
    path: "$.params.fromDay",
    generation: 2,
  };
  const shown = core.tabContent(bad);
  assert.match(shown, /\$\.params\.fromDay/, "the done-when's 400 must be visible in the tab");
  assert.match(shown, /"status": 400/);
});

test("tab: a document that cannot be printed does not throw", () => {
  const cyclic = { ok: true, document: {} };
  cyclic.document.self = cyclic.document;
  assert.match(core.tabContent(cyclic), /could not be printed/);
});

test("displaced renders are not shown, other errors are dressed as answers", () => {
  assert.strictEqual(core.isDisplaced({ code: core.REQUEST_CANCELLED }), true);
  assert.strictEqual(core.isDisplaced({ data: { code: core.REQUEST_CANCELLED } }), true);
  assert.strictEqual(core.isDisplaced({ code: -32603 }), false);
  assert.strictEqual(core.isDisplaced(undefined), false);

  const dressed = core.errorAnswer(new Error("the server went away"), 4);
  assert.strictEqual(dressed.ok, false);
  assert.strictEqual(dressed.generation, 4);
  assert.match(core.tabContent(dressed), /the server went away/);
});

test("pickLabel says what is picked without a module name", () => {
  assert.strictEqual(core.pickLabel(PICK), "Sales.report");
  assert.strictEqual(core.pickLabel(core.makePick("file:///w/X.e", "/w/X.e", "wide", null, [])), "X.e.wide");
  assert.strictEqual(core.pickLabel(undefined), "no report picked");
});

// ----------------------------------------------------- the picker and the bar

test("picker: the active editor's file comes first, the rest are sorted, and nothing repeats", () => {
  const files = [
    { fsPath: "/w/b/Sales.e", relative: "b/Sales.e" },
    { fsPath: "/w/a/Alpha.e", relative: "a/Alpha.e" },
    { fsPath: "/w/a/Sales.e", relative: "a/Sales.e" },
  ];
  const active = { fsPath: "/w/a/Sales.e", relative: "a/Sales.e" };
  const items = core.pickerItems(files, active);
  assert.deepStrictEqual(items.map((i) => i.fsPath),
    ["/w/a/Sales.e", "/w/a/Alpha.e", "/w/b/Sales.e"]);
  assert.deepStrictEqual(items[0], { label: "Sales.e", description: "a/Sales.e", fsPath: "/w/a/Sales.e" });
});

test("picker: an active file the workspace scan missed is still offered, and a non-.e one is not", () => {
  const outside = { fsPath: "/elsewhere/Report.e", relative: "/elsewhere/Report.e" };
  assert.strictEqual(core.pickerItems([], outside)[0].fsPath, "/elsewhere/Report.e");
  assert.deepStrictEqual(core.pickerItems([], { fsPath: "/w/notes.md", relative: "notes.md" }), []);
  assert.deepStrictEqual(core.pickerItems(undefined, undefined), []);
});

test("picker: the binding list always ends with the free-text entry", () => {
  const listed = core.bindingItems([{ binding: "report", type: "Query -> Node" }], undefined);
  assert.strictEqual(listed.length, 2);
  assert.deepStrictEqual(
    { label: listed[0].label, description: listed[0].description, binding: listed[0].binding },
    { label: "report", description: "Query -> Node", binding: "report" });
  assert.strictEqual(listed[1].label, core.TYPE_A_BINDING);
  assert.strictEqual(listed[1].binding, null);

  const failed = core.bindingItems(undefined, "cannot read Sales.e");
  assert.strictEqual(failed.length, 1);
  assert.match(failed[0].description, /cannot read Sales\.e/);
  assert.match(core.bindingItems([], undefined)[0].description, /no report-typed binding/);
});

test("status bar: NOT RUNNING BEATS STUCK, because a wedged server exits about two minutes later", () => {
  const both = core.statusBarState({ stuck: true, running: false, pick: PICK, message: "wedged" });
  assert.match(both.text, /preview offline/);
  assert.strictEqual(both.severity, "warning");

  const stuck = core.statusBarState({ stuck: true, running: true, pick: PICK, message: "wedged" });
  assert.match(stuck.text, /stuck/);
  assert.strictEqual(stuck.tooltip, "wedged");
  assert.strictEqual(stuck.severity, "warning");
});

test("status bar: hidden until there is something to say, then the pick, then the spinner", () => {
  assert.strictEqual(core.statusBarState({ running: true }).hidden, true);
  // Stuck with no pick is still worth showing: the server said so.
  assert.strictEqual(core.statusBarState({ running: true, stuck: true }).hidden, false);
  assert.strictEqual(core.statusBarState({ running: false }).hidden, false);

  const idle = core.statusBarState({ running: true, pick: PICK });
  assert.strictEqual(idle.text, "$(json) Ermine: Sales.report");
  assert.match(idle.tooltip, /\/w\/doc\/Sales\.e/);
  assert.match(idle.tooltip, /roots: \/w\/doc, \/w\/lib/);
  assert.strictEqual(idle.severity, "none");

  const rendering = core.statusBarState({ running: true, pick: PICK, rendering: true });
  assert.match(rendering.text, /sync~spin/);

  const noModule = core.statusBarState({
    running: true,
    pick: core.makePick("file:///w/X.e", "/w/X.e", "report", null, []),
  });
  assert.match(noModule.tooltip, /module name is unknown/);
  assert.match(noModule.tooltip, /\(none configured\)/);
});

test("roots: a path the platform refuses is named, not thrown", () => {
  // MEASURED while writing this: `path.resolve` does NOT throw on a NUL
  // byte on Node 24 -- it concatenates -- so the entry is refused by name
  // before it can reach the wire, and the try/catch behind it is for the
  // platforms where `path` does throw.
  const { roots, problems } = core.absoluteRoots(["/w/good", "bad\u0000name"], "/w");
  assert.deepStrictEqual(roots, [path.normalize("/w/good")]);
  assert.strictEqual(problems.length, 1);
  assert.match(problems[0], /is not a usable path: it contains a NUL byte/);
  assert.ok(problems[0].indexOf("\u0000") < 0, "no control character reaches the message");
});

// --------------------------------------------------- WP-22: the wedge guard
//
// The guard's DECISION is tested here; the guard's ARRIVAL is not, and
// cannot be: nobody has run this extension in VS Code. Everything about the
// editor -- that a crash really produces a `Stopped` edge, what a dismissed
// `showWarningMessage` resolves to, whether `workspaceState` survives what
// we think it survives -- is glue, and is listed as unobserved in
// tracker/JSON-WIDGET-PLAYGROUND.md's WP-22 row.

const OTHER = core.makePick("file:///w/doc/Other.e", "/w/doc/Other.e", "report", "Other", ["/w/doc", "/w/lib"]);

/** The mark the glue would hold after `Sales.report` wedged. */
function wedged(pick, reason, at) {
  const r = core.guardReduce(null, {
    type: "notification", stuck: true, applies: true,
    pick: pick || PICK, at: at === undefined ? 1000 : at,
  });
  if (reason === core.WEDGE_DIED_MID_RENDER) {
    return core.guardReduce(null, {
      type: "clientState", to: "Stopped", renderInFlight: true, pick: pick || PICK, at: at === undefined ? 1000 : at,
    }).mark;
  }
  return r.mark;
}

test("guard: the key is the pick's identity, and nothing else is in it", () => {
  assert.strictEqual(core.markKey(PICK), "file:///w/doc/Sales.e" + core.MARK_SEPARATOR + "report");
  assert.strictEqual(core.markKey(undefined), null);
  assert.strictEqual(core.markKey({}), null);

  // The same file, a different binding, is a different report.
  const wide = core.makePick(PICK.uri, PICK.fsPath, "wideReport", "Sales", PICK.roots);
  assert.notStrictEqual(core.markKey(wide), core.markKey(PICK));

  // The module name and the roots are NOT in the key: the roots are in the
  // VALUE so that changing them CLEARS rather than mints a second mark, and
  // the module is a cache the pick may learn later.
  const relearned = core.makePick(PICK.uri, PICK.fsPath, PICK.binding, null, ["/elsewhere"]);
  assert.strictEqual(core.markKey(relearned), core.markKey(PICK));
});

test("guard: fingerprints -- roots keep their order, params do not keep their key order", () => {
  assert.notStrictEqual(core.rootsFingerprint(["/a", "/b"]), core.rootsFingerprint(["/b", "/a"]),
                        "the roots are a loader chain, so the order is part of the value");
  assert.strictEqual(core.rootsFingerprint(["/a"]), core.rootsFingerprint(["/a"]));
  assert.strictEqual(core.rootsFingerprint(undefined), core.rootsFingerprint([]));

  assert.strictEqual(core.paramsFingerprint({ a: 1, b: [2, { d: 4, c: 3 }] }),
                     core.paramsFingerprint({ b: [2, { c: 3, d: 4 }], a: 1 }));
  assert.notStrictEqual(core.paramsFingerprint({ a: 1 }), core.paramsFingerprint({ a: 2 }));
  // WP-8's hook: no params exist yet, so every mark carries the same one.
  assert.strictEqual(core.paramsFingerprint(undefined), core.paramsFingerprint({}));
  assert.strictEqual(core.paramsFingerprint(null), core.paramsFingerprint({}));

  const cyclic = { a: 1 };
  cyclic.self = cyclic;
  assert.strictEqual(typeof core.paramsFingerprint(cyclic), "string",
                     "an unfingerprintable value must not throw inside a reducer");
});

test("guard: SET -- a stuck answer, a stuck notification, and a death mid-render", () => {
  const byAnswer = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PICK, at: 7 });
  assert.deepStrictEqual(byAnswer.mark, {
    key: core.markKey(PICK),
    reason: core.WEDGE_WATCHDOG,
    at: 7,
    rootsFingerprint: core.rootsFingerprint(PICK.roots),
    paramsFingerprint: core.paramsFingerprint({}),
  });
  assert.strictEqual(byAnswer.effects.set, true);
  assert.strictEqual(byAnswer.effects.reason, core.WEDGE_WATCHDOG);

  const byNotification = core.guardReduce(null, { type: "notification", stuck: true, applies: true, pick: PICK, at: 7 });
  assert.deepStrictEqual(byNotification.mark, byAnswer.mark, "either edge mints the same mark");

  const byDeath = core.guardReduce(null, {
    type: "clientState", to: "Stopped", renderInFlight: true, pick: PICK, at: 7,
  });
  assert.strictEqual(byDeath.mark.reason, core.WEDGE_DIED_MID_RENDER);
});

test("guard: SET does nothing without a pick, without a render in flight, or on an event the banner ignored", () => {
  const rows = [
    ["no pick, so nothing to mark", { type: "answer", stuck: true, applies: true, pick: undefined }],
    ["an ordinary answer says nothing", { type: "answer", stuck: false, applies: true, pick: PICK }],
    ["a STALE stuck refusal, decided before a clear", { type: "answer", stuck: true, applies: false, pick: PICK }],
    ["a stuck notification the seq rule ignored", { type: "notification", stuck: true, applies: false, pick: PICK }],
    ["a stop with nothing in flight", { type: "clientState", to: "Stopped", renderInFlight: false, pick: PICK }],
    ["the restart itself marks nothing", { type: "clientState", to: "Running", pick: PICK }],
    ["an automatic render is not consent and is not a wedge", { type: "render", explicit: false, pick: PICK }],
    ["an event this reducer does not know", { type: "whatever", pick: PICK }],
    ["no event at all", undefined],
  ];
  for (const [why, event] of rows) {
    assert.strictEqual(core.guardReduce(null, event).mark, null, why);
  }
});

test("guard: SET IS IDEMPOTENT for a key -- the two edges arrive in either order and leave ONE mark", () => {
  // MEASURED over the wire (checklist 2.9): the wedged job's ANSWER came
  // first in every run, and the notification is sent by another thread.
  const first = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PICK, at: 10 }).mark;
  const second = core.guardReduce(first, { type: "notification", stuck: true, applies: true, pick: PICK, at: 99 });
  assert.strictEqual(second.mark, first, "the first mark for a pick stands, `at` and all");
  assert.strictEqual(second.effects.set, false);

  // And the other order.
  const n = core.guardReduce(null, { type: "notification", stuck: true, applies: true, pick: PICK, at: 10 }).mark;
  assert.strictEqual(core.guardReduce(n, { type: "answer", stuck: true, applies: true, pick: PICK, at: 99 }).mark, n);

  // A death mid-render after the watchdog already marked it does not
  // re-word the reason: one incident, one mark.
  const died = core.guardReduce(n, { type: "clientState", to: "Stopped", renderInFlight: true, pick: PICK, at: 99 });
  assert.strictEqual(died.mark.reason, core.WEDGE_WATCHDOG);

  // A mark for ANOTHER pick is replaced rather than kept.
  const moved = core.guardReduce(n, { type: "notification", stuck: true, applies: true, pick: OTHER, at: 99 });
  assert.strictEqual(moved.mark.key, core.markKey(OTHER));
  assert.strictEqual(moved.effects.set, true);
});

test("guard: the server can die BEFORE the watchdog ever fires, and that is still a mark", () => {
  // MEASURED, tracker 2.5: WpBlow at -Xmx256m exited 3 at 8.6 s with no
  // watchdog fire at all. The stuck edge never happened; the mark must not
  // depend on it.
  let mark = null;
  mark = core.guardReduce(mark, { type: "clientState", to: "Stopped", renderInFlight: true, pick: PICK, at: 1 }).mark;
  assert.strictEqual(mark.reason, core.WEDGE_DIED_MID_RENDER);
  assert.strictEqual(core.shouldAutoRender(mark, PICK, core.TRIGGER_RESTART), false);
});

test("guard: CLEAR -- every row of the lifecycle that says the mark is gone", () => {
  const mark = wedged(PICK);
  const rows = [
    ["the wedged job came back: it was slow, not wedged (Q10)",
     { type: "notification", stuck: false, applies: true, pick: PICK }],
    ["the server invalidated the pick's module",
     { type: "invalidated", modules: ["Other", "Sales"], pick: PICK }],
    ["any .e save, the fallback a dead server cannot send",
     { type: "save", path: "/w/doc/Widgets.e" }],
    ["the pick changed",
     { type: "pick", pick: OTHER }],
    ["the roots changed",
     { type: "roots", pick: core.makePick(PICK.uri, PICK.fsPath, PICK.binding, PICK.module, ["/w/doc"]) }],
    ["the params changed (WP-8)",
     { type: "params", params: { fromDay: "2026-01-05" }, pick: PICK }],
    ["the user asked for this render, which IS the confirmation",
     { type: "render", explicit: true, pick: PICK }],
  ];
  for (const [why, event] of rows) {
    const r = core.guardReduce(mark, event);
    assert.strictEqual(r.mark, null, why);
    assert.strictEqual(r.effects.cleared, true, why);
    assert.ok(typeof r.effects.why === "string" && r.effects.why.length > 0, why);
  }
});

test("guard: the near misses that must NOT clear", () => {
  const mark = wedged(PICK);
  const rows = [
    ["a clear the seq rule ignored -- the banner still says stuck",
     { type: "notification", stuck: false, applies: false, pick: PICK }],
    ["an invalidated naming somebody else's module",
     { type: "invalidated", modules: ["Other"], pick: PICK }],
    ["an invalidated for a pick whose module the server never named",
     { type: "invalidated", modules: ["Sales"], pick: core.makePick(PICK.uri, PICK.fsPath, "report", null, []) }],
    ["a save of something that is not Ermine source",
     { type: "save", path: "/w/doc/notes.md" }],
    ["a save with no path at all",
     { type: "save" }],
    ["the roots did not actually change",
     { type: "roots", pick: PICK }],
    ["the params did not actually change",
     { type: "params", params: {}, pick: PICK }],
    ["an automatic render is not consent",
     { type: "render", explicit: false, pick: PICK }],
    ["the restart itself is not evidence of anything",
     { type: "clientState", to: "Running", pick: PICK }],
  ];
  for (const [why, event] of rows) {
    const r = core.guardReduce(mark, event);
    assert.strictEqual(r.mark, mark, why);
    assert.strictEqual(r.effects.cleared, false, why);
  }
});

test("guard: a stale {stuck:false} cannot clear a mark the BANNER is still showing", () => {
  // The one place the two reducers could have disagreed. `stuckReduce`
  // ignores a notification at or below the high-water mark; if the guard
  // did not, the banner would say stuck while the mark was gone, and the
  // next restart would re-render the report that wedged.
  const state = core.stuckReduce(core.initialStuckState(), notification(true, 4)).state;
  const stale = { type: "notification", stuck: false, seq: 3, message: "recovered" };
  assert.strictEqual(core.stuckEventApplies(state, stale), false);
  assert.strictEqual(core.stuckReduce(state, stale).state.stuck, true, "the banner ignores it");

  const mark = wedged(PICK);
  const guarded = core.guardReduce(mark, { type: "notification", stuck: false, applies: false, pick: PICK });
  assert.strictEqual(guarded.mark, mark, "so the guard must ignore it too");
});

test("guard: the two reducers accept EXACTLY the same events (the duplication is pinned)", () => {
  // A 32-bit xorshift rather than the LCG the older tests use: this one
  // asks for `% 8`, and the LCG's low bits do not have the period for it
  // (MEASURED while writing this: `% 8` came out 1994/6 over 2000 draws).
  let seed = 20260922 | 0;
  const rnd = (n) => {
    seed ^= seed << 13; seed |= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5; seed |= 0;
    return (seed >>> 0) % n;
  };
  let state = core.initialStuckState();
  let agreed = 0;
  // THE ADVERSARIAL SHAPES ARE IN THE DRAW, not in a separate test (the
  // WP-22 review found the one this generator used to miss): a `seq` of
  // NaN, of a non-number, absent entirely, EQUAL to the high-water mark,
  // and an answer whose `seqAtSend` predates a reset.
  const SEQS = [0, 1, 2, 3, 4, 5, 6, 7, NaN, Infinity, -Infinity, "3", null, true, undefined];
  for (let step = 0; step < 6000; step++) {
    const kind = rnd(4);
    let event;
    if (kind === 0) {
      event = { type: "notification", stuck: rnd(2) === 0, seq: rnd(8), message: "m" };
    } else if (kind === 1) {
      event = { type: "notification", stuck: rnd(2) === 0, message: "m" };   // an older server: no seq
    } else if (kind === 2) {
      // Equal to the mark as often as not, and every shape above.
      const seq = rnd(3) === 0 ? state.highWater : SEQS[rnd(SEQS.length)];
      event = { type: "notification", stuck: rnd(2) === 0, seq, message: "m" };
    } else {
      const at = rnd(3) === 0 ? state.highWater : SEQS[rnd(SEQS.length)];
      event = { type: "answer", stuck: rnd(2) === 0, message: "a", seqAtSend: at };
    }
    const applies = core.stuckEventApplies(state, event);
    const r = core.stuckReduce(state, event);
    // `stuckReduce` returns the SAME state object for an event it ignores
    // and a fresh one for an event it applies.
    assert.strictEqual(applies, r.state !== state,
                       "step " + step + " " + JSON.stringify(event) + " against " + JSON.stringify(state));
    agreed++;
    state = r.state;
    if (rnd(11) === 0) state = core.stuckReduce(state, { type: "clientState", to: "Running" }).state;
  }
  assert.strictEqual(agreed, 6000);
});

test("guard: restore -- kept for its own pick, discarded for anything else", () => {
  const mark = wedged(PICK);

  const kept = core.guardReduce(null, { type: "restore", mark, pick: PICK });
  assert.deepStrictEqual(kept.mark, mark, "a window reload keeps the mark");

  const foreign = core.guardReduce(null, { type: "restore", mark, pick: OTHER });
  assert.strictEqual(foreign.mark, null);
  assert.match(foreign.effects.why, /not this pick's/);

  const rootsMoved = core.guardReduce(null, {
    type: "restore", mark,
    pick: core.makePick(PICK.uri, PICK.fsPath, PICK.binding, PICK.module, ["/w/doc"]),
  });
  assert.strictEqual(rootsMoved.mark, null, "roots edited while the window was closed");

  for (const junk of [undefined, null, {}, "mark", { key: "k" },
                      { key: "k", reason: "made-up", at: 1, rootsFingerprint: "[]", paramsFingerprint: "{}" }]) {
    assert.strictEqual(core.guardReduce(null, { type: "restore", mark: junk, pick: PICK }).mark, null,
                       JSON.stringify(junk));
    assert.strictEqual(core.isMark(junk), false, JSON.stringify(junk));
  }
  assert.strictEqual(core.isMark(mark), true);
});

test("guard: a mark that is not a mark is not consulted and never survives a reduction", () => {
  for (const junk of [{}, { key: 1 }, "x", 7, true]) {
    assert.strictEqual(core.guardReduce(junk, { type: "render", explicit: false }).mark, null, JSON.stringify(junk));
    assert.strictEqual(core.shouldAutoRender(junk, PICK, core.TRIGGER_RESTART), true, JSON.stringify(junk));
  }
});

test("guard: the CONSULTATION -- only the restart trigger is ever refused", () => {
  const mark = wedged(PICK);
  assert.strictEqual(core.shouldAutoRender(mark, PICK, core.TRIGGER_RESTART), false,
                     "the one case the ticket exists for");
  assert.strictEqual(core.shouldAutoRender(null, PICK, core.TRIGGER_RESTART), true);

  // T3, T4, T5, T6 are each evidence of change or of recovery, and T1/T2
  // are consent. None of them consults the mark.
  for (const trigger of ["recovered", "invalidated", "file-event", "roots", "explicit", "answer", undefined]) {
    assert.strictEqual(core.shouldAutoRender(mark, PICK, trigger), true, String(trigger));
  }
});

test("guard: a mark whose key does not match the current pick is never consulted", () => {
  const mark = wedged(OTHER);
  assert.strictEqual(core.markMatches(mark, PICK), false);
  assert.strictEqual(core.shouldAutoRender(mark, PICK, core.TRIGGER_RESTART), true);
  assert.strictEqual(core.heldMessage(mark, PICK), null);
  assert.ok(core.statusBarState({ running: true, pick: PICK, mark }).text.indexOf("held") < 0);
  // And with no pick at all there is nothing to hold.
  assert.strictEqual(core.shouldAutoRender(mark, undefined, core.TRIGGER_RESTART), true);
  assert.strictEqual(core.statusBarState({ running: true, mark }).hidden, true);
});

test("guard: the held message names the report and why it is held", () => {
  const watchdog = core.heldMessage(wedged(PICK), PICK);
  assert.match(watchdog, /Sales\.report/);
  assert.match(watchdog, /watchdog/);
  assert.match(watchdog, /NOT re-rendered automatically/);

  const died = core.heldMessage(wedged(PICK, core.WEDGE_DIED_MID_RENDER), PICK);
  assert.match(died, /Sales\.report/);
  assert.match(died, /still rendering when the language server stopped/);
});

test("status bar: the precedence is offline > stuck > held > rendering > idle", () => {
  const mark = wedged(PICK);
  const view = (over) => core.statusBarState(Object.assign({ running: true, pick: PICK, mark }, over));

  // Every row below has the mark set, so each line is "what beats held".
  assert.match(view({ running: false, stuck: true, rendering: true }).text, /preview offline/);
  assert.match(view({ stuck: true, rendering: true, message: "wedged" }).text, /preview: stuck/);
  assert.match(view({ rendering: true }).text, /preview: held/);
  assert.match(view({ mark: null, rendering: true }).text, /sync~spin/);
  assert.strictEqual(view({ mark: null }).text, "$(json) Ermine: Sales.report");

  const held = view({});
  assert.strictEqual(held.severity, "warning");
  assert.match(held.tooltip, /Sales\.report/);
  assert.match(held.tooltip, /Render it anyway/);
  assert.strictEqual(held.hidden, false);
});

// ------------------------------------------------- the guard, over sequences
//
// A MODEL OF THE GLUE, and only of the glue's ORDER: which reducer sees an
// event first, what the glue computes between them, and where the one
// consultation sits. It is the same order as src/extension.js, written out
// once so that the properties below are about the pair of reducers rather
// than about either one alone.

function runGlue(events, pick, options) {
  const opts = options || {};
  let stuck = core.initialStuckState();
  let mark = null;
  // M1's latch, modelled as the glue holds it: the render that is out, or
  // null. It is released by a SETTLED result and -- in the real code, and
  // not in the mutant -- NOT by a transport rejection.
  let inFlight = null;
  const renders = [];
  const deaths = [];
  const record = (trigger, issued, markAtDecision) => {
    renders.push({ trigger, issued, mark: markAtDecision });
    if (issued) inFlight = { pick };
  };
  const stopped = () => {
    mark = core.guardReduce(mark, {
      type: "clientState", to: "Stopped",
      renderInFlight: inFlight !== null,
      pick: core.markPickFor(inFlight && inFlight.pick, pick),
      at: 1,
    }).mark;
    stuck = core.stuckReduce(stuck, { type: "clientState", to: "Stopped" }).state;
  };
  const rejection = (err) => {
    const before = mark;
    const hadInFlight = inFlight !== null;
    // THE MUTANT IS THE OLD CODE: the transport rejection cleared the
    // in-flight fact and marked nothing, so whichever of the two the
    // library delivered first decided whether the wedge was remembered.
    if (opts.mutantClearOnRejection) {
      inFlight = null;
      return { before, after: mark, hadInFlight };
    }
    if (inFlight && core.rejectionMeansServerGone(err)) {
      mark = core.guardReduce(mark, {
        type: "clientState", to: "Stopped", renderInFlight: true, pick: inFlight.pick, at: 1,
      }).mark;
    }
    inFlight = null;                                       // released AFTER marking
    return { before, after: mark, hadInFlight };
  };

  for (const e of events) {
    if (e.type === "notification" || e.type === "answer") {
      const applies = core.stuckEventApplies(stuck, e);
      mark = core.guardReduce(mark, {
        type: e.type, stuck: e.stuck === true, applies,
        pick: core.markPickFor(inFlight && inFlight.pick, pick), at: 1,
      }).mark;
      const r = core.stuckReduce(stuck, e);
      stuck = r.state;
      if (e.type === "answer") inFlight = null;            // a settled result
      if (r.effects.rerender) {
        const trigger = "recovered";
        record(trigger, core.shouldAutoRender(mark, pick, trigger), mark);
      }
    } else if (e.type === "serverDeath") {
      // THE RACE, BOTH WAYS ROUND. The library decides which of these two
      // the extension sees first and nothing here can observe it, so the
      // generator produces both and the property must hold for both.
      const inFlightAtDeath = inFlight !== null;
      let step;
      if (e.order === "rejection-first") { step = rejection(e.err); stopped(); }
      else { stopped(); step = rejection(e.err); }
      deaths.push({
        order: e.order, inFlightAtDeath, gone: core.rejectionMeansServerGone(e.err),
        rejection: step, mark,
      });
      const r = core.stuckReduce(stuck, { type: "clientState", to: "Running" });
      stuck = r.state;
      if (r.effects.rerender) {
        record(core.TRIGGER_RESTART, core.shouldAutoRender(mark, pick, core.TRIGGER_RESTART), mark);
      }
    } else if (e.type === "rejection") {
      // A REJECTION WITH NO `Stopped` EDGE AT ALL -- the shape the delta
      // review found in this server: a FATAL error kills the preview thread
      // and the JVM lives, so the render is answered -32603 and the
      // connection never drops (Preview.scala:207-208, :1263, :1277).
      // Nothing else in the client will ever mention it.
      const inFlightAtDeath = inFlight !== null;
      const step = rejection(e.err);
      deaths.push({
        order: "rejection-only", inFlightAtDeath, gone: core.rejectionMeansServerGone(e.err),
        rejection: step, mark,
      });
    } else if (e.type === "clientState") {
      if (e.to === "Stopped") stopped();
      else {
        const r = core.stuckReduce(stuck, { type: "clientState", to: e.to });
        stuck = r.state;
        if (r.effects.rerender) {
          record(core.TRIGGER_RESTART, core.shouldAutoRender(mark, pick, core.TRIGGER_RESTART), mark);
        }
      }
    } else {
      // save / invalidated / pick / roots / params / render
      mark = core.guardReduce(mark, Object.assign({ pick, at: 1 }, e)).mark;
      if (e.type === "render" && e.explicit === true) {
        record("explicit", core.shouldAutoRender(mark, pick, "explicit"), mark);
      }
    }
  }
  return { stuck, mark, renders, deaths };
}

const DEATH_ERRORS = [
  new Error("Connection got disposed"),                    // the shape we cannot name: GONE
  { code: -32097, message: "pending response rejected" },  // the library's own band: GONE
  { code: -32603, message: "the preview failed" },         // THIS SERVER's crashAnswer: GONE
  { code: -32800, message: "shutdown drain" },             // the peer's own answer: SETTLED
];

function guardEventStream(seed0, pick) {
  let seed = seed0 | 0;
  const rnd = (n) => {
    seed ^= seed << 13; seed |= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5; seed |= 0;
    return (seed >>> 0) % n;
  };
  const events = [];
  let seq = 0;
  for (let i = 0; i < 30; i++) {
    switch (rnd(9)) {
      case 0:
        if (rnd(3) === 0) seq += 1 + rnd(2);
        events.push({ type: "notification", stuck: rnd(2) === 0, seq: rnd(4) === 0 ? undefined : seq, message: "m" });
        break;
      case 1:
        events.push({ type: "answer", stuck: rnd(2) === 0, message: "a", seqAtSend: Math.max(0, seq - rnd(2)) });
        break;
      case 2:
        events.push({ type: "clientState", to: ["Running", "Stopped", "Starting"][rnd(3)] });
        break;
      case 3:
        events.push({ type: "save", path: rnd(2) === 0 ? "/w/doc/Sales.e" : "/w/doc/notes.md" });
        break;
      case 4:
        events.push({ type: "invalidated", modules: rnd(2) === 0 ? ["Sales"] : ["Other"] });
        break;
      case 5:
        events.push({ type: "render", explicit: rnd(2) === 0 });
        break;
      case 6:
        events.push({ type: "roots" });
        break;
      case 7:
        events.push({ type: "params", params: rnd(2) === 0 ? {} : { day: rnd(5) } });
        break;
      default:
        if (rnd(3) === 0) {
          // The preview thread dies and the JVM does not: a rejection and
          // nothing else.
          events.push({ type: "rejection", err: DEATH_ERRORS[rnd(DEATH_ERRORS.length)] });
        } else {
          events.push({
            type: "serverDeath",
            order: rnd(2) === 0 ? "rejection-first" : "stopped-first",
            err: DEATH_ERRORS[rnd(DEATH_ERRORS.length)],
          });
        }
        break;
    }
  }
  return events;
}

test("guard PROPERTY: over any event sequence, an automatic Running re-render is issued ONLY with a clear mark", () => {
  let restarts = 0;
  let suppressed = 0;
  for (let run = 0; run < 600; run++) {
    const events = guardEventStream(1000003 + run * 7919, PICK);
    const { renders } = runGlue(events, PICK);
    for (const r of renders) {
      if (r.trigger !== core.TRIGGER_RESTART) continue;
      restarts++;
      if (r.issued) {
        assert.strictEqual(core.markMatches(r.mark, PICK), false,
                           "run " + run + ": a restart re-rendered a pick that was marked as wedged");
      } else {
        suppressed++;
        assert.strictEqual(core.markMatches(r.mark, PICK), true,
                           "run " + run + ": a restart was held with no mark for this pick");
      }
    }
  }
  // The generator has to reach BOTH outcomes or the property is vacuous.
  // MEASURED on this seed: 219 restarts, of which 59 were held.
  assert.ok(restarts > 100, "restarts exercised: " + restarts);
  assert.ok(suppressed > 20, "suppressions exercised: " + suppressed);
});

test("guard PROPERTY: an explicit render is NEVER suppressed, whatever the mark", () => {
  let explicit = 0;
  for (let run = 0; run < 600; run++) {
    const events = guardEventStream(7700001 + run * 104729, PICK);
    const { renders, mark } = runGlue(events, PICK);
    for (const r of renders) {
      if (r.trigger === core.TRIGGER_RESTART) continue;
      explicit++;
      assert.strictEqual(r.issued, true, "run " + run + ": an explicit or recovery render was suppressed");
      if (r.trigger === "explicit") {
        assert.strictEqual(r.mark, null, "run " + run + ": asking for a render clears the mark");
      }
    }
    // Whatever happened, the mark is either null or this pick's: one mark,
    // never a map, never somebody else's.
    if (mark !== null) assert.strictEqual(mark.key, core.markKey(PICK));
  }
  // MEASURED on this seed: 1834 explicit and recovery renders.
  assert.ok(explicit > 200, "explicit/recovery renders exercised: " + explicit);
});

test("guard PROPERTY: a foreign mark is never consulted, over every ordered pair of four picks", () => {
  // The review caught the old title claiming "generated" over a hand-written
  // list. It is exhaustive over the pairs, which is the stronger statement
  // for four picks, and now it says so.
  const picks = [PICK, OTHER, core.makePick(PICK.uri, PICK.fsPath, "wideReport", "Sales", PICK.roots),
                 core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", null, [])];
  for (const owner of picks) {
    const mark = wedged(owner);
    for (const current of picks) {
      const matches = core.markKey(owner) === core.markKey(current);
      assert.strictEqual(core.markMatches(mark, current), matches);
      assert.strictEqual(core.shouldAutoRender(mark, current, core.TRIGGER_RESTART), !matches);
      assert.strictEqual(core.heldMessage(mark, current) === null, !matches);
      const bar = core.statusBarState({ running: true, pick: current, mark });
      assert.strictEqual(bar.text.indexOf("held") >= 0, matches);
    }
  }
});

// -------------------------------------------- WP-22 review: M1, M2, M3, N2

test("M1: a rejection is 'the server went away' unless a SPECIFICATION says the peer answered", () => {
  // Documented answers a peer composes -- JSON-RPC 2.0 §5.1 and the LSP's
  // own codes. The connection was alive, so nothing is marked.
  for (const code of core.SETTLED_BY_PEER_CODES) {
    assert.strictEqual(core.rejectionMeansServerGone({ code }), false, String(code));
    assert.strictEqual(core.rejectionMeansServerGone({ data: { code } }), false, "data." + code);
  }
  assert.ok(core.SETTLED_BY_PEER_CODES.indexOf(core.REQUEST_CANCELLED) >= 0,
            "-32800 is the preview queue's own answer (§2.5: displaced, cancelled, shutdown drain)");

  // EVERYTHING ELSE MARKS, including every shape we cannot name. This is
  // the asymmetry the review asked for: a spurious `held` costs one click,
  // a missed one re-renders a report that killed the last process.
  const gone = [
    new Error("Connection got disposed"),
    new Error("Pending response rejected since connection got disposed"),
    { code: -32099, message: "message write error" },
    { code: -32097, message: "pending response rejected" },
    { code: -32096, message: "connection inactive" },
    { code: 0 }, { code: 1 }, { code: -1 },
    { message: "no code at all" },
    { data: { code: -32097 } },
    "a string", 7, null, undefined, {},
  ];
  for (const err of gone) {
    assert.strictEqual(core.rejectionMeansServerGone(err), true, JSON.stringify(err) || String(err));
  }
});

test("M1: either ordering of (rejection, Stopped) leaves exactly one mark", () => {
  const death = (order) => {
    let mark = null;
    let inFlight = { pick: PICK };
    const reject = () => {
      if (inFlight && core.rejectionMeansServerGone(new Error("connection closed"))) {
        mark = core.guardReduce(mark, {
          type: "clientState", to: "Stopped", renderInFlight: true, pick: inFlight.pick, at: 5,
        }).mark;
      }
      inFlight = null;
    };
    const stop = () => {
      mark = core.guardReduce(mark, {
        type: "clientState", to: "Stopped",
        renderInFlight: inFlight !== null,
        pick: core.markPickFor(inFlight && inFlight.pick, PICK),
        at: 5,
      }).mark;
    };
    if (order === "rejection-first") { reject(); stop(); } else { stop(); reject(); }
    return mark;
  };
  const a = death("rejection-first");
  const b = death("stopped-first");
  assert.deepStrictEqual(a, b, "the race must not decide what is remembered");
  assert.strictEqual(a.reason, core.WEDGE_DIED_MID_RENDER);
  assert.strictEqual(core.shouldAutoRender(a, PICK, core.TRIGGER_RESTART), false);
});

test("M2: the held question's answer belongs to the report it asked about", () => {
  const asked = core.markKey(PICK);
  const mark = wedged(PICK);

  // The plain cases.
  assert.deepStrictEqual(core.promptAnswerApplies(asked, PICK, mark, "Render anyway"), { render: true, why: null });
  assert.strictEqual(core.promptAnswerApplies(asked, PICK, mark, "Not now").render, false);
  assert.strictEqual(core.promptAnswerApplies(asked, PICK, mark, undefined).render, false);
  assert.match(core.promptAnswerApplies(asked, PICK, mark, undefined).why, /dismissed/);
  // Only the exact string consents.
  for (const choice of ["render anyway", "Render Anyway", "", null, 0, { title: "Render anyway" }]) {
    assert.strictEqual(core.promptAnswerApplies(asked, PICK, mark, choice).render, false, JSON.stringify(choice));
  }

  // THE REVIEWER'S S11: the question about Sales is still on screen, the
  // user picks Ops.e (which wedges too), and then answers "Render anyway".
  // The consent was for Sales and must not be spent on Ops.
  const opsMark = wedged(OTHER);
  const s11 = core.promptAnswerApplies(asked, OTHER, opsMark, "Render anyway");
  assert.strictEqual(s11.render, false);
  assert.match(s11.why, /the pick changed/);

  // Cleared underneath the question: the user still asked, so it renders,
  // and the log says why.
  const clearedUnder = core.promptAnswerApplies(asked, PICK, null, "Render anyway");
  assert.strictEqual(clearedUnder.render, true);
  assert.match(clearedUnder.why, /already cleared/);

  // No pick at all when the question was shown.
  assert.strictEqual(core.promptAnswerApplies(null, PICK, mark, "Render anyway").render, false);
});

test("M3: a fingerprint is a DIGEST -- no part of what it fingerprints is in it", () => {
  const secret = "hunter2";
  const params = { day: "2026-09-20", db: "Server=prod;User Id=svc;Password=" + secret };
  const fp = core.paramsFingerprint(params);
  assert.match(fp, /^[0-9a-f]{64}$/, "sha256, hex");
  for (const piece of [secret, "Password", "Server=prod", "svc", "2026-09-20", "day", "db"]) {
    assert.ok(fp.indexOf(piece) < 0, "the fingerprint must not carry " + piece);
  }
  // The same for the roots, which `PICK_KEY` does not persist at all.
  const roots = core.rootsFingerprint(["/home/someone/secret-project", "/w/lib"]);
  assert.match(roots, /^[0-9a-f]{64}$/);
  for (const piece of ["home", "someone", "secret-project", "/w/lib"]) {
    assert.ok(roots.indexOf(piece) < 0, "the roots fingerprint must not carry " + piece);
  }
  // And the whole point of a fingerprint still holds after digesting.
  assert.strictEqual(core.paramsFingerprint({ a: 1, b: 2 }), core.paramsFingerprint({ b: 2, a: 1 }));
  assert.notStrictEqual(core.paramsFingerprint({ a: 1 }), core.paramsFingerprint({ a: 2 }));
  assert.notStrictEqual(core.rootsFingerprint(["/a", "/b"]), core.rootsFingerprint(["/b", "/a"]));
});

test("M3: an unfingerprintable value HOLDS rather than clears, and it does so deterministically", () => {
  // Two cyclic values answer the same sentinel digest, so `roots`/`params`
  // compare EQUAL and the mark is NOT cleared: the user is asked. That is
  // the safe direction, and the comment that used to claim the opposite
  // has been corrected.
  const a = {}; a.self = a;
  const b = { x: 1 }; b.self = b;
  assert.strictEqual(core.paramsFingerprint(a), core.paramsFingerprint(b));
  assert.match(core.paramsFingerprint(a), /^[0-9a-f]{64}$/);

  // A mark minted while the params could not be read, and then a params
  // event carrying a DIFFERENT unreadable value: the two compare equal, so
  // the mark stands and the next restart asks.
  const marked = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: PICK, at: 4, params: a,
  }).mark;
  const after = core.guardReduce(marked, { type: "params", params: b, pick: PICK });
  assert.strictEqual(after.mark, marked, "an unreadable value never auto-renders a wedge");
  assert.strictEqual(after.effects.cleared, false);
  // A value that CAN be read and differs still clears, as it must.
  assert.strictEqual(core.guardReduce(marked, { type: "params", params: { day: 1 }, pick: PICK }).mark, null);

  // Recorded rather than fixed: a Date has no own enumerable keys, so two
  // different Dates fingerprint alike. Unreachable from JSON params.
  assert.strictEqual(core.paramsFingerprint(new Date(0)), core.paramsFingerprint(new Date(99)));
});

test("N2: a wedge event names the render that is IN FLIGHT, and the current pick only as a fallback", () => {
  assert.strictEqual(core.markPickFor(PICK, OTHER), PICK);
  assert.strictEqual(core.markPickFor(null, OTHER), OTHER);
  assert.strictEqual(core.markPickFor(undefined, undefined), undefined);

  // The scenario: a render of Sales is out, the user picks Other, and the
  // watchdog's notification lands. The mark belongs to Sales.
  const mark = core.guardReduce(null, {
    type: "notification", stuck: true, applies: true,
    pick: core.markPickFor(PICK, OTHER), at: 3,
  }).mark;
  assert.strictEqual(mark.key, core.markKey(PICK));
  assert.strictEqual(core.shouldAutoRender(mark, OTHER, core.TRIGGER_RESTART), true,
                     "and Other, which did not wedge, is not held");
});

test("N4: a restored mark is reported as a restore, not as a fresh incident", () => {
  const mark = wedged(PICK);
  const restored = core.guardReduce(null, { type: "restore", mark, pick: PICK });
  assert.strictEqual(restored.effects.restored, true);
  assert.strictEqual(restored.effects.set, true);
  // A fresh wedge is not a restore.
  const fresh = core.guardReduce(null, { type: "notification", stuck: true, applies: true, pick: PICK, at: 1 });
  assert.strictEqual(fresh.effects.restored, false);
  // A discard says `cleared`, which is what tells the glue to remove the
  // stale entry from `workspaceState` (N3).
  const discarded = core.guardReduce(null, { type: "restore", mark, pick: OTHER });
  assert.strictEqual(discarded.effects.cleared, true);
  assert.strictEqual(discarded.effects.restored, false);
});

test("M1 PROPERTY: EVERY generated death is asserted -- a gone one marks, a settled one changes nothing", () => {
  // THE DELTA REVIEW'S FINDING ABOUT THIS PROPERTY ITSELF: it used to skip
  // every death whose rejection classified as settled (`if (!d.gone)
  // continue`), which is precisely how a wrong classification -- -32603 --
  // hid inside it. Now every death shape carries an assertion and NOTHING
  // is skipped, and the count is checked.
  let deaths = 0;
  let asserted = 0;
  let inFlightDeaths = 0;
  const byOrder = { "rejection-first": 0, "stopped-first": 0, "rejection-only": 0 };
  for (let run = 0; run < 600; run++) {
    const events = guardEventStream(31337 + run * 7919, PICK);
    const r = runGlue(events, PICK);
    for (const d of r.deaths) {
      deaths++;
      byOrder[d.order]++;
      if (d.gone) {
        if (d.inFlightAtDeath) {
          inFlightDeaths++;
          // The whole point: a render was out, the server went away under
          // it, and the next restart must ask rather than re-render.
          assert.ok(core.markMatches(d.mark, PICK),
                    "run " + run + " (" + d.order + "): a wedge that killed the server was not remembered");
          assert.ok(core.markMatches(d.rejection.after, PICK),
                    "run " + run + ": the rejection itself must mark, whatever else happens");
        } else {
          // Nothing was in flight, so this rejection has nothing to say.
          assert.strictEqual(d.rejection.after, d.rejection.before,
                             "run " + run + ": a rejection with nothing in flight must not mark");
        }
      } else {
        // A SETTLED shape: the peer composed this answer, so the rejection
        // itself marks nothing and leaves any earlier mark exactly as it
        // was. (The `Stopped` edge beside it may still mark, and that is
        // the Stopped edge's business, not this one's.)
        assert.strictEqual(d.rejection.after, d.rejection.before,
                           "run " + run + " (" + d.order + "): a peer's own answer must not mark");
      }
      asserted++;
    }
  }
  assert.strictEqual(asserted, deaths, "every death must be asserted; skipped = " + (deaths - asserted));
  assert.ok(byOrder["rejection-first"] > 50 && byOrder["stopped-first"] > 50 && byOrder["rejection-only"] > 50,
            "all three shapes exercised: " + JSON.stringify(byOrder));
  assert.ok(inFlightDeaths > 50, "deaths with a render in flight: " + inFlightDeaths);

  // THE MUTANT IS THE PRE-REVIEW CODE: the transport rejection cleared the
  // in-flight fact and marked nothing. Run the SAME sequences through it
  // and count how often the wedge is forgotten.
  let missed = 0;
  for (let run = 0; run < 600; run++) {
    const events = guardEventStream(31337 + run * 7919, PICK);
    const r = runGlue(events, PICK, { mutantClearOnRejection: true });
    for (const d of r.deaths) {
      if (d.inFlightAtDeath && d.gone && d.order !== "stopped-first" && !core.markMatches(d.mark, PICK)) missed++;
    }
  }
  assert.ok(missed > 0, "the mutant must be caught, or this property proves nothing");
  console.log("    M1: " + deaths + " deaths generated, " + asserted + " asserted, " + (deaths - asserted) +
              " skipped; " + inFlightDeaths + " with a render in flight; the old code forgot " + missed +
              " of them " + JSON.stringify(byOrder));
});

test("M1: -32603 is THIS SERVER's own crash answer, and it must mark", () => {
  // READ in the Scala, and the reason this code is not in the settled set:
  //   Rpc.scala:252            InternalError = -32603
  //   Preview.scala:207-208    crashAnswer = Left((InternalError, "the preview failed"))
  //   Preview.scala:1263       rescueInFlight() hands it to the render that was IN FLIGHT
  //   Preview.scala:1277       drainOnDeath() hands it to everything queued behind it
  //   Preview.scala:523, :614  every LATER render: "the preview thread is not running"
  //   Preview.scala:1086       isFatal = any `Error` -- a StackOverflowError out of a
  //                            runaway recursive evaluation kills the preview thread
  //                            and leaves the JVM alive, so there is NO connection drop
  // Without the mark the user's only remedy (Restart Language Server) would
  // re-render the pick straight back into the same overflow.
  const crash = { code: -32603, message: "the preview failed" };
  assert.strictEqual(core.rejectionMeansServerGone(crash), true);
  assert.ok(core.SETTLED_BY_PEER_CODES.indexOf(-32603) < 0, "-32603 is not a peer's ordinary answer here");

  const mark = core.guardReduce(null, {
    type: "clientState", to: "Stopped", renderInFlight: true, pick: PICK, at: 9,
  }).mark;
  assert.strictEqual(core.shouldAutoRender(mark, PICK, core.TRIGGER_RESTART), false,
                     "the restart the user reaches for must ask, not re-render");

  // The shutdown contract is why -32800 stays settled: Preview.scala:764-766
  // answers every QUEUED job -32800 while an IN-FLIGHT one "finishes and is
  // answered normally", so a dying render never comes back as -32800.
  assert.strictEqual(core.rejectionMeansServerGone({ code: -32800 }), false);
});
