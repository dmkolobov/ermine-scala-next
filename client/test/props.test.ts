// The generated zod is the authority on the wire; src/props.ts is the
// compile-time mirror of it.  These pins fail when the two drift -- a field
// renamed in Ermine, a constructor added, a Maybe field that stopped being
// optional -- instead of leaving a silent `any` in the client.

import { test } from "node:test";
import assert from "node:assert/strict";
import { z } from "zod";

import {
  TablePropsSchema, DrilldownTablePropsSchema, ScorecardPropsSchema,
  CellFormatSchema, DocNodeSchema, WIDGET_PROP_SCHEMAS,
} from "../src/generated";
import { COLUMN_TYPES, InlineRelationSchema, DeferredRelationSchema, WireRelationSchema, isWireRelation } from "../src/relation";
import { alignmentOf, columnTypeOf } from "../src/legacy";
import { evalCondition } from "../src/format";
import type { CellCondition, ColumnAlign, ColumnKind, Threshold } from "../src/props";

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

test("(p-registry) every registry name has a generated schema", () => {
  assert.deepStrictEqual(Object.keys(WIDGET_PROP_SCHEMAS).sort(),
    ["drilldownTable", "scorecard", "table"]);
});
