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

function deferred() {
  let settle;
  const promise = new Promise((resolve) => { settle = resolve; });
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
// builtins :327-339), `core/src/test/resources/doc/Sales.e:53-63` and the
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
  // (Sales.e:53), which is what `enum`'s member order is (Schema.scala:527).
  assert.strictEqual(SALES_SCHEMA.$defs["Sales.Sort"].enum[0], "ByDay");
  // U2/D4, said out loud: TODAY selects NONE of Sales's 2026-01-05..2026-03-17
  // rows. What the server then answers was MEASURED by the S1 review against a
  // real render, and it is NOT an empty document -- it is
  //   ok=false, status=500, "Sales.report produced a document that cannot be
  //   encoded: an empty relation built from no rows carries no columns; give it
  //   a header (mkRelationWithHeader#) or a static hint"
  //   at $.children[1].cells[0][0].props
  // and the same review's controls show the skeleton itself DECODES: a
  // wrong-typed date and a missing key each earn a 400 naming the key, and the
  // gate's in-range params render ok=true. So this is a property of `Sales.e`
  // and of empty relations, not of the skeleton. What to do about it is the
  // USER'S -- section 13, Q21 -- and WP-8's first done-when clause is BLOCKED
  // on that answer. The assertion below is the part that is true and stays.
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
  // `docs/JSON-GUIDE.md:1295-1297`: a `Maybe`-rooted report wants null, and
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
  assert.match(core.paramsWrittenNotice(paths, false), /no "\$schema" line/);
  assert.match(core.paramsWrittenNotice(paths, false), /editor will not validate/);
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
  m.opened = [];             // U2
  m.notices = [];
  m.firstPickTried = new Set();
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
    const still = o.mutantNoSchemaGap
      ? { send: true }
      : core.mayUseSchemaAnswer(
          attempt,
          core.previewNow(m.generation, m.picked, m.clientEpoch, m.stopCount, m.hasClient),
          m.picked);
    if (!still.send) return core.schemaAbandoned(still);
    return core.schemaAnswerOutcome(reply);
  };

  /** `applyWritePlan(files, paramsPath)`, statement for statement. */
  m.applyWritePlan = function (files, paramsPath) {
    const wrote = [];
    const problems = [];
    for (const file of files) {
      // M-2: a PURE decision, and it fails CLOSED. The mutant is the
      // fail-OPEN `else` the first cut shipped.
      const step = o.mutantParamsOverwrite
        ? { act: file.mode === core.WRITE_IF_ABSENT ? "MUTANT" : core.WRITE_IF_DIFFERENT, problem: null }
        : core.writeStep(file, paramsPath);
      if (step.problem) {
        problems.push(step.problem);
        if (file.what === core.WRITE_PARAMS) return core.writeOutcome({ wrote, problems });
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
    notice("written", core.paramsWrittenNotice(paths, plan.embeddable));
    m.opened.push(paths.paramsPath);
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
 */
function codeOf(text) {
  return String(text).replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
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
  assert.ok(order > consult && write > order && write < latch,
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
  assert.strictEqual((src.match(/applyWritePlan\(/g) || []).length, 2,
    pin("applyWritePlan has more than its definition and one caller", "the same"));
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
  assert.strictEqual((src.match(/writeTextFile\(/g) || []).length, 3,
    pin("writeTextFile — the OVERWRITING primitive — has call sites other than its definition, " +
        "the create's zero-byte branch and writeIfDifferent",
        "that the only unconditional write in this extension is over zero bytes or over a " +
        "generated file whose bytes differ"));

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
  assert.ok(/async function applyWritePlan\(files, paramsPath\) \{/.test(applyBody),
    pin("applyWritePlan no longer takes the params path", "the same (M-2)"));
  assert.ok(/const step = core\.writeStep\(file, paramsPath\);/.test(applyBody) &&
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
  assert.strictEqual((src.match(/await symlinkProblem\(/g) || []).length, 2,
    pin("the symlink check is gone from one of the two write paths",
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
  assert.ok(/if \(applied\.wrote\.indexOf\(core\.WRITE_PARAMS\) < 0\) return core\.firstPickResult\(\{\}\);/.test(firstPickBody) &&
            firstPickBody.indexOf("openParamsDocument(paths.paramsPath)") >
            firstPickBody.indexOf("core.paramsWrittenNotice(paths, plan.embeddable)"),
    pin("the params document is opened, or announced, for a file this branch did not write",
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
  assert.ok(/openedParamsFiles\.has\(fsPath\)/.test(openBody) && /openedParamsFiles\.add\(fsPath\)/.test(openBody),
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
                         { schema: null, problem: null, abandoned: { reason: "pick-changed", why: "x" } });
  assert.strictEqual(core.schemaAbandoned(undefined).abandoned.reason, "pick-cleared");
  // D-1's builder audit: the two shapes that were still raw literals on BOTH
  // sides, which is M-1's class once more.
  assert.deepStrictEqual(core.firstPickResult({}), { wrote: false, raced: false, abandoned: false });
  assert.deepStrictEqual(core.firstPickResult({ wrote: true, raced: true }),
                         { wrote: true, raced: true, abandoned: false });
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
  const src = fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
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
  const src = fsMod.readFileSync(path.join(__dirname, "..", "src", "extension.js"), "utf8");
  const body = src.slice(src.indexOf("async function refreshSchemaFile("),
                         src.indexOf("async function refreshSchemaFor("));
  assert.ok(body.indexOf("if (outcome.abandoned)") < body.indexOf("await symlinkProblem("),
    "source pin: the refresh acts on a stale answer before it checks anything");
  assert.ok(body.indexOf("if (outcome.abandoned)") < body.indexOf("writeIfDifferent("),
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
