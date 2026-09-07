module Algebra.OrderLedger where

{- FIVE WAYS TO JOIN A DIMENSION THAT IS MISSING ROWS, side by side on one
   fact table.

   The order ledger references five dimensions and three of them are
   incomplete: a customer, a channel and two sales reps have no dimension row.
   A plain natural join silently DROPS those order lines -- the single most
   common reporting bug there is -- so this report computes the same
   enrichment six ways and puts the row counts next to each other.

   Fact:       orderLines (16 columns)
                 orderId, lineNo, orderDate, customerId, productId, channelId,
                 warehouseId, salesRepId, quantity, unitPrice, discountPct,
                 taxPct, freightCost, currencyCode, orderStatus, promoCode
   Dimensions: customerDim (customerId -> customerName, customerTier,
                            customerCountry)          -- customer 4004 missing
               productDim  (productId  -> productName, productCategory,
                            listPrice)                -- complete
               channelDim  (channelId  -> channelName) -- channel 3 missing
               repDim      (salesRepId -> repName, repTeam) -- 2 reps missing

   Helpers used: enrich, enrichRight, lookupOr, semiJoin, antiJoin,
                 intersectRows, exceptRows, groupSum.

   SOLVER SHAPES. `lookupOr` is `Relation.joinWithDefault`, whose constraint
   set is the stdlib's only EXISTENTIALLY quantified one (`exists c s.`); this
   file instantiates it twice, once against a 16-column fact table. `enrich`
   instantiates a three-way partition where the third part is a RECORD row
   rather than a relation row. The anti-join is a `difference` whose two
   operands must be proved to have the same 16-column header, which is the
   `concrete` branch of the solver on a wide row.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/OrderLedger.e
     >> :import Algebra.OrderLedger
     >> ledgerReport
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Algebra.Helpers

field orderId, lineNo, customerId, productId, channelId : Int
field warehouseId, salesRepId : Int
field orderDate, currencyCode, orderStatus, promoCode : String
field customerName, customerTier, customerCountry : String
field productName, productCategory, channelName, repName, repTeam : String
field quantity, unitPrice, discountPct, taxPct, freightCost, listPrice : Double
field lineTotal, tierTotal : Double

-- ------------------------------------------------------------------ the fact

orderLines : [ orderId, lineNo, orderDate, customerId, productId, channelId
             , warehouseId, salesRepId, quantity, unitPrice, discountPct
             , taxPct, freightCost, currencyCode, orderStatus, promoCode ]
orderLines = relation [
  { orderId = 9001, lineNo = 1, orderDate = "2026-01-04", customerId = 4001
  , productId = 5001, channelId = 1, warehouseId = 7001, salesRepId = 6001
  , quantity = 12.0, unitPrice = 41.50, discountPct = 0.05, taxPct = 0.20
  , freightCost = 18.40, currencyCode = "EUR", orderStatus = "shipped"
  , promoCode = "NEWYEAR" },
  { orderId = 9001, lineNo = 2, orderDate = "2026-01-04", customerId = 4001
  , productId = 5002, channelId = 1, warehouseId = 7001, salesRepId = 6001
  , quantity = 3.0, unitPrice = 220.00, discountPct = 0.00, taxPct = 0.20
  , freightCost = 0.00, currencyCode = "EUR", orderStatus = "shipped"
  , promoCode = "" },
  { orderId = 9002, lineNo = 1, orderDate = "2026-01-07", customerId = 4002
  , productId = 5003, channelId = 2, warehouseId = 7002, salesRepId = 6002
  , quantity = 40.0, unitPrice = 9.99, discountPct = 0.10, taxPct = 0.00
  , freightCost = 6.25, currencyCode = "USD", orderStatus = "invoiced"
  , promoCode = "BULK40" },
  { orderId = 9003, lineNo = 1, orderDate = "2026-01-09", customerId = 4003
  , productId = 5001, channelId = 3, warehouseId = 7001, salesRepId = 6003
  , quantity = 5.0, unitPrice = 41.50, discountPct = 0.00, taxPct = 0.19
  , freightCost = 11.00, currencyCode = "EUR", orderStatus = "shipped"
  , promoCode = "" },
  { orderId = 9004, lineNo = 1, orderDate = "2026-01-11", customerId = 4004
  , productId = 5004, channelId = 1, warehouseId = 7003, salesRepId = 6001
  , quantity = 1.0, unitPrice = 1850.00, discountPct = 0.02, taxPct = 0.20
  , freightCost = 95.00, currencyCode = "GBP", orderStatus = "pending"
  , promoCode = "" },
  { orderId = 9005, lineNo = 1, orderDate = "2026-01-14", customerId = 4002
  , productId = 5002, channelId = 2, warehouseId = 7002, salesRepId = 6004
  , quantity = 8.0, unitPrice = 220.00, discountPct = 0.15, taxPct = 0.00
  , freightCost = 22.10, currencyCode = "USD", orderStatus = "shipped"
  , promoCode = "SPRING" },
  { orderId = 9006, lineNo = 1, orderDate = "2026-01-18", customerId = 4003
  , productId = 5003, channelId = 3, warehouseId = 7003, salesRepId = 6003
  , quantity = 60.0, unitPrice = 9.99, discountPct = 0.20, taxPct = 0.19
  , freightCost = 4.75, currencyCode = "EUR", orderStatus = "cancelled"
  , promoCode = "BULK40" },
  { orderId = 9007, lineNo = 1, orderDate = "2026-01-21", customerId = 4001
  , productId = 5004, channelId = 2, warehouseId = 7001, salesRepId = 6002
  , quantity = 2.0, unitPrice = 1850.00, discountPct = 0.00, taxPct = 0.20
  , freightCost = 140.00, currencyCode = "EUR", orderStatus = "shipped"
  , promoCode = "" }
]

-- ----------------------------------------------------------- the dimensions

-- customer 4004 was created after the dimension was last loaded
customerDim : [customerId, customerName, customerTier, customerCountry]
customerDim = relation [
  { customerId = 4001, customerName = "Aurora Retail",  customerTier = "gold",   customerCountry = "DE" },
  { customerId = 4002, customerName = "Basalt Trading", customerTier = "silver", customerCountry = "US" },
  { customerId = 4003, customerName = "Cinder & Co",    customerTier = "gold",   customerCountry = "NL" }
]

productDim : [productId, productName, productCategory, listPrice]
productDim = relation [
  { productId = 5001, productName = "Desk lamp, 12W LED",    productCategory = "lighting",  listPrice = 44.00 },
  { productId = 5002, productName = "Task chair, mesh back", productCategory = "seating",   listPrice = 235.00 },
  { productId = 5003, productName = "Cable tidy, 2m",        productCategory = "accessory", listPrice = 10.50 },
  { productId = 5004, productName = "Standing desk, 180cm",  productCategory = "surfaces",  listPrice = 1899.00 }
]

-- channel 3 ("partner") was never given a row
channelDim : [channelId, channelName]
channelDim = relation [
  { channelId = 1, channelName = "web" },
  { channelId = 2, channelName = "field sales" }
]

repDim : [salesRepId, repName, repTeam]
repDim = relation [
  { salesRepId = 6001, repName = "R. Okonjo", repTeam = "north" },
  { salesRepId = 6002, repName = "M. Haldi",  repTeam = "north" }
]

-- ----------------------------------------------------- 1. the naive join
-- Every order line whose customer, product, channel AND rep all have a
-- dimension row. Four of the eight lines survive; nothing says so.
naiveJoin = orderLines ** customerDim ** productDim ** channelDim ** repDim

-- ------------------------------------------- 2. a default record per dimension
-- `enrich` keeps every left row and fills the dimension's private columns
-- from a record. The record's row IS the dimension's non-key row -- write one
-- column too few and the module does not check (see shouldfail/alg01).
withCustomer =
  enrich orderLines customerDim
    { customerName = "(unknown customer)"
    , customerTier = "unrated"
    , customerCountry = "??" }

withRep =
  enrich withCustomer repDim
    { repName = "(house account)", repTeam = "unassigned" }

-- --------------------------------------- 3. a default for ONE added column
-- `lookupOr` is the single-column case, and the only stdlib signature with
-- existentially quantified row variables. The default is a value, not a record.
withChannel = lookupOr channelName "(partner)" withRep channelDim

fullyEnriched = withChannel ** productDim

-- ----------------------------------------------- 4. which rows were missing
-- The anti-join names the damage the naive join would have done silently.
ordersWithNoCustomer = antiJoin {customerId} customerDim orderLines
ordersWithNoChannel  = antiJoin {channelId}  channelDim  orderLines
ordersWithNoRep      = antiJoin {salesRepId} repDim      orderLines

-- ----------------------------------------------- 5. and which rows survive
ordersWithACustomer = semiJoin {customerId} customerDim orderLines

-- The two halves partition the fact table: their intersection is empty and
-- their difference-from-the-whole is the other half. `intersectRows` and
-- `exceptRows` need both operands to carry the same 16 columns, which is what
-- makes them well-typed here at all.
partitionCheckEmpty = intersectRows ordersWithACustomer ordersWithNoCustomer
partitionCheckAll   = exceptRows orderLines ordersWithACustomer

-- ------------------------------------------ 6. the dimension's unused rows
-- The other direction: dimension rows no fact row references.
unusedCustomers = antiJoin {customerId} orderLines customerDim

-- and the outer join that KEEPS them. `enrichRight` is `enrich` with the sides
-- swapped: every row of the SECOND operand survives and the FIRST operand's
-- private columns are defaulted. Note how narrow the left operand has to be --
-- the default record's row is everything the left side does not share, so
-- passing the whole 16-column fact table would need a sixteen-field record.
everyCustomer =
  enrichRight (orderLines # {customerId, orderId}) customerDim { orderId = 0 }

-- ------------------------------------------------------------- the measures

priced = combine_Op
  (col_Op quantity *_Op col_Op unitPrice *_Op
    (prim_Op 1.0 -_Op col_Op discountPct))
  lineTotal
  fullyEnriched

revenueByTier = rename lineTotal tierTotal (groupSum {customerTier} lineTotal priced)

-- ---------------------------------------------------------------- the report

ledgerReport = vflow [
  atomShown "## Order ledger: six ways to meet a missing dimension row",
  atomShown "### 1. Natural join -- four of eight lines silently gone",
  tabular Nothing naiveJoin,
  atomShown "### 2-3. Outer joins with defaults -- all eight lines kept",
  tabular Nothing priced,
  atomShown "### 4. Anti-joins: the lines the natural join would have dropped",
  tabular Nothing ordersWithNoCustomer,
  tabular Nothing ordersWithNoChannel,
  tabular Nothing ordersWithNoRep,
  atomShown "### 5. Semi-join: the lines it would have kept",
  tabular Nothing ordersWithACustomer,
  atomShown "### 6. Dimension rows nothing references",
  tabular Nothing unusedCustomers,
  atomShown "### ...and the same dimension with every row kept",
  tabular Nothing everyCustomer,
  atomShown "### Revenue by customer tier",
  tabular Nothing revenueByTier
]
