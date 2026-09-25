import { test } from "node:test";
import assert from "node:assert/strict";
import { field, line, parse, numberText } from "../src/lib/csv.js";

test("csv: NULL is an empty unquoted field, an empty string is quoted", () => {
  assert.equal(line([1, null, "", "a"]), '1,,"",a\n');
  assert.deepEqual(parse('1,,"",a\n'), [["1", null, "", "a"]]);
  assert.deepEqual(parse("a,\n"), [["a", null]]);
});

test("csv: quoting of comma, quote, newline and edge whitespace round-trips", () => {
  const vals = ['He said "hi"', "a,b", "two\nlines", " pad", "Café 東京", "x"];
  assert.deepEqual(parse(line(vals)), [vals]);
  assert.equal(field('a"b'), '"a""b"');
});

test("csv: numbers are plain decimals with '.', never exponent form", () => {
  assert.equal(numberText(1200.5), "1200.5");
  assert.equal(numberText(1e-7), "0.0000001");
  assert.equal(numberText(-0), "0");
  assert.equal(numberText(1e21), "1000000000000000000000");
});
