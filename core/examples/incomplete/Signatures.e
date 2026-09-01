module Incomplete.Signatures where

{- THE SMALLER SIGNATURES, AND MACHINE-CHECKED PROOF THAT THEY SAY THE SAME.

   For each query in this directory this file holds

     xFull     -- the body, carrying VERBATIM the constraint set the compiler
                  infers for it in the query file, and
     xDeduped  -- the same constraint set with the redundant members deleted,
                  DEFINED AS `= xFull`.

   That definition is the proof. Checking `xDeduped = xFull` means assuming the
   deduped constraints and discharging the full ones, so if the module compiles
   then the deduped set ENTAILS the full set. The full set trivially entails the
   deduped one, being a superset. The two are therefore equivalent, and the
   constraints the solver added are noise it could not see was noise.

   Where a signature is a specialisation rather than an equivalent -- the
   signature a person would actually write -- it is named `xSimple` and gets its
   body written out instead, so that its checking still proves the body has that
   type.

   KEEP THIS FILE SEPARATE from the query files: an annotated copy of a body in
   the same module as the unannotated one perturbs what the unannotated one
   infers.
-}

import Prelude
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation
import Date

-- ------------------------------------------------ two facts used throughout

-- `r <- (r)` is a tautology: `taut`'s constraint is discharged at a call site
-- with NO constraint whatsoever in scope, so every occurrence of it in a
-- residual is pure noise.
taut : r <- (r) => Relation r -> Relation r
taut x = x

tautIsFree : Relation r -> Relation r
tautIsFree x = taut x

-- The right-hand side of a partition constraint is a SET. The rotations entail
-- one another, so of any group of permuted copies all but one are noise.
permA : t <- (a, b, c) => Relation t -> Relation t
permA x = x
permB : t <- (c, a, b) => Relation t -> Relation t
permB x = permA x
permC : t <- (b, c, a) => Relation t -> Relation t
permC x = permB x

perm2A : t <- (a, b) => Relation t -> Relation t
perm2A x = x
perm2B : t <- (b, a) => Relation t -> Relation t
perm2B x = perm2A x

-- ---------------------------------------------------------- RunCalibration

-- The LARGER of the two residuals RunCalibration.e emits, verbatim, all fifteen.
valueAsOfFormA : ( r <- (r)
                 , r1 <- (c1, r)
                 , r2 <- (d, r)
                 , f <- (r, c1, h)
                 , f <- (r, g, d)
                 , r1 <- (i, g)
                 , c <- (d, e)
                 , c <- (e, d)
                 , r2 <- (h, i)
                 , f <- (h, i, g)
                 , f <- (d, r, g)
                 , o <- (k, j)
                 , a <- (j, l)
                 , a <- (r, e)
                 , b <- (k, j, l) )
              => Field r Date -> Relation r1 -> Relation a -> Relation b
valueAsOfFormA d ts ps = withFieldCopy d (d' ->
  let nearest = nearestDateWithin (f -> dateAdd_Op 5 days (col_Op f))
                                  d (ts # {d}) d' (rename d d' ps # {d'})
      ts' = except {d'} . [| d = d' |] ' join nearest ts
  in join ts' ps)

-- The SMALLER residual the SAME FILE emits on other runs, minus its one
-- tautology: nine constraints, discharging all fifteen above.
valueAsOfFormB : ( a <- (i, r)
                 , r1 <- (h, g)
                 , t <- (h, g, f)
                 , r21 <- (e, d)
                 , a <- (d, c)
                 , b <- (e, d, c)
                 , r2 <- (g, f)
                 , r1 <- (r, c1)
                 , t <- (f, c1, r) )
              => Field r Date -> Relation r1 -> Relation a -> Relation b
valueAsOfFormB = valueAsOfFormA

-- And the other direction, so the file proves the two sets EQUIVALENT: Form A's
-- fifteen discharged from Form B's nine.
valueAsOfFormAviaB : ( r <- (r)
                     , r1 <- (c1, r)
                     , r2 <- (d, r)
                     , f <- (r, c1, h)
                     , f <- (r, g, d)
                     , r1 <- (i, g)
                     , c <- (d, e)
                     , c <- (e, d)
                     , r2 <- (h, i)
                     , f <- (h, i, g)
                     , f <- (d, r, g)
                     , o <- (k, j)
                     , a <- (j, l)
                     , a <- (r, e)
                     , b <- (k, j, l) )
                  => Field r Date -> Relation r1 -> Relation a -> Relation b
valueAsOfFormAviaB = valueAsOfFormB

-- What a person writes: one constraint per join leg. A specialisation.
valueAsOfSimple : (r1 <- (k, s), r2 <- (k, t), r3 <- (k, s, t))
               => Field k Date -> Relation r1 -> Relation r2 -> Relation r3
valueAsOfSimple d ts ps = withFieldCopy d (d' ->
  let nearest = nearestDateWithin (f -> dateAdd_Op 5 days (col_Op f))
                                  d (ts # {d}) d' (rename d d' ps # {d'})
      ts' = except {d'} . [| d = d' |] ' join nearest ts
  in join ts' ps)

-- ------------------------------------------------------------ RevenueShare

-- The inferred set, verbatim: fifteen row constraints and seventeen
-- existentials, for "group, total, divide".
shareOfGroupFull : ( PrimitiveNum n
                   , e1 <- (g, j)
                   , kv2 <- (b, f1)
                   , r <- (t1, b)
                   , kv <- (t1, b, f1)
                   , d <- (f, e)
                   , t <- (rs, so, ro)
                   , i <- (h, g, j)
                   , i <- (o, f, e, d1)
                   , i <- (rs, ro)
                   , e1 <- (f1, d)
                   , c1 <- (rs, so)
                   , kv <- (h, g)
                   , c2 <- (f, e, d1)
                   , b <- (e, d1)
                   , kv2 <- (f1, b) )
                => Row a -> Field b n -> Field d n -> Field c1 n
                -> Mem kv -> Mem t
shareOfGroupFull keyRow amtF totF pctF r =
  let totals = rename amtF totF (groupBy keyRow (sumBy amtF) r)
  in combine_Op (col_Op amtF /_Op col_Op totF) pctF (join r totals)

-- The same set minus the four redundant members: `kv2 <- (b, f1)` and
-- `kv2 <- (f1, b)` (a permuted pair, and `kv2` occurs nowhere else, so together
-- they only assert `b` and `f1` disjoint, which `kv <- (t1, b, f1)` says);
-- `r <- (t1, b)` (`r` occurs nowhere else; `kv <- (t1, b, f1)` says it); and
-- `c2 <- (f, e, d1)` (`c2` occurs nowhere else; `i <- (o, f, e, d1)` says it).
shareOfGroupDeduped : ( PrimitiveNum n
                      , e1 <- (g, j)
                      , kv <- (t1, b, f1)
                      , d <- (f, e)
                      , t <- (rs, so, ro)
                      , i <- (h, g, j)
                      , i <- (o, f, e, d1)
                      , i <- (rs, ro)
                      , e1 <- (f1, d)
                      , c1 <- (rs, so)
                      , kv <- (h, g)
                      , b <- (e, d1) )
                   => Row a -> Field b n -> Field d n -> Field c1 n
                   -> Mem kv -> Mem t
shareOfGroupDeduped = shareOfGroupFull

-- "the input, plus the group total, plus the share". A specialisation.
shareOfGroupSimple : ( PrimitiveNum n
                     , kv <- (key, amt, rest)
                     , wt <- (kv, tot)
                     , out <- (wt, pct) )
                  => Row key -> Field amt n -> Field tot n -> Field pct n
                  -> Mem kv -> Mem out
shareOfGroupSimple keyRow amtF totF pctF r =
  let totals = rename amtF totF (groupBy keyRow (sumBy amtF) r)
  in combine_Op (col_Op amtF /_Op col_Op totF) pctF (join r totals)

-- ------------------------------------------------------------- TopReadings

topRowsByFull : (h <- (h), b <- (h, c), RelationalComb rel)
             => Row h -> Int -> rel b -> rel b
topRowsByFull h n r = join r (topK h n (r # h))

-- The tautology deleted. What is left, `exists c. b <- (h, c)`, is exactly the
-- `Has b h` alias, which is how a person spells it.
topRowsByDeduped : (Has b h, RelationalComb rel)
                => Row h -> Int -> rel b -> rel b
topRowsByDeduped = topRowsByFull

-- ----------------------------------------------------- RecalibratedColumns

overwriteWithFull : (RelationalComb rel, r <- (a, e, c), r2 <- (e, a), d <- (e, c))
                 => Field a t -> Field c t -> rel r -> rel d
overwriteWithFull f1 f2 r = rename f1 f2 (except {f2} r)

-- `r2 <- (e, a)` deleted: `r2` occurs nowhere else, so the constraint only
-- asserts that `e` and `a` are disjoint, which the kept `r <- (a, e, c)` says.
overwriteWithDeduped : (RelationalComb rel, r <- (a, e, c), d <- (e, c))
                    => Field a t -> Field c t -> rel r -> rel d
overwriteWithDeduped = overwriteWithFull

-- -------------------------------------------------------------- TargetList

-- What a person writes: the key list carries the key columns, the relation
-- carries them plus the rest, and the RESULT IS THE RELATION UNCHANGED -- one
-- constraint, and no third row variable. A specialisation.
restrictToSimple : (Relational rel, r <- (k, o))
                => Row k -> rel k -> rel r -> rel r
restrictToSimple k keys r = join r (join keys (r # k))
