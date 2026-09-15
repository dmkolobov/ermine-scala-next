// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Ord/Ordering
// zod 3

import { z } from "zod";

export const Ord_Ordering = z.enum(["LT", "EQ", "GT"]);
export type Ord_Ordering = z.infer<typeof Ord_Ordering>;

export const Schema = Ord_Ordering;
export type Schema = z.infer<typeof Schema>;
