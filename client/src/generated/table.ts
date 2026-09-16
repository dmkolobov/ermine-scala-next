// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.Widgets.Table/TableProps r
// zod 3

import { z } from "zod";

export const Layout_Widgets_Format_RGB = z.object({ red: z.number().int(), green: z.number().int(), blue: z.number().int() }).strict();
export type Layout_Widgets_Format_RGB = z.infer<typeof Layout_Widgets_Format_RGB>;

export const Layout_Widgets_Format_Threshold = z.discriminatedUnion("tag", [z.object({ tag: z.literal("TNum"), args: z.tuple([z.number()]) }).strict(), z.object({ tag: z.literal("TStr"), args: z.tuple([z.string()]) }).strict(), z.object({ tag: z.literal("TBool"), args: z.tuple([z.boolean()]) }).strict()]);
export type Layout_Widgets_Format_Threshold = z.infer<typeof Layout_Widgets_Format_Threshold>;

export const Layout_Widgets_Table_ColumnAlign = z.enum(["AlignLeft", "AlignRight"]);
export type Layout_Widgets_Table_ColumnAlign = z.infer<typeof Layout_Widgets_Table_ColumnAlign>;

export const Layout_Widgets_Table_ColumnKind = z.enum(["NumberColumn", "DateColumn", "OtherColumn"]);
export type Layout_Widgets_Table_ColumnKind = z.infer<typeof Layout_Widgets_Table_ColumnKind>;

export const Layout_Widgets_Table_ColumnSort = z.object({ sortColumn: z.number().int(), descending: z.boolean() }).strict();
export type Layout_Widgets_Table_ColumnSort = z.infer<typeof Layout_Widgets_Table_ColumnSort>;

export const Layout_Widgets_Format_CellCondition: z.ZodTypeAny = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Gt"), gt: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Lt"), lt: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Eq"), eq: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Gte"), gte: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Lte"), lte: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("And"), and: z.tuple([z.lazy(() => Layout_Widgets_Format_CellCondition), z.lazy(() => Layout_Widgets_Format_CellCondition)]) }).strict()]);
export type Layout_Widgets_Format_CellCondition = z.infer<typeof Layout_Widgets_Format_CellCondition>;

export const Layout_Widgets_Format_CellFormat: z.ZodTypeAny = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Default"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Verbatim"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Markdown"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Constant"), value: z.string() }).strict(), z.object({ tag: z.literal("Percentage"), color: z.boolean(), negParens: z.boolean(), places: z.number().int(), pad: z.boolean() }).strict(), z.object({ tag: z.literal("Currency"), color: z.boolean(), negParens: z.boolean(), symbol: z.string(), places: z.number().int() }).strict(), z.object({ tag: z.literal("Pr1"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Pr2"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("DateRange"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Round"), color: z.boolean(), negParens: z.boolean(), places: z.number().int() }).strict(), z.object({ tag: z.literal("IntegralRound"), color: z.boolean(), negParens: z.boolean(), places: z.number().int() }).strict(), z.object({ tag: z.literal("Truncate"), places: z.number().int() }).strict(), z.object({ tag: z.literal("Conditional"), condition: z.lazy(() => Layout_Widgets_Format_CellCondition), whenTrue: z.lazy(() => Layout_Widgets_Format_CellFormat), whenFalse: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Color"), bg: Layout_Widgets_Format_RGB, fg: Layout_Widgets_Format_RGB, base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Alias"), aliases: z.array(z.tuple([z.string(), z.string()])) }).strict()]);
export type Layout_Widgets_Format_CellFormat = z.infer<typeof Layout_Widgets_Format_CellFormat>;

export const Layout_Widgets_Table_TableColumn = z.object({ column: z.string(), header: z.string(), cellFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), align: Layout_Widgets_Table_ColumnAlign, kind: Layout_Widgets_Table_ColumnKind }).strict();
export type Layout_Widgets_Table_TableColumn = z.infer<typeof Layout_Widgets_Table_TableColumn>;

export const Layout_Widgets_Table_TableProps__ = z.object({ columns: z.array(Layout_Widgets_Table_TableColumn), rowGroup: z.number().int().optional(), sorts: z.array(Layout_Widgets_Table_ColumnSort), paginate: z.boolean(), scroll: z.boolean(), rows: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Layout_Widgets_Table_TableProps__ = z.infer<typeof Layout_Widgets_Table_TableProps__>;

export const Schema = Layout_Widgets_Table_TableProps__;
export type Schema = z.infer<typeof Schema>;
