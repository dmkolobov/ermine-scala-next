// The wire form of a relation (tracker/JSON-STAGE3-PLAN.md, "Wire contract"), and
// the one place a deferred relation turns into rows.
//
//   inline    {"kind":"inline",   "columns":[col..], "rows":[[cell..]..], "rowCount":n}
//   deferred  {"kind":"deferred", "columns":[col..], "token":"..", "expires":".."}
//   col       {"name":"<column>", "type":<one of COLUMN_TYPES>, "nullable":<bool>}
//
// Columns are sorted by name and every row array follows that order.  The JSON type
// of a cell follows the column's `type`: Int/Short/Byte/Double are numbers, Bool a
// boolean, and Long/Date/Timestamp/GUID/String are STRINGS (a Long is a decimal
// string because JSON numbers lose precision past 2^53).  A null cell is `null`,
// whatever the column type.
//
// These types are hand-written rather than inferred from src/generated: the
// generated zod describes one relation position inside one prop type, while this is
// the vocabulary every widget shares.  src/generated is still the authority -- the
// dispatcher validates props with it before anything here runs, and
// test/generated.test.ts `(g-wire)` pins these declarations against the generated
// schema, at runtime and (mutual assignability) at compile time.

import { z } from "zod";

export const COLUMN_TYPES = [
  "Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp",
] as const;

export type ColumnType = (typeof COLUMN_TYPES)[number];

export interface WireColumn {
  name: string;
  type: ColumnType;
  nullable: boolean;
}

/** A cell as it travels: the column's `type` says how to read it. */
export type WireCell = string | number | boolean | null;

export interface InlineRelation {
  kind: "inline";
  columns: WireColumn[];
  rows: WireCell[][];
  rowCount: number;
}

export interface DeferredRelation {
  kind: "deferred";
  columns: WireColumn[];
  token: string;
  expires: string;
}

export type WireRelation = InlineRelation | DeferredRelation;

export const WireColumnSchema = z
  .object({ name: z.string(), type: z.enum(COLUMN_TYPES), nullable: z.boolean() })
  .strict();

export const InlineRelationSchema = z
  .object({
    kind: z.literal("inline"),
    columns: z.array(WireColumnSchema),
    rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))),
    rowCount: z.number().int().min(0),
  })
  .strict();

export const DeferredRelationSchema = z
  .object({
    kind: z.literal("deferred"),
    columns: z.array(WireColumnSchema),
    token: z.string().min(1),
    expires: z.string().datetime(),
  })
  .strict();

export const WireRelationSchema = z.discriminatedUnion("kind", [
  InlineRelationSchema,
  DeferredRelationSchema,
]);

/** True for anything shaped like a relation on the wire, inline or deferred.
 *
 *  Deliberately narrow.  `resolveRelations` uses this to decide, STRUCTURALLY,
 *  which sub-object of a widget's props is a relation, and a false positive is
 *  silent and confusing: an inline-looking record is handed to the widget
 *  untouched and never descended into, a deferred-looking one sends a
 *  `GET /data/<whatever that object's `token` was>`.  `kind` alone would be far
 *  too weak -- `TableColumn` already has a field named `kind` -- so every key of
 *  the arm is required, with the right JSON type, and `columns` must hold column
 *  DESCRIPTORS.  A props record would have to reproduce a whole relation arm to
 *  be mistaken for one. */
export function isWireRelation(x: unknown): x is WireRelation {
  if (x === null || typeof x !== "object" || Array.isArray(x)) return false;
  const o = x as Record<string, unknown>;
  if (!Array.isArray(o["columns"]) || !o["columns"].every(isWireColumn)) return false;
  if (o["kind"] === "inline") {
    return Array.isArray(o["rows"]) && typeof o["rowCount"] === "number";
  }
  if (o["kind"] === "deferred") {
    return typeof o["token"] === "string" && typeof o["expires"] === "string";
  }
  return false;
}

function isWireColumn(c: unknown): boolean {
  if (c === null || typeof c !== "object" || Array.isArray(c)) return false;
  const o = c as Record<string, unknown>;
  return typeof o["name"] === "string" && typeof o["nullable"] === "boolean" &&
    typeof o["type"] === "string" && (COLUMN_TYPES as readonly string[]).includes(o["type"]);
}

/** Fetches the rows behind a deferred token.  Injectable: the dispatcher never
 *  touches `globalThis.fetch` itself. */
export type FetchData = (token: string) => Promise<InlineRelation>;

/** `GET <baseUrl>/data/<token>`, the runner's re-request endpoint (J3c).  The
 *  response body is exactly the inline object for that relation. */
export function httpFetchData(
  baseUrl: string,
  doFetch: (url: string) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>,
): FetchData {
  const base = baseUrl.replace(/\/+$/, "");
  return async (token: string): Promise<InlineRelation> => {
    const res = await doFetch(`${base}/data/${encodeURIComponent(token)}`);
    if (!res.ok) throw new Error(`GET ${base}/data/<token> failed with ${res.status}`);
    const parsed = InlineRelationSchema.safeParse(await res.json());
    if (!parsed.success) {
      throw new Error(`GET ${base}/data/<token> did not answer an inline relation: ${zodMessage(parsed.error)}`);
    }
    return parsed.data;
  };
}

/** A deferred relation becomes an inline one; an inline one is returned as is.
 *  The re-request RE-SCANS the plan, and Ermine relations carry no order, so the
 *  ROWS are the same but the ORDER need not be (report-J3b.md). */
export async function resolveRelation(rel: WireRelation, fetchData: FetchData): Promise<InlineRelation> {
  if (rel.kind === "inline") return rel;
  const inline = await fetchData(rel.token);
  return inline;
}

/** A props type AFTER `resolveRelations`: the same type with every deferred
 *  relation arm removed, so each relation position is the inline arm.  The
 *  generated props types (src/generated/widgets.ts) carry the WIRE relation, a
 *  bare relation being `inline | deferred`; a renderer is handed
 *  `Resolved<WidgetRegistry[K]>` (dispatcher.ts `Widget`), never a deferred one.
 *  Structural, like `resolveRelations`: a widget added later needs nothing here. */
export type Resolved<T> =
  T extends { kind: "deferred"; token: string; expires: string } ? never
  : T extends object ? { [K in keyof T]: Resolved<T[K]> }
  : T;

/** Deep-walks a props value and replaces every deferred relation in it with the
 *  inline one its token resolves to.  Structural, so a widget added later needs no
 *  change here and J3e's chart props resolve for free. */
export async function resolveRelations<T>(props: T, fetchData: FetchData): Promise<Resolved<T>> {
  if (Array.isArray(props)) {
    const out = await Promise.all(props.map((v) => resolveRelations(v, fetchData)));
    return out as unknown as Resolved<T>;
  }
  if (props !== null && typeof props === "object") {
    if (isWireRelation(props)) {
      return (await resolveRelation(props, fetchData)) as unknown as Resolved<T>;
    }
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(props as Record<string, unknown>)) {
      out[k] = await resolveRelations(v, fetchData);
    }
    return out as unknown as Resolved<T>;
  }
  return props as Resolved<T>;
}

/** Index of a column by name, or -1. */
export function columnIndex(rel: { columns: WireColumn[] }, name: string): number {
  return rel.columns.findIndex((c) => c.name === name);
}

/** The rows of an inline relation as name-keyed records. */
export function rowRecords(rel: InlineRelation): Record<string, WireCell>[] {
  return rel.rows.map((row) => {
    const rec: Record<string, WireCell> = {};
    rel.columns.forEach((c, i) => {
      rec[c.name] = i < row.length ? (row[i] as WireCell) : null;
    });
    return rec;
  });
}

/** A one-line rendering of a zod error: the first issue with its path. */
export function zodMessage(err: z.ZodError): string {
  const first = err.issues[0];
  if (!first) return "invalid";
  const path = first.path.length ? first.path.join(".") : "<root>";
  return `${path}: ${first.message}`;
}
