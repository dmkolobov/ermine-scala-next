// The response envelope (tracker/JSON-STAGE3-PLAN.md, "Wire contract"):
//
//   {"version": 1, "settings": {..}, "root": <Layout.Doc.Node>}
//
// `settings` is whatever the runner is configured with, written verbatim and
// opaque to the dispatcher; `errors` is reserved as a LAST top-level key for the
// Streamed strategy and is not in v1, so the envelope is `.strict()` -- a document
// carrying one is refused here rather than silently ignored.

import { z } from "zod";
import { DocNodeSchema } from "./generated/widgets";
import type { DocNode } from "./generated/widgets";
import { zodMessage } from "./relation";

export const DOCUMENT_VERSION = 1;

export const DocumentSchema = z
  .object({
    version: z.literal(DOCUMENT_VERSION),
    settings: z.record(z.unknown()),
    root: DocNodeSchema,
  })
  .strict();

export interface ReportDocument {
  version: typeof DOCUMENT_VERSION;
  settings: Record<string, unknown>;
  root: DocNode;
}

export class DocumentError extends Error {
  readonly issues: z.ZodIssue[];
  constructor(message: string, issues: z.ZodIssue[]) {
    super(message);
    this.name = "DocumentError";
    this.issues = issues;
  }
}

export type ParseResult =
  | { ok: true; document: ReportDocument }
  | { ok: false; error: DocumentError };

/** Validate a decoded JSON value as a report document.  Never throws. */
export function safeParseDocument(value: unknown): ParseResult {
  const parsed = DocumentSchema.safeParse(value);
  if (parsed.success) {
    return { ok: true, document: parsed.data as unknown as ReportDocument };
  }
  return {
    ok: false,
    error: new DocumentError(`not a report document -- ${zodMessage(parsed.error)}`, parsed.error.issues),
  };
}

/** As `safeParseDocument`, but throws a `DocumentError`.  Accepts the response
 *  TEXT as well as a decoded value, so a caller can hand it `await res.text()`. */
export function parseDocument(value: unknown): ReportDocument {
  let decoded = value;
  if (typeof value === "string") {
    try {
      decoded = JSON.parse(value);
    } catch (e) {
      throw new DocumentError(`not JSON: ${(e as Error).message}`, []);
    }
  }
  const result = safeParseDocument(decoded);
  if (!result.ok) throw result.error;
  return result.document;
}
