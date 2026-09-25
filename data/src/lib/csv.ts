// RFC 4180 CSV, UTF-8 without BOM, LF line endings (RFC 4180 says CRLF; the
// loaders take LF, and the plan fixes LF -- DB-PLAN / the generator brief).
// A field is quoted when it contains a comma, a quote, CR or LF, or leading /
// trailing whitespace; quotes are doubled.  NULL is the EMPTY UNQUOTED field;
// an empty STRING is written as "" (quoted) so the two stay distinguishable.

export type Cell = string | number | boolean | null;

export function field(v: Cell): string {
  if (v === null) return "";
  if (typeof v === "boolean") return v ? "1" : "0";
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error(`csv: non-finite number ${v}`);
    return numberText(v);
  }
  if (v === "" || /[",\r\n]/.test(v) || /^\s|\s$/.test(v)) return `"${v.replace(/"/g, '""')}"`;
  return v;
}

/** Plain decimal notation, `.` separator, never exponent form. */
export function numberText(v: number): string {
  if (Object.is(v, -0)) return "0";
  const s = String(v);
  if (!/e/i.test(s)) return s;
  // exponent form only happens for |v| < 1e-6 or >= 1e21; expand it
  if (Math.abs(v) >= 1e21) return BigInt(v).toString();
  return v.toFixed(20).replace(/0+$/, "").replace(/\.$/, "");
}

export function line(cells: readonly Cell[]): string { return cells.map(field).join(",") + "\n"; }

/** Parse our own CSV back (tests only): returns rows of raw fields, null for an unquoted empty field. */
export function parse(text: string): (string | null)[][] {
  const rows: (string | null)[][] = [];
  let row: (string | null)[] = [], i = 0;
  while (i < text.length) {
    if (text[i] === '"') {
      let v = ""; i++;
      for (;;) {
        const c = text[i];
        if (c === undefined) throw new Error("csv: unterminated quote");
        if (c === '"') { if (text[i + 1] === '"') { v += '"'; i += 2; continue; } i++; break; }
        v += c; i++;
      }
      row.push(v);
    } else {
      let j = i;
      while (j < text.length && text[j] !== "," && text[j] !== "\n") j++;
      const raw = text.slice(i, j);
      row.push(raw === "" ? null : raw);
      i = j;
    }
    if (text[i] === ",") { i++; if (i === text.length) row.push(null); continue; }
    if (text[i] === "\n") { rows.push(row); row = []; i++; continue; }
  }
  if (row.length) rows.push(row);
  return rows;
}
