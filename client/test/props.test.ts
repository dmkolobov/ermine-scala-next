// The generated zod is the authority on the wire; src/props.ts is the
// compile-time mirror of it.  These pins fail when the two drift -- a field
// renamed in Ermine, a constructor added, a Maybe field that stopped being
// optional -- instead of leaving a silent `any` in the client.

import { test } from "node:test";
import assert from "node:assert/strict";
import { z } from "zod";

import {
  TablePropsSchema, DrilldownTablePropsSchema, ScorecardPropsSchema, HeadlinePropsSchema,
  CrosstabPropsSchema, HeadingPropsSchema, TextPropsSchema,
  AxisChartPropsSchema, PieChartPropsSchema, StyleBoxPropsSchema, DrilldownBarPropsSchema,
  CellFormatSchema, DocNodeSchema, WIDGET_PROP_SCHEMAS, UNSUPPORTED_WIDGETS,
} from "../src/generated";
// the shared chart types live inside the generated axis-chart module, which is
// where `ermine-schema --zod` inlines every $def it reaches
import {
  Layout_Widgets_Chart_AxisConstraints as AxisConstraintsSchema,
  Layout_Widgets_Chart_ChartAxis as ChartAxisSchema,
  Layout_Widgets_Chart_ChartMeta as ChartMetaSchema,
  Layout_Widgets_Chart_ChartSeries as ChartSeriesSchema,
  Layout_Widgets_Chart_ChartVariant as ChartVariantSchema,
  Layout_Widgets_Chart_DisplayScale as DisplayScaleSchema,
  Layout_Widgets_Chart_LegendLocation as LegendLocationSchema,
  Layout_Widgets_Chart_Orientation as OrientationSchema,
  Layout_Widgets_Chart_ScalarType as ScalarTypeSchema,
  Layout_Widgets_Chart_SortDir as SortDirSchema,
} from "../src/generated/axisChart";
import { COLUMN_TYPES, InlineRelationSchema, DeferredRelationSchema, WireRelationSchema, isWireRelation } from "../src/relation";
import { alignmentOf, columnTypeOf } from "../src/legacy";
import { legacyAxis, legacyScalarType, legendLocationOf } from "../src/charts";
import { evalCondition } from "../src/format";
import type { CellCondition, ColumnAlign, ColumnKind, LegendLocation, Threshold } from "../src/props";

// The vocabularies src/props.ts declares.  Kept here as literals on purpose: the
// point of the pin is that the generated zod and these two lists must agree, so
// importing the types would defeat it.
const COLUMN_ALIGNS = ["AlignLeft", "AlignRight"];
const COLUMN_KINDS = ["DateColumn", "NumberColumn", "OtherColumn"];   // sorted
const THRESHOLD_TAGS = ["TBool", "TNum", "TStr"];                     // sorted
const CELL_CONDITION_TAGS = ["And", "Eq", "Gt", "Gte", "Lt", "Lte"];  // sorted

function unwrap(schema: unknown): any {
  let s = schema as any;
  while (s && s._def && s._def.typeName === "ZodLazy") s = s._def.getter();
  return s;
}

function keysOf(schema: unknown): string[] {
  const s = unwrap(schema);
  return Object.keys(s.shape ?? s._def?.shape?.() ?? {}).sort();
}

function optionalKeys(schema: unknown): string[] {
  const s = unwrap(schema);
  const shape = s.shape ?? s._def?.shape?.() ?? {};
  return Object.keys(shape).filter((k) => (shape[k] as z.ZodTypeAny).isOptional()).sort();
}

/** The `tag` literals of a generated discriminated union, sorted. */
function unionTags(schema: unknown): string[] {
  return Object.keys(unionArms(schema)).sort();
}

/** The members of a generated `z.enum`, sorted. */
function enumValues(schema: unknown): string[] {
  return [...((unwrap(schema)._def.values ?? []) as string[])].sort();
}

function unionArms(schema: unknown): Record<string, string[]> {
  const s = unwrap(schema);
  const out: Record<string, string[]> = {};
  for (const arm of s.options ?? []) {
    const tag = (arm as any).shape?.tag?.value as string;
    out[tag] = Object.keys((arm as any).shape).filter((k) => k !== "tag").sort();
  }
  return out;
}

test("(p-table) TableProps as declared in Layout/Widgets/Table.e", () => {
  assert.deepStrictEqual(keysOf(TablePropsSchema),
    ["columns", "paginate", "rowGroup", "rows", "scroll", "sorts"]);
  assert.deepStrictEqual(optionalKeys(TablePropsSchema), ["rowGroup"],
    "only the `Maybe Int` field may be optional");
  const shape = unwrap(TablePropsSchema).shape;
  assert.deepStrictEqual(keysOf(unwrap(shape.columns)._def.type), ["align", "cellFormat", "column", "header", "kind"]);
  assert.deepStrictEqual(keysOf(unwrap(shape.sorts)._def.type), ["descending", "sortColumn"]);
  // the ENUM MEMBERS, not just the field names: a case added in Ermine would
  // otherwise pass check-generated.sh, tsc and this file, and then silently make
  // `alignmentOf` answer "left" and `columnTypeOf` answer undefined
  const col = unwrap(unwrap(shape.columns)._def.type);
  assert.deepStrictEqual(enumValues(col.shape.align), COLUMN_ALIGNS);
  assert.deepStrictEqual(enumValues(col.shape.kind), COLUMN_KINDS);
  // both directions: every generated member is one the adapter handles, and
  // every member the adapter handles is generated
  COLUMN_ALIGNS.forEach((a) => assert.ok(["left", "right"].includes(alignmentOf(a as ColumnAlign))));
  COLUMN_KINDS.forEach((k) => assert.ok(["number", "date", "other"].includes(columnTypeOf(k as ColumnKind))));
  // `rows` is a BARE relation, so both arms are there
  assert.deepStrictEqual(
    unwrap(shape.rows).options.map((o: any) => o.shape.kind.value).sort(), ["deferred", "inline"]);
});

test("(p-drilldown) DrilldownTableProps as declared", () => {
  assert.deepStrictEqual(keysOf(DrilldownTablePropsSchema),
    ["childColumn", "ddColumns", "ddPaginate", "ddRows", "ddScroll", "ddSorts", "labelColumn", "parentColumn"]);
  assert.deepStrictEqual(optionalKeys(DrilldownTablePropsSchema), []);
});

test("(p-scorecard) ScorecardProps as declared; `cards` is Inline, so there is no deferred arm", () => {
  assert.deepStrictEqual(keysOf(ScorecardPropsSchema),
    ["cardDelta", "cardFormat", "cardLabel", "cardValue", "cards", "title"]);
  assert.deepStrictEqual(optionalKeys(ScorecardPropsSchema), ["cardDelta"]);
  const cards = unwrap(unwrap(ScorecardPropsSchema).shape.cards);
  assert.deepStrictEqual(keysOf(cards), ["columns", "kind", "rowCount", "rows"]);
  assert.equal(cards.safeParse({ kind: "deferred", columns: [], token: "t", expires: "2026-01-01T00:00:00.000Z" }).success, false);
});

test("(p-headline) HeadlineProps as declared; no relation at all", () => {
  assert.deepStrictEqual(keysOf(HeadlinePropsSchema),
    ["headlineFormat", "headlineTitle", "largest", "rowCount", "scope", "total"]);
  assert.deepStrictEqual(optionalKeys(HeadlinePropsSchema), []);
  // the numbers the Ermine scan produced, and nothing to resolve on this side
  assert.equal(HeadlinePropsSchema.safeParse({
    headlineTitle: "T", scope: "s", rowCount: 3, total: 1.5, largest: 1.5,
    headlineFormat: { tag: "Default", args: [] },
  }).success, true);
  assert.equal(HeadlinePropsSchema.safeParse({
    headlineTitle: "T", scope: "s", rowCount: 3, total: 1.5,
    headlineFormat: { tag: "Default", args: [] },
  }).success, false);
});

test("(p-heading-text) HeadingProps and TextProps as declared in Layout/Widgets/Heading.e and Text.e (Q25)", () => {
  assert.deepStrictEqual(keysOf(HeadingPropsSchema), ["matched", "sortColumn", "title", "total"]);
  assert.deepStrictEqual(optionalKeys(HeadingPropsSchema), []);
  assert.deepStrictEqual(keysOf(TextPropsSchema), ["body"]);
  assert.deepStrictEqual(optionalKeys(TextPropsSchema), []);
  // a record, never a bare string: the pre-Q25 wire is refused
  assert.equal(TextPropsSchema.safeParse({ body: "x" }).success, true);
  assert.equal(TextPropsSchema.safeParse("x").success, false);
  assert.equal(HeadingPropsSchema.safeParse({ title: "S", sortColumn: "day", matched: 1, total: 2.5 }).success, true);
  assert.equal(HeadingPropsSchema.safeParse({ title: "S", sortColumn: "day", matched: 1.5, total: 2.5 }).success, false);
});

test("(p-crosstab) CrosstabProps as declared; a cell is a number OR null", () => {
  assert.deepStrictEqual(keysOf(CrosstabPropsSchema),
    ["cells", "colHeader", "colTotals", "crosstabColLabels", "crosstabFormat", "crosstabRowLabels",
     "crosstabTitle", "grandTotal", "rowHeader", "rowTotals"]);
  // nothing is optional: a `Maybe` INSIDE a list is a nullable element, not an
  // absent key -- the encoder omits a key only for a named Maybe FIELD
  assert.deepStrictEqual(optionalKeys(CrosstabPropsSchema), []);
  const ok = {
    crosstabTitle: "T", rowHeader: "Region", colHeader: "Month",
    crosstabRowLabels: ["north", "south"], crosstabColLabels: ["jan", "feb", "mar"],
    cells: [[1.5, null, 2.5], [null, 3, 4]],
    rowTotals: [4, 7], colTotals: [1.5, 3, 6.5], grandTotal: 11,
    crosstabFormat: { tag: "Default", args: [] },
  };
  assert.equal(CrosstabPropsSchema.safeParse(ok).success, true);
  // a null is a pair no row had; a STRING there is not a cell
  assert.equal(CrosstabPropsSchema.safeParse({ ...ok, cells: [["x", null, 2.5], [null, 3, 4]] }).success, false);
  // ...and the matrix is a matrix: a bare number is not a row
  assert.equal(CrosstabPropsSchema.safeParse({ ...ok, cells: [1.5, 2.5] }).success, false);
  // the totals carry no nulls
  assert.equal(CrosstabPropsSchema.safeParse({ ...ok, rowTotals: [4, null] }).success, false);
});

test("(p-format) every CellFormat constructor and its fields", () => {
  assert.deepStrictEqual(unionArms(CellFormatSchema), {
    Default: ["args"],
    Verbatim: ["args"],
    Markdown: ["base"],
    Constant: ["value"],
    Percentage: ["color", "negParens", "pad", "places"],
    Currency: ["color", "negParens", "places", "symbol"],
    Pr1: ["base"],
    Pr2: ["base"],
    DateRange: ["args"],
    Round: ["color", "negParens", "places"],
    IntegralRound: ["color", "negParens", "places"],
    Truncate: ["places"],
    Conditional: ["condition", "whenFalse", "whenTrue"],
    Color: ["base", "bg", "fg"],
    Alias: ["aliases"],
  });
});

test("(p-condition) Threshold and CellCondition arms, and evalCondition handles every one", () => {
  // reachable from the CellFormat union: Conditional.condition, then any arm's threshold
  const conditional = unwrap(CellFormatSchema).options.find((o: any) => o.shape.tag.value === "Conditional");
  const condition = conditional.shape.condition;
  assert.deepStrictEqual(unionTags(condition), CELL_CONDITION_TAGS);
  const gt = unwrap(condition).options.find((o: any) => o.shape.tag.value === "Gt");
  assert.deepStrictEqual(unionTags(gt.shape.gt), THRESHOLD_TAGS);
  assert.deepStrictEqual(unionArms(condition), {
    Gt: ["gt"], Lt: ["lt"], Eq: ["eq"], Gte: ["gte"], Lte: ["lte"], And: ["and"],
  });
  assert.deepStrictEqual(unionArms(gt.shape.gt), {
    TNum: ["args"], TStr: ["args"], TBool: ["args"],
  });

  // both directions: every generated arm is decided by evalCondition, and every
  // arm evalCondition decides is generated.  A missing case falls off the switch
  // and returns undefined, so a Conditional would silently always take whenFalse.
  const sample: Record<string, CellCondition> = {
    Gt: { tag: "Gt", gt: { tag: "TNum", args: [0] } },
    Lt: { tag: "Lt", lt: { tag: "TNum", args: [9] } },
    Eq: { tag: "Eq", eq: { tag: "TNum", args: [1] } },
    Gte: { tag: "Gte", gte: { tag: "TNum", args: [1] } },
    Lte: { tag: "Lte", lte: { tag: "TNum", args: [1] } },
    And: { tag: "And", and: [
      { tag: "Gte", gte: { tag: "TNum", args: [0] } },
      { tag: "Lte", lte: { tag: "TBool", args: [true] } }] },
  };
  assert.deepStrictEqual(Object.keys(sample).sort(), CELL_CONDITION_TAGS);
  for (const [tag, cond] of Object.entries(sample)) {
    assert.equal(typeof evalCondition(cond, 1), "boolean", `evalCondition has no case for ${tag}`);
    assert.equal(unwrap(condition).safeParse(cond).success, true, `${tag} is not what the schema expects`);
  }
  // and each Threshold arm round-trips through the generated schema
  const thresholds: Threshold[] = [
    { tag: "TNum", args: [1.5] }, { tag: "TStr", args: ["x"] }, { tag: "TBool", args: [false] }];
  assert.deepStrictEqual(thresholds.map((t) => t.tag).sort(), THRESHOLD_TAGS);
  thresholds.forEach((t) => assert.equal(unwrap(gt.shape.gt).safeParse(t).success, true, t.tag));
});

test("(p-doc) Layout.Doc.Node, and Tab carrying no tag", () => {
  assert.deepStrictEqual(unionArms(DocNodeSchema), {
    Widget: ["name", "props"],
    VFlow: ["children"],
    HFlow: ["children"],
    Grid: ["cells"],
    Tabbed: ["tabs"],
  });
  const tabbed = unwrap(DocNodeSchema).options.find((o: any) => o.shape.tag.value === "Tabbed");
  const tab = unwrap(unwrap(tabbed.shape.tabs)._def.type);
  assert.deepStrictEqual(keysOf(tab), ["content", "label"]);
});

test("(p-wire) the hand-written relation types match the generated ones", () => {
  const generated = unwrap(unwrap(TablePropsSchema).shape.rows);
  const inline = generated.options.find((o: any) => o.shape.kind.value === "inline");
  const deferred = generated.options.find((o: any) => o.shape.kind.value === "deferred");
  assert.deepStrictEqual(keysOf(inline), keysOf(InlineRelationSchema));
  assert.deepStrictEqual(keysOf(deferred), keysOf(DeferredRelationSchema));
  const col = unwrap(unwrap(inline.shape.columns)._def.type);
  assert.deepStrictEqual(keysOf(col), ["name", "nullable", "type"]);
  assert.deepStrictEqual([...(col.shape.type._def.values as string[])].sort(), [...COLUMN_TYPES].sort());
  // and they accept and refuse the same documents
  const doc = { kind: "inline", columns: [{ name: "a", type: "Int", nullable: false }], rows: [[1]], rowCount: 1 };
  assert.equal(inline.safeParse(doc).success, true);
  assert.equal(WireRelationSchema.safeParse(doc).success, true);
  assert.equal(inline.safeParse({ ...doc, extra: 1 }).success, false);
  assert.equal(WireRelationSchema.safeParse({ ...doc, extra: 1 }).success, false);
});

test("(p-relation-guard) isWireRelation does not mistake a props record for a relation", () => {
  // the whole arm, with column descriptors, is a relation
  const rel = { kind: "inline", columns: [{ name: "a", type: "Int", nullable: false }], rows: [[1]], rowCount: 1 };
  const deferred = { kind: "deferred", columns: rel.columns, token: "t", expires: "2099-01-01T00:00:00.000Z" };
  assert.equal(isWireRelation(rel), true);
  assert.equal(isWireRelation(deferred), true);
  // a props record that merely HAS `kind` and `columns` is not -- TableColumn
  // already declares a field named `kind`, so the margin would otherwise be one
  // field name wide, and a J3e chart descriptor is exactly this shape
  assert.equal(isWireRelation({ kind: "inline", columns: ["a", "b"] }), false);
  assert.equal(isWireRelation({ kind: "deferred", columns: [] }), false);
  assert.equal(isWireRelation({ kind: "inline", columns: [], rows: [] }), false);        // no rowCount
  assert.equal(isWireRelation({ kind: "deferred", columns: [], token: "t" }), false);    // no expires
  assert.equal(isWireRelation({ kind: "inline", columns: [{ name: "a", type: "Money", nullable: false }], rows: [], rowCount: 0 }), false);
  assert.equal(isWireRelation({ kind: "OtherColumn", columns: [] }), false);
  assert.equal(isWireRelation([rel]), false);
  assert.equal(isWireRelation(null), false);
});

test("(p-registry) every registry name has a generated schema, and treeMap has none", () => {
  assert.deepStrictEqual(Object.keys(WIDGET_PROP_SCHEMAS).sort(),
    ["axisChart", "crosstab", "drilldownBar", "drilldownPieChart", "drilldownTable", "heading", "headline",
     "pieChart", "scorecard", "styleBox", "table", "text"]);
  // the two pie names share ONE props type, as Layout/Widgets/PieChart.e declares
  assert.equal(WIDGET_PROP_SCHEMAS["pieChart"], WIDGET_PROP_SCHEMAS["drilldownPieChart"]);
  // treeMap is the reserved name with no renderer: no schema either, so a
  // document naming it cannot even get as far as validation
  assert.equal(WIDGET_PROP_SCHEMAS["treeMap"], undefined);
  assert.deepStrictEqual([...UNSUPPORTED_WIDGETS], ["treeMap"]);
});

// --------------------------------------------------------- J3e: the charts

test("(p-charts) the four chart prop types as declared in Layout/Widgets/*.e", () => {
  assert.deepStrictEqual(keysOf(AxisChartPropsSchema), ["chartMeta", "chartRows", "chartSeries"]);
  assert.deepStrictEqual(optionalKeys(AxisChartPropsSchema), []);
  // `chartRows` is a BARE relation: both arms, resolved by the dispatcher
  assert.deepStrictEqual(
    unwrap(unwrap(AxisChartPropsSchema).shape.chartRows).options.map((o: any) => o.shape.kind.value).sort(),
    ["deferred", "inline"]);

  assert.deepStrictEqual(keysOf(DrilldownBarPropsSchema),
    ["barChildColumn", "barMeta", "barParentColumn", "barRows", "barSeries"]);
  assert.deepStrictEqual(optionalKeys(DrilldownBarPropsSchema), []);

  assert.deepStrictEqual(keysOf(PieChartPropsSchema),
    ["pieChildColumn", "pieColorColumn", "pieHints", "pieLabelColumn", "pieLabelFormat",
     "pieLegend", "pieParentColumn", "pieRows", "pieTitle", "pieValueColumn",
     "pieValueFormat", "seriesName"]);
  assert.deepStrictEqual(optionalKeys(PieChartPropsSchema),
    ["pieChildColumn", "pieColorColumn", "pieParentColumn"],
    "only the three `Maybe String` fields may be optional");
  // `pieRows` is `Inline r`: the inline arm alone, no `kind: "deferred"` to handle
  const pieRel = unwrap(unwrap(PieChartPropsSchema).shape.pieRows);
  assert.deepStrictEqual(keysOf(pieRel), ["columns", "kind", "rowCount", "rows"]);
  assert.equal(pieRel.safeParse({ kind: "deferred", columns: [], token: "t", expires: "2026-01-01T00:00:00.000Z" }).success, false);

  assert.deepStrictEqual(keysOf(StyleBoxPropsSchema),
    ["aggColumn", "aggFormat", "aggTitle", "columnLabels", "rowLabels", "showNumber",
     "styleBoxRows", "xBins", "xPositionColumn", "xTitle", "yBins", "yPositionColumn", "yTitle"]);
  assert.deepStrictEqual(optionalKeys(StyleBoxPropsSchema), []);
  const sbRel = unwrap(unwrap(StyleBoxPropsSchema).shape.styleBoxRows);
  assert.deepStrictEqual(keysOf(sbRel), ["columns", "kind", "rowCount", "rows"]);
});

test("(p-chart-types) the shared chart vocabulary, and every enum member reaches an adapter", () => {
  assert.deepStrictEqual(keysOf(ChartMetaSchema),
    ["chartTitle", "domainAxis", "legendOptions", "orientation", "rangeAxis", "renderHints"]);
  assert.deepStrictEqual(keysOf(ChartAxisSchema),
    ["axisFormat", "axisLabel", "constraints", "scalarType", "showTicks", "tooltipLabel"]);
  assert.deepStrictEqual(keysOf(ChartSeriesSchema),
    ["categoryColumns", "colorColumn", "extraColumns", "extraFormats", "seriesColumns",
     "seriesFormat", "valueColumn", "variant"]);
  assert.deepStrictEqual(optionalKeys(ChartSeriesSchema), ["colorColumn"]);

  assert.deepStrictEqual(unionArms(ScalarTypeSchema), {
    Scalar: ["typeName", "typeNumeric"], Compound: ["componentTypes"],
  });
  assert.deepStrictEqual(unionArms(AxisConstraintsSchema), {
    Scaled: ["displayScale", "lowerBound", "upperBound"],
    Unscaled: ["sortOrders", "tickOverrides"],
  });
  assert.deepStrictEqual(unionTags(ChartVariantSchema),
    ["Bar", "BoxAndWhiskers", "Bubble", "Line", "Scatter", "StackedArea", "StackedBar", "Step"]);
  // only Bubble is non-nullary
  assert.deepStrictEqual(unionArms(ChartVariantSchema)["Bubble"], ["zLabel"]);

  // ---- the enum MEMBERS, both directions.  A location added in Ermine that the
  // adapter does not strip would reach Highcharts as a class name it has no rule
  // for; a DisplayScale or SortDir added would travel unrecognised.
  const locations = enumValues(LegendLocationSchema);
  assert.deepStrictEqual(locations,
    ["LegendAbove", "LegendDefault", "LegendHidden", "LegendOverlay",
     "LegendRightNotOverlay", "LegendRightOverlay", "LegendRightTable"]);
  const stripped = locations.map((l) => legendLocationOf(l as LegendLocation));
  assert.deepStrictEqual(stripped.sort(),
    ["Above", "Default", "Hidden", "Overlay", "RightNotOverlay", "RightOverlay", "RightTable"]);
  stripped.forEach((s) => assert.ok(!s.startsWith("Legend"), `${s} kept its prefix`));
  assert.deepStrictEqual(enumValues(OrientationSchema), ["Horizontal", "Vertical"]);
  assert.deepStrictEqual(enumValues(DisplayScaleSchema), ["Linear", "Logarithmic"]);
  assert.deepStrictEqual(enumValues(SortDirSchema), ["Asc", "Desc"]);

  // every ScalarType arm is handled by the adapter (a missing case would fall
  // off the switch and hand Highcharts `undefined`)
  assert.deepStrictEqual(
    legacyScalarType({ tag: "Scalar", typeName: "Int", typeNumeric: true }),
    { name: "Int", isNumeric: true });
  assert.equal(legacyScalarType({ tag: "Compound", componentTypes: [] }).name, "compound");
  // and both AxisConstraints arms
  const axis = (c: any): any => legacyAxis({
    axisLabel: "l", tooltipLabel: "t", axisFormat: { tag: "Default", args: [] },
    scalarType: { tag: "Scalar", typeName: "String", typeNumeric: false },
    showTicks: true, constraints: c,
  }).constraints;
  assert.equal(axis({ tag: "Scaled", displayScale: "Logarithmic" }).scaled, true);
  assert.equal(axis({ tag: "Unscaled", sortOrders: [], tickOverrides: [] }).scaled, false);
});
