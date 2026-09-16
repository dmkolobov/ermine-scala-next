// The adapters onto the legacy CHART renderers: `htmlwriter.runTimeSeries`
// (ermine-htmlwriter.js:1716), `runPiechart` / `runPiechartDrilldown` (:2370,
// :2632), `runDrilldownBar` (:2646, an alias of runTimeSeries) and `runStylebox`
// (:3582 -> js/ermine/stylebox.js).  Stage J3e.
//
// These do on the client what HTMLWriter.axisChart (~1099-1121), genPieChart
// (~1146-1186), styleBox (~1188-1271) and drilldownBarChartPC (~1279-1313) do on
// the server -- with one difference that is the whole point of the stage: every
// one of those emission sites can put an f0 HANDLE where the data should be and
// let the browser POST for it (design note section 4.5).  Here the rows travel
// with the document, so each adapter builds the LOCAL shape the renderers already
// accept and no callback is made.  Where the legacy has no local branch at all,
// the gap is named below and in tracker/json-stage3/report-J3e.md.
//
// ## The callback paths, one by one
//
// | legacy POST | when | what this does |
// |---|---|---|
// | `relation` (series rows) | `withTimeSeriesData` :221, taken unless `series[i].data` is an ARRAY (:223) | always sends an array, so the branch is never taken.  `selSeries`/`selCategory`/`selValue`/`selExtra`/`colors` exist only to build that payload and are not emitted. |
// | `pieChartData` | `withPiechartData` :261, unless `args.relation` is an ARRAY (:262) | always sends an array.  A drilldown pie filters `rec[4] === parentId` IN THE BROWSER (:268), so drilling needs no round trip either. |
// | `styleBoxData` | `withStyleBoxData` :297 -- **no local branch** | UNAVOIDABLE.  The 3x3 grid is built entirely from `cellCounts`, which this adapter computes, so the widget RENDERS with no request; but clicking a cell opens a popup whose rows only that POST can supply.  `relation` and `legend` are sent as `null`, the POST fails, and stylebox.js logs through its own `callbackError`.  No exception reaches the page. |
// | `tableData` | unreachable from writer-generated pages (tables are inline) | n/a |
// | `treeMapData` | `runTreeMap` is undefined in the bundle | `treeMap` is deliberately not registered; the dispatcher's error box is the answer. |
//
// ## Formats
//
// Chart axes, series and the style box read the LOSSY TUPLE form
// (HTMLWriter.jsLayoutFormat), not the object form a table cell carries, so every
// format here goes through `legacyFormatTuple`.  `TUPLE_LOSS` below says, case by
// case, what that drops.  `runStylebox` applies `formatDisplay` to `args.aFormat`
// ITSELF (:3583), so it is handed the tuple, never a formatted value.
//
// ## Dates
//
// A Date or Timestamp cell arrives as an ISO string and the chart path wants the
// legacy `[y, m, d]` triple (`hwDate`, utils.js:267-270; `nelpeHwDates` turns any
// 3-element all-number array back into a Date).  `axisValue` does that conversion,
// keyed on the relation column's declared type -- never on the shape of the cell.

import type {
  AxisChartProps, CellFormat, ChartAxis, ChartMeta, ChartSeries, ChartVariant,
  DrilldownBarProps, LegendLocation, PieChartProps, ScalarType, StyleBoxProps,
} from "./props";
import type { InlineRelation, WireCell, WireColumn } from "./relation";
import { columnIndex } from "./relation";
import { defaultFormatEnv, formatDisplay, type FormatEnv } from "./format";
import { LEGACY_STYLE_NAMES, legacyFormatTuple, type LegacyFormatTuple } from "./legacy";
import type { Widget, WidgetContext } from "./dispatcher";

// ------------------------------------------------------ the tuple's lossiness

export interface TupleLoss {
  /** Does `formatDisplay`'s styleMap (utils.js:293-333) have this name at all?
   *  A name it does not have silently falls back to `Default` there. */
  implemented: boolean;
  /** What the tuple cannot carry, in words.  Empty = nothing is lost. */
  drops: string[];
}

/**
 * What `legacyFormatTuple` loses, per `CellFormat` constructor.  This is the
 * documentation the brief asks for AND the table `test/charts.test.ts` drives the
 * real legacy `formatDisplay` against: for a tag with `implemented: false` the
 * legacy must answer exactly what `Default` answers, and for a tag with
 * `drops: []` it must agree with `src/format.ts` on every value.
 *
 * Read `jsLayoutFormat` (HTMLWriter.scala ~208-227) beside it.
 */
export const TUPLE_LOSS: Record<CellFormat["tag"], TupleLoss> = {
  // ["Default", null] -- nothing to carry
  Default: { implemented: true, drops: [] },
  // ["Percentage", [places, pad]] -- the two colour/parenthesis flags are gone,
  // so a red negative percentage draws black and -0.17 reads "-17%", not "(17%)"
  Percentage: { implemented: true, drops: ["color", "negParens"] },
  // ["Currency", [symbol, places]] -- same two flags
  Currency: { implemented: true, drops: ["color", "negParens"] },
  // ["Round", places] -- same two flags, and the tuple is a BARE number, not a pair
  Round: { implemented: true, drops: ["color", "negParens"] },
  IntegralRound: { implemented: true, drops: ["color", "negParens"] },
  // ["Truncate", places] / ["Constant", value] / ["DateRange", null] -- total
  Truncate: { implemented: true, drops: [] },
  Constant: { implemented: true, drops: [] },
  DateRange: { implemented: true, drops: [] },
  // ["Alias", {from: to}] -- the pair LIST becomes an object, so the ORDER is
  // gone and a repeated key keeps the last pair.  The RENDERING is unaffected:
  // src/format.ts also keeps the last match, and the map is built with
  // Object.create(null), so a key of "constructor"/"__proto__" does not read
  // Object.prototype's member on either side
  Alias: { implemented: true, drops: ["the pair LIST becomes an object: order is gone and a repeated key keeps the LAST pair"] },
  // ["Pr1", <inner tuple>] -- the only recursive case the tuple keeps, and the
  // inner tuple loses whatever its own row says
  Pr1: { implemented: true, drops: ["whatever the inner format's tuple drops"] },
  // ---- the five the styleMap has no entry for: formatDisplay falls back to
  // styleMap.Default, so the format is lost ENTIRELY, not partly
  Pr2: { implemented: false, drops: ["the whole format: styleMap has no Pr2"] },
  Markdown: { implemented: false, drops: ["the whole format: the tag is spelled MarkdownFmt and styleMap has no entry"] },
  Conditional: { implemented: false, drops: ["the whole format: the condition and both branches become ['Conditional', null]"] },
  Color: { implemented: false, drops: ["the whole format: bg/fg/base become ['ColorFormat', null]"] },
  Verbatim: { implemented: false, drops: ["the whole format: ['Verbatim', null] falls back to Default, which ESCAPES -- the opposite of Verbatim"] },
};

/** Every style NAME `legacyFormatTuple` can put at the head of a tuple: the ten
 *  `LEGACY_STYLE_NAMES` the legacy styleMap implements, plus the five renames it
 *  does not.  Anything else reaching a chart as a format is an adapter bug, which
 *  is what `test/corpus.test.ts::assertTuple` checks. */
export const TUPLE_STYLE_NAMES: readonly string[] = [
  ...LEGACY_STYLE_NAMES, "MarkdownFmt", "ColorFormat", "Conditional", "Verbatim", "Pr2",
];

/**
 * True when this PARTICULAR format renders the same through the tuple as it does
 * through `src/format.ts`.
 *
 * `TUPLE_LOSS[tag].drops` says what the ENCODING cannot carry; this says whether
 * that matters for the value at hand.  `Percentage`'s tuple has no room for
 * `color`/`negParens`, but a Percentage with both flags FALSE loses nothing, so
 * the agreement property can still hold it against the real legacy function --
 * which is the point.  `Alias` drops the pair list's order, and the rendering is
 * nevertheless identical, because `src/format.ts` takes the last match too.
 */
export function tupleIsLossless(f: CellFormat): boolean {
  switch (f.tag) {
    case "Default": case "Truncate": case "Constant": case "DateRange": case "Alias":
      return true;
    case "Percentage": case "Currency": case "Round": case "IntegralRound":
      return !f.color && !f.negParens;
    case "Pr1":
      return tupleIsLossless(f.base);
    case "Pr2": case "Markdown": case "Conditional": case "Color": case "Verbatim":
      return false;
  }
}

// ------------------------------------------------------------ axis values

/** The column types `PrimT.isNumeric` answers true for.  A NULL in one of these
 *  goes out as `null`; a null anywhere else goes out as `""`, which is what
 *  `RelationRunner.jsonPrepAxis` does (`extractNullableString ""`).
 *
 *  Two deliberate divergences from `jsonPrepAxis`, both cosmetic:
 *  a `Bool` cell stays a JS boolean here, where the legacy's fall-through would
 *  send the string `"true"`/`"false"`; and a `Timestamp` column is treated as a
 *  date (below), where the legacy matches only `DateExpr` and sends a
 *  `TimestampExpr` as its string.  Nothing in the bundle compares either against
 *  a literal, and a timestamp axis behaving like a date axis is the useful
 *  reading of `hwAxisDateP`. */
const NUMERIC_TYPES = new Set(["Byte", "Double", "Int", "Long", "Short"]);
const DATE_TYPES = new Set(["Date", "Timestamp"]);

/** The legacy YMD triple of an ISO `yyyy-MM-dd[THH:mm:ss.SSSZ]` cell. */
export function ymd(iso: string): [number, number, number] | null {
  const m = /^(-?\d{4,})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}

/** One cell as the chart path wants it: a Date/Timestamp column becomes the
 *  `[y, m, d]` triple `hwDate` reads, a numeric column stays a number, a null
 *  follows `jsonPrepAxis`. */
export function axisValue(col: WireColumn | undefined, cell: WireCell): unknown {
  if (cell === null || cell === undefined) {
    return col && NUMERIC_TYPES.has(col.type) ? null : "";
  }
  if (col && DATE_TYPES.has(col.type) && typeof cell === "string") {
    return ymd(cell) ?? cell;
  }
  if (col && col.type === "Long" && typeof cell === "string") {
    // a Long travels as a decimal string so JSON does not lose precision; the
    // chart wants a number, and the legacy sends one (PrimNumAsJson)
    const n = Number(cell);
    return Number.isFinite(n) ? n : cell;
  }
  return cell;
}

/** A reader for one named column of a relation: `-1` (absent) reads as a null
 *  cell, which `axisValue` turns into "" or null by the column's type. */
function reader(rel: InlineRelation, name: string): (row: WireCell[]) => unknown {
  const at = columnIndex(rel, name);
  const col = at < 0 ? undefined : rel.columns[at];
  return (row: WireCell[]): unknown => axisValue(col, at < 0 ? null : ((row[at] ?? null) as WireCell));
}

/** `#rrggbb` or null.  The legacy's `cssColor` prints lower-case hex
 *  (HTMLWriter.getColorHexcode, `f"#$r%02x$g%02x$b%02x"`), and `getColorIndex`
 *  looks the string up in a map, so anything else is better sent as null than as
 *  a colour the renderer will not find. */
export function cssColor(cell: unknown): string | null {
  if (typeof cell !== "string") return null;
  return /^#[0-9a-fA-F]{6}$/.test(cell) ? cell.toLowerCase() : null;
}

// --------------------------------------------------------- the legacy objects

export type LegacyTuple = LegacyFormatTuple;

export interface LegacyScalarType {
  name: string;
  isNumeric: boolean;
  types?: LegacyScalarType[];
}

export interface LegacyAxis {
  type: "Axis";
  label: string;
  tooltipLabel: string;
  format: LegacyTuple;
  scalarType: LegacyScalarType;
  showTicks: boolean;
  constraints: Record<string, unknown>;
}

export interface LegacyMeta {
  type: "AxisChartData";
  domain: LegacyAxis;
  range: LegacyAxis;
  title: string;
  orientation: "vertical" | "horizontal";
  legendOptions: { type: "ChartLegendOptions"; location: string };
  renderHints: { type: "ChartRenderHints"; enableDataLabels: boolean };
  /** An f0 colour handle server-side; only ever forwarded in the POST payload,
   *  and this path never posts. */
  colors: null;
}

/** One series row: `[[value..], [category..], [series..], color, ...extra]`
 *  (RelationRunner.runRelation ~70-80). */
export type LegacySeriesRow = unknown[];

export interface LegacySeries {
  type: "ChartSeries";
  fmtSeries: LegacyTuple;
  fmtExtra: LegacyTuple[];
  selCategoryCols: [string, boolean][];
  data: LegacySeriesRow[];
  variant: string;
  zlabel?: string;
}

export interface RunTimeSeriesArgs {
  type: "AxisChart";
  series: LegacySeries[];
  meta: LegacyMeta;
  parentCol?: string | null;
  childCol?: string | null;
}

/** One pie row: `[label, |value|, cssColor|null, child?, parent?]`. */
export type LegacyPieRow = unknown[];

export interface RunPiechartArgs {
  title: string;
  seriesName: string;
  legendOptions: { type: "ChartLegendOptions"; location: string };
  renderHints: { type: "ChartRenderHints"; enableDataLabels: boolean };
  dataFmt: LegacyTuple;
  labelFmt: LegacyTuple;
  parentCol: string | null;
  childCol: string | null;
  relation: LegacyPieRow[];
}

export interface RunStyleboxArgs {
  xTitle: string;
  yTitle: string;
  aField: string;
  aTitle: string;
  /** A TUPLE: runStylebox does `args.aFormat = formatDisplay(args.aFormat)`. */
  aFormat: LegacyTuple;
  legend: null;
  xPositionField: string;
  yPositionField: string;
  rowLabels: string[];
  columnLabels: string[];
  showNumber: "showNumber" | "hiddenNumber";
  xBins: [number, number][];
  yBins: [number, number][];
  /** JSON INSIDE a JSON string: stylebox.js:87 runs `$.parseJSON` on it. */
  cellCounts: string;
  relation: null;
}

/** One entry of the parsed `cellCounts`.  `xPosition`/`yPosition` are the LITERAL
 *  key names stylebox.js reads (:91-96), whatever the relation's columns are
 *  called, and `[aField]` holds the aggregate. */
export interface StyleBoxCell {
  xPosition: number;
  yPosition: number;
  styleBoxAggFormatted: string;
  [column: string]: unknown;
}

// ----------------------------------------------------------- meta and series

/** `ChartLegendLocation` as the JS compares it: the Ermine constructor with its
 *  `Legend` prefix removed (`LegendRightTable` -> `RightTable`). */
export function legendLocationOf(l: LegendLocation): string {
  return l.replace(/^Legend/, "");
}

export function legacyScalarType(t: ScalarType): LegacyScalarType {
  if (t.tag === "Scalar") return { name: t.typeName, isNumeric: t.typeNumeric };
  return { name: "compound", isNumeric: false, types: t.componentTypes.map(legacyScalarType) };
}

export function legacyAxis(a: ChartAxis): LegacyAxis {
  const c = a.constraints;
  const constraints: Record<string, unknown> =
    c.tag === "Scaled"
      ? {
          scaled: true,
          lowerBound: c.lowerBound ?? null,
          upperBound: c.upperBound ?? null,
          displayScale: c.displayScale,
        }
      : {
          scaled: false,
          // `sortByCategory` only ever uses this array's LENGTH -- it compares
          // the category components pairwise (categoryOrdering, :1589-1601) --
          // so the direction travels for the server's benefit
          sort: c.sortOrders,
          tickOverrides: c.tickOverrides,
        };
  return {
    type: "Axis",
    label: a.axisLabel,
    tooltipLabel: a.tooltipLabel,
    format: legacyFormatTuple(a.axisFormat),
    scalarType: legacyScalarType(a.scalarType),
    showTicks: a.showTicks,
    constraints,
  };
}

export function legacyMeta(m: ChartMeta): LegacyMeta {
  return {
    type: "AxisChartData",
    domain: legacyAxis(m.domainAxis),
    range: legacyAxis(m.rangeAxis),
    title: m.chartTitle,
    orientation: m.orientation === "Horizontal" ? "horizontal" : "vertical",
    legendOptions: { type: "ChartLegendOptions", location: legendLocationOf(m.legendOptions.legendLocation) },
    renderHints: { type: "ChartRenderHints", enableDataLabels: m.renderHints.enableDataLabels },
    colors: null,
  };
}

function variantName(v: ChartVariant): string {
  return v.tag;
}

/**
 * The rows of one series' `data`.
 *
 * `extraShape` follows `RelationRunner.runRelation`'s own split: the axis chart
 * passes its extras as `extraOps`, whose positions are LISTS, while the drilldown
 * bar passes the child and parent columns as `extraCols`, whose positions are
 * SCALARS (RelationRunner.scala ~76-79).  Both are reproduced as written.
 */
export function seriesRows(
  s: ChartSeries,
  rel: InlineRelation,
  opts: { scalarExtras?: string[]; listExtras?: string[] } = {},
): LegacySeriesRow[] {
  const values = reader(rel, s.valueColumn);
  const cats = s.categoryColumns.map((c) => reader(rel, c));
  // a series with no series column is one series; the legacy always has a
  // Presentation here, and the idiom is a `Constant` seriesFormat that renames
  // whatever arrives, so an empty name is the honest input to it
  const sers = s.seriesColumns.length
    ? s.seriesColumns.map((c) => reader(rel, c))
    : [(): unknown => ""];
  const colorAt = s.colorColumn === undefined ? -1 : columnIndex(rel, s.colorColumn);
  const scalarExtras = (opts.scalarExtras ?? []).map((c) => reader(rel, c));
  const listExtras = (opts.listExtras ?? []).map((c) => reader(rel, c));

  return rel.rows.map((row) => {
    const out: unknown[] = [
      [values(row)],
      cats.map((f) => f(row)),
      sers.map((f) => f(row)),
      colorAt < 0 ? null : cssColor(row[colorAt]),
    ];
    for (const f of scalarExtras) out.push(f(row));
    for (const f of listExtras) out.push([f(row)]);
    return out;
  });
}

/** `selCategoryCols`: each category column paired with the domain's sort
 *  direction.  The SPELLING is not the server's -- `chartSeriesToMap`
 *  (HTMLWriter.scala:756-760) pairs it with the `SortOrder` VALUE, because the
 *  lambda's own `order` parameter shadows the `val order = domOrder map {Asc =>
 *  false; Desc => true}` at :737 and leaves that val dead.  A boolean is the
 *  shape that `val` intended; the key is POST-only, and this path never posts,
 *  so nothing reads either. */
function categoryCols(s: ChartSeries, meta: ChartMeta): [string, boolean][] {
  const c = meta.domainAxis.constraints;
  const orders = c.tag === "Unscaled" ? c.sortOrders : [];
  return s.categoryColumns.map((col, i) => [col, orders[i] === "Desc"]);
}

export function legacySeries(
  s: ChartSeries,
  meta: ChartMeta,
  rel: InlineRelation,
  opts: { scalarExtras?: string[]; listExtras?: string[] } = {},
): LegacySeries {
  const out: LegacySeries = {
    type: "ChartSeries",
    fmtSeries: legacyFormatTuple(s.seriesFormat),
    fmtExtra: s.extraFormats.map(legacyFormatTuple),
    selCategoryCols: categoryCols(s, meta),
    data: seriesRows(s, rel, opts),
    variant: variantName(s.variant),
  };
  // `structure` is deliberately absent: SeriesStructure.Complex's `trees` is an
  // f0 blob with no JSON equivalent, and without it `isSeriesLevelDD` is false,
  // which is the Simple behaviour.
  if (s.variant.tag === "Bubble") out.zlabel = s.variant.zLabel;
  return out;
}

// ------------------------------------------------------------- the skeletons

/** The DOM `xyChart`/`genPieChart`/`styleBox`/`drilldownBarChartPC` emit around
 *  the renderer's div: `<div class="<css>_wrapper sizeme"><div class="<css>"
 *  id="<id>">`.  The renderers address that inner div by id. */
export function chartSkeleton(doc: Document, id: string, css: string): HTMLElement {
  const wrapper = doc.createElement("div");
  wrapper.className = `${css}_wrapper sizeme`;
  const inner = doc.createElement("div");
  inner.className = css;
  inner.id = id;
  wrapper.appendChild(inner);
  return wrapper;
}

interface ChartWriter {
  runTimeSeries?(id: string, args: RunTimeSeriesArgs): void;
  runPiechart?(id: string, args: RunPiechartArgs): void;
  runPiechartDrilldown?(id: string, args: RunPiechartArgs): void;
  runDrilldownBar?(id: string, args: RunTimeSeriesArgs): void;
  runStylebox?(id: string, args: RunStyleboxArgs): void;
}

function requireFn<K extends keyof ChartWriter>(ctx: WidgetContext, name: K): NonNullable<ChartWriter[K]> {
  const hw = ctx.env.htmlwriter as ChartWriter | undefined;
  const fn = hw ? hw[name] : undefined;
  if (typeof fn !== "function") {
    throw new Error(`env.htmlwriter with a ${String(name)} function is required by this widget`);
  }
  return fn.bind(hw) as NonNullable<ChartWriter[K]>;
}

// ---------------------------------------------------------------- axisChart

/** Registry entry for "axisChart". */
export function axisChartWidget(): Widget<AxisChartProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: AxisChartProps<InlineRelation>): void {
      const run = requireFn(ctx, "runTimeSeries");
      const id = ctx.uid();
      ctx.target.appendChild(chartSkeleton(ctx.document, id, "timeseries"));
      run(id, {
        type: "AxisChart",
        meta: legacyMeta(props.chartMeta),
        series: props.chartSeries.map((s) =>
          legacySeries(s, props.chartMeta, props.chartRows, { listExtras: s.extraColumns })),
        parentCol: null,
        childCol: null,
      });
    },
  };
}

// -------------------------------------------------------------- drilldownBar

/** Registry entry for "drilldownBar".  `runDrilldownBar` IS `runTimeSeries`, and
 *  the non-null parent/child pair is what makes it take its drilldown branch
 *  (`isDD`, :1728). */
export function drilldownBarWidget(): Widget<DrilldownBarProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: DrilldownBarProps<InlineRelation>): void {
      const run = requireFn(ctx, "runDrilldownBar");
      const id = `${ctx.uid()}_barchart`;
      ctx.target.appendChild(chartSkeleton(ctx.document, id, "dd_barchart"));
      run(id, {
        type: "AxisChart",
        meta: legacyMeta(props.barMeta),
        series: [
          legacySeries(props.barSeries, props.barMeta, props.barRows, {
            // extraCols first, in the order drilldownBarChartPC passes them:
            // index 4 is the CHILD (the drilldown id `cur[4]`), index 5 the
            // PARENT (`_.filter(d, [5, ddid])`)
            scalarExtras: [props.barChildColumn, props.barParentColumn],
            listExtras: props.barSeries.extraColumns,
          }),
        ],
        parentCol: props.barParentColumn,
        childCol: props.barChildColumn,
      });
    },
  };
}

// ----------------------------------------------------------------- pieChart

/**
 * The rows `processPieData` reads: `[label, |value|, cssColor|null, child?,
 * parent?]`.
 *
 * The value is the ABSOLUTE value, as `runPieChartData` sends it --
 * `processPieData` sorts by `-y` and a negative slice would draw as a hole.
 *
 * The label is FORMATTED here, not passed raw. `RelationRunner.runPieChartData`
 * builds position 0 as `lc.format.basicEval(labels) extractNullableString ""`
 * (RelationRunner.scala:240): the label column's format applied server-side,
 * always a String, with a NULL flattened to "".  `args.labelFmt` cannot repair it
 * in the browser -- `runPiechart` hands it to `hcutil.pieLegendOptions` alone
 * (ermine-htmlwriter.js:2422), whose merged options end with the pie's own
 * `labelFormatter` (:1358-1369, :1379-1388) interpolating `this.name` verbatim,
 * and `this.name` is `r[0]` straight out of `processPieData` (:250-258).  So
 * whatever goes in at position 0 is what reaches the DOM.
 *
 * The RAW cell is formatted, not `axisValue`'s: a `[y, m, d]` triple would be
 * turned back into a `Date` by `formatDisplay`'s own `nelpeHwDates`.  A side
 * benefit is that `Default` runs `string_unhtml`, so the label the legend
 * interpolates into HTML is escaped -- the same move J3d made for table cells.
 */
export function pieRows(props: PieChartProps<InlineRelation>, env: FormatEnv): LegacyPieRow[] {
  const rel = props.pieRows;
  const labelAt = columnIndex(rel, props.pieLabelColumn);
  const labelFmt = formatDisplay(props.pieLabelFormat, env);
  const label = (row: WireCell[]): string => {
    const raw = labelAt < 0 ? null : ((row[labelAt] ?? null) as WireCell);
    return String(labelFmt([raw]) ?? "");
  };
  const valueAt = columnIndex(rel, props.pieValueColumn);
  const colorAt = props.pieColorColumn === undefined ? -1 : columnIndex(rel, props.pieColorColumn);
  const child = props.pieChildColumn === undefined ? null : reader(rel, props.pieChildColumn);
  const parent = props.pieParentColumn === undefined ? null : reader(rel, props.pieParentColumn);
  return rel.rows.map((row) => {
    const raw = valueAt < 0 ? null : row[valueAt];
    const n = typeof raw === "number" ? raw : Number(raw);
    const out: unknown[] = [
      label(row),
      Math.abs(Number.isFinite(n) ? n : 0),
      colorAt < 0 ? null : cssColor(row[colorAt]),
    ];
    if (child || parent) {
      out.push(child ? child(row) : null);
      out.push(parent ? parent(row) : null);
    }
    return out;
  });
}

function pieArgs(props: PieChartProps<InlineRelation>, env: FormatEnv): RunPiechartArgs {
  return {
    title: props.pieTitle,
    seriesName: props.seriesName,
    legendOptions: { type: "ChartLegendOptions", location: legendLocationOf(props.pieLegend.legendLocation) },
    renderHints: { type: "ChartRenderHints", enableDataLabels: props.pieHints.enableDataLabels },
    dataFmt: legacyFormatTuple(props.pieValueFormat),
    labelFmt: legacyFormatTuple(props.pieLabelFormat),
    parentCol: props.pieParentColumn ?? null,
    childCol: props.pieChildColumn ?? null,
    relation: pieRows(props, env),
  };
}

/** Registry entries for "pieChart" and "drilldownPieChart".  `drilldown` picks
 *  the renderer (`runPiechartDrilldown` is the same function under another name,
 *  :2632) and the css the legacy wraps it in.  The `FormatEnv` is what the slice
 *  LABEL is formatted with, exactly as the style box's aggregate is. */
export function pieChartWidget(drilldown: boolean, env?: FormatEnv): Widget<PieChartProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: PieChartProps<InlineRelation>): void {
      const run = requireFn(ctx, drilldown ? "runPiechartDrilldown" : "runPiechart");
      const fenv = env ?? defaultFormatEnv(ctx.document);
      const id = `${ctx.uid()}_piechart`;
      ctx.target.appendChild(chartSkeleton(ctx.document, id, drilldown ? "dd_piechart" : "piechart"));
      run(id, pieArgs(props, fenv));
    },
  };
}

// ----------------------------------------------------------------- styleBox

/** The fixed grid size stylebox.js is written around (`gridSize = 3`). */
export const STYLE_BOX_GRID = 3;

/** The three keys `stylebox.js` reads by name out of a `cellCounts` entry; an
 *  `aggColumn` called one of them would shadow it. */
const RESERVED_CELL_KEYS = new Set(["xPosition", "yPosition", "styleBoxAggFormatted"]);

/**
 * The aggregation `HTMLWriter.styleBox` does relationally before it emits
 * anything: sum `aggColumn` grouped by the two position columns, then format the
 * sum.  Positions outside `0..2` are kept -- `validatePosition` drops them in the
 * renderer, which is where the legacy drops them too.
 *
 * One divergence: SQL `Sum` over a nullable column ignores NULLs and answers NULL
 * for an all-NULL group, where a NULL cell counts as 0 here, so such a group shows
 * a formatted zero rather than the format of a `NullExpr`.
 *
 * The keys are `xPosition`/`yPosition` LITERALLY, because that is what
 * stylebox.js reads (:91-96).  Server-side those are the names of the position
 * columns themselves, so today the widget only works when they happen to be
 * called that; renaming here makes any column name work.
 */
export function styleBoxCells(props: StyleBoxProps<InlineRelation>, env: FormatEnv): StyleBoxCell[] {
  const rel = props.styleBoxRows;
  const xAt = columnIndex(rel, props.xPositionColumn);
  const yAt = columnIndex(rel, props.yPositionColumn);
  const aAt = columnIndex(rel, props.aggColumn);
  const sums = new Map<string, { x: number; y: number; sum: number }>();
  const order: string[] = [];
  for (const row of rel.rows) {
    const x = Number(xAt < 0 ? NaN : row[xAt]);
    const y = Number(yAt < 0 ? NaN : row[yAt]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    const v = Number(aAt < 0 ? 0 : row[aAt]);
    const key = `${x} ${y}`;
    const cur = sums.get(key);
    if (cur) cur.sum += Number.isFinite(v) ? v : 0;
    else {
      sums.set(key, { x, y, sum: Number.isFinite(v) ? v : 0 });
      order.push(key);
    }
  }
  const fmt = formatDisplay(props.aggFormat, env);
  return order.map((k) => {
    const g = sums.get(k) as { x: number; y: number; sum: number };
    const cell: StyleBoxCell = {
      xPosition: g.x,
      yPosition: g.y,
      styleBoxAggFormatted: String(fmt([g.sum]) ?? ""),
    };
    // an aggColumn literally named one of the three keys above would overwrite
    // it, and the renderer would then read a sum where it wants a position
    if (!RESERVED_CELL_KEYS.has(props.aggColumn)) cell[props.aggColumn] = g.sum;
    return cell;
  });
}

/** Registry entry for "styleBox". */
export function styleBoxWidget(env?: FormatEnv): Widget<StyleBoxProps<InlineRelation>> {
  return {
    render(ctx: WidgetContext, props: StyleBoxProps<InlineRelation>): void {
      const run = requireFn(ctx, "runStylebox");
      const fenv = env ?? defaultFormatEnv(ctx.document);
      const id = `${ctx.uid()}_stylebox`;
      ctx.target.appendChild(chartSkeleton(ctx.document, id, "stylebox"));
      run(id, {
        xTitle: props.xTitle,
        yTitle: props.yTitle,
        aField: props.aggColumn,
        aTitle: props.aggTitle,
        aFormat: legacyFormatTuple(props.aggFormat),
        // the legend is an f0 blob that only the styleBoxData POST reads, and
        // that POST has no local branch: see the callback table at the top
        legend: null,
        xPositionField: props.xPositionColumn,
        yPositionField: props.yPositionColumn,
        rowLabels: props.rowLabels,
        columnLabels: props.columnLabels,
        showNumber: props.showNumber ? "showNumber" : "hiddenNumber",
        xBins: props.xBins,
        yBins: props.yBins,
        cellCounts: JSON.stringify(styleBoxCells(props, fenv)),
        relation: null,
      });
    },
  };
}
