module Layout.Widgets.Drilldown where

-- The drilldown tabular widget: registry name "drilldownTable", rendered by the
-- same legacy htmlwriter.runTabular with `isDD: true` (ermine-writers,
-- HTMLWriter.drilldownTable ~1064-1096).  The tree the legacy TreeTabular builds
-- server-side is built on the client instead, from `parentColumn`/`childColumn`:
-- each row's parent cell names its parent's child cell, a root has a parent value
-- that matches no child.  `labelColumn` is the column whose cell carries the
-- expander and the indent.
--
-- Its own field selectors, deliberately: field selectors are MODULE-global in
-- Ermine, so two widgets that both want `columns`/`rows`/`sorts` cannot live in
-- one module.  One module per widget is the pattern J3e should follow.

import Layout.Widgets.Table using {type TableColumn; type ColumnSort; type Column; simpleTable; columns; sorts}
import Field using fieldName
import List using empty_Bracket; cons_Bracket
import Layout.Doc using {widget; type Node; type WidgetName; WidgetName}

data DrilldownTableProps r = DrilldownTableProps { ddColumns : List TableColumn
                                                 , parentColumn : String
                                                 , childColumn : String
                                                 , labelColumn : String
                                                 , ddSorts : List ColumnSort
                                                 , ddPaginate : Bool
                                                 , ddScroll : Bool
                                                 , ddRows : [..r] }

-- | The registry name, tied to the props type.
drilldownTableName : WidgetName (DrilldownTableProps r)
drilldownTableName = WidgetName "drilldownTable"

drilldownTable : DrilldownTableProps r -> Node
drilldownTable p = widget drilldownTableName p

-- * The typed authoring API (WP-37, D1/D4)
--
-- `DrilldownTableProps` is the WIRE (column names, D3).  A report builds it with
-- `drilldownTableOf` from a `DrilldownSource`: the displayed columns are an open
-- list of `Layout.Widgets.Table.Column r` (as for a table), the three roles are
-- FIELDS, and the partition proves parent, child and label are three DISTINCT
-- columns of the relation (as `Layout.Report.drilldownTable` does).

-- | What `drilldownTableOf` lowers.  Server-side only.  The parent and child
-- carry the same value type: a parent cell names another row's child cell.
data DrilldownSource h1 h2 h3 a b r =
  DrilldownSource { ddSourceColumns : List (Column r)
                  , ddParent : Field h1 a
                  , ddChild : Field h2 a
                  , ddLabel : Field h3 b
                  , ddSourceRows : [..r] }

-- | The wire props, every other knob at its legacy default (paginate, scroll).
-- The columns lower as `simpleTable` lowers them, sort marks included; a
-- `groupRows` mark is ignored (the drilldown wire has no row group).
drilldownTableOf : (r <- (h1, h2, h3, t)) => DrilldownSource h1 h2 h3 a b r -> DrilldownTableProps r
drilldownTableOf s =
  let t = simpleTable (ddSourceColumns s) (ddSourceRows s)
  in DrilldownTableProps (columns t) (fieldName (ddParent s)) (fieldName (ddChild s))
                         (fieldName (ddLabel s)) (sorts t) True True (ddSourceRows s)
