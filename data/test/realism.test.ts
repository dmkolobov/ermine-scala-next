// Realism bounds (the model does what GENERATOR.md says it does) and the
// star schema's consistency with the minimal `sales` relation of FetchData.e.

import { test } from "node:test";
import assert from "node:assert/strict";
import { bandEdges, categoryByName, PRICE_BANDS } from "../src/domains/sales.js";
import { parseIso, parts } from "../src/lib/dates.js";
import { round } from "../src/lib/dist.js";
import { contract, rowsOf, tier, TRow } from "./harness.js";

test("realism s, m: listPrice and every unitPrice inside the product's category price band", () => {
  for (const name of ["s", "m"]) {
    const l = tier(name);
    const prod = new Map(rowsOf(l, "dim_product").map((p) => [p.productId, p]));
    const edges = (p: TRow) => bandEdges(categoryByName(String(p.category))!, PRICE_BANDS.indexOf(p.priceBand as never));
    for (const p of prod.values()) { const [lo, hi] = edges(p); assert.ok(Number(p.listPrice) >= lo && Number(p.listPrice) <= hi, `${p.productName} list ${p.listPrice} not in [${lo}, ${hi}]`); }
    for (const f of rowsOf(l, "fact_order_line")) {
      const p = prod.get(f.productId!)!; const [lo, hi] = edges(p); const u = Number(f.unitPrice);
      assert.ok(u >= lo && u <= hi, `${name}: unitPrice ${u} of ${p.productName} not in [${lo}, ${hi}]`);
      assert.ok(Math.abs(u / Number(p.listPrice) - 1) <= 0.041, `${name}: unitPrice ${u} more than 4% off list ${p.listPrice}`);
    }
  }
});

test("realism m: region shares of order lines honour populationWeight (10% relative + 3 sigma, clustered)", () => {
  const l = tier("m");
  const fact = rowsOf(l, "fact_order_line");
  const orders = new Set(fact.map((f) => f.orderId)).size;
  const per = new Map<number, number>();
  for (const f of fact) per.set(Number(f.regionId), (per.get(Number(f.regionId)) ?? 0) + 1);
  for (const r of rowsOf(l, "dim_region")) {
    const w = Number(r.populationWeight), obs = (per.get(Number(r.regionId)) ?? 0) / fact.length;
    // lines come in orders of ~2.2, so the effective sample is the order count
    const tol = 0.1 * w + 3 * Math.sqrt(w * (1 - w) / orders);
    assert.ok(Math.abs(obs - w) <= tol, `${r.regionCode}: share ${obs.toFixed(4)} vs weight ${w} (tol ${tol.toFixed(4)})`);
  }
});

test("realism m: weekday shape (Tue-Wed busiest, weekends under a third) and outdoor seasonality", () => {
  const l = tier("m");
  const byDow: number[] = new Array(7).fill(0), daysPerDow: number[] = new Array(7).fill(0);
  for (const d of rowsOf(l, "dim_date")) daysPerDow[Number(d.weekdayNo) - 1]! += 1;
  const prod = new Map(rowsOf(l, "dim_product").map((p) => [p.productId, p]));
  const outdoorByMonth: number[] = new Array(12).fill(0), allByMonth: number[] = new Array(12).fill(0);
  for (const f of rowsOf(l, "fact_order_line")) {
    const p = parts(parseIso(String(f.orderDate)));
    byDow[p.dow]! += 1;
    allByMonth[p.m - 1]! += 1;
    if (prod.get(f.productId!)!.category === "Outdoor") outdoorByMonth[p.m - 1]! += 1;
  }
  const perDay = byDow.map((n, i) => n / daysPerDow[i]!);
  const weekday = (perDay[1]! + perDay[2]!) / 2, weekend = (perDay[5]! + perDay[6]!) / 2;
  assert.ok(weekend < weekday / 3, `weekend ${weekend.toFixed(1)} vs Tue-Wed ${weekday.toFixed(1)} lines/day`);
  const share = (m: number) => outdoorByMonth[m]! / allByMonth[m]!;
  assert.ok(share(5) > 1.8 * share(0), `outdoor share June ${share(5).toFixed(3)} vs January ${share(0).toFixed(3)}`);
});

test("realism m: repScore NULL rate near the contract's 0.15; promoCode NULL rate near 0.8", () => {
  const l = tier("m");
  const reps = rowsOf(l, "dim_rep"), fact = rowsOf(l, "fact_order_line");
  const repNull = reps.filter((r) => r.repScore === null).length / reps.length;
  const promoNull = fact.filter((f) => f.promoCode === null).length / fact.length;
  assert.ok(repNull > 0.03 && repNull < 0.35, `repScore NULL rate ${repNull}`);
  assert.ok(promoNull > 0.7 && promoNull < 0.9, `promoCode NULL rate ${promoNull}`);
});

// The `sales` view of the contract, computed in JS: region, day, SUM(lineAmount), SUM(quantity).
function salesView(fact: TRow[], region: TRow[]): Map<string, { region: string; day: string; amount: number; units: number }> {
  const code = new Map(region.map((r) => [r.regionId, String(r.regionCode)]));
  const out = new Map<string, { region: string; day: string; amount: number; units: number }>();
  for (const f of fact) {
    const k = `${code.get(f.regionId)}|${f.orderDate}`;
    const v = out.get(k) ?? { region: code.get(f.regionId)!, day: String(f.orderDate), amount: 0, units: 0 };
    v.amount = round(v.amount + Number(f.lineAmount), 2); v.units += Number(f.quantity);
    out.set(k, v);
  }
  return out;
}

test("star schema xs: the `sales` view over the fact reproduces FetchData.e's eight rows and pinned totals", () => {
  const l = tier("xs");
  const view = salesView(rowsOf(l, "fact_order_line"), rowsOf(l, "dim_region"));
  const fetchData: [string, string, number, number][] = [
    ["north", "2026-01-05", 1200.5, 3], ["north", "2026-01-19", 840.0, 2], ["north", "2026-02-14", 2310.25, 7],
    ["south", "2026-01-09", 615.75, 1], ["south", "2026-02-02", 1990.0, 5], ["east", "2026-02-20", 75.5, 1],
    ["east", "2026-03-03", 4100.0, 11], ["west", "2026-03-17", 1550.0, 4]];
  assert.deepEqual([...view.values()].map((v) => [v.region, v.day, v.amount, v.units]).sort(), fetchData.slice().sort());
  const pinned = contract.xsPinned as { regionAmount: Record<string, number>; totalAmount: number; totalUnits: number; targetTotal: number; srSalesTotal: number };
  for (const [r, a] of Object.entries(pinned.regionAmount)) {
    assert.equal(round([...view.values()].filter((v) => v.region === r).reduce((s, v) => s + v.amount, 0), 2), a, r);
  }
  assert.equal(round([...view.values()].reduce((s, v) => s + v.amount, 0), 2), pinned.totalAmount);
  assert.equal([...view.values()].reduce((s, v) => s + v.units, 0), pinned.totalUnits);
  assert.equal(rowsOf(l, "fact_target").reduce((s, t) => s + Number(t.targetAmount), 0), pinned.targetTotal);
  assert.equal(round(rowsOf(l, "sales_report").reduce((s, t) => s + Number(t.srSales), 0), 2), pinned.srSalesTotal);
});

test("star schema s: the `sales` view has the minimal columns with their Ermine types and distinct keys", () => {
  const l = tier("s");
  const view = [...salesView(rowsOf(l, "fact_order_line"), rowsOf(l, "dim_region")).values()];
  const vc = contract.views.find((v) => v.name === "sales")!.columns.map((c) => [c.name, c.ermine]);
  assert.deepEqual(vc, [["region", "String"], ["day", "Date"], ["amount", "Double"], ["units", "Int"]]);
  const days = new Set(rowsOf(l, "dim_date").map((d) => d.day));
  for (const v of view) {
    assert.equal(typeof v.region, "string"); assert.ok(days.has(v.day));
    assert.ok(Number.isFinite(v.amount) && v.amount > 0); assert.ok(Number.isInteger(v.units) && v.units > 0);
  }
  assert.equal(new Set(view.map((v) => `${v.region}|${v.day}`)).size, view.length);
  assert.ok(view.length > 300, `only ${view.length} (region, day) rows at s`);
});

test("sales_report s: srSales and srDelta follow the last two quarters of the fact", () => {
  const l = tier("s");
  const group = new Map(rowsOf(l, "dim_region").map((r) => [r.regionId, String(r.regionGroup)]));
  const q = (g: string, quarter: number) => rowsOf(l, "fact_order_line")
    .filter((f) => group.get(f.regionId) === g && parts(parseIso(String(f.orderDate))).m > (quarter - 1) * 3 && parts(parseIso(String(f.orderDate))).m <= quarter * 3)
    .reduce((s, f) => s + Number(f.lineAmount), 0);
  for (const r of rowsOf(l, "sales_report")) {
    const g = String(r.srRegion), a = q(g, 4), b = q(g, 3);
    assert.equal(r.srSales, round(a / 1000, 2), `${g} srSales`);
    assert.equal(r.srDelta, round((a - b) / b, 3), `${g} srDelta`);
  }
});
