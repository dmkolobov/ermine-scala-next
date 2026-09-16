// Generated from Ermine by com.clarifi.reporting.ermine.json.Zod -- do not edit.
// source: ermine:Layout.Widgets.DrilldownBar/DrilldownBarProps r
// zod 3

import { z } from "zod";

export const Layout_Widgets_Chart_ChartRenderHints = z.object({ enableDataLabels: z.boolean() }).strict();
export type Layout_Widgets_Chart_ChartRenderHints = z.infer<typeof Layout_Widgets_Chart_ChartRenderHints>;

export const Layout_Widgets_Chart_ChartVariant = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Line"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Bar"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Step"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Scatter"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("StackedBar"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("StackedArea"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("BoxAndWhiskers"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Bubble"), zLabel: z.string() }).strict()]);
export type Layout_Widgets_Chart_ChartVariant = z.infer<typeof Layout_Widgets_Chart_ChartVariant>;

export const Layout_Widgets_Chart_DisplayScale = z.enum(["Linear", "Logarithmic"]);
export type Layout_Widgets_Chart_DisplayScale = z.infer<typeof Layout_Widgets_Chart_DisplayScale>;

export const Layout_Widgets_Chart_LegendLocation = z.enum(["LegendDefault", "LegendAbove", "LegendOverlay", "LegendRightOverlay", "LegendRightNotOverlay", "LegendRightTable", "LegendHidden"]);
export type Layout_Widgets_Chart_LegendLocation = z.infer<typeof Layout_Widgets_Chart_LegendLocation>;

export const Layout_Widgets_Chart_Orientation = z.enum(["Vertical", "Horizontal"]);
export type Layout_Widgets_Chart_Orientation = z.infer<typeof Layout_Widgets_Chart_Orientation>;

export const Layout_Widgets_Chart_ScalarType: z.ZodTypeAny = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Scalar"), typeName: z.string(), typeNumeric: z.boolean() }).strict(), z.object({ tag: z.literal("Compound"), componentTypes: z.array(z.lazy(() => Layout_Widgets_Chart_ScalarType)) }).strict()]);
export type Layout_Widgets_Chart_ScalarType = z.infer<typeof Layout_Widgets_Chart_ScalarType>;

export const Layout_Widgets_Chart_SortDir = z.enum(["Asc", "Desc"]);
export type Layout_Widgets_Chart_SortDir = z.infer<typeof Layout_Widgets_Chart_SortDir>;

export const Layout_Widgets_Format_RGB = z.object({ red: z.number().int(), green: z.number().int(), blue: z.number().int() }).strict();
export type Layout_Widgets_Format_RGB = z.infer<typeof Layout_Widgets_Format_RGB>;

export const Layout_Widgets_Format_Threshold = z.discriminatedUnion("tag", [z.object({ tag: z.literal("TNum"), args: z.tuple([z.number()]) }).strict(), z.object({ tag: z.literal("TStr"), args: z.tuple([z.string()]) }).strict(), z.object({ tag: z.literal("TBool"), args: z.tuple([z.boolean()]) }).strict()]);
export type Layout_Widgets_Format_Threshold = z.infer<typeof Layout_Widgets_Format_Threshold>;

export const Layout_Widgets_Chart_AxisConstraints = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Scaled"), lowerBound: z.number().optional(), upperBound: z.number().optional(), displayScale: Layout_Widgets_Chart_DisplayScale }).strict(), z.object({ tag: z.literal("Unscaled"), sortOrders: z.array(Layout_Widgets_Chart_SortDir), tickOverrides: z.array(z.tuple([z.string(), z.string()])) }).strict()]);
export type Layout_Widgets_Chart_AxisConstraints = z.infer<typeof Layout_Widgets_Chart_AxisConstraints>;

export const Layout_Widgets_Chart_ChartLegendOptions = z.object({ legendLocation: Layout_Widgets_Chart_LegendLocation }).strict();
export type Layout_Widgets_Chart_ChartLegendOptions = z.infer<typeof Layout_Widgets_Chart_ChartLegendOptions>;

export const Layout_Widgets_Format_CellCondition: z.ZodTypeAny = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Gt"), gt: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Lt"), lt: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Eq"), eq: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Gte"), gte: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Lte"), lte: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("And"), and: z.tuple([z.lazy(() => Layout_Widgets_Format_CellCondition), z.lazy(() => Layout_Widgets_Format_CellCondition)]) }).strict()]);
export type Layout_Widgets_Format_CellCondition = z.infer<typeof Layout_Widgets_Format_CellCondition>;

export const Layout_Widgets_Format_CellFormat: z.ZodTypeAny = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Default"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Verbatim"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Markdown"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Constant"), value: z.string() }).strict(), z.object({ tag: z.literal("Percentage"), color: z.boolean(), negParens: z.boolean(), places: z.number().int(), pad: z.boolean() }).strict(), z.object({ tag: z.literal("Currency"), color: z.boolean(), negParens: z.boolean(), symbol: z.string(), places: z.number().int() }).strict(), z.object({ tag: z.literal("Pr1"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Pr2"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("DateRange"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Round"), color: z.boolean(), negParens: z.boolean(), places: z.number().int() }).strict(), z.object({ tag: z.literal("IntegralRound"), color: z.boolean(), negParens: z.boolean(), places: z.number().int() }).strict(), z.object({ tag: z.literal("Truncate"), places: z.number().int() }).strict(), z.object({ tag: z.literal("Conditional"), condition: z.lazy(() => Layout_Widgets_Format_CellCondition), whenTrue: z.lazy(() => Layout_Widgets_Format_CellFormat), whenFalse: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Color"), bg: Layout_Widgets_Format_RGB, fg: Layout_Widgets_Format_RGB, base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Alias"), aliases: z.array(z.tuple([z.string(), z.string()])) }).strict()]);
export type Layout_Widgets_Format_CellFormat = z.infer<typeof Layout_Widgets_Format_CellFormat>;

export const Layout_Widgets_Chart_ChartAxis = z.object({ axisLabel: z.string(), tooltipLabel: z.string(), axisFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), scalarType: z.lazy(() => Layout_Widgets_Chart_ScalarType), showTicks: z.boolean(), constraints: Layout_Widgets_Chart_AxisConstraints }).strict();
export type Layout_Widgets_Chart_ChartAxis = z.infer<typeof Layout_Widgets_Chart_ChartAxis>;

export const Layout_Widgets_Chart_ChartSeries = z.object({ seriesColumns: z.array(z.string()), categoryColumns: z.array(z.string()), valueColumn: z.string(), extraColumns: z.array(z.string()), colorColumn: z.string().optional(), seriesFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), extraFormats: z.array(z.lazy(() => Layout_Widgets_Format_CellFormat)), variant: Layout_Widgets_Chart_ChartVariant }).strict();
export type Layout_Widgets_Chart_ChartSeries = z.infer<typeof Layout_Widgets_Chart_ChartSeries>;

export const Layout_Widgets_Chart_ChartMeta = z.object({ chartTitle: z.string(), domainAxis: Layout_Widgets_Chart_ChartAxis, rangeAxis: Layout_Widgets_Chart_ChartAxis, orientation: Layout_Widgets_Chart_Orientation, legendOptions: Layout_Widgets_Chart_ChartLegendOptions, renderHints: Layout_Widgets_Chart_ChartRenderHints }).strict();
export type Layout_Widgets_Chart_ChartMeta = z.infer<typeof Layout_Widgets_Chart_ChartMeta>;

export const Layout_Widgets_DrilldownBar_DrilldownBarProps__ = z.object({ barMeta: Layout_Widgets_Chart_ChartMeta, barSeries: Layout_Widgets_Chart_ChartSeries, barParentColumn: z.string(), barChildColumn: z.string(), barRows: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Layout_Widgets_DrilldownBar_DrilldownBarProps__ = z.infer<typeof Layout_Widgets_DrilldownBar_DrilldownBarProps__>;

export const Schema = Layout_Widgets_DrilldownBar_DrilldownBarProps__;
export type Schema = z.infer<typeof Schema>;
