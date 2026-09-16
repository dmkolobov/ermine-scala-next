// The bridge to the renderers that already exist: the `htmlwriter` global
// (ermine-writers, writers/js/ermine-htmlwriter.js:3571-3596) and the DOM that
// HTMLWriter.scala emits around them.
//
// The adapters here do, on the client, exactly what `tableRegular` (~1034-1060) and
// `drilldownTable` (~1064-1096) do on the server:
//
//   * build the `<div class="tabular_wrapper"><table class="tabular" id="..">`
//     skeleton with a `<thead>` and one placeholder `<tbody>` row;
//   * build `args.relation` -- for a regular table an array of ROWS, each an array
//     of `{formatted, raw, format}` cells (HTMLWriter.rowAction, ~544-550); for a
//     drilldown an array of `{indent, ix, content}` entries (jsTreeEntry);
//   * derive `cols`, `colAlignments`, `colType`, `rowgroupCol`, `sorts`,
//     `paginate`, `scroll`, `isDD` from the props;
//   * call `htmlwriter.runTabular(args)`.
//
// The one thing that moved is WHO formats a cell.  Today `formatted` is computed in
// Scala (htmlEval + Format.basicEval) and shipped; here it is computed from the raw
// cell and the column's CellFormat by src/format.ts, which is why that port has to
// be total.  `raw` is the wire cell unchanged, and `format` is the legacy object
// form -- the tabular sort key reads `entry.format.type === 'markdown'` off it
// (tables.js ~216), so the mapping below is load-bearing, not decoration.
//
// Two places where the legacy object form is genuinely lossy are kept lossy, so
// that the `format` key of a cell is byte-comparable with what the server sends
// today: `round`/`integralRound` drop the colour flag, and `currency` has no
// `places`.  The CellFormat the client formats with keeps both.
//
// `formatted` is NOT byte-comparable with the server's, and is not meant to be:
// a Date or Timestamp cell arrives as its `yyyy-MM-dd`(`THH:mm:ss.SSSZ`) wire
// string rather than through HTMLRunner.tabularDateFmt's `MMM-dd-yyyy`, and
// htmlEval's fallback branch replaces every " " with "&nbsp;" while the port
// (following the JS formatDisplay) does not.  Both are cosmetic.

import type {
  CellCondition, CellFormat, ColumnAlign, ColumnKind, ColumnSort,
  DrilldownTableProps, TableColumn, TableProps, Threshold,
} from "./props";
import type { InlineRelation, WireCell } from "./relation";
import { columnIndex } from "./relation";
import { defaultFormatEnv, formatDisplay, type FormatEnv, type Formatted } from "./format";
import type { Widget, WidgetContext } from "./dispatcher";
import type { RunPiechartArgs, RunStyleboxArgs, RunTimeSeriesArgs } from "./charts";

// --------------------------------------------------------------- the global

/** One cell as `HTMLWriter.rowAction` builds it. */
export interface LegacyCell {
  formatted: Formatted;
  raw: WireCell;
  format: LegacyFormat;
}

/** One drilldown row.  `jsTreeEntry` (PruJS.scala:41-45) emits only
 *  `{indent, content}`; `ix` is minted by tables.js:121-124 itself, and is added
 *  here because it is inert there (each row is re-wrapped as `{ix, row}` anyway)
 *  and it lets the corpus property check that the tree is densely numbered. */
export interface LegacyTreeRow {
  indent: number;
  ix: number;
  content: LegacyCell[];
}

/** The argument object `htmlwriter.runTabular` destructures (tables.js ~1208). */
export interface RunTabularArgs {
  id: string;
  cols: string[];
  rowgroupCol?: number | null;
  colAlignments: ("left" | "right")[];
  colType: ("number" | "date" | "other")[];
  relation: LegacyCell[][] | LegacyTreeRow[];
  legend: string | null;
  /** `[column index, "asc" | "desc"]`, DataTables' aaSorting.  A STRING, not a
   *  boolean: the comparator DataTables calls is named
   *  `oSort[sDataType + "-" + aaSort[k][1]]` (datatables.js:4019), so a boolean
   *  there resolves to `oSort["ermine-htmlwriter-true"]`, which is undefined.
   *  The server sends the same strings -- `Tabular.ordering` is
   *  `IndexedSeq[(Label, SortOrder)]` and PruJS.scala:59 prints a SortOrder as
   *  `x.toString.toLowerCase`. */
  sorts: [number, SortDirection][];
  paginate: boolean;
  scroll: boolean;
  isDD: boolean;
}

/** As much of the `htmlwriter` global as the adapters touch.  Typed from the
 *  Scala emission sites and from the bundle's own uses of it.
 *
 *  Note the calling conventions differ: `runTabular` takes ONE map with the id
 *  inside it, every chart renderer takes `(id, args)`.  `runPiechartDrilldown`
 *  and `runDrilldownBar` are ALIASES (ermine-htmlwriter.js:2632, :2646) of
 *  `runPiechart` and `runTimeSeries`; they are listed separately because that is
 *  how the writer calls them and how a stub records them. */
export interface HtmlWriter {
  runTabular(args: RunTabularArgs): void;
  /** J3e.  `runDrilldownBar` is this same function. */
  runTimeSeries?(id: string, args: RunTimeSeriesArgs): void;
  runDrilldownBar?(id: string, args: RunTimeSeriesArgs): void;
  runPiechart?(id: string, args: RunPiechartArgs): void;
  runPiechartDrilldown?(id: string, args: RunPiechartArgs): void;
  /** J3e.  Applies `formatDisplay` to `args.aFormat` ITSELF
   *  (ermine-htmlwriter.js:3583), so it must be handed the TUPLE. */
  runStylebox?(id: string, args: RunStyleboxArgs): void;
  getScrollbarDimensions?(): { sbw: number; sbh: number };
  showFullPrimaryColumn?(): boolean;
  tableScrollable?(): boolean;
}

// ------------------------------------------------------- the legacy formats

/** What `deriveIndexedSort` serialises a `SortOrder` to (PruJS.scala:59). */
export type SortDirection = "asc" | "desc";

export type LegacyFormat = { type: string } & Record<string, unknown>;

function legacyThreshold(t: Threshold): string | number | boolean {
  return t.args[0];
}

/** HTMLWriter.jsCondition (~260-267). */
export function legacyCondition(c: CellCondition): Record<string, unknown> {
  switch (c.tag) {
    case "Gt": return { gt: legacyThreshold(c.gt) };
    case "Lt": return { lt: legacyThreshold(c.lt) };
    case "Eq": return { eq: legacyThreshold(c.eq) };
    case "Gte": return { gte: legacyThreshold(c.gte) };
    case "Lte": return { lte: legacyThreshold(c.lte) };
    case "And": return { and: [legacyCondition(c.and[0]), legacyCondition(c.and[1])] };
  }
}

/** HTMLWriter.jsFormat (~269-347): the object form the cell carries. */
export function legacyFormat(f: CellFormat): LegacyFormat {
  switch (f.tag) {
    case "Default": return { type: "default" };
    case "Verbatim": return { type: "verbatim" };
    case "Markdown": return { type: "markdown", base: legacyFormat(f.base) };
    case "Constant": return { type: "constant", value: f.value };
    case "Percentage":
      return { type: "percentage", color: f.color, negParens: f.negParens, places: f.places, pad: f.pad };
    // the legacy object carries no `places` for a currency (the server reads it
    // from CurrencyObj.settings); it is added here because the client formats
    case "Currency":
      return { type: "currency", color: f.color, negParens: f.negParens, symbol: f.symbol, places: f.places };
    case "Pr1": return { type: "pr1", base: legacyFormat(f.base) };
    case "Pr2": return { type: "pr2", base: legacyFormat(f.base) };
    case "DateRange": return { type: "dateRange" };
    // the legacy object drops `color` on round/integralRound; kept dropped
    case "Round": return { type: "round", negParens: f.negParens, places: f.places };
    case "IntegralRound": return { type: "integralRound", negParens: f.negParens, places: f.places };
    case "Truncate": return { type: "truncate", places: f.places };
    case "Conditional":
      return {
        type: "conditional",
        condition: legacyCondition(f.condition),
        then: legacyFormat(f.whenTrue),
        else: legacyFormat(f.whenFalse),
      };
    case "Color":
      return {
        type: "color",
        bg: [f.bg.red, f.bg.green, f.bg.blue],
        fg: [f.fg.red, f.fg.green, f.fg.blue],
        base: legacyFormat(f.base),
      };
    case "Alias": {
      // Object.create(null): a key of `__proto__` would otherwise invoke the
      // prototype setter and be silently dropped
      const aliases = Object.create(null) as Record<string, string>;
      for (const [k, v] of f.aliases) aliases[k] = v;
      return { type: "alias", aliases };
    }
  }
}

/** `[style name, argument]` -- HTMLWriter.jsLayoutFormat's pair. */
export type LegacyFormatTuple = [string, unknown];

/** HTMLWriter.jsLayoutFormat (~208-227): the TUPLE form the chart path and the
 *  legacy `formatDisplay` take.  Lossy by construction -- five of the fifteen
 *  cases become a style name `formatDisplay`'s styleMap does not have, and fall
 *  back to Default there.  `charts.ts::TUPLE_LOSS` documents the loss case by
 *  case and `test/charts.test.ts` drives the real legacy function through it. */
export function legacyFormatTuple(f: CellFormat): LegacyFormatTuple {
  switch (f.tag) {
    case "Default": return ["Default", null];
    case "Markdown": return ["MarkdownFmt", null];
    case "Constant": return ["Constant", f.value];
    case "Percentage": return ["Percentage", [f.places, f.pad]];
    case "Currency": return ["Currency", [f.symbol, f.places]];
    case "DateRange": return ["DateRange", null];
    case "Round": return ["Round", f.places];
    case "IntegralRound": return ["IntegralRound", f.places];
    case "Truncate": return ["Truncate", f.places];
    case "Pr1": return ["Pr1", legacyFormatTuple(f.base)];
    case "Pr2": return ["Pr2", legacyFormatTuple(f.base)];
    case "Conditional": return ["Conditional", null];
    case "Color": return ["ColorFormat", null];
    case "Verbatim": return ["Verbatim", null];
    case "Alias": {
      const aliases = Object.create(null) as Record<string, string>;
      for (const [k, v] of f.aliases) aliases[k] = v;
      return ["Alias", aliases];
    }
  }
}

/** The style names `formatDisplay`'s styleMap actually has; every other tuple
 *  falls back to Default there. */
export const LEGACY_STYLE_NAMES = [
  "Default", "Percentage", "Currency", "DateRange", "Round", "IntegralRound",
  "Truncate", "Pr1", "Alias", "Constant",
] as const;

// ------------------------------------------------------------- the cells

/** `HTMLWriter.jsPrimExprTabular`'s null: a NullExpr prints as "-". */
export const NULL_DISPLAY = "-";

/** What one table cell displays: the port's answer, with the legacy null. */
export function displayValue(v: Formatted): Formatted {
  return v === null || v === undefined ? NULL_DISPLAY : v;
}

/** One `{formatted, raw, format}` cell.  `raw` is the wire cell unchanged; the
 *  legacy `rawEval` only differs from that for Pr1/Pr2, which pair two source
 *  values -- a column here reads exactly one.
 *
 *  The one adapter rule on top of the port: a NULL cell displays as the legacy
 *  null placeholder.  Server-side a format is applied to a PrimExpr and a
 *  NullExpr comes out a NullExpr, which `HTMLWriter.jsPrimExprTabular` prints as
 *  "-"; the JS `formatDisplay` has no null case at all, so `Round` on a null
 *  would otherwise read "0.0".  `Constant` is the exception -- it ignores its
 *  input, so it still answers its constant. */
export function tabularCell(fmt: CellFormat, raw: WireCell, env: FormatEnv): LegacyCell {
  const formatted = raw === null && fmt.tag !== "Constant"
    ? NULL_DISPLAY
    : displayValue(formatDisplay(fmt, env)([raw]));
  return { formatted, raw, format: legacyFormat(fmt) };
}

export function alignmentOf(a: ColumnAlign): "left" | "right" {
  return a === "AlignRight" ? "right" : "left";
}

export function columnTypeOf(k: ColumnKind): "number" | "date" | "other" {
  switch (k) {
    case "NumberColumn": return "number";
    case "DateColumn": return "date";
    case "OtherColumn": return "other";
  }
}

function sortPairs(sorts: ColumnSort[]): [number, SortDirection][] {
  return sorts.map((s) => [s.sortColumn, s.descending ? "desc" : "asc"]);
}

/** The rows of `args.relation` for a regular table: one array of cells per
 *  relation row, in `columns` order.  A column naming no relation column gets a
 *  null cell, which displays as the legacy "-" rather than throwing. */
export function tabularRelation(
  columns: TableColumn[],
  rel: InlineRelation,
  env: FormatEnv,
): LegacyCell[][] {
  const ix = columns.map((c) => columnIndex(rel, c.column));
  return rel.rows.map((row) =>
    columns.map((c, i) => {
      const at = ix[i] as number;
      const raw = at < 0 ? null : ((row[at] ?? null) as WireCell);
      return tabularCell(c.cellFormat, raw, env);
    }),
  );
}

// ------------------------------------------------------------- the skeleton

/** The DOM `tableRegular`/`drilldownTable` emit server-side today.  `<thead>` is a
 *  single row of `<th>`s carrying the sticky span tables.js would otherwise build
 *  in `updateStickyHeaderPositions`; column GROUPINGS (the Legend's nested header
 *  rows) are not reproduced -- the JSON path has no Legend, see README. */
export function tableSkeleton(
  doc: Document,
  id: string,
  headers: string[],
  isDD: boolean,
): HTMLElement {
  const wrapper = doc.createElement("div");
  wrapper.className = "tabular_wrapper";
  const table = doc.createElement("table");
  table.className = "tabular";
  table.id = id;
  const thead = doc.createElement("thead");
  const headRow = doc.createElement("tr");
  if (isDD) {
    const th = doc.createElement("th");
    th.textContent = "+";
    headRow.appendChild(th);
  }
  for (const h of headers) {
    const th = doc.createElement("th");
    const sticky = doc.createElement("span");
    sticky.className = "sticky has-tooltip tooltip-on-truncate";
    sticky.textContent = h.replace(/ /g, " ");
    const indicator = doc.createElement("span");
    indicator.className = "sort-indicator";
    sticky.appendChild(indicator);
    th.appendChild(sticky);
    headRow.appendChild(th);
  }
  thead.appendChild(headRow);
  const tbody = doc.createElement("tbody");
  const placeholder = doc.createElement("tr");
  const cellCount = headers.length + (isDD ? 1 : 0);
  for (let i = 0; i < cellCount; i++) {
    const td = doc.createElement("td");
    td.textContent = ".";
    placeholder.appendChild(td);
  }
  tbody.appendChild(placeholder);
  table.appendChild(thead);
  table.appendChild(tbody);
  wrapper.appendChild(table);
  return wrapper;
}

function requireHtmlWriter(ctx: WidgetContext): HtmlWriter {
  const hw = ctx.env.htmlwriter as HtmlWriter | undefined;
  if (!hw || typeof hw.runTabular !== "function") {
    throw new Error("env.htmlwriter with a runTabular function is required by this widget");
  }
  return hw;
}

// -------------------------------------------------------------- the widgets

/** Registry entry for "table". */
export function tableWidget(env?: FormatEnv): Widget<TableProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: TableProps<InlineRelation>): void {
      const hw = requireHtmlWriter(ctx);
      const fenv = env ?? defaultFormatEnv(ctx.document);
      const id = `${ctx.uid()}_tabular`;
      const headers = props.columns.map((c) => c.header);
      ctx.target.appendChild(tableSkeleton(ctx.document, id, headers, false));
      hw.runTabular({
        id,
        cols: headers,
        rowgroupCol: props.rowGroup ?? null,
        colAlignments: props.columns.map((c) => alignmentOf(c.align)),
        colType: props.columns.map((c) => columnTypeOf(c.kind)),
        relation: tabularRelation(props.columns, props.rows, fenv),
        legend: null,
        sorts: sortPairs(props.sorts),
        paginate: props.paginate,
        scroll: props.scroll,
        isDD: false,
      });
    },
  };
}

/** The drilldown tree the legacy TreeTabular builds server-side: rows ordered
 *  depth-first from the roots, each carrying its depth.  A root is a row whose
 *  `parentColumn` value matches no other row's `childColumn`; a cycle or a missing
 *  parent leaves its rows at the end, at depth 0, rather than looping. */
export function drilldownRows(
  props: DrilldownTableProps<InlineRelation>,
  env: FormatEnv,
): LegacyTreeRow[] {
  const rel = props.ddRows;
  const parentAt = columnIndex(rel, props.parentColumn);
  const childAt = columnIndex(rel, props.childColumn);
  const key = (row: WireCell[], at: number): string =>
    at < 0 ? "" : JSON.stringify(row[at] ?? null);

  const childrenOf = new Map<string, number[]>();
  const roots: number[] = [];
  const ownKeys = new Set(rel.rows.map((r) => key(r, childAt)));
  rel.rows.forEach((row, i) => {
    const p = key(row, parentAt);
    if (parentAt < 0 || !ownKeys.has(p) || p === key(row, childAt)) {
      roots.push(i);
      return;
    }
    const bucket = childrenOf.get(p);
    if (bucket) bucket.push(i);
    else childrenOf.set(p, [i]);
  });

  const out: LegacyTreeRow[] = [];
  const seen = new Set<number>();
  const cells = tabularRelation(props.ddColumns, rel, env);
  const visit = (i: number, depth: number): void => {
    if (seen.has(i)) return;
    seen.add(i);
    out.push({ indent: depth, ix: out.length, content: cells[i] as LegacyCell[] });
    for (const c of childrenOf.get(key(rel.rows[i] as WireCell[], childAt)) ?? []) {
      visit(c, depth + 1);
    }
  };
  for (const r of roots) visit(r, 0);
  rel.rows.forEach((_r, i) => visit(i, 0)); // anything a cycle stranded
  return out;
}

/** Registry entry for "drilldownTable". */
export function drilldownTableWidget(env?: FormatEnv): Widget<DrilldownTableProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: DrilldownTableProps<InlineRelation>): void {
      const hw = requireHtmlWriter(ctx);
      const fenv = env ?? defaultFormatEnv(ctx.document);
      const id = `${ctx.uid()}_tabular`;
      const headers = props.ddColumns.map((c) => c.header);
      ctx.target.appendChild(tableSkeleton(ctx.document, id, headers, true));
      hw.runTabular({
        id,
        cols: headers,
        colAlignments: props.ddColumns.map((c) => alignmentOf(c.align)),
        colType: props.ddColumns.map((c) => columnTypeOf(c.kind)),
        relation: drilldownRows(props, fenv),
        legend: null,
        sorts: sortPairs(props.ddSorts),
        paginate: props.ddPaginate,
        scroll: props.ddScroll,
        isDD: true,
      });
    },
  };
}
