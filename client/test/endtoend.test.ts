// End to end: an Ermine report module (core/src/test/resources/modules/Doc/
// SalesReport.e) -> Write.doc on a SQLite in-memory connection -> this client.
//
//   sbt -batch 'core/Test/runMain com.clarifi.reporting.SalesReportDoc <file>'
//   ERMINE_REPORT_DOC=<file> node --test "dist/test/*.test.js"
//
// The table half is asserted through the stub htmlwriter's recorded runTabular
// call; the scorecard's DOM is asserted directly, since nothing legacy is behind
// it.  Row ORDER is not asserted: the relation carries no order, and the SQL scan
// is free to answer the rows in any order (report-J3b.md).

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as path from "path";

import { parseDocument } from "../src/document";
import { render } from "../src/dispatcher";
import { defaultRegistry } from "../src/index";
import { newDom, stubHtmlWriter } from "./harness";

// dist/test -> client -> the repo root, as client/scripts/check-corpus.sh writes it
const DOC = process.env.ERMINE_REPORT_DOC ?? path.resolve(__dirname, "../../../target/sales-report.json");

test("(e2e) Doc.SalesReport renders its scorecard and its table", async (t) => {
  if (!fs.existsSync(DOC)) {
    t.skip(`no document at ${DOC} -- run client/scripts/check-corpus.sh, or ` +
      `sbt 'core/Test/runMain com.clarifi.reporting.SalesReportDoc ${DOC}'`);
    return;
  }
  const doc = parseDocument(fs.readFileSync(DOC, "utf8"));
  assert.equal(doc.version, 1);
  assert.deepStrictEqual(doc.settings, {});

  const { document, target } = newDom();
  const hw = stubHtmlWriter();
  const result = await render(target, doc, defaultRegistry(), {
    document,
    htmlwriter: hw,
    fetchData: async (t) => { throw new Error(`nothing should be deferred here (${t})`); },
  });
  assert.deepStrictEqual(result.errors, []);

  // ---- the scorecard, asserted as DOM
  const section = target.querySelector("section.ermine-scorecard") as HTMLElement;
  assert.ok(section, "the scorecard rendered");
  assert.equal(section.querySelector(".ermine-scorecard-title")?.textContent, "Sales by region");
  const cards = Array.from(section.querySelectorAll(".ermine-scorecard-card"));
  assert.equal(cards.length, 3);
  const byLabel = new Map(cards.map((c) => [
    c.querySelector(".ermine-scorecard-label")?.textContent ?? "",
    {
      value: c.querySelector(".ermine-scorecard-value")?.textContent ?? "",
      delta: c.querySelector(".ermine-scorecard-delta")?.textContent ?? "",
      direction: c.querySelector(".ermine-scorecard-delta")?.getAttribute("data-direction") ?? "",
    },
  ]));
  assert.deepStrictEqual([...byLabel.keys()].sort(), ["AMER", "APAC", "EMEA"]);
  // Round 1 through the port: 120.5 -> "120.5", 0.125 -> "0.1", -0.04 -> "-0.0"
  assert.deepStrictEqual(byLabel.get("EMEA"), { value: "120.5", delta: "0.1", direction: "up" });
  assert.deepStrictEqual(byLabel.get("APAC"), { value: "98.3", delta: "-0.0", direction: "down" });
  assert.deepStrictEqual(byLabel.get("AMER"), { value: "310.8", delta: "0.5", direction: "up" });

  // ---- the table, asserted through the legacy interface
  assert.equal(hw.calls.length, 1);
  const args = hw.calls[0]!;
  assert.deepStrictEqual(args.cols, ["Region", "Sales", "Change"]);
  assert.deepStrictEqual(args.colAlignments, ["left", "right", "right"]);
  assert.deepStrictEqual(args.colType, ["other", "number", "number"]);
  assert.deepStrictEqual(args.sorts, [[1, "desc"]]);   // a string, not a boolean
  assert.equal(args.isDD, false);
  assert.equal(args.paginate, true);
  assert.equal(args.scroll, true);
  assert.ok(target.querySelector(`#${args.id}`), "the table skeleton is in the tree");

  const rows = args.relation as { formatted: unknown; raw: unknown; format: { type: string } }[][];
  assert.equal(rows.length, 3);
  const cells = new Map(rows.map((r) => [String(r[0]!.raw), r]));
  assert.deepStrictEqual(cells.get("EMEA")!.map((c) => c.formatted), ["EMEA", "$120.5", "12.5%"]);
  assert.deepStrictEqual(cells.get("APAC")!.map((c) => c.formatted), ["APAC", "$98.25", "(4%)"]);
  assert.deepStrictEqual(cells.get("AMER")!.map((c) => c.formatted), ["AMER", "$310.75", "50%"]);
  assert.deepStrictEqual(rows[0]!.map((c) => c.format.type), ["default", "currency", "percentage"]);

  // ---- J3e: the axis chart and the pie, over the SAME relation
  assert.equal(hw.timeSeries.length, 1);
  const chart = hw.timeSeries[0]!.args;
  assert.equal(chart.meta.title, "Sales by region");
  assert.deepStrictEqual(chart.meta.range.format, ["Round", 1]);
  assert.deepStrictEqual(chart.meta.range.constraints,
    { scaled: true, lowerBound: 0, upperBound: null, displayScale: "Linear" });
  assert.equal(chart.meta.legendOptions.location, "Above");
  assert.equal(chart.series.length, 1);
  assert.equal(chart.series[0]!.variant, "Bar");
  assert.deepStrictEqual(chart.series[0]!.fmtSeries, ["Constant", "Sales"]);
  // one point per relation row: [[value], [category], [""], null]
  const points = new Map(
    chart.series[0]!.data.map((r) => [String((r as unknown[][])[1]![0]), r as unknown[]]));
  assert.deepStrictEqual([...points.keys()].sort(), ["AMER", "APAC", "EMEA"]);
  assert.deepStrictEqual(points.get("EMEA"), [[120.5], ["EMEA"], [""], null]);
  assert.deepStrictEqual(points.get("AMER"), [[310.75], ["AMER"], [""], null]);

  assert.equal(hw.pies.length, 1);
  const pie = hw.pies[0]!.args;
  assert.equal(pie.title, "Share of sales");
  assert.equal(pie.seriesName, "Sales");
  assert.equal(pie.legendOptions.location, "RightTable");
  assert.equal(pie.renderHints.enableDataLabels, true);
  assert.deepStrictEqual(pie.dataFmt, ["Round", 1]);
  assert.equal(pie.parentCol, null);
  assert.equal(pie.childCol, null);
  const slices = new Map(pie.relation.map((r) => [String((r as unknown[])[0]), r as unknown[]]));
  assert.deepStrictEqual([...slices.keys()].sort(), ["AMER", "APAC", "EMEA"]);
  assert.deepStrictEqual(slices.get("APAC"), ["APAC", 98.25, null]);
});
