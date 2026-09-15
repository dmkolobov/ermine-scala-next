// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Relation.Sort/SortOrder
// zod 3

import { z } from "zod";

export const Relation_Sort_SortOrder = z.enum(["Ascending", "Descending"]);
export type Relation_Sort_SortOrder = z.infer<typeof Relation_Sort_SortOrder>;

export const Schema = Relation_Sort_SortOrder;
export type Schema = z.infer<typeof Schema>;
