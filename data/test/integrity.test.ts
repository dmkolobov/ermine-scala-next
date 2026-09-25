// Integrity of every tier the tests generate (xs, s, m): the contract's
// structural rules (PK, UNIQUE case-insensitive, FK, NULL only where
// nullable, no duplicate rows) and the sales invariants it states.

import { test } from "node:test";
import assert from "node:assert/strict";
import { baseType } from "../src/contract.js";
import { parseIso, parts } from "../src/lib/dates.js";
import { round } from "../src/lib/dist.js";
import { contract, Loaded, rowsOf, tier, TRow } from "./harness.js";

const key = (r: TRow, cols: string[], ci = false) =>
  JSON.stringify(cols.map((c) => { const v = r[c] ?? null; return ci && typeof v === "string" ? v.toLowerCase() : v; }));

function structural(l: Loaded): void {
  for (const t of contract.tables) {
    const rows = rowsOf(l, t.name);
    assert.equal(rows.length, l.manifest.tables[t.name]!.rows, `${t.name}: manifest count`);
    // no duplicate rows (the scanner assumes distinct rows), PK unique, UNIQUE unique case-insensitively
    const all = new Set(rows.map((r) => key(r, t.columns.map((c) => c.name))));
    assert.equal(all.size, rows.length, `${t.name}: duplicate rows`);
    const pk = new Set(rows.map((r) => key(r, t.pk)));
    assert.equal(pk.size, rows.length, `${t.name}: duplicate primary key`);
    for (const u of t.unique) {
      const s = new Set(rows.map((r) => key(r, u, true)));
      assert.equal(s.size, rows.length, `${t.name}: UNIQUE(${u}) violated case-insensitively`);
    }
    // NULL only in nullable columns; types and lengths
    for (const c of t.columns) {
      for (const r of rows) {
        const v = r[c.name] ?? null;
        if (v === null) { assert.ok(c.nullable, `${t.name}.${c.name}: NULL in a non-nullable column`); continue; }
        const bt = baseType(c.ermine);
        if (bt === "Int") assert.ok(Number.isInteger(v), `${t.name}.${c.name}: ${v} not Int`);
        if (bt === "Double") assert.ok(Number.isFinite(v), `${t.name}.${c.name}: ${v} not Double`);
        if (bt === "Date") assert.match(String(v), /^\d{4}-\d{2}-\d{2}$/);
        if (c.maxLength !== undefined) assert.ok([...String(v)].length <= c.maxLength, `${t.name}.${c.name}: too long: ${v}`);
      }
    }
    // every FK resolves
    for (const fk of t.fks) {
      const target = new Set(rowsOf(l, fk.ref).map((r) => key(r, fk.refColumns)));
      for (const r of rows) assert.ok(target.has(key(r, fk.columns)), `${t.name}(${fk.columns}) -> ${fk.ref}: ${key(r, fk.columns)} dangles`);
    }
  }
}

function salesInvariants(l: Loaded, generated: boolean): void {
  const region = rowsOf(l, "dim_region"), product = rowsOf(l, "dim_product"), rep = rowsOf(l, "dim_rep");
  const customer = rowsOf(l, "dim_customer"), date = rowsOf(l, "dim_date"), fact = rowsOf(l, "fact_order_line");
  const target = rowsOf(l, "fact_target"), report = rowsOf(l, "sales_report");
  for (const r of region) assert.match(String(r.regionCode), /^[a-z][a-z0-9-]*$/);
  assert.ok(Math.abs(region.reduce((a, r) => a + Number(r.populationWeight), 0) - 1) < 1e-6, "populationWeight sums to 1");
  const repRegion = new Map(rep.map((r) => [r.repId, r.regionId]));
  const custRegion = new Map(customer.map((r) => [r.customerId, r.regionId]));
  const orders = new Map<number, TRow[]>();
  for (const f of fact) {
    assert.equal(f.lineAmount, round(Number(f.quantity) * Number(f.unitPrice) * (1 - Number(f.discountPct)), 2), `lineAmount of ${f.orderId}/${f.lineNo}`);
    assert.equal(repRegion.get(f.repId!), f.regionId, "rep's region = line's region");
    assert.equal(custRegion.get(f.customerId!), f.regionId, "customer's region = line's region");
    if (f.promoCode !== null) {
      assert.ok(Number(f.discountPct) > 0, "promoCode only with a discount");
      assert.match(String(f.promoCode), /^[A-Z]{4,8}[0-9]{2}$/);
    }
    const q = Number(f.quantity), d = Number(f.discountPct), a = Number(f.lineAmount);
    assert.ok(q >= 1 && q <= 50, `quantity ${q}`);
    assert.ok(d >= 0 && d <= 0.3, `discountPct ${d}`);
    assert.ok(a >= 0 && a <= 50000, `lineAmount ${a}`);
    const o = orders.get(Number(f.orderId)) ?? []; o.push(f); orders.set(Number(f.orderId), o);
  }
  for (const [id, lines] of orders) {
    const nos = lines.map((x) => Number(x.lineNo)).sort((a, b) => a - b);
    assert.deepEqual(nos, nos.map((_, i) => i + 1), `order ${id}: lineNo 1..n without gaps`);
    assert.ok(nos.length <= 8);
    for (const c of ["orderDate", "regionId", "customerId", "repId", "channelId"]) {
      assert.equal(new Set(lines.map((x) => x[c])).size, 1, `order ${id}: lines disagree on ${c}`);
    }
  }
  for (const p of product) assert.ok(Number(p.unitCost) < Number(p.listPrice), `unitCost < listPrice for ${p.productName}`);
  // one target per (region, year, quarter) of the calendar's quarters
  const quarters = new Set(date.map((d) => `${d.yearNo}/${d.quarterNo}`));
  assert.equal(target.length, region.length * quarters.size);
  assert.deepEqual(report.map((r) => r.srRegion), ["EMEA", "APAC", "AMER"]);
  if (!generated) return;
  // calendar: contiguous, derived columns right
  const days = date.map((d) => parseIso(String(d.day)));
  for (let i = 1; i < days.length; i++) assert.equal(days[i], days[i - 1]! + 1, "dim_date contiguous");
  for (const d of date) {
    const p = parts(parseIso(String(d.day)));
    assert.equal(d.yearNo, p.y); assert.equal(d.monthNo, p.m); assert.equal(d.weekdayNo, p.dow + 1);
    assert.equal(d.quarterNo, Math.floor((p.m - 1) / 3) + 1);
    assert.equal(d.monthName, `${p.y}-${String(p.m).padStart(2, "0")}`);
  }
  // hires not after the tier's first day; signups not after the customer's first order
  const first = days[0]!;
  for (const r of rep) assert.ok(parseIso(String(r.hireDate)) <= first, `hireDate ${r.hireDate}`);
  const firstOrder = new Map<number, number>();
  for (const f of fact) {
    const c = Number(f.customerId), d = parseIso(String(f.orderDate));
    firstOrder.set(c, Math.min(firstOrder.get(c) ?? Infinity, d));
  }
  for (const c of customer) {
    const fo = firstOrder.get(Number(c.customerId));
    if (fo !== undefined) assert.ok(parseIso(String(c.signupDate)) <= fo, `customer ${c.customerId} ordered before signing up`);
  }
  // money columns carry cents
  for (const f of fact) assert.equal(Number(f.unitPrice), round(Number(f.unitPrice), 4));
  for (const t of target) assert.equal(Number(t.targetAmount), round(Number(t.targetAmount), 2));
}

for (const name of ["xs", "s", "m"]) {
  test(`integrity ${name}: PK, UNIQUE (case-insensitive), FK, NULLs, no duplicate rows`, () => structural(tier(name)));
  test(`integrity ${name}: sales invariants (lineAmount, order headers, regions, targets, calendar)`, () => salesInvariants(tier(name), name !== "xs"));
}

test("integrity xs: every table is exactly the contract's literal rows", () => {
  const l = tier("xs");
  for (const t of contract.tables) {
    const got = rowsOf(l, t.name);
    assert.deepEqual(got, t.xs.rows.map((r) => Object.fromEntries(t.columns.map((c) => [c.name, (r[c.name] ?? null) as never]))), t.name);
  }
});

test("integrity xs: seed is ignored (seed 42 and seed 7 give the same bytes)", () => {
  const a = tier("xs", 42), b = tier("xs", 7);
  assert.deepEqual(a.manifest, b.manifest);
});
