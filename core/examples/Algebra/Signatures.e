module Algebra.Signatures where

{- THE SIGNATURES IN `Helpers.e`, AND MACHINE-CHECKED PROOF THAT THEY SAY WHAT
   THE COMPILER INFERS.

   `Helpers.e` gives every helper an explicit signature written the way a
   person would write it. That is a claim, and this file is where the claim is
   discharged. For four of the helpers it holds

     xFull       -- the body, carrying VERBATIM the constraint set the compiler
                    infers for it when the signature is removed;
     xDeduped    -- the same set with the redundant members deleted, DEFINED AS
                    `= xFull`; and
     xAsWritten  -- the signature `Helpers.e` actually carries, also defined as
                    `= xFull`, plus the reverse definition so the two are
                    proved EQUIVALENT rather than merely comparable.

   One of the three (`antiJoin`) turns out to be a pure renaming of its own
   deduped set; the other two are substantive. The file says which is which,
   because a proof that proves nothing is worse than no proof.

   A definition `p = q` is the proof: checking it means ASSUMING p's
   constraints and DISCHARGING q's, so if this module compiles then p entails
   q. Writing both directions gives equivalence.

   The inferred sets were read out of the REPL on 2026-09-06 at the adopted
   defaults (`-Dermine.rowSound` on, `smallcanon`, budget 20000) with the
   signature-free definitions in a scratch module, `:type` each. Reproduce
   with the recipe in `tracker/loopmodel/E2-EXAMPLES.md` §G4.

   KEEP THIS FILE SEPARATE from `Helpers.e`: an annotated copy of a body in the
   same module as the unannotated one perturbs what the unannotated one infers.
-}

import Prelude
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Syntax.Relation

-- ==================================================================== antiJoin
--
-- The interesting member of the inferred set is `r1 <- (r1)`, a TAUTOLOGY: a
-- row is the disjoint union of itself and nothing. It is discharged at any call
-- site with no constraint in scope whatsoever, so it carries no information.
-- It appears because `difference`'s two operands are unified through the row
-- the semi-join returns, and the solver records the resulting identity as a
-- partition rather than dropping it.

antiJoinFull : ( b <- (c1, r1)
               , r <- (r1, c)
               , r1 <- (r1)
               , RelationalComb a )
            => Row r1 -> a r -> a b -> a b
antiJoinFull ks probe r = difference r (join r (project ks probe))

-- The tautology deleted. Three constraints, and they entail all four.
antiJoinDeduped : ( b <- (c1, r1)
                  , r <- (r1, c)
                  , RelationalComb a )
               => Row r1 -> a r -> a b -> a b
antiJoinDeduped = antiJoinFull

-- What `Helpers.e` carries. This one IS the deduped set renamed -- map
-- `k |-> r1, p |-> r, r |-> b, o |-> c1, q |-> c` and the two constraints
-- become `b <- (r1, c1)` and `r <- (r1, c)`, which are `antiJoinDeduped`'s two
-- with the right-hand sides permuted, and a partition's right-hand side is a
-- SET (that is what `rot3A/B/C` at the bottom of this file establishes). So
-- this pair proves a RENAMING; the `dedupeBy` and `groupSum` pairs below are
-- the substantive ones. It earns its place by showing what the deduped set
-- looks like once the variables are given the names a person would use.
antiJoinAsWritten : (RelationalComb rel, r <- (k, o), p <- (k, q))
                 => Row k -> rel p -> rel r -> rel r
antiJoinAsWritten = antiJoinFull

-- And the other direction, so the two sets are EQUIVALENT rather than one
-- being merely stronger: the inferred four discharged from the written two.
antiJoinFullViaWritten : ( b <- (c1, r1)
                         , r <- (r1, c)
                         , r1 <- (r1)
                         , RelationalComb a )
                      => Row r1 -> a r -> a b -> a b
antiJoinFullViaWritten = antiJoinAsWritten

-- ==================================================================== dedupeBy
--
-- Here the redundant member is `r <- (c, h)`. The variable `r` occurs NOWHERE
-- else in the set, so the constraint asserts only that `c` and `h` are
-- disjoint -- and `kv <- (k, h, c)`, which is kept, already says that. This is
-- the same class of noise as `overwriteWithFull`'s `r2 <- (e, a)` in
-- `core/examples/incomplete/Signatures.e`.

dedupeByFull : ( r <- (c, h)
               , kv <- (k, h, c)
               , Relational rel )
            => Row k -> Row h -> rel kv -> Mem kv
dedupeByFull ks ord r = groupBy ks (topK ord 1) r

dedupeByDeduped : ( kv <- (k, h, c)
                  , Relational rel )
               => Row k -> Row h -> rel kv -> Mem kv
dedupeByDeduped = dedupeByFull

-- What `Helpers.e` carries: a three-part partition written as two two-part
-- ones, with the intermediate row `v` named. `v` is the row `groupBy` hands to
-- the group function, so naming it is what makes the doc comment sayable --
-- "the ordering column must be OUTSIDE the key" is exactly `v <- (ord, o)`.
dedupeByAsWritten : (Relational rel, kv <- (k, v), v <- (ord, o))
                 => Row k -> Row ord -> rel kv -> Mem kv
dedupeByAsWritten = dedupeByFull

dedupeByFullViaWritten : ( r <- (c, h)
                         , kv <- (k, h, c)
                         , Relational rel )
                      => Row k -> Row h -> rel kv -> Mem kv
dedupeByFullViaWritten = dedupeByAsWritten

-- ==================================================================== groupSum
--
-- `r1 <- (r, t)` is the redundant one, for the same reason: `r1` occurs
-- nowhere else, so it only asserts `r` and `t` disjoint, which
-- `kv <- (k, t, r)` says. What is left is the honest content of a grouped
-- aggregate: the input splits into key, measure and remainder; the output is
-- key plus measure.

groupSumFull : ( kv <- (k, t, r)
               , kv2 <- (k, r)
               , r1 <- (r, t)
               , Relational rel
               , PrimitiveNum n )
            => Row k -> Field r n -> rel kv -> Mem kv2
groupSumFull ks amt r = groupBy ks (sumBy amt) r

groupSumDeduped : ( kv <- (k, t, r)
                  , kv2 <- (k, r)
                  , Relational rel
                  , PrimitiveNum n )
               => Row k -> Field r n -> rel kv -> Mem kv2
groupSumDeduped = groupSumFull

groupSumAsWritten : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m),
                     PrimitiveNum n)
                 => Row k -> Field m n -> rel kv -> Mem out
groupSumAsWritten = groupSumFull

groupSumFullViaWritten : ( kv <- (k, t, r)
                         , kv2 <- (k, r)
                         , r1 <- (r, t)
                         , Relational rel
                         , PrimitiveNum n )
                      => Row k -> Field r n -> rel kv -> Mem kv2
groupSumFullViaWritten = groupSumAsWritten

-- ============================================================== runningTotal
--
-- The fourth pair, added after review, and the one that makes the case for
-- Rule 1 of `Helpers.e` better than anything else in the directory.
-- `Helpers.runningTotal` carries TWO partition constraints. Remove its
-- signature and the compiler infers TWENTY-ONE, over twenty-seven existentially
-- quantified row variables -- because the body nests two `withFieldCopy`s, a
-- deliberate cartesian product, a filter, a `groupBy` and two renames, and
-- nothing tells the solver which of those rows are the same row.
--
-- Below is that set VERBATIM (REPL `:type` on the unannotated body, 2026-09-07,
-- adopted defaults), the signature `Helpers.e` actually carries defined as
-- `= runningTotalFull`, and the reverse definition.
--
-- BOTH DIRECTIONS CHECK, so the two sets are EQUIVALENT and NINETEEN OF THE
-- TWENTY-ONE inferred constraints carry nothing the other two do not. That is
-- the largest noise ratio measured anywhere in this repository -- the previous
-- record is `core/examples/incomplete/Signatures.e`'s fifteen against nine --
-- and it is the concrete cost of leaving a helper unsignatured: not a wrong
-- type, but a published interface with twenty-seven existential row variables
-- in it that every call site has to solve again.
--
-- One thing the inferred set does NOT say, which is worth noticing beside the
-- `unify1` finding in `Customer360.e`: `Field a a1`, the ordering column,
-- occurs in no constraint at all. That it is nevertheless equivalent to the
-- written form is a fact about `Mem r` appearing in the type, not about the
-- constraint list.

runningTotalFull : ( o <- (e, i, t)
                   , j <- (e2, f2)
                   , c2 <- (rs, so)
                   , c11 <- (d1, e1, f1)
                   , o <- (i, t, e)
                   , c11 <- (rs, ro)
                   , l <- (n, m)
                   , r <- (e, e1, f1, c1)
                   , d <- (p, n, m)
                   , f <- (k, i, g, ro, d2)
                   , PrimitiveNum a2
                   , c2 <- (d2, e2, f2)
                   , r <- (p, n)
                   , j <- (e1, f1)
                   , r <- (e1, f1, c1, e)
                   , t1 <- (rs, so, ro)
                   , f <- (g, d1, k, i, so)
                   , f <- (d1, g, so, e1, f1)
                   , j <- (k, i)
                   , l <- (c, e1, f1)
                   , h <- (i, g, ro, d2)
                   , r1 <- (e, e1, f1) )
                => Field a a1 -> Field b a2 -> Field c a2 -> Mem r -> Mem d
runningTotalFull ordF amtF totF r =
  withFieldCopy ordF (o' ->
  withFieldCopy amtF (a' ->
    let prior = rename amtF a' (rename ordF o' (r # {ordF, amtF}))
        pairs = filter_Pred (col_Op o' <=_Pred col_Op ordF) (join prior (r # {ordF}))
        sums  = rename a' totF (groupBy {ordF} (sumBy a') pairs)
    in join r sums))

-- Two constraints, discharging twenty-one. `r <- (ord, amt, rest)` says the
-- input has the two named columns; `out <- (r, tot)` says the output is the
-- input plus one more. That is the whole content of a running total, and it is
-- what a person would write.
runningTotalAsWritten : (r <- (ord, amt, rest), out <- (r, tot), PrimitiveNum n)
                     => Field ord k -> Field amt n -> Field tot n -> Mem r -> Mem out
runningTotalAsWritten = runningTotalFull

-- And the other direction: the twenty-one assumed, the two discharged.
runningTotalFullViaWritten : ( o <- (e, i, t)
                             , j <- (e2, f2)
                             , c2 <- (rs, so)
                             , c11 <- (d1, e1, f1)
                             , o <- (i, t, e)
                             , c11 <- (rs, ro)
                             , l <- (n, m)
                             , r <- (e, e1, f1, c1)
                             , d <- (p, n, m)
                             , f <- (k, i, g, ro, d2)
                             , PrimitiveNum a2
                             , c2 <- (d2, e2, f2)
                             , r <- (p, n)
                             , j <- (e1, f1)
                             , r <- (e1, f1, c1, e)
                             , t1 <- (rs, so, ro)
                             , f <- (g, d1, k, i, so)
                             , f <- (d1, g, so, e1, f1)
                             , j <- (k, i)
                             , l <- (c, e1, f1)
                             , h <- (i, g, ro, d2)
                             , r1 <- (e, e1, f1) )
                          => Field a a1 -> Field b a2 -> Field c a2 -> Mem r -> Mem d
runningTotalFullViaWritten = runningTotalAsWritten

-- =================================================== two facts used above
--
-- Repeated from `core/examples/incomplete/Signatures.e` so this file stands on
-- its own, and because the row solver reaches them by different routes here.

-- `r <- (r)` is a tautology: it is discharged with nothing in scope.
tautIsFree : Relation r -> Relation r
tautIsFree x = tautHere x
  where tautHere : r <- (r) => Relation r -> Relation r
        tautHere y = y

-- The right-hand side of a partition is a SET, so rotations entail one another
-- and all but one of any permuted group is noise. `groupSumFull` above has
-- `kv <- (k, t, r)` where the compiler could equally have printed
-- `kv <- (r, k, t)`.
rot3A : t <- (a, b, c) => Relation t -> Relation t
rot3A x = x
rot3B : t <- (c, a, b) => Relation t -> Relation t
rot3B x = rot3A x
rot3C : t <- (b, c, a) => Relation t -> Relation t
rot3C x = rot3B x
