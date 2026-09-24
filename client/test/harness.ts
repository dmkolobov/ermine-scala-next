// jsdom, the stub `htmlwriter`, and the fast-check arbitraries the properties
// share.  The stub RECORDS every runTabular call instead of drawing a table: what
// the cross-language property checks is the ARGUMENT object, which is the whole
// contract between this client and the renderers that already exist.

import { JSDOM } from "jsdom";
import fc from "fast-check";
import type { CellFormat, CellCondition, Threshold, RGB } from "../src/generated/widgets";
import type { RunTabularArgs, HtmlWriter } from "../src/legacy";
import type { RunPiechartArgs, RunStyleboxArgs, RunTimeSeriesArgs } from "../src/charts";
import type { InlineRelation, WireCell } from "../src/relation";

/** A chart renderer is called `(id, args)`, unlike runTabular's single map. */
export interface ChartCall<A> {
  id: string;
  args: A;
}

export interface StubWriter extends HtmlWriter {
  calls: RunTabularArgs[];
  /** J3e.  One list per RENDERER, keyed by the name the adapter calls -- the
   *  aliases are recorded apart so a test can tell `runPiechart` from
   *  `runPiechartDrilldown` even though the bundle makes them one function. */
  timeSeries: ChartCall<RunTimeSeriesArgs>[];
  drilldownBars: ChartCall<RunTimeSeriesArgs>[];
  pies: ChartCall<RunPiechartArgs>[];
  drilldownPies: ChartCall<RunPiechartArgs>[];
  styleBoxes: ChartCall<RunStyleboxArgs>[];
}

export function stubHtmlWriter(): StubWriter {
  const calls: RunTabularArgs[] = [];
  const timeSeries: ChartCall<RunTimeSeriesArgs>[] = [];
  const drilldownBars: ChartCall<RunTimeSeriesArgs>[] = [];
  const pies: ChartCall<RunPiechartArgs>[] = [];
  const drilldownPies: ChartCall<RunPiechartArgs>[] = [];
  const styleBoxes: ChartCall<RunStyleboxArgs>[] = [];
  return {
    calls, timeSeries, drilldownBars, pies, drilldownPies, styleBoxes,
    runTabular(args: RunTabularArgs): void {
      calls.push(args);
    },
    runTimeSeries(id: string, args: RunTimeSeriesArgs): void {
      timeSeries.push({ id, args });
    },
    runDrilldownBar(id: string, args: RunTimeSeriesArgs): void {
      drilldownBars.push({ id, args });
    },
    runPiechart(id: string, args: RunPiechartArgs): void {
      pies.push({ id, args });
    },
    runPiechartDrilldown(id: string, args: RunPiechartArgs): void {
      drilldownPies.push({ id, args });
    },
    runStylebox(id: string, args: RunStyleboxArgs): void {
      styleBoxes.push({ id, args });
    },
    getScrollbarDimensions: () => ({ sbw: 15, sbh: 15 }),
    showFullPrimaryColumn: () => false,
    tableScrollable: () => true,
  };
}

export function newDom(): { dom: JSDOM; document: Document; target: Element } {
  const dom = new JSDOM("<!doctype html><html><body><div id='root'></div></body></html>");
  const document = dom.window.document as unknown as Document;
  return { dom, document, target: document.getElementById("root") as Element };
}

// ----------------------------------------------------------- arbitraries

const alphaNum = fc.stringMatching(/^[A-Za-z0-9]{0,8}$/);

export const rgbArb: fc.Arbitrary<RGB> = fc.record({
  red: fc.integer({ min: 0, max: 255 }),
  green: fc.integer({ min: 0, max: 255 }),
  blue: fc.integer({ min: 0, max: 255 }),
});

export const thresholdArb: fc.Arbitrary<Threshold> = fc.oneof(
  fc.double({ min: -1000, max: 1000, noNaN: true }).map((n) => ({ tag: "TNum", args: [n] }) as Threshold),
  alphaNum.map((s) => ({ tag: "TStr", args: [s] }) as Threshold),
  fc.boolean().map((b) => ({ tag: "TBool", args: [b] }) as Threshold),
);

export const conditionArb: fc.Arbitrary<CellCondition> = fc.letrec<{ c: CellCondition }>((tie) => ({
  c: fc.oneof(
    { depthSize: "small" },
    thresholdArb.map((t) => ({ tag: "Gt", gt: t }) as CellCondition),
    thresholdArb.map((t) => ({ tag: "Lt", lt: t }) as CellCondition),
    thresholdArb.map((t) => ({ tag: "Eq", eq: t }) as CellCondition),
    thresholdArb.map((t) => ({ tag: "Gte", gte: t }) as CellCondition),
    thresholdArb.map((t) => ({ tag: "Lte", lte: t }) as CellCondition),
    fc.tuple(tie("c"), tie("c")).map((p) => ({ tag: "And", and: p }) as CellCondition),
  ),
})).c;

/** A random CellFormat.  `flags` false pins `color`/`negParens` to false, which is
 *  what the legacy tuple form can express -- property (c) uses that mode. */
export function cellFormatArb(flags: boolean): fc.Arbitrary<CellFormat> {
  const flag = flags ? fc.boolean() : fc.constant(false);
  const places = fc.integer({ min: 0, max: 6 });
  return fc.letrec<{ f: CellFormat }>((tie) => ({
    f: fc.oneof(
      { depthSize: "small", withCrossShrink: true },
      fc.constant({ tag: "Default", args: [] } as CellFormat),
      fc.constant({ tag: "Verbatim", args: [] } as CellFormat),
      fc.constant({ tag: "DateRange", args: [] } as CellFormat),
      alphaNum.map((v) => ({ tag: "Constant", value: v }) as CellFormat),
      fc.record({ color: flag, negParens: flag, places, pad: fc.boolean() })
        .map((r) => ({ tag: "Percentage", ...r }) as CellFormat),
      fc.record({ color: flag, negParens: flag, symbol: fc.constantFrom("$", "€", "USD"), places })
        .map((r) => ({ tag: "Currency", ...r }) as CellFormat),
      fc.record({ color: flag, negParens: flag, places })
        .map((r) => ({ tag: "Round", ...r }) as CellFormat),
      fc.record({ color: flag, negParens: flag, places })
        .map((r) => ({ tag: "IntegralRound", ...r }) as CellFormat),
      fc.integer({ min: 1, max: 20 }).map((n) => ({ tag: "Truncate", places: n }) as CellFormat),
      // alias keys are held to [A-Za-z0-9]: the legacy looks a key up with
      // `aliases[fst]` on a plain object, so "constructor" or "__proto__" there
      // would answer Object.prototype's member.  The port walks a list of pairs
      // and is not exposed to that; see the open issue in report-J3d.md.
      fc.array(fc.tuple(alphaNum, alphaNum), { maxLength: 4 })
        .map((ps) => ({ tag: "Alias", aliases: ps }) as CellFormat),
      tie("f").map((b) => ({ tag: "Markdown", base: b }) as CellFormat),
      tie("f").map((b) => ({ tag: "Pr1", base: b }) as CellFormat),
      tie("f").map((b) => ({ tag: "Pr2", base: b }) as CellFormat),
      fc.tuple(conditionArb, tie("f"), tie("f"))
        .map(([c, t, e]) => ({ tag: "Conditional", condition: c, whenTrue: t, whenFalse: e }) as CellFormat),
      fc.tuple(rgbArb, rgbArb, tie("f"))
        .map(([bg, fg, b]) => ({ tag: "Color", bg, fg, base: b }) as CellFormat),
    ),
  })).f;
}

/** Wire cells plus the YMD triples the legacy turns into Dates. */
export const rawValueArb: fc.Arbitrary<unknown> = fc.oneof(
  fc.double({ min: -1e6, max: 1e6, noNaN: true }),
  fc.integer({ min: -1000, max: 1000 }),
  fc.string({ maxLength: 12 }),
  fc.constantFrom("<b>bold</b>", "a&amp;b", "&nbsp;x", "2026-09-16", ""),
  fc.boolean(),
  fc.constant(null),
  fc.tuple(fc.integer({ min: 1970, max: 2030 }), fc.integer({ min: 1, max: 12 }), fc.integer({ min: 1, max: 28 })),
);

export const rawValuesArb: fc.Arbitrary<unknown[]> = fc.array(rawValueArb, { minLength: 1, maxLength: 4 });

/** A small inline relation, for the widget tests. */
export function inlineRelation(
  columns: { name: string; type: InlineRelation["columns"][number]["type"]; nullable?: boolean }[],
  rows: WireCell[][],
): InlineRelation {
  // the wire sorts columns by name and every row follows that order, so the
  // helper permutes the values it is given rather than leaving them misaligned
  const order = columns.map((_c, i) => i)
    .sort((a, b) => (columns[a]!.name < columns[b]!.name ? -1 : columns[a]!.name > columns[b]!.name ? 1 : 0));
  return {
    kind: "inline",
    columns: order.map((i) => ({ name: columns[i]!.name, type: columns[i]!.type, nullable: columns[i]!.nullable ?? false })),
    rows: rows.map((r) => order.map((i) => r[i] ?? null)),
    rowCount: rows.length,
  };
}

/** No deferred relation should reach this; the tests that expect one install
 *  their own. */
export const refusingFetch = async (token: string): Promise<InlineRelation> => {
  throw new Error(`unexpected deferred fetch for ${token}`);
};
