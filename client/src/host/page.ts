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
// ENVELOPE handled here, not a reducer kind -- `MESSAGE_KINDS` holds the ten
// message kinds (S2d added `trace`) and `applyMessage` returns by identity if
// it is ever handed a snapshot.
//
// Nothing here decides anything either (D10): the snapshot REPLACES the state,
// wholesale, with what the extension says is true.

import {
  applyMessage, initialHostState, presentation,
  type HostMessage, type HostState, type HostDocument,
} from "./index";

export * from "./index";

/** The resync envelope: the whole truth, as the message kinds.  Since S2 it is
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

/** What `acquireVsCodeApi()` returns, as far as this page uses it.
 *  `getState`/`setState` are the webview's own per-viewer store (restored when
 *  the webview is re-created); optional here so a stub without them still boots,
 *  and the page then starts in the Document view every time (WP-31). */
export interface VsCodeApi {
  postMessage(message: unknown): unknown;
  getState?(): unknown;
  setState?(state: unknown): unknown;
}

// ---------------------------------------------- the Document / JSON toggle (WP-31)

/** Which view of the answer the panel shows.  VIEWER-LOCAL (the WP-10 design
 *  review §2(a): "Use setState only for viewer-local trivia the extension
 *  cannot know"): kept with `setState`/`getState`, never posted to the
 *  extension and never part of the reducer or `PageModel`. */
export type PanelView = "document" | "json" | "trace";

/** The view a `getState()` value restores: `json` or (S2d) `trace` only when
 *  it says so exactly; anything else (nothing stored, another shape) is the
 *  Document. */
export function restoredView(state: unknown): PanelView {
  const v = state !== null && typeof state === "object" ? (state as { view?: unknown }).view : undefined;
  return v === "json" || v === "trace" ? v : "document";
}

/**
 * What the JSON view shows: the same text `editor/vscode/src/preview-core.js`
 * `tabContent` puts in the JSON tab, AS FAR AS THE PANEL CAN KNOW IT.
 *
 *   * the last answer was a document (`render`, no `error` after it): exactly
 *     `JSON.stringify(document, null, 2)`, the tab's `ok` case;
 *   * the last message was an `error`: its fields `{status, message, path,
 *     reason}`, pretty-printed the same way.  This is NOT byte-for-byte the
 *     tab's `{ok:false}` case: the panel is not sent the raw wire answer, so
 *     `ok`, `generation` and `stale` are not here; the reducer has normalised
 *     the fields (a blank message is "the render failed", a missing path or
 *     reason is null); and the extension's `panelErrorMessage` may have appended
 *     the fast-mode sentence or the writers note to `message`.  A missing
 *     writers bundle reaches the panel as an `error` (status 0) even when the
 *     answer was a document, and then that error is what shows.  Forwarding the
 *     raw answer would be an EXTENSION change (tracker Q28, offered, not built);
 *   * nothing yet: the empty string.
 *
 * `render` clears `error` in the reducer, so a non-null `error` is always the
 * more recent of the two.
 */
export function jsonViewText(host: HostState): string {
  const value: unknown = host.error !== null
    ? { status: host.error.status, message: host.error.message, path: host.error.path, reason: host.error.reason }
    : host.document !== null ? host.document.payload : undefined;
  if (value === undefined) return "";
  try {
    return JSON.stringify(value, null, 2) ?? "";
  } catch (e) {
    return JSON.stringify({ error: `the answer could not be printed: ${(e as Error)?.message ?? String(e)}` }, null, 2);
  }
}

// ---- S2d trace (panel) ----
//
// THE TRACE VIEW'S PURE HALF (DB programme stage 2, DESIGN-OBSERVABILITY §3.1).
// The payload is what the extension's `traceOf` (`editor/vscode/src/
// preview-core.js`) built from the last CURRENT answer: already normalised, so
// nothing here decides which trace belongs to the view (D10).  Everything below
// still reads it defensively -- a payload from a newer extension must draw
// something, never throw.

/** One query of a normalised trace, as far as the view reads it. */
export interface TraceQueryView {
  relation: string; delivery: string | null; dialect: string | null;
  sql: string | null; sqlBytes: number | null; sqlTruncated: boolean;
  rows: number | null; rowsRead: number | null; scanned: number | null; ms: number | null; dbMs: number | null;
  setup: readonly { kind: string; table: string | null; rows: number | null; ms: number | null; created: boolean | null }[];
  overThreshold: boolean; error: boolean; note: string | null;
}
/** A normalised trace, as far as the view reads it (see `traceOf`). */
export interface TraceView {
  generation: number | null; failed: boolean; status: number | null;
  wallMs: number | null;
  phases: readonly { name: string; ms: number; cached: boolean }[];
  queries: readonly TraceQueryView[];
  totals: { dbMs: number; otherMs: number; wallMs: number; queries: number; rows: number | null; rowsRead: number | null };
  connection: { kind: string | null; dialect: string | null; profile: string | null; database: string | null; host: string | null } | null;
  partial: boolean;
  running: { relation: string | null; phase: string | null; sql: string | null; sinceMs: number | null } | null;
  truncated: { queries: number } | null;
}

const num = (v: unknown): number | null => typeof v === "number" && Number.isFinite(v) ? v : null;
const str = (v: unknown): string | null => typeof v === "string" && v.trim() !== "" ? v : null;
const obj = (v: unknown): Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
const arr = (v: unknown): unknown[] => Array.isArray(v) ? v : [];

/** Read a trace payload into the view's shape.  Total: junk gives an empty trace. */
export function readTrace(payload: unknown): TraceView {
  const t = obj(payload);
  const tot = obj(t["totals"]);
  const conn = t["connection"] !== null && typeof t["connection"] === "object" ? obj(t["connection"]) : null;
  const run = t["running"] !== null && typeof t["running"] === "object" ? obj(t["running"]) : null;
  const trunc = t["truncated"] !== null && typeof t["truncated"] === "object" ? obj(t["truncated"]) : null;
  const queries: TraceQueryView[] = arr(t["queries"]).map((q0) => {
    const q = obj(q0);
    return {
      relation: str(q["relation"]) ?? "?", delivery: str(q["delivery"]), dialect: str(q["dialect"]),
      sql: typeof q["sql"] === "string" ? q["sql"] as string : null, sqlBytes: num(q["sqlBytes"]), sqlTruncated: q["sqlTruncated"] === true,
      rows: num(q["rows"]), rowsRead: num(q["rowsRead"]), scanned: num(q["scanned"]) ?? num(q["rowsRead"]), ms: num(q["ms"]), dbMs: num(q["dbMs"]),
      setup: arr(q["setup"]).map((s0) => {
        const x = obj(s0);
        return { kind: str(x["kind"]) ?? "statement", table: str(x["table"]), rows: num(x["rows"]), ms: num(x["ms"]),
          created: typeof x["created"] === "boolean" ? x["created"] as boolean : null };
      }),
      overThreshold: q["overThreshold"] === true, error: q["error"] === true, note: str(q["note"]),
    };
  });
  const wall = num(t["wallMs"]) ?? num(tot["wallMs"]);
  const db = num(tot["dbMs"]) ?? 0;
  return {
    generation: num(t["generation"]), failed: t["failed"] === true, status: num(t["status"]),
    wallMs: wall,
    phases: arr(t["phases"]).map((p0) => {
      const p = obj(p0);
      return { name: str(p["name"]) ?? "?", ms: Math.max(0, num(p["ms"]) ?? 0), cached: p["cached"] === true };
    }),
    queries,
    totals: {
      dbMs: db, otherMs: num(tot["otherMs"]) ?? Math.max(0, (wall ?? 0) - db), wallMs: num(tot["wallMs"]) ?? wall ?? 0,
      queries: num(tot["queries"]) ?? queries.length, rows: num(tot["rows"]), rowsRead: num(tot["rowsRead"]),
    },
    connection: conn === null ? null : {
      kind: str(conn["kind"]), dialect: str(conn["dialect"]), profile: str(conn["profile"]),
      database: str(conn["database"]), host: str(conn["host"]),
    },
    partial: t["partial"] === true,
    running: run === null ? null : { relation: str(run["relation"]) ?? str(run["path"]), phase: str(run["phase"]), sql: typeof run["sql"] === "string" ? run["sql"] as string : null, sinceMs: num(run["sinceMs"]) },
    truncated: trunc === null || num(trunc["queries"]) === null ? null : { queries: num(trunc["queries"])! },
  };
}

/** `1676` -> `1,676`; the same grouping `preview-core.js`'s output line uses. */
export function formatCount(n: number): string {
  const whole = Math.round(n);
  const sign = whole < 0 ? "-" : "";
  return sign + String(Math.abs(whole)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
/** Milliseconds: one decimal under 10 ms (an in-memory scan is 0.4 ms), whole and grouped above. */
export function formatMs(ms: number): string {
  return (Math.abs(ms) < 10 ? (Math.round(ms * 10) / 10).toFixed(1) : formatCount(ms)) + " ms";
}

/** The phases that ARE the database (§2.1: `dbMs` = sql + connect). */
const DB_PHASES = ["sql", "connect", "db-execute", "db-fetch"];

export interface TraceSegment { readonly key: string; readonly label: string; readonly ms: number; readonly pct: number }

/**
 * The phase bar, left to right: `db` first, then every other phase in the
 * server's (pipeline) order, then `other`, the part of the wall time no phase
 * explains (§2.1's rule: never computed by summing, so a gap shows).  Widths
 * are percentages of the larger of the wall time and the segments' sum, and
 * they SUM TO 100 exactly (the last segment absorbs the rounding).  A trace
 * with no time at all has no bar.
 */
export function traceSegments(t: TraceView): TraceSegment[] {
  const raw: { key: string; label: string; ms: number }[] = [];
  if (t.totals.dbMs > 0) raw.push({ key: "db", label: "db", ms: t.totals.dbMs });
  for (const p of t.phases) {
    if (DB_PHASES.includes(p.name) || p.ms <= 0) continue;
    raw.push({ key: p.name, label: p.name, ms: p.ms });
  }
  const explained = raw.reduce((a, s) => a + s.ms, 0);
  const wall = t.totals.wallMs > 0 ? t.totals.wallMs : explained;
  if (wall - explained > 0.05) raw.push({ key: "other", label: "other", ms: wall - explained });
  const total = Math.max(wall, explained);
  if (!(total > 0) || raw.length === 0) return [];
  let used = 0;
  return raw.map((s, i) => {
    const pct = i === raw.length - 1 ? Math.round((100 - used) * 100) / 100 : Math.round(s.ms / total * 10000) / 100;
    used += pct;
    return { ...s, pct };
  });
}

/** §3.1's headline: `render 412 ms: db 310 ms (75%), 3 queries, 1,676 rows · generation 12`. */
export function traceHeadline(t: TraceView): string {
  const wall = t.totals.wallMs;
  const pct = wall > 0 ? ` (${Math.round(t.totals.dbMs / wall * 100)}%)` : "";
  const q = t.totals.queries;
  const rows = t.totals.rows ?? t.queries.reduce((a, x) => a + (x.rows ?? 0), 0);
  const head = t.partial ? `stuck: partial trace, ${formatMs(wall)} so far` : `render ${formatMs(wall)}`;
  return `${head}: db ${formatMs(t.totals.dbMs)}${pct}, ${formatCount(q)} ${q === 1 ? "query" : "queries"}, ` +
    `${formatCount(rows)} ${rows === 1 ? "row" : "rows"}` +
    (t.totals.rowsRead !== null && t.totals.rowsRead > rows ? ` (${formatCount(t.totals.rowsRead)} read)` : "") + (t.generation === null ? "" : ` · generation ${t.generation}`);
}

/** §5's connection line.  The in-memory database is said to be per render, so
 *  a memo "created" on every render is not read as a bug. */
export function traceConnectionText(t: TraceView): string {
  const c = t.connection;
  if (c === null) return "connection: not reported";
  if (c.kind === "in-memory" || (c.profile === null && c.kind !== "profile")) {
    return `in-memory ${c.dialect ?? "sqlite"} (per render: memo tables are rebuilt every time)`;
  }
  return `${c.profile ?? "profile"}${c.dialect ? ` (${c.dialect})` : ""}${c.host ? ` @ ${c.host}` : ""}${c.database ? ` / ${c.database}` : ""}`;
}

/** What the Trace view says when the last answer carried no trace. */
export const NO_TRACE_FAILED = "no trace: the render did not reach the server (or the server sends none)";
export const NO_TRACE_OK = "no trace: this answer carried none (a server from before DB stage 2 sends none)";
// ---- end S2d trace ----

/** `window.ErmineClient`, as far as this page uses it.  Typed HERE, not
 *  imported: importing `../index` would pull zod into this bundle
 *  (`(b-host-surface)` forbids it). */
interface ClientGlobal {
  parseDocument(value: unknown): unknown;
  defaultRegistry(): unknown;
  render(target: Element, doc: unknown, registry: unknown, env: {
    document: Document; fetchData: (token: string) => Promise<never>; htmlwriter?: unknown; idPrefix?: string;
  }): Promise<{ errors: readonly { path: string; widget: string; message: string }[] }>;
}

export interface BootWindow {
  document: Document;
  /** S2d: the Trace view's Copy button; absent or refusing, the SQL is selected instead. */
  navigator?: { clipboard?: { writeText?(text: string): Promise<unknown> } };
  getSelection?(): Selection | null;
  addEventListener(type: "message", listener: (ev: { data: unknown }) => void): void;
  ErmineClient?: ClientGlobal;
  ermine_htmlwriter?: unknown;
  /** The writers' page configuration.  Its `renderFunction(htmlwriter)` DRAWS
   *  what the `run*` calls only queued: the legacy page calls it once, after
   *  `renderPage` (HTMLWriter.scala `wrapHeader` ~:365-376).  F3 (2026-09-23). */
  ermine_htmlwriter_conf?: { renderFunction?: (htmlwriter: unknown) => unknown };
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
 * `Deferred` itself gets a token whatever the request says -- `doc/SalesRaw.e`
 * does (`Sales.e` did until Q25 typed it), and the S1 capture of the old Sales
 * held one -- so a document made by the preview's own render request CAN
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

/** What the log says, once per page, when the writers' draw step is missing. */
export const NO_RENDER_FUNCTION =
  "window.ermine_htmlwriter_conf.renderFunction is not there, so the legacy widgets (tables, charts) were queued but not drawn";

/**
 * The page's own CSS.  F3 (playtest, 2026-09-23):
 *
 *   * the banner and hint keep the THEME's colours: `--vscode-editor-foreground`
 *     (the colour the webview's body text has), not `--vscode-foreground`, which
 *     some themes set to a mid grey (#9e9e9e in the user's);
 *   * the document draws on a white PAPER with #222 text.  The writers' CSS is
 *     only ever used on a white page: it colours headers (#48535B) and stripes
 *     (#E9E9E9 / #fff) and lets every cell INHERIT its text colour, so under a
 *     dark theme the cells were theme-grey on light grey (2.2:1).  Theme-aware
 *     overrides would have to re-colour every writers rule with no reference
 *     rendering, and are not attempted;
 *   * the page's own error box is drawn INSIDE the paper, so it takes a red
 *     chosen for white (#b00020, 7.33:1), not the theme's error colour (a dark
 *     theme's is chosen for a dark background: #f48771 is 2.46:1 on white);
 *   * the writers' common.css makes the body 10px (`font-size:62.5%`) and the
 *     cells 10px outright: the root takes the editor's `--vscode-font-size`
 *     back (so the banner is not 10px either), inside the paper the base is
 *     13px and table text 12px;
 *   * `Grid` is laid out as a grid (the dispatcher emits rows of cells and no
 *     CSS; it stacked into one column), a row's cells wrapping under each
 *     other only when a cell would be narrower than 480px; `HFlow` as a row;
 *   * the writers' tables, MEASURED in a headless harness (F3 IMPL-REPORT):
 *     each table is split into a row-header part (`.rowheader-table`, the
 *     primary column) and a `.main-table` part, and the writers size the pair
 *     to the WINDOW's width, whatever the container (1200px viewport -> a
 *     1200px wrapper in a 560px grid cell, drawn over its neighbour).  So the
 *     pair is a flex row no wider than its cell, the main part scrolling
 *     sideways inside it.  A ONE-column table is all row header: its main part
 *     has no columns and 0px height, and the writers give the row-header
 *     scroller that height too, so its rows were drawn at 0px (not a timing
 *     effect: drawing after two animation frames or 500 ms, or with the table
 *     alone, measured the same 0px).  Such a scroller gets its natural height.
 *     And the main part's truncating cell spans are inline-blocks with
 *     overflow:hidden, which sit on their bottom edge and make those rows 3px
 *     taller than the row-header rows beside them: top-aligned here.
 *
 * WP-31, MEASURED in the same harness (json-toggle IMPL-REPORT): a document
 * rendered while `display:none` is drawn wrong by the writers -- every table
 * stayed its one-row skeleton, 38px, after switching back, and DataTables
 * logged `andSelf is not a function` from `fnDestroy`.  So the document the
 * JSON view hides keeps its `hidden` attribute but is laid out OFF-STAGE
 * (`.ermine-offstage`): full width, invisible, zero CONTENT height (the
 * paper's padding keeps the box 20px tall, MEASURED by the WP-31 review; it
 * adds nothing to the page's scroll height), clipped, out of
 * the flow and out of the accessibility tree.  The root is `position:relative`
 * so that width is the document's own.
 *
 * Everything document-side is scoped under `#${PREVIEW_ROOT_ID} .ermine-document`,
 * so nothing leaks onto the banner or the page around it.
 */
/**
 * S2f-1 (DB programme, 2026-09-25, MEASURED in a headless harness,
 * scratch-widget-preview/db/s2f/): THE CHARTS.  The writers draw Highcharts
 * in STYLED MODE (`styledMode: true` in htmlwriter.js), so every colour and
 * fill comes from CSS, and those rules live only in the writers'
 * `javafxwriter.css`, which the page did not link (every chart drew as a
 * black box).  The extension now links it as the FOURTH sheet
 * (`preview-core.js` `PREVIEW_WRITERS_STYLES`).  It was written for a JavaFX
 * window holding ONE chart, and three of its effects are countered here:
 *   * `body{background-color:white}` -- the page's body keeps the editor's
 *     background (the only rule outside the root, and it restates the theme);
 *   * `.timeseries{position:fixed;width:100%;height:100%}`, and the writers
 *     size each chart's div to the WINDOW (`getHighestParentSize` walks up to
 *     `body` unless a parent carries an INLINE height or `.widget_body`, then
 *     uses `$(window).height()`): so a chart div is `CHART_HEIGHT` px tall and
 *     as wide as its cell, `!important` over the writers' inline size.
 *     Highcharts reads its container's size when it draws, so the chart is
 *     DRAWN at that size, not clipped (MEASURED: container 1056x320);
 *   * a `RightTable` pie legend's SVG symbols are hidden, as `common.css`
 *     already does for the drilldown pie (its "wacky" swatch comment): the
 *     HTML legend rows carry their own swatches.
 * And the headline's figures and the scorecard's cards are laid out as a ROW
 * of label-over-value pairs rather than the browser's default list layout
 * (CSS only; the widgets' markup is unchanged).
 */
const CHART_HEIGHT = 320;
const PAPER = `#${PREVIEW_ROOT_ID} .ermine-document`;
/** WP-31: the JSON view's `<pre>`, drawn on the same paper as the document. */
const JSON_PAPER = `#${PREVIEW_ROOT_ID} .ermine-json`;
/** WP-31: the Document / JSON toolbar.  It sits between the banner and the
 *  paper, OUTSIDE it, so it keeps the theme's own colours: the pressed control
 *  is a VS Code button (`--vscode-button-background` / `-foreground`), the
 *  other is editor text on the editor background with a button-coloured
 *  border.  Not dimmed with the document (it is how you read the answer). */
const VIEWBAR = `#${PREVIEW_ROOT_ID} .ermine-viewbar`;
/** S2d: the Trace view, drawn on the same white paper as the JSON view, so
 *  every colour in it is FIXED and its contrast is measured once, whatever the
 *  theme (the page test pins each pair at >= 4.5:1). */
const TRACE_PAPER = `#${PREVIEW_ROOT_ID} .ermine-trace`;
const PAGE_CSS = `
#${PREVIEW_ROOT_ID}{position:relative;font-family:var(--vscode-font-family);font-size:var(--vscode-font-size,13px);color:var(--vscode-editor-foreground)}
${PAPER}{background:#fff;color:#222;color-scheme:light;font-size:13px;padding:10px 14px;border-radius:3px}
${PAPER} .ermine-page-error{color:#b00020}
${PAPER} .tabular,${PAPER} th.tabledata-left,${PAPER} th.tabledata-right,${PAPER} td.tabledata-left,${PAPER} td.tabledata-right,${PAPER} .ermine-heading-summary,${PAPER} .ermine-text,${PAPER} .dataTables_info,${PAPER} .dataTables_paginate{font-size:12px}
${PAPER} .ermine-grid{display:grid;gap:16px}
${PAPER} .ermine-grid-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,480px),1fr));gap:16px;align-items:start}
${PAPER} .ermine-grid-cell,${PAPER} .ermine-widget{min-width:0}
${PAPER} .ermine-hflow{display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start}
${PAPER} .table-full-scroll-wrapper{display:flex!important;width:auto!important;max-width:100%;height:auto!important}
${PAPER} .table-full-scroll-wrapper>.rowheader-table{flex:none}
${PAPER} .table-full-scroll-wrapper>.main-table{flex:1 1 auto;min-width:0}
${PAPER} .main-table .table-hscroll-wrapper,${PAPER} .main-table .table-vscroll-pos-wrapper{width:auto!important}
${PAPER} .main-table .tabular{min-width:0}
${PAPER} .table-full-scroll-wrapper:not(:has(.main-table th)) .table-vscroll-wrapper{height:auto!important}
${PAPER} .main-table .dataTable .shrinkable-cell{vertical-align:top}
${VIEWBAR}{display:flex;gap:4px;margin-bottom:6px}
${VIEWBAR}[hidden]{display:none}
${VIEWBAR} button{font:inherit;padding:2px 10px;border-radius:2px;cursor:pointer;background:transparent;color:var(--vscode-editor-foreground);border:1px solid var(--vscode-button-background,#0e639c)}
${VIEWBAR} button[aria-pressed=true]{background:var(--vscode-button-background,#0e639c);color:var(--vscode-button-foreground,#ffffff)}
${VIEWBAR} button:focus-visible{outline:1px solid var(--vscode-focusBorder,#007fd4);outline-offset:2px}
${JSON_PAPER}{background:#fff;color:#222;color-scheme:light;margin:0;padding:10px 14px;border-radius:3px;font-family:var(--vscode-editor-font-family,monospace);font-size:12px;line-height:1.45;white-space:pre-wrap;overflow-wrap:anywhere;user-select:text;tab-size:2}
${JSON_PAPER}[hidden]{display:none}
${TRACE_PAPER}{background:#fff;color:#222;color-scheme:light;padding:10px 14px;border-radius:3px;font-size:13px;line-height:1.4}
${TRACE_PAPER}[hidden]{display:none}
${TRACE_PAPER} .ermine-trace-head{font-weight:600;font-size:14px}
${TRACE_PAPER} .ermine-trace-sub{color:#555}
${TRACE_PAPER} .ermine-trace-failed{color:#b00020}
${TRACE_PAPER} .ermine-trace-bar{display:flex;height:22px;margin:10px 0 4px;border:1px solid #767676;border-radius:2px;overflow:hidden}
${TRACE_PAPER} .ermine-trace-seg{flex:none;min-width:0;box-sizing:border-box;padding:0;overflow:hidden;white-space:nowrap;font-size:11px;line-height:22px;color:#fff;background:#4d5761}
${TRACE_PAPER} .ermine-trace-seg:not(:empty){padding:0 4px}
${TRACE_PAPER} .ermine-trace-seg[data-phase=db]{background:#0b5cad}
${TRACE_PAPER} .ermine-trace-seg[data-tone=b]{background:#646e78}
${TRACE_PAPER} .ermine-trace-seg[data-phase=other]{background:#e4e7ea;color:#222}
${TRACE_PAPER} .ermine-trace-legend{display:flex;flex-wrap:wrap;gap:4px 14px;font-size:12px;margin-bottom:10px}
${TRACE_PAPER} .ermine-trace-swatch{display:inline-block;width:10px;height:10px;margin-right:4px;border:1px solid #767676;vertical-align:-1px;background:#4d5761}
${TRACE_PAPER} .ermine-trace-swatch[data-phase=db]{background:#0b5cad}
${TRACE_PAPER} .ermine-trace-swatch[data-tone=b]{background:#646e78}
${TRACE_PAPER} .ermine-trace-swatch[data-phase=other]{background:#e4e7ea}
${TRACE_PAPER} .ermine-trace-scroll{overflow-x:auto}
${TRACE_PAPER} table.ermine-trace-queries{border-collapse:collapse;width:100%;font-size:12px}
${TRACE_PAPER} .ermine-trace-queries th{text-align:left;font-weight:600;color:#222;border-bottom:1px solid #767676;padding:3px 8px;white-space:nowrap}
${TRACE_PAPER} .ermine-trace-queries td{padding:3px 8px;border-top:1px solid #ddd;vertical-align:top}
${TRACE_PAPER} .ermine-trace-queries .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
${TRACE_PAPER} .ermine-trace-queries tr.ermine-trace-sqlrow td{border-top:none;padding-top:0}
${TRACE_PAPER} .ermine-trace-queries tr.ermine-trace-error td{color:#b00020}
${TRACE_PAPER} .ermine-trace-rel{font-family:var(--vscode-editor-font-family,monospace)}
${TRACE_PAPER} .ermine-trace-track{width:80px;height:8px;margin-top:4px;background:#dde6f0}
${TRACE_PAPER} .ermine-trace-fill{height:8px;background:#0b5cad}
${TRACE_PAPER} summary{cursor:pointer;color:#0b5cad}
${TRACE_PAPER} pre.ermine-trace-sql{background:#f4f5f7;color:#222;margin:4px 0;padding:6px 8px;max-height:320px;overflow:auto;font-family:var(--vscode-editor-font-family,monospace);font-size:12px;white-space:pre-wrap;overflow-wrap:anywhere;user-select:text}
${TRACE_PAPER} button.ermine-trace-copy{font:inherit;font-size:12px;padding:1px 8px;margin-top:4px;cursor:pointer;background:#fff;color:#0b5cad;border:1px solid #0b5cad;border-radius:2px}
${TRACE_PAPER} button.ermine-trace-copy:focus-visible{outline:2px solid #0b5cad;outline-offset:2px}
${TRACE_PAPER} .ermine-trace-note{background:#fff4ce;color:#4a3700;border-left:3px solid #8a6d00;padding:4px 8px;margin:6px 0;font-size:12px}
${TRACE_PAPER} .ermine-trace-empty{color:#555}
${TRACE_PAPER} .ermine-trace-rel{overflow-wrap:anywhere}
@media (max-width:560px){${TRACE_PAPER}{padding:8px 10px}${TRACE_PAPER} .ermine-trace-queries .opt{display:none}${TRACE_PAPER} .ermine-trace-queries th,${TRACE_PAPER} .ermine-trace-queries td{padding:3px 4px}}
html body{background-color:var(--vscode-editor-background)}
${PAPER} .timeseries,${PAPER} .piechart{position:relative!important;width:100%!important;height:${CHART_HEIGHT}px!important}
${PAPER} .highcharts-legend-RightTable .highcharts-legend-item rect{display:none}
${PAPER} .ermine-headline-figures,${PAPER} .ermine-scorecard-cards{display:flex;flex-wrap:wrap;gap:6px 28px;margin:6px 0 10px;padding:0;list-style:none}
${PAPER} .ermine-headline-figure,${PAPER} .ermine-scorecard-card{display:flex;flex-direction:column}
${PAPER} .ermine-headline-figure dt,${PAPER} .ermine-scorecard-label{font-size:11px;color:#555}
${PAPER} .ermine-headline-figure dd,${PAPER} .ermine-scorecard-value{margin:0;font-size:18px;font-weight:600;color:#222}
${PAPER}.ermine-offstage[hidden]{display:block;visibility:hidden;position:absolute;top:0;left:0;right:0;height:0;overflow:hidden;pointer-events:none}
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
  // WP-36 MF-1: the id prefix of the render whose tables the writers still keep
  // callbacks for.  Each render mints under its own prefix (`ermine_p<token>`),
  // so a stale callback cannot find a new table by id; `retire` also drops the
  // stale callbacks, so the writers' list does not grow with every render.
  let drawnPrefix: string | null = null;
  const retire = (prefix: string | null): void => {
    if (prefix === null) return;
    const hw = win.ermine_htmlwriter as { invalidateRegion?: unknown } | undefined;
    if (hw && typeof hw.invalidateRegion === "function") {
      try {
        (hw.invalidateRegion as (uid: string) => void).call(hw, prefix);
      } catch (e) {
        log(`the writers could not drop the replaced render's tables (${prefix}): ${(e as Error)?.message ?? String(e)}`);
      }
    }
  };
  const post = (m: unknown): void => {
    try { api.postMessage(m); } catch { /* nothing to tell: the channel IS the log */ }
  };
  const log = (message: string): void => post({ type: "log", message });
  let saidNoRenderFunction = false;

  /** The legacy page's tail call (HTMLWriter.scala `wrapHeader`): after the
   *  widgets are in the page, `conf.renderFunction(htmlwriter)` draws every
   *  table and chart `run*` queued.  Without it a table stays its skeleton: a
   *  header and one row of "." (F3).  No writers at all: no call and no log
   *  (the writers banner and each legacy widget's error box already say so).
   *  Writers but no draw step: no call, and ONE log per page. */
  const drawLegacy = (): void => {
    if (win.ermine_htmlwriter === undefined) return;
    const conf = win.ermine_htmlwriter_conf;
    const fn = conf?.renderFunction;
    if (typeof fn !== "function") {
      if (!saidNoRenderFunction) { saidNoRenderFunction = true; log(NO_RENDER_FUNCTION); }
      return;
    }
    try {
      fn.call(conf, win.ermine_htmlwriter);
    } catch (e) {
      log(`the legacy writers' renderFunction failed to draw: ${(e as Error)?.message ?? String(e)}`);
    }
  };

  let banner: HTMLElement, bannerText: HTMLElement, restart: HTMLButtonElement;
  let hint: HTMLElement, area: HTMLElement;
  // WP-31: the toggle.  The view is read ONCE from the webview's own state
  // and written back on every click; it never reaches the extension.
  let viewbar: HTMLElement, showDoc: HTMLButtonElement, showJson: HTMLButtonElement, json: HTMLPreElement;
  // S2d: the third view, and the key of what it last drew (so a stale toggle
  // does not rebuild it and collapse an expanded SQL).
  let showTrace: HTMLButtonElement, traceBox: HTMLElement;
  let traceKey: string | null = null;
  let view: PanelView = "document";
  try { view = restoredView(api.getState?.()); } catch { /* no state: the Document view */ }

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
    viewbar = doc.createElement("div");
    viewbar.className = "ermine-viewbar";
    viewbar.setAttribute("role", "toolbar");
    viewbar.setAttribute("aria-label", "Preview view");
    const control = (label: string, which: PanelView): HTMLButtonElement => {
      const b = doc.createElement("button");
      b.type = "button";
      b.textContent = label;
      b.addEventListener("click", () => setView(which));
      return b;
    };
    showDoc = control("Document", "document");
    showJson = control("JSON", "json");
    showTrace = control("Trace", "trace");
    viewbar.append(showDoc, showJson, showTrace);
    area = doc.createElement("div");
    area.className = "ermine-document";
    json = doc.createElement("pre");
    json.className = "ermine-json";
    json.setAttribute("aria-label", "The answer as JSON");
    traceBox = doc.createElement("div");
    traceBox.className = "ermine-trace";
    traceBox.setAttribute("role", "region");
    traceBox.setAttribute("aria-label", "What the render did");
    root.append(banner, hint, viewbar, area, json, traceBox);
  };

  /** WP-31: the viewer's choice.  Stored with the webview's `setState`, merged
   *  into whatever else is stored there; posted to nobody.  It only redraws
   *  what is SHOWN: the document is never re-rendered by a toggle. */
  const setView = (which: PanelView): void => {
    view = which;
    try {
      const old = api.getState?.();
      const base = old !== null && typeof old === "object" ? old as Record<string, unknown> : {};
      api.setState?.({ ...base, view });
    } catch { /* the choice just is not remembered */ }
    draw();
  };

  const draw = (): void => {
    const p = presentation(page.host);
    banner.hidden = p.banner === null;
    banner.setAttribute("data-kind", p.banner?.kind ?? "");
    bannerText.textContent = p.banner?.text ?? "";
    restart.hidden = p.banner?.action !== "restartServer";
    hint.hidden = p.hint === null;
    hint.textContent = p.hint ?? "";
    // WP-31: the toolbar shows whenever there is an answer to look at.  In the
    // JSON view the document is HIDDEN (still rendered, and re-rendered on a
    // new document, so switching back is instant) and the <pre> shows the
    // answer as text -- textContent only, never markup.  The <pre> is not
    // dimmed: it is the answer itself, an error included.
    const answered = page.host.document !== null || page.host.error !== null;
    viewbar.hidden = !answered;
    showDoc.setAttribute("aria-pressed", String(view === "document"));
    showJson.setAttribute("aria-pressed", String(view === "json"));
    showTrace.setAttribute("aria-pressed", String(view === "trace"));
    area.hidden = !p.showDocument || view !== "document";
    // hidden by the JSON or Trace view, not for want of a document: keep it laid out
    area.classList.toggle("ermine-offstage", p.showDocument && view !== "document");
    traceBox.hidden = view !== "trace" || !answered;
    if (view === "trace" && answered) drawTrace();
    area.classList.toggle("ermine-dimmed", p.dimmed);
    json.hidden = view !== "json" || !answered;
    if (view === "json") {
      // Rebuilt on EVERY accepted snapshot while JSON shows (stale, hint and
      // stuck posts included): one stringify plus one string compare.  Intended
      // as cheap enough -- Sales is 8 KB -- and deliberately uncached; a large
      // document pays two full passes per post (WP-31 review N2).  Caching by
      // `page.host.document` / `page.host.error` identity would remove it.
      const text = jsonViewText(page.host);
      // unchanged text is not re-set, so a selection survives a stale toggle
      if (json.textContent !== text) json.textContent = text;
    }
  };

  // ---- S2d trace (panel) ----
  /** Copy: the clipboard when the webview has one, else the SQL is SELECTED
   *  (and the log says why), so Ctrl+C still works.  Never markup. */
  const copySql = (text: string, pre: HTMLElement, button: HTMLButtonElement): void => {
    const select = (why: string): void => {
      try {
        const sel = win.getSelection?.() ?? doc.getSelection?.() ?? null;
        const range = doc.createRange();
        range.selectNodeContents(pre);
        sel?.removeAllRanges();
        sel?.addRange(range);
      } catch { /* nothing more to do: the <pre> is selectable by hand */ }
      button.textContent = "Selected: press Ctrl+C";
      log(`trace: ${why}; the SQL is selected instead`);
    };
    const clip = win.navigator?.clipboard;
    if (clip && typeof clip.writeText === "function") {
      try {
        clip.writeText(text).then(() => { button.textContent = "Copied"; },
          (e: unknown) => select(`the clipboard refused (${(e as Error)?.message ?? String(e)})`));
      } catch (e) { select(`the clipboard refused (${(e as Error)?.message ?? String(e)})`); }
    } else select("this webview has no clipboard");
  };

  const el = <K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string): HTMLElementTagNameMap[K] => {
    const e = doc.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  };

  /** A SQL text in a <pre> (textContent ONLY -- the text is the user's query,
   *  never markup) with its Copy button. */
  const sqlBlock = (sql: string): HTMLElement => {
    const wrap = el("div", "ermine-trace-sqlbox");
    const pre = el("pre", "ermine-trace-sql");
    pre.textContent = sql;
    const copy = el("button", "ermine-trace-copy", "Copy");
    copy.type = "button";
    copy.addEventListener("click", () => copySql(sql, pre, copy));
    wrap.append(copy, pre);
    return wrap;
  };

  const drawTrace = (): void => {
    const payload = page.host.trace?.payload ?? null;
    const failedNoTrace = page.host.error !== null;
    let key: string;
    try { key = `${failedNoTrace}:${JSON.stringify(payload)}`; } catch { key = `${failedNoTrace}:<unserialisable>`; }
    if (key === traceKey) return;
    traceKey = key;
    if (payload === null) {
      traceBox.replaceChildren(el("div", "ermine-trace-empty", failedNoTrace ? NO_TRACE_FAILED : NO_TRACE_OK));
      return;
    }
    const t = readTrace(payload);
    const parts: HTMLElement[] = [el("div", "ermine-trace-head", traceHeadline(t))];
    if (t.failed) {
      parts.push(el("div", "ermine-trace-sub ermine-trace-failed",
        `from the failed render${t.generation === null ? "" : ` (generation ${t.generation})`}` +
        `${t.status === null ? "" : `, status ${t.status}`}`));
    }
    parts.push(el("div", "ermine-trace-sub ermine-trace-conn", traceConnectionText(t)));
    if (t.partial) {
      const r = t.running;
      const note = el("div", "ermine-trace-note ermine-trace-partial",
        "partial: the watchdog answered before the render finished; this is what had run" +
        (r === null ? "." : `, and this query was still running: ${r.relation ?? "?"}` +
          (r.phase === null ? "" : ` in ${r.phase}`) + (r.sinceMs === null ? "" : ` (for ${formatMs(r.sinceMs)})`)));
      parts.push(note);
      if (r !== null && r.sql !== null) parts.push(sqlBlock(r.sql));
    }
    // the phase bar: CSS widths only, no chart library (§3.1)
    const segs = traceSegments(t);
    if (segs.length > 0) {
      const bar = el("div", "ermine-trace-bar");
      bar.setAttribute("role", "img");
      bar.setAttribute("aria-label", "time by phase: " + segs.map((x) => `${x.label} ${formatMs(x.ms)}`).join(", "));
      const legend = el("div", "ermine-trace-legend");
      let grey = 0;
      for (const sg of segs) {
        const tone = sg.key === "db" || sg.key === "other" ? null : (grey++ % 2 === 0 ? "a" : "b");
        const seg = el("div", "ermine-trace-seg", sg.pct >= 12 ? `${sg.label} ${formatMs(sg.ms)}` : "");
        seg.setAttribute("data-phase", sg.key);
        if (tone) seg.setAttribute("data-tone", tone);
        seg.style.width = `${sg.pct}%`;
        seg.title = `${sg.label}: ${formatMs(sg.ms)} (${sg.pct}%)`;
        bar.append(seg);
        const item = el("span", "ermine-trace-key");
        const sw = el("span", "ermine-trace-swatch");
        sw.setAttribute("data-phase", sg.key);
        if (tone) sw.setAttribute("data-tone", tone);
        item.append(sw, doc.createTextNode(`${sg.label} ${formatMs(sg.ms)}`));
        legend.append(item);
      }
      parts.push(bar, legend);
    }
    // the per-query table
    if (t.queries.length > 0) {
      const table = el("table", "ermine-trace-queries");
      const head = el("tr");
      for (const [h, cls] of [["#", "num"], ["relation", ""], ["delivery", "opt"], ["rows", "num"], ["scanned", "num"],
        ["db", "num"], ["total", "num"], ["dialect", "opt"], ["share", "opt"]] as const) {
        const th = el("th", cls || undefined, h);
        th.scope = "col";
        head.append(th);
      }
      table.append(el("thead"));
      table.tHead!.append(head);
      const body = el("tbody");
      const slowest = Math.max(0, ...t.queries.map((q) => q.ms ?? 0));
      t.queries.forEach((q, i) => {
        const tr = el("tr", q.error ? "ermine-trace-query ermine-trace-error" : "ermine-trace-query");
        const cell = (text: string, cls?: string): HTMLTableCellElement => { const td = el("td", cls, text); tr.append(td); return td; };
        cell(String(i + 1), "num");
        cell(q.relation, "ermine-trace-rel");
        cell([q.delivery, q.error ? "(failed)" : null].filter((x) => x !== null).join(" "), "opt");
        cell(q.rows === null ? "" : formatCount(q.rows), "num");
        // "scanned" = rows the DATABASE returned (rowsRead); `rows` = what the report got
        const read = q.rowsRead ?? q.scanned;
        cell(read === null ? "" : formatCount(read), "num");
        cell(q.dbMs === null ? "" : formatMs(q.dbMs), "num");
        cell(q.ms === null ? "" : formatMs(q.ms), "num");
        cell(q.dialect ?? "", "opt");
        const share = cell("", "opt");
        if (slowest > 0 && q.ms !== null) {
          const track = el("div", "ermine-trace-track");
          const fill = el("div", "ermine-trace-fill");
          fill.style.width = `${Math.round(q.ms / slowest * 100)}%`;
          track.append(fill);
          share.append(track);
        }
        body.append(tr);
        // the expandable row: SQL (copyable), setup statements, notes
        const notes: string[] = [];
        if (q.note !== null) notes.push(q.note);
        else if (q.sql === null && q.delivery === "deferred") notes.push("no query ran: the rows are read when the token is fetched, and this panel does not fetch tokens (U6)");
        if (q.overThreshold) notes.push("the scan was abandoned at threshold + 1 rows");
        // server-trace 00:06: usually NOT duplicates -- a groupBy/sumBy Ermine ran in memory
        if (q.rows !== null && q.rowsRead !== null && q.rowsRead > q.rows) notes.push(`the database returned ${formatCount(q.rowsRead)} rows; Ermine reduced them to ${formatCount(q.rows)}`);
        if (q.sql === null && q.setup.length === 0 && notes.length === 0) return;
        const sub = el("tr", "ermine-trace-sqlrow");
        const td = el("td");
        td.colSpan = 9;
        for (const n of notes) td.append(el("div", "ermine-trace-note", n));
        if (q.sql !== null || q.setup.length > 0) {
          const det = el("details");
          const bytes = q.sqlBytes ?? new TextEncoder().encode(q.sql ?? "").length;
          det.append(el("summary", undefined, q.sql !== null
            ? `SQL · ${formatCount(bytes)} bytes${q.sqlTruncated ? " (truncated)" : ""}${q.setup.length ? ` · ${q.setup.length} setup` : ""}`
            : `${q.setup.length} setup statement${q.setup.length === 1 ? "" : "s"}`));
          for (const st of q.setup) {
            det.append(el("div", "ermine-trace-sub",
              `${st.kind}${st.table ? " " + st.table : ""}${st.created === null ? "" : st.created ? " created" : " reused"}` +
              `${st.rows === null ? "" : `, ${formatCount(st.rows)} rows`}${st.ms === null ? "" : `, ${formatMs(st.ms)}`}`));
          }
          if (q.sql !== null) det.append(sqlBlock(q.sql));
          td.append(det);
        }
        sub.append(td);
        body.append(sub);
      });
      table.append(body);
      const scroll = el("div", "ermine-trace-scroll");
      scroll.append(table);
      parts.push(scroll);
    } else {
      parts.push(el("div", "ermine-trace-empty", "no relation was scanned"));
    }
    if (t.truncated !== null) {
      parts.push(el("div", "ermine-trace-note", `${formatCount(t.truncated.queries)} more queries ran and are not listed (the trace keeps the first ${formatCount(t.queries.length)}); the totals count them all`));
    }
    traceBox.replaceChildren(...parts);
  };
  // ---- end S2d trace ----

  const renderDocument = async (): Promise<void> => {
    const mine = ++token;
    renders += 1;
    // A FRESH slot per render, attached now: a slower, older render that
    // finishes later writes into a slot that is no longer in the page.
    const slot = doc.createElement("div");
    area.replaceChildren(slot);
    retire(drawnPrefix);
    drawnPrefix = null;
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
    const prefix = `ermine_p${mine}`;
    drawnPrefix = prefix;
    try {
      const result = await client.render(slot, parsed, client.defaultRegistry(), {
        document: doc,
        fetchData: refuseDeferred,
        // read at RENDER time, never at script-evaluation time (§2(e))
        htmlwriter: win.ermine_htmlwriter,
        idPrefix: prefix,
      });
      // replaced while it rendered: the newer render retired this prefix before
      // this one finished registering, so retire it again (WP-36 MF-1)
      if (mine !== token) { retire(prefix); return; }
      for (const e of result.errors) log(`widget "${e.widget}" at ${e.path}: ${e.message}`);
      // the tree is attached now (the dispatcher appends it last)
      drawLegacy();
    } catch (e) {
      if (mine === token) fail(`the document could not be rendered: ${(e as Error)?.message ?? String(e)}`);
      else retire(prefix);
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
