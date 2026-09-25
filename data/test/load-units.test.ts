// Loader units: the FK-order sort, the BULK INSERT builder, the manifest
// comparisons and the streaming CSV reader (tracker/db/LOADER.md §6).
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { loadContract } from "../src/contract.js";
import { line } from "../src/lib/csv.js";
import { fkOrder, respectsFks } from "../src/load/order.js";
import { bracket, bulkInsertSql, nstring, rowsAffected } from "../src/load/bulk.js";
import { checkFiles, compareCounts, staleReason, type Manifest } from "../src/load/manifest.js";
import { CsvReader, parseAll } from "../src/load/csvstream.js";
import { Digest } from "../src/load/canon.js";

const sales = loadContract("sales");

test("fk order: the sales contract sorts parents first and agrees with its loadOrder", () => {
  const order = fkOrder(sales.tables);
  assert.equal(respectsFks(order, sales.tables), null);
  assert.equal(respectsFks(sales.loadOrder, sales.tables), null);
  assert.deepEqual([...order].sort(), [...sales.loadOrder].sort());
  const pos = (n: string) => order.indexOf(n);
  assert.ok(pos("dim_region") < pos("dim_rep") && pos("dim_rep") < pos("fact_order_line"));
  assert.ok(pos("dim_date") < pos("fact_order_line") && pos("dim_region") < pos("fact_target"));
});

test("fk order: ties keep contract order, self-references are ignored, cycles and unknown parents throw", () => {
  const t = (name: string, ...refs: string[]) => ({ name, fks: refs.map((ref) => ({ ref })) });
  assert.deepEqual(fkOrder([t("c", "a", "b"), t("b", "a"), t("a"), t("d")]), ["a", "b", "c", "d"]);
  assert.deepEqual(fkOrder([t("emp", "emp", "dept"), t("dept")]), ["dept", "emp"]);
  assert.throws(() => fkOrder([t("x", "y"), t("y", "x")]), /cycle among x, y/);
  assert.throws(() => fkOrder([t("x", "nope")]), /unknown table nope/);
  assert.match(respectsFks(["b", "a"], [t("a"), t("b", "a")]) ?? "", /b comes before its parent a/);
});

test("bulk: the statement names the table in brackets and carries every option", () => {
  const s = bulkInsertSql({ database: "ErmineSales", schema: "dbo", table: "dim_rep", file: "/load/sales/dim_rep.csv", keepNulls: true });
  assert.equal(s, "BULK INSERT [ErmineSales].[dbo].[dim_rep] FROM N'/load/sales/dim_rep.csv' WITH (FORMAT = 'CSV', DATAFILETYPE = 'widechar', "
    + "FIELDQUOTE = '\"', FIELDTERMINATOR = ',', ROWTERMINATOR = '\\n', FIRSTROW = 2, TABLOCK, CHECK_CONSTRAINTS, MAXERRORS = 0, KEEPNULLS);");
  const noNull = bulkInsertSql({ database: "D", schema: "dbo", table: "t", file: "/load/x.csv", keepNulls: false });
  assert.ok(!noNull.includes("KEEPNULLS"));
  assert.ok(!/CODEPAGE/.test(s), "CODEPAGE is refused on Linux (Msg 16202)");
});

test("bulk: quoting doubles ] and ', and refuses newlines and sqlcmd $( variables", () => {
  assert.equal(bracket("we]ird"), "[we]]ird]");
  assert.equal(nstring("/load/o'brien.csv"), "N'/load/o''brien.csv'");
  assert.throws(() => bracket("a\nb"), /bad identifier/);
  assert.throws(() => nstring("/load/$(x).csv"), /\$\(/);
  assert.throws(() => bracket(""), /bad identifier/);
});

test("bulk: rows affected are summed from sqlcmd output, null when absent", () => {
  assert.equal(rowsAffected("\n(4 rows affected)\n"), 4);
  assert.equal(rowsAffected("(1 row affected)\n(2 rows affected)"), 3);
  assert.equal(rowsAffected("(1,000 rows affected)\n"), 1000);
  assert.equal(rowsAffected("(2,000,000 rows affected)"), 2000000);
  assert.equal(rowsAffected("Msg 4864, Level 16"), null);
});

const man = (tables: Record<string, number>): Manifest => ({
  generator: "t", domain: "d", database: "D", tier: "s", seed: 42, factRows: 0, dateRange: "", contractVersion: 1, contractSha256: "c",
  tables: Object.fromEntries(Object.entries(tables).map(([k, rows]) => [k, { file: `${k}.csv`, rows, bytes: 0, sha256: "" }])),
});

test("manifest: counts equal, differ, or are missing on either side", () => {
  const r = compareCounts(man({ a: 3, b: 5 }), { a: 3, b: 4, c: 1 });
  assert.deepEqual(r.map((x) => [x.table, x.ok]), [["a", true], ["b", false], ["c", false]]);
  assert.deepEqual(compareCounts(man({ a: 1 }), {}, ["a"]), [{ table: "a", expected: 1, actual: null, ok: false }]);
});

test("manifest: a directory is stale on tier, seed (not at xs) or contract change", () => {
  const m = man({});
  assert.equal(staleReason(m, "s", 42, "c"), null);
  assert.match(staleReason(m, "s", 7, "c")!, /seed 42, asked 7/);
  assert.match(staleReason(m, "m", 42, "c")!, /tier s/);
  assert.match(staleReason(m, "s", 42, "other")!, /contract changed/);
  assert.equal(staleReason({ ...m, tier: "xs", seed: null }, "xs", 99, "c"), null);
  assert.equal(staleReason(null, "s", 42, "c"), "no manifest");
});

test("manifest: checkFiles catches a missing, resized or altered CSV", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ermine-load-test-"));
  try {
    const body = "id\n1\n";
    writeFileSync(join(dir, "a.csv"), body); writeFileSync(join(dir, "b.csv"), body); writeFileSync(join(dir, "c.csv"), "id\n2\n");
    const sha = createHash("sha256").update(body).digest("hex");
    const m = man({});
    m.tables = { a: { file: "a.csv", rows: 1, bytes: 5, sha256: sha }, b: { file: "b.csv", rows: 1, bytes: 6, sha256: sha },
      c: { file: "c.csv", rows: 1, bytes: 5, sha256: sha }, d: { file: "d.csv", rows: 1, bytes: 5, sha256: sha } };
    const bad = await checkFiles(dir, m);
    assert.equal(bad.length, 3);
    assert.match(bad.join(";"), /b: 5 bytes, manifest says 6/);
    assert.match(bad.join(";"), /c: sha256/);
    assert.match(bad.join(";"), /d: d.csv missing/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("csv reader: every chunk split gives the same rows as one piece (quotes, NULL vs \"\", LF in quotes, UTF-8)", () => {
  const text = line([1, "a,b \"q\"", null, ""]) + line([2, "x\ny", "Zoë 中文", " lead"]) + line([3, null, null, "t"]);
  const whole = parseAll(text);
  assert.deepEqual(whole, [["1", 'a,b "q"', null, ""], ["2", "x\ny", "Zoë 中文", " lead"], ["3", null, null, "t"]]);
  for (let i = 1; i < text.length; i++) {
    const r = new CsvReader();
    assert.deepEqual([...r.push(text.slice(0, i)), ...r.push(text.slice(i)), ...r.end()], whole, `split at ${i}`);
  }
  assert.throws(() => parseAll('a,"b\n'), /unterminated/);
  assert.throws(() => parseAll("a\r\n"), /CR/);
});

test("canonical digest: row order does not matter, a 1-ulp float or a NULL-vs-empty change does", () => {
  const cols = [{ name: "i", ermine: "Int" }, { name: "f", ermine: "Double" }, { name: "s", ermine: "Nullable String" }, { name: "d", ermine: "Date" }];
  const a = new Digest(cols), b = new Digest(cols), c = new Digest(cols), e = new Digest(cols);
  a.add(["1", "0.1", null, "2026-01-05"]); a.add(["2", "2310.25", "", "2026-12-31"]);
  b.add([2, "2.3102500000000000e+003", "", "2026-12-31"]); b.add([1, "1.0000000000000001e-001", null, Date.UTC(2026, 0, 5)]);
  c.add(["1", String(0.1 + Number.EPSILON / 8 * 2), null, "2026-01-05"]); c.add(["2", "2310.25", "", "2026-12-31"]);
  e.add(["1", "0.1", "", "2026-01-05"]); e.add(["2", "2310.25", "", "2026-12-31"]);
  assert.equal(a.hex(), b.hex());
  assert.notEqual(a.hex(), c.hex());
  assert.notEqual(a.hex(), e.hex());
});
