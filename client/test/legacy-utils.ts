// Loads the REAL legacy `formatDisplay` out of the ermine-writers checkout, so
// property (c) compares the port against the original rather than against a
// re-reading of it.
//
// `writers/js/ermine/utils.js` is an ES module that imports lodash, Highcharts and
// the htmlwriter bundle, none of which are installed here (and the bundle cannot
// load outside a browser at all).  So the file is read as TEXT, its three `import`
// lines and its `export` keywords are stripped, and the body is evaluated with
// stubs.  What is stubbed, and why it is honest:
//
//   * `_` -- the five lodash functions the module reaches at load time or from
//     formatDisplay (`map`, `isArray`, `size`, `every`, `isNumber`, `has`,
//     `identity`, `isString`), each a two-line transcription.
//   * `Highcharts` -- `getOptions().lang.decimalPoint` (".") and `numberFormat`.
//     numberFormat is OUR implementation (src/format.ts), injected into the legacy
//     side as well: highcharts is not a dependency of this package, so the
//     agreement property covers the DISPATCH and the argument plumbing of every
//     case, not Highcharts' own number formatting.  That transcription is pinned
//     separately in test/format.test.ts against its documented behaviour.
//   * `htmlwriter`, `window`, `$` -- touched only by module-level bindings that
//     formatDisplay does not use (`toJSON`, `dateTimeLabelFormats`).
//   * `document` -- jsdom's, which is what `string_unhtml` needs and what the port
//     uses too.
//
// If the checkout is missing the tests that need it are skipped, loudly.

import * as fs from "fs";
import * as path from "path";
import { numberFormat } from "../src/format";

const REL = "writers/js/ermine/utils.js";

/** The ermine-writers checkout: $ERMINE_WRITERS, else the nearest sibling of an
 *  ancestor directory that actually holds writers/js/ermine/utils.js.  Searched
 *  rather than hard-coded because the tests run from src/ and from dist/. */
function findWriters(): string {
  const fromEnv = process.env.ERMINE_WRITERS;
  if (fromEnv) return fromEnv;
  let dir = __dirname;
  for (let i = 0; i < 8; i++) {
    const candidate = path.join(dir, "..", "ermine-writers");
    if (fs.existsSync(path.join(candidate, REL))) return path.resolve(candidate);
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return path.resolve(__dirname, "../../../ermine-writers");
}

export const WRITERS_ROOT = findWriters();

const UTILS = path.join(WRITERS_ROOT, REL);

export interface LegacyUtils {
  formatDisplay(fmt: [string, unknown]): (values: unknown[]) => unknown;
  nelpeHwDates(values: unknown[]): unknown[];
  round(n: number, places: number): number;
  string_unhtml(s: string, force?: boolean): string;
}

export function legacyAvailable(): boolean {
  return fs.existsSync(UTILS);
}

const lodashStub = {
  identity: <A>(a: A): A => a,
  isArray: Array.isArray,
  isNumber: (v: unknown): boolean => typeof v === "number",
  isString: (v: unknown): boolean => typeof v === "string",
  size: (v: unknown): number => (Array.isArray(v) ? v.length : Object.keys(v as object).length),
  every: <A>(xs: A[], f: (a: A) => boolean): boolean => xs.every((x) => f(x)),
  map: <A, B>(xs: A[], f: (a: A, i: number) => B): B[] => xs.map((x, i) => f(x, i)),
  has: (o: object, k: string): boolean => Object.prototype.hasOwnProperty.call(o, k),
  reduce: <A, B>(xs: A[], f: (acc: B, a: A) => B, init: B): B => xs.reduce((a, x) => f(a, x), init),
};

const highchartsStub = {
  getOptions: () => ({ lang: { decimalPoint: ".", thousandsSep: "" } }),
  numberFormat,
};

/** Evaluate the legacy module against `doc` (a jsdom Document). */
export function loadLegacyUtils(doc: Document): LegacyUtils {
  const source = fs.readFileSync(UTILS, "utf8");
  const body = source
    .split("\n")
    .filter((line) => !/^\s*import\s/.test(line))
    .join("\n")
    .replace(/^export\s+/gm, "");
  const factory = new Function(
    "_", "Highcharts", "htmlwriter", "document", "window", "$",
    `${body}\nreturn { formatDisplay, nelpeHwDates, round, string_unhtml };`,
  ) as (
    lodash: unknown, hc: unknown, hw: unknown, d: Document, w: unknown, jq: unknown,
  ) => LegacyUtils;
  const windowStub = { toJSON: undefined, JSON };
  const jqueryStub = { parseJSON: JSON.parse, extend: Object.assign, fn: { dataTableExt: { oSort: {} } } };
  return factory(lodashStub, highchartsStub, {}, doc, windowStub, jqueryStub);
}
