// The preview panel's PAGE module (WP-10), and since S2 the `ermine-host`
// webpack ENTRY: `window.ErmineHost` is this module's exports, which re-export
// the reducer's whole surface (`(b-host-surface)` checks both).
//
// Two halves:
//   * PURE (S1 + S2): the snapshot fold (`foldSnapshot`, `receive`) and the
//     page's step (`pageStep`), which decides only DELIVERY -- is this
//     envelope newer than the last one, and did the document change so the
//     DOM must be re-rendered.  Tested in node.
//   * DOM (S2): `boot(win, api)`, which draws the banner/hint/dimming from
//     `presentation()` and renders through `window.ErmineClient`.  It runs by
//     itself only where `acquireVsCodeApi` exists (a VS Code webview), at the
//     bottom of this file; node never runs it, and the bundle test drives it
//     in a JSDOM with a stub API.
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
  applyMessage, initialHostState, presentation,
  type HostMessage, type HostState, type HostDocument,
} from "./index";

export * from "./index";

/** The resync envelope: the whole truth, as the nine kinds.  Since S2 it is
 *  the ONLY thing the extension posts, with a `seq` that rises by one per post
 *  (`editor/vscode/src/preview-core.js` `panelSnapshot`). */
export interface SnapshotEnvelope { kind: "snapshot"; messages: readonly HostMessage[]; seq?: number }

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

// ------------------------------------------------------ the page's step (S2)

/** What the page keeps between posts: the folded state, the last applied
 *  `seq`, and the key of the document the DOM currently shows. */
export interface PageModel {
  readonly host: HostState;
  readonly seq: number | null;
  readonly shownKey: string | null;
}

export function initialPage(): PageModel {
  return { host: initialHostState(), seq: null, shownKey: null };
}

/** The identity of a document for the DOM: its generation AND its payload.
 *  Null when there is no document.  A payload that will not stringify is keyed
 *  by generation alone (it cannot have come through `postMessage` anyway). */
export function documentKey(doc: HostDocument | null): string | null {
  if (doc === null) return null;
  let text: string;
  try {
    text = JSON.stringify(doc.payload) ?? "undefined";
  } catch {
    text = "<unserialisable>";
  }
  return `${doc.generation === null ? "-" : String(doc.generation)}:${text}`;
}

export interface PageStep {
  readonly page: PageModel;
  /** false: the envelope was not a snapshot, or was older than the last one. */
  readonly accepted: boolean;
  /** true: the DOM must be (re)rendered, or emptied, for `page.host.document`. */
  readonly rerender: boolean;
}

/**
 * One post into the page.  DELIVERY ONLY -- no domain decision is made here
 * (D10):
 *
 *   * only a `snapshot` envelope is taken.  The extension posts nothing else
 *     (one shape, ever), so a loose host message is IGNORED rather than
 *     applied: applying it would reintroduce the incremental path S1 measured
 *     diverging (`(pg-h7-abandoned-reload)`);
 *   * a numeric `seq` not above the last applied one is IGNORED: ordering of
 *     `postMessage` is documented neither way, and an older whole-state
 *     envelope arriving late would roll the panel back;
 *   * the snapshot REPLACES the state (`receive`);
 *   * `rerender` is true ONLY when the document's key changed -- the S1
 *     review's note: every post carries the document, so re-rendering on each
 *     one would lose scroll and drilldown on every `stale` toggle.
 */
export function pageStep(page: PageModel, envelope: unknown): PageStep {
  if (envelope === null || typeof envelope !== "object" ||
      (envelope as { kind?: unknown }).kind !== "snapshot" ||
      !Array.isArray((envelope as SnapshotEnvelope).messages)) {
    return { page, accepted: false, rerender: false };
  }
  const env = envelope as SnapshotEnvelope;
  const seq = typeof env.seq === "number" && Number.isFinite(env.seq) ? env.seq : null;
  if (seq !== null && page.seq !== null && seq <= page.seq) return { page, accepted: false, rerender: false };
  const host = receive(page.host, env);
  const key = documentKey(host.document);
  return {
    page: { host, seq: seq ?? page.seq, shownKey: key },
    accepted: true,
    rerender: key !== page.shownKey,
  };
}

// ----------------------------------------------------------- the DOM (S2)

/** What `acquireVsCodeApi()` returns, as far as this page uses it. */
export interface VsCodeApi { postMessage(message: unknown): unknown }

/** `window.ErmineClient`, as far as this page uses it.  Typed HERE, not
 *  imported: importing `../index` would pull zod into this bundle
 *  (`(b-host-surface)` forbids it). */
interface ClientGlobal {
  parseDocument(value: unknown): unknown;
  defaultRegistry(): unknown;
  render(target: Element, doc: unknown, registry: unknown, env: {
    document: Document; fetchData: (token: string) => Promise<never>; htmlwriter?: unknown;
  }): Promise<{ errors: readonly { path: string; widget: string; message: string }[] }>;
}

export interface BootWindow {
  document: Document;
  addEventListener(type: "message", listener: (ev: { data: unknown }) => void): void;
  ErmineClient?: ClientGlobal;
  ermine_htmlwriter?: unknown;
}

/**
 * U6: `fetchData` is a stub that REJECTS, naming the token, and touches
 * nothing: no `fetch`, no `XMLHttpRequest`, no message to the extension (there
 * is no fetch message pair), and the CSP's `default-src 'none'` keeps
 * `connect-src` shut, so the panel could not fetch even if it tried.  The
 * dispatcher turns the rejection into that widget's own error box
 * (`div.ermine-widget-error[data-widget]`, "a deferred relation could not be
 * resolved: ..."), which therefore says why by itself.
 *
 * U6 was TAKEN on the design review's F2, "the preview never mints a deferred
 * token" (`Preview.scala` sends `params` only, so `json.Request`'s defaults
 * deliver every relation inline).  F2 DOES NOT HOLD: a report that asks for
 * `Deferred` itself gets a token whatever the request says --
 * `core/src/test/resources/doc/Sales.e` does, and the S1 capture of its render
 * holds one -- so a document made by the preview's own render request CAN
 * reach this stub.  The refusal STAYS by the user's decision on Q24
 * (2026-09-23: "Do (a) and (d) now, file (c)"): WP-10's done-when is an inline
 * fixture (`Doc/SalesReport.e`), and fetching deferred rows through the
 * extension is WP-30 (the fetch message pair), filed and NOT built.  The text
 * below says what is true in every case: this preview does not fetch, and the
 * report asked.
 */
const DEFERRED_REFUSAL =
  "this preview does not fetch deferred relations, and the report asked for deferred delivery of";

export function refuseDeferred(token: string): Promise<never> {
  return Promise.reject(new Error(
    `${DEFERRED_REFUSAL} "${token}" (the panel has no network access: its CSP has no connect-src)`));
}

/** The one element the extension's html builder puts in the body
 *  (`preview-core.js` `PREVIEW_ROOT_ID`). */
export const PREVIEW_ROOT_ID = "ermine-preview-root";

const PAGE_CSS = `
#${PREVIEW_ROOT_ID}{font-family:var(--vscode-font-family);color:var(--vscode-foreground)}
.ermine-banner{display:flex;gap:1em;align-items:center;padding:.4em .8em;margin-bottom:.6em;border-left:4px solid var(--vscode-focusBorder,#888)}
.ermine-banner[hidden]{display:none}
.ermine-banner[data-kind=error],.ermine-banner[data-kind=stuck],.ermine-banner[data-kind=offline]{border-left-color:var(--vscode-editorError-foreground,#c33)}
.ermine-banner[data-kind=held]{border-left-color:var(--vscode-editorWarning-foreground,#c93)}
.ermine-hint{opacity:.8;font-style:italic;margin-bottom:.6em}
.ermine-document.ermine-dimmed{opacity:.45}
.ermine-page-error{color:var(--vscode-editorError-foreground,#c33)}
`;

export interface PageHandle {
  /** The page's current model (for tests and for debugging from devtools). */
  readonly model: () => PageModel;
  /** How many times the document area was (re)rendered or emptied. */
  readonly renders: () => number;
}

/**
 * Wire the page.  Posts `ready` once the DOM is there (after
 * DOMContentLoaded, so the writers' own listener, registered by an earlier
 * script, has already run and `window.ermine_htmlwriter` exists), then folds
 * every snapshot through `pageStep`, redraws the banner, hint and dimming
 * from `presentation()`, and re-renders the document ONLY when `pageStep`
 * says it changed.  Returns a handle for tests.
 */
export function boot(win: BootWindow, api: VsCodeApi): PageHandle {
  const doc = win.document;
  let page = initialPage();
  let renders = 0;
  let token = 0;
  const post = (m: unknown): void => {
    try { api.postMessage(m); } catch { /* nothing to tell: the channel IS the log */ }
  };
  const log = (message: string): void => post({ type: "log", message });

  let banner: HTMLElement, bannerText: HTMLElement, restart: HTMLButtonElement;
  let hint: HTMLElement, area: HTMLElement;

  const layout = (): void => {
    const root = doc.getElementById(PREVIEW_ROOT_ID) ?? doc.body;
    const style = doc.createElement("style");
    style.textContent = PAGE_CSS;
    doc.head.appendChild(style);
    banner = doc.createElement("div");
    banner.className = "ermine-banner";
    banner.setAttribute("role", "status");
    bannerText = doc.createElement("span");
    restart = doc.createElement("button");
    restart.type = "button";
    restart.textContent = "Restart Language Server";
    // U4: the one action.  An INTENT: the extension runs its own command.
    restart.addEventListener("click", () => post({ type: "intent", kind: "restartServer" }));
    banner.append(bannerText, restart);
    hint = doc.createElement("div");
    hint.className = "ermine-hint";
    area = doc.createElement("div");
    area.className = "ermine-document";
    root.append(banner, hint, area);
  };

  const draw = (): void => {
    const p = presentation(page.host);
    banner.hidden = p.banner === null;
    banner.setAttribute("data-kind", p.banner?.kind ?? "");
    bannerText.textContent = p.banner?.text ?? "";
    restart.hidden = p.banner?.action !== "restartServer";
    hint.hidden = p.hint === null;
    hint.textContent = p.hint ?? "";
    area.hidden = !p.showDocument;
    area.classList.toggle("ermine-dimmed", p.dimmed);
  };

  const renderDocument = async (): Promise<void> => {
    const mine = ++token;
    renders += 1;
    // A FRESH slot per render, attached now: a slower, older render that
    // finishes later writes into a slot that is no longer in the page.
    const slot = doc.createElement("div");
    area.replaceChildren(slot);
    const d = page.host.document;
    if (d === null) return;
    const client = win.ErmineClient;
    const fail = (what: string): void => {
      const box = doc.createElement("div");
      box.className = "ermine-page-error";
      box.setAttribute("role", "alert");
      box.textContent = what;
      slot.replaceChildren(box);
      log(what);
    };
    if (!client || typeof client.render !== "function") {
      fail("the client bundle (window.ErmineClient) is not loaded, so the document cannot be drawn");
      return;
    }
    let parsed: unknown;
    try {
      parsed = client.parseDocument(d.payload);
    } catch (e) {
      fail(`the document could not be read: ${(e as Error)?.message ?? String(e)}`);
      return;
    }
    try {
      const result = await client.render(slot, parsed, client.defaultRegistry(), {
        document: doc,
        fetchData: refuseDeferred,
        // read at RENDER time, never at script-evaluation time (§2(e))
        htmlwriter: win.ermine_htmlwriter,
      });
      if (mine !== token) return;
      for (const e of result.errors) log(`widget "${e.widget}" at ${e.path}: ${e.message}`);
    } catch (e) {
      if (mine === token) fail(`the document could not be rendered: ${(e as Error)?.message ?? String(e)}`);
    }
  };

  const onMessage = (ev: { data: unknown }): void => {
    const step = pageStep(page, ev.data);
    if (!step.accepted) return;
    page = step.page;
    draw();
    if (step.rerender) void renderDocument();
  };

  const start = (): void => {
    layout();
    draw();
    win.addEventListener("message", onMessage);
    post({ type: "ready" });
  };
  if (doc.readyState === "loading") doc.addEventListener("DOMContentLoaded", start);
  else start();
  return { model: () => page, renders: () => renders };
}

// ------------------------------------------------------------- autostart

declare const acquireVsCodeApi: undefined | (() => VsCodeApi);

/** Runs `boot` in a VS Code webview -- and ONLY there: `acquireVsCodeApi` is
 *  called ONCE (a second call throws), here and nowhere else. */
function autostart(): void {
  if (typeof acquireVsCodeApi !== "function" || typeof window === "undefined") return;
  boot(window as unknown as BootWindow, acquireVsCodeApi());
}
autostart();
