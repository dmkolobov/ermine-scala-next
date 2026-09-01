module Ai.RevenueByPeriod where

{- A star schema whose TIME dimension is a tree of date ranges rather than a
   flat date column, so the same fact table can be reported at year, quarter
   or month granularity without being re-shaped.

   Fact:       bookings (contractId, customerId, dateRangeId, netRevenue)
   Dimensions: customer (customerId -> customerName, segment, region)
               calendar (dateRangeId -> parentDateRangeId, periodKind,
                                        periodShort, fiscalYear)

   The roll-up is done with `Ai.Common.factsAtKind`, which is generic in the
   fact row: it names only the kind column it filters on.

     >> :load core/examples/ai/Common.e
     >> :load core/examples/ai/RevenueByPeriod.e
     >> render revenueReport
-}

import Prelude
import Layout
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Ai.Common

field contractId, customerId : Int
field dateRangeId, parentDateRangeId : Int
field customerName, segment, region : String
field periodKind, periodShort, fiscalYear, periodName, displayName : String
field netRevenue : Double
field value : Nullable Double

calendar : [ dateRangeId, parentDateRangeId, periodKind, periodShort, fiscalYear ]
calendar = relation [
  { dateRangeId = 2011,   parentDateRangeId = 0,     periodKind = "Year",    periodShort = "FY",  fiscalYear = "2011" },
  { dateRangeId = 20111,  parentDateRangeId = 2011,  periodKind = "Quarter", periodShort = "Q1",  fiscalYear = "2011" },
  { dateRangeId = 20112,  parentDateRangeId = 2011,  periodKind = "Quarter", periodShort = "Q2",  fiscalYear = "2011" },
  { dateRangeId = 201101, parentDateRangeId = 20111, periodKind = "Month",   periodShort = "Jan", fiscalYear = "2011" },
  { dateRangeId = 201102, parentDateRangeId = 20111, periodKind = "Month",   periodShort = "Feb", fiscalYear = "2011" },
  { dateRangeId = 201103, parentDateRangeId = 20111, periodKind = "Month",   periodShort = "Mar", fiscalYear = "2011" },
  { dateRangeId = 201104, parentDateRangeId = 20112, periodKind = "Month",   periodShort = "Apr", fiscalYear = "2011" },
  { dateRangeId = 201105, parentDateRangeId = 20112, periodKind = "Month",   periodShort = "May", fiscalYear = "2011" },
  { dateRangeId = 201106, parentDateRangeId = 20112, periodKind = "Month",   periodShort = "Jun", fiscalYear = "2011" }
]

-- Bookings land on MONTH nodes of the calendar tree.
bookings : [ contractId, customerId, dateRangeId, netRevenue ]
bookings = relation [
  { contractId = 9001, customerId = 1, dateRangeId = 201101, netRevenue =  42000.0 },
  { contractId = 9002, customerId = 1, dateRangeId = 201103, netRevenue =  51500.0 },
  { contractId = 9003, customerId = 2, dateRangeId = 201102, netRevenue = 118000.0 },
  { contractId = 9004, customerId = 2, dateRangeId = 201105, netRevenue =  96000.0 },
  { contractId = 9005, customerId = 3, dateRangeId = 201104, netRevenue =  23750.0 },
  { contractId = 9006, customerId = 3, dateRangeId = 201106, netRevenue =  31200.0 }
]

customerDim = relation [
  { customerId = 1, customerName = "Northwind Traders", segment = "Enterprise", region = "AMER" },
  { customerId = 2, customerName = "Contoso GmbH",      segment = "Enterprise", region = "EMEA" },
  { customerId = 3, customerName = "Fabrikam Ltd",      segment = "SMB",        region = "EMEA" }
]

-- The star join: fact + customer dimension + the month rows of the calendar.
revenue : [ contractId, customerId, dateRangeId, netRevenue, customerName
          , segment, region, parentDateRangeId, periodKind, periodShort, fiscalYear ]
revenue = bookings ** customerDim ** nodesOfKind periodKind "Month" calendar

-- Enterprise accounts carry their region; SMB accounts do not, because there
-- is only ever one SMB team per region and the region would be noise.
labelled =
  withColumn (if_Op (col_Op segment ==_Pred prim_Op "Enterprise")
                    (col_Op customerName ++_Op prim_Op " - " ++_Op col_Op region)
                    (col_Op customerName))
             displayName
             revenue

-- Period labels from the same generic function the calendar example uses.
labelledPeriods =
  withColumn (if_Op (col_Op periodKind ==_Pred prim_Op "Year")
                    (prim_Op "FY" ++_Op col_Op fiscalYear)
                    (col_Op periodShort ++_Op prim_Op " " ++_Op col_Op fiscalYear))
             periodName
             calendar

calendarTree = treeTable periodShort parentDateRangeId dateRangeId calendar

revenueChart =
  chart_K ([chartTitle_O := "Net Revenue by Month"]_Opt)
          defaultUnscaled defaultScaled
          [bar customerName periodShort netRevenue revenue]

revenueReport = vflow [
  atomShown "## Revenue by Period",
  atomShown "### Calendar",
  calendarTree,
  tabular Nothing labelledPeriods,
  atomShown "### Revenue",
  revenueChart,
  tabular Nothing labelled
]
