// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.BorderOptions/BorderOptions Int
// zod 3

import { z } from "zod";

export const Layout_BorderOptions_BorderOptions_Int = z.object({ tag: z.literal("BorderOptions"), args: z.tuple([z.number().int().nullable(), z.number().int().nullable(), z.number().int().nullable(), z.number().int().nullable()]) }).strict();
export type Layout_BorderOptions_BorderOptions_Int = z.infer<typeof Layout_BorderOptions_BorderOptions_Int>;

export const Schema = Layout_BorderOptions_BorderOptions_Int;
export type Schema = z.infer<typeof Schema>;
