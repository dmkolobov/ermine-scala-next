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

import Layout.Widgets.Table using type TableColumn; type ColumnSort
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

-- | Every knob at its legacy default.
simpleDrilldownTable : List TableColumn -> String -> String -> String -> [..r]
                    -> DrilldownTableProps r
simpleDrilldownTable cs parent child lbl rs =
  DrilldownTableProps cs parent child lbl [] True True rs
