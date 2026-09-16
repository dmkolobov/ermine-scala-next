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
import { defaultFormatEnv } from "../src/format";
import { InlineRelationSchema, type InlineRelation } from "../src/relation";
import type { CellFormat, TableColumn } from "../src/props";
import { newDom, stubHtmlWriter } from "./harness";
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

    // ---- raw / formatted / format, against the props the document carried
    const doc = parseDocument(JSON.parse(text));
    let call = 0;
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
        }
        return;
      }
      if (n.children) n.children.forEach(walk);
      if (n.cells) n.cells.forEach((r) => r.forEach(walk));
      if (n.tabs) n.tabs.forEach((tb) => walk(tb.content));
    };
    walk(doc.root);
  }

  assert.deepStrictEqual([...widgetNames].sort(), ["drilldownTable", "scorecard", "table"]);
  assert.deepStrictEqual([...kinds].sort(), ["deferred", "inline"]);
  assert.ok(tokensResolved > 0, "no deferred relation was ever resolved");
  assert.ok(cells > 1000, `only ${cells} cells were checked`);
  assert.ok(formatTags.size >= 12, `only ${formatTags.size} CellFormat cases occurred: ${[...formatTags]}`);
  assert.deepStrictEqual([...sortDirections].sort(), ["asc", "desc"],
    "both sort directions must occur, and nothing else may");
  t.diagnostic(
    `${names.length} documents, ${widgets} widgets, ${cells} cells, ` +
    `${tokensResolved} deferred relations resolved, ${formatTags.size} CellFormat cases, ` +
    `sort directions ${[...sortDirections].sort().join("/")}`);
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
