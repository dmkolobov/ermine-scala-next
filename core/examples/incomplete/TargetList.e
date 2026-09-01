module Incomplete.TargetList where

{- SCENARIO -- cut an order book down to a campaign's target list.

   Two tables:

     orders  (orderId, region, bookingMonth, productLine, amount)
     targets (region, bookingMonth)

   `targets` is the list of (region, month) cells the campaign covers. Keep the
   order lines whose key is on it, and keep every column of the order line.
   Written as a semijoin through the key projection:

     restrictTo k targets r = join r (join targets (r # k))

   WHAT A COMPETENT USER EXPECTS -- a semijoin does not change the shape of the
   relation, so the result type IS the argument type:

       restrictTo : (Relational rel, r <- (k, o)) => Row k -> rel k -> rel r -> rel r

   One constraint. `Incomplete.Signatures.restrictToSimple` has that signature
   and it checks.

   WHAT ACTUALLY HAPPENS. Reproduce with

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/TargetList.e
     >> :type restrictTo

   Identical on every run:

     forall (r1: rho) (a: rho -> *) (b: rho) (c: rho) (d: rho).
       (exists (e: rho) (f: rho) (g: rho) (h: rho) (i: rho) (j: rho) (c1: rho)
       (k: rho). b <- (f, e),
       RelationalComb a,
       h <- (k, j),
       c <- (j, i),
       r1 <- (g, f),
       c <- (r1, c1),
       h <- (g, f, e),
       d <- (k, j, i)) =>
       Row r1 -> a b -> a c -> a d

   Seven partition constraints and EIGHT existential rows for a query that adds
   and removes no columns. The damage is not only the count: the inferred type
   does not say the output has the same columns as the input. It invents a third
   visible row variable `d` and ties it to the input `c` through the
   existentials `k`, `j` and `i` -- so a caller reads a function from `a c` to
   some unrelated `a d`, and has to solve seven constraints to discover that
   `d` is `c`.

   INCOMPLETENESS DEMONSTRATED -- THE RESIDUAL IS TRUE BUT USELESS. It is a
   correct description of the function that fails to communicate the one fact
   about it a caller needs, buried under eight rows the query never mentions.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Syntax.Relation
import Date

field orderId : Int
field region, productLine : String
field bookingMonth : Date
field amount : Double

orders = relation [
  { orderId = 1, region = "EMEA", bookingMonth = @2011/1/31, productLine = "Core",     amount = 120000.0 },
  { orderId = 2, region = "EMEA", bookingMonth = @2011/2/28, productLine = "Platform", amount =  84000.0 },
  { orderId = 3, region = "AMER", bookingMonth = @2011/1/31, productLine = "Core",     amount = 310000.0 },
  { orderId = 4, region = "APAC", bookingMonth = @2011/2/28, productLine = "Platform", amount =  95000.0 }
]

targets = relation [
  { region = "EMEA", bookingMonth = @2011/1/31 },
  { region = "AMER", bookingMonth = @2011/1/31 }
]

-- | Keep the rows of `r` whose `k` columns appear in `keys`.
restrictTo k keys r = join r (join keys (r # k))

inCampaign = restrictTo {region, bookingMonth} targets orders

campaignReport = vflow [
  atomShown "## Order lines inside the campaign",
  tabular Nothing inCampaign
]
