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
//
// ---------------------------------------------------------------------------
// THE RULE FOR EVERY MODEL IN THIS FILE, WRITTEN DOWN AFTER IT WAS BROKEN
// THREE TIMES:
//
//     A MODEL MUST MUTATE, OMIT AND CAPTURE EXACTLY WHAT THE GLUE MUTATES,
//     OMITS AND CAPTURES.  A model that supplies something `src/extension.js`
//     never produces is not a weaker test, it is a test of a different
//     program, and it reports GREEN on a defect that is live in the
//     extension.
//
// The three:
//   1. WP-22(c)'s M1 -- the model hand-wrote the restart reducer's events and
//      supplied `at` on exactly the events the glue OMITTED it from, so no
//      test could see that the floor's stretch was dead code in the shipped
//      extension. Fixed by making the model call `core.restartEvents.*`, the
//      same builders the glue calls, and by pinning that the glue has no
//      hand-written event left.
//   2. WP-22(c)'s delta review -- the model's `stopQuietly` always settled,
//      so the bound that a hung stop needs was untested until the model was
//      given the timed-out outcome the glue can really see.
//   3. WP-8 S2's M1 -- the model REPLACED the pick object to test a roots
//      change, while the glue MUTATES `picked.roots` in place. The arm under
//      test could not fire in the real extension at all, and the test passed
//      (MEASURED by the independent review: the glue's shape answered
//      `{"send":true}` where the model answered `roots-changed`). Fixed by
//      giving the model the glue's own mutators (`rootsChangeInPlace`,
//      `serverStopped`, `serverRestarted`, `tearDown`) and by moving the
//      capture into one pure snapshot both call (`core.renderAttempt`).
//
// So: when a model reaches for a module global the glue holds, it must reach
// for it the same way, at the same moment, and change it the same way. Where
// that cannot be checked by reading, the "glue pins" test at the bottom of
// this file reads `src/extension.js` and says so.
// ---------------------------------------------------------------------------

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
  //
  // WP-8 S2 CHANGED THE SENTINEL FOR "NO PARAMS" FROM `null` TO `undefined`,
  // AND THIS LINE IS THE ONLY TEST IT MOVED. The measured behaviour above is
  // unchanged -- "no params" is still `{}` on the wire -- but a params FILE
  // may legitimately hold `null` (a `Maybe`-rooted report; S1's skeleton
  // mints exactly that), and coercing it here would have turned a correct
  // file into a 400. `renderNow` passes what it read, and passes `{}` itself
  // when there is no file.
  assert.deepStrictEqual(core.renderParams(PICK, undefined, 7).params, {});
  assert.strictEqual(core.renderParams(PICK, null, 7).params, null);
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

test("roots: all six refusal texts, EXACTLY, with no setting name (WP-11 review N1)", () => {
  // The WP-11 review's R18b made ONE of these name ermine.preview.writersPath
  // and every other test stayed green: the older tests above match suffixes.
  // Each kind is pinned here as the whole string `absoluteRoots` returns when
  // no setting name is passed, which is how ermine.preview.roots calls it.
  assert.deepStrictEqual(core.absoluteRoots("reports", "/w").problems,
    ["ermine.preview.roots is an array of directory paths, not a string"]);
  assert.deepStrictEqual(core.absoluteRoots(["/a", 7], "/w").problems,
    ["ermine.preview.roots has an entry that is a number; each root is a directory path"]);
  assert.deepStrictEqual(core.absoluteRoots(["   "], "/w").problems,
    ["ermine.preview.roots has an empty entry; each root is a directory path"]);
  assert.deepStrictEqual(core.absoluteRoots(["bad\u0000name"], "/w").problems,
    ['ermine.preview.roots entry "bad?name" is not a usable path: it contains a NUL byte']);
  assert.deepStrictEqual(core.absoluteRoots(["reports"], undefined).problems,
    ['ermine.preview.roots entry "reports" is relative and there is no workspace folder to resolve it against']);
  // The sixth, `path` itself throwing, is not reachable on Node 24 with a
  // string (see the NUL-byte test above), so `path.isAbsolute` is made to
  // throw for this one call and put back.
  const real = path.isAbsolute;
  path.isAbsolute = () => { throw new Error("the platform refused it"); };
  let thrown;
  try {
    thrown = core.absoluteRoots(["/x"], "/w");
  } finally {
    path.isAbsolute = real;
  }
  assert.deepStrictEqual(thrown, { roots: [], problems: ['ermine.preview.roots entry "/x" is not a usable path: the platform refused it'] });
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
  // WP-8's hook. `undefined` means NOTHING WAS SENT and still maps to `{}`,
  // which is what every mark WP-22 and 0.1.7 wrote carries -- a mark
  // restored from `workspaceState` after an upgrade must keep meaning "no
  // params". `null` is a VALUE and is its own fingerprint since the S2
  // review's M3: a params file holding `null` is what a `Maybe`-rooted
  // report wants, and collapsing it into `{}` meant a report that wedged
  // with no file could not be un-held by writing one.
  assert.strictEqual(core.paramsFingerprint(undefined), core.paramsFingerprint({}));
  assert.notStrictEqual(core.paramsFingerprint(null), core.paramsFingerprint({}));
  assert.notStrictEqual(core.paramsFingerprint(null), core.paramsFingerprint(undefined));
  assert.strictEqual(core.paramsFingerprint(null), core.paramsFingerprint(null));

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

test("guard: the CONSULTATION -- an EVIDENCE trigger renders, anything else consults the mark", () => {
  // **THE POLICY CHANGED TWICE AND THIS TEST RECORDS BOTH CHANGES.**
  //
  // As written for WP-22 it said "only the restart trigger is ever refused",
  // and it pinned FAIL-OPEN for every other string including `undefined`.
  // WP-8 S2's delta re-review falsified both halves:
  //   D1 -- `roots` schedules on `affectsConfiguration` but its guard event
  //         clears only when the roots FINGERPRINT moved, so a setting
  //         edited to an equal list rendered a held report (MEASURED over
  //         579,194 generated sequences: 2,631 of 5,097 violations);
  //   D2 -- fail-open meant that FORGETTING to forward the trigger through
  //         the coalescer neutered both consultation sites for every
  //         automatic render, and that mutant survived all 210 tests.
  // So the rule is now: a trigger may be permitted only if it is DECLARED
  // and its guard event clears the mark WHENEVER it schedules.
  const mark = wedged(PICK);
  assert.strictEqual(core.shouldAutoRender(mark, PICK, core.TRIGGER_RESTART), false,
                     "the one case the ticket exists for");
  assert.strictEqual(core.shouldAutoRender(null, PICK, core.TRIGGER_RESTART), true);

  // The evidence triggers: each clears the mark before it schedules.
  // `TRIGGER_ANSWER` is NOT among them -- see the vocabulary test below.
  for (const trigger of [core.TRIGGER_RECOVERED, core.TRIGGER_INVALIDATED, core.TRIGGER_FILE_EVENT,
                         core.TRIGGER_EXPLICIT]) {
    assert.strictEqual(core.shouldAutoRender(mark, PICK, trigger), true, String(trigger));
  }
  // The unconfirmed ones, `roots` now among them.
  for (const trigger of core.UNCONFIRMED_TRIGGERS) {
    assert.strictEqual(core.shouldAutoRender(mark, PICK, trigger), false, String(trigger));
  }
  // AND ANYTHING UNDECLARED IS REFUSED AND NAMED.
  for (const trigger of [undefined, null, "", 0, "restarted", "params", "RESTART"]) {
    assert.strictEqual(core.shouldAutoRender(mark, PICK, trigger), false, String(trigger));
    assert.match(core.triggerProblem(trigger), /not one of the declared render triggers/);
  }
  for (const trigger of core.RENDER_TRIGGERS) assert.strictEqual(core.triggerProblem(trigger), null, trigger);
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
  // WP-22 (c). THE TIMER, IN THE MODEL, IN THE GLUE'S OWN ORDER: the same
  // `applies` goes to both reducers, every clientState edge is fed to the
  // restart reducer, and a FIRE does what `fireRestart` does -- attribute a
  // pick, mark it, then `restart(context)`, whose Stopped and Running edges
  // are the ones a crash produces. `opts.restart` is the setting in
  // seconds; absent, it is 0 and nothing can ever arm, so every property
  // written before (c) runs exactly as it did.
  let rs = core.initialRestartState(opts.restart);
  let now = 100000;
  let armAt = null;
  let armMs = 0;
  const fires = [];
  const arms = [];
  let fireOrder = "stopped-first";
  let fireErr = DEATH_ERRORS[0];
  const record = (trigger, issued, markAtDecision) => {
    renders.push({ trigger, issued, mark: markAtDecision });
    if (issued) inFlight = { pick };
  };
  const feedRestart = (ev) => {
    const r = core.restartReduce(rs, ev);
    rs = r.state;
    if (r.effects.arm) {
      armAt = now;
      armMs = r.effects.ms;
      arms.push({ at: now, seconds: r.effects.seconds, ms: r.effects.ms, serial: r.effects.serial });
    }
    if (r.effects.disarm) armAt = null;
    if (r.effects.fire) {
      armAt = null;
      doFire(r.effects);
    }
    return r.effects;
  };
  const stopped = () => {
    mark = core.guardReduce(mark, {
      type: "clientState", to: "Stopped",
      renderInFlight: inFlight !== null,
      pick: core.markPickFor(inFlight && inFlight.pick, pick),
      at: 1,
    }).mark;
    stuck = core.stuckReduce(stuck, { type: "clientState", to: "Stopped" }).state;
    feedRestart(core.restartEvents.clientState("Stopped"));
  };
  const running = () => {
    const r = core.stuckReduce(stuck, { type: "clientState", to: "Running" });
    stuck = r.state;
    feedRestart(core.restartEvents.clientState("Running"));
    if (r.effects.rerender) {
      record(core.TRIGGER_RESTART, core.shouldAutoRender(mark, pick, core.TRIGGER_RESTART), mark);
    }
  };
  // `fireRestart` (extension.js): attribute, MARK, then restart. The mutant
  // is the naive version -- restart and let the guard sort it out.
  const doFire = (fx) => {
    const attributed = core.markPickFor(inFlight && inFlight.pick, pick);
    const from = renders.length;
    // D3: every exit reports back, so only a restart that STARTED moves
    // the floor's memory.
    const refuse = (why) => {
      rs = core.restartReduce(rs, core.restartEvents.fireRefused(why, now)).state;
      fires.push({ fired: false, why, pick: attributed || null, markAtFire: mark, from });
    };
    if (!attributed) {
      refuse("unattributed");
      return;
    }
    if (!opts.mutantFireWithoutMark) {
      mark = core.guardReduce(mark, { type: "killedByUs", pick: attributed, at: now }).mark;
      if (!core.markMatches(mark, attributed)) {
        refuse("no mark");
        return;
      }
    }
    rs = core.restartReduce(rs, core.restartEvents.fired(now)).state;
    fires.push({ fired: true, why: fx.why, pick: attributed, markAtFire: mark, serial: fx.serial, at: now, from });
    // `restart(context)`: stop -- which rejects the render that is out, in
    // whichever order the library chooses -- and start again.
    if (fireOrder === "rejection-first") { rejection(fireErr); stopped(); }
    else { stopped(); rejection(fireErr); }
    running();
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
      // M1: THE MODEL CALLS THE SAME BUILDERS THE GLUE CALLS. The first
      // build hand-wrote these objects here and supplied `at` on exactly the
      // events extension.js omitted it from, which is why no test could see
      // that D2's stretch was dead code in the shipped extension.
      feedRestart(
        e.type === "answer"
          ? core.restartEvents.answer(e.stuck === true, applies, now)
          : core.restartEvents.notification(e.stuck === true, applies, now)
      );
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
      running();
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
      else if (e.to === "Running") running();
      else {
        // `Starting` moves `stuckReduce` not at all, and disarms the grace.
        feedRestart(core.restartEvents.clientState(e.to));
      }
    } else if (e.type === "tick") {
      // THE CLOCK, AND IT LIVES HERE RATHER THAN IN THE REDUCER. When it
      // passes the grace the expiry is delivered with the serial the arm
      // was minted with.
      now += e.ms;
      fireOrder = e.order || "stopped-first";
      fireErr = DEATH_ERRORS[(e.err || 0) % DEATH_ERRORS.length];
      if (rs.armed !== null && armAt !== null && now - armAt >= armMs) {
        feedRestart(core.restartEvents.expiry(rs.armed, now));
      }
    } else if (e.type === "staleExpiry") {
      // A TIMER FROM AN EARLIER INCIDENT, arriving late.
      feedRestart(core.restartEvents.expiry(e.serial, now));
    } else if (e.type === "setting") {
      feedRestart(core.restartEvents.setting(e.seconds, now));
    } else {
      // save / invalidated / pick / roots / params / render
      mark = core.guardReduce(mark, Object.assign({ pick, at: 1 }, e)).mark;
      if (e.type === "render" && e.explicit === true) {
        record("explicit", core.shouldAutoRender(mark, pick, "explicit"), mark);
      }
    }
  }
  return { stuck, mark, renders, deaths, fires, arms, restart: rs };
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

// ------------------------------------------- WP-22 (c): the restart timer
//
// The reducer holds no clock, so every row of its table is a plain value
// test, and the properties below are about the pair (guard, timer) in the
// glue's own order -- `runGlue` above, which now wires the timer in exactly
// as src/extension.js does.

function rstate(over) {
  return Object.assign(core.initialRestartState(20), over || {});
}

/** Armed for incident 1: stuck, running, a 20 s grace, serial 1. */
function armedState(over) {
  // `armedFor` is what THIS arm waits for, which is the setting unless the
  // floor stretched it (review D2); it is what the user is told.
  return rstate(Object.assign({ armed: 1, armedFor: 20, serial: 1, stuck: true }, over || {}));
}

test("restart setting: 0 is the default and the off switch, nonsense is NAMED and leaves it off, a big value is clamped", () => {
  assert.deepStrictEqual(core.restartGraceSetting(undefined), { seconds: 0, problems: [] });
  assert.deepStrictEqual(core.restartGraceSetting(null), { seconds: 0, problems: [] });
  assert.deepStrictEqual(core.restartGraceSetting(0), { seconds: 0, problems: [] });
  assert.deepStrictEqual(core.restartGraceSetting(20), { seconds: 20, problems: [] });
  assert.deepStrictEqual(core.restartGraceSetting(3600), { seconds: 3600, problems: [] });

  // NONSENSE FALLS BACK TO OFF, not to some grace nobody asked for.
  for (const bad of ["20", true, {}, [], NaN, Infinity, 2.5]) {
    const r = core.restartGraceSetting(bad);
    assert.strictEqual(r.seconds, 0, "a value nobody can parse must leave the restart off: " + String(bad));
    assert.strictEqual(r.problems.length, 1);
    assert.match(r.problems[0], /^ermine\.preview\.restartAfterStuckSeconds /);
    assert.match(r.problems[0], /stays OFF$/);
  }
  const negative = core.restartGraceSetting(-5);
  assert.strictEqual(negative.seconds, 0);
  assert.match(negative.problems[0], /not a length of time/);

  // ABOVE THE MAXIMUM IS CLAMPED, because "restart eventually" is
  // unambiguous and a grace over an hour is indistinguishable from one.
  const big = core.restartGraceSetting(100000);
  assert.strictEqual(big.seconds, core.RESTART_GRACE_MAX);
  assert.match(big.problems[0], /clamped to it$/);
});

test("restart: ARM -- the rising edge of the stuck state, once per incident, and never when it cannot act", () => {
  // The wedged ANSWER arrives first (MEASURED over the wire) and arms.
  const a = core.restartReduce(rstate(), { type: "answer", stuck: true, applies: true });
  assert.strictEqual(a.effects.arm, true);
  assert.strictEqual(a.effects.seconds, 20);
  assert.strictEqual(a.effects.serial, 1);
  assert.strictEqual(a.state.armed, 1);
  assert.strictEqual(a.state.stuck, true);

  // The notification that follows it is the SAME incident: no second arm.
  const b = core.restartReduce(a.state, { type: "notification", stuck: true, applies: true });
  assert.deepStrictEqual(b.state, a.state);
  assert.strictEqual(b.effects.arm, false);

  // The notification on its own arms just the same.
  const c = core.restartReduce(rstate(), { type: "notification", stuck: true, applies: true });
  assert.strictEqual(c.effects.arm, true);

  // A STALE EVENT ARMS NOTHING -- the same `applies` discipline as the guard.
  for (const e of [
    { type: "notification", stuck: true, applies: false },
    { type: "answer", stuck: true, applies: false },
    { type: "answer", stuck: false, applies: true },
  ]) {
    const r = core.restartReduce(rstate(), e);
    assert.strictEqual(r.effects.arm, false, JSON.stringify(e));
    assert.strictEqual(r.state.armed, null);
    assert.strictEqual(r.state.stuck, false);
  }

  // The setting at 0 arms nothing, and the state still tracks the wedge.
  const off = core.restartReduce(core.initialRestartState(0), { type: "notification", stuck: true, applies: true });
  assert.strictEqual(off.effects.arm, false);
  assert.strictEqual(off.state.stuck, true);
  assert.strictEqual(off.state.armed, null);

  // A wedge reported while the client is not running arms nothing: there is
  // nothing to restart.
  const down = core.restartReduce(rstate({ running: false }), { type: "answer", stuck: true, applies: true });
  assert.strictEqual(down.effects.arm, false);
  assert.strictEqual(down.state.stuck, true);
});

test("restart: DISARM -- the recovery, every way of leaving Running, the setting, and the teardown", () => {
  const rows = [
    [{ type: "notification", stuck: false, applies: true }, "came back"],
    [{ type: "clientState", to: "Stopped" }, "stopped"],
    [{ type: "clientState", to: "Starting" }, "left Running"],
    [{ type: "clientState", to: "Running" }, "running again"],
    [{ type: "setting", seconds: 0 }, "set to 0"],
    [{ type: "deactivate" }, "shutting down"],
  ];
  for (const [event, phrase] of rows) {
    const r = core.restartReduce(armedState(), event);
    assert.strictEqual(r.effects.disarm, true, JSON.stringify(event));
    assert.strictEqual(r.state.armed, null, JSON.stringify(event));
    assert.match(r.effects.why, new RegExp(phrase));
  }

  // Q10's recovery is the load-bearing one, and it also lowers the mirror.
  const back = core.restartReduce(armedState(), { type: "notification", stuck: false, applies: true });
  assert.strictEqual(back.state.stuck, false);

  // A STALE `{stuck:false}` -- one the banner ignores -- disarms nothing,
  // exactly as it clears no mark.
  const stale = core.restartReduce(armedState(), { type: "notification", stuck: false, applies: false });
  assert.deepStrictEqual(stale.state, armedState());
  assert.strictEqual(stale.effects.disarm, false);

  // Nothing armed, nothing to say.
  const quiet = core.restartReduce(rstate(), { type: "clientState", to: "Stopped" });
  assert.strictEqual(quiet.effects.disarm, false);
  assert.strictEqual(quiet.state.running, false);
});

test("restart: the SETTING -- 0 disarms, another value re-arms, and turning it ON mid-incident ARMS (review D1)", () => {
  // VS Code fires a configuration event for every `ermine.*` key, so the
  // same value again MUST be inert -- otherwise a grace is extended for as
  // long as the user keeps typing in settings.json.
  const same = core.restartReduce(armedState(), { type: "setting", seconds: 20 });
  assert.deepStrictEqual(same.state, armedState());
  assert.deepStrictEqual(same.effects, {
    arm: false, disarm: false, fire: false, refused: false, bug: null,
    seconds: 0, ms: 0, serial: 0, why: null,
  });

  const changed = core.restartReduce(armedState(), { type: "setting", seconds: 45 });
  assert.strictEqual(changed.effects.arm, true);
  assert.strictEqual(changed.effects.seconds, 45);
  assert.strictEqual(changed.state.armed, 2, "a re-arm mints a NEW serial, so the old timer is stale");
  assert.strictEqual(changed.state.seconds, 45);

  // REVIEW D1, AND THE FIRST BUILD HAD THIS THE OTHER WAY ROUND: turning
  // the setting on WHILE THE PREVIEW IS STUCK arms it there and then. That
  // is the likeliest moment anyone touches this setting, and there is no
  // second rising edge to save them (§4's rule (5) is withdrawn).
  const stuckNotArmed = rstate({ seconds: 0, stuck: true });
  const on = core.restartReduce(stuckNotArmed, { type: "setting", seconds: 30 });
  assert.strictEqual(on.effects.arm, true);
  assert.strictEqual(on.state.armed, 1);
  assert.strictEqual(on.state.seconds, 30);
  assert.strictEqual(on.state.armedFor, 30);
  assert.match(on.effects.why, /turned on while the preview was stuck/);

  // But only when there is something to restart: not stuck, or not running.
  const idle = core.restartReduce(rstate({ seconds: 0 }), { type: "setting", seconds: 30 });
  assert.strictEqual(idle.effects.arm, false);
  const offline = core.restartReduce(rstate({ seconds: 0, stuck: true, running: false }), { type: "setting", seconds: 30 });
  assert.strictEqual(offline.effects.arm, false);

  // N6: the reducer clamps too, not only the settings validator.
  const huge = core.restartReduce(rstate({ seconds: 0, stuck: true }), { type: "setting", seconds: 1e9 });
  assert.strictEqual(huge.state.seconds, core.RESTART_GRACE_MAX);
  assert.strictEqual(huge.effects.ms, core.RESTART_GRACE_MAX * 1000);
  assert.strictEqual(core.initialRestartState(1e9).seconds, core.RESTART_GRACE_MAX);

  // Nonsense that reaches the reducer anyway is 0 = off.
  const junk = core.restartReduce(armedState(), { type: "setting", seconds: "45" });
  assert.strictEqual(junk.state.seconds, 0);
  assert.strictEqual(junk.effects.disarm, true);
});

test("restart: FIRE -- only for the live serial, only while stuck and running, and the floor DEFERS rather than strands", () => {
  const armed = armedState();
  const fired = core.restartReduce(armed, { type: "expiry", serial: 1, at: 1000000 });
  assert.strictEqual(fired.effects.fire, true);
  assert.strictEqual(fired.effects.seconds, 20);
  assert.strictEqual(fired.state.armed, null);
  // D3: the FIRE does not move the floor's memory. The glue does, with
  // `fired`, and only when the restart really started.
  assert.strictEqual(fired.state.lastFireAt, null);
  const started = core.restartReduce(fired.state, core.restartEvents.fired(1000000));
  assert.strictEqual(started.state.lastFireAt, 1000000);
  // Delta review (d): `fired` MINTS a one-shot token; the Stopped -> Running
  // it causes is what spends it.
  assert.strictEqual(started.state.restartPending, true);
  assert.strictEqual(started.state.restartedByUs, false);
  const refused = core.restartReduce(fired.state, { type: "fireRefused", why: "unattributed", at: 1000000 });
  assert.strictEqual(refused.state.lastFireAt, null, "a refused fire must not consume the floor");
  assert.strictEqual(refused.effects.refused, true);
  assert.strictEqual(core.restartProblem(refused.state), "unattributed");
  assert.match(fired.effects.why, /stuck for 20 s/);

  // A STALE TIMER CANNOT FIRE, AND MUST NOT DISARM THE LIVE ONE.
  for (const serial of [0, 2, undefined, null, "1"]) {
    const r = core.restartReduce(armed, { type: "expiry", serial, at: 1000000 });
    assert.strictEqual(r.effects.fire, false, "serial " + String(serial));
    assert.deepStrictEqual(r.state, armed, "a stale timer left the live arm alone");
    assert.match(r.effects.why, /earlier incident/);
  }

  // Nothing armed: nothing happens, and the state is untouched.
  const none = core.restartReduce(rstate({ stuck: true }), { type: "expiry", serial: 1, at: 1000000 });
  assert.strictEqual(none.effects.fire, false);
  assert.match(none.effects.why, /already been disarmed/);

  // Defence in depth: each of these should have disarmed already.
  const notStuck = core.restartReduce(armedState({ stuck: false }), { type: "expiry", serial: 1, at: 1000000 });
  assert.strictEqual(notStuck.effects.fire, false);
  assert.strictEqual(notStuck.effects.disarm, true);
  const notRunning = core.restartReduce(armedState({ running: false }), { type: "expiry", serial: 1, at: 1000000 });
  assert.strictEqual(notRunning.effects.fire, false);
  const noSetting = core.restartReduce(armedState({ seconds: 0 }), { type: "expiry", serial: 1, at: 1000000 });
  assert.strictEqual(noSetting.effects.fire, false);

  // THE FLOOR, and it is checked with the clock the GLUE passes: an expiry
  // that carries none cannot fire at all, so the floor is never
  // unfalsifiable.
  const noClock = core.restartReduce(armedState(), { type: "expiry", serial: 1 });
  assert.strictEqual(noClock.effects.fire, false);
  assert.match(noClock.effects.why, /no clock/);

  // REVIEW D2: INSIDE THE FLOOR THE TIMER IS RE-ARMED FOR WHAT IS LEFT,
  // never disarmed -- a disarm here stranded the incident for the rest of
  // the session, because no second rising edge comes to re-arm it.
  const soon = core.restartReduce(armedState({ lastFireAt: 1000000 }), {
    type: "expiry", serial: 1, at: 1000000 + core.RESTART_FLOOR_MS - 5000,
  });
  assert.strictEqual(soon.effects.fire, false);
  assert.strictEqual(soon.effects.disarm, false);
  assert.strictEqual(soon.effects.arm, true);
  assert.strictEqual(soon.effects.ms, 5000);
  assert.strictEqual(soon.effects.seconds, 5);
  assert.strictEqual(soon.state.armed, 2, "the re-arm mints a new serial");
  assert.strictEqual(soon.state.armedFor, 5);
  assert.match(soon.effects.why, /waits another 5 s/);

  // AND THE ARM ITSELF ALREADY KNEW: a grace armed inside the floor waits
  // for the floor, so the number the user is TOLD is the real one and the
  // expiry above is only a backstop.
  const withinFloor = core.restartReduce(
    rstate({ lastFireAt: 1000000, running: true }),
    { type: "notification", stuck: true, applies: true, at: 1000000 + 10000 }
  );
  assert.strictEqual(withinFloor.effects.arm, true);
  assert.strictEqual(withinFloor.effects.ms, 20000, "20 s of floor left beats the 20 s setting only when larger");
  const tightFloor = core.restartReduce(
    rstate({ seconds: 5, lastFireAt: 1000000 }),
    { type: "notification", stuck: true, applies: true, at: 1000000 + 5000 }
  );
  assert.strictEqual(tightFloor.effects.ms, 25000, "the floor stretches a 5 s grace to 25 s");
  assert.strictEqual(tightFloor.effects.seconds, 25, "and the user is told 25, not 5");
  assert.strictEqual(core.restartArmedSeconds(tightFloor.state), 25);

  const later = core.restartReduce(armedState({ lastFireAt: 1000000 }), {
    type: "expiry", serial: 1, at: 1000000 + core.RESTART_FLOOR_MS,
  });
  assert.strictEqual(later.effects.fire, true);

  // A CLOCK THAT MOVED BACKWARDS refuses, which is the safe direction, and
  // re-arms rather than stranding.
  const backwards = core.restartReduce(armedState({ lastFireAt: 2000000 }), {
    type: "expiry", serial: 1, at: 1000000,
  });
  assert.strictEqual(backwards.effects.fire, false);
  assert.strictEqual(backwards.effects.arm, true);
});

test("restart: an event the reducer does not know, and no event at all, change nothing", () => {
  const armed = armedState();
  for (const e of [undefined, null, 42, "expiry", {}, { type: "save", path: "/w/doc/Sales.e" }]) {
    const r = core.restartReduce(armed, e);
    assert.deepStrictEqual(r.state, armed);
    assert.strictEqual(r.effects.fire, false);
    assert.strictEqual(r.effects.arm, false);
    assert.strictEqual(r.effects.disarm, false);
  }
  // A pick change is NOT an event here, and that is the decision: the wedge
  // is the SERVER's state, not the pick's. The glue never sends one.
  assert.deepStrictEqual(core.restartReduce(armed, { type: "pick", pick: OTHER }).state, armed);
});

test("restart: the UX -- the armed grace is on the notification and on the tooltip, and says how to stop it", () => {
  assert.strictEqual(core.restartArmedSeconds(core.initialRestartState(20)), 0);
  assert.strictEqual(core.restartArmedSeconds(armedState()), 20);
  assert.strictEqual(core.restartNotice(0), null);
  assert.strictEqual(core.restartNotice(undefined), null);

  const notice = core.restartNotice(20);
  assert.match(notice, /restarted automatically in 20 s/);
  assert.match(notice, /ermine\.preview\.restartAfterStuckSeconds to 0/);
  // N1: the manual restart the server's own message asks for is OPTIONAL
  // while a grace is armed, and the notice says so.
  assert.match(notice, /do not need to do that by hand/);

  assert.strictEqual(
    core.stuckNotificationText("evaluation did not finish", 0),
    "Ermine: evaluation did not finish"
  );
  // N1: THE JOIN IS PUNCTUATED. The server's own message ends
  // `... (ermine.restartServer)` with no terminator, and a bare space made
  // the two into one run-on sentence.
  const server = 'evaluation did not finish after 5s; the preview is stuck. It recovers by itself if that ' +
    'evaluation ever finishes; if it does not, restart the language server -- run ' +
    '"Ermine: Restart Language Server" (ermine.restartServer)';
  assert.strictEqual(core.stuckNotificationText(server, 20), "Ermine: " + server + ". " + notice);
  // A message that already ends in a terminator is not given a second one.
  assert.strictEqual(core.stuckNotificationText("it is stuck.", 20), "Ermine: it is stuck. " + notice);

  const armedBar = core.statusBarState({ running: true, stuck: true, message: "the preview is stuck", pick: PICK, restartIn: 20 });
  assert.match(armedBar.tooltip, /restarted automatically in 20 s/);
  const quietBar = core.statusBarState({ running: true, stuck: true, message: "the preview is stuck", pick: PICK, restartIn: 0 });
  assert.strictEqual(quietBar.tooltip, "the preview is stuck");
  // The text never changes: "stuck" is what the user acts on.
  assert.strictEqual(armedBar.text, quietBar.text);

  // D3: a REFUSAL reaches the tooltip too -- it is not a log line.
  const refusedBar = core.statusBarState({
    running: true, stuck: true, message: "the preview is stuck", pick: PICK,
    restartIn: 0, restartProblem: "nothing is picked",
  });
  assert.match(refusedBar.tooltip, /The automatic restart did not happen: nothing is picked\./);
});

test("guard: killed-by-us is a mark, is idempotent, and NEVER overwrites a truer reason", () => {
  const fresh = core.guardReduce(null, { type: "killedByUs", pick: PICK, at: 7 });
  assert.strictEqual(fresh.effects.set, true);
  assert.strictEqual(fresh.effects.reason, core.WEDGE_KILLED_BY_US);
  assert.strictEqual(fresh.mark.key, core.markKey(PICK));
  assert.strictEqual(core.isMark(fresh.mark), true);
  assert.strictEqual(core.markMatches(fresh.mark, PICK), true);

  // The watchdog got there first: its reason and its `at` stand.
  const watchdog = wedged(PICK, core.WEDGE_WATCHDOG, 3);
  const kept = core.guardReduce(watchdog, { type: "killedByUs", pick: PICK, at: 9 });
  assert.strictEqual(kept.mark, watchdog);
  assert.strictEqual(kept.effects.set, false);

  // A mark for ANOTHER pick is replaced, exactly as every other SET does.
  const foreign = core.guardReduce(wedged(OTHER), { type: "killedByUs", pick: PICK, at: 9 });
  assert.strictEqual(foreign.mark.key, core.markKey(PICK));

  // Nothing picked: nothing to mark -- and the glue refuses to restart.
  assert.strictEqual(core.guardReduce(null, { type: "killedByUs", pick: undefined, at: 9 }).mark, null);

  // The user-facing text has its own branch.
  assert.match(core.heldMessage(fresh.mark, PICK), /the language server was restarted to clear it/);
  assert.match(
    core.statusBarState({ running: true, pick: PICK, mark: fresh.mark }).tooltip,
    /the language server was restarted to clear it/
  );
});

// ------------------------------------------- WP-22 (c), over sequences

/**
 * The stage 1 generator, plus the events letter (c) adds: a CLOCK (`tick`,
 * which delivers the expiry when the grace has passed), a timer left over
 * from an earlier incident (`staleExpiry`), and the setting changing under
 * everything.
 */
function restartEventStream(seed0, opts) {
  const o = opts || {};
  let seed = seed0 | 0;
  const rnd = (n) => {
    seed ^= seed << 13; seed |= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5; seed |= 0;
    return (seed >>> 0) % n;
  };
  const events = [];
  let seq = 0;
  for (let i = 0; i < 40; i++) {
    switch (rnd(11)) {
      case 0:
        if (rnd(3) === 0) seq += 1 + rnd(2);
        events.push({ type: "notification", stuck: rnd(3) > 0, seq: rnd(5) === 0 ? undefined : seq, message: "m" });
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
      case 7:
        events.push({
          type: "tick",
          ms: [1000, 5000, 21000, 60000][rnd(4)],
          order: rnd(2) === 0 ? "rejection-first" : "stopped-first",
          err: rnd(4),
        });
        break;
      case 8:
        events.push({ type: "staleExpiry", serial: rnd(4) });
        break;
      case 9:
        events.push({ type: "setting", seconds: o.alwaysOff ? 0 : [0, 5, 20][rnd(3)] });
        break;
      default:
        if (rnd(3) === 0) events.push({ type: "rejection", err: DEATH_ERRORS[rnd(DEATH_ERRORS.length)] });
        else {
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

test("restart PROPERTY: a FIRE is only ever produced while stuck and Running, for the LIVE serial, with a non-zero setting", () => {
  // This one drives the reducer alone, so the invariant can be read off the
  // state the fire was decided from.
  let fires = 0;
  let stale = 0;
  let floored = 0;
  let stretched = 0;
  for (let run = 0; run < 500; run++) {
    const events = restartEventStream(500009 + run * 7919);
    let state = core.initialRestartState(20);
    let now = 100000;
    let armAt = null;
    let armMs = 0;
    for (const e of events) {
      let event = null;
      if (e.type === "notification" || e.type === "answer") {
        // `applies` is DRAWN here rather than computed, which is the
        // stronger choice for this property: the invariant must hold for
        // any acceptance the glue could hand over.
        const applies = e.type === "answer" ? e.stuck === true : e.seq === undefined || e.seq % 3 !== 0;
        event = { type: e.type, stuck: e.stuck === true, applies, at: now };
      } else if (e.type === "clientState") {
        event = { type: e.type, to: e.to };
      } else if (e.type === "setting") {
        event = { type: e.type, seconds: e.seconds, at: now };
      } else if (e.type === "tick") {
        now += e.ms;
        if (state.armed !== null && armAt !== null && now - armAt >= armMs) {
          event = { type: "expiry", serial: state.armed, at: now };
        }
      } else if (e.type === "staleExpiry") {
        event = { type: "expiry", serial: e.serial, at: now };
        if (e.serial !== state.armed) stale++;
      }
      if (!event) continue;
      const before = state;
      const r = core.restartReduce(before, event);
      if (r.effects.arm && r.effects.ms > before.seconds * 1000) stretched++;
      if (r.effects.fire) {
        fires++;
        assert.strictEqual(before.stuck, true, "run " + run + ": a fire while the preview was not stuck");
        assert.strictEqual(before.running, true, "run " + run + ": a fire while the client was not running");
        assert.ok(before.seconds > 0, "run " + run + ": a fire with the setting at 0");
        assert.strictEqual(event.serial, before.armed, "run " + run + ": a fire for a serial that was not the live arm");
        assert.ok(
          before.lastFireAt === null || event.at - before.lastFireAt >= core.RESTART_FLOOR_MS,
          "run " + run + ": two fires inside the floor"
        );
      }
      if (!r.effects.fire && event.type === "expiry" && r.effects.why && /no two may be closer/.test(r.effects.why)) floored++;
      if (r.effects.arm) { armAt = now; armMs = r.effects.ms; }
      if (r.effects.disarm) armAt = null;
      state = r.state;
      // The glue's answer, which is the ONLY thing that moves the floor's
      // memory (review D3). Modelled as the ordinary case: it started.
      if (r.effects.fire) {
        armAt = null;
        state = core.restartReduce(state, { type: "fired", at: now }).state;
      }
    }
  }
  // MEASURED on this seed: the generator has to reach all three or the
  // property says nothing.
  assert.ok(fires > 100, "fires exercised: " + fires);
  assert.ok(stale > 100, "stale timers exercised: " + stale);
  // THE FLOOR IS NOW REACHED AT ARM TIME, which is the point of review D2:
  // the grace stretches itself, so the number the user is told is the one
  // the restart happens at, and the expiry-time check is only a backstop.
  assert.ok(stretched > 50, "arms stretched by the floor: " + stretched);
  console.log("    [counts] fires " + fires + ", stale timers " + stale +
              ", arms stretched by the floor " + stretched + ", expiry-time deferrals " + floored);
});

test("restart PROPERTY: with the setting at 0 -- the DEFAULT -- no fire is ever produced", () => {
  let expiries = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(31337 + run * 104729, { alwaysOff: true });
    const out = runGlue(events, PICK, { restart: 0 });
    assert.deepStrictEqual(out.fires, [], "run " + run + ": something fired with the feature off");
    assert.strictEqual(out.restart.armed, null);
    for (const e of events) if (e.type === "staleExpiry") expiries++;
  }
  assert.ok(expiries > 100, "expiries offered to a disarmed timer: " + expiries);
  console.log("    [counts] expiries offered with the feature off: " + expiries);
});

test("restart PROPERTY: EVERY fire is preceded by a mark for the pick it restarts (and the mutant is caught)", () => {
  let fired = 0;
  let refused = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(90210 + run * 7919);
    const { fires } = runGlue(events, PICK, { restart: 20 });
    for (const f of fires) {
      if (!f.fired) { refused++; continue; }
      fired++;
      assert.strictEqual(core.markMatches(f.markAtFire, f.pick), true,
                         "run " + run + ": the server was restarted with no mark for " + core.pickLabel(f.pick));
    }
  }
  assert.ok(fired > 50, "fires exercised: " + fired);
  console.log("    [counts] fires " + fired + ", refused " + refused);

  // THE MUTANT: `fireRestart` without the `killedByUs` SET -- restart and
  // let the guard sort it out. This is the version that reopens Q17's loop.
  let unmarked = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(90210 + run * 7919);
    const { fires } = runGlue(events, PICK, { restart: 20, mutantFireWithoutMark: true });
    for (const f of fires) if (f.fired && !core.markMatches(f.markAtFire, f.pick)) unmarked++;
  }
  assert.ok(unmarked > 0, "the mutant must fire without a mark at least once: " + unmarked);
  // MEASURED, and printed so the count is evidence rather than a claim.
  console.log("    [mutant] fires with no mark, over the same 400 sequences: " + unmarked +
              " (real code: 0; refusals: " + refused + ")");
});

test("restart PROPERTY: after a fire, the Stopped -> Running it causes NEVER auto-renders", () => {
  // THE PROPERTY THAT MATTERS: stage 1's guard is what makes stage 2 safe,
  // and this is the composition of the two.
  let checked = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(20260921 + run * 104729);
    const { fires, renders } = runGlue(events, PICK, { restart: 20 });
    for (const f of fires) {
      if (!f.fired) continue;
      for (let i = f.from; i < renders.length; i++) {
        if (renders[i].trigger !== core.TRIGGER_RESTART) continue;
        checked++;
        assert.strictEqual(renders[i].issued, false,
                           "run " + run + ": the restart we caused re-rendered the report that wedged");
        break;                                   // only the restart's own edge
      }
    }
  }
  assert.ok(checked > 50, "restart re-renders checked after a fire: " + checked);
  console.log("    [counts] restart re-renders checked after a fire: " + checked);

  // THE SAME SEQUENCES THROUGH THE MUTANT: without the mark, the restart we
  // caused re-renders the wedge -- the loop, by our own hand.
  let reopened = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(20260921 + run * 104729);
    const { fires, renders } = runGlue(events, PICK, { restart: 20, mutantFireWithoutMark: true });
    for (const f of fires) {
      if (!f.fired) continue;
      for (let i = f.from; i < renders.length; i++) {
        if (renders[i].trigger !== core.TRIGGER_RESTART) continue;
        if (renders[i].issued) reopened++;
        break;
      }
    }
  }
  assert.ok(reopened > 0, "the mutant must reopen the loop at least once: " + reopened);
  console.log("    [mutant] restarts that re-rendered the wedge: " + reopened + " (real code: 0)");
});

test("restart PROPERTY: the stale-serial rule is load-bearing -- without it a dead incident restarts the server", () => {
  // THE SECOND MUTANT, and it is in the REDUCER rather than in the glue: an
  // expiry whose serial is not the live arm's is treated as if it were.
  // It is run as a PER-STEP DIFFERENTIAL against the real reducer -- both
  // are asked about the same state, and the real answer is the one that
  // advances -- so the two can never drift apart and the count is exactly
  // "decisions the rule changed".
  const mutant = (state, event) => {
    if (event && event.type === "expiry" && state.armed !== null) {
      return core.restartReduce(state, Object.assign({}, event, { serial: state.armed }));
    }
    return core.restartReduce(state, event);
  };

  let extra = 0;
  let realFires = 0;
  let staleOffers = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(777771 + run * 7919);
    let state = core.initialRestartState(20);
    let now = 100000;
    let armAt = null;
    for (const e of events) {
      let event = null;
      if (e.type === "notification") event = { type: e.type, stuck: e.stuck === true, applies: true };
      else if (e.type === "answer") event = { type: e.type, stuck: e.stuck === true, applies: e.stuck === true };
      else if (e.type === "clientState") event = { type: e.type, to: e.to };
      else if (e.type === "setting") event = { type: e.type, seconds: e.seconds };
      else if (e.type === "tick") {
        now += e.ms;
        if (state.armed !== null && armAt !== null && now - armAt >= state.seconds * 1000) {
          event = { type: "expiry", serial: state.armed, at: now };
        }
      } else if (e.type === "staleExpiry") {
        event = { type: "expiry", serial: e.serial, at: now };
        if (state.armed !== null && e.serial !== state.armed) staleOffers++;
      }
      if (!event) continue;
      const real = core.restartReduce(state, event);
      const mut = mutant(state, event);
      if (mut.effects.fire && !real.effects.fire) extra++;
      if (real.effects.fire) realFires++;
      if (real.effects.arm) armAt = now;
      if (real.effects.disarm || real.effects.fire) armAt = null;
      state = real.state;
    }
  }
  assert.ok(staleOffers > 50, "stale timers offered to a LIVE arm: " + staleOffers);
  assert.ok(extra > 0, "the stale-serial rule must make a difference: " + extra);
  console.log("    [mutant] restarts caused by a timer armed for an earlier incident: " + extra +
              " (real reducer: 0; real fires over the same runs: " + realFires + ")");
});

test("restart PROPERTY: the timer's mirror of stuck/running is EXACTLY stuckReduce's, event for event", () => {
  // The one thing letter (c) states twice, pinned the way stage 1 pins
  // `stuckEventApplies`: if the mirror ever disagreed, a fire could be
  // decided from a state the banner does not believe in.
  let checks = 0;
  let stuckSeen = 0;
  for (let run = 0; run < 400; run++) {
    const events = restartEventStream(13579 + run * 104729);
    let s = core.initialStuckState();
    let r = core.initialRestartState(20);
    for (const e of events) {
      if (e.type === "notification" || e.type === "answer") {
        const applies = core.stuckEventApplies(s, e);
        r = core.restartReduce(r, { type: e.type, stuck: e.stuck === true, applies }).state;
        s = core.stuckReduce(s, e).state;
      } else if (e.type === "clientState") {
        r = core.restartReduce(r, { type: "clientState", to: e.to }).state;
        s = core.stuckReduce(s, { type: "clientState", to: e.to }).state;
      } else continue;
      checks++;
      if (s.stuck) stuckSeen++;
      assert.strictEqual(r.stuck, s.stuck, "run " + run + ": the mirror disagrees about stuck");
      assert.strictEqual(r.running, s.running, "run " + run + ": the mirror disagrees about running");
    }
  }
  assert.ok(checks > 1000, "events compared: " + checks);
  assert.ok(stuckSeen > 100, "stuck states reached: " + stuckSeen);
  console.log("    [counts] mirror comparisons " + checks + ", of them stuck " + stuckSeen);
});

test("restart: the WALK-THROUGH -- fire, held, Render anyway, wedge again, fire again, held again", () => {
  // The loop-safety argument, run end to end: the only thing that lets a
  // second restart happen is the user asking for the render again.
  const events = [
    { type: "render", explicit: true },                        // the user renders
    { type: "answer", stuck: true, seqAtSend: 0 },             // it wedges: the refusal
    { type: "notification", stuck: true, seq: 1 },             // and the notification
    { type: "tick", ms: 21000, order: "stopped-first", err: 0 },  // the grace expires: FIRE
    { type: "render", explicit: true },                        // "Render anyway"
    { type: "answer", stuck: true, seqAtSend: 0 },             // it wedges again
    { type: "tick", ms: 60000, order: "rejection-first", err: 1 },  // FIRE again
  ];
  const out = runGlue(events, PICK, { restart: 20 });
  const fired = out.fires.filter((f) => f.fired);
  assert.strictEqual(fired.length, 2, "two incidents, two restarts, each bought by a click");
  for (const f of fired) assert.strictEqual(core.markMatches(f.markAtFire, PICK), true);
  const restarts = out.renders.filter((r) => r.trigger === core.TRIGGER_RESTART);
  assert.ok(restarts.length >= 2);
  for (const r of restarts) assert.strictEqual(r.issued, false, "a restart we caused re-rendered the wedge");
  // And the second fire was outside the floor, which is what let it happen.
  assert.ok(fired[1].at - fired[0].at >= core.RESTART_FLOOR_MS);
});

test("restart: a fire with nothing to attribute the wedge to does NOT restart", () => {
  // The hard rule: no pick, no mark, no restart -- a restart nothing would
  // hold is the loop this ticket exists to close.
  const events = [
    { type: "notification", stuck: true, seq: 1 },
    { type: "tick", ms: 21000 },
  ];
  const out = runGlue(events, undefined, { restart: 20 });
  assert.strictEqual(out.fires.length, 1);
  assert.strictEqual(out.fires[0].fired, false);
  assert.strictEqual(out.fires[0].why, "unattributed");
  // REVIEW D3: a refusal must not consume the floor, and must not be
  // silent. `lastFireAt` is untouched and the status bar carries the reason.
  assert.strictEqual(out.restart.lastFireAt, null);
  assert.strictEqual(core.restartProblem(out.restart), "unattributed");
  assert.match(
    core.statusBarState({ running: true, stuck: true, message: "stuck", pick: PICK, restartProblem: core.restartProblem(out.restart) }).tooltip,
    /The automatic restart did not happen: unattributed\./
  );
});

// ------------------------------- WP-22(c) review: F1, D1, D2, D3, F4, N2

test("F1: the user's Restart can never be refused, and a hung stop cannot disable it", () => {
  // THE BUG THIS PINS: the first build took a plain `restartInFlight` latch
  // around `restart(context)`, and `stopQuietly` awaits `client.stop()`,
  // which a wedged server can leave UNSETTLED for ever -- a hang is not a
  // throw, so the `try/finally` never ran. The latch then refused every
  // later restart, including the **Ermine: Restart Language Server** button
  // on our own stuck notification, in exactly the situation it exists for.
  assert.deepStrictEqual(core.restartAttempt(null, core.RESTART_BY_USER),
                         { proceed: true, supersedes: false, why: null });
  assert.deepStrictEqual(core.restartAttempt(null, core.RESTART_BY_TIMER),
                         { proceed: true, supersedes: false, why: null });

  const byTimer = { source: core.RESTART_BY_TIMER, epoch: 1 };
  const byUser = { source: core.RESTART_BY_USER, epoch: 1 };

  // THE TIMER NEVER STACKS on a restart that is already under way.
  assert.strictEqual(core.restartAttempt(byTimer, core.RESTART_BY_TIMER).proceed, false);
  assert.strictEqual(core.restartAttempt(byUser, core.RESTART_BY_TIMER).proceed, false);
  assert.match(core.restartAttempt(byTimer, core.RESTART_BY_TIMER).why, /already under way/);

  // THE USER ALWAYS WINS, and takes over rather than running beside it.
  // "A hung stop does not disable the button" is this line, repeated: the
  // answer does not depend on how long the other restart has been stuck,
  // because nothing here can time out.
  for (let i = 0; i < 100; i++) {
    for (const underway of [byTimer, byUser]) {
      const v = core.restartAttempt(underway, core.RESTART_BY_USER);
      assert.strictEqual(v.proceed, true, "attempt " + i + ": the user's restart was refused");
      assert.strictEqual(v.supersedes, true);
      assert.match(v.why, /takes over/);
    }
  }
  // An unnamed source is the user's: here "let it through" is the safe
  // direction, because refusing is the thing that breaks the button.
  assert.strictEqual(core.restartAttempt(byTimer, undefined).proceed, true);
  assert.strictEqual(core.restartAttempt(byTimer, "somebody-else").proceed, true);
});

test("D2: the reviewer's scenario -- timeoutSeconds 5, grace 5, Render anyway -- is never stranded", () => {
  // The walk-through that made the floor a stranding bug in the first
  // build: fire #1, hold, "Render anyway", the report wedges again ~5 s
  // later, and the expiry lands INSIDE the 30 s floor. The first build
  // refused AND DISARMED, and since §4's rule (5) is withdrawn there is no
  // second rising edge to re-arm it: `stuck` for the rest of the session,
  // with a notification still promising a restart in 5 s.
  const events = [
    { type: "render", explicit: true },
    { type: "answer", stuck: true, seqAtSend: 0 },              // the wedge
    { type: "tick", ms: 6000, order: "stopped-first", err: 0 }, // FIRE #1
    { type: "render", explicit: true },                         // "Render anyway"
    { type: "answer", stuck: true, seqAtSend: 0 },              // it wedges again
    { type: "tick", ms: 31000, order: "stopped-first", err: 0 },
  ];
  const out = runGlue(events, PICK, { restart: 5 });
  const fired = out.fires.filter((f) => f.fired);
  assert.strictEqual(fired.length, 2, "the second incident must NOT be stranded");
  assert.ok(fired[1].at - fired[0].at >= core.RESTART_FLOOR_MS, "and the floor is still respected");

  // AND THE USER WAS TOLD THE TRUTH. The second arm knows the floor is in
  // the way and waits for it, so the notification says 30 s rather than the
  // setting's 5 s for a restart that could not happen for 30.
  assert.strictEqual(out.arms.length, 2);
  assert.strictEqual(out.arms[0].seconds, 5);
  assert.strictEqual(out.arms[1].seconds, 30);
  assert.strictEqual(out.arms[1].ms, core.RESTART_FLOOR_MS);
  // Both restarts were held, neither re-rendered the wedge.
  for (const r of out.renders.filter((x) => x.trigger === core.TRIGGER_RESTART)) {
    assert.strictEqual(r.issued, false);
  }
});

test("D1: a setting turned on while the preview is stuck restarts that incident, through the glue", () => {
  const events = [
    { type: "render", explicit: true },
    { type: "answer", stuck: true, seqAtSend: 0 },   // wedged, with the feature OFF
    { type: "tick", ms: 60000 },                     // an hour passes: nothing
    { type: "setting", seconds: 20 },                // the user reaches for the setting
    { type: "tick", ms: 21000 },
  ];
  const off = runGlue(events.slice(0, 3), PICK, { restart: 0 });
  assert.deepStrictEqual(off.fires, [], "with the feature off, nothing happens -- that is the default");
  assert.strictEqual(off.restart.stuck, true);

  const out = runGlue(events, PICK, { restart: 0 });
  assert.strictEqual(out.arms.length, 1, "turning it on while stuck arms it there and then");
  assert.strictEqual(out.fires.filter((f) => f.fired).length, 1);
  assert.strictEqual(core.markMatches(out.fires[0].markAtFire, PICK), true);
});

test("N2: after OUR restart the held text says so, whatever the mark's reason says", () => {
  // The reason at fire time is normally `watchdog`, because the accepted
  // rising edge that ARMS the grace is the same event that MARKS the pick
  // and `killed-by-us` never overwrites. So the flag, not the reason, has
  // to decide the wording -- "the server did not come back" is false when
  // we are the ones who brought it back.
  const watchdog = wedged(PICK, core.WEDGE_WATCHDOG, 1);
  assert.match(core.heldMessage(watchdog, PICK, false), /the watchdog fired and the server did not come back/);
  assert.match(core.heldMessage(watchdog, PICK, true), /the language server was restarted to clear it/);
  assert.match(
    core.statusBarState({ running: true, pick: PICK, mark: watchdog, restartedByUs: true }).tooltip,
    /the language server was restarted to clear it/
  );

  // AND THE FLAG COMES FROM THE REDUCER, set by the glue's `fired` answer.
  const fire = core.restartReduce(armedState(), { type: "expiry", serial: 1, at: 1000 });
  assert.strictEqual(core.restartedByUs(fire.state), false, "the fire alone is not a restart");
  const started = core.restartReduce(fire.state, core.restartEvents.fired(1000));
  assert.strictEqual(started.state.restartPending, true, "a token, minted");
  assert.strictEqual(core.restartedByUs(started.state), false, "and not yet spent");

  // IT IS SPENT ON THE Stopped -> Running OUR OWN RESTART CAUSES, because
  // the held question is asked on exactly that edge.
  const stopped = core.restartReduce(started.state, { type: "clientState", to: "Stopped" });
  const running = core.restartReduce(stopped.state, { type: "clientState", to: "Running" });
  assert.strictEqual(core.restartedByUs(running.state), true);
  assert.strictEqual(running.state.restartPending, false, "and spent exactly once");

  // A new incident's grace clears it, and so does the recovery.
  const again = core.restartReduce(running.state, { type: "notification", stuck: true, applies: true, at: 2000 });
  assert.strictEqual(core.restartedByUs(again.state), false);
  const recovered = core.restartReduce(started.state, { type: "notification", stuck: false, applies: true, at: 2000 });
  assert.strictEqual(core.restartedByUs(recovered.state), false);
});

test("F4: a stored mark this version cannot read is CLEARED, so the stale key leaves workspaceState", () => {
  // THE CONCRETE CASE: 0.1.7 writes the reason `killed-by-us`; 0.1.6's
  // vocabulary is closed and does not have it, so `isMark` rejects it. The
  // restore branch used to answer `{mark: null, effects: {}}` with no
  // `cleared`, and `applyGuard`'s `before === wedgeMark && !fx.cleared`
  // early return then meant `rememberWedge()` never ran: the stale key sat
  // in `workspaceState` being re-discarded on every activation, for ever.
  // That is stage 1's own N3 rule, applied to the branch that missed it.
  const fromAnotherVersion = {
    key: core.markKey(PICK),
    reason: "banished-by-us",
    at: 1,
    rootsFingerprint: core.rootsFingerprint(PICK.roots),
    paramsFingerprint: core.paramsFingerprint({}),
  };
  assert.strictEqual(core.isMark(fromAnotherVersion), false);
  const r = core.guardReduce(null, { type: "restore", mark: fromAnotherVersion, pick: PICK });
  assert.strictEqual(r.mark, null);
  assert.strictEqual(r.effects.cleared, true);
  assert.match(r.effects.why, /not one this version understands/);

  // NOTHING STORED is the ordinary case and must stay silent, or every
  // activation would log a clear and write the store.
  for (const empty of [undefined, null]) {
    const q = core.guardReduce(null, { type: "restore", mark: empty, pick: PICK });
    assert.strictEqual(q.mark, null);
    assert.strictEqual(q.effects.cleared, false);
  }
  // Any other stored shape is still a stored value.
  for (const junk of ["nonsense", 42, {}, { key: "k" }]) {
    assert.strictEqual(core.guardReduce(null, { type: "restore", mark: junk, pick: PICK }).effects.cleared, true,
                       "a stored " + typeof junk + " must be cleared from the store");
  }
});

// --------------------------- WP-22(c) delta review: M1, M2, (d), glue pins
//
// M2 NEEDS AN ASYNC MODEL, and that is what the block below is. `restart()`
// and `startClient()` are not pure and never will be -- they await a
// classpath warm-up that can run for minutes, a `stop()` that can hang, and
// a client constructor from the library -- but their INTERLEAVINGS are
// exactly where the two-client bug lived, and interleavings can be modelled
// with promises the test resolves by hand. The model mirrors the real
// control flow statement for statement; where it can call the real pure
// decision (`core.restartAttempt`) it does, rather than restating it.

function flush() {
  return new Promise((resolve) => setImmediate(resolve));
}

/**
 * A promise the TEST settles by hand -- BOUNDED (the S4 review's nit 5).
 *
 * Unbounded, a mutant that widens consent (R13: any modal answer counts as
 * Replace) made a model await a schema answer the test never gives, and
 * the WHOLE SUITE HUNG instead of failing the test by name (MEASURED: 60 s,
 * then killed). Now an awaited deferred that nobody settles within
 * `DEFERRED_BOUND_MS` REJECTS with a sentence saying so, and the test that
 * awaited it fails by name.
 *
 * The timer is `unref`ed and both promises carry a no-op catch, so the
 * deferreds an ordinary test leaves pending on purpose (an orphan notice
 * never clicked, a render superseded before its read) neither keep the
 * process alive nor surface as unhandled rejections: the whole suite runs
 * in about two seconds, far inside the bound.
 */
const DEFERRED_BOUND_MS = 8000;

function deferred() {
  let settle;
  const raw = new Promise((resolve) => { settle = resolve; });
  let timer = null;
  const bound = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error(
      "a deferred was awaited and never settled within " + DEFERRED_BOUND_MS + " ms -- the code under " +
      "test is waiting for an answer this test never gives (a consent- or step-widening mutant, or a " +
      "model that reaches a step the test did not drive)")), DEFERRED_BOUND_MS);
    if (timer && typeof timer.unref === "function") timer.unref();
  });
  bound.catch(() => {});
  raw.then(() => clearTimeout(timer));
  const promise = Promise.race([raw, bound]);
  promise.catch(() => {});
  return { promise, settle };
}

/**
 * A faithful model of extension.js's `restart(context, source)` /
 * `startClient(context, epoch)` / `stopQuietly(c)`.
 *
 * `opts.onStopped` receives the synthesised `Stopped` edge, `opts.noSynthStop`
 * removes it (mutant), `opts.noStartCheckpoint` drops `startClient`'s epoch check (mutant),
 * `opts.clearAfterAwait` clears `client` after the stop instead of before
 * (mutant), `opts.noStopBound` removes the 5 s bound so a hung stop never
 * returns (mutant), `opts.startThrows` makes the client constructor throw.
 */
function restartModel(opts) {
  const o = opts || {};
  const log = [];
  const clients = [];
  const warms = [];
  const stops = [];
  let startEpoch = 0;
  let clientEpoch = 0;
  let restartUnderway = null;
  let client = null;

  async function stopQuietly(c) {
    if (!c) return "none";
    const d = deferred();
    stops.push({ client: c, settle: d.settle });
    // THE 5 s BOUND IS WHAT MAKES THIS RETURN AT ALL when the server never
    // answers: the test resolves with "timed-out" to model the bound
    // firing, and the old process may then still be alive.
    const outcome = o.noStopBound ? await d.promise.then(() => "stopped") : await d.promise;
    if (outcome === "stopped") c.stopped = true;
    else log.push("stop timed out for client " + c.epoch);
    return outcome;
  }

  async function startClient(epoch) {
    const mine = typeof epoch === "number" ? epoch : (startEpoch += 1);
    const d = deferred();
    warms.push({ epoch: mine, settle: d.settle });
    await d.promise;                                   // the classpath warm-up
    if (!o.noStartCheckpoint && mine !== startEpoch) {
      log.push("superseded during the warm-up: " + mine);
      return;
    }
    if (o.startThrows) throw new Error("the language client could not be constructed");
    const c = { epoch: mine, stopped: false };
    clients.push(c);
    client = c;
    clientEpoch = mine;
    log.push("client " + mine + " is current");
  }

  async function restart(source) {
    const who = source === core.RESTART_BY_TIMER ? core.RESTART_BY_TIMER : core.RESTART_BY_USER;
    const attempt = core.restartAttempt(restartUnderway, who);
    if (!attempt.proceed) {
      log.push("refused " + who + " (" + attempt.why + ")");
      return attempt;
    }
    startEpoch += 1;
    const mine = startEpoch;
    restartUnderway = { source: who, epoch: mine };
    try {
      if (client) {
        const going = client;
        if (!o.clearAfterAwait) client = null;
        const outcome = await stopQuietly(going);
        if (o.clearAfterAwait) client = null;
        // THE SYNTHESISED `Stopped` EDGE (final re-check must-fix): on the
        // timed-out path the old client's real one arrives after the epoch
        // has moved and is dropped as stale, so `restart` reports it
        // itself. `noSynthStop` is the mutant: the code as it was.
        if (!o.noSynthStop) {
          log.push("stopped edge synthesised after " + outcome);
          if (o.onStopped) o.onStopped('the stop returned "' + outcome + '"');
        }
      }
      if (mine !== startEpoch) {
        log.push("superseded before the start: " + mine);
        return attempt;
      }
      await startClient(mine);
      if (mine !== startEpoch && client && clientEpoch === mine) {
        const stray = client;
        client = null;
        log.push("stray client " + stray.epoch + " stopped");
        await stopQuietly(stray);
      }
    } finally {
      if (restartUnderway && restartUnderway.epoch === mine) restartUnderway = null;
    }
    return attempt;
  }

  return {
    log, clients, warms, stops,
    restart,
    start: () => { startEpoch += 1; return startClient(startEpoch); },
    live: () => clients.filter((c) => !c.stopped),
    current: () => client,
    underway: () => restartUnderway,
    settleWarm: (i, ...rest) => warms[i].settle(...rest),
    settleStop: (i, how) => stops[i].settle(how || "stopped"),
  };
}

/**
 * Settle everything the model is waiting on, repeatedly, until nothing new
 * appears. A continuation can push a NEW warm-up or stop, so a single pass
 * over the arrays is not enough -- and an unsettled deferred would hang the
 * test rather than fail it.
 */
async function drain(m, howStop) {
  for (let round = 0; round < 30; round++) {
    let moved = false;
    for (const w of m.warms) if (!w.done) { w.done = true; w.settle(); moved = true; }
    for (const st of m.stops) if (!st.done) { st.done = true; st.settle(howStop || "stopped"); moved = true; }
    await flush();
    if (!moved) return;
  }
  throw new Error("the model never went quiet");
}

/** The invariant every interleaving has to leave true. */
function assertOneClient(m, where) {
  assert.ok(m.live().length <= 1, where + ": " + m.live().length + " clients are alive at once");
  if (m.current()) assert.strictEqual(m.current().stopped, false, where + ": the current client was stopped");
  for (const c of m.clients) {
    if (c === m.current()) continue;
    assert.strictEqual(c.stopped, true, where + ": client " + c.epoch + " was left running and unreferenced");
  }
}

test("M2: a restart DURING the classpath warm-up does not leave two clients (the bug)", async () => {
  // THE BUG: `startClient` awaits `warmClasspath`, which on a cold checkout
  // runs sbt for MINUTES, and only then assigns the module global. A
  // restart arriving in that window found `client` already cleared, skipped
  // the stop, and raced into its own `startClient`. Two clients, two server
  // JVMs, one referenced by nothing and never stopped -- and which one won
  // was decided by whichever warm-up finished last, not by any decision.
  const m = restartModel();
  m.start();                                  // activation's own client
  await flush();
  m.settleWarm(0);                            // it comes up
  await flush();
  assert.strictEqual(m.clients.length, 1);

  const first = m.restart(core.RESTART_BY_TIMER);   // the grace fires
  await flush();
  m.settleStop(0);                            // the old client stops
  await flush();
  // ...and now we are inside the warm-up. The user presses Restart.
  const second = m.restart(core.RESTART_BY_USER);
  await flush();
  await drain(m);                             // both warm-ups finish
  await first;
  await second;
  assertOneClient(m, "restart during the warm-up");
  assert.ok(m.log.indexOf("superseded during the warm-up: 2") >= 0, m.log.join(" | "));
  assert.strictEqual(m.current().epoch, 3, "the newest start is the one that survives");
  assert.strictEqual(m.underway(), null);
});

test("M2: each mutant of the fix does its own damage, and the model sees it", async () => {
  // MUTANT 1 -- `startClient` without its epoch checkpoint: the exact bug
  // the delta review found. TWO LIVE CLIENTS, two server JVMs, one of them
  // referenced by nothing.
  {
    const m = restartModel({ noStartCheckpoint: true });
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_TIMER);
    await flush();
    m.settleStop(0); m.stops[0].done = true; await flush();
    const b = m.restart(core.RESTART_BY_USER);
    await flush();
    await drain(m);
    await a; await b;
    assert.ok(m.live().length > 1,
              "the mutant must leave more than one live client; live=" + m.live().length);
    // And the real code, same interleaving, does not: that is the test above.
  }

  // MUTANT 2 -- clearing `client` AFTER the stop instead of before: a
  // second restart arriving inside the stop finds the SAME client and stops
  // it twice. Not two clients, but two `stop()`s on one, which is the other
  // half of what the guard is for.
  {
    const m = restartModel({ clearAfterAwait: true });
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_USER);
    await flush();
    const b = m.restart(core.RESTART_BY_USER);       // while the stop is pending
    await flush();
    const stoppedTwice = m.stops.filter((x) => x.client === m.clients[0]).length;
    assert.ok(stoppedTwice > 1, "the mutant must stop the same client twice; got " + stoppedTwice);
    await drain(m);
    await a; await b;
  }

  // THE REAL CODE, the same second interleaving: exactly one stop per client.
  {
    const m = restartModel();
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_USER);
    await flush();
    const b = m.restart(core.RESTART_BY_USER);
    await flush();
    await drain(m);
    await a; await b;
    for (const c of m.clients) {
      assert.ok(m.stops.filter((st) => st.client === c).length <= 1,
                "client " + c.epoch + " was stopped more than once");
    }
    assertOneClient(m, "user after user, real code");
  }
});

test("M2: the other five interleavings", async () => {
  // (1) A SECOND RESTART DURING THE STOP.
  {
    const m = restartModel();
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_TIMER);
    await flush();
    const b = m.restart(core.RESTART_BY_USER);      // while the stop is pending
    await flush();
    await drain(m);
    await a; await b;
    assertOneClient(m, "second restart during the stop");
  }

  // (2) TIMER AFTER USER: the automatic one is refused outright, so nothing
  // can stack behind a restart the user is already having.
  {
    const m = restartModel();
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_USER);
    await flush();
    const verdict = await m.restart(core.RESTART_BY_TIMER);
    assert.strictEqual(verdict.proceed, false);
    await drain(m);
    await a;
    assertOneClient(m, "timer after user");
  }

  // (3) USER AFTER USER: the second one takes over.
  {
    const m = restartModel();
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_USER);
    await flush();
    const b = m.restart(core.RESTART_BY_USER);
    await flush();
    await drain(m);
    await a; await b;
    assertOneClient(m, "user after user");
  }

  // (4) A LATE-SETTLING STOP -- the 5 s bound returned, the server did not.
  // The old process may still be alive; that is what the loud log line is
  // for. What must NOT happen is a second CLIENT.
  {
    const m = restartModel();
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_USER);
    await flush();
    m.settleStop(0, "timed-out");                   // the bound fired
    m.stops[0].done = true;
    await flush();
    await drain(m);
    await a;
    assert.ok(m.log.some((l) => /stop timed out/.test(l)), m.log.join(" | "));
    assert.strictEqual(m.clients.length, 2, "a new client is started even though the old stop timed out");
    assert.strictEqual(m.current().epoch, 2);
  }

  // (5) `startClient` THROWS: the guard is still released, so the next
  // restart is not refused for ever.
  {
    const m = restartModel({ startThrows: true });
    m.start().catch(() => {});                      // the first start throws too
    await flush();
    m.settleWarm(0); await flush();
    let threw = false;
    const r = m.restart(core.RESTART_BY_USER).catch(() => { threw = true; });
    await flush();
    await drain(m);
    await r;
    assert.strictEqual(m.underway(), null, "the restart guard must be released even when the start throws");
    assert.strictEqual(core.restartAttempt(m.underway(), core.RESTART_BY_TIMER).proceed, true);
    assert.ok(threw || m.clients.length === 0);
  }
});

test("M1: the arm-time floor stretch reaches the NUMBER THE USER IS TOLD", async () => {
  // THE DEFECT: `arm()` stretches the delay to the floor only when the
  // event carries a clock, and the three events that can arm were sent from
  // extension.js as bare literals with no clock -- so the stretch never ran
  // in the shipped extension, and a user who set 5 was told "5 s" for a
  // restart that could not happen for 25. The outcome was right (the
  // expiry-time backstop held the floor); the sentence was not.
  const armed = core.restartReduce(
    rstate({ seconds: 5, lastFireAt: 1000000 }),
    core.restartEvents.notification(true, true, 1005000)
  );
  assert.strictEqual(armed.effects.ms, 25000);
  assert.strictEqual(armed.effects.seconds, 25);
  assert.strictEqual(armed.effects.bug, null);
  // AND IT SAYS WHY, or 25 looks like a bug in the setting just typed.
  const notice = core.restartNotice(core.restartArmedSeconds(armed.state), armed.state.seconds);
  assert.match(notice, /restarted automatically in 25 s/);
  assert.match(notice, /restarted less than 30 s ago/);
  assert.match(notice, /you asked for 5 s/);
  // The channel's arm line carries the same reason.
  assert.match(armed.effects.why, /not before 25 s/);
  // An ordinary arm says none of that.
  const plain = core.restartReduce(rstate({ seconds: 5 }), core.restartEvents.notification(true, true, 1005000));
  assert.strictEqual(plain.effects.ms, 5000);
  assert.strictEqual(core.restartNotice(5, 5).indexOf("not before"), -1);
});

test("M1: an arm with NO clock is a BUG, said out loud, not a silent zero", () => {
  // The builders make this unreachable from extension.js; the reducer still
  // refuses to pretend, because that silence is what hid the defect.
  const clockless = core.restartReduce(
    rstate({ seconds: 5, lastFireAt: 1000000 }),
    { type: "notification", stuck: true, applies: true }          // a hand-written event
  );
  assert.strictEqual(clockless.effects.arm, true, "it still arms: a broken clock must not break the feature");
  assert.match(clockless.effects.bug, /no clock/);
  assert.match(clockless.effects.bug, /core\.restartEvents/);
  // With no restart behind it there is nothing the clock would have
  // decided, so it is not a bug.
  const first = core.restartReduce(rstate({ seconds: 5 }), { type: "notification", stuck: true, applies: true });
  assert.strictEqual(first.effects.arm, true);
  assert.strictEqual(first.effects.bug, null);
  // And a builder always stamps one.
  assert.strictEqual(core.restartEvents.notification(true, true, 123).at, 123);
  assert.strictEqual(core.restartEvents.answer(true, true, 123).at, 123);
  assert.strictEqual(core.restartEvents.setting(20, 123).at, 123);
  assert.strictEqual(core.restartEvents.notification(true, true, "no").at, null);
});

test("(d): 'we restarted it' is a ONE-SHOT token, not a mood that leaks for ever", () => {
  // THE LEAK: `restartedByUs` was set by `fired` and cleared by almost
  // nothing, so a SPONTANEOUS death ten minutes later was described to the
  // user as "the language server was restarted to clear it" -- which we had
  // not done.
  let st = core.restartReduce(armedState(), core.restartEvents.expiry(1, 1000)).state;
  st = core.restartReduce(st, core.restartEvents.fired(1000)).state;
  st = core.restartReduce(st, core.restartEvents.clientState("Stopped")).state;
  st = core.restartReduce(st, core.restartEvents.clientState("Running")).state;
  assert.strictEqual(core.restartedByUs(st), true, "the edge our own restart caused");

  // TEN MINUTES LATER, a server that died by itself and came back.
  st = core.restartReduce(st, core.restartEvents.clientState("Stopped")).state;
  st = core.restartReduce(st, core.restartEvents.clientState("Running")).state;
  assert.strictEqual(core.restartedByUs(st), false, "a spontaneous death is not our restart");
  const mark = wedged(PICK, core.WEDGE_WATCHDOG, 1);
  assert.match(core.heldMessage(mark, PICK, core.restartedByUs(st)), /the server did not come back/);
});

test("glue pins: extension.js keeps the shape the models assume", () => {
  // THESE ARE SOURCE PINS, NOT BEHAVIOUR TESTS, and they exist because the
  // review's mutation runs showed that glue defects leave every
  // behavioural test in this file green: the glue is in no model. Each
  // message below says what the pin is, what it protects, and what to do if
  // you meant the change. THE MEASURED LIMIT IS RECORDED IN THE TRACKER:
  // these catch SHAPE DRIFT, not a deliberate neutering -- four
  // prose-preserving mutants (the warm-up checkpoint made `if (false)` with
  // its log kept, every `stale()` call neutered, `restartAttempt` called
  // and its answer ignored, the stray-stop branch neutered) survive the
  // whole suite, and only the manual checklist can observe those.
  const fs = require("node:fs");
  // **N-1'S AUDIT, APPLIED HERE TOO** (the S3 review): every pin in this
  // test matches STATEMENT text, and a statement that is commented out
  // leaves its text in place. That is how the S3 pin protecting the only
  // unbounded loop of that stage passed on a commented-out
  // `firstPickTried.add(...)` with all 249 tests green (MEASURED). The
  // stripping is `codeOf`'s, declared beside the S3 pins, and two places in
  // this test already did it by hand for exactly this reason.
  const raw = fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const src = codeOf(raw);
  const pin = (what, fix) =>
    "source pin (test/preview-core.test.js): extension.js changed shape — " + what +
    ". If you meant it, update this pin; the behaviour it protects is " + fix;

  // M1: no hand-written reducer event may reach `restartReduce`.
  assert.strictEqual(/restartReduce\(\s*restartState\s*,\s*\{/.test(src), false,
    pin("a reducer event is built inline instead of by core.restartEvents.*",
        "that every event carries the clock the 30 s floor needs (review M1)"));
  const calls = src.match(/core\.restartReduce\(/g) || [];
  const built = src.match(/core\.restartReduce\(\s*restartState,\s*core\.restartEvents\./g) || [];
  assert.strictEqual(calls.length, built.length,
    pin("a core.restartReduce call does not go through a builder",
        "that every event carries the clock the 30 s floor needs (review M1)"));
  assert.ok(built.length >= 8, pin("only " + built.length + " builder call sites were found", "the same"));

  // AND THE CLOCK ITSELF: a builder call that simply omits the argument is
  // exactly what M1 was. Counted as ARGUMENTS rather than matched as the
  // text `Date.now()`, so hoisting the clock into a local still passes.
  // (MEASURED: the builder check above alone does NOT kill that mutant.)
  const arity = { notification: 3, answer: 3, setting: 2, expiry: 2, fired: 1, fireRefused: 2 };
  for (const name of Object.keys(arity)) {
    const needle = "core.restartEvents." + name + "(";
    let from = 0;
    let seen = 0;
    for (;;) {
      const i = src.indexOf(needle, from);
      if (i < 0) break;
      seen++;
      let depth = 0;
      let args = 1;
      let j = i + needle.length - 1;
      for (; j < src.length; j++) {
        const ch = src[j];
        if (ch === "(" || ch === "[" || ch === "{") depth++;
        else if (ch === ")" || ch === "]" || ch === "}") { depth--; if (depth === 0) break; }
        else if (ch === "," && depth === 1) args++;
      }
      assert.ok(args >= arity[name],
        pin("core.restartEvents." + name + " is called with " + args + " arguments, not " + arity[name],
            "the clock the 30 s floor and its announced number need (review M1)"));
      from = i + needle.length;
    }
    assert.ok(seen > 0, pin("no call site for core.restartEvents." + name, "the same"));
  }

  // F1/M2, each matched on its STRUCTURE rather than on a variable name or
  // a log sentence, so renaming or rewording does not accuse the wrong
  // thing. What no pin can catch is a body that is kept and neutered.
  assert.ok(/restartAttempt\(\s*restartUnderway,\s*core\.RESTART_BY_TIMER\s*\)/.test(src),
    pin("fireRestart no longer asks core.restartAttempt",
        "that an automatic restart never stacks on one already under way (F1)"));
  assert.ok(/Promise\.race\(/.test(src) && /STOP_TIMEOUT_MS/.test(src),
    pin("stopQuietly no longer bounds its wait",
        "that a stop which never settles cannot disable the user's Restart (F1)"));
  // Sliced to `startClient`'s own body: the SAME structural check exists in
  // `restart`, so an unsliced match would have passed with this one gone
  // (MEASURED while loosening these pins -- it did).
  const startBody = src.slice(src.indexOf("async function startClient("), src.indexOf("async function stopQuietly("));
  const warmed = startBody.indexOf("await warmClasspath(");
  const checked = startBody.search(/if\s*\(\s*mine\s*!==\s*startEpoch\s*\)/);
  assert.ok(warmed > 0 && checked > warmed,
    pin("startClient no longer re-checks its epoch AFTER the warm-up",
        "that a restart during the first-run classpath warm-up leaves one client, not two (M2)"));
  assert.ok(/mine\s*!==\s*startEpoch\s*&&\s*client\s*&&\s*clientEpoch\s*===\s*mine/.test(src),
    pin("restart no longer stops a stray client after startClient",
        "that a superseded start cannot leave an unreferenced server running (M2)"));
  assert.ok(/mine\s*!==\s*clientEpoch/.test(src),
    pin("a stale client's events are no longer ignored",
        "that a client nothing references cannot drive the reducers (M2)"));
  // The must-fix that came with the epoch guard: the Stopped edge has two
  // sources and exactly one implementation.
  assert.ok(/function onClientStopped\(/.test(src),
    pin("the Stopped edge is no longer factored into one function",
        "that a timed-out stop still reaches the guard's one consultation"));
  const synth = src.indexOf("onClientStopped(");
  assert.ok((src.match(/onClientStopped\(/g) || []).length >= 3 && synth > 0,
    pin("onClientStopped has fewer than the expected call sites (its definition, the handler, restart)",
        "that both the reported and the synthesised Stopped run the same code"));

  // M2's other half: the client must be cleared BEFORE the stop is awaited,
  // or a restart arriving inside the stop finds it and stops it twice.
  const body = src.slice(src.indexOf("async function restart(context, source)"));
  const clears = body.indexOf("client = undefined;");
  const stops = body.search(/await stopQuietly\(/);
  assert.ok(clears > 0 && stops > 0 && clears < stops,
    pin("restart() awaits the stop before clearing `client`",
        "that two restarts cannot stop the same client twice (M2)"));

  // ------------------------------------------------- WP-8 S2's own pins
  //
  // S2 put an `await` inside the send path, so the ORDER of four statements
  // in `renderNow` is now load-bearing and no behavioural test in this file
  // can see that order in the real source. These pin it.
  const renderBody = src.slice(src.indexOf("async function renderNow("), src.indexOf("async function showAnswer("));
  const at = (needle) => renderBody.indexOf(needle);
  const read = at("await prepareParams(");
  const gap = at("core.mayStillSend(");
  const refusal = at("prepared.refusal");
  const paramsEvent = at('type: "params"');
  const latch = at("inFlightRender = {");
  const wire = at('sendRequest("ermine/render"');
  const acted = renderBody.search(/if\s*\(\s*!verdict\.send\s*\)/);
  assert.ok(read > 0 && gap > read,
    pin("renderNow no longer re-checks core.mayStillSend AFTER reading the params",
        "that a pick change, a restart or a newer render during the read abandons this one " +
        "instead of sending stale parameters for the wrong pick (WP-8 S2)"));
  // AND THE ANSWER IS ACTED ON. Asking and ignoring the answer is exactly
  // the mutant a "does it call it?" pin cannot see (MEASURED while writing
  // these: with only the check above, deleting the `if` block survived the
  // whole suite).
  assert.ok(acted > gap && acted < at("prepared.refusal"),
    pin("renderNow computes the gap verdict and does not act on it",
        "the same: a render whose world moved must ABANDON, not merely notice"));
  // P3 OF THE DELTA RE-REVIEW: calling the function and DISCARDING its
  // answer on the next line survived both pins above (`core.mayStillSend(`
  // was present, and so was an `if (!verdict.send)` reading a `verdict`
  // that came from somewhere else). So the binding itself is pinned.
  assert.ok(/const verdict = core\.mayStillSend\(/.test(renderBody),
    pin("`verdict` is no longer ASSIGNED FROM core.mayStillSend",
        "that the object the abandon branch reads is the one the gap check answered (P3)"));
  assert.ok(!/^\s*core\.mayStillSend\(/m.test(renderBody),
    pin("core.mayStillSend is called for its side effect somewhere in renderNow",
        "the same: it has no side effect, so such a call is an answer being thrown away (P3)"));
  assert.ok(refusal > gap,
    pin("renderNow decides a params refusal before it re-checks the gap",
        "that a refusal about the OLD pick's file is not shown over the new pick (WP-8 S2)"));
  assert.ok(paramsEvent > gap && paramsEvent < latch,
    pin("the guard's `params` event is no longer fed between the gap check and the send",
        "that changing the parameters CLEARS the wedge mark and a re-format does not (WP-22, WP-8)"));
  // AND IT IS FED THIS RENDER'S OWN PARAMS. Feeding it `lastParamsSent`
  // instead compares the value with itself and never clears anything, with
  // the shape entirely intact (MEASURED: that mutant survived every other
  // test in this file).
  assert.ok(/\{ type: "params", pick: sentPick, params: prepared\.params \}/.test(renderBody),
    pin("the `params` guard event is built from something other than `prepared.params`",
        "the same: the mark must be compared against the params THIS render is sending"));
  assert.ok(latch > gap && wire > latch,
    pin("the in-flight latch is taken before the gap is re-checked, or after the request is sent",
        "that a render which is never sent cannot mark a report as having died mid-render (M1, WP-8 S2)"));

  // ---- THE SNAPSHOT (S2 review M1 and M2) ----------------------------------
  //
  // FOUR MUTANTS SURVIVED THE WHOLE SUITE by swapping one captured value for
  // the live global in an object literal written AFTER the await
  // (`clientEpoch: sentEpoch` -> `clientEpoch`, `pick: sentPick` -> `picked`,
  // `generation: mine` -> `generation`, and the request taking `picked`).
  // The STRUCTURAL answer is that there is no such literal any more: one
  // frozen snapshot is built BEFORE the await and everything after it reads
  // that. These pins hold that shape; the regexes are the belt.
  const snapshot = renderBody.indexOf("core.renderAttempt(");
  assert.ok(snapshot > 0 && snapshot < read,
    pin("renderNow no longer takes core.renderAttempt's snapshot BEFORE the read",
        "that the roots, the pick, the generation and the epoch a render is decided on cannot " +
        "move under it -- the roots are MUTATED IN PLACE by the settings handler, so a captured " +
        "reference compares an array with itself (M1)"));
  assert.ok(/core\.renderAttempt\(generation, picked, clientEpoch, stopCount, stuckState\.highWater\)/.test(renderBody),
    pin("the snapshot is built from something other than the five live values",
        "the same: it is a SNAPSHOT of the globals at send, taken where reading them is correct"));
  assert.ok(/core\.mayStillSend\(\s*attempt,/.test(renderBody),
    pin("the gap check is handed something other than the snapshot",
        "that no value it compares can be the live global by accident (M2)"));
  assert.ok(/core\.previewNow\(generation, picked, clientEpoch, stopCount, !!sentClient\)/.test(renderBody),
    pin("the gap check's LIVE side is not read through core.previewNow",
        "the same, from the other direction: the live side must be read at the comparison -- and " +
        "with the CLIENT THE VERDICT SAW, which is the one the request is then sent to"));
  assert.ok(/core\.renderRequest\(attempt, prepared\.params\)/.test(renderBody),
    pin("the request is no longer built from the snapshot",
        "that the uri, the binding, the roots and the generation on the wire all come from the " +
        "render that was decided on, not from whatever is current after the read (M2's R9/R10)"));
  assert.ok(/const sentPick = attempt\.pick;/.test(renderBody) && !/const sentPick = picked;/.test(renderBody),
    pin("renderNow captures the live pick object instead of the snapshot's copy",
        "the same (M1): `picked.roots` is mutated in place by the roots handler"));

  // ---- M6: the second place the ONE consultation is reached from -----------
  const consult = renderBody.indexOf("core.mayAutoRender(");
  assert.ok(consult > paramsEvent && consult < latch,
    pin("renderNow no longer consults core.shouldAutoRender between the guard's `params` event " +
        "and the send",
        "the USER'S OWN SENTENCE: a report that wedged and did not change is not re-rendered " +
        "without a confirmation. This is the moment the extension KNOWS nothing changed, because " +
        "it has just computed the fingerprint (S2 review M6)"));
  // MATCHED AS THE WHOLE STATEMENT, not as a call: `if (false && !core.may...)`
  // keeps every word and neuters it (MEASURED -- that mutant survived a pin
  // that only looked for the call).
  assert.ok(/const permitted = core\.mayAutoRender\(wedgeMark, sentPick, trigger, scheduledAt\);/.test(renderBody) &&
            /if \(!permitted\.render\) \{/.test(renderBody),
    pin("the consultation is neutered, or asked about something other than (the mark, this " +
        "render's pick, this render's trigger, and WHEN it was scheduled)",
        "that a held report is not re-rendered by a trigger with no evidence -- and not by one " +
        "whose evidence PREDATES the mark either (delta re-review D1/D2, families B and C)"));
  assert.ok(/holdRender\(trigger\)/.test(renderBody),
    pin("the held render no longer asks the SAME question the restart asks, with the trigger " +
        "that asked",
        "that there is one question and one `held` state, not two (M6) -- and that D3 can tell a " +
        "params re-format (asked once) from a restart (asked every time)"));

  // ---- D2's BUG line, and D3's memory, each pinned at its own site --------
  assert.ok(/const triggerBug = core\.triggerProblem\(trigger\);/.test(renderBody) &&
            /if \(triggerBug\) log\("preview: BUG — " \+ triggerBug\);/.test(renderBody),
    pin("renderNow no longer says out loud that a render was triggered by something nothing " +
        "declared",
        "that an undeclared trigger is a BUG a human can see, not a silent hold -- the same " +
        "philosophy as the restart reducer's clockless arm (D2)"));
  const holdBody = src.slice(src.indexOf("function holdRender("), src.indexOf("function applyGuard("));
  assert.ok(/core\.shouldAskHeld\(heldRefusedToken, wedgeMark, picked, trigger\)/.test(holdBody),
    pin("holdRender no longer consults what the user last refused",
        "that format-on-save asks ONCE and not once per save (D3)"));
  assert.ok(/heldRefusedToken = asking\.token;/.test(holdBody),
    pin("holdRender no longer remembers a refusal",
        "the same (D3): a memory that is never written is never consulted either"));
  // MATCHED AS THE STATEMENT AND ITS NEIGHBOUR, not as the comment beside
  // it: this pin used to key on `// consent resets it`, which N-1's audit
  // strips. A comment is not a behaviour.
  assert.ok(/heldRefusedToken = undefined;\s*\n\s*applyGuard\(core\.guardReduce\(wedgeMark, \{ type: "render", explicit: true \}\)\);/.test(holdBody),
    pin("consent no longer resets what was refused",
        "that after \"Render anyway\" the next unchanged save asks again (D3)"));

  // ---- M5: the stop counter ----------------------------------------------
  assert.ok(/stopCount \+= 1;/.test(src.slice(src.indexOf("function onClientStopped("))),
    pin("onClientStopped no longer counts the stop",
        "the defence against a library-internal restart on the SAME client object, which moves " +
        "no epoch and would otherwise reach the fresh server unguarded (M5, UNVERIFIED)"));

  // ---- M4: learning the module renders ------------------------------------
  const refresh = src.slice(src.indexOf("async function refreshModule("), src.indexOf("function installWatcher("));
  assert.ok(/scheduleRender\(.*TRIGGER_MODULE_LEARNED\)/.test(refresh),
    pin("learning the module name no longer schedules a render",
        "that a params file sitting on disk is not ignored for ever by a pick whose module " +
        "arrived late (M4)"));

  // P14: `scheduleRender` FORWARDS what it was given. Passing `undefined`
  // instead neutered both consultation sites for every automatic render and
  // survived the whole suite -- which is also why `shouldAutoRender` now
  // fails CLOSED on an undeclared trigger (D2), so this mutant is caught
  // twice: here, and by the behaviour if it ever gets past here.
  const coalescer = src.slice(src.indexOf("function scheduleRender("), src.indexOf("async function renderNow("));
  assert.ok(/const scheduledAt = Date\.now\(\);/.test(coalescer),
    pin("scheduleRender no longer records WHEN the evidence arrived",
        "that a render whose evidence predates the mark is held rather than sent (families B/C)"));
  assert.ok(/renderNow\(reason, false, trigger, scheduledAt\)/.test(coalescer),
    pin("scheduleRender no longer forwards its trigger and schedule time to renderNow",
        "that the consultation knows WHICH trigger is rendering and WHEN it was decided (P14)"));

  // ---- every trigger the glue passes is one the core knows ----------------
  const triggers = (src.match(/core\.TRIGGER_[A-Z_]+/g) || []).map((t) => t.replace("core.", ""));
  assert.ok(triggers.length >= 9, pin("only " + triggers.length + " trigger constants are used", "the same"));
  for (const t of triggers) {
    assert.ok(Object.prototype.hasOwnProperty.call(core, t),
      pin("extension.js uses core." + t + ", which preview-core.js does not export",
          "that `shouldAutoRender`'s refused set is decided over a vocabulary both files agree on"));
  }
  // A literal string where a trigger belongs is how the vocabulary rots.
  assert.ok(!/scheduleRender\([^;]*,\s*"[a-z-]+"\s*\)/.test(src),
    pin("a render trigger is passed as a bare string instead of a core.TRIGGER_* constant",
        "the same"));
  // AND EACH SITE PASSES ITS OWN, because a trigger that claims the wrong
  // kind is how the consultation gets bypassed while every constant is still
  // in use (MEASURED: the params save passing TRIGGER_INVALIDATED survived a
  // pin that only checked the vocabulary).
  for (const [what, needle] of [
    ["the params file save", /scheduleRender\("the params file was saved", core\.TRIGGER_PARAMS_FILE\)/],
    ["the params file watcher", /the params file was \$\{what\} outside the editor`, core\.TRIGGER_PARAMS_FILE\)/],
    ["learning the module name", /scheduleRender\("the module name was learned", core\.TRIGGER_MODULE_LEARNED\)/],
    ["the invalidated notification", /scheduleRender\(`invalidated: \$\{picked\.module\}`, core\.TRIGGER_INVALIDATED\)/],
    ["the Q11 watcher", /core\.TRIGGER_FILE_EVENT\)/],
    ["the roots change", /scheduleRender\("ermine\.preview\.roots changed", core\.TRIGGER_ROOTS\)/],
    ["the picker", /renderNow\("the report was picked", true, core\.TRIGGER_EXPLICIT\)/],
    ["the render command", /renderNow\("Ermine: Render Report to JSON", true, core\.TRIGGER_EXPLICIT\)/],
    ["Render anyway", /renderNow\("Render anyway", true, core\.TRIGGER_EXPLICIT\)/],
  ]) {
    assert.ok(needle.test(src),
      pin(what + " no longer names its own trigger",
          "that a trigger which brings NO evidence of change cannot claim to bring some, and so " +
          "cannot walk past the consultation (M6)"));
  }

  // ---- nits 3, 6 and 7 ----------------------------------------------------
  assert.ok(/vscode\.workspace\.fs\.stat\(/.test(src) && /paramsTooLargeToRead\(/.test(src),
    pin("the params file is read without asking its size first",
        "that a gigabyte params file cannot be materialised in the extension host before the " +
        "cap looks at it (review nit 3)"));
  assert.ok(/Promise\.race\(\[reading, bounded\]\)/.test(src),
    pin("the params read is no longer bounded",
        "that a read which never settles cannot leave the spinner on for the life of the window " +
        "-- a hang is not a throw (review nit 7, and stopQuietly's own lesson)"));
  // P11: the bound exists and must also be USED. Reading the file through
  // the unbounded helper instead left `readParamsFileBounded` in the source,
  // unreferenced, and every pin above green.
  assert.ok(/await readParamsFileBounded\(paths\.paramsPath\)/.test(src),
    pin("prepareParams reads the params file through the UNBOUNDED helper",
        "the same (P11): the bound is worth nothing if the read does not go through it"));
  // ---- the four the review found SURVIVING, each now pinned ---------------
  //
  // R11/R12/R13/R14 are glue assignments: no model reaches them, so a pin is
  // the only thing that can. Each message says what the assignment buys.
  // EVERY EXIT, PINNED WHERE IT IS. A count pin passes when one exit of five
  // loses its guard or its release (MEASURED: both mutants survived it).
  const RELEASE = "if (mine === generation) renderInFlight = false;";
  for (const [what, from, until] of [
    ["the abandon path", "if (!verdict.send) {", "  // Said only now"],
    ["the refusal path", "if (prepared.refusal) {", "  // WP-22's `params` event"],
    ["the held path", "const permitted = core.mayAutoRender(", "  lastParamsSent ="],
  ]) {
    const start = renderBody.indexOf(from);
    const exit = renderBody.slice(start, renderBody.indexOf(until, start));
    assert.ok(start > 0 && exit.indexOf(RELEASE) >= 0,
      pin(what + " of renderNow no longer releases the spinner under its generation guard",
          "that a render which stops here leaves the status bar idle, and that it cannot switch " +
          "off a NEWER render's spinner (R5, R11)"));
  }
  assert.ok(/lastParamsSent = prepared\.params;/.test(renderBody),
    pin("renderNow no longer remembers the params it sent",
        "that a wedge mark minted by a LATER event (a stuck notification, a Stopped edge) carries " +
        "the params that were in force, which is what makes editing them clear it (R12)"));
  const setSites = [
    ["function onClientStopped(", "function installPreviewHandlers("],
    ['c.onNotification("ermine/preview/stuck"', "// Section 5's \"Server stopped\" row"],
    ["function fireRestart(", "function releaseInFlight("],
  ];
  for (const [from, until] of setSites) {
    const start = src.indexOf(from);
    const body = src.slice(start, src.indexOf(until, start));
    assert.ok(start > 0 && /params: core\.markParamsFor\(/.test(body),
      pin(from.replace(/[({"].*/, "") + " feeds the guard a SET event with no `params:`",
          "that every way a wedge is marked records the params that were in force -- a mark " +
          "without them can never be cleared by changing them (R13)"));
  }
  const noticeBody = src.slice(src.indexOf("function paramsNoticeOnce("), src.indexOf("function forgetParamsNotices("));
  assert.ok(/paramsNotices\.has\(key\)/.test(noticeBody) && /paramsNotices\.add\(key\)/.test(noticeBody),
    pin("paramsNoticeOnce no longer remembers what it has already said",
        "that a save-driven loop does not repeat the same sentence in the channel every few " +
        "seconds, which is how a real message gets missed (R6)"));
  const prepare = src.slice(src.indexOf("async function prepareParams("), src.indexOf("function onClientStopped("));
  assert.ok(/core\.meansFileMissing\(err\)/.test(prepare),
    pin("prepareParams no longer asks core.meansFileMissing what the read failure meant",
        "that a file which EXISTS and could not be read REFUSES, instead of rendering `{}` over " +
        "parameters that are really there (R14)"));

  // P8: the variable is READ by the watcher and must also be WRITTEN by the
  // answer path -- deleting the write left the read pinned and the value
  // for ever undefined, which disarms the watcher just as thoroughly.
  assert.ok(/\n  lastServerAnswer = answer;/.test(src),
    pin("renderNow no longer records the server's answer as the last SERVER answer",
        "that the Q11 watcher has something to ask about at all (P8)"));
  assert.ok(/core\.shouldRerenderOnFileEvent\(picked, lastServerAnswer, where\)/.test(src),
    pin("the Q11 watcher no longer asks about the last SERVER answer",
        "that a params refusal -- which no server gave -- cannot disarm the watcher that brings a " +
        "deleted report back to life (review nit 5)"));
  const teardown = src.slice(src.indexOf("function disposePreview("), src.indexOf("function restorePick("));
  assert.ok(/picked = undefined;/.test(teardown) && /previewDisposed = true;/.test(teardown),
    pin("the teardown no longer clears the pick",
        "that a render sitting in its file read abandons instead of sending into a disposed " +
        "window -- and that `pick-cleared` is reachable at all (review nit 6)"));
  assert.ok(/vscode\.workspace\.fs\.readFile\(/.test(src),
    pin("the params file is no longer read through vscode.workspace.fs",
        "that the preview reads SAVED files and not editor buffers (section 2.4), asynchronously. " +
        "IT DOES NOT PROTECT REMOTE OR VIRTUAL WORKSPACES: `Uri.file(fsPath)` drops the scheme and " +
        "the authority, so this is local-only and section 6 says so (S2 review M7)"));
  // G1: the folder is the one that CONTAINS the report. `rootsFor`'s
  // folders[0] fallback is fine for a SETTING and is not for a file. Pinned
  // at each of the three sites rather than by a count, because a count
  // survives replacing ONE of them (MEASURED: it did).
  for (const [fn, until] of [
    ["function paramsPathsFor(", "function paramsNoticeOnce("],
    ["function installParamsWatcher(", "function disposeWatchers("],
    ["onDidSaveTextDocument(", "// WP-22 (c): the grace, read once at activation"],
  ]) {
    const start = src.indexOf(fn);
    const body = src.slice(start, src.indexOf(until, start));
    assert.ok(start > 0 && /core\.paramsFolderFor\(/.test(body),
      pin(fn.replace(/[({].*/, "") + " no longer asks core.paramsFolderFor which folder owns the report",
          "that nothing reads -- and in S3 writes -- `.ermine/preview` inside an unrelated " +
          "workspace folder just because it is folders[0] (G1)"));
    // The COMMENTS are stripped first: they say "never `folders[0]`", which
    // a naive search reads as the thing it is forbidding.
    const code = body.replace(/\/\/[^\n]*/g, "").replace(/\/\*[\s\S]*?\*\//g, "");
    assert.ok(!/folders\[0\]|workspaceRoot\(\)|workspaceFolderPaths\(\)\[0\]/.test(code),
      pin(fn.replace(/[({].*/, "") + " reaches for the FIRST workspace folder", "the same (G1)"));
  }
  // Both re-render triggers go through the coalescer, or one save renders twice.
  const saveHandler = src.slice(src.indexOf("onDidSaveTextDocument("), src.indexOf("onDidSaveTextDocument(") + 2000);
  assert.ok(/shouldRerenderOnParamsSave\(/.test(saveHandler) && /scheduleRender\(/.test(saveHandler),
    pin("the params save no longer re-renders through scheduleRender",
        "that a save which fires BOTH the document event and the watcher costs ONE render"));
  const watcherBody = src.slice(src.indexOf("function installParamsWatcher("), src.indexOf("function disposeWatchers("));
  assert.ok(watcherBody.length > 0 && /scheduleRender\(/.test(watcherBody) && !/renderNow\(/.test(watcherBody),
    pin("the params watcher no longer re-renders through scheduleRender",
        "the same: one save, one render"));
  assert.ok(/onDidDelete\(/.test(watcherBody),
    pin("the params watcher no longer watches for the file being DELETED",
        "that deleting the params file renders with `{}` rather than with the last file's contents"));
});

test("2b: a stop that TIMED OUT still reaches the guard's one consultation, and holds", async () => {
  // THE DEFECT THE FINAL RE-CHECK FOUND. M2's epoch guard drops a stale
  // client's events, which is right -- except on this path: when
  // `stopQuietly` hits its 5 s bound, `restart` carries on, `startClient`
  // moves `clientEpoch`, and the OLD client's late `Stopped` is then
  // dropped. Nothing else reports it, so `stuckReduce` keeps `running:
  // true`, the new client's `Running` produces `rerender: false`, and the
  // ONE CONSULTATION IS NEVER REACHED: the report that wedged is never
  // asked about, the status bar never goes offline, and `lastAnswer` from a
  // dead process survives. It fails safe and it is still wrong.
  //
  // The async model runs the control flow; the three real reducers hang off
  // its `onStopped` hook, which is where "reached the consultation" can be
  // observed at all.
  const scenario = async (opts) => {
    let stuck = core.initialStuckState();
    let mark = wedged(PICK, core.WEDGE_WATCHDOG, 1);          // the pick wedged
    let rs = core.initialRestartState(20);
    const edges = [];
    const renders = [];
    let lastAnswerCleared = false;

    const stoppedEdge = (why) => {
      edges.push(why);
      mark = core.guardReduce(mark, {
        type: "clientState", to: "Stopped", renderInFlight: false, pick: PICK, at: 1,
      }).mark;
      rs = core.restartReduce(rs, core.restartEvents.clientState("Stopped")).state;
      stuck = core.stuckReduce(stuck, { type: "clientState", to: "Stopped" }).state;
    };
    const runningEdge = () => {
      const r = core.stuckReduce(stuck, { type: "clientState", to: "Running" });
      if (r.effects.rerender) {
        renders.push({ issued: core.shouldAutoRender(mark, PICK, core.TRIGGER_RESTART), mark });
      }
      if (!stuck.running) lastAnswerCleared = true;           // extension.js's own rule
      stuck = r.state;
      rs = core.restartReduce(rs, core.restartEvents.clientState("Running")).state;
    };

    const m = restartModel(Object.assign({ onStopped: stoppedEdge }, opts || {}));
    m.start(); await flush(); m.settleWarm(0); await flush();
    const a = m.restart(core.RESTART_BY_USER);
    await flush();
    m.settleStop(0, "timed-out");                             // THE 5 s BOUND FIRED
    m.stops[0].done = true;
    await flush();
    await drain(m);
    await a;
    // The state AS IT IS between the stop and the fresh client coming up:
    // this is the moment a second `Stopped` has to be a no-op, and it is
    // what makes the synthesis safe to send unconditionally.
    const afterStop = { stuck, mark, rs };
    runningEdge();                                            // the fresh client comes up
    return { edges, renders, stuck, mark, rs, lastAnswerCleared, afterStop, m };
  };

  // THE FIX: the edge is synthesised, so everything downstream happens.
  const fixed = await scenario();
  assert.deepStrictEqual(fixed.edges, ['the stop returned "timed-out"']);
  assert.strictEqual(fixed.renders.length, 1, "the restart must reach the one consultation");
  assert.strictEqual(fixed.renders[0].issued, false, "and it must HOLD the report that wedged");
  assert.strictEqual(fixed.lastAnswerCleared, true, "a dead process's answer must not survive");
  assert.strictEqual(core.markMatches(fixed.mark, PICK), true, "the mark is still this pick's");

  // THE MUTANT -- the code as it was -- reaches no consultation at all.
  const broken = await scenario({ noSynthStop: true });
  assert.deepStrictEqual(broken.edges, []);
  assert.strictEqual(broken.renders.length, 0, "without the synthesised edge nothing asks");
  assert.strictEqual(broken.lastAnswerCleared, false);

  // A SECOND `Stopped` BEFORE THE FRESH CLIENT IS UP IS A PURE NO-OP, which
  // is what lets the synthesis be unconditional: on the ORDINARY path the
  // library's own edge has already arrived and ours costs nothing.
  const at = fixed.afterStop;
  const before = JSON.stringify([at.stuck, at.mark, at.rs]);
  const mark2 = core.guardReduce(at.mark, {
    type: "clientState", to: "Stopped", renderInFlight: false, pick: PICK, at: 2,
  }).mark;
  const rs2 = core.restartReduce(at.rs, core.restartEvents.clientState("Stopped"));
  const st2 = core.stuckReduce(at.stuck, { type: "clientState", to: "Stopped" });
  assert.strictEqual(st2.effects.offline, false, "a second Stopped says nothing");
  assert.strictEqual(rs2.effects.disarm, false);
  assert.strictEqual(core.markMatches(mark2, PICK), true);
  assert.strictEqual(JSON.stringify([at.stuck, at.mark, at.rs]), before, "and changes nothing");

  // AND AFTER THE FRESH CLIENT IS RUNNING, THE LATE REAL `Stopped` MUST BE
  // DROPPED -- which is precisely what the epoch guard does. It is not
  // merely harmless there: delivered, it would report the preview offline
  // about a server that is up.
  const late = core.stuckReduce(fixed.stuck, { type: "clientState", to: "Stopped" });
  assert.strictEqual(late.effects.offline, true,
                     "a late Stopped would be WRONG after the new client is up -- hence the epoch guard");
});

// =========================================================== WP-8 S1: params files
//
// The pure core of section 6's params files: where they go, what a first
// skeleton holds, what the `.schema.json` beside them looks like, and what is
// actually put on the wire.  S1 IS PURE -- none of this is wired into
// `src/extension.js` and none of it touches a disk, so every case below is a
// value in and a value out.
//
// THE SALES FIXTURE WAS READ-DERIVED AND HAS SINCE BEEN CONFIRMED AGAINST A
// REAL SERVER.  `test/fixtures/sales-query.schema.json` was built by reading
// `core/src/main/scala/com/clarifi/reporting/ermine/json/Schema.scala`
// (`exportType` :184-196, the root splice :195, `dataType` :512-536, `constructor` :571-616, the
// builtins :327-339), `core/src/test/resources/doc/Sales.e:61-71` and the
// commit-tier `lsp` gate's own assertions (`tracker/tools/lsp-client.py:3398-3407`,
// which pin `$id`, `$ref` and Query's four properties and three required keys).
// The S1 REVIEW (2026-09-21) then started a real `bin/ermine-lsp`, sent one
// `ermine/schema`, and MEASURED the answer to be BYTE-IDENTICAL to this file --
// same bytes, same key order, so `schemaFileText` exposes no ordering
// difference either.  The capture driver is
// `scratchpad/wp8-review/capture.py` (about 40 s, no sbt) and the captured
// answer is `scratchpad/wp8-review/real-schema.json`.  S2's obligation to
// capture and diff is therefore DISCHARGED; re-running it is cheap if a
// change to the exporter ever makes it worth doing again.
//
// `test/fixtures/user-tree.schema.json` is a VERBATIM COPY of the committed
// exporter golden `core/src/test/resources/schema/UserTree.schema.json`
// (sha256 c0439f25...), copied here so the node tests can read it without
// reaching across the repository.  It is the recursive case the S1 review's
// D-1 turns on: `Test.Tree` is the root `$ref`'s target AND what the `Node`
// arm's `args` refer to.

const fs = require("node:fs");
const SALES_SCHEMA = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "sales-query.schema.json"), "utf8"));

/** One fixed "today", so every expectation below is a constant (U2: the clock
  * is the glue's, and a pure function is handed the date). */
const TODAY = "2026-09-21";

const SALES_PICK = core.makePick(
  "file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc"]);

/** The 32-bit xorshift the WP-22 tests use. NOT the LCG of the older ones:
  * ticket WP-27 records that its low bits are badly skewed, and every draw
  * below is a small modulus. */
function wp8Rnd(seed0) {
  let seed = seed0 | 0;
  return (n) => {
    seed ^= seed << 13; seed |= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5; seed |= 0;
    return (seed >>> 0) % n;
  };
}

// ------------------------------------------------------- paramsPaths (G1-G4, G6)

test("paramsPaths: the layout is a directory per module and a file per binding", () => {
  const p = core.paramsPaths(SALES_PICK, "/w", "posix");
  assert.strictEqual(p.problem, undefined, JSON.stringify(p));
  assert.strictEqual(p.previewDir, "/w/.ermine/preview");
  assert.strictEqual(p.dir, "/w/.ermine/preview/Sales");
  assert.strictEqual(p.paramsPath, "/w/.ermine/preview/Sales/report.params.json");
  assert.strictEqual(p.schemaPath, "/w/.ermine/preview/Sales/report.schema.json");
  assert.strictEqual(p.gitignorePath, "/w/.ermine/preview/.gitignore");
  // RELATIVE, and a sibling: the two files are written next to each other and
  // VS Code resolves a relative `$schema` against the document.
  assert.strictEqual(p.schemaRef, "./report.schema.json");
});

test("paramsPaths: a dotted module is ONE directory, never a path (section 6)", () => {
  const pick = core.makePick("file:///w/L/R.e", "/w/L/R.e", "report", "Layout.Widgets.Foo", []);
  const p = core.paramsPaths(pick, "/w", "posix");
  assert.strictEqual(p.dir, "/w/.ermine/preview/Layout.Widgets.Foo");
  assert.strictEqual(p.paramsPath, "/w/.ermine/preview/Layout.Widgets.Foo/report.params.json");
});

test("paramsPaths: the win32 flavour is tested HERE, on Linux, or it is not tested", () => {
  const pick = core.makePick("file:///c/w/Sales.e", "C:\\w\\doc\\Sales.e", "report", "Sales", []);
  const p = core.paramsPaths(pick, "C:\\w", "win32");
  assert.strictEqual(p.problem, undefined, JSON.stringify(p));
  assert.strictEqual(p.dir, "C:\\w\\.ermine\\preview\\Sales");
  assert.strictEqual(p.paramsPath, "C:\\w\\.ermine\\preview\\Sales\\report.params.json");
  // The REF is a URL fragment in the file, not a path: it stays forward-slashed.
  assert.strictEqual(p.schemaRef, "./report.schema.json");
});

test("paramsPaths: a report outside every workspace folder gets NO file (G1)", () => {
  // WP-7's own stuck fixture lives at /tmp/wp7/WpSpin.e -- outside the
  // workspace -- and `rootsFor` falls back to folders[0]. Doing the same here
  // would mint `.ermine/` in an unrelated repository.
  const outside = core.makePick("file:///tmp/wp7/WpSpin.e", "/tmp/wp7/WpSpin.e", "report", "WpSpin", []);
  const p = core.paramsPaths(outside, "/w", "posix");
  assert.strictEqual(p.problem.reason, "outside-workspace");
  assert.match(p.problem.message, /not inside the workspace folder/);
  assert.match(p.problem.message, /empty parameters/);

  const noFolder = core.paramsPaths(SALES_PICK, undefined, "posix");
  assert.strictEqual(noFolder.problem.reason, "no-workspace-folder");
  assert.strictEqual(core.paramsPaths(SALES_PICK, "   ", "posix").problem.reason, "no-workspace-folder");
});

test("paramsPaths: a sibling folder whose name is a prefix is NOT the workspace", () => {
  const pick = core.makePick("file:///workspace-old/S.e", "/workspace-old/S.e", "report", "S", []);
  assert.strictEqual(core.paramsPaths(pick, "/workspace", "posix").problem.reason, "outside-workspace");
});

test("paramsPaths: the workspace folder itself is not a report inside it", () => {
  const pick = core.makePick("file:///w", "/w", "report", "S", []);
  assert.strictEqual(core.paramsPaths(pick, "/w", "posix").problem.reason, "outside-workspace");
});

test("paramsPaths: a relative path on either side is refused, never resolved against cwd", () => {
  const pick = core.makePick("file:///w/S.e", "doc/S.e", "report", "S", []);
  assert.strictEqual(core.paramsPaths(pick, "/w", "posix").problem.reason, "outside-workspace");
  const abs = core.makePick("file:///w/S.e", "/w/S.e", "report", "S", []);
  assert.strictEqual(core.paramsPaths(abs, "w", "posix").problem.reason, "outside-workspace");
});

test("paramsPaths: a pick with no module name has no directory to live in (G6)", () => {
  const pick = core.makePick("file:///w/S.e", "/w/S.e", "report", null, []);
  const p = core.paramsPaths(pick, "/w", "posix");
  assert.strictEqual(p.problem.reason, "no-module");
  assert.match(p.problem.message, /empty parameters/);
});

test("paramsPaths: no pick at all", () => {
  assert.strictEqual(core.paramsPaths(null, "/w", "posix").problem.reason, "no-pick");
  assert.strictEqual(core.paramsPaths(undefined, "/w", "posix").problem.reason, "no-pick");
});

test("paramsPaths: every binding review G3 names is refused, by name", () => {
  const cases = [
    ["<+>",          "an operator binding"],
    ["|>",           "an operator binding with a pipe"],
    ["a/b",          "a forward slash"],
    ["a\\b",         "a backslash"],
    ["a:b",          "a colon (an NTFS stream, a drive on Windows)"],
    ["a\u0000b",     "a NUL byte"],
    [".hidden",      "a leading dot"],
    ["trailing.",    "a trailing dot (Windows silently strips it)"],
    ["trailing ",    "a trailing space (likewise)"],
    ["",             "the empty string"],
    ["..",           "the parent directory"],
    ["/abs",         "an absolute path"],
    ["x".repeat(core.MAX_NAME_LENGTH + 1), "over-long"],
    ["\u00e9t\u00e9", "a non-ASCII name"],
  ];
  for (const [binding, why] of cases) {
    const pick = core.makePick("file:///w/S.e", "/w/S.e", binding, "S", []);
    const p = core.paramsPaths(pick, "/w", "posix");
    assert.strictEqual(p.problem && p.problem.reason, "unsafe-binding", why + " must be refused");
    assert.match(p.problem.message, /empty parameters/, why + " must say what happens instead");
  }
  // and the length that is exactly allowed is allowed
  const ok = core.makePick("file:///w/S.e", "/w/S.e", "x".repeat(core.MAX_NAME_LENGTH), "S", []);
  assert.strictEqual(core.paramsPaths(ok, "/w", "posix").problem, undefined);
});

test("paramsPaths: a module name that is not a dotted run of plain names is refused", () => {
  const bad = ["..", "a/b", "a\\b", ".a", "a.", "a..b", "", "a b", "a\u0000b",
               "x".repeat(core.MAX_NAME_LENGTH + 1), "/abs", "C:\\x"];
  for (const moduleName of bad) {
    const pick = core.makePick("file:///w/S.e", "/w/S.e", "report", moduleName, []);
    const p = core.paramsPaths(pick, "/w", "posix");
    // an empty module name is `null`-ish to makePick, so it lands on no-module
    const reason = p.problem && p.problem.reason;
    assert.ok(reason === "unsafe-module" || reason === "no-module",
              JSON.stringify(moduleName) + " came back as " + reason);
  }
  const ok = core.makePick("file:///w/S.e", "/w/S.e", "report", "A.B'.C_1", []);
  assert.strictEqual(core.paramsPaths(ok, "/w", "posix").problem, undefined);
});

test("paramsPaths: a Windows device name is refused as ANY segment, extension or not (G4)", () => {
  for (const moduleName of ["CON", "con", "Nul", "AUX", "COM1", "lpt9", "PRN"]) {
    const pick = core.makePick("file:///w/S.e", "/w/S.e", "report", moduleName, []);
    assert.strictEqual(core.paramsPaths(pick, "/w", "posix").problem.reason, "reserved-name",
                       moduleName + " is a device name");
  }
  for (const binding of ["NUL", "nul", "com1", "LPT9", "aux", "prn"]) {
    // as a BINDING the segment is `NUL.params.json`: Windows reads the device
    // name off the part before the FIRST dot, so the extension does not save it
    const pick = core.makePick("file:///w/S.e", "/w/S.e", binding, "S", []);
    const p = core.paramsPaths(pick, "/w", "posix");
    assert.strictEqual(p.problem.reason, "reserved-name", binding + ".params.json is a device name");
    assert.match(p.problem.message, /rename the module or the binding/);
  }
  // LOOKALIKES ARE NOT REFUSED: the list is exactly Windows', not a prefix match
  for (const name of ["COM0", "COM10", "LPT10", "CONS", "NULL", "AUXILIARY"]) {
    const pick = core.makePick("file:///w/S.e", "/w/S.e", "report", name, []);
    assert.strictEqual(core.paramsPaths(pick, "/w", "posix").problem, undefined, name + " is not reserved");
  }
});

test("paramsPaths: the dotted module `CON.Reports` IS refused -- the rule reads before the dot", () => {
  // `.ermine/preview/CON.Reports` is ONE directory named `CON.Reports`, and
  // Windows reads the device name off the part before the FIRST dot, so this
  // one is refused too. Recorded because it is the case the rule is least
  // obvious in, and because it is a real cost: a module legitimately called
  // `Con.Something` gets no params file. Refusing is the safe direction --
  // the report still renders, with empty parameters.
  const pick = core.makePick("file:///w/S.e", "/w/S.e", "report", "CON.Reports", []);
  assert.strictEqual(core.paramsPaths(pick, "/w", "posix").problem.reason, "reserved-name");
});

// -------------------------------------- shouldRerenderOnParamsSave, isCurrentSchemaAnswer

test("params save: saving THIS pick's params file re-renders, and only it (G9)", () => {
  const f = (saved, flavour, folder) => core.shouldRerenderOnParamsSave(
    SALES_PICK, saved, folder === undefined ? "/w" : folder, flavour);
  assert.strictEqual(f("/w/.ermine/preview/Sales/report.params.json", "posix"), true);
  assert.strictEqual(f("/w/.ermine/preview/Sales/./report.params.json", "posix"), true, "normalised");
  assert.strictEqual(f("/w/.ermine/preview/Sales/other.params.json", "posix"), false);
  assert.strictEqual(f("/w/.ermine/preview/Other/report.params.json", "posix"), false);
  assert.strictEqual(f("/w/doc/Sales.e", "posix"), false);
  // the GENERATED schema file is not the params file: saving it changes nothing
  assert.strictEqual(f("/w/.ermine/preview/Sales/report.schema.json", "posix"), false);
  assert.strictEqual(f("", "posix"), false);
  assert.strictEqual(f(null, "posix"), false);
  // a pick with no derivable params file can never match a save
  assert.strictEqual(core.shouldRerenderOnParamsSave(SALES_PICK, "/w/x.json", undefined, "posix"), false);
});

test("params save: the compare is case-INSENSITIVE on win32 and case-SENSITIVE on posix", () => {
  const winPick = core.makePick("file:///c/Sales.e", "C:\\w\\doc\\Sales.e", "report", "Sales", []);
  assert.strictEqual(core.shouldRerenderOnParamsSave(
    winPick, "c:\\W\\.ermine\\PREVIEW\\sales\\Report.Params.JSON", "C:\\w", "win32"), true,
    "one file on Windows: a save that did not re-render would look broken");
  assert.strictEqual(core.shouldRerenderOnParamsSave(
    SALES_PICK, "/w/.ermine/preview/sales/report.params.json", "/w", "posix"), false,
    "two different files on Linux");
});

test("schema answer: a late answer whose pick has moved is dropped (D7)", () => {
  const at = core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc"]);
  const same = core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc"]);
  assert.strictEqual(core.isCurrentSchemaAnswer(at, same), true, "the same pick, rebuilt");
  const moved = {
    uri: core.makePick("file:///w/doc/Other.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc"]),
    binding: core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "other", "Sales", ["/w/doc"]),
    // the header changed: same file, same binding, a DIFFERENT directory to write into
    module: core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales2", ["/w/doc"]),
    moduleLost: core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", null, ["/w/doc"]),
    // the loader chain is the render session's discard key (section 2.4)
    roots: core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/lib"]),
    rootOrder: core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc", "/w/lib"]),
  };
  for (const key of Object.keys(moved)) {
    assert.strictEqual(core.isCurrentSchemaAnswer(at, moved[key]), false, key + " moved");
  }
  assert.strictEqual(core.isCurrentSchemaAnswer(null, same), false);
  assert.strictEqual(core.isCurrentSchemaAnswer(at, null), false);
  assert.strictEqual(core.isCurrentSchemaAnswer(null, null), false, "no pick is not the current pick");
});

// ------------------------------------------------------------- skeletonFrom

test("skeleton: THE SALES CASE -- the done-when of S1, from the read-derived fixture", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const out = core.skeletonFrom(SALES_SCHEMA, TODAY, paths.schemaRef);
  assert.strictEqual(out.problem, undefined, JSON.stringify(out));
  assert.deepStrictEqual(out.value, {
    $schema: "./report.schema.json",
    fromDay: TODAY,
    toDay: TODAY,
    orderBy: "ByDay",
  });
  assert.strictEqual(out.embeddable, true);
  // `onlyRegion : Maybe String` is OMITTED, not null: docs/JSON-GUIDE.md shows
  // the 400 a null in its place earns ("expected ..., found null").
  assert.ok(!Object.prototype.hasOwnProperty.call(out.value, "onlyRegion"));
  // `$schema` FIRST, so the file opens with the line that makes the rest of it
  // validate.
  assert.deepStrictEqual(Object.keys(out.value), ["$schema", "fromDay", "toDay", "orderBy"]);
  // `ByDay` is the FIRST constructor of `data Sort = ByDay | ByAmount | ByUnits`
  // (Sales.e:61), which is what `enum`'s member order is (Schema.scala:527).
  assert.strictEqual(SALES_SCHEMA.$defs["Sales.Sort"].enum[0], "ByDay");
  // U2/D4, said out loud: TODAY selects NONE of Sales's 2026-01-05..2026-03-17
  // rows. Until 2026-09-23 the server answered that with a 500 ("an empty
  // relation built from no rows carries no columns", MEASURED by the S1
  // review); the skeleton itself always DECODED (a wrong-typed date and a
  // missing key each earn a 400 naming the key). The user decided Q21 (section
  // 13): Sales.e now builds that table with `relationWithHeader`, and the
  // first pick renders ok=true with an empty four-column table (MEASURED,
  // scratch-widget-preview/q21-sales/); the engine gap is WP-29. The assertion
  // below is the part about the skeleton, and it stays.
  assert.ok(out.value.fromDay > "2026-03-17", "the skeleton's range is after every Sales row");
});

test("skeleton: with no schemaRef there is no `$schema` key", () => {
  const out = core.skeletonFrom(SALES_SCHEMA, TODAY);
  assert.deepStrictEqual(Object.keys(out.value), ["fromDay", "toDay", "orderBy"]);
  assert.strictEqual(out.embeddable, true, "it COULD carry one; it just was not given a ref");
});

test("skeleton: the first step is the `$ref` hop -- the root has no properties (D2)", () => {
  assert.strictEqual(SALES_SCHEMA.properties, undefined, "the fixture pins the shape the walker must handle");
  assert.strictEqual(SALES_SCHEMA.$ref, "#/$defs/Sales.Query");
  const noDefs = { $schema: "d", $ref: "#/$defs/Nope" };
  assert.strictEqual(core.skeletonFrom(noDefs, TODAY).problem.reason, "unsupported");
  const badRef = { $ref: "http://example/schema#/definitions/X" };
  assert.strictEqual(core.skeletonFrom(badRef, TODAY).problem.reason, "unsupported");
});

test("skeleton: a multi-constructor type is the FIRST arm, tagged as the decoder wants", () => {
  // `data Scope = Everything | OneRegion { regionName : String }`
  // (docs/JSON-GUIDE.md): a NULLARY constructor of a MIXED union is still
  // `{"tag":..,"args":[]}` -- only an ALL-nullary type is a bare string.
  const schema = {
    $ref: "#/$defs/M.Scope",
    $defs: {
      "M.Scope": {
        oneOf: [
          { type: "object",
            properties: { tag: { const: "Everything" }, args: { type: "array", maxItems: 0 } },
            required: ["tag", "args"], additionalProperties: false },
          { type: "object",
            properties: { tag: { const: "OneRegion" }, regionName: { type: "string" } },
            required: ["tag", "regionName"], additionalProperties: false },
        ],
      },
    },
  };
  assert.deepStrictEqual(core.skeletonFrom(schema, TODAY).value, { tag: "Everything", args: [] });
  // and the record-style arm, when it is first
  const swapped = { $ref: "#/$defs/M.Scope",
                    $defs: { "M.Scope": { oneOf: schema.$defs["M.Scope"].oneOf.slice().reverse() } } };
  assert.deepStrictEqual(core.skeletonFrom(swapped, TODAY).value, { tag: "OneRegion", regionName: "" });
});

test("skeleton: a positional constructor is prefixItems, one skeleton per position", () => {
  const schema = {
    $ref: "#/$defs/M.P",
    $defs: {
      "M.P": { type: "object",
               properties: { tag: { const: "P" },
                             args: { type: "array", minItems: 3, maxItems: 3,
                                     prefixItems: [{ type: "integer" }, { type: "string" },
                                                   { type: "boolean" }] } },
               required: ["tag", "args"], additionalProperties: false },
    },
  };
  assert.deepStrictEqual(core.skeletonFrom(schema, TODAY).value, { tag: "P", args: [0, "", false] });
  // a bare tuple root (`report : (Int, String) -> Node`) is an ARRAY, so no
  // `$schema` key can go in it
  const tuple = { type: "array", minItems: 2, maxItems: 2,
                  prefixItems: [{ type: "integer" }, { type: "string" }] };
  const out = core.skeletonFrom(tuple, TODAY, "./report.schema.json");
  assert.deepStrictEqual(out.value, [0, ""]);
  assert.strictEqual(out.embeddable, false);
});

test("skeleton: a list is empty and a unit is the empty array", () => {
  assert.deepStrictEqual(core.skeletonFrom({ type: "array", items: { type: "string" } }, TODAY).value, []);
  // `()` and a nullary positional constructor's `args` are both `maxItems: 0`,
  // and the decoder wants "an array of exactly 0"
  assert.deepStrictEqual(core.skeletonFrom({ type: "array", maxItems: 0 }, TODAY).value, []);
});

test("skeleton: the scalar vocabulary, each read off Schema.scala", () => {
  const value = (node) => core.skeletonFrom(node, TODAY).value;
  assert.strictEqual(value({ type: "string" }), "");
  assert.strictEqual(value({ type: "integer" }), 0);
  assert.strictEqual(value({ type: "number" }), 0);
  assert.strictEqual(value({ type: "boolean" }), false);
  assert.strictEqual(value({ type: "null" }), null);
  assert.strictEqual(value({ type: "string", format: "date" }), TODAY);
  // the EXPORTER'S OWN spelling (Encode.scala:203), because the decoder's
  // ISO_OFFSET_DATE_TIME (Decode.scala:461) demands an offset
  assert.strictEqual(value({ type: "string", format: "date-time" }), TODAY + "T00:00:00.000Z");
  assert.strictEqual(value({ type: "string", format: "uuid" }), core.NIL_UUID);
  assert.match(core.NIL_UUID, /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/,
               "the canonical 8-4-4-4-12 form Decode.scala:463 demands");
  // `Long` is a decimal STRING with a pattern `""` does not match
  assert.strictEqual(value({ type: "string", pattern: "^-?[0-9]+$" }), "0");
  // `Char` is minLength 1 / maxLength 1, and `""` fails it
  assert.strictEqual(value({ type: "string", minLength: 1, maxLength: 1 }), "x");
  // `Short`/`Byte` carry a range 0 is inside
  assert.strictEqual(value({ type: "integer", minimum: -32768, maximum: 32767 }), 0);
  // a range that excludes 0 still gets a value inside it
  assert.strictEqual(value({ type: "integer", minimum: 5, maximum: 9 }), 5);
  assert.strictEqual(value({ type: "integer", maximum: -3 }), -3);
  // a `Json` position is `{}` -- anything goes, and null is the shortest
  assert.strictEqual(value({}), null);
  assert.strictEqual(value({ type: "string", enum: ["a", "b"] }), "a");
  assert.strictEqual(value({ const: 7 }), 7);
});

test("skeleton: a pattern that is not the exporter's own Long is a refusal, not a guess", () => {
  const out = core.skeletonFrom({ type: "string", pattern: "^[a-f]{4}$" }, TODAY);
  assert.strictEqual(out.problem.reason, "unsupported");
  assert.match(out.problem.message, /write the params file by hand/);
});

test("skeleton: `anyOf [a, null]` takes NULL -- a required Nullable's default is absent", () => {
  // `Nullable a` and a native `Maybe# a` are REQUIRED keys whose schema admits
  // null (Schema.scala:585-591); only a declared `Builtin.Maybe` field is an
  // OPTIONAL key, and that is the `required` test, not this one.
  //
  // SETTLED BY THE S1 REVIEW: `null`, not the payload's skeleton. Rule 2 is
  // "the smallest value that decodes" and this is the same "absent" answer an
  // optional `Maybe` key gets by omission. The payload was not merely longer,
  // it was WRONG as a default: `""` for a `Nullable String` filter means
  // "match the empty string", not "no filter", and a date means a real range.
  const schema = { type: "object",
                   properties: { at: { anyOf: [{ type: "string", format: "date" }, { type: "null" }] } },
                   required: ["at"], additionalProperties: false };
  assert.deepStrictEqual(core.skeletonFrom(schema, TODAY).value, { at: null });
  // `oneOf` keeps the first-that-yields rule: the exporter never puts a null
  // arm in one, and a recursive union needs its base case.
  assert.strictEqual(core.skeletonFrom({ oneOf: [{ type: "string" }, { type: "null" }] }, TODAY).value, "");
  // a `Maybe X` params ROOT is then `null`, which is exactly what
  // docs/JSON-GUIDE.md says a report over `Maybe` wants
  const root = { $schema: "d", anyOf: [{ type: "integer" }, { type: "null" }] };
  assert.deepStrictEqual(core.skeletonFrom(root, TODAY, "./r.json"), { value: null, embeddable: false });
  // an anyOf with no null arm still takes the first that yields
  assert.strictEqual(core.skeletonFrom({ anyOf: [{ type: "boolean" }, { type: "string" }] }, TODAY).value,
                     false);
});

test("skeleton: a recursive required type has NO finite default, and is named", () => {
  // `data Chain = Chain { next : Chain }`
  const schema = {
    $ref: "#/$defs/M.Chain",
    $defs: { "M.Chain": { type: "object", properties: { next: { $ref: "#/$defs/M.Chain" } },
                          required: ["next"], additionalProperties: false } },
  };
  const out = core.skeletonFrom(schema, TODAY);
  assert.strictEqual(out.problem.reason, "recursive");
  assert.match(out.problem.message, /M\.Chain/, "the refusal NAMES the type");
});

test("skeleton: a recursive type with a base case still gets one -- the arm fails, not the call", () => {
  // `data Tree = Leaf | Node { left : Tree, right : Tree }`: `oneOf` tries the
  // next arm when one recurses, which is the whole reason a failed branch is
  // not fatal.
  const schema = {
    $ref: "#/$defs/M.Tree",
    $defs: {
      "M.Tree": { oneOf: [
        { type: "object", properties: { tag: { const: "Node" },
                                        left: { $ref: "#/$defs/M.Tree" },
                                        right: { $ref: "#/$defs/M.Tree" } },
          required: ["tag", "left", "right"], additionalProperties: false },
        { type: "object", properties: { tag: { const: "Leaf" }, args: { type: "array", maxItems: 0 } },
          required: ["tag", "args"], additionalProperties: false },
      ] },
    },
  };
  assert.deepStrictEqual(core.skeletonFrom(schema, TODAY).value, { tag: "Leaf", args: [] });
});

test("skeleton: recursion behind an OPTIONAL key or a list is no recursion at all", () => {
  const optional = {
    $ref: "#/$defs/M.R",
    $defs: { "M.R": { type: "object", properties: { n: { type: "integer" }, next: { $ref: "#/$defs/M.R" } },
                      required: ["n"], additionalProperties: false } },
  };
  assert.deepStrictEqual(core.skeletonFrom(optional, TODAY).value, { n: 0 }, "the Maybe key is omitted");
  const list = {
    $ref: "#/$defs/M.F",
    $defs: { "M.F": { type: "object", properties: { kids: { type: "array", items: { $ref: "#/$defs/M.F" } } },
                      required: ["kids"], additionalProperties: false } },
  };
  assert.deepStrictEqual(core.skeletonFrom(list, TODAY).value, { kids: [] }, "an empty list stops the walk");
});

test("skeleton: a non-object root gets a value and says NO `$schema` can go in it (G5)", () => {
  const ref = "./report.schema.json";
  // `report : Int -> Node` -- WP-7's own WpSpin fixture
  const int = core.skeletonFrom({ $schema: "d", $id: "ermine:WpSpin/Int", type: "integer" }, TODAY, ref);
  assert.deepStrictEqual(int, { value: 0, embeddable: false });
  // an all-nullary enum root
  const en = core.skeletonFrom({ $ref: "#/$defs/M.S", $defs: { "M.S": { enum: ["ByDay", "ByAmount"] } } },
                               TODAY, ref);
  assert.deepStrictEqual(en, { value: "ByDay", embeddable: false });
  // `Json` / `Maybe X` / `()` roots
  assert.deepStrictEqual(core.skeletonFrom({ $schema: "d", $id: "x" }, TODAY, ref),
                         { value: null, embeddable: false });
  assert.deepStrictEqual(core.skeletonFrom({ type: "array", maxItems: 0 }, TODAY, ref),
                         { value: [], embeddable: false });
});

test("skeleton: the arguments it refuses", () => {
  assert.strictEqual(core.skeletonFrom(null, TODAY).problem.reason, "not-a-schema");
  assert.strictEqual(core.skeletonFrom("{}", TODAY).problem.reason, "not-a-schema");
  assert.strictEqual(core.skeletonFrom([], TODAY).problem.reason, "not-a-schema");
  for (const bad of [undefined, "", "today", "2026-9-21", "2026-09-21T00:00:00Z", 20260921]) {
    assert.strictEqual(core.skeletonFrom(SALES_SCHEMA, bad).problem.reason, "bad-today",
                       JSON.stringify(bad) + " is not YYYY-MM-DD");
  }
});

test("skeleton: an unsatisfiable schema is named, not looped over", () => {
  const closed = { type: "object", properties: {}, required: ["x"], additionalProperties: false };
  assert.strictEqual(core.skeletonFrom(closed, TODAY).problem.reason, "unsatisfiable");
  assert.strictEqual(core.skeletonFrom({ oneOf: [] }, TODAY).problem.reason, "unsatisfiable");
  assert.strictEqual(core.skeletonFrom({ enum: [] }, TODAY).problem.reason, "unsatisfiable");
  assert.strictEqual(core.skeletonFrom(false, TODAY).problem.reason, "not-a-schema",
                     "a boolean is not a schema DOCUMENT, whatever it is inside one");
  // a required key with no schema of its own, in an OPEN object, is allowed
  const open = { type: "object", properties: {}, required: ["x"], additionalProperties: true };
  assert.deepStrictEqual(core.skeletonFrom(open, TODAY).value, { x: null });
});

test("skeleton: a schema deeper than the stack is a refusal, not a crash", () => {
  let node = { type: "string" };
  for (let i = 0; i < core.MAX_SKELETON_DEPTH + 5; i++) {
    node = { type: "object", properties: { a: node }, required: ["a"], additionalProperties: false };
  }
  assert.strictEqual(core.skeletonFrom(node, TODAY).problem.reason, "too-deep");
});

test("skeleton: the schema it was handed is not touched", () => {
  const before = JSON.stringify(SALES_SCHEMA);
  core.skeletonFrom(SALES_SCHEMA, TODAY, "./report.schema.json");
  assert.strictEqual(JSON.stringify(SALES_SCHEMA), before);
});

// ------------------------------------------------------ schemaFileFor / schemaFileText

test("schemaFile: `$id` is dropped and `$schema`/`$ref`/`$defs` are kept (U1)", () => {
  const file = core.schemaFileFor(SALES_SCHEMA);
  assert.strictEqual(file.$id, undefined, "a custom-scheme base URI may defeat $ref resolution (D3)");
  assert.strictEqual(file.$schema, "https://json-schema.org/draft/2020-12/schema", "the DIALECT stays");
  assert.strictEqual(file.$ref, "#/$defs/Sales.Query", "recursion needs $ref and $defs");
  assert.deepStrictEqual(Object.keys(file.$defs), ["Sales.Query", "Sales.Sort"]);
});

test("schemaFile: `$schema` is injected into the object the root `$ref` NAMES, not the root (D1)", () => {
  const file = core.schemaFileFor(SALES_SCHEMA);
  const query = file.$defs["Sales.Query"];
  assert.deepStrictEqual(query.properties.$schema, { type: "string" });
  assert.deepStrictEqual(Object.keys(query.properties),
                         ["$schema", "fromDay", "toDay", "onlyRegion", "orderBy"]);
  assert.strictEqual(query.additionalProperties, false, "the object stays CLOSED: a wrong key still squiggles");
  assert.deepStrictEqual(query.required, ["fromDay", "toDay", "orderBy"], "`$schema` is OPTIONAL");
  assert.strictEqual(file.properties, undefined,
                     "a `properties` at the root would do nothing: additionalProperties only sees its sibling");
  // THE POINT OF THE WHOLE EDIT: the skeleton we write carries a `$schema`
  // line, and the schema we write beside it must allow that line.
  const out = core.skeletonFrom(SALES_SCHEMA, TODAY, "./report.schema.json");
  assert.ok(Object.prototype.hasOwnProperty.call(
    file.$defs["Sales.Query"].properties, "$schema"), JSON.stringify(out.value));
});

test("schemaFile: an INLINE object root is injected at the root -- there it IS the sibling", () => {
  // `report : {..(|a, b|)} -> Node` (a Record params type, Schema.scala:412):
  // the exporter splices the record's own fields next to $schema/$id, so the
  // document root carries `properties` AND `additionalProperties: false`.
  // D1 named only the `$ref` case; this is the same defect one level up.
  const record = { $schema: "d", $id: "ermine:M/{..}", type: "object",
                   properties: { a: { type: "string" }, b: { type: "integer" } },
                   required: ["a", "b"], additionalProperties: false };
  const file = core.schemaFileFor(record);
  assert.deepStrictEqual(Object.keys(file.properties), ["$schema", "a", "b"]);
  assert.strictEqual(file.$id, undefined);
});

test("schemaFile: EVERY arm of a multi-constructor root is injected", () => {
  // The developer may retag the file to any arm, and the `$schema` line has to
  // survive that. An optional key on every arm cannot make two arms match one
  // value: the `tag` consts still discriminate.
  const schema = { $ref: "#/$defs/M.S", $defs: { "M.S": { oneOf: [
    { type: "object", properties: { tag: { const: "A" } }, required: ["tag"], additionalProperties: false },
    { type: "object", properties: { tag: { const: "B" } }, required: ["tag"], additionalProperties: false },
  ] } } };
  const file = core.schemaFileFor(schema);
  for (const arm of file.$defs["M.S"].oneOf) {
    assert.deepStrictEqual(arm.properties.$schema, { type: "string" });
  }
});

test("schemaFile: an OPEN object and a non-object root are left alone", () => {
  // A `Spread Json` field makes the object open (Schema.scala:620): it already
  // admits any key, so injecting would change what the file MEANS.
  const open = { $id: "x", $ref: "#/$defs/M.T", $defs: { "M.T": {
    type: "object", properties: { a: { type: "string" } }, required: ["a"], additionalProperties: true } } };
  assert.deepStrictEqual(core.schemaFileFor(open).$defs["M.T"].properties, { a: { type: "string" } });

  const int = { $schema: "d", $id: "ermine:M/Int", type: "integer" };
  assert.deepStrictEqual(core.schemaFileFor(int), { $schema: "d", type: "integer" });

  const already = { $ref: "#/$defs/M.T", $defs: { "M.T": {
    type: "object", properties: { $schema: { type: "number" } }, required: [], additionalProperties: false } } };
  assert.deepStrictEqual(core.schemaFileFor(already).$defs["M.T"].properties.$schema, { type: "number" },
                         "an existing declaration is not overwritten");

  assert.strictEqual(core.schemaFileFor(null), null);
  assert.strictEqual(core.schemaFileFor("x"), "x");
});

test("schemaFile: the input is never mutated and the edit is idempotent", () => {
  const before = JSON.stringify(SALES_SCHEMA);
  const once = core.schemaFileFor(SALES_SCHEMA);
  assert.strictEqual(JSON.stringify(SALES_SCHEMA), before, "the server's schema is the glue's, not ours");
  const twice = core.schemaFileFor(once);
  assert.strictEqual(core.schemaFileText(twice), core.schemaFileText(once),
                     "D8 compares BYTES, so the second run must produce the same ones");
});

test("schemaFile: the text is stable and ends in a newline (D8's write-if-different)", () => {
  const text = core.schemaFileText(core.schemaFileFor(SALES_SCHEMA));
  assert.ok(text.endsWith("\n"), "so git and every POSIX tool behave");
  assert.strictEqual(text, core.schemaFileText(core.schemaFileFor(SALES_SCHEMA)));
  assert.match(text, /^\{\n  "\$schema"/, "two-space, one key per line, diffable");
  assert.deepStrictEqual(JSON.parse(text), core.schemaFileFor(SALES_SCHEMA));
});

test("gitignore: the generated file ignores what is GENERATED and not the params (U7)", () => {
  const lines = core.paramsGitignoreText.split("\n");
  assert.ok(lines.indexOf("*.schema.json") >= 0, "the schema is generated on every change");
  assert.ok(lines.indexOf("*.db") >= 0, "WP-13/WP-14's local database file");
  assert.ok(!lines.some((l) => /^[^#]*params\.json/.test(l)),
            "the params file is COMMITTED: `git status` showing it is a done-when");
  assert.ok(core.paramsGitignoreText.endsWith("\n"));
  assert.match(core.paramsGitignoreText, /^# Generated by the Ermine preview/,
               "a generated file says so in its first line");
});

// -------------------------------------------------------------- paramsToSend

test("paramsToSend: the ordinary case, and the `$schema` strip (G20)", () => {
  const out = core.paramsToSend('{"$schema":"./report.schema.json","fromDay":"2026-01-05","toDay":"2026-02-20"}');
  assert.deepStrictEqual(out.params, { fromDay: "2026-01-05", toDay: "2026-02-20" });
  assert.deepStrictEqual(out.warnings, []);
  // every request key is closed (json/Runner.scala:101-103), so the line that
  // makes the EDITOR work would be a 400 from the SERVER
  assert.ok(!Object.prototype.hasOwnProperty.call(out.params, "$schema"));
});

test("paramsToSend: ONLY the top-level `$schema`, and ONLY when the root is an object", () => {
  const nested = core.paramsToSend('{"a":{"$schema":"keep me"},"b":[{"$schema":"me too"}]}');
  assert.deepStrictEqual(nested.params, { a: { $schema: "keep me" }, b: [{ $schema: "me too" }] });
  // a non-object root has no top-level key to strip
  assert.deepStrictEqual(core.paramsToSend('[{"$schema":"x"}]').params, [{ $schema: "x" }]);
  assert.strictEqual(core.paramsToSend('5').params, 5);
  assert.strictEqual(core.paramsToSend('"ByDay"').params, "ByDay");
  assert.strictEqual(core.paramsToSend('null').params, null);
  assert.strictEqual(core.paramsToSend('true').params, true);
  assert.deepStrictEqual(core.paramsToSend('[]').params, []);
  // the remaining keys keep their order
  assert.deepStrictEqual(Object.keys(core.paramsToSend('{"b":1,"$schema":"x","a":2}').params), ["b", "a"]);
});

test("paramsToSend: invalid JSON is a REFUSAL and the render does not happen (G7)", () => {
  const out = core.paramsToSend('{"fromDay": }');
  assert.strictEqual(out.params, undefined);
  assert.strictEqual(out.problem.reason, "invalid-json");
  assert.match(out.problem.message, /not valid JSON/);
  assert.ok(out.problem.message.length > "The params file is not valid JSON, so the report was not rendered: ".length,
            "the parser's own message travels with the refusal");
  // a control character from a broken file never reaches a message raw
  assert.ok(core.paramsToSend('{\u0007').problem.message.indexOf("\u0007") < 0);
});

test("paramsToSend: an EMPTY file is named, and is not silently `{}`", () => {
  for (const text of ["", "   ", "\n\n", "\t \r\n"]) {
    const out = core.paramsToSend(text);
    assert.strictEqual(out.problem.reason, "empty", JSON.stringify(text));
    assert.match(out.problem.message, /empty/);
    assert.match(out.problem.message, /\{\}/, "and says what to write instead");
  }
  // WHY, since the tracker did not settle it: a MISSING params key decodes as
  // null server-side (docs/JSON-GUIDE.md), but a missing key is a file that
  // does not EXIST -- S3's case, which sends `{}`. A file that exists and is
  // empty is a truncated write, and rendering it as `{}` would throw away
  // parameters the developer believes are there and show a document that
  // looks fine.
  assert.deepStrictEqual(core.paramsToSend("{}").params, {}, "an EXPLICIT {} is not the same event");
});

test("paramsToSend: the cap is on UTF-8 BYTES of the text, with a named refusal (U6)", () => {
  assert.strictEqual(core.PARAMS_MAX_BYTES, 1024 * 1024, "1 MiB; the only other bound closes the connection");
  const big = '{"a":"' + "x".repeat(core.PARAMS_MAX_BYTES) + '"}';
  const out = core.paramsToSend(big);
  assert.strictEqual(out.problem.reason, "too-large");
  assert.match(out.problem.message, /was not sent and the report was not rendered/);
  // BYTES, not UTF-16 units: eight astral characters are 32 bytes
  const astral = '{"a":"' + "\u{1F600}".repeat(8) + '"}';
  assert.strictEqual(Buffer.byteLength(astral, "utf8"), 32 + 8);
  assert.strictEqual(core.paramsToSend(astral, 39).problem.reason, "too-large");
  assert.strictEqual(core.paramsToSend(astral, 40).problem, undefined);
  assert.strictEqual(core.paramsToSend("{}", 0).problem, undefined, "a nonsense cap falls back to the default");
});

test("paramsToSend: a credential-looking top-level key WARNS and never blocks (U5)", () => {
  const out = core.paramsToSend('{"password":"hunter2","apiKey":"k","api_key":"k","x":1}');
  assert.deepStrictEqual(out.params, { password: "hunter2", apiKey: "k", api_key: "k", x: 1 },
                         "NOTHING is blocked: a report may legitimately take a token");
  assert.strictEqual(out.warnings.length, 1, "one warning per file, not per key");
  assert.match(out.warnings[0], /"password", "apiKey", "api_key"/);
  for (const key of ["pass", "passwd", "PASSWORD", "pwd", "secret", "clientSecret", "token",
                     "apiKey", "api_key", "api-key", "APIKEY"]) {
    assert.ok(core.CREDENTIAL_KEY.test(key), key + " must be flagged");
    assert.strictEqual(core.paramsToSend(JSON.stringify({ [key]: 1 })).warnings.length, 1, key);
  }
  for (const key of ["fromDay", "region", "orderBy", "passenger"]) {
    // `passenger` CONTAINS "pass" and is flagged: the rule is a substring
    // match on purpose (U5's own regex), and over-warning costs a sentence.
    const flagged = core.paramsToSend(JSON.stringify({ [key]: 1 })).warnings.length;
    assert.strictEqual(flagged, key === "passenger" ? 1 : 0, key);
  }
  // NESTED keys are not scanned: the rule is top-level, like the strip
  assert.deepStrictEqual(core.paramsToSend('{"db":{"password":"x"}}').warnings, []);
  assert.strictEqual(core.paramsToSend('{"$schema":"./x.json","token":1}').warnings.length, 1,
                     "the stripped key is not scanned, the rest is");
});

test("paramsToSend: the warning says what the hazard IS, not just that there is one", () => {
  const text = core.credentialKeyWarning(["password"]);
  assert.match(text, /committed to the repository/, "section 8: a params file is committed");
  assert.match(text, /log/, "and the render body reaches ERMINE_LSP_LOG (Rpc.scala:244)");
  assert.match(text, /Nothing is blocked/);
  // THE TEXT MUST MATCH THE REGEX (the S1 review's nit 5). U5 fixed the
  // pattern verbatim, so it is NOT widened here -- instead the warning says
  // what it actually looks for and names what it does NOT, so nobody reads
  // its silence as a clearance.
  assert.match(text, /KEY NAME only/);
  for (const missed of ["connectionString", "dsn", "jwt", "auth", "bearer", "privateKey", "credential"]) {
    assert.ok(!core.CREDENTIAL_KEY.test(missed), missed + " is NOT matched by U5's pattern");
    assert.ok(text.indexOf(missed) >= 0, "so the warning must name " + missed + " as a blind spot");
  }
  assert.ok(text.indexOf("connection string") < 0,
            "the old text claimed a connection string was covered; the regex cannot match one");
  assert.match(core.credentialKeyWarning(["a", "b"]), /^The keys "a", "b" look/);
  assert.match(core.credentialKeyWarning(["a"]), /^The key "a" looks/);
});

test("paramsToSend: what is not text", () => {
  for (const bad of [undefined, null, 5, {}, []]) {
    assert.strictEqual(core.paramsToSend(bad).problem.reason, "not-text", JSON.stringify(bad));
  }
});

// ------------------------------------------------ the fingerprint is WP-22's (G19)

test("fingerprint: WP-8 CALLS WP-22's `paramsFingerprint` and mints no second one", () => {
  const fp = (text) => core.paramsFingerprint(core.paramsToSend(text).params);
  const canonical = fp('{"$schema":"./report.schema.json","fromDay":"2026-01-05","toDay":"2026-02-20"}');

  // A RE-FORMAT does not clear the wedge mark...
  assert.strictEqual(fp('{\n  "$schema" : "./report.schema.json",\n  "fromDay":"2026-01-05",\n' +
                        '  "toDay" : "2026-02-20"\n}\n'), canonical, "re-formatted");
  // ...nor does REORDERING the keys (canonicalJson sorts them)...
  assert.strictEqual(fp('{"toDay":"2026-02-20","fromDay":"2026-01-05","$schema":"./report.schema.json"}'),
                     canonical, "reordered");
  // ...nor does changing the `$schema` LINE, which is stripped before the
  // fingerprint is taken: it is not part of the value that is sent.
  assert.strictEqual(fp('{"$schema":"./somewhere/else.json","fromDay":"2026-01-05","toDay":"2026-02-20"}'),
                     canonical, "a different $schema");
  assert.strictEqual(fp('{"fromDay":"2026-01-05","toDay":"2026-02-20"}'), canonical, "no $schema at all");

  // A REAL VALUE CHANGE DOES clear it.
  assert.notStrictEqual(fp('{"fromDay":"2026-01-06","toDay":"2026-02-20"}'), canonical, "a changed date");
  assert.notStrictEqual(fp('{"fromDay":"2026-01-05","toDay":"2026-02-20","onlyRegion":"north"}'), canonical,
                        "a key added");
  assert.notStrictEqual(fp('{"fromDay":"2026-01-05"}'), canonical, "a key removed");
  assert.notStrictEqual(fp('{"fromDay":"2026-01-05","toDay":20260220}'), canonical, "a type changed");
});

test("fingerprint: a params value is stored as a DIGEST and nowhere appears in it (WP-22 M3)", () => {
  const secret = "hunter2-s3cr3t-c0nnection-string";
  const fp = core.paramsFingerprint(core.paramsToSend(JSON.stringify({ password: secret })).params);
  assert.match(fp, /^[0-9a-f]{64}$/, "a SHA-256, because the mark goes into workspaceState on disk");
  assert.ok(fp.indexOf(secret) < 0);
  assert.ok(fp.indexOf("password") < 0);
  for (const piece of ["hunter2", "s3cr3t", "c0nnection"]) assert.ok(fp.indexOf(piece) < 0, piece);
});

// ------------------------------------------------------------------ properties
//
// A SMALL VALIDATOR FOR THE EXPORTER'S VOCABULARY AND NOTHING ELSE.  It is
// here, in the test, rather than in `preview-core.js`, because the rule is
// "never validate client-side twice" (review G7): the server's 400 is
// authoritative at run time.  What this one is for is the property below --
// the skeleton this code writes must be a value the schema accepts, or the
// first render of a fresh checkout is a 400 with our own file's name on it.

function jsonEqual(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

function validates(node, value, defs, depth) {
  if (depth > 400) return false;
  if (node === true) return true;
  if (node === false) return false;
  if (!node || typeof node !== "object" || Array.isArray(node)) return false;
  if (typeof node.$ref === "string") {
    const name = node.$ref.replace("#/$defs/", "");
    if (!Object.prototype.hasOwnProperty.call(defs, name)) return false;
    return validates(defs[name], value, defs, depth + 1);
  }
  if (Object.prototype.hasOwnProperty.call(node, "const")) return jsonEqual(node.const, value);
  if (Array.isArray(node.enum)) return node.enum.some((e) => jsonEqual(e, value));
  // `oneOf` is EXACTLY one, which is what the tag consts of a multi-constructor
  // type give; `anyOf` is at least one.
  if (Array.isArray(node.oneOf)) {
    return node.oneOf.filter((s) => validates(s, value, defs, depth + 1)).length === 1;
  }
  if (Array.isArray(node.anyOf)) return node.anyOf.some((s) => validates(s, value, defs, depth + 1));
  const type = Array.isArray(node.type) ? node.type[0] : node.type;
  if (type === undefined) return true;
  if (type === "null") return value === null;
  if (type === "boolean") return typeof value === "boolean";
  if (type === "integer" || type === "number") {
    if (typeof value !== "number") return false;
    if (type === "integer" && !Number.isInteger(value)) return false;
    if (typeof node.minimum === "number" && value < node.minimum) return false;
    if (typeof node.maximum === "number" && value > node.maximum) return false;
    return true;
  }
  if (type === "string") {
    if (typeof value !== "string") return false;
    if (typeof node.minLength === "number" && value.length < node.minLength) return false;
    if (typeof node.maxLength === "number" && value.length > node.maxLength) return false;
    if (typeof node.pattern === "string" && !new RegExp(node.pattern).test(value)) return false;
    // FORMAT IS CHECKED, though JSON Schema calls it an annotation: the
    // decoder is not an annotation (Decode.scala:551-573).
    if (node.format === "date" && !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    if (node.format === "date-time" && !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) return false;
    if (node.format === "uuid" &&
        !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(value)) return false;
    return true;
  }
  if (type === "array") {
    if (!Array.isArray(value)) return false;
    if (typeof node.minItems === "number" && value.length < node.minItems) return false;
    if (typeof node.maxItems === "number" && value.length > node.maxItems) return false;
    const prefix = Array.isArray(node.prefixItems) ? node.prefixItems : [];
    for (let i = 0; i < value.length; i++) {
      const sub = i < prefix.length ? prefix[i] : node.items;
      if (sub !== undefined && !validates(sub, value[i], defs, depth + 1)) return false;
    }
    return true;
  }
  if (type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    const properties = node.properties && typeof node.properties === "object" ? node.properties : {};
    for (const key of (Array.isArray(node.required) ? node.required : [])) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) return false;
    }
    for (const key of Object.keys(value)) {
      if (Object.prototype.hasOwnProperty.call(properties, key)) {
        if (!validates(properties[key], value[key], defs, depth + 1)) return false;
      } else if (node.additionalProperties === false) {
        return false;
      }
    }
    return true;
  }
  return false;
}

test("validator: the little validator has teeth (it is the property's only oracle)", () => {
  const defs = SALES_SCHEMA.$defs;
  assert.strictEqual(validates(SALES_SCHEMA, { fromDay: TODAY, toDay: TODAY, orderBy: "ByDay" }, defs, 0), true);
  assert.strictEqual(validates(SALES_SCHEMA, { fromDay: TODAY, toDay: TODAY }, defs, 0), false, "a missing required key");
  assert.strictEqual(validates(SALES_SCHEMA, { fromDay: TODAY, toDay: TODAY, orderBy: "Nope" }, defs, 0), false, "a bad enum");
  assert.strictEqual(validates(SALES_SCHEMA, { fromDay: "nope", toDay: TODAY, orderBy: "ByDay" }, defs, 0), false, "a bad date");
  assert.strictEqual(validates(SALES_SCHEMA, { fromDay: TODAY, toDay: TODAY, orderBy: "ByDay", nope: 1 }, defs, 0),
                     false, "an extra key under additionalProperties:false");
  // AND THE WHOLE POINT OF D1: the `$schema` line is refused by the RAW schema
  // and accepted by the one we WRITE.
  const withRef = { $schema: "./report.schema.json", fromDay: TODAY, toDay: TODAY, orderBy: "ByDay" };
  assert.strictEqual(validates(SALES_SCHEMA, withRef, defs, 0), false, "D1: the raw schema squiggles our own line");
  const file = core.schemaFileFor(SALES_SCHEMA);
  assert.strictEqual(validates(file, withRef, file.$defs, 0), true, "and the written file does not");
});

/**
 * A GENERATOR OF SCHEMAS IN THE EXPORTER'S VOCABULARY, and only it: `$defs`
 * entries that are an `enum` (an all-nullary `data`), one arm (a
 * single-constructor `data`) or a `oneOf` of arms, each arm record-style or
 * positional exactly as `json/Schema.scala:571-616` writes them, over the
 * builtins of `:327-339`.  A def may reference a LATER def or ITSELF, so
 * recursive types -- with and without a base case -- are drawn.
 */
/** Is this the exporter's `Nullable` shape? (The generator must not nest one
  * inside another; the exporter refuses that at `Schema.scala:368-370`.) */
function isPlainNullable(node) {
  return !!node && typeof node === "object" && Array.isArray(node.anyOf) &&
         node.anyOf.some((a) => a && a.type === "null");
}

function generateSchema(rnd) {
  const defCount = 1 + rnd(4);
  const names = [];
  for (let i = 0; i < defCount; i++) names.push("M.T" + i);
  const defs = {};

  const leaf = () => {
    switch (rnd(11)) {
      case 0: return { type: "string" };
      case 1: return { type: "integer" };
      case 2: return { type: "integer", minimum: -128, maximum: 127 };
      case 3: return { type: "number" };
      case 4: return { type: "boolean" };
      case 5: return { type: "string", format: "date" };
      case 6: return { type: "string", format: "date-time" };
      case 7: return { type: "string", format: "uuid" };
      case 8: return { type: "string", pattern: "^-?[0-9]+$" };            // Long
      case 9: return { type: "string", minLength: 1, maxLength: 1 };       // Char
      default: return {};                                                  // Json
    }
  };
  const value = (self, depth) => {
    if (depth > 3) return leaf();
    switch (rnd(7)) {
      case 0: return { $ref: "#/$defs/" + names[self + rnd(defCount - self)] };
      case 1: return { type: "array", items: value(self, depth + 1) };
      case 2: {
        const n = 1 + rnd(3);
        const items = [];
        for (let i = 0; i < n; i++) items.push(value(self, depth + 1));
        return { type: "array", prefixItems: items, minItems: n, maxItems: n };
      }
      case 3: {
        // `Maybe (Maybe a)` and `Nullable (Nullable a)` are REFUSED by the
        // exporter ("both layers encode to null", `Schema.scala:368-370`), so
        // the payload here is never itself a nullable.
        let payload = value(self, depth + 1);
        if (isPlainNullable(payload)) payload = leaf();
        return { anyOf: [payload, { type: "null" }] };
      }
      case 4: return { type: "array", maxItems: 0 };                          // ()
      default: return leaf();
    }
  };
  const arm = (self, tag, only) => {
    const n = rnd(4);
    const named = n > 0 && rnd(2) === 0;
    if (named) {
      const properties = only ? {} : { tag: { const: tag } };
      const required = only ? [] : ["tag"];
      for (let i = 0; i < n; i++) {
        const key = "f" + i;
        properties[key] = value(self, 0);
        if (rnd(3) !== 0) required.push(key);                  // else a Maybe: OPTIONAL
      }
      // A `Spread Json` FIELD MAKES THE OBJECT OPEN (`Schema.scala:606`,
      // `additionalProperties -> Json.jBool(spreads.nonEmpty)`; the real
      // example is the committed `UserSpread.schema.json`). The S1 review
      // measured this branch at COUNT 0 over the shipped 4000 draws -- and it
      // is exactly the branch `allowSchemaKey` short-circuits on, and the one
      // where a nested `$schema` is legitimately legal. A Spread field is NOT
      // a property of its own, so only the flag changes.
      const open = rnd(5) === 0;
      return { type: "object", properties: properties, required: required,
               additionalProperties: !open ? false : true };
    }
    const items = [];
    for (let i = 0; i < n; i++) items.push(value(self, 0));
    const args = n === 0
      ? { type: "array", maxItems: 0 }
      : { type: "array", prefixItems: items, minItems: n, maxItems: n };
    return { type: "object", properties: { tag: { const: tag }, args: args },
             required: ["tag", "args"], additionalProperties: false };
  };
  for (let i = 0; i < defCount; i++) {
    if (rnd(4) === 0) {
      const members = [];
      for (let k = 0; k <= rnd(3); k++) members.push("C" + k);
      defs[names[i]] = { enum: members };
    } else {
      const arms = 1 + rnd(3);
      const body = [];
      for (let k = 0; k < arms; k++) body.push(arm(i, "C" + k, arms === 1));
      defs[names[i]] = arms === 1 ? body[0] : { oneOf: body };
    }
  }
  const root = rnd(4) === 0 ? value(0, 0) : { $ref: "#/$defs/" + names[0] };
  return Object.assign({ $schema: "https://json-schema.org/draft/2020-12/schema",
                         $id: "ermine:M/T" }, root, { $defs: defs });
}

test("PROPERTY: a skeleton is a problem or a value the schema ACCEPTS", () => {
  const rnd = wp8Rnd(20260921);
  let problems = 0, values = 0, recursive = 0, embedded = 0;
  for (let i = 0; i < 4000; i++) {
    const schema = generateSchema(rnd);
    const before = JSON.stringify(schema);
    const file = core.schemaFileFor(schema);
    const out = core.skeletonFrom(schema, TODAY, "./report.schema.json");
    assert.strictEqual(JSON.stringify(schema), before, "the schema is not touched");
    if (out.problem) {
      problems++;
      if (out.problem.reason === "recursive") recursive++;
      assert.ok(out.problem.message.length > 0, JSON.stringify(out.problem));
      continue;
    }
    values++;
    // WITHOUT the `$schema` line, the value must satisfy the schema AS EXPORTED
    const bare = core.skeletonFrom(schema, TODAY);
    assert.strictEqual(validates(schema, bare.value, schema.$defs, 0), true,
                       "the skeleton must decode: " + JSON.stringify(bare.value) + " against " + before);
    // WITH it -- which is what is actually written -- it must satisfy the
    // schema FILE. This is D1's whole point, as a property.
    if (out.embeddable) {
      embedded++;
      assert.strictEqual(out.value.$schema, "./report.schema.json");
      assert.strictEqual(validates(file, out.value, file.$defs, 0), true,
                         "the `$schema` line must not squiggle: " + JSON.stringify(out.value) +
                         " against " + JSON.stringify(file));
    } else {
      assert.ok(!core.schemaFileText(out.value).includes('"$schema"') || typeof out.value !== "object",
                "a non-embeddable skeleton carries no $schema key we put there");
    }
  }
  // MEASURED on this seed: values=3882, problems=118 (ALL OF THEM `recursive` --
  // the generator emits only the exporter's vocabulary, so `unsupported`,
  // `unsatisfiable` and `too-deep` are reachable from a hand-edited schema and
  // are covered by the table tests above, not from here), embedded=2203. The
  // generator has to reach all four or the property is only testing the easy half.
  assert.deepStrictEqual(
    [values > 2000, problems > 100, recursive > 50, embedded > 1000],
    [true, true, true, true],
    "values=" + values + " problems=" + problems + " recursive=" + recursive + " embedded=" + embedded);
});

test("PROPERTY: `schemaFileFor` never mutates its input and is idempotent", () => {
  const rnd = wp8Rnd(424243);
  for (let i = 0; i < 2000; i++) {
    const schema = generateSchema(rnd);
    const before = JSON.stringify(schema);
    const once = core.schemaFileFor(schema);
    assert.strictEqual(JSON.stringify(schema), before);
    assert.strictEqual(once.$id, undefined);
    const twice = core.schemaFileFor(once);
    assert.strictEqual(core.schemaFileText(twice), core.schemaFileText(once));
    // and nothing it answers shares structure with what it was given
    once.$defs = null;
    assert.strictEqual(JSON.stringify(schema), before);
  }
});

/** Any JSON value, for the round-trip property. */
function generateJson(rnd, depth) {
  if (depth > 3) return rnd(2) === 0 ? rnd(100) : "s" + rnd(10);
  switch (rnd(9)) {
    case 0: return null;
    case 1: return rnd(2) === 0;
    case 2: return rnd(1000) - 500;
    case 3: return (rnd(1000) - 500) / 8;
    case 4: return ["", "s", "\u00e9\u{1F600}", "a b", '"q"', "\u0000"][rnd(6)];
    case 5: {
      const out = [];
      for (let i = rnd(4); i > 0; i--) out.push(generateJson(rnd, depth + 1));
      return out;
    }
    default: {
      const out = {};
      const keys = ["a", "b", "$schema", "token", "", "x.y", "\u00e9"];
      for (let i = rnd(5); i > 0; i--) out[keys[rnd(keys.length)]] = generateJson(rnd, depth + 1);
      return out;
    }
  }
}

test("PROPERTY: `paramsToSend(JSON.stringify(x))` round-trips any JSON value", () => {
  const rnd = wp8Rnd(9090909);
  let stripped = 0, warned = 0;
  for (let i = 0; i < 4000; i++) {
    const original = generateJson(rnd, 0);
    const out = core.paramsToSend(JSON.stringify(original));
    assert.strictEqual(out.problem, undefined, JSON.stringify(original));
    const expected = original;
    if (expected && typeof expected === "object" && !Array.isArray(expected) &&
        Object.prototype.hasOwnProperty.call(expected, "$schema")) {
      stripped++;
      const copy = Object.assign({}, expected);
      delete copy.$schema;
      assert.deepStrictEqual(out.params, copy);
    } else {
      assert.deepStrictEqual(out.params, JSON.parse(JSON.stringify(expected)));
    }
    if (out.warnings.length) {
      warned++;
      assert.strictEqual(out.warnings.length, 1, "one warning per file");
    }
  }
  // MEASURED on this seed: stripped=359, warned=338.
  assert.ok(stripped > 100 && warned > 100, "stripped=" + stripped + " warned=" + warned);
});

test("PROPERTY: `paramsPaths` never answers a path outside the workspace folder", () => {
  const rnd = wp8Rnd(777777);
  // The hostile alphabet, plus the shapes that are legal, so the property is
  // not vacuously about refusals.
  const pieces = ["..", ".", "/", "\\", ":", "\u0000", "Sales", "report", "%2e%2e", "~",
                  "C:", "CON", "NUL", "com1", " ", "'", "\u00e9", "x", "*", "?", "|", "<", ">", '"'];
  const clean = ["Sales", "report", "Layout", "Widgets", "x", "T1", "_a", "b'", "."];
  const draw = () => {
    // A THIRD OF THE DRAWS ARE PLAUSIBLE NAMES, deliberately: with the hostile
    // alphabet alone the property is only ever about refusals, and the thing it
    // has to pin is what the ACCEPTED paths look like.
    const alphabet = rnd(3) === 0 ? pieces : clean;
    let s = "";
    for (let i = rnd(5); i >= 0; i--) s += alphabet[rnd(alphabet.length)];
    return s;
  };
  const folders = { posix: "/w/space", win32: "C:\\w space" };
  const files = { posix: "/w/space/doc/S.e", win32: "C:\\w space\\doc\\S.e" };
  let accepted = 0, refused = 0;
  for (let i = 0; i < 6000; i++) {
    const flavour = rnd(2) === 0 ? "posix" : "win32";
    const p = path[flavour];
    const pick = core.makePick("file:///x", files[flavour], draw(), draw(), []);
    const out = core.paramsPaths(pick, folders[flavour], flavour);
    if (out.problem) { refused++; assert.ok(out.problem.message.length > 0); continue; }
    accepted++;
    // An INDEPENDENT containment check: `path.relative` (which the code under
    // test deliberately does not use) over two absolute paths.
    for (const key of ["previewDir", "dir", "paramsPath", "schemaPath", "gitignorePath"]) {
      const rel = p.relative(folders[flavour], out[key]);
      assert.ok(rel && !rel.startsWith("..") && !p.isAbsolute(rel),
                key + " = " + out[key] + " escaped " + folders[flavour] + " (rel " + rel + ")");
    }
    assert.match(out.schemaRef, /^\.\/[A-Za-z_][A-Za-z0-9_']*\.schema\.json$/);
  }
  // MEASURED on this seed: accepted=1593, refused=4407.
  assert.ok(accepted > 200 && refused > 2000, "accepted=" + accepted + " refused=" + refused);
});

// ------------------------------------------- D-1: a NESTED `$schema` stays illegal
//
// The S1 review found the design's own failure with the sign reversed: the
// injection went into the SHARED `$defs` entry, so for a recursive params type
// the editor ACCEPTED a nested `$schema` key that `paramsToSend` does not strip
// (G20 is top-level-only, deliberately) and that the server refuses --
// MEASURED against a real server as `400 "the key \"$schema\" is not allowed
// here"` (`json/Decode.scala:755-756` via `:848-849`).

const USER_TREE = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "user-tree.schema.json"), "utf8"));

test("D-1: a shared `$defs` entry is injected through a ROOT-LEVEL COPY, never in place", () => {
  // `Test.Tree` is the root `$ref`'s target AND what the `Node` arm's
  // `args.prefixItems` refer to -- the whole point of this fixture.
  assert.strictEqual(USER_TREE.$ref, "#/$defs/Test.Tree");
  assert.deepStrictEqual(USER_TREE.$defs["Test.Tree"].oneOf[1].properties.args.prefixItems,
                         [{ $ref: "#/$defs/Test.Tree" }, { $ref: "#/$defs/Test.Tree" }]);

  const file = core.schemaFileFor(USER_TREE);
  assert.strictEqual(file.$ref, "#/$defs/Test.Tree-params-root", "the ROOT points at the copy");
  assert.deepStrictEqual(Object.keys(file.$defs), ["Test.Tree", "Test.Tree-params-root"]);
  for (const arm of file.$defs["Test.Tree-params-root"].oneOf) {
    assert.deepStrictEqual(Object.keys(arm.properties), ["$schema", "tag", "args"], "the COPY carries it");
  }
  for (const arm of file.$defs["Test.Tree"].oneOf) {
    assert.deepStrictEqual(Object.keys(arm.properties), ["tag", "args"], "the SHARED entry does not");
  }
  // and the copy's own inner references still name the ORIGINAL, which is what
  // makes it one level of `$schema` and no more
  assert.deepStrictEqual(file.$defs["Test.Tree-params-root"].oneOf[1].properties.args.prefixItems,
                         [{ $ref: "#/$defs/Test.Tree" }, { $ref: "#/$defs/Test.Tree" }]);
  // the copy's name cannot collide with an exporter name: `Schema.sanitise`
  // (json/Schema.scala:721-722) turns every character that is not a letter, a
  // digit, `_` or `.` into `_`, so no exported $defs name holds a `-`
  assert.ok(Object.keys(USER_TREE.$defs).every((n) => n.indexOf("-") < 0));
});

test("D-1: the editor and the server now agree in BOTH directions on UserTree", () => {
  const file = core.schemaFileFor(USER_TREE);
  const defs = file.$defs;
  const bare = { tag: "Node", args: [{ tag: "Leaf", args: [0] }, { tag: "Leaf", args: [1] }] };
  assert.strictEqual(validates(file, bare, defs, 0), true, "a plain value validates");

  // TOP LEVEL: accepted, because that is the line we write and `paramsToSend`
  // strips it before the request goes out.
  const top = Object.assign({ $schema: "./report.schema.json" }, bare);
  assert.strictEqual(validates(file, top, defs, 0), true);
  assert.deepStrictEqual(core.paramsToSend(JSON.stringify(top)).params, bare, "and it IS stripped");

  // NESTED: refused. This is the case that used to be accepted.
  const nested = { tag: "Node",
                   args: [Object.assign({ $schema: "./report.schema.json" }, bare.args[0]), bare.args[1]] };
  assert.strictEqual(validates(file, nested, defs, 0), false,
                     "a nested `$schema` must squiggle -- the server 400s on it");
  // and `paramsToSend` does NOT strip it, which is why the schema has to refuse it
  assert.strictEqual(core.paramsToSend(JSON.stringify(nested)).params.args[0].$schema,
                     "./report.schema.json", "G20 is top-level-only, on purpose");
  // the RAW exported schema refuses it too, at both levels -- the file is never
  // more permissive than the server except for the one key we strip
  assert.strictEqual(validates(USER_TREE, nested, USER_TREE.$defs, 0), false);
  assert.strictEqual(validates(USER_TREE, top, USER_TREE.$defs, 0), false);
});

test("D-1: the skeleton still validates against the file, and the copy is not minted twice", () => {
  const file = core.schemaFileFor(USER_TREE);
  const out = core.skeletonFrom(USER_TREE, TODAY, "./report.schema.json");
  assert.deepStrictEqual(out.value, { $schema: "./report.schema.json", tag: "Leaf", args: [0] });
  assert.strictEqual(validates(file, out.value, file.$defs, 0), true);
  // IDEMPOTENT: the root `$ref` already names the copy, the copy is referenced
  // by nothing else, and its properties already declare `$schema`.
  const twice = core.schemaFileFor(file);
  assert.strictEqual(core.schemaFileText(twice), core.schemaFileText(file));
  assert.deepStrictEqual(Object.keys(twice.$defs), ["Test.Tree", "Test.Tree-params-root"]);
});

test("D-1: an entry reached ONLY from the root is still injected in place (Sales is unchanged)", () => {
  // The copy is not minted speculatively: `Sales.Query` is named by the root
  // `$ref` and by nothing else, so the file stays exactly as it was before the
  // fix -- which is what section 6's S1 done-when says.
  const file = core.schemaFileFor(SALES_SCHEMA);
  assert.deepStrictEqual(Object.keys(file.$defs), ["Sales.Query", "Sales.Sort"], "no copy");
  assert.strictEqual(file.$ref, "#/$defs/Sales.Query");
  assert.ok(Object.prototype.hasOwnProperty.call(file.$defs["Sales.Query"].properties, "$schema"));
});

test("D-1: nothing is copied when the injection would change nothing", () => {
  // A shared entry that is an enum, or an OPEN object, has nowhere to put a
  // `$schema` key, so no copy is minted and the file keeps the exporter's shape.
  const sharedEnum = { $ref: "#/$defs/M.S",
                       $defs: { "M.S": { enum: ["A", "B"] },
                                "M.T": { type: "object", properties: { s: { $ref: "#/$defs/M.S" } },
                                         required: ["s"], additionalProperties: false } } };
  assert.deepStrictEqual(Object.keys(core.schemaFileFor(sharedEnum).$defs), ["M.S", "M.T"]);
  const sharedOpen = { $ref: "#/$defs/M.O",
                       $defs: { "M.O": { type: "object", properties: { a: { type: "string" } },
                                         required: ["a"], additionalProperties: true },
                                "M.U": { type: "object", properties: { o: { $ref: "#/$defs/M.O" } },
                                         required: ["o"], additionalProperties: false } } };
  const openFile = core.schemaFileFor(sharedOpen);
  assert.deepStrictEqual(Object.keys(openFile.$defs), ["M.O", "M.U"]);
  assert.strictEqual(openFile.$ref, "#/$defs/M.O");
});

test("D-1: a hand-edited file that already took the copy's name does not lose its entry", () => {
  const taken = { $ref: "#/$defs/M.T",
                  $defs: { "M.T": { type: "object", properties: { t: { $ref: "#/$defs/M.T" } },
                                    required: [], additionalProperties: false },
                           "M.T-params-root": { const: "mine" } } };
  const file = core.schemaFileFor(taken);
  assert.deepStrictEqual(file.$defs["M.T-params-root"], { const: "mine" }, "not overwritten");
  assert.strictEqual(file.$ref, "#/$defs/M.T-params-root-");
  assert.ok(Object.prototype.hasOwnProperty.call(file.$defs["M.T-params-root-"].properties, "$schema"));
});

// ------------------------------------------------------- I-1 and I-2

test("I-1: a `__proto__` key is kept as DATA and never re-prototypes the answer", () => {
  // `JSON.parse` makes `__proto__` an ordinary OWN property and `Object.keys`
  // hands it over -- but `obj[key] = v` reaches `Object.prototype`'s setter.
  // MEASURED before the fix: the key vanished and `"polluted" in params` was
  // TRUE. The wire payload was safe either way; the glue that reads this
  // object with `in` / `for...in` / spread was not.
  const text = '{"__proto__":{"polluted":1},"a":1}';
  assert.deepStrictEqual(Object.keys(JSON.parse(text)), ["__proto__", "a"], "it IS an own key");
  const out = core.paramsToSend(text);
  assert.ok(Object.prototype.hasOwnProperty.call(out.params, "__proto__"), "kept, as data");
  assert.deepStrictEqual(out.params.__proto__, { polluted: 1 });
  assert.strictEqual(Object.getPrototypeOf(out.params), Object.prototype, "the prototype is untouched");
  assert.strictEqual("polluted" in out.params, false);
  assert.strictEqual({}.polluted, undefined, "and Object.prototype is never polluted");
  assert.strictEqual(JSON.stringify(out.params), '{"__proto__":{"polluted":1},"a":1}',
                     "the key survives to the wire");
  assert.deepStrictEqual(Object.keys(out.params), ["__proto__", "a"]);
  // and a top-level `$schema` is still the only key ever removed
  assert.deepStrictEqual(Object.keys(core.paramsToSend('{"$schema":"x","__proto__":1}').params),
                         ["__proto__"]);
});

test("I-1: a required `__proto__` in a schema is a skeleton key, not a false `unsatisfiable`", () => {
  // PARSED, not written as a literal: `{"__proto__": x}` in an object LITERAL
  // is prototype-setting syntax and makes no own property at all, so a literal
  // would not be the schema a real `.schema.json` file parses to. (Learned the
  // hard way writing this test -- worth the two lines.)
  const schema = JSON.parse(
    '{"type":"object","properties":{"__proto__":{"type":"integer"},"a":{"type":"string"}},' +
    '"required":["__proto__","a"],"additionalProperties":false}');
  const out = core.skeletonFrom(schema, TODAY);
  assert.strictEqual(out.problem, undefined, JSON.stringify(out.problem));
  assert.strictEqual(JSON.stringify(out.value), '{"__proto__":0,"a":""}');
  assert.strictEqual(Object.getPrototypeOf(out.value), Object.prototype);
  assert.strictEqual({}.polluted, undefined);
  // the required-key-with-no-schema arm too
  const open = JSON.parse('{"type":"object","properties":{},"required":["__proto__"],"additionalProperties":true}');
  assert.strictEqual(JSON.stringify(core.skeletonFrom(open, TODAY).value), '{"__proto__":null}');
});

test("I-2: a UTF-8 BOM is not a syntax error (VS Code writes one under files.encoding utf8bom)", () => {
  const out = core.paramsToSend('﻿{"fromDay":"2026-01-05"}');
  assert.strictEqual(out.problem, undefined, JSON.stringify(out.problem));
  assert.deepStrictEqual(out.params, { fromDay: "2026-01-05" });
  // ONE bom, and only a leading one: a stray U+FEFF anywhere else is still a
  // genuine syntax error and still reports itself
  assert.strictEqual(core.paramsToSend('﻿﻿{"a":1}').problem.reason, "invalid-json");
  assert.strictEqual(core.paramsToSend('{"a":1}﻿').problem.reason, "invalid-json");
  // a BOM-only file is still the EMPTY case, not a parse error (trim() drops it)
  assert.strictEqual(core.paramsToSend("﻿").problem.reason, "empty");
  assert.strictEqual(core.paramsToSend("﻿  \n").problem.reason, "empty");
  // THE CAP COUNTS THE BOM: it is a bound on the file as read off the disk, so
  // "the file is N bytes" in the refusal matches what the developer's tools say
  assert.strictEqual(Buffer.byteLength('﻿{"a":1}', "utf8"), 3 + 7);
  assert.strictEqual(core.paramsToSend('﻿{"a":1}', 9).problem.reason, "too-large");
  assert.match(core.paramsToSend('﻿{"a":1}', 9).problem.message, /is 10 bytes/);
  assert.strictEqual(core.paramsToSend('﻿{"a":1}', 10).problem, undefined);
});

/** Every object position in a value, as a path of keys and indices; `[]` is
  * the root. Used to put a `$schema` key everywhere it could go. */
function objectPaths(value, prefix, out) {
  if (Array.isArray(value)) {
    value.forEach((v, i) => objectPaths(v, prefix.concat([i]), out));
  } else if (value && typeof value === "object") {
    out.push(prefix);
    for (const key of Object.keys(value)) objectPaths(value[key], prefix.concat([key]), out);
  }
  return out;
}

/** A copy of `value` with `$schema` added at `path`. */
function withSchemaAt(value, path) {
  const copy = JSON.parse(JSON.stringify(value));
  let node = copy;
  for (const step of path) node = node[step];
  node.$schema = "./report.schema.json";
  return copy;
}

/**
 * WHERE, IN A SCHEMA FILE, A `$ref` STANDS AT THE INSTANCE'S ROOT.
 *
 * The document itself (`{"$ref": ...}`), and anything reachable from it
 * through `oneOf`/`anyOf` alone -- a branching keyword picks BETWEEN
 * descriptions of the same position, so an alternative of an alternative is
 * still the root.  Every `$ref` under `properties`, `items` or `prefixItems`
 * names a NESTED position instead, because those keywords step INTO a value.
 *
 * This is read off JSON Schema's own semantics and the exporter's output
 * shape, not off `preview-core.js`: it takes no view on how the injector
 * decides anything, only on where a value can sit.
 *
 * (Written one level deep at first, which the property below then failed on a
 * generated `anyOf` inside an `anyOf`. The helper was wrong, not the code --
 * worth recording, because a too-narrow oracle is the way a property lies.)
 */
function rootLevelRefNodes(file) {
  const nodes = [];
  const visit = (node, depth) => {
    if (!node || typeof node !== "object" || depth > 50) return;
    if (typeof node.$ref === "string") nodes.push(node);
    for (const key of ["oneOf", "anyOf"]) {
      if (Array.isArray(node[key])) node[key].forEach((alt) => visit(alt, depth + 1));
    }
  };
  visit(file, 0);
  return nodes;
}

/** Does any node under `node` declare a `$schema` PROPERTY? */
function declaresSchemaKey(node) {
  if (!node || typeof node !== "object") return false;
  if (Array.isArray(node)) return node.some(declaresSchemaKey);
  if (node.properties && typeof node.properties === "object" &&
      Object.prototype.hasOwnProperty.call(node.properties, "$schema")) return true;
  return Object.keys(node).some((k) => declaresSchemaKey(node[k]));
}

/** Every `$ref` node in the document, with the ones standing at the instance
  * root marked, so "is this entry reachable from a nested position" can be
  * asked without borrowing the implementation's own answer. */
function allRefNodes(node, out) {
  if (!node || typeof node !== "object") return out;
  if (Array.isArray(node)) { node.forEach((x) => allRefNodes(x, out)); return out; }
  if (typeof node.$ref === "string") out.push(node);
  for (const key of Object.keys(node)) allRefNodes(node[key], out);
  return out;
}

/**
 * THE STRUCTURAL HALF OF D-1, as one assertion over a finished schema file:
 * a `$defs` entry that carries a `$schema` property must be named ONLY by
 * root-level `$ref`s.  If a nested `$ref` can reach it, the editor accepts a
 * nested `$schema` that `paramsToSend` does not strip and the server 400s.
 *
 * KNOWN BLIND SPOT, recorded rather than fixed: it does not follow a CHAINED
 * `$ref` (root -> `A`, where `A` is itself `{"$ref": "#/$defs/B"}`), so it
 * would put `B` in the wrong class.  The exporter never chains one -- a
 * `$defs` body is an arm object, a `oneOf` of arms, or an `enum`
 * (`json/Schema.scala:526-532`) -- and `generateSchema` never draws one, so
 * no schema this code can be handed reaches it.  `allowSchemaKey` itself
 * follows chains correctly; it is the ORACLE that is narrow here.
 */
function assertSchemaKeyIsRootOnly(file, what) {
  const defs = file.$defs && typeof file.$defs === "object" ? file.$defs : {};
  const rootRefs = new Set(rootLevelRefNodes(file));
  const all = allRefNodes(file, []);
  for (const name of Object.keys(defs)) {
    if (!declaresSchemaKey(defs[name])) continue;
    const target = "#/$defs/" + name;
    for (const node of all) {
      if (node.$ref !== target) continue;
      assert.ok(rootRefs.has(node),
                what + ": `" + name + "` declares a `$schema` property and is named from a NESTED " +
                "position, so the editor would accept a nested `$schema` the server refuses");
    }
  }
}

test("D-1 (structural): a `$schema`-carrying entry is reachable ONLY from the instance root", () => {
  assertSchemaKeyIsRootOnly(core.schemaFileFor(USER_TREE), "UserTree");
  assertSchemaKeyIsRootOnly(core.schemaFileFor(SALES_SCHEMA), "Sales");
  // and the check has teeth: the PRE-FIX behaviour (inject into the shared
  // entry in place) is exactly what it refuses.
  const broken = JSON.parse(JSON.stringify(USER_TREE));
  delete broken.$id;
  for (const arm of broken.$defs["Test.Tree"].oneOf) {
    arm.properties = Object.assign({ $schema: { type: "string" } }, arm.properties);
  }
  assert.throws(() => assertSchemaKeyIsRootOnly(broken, "the pre-fix shape"), /NESTED position/);
});

test("PROPERTY: a `$schema` key is legal ONLY at the TOP LEVEL of the instance (D-1)", () => {
  // THE INVARIANT, in one line: THE SCHEMA FILE WE WRITE IS NEVER MORE
  // PERMISSIVE THAN THE SCHEMA THE SERVER EXPORTED -- except for exactly one
  // key, at exactly one place, which `paramsToSend` strips before the request
  // goes out. Anything else the editor accepts is a 400 the developer gets
  // after the squiggle told them it was fine.
  //
  // TWO HALVES, because neither alone is enough. The STRUCTURAL half catches
  // the D-1 shape even when no skeleton instance exhibits it -- and none does,
  // because a skeleton of a recursive type takes the base arm and so has no
  // nested occurrence of itself. The INSTANCE half is the semantic complement:
  // it puts a `$schema` at every object position of a real value and compares
  // the file's verdict with the server's.
  const rnd = wp8Rnd(31313131);
  let files = 0, clones = 0, rootChecked = 0, nestedClosed = 0, nestedOpen = 0;
  for (let i = 0; i < 12000; i++) {
    const schema = generateSchema(rnd);
    const file = core.schemaFileFor(schema);
    files++;
    if (Object.keys(file.$defs || {}).some((n) => n.indexOf("-params-root") >= 0)) clones++;
    assertSchemaKeyIsRootOnly(file, "generated #" + i);
    const out = core.skeletonFrom(schema, TODAY, "./report.schema.json");
    if (out.problem || !out.embeddable) continue;
    const bare = core.skeletonFrom(schema, TODAY).value;
    for (const p of objectPaths(bare, [], [])) {
      const mutated = withSchemaAt(bare, p);
      const byFile = validates(file, mutated, file.$defs, 0);
      const byServer = validates(schema, mutated, schema.$defs, 0);
      if (p.length === 0) {
        rootChecked++;
        assert.strictEqual(byFile, true,
                           "the top-level line must NOT squiggle: " + JSON.stringify(mutated));
        assert.deepStrictEqual(core.paramsToSend(JSON.stringify(mutated)).params, bare,
                               "and it must be stripped before the request");
      } else if (byServer) {
        nestedOpen++;                                          // an open (Spread) object: legal both ways
      } else {
        nestedClosed++;
        assert.strictEqual(byFile, false,
                           "a nested `$schema` the SERVER refuses must be refused by the FILE too, at " +
                           JSON.stringify(p) + " of " + JSON.stringify(mutated));
      }
    }
  }
  // MEASURED on this seed: files=12000, clones=2398 (the D-1 fix firing),
  // rootChecked=6679, nestedClosed=482, nestedOpen=37. Every arm has to be
  // reached or the property is testing less than it claims. `nestedOpen` is
  // THIN and recorded as thin: a skeleton is the smallest value that decodes,
  // so a nested object appears only for a required object-typed field, and an
  // OPEN one only when that field's type also carries a Spread.
  assert.deepStrictEqual(
    [clones > 500, rootChecked > 2000, nestedClosed > 300, nestedOpen > 20],
    [true, true, true, true],
    "files=" + files + " clones=" + clones + " rootChecked=" + rootChecked +
    " nestedClosed=" + nestedClosed + " nestedOpen=" + nestedOpen);
});

test("PROPERTY: the generator draws OPEN objects, so the short-circuit branch is exercised", () => {
  // The S1 review measured `additionalProperties: true` at COUNT 0 over the
  // shipped draws. It is the one branch `allowSchemaKey` returns early on, and
  // the one place a nested `$schema` is legitimately legal, so it is drawn now.
  const rnd = wp8Rnd(20260921);
  let open = 0, closed = 0;
  const count = (node) => {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) return node.forEach(count);
    if (node.type === "object") { if (node.additionalProperties === true) open++; else closed++; }
    for (const key of Object.keys(node)) count(node[key]);
  };
  for (let i = 0; i < 2000; i++) count(generateSchema(rnd));
  // MEASURED on this seed: open=577, closed=6873.
  assert.ok(open > 200 && closed > 2000, "open=" + open + " closed=" + closed);
});

test("schemaFile: a schema whose own KEYS are named `__proto__` is copied as data", () => {
  // PARSED, never a literal: `{"__proto__": x}` in an object literal is
  // prototype-setting syntax and makes no own property, so a literal cannot
  // express the file this test is about.
  //
  // Unreachable from the exporter (`Schema.defName` builds `<module>.<type>`,
  // and `__proto__` is not an Ermine field name), reachable from a hand-edited
  // `.schema.json`, and it used to fail SILENTLY: `cloneJson`'s `out[key] = `
  // hit `Object.prototype`'s setter. MEASURED before the fix: a `properties`
  // key called `__proto__` disappeared from the written file, and a `$defs`
  // ENTRY called `__proto__` vanished entirely, leaving the root `$ref`
  // dangling at a name the file no longer defined.
  const props = JSON.parse('{"type":"object","properties":{"__proto__":{"type":"integer"},' +
                           '"a":{"type":"string"}},"required":["a"],"additionalProperties":false}');
  const file = core.schemaFileFor(props);
  assert.deepStrictEqual(Object.keys(file.properties), ["$schema", "__proto__", "a"],
                         "the key survives AND `$schema` is still first");
  assert.deepStrictEqual(file.properties.__proto__, { type: "integer" });
  assert.strictEqual(Object.getPrototypeOf(file.properties), Object.prototype);
  assert.strictEqual({}.type, undefined, "and Object.prototype is never polluted");

  const entry = JSON.parse(
    '{"$ref":"#/$defs/__proto__","$defs":{' +
    '"__proto__":{"type":"object","properties":{"a":{"type":"string"}},"required":["a"],' +
    '"additionalProperties":false},' +
    '"M.T":{"type":"object","properties":{"p":{"$ref":"#/$defs/__proto__"}},"required":["p"],' +
    '"additionalProperties":false}}}');
  const entryFile = core.schemaFileFor(entry);
  assert.ok(Object.prototype.hasOwnProperty.call(entryFile.$defs, "__proto__"), "the entry survives");
  assert.strictEqual(entryFile.$ref, "#/$defs/__proto__-params-root");
  assert.ok(Object.prototype.hasOwnProperty.call(entryFile.$defs, "__proto__-params-root"),
            "and the root `$ref` is not left dangling");
  // the shared entry is still shared and still uninjected, as D-1 requires
  assert.deepStrictEqual(Object.keys(entryFile.$defs["__proto__"].properties), ["a"]);
  assert.deepStrictEqual(Object.keys(entryFile.$defs["__proto__-params-root"].properties),
                         ["$schema", "a"]);
  assertSchemaKeyIsRootOnly(entryFile, "a $defs entry named __proto__");
});

test("schemaFile: the S3 OBLIGATION -- a copy tracks its original only WITHIN one call", () => {
  // `schemaFileFor` is a pure function of what it is handed. It cannot diff a
  // root-level copy against a LATER version of the entry it was cloned from,
  // so S3 must always feed it the server's fresh `ermine/schema` answer and
  // must never read its own written `.schema.json` back in. This test does the
  // forbidden thing on purpose, so the consequence is recorded rather than
  // discovered.
  const written = core.schemaFileFor(USER_TREE);
  const drifted = JSON.parse(JSON.stringify(written));
  drifted.$defs["Test.Tree"].oneOf[0].properties.note = { type: "string" };   // the params type changed
  const again = core.schemaFileFor(drifted);
  assert.ok(Object.prototype.hasOwnProperty.call(again.$defs["Test.Tree"].oneOf[0].properties, "note"),
            "the shared entry has the new field");
  assert.ok(!Object.prototype.hasOwnProperty.call(
              again.$defs["Test.Tree-params-root"].oneOf[0].properties, "note"),
            "THE COPY IS STALE -- this is why S3 must pass the FRESH answer, never its own file");
  // and the fresh answer gets it right, which is the whole remedy
  const fresh = JSON.parse(JSON.stringify(USER_TREE));
  fresh.$defs["Test.Tree"].oneOf[0].properties.note = { type: "string" };
  fresh.$defs["Test.Tree"].oneOf[0].required.push("note");
  const correct = core.schemaFileFor(fresh);
  assert.ok(Object.prototype.hasOwnProperty.call(
              correct.$defs["Test.Tree-params-root"].oneOf[0].properties, "note"));
  assert.deepStrictEqual(core.skeletonFrom(fresh, TODAY).value, { tag: "Leaf", args: [0], note: "" });
});

// ======================================================= WP-8 S2: SENDING IT
//
// S1 decided WHERE a params file lives and WHAT its text becomes.  S2 is the
// glue: read it off the disk at SEND time, send it, re-render when it
// changes.  Three kinds of test live below, in this order:
//
//   1. the new PURE decisions -- which workspace folder owns the report, what
//      a failed read means, and the one this stage exists for, "after the
//      read, may this render still be sent?";
//   2. an ASYNC MODEL of `renderNow`'s send path, in the style of
//      `restartModel` above, because the read puts an `await` between
//      deciding to render and sending -- and a decision applied to state that
//      moved under it is the defect this code base has already been bitten by
//      three times (WP-22's M1, its M2, and the final re-check's timed-out
//      stop).  Every interleaving is driven by hand and each of the four
//      mutants the brief names is run against the same sequences;
//   3. the guard's `params` event end to end: what clears the wedge mark and
//      what must not.

// ------------------------------------------------------ paramsFolderFor (G1)

test("S2: the workspace folder is the one CONTAINING the report, never folders[0] (G1)", () => {
  // `rootsFor` falls back to folders[0] for a SETTING. Doing that for a FILE
  // would read -- and in S3 write -- `.ermine/preview/` inside whichever
  // repository happens to be first in the window.
  const folders = ["/first", "/w"];
  assert.strictEqual(core.paramsFolderFor("/w/doc/Sales.e", folders, "posix"), "/w");
  assert.strictEqual(core.paramsFolderFor("/tmp/wp7/WpSpin.e", folders, "posix"), null);
  assert.strictEqual(core.paramsFolderFor("/w/doc/Sales.e", [], "posix"), null);
  assert.strictEqual(core.paramsFolderFor("/w/doc/Sales.e", undefined, "posix"), null);
  assert.strictEqual(core.paramsFolderFor(undefined, folders, "posix"), null);
  // A folder is not inside itself, and a prefix sibling is not a parent.
  assert.strictEqual(core.paramsFolderFor("/w", ["/w"], "posix"), null);
  assert.strictEqual(core.paramsFolderFor("/workspace-old/S.e", ["/workspace"], "posix"), null);
});

test("S2: with nested workspace folders the INNERMOST one owns the report", () => {
  // VS Code allows a folder nested inside another in one window (external).
  // The params file belongs beside the report, in the folder the developer
  // actually opened it from.
  const nested = ["/w", "/w/sub", "/elsewhere"];
  assert.strictEqual(core.paramsFolderFor("/w/sub/doc/Sales.e", nested, "posix"), "/w/sub");
  assert.strictEqual(core.paramsFolderFor("/w/doc/Sales.e", nested, "posix"), "/w");
  // Order in the array must not decide it.
  assert.strictEqual(core.paramsFolderFor("/w/sub/doc/Sales.e", nested.slice().reverse(), "posix"), "/w/sub");
});

test("S2: the folder rule is tested on win32 too, case-insensitively", () => {
  const folders = ["C:\\First", "C:\\W"];
  assert.strictEqual(core.paramsFolderFor("C:\\w\\doc\\Sales.e", folders, "win32"), "C:\\W");
  assert.strictEqual(core.paramsFolderFor("D:\\other\\Sales.e", folders, "win32"), null);
});

test("S2: the params path is also answered as a folder-relative GLOB, for the watcher", () => {
  const p = core.paramsPaths(SALES_PICK, "/w", "posix");
  // `createFileSystemWatcher(new RelativePattern(folder, glob))` is what
  // reports a file whose DIRECTORY does not exist yet -- `.ermine/preview/`
  // is not there until S3 or the developer writes it.
  assert.strictEqual(p.relativeGlob, ".ermine/preview/Sales/report.params.json");
  // A glob is forward-slashed on every platform: it is not a path.
  const win = core.paramsPaths(
    core.makePick("file:///c/w/Sales.e", "C:\\w\\doc\\Sales.e", "report", "Sales", []), "C:\\w", "win32");
  assert.strictEqual(win.relativeGlob, ".ermine/preview/Sales/report.params.json");
  assert.strictEqual(win.paramsPath, "C:\\w\\.ermine\\preview\\Sales\\report.params.json");
});

// ----------------------------------------------------------- meansFileMissing

test("S2: a read failure that means NO SUCH FILE, and every one that does not", () => {
  // Missing is the ordinary case and renders with `{}`. Everything else is a
  // file we could not read, which REFUSES -- rendering `{}` over parameters
  // that exist is the silent-wrong-document failure S1 refused an empty file
  // for.
  for (const code of ["FileNotFound", "ENOENT", "ENOTDIR", "EntryNotFound"]) {
    assert.strictEqual(core.meansFileMissing({ code }), true, code);
    assert.strictEqual(core.meansFileMissing({ name: code }), true, "name " + code);
  }
  assert.strictEqual(core.meansFileMissing({ code: "EACCES" }), false);
  assert.strictEqual(core.meansFileMissing({ code: "NoPermissions" }), false);
  assert.strictEqual(core.meansFileMissing(new Error("something went wrong")), false);
  assert.strictEqual(core.meansFileMissing({}), false);
  assert.strictEqual(core.meansFileMissing(undefined), false);
  assert.strictEqual(core.meansFileMissing(null), false);
});

// ---------------------------------------------------------------- the gap

const OTHER_PICK = core.makePick("file:///w/doc/Other.e", "/w/doc/Other.e", "report", "Other", ["/w/doc"]);

function atSend(over) {
  return Object.assign({ generation: 7, pick: SALES_PICK, clientEpoch: 3 }, over);
}
function atNow(over) {
  return Object.assign({ generation: 7, pick: SALES_PICK, clientEpoch: 3, hasClient: true }, over);
}

test("S2: THE ASYNC GAP -- every way the world can move under a render, named", () => {
  assert.deepStrictEqual(core.mayStillSend(atSend(), atNow()), { send: true, reason: null, why: null });

  const cases = [
    ["pick-cleared", atNow({ pick: undefined })],
    ["pick-changed", atNow({ pick: OTHER_PICK })],
    ["roots-changed", atNow({ pick: core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales", ["/w/other"]) })],
    ["superseded", atNow({ generation: 8 })],
    ["server-restarted", atNow({ clientEpoch: 4 })],
    ["no-client", atNow({ hasClient: false })],
  ];
  for (const [reason, now] of cases) {
    const v = core.mayStillSend(atSend(), now);
    assert.strictEqual(v.send, false, reason);
    assert.strictEqual(v.reason, reason);
    assert.ok(typeof v.why === "string" && v.why.length > 10, reason + ": " + v.why);
    assert.ok(core.ABANDON_REASONS.indexOf(v.reason) >= 0, "the vocabulary is closed: " + v.reason);
  }
  // Nothing at all to send.
  assert.strictEqual(core.mayStillSend(undefined, atNow()).send, false);
  assert.strictEqual(core.mayStillSend(atSend(), undefined).send, false);
  assert.strictEqual(core.mayStillSend(atSend({ pick: undefined }), atNow()).reason, "pick-cleared");
});

test("S2: the gap's order is most-specific-first, so the channel says something useful", () => {
  // Picking RENDERS, so a pick change always bumps the generation too. If the
  // generation were tested first every pick change would be reported as
  // "superseded", which names the symptom and not the event.
  const v = core.mayStillSend(atSend(), atNow({ pick: OTHER_PICK, generation: 8, clientEpoch: 4 }));
  assert.strictEqual(v.reason, "pick-changed");
  assert.match(v.why, /Other\.report/);
  // A restart does NOT bump the generation, so it is distinguishable.
  assert.strictEqual(core.mayStillSend(atSend(), atNow({ clientEpoch: 4 })).reason, "server-restarted");
  // The same pick object, re-made with the same fields, is the same pick:
  // the test is on the KEY and the roots, not on identity.
  const sameAgain = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales", ["/w/doc"]);
  assert.strictEqual(core.mayStillSend(atSend(), atNow({ pick: sameAgain })).send, true);
});

// -------------------------------------------------------------- the refusal

test("S2: a params refusal is shown in the tab through the SAME path every failure takes", () => {
  const bad = core.paramsToSend('{"fromDay": ');
  assert.ok(bad.problem, "the fixture must actually be invalid JSON");
  const answer = core.paramsRefusalAnswer(bad.problem, "/w/.ermine/preview/Sales/report.params.json", 9);

  assert.strictEqual(core.isOk(answer), false);
  // NOT a placement 404: `status` is null, because no server was asked.
  assert.strictEqual(answer.status, null);
  assert.strictEqual(core.isPlacement404(answer), false);
  // The named reason travels under its OWN key: `reason` is the server's
  // closed vocabulary on this wire (section 4, Q15) and minting a
  // client-side value into it would make the two indistinguishable later.
  assert.strictEqual(answer.reason, undefined);
  assert.strictEqual(answer.paramsProblem, "invalid-json");
  assert.strictEqual(answer.path, "/w/.ermine/preview/Sales/report.params.json");
  assert.strictEqual(answer.generation, 9);
  assert.match(answer.message, /not valid JSON/);
  assert.match(answer.message, /Nothing was sent to the language server/);

  // The tab shows the whole object, which is where the diagnostic lives.
  const shown = JSON.parse(core.tabContent(answer));
  assert.strictEqual(shown.paramsProblem, "invalid-json");
  assert.strictEqual(shown.ok, false);
});

test("S2: every paramsToSend refusal dresses as an answer, and each one names itself", () => {
  const cases = [
    ["invalid-json", "{"],
    ["empty", "   \n "],
    ["too-large", "[" + '"x",'.repeat(400) + '"x"]'],
  ];
  for (const [reason, text] of cases) {
    const out = reason === "too-large" ? core.paramsToSend(text, 64) : core.paramsToSend(text);
    assert.strictEqual(out.problem.reason, reason, JSON.stringify(out));
    const answer = core.paramsRefusalAnswer(out.problem, "/p.json", 1);
    assert.strictEqual(answer.paramsProblem, reason);
    assert.strictEqual(core.isOk(answer), false);
  }
  // It also accepts the whole `{problem: ...}` wrapper, since that is what
  // `paramsToSend` answers and what the glue holds.
  assert.strictEqual(core.paramsRefusalAnswer(core.paramsToSend("{"), "/p.json", 1).paramsProblem, "invalid-json");
});

test("S2: one notice per distinct problem per pick, and the missing-file sentence", () => {
  const a = core.paramsNoticeKey(SALES_PICK, "missing");
  assert.strictEqual(a, core.paramsNoticeKey(SALES_PICK, "missing"));
  assert.notStrictEqual(a, core.paramsNoticeKey(SALES_PICK, "no-module"));
  assert.notStrictEqual(a, core.paramsNoticeKey(OTHER_PICK, "missing"));
  // The key is the mark key's, so a pick with a different BINDING on the
  // same file is a different pick here too.
  const otherBinding = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report2", "Sales", ["/w/doc"]);
  assert.notStrictEqual(a, core.paramsNoticeKey(otherBinding, "missing"));

  const notice = core.paramsMissingNotice("/w/.ermine/preview/Sales/report.params.json");
  assert.match(notice, /no params file at/);
  assert.match(notice, /empty parameters/);
  assert.match(notice, /report\.params\.json/);
});

// ------------------------------------------------------------ markParamsFor

test("S2: the mark carries the params of the render that is OUT, else the last sent", () => {
  assert.deepStrictEqual(core.markParamsFor(undefined, { a: 1 }), { a: 1 });
  assert.deepStrictEqual(core.markParamsFor({ b: 2 }, { a: 1 }), { b: 2 });
  // `null` IS a value: a params file holding `null` is what a `Maybe`-rooted
  // report wants, so it must not fall through to the last one sent.
  assert.strictEqual(core.markParamsFor(null, { a: 1 }), null);
  assert.strictEqual(core.markParamsFor(undefined, undefined), undefined);
});

// ------------------------------------------- the async model of the send path
//
// A FAITHFUL MODEL OF `renderNow`'s FIRST HALF, statement for statement, with
// the two awaits it now has -- the params READ and the request itself -- held
// open by hand.  It calls the real pure decisions (`mayStillSend`,
// `guardReduce`, `renderParams`, `isCurrentGeneration`, `stuckEventApplies`)
// rather than restating them, so what is modelled is the ORDER and nothing
// else: what is captured before the read, what is re-checked after it, when
// the wedge latch is taken, and what is released on every exit.
//
// THE FOUR MUTANTS the brief names are options on the same model, so each is
// run against the SAME interleavings as the real code:
//   `mutantNoGap`            the read happens and the re-check does not;
//   `mutantGuardNotFed`      no `params` event, so nothing clears the mark;
//   `mutantRefusalSends`     a refusal that renders anyway;
//   (the fourth, both save events rendering twice, is the coalescer's and is
//    modelled separately below -- it is not on this path at all.)

function sendModel(opts) {
  const o = opts || {};
  // ITS OWN PICK OBJECT, always. `rootsChangeInPlace` below mutates it the
  // way the glue mutates `picked`, and a model that mutated a shared
  // constant would leak into every later test -- which it did, once,
  // immediately.
  const seed = o.pick || SALES_PICK;
  const m = {
    // M-1: the model's OWN `paramsPaths` answer, which its read-settlers
    // hand to `core.preparedParams` exactly as `prepareParams` does.
    paths: o.paths || core.paramsPaths(seed, "/w", "posix"),
    generation: 0,
    picked: core.makePick(seed.uri, seed.fsPath, seed.binding, seed.module, seed.roots),
    clientEpoch: 1,
    stopCount: 0,
    hasClient: true,
    disposed: false,
    mark: null,
    lastParamsSent: undefined,
    inFlight: null,
    renderInFlight: false,
    lastAnswer: undefined,
    lastServerAnswer: undefined,
    stuck: core.initialStuckState(),
    restart: core.initialRestartState(o.restart || 0),
    reads: [],      // one per render, settled with a `prepareParams` result
    wires: [],      // one per request that actually reached the wire
    sent: [],
    tabs: [],
    held: [],
    asked: [],
    heldRefusedToken: undefined,
    log: [],
    arms: [],
  };

  m.renderNow = async function renderNow(reason, reveal, trigger, scheduledAt) {
    if (!m.picked) return;
    if (!m.hasClient) { m.log.push("no client"); return; }
    m.generation += 1;
    // THE SNAPSHOT, built by the SAME function the glue builds it with.
    const attempt = core.renderAttempt(
      m.generation, m.picked, m.clientEpoch, m.stopCount, m.stuck.highWater);
    const mine = attempt.generation;
    const sentPick = attempt.pick;
    m.renderInFlight = true;

    const read = deferred();
    m.reads.push({ generation: mine, settle: read.settle });
    const prepared = await read.promise;

    const verdict = o.mutantNoGap
      ? { send: true, reason: null, why: null }
      : core.mayStillSend(
          attempt,
          core.previewNow(m.generation, m.picked, m.clientEpoch, m.stopCount, m.hasClient));
    if (!verdict.send) {
      m.log.push("abandoned " + mine + " (" + verdict.reason + ")");
      if (mine === m.generation) m.renderInFlight = false;
      return;
    }
    if (prepared.refusal && !o.mutantRefusalSends) {
      const refusal = core.paramsRefusalAnswer(prepared.refusal, prepared.path, mine);
      m.lastAnswer = refusal;                       // and NOT `lastServerAnswer`
      if (mine === m.generation) m.renderInFlight = false;
      m.tabs.push(refusal);
      m.log.push("refused " + mine + " (" + refusal.paramsProblem + ")");
      return;
    }
    if (!o.mutantGuardNotFed) {
      m.mark = core.guardReduce(m.mark, { type: "params", pick: sentPick, params: prepared.params }).mark;
    }
    // WP-22's ONE CONSULTATION, from its second place (S2 review M6), and
    // since the delta re-review through `mayAutoRender`, which also asks
    // whether the mark was minted AFTER this render was scheduled.
    const permitted = o.mutantNoHeldCheck
      ? { render: true, why: null }
      : core.mayAutoRender(m.mark, sentPick, trigger, scheduledAt);
    if (!permitted.render) {
      m.log.push("held " + mine + " (" + trigger + ")");
      m.held.push({ generation: mine, trigger, mark: m.mark, why: permitted.why });
      // D3: the glue asks `shouldAskHeld` here and remembers a refusal.
      const asking = core.shouldAskHeld(m.heldRefusedToken, m.mark, sentPick, trigger);
      m.asked.push({ generation: mine, trigger, ask: asking.ask, why: asking.why });
      if (mine === m.generation) m.renderInFlight = false;
      return;
    }
    m.lastParamsSent = prepared.params;
    m.inFlight = { generation: mine, pick: sentPick, params: prepared.params };
    const request = core.renderRequest(attempt, prepared.params);
    m.sent.push(request);
    m.log.push("sent " + mine);

    const wire = deferred();
    m.wires.push({ generation: mine, settle: wire.settle });
    let answer = await wire.promise;
    if (answer && answer.__reject) {
      if (core.rejectionMeansServerGone(answer.err)) {
        m.mark = core.guardReduce(m.mark, {
          type: "clientState", to: "Stopped", renderInFlight: true,
          pick: sentPick, params: prepared.params, at: 1,
        }).mark;
      }
      if (m.inFlight && m.inFlight.generation === mine) m.inFlight = null;
      answer = core.errorAnswer(answer.err, mine);
    } else if (m.inFlight && m.inFlight.generation === mine) {
      m.inFlight = null;
    }
    if (mine === m.generation) m.renderInFlight = false;
    if (!core.isCurrentGeneration(m.generation, answer)) {
      m.log.push("stale answer " + mine);
      return;
    }
    m.lastAnswer = answer;
    m.lastServerAnswer = answer;
    const stuckEvent = {
      type: "answer",
      stuck: !!(answer && answer.stuck === true),
      message: answer && answer.message,
      seqAtSend: attempt.seqAtSend,
    };
    const applies = core.stuckEventApplies(m.stuck, stuckEvent);
    m.mark = core.guardReduce(m.mark, {
      type: "answer", stuck: stuckEvent.stuck, applies,
      pick: sentPick, params: prepared.params, at: 1,
    }).mark;
    const r = core.restartReduce(m.restart, core.restartEvents.answer(stuckEvent.stuck, applies, 100000));
    m.restart = r.state;
    if (r.effects.arm) m.arms.push(r.effects);
    m.stuck = core.stuckReduce(m.stuck, stuckEvent).state;
    m.tabs.push(answer);
  };

  /**
   * **THE READ-SETTLERS CALL `core.preparedParams`, WHICH IS WHAT THE GLUE
   * CALLS (the S3 review's M-1).** They used to hand-write their own object
   * literals -- and so did `prepareParams` -- so a field could be present on
   * one side and absent on the other. It was: deleting the one word `paths,`
   * from the glue's missing-file literal turned the WHOLE of S3 off, with
   * 249 of 249 tests green (MEASURED by the review, reproduced by the
   * implementer). One builder, both sides, and the class is closed.
   *
   * `m.paths` is the model's `paramsPaths` answer, and the `paths` the
   * settler passes is the same object `paramsPathsFor` would answer.
   */
  m.readOk = (i, params, path) =>
    m.reads[i].settle(core.preparedParams(m.paths, { kind: core.PREPARED_READ, params, warnings: [] }));
  /** `prepareParams` answered: no file, `{}` and one notice. */
  m.readMissing = (i) =>
    m.reads[i].settle(core.preparedParams(m.paths, { kind: core.PREPARED_MISSING }));
  /** `prepareParams` answered: a refusal. */
  m.readRefusal = (i, reason) =>
    m.reads[i].settle(core.preparedParams(m.paths, {
      kind: core.PREPARED_REFUSAL,
      problem: { reason: reason || "invalid-json", message: "the params file is not valid JSON" } }));
  /** `prepareParams` answered: there is nowhere to write (a `paramsPaths` problem). */
  m.readNoPath = (i, paths) =>
    m.reads[i].settle(core.preparedParams(paths, { kind: core.PREPARED_PATH_PROBLEM }));
  m.answerWith = (i, answer) => m.wires[i].settle(answer);
  m.rejectWith = (i, err) => m.wires[i].settle({ __reject: true, err });
  /**
   * THE GLUE'S OWN MUTATIONS, spelled exactly as `extension.js` spells them.
   * `rootsChangeInPlace` is the one the S2 review's M1 turned on: the roots
   * handler assigns `picked.roots`, it does NOT replace the pick.
   */
  m.rootsChangeInPlace = (roots) => { m.picked.roots = roots.slice(); };
  m.serverStopped = () => { m.stopCount += 1; };            // onClientStopped
  m.serverRestarted = () => { m.clientEpoch += 1; };        // startClient
  m.tearDown = () => { m.disposed = true; m.picked = undefined; };   // disposePreview
  /** S4: `pickReport` REPLACES the pick with a fresh `core.makePick`, which
    * is how a pick change differs from `rootsChangeInPlace` above. */
  m.pickAnother = (binding) => {
    m.picked = core.makePick(m.picked.uri, m.picked.fsPath, binding, m.picked.module, m.picked.roots);
  };
  /** "Not now": the glue stores the token the question was shown with. */
  m.notNow = () => { m.heldRefusedToken = core.heldPromptToken(m.mark); };
  return m;
}


test("S2 ASYNC: the ordinary interleaving -- read, nothing moved, send what was read", async () => {
  const m = sendModel();
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  // THE LATCH IS NOT TAKEN WHILE READING: nothing is on the wire, so a
  // server death here is not "died mid-render".
  assert.strictEqual(m.inFlight, null, "the wedge latch must not be held during the read");
  assert.strictEqual(m.renderInFlight, true, "the spinner IS on: reading is this render working");
  m.readOk(0, { fromDay: "2026-01-05", toDay: "2026-03-17", orderBy: "ByDay" });
  await flush();
  assert.strictEqual(m.sent.length, 1);
  assert.deepStrictEqual(m.sent[0].params, { fromDay: "2026-01-05", toDay: "2026-03-17", orderBy: "ByDay" });
  assert.strictEqual(m.sent[0].generation, 1);
  assert.ok(m.inFlight, "the latch is taken for the request that IS out");
  assert.deepStrictEqual(m.inFlight.params, m.sent[0].params);
  m.answerWith(0, { ok: true, document: { t: "doc" }, generation: 1 });
  await flush();
  assert.strictEqual(m.inFlight, null, "a settled answer releases the latch");
  assert.strictEqual(m.renderInFlight, false);
  assert.strictEqual(m.tabs.length, 1);
  assert.strictEqual(m.tabs[0].ok, true);
});

test("S2 ASYNC: a PICK CHANGE during the read abandons -- the old file is never sent", async () => {
  const m = sendModel();
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  // The user picks another report while we are reading.
  m.picked = OTHER_PICK;
  m.generation += 1;                       // picking renders, so it bumps too
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  assert.deepStrictEqual(m.sent, [], "Sales's parameters must never be sent for Other");
  assert.strictEqual(m.inFlight, null, "no latch is taken for a render that is never sent");
  assert.match(m.log.join("|"), /abandoned 1 \(pick-changed\)/);
});

test("S2 ASYNC: a NEWER RENDER during the read abandons the older one, and only it", async () => {
  const m = sendModel();
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.renderNow("another save", false, core.TRIGGER_INVALIDATED);             // the coalescer let a second one through
  await flush();
  assert.strictEqual(m.reads.length, 2);
  m.readOk(0, { fromDay: "old" });         // the OLDER read finishes first
  await flush();
  assert.deepStrictEqual(m.sent, [], "the superseded render must not reach the wire");
  assert.match(m.log.join("|"), /abandoned 1 \(superseded\)/);
  m.readOk(1, { fromDay: "new" });
  await flush();
  assert.strictEqual(m.sent.length, 1);
  assert.deepStrictEqual(m.sent[0].params, { fromDay: "new" });
  assert.strictEqual(m.sent[0].generation, 2);
});

test("S2 ASYNC: a RESTART during the read abandons -- the fresh server is not fed behind the guard", async () => {
  const m = sendModel();
  m.renderNow("the server restarted", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.clientEpoch = 2;                       // restart(): a new client is current
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  assert.deepStrictEqual(m.sent, []);
  assert.match(m.log.join("|"), /abandoned 1 \(server-restarted\)/);
  // The same hole `fireRestart` clears the coalesced render for: a request
  // slipped into the fresh server here would never pass WP-22's one
  // consultation site.
  assert.strictEqual(m.inFlight, null);
});

test("S2 ASYNC: the client going away, and the roots changing, each abandon too", async () => {
  const gone = sendModel();
  gone.renderNow("x", false, core.TRIGGER_INVALIDATED);
  await flush();
  gone.hasClient = false;
  gone.readOk(0, {});
  await flush();
  assert.deepStrictEqual(gone.sent, []);
  assert.match(gone.log.join("|"), /abandoned 1 \(no-client\)/);

  // THE ROOTS CHANGE **IN PLACE**, WHICH IS THE ONLY SHAPE THE GLUE
  // PRODUCES (S2 review M1). The first cut of this test REPLACED the pick
  // object -- a shape `extension.js` never creates -- and so it passed while
  // the arm it was testing could not fire in the real extension at all.
  const roots = sendModel();
  roots.renderNow("x", false, core.TRIGGER_INVALIDATED);
  await flush();
  roots.rootsChangeInPlace(["/w/doc", "/w/extra"]);
  roots.readOk(0, {});
  await flush();
  assert.deepStrictEqual(roots.sent, []);
  assert.match(roots.log.join("|"), /abandoned 1 \(roots-changed\)/);
});

test("S2 ASYNC: M1 -- the snapshot COPIES the roots, so an in-place change is seen", () => {
  // THE DEFECT, REPRODUCED AT THE PURE LEVEL. `const sentPick = picked` is a
  // REFERENCE; the roots handler is `picked.roots = rootsFor(...)`, an
  // in-place mutation of that same object. Comparing `atSend.pick.roots`
  // with `now.pick.roots` then compared an array with ITSELF.
  const live = core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc"]);
  const reference = live;                       // what the first cut captured
  const snapshot = core.renderAttempt(1, live, 1, 0, 0);   // what it captures now
  live.roots = ["/w/doc", "/w/extra"];          // extension.js's roots handler

  assert.strictEqual(
    core.mayStillSend({ generation: 1, pick: reference, clientEpoch: 1, stopCount: 0 },
                      core.previewNow(1, live, 1, 0, true)).send,
    true, "MEASURED: the reference cannot see its own mutation -- this is the bug");
  const verdict = core.mayStillSend(snapshot, core.previewNow(1, live, 1, 0, true));
  assert.strictEqual(verdict.send, false);
  assert.strictEqual(verdict.reason, "roots-changed");

  // The snapshot is frozen all the way down, so nothing can edit it later.
  assert.ok(Object.isFrozen(snapshot) && Object.isFrozen(snapshot.pick) && Object.isFrozen(snapshot.pick.roots));
  assert.deepStrictEqual(snapshot.pick.roots, ["/w/doc"]);

  // AND THE ROOTS ARRAY ITSELF IS A COPY, not the same array frozen: a
  // snapshot that shared it would still see an ASSIGNMENT (which is what the
  // roots handler does today) and would be blind to a MUTATION of the array
  // in place -- a difference nothing in the glue relies on today and
  // everything would rely on tomorrow.
  const shared = core.makePick("file:///w/S.e", "/w/S.e", "report", "S", ["/w"]);
  const snap2 = core.renderAttempt(1, shared, 1, 0, 0);
  assert.notStrictEqual(snap2.pick.roots, shared.roots, "the arrays must not be the same object");
  shared.roots.push("/w/extra");
  assert.deepStrictEqual(snap2.pick.roots, ["/w"]);
  assert.strictEqual(
    core.mayStillSend(snap2, core.previewNow(1, shared, 1, 0, true)).reason, "roots-changed");
  // And the request built from it carries the roots as they were AT SEND.
  assert.deepStrictEqual(core.renderRequest(snapshot, {}).roots, ["/w/doc"]);
  assert.strictEqual(core.renderRequest(snapshot, {}).generation, 1);
});

test("S2 ASYNC: M5 -- a stop the library performs on the same client is seen", async () => {
  // `clientEpoch` moves only inside our own `startClient`. A restart
  // performed by `vscode-languageclient`'s default close action on the SAME
  // client object moves nothing -- so the counter `onClientStopped` bumps is
  // what notices. UNVERIFIED library behaviour; this is the defence.
  const m = sendModel();
  m.renderNow("x", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.serverStopped();                            // onClientStopped, no epoch change
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  assert.deepStrictEqual(m.sent, []);
  assert.match(m.log.join("|"), /abandoned 1 \(server-stopped\)/);
  assert.ok(core.ABANDON_REASONS.indexOf("server-stopped") >= 0);
});

test("S2 ASYNC: a TEARDOWN during the read abandons -- `pick-cleared` is reachable now", async () => {
  // Review nit 6: `picked` was never cleared, so this arm was dead and a
  // render in its read survived `deactivate()` and sent into a disposed
  // window. `disposePreview` now clears the pick, which is the event the
  // arm was documented for.
  const m = sendModel();
  m.renderNow("x", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.tearDown();
  m.readOk(0, {});
  await flush();
  assert.deepStrictEqual(m.sent, []);
  assert.match(m.log.join("|"), /abandoned 1 \(pick-cleared\)/);
});

test("S2 ASYNC: a REFUSAL shows in the tab, sends nothing, and releases everything", async () => {
  const m = sendModel();
  m.renderNow("a save", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readRefusal(0, "invalid-json");
  await flush();
  assert.deepStrictEqual(m.sent, [], "G7: the render does not happen");
  assert.strictEqual(m.inFlight, null, "nothing was taken, so nothing is held");
  assert.strictEqual(m.renderInFlight, false, "the status bar goes back to its idle state");
  assert.strictEqual(m.tabs.length, 1);
  assert.strictEqual(m.tabs[0].paramsProblem, "invalid-json");
  assert.strictEqual(m.tabs[0].generation, 1);
  assert.strictEqual(m.lastAnswer.ok, false);
  // A refusal is not a placement 404, so it cannot arm the Q11 watcher.
  assert.strictEqual(core.isPlacement404(m.lastAnswer), false);
});

test("S2 ASYNC: a refusal for a pick that has MOVED is not shown either", async () => {
  // The verdict is taken BEFORE the refusal is shown, on purpose: the file
  // that would not parse is the OLD report's, and a banner about it over the
  // new report's render is a lie.
  const m = sendModel();
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.picked = OTHER_PICK;
  m.generation += 1;
  m.readRefusal(0);
  await flush();
  assert.deepStrictEqual(m.tabs, []);
  assert.deepStrictEqual(m.sent, []);
  assert.match(m.log.join("|"), /abandoned 1 \(pick-changed\)/);
});

test("S2 ASYNC: a missing params file sends `{}` -- exactly what WP-7 measured", async () => {
  const m = sendModel();
  m.renderNow("the report was picked", false, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  assert.deepStrictEqual(m.sent[0].params, {}, "MEASURED (WP-7): `{}` names the first missing key, `null` names none");
  m.answerWith(0, { ok: false, status: 400, message: 'the required key "fromDay" is missing', path: "$.params", generation: 1 });
  await flush();
  assert.strictEqual(m.tabs[0].status, 400);
});

test("S2 ASYNC: a params file holding `null` is sent AS null, not coerced to `{}`", async () => {
  // `docs/JSON-GUIDE.md:1329-1331`: a `Maybe`-rooted report wants null, and
  // S1's skeleton mints exactly that. WP-7's `null -> {}` coercion would have
  // turned a correct file into a 400 nobody could explain.
  const m = sendModel();
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  const parsed = core.paramsToSend("null");
  assert.strictEqual(parsed.params, null);
  m.readOk(0, parsed.params);
  await flush();
  assert.strictEqual(m.sent[0].params, null);
});

test("S2 ASYNC: MUTANT -- the params are read but the gap is not re-checked", async () => {
  // This is the defect the whole stage is about: the decision to render is
  // applied to state that moved under it.
  for (const move of ["pick", "generation", "epoch"]) {
    const m = sendModel({ mutantNoGap: true });
    m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
    await flush();
    if (move === "pick") { m.picked = OTHER_PICK; m.generation += 1; }
    if (move === "generation") m.generation += 1;
    if (move === "epoch") m.clientEpoch = 2;
    m.readOk(0, { fromDay: "2026-01-05" });
    await flush();
    assert.strictEqual(m.sent.length, 1, "the mutant sends (" + move + ")");
    if (move === "pick") {
      // The wrong report's parameters, on the wrong pick's URI's behalf.
      assert.strictEqual(m.sent[0].uri, SALES_PICK.uri);
      assert.notStrictEqual(m.picked.uri, m.sent[0].uri);
    }
  }
  // And the shipped code sends none of them -- the assertions above are the
  // mutant's; the three interleaving tests above are the real code's.
});

test("S2 ASYNC: MUTANT -- a refusal that still sends renders yesterday's parameters", async () => {
  const m = sendModel({ mutantRefusalSends: true });
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readRefusal(0, "invalid-json");
  await flush();
  assert.strictEqual(m.sent.length, 1, "the mutant renders a file that does not parse");
  // `prepared.params` is undefined on a refusal, so what reaches the wire is
  // `{}` -- a document that looks like it worked, which is exactly why G7
  // makes an unparseable file a refusal.
  assert.deepStrictEqual(m.sent[0].params, {});
  assert.deepStrictEqual(m.tabs, []);
});

test("S2 ASYNC: a server death during the request still marks, and carries the params", async () => {
  const m = sendModel();
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.rejectWith(0, new Error("Connection got disposed"));
  await flush();
  assert.ok(m.mark, "M1: a rejection we cannot read as the peer's own answer marks");
  assert.strictEqual(m.mark.reason, core.WEDGE_DIED_MID_RENDER);
  // AND THE MARK CARRIES THE PARAMS THAT WERE SENT, which is what makes
  // changing them clear it.
  assert.strictEqual(m.mark.paramsFingerprint, core.paramsFingerprint({ fromDay: "2026-01-05" }));
  assert.notStrictEqual(m.mark.paramsFingerprint, core.paramsFingerprint({ fromDay: "2026-02-01" }));
});

// -------------------------------------- the wedge guard, fed with real params

test("S2 GUARD: a params CHANGE clears the wedge mark; a re-format does NOT", async () => {
  // WP-22 put `paramsFingerprint` in the mark's VALUE so that changing the
  // parameters CLEARS the mark rather than minting a second one, and said
  // WP-8 would hand it the params actually sent. This is that, end to end.
  const ORIGINAL = '{\n  "$schema": "./report.schema.json",\n  "fromDay": "2026-01-05",\n' +
                   '  "toDay": "2026-03-17",\n  "orderBy": "ByDay"\n}\n';
  const REFORMATTED = '{"orderBy":"ByDay","toDay":"2026-03-17","fromDay":"2026-01-05",' +
                      '"$schema":"./somewhere/else/report.schema.json"}';
  const CHANGED = '{"$schema":"./report.schema.json","fromDay":"2026-02-01",' +
                  '"toDay":"2026-03-17","orderBy":"ByDay"}';

  const m = sendModel();
  // 1. render, and the server answers that the preview is wedged.
  m.renderNow("the report was picked", false, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, core.paramsToSend(ORIGINAL).params);
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "evaluation did not finish", generation: 1, stuck: true });
  await flush();
  assert.ok(m.mark, "the wedged answer marks");
  assert.strictEqual(m.mark.paramsFingerprint, core.paramsFingerprint(core.paramsToSend(ORIGINAL).params));

  // 2. the developer re-formats the file and moves its `$schema` line.
  //    The mark STAYS, because nothing the server sees has changed -- and
  //    since the S2 review's M6 the render is therefore HELD rather than
  //    sent: this is the user's own sentence about a report that wedged
  //    "and it didn't change".
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(1, core.paramsToSend(REFORMATTED).params);
  await flush();
  assert.ok(m.mark, "a re-format and a changed $schema line are NOT a parameter change");
  assert.strictEqual(m.sent.length, 1, "and so the wedge is not re-issued");
  assert.strictEqual(m.held.length, 1);

  // 3. now a real change, and the mark goes.
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(2, core.paramsToSend(CHANGED).params);
  await flush();
  assert.strictEqual(m.mark, null, "changing fromDay clears the wedge mark");
});

test("S2 GUARD: while HELD, saving a changed params file clears the hold", async () => {
  const m = sendModel();
  m.renderNow("picked", false, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  assert.ok(core.markMatches(m.mark, m.picked), "the pick is held");
  assert.strictEqual(core.statusBarState({ pick: m.picked, mark: m.mark }).text, "$(warning) Ermine preview: held");
  assert.strictEqual(core.shouldAutoRender(m.mark, m.picked, core.TRIGGER_RESTART), false);

  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(1, { fromDay: "2026-02-01" });
  await flush();
  assert.strictEqual(m.mark, null);
  // And the status bar leaves `held` -- the report is no longer the one that
  // wedged with nothing changed since.
  assert.strictEqual(core.statusBarState({ pick: m.picked, mark: m.mark }).text, "$(json) Ermine: Sales.report");
  assert.strictEqual(core.shouldAutoRender(m.mark, m.picked, core.TRIGGER_RESTART), true);
});

test("S2 GUARD: MUTANT -- the guard is not fed, so a params change never clears the mark", async () => {
  const m = sendModel({ mutantGuardNotFed: true });
  m.renderNow("picked", false, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  assert.ok(m.mark);
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(1, { fromDay: "2026-02-01" });
  await flush();
  assert.ok(m.mark, "the mutant keeps the mark over a real parameter change");
  // The cost of that: the restart after it holds a report whose parameters
  // the developer already fixed, and the only way out is the question.
  assert.strictEqual(core.shouldAutoRender(m.mark, m.picked, core.TRIGGER_RESTART), false);
});

test("S2 GUARD: a params event for ANOTHER pick's mark clears it, and an empty file cannot", async () => {
  // `guardReduce`'s own rows, reached with real `paramsToSend` output rather
  // than with hand-written objects.
  const marked = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: SALES_PICK,
    params: core.paramsToSend('{"fromDay":"2026-01-05"}').params, at: 1,
  }).mark;
  assert.ok(marked);
  // A refusal has no params at all, so the glue sends no event and the mark
  // cannot move: an unparseable file is not evidence that anything changed.
  assert.ok(core.paramsToSend("{").problem);
  assert.strictEqual(core.guardReduce(marked, { type: "params", pick: SALES_PICK, params: undefined }).mark, null,
                     "an event with NO params is a different fingerprint and so a clear -- which is why the " +
                     "glue must not send one for a refusal");
  // The same params keep it.
  const same = core.guardReduce(marked, {
    type: "params", pick: SALES_PICK, params: core.paramsToSend('{"fromDay":"2026-01-05"}').params });
  assert.strictEqual(same.mark, marked);
});

test("S2: a 400 on bad params marks NOTHING, arms nothing, and leaves the latch released", async () => {
  // The server's 400 is authoritative and is a report that ran and was
  // refused, not a wedge. MEASURED shape (section 6's control C).
  const m = sendModel({ restart: 20 });
  m.renderNow("a save", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readOk(0, { fromDay: 5, toDay: "2026-03-17", orderBy: "ByDay" });
  await flush();
  m.answerWith(0, {
    ok: false, status: 400, generation: 1,
    message: "expected a date string yyyy-MM-dd, found the number 5",
    path: "$.params.fromDay",
  });
  await flush();
  assert.strictEqual(m.mark, null, "a 400 is not a wedge");
  assert.deepStrictEqual(m.arms, [], "and it arms no automatic restart");
  assert.strictEqual(m.inFlight, null, "the latch is released by the settled answer");
  assert.strictEqual(m.renderInFlight, false);
  assert.strictEqual(m.stuck.stuck, false);
  // The tab shows the whole refusal, which is where `path` and `message` are.
  const shown = JSON.parse(core.tabContent(m.tabs[0]));
  assert.strictEqual(shown.path, "$.params.fromDay");
  assert.match(shown.message, /found the number 5/);
  // And a MISSING key is reported at its object's path with the key in the
  // message -- the deviation WP-7 measured and section 3 of the checklist
  // records.
  const missing = { ok: false, status: 400, message: 'the required key "toDay" is missing', path: "$.params", generation: 2 };
  // (the tab is JSON, so the message's own quotes arrive escaped)
  assert.match(core.tabContent(missing), /\\"toDay\\" is missing/);
});

// ---------------------------------------------------- the coalescing window

/**
 * A MODEL OF `scheduleRender`'s 150 ms window, with a virtual clock.  The
 * window is glue -- it is a `setTimeout` in extension.js -- but WHAT IT
 * DECIDES (two triggers inside it cost one render) is testable, and S2 adds a
 * second trigger for the same file: `onDidSaveTextDocument` AND the params
 * file watcher both fire for one save in the editor.
 */
function coalesceModel(windowMs) {
  const renders = [];
  let timer = null;
  let now = 0;
  return {
    renders,
    schedule(reason) { timer = { at: now + windowMs, reason }; },
    tick(ms) {
      now += ms;
      if (timer && now >= timer.at) { renders.push(timer.reason); timer = null; }
    },
    cancel() { timer = null; },
  };
}

/** The real number, read out of the glue, so the model cannot drift from it. */
const COALESCE_MS = (() => {
  const fs = require("node:fs");
  const src = fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const m = /const COALESCE_MS = (\d+);/.exec(src);
  assert.ok(m, "source pin: extension.js no longer declares COALESCE_MS");
  return Number(m[1]);
})();

test("S2: ONE save that fires BOTH triggers costs ONE render", () => {
  const m = coalesceModel(COALESCE_MS);
  // The editor reports the save; the file system watcher reports the same
  // write. Whichever order they arrive in, and however close together.
  m.schedule("the params file was saved");
  m.tick(5);
  m.schedule("the params file was changed outside the editor");
  m.tick(COALESCE_MS + 1);
  assert.deepStrictEqual(m.renders, ["the params file was changed outside the editor"]);
  // The window is a coalescer, not a rate limiter: two real edits far apart
  // are two renders.
  m.schedule("edit one");
  m.tick(COALESCE_MS + 1);
  m.schedule("edit two");
  m.tick(COALESCE_MS + 1);
  assert.strictEqual(m.renders.length, 3);
});

test("S2: MUTANT -- both save events rendering directly costs TWO renders for one save", () => {
  // The mutant is "call renderNow instead of scheduleRender", which is what
  // a reader who did not know about the window would write.
  const direct = [];
  const renderNow = (reason) => direct.push(reason);
  renderNow("the params file was saved");
  renderNow("the params file was changed outside the editor");
  assert.strictEqual(direct.length, 2, "the mutant renders twice");
  // Two renders for one save means the second one supersedes the first,
  // which the server answers -32800 for -- a wasted boot's worth of work on
  // a save-driven loop.
  const m = coalesceModel(COALESCE_MS);
  m.schedule("a"); m.tick(5); m.schedule("b"); m.tick(COALESCE_MS + 1);
  assert.strictEqual(m.renders.length, 1, "the real code coalesces them");
});


// ================================ WP-8 S2, the independent review's must-fixes
//
// M6 IS THE USER'S OWN SENTENCE: "We'd want some sort of confirmation before
// rendering a report which wedged and was killed the first time around AND IT
// DIDN'T CHANGE."  The first cut of S2 re-issued the wedge when a params file
// was SAVED while `held` and its parameters had not moved -- a re-format, a
// format-on-save, a touched `$schema` line -- and the tracker recorded that as
// settled.  It is not settled; it is the loop.

test("S2 M6: the trigger vocabulary -- which triggers consult the mark and which do not", () => {
  const mark = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: SALES_PICK, params: { a: 1 }, at: 1 }).mark;
  assert.ok(core.markMatches(mark, SALES_PICK));

  // THE REFUSED SET IS CLOSED: a trigger that brings no evidence of change.
  for (const trigger of core.UNCONFIRMED_TRIGGERS) {
    assert.strictEqual(core.shouldAutoRender(mark, SALES_PICK, trigger), false, trigger);
  }
  // WP-8 S3 ADDED `schema` TO THE LIST, and the membership rule is what put
  // it there: the glue asks for a schema refresh on a render's ANSWER, and
  // `guardReduce`'s `answer` case KEEPS the mark for a non-stuck answer (it
  // only ever SETS). So it cannot qualify to stay out -- and it must not,
  // because `Runner.paramSchema` compiles and EVALUATES the binding
  // (`json/Runner.scala:849-852`), which is the very thing that wedges.
  assert.deepStrictEqual(core.UNCONFIRMED_TRIGGERS.slice().sort(),
                         ["answer", "module-learned", "params-file", "restart", "roots", "schema"]);
  assert.strictEqual(core.shouldAutoRender(mark, SALES_PICK, core.TRIGGER_SCHEMA), false);
  // `answer` is in the refused set although `stuckReduce` can never emit a
  // rerender for one (final re-check, nit 5): the trigger carries no
  // evidence -- it is the server describing the render we just sent -- and
  // a trigger kept out by a comment nobody re-reads is how D1 happened.
  // It costs nothing today, which this asserts rather than assumes.
  assert.strictEqual(core.shouldAutoRender(mark, SALES_PICK, core.TRIGGER_ANSWER), false);
  const answerRerenders = core.stuckReduce(core.initialStuckState(),
    { type: "answer", stuck: true, seqAtSend: 0 }).effects.rerender;
  assert.strictEqual(answerRerenders, false, "so the refused set cannot change any behaviour today");
  // Everything else renders, mark or no mark -- and `undefined` is NOT in
  // that list any more (D2): an undeclared trigger is refused and named.
  for (const trigger of [core.TRIGGER_EXPLICIT, core.TRIGGER_INVALIDATED, core.TRIGGER_FILE_EVENT,
                         core.TRIGGER_RECOVERED]) {
    assert.strictEqual(core.shouldAutoRender(mark, SALES_PICK, trigger), true, String(trigger));
  }
  assert.strictEqual(core.shouldAutoRender(mark, SALES_PICK, undefined), false, "D2: fail CLOSED");
  // A mark that is not this pick's is never consulted, whatever the trigger.
  for (const trigger of core.RENDER_TRIGGERS) {
    assert.strictEqual(core.shouldAutoRender(mark, OTHER_PICK, trigger), true, trigger);
  }
});

test("S2 M6: EVERY evidence trigger really does clear the mark BEFORE it renders", () => {
  // The review asked for this to be proven rather than asserted: the
  // refused set is safe only if the triggers left OUT of it cannot reach
  // the consultation with a mark still standing.
  const wedged = () => core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: SALES_PICK, params: { a: 1 }, at: 1 }).mark;

  // `invalidated` naming the pick's module -> cleared by the guard.
  let m = core.guardReduce(wedged(), { type: "invalidated", modules: ["Sales"], pick: SALES_PICK }).mark;
  assert.strictEqual(m, null, "invalidated");
  // The Q11 watcher feeds a `save` event for the report's own `.e` file.
  m = core.guardReduce(wedged(), { type: "save", path: SALES_PICK.fsPath }).mark;
  assert.strictEqual(m, null, "file-event");
  // A roots change, when the fingerprint moved.
  const movedRoots = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales", ["/w/doc", "/w/extra"]);
  m = core.guardReduce(wedged(), { type: "roots", pick: movedRoots }).mark;
  assert.strictEqual(m, null, "roots");
  // The recovery notification.
  m = core.guardReduce(wedged(), { type: "notification", stuck: false, applies: true, pick: SALES_PICK }).mark;
  assert.strictEqual(m, null, "recovered");

  // AND THE ONE THAT DOES NOT CLEAR, WHICH IS WHY IT IS NOT AN EVIDENCE
  // TRIGGER ANY MORE (D1): a `roots` event whose fingerprint did not move
  // KEEPS the mark. The glue schedules on `affectsConfiguration` either way,
  // so before D1 this rendered a held report -- and the justification
  // recorded for it proves the opposite, because if the resolved list is the
  // session's discard key and it did not move then nothing that matters
  // changed. MEASURED: 2,631 of 5,097 violating sequences were this one.
  const same = core.guardReduce(wedged(), { type: "roots", pick: SALES_PICK });
  assert.ok(same.mark, "the same roots keep the mark");
  assert.strictEqual(core.shouldAutoRender(same.mark, SALES_PICK, core.TRIGGER_ROOTS), false,
                     "so the trigger must consult it");
  // THE MEMBERSHIP RULE, as an assertion rather than a sentence: a trigger
  // may stay OUT of the refused set only if its guard event cleared.
  const clearsWhenItSchedules = {
    [core.TRIGGER_INVALIDATED]: true, [core.TRIGGER_FILE_EVENT]: true,
    [core.TRIGGER_RECOVERED]: true, [core.TRIGGER_ROOTS]: false,
  };
  for (const [trigger, clears] of Object.entries(clearsWhenItSchedules)) {
    assert.strictEqual(core.UNCONFIRMED_TRIGGERS.indexOf(trigger) < 0, clears,
                       trigger + ": out of the refused set iff it clears whenever it schedules");
  }
});

test("S2 M6: a params save while HELD with an unchanged fingerprint ASKS, it does not render", async () => {
  const m = sendModel();
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "evaluation did not finish", generation: 1, stuck: true });
  await flush();
  assert.ok(core.markMatches(m.mark, m.picked), "the report wedged the preview");

  // Format-on-save rewrites the file; the PARAMETERS are identical.
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 1, "the wedge is NOT re-issued");
  assert.strictEqual(m.held.length, 1);
  assert.strictEqual(m.held[0].trigger, core.TRIGGER_PARAMS_FILE);
  assert.ok(m.mark, "and the mark stands, so the status bar still reads held");
  assert.strictEqual(m.renderInFlight, false, "the spinner is released");
  assert.strictEqual(m.inFlight, null, "nothing was taken");

  // A REAL change clears the mark at the same site and renders.
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(2, { fromDay: "2026-02-01" });
  await flush();
  assert.strictEqual(m.mark, null);
  assert.strictEqual(m.sent.length, 2);
  assert.deepStrictEqual(m.sent[1].params, { fromDay: "2026-02-01" });
});

test("S2 M6: an EXPLICIT render while held is never refused -- asking for it IS the consent", async () => {
  const m = sendModel();
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  assert.ok(m.mark);
  // "Render anyway" clears the mark before `renderNow` (holdRender does it),
  // but even without that the explicit trigger is never consulted.
  m.renderNow("Render anyway", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 2);
  assert.deepStrictEqual(m.held, []);
});

test("S2 M6: MUTANT -- without the second consultation the wedge is re-issued silently", async () => {
  const m = sendModel({ mutantNoHeldCheck: true });
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(1, { fromDay: "2026-01-05" });          // a re-format: nothing changed
  await flush();
  assert.strictEqual(m.sent.length, 2, "the mutant re-renders the report that wedged the server");
  assert.deepStrictEqual(m.held, []);
});

test("S2 M4: the module is learned -> a render is scheduled, and it respects the hold", async () => {
  // Until the module was known there was no params PATH, so the first render
  // went out with `{}` and a params file on disk was ignored for ever
  // (review M4: "there is no next render").
  const noModule = core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", null, ["/w/doc"]);
  assert.strictEqual(core.paramsPaths(noModule, "/w", "posix").problem.reason, "no-module");
  const learned = core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Sales", ["/w/doc"]);
  assert.strictEqual(core.paramsPaths(learned, "/w", "posix").paramsPath,
                     "/w/.ermine/preview/Sales/report.params.json");

  // It carries no evidence of change, so it is in the refused set.
  const mark = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: learned, params: {}, at: 1 }).mark;
  assert.strictEqual(core.shouldAutoRender(mark, learned, core.TRIGGER_MODULE_LEARNED), false);
  assert.strictEqual(core.shouldAutoRender(null, learned, core.TRIGGER_MODULE_LEARNED), true);

  const m = sendModel({ pick: learned });
  m.renderNow("the module name was learned", false, core.TRIGGER_MODULE_LEARNED);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 1, "with no mark it renders, and now it finds the file");
  assert.deepStrictEqual(m.sent[0].params, { fromDay: "2026-01-05" });
});

test("S2 M3: the three params the fingerprint used to collapse are three marks", () => {
  // MEASURED before the fix: fp(null) == fp({}) == fp(undefined). So a report
  // that wedged with NO FILE could not be un-held by writing a file holding
  // `null`, and one that wedged on `null` could not be un-held by replacing
  // it with `{}` or by deleting the file.
  const wedged = (params) => core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: SALES_PICK, params, at: 1 }).mark;
  const clears = (mark, params) =>
    core.guardReduce(mark, { type: "params", pick: SALES_PICK, params }).mark === null;

  assert.ok(clears(wedged(undefined), null), "no file -> a file holding null IS a change");
  assert.ok(clears(wedged(null), {}), "null -> {} IS a change");
  assert.ok(clears(wedged(null), undefined), "null -> no params at all IS a change");
  assert.ok(!clears(wedged(null), null), "and null -> null is not");
  assert.ok(!clears(wedged({}), undefined), "`undefined` still means `{}`, for the marks 0.1.7 wrote");
});

test("S2 nits: the read failures VS Code spells differently, and the name fallback", () => {
  // nit 1: `FileNotADirectory` is VS Code's spelling of node's `ENOTDIR`, so
  // the same physical state must classify the same way whichever provider
  // answered.
  for (const code of ["FileNotFound", "FileNotADirectory", "ENOENT", "ENOTDIR", "EntryNotFound"]) {
    assert.strictEqual(core.meansFileMissing({ code }), true, code);
  }
  // nit 2: `name` has been seen rendered as "EntryNotFound (FileSystemError)".
  assert.strictEqual(core.meansFileMissing({ name: "EntryNotFound (FileSystemError)" }), true);
  assert.strictEqual(core.meansFileMissing({ name: "FileNotFound (FileSystemError)" }), true);
  // Something IS there and we could not read it: still a refusal.
  for (const code of ["EACCES", "NoPermissions", "EISDIR", "FileIsADirectory", "EBUSY"]) {
    assert.strictEqual(core.meansFileMissing({ code }), false, code);
  }
  assert.strictEqual(core.meansFileMissing({ name: "Error" }), false);
});

test("S2 nits: the cap is applied BEFORE the file is materialised", () => {
  // nit 3: `readFile` pulls the whole file into the extension host, and the
  // text cap only runs afterwards. A 1 GiB params file would kill the host
  // the way a 64 MiB frame kills the server.
  const over = core.paramsTooLargeToRead(core.PARAMS_MAX_BYTES + 1);
  assert.strictEqual(over.reason, "too-large");
  assert.match(over.message, /1048577 bytes/);
  assert.match(over.message, /not read/);
  // The boundary is the same `>` the text cap uses (MEASURED by the review:
  // exactly 1 MiB reaches the server).
  assert.strictEqual(core.paramsTooLargeToRead(core.PARAMS_MAX_BYTES), null);
  // A provider that cannot stat must still work: an unusable answer means
  // "carry on and let the text cap decide".
  for (const size of [undefined, null, -1, NaN, Infinity, "big"]) {
    assert.strictEqual(core.paramsTooLargeToRead(size), null, String(size));
  }
  // And it dresses as an answer like every other refusal.
  assert.strictEqual(core.paramsRefusalAnswer(over, "/p.json", 4).paramsProblem, "too-large");
});

test("S2 nits: a read that never settles is a named refusal, not a stuck spinner", () => {
  // nit 7, and `stopQuietly`'s own lesson: a hang is not a throw.
  const out = core.paramsReadTimedOut("/w/.ermine/preview/Sales/report.params.json", 5000);
  assert.strictEqual(out.reason, "timed-out");
  assert.match(out.message, /did not finish being read within 5s/);
  assert.match(out.message, /Save it again to retry/);
  assert.strictEqual(core.PARAMS_READ_TIMEOUT_MS, 5000);
  assert.strictEqual(core.paramsRefusalAnswer(out, "/p.json", 2).status, null);
});

test("S2 nits: a params refusal does NOT disarm the Q11 watcher", async () => {
  // nit 5: `shouldRerenderOnFileEvent` asks whether the last SERVER answer
  // was a placement 404. A refusal decided in the extension is not an answer
  // from any server, and overwriting it lost the render that brings a
  // deleted report back to life.
  const placement404 = { ok: false, status: 404, reason: "unreadable", message: "cannot read Sales.e", generation: 1 };
  assert.strictEqual(core.shouldRerenderOnFileEvent(SALES_PICK, placement404, SALES_PICK.fsPath), true);

  const m = sendModel();
  m.renderNow("x", false, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerWith(0, placement404);
  await flush();
  assert.strictEqual(m.lastServerAnswer, placement404);

  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readRefusal(1, "invalid-json");
  await flush();
  assert.strictEqual(m.lastAnswer.paramsProblem, "invalid-json", "the tab shows the refusal");
  assert.strictEqual(m.lastServerAnswer, placement404, "and the watcher still knows it is watching");
  assert.strictEqual(core.shouldRerenderOnFileEvent(m.picked, m.lastServerAnswer, m.picked.fsPath), true);
  assert.strictEqual(core.shouldRerenderOnFileEvent(m.picked, m.lastAnswer, m.picked.fsPath), false,
                     "which is exactly what the single variable used to answer");
});


// ================== WP-8 S2, the DELTA re-review: D1, D2, D3 and families B/C
//
// The delta re-review drove the REAL reducers, in the glue's real order, over
// every sequence of 13 events up to depth 5 -- 579,194 of them -- and asked one
// question of each: did a render reach the wire for a report whose mark was
// still standing, without the user asking?  It found 5,097 that did.  The three
// families are D1 (a `roots` change that moved nothing), and B/C (an evidence
// trigger that cleared the mark and scheduled, after which the report wedged
// AGAIN inside the coalescing window and the read).

test("S2 D1: a roots change that moves NOTHING consults the mark", async () => {
  const m = sendModel();
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  assert.ok(core.markMatches(m.mark, m.picked), "the report wedged");

  // `ermine.preview.roots` was edited to a list that RESOLVES the same. The
  // glue feeds the guard, which KEEPS the mark, and schedules regardless.
  m.mark = core.guardReduce(m.mark, { type: "roots", pick: m.picked }).mark;
  assert.ok(m.mark, "the guard keeps a mark whose roots fingerprint did not move");
  m.renderNow("ermine.preview.roots changed", false, core.TRIGGER_ROOTS);
  await flush();
  m.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 1, "the wedge is NOT re-issued");
  assert.strictEqual(m.held.length, 1);
  assert.strictEqual(m.held[0].trigger, core.TRIGGER_ROOTS);

  // And a roots change that DOES move clears the mark, so it renders.
  const n = sendModel();
  n.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  n.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  n.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  n.rootsChangeInPlace(["/w/doc", "/w/extra"]);
  n.mark = core.guardReduce(n.mark, { type: "roots", pick: n.picked }).mark;
  assert.strictEqual(n.mark, null);
  n.renderNow("ermine.preview.roots changed", false, core.TRIGGER_ROOTS);
  await flush();
  n.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(n.sent.length, 2);
});

test("S2 D2: an undeclared trigger is refused and named, not permitted", async () => {
  // THE MUTANT THIS EXISTS FOR: `scheduleRender` forwarding `undefined`
  // instead of its trigger neutered BOTH consultation sites for every
  // automatic render and survived all 210 tests.
  assert.match(core.triggerProblem(undefined), /not one of the declared render triggers/);
  assert.match(core.triggerProblem("restarted"), /restarted/);
  assert.strictEqual(core.isRenderTrigger(core.TRIGGER_ROOTS), true);
  assert.strictEqual(core.isRenderTrigger("Roots"), false);

  const m = sendModel();
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  m.renderNow("a trigger nobody declared", false, undefined);
  await flush();
  m.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 1, "fail CLOSED: the held report is not re-rendered");
  assert.strictEqual(m.held.length, 1);

  // AND EVERY TRIGGER THE GLUE REALLY PASSES IS DECLARED. Read out of the
  // source, so adding a call site with a new spelling fails here.
  const fs = require("node:fs");
  const glue = fs.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const used = new Set((glue.match(/core\.TRIGGER_[A-Z_]+/g) || []).map((t) => t.replace("core.", "")));
  assert.ok(used.size >= 7, "only " + used.size + " trigger constants are used");
  for (const name of used) {
    assert.ok(core.RENDER_TRIGGERS.indexOf(core[name]) >= 0, name + " is not a declared render trigger");
  }
  // `applyStuck`'s own third argument used to be a bare string that
  // OVERLAPPED this vocabulary by luck ("restart", "recovered", "answer").
  assert.ok(used.has("TRIGGER_ANSWER") && used.has("TRIGGER_RECOVERED") && used.has("TRIGGER_RESTART"));
});

test("S2 families B/C: a mark minted AFTER the render was scheduled holds it", () => {
  // `invalidated` clears the mark and schedules; inside the 150 ms window
  // and the file read the report wedges AGAIN. The trigger is evidence and
  // the mark stands, so the consultation alone would permit it -- and the
  // request would reach a server that has just wedged.
  const pick = SALES_PICK;
  const markAt = (at) => core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick, params: { a: 1 }, at }).mark;

  assert.strictEqual(core.markMintedAfter(markAt(2000), pick, 1000), true);
  assert.strictEqual(core.markMintedAfter(markAt(500), pick, 1000), false, "an OLDER mark is the one the guard already asked about");
  assert.strictEqual(core.markMintedAfter(markAt(1000), pick, 1000), false, "same instant: not newer");
  assert.strictEqual(core.markMintedAfter(null, pick, 1000), false);
  assert.strictEqual(core.markMintedAfter(markAt(2000), OTHER_PICK, 1000), false, "another pick's mark is never consulted");

  // FAIL OPEN on anything it cannot compare: this arm refines an
  // already-safe decision, and a spurious hold on a broken clock is a worse
  // trade than the one it fixes.
  assert.strictEqual(core.markMintedAfter(markAt(2000), pick, undefined), false);
  assert.strictEqual(core.markMintedAfter(markAt(2000), pick, NaN), false);
  assert.strictEqual(core.markMintedAfter(markAt(null), pick, 1000), false);

  // End to end through the one function the glue calls.
  assert.deepStrictEqual(core.mayAutoRender(markAt(2000), pick, core.TRIGGER_INVALIDATED, 1000).render, false);
  assert.match(core.mayAutoRender(markAt(2000), pick, core.TRIGGER_INVALIDATED, 1000).why, /wedged the preview again AFTER/);
  assert.strictEqual(core.mayAutoRender(markAt(500), pick, core.TRIGGER_INVALIDATED, 1000).render, true);
  // An EXPLICIT render is never held by it: asking for it is the consent.
  assert.strictEqual(core.mayAutoRender(markAt(2000), pick, core.TRIGGER_EXPLICIT, 1000).render, true);
});

test("S2 families B/C: the sequence the explorer found, walked end to end", async () => {
  const m = sendModel();
  // 1. a render wedges the preview.
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();
  assert.ok(m.mark);

  // 2. the developer saves the `.e` file: `invalidated` CLEARS the mark and
  //    schedules a render at T.
  m.mark = core.guardReduce(m.mark, { type: "invalidated", modules: ["Sales"], pick: m.picked }).mark;
  assert.strictEqual(m.mark, null);
  const scheduledAt = 1000;
  m.renderNow("invalidated: Sales", false, core.TRIGGER_INVALIDATED, scheduledAt);
  await flush();

  // 3. INSIDE the window, the server answers an older render `stuck: true`
  //    and the mark is re-minted, at a time AFTER T.
  m.mark = core.guardReduce(m.mark, {
    type: "answer", stuck: true, applies: true, pick: m.picked, params: { fromDay: "2026-01-05" },
    at: scheduledAt + 50 }).mark;
  assert.ok(m.mark, "the report wedged again while the render waited");

  // 4. the read finishes and the render is HELD, not sent.
  m.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 1);
  assert.strictEqual(m.held.length, 1);
  assert.match(m.held[0].why, /AFTER this render was scheduled/);
});

test("S2 D3: \"Not now\" is remembered for a params re-format and NOT for a restart", () => {
  const pick = SALES_PICK;
  const mark = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick, params: { a: 1 }, at: 1000 }).mark;
  const token = core.heldPromptToken(mark);
  assert.ok(typeof token === "string" && token.length > 20);
  assert.strictEqual(core.heldPromptToken(null), null);
  assert.strictEqual(core.heldPromptToken({ key: "x" }), null, "only a real mark has a token");

  // Nothing refused yet: ask.
  assert.strictEqual(core.shouldAskHeld(undefined, mark, pick, core.TRIGGER_PARAMS_FILE).ask, true);
  // Refused once: a second re-format of the same file does not ask again.
  const again = core.shouldAskHeld(token, mark, pick, core.TRIGGER_PARAMS_FILE);
  assert.strictEqual(again.ask, false);
  assert.match(again.why, /already answered "Not now"/);
  // A RESTART is a new event -- the user pressed the button, or the server
  // died again -- and always asks.
  for (const trigger of [core.TRIGGER_RESTART, core.TRIGGER_MODULE_LEARNED, core.TRIGGER_ROOTS]) {
    assert.strictEqual(core.shouldAskHeld(token, mark, pick, trigger).ask, true, trigger);
  }
  // A NEW mark for the same pick (the wedge happened again) asks.
  const reMinted = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick, params: { a: 1 }, at: 9999 }).mark;
  assert.strictEqual(core.shouldAskHeld(token, reMinted, pick, core.TRIGGER_PARAMS_FILE).ask, true);
  // A mark that is not this pick's is never asked about at all.
  assert.strictEqual(core.shouldAskHeld(token, mark, OTHER_PICK, core.TRIGGER_PARAMS_FILE).ask, false);
  assert.strictEqual(core.shouldAskHeld(undefined, null, pick, core.TRIGGER_PARAMS_FILE).ask, false);
});

test("S2 D3: the second re-format while held logs instead of asking, and the hold stays", async () => {
  const m = sendModel();
  m.renderNow("picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readOk(0, { fromDay: "2026-01-05" });
  await flush();
  m.answerWith(0, { ok: false, status: 500, message: "stuck", generation: 1, stuck: true });
  await flush();

  // First re-format: held, and the question is asked.
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(1, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.asked.length, 1);
  assert.strictEqual(m.asked[0].ask, true);
  m.notNow();                                    // the user dismisses it

  // Second re-format: still held, and NOT asked again.
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readOk(2, { fromDay: "2026-01-05" });
  await flush();
  assert.strictEqual(m.sent.length, 1, "nothing is rendered either way");
  assert.strictEqual(m.asked.length, 2);
  assert.strictEqual(m.asked[1].ask, false, "the same question is not asked twice");
  assert.ok(core.markMatches(m.mark, m.picked), "and the status bar still reads held");
  assert.strictEqual(core.statusBarState({ pick: m.picked, mark: m.mark }).text,
                     "$(warning) Ermine preview: held");

  // A RESTART after that asks again.
  const asking = core.shouldAskHeld(m.heldRefusedToken, m.mark, m.picked, core.TRIGGER_RESTART);
  assert.strictEqual(asking.ask, true);
});


// ============================================ WP-8 S3: THE FIRST PICK WRITES
//
// S1 decided WHERE the files go and WHAT their text is.  S2 reads a params
// file that is already there and sends it.  S3 is the first `ermine/schema`
// client and the first thing in this extension that writes to the
// developer's disk.  Four kinds of test live below, in this order:
//
//   1. the new PURE decisions -- the ordering rule, when a refresh is worth
//      a preview job, what an answer turned out to be, whether a late one
//      may still be used, which bytes go where in which order, and whether a
//      file already holds them;
//   2. PROPERTIES over the same generated schemas S1's walker is tested on,
//      because the write plan is a function of an exported schema and its
//      two invariants (the params file is LAST and is never overwritten, and
//      no path escapes the workspace folder) must hold for every one;
//   3. an ASYNC MODEL of the whole first-pick sequence in `sendModel`'s
//      style, because the schema request puts a SECOND `await` into the send
//      path -- and every mutant the brief names is an option on that same
//      model, so each is run against the SAME interleavings;
//   4. SOURCE PINS, because the write order, the guard's place in it and the
//      "the params file is written from ONE branch" rule are all shapes of
//      `extension.js` that no behavioural test in this file can see.

// -------------------------------------------------------------------- isoDay

test("S3: today is the machine's own day, not a UTC slice of it", () => {
  // A pure function of the Date it is handed: the glue owns the clock, as it
  // does for the restart reducer.
  assert.strictEqual(core.isoDay(new Date(2026, 8, 21, 0, 5)), "2026-09-21");
  assert.strictEqual(core.isoDay(new Date(2026, 8, 21, 23, 55)), "2026-09-21");
  assert.strictEqual(core.isoDay(new Date(2026, 0, 1)), "2026-01-01");
  assert.strictEqual(core.isoDay(new Date(2026, 11, 31)), "2026-12-31");
  assert.strictEqual(core.isoDay(new Date("nonsense")), null);
  // AND IT IS WHAT `skeletonFrom` ACCEPTS: the two are only useful together.
  const today = core.isoDay(new Date());
  assert.strictEqual(core.skeletonFrom(SALES_SCHEMA, today, "./report.schema.json").problem, undefined);
  // A UTC slice is a DIFFERENT day west of Greenwich for most of the working
  // day, which is the reason this is local. Pinned as the shape rather than
  // as an inequality, since the test machine's zone is not ours to choose.
  assert.match(today, /^\d{4}-\d{2}-\d{2}$/);
});

// -------------------------------------------------------- G15: which first

test("S3: G15 -- no params file puts the SCHEMA first, a file present puts the RENDER first", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  assert.ok(!paths.problem);

  const missing = core.schemaOrder(paths, true);
  assert.strictEqual(missing.first, "schema");
  assert.strictEqual(missing.write, true);
  assert.match(missing.why, /no params file yet/);

  const present = core.schemaOrder(paths, false);
  assert.strictEqual(present.first, "render");
  assert.strictEqual(present.write, false);
  assert.match(present.why, /already on disk/);

  // NO PATHS AT ALL: a report outside every workspace folder, a pick with no
  // module, an operator binding. Nothing is written and no schema is asked
  // for -- the render goes with the inline `{}` as WP-7 sends it, and S2 has
  // already said why, once per pick.
  const outside = core.paramsPaths(SALES_PICK, "/elsewhere", "posix");
  assert.ok(outside.problem);
  for (const nowhere of [outside, undefined, null, {}, "nonsense"]) {
    const o = core.schemaOrder(nowhere, true);
    assert.strictEqual(o.first, "render", JSON.stringify(nowhere));
    assert.strictEqual(o.write, false);
  }
  // `fileMissing` is a strict true: an undefined "we do not know" must not
  // be read as "there is no file" and write over one.
  for (const unknown of [undefined, null, 0, "", "yes", 1]) {
    assert.strictEqual(core.schemaOrder(paths, unknown).first, "render", JSON.stringify(unknown));
  }
});

// ------------------------------------------------------------ D8: refreshing

test("S3: D8 -- the schema file is refreshed only after an answer that says the report COMPILED", () => {
  const T = core.TRIGGER_INVALIDATED;
  assert.strictEqual(core.shouldRefreshSchema({ ok: true, generation: 1 }, T).refresh, true);
  assert.strictEqual(
    core.shouldRefreshSchema({ ok: false, status: 400, path: "$.params.fromDay" }, T).refresh, true);
  assert.strictEqual(core.shouldRefreshSchema({ ok: false, status: 400, path: "$.params" }, T).refresh, true);

  // Each NO for its own reason: a 404/409 never reached a report, a 500 is a
  // load or an evaluation failure (so there may be no parameter type to
  // export, and asking queues a job behind a server that is already
  // unhappy), and a 400 anywhere else is about the request.
  for (const answer of [
    { ok: false, status: 404, reason: "not-placed" },
    { ok: false, status: 409, reason: "shadowed" },
    { ok: false, status: 500, message: "module does not load" },
    { ok: false, status: 400, path: "$" },
    { ok: false, status: 400, path: "$.roots" },
    { ok: false, status: 500, stuck: true },
  ]) {
    assert.strictEqual(core.shouldRefreshSchema(answer, T).refresh, false, JSON.stringify(answer));
  }
  // A PARAMS REFUSAL never asked a server anything at all (`status: null`).
  const refusal = core.paramsRefusalAnswer(core.paramsToSend("{"), "/p.json", 3);
  assert.strictEqual(core.shouldRefreshSchema(refusal, T).refresh, false);
  assert.strictEqual(core.shouldRefreshSchema(undefined, T).refresh, false);
});

test("S3: D8 -- and the TRIGGER decides too, fail-closed on anything undeclared", () => {
  const ok = { ok: true, generation: 1 };
  assert.deepStrictEqual(core.SCHEMA_REFRESH_TRIGGERS.slice().sort(),
                         ["explicit", "file-event", "invalidated", "module-learned", "roots"]);
  for (const trigger of core.SCHEMA_REFRESH_TRIGGERS) {
    assert.strictEqual(core.shouldRefreshSchema(ok, trigger).refresh, true, trigger);
  }
  // `params-file` IS THE LOAD-BEARING EXCLUSION, twice over: editing the
  // parameters cannot change the parameter TYPE, and it is the trigger the
  // skeleton's own creation fires -- so leaving it out is what stops a first
  // pick asking for the schema twice in a row.
  assert.strictEqual(core.shouldRefreshSchema(ok, core.TRIGGER_PARAMS_FILE).refresh, false);
  // `restart` and `recovered` are the `fx.schema` seam's own, and it asks.
  assert.strictEqual(core.shouldRefreshSchema(ok, core.TRIGGER_RESTART).refresh, false);
  assert.strictEqual(core.shouldRefreshSchema(ok, core.TRIGGER_RECOVERED).refresh, false);
  // D2's policy, applied here as well: unknown means NO.
  for (const junk of [undefined, null, "", 0, "typo", {}]) {
    assert.strictEqual(core.shouldRefreshSchema(ok, junk).refresh, false, JSON.stringify(junk));
    assert.match(core.shouldRefreshSchema(ok, junk).why, /cannot have changed/);
  }
});

// -------------------------------------------------- what an answer turned out to be

test("S3: every way an ermine/schema answer can fail is named, and NONE of them blocks a render", () => {
  // **EVERY ARM CARRIES ALL THREE KEYS (the delta re-review's D-1).** The
  // first cut minted the success and the three server-side failures HERE as
  // `{schema}` and a BARE `{reason, message}`, while the glue's other two
  // failure returns were WRAPPED `{problem: ...}` -- and both callers test
  // `outcome.problem`. MEASURED on a real disk: every server-side failure
  // fell through the handler and the D8 refresh wrote the literal text
  // `undefined\n` into the schema file.
  const shapes = [
    ["a schema", SALES_SCHEMA, null],
    ["an {error}", { error: "no module named Sales", reason: "not-placed" }, "error"],
    ["a stuck refusal", { error: "the preview is stuck", stuck: true }, "stuck"],
    ["not an object", 7, "no-schema"],
  ];
  for (const [label, answer, reason] of shapes) {
    const out = core.schemaAnswerOutcome(answer);
    for (const key of ["schema", "problem", "abandoned"]) {
      assert.ok(key in out, label + " declares `" + key + "`");
    }
    assert.strictEqual(out.problem === null ? null : out.problem.reason, reason, label);
    assert.strictEqual(out.schema, reason === null ? SALES_SCHEMA : null, label);
    assert.strictEqual(out.abandoned, null, label);
    if (reason !== null) assert.ok(out.problem.message.length > 20, label);
  }
  assert.match(core.schemaAnswerOutcome({ error: "no module named Sales" }).problem.message,
               /no module named Sales/);
  assert.match(core.schemaAnswerOutcome({ error: "x", stuck: true }).problem.message, /Nothing was written/);
  for (const junk of [null, undefined, 7, "a schema", [], true]) {
    assert.strictEqual(core.schemaAnswerOutcome(junk).problem.reason, "no-schema", JSON.stringify(junk));
  }
  // A JSON-RPC error or a transport rejection, in the SAME shape.
  const failed = core.schemaRequestFailure(new Error("Connection got disposed"));
  assert.strictEqual(failed.problem.reason, "request-failed");
  assert.match(failed.problem.message, /Connection got disposed/);
  assert.match(failed.problem.message, /no schema file was written/);
  assert.strictEqual(failed.schema, null);
  // And the abandon arm, which the MODEL used to mint as a literal.
  const gone = core.schemaAbandoned({ reason: "pick-changed", why: "x" });
  assert.strictEqual(gone.abandoned.reason, "pick-changed");
  assert.strictEqual(gone.problem, null);
  assert.strictEqual(gone.schema, null);
  // FAIL CLOSED: a builder call that names none of the three is a problem,
  // never a silent success.
  for (const nothing of [undefined, null, {}, { schema: undefined }, { schema: 7 }, 5]) {
    assert.strictEqual(core.schemaOutcome(nothing).problem.reason, "no-schema", JSON.stringify(nothing));
  }
  // Every one of them carries a `reason` from a closed little vocabulary, so
  // "one notice per distinct problem per pick" really is one.
  const reasons = ["no-schema", "error", "stuck", "request-failed"];
  const keys = new Set(reasons.map((r) => core.schemaNoticeKey(SALES_PICK, r)));
  assert.strictEqual(keys.size, reasons.length, "four reasons, four keys");
});

// --------------------------------------------- D7: may a late answer be used

test("S3: D7 -- a schema answer is discarded by BOTH tests, and neither is redundant", () => {
  const attempt = core.renderAttempt(4, SALES_PICK, 2, 0, 0);
  const live = (over) => core.previewNow(
    over && "generation" in over ? over.generation : 4,
    over && "pick" in over ? over.pick : SALES_PICK,
    over && "clientEpoch" in over ? over.clientEpoch : 2,
    over && "stopCount" in over ? over.stopCount : 0,
    over && "hasClient" in over ? over.hasClient : true);

  assert.deepStrictEqual(core.mayUseSchemaAnswer(attempt, live(), SALES_PICK),
                         { send: true, reason: null, why: null });

  // `mayStillSend`'s own arms, unchanged: a restart, a stop, a newer render,
  // a teardown, the client going away.
  assert.strictEqual(core.mayUseSchemaAnswer(attempt, live({ clientEpoch: 3 }), SALES_PICK).reason,
                     "server-restarted");
  assert.strictEqual(core.mayUseSchemaAnswer(attempt, live({ stopCount: 1 }), SALES_PICK).reason,
                     "server-stopped");
  assert.strictEqual(core.mayUseSchemaAnswer(attempt, live({ generation: 5 }), SALES_PICK).reason,
                     "superseded");
  assert.strictEqual(core.mayUseSchemaAnswer(attempt, live({ pick: undefined }), undefined).reason,
                     "pick-cleared");
  assert.strictEqual(core.mayUseSchemaAnswer(attempt, live({ hasClient: false }), SALES_PICK).reason,
                     "no-client");

  // AND THE ONE `mayStillSend` CANNOT SEE: the MODULE, which is the
  // DIRECTORY the file would be written into. A header edited from
  // `module Sales` to `module Sales2` keeps the uri and the binding, so
  // `markKey` -- and every arm above -- says nothing moved.
  const renamed = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales2", ["/w/doc"]);
  assert.strictEqual(core.mayStillSend(attempt, live({ pick: renamed })).send, true,
                     "mayStillSend alone does not notice a module rename -- this is why both are asked");
  const both = core.mayUseSchemaAnswer(attempt, live({ pick: renamed }), renamed);
  assert.strictEqual(both.send, false);
  assert.strictEqual(both.reason, "pick-changed");
  assert.ok(core.ABANDON_REASONS.indexOf(both.reason) >= 0, "the vocabulary stays closed");
  assert.match(both.why, /module or roots moved/);
});

// -------------------------------------------------------- write-if-different

test("S3: D8's write-if-different, and an unreadable file is never mistaken for a matching one", () => {
  assert.strictEqual(core.schemaFileNeedsWrite("a\n", "a\n"), false);
  assert.strictEqual(core.schemaFileNeedsWrite("a\n", "b\n"), true);
  // NOT THERE, or could not be read: `readTextIfPresent` answers null and
  // "we do not know what is there" is not "it is already right".
  assert.strictEqual(core.schemaFileNeedsWrite(null, "a\n"), true);
  assert.strictEqual(core.schemaFileNeedsWrite(undefined, "a\n"), true);
  // Nothing to write is nothing to do.
  assert.strictEqual(core.schemaFileNeedsWrite("a\n", undefined), false);
  // AND IT IS MEANINGFUL ONLY BECAUSE `schemaFileText` IS STABLE: the same
  // schema always renders to the same bytes, which is why the comparison can
  // be of bytes at all.
  const once = core.schemaFileText(core.schemaFileFor(SALES_SCHEMA));
  const twice = core.schemaFileText(core.schemaFileFor(JSON.parse(JSON.stringify(SALES_SCHEMA))));
  assert.strictEqual(once, twice);
  assert.strictEqual(core.schemaFileNeedsWrite(once, twice), false);
});

// ------------------------------------------------------------- the write plan

test("S3: the plan writes the params file LAST, and ifAbsent, and the schema file ifDifferent", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const plan = core.paramsWritePlan(paths, SALES_SCHEMA, TODAY);
  assert.strictEqual(plan.problem, undefined);
  assert.deepStrictEqual(plan.files.map((f) => f.what), ["gitignore", "schema", "params"]);
  assert.deepStrictEqual(plan.files.map((f) => f.mode), ["ifAbsent", "ifDifferent", "ifAbsent"]);
  assert.deepStrictEqual(plan.files.map((f) => f.path), [
    "/w/.ermine/preview/.gitignore",
    "/w/.ermine/preview/Sales/report.schema.json",
    "/w/.ermine/preview/Sales/report.params.json",
  ]);
  // THE PARAMS FILE IS LAST BECAUSE ITS CREATION IS WHAT THE S2 WATCHER SEES
  // (the watcher's glob is the exact params path, so neither of the other
  // two matches anything). By the time the render its `onDidCreate`
  // schedules runs, the schema it points at is already on disk.
  assert.strictEqual(core.paramsPaths(SALES_PICK, "/w", "posix").relativeGlob,
                     ".ermine/preview/Sales/report.params.json");

  // THE BYTES, each from the function S1 wrote for it.
  assert.strictEqual(plan.files[0].text, core.paramsGitignoreText);
  assert.strictEqual(plan.files[1].text, core.schemaFileText(core.schemaFileFor(SALES_SCHEMA)));
  assert.strictEqual(plan.files[2].text,
                     core.schemaFileText(core.skeletonFrom(SALES_SCHEMA, TODAY, "./report.schema.json").value));
  assert.strictEqual(plan.embeddable, true);
  // THE SKELETON IS S1's, MEASURED: `onlyRegion` is a `Maybe` and is ABSENT.
  assert.deepStrictEqual(plan.skeleton,
    { $schema: "./report.schema.json", fromDay: TODAY, toDay: TODAY, orderBy: "ByDay" });
  assert.ok(plan.files[2].text.endsWith("}\n"), "a trailing newline, so git and every POSIX tool behave");
});

test("S3: a NON-OBJECT params root still gets its file, without a $schema line (G5)", () => {
  // WP-7's own `WpSpin` shape, `report : Int -> Node`.
  const intRoot = { $schema: "https://json-schema.org/draft/2020-12/schema", $id: "ermine:WpSpin/Int",
                    type: "integer", $defs: {} };
  const paths = core.paramsPaths(
    core.makePick("file:///w/WpSpin.e", "/w/WpSpin.e", "report", "WpSpin", []), "/w", "posix");
  const plan = core.paramsWritePlan(paths, intRoot, TODAY);
  assert.strictEqual(plan.embeddable, false);
  assert.strictEqual(plan.skeleton, 0);
  assert.strictEqual(plan.files[2].text, "0\n");
  // The schema file is STILL written -- it is generated and gitignored
  // either way, and the refresh path then needs no second rule -- and the
  // notice says the editor will not validate the params file.
  assert.strictEqual(plan.files[1].what, "schema");
  assert.match(core.paramsWrittenNotice(paths, false, plan.shape), /no "\$schema" line/);
  assert.match(core.paramsWrittenNotice(paths, false, plan.shape), /editor will not validate/);
  assert.match(core.paramsWrittenNotice(paths, true), /ordinary committed source/);
});

test("S3: a plan is refused, and nothing is written, when there is no skeleton or no path", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  // An ALL-RECURSIVE type has no finite skeleton (S1's own refusal).
  const loop = { $ref: "#/$defs/T", $defs: { T: { type: "object", properties: { next: { $ref: "#/$defs/T" } },
                                                 required: ["next"], additionalProperties: false } } };
  const refused = core.paramsWritePlan(paths, loop, TODAY);
  assert.ok(refused.problem, JSON.stringify(refused).slice(0, 200));
  assert.strictEqual(refused.files, undefined, "a refusal writes NOTHING, not some of it");

  // No path at all.
  for (const nowhere of [undefined, null, {}, core.paramsPaths(SALES_PICK, "/elsewhere", "posix")]) {
    const out = core.paramsWritePlan(nowhere, SALES_SCHEMA, TODAY);
    assert.strictEqual(out.problem.reason, "no-params-path", JSON.stringify(nowhere));
    assert.strictEqual(out.files, undefined);
  }
  // An answer that is not a schema document.
  assert.strictEqual(core.paramsWritePlan(paths, 7, TODAY).problem.reason, "not-a-schema");
  // A `today` the walker refuses.
  assert.strictEqual(core.paramsWritePlan(paths, SALES_SCHEMA, "21/09/2026").problem.reason, "bad-today");
});

test("S3: the plan never mutates the server's answer, and is idempotent over it", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const before = JSON.stringify(SALES_SCHEMA);
  const a = core.paramsWritePlan(paths, SALES_SCHEMA, TODAY);
  const b = core.paramsWritePlan(paths, SALES_SCHEMA, TODAY);
  assert.strictEqual(JSON.stringify(SALES_SCHEMA), before, "the server's answer is the glue's, not ours");
  assert.deepStrictEqual(a.files, b.files);
});

test("S3: the notices name the files and say what is ignored and why", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const written = core.paramsWrittenNotice(paths, true);
  assert.match(written, /report\.params\.json/);
  assert.match(written, /report\.schema\.json/);
  assert.match(written, /gitignore/);
  const problem = core.schemaProblemNotice(
    core.schemaAnswerOutcome({ error: "boom" }), paths.paramsPath);
  assert.match(problem, /no params file was written/);
  assert.match(problem, /renders with empty parameters/);
  assert.match(problem, /boom/);
  // It takes the `{problem: ...}` wrapper too, which is what `paramsWritePlan`
  // answers and what the glue holds.
  assert.match(core.schemaProblemNotice(core.paramsWritePlan({}, SALES_SCHEMA, TODAY), "/p.json"),
               /nowhere to write/);
  // One key per (pick, reason), and it cannot collide with a params notice.
  assert.notStrictEqual(core.schemaNoticeKey(SALES_PICK, "stuck"), core.paramsNoticeKey(SALES_PICK, "stuck"));
  assert.strictEqual(core.schemaNoticeKey(SALES_PICK, "stuck"), core.schemaNoticeKey(SALES_PICK, "stuck"));
  assert.notStrictEqual(core.schemaNoticeKey(SALES_PICK, "stuck"), core.schemaNoticeKey(OTHER_PICK, "stuck"));
});

// ---------------------------------------------------------------- properties

test("PROPERTY (S3): every plan puts the params file last, ifAbsent, inside the folder", () => {
  const rnd = wp8Rnd(8383831);
  let planned = 0, refused = 0, nonObject = 0;
  for (let i = 0; i < 3000; i++) {
    const schema = generateSchema(rnd);
    const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
    const plan = core.paramsWritePlan(paths, schema, TODAY);
    if (plan.problem) { refused++; continue; }
    planned++;
    if (!plan.embeddable) nonObject++;
    // THE TWO INVARIANTS THE WRITE LOOP RELIES ON.
    const last = plan.files[plan.files.length - 1];
    assert.strictEqual(last.what, "params", "the params file is LAST");
    assert.strictEqual(last.mode, "ifAbsent", "and is NEVER overwritten");
    assert.strictEqual(plan.files.filter((f) => f.what === "params").length, 1);
    assert.strictEqual(plan.files.filter((f) => f.mode === "ifDifferent").length, 1);
    for (const f of plan.files) {
      assert.ok(f.path.indexOf("/w/.ermine/preview/") === 0, f.path);
      assert.strictEqual(typeof f.text, "string");
      assert.ok(f.text.endsWith("\n"), f.what + " ends with a newline");
    }
    // And the params file's own bytes always parse back to the skeleton.
    assert.deepStrictEqual(JSON.parse(last.text), plan.skeleton);
  }
  assert.ok(planned > 2000 && refused > 0 && nonObject > 0,
            `distribution: ${planned} planned, ${refused} refused, ${nonObject} non-object roots`);
});

test("PROPERTY (S3): the written params file is what the written schema file accepts", () => {
  // The whole point of writing the two together. S1 pins that a skeleton
  // validates against the schema FILE; this pins that the PLAN's two texts
  // -- the bytes that actually reach the disk -- are that same pair after a
  // round trip through JSON.
  const rnd = wp8Rnd(6464641);
  let checked = 0;
  for (let i = 0; i < 1500; i++) {
    const schema = generateSchema(rnd);
    const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
    const plan = core.paramsWritePlan(paths, schema, TODAY);
    if (plan.problem) continue;
    const file = JSON.parse(plan.files[1].text);
    const value = JSON.parse(plan.files[2].text);
    assert.strictEqual(validates(file, value, file.$defs || {}, 0), true,
                       "the skeleton does not validate against the file that is written beside it");
    // AND THE `$schema` LINE THE FILE CARRIES IS THE ONE THAT WAS WRITTEN.
    if (plan.embeddable) assert.strictEqual(value.$schema, paths.schemaRef);
    else assert.ok(value === null || typeof value !== "object" || Array.isArray(value) ||
                   value.$schema === undefined);
    checked++;
  }
  assert.ok(checked > 1000, "checked " + checked);
});

// ------------------------------- the async model of the first-pick sequence
//
// A FAITHFUL MODEL OF THE SECOND `await` THE SEND PATH NOW HAS, statement for
// statement with `renderNow`'s no-file branch, `firstPickSchemaAndWrite`,
// `requestSchema` and `applyWritePlan`.  It calls the real pure decisions
// (`schemaOrder`, `mayUseSchemaAnswer`, `schemaAnswerOutcome`,
// `paramsWritePlan`, `schemaFileNeedsWrite`, `mayAutoRender`) rather than
// restating them, so what is modelled is the ORDER, the DISK and nothing
// else.
//
// THE MODEL-FIDELITY RULE (the header of this file) applied to this stage:
//   * the glue captures `core.renderAttempt`'s frozen snapshot BEFORE the
//     read and reuses that SAME object across the schema await -- so the
//     model does too, and never rebuilds one;
//   * the glue mutates `picked.roots` IN PLACE on a roots change, replaces
//     `client` on a restart and bumps `stopCount` on a stop -- `sendModel`'s
//     own mutators, reused here unchanged;
//   * the glue's `firstPickTried` is keyed by `attempt.key` and is added to
//     BEFORE the await, so a second render during the wait does not ask a
//     second time. The model adds it in the same place;
//   * the glue writes the params file LAST and relies on the S2 watcher's
//     `onDidCreate` for the render, scheduling nothing itself -- except in
//     the one case where the file turned out to be somebody else's.

/**
 * A disk: path -> text, plus the failure modes a real one has.
 *
 * **IT HOLDS SYMLINKS, BECAUSE A REAL DISK DOES** (the S3 review's M-3, and
 * this file's own model-fidelity rule: a model disk that cannot hold what a
 * real disk holds is a test of a different program). `links` maps a path to
 * whether it is a link; `type` answers VS Code's FileType bitmask the way
 * `statType` reads it, and `read`/`write` FOLLOW a link exactly as node's
 * `fs` does -- which is what made probes 8b and 11 destroy things outside
 * the workspace.
 */
function diskModel(opts) {
  const o = opts || {};
  const files = new Map(o.files || []);
  const links = new Map(o.links || []);        // path -> target path
  return {
    files,
    links,
    creates: [],
    writes: [],
    readOnly: o.readOnly === true,
    symlink(p, target) { links.set(p, target); },
    /** `statType`: null when it is not there, else the FileType bitmask. */
    type(p) {
      if (links.has(p)) return core.FILE_TYPE_SYMLINK | 1;
      if (files.has(p)) return 1;
      if (o.directories && o.directories.indexOf(p) >= 0) return 2;
      return null;
    },
    /** Where a path really lands, following one level of link as fs does. */
    real(p) { return links.has(p) ? links.get(p) : p; },
    /** `vscode.workspace.fs.createDirectory` */
    mkdir() { if (this.readOnly) throw new Error("EROFS: read-only file system"); },
    /** `readTextIfPresent`: null for anything that is not there. */
    read(p) { const r = this.real(p); return files.has(r) ? files.get(r) : null; },
    /**
     * S4: `vscode.workspace.fs.readDirectory`, in ITS OWN shape --
     * `[name, FileType][]`, one level, THROWING for a directory that is not
     * there (`FileNotFound`) exactly as the editor's API documents.
     * `o.readDirThrows` is any other failure (EACCES), which is the arm the
     * orphan scan must not read as "there is nothing stale".
     */
    readDirectory(dir) {
      if (o.readDirThrows) throw o.readDirThrows;
      const prefix = dir.endsWith("/") ? dir : dir + "/";
      const out = [];
      const seen = new Set();
      for (const p of files.keys()) {
        if (!p.startsWith(prefix)) continue;
        const rest = p.slice(prefix.length);
        const cut = rest.indexOf("/");
        const name = cut < 0 ? rest : rest.slice(0, cut);
        if (seen.has(name)) continue;
        seen.add(name);
        out.push([name, cut < 0 ? (links.has(p) ? DIR_LINKED_FILE : DIR_FILE) : DIR_DIRECTORY]);
      }
      for (const d of o.directories || []) {
        if (!d.startsWith(prefix)) continue;
        const name = d.slice(prefix.length);
        if (name.indexOf("/") >= 0 || seen.has(name)) continue;
        seen.add(name);
        out.push([name, DIR_DIRECTORY]);
      }
      if (!out.length && !(o.directories || []).includes(dir.replace(/\/$/, ""))) {
        const err = new Error("EntryNotFound (FileSystemError)");
        err.code = "FileNotFound";
        throw err;
      }
      return out;
    },
    /** `writeTextFile`: OVERWRITES, like `workspace.fs.writeFile`. */
    write(p, text) {
      if (this.readOnly) throw new Error("EROFS: read-only file system");
      files.set(this.real(p), text);
      this.writes.push(this.real(p));
    },
    /**
     * `createFileWithoutOverwriting`, including the read-back.
     * `o.ignoresContents` models a VS Code that honours `createFile` but not
     * its `contents` option -- the case the read-back exists for.
     */
    create(p, text) {
      if (this.readOnly) return core.createOutcome(core.CREATE_FAILED, "EROFS: read-only file system");
      // The look before, which decides nothing about safety and everything
      // about what is SAID: a file already holding exactly these bytes was
      // not created by us (MEASURED against a real disk, wp8-s3/measure.log).
      if (this.read(p) !== null) return core.createOutcome(core.EXISTED);
      const r = this.real(p);                       // a link is followed, as fs does
      this.creates.push(r);
      // A RACING WRITER, landing between the look-before and the read-back,
      // which is the only way the zero-byte branch is reachable at all and
      // is how the review MEASURED M-5.
      if (o.racingCreate !== undefined) files.set(r, o.racingCreate);
      else if (!files.has(r)) files.set(r, o.ignoresContents ? "" : text);
      const after = this.read(p);
      if (after === null) return core.createOutcome(core.CREATE_FAILED, "it is not there after the create");
      if (after === text) return core.createOutcome(core.CREATED);
      // M-5: ZERO BYTES, not "empty". Whitespace is somebody's bytes.
      if (after === "") { this.write(p, text); return core.createOutcome(core.CREATED); }
      return core.createOutcome(core.EXISTED);
    },
  };
}

const SALES_PATHS = core.paramsPaths(SALES_PICK, "/w", "posix");

/**
 * `sendModel` with the S3 branch in it.  Everything `sendModel` does is
 * unchanged; the additions are the disk, the schema deferreds, and the
 * no-file branch between the consultation and the latch -- which is exactly
 * where `extension.js` puts it.
 *
 * MUTANTS, each an option, each run against the SAME interleavings:
 *   `mutantNoSchemaGap`   the answer is used without `mayUseSchemaAnswer`;
 *   `mutantParamsOverwrite` the params file is written unconditionally;
 *   `mutantExplicitRender` a render is issued after the write as well;
 *   `mutantNoSchemaGuard`  the schema request skips the consultation;
 *   `mutantStaleSchema`    `schemaFileFor` is fed the file read back off the
 *                          disk instead of the server's fresh answer.
 */
function firstPickModel(opts) {
  const o = opts || {};
  const m = sendModel(o);
  m.disk = o.disk || diskModel();
  m.schemas = [];            // one deferred per ermine/schema request
  m.scheduled = [];          // scheduleRender calls
  m.opened = [];             // U2: the documents actually SHOWN
  // `openedParamsFiles`, and `openParamsDocument` through the SAME pure
  // dedupe the glue calls (the S4 review's M-4: the model pushed
  // unconditionally, so "once per path per session" was pinned, not tested).
  m.openedParamsFiles = new Set();
  m.openParamsDocument = (fsPath, always) => {
    if (core.claimParamsDocument(m.openedParamsFiles, fsPath, always)) m.opened.push(fsPath);
  };
  m.notices = [];
  m.firstPickTried = new Set();
  // WP-34: the glue's `noParametersPicks`, and the `paramsNoticeOnce` lines
  // (reasons only) this model says, where the glue says them.
  m.noParametersPicks = new Set();
  m.paramsNotices = [];
  m.revealNextRender = false;
  m.reveals = [];
  m.today = TODAY;

  const scheduleRender = (reason, trigger) => m.scheduled.push({ reason, trigger });
  const notice = (reason, line) => m.notices.push({ reason, line });

  /** `requestSchema(attempt)`. */
  m.requestSchema = async function (attempt) {
    // N-f: THE BUILDER, BARE, exactly as the glue returns it. This arm
    // double-wrapped it while the comment below asserted the opposite --
    // the very class this round closed, gone latent because nothing drove it.
    if (!m.hasClient) return core.schemaRequestFailure(new Error("there is no language client"));
    const d = deferred();
    m.schemas.push({ key: attempt.key, settle: d.settle });
    const reply = await d.promise;
    // **D-1: the same builder the glue calls, for EVERY arm.** The model
    // used to wrap the rejection itself and mint `{abandoned: still}` as a
    // literal, which is M-1's class with the sign reversed.
    if (reply && reply.__reject) return core.schemaRequestFailure(reply.err);
    // WP-34's reverse mutant: the marker read as a schema, as 0.1.15 did.
    if (o.mutantNoParamsAsSchema) return core.schemaOutcome({ schema: reply });
    const still = o.mutantNoSchemaGap
      ? { send: true }
      : core.mayUseSchemaAnswer(
          attempt,
          core.previewNow(m.generation, m.picked, m.clientEpoch, m.stopCount, m.hasClient),
          m.picked);
    if (!still.send) return core.schemaAbandoned(still);
    return core.schemaAnswerOutcome(reply);
  };

  /** `applyWritePlan(files, paramsPath, allowExplicitOverwrite)`, statement
    * for statement -- INCLUDING S4's third argument, which is the PERMISSION
    * to replace a params file and which only U3's command ever passes. */
  m.applyWritePlan = function (files, paramsPath, allowExplicitOverwrite) {
    const wrote = [];
    const problems = [];
    for (const file of files) {
      // M-2: a PURE decision, and it fails CLOSED. The mutant is the
      // fail-OPEN `else` the first cut shipped.
      const step = o.mutantParamsOverwrite
        ? { act: file.mode === core.WRITE_IF_ABSENT ? "MUTANT" : core.WRITE_IF_DIFFERENT, problem: null }
        : core.writeStep(file, paramsPath, allowExplicitOverwrite);
      if (step.problem) {
        problems.push(step.problem);
        if (file.what === core.WRITE_PARAMS) return core.writeOutcome({ wrote, problems });
        continue;
      }
      if (step.act === core.WRITE_EXPLICIT_OVERWRITE) {   // S4/U3, after the modal
        m.disk.write(file.path, file.text);
        wrote.push(file.what);
        continue;
      }
      if (step.act === "MUTANT") {                   // the unconditional overwrite
        m.disk.write(file.path, file.text);
        wrote.push(file.what);
        continue;
      }
      if (step.act === core.WRITE_IF_ABSENT) {
        const outcome = m.disk.create(file.path, file.text);
        if (outcome.outcome === core.CREATE_FAILED) {
          problems.push(core.writeFailedProblem(file.what, file.path, outcome.why));
          // N-5: the generated .gitignore is a convenience.
          if (file.what === core.WRITE_GITIGNORE) continue;
          return core.writeOutcome({ wrote, problems });
        }
        if (outcome.outcome === core.CREATED) wrote.push(file.what);
        else if (file.what === core.WRITE_PARAMS) return core.writeOutcome({ wrote, existed: true, problems });
        continue;
      }
      const existing = m.disk.read(file.path);
      if (!core.schemaFileNeedsWrite(existing, file.text)) continue;
      m.disk.write(file.path, file.text);
      wrote.push(file.what);
    }
    return core.writeOutcome({ wrote, problems });
  };

  /** `firstPickSchemaAndWrite(attempt, paths)`. */
  m.firstPickSchemaAndWrite = async function (attempt, paths) {
    const outcome = await m.requestSchema(attempt);
    if (outcome.abandoned) {
      m.log.push("schema discarded (" + outcome.abandoned.reason + ")");
      return core.firstPickResult({ abandoned: true });
    }
    if (outcome.problem) { notice(outcome.problem.reason, outcome.problem.message); return core.firstPickResult({}); }
    // WP-34: a report with NO parameters -- nothing written, nothing opened.
    if (outcome.noParameters) {
      notice("no-parameters", core.noParametersNotice(attempt.label));
      return core.firstPickResult({ noParameters: true });
    }
    // THE FRESH ANSWER, ALWAYS (the S1 review's D-1 obligation). The mutant
    // feeds the file back off the disk instead.
    const source = o.mutantStaleSchema && m.disk.read(paths.schemaPath) !== null
      ? JSON.parse(m.disk.read(paths.schemaPath))
      : outcome.schema;
    const plan = core.paramsWritePlan(paths, source, m.today);
    if (plan.problem) { notice(plan.problem.reason, plan.problem.message); return core.firstPickResult({}); }
    // M-3: the symlink check, BEFORE the directory is made, over the same
    // paths the glue stats and through the same pure pair.
    if (!o.mutantNoSymlinkCheck) {
      const seen = [];
      for (const target of core.writeTargetPaths(
             paths, [paths.gitignorePath, paths.schemaPath, paths.paramsPath], "posix")) {
        const type = m.disk.type(target);
        if (type !== null) seen.push({ path: target, type });
      }
      const linked = core.writeTargetProblem(seen);
      if (linked) { notice(linked.reason, linked.message); return core.firstPickResult({}); }
    }
    let applied;
    try {
      m.disk.mkdir(paths.dir);
      applied = m.applyWritePlan(plan.files, paths.paramsPath);
    } catch (err) {
      notice("write-failed", String(err && err.message ? err.message : err));
      return core.firstPickResult({});
    }
    for (const problem of applied.problems) notice(problem.reason, problem.message);
    if (applied.problems.length && applied.wrote.indexOf(core.WRITE_PARAMS) < 0 && !applied.existed) {
      return core.firstPickResult({});
    }
    if (applied.existed) {
      m.log.push("a params file appeared while the schema was being worked out");
      return core.firstPickResult({ wrote: true, raced: true });
    }
    if (applied.wrote.indexOf(core.WRITE_PARAMS) < 0) return core.firstPickResult({});
    // M-4 of the S4 review: the PLAN, through the builder the glue calls --
    // this line used to drop `plan.shape`, so every model test of this
    // notice read the generic fallback sentence.
    notice("written", core.skeletonWrittenNotice(paths, plan, false));
    m.openParamsDocument(paths.paramsPath);
    return core.firstPickResult({ wrote: true });
  };

  /** `renderNow`, with the S3 branch where `extension.js` puts it. */
  const inner = m.renderNow;
  m.renderNow = async function (reason, reveal, trigger, scheduledAt) {
    if (!m.picked) return;
    if (!m.hasClient) { m.log.push("no client"); return; }
    m.generation += 1;
    const attempt = core.renderAttempt(
      m.generation, m.picked, m.clientEpoch, m.stopCount, m.stuck.highWater);
    const mine = attempt.generation;
    const sentPick = attempt.pick;
    m.renderInFlight = true;
    const revealThis = reveal === true || m.revealNextRender;
    m.revealNextRender = false;

    const read = deferred();
    m.reads.push({ generation: mine, settle: read.settle });
    const prepared = await read.promise;

    const verdict = core.mayStillSend(
      attempt, core.previewNow(m.generation, m.picked, m.clientEpoch, m.stopCount, m.hasClient));
    if (!verdict.send) {
      m.log.push("abandoned " + mine + " (" + verdict.reason + ")");
      if (mine === m.generation) m.renderInFlight = false;
      return;
    }
    // WP-34: the "no params file" line is HELD while it may be false.
    const heldNotice = o.mutantNeverHoldNotice
      ? false
      : core.holdsParamsNotice(prepared, m.firstPickTried.has(attempt.key), m.noParametersPicks.has(attempt.key));
    if (prepared.notice && !heldNotice) m.paramsNotices.push(prepared.notice.reason);
    if (prepared.refusal) {
      const refusal = core.paramsRefusalAnswer(prepared.refusal, prepared.path, mine);
      m.lastAnswer = refusal;
      if (mine === m.generation) m.renderInFlight = false;
      m.tabs.push(refusal);
      m.reveals.push({ generation: mine, reveal: revealThis });
      return;
    }
    m.mark = core.guardReduce(m.mark, { type: "params", pick: sentPick, params: prepared.params }).mark;
    const permitted = o.mutantNoSchemaGuard
      ? { render: true, why: null }
      : core.mayAutoRender(m.mark, sentPick, trigger, scheduledAt);
    if (!permitted.render) {
      m.log.push("held " + mine + " (" + trigger + ")");
      m.held.push({ generation: mine, trigger, mark: m.mark, why: permitted.why });
      if (mine === m.generation) m.renderInFlight = false;
      return;
    }

    // ---- S3, BELOW THE CONSULTATION ----------------------------------------
    // **`prepared.paths`, NOT A MODEL CONSTANT** (the S3 review's M-1): the
    // glue reads what `prepareParams` answered, so the model must too.
    const order = core.schemaOrder(prepared.paths, prepared.notice && prepared.notice.reason === "missing");
    if (order.first === "schema" && !m.firstPickTried.has(attempt.key)) {
      m.firstPickTried.add(attempt.key);
      const written = await m.firstPickSchemaAndWrite(attempt, prepared.paths);
      if (written.noParameters) m.noParametersPicks.add(attempt.key);
      if (written.wrote) {
        // M-4: the render is SCHEDULED, carrying THIS render's own trigger,
        // instead of being left to an event nobody has ever seen fire.
        m.revealNextRender = revealThis;
        scheduleRender(written.raced
          ? "a params file appeared while the parameter schema was being worked out"
          : "the params skeleton was written",
          o.mutantWatcherTrigger ? core.TRIGGER_PARAMS_FILE : trigger);
        if (mine === m.generation) m.renderInFlight = false;
        return;
      }
      const afterSchema = core.mayStillSend(
        attempt, core.previewNow(m.generation, m.picked, m.clientEpoch, m.stopCount, m.hasClient));
      if (!afterSchema.send) {
        m.log.push("abandoned " + mine + " (" + afterSchema.reason + ")");
        if (mine === m.generation) m.renderInFlight = false;
        return;
      }
    }

    if (heldNotice && !m.noParametersPicks.has(attempt.key)) m.paramsNotices.push(prepared.notice.reason);
    m.lastParamsSent = prepared.params;
    m.inFlight = { generation: mine, pick: sentPick, params: prepared.params };
    m.sent.push(core.renderRequest(attempt, prepared.params));
    m.reveals.push({ generation: mine, reveal: revealThis });
    m.log.push("sent " + mine);
    const wire = deferred();
    m.wires.push({ generation: mine, settle: wire.settle });
    const answer = await wire.promise;
    if (m.inFlight && m.inFlight.generation === mine) m.inFlight = null;
    if (mine === m.generation) m.renderInFlight = false;
    m.lastAnswer = answer;
    m.lastServerAnswer = answer;
    m.tabs.push(answer);
    // D8's refresh, NOT awaited in the glue either.
    const refresh = core.shouldRefreshSchema(answer, trigger);
    if (refresh.refresh) m.refreshes = (m.refreshes || []).concat([{ generation: mine, why: refresh.why }]);
  };
  void inner;

  /** `refreshSchemaFile(attempt, paths, why)`, statement for statement. */
  m.refreshSchemaFile = async function (attempt, paths, why) {
    const outcome = await m.requestSchema(attempt);
    if (outcome.abandoned) { m.log.push("refresh discarded (" + outcome.abandoned.reason + ")"); return; }
    if (outcome.problem) {
      notice("refresh-" + outcome.problem.reason,
             "could not refresh " + paths.schemaPath + ": " + outcome.problem.message);
      return;
    }
    if (outcome.noParameters) {
      notice("refresh-no-parameters", core.noParametersNotice(attempt.label));
      return;
    }
    if (!o.mutantNoSymlinkCheck) {
      const seen = [];
      for (const target of core.writeTargetPaths(paths, [paths.schemaPath], "posix")) {
        const type = m.disk.type(target);
        if (type !== null) seen.push({ path: target, type });
      }
      const linked = core.writeTargetProblem(seen);
      if (linked) { notice(linked.reason, linked.message); return; }
    }
    // D-1's defence in depth: the bytes, or a named refusal.
    const bytes = core.schemaFileBytes(outcome.schema);
    if (bytes.problem) {
      notice("refresh-" + bytes.problem.reason, bytes.problem.message);
      return;
    }
    const existing = m.disk.read(paths.schemaPath);
    if (!core.schemaFileNeedsWrite(existing, bytes.text)) return;
    m.disk.write(paths.schemaPath, bytes.text);
    m.log.push("rewrote " + paths.schemaPath + " (" + why + ")");
  };

  m.answerSchema = (i, answer) => m.schemas[i].settle(answer);
  m.rejectSchema = (i, err) => m.schemas[i].settle({ __reject: true, err });
  return m;
}

test("S3 ASYNC: the ordinary first pick -- schema, three files, the document opened, ONE render", async () => {
  const m = firstPickModel();
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);                                   // there is no params file
  await flush();
  assert.strictEqual(m.sent.length, 0, "the certain-400 render is NOT sent");
  assert.strictEqual(m.schemas.length, 1, "one ermine/schema, and only one");
  m.answerSchema(0, SALES_SCHEMA);
  await flush();

  // THE THREE FILES, IN ORDER, AND THE PARAMS FILE LAST.
  assert.deepStrictEqual(m.disk.creates, [
    "/w/.ermine/preview/.gitignore",
    "/w/.ermine/preview/Sales/report.params.json",
  ]);
  assert.deepStrictEqual(m.disk.writes, ["/w/.ermine/preview/Sales/report.schema.json"]);
  assert.strictEqual(m.disk.read("/w/.ermine/preview/.gitignore"), core.paramsGitignoreText);
  assert.deepStrictEqual(JSON.parse(m.disk.read("/w/.ermine/preview/Sales/report.params.json")),
    { $schema: "./report.schema.json", fromDay: TODAY, toDay: TODAY, orderBy: "ByDay" });

  // U2: the params document is opened, once.
  assert.deepStrictEqual(m.opened, ["/w/.ermine/preview/Sales/report.params.json"]);
  // ONE NOTICE, and it names all three files.
  assert.strictEqual(m.notices.length, 1);
  assert.strictEqual(m.notices[0].reason, "written");

  // **M-4: THE RENDER IS SCHEDULED, NOT LEFT TO AN EVENT NOBODY HAS SEEN
  // FIRE**, and it carries THIS render's own trigger rather than the
  // watcher's `params-file` (N-3). It goes through the 150 ms coalescer, so
  // a watcher event inside that window merges into the same one.
  assert.strictEqual(m.scheduled.length, 1, "exactly one render is scheduled");
  assert.strictEqual(m.scheduled[0].trigger, core.TRIGGER_EXPLICIT,
    "consent stays consent: the watcher's own event would have carried `params-file`");
  assert.strictEqual(m.sent.length, 0, "and nothing is sent from HERE");
  assert.strictEqual(m.renderInFlight, false, "and the spinner is released");
  // THE REVEAL THE PICK WOULD OTHERWISE LOSE is carried to that render.
  assert.strictEqual(m.revealNextRender, true);

  // THAT RENDER, 150 ms later, reading the file that is now there.
  m.renderNow(m.scheduled[0].reason, false, m.scheduled[0].trigger);
  await flush();
  m.readOk(1, { fromDay: TODAY, toDay: TODAY, orderBy: "ByDay" });
  await flush();
  assert.strictEqual(m.sent.length, 1, "exactly ONE render comes of the write");
  assert.strictEqual(m.schemas.length, 1, "and it does NOT ask for the schema again");
  assert.strictEqual(m.reveals[0].reveal, true, "the tab the pick asked for is revealed after all");
});

test("S3 ASYNC: the pick CHANGES while the schema is being worked out -- nothing is written", async () => {
  const m = firstPickModel();
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  // The user picks another report. The glue replaces `picked` here.
  m.picked = core.makePick(OTHER_PICK.uri, OTHER_PICK.fsPath, "report", "Other", ["/w/doc"]);
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.strictEqual(m.disk.files.size, 0, "NOTHING is written for a report nobody picked (D7)");
  assert.deepStrictEqual(m.opened, []);
  assert.strictEqual(m.sent.length, 0);
  assert.ok(m.log.some((l) => /schema discarded \(pick-changed\)/.test(l)), m.log.join(" | "));
});

test("S3 ASYNC: the MODULE is renamed under the same file -- the one mayStillSend cannot see", async () => {
  const m = firstPickModel();
  m.renderNow("invalidated", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readMissing(0);
  await flush();
  // Same uri, same binding, same roots, DIFFERENT module: the directory the
  // file would be written into has moved.
  m.picked = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales2", ["/w/doc"]);
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.strictEqual(m.disk.files.size, 0, "the schema would have been written into the OLD directory");
  assert.ok(m.log.some((l) => /schema discarded \(pick-changed\)/.test(l)));
});

test("S3 ASYNC: a RESTART during the schema wait -- nothing is written, nothing is sent", async () => {
  for (const [what, move] of [
    ["a new client", (m) => m.serverRestarted()],
    ["a stop on the same client", (m) => m.serverStopped()],
    ["a teardown", (m) => m.tearDown()],
    ["a newer render", (m) => { m.generation += 1; }],
  ]) {
    const m = firstPickModel();
    m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
    await flush();
    m.readMissing(0);
    await flush();
    move(m);
    m.answerSchema(0, SALES_SCHEMA);
    await flush();
    assert.strictEqual(m.disk.files.size, 0, what + ": nothing is written");
    assert.strictEqual(m.sent.length, 0, what + ": nothing is sent");
  }
});

test("S3 ASYNC: the ROOTS change IN PLACE during the schema wait (the S2 review's M1 shape)", async () => {
  const m = firstPickModel();
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  // THE GLUE MUTATES `picked.roots`, it does not replace the pick. A model
  // that replaced it would be testing a different program (the file header's
  // rule, and the defect it was written after).
  m.rootsChangeInPlace(["/w/other"]);
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.strictEqual(m.disk.files.size, 0,
    "a schema computed under the old roots may describe a same-named module from another tree");
  assert.ok(m.log.some((l) => /roots-changed|pick-changed/.test(l)), m.log.join(" | "));
});

test("S3 ASYNC: a params file APPEARS during the schema wait -- it is never clobbered", async () => {
  const mine = '{"fromDay":"2026-01-05","toDay":"2026-02-20","orderBy":"ByAmount"}\n';
  const disk = diskModel();
  const m = firstPickModel({ disk });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  // A `git checkout`, a second window, a colleague's script: the file is
  // there between the read that said it was not and the write.
  disk.files.set("/w/.ermine/preview/Sales/report.params.json", mine);
  m.answerSchema(0, SALES_SCHEMA);
  await flush();

  assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.params.json"), mine,
    "THE RACE, ANSWERED: committed source is never overwritten");
  assert.deepStrictEqual(m.opened, [], "and a file we did not write is not opened over what you are typing");
  assert.strictEqual(m.notices.filter((n) => n.reason === "written").length, 0);
  // We caused no create event, so nothing else may have scheduled a render:
  // this is the ONE case in which the no-file branch asks for one itself.
  assert.deepStrictEqual(m.scheduled.map((s) => s.trigger), [core.TRIGGER_EXPLICIT]);
  assert.match(m.scheduled[0].reason, /appeared/);
  // The schema file and the .gitignore WERE written: they are ours.
  assert.ok(disk.read("/w/.ermine/preview/Sales/report.schema.json") !== null);
  assert.ok(disk.read("/w/.ermine/preview/.gitignore") !== null);
});

test("S3 ASYNC: a READ-ONLY workspace -- one notice, no files, and the render happens anyway", async () => {
  const disk = diskModel({ readOnly: true });
  const m = firstPickModel({ disk });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.strictEqual(disk.files.size, 0);
  assert.strictEqual(m.notices.length, 1);
  assert.strictEqual(m.notices[0].reason, "write-failed");
  // NON-FATAL: the report renders, with the inline `{}` WP-7 sends.
  assert.strictEqual(m.sent.length, 1);
  assert.deepStrictEqual(m.sent[0].params, {});
  assert.strictEqual(m.reveals[0].reveal, true, "and it still reveals the tab the pick asked for");
});

test("S3 ASYNC: the editor creates the file but drops the contents -- the read-back catches it", async () => {
  // `WorkspaceEdit.createFile`'s `contents` option is DOCUMENTED and its
  // behaviour here is UNVERIFIED (nobody has run this extension). A create
  // that produced an EMPTY params file would be an S1 REFUSAL on the next
  // render -- so the file is read back, and zero content is the one thing
  // this extension will ever write over.
  const disk = diskModel({ ignoresContents: true });
  const m = firstPickModel({ disk });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.deepStrictEqual(JSON.parse(disk.read("/w/.ermine/preview/Sales/report.params.json")),
    { $schema: "./report.schema.json", fromDay: TODAY, toDay: TODAY, orderBy: "ByDay" });
  assert.deepStrictEqual(m.opened, ["/w/.ermine/preview/Sales/report.params.json"]);
});

test("S3 ASYNC: every way the schema request can fail falls back to `{}` and says so ONCE", async () => {
  for (const [what, reply] of [
    ["an {error}", { error: "no module named Sales", reason: "not-placed" }],
    ["a stuck refusal", { error: "the preview is stuck", stuck: true }],
    ["something that is not a schema", 7],
  ]) {
    const m = firstPickModel();
    m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
    await flush();
    m.readMissing(0);
    await flush();
    m.answerSchema(0, reply);
    await flush();
    assert.strictEqual(m.disk.files.size, 0, what);
    assert.strictEqual(m.notices.length, 1, what);
    assert.strictEqual(m.sent.length, 1, what + ": the render still happens");
    assert.deepStrictEqual(m.sent[0].params, {}, what);
  }
  // A transport rejection is the same story through the other door.
  const m = firstPickModel();
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.rejectSchema(0, new Error("Connection got disposed"));
  await flush();
  assert.strictEqual(m.notices[0].reason, "request-failed");
  assert.strictEqual(m.sent.length, 1);
});

test("S3 ASYNC: a failed first pick is NOT retried on every render (the loop that would be)", async () => {
  const m = firstPickModel();
  for (let i = 0; i < 4; i++) {
    m.renderNow("invalidated", false, core.TRIGGER_INVALIDATED);
    await flush();
    m.readMissing(i);
    await flush();
    if (m.schemas.length > i && i === 0) { m.answerSchema(0, { error: "boom" }); await flush(); }
    if (m.wires.length) { m.answerWith(m.wires.length - 1, { ok: true, generation: m.generation, document: {} }); await flush(); }
  }
  assert.strictEqual(m.schemas.length, 1, "ONE attempt per pick: a failed schema is not re-asked per render");
  assert.strictEqual(m.notices.length, 1, "and the sentence is said once, not four times");
  assert.strictEqual(m.sent.length, 4, "while every render still happens");
});

test("S3 ASYNC: TWO first picks in quick succession ask ONCE and write ONCE", async () => {
  const m = firstPickModel();
  // Two renders of the SAME pick overlap: the pick's own, and a save that
  // landed inside the coalescing window and scheduled another.
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.renderNow("invalidated", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readMissing(0);
  m.readMissing(1);
  await flush();
  // The FIRST is superseded by the second at the gap check (it is older), so
  // only one reaches the branch -- and `firstPickTried` holds the key from
  // BEFORE the await, so even if both had, only one request would go out.
  assert.strictEqual(m.schemas.length, 1, "one ermine/schema for two overlapping renders");
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.strictEqual(m.disk.creates.filter((p) => /params\.json$/.test(p)).length, 1);
  assert.deepStrictEqual(m.opened, ["/w/.ermine/preview/Sales/report.params.json"]);
});

test("S3 ASYNC: a HELD report is never handed a schema request", async () => {
  // A schema job COMPILES and EVALUATES the binding on the preview queue
  // (`json/Runner.scala:849-852`), so it is the very thing WP-22 holds --
  // not a read.
  const m = firstPickModel();
  m.mark = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: m.picked, params: {}, at: 1 }).mark;
  assert.ok(core.markMatches(m.mark, m.picked));
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readMissing(0);
  await flush();
  assert.strictEqual(m.schemas.length, 0, "no schema request for a report that wedged and did not change");
  assert.strictEqual(m.disk.files.size, 0, "and nothing is written");
  assert.strictEqual(m.sent.length, 0);
  assert.strictEqual(m.held.length, 1);

  // AND CONSENT LETS IT THROUGH: the same pick, rendered explicitly.
  m.mark = core.guardReduce(m.mark, { type: "render", explicit: true }).mark;
  m.renderNow("Render anyway", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(1);
  await flush();
  assert.strictEqual(m.schemas.length, 1);
});

test("S3 ASYNC: D8's refresh runs after the right answers and the right triggers only", async () => {
  const cases = [
    [core.TRIGGER_INVALIDATED, { ok: true, generation: 1, document: {} }, 1],
    [core.TRIGGER_EXPLICIT, { ok: false, status: 400, path: "$.params.fromDay", generation: 1 }, 1],
    [core.TRIGGER_INVALIDATED, { ok: false, status: 500, message: "boom", generation: 1 }, 0],
    // A params save cannot have changed the parameter TYPE -- and this is
    // also what stops a first pick asking for the schema twice in a row.
    [core.TRIGGER_PARAMS_FILE, { ok: true, generation: 1, document: {} }, 0],
    // The `fx.schema` seam owns these two edges.
    [core.TRIGGER_RESTART, { ok: true, generation: 1, document: {} }, 0],
    [core.TRIGGER_RECOVERED, { ok: true, generation: 1, document: {} }, 0],
  ];
  for (const [trigger, answer, expected] of cases) {
    const m = firstPickModel({ disk: diskModel({ files: [["/w/.ermine/preview/Sales/report.params.json", "{}"]] }) });
    m.renderNow("a render", false, trigger);
    await flush();
    m.readOk(0, {});
    await flush();
    m.answerWith(0, Object.assign({}, answer, { generation: m.generation }));
    await flush();
    assert.strictEqual((m.refreshes || []).length, expected, trigger + " " + JSON.stringify(answer));
  }
});

// ----------------------------------------------------------------- mutants

test("S3 MUTANT: the schema answer used without the gap check writes for the WRONG pick", async () => {
  const m = firstPickModel({ mutantNoSchemaGap: true });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.picked = core.makePick(OTHER_PICK.uri, OTHER_PICK.fsPath, "report", "Other", ["/w/doc"]);
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.ok(m.disk.files.size > 0, "the mutant writes Sales's files for a pick that is now Other");
  assert.ok(m.opened.length > 0, "and opens a document for a report nobody picked");
});

test("S3 MUTANT: an unconditional params write DESTROYS committed source", async () => {
  const mine = '{"fromDay":"2026-01-05","toDay":"2026-02-20","orderBy":"ByAmount"}\n';
  const disk = diskModel();
  const m = firstPickModel({ disk, mutantParamsOverwrite: true });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  disk.files.set("/w/.ermine/preview/Sales/report.params.json", mine);
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.notStrictEqual(disk.read("/w/.ermine/preview/Sales/report.params.json"), mine,
    "the mutant clobbers the file that appeared -- which is what `ifAbsent` exists to stop");
});

test("S3 MUTANT (N-3): a scheduled render carrying the WATCHER's trigger HOLDS an explicit pick", async () => {
  // A params type with NO required fields skeletonises to `{"$schema": ...}`
  // and SENDS `{}` -- which fingerprints identically to whatever wedged the
  // report. So a render carrying `params-file` (UNCONFIRMED) is refused, and
  // the user who explicitly picked the report is asked a question instead of
  // shown a document, seconds later. MEASURED by the S3 review
  // (`scratchpad/wp8s3-review/edge-empty.js`), and the reason M-4's
  // scheduled render carries THIS render's own trigger.
  const EMPTY_PARAMS = {
    $schema: "https://json-schema.org/draft/2020-12/schema", $id: "ermine:Sales/Query",
    $ref: "#/$defs/Sales.Query",
    $defs: { "Sales.Query": { type: "object", additionalProperties: false,
                              properties: { onlyRegion: { type: "string" } }, required: [] } } };
  const run = async (opts) => {
    const m = firstPickModel(opts);
    // The report wedged the preview with `{}` -- a mark that this pick's
    // skeleton cannot clear, because the skeleton SENDS `{}` too.
    m.mark = core.guardReduce(null, {
      type: "answer", stuck: true, applies: true, pick: m.picked, params: {}, at: 1 }).mark;
    m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
    await flush();
    m.readMissing(0);
    await flush();
    m.answerSchema(0, EMPTY_PARAMS);
    await flush();
    assert.strictEqual(m.scheduled.length, 1);
    m.renderNow(m.scheduled[0].reason, false, m.scheduled[0].trigger);
    await flush();
    m.readOk(1, {});
    await flush();
    return m;
  };
  const mutant = await run({ mutantWatcherTrigger: true });
  assert.strictEqual(mutant.sent.length, 0, "the mutant renders nothing");
  assert.strictEqual(mutant.held.length, 1, "and asks the user a question instead");
  assert.match(mutant.held[0].why, /nothing about .* has changed/);

  const good = await run({});
  assert.strictEqual(good.sent.length, 1, "consent stays consent: the document is rendered");
  assert.strictEqual(good.held.length, 0);
});

test("S3 MUTANT: a schema request that skips the consultation reaches a held report", async () => {
  const m = firstPickModel({ mutantNoSchemaGuard: true });
  m.mark = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: m.picked, params: {}, at: 1 }).mark;
  m.renderNow("the params file was saved", false, core.TRIGGER_PARAMS_FILE);
  await flush();
  m.readMissing(0);
  await flush();
  assert.strictEqual(m.schemas.length, 1,
    "the mutant hands a job that compiles and evaluates the report to a server it just wedged");
});

test("S3 MUTANT: feeding the WRITTEN schema file back leaves the root-level copy stale", () => {
  // THE S1 REVIEW'S D-1 OBLIGATION, and the one thing section 6 makes S3
  // promise. `schemaFileFor` mints a root-level COPY of a `$defs` entry that
  // also describes a nested position; a copy tracks its original only within
  // the call that made it.
  const tree = JSON.parse(
    fs.readFileSync(path.join(__dirname, "fixtures", "user-tree.schema.json"), "utf8"));
  const written = core.schemaFileFor(tree);
  const copyName = Object.keys(written.$defs).find((n) => /-params-root$/.test(n));
  assert.ok(copyName, "the fixture must be the recursive case D-1 turns on");

  // THE PARAMS TYPE MOVES UPSTREAM: a field is added to the shared entry.
  const moved = JSON.parse(JSON.stringify(tree));
  const shared = moved.$defs[copyName.replace(/-params-root$/, "")];
  const arm = shared.oneOf ? shared.oneOf[shared.oneOf.length - 1] : shared;
  arm.properties.newField = { type: "string" };
  arm.required.push("newField");

  // THE RIGHT WAY: the server's fresh answer. The copy carries the new field.
  const fresh = core.schemaFileFor(moved);
  const freshCopy = fresh.$defs[Object.keys(fresh.$defs).find((n) => /-params-root$/.test(n))];
  const freshArm = freshCopy.oneOf ? freshCopy.oneOf[freshCopy.oneOf.length - 1] : freshCopy;
  assert.ok(freshArm.properties.newField, "the fresh answer's copy has the new field");

  // THE FORBIDDEN ROUND TRIP: the file we wrote, fed back. The copy is
  // already there, referenced by nothing else, so nothing re-mints it -- and
  // it silently keeps the OLD shape while the shared entry beside it moves.
  const stale = core.schemaFileFor(written);
  const staleCopy = stale.$defs[copyName];
  const staleArm = staleCopy.oneOf ? staleCopy.oneOf[staleCopy.oneOf.length - 1] : staleCopy;
  assert.strictEqual(staleArm.properties.newField, undefined,
    "which is why S3 must ALWAYS pass the server's fresh ermine/schema answer");
});

// ------------------------------------------------------------- S3's pins
//
// SOURCE PINS, NOT BEHAVIOUR TESTS. S3 adds a second `await` to the send
// path, a write path and a third caller of the ONE consultation, and none of
// those three shapes is visible to any model in this file: the model is
// written from the glue, so a model and a glue that drift agree with each
// other and with nothing else (this file's header, and the three times it
// has happened). Each message says what the pin is and what it protects.

/**
 * STRIP COMMENTS BEFORE MATCHING A STATEMENT (the S3 review's N-1).
 *
 * The pin protecting the only unbounded loop this stage could have did
 * `renderBody.indexOf("firstPickTried.add(attempt.key);")`. **Commenting the
 * statement out leaves the text in place**, so the pin passed and all 249
 * tests passed -- MEASURED by the review and reproduced here -- while the
 * extension asked for a parameter schema, a preview job that compiles and
 * evaluates the report, once per render for ever in a save-driven loop.
 *
 * Every pin below that matches STATEMENT text now matches against this.
 * Pins that match a log SENTENCE deliberately do not, because a sentence is
 * allowed to be quoted in a comment.
 *
 * **IT WAS TWO REGULAR EXPRESSIONS AND THAT WAS A LIVE TRAP, FOUND AND
 * MEASURED BY S4.** `\/\*[\s\S]*?\*\/` does not know what a STRING is, and
 * `extension.js` contains one: `vscode.workspace.findFiles("**\/*.e")` in
 * `pickReport` holds the two characters that open a block comment. Nothing
 * closed it, so the non-greedy regex simply failed to match and the file
 * survived **by luck**. S4 added a JSDoc block after `renderCommand`, whose
 * `*\/` closed it -- and `codeOf` then deleted **124 lines** of
 * `pickReport`, `renderCommand` and the head of `activate`. MEASURED: the
 * picker's own `renderNow("the report was picked", true,
 * core.TRIGGER_EXPLICIT)` pin went from passing to failing while the source
 * line was untouched, and had S4's block been added a few lines further on
 * the same deletion would have been SILENT -- every pin inside those 124
 * lines would have stopped protecting anything, which is precisely the
 * failure N-1 exists to prevent, one level down in the tool N-1 built.
 *
 * So this is a scanner rather than a pair of regexes: it knows single,
 * double and template strings (with their escapes) and regular-expression
 * literals, and it strips comments and nothing else. A `/` is read as a
 * regex only where one may begin -- after an operator or an opening
 * bracket -- which covers every regex literal in `preview-core.js` (`=`,
 * `(`, `[`, `,`) and leaves division alone. There is a table test for it
 * below, and an assertion that the stripped `extension.js` still contains
 * its last function.
 */
const REGEX_MAY_START = /[=(,:[!&|?{};+\-*%~^<>]/;

function codeOf(text) {
  const s = String(text);
  let out = "";
  let prev = "";                         // the last significant character kept
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    const d = s[i + 1];
    if (c === "/" && d === "/") {        // a line comment: to the newline
      while (i < s.length && s[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && d === "*") {        // a block comment: to its close
      i += 2;
      while (i < s.length && !(s[i] === "*" && s[i + 1] === "/")) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") {
      out += c;
      i += 1;
      while (i < s.length) {
        if (s[i] === "\\") { out += s.slice(i, i + 2); i += 2; continue; }
        out += s[i];
        i += 1;
        if (s[i - 1] === c) break;
      }
      prev = c;
      continue;
    }
    if (c === "/" && REGEX_MAY_START.test(prev)) {
      out += c;
      i += 1;
      let inClass = false;
      while (i < s.length) {
        if (s[i] === "\\") { out += s.slice(i, i + 2); i += 2; continue; }
        if (s[i] === "[") inClass = true;
        else if (s[i] === "]") inClass = false;
        out += s[i];
        i += 1;
        if (s[i - 1] === "/" && !inClass) break;
      }
      prev = "/";
      continue;
    }
    out += c;
    if (!/\s/.test(c)) prev = c;
    i += 1;
  }
  return out;
}

test("glue pins (S3): the first-pick branch, the write path and the guard", () => {
  const fsMod = require("node:fs");
  const raw = fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  // N-1: EVERY statement pin below reads this, not `raw`.
  const src = codeOf(raw);
  const pin = (what, fix) =>
    "source pin (test/preview-core.test.js): extension.js changed shape — " + what +
    ". If you meant it, update this pin; the behaviour it protects is " + fix;
  const renderBody = src.slice(src.indexOf("async function renderNow("), src.indexOf("async function showAnswer("));

  // ---- M-1: THE SHAPES ARE MINTED ONCE, AND THE MODEL CALLS THE SAME ------
  //
  // THE FOURTH OCCURRENCE of this branch's recurring defect. `prepareParams`
  // used to build four object literals while the model built its own;
  // deleting the one word `paths,` from ONE of them turned the whole stage
  // off with 249/249 green (MEASURED). The builders are the structural fix;
  // these pins are only that the glue uses them.
  // The end marker is CODE, not a comment: `codeOf` has stripped the banner
  // that used to delimit this section, which is exactly the trap N-1 names.
  const prepareBody = src.slice(src.indexOf("async function prepareParams("),
                                src.indexOf("const openedParamsFiles = new Set();"));
  assert.ok(prepareBody.length > 0 && prepareBody.length < 4000 && !/return \{/.test(prepareBody),
    pin("prepareParams builds an object literal again instead of going through core.preparedParams",
        "THE FOURTH OCCURRENCE of the model/glue divergence this branch keeps having: a field " +
        "present on one side and absent on the other. Deleting `paths,` from ONE literal turned " +
        "the whole stage off with 249/249 green (MEASURED, the S3 review's M-1)"));
  assert.strictEqual((prepareBody.match(/core\.preparedParams\(/g) || []).length, 7,
    pin("prepareParams has a return that does not go through core.preparedParams", "the same"));
  for (const kind of ["PREPARED_PATH_PROBLEM", "PREPARED_MISSING", "PREPARED_READ", "PREPARED_REFUSAL"]) {
    assert.ok(prepareBody.indexOf("core." + kind) > 0,
      pin("prepareParams no longer has a " + kind + " outcome", "the same"));
  }
  assert.strictEqual((src.match(/return \{ wrote/g) || []).length, 0,
    pin("firstPickSchemaAndWrite or writeIfDifferent builds a `{wrote}` literal again",
        "D-1's builder audit: those eleven returns were raw literals on BOTH sides, which is " +
        "M-1's class once more"));
  assert.ok(/core\.firstPickResult\(/.test(src) && /core\.writeResult\(/.test(src),
    pin("the first-pick and write-if-different results are no longer minted by a builder", "the same"));
  assert.ok(/core\.createOutcome\(/.test(src) && /core\.writeOutcome\(/.test(src) && /core\.schemaAbandoned\(/.test(src),
    pin("one of the S3 glue shapes is built by hand again (the create's answer, the write plan's " +
        "answer, or the schema request's abandon)",
        "the same: every object the glue hands one of its own decisions is minted by ONE exported " +
        "builder that the MODEL calls too, so a field cannot be dropped on one side only"));

  // ---- G15: WHERE the branch sits, which is the whole of its safety -------
  const consult = renderBody.indexOf("core.mayAutoRender(");
  const order = renderBody.indexOf("core.schemaOrder(");
  const write = renderBody.indexOf("firstPickSchemaAndWrite(");
  const latch = renderBody.indexOf("inFlightRender = {");
  assert.ok(consult > 0 && order > consult && write > order && write < latch,
    pin("renderNow's no-file branch is no longer BETWEEN the consultation and the wire",
        "that a report which wedged the preview is not handed an ermine/schema job — which " +
        "COMPILES AND EVALUATES the binding on the preview queue (json/Runner.scala:849-852, and " +
        "lsp/Preview.scala:596-598 says so in the server's own words) — without the user's consent"));
  assert.ok(/const order = core\.schemaOrder\(prepared\.paths, prepared\.notice && prepared\.notice\.reason === "missing"\);/.test(renderBody),
    pin("the ordering rule is not asked of core.schemaOrder, or is asked about something other " +
        "than (this render's paths, and whether the read said there is no file)",
        "G15: no params file -> the schema first (that render is a certain 400 anyway); a file " +
        "present -> the render first and the schema only refreshes the generated file"));
  assert.ok(/if \(order\.first === "schema" && !firstPickTried\.has\(attempt\.key\)\) \{/.test(renderBody),
    pin("the no-file branch is neutered, or no longer keyed by the snapshot's own pick",
        "that a failed schema or a failed write is NOT retried on every render of a save-driven " +
        "loop — which is the only unbounded loop this stage could have"));
  // N-1: the comments are gone from `renderBody`, so commenting this out is
  // now exactly as dead as deleting it (MEASURED: it was not, before).
  const tried = renderBody.indexOf("firstPickTried.add(attempt.key);");
  assert.ok(tried > 0 && tried < write,
    pin("renderNow records the first-pick attempt AFTER the await, or not at all",
        "that two renders overlapping in the coalescing window ask for ONE schema, not two — and " +
        "that a failed attempt is not re-made once per render for ever (N-1: this pin reads the " +
        "source with COMMENTS STRIPPED, because commenting the statement out used to pass it)"));
  // N-10: THE SNAPSHOT, not a fresh one. A rebuilt attempt silently vacates
  // the MODULE half of D7, which `mayStillSend` does not compare.
  assert.ok(/const written = await firstPickSchemaAndWrite\(attempt, prepared\.paths\);/.test(renderBody),
    pin("firstPickSchemaAndWrite is handed something other than THE snapshot and THIS render's paths",
        "D7's module half: `mayUseSchemaAnswer` compares the module and the roots, which " +
        "`mayStillSend` does not, and a freshly built attempt would compare the live pick with " +
        "itself (N-10)"));

  // ---- M-4: ONE RENDER PER COALESCING WINDOW, AND NOTHING OUTSIDE IT ------
  //
  // RE-EXPRESSED from "nothing is rendered after the write". The first cut
  // left the render entirely to the S2 watcher's `onDidCreate`, so a first
  // pick whose watcher never fires showed NO document and NO message. It now
  // schedules one; a watcher event inside 150 ms merges, one outside costs a
  // second identical render with no boot and no mark movement.
  const wroteBranch = renderBody.slice(renderBody.indexOf("if (written.wrote) {"),
                                       renderBody.indexOf("const afterSchema ="));
  assert.ok(wroteBranch.length > 0 && !/renderNow\(/.test(wroteBranch),
    pin("renderNow renders DIRECTLY after writing the skeleton instead of scheduling",
        "that at most ONE render comes of the write: `scheduleRender` clears and re-arms the one " +
        "coalescing timer, so the watcher's own event merges with ours (M-4)"));
  assert.strictEqual((wroteBranch.match(/scheduleRender\(/g) || []).length, 1,
    pin("the first-pick branch schedules a number of renders other than one",
        "the same (M-4)"));
  // MATCHED AS A WHOLE STATEMENT AT THE START OF ITS LINE: `if (false)
  // scheduleRender(...)` keeps every word and every count (MEASURED -- that
  // mutant survived the first expression of this pin).
  assert.ok(/\n      scheduleRender\(written\.raced/.test(wroteBranch),
    pin("the render after the write is guarded away, or is no longer a statement of its own",
        "M-4: a first pick whose watcher event never fires would show NO document and NO " +
        "message, which is the wrong failure mode for the feature's first minute"));
  assert.ok(/scheduleRender\(written\.raced[\s\S]{0,220}?, trigger\);/.test(wroteBranch),
    pin("the render scheduled after the write no longer carries THIS render's own trigger",
        "N-3: the watcher's event carries `params-file`, which is UNCONFIRMED — so an EXPLICIT " +
        "pick of a previously-wedged report whose params type has no required fields was answered " +
        "with the held question instead of a document (MEASURED by the review)"));
  assert.ok(/if \(mine === generation\) renderInFlight = false;/.test(wroteBranch),
    pin("the first-pick exit of renderNow no longer releases the spinner under its generation guard",
        "that a first pick leaves the status bar idle rather than spinning for ever (R5, R11)"));
  // AND THE SECOND GAP CHECK, for the path where nothing was written.
  assert.ok(/const afterSchema = core\.mayStillSend\(\s*\n?\s*attempt, core\.previewNow\(generation, picked, clientEpoch, stopCount, !!client\)\);/.test(renderBody) &&
            /if \(!afterSchema\.send\) \{/.test(renderBody),
    pin("renderNow does not re-check the gap after the schema request, or does not act on it",
        "that a pick change, a restart or a newer render during the SCHEMA await abandons this " +
        "render instead of sending for the wrong pick — the same rule S2 wrote for the read"));

  // ---- THE WRITE PATH IS REACHABLE FROM ONE BRANCH, AND THAT IS STRUCTURAL -
  assert.strictEqual((src.match(/core\.paramsWritePlan\(/g) || []).length, 1,
    pin("core.paramsWritePlan has more than one caller",
        "that the params file can be written from exactly ONE place — renderNow's no-file " +
        "branch — so a write triggered by an ANSWER cannot be written by accident"));
  const planCall = src.indexOf("core.paramsWritePlan(");
  const firstPickFn = src.indexOf("async function firstPickSchemaAndWrite(");
  const firstPickEnd = src.indexOf("async function refreshSchemaFile(");
  assert.ok(firstPickFn > 0 && planCall > firstPickFn && planCall < firstPickEnd,
    pin("core.paramsWritePlan is called from somewhere other than firstPickSchemaAndWrite", "the same"));
  assert.strictEqual((src.match(/firstPickSchemaAndWrite\(/g) || []).length, 2,
    pin("firstPickSchemaAndWrite has more than its definition and renderNow's one call",
        "the same: one definition, one caller, and that caller is the no-file branch"));
  // **S4 MOVED THIS FROM 2 TO 3, AND THE THIRD IS U3's COMMAND.** The rule
  // is unchanged and is now spelled out below: the write loop has exactly
  // two callers, one of which may replace a params file and one of which may
  // not, and the difference is the third ARGUMENT rather than the mode.
  assert.strictEqual((src.match(/applyWritePlan\(/g) || []).length, 3,
    pin("applyWritePlan has more than its definition and its two callers",
        "that the write loop is reachable from `firstPickSchemaAndWrite` (the automatic path, which " +
        "may never overwrite) and from `writeSkeletonNow` (U3's command, which may, once the user has " +
        "confirmed it) and from nothing else"));
  const refreshBody = src.slice(src.indexOf("async function refreshSchemaFile("),
                                src.indexOf("async function refreshSchemaFor("));
  assert.ok(refreshBody.length > 0 && !/paramsPath/.test(refreshBody),
    pin("refreshSchemaFile names the params path",
        "that a render's ANSWER can never rewrite the params file — the write -> watcher -> " +
        "render -> write loop is unwritable rather than merely avoided"));
  // D-1: the bytes come from the ONE checked builder, over the FRESH answer.
  assert.ok(/const bytes = core\.schemaFileBytes\(outcome\.schema\);/.test(refreshBody) &&
            /if \(bytes\.problem\) \{/.test(refreshBody) &&
            /writeIfDifferent\(paths\.schemaPath, bytes\.text\)/.test(refreshBody),
    pin("the refreshed schema file is built from something other than the server's FRESH answer, " +
        "or not through core.schemaFileBytes, or its refusal is ignored",
        "the S1 review's D-1 obligation: schemaFileFor mints a ROOT-LEVEL COPY of a $defs entry " +
        "that also describes a nested position, and a copy tracks its original only within the " +
        "call that made it. Feeding the written file back leaves the copy silently stale"));
  assert.ok(/core\.paramsWritePlan\(paths, outcome\.schema, todayForSkeleton\(\)\)/.test(src),
    pin("the write plan is built from something other than the server's FRESH answer", "the same"));

  // ---- N-2: write-if-different is ONE site, and the write is its CONSEQUENCE
  const wid = src.slice(src.indexOf("async function writeIfDifferent("),
                        src.indexOf("async function symlinkProblem("));
  assert.ok(wid.length > 0 &&
            /const existing = await readTextIfPresent\(fsPath\);\s*\n\s*if \(!core\.schemaFileNeedsWrite\(existing, text\)\) return core\.writeResult\(\{ wrote: false \}\);\s*\n\s*await writeTextFile\(fsPath, text\);/.test(wid),
    pin("writeIfDifferent no longer makes the write a CONSEQUENCE of core.schemaFileNeedsWrite",
        "D8: two prose-preserving mutants survived the whole suite when this was two copies with " +
        "the helper called and its answer ignored — the schema file was then rewritten with " +
        "identical bytes after every qualifying render, which is the churn it exists to prevent (N-2)"));
  assert.strictEqual((src.match(/core\.schemaFileNeedsWrite\(/g) || []).length, 1,
    pin("core.schemaFileNeedsWrite is asked from more than the one write-if-different site",
        "the same (N-2): one site is one thing to pin"));
  // **S4 MOVED THIS FROM 3 TO 4**: U3's explicit overwrite is the fourth,
  // and it is reachable only through `core.writeStep`'s `explicitOverwrite`
  // act, which refuses without the caller's permission (pinned below).
  assert.strictEqual((src.match(/writeTextFile\(/g) || []).length, 4,
    pin("writeTextFile — the OVERWRITING primitive — has call sites other than its definition, " +
        "the create's zero-byte branch, writeIfDifferent and U3's confirmed overwrite",
        "that the only unconditional write in this extension is over zero bytes, over a " +
        "generated file whose bytes differ, or over a params file the user has just confirmed " +
        "replacing in a modal"));

  // ---- M-2: the plan's step is a DECISION, and it fails CLOSED -----------
  const applyBody = src.slice(src.indexOf("async function applyWritePlan("),
                              src.indexOf("async function openParamsDocument("));
  // AND THE PARAMS PATH REACHES IT. `writeStep` identifies the params file
  // BOTH by `what` and by its path; handing it no path drops the second
  // half silently, so a mislabelled entry would be judged on its label alone.
  assert.ok(/applyWritePlan\(plan\.files, paths\.paramsPath\)/.test(src),
    pin("applyWritePlan is called without the params path to compare against",
        "M-2: the belt as well as the braces — a params entry is refused by any route but the " +
        "create whether its LABEL says so or only its PATH does"));
  assert.ok(/async function applyWritePlan\(files, paramsPath, allowExplicitOverwrite\) \{/.test(applyBody),
    pin("applyWritePlan no longer takes the params path, or no longer takes the overwrite permission " +
        "as an argument of its own",
        "the same (M-2), and S4's U3: the permission to REPLACE a params file belongs to the CALLER, " +
        "not to the plan entry — a plan carrying `explicitOverwrite` that reaches any other caller " +
        "writes nothing"));
  assert.ok(/const step = core\.writeStep\(file, paramsPath, allowExplicitOverwrite\);/.test(applyBody) &&
            /if \(step\.problem\) \{/.test(applyBody),
    pin("applyWritePlan decides what to do with an entry inline again instead of asking " +
        "core.writeStep, or ignores its answer",
        "**THE FAIL-OPEN `else`**: any mode that was not the exact string \"ifAbsent\" fell " +
        "through to an UNCONDITIONAL overwrite at the one site that can destroy committed source. " +
        "MEASURED on a real disk: `mode: \"ifabsent\"` overwrote {\"COMMITTED\":\"SOURCE\"} (M-2)"));
  assert.ok(/if \(step\.act === core\.WRITE_IF_ABSENT\)/.test(applyBody),
    pin("applyWritePlan no longer branches on the decision's own answer", "the same (M-2)"));
  assert.ok(!/file\.mode === "/.test(applyBody),
    pin("applyWritePlan compares a mode string by hand again",
        "the same (M-2): the vocabulary is core's, shared by the plan that produces it and the " +
        "loop that consumes it"));
  assert.ok(/const outcome = await createFileWithoutOverwriting\(file\.path, file\.text\);/.test(applyBody),
    pin("applyWritePlan's ifAbsent branch no longer goes through createFileWithoutOverwriting",
        "that a params file which is already there is LEFT EXACTLY AS IT IS — it is committed " +
        "source, and `workspace.fs.writeFile` overwrites"));
  assert.ok(/if \(outcome\.outcome === core\.CREATE_FAILED\)/.test(applyBody) &&
            /if \(outcome\.outcome === core\.CREATED\) wrote\.push\(file\.what\);/.test(applyBody) &&
            /else if \(file\.what === core\.WRITE_PARAMS\) return core\.writeOutcome\(\{ wrote, existed: true, problems \}\);/.test(applyBody),
    pin("applyWritePlan ignores what the create answered",
        "that a params file it did NOT write is never announced, never opened over what is being " +
        "typed, and never counted as a render that the watcher will bring"));
  // N-5: the generated .gitignore is a convenience and must not block.
  assert.ok(/if \(file\.what === core\.WRITE_GITIGNORE\) continue;/.test(applyBody),
    pin("a .gitignore that could not be written aborts the whole plan again",
        "N-5: a stray DIRECTORY named .gitignore permanently disabled params files for that " +
        "workspace folder, because firstPickTried then held the pick (MEASURED by the review)"));

  // ---- D-1: a write of the literal text `undefined` is UNREACHABLE -------
  //
  // MEASURED before the fix: `schemaAnswerOutcome` answered a BARE
  // `{reason, message}` for the three server-side failures while the glue's
  // other returns were WRAPPED, both callers test `outcome.problem`, and the
  // D8 refresh wrote `undefined\n` into the schema file for all three.
  assert.ok(/core\.schemaRequestFailure\(new Error\("there is no language client"\)\);/.test(src) &&
            !/\{ problem: core\.schemaRequestFailure\(/.test(src),
    pin("requestSchema wraps a failure itself instead of returning the builder's shape",
        "D-1: the success and the failures must be ONE shape, or `if (outcome.problem)` reads " +
        "`undefined` off a server-side failure and the handler is skipped entirely"));
  const writeBody = src.slice(src.indexOf("async function writeTextFile("),
                              src.indexOf("async function createFileWithoutOverwriting("));
  assert.ok(/if \(typeof text !== "string"\) throw new Error\(/.test(writeBody),
    pin("writeTextFile no longer refuses bytes that are not bytes",
        "D-1's last gate: a write of the six-letter word `undefined` must be impossible by " +
        "CONSTRUCTION, not only because the control flow above returns"));
  assert.ok(/if \(typeof text !== "string"\) \{/.test(wid),
    pin("writeIfDifferent no longer refuses bytes that are not bytes", "the same (D-1)"));
  // The round-trip check inside `schemaFileBytes` is the SECOND layer, and
  // it is redundant for every input reachable from the wire (`JSON.parse`
  // never produces a `toJSON`), so no behavioural test can kill its removal.
  // It is pinned instead, because "impossible by construction" was the ask.
  const coreSrc = codeOf(fsMod.readFileSync(path.join(__dirname, "..", "src", "preview-core.js"), "utf8"));
  const bytesBody = coreSrc.slice(coreSrc.indexOf("function schemaFileBytes("),
                                  coreSrc.indexOf("function paramsToSend("));
  assert.ok(/if \(!isPlainObject\(schema\)\) \{/.test(bytesBody) &&
            /if \(typeof text !== "string" \|\| !isPlainObject\(parsed\)\) \{/.test(bytesBody),
    pin("schemaFileBytes lost one of its two layers",
        "D-1: the first refuses a non-object, the second refuses anything that does not " +
        "ROUND-TRIP to one. The second is unreachable from the wire today and is the reason a " +
        "write of the literal text `undefined` is impossible by CONSTRUCTION rather than by " +
        "control flow"));

  // ---- M-3: SYMLINKS, which S1 handed to S3 ------------------------------
  // S4 MOVED THIS FROM 2 TO 3: U3's command is a third write path and is
  // held to exactly the same rule (its own `if (linked)` statement is pinned
  // with the other two below).
  assert.strictEqual((src.match(/await symlinkProblem\(/g) || []).length, 3,
    pin("the symlink check is gone from one of the three write paths",
        "M-3: node's fs FOLLOWS symlinks and the editor's API is UNVERIFIED either way. MEASURED: " +
        "a <binding>.schema.json symlinked outside the workspace was written THROUGH from the " +
        "REFRESH path — which is reachable from an ANSWER, the one thing the tracker says an " +
        "answer can never do — and a DANGLING params symlink had the skeleton created at its " +
        "outside target"));
  const firstPickBody = src.slice(firstPickFn, firstPickEnd);
  const linkCheck = firstPickBody.indexOf("await symlinkProblem(");
  const mkdir = firstPickBody.indexOf("await ensureDirectory(");
  assert.ok(linkCheck > 0 && mkdir > linkCheck,
    pin("the symlink check no longer runs BEFORE the directory is created",
        "that `createDirectory` cannot make the module directory inside a symlinked preview/, " +
        "after which every write lands wherever that link points (M-3)"));
  assert.ok(/symlinkProblem\(paths, \[paths\.gitignorePath, paths\.schemaPath, paths\.paramsPath\]\)/.test(firstPickBody),
    pin("the first-pick symlink check no longer covers all three targets", "the same (M-3)"));
  assert.ok(/symlinkProblem\(paths, \[paths\.schemaPath\]\)/.test(refreshBody),
    pin("the refresh's symlink check no longer covers the schema file", "the same (M-3)"));
  const symBody = src.slice(src.indexOf("async function symlinkProblem("),
                            src.indexOf("async function statType("));
  assert.ok(/core\.writeTargetPaths\(paths, targets\)/.test(symBody) &&
            /return core\.writeTargetProblem\(seen\);/.test(symBody),
    pin("symlinkProblem no longer asks the pure pair which paths to stat and whether one is a link",
        "the same (M-3): the policy is a decision, the stat is the glue"));

  // ---- D-3: THE THREE M-3 SITES, WHICH HAD NO PIN AT ALL -----------------
  //
  // MEASURED by the delta re-review: `statType` always null, and either
  // `if (linked)` kept but neutered as `if (false && linked)`, all survived
  // 261/261.
  const statBody = src.slice(src.indexOf("async function statType("),
                             src.indexOf("async function applyWritePlan("));
  assert.ok(statBody.length > 0 && statBody.length < 900, "the statType slice must be statType's own");
  assert.ok(/if \(st && typeof st\.type === "number"\) return \{ type: st\.type \};/.test(statBody) &&
            /if \(core\.meansFileMissing\(err\)\) return \{ missing: true \};/.test(statBody) &&
            /return \{ unknown:/.test(statBody),
    pin("statType no longer distinguishes `not there` from `cannot tell`",
        "**D-2**: it used to answer null for every stat that threw, which reads as `not there`, so " +
        "a path that EXISTS but cannot be stat'd voided the whole symlink defence — MEASURED, a " +
        "schema symlink outside the workspace was written THROUGH"));
  assert.ok(/if \(what\.missing === true\) continue;/.test(symBody) &&
            /what\.unknown !== undefined/.test(symBody),
    pin("symlinkProblem no longer forwards `cannot tell` to the decision", "the same (D-2)"));
  for (const [where, body] of [["the first pick", firstPickBody], ["the refresh", refreshBody]]) {
    assert.ok(/\n  const linked = await symlinkProblem\(/.test(body),
      pin("the symlink check at " + where + " is no longer a statement of its own",
          "**D-3**: `if (false && linked)` keeps every word and every call, and both sites " +
          "survived 261/261 with no pin at all"));
    assert.ok(/\n  if \(linked\) \{\n    schemaNoticeOnce\(attempt\.pick, linked\.reason, linked\.message\);/.test(body),
      pin("the symlink refusal at " + where + " is guarded away or no longer said",
          "the same (D-3): the check is worth nothing if its answer is not acted on"));
  }


  // ---- M-5: the ONE overwrite is over ZERO BYTES, not over whitespace -----
  // CODE end markers, not comment banners: `codeOf` stripped those (N-1).
  const createBody = src.slice(src.indexOf("async function createFileWithoutOverwriting("),
                               src.indexOf("async function writeIfDifferent("));
  assert.ok(/overwrite: false, ignoreIfExists: true/.test(createBody),
    pin("the create no longer asks the editor for a create that SKIPS an existing file",
        "that `workspace.fs.writeFile`'s documented OVERWRITE cannot destroy committed source " +
        "in the window between a stat and a write (a git checkout, a second window)"));
  assert.ok(/edit\.createFile\(/.test(createBody) && /applyEdit\(edit\)/.test(createBody),
    pin("the create no longer goes through WorkspaceEdit.createFile", "the same"));
  const lookBefore = createBody.indexOf(
    'if ((await readTextIfPresent(fsPath)) !== null) return core.createOutcome(core.EXISTED);');
  assert.ok(lookBefore >= 0 && lookBefore < createBody.indexOf("applyEdit(edit)"),
    pin("createFileWithoutOverwriting no longer looks before it creates",
        "that a file already holding exactly these bytes is reported as one we did NOT write — " +
        "a first pick that announced a file it did not create would open a document over what is " +
        "being typed and then wait for a watcher event nobody caused (MEASURED, wp8-s3/measure.log)"));
  const readBack = createBody.lastIndexOf("await readTextIfPresent(fsPath)");
  assert.ok(readBack > createBody.indexOf("applyEdit(edit)"),
    pin("the create no longer READS THE FILE BACK",
        "that whether this VS Code honours createFile's `contents` option — which is UNVERIFIED " +
        "here — cannot leave a zero-byte params file, which S1 refuses to render"));
  assert.ok(/if \(after === ""\) \{\s*\n\s*await writeTextFile\(fsPath, text\);/.test(createBody),
    pin("the create's one overwrite is not over ZERO BYTES exactly",
        "**M-5**: it used to test `after.trim() === \"\"`, so a file holding only WHITESPACE was " +
        "written over (MEASURED by the review through a racing writer) while the README promised " +
        "the params file is never overwritten by anything in this version. Whitespace is " +
        "somebody's bytes; zero length is not, and zero length is what the case this branch " +
        "exists for produces"));
  assert.ok(!/after\.trim\(\)/.test(createBody),
    pin("the create is back to trimming the read-back", "the same (M-5)"));
  assert.ok(createBody.lastIndexOf("return core.createOutcome(core.EXISTED);") > readBack,
    pin("the create no longer leaves a file whose bytes are not ours alone",
        "THE RACE, ANSWERED: a params file that appeared while the schema was being worked out " +
        "is left exactly as it is"));

  // THE RACE'S OWN RENDER, now the same scheduled one every successful write
  // gets (M-4), and the notice/open still only for a file WE wrote.
  assert.ok(/if \(applied\.existed\) \{[\s\S]{0,600}?return core\.firstPickResult\(\{ wrote: true, raced: true \}\);/.test(firstPickBody),
    pin("a params file that APPEARED during the schema request is no longer reported as such",
        "that the render is still scheduled for it (M-4's one call covers both) and that it is " +
        "never announced or opened as one we wrote"));
  // **THE `-1` HAZARD, WHICH S4 HIT.** This used to compare two `indexOf`s
  // and the second needle moved (S4 passes `plan.shape` as well), so it went
  // to `-1` -- and `anything > -1` is TRUE, leaving the pin green and
  // protecting nothing. Both needles are now asserted PRESENT first.
  // M-4 of the S4 review: the sentence is now `core.skeletonWrittenNotice`,
  // handed the WHOLE plan -- the builder the model calls too, so dropping
  // `plan.shape` is now a behaviour change the model sees, not only a pin.
  const announce = firstPickBody.indexOf("core.skeletonWrittenNotice(paths, plan, false)");
  const openIt = firstPickBody.indexOf("openParamsDocument(paths.paramsPath)");
  assert.ok(announce > 0 && openIt > 0 && openIt > announce &&
            /if \(applied\.wrote\.indexOf\(core\.WRITE_PARAMS\) < 0\) return core\.firstPickResult\(\{\}\);/.test(firstPickBody),
    pin("the params document is opened, or announced, for a file this branch did not write — or the " +
        "notice no longer says what a non-object root's value MEANS (S4's `plan.shape`)",
        "U2: the document that opens is the skeleton we just wrote, and nothing else"));

  // ---- Q7: ONE BOOT, THE SAME ROOTS --------------------------------------
  assert.ok(/sendRequest\("ermine\/schema", core\.schemaParams\(attempt\.pick\)\)/.test(src),
    pin("the schema request is not built from core.schemaParams over the SNAPSHOT's pick",
        "Q7: a schema and the render that follows must carry the SAME roots, or the root set — " +
        "the render session's discard key (section 2.4) — throws the session away and the next " +
        "render pays a boot, which is the cost Q7 removed"));
  assert.ok(/const still = core\.mayUseSchemaAnswer\(/.test(src) && /if \(!still\.send\) return core\.schemaAbandoned\(still\);/.test(src),
    pin("the schema answer's staleness check is gone, or its answer is discarded",
        "D7: ermine/schema carries no generation and no pick identity, so a late answer can only " +
        "be recognised by the snapshot it is compared against"));

  // ---- THE THIRD PLACE THE ONE CONSULTATION IS REACHED FROM ---------------
  const refreshFor = src.slice(src.indexOf("async function refreshSchemaFor("),
                               src.indexOf("function onClientStopped("));
  assert.ok(/const permitted = core\.mayAutoRender\(wedgeMark, pick, trigger\);/.test(refreshFor) &&
            /if \(!permitted\.render\) \{/.test(refreshFor),
    pin("the schema refresh no longer asks the ONE consultation, or ignores its answer",
        "that a held report is not handed a job that compiles and evaluates it — the refresh is " +
        "an AUTOMATIC action on the preview queue, not a read"));
  assert.ok(/if \(\(await readTextIfPresent\(paths\.paramsPath\)\) === null\) return;/.test(refreshFor),
    pin("the schema file is refreshed for a report that has no params file",
        "that a <binding>.schema.json referenced by nothing does not cost a preview job that " +
        "compiles and evaluates the report to produce"));
  assert.ok(/const refresh = core\.shouldRefreshSchema\(answer, trigger\);/.test(renderBody) &&
            /if \(refresh\.refresh\) \{/.test(renderBody),
    pin("the post-render refresh no longer asks core.shouldRefreshSchema, or ignores its answer",
        "D8: only an answer that says the report COMPILED, and only a trigger that could have " +
        "moved its parameter TYPE"));
  assert.ok(/refreshSchemaFor\(sentPick, core\.TRIGGER_SCHEMA, refresh\.why\)/.test(renderBody),
    pin("the post-render refresh is asked about something other than the snapshot's pick, or " +
        "does not declare itself as core.TRIGGER_SCHEMA",
        "that the consultation sees a declared trigger (D2 fails CLOSED on anything else) and " +
        "that the pick it refreshes for is the one this render was decided on"));

  // ---- N-11 / M8c: the SECOND consultation site, pinned at last ----------
  //
  // "Guard skipped at applyStuck's rerender" has survived every mutation
  // round on this branch, and both the WP-22 review and the S3 review
  // recorded it as irreducible glue. It is not: the STATEMENT can be pinned
  // exactly as the other two sites are. It is pre-existing and it is closed
  // here because S3 added a third site and the three should be held alike.
  const stuckBody = src.slice(src.indexOf("function applyStuck("), src.indexOf("function holdRender("));
  assert.ok(/const permitted = core\.mayAutoRender\(wedgeMark, picked, trigger\);/.test(stuckBody) &&
            /if \(permitted\.render\) \{/.test(stuckBody),
    pin("applyStuck's rerender no longer asks the ONE consultation, or ignores its answer",
        "WP-22's original site: the Stopped -> Running re-render is the automatic render this " +
        "whole ticket exists to hold, and a mutant that skipped it survived every round until now"));

  // ---- the write-failure sentence is minted once (M-1's treatment) -------
  assert.ok(/core\.writeFailedProblem\(file\.what, file\.path, outcome\.why\)/.test(src),
    pin("applyWritePlan builds the write-failure sentence by hand again",
        "M-1's class: the MODEL said something different, so a test could pass on a message the " +
        "developer never sees — N-5's whole point is in that sentence"));

  // ---- fx.schema: the seam that used to only say it existed ---------------
  assert.ok(/if \(fx\.schema && picked\) \{/.test(stuckBody) &&
            /\n    refreshSchemaFor\(picked, trigger, trigger === core\.TRIGGER_RESTART/.test(stuckBody),
    pin("applyStuck's fx.schema effect no longer asks for the schema",
        "that every `invalidate` DROPPED while the preview was stuck (Q10) is made good: the " +
        "generated schema file may describe a parameter type that has since moved, and these two " +
        "edges are when nothing else will say so"));
  assert.ok(!/a schema re-request belongs here \(WP-8\)/.test(raw),
    pin("the fx.schema seam still only LOGS that a re-request belongs there", "the same"));
  assert.ok(/forgetSchemaAttempts\(\);[\s\S]{0,200}refreshSchemaFor\(picked, trigger,/.test(stuckBody),
    pin("the fx.schema seam no longer forgets the first-pick attempt",
        "that a report whose first-pick write failed while the server was wedged gets another " +
        "attempt once it comes back"));

  // ---- U2: the params document is opened once, without stealing focus -----
  const openBody = src.slice(src.indexOf("async function openParamsDocument("),
                             src.indexOf("async function requestSchema("));
  // S4 fix round (M-4): the has/add pair is `core.claimParamsDocument`, the
  // one dedupe the models call as well.
  assert.ok(/if \(!core\.claimParamsDocument\(openedParamsFiles, fsPath, always\)\) return;/.test(openBody),
    pin("the params document is opened more than once per path",
        "U2: it is opened right after it is written, and never again"));
  assert.ok(/preserveFocus: true/.test(openBody) && /ViewColumn\.Beside/.test(openBody),
    pin("opening the params document steals focus, or does not go beside",
        "that a file appearing must not take the cursor out of whatever is being typed"));

  // ---- the reveal a first pick would otherwise lose (N-9) -----------------
  assert.ok(/const revealThis = reveal === true \|\| revealNextRender;/.test(renderBody) &&
            /revealNextRender = false;/.test(renderBody) &&
            /revealNextRender = revealThis;/.test(renderBody),
    pin("the reveal latch is gone, or is not consumed once",
        "that picking a report with no params file still REVEALS the render tab. N-9: it cannot " +
        "leak to an unrelated later render either, because M-4 schedules that render itself " +
        "rather than waiting on an event that may never come"));
  const armed = wroteBranch.indexOf("revealNextRender = revealThis;");
  const sched = wroteBranch.indexOf("scheduleRender(");
  assert.ok(armed >= 0 && sched > armed,
    pin("the reveal latch is armed after the render that consumes it is scheduled", "the same (N-9)"));
  for (const [what, needle, until] of [
    ["a pick change", "async function pickReport(", "async function renderCommand("],
    ["a teardown", "function disposePreview(", "function restorePick("],
    ["learning the module name", "async function refreshModule(", "function installWatcher("],
    ["a roots change", 'event.affectsConfiguration("ermine.preview.roots")', "ermine.preview.restartAfterStuckSeconds"],
    ["a window reload", "function restorePick(", "function rememberPick("],
  ]) {
    const start = src.indexOf(needle);
    assert.ok(start > 0 && src.slice(start, src.indexOf(until, start)).indexOf("forgetSchemaAttempts()") > 0,
      pin(what + " no longer forgets the first-pick attempt",
          "that the attempt is re-made when something could have changed the answer — the module " +
          "IS the directory, and the roots decide which module of that name is resolved"));
  }
});

// ==================== WP-8 S3, AFTER THE INDEPENDENT REVIEW (DESIGN RED,
// ==================== IMPLEMENTATION RED, ON REPRODUCED DEFECTS)
//
// Five must-fixes and ten nits. What is below is the part that can be tested
// here; the rest is in the models above, in the glue pins, and in the
// documentation. Each defect was REPRODUCED before it was fixed -- M-1 as a
// mutant that leaves 249/249 green, M-2/M-3/M-5 on a real disk through a
// scripted `vscode`, N-1/N-2/N-10 as surviving mutants, N-3 with the
// review's own `edge-empty.js`.

// ------------------------------------------------- M-1: one shape, one place

test("S3 M-1: every prepareParams outcome carries `paths`, and the MODEL mints the same shape", () => {
  // THE FOURTH OCCURRENCE of this branch's recurring defect. `prepareParams`
  // built four object literals and the model built its own; deleting the one
  // word `paths,` from the missing-file literal made `schemaOrder(undefined,
  // true)` answer "render first, write nothing" -- THE WHOLE STAGE DEAD --
  // with 249 of 249 tests green. MEASURED by the review, reproduced here.
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const outcomes = [
    [core.PREPARED_MISSING, {}],
    [core.PREPARED_READ, { params: { a: 1 }, warnings: [] }],
    [core.PREPARED_REFUSAL, { problem: { reason: "invalid-json", message: "not JSON" } }],
  ];
  for (const [kind, over] of outcomes) {
    const prepared = core.preparedParams(paths, Object.assign({ kind }, over));
    assert.strictEqual(prepared.paths, paths, kind + " carries `paths`");
    assert.strictEqual(prepared.path, paths.paramsPath, kind + " carries `path`");
    // AND THE THING THE DROPPED FIELD BROKE: the ordering rule answers.
    assert.strictEqual(core.schemaOrder(prepared.paths, kind === core.PREPARED_MISSING).first,
                       kind === core.PREPARED_MISSING ? "schema" : "render", kind);
  }
  // A `paramsPaths` PROBLEM is carried too -- `schemaOrder` reads it and
  // answers "nowhere to write", which is right, and which is exactly what a
  // DROPPED `paths` looks like. The two must be distinguishable.
  const outside = core.paramsPaths(SALES_PICK, "/elsewhere", "posix");
  const problem = core.preparedParams(outside, { kind: core.PREPARED_PATH_PROBLEM });
  assert.strictEqual(problem.paths, outside);
  assert.strictEqual(problem.notice.reason, outside.problem.reason);
  assert.strictEqual(problem.path, null, "there is no params file to name");
  assert.deepStrictEqual(problem.params, {});

  // FAIL CLOSED on a kind nothing declares, like every other unknown here.
  const junk = core.preparedParams(paths, { kind: "typo" });
  assert.strictEqual(junk.refusal.reason, "bad-prepared-kind");
  assert.strictEqual(junk.params, undefined, "an unknown outcome sends nothing");
  assert.deepStrictEqual(core.PREPARED_KINDS.slice().sort(),
                         ["missing", "path-problem", "read", "refusal"]);
});

test("S3 M-1: the other three glue shapes are minted once too", () => {
  // The audit the must-fix asked for: every object the glue hands one of its
  // own decisions, not just `prepareParams`'s.
  assert.deepStrictEqual(core.createOutcome(core.CREATED), { outcome: "created", why: null });
  assert.deepStrictEqual(core.createOutcome(core.CREATE_FAILED, "EROFS"),
                         { outcome: "failed", why: "EROFS" });
  assert.deepStrictEqual(core.writeOutcome({}), { wrote: [], existed: false, problems: [] });
  assert.deepStrictEqual(core.writeOutcome({ wrote: ["schema"], existed: true, problems: [1] }),
                         { wrote: ["schema"], existed: true, problems: [1] });
  // Every field is present whatever it is handed, so a caller that forgets
  // one reads a default rather than `undefined`.
  for (const junk of [undefined, null, 7, { wrote: "not an array" }]) {
    const out = core.writeOutcome(junk);
    assert.ok(Array.isArray(out.wrote) && Array.isArray(out.problems), JSON.stringify(junk));
    assert.strictEqual(typeof out.existed, "boolean");
  }
  assert.deepStrictEqual(core.schemaAbandoned({ reason: "pick-changed", why: "x" }),
                         { schema: null, problem: null, abandoned: { reason: "pick-changed", why: "x" },
                           noParameters: false });
  assert.strictEqual(core.schemaAbandoned(undefined).abandoned.reason, "pick-cleared");
  // D-1's builder audit: the two shapes that were still raw literals on BOTH
  // sides, which is M-1's class once more.
  assert.deepStrictEqual(core.firstPickResult({}), { wrote: false, raced: false, abandoned: false, noParameters: false });
  assert.deepStrictEqual(core.firstPickResult({ wrote: true, raced: true }),
                         { wrote: true, raced: true, abandoned: false, noParameters: false });
  for (const junk of [undefined, null, 7, { wrote: "yes" }]) {
    const out = core.firstPickResult(junk);
    assert.strictEqual(typeof out.wrote, "boolean", JSON.stringify(junk));
    assert.strictEqual(typeof out.raced, "boolean");
    assert.strictEqual(typeof out.abandoned, "boolean");
  }
  assert.deepStrictEqual(core.writeResult({ wrote: true }), { wrote: true, problem: null });
  assert.deepStrictEqual(core.writeResult(undefined), { wrote: false, problem: null });
});

// --------------------------------------------- M-2: the write step, closed

test("S3 M-2: an unknown write mode is a NAMED REFUSAL, never an overwrite", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const params = paths.paramsPath;

  assert.deepStrictEqual(core.writeStep({ what: core.WRITE_PARAMS, path: params, mode: core.WRITE_IF_ABSENT }, params),
                         { act: "ifAbsent", problem: null });
  assert.deepStrictEqual(core.writeStep({ what: core.WRITE_SCHEMA, path: paths.schemaPath, mode: core.WRITE_IF_DIFFERENT }, params),
                         { act: "ifDifferent", problem: null });

  // **THE MEASURED ONE**: one lowercase letter overwrote `{"COMMITTED":"SOURCE"}`
  // on a real disk under the fail-OPEN `else` this replaces.
  assert.strictEqual(core.writeStep({ what: core.WRITE_PARAMS, path: params, mode: "ifabsent" }, params).problem.reason,
                     "params-not-creatable");
  // And the params file is refused by any route but the create, whatever the
  // mode says -- identified BOTH by `what` and by its path.
  assert.strictEqual(core.writeStep({ what: core.WRITE_PARAMS, path: params, mode: core.WRITE_IF_DIFFERENT }, params).problem.reason,
                     "params-not-creatable");
  assert.strictEqual(core.writeStep({ what: "something-else", path: params, mode: core.WRITE_IF_DIFFERENT }, params).problem.reason,
                     "params-not-creatable", "the PATH gives it away even when the label does not");
  assert.strictEqual(core.writeStep({ what: core.WRITE_PARAMS, path: params, mode: core.WRITE_IF_DIFFERENT }, undefined).problem.reason,
                     "params-not-creatable", "and the label gives it away even without the path");

  // Anything else is named, and nothing is written.
  for (const mode of [undefined, null, "", "overwrite", 7, {}]) {
    const step = core.writeStep({ what: core.WRITE_SCHEMA, path: paths.schemaPath, mode }, params);
    assert.strictEqual(step.problem.reason, "unknown-write-mode", JSON.stringify(mode));
    assert.strictEqual(step.act, undefined);
  }
  for (const junk of [undefined, null, {}, { path: "" }, { path: 7, mode: core.WRITE_IF_ABSENT }]) {
    assert.strictEqual(core.writeStep(junk, params).problem.reason, "bad-write-entry", JSON.stringify(junk));
  }
  // THE PRODUCER AND THE CONSUMER SHARE THE VOCABULARY, which is what makes
  // a typo unwritable rather than merely caught.
  const plan = core.paramsWritePlan(paths, SALES_SCHEMA, TODAY);
  for (const file of plan.files) {
    assert.ok(file.mode === core.WRITE_IF_ABSENT || file.mode === core.WRITE_IF_DIFFERENT, file.mode);
    assert.strictEqual(core.writeStep(file, params).problem, null, file.what);
  }
  assert.deepStrictEqual(plan.files.map((f) => f.what),
                         [core.WRITE_GITIGNORE, core.WRITE_SCHEMA, core.WRITE_PARAMS]);
});

// ----------------------------------------------------------- M-3: symlinks

test("S3 M-3: every directory component and every target is checked, outermost first", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  assert.deepStrictEqual(
    core.writeTargetPaths(paths, [paths.gitignorePath, paths.schemaPath, paths.paramsPath], "posix"),
    ["/w/.ermine", "/w/.ermine/preview", "/w/.ermine/preview/Sales",
     "/w/.ermine/preview/.gitignore",
     "/w/.ermine/preview/Sales/report.schema.json",
     "/w/.ermine/preview/Sales/report.params.json"]);
  // `.ermine/preview/<Module>` is in the list because `createDirectory` would
  // make the module directory INSIDE a symlinked preview/, after which every
  // write lands wherever it points.
  assert.deepStrictEqual(core.writeTargetPaths(paths, [paths.schemaPath], "posix").slice(0, 3),
                         ["/w/.ermine", "/w/.ermine/preview", "/w/.ermine/preview/Sales"]);
  // THE WORKSPACE FOLDER ITSELF IS NOT IN IT: `/home/me/work -> /mnt/big/work`
  // is an ordinary setup and refusing it would buy nothing.
  assert.ok(core.writeTargetPaths(paths, [], "posix").indexOf("/w") < 0);
  // A duplicate target is listed once.
  assert.strictEqual(core.writeTargetPaths(paths, [paths.dir, paths.dir], "posix").length, 3);
  // Nothing to write, nothing to check.
  for (const nowhere of [undefined, null, {}, core.paramsPaths(SALES_PICK, "/elsewhere", "posix")]) {
    assert.deepStrictEqual(core.writeTargetPaths(nowhere, ["/x"], "posix"), []);
  }
  // win32 too, since the components are derived with the path flavour.
  const win = core.paramsPaths(
    core.makePick("file:///c/w/Sales.e", "C:\\w\\doc\\Sales.e", "report", "Sales", []), "C:\\w", "win32");
  assert.deepStrictEqual(core.writeTargetPaths(win, [], "win32"),
                         ["C:\\w\\.ermine", "C:\\w\\.ermine\\preview", "C:\\w\\.ermine\\preview\\Sales"]);
});

test("S3 M-3: a symbolic link anywhere on the way refuses the write, by name", () => {
  // VS Code documents FileType as a BITMASK: SymbolicLink | File, or
  // SymbolicLink | Directory.
  assert.strictEqual(core.FILE_TYPE_SYMLINK, 64);
  const link = (path, kind) => ({ path, type: core.FILE_TYPE_SYMLINK | kind });

  assert.strictEqual(core.writeTargetProblem([]), null);
  assert.strictEqual(core.writeTargetProblem(undefined), null);
  assert.strictEqual(core.writeTargetProblem([{ path: "/w/.ermine", type: 2 },
                                              { path: "/w/.ermine/preview/Sales/report.params.json", type: 1 }]), null);
  for (const kind of [1, 2]) {
    const out = core.writeTargetProblem([{ path: "/w/.ermine", type: 2 }, link("/w/.ermine/preview", kind)]);
    assert.strictEqual(out.reason, "symlink", "FileType " + (core.FILE_TYPE_SYMLINK | kind));
    assert.match(out.message, /\/w\/\.ermine\/preview/);
    assert.match(out.message, /empty parameters/);
  }
  // THE MEASURED CASES, both of which wrote OUTSIDE the workspace before
  // this existed: the schema file itself (from the REFRESH path, which is
  // reachable from an ANSWER), and a DANGLING params link.
  assert.strictEqual(core.writeTargetProblem(
    [link("/w/.ermine/preview/Sales/report.schema.json", 1)]).reason, "symlink");
  assert.strictEqual(core.writeTargetProblem(
    [link("/w/.ermine/preview/Sales/report.params.json", 1)]).reason, "symlink");
  // A path that is not there, or that could not be stat'd, contributes
  // nothing -- we are about to create it.
  assert.strictEqual(core.writeTargetProblem([{ path: "/w/nope", type: null },
                                              { path: "/w/also-nope" }]), null);
  // The FIRST one found is the one named, so the message points at the
  // outermost problem rather than at a consequence of it.
  const two = core.writeTargetProblem([link("/w/.ermine", 2), link("/w/.ermine/preview", 2)]);
  assert.match(two.message, /"\/w\/\.ermine"/);
});

test("S3 ASYNC M-3: a symlinked target writes NOTHING, and the report still renders", async () => {
  for (const linked of ["/w/.ermine/preview",
                        "/w/.ermine/preview/Sales/report.params.json",
                        "/w/.ermine/preview/Sales/report.schema.json",
                        "/w/.ermine/preview/.gitignore"]) {
    const disk = diskModel({ links: [[linked, "/outside/precious"]] });
    const m = firstPickModel({ disk });
    m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
    await flush();
    m.readMissing(0);
    await flush();
    m.answerSchema(0, SALES_SCHEMA);
    await flush();
    assert.strictEqual(disk.files.size, 0, linked + ": nothing is written");
    assert.deepStrictEqual(m.opened, [], linked + ": and nothing is opened");
    assert.strictEqual(m.notices.length, 1, linked);
    assert.strictEqual(m.notices[0].reason, "symlink", linked);
    // NON-FATAL, like every other write failure: the report renders with `{}`.
    assert.strictEqual(m.sent.length, 1, linked + ": the render still happens");
    assert.deepStrictEqual(m.sent[0].params, {}, linked);
  }
});

test("S3 MUTANT M-3: without the check, the write goes THROUGH the link and lands outside", async () => {
  const disk = diskModel({ links: [["/w/.ermine/preview/Sales/report.params.json", "/outside/precious"]] });
  const m = firstPickModel({ disk, mutantNoSymlinkCheck: true });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.ok(disk.files.has("/outside/precious"),
    "the mutant creates the skeleton OUTSIDE the workspace folder, which is what the review MEASURED");
  assert.deepStrictEqual(m.opened, ["/w/.ermine/preview/Sales/report.params.json"],
    "and opens a document that is not where it thinks it is");
});

// --------------------------------------------- M-5: zero bytes, not "empty"

test("S3 M-5: only ZERO BYTES are written over -- whitespace is somebody's bytes", async () => {
  // The review MEASURED both through a racing writer that lands between the
  // look-before and the read-back. Whitespace used to be treated as empty,
  // while the README promised the params file is never overwritten by
  // anything in this version.
  for (const [label, racing, expected] of [
    ["zero bytes", "", core.CREATED],
    ["whitespace only", "   \n \t ", core.EXISTED],
    ["a newline", "\n", core.EXISTED],
    ["real content", '{"MY":"WORK"}', core.EXISTED],
  ]) {
    const disk = diskModel({ racingCreate: racing });
    const out = disk.create("/p.json", "SKELETON");
    assert.strictEqual(out.outcome, expected, label);
    assert.strictEqual(disk.read("/p.json"), expected === core.CREATED ? "SKELETON" : racing, label);
  }
  // AND A FILE ALREADY THERE, whatever it holds, is `existed` at the
  // look-before and is never even reached by the branch above.
  for (const already of ["", "   ", '{"MY":"WORK"}']) {
    const disk = diskModel({ files: [["/p.json", already]] });
    assert.strictEqual(disk.create("/p.json", "SKELETON").outcome, core.EXISTED, JSON.stringify(already));
    assert.strictEqual(disk.read("/p.json"), already);
  }
});

// ------------------------------------------------------------ N-4 and N-6

test("S3 N-4: the consenting render DOES qualify for a schema refresh", () => {
  // The review read the consenting render as carrying `restart`. It does
  // not: `holdRender`'s answer calls `renderNow("Render anyway", true,
  // core.TRIGGER_EXPLICIT)` (`src/extension.js`), and `explicit` IS in
  // `SCHEMA_REFRESH_TRIGGERS` -- so the seam's purpose is not lost in the
  // held case. Asserted rather than argued, and pinned to the source below.
  assert.ok(core.SCHEMA_REFRESH_TRIGGERS.indexOf(core.TRIGGER_EXPLICIT) >= 0);
  assert.strictEqual(core.shouldRefreshSchema({ ok: true, generation: 1 }, core.TRIGGER_EXPLICIT).refresh, true);
  // And the render itself is permitted, because explicit is consent.
  const mark = core.guardReduce(null, {
    type: "answer", stuck: true, applies: true, pick: SALES_PICK, params: {}, at: 1 }).mark;
  assert.strictEqual(core.mayAutoRender(mark, SALES_PICK, core.TRIGGER_EXPLICIT, 5).render, true);
  const fsMod = require("node:fs");
  const src = codeOf(fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8"));
  assert.ok(/renderNow\("Render anyway", true, core\.TRIGGER_EXPLICIT\)/.test(src),
    "source pin: the consenting render no longer carries `explicit`, so N-4 becomes real");
});

test("S3 N-6: a refresh whose attempt is no longer current writes NOTHING", async () => {
  // Fired and forgotten, uncoalesced and uncancelled -- so the one thing it
  // MUST do is notice that the world moved before it touches the disk.
  const disk = diskModel({ files: [["/w/.ermine/preview/Sales/report.params.json", "{}"],
                                   ["/w/.ermine/preview/Sales/report.schema.json", "OLD"]] });
  const m = firstPickModel({ disk });
  const attempt = core.renderAttempt(m.generation, m.picked, m.clientEpoch, m.stopCount, 0);
  const pending = m.requestSchema(attempt);
  await flush();
  m.picked = core.makePick(OTHER_PICK.uri, OTHER_PICK.fsPath, "report", "Other", ["/w/doc"]);
  m.answerSchema(0, SALES_SCHEMA);
  const outcome = await pending;
  assert.ok(outcome.abandoned, "the answer is discarded BEFORE anything is written");
  assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.schema.json"), "OLD");
  // And the glue returns on `abandoned` before its symlink check and before
  // its write -- pinned in the glue pins, because the order is glue.
  const fsMod = require("node:fs");
  // M-2 of the S4 review: this pin was -1-TOLERANT (`-1 < anything` is
  // true), so deleting the guard left the suite GREEN (MEASURED, R16). Every
  // position is now bound and asserted PRESENT first, and the source is read
  // through `codeOf`, so a commented-out guard is absent too.
  const src = codeOf(fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8"));
  const from = src.indexOf("async function refreshSchemaFile(");
  const to = src.indexOf("async function refreshSchemaFor(");
  assert.ok(from > 0 && to > from, "source pin: refreshSchemaFile / refreshSchemaFor not found");
  const body = src.slice(from, to);
  const guard = body.indexOf("if (outcome.abandoned)");
  const symlink = body.indexOf("await symlinkProblem(");
  const write = body.indexOf("writeIfDifferent(");
  assert.ok(guard > 0, "source pin: refreshSchemaFile no longer returns on an abandoned answer");
  assert.ok(symlink > 0, "source pin: refreshSchemaFile no longer checks for symlinks");
  assert.ok(write > 0, "source pin: refreshSchemaFile no longer writes through writeIfDifferent");
  const problemArm = body.indexOf("if (outcome.problem)");
  assert.ok(problemArm > guard, "source pin: refreshSchemaFile's problem arm moved above its abandoned guard");
  assert.ok(/\breturn;/.test(body.slice(guard, problemArm)),
    "source pin: the abandoned guard no longer RETURNS");
  assert.ok(guard < symlink,
    "source pin: the refresh acts on a stale answer before it checks anything");
  assert.ok(guard < write,
    "source pin: the refresh writes before it notices the world moved");
});

// ----------------------------------------------------------- N-5: the .gitignore

test("S3 N-5: a .gitignore that cannot be written does NOT block the two files that matter", async () => {
  // MEASURED by the review with a stray DIRECTORY named `.gitignore`: the
  // whole plan aborted, and `firstPickTried` then disabled params files for
  // that workspace folder for the rest of the session.
  const disk = diskModel({ directories: ["/w/.ermine/preview/.gitignore"] });
  // A directory at that path: the create cannot make a file there.
  const realCreate = disk.create.bind(disk);
  disk.create = (p, text) =>
    p === "/w/.ermine/preview/.gitignore"
      ? core.createOutcome(core.CREATE_FAILED, "it is a directory")
      : realCreate(p, text);
  const m = firstPickModel({ disk });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.ok(disk.read("/w/.ermine/preview/Sales/report.params.json") !== null,
    "the params file is written anyway");
  assert.ok(disk.read("/w/.ermine/preview/Sales/report.schema.json") !== null,
    "and so is the schema file");
  assert.deepStrictEqual(m.opened, ["/w/.ermine/preview/Sales/report.params.json"]);
  // TWO notices: what went wrong, and what was written.
  assert.deepStrictEqual(m.notices.map((n) => n.reason).sort(), ["write-failed", "written"]);
  assert.match(m.notices.find((n) => n.reason === "write-failed").line, /written anyway/);
  assert.match(m.notices.find((n) => n.reason === "write-failed").line, /\.gitignore is missing/);
  // And the render comes from the write, as it does on the ordinary path.
  assert.strictEqual(m.scheduled.length, 1);
});

test("S3: a PARAMS file that cannot be written still stops the branch", async () => {
  // The other side of N-5: the gitignore is a convenience, the params file
  // is the point. Its failure means no file, so the render goes with `{}`.
  const disk = diskModel();
  const realCreate2 = disk.create.bind(disk);
  disk.create = (p, text) =>
    /params\.json$/.test(p) ? core.createOutcome(core.CREATE_FAILED, "EACCES") : realCreate2(p, text);
  const m = firstPickModel({ disk });
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  await flush();
  assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.params.json"), null);
  assert.deepStrictEqual(m.opened, []);
  assert.strictEqual(m.notices.filter((n) => n.reason === "written").length, 0);
  assert.strictEqual(m.sent.length, 1, "the render still happens, with `{}`");
  assert.deepStrictEqual(m.sent[0].params, {});
  assert.deepStrictEqual(m.scheduled, [], "and nothing is scheduled, because nothing was written");
});


// ============= WP-8 S3, AFTER THE DELTA RE-REVIEW (DESIGN GREEN,
// ============= IMPLEMENTATION RED on one reproduced defect)
//
// D-1 is the defect a faithful model cannot see: the model reproduced the
// GLUE correctly, and the glue and the pure core disagreed about a SHAPE.
// Both callers tested `outcome.problem`, which is `undefined` for the bare
// `{reason, message}` three of the five failure modes answered -- so they
// fell straight through the handler, and the D8 refresh wrote the literal
// text `undefined` into `<binding>.schema.json`. MEASURED on a real disk
// with a stub client, reproduced here before the fix.

const GOOD_SCHEMA_FILE = core.schemaFileBytes(SALES_SCHEMA).text;

test("S3 D-1: EVERY schema failure reaches its OWN notice and LEAVES THE SCHEMA FILE ALONE", async () => {
  const cases = [
    ["a server {error}", { error: "no module named Sales", reason: "not-placed" }, "refresh-error"],
    ["Q8's stuck refusal", { error: "the preview is stuck", stuck: true }, "refresh-stuck"],
    ["an answer that is not an object", 7, "refresh-no-schema"],
    ["a JSON-RPC error", { __reject: true, err: { code: -32603, message: "internal" } }, "refresh-request-failed"],
    ["a transport rejection", { __reject: true, err: new Error("Connection got disposed") }, "refresh-request-failed"],
  ];
  for (const [label, reply, reason] of cases) {
    const disk = diskModel({ files: [
      ["/w/.ermine/preview/Sales/report.params.json", "{}"],
      ["/w/.ermine/preview/Sales/report.schema.json", GOOD_SCHEMA_FILE]] });
    const m = firstPickModel({ disk });
    const attempt = core.renderAttempt(m.generation, m.picked, m.clientEpoch, m.stopCount, 0);
    const pending = m.refreshSchemaFile(attempt, SALES_PATHS, "a test");
    await flush();
    if (reply && reply.__reject) m.rejectSchema(0, reply.err); else m.answerSchema(0, reply);
    await pending;

    // THE FILE IS EXACTLY WHAT IT WAS -- not `undefined\n`, not truncated.
    assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.schema.json"), GOOD_SCHEMA_FILE, label);
    assert.deepStrictEqual(disk.writes, [], label + ": nothing was written at all");
    // AND ITS OWN NAMED NOTICE, which was dead code for the first three.
    assert.strictEqual(m.notices.length, 1, label);
    assert.strictEqual(m.notices[0].reason, reason, label);
    assert.ok(m.notices[0].line.length > 20, label);
    // The params file is untouched either way -- it always was.
    assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.params.json"), "{}", label);
  }
  // THE CONTROL: a good answer really does rewrite it.
  const disk = diskModel({ files: [
    ["/w/.ermine/preview/Sales/report.params.json", "{}"],
    ["/w/.ermine/preview/Sales/report.schema.json", "OLD\n"]] });
  const m = firstPickModel({ disk });
  const pending = m.refreshSchemaFile(
    core.renderAttempt(m.generation, m.picked, m.clientEpoch, m.stopCount, 0), SALES_PATHS, "a test");
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  await pending;
  assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.schema.json"), GOOD_SCHEMA_FILE);
  assert.ok(JSON.parse(GOOD_SCHEMA_FILE), "and it is valid JSON");
});

test("S3 D-1: the FIRST-PICK path names each failure too, and writes nothing", async () => {
  for (const [label, reply, reason] of [
    ["a server {error}", { error: "no module named Sales" }, "error"],
    ["Q8's stuck refusal", { error: "stuck", stuck: true }, "stuck"],
    ["not an object", 7, "no-schema"],
  ]) {
    const m = firstPickModel();
    m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
    await flush();
    m.readMissing(0);
    await flush();
    m.answerSchema(0, reply);
    await flush();
    assert.strictEqual(m.disk.files.size, 0, label);
    assert.strictEqual(m.notices.length, 1, label + ": the named reason was DEAD CODE before D-1");
    assert.strictEqual(m.notices[0].reason, reason, label);
    assert.strictEqual(m.sent.length, 1, label + ": the render still happens with `{}`");
  }
});

test("S3 D-1: a write of the literal text `undefined` is unreachable BY CONSTRUCTION", () => {
  // Not merely because the control flow above now returns. `schemaFileFor`
  // answers its input unchanged for a non-object and `schemaFileText` is
  // JSON.stringify plus a newline -- which for `undefined` is the six-letter
  // word. That is exactly what reached the disk.
  assert.strictEqual(core.schemaFileText(core.schemaFileFor(undefined)), "undefined\n",
    "the mechanism, pinned so nobody re-discovers it");
  for (const junk of [undefined, null, 7, "x", [], true, NaN]) {
    const out = core.schemaFileBytes(junk);
    assert.strictEqual(out.problem.reason, "not-a-schema", JSON.stringify(junk));
    assert.strictEqual(out.text, undefined, JSON.stringify(junk));
  }
  // A real schema round-trips to an object, which is the test it must pass.
  const good = core.schemaFileBytes(SALES_SCHEMA);
  assert.strictEqual(good.problem, undefined);
  assert.ok(good.text.endsWith("}\n"));
  assert.strictEqual(good.text, core.schemaFileText(core.schemaFileFor(SALES_SCHEMA)));
  // `schemaFileText` itself is NOT narrowed: it renders the PARAMS file too,
  // whose value may legitimately be a number or a string (G5, MEASURED on
  // WpInt: the skeleton is `0`).
  assert.strictEqual(core.schemaFileText(0), "0\n");
  assert.strictEqual(core.schemaFileText(null), "null\n");
});

test("S3 D-2: a path that EXISTS but cannot be stat'd refuses, like everything else this round", () => {
  // It used to answer null for every throw, which reads as "not there" --
  // MEASURED, a schema symlink outside the workspace was written THROUGH.
  const out = core.writeTargetProblem([
    { path: "/w/.ermine", type: 2 },
    { path: "/w/.ermine/preview/Sales/report.schema.json", unknown: "EACCES: permission denied" },
  ]);
  assert.strictEqual(out.reason, "unstattable");
  assert.match(out.message, /report\.schema\.json/);
  assert.match(out.message, /EACCES/);
  assert.match(out.message, /cannot rule out a symbolic link/);
  assert.match(out.message, /empty parameters/);
  // A path that is REALLY absent still contributes nothing: we create it.
  assert.strictEqual(core.writeTargetProblem([{ path: "/w/.ermine/preview", type: 2 }]), null);
  // AN EMPTY `unknown` IS STILL AN UNKNOWN (N-g). This line used to assert
  // the opposite, which was fail-OPEN on truthiness; see the N-g test below.
  assert.strictEqual(core.writeTargetProblem([{ path: "/x", unknown: "" }]).reason, "unstattable");
  // The first problem on the way is the one named, whichever kind it is.
  assert.strictEqual(core.writeTargetProblem([
    { path: "/w/.ermine", unknown: "EACCES" },
    { path: "/w/.ermine/preview", type: core.FILE_TYPE_SYMLINK | 2 }]).reason, "unstattable");
  assert.strictEqual(core.writeTargetProblem([
    { path: "/w/.ermine", type: core.FILE_TYPE_SYMLINK | 2 },
    { path: "/w/.ermine/preview", unknown: "EACCES" }]).reason, "symlink");
});

test("S3 N-f: the no-client arm answers the SAME shape as every other failure", async () => {
  // Latent -- nothing drives it today -- and it double-wrapped the builder
  // under a comment saying it did not, which is exactly the class D-1 was.
  const m = firstPickModel();
  m.hasClient = false;
  const outcome = await m.requestSchema(core.renderAttempt(1, m.picked, 1, 0, 0));
  assert.strictEqual(outcome.problem.reason, "request-failed");
  assert.match(outcome.problem.message, /no language client/);
  assert.strictEqual(outcome.schema, null);
  assert.strictEqual(outcome.abandoned, null);
  // The glue's own arm, for the same input, is the same shape.
  const glue = core.schemaRequestFailure(new Error("there is no language client"));
  assert.deepStrictEqual(Object.keys(outcome).sort(), Object.keys(glue).sort());
  assert.strictEqual(glue.problem.reason, outcome.problem.reason);
});

test("S3 N-g: an EMPTY `unknown` refuses too -- no truthiness anywhere in the defence", () => {
  // A provider that throws an empty message answered `{unknown: ""}`, and
  // the defence answered null: fail-OPEN on truthiness, one level below the
  // shape D-2 closed.
  for (const unknown of ["", "EACCES", " ", "0"]) {
    const out = core.writeTargetProblem([{ path: "/w/.ermine/preview", unknown }]);
    assert.strictEqual(out && out.reason, "unstattable", JSON.stringify(unknown));
    assert.match(out.message, /\/w\/\.ermine\/preview/);
    assert.ok(out.message.indexOf("()") < 0, "the sentence never has an empty reason in it");
  }
  assert.match(core.writeTargetProblem([{ path: "/x", unknown: "" }]).message, /did not say why/);
  // A non-string `unknown` is still an unknown: the KEY is what decides.
  for (const unknown of [null, undefined, 0, false, {}]) {
    assert.strictEqual(core.writeTargetProblem([{ path: "/x", unknown }]).reason, "unstattable",
                       JSON.stringify(unknown));
  }
  // And an entry with no `unknown` key at all is unaffected.
  assert.strictEqual(core.writeTargetProblem([{ path: "/x", type: 1 }]), null);
});

test("S3 D-2: a link to a DIRECTORY is 66, not 65 (N-c)", () => {
  // The summary said 65. MEASURED: `SymbolicLink | File` is 65 and
  // `SymbolicLink | Directory` is 66, and the code is right either way
  // because it tests the BIT and not the number.
  assert.strictEqual(core.FILE_TYPE_SYMLINK | 1, 65);
  assert.strictEqual(core.FILE_TYPE_SYMLINK | 2, 66);
  for (const type of [65, 66, 64, 64 | 8]) {
    assert.strictEqual(core.writeTargetProblem([{ path: "/w/.ermine/preview", type }]).reason,
                       "symlink", "FileType " + type);
  }
  for (const type of [0, 1, 2, 8]) {
    assert.strictEqual(core.writeTargetProblem([{ path: "/w/.ermine/preview", type }]), null,
                       "FileType " + type);
  }
});

// ==========================================================================
// WP-8 S4 -- THE EDGES.  U3's explicit command, D6's orphan notice, the
// non-object params roots, and the two picks that can have no params file at
// all.
//
// WHAT IS TESTED WHERE, and why each kind is here:
//   1. TABLE TESTS for every new decision, over the FIVE REAL `ermine/schema`
//      answers this stage captured (`test/fixtures/wp*.schema.json`, verbatim
//      from `scratchpad/wp8-s4/measure.log`) as well as hand-made shapes;
//   2. the ASYNC MODEL extended with the COMMAND path -- a modal is an
//      `await` the user can hold open for minutes, which is a wider gap than
//      any S2/S3 await, and with the ORPHAN path, whose listing shapes are a
//      table of their own;
//   3. a property that the overwrite mode is reachable ONLY from the command
//      (a model assertion AND a grep pin, because neither sees the other);
//   4. SOURCE PINS for the chain that makes "only the command overwrites"
//      structural rather than careful.
// ==========================================================================

const WPINT_SCHEMA = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "wpint.schema.json"), "utf8"));
const WPENUM_SCHEMA = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "wpenum.schema.json"), "utf8"));
const WPMAYBE_SCHEMA = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "wpmaybe.schema.json"), "utf8"));
const WPJSON_SCHEMA = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "wpjson.schema.json"), "utf8"));
const WPUNIT_SCHEMA = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "wpunit.schema.json"), "utf8"));

// ------------------------------------------------- codeOf, the pins' own tool

test("S4: codeOf knows what a STRING is, and the trap it used to fall into", () => {
  // **THE LIVE TRAP S4 FOUND.** `extension.js` contains
  // `findFiles("**/*.e")`, whose `/*` opened a block comment for the two
  // regexes codeOf used to be. Nothing closed it, so the file survived by
  // LUCK; S4 added a JSDoc after it, its `*/` closed the block, and 124
  // lines of pickReport/renderCommand/activate were deleted from what every
  // pin reads. MEASURED: the picker's trigger pin failed with the source
  // line untouched.
  const old = (t) => String(t).replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  const trap = 'const a = findFiles("**/*.e");\nconst KEEP = 1;\n/** doc */\nconst ALSO = 2;\n';
  assert.ok(!/KEEP/.test(old(trap)), "the old codeOf really did eat the line between them");
  assert.ok(/KEEP/.test(codeOf(trap)), "the scanner keeps it");
  assert.ok(/ALSO/.test(codeOf(trap)));
  assert.ok(!/doc/.test(codeOf(trap)), "and it still strips a real block comment");

  // Line comments, block comments, and comment-looking text inside strings.
  assert.strictEqual(codeOf('a; // gone\nb;'), "a; \nb;");
  assert.strictEqual(codeOf("a; /* gone */ b;"), "a;  b;");
  assert.strictEqual(codeOf('const u = "http://x/y"; // gone'), 'const u = "http://x/y"; ');
  assert.strictEqual(codeOf("const t = `a // b ${x} /* c */`;"), "const t = `a // b ${x} /* c */`;");
  assert.strictEqual(codeOf('const e = "a \\" // still a string";'), 'const e = "a \\" // still a string";');
  // A regex literal carrying a quote -- `preview-core.js`'s SAFE_NAME does.
  assert.strictEqual(codeOf("const r = /^[A-Za-z_][A-Za-z0-9_']*$/; // gone\nnext;"),
                     "const r = /^[A-Za-z_][A-Za-z0-9_']*$/; \nnext;");
  // A regex whose character class holds a slash must not end early.
  assert.strictEqual(codeOf("x.replace(/[/]/g, \"\"); // gone"), 'x.replace(/[/]/g, ""); ');
  // Division is not a regex.
  assert.strictEqual(codeOf("const n = a / b; // gone"), "const n = a / b; ");

  // AND THE ASSERTION THAT WOULD HAVE CAUGHT THE TRAP: the stripped
  // extension really does still contain what comes after that string.
  const ext = codeOf(require("node:fs").readFileSync(
    path.join(__dirname, "..", "src", "extension.js"), "utf8"));
  for (const needle of ["async function pickReport(", "async function renderCommand(",
                        "async function activate(", "function deactivate("]) {
    assert.ok(ext.indexOf(needle) > 0,
      "source pin (test/preview-core.test.js): codeOf lost " + needle + " — every pin that reads a " +
      "slice at or after it has silently stopped protecting anything");
  }
});

// ------------------------------------------ G5: what a non-object root MEANS

test("S4 G5: paramsRootShape names every non-object root the exporter can make", () => {
  // THE FIVE ARE REAL ANSWERS, captured in one boot from a real
  // `bin/ermine-lsp` (scratchpad/wp8-s4/measure.log), not hand-made.
  assert.strictEqual(core.paramsRootShape(SALES_SCHEMA).kind, "object");
  assert.strictEqual(core.paramsRootShape(SALES_SCHEMA).sentence, null,
    "an object root has nothing to explain: the $schema line and completion do it");

  const int = core.paramsRootShape(WPINT_SCHEMA);
  assert.strictEqual(int.kind, "integer");
  assert.match(int.sentence, /a single whole number, so the file holds just that number/);

  // AN ALL-NULLARY ENUM IS BEHIND A `$ref`, so this is also the hop test.
  const season = core.paramsRootShape(WPENUM_SCHEMA);
  assert.strictEqual(season.kind, "enum");
  assert.match(season.sentence, /one of "Spring", "Summer", "Autumn"/);

  const maybe = core.paramsRootShape(WPMAYBE_SCHEMA);
  assert.strictEqual(maybe.kind, "optional");
  assert.match(maybe.sentence, /optional \(a single string\)/);
  assert.match(maybe.sentence, /`null` means there is none/);

  const anyJson = core.paramsRootShape(WPJSON_SCHEMA);
  assert.strictEqual(anyJson.kind, "any");
  assert.match(anyJson.sentence, /any JSON value at all/);

  const unit = core.paramsRootShape(WPUNIT_SCHEMA);
  assert.strictEqual(unit.kind, "unit");
  assert.match(unit.sentence, /the empty tuple `\(\)`/);
  assert.match(unit.sentence, /\[\]/);
});

test("S4 G5: the rest of the exporter's builtin string and scalar roots", () => {
  const shape = (node) => core.paramsRootShape(node);
  const rows = [
    [{ type: "string", format: "date" }, "date", /"YYYY-MM-DD" string/],
    [{ type: "string", format: "date-time" }, "timestamp", /ISO-8601 string with an offset/],
    [{ type: "string", format: "uuid" }, "guid", /GUID as a string/],
    [{ type: "string", pattern: "^-?[0-9]+$" }, "long", /WRITTEN AS A STRING/],
    [{ type: "string", minLength: 1, maxLength: 1 }, "char", /one-character string/],
    [{ type: "string" }, "string", /a single string/],
    [{ type: "number" }, "number", /a single number/],
    [{ type: "boolean" }, "boolean", /a single true or false/],
    [{ type: "null" }, "null", /just `null`/],
    [{ type: "array", items: { type: "integer" } }, "array", /a JSON array/],
    [{ type: "array", maxItems: 0 }, "unit", /empty tuple/],
    [{ const: 7 }, "const", /always 7/],
    [{ oneOf: [{ type: "string" }, { type: "integer" }] }, "union", /one of 2 shapes/],
    [{ type: "object", properties: {} }, "object", null],
    // Nit 6: the boolean schema `true` accepts anything, exactly as `{}`
    // does, so it gets `{}`'s measured sentence, not the generic fallback.
    [true, "any", /any JSON value at all/],
    [{ $ref: "#/$defs/A", $defs: { A: true } }, "any", /any JSON value at all/],
  ];
  for (const [node, kind, sentence] of rows) {
    const answer = shape(node);
    assert.strictEqual(answer.kind, kind, JSON.stringify(node));
    if (sentence === null) assert.strictEqual(answer.sentence, null, JSON.stringify(node));
    else assert.match(answer.sentence, sentence, JSON.stringify(node));
  }
  // AND THE UNKNOWNS, each of which must not guess.
  assert.strictEqual(shape(undefined).kind, "unknown");
  assert.strictEqual(shape(null).kind, "unknown");
  assert.strictEqual(shape(7).kind, "unknown");
  assert.strictEqual(shape({ $ref: "#/$defs/Nope" }).kind, "unknown", "a $ref it cannot follow");
  assert.strictEqual(shape({ $ref: "http://elsewhere#/x" }).kind, "unknown", "a $ref it does not do");
  // A long enum is counted rather than listed.
  const many = shape({ enum: ["a", "b", "c", "d", "e", "f", "g", "h"] });
  assert.match(many.sentence, /\(and 2 more\)/);
  // An `anyOf` with a null arm and NO payload still says something.
  assert.match(shape({ anyOf: [{ type: "null" }] }).sentence, /optional, so the file holds/);
});

test("S4 G5: the write notice SAYS what the value means, and only for a non-object root", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const objectNotice = core.paramsWrittenNotice(paths, true, core.paramsRootShape(SALES_SCHEMA));
  assert.match(objectNotice, /ordinary committed source/);
  assert.ok(objectNotice.indexOf("$schema") < 0, "an object root is not told its file has no $schema line");

  const intNotice = core.paramsWrittenNotice(paths, false, core.paramsRootShape(WPINT_SCHEMA));
  // S3's sentence said what the file is NOT. S4's says what it IS -- and it
  // KEEPS the half that matters operationally.
  assert.match(intNotice, /Its parameters are a single whole number, so the file holds just that number\./);
  assert.match(intNotice, /carries no "\$schema" line and the editor will not validate it/);
  assert.match(intNotice, /the server still checks it and answers a 400 with a path/);

  // A shape nothing recognised is still honest rather than silent.
  assert.match(core.paramsWrittenNotice(paths, false, { kind: "unknown", sentence: null }),
               /not a JSON object, so the file holds just that value/);
  assert.match(core.paramsWrittenNotice(paths, false, undefined),
               /not a JSON object, so the file holds just that value/);
  assert.strictEqual(core.rootShapeSentence(null), core.rootShapeSentence({ kind: "x" }));
});

test("S4 G5: the plan carries the shape, and the skeleton of each real root decodes to itself", () => {
  // MEASURED end to end (section 6's S4 table): each of these five renders
  // `ok=true` on a real server. What a unit test can add is that the SHIPPED
  // plan writes exactly the bytes that were sent.
  const rows = [
    [WPINT_SCHEMA, "integer", 0, false],
    [WPENUM_SCHEMA, "enum", "Spring", false],
    [WPMAYBE_SCHEMA, "optional", null, false],
    [WPJSON_SCHEMA, "any", null, false],
    [WPUNIT_SCHEMA, "unit", [], false],
    [SALES_SCHEMA, "object", undefined, true],
  ];
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  for (const [schema, kind, value, embeddable] of rows) {
    const plan = core.paramsWritePlan(paths, schema, TODAY);
    assert.ok(!plan.problem, kind);
    assert.strictEqual(plan.shape.kind, kind);
    assert.strictEqual(plan.embeddable, embeddable, kind);
    if (value !== undefined) assert.deepStrictEqual(plan.skeleton, value, kind);
    const params = plan.files[2];
    assert.strictEqual(params.what, core.WRITE_PARAMS);
    assert.strictEqual(params.mode, core.WRITE_IF_ABSENT, "the automatic path never overwrites");
    // The bytes on disk ARE the value: a non-object root has no `$schema`
    // key, because a JSON number has nowhere to put one.
    assert.deepStrictEqual(JSON.parse(params.text), plan.skeleton, kind);
    if (!embeddable) assert.ok(params.text.indexOf("$schema") < 0, kind + " must carry no $schema key");
    else assert.ok(params.text.indexOf('"$schema": "./report.schema.json"') > 0);
  }
});

// -------------------------------------- U3: the explicit-overwrite mode alone

test("S4 U3: the overwrite mode needs the CALLER's permission, not just the mode", () => {
  const params = { what: core.WRITE_PARAMS, path: "/w/p.params.json", text: "x",
                   mode: core.WRITE_EXPLICIT_OVERWRITE };
  // WITHOUT the permission -- which is what every pre-S4 call site passes,
  // because it passes two arguments and this is the third.
  for (const allow of [undefined, false, null, 0, "true", 1, {}]) {
    const step = core.writeStep(params, "/w/p.params.json", allow);
    assert.strictEqual(step.act, undefined, JSON.stringify(allow));
    assert.strictEqual(step.problem.reason, "overwrite-not-permitted", JSON.stringify(allow));
    assert.match(step.problem.message, /Write Params Skeleton/);
  }
  // WITH it.
  assert.strictEqual(core.writeStep(params, "/w/p.params.json", true).act, core.WRITE_EXPLICIT_OVERWRITE);
  assert.strictEqual(core.writeStep(params, "/w/p.params.json", true).problem, null);

  // AND ONLY FOR THE PARAMS FILE. A `.gitignore` or a schema file carrying
  // the mode is refused even WITH the permission: those two have their own
  // modes, and a mode that works everywhere is one that will be pasted.
  for (const what of [core.WRITE_GITIGNORE, core.WRITE_SCHEMA]) {
    const other = { what, path: "/w/.ermine/preview/.gitignore", text: "x",
                    mode: core.WRITE_EXPLICIT_OVERWRITE };
    const step = core.writeStep(other, "/w/p.params.json", true);
    assert.strictEqual(step.act, undefined, what);
    assert.strictEqual(step.problem.reason, "overwrite-not-params", what);
  }
  // THE OVERWRITE NEEDS BOTH SIGNS (M-1 of the S4 review). A MISLABELLED
  // entry aimed at the params file is REFUSED: the one door is opened only
  // by an entry that says it is the params file AND names its path. (S4 as
  // first built let this row through "identified by its path"; the fix
  // round made the arm a conjunction, which is strictly more closed.)
  const mislabelled = { what: core.WRITE_SCHEMA, path: "/w/p.params.json", text: "x",
                        mode: core.WRITE_EXPLICIT_OVERWRITE };
  assert.strictEqual(core.writeStep(mislabelled, "/w/p.params.json", true).act, undefined,
                     "a schema label never opens the overwrite, even on the params path");
  assert.strictEqual(core.writeStep(mislabelled, "/w/p.params.json", true).problem.reason,
                     "overwrite-not-params");
  assert.strictEqual(core.writeStep(mislabelled, "/w/other.params.json", true).problem.reason,
                     "overwrite-not-params");
  // AND THE ROW THE S4 TABLE NEVER HAD, which is the review's MEASURED hole:
  // {what: PARAMS, path: <not the params file>} with the permission. Before
  // the fix every one of these OVERWROTE (the schema file, the .gitignore,
  // a path outside the workspace), whether paramsPath was known or not.
  for (const pp of ["/w/p.params.json", undefined, "", null]) {
    for (const target of ["/w/.ermine/preview/m/report.schema.json", "/w/.ermine/preview/.gitignore",
                          "/etc/passwd"]) {
      const labelled = { what: core.WRITE_PARAMS, path: target, text: "x",
                         mode: core.WRITE_EXPLICIT_OVERWRITE };
      const step = core.writeStep(labelled, pp, true);
      assert.strictEqual(step.act, undefined, target + " with paramsPath " + JSON.stringify(pp));
      assert.strictEqual(step.problem.reason, "overwrite-not-params",
                         target + " with paramsPath " + JSON.stringify(pp));
    }
  }
  // With no paramsPath at all even the right label on the right-looking
  // path is refused: there is nothing to compare it with.
  assert.strictEqual(core.writeStep(params, undefined, true).problem.reason, "overwrite-not-params");
});

test("S4 U3: M-2's rules are UNCHANGED by the new mode", () => {
  // Every row of the S3 table still answers what it answered, with and
  // without the new permission -- the door S4 opened is the only one.
  const rows = [
    [{ what: core.WRITE_GITIGNORE, path: "/w/.gitignore", mode: core.WRITE_IF_ABSENT },
     core.WRITE_IF_ABSENT, null],
    [{ what: core.WRITE_SCHEMA, path: "/w/s.schema.json", mode: core.WRITE_IF_DIFFERENT },
     core.WRITE_IF_DIFFERENT, null],
    [{ what: core.WRITE_PARAMS, path: "/w/p.params.json", mode: core.WRITE_IF_ABSENT },
     core.WRITE_IF_ABSENT, null],
    [{ what: core.WRITE_PARAMS, path: "/w/p.params.json", mode: core.WRITE_IF_DIFFERENT },
     undefined, "params-not-creatable"],
    [{ what: core.WRITE_SCHEMA, path: "/w/p.params.json", mode: core.WRITE_IF_DIFFERENT },
     undefined, "params-not-creatable"],
    [{ what: core.WRITE_SCHEMA, path: "/w/s.schema.json", mode: "ifabsent" },
     undefined, "unknown-write-mode"],
    [{ what: core.WRITE_PARAMS, path: "/w/p.params.json", mode: "ifabsent" },
     undefined, "params-not-creatable"],
    [{ path: "" }, undefined, "bad-write-entry"],
    [null, undefined, "bad-write-entry"],
  ];
  for (const allow of [undefined, true]) {
    for (const [file, act, reason] of rows) {
      const step = core.writeStep(file, "/w/p.params.json", allow);
      assert.strictEqual(step.act, act, JSON.stringify(file) + " allow=" + allow);
      assert.strictEqual(step.problem ? step.problem.reason : null, reason,
                         JSON.stringify(file) + " allow=" + allow);
    }
  }
});

test("S4 U3: the command's plan is the first pick's plan with ONE mode moved", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const automatic = core.paramsWritePlan(paths, SALES_SCHEMA, TODAY);
  const replacing = core.skeletonCommandPlan(paths, SALES_SCHEMA, TODAY, true);
  const creating = core.skeletonCommandPlan(paths, SALES_SCHEMA, TODAY, false);

  // BYTE-IDENTICAL apart from the params entry's mode -- two skeletons that
  // could differ is two checkouts that disagree about the same report.
  assert.deepStrictEqual(replacing.skeleton, automatic.skeleton);
  assert.deepStrictEqual(replacing.files.map((f) => [f.what, f.path, f.text]),
                         automatic.files.map((f) => [f.what, f.path, f.text]));
  assert.deepStrictEqual(automatic.files.map((f) => f.mode),
                         [core.WRITE_IF_ABSENT, core.WRITE_IF_DIFFERENT, core.WRITE_IF_ABSENT]);
  assert.deepStrictEqual(replacing.files.map((f) => f.mode),
                         [core.WRITE_IF_ABSENT, core.WRITE_IF_DIFFERENT, core.WRITE_EXPLICIT_OVERWRITE]);
  assert.deepStrictEqual(creating.files.map((f) => f.mode), automatic.files.map((f) => f.mode));

  // `replace` IS A STRICT `true`, the same discipline `schemaOrder`'s
  // `fileMissing` has: an "I do not know" must not read as a confirmation.
  for (const loose of [undefined, null, 0, 1, "true", "yes", {}, []]) {
    assert.strictEqual(core.skeletonCommandPlan(paths, SALES_SCHEMA, TODAY, loose).files[2].mode,
                       core.WRITE_IF_ABSENT, JSON.stringify(loose));
  }
  // And its refusals are the plan's own, unchanged.
  assert.strictEqual(core.skeletonCommandPlan({ problem: { reason: "x" } }, SALES_SCHEMA, TODAY, true)
                       .problem.reason, "no-params-path");
  assert.strictEqual(core.skeletonCommandPlan(paths, "not a schema", TODAY, true).problem.reason,
                     "not-a-schema");
});

// ------------------------------------------------ U3: may the command run?

test("S4 U3: whether the command may run at all, one decision", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const ok = core.skeletonCommandVerdict(SALES_PICK, paths, true);
  assert.strictEqual(ok.run, true);
  assert.strictEqual(ok.reason, null);

  const noPick = core.skeletonCommandVerdict(undefined, paths, true);
  assert.strictEqual(noPick.run, false);
  assert.strictEqual(noPick.reason, "no-pick");
  assert.match(noPick.message, /Ermine: Preview Report/);

  for (const has of [false, undefined, null, "yes"]) {
    const noClient = core.skeletonCommandVerdict(SALES_PICK, paths, has);
    assert.strictEqual(noClient.run, false, JSON.stringify(has));
    assert.strictEqual(noClient.reason, "no-client", JSON.stringify(has));
  }
  assert.strictEqual(core.skeletonCommandVerdict(SALES_PICK, undefined, true).reason, "no-params-path");
  assert.strictEqual(core.skeletonCommandVerdict(SALES_PICK, {}, true).reason, "no-params-path");
});

test("S4 item 4: a pick with NO MODULE and a NON-IDENTIFIER binding are refused BY NAME everywhere", () => {
  // The two edges the S4 row names. Each must (a) have a named reason and a
  // sentence, (b) be said as a log line, (c) write nothing, and (d) be
  // unreachable for the orphan machinery.
  const rows = [
    [core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", null, ["/w/doc"]), "no-module"],
    [core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "<+>", "Sales", ["/w/doc"]), "unsafe-binding"],
    [core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "report", "Not A Module", ["/w/doc"]),
     "unsafe-module"],
    [core.makePick("file:///w/doc/Sales.e", "/w/doc/Sales.e", "NUL", "Sales", ["/w/doc"]), "reserved-name"],
  ];
  for (const [pick, reason] of rows) {
    const paths = core.paramsPaths(pick, "/w", "posix");
    assert.strictEqual(paths.problem.reason, reason);
    assert.ok(paths.problem.message.length > 40, reason + " must have a sentence, not just a reason");
    assert.match(paths.problem.message, /empty parameters/, reason);

    // (b) the NAMED LOG LINE: `prepareParams` carries the problem's own
    // reason and sentence through the builder both sides call, and the
    // notice key is per (pick, reason) so it is said once.
    const prepared = core.preparedParams(paths, { kind: core.PREPARED_PATH_PROBLEM });
    assert.strictEqual(prepared.notice.reason, reason);
    assert.strictEqual(prepared.notice.line, paths.problem.message);
    assert.deepStrictEqual(prepared.params, {}, "and it still renders, with the inline {}");
    assert.strictEqual(prepared.paths, paths, "M-1: `paths` is ALWAYS carried");
    assert.notStrictEqual(core.paramsNoticeKey(pick, reason), core.paramsNoticeKey(pick, "other"));

    // (c) NOTHING IS WRITTEN and no schema is asked for.
    const order = core.schemaOrder(paths, true);
    assert.strictEqual(order.first, "render", reason);
    assert.strictEqual(order.write, false, reason);
    assert.strictEqual(core.paramsWritePlan(paths, SALES_SCHEMA, TODAY).problem.reason, "no-params-path");
    assert.strictEqual(core.skeletonCommandPlan(paths, SALES_SCHEMA, TODAY, true).problem.reason,
                       "no-params-path");

    // (d) THE COMMAND refuses with the SAME named reason and sentence, so
    // the two paths cannot disagree about why there is no params file.
    const verdict = core.skeletonCommandVerdict(pick, paths, true);
    assert.strictEqual(verdict.run, false, reason);
    assert.strictEqual(verdict.reason, reason);
    assert.strictEqual(verdict.message, paths.problem.message);
  }
});

// ------------------------------------------------------------ U3: the modal

test("S4 U3: the confirmation NAMES the file and only one word consents", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const q = core.skeletonConfirmation(paths);
  assert.ok(q.message.indexOf(paths.paramsPath) > 0, "U3: it must name the file");
  assert.match(q.message, /REPLACED/);
  assert.match(q.message, /cannot be undone from here; git can/);
  assert.match(q.message, /schema file beside it is refreshed too/);
  assert.strictEqual(q.confirm, core.SKELETON_REPLACE);

  // A dismissal, an Escape and every near miss are a DECLINE -- `holdRender`'s
  // rule, and this one destroys committed source.
  assert.strictEqual(core.skeletonConfirmed(core.SKELETON_REPLACE), true);
  for (const choice of [undefined, null, "", "replace", "Replace ", "REPLACE", "Yes", 0, true, {}]) {
    assert.strictEqual(core.skeletonConfirmed(choice), false, JSON.stringify(choice));
  }
});

test("S4 U3: an answer given to the modal stops applying when the report moves", () => {
  const same = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales", ["/w/doc"]);
  assert.strictEqual(core.skeletonStillApplies(SALES_PICK, same).apply, true);

  const rows = [
    ["another binding", core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "other", "Sales", ["/w/doc"])],
    ["another file", core.makePick("file:///w/doc/Other.e", "/w/doc/Other.e", "report", "Sales", ["/w/doc"])],
    // THE MODULE IS THE DIRECTORY, and `markKey` does not know about it --
    // which is why this is `isCurrentSchemaAnswer` and not `mayStillSend`.
    ["a header edit", core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales2", ["/w/doc"])],
    ["a roots change", core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales", ["/w/lib"])],
    ["a roots REORDER", core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales",
                                      ["/w/lib", "/w/doc"])],
    ["nothing picked", undefined],
  ];
  for (const [what, now] of rows) {
    const answer = core.skeletonStillApplies(SALES_PICK, now);
    assert.strictEqual(answer.apply, false, what);
    assert.match(answer.why, /while the question was on screen, so nothing was written/, what);
  }
  // `markKey` alone would have said YES to the header edit -- the gap this
  // decision exists for, asserted rather than described.
  assert.strictEqual(core.markKey(SALES_PICK),
                     core.markKey(core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Sales2",
                                                ["/w/doc"])));
});

test("S4 U3: what the command says when it replaced a file", () => {
  const paths = core.paramsPaths(SALES_PICK, "/w", "posix");
  const object = core.skeletonReplacedNotice(paths, true, core.paramsRootShape(SALES_SCHEMA));
  assert.match(object, /^replaced/);
  assert.ok(object.indexOf(paths.paramsPath) > 0);
  assert.ok(object.indexOf(paths.schemaPath) > 0, "the schema file is refreshed too");
  const int = core.skeletonReplacedNotice(paths, false, core.paramsRootShape(WPINT_SCHEMA));
  assert.match(int, /a single whole number/);
});

test("S4: the command's result shape is minted once and fails safe", () => {
  assert.deepStrictEqual(core.skeletonCommandResult({ wrote: true, replaced: true }),
                         { wrote: true, replaced: true, existed: false, abandoned: false, problem: null });
  assert.deepStrictEqual(core.skeletonCommandResult(undefined),
                         { wrote: false, replaced: false, existed: false, abandoned: false, problem: null });
  // Every field is a STRICT boolean, so a truthy accident is not a write.
  assert.strictEqual(core.skeletonCommandResult({ wrote: 1 }).wrote, false);
});

// ------------------------------------------------------ D6: the orphan notice

/** `vscode.workspace.fs.readDirectory` answers `[name, FileType][]`; the glue
  * hands THAT to `core.directoryListing` and so does every test below. */
const DIR_FILE = core.FILE_TYPE_FILE;
const DIR_DIRECTORY = 2;
const DIR_LINKED_FILE = core.FILE_TYPE_SYMLINK | core.FILE_TYPE_FILE;

const SALES_PATHS_S4 = core.paramsPaths(SALES_PICK, "/w", "posix");
const REPORTS = [{ binding: "report", type: "Query -> Node" }, { binding: "summary", type: "() -> Node" }];

test("S4 D6: the directory listing is one shape with three arms, and it fails closed", () => {
  const read = core.directoryListing({ entries: [["report.params.json", DIR_FILE]] });
  assert.deepStrictEqual(read, { entries: [{ name: "report.params.json", type: DIR_FILE }],
                                 missing: false, problem: null });
  // The `{name, type}` spelling is accepted too, so a model need not fake
  // tuples if it holds its disk differently.
  assert.deepStrictEqual(core.directoryListing({ entries: [{ name: "a", type: 1 }] }).entries,
                         [{ name: "a", type: 1 }]);
  assert.deepStrictEqual(core.directoryListing({ entries: [] }).entries, []);

  const missing = core.directoryListing({ missing: true });
  assert.strictEqual(missing.missing, true);
  assert.deepStrictEqual(missing.entries, []);
  assert.strictEqual(missing.problem, null);

  const bad = core.directoryListing({ problem: { reason: "unreadable", message: "EACCES" } });
  assert.strictEqual(bad.problem.reason, "unreadable");
  assert.strictEqual(bad.entries, null);

  // FAIL CLOSED: anything else is a problem, not an empty directory --
  // "we could not read it" is not "there is nothing stale", which is the
  // same distinction `statType`'s third answer exists for (D-2).
  for (const over of [undefined, null, {}, { entries: "nope" }, { entries: 7 }, "x"]) {
    assert.strictEqual(core.directoryListing(over).problem.reason, "bad-listing", JSON.stringify(over));
  }
  // Every key is ALWAYS present, so `if (listing.problem)` cannot read
  // `undefined` off a shape that forgot to declare itself (D-1's class).
  for (const over of [{ entries: [] }, { missing: true }, { problem: { reason: "x", message: "y" } }, {}]) {
    const listing = core.directoryListing(over);
    for (const key of ["entries", "missing", "problem"]) {
      assert.ok(Object.prototype.hasOwnProperty.call(listing, key), key + " for " + JSON.stringify(over));
    }
  }
});

test("S4 D6: which params files name a binding the server no longer offers", () => {
  const listing = (entries) => core.directoryListing({ entries });
  const find = (entries, reports) =>
    core.orphanParamsFiles(listing(entries), reports, SALES_PATHS_S4, "posix");

  // NONE: an empty directory, and a directory that is not there.
  assert.deepStrictEqual(find([], REPORTS).orphans, []);
  assert.deepStrictEqual(
    core.orphanParamsFiles(core.directoryListing({ missing: true }), REPORTS, SALES_PATHS_S4, "posix"),
    { orphans: [], problem: null,
      why: "there is no params directory for this module yet, so nothing can be stale" });

  // MATCHING: every file names a binding that is still offered.
  assert.deepStrictEqual(find([["report.params.json", DIR_FILE],
                               ["summary.params.json", DIR_FILE],
                               ["report.schema.json", DIR_FILE]], REPORTS).orphans, []);

  // ONE STALE -- the D6 case: the binding was renamed and its file lingers.
  const one = find([["report.params.json", DIR_FILE], ["oldName.params.json", DIR_FILE]], REPORTS);
  assert.deepStrictEqual(one.orphans, [{ binding: "oldName", fileName: "oldName.params.json",
                                         path: "/w/.ermine/preview/Sales/oldName.params.json" }]);
  assert.strictEqual(one.problem, null);

  // SEVERAL, in the order the directory gave them.
  assert.deepStrictEqual(
    find([["b.params.json", DIR_FILE], ["a.params.json", DIR_FILE]], REPORTS).orphans.map((o) => o.binding),
    ["b", "a"]);

  // A STALE MODULE DIRECTORY, and everything else that is not a plain FILE.
  // `Sales.params.json` as a DIRECTORY, and a SYMLINK, are both left alone:
  // this extension never touches either, and calling one stale is advice to
  // delete something we did not write.
  assert.deepStrictEqual(find([["OldModule", DIR_DIRECTORY],
                               ["weird.params.json", DIR_DIRECTORY],
                               ["linked.params.json", DIR_LINKED_FILE],
                               ["typeless.params.json", null]], REPORTS).orphans, []);

  // NOT ONE OF OURS: a name we could never have minted, and a file that is
  // not a params file at all.
  assert.deepStrictEqual(find([["report.schema.json", DIR_FILE],
                               [".gitignore", DIR_FILE],
                               [".params.json", DIR_FILE],
                               ["params.json", DIR_FILE],
                               ["not an identifier.params.json", DIR_FILE],
                               ["../escape.params.json", DIR_FILE],
                               ["x".repeat(200) + ".params.json", DIR_FILE]], REPORTS).orphans, []);

  // AN UNREADABLE DIRECTORY: a problem, and NOTHING is called stale.
  const unreadable = core.orphanParamsFiles(
    core.directoryListing({ problem: { reason: "unreadable", message: "EACCES: permission denied" } }),
    REPORTS, SALES_PATHS_S4, "posix");
  assert.deepStrictEqual(unreadable.orphans, []);
  assert.strictEqual(unreadable.problem.reason, "unreadable");

  // AND THE THREE FAIL-CLOSED ARMS, each of which would otherwise call every
  // file in the directory stale at the worst possible moment.
  const stale = [["oldName.params.json", DIR_FILE]];
  for (const reports of [undefined, null, "reports", 7, {}]) {
    const answer = find(stale, reports);
    assert.deepStrictEqual(answer.orphans, [], JSON.stringify(reports));
    assert.match(answer.why, /did not list this file's reports/, JSON.stringify(reports));
  }
  const empty = find(stale, []);
  assert.deepStrictEqual(empty.orphans, []);
  assert.match(empty.why, /offered no report-typed binding at all/);
  assert.match(empty.why, /does not compile right now/);

  // A `reports` entry with no binding does not hide anything and does not throw.
  assert.deepStrictEqual(find(stale, [{ type: "x" }, null, { binding: "report" }]).orphans.map((o) => o.binding),
                         ["oldName"]);
  // A binding called `__proto__` is an ORDINARY key here (I-1's lesson).
  assert.deepStrictEqual(find([["__proto__.params.json", DIR_FILE]],
                              [{ binding: "__proto__" }]).orphans, [],
                         "a __proto__ binding that IS offered must not read as an orphan");
  assert.deepStrictEqual(find([["toString.params.json", DIR_FILE]], REPORTS).orphans.map((o) => o.binding),
                         ["toString"],
                         "and a prototype method name that is NOT offered must not read as offered");

  // A listing that is not a listing at all.
  assert.strictEqual(core.orphanParamsFiles(undefined, REPORTS, SALES_PATHS_S4).problem.reason, "bad-listing");
  assert.strictEqual(core.orphanParamsFiles({ entries: "no", missing: false, problem: null }, REPORTS,
                                            SALES_PATHS_S4).problem.reason, "bad-listing");
});

test("S4 D6: win32 orphan paths are joined the win32 way", () => {
  const winPick = core.makePick("file:///C:/w/doc/Sales.e", "C:\\w\\doc\\Sales.e", "report", "Sales",
                                ["C:\\w\\doc"]);
  const winPaths = core.paramsPaths(winPick, "C:\\w", "win32");
  const found = core.orphanParamsFiles(core.directoryListing({ entries: [["old.params.json", DIR_FILE]] }),
                                       REPORTS, winPaths, "win32");
  assert.strictEqual(found.orphans[0].path, "C:\\w\\.ermine\\preview\\Sales\\old.params.json");
});

test("S4 D6: ONE notice per (module, binding) per session, and what it says", () => {
  const other = core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "summary", "Sales", ["/w/doc"]);
  // THE SAME stale file is found again from every binding in the module, so
  // the key is the MODULE's and not the pick's -- a per-pick key would be a
  // notification per pick for the rest of the session.
  assert.strictEqual(core.orphanNoticeKey(SALES_PICK, "old"), core.orphanNoticeKey(other, "old"));
  assert.notStrictEqual(core.orphanNoticeKey(SALES_PICK, "old"), core.orphanNoticeKey(SALES_PICK, "older"));
  const elsewhere = core.makePick("file:///w/doc/Other.e", "/w/doc/Other.e", "report", "Other", ["/w/doc"]);
  assert.notStrictEqual(core.orphanNoticeKey(SALES_PICK, "old"), core.orphanNoticeKey(elsewhere, "old"));
  // It cannot collide with S2's or S3's notice keys for the same pick.
  assert.notStrictEqual(core.orphanNoticeKey(SALES_PICK, "old"), core.paramsNoticeKey(SALES_PICK, "old"));
  assert.notStrictEqual(core.orphanNoticeKey(SALES_PICK, "old"), core.schemaNoticeKey(SALES_PICK, "old"));

  const text = core.orphanNoticeText(
    { binding: "oldName", fileName: "oldName.params.json",
      path: "/w/.ermine/preview/Sales/oldName.params.json" }, SALES_PICK);
  assert.ok(text.indexOf("/w/.ermine/preview/Sales/oldName.params.json") >= 0, "it names the FILE");
  assert.match(text, /no longer offers a report called "oldName"/);
  // Nit 1 of the S4 review: a binding made PRIVATE looks exactly like a
  // deleted one to `ermine/preview/reports`, so the sentence says so.
  assert.match(text, /renamed or removed, or the module has made it private/);
  assert.match(text, /the preview will not delete it/, "D6: nothing is ever deleted");
  assert.match(text, /delete it yourself/);
  assert.ok(text.indexOf(core.ORPHAN_BUTTON) > 0, "it says what the button does");
  assert.match(text, /the report picked now/, "and that the button is about the CURRENT pick");

  assert.match(core.orphanListingNotice({ reason: "unreadable", message: "EACCES" }, "/w/x"),
               /could not list \/w\/x \(EACCES\), so left-over params files under it were not looked for/);
  assert.match(core.orphanListingNotice(null, "/w/x"), /the editor did not say why/);
});

// ------------------------- the async model of U3's command and D6's scan
//
// `firstPickModel` with the COMMAND and the ORPHAN SCAN on it, statement for
// statement from `extension.js`, calling the SAME pure decisions and the SAME
// builders. What is modelled is the ORDER and the AWAITS, and this stage adds
// the widest await the extension has: a MODAL, which the user can leave on
// screen for minutes while the pick changes, the server restarts and renders
// come and go.
//
// THE MUTANTS, each an option so that each is run against the SAME
// interleavings:
//   `mutantNoConfirm`       the modal is never shown;
//   `mutantLooseConfirm`    anything but `undefined` counts as consent;
//   `mutantNoStillApplies`  the answer is applied to whatever is picked now;
//   `mutantNoPermission`    the write loop is called WITHOUT the permission;
//   `mutantCommandAutoTrigger` the command consults with an AUTOMATIC trigger
//                           (the laundering question, from both ends);
//   `mutantOrphanDeletes`   the scan deletes what it finds (D6's one rule);
//   `mutantClearMarkEarly`  the wedge mark is cleared BEFORE the work, as the
//                           first cut did (the S4 review's M-3);
//   `mutantNoReread`        the replace is written without re-reading the
//                           file after the schema answer (the TOCTOU).

function commandModel(opts) {
  const o = opts || {};
  const m = firstPickModel(o);
  m.modals = [];              // one deferred per modal shown
  m.messages = [];            // showWarningMessage, non-modal
  m.commandLog = [];
  m.orphanNotices = new Set();
  m.orphanShown = [];         // {text, button, settle}
  m.executed = [];            // vscode.commands.executeCommand
  m.deleted = [];             // must stay EMPTY for ever (D6)
  m.revealed = [];

  const log = (line) => m.commandLog.push(line);
  const paramsPathsFor = (pick) => core.paramsPaths(pick, "/w", "posix");

  /** `writeSkeletonNow(attempt, paths, replace, existing)`. */
  m.writeSkeletonNow = async function (attempt, paths, replace, existing) {
    const say = (reason, message) => {
      log(message);
      m.messages.push(message);
      return core.skeletonCommandResult({ problem: { reason, message } });
    };
    const outcome = await m.requestSchema(attempt);
    if (outcome.abandoned) {
      log("command abandoned (" + outcome.abandoned.reason + ")");
      return core.skeletonCommandResult({ abandoned: true });
    }
    if (outcome.problem) return say(outcome.problem.reason, outcome.problem.message);
    // WP-34, the glue's arm (`extension.js` `writeSkeletonNow`). The mutant
    // is the arm deleted (the review's R5).
    if (outcome.noParameters && !o.mutantNoCommandNoParamsArm) {
      return say("no-parameters", core.noParametersNotice(attempt.label));
    }
    const plan = core.skeletonCommandPlan(paths, outcome.schema, m.today, replace === true);
    if (plan.problem) return say(plan.problem.reason, plan.problem.message);
    if (!o.mutantNoSymlinkCheck) {
      const seen = [];
      for (const target of core.writeTargetPaths(
             paths, [paths.gitignorePath, paths.schemaPath, paths.paramsPath], "posix")) {
        const type = m.disk.type(target);
        if (type !== null) seen.push({ path: target, type });
      }
      const linked = core.writeTargetProblem(seen);
      if (linked) return say(linked.reason, linked.message);
    }
    // THE TOCTOU DECISION (2026-09-23): re-read, and refuse a replace over
    // bytes the modal was not about. `mutantNoReread` is the first cut.
    const now = replace === true ? await Promise.resolve(m.disk.read(paths.paramsPath)) : null;
    const bytes = o.mutantNoReread
      ? { apply: true }
      : core.skeletonBytesStillApply(replace, existing, now, paths.paramsPath);
    if (!bytes.apply) return say(bytes.reason, bytes.message);
    let applied;
    try {
      m.disk.mkdir(paths.dir);
      // **THE PERMISSION, AND IT IS THE CALLER'S.** The mutant drops it,
      // which must make the whole command a no-op rather than a quiet
      // create.
      applied = m.applyWritePlan(plan.files, paths.paramsPath, o.mutantNoPermission ? undefined : true);
    } catch (err) {
      return say("write-failed", String(err && err.message ? err.message : err));
    }
    for (const problem of applied.problems) log(problem.message);
    if (applied.problems.length && applied.wrote.indexOf(core.WRITE_PARAMS) < 0) {
      m.messages.push(applied.problems[0].message);
    }
    if (applied.existed) {
      log("a params file appeared while the parameter schema was being worked out");
      return core.skeletonCommandResult({ existed: true });
    }
    if (applied.wrote.indexOf(core.WRITE_PARAMS) < 0) return core.skeletonCommandResult({});
    log(core.skeletonWrittenNotice(paths, plan, replace === true));
    m.openParamsDocument(paths.paramsPath, true);
    return core.skeletonCommandResult({ wrote: true, replaced: replace === true });
  };

  /** `writeParamsSkeletonCommand(context)`. */
  m.writeParamsSkeleton = async function () {
    const paths = paramsPathsFor(m.picked);
    const verdict = core.skeletonCommandVerdict(m.picked, paths, m.hasClient);
    if (!verdict.run) {
      log(verdict.message);
      m.messages.push(verdict.message);
      return core.skeletonCommandResult({ problem: { reason: verdict.reason, message: verdict.message } });
    }
    const askedPick = m.picked;
    const existing = await Promise.resolve(m.disk.read(paths.paramsPath));
    if (existing !== null && !o.mutantNoConfirm) {
      const question = core.skeletonConfirmation(paths);
      const d = deferred();
      m.modals.push({ message: question.message, confirm: question.confirm, settle: d.settle });
      const choice = await d.promise;
      const consented = o.mutantLooseConfirm ? choice !== undefined : core.skeletonConfirmed(choice);
      if (!consented) {
        log("declined; " + paths.paramsPath + " is untouched");
        return core.skeletonCommandResult({ abandoned: true });
      }
    }
    const still = o.mutantNoStillApplies ? { apply: true } : core.skeletonStillApplies(askedPick, m.picked);
    if (!still.apply) {
      log("abandoned — " + still.why);
      return core.skeletonCommandResult({ abandoned: true });
    }
    // WP-22 / M-3: the mark is NOT cleared here; `mutantClearMarkEarly` is
    // the first cut, which spent it before the work on every failing path.
    if (o.mutantClearMarkEarly) m.mark = core.guardReduce(m.mark, { type: "render", explicit: true }).mark;
    const trigger = o.mutantCommandAutoTrigger ? core.TRIGGER_PARAMS_FILE : core.TRIGGER_EXPLICIT;
    const permitted = core.mayAutoRender(m.mark, m.picked, trigger);
    if (!permitted.render) {
      log("HELD (" + permitted.why + ")");
      m.held.push({ generation: m.generation, trigger, mark: m.mark, why: permitted.why });
      return core.skeletonCommandResult({ abandoned: true });
    }
    const attempt = core.renderAttempt(m.generation, m.picked, m.clientEpoch, m.stopCount, m.stuck.highWater);
    const written = await m.writeSkeletonNow(attempt, paths, existing !== null, existing);
    if (written.wrote) {
      // M-3: spent HERE, beside the render, and on no failing path.
      m.mark = core.guardReduce(m.mark, { type: "render", explicit: true }).mark;
      m.revealNextRender = true;
      m.revealed.push(true);
      m.scheduled.push({ reason: "the params skeleton was written by the Write Params Skeleton command",
                         trigger: core.TRIGGER_EXPLICIT });
    }
    return written;
  };

  /** `noticeOrphanParamsFiles(pick, listed)`. */
  m.noticeOrphans = async function (pick, listed) {
    if (!pick || !pick.module) return;
    const paths = paramsPathsFor(pick);
    if (paths.problem) return;
    let listing;
    try {
      const entries = await Promise.resolve(m.disk.readDirectory(paths.dir));
      listing = core.directoryListing({ entries });
    } catch (err) {
      listing = core.meansFileMissing(err)
        ? core.directoryListing({ missing: true })
        : core.directoryListing({ problem: { reason: "unreadable",
                                             message: err && err.message ? String(err.message) : String(err) } });
    }
    const found = core.orphanParamsFiles(listing, listed && listed.reports, paths, "posix");
    // Nit 3 of the S4 review: the SAME plan the glue calls, so what is said
    // (including the unreadable-directory line R24 silenced) is modelled.
    const plan = core.orphanNoticePlan(found, pick, m.orphanNotices, paths.dir);
    if (plan.listingLine !== null) log(plan.listingLine);
    for (const { orphan, text } of plan.orphans) {
      log(text);
      if (o.mutantOrphanDeletes) m.deleted.push(orphan.path);       // the one thing D6 forbids
      const d = deferred();
      m.orphanShown.push({ text, button: core.ORPHAN_BUTTON, settle: d.settle, path: orphan.path });
      d.promise.then((choice) => {
        if (choice !== core.ORPHAN_BUTTON) return;
        m.executed.push(core.SKELETON_COMMAND);
      });
    }
  };

  m.answerModal = (i, choice) => m.modals[i].settle(choice);
  m.clickOrphan = (i, choice) => m.orphanShown[i].settle(choice);
  return m;
}

const COMMITTED = '{"fromDay": "2026-01-05", "toDay": "2026-03-17", "orderBy": "ByAmount"}';
const PARAMS_PATH = "/w/.ermine/preview/Sales/report.params.json";
const SCHEMA_PATH = "/w/.ermine/preview/Sales/report.schema.json";

test("S4 ASYNC: the ordinary command — confirm, schema, replace, refresh, open, ONE render", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk });
  const run = m.writeParamsSkeleton();
  await flush();
  assert.strictEqual(m.modals.length, 1, "a file is there, so it ASKS");
  assert.ok(m.modals[0].message.indexOf(PARAMS_PATH) > 0, "U3: the modal names the file");
  assert.strictEqual(m.schemas.length, 0, "and it asks the user BEFORE it asks the server");
  assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED, "nothing has been touched yet");

  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  assert.strictEqual(m.schemas.length, 1, "one ermine/schema, and only one");
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;

  assert.strictEqual(result.wrote, true);
  assert.strictEqual(result.replaced, true);
  assert.strictEqual(disk.read(PARAMS_PATH),
                     core.schemaFileText(core.paramsWritePlan(SALES_PATHS_S4, SALES_SCHEMA, m.today).skeleton),
                     "the file holds the SAME skeleton a first pick would have written");
  assert.notStrictEqual(disk.read(PARAMS_PATH), COMMITTED);
  assert.ok(disk.read(SCHEMA_PATH) !== null, "the schema file is refreshed too");
  assert.ok(disk.read("/w/.ermine/preview/.gitignore") !== null, "and the generated .gitignore is made");
  assert.deepStrictEqual(m.opened, [PARAMS_PATH], "and the document is opened");
  assert.deepStrictEqual(m.scheduled.map((s) => s.trigger), [core.TRIGGER_EXPLICIT],
    "ONE render, carrying the command's own EXPLICIT trigger (N-3: consent stays consent)");
  assert.strictEqual(m.revealNextRender, true, "and it reveals, because the user asked for it");
  assert.ok(m.commandLog.some((l) => /^replaced/.test(l)), "and it says so");
});

test("S4 ASYNC: declining leaves the file EXACTLY as it is, and asks the server nothing", async () => {
  for (const choice of [undefined, "Cancel", "", null, "replace"]) {
    const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
    const m = commandModel({ disk });
    const run = m.writeParamsSkeleton();
    await flush();
    m.answerModal(0, choice);
    const result = await run;
    assert.strictEqual(result.abandoned, true, JSON.stringify(choice));
    assert.strictEqual(result.wrote, false, JSON.stringify(choice));
    assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED, JSON.stringify(choice));
    assert.deepStrictEqual(disk.writes, [], JSON.stringify(choice));
    assert.strictEqual(m.schemas.length, 0, "no schema job is queued for a command nobody confirmed");
    assert.deepStrictEqual(m.scheduled, []);
    assert.deepStrictEqual(m.opened, []);
  }
});

test("S4 ASYNC: with NO params file it behaves like a FIRST PICK — no modal, a race-safe create", async () => {
  const m = commandModel({});
  const run = m.writeParamsSkeleton();
  await flush();
  assert.strictEqual(m.modals.length, 0, "nothing can be lost, so nothing is asked");
  assert.strictEqual(m.schemas.length, 1);
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;
  assert.strictEqual(result.wrote, true);
  assert.strictEqual(result.replaced, false, "it CREATED, it did not replace");
  assert.ok(m.disk.writes.indexOf(PARAMS_PATH) < 0,
    "and the params file went through the CREATE, not through an overwrite (only the generated " +
    "schema file is ever written unconditionally on this path)");
  assert.deepStrictEqual(m.disk.creates, ["/w/.ermine/preview/.gitignore", PARAMS_PATH]);
  assert.ok(m.disk.read(PARAMS_PATH) !== null);
  assert.ok(m.commandLog.some((l) => /^wrote/.test(l)), "so it says `wrote`, not `replaced`");
});

test("S4 ASYNC: a params file that APPEARS while the schema is worked out is left alone", async () => {
  // The check-then-act race, answered rather than narrowed: with no file the
  // command takes the `ifAbsent` create, so a `git checkout` landing in the
  // gap keeps ITS bytes and the user is told to run the command again.
  const m = commandModel({});
  const run = m.writeParamsSkeleton();
  await flush();
  m.disk.files.set(PARAMS_PATH, COMMITTED);            // somebody else's write
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;
  assert.strictEqual(result.existed, true);
  assert.strictEqual(result.wrote, false);
  assert.strictEqual(m.disk.read(PARAMS_PATH), COMMITTED, "THE RACE: their bytes survive");
  assert.deepStrictEqual(m.scheduled, [], "and no render is scheduled for a file we did not write");
  assert.ok(m.commandLog.some((l) => /Run the command again/.test(l) || /appeared/.test(l)));
});

test("S4 ASYNC: the pick changes while the question is on screen — nothing is written", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk });
  const run = m.writeParamsSkeleton();
  await flush();
  m.pickAnother("other");                               // the glue's own mutator
  m.answerModal(0, core.SKELETON_REPLACE);
  const result = await run;
  assert.strictEqual(result.abandoned, true);
  assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED);
  assert.strictEqual(m.schemas.length, 0, "and no schema job was queued for the report they left");
  assert.ok(m.commandLog.some((l) => /while the question was on screen/.test(l)));
});

test("S4 ASYNC: a HEADER EDIT during the question also abandons — markKey would not have seen it", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk });
  const run = m.writeParamsSkeleton();
  await flush();
  // `module Sales` -> `module Sales2`, which MOVES the directory the file
  // would be written into and leaves uri and binding alone.
  m.picked = core.makePick(m.picked.uri, m.picked.fsPath, m.picked.binding, "Sales2", m.picked.roots);
  m.answerModal(0, core.SKELETON_REPLACE);
  const result = await run;
  assert.strictEqual(result.abandoned, true);
  assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED);
  assert.strictEqual(disk.read("/w/.ermine/preview/Sales2/report.params.json"), null,
    "and nothing was written under the NEW module either");
});

test("S4 ASYNC: a SERVER RESTART during the question is fine; one during the SCHEMA abandons", async () => {
  // The snapshot is taken AFTER the modal, on purpose: a restart while the
  // question is on screen simply means the request goes to the server that
  // is running when the user answers, which is what they asked for.
  const during = commandModel({ disk: diskModel({ files: [[PARAMS_PATH, COMMITTED]] }) });
  const runA = during.writeParamsSkeleton();
  await flush();
  during.serverRestarted();
  during.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  assert.strictEqual(during.schemas.length, 1, "the fresh server is asked");
  during.answerSchema(0, SALES_SCHEMA);
  assert.strictEqual((await runA).wrote, true);

  // A restart DURING the schema request is D7's own case and abandons.
  const after = commandModel({ disk: diskModel({ files: [[PARAMS_PATH, COMMITTED]] }) });
  const runB = after.writeParamsSkeleton();
  await flush();
  after.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  after.serverRestarted();
  after.answerSchema(0, SALES_SCHEMA);
  const result = await runB;
  assert.strictEqual(result.abandoned, true);
  assert.strictEqual(after.disk.read(PARAMS_PATH), COMMITTED, "the committed file survives");
});

test("S4 ASYNC: every way the schema can fail says so and writes NOTHING", async () => {
  const rows = [
    ["an {error}", (m) => m.answerSchema(0, { error: "Sales.e:12: not in scope" })],
    ["Q8's stuck refusal", (m) => m.answerSchema(0, { error: "the preview is stuck", stuck: true })],
    ["an answer that is not an object", (m) => m.answerSchema(0, "nope")],
    ["a transport rejection", (m) => m.rejectSchema(0, new Error("socket closed"))],
  ];
  for (const [what, settle] of rows) {
    const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
    const m = commandModel({ disk });
    const run = m.writeParamsSkeleton();
    await flush();
    m.answerModal(0, core.SKELETON_REPLACE);
    await flush();
    settle(m);
    const result = await run;
    assert.strictEqual(result.wrote, false, what);
    assert.ok(result.problem, what);
    assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED, what);
    assert.deepStrictEqual(disk.writes, [], what);
    // A COMMAND ANSWERS EVERY TIME. `schemaNoticeOnce` dedupes the automatic
    // path, where a line per render would be a storm; a command the user ran
    // twice must not be silent the second time.
    assert.strictEqual(m.messages.length, 1, what);
  }
});

test("S4 ASYNC: a read-only workspace refuses by name and leaves the file alone", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]], readOnly: true });
  const m = commandModel({ disk });
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;
  assert.strictEqual(result.wrote, false);
  assert.strictEqual(result.problem.reason, "write-failed");
  assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED);
  assert.deepStrictEqual(m.scheduled, []);
});

test("S4 ASYNC: a SYMLINK anywhere on the way refuses the command too (M-3)", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED], ["/outside/precious", "PRECIOUS"]] });
  disk.symlink(PARAMS_PATH, "/outside/precious");
  const m = commandModel({ disk });
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;
  assert.strictEqual(result.wrote, false);
  assert.strictEqual(result.problem.reason, "symlink");
  assert.strictEqual(disk.read("/outside/precious"), "PRECIOUS");
});

test("S4 ASYNC: the command runs while HELD, and CLEARS the mark — it is consent", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk });
  // The report wedged the preview and nothing has changed since.
  m.mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: m.picked,
                                    params: {}, at: 1000 }).mark;
  assert.ok(core.markMatches(m.mark, m.picked), "it really is held");
  assert.strictEqual(core.mayAutoRender(m.mark, m.picked, core.TRIGGER_PARAMS_FILE).render, false,
    "and an automatic save of its params file would be refused");

  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;
  assert.strictEqual(result.wrote, true, "an explicit command is never refused");
  assert.strictEqual(m.mark, null, "and it CLEARS the mark, exactly as the render command does");
  assert.deepStrictEqual(m.held, []);
  assert.deepStrictEqual(m.scheduled.map((s) => s.trigger), [core.TRIGGER_EXPLICIT]);
});

test("S4 ASYNC: the OVERWRITE mode is reachable ONLY with the caller's permission", async () => {
  // **THE PROPERTY THIS STAGE TURNS ON.** The mode alone must write nothing:
  // drop the permission at the one call site and the command becomes a
  // no-op that says why, rather than a quiet create or a quiet overwrite.
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk, mutantNoPermission: true });
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  m.answerSchema(0, SALES_SCHEMA);
  const result = await run;
  assert.strictEqual(result.wrote, false, "the mutant writes NOTHING");
  assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED, "and the committed source is untouched");
  assert.ok(m.messages.some((x) => /may not replace anything/.test(x)),
    "and it is REFUSED BY NAME rather than silently skipped");

  // AND THE SAME PLAN, HANDED TO THE AUTOMATIC PATH, WRITES NOTHING EITHER.
  // `firstPickSchemaAndWrite` calls `applyWritePlan(plan.files, paramsPath)`
  // with two arguments, so the third is `undefined` for it, for ever.
  const auto = firstPickModel({ disk: diskModel({ files: [[PARAMS_PATH, COMMITTED]] }) });
  const leaked = core.skeletonCommandPlan(SALES_PATHS_S4, SALES_SCHEMA, TODAY, true);
  const applied = auto.applyWritePlan(leaked.files, SALES_PATHS_S4.paramsPath);
  assert.ok(applied.wrote.indexOf(core.WRITE_PARAMS) < 0);
  assert.strictEqual(applied.problems[0].reason, "overwrite-not-permitted");
  assert.strictEqual(auto.disk.read(PARAMS_PATH), COMMITTED);
});

test("S4 ASYNC: the command cannot LAUNDER an automatic render", async () => {
  // The worry: the command clears the wedge mark, so anything that can make
  // the command run can un-hold a report that wedged the server. Two halves.
  //
  // (1) THE TRIGGER IS THE COMMAND'S OWN, and if it were ever an automatic
  //     one the consultation REFUSES it -- the site is not decorative. Since
  //     the S4 review's M-3 the mark is no longer cleared BEFORE the
  //     consultation, so this is now observable end to end: held, nothing
  //     asked of the server, nothing written, the mark intact. (Under the
  //     first cut the early clear hid the mark from the consultation.)
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk, mutantCommandAutoTrigger: true });
  const wedged = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: m.picked,
                                          params: {}, at: 1000 }).mark;
  m.mark = wedged;
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  const held = await run;
  assert.strictEqual(held.abandoned, true, "an automatic trigger is HELD by the mark");
  assert.strictEqual(m.schemas.length, 0, "and nothing is asked of the server");
  assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED, "and nothing is written");
  assert.strictEqual(m.mark, wedged, "and the hold is intact");
  // The command's OWN trigger over the same mark: consent, so it runs --
  // and the mark is spent only because the file WAS written (M-3).
  const own = commandModel({ disk: diskModel({ files: [[PARAMS_PATH, COMMITTED]] }) });
  own.mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: own.picked,
                                      params: {}, at: 1000 }).mark;
  const ran = own.writeParamsSkeleton();
  await flush();
  own.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  own.answerSchema(0, SALES_SCHEMA);
  assert.strictEqual((await ran).wrote, true);
  assert.strictEqual(own.mark, null);

  // (2) NOTHING AUTOMATIC REACHES IT. The only two doors are the palette's
  //     registration and the orphan notification's BUTTON, and the button is
  //     a click: a notification that is dismissed, ignored or answered with
  //     anything else runs nothing.
  const scan = commandModel({ disk: diskModel({ files: [[PARAMS_PATH, COMMITTED],
                                                        ["/w/.ermine/preview/Sales/old.params.json", "{}"]] }) });
  await scan.noticeOrphans(scan.picked, { reports: REPORTS });
  assert.strictEqual(scan.orphanShown.length, 1, "the orphan is noticed");
  assert.deepStrictEqual(scan.executed, [], "and NOTHING has run");
  for (const dismissal of [undefined, null, "", "Dismiss", core.SKELETON_REPLACE]) {
    scan.clickOrphan(0, dismissal);
    await flush();
    assert.deepStrictEqual(scan.executed, [], JSON.stringify(dismissal));
  }
  const clicked = commandModel({ disk: diskModel({ files: [["/w/.ermine/preview/Sales/old.params.json", "{}"]] }) });
  await clicked.noticeOrphans(clicked.picked, { reports: REPORTS });
  clicked.clickOrphan(0, core.ORPHAN_BUTTON);
  await flush();
  assert.deepStrictEqual(clicked.executed, [core.SKELETON_COMMAND],
    "only the button runs it, and it runs it through executeCommand -- the palette's own door");
});

// ------------------------------------------------- D6: the scan, interleaved

test("S4 ASYNC D6: the listing shapes, end to end through the glue's own order", async () => {
  // NONE -- there is no params directory yet (the ordinary case).
  const none = commandModel({});
  await none.noticeOrphans(none.picked, { reports: REPORTS });
  assert.deepStrictEqual(none.orphanShown, []);
  assert.deepStrictEqual(none.commandLog, []);

  // MATCHING -- every file names a binding the server still offers.
  const matching = commandModel({ disk: diskModel({ files: [
    [PARAMS_PATH, COMMITTED],
    ["/w/.ermine/preview/Sales/summary.params.json", "{}"],
    [SCHEMA_PATH, "{}"]] }) });
  await matching.noticeOrphans(matching.picked, { reports: REPORTS });
  assert.deepStrictEqual(matching.orphanShown, []);

  // ONE STALE -- D6 itself.
  const stale = commandModel({ disk: diskModel({ files: [
    [PARAMS_PATH, COMMITTED],
    ["/w/.ermine/preview/Sales/oldName.params.json", "{}"]] }) });
  await stale.noticeOrphans(stale.picked, { reports: REPORTS });
  assert.strictEqual(stale.orphanShown.length, 1);
  assert.ok(stale.orphanShown[0].text.indexOf("oldName.params.json") > 0);
  assert.deepStrictEqual(stale.deleted, [], "**NOTHING IS EVER DELETED**");
  assert.ok(stale.disk.read("/w/.ermine/preview/Sales/oldName.params.json") !== null);

  // ONCE PER (MODULE, BINDING) PER SESSION, over three scans and TWO PICKS
  // in the same module -- which is exactly what a per-pick key would have
  // turned into a notification per pick.
  await stale.noticeOrphans(stale.picked, { reports: REPORTS });
  stale.pickAnother("summary");
  await stale.noticeOrphans(stale.picked, { reports: REPORTS });
  assert.strictEqual(stale.orphanShown.length, 1, "still one");

  // A STALE MODULE DIRECTORY -- NOT COVERED, and the test records it as the
  // known gap rather than pretending. `.ermine/preview/OldModule/` is never
  // looked inside, because the scan is only ever asked about the CURRENT
  // pick's module.
  const moduleGone = commandModel({ disk: diskModel({ files: [
    [PARAMS_PATH, COMMITTED],
    ["/w/.ermine/preview/OldModule/report.params.json", "{}"]] }) });
  await moduleGone.noticeOrphans(moduleGone.picked, { reports: REPORTS });
  assert.deepStrictEqual(moduleGone.orphanShown, [],
    "a renamed MODULE is NOT detected: knowing it would cost one ermine/preview/reports — a job " +
    "that COMPILES a module — per .e file in the workspace. Recorded, not fixed (section 6's S4 block)");

  // AN UNREADABLE DIRECTORY -- said once, and nothing is called stale.
  const unreadable = commandModel({ disk: diskModel({
    files: [[PARAMS_PATH, COMMITTED]],
    readDirThrows: Object.assign(new Error("EACCES: permission denied"), { code: "EACCES" }) }) });
  await unreadable.noticeOrphans(unreadable.picked, { reports: REPORTS });
  await unreadable.noticeOrphans(unreadable.picked, { reports: REPORTS });
  assert.deepStrictEqual(unreadable.orphanShown, []);
  assert.strictEqual(unreadable.commandLog.length, 1);
  assert.match(unreadable.commandLog[0], /could not list/);
});

test("S4 ASYNC D6: the scan never runs for a pick that can have no params file", async () => {
  // Item 4 again, from the orphan side: no module, an operator binding, a
  // module name that is not a directory name. None of them may reach a
  // `readDirectory`, and none may be told anything is stale.
  for (const pick of [
    core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", null, ["/w/doc"]),
    core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "<+>", "Sales", ["/w/doc"]),
    core.makePick(SALES_PICK.uri, SALES_PICK.fsPath, "report", "Not A Module", ["/w/doc"]),
    undefined,
  ]) {
    const m = commandModel({ disk: diskModel({ files: [
      ["/w/.ermine/preview/Sales/oldName.params.json", "{}"]] }) });
    await m.noticeOrphans(pick, { reports: REPORTS });
    assert.deepStrictEqual(m.orphanShown, [], core.pickLabel(pick));
    assert.deepStrictEqual(m.commandLog, [], core.pickLabel(pick));
  }
});

test("S4 ASYNC D6: a server that could not list the file calls NOTHING stale", async () => {
  for (const listed of [undefined, null, {}, { error: "Sales.e:1: expected `where`" }, { reports: [] }]) {
    const m = commandModel({ disk: diskModel({ files: [
      ["/w/.ermine/preview/Sales/oldName.params.json", "{}"]] }) });
    await m.noticeOrphans(m.picked, listed);
    assert.deepStrictEqual(m.orphanShown, [], JSON.stringify(listed));
    assert.deepStrictEqual(m.deleted, [], JSON.stringify(listed));
  }
});

// ------------------------------------------------------------ S4 SOURCE PINS
//
// The chain that makes "only U3's command overwrites a params file"
// STRUCTURAL rather than careful is a shape of `extension.js`, and no model
// in this file can see it: a model is written from the glue, so a model and
// a glue that drift agree with each other and with nothing else. Each pin
// says what it is and what it protects.

// ------------------------------------------------ the S4 fix round (2026-09-23)

test("S4 fix (nit 2): on WIN32 the orphan compare folds case; on POSIX it does not", () => {
  const listing = core.directoryListing({ entries: [
    ["Report.params.json", DIR_FILE],           // the live file for `report`, on NTFS
    ["gone.PARAMS.JSON", DIR_FILE],             // a real orphan, spelled loudly
  ] });
  const reports = [{ binding: "report" }];
  const win = core.orphanParamsFiles(listing, reports, { dir: "C:\\w\\.ermine\\preview\\Sales" }, "win32");
  assert.deepStrictEqual(win.orphans.map((o) => o.binding), ["gone"],
    "on a case-insensitive file system Report.params.json IS report's file, so it is not an orphan");
  const posix = core.orphanParamsFiles(listing, reports, { dir: "/w/.ermine/preview/Sales" }, "posix");
  assert.deepStrictEqual(posix.orphans.map((o) => o.binding), ["Report"],
    "on POSIX they are different files, and `gone.PARAMS.JSON` is not a name we mint");
});

test("S4 fix (M-4): ONE open-once decision for the glue and both models", () => {
  const opened = new Set();
  assert.strictEqual(core.claimParamsDocument(opened, "/p", undefined), true, "first time: open");
  assert.strictEqual(core.claimParamsDocument(opened, "/p", undefined), false, "then: once per path");
  assert.strictEqual(core.claimParamsDocument(opened, "/p", false), false);
  assert.strictEqual(core.claimParamsDocument(opened, "/p", "true"), false, "only `true` is always");
  assert.strictEqual(core.claimParamsDocument(opened, "/p", true), true, "U3's command: every time");
  assert.strictEqual(core.claimParamsDocument(opened, "/q", false), true, "another path is its own");
  assert.deepStrictEqual([...opened].sort(), ["/p", "/q"]);
});

test("S4 fix (M-4): the AUTOMATIC first-pick notice says what a non-object root MEANS", async () => {
  // Through the model, which now hands the PLAN to the same builder the glue
  // does. Before the fix this model read the generic fallback, so dropping
  // `plan.shape` was visible to a source pin only (R15).
  const rows = [
    [WPINT_SCHEMA, /a single whole number, so the file holds just that number/],
    [WPUNIT_SCHEMA, /the empty tuple `\(\)`/],
    [WPJSON_SCHEMA, /any JSON value at all/],
  ];
  for (const [schema, sentence] of rows) {
    const m = firstPickModel();
    m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
    await flush();
    m.readMissing(0);
    await flush();
    m.answerSchema(0, schema);
    await flush();
    const written = m.notices.filter((n) => n.reason === "written");
    assert.strictEqual(written.length, 1, String(sentence));
    assert.match(written[0].line, sentence);
    assert.match(written[0].line, /carries no "\$schema" line/);
    assert.deepStrictEqual(m.opened, [PARAMS_PATH]);
  }
});

test("S4 fix (re-review nit 4): the COMMAND's notice says what a non-object root MEANS", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, "0"]] });
  const m = commandModel({ disk });
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  m.answerSchema(0, WPINT_SCHEMA);
  assert.strictEqual((await run).replaced, true);
  const line = m.commandLog.filter((l) => /^replaced /.test(l));
  assert.strictEqual(line.length, 1);
  assert.match(line[0], /a single whole number, so the file holds just that number/);
});

test("S4 fix (M-4): the document opens once per path automatically, and EVERY time for the command", async () => {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel({ disk });
  for (let i = 0; i < 2; i++) {
    const run = m.writeParamsSkeleton();
    await flush();
    m.answerModal(i, core.SKELETON_REPLACE);
    await flush();
    m.answerSchema(i, SALES_SCHEMA);
    assert.strictEqual((await run).wrote, true);
  }
  assert.deepStrictEqual(m.opened, [PARAMS_PATH, PARAMS_PATH],
    "the user who asked twice is shown the file twice (R14: dropping `always` showed nothing)");
  // And the automatic open, which is once per path: the command has already
  // claimed it, so an automatic open of the same path shows nothing more.
  m.openParamsDocument(PARAMS_PATH);
  assert.deepStrictEqual(m.opened, [PARAMS_PATH, PARAMS_PATH]);
});

test("S4 fix (TOCTOU): the decision, as a table", () => {
  const P = "/w/p.params.json";
  const ok = (r, b, n) => core.skeletonBytesStillApply(r, b, n, P).apply;
  assert.strictEqual(ok(true, "A", "A"), true, "the same bytes: replace");
  assert.strictEqual(ok(true, "A", "A\n"), false, "one byte more: refuse");
  assert.strictEqual(ok(true, "A", ""), false, "emptied: refuse");
  assert.strictEqual(ok(true, "A", null), false, "gone: refuse");
  assert.strictEqual(ok(true, null, null), false, "nothing was asked about: refuse (never a replace)");
  assert.strictEqual(ok(false, null, "B"), true, "a CREATE is the race-safe create's business");
  assert.strictEqual(ok(undefined, "A", "B"), true, "and only `true` is a replace");
  const refused = core.skeletonBytesStillApply(true, "A", "B", P);
  assert.strictEqual(refused.reason, "params-changed");
  assert.ok(refused.message.indexOf(P) > 0, "it names the file");
  assert.match(refused.message, /changed after you were asked/);
  assert.match(refused.message, /nothing was written; run the command again/);
  assert.match(core.skeletonBytesStillApply(true, "A", null, P).message, /was removed or could not be read after you were asked/);
});

/** The TOCTOU scenario the review MEASURED (probe/overwrite.js case 4):
  * Replace is clicked, then the file is edited and SAVED while the schema
  * request runs. Answers the model and the run's result. */
async function editedDuringSchema(opts, edit) {
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED]] });
  const m = commandModel(Object.assign({ disk }, opts));
  m.mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: m.picked,
                                    params: {}, at: 1000 }).mark;
  const mark = m.mark;
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, core.SKELETON_REPLACE);
  await flush();
  edit(disk);                                          // autoSave, or the developer
  m.answerSchema(0, SALES_SCHEMA);
  return { m, disk, mark, result: await run };
}

const FRESH_EDIT = '{"fromDay": "2026-02-01", "toDay": "2026-02-28", "orderBy": "ByDay"}';

test("S4 fix (TOCTOU): a file SAVED while the schema request runs is NOT replaced — refused by name", async () => {
  const { m, disk, mark, result } = await editedDuringSchema({}, (d) => d.files.set(PARAMS_PATH, FRESH_EDIT));
  assert.strictEqual(result.wrote, false);
  assert.strictEqual(result.problem.reason, "params-changed");
  assert.strictEqual(disk.read(PARAMS_PATH), FRESH_EDIT, "THE FRESH EDIT SURVIVES");
  assert.deepStrictEqual(disk.writes, [], "and nothing else is written either");
  assert.deepStrictEqual(m.scheduled, [], "no render");
  assert.strictEqual(m.mark, mark, "and the wedge hold is not spent (M-3)");
  assert.strictEqual(m.messages.length, 1, "said, as a notification");
  assert.ok(m.messages[0].indexOf(PARAMS_PATH) > 0 &&
            /changed after you were asked/.test(m.messages[0]), m.messages[0]);

  // A file DELETED in the same window is refused too: the user consented to
  // replacing bytes that are no longer there.
  const gone = await editedDuringSchema({}, (d) => d.files.delete(PARAMS_PATH));
  assert.strictEqual(gone.result.problem.reason, "params-changed");
  assert.strictEqual(gone.disk.read(PARAMS_PATH), null);
  assert.match(gone.m.messages[0], /was removed or could not be read after you were asked/);
});

test("S4 fix MUTANT (TOCTOU): without the re-read, the fresh edit is DESTROYED", async () => {
  const { disk, result } = await editedDuringSchema({ mutantNoReread: true },
                                                    (d) => d.files.set(PARAMS_PATH, FRESH_EDIT));
  assert.strictEqual(result.wrote, true, "the first cut wrote");
  assert.notStrictEqual(disk.read(PARAMS_PATH), FRESH_EDIT, "over bytes the modal never named");
});

/** Every way the command can END WITHOUT WRITING, each over a held report. */
const COMMAND_FAILURES = [
  ["the schema request dies", {}, (m) => m.rejectSchema(0, new Error("socket closed")), "fails"],
  ["the server answers an error", {}, (m) => m.answerSchema(0, { error: "Sales.e:3: nope" }), "fails"],
  ["a symlinked params file", { link: true }, (m) => m.answerSchema(0, SALES_SCHEMA), "fails"],
  ["the file changed under the modal", { edit: true }, (m) => m.answerSchema(0, SALES_SCHEMA), "fails"],
  ["declined", { decline: true }, null, "declined"],
];

async function heldCommand(opts, row) {
  const [, how, settle] = row;
  const disk = diskModel({ files: [[PARAMS_PATH, COMMITTED], ["/outside/precious", "PRECIOUS"]] });
  if (how.link) disk.symlink(PARAMS_PATH, "/outside/precious");
  const m = commandModel(Object.assign({ disk }, opts));
  const mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: m.picked,
                                        params: {}, at: 1000 }).mark;
  m.mark = mark;
  const run = m.writeParamsSkeleton();
  await flush();
  m.answerModal(0, how.decline ? "Cancel" : core.SKELETON_REPLACE);
  await flush();
  if (how.edit) disk.files.set(PARAMS_PATH, FRESH_EDIT);
  if (settle) settle(m);
  return { m, mark, result: await run };
}

test("S4 fix (M-3): a command that writes NOTHING leaves the wedge hold exactly as it was", async () => {
  for (const row of COMMAND_FAILURES) {
    const { m, mark, result } = await heldCommand({}, row);
    assert.notStrictEqual(result.wrote, true, row[0]);
    assert.strictEqual(m.mark, mark, row[0] + ": the hold is intact");
    assert.deepStrictEqual(m.scheduled, [], row[0] + ": nothing is rendered");
    // And so the automatic save of the params file is STILL refused.
    assert.strictEqual(core.mayAutoRender(m.mark, m.picked, core.TRIGGER_PARAMS_FILE).render, false, row[0]);
  }
});

test("S4 fix MUTANT (M-3): clearing the mark BEFORE the work spends it on every failing path", async () => {
  for (const row of COMMAND_FAILURES.filter((r) => r[3] === "fails")) {
    const { m, result } = await heldCommand({ mutantClearMarkEarly: true }, row);
    assert.notStrictEqual(result.wrote, true, row[0]);
    assert.strictEqual(m.mark, null, row[0] + ": the first cut spent the hold for nothing");
    assert.strictEqual(core.mayAutoRender(m.mark, m.picked, core.TRIGGER_PARAMS_FILE).render, true, row[0]);
  }
});

test("glue pins (S4): U3's command, the overwrite chain, and D6's scan", () => {
  const fsMod = require("node:fs");
  const raw = fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const src = codeOf(raw);
  const pin = (what, fix) =>
    "source pin (test/preview-core.test.js): extension.js changed shape — " + what +
    ". If you meant it, update this pin; the behaviour it protects is " + fix;
  const commandBody = src.slice(src.indexOf("async function writeParamsSkeletonCommand("),
                                src.indexOf("async function writeSkeletonNow("));
  const writeBody = src.slice(src.indexOf("async function writeSkeletonNow("),
                              src.indexOf("async function noticeOrphanParamsFiles("));
  const scanBody = src.slice(src.indexOf("async function noticeOrphanParamsFiles("),
                             src.indexOf("async function activate("));
  assert.ok(commandBody.length > 400 && writeBody.length > 400 && scanBody.length > 400,
    "the three S4 slices must be the three S4 functions");

  // ---- THE OVERWRITE IS REACHABLE FROM ONE CALL SITE, AND THAT IS THE POINT
  assert.strictEqual((src.match(/core\.skeletonCommandPlan\(/g) || []).length, 1,
    pin("core.skeletonCommandPlan has more than one caller",
        "that the plan which can carry `explicitOverwrite` is built in exactly ONE place — U3's " +
        "command, after a modal the user answered"));
  assert.ok(writeBody.indexOf("core.skeletonCommandPlan(") > 0,
    pin("the overwrite plan is built somewhere other than writeSkeletonNow", "the same"));
  assert.strictEqual((src.match(/applyWritePlan\(plan\.files, paths\.paramsPath, true\)/g) || []).length, 1,
    pin("the PERMISSION to replace a params file is passed from more or fewer than one call site",
        "U3: `explicitOverwrite` is refused unless its caller passes the permission, and exactly one " +
        "caller does — so a plan that leaks anywhere else writes nothing (asserted in the model too)"));
  assert.ok(writeBody.indexOf("applyWritePlan(plan.files, paths.paramsPath, true)") > 0,
    pin("the permission is passed from somewhere other than writeSkeletonNow", "the same"));
  assert.ok(/applyWritePlan\(plan\.files, paths\.paramsPath\)/.test(
              src.slice(src.indexOf("async function firstPickSchemaAndWrite("),
                        src.indexOf("async function refreshSchemaFile("))),
    pin("the AUTOMATIC first-pick path now passes something as the overwrite permission",
        "that the first-pick write can never replace committed source, whatever mode an entry " +
        "carries — it passes two arguments, so the third is `undefined` for it, for ever"));
  const overwriteBranch = src.slice(src.indexOf("if (step.act === core.WRITE_EXPLICIT_OVERWRITE) {"),
                                    src.indexOf("if (step.act === core.WRITE_IF_ABSENT) {"));
  assert.ok(overwriteBranch.length > 0 && /\n      await writeTextFile\(file\.path, file\.text\);/.test(overwriteBranch),
    pin("the explicit overwrite is no longer a statement of its own, or no longer writes",
        "the neutered-guard class: `if (false && ...)` keeps every word and every call. This branch " +
        "is the ONE unconditional write over committed source in the extension"));

  // ---- THE COMMAND'S ORDER, WHICH IS ITS SAFETY -------------------------
  const verdictAt = commandBody.indexOf("core.skeletonCommandVerdict(");
  const readAt = commandBody.indexOf("await readTextIfPresent(paths.paramsPath)");
  const modalAt = commandBody.indexOf("showWarningMessage(question.message, { modal: true }, question.confirm)");
  const appliesAt = commandBody.indexOf("core.skeletonStillApplies(askedPick, picked)");
  const guardAt = commandBody.indexOf('applyGuard(core.guardReduce(wedgeMark, { type: "render", explicit: true }))');
  const consultAt = commandBody.indexOf("core.mayAutoRender(wedgeMark, picked, core.TRIGGER_EXPLICIT)");
  const snapshotAt = commandBody.indexOf("core.renderAttempt(generation, picked, clientEpoch, stopCount, stuckState.highWater)");
  const writeAt = commandBody.indexOf("await writeSkeletonNow(attempt, paths, existing !== null, existing)");
  const wroteAt = commandBody.indexOf("if (written.wrote) {");
  for (const [what, at] of [["the verdict", verdictAt], ["the read", readAt], ["the modal", modalAt],
                            ["the still-applies check", appliesAt], ["the guard's clear", guardAt],
                            ["the consultation", consultAt], ["the snapshot", snapshotAt],
                            ["the write", writeAt], ["the written branch", wroteAt]]) {
    assert.ok(at > 0, pin("the command no longer has " + what + " in the shape this pin reads",
                          "U3's order, every step of which is load-bearing"));
  }
  assert.ok(verdictAt < readAt && readAt < modalAt && modalAt < appliesAt &&
            appliesAt < consultAt && consultAt < snapshotAt && snapshotAt < writeAt,
    pin("the command's steps are out of order",
        "U3: it checks it CAN run, then asks the user, then re-checks that the answer is still about " +
        "the same report, then consults the mark, then takes its snapshot (AFTER the modal, so the " +
        "schema request belongs to the server running when they answered), then writes"));
  // **M-3 OF THE S4 REVIEW: THE MARK IS SPENT ONLY AFTER A WRITE.** The
  // first cut cleared it before the consultation, so every failing path
  // (the schema request dies, a symlink refusal) spent the user's hold for
  // nothing (MEASURED, probe/mark.js). The clear is now the FIRST statement
  // of the written branch, and it is the only one in the command.
  assert.strictEqual((commandBody.match(/applyGuard\(/g) || []).length, 1,
    pin("the command clears the wedge mark from more or fewer than one place",
        "M-3: the hold is spent only on the path that wrote the file and schedules its render"));
  assert.ok(/\n  if \(written\.wrote\) \{\s*applyGuard\(core\.guardReduce\(wedgeMark, \{ type: "render", explicit: true \}\)\);/.test(commandBody) &&
            guardAt > wroteAt && guardAt > writeAt,
    pin("the wedge mark is cleared somewhere other than the start of the written branch",
        "M-3: a command that wrote nothing (schema request died, symlink refused, file changed " +
        "under the modal, declined) leaves the hold exactly as it was"));
  assert.ok(commandBody.indexOf("await requestSchema(") < 0 && writeBody.indexOf("await requestSchema(") > 0,
    pin("the command asks the server for a schema before, or instead of, asking the user",
        "U3: nothing is asked of the preview queue — a job that COMPILES and EVALUATES the report — " +
        "until the user has confirmed"));
  assert.ok(/if \(!core\.skeletonConfirmed\(choice\)\) \{/.test(commandBody),
    pin("the modal's answer is no longer read by core.skeletonConfirmed",
        "that ONLY the exact string `Replace` consents: a dismissal, an Escape and every near miss " +
        "are a decline, because this write destroys committed source"));
  assert.ok(!/choice ===/.test(commandBody) && !/choice !==/.test(commandBody),
    pin("the command compares the modal's answer by hand again", "the same"));
  assert.ok(/\{ modal: true \}/.test(commandBody),
    pin("the confirmation is no longer MODAL",
        "U3: a non-modal notification can be missed entirely, and the thing being destroyed is " +
        "committed source"));
  // **THE WHOLE `if`, WITH ITS CONDITION** -- MEASURED: `if (false) {` around
  // the modal block keeps every word of the two pins above, so the command
  // overwrote committed source with no question at all and 303 tests stayed
  // green. It is the neutered-guard class at the one place it matters most.
  assert.ok(/\n  if \(existing !== null\) \{\n    const question = core\.skeletonConfirmation\(paths\);/.test(commandBody),
    pin("the modal is guarded away, or is no longer asked for a file that EXISTS",
        "U3's whole sentence: a params file that is there is replaced only after a confirmation. " +
        "A file that is NOT there is a first pick — nothing to lose, so nothing to confirm"));
  // EACH IS THE WHOLE STATEMENT AND ITS CONSEQUENCE: `if (false && ...)`
  // keeps every word, and so does an `if` whose body has been emptied.
  assert.ok(/\n  if \(!still\.apply\) \{\n    log\([\s\S]{0,160}?return core\.skeletonCommandResult\(\{ abandoned: true \}\);/.test(commandBody),
    pin("the still-applies check is guarded away, or its answer no longer abandons",
        "that an answer given to the modal is not applied to a report the user has since left"));
  assert.ok(/\n  if \(!permitted\.render\) \{[\s\S]{0,200}?return core\.skeletonCommandResult\(\{ abandoned: true \}\);/.test(commandBody),
    pin("the consultation is asked and its answer discarded",
        "the neutered-guard class: a helper called and ignored is the mutation no pin that only " +
        "counts calls can see. This site can refuse nothing today (`explicit` is never refused), " +
        "and it is here so that a future caller with another trigger IS judged"));
  assert.ok(/\n  if \(!verdict\.run\) \{[\s\S]{0,320}?return core\.skeletonCommandResult\(\{ problem:/.test(commandBody),
    pin("the command's own verdict is asked and its answer discarded", "the same"));
  assert.ok(/\n    scheduleRender\(/.test(commandBody) &&
            /scheduleRender\([\s\S]{0,140}?core\.TRIGGER_EXPLICIT\);/.test(commandBody) &&
            (commandBody.match(/scheduleRender\(/g) || []).length === 1,
    pin("the command renders directly after writing, or schedules more than one render, or the " +
        "render it schedules no longer carries EXPLICIT",
        "M-4 and N-3: at most ONE render per coalescing window (the params watcher sees our write " +
        "too and merges), and consent stays consent — a `params-file` trigger here would answer an " +
        "explicit command with the held question"));
  assert.ok(/revealNextRender = true;/.test(commandBody),
    pin("the command no longer reveals the render tab", "that the user who asked for this sees the result"));

  // ---- ONE REGISTRATION, ONE DIRECT CALLER ------------------------------
  assert.strictEqual((src.match(/writeParamsSkeletonCommand\(/g) || []).length, 2,
    pin("writeParamsSkeletonCommand has more than its definition and the command registration",
        "that the ONLY way to reach the overwrite is a command the user ran: the palette, or the " +
        "orphan notification's BUTTON, which goes through executeCommand — the same door"));
  assert.ok(/registerCommand\(core\.SKELETON_COMMAND, \(\) => writeParamsSkeletonCommand\(context\)\)/.test(src),
    pin("the command is not registered under core.SKELETON_COMMAND", "the same"));
  assert.strictEqual((src.match(/writeSkeletonNow\(/g) || []).length, 2,
    pin("writeSkeletonNow has more than its definition and the command's one call", "the same"));
  assert.strictEqual((src.match(/openParamsDocument\(paths\.paramsPath, true\)/g) || []).length, 1,
    pin("the `always` open is used from more or fewer than one place",
        "U2 stays once-per-path for the automatic path; the user who explicitly asked for a rewrite " +
        "is shown the file every time"));
  // AND THE OTHER END OF IT -- MEASURED: dropping `&& always !== true` from
  // the function's own guard left the call site untouched, so the count
  // above still said 1 while the second run of the command showed nothing.
  const openS4 = src.slice(src.indexOf("async function openParamsDocument("),
                           src.indexOf("async function requestSchema("));
  // M-4 of the S4 review: the dedupe is `core.claimParamsDocument`, which
  // BOTH models call, so dropping `always` inside it is caught by behaviour;
  // this pin is only that the glue still goes through it with `always`.
  assert.ok(/async function openParamsDocument\(fsPath, always\) \{\s*if \(!core\.claimParamsDocument\(openedParamsFiles, fsPath, always\)\) return;/.test(openS4),
    pin("openParamsDocument ignores its `always` argument, or no longer takes one",
        "that running the command twice shows the file twice: 'once per path per session' is right " +
        "for a file that appears because a report was picked, and wrong for one the user has just " +
        "explicitly asked to be rewritten"));

  // ---- THE TOCTOU DECISION (2026-09-23): RE-READ AND REFUSE -------------
  // The bytes are re-read AFTER the schema answer and the symlink check and
  // BEFORE the write, and a replace over different bytes is REFUSED by name.
  // The decision is `core.skeletonBytesStillApply` (tested with the model);
  // this is that the glue still asks it, with a FRESH read, and obeys it.
  const schemaAt = writeBody.indexOf("await requestSchema(attempt)");
  const linkAt0 = writeBody.indexOf("await symlinkProblem(");
  const rereadAt = writeBody.indexOf(
    "core.skeletonBytesStillApply(replace, existing,\n" +
    "                                             replace === true ? await readTextIfPresent(paths.paramsPath) : null,");
  const obeyAt = writeBody.indexOf("if (!bytes.apply) return say(bytes.reason, bytes.message);");
  const applyAt = writeBody.indexOf("applyWritePlan(plan.files, paths.paramsPath, true)");
  assert.ok(schemaAt > 0 && linkAt0 > 0 && rereadAt > 0 && obeyAt > 0 && applyAt > 0 &&
            schemaAt < linkAt0 && linkAt0 < rereadAt && rereadAt < obeyAt && obeyAt < applyAt,
    pin("the command no longer re-reads the params file between the schema answer and the write, " +
        "or no longer refuses on what it finds",
        "the TOCTOU decision: MEASURED, a file saved while the schema request ran was destroyed; a " +
        "replace now goes ahead only over the bytes the modal was about"));
  // RE-REVIEW M-1 (2026-09-23): ORDER ALONE LET FOUR MUTANTS THROUGH 312/312
  // -- a post-modal read re-assigned into `existing` (V3/V3b: the wrong
  // baseline; MEASURED on a real disk, the edit made during the question was
  // destroyed), `bytes.apply = true` between ask and obey (V4), and the
  // decision `&& { apply: true }` (V6). The ask-and-obey is pinned as ONE
  // contiguous block, and the pre-modal read as the ONLY assignment.
  assert.ok(/\n  const bytes = core\.skeletonBytesStillApply\(replace, existing,\n\s+replace === true \? await readTextIfPresent\(paths\.paramsPath\) : null,\n\s+paths\.paramsPath\);\n  if \(!bytes\.apply\) return say\(bytes\.reason, bytes\.message\);\n/.test(writeBody),
    pin("the TOCTOU decision is no longer one contiguous ask-and-obey", "the same"));
  assert.ok(!/\bexisting\s*=(?!=)/.test(writeBody) &&
            (commandBody.match(/\bexisting\s*=(?!=)/g) || []).length === 1 &&
            /\n  const existing = await readTextIfPresent\(paths\.paramsPath\);\n/.test(commandBody),
    pin("the pre-modal read is re-assigned, so the TOCTOU compares against the wrong baseline", "the same"));
  // Re-review nit 1: V8 (`wedgeMark = null` in `say`), V11 (the command's
  // notice told `replace = false`) and V21 (`plan.listingLine = null`).
  assert.strictEqual((src.match(/\bwedgeMark\s*=(?!=)/g) || []).length, 2,
    pin("the wedge mark is assigned somewhere other than its declaration and applyGuard",
        "M-3: the hold changes only through the guard's reducer"));
  assert.ok(/const line = core\.skeletonWrittenNotice\(paths, plan, replace === true\);/.test(writeBody),
    pin("the command's notice no longer says `replaced` for a replace", "B23's channel line"));
  assert.ok(!/\bplan\.(listingLine|orphans)\s*=(?!=)/.test(scanBody),
    pin("the orphan scan overrides what core.orphanNoticePlan decided", "R24 by another route"));
  assert.ok(/async function writeSkeletonNow\(attempt, paths, replace, existing\) \{/.test(writeBody),
    pin("writeSkeletonNow no longer receives the bytes read before the modal", "the same"));

  // ---- NIT 3 (R24): the scan says what `core.orphanNoticePlan` decides -----
  assert.ok(/const plan = core\.orphanNoticePlan\(found, pick, orphanNotices, paths\.dir\);/.test(scanBody) &&
            /\n  if \(plan\.listingLine !== null\) log\("preview: " \+ plan\.listingLine\);/.test(scanBody) &&
            /for \(const \{ text \} of plan\.orphans\) \{\s*log\("preview: " \+ text\);/.test(scanBody),
    pin("the orphan scan no longer says what core.orphanNoticePlan decides",
        "D6: an unreadable params directory is SAID (R24 silenced it with every test green), and each " +
        "orphan is logged as well as notified"));

  // ---- M-3 AGAIN, AT THE THIRD WRITE PATH -------------------------------
  assert.ok(/\n  const linked = await symlinkProblem\(paths, \[paths\.gitignorePath, paths\.schemaPath, paths\.paramsPath\]\);/.test(writeBody),
    pin("the command's symlink check is gone, is no longer a statement of its own, or no longer " +
        "covers all three targets",
        "M-3: a params file symlinked outside the workspace would be written THROUGH by the one " +
        "write in this extension that does not go through the create"));
  assert.ok(/\n  if \(linked\) return say\(linked\.reason, linked\.message\);/.test(writeBody),
    pin("the command's symlink refusal is guarded away or no longer said", "the same (D-3's shape)"));
  const linkAt = writeBody.indexOf("await symlinkProblem(");
  const mkdirAt = writeBody.indexOf("await ensureDirectory(");
  assert.ok(linkAt > 0 && mkdirAt > linkAt,
    pin("the command creates the directory before it checks for symbolic links",
        "M-3: createDirectory would happily make the module directory inside a symlinked preview/"));

  // ---- D6: THE SCAN NEVER DELETES ---------------------------------------
  assert.ok(!/workspace\.fs\.delete/.test(src) && !/fs\.unlink/.test(src) && !/rmSync/.test(src),
    pin("the extension can delete a file",
        "D6, and it is the whole rule of the orphan notice: a params file is COMMITTED SOURCE, and " +
        "an extension that deletes one because a server answer did not mention it is one bad answer " +
        "away from losing work. It names the file; the rm is the developer's"));
  assert.strictEqual((src.match(/noticeOrphanParamsFiles\(/g) || []).length, 3,
    pin("the orphan scan has more or fewer than its definition and its two call sites",
        "that it runs exactly where an `ermine/preview/reports` answer is ALREADY in hand — the " +
        "picker and `refreshModule` — so it costs one readDirectory and no server request"));
  assert.ok(/noticeOrphanParamsFiles\(picked, listed\)/.test(src) &&
            /noticeOrphanParamsFiles\(picked, answer\)/.test(src),
    pin("the orphan scan is handed something other than the answer that named the module", "the same"));
  assert.ok(/if \(!pick \|\| !pick\.module\) return;/.test(scanBody) && /if \(paths\.problem\) return;/.test(scanBody),
    pin("the orphan scan runs for a pick that can have no params file at all",
        "S4 item 4: a pick with no module, an operator binding and an unsafe module name have no " +
        "params DIRECTORY, so there is nothing to compare and nothing to call stale"));
  assert.ok(/core\.orphanParamsFiles\(listing, listed && listed\.reports, paths\)/.test(scanBody),
    pin("the orphan scan compares against something other than the server's own reports list",
        "D6: `reports` that is absent or empty means the server could not list the file — which must " +
        "call NOTHING stale, not everything"));
  assert.ok(/core\.directoryListing\(\{ entries \}\)/.test(scanBody) &&
            /core\.directoryListing\(\{ missing: true \}\)/.test(scanBody) &&
            /core\.directoryListing\(\{ problem:/.test(scanBody),
    pin("the directory listing reaches the decision without going through its builder, or one of " +
        "its three arms is gone",
        "M-1's class, closed before the defect rather than after it: `missing` (no directory yet) " +
        "and `problem` (there IS one and we could not read it) are different answers, and the " +
        "second must not read as `nothing is stale`"));
  assert.strictEqual((src.match(/executeCommand\(core\.SKELETON_COMMAND\)/g) || []).length, 1,
    pin("the orphan notification's button runs something other than the command, or runs it from " +
        "more than one place",
        "that the button is a CLICK, and that it goes through the palette's own door rather than " +
        "calling the handler — which is what keeps the handler with one direct caller"));
  assert.ok(/if \(choice !== core\.ORPHAN_BUTTON\) return;/.test(scanBody),
    pin("a dismissed orphan notification can run the command",
        "that nothing automatic reaches the one thing that overwrites committed source"));

  // ---- THE NOTICES ARE PER SESSION, NOT PER PICK ------------------------
  for (const [what, needle, until] of [
    ["forgetting the schema attempts", "function forgetSchemaAttempts(", "function schemaNoticeOnce("],
    ["forgetting the params notices", "function forgetParamsNotices(", "async function readParamsFile("],
    ["a pick change", "async function pickReport(", "async function renderCommand("],
    ["learning the module name", "async function refreshModule(", "function installWatcher("],
  ]) {
    const start = src.indexOf(needle);
    assert.ok(start > 0 && src.slice(start, src.indexOf(until, start)).indexOf("orphanNotices") < 0,
      pin(what + " now clears the orphan notices",
          "D6: ONE notice per (module, binding) per SESSION. The same stale file is found again from " +
          "every binding in that module, so clearing on a pick change would be a notification per pick"));
  }
  const disposeBody = src.slice(src.indexOf("function disposePreview("), src.indexOf("function restorePick("));
  assert.ok(/orphanNotices = new Set\(\);/.test(disposeBody),
    pin("the orphan notices outlive the window", "the same: they die with the session and nowhere else"));
});

// ===========================================================================
// WP-10 S1: THE PANEL'S PURE HALF -- `panelMessagesFor`, its shared view
// builder, and the host page's HTML.  NOTHING OF IT IS WIRED: `extension.js`
// creates no panel yet (S2).  The builders the glue will call are the ones
// called here (`panelAnswerStep`, `panelView`, `unsavedNames`), per the rule at
// the head of this file; no test below hand-writes a view object.
//
// The cross-language half -- these messages folded through the REAL
// `client/src/host/index.ts` reducer, and H7's snapshot-equals-incremental
// property over generated extension histories -- is `client/test/page.test.ts`,
// because the reducer is TypeScript and this suite needs no build.
// ===========================================================================

const PANEL_ANSWERS = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "panel-answers.json"), "utf8"));
const PANEL_PICK = core.makePick("file:///w/doc/WpSpin.e", "/w/doc/WpSpin.e", "report", "WpSpin", []);

/** The panel view after a list of render outcomes, through the SHARED
 *  builders, with the extension's generation advanced as `renderNow` does. */
function panelAfter(outcomes, extra) {
  let answers = core.initialPanelAnswers();
  let current = 0;
  for (const o of outcomes) {
    current = Math.max(current, o.current || 0);
    answers = core.panelAnswerStep(answers, o.outcome, current);
  }
  return core.panelView(Object.assign({ answers }, extra || {}));
}
const kinds = (msgs) => msgs.map((m) => m.kind);
const captured = (name) => PANEL_ANSWERS.cases[name];
const answerOutcome = (name) => ({ current: captured(name).request.generation, outcome: { answer: captured(name).answer } });

test("panel (csp): the policy is EXACTLY the design review's one line, character for character", () => {
  const src = "https://file+.vscode-resource.vscode-cdn.net";
  assert.strictEqual(core.previewCsp(src),
    "default-src 'none'; script-src https://file+.vscode-resource.vscode-cdn.net 'unsafe-eval'; " +
    "style-src https://file+.vscode-resource.vscode-cdn.net 'unsafe-inline'; " +
    "img-src https://file+.vscode-resource.vscode-cdn.net data:;");
  const html = core.buildPreviewHtml({ cspSource: src, client: "c.js", host: "h.js" });
  const metas = html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]*)">/g) || [];
  assert.strictEqual(metas.length, 1, "exactly one CSP meta");
  assert.ok(html.indexOf('<meta http-equiv="Content-Security-Policy" content="' + core.previewCsp(src) + '">') > 0);
  // no nonce (W3), no blob: (U5), no font-src / connect-src (F2, F3), one line
  for (const absent of ["nonce", "blob:", "font-src", "connect-src", "\n"]) {
    assert.ok(core.previewCsp(src).indexOf(absent) < 0, absent + " is not in the policy");
  }
});

test("panel (csp): a cspSource that would change the policy is REFUSED, never escaped into it", () => {
  // `a 'unsafe-inline'` left this list in 0.1.15 (F1): a quoted keyword is a
  // CSP source expression, passed through verbatim like VS Code's own 'self'.
  for (const bad of ["", "  ", "a; script-src *", 'a"', "a\nb", undefined, 7]) {
    assert.throws(() => core.buildPreviewHtml({ cspSource: bad, client: "c.js", host: "h.js" }),
      /buildPreviewHtml: cspSource/, "cspSource " + JSON.stringify(bad));
  }
});

// PLAYTEST F1 (2026-09-23): VS Code's REAL webview.cspSource, MEASURED by the
// user in a real VS Code. The 0.1.14 guard refused it, so every panel render
// showed "the preview page could not be built". Every test before this one
// used a single bare token.
const REAL_VSCODE_CSP_SOURCE = "'self' https://*.vscode-cdn.net";

test("panel (csp) F1: VS Code's REAL cspSource `'self' https://*.vscode-cdn.net` is ACCEPTED and the page's CSP is pinned exactly", () => {
  const html = core.buildPreviewHtml({ cspSource: REAL_VSCODE_CSP_SOURCE, client: "c.js", host: "h.js" });
  const expected =
    "default-src 'none'; script-src 'self' https://*.vscode-cdn.net 'unsafe-eval'; " +
    "style-src 'self' https://*.vscode-cdn.net 'unsafe-inline'; " +
    "img-src 'self' https://*.vscode-cdn.net data:;";
  assert.strictEqual(core.previewCsp(REAL_VSCODE_CSP_SOURCE), expected);
  assert.strictEqual(html, [
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta http-equiv="Content-Security-Policy" content="' + expected + '">',
    "<title>Ermine preview</title>",
    "</head>",
    "<body>",
    '<div id="' + core.PREVIEW_ROOT_ID + '"></div>',
    '<script src="c.js"></script>',
    '<script src="h.js"></script>',
    "</body>",
    "</html>",
    "",
  ].join("\n"));
});

test("panel (csp) F1 table: each token must be ONE CSP source expression -- accepted rows build, refused rows are named by token", () => {
  const accepted = [
    REAL_VSCODE_CSP_SOURCE,
    "vscode-webview-resource: https:",
    "'self'",
    "https://example.com:8443/assets/web/",
    "*.example.com:* http://localhost:3000/x",
    "https://file+.vscode-resource.vscode-cdn.net",
    "'self'\thttps://*.vscode-cdn.net",
    "'self'  https://*.vscode-cdn.net",
    "'self' \t \thttps://*.vscode-cdn.net",
    "*",
  ];
  for (const src of accepted) {
    const html = core.buildPreviewHtml({ cspSource: src, client: "c.js", host: "h.js" });
    assert.ok(html.indexOf('content="' + core.previewCsp(src) + '"') > 0, "accepted verbatim: " + JSON.stringify(src));
  }
  const refused = [
    ["'self'; script-src *", "'self';"],
    ["a b;", "b;"],
    ["self", "self"],
    ["'self' <x>", "<x>"],
    ["'self'\nhttps://x", "'self'\nhttps://x"],
    ["", null],
    ['"quoted"', '"quoted"'],
    ["'self' https://a,https://b", "https://a,https://b"],
    ["';'", "';'"],
    ["'self' https://a;b", "https://a;b"],
    ["https://a/p;q", "https://a/p;q"],
    ["https://a/&quot;", "https://a/&quot;"],
    ["https://a\\b", "https://a\\b"],
    ["https://a/&amp", "https://a/&amp"],
    ["https://a/\\b", "https://a/\\b"],
    ["'self'\n", "'self'\n"],
    ["\v'self'", "\v'self'"],
    ["'self' https://x\u00a0", "https://x\u00a0"],
    ["'self'\u2028", "'self'\u2028"],
  ];
  for (const [src, token] of refused) {
    assert.throws(() => core.buildPreviewHtml({ cspSource: src, client: "c.js", host: "h.js" }),
      (err) => /^buildPreviewHtml: cspSource/.test(err.message) &&
        (token === null || err.message.indexOf("the token " + JSON.stringify(token) + " ") >= 0),
      "refused by name: " + JSON.stringify(src));
  }
});

test("panel (csp) F1 glue: setPanelHtml passes webview.cspSource UNTOUCHED, and a build failure still becomes the notice page", () => {
  const fsMod = require("node:fs");
  const ext = fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  assert.ok(/core\.previewPageUris\(panel\.webview\.cspSource, bundle, writers, uriOf\)/.test(ext), "cspSource passed verbatim");
  assert.strictEqual((ext.match(/cspSource/g) || []).length, 1, "extension.js touches cspSource exactly once");
  assert.strictEqual(core.previewPageUris(REAL_VSCODE_CSP_SOURCE, { ok: true, dir: "/b" }, null, (d, f) => d + "/" + f).cspSource,
    REAL_VSCODE_CSP_SOURCE);
  let message = null;
  try { core.buildPreviewHtml({ cspSource: "self", client: "c.js", host: "h.js" }); } catch (err) { message = err.message; }
  assert.ok(message && /^buildPreviewHtml: cspSource/.test(message));
  const notice = core.buildPanelNoticeHtml({ title: "The preview page could not be built", message });
  assert.ok(notice.indexOf("The preview page could not be built") >= 0, "the notice names the failure");
  assert.ok(notice.indexOf("buildPreviewHtml: cspSource") >= 0, "the notice carries the message");
  // extension.js's own catch: a page-build throw becomes THIS notice page
  assert.ok(/catch \(err\) \{\s*const message = err && err\.message \? err\.message : String\(err\);\s*log\(`preview: BUG -- the panel page could not be built: \$\{message\}`\);\s*panel\.webview\.html = core\.buildPanelNoticeHtml\(\{ title: "The preview page could not be built", message \}\);/.test(ext),
    "extension.js setPanelHtml's catch shows the notice page on a build failure");
});

test("panel (csp) F1 round 2: the TRIMMED value is both checked and emitted -- surrounding spaces/tabs never reach the policy", () => {
  const html = core.buildPreviewHtml({ cspSource: " \t" + REAL_VSCODE_CSP_SOURCE + "\t ", client: "c.js", host: "h.js" });
  assert.ok(html.indexOf('content="' + core.previewCsp(REAL_VSCODE_CSP_SOURCE) + '"') > 0, "the emitted CSP is the trimmed value");
  // a control or non-ASCII character is refused by its own name, before the arms run
  for (const [src, token] of [["'self'\n", "'self'\n"], ["\v'self'", "\v'self'"], ["'self' https://x\u00a0", "https://x\u00a0"], ["'self'\u2028", "'self'\u2028"]]) {
    assert.throws(() => core.buildPreviewHtml({ cspSource: src, client: "c.js", host: "h.js" }),
      (err) => err.message === "buildPreviewHtml: cspSource " + JSON.stringify(src) + ": the token " + JSON.stringify(token) +
        " holds a control or non-ASCII character",
      "refused as a control/non-ASCII token: " + JSON.stringify(src));
  }
});

test("panel (html): scripts load writers -> client -> host, classic, stamped, and NO inline script body", () => {
  const html = core.buildPreviewHtml(
    { cspSource: "vscode-src", writers: "w/htmlwriter.js", client: "b/ermine-client.js", host: "b/ermine-host.js" },
    { stamp: 1234 });
  const tags = html.match(/<script\b[^>]*>[\s\S]*?<\/script>/g) || [];
  assert.deepStrictEqual(tags, [
    '<script src="w/htmlwriter.js"></script>',
    '<script src="b/ermine-client.js?v=1234"></script>',
    '<script src="b/ermine-host.js?v=1234"></script>',
  ]);
  assert.strictEqual((html.match(/<script/g) || []).length, 3, "no <script> the tag list missed");
  const inlineBodies = tags.filter((t) => !/^<script src="[^"]+"><\/script>$/.test(t));
  assert.strictEqual(inlineBodies.length, 0, "W3: zero inline script bodies");
  for (const attr of ["defer", "async", "type=", "nonce"]) assert.ok(html.indexOf(attr) < 0, attr);
  assert.ok(html.indexOf('<div id="' + core.PREVIEW_ROOT_ID + '"></div>') > 0, "the root element");
  assert.ok(html.indexOf("<div id") < html.indexOf("<script"), "the root exists before any script runs");
  // the writers slot is optional in S1, and the order holds without it
  const bare = core.buildPreviewHtml({ cspSource: "vscode-src", client: "c.js", host: "h.js" });
  assert.deepStrictEqual(bare.match(/<script\b[^>]*>/g), ['<script src="c.js">', '<script src="h.js">']);
  // a URI that already has a query keeps it
  assert.ok(core.buildPreviewHtml({ cspSource: "s", client: "c.js?x=1", host: "h.js" }, { stamp: "a b" })
    .indexOf('src="c.js?x=1&amp;v=a%20b"') > 0);
});

test("panel (html): the writers' CSS links are optional, in order, and at most three", () => {
  const html = core.buildPreviewHtml({ cspSource: "s", client: "c.js", host: "h.js",
    styles: ["web/common.css", "web/htmlwriter.css", "web/htmlwriter_classic.css"] });
  assert.deepStrictEqual(html.match(/<link [^>]*>/g), [
    '<link rel="stylesheet" href="web/common.css">',
    '<link rel="stylesheet" href="web/htmlwriter.css">',
    '<link rel="stylesheet" href="web/htmlwriter_classic.css">',
  ]);
  assert.strictEqual((core.buildPreviewHtml({ cspSource: "s", client: "c.js", host: "h.js" }).match(/<link/g) || []).length, 0);
  assert.throws(() => core.buildPreviewHtml({ cspSource: "s", client: "c.js", host: "h.js", styles: ["a", "b", "c", "d"] }), /styles/);
  assert.throws(() => core.buildPreviewHtml({ cspSource: "s", client: "c.js" }), /host script URI is missing/);
  assert.throws(() => core.buildPreviewHtml({ cspSource: "s", host: "h.js" }), /client script URI is missing/);
});

test("panel (html): every URI is HTML-escaped, so a hostile path cannot add a tag", () => {
  const evil = 'x"><script>alert(1)</script><x a="';
  const html = core.buildPreviewHtml({ cspSource: "s", client: evil, host: "h.js", writers: evil, styles: [evil] });
  assert.strictEqual((html.match(/<script/g) || []).length, 3);
  assert.ok(html.indexOf("alert(1)</script>") < 0);
  assert.ok(html.indexOf("&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;") > 0);
  assert.strictEqual((html.match(/<link/g) || []).length, 1);
});

test("panel (target): U1's contract -- panel | json | both, default panel, anything else refused AND named", () => {
  assert.deepStrictEqual(core.PANEL_TARGETS, ["panel", "json", "both"]);
  assert.deepStrictEqual(core.panelTarget(undefined), { target: "panel", problem: null });
  assert.deepStrictEqual(core.panelTarget("json"), { target: "json", problem: null });
  assert.deepStrictEqual(core.panelTarget("both"), { target: "both", problem: null });
  const bad = core.panelTarget("tab");
  assert.strictEqual(bad.target, "panel");
  assert.match(bad.problem, /"tab"/);
  assert.match(core.panelTarget(3).problem, /a number/);
  // WP-10 S5 review nit 4: the article follows the type name.
  assert.strictEqual(core.panelTarget([]).problem,
    'ermine.preview.target is one of "panel", "json" or "both", not an array; the preview uses "panel"');
});

test("panel (kinds): the kind list is the host reducer's nine, in its order", () => {
  const hostSrc = fs.readFileSync(path.join(__dirname, "..", "..", "..", "client", "src", "host", "index.ts"), "utf8");
  const block = hostSrc.slice(hostSrc.indexOf("export const MESSAGE_KINDS = ["), hostSrc.indexOf("] as const;"));
  assert.deepStrictEqual(core.PANEL_MESSAGE_KINDS, (block.match(/"([A-Za-z]+)"/g) || []).map((s) => s.slice(1, -1)));
});

test("panel (table): each of the nine kinds is produced by at least one view built by the shared builder", () => {
  const good = { current: 1, outcome: { answer: captured("ok-wpint").answer } };
  const stuck = core.stuckReduce(core.initialStuckState(),
    { type: "notification", stuck: true, message: "evaluation did not finish", seq: 3 }).state;
  const offline = core.stuckReduce(core.initialStuckState(), { type: "clientState", to: "Stopped" }).state;
  const mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PANEL_PICK, at: 1 }).mark;
  const table = [
    ["render", panelAfter([good])],
    ["error", panelAfter([good, answerOutcome("error-400-wpint")])],
    ["stale", panelAfter([good], { pending: true })],
    ["stuck", panelAfter([], { stuckState: stuck })],
    ["held", panelAfter([], { mark, pick: PANEL_PICK })],
    ["offline", panelAfter([], { stuckState: offline })],
    ["switching", panelAfter([], { switching: "prod" })],
    ["unsaved", panelAfter([], { unsaved: core.unsavedNames([{ fileName: "/w/Chart.e", isDirty: true, languageId: "ermine" }]) })],
    ["reloadBundle", panelAfter([good], { reloading: true })],
  ];
  assert.deepStrictEqual(table.map((r) => r[0]), core.PANEL_MESSAGE_KINDS.slice());
  const on = {
    render: (m) => m.document !== undefined,
    error: (m) => m.status === 400,
    stale: (m) => m.stale === true,
    stuck: (m) => m.stuck === true && m.seq === 3 && m.message === "evaluation did not finish",
    held: (m) => m.held === true && /WpSpin\.report wedged/.test(m.message),
    offline: (m) => m.offline === true,
    switching: (m) => m.to === "prod",
    unsaved: (m) => m.names.length === 1 && m.names[0] === "Chart.e",
    reloadBundle: () => true,
  };
  for (const [kind, view] of table) {
    const msgs = core.panelMessagesFor(view);
    const hit = msgs.filter((m) => m.kind === kind);
    assert.strictEqual(hit.length, 1, kind + " appears exactly once");
    assert.ok(on[kind](hit[0]), kind + " carries its RAISED value: " + JSON.stringify(hit[0]));
  }
});

test("panel (snapshot): every slice is sent on BOTH edges, in the order the reducer needs", () => {
  // H7: the resync must overwrite a panel that missed any post, so the six
  // latch slices are always present -- lowered as well as raised.
  const idle = core.panelMessagesFor(core.panelView({}));
  assert.deepStrictEqual(idle, [
    { kind: "stale", stale: false },
    { kind: "stuck", stuck: false },
    { kind: "held", held: false },
    { kind: "offline", offline: false },
    { kind: "switching", to: null },
    { kind: "unsaved", names: [] },
  ]);
  const busy = core.panelMessagesFor(panelAfter(
    [{ current: 1, outcome: { answer: captured("ok-wpint").answer } }, answerOutcome("error-400-wpint")],
    { reloading: true, pending: true }));
  assert.deepStrictEqual(kinds(busy),
    ["render", "error", "stale", "stuck", "held", "offline", "switching", "unsaved", "reloadBundle"]);
  // `held` carries NO button (U4, WP-22), and nothing else names an action
  for (const m of busy) assert.ok(!("action" in m), m.kind + " carries no action");
  const held = core.panelMessagesFor(core.panelView({
    mark: core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PANEL_PICK, at: 1 }).mark,
    pick: PANEL_PICK })).find((m) => m.kind === "held");
  assert.deepStrictEqual(Object.keys(held).sort(), ["held", "kind", "message"]);
});

test("panel (displaced): a displaced render produces NOTHING -- the answers are returned by identity", () => {
  const before = core.panelAnswerStep(core.initialPanelAnswers(), { answer: captured("burst-0").answer }, 8);
  const rej = captured("burst-1").rejection;
  assert.strictEqual(rej.code, -32800, "the captured rejection is the server's own displacement");
  const after = core.panelAnswerStep(before, { rejection: rej, generation: 9 }, 9);
  assert.strictEqual(after, before, "displaced: nothing changes");
  assert.deepStrictEqual(core.panelMessagesFor(core.panelView({ answers: after })),
                         core.panelMessagesFor(core.panelView({ answers: before })));
  // the vscode-languageclient shape (code under `data`) is displaced too
  assert.strictEqual(core.panelAnswerStep(before, { rejection: { data: { code: -32800 } }, generation: 9 }, 9), before);
  // and any OTHER rejection is dressed by errorAnswer and shown
  const lost = core.panelAnswerStep(before, { rejection: new Error("connection got disposed"), generation: 9 }, 9);
  const err = core.panelMessagesFor(core.panelView({ answers: lost })).find((m) => m.kind === "error");
  assert.deepStrictEqual(err, { kind: "error", status: 0, message: "connection got disposed", path: null, reason: null });
});

test("panel (generation): an answer behind the current generation is discarded, a newer one is shown", () => {
  // REAL: burst-2 (generation 10) answered; burst-0 (generation 8) arriving
  // after it, while the extension is at 10, must change nothing.
  const at10 = core.panelAnswerStep(core.initialPanelAnswers(), { answer: captured("burst-2").answer }, 10);
  assert.strictEqual(core.panelAnswerStep(at10, { answer: captured("burst-0").answer }, 10), at10);
  const msgs = core.panelMessagesFor(core.panelView({ answers: at10 }));
  assert.deepStrictEqual(msgs[0], { kind: "render", document: captured("burst-2").answer.document, generation: 10 });
  // a generation that is not a number is ACCEPTED (isCurrentGeneration's rule)
  const nullGen = core.panelAnswerStep(at10, { answer: { ok: false, status: 400, message: "m", generation: null } }, 10);
  assert.notStrictEqual(nullGen, at10);
});

test("panel (answers): an error keeps the last GOOD document, which the snapshot re-sends below it", () => {
  const v = panelAfter([answerOutcome("ok-sales"), answerOutcome("error-500-wpempty")]);
  const msgs = core.panelMessagesFor(v);
  assert.deepStrictEqual(kinds(msgs).slice(0, 2), ["render", "error"]);
  assert.deepStrictEqual(msgs[0].document, captured("ok-sales").answer.document);
  assert.strictEqual(msgs[0].generation, 2);
  assert.strictEqual(msgs[1].status, 500);
  // an error with nothing ever rendered sends no render
  assert.deepStrictEqual(kinds(core.panelMessagesFor(panelAfter([answerOutcome("error-404-binding")]))).slice(0, 1), ["error"]);
});

test("panel (stale): from the answer's OWN key, or while a render is pending -- and after the answer pair", () => {
  const staleAnswer = Object.assign({}, captured("ok-wpint").answer, { stale: true });
  const v = panelAfter([{ current: 1, outcome: { answer: staleAnswer } }]);
  const msgs = core.panelMessagesFor(v);
  assert.deepStrictEqual(msgs.slice(0, 2).map((m) => [m.kind, m.stale]), [["render", undefined], ["stale", true]]);
  assert.strictEqual(core.panelMessagesFor(panelAfter([answerOutcome("ok-wpint")])).find((m) => m.kind === "stale").stale, false);
});

test("panel (fast mode): W5 -- the sentence is composed into `error`, never a tenth kind", () => {
  const v = panelAfter([answerOutcome("error-400-sales-key")], { fastMode: true });
  const err = core.panelMessagesFor(v).find((m) => m.kind === "error");
  assert.strictEqual(err.message, 'the key "fromDy" is not allowed here' + core.FAST_MODE_SUFFIX);
  assert.strictEqual(err.path, "$.params.fromDy");
  assert.match(core.FAST_MODE_SUFFIX, /fast mode is on: type errors are not shown in Problems/);
  // a blank message still says something before the suffix
  const blank = core.panelMessagesFor(panelAfter([{ current: 1, outcome: { answer: { ok: false, status: 500, message: " ", generation: 1 } } }],
    { fastMode: true })).find((m) => m.kind === "error");
  assert.strictEqual(blank.message, "the render failed" + core.FAST_MODE_SUFFIX);
  // off: the message is the server's, verbatim
  assert.strictEqual(core.panelMessagesFor(panelAfter([answerOutcome("error-400-sales-key")])).find((m) => m.kind === "error").message,
    'the key "fromDy" is not allowed here');
  assert.ok(core.panelMessagesFor(panelAfter([answerOutcome("ok-wpint")], { fastMode: true })).every((m) => m.kind !== "error"));
});

test("panel (stuck): from the ARBITRATED stuck state, never from the answer's own key (D10, rule 3)", () => {
  const ans = captured("stuck-wpspin").answer;
  assert.strictEqual(ans.stuck, true);
  // rule (3) APPLIES the marker: no notification since the send
  const applied = core.stuckReduce(core.initialStuckState(),
    { type: "answer", stuck: true, message: ans.message, seqAtSend: 0 }).state;
  const v = panelAfter([answerOutcome("stuck-wpspin")], { stuckState: applied });
  const msgs = core.panelMessagesFor(v);
  assert.deepStrictEqual(msgs.find((m) => m.kind === "stuck"), { kind: "stuck", stuck: true, message: ans.message });
  assert.strictEqual(msgs.find((m) => m.kind === "error").status, 500);
  // rule (3) REFUSES it (a clear arrived after the send): the SAME answer raises no banner
  const cleared = core.stuckReduce(core.initialStuckState(), { type: "notification", stuck: false, seq: 5 }).state;
  const refused = core.stuckReduce(cleared, { type: "answer", stuck: true, message: ans.message, seqAtSend: 0 }).state;
  assert.deepStrictEqual(core.panelMessagesFor(panelAfter([answerOutcome("stuck-wpspin")], { stuckState: refused }))
    .find((m) => m.kind === "stuck"), { kind: "stuck", stuck: false });
  // the captured notification carries the seq through
  const note = PANEL_ANSWERS.notifications.find((n) => n.method === "ermine/preview/stuck").params;
  const noted = core.stuckReduce(core.initialStuckState(), Object.assign({ type: "notification" }, note)).state;
  assert.strictEqual(core.panelMessagesFor(core.panelView({ stuckState: noted })).find((m) => m.kind === "stuck").seq, note.seq);
});

test("panel (held): H6 -- only the guard's own clears lower it; a restart (offline -> running) does not", () => {
  const mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PANEL_PICK, at: 1 }).mark;
  const heldOf = (extra) => core.panelMessagesFor(core.panelView(Object.assign({ mark, pick: PANEL_PICK }, extra)))
    .find((m) => m.kind === "held");
  assert.strictEqual(heldOf({}).held, true);
  assert.strictEqual(heldOf({ restartedByUs: true }).message, core.heldMessage(mark, PANEL_PICK, true));
  const running = core.stuckReduce(core.stuckReduce(core.initialStuckState(), { type: "clientState", to: "Stopped" }).state,
    { type: "clientState", to: "Running" }).state;
  assert.strictEqual(heldOf({ stuckState: running }).held, true, "a bare Stopped -> Running keeps it");
  const recovered = core.guardReduce(mark, { type: "notification", stuck: false, pick: PANEL_PICK });
  assert.strictEqual(recovered.effects.cleared, true);
  assert.strictEqual(heldOf({ mark: recovered.mark }).held, false, "a {stuck:false} recovery lowers it");
  // a mark for ANOTHER pick is never spoken about (markMatches)
  const other = core.makePick("file:///w/doc/WpInt.e", "/w/doc/WpInt.e", "report", "WpInt", []);
  assert.strictEqual(heldOf({ pick: other }).held, false);
});

test("panel (unsaved): dirty Ermine documents by base name, sorted, de-duplicated, nothing else", () => {
  assert.deepStrictEqual(core.unsavedNames([
    { fileName: "/w/b/Sales.e", isDirty: true, languageId: "ermine" },
    { fileName: "/w/a/Chart.e", isDirty: true, languageId: "ermine" },
    { fileName: "/w/c/Sales.e", isDirty: true, languageId: "ermine" },
    { fileName: "/w/Clean.e", isDirty: false, languageId: "ermine" },
    { fileName: "/w/p.params.json", isDirty: true, languageId: "json" },
    null, { isDirty: true, languageId: "ermine" },
  ]), ["Chart.e", "Sales.e"]);
  assert.deepStrictEqual(core.unsavedNames(undefined), []);
});

test("panel (switching): W6 -- NOT WIRED, so a view built with no producer always lowers it", () => {
  const sw = (parts) => core.panelMessagesFor(core.panelView(parts)).find((m) => m.kind === "switching");
  assert.deepStrictEqual(sw({}), { kind: "switching", to: null });
  assert.deepStrictEqual(sw({ switching: "  " }), { kind: "switching", to: null });
});

test("panel (real answers): every captured answer from a real bin/ermine-lsp maps to the message stream it should", () => {
  // `test/fixtures/panel-answers.json`: CAPTURED, one boot, no editor -- its
  // `_note` says how.  Each case is fed through the shared builders exactly as
  // S2's glue will: outcome -> panelAnswerStep -> panelView -> panelMessagesFor.
  const expect = {
    "ok-wpint":            { first: "render" },
    "ok-sales":            { first: "render" },
    "burst-0":             { first: "render" },
    "burst-2":             { first: "render" },
    "error-400-wpint":     { first: "error", status: 400, path: "$.params" },
    "error-400-sales-key": { first: "error", status: 400, path: "$.params.fromDy" },
    "error-404-binding":   { first: "error", status: 404, reason: null },
    "error-404-placement": { first: "error", status: 404, reason: "unreadable" },
    "error-500-wpempty":   { first: "error", status: 500, path: "$.props" },
    "stuck-wpspin":        { first: "error", status: 500, stuck: true },
    "while-stuck-wpint":   { first: "error", status: 500, stuck: true },
    "while-stuck-wpchain": { first: "error", status: 500, stuck: true },
    "while-stuck-wpblow":  { first: "error", status: 500, stuck: true },
    "burst-1":             { none: true },
  };
  assert.deepStrictEqual(Object.keys(expect).sort(), Object.keys(PANEL_ANSWERS.cases).sort(), "every capture has a row");
  for (const [name, want] of Object.entries(expect)) {
    const c = PANEL_ANSWERS.cases[name];
    const gen = c.request.generation;
    const outcome = c.rejection ? { rejection: c.rejection, generation: gen } : { answer: c.answer };
    const answers = core.panelAnswerStep(core.initialPanelAnswers(), outcome, gen);
    // the glue feeds a stuck-marked answer to stuckReduce; the view takes that state
    const stuckState = core.stuckReduce(core.initialStuckState(),
      { type: "answer", stuck: !!(c.answer && c.answer.stuck === true), message: c.answer && c.answer.message, seqAtSend: 0 }).state;
    const msgs = core.panelMessagesFor(core.panelView({ answers, stuckState }));
    if (want.none) {
      assert.strictEqual(answers, core.panelAnswerStep(answers, outcome, gen), name);
      assert.ok(msgs.every((m) => m.kind !== "render" && m.kind !== "error"), name + ": displaced shows nothing");
      continue;
    }
    assert.strictEqual(msgs[0].kind, want.first, name);
    if (want.first === "render") {
      assert.deepStrictEqual(msgs[0].document, c.answer.document, name);
      assert.strictEqual(msgs[0].generation, gen, name);
    } else {
      assert.strictEqual(msgs[0].status, want.status, name);
      assert.strictEqual(msgs[0].message, c.answer.message, name);
      if ("path" in want) assert.strictEqual(msgs[0].path, want.path, name);
      if ("reason" in want) assert.strictEqual(msgs[0].reason, want.reason, name);
    }
    assert.strictEqual(msgs.find((m) => m.kind === "stuck").stuck, want.stuck === true, name + ": stuck");
    // and a real answer at an OLDER generation than the extension's changes nothing
    const later = core.panelAnswerStep(core.initialPanelAnswers(), outcome, gen + 1);
    if (!c.rejection) assert.deepStrictEqual(later, core.initialPanelAnswers(), name + ": discarded when behind");
  }
});

test("panel (explorer): over generated views, the stream's shape never breaks", () => {
  // A small seeded explorer (no fast-check here: this suite needs no
  // node_modules).  Draws every input `panelView` reads from the real
  // reducers and the captured answers, and checks the invariants S2 relies on.
  // The xorshift (`wp8Rnd`), NOT the LCG: WP-27 measured the LCG's `% 2` as
  // 1992 zeros in 2000, and half the draws below are `% 2`.
  const rnd = wp8Rnd(20260923);
  const names = Object.keys(PANEL_ANSWERS.cases);
  const mark = core.guardReduce(null, { type: "answer", stuck: true, applies: true, pick: PANEL_PICK, at: 1 }).mark;
  const stuckEvents = [
    { type: "notification", stuck: true, message: "m", seq: 1 }, { type: "notification", stuck: false, seq: 2 },
    { type: "clientState", to: "Stopped" }, { type: "clientState", to: "Running" },
  ];
  for (let run = 0; run < 3000; run++) {
    let answers = core.initialPanelAnswers();
    let current = 0;
    let stuckState = core.initialStuckState();
    for (let i = rnd(6); i > 0; i--) {
      const c = PANEL_ANSWERS.cases[names[rnd(names.length)]];
      current = Math.max(current, rnd(12));
      const outcome = c.rejection ? { rejection: c.rejection, generation: c.request.generation } : { answer: c.answer };
      answers = core.panelAnswerStep(answers, outcome, current);
      stuckState = core.stuckReduce(stuckState, stuckEvents[rnd(stuckEvents.length)]).state;
    }
    const view = core.panelView({
      answers, stuckState, mark: rnd(2) ? mark : null, pick: PANEL_PICK, pending: !!rnd(2),
      unsaved: rnd(2) ? ["A.e"] : [], fastMode: !!rnd(2), reloading: rnd(4) === 0,
    });
    const msgs = core.panelMessagesFor(view);
    const ks = kinds(msgs);
    for (const k of ks) assert.ok(core.PANEL_MESSAGE_KINDS.indexOf(k) >= 0, k);
    for (const k of ["stale", "stuck", "held", "offline", "switching", "unsaved"]) {
      assert.strictEqual(ks.filter((x) => x === k).length, 1, k + " exactly once");
    }
    assert.strictEqual(ks.indexOf("render") >= 0, view.document !== null);
    assert.strictEqual(ks.indexOf("error") >= 0, view.answer !== null && !core.isOk(view.answer));
    if (ks.indexOf("render") >= 0) assert.strictEqual(ks.indexOf("render"), 0);
    if (ks.indexOf("error") >= 0) assert.ok(ks.indexOf("error") < ks.indexOf("stale"));
    assert.strictEqual(ks.indexOf("reloadBundle") >= 0, view.reloading);
    if (view.reloading) assert.strictEqual(ks[ks.length - 1], "reloadBundle");
    assert.ok(msgs.every((m) => !("action" in m)));
    assert.strictEqual(msgs.find((m) => m.kind === "offline").offline, stuckState.running === false);
    assert.strictEqual(msgs.find((m) => m.kind === "stuck").stuck, stuckState.stuck === true);
    assert.doesNotThrow(() => JSON.parse(JSON.stringify(msgs)), "postMessage-clonable");
    assert.deepStrictEqual(JSON.parse(JSON.stringify(msgs)), msgs, "nothing is lost to a JSON round trip");
  }
});

// ===========================================================================
// WP-10 S2: THE PANEL GLUE.  `extension.js` now creates the panel (`openPanel`),
// posts ONE envelope shape (`postSnapshot` -> `core.panelSnapshot`), reads the
// panel's messages (`onPanelMessage` -> `core.panelInbound`), and routes every
// answer through `present` (`core.presentRoute`).  Three layers, per the rule
// at the head of this file:
//
//   * the pure decisions, table-tested;
//   * `panelGlueModel`, the glue statement for statement, calling THE SAME
//     builders, driven through the design review's hazards H1, H2, H3, H9 and
//     an interleaving explorer;
//   * "glue pins (WP-10 S2)", which reads `extension.js` and fails if the glue
//     stops having the shape the model has.
// ===========================================================================

const BUNDLE_OK = ["ermine-client.js", "ermine-client.js.map", "ermine-host.js", "ermine-host.js.map"];
/** The writers' web/ folder as listed on the machine this was built on
 *  (MEASURED: `ls ermine-writers/writers/html/src/main/resources/web`). */
const WRITERS_OK = ["common.css", "htmlwriter.css", "htmlwriter.js", "htmlwriter_classic.css", "htmlwriter_dark.css",
  "iejson.js", "javafxwriter.css"];

test("panel S2 (envelope): ONE shape -- {kind: snapshot, seq, messages} -- and the messages are panelMessagesFor's", () => {
  const view = panelAfter([answerOutcome("ok-wpint")], { pending: true });
  const env = core.panelSnapshot(view, 7);
  assert.deepStrictEqual(Object.keys(env).sort(), ["kind", "messages", "seq"]);
  assert.strictEqual(env.kind, "snapshot");
  assert.strictEqual(env.seq, 7);
  assert.deepStrictEqual(env.messages, core.panelMessagesFor(view));
  assert.ok(core.PANEL_MESSAGE_KINDS.indexOf("snapshot") < 0, "the envelope is not a reducer kind");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(env)), env, "postMessage-clonable, nothing lost");
  for (const bad of [0, -1, 1.5, "1", null, undefined, NaN]) {
    assert.throws(() => core.panelSnapshot(view, bad), /seq is a positive integer/, String(bad));
  }
});

test("panel S2 (inbound): ready, the ONE intent, log -- and everything else is ignored by name", () => {
  assert.deepStrictEqual(core.panelInbound({ type: "ready" }), { act: "ready" });
  assert.deepStrictEqual(core.panelInbound({ type: "ready", v: 1 }), { act: "ready" });
  assert.deepStrictEqual(core.panelInbound({ type: "intent", kind: "restartServer" }), { act: "restartServer" });
  assert.deepStrictEqual(core.panelInbound({ type: "log", message: "widget x failed" }), { act: "log", text: "widget x failed" });
  const long = core.panelInbound({ type: "log", message: "x".repeat(5000) });
  assert.strictEqual(long.act, "log");
  assert.ok(long.text.length <= 2003, "a page cannot flood the channel with one line");
  // U4: Restart ONLY -- a Render anyway intent is NOT offered
  for (const bad of [
    { type: "intent", kind: "render" }, { type: "intent", action: "restartServer" }, { type: "intent" },
    { type: "snapshot" }, { type: "command", command: "ermine.restartServer" }, { kind: "ready" },
    null, undefined, "ready", 3,
  ]) {
    const d = core.panelInbound(bad);
    assert.strictEqual(d.act, "ignore", JSON.stringify(bad));
    assert.ok(typeof d.why === "string" && d.why.length > 0, JSON.stringify(bad));
  }
});

test("panel S2 (route): U1 -- json is the tab alone, panel the panel alone, both both; junk is the default", () => {
  assert.deepStrictEqual(core.presentRoute("json"), { tab: true, panel: false });
  assert.deepStrictEqual(core.presentRoute("panel"), { tab: false, panel: true });
  assert.deepStrictEqual(core.presentRoute("both"), { tab: true, panel: true });
  assert.strictEqual(core.PANEL_TARGET_DEFAULT, "panel");
  for (const junk of [undefined, null, "", "JSON", "tab", 1]) {
    assert.deepStrictEqual(core.presentRoute(junk), { tab: false, panel: true }, String(junk));
    assert.deepStrictEqual(core.presentRoute(core.panelTarget(junk).target), { tab: false, panel: true });
  }
});

test("panel S2 (bundle): the check is fail-CLOSED over the listing -- ok only when BOTH entries are there", () => {
  const dir = core.previewBundleDir("/w/ermine-scala");
  assert.strictEqual(dir, path.join("/w/ermine-scala", "client", "dist", "browser"));
  assert.strictEqual(core.previewBundleDir(""), null);
  assert.strictEqual(core.previewBundleDir(undefined), null);
  assert.deepStrictEqual(core.PREVIEW_BUNDLE_FILES, ["ermine-client.js", "ermine-host.js"]);

  const ok = core.previewBundleCheck(dir, BUNDLE_OK);
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(ok.state, "ok");
  assert.deepStrictEqual(ok.missing, []);

  const rows = [
    // listing                                         state      ok
    [null,                                             "absent",  false],   // no directory at all (W10)
    [[],                                               "absent",  false],
    [["ermine-client.js.map", "ermine-host.js.map"],   "absent",  false],   // maps are not scripts
    [["ermine-client.js"],                             "half",    false],
    [["ermine-host.js", "ermine-host.js.map"],         "half",    false],
    [["ERMINE-CLIENT.JS", "ermine-host.js"],           "half",    false],   // exact names
    [["ermine-client.js", "ermine-host.js"],           "ok",      true],
    ["ermine-client.js ermine-host.js",                "absent",  false],   // not a listing
  ];
  for (const [listing, state, isOk] of rows) {
    const c = core.previewBundleCheck(dir, listing);
    assert.strictEqual(c.state, state, JSON.stringify(listing));
    assert.strictEqual(c.ok, isOk, JSON.stringify(listing));
    if (!isOk) {
      assert.ok(c.message.indexOf(dir) >= 0, "the resolved path is printed: " + c.message);
      assert.match(c.message, /npm run bundle/);
    }
  }
  const half = core.previewBundleCheck(dir, ["ermine-client.js"]);
  assert.match(half.title, /HALF-BUILT/);
  assert.match(half.message, /has ermine-client\.js but not ermine-host\.js/);
  assert.match(half.message, /Delete /, "half-built is LOUDER than absent: it says to delete the leftovers");
  assert.doesNotMatch(core.previewBundleCheck(dir, []).message, /Delete /);
  const noRoot = core.previewBundleCheck(null, BUNDLE_OK);
  assert.strictEqual(noRoot.ok, false, "no root is never ok, whatever the listing says");
  assert.strictEqual(noRoot.state, "no-root");
});

test("panel S2 (notice page): static, script-free, its own CSP, every string escaped", () => {
  const dir = core.previewBundleDir("/w/<b>&\"x\"");
  for (const listing of [null, ["ermine-client.js"]]) {
    const html = core.buildPanelNoticeHtml(core.previewBundleCheck(dir, listing));
    assert.ok(!/<script/i.test(html), "no script: nothing could post ready from it");
    assert.ok(!/\son[a-z]+=/i.test(html), "no inline handler either");
    assert.ok(html.indexOf('content="' + core.PANEL_NOTICE_CSP + '"') > 0);
    assert.strictEqual(core.PANEL_NOTICE_CSP, "default-src 'none'; style-src 'unsafe-inline';");
    assert.ok(html.indexOf("<b>") < 0, "the path is escaped");
    assert.ok(html.indexOf("&lt;b&gt;&amp;&quot;x&quot;") > 0, "and it is printed");
    assert.ok(html.indexOf('id="' + core.PREVIEW_ROOT_ID + '"') > 0);
  }
  assert.match(core.buildPanelNoticeHtml(core.previewBundleCheck(dir, [])), /The preview bundle is not built/);
  assert.match(core.buildPanelNoticeHtml(undefined), /The preview cannot be shown/);
});

test("panel S2 (roots): localResourceRoots is exactly what the page loads -- the bundle dir, and WP-11's slot", () => {
  assert.deepStrictEqual(core.previewResourceRoots("/w/client/dist/browser", null), ["/w/client/dist/browser"]);
  assert.deepStrictEqual(core.previewResourceRoots("/w/client/dist/browser", "/wr/web"), ["/w/client/dist/browser", "/wr/web"]);
  assert.deepStrictEqual(core.previewResourceRoots(null, null), [], "no root: nothing is loadable, and nothing is needed");
});

/**
 * THE PANEL GLUE, STATEMENT FOR STATEMENT: `present`, `postSnapshot`,
 * `openPanel`, `setPanelHtml`, `checkPreviewBundle`, `onPanelMessage`,
 * `panelViewNow`, the two `panelAnswers` assignments in `renderNow`, the
 * `setPreviewStatus` hook, `holdRender`'s post, `pickReport`'s reset and
 * `disposePreview`'s teardown -- with the SAME core builders.  `renderNow` is
 * cut down to what the panel reads: the latch consumed once at its top, the
 * generation, the spinner, one wire the test settles by hand, the generation
 * check and the stuck reducer.
 *
 * The FAKE PANEL is the documented contract (design review F1, READ): a post
 * to a HIDDEN webview is dropped and still answers `true`; a post to a
 * DISPOSED one throws; `webview.html = ...` replaces the page, which says
 * `ready` only if it has a script (the notice page has none).  It records
 * every post ATTEMPT made before its page said `ready`, which is H3's
 * invariant.
 *
 * WHAT IT OMITS, SAID HERE PER THE HEADER RULE: `openPanel`'s re-check does
 * not model `webview.options = panelOptions(bundle)` (a fake panel loads from
 * nowhere), and `panelOptions` is not modelled at all -- both are pinned
 * instead, by `glue pins (WP-10 S2) one panel` and `... the page and the bundle`.
 * WP-10 S3 (the S3 review's N1): `reloadBundle`'s
 * `if (bundle.ok) panel.webview.options = panelOptions(bundle);` is not
 * modelled either, nor `watchBundle`'s channel log, its try/catch and its
 * `if (!watcher) return;` -- the first is pinned by the anchored reload regex
 * in `glue pins (WP-10 S3) the coalescer and the reload`, the others are
 * logging and editor-failure paths the fake watcher never takes.  The fake
 * watcher is also MORE capable than the documented one: it reports per-file
 * events for a folder that is absent or re-created and every deleted file,
 * which the typings say a real one may not (the S3 review's M1).
 * WP-11 (S4): `checkPreviewWriters` reads the setting from `m.writersPath` and
 * uses `m.root` for BOTH the first workspace folder and `resolveServer().root`
 * (the glue's two sources agree whenever `ermine.serverPath` is unset, which is
 * the only case the model has); `panelOptions(bundle, writers)` is still not
 * modelled -- its one `localResourceRoots` list is pinned by `glue pins
 * (WP-11) the writers` and its content by `panel S4 (roots)`.
 *
 * THE H-NUMBERS in the test names are the design review's §3: H1 a panel
 * disposed or replaced under a render, H2 an answer overtaken by a newer
 * render, H3 `ready` before/after the first answer, H7 a hidden panel drops
 * posts, H9 the reveal latch and one panel.
 */
function panelGlueModel(opts) {
  const o = opts || {};
  const m = {
    target: o.target || "panel",
    root: o.root === undefined ? "/w" : o.root,
    listing: o.listing === undefined ? BUNDLE_OK.slice() : o.listing,
    // WP-11: the setting and the writers folder's listing.
    writersPath: o.writersPath === undefined ? "" : o.writersPath,
    writersListing: o.writersListing === undefined ? WRITERS_OK.slice() : o.writersListing,
    panelWriters: null,
    previewPanel: undefined,
    panelReady: false,
    panelSeq: 0,
    panelAnswers: core.initialPanelAnswers(),
    panelBundle: null,
    generation: 0,
    picked: PANEL_PICK,
    stuckState: core.initialStuckState(),
    mark: null,
    restartState: core.initialRestartState(0),
    renderInFlight: false,
    coalescing: false,
    fastMode: false,
    revealNextRender: false,
    lastAnswer: undefined,
    disposed: false,
    created: [],
    tabs: [],
    commands: [],
    logs: [],
    wires: [],
    throwsOut: 0,
    // WP-10 S3: the bundle watcher's globals, and the fake editor's clock,
    // watchers and one timer (the glue's `setTimeout`/`clearTimeout`).
    bundleWatcher: null,
    bundleWatch: core.initialBundleWatch(),
    bundleTimer: undefined,
    now: 1000,
    timers: [],
    fsWatchers: [],
    reloads: 0,
  };

  /** `setTimeout` / `clearTimeout` on the virtual clock; `tick` runs what is due. */
  m.setTimeout = (fn, ms) => { const t = { at: m.now + ms, fn, cleared: false }; m.timers.push(t); return t; };
  m.clearTimeout = (t) => { if (t) t.cleared = true; };
  m.tick = (ms) => {
    const until = m.now + ms;
    for (;;) {
      const due = m.timers.filter((t) => !t.cleared && t.at <= until).sort((a, b) => a.at - b.at)[0];
      if (!due) break;
      m.now = Math.max(m.now, due.at);
      due.cleared = true;
      due.fn();
    }
    m.now = until;
  };
  m.liveTimers = () => m.timers.filter((t) => !t.cleared).length;
  /** `vscode.workspace.createFileSystemWatcher(new RelativePattern(Uri.file(dir), glob))`:
   *  it reports an event for a base name the glob matches, and nothing once disposed. */
  m.fakeWatcher = (dir, glob) => {
    const w = { dir, glob, disposed: false, handlers: { create: [], change: [], delete: [] } };
    const sub = (list, fn) => { list.push(fn); return { dispose() { const i = list.indexOf(fn); if (i >= 0) list.splice(i, 1); } }; };
    w.onDidCreate = (fn) => sub(w.handlers.create, fn);
    w.onDidChange = (fn) => sub(w.handlers.change, fn);
    w.onDidDelete = (fn) => sub(w.handlers.delete, fn);
    w.dispose = () => { w.disposed = true; };
    w.emit = (kind, file) => {
      if (w.disposed) return;
      if (!(glob === "*.js" && /^[^/]*\.js$/.test(file))) return;
      w.handlers[kind].slice().forEach((f) => f({ fsPath: path.join(dir, file) }));
    };
    return w;
  };
  /** The file system: what webpack (or `rm -rf`) does to the bundle folder, as
   *  the LISTING `checkPreviewBundle` reads plus the events every live watcher on
   *  that folder reports.  A write is TWO events (open/truncate, then the data):
   *  INFERRED, the per-write event count is UNVERIFIED -- the point is only that
   *  one build is several events. */
  m.fs = {
    write(file, dt) {
      const existed = m.listing !== null && m.listing.indexOf(file) >= 0;
      if (!existed) m.listing = (m.listing || []).concat([file]).sort();
      for (const w of m.fsWatchers) { w.emit(existed ? "change" : "create", file); w.emit("change", file); }
      if (dt) m.tick(dt);
    },
    remove(file, dt) {
      if (m.listing === null || m.listing.indexOf(file) < 0) return;
      m.listing = m.listing.filter((f) => f !== file);
      if (m.listing.length === 0) m.listing = null;
      for (const w of m.fsWatchers) w.emit("delete", file);
      if (dt) m.tick(dt);
    },
  };
  /** ONE webpack build: four files, 5 ms apart (`client/webpack.config.js`'s two
   *  entries, each with its `.map`). */
  m.build = () => { for (const f of BUNDLE_OK) m.fs.write(f, 5); };
  /** `rm -rf client/dist/browser`. */
  m.removeBundle = () => { for (const f of BUNDLE_OK) m.fs.remove(f, 1); };

  m.fakePanel = function () {
    const p = {
      visible: true, disposed: false, reveals: 0, htmls: [], delivered: [], dropped: 0,
      early: 0, afterDispose: 0, pageReady: false, handlers: { dispose: [], view: [], msg: [] },
    };
    const sub = (list, fn) => { list.push(fn); return { dispose() { const i = list.indexOf(fn); if (i >= 0) list.splice(i, 1); } }; };
    p.webview = {
      cspSource: "vscode-webview-resource:",
      options: null,
      asWebviewUri: (u) => ({ toString: () => "https://file+.vscode-resource.x" + u.fsPath }),
      get html() { return p.htmls[p.htmls.length - 1]; },
      set html(v) { p.htmls.push(v); p.pageReady = false; },
      postMessage(env) {
        if (p.disposed) { p.afterDispose += 1; throw new Error("Webview is disposed"); }
        if (!p.pageReady) p.early += 1;
        if (!p.visible || !p.pageReady) { p.dropped += 1; return Promise.resolve(true); }
        p.delivered.push(JSON.parse(JSON.stringify(env)));
        return Promise.resolve(true);
      },
      onDidReceiveMessage: (fn) => sub(p.handlers.msg, fn),
    };
    p.onDidDispose = (fn) => sub(p.handlers.dispose, fn);
    p.onDidChangeViewState = (fn) => sub(p.handlers.view, fn);
    p.reveal = () => {
      if (p.disposed) throw new Error("revealed a disposed panel");
      p.reveals += 1;
      if (!p.visible) { p.visible = true; p.handlers.view.slice().forEach((f) => f({ webviewPanel: p })); }
    };
    p.dispose = () => {
      if (p.disposed) return;
      p.disposed = true;
      p.handlers.dispose.slice().forEach((f) => f());
    };
    // ---- what the TEST does to the panel ----
    p.loadPage = () => {                       // the page's script ran and said ready
      if (p.disposed) return;
      if (/<script /.test(p.webview.html)) {
        p.pageReady = true;
        p.handlers.msg.slice().forEach((f) => f({ type: "ready" }));
      }
    };
    p.hide = () => { p.visible = false; p.handlers.view.slice().forEach((f) => f({ webviewPanel: p })); };
    p.show = () => { p.visible = true; p.handlers.view.slice().forEach((f) => f({ webviewPanel: p })); };
    p.send = (msg) => p.handlers.msg.slice().forEach((f) => f(msg));
    p.last = () => p.delivered[p.delivered.length - 1];
    return p;
  };

  /** `panelViewNow()`. */
  m.viewNow = () => core.panelView({
    answers: m.panelAnswers,
    stuckState: m.stuckState,
    mark: m.mark,
    pick: m.picked,
    restartedByUs: core.restartedByUs(m.restartState),
    pending: m.renderInFlight || m.coalescing,
    unsaved: [],
    fastMode: m.fastMode === true,
    switching: null,
    reloading: core.bundleReloading(m.bundleWatch),
    writers: o.mutantViewNoWriters ? null : m.panelWriters,
  });
  /** `postSnapshot(why)`. */
  m.postSnapshot = (why) => {
    const panel = m.previewPanel;
    if (!panel || (!m.panelReady && !o.mutantPostBeforeReady)) return false;
    m.panelSeq += 1;
    try {
      if (o.mutantLooseMessages) {
        for (const msg of core.panelMessagesFor(m.viewNow())) panel.webview.postMessage(msg);
        return true;
      }
      const envelope = core.panelSnapshot(m.viewNow(), m.panelSeq);
      panel.webview.postMessage(envelope);
      return true;
    } catch (err) {
      m.logs.push("could not post to the panel (" + why + "): " + err.message);
      return false;
    }
  };
  /** `checkPreviewBundle()`. */
  m.checkPreviewBundle = () => {
    const dir = core.previewBundleDir(m.root);
    const listing = dir ? m.listing : null;
    return core.previewBundleCheck(dir, listing);
  };
  /** `checkPreviewWriters()` (WP-11). */
  m.checkPreviewWriters = () => {
    const where = core.previewWritersDir(m.writersPath, m.root, m.root);
    const listing = where.dir ? m.writersListing : null;
    return core.previewWritersCheck(where, listing);
  };
  /** `setPanelHtml(panel, bundle, writers)`. */
  m.setPanelHtml = (panel, bundle, writers) => {
    m.panelWriters = writers;
    m.panelBundle = bundle;
    m.panelReady = false;
    if (!bundle.ok) {
      m.logs.push("preview: " + bundle.title + " -- " + bundle.message);
      panel.webview.html = core.buildPanelNoticeHtml(bundle);
      return;
    }
    const writersNote = core.writersLine(writers);
    if (writersNote) m.logs.push(writersNote);
    const uriOf = (dir, file) => panel.webview.asWebviewUri({ fsPath: path.join(dir, file) }).toString();
    panel.webview.html = core.buildPreviewHtml(
      core.previewPageUris(panel.webview.cspSource, bundle, writers, uriOf),
      { stamp: m.now });
  };
  /** `openPanel()`. */
  m.openPanel = () => {
    if (m.previewPanel && !o.mutantSecondPanel) {
      m.previewPanel.reveal(undefined, true);
      if (o.mutantNoWritersRecheck ? (!m.panelBundle || !m.panelBundle.ok) : core.panelRecheck(m.panelBundle, m.panelWriters)) {
        const bundle = m.checkPreviewBundle();
        const writers = m.checkPreviewWriters();
        const reload = o.mutantReloadEveryCommand ? bundle.ok : core.panelReload(m.panelBundle, m.panelWriters, bundle, writers);
        if (reload) {
          m.setPanelHtml(m.previewPanel, bundle, writers);
          m.watchBundle(bundle.dir);
        }
      }
      return;
    }
    const bundle = m.checkPreviewBundle();
    const writers = m.checkPreviewWriters();
    const panel = m.fakePanel();
    m.created.push(panel);
    m.previewPanel = panel;
    m.panelReady = false;
    const listeners = [];
    listeners.push(
      panel.onDidDispose(() => {
        for (const l of listeners) l.dispose();
        if (m.previewPanel !== panel) return;
        m.previewPanel = undefined;
        m.panelReady = false;
        m.panelBundle = null;
        m.panelWriters = null;
        if (!o.mutantNoUnwatch) m.unwatchBundle();
      }),
      panel.onDidChangeViewState(() => {
        if (o.mutantNoResyncOnVisible) return;
        if (m.previewPanel === panel && panel.visible) m.postSnapshot("visible");
      }),
      panel.webview.onDidReceiveMessage((msg) => m.onPanelMessage(panel, msg))
    );
    m.setPanelHtml(panel, bundle, writers);
    m.watchBundle(bundle.dir);
  };
  /** `watchBundle(dir)`. */
  m.watchBundle = (dir) => {
    if (m.bundleWatcher && m.bundleWatcher.dir === dir) return;
    m.unwatchBundle();
    if (!dir) return;
    const watcher = m.fakeWatcher(dir, core.BUNDLE_WATCH_GLOB);
    m.fsWatchers.push(watcher);
    const fire = (kind) => (uri) =>
      m.bundleStep({ type: "event", event: core.bundleWatchEvent(kind, uri && uri.fsPath), at: m.now });
    m.bundleWatcher = {
      dir,
      disposables: [
        watcher,
        watcher.onDidCreate(fire("create")),
        watcher.onDidChange(fire("change")),
        watcher.onDidDelete(o.mutantNoDeleteArm ? () => {} : fire("delete")),
      ],
    };
  };
  /** `unwatchBundle()`. */
  m.unwatchBundle = () => {
    const w = m.bundleWatcher;
    m.bundleWatcher = null;
    if (w) for (const d of w.disposables) d.dispose();
    m.bundleStep({ type: "dispose" });
  };
  /** `bundleStep(input)`. */
  m.bundleStep = (input) => {
    const step = core.bundleWatchStep(m.bundleWatch, input);
    m.bundleWatch = step.state;
    const fx = step.effects;
    if (o.mutantNoDebounce && input.type === "event" && fx.armMs !== null) { m.reloadBundle(1); return; }
    if (fx.disarm || fx.armMs !== null) {
      if (m.bundleTimer) m.clearTimeout(m.bundleTimer);
      m.bundleTimer = undefined;
    }
    if (fx.armMs !== null) {
      m.bundleTimer = m.setTimeout(() => {
        m.bundleTimer = undefined;
        m.bundleStep({ type: "timer", at: m.now });
      }, fx.armMs);
    }
    if (fx.announce) m.postSnapshot("bundle changed");
    if (fx.reload) m.reloadBundle(fx.events);
  };
  /** `reloadBundle(events)`. */
  m.reloadBundle = (events) => {
    const panel = m.previewPanel;
    if (!panel) return;
    const bundle = m.checkPreviewBundle();
    const writers = m.checkPreviewWriters();
    m.logs.push(core.bundleReloadLine(m.panelBundle, bundle, events));
    m.reloads += 1;
    if (o.mutantReloadNoHtml) { m.postSnapshot("reloaded"); return; }
    if (o.mutantNoticeNotRestored && m.panelBundle && !m.panelBundle.ok) return;
    m.setPanelHtml(panel, bundle, writers);
  };
  /** `onPanelMessage(panel, msg)`. */
  m.onPanelMessage = (panel, msg) => {
    if (m.previewPanel !== panel) return;
    const inbound = core.panelInbound(msg);
    if (inbound.act === "ready") { m.panelReady = true; m.postSnapshot("ready"); return; }
    if (inbound.act === "restartServer") {
      if (o.mutantRestartBypass) { m.commands.push("<restart() called directly>"); return; }
      m.commands.push("ermine.restartServer");
      return;
    }
    if (inbound.act === "log") { m.logs.push("preview panel: " + inbound.text); return; }
    m.logs.push("preview: ignored a message from the panel (" + inbound.why + ")");
  };
  /** `showAnswer(answer, reveal)` -- recorded, since its body is pinned byte-identical. */
  m.showAnswer = async (answer, reveal) => { m.tabs.push({ content: core.tabContent(answer), reveal }); };
  /** `present(answer, reveal)`. */
  m.present = async (answer, reveal) => {
    const route = core.presentRoute(m.target);
    if (route.tab) await m.showAnswer(answer, o.mutantTabRevealAlways ? true : reveal);
    if (route.panel) {
      if (reveal || (o.mutantLatchTwice && m.revealNextRender)) m.openPanel();
      if (o.mutantLatchTwice) m.revealNextRender = false;
      m.postSnapshot("answer");
    }
  };
  /** `setPreviewStatus()`'s hook. */
  m.setPreviewStatus = () => { if (m.disposed) return; m.postSnapshot("status"); };
  /** `holdRender(trigger)`'s post. */
  m.holdRender = () => { m.postSnapshot("held"); };
  /** `renderNow`, cut down to what the panel reads. */
  m.renderNow = async (reveal) => {
    if (!m.picked) return;
    m.generation += 1;
    const mine = m.generation;
    m.renderInFlight = true;
    const revealThis = reveal === true || m.revealNextRender;
    m.revealNextRender = false;
    m.setPreviewStatus();
    const wire = deferred();
    m.wires.push({ generation: mine, settle: wire.settle });
    const outcome = await wire.promise;
    let answer;
    if (outcome && outcome.rejection) {
      if (core.isDisplaced(outcome.rejection)) {
        if (mine === m.generation) m.renderInFlight = false;
        m.setPreviewStatus();
        return;
      }
      answer = core.errorAnswer(outcome.rejection, mine);
    } else {
      answer = Object.assign({}, outcome, { generation: mine });
    }
    if (mine === m.generation) m.renderInFlight = false;
    if (o.mutantStepBeforeDiscard) m.panelAnswers = core.panelAnswerStep(m.panelAnswers, { answer }, mine);
    if (!core.isCurrentGeneration(m.generation, answer)) { m.setPreviewStatus(); return; }
    m.lastAnswer = answer;
    m.panelAnswers = core.panelAnswerStep(m.panelAnswers, { answer }, m.generation);
    const stuckEvent = { type: "answer", stuck: answer.stuck === true, message: answer.message, seqAtSend: 0 };
    m.stuckState = core.stuckReduce(m.stuckState, stuckEvent).state;
    m.setPreviewStatus();                                   // applyStuck's
    await m.present(answer, revealThis);
    m.setPreviewStatus();
  };
  /** `pickReport`'s part: another report, and it reveals. */
  m.pickReport = (pick) => {
    m.picked = pick;
    m.lastAnswer = undefined;
    m.panelAnswers = core.initialPanelAnswers();
    m.revealNextRender = false;
    m.setPreviewStatus();
    return m.renderNow(true);
  };
  /** `disposePreview()`'s part. */
  m.disposePreview = () => {
    m.disposed = true;
    m.picked = undefined;
    m.revealNextRender = false;
    if (m.previewPanel) {
      const panel = m.previewPanel;
      m.previewPanel = undefined;
      m.panelReady = false;
      panel.dispose();
    }
    if (!o.mutantNoUnwatch) m.unwatchBundle();
    m.panelBundle = null;
    m.panelWriters = null;
    m.panelAnswers = core.initialPanelAnswers();
  };
  m.answer = (i, value) => m.wires[i].settle(value);
  /** The truth the panel should show now, as the messages. */
  m.truth = () => core.panelMessagesFor(m.viewNow());
  return m;
}

const OK_DOC = (tag) => ({ ok: true, document: { version: 1, settings: {}, root: { tag: "VFlow", children: [], note: tag } } });
const ERR_500 = { ok: false, status: 500, message: "Sales.report produced a document that cannot be encoded", path: null };
const STUCK_ANSWER = { ok: false, status: 503, message: "evaluation did not finish after 4s", stuck: true };

test("panel S2 H3 (ready AFTER the first answer): nothing is posted before ready; ready brings the whole truth", async () => {
  const m = panelGlueModel();
  const r = m.renderNow(true);
  await flush();
  assert.strictEqual(m.created.length, 0, "no panel before there is an answer to show");
  m.answer(0, OK_DOC("a"));
  await r;
  assert.strictEqual(m.created.length, 1, "the explicit render created it");
  const p = m.created[0];
  assert.strictEqual(p.early, 0, "not one post before the page said ready");
  assert.strictEqual(p.delivered.length, 0);
  assert.match(p.webview.html, /<script src=/);
  p.loadPage();
  assert.strictEqual(p.delivered.length, 1, "exactly one snapshot, on ready");
  assert.deepStrictEqual(p.last().messages, m.truth());
  assert.strictEqual(p.last().messages[0].kind, "render");
  assert.strictEqual(p.last().messages[0].document.root.note, "a");
});

test("panel S2 H3 (ready BEFORE the next answer): every later post is a whole snapshot, seq rising", async () => {
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  const r2 = m.renderNow(false);                          // an automatic re-render
  await flush();
  assert.strictEqual(p.last().messages.find((x) => x.kind === "stale").stale, true, "the pending render is said");
  m.answer(1, ERR_500);
  await r2;
  assert.deepStrictEqual(p.last().messages, m.truth());
  assert.deepStrictEqual(core.panelMessagesFor(m.viewNow()).map((x) => x.kind).slice(0, 2), ["render", "error"],
    "the error keeps the last good document below it");
  for (const env of p.delivered) assert.strictEqual(env.kind, "snapshot", "ONE shape, ever");
  const seqs = p.delivered.map((e) => e.seq);
  for (let i = 1; i < seqs.length; i++) assert.ok(seqs[i] > seqs[i - 1], "seq rises: " + seqs);
  assert.strictEqual(p.early, 0);
});

test("panel S2 H3 MUTANT: a post before ready is an attempt the page cannot receive", async () => {
  const m = panelGlueModel({ mutantPostBeforeReady: true });
  const r = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r;
  assert.ok(m.created[0].early > 0, "the mutant posts into a page that has not loaded");
});

test("panel S2 H7 (hidden drops): a stuck answer while hidden is dropped, and becoming visible resyncs it", async () => {
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  p.hide();
  const r2 = m.renderNow(false);
  await flush();
  m.answer(1, STUCK_ANSWER);
  await r2;
  assert.ok(p.dropped > 0, "the posts while hidden were dropped");
  assert.notDeepStrictEqual(p.last().messages, m.truth(), "so the page is behind");
  p.show();
  assert.deepStrictEqual(p.last().messages, m.truth(), "visible -> one snapshot, the whole truth");
  assert.strictEqual(p.last().messages.find((x) => x.kind === "stuck").stuck, true, "including the stuck banner (H7/H10)");
});

test("panel S2 H7 MUTANT: without the resync on visible the stuck state never arrives", async () => {
  const m = panelGlueModel({ mutantNoResyncOnVisible: true });
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  p.hide();
  const r2 = m.renderNow(false);
  await flush();
  m.answer(1, STUCK_ANSWER);
  await r2;
  p.show();
  assert.strictEqual(p.last().messages.find((x) => x.kind === "stuck").stuck, false, "the page still shows no wedge");
});

test("panel S2 H1 (dispose mid-render): an answer after the user closed the panel posts nothing, throws nothing, re-creates nothing", async () => {
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  const r2 = m.renderNow(false);
  await flush();
  p.dispose();                                            // the user closes the tab
  assert.strictEqual(m.previewPanel, undefined);
  assert.strictEqual(m.panelReady, false);
  m.answer(1, OK_DOC("b"));
  await r2;
  assert.strictEqual(p.afterDispose, 0, "nothing reached the disposed panel");
  assert.strictEqual(m.created.length, 1, "an automatic render does not bring it back");
  // and the NEXT explicit render does, with a fresh page and a fresh latch
  const r3 = m.renderNow(true);
  await flush();
  m.answer(2, OK_DOC("c"));
  await r3;
  assert.strictEqual(m.created.length, 2);
  const q = m.created[1];
  assert.strictEqual(q.early, 0);
  q.loadPage();
  assert.strictEqual(q.last().messages[0].document.root.note, "c");
});

test("panel S2 H1 (teardown mid-render): disposePreview closes the panel and the late answer is a no-op", async () => {
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  const r2 = m.renderNow(false);
  await flush();
  m.disposePreview();
  assert.strictEqual(p.disposed, true, "disposePreview disposes the panel");
  m.answer(1, OK_DOC("b"));
  await r2;
  assert.strictEqual(p.afterDispose, 0);
  assert.strictEqual(m.created.length, 1, "nothing re-creates a panel after the window's teardown");
  assert.strictEqual(m.previewPanel, undefined);
});

test("panel S2 H9 (two commands, one panel): overlapping explicit renders reveal ONE panel", async () => {
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  const r2 = m.renderNow(true);                           // the second command before the first answer
  await flush();
  m.answer(1, OK_DOC("b"));
  m.answer(0, OK_DOC("a"));                               // the older answer lands later: discarded
  await Promise.all([r1, r2]);
  assert.strictEqual(m.created.length, 1, "one panel per window");
  // a third command after it exists reveals the SAME panel
  const r3 = m.renderNow(true);
  await flush();
  m.answer(2, OK_DOC("c"));
  await r3;
  assert.strictEqual(m.created.length, 1);
  assert.ok(m.created[0].reveals >= 1, "the existing panel is revealed");
  m.created[0].loadPage();
  assert.strictEqual(m.created[0].last().messages[0].document.root.note, "c");
});

async function overtaken(opts) {
  const m = panelGlueModel(opts);
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  const r2 = m.renderNow(false);          // overtaken ...
  await flush();
  const r3 = m.renderNow(false);          // ... by this one, before r2 settles
  await flush();
  m.answer(1, OK_DOC("stale"));           // r2's answer lands late: generation 2 < 3
  await r2;
  const staleShown = p.delivered.some((e) => e.messages.some((x) => x.kind === "render" && x.document.root.note === "stale"));
  m.answer(2, OK_DOC("c"));
  await r3;
  return { m, p, staleShown };
}

test("panel S2 H2 (overtaken answer): an answer behind a newer render posts NOTHING of its document, whatever order they settle in", async () => {
  const { p, staleShown } = await overtaken();
  assert.strictEqual(staleShown, false, "the overtaken answer's document never reached the page");
  assert.strictEqual(p.last().messages[0].document.root.note, "c");
  // and the other order: the newer answer first, then the older one
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  await flush();
  const r2 = m.renderNow(true);                           // a second command overtakes the first
  await flush();
  m.answer(1, OK_DOC("new"));
  await r2;
  m.created[0].loadPage();
  m.answer(0, OK_DOC("old"));
  await r1;
  assert.ok(!m.created[0].delivered.some((e) => e.messages.some((x) => x.kind === "render" && x.document.root.note === "old")));
  assert.strictEqual(m.created[0].last().messages[0].document.root.note, "new");
});

test("panel S2 H2 MUTANT: stepping the answers BEFORE the generation discard shows the overtaken document", async () => {
  const { staleShown } = await overtaken({ mutantStepBeforeDiscard: true });
  assert.strictEqual(staleShown, true);
});

test("panel S2 H9 MUTANT: create-without-reveal makes a second panel", async () => {
  const m = panelGlueModel({ mutantSecondPanel: true });
  for (let i = 0; i < 2; i++) {
    const r = m.renderNow(true);
    await flush();
    m.answer(i, OK_DOC(String(i)));
    await r;
  }
  assert.strictEqual(m.created.length, 2);
});

test("panel S2 (latch): an automatic render never creates or reveals; the first-pick carry reveals ONCE", async () => {
  const m = panelGlueModel();
  const auto = m.renderNow(false);
  await flush();
  m.answer(0, OK_DOC("a"));
  await auto;
  assert.strictEqual(m.created.length, 0, "never created by an automatic re-render");
  // WP-8 S3's carry: the yield-to-schema path sets the latch and the SCHEDULED
  // render (reveal=false) consumes it
  m.revealNextRender = true;
  const carried = m.renderNow(false);
  assert.strictEqual(m.revealNextRender, false, "consumed at the top, before any await");
  await flush();
  m.answer(1, OK_DOC("b"));
  await carried;
  assert.strictEqual(m.created.length, 1, "the carried reveal creates the panel");
  const p = m.created[0];
  p.loadPage();
  const later = m.renderNow(false);
  await flush();
  m.answer(2, OK_DOC("c"));
  await later;
  assert.strictEqual(p.reveals, 0, "and a later automatic render does not reveal it");
});

test("panel S2 (latch) MUTANT: consuming the latch a second time in present spends a reveal the render did not have", async () => {
  const m = panelGlueModel({ mutantLatchTwice: true });
  const r = m.renderNow(false);
  await flush();
  m.revealNextRender = true;               // armed while the automatic render is in flight
  m.answer(0, OK_DOC("a"));
  await r;
  assert.strictEqual(m.created.length, 1, "the automatic render created the panel");
  assert.strictEqual(m.revealNextRender, false, "and ate the reveal meant for the next render");
});

test("panel S2 (target): json keeps the 0.1.11 tab path and touches no panel; both does both; panel no tab", async () => {
  for (const [target, tabs, panels] of [["json", 2, 0], ["panel", 0, 1], ["both", 2, 1]]) {
    const m = panelGlueModel({ target });
    const r1 = m.renderNow(true);
    await flush();
    m.answer(0, OK_DOC("a"));
    await r1;
    const r2 = m.renderNow(false);
    await flush();
    m.answer(1, ERR_500);
    await r2;
    assert.strictEqual(m.tabs.length, tabs, target + ": tab updates");
    assert.strictEqual(m.created.length, panels, target + ": panels");
    if (tabs) {
      assert.deepStrictEqual(m.tabs.map((t) => t.reveal), [true, false], target + ": the tab reveals exactly as before");
      assert.strictEqual(m.tabs[1].content, core.tabContent(Object.assign({}, ERR_500, { generation: 2 })));
    }
  }
  const mut = panelGlueModel({ target: "json", mutantTabRevealAlways: true });
  const r = mut.renderNow(false);
  await flush();
  mut.answer(0, OK_DOC("a"));
  await r;
  assert.strictEqual(mut.tabs[0].reveal, true, "MUTANT: the tab path changed -- an automatic render reveals");
});

test("panel S2 (loose) MUTANT: loose messages are not the envelope the page takes", async () => {
  const m = panelGlueModel({ mutantLooseMessages: true });
  const r = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r;
  m.created[0].loadPage();
  assert.ok(m.created[0].delivered.length > 1);
  assert.ok(m.created[0].delivered.every((e) => e.kind !== "snapshot"), "not one snapshot envelope reached the page");
});

test("panel S2 (intent): Restart goes through the ermine.restartServer COMMAND; nothing else is obeyed", async () => {
  for (const bypass of [false, true]) {
    const m = panelGlueModel({ mutantRestartBypass: bypass });
    const r = m.renderNow(true);
    await flush();
    m.answer(0, STUCK_ANSWER);
    await r;
    const p = m.created[0];
    p.loadPage();
    p.send({ type: "intent", kind: "restartServer" });
    p.send({ type: "intent", kind: "render" });
    p.send({ type: "log", message: "widget scorecard at $.root: boom" });
    if (!bypass) {
      assert.deepStrictEqual(m.commands, ["ermine.restartServer"]);
      assert.ok(m.logs.some((l) => /ignored a message from the panel \(an intent this extension does not offer/.test(l)));
      assert.ok(m.logs.indexOf("preview panel: widget scorecard at $.root: boom") >= 0);
    } else {
      assert.notDeepStrictEqual(m.commands, ["ermine.restartServer"], "MUTANT: the wedge guard's door is bypassed");
    }
  }
});

test("panel S2 (bundle absent): the notice page, a channel line, never a post -- and a re-run after building loads the page", async () => {
  for (const listing of [null, ["ermine-client.js"]]) {
    const m = panelGlueModel({ listing });
    const r = m.renderNow(true);
    await flush();
    m.answer(0, OK_DOC("a"));
    await r;
    const p = m.created[0];
    assert.ok(!/<script/.test(p.webview.html), "the notice page has no script");
    assert.ok(m.logs.some((l) => /preview: The preview bundle is (not built|HALF-BUILT)/.test(l)), m.logs.join("\n"));
    p.loadPage();                                          // nothing in it can say ready
    assert.strictEqual(m.panelReady, false);
    assert.strictEqual(p.delivered.length + p.dropped + p.early, 0, "not one post attempted");
    // the developer runs `npm run bundle` and the command again
    m.listing = BUNDLE_OK.slice();
    const r2 = m.renderNow(true);
    await flush();
    m.answer(1, OK_DOC("b"));
    await r2;
    assert.strictEqual(m.created.length, 1, "the same panel");
    assert.match(p.webview.html, /<script src=/, "now the real page");
    p.loadPage();
    assert.strictEqual(p.last().messages[0].document.root.note, "b");
  }
});

test("panel S2 (pick change): the panel never shows a document for a pick the user has left (H2 of the review)", async () => {
  const m = panelGlueModel();
  const r1 = m.renderNow(true);
  await flush();
  m.answer(0, OK_DOC("a"));
  await r1;
  const p = m.created[0];
  p.loadPage();
  const other = core.makePick("file:///w/doc/Other.e", "/w/doc/Other.e", "report", "Other", []);
  const r2 = m.pickReport(other);
  await flush();
  assert.ok(!p.last().messages.some((x) => x.kind === "render"), "the old document is withdrawn at once");
  m.answer(1, OK_DOC("other"));
  await r2;
  assert.strictEqual(p.last().messages[0].document.root.note, "other");
});

test("panel S2 (explorer): over random interleavings, never a post before ready or after dispose, and a visible ready panel ends on the truth", async () => {
  const rnd = wp8Rnd(20260924);
  for (let run = 0; run < 250; run++) {
    const m = panelGlueModel({ target: ["panel", "both"][rnd(2)] });
    const pending = [];
    let wire = 0;
    for (let step = 0; step < 14; step++) {
      const p = m.previewPanel;
      switch (rnd(8)) {
        case 0: pending.push(m.renderNow(true)); break;
        case 1: pending.push(m.renderNow(false)); break;
        case 2: if (wire < m.wires.length) m.answer(wire++, [OK_DOC("x" + step), ERR_500, STUCK_ANSWER][rnd(3)]); break;
        case 3: if (p) p.loadPage(); break;
        case 4: if (p) p.hide(); break;
        case 5: if (p) p.show(); break;
        case 6: if (p && rnd(3) === 0) p.dispose(); break;
        default: m.holdRender(); break;
      }
      await flush();
    }
    while (wire < m.wires.length) m.answer(wire++, OK_DOC("end"));
    await Promise.all(pending);
    for (const p of m.created) {
      assert.strictEqual(p.early, 0, "run " + run + ": a post before ready");
      assert.strictEqual(p.afterDispose, 0, "run " + run + ": a post after dispose");
      for (const e of p.delivered) assert.strictEqual(e.kind, "snapshot");
    }
    assert.ok(m.created.filter((p) => !p.disposed).length <= 1, "run " + run + ": two live panels");
    const live = m.previewPanel;
    if (live) {
      live.show();
      live.loadPage();
      assert.deepStrictEqual(live.last().messages, m.truth(), "run " + run + ": the page ends on the truth");
    }
  }
});

/** The source and helpers every WP-10 S2 glue pin reads (split into named
 *  tests so a mutant dies by the name of the rule it broke). */
function s2Glue() {
  const fsMod = require("node:fs");
  const raw = fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const src = codeOf(raw);
  const pin = (what, fix) =>
    "source pin (test/preview-core.test.js): extension.js changed shape — " + what +
    ". If you meant it, update this pin; the behaviour it protects is " + fix;
  const body = (start, end) => {
    const i = src.indexOf(start);
    const j = src.indexOf(end, i + start.length);
    assert.ok(i >= 0 && j > i, pin("cannot find " + start + " .. " + end, "every pin below"));
    return src.slice(i, j);
  };
  const count = (re, text) => (text.match(re) || []).length;
  return { raw, src, pin, body, count };
}

test("glue pins (WP-10 S2) one panel -- one createWebviewPanel, create-or-reveal, opened only by present on the reveal latch", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  // ---- ONE panel, created in ONE place, reached ONLY on the reveal latch --
  assert.strictEqual(count(/createWebviewPanel\(/g, src), 1,
    pin("createWebviewPanel is called other than once", "H5/H9: ONE panel per window"));
  const open = body("function openPanel(", "function onPanelMessage(");
  assert.ok(open.indexOf("createWebviewPanel(") > 0, pin("the one createWebviewPanel is not in openPanel", "the same"));
  const reuse = open.indexOf("if (previewPanel) {");
  assert.ok(reuse >= 0 && reuse < open.indexOf("createWebviewPanel(") &&
            /if \(previewPanel\) \{[\s\S]*?previewPanel\.reveal\(undefined, true\);[\s\S]*?return;\s*\}/.test(open),
    pin("openPanel no longer reveals-and-returns when a panel exists", "H9: two commands, one panel"));
  assert.ok(/previewPanel = panel;\s*panelReady = false;/.test(open),
    pin("the new panel is not stored, or the ready latch is not lowered", "that nothing posts to a page that has not loaded"));
  assert.ok(/viewColumn: vscode\.ViewColumn\.Beside, preserveFocus: true/.test(open) &&
            /retainContextWhenHidden: true/.test(open),
    pin("the panel does not open beside without focus, or retain is gone", "§2(a): the reveal never steals focus (U2's optimisation)"));
  // WP-11 (S4) widened the re-check to a page built without the whole
  // writers, and gated the re-set on core.panelReload (fresh checks differ).
  assert.ok(/if \(core\.panelRecheck\(panelBundle, panelWriters\)\) \{\s*const bundle = checkPreviewBundle\(\);\s*const writers = checkPreviewWriters\(\);\s*if \(core\.panelReload\(panelBundle, panelWriters, bundle, writers\)\) \{\s*previewPanel\.webview\.options = panelOptions\(bundle, writers\);\s*setPanelHtml\(previewPanel, bundle, writers\);/.test(open),
    pin("the re-check of an existing panel changed (its condition, or the options reset before the html)",
        "that ONLY a panel showing the notice page is re-checked (a working page is never reloaded by a command), " +
        "and that a panel first opened with no root gets its localResourceRoots when the bundle appears (review M1: R15, R16)"));
  assert.strictEqual(count(/openPanel\(\);/g, src), 1, pin("openPanel is called from more than one place", "that ONLY present opens it"));
  const present = body("async function present(", "function previewTarget(");
  assert.ok(/if \(route\.panel\) \{\s*if \(reveal\) openPanel\(\);\s*postSnapshot\("answer"\);\s*\}/.test(present),
    pin("present opens the panel other than on `reveal`", "that an automatic re-render never creates or reveals the panel"));
  assert.strictEqual(present.indexOf("revealNextRender"), -1,
    pin("present reads or writes the reveal latch", "that the latch is consumed ONCE, at the top of renderNow"));
  assert.ok(/const route = core\.presentRoute\(previewTarget\(\)\);/.test(present),
    pin("present does not route through core.presentRoute", "U1"));
});

test("glue pins (WP-10 S2) the tab -- target=json is byte-identical to 0.1.11, and every answer goes through present", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  const present = body("async function present(", "function previewTarget(");
  // ---- the tab path is byte-identical under json ---------------------------
  assert.ok(/if \(route\.tab\) await showAnswer\(answer, reveal\);/.test(present),
    pin("present calls showAnswer other than with the render's own reveal", "that the tab behaves as 0.1.11 (playtest A/B)"));
  const i = raw.indexOf("async function showAnswer(");
  const showAnswerText = raw.slice(i, raw.indexOf("\n}\n", i) + 3);
  assert.strictEqual(require("node:crypto").createHash("sha256").update(showAnswerText).digest("hex"),
    "1def850a87e8d3b378cfe1dbe03b936c7e3617ab29499644841ab0ed792f140d",
    pin("showAnswer's text changed", "that target=json is BYTE-IDENTICAL to 0.1.11's tab (playtest groups A and B)"));
  assert.strictEqual(count(/showAnswer\(/g, src), 2,
    pin("showAnswer is called from somewhere other than present", "that every answer goes through present"));
});

test("glue pins (WP-10 S2) renderNow -- present where showAnswer was, the latch consumed once, the answers stepped beside lastAnswer", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  // ---- renderNow: present where showAnswer was; the latch consumed once ----
  const renderBody = body("async function renderNow(", "async function showAnswer(");
  assert.strictEqual(count(/await present\(refusal, revealThis\);/g, renderBody), 1,
    pin("the refusal arm does not present with revealThis", "H9"));
  assert.strictEqual(count(/await present\(answer, revealThis\);/g, renderBody), 1,
    pin("the answer arm does not present with revealThis", "H9"));
  assert.strictEqual(count(/revealNextRender = false;/g, renderBody), 1,
    pin("renderNow consumes the latch other than once", "that the reveal cannot leak into a later render"));
  assert.ok(renderBody.indexOf("revealNextRender = false;") < renderBody.indexOf("await "),
    pin("the latch is consumed after an await", "the same"));
  // the panel's answers are stepped beside every lastAnswer, by the shared step
  assert.ok(/lastAnswer = refusal;[\s\S]{0,900}?panelAnswers = core\.panelAnswerStep\(panelAnswers, \{ answer: refusal \}, generation\);/.test(renderBody),
    pin("the refusal is not stepped into panelAnswers", "that the panel shows a params refusal like the tab"));
  assert.ok(/lastAnswer = answer;\s*panelAnswers = core\.panelAnswerStep\(panelAnswers, \{ answer \}, generation\);/.test(renderBody),
    pin("the answer is not stepped into panelAnswers", "that the panel shows what the tab shows"));
  // THE S1 REVIEW'S NOTE, CLOSED BY ARGUMENT: nothing awaits between the
  // verdict that compared the generation and the refusal's present.
  const gap = body("const verdict = core.mayStillSend(", "await present(refusal, revealThis);");
  assert.strictEqual(gap.indexOf("await "), -1,
    pin("an await now sits between mayStillSend and the refusal's present",
        "that the panel's generation check cannot refuse a refusal the tab shows (target=both)"));
});

test("glue pins (WP-10 S2) the post -- one postMessage, guarded by the ready latch, and only core.panelSnapshot's envelope", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  // ---- ONE post, guarded, and only ever an envelope ------------------------
  assert.strictEqual(count(/\.postMessage\(/g, src), 1, pin("postMessage is called other than once", "ONE message shape"));
  const post = body("function postSnapshot(", "function checkPreviewBundle(");
  assert.ok(/const panel = previewPanel;\s*if \(!panel \|\| !panelReady\) return false;/.test(post),
    pin("postSnapshot is not guarded by the panel AND the ready latch", "H1/H3: never before ready, never to a disposed panel"));
  assert.ok(/const envelope = core\.panelSnapshot\(panelViewNow\(\), panelSeq\);/.test(post) &&
            /panel\.webview\.postMessage\(envelope\)/.test(post),
    pin("the post is not core.panelSnapshot's envelope", "the S1 finding: loose messages leave `reloading` raised"));
  assert.ok(/try \{[\s\S]*postMessage\(envelope\)[\s\S]*\} catch \(err\) \{/.test(post),
    pin("a throwing post is not caught", "H3: a panel disposed under us is a log line, not an exception"));
  const viewNow = body("function panelViewNow(", "function postSnapshot(");
  assert.ok(/return core\.panelView\(\{/.test(viewNow) && /answers: panelAnswers,/.test(viewNow) &&
            /stuckState,/.test(viewNow) && /mark: wedgeMark,/.test(viewNow) && /pick: picked,/.test(viewNow) &&
            /pending: renderInFlight \|\| coalesceTimer !== undefined,/.test(viewNow),
    pin("the view is not the shared builder over the module globals", "that the model reads what the glue reads"));
  // ALL TEN FIELDS, one by one (the review's M1: five were unpinned, and
  // `restartedByUs: false` / `fastMode: false` left every test green).
  const fields = [
    "answers: panelAnswers,", "stuckState,", "mark: wedgeMark,", "pick: picked,",
    "restartedByUs: core.restartedByUs(restartState),", "pending: renderInFlight || coalesceTimer !== undefined,",
    "unsaved: [],", 'fastMode: config().get("fastMode", false) === true,', "switching: null,",
    // WP-10 S3: the watcher's coalescer raises it (`glue pins (WP-10 S3) ...`).
    "reloading: core.bundleReloading(bundleWatch),",
    // WP-11 (S4): the writers check the page was built from.
    "writers: panelWriters,",
  ];
  const got = (viewNow.match(/^\s*[a-zA-Z]+[:,][^\n]*$/gm) || []).map((l) => l.trim());
  assert.deepStrictEqual(got, fields,
    pin("panelViewNow's fields are not exactly the eleven the model passes", "that the model reads what the glue reads (review M1: R17, R18)"));
});

test("glue pins (WP-10 S2) the page talks back -- ready and visible resync, Restart is the command, dispose clears", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  const open = body("function openPanel(", "function onPanelMessage(");
  // ---- where it posts ------------------------------------------------------
  assert.ok(/if \(previewDisposed\) return;\s*[\s\S]{0,400}?postSnapshot\("status"\);/.test(body("function setPreviewStatus(", "function rootsFor(")),
    pin("setPreviewStatus no longer tells the panel", "stale, stuck, offline and held reach the panel"));
  assert.ok(/function holdRender\(trigger\) \{\s*postSnapshot\("held"\);/.test(src),
    pin("holdRender does not post first", "that the panel learns it is held where the hold is decided"));
  const msgBody = body("function onPanelMessage(", "async function refreshModule(");
  assert.ok(/if \(previewPanel !== panel\) return;\s*const inbound = core\.panelInbound\(msg\);/.test(msgBody),
    pin("a message from a panel that is not the current one is obeyed, or is not decided by core.panelInbound", "H3"));
  assert.ok(/if \(inbound\.act === "ready"\) \{\s*panelReady = true;\s*postSnapshot\("ready"\);/.test(msgBody),
    pin("ready does not raise the latch and resync", "H1"));
  assert.ok(/if \(inbound\.act === "log"\) \{\s*log\("preview panel: " \+ inbound\.text\);\s*return;/.test(msgBody),
    pin("the page's log intent no longer reaches the Ermine output channel",
        "the only way a human sees a CSP violation or a page-side render failure (review M1: R14)"));
  assert.ok(/if \(inbound\.act === "restartServer"\) \{[\s\S]*?vscode\.commands\.executeCommand\("ermine\.restartServer"\);/.test(msgBody) &&
            !/\brestart\(/.test(msgBody),
    pin("the Restart intent does not go through the ermine.restartServer command", "U4 and the wedge guard: a panel button uses the palette's door"));
  assert.ok(/panel\.onDidChangeViewState\(\(\) => \{\s*if \(previewPanel === panel && panel\.visible\) postSnapshot\("visible"\);/.test(open),
    pin("becoming visible does not resync", "H2/U2: a hidden webview drops posts (F1)"));
  assert.ok(/panel\.onDidDispose\(\(\) => \{[\s\S]*?if \(previewPanel !== panel\) return;\s*previewPanel = undefined;\s*panelReady = false;/.test(open),
    pin("onDidDispose does not clear the globals", "H3"));
});

test("glue pins (WP-10 S2) the page and the bundle -- the notice page on a failed check, the exact CSP, the options", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  // ---- the page, and the bundle check --------------------------------------
  const html = body("function setPanelHtml(", "function openPanel(");
  assert.ok(/panelBundle = bundle;\s*panelReady = false;\s*if \(!bundle\.ok\) \{[\s\S]*?log\([\s\S]*?core\.buildPanelNoticeHtml\(bundle\);\s*return;/.test(html),
    pin("a missing bundle is not the notice page plus a channel line, or the latch is not lowered first", "W10"));
  assert.ok(/core\.buildPreviewHtml\(\s*core\.previewPageUris\(panel\.webview\.cspSource, bundle, writers, uriOf\),/.test(html),
    pin("the page is not core.buildPreviewHtml with the webview's cspSource", "the exact CSP"));
  const check = body("function checkPreviewBundle(", "function panelOptions(");
  assert.ok(/core\.previewBundleDir\(server && server\.root\)/.test(check) && /fs\.readdirSync\(dir\)/.test(check) &&
            /return core\.previewBundleCheck\(dir, listing\);/.test(check),
    pin("the bundle check is not the pure check over a listing of resolveServer's root", "U3, fail-closed"));
  assert.ok(/enableScripts: true,/.test(body("function panelOptions(", "function setPanelHtml(")) &&
            /enableForms: false,/.test(src) && !/enableCommandUris: true/.test(src),
    pin("the webview options changed", "§2(b): scripts on, forms off, command URIs off"));
});

test("glue pins (WP-10 S2) teardown and a pick change -- the panel goes with the window, the old document with the old pick", () => {
  const { raw, src, pin, body, count } = s2Glue();
  void raw; void count;
  // ---- teardown, and a pick change -----------------------------------------
  const teardown = body("function disposePreview(", "function restorePick(");
  assert.ok(/if \(previewPanel\) \{[\s\S]*?previewPanel = undefined;\s*panelReady = false;[\s\S]*?panel\.dispose\(\);/.test(teardown) &&
            /panelAnswers = core\.initialPanelAnswers\(\);/.test(teardown),
    pin("disposePreview does not dispose the panel and clear its state", "teardown is a state"));
  assert.ok(/lastAnswer = undefined;[\s\S]{0,300}?panelAnswers = core\.initialPanelAnswers\(\);/.test(body("async function pickReport(", "async function renderCommand(")),
    pin("a pick change keeps the old report's document for the panel", "H2: never a document for a pick the user has left"));
});

// ===========================================================================
// WP-10 STAGE 3: the bundle watcher (W4), the H4 notice page, the CSP's
// missing connect-src, and gate_client.
//
// The watcher is glue -- a `createFileSystemWatcher` and a `setTimeout` in
// extension.js -- but WHAT IT DECIDES is `core.bundleWatchStep`, a coalescer
// with the clock as an argument, and the model above drives the SAME step
// with a virtual clock (the style of the `scheduleRender` 150 ms model).
// Glue edits are seen only by the `glue pins (WP-10 S3) ...` tests.
// ===========================================================================

/** A panel opened by an explicit render of "a", its page loaded. */
async function s3OpenReady(m, note) {
  const r = m.renderNow(true);
  await flush();
  m.answer(m.wires.length - 1, OK_DOC(note || "a"));
  await r;
  const p = m.created[m.created.length - 1];
  p.loadPage();
  return p;
}
const Q = core.BUNDLE_QUIET_MS;
const liveWatchers = (m) => m.fsWatchers.filter((w) => !w.disposed);
const hasReloadBanner = (env) => env.messages.some((x) => x.kind === "reloadBundle");

test("panel S3 (step): every event pushes ONE shared deadline, whatever the file; only a quiet period reloads, once", () => {
  assert.ok(Q >= 200, "W4: the quiet period is at least 200 ms, not " + Q);
  assert.strictEqual(core.BUNDLE_WATCH_GLOB, "*.js");
  const ev = (kind, file) => core.bundleWatchEvent(kind, "/w/client/dist/browser/" + file);
  assert.deepStrictEqual(ev("change", "ermine-host.js"), { kind: "change", file: "ermine-host.js" });
  let s = core.initialBundleWatch();
  assert.strictEqual(core.bundleReloading(s), false);
  let st = core.bundleWatchStep(s, { type: "event", event: ev("create", "ermine-client.js"), at: 0 });
  assert.deepStrictEqual([st.effects.armMs, st.effects.announce, st.effects.reload], [Q, true, false], "the first event announces");
  s = st.state;
  assert.strictEqual(core.bundleReloading(s), true, "announced, not yet reloaded");
  st = core.bundleWatchStep(s, { type: "event", event: ev("change", "ermine-host.js"), at: 100 });
  assert.deepStrictEqual([st.effects.armMs, st.effects.announce, st.effects.reload], [Q, false, false], "a later event only pushes the deadline");
  s = st.state;
  assert.strictEqual(s.due, 100 + Q, "ONE deadline for the whole folder, from the LAST event");
  st = core.bundleWatchStep(s, { type: "timer", at: Q });
  assert.deepStrictEqual([st.effects.armMs, st.effects.reload], [100, false], "a timer before the deadline re-arms for the rest");
  assert.strictEqual(st.state, s);
  st = core.bundleWatchStep(s, { type: "timer", at: 100 + Q });
  assert.deepStrictEqual([st.effects.reload, st.effects.events, st.effects.files], [true, 2, ["ermine-client.js", "ermine-host.js"]]);
  assert.strictEqual(core.bundleReloading(st.state), false, "idle again: the new page's snapshot carries no reloadBundle");
  assert.strictEqual(core.bundleWatchStep(st.state, { type: "timer", at: 9e9 }).effects.reload, false, "an idle timer does nothing");
  // ignored BY IDENTITY: a .map, an unknown kind, no file, no clock
  for (const bad of [
    { type: "event", event: ev("change", "ermine-client.js.map"), at: 1 },
    { type: "event", event: ev("rename", "ermine-client.js"), at: 1 },
    { type: "event", event: core.bundleWatchEvent("change", undefined), at: 1 },
    { type: "event", event: ev("change", "ermine-client.js") },
    { type: "nonsense", at: 1 }, null,
  ]) {
    const r = core.bundleWatchStep(s, bad);
    assert.strictEqual(r.state, s, JSON.stringify(bad));
    assert.deepStrictEqual([r.effects.armMs, r.effects.reload, r.effects.announce], [null, false, false]);
  }
  // the DELETE arm is an event like the other two
  assert.strictEqual(core.bundleWatchStep(core.initialBundleWatch(), { type: "event", event: ev("delete", "ermine-host.js"), at: 5 }).effects.armMs, Q);
  const d = core.bundleWatchStep(s, { type: "dispose" });
  assert.strictEqual(d.effects.disarm, true);
  assert.strictEqual(core.bundleReloading(d.state), false);
});

test("panel S3 (reload line): the channel says what the page was and what it is now", () => {
  const ok = core.previewBundleCheck("/w/client/dist/browser", BUNDLE_OK);
  const gone = core.previewBundleCheck("/w/client/dist/browser", null);
  assert.match(core.bundleReloadLine(ok, ok, 4), /changed \(4 file events\); reloading the panel$/);
  assert.match(core.bundleReloadLine(gone, ok, 2), /whole again; loading the panel page$/);
  assert.match(core.bundleReloadLine(ok, gone, 1), /\(1 file event\) and the bundle is not whole \(absent\); showing the notice page$/);
});

test("panel S3 watcher (one build): a four-file webpack write is ONE announcement and ONE reload, after the quiet period", async () => {
  const m = panelGlueModel();
  const p = await s3OpenReady(m);
  assert.strictEqual(liveWatchers(m).length, 1);
  assert.deepStrictEqual([liveWatchers(m)[0].dir, liveWatchers(m)[0].glob], [path.join("/w", "client", "dist", "browser"), "*.js"],
    "the bundle FOLDER from resolveServer's root, with *.js (W4)");
  const html0 = p.webview.html;
  const posted = p.delivered.length;
  m.build();                                                  // four files, 20 ms
  const during = p.delivered.slice(posted);
  assert.strictEqual(during.length, 1, "the page is told ONCE that a reload is coming");
  assert.ok(hasReloadBanner(during[0]), "through the reducer's own reloadBundle kind");
  assert.strictEqual(during[0].messages[0].document.root.note, "a", "the document stays under the banner");
  assert.strictEqual(p.htmls.length, 1, "nothing reloads inside the quiet period");
  m.tick(Q);
  assert.strictEqual(m.reloads, 1, "ONE reload per build");
  assert.strictEqual(p.htmls.length, 2);
  assert.match(p.webview.html, /<script src=/);
  assert.notStrictEqual(p.webview.html, html0, "a fresh stamp: the html string differs");
  assert.ok(m.logs.some((l) => /changed \(4 file events\); reloading the panel/.test(l)), m.logs.join("\n"));
  assert.strictEqual(m.panelReady, false, "the ready latch dropped with the page");
  assert.strictEqual(m.liveTimers(), 0);
  p.loadPage();
  assert.ok(!hasReloadBanner(p.last()), "the NEW page's snapshot says nothing about a reload");
  assert.strictEqual(p.last().messages[0].document.root.note, "a", "and it carries the document back");
  m.tick(10 * Q);
  assert.strictEqual(m.reloads, 1, "and nothing more");
});

test("panel S3 watcher (two builds): separated by more than the quiet period, TWO reloads; inside it, ONE", async () => {
  const m = panelGlueModel();
  const p = await s3OpenReady(m);
  m.build(); m.tick(Q + 50); m.build(); m.tick(Q + 50);
  assert.strictEqual(m.reloads, 2);
  assert.strictEqual(p.htmls.length, 3);
  const n = panelGlueModel();
  const q = await s3OpenReady(n);
  n.build(); n.tick(Q - 100); n.build(); n.tick(Q + 50);
  assert.strictEqual(n.reloads, 1, "a second build inside the window is the same burst");
  assert.strictEqual(q.htmls.length, 2);
});

test("panel S3 watcher MUTANT: without the debounce one build reloads the page FOUR times", async () => {
  const m = panelGlueModel({ mutantNoDebounce: true });
  await s3OpenReady(m);
  m.build();
  m.tick(Q);
  assert.strictEqual(m.reloads, 4, "the model's teeth: every event reloads");
});

test("panel S3 H4 (vanish/appear): the bundle deleted flips the panel to the notice page, rebuilt flips it back and resyncs", async () => {
  const m = panelGlueModel();
  const p = await s3OpenReady(m);
  m.removeBundle();                                            // rm -rf client/dist/browser
  m.tick(Q);
  assert.strictEqual(m.reloads, 1);
  assert.ok(!/<script/.test(p.webview.html), "the static notice page");
  assert.match(p.webview.html, /data-state="absent"/);
  assert.ok(m.logs.some((l) => /not whole \(absent\); showing the notice page/.test(l)));
  const before = p.delivered.length;
  p.loadPage();
  assert.strictEqual(p.delivered.length, before, "nothing can say ready on the notice page, so nothing is posted");
  // half a build: only the client entry lands, then a pause
  m.fs.write("ermine-client.js", 5); m.fs.write("ermine-client.js.map", 5);
  m.tick(Q);
  assert.match(p.webview.html, /data-state="half"/, "HALF-BUILT is its own, louder, notice");
  m.fs.write("ermine-host.js", 5); m.fs.write("ermine-host.js.map", 5);
  m.tick(Q);
  assert.match(p.webview.html, /<script src=/, "the page is back");
  assert.ok(m.logs.some((l) => /whole again; loading the panel page/.test(l)));
  p.loadPage();
  assert.strictEqual(p.last().messages[0].document.root.note, "a", "and the resync brings the document");
  assert.strictEqual(m.created.length, 1, "the same panel throughout");
});

test("panel S3 H4 (W10 first experience): a panel opened on the not-built notice becomes the page when the bundle is built", async () => {
  const m = panelGlueModel({ listing: null });
  const r = m.renderNow(true); await flush(); m.answer(0, OK_DOC("a")); await r;
  const p = m.created[0];
  assert.ok(!/<script/.test(p.webview.html));
  assert.strictEqual(liveWatchers(m).length, 1, "the folder is watched although nothing is in it yet (UNVERIFIED in a real editor)");
  m.build();
  m.tick(Q);
  assert.match(p.webview.html, /<script src=/);
  p.loadPage();
  assert.strictEqual(p.last().messages[0].document.root.note, "a");
});

test("panel S3 H4 MUTANTS: the delete arm dropped, the notice page never left, the reload posted without a new page", async () => {
  {
    const m = panelGlueModel({ mutantNoDeleteArm: true });
    const p = await s3OpenReady(m);
    m.removeBundle(); m.tick(Q);
    assert.match(p.webview.html, /<script src=/, "teeth: without the delete arm a vanished bundle is never noticed");
  }
  {
    const m = panelGlueModel({ mutantNoticeNotRestored: true });
    const p = await s3OpenReady(m);
    m.removeBundle(); m.tick(Q); m.build(); m.tick(Q);
    assert.ok(!/<script/.test(p.webview.html), "teeth: the notice page stays up after the rebuild");
  }
  {
    const m = panelGlueModel({ mutantReloadNoHtml: true });
    const p = await s3OpenReady(m);
    m.build(); m.tick(Q);
    assert.strictEqual(p.htmls.length, 1, "teeth: a reload that re-sets no html loads no new code");
  }
});

test("panel S3 H4 (reload mid-render): an answer that settles while the page is being replaced arrives with the new page's ready", async () => {
  const m = panelGlueModel();
  const p = await s3OpenReady(m);
  const r2 = m.renderNow(false);
  await flush();
  m.build();
  m.tick(Q);                                                  // the page is replaced between send and answer
  assert.strictEqual(m.panelReady, false);
  const before = p.delivered.length + p.dropped + p.early;
  m.answer(1, OK_DOC("b"));
  await r2;
  assert.strictEqual(p.delivered.length + p.dropped + p.early, before, "nothing is posted to a page that is not ready");
  p.loadPage();
  assert.strictEqual(p.last().messages[0].document.root.note, "b", "the new page's snapshot carries the answer");
  assert.deepStrictEqual(p.last().messages, m.truth());
});

test("panel S3 watcher (lifetime): no panel, no watcher; the watcher, its listeners and its timer go with the panel and the window", async () => {
  const m = panelGlueModel();
  m.build(); m.tick(Q);
  assert.strictEqual(m.fsWatchers.length, 0, "activation and a build with no panel: nothing watches");
  const auto = m.renderNow(false); await flush(); m.answer(0, OK_DOC("x")); await auto;
  assert.strictEqual(m.fsWatchers.length, 0, "an automatic render opens no panel, so no watcher");
  const p = await s3OpenReady(m);
  assert.strictEqual(liveWatchers(m).length, 1);
  m.fs.write("ermine-client.js");                              // a burst begins ...
  assert.strictEqual(m.liveTimers(), 1);
  p.dispose();                                                 // ... and the user closes the panel
  assert.strictEqual(liveWatchers(m).length, 0, "the watcher is disposed with the panel");
  assert.strictEqual(m.liveTimers(), 0, "and its timer");
  assert.strictEqual(core.bundleReloading(m.bundleWatch), false);
  m.tick(4 * Q); m.build(); m.tick(4 * Q);
  assert.strictEqual(m.reloads, 0, "nothing reloads a panel that is gone");
  const p2 = await s3OpenReady(m, "b");
  assert.notStrictEqual(p2, p);
  assert.strictEqual(liveWatchers(m).length, 1, "a new panel, ONE new watcher");
  m.renderNow(true); await flush(); m.answer(m.wires.length - 1, OK_DOC("c")); await flush();
  assert.strictEqual(m.fsWatchers.length, 2, "a second command reveals; it does not watch twice");
  m.fs.write("ermine-host.js");
  m.disposePreview();
  assert.strictEqual(liveWatchers(m).length, 0, "the window's teardown disposes it too");
  assert.strictEqual(m.liveTimers(), 0);
  // no root at all: the notice page, and nothing to watch
  const n = panelGlueModel({ root: null });
  const r = n.renderNow(true); await flush(); n.answer(0, OK_DOC("a")); await r;
  assert.strictEqual(n.fsWatchers.length, 0);
});

test("panel S3 watcher MUTANT: a watcher left behind by a closed panel still holds a timer and a listener", async () => {
  const m = panelGlueModel({ mutantNoUnwatch: true });
  const p = await s3OpenReady(m);
  m.fs.write("ermine-client.js");
  p.dispose();
  assert.strictEqual(liveWatchers(m).length, 1, "teeth: the watcher outlives its panel");
  assert.strictEqual(m.liveTimers(), 1);
});

test("panel S3 watcher (explorer): over random builds, deletions, renders and closes -- at most one watcher, only with a panel, and the page ends on the truth", async () => {
  const rnd = wp8Rnd(20260923);
  for (let run = 0; run < 200; run++) {
    const m = panelGlueModel();
    const pending = [];
    let wire = 0;
    for (let step = 0; step < 16; step++) {
      const p = m.previewPanel;
      switch (rnd(10)) {
        case 0: pending.push(m.renderNow(true)); break;
        case 1: pending.push(m.renderNow(false)); break;
        case 2: if (wire < m.wires.length) m.answer(wire++, [OK_DOC("x" + step), ERR_500][rnd(2)]); break;
        case 3: if (p) p.loadPage(); break;
        case 4: m.build(); break;
        case 5: if (rnd(3) === 0) m.removeBundle(); else m.fs.write(BUNDLE_OK[rnd(4)]); break;
        case 6: if (p && rnd(3) === 0) p.dispose(); break;
        case 7: if (p) (rnd(2) ? p.hide() : p.show()); break;
        default: m.tick(rnd(2 * Q)); break;
      }
      await flush();
      const live = liveWatchers(m);
      assert.ok(live.length <= 1, "run " + run + ": two live watchers");
      assert.strictEqual(live.length === 1, !!m.previewPanel, "run " + run + ": a watcher without a panel, or a panel without one");
    }
    while (wire < m.wires.length) m.answer(wire++, OK_DOC("end"));
    await Promise.all(pending);
    m.listing = BUNDLE_OK.slice();
    for (const w of liveWatchers(m)) w.emit("change", "ermine-host.js");
    m.tick(Q + 1);
    for (const p of m.created) {
      assert.strictEqual(p.early, 0, "run " + run + ": a post before ready");
      assert.strictEqual(p.afterDispose, 0, "run " + run + ": a post after dispose");
    }
    assert.strictEqual(m.liveTimers(), 0, "run " + run + ": a timer outlived its burst");
    const live = m.previewPanel;
    if (live) {
      assert.match(live.webview.html, /<script src=/, "run " + run + ": a whole bundle, and the page is not the page");
      live.show();
      live.loadPage();
      assert.ok(!hasReloadBanner(live.last()), "run " + run + ": a reload banner left up");
      assert.deepStrictEqual(live.last().messages, m.truth(), "run " + run + ": the page ends on the truth");
    }
  }
});

test("panel S3 (csp): connect-src is ABSENT, ever -- F2's check that the preview never fetches -- from the page, the notice page and both sources", () => {
  for (const src of ["vscode-webview-resource:", "https://file+.vscode-resource.vscode-cdn.net", "x"]) {
    const csp = core.previewCsp(src);
    assert.ok(csp.startsWith("default-src 'none'; "), "default-src 'none' is what shuts connect-src: " + csp);
    assert.ok(!/connect-src/.test(csp), csp);
    const html = core.buildPreviewHtml({ cspSource: src, client: "c.js", host: "h.js", writers: "w.js", styles: ["a.css"] }, { stamp: 7 });
    assert.ok(!/connect-src/.test(html), "the page");
  }
  assert.ok(!/connect-src/.test(core.PANEL_NOTICE_CSP) && core.PANEL_NOTICE_CSP.startsWith("default-src 'none';"));
  assert.ok(!/connect-src/.test(core.buildPanelNoticeHtml(core.previewBundleCheck("/d", null))));
  const fsMod = require("node:fs");
  for (const f of ["preview-core.js", "extension.js"]) {
    const code = codeOf(fsMod.readFileSync(path.join(__dirname, "..", "src", f), "utf8"));
    assert.ok(!/connect-src/.test(code), "source pin: src/" + f + " mentions connect-src outside a comment");
  }
});

test("glue pins (WP-10 S3) one watcher -- ONE createFileSystemWatcher on the bundle folder, *.js, three arms into ONE coalescer, only from openPanel", () => {
  const { src, pin, body, count } = s2Glue();
  const watch = body("function watchBundle(", "function unwatchBundle(");
  assert.strictEqual(count(/createFileSystemWatcher\(/g, watch), 1, pin("watchBundle does not create exactly one watcher", "W4"));
  assert.ok(/createFileSystemWatcher\(\s*new vscode\.RelativePattern\(vscode\.Uri\.file\(dir\), core\.BUNDLE_WATCH_GLOB\)\s*\)/.test(watch),
    pin("the bundle watcher is not the FOLDER with core.BUNDLE_WATCH_GLOB", "W4: the documented out-of-workspace form, and no .map"));
  assert.strictEqual(count(/createFileSystemWatcher\(/g, src), 3,
    pin("a createFileSystemWatcher was added or removed (the report file, the params file, the bundle folder)", "one watcher per thing watched"));
  assert.ok(/if \(bundleWatcher && bundleWatcher\.dir === dir\) return;\s*unwatchBundle\(\);\s*if \(!dir\) return;/.test(watch),
    pin("watchBundle can hold two watchers, or watches without a directory", "ONE watcher"));
  assert.ok(/const fire = \(kind\) => \(uri\) =>\s*bundleStep\(\{ type: "event", event: core\.bundleWatchEvent\(kind, uri && uri\.fsPath\), at: Date\.now\(\) \}\);/.test(watch),
    pin("the arms do not build core.bundleWatchEvent into bundleStep with the clock", "the model drives what the glue drives"));
  assert.ok(/watcher,\s*watcher\.onDidCreate\(fire\("create"\)\),\s*watcher\.onDidChange\(fire\("change"\)\),\s*watcher\.onDidDelete\(fire\("delete"\)\),/.test(watch),
    pin("one of the three arms (create, change, DELETE) is missing or not the shared fire", "H4: a deleted bundle flips the page to the notice"));
  assert.strictEqual(count(/\bwatchBundle\(/g, src), 3, pin("watchBundle is called other than from openPanel's two branches", "never a watcher without a panel"));
  const open = body("function openPanel(", "function watchBundle(");
  assert.strictEqual(count(/\bwatchBundle\(bundle\.dir\);/g, open), 2, pin("openPanel does not watch in both branches", "the recovered page is watched too"));
  assert.ok(/setPanelHtml\(panel, bundle, writers\);\s*watchBundle\(bundle\.dir\);\s*\}/.test(open),
    pin("the new panel is not watched after its page is set", "W4"));
});

test("glue pins (WP-10 S3) the coalescer and the reload -- one timer, the announcement, the html reset", () => {
  const { src, pin, body, count } = s2Glue();
  const stepBody = body("function bundleStep(", "function reloadBundle(");
  assert.ok(/const step = core\.bundleWatchStep\(bundleWatch, input\);\s*bundleWatch = step\.state;\s*const fx = step\.effects;/.test(stepBody),
    pin("bundleStep does not run core.bundleWatchStep", "W4: the coalescer decides, nothing else"));
  assert.ok(/if \(fx\.disarm \|\| fx\.armMs !== null\) \{\s*if \(bundleTimer\) clearTimeout\(bundleTimer\);\s*bundleTimer = undefined;\s*\}/.test(stepBody) &&
            /if \(fx\.armMs !== null\) \{\s*bundleTimer = setTimeout\(\(\) => \{\s*bundleTimer = undefined;\s*bundleStep\(\{ type: "timer", at: Date\.now\(\) \}\);\s*\}, fx\.armMs\);\s*\}/.test(stepBody),
    pin("the ONE timer is not cleared and re-armed from the step's effects", "one reload per build (a second timer is a second reload)"));
  assert.ok(/if \(fx\.announce\) postSnapshot\("bundle changed"\);\s*if \(fx\.reload\) reloadBundle\(fx\.events\);\s*\}/.test(stepBody),
    pin("the announcement or the reload is not the step's", "the reloading banner, and ONE reload"));
  assert.strictEqual(count(/\breloadBundle\(/g, src), 2, pin("reloadBundle is reached other than from bundleStep", "the debounce: no direct reload"));
  // the definition, the arms' fire, the timer and the dispose -- nothing else feeds it
  assert.strictEqual(count(/\bbundleStep\(/g, src), 4, pin("bundleStep is called from somewhere new", "the watcher's inputs are the arms, the timer and dispose"));
  const reload = body("function reloadBundle(", "function onPanelMessage(");
  assert.ok(/const panel = previewPanel;\s*if \(!panel\) return;\s*const bundle = checkPreviewBundle\(\);\s*const writers = checkPreviewWriters\(\);\s*log\(core\.bundleReloadLine\(panelBundle, bundle, events\)\);\s*if \(bundle\.ok\) panel\.webview\.options = panelOptions\(bundle, writers\);\s*setPanelHtml\(panel, bundle, writers\);\s*\}\s*$/.test(reload),
    pin("reloadBundle is not: re-check, one channel line, the html re-set by setPanelHtml (page or notice)",
        "a reload loads new code (the html reset), a vanished bundle shows the notice and a returned one the page (H4)"));
  const viewNow = body("function panelViewNow(", "function postSnapshot(");
  assert.ok(/reloading: core\.bundleReloading\(bundleWatch\),/.test(viewNow), pin("the view's reloading is not the coalescer's", "the reloadBundle banner"));
});

test("glue pins (WP-10 S3) disposal -- the watcher goes with the panel and with the window", () => {
  const { src, pin, body } = s2Glue();
  const open = body("function openPanel(", "function watchBundle(");
  assert.ok(/if \(previewPanel !== panel\) return;\s*previewPanel = undefined;\s*panelReady = false;\s*panelBundle = null;\s*panelWriters = null;\s*unwatchBundle\(\);\s*\}\),/.test(open),
    pin("closing the panel does not dispose the bundle watcher", "never a watcher without a panel"));
  assert.ok(/unwatchBundle\(\);\s*panelBundle = null;\s*panelWriters = null;/.test(body("function disposePreview(", "function restorePick(")),
    pin("disposePreview does not dispose the bundle watcher", "teardown is a state"));
  const unwatch = body("function unwatchBundle(", "function bundleStep(");
  assert.ok(/const w = bundleWatcher;\s*bundleWatcher = null;\s*if \(w\) \{\s*for \(const d of w\.disposables\) \{/.test(unwatch) &&
            /d\.dispose\(\);/.test(unwatch) && /bundleStep\(\{ type: "dispose" \}\);\s*\}\s*$/.test(unwatch),
    pin("unwatchBundle does not dispose every listener and reset the coalescer", "the timer dies with the watcher"));
  void src;
});

test("gate_client (WP-10 S3; WP-32 S2): UNAVAILABLE (3) without client/node_modules, FAIL (1) on a stale generated file or a red suite, PASS (0) with the counts -- one SUMMARY line", (t) => {
  const cp = require("node:child_process");
  const fsMod = require("node:fs");
  const os = require("node:os");
  if (cp.spawnSync("bash", ["-c", "true"]).status !== 0) { t.skip("no bash"); return; }
  const gates = path.resolve(__dirname, "..", "..", "..", "scripts", "gates.sh");
  assert.ok(fsMod.existsSync(gates), gates);
  const tmp = fsMod.mkdtempSync(path.join(os.tmpdir(), "gate-client-"));
  try {
    fsMod.mkdirSync(path.join(tmp, "client"));
    fsMod.mkdirSync(path.join(tmp, "client", "scripts"));
    fsMod.mkdirSync(path.join(tmp, "bin"));
    // WP-32 S2: gate_client runs client/scripts/check-fresh.js (real node) before npm test
    const fresh = (line, rc) => fsMod.writeFileSync(path.join(tmp, "client", "scripts", "check-fresh.js"),
      "console.log(" + JSON.stringify("generated: " + line) + "); process.exit(" + rc + ");\n");
    fresh("fresh and exact: stub", 0);
    const run = (npmOut, npmRc) => {
      fsMod.writeFileSync(path.join(tmp, "bin", "npm"),
        "#!/bin/sh\nprintf '%s\\n' " + npmOut.map((l) => "'" + l + "'").join(" ") + "\nexit " + npmRc + "\n", { mode: 0o755 });
      const r = cp.spawnSync("bash", ["-c", 'source "$1"; gate_client > "$GATE_LOG" 2>&1; rc=$?; cat "$GATE_LOG"; exit $rc', "-", gates], {
        cwd: tmp, encoding: "utf8",
        env: Object.assign({}, process.env, { GATE_LOG: path.join(tmp, "gate.log"), PATH: path.join(tmp, "bin") + path.delimiter + process.env.PATH }),
      });
      const summaries = r.stdout.split("\n").filter((l) => l.startsWith("SUMMARY"));
      return { rc: r.status, summaries };
    };
    const green = ["ℹ tests 112", "ℹ pass 109", "ℹ fail 0", "ℹ skipped 3"];
    const none = run(green, 0);
    assert.strictEqual(none.rc, 3, "no client/node_modules is UNAVAILABLE, not FAIL: " + JSON.stringify(none));
    assert.strictEqual(none.summaries.length, 1);
    assert.match(none.summaries[0], /node_modules/);
    fsMod.mkdirSync(path.join(tmp, "client", "node_modules"));
    const pass = run(green, 0);
    assert.deepStrictEqual(pass, { rc: 0, summaries: ["SUMMARY 112 tests, 109 pass, 0 fail, 3 skipped"] }, "the three sbt-fixture skips are acceptable");
    const red = run(["ℹ tests 112", "ℹ pass 108", "ℹ fail 1", "ℹ skipped 3"], 1);
    assert.deepStrictEqual(red, { rc: 1, summaries: ["SUMMARY 112 tests, 108 pass, 1 fail, 3 skipped"] });
    const lying = run(["ℹ tests 112", "ℹ pass 108", "ℹ fail 1", "ℹ skipped 3"], 0);
    assert.strictEqual(lying.rc, 1, "a fail count is a FAIL whatever npm exited with");
    const noCounts = run(["error TS2322: nope"], 2);
    assert.strictEqual(noCounts.rc, 1);
    assert.match(noCounts.summaries[0] || "", /no test counts/);
    // a stale generated file FAILS before npm test runs, whatever npm would say
    fresh("STALE: Layout/Widgets/Text.e changed since generation -- regenerate: client/scripts/generate.sh", 1);
    const stale = run(green, 0);
    assert.deepStrictEqual(stale, { rc: 1, summaries: ["SUMMARY generated-file check failed: STALE: Layout/Widgets/Text.e changed since generation -- regenerate: client/scripts/generate.sh"] });
  } finally {
    fsMod.rmSync(tmp, { recursive: true, force: true });
  }
});

// ===========================================================================
// WP-11 (= WP-10 STAGE 4): THE LEGACY WRITERS IN THE PANEL.
//
// The writers `<script>` (first), three style sheets, `ermine.preview.writersPath`
// (U3) and the writers-missing banner (the reducer's `error`, argued at
// `WRITERS_NOTE_SEPARATOR` in preview-core.js).  Whether the writers bundle
// RUNS in a webview -- `table` through `runTabular`, a `pieChart` drawing, the
// CSP console -- is NOT observable here: this stage's done-when is the
// playtest (E3, E9-E11).  What node can hold is what the extension DECIDES:
// the page it builds, the roots it grants, the banner it sends, and when it
// re-checks.
// ===========================================================================

const S4_SRC = "https://file+.vscode-resource.vscode-cdn.net";
const S4_UPON = (dir, file) => "U(" + path.join(dir, file) + ")";
const s4Bundle = () => core.previewBundleCheck("/w/client/dist/browser", BUNDLE_OK);
const s4Check = (listing, dir) => core.previewWritersCheck({ dir: dir === undefined ? "/wr/web" : dir, source: "setting", problem: null }, listing);
const s4Page = (writers, stamp) =>
  core.buildPreviewHtml(core.previewPageUris(S4_SRC, s4Bundle(), writers, S4_UPON), { stamp: stamp === undefined ? 9 : stamp });
const s4Scripts = (html) => html.match(/<script\b[^>]*>[\s\S]*?<\/script>/g) || [];
const s4Links = (html) => html.match(/<link [^>]*>/g) || [];

test("panel S4 (html): writers FIRST, then client and host; the three style sheets in order; zero inline scripts; the writers unstamped", () => {
  const html = s4Page(s4Check(WRITERS_OK));
  assert.deepStrictEqual(s4Scripts(html), [
    '<script src="U(/wr/web/htmlwriter.js)"></script>',
    '<script src="U(/w/client/dist/browser/ermine-client.js)?v=9"></script>',
    '<script src="U(/w/client/dist/browser/ermine-host.js)?v=9"></script>',
  ]);
  assert.strictEqual((html.match(/<script/g) || []).length, 3, "no <script> the tag list missed");
  assert.strictEqual(s4Scripts(html).filter((t) => !/^<script src="[^"]+"><\/script>$/.test(t)).length, 0, "zero inline script bodies");
  for (const attr of ["defer", "async", "type=", "nonce"]) assert.ok(html.indexOf(attr) < 0, attr);
  assert.deepStrictEqual(s4Links(html), [
    '<link rel="stylesheet" href="U(/wr/web/common.css)">',
    '<link rel="stylesheet" href="U(/wr/web/htmlwriter.css)">',
    '<link rel="stylesheet" href="U(/wr/web/htmlwriter_classic.css)">',
  ]);
  assert.ok(html.indexOf("<link") < html.indexOf("</head>") && html.indexOf("</head>") < html.indexOf("<script"),
    "style sheets in the head, scripts after the root element");
  assert.ok(html.indexOf('<div id="' + core.PREVIEW_ROOT_ID + '"></div>') < html.indexOf("<script"));
  // the three are exactly these, and neither the dark theme nor the JavaFX sheet
  assert.deepStrictEqual(core.PREVIEW_WRITERS_STYLES.slice(), ["common.css", "htmlwriter.css", "htmlwriter_classic.css"]);
  assert.strictEqual(core.PREVIEW_WRITERS_SCRIPT, "htmlwriter.js");
  assert.ok(!/dark|javafx/.test(html));
});

test("panel S4 (html): a missing writers folder builds the page WITHOUT them -- two scripts, no link; half loads the script and the sheets it has", () => {
  const missing = s4Page(s4Check(["common.css", "htmlwriter.css", "htmlwriter_classic.css"]));
  assert.deepStrictEqual(s4Scripts(missing).map((t) => t.replace(/\?v=9/, "")), [
    '<script src="U(/w/client/dist/browser/ermine-client.js)"></script>',
    '<script src="U(/w/client/dist/browser/ermine-host.js)"></script>',
  ]);
  assert.deepStrictEqual(s4Links(missing), [], "no style sheet of a folder the page does not load from");
  const none = s4Page(s4Check(null));
  assert.deepStrictEqual(s4Links(none), []);
  assert.strictEqual(s4Scripts(none).length, 2);
  const half = s4Page(s4Check(["htmlwriter.js", "common.css", "htmlwriter_classic.css"]));
  assert.strictEqual(s4Scripts(half)[0], '<script src="U(/wr/web/htmlwriter.js)"></script>');
  assert.deepStrictEqual(s4Links(half), [
    '<link rel="stylesheet" href="U(/wr/web/common.css)">',
    '<link rel="stylesheet" href="U(/wr/web/htmlwriter_classic.css)">',
  ]);
});

test("panel S4 (html): a hostile writers folder is escaped -- no tag, no attribute, in the script or the links", () => {
  const evil = '/x"><script>alert(1)</script><x a="';
  const html = s4Page(s4Check(WRITERS_OK, evil));
  assert.strictEqual((html.match(/<script/g) || []).length, 3);
  assert.strictEqual((html.match(/<link/g) || []).length, 3);
  assert.ok(html.indexOf("alert(1)</script>") < 0);
  assert.strictEqual((html.match(/&quot;&gt;&lt;script&gt;alert\(1\)&lt;\/script&gt;/g) || []).length, 4, "the script and the three links, each escaped");
});

test("panel S4 (csp): the page with the writers carries the S1 policy EXACTLY -- 'unsafe-eval' stays, no blob:, no font-src, no connect-src", () => {
  const exact = "default-src 'none'; script-src " + S4_SRC + " 'unsafe-eval'; style-src " + S4_SRC +
    " 'unsafe-inline'; img-src " + S4_SRC + " data:;";
  for (const listing of [WRITERS_OK, null, ["htmlwriter.js"]]) {
    const html = s4Page(s4Check(listing));
    const metas = html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]*)">/g) || [];
    assert.deepStrictEqual(metas, ['<meta http-equiv="Content-Security-Policy" content="' + exact + '">']);
    for (const absent of ["blob:", "font-src", "connect-src", "nonce"]) assert.ok(html.indexOf(absent) < 0, absent);
  }
});

test("panel S4 (writersState): present / half / missing from the listing, FAIL-CLOSED on htmlwriter.js", () => {
  const rows = [
    [WRITERS_OK, "present"],
    [["htmlwriter.js", "common.css", "htmlwriter.css", "htmlwriter_classic.css"], "present"],
    [["htmlwriter.js", "common.css", "htmlwriter.css"], "half"],
    [["htmlwriter.js", "common.css", "htmlwriter.css", "htmlwriter_dark.css"], "half"],
    [["htmlwriter.js"], "half"],
    [["common.css", "htmlwriter.css", "htmlwriter_classic.css", "htmlwriter_dark.css", "iejson.js"], "missing"],
    [["HTMLWRITER.JS", "common.css", "htmlwriter.css", "htmlwriter_classic.css"], "missing"],
    [["htmlwriter.js.map", "common.css", "htmlwriter.css", "htmlwriter_classic.css"], "missing"],
    [[], "missing"],
    [null, "missing"],
    [undefined, "missing"],
    ["htmlwriter.js", "missing"],
    [[7, null, "common.css"], "missing"],
  ];
  for (const [listing, want] of rows) assert.strictEqual(core.writersState(listing), want, JSON.stringify(listing));
});

test("panel S4 (check): what the page loads, the root it needs and the sentence it says -- per state", () => {
  const present = s4Check(WRITERS_OK);
  assert.deepStrictEqual(
    { state: present.state, script: present.script, styles: present.styles.slice(), root: present.root, missing: present.missing.slice(), message: present.message },
    { state: "present", script: "htmlwriter.js", styles: ["common.css", "htmlwriter.css", "htmlwriter_classic.css"], root: "/wr/web", missing: [], message: null });
  assert.strictEqual(core.writersLine(present), null, "a present folder writes no channel line");
  const missing = s4Check(["common.css"]);
  assert.strictEqual(missing.state, "missing");
  assert.strictEqual(missing.script, null);
  assert.deepStrictEqual(missing.styles.slice(), []);
  assert.strictEqual(missing.root, null, "nothing of the folder is loaded, so it is no resource root");
  assert.match(missing.message, /^the legacy writers are not loaded: no htmlwriter\.js in \/wr\/web\. /);
  assert.match(missing.message, /table, drilldownTable, the charts and styleBox show an error box/);
  assert.match(missing.message, /set ermine\.preview\.writersPath to the writers' web\/ folder and run Ermine: Preview Report\.\.\. again$/);
  assert.strictEqual(core.writersLine(missing), "preview: " + missing.message);
  const half = s4Check(["htmlwriter.js", "common.css"]);
  assert.strictEqual(half.state, "half");
  assert.strictEqual(half.root, "/wr/web");
  assert.deepStrictEqual(half.missing.slice(), ["htmlwriter.css", "htmlwriter_classic.css"]);
  assert.match(half.message, /has htmlwriter\.js but not htmlwriter\.css, htmlwriter_classic\.css, so the legacy widgets draw unstyled/);
  const dflt = core.previewWritersCheck({ dir: "/d/web", source: "default", problem: null }, null);
  assert.match(dflt.message, /no htmlwriter\.js in \/d\/web \(ermine\.preview\.writersPath is empty, so this is the default: the ermine-writers checkout beside this one\)/);
  const noDir = core.previewWritersCheck(core.previewWritersDir("", "/w", null), WRITERS_OK);
  assert.strictEqual(noDir.state, "missing", "no folder is missing, whatever listing is handed in");
  assert.strictEqual(noDir.root, null);
  assert.match(noDir.message, /ermine\.preview\.writersPath is empty and there is no checkout/);
  for (const c of [present, missing, half, dflt, noDir]) assert.ok(Object.isFrozen(c) && Object.isFrozen(c.styles));
});

test("panel S4 (dir): ermine.preview.writersPath goes through THE SAME absoluteRoots as ermine.preview.roots; empty is the sibling default", () => {
  const base = path.join("/w", "folder");
  for (const raw of ["web", "./a/../web", "../ermine-writers/web", path.join("/abs", "x", "..", "web"), "  web  "]) {
    const got = core.previewWritersDir(raw, base, "/srv/root");
    const via = core.absoluteRoots([raw], base, "ermine.preview.writersPath");
    assert.deepStrictEqual({ dir: got.dir, problem: got.problem }, { dir: via.roots[0], problem: null }, JSON.stringify(raw));
    assert.strictEqual(got.source, "setting");
  }
  for (const empty of ["", "   ", undefined, null]) {
    const d = core.previewWritersDir(empty, base, path.join("/home", "me", "ermine-scala"));
    assert.deepStrictEqual({ dir: d.dir, source: d.source, problem: d.problem },
      { dir: path.join("/home", "me", "ermine-writers", "writers", "html", "src", "main", "resources", "web"), source: "default", problem: null },
      JSON.stringify(empty));
  }
  const nul = core.previewWritersDir("we\u0000b", base, "/r");
  assert.strictEqual(nul.dir, null);
  assert.match(nul.problem, /^ermine\.preview\.writersPath entry .* contains a NUL byte/);
  const rel = core.previewWritersDir("web", undefined, "/r");
  assert.strictEqual(rel.dir, null);
  assert.match(rel.problem, /^ermine\.preview\.writersPath entry "web" is relative and there is no workspace folder/);
  assert.match(core.previewWritersDir(7, base, "/r").problem, /ermine\.preview\.writersPath is a directory path, not a number/);
  // WP-11 review N3: the article follows the type name ("an array", "an object").
  assert.strictEqual(core.previewWritersDir(["web"], base, "/r").problem, "ermine.preview.writersPath is a directory path, not an array");
  assert.strictEqual(core.previewWritersDir({}, base, "/r").problem, "ermine.preview.writersPath is a directory path, not an object");
  // the roots' own wording is unchanged by the new parameter
  assert.match(core.absoluteRoots([" "], "/w").problems[0], /^ermine\.preview\.roots has an empty entry/);
});

test("panel S4 (roots): localResourceRoots gains the writers folder exactly when the page loads from it -- at most two entries", () => {
  const b = "/w/client/dist/browser";
  assert.deepStrictEqual(core.previewResourceRoots(b, s4Check(WRITERS_OK).root), [b, "/wr/web"]);
  assert.deepStrictEqual(core.previewResourceRoots(b, s4Check(["htmlwriter.js"]).root), [b, "/wr/web"]);
  assert.deepStrictEqual(core.previewResourceRoots(b, s4Check(null).root), [b]);
  assert.deepStrictEqual(core.previewResourceRoots(b, s4Check(["common.css"]).root), [b]);
  // every URI the page references lies under one of those roots
  for (const listing of [WRITERS_OK, ["htmlwriter.js", "common.css"], null]) {
    const w = s4Check(listing);
    const roots = core.previewResourceRoots(b, w.root);
    const refs = [];
    core.previewPageUris(S4_SRC, s4Bundle(), w, (dir, file) => { refs.push(path.join(dir, file)); return "u"; });
    for (const r of refs) assert.ok(roots.some((root) => r.startsWith(root + path.sep)), r + " outside " + JSON.stringify(roots));
  }
});

test("panel S4 (banner): the writers sentence is the reducer's `error` -- alone after a good answer, a suffix on a failed one, absent when present", () => {
  const missing = s4Check(null);
  const half = s4Check(["htmlwriter.js"]);
  const okView = (writers, extra) => panelAfter([answerOutcome("ok-wpint")], Object.assign({ writers }, extra || {}));
  // present: the S1-S3 stream, unchanged
  assert.deepStrictEqual(core.panelMessagesFor(okView(s4Check(WRITERS_OK))), core.panelMessagesFor(okView(null)));
  // missing / half: ONE error after the render, status 0, no path, the check's own sentence
  for (const w of [missing, half]) {
    const msgs = core.panelMessagesFor(okView(w));
    assert.deepStrictEqual(kinds(msgs), ["render", "error", "stale", "stuck", "held", "offline", "switching", "unsaved"]);
    assert.deepStrictEqual(msgs[1], { kind: "error", status: 0, message: w.message, path: null, reason: null });
  }
  // before any render: the banner alone (it replaces "Pick a report")
  const bare = core.panelMessagesFor(core.panelView({ writers: missing }));
  assert.deepStrictEqual(kinds(bare), ["error", "stale", "stuck", "held", "offline", "switching", "unsaved"]);
  // a FAILED answer keeps the one error slot; the writers sentence rides on it, after the fast-mode suffix
  const failed = core.panelMessagesFor(panelAfter([{ current: 1, outcome: { answer: Object.assign({}, ERR_500, { generation: 1 }) } }],
    { writers: missing, fastMode: true }));
  const errs = failed.filter((x) => x.kind === "error");
  assert.strictEqual(errs.length, 1, "one error message, never two");
  assert.strictEqual(errs[0].status, 500);
  assert.strictEqual(errs[0].message, ERR_500.message + core.FAST_MODE_SUFFIX + core.WRITERS_NOTE_SEPARATOR + missing.message);
  // the view keeps only {state, message}, and only when not present
  assert.deepStrictEqual(core.panelView({ writers: missing }).writers, { state: "missing", message: missing.message });
  assert.strictEqual(core.panelView({ writers: s4Check(WRITERS_OK) }).writers, null);
  assert.strictEqual(core.panelView({}).writers, null);
  assert.strictEqual(core.panelView({ writers: { state: "missing", message: "  " } }).writers, null, "a blank sentence is no banner");
  // no tenth kind, ever
  for (const w of [missing, half, null]) {
    for (const m of core.panelMessagesFor(okView(w))) assert.ok(core.PANEL_MESSAGE_KINDS.indexOf(m.kind) >= 0, m.kind);
  }
});

test("panel S4 (recheck): an explicit command re-checks a page built without the whole writers, and re-sets it only when the checks differ", () => {
  const ok = s4Bundle();
  const notBuilt = core.previewBundleCheck("/w/client/dist/browser", null);
  const P = s4Check(WRITERS_OK), M = s4Check(null), H = s4Check(["htmlwriter.js"]);
  assert.strictEqual(core.panelRecheck(ok, P), false, "a working page with the writers is never reloaded by a command");
  for (const [b, w] of [[ok, M], [ok, H], [notBuilt, P], [null, P], [ok, null]]) assert.strictEqual(core.panelRecheck(b, w), true);
  assert.strictEqual(core.panelReload(ok, M, ok, P), true, "missing -> present: the page gains the writers");
  assert.strictEqual(core.panelReload(ok, H, ok, P), true);
  assert.strictEqual(core.panelReload(ok, M, ok, s4Check(null)), false, "still missing, same folder: no reload per command");
  assert.strictEqual(core.panelReload(ok, M, ok, s4Check(null, "/other/web")), true, "the setting moved: a new sentence");
  assert.strictEqual(core.panelReload(notBuilt, P, ok, M), true, "the bundle came back: the page, whatever the writers");
  assert.strictEqual(core.panelReload(ok, M, notBuilt, P), false, "never swap a page for a notice on a command");
  assert.strictEqual(core.panelReload(notBuilt, M, notBuilt, P), false);
});

/** A model opened by an explicit render and loaded, then one more explicit render. */
async function s4Explicit(m, note) {
  const r = m.renderNow(true);
  await flush();
  m.answer(m.wires.length - 1, OK_DOC(note));
  await r;
}
const s4Error = (env) => env.messages.filter((x) => x.kind === "error");

test("panel S4 model (missing): the page loads WITHOUT the writers, ONE channel line, and the banner is the snapshot's error", async () => {
  const m = panelGlueModel({ writersListing: ["common.css", "htmlwriter.css", "htmlwriter_classic.css"] });
  const p = await s3OpenReady(m, "a");
  assert.strictEqual((p.webview.html.match(/<script/g) || []).length, 2, "client and host only");
  assert.ok(!/htmlwriter/.test(p.webview.html) && !/<link/.test(p.webview.html));
  const lines = m.logs.filter((l) => /legacy writers/.test(l));
  assert.strictEqual(lines.length, 1, m.logs.join("\n"));
  assert.match(lines[0], /^preview: the legacy writers are not loaded: no htmlwriter\.js in \/ermine-writers\/writers\/html\/src\/main\/resources\/web \(ermine\.preview\.writersPath is empty/);
  const errs = s4Error(p.last());
  assert.strictEqual(errs.length, 1);
  assert.strictEqual(errs[0].message, lines[0].slice("preview: ".length));
  assert.strictEqual(p.last().messages[0].document.root.note, "a", "the document is still sent below the banner");
  assert.deepStrictEqual(p.last().messages, m.truth());
});

test("panel S4 model (present / half): the writers load first with their sheets; present is silent, half says what is missing", async () => {
  const m = panelGlueModel();
  const p = await s3OpenReady(m, "a");
  assert.match(s4Scripts(p.webview.html)[0], /\/ermine-writers\/writers\/html\/src\/main\/resources\/web\/htmlwriter\.js\)?"><\/script>$/);
  assert.strictEqual(s4Links(p.webview.html).length, 3);
  assert.deepStrictEqual(s4Error(p.last()), []);
  assert.ok(!m.logs.some((l) => /legacy writers/.test(l)), "a present folder writes no line");
  const h = panelGlueModel({ writersListing: ["htmlwriter.js", "common.css"] });
  const ph = await s3OpenReady(h, "a");
  assert.strictEqual(s4Links(ph.webview.html).length, 1);
  assert.match(s4Error(ph.last())[0].message, /style sheets are incomplete/);
  assert.strictEqual(h.logs.filter((l) => /legacy writers/.test(l)).length, 1);
});

test("panel S4 model (fixed): the writers folder is NOT watched -- a fixed path is picked up by the NEXT explicit command, once", async () => {
  const m = panelGlueModel({ writersListing: null });
  const p = await s3OpenReady(m, "a");
  assert.strictEqual(s4Error(p.last()).length, 1);
  assert.strictEqual(liveWatchers(m).length, 1, "the bundle folder only");
  m.writersListing = WRITERS_OK.slice();              // the developer fixes the path (or checks the writers out)
  m.setPreviewStatus();                               // a status post changes nothing: not watched
  assert.strictEqual(p.htmls.length, 1);
  await s4Explicit(m, "b");
  assert.strictEqual(p.htmls.length, 2, "the explicit command re-set the page");
  assert.match(p.webview.html, /htmlwriter\.js/);
  p.loadPage();
  assert.deepStrictEqual(s4Error(p.last()), [], "the banner is gone");
  assert.strictEqual(p.last().messages[0].document.root.note, "b");
  await s4Explicit(m, "c");
  assert.strictEqual(p.htmls.length, 2, "a working page is never reloaded by a command");
  assert.strictEqual(liveWatchers(m).length, 1);
});

test("panel S4 model (still missing): a machine with no writers is NOT reloaded on every command", async () => {
  const m = panelGlueModel({ writersListing: null });
  const p = await s3OpenReady(m, "a");
  for (const n of ["b", "c", "d"]) await s4Explicit(m, n);
  assert.strictEqual(p.htmls.length, 1);
  assert.strictEqual(m.logs.filter((l) => /legacy writers/.test(l)).length, 1, "one line per page built, not per command");
});

test("panel S4 model (bundle rebuild): a reload re-checks the writers too, and the new page's ready carries the banner's new state", async () => {
  const m = panelGlueModel({ writersListing: null });
  const p = await s3OpenReady(m, "a");
  m.writersListing = WRITERS_OK.slice();
  m.build();
  m.tick(Q + 10);
  assert.strictEqual(m.reloads, 1);
  assert.match(p.webview.html, /htmlwriter\.js/);
  p.loadPage();
  assert.deepStrictEqual(s4Error(p.last()), []);
  m.writersListing = null;
  m.build();
  m.tick(Q + 10);
  p.loadPage();
  assert.ok(!/htmlwriter\.js/.test(p.webview.html));
  assert.strictEqual(s4Error(p.last()).length, 1);
});

test("panel S4 model MUTANTS: no writers re-check, a reload per command, the banner left out of the view", async () => {
  {
    const m = panelGlueModel({ writersListing: null, mutantNoWritersRecheck: true });
    const p = await s3OpenReady(m, "a");
    m.writersListing = WRITERS_OK.slice();
    await s4Explicit(m, "b");
    assert.strictEqual(p.htmls.length, 1, "MUTANT: the fixed path is never picked up by a command");
  }
  {
    const m = panelGlueModel({ writersListing: null, mutantReloadEveryCommand: true });
    const p = await s3OpenReady(m, "a");
    await s4Explicit(m, "b");
    assert.strictEqual(p.htmls.length, 2, "MUTANT: the page is reloaded although nothing changed");
  }
  {
    const m = panelGlueModel({ writersListing: null, mutantViewNoWriters: true });
    const p = await s3OpenReady(m, "a");
    assert.deepStrictEqual(s4Error(p.last()), [], "MUTANT: the page loads without the writers and says nothing");
  }
});

test("glue pins (WP-11) the writers -- ONE localResourceRoots list of at most two entries, the setting through the roots' absolutiser, the output line", () => {
  const { src, pin, body, count } = s2Glue();
  assert.strictEqual(count(/localResourceRoots:/g, src), 1, pin("localResourceRoots is set other than in one place", "one list"));
  const opts = body("function panelOptions(", "function setPanelHtml(");
  assert.ok(/localResourceRoots: core\.previewResourceRoots\(bundle\.dir, writers\.root\)\.map\(\(p\) => vscode\.Uri\.file\(p\)\),/.test(opts),
    pin("localResourceRoots is not exactly [bundle dir, writers root]", "the page may load the writers (and nothing else)"));
  // the definition and its three calls (openPanel's two branches, reloadBundle)
  assert.strictEqual(count(/panelOptions\(bundle, writers\)/g, src), 4, pin("a panelOptions call does not pass the writers check", "every page's roots include the folder it loads"));
  assert.strictEqual(count(/panelOptions\(/g, src), 4, pin("panelOptions is called from somewhere new", "the same"));
  const check = body("function checkPreviewWriters(", "function panelOptions(");
  assert.ok(/const where = core\.previewWritersDir\(config\(\)\.get\("preview\.writersPath", ""\), workspaceRoot\(\), server && server\.root\);/.test(check),
    pin("the setting is not read through core.previewWritersDir (the roots' absolutiser) with the workspace folder and the server root", "U3"));
  assert.ok(/if \(where\.dir\) \{\s*try \{\s*listing = fs\.readdirSync\(where\.dir\);/.test(check) && /return core\.previewWritersCheck\(where, listing\);\s*\}\s*$/.test(check),
    pin("the writers check is not the pure check over a listing", "fail-closed on htmlwriter.js"));
  // the definition and its three calls
  assert.strictEqual(count(/checkPreviewWriters\(\)/g, src), 4, pin("checkPreviewWriters is called other than from openPanel's two branches and reloadBundle", "the writers are NOT watched"));
  assert.strictEqual(body("function watchBundle(", "function unwatchBundle(").indexOf("Writers"), -1, pin("the bundle watcher touches the writers", "not watched"));
  const html = body("function setPanelHtml(", "function openPanel(");
  assert.ok(/panelWriters = writers;\s*panelBundle = bundle;\s*panelReady = false;/.test(html),
    pin("setPanelHtml does not store the writers check beside the bundle check", "the banner is the check the page was built from"));
  assert.ok(/return;\s*\}\s*const writersNote = core\.writersLine\(writers\);\s*if \(writersNote\) log\(writersNote\);\s*const uriOf =/.test(html),
    pin("the page built without the whole writers does not write its ONE channel line", "the output line"));
  assert.strictEqual(count(/core\.writersLine\(/g, src), 1, pin("the writers line is written from somewhere else too", "one line per page"));
  assert.ok(/const uriOf = \(dir, file\) => panel\.webview\.asWebviewUri\(vscode\.Uri\.file\(path\.join\(dir, file\)\)\)\.toString\(\);/.test(html),
    pin("the page URIs are not asWebviewUri of the files", "the webview may load them"));
  assert.strictEqual(count(/setPanelHtml\([a-zA-Z]+, bundle, writers\);/g, src), 3, pin("a setPanelHtml call does not pass the writers", "every page is built with the writers check"));
  assert.ok(/writers: panelWriters,/.test(body("function panelViewNow(", "function postSnapshot(")), pin("the view does not carry the writers", "the banner"));
});

test("model = glue (WP-11): the model's view builder passes EXACTLY the glue's fields, and the same value wherever the two can be compared", () => {
  const fsMod = require("node:fs");
  const { body } = s2Glue();
  const glue = body("function panelViewNow(", "function postSnapshot(");
  const self = codeOf(fsMod.readFileSync(__filename, "utf8"));
  const i = self.indexOf("m.viewNow = () => core.panelView({");
  const j = self.indexOf("});", i);
  assert.ok(i >= 0 && j > i, "the model's viewNow is where this test expects it");
  const model = self.slice(i, j);
  const fields = (text) => (text.match(/^\s*[a-zA-Z]+[:,][^\n]*$/gm) || []).map((l) => l.trim());
  const g = fields(glue), mm = fields(model);
  const key = (l) => l.split(/[:,]/)[0];
  assert.deepStrictEqual(mm.map(key), g.map(key), "the model passes a field the glue does not, or omits one it passes");
  // where the glue reads a global the model holds as m.<same name>, the text must match after `m.` goes
  const LEGIT = {                                    // the glue's global -> the model's, and why
    "stuckState,": "stuckState: m.stuckState,",
    "mark: wedgeMark,": "mark: m.mark,",
    "pick: picked,": "pick: m.picked,",
    "restartedByUs: core.restartedByUs(restartState),": "restartedByUs: core.restartedByUs(m.restartState),",
    "pending: renderInFlight || coalesceTimer !== undefined,": "pending: m.renderInFlight || m.coalescing,",
    'fastMode: config().get("fastMode", false) === true,': "fastMode: m.fastMode === true,",
    "reloading: core.bundleReloading(bundleWatch),": "reloading: core.bundleReloading(m.bundleWatch),",
    "writers: panelWriters,": "writers: o.mutantViewNoWriters ? null : m.panelWriters,",
  };
  g.forEach((line, n) => {
    if (Object.prototype.hasOwnProperty.call(LEGIT, line)) assert.strictEqual(mm[n], LEGIT[line], "field " + key(line));
    else assert.strictEqual(mm[n].replace(/\bm\./g, ""), line, "field " + key(line) + ": the model's value is not the glue's");
  });
});

// ------------------------------------------- WP-34: a report with no parameters
//
// Q27 option (i), decided 2026-09-24: a binding typed `Node` or `Fetch Node`
// is a report with NO parameters. The runner renders it with `{}` or with no
// `params` and refuses any key; `ermine/schema` answers the marker
// `{"parameters": false}` (`json/Runner.scala`'s `Runner.NoParameters`),
// MEASURED from one bin/ermine-lsp boot on `Doc/SalesReport.e` (WP-34's
// IMPL-REPORT). The extension writes NOTHING for it and says no "no params
// file" line about it.

const NO_PARAMETERS = { parameters: false };
const SALES_REPORT_PICK = core.makePick(
  "file:///w/doc/SalesReport.e", "/w/doc/SalesReport.e", "report", "Doc.SalesReport", ["/w/doc"]);

test("WP-34: the marker is read as 'no parameters', and ONLY the exact marker", () => {
  const out = core.schemaAnswerOutcome(NO_PARAMETERS);
  assert.deepStrictEqual(out, { schema: null, problem: null, abandoned: null, noParameters: true });
  assert.strictEqual(core.isNoParametersAnswer(NO_PARAMETERS), true);
  // a real schema, even one that happens to mention the word, is a schema
  for (const schema of [SALES_SCHEMA, { parameters: false, type: "object" }, { parameters: "false" },
                        { parameters: true }, { type: "object", properties: {}, additionalProperties: false }]) {
    assert.strictEqual(core.isNoParametersAnswer(schema), false, JSON.stringify(schema));
    const o = core.schemaAnswerOutcome(schema);
    assert.strictEqual(o.noParameters, false, JSON.stringify(schema));
    assert.deepStrictEqual(o.schema, schema);
  }
  // an error beside it is still an error: the failure shape wins
  assert.strictEqual(core.schemaAnswerOutcome({ error: "boom", parameters: false }).problem.reason, "error");
  for (const junk of [null, undefined, 7, [], "x"]) assert.strictEqual(core.isNoParametersAnswer(junk), false);
  assert.match(core.noParametersNotice("Doc.SalesReport.report"),
               /^Doc\.SalesReport\.report takes no parameters, so no params file is written/);
});

test("WP-34: the 'no params file' line is held exactly while the schema may say 'no parameters'", () => {
  const paths = core.paramsPaths(SALES_REPORT_PICK, "/w");
  assert.ok(paths && !paths.problem, JSON.stringify(paths));
  const missing = core.preparedParams(paths, { kind: core.PREPARED_MISSING });
  const read = core.preparedParams(paths, { kind: core.PREPARED_READ, params: {}, warnings: [] });
  const noPath = core.preparedParams({ problem: { reason: "outside", message: "x" } },
                                     { kind: core.PREPARED_PATH_PROBLEM });
  // [prepared, tried, knownNoParameters] -> held?
  const table = [
    [missing, false, false, true],    // the first-pick branch is about to ask
    [missing, true,  false, false],   // it asked and the answer was not the marker
    [missing, true,  true,  true],    // known: never said
    [missing, false, true,  true],
    [read,    false, false, false],   // no notice at all
    [read,    false, true,  false],
    [noPath,  false, false, false],   // a path problem's notice is said as before
    [noPath,  false, true,  false],
  ];
  for (const [p, tried, known, want] of table) {
    assert.strictEqual(core.holdsParamsNotice(p, tried, known), want,
                       JSON.stringify([p.notice && p.notice.reason, tried, known]));
  }
  // the second arm is `schemaOrder`'s own condition
  assert.strictEqual(core.schemaOrder(missing.paths, true).first, "schema");
  for (const junk of [undefined, null, 7, {}]) assert.strictEqual(core.holdsParamsNotice(junk, false, false), false);
});

/** A first pick of `Doc.SalesReport.report` through the S3 model, answered
  * with the marker; the render that follows is answered ok. */
async function zeroParamFirstPick(opts) {
  const m = firstPickModel(opts);
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  m.answerSchema(0, NO_PARAMETERS);
  await flush();
  return m;
}

test("WP-34 ASYNC: the first pick of a zero-parameter report writes NOTHING and renders with {}", async () => {
  const m = await zeroParamFirstPick();
  assert.strictEqual(m.schemas.length, 1, "one ermine/schema");
  assert.strictEqual(m.disk.files.size, 0, "no params file, no schema file, no .gitignore");
  assert.deepStrictEqual(m.disk.creates, []);
  assert.deepStrictEqual(m.disk.writes, []);
  assert.deepStrictEqual(m.opened, [], "no params document is opened");
  assert.deepStrictEqual(m.notices.map((n) => n.reason), ["no-parameters"]);
  assert.deepStrictEqual(m.paramsNotices, [], "and NO 'no params file ... write one' line");
  assert.strictEqual(m.scheduled.length, 0, "nothing was written, so nothing is scheduled");
  assert.strictEqual(m.sent.length, 1, "THIS render goes, with the inline {}");
  assert.deepStrictEqual(m.sent[0].params, {});
  assert.strictEqual(m.reveals[0].reveal, true, "and the tab the pick asked for is revealed");
  m.answerWith(0, { ok: true, generation: m.generation, document: { version: 1, root: {} } });
  await flush();

  // A later render (a save): no second schema, still no line, still `{}`.
  m.renderNow("invalidated", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readMissing(1);
  await flush();
  assert.strictEqual(m.schemas.length, 1, "it is not asked again");
  assert.deepStrictEqual(m.paramsNotices, [], "and the line is never said for it");
  assert.strictEqual(m.sent.length, 2);
  assert.deepStrictEqual(m.sent[1].params, {});
});

test("WP-34 ASYNC: a report WITH parameters whose schema fails still hears the 'no params file' line, once", async () => {
  const m = firstPickModel();
  m.renderNow("the report was picked", true, core.TRIGGER_EXPLICIT);
  await flush();
  m.readMissing(0);
  await flush();
  assert.deepStrictEqual(m.paramsNotices, [], "held while the schema is asked");
  m.answerSchema(0, { error: "boom" });
  await flush();
  assert.deepStrictEqual(m.paramsNotices, ["missing"], "said once the answer is known not to be the marker");
  assert.strictEqual(m.sent.length, 1);
  m.answerWith(0, { ok: true, generation: m.generation, document: {} });
  await flush();
  m.renderNow("invalidated", false, core.TRIGGER_INVALIDATED);
  await flush();
  m.readMissing(1);
  await flush();
  assert.deepStrictEqual(m.paramsNotices, ["missing", "missing"],
                         "and at the read of every later render, as before (the glue's once-per-pick dedupe is " +
                         "paramsNoticeOnce's)");
});

test("WP-34 ASYNC: the D8 refresh of a zero-parameter report with a hand-made params file writes no schema file", async () => {
  const disk = diskModel({ files: [["/w/.ermine/preview/Sales/report.params.json", "{}"]] });
  const m = firstPickModel({ disk });
  const attempt = core.renderAttempt(m.generation, m.picked, m.clientEpoch, m.stopCount, 0);
  const done = m.refreshSchemaFile(attempt, SALES_PATHS, "test");
  await flush();
  m.answerSchema(0, NO_PARAMETERS);
  await done;
  assert.deepStrictEqual(disk.writes, [], "no <binding>.schema.json from the marker");
  assert.strictEqual(disk.read("/w/.ermine/preview/Sales/report.schema.json"), null);
  assert.deepStrictEqual(m.notices.map((n) => n.reason), ["refresh-no-parameters"]);
});

test("WP-34 MUTANT: reading the marker as a schema (0.1.15's behaviour) writes a params skeleton", async () => {
  const m = await zeroParamFirstPick({ mutantNoParamsAsSchema: true });
  assert.ok(m.disk.creates.length > 0,
            "the mutant must write something, or the WP-34 test above is vacuous: " + JSON.stringify(m.disk.creates));
  assert.ok(m.disk.creates.some((p) => /report\.params\.json$/.test(p)), JSON.stringify(m.disk.creates));
});

test("WP-34 MUTANT: never holding the line says 'write a params file' about a report that takes none", async () => {
  const m = await zeroParamFirstPick({ mutantNeverHoldNotice: true });
  assert.deepStrictEqual(m.paramsNotices, ["missing"], "the mutant says the false line");
});

test("glue pins (WP-34): every ermine/schema consumer handles the marker, and the line is held", () => {
  const fsMod = require("node:fs");
  const src = codeOf(fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8"));
  const pin = (what, fix) =>
    "source pin (test/preview-core.test.js): extension.js changed shape — " + what +
    ". If you meant it, update this pin; the behaviour it protects is " + fix;
  const body = (from, to) => src.slice(src.indexOf(from), src.indexOf(to, src.indexOf(from) + 1));
  const first = body("async function firstPickSchemaAndWrite(", "async function refreshSchemaFile(");
  const refresh = body("async function refreshSchemaFile(", "async function refreshSchemaFor(");
  const command = body("async function writeSkeletonNow(", "\nasync function ");
  const why = "WP-34: a report with no parameters gets no params file, no schema file and no skeleton";
  for (const [name, text] of [["firstPickSchemaAndWrite", first], ["refreshSchemaFile", refresh],
                              ["writeSkeletonNow", command]]) {
    const at = text.indexOf("if (outcome.noParameters)");
    const problem = text.indexOf("if (outcome.problem)");
    assert.ok(at > 0 && problem > 0 && at > problem, pin(name + " no longer returns on outcome.noParameters, " +
                                                     "right after the problem arm", why));
    assert.ok(at < text.indexOf("outcome.schema") || text.indexOf("outcome.schema") < 0,
              pin(name + " reads outcome.schema before the noParameters arm", why));
  }
  assert.ok(/return core\.firstPickResult\(\{ noParameters: true \}\);/.test(first),
            pin("the first pick does not report noParameters to renderNow", why));
  const renderBody = src.slice(src.indexOf("async function renderNow("), src.indexOf("async function showAnswer("));
  const held = renderBody.indexOf("const heldNotice = core.holdsParamsNotice(prepared, firstPickTried.has(attempt.key),");
  const said = renderBody.indexOf("if (prepared.notice && !heldNotice) paramsNoticeOnce(");
  const learn = renderBody.indexOf("if (written.noParameters) noParametersPicks.add(attempt.key);");
  const late = renderBody.indexOf("if (heldNotice && !noParametersPicks.has(attempt.key)) {");
  const latch = renderBody.indexOf("inFlightRender = {");
  assert.ok(held > 0 && said > held && learn > said && late > learn && late < latch,
            pin("renderNow's held 'no params file' line is not held, learned and said in that order before the wire",
                "WP-34: no advice to write a params file for a report that takes none"));
  assert.ok(/noParametersPicks = new Set\(\);\s*schemaNotices = new Set\(\);/.test(
              body("function forgetSchemaAttempts(", "\n}")),
            pin("forgetSchemaAttempts no longer forgets noParametersPicks",
                "that a report which GAINS a parameter is asked about again"));
});

test("WP-34 ASYNC (review M1): Write Params Skeleton on a zero-parameter report writes NOTHING and says so", async () => {
  const run1 = async (opts, withFile) => {
    const disk = withFile ? diskModel({ files: [[PARAMS_PATH, COMMITTED]] }) : diskModel();
    const m = commandModel(Object.assign({ disk }, opts));
    const run = m.writeParamsSkeleton();
    await flush();
    if (withFile) { m.answerModal(0, core.SKELETON_REPLACE); await flush(); }
    m.answerSchema(0, NO_PARAMETERS);
    const result = await run;
    return { m, disk, result };
  };
  for (const withFile of [false, true]) {
    const what = withFile ? "with a params file" : "with no params file";
    const { m, disk, result } = await run1({}, withFile);
    assert.strictEqual(result.wrote, false, what);
    assert.strictEqual(result.problem.reason, "no-parameters", what);
    assert.strictEqual(result.problem.message, core.noParametersNotice(m.picked ? core.renderAttempt(
      m.generation, m.picked, m.clientEpoch, m.stopCount, 0).label : ""), what);
    assert.match(result.problem.message, /takes no parameters/, what);
    assert.deepStrictEqual(disk.writes, [], what + ": nothing written");
    assert.deepStrictEqual(disk.creates, [], what + ": nothing created");
    if (withFile) assert.strictEqual(disk.read(PARAMS_PATH), COMMITTED, what);
    assert.deepStrictEqual(m.opened, [], what + ": nothing opened");
    assert.deepStrictEqual(m.scheduled, [], what + ": nothing scheduled");
    assert.strictEqual(m.messages.length, 1, what + ": said once");
  }
  // the mutant (the arm deleted) says the false "not a JSON object" sentence
  const mut = await run1({ mutantNoCommandNoParamsArm: true }, false);
  assert.notStrictEqual(mut.result.problem && mut.result.problem.reason, "no-parameters",
                        "the mutant must be visible to this test");
  assert.ok(!/takes no parameters/.test(mut.m.messages.join(" ")), mut.m.messages.join(" "));
});
