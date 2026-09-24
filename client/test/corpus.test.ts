// Property (b), the cross-language half: documents written by the Scala side
// (com.clarifi.reporting.WidgetCorpus, from the same random prop values property
// (a) validates) are parsed, dispatched and rendered here, and what reaches the
// stub `htmlwriter` is checked against the legacy interface and its invariants.
//
//   sbt -batch 'core/Test/runMain com.clarifi.reporting.WidgetCorpus <dir> 200'
//   ERMINE_CORPUS=<dir> node --test "dist/test/*.test.js"
//
// `client/scripts/check-corpus.sh <dir>` does both halves of the second line.
// Each <dir>/NNN.json is a document; <dir>/NNN.tokens.json is the {token: inline
// relation} map that stands for the runner's GET /data/<token>.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";

import { safeParseDocument, parseDocument } from "../src/document";
import { render } from "../src/dispatcher";
import { defaultRegistry } from "../src/index";
import { tabularCell, legacyFormat, type LegacyCell, type LegacyTreeRow, type RunTabularArgs } from "../src/legacy";
import { defaultFormatEnv, formatDisplay } from "../src/format";
import { InlineRelationSchema, type InlineRelation } from "../src/relation";
import { axisValue, TUPLE_LOSS, TUPLE_STYLE_NAMES } from "../src/charts";
import type {
  AxisChartProps, CellFormat, ChartSeries, DrilldownBarProps, PieChartProps,
  StyleBoxProps, TableColumn,
} from "../src/props";
import { newDom, stubHtmlWriter, type StubWriter } from "./harness";
import { mutateOnce } from "./mutate";

// dist/test -> client -> the repo root: the same path client/scripts/check-corpus.sh
// writes, so `npm test` after that script finds the fixtures with no environment.
const CORPUS = process.env.ERMINE_CORPUS ?? path.resolve(__dirname, "../../../target/widget-corpus");

const MISSING = `no corpus at ${CORPUS} -- run client/scripts/check-corpus.sh, or ` +
  `sbt 'core/Test/runMain com.clarifi.reporting.WidgetCorpus ${CORPUS} 200'`;

function corpusNames(): string[] {
  if (!fs.existsSync(path.join(CORPUS, "manifest.json"))) return [];
  return JSON.parse(fs.readFileSync(path.join(CORPUS, "manifest.json"), "utf8")) as string[];
}

function tokensOf(stem: string): Record<string, InlineRelation> {
  const f = path.join(CORPUS, `${stem}.tokens.json`);
  if (!fs.existsSync(f)) return {};
  return JSON.parse(fs.readFileSync(f, "utf8")) as Record<string, InlineRelation>;
}

function isTreeRows(rel: RunTabularArgs["relation"]): rel is LegacyTreeRow[] {
  return rel.length > 0 && typeof (rel[0] as LegacyTreeRow).indent === "number";
}

// ------------------------------------------------- J3e: the chart invariants
//
// Stated once here, checked over every chart in every corpus document.  They are
// the same ones test/charts.test.ts states against a readable fixture.

const CSS_COLOR = /^#[0-9a-f]{6}$/;
const LEGEND_LOCATIONS = ["Default", "Above", "Overlay", "RightOverlay",
                          "RightNotOverlay", "RightTable", "Hidden"];

/** Anything that reaches a chart as a format must be a `[name, arg]` pair whose
 *  name is one of the fifteen `legacyFormatTuple` can emit.  A name outside that
 *  set is an adapter bug the legacy would swallow: `formatDisplay` falls back to
 *  `styleMap.Default` for any name it does not have, so nothing would ever
 *  complain at runtime. */
function assertTuple(t: unknown, where: string): void {
  assert.ok(Array.isArray(t) && t.length === 2, `${where}: not a 2-tuple: ${JSON.stringify(t)}`);
  const name = (t as unknown[])[0];
  assert.equal(typeof name, "string", `${where}: tuple head`);
  assert.ok(TUPLE_STYLE_NAMES.includes(name as string),
    `${where}: ${String(name)} is not a style name legacyFormatTuple emits`);
  assert.equal(Object.keys(TUPLE_LOSS).length, 15, "TUPLE_LOSS lost a case");
  assert.equal(TUPLE_STYLE_NAMES.length, 15, "TUPLE_STYLE_NAMES lost a case");
}

function assertMeta(meta: any, where: string): void {
  assert.equal(meta.type, "AxisChartData", where);
  assert.equal(meta.colors, null, `${where}: colors is a POST-only handle and must be null`);
  assert.ok(meta.orientation === "vertical" || meta.orientation === "horizontal", where);
  assert.equal(meta.legendOptions.type, "ChartLegendOptions");
  assert.ok(LEGEND_LOCATIONS.includes(meta.legendOptions.location),
    `${where}: legend location ${meta.legendOptions.location}`);
  assert.equal(meta.renderHints.type, "ChartRenderHints");
  assert.equal(typeof meta.renderHints.enableDataLabels, "boolean");
  for (const axis of [meta.domain, meta.range]) {
    assert.equal(axis.type, "Axis", where);
    assertTuple(axis.format, `${where} axis format`);
    assert.equal(typeof axis.scalarType.name, "string");
    assert.equal(typeof axis.scalarType.isNumeric, "boolean");
    assert.equal(typeof axis.showTicks, "boolean");
    if (axis.constraints.scaled) {
      assert.ok(axis.constraints.lowerBound === null || typeof axis.constraints.lowerBound === "number");
      assert.ok(["Linear", "Logarithmic"].includes(axis.constraints.displayScale));
    } else {
      assert.ok(Array.isArray(axis.constraints.sort));
      assert.ok(Array.isArray(axis.constraints.tickOverrides));
    }
  }
}

/** One legacy series against the ChartSeries that produced it and the relation
 *  the rows came from.  `extras` is how many positions follow the colour. */
function assertSeries(
  s: any, spec: ChartSeries, rel: InlineRelation, scalarExtras: string[], where: string,
): number {
  assert.equal(s.type, "ChartSeries", where);
  assertTuple(s.fmtSeries, `${where} fmtSeries`);
  assert.equal(s.fmtExtra.length, spec.extraFormats.length);
  s.fmtExtra.forEach((t: unknown, i: number) => assertTuple(t, `${where} fmtExtra[${i}]`));
  assert.equal(s.selCategoryCols.length, spec.categoryColumns.length);
  assert.ok(!("structure" in s), `${where}: structure must not be emitted`);
  assert.equal(typeof s.variant, "string");
  if (s.variant === "Bubble") assert.equal(typeof s.zlabel, "string");
  assert.equal(s.data.length, rel.rows.length, `${where}: one row per relation row`);

  const at = (n: string): number => rel.columns.findIndex((c) => c.name === n);
  const want = (n: string, row: unknown[]): unknown => {
    const i = at(n);
    return axisValue(i < 0 ? undefined : rel.columns[i], i < 0 ? null : ((row[i] ?? null) as never));
  };
  const nSers = Math.max(1, spec.seriesColumns.length);
  const width = 4 + scalarExtras.length + spec.extraColumns.length;
  s.data.forEach((row: unknown[], r: number) => {
    const wire = rel.rows[r] as unknown[];
    assert.equal(row.length, width, `${where}: row width`);
    assert.deepStrictEqual(row[0], [want(spec.valueColumn, wire)], `${where}: value`);
    // EVERY series row's category is one of the relation's values, in order
    assert.deepStrictEqual(row[1], spec.categoryColumns.map((c) => want(c, wire)), `${where}: category`);
    assert.equal((row[2] as unknown[]).length, nSers, `${where}: series name arity`);
    if (spec.seriesColumns.length) {
      assert.deepStrictEqual(row[2], spec.seriesColumns.map((c) => want(c, wire)), `${where}: series`);
    } else {
      assert.deepStrictEqual(row[2], [""], `${where}: unnamed series`);
    }
    const colour = row[3];
    assert.ok(colour === null || (typeof colour === "string" && CSS_COLOR.test(colour)),
      `${where}: colour ${JSON.stringify(colour)} is neither #rrggbb nor null`);
    scalarExtras.forEach((c, i) => assert.deepStrictEqual(row[4 + i], want(c, wire), `${where}: extraCol`));
    spec.extraColumns.forEach((c, i) =>
      assert.deepStrictEqual(row[4 + scalarExtras.length + i], [want(c, wire)], `${where}: extraOp`));
  });
  return s.data.length;
}

test("(b) the whole corpus parses, dispatches and reaches runTabular with legal arguments", async (t) => {
  const names = corpusNames();
  if (names.length === 0) { t.skip(MISSING); return; }
  assert.ok(names.length >= 100, `${names.length} documents in ${CORPUS}, want at least 100`);

  let widgets = 0;
  let cells = 0;
  let tokensResolved = 0;
  const kinds = new Set<string>();
  const widgetNames = new Set<string>();
  const formatTags = new Set<string>();
  const sortDirections = new Set<string>();
  // J3e
  const variants = new Set<string>();
  let chartPoints = 0;
  let pieSlices = 0;
  let styleBoxCellCount = 0;

  for (const stem of names) {
    const text = fs.readFileSync(path.join(CORPUS, `${stem}.json`), "utf8");
    const tokens = tokensOf(stem);
    for (const k of Object.keys(tokens)) kinds.add("deferred");

    const parsed = safeParseDocument(JSON.parse(text));
    assert.ok(parsed.ok, `${stem}: ${parsed.ok ? "" : parsed.error.message}`);
    if (!parsed.ok) continue;

    const { document, target } = newDom();
    const hw = stubHtmlWriter();
    const env = defaultFormatEnv(document);
    const result = await render(target, parsed.document, defaultRegistry(env), {
      document,
      htmlwriter: hw,
      fetchData: async (token: string): Promise<InlineRelation> => {
        const rel = tokens[token];
        assert.ok(rel, `${stem}: no rows recorded for token ${token}`);
        const ok = InlineRelationSchema.safeParse(rel);
        assert.ok(ok.success, `${stem}: the token payload is not an inline relation`);
        tokensResolved++;
        return rel as InlineRelation;
      },
    });
    assert.deepStrictEqual(result.errors, [], `${stem}: ${JSON.stringify(result.errors)}`);

    // every widget of the document produced exactly one piece of DOM
    const rendered = target.querySelectorAll(".ermine-widget");
    assert.equal(target.querySelectorAll(".ermine-widget-error").length, 0, `${stem}: an error box`);
    widgets += rendered.length;
    rendered.forEach((el) => widgetNames.add(el.getAttribute("data-widget") ?? "?"));

    // ---- the legacy interface, per runTabular call
    for (const args of hw.calls) {
      assert.equal(typeof args.id, "string");
      assert.ok(args.id.endsWith("_tabular"), `${stem}: id ${args.id}`);
      assert.ok(Array.isArray(args.cols));
      assert.equal(args.colAlignments.length, args.cols.length);
      assert.equal(args.colType.length, args.cols.length);
      args.colAlignments.forEach((a) => assert.ok(a === "left" || a === "right"));
      args.colType.forEach((c) => assert.ok(c === "number" || c === "date" || c === "other"));
      args.sorts.forEach(([i, d]) => {
        assert.equal(typeof i, "number");
        assert.ok(Number.isInteger(i) && i >= 0, `sort column ${i}`);
        // a STRING, not a boolean: DataTables names its comparator
        // `oSort[sDataType + "-" + aaSort[k][1]]` (datatables.js:4019)
        assert.ok(d === "asc" || d === "desc", `sort direction ${String(d)}`);
        sortDirections.add(d);
      });
      assert.equal(typeof args.paginate, "boolean");
      assert.equal(typeof args.scroll, "boolean");
      assert.equal(args.legend, null);
      if (args.isDD) assert.equal(args.rowgroupCol, undefined);
      else assert.ok(args.rowgroupCol === null || typeof args.rowgroupCol === "number");
      // the DOM skeleton the legacy expects is in the tree, addressed by that id
      const table = target.querySelector(`#${args.id}`);
      assert.ok(table, `${stem}: no table skeleton for ${args.id}`);
      assert.equal(table?.parentElement?.className, "tabular_wrapper");

      const rows: LegacyCell[][] = isTreeRows(args.relation)
        ? (args.relation as LegacyTreeRow[]).map((r) => r.content)
        : (args.relation as LegacyCell[][]);
      if (isTreeRows(args.relation)) {
        (args.relation as LegacyTreeRow[]).forEach((r, i) => {
          assert.equal(r.ix, i);
          assert.ok(r.indent >= 0);
        });
      }
      // cells.length = rows x displayed columns
      rows.forEach((row) => assert.equal(row.length, args.cols.length, `${stem}: row width`));
      cells += rows.length * args.cols.length;
    }

    // ---- J3e: every chart call's id addresses the skeleton the renderer wants
    for (const { id } of hw.timeSeries) {
      assert.equal(target.querySelector(`#${id}`)?.className, "timeseries", `${stem}: ${id}`);
    }
    for (const { id } of hw.drilldownBars) {
      assert.ok(id.endsWith("_barchart"), `${stem}: ${id}`);
      assert.equal(target.querySelector(`#${id}`)?.className, "dd_barchart");
    }
    for (const { id } of hw.pies) {
      assert.ok(id.endsWith("_piechart"), `${stem}: ${id}`);
      assert.equal(target.querySelector(`#${id}`)?.className, "piechart");
    }
    for (const { id } of hw.drilldownPies) {
      assert.equal(target.querySelector(`#${id}`)?.className, "dd_piechart");
    }
    for (const { id } of hw.styleBoxes) {
      assert.ok(id.endsWith("_stylebox"), `${stem}: ${id}`);
      assert.equal(target.querySelector(`#${id}`)?.className, "stylebox");
    }

    // ---- raw / formatted / format, against the props the document carried
    const doc = parseDocument(JSON.parse(text));
    let call = 0;
    const chartCall = { ts: 0, bar: 0, pie: 0, ddPie: 0, sb: 0 };
    const resolve = (r: any): InlineRelation =>
      (r.kind === "inline" ? r : tokens[r.token]) as InlineRelation;
    const walk = (node: unknown): void => {
      const n = node as { tag?: string; name?: string; props?: any; children?: unknown[]; cells?: unknown[][]; tabs?: { content: unknown }[] };
      if (n.tag === "Widget") {
        if (n.name === "table" || n.name === "drilldownTable") {
          const args = hw.calls[call++]!;
          const columns: TableColumn[] = n.name === "table" ? n.props.columns : n.props.ddColumns;
          const relRaw = n.name === "table" ? n.props.rows : n.props.ddRows;
          const rel: InlineRelation = relRaw.kind === "inline" ? relRaw : tokens[relRaw.token]!;
          const rows: LegacyCell[][] = isTreeRows(args.relation)
            ? (args.relation as LegacyTreeRow[]).map((r) => r.content)
            : (args.relation as LegacyCell[][]);
          assert.equal(rows.length, rel.rows.length, "row count");
          for (const row of rows) {
            row.forEach((cell, c) => {
              const col = columns[c] as TableColumn;
              formatTags.add((col.cellFormat as CellFormat).tag);
              // `raw` IS a wire cell of that relation's column (or null when the
              // column names nothing in the relation)
              const at = rel.columns.findIndex((x) => x.name === col.column);
              assert.ok(at >= 0 || cell.raw === null, "a column with no relation column is null");
              // `formatted` is what format.ts answers on it
              assert.deepStrictEqual(cell.formatted,
                tabularCell(col.cellFormat as CellFormat, cell.raw, env).formatted);
              assert.deepStrictEqual(cell.format, legacyFormat(col.cellFormat as CellFormat));
              cells += 0;
            });
          }
          // every raw in a row came from the same relation row, in order
          rows.forEach((row, r) => {
            row.forEach((cell, c) => {
              const at = rel.columns.findIndex((x) => x.name === (columns[c] as TableColumn).column);
              const want = at < 0 ? null : (rel.rows[r]?.[at] ?? null);
              assert.deepStrictEqual(cell.raw, want, "raw equals the wire cell");
            });
          });
          kinds.add(relRaw.kind);
        } else if (n.name === "scorecard") {
          kinds.add(n.props.cards.kind);
          formatTags.add((n.props.cardFormat as CellFormat).tag);
        } else if (n.name === "axisChart") {
          const p = n.props as AxisChartProps<any>;
          const rel = resolve(p.chartRows);
          const { args } = hw.timeSeries[chartCall.ts++] as { args: any };
          assertMeta(args.meta, `${stem}: axisChart meta`);
          assert.equal(args.parentCol, null, `${stem}: a plain axis chart must not be a drilldown`);
          assert.equal(args.childCol, null);
          assert.equal(args.series.length, p.chartSeries.length);
          args.series.forEach((s: unknown, i: number) => {
            variants.add((s as { variant: string }).variant);
            chartPoints += assertSeries(s, p.chartSeries[i] as ChartSeries, rel, [], `${stem}: axisChart series[${i}]`);
          });
          kinds.add(p.chartRows.kind as string);
        } else if (n.name === "drilldownBar") {
          const p = n.props as DrilldownBarProps<any>;
          const rel = resolve(p.barRows);
          const { args } = hw.drilldownBars[chartCall.bar++] as { args: any };
          assertMeta(args.meta, `${stem}: drilldownBar meta`);
          // isDD needs BOTH, or runTimeSeries draws no breadcrumb at all
          assert.equal(args.parentCol, p.barParentColumn);
          assert.equal(args.childCol, p.barChildColumn);
          assert.equal(args.series.length, 1);
          variants.add(args.series[0].variant);
          chartPoints += assertSeries(args.series[0], p.barSeries, rel,
            [p.barChildColumn, p.barParentColumn], `${stem}: drilldownBar series`);
          kinds.add(p.barRows.kind as string);
        } else if (n.name === "pieChart" || n.name === "drilldownPieChart") {
          const p = n.props as PieChartProps<any>;
          const rel = resolve(p.pieRows);
          const { args } = (n.name === "pieChart"
            ? hw.pies[chartCall.pie++]
            : hw.drilldownPies[chartCall.ddPie++]) as { args: any };
          assertTuple(args.dataFmt, `${stem}: pie dataFmt`);
          assertTuple(args.labelFmt, `${stem}: pie labelFmt`);
          assert.equal(args.legendOptions.type, "ChartLegendOptions");
          assert.ok(LEGEND_LOCATIONS.includes(args.legendOptions.location));
          assert.equal(args.parentCol, p.pieParentColumn ?? null);
          assert.equal(args.childCol, p.pieChildColumn ?? null);
          const isDD = p.pieChildColumn !== undefined || p.pieParentColumn !== undefined;
          assert.equal(args.relation.length, rel.rows.length);
          const vAt = rel.columns.findIndex((c) => c.name === p.pieValueColumn);
          const lAt = rel.columns.findIndex((c) => c.name === p.pieLabelColumn);
          const labelFmt = formatDisplay(p.pieLabelFormat as CellFormat, env);
          args.relation.forEach((row: unknown[], r: number) => {
            assert.equal(row.length, isDD ? 5 : 3, `${stem}: pie row width`);
            // position 0 is the label FORMATTED and stringified -- the server
            // builds it as `lc.format.basicEval(labels) extractNullableString ""`
            // (RelationRunner.scala:240), and nothing in the bundle formats
            // `this.name` again, so it must be right here or not at all
            assert.equal(typeof row[0], "string", `${stem}: pie label is not a string`);
            const rawLabel = lAt < 0 ? null : ((rel.rows[r] as unknown[])[lAt] ?? null);
            assert.equal(row[0], String(labelFmt([rawLabel]) ?? ""), `${stem}: pie label`);
            // pie values are ABSOLUTE (processPieData sorts by -y)
            const v = row[1] as number;
            assert.equal(typeof v, "number");
            assert.ok(Number.isFinite(v) && v >= 0, `${stem}: pie value ${v}`);
            if (vAt >= 0) {
              const wire = Number((rel.rows[r] as unknown[])[vAt]);
              assert.equal(v, Math.abs(Number.isFinite(wire) ? wire : 0), `${stem}: |value|`);
            }
            const colour = row[2];
            assert.ok(colour === null || (typeof colour === "string" && CSS_COLOR.test(colour)),
              `${stem}: pie colour ${JSON.stringify(colour)}`);
          });
          pieSlices += args.relation.length;
          kinds.add(p.pieRows.kind as string);
        } else if (n.name === "styleBox") {
          const p = n.props as StyleBoxProps<any>;
          const rel = resolve(p.styleBoxRows);
          const { args } = hw.styleBoxes[chartCall.sb++] as { args: any };
          assertTuple(args.aFormat, `${stem}: styleBox aFormat`);
          assert.equal(args.aField, p.aggColumn);
          // the two f0 handles whose only consumer is the styleBoxData POST
          assert.equal(args.relation, null);
          assert.equal(args.legend, null);
          assert.ok(args.showNumber === "showNumber" || args.showNumber === "hiddenNumber");
          assert.equal(typeof args.cellCounts, "string", `${stem}: cellCounts is JSON in a STRING`);
          const cells2 = JSON.parse(args.cellCounts) as Record<string, number | string>[];
          const xAt = rel.columns.findIndex((c) => c.name === p.xPositionColumn);
          const yAt = rel.columns.findIndex((c) => c.name === p.yPositionColumn);
          const aAt = rel.columns.findIndex((c) => c.name === p.aggColumn);
          // one entry per distinct (x, y), each the SUM the server aggregates
          const want = new Map<string, number>();
          for (const row of rel.rows as unknown[][]) {
            const k = `${row[xAt]} ${row[yAt]}`;
            want.set(k, (want.get(k) ?? 0) + Number(row[aAt]));
          }
          assert.equal(cells2.length, want.size, `${stem}: cellCounts group count`);
          for (const c of cells2) {
            assert.equal(typeof c["xPosition"], "number");
            assert.equal(typeof c["yPosition"], "number");
            assert.equal(typeof c["styleBoxAggFormatted"], "string");
            const k = `${c["xPosition"]} ${c["yPosition"]}`;
            assert.ok(Math.abs((c[p.aggColumn] as number) - (want.get(k) as number)) < 1e-9,
              `${stem}: ${k} summed to ${String(c[p.aggColumn])}, want ${String(want.get(k))}`);
          }
          styleBoxCellCount += cells2.length;
          kinds.add(p.styleBoxRows.kind as string);
        }
        return;
      }
      if (n.children) n.children.forEach(walk);
      if (n.cells) n.cells.forEach((r) => r.forEach(walk));
      if (n.tabs) n.tabs.forEach((tb) => walk(tb.content));
    };
    walk(doc.root);
  }

  // DERIVED from the registry (Q25 round 1b), so a widget registered later cannot
  // be silently missing from this pin: every registered name must occur, minus the
  // two the WidgetCorpus generator does not draw (Layout.Widgets.Heading/Text,
  // which no generated case uses).  The literal list this replaced had gone stale
  // at crosstab/headline (J3g/J3i) and failed whenever target/widget-corpus existed.
  const NOT_IN_CORPUS = new Set(["heading", "text"]);
  assert.deepStrictEqual([...widgetNames].sort(),
    Object.keys(defaultRegistry()).filter((n) => !NOT_IN_CORPUS.has(n)).sort(),
    "every registered widget must occur in the corpus, and nothing else may");
  assert.deepStrictEqual([...kinds].sort(), ["deferred", "inline"]);
  assert.ok(tokensResolved > 0, "no deferred relation was ever resolved");
  // A vacuity floor near the measured count.  MEASURED 929 on the default corpus
  // (WidgetCorpus seed 5150, 200 documents) since J3g/J3i added headline/crosstab
  // cases, which reach no runTabular; the old floor of 1000 had gone stale with them.
  assert.ok(cells > 900, `only ${cells} cells were checked`);
  assert.ok(formatTags.size >= 12, `only ${formatTags.size} CellFormat cases occurred: ${[...formatTags]}`);
  assert.deepStrictEqual([...sortDirections].sort(), ["asc", "desc"],
    "both sort directions must occur, and nothing else may");
  // J3e: every ChartVariant must have been drawn, and the three data paths used
  assert.deepStrictEqual([...variants].sort(),
    ["Bar", "BoxAndWhiskers", "Bubble", "Line", "Scatter", "StackedArea", "StackedBar", "Step"],
    "every ChartVariant must occur, and nothing else may");
  assert.ok(chartPoints > 200, `only ${chartPoints} chart points`);
  assert.ok(pieSlices > 100, `only ${pieSlices} pie slices`);
  assert.ok(styleBoxCellCount > 50, `only ${styleBoxCellCount} style-box cells`);
  t.diagnostic(
    `${names.length} documents, ${widgets} widgets, ${cells} cells, ` +
    `${tokensResolved} deferred relations resolved, ${formatTags.size} CellFormat cases, ` +
    `sort directions ${[...sortDirections].sort().join("/")}; ` +
    `${chartPoints} chart points over ${variants.size} variants, ${pieSlices} pie slices, ` +
    `${styleBoxCellCount} style-box cells`);
});

test("(b-neg) one mutation of each corpus document is refused, with a path", async (t) => {
  const names = corpusNames();
  if (names.length === 0) { t.skip(MISSING); return; }
  assert.ok(names.length >= 100, `${names.length} documents in ${CORPUS}, want at least 100`);
  let seed = 7;
  const rand = (): number => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };
  let checked = 0;
  const kinds = new Set<string>();
  for (const stem of names) {
    const valid = JSON.parse(fs.readFileSync(path.join(CORPUS, `${stem}.json`), "utf8"));
    const m = mutateOnce(valid, rand);
    if (!m) continue;
    if (JSON.stringify(m.after) === JSON.stringify(valid)) continue;
    kinds.add(m.how);
    const parsed = safeParseDocument(m.after);
    if (!parsed.ok) {
      assert.ok(parsed.error.issues.length > 0);
      checked++;
      continue;
    }
    const { document, target } = newDom();
    const result = await render(target, parsed.document, defaultRegistry(), {
      document, htmlwriter: stubHtmlWriter(), fetchData: async () => { throw new Error("no fetch"); },
    });
    assert.ok(result.errors.length > 0,
      `${stem}: mutation ${m.how} at ${m.path.join(".")} was accepted`);
    assert.ok(target.querySelector(".ermine-widget-error"), `${stem}: no error box`);
    checked++;
  }
  assert.ok(checked >= 100, `only ${checked} mutants`);
  assert.deepStrictEqual([...kinds].sort(), ["add", "drop", "retype"]);
  t.diagnostic(`${checked} single mutations, all refused`);
});
