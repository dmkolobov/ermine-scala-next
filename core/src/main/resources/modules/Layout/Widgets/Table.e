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

-- | Every knob at its legacy default.
simpleTable : List TableColumn -> [..r] -> TableProps r
simpleTable cs rs = TableProps cs Nothing [] True True rs

-- | A left-aligned text column with no formatting.
textColumn : String -> String -> TableColumn
textColumn c h = TableColumn c h Default AlignLeft OtherColumn

-- | A right-aligned numeric column.
numberColumn : String -> String -> CellFormat -> TableColumn
numberColumn c h f = TableColumn c h f AlignRight NumberColumn
