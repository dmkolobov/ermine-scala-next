// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.Doc/Node
// zod 3

import { z } from "zod";

export const Layout_Doc_Node: z.ZodTypeAny = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Widget"), name: z.string(), props: z.unknown() }).strict(), z.object({ tag: z.literal("VFlow"), children: z.array(z.lazy(() => Layout_Doc_Node)) }).strict(), z.object({ tag: z.literal("HFlow"), children: z.array(z.lazy(() => Layout_Doc_Node)) }).strict(), z.object({ tag: z.literal("Grid"), cells: z.array(z.array(z.lazy(() => Layout_Doc_Node))) }).strict(), z.object({ tag: z.literal("Tabbed"), tabs: z.array(z.lazy(() => Layout_Doc_Tab)) }).strict()]);
export type Layout_Doc_Node = z.infer<typeof Layout_Doc_Node>;

export const Layout_Doc_Tab: z.ZodTypeAny = z.object({ label: z.string(), content: z.lazy(() => Layout_Doc_Node) }).strict();
export type Layout_Doc_Tab = z.infer<typeof Layout_Doc_Tab>;

export const Schema = z.lazy(() => Layout_Doc_Node);
export type Schema = z.infer<typeof Schema>;
