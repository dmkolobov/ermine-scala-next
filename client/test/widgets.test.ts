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
