// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/TableProps r
// zod 3

import { z } from "zod";

export const Test_TableProps__ = z.object({ title: z.string(), rows: z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), detail: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Test_TableProps__ = z.infer<typeof Test_TableProps__>;

export const Schema = Test_TableProps__;
export type Schema = z.infer<typeof Schema>;
