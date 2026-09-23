// The panel page's snapshot fold (WP-10 stage 1; `client/src/host/page.ts`),
// and H7 of the WP-10 design review against the REAL extension-side builders.
//
// Two halves:
//   (pg-*)   the page module alone: a snapshot folds from a FRESH state, equals
//            the same messages applied one at a time, and REPLACES whatever the
//            panel had -- over random sequences of all nine kinds;
//   (pg-h7-*) `editor/vscode/src/preview-core.js` driven by a model of the
//            extension's module globals (every transition through the real
//            reducers: panelAnswerStep, stuckReduce, guardReduce, panelView),
//            its `panelMessagesFor` output folded through the real
//            `applyMessage`.  That is the only place the two languages meet,
//            so it is where the snapshot rule is proved to hold.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as path from "node:path";
import * as fs from "node:fs";
import fc from "fast-check";

import {
  foldSnapshot, receive, applyMessage, initialHostState, presentation, MESSAGE_KINDS,
  type HostMessage, type HostState, type PanelEnvelope,
} from "../src/host/page";
import * as hostIndex from "../src/host/index";
import * as pageModule from "../src/host/page";

// The extension's pure core, plain CommonJS with no dependencies.  Found by
// walking up from this file, so the test runs from `dist/test/` (compiled) and
// would from `test/` too.
function findCore(): string {
  let dir = __dirname;
  for (let i = 0; i < 6; i++) {
    const p = path.join(dir, "editor", "vscode", "src", "preview-core.js");
    if (fs.existsSync(p)) return p;
    dir = path.dirname(dir);
  }
  throw new Error("editor/vscode/src/preview-core.js not found above " + __dirname);
}
// eslint-disable-next-line @typescript-eslint/no-require-imports
const core = require(findCore());

const doc = { version: 1, settings: {}, root: { tag: "VFlow", children: [] } };

// ------------------------------------------------------------- page alone

const messageArb: fc.Arbitrary<HostMessage> = fc.oneof(
  fc.record({ kind: fc.constant("render" as const), document: fc.constant(doc), generation: fc.integer({ min: 0, max: 50 }) }),
  fc.record({
    kind: fc.constant("error" as const),
    status: fc.constantFrom(400, 404, 409, 500, 503),
    message: fc.string({ maxLength: 20 }),
    path: fc.option(fc.string({ maxLength: 12 }), { nil: null }),
  }),
  fc.record({ kind: fc.constant("stale" as const), stale: fc.boolean() }),
  fc.record({ kind: fc.constant("stuck" as const), stuck: fc.boolean(), message: fc.string({ maxLength: 20 }), seq: fc.integer({ min: 1, max: 20 }) }),
  fc.record({ kind: fc.constant("held" as const), held: fc.boolean(), message: fc.string({ maxLength: 20 }) }),
  fc.record({ kind: fc.constant("offline" as const), offline: fc.boolean() }),
  fc.record({ kind: fc.constant("switching" as const), to: fc.option(fc.string({ maxLength: 8 }), { nil: null }) }),
  fc.record({ kind: fc.constant("unsaved" as const), names: fc.array(fc.string({ maxLength: 8 }), { maxLength: 3 }) }),
  fc.record({ kind: fc.constant("reloadBundle" as const) }),
);

test("(pg-arb-covers) the generator draws all nine kinds", () => {
  const seen = new Set(fc.sample(messageArb, { numRuns: 2000, seed: 7 }).map((m) => m.kind));
  assert.deepStrictEqual([...seen].sort(), [...MESSAGE_KINDS].sort());
});

test("(pg-snapshot-equals-incremental) a snapshot's fold equals the same messages received one by one", () => {
  fc.assert(fc.property(fc.array(messageArb, { maxLength: 30 }), (msgs) => {
    const incremental = msgs.reduce<HostState>((s, m) => receive(s, m), initialHostState());
    assert.deepStrictEqual(foldSnapshot(msgs), incremental);
    assert.deepStrictEqual(receive(initialHostState(), { kind: "snapshot", messages: msgs }), incremental);
  }), { numRuns: 1000 });
});

test("(pg-snapshot-replaces) a snapshot REPLACES whatever the panel had, whatever it had seen", () => {
  fc.assert(fc.property(fc.array(messageArb, { maxLength: 20 }), fc.array(messageArb, { maxLength: 20 }), (history, snap) => {
    const before = history.reduce<HostState>((s, m) => receive(s, m), initialHostState());
    const after = receive(before, { kind: "snapshot", messages: snap });
    assert.deepStrictEqual(after, foldSnapshot(snap));
    assert.deepStrictEqual(presentation(after), presentation(foldSnapshot(snap)));
  }), { numRuns: 1000 });
});

test("(pg-pure) receive never mutates the state or the envelope", () => {
  fc.assert(fc.property(fc.array(messageArb, { maxLength: 12 }), fc.array(messageArb, { maxLength: 12 }), (pre, snap) => {
    const s = foldSnapshot(pre);
    const env: PanelEnvelope = { kind: "snapshot", messages: snap };
    const sBefore = structuredClone(s); const eBefore = structuredClone(env);
    receive(s, env);
    assert.deepStrictEqual(s, sBefore);
    assert.deepStrictEqual(env, eBefore);
  }), { numRuns: 300 });
});

test("(pg-malformed) a snapshot with no message list leaves the panel as it was, BY IDENTITY", () => {
  const s = foldSnapshot([{ kind: "render", document: doc }, { kind: "error", status: 500, message: "e" }]);
  for (const bad of [undefined, null, "x", 3, { length: 1 }]) {
    assert.equal(receive(s, { kind: "snapshot", messages: bad } as unknown as PanelEnvelope), s);
  }
  // and an unknown kind is still the reducer's identity
  assert.equal(receive(s, { kind: "somethingNewer" } as unknown as PanelEnvelope), s);
  // `snapshot` is an ENVELOPE: the reducer itself does not know it
  assert.equal(applyMessage(s, { kind: "snapshot", messages: [] } as unknown as HostMessage), s);
  assert.ok(!(MESSAGE_KINDS as readonly string[]).includes("snapshot"), "MESSAGE_KINDS stays nine");
});

test("(pg-surface) page re-exports the reducer's whole surface, so S2 can point the host entry at it", () => {
  const want = Object.keys(hostIndex).sort();
  const have = Object.keys(pageModule);
  for (const k of want) assert.ok(have.includes(k), `page.ts is missing ${k}`);
  assert.deepStrictEqual(have.filter((k) => !want.includes(k)).sort(), ["foldSnapshot", "receive"]);
});

// ------------------------------------------------ H7, against the extension

const CAPTURED = JSON.parse(fs.readFileSync(
  path.join(path.dirname(findCore()), "..", "test", "fixtures", "panel-answers.json"), "utf8"));
const PICK = core.makePick("file:///w/doc/WpSpin.e", "/w/doc/WpSpin.e", "report", "WpSpin", []);

/** A MODEL OF THE EXTENSION'S MODULE GLOBALS -- the ones `panelView` reads --
 *  where every transition goes through the real reducer the glue will call. */
interface Ext {
  answers: unknown; current: number; stuckState: unknown; mark: unknown;
  pending: boolean; unsaved: string[]; fastMode: boolean; reloading: boolean;
}
type Ev =
  | { t: "answer"; name: string; gen: number } | { t: "bump" } | { t: "pending"; on: boolean }
  | { t: "stuck"; on: boolean; seq: number } | { t: "client"; to: "Stopped" | "Running" }
  | { t: "mark" } | { t: "recover" } | { t: "unsaved"; names: string[] } | { t: "fast"; on: boolean }
  | { t: "reloadAnnounce" } | { t: "reloadDone" } | { t: "reloadAbandoned" };

const caseNames = Object.keys(CAPTURED.cases);
const evArb = (withAbandon: boolean): fc.Arbitrary<Ev> => fc.oneof(
  fc.record({ t: fc.constant("answer" as const), name: fc.constantFrom(...caseNames), gen: fc.integer({ min: 0, max: 12 }) }),
  fc.record({ t: fc.constant("bump" as const) }),
  fc.record({ t: fc.constant("pending" as const), on: fc.boolean() }),
  fc.record({ t: fc.constant("stuck" as const), on: fc.boolean(), seq: fc.integer({ min: 1, max: 9 }) }),
  fc.record({ t: fc.constant("client" as const), to: fc.constantFrom("Stopped" as const, "Running" as const) }),
  fc.record({ t: fc.constant("mark" as const) }),
  fc.record({ t: fc.constant("recover" as const) }),
  fc.record({ t: fc.constant("unsaved" as const), names: fc.subarray(["A.e", "B.e"]) }),
  fc.record({ t: fc.constant("fast" as const), on: fc.boolean() }),
  fc.record({ t: fc.constant("reloadAnnounce" as const) }),
  fc.record({ t: fc.constant("reloadDone" as const) }),
  ...(withAbandon ? [fc.record({ t: fc.constant("reloadAbandoned" as const) })] : []),
);

function initialExt(): Ext {
  return { answers: core.initialPanelAnswers(), current: 0, stuckState: core.initialStuckState(), mark: null,
           pending: false, unsaved: [], fastMode: false, reloading: false };
}

/** One extension event.  Returns whether the PAGE was replaced (a reload). */
function step(x: Ext, e: Ev): { freshPage: boolean } {
  switch (e.t) {
    case "answer": {
      const c = CAPTURED.cases[e.name];
      const outcome = c.rejection ? { rejection: c.rejection, generation: e.gen } : { answer: { ...c.answer, generation: e.gen } };
      x.answers = core.panelAnswerStep(x.answers, outcome, x.current);
      if (c.answer && c.answer.stuck === true) {
        x.stuckState = core.stuckReduce(x.stuckState, { type: "answer", stuck: true, message: c.answer.message, seqAtSend: 0 }).state;
      }
      return { freshPage: false };
    }
    case "bump": x.current += 1; return { freshPage: false };
    case "pending": x.pending = e.on; return { freshPage: false };
    case "stuck":
      x.stuckState = core.stuckReduce(x.stuckState, { type: "notification", stuck: e.on, message: "wedged", seq: e.seq }).state;
      return { freshPage: false };
    case "client": x.stuckState = core.stuckReduce(x.stuckState, { type: "clientState", to: e.to }).state; return { freshPage: false };
    case "mark": x.mark = core.guardReduce(x.mark, { type: "answer", stuck: true, applies: true, pick: PICK, at: 1 }).mark; return { freshPage: false };
    case "recover": x.mark = core.guardReduce(x.mark, { type: "notification", stuck: false, pick: PICK }).mark; return { freshPage: false };
    case "unsaved": x.unsaved = e.names.slice(); return { freshPage: false };
    case "fast": x.fastMode = e.on; return { freshPage: false };
    case "reloadAnnounce": x.reloading = true; return { freshPage: false };
    case "reloadDone":
      if (!x.reloading) return { freshPage: false };
      x.reloading = false; return { freshPage: true };
    case "reloadAbandoned": x.reloading = false; return { freshPage: false };
  }
}

function messagesOf(x: Ext): HostMessage[] {
  return core.panelMessagesFor(core.panelView({
    answers: x.answers, stuckState: x.stuckState, mark: x.mark, pick: PICK,
    pending: x.pending, unsaved: x.unsaved, fastMode: x.fastMode, reloading: x.reloading,
  }));
}

test("(pg-h7-incremental) over generated extension histories, posting each view's messages one by one equals the snapshot of the last view", () => {
  // THE PROPERTY THAT MAKES A DROPPED POST HARMLESS (design review H7/H10):
  // `panelMessagesFor(view)` carries every slice, so the panel that saw every
  // post is in exactly the state a panel that saw only the final snapshot is.
  fc.assert(fc.property(fc.array(evArb(false), { maxLength: 40 }), (events) => {
    const x = initialExt();
    let page = receive(initialHostState(), { kind: "snapshot", messages: messagesOf(x) });
    for (const e of events) {
      if (step(x, e).freshPage) page = receive(initialHostState(), { kind: "snapshot", messages: messagesOf(x) });
      else for (const m of messagesOf(x)) page = receive(page, m);
      assert.deepStrictEqual(page, foldSnapshot(messagesOf(x)), `after ${JSON.stringify(e)}`);
    }
  }), { numRuns: 1500 });
});

test("(pg-h7-drops) a panel that MISSED any subset of posts is restored exactly by the next snapshot", () => {
  fc.assert(fc.property(fc.array(fc.tuple(evArb(true), fc.boolean()), { maxLength: 40 }), (events) => {
    const x = initialExt();
    let seen = initialHostState();      // the panel that saw every post
    let lossy = initialHostState();     // the one that was hidden for some of them
    for (const [e, dropped] of events) {
      const fresh = step(x, e).freshPage;
      const env: PanelEnvelope = { kind: "snapshot", messages: messagesOf(x) };
      if (fresh) { seen = receive(initialHostState(), env); lossy = receive(initialHostState(), env); continue; }
      seen = receive(seen, env);
      if (!dropped) lossy = receive(lossy, env);
    }
    const resync: PanelEnvelope = { kind: "snapshot", messages: messagesOf(x) };
    assert.deepStrictEqual(receive(lossy, resync), receive(seen, resync));
    assert.deepStrictEqual(presentation(receive(lossy, resync)), presentation(foldSnapshot(messagesOf(x))));
  }), { numRuns: 1500 });
});

test("(pg-h7-abandoned-reload) FOUND BY S1: a reload ANNOUNCED and then ABANDONED before the FIRST answer diverges on the one-by-one path", () => {
  // `reloadBundle` is the only latch the extension never retracts (the
  // reducer's own comment): only an ANSWER message lowers `reloading`.  Once
  // there is an answer, every `panelMessagesFor` list re-sends it (`render`
  // and/or `error`), so a loose post lowers the latch anyway -- MEASURED by
  // the first version of this test, which assumed otherwise and failed.  But
  // BEFORE the first answer the list carries no answer at all, and a panel fed
  // one message at a time keeps the "reloading" banner while the snapshot of
  // the same view does not.  S2 THEREFORE POSTS SNAPSHOT ENVELOPES, never loose
  // messages -- and this test is the reason, pinned.
  const x = initialExt();
  let page = foldSnapshot(messagesOf(x));
  step(x, { t: "reloadAnnounce" });
  for (const m of messagesOf(x)) page = receive(page, m);
  step(x, { t: "reloadAbandoned" });
  for (const m of messagesOf(x)) page = receive(page, m);
  assert.equal(page.reloading, true, "one by one: the banner is stuck on 'reloading'");
  assert.equal(presentation(page).banner?.kind, "reloading");
  assert.equal(foldSnapshot(messagesOf(x)).reloading, false, "the snapshot tells the truth");
  assert.equal(receive(page, { kind: "snapshot", messages: messagesOf(x) }).reloading, false, "and a snapshot envelope repairs it");

  // and with an answer on record the loose path is repaired by the list itself
  const y = initialExt();
  step(y, { t: "answer", name: "ok-wpint", gen: 1 });
  let page2 = foldSnapshot(messagesOf(y));
  step(y, { t: "reloadAnnounce" });
  for (const m of messagesOf(y)) page2 = receive(page2, m);
  step(y, { t: "reloadAbandoned" });
  for (const m of messagesOf(y)) page2 = receive(page2, m);
  assert.equal(page2.reloading, false);
});

test("(pg-h7-real) every captured real answer, folded through the real reducer, draws the banner it should", () => {
  const table: Record<string, { banner: string | null; text?: RegExp; doc: boolean }> = {
    "ok-wpint": { banner: null, doc: true },
    "error-400-sales-key": { banner: "error", text: /^400: the key "fromDy" is not allowed here \(\$\.params\.fromDy\)$/, doc: false },
    "error-404-placement": { banner: "error", text: /^404: cannot read Missing\.e$/, doc: false },
    "error-500-sales": { banner: "error", text: /^500: Sales\.report produced a document that cannot be encoded/, doc: false },
    "stuck-wpspin": { banner: "stuck", text: /^evaluation did not finish after 4s; the preview is stuck/, doc: false },
    "burst-1": { banner: "initial", doc: false },
  };
  for (const [name, want] of Object.entries(table)) {
    const x = initialExt();
    x.current = CAPTURED.cases[name].request.generation;
    step(x, { t: "answer", name, gen: x.current });
    const p = presentation(foldSnapshot(messagesOf(x)));
    assert.equal(p.banner?.kind ?? null, want.banner, name);
    if (want.text) assert.match(p.banner!.text, want.text, name);
    assert.equal(p.showDocument, want.doc, name);
    if (name === "stuck-wpspin") assert.equal(p.banner?.action, "restartServer", "the stuck banner's one action");
  }
});
