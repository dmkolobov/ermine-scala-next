// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/[..(|sfDate, sfInt, sfString|)]
// zod 3

import { z } from "zod";

export const Schema = z.object({ columns: z.tuple([z.object({ name: z.literal("sfDate"), type: z.literal("Date") }).strict(), z.object({ name: z.literal("sfInt"), type: z.literal("Int") }).strict(), z.object({ name: z.literal("sfString"), type: z.literal("String") }).strict()]), rows: z.array(z.tuple([z.string().date(), z.number().int(), z.string()])) }).strict();
export type Schema = z.infer<typeof Schema>;
