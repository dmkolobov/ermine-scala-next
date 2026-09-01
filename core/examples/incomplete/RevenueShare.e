module Incomplete.RevenueShare where

{- SCENARIO -- what fraction of its region's bookings did each rep write?

   One fact table:

     bookings (region, salesRep, productLine, bookingMonth, amount)

   The report everyone builds: roll the amounts up to the region, join the
   region total back onto every row, divide. Three steps, one line each,
   written below as `shareOfGroup`.

   WHAT A COMPETENT USER EXPECTS -- "the input, plus the group total, plus the
   share". Three constraints and one numeric class:

       shareOfGroup : (PrimitiveNum n, kv <- (key, amt, rest),
                       wt <- (kv, tot), out <- (wt, pct))
                   => Row key -> Field amt n -> Field tot n -> Field pct n
                   -> Mem kv -> Mem out

   `Incomplete.Signatures.shareOfGroupSimple` is this exact body under exactly
   that signature. It checks.

   WHAT ACTUALLY HAPPENS. Reproduce with

     ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
       core/examples/incomplete/RevenueShare.e
     >> :type shareOfGroup

   Fifteen row constraints over SEVENTEEN existential row variables, stable
   across runs up to renaming:

     forall (a: rho) (b: rho) c (d: rho) (c1: rho) (kv: rho) (t: rho).
       (exists (c2: rho) (d1: rho) (e: rho) (f: rho) (e1: rho) (f1: rho) (g: rho)
       (h: rho) (r: rho) (t1: rho) (kv2: rho) (so: rho) (rs: rho) (i: rho) (j: rho)
       (o: rho) (ro: rho). e1 <- (g, j),
       kv2 <- (b, f1),
       r <- (t1, b),
       kv <- (t1, b, f1),
       d <- (f, e),
       t <- (rs, so, ro),
       i <- (h, g, j),
       i <- (o, f, e, d1),
       i <- (rs, ro),
       e1 <- (f1, d),
       c1 <- (rs, so),
       PrimitiveNum c,
       kv <- (h, g),
       c2 <- (f, e, d1),
       b <- (e, d1),
       kv2 <- (f1, b)) =>
       Row a -> Field b c -> Field d c -> Field c1 c -> Mem kv -> Mem t

   Seventeen row variables. The user named four things: a key, an amount, a
   total and a percentage. Thirteen of the seventeen are rows the query never
   mentions and the caller can never see.

   FOUR OF THE FIFTEEN ARE REDUNDANT BY INSPECTION.

     * `kv2 <- (b, f1)` and `kv2 <- (f1, b)` are the same constraint with the
       right-hand side permuted. Worse, `kv2` occurs NOWHERE ELSE in the type,
       so together the pair asserts only that `b` and `f1` are disjoint -- which
       the kept `kv <- (t1, b, f1)` already asserts. Both are deletable.
     * `r <- (t1, b)`: `r` occurs nowhere else, so this asserts only that `t1`
       and `b` are disjoint. `kv <- (t1, b, f1)` asserts it.
     * `c2 <- (f, e, d1)`: `c2` occurs nowhere else, so this asserts only that
       `f`, `e` and `d1` are pairwise disjoint. `i <- (o, f, e, d1)` asserts it.

   `Incomplete.Signatures.shareOfGroupDeduped` is the remaining eleven, and it
   is defined as `= shareOfGroupFull`, where `shareOfGroupFull` carries all
   fifteen. That definition checking means the eleven ENTAIL the fifteen; the
   fifteen trivially entail the eleven, being a superset. The two constraint
   sets are equivalent, and the solver could not tell.

   INCOMPLETENESS DEMONSTRATED -- THE RESIDUAL IS TRUE BUT USELESS. A rollup and
   a division, three lines of query, and the type the user is handed is fifteen
   partition constraints and a swarm of seventeen existential rows, four of the
   constraints saying nothing the others do not.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Date

field region, salesRep, productLine : String
field bookingMonth : Date
field amount, regionTotal, pctOfRegion : Double

bookings = mem [
  { region = "EMEA", salesRep = "Aliyev",   productLine = "Core",     bookingMonth = @2011/1/31, amount = 120000.0 },
  { region = "EMEA", salesRep = "Aliyev",   productLine = "Platform", bookingMonth = @2011/2/28, amount =  84000.0 },
  { region = "EMEA", salesRep = "Bergqvist",productLine = "Core",     bookingMonth = @2011/1/31, amount = 196000.0 },
  { region = "AMER", salesRep = "Cardoso",  productLine = "Core",     bookingMonth = @2011/1/31, amount = 310000.0 },
  { region = "AMER", salesRep = "Cardoso",  productLine = "Platform", bookingMonth = @2011/2/28, amount = 155000.0 },
  { region = "AMER", salesRep = "Delacroix",productLine = "Platform", bookingMonth = @2011/2/28, amount =  95000.0 }
]

-- | Roll `amtF` up by `keyRow`, join the group total back on under `totF`,
-- and add each row's share of it under `pctF`.
shareOfGroup keyRow amtF totF pctF r =
  let totals = rename amtF totF (groupBy keyRow (sumBy amtF) r)
  in combine_Op (col_Op amtF /_Op col_Op totF) pctF (join r totals)

repShare = shareOfGroup {region} amount regionTotal pctOfRegion bookings

shareReport = vflow [
  atomShown "## Bookings as a share of the region total",
  tabular Nothing repShare
]
