module Ai.FiscalCalendar where

{- A TREE OF DATE RANGES, and a table whose COLUMNS are grouped by it.

   The calendar is an ordinary parent/child tree, expressed with
   `dateRangeId` / `parentDateRangeId` exactly as a grouping hierarchy is
   expressed with `productGroupId` / `parentProductGroupId`:

     FY2011                         (dateRangeId 2011, parent 0)
       Q1 2011                      (20111, parent 2011)
         Jan 2011                   (201101, parent 20111)
           1 Jan 2011 .. 3 Jan 2011 (20110101.., parent 201101)
         Feb 2011, Mar 2011
       Q2 2011 .. Q4 2011

   A fiscal year has four quarters, each quarter three months, and a month may
   be subdivided into days. Only January is expanded to days here, to show that
   the tree need not be uniform in depth.

   The display labels are built by `Ai.Common.periodLabel`, a row-polymorphic
   function that knows only the four columns it reads.

     >> :load core/examples/Ai/Common.e
     >> :load core/examples/Ai/FiscalCalendar.e
     >> render calendarReport
-}

import Prelude
import Layout
import Layout.Legend as Lg
import Layout.Scan
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Ai.Common

field dateRangeId, parentDateRangeId : Int
field productGroupId, parentProductGroupId : Int
field periodKind, periodShort, fiscalYear, periodName : String
field productName, productLine : String
field amount : Double
field value : Nullable Double

-- ------------------------------------------------------------ the calendar

calendar : [ dateRangeId, parentDateRangeId, periodKind, periodShort, fiscalYear ]
calendar = relation [
  { dateRangeId = 2011,     parentDateRangeId = 0,      periodKind = "Year",    periodShort = "FY",  fiscalYear = "2011" },

  { dateRangeId = 20111,    parentDateRangeId = 2011,   periodKind = "Quarter", periodShort = "Q1",  fiscalYear = "2011" },
  { dateRangeId = 201101,   parentDateRangeId = 20111,  periodKind = "Month",   periodShort = "Jan", fiscalYear = "2011" },
  { dateRangeId = 20110101, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "1",   fiscalYear = "2011" },
  { dateRangeId = 20110102, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "2",   fiscalYear = "2011" },
  { dateRangeId = 20110103, parentDateRangeId = 201101, periodKind = "Day",     periodShort = "3",   fiscalYear = "2011" },
  { dateRangeId = 201102,   parentDateRangeId = 20111,  periodKind = "Month",   periodShort = "Feb", fiscalYear = "2011" },
  { dateRangeId = 201103,   parentDateRangeId = 20111,  periodKind = "Month",   periodShort = "Mar", fiscalYear = "2011" },

  { dateRangeId = 20112,    parentDateRangeId = 2011,   periodKind = "Quarter", periodShort = "Q2",  fiscalYear = "2011" },
  { dateRangeId = 201104,   parentDateRangeId = 20112,  periodKind = "Month",   periodShort = "Apr", fiscalYear = "2011" },
  { dateRangeId = 201105,   parentDateRangeId = 20112,  periodKind = "Month",   periodShort = "May", fiscalYear = "2011" },
  { dateRangeId = 201106,   parentDateRangeId = 20112,  periodKind = "Month",   periodShort = "Jun", fiscalYear = "2011" },

  { dateRangeId = 20113,    parentDateRangeId = 2011,   periodKind = "Quarter", periodShort = "Q3",  fiscalYear = "2011" },
  { dateRangeId = 201107,   parentDateRangeId = 20113,  periodKind = "Month",   periodShort = "Jul", fiscalYear = "2011" },
  { dateRangeId = 201108,   parentDateRangeId = 20113,  periodKind = "Month",   periodShort = "Aug", fiscalYear = "2011" },
  { dateRangeId = 201109,   parentDateRangeId = 20113,  periodKind = "Month",   periodShort = "Sep", fiscalYear = "2011" },

  { dateRangeId = 20114,    parentDateRangeId = 2011,   periodKind = "Quarter", periodShort = "Q4",  fiscalYear = "2011" },
  { dateRangeId = 201110,   parentDateRangeId = 20114,  periodKind = "Month",   periodShort = "Oct", fiscalYear = "2011" },
  { dateRangeId = 201111,   parentDateRangeId = 20114,  periodKind = "Month",   periodShort = "Nov", fiscalYear = "2011" },
  { dateRangeId = 201112,   parentDateRangeId = 20114,  periodKind = "Month",   periodShort = "Dec", fiscalYear = "2011" }
]

-- The generic labeller from Ai.Common: "FY2011", "Q1 2011", "Mar 2011", "3 2011".
labelledCalendar =
  withColumn (if_Op (col_Op periodKind ==_Pred prim_Op "Year")
                    (prim_Op "FY" ++_Op col_Op fiscalYear)
                    (col_Op periodShort ++_Op prim_Op " " ++_Op col_Op fiscalYear))
             periodName
             calendar

-- The whole calendar as a navigable tree, via Ai.Common.treeTable.
calendarTree = treeTable periodShort parentDateRangeId dateRangeId calendar

-- One level of the tree, via Ai.Common.nodesOfKind.
quarters = nodesOfKind periodKind "Quarter" calendar
calMonths = nodesOfKind periodKind "Month"   calendar

-- The children of Q1, via Ai.Common.childrenOf.
q1Months = childrenOf parentDateRangeId 20111 calendar

-- --------------------------------------- a table with period-grouped columns

-- A product hierarchy for the rows.
productTree : [ productGroupId, parentProductGroupId, productName ]
productTree = relation [
  { productGroupId = 1,  parentProductGroupId = 0, productName = "All Products" },
  { productGroupId = 10, parentProductGroupId = 1, productName = "Lighting" },
  { productGroupId = 11, parentProductGroupId = 10, productName = "Desk Lamp" },
  { productGroupId = 12, parentProductGroupId = 10, productName = "Floor Lamp" },
  { productGroupId = 20, parentProductGroupId = 1, productName = "Seating" },
  { productGroupId = 21, parentProductGroupId = 20, productName = "Office Chair" }
]

-- The fact table is keyed by BOTH hierarchies: a product node and a period.
monthlySales : [ productGroupId, parentProductGroupId, productName, periodShort, amount ]
monthlySales = relation [
  { productGroupId = 11, parentProductGroupId = 10, productName = "Desk Lamp",    periodShort = "Q1", amount = 12500.0 },
  { productGroupId = 11, parentProductGroupId = 10, productName = "Desk Lamp",    periodShort = "Q2", amount = 14100.0 },
  { productGroupId = 11, parentProductGroupId = 10, productName = "Desk Lamp",    periodShort = "Q3", amount = 11800.0 },
  { productGroupId = 11, parentProductGroupId = 10, productName = "Desk Lamp",    periodShort = "Q4", amount = 16900.0 },
  { productGroupId = 12, parentProductGroupId = 10, productName = "Floor Lamp",   periodShort = "Q1", amount =  4200.0 },
  { productGroupId = 12, parentProductGroupId = 10, productName = "Floor Lamp",   periodShort = "Q2", amount =  5100.0 },
  { productGroupId = 12, parentProductGroupId = 10, productName = "Floor Lamp",   periodShort = "Q3", amount =  4800.0 },
  { productGroupId = 12, parentProductGroupId = 10, productName = "Floor Lamp",   periodShort = "Q4", amount =  6300.0 },
  { productGroupId = 21, parentProductGroupId = 20, productName = "Office Chair", periodShort = "Q1", amount = 22000.0 },
  { productGroupId = 21, parentProductGroupId = 20, productName = "Office Chair", periodShort = "Q2", amount = 19500.0 },
  { productGroupId = 21, parentProductGroupId = 20, productName = "Office Chair", periodShort = "Q3", amount = 24100.0 },
  { productGroupId = 21, parentProductGroupId = 20, productName = "Office Chair", periodShort = "Q4", amount = 27300.0 }
]

-- COLUMNS GROUPED BY DATE RANGE: one column per quarter, rows keyed by product.
quarterlyMatrix =
  groupBy1 periodShort monthlySales
    |> mapV column
    |> columns '
       keys { productName }

-- The same, with the ROWS drilling down the product tree while the COLUMNS
-- stay grouped by date range.
quarterlyMatrixNested =
  groupBy1 periodShort monthlySales
    |> mapV column
    |> columns '
       keys { productName } . nestBy parentProductGroupId productGroupId

calendarReport = vflow [
  atomShown "## Fiscal Calendar",
  atomShown "### The date-range tree",
  calendarTree,
  atomShown "### Quarters only",
  tabular Nothing quarters,
  atomShown "### Labelled periods",
  tabular Nothing labelledCalendar,
  atomShown "### Sales, columns grouped by quarter",
  quarterlyMatrix,
  atomShown "### Same, rows nested by product hierarchy",
  quarterlyMatrixNested
]
