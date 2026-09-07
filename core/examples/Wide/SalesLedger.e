module Wide.SalesLedger where

{- A SALES LEDGER PIVOTED TWICE: once so that the four quarters of the year
   become four columns, and once so that the three product lines do.

   This is the shape a pivot exists for.  The ledger is stored long -- one row
   per customer, per line, per quarter -- because that is how it arrives and how
   it aggregates.  A reader wants it wide, because a reader compares Q1 with Q4
   by moving their eye sideways, not by scanning for a second row.  `pivotBy`
   turns one into the other, and the row variable `i` in its signature -- the
   IDENTITY columns, the ones that are neither key nor value and therefore
   survive -- is never written down by anybody: the solver mints it.

   Fact:       orderLine (27 columns)
                 keys      orderId, customerId, productId, period
                 amounts   grossRevenue, discountAmt, netRevenue, cogs,
                           freightCost, dutyCost, rebateAccrual, marketingFund
                 units     unitsOrdered, unitsShipped, unitsReturned, backorder
                 dates     orderDay, shipDay, dueDay
                 flags     channel, incoterm, currencyCode, priceListId
                 service   fillRatePct, onTimePct, leadTimeDays, disputeCount
   Dimensions: customer (customerId -> customerName, segment, region, country)
               product  (productId  -> productName, productLine, family, tier)

   Helpers used: pivotBy, startPivot, pivotColumn (Wide.Helpers).

   Solver shapes exercised:
     * TWO pivots over the same ledger, each solving `r <- (k, v, i)` and
       `s <- (i, p)`.  The existential `i` is a PART of both: the solver learns
       it from the narrow row and has to use it to build the wide one.  Outside
       `core/examples/PivotTest.e` -- a fifteen-row toy whose pivot is never
       forced -- that shape appears nowhere else in the example corpus;
     * a `Fulcrum` built four deep, so `consFulcrum`'s `p' <- (f, p)` and
       `RUnion2 v3 v2 v1` are instantiated four times in a chain, each layer's
       output row feeding the next layer's input;
     * `groupBy` ahead of each pivot (`kv <- (k, v)`, `kv2 <- (k, v2)`).

   The pivoted relations TYPE-CHECK but cannot be evaluated in this repository:
   `Relation.Pivot.pivot` panics when forced.  See section 7.2 of
   `tracker/loopmodel/E1-EXAMPLES.md`.

     >> :load core/examples/Wide/Helpers.e
     >> :load core/examples/Wide/SalesLedger.e
     >> :type revenueByQuarter
-}

import Prelude
import Layout
import Layout.Legend as Lg
import Layout.Report.Keyed as K
import Layout.Report.Keyed.Options as O
import Layout.Report.Keyed.Syntax
import Layout.SortPriority
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Wide.Helpers

field orderId, customerId, productId, priceListId, disputeCount : Int
field unitsOrdered, unitsShipped, unitsReturned, backorder, leadTimeDays : Int
field grossRevenue, discountAmt, netRevenue, cogs : Double
field freightCost, dutyCost, rebateAccrual, marketingFund : Double
field fillRatePct, onTimePct : Double
field orderDay, shipDay, dueDay : Date
field period, channel, incoterm, currencyCode : String
field customerName, segment, region, country : String
field productName, productLine, family, tier : String
field q1, q2, q3, q4 : Double
field bikes, apparel, spares : Double

-- Twenty-seven columns.  Twelve order lines across two customers, three product
-- lines and four quarters.
orderLine = relation [
  { orderId = 9001, customerId = 1, productId = 100, period = "Q1",
    grossRevenue = 128000.0, discountAmt = 8400.0, netRevenue = 119600.0, cogs = 71200.0,
    freightCost = 3100.0, dutyCost = 1250.0, rebateAccrual = 2400.0, marketingFund = 1800.0,
    unitsOrdered = 420, unitsShipped = 412, unitsReturned = 6, backorder = 8,
    orderDay = yyyymmdd 2025 1 14, shipDay = yyyymmdd 2025 1 21, dueDay = yyyymmdd 2025 2 14,
    channel = "Direct", incoterm = "DAP", currencyCode = "USD", priceListId = 3,
    fillRatePct = 98.1, onTimePct = 94.0, leadTimeDays = 7, disputeCount = 0 },
  { orderId = 9002, customerId = 1, productId = 200, period = "Q1",
    grossRevenue = 64000.0, discountAmt = 2200.0, netRevenue = 61800.0, cogs = 38900.0,
    freightCost = 1400.0, dutyCost = 520.0, rebateAccrual = 900.0, marketingFund = 640.0,
    unitsOrdered = 1600, unitsShipped = 1600, unitsReturned = 41, backorder = 0,
    orderDay = yyyymmdd 2025 2 3, shipDay = yyyymmdd 2025 2 6, dueDay = yyyymmdd 2025 3 3,
    channel = "Direct", incoterm = "DAP", currencyCode = "USD", priceListId = 3,
    fillRatePct = 100.0, onTimePct = 100.0, leadTimeDays = 3, disputeCount = 1 },
  { orderId = 9003, customerId = 1, productId = 300, period = "Q2",
    grossRevenue = 41000.0, discountAmt = 1100.0, netRevenue = 39900.0, cogs = 26400.0,
    freightCost = 980.0, dutyCost = 310.0, rebateAccrual = 400.0, marketingFund = 410.0,
    unitsOrdered = 2050, unitsShipped = 2010, unitsReturned = 18, backorder = 40,
    orderDay = yyyymmdd 2025 4 9, shipDay = yyyymmdd 2025 4 17, dueDay = yyyymmdd 2025 5 9,
    channel = "Partner", incoterm = "EXW", currencyCode = "USD", priceListId = 4,
    fillRatePct = 98.0, onTimePct = 88.0, leadTimeDays = 8, disputeCount = 0 },
  { orderId = 9004, customerId = 1, productId = 100, period = "Q3",
    grossRevenue = 152000.0, discountAmt = 11400.0, netRevenue = 140600.0, cogs = 84100.0,
    freightCost = 3600.0, dutyCost = 1480.0, rebateAccrual = 2900.0, marketingFund = 2100.0,
    unitsOrdered = 495, unitsShipped = 495, unitsReturned = 3, backorder = 0,
    orderDay = yyyymmdd 2025 7 2, shipDay = yyyymmdd 2025 7 8, dueDay = yyyymmdd 2025 8 2,
    channel = "Direct", incoterm = "DAP", currencyCode = "USD", priceListId = 3,
    fillRatePct = 100.0, onTimePct = 97.0, leadTimeDays = 6, disputeCount = 0 },
  { orderId = 9005, customerId = 1, productId = 200, period = "Q4",
    grossRevenue = 88000.0, discountAmt = 4100.0, netRevenue = 83900.0, cogs = 52700.0,
    freightCost = 1900.0, dutyCost = 700.0, rebateAccrual = 1200.0, marketingFund = 880.0,
    unitsOrdered = 2200, unitsShipped = 2140, unitsReturned = 55, backorder = 60,
    orderDay = yyyymmdd 2025 10 20, shipDay = yyyymmdd 2025 10 29, dueDay = yyyymmdd 2025 11 20,
    channel = "Direct", incoterm = "DAP", currencyCode = "USD", priceListId = 3,
    fillRatePct = 97.3, onTimePct = 91.0, leadTimeDays = 9, disputeCount = 2 },
  { orderId = 9006, customerId = 1, productId = 300, period = "Q4",
    grossRevenue = 47000.0, discountAmt = 1500.0, netRevenue = 45500.0, cogs = 30100.0,
    freightCost = 1050.0, dutyCost = 360.0, rebateAccrual = 450.0, marketingFund = 470.0,
    unitsOrdered = 2350, unitsShipped = 2350, unitsReturned = 12, backorder = 0,
    orderDay = yyyymmdd 2025 11 5, shipDay = yyyymmdd 2025 11 11, dueDay = yyyymmdd 2025 12 5,
    channel = "Partner", incoterm = "EXW", currencyCode = "USD", priceListId = 4,
    fillRatePct = 100.0, onTimePct = 96.0, leadTimeDays = 6, disputeCount = 0 },
  { orderId = 9007, customerId = 2, productId = 100, period = "Q1",
    grossRevenue = 96000.0, discountAmt = 3800.0, netRevenue = 92200.0, cogs = 55600.0,
    freightCost = 2400.0, dutyCost = 990.0, rebateAccrual = 1700.0, marketingFund = 1440.0,
    unitsOrdered = 310, unitsShipped = 298, unitsReturned = 2, backorder = 12,
    orderDay = yyyymmdd 2025 3 11, shipDay = yyyymmdd 2025 3 19, dueDay = yyyymmdd 2025 4 11,
    channel = "Partner", incoterm = "CIF", currencyCode = "EUR", priceListId = 7,
    fillRatePct = 96.1, onTimePct = 90.0, leadTimeDays = 8, disputeCount = 1 },
  { orderId = 9008, customerId = 2, productId = 200, period = "Q2",
    grossRevenue = 72000.0, discountAmt = 3600.0, netRevenue = 68400.0, cogs = 43800.0,
    freightCost = 1750.0, dutyCost = 640.0, rebateAccrual = 1000.0, marketingFund = 720.0,
    unitsOrdered = 1800, unitsShipped = 1800, unitsReturned = 27, backorder = 0,
    orderDay = yyyymmdd 2025 5 22, shipDay = yyyymmdd 2025 5 28, dueDay = yyyymmdd 2025 6 22,
    channel = "Partner", incoterm = "CIF", currencyCode = "EUR", priceListId = 7,
    fillRatePct = 100.0, onTimePct = 99.0, leadTimeDays = 6, disputeCount = 0 },
  { orderId = 9009, customerId = 2, productId = 300, period = "Q2",
    grossRevenue = 33000.0, discountAmt = 900.0, netRevenue = 32100.0, cogs = 21300.0,
    freightCost = 810.0, dutyCost = 250.0, rebateAccrual = 320.0, marketingFund = 330.0,
    unitsOrdered = 1650, unitsShipped = 1610, unitsReturned = 9, backorder = 40,
    orderDay = yyyymmdd 2025 6 4, shipDay = yyyymmdd 2025 6 13, dueDay = yyyymmdd 2025 7 4,
    channel = "Partner", incoterm = "CIF", currencyCode = "EUR", priceListId = 7,
    fillRatePct = 97.6, onTimePct = 85.0, leadTimeDays = 9, disputeCount = 0 },
  { orderId = 9010, customerId = 2, productId = 100, period = "Q3",
    grossRevenue = 111000.0, discountAmt = 6600.0, netRevenue = 104400.0, cogs = 62800.0,
    freightCost = 2800.0, dutyCost = 1120.0, rebateAccrual = 2000.0, marketingFund = 1665.0,
    unitsOrdered = 360, unitsShipped = 360, unitsReturned = 4, backorder = 0,
    orderDay = yyyymmdd 2025 8 15, shipDay = yyyymmdd 2025 8 21, dueDay = yyyymmdd 2025 9 15,
    channel = "Partner", incoterm = "CIF", currencyCode = "EUR", priceListId = 7,
    fillRatePct = 100.0, onTimePct = 93.0, leadTimeDays = 6, disputeCount = 0 },
  { orderId = 9011, customerId = 2, productId = 200, period = "Q3",
    grossRevenue = 59000.0, discountAmt = 2000.0, netRevenue = 57000.0, cogs = 36400.0,
    freightCost = 1500.0, dutyCost = 540.0, rebateAccrual = 820.0, marketingFund = 590.0,
    unitsOrdered = 1475, unitsShipped = 1440, unitsReturned = 31, backorder = 35,
    orderDay = yyyymmdd 2025 9 9, shipDay = yyyymmdd 2025 9 18, dueDay = yyyymmdd 2025 10 9,
    channel = "Partner", incoterm = "CIF", currencyCode = "EUR", priceListId = 7,
    fillRatePct = 97.6, onTimePct = 87.0, leadTimeDays = 9, disputeCount = 1 },
  { orderId = 9012, customerId = 2, productId = 300, period = "Q4",
    grossRevenue = 38000.0, discountAmt = 1200.0, netRevenue = 36800.0, cogs = 24600.0,
    freightCost = 900.0, dutyCost = 290.0, rebateAccrual = 370.0, marketingFund = 380.0,
    unitsOrdered = 1900, unitsShipped = 1900, unitsReturned = 14, backorder = 0,
    orderDay = yyyymmdd 2025 12 1, shipDay = yyyymmdd 2025 12 8, dueDay = yyyymmdd 2026 1 1,
    channel = "Partner", incoterm = "CIF", currencyCode = "EUR", priceListId = 7,
    fillRatePct = 100.0, onTimePct = 98.0, leadTimeDays = 7, disputeCount = 0 }
]

customerDim = relation [
  { customerId = 1, customerName = "Northwind Cycles", segment = "Retail",
    region = "North America", country = "US" },
  { customerId = 2, customerName = "Ardennes Sport",   segment = "Wholesale",
    region = "Europe",        country = "BE" }
]

productDim = relation [
  { productId = 100, productName = "Trail 900 frameset", productLine = "bikes",
    family = "Mountain", tier = "Premium" },
  { productId = 200, productName = "Storm jersey",       productLine = "apparel",
    family = "Tops",     tier = "Core" },
  { productId = 300, productName = "Sealed hub bearing", productLine = "spares",
    family = "Drivetrain", tier = "Value" }
]

ledger = orderLine ** customerDim ** productDim

-- ------------------------------------------------------------ pivot one: time
--
-- Narrow first.  A pivot's input row is exactly key + value + identity, so the
-- other twenty-three ledger columns are summed away before the transpose; what
-- is left is the identity `{customerName}`, the key `period` and the value
-- `netRevenue`.

byCustomerQuarter = groupBy {customerName, period} (sumBy netRevenue) ledger

quarterFulcrum =
  pivotColumn q4 "Q4" period netRevenue
    (pivotColumn q3 "Q3" period netRevenue
      (pivotColumn q2 "Q2" period netRevenue
        (pivotColumn q1 "Q1" period netRevenue
          (startPivot period netRevenue))))

-- One row per customer; four revenue columns.
revenueByQuarter = pivotBy quarterFulcrum byCustomerQuarter

-- ------------------------------------------------------- pivot two: product
--
-- The same ledger, the same value column, a different key: the three product
-- lines become three columns, and the identity is now customer AND quarter.

byCustomerLine = groupBy {customerName, period, productLine} (sumBy netRevenue) ledger

lineFulcrum =
  pivotColumn spares  "spares"  productLine netRevenue
    (pivotColumn apparel "apparel" productLine netRevenue
      (pivotColumn bikes   "bikes"   productLine netRevenue
        (startPivot productLine netRevenue)))

-- One row per customer per quarter; three revenue columns.
revenueByLine = pivotBy lineFulcrum byCustomerLine

-- ----------------------------------------------------------------- reporting
--
-- A legend pins the column order, which matters more for a pivoted table than
-- for any other: the four quarters have no natural order in the row type, and
-- without a legend they come out in whatever order the header hashes to.

quarterLegend : Legend_Lg (| customerName, q1, q2, q3, q4 |)
quarterLegend = [ (customerName, "Customer") ^ 0
                , (q1, "Q1") ^ 1
                , (q2, "Q2") ^ 2
                , (q3, "Q3") ^ 3
                , (q4, "Q4") ^ 4 ]_Sorted_Lg

lineLegend : Legend_Lg (| customerName, period, bikes, apparel, spares |)
lineLegend = [ (customerName, "Customer") ^ 0
             , (period,  "Quarter") ^ 1
             , (bikes,   "Bikes")   ^ 2
             , (apparel, "Apparel") ^ 3
             , (spares,  "Spares")  ^ 4 ]_Sorted_Lg

quarterTable = tabular_K ([tabLegend_O := quarterLegend]_Opt) revenueByQuarter
lineTable    = tabular_K ([tabLegend_O := lineLegend]_Opt)    revenueByLine

salesReport = vflow [
  atomShown "## Sales ledger",
  atomShown "### Net revenue by quarter",
  quarterTable,
  atomShown "### Net revenue by product line",
  lineTable,
  atomShown "### The ledger it came from (long form)",
  tabular Nothing (ledger # { customerName, period, productLine, netRevenue, unitsShipped })
]
