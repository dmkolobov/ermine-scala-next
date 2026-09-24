// Stage J3e: the chart and style-box adapters, argument by argument, plus the
// fast-check property on the tuple-format adapter the whole chart path formats
// through.
//
// The invariants asserted here are the ones the corpus property (b) then checks
// over 200 generated documents; this file is where each is stated once against a
// fixture small enough to read.

import { test } from "node:test";
import assert from "node:assert/strict";
import fc from "fast-check";

import { render } from "../src/dispatcher";
import { defaultRegistry } from "../src/index";
import { UNSUPPORTED_WIDGETS, WIDGET_PROP_SCHEMAS } from "../src/generated/widgets";
import { legacyFormatTuple, LEGACY_STYLE_NAMES } from "../src/legacy";
import {
  TUPLE_LOSS, axisValue, cssColor, legacyAxis, legacyMeta, legacyScalarType,
  legendLocationOf, pieRows, seriesRows, styleBoxCells, tupleIsLossless, ymd,
} from "../src/charts";
import { defaultFormatEnv, formatDisplay } from "../src/format";
import type {
  AxisChartProps, CellFormat, ChartMeta, ChartSeries, DrilldownBarProps,
  PieChartProps, StyleBoxProps,
} from "../src/generated/widgets";
import type { InlineRelation, Resolved } from "../src/relation";
import { cellFormatArb, inlineRelation, newDom, rawValuesArb, refusingFetch, stubHtmlWriter } from "./harness";
import { legacyAvailable, loadLegacyUtils, WRITERS_ROOT } from "./legacy-utils";

// --------------------------------------------------------------- fixtures

const META: ChartMeta = {
  chartTitle: "Sales",
  domainAxis: {
    axisLabel: "Month", tooltipLabel: "Month",
    axisFormat: { tag: "Default", args: [] },
    scalarType: { tag: "Scalar", typeName: "Date", typeNumeric: false },
    showTicks: true,
    constraints: { tag: "Unscaled", sortOrders: ["Asc"], tickOverrides: [["a", "b"]] },
  },
  rangeAxis: {
    axisLabel: "Revenue", tooltipLabel: "Revenue",
    axisFormat: { tag: "Round", color: false, negParens: false, places: 2 },
    scalarType: { tag: "Scalar", typeName: "Double", typeNumeric: true },
    showTicks: false,
    constraints: { tag: "Scaled", lowerBound: 0, displayScale: "Linear" },
  },
  orientation: "Horizontal",
  legendOptions: { legendLocation: "LegendRightTable" },
  renderHints: { enableDataLabels: true },
};

const SERIES: ChartSeries = {
  seriesColumns: ["region"],
  categoryColumns: ["month"],
  valueColumn: "revenue",
  extraColumns: ["units"],
  colorColumn: "colour",
  seriesFormat: { tag: "Constant", value: "R" },
  extraFormats: [{ tag: "IntegralRound", color: false, negParens: false, places: 0 }],
  variant: { tag: "Bar", args: [] },
};

/** month is a DATE column, so the chart path must see `[y, m, d]`. */
const REL: InlineRelation = inlineRelation(
  [
    { name: "month", type: "Date" },
    { name: "region", type: "String" },
    { name: "revenue", type: "Double" },
    { name: "units", type: "Int" },
    { name: "colour", type: "String", nullable: true },
    { name: "parent", type: "String", nullable: true },
    { name: "child", type: "String" },
  ],
  [
    ["2026-01-31", "east", 10.5, 3, "#FF0080", null, "e"],
    ["2026-02-28", "west", -4, 1, "not a colour", "e", "w"],
  ],
);

function mkDoc(name: string, props: unknown): { version: 1; settings: {}; root: unknown } {
  return { version: 1, settings: {}, root: { tag: "Widget", name, props } };
}

async function renderWidget(name: string, props: unknown): Promise<{
  target: Element; hw: ReturnType<typeof stubHtmlWriter>; errors: { message: string }[];
}> {
  const { document, target } = newDom();
  const hw = stubHtmlWriter();
  const doc = mkDoc(name, props) as never;
  const result = await render(target, doc as never, defaultRegistry(defaultFormatEnv(document)), {
    document, htmlwriter: hw, fetchData: refusingFetch,
  });
  return { target, hw, errors: result.errors };
}

// ------------------------------------------------- (t) the tuple adapter

test("(t-pin) legacyFormatTuple's spelling, one pin per CellFormat case", () => {
  const cases: [CellFormat, [string, unknown]][] = [
    [{ tag: "Default", args: [] }, ["Default", null]],
    [{ tag: "Verbatim", args: [] }, ["Verbatim", null]],
    [{ tag: "DateRange", args: [] }, ["DateRange", null]],
    [{ tag: "Constant", value: "x" }, ["Constant", "x"]],
    [{ tag: "Percentage", color: true, negParens: true, places: 2, pad: true }, ["Percentage", [2, true]]],
    [{ tag: "Currency", color: true, negParens: true, symbol: "$", places: 2 }, ["Currency", ["$", 2]]],
    [{ tag: "Round", color: true, negParens: true, places: 3 }, ["Round", 3]],
    [{ tag: "IntegralRound", color: true, negParens: true, places: 0 }, ["IntegralRound", 0]],
    [{ tag: "Truncate", places: 7 }, ["Truncate", 7]],
    [{ tag: "Markdown", base: { tag: "Default", args: [] } }, ["MarkdownFmt", null]],
    [{ tag: "Pr1", base: { tag: "Truncate", places: 4 } }, ["Pr1", ["Truncate", 4]]],
    [{ tag: "Pr2", base: { tag: "Truncate", places: 4 } }, ["Pr2", ["Truncate", 4]]],
    [{ tag: "Color", bg: { red: 1, green: 2, blue: 3 }, fg: { red: 4, green: 5, blue: 6 }, base: { tag: "Default", args: [] } }, ["ColorFormat", null]],
    [{
      tag: "Conditional",
      condition: { tag: "Gt", gt: { tag: "TNum", args: [1] } },
      whenTrue: { tag: "Default", args: [] }, whenFalse: { tag: "Default", args: [] },
    }, ["Conditional", null]],
  ];
  for (const [f, want] of cases) assert.deepStrictEqual(legacyFormatTuple(f), want, f.tag);
  // Alias is the one whose argument is an object, built prototype-less
  const alias = legacyFormatTuple({ tag: "Alias", aliases: [["a", "b"], ["a", "c"]] });
  assert.equal(alias[0], "Alias");
  assert.deepStrictEqual({ ...(alias[1] as object) }, { a: "c" });
  assert.equal(Object.getPrototypeOf(alias[1] as object), null);
  // TUPLE_LOSS covers every case, and says exactly which names the legacy has
  const tags = Object.keys(TUPLE_LOSS).sort();
  assert.equal(tags.length, 15);
  for (const [f] of cases) {
    const tup = legacyFormatTuple(f);
    assert.equal(TUPLE_LOSS[f.tag].implemented, LEGACY_STYLE_NAMES.includes(tup[0] as never),
      `${f.tag}: TUPLE_LOSS.implemented disagrees with LEGACY_STYLE_NAMES`);
  }
});

test("(t-tuple) the tuple adapter against the REAL legacy formatDisplay, 600 random formats", (t) => {
  if (!legacyAvailable()) { t.skip(`no ermine-writers checkout at ${WRITERS_ROOT}`); return; }
  const { document } = newDom();
  const legacy = loadLegacyUtils(document);
  const env = defaultFormatEnv(document);
  const dflt = legacy.formatDisplay(["Default", null]);

  let lossless = 0;
  let fellBack = 0;
  const seen = new Set<string>();
  fc.assert(
    fc.property(cellFormatArb(true), rawValuesArb, (f: CellFormat, values: unknown[]) => {
      const tup = legacyFormatTuple(f);
      seen.add(f.tag);
      // total, and a 2-tuple whose head is a style NAME
      assert.equal(tup.length, 2);
      assert.equal(typeof tup[0], "string");
      const loss = TUPLE_LOSS[f.tag];
      assert.ok(loss, `no TUPLE_LOSS row for ${f.tag}`);
      assert.equal(loss.implemented, LEGACY_STYLE_NAMES.includes(tup[0] as never));

      const got = legacy.formatDisplay(tup)(values);
      if (!loss.implemented) {
        // the documented loss IS a loss: formatDisplay has no entry for the
        // name, so it falls through to styleMap.Default
        assert.deepStrictEqual(got, dflt(values),
          `${f.tag} should fall back to Default in the legacy`);
        fellBack++;
      }
      if (tupleIsLossless(f)) {
        // ... and where nothing is lost, the tuple renders what the port renders
        assert.deepStrictEqual(got, formatDisplay(f, env)(values),
          `${f.tag} disagreed: ${JSON.stringify(f)} on ${JSON.stringify(values)}`);
        lossless++;
      }
      return true;
    }),
    { numRuns: 600 },
  );
  assert.ok(lossless > 100, `only ${lossless} lossless pairs were compared`);
  assert.ok(fellBack > 50, `only ${fellBack} fallbacks were seen`);
  assert.equal(seen.size, 15, `only ${seen.size} CellFormat cases occurred: ${[...seen].sort()}`);
  t.diagnostic(`600 formats: ${lossless} compared value-for-value, ${fellBack} fell back to Default`);
});

test("(t-mutant) a wrong tuple is caught by the same comparison", (t) => {
  if (!legacyAvailable()) { t.skip("no ermine-writers checkout"); return; }
  const { document } = newDom();
  const legacy = loadLegacyUtils(document);
  // Currency's tuple argument is [symbol, places], in that order.  Swapping it
  // -- the mistake the adapter could plausibly make -- renders "2NaN", which is
  // what the comparison in (t-tuple) would catch.
  const wrong = legacy.formatDisplay(["Currency", [2, "$"]] as [string, unknown])([12.3456]);
  const right = legacy.formatDisplay(
    legacyFormatTuple({ tag: "Currency", color: false, negParens: false, symbol: "$", places: 2 }),
  )([12.3456]);
  assert.equal(right, "$12.35");
  assert.notDeepStrictEqual(wrong, right);
});

// -------------------------------------------------------------- axis values

test("(x-dates) a Date column becomes the legacy [y, m, d] triple, and back", (t) => {
  assert.deepStrictEqual(ymd("2026-01-31"), [2026, 1, 31]);
  assert.deepStrictEqual(ymd("2026-01-31T12:00:00.000Z"), [2026, 1, 31]);
  assert.equal(ymd("not a date"), null);
  const col = { name: "d", type: "Date" as const, nullable: false };
  assert.deepStrictEqual(axisValue(col, "2026-01-31"), [2026, 1, 31]);
  // a null follows jsonPrepAxis: null in a numeric column, "" anywhere else
  assert.equal(axisValue(col, null), "");
  assert.equal(axisValue({ name: "n", type: "Double", nullable: true }, null), null);
  // a Long is a decimal STRING on the wire and a number on a chart axis
  assert.equal(axisValue({ name: "l", type: "Long", nullable: false }, "42"), 42);
  if (!legacyAvailable()) { t.skip("no ermine-writers checkout for the round trip"); return; }
  const { document } = newDom();
  const legacy = loadLegacyUtils(document);
  const back = legacy.nelpeHwDates([axisValue(col, "2026-01-31")])[0] as Date;
  assert.ok(back instanceof Date);
  assert.equal(back.toISOString().slice(0, 10), "2026-01-31");
});

test("(x-color) a colour cell is #rrggbb or null, never anything else", () => {
  assert.equal(cssColor("#FF0080"), "#ff0080");
  assert.equal(cssColor("#ff0080"), "#ff0080");
  assert.equal(cssColor("red"), null);
  assert.equal(cssColor("#12345"), null);
  assert.equal(cssColor(null), null);
  assert.equal(cssColor(7), null);
});

// ---------------------------------------------------------------- axisChart

test("(x-axis) the runTimeSeries argument object, meta and series, cell by cell", async () => {
  const props: Resolved<AxisChartProps> = {
    chartMeta: META, chartSeries: [SERIES], chartRows: REL,
  };
  const { target, hw, errors } = await renderWidget("axisChart", props);
  assert.deepStrictEqual(errors, []);
  assert.equal(hw.timeSeries.length, 1);
  const { id, args } = hw.timeSeries[0]!;

  // the DOM xyChart emits, addressed by the id the renderer is given
  const div = target.querySelector(`#${id}`);
  assert.ok(div, "no chart div");
  assert.equal(div?.className, "timeseries");
  assert.equal(div?.parentElement?.className, "timeseries_wrapper sizeme");

  assert.equal(args.type, "AxisChart");
  assert.equal(args.parentCol, null);
  assert.equal(args.childCol, null);

  // ---- meta
  assert.deepStrictEqual(args.meta, {
    type: "AxisChartData",
    title: "Sales",
    orientation: "horizontal",
    legendOptions: { type: "ChartLegendOptions", location: "RightTable" },
    renderHints: { type: "ChartRenderHints", enableDataLabels: true },
    colors: null,
    domain: {
      type: "Axis", label: "Month", tooltipLabel: "Month",
      format: ["Default", null],
      scalarType: { name: "Date", isNumeric: false },
      showTicks: true,
      constraints: { scaled: false, sort: ["Asc"], tickOverrides: [["a", "b"]] },
    },
    range: {
      type: "Axis", label: "Revenue", tooltipLabel: "Revenue",
      format: ["Round", 2],
      scalarType: { name: "Double", isNumeric: true },
      showTicks: false,
      constraints: { scaled: true, lowerBound: 0, upperBound: null, displayScale: "Linear" },
    },
  });

  // ---- series
  assert.equal(args.series.length, 1);
  const s = args.series[0]!;
  assert.equal(s.type, "ChartSeries");
  assert.deepStrictEqual(s.fmtSeries, ["Constant", "R"]);
  assert.deepStrictEqual(s.fmtExtra, [["IntegralRound", 0]]);
  assert.deepStrictEqual(s.selCategoryCols, [["month", false]]);
  assert.equal(s.variant, "Bar");
  assert.equal(s.zlabel, undefined);
  // `structure` must be ABSENT, or runTimeSeries takes the series-level
  // drilldown branch and looks for trees that are not there
  assert.ok(!("structure" in s), "structure must not be emitted");

  // one row per relation row, in the legacy positional shape
  assert.deepStrictEqual(s.data, [
    [[10.5], [[2026, 1, 31]], ["east"], "#ff0080", [3]],
    [[-4], [[2026, 2, 28]], ["west"], null, [1]],
  ]);
});

test("(x-axis-empty-series-column) no series column gives one unnamed series", async () => {
  const series: ChartSeries = { ...SERIES, seriesColumns: [], colorColumn: undefined, extraColumns: [] };
  const { hw } = await renderWidget("axisChart", { chartMeta: META, chartSeries: [series], chartRows: REL });
  const rows = hw.timeSeries[0]!.args.series[0]!.data;
  rows.forEach((r) => assert.deepStrictEqual((r as unknown[])[2], [""]));
  rows.forEach((r) => assert.equal((r as unknown[])[3], null));
});

test("(x-axis-bubble) a Bubble series carries its zlabel", async () => {
  const series: ChartSeries = { ...SERIES, variant: { tag: "Bubble", zLabel: "Units" } };
  const { hw } = await renderWidget("axisChart", { chartMeta: META, chartSeries: [series], chartRows: REL });
  const s = hw.timeSeries[0]!.args.series[0]!;
  assert.equal(s.variant, "Bubble");
  assert.equal(s.zlabel, "Units");
});

test("(x-scalartype) a compound scalar type is {name:'compound', types:[...]}", () => {
  assert.deepStrictEqual(
    legacyScalarType({
      tag: "Compound",
      componentTypes: [
        { tag: "Scalar", typeName: "String", typeNumeric: false },
        { tag: "Scalar", typeName: "Int", typeNumeric: true },
      ],
    }),
    {
      name: "compound", isNumeric: false,
      types: [{ name: "String", isNumeric: false }, { name: "Int", isNumeric: true }],
    });
  // every LegendLocation loses exactly its prefix
  assert.equal(legendLocationOf("LegendDefault"), "Default");
  assert.equal(legendLocationOf("LegendRightNotOverlay"), "RightNotOverlay");
  assert.equal(legendLocationOf("LegendHidden"), "Hidden");
});

// -------------------------------------------------------------- drilldownBar

test("(x-bar) runDrilldownBar: child at index 4, parent at index 5, both cols non-null", async () => {
  const props: Resolved<DrilldownBarProps> = {
    barMeta: META,
    barSeries: { ...SERIES, extraColumns: [], extraFormats: [] },
    barParentColumn: "parent",
    barChildColumn: "child",
    barRows: REL,
  };
  const { target, hw, errors } = await renderWidget("drilldownBar", props);
  assert.deepStrictEqual(errors, []);
  assert.equal(hw.drilldownBars.length, 1);
  const { id, args } = hw.drilldownBars[0]!;
  assert.ok(id.endsWith("_barchart"));
  assert.equal(target.querySelector(`#${id}`)?.className, "dd_barchart");
  // isDD = !isnull(parentCol) && !isnull(childCol) -- both must be there
  assert.equal(args.parentCol, "parent");
  assert.equal(args.childCol, "child");
  assert.equal(args.series.length, 1);
  assert.deepStrictEqual(args.series[0]!.data, [
    [[10.5], [[2026, 1, 31]], ["east"], "#ff0080", "e", ""],
    [[-4], [[2026, 2, 28]], ["west"], null, "w", "e"],
  ]);
});

// ----------------------------------------------------------------- pieChart

test("(x-pie) runPiechart: [label, |value|, colour] rows and the legend options", async () => {
  const props: Resolved<PieChartProps> = {
    pieTitle: "Share", seriesName: "Revenue",
    pieLabelColumn: "region", pieValueColumn: "revenue", pieColorColumn: "colour",
    // NOT Default on purpose.  The label reaches the legend, the tooltip and the
    // breadcrumb as `this.name`, which is row[0] straight out of processPieData,
    // and nothing in the bundle formats it again -- `args.labelFmt` only feeds
    // hcutil.pieLegendOptions, whose merged options end with the pie's own
    // labelFormatter interpolating `this.name` verbatim.  So the adapter has to
    // apply this here or the prop is inert, which is what this asserts.
    pieLabelFormat: { tag: "Alias", aliases: [["east", "East region"]] },
    pieValueFormat: { tag: "Round", color: false, negParens: false, places: 1 },
    pieLegend: { legendLocation: "LegendAbove" },
    pieHints: { enableDataLabels: false },
    pieRows: REL,
  };
  const { target, hw, errors } = await renderWidget("pieChart", props);
  assert.deepStrictEqual(errors, []);
  assert.equal(hw.pies.length, 1);
  assert.equal(hw.drilldownPies.length, 0);
  const { id, args } = hw.pies[0]!;
  assert.ok(id.endsWith("_piechart"));
  assert.equal(target.querySelector(`#${id}`)?.className, "piechart");
  assert.equal(args.title, "Share");
  assert.equal(args.seriesName, "Revenue");
  assert.deepStrictEqual(args.legendOptions, { type: "ChartLegendOptions", location: "Above" });
  assert.deepStrictEqual(args.renderHints, { type: "ChartRenderHints", enableDataLabels: false });
  assert.deepStrictEqual(args.dataFmt, ["Round", 1]);
  assert.equal(args.labelFmt[0], "Alias");
  // the alias map is built prototype-less, so spread it before comparing
  assert.deepStrictEqual({ ...(args.labelFmt[1] as object) }, { east: "East region" });
  assert.equal(args.parentCol, null);
  assert.equal(args.childCol, null);
  // the label is FORMATTED (RelationRunner.scala:240 applies the label column's
  // format server-side and takes `extractNullableString ""`), and the ABSOLUTE
  // value is sent: processPieData sorts by -y and a negative slice draws as a
  // hole, so -4 becomes 4 exactly as runPieChartData sends it
  assert.deepStrictEqual(args.relation, [
    ["East region", 10.5, "#ff0080"],
    ["west", 4, null],
  ]);
});

test("(x-pie-label) the slice label is formatted, and a Date label column is a STRING", async () => {
  const rel = inlineRelation(
    [
      { name: "day", type: "Date", nullable: true },
      { name: "amount", type: "Double" },
    ],
    [["2026-01-31", 5], [null, 2]],
  );
  const base = {
    pieTitle: "", seriesName: "s",
    pieLabelColumn: "day", pieValueColumn: "amount",
    pieValueFormat: { tag: "Default", args: [] } as CellFormat,
    pieLegend: { legendLocation: "LegendDefault" } as const,
    pieHints: { enableDataLabels: false },
    pieRows: rel,
  };
  // Default: the wire string, unescaped through string_unhtml -- NOT the [y,m,d]
  // triple the axis path wants.  A NULL label is "" (extractNullableString "").
  const plain = await renderWidget("pieChart", {
    ...base, pieLabelFormat: { tag: "Default", args: [] },
  });
  assert.deepStrictEqual(plain.errors, []);
  const plainRows = plain.hw.pies[0]!.args.relation;
  plainRows.forEach((r) => assert.equal(typeof (r as unknown[])[0], "string"));
  assert.deepStrictEqual(plainRows, [["2026-01-31", 5, null], ["", 2, null]]);

  // and a format that rewrites every value reaches row[0]
  const constant = await renderWidget("pieChart", {
    ...base, pieLabelFormat: { tag: "Constant", value: "ALL" },
  });
  assert.deepStrictEqual(constant.hw.pies[0]!.args.relation,
    [["ALL", 5, null], ["ALL", 2, null]]);

  // the same for the drilldown renderer, which shares pieArgs
  const dd = await renderWidget("drilldownPieChart", {
    ...base, pieLabelFormat: { tag: "Truncate", places: 6 },
    pieChildColumn: "day", pieParentColumn: "day",
  });
  assert.equal((dd.hw.drilldownPies[0]!.args.relation[0] as unknown[])[0], "202…");
});

test("(x-pie-dd) drilldownPieChart adds the child and parent positions", async () => {
  const props: Resolved<PieChartProps> = {
    pieTitle: "", seriesName: "s",
    pieLabelColumn: "region", pieValueColumn: "revenue", pieColorColumn: "colour",
    pieChildColumn: "child", pieParentColumn: "parent",
    pieLabelFormat: { tag: "Default", args: [] },
    pieValueFormat: { tag: "Default", args: [] },
    pieLegend: { legendLocation: "LegendDefault" },
    pieHints: { enableDataLabels: false },
    pieRows: REL,
  };
  const { target, hw } = await renderWidget("drilldownPieChart", props);
  assert.equal(hw.drilldownPies.length, 1);
  assert.equal(hw.pies.length, 0);
  const { id, args } = hw.drilldownPies[0]!;
  assert.equal(target.querySelector(`#${id}`)?.className, "dd_piechart");
  assert.equal(args.childCol, "child");
  assert.equal(args.parentCol, "parent");
  // withPiechartData filters `rec[4] === parentId` in the BROWSER, so the child
  // id must be at 3 and the parent at 4
  assert.deepStrictEqual(args.relation, [
    ["east", 10.5, "#ff0080", "e", ""],
    ["west", 4, null, "w", "e"],
  ]);
});

// ----------------------------------------------------------------- styleBox

const SB_REL: InlineRelation = inlineRelation(
  [
    { name: "sbAmount", type: "Double" },
    { name: "sbX", type: "Int" },
    { name: "sbY", type: "Int" },
  ],
  [[1.5, 0, 0], [2.5, 0, 0], [7, 1, 2], [9, 5, 5]],
);

const SB: Resolved<StyleBoxProps> = {
  xTitle: "Value", yTitle: "Growth",
  aggColumn: "sbAmount", aggTitle: "Amount",
  aggFormat: { tag: "Round", color: false, negParens: false, places: 1 },
  xPositionColumn: "sbX", yPositionColumn: "sbY",
  rowLabels: ["a", "b", "c"], columnLabels: ["x", "y", "z"],
  showNumber: true,
  xBins: [[0, 1], [1, 2], [2, 3]],
  yBins: [[0, 1], [1, 2], [2, 3]],
  styleBoxRows: SB_REL,
};

test("(x-stylebox) the aggregation the server does relationally, done here", async () => {
  const { document } = newDom();
  const cells = styleBoxCells(SB, defaultFormatEnv(document));
  // grouped by (x, y), summed, then formatted with aggFormat; the keys are
  // xPosition/yPosition LITERALLY, whatever the columns are called
  assert.deepStrictEqual(cells, [
    { xPosition: 0, yPosition: 0, styleBoxAggFormatted: "4.0", sbAmount: 4 },
    { xPosition: 1, yPosition: 2, styleBoxAggFormatted: "7.0", sbAmount: 7 },
    // out of the 3x3 grid: kept here, dropped by validatePosition in the renderer
    { xPosition: 5, yPosition: 5, styleBoxAggFormatted: "9.0", sbAmount: 9 },
  ]);
});

test("(x-stylebox-args) runStylebox gets a TUPLE aFormat and JSON inside a string", async () => {
  const { target, hw, errors } = await renderWidget("styleBox", SB);
  assert.deepStrictEqual(errors, []);
  assert.equal(hw.styleBoxes.length, 1);
  const { id, args } = hw.styleBoxes[0]!;
  assert.ok(id.endsWith("_stylebox"));
  assert.equal(target.querySelector(`#${id}`)?.className, "stylebox");
  assert.equal(args.aField, "sbAmount");
  assert.equal(args.aTitle, "Amount");
  assert.equal(args.xPositionField, "sbX");
  assert.equal(args.yPositionField, "sbY");
  assert.equal(args.showNumber, "showNumber");
  // runStylebox does `args.aFormat = formatDisplay(args.aFormat)`, so it must be
  // handed the tuple, not a formatted value and not the CellFormat object
  assert.deepStrictEqual(args.aFormat, ["Round", 1]);
  // cellCounts is JSON INSIDE a JSON string ($.parseJSON at stylebox.js:87)
  assert.equal(typeof args.cellCounts, "string");
  const parsed = JSON.parse(args.cellCounts) as { xPosition: number; sbAmount: number }[];
  assert.equal(parsed.length, 3);
  assert.equal(parsed[0]!.sbAmount, 4);
  // the two callback-only handles, sent as null on purpose: withStyleBoxData has
  // no local branch, so the cell-click popup is the one thing this path loses
  assert.equal(args.relation, null);
  assert.equal(args.legend, null);
  assert.deepStrictEqual(args.xBins, SB.xBins);
});

test("(x-stylebox-hidden) showNumber false is the legacy 'hiddenNumber' string", async () => {
  const { hw } = await renderWidget("styleBox", { ...SB, showNumber: false });
  assert.equal(hw.styleBoxes[0]!.args.showNumber, "hiddenNumber");
});

test("(x-stylebox-legacy) the legacy applies formatDisplay to aFormat itself", (t) => {
  if (!legacyAvailable()) { t.skip("no ermine-writers checkout"); return; }
  const { document } = newDom();
  const legacy = loadLegacyUtils(document);
  // stylebox.js does `let fz = aFormat(0)` on the ALREADY-curried function, and
  // runStylebox is what curries it -- so the tuple has to survive that
  const curried = legacy.formatDisplay(legacyFormatTuple(SB.aggFormat));
  assert.equal(curried([4]), "4.0");
});

// ------------------------------------------------------- unsupported widgets

test("(x-treemap) treeMap is registered as UNSUPPORTED: no renderer, an error box", async () => {
  assert.deepStrictEqual([...UNSUPPORTED_WIDGETS], ["treeMap"]);
  const registry = defaultRegistry();
  assert.equal((registry as Record<string, unknown>)["treeMap"], undefined, "treeMap must NOT be in the registry");
  // ... but its schema is not generated either, so the message is the registry's
  const { document, target } = newDom();
  const result = await render(target, mkDoc("treeMap", {}) as never, registry, {
    document, htmlwriter: stubHtmlWriter(), fetchData: refusingFetch,
  });
  assert.equal(result.errors.length, 1);
  assert.equal(result.errors[0]!.widget, "treeMap");
  const box = target.querySelector(".ermine-widget-error");
  assert.ok(box, "no error box");
  assert.equal(box?.getAttribute("data-widget"), "treeMap");
  // every GENERATED name does render (derived, never listed here: WP-32)
  for (const n of Object.keys(WIDGET_PROP_SCHEMAS)) {
    assert.ok((registry as Record<string, unknown>)[n], `${n} is not registered`);
  }
});

test("(x-no-htmlwriter) a chart without the legacy global is an error box, not a throw", async () => {
  const { document, target } = newDom();
  const result = await render(
    target,
    mkDoc("axisChart", { chartMeta: META, chartSeries: [SERIES], chartRows: REL }) as never,
    defaultRegistry(),
    { document, htmlwriter: undefined, fetchData: refusingFetch },
  );
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0]!.message, /runTimeSeries/);
  assert.ok(target.querySelector(".ermine-widget-error"));
});

test("(x-deferred) a chart's relation is resolved before the adapter sees it", async () => {
  const deferred = {
    kind: "deferred", columns: REL.columns, token: "tok-1",
    expires: "2030-01-01T00:00:00.000Z",
  };
  const { document, target } = newDom();
  const hw = stubHtmlWriter();
  const result = await render(
    target,
    mkDoc("axisChart", { chartMeta: META, chartSeries: [SERIES], chartRows: deferred }) as never,
    defaultRegistry(defaultFormatEnv(document)),
    {
      document, htmlwriter: hw,
      fetchData: async (token: string): Promise<InlineRelation> => {
        assert.equal(token, "tok-1");
        return REL;
      },
    },
  );
  assert.deepStrictEqual(result.errors, []);
  assert.equal(hw.timeSeries[0]!.args.series[0]!.data.length, 2);
});

// ------------------------------- the row builders, directly (property style)

test("(x-rows) every series row's category comes from the relation, every colour is #rrggbb or null", () => {
  const rows = seriesRows(SERIES, REL, { listExtras: SERIES.extraColumns });
  assert.equal(rows.length, REL.rows.length);
  const at = (n: string): number => REL.columns.findIndex((c) => c.name === n);
  rows.forEach((row, i) => {
    const wire = REL.rows[i]!;
    assert.deepStrictEqual(row[0], [axisValue(REL.columns[at("revenue")], wire[at("revenue")]!)]);
    assert.deepStrictEqual(row[1], [axisValue(REL.columns[at("month")], wire[at("month")]!)]);
    assert.deepStrictEqual(row[2], [axisValue(REL.columns[at("region")], wire[at("region")]!)]);
    const colour = row[3];
    assert.ok(colour === null || /^#[0-9a-f]{6}$/.test(colour as string), `colour ${String(colour)}`);
  });
  // a column the relation does not have reads as a null cell, not a throw
  const missing = seriesRows({ ...SERIES, valueColumn: "nope" }, REL);
  assert.deepStrictEqual(missing[0]![0], [""]);
  // pie rows: the value is absolute and finite even when the column is absent,
  // and the label is a STRING even when ITS column is absent ("")
  const { document } = newDom();
  const pr = pieRows({
    pieTitle: "", seriesName: "", pieLabelColumn: "nope", pieValueColumn: "nope",
    pieLabelFormat: { tag: "Default", args: [] }, pieValueFormat: { tag: "Default", args: [] },
    pieLegend: { legendLocation: "LegendDefault" }, pieHints: { enableDataLabels: false },
    pieRows: REL,
  }, defaultFormatEnv(document));
  pr.forEach((r) => {
    assert.equal(r[0], "");
    assert.equal(typeof r[1], "number");
    assert.ok(Number.isFinite(r[1] as number) && (r[1] as number) >= 0);
  });
});

test("(x-axis-fn) legacyAxis/legacyMeta are total over both constraint arms", () => {
  const unscaled = legacyAxis(META.domainAxis);
  assert.equal((unscaled.constraints as { scaled: boolean }).scaled, false);
  const scaled = legacyAxis(META.rangeAxis);
  assert.equal((scaled.constraints as { scaled: boolean }).scaled, true);
  assert.equal(legacyMeta({ ...META, orientation: "Vertical" }).orientation, "vertical");
});
