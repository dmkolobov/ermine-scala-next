module Doc.SalesReport where

-- The end-to-end fixture of stage J3d: a report that uses the legacy-backed
-- "table" widget and the new "scorecard" widget over one relation.
--
--   sbt -batch 'core/Test/runMain com.clarifi.reporting.SalesReportDoc <file>'
--
-- writes it through json/Write.scala on a SQLite in-memory connection, and
-- client/test/endtoend.test.ts renders THAT FILE in jsdom with a stub
-- htmlwriter.  When J3c lands, the same module is what `bin/ermine-serve`
-- answers `POST /report/Doc.SalesReport` with.
--
-- It lives under modules/ rather than the brief's core/src/test/resources/doc/
-- because that is the directory the module loader searches on the classpath.

import Native.List
import Native.Relation
import List
import Json using type Inline; Inline
import Layout.Doc using vflow; type Node
import Layout.Widgets.Format
import Layout.Widgets.Table
import Layout.Widgets.Scorecard

field srRegion : String
field srSales : Double
field srDelta : Double

sales : [srRegion, srSales, srDelta]
sales = mkRelation# (toList#
  [ { srRegion = "EMEA", srSales = 120.5,  srDelta = 0.125 }
  , { srRegion = "APAC", srSales = 98.25,  srDelta = -0.04 }
  , { srRegion = "AMER", srSales = 310.75, srDelta = 0.5 }
  ])

report : Node
report =
  vflow
    [ scorecard (ScorecardProps "Sales by region" "srRegion" "srSales" (Just "srDelta")
                                (Round False False 1) (Inline sales))
    , tabular (TableProps
        [ TableColumn "srRegion" "Region" Default AlignLeft OtherColumn
        , TableColumn "srSales" "Sales" (Currency False False "$" 2) AlignRight NumberColumn
        , TableColumn "srDelta" "Change" (Percentage False True 1 False) AlignRight NumberColumn
        ]
        Nothing [ColumnSort 1 True] True True sales)
    ]
