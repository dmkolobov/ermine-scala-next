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
  pageStep, initialPage, documentKey, boot, refuseDeferred, PREVIEW_ROOT_ID, NO_RENDER_FUNCTION,
  type HostMessage, type HostState, type PanelEnvelope, type PageModel, type BootWindow,
} from "../src/host/page";
import { JSDOM } from "jsdom";
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
  // S1's fold, and S2's step + DOM bootstrap: nothing else may grow here
  assert.deepStrictEqual(have.filter((k) => !want.includes(k)).sort(),
    ["NO_RENDER_FUNCTION", "PREVIEW_ROOT_ID", "boot", "documentKey", "foldSnapshot", "initialPage", "pageStep", "receive", "refuseDeferred"]);
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
    "error-500-wpempty": { banner: "error", text: /^500: WpEmpty\.report produced a document that cannot be encoded/, doc: false },
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

// ============================================ S2: the page's step and its DOM
//
// `pageStep` is the rule the bootstrap runs on every post, so these are the
// page's model: DELIVERY only (snapshot envelopes only, `seq` monotone) and
// the S1 review's "render only when the document changed".  The `(pg-boot-*)`
// tests then drive the REAL `boot` in a JSDOM with a stub VS Code API and a
// stub `window.ErmineClient` that counts renders.

/** The extension's envelopes, built by ITS builders (`panelView` ->
 *  `panelSnapshot`), so the page is tested against what the glue posts. */
function envelopeOf(parts: Record<string, unknown>, seq: number): unknown {
  return core.panelSnapshot(core.panelView(parts), seq);
}
const okAnswers = (gen: number, note: string): unknown =>
  core.panelAnswerStep(core.initialPanelAnswers(), { answer: { ok: true, document: { ...doc, note }, generation: gen } }, gen);

test("(pg-step-render-on-change) a re-render happens exactly when the document's generation or payload changes", () => {
  fc.assert(fc.property(fc.array(fc.record({
    gen: fc.integer({ min: 1, max: 4 }), note: fc.constantFrom("a", "b"), hasDoc: fc.boolean(),
    pending: fc.boolean(), fast: fc.boolean(), stuck: fc.boolean(),
  }), { maxLength: 25 }), (posts) => {
    let page: PageModel = initialPage();
    let lastKey: string | null = null;
    let seq = 0;
    for (const p of posts) {
      const env = envelopeOf({
        answers: p.hasDoc ? okAnswers(p.gen, p.note) : core.initialPanelAnswers(),
        pending: p.pending, fastMode: p.fast,
        stuckState: p.stuck ? core.stuckReduce(core.initialStuckState(), { type: "notification", stuck: true, message: "m", seq: 1 }).state : undefined,
      }, ++seq);
      const step = pageStep(page, env);
      assert.equal(step.accepted, true);
      const key = p.hasDoc ? `${p.gen}:${JSON.stringify({ ...doc, note: p.note })}` : null;
      assert.equal(step.rerender, key !== lastKey, JSON.stringify(p));
      assert.equal(step.page.shownKey, key);
      lastKey = key;
      page = step.page;
      // and the state is the snapshot's, whatever came before
      assert.deepStrictEqual(page.host, foldSnapshot((env as { messages: HostMessage[] }).messages));
    }
  }), { numRuns: 500 });
});

test("(pg-step-no-rerender-on-toggles) stale, stuck, held, offline and unsaved toggles over the SAME document never re-render", () => {
  let page = pageStep(initialPage(), envelopeOf({ answers: okAnswers(3, "a") }, 1)).page;
  const toggles: Record<string, unknown>[] = [
    { pending: true }, { pending: false }, { fastMode: true }, { unsaved: ["A.e"] },
    { stuckState: core.stuckReduce(core.initialStuckState(), { type: "clientState", from: "Running", to: "Stopped" }).state },
  ];
  let seq = 1;
  for (const t of toggles) {
    const step = pageStep(page, envelopeOf({ answers: okAnswers(3, "a"), ...t }, ++seq));
    assert.equal(step.accepted, true);
    assert.equal(step.rerender, false, JSON.stringify(t));
    page = step.page;
  }
  // the same payload at a NEW generation is a new render (a re-render of the same report)
  assert.equal(pageStep(page, envelopeOf({ answers: okAnswers(4, "a") }, ++seq)).rerender, true);
});

test("(pg-step-seq) an envelope whose seq is not above the last applied one is IGNORED; no seq is taken", () => {
  const first = pageStep(initialPage(), envelopeOf({ answers: okAnswers(1, "a") }, 5));
  assert.equal(first.page.seq, 5);
  for (const older of [5, 4, 1]) {
    const s = pageStep(first.page, envelopeOf({ answers: okAnswers(2, "b") }, older));
    assert.equal(s.accepted, false, String(older));
    assert.equal(s.page, first.page, "by identity");
  }
  const newer = pageStep(first.page, envelopeOf({ answers: okAnswers(2, "b") }, 6));
  assert.equal(newer.accepted, true);
  const noSeq = pageStep(newer.page, { kind: "snapshot", messages: [] });
  assert.equal(noSeq.accepted, true);
  assert.equal(noSeq.page.seq, 6, "a snapshot with no seq keeps the last one");
});

test("(pg-step-envelope-only) a loose host message, or anything else, is NOT applied by the page", () => {
  const page = pageStep(initialPage(), envelopeOf({ answers: okAnswers(1, "a") }, 1)).page;
  const loose: unknown[] = [
    { kind: "render", document: doc, generation: 9 }, { kind: "reloadBundle" }, { kind: "error", status: 500, message: "x" },
    { kind: "snapshot" }, { kind: "snapshot", messages: "x" }, null, 3, "snapshot", { type: "snapshot", messages: [] },
  ];
  for (const m of loose) {
    const s = pageStep(page, m);
    assert.equal(s.accepted, false, JSON.stringify(m));
    assert.equal(s.rerender, false);
    assert.equal(s.page, page);
  }
});

test("(pg-key) documentKey: null without a document, generation AND payload with one", () => {
  assert.equal(documentKey(null), null);
  assert.equal(documentKey({ payload: { a: 1 }, generation: 2 }), '2:{"a":1}');
  assert.equal(documentKey({ payload: { a: 1 }, generation: null }), '-:{"a":1}');
  assert.notEqual(documentKey({ payload: { a: 1 }, generation: 2 }), documentKey({ payload: { a: 2 }, generation: 2 }));
});

test("(pg-root-id) the page draws into the element the extension's html builder makes", () => {
  assert.equal(PREVIEW_ROOT_ID, core.PREVIEW_ROOT_ID);
});

test("(pg-fetch-refuses) U6: fetchData REJECTS, naming the token and that this preview does not fetch deferred relations", async () => {
  await assert.rejects(refuseDeferred("tok-123"), /deferred delivery of "tok-123"/);
  await assert.rejects(refuseDeferred("tok-123"), /this preview does not fetch deferred relations, and the report asked for deferred delivery of "tok-123" \(the panel has no network access: its CSP has no connect-src\)$/);
  await assert.rejects(refuseDeferred("tok-123"), /no connect-src/);
});

// ------------------------------------------------------------- the real boot

interface Harness {
  dom: JSDOM; posted: unknown[]; renders: { note: unknown }[]; win: BootWindow;
  send(env: unknown): Promise<void>; area(): Element; banner(): HTMLElement; button(): HTMLButtonElement;
}

async function harness(withClient = true, early?: (posted: unknown[], state: string) => void): Promise<Harness> {
  const dom = new JSDOM(`<!doctype html><html><head></head><body><div id="${PREVIEW_ROOT_ID}"></div></body></html>`);
  const w = dom.window as unknown as BootWindow & { Event: typeof Event };
  const posted: unknown[] = [];
  const renders: { note: unknown }[] = [];
  if (withClient) {
    w.ErmineClient = {
      parseDocument: (v: unknown) => v,
      defaultRegistry: () => ({}),
      render: async (target, d, _reg, env) => {
        assert.equal(env.fetchData, refuseDeferred, "the rejecting stub is what reaches render");
        renders.push({ note: (d as { note?: unknown }).note });
        target.textContent = `doc ${(d as { note?: unknown }).note}`;
        return { errors: [] };
      },
    };
  }
  boot(w, { postMessage: (m: unknown) => { posted.push(m); } });
  const doc = dom.window.document;
  if (early) early(posted.slice(), doc.readyState);
  // a real webview runs the host script while the document is still loading,
  // exactly as JSDOM does here; `ready` waits for DOMContentLoaded
  if (doc.readyState === "loading") await new Promise((r) => doc.addEventListener("DOMContentLoaded", r));
  return {
    dom, posted, renders, win: w,
    async send(env) {
      dom.window.dispatchEvent(new dom.window.MessageEvent("message", { data: env }));
      await new Promise((r) => setImmediate(r));
    },
    area: () => doc.querySelector(".ermine-document")!,
    banner: () => doc.querySelector(".ermine-banner") as HTMLElement,
    button: () => doc.querySelector(".ermine-banner button") as HTMLButtonElement,
  };
}

test("(pg-boot-ready) the page posts ready ONCE, after DOMContentLoaded, and nothing else on its own", async () => {
  let before: unknown[] = ["unset"];
  let state = "";
  const h = await harness(true, (p, s) => { before = p; state = s; });
  assert.equal(state, "loading", "sanity: boot ran while the document was loading, as in a webview");
  assert.deepStrictEqual(before, [], "nothing before DOMContentLoaded (the writers' listener must run first)");
  assert.deepStrictEqual(h.posted, [{ type: "ready" }]);
  assert.ok(h.dom.window.document.getElementById(PREVIEW_ROOT_ID)!.querySelector(".ermine-document"), "drawn into the root");
  h.dom.window.close();
});

test("(pg-boot-render-once) the DOM re-renders only when the document changes, never on a toggle", async () => {
  const h = await harness();
  let seq = 0;
  await h.send(envelopeOf({ answers: okAnswers(1, "a") }, ++seq));
  assert.deepStrictEqual(h.renders, [{ note: "a" }]);
  const shown = h.area().firstElementChild;
  for (const t of [{ pending: true }, { pending: false }, { fastMode: true }, { unsaved: ["X.e"] }]) {
    await h.send(envelopeOf({ answers: okAnswers(1, "a"), ...t }, ++seq));
  }
  assert.equal(h.renders.length, 1, "four toggles, no re-render");
  assert.equal(h.area().firstElementChild, shown, "the same DOM node: scroll and drilldown survive");
  await h.send(envelopeOf({ answers: okAnswers(2, "b") }, ++seq));
  assert.deepStrictEqual(h.renders.map((r) => r.note), ["a", "b"]);
  // a loose message changes nothing
  await h.send({ kind: "render", document: { ...doc, note: "loose" }, generation: 9 });
  assert.equal(h.renders.length, 2);
  // the pick changes: no document, the area is emptied and hidden, the initial banner is up
  await h.send(envelopeOf({}, ++seq));
  assert.equal(h.area().textContent, "");
  assert.equal((h.area() as HTMLElement).hidden, true);
  assert.equal(h.banner().getAttribute("data-kind"), "initial");
  h.dom.window.close();
});

test("(pg-boot-banner) banner, dimming and the ONE button come from presentation(); Restart posts the intent", async () => {
  const h = await harness();
  let seq = 0;
  const failed = core.panelAnswerStep(okAnswers(1, "a"), { answer: { ok: false, status: 500, message: "boom", generation: 2 } }, 2);
  await h.send(envelopeOf({ answers: failed }, ++seq));
  assert.equal(h.banner().getAttribute("data-kind"), "error");
  assert.match(h.banner().textContent!, /500: boom/);
  assert.ok(h.area().classList.contains("ermine-dimmed"), "an error dims the document below it");
  assert.equal(h.button().hidden, true, "no button on an error");
  const stuck = core.stuckReduce(core.initialStuckState(), { type: "notification", stuck: true, message: "did not finish", seq: 1 }).state;
  await h.send(envelopeOf({ answers: okAnswers(1, "a"), stuckState: stuck }, ++seq));
  assert.equal(h.banner().getAttribute("data-kind"), "stuck");
  assert.equal(h.button().hidden, false, "the stuck banner carries the one action");
  assert.ok(!h.area().classList.contains("ermine-dimmed"), "stuck does not dim");
  h.button().click();
  assert.deepStrictEqual(h.posted.slice(1), [{ type: "intent", kind: "restartServer" }]);
  await h.send(envelopeOf({ answers: okAnswers(1, "a"), unsaved: ["Sales.e"] }, ++seq));
  assert.equal(h.banner().hidden, true, "nothing to say");
  assert.equal((h.dom.window.document.querySelector(".ermine-hint") as HTMLElement).textContent, "unsaved: Sales.e");
  h.dom.window.close();
});

test("(pg-boot-no-client) without window.ErmineClient the page says so and logs it; it never throws", async () => {
  const h = await harness(false);
  await h.send(envelopeOf({ answers: okAnswers(1, "a") }, 1));
  assert.match(h.area().textContent!, /window\.ErmineClient\) is not loaded/);
  assert.ok(h.posted.some((m) => (m as { type?: string }).type === "log"));
  h.dom.window.close();
});

// ------------------------------------------------ WP-10 S3: the rejecting fetch

test("(pg-fetch-deferred-box) WP-10 S3: a widget asking for deferred data shows its OWN error box, the page logs it, and NOTHING reaches the network", async () => {
  const real = await import("../src/index");
  const dom = new JSDOM(`<!doctype html><html><head></head><body><div id="${PREVIEW_ROOT_ID}"></div></body></html>`);
  const w = dom.window as unknown as BootWindow & Record<string, unknown>;
  const network: string[] = [];
  // every door to the network, in the page's realm AND in node's, counts a call
  w["fetch"] = (u: unknown) => { network.push("window.fetch " + String(u)); return Promise.reject(new Error("no network")); };
  w["XMLHttpRequest"] = function XMLHttpRequest() { network.push("window.XMLHttpRequest"); };
  const g = globalThis as Record<string, unknown>;
  const saved = { fetch: g["fetch"], xhr: g["XMLHttpRequest"] };
  g["fetch"] = (u: unknown) => { network.push("globalThis.fetch " + String(u)); return Promise.reject(new Error("no network")); };
  g["XMLHttpRequest"] = function XMLHttpRequest() { network.push("globalThis.XMLHttpRequest"); };
  try {
    w.ErmineClient = {
      parseDocument: real.parseDocument,
      defaultRegistry: real.defaultRegistry,
      render: real.render as unknown as NonNullable<BootWindow["ErmineClient"]>["render"],
    };
    const posted: unknown[] = [];
    boot(w, { postMessage: (m: unknown) => { posted.push(m); } });
    const d = dom.window.document;
    if (d.readyState === "loading") await new Promise((r) => d.addEventListener("DOMContentLoaded", r));
    const columns = [{ name: "region", type: "String", nullable: false }, { name: "sales", type: "Double", nullable: false }];
    const table = {
      tag: "Widget", name: "table", props: {
        columns: [
          { column: "region", header: "Region", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "OtherColumn" },
          { column: "sales", header: "Sales", cellFormat: { tag: "Round", color: false, negParens: false, places: 1 }, align: "AlignRight", kind: "NumberColumn" },
        ],
        sorts: [], paginate: false, scroll: false,
        rows: { kind: "deferred", columns, token: "tok-deferred-1", expires: "2099-01-01T00:00:00.000Z" },
      },
    };
    const document = { version: 1, settings: {}, root: { tag: "VFlow", children: [table] } };
    const env = core.panelSnapshot(core.panelView({
      answers: core.panelAnswerStep(core.initialPanelAnswers(), { answer: { ok: true, document, generation: 1 } }, 1),
    }), 1);
    dom.window.dispatchEvent(new dom.window.MessageEvent("message", { data: env }));
    for (let i = 0; i < 20 && !d.querySelector(".ermine-widget-error"); i++) await new Promise((r) => setTimeout(r, 5));
    const box = d.querySelector(`#${PREVIEW_ROOT_ID} .ermine-document .ermine-widget-error`);
    assert.ok(box, "the dispatcher drew the widget's own error box: " + d.body.innerHTML.slice(0, 300));
    assert.equal(box!.getAttribute("data-widget"), "table");
    assert.equal(box!.getAttribute("role"), "alert");
    assert.match(box!.textContent!, /a deferred relation could not be resolved: this preview does not fetch deferred relations, and the report asked for deferred delivery of/);
    assert.match(box!.textContent!, /"tok-deferred-1"/);
    assert.equal(d.querySelector(".ermine-page-error"), null, "a widget failure, not a page failure");
    const logs = posted.filter((m) => (m as { type?: string }).type === "log").map((m) => (m as { message: string }).message);
    assert.equal(logs.length, 1, "the page logs the widget failure to the output channel once");
    assert.match(logs[0]!, /^widget "table" at .*deferred delivery of "tok-deferred-1"/);
    assert.deepStrictEqual(network, [], "no fetch and no XMLHttpRequest, in either realm");
  } finally {
    g["fetch"] = saved.fetch;
    g["XMLHttpRequest"] = saved.xhr;
    dom.window.close();
  }
});

test("(pg-boot-listener-first) the message listener is in place BEFORE ready is posted (S2 review N2 / R23)", async () => {
  // An extension that answers `ready` at once -- here synchronously, from
  // inside postMessage -- must find the listener already there.
  const dom = new JSDOM(`<!doctype html><html><head></head><body><div id="${PREVIEW_ROOT_ID}"></div></body></html>`);
  const w = dom.window as unknown as BootWindow;
  const renders: unknown[] = [];
  w.ErmineClient = {
    parseDocument: (v: unknown) => v,
    defaultRegistry: () => ({}),
    render: async (_t, d) => { renders.push((d as { note?: unknown }).note); return { errors: [] }; },
  };
  const answer = (m: unknown): void => {
    if ((m as { type?: string }).type !== "ready") return;
    dom.window.dispatchEvent(new dom.window.MessageEvent("message", { data: envelopeOf({ answers: okAnswers(1, "first") }, 1) }));
  };
  const h = boot(w, { postMessage: answer });
  const d = dom.window.document;
  if (d.readyState === "loading") await new Promise((r) => d.addEventListener("DOMContentLoaded", r));
  await new Promise((r) => setImmediate(r));
  assert.equal(h.model().seq, 1, "the snapshot answering ready was applied");
  assert.deepStrictEqual(renders, ["first"]);
  dom.window.close();
});

test("(pg-writers-global) WP-11: the writers' DOMContentLoaded listener, registered FIRST, has run before ready; render hands window.ermine_htmlwriter to runTabular, and without it `table` is its error box under the writers banner", async () => {
  const real = await import("../src/index");
  const { inlineRelation, stubHtmlWriter } = await import("./harness");
  const rows = inlineRelation([{ name: "region", type: "String" }, { name: "sales", type: "Double" }], [["EMEA", 1.5], ["APAC", 2]]);
  const table = {
    tag: "Widget", name: "table", props: {
      columns: [
        { column: "region", header: "Region", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "OtherColumn" },
        { column: "sales", header: "Sales", cellFormat: { tag: "Round", color: false, negParens: false, places: 1 }, align: "AlignRight", kind: "NumberColumn" },
      ],
      sorts: [], paginate: false, scroll: false, rows,
    },
  };
  const document = { version: 1, settings: {}, root: { tag: "VFlow", children: [table] } };
  const answers = core.panelAnswerStep(core.initialPanelAnswers(), { answer: { ok: true, document, generation: 1 } }, 1);
  const run = async (withWriters: boolean) => {
    const dom = new JSDOM(`<!doctype html><html><head></head><body><div id="${PREVIEW_ROOT_ID}"></div></body></html>`);
    const w = dom.window as unknown as BootWindow & Record<string, unknown>;
    const d = dom.window.document;
    const order: string[] = [];
    const hw = stubHtmlWriter();
    // SCRIPT 1, what the writers bundle does (READ: ermine-writers
    // writers/js/htmlwriter.js:10-13): the global is assigned INSIDE a
    // DOMContentLoaded listener, registered before the host script runs.
    if (withWriters) d.addEventListener("DOMContentLoaded", () => { order.push("writers"); w["ermine_htmlwriter"] = hw; });
    w.ErmineClient = {
      parseDocument: real.parseDocument,
      defaultRegistry: real.defaultRegistry,
      render: real.render as unknown as NonNullable<BootWindow["ErmineClient"]>["render"],
    };
    const posted: unknown[] = [];
    boot(w, {
      postMessage: (m: unknown) => {
        if ((m as { type?: string }).type === "ready") order.push("ready with the global " + (w["ermine_htmlwriter"] === undefined ? "absent" : "present"));
        posted.push(m);
      },
    });
    assert.equal(d.readyState, "loading", "sanity: the host script runs while the document is loading, as in a webview");
    assert.deepStrictEqual(order, [], "nothing is posted before DOMContentLoaded");
    await new Promise((r) => d.addEventListener("DOMContentLoaded", r));
    const writers = core.previewWritersCheck({ dir: "/wr/web", source: "setting", problem: null },
      withWriters ? ["htmlwriter.js", "common.css", "htmlwriter.css", "htmlwriter_classic.css"] : null);
    const env = core.panelSnapshot(core.panelView({ answers, writers }), 1);
    dom.window.dispatchEvent(new dom.window.MessageEvent("message", { data: env }));
    for (let i = 0; i < 40 && !d.querySelector(".ermine-widget-error") && hw.calls.length === 0; i++) await new Promise((r) => setTimeout(r, 5));
    const banner = d.querySelector(".ermine-banner") as HTMLElement;
    const out = { order, calls: hw.calls.length, box: d.querySelector(".ermine-widget-error"), banner, writers, dimmed: d.querySelector(".ermine-document")!.classList.contains("ermine-dimmed") };
    dom.window.close();
    return out;
  };
  const withW = await run(true);
  assert.deepStrictEqual(withW.order, ["writers", "ready with the global present"],
    "the writers' listener runs first, so the global exists when ready is posted");
  assert.equal(withW.calls, 1, "the table went through runTabular of window.ermine_htmlwriter, read at render time");
  assert.equal(withW.box, null);
  assert.equal(withW.banner.hidden, true, "present writers: no banner");
  const without = await run(false);
  assert.deepStrictEqual(without.order, ["ready with the global absent"]);
  assert.equal(without.calls, 0);
  assert.ok(without.box, "the dispatcher's own error box for the legacy widget");
  assert.equal(without.box!.getAttribute("data-widget"), "table");
  assert.match(without.box!.textContent!, /window\.ermine_htmlwriter/);
  assert.equal(without.banner.hidden, false);
  assert.equal(without.banner.getAttribute("data-kind"), "error", "the writers banner is the reducer's error kind");
  assert.equal(without.banner.textContent!.startsWith(without.writers.message), true, without.banner.textContent!);
  assert.equal(without.dimmed, true, "the documented cost: the document is dimmed while the writers are missing");
});

// ------------------------------------------ F3 (playtest 2026-09-23): the draw

// What JSDOM CAN see of F3: the writers' draw step is called, once, after the
// widgets are in the page, and the page's CSS carries the paper and the grid.
// What it cannot (colours as computed, rows drawn, the layout) is measured in
// a headless Chromium: scratch-widget-preview/panel-fix/{fix.js,RESULTS.md}.

interface DrawRun { order: string[]; posted: unknown[]; rfArgs: unknown[]; rfThis: unknown[]; dom: JSDOM; send(env: unknown): Promise<void> }

async function drawHarness(conf: "function" | "absent" | "noFunction" | "throws"): Promise<DrawRun> {
  const dom = new JSDOM(`<!doctype html><html><head></head><body><div id="${PREVIEW_ROOT_ID}"></div></body></html>`);
  const w = dom.window as unknown as BootWindow;
  const order: string[] = [];
  const rfArgs: unknown[] = [];
  const rfThis: unknown[] = [];
  const hw = { runTabular() { /* queues, as the writers' does */ } };
  const d = dom.window.document;
  d.addEventListener("DOMContentLoaded", () => {
    w.ermine_htmlwriter = hw;
    if (conf === "function" || conf === "throws") {
      w.ermine_htmlwriter_conf = {
        renderFunction(this: unknown, h: unknown) {
          rfArgs.push(h); rfThis.push(this);
          // the widgets must be IN the page when the writers look them up by id
          const shown = d.querySelector(`#${PREVIEW_ROOT_ID} .ermine-document [data-note]`);
          order.push(`draw sees ${shown ? shown.getAttribute("data-note") : "nothing"}`);
          if (conf === "throws") throw new Error("writers exploded");
        },
      };
    } else if (conf === "noFunction") {
      w.ermine_htmlwriter_conf = { renderFunction: "nope" as unknown as undefined };
    }
  });
  w.ErmineClient = {
    parseDocument: (v: unknown) => v,
    defaultRegistry: () => ({}),
    render: async (target, doc0) => {
      const note = String((doc0 as { note?: unknown }).note);
      order.push(`render ${note} starts`);
      // a render of a document noted "slow" resolves AFTER a later one starts and ends
      await new Promise((r) => setTimeout(r, note === "slow" ? 60 : 5));
      const el = d.createElement("div");
      el.setAttribute("data-note", note);
      target.appendChild(el);
      order.push(`render ${note} resolves`);
      return { errors: [] };
    },
  };
  const posted: unknown[] = [];
  boot(w, { postMessage: (m: unknown) => { posted.push(m); } });
  if (d.readyState === "loading") await new Promise((r) => d.addEventListener("DOMContentLoaded", r));
  return {
    order, posted, rfArgs, rfThis, dom,
    async send(env) {
      dom.window.dispatchEvent(new dom.window.MessageEvent("message", { data: env }));
      await new Promise((r) => setTimeout(r, 30));
    },
  };
}

const logsOf = (posted: unknown[]): string[] =>
  posted.filter((m) => (m as { type?: string }).type === "log").map((m) => (m as { message: string }).message);

test("(pg-f3-draw-once-after-render) F3: conf.renderFunction(window.ermine_htmlwriter) is called exactly ONCE per render, AFTER render resolves, and never on a toggle", async () => {
  const h = await drawHarness("function");
  let seq = 0;
  await h.send(envelopeOf({ answers: okAnswers(1, "a") }, ++seq));
  assert.deepStrictEqual(h.order, ["render a starts", "render a resolves", "draw sees a"]);
  for (const t of [{ pending: true }, { pending: false }, { unsaved: ["X.e"] }]) {
    await h.send(envelopeOf({ answers: okAnswers(1, "a"), ...t }, ++seq));
  }
  assert.equal(h.rfArgs.length, 1, "toggles do not redraw");
  await h.send(envelopeOf({ answers: okAnswers(2, "b") }, ++seq));
  await h.send(envelopeOf({ answers: okAnswers(3, "a") }, ++seq));
  assert.deepStrictEqual(h.order, [
    "render a starts", "render a resolves", "draw sees a",
    "render b starts", "render b resolves", "draw sees b",
    "render a starts", "render a resolves", "draw sees a",
  ]);
  const w = h.dom.window as unknown as BootWindow;
  assert.equal(h.rfArgs.length, 3);
  for (const a of h.rfArgs) assert.equal(a, w.ermine_htmlwriter, "handed the writers' global");
  for (const t of h.rfThis) assert.equal(t, w.ermine_htmlwriter_conf, "called as a method of conf");
  assert.deepStrictEqual(logsOf(h.posted), [], "nothing to log when the draw step is there");
  h.dom.window.close();
});

test("(pg-f3-draw-not-superseded) F3 review N1: a render overtaken by a newer one is NOT drawn -- the draw comes after the stale-render check", async () => {
  const h = await drawHarness("function");
  // the second snapshot arrives while the first render is still running
  h.dom.window.dispatchEvent(new h.dom.window.MessageEvent("message", { data: envelopeOf({ answers: okAnswers(1, "slow") }, 1) }));
  await h.send(envelopeOf({ answers: okAnswers(2, "b") }, 2));
  await new Promise((r) => setTimeout(r, 100));
  assert.deepStrictEqual(h.order, ["render slow starts", "render b starts", "render b resolves", "draw sees b", "render slow resolves"],
    "one draw, for the render that is shown; none when the overtaken one resolves");
  assert.equal(h.rfArgs.length, 1);
  h.dom.window.close();
});

test("(pg-f3-draw-absent) F3: with the writers' global but without conf, or with a renderFunction that is not a function, there is no call and ONE log naming it per page", async () => {
  // (no writers at all -> no log either: `(pg-fetch-deferred-box)` pins exactly one log there)
  for (const conf of ["absent", "noFunction"] as const) {
    const h = await drawHarness(conf);
    await h.send(envelopeOf({ answers: okAnswers(1, "a") }, 1));
    await h.send(envelopeOf({ answers: okAnswers(2, "b") }, 2));
    assert.deepStrictEqual(h.order, ["render a starts", "render a resolves", "render b starts", "render b resolves"], conf);
    assert.deepStrictEqual(logsOf(h.posted), [NO_RENDER_FUNCTION], `${conf}: one log, not one per render`);
    assert.match(NO_RENDER_FUNCTION, /window\.ermine_htmlwriter_conf\.renderFunction/);
    h.dom.window.close();
  }
  // a throwing draw step is logged, and the page carries on
  const t = await drawHarness("throws");
  await t.send(envelopeOf({ answers: okAnswers(1, "a") }, 1));
  assert.deepStrictEqual(logsOf(t.posted), ["the legacy writers' renderFunction failed to draw: writers exploded"]);
  assert.equal(t.dom.window.document.querySelector(".ermine-page-error"), null, "a draw failure is not a page failure");
  t.dom.window.close();
});

/** The page's own stylesheet as `selector -> declarations` rules. */
async function pageRules(): Promise<{ sel: string; body: string }[]> {
  const h = await harness();
  const css = [...h.dom.window.document.querySelectorAll("style")].map((s) => s.textContent ?? "").join("\n");
  h.dom.window.close();
  return css.split("}").map((r) => r.trim()).filter((r) => r.includes("{"))
    .map((r) => { const i = r.indexOf("{"); return { sel: r.slice(0, i).trim(), body: r.slice(i + 1).trim() }; });
}
const PAPER_SEL = `#${PREVIEW_ROOT_ID} .ermine-document`;

test("(pg-f3-paper) F3: the document draws on white paper with #222 text and 12px table text, SCOPED to the document; the banner keeps the theme's editor foreground", async () => {
  const rules = await pageRules();
  const paper = rules.find((r) => r.sel === PAPER_SEL);
  assert.ok(paper, "a rule for exactly the document area");
  for (const decl of ["background:#fff", "color:#222", "font-size:13px"]) assert.ok(paper!.body.includes(decl), `paper has ${decl}: ${paper!.body}`);
  const root = rules.find((r) => r.sel === `#${PREVIEW_ROOT_ID}`);
  assert.ok(root, "a root rule");
  assert.match(root!.body, /color:var\(--vscode-editor-foreground\)/);
  assert.doesNotMatch(root!.body, /color:var\(--vscode-foreground\)/, "not the theme's mid-grey foreground (F3)");
  // review M-1: the page's own error box is inside the paper, so its red must be chosen for white
  const pageError = rules.find((r) => r.sel === `${PAPER_SEL} .ermine-page-error`);
  assert.ok(pageError && /color:#b00020/.test(pageError.body), "the page-error box takes a paper red, not the theme's");
  for (const r of rules.filter((x) => x.sel.split(",").some((sel) => sel.trim().startsWith(PAPER_SEL)))) {
    assert.doesNotMatch(r.body, /color:var\(--vscode-/, `a theme colour inside the paper: ${r.sel}`);
  }
  const cells = rules.find((r) => r.sel.includes(`${PAPER_SEL} td.tabledata-left`) && r.sel.includes(`${PAPER_SEL} td.tabledata-right`));
  assert.ok(cells && /font-size:12px/.test(cells.body), "table text is 12px, not the writers' 10px");
  // every rule that paints white or #222 is under the document area, so the banner is untouched
  for (const r of rules.filter((x) => /#fff\b|#222\b/.test(x.body))) {
    for (const sel of r.sel.split(",")) assert.ok(sel.trim().startsWith(PAPER_SEL), `unscoped paper rule: ${sel}`);
  }
});

test("(pg-f3-grid) F3: Grid rows lay out as CSS grid columns, and the writers' table pair is held inside its cell", async () => {
  const rules = await pageRules();
  const row = rules.find((r) => r.sel === `${PAPER_SEL} .ermine-grid-row`);
  assert.ok(row, "a rule for the dispatcher's grid rows");
  assert.match(row!.body, /display:grid/);
  assert.match(row!.body, /grid-template-columns:repeat\(auto-fit,minmax\(min\(100%,480px\),1fr\)\)/);
  const pair = rules.find((r) => r.sel === `${PAPER_SEL} .table-full-scroll-wrapper`);
  assert.ok(pair && /display:flex!important/.test(pair.body) && /width:auto!important/.test(pair.body),
    "the writers size the pair to the WINDOW; the page holds it to its cell");
  assert.ok(rules.some((r) => r.sel === `${PAPER_SEL} .table-full-scroll-wrapper:not(:has(.main-table th)) .table-vscroll-wrapper` && /height:auto!important/.test(r.body)),
    "a one-column table's scroller gets its natural height, not the empty main part's 0px");
  for (const r of rules) {
    if (r.sel.startsWith(`#${PREVIEW_ROOT_ID}{`) || r.sel === `#${PREVIEW_ROOT_ID}` || r.sel.startsWith(".ermine-banner") || r.sel.startsWith(".ermine-hint") ||
        r.sel.startsWith(".ermine-document.ermine-dimmed") || r.sel.startsWith(".ermine-page-error")) continue;
    for (const sel of r.sel.split(",")) assert.ok(sel.trim().startsWith(PAPER_SEL), `unscoped document rule: ${sel}`);
  }
});
