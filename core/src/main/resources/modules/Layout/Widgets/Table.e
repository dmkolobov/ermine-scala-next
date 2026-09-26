module Layout.Widgets.Table where

-- The regular tabular widget: registry name "table", rendered by the legacy
-- htmlwriter.runTabular through client/src/legacy.ts.  The props are the arguments
-- HTMLWriter.tableRegular (ermine-writers, HTMLWriter.scala ~1034-1060) builds
-- server-side today -- cols, colAlignments, colType, rowgroupCol, sorts, paginate,
-- scroll -- with the per-cell `{formatted, raw, format}` objects replaced by the
-- relation plus a CellFormat per column, which the client assembles.
--
-- `rows` is a BARE relation: the request's `data.default` decides whether the rows
-- come inline or as a deferred token, and the client's resolveRelation fetches the
-- latter.  The row parameter is free, so `bin/ermine-schema --zod -i
-- Layout.Widgets.Table TableProps` is ONE schema for every relation a table is
-- used with.

import Layout.Widgets.Format using type CellFormat; Default
import List using empty_Bracket; cons_Bracket
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}
import Layout.Widgets.Column using {fieldKind; NumericField; TemporalField; OtherField}
import Constraint using type Has
import Num using (+)
import Field using fieldName

-- | runTabular's `colAlignments`: "left" | "right" after the adapter.
data ColumnAlign = AlignLeft | AlignRight

-- | runTabular's `colType`: "number" | "date" | "other" after the adapter
-- (HTMLWriter.getColumnType).  A sorting and CSS hint, not a wire type.
data ColumnKind = NumberColumn | DateColumn | OtherColumn

-- | One entry of runTabular's `sorts`: an INDEX into `columns` and a direction.
data ColumnSort = ColumnSort { sortColumn : Int, descending : Bool }

-- | A displayed column: the relation column it reads, its header text, how a cell
-- is formatted, and the two presentation hints the legacy renderer derives from a
-- Presentation server-side.
data TableColumn = TableColumn { column : String
                               , header : String
                               , cellFormat : CellFormat
                               , align : ColumnAlign
                               , kind : ColumnKind }

data TableProps r = TableProps { columns : List TableColumn
                               , rowGroup : Maybe Int      -- index into `columns`
                               , sorts : List ColumnSort
                               , paginate : Bool
                               , scroll : Bool
                               , rows : [..r] }

-- | `table` is an Ermine KEYWORD, so the smart constructor cannot be called that;
-- the registry name on the wire is still "table".
-- | The registry name, tied to the props type.
tableName : WidgetName (TableProps r)
tableName = WidgetName "table"

tabular : TableProps r -> Node
tabular p = widget tableName p

-- * The typed authoring API (WP-37, D1/D2/D5/D6)
--
-- A column is named by a `Field`, never by a String: `col region` carries
-- `Has r region`, and the row `r` is settled where the columns meet the relation
-- in `simpleTable`, so a column the relation does not have is a type error
-- ("Row partitions are unsatisfiable at field ...").  Sorts and the row group are
-- marks ON a column; `simpleTable` lowers them to the wire's indices.

-- | A table column valid for relations with row `r`: the wire column, its sort
-- mark (Nothing, Just False = ascending, Just True = descending) and its
-- row-group mark.  `Column#` is the unchecked constructor: build columns with
-- `col`/`numCol`/`dateCol`; the only sanctioned String-named column is
-- Layout.Widgets.Table.Unsafe.rawColumn.
data Column (r : rho) = Column# TableColumn (Maybe Bool) Bool

-- | Kind and alignment from the field's runtime type (Layout.Widgets.Column):
-- numeric -> NumberColumn, right; temporal -> DateColumn, left; else
-- OtherColumn, left.  Header = the field name, no formatting.
col : Has r h => Field h a -> Column r
col f = case fieldKind f of
  NumericField  -> plainColumn f AlignRight NumberColumn
  TemporalField -> plainColumn f AlignLeft DateColumn
  OtherField    -> plainColumn f AlignLeft OtherColumn

-- | A numeric column with a format; the field's value type must be numeric.
numCol : (Has r h, PrimitiveNum a) => Field h a -> CellFormat -> Column r
numCol f fmt = Column# (TableColumn (fieldName f) (fieldName f) fmt AlignRight NumberColumn) Nothing False

-- | A date column; the field's value type must be temporal.
dateCol : (Has r h, PrimitiveTemporal a) => Field h a -> Column r
dateCol f = plainColumn f AlignLeft DateColumn

withHeader : String -> Column r -> Column r
withHeader h (Column# (TableColumn c _ f a k) s g) = Column# (TableColumn c h f a k) s g

withFormat : CellFormat -> Column r -> Column r
withFormat f (Column# (TableColumn c h _ a k) s g) = Column# (TableColumn c h f a k) s g

alignLeft, alignRight : Column r -> Column r
alignLeft  (Column# (TableColumn c h f _ k) s g) = Column# (TableColumn c h f AlignLeft k) s g
alignRight (Column# (TableColumn c h f _ k) s g) = Column# (TableColumn c h f AlignRight k) s g

-- | Sort marks.  Several sorted columns sort in COLUMN order (the first sorted
-- column is the primary key); the last mark applied to one column wins.
sortAsc, sortDesc : Column r -> Column r
sortAsc  (Column# tc _ g) = Column# tc (Just False) g
sortDesc (Column# tc _ g) = Column# tc (Just True) g

-- | Row-group mark.  The wire has one row group: the FIRST marked column wins.
groupRows : Column r -> Column r
groupRows (Column# tc s _) = Column# tc s True

-- | The wire column a typed column lowers to.
columnWire : Column r -> TableColumn
columnWire (Column# tc _ _) = tc

-- | The relation column a typed column reads (its field name).
columnName : Column r -> String
columnName (Column# (TableColumn c _ _ _ _) _ _) = c

-- | Every knob at its legacy default; the columns' marks become `sorts` and
-- `rowGroup`, indices in column order.
simpleTable : List (Column r) -> [..r] -> TableProps r
simpleTable cs rs = TableProps (wires cs) (groupIndex 0 cs) (sortsFrom 0 cs) True True rs

private
  plainColumn : Field h a -> ColumnAlign -> ColumnKind -> Column r
  plainColumn f a k = Column# (TableColumn (fieldName f) (fieldName f) Default a k) Nothing False

  wires : List (Column r) -> List TableColumn
  wires [] = []
  wires (c :: cs) = columnWire c :: wires cs

  groupIndex : Int -> List (Column r) -> Maybe Int
  groupIndex _ [] = Nothing
  groupIndex i (Column# _ _ True :: _) = Just i
  groupIndex i (_ :: cs) = groupIndex (i + 1) cs

  sortsFrom : Int -> List (Column r) -> List ColumnSort
  sortsFrom _ [] = []
  sortsFrom i (Column# _ (Just d) _ :: cs) = ColumnSort i d :: sortsFrom (i + 1) cs
  sortsFrom i (_ :: cs) = sortsFrom (i + 1) cs
