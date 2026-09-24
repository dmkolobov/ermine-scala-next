// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Test/Tree
// zod 3

import { z } from "zod";

/** Test.Tree */
export type Test_Tree =
  | { tag: "Leaf"; args: [number] }
  | { tag: "Node"; args: [Test_Tree, Test_Tree] };
export const Test_Tree: z.ZodType<Test_Tree> = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Leaf"), args: z.tuple([z.number().int()]) }).strict(), z.object({ tag: z.literal("Node"), args: z.tuple([z.lazy(() => Test_Tree), z.lazy(() => Test_Tree)]) }).strict()]);

export const Schema = z.lazy(() => Test_Tree);
export type Schema = z.infer<typeof Schema>;
