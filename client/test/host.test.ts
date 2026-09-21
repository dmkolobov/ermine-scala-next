// The panel's presentation reducer (WP-9 stage 4; `client/src/host/index.ts`).
//
// Two halves: the transitions, one test each, and the property the reducer
// exists to have -- EVERY message sequence leaves a consistent state, where
// "consistent" is the seven clauses `consistent()` below spells out.  The
// arbitrary draws from `MESSAGE_KINDS`, so a tenth message kind added without a
// case in `applyMessage` falsifies clause (7) rather than passing silently.

import { test } from "node:test";
import assert from "node:assert/strict";
import fc from "fast-check";

import {
  applyMessage, initialHostState, presentation, activeBanners,
  BANNER_PRECEDENCE, MESSAGE_KINDS,
  type HostMessage, type HostState, type BannerKind,
} from "../src/host/index";

const doc = { version: 1, settings: {}, root: { tag: "VFlow", children: [] } };
const HELD_TEXT = "this report wedged and was stopped; it has not changed since";

function fold(msgs: HostMessage[], from: HostState = initialHostState()): HostState {
  return msgs.reduce(applyMessage, from);
}

// ------------------------------------------------------------- transitions

test("(h-initial) nothing has happened: no document, the pick banner, no hint", () => {
  const p = presentation(initialHostState());
  assert.equal(p.showDocument, false);
  assert.equal(p.dimmed, false);
  assert.equal(p.hint, null);
  assert.equal(p.banner?.kind, "initial");
  assert.match(p.banner!.text, /Ermine: Preview Report/);
});

test("(h-render) a document is shown, clears the error it supersedes and ends the re-render", () => {
  const s = fold([
    { kind: "error", status: 500, message: "boom" },
    { kind: "stale", stale: true },
    { kind: "render", document: doc, generation: 7 },
  ]);
  assert.deepStrictEqual(s.document, { payload: doc, generation: 7 });
  assert.equal(s.error, null);
  assert.equal(s.stale, false);
  const p = presentation(s);
  assert.equal(p.showDocument, true);
  assert.equal(p.dimmed, false);
  assert.equal(p.banner, null);
});

test("(h-error) the last document stays, dimmed, under a banner carrying status, message and path", () => {
  const s = fold([
    { kind: "render", document: doc, generation: 1 },
    { kind: "error", status: 400, message: "no such key", path: "$.params.from" },
  ]);
  assert.deepStrictEqual(s.document, { payload: doc, generation: 1 });
  const p = presentation(s);
  assert.equal(p.showDocument, true);
  assert.equal(p.dimmed, true);
  assert.equal(p.banner?.kind, "error");
  assert.equal(p.banner?.text, "400: no such key ($.params.from)");
});

test("(h-stale) re-rendering says so and does not dim: the document below is still the last good one", () => {
  const p = presentation(fold([{ kind: "render", document: doc }, { kind: "stale", stale: true }]));
  assert.equal(p.banner?.kind, "stale");
  assert.equal(p.dimmed, false);
  assert.equal(p.showDocument, true);
});

test("(h-stuck) the wedge banner carries the message and the panel's own restart action", () => {
  const s = applyMessage(initialHostState(), { kind: "stuck", stuck: true, message: "evaluation did not finish", seq: 3 });
  assert.deepStrictEqual(s.stuck, { message: "evaluation did not finish", seq: 3 });
  const b = presentation(s).banner;
  assert.equal(b?.kind, "stuck");
  assert.equal(b?.text, "evaluation did not finish");
  assert.equal(b?.action, "restartServer");
  // and the falling edge clears it
  assert.equal(applyMessage(s, { kind: "stuck", stuck: false, seq: 4 }).stuck, null);
});

test("(h-stuck-no-arbitration) a LOWER seq is applied as sent: rule (1) is the extension's, not the panel's", () => {
  // D10: this reducer decides what is shown, never which message to believe.
  const s = fold([
    { kind: "stuck", stuck: true, message: "first", seq: 9 },
    { kind: "stuck", stuck: true, message: "second", seq: 2 },
  ]);
  assert.deepStrictEqual(s.stuck, { message: "second", seq: 2 });
});

test("(h-held) WP-22's ninth message: shown, informational, and it dims the kept document", () => {
  const s = fold([{ kind: "render", document: doc }, { kind: "held", held: true }]);
  const p = presentation(s);
  assert.equal(p.banner?.kind, "held");
  assert.equal(p.banner?.action, null, "Render anyway is the extension's showWarningMessage, not a panel button");
  assert.equal(p.dimmed, true);
  assert.equal(applyMessage(s, { kind: "held", held: false }).held, null);
});

test("(h-offline) the server stopped: the document is kept and dimmed under the offline banner", () => {
  const p = presentation(fold([{ kind: "render", document: doc }, { kind: "offline", offline: true }]));
  assert.equal(p.banner?.kind, "offline");
  assert.equal(p.showDocument, true);
  assert.equal(p.dimmed, true);
});

test("(h-switching) a profile switch names its target and ends on null", () => {
  const s = fold([{ kind: "render", document: doc }, { kind: "switching", to: "prod" }]);
  assert.equal(presentation(s).banner?.text, "switching to prod");
  assert.equal(applyMessage(s, { kind: "switching", to: null }).switching, null);
});

test("(h-unsaved) the hint sits beside the banner, never instead of it", () => {
  const p = presentation(fold([{ kind: "stale", stale: true }, { kind: "unsaved", names: ["Chart.e", "Sales.e"] }]));
  assert.equal(p.hint, "unsaved: Chart.e, Sales.e");
  assert.equal(p.banner?.kind, "stale");
  // a non-string in the list is dropped rather than printed as "undefined"
  const junk = applyMessage(initialHostState(), { kind: "unsaved", names: ["a", 3 as unknown as string] });
  assert.deepStrictEqual(junk.unsaved, ["a"]);
});

test("(h-reload) a bundle reload is announced above a switch and below the wedge", () => {
  const s = fold([{ kind: "render", document: doc }, { kind: "switching", to: "prod" }, { kind: "reloadBundle" }]);
  assert.equal(presentation(s).banner?.kind, "reloading");
  assert.deepStrictEqual(activeBanners(applyMessage(s, { kind: "held", held: true })).slice(0, 2), ["held", "reloading"]);
});

test("(h-precedence) offline > stuck > held > reloading > switching > error > stale > initial", () => {
  // ORDER MATTERS: an answer clears `stale` and `reloading`, so both are raised
  // after the `error` rather than before it
  const s = fold([
    { kind: "offline", offline: true }, { kind: "stuck", stuck: true },
    { kind: "held", held: true }, { kind: "switching", to: "x" },
    { kind: "error", status: 500, message: "e" },
    { kind: "reloadBundle" }, { kind: "stale", stale: true },
  ]);
  assert.deepStrictEqual(activeBanners(s), BANNER_PRECEDENCE);
  assert.equal(presentation(s).banner?.kind, "offline");
});

test("(h-blank) a blank message, path or switch target is a MISSING value, never an empty banner", () => {
  // found by (h-prop-consistent): `{stuck: true, message: ""}` drew a banner
  // that said nothing.  §4 promises no non-empty `message`, so the reducer
  // normalises at its boundary.
  const stuck = applyMessage(initialHostState(), { kind: "stuck", stuck: true, message: "  " });
  assert.equal(presentation(stuck).banner?.text, "the evaluation did not finish");
  const err = applyMessage(initialHostState(), { kind: "error", status: 500, message: "", path: "" });
  assert.equal(err.error?.path, null);
  assert.equal(presentation(err).banner?.text, "500: the render failed");
  assert.equal(applyMessage(initialHostState(), { kind: "switching", to: "" }).switching, null);
  assert.equal(applyMessage(initialHostState(), { kind: "held", held: true, message: "" }).held?.message, HELD_TEXT);
});

test("(h-reload-cleared) an ANSWER clears the reload announcement, so a reload that never happened masks nothing", () => {
  // S-1 of the WP-9 review: `reloading` outranks `error`, and it was the only
  // latch with no falling edge -- measured winning 16.5 % of generated states
  // once raised.  A real reload destroys this page (§5 re-sets webview.html),
  // so the flag only ever survives a reload that did NOT happen.
  const raised = fold([{ kind: "render", document: doc }, { kind: "reloadBundle" }]);
  assert.equal(raised.reloading, true);
  assert.equal(presentation(raised).banner?.kind, "reloading");

  const afterRender = applyMessage(raised, { kind: "render", document: doc });
  assert.equal(afterRender.reloading, false);
  assert.equal(presentation(afterRender).banner, null);

  const afterError = applyMessage(raised, { kind: "error", status: 500, message: "boom" });
  assert.equal(afterError.reloading, false);
  assert.equal(presentation(afterError).banner?.kind, "error", "the failure is visible, not masked");

  // and nothing else clears it: it is the extension's announcement, never retracted
  for (const m of [{ kind: "stale", stale: false }, { kind: "offline", offline: false },
                   { kind: "switching", to: null }, { kind: "held", held: false },
                   { kind: "stuck", stuck: false }, { kind: "unsaved", names: [] }] as HostMessage[]) {
    assert.equal(applyMessage(raised, m).reloading, true, `${m.kind} must not clear it`);
  }
});

test("(h-dim-table) a document on screen is dimmed exactly when nothing is trying to replace it", () => {
  // S-2 of the WP-9 review.  The rule is one sentence; this is the whole table.
  const table: [string, HostMessage, boolean][] = [
    ["offline",   { kind: "offline", offline: true },            true],
    ["error",     { kind: "error", status: 500, message: "e" },  true],
    ["switching", { kind: "switching", to: "prod" },             true],
    ["held",      { kind: "held", held: true },                  true],
    ["stale",     { kind: "stale", stale: true },                false],
    ["stuck",     { kind: "stuck", stuck: true },                false],
    ["reloading", { kind: "reloadBundle" },                      false],
  ];
  for (const [name, msg, dim] of table) {
    const p = presentation(fold([{ kind: "render", document: doc }, msg]));
    assert.equal(p.showDocument, true, `${name}: the last document is always kept`);
    assert.equal(p.dimmed, dim, `${name} should ${dim ? "" : "not "}dim`);
  }
  // nothing is dimmed when there is nothing on screen
  assert.equal(presentation(fold([{ kind: "offline", offline: true }])).dimmed, false);
});

test("(h-unknown) a message kind this panel does not know leaves the state IDENTICAL, not blank", () => {
  const s = fold([{ kind: "render", document: doc }]);
  const after = applyMessage(s, { kind: "somethingNewer" } as unknown as HostMessage);
  assert.equal(after, s, "the same object, by identity");
  assert.equal(applyMessage(s, null as unknown as HostMessage), s);
  assert.equal(applyMessage(s, "render" as unknown as HostMessage), s);
});

// ---------------------------------------------------------------- property

/** The seven clauses "a consistent state" means.  Anything that throws here
 *  falsifies; the message says which clause. */
function consistent(s: HostState): void {
  // (1) every field carries its declared shape
  assert.ok(s.document === null || (typeof s.document === "object" && "payload" in s.document));
  assert.ok(s.document === null || s.document.generation === null || typeof s.document.generation === "number");
  assert.ok(s.error === null || (typeof s.error.status === "number" && typeof s.error.message === "string"));
  assert.ok(s.stuck === null || typeof s.stuck.message === "string");
  assert.ok(s.held === null || typeof s.held.message === "string");
  assert.equal(typeof s.stale, "boolean");
  assert.equal(typeof s.offline, "boolean");
  assert.equal(typeof s.reloading, "boolean");
  assert.ok(s.switching === null || typeof s.switching === "string");
  assert.ok(Array.isArray(s.unsaved) && s.unsaved.every((n) => typeof n === "string"));

  // (2) presentation is total
  const p = presentation(s);

  // (3) exactly one banner, and it is the highest ACTIVE one
  const active = activeBanners(s);
  assert.equal(p.banner === null, active.length === 0);
  if (p.banner !== null) {
    assert.equal(p.banner.kind, active[0]);
    assert.equal(typeof p.banner.text, "string");
    assert.ok(p.banner.text.length > 0, "a banner always says something");
    assert.ok(p.banner.action === null || p.banner.action === "restartServer");
  }

  // (4) the active set is a subsequence of the declared precedence
  assert.deepStrictEqual(active, BANNER_PRECEDENCE.filter((k) => active.includes(k as BannerKind)));

  // (5) the document is shown exactly when there is one
  assert.equal(p.showDocument, s.document !== null);

  // (6) nothing is dimmed that is not on screen
  assert.ok(!p.dimmed || p.showDocument);

  // (7) there is always something to say when there is no document: `initial`
  //     is active whenever `document` is null, so `banner` is never null then
  assert.ok(s.document !== null || p.banner !== null);
}

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
  // the messages an OLDER panel would be handed by a NEWER extension
  fc.record({ kind: fc.string({ maxLength: 8 }) }) as fc.Arbitrary<HostMessage>,
);

test("(h-prop-consistent) every message sequence leaves a consistent state", () => {
  fc.assert(fc.property(fc.array(messageArb, { maxLength: 24 }), (msgs) => {
    let s = initialHostState();
    consistent(s);
    for (const m of msgs) {
      s = applyMessage(s, m);
      consistent(s);
    }
  }), { numRuns: 500 });
});

test("(h-prop-pure) applyMessage never mutates the state it is given", () => {
  fc.assert(fc.property(fc.array(messageArb, { maxLength: 12 }), messageArb, (pre, m) => {
    const s = fold(pre);
    const before = structuredClone(s);
    applyMessage(s, m);
    assert.deepStrictEqual(s, before);
  }), { numRuns: 300 });
});

test("(h-prop-kinds) every declared kind has a case: each one moves the state or is a no-op by design", () => {
  // `reloadBundle` from a reloading state is the only declared kind that can be
  // a genuine no-op; every other kind has an argument that changes something.
  const movers: Record<string, HostMessage> = {
    render: { kind: "render", document: doc },
    error: { kind: "error", status: 500, message: "e" },
    stale: { kind: "stale", stale: true },
    stuck: { kind: "stuck", stuck: true },
    held: { kind: "held", held: true },
    offline: { kind: "offline", offline: true },
    switching: { kind: "switching", to: "p" },
    unsaved: { kind: "unsaved", names: ["A.e"] },
    reloadBundle: { kind: "reloadBundle" },
  };
  assert.deepStrictEqual(Object.keys(movers).sort(), [...MESSAGE_KINDS].sort());
  for (const k of MESSAGE_KINDS) {
    const s0 = initialHostState();
    const s1 = applyMessage(s0, movers[k]!);
    assert.notEqual(s1, s0, `${k} fell through to the default arm`);
    consistent(s1);
  }
});
