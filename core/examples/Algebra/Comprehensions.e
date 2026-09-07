module Algebra.Comprehensions where

{- THE SAME REPORT WRITTEN TWICE -- once as `combine`/`filter`/`rename`, once as
   `[| ... |]` -- plus the three outer-join spellings the rest of this directory
   does not use, and a running total computed two ways.

   `Syntax.Relation` is a PARSE-TIME rewrite, not a library: the module's own
   header says the tricks happen "before typing". Inside `[| ... |]`,

     `f = expr`   becomes  combine (the Op built from expr) f
     `pred`       becomes  filter (the Predicate built from pred)
     `g <- f`     becomes  rename f g

   applied LEFT TO RIGHT, so a later clause sees the columns the earlier ones
   made. Bare column names inside the brackets are rewritten to `col`, and bare
   literals to `prim`, which is the whole convenience: the longhand form has to
   say `col_Op`/`prim_Op` at every leaf.

   Because it is a rewrite and not a function, the two forms produce THE SAME
   TERM, and this file proves it the cheapest way there is: it puts each pair in
   a two-element list, which does not type-check unless both members have the
   same type.

   Table: orders (12 columns)
            orderNo, orderSeq, orderDate, region, channel, repCode, currencyCode,
            isReturn, unitsSold, unitPrice, unitCost, discountPct
   Dimensions: regionDim (region -> regionName)   -- "SW" missing on purpose
               channelDim (channel -> channelName) -- "partner" missing

   Helpers used: lookupOrRight, rightOuter, translateKeeping, runningTotal,
                 groupSum, antiJoin.
   Stdlib exercised: `Syntax.Relation`'s `[| ... |]` in all three of its forms
                 and in combination. Measured 2026-09-07: four pre-existing
                 example files use the syntax and none of them exercises it --
                 `Yahoo.e:202` and `incomplete/RunCalibration.e:147` (with its copy
                 in `incomplete/Signatures.e`) each use ONE clause of ONE form,
                 and `ChartsExample.e:439` has one inside a comment. The
                 stdlib's own `Syntax/Relation.e` header and the test module
                 `core/src/test/resources/modules/Syntax/RelationTest.e` are the
                 only places where the combined form appears at all, and neither
                 is an example a user reads. Also: `Relation.rightJoinWithDefault`,
                 `Relation.unsafeRightJoin`, `Relation.partialLookup'` (none had
                 an example use anywhere); `Relation.Scan.transform` over the
                 record vector.

   SOLVER SHAPES. The comprehension is where the stdlib's `exists`-heavy
   inferred residuals come from: `Syntax/Relation.e`'s own header shows the
   three-clause form inferring
   `(exists o t. a <- ((|y|), r), t <- ((|x|), r), r <- ((|z|), o))`, which is
   two more existential row variables than any hand-written signature in
   `Helpers.e`. `runningTotal` is the group's only DELIBERATE cartesian product
   (two renamed copies with nothing in common) and its only nested
   `withFieldCopy`, so the solver meets two GUID-named labels in one solve.

     >> :load core/examples/Algebra/Helpers.e
     >> :load core/examples/Algebra/Comprehensions.e
     >> :import Algebra.Comprehensions
     >> bothMarginForms
     >> withRunningBalance
-}

import Prelude
import Layout
import Layout.Scan as Sc
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Vector as V
import Algebra.Helpers

field orderNo, orderSeq : Int
-- `currency` would clash with `Layout.Format.currency` / `Layout.Report.currency`,
-- which `Layout` re-exports; the clash is reported as
-- "failed to unify type Field with type (->)" at the RECORD LITERAL, not at
-- the declaration. `currencyCode` is the name the rest of this directory uses.
field orderDate, region, channel, repCode, currencyCode, isReturn : String
field regionName, channelName : String
field unitsSold, unitPrice, unitCost, discountPct : Double
field revenueEur, costEur, marginEur, marginPct, profitEur : Double
field balanceEur, regionTotal : Double

orders : [ orderNo, orderSeq, orderDate, region, channel, repCode, currencyCode
         , isReturn, unitsSold, unitPrice, unitCost, discountPct ]
orders = relation [
  { orderNo = 5001, orderSeq = 1, orderDate = "2026-02-02", region = "NE", channel = "web",     repCode = "R1", currencyCode = "EUR", isReturn = "no",  unitsSold =  40.0, unitPrice =  22.50, unitCost = 14.00, discountPct = 0.00 },
  { orderNo = 5002, orderSeq = 2, orderDate = "2026-02-03", region = "NE", channel = "partner", repCode = "R1", currencyCode = "EUR", isReturn = "no",  unitsSold =   6.0, unitPrice = 310.00, unitCost = 205.00, discountPct = 0.10 },
  { orderNo = 5003, orderSeq = 3, orderDate = "2026-02-05", region = "SW", channel = "web",     repCode = "R2", currencyCode = "EUR", isReturn = "no",  unitsSold = 120.0, unitPrice =   9.90, unitCost =  6.40, discountPct = 0.05 },
  { orderNo = 5004, orderSeq = 4, orderDate = "2026-02-07", region = "SW", channel = "field",   repCode = "R2", currencyCode = "EUR", isReturn = "yes", unitsSold =  -6.0, unitPrice = 310.00, unitCost = 205.00, discountPct = 0.10 },
  { orderNo = 5005, orderSeq = 5, orderDate = "2026-02-09", region = "NW", channel = "field",   repCode = "R3", currencyCode = "EUR", isReturn = "no",  unitsSold =  15.0, unitPrice = 128.00, unitCost = 96.00, discountPct = 0.15 },
  { orderNo = 5006, orderSeq = 6, orderDate = "2026-02-11", region = "NE", channel = "web",     repCode = "R1", currencyCode = "EUR", isReturn = "no",  unitsSold =  90.0, unitPrice =   9.90, unitCost =  6.40, discountPct = 0.00 },
  { orderNo = 5007, orderSeq = 7, orderDate = "2026-02-14", region = "NW", channel = "partner", repCode = "R3", currencyCode = "EUR", isReturn = "no",  unitsSold =   2.0, unitPrice = 980.00, unitCost = 740.00, discountPct = 0.20 },
  { orderNo = 5008, orderSeq = 8, orderDate = "2026-02-16", region = "SW", channel = "web",     repCode = "R2", currencyCode = "EUR", isReturn = "no",  unitsSold =  55.0, unitPrice =  22.50, unitCost = 14.00, discountPct = 0.05 }
]

-- "SW" is deliberately absent: the lookups below are where you see it.
regionDim : [region, regionName]
regionDim = relation [
  { region = "NE", regionName = "North East" },
  { region = "NW", regionName = "North West" }
]

-- "partner" is deliberately absent.
channelDim : [channel, channelName]
channelDim = relation [
  { channel = "web",   channelName = "Web store" },
  { channel = "field", channelName = "Field sales" }
]

-- ================================================ 1. the same thing, twice

-- LONGHAND. Every leaf says `col_Op` or `prim_Op`, and every step names the
-- combinator. Three `combine`s, one per derived column.
longhandMargin =
  combine_Op (col_Op unitsSold *_Op col_Op unitPrice *_Op
              (prim_Op 1.0 -_Op col_Op discountPct)) revenueEur orders
  |> combine_Op (col_Op unitsSold *_Op col_Op unitCost) costEur
  |> combine_Op (col_Op revenueEur -_Op col_Op costEur) marginEur

-- COMPREHENSION. The same three steps, and `marginEur`'s clause sees the two
-- columns the clauses before it made, because the rewrite is left to right.
comprehensionMargin =
  [| revenueEur = unitsSold * unitPrice * (1.0 - discountPct),
     costEur    = unitsSold * unitCost,
     marginEur  = revenueEur - costEur |] orders

-- THE PROOF. A two-element list does not type-check unless both members have
-- the same type, and neither definition is annotated -- so this line is a
-- machine-checked statement that the rewrite produced what the longhand says.
bothMarginForms = [longhandMargin, comprehensionMargin]

-- ================================================ 2. the three clause forms

-- FILTER only. A bare boolean clause becomes `filter`; `&&`, `||` and the
-- comparisons come from `Relation.Predicate` and work on columns, not values.
bigProfitable = [| marginEur > 200.0 && isReturn == "no" |] comprehensionMargin

-- The longhand of the same thing, for comparison.
bigProfitableLonghand =
  filter_Pred (col_Op marginEur >_Pred prim_Op 200.0 &&_Pred
               col_Op isReturn ==_Pred prim_Op "no") comprehensionMargin

bothFilterForms = [bigProfitable, bigProfitableLonghand]

-- RENAME only. `g <- f` is `rename f g`; the arrow points the way the DATA
-- moves, which is the opposite of how an assignment reads.
renamedOnly = [| profitEur <- marginEur |] comprehensionMargin
bothRenameForms = [renamedOnly, alias marginEur profitEur comprehensionMargin]

-- ALL THREE IN ONE BRACKET, in the order they are applied: derive, restrict,
-- rename. This is the form `Syntax/Relation.e`'s header advertises, and the
-- one whose inferred residual carries the extra existentials.
pipeline =
  [| marginPct  = (unitPrice - unitCost) / unitPrice,
     marginPct > 0.3,
     profitEur <- marginPct |] orders

-- =========================================== 3. the outer joins not used yet

-- `lookupOrRight` (`Relation.rightJoinWithDefault`) is `lookupOr` with the
-- dimension first: the FACT rows survive and the missing channel name is
-- filled in.
withChannelName = lookupOrRight channelName "(partner)" channelDim orders

-- `rightOuter` (`Relation.unsafeRightJoin`) is the same join with NO default.
-- Every order survives and `regionName` is NULL for the SW orders -- which is
-- exactly why the type is a lie and why the two helpers above exist.
withRegionOrNull = rightOuter regionDim orders

-- `translateKeeping` (`Relation.partialLookup'`) keeps BOTH columns, and the
-- new one is `coalesce' regionName region`: it holds the display name where the
-- lookup had a row and the RAW CODE where it did not. Comparing the two columns
-- is how you audit a lookup, and it is the reason the primed form exists.
withRegionAudited = translateKeeping region regionName regionDim orders

-- and the plain anti-join that says the same thing as a set
regionsWithNoName = antiJoin {region} regionDim orders

-- ================================================ 4. a running total, twice

-- RELATIONALLY. `runningTotal` is a deliberate cartesian product of two renamed
-- copies, filtered by `<=` and grouped -- the mechanism SQL without `OVER` has
-- to use. It gives back a RELATION, so it can be joined against anything.
withRunningBalance =
  runningTotal orderSeq revenueEur balanceEur
               (asMem (comprehensionMargin # {orderSeq, revenueEur, orderNo, region}))

-- BY SCANNING. `Relation.Scan` pulls the rows into a vector of records and
-- hands them to ordinary code, so one left fold does it in one pass instead of
-- n^2 comparisons. The price is in the type: a `Scan z a` is a `Cont` whose
-- answer type is fixed to `Report` by `Layout.Scan`, so this CANNOT be joined
-- against anything -- it is a one-way door out of the algebra.
-- (`scan` and `transform` are reached under `Layout.Scan`'s own suffix: plain
-- `scan` is ambiguous, because `Layout.Report` exports one too and `Layout`
-- re-exports it. The clash is reported as `undefined term`, not as an
-- ambiguity, which costs a minute to diagnose the first time.)
runningBalanceScan =
  scan_Sc (comprehensionMargin # {orderSeq, revenueEur})
  |> transform_Sc accumulate1

private
  -- The fold itself: carry the running sum, `cons` it onto each record. This is
  -- the one place in the directory where a ROW is built by hand.
  accumulate1 vs =
    vector_V (reverse (snd (foldl_V step (0.0, []) vs)))
    where step (acc, out) t =
            let a = acc + (t ! revenueEur)
            in (a, cons balanceEur a t :: out)

-- ==================================================== 5. and the ordinary way

byRegion = rename revenueEur regionTotal
             (groupSum {region} revenueEur comprehensionMargin)

-- ---------------------------------------------------------------- the report

comprehensionReport = vflow [
  atomShown "## One report, two syntaxes",
  atomShown "### Margin, written longhand",
  tabular Nothing longhandMargin,
  atomShown "### The same, as a comprehension -- same type, proved by `bothMarginForms`",
  tabular Nothing comprehensionMargin,
  atomShown "### Filter clause",
  tabular Nothing bigProfitable,
  atomShown "### Derive, restrict and rename in one bracket",
  tabular Nothing pipeline,
  atomShown "### Right outer join with a default for the missing channel",
  tabular Nothing withChannelName,
  atomShown "### The same join with no default: NULL region names",
  tabular Nothing withRegionOrNull,
  atomShown "### partialLookup': both columns kept, so the misses are visible",
  tabular Nothing withRegionAudited,
  atomShown "### Regions the dimension does not name",
  tabular Nothing regionsWithNoName,
  atomShown "### Running balance, computed relationally",
  tabular Nothing withRunningBalance,
  atomShown "### Revenue by region",
  tabular Nothing byRegion
]
