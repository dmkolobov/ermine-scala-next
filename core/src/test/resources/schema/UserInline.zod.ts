// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/Inline (|sfDate, sfInt, sfNote|)
// zod 3

import { z } from "zod";

export const Schema = z.object({ kind: z.literal("inline"), columns: z.tuple([z.object({ name: z.literal("sfDate"), type: z.literal("Date"), nullable: z.literal(false) }).strict(), z.object({ name: z.literal("sfInt"), type: z.literal("Int"), nullable: z.literal(false) }).strict(), z.object({ name: z.literal("sfNote"), type: z.literal("String"), nullable: z.literal(true) }).strict()]), rows: z.array(z.tuple([z.string().date(), z.number().int(), z.string().nullable()])), rowCount: z.number().int().min(0) }).strict();
export type Schema = z.infer<typeof Schema>;
