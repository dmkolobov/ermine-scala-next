// TypeScript declarations of the widget prop types, mirroring
// core/src/main/resources/modules/Layout/Widgets/*.e one field at a time.
//
// Why these are hand-written while src/generated holds the zod: `ermine-schema
// --zod` emits a RECURSIVE schema as `z.ZodTypeAny` (it must, for `z.lazy`), and
// `z.infer` of a `z.ZodTypeAny` is `any` -- so the generated file is authoritative
// at RUNTIME but says nothing useful at compile time.  These declarations are the
// compile-time half, and test/props.test.ts pins them against the generated zod:
// every constructor tag, every field name, both directions.  A type added or a
// field renamed in Ermine fails that test, not a reviewer's attention.

/** Layout.Widgets.Format.RGB */
export interface RGB {
  red: number;
  green: number;
  blue: number;
}

/** Layout.Widgets.Format.Threshold -- positional constructors, so `{tag, args}`. */
export type Threshold =
  | { tag: "TNum"; args: [number] }
  | { tag: "TStr"; args: [string] }
  | { tag: "TBool"; args: [boolean] };

/** Layout.Widgets.Format.CellCondition */
export type CellCondition =
  | { tag: "Gt"; gt: Threshold }
  | { tag: "Lt"; lt: Threshold }
  | { tag: "Eq"; eq: Threshold }
  | { tag: "Gte"; gte: Threshold }
  | { tag: "Lte"; lte: Threshold }
  | { tag: "And"; and: [CellCondition, CellCondition] };

/** Layout.Widgets.Format.CellFormat.  A nullary constructor of a type that has
 *  non-nullary ones is `{tag, args: []}`, which is the generic walker's positional
 *  encoding -- not a bare string. */
export type CellFormat =
  | { tag: "Default"; args: [] }
  | { tag: "Verbatim"; args: [] }
  | { tag: "Markdown"; base: CellFormat }
  | { tag: "Constant"; value: string }
  | { tag: "Percentage"; color: boolean; negParens: boolean; places: number; pad: boolean }
  | { tag: "Currency"; color: boolean; negParens: boolean; symbol: string; places: number }
  | { tag: "Pr1"; base: CellFormat }
  | { tag: "Pr2"; base: CellFormat }
  | { tag: "DateRange"; args: [] }
  | { tag: "Round"; color: boolean; negParens: boolean; places: number }
  | { tag: "IntegralRound"; color: boolean; negParens: boolean; places: number }
  | { tag: "Truncate"; places: number }
  | { tag: "Conditional"; condition: CellCondition; whenTrue: CellFormat; whenFalse: CellFormat }
  | { tag: "Color"; bg: RGB; fg: RGB; base: CellFormat }
  | { tag: "Alias"; aliases: [string, string][] };

/** Layout.Widgets.Table.ColumnAlign -- an all-nullary data type, so a bare name. */
export type ColumnAlign = "AlignLeft" | "AlignRight";

/** Layout.Widgets.Table.ColumnKind */
export type ColumnKind = "NumberColumn" | "DateColumn" | "OtherColumn";

/** Layout.Widgets.Table.ColumnSort */
export interface ColumnSort {
  sortColumn: number;
  descending: boolean;
}

/** Layout.Widgets.Table.TableColumn */
export interface TableColumn {
  column: string;
  header: string;
  cellFormat: CellFormat;
  align: ColumnAlign;
  kind: ColumnKind;
}

// The relation positions are typed by src/relation.ts.  A `Maybe a` field is
// OPTIONAL and carries the payload: the encoder omits the key for Nothing.

/** Layout.Widgets.Table.TableProps -- `rows` is a BARE relation, so it arrives
 *  inline or deferred; the dispatcher resolves it before the adapter sees it. */
export interface TableProps<R = import("./relation").WireRelation> {
  columns: TableColumn[];
  rowGroup?: number;
  sorts: ColumnSort[];
  paginate: boolean;
  scroll: boolean;
  rows: R;
}

/** Layout.Widgets.Drilldown.DrilldownTableProps */
export interface DrilldownTableProps<R = import("./relation").WireRelation> {
  ddColumns: TableColumn[];
  parentColumn: string;
  childColumn: string;
  labelColumn: string;
  ddSorts: ColumnSort[];
  ddPaginate: boolean;
  ddScroll: boolean;
  ddRows: R;
}

/** Layout.Widgets.Scorecard.ScorecardProps -- `cards` is `Inline r`, so it is
 *  always inline on the wire and the schema has no deferred arm. */
export interface ScorecardProps<R = import("./relation").InlineRelation> {
  title: string;
  cardLabel: string;
  cardValue: string;
  cardDelta?: string;
  cardFormat: CellFormat;
  cards: R;
}

/** Layout.Doc.Node, the layout tree.  `props` is whatever the widget declares. */
export type DocNode =
  | { tag: "Widget"; name: string; props: unknown }
  | { tag: "VFlow"; children: DocNode[] }
  | { tag: "HFlow"; children: DocNode[] }
  | { tag: "Grid"; cells: DocNode[][] }
  | { tag: "Tabbed"; tabs: DocTab[] };

/** Layout.Doc.Tab -- one constructor, so NO `tag` key. */
export interface DocTab {
  label: string;
  content: DocNode;
}
