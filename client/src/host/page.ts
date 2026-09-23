// The preview panel's PAGE module (WP-10).  STAGE 1 IS THE FOLD ONLY: no DOM,
// no `window`, no `acquireVsCodeApi()` -- S2 adds those here, and S2 also moves
// the `ermine-host` webpack entry from `host/index` to this file, which is why
// it re-exports the reducer's whole surface (so `window.ErmineHost` keeps
// every name `(b-host-surface)` expects).  Until S2 this module is NOT in the
// bundle; it is compiled and tested by `npm test` only.
//
// THE RESYNC (design review §2(c), H7).  `Webview.postMessage` is DOCUMENTED to
// drop messages to a webview that is not live, so the extension cannot rely on
// the panel having seen every incremental message.  On `ready` and whenever
// the panel becomes visible it posts ONE envelope,
//
//     { kind: "snapshot", messages: HostMessage[] }
//
// whose `messages` are `panelMessagesFor(view)` (`editor/vscode/src/
// preview-core.js`).  The page folds them FROM `initialHostState()`, never onto
// the state it has: folding the nine incremental kinds onto a non-fresh state
// is not idempotent (`reloadBundle` raises `reloading` and only an ANSWER
// lowers it), and a fresh fold needs no new decision.  So `snapshot` is an
// ENVELOPE handled here, not a tenth reducer kind -- `MESSAGE_KINDS` stays nine
// and `applyMessage` returns by identity if it is ever handed one.
//
// Nothing here decides anything either (D10): the snapshot REPLACES the state,
// wholesale, with what the extension says is true.

import {
  applyMessage, initialHostState,
  type HostMessage, type HostState,
} from "./index";

export * from "./index";

/** The resync envelope: the whole truth, as the nine kinds. */
export interface SnapshotEnvelope { kind: "snapshot"; messages: readonly HostMessage[] }

/** Everything the extension posts to the page. */
export type PanelEnvelope = HostMessage | SnapshotEnvelope;

/** A snapshot's messages folded from a FRESH state.  Pure and total. */
export function foldSnapshot(messages: readonly HostMessage[]): HostState {
  return messages.reduce(applyMessage, initialHostState());
}

/** One envelope into the page's state.
 *
 *  A `snapshot` REPLACES the state with `foldSnapshot(messages)`; anything else
 *  is `applyMessage`'s, unchanged.  A snapshot whose `messages` is not an array
 *  returns `state` BY IDENTITY -- the reducer's own rule for input it does not
 *  understand: a malformed resync must leave the panel as it was, not blank it. */
export function receive(state: HostState, envelope: PanelEnvelope): HostState {
  if (envelope !== null && typeof envelope === "object" && envelope.kind === "snapshot") {
    const msgs = (envelope as SnapshotEnvelope).messages;
    return Array.isArray(msgs) ? foldSnapshot(msgs) : state;
  }
  return applyMessage(state, envelope as HostMessage);
}
