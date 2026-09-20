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
