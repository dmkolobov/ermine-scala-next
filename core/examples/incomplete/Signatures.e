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

   ---------------------------------------------------------------------------
   STAGE S3 (2026-09-07) CHANGED WHAT THE COMPILER INFERS FOR THESE BODIES

   Every `xFull` set below was transcribed BEFORE stage S3's change to
   `Subst.mkSimplified` (`tracker/loopmodel/S3-SIMPLIFY.md`).  `mkSimplified`
   has always documented that its first job is to "eliminate all but one
   permutation of a right hand side"; it never did it, because `NormalPart`
   overrode `equals` (ignoring the order of the parts) and not `hashCode`, and
   `List.distinct` buckets by hash.  Beside it, `normalPart` had a `None` case
   for the concrete identity `(|Foo|) <- (|Foo|)` and none for the variable
   identity `a <- (a)`.  Both are fixed, so a PUBLISHED residual no longer
   carries either -- and the two facts this file opens with, `taut` and
   `permA`/`permB`/`permC`, are exactly the two entailments that licence the
   deletions.  This module is where the fix was read out of.

   The three bodies below, re-measured (`S3-SIMPLIFY.md` §1, §6):

       topRowsBy    3 partitions -> 1  -- BOTH defects in one residual:
                                          `h <- (h)` and a permuted copy of
                                          `b <- (h, c)`.  What is left is exactly
                                          `topRowsByDeduped`, i.e. `Has b h`
       valueAsOf    the two residuals `RunCalibration.e` emits lose `r <- (r)` and
                    the `c <- (d, e)` / `c <- (e, d)` pair
       shareOfGroup loses the `kv2 <- (b, f1)` / `kv2 <- (f1, b)` pair

   NOTHING BELOW WAS CHANGED AND NOTHING BELOW STOPS CHECKING.  A DECLARED
   signature is published verbatim -- it does not pass through `mkSimplified` --
   so `taut`, every `xFull`, every `xDeduped` and every `= xFull` proof is
   exactly as it was, and `incomplete/Signatures.ei` still reads
   `taut : forall (r: rho). r <- (r) => ...`.  Read the `xFull` sets as "the
   residual before S3" and the file as the record of what S3 removed.

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
-- SINCE S3 (2026-09-07) three of the fifteen are no longer published for an
-- inferred residual: the tautology `r <- (r)` and the permuted pair
-- `c <- (d, e)` / `c <- (e, d)`.  The set is transcribed here as it was, and the
-- proofs below are untouched; it is the compiler's PRE-S3 answer.
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
-- existentials, for "group, total, divide".  SINCE S3 (2026-09-07) the permuted
-- pair `kv2 <- (b, f1)` / `kv2 <- (f1, b)` is no longer published twice, so an
-- inferred residual of this shape carries fourteen; the other three members
-- `shareOfGroupDeduped` deletes still need the entailment test `mkSimplified`
-- does not have.  The set below is the PRE-S3 answer and is left as it was --
-- it is also the residual `A1-REVIEW.md` §R-6 certifies at both dequeue-order
-- configurations.
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
--
-- AND SINCE S3 (2026-09-07) THE COMPILER PRODUCES THIS SIGNATURE ITSELF.  On a
-- virgin load `TopReadings.topRowsBy` published `b <- (c, h), h <- (h),
-- b <- (h, c)` -- the tautology AND a permuted duplicate, both defects in one
-- three-member residual -- and now publishes `b <- (h, c)` alone.  `topRowsByFull`
-- above is the pre-S3 answer, kept because this pair is the proof that deleting
-- the tautology was sound; `TopReadings.e`'s own header records the same
-- before/after.
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
