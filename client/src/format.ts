// A port of the legacy `formatDisplay` (ermine-writers, writers/js/ermine/utils.js
// ~291-352) to the OBJECT form of a format, total over Layout.Widgets.Format's
// CellFormat.
//
// Why a port and not a call: the legacy function takes the TUPLE form that
// HTMLWriter.jsLayoutFormat emits (`["Percentage", [places, pad]]`), which throws
// away the colour flag, the negative-parenthesis flag and every recursive format
// except Pr1 -- `Markdown`, `Conditional`, `ColorFormat`, `Verbatim` and `Pr2` all
// collapse to a name its styleMap does not have and fall back to `Default`.  The
// object form keeps all of it, and on the JSON path the client is the only thing
// that can format a cell: today `formatted` is computed server-side by Scala
// (HTMLWriter.htmlEval + Format.basicEval), and that code is not on the wire.
//
// The ten cases the legacy styleMap does implement are reproduced EXACTLY,
// including their oddities:
//
//   * `Pr1`'s inner formatter is called with (fst, rest[0], rest.slice(1)) -- the
//     second value is skipped, not passed on.
//   * `Round` goes through Highcharts.numberFormat (a string) while
//     `IntegralRound` goes through plain rounding (a number).
//   * `Truncate` unescapes HTML first, then cuts at max(2, n-3) and appends U+2026.
//   * a 3-element all-number array anywhere in the values is a YMD date triple and
//     becomes a Date first (`nelpeHwDates`).  Nothing on the JSON wire is an array,
//     so this only matters to the agreement property, which feeds triples on
//     purpose.
//
// The five cases it does not implement, and the two flags it drops, follow the
// SCALA renderer (HTMLWriter.htmlEval) instead; see each case below.

import type { CellFormat, CellCondition, Threshold, RGB } from "./props";

export type { CellFormat, CellCondition, Threshold, RGB };

/** What a formatter is handed: wire cells, or (for the legacy chart path) a YMD
 *  triple.  `unknown[]` rather than WireCell[] because the legacy function is
 *  untyped and the agreement property feeds it triples and Dates. */
export type RawValues = unknown[];

/** What a formatter answers.  The legacy returns a number for `IntegralRound` and
 *  a Date for a bare date triple, so the port does too. */
export type Formatted = string | number | boolean | Date | null | undefined;

export interface FormatEnv {
  /** The legacy `string_unhtml(s, true)`: unescape entities and strip tags. */
  unhtml(s: string): string;
  /** `Highcharts.getOptions().lang.decimalPoint`. */
  decimalPoint: string;
}

/** `Highcharts.numberFormat(number, decimals, decimalPoint, thousandsSep)`,
 *  transcribed.  The legacy passes `thousandsSep = ''`, so no separator ever
 *  reaches a table cell, but the argument is kept so the transcription can be read
 *  against the original. */
export function numberFormat(
  value: number,
  decimals: number,
  decimalPoint: string,
  thousandsSep: string,
): string {
  const n = Number(value) || 0;
  let dec = Number(decimals);
  const origDec = (n.toString().split(".")[1] || "").length;
  if (dec === -1) dec = Math.min(origDec, 20);
  else if (!Number.isFinite(dec)) dec = 2;
  // the extra decimal is Highcharts' float-rounding guard (#4573)
  const rounded = (Math.abs(n) + Math.pow(10, -Math.max(dec, origDec) - 1)).toFixed(dec);
  const strInteger = String(parseInt(rounded, 10));
  const thousands = strInteger.length > 3 ? strInteger.length % 3 : 0;
  let ret = n < 0 ? "-" : "";
  ret += thousands ? strInteger.substr(0, thousands) + thousandsSep : "";
  ret += strInteger.substr(thousands).replace(/(\d{3})(?=\d)/g, "$1" + thousandsSep);
  if (dec) ret += decimalPoint + rounded.slice(-dec);
  return ret;
}

/** The legacy `round(n, places)`: a NUMBER, not a string. */
export function roundTo(n: unknown, places: number): number {
  const shift = Math.pow(10, places);
  return Math.round((n as number) * shift) / shift;
}

/** The legacy `hwDate`: a YMD triple is a UTC date. */
export function hwDate(v: [number, number, number]): Date {
  return new Date(Date.UTC(v[0], v[1] - 1, v[2]));
}

/** The legacy `nelpeHwDates`. */
export function hwDates(values: RawValues): unknown[] {
  return values.map((v) =>
    Array.isArray(v) && v.length === 3 && v.every((x) => typeof x === "number")
      ? hwDate(v as [number, number, number])
      : v,
  );
}

const ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
};

/** A DOM-free `string_unhtml`, used when no Document is around.  The legacy sets
 *  innerHTML on a shared <span> and reads textContent back; with a Document
 *  present `domUnhtml` does exactly that instead. */
export function textUnhtml(s: string): string {
  return s
    .replace(/<[^>]*>/g, "")
    .replace(/&#x([0-9a-fA-F]+);/g, (_m, h: string) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#([0-9]+);/g, (_m, d: string) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&([a-zA-Z]+);/g, (m, name: string) => ENTITIES[name.toLowerCase()] ?? m);
}

/** `string_unhtml(s, true)` against a real Document, the legacy behaviour. */
export function domUnhtml(doc: Document): (s: string) => string {
  const holder = doc.createElement("span");
  return (s: string) => {
    holder.innerHTML = s;
    return holder.textContent ?? "";
  };
}

export function defaultFormatEnv(doc?: Document): FormatEnv {
  const d = doc ?? (typeof document !== "undefined" ? document : undefined);
  return { unhtml: d ? domUnhtml(d) : textUnhtml, decimalPoint: "." };
}

// ---------------------------------------------------------------------------

function thresholdValue(t: Threshold): string | number | boolean {
  return t.args[0];
}

/** Layout.Format's Condition, evaluated against the cell's first value. */
export function evalCondition(cond: CellCondition, value: unknown): boolean {
  switch (cond.tag) {
    case "Gt": return (value as number) > (thresholdValue(cond.gt) as number);
    case "Lt": return (value as number) < (thresholdValue(cond.lt) as number);
    case "Eq": return value === thresholdValue(cond.eq);
    case "Gte": return (value as number) >= (thresholdValue(cond.gte) as number);
    case "Lte": return (value as number) <= (thresholdValue(cond.lte) as number);
    case "And": return evalCondition(cond.and[0], value) && evalCondition(cond.and[1], value);
  }
}

function hex2(n: number): string {
  const v = Math.max(0, Math.min(255, Math.round(n)));
  return (v < 16 ? "0" : "") + v.toString(16);
}

/** HTMLWriter.getColorHexcode. */
export function colorHex(c: RGB): string {
  return `#${hex2(c.red)}${hex2(c.green)}${hex2(c.blue)}`;
}

/** HTMLWriter.htmlEval's Currency(true)/Percentage(true)/Round(true)/
 *  IntegralRound(true) branch: the sign decides the span class. */
function signSpan(colored: boolean, value: unknown, text: string): string {
  if (!colored) return text;
  const negative = typeof value === "number" && value < 0;
  return `<span class="${negative ? "ermine_negative" : "ermine_positive"}">${text}</span>`;
}

/** The `negParens` flag the tuple form drops: -1.7 renders as (1.7). */
function parenthesise(negParens: boolean, value: unknown, text: string): string {
  if (!negParens || typeof value !== "number" || value >= 0) return text;
  return `(${text.replace(/^-/, "")})`;
}

// ---------------------------------------------------------------------------

/**
 * `formatDisplay(fmt)(values)`.  Curried exactly like the legacy, so an adapter
 * can build the formatter once per COLUMN and apply it per row.
 */
export function formatDisplay(
  fmt: CellFormat,
  env: FormatEnv = defaultFormatEnv(),
): (values: RawValues) => Formatted {
  return (values: RawValues): Formatted => {
    const vs = hwDates(values);
    return applyFormat(fmt, env, vs[0], vs[1], vs.slice(2));
  };
}

/** The whole of the port: every CellFormat case, in the declaration order of
 *  Layout.Widgets.Format.  `fst`/`snd`/`rest` are the legacy's three arguments. */
function applyFormat(
  fmt: CellFormat,
  env: FormatEnv,
  fst: unknown,
  snd: unknown,
  rest: unknown[],
): Formatted {
  switch (fmt.tag) {
    // legacy styleMap.Default
    case "Default":
      return typeof fst === "string" ? env.unhtml(fst) : (fst as Formatted);

    // not in the legacy styleMap.  HTMLWriter.htmlEval: `pes.head`, untouched --
    // Verbatim is the escape hatch that lets a report emit its own HTML.
    case "Verbatim":
      return fst as Formatted;

    // not in the legacy styleMap ("MarkdownFmt" falls through to Default there).
    // The port formats with `base` and passes the result through: rendering
    // markdown needs an engine, which is the host page's business, and the table
    // adapter already tells the legacy sort key that this cell is markdown.
    case "Markdown":
      return applyFormat(fmt.base, env, fst, snd, rest);

    // legacy styleMap.Constant
    case "Constant":
      return fmt.value;

    // legacy styleMap.Percentage, plus the two flags the tuple form drops
    case "Percentage": {
      const scaled = (fst as number) * 100;
      const body = fmt.pad
        ? numberFormat(scaled, fmt.places, env.decimalPoint, "")
        : String(roundTo(scaled, fmt.places));
      return signSpan(fmt.color, fst, parenthesise(fmt.negParens, fst, `${body}%`));
    }

    // legacy styleMap.Currency
    case "Currency": {
      const body = fmt.symbol + String(roundTo(fst, fmt.places));
      return signSpan(fmt.color, fst, parenthesise(fmt.negParens, fst, body));
    }

    // legacy styleMap.Pr1: the inner format sees (fst, rest[0], rest.slice(1)).
    case "Pr1":
      return applyFormat(fmt.base, env, fst, rest[0], rest.slice(1));

    // not in the legacy styleMap.  The mirror of Pr1 (HTMLWriter.rawEval Pr2
    // formats the SECOND value with `base` and the first with Default).
    case "Pr2":
      return applyFormat(fmt.base, env, snd, rest[0], rest.slice(1));

    // legacy styleMap.DateRange
    case "DateRange":
      return isNullish(snd) ? (fst as Formatted) : `${String(fst)}–${String(snd)}`;

    // legacy styleMap.Round
    case "Round": {
      const body = numberFormat(fst as number, fmt.places, env.decimalPoint, "");
      return signSpan(fmt.color, fst, parenthesise(fmt.negParens, fst, body));
    }

    // legacy styleMap.IntegralRound -- a NUMBER when neither flag is set, which is
    // what the legacy returns and what the sort key wants
    case "IntegralRound": {
      const n = roundTo(fst, fmt.places);
      if (!fmt.color && !fmt.negParens) return n;
      return signSpan(fmt.color, fst, parenthesise(fmt.negParens, fst, String(n)));
    }

    // legacy styleMap.Truncate
    case "Truncate": {
      const s = env.unhtml(String(fst));
      return s.length > fmt.places
        ? `${s.substr(0, Math.max(2, fmt.places - 3))}…`
        : s;
    }

    // not in the legacy styleMap.  HTMLWriter.htmlEval: recursiveEval, i.e. pick a
    // branch by the condition on the FIRST value and format with it.
    case "Conditional":
      return applyFormat(
        evalCondition(fmt.condition, fst) ? fmt.whenTrue : fmt.whenFalse,
        env, fst, snd, rest,
      );

    // not in the legacy styleMap.  HTMLWriter.htmlEval wraps the formatted text in
    // the same two spans it substitutes for its <COLOR_FORMAT> markers.
    case "Color": {
      const inner = applyFormat(fmt.base, env, fst, snd, rest);
      return (
        `<span class="foreground" style="color: ${colorHex(fmt.fg)};">` +
        `<span class="background" style="background-color: ${colorHex(fmt.bg)};">` +
        `${String(inner)}</span></span>`
      );
    }

    // legacy styleMap.Alias, over a list of pairs instead of an object.  The
    // legacy builds `{k: v}` and reads `aliases[fst] || fst`, so a REPEATED key
    // takes the LAST pair's value and an empty alias falls back to the value --
    // both reproduced here.  (The legacy also answers Object.prototype's member
    // for a key like "constructor" or "__proto__"; the list walk does not, which
    // is the one place the port is deliberately not bug-compatible.)
    case "Alias": {
      const key = String(fst);
      let hit: string | undefined;
      for (const [from, to] of fmt.aliases) if (from === key) hit = to;
      return hit || (fst as Formatted);
    }
  }
}

function isNullish(v: unknown): boolean {
  return v === null || v === undefined;
}

/** Every tag `applyFormat` handles.  test/format.test.ts checks this against the
 *  generated zod so a case added in Ermine cannot be forgotten here. */
export const CELL_FORMAT_TAGS = [
  "Default", "Verbatim", "Markdown", "Constant", "Percentage", "Currency",
  "Pr1", "Pr2", "DateRange", "Round", "IntegralRound", "Truncate",
  "Conditional", "Color", "Alias",
] as const;
