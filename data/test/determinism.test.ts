// (seed, tier, domain) -> identical bytes, always.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { freshDir, generate } from "./harness.js";

test("determinism s: two runs with the same seed give identical manifests (sha256 per CSV)", () => {
  const a = generate("s", 42, undefined, freshDir()), b = generate("s", 42, undefined, freshDir());
  assert.deepEqual(a.manifest, b.manifest);
  for (const f of Object.values(a.manifest.tables)) {
    assert.ok(readFileSync(join(a.dir, f.file)).equals(readFileSync(join(b.dir, f.file))), f.file);
  }
  assert.ok(readFileSync(join(a.dir, "manifest.json")).equals(readFileSync(join(b.dir, "manifest.json"))));
});

test("determinism s: a different seed changes the generated tables", () => {
  const a = generate("s", 42, undefined, freshDir()), b = generate("s", 43, undefined, freshDir());
  for (const t of ["dim_rep", "dim_customer", "fact_order_line", "fact_target"]) {
    assert.notEqual(a.manifest.tables[t]!.sha256, b.manifest.tables[t]!.sha256, t);
  }
  // the calendar and the channel list do not depend on the seed
  assert.equal(a.manifest.tables.dim_date!.sha256, b.manifest.tables.dim_date!.sha256);
});

test("determinism: --rows N gives exactly N fact rows and is itself reproducible", () => {
  const a = generate("s", 9, 2500, freshDir()), b = generate("s", 9, 2500, freshDir());
  assert.equal(a.manifest.tables.fact_order_line!.rows, 2500);
  assert.equal(a.manifest.tier, "s-2500");
  assert.deepEqual(a.manifest, b.manifest);
});

test("determinism: this box's s/42 bytes are pinned (a change here is a deliberate model change)", () => {
  const a = generate("s", 42, undefined, freshDir());
  const pinned = JSON.parse(readFileSync(join(__dirnameOf(), "..", "..", "test", "pinned-s42.json"), "utf8")) as Record<string, string>;
  const got = Object.fromEntries(Object.entries(a.manifest.tables).map(([k, v]) => [k, v.sha256]));
  assert.deepEqual(got, pinned, "regenerate test/pinned-s42.json only for an intended model change, and say so in GENERATOR.md");
});

function __dirnameOf(): string { return new URL(".", import.meta.url).pathname; }
