// The preview panel's PRESENTATION reducer -- the webview half of the
// extension <-> panel message protocol (§5's "Host-page logic" row).
//
// WP-9 builds the SKELETON and the second webpack entry it is bundled as
// (`ermine-host`); WP-10 owns the panel itself -- the host page, the CSP, the
// `acquireVsCodeApi()` plumbing, the DOM the banners are drawn into, the bundle
// watcher.  Nothing here touches the DOM or `window`.
//
// THE ONE RULE THIS FILE OBEYS (the design review's D10).  There are TWO
// reducers over overlapping state: `editor/vscode/src/preview-core.js`'s
// `stuckReduce` (WP-7, on the extension side) and this one.  They cannot
// disagree because only ONE of them decides anything:
//
//   * every DECISION stays in `preview-core.js` -- is this answer current, is
//     this `seq` newer than the last, should we re-render, did the wedge clear,
//     is the pick held;
//   * this reducer decides only what the panel SHOWS for the messages it is
//     handed: which banner, whether the document is visible, whether it is
//     dimmed, and the unsaved hint beside it.
//
// So there is deliberately NO `seq` arbitration here and no generation
// comparison: §4's client contract rule (1) (keep the highest `seq`, reset the
// mark on Stopped -> Running) is the EXTENSION's, and a `stuck` message that
// reaches this reducer has already been decided to be believed.  `seq` is
// carried in the state only so a panel can show it while debugging.
//
// THE MESSAGE KINDS are §5's eight -- `render`, `error`, `stale`, `stuck`,
// `reloadBundle`, `unsaved`, `switching`, `offline` -- plus WP-22's ninth,
// `held` (a report that wedged and was killed is not re-rendered without a
// confirmation).  §4's rule (5) is WITHDRAWN (WP-24): a client gets one rising
// edge per watchdog incident again, so nothing here treats a missing falling
// edge as special, and nothing here expects a cancel that sends no pair at all.
//
// The document is carried as an OPAQUE payload.  This module does not import
// `../document` and so pulls neither zod nor the widget schemas into
// `ermine-host.js`: parsing and rendering are `ermine-client.js`'s job, and the
// panel hands the payload straight to `ErmineClient.parseDocument`.

// ------------------------------------------------------------------ messages

/** A document to show.  `generation` is carried, never compared (D10). */
export interface RenderMessage { kind: "render"; document: unknown; generation?: number | null }
/** An `{ok: false}` answer: §4's `status` / `message` / `path` / `reason`. */
export interface ErrorMessage {
  kind: "error"; status: number; message: string;
  path?: string | null; reason?: string | null;
}
/** §2.5: a re-render is in flight and the document below may be behind. */
export interface StaleMessage { kind: "stale"; stale: boolean }
/** §4's `ermine/preview/stuck`, already arbitrated by the extension. */
export interface StuckMessage { kind: "stuck"; stuck: boolean; message?: string; seq?: number | null }
/** WP-22: the pick wedged, was killed, and has not changed since. */
export interface HeldMessage { kind: "held"; held: boolean; message?: string }
/** The language client's Stopped / Running transition (§5). */
export interface OfflineMessage { kind: "offline"; offline: boolean }
/** A profile or roots switch (§7.2); `to: null` ends it, and so does a blank
 *  id -- an empty string names no target, so it is a missing value, not one. */
export interface SwitchingMessage { kind: "switching"; to: string | null }
/** The dirty `.e` documents in the workspace, by name (§5). */
export interface UnsavedMessage { kind: "unsaved"; names: readonly string[] }
/** The client bundle changed on disk; the panel is about to be reset (§5). */
export interface ReloadBundleMessage { kind: "reloadBundle" }

export type HostMessage =
  | RenderMessage | ErrorMessage | StaleMessage | StuckMessage | HeldMessage
  | OfflineMessage | SwitchingMessage | UnsavedMessage | ReloadBundleMessage;

/** The nine kinds, in one place, so a test can enumerate them. */
export const MESSAGE_KINDS = [
  "render", "error", "stale", "stuck", "held", "offline", "switching",
  "unsaved", "reloadBundle",
] as const;

export type MessageKind = (typeof MESSAGE_KINDS)[number];

// -------------------------------------------------------------------- state

export interface HostDocument { readonly payload: unknown; readonly generation: number | null }
export interface HostError {
  readonly status: number; readonly message: string;
  readonly path: string | null; readonly reason: string | null;
}
export interface HostStuck { readonly message: string; readonly seq: number | null }
export interface HostHeld { readonly message: string }

/** Everything the panel needs to draw itself, and nothing else. */
export interface HostState {
  /** The last document the panel was told to show; kept across every failure. */
  readonly document: HostDocument | null;
  readonly error: HostError | null;
  readonly stale: boolean;
  readonly stuck: HostStuck | null;
  readonly held: HostHeld | null;
  readonly offline: boolean;
  /** The profile or roots id being switched to, or null. */
  readonly switching: string | null;
  readonly unsaved: readonly string[];
  /** A bundle reload was announced; the host page is about to be replaced.
   *  Cleared by the next ANSWER -- see `applyMessage`. */
  readonly reloading: boolean;
}

export function initialHostState(): HostState {
  return {
    document: null, error: null, stale: false, stuck: null, held: null,
    offline: false, switching: null, unsaved: [], reloading: false,
  };
}

// ------------------------------------------------------------------ reducer

/** Fold one message into the state.
 *
 *  TOTAL and PURE: it never throws, never mutates `state`, and returns `state`
 *  ITSELF (by identity) for anything it does not recognise -- a message from a
 *  newer extension must leave an older panel exactly as it was, not blank it.
 *
 *  Each message touches only its own slice.  The exceptions are all in the
 *  ANSWER PAIR, `render` and `error`:
 *
 *   * a `render` clears the error it supersedes, and both end the re-render;
 *   * an `error` KEEPS the last document (§5: the last good document stays
 *     below, dimmed);
 *   * **both clear `reloading`.**  `reloadBundle` is an announcement, and the
 *     reload it announces normally destroys this page -- §5 re-sets
 *     `webview.html`, so a real reload is a fresh state, not a cleared flag.
 *     The flag therefore only ever survives when the reload did NOT happen
 *     (debounced away, or the write failed), and an answer arriving proves this
 *     page is still alive and talking.  Without this, `reloading` outranks
 *     `error` and would mask every later failure for the life of the panel
 *     (the WP-9 review measured it winning 16.5 % of generated states once
 *     raised).  It is the only latch whose falling edge is not its own message,
 *     because it is the only one the EXTENSION never retracts.
 *
 *  In particular no answer clears `stuck` or `held`: §4's rule (2) makes the
 *  notification authoritative for the wedge, and WP-22's mark is the
 *  extension's -- deciding here that a document means the wedge is over is
 *  exactly the second decision D10 forbids. */
export function applyMessage(state: HostState, msg: HostMessage): HostState {
  if (msg === null || typeof msg !== "object") return state;
  switch (msg.kind) {
    case "render":
      return {
        ...state,
        document: { payload: msg.document, generation: numberOrNull(msg.generation) },
        error: null,
        stale: false,
        reloading: false,
      };
    case "error":
      return {
        ...state,
        error: {
          status: typeof msg.status === "number" ? msg.status : 0,
          message: stringOr(msg.message, ERROR_DEFAULT),
          path: stringOrNull(msg.path),
          reason: stringOrNull(msg.reason),
        },
        stale: false,
        reloading: false,
      };
    case "stale":
      return { ...state, stale: msg.stale === true };
    case "stuck":
      return {
        ...state,
        stuck: msg.stuck === true
          ? { message: stringOr(msg.message, STUCK_DEFAULT), seq: numberOrNull(msg.seq) }
          : null,
      };
    case "held":
      return {
        ...state,
        held: msg.held === true ? { message: stringOr(msg.message, HELD_DEFAULT) } : null,
      };
    case "offline":
      return { ...state, offline: msg.offline === true };
    case "switching":
      return { ...state, switching: stringOrNull(msg.to) };
    case "unsaved":
      return { ...state, unsaved: Array.isArray(msg.names) ? msg.names.filter(isString) : [] };
    case "reloadBundle":
      return { ...state, reloading: true };
    default:
      return state;
  }
}

const STUCK_DEFAULT = "the evaluation did not finish";
const HELD_DEFAULT = "this report wedged and was stopped; it has not changed since";
const ERROR_DEFAULT = "the render failed";

// A BLANK string is not a value here, it is a missing one.  Found by
// `(h-prop-consistent)`: `{kind: "stuck", stuck: true, message: ""}` is a legal
// message on the wire (§4 does not promise a non-empty `message`), and taking
// it literally drew a banner that said NOTHING -- visible as a coloured strip
// with no text, which is worse than no banner at all.  Normalising at the
// reducer's boundary keeps every drawing site free of the check.
function isString(v: unknown): v is string { return typeof v === "string"; }
function nonBlank(v: unknown): v is string { return isString(v) && v.trim() !== ""; }
function stringOr(v: unknown, fallback: string): string { return nonBlank(v) ? v : fallback; }
function stringOrNull(v: unknown): string | null { return nonBlank(v) ? v : null; }
function numberOrNull(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

// --------------------------------------------------------------- what to show

export type BannerKind =
  | "offline" | "stuck" | "held" | "reloading" | "switching" | "error" | "stale" | "initial";

/** The only action a banner offers today: the panel's own
 *  **Ermine: Restart Language Server** button (§5's Stuck row -- an LSP server
 *  cannot make a client run a client-side command, so the button is the
 *  panel's).  WP-22's **Render anyway** is deliberately NOT here: that
 *  confirmation is a `showWarningMessage` on the extension side, and the `held`
 *  banner is informational. */
export type PanelAction = "restartServer";

/** Highest first.  The order mirrors WP-22's status-bar precedence
 *  (offline > stuck > held > rendering > idle) and slots the three states the
 *  status bar has no branch for -- a pending bundle reload, a switch, and a
 *  failed answer -- above `stale`, which is the "rendering" one. */
export const BANNER_PRECEDENCE: readonly BannerKind[] = [
  "offline", "stuck", "held", "reloading", "switching", "error", "stale", "initial",
];

export interface Banner {
  readonly kind: BannerKind;
  readonly text: string;
  readonly action: PanelAction | null;
}

export interface Presentation {
  /** The one banner to draw, or null when there is nothing to say. */
  readonly banner: Banner | null;
  readonly showDocument: boolean;
  /** THE DIMMING RULE, in one sentence: a document on screen is dimmed exactly
   *  when NOTHING IS CURRENTLY TRYING TO REPLACE IT.
   *
   *  So `offline` (the server is gone), `error` (the attempt failed),
   *  `switching` (the inputs are changing under it) and `held` (WP-22: we have
   *  not even asked) all dim; `stale` (a re-render is in flight) and `stuck`
   *  (the evaluation has not returned, and Q10's recovery may still bring it
   *  back) do NOT, because something is still coming; and `reloading` does not
   *  because the page is about to be replaced wholesale and a flicker there
   *  would be for nothing.  `(h-dim-table)` pins the whole table. */
  readonly dimmed: boolean;
  /** The non-blocking unsaved hint, drawn beside the banner, never instead. */
  readonly hint: string | null;
}

/** Which banner states are ACTIVE, highest precedence first.  Exported because
 *  the precedence, not just the winner, is what a test wants to pin. */
export function activeBanners(state: HostState): readonly BannerKind[] {
  const on: Record<BannerKind, boolean> = {
    offline: state.offline,
    stuck: state.stuck !== null,
    held: state.held !== null,
    reloading: state.reloading,
    switching: state.switching !== null,
    error: state.error !== null,
    stale: state.stale,
    initial: state.document === null,
  };
  return BANNER_PRECEDENCE.filter((k) => on[k]);
}

/** The whole of what the panel draws, derived from the state. */
export function presentation(state: HostState): Presentation {
  const kind = activeBanners(state)[0] ?? null;
  const showDocument = state.document !== null;
  return {
    banner: kind === null ? null : bannerFor(kind, state),
    showDocument,
    dimmed: showDocument &&
      (state.offline || state.switching !== null || state.error !== null || state.held !== null),
    hint: state.unsaved.length === 0 ? null : `unsaved: ${state.unsaved.join(", ")}`,
  };
}

function bannerFor(kind: BannerKind, state: HostState): Banner {
  switch (kind) {
    case "offline":
      return { kind, text: "server stopped -- last document kept", action: null };
    case "stuck":
      return { kind, text: state.stuck?.message ?? STUCK_DEFAULT, action: "restartServer" };
    case "held":
      return { kind, text: state.held?.message ?? HELD_DEFAULT, action: null };
    case "reloading":
      return { kind, text: "the client bundle changed; reloading", action: null };
    case "switching":
      return { kind, text: `switching to ${state.switching ?? ""}`, action: null };
    case "error":
      return { kind, text: errorText(state.error), action: null };
    case "stale":
      return { kind, text: "re-rendering", action: null };
    case "initial":
      return { kind, text: "Pick a report: Ermine: Preview Report...", action: null };
  }
}

function errorText(e: HostError | null): string {
  if (e === null) return "";
  const head = e.status === 0 ? e.message : `${e.status}: ${e.message}`;
  return e.path === null ? head : `${head} (${e.path})`;
}
