// Incremental RFC 4180 reader for the generator's CSVs (src/lib/csv.ts writes
// them): LF rows, `"` quoting with doubled quotes, NULL = an EMPTY UNQUOTED
// field (returned as null), an empty STRING = `""` (returned as "").  Fed in
// chunks so a 2 M-line fact table never has to sit in memory as one string.

import { createReadStream } from "node:fs";

export type Field = string | null;

export class CsvReader {
  private state = 0;            // 0 field start, 1 unquoted, 2 quoted, 3 quote inside quoted
  private buf = "";
  private quoted = false;
  private row: Field[] = [];
  private out: Field[][] = [];
  line = 1;

  /** Feed a chunk; returns the rows it completed. */
  push(chunk: string): Field[][] {
    for (let i = 0; i < chunk.length; i++) {
      const c = chunk[i]!;
      switch (this.state) {
        case 0:
          if (c === '"') { this.state = 2; this.quoted = true; }
          else if (c === ",") this.endField();
          else if (c === "\n") { this.endField(); this.endRow(); }
          else if (c === "\r") throw new Error(`csv line ${this.line}: CR found (the loaders take LF-only files)`);
          else { this.buf += c; this.state = 1; }
          break;
        case 1:
          if (c === ",") this.endField();
          else if (c === "\n") { this.endField(); this.endRow(); }
          else if (c === '"' || c === "\r") throw new Error(`csv line ${this.line}: ${c === "\r" ? "CR" : "a bare quote"} in an unquoted field`);
          else this.buf += c;
          break;
        case 2:
          if (c === '"') this.state = 3;
          else { if (c === "\n") this.line++; this.buf += c; }
          break;
        case 3:
          if (c === '"') { this.buf += '"'; this.state = 2; }
          else if (c === ",") this.endField();
          else if (c === "\n") { this.endField(); this.endRow(); }
          else throw new Error(`csv line ${this.line}: ${JSON.stringify(c)} after a closing quote`);
          break;
      }
    }
    const done = this.out; this.out = [];
    return done;
  }

  /** End of input: flushes a last row that lacks its LF. */
  end(): Field[][] {
    if (this.state === 2) throw new Error(`csv line ${this.line}: unterminated quoted field`);
    if (this.state !== 0 || this.row.length > 0) { this.endField(); this.endRow(); }
    const done = this.out; this.out = [];
    return done;
  }

  private endField(): void {
    this.row.push(this.quoted ? this.buf : this.buf === "" ? null : this.buf);
    this.buf = ""; this.quoted = false; this.state = 0;
  }

  private endRow(): void { this.out.push(this.row); this.row = []; this.line++; }
}

export function parseAll(text: string): Field[][] {
  const r = new CsvReader();
  return [...r.push(text), ...r.end()];
}

/** Stream a CSV file row by row (the header is row 0). */
export async function* csvRows(path: string): AsyncGenerator<Field[]> {
  const r = new CsvReader();
  const s = createReadStream(path, { encoding: "utf8", highWaterMark: 1 << 20 });
  for await (const chunk of s) for (const row of r.push(chunk as string)) yield row;
  for (const row of r.end()) yield row;
}
