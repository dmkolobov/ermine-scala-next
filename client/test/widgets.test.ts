// The two legacy adapters and the new widget.

import { test } from "node:test";
import assert from "node:assert/strict";

import { parseDocument } from "../src/document";
import { render } from "../src/dispatcher";
import { defaultRegistry } from "../src/index";
import { legacyFormat, legacyFormatTuple, tableSkeleton, drilldownRows, tabularCell, NULL_DISPLAY } from "../src/legacy";
import { defaultFormatEnv, formatDisplay } from "../src/format";
import { newDom, stubHtmlWriter, inlineRelation } from "./harness";
import type { CellFormat } from "../src/props";
import { WIDGET_PROP_SCHEMAS } from "../src/generated";
import { refuseDeferred } from "../src/host/page";
import * as fs from "node:fs";
import * as path from "node:path";

const rel = inlineRelation(
  [{ name: "region", type: "String" }, { name: "sales", type: "Double", nullable: true }],
  [["EMEA", 120.55], ["APAC", null], ["AMER", -3]],
);

const roundOne: CellFormat = { tag: "Round", color: false, negParens: false, places: 1 };

const tableProps = {
  columns: [
    { column: "region", header: "Region", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "OtherColumn" },
    { column: "sales", header: "Sales", cellFormat: roundOne, align: "AlignRight", kind: "NumberColumn" },
    { column: "absent", header: "Gone", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "DateColumn" },
  ],
  rowGroup: 0,
  sorts: [{ sortColumn: 1, descending: true }],
  paginate: true,
  scroll: false,
  rows: rel,
};

function docOf(root: unknown): unknown {
  return { version: 1, settings: {}, root };
}

test("(w-table) the table adapter builds the skeleton and calls runTabular with the legacy arguments", async () => {
  const { document, target } = newDom();
  const hw = stubHtmlWriter();
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "table", props: tableProps })),
    defaultRegistry(), { document, fetchData: async () => rel, htmlwriter: hw });
  assert.deepStrictEqual(result.errors, []);

  // the DOM tableRegular emits server-side today
  const table = target.querySelector(".tabular_wrapper > table.tabular") as HTMLTableElement;
  assert.ok(table, "the tabular_wrapper / table.tabular skeleton");
  assert.match(table.id, /_tabular$/);
  assert.equal(table.querySelectorAll("thead th").length, 3);
  assert.equal(table.querySelectorAll("tbody tr td").length, 3);

  assert.equal(hw.calls.length, 1);
  const args = hw.calls[0]!;
  assert.equal(args.id, table.id);
  assert.deepStrictEqual(args.cols, ["Region", "Sales", "Gone"]);
  assert.deepStrictEqual(args.colAlignments, ["left", "right", "left"]);
  assert.deepStrictEqual(args.colType, ["other", "number", "date"]);
  assert.equal(args.rowgroupCol, 0);
  // `[index, "asc"|"desc"]`: DataTables builds its comparator's NAME out of that
  // second element (datatables.js:4019), so a boolean there is a TypeError
  assert.deepStrictEqual(args.sorts, [[1, "desc"]]);
  assert.equal(args.paginate, true);
  assert.equal(args.scroll, false);
  assert.equal(args.isDD, false);
  assert.equal(args.legend, null);

  // cells: rows x displayed columns, raw = the wire cell, formatted = format.ts
  const env = defaultFormatEnv(document);
  const cells = args.relation as { formatted: unknown; raw: unknown; format: { type: string } }[][];
  assert.equal(cells.length, rel.rows.length);
  cells.forEach((row, r) => {
    assert.equal(row.length, 3);
    row.forEach((cell, c) => {
      const colName = tableProps.columns[c]!.column;
      const at = rel.columns.findIndex((x) => x.name === colName);
      const raw = at < 0 ? null : rel.rows[r]![at]!;
      assert.deepStrictEqual(cell.raw, raw);
      assert.deepStrictEqual(cell.formatted,
        tabularCell(tableProps.columns[c]!.cellFormat as CellFormat, raw, env).formatted);
      assert.deepStrictEqual(cell.format, legacyFormat(tableProps.columns[c]!.cellFormat as CellFormat));
    });
  });
  // the null cell displays as the legacy "-", and the column that names no
  // relation column is all nulls rather than a crash
  assert.equal(cells[1]![1]!.formatted, NULL_DISPLAY);
  assert.equal(cells[0]![2]!.formatted, NULL_DISPLAY);
  assert.equal(cells[0]![1]!.formatted, "120.6");
});

test("(w-legacy-format) the object form is what the tabular sort key reads", () => {
  assert.deepStrictEqual(legacyFormat({ tag: "Markdown", base: { tag: "Default", args: [] } }),
    { type: "markdown", base: { type: "default" } });
  // the alias map is built with a NULL prototype, so a key of `__proto__` is
  // stored rather than silently swallowed by the prototype setter
  const alias = legacyFormat({ tag: "Alias", aliases: [["a", "b"], ["c", "d"], ["__proto__", "p"]] });
  assert.equal(alias["type"], "alias");
  assert.equal(Object.getPrototypeOf(alias["aliases"] as object), null);
  assert.deepStrictEqual(Object.entries(alias["aliases"] as object).sort(),
    [["__proto__", "p"], ["a", "b"], ["c", "d"]]);
  assert.deepStrictEqual(legacyFormat({ tag: "Conditional",
    condition: { tag: "And", and: [{ tag: "Gt", gt: { tag: "TNum", args: [1] } }, { tag: "Eq", eq: { tag: "TStr", args: ["x"] } }] },
    whenTrue: { tag: "Verbatim", args: [] }, whenFalse: { tag: "DateRange", args: [] } }),
    { type: "conditional", condition: { and: [{ gt: 1 }, { eq: "x" }] },
      then: { type: "verbatim" }, else: { type: "dateRange" } });
  assert.deepStrictEqual(legacyFormat({ tag: "Color", bg: { red: 1, green: 2, blue: 3 },
    fg: { red: 4, green: 5, blue: 6 }, base: { tag: "Default", args: [] } }),
    { type: "color", bg: [1, 2, 3], fg: [4, 5, 6], base: { type: "default" } });
  // the two lossy spots, kept lossy
  assert.deepStrictEqual(legacyFormat({ tag: "Round", color: true, negParens: true, places: 2 }),
    { type: "round", negParens: true, places: 2 });
  // and the tuple form the chart path uses
  assert.deepStrictEqual(legacyFormatTuple({ tag: "Percentage", color: true, negParens: true, places: 3, pad: false }),
    ["Percentage", [3, false]]);
  assert.deepStrictEqual(legacyFormatTuple({ tag: "Markdown", base: { tag: "Default", args: [] } }), ["MarkdownFmt", null]);
});

test("(w-drilldown) the drilldown adapter builds the tree the legacy TreeTabular sends", async () => {
  const tree = inlineRelation(
    [{ name: "id", type: "String" }, { name: "parent", type: "String" }, { name: "label", type: "String" }],
    [
      ["a", "", "root"],
      ["b", "a", "child of a"],
      ["c", "b", "grandchild"],
      ["d", "a", "second child"],
      ["e", "", "other root"],
    ],
  );
  const props = {
    ddColumns: [
      { column: "label", header: "Name", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "OtherColumn" },
    ],
    parentColumn: "parent",
    childColumn: "id",
    labelColumn: "label",
    ddSorts: [],
    ddPaginate: false,
    ddScroll: true,
    ddRows: tree,
  };
  const { document, target } = newDom();
  const hw = stubHtmlWriter();
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "drilldownTable", props })),
    defaultRegistry(), { document, fetchData: async () => tree, htmlwriter: hw });
  assert.deepStrictEqual(result.errors, []);
  const args = hw.calls[0]!;
  assert.equal(args.isDD, true);
  // the skeleton has the extra "+" column
  assert.equal(target.querySelectorAll("thead th").length, 2);
  const rows = args.relation as { indent: number; ix: number; content: { formatted: unknown }[] }[];
  assert.deepStrictEqual(rows.map((r) => [r.indent, r.content[0]!.formatted]), [
    [0, "root"], [1, "child of a"], [2, "grandchild"], [1, "second child"], [0, "other root"],
  ]);
  assert.deepStrictEqual(rows.map((r) => r.ix), [0, 1, 2, 3, 4]);
});

test("(w-drilldown-cycle) a cycle does not loop; its rows land at the end", () => {
  const cyc = inlineRelation(
    [{ name: "id", type: "String" }, { name: "parent", type: "String" }],
    [["x", "y"], ["y", "x"], ["z", ""]],
  );
  const rows = drilldownRows(
    { ddColumns: [{ column: "id", header: "Id", cellFormat: { tag: "Default", args: [] }, align: "AlignLeft", kind: "OtherColumn" }],
      parentColumn: "parent", childColumn: "id", labelColumn: "id",
      ddSorts: [], ddPaginate: false, ddScroll: false, ddRows: cyc },
    defaultFormatEnv(newDom().document),
  );
  assert.equal(rows.length, 3);
  assert.deepStrictEqual(rows.map((r) => r.content[0]!.raw), ["z", "x", "y"]);
});

test("(w-scorecard) the new widget's DOM, asserted directly", async () => {
  const { document, target } = newDom();
  const props = {
    title: "Sales by region",
    cardLabel: "region",
    cardValue: "sales",
    cardDelta: "sales",
    cardFormat: roundOne,
    cards: rel,
  };
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "scorecard", props })),
    defaultRegistry(), { document, fetchData: async () => rel, htmlwriter: undefined });
  assert.deepStrictEqual(result.errors, []);
  const section = target.querySelector("section.ermine-scorecard") as HTMLElement;
  assert.ok(section);
  assert.equal(section.querySelector(".ermine-scorecard-title")?.textContent, "Sales by region");
  const cards = Array.from(section.querySelectorAll(".ermine-scorecard-card"));
  assert.equal(cards.length, 3);
  assert.deepStrictEqual(cards.map((c) => c.querySelector(".ermine-scorecard-label")?.textContent),
    ["EMEA", "APAC", "AMER"]);
  assert.deepStrictEqual(cards.map((c) => c.querySelector(".ermine-scorecard-value")?.textContent),
    ["120.6", "—", "-3.0"]);
  assert.deepStrictEqual(cards.map((c) => c.querySelector(".ermine-scorecard-delta")?.getAttribute("data-direction")),
    ["up", "flat", "down"]);
  // no delta column named: no delta element
  const { document: d2, target: t2 } = newDom();
  const { cardDelta: _drop, ...noDelta } = props;
  await render(t2, parseDocument(docOf({ tag: "Widget", name: "scorecard", props: noDelta })),
    defaultRegistry(), { document: d2, fetchData: async () => rel });
  assert.equal(t2.querySelectorAll(".ermine-scorecard-delta").length, 0);
});

test("(w-headline) the headline's DOM: the count raw, the two measurements through the format", async () => {
  const { document, target } = newDom();
  const props = {
    headlineTitle: "Sales",
    scope: "in north",
    rowCount: 3,
    total: 4350.75,
    largest: 2310.25,
    headlineFormat: { tag: "Currency", color: false, negParens: false, symbol: "$", places: 2 },
  };
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "headline", props })),
    defaultRegistry(), { document, fetchData: async () => rel });
  assert.deepStrictEqual(result.errors, []);
  const section = target.querySelector("section.ermine-headline") as HTMLElement;
  assert.ok(section);
  assert.equal(section.querySelector(".ermine-headline-title")?.textContent, "Sales");
  assert.equal(section.querySelector(".ermine-headline-scope")?.textContent, "in north");
  const figures = Array.from(section.querySelectorAll(".ermine-headline-figure"));
  assert.deepStrictEqual(figures.map((f) => f.getAttribute("data-figure")), ["rowCount", "total", "largest"]);
  assert.deepStrictEqual(figures.map((f) => f.querySelector("dt")?.textContent), ["Rows", "Total", "Largest"]);
  const env = defaultFormatEnv(document);
  const fmt = formatDisplay(props.headlineFormat as CellFormat, env);
  // the count is printed as it arrives; the two measurements are formatted
  assert.deepStrictEqual(figures.map((f) => f.querySelector("dd")?.textContent),
    ["3", String(fmt([props.total])), String(fmt([props.largest]))]);
  // ...and the format is the one that was sent: a plain String() of the numbers is not it
  assert.notDeepStrictEqual(figures.map((f) => f.querySelector("dd")?.textContent),
    ["3", String(props.total), String(props.largest)]);
});

test("(w-crosstab) a 2x3 matrix with a gap: the header row, the row labels, the formatted cells and the em dash", async () => {
  const { document, target } = newDom();
  const props = {
    crosstabTitle: "Sales by region and month",
    rowHeader: "Region",
    colHeader: "Month",
    crosstabRowLabels: ["north", "south"],
    crosstabColLabels: ["2026-01", "2026-02", "2026-03"],
    // south sold nothing in March: a pair NO ROW HAD, which is not a zero
    cells: [[2040.5, 2310.25, 1000], [615.75, 1990, null]],
    rowTotals: [5350.75, 2605.75],
    colTotals: [2656.25, 4300.25, 1000],
    grandTotal: 7956.5,
    crosstabFormat: { tag: "Currency", color: false, negParens: false, symbol: "$", places: 2 },
  };
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "crosstab", props })),
    defaultRegistry(), { document, fetchData: async () => rel });
  assert.deepStrictEqual(result.errors, []);

  const section = target.querySelector("section.ermine-crosstab") as HTMLElement;
  assert.ok(section);
  assert.equal(section.querySelector(".ermine-crosstab-title")?.textContent, "Sales by region and month");
  // the corner cell says what each axis is
  assert.equal(section.querySelector(".ermine-crosstab-row-header")?.textContent, "Region");
  assert.equal(section.querySelector(".ermine-crosstab-col-header")?.textContent, "Month");
  // the header row: the corner, one <th> per column label, and the totals column
  assert.deepStrictEqual(
    Array.from(section.querySelectorAll("thead th")).slice(1).map((th) => th.textContent),
    ["2026-01", "2026-02", "2026-03", "Total"]);

  const env = defaultFormatEnv(document);
  const fmt = formatDisplay(props.crosstabFormat as CellFormat, env);
  const bodyRows = Array.from(section.querySelectorAll("tbody tr"));
  assert.deepStrictEqual(bodyRows.map((tr) => tr.querySelector("th")?.textContent), ["north", "south"]);
  // every cell through crosstabFormat, the missing pair as an em dash
  assert.deepStrictEqual(
    bodyRows.map((tr) => Array.from(tr.querySelectorAll("td")).map((td) => td.textContent)),
    [[String(fmt([2040.5])), String(fmt([2310.25])), String(fmt([1000])), String(fmt([5350.75]))],
     [String(fmt([615.75])), String(fmt([1990])), "—", String(fmt([2605.75]))]]);
  // ...and the format is the one that was sent: String() of the numbers is not it
  assert.notEqual(bodyRows[0]!.querySelectorAll("td")[0]!.textContent, String(2040.5));
  // only the missing pair is marked empty
  assert.equal(section.querySelectorAll("td.ermine-crosstab-empty").length, 1);
  assert.equal(section.querySelector("td.ermine-crosstab-empty")?.textContent, "—");
  // the totals row
  assert.deepStrictEqual(
    Array.from(section.querySelectorAll("tfoot td")).map((td) => td.textContent),
    [String(fmt([2656.25])), String(fmt([4300.25])), String(fmt([1000])), String(fmt([7956.5]))]);
  assert.equal(section.querySelector("tfoot th")?.textContent, "Total");
  assert.equal(section.querySelector(".ermine-crosstab-no-rows"), null);
});

test("(w-crosstab-empty) a scan that found no rows is two empty axes and no grid", async () => {
  const { document, target } = newDom();
  const props = {
    crosstabTitle: "Sales", rowHeader: "Region", colHeader: "Month",
    crosstabRowLabels: [], crosstabColLabels: [], cells: [],
    rowTotals: [], colTotals: [], grandTotal: 0,
    crosstabFormat: { tag: "Default", args: [] },
  };
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "crosstab", props })),
    defaultRegistry(), { document, fetchData: async () => rel });
  assert.deepStrictEqual(result.errors, []);
  const section = target.querySelector("section.ermine-crosstab") as HTMLElement;
  assert.equal(section.querySelectorAll("tbody tr").length, 0);
  assert.equal(section.querySelector(".ermine-crosstab-no-rows")?.textContent, "no rows");
});

test("(w-sorts) both sort directions reach runTabular as the strings DataTables names its comparator with", async () => {
  for (const [descending, want] of [[true, "desc"], [false, "asc"]] as const) {
    const { document, target } = newDom();
    const hw = stubHtmlWriter();
    const props = { ...tableProps, sorts: [{ sortColumn: 0, descending }, { sortColumn: 2, descending: !descending }] };
    await render(target, parseDocument(docOf({ tag: "Widget", name: "table", props })),
      defaultRegistry(), { document, fetchData: async () => rel, htmlwriter: hw });
    const other = want === "desc" ? "asc" : "desc";
    assert.deepStrictEqual(hw.calls[0]!.sorts, [[0, want], [2, other]]);
    // and the drilldown, whose sorts field is its own
    const { document: d2, target: t2 } = newDom();
    const hw2 = stubHtmlWriter();
    const dd = {
      ddColumns: tableProps.columns.slice(0, 1),
      parentColumn: "region", childColumn: "region", labelColumn: "region",
      ddSorts: [{ sortColumn: 0, descending }], ddPaginate: false, ddScroll: false, ddRows: rel,
    };
    await render(t2, parseDocument(docOf({ tag: "Widget", name: "drilldownTable", props: dd })),
      defaultRegistry(), { document: d2, fetchData: async () => rel, htmlwriter: hw2 });
    assert.deepStrictEqual(hw2.calls[0]!.sorts, [[0, want]]);
  }
});

test("(w-skeleton) the table skeleton for a drilldown carries the extra + column", () => {
  const { document } = newDom();
  const el = tableSkeleton(document, "t1_tabular", ["A", "B"], true);
  assert.equal(el.className, "tabular_wrapper");
  const ths = Array.from(el.querySelectorAll("th"));
  assert.deepStrictEqual(ths.map((th) => th.textContent), ["+", "A", "B"]);
  assert.equal(el.querySelectorAll("tbody td").length, 3);
  assert.equal(el.querySelectorAll("th .sticky").length, 2);
});

test("(w-no-writer) the missing-writer box names the REAL global and its DOMContentLoaded timing", async () => {
  // WP-9 / Q1.  `client/src/index.ts` documented `window.htmlwriter`; the
  // writers entry assigns `window.ermine_htmlwriter`, and only inside a
  // `DOMContentLoaded` listener (`ermine-writers/writers/js/htmlwriter.js:10-13`,
  // READ).  The LOOKUP was never wrong -- it is `ctx.env.htmlwriter`, an env key
  // the HOST fills -- so this pins the one thing that did change: the text a
  // developer reads out of the error box when the host read the global too early.
  const { document, target } = newDom();
  const result = await render(target, parseDocument(docOf({ tag: "Widget", name: "table", props: tableProps })),
    defaultRegistry(), { document, fetchData: async () => rel, htmlwriter: undefined });
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0]!.message, /window\.ermine_htmlwriter/);
  assert.match(result.errors[0]!.message, /DOMContentLoaded/);
  assert.ok(target.querySelector(".ermine-widget-error"));
});

// ------------------------------------------ Q24 (d): `heading` and `text`
//
// The two names `core/src/test/resources/doc/Sales.e` uses that are not typed
// `Layout.Widgets.*` modules.  Their props are taken from the REAL answer the
// extension's fixture holds (CAPTURED from one `bin/ermine-lsp` boot, WP-10 S1),
// never written by hand here.

function findPanelAnswers(): string {
  let dir = __dirname;
  for (let i = 0; i < 6; i++) {
    const p = path.join(dir, "editor", "vscode", "test", "fixtures", "panel-answers.json");
    if (fs.existsSync(p)) return p;
    dir = path.dirname(dir);
  }
  throw new Error("editor/vscode/test/fixtures/panel-answers.json not found above " + __dirname);
}

const SALES_DOC = (JSON.parse(fs.readFileSync(findPanelAnswers(), "utf8")) as
  { cases: Record<string, { answer: { document: { root: { children: unknown[] } } } }> })
  .cases["ok-sales"]!.answer.document;
const SALES_HEADING = SALES_DOC.root.children[0] as { tag: string; name: string; props: Record<string, unknown> };
const SALES_TEXT = ((SALES_DOC.root.children[1] as { cells: unknown[][] }).cells[1]![1]) as
  { tag: string; name: string; props: unknown };

test("(w-heading) the captured Sales heading draws: title, matched, total, sort column", async () => {
  assert.equal(SALES_HEADING.name, "heading");
  assert.deepStrictEqual(Object.keys(SALES_HEADING.props).sort(), ["matched", "sortColumn", "title", "total"]);
  const { document, target } = newDom();
  const result = await render(target, parseDocument(docOf(SALES_HEADING)), defaultRegistry(),
    { document, fetchData: refuseDeferred });
  assert.deepStrictEqual(result.errors, []);
  const section = target.querySelector("section.ermine-heading") as HTMLElement;
  assert.ok(section);
  assert.equal(section.querySelector("h2.ermine-heading-title")?.textContent, "Sales");
  assert.equal(section.querySelector(".ermine-heading-summary")?.textContent,
    "3 matched, total 4350.75, sorted by amount");
  assert.equal(target.querySelectorAll(".ermine-widget-error").length, 0);
});

test("(w-text) the captured Sales text widget -- a BARE string on the wire -- draws as a paragraph", async () => {
  assert.equal(SALES_TEXT.name, "text");
  assert.equal(SALES_TEXT.props, "line items on demand");
  const { document, target } = newDom();
  const result = await render(target, parseDocument(docOf(SALES_TEXT)), defaultRegistry(),
    { document, fetchData: refuseDeferred });
  assert.deepStrictEqual(result.errors, []);
  assert.equal(target.querySelector("p.ermine-text")?.textContent, "line items on demand");
});

test("(w-heading-text-escape) markup in the props is TEXT, never parsed", async () => {
  const evil = "<img src=x onerror=\"window.pwned=1\"><b>bold</b>";
  const { document, target } = newDom();
  const result = await render(target, parseDocument(docOf({ tag: "VFlow", children: [
    { tag: "Widget", name: "heading", props: { ...SALES_HEADING.props, title: evil, sortColumn: evil } },
    { tag: "Widget", name: "text", props: evil },
  ] })), defaultRegistry(), { document, fetchData: refuseDeferred });
  assert.deepStrictEqual(result.errors, []);
  assert.equal(target.querySelectorAll("img").length, 0, "an <img> was parsed out of the props");
  assert.equal(target.querySelectorAll("b").length, 0, "a <b> was parsed out of the props");
  assert.equal(target.querySelector(".ermine-heading-title")?.textContent, evil);
  assert.equal(target.querySelector(".ermine-heading-sort")?.textContent, `sorted by ${evil}`);
  assert.equal(target.querySelector(".ermine-text")?.textContent, evil);
});

test("(w-heading-text-invalid) malformed props draw the error box naming the widget", async () => {
  const bad: [string, unknown, RegExp][] = [
    ["heading", { ...SALES_HEADING.props, title: 7 }, /props are invalid -- title: Expected string/],
    ["heading", { ...SALES_HEADING.props, matched: 1.5 }, /props are invalid -- matched/],
    ["heading", { title: "Sales", sortColumn: "day", matched: 1 }, /props are invalid -- total: Required/],
    ["heading", { ...SALES_HEADING.props, extra: 1 }, /props are invalid/],   // strict, as the generated schemas are
    ["heading", "Sales", /props are invalid/],
    ["text", 42, /props are invalid/],
    ["text", { text: "line items on demand" }, /props are invalid/],        // the wire carries a bare string
    ["text", null, /props are invalid/],
  ];
  for (const [name, props, why] of bad) {
    const { document, target } = newDom();
    const result = await render(target, parseDocument(docOf({ tag: "Widget", name, props })), defaultRegistry(),
      { document, fetchData: refuseDeferred });
    assert.equal(result.errors.length, 1, `${name} ${JSON.stringify(props)} was accepted`);
    assert.match(result.errors[0]!.message, why, `${name} ${JSON.stringify(props)}`);
    const box = target.querySelector(".ermine-widget-error");
    assert.equal(box?.getAttribute("data-widget"), name);
    assert.equal(target.querySelectorAll(".ermine-heading, .ermine-text").length, 0);
  }
});

test("(w-own-schema) every registered name has EXACTLY ONE schema: generated, or its own; heading and text are the own ones", () => {
  const reg = defaultRegistry() as Record<string, { schema?: unknown }>;
  const own: string[] = [];
  for (const [name, w] of Object.entries(reg)) {
    const generated = WIDGET_PROP_SCHEMAS[name] !== undefined;
    const mine = w.schema !== undefined;
    assert.ok(generated !== mine, `${name}: generated=${generated} own=${mine}`);
    if (mine) own.push(name);
  }
  assert.deepStrictEqual(own.sort(), ["heading", "text"]);
  assert.deepStrictEqual(Object.keys(reg).sort(),
    [...Object.keys(WIDGET_PROP_SCHEMAS), "heading", "text"].sort());
});

test("(w-sales-panel) the captured Sales document with the panel's refusing fetchData: heading and text draw, the three tables are boxes", async () => {
  const { document, target } = newDom();
  const result = await render(target, parseDocument(SALES_DOC), defaultRegistry(),
    { document, fetchData: refuseDeferred, htmlwriter: stubHtmlWriter() });
  assert.equal(target.querySelector(".ermine-heading-title")?.textContent, "Sales");
  assert.equal(target.querySelector(".ermine-text")?.textContent, "line items on demand");
  // MEASURED, Q24: Sales hands `table` a BARE relation, not TableProps, so all
  // three tables -- the deferred one included -- fail VALIDATION, which comes
  // before any fetch: the page's refusal is never reached for this document.
  assert.deepStrictEqual(result.errors.map((e) => [e.widget, e.path, e.message]), [
    ["table", "$.root.children[1].cells[0][0]", "its props are invalid -- columns.0.column: Required"],
    ["table", "$.root.children[1].cells[0][1]", "its props are invalid -- columns.0.column: Required"],
    ["table", "$.root.children[1].cells[1][0]", "its props are invalid -- columns.0.column: Required"],
  ]);
  assert.equal(target.querySelectorAll(".ermine-widget-error").length, 3);
});
