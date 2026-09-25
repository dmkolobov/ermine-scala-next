// The emitter's per-cell contract checks.

import { test } from "node:test";
import assert from "node:assert/strict";
import { checkCell, writeTable } from "../src/emit.js";
import type { Table } from "../src/contract.js";
import { contract, freshDir } from "./harness.js";

const fact = contract.tables.find((t) => t.name === "fact_order_line")!;
const promo = fact.columns.find((c) => c.name === "promoCode")!;

test("emit: '' in a nullable String column is rejected by name (REVIEW-S1 M3); NULL and a code pass", () => {
  assert.ok(promo.nullable);
  assert.throws(() => checkCell(fact, promo, "", 3), /fact_order_line row 3 column promoCode: empty string \(the contract bans/);
  checkCell(fact, promo, null, 3);
  checkCell(fact, promo, "SPRING26", 3);
});

test("emit: '' in a nullable non-string column is rejected too", () => {
  const rep = contract.tables.find((t) => t.name === "dim_rep")!;
  const score = rep.columns.find((c) => c.name === "repScore")!;
  assert.throws(() => checkCell(rep, score, "" as never, 1), /dim_rep row 1 column repScore: empty string \(the contract bans/);
});

test("emit: '' in a NON-nullable String column is rejected by name as well", () => {
  const region = contract.tables.find((t) => t.name === "dim_region")!;
  const code = region.columns.find((c) => c.name === "regionCode")!;
  assert.ok(!code.nullable);
  assert.throws(() => checkCell(region, code, "", 2), /dim_region row 2 column regionCode: empty string \(the contract bans/);
  checkCell(region, code, "north", 2);
});

test("emit: a model emitting '' in promoCode fails the table write, naming table, row and column", () => {
  const row = { ...(fact.xs.rows[0] as Record<string, unknown>), promoCode: "" };
  assert.throws(() => writeTable(freshDir(), fact as Table, [fact.xs.rows[1] as never, row as never]),
    /fact_order_line row 2 column promoCode: empty string \(the contract bans/);
});
