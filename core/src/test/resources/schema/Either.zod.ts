// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Either/Either String Int
// zod 3

import { z } from "zod";

export const Either_Either_String_Int = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Left"), args: z.tuple([z.string()]) }).strict(), z.object({ tag: z.literal("Right"), args: z.tuple([z.number().int()]) }).strict()]);
export type Either_Either_String_Int = z.infer<typeof Either_Either_String_Int>;

export const Schema = Either_Either_String_Int;
export type Schema = z.infer<typeof Schema>;
