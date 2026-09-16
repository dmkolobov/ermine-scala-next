// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/[..(|sfDate, sfInt, sfString|)]
// zod 3

import { z } from "zod";

export const Schema = z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.tuple([z.object({ name: z.literal("sfDate"), type: z.literal("Date"), nullable: z.literal(false) }).strict(), z.object({ name: z.literal("sfInt"), type: z.literal("Int"), nullable: z.literal(false) }).strict(), z.object({ name: z.literal("sfString"), type: z.literal("String"), nullable: z.literal(false) }).strict()]), rows: z.array(z.tuple([z.string().date(), z.number().int(), z.string()])), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.tuple([z.object({ name: z.literal("sfDate"), type: z.literal("Date"), nullable: z.literal(false) }).strict(), z.object({ name: z.literal("sfInt"), type: z.literal("Int"), nullable: z.literal(false) }).strict(), z.object({ name: z.literal("sfString"), type: z.literal("String"), nullable: z.literal(false) }).strict()]), token: z.string().min(1), expires: z.string().datetime() }).strict()]);
export type Schema = z.infer<typeof Schema>;
