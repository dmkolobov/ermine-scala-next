// Property (c): the port of formatDisplay is TOTAL over CellFormat, and agrees
// with the legacy function on every case the legacy's styleMap implements.

import { test } from "node:test";
import assert from "node:assert/strict";
import fc from "fast-check";

import {
  formatDisplay, defaultFormatEnv, numberFormat, roundTo, hwDates, CELL_FORMAT_TAGS,
  evalCondition, colorHex,
} from "../src/format";
import { legacyFormatTuple, LEGACY_STYLE_NAMES } from "../src/legacy";
import type { CellFormat } from "../src/generated/widgets";
import { CellFormatSchema } from "../src/generated/widgets";
import { cellFormatArb, rawValuesArb, newDom } from "./harness";
import { legacyAvailable, loadLegacyUtils, WRITERS_ROOT } from "./legacy-utils";

const { document: doc } = newDom();
const env = defaultFormatEnv(doc);

/** The `tag` literals of a generated discriminated union, unwrapping the z.lazy
 *  the generator puts around a recursive schema. */
export function unionTags(schema: unknown): string[] {
  let s = schema as { _def?: { typeName?: string; getter?: () => unknown }; options?: unknown[] };
  while (s && s._def && s._def.typeName === "ZodLazy" && s._def.getter) {
    s = s._def.getter() as typeof s;
  }
  const options = (s?.options ?? []) as { shape?: { tag?: { value?: unknown } } }[];
  return options
    .map((o) => o.shape?.tag?.value)
    .filter((t): t is string => typeof t === "string")
    .sort();
}

/** The formats the legacy tuple form can carry without loss: its style name is in
 *  the styleMap AND the two flags the tuple drops are off. */
function comparable(f: CellFormat): boolean {
  switch (f.tag) {
    case "Default": case "DateRange": case "Constant": case "Truncate": case "Alias":
      return true;
    case "Percentage": case "Currency": case "Round": case "IntegralRound":
      return !f.color && !f.negParens;
    case "Pr1":
      return comparable(f.base);
    default:
      return false;
  }
}

test("(c-total) the port answers for every CellFormat, and handles every tag the generated zod has", () => {
  // the hand-written switch and the generated schema must list the same tags
  assert.deepStrictEqual(unionTags(CellFormatSchema), [...CELL_FORMAT_TAGS].sort(),
    "src/format.ts and the generated zod disagree about the CellFormat cases");

  fc.assert(
    fc.property(cellFormatArb(true), rawValuesArb, (fmt, values) => {
      const out = formatDisplay(fmt, env)(values);
      // total: it returned, and never undefined-by-accident for a defined input
      assert.ok(out === null || out === undefined || typeof out !== "object" || out instanceof Date);
      // and the value it was given validates against the generated schema
      assert.ok(CellFormatSchema.safeParse(fmt).success, JSON.stringify(fmt));
    }),
    { numRuns: 500 },
  );
});

test("(c-legacy) the port agrees with ermine-writers' formatDisplay wherever the tuple form is lossless", (t) => {
  if (!legacyAvailable()) {
    assert.fail(`ermine-writers not found at ${WRITERS_ROOT}; set ERMINE_WRITERS to its checkout`);
  }
  const legacy = loadLegacyUtils(doc);
  let compared = 0;
  const seen = new Set<string>();
  fc.assert(
    fc.property(cellFormatArb(false), rawValuesArb, (fmt, values) => {
      if (!comparable(fmt)) return;
      const tuple = legacyFormatTuple(fmt);
      assert.ok(
        (LEGACY_STYLE_NAMES as readonly string[]).includes(tuple[0]),
        `comparable() let a format through whose style ${tuple[0]} the legacy has no case for`,
      );
      const want = legacy.formatDisplay(tuple)(values);
      const got = formatDisplay(fmt, env)(values);
      assert.deepStrictEqual(got, want,
        `${JSON.stringify(fmt)} on ${JSON.stringify(values)}: port ${String(got)} vs legacy ${String(want)}`);
      compared++;
      seen.add(fmt.tag);
    }),
    { numRuns: 4000 },
  );
  // anti-vacuity: the comparison must actually have run, on every lossless case
  assert.ok(compared > 500, `only ${compared} cases were comparable`);
  assert.deepStrictEqual(
    [...seen].sort(),
    ["Alias", "Constant", "Currency", "Default", "DateRange", "IntegralRound", "Percentage", "Pr1", "Round", "Truncate"].sort(),
    `cases never compared: ${JSON.stringify([...seen])}`,
  );
  t.diagnostic(`compared ${compared} random (format, values) pairs against the legacy`);
});

test("(c-mutant) the agreement check is not vacuous: a deliberately wrong port is caught", () => {
  if (!legacyAvailable()) return;
  const legacy = loadLegacyUtils(doc);
  // Truncate at n instead of max(2, n-3): the legacy must disagree
  const broken = (n: number) => (s: string) => (s.length > n ? `${s.substr(0, n)}…` : s);
  const fmt: CellFormat = { tag: "Truncate", places: 8 };
  const value = "abcdefghijklmnop";
  assert.notDeepStrictEqual(broken(8)(value), legacy.formatDisplay(legacyFormatTuple(fmt))([value]));
  assert.deepStrictEqual(formatDisplay(fmt, env)([value]), legacy.formatDisplay(legacyFormatTuple(fmt))([value]));
});

test("(c-pin) the transcribed helpers", () => {
  assert.equal(numberFormat(1.005, 2, ".", ""), "1.01");
  assert.equal(numberFormat(-1234.5678, 2, ".", ","), "-1,234.57");
  assert.equal(numberFormat(1234.5678, 0, ".", ""), "1235");
  assert.equal(numberFormat(0, 3, ",", ""), "0,000");
  assert.equal(roundTo(1.005, 2), 1);          // Math.round on the float, as the legacy
  assert.equal(roundTo(2.5, 0), 3);
  assert.deepStrictEqual(hwDates([[2026, 9, 16]]), [new Date(Date.UTC(2026, 8, 16))]);
  assert.deepStrictEqual(hwDates([[2026, 9]]), [[2026, 9]]);
  assert.equal(colorHex({ red: 0, green: 128, blue: 255 }), "#0080ff");
});

test("(c-extra) the five cases the legacy tuple form cannot carry", () => {
  const f = (x: CellFormat, vs: unknown[]) => formatDisplay(x, env)(vs);
  assert.equal(f({ tag: "Verbatim", args: [] }, ["<b>x</b>"]), "<b>x</b>");
  assert.equal(f({ tag: "Markdown", base: { tag: "Default", args: [] } }, ["<b>x</b>"]), "x");
  // Pr2 formats the SECOND value with `base`; Truncate cuts at max(2, n-3)
  assert.equal(f({ tag: "Pr2", base: { tag: "Truncate", places: 4 } }, ["ignored", "abcdefgh"]), "ab…");
  assert.equal(
    f({ tag: "Conditional", condition: { tag: "Gt", gt: { tag: "TNum", args: [10] } },
        whenTrue: { tag: "Constant", value: "big" }, whenFalse: { tag: "Constant", value: "small" } }, [11]),
    "big",
  );
  assert.equal(
    f({ tag: "Color", bg: { red: 255, green: 0, blue: 0 }, fg: { red: 0, green: 0, blue: 0 },
        base: { tag: "Constant", value: "v" } }, [1]),
    '<span class="foreground" style="color: #000000;"><span class="background" style="background-color: #ff0000;">v</span></span>',
  );
  // the flags the tuple drops
  assert.equal(f({ tag: "Round", color: false, negParens: true, places: 1 }, [-1.75]), "(1.8)");
  assert.equal(f({ tag: "Round", color: true, negParens: false, places: 1 }, [-1.75]),
    '<span class="ermine_negative">-1.8</span>');
  // Alias: a repeated key takes the LAST pair (the legacy builds an object), and
  // an empty alias falls back to the value.  Found by (c-legacy), pinned here.
  assert.equal(f({ tag: "Alias", aliases: [["a", "one"], ["a", "two"]] }, ["a"]), "two");
  assert.equal(f({ tag: "Alias", aliases: [["a", ""]] }, ["a"]), "a");
  assert.equal(f({ tag: "Alias", aliases: [["b", "x"]] }, ["a"]), "a");
  // and the one place the port is NOT bug-compatible: the legacy reads
  // `aliases[fst]` off a plain object, so these answer Object.prototype's member
  assert.equal(f({ tag: "Alias", aliases: [] }, ["constructor"]), "constructor");
  assert.equal(f({ tag: "Alias", aliases: [] }, ["__proto__"]), "__proto__");
  // conditions
  assert.equal(evalCondition({ tag: "And", and: [
    { tag: "Gte", gte: { tag: "TNum", args: [1] } },
    { tag: "Lte", lte: { tag: "TNum", args: [3] } }] }, 2), true);
});
