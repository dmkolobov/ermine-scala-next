// Written by client/scripts/generate.sh -- do not edit; run it again instead.
// generator sha256 fd620fc9b2709307610e341ba9b147fba536ff2aa08e038ce04061bd20bd9b6a core/src/main/scala/com/clarifi/reporting/ermine/json/Schema.scala
// generator sha256 945ed57841a8286d214ab99b09ea7ff1b0cbddc52b9558d8a460fdfd0e9d7192 core/src/main/scala/com/clarifi/reporting/ermine/json/SchemaMain.scala
// generator sha256 86cb46708f035d0540e7b5f9ef9b73ffed587f2aff800bd7e5119ea823e173e8 core/src/main/scala/com/clarifi/reporting/ermine/json/Zod.scala
// body sha256: 3bb927b6058ba9f60b61076f2e7100b6ec9dae47bb2f8d9d3576656aab670cd4
// Generated from Ermine by bin/ermine-schema (com.clarifi.reporting.ermine.json.Zod) -- do not edit.
// command: bin/ermine-schema --widgets Layout.Widgets Layout.Doc:Node=DocNode Layout.Doc:Tab=DocTab
//
// scanned for `WidgetName T` terms: Layout.Widgets and every module under its directory
//   Layout.Widgets               treeMap : no props (Unsupported)
//   Layout.Widgets.AxisChart     axisChart : AxisChartProps r
//   Layout.Widgets.Chart         no WidgetName term: not a widget
//   Layout.Widgets.Crosstab      crosstab : CrosstabProps
//   Layout.Widgets.Drilldown     drilldownTable : DrilldownTableProps r
//   Layout.Widgets.DrilldownBar  drilldownBar : DrilldownBarProps r
//   Layout.Widgets.Format        no WidgetName term: not a widget
//   Layout.Widgets.Heading       heading : HeadingProps
//   Layout.Widgets.Headline      headline : HeadlineProps
//   Layout.Widgets.PieChart      drilldownPieChart : PieChartProps r, pieChart : PieChartProps r
//   Layout.Widgets.Scorecard     scorecard : ScorecardProps r
//   Layout.Widgets.StyleBox      styleBox : StyleBoxProps r
//   Layout.Widgets.Table         table : TableProps r
//   Layout.Widgets.Text          text : TextProps
//
// sources: the sha256 of every .e file this run read, by path under core/src/main/resources/modules
// sha256 33db3a3d6875a0dea28dec656536ea27d4cea6a0842cd1e74a3a883953a2cbea Bool.e
// sha256 221c29a3a5ef3d1b4694f63254500e0ecdf35f62cc015d9b589dfb3147d16189 Constraint.e
// sha256 29b25593ddd690e47835bff509b88030a9d0bb5f1b0b111f79b2199a33206ba2 Control/Alt.e
// sha256 da83bf09180c71ab282ed6a064a1f0157ef423707882935e203fd126933edec8 Control/Ap.e
// sha256 45601357c5738a8cb2ba064eca307c0538d3b60e93b8bea4dd675f932e60a30d Control/Category.e
// sha256 cad254dc8b50ace2bcdef3ddb15b77d47fdebf33e9611eb863388bdc9720d866 Control/Functor.e
// sha256 7a9daf8de041e0157def474169b01401c3c3b9a5d3b3ba833db8235ab595dc9f Control/Monad.e
// sha256 29fe684c636df70ead587cd4bf0558ac5ca75d44f8ff39f108e5eaaee56eb962 Control/Monad/Cont.e
// sha256 676e3efa7904d969c76781a1a8b6a070bab3505b468123e640f84a5263410e52 Control/Monoid.e
// sha256 f7c74bdda3f73ff2cc3d4c958eba7327580daf6f5deedd092e5c122907ea7aaa Control/Traversable.e
// sha256 cd71cbabbe6aa3221232f00ddbedf50d54e52700f9dce7084528f8b255dede7e Date.e
// sha256 9c879c57ebb8d73ccb7b6ce80cbe363248a0f517ed12fb463b86df2754a782da Double.e
// sha256 235ae8c838df91df743b54f9f6eeff27e00be1da4d529eef08ab86315fcbc549 Either.e
// sha256 26b9a44dd2544f796e50f655a9365506e3b98099592f32c8eec11fff2b830429 Eq.e
// sha256 169b8135844725bddb7ab369b2f1316b6208be50084c7ddb85538220cb13a22d Error.e
// sha256 477994a2b2a2308a712e28b98b7329e487c84ed3f59a38d2e9a146e78f56bdf8 Field.e
// sha256 f65be14efb3f4317d64d0421024c779d40f288480c825fea68709c7477e8d43a Field/Type.e
// sha256 fff88c5b0578f6d3430aa08f83c7455aaa17f337544887854dc5c87712c72f2a Function.e
// sha256 c1b25fb7463df81ac4fc20bd8ea6276633afb503a547ceba22e0cf40ee939e5b Function/Endo.e
// sha256 dbade05eae63cf1ddfaa5c5a33276b43898899d2f53b306cf1f647908887e52c GUID.e
// sha256 5b25139939a4395f0c31f74a2a8ad7f91c388258de98f7f1e542c70cbab52fc0 IO.e
// sha256 720b53a09797b9fe00a51f92cf3e4602c4575ad98ab1dcaf4450fc75cfd76bac IO/Unsafe.e
// sha256 f1fd0e59997e415d4ee53be40502f995331a92df10a6211baa8de65fb74645ab Int.e
// sha256 d9b0166aa330d0b37320ff23502d7317356396e8fba3463bf00ba4dbd786abdd Json.e
// sha256 b84bf1d0f3d427e81e5cef22f0ec38423f65783859e892a0e386bb58f00ea7be Layout/BorderOptions.e
// sha256 34815e30f92b2c2737c9cf86a26afd2f575a7f559edf9077851f16b9fcb21011 Layout/Doc.e
// sha256 64401b6c1b5851c206b365486b7a5e9c6a6906665ab48cdd9f30395f6150e802 Layout/Fetch.e
// sha256 edbba15a542cf3164cfde2cb99ea42ad3279025020e2bfebb42f5e66dd19132a Layout/Widgets.e
// sha256 38eaab87a929fd272e9e7a7325d0651ad38446145d177ecca5f5462fc304fb48 Layout/Widgets/AxisChart.e
// sha256 06eee101ed74664f32cf2184929751994bdcb7699d341f7d889d784ed11739a6 Layout/Widgets/Chart.e
// sha256 b2b330cb8abe56908646cea0da519dfe657411524f61491bdbe83bdaa5efe268 Layout/Widgets/Crosstab.e
// sha256 9dfcda07d769a51535759eabb082ffa170988b8d2e8c68590d37da4bc209c3a1 Layout/Widgets/Drilldown.e
// sha256 8a9f59009f2a832d748390ddce3cf0b28089b18df5b417831bdbf059420fbed0 Layout/Widgets/DrilldownBar.e
// sha256 5a0e9ceb846e7697af30e692f96579d88bbc27d263a210cfa8ea0156d2b03ab2 Layout/Widgets/Format.e
// sha256 f771f97fdd5ec915b0929a00f32d5ea47bf391003f2e189b3b719ab3a59477c7 Layout/Widgets/Heading.e
// sha256 257f8544e1aedf9ded1048d43d53ad711007a5e373fa481edaaf5867ec7915bf Layout/Widgets/Headline.e
// sha256 7f763b2d1eae23900d60a8150431657fad8f657561b56681bd3780231fa8bc65 Layout/Widgets/PieChart.e
// sha256 0e743de5b4612b50518a1db82e0d0c9d387588a1c415154c0852d2c1960a3d1c Layout/Widgets/Scorecard.e
// sha256 c6b9c6214a92c0ea6fc7b1401c7f20e7708f5e4c7a506900b105cfa94d79e4ac Layout/Widgets/StyleBox.e
// sha256 976d966dfee0f7e28472def88290b95ceb4c934e6674c43752b06f20cc5a56dd Layout/Widgets/Table.e
// sha256 83535c5b7817d6b7a2e3d5305de0228fc118f55a915fb6ae6df1ebbe98f3d743 Layout/Widgets/Text.e
// sha256 1dcf8e3e7c97e15cdb0813e70e8e14131ba8e5ef2a85ab5c1a5d9932c06c2d8b List.e
// sha256 ca65266b55fb2a6c995201109b07141c07360e1650ec3f1a83972f3e35018084 List/NonEmpty.e
// sha256 fcc4e36b774f97fcec3aa58b1c595667d93564281afc3e641eb7631ae166a89b List/Util.e
// sha256 e45c6518f0f90cc348544c6fdd9ba54e768f707ba3cbcc1209a1a35fbb0e3966 Map.e
// sha256 cb54ec6bdc5cf292aadb443209dfe63e051eb8b5dd80ed7b547176c014d72f08 Math.e
// sha256 f70695a4d82fd8af1f5efffad08d37e9677566681c0242b584bd749658f74516 Maybe.e
// sha256 541febac52389ebb408c756cfdb4488d3177aedf93fedf4016b8384ce92e3bf7 Native.e
// sha256 f4e4a90e08a1d248c2b79f09569af012caf84e31089df40632e0b1d96ebdcd22 Native/Bool.e
// sha256 f3f3e0b44716b9c7252ecd2843901679bc23ad89f6e4de5571b13f628e1dea3d Native/BorderOptions.e
// sha256 a40c9fc43fc3d0d292ea00e51a99c1afa601400cdddb7c21aa0465d7b64bb080 Native/Either.e
// sha256 bb290fd3b3c0fe9989923684e8e01a61a574e106257206cfcccc65244e08c699 Native/Error.e
// sha256 d483942830b49edd199e02fc80d5e013a145431e5881f28321d01d36daac2b77 Native/Exception.e
// sha256 b8b671afe1547e5bf3c2ba43a742e8251bd64441bd168e6c76e24e5cb0c0d754 Native/Function.e
// sha256 16f7ef4a89c9124054083ce908217c7cb29d8d212baef8dcd7e39b0eb634bf51 Native/List.e
// sha256 b7f7983933a2efa6a1671194358f6481e5cf42e5dfd70b28335c8f900b40e06d Native/Magnitude.e
// sha256 4be5bfa28aaef24972a75540f634b8c529e9ff9ad39156c8b9952af2074785b5 Native/Maybe.e
// sha256 fbca5b7f032c6523f70eb897d1b7b7eb61457b7b57ba2c7fb3e95527e4497a28 Native/NonEmpty.e
// sha256 83640d39d34e146026c6ecf2f2662d8fb1e4b3b9606158bdbf648eb4685d95bd Native/Object.e
// sha256 82da5d4b2f54dd1427f049ffd37d464d7759ed7e4ee3e99ef1c977bed5a9d182 Native/Ord.e
// sha256 ef6c87df3ceb9054511dd92354cd83c8f67eb7785c44b731aadd4fb426e6fd9a Native/Pair.e
// sha256 6fc682ad3bd58ae8e2d73026cce497d96004776d4159b95efa55a161b0b30632 Native/Record.e
// sha256 6dd517e63d88af07e1cfc23537d844bf9a24065004b90f72de768d8bac8b4ec0 Native/Relation.e
// sha256 4038bea9cbc4d331f4b1e2b7a356d6a258d78a1578f0fbeb6fa840c06ef3b7bf Native/Serializable.e
// sha256 5d673cfde28d367656b88c65bdcba0a1ab8103fe74e530d0004723ad3c687bd9 Native/Throwable.e
// sha256 beec1c80797567af3662c0c6ad9be3c3e493f8379c884f37cac2e589a6ce8b5b Native/TraversableColumns.e
// sha256 ed1b4e31d15e5a93ce943b6512f3c1f413e0dd5242c4c9d461224cdef99b20b6 Nullable.e
// sha256 9ba4fb26787b2719e7fde2c5219ab6ddf2e140a790876537796b3954b9c8ceb6 Num.e
// sha256 8db9d9083db1dc3635c83101aeb036437fd526bc6afb3039625bbf156eeb2d71 Ord.e
// sha256 279ca21a83cff509f3e016826642fe5cbd8506735c4430e9567df48c27dfaf90 Pair.e
// sha256 c5e459410d14536b875cce1a6c51391a2b8a03cc3bef7b9892ff92db2e99a492 Prim.e
// sha256 c1416a7aa4d51cda47570523264e1f23190ba9198602df25f5bd39a6bf471d8a Primitive.e
// sha256 389d487102d6d1bd4fdef7a87b3fa52974dcbe68b56e670459f4eecabb51012a Record.e
// sha256 3e39b7c1d07f9a97cd9dc03064a2a1ab3750ec482f327af5ae555180c8e03eb3 Relation.e
// sha256 d213dc9a9097d19839459d8a95b7f39bc856890da15b0c4e6c2cf76287518960 Relation/Aggregate.e
// sha256 505d2942527a8e19980530684a8b31997f759ac25b7313969870a400f3236753 Relation/Aggregate/Type.e
// sha256 d0b9d024b6ffba1d2d80c6c7b32d476f911adb31b8b158c833ccc193cf548605 Relation/Aggregate/Unsafe.e
// sha256 c0a3033d462db53aa8a967f5d7f27b3c20902422834c2dd154379e345c33f262 Relation/Op.e
// sha256 1bee37d0d86402cb3f0d5c20ef23a68c9ef0e1fb67e382419ee275ec5ff03afa Relation/Op/Type.e
// sha256 d6bbc4ceb80066c7cc09113c0873fd5e11ac8c959a6d299dfea500c440606d4f Relation/Op/Unsafe.e
// sha256 0d896f7f98a33fd53fd19b88762ad748131e0288d2346312fbb6c1d2bfb2219a Relation/Predicate.e
// sha256 30a4309cdbbbf1b54b384dcd6d9e5dd9aa579a139623dcce34b769cd0bce5155 Relation/Predicate/Type.e
// sha256 7e222a9e9a11ee7fbf4aa5d957f61e038778232ec688af0958665c469f57dfe2 Relation/Process.e
// sha256 40188ce4de07b3a8aced2ac71815d3abc1540cbebf39a59bb6f5af7b3772596c Relation/Row.e
// sha256 92adc949a6d07c501cd5165182976d45b3ebb62617d5db6cbd34f4736c02cbc4 Relation/Scan.e
// sha256 3ecbb6d456e48247df286fce50fd8bfd15984bfa3cc108bd66c19d0443f44448 Relation/Sort.e
// sha256 6cee54ab2cd94ff7ed95c255e1d54543eea24fb215ccd6f31acfee23cca5f11d String.e
// sha256 62e87f31c4027db25a1d2d140613a4ff2a8ded6e473bf87536fbc499d9ceb55a Syntax/List.e
// sha256 5b7f39b6a0f421b2dbac68b1c8a1ab2983a8a6cf80570d53906e75a8f786014f Syntax/Maybe.e
// sha256 fbabddf17de5ffbec6283807f688c0568b1028cffbc068ba6efb96ceda98bf91 Syntax/Relation.e
// sha256 6ac7122ca046415a1836957a7a0e17a161076812df754a2ec01f1ea8c21cb94e Type/Cast.e
// sha256 57371bf7d0cbe50c2cae201aed2ee1cbc257d4399abce6f116c46c9f149943ca Unsafe/Coerce.e
// sha256 61ce9a552d8f33648894e9c8f26892f8ca21fbe7702f7d7437b6e24d75da593c Vector.e
// zod 3

import { z } from "zod";

/** Layout.Doc.Node */
export type Layout_Doc_Node =
  | { tag: "Widget"; name: string; props?: unknown }
  | { tag: "VFlow"; children: Array<Layout_Doc_Node> }
  | { tag: "HFlow"; children: Array<Layout_Doc_Node> }
  | { tag: "Grid"; cells: Array<Array<Layout_Doc_Node>> }
  | { tag: "Tabbed"; tabs: Array<Layout_Doc_Tab> };
export const Layout_Doc_Node: z.ZodType<Layout_Doc_Node> = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Widget"), name: z.string(), props: z.unknown() }).strict(), z.object({ tag: z.literal("VFlow"), children: z.array(z.lazy(() => Layout_Doc_Node)) }).strict(), z.object({ tag: z.literal("HFlow"), children: z.array(z.lazy(() => Layout_Doc_Node)) }).strict(), z.object({ tag: z.literal("Grid"), cells: z.array(z.array(z.lazy(() => Layout_Doc_Node))) }).strict(), z.object({ tag: z.literal("Tabbed"), tabs: z.array(z.lazy(() => Layout_Doc_Tab)) }).strict()]);

/** Layout.Doc.Tab */
export interface Layout_Doc_Tab {
  label: string;
  content: Layout_Doc_Node;
}
export const Layout_Doc_Tab: z.ZodType<Layout_Doc_Tab> = z.object({ label: z.string(), content: z.lazy(() => Layout_Doc_Node) }).strict();

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

/** Layout.Widgets.Chart.ScalarType */
export type Layout_Widgets_Chart_ScalarType =
  | { tag: "Scalar"; typeName: string; typeNumeric: boolean }
  | { tag: "Compound"; componentTypes: Array<Layout_Widgets_Chart_ScalarType> };
export const Layout_Widgets_Chart_ScalarType: z.ZodType<Layout_Widgets_Chart_ScalarType> = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Scalar"), typeName: z.string(), typeNumeric: z.boolean() }).strict(), z.object({ tag: z.literal("Compound"), componentTypes: z.array(z.lazy(() => Layout_Widgets_Chart_ScalarType)) }).strict()]);

export const Layout_Widgets_Chart_SortDir = z.enum(["Asc", "Desc"]);
export type Layout_Widgets_Chart_SortDir = z.infer<typeof Layout_Widgets_Chart_SortDir>;

export const Layout_Widgets_Format_RGB = z.object({ red: z.number().int(), green: z.number().int(), blue: z.number().int() }).strict();
export type Layout_Widgets_Format_RGB = z.infer<typeof Layout_Widgets_Format_RGB>;

export const Layout_Widgets_Format_Threshold = z.discriminatedUnion("tag", [z.object({ tag: z.literal("TNum"), args: z.tuple([z.number()]) }).strict(), z.object({ tag: z.literal("TStr"), args: z.tuple([z.string()]) }).strict(), z.object({ tag: z.literal("TBool"), args: z.tuple([z.boolean()]) }).strict()]);
export type Layout_Widgets_Format_Threshold = z.infer<typeof Layout_Widgets_Format_Threshold>;

export const Layout_Widgets_Heading_HeadingProps = z.object({ title: z.string(), sortColumn: z.string(), matched: z.number().int(), total: z.number() }).strict();
export type Layout_Widgets_Heading_HeadingProps = z.infer<typeof Layout_Widgets_Heading_HeadingProps>;

export const Layout_Widgets_Table_ColumnAlign = z.enum(["AlignLeft", "AlignRight"]);
export type Layout_Widgets_Table_ColumnAlign = z.infer<typeof Layout_Widgets_Table_ColumnAlign>;

export const Layout_Widgets_Table_ColumnKind = z.enum(["NumberColumn", "DateColumn", "OtherColumn"]);
export type Layout_Widgets_Table_ColumnKind = z.infer<typeof Layout_Widgets_Table_ColumnKind>;

export const Layout_Widgets_Table_ColumnSort = z.object({ sortColumn: z.number().int(), descending: z.boolean() }).strict();
export type Layout_Widgets_Table_ColumnSort = z.infer<typeof Layout_Widgets_Table_ColumnSort>;

export const Layout_Widgets_Text_TextProps = z.object({ body: z.string() }).strict();
export type Layout_Widgets_Text_TextProps = z.infer<typeof Layout_Widgets_Text_TextProps>;

export const Layout_Widgets_Chart_AxisConstraints = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Scaled"), lowerBound: z.number().optional(), upperBound: z.number().optional(), displayScale: Layout_Widgets_Chart_DisplayScale }).strict(), z.object({ tag: z.literal("Unscaled"), sortOrders: z.array(Layout_Widgets_Chart_SortDir), tickOverrides: z.array(z.tuple([z.string(), z.string()])) }).strict()]);
export type Layout_Widgets_Chart_AxisConstraints = z.infer<typeof Layout_Widgets_Chart_AxisConstraints>;

export const Layout_Widgets_Chart_ChartLegendOptions = z.object({ legendLocation: Layout_Widgets_Chart_LegendLocation }).strict();
export type Layout_Widgets_Chart_ChartLegendOptions = z.infer<typeof Layout_Widgets_Chart_ChartLegendOptions>;

/** Layout.Widgets.Format.CellCondition */
export type Layout_Widgets_Format_CellCondition =
  | { tag: "Gt"; gt: Layout_Widgets_Format_Threshold }
  | { tag: "Lt"; lt: Layout_Widgets_Format_Threshold }
  | { tag: "Eq"; eq: Layout_Widgets_Format_Threshold }
  | { tag: "Gte"; gte: Layout_Widgets_Format_Threshold }
  | { tag: "Lte"; lte: Layout_Widgets_Format_Threshold }
  | { tag: "And"; and: [Layout_Widgets_Format_CellCondition, Layout_Widgets_Format_CellCondition] };
export const Layout_Widgets_Format_CellCondition: z.ZodType<Layout_Widgets_Format_CellCondition> = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Gt"), gt: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Lt"), lt: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Eq"), eq: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Gte"), gte: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("Lte"), lte: Layout_Widgets_Format_Threshold }).strict(), z.object({ tag: z.literal("And"), and: z.tuple([z.lazy(() => Layout_Widgets_Format_CellCondition), z.lazy(() => Layout_Widgets_Format_CellCondition)]) }).strict()]);

/** Layout.Widgets.Format.CellFormat */
export type Layout_Widgets_Format_CellFormat =
  | { tag: "Default"; args: [] }
  | { tag: "Verbatim"; args: [] }
  | { tag: "Markdown"; base: Layout_Widgets_Format_CellFormat }
  | { tag: "Constant"; value: string }
  | { tag: "Percentage"; color: boolean; negParens: boolean; places: number; pad: boolean }
  | { tag: "Currency"; color: boolean; negParens: boolean; symbol: string; places: number }
  | { tag: "Pr1"; base: Layout_Widgets_Format_CellFormat }
  | { tag: "Pr2"; base: Layout_Widgets_Format_CellFormat }
  | { tag: "DateRange"; args: [] }
  | { tag: "Round"; color: boolean; negParens: boolean; places: number }
  | { tag: "IntegralRound"; color: boolean; negParens: boolean; places: number }
  | { tag: "Truncate"; places: number }
  | { tag: "Conditional"; condition: Layout_Widgets_Format_CellCondition; whenTrue: Layout_Widgets_Format_CellFormat; whenFalse: Layout_Widgets_Format_CellFormat }
  | { tag: "Color"; bg: Layout_Widgets_Format_RGB; fg: Layout_Widgets_Format_RGB; base: Layout_Widgets_Format_CellFormat }
  | { tag: "Alias"; aliases: Array<[string, string]> };
export const Layout_Widgets_Format_CellFormat: z.ZodType<Layout_Widgets_Format_CellFormat> = z.discriminatedUnion("tag", [z.object({ tag: z.literal("Default"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Verbatim"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Markdown"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Constant"), value: z.string() }).strict(), z.object({ tag: z.literal("Percentage"), color: z.boolean(), negParens: z.boolean(), places: z.number().int(), pad: z.boolean() }).strict(), z.object({ tag: z.literal("Currency"), color: z.boolean(), negParens: z.boolean(), symbol: z.string(), places: z.number().int() }).strict(), z.object({ tag: z.literal("Pr1"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Pr2"), base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("DateRange"), args: z.tuple([]) }).strict(), z.object({ tag: z.literal("Round"), color: z.boolean(), negParens: z.boolean(), places: z.number().int() }).strict(), z.object({ tag: z.literal("IntegralRound"), color: z.boolean(), negParens: z.boolean(), places: z.number().int() }).strict(), z.object({ tag: z.literal("Truncate"), places: z.number().int() }).strict(), z.object({ tag: z.literal("Conditional"), condition: z.lazy(() => Layout_Widgets_Format_CellCondition), whenTrue: z.lazy(() => Layout_Widgets_Format_CellFormat), whenFalse: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Color"), bg: Layout_Widgets_Format_RGB, fg: Layout_Widgets_Format_RGB, base: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict(), z.object({ tag: z.literal("Alias"), aliases: z.array(z.tuple([z.string(), z.string()])) }).strict()]);

export const Layout_Widgets_Chart_ChartAxis = z.object({ axisLabel: z.string(), tooltipLabel: z.string(), axisFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), scalarType: z.lazy(() => Layout_Widgets_Chart_ScalarType), showTicks: z.boolean(), constraints: Layout_Widgets_Chart_AxisConstraints }).strict();
export type Layout_Widgets_Chart_ChartAxis = z.infer<typeof Layout_Widgets_Chart_ChartAxis>;

export const Layout_Widgets_Chart_ChartSeries = z.object({ seriesColumns: z.array(z.string()), categoryColumns: z.array(z.string()), valueColumn: z.string(), extraColumns: z.array(z.string()), colorColumn: z.string().optional(), seriesFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), extraFormats: z.array(z.lazy(() => Layout_Widgets_Format_CellFormat)), variant: Layout_Widgets_Chart_ChartVariant }).strict();
export type Layout_Widgets_Chart_ChartSeries = z.infer<typeof Layout_Widgets_Chart_ChartSeries>;

export const Layout_Widgets_Crosstab_CrosstabProps = z.object({ crosstabTitle: z.string(), rowHeader: z.string(), colHeader: z.string(), crosstabRowLabels: z.array(z.string()), crosstabColLabels: z.array(z.string()), cells: z.array(z.array(z.number().nullable())), rowTotals: z.array(z.number()), colTotals: z.array(z.number()), grandTotal: z.number(), crosstabFormat: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict();
export type Layout_Widgets_Crosstab_CrosstabProps = z.infer<typeof Layout_Widgets_Crosstab_CrosstabProps>;

export const Layout_Widgets_Headline_HeadlineProps = z.object({ headlineTitle: z.string(), scope: z.string(), rowCount: z.number().int(), total: z.number(), largest: z.number(), headlineFormat: z.lazy(() => Layout_Widgets_Format_CellFormat) }).strict();
export type Layout_Widgets_Headline_HeadlineProps = z.infer<typeof Layout_Widgets_Headline_HeadlineProps>;

export const Layout_Widgets_PieChart_PieChartProps__ = z.object({ pieTitle: z.string(), seriesName: z.string(), pieLabelColumn: z.string(), pieValueColumn: z.string(), pieColorColumn: z.string().optional(), pieChildColumn: z.string().optional(), pieParentColumn: z.string().optional(), pieLabelFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), pieValueFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), pieLegend: Layout_Widgets_Chart_ChartLegendOptions, pieHints: Layout_Widgets_Chart_ChartRenderHints, pieRows: z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict() }).strict();
export type Layout_Widgets_PieChart_PieChartProps__ = z.infer<typeof Layout_Widgets_PieChart_PieChartProps__>;

export const Layout_Widgets_Scorecard_ScorecardProps__ = z.object({ title: z.string(), cardLabel: z.string(), cardValue: z.string(), cardDelta: z.string().optional(), cardFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), cards: z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict() }).strict();
export type Layout_Widgets_Scorecard_ScorecardProps__ = z.infer<typeof Layout_Widgets_Scorecard_ScorecardProps__>;

export const Layout_Widgets_StyleBox_StyleBoxProps__ = z.object({ xTitle: z.string(), yTitle: z.string(), aggColumn: z.string(), aggTitle: z.string(), aggFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), xPositionColumn: z.string(), yPositionColumn: z.string(), rowLabels: z.array(z.string()), columnLabels: z.array(z.string()), showNumber: z.boolean(), xBins: z.array(z.tuple([z.number(), z.number()])), yBins: z.array(z.tuple([z.number(), z.number()])), styleBoxRows: z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict() }).strict();
export type Layout_Widgets_StyleBox_StyleBoxProps__ = z.infer<typeof Layout_Widgets_StyleBox_StyleBoxProps__>;

export const Layout_Widgets_Table_TableColumn = z.object({ column: z.string(), header: z.string(), cellFormat: z.lazy(() => Layout_Widgets_Format_CellFormat), align: Layout_Widgets_Table_ColumnAlign, kind: Layout_Widgets_Table_ColumnKind }).strict();
export type Layout_Widgets_Table_TableColumn = z.infer<typeof Layout_Widgets_Table_TableColumn>;

export const Layout_Widgets_Chart_ChartMeta = z.object({ chartTitle: z.string(), domainAxis: Layout_Widgets_Chart_ChartAxis, rangeAxis: Layout_Widgets_Chart_ChartAxis, orientation: Layout_Widgets_Chart_Orientation, legendOptions: Layout_Widgets_Chart_ChartLegendOptions, renderHints: Layout_Widgets_Chart_ChartRenderHints }).strict();
export type Layout_Widgets_Chart_ChartMeta = z.infer<typeof Layout_Widgets_Chart_ChartMeta>;

export const Layout_Widgets_Drilldown_DrilldownTableProps__ = z.object({ ddColumns: z.array(Layout_Widgets_Table_TableColumn), parentColumn: z.string(), childColumn: z.string(), labelColumn: z.string(), ddSorts: z.array(Layout_Widgets_Table_ColumnSort), ddPaginate: z.boolean(), ddScroll: z.boolean(), ddRows: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Layout_Widgets_Drilldown_DrilldownTableProps__ = z.infer<typeof Layout_Widgets_Drilldown_DrilldownTableProps__>;

export const Layout_Widgets_Table_TableProps__ = z.object({ columns: z.array(Layout_Widgets_Table_TableColumn), rowGroup: z.number().int().optional(), sorts: z.array(Layout_Widgets_Table_ColumnSort), paginate: z.boolean(), scroll: z.boolean(), rows: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Layout_Widgets_Table_TableProps__ = z.infer<typeof Layout_Widgets_Table_TableProps__>;

export const Layout_Widgets_AxisChart_AxisChartProps__ = z.object({ chartMeta: Layout_Widgets_Chart_ChartMeta, chartSeries: z.array(Layout_Widgets_Chart_ChartSeries), chartRows: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Layout_Widgets_AxisChart_AxisChartProps__ = z.infer<typeof Layout_Widgets_AxisChart_AxisChartProps__>;

export const Layout_Widgets_DrilldownBar_DrilldownBarProps__ = z.object({ barMeta: Layout_Widgets_Chart_ChartMeta, barSeries: Layout_Widgets_Chart_ChartSeries, barParentColumn: z.string(), barChildColumn: z.string(), barRows: z.discriminatedUnion("kind", [z.object({ kind: z.literal("inline"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), rows: z.array(z.array(z.union([z.string(), z.number(), z.boolean(), z.null()]))), rowCount: z.number().int().min(0) }).strict(), z.object({ kind: z.literal("deferred"), columns: z.array(z.object({ name: z.string(), type: z.enum(["Bool", "Byte", "Date", "Double", "GUID", "Int", "Long", "Short", "String", "Timestamp"]), nullable: z.boolean() }).strict()), token: z.string().min(1), expires: z.string().datetime() }).strict()]) }).strict();
export type Layout_Widgets_DrilldownBar_DrilldownBarProps__ = z.infer<typeof Layout_Widgets_DrilldownBar_DrilldownBarProps__>;

// -------------------------------------------------------------- short names

export type AxisChartProps = Layout_Widgets_AxisChart_AxisChartProps__;
export const AxisChartPropsSchema = Layout_Widgets_AxisChart_AxisChartProps__;
export type AxisConstraints = Layout_Widgets_Chart_AxisConstraints;
export const AxisConstraintsSchema = Layout_Widgets_Chart_AxisConstraints;
export type CellCondition = Layout_Widgets_Format_CellCondition;
export const CellConditionSchema = Layout_Widgets_Format_CellCondition;
export type CellFormat = Layout_Widgets_Format_CellFormat;
export const CellFormatSchema = Layout_Widgets_Format_CellFormat;
export type ChartAxis = Layout_Widgets_Chart_ChartAxis;
export const ChartAxisSchema = Layout_Widgets_Chart_ChartAxis;
export type ChartLegendOptions = Layout_Widgets_Chart_ChartLegendOptions;
export const ChartLegendOptionsSchema = Layout_Widgets_Chart_ChartLegendOptions;
export type ChartMeta = Layout_Widgets_Chart_ChartMeta;
export const ChartMetaSchema = Layout_Widgets_Chart_ChartMeta;
export type ChartRenderHints = Layout_Widgets_Chart_ChartRenderHints;
export const ChartRenderHintsSchema = Layout_Widgets_Chart_ChartRenderHints;
export type ChartSeries = Layout_Widgets_Chart_ChartSeries;
export const ChartSeriesSchema = Layout_Widgets_Chart_ChartSeries;
export type ChartVariant = Layout_Widgets_Chart_ChartVariant;
export const ChartVariantSchema = Layout_Widgets_Chart_ChartVariant;
export type ColumnAlign = Layout_Widgets_Table_ColumnAlign;
export const ColumnAlignSchema = Layout_Widgets_Table_ColumnAlign;
export type ColumnKind = Layout_Widgets_Table_ColumnKind;
export const ColumnKindSchema = Layout_Widgets_Table_ColumnKind;
export type ColumnSort = Layout_Widgets_Table_ColumnSort;
export const ColumnSortSchema = Layout_Widgets_Table_ColumnSort;
export type CrosstabProps = Layout_Widgets_Crosstab_CrosstabProps;
export const CrosstabPropsSchema = Layout_Widgets_Crosstab_CrosstabProps;
export type DisplayScale = Layout_Widgets_Chart_DisplayScale;
export const DisplayScaleSchema = Layout_Widgets_Chart_DisplayScale;
export type DocNode = Layout_Doc_Node;
export const DocNodeSchema = Layout_Doc_Node;
export type DocTab = Layout_Doc_Tab;
export const DocTabSchema = Layout_Doc_Tab;
export type DrilldownBarProps = Layout_Widgets_DrilldownBar_DrilldownBarProps__;
export const DrilldownBarPropsSchema = Layout_Widgets_DrilldownBar_DrilldownBarProps__;
export type DrilldownTableProps = Layout_Widgets_Drilldown_DrilldownTableProps__;
export const DrilldownTablePropsSchema = Layout_Widgets_Drilldown_DrilldownTableProps__;
export type HeadingProps = Layout_Widgets_Heading_HeadingProps;
export const HeadingPropsSchema = Layout_Widgets_Heading_HeadingProps;
export type HeadlineProps = Layout_Widgets_Headline_HeadlineProps;
export const HeadlinePropsSchema = Layout_Widgets_Headline_HeadlineProps;
export type LegendLocation = Layout_Widgets_Chart_LegendLocation;
export const LegendLocationSchema = Layout_Widgets_Chart_LegendLocation;
export type Orientation = Layout_Widgets_Chart_Orientation;
export const OrientationSchema = Layout_Widgets_Chart_Orientation;
export type PieChartProps = Layout_Widgets_PieChart_PieChartProps__;
export const PieChartPropsSchema = Layout_Widgets_PieChart_PieChartProps__;
export type RGB = Layout_Widgets_Format_RGB;
export const RGBSchema = Layout_Widgets_Format_RGB;
export type ScalarType = Layout_Widgets_Chart_ScalarType;
export const ScalarTypeSchema = Layout_Widgets_Chart_ScalarType;
export type ScorecardProps = Layout_Widgets_Scorecard_ScorecardProps__;
export const ScorecardPropsSchema = Layout_Widgets_Scorecard_ScorecardProps__;
export type SortDir = Layout_Widgets_Chart_SortDir;
export const SortDirSchema = Layout_Widgets_Chart_SortDir;
export type StyleBoxProps = Layout_Widgets_StyleBox_StyleBoxProps__;
export const StyleBoxPropsSchema = Layout_Widgets_StyleBox_StyleBoxProps__;
export type TableColumn = Layout_Widgets_Table_TableColumn;
export const TableColumnSchema = Layout_Widgets_Table_TableColumn;
export type TableProps = Layout_Widgets_Table_TableProps__;
export const TablePropsSchema = Layout_Widgets_Table_TableProps__;
export type TextProps = Layout_Widgets_Text_TextProps;
export const TextPropsSchema = Layout_Widgets_Text_TextProps;
export type Threshold = Layout_Widgets_Format_Threshold;
export const ThresholdSchema = Layout_Widgets_Format_Threshold;

// -------------------------------------------------------------- widgets

/** Widget registry name -> its props type: every `WidgetName T` term the scan found. */
export interface WidgetRegistry {
  axisChart: AxisChartProps;
  crosstab: CrosstabProps;
  drilldownBar: DrilldownBarProps;
  drilldownPieChart: PieChartProps;
  drilldownTable: DrilldownTableProps;
  heading: HeadingProps;
  headline: HeadlineProps;
  pieChart: PieChartProps;
  scorecard: ScorecardProps;
  styleBox: StyleBoxProps;
  table: TableProps;
  text: TextProps;
}

export type WidgetName = keyof WidgetRegistry;

/** Widget registry name -> the zod its props are validated with. */
export const WIDGET_PROP_SCHEMAS: { [K in WidgetName]: z.ZodType<WidgetRegistry[K]> } = {
  axisChart: AxisChartPropsSchema,
  crosstab: CrosstabPropsSchema,
  drilldownBar: DrilldownBarPropsSchema,
  drilldownPieChart: PieChartPropsSchema,
  drilldownTable: DrilldownTablePropsSchema,
  heading: HeadingPropsSchema,
  headline: HeadlinePropsSchema,
  pieChart: PieChartPropsSchema,
  scorecard: ScorecardPropsSchema,
  styleBox: StyleBoxPropsSchema,
  table: TablePropsSchema,
  text: TextPropsSchema,
};

/** Names declared `WidgetName T` at an uninhabited `T` (a data type with no
 *  constructors): reserved, with no props and no renderer. */
export const UNSUPPORTED_WIDGETS: readonly string[] = ["treeMap"];
