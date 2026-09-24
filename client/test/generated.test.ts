// The generated module (src/generated/widgets.ts, WP-32) and what the client
// builds on it.  src/props.ts and its pins are GONE: the prop types are generated
// from Ermine, recursive ones declared and annotated `z.ZodType<X>`, and
// scripts/check-fresh.js (the `generated` gate) proves each declaration EQUALS
// zod's inference.  What stays here is what the generator cannot see:
//
//   (g-tsc)          tsc REFUSES a registry with a name not in WidgetRegistry, a
//                    renderer for the wrong props type, and a missing name;
//   (g-no-name-lists) no source or test lists the widget names by hand;
//   (g-wire)         relation.ts's hand-written relation types equal the generated
//                    relation arms, at runtime and at compile time;
//   (g-relation-guard), (g-condition), (g-adapters): the hand-written code that
//                    switches over a generated vocabulary handles all of it.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as cp from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import {
  WIDGET_PROP_SCHEMAS, UNSUPPORTED_WIDGETS,
  TablePropsSchema, ScorecardPropsSchema, CellConditionSchema, ThresholdSchema,
  ColumnAlignSchema, ColumnKindSchema, LegendLocationSchema,
  type CellCondition, type Threshold, type TableProps, type ScorecardProps,
  type ScalarType, type AxisConstraints,
} from "../src/generated/widgets";
import {
  COLUMN_TYPES, InlineRelationSchema, DeferredRelationSchema, WireRelationSchema, isWireRelation,
  type InlineRelation, type DeferredRelation,
} from "../src/relation";
import { alignmentOf, columnTypeOf } from "../src/legacy";
import { legacyAxis, legacyScalarType, legendLocationOf } from "../src/charts";
import { evalCondition } from "../src/format";

// dist/test -> dist -> client
const CLIENT = path.resolve(__dirname, "..", "..");

/** The zod object behind a schema (the generated consts are plain; a `z.lazy`
 *  appears only inside them). */
function unwrap(schema: unknown): any {
  let s = schema as any;
  while (s && s._def && s._def.typeName === "ZodLazy") s = s._def.getter();
  return s;
}
function keysOf(schema: unknown): string[] {
  const s = unwrap(schema);
  return Object.keys(s.shape ?? {}).sort();
}
function unionTags(schema: unknown): string[] {
  return (unwrap(schema).options as any[]).map((o) => o.shape.tag.value as string).sort();
}

// ------------------------------------------------------------------ (g-tsc)

/** Runs the client's tsc over `files` (name -> source) in a scratch directory
 *  inside client/ (so `../src/...` and `zod` resolve), and answers its error
 *  lines by file. */
interface Diag { code: string; at: string }
function tscOver(files: Record<string, string>): { rc: number | null; byFile: Record<string, Diag[]>; out: string } {
  const dir = fs.mkdtempSync(path.join(CLIENT, ".tsc-probe-"));
  try {
    for (const [name, src] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), src);
    fs.writeFileSync(path.join(dir, "tsconfig.json"), JSON.stringify({
      extends: "../tsconfig.json", compilerOptions: { noEmit: true }, include: Object.keys(files),
    }));
    const tsc = path.join(CLIENT, "node_modules", "typescript", "bin", "tsc");
    const r = cp.spawnSync(process.execPath, [tsc, "-p", dir], { encoding: "utf8" });
    const out = r.stdout + r.stderr;
    // each diagnostic as its CODE and the source text it points at (the rest of
    // the line from its column): the printed types in the message would tie the
    // test to Text.e's and Heading.e's fields and to tsc's wording (review N-1)
    const byFile: Record<string, Diag[]> = {};
    for (const name of Object.keys(files)) byFile[name] = [];
    for (const line of out.split("\n")) {
      const m = line.match(/(?:^|[\\/])([\w-]+\.ts)\((\d+),(\d+)\): error (TS\d+):/);
      if (!m || !byFile[m[1]!]) continue;
      const srcLine = (files[m[1]!]!.split("\n")[Number(m[2]) - 1] ?? "").slice(Number(m[3]) - 1);
      byFile[m[1]!]!.push({ code: m[4]!, at: srcLine });
    }
    return { rc: r.status, byFile, out };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("(g-tsc) tsc refuses a renderer under a name not in WidgetRegistry, a renderer for the wrong props type, and a missing name", () => {
  const head = 'import { defaultRegistry, headingWidget, textWidget, type Registry } from "../src/index";\n' +
    "void headingWidget; void textWidget;\n";
  const r = tscOver({
    // the control: the same imports and the real registry compile, so the three
    // refusals below are about the registry and not the scaffolding
    "control.ts": head + "export const r: Registry = { ...defaultRegistry() };\n",
    "extra-name.ts": head + "export const r: Registry = { ...defaultRegistry(), bogusWidget: headingWidget() };\n",
    "wrong-props.ts": head + "export const r: Registry = { ...defaultRegistry(), heading: textWidget() };\n",
    "missing-name.ts": head + "const { heading: _gone, ...rest } = defaultRegistry();\nvoid _gone;\n" +
      "export const r: Registry = rest;\n",
  });
  assert.notEqual(r.rc, 0, "tsc accepted every file:\n" + r.out);
  assert.deepStrictEqual(r.byFile["control.ts"], [], "the control must compile:\n" + r.out);
  const one = (f: string): Diag => {
    assert.equal(r.byFile[f]!.length, 1, `${f}: want exactly one diagnostic:\n${r.out}`);
    return r.byFile[f]![0]!;
  };
  // codes and the offending key only
  const extra = one("extra-name.ts");
  assert.equal(extra.code, "TS2353", r.out);
  assert.match(extra.at, /^bogusWidget:/, "the excess key is the one refused");
  // the wrong renderer is refused AT ITS KEY
  const wrong = one("wrong-props.ts");
  assert.equal(wrong.code, "TS2322", r.out);
  assert.match(wrong.at, /^heading:/, "the error sits on the heading entry");
  const missing = one("missing-name.ts");
  assert.equal(missing.code, "TS2741", r.out);
  assert.match(r.out, /missing-name\.ts\(\d+,\d+\): error TS2741: Property 'heading' is missing/, "the missing key is named");
});

// ------------------------------------------------------- (g-no-name-lists)

test("(g-no-name-lists) no source or test lists the widget names by hand: they are read off the generated module", () => {
  // WP-32: a hand-written list goes stale the day a widget is added (the corpus
  // list did, twice).  Three or more DISTINCT widget names as string literals in
  // one innermost [...] is a list; one or two (an exception set, a pair of
  // aliases) is not.  src/generated is the one place the names are written.
  const names = new Set(Object.keys(WIDGET_PROP_SCHEMAS));
  assert.ok(names.size >= 3);
  const roots = [path.join(CLIENT, "src"), path.join(CLIENT, "test")];
  const offenders: string[] = [];
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (e.name !== "generated") walk(p); continue; }
      if (!e.name.endsWith(".ts")) continue;
      const src = fs.readFileSync(p, "utf8");
      for (const m of src.matchAll(/\[[^\[\]]*\]/g)) {
        const found = new Set([...m[0].matchAll(/["'`](\w+)["'`]/g)].map((q) => q[1]!).filter((s) => names.has(s)));
        if (found.size >= 3) {
          const line = src.slice(0, m.index).split("\n").length;
          offenders.push(`${path.relative(CLIENT, p)}:${line} lists ${[...found].join(", ")}`);
        }
      }
    }
  };
  roots.forEach(walk);
  assert.deepStrictEqual(offenders, [], "derive the names from WIDGET_PROP_SCHEMAS / WidgetName instead");
});

test("(g-registry) the two pie names share ONE props schema; the unsupported names have none", () => {
  // Layout/Widgets/PieChart.e declares pieChart and drilldownPieChart at the
  // same PieChartProps: one type, two keys
  assert.equal(WIDGET_PROP_SCHEMAS.pieChart, WIDGET_PROP_SCHEMAS.drilldownPieChart);
  assert.ok(UNSUPPORTED_WIDGETS.length > 0);
  for (const n of UNSUPPORTED_WIDGETS) {
    assert.equal(Object.prototype.hasOwnProperty.call(WIDGET_PROP_SCHEMAS, n), false, `${n} has a schema`);
  }
});

// ----------------------------------------------------------------- (g-wire)

// compile time, both directions: the hand-written relation types and the
// generated relation arms are the same types (a drift is a tsc error here)
type GenInline = Extract<TableProps["rows"], { kind: "inline" }>;
type GenDeferred = Extract<TableProps["rows"], { kind: "deferred" }>;
const _i1: InlineRelation = null as unknown as GenInline;
const _i2: GenInline = null as unknown as InlineRelation;
const _d1: DeferredRelation = null as unknown as GenDeferred;
const _d2: GenDeferred = null as unknown as DeferredRelation;
// `Inline r` (a scorecard's cards) is the inline arm alone
const _c1: InlineRelation = null as unknown as ScorecardProps["cards"];
const _c2: ScorecardProps["cards"] = null as unknown as InlineRelation;
void [_i1, _i2, _d1, _d2, _c1, _c2];

test("(g-wire) the hand-written relation types match the generated ones", () => {
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
  // `Inline r` refuses a deferred relation outright
  const cards = unwrap(unwrap(ScorecardPropsSchema).shape.cards);
  assert.equal(cards.safeParse({ kind: "deferred", columns: [], token: "t", expires: "2026-01-01T00:00:00.000Z" }).success, false);
});

test("(g-relation-guard) isWireRelation does not mistake a props record for a relation", () => {
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
  assert.equal(isWireRelation({ kind: "deferred", columns: [], token: "t" }), false);    // no expires
  assert.equal(isWireRelation({ kind: "inline", columns: [{ name: "a", type: "Money", nullable: false }], rows: [], rowCount: 0 }), false);
  assert.equal(isWireRelation({ kind: "OtherColumn", columns: [] }), false);
  assert.equal(isWireRelation([rel]), false);
  assert.equal(isWireRelation(null), false);
});

// ------------------------------------------ the hand-written switches, total

test("(g-condition) evalCondition decides every generated CellCondition arm, over every Threshold arm", () => {
  // one sample per tag, TYPED so that a tag added in Ermine is a tsc error here
  // (a missing key) and a removed one too (an excess key)
  const sample: { [T in CellCondition["tag"]]: Extract<CellCondition, { tag: T }> } = {
    Gt: { tag: "Gt", gt: { tag: "TNum", args: [0] } },
    Lt: { tag: "Lt", lt: { tag: "TNum", args: [9] } },
    Eq: { tag: "Eq", eq: { tag: "TNum", args: [1] } },
    Gte: { tag: "Gte", gte: { tag: "TNum", args: [1] } },
    Lte: { tag: "Lte", lte: { tag: "TNum", args: [1] } },
    And: { tag: "And", and: [
      { tag: "Gte", gte: { tag: "TNum", args: [0] } },
      { tag: "Lte", lte: { tag: "TBool", args: [true] } }] },
  };
  assert.deepStrictEqual(Object.keys(sample).sort(), unionTags(CellConditionSchema));
  for (const [tag, cond] of Object.entries(sample)) {
    // a missing case falls off the switch and returns undefined, so a
    // Conditional would silently always take whenFalse
    assert.equal(typeof evalCondition(cond, 1), "boolean", `evalCondition has no case for ${tag}`);
    assert.equal(CellConditionSchema.safeParse(cond).success, true, tag);
  }
  const thresholds: { [T in Threshold["tag"]]: Extract<Threshold, { tag: T }> } = {
    TNum: { tag: "TNum", args: [1.5] }, TStr: { tag: "TStr", args: ["x"] }, TBool: { tag: "TBool", args: [false] },
  };
  assert.deepStrictEqual(Object.keys(thresholds).sort(), unionTags(ThresholdSchema));
  for (const t of Object.values(thresholds)) {
    assert.equal(ThresholdSchema.safeParse(t).success, true, t.tag);
    assert.equal(typeof evalCondition({ tag: "Eq", eq: t }, 1), "boolean", t.tag);
  }
});

test("(g-adapters) every member of a generated enum reaches its adapter", () => {
  // read off the generated z.enum, never listed here
  for (const a of ColumnAlignSchema.options) assert.ok(["left", "right"].includes(alignmentOf(a)), a);
  for (const k of ColumnKindSchema.options) assert.ok(["number", "date", "other"].includes(columnTypeOf(k)), k);
  const stripped = LegendLocationSchema.options.map((l) => legendLocationOf(l));
  assert.equal(new Set(stripped).size, LegendLocationSchema.options.length, "two locations collapsed");
  stripped.forEach((s) => assert.ok(s.length > 0 && !s.startsWith("Legend"), `${s} kept its prefix`));
  // both ScalarType arms and both AxisConstraints arms, typed so a new arm is a
  // tsc error here
  const scalar: { [T in ScalarType["tag"]]: Extract<ScalarType, { tag: T }> } = {
    Scalar: { tag: "Scalar", typeName: "Int", typeNumeric: true },
    Compound: { tag: "Compound", componentTypes: [] },
  };
  assert.deepStrictEqual(legacyScalarType(scalar.Scalar), { name: "Int", isNumeric: true });
  assert.equal(legacyScalarType(scalar.Compound).name, "compound");
  const constraints: { [T in AxisConstraints["tag"]]: Extract<AxisConstraints, { tag: T }> } = {
    Scaled: { tag: "Scaled", displayScale: "Logarithmic" },
    Unscaled: { tag: "Unscaled", sortOrders: [], tickOverrides: [] },
  };
  const axis = (c: AxisConstraints): any => legacyAxis({
    axisLabel: "l", tooltipLabel: "t", axisFormat: { tag: "Default", args: [] },
    scalarType: scalar.Scalar, showTicks: true, constraints: c,
  }).constraints;
  assert.equal(axis(constraints.Scaled).scaled, true);
  assert.equal(axis(constraints.Unscaled).scaled, false);
});
