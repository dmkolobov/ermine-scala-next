module Wide.Signatures where

{- THE SMALLER SIGNATURES FOR `Wide.Helpers`, AND MACHINE-CHECKED PROOF THAT THEY
   SAY THE SAME THING.

   The idiom is `core/examples/incomplete/Signatures.e`'s, and it is worth
   restating because the whole file is one trick.  For a helper we write

     xFull      -- the body, carrying VERBATIM the constraint set the compiler
                   publishes for it, and
     xDeduped   -- the same set with the redundant members deleted, DEFINED AS
                   `= xFull`.

   That definition IS the proof.  Checking `xDeduped = xFull` means assuming the
   deduped constraints and discharging the full ones, so if the module compiles
   then the deduped set ENTAILS the full one.  The full set trivially entails the
   deduped one, being a superset, so the two are equivalent and the extra
   constraints are noise the solver could not see was noise.  Where the direction
   is not obvious we write BOTH definitions and get equivalence outright.

   Where a signature is a SPECIALISATION rather than an equivalent -- the
   signature a person would actually write -- it is named `xSimple` and gets its
   body written out instead, so that its checking still proves the body has that
   type.

   Four things are proved here, in order of how much they are worth knowing:

     1. `RUnion2 t r c` is exactly the three-constraint lattice
        `r <- (ro, rs), c <- (so, rs), t <- (ro, so, rs)` -- proved in BOTH
        directions.  Every window and derived-column helper in `Helpers.e` is
        written with the sugar and published with the expansion, and section 2
        of `tracker/loopmodel/E1-EXAMPLES.md` asserts this equality in prose.
        Here it is checked.
     2. `rankWithin`'s five published constraints are equivalent to the four it
        was written with -- again both directions.
     3. `melt3`'s TWENTY-TWO inferred constraints reduce by deleting order-
        permuted duplicates, and to TWO by saying what the function means.  The
        first reduction is the interesting one: it proves that the published list
        is not canonical, which is why the same body publishes 20 constraints in
        one module and 22 in another (E1 review, N-11).
        TWO CORRECTIONS, both from stage S3 (2026-09-07):
          (a) there are THREE permuted pairs in the twenty-two, not two, so the
              reduction is to NINETEEN.  The third, `r21 <- (ro, rs)` beside
              `r21 <- (rs, ro)`, is still present in `melt3Deduped` below --
              which is why that signature says twenty and not nineteen; and
          (b) the compiler now performs the reduction ITSELF.  `mkSimplified`
              could never delete a permuted duplicate because `NormalPart`
              overrode `equals` and not `hashCode`; since S3 it can, and this
              body re-measured infers TWENTY partitions before the fix and
              NINETEEN after (`tracker/loopmodel/S3-SIMPLIFY.md` §6).
     4. `withDerived2`'s eight published constraints reduce to four.

   NOTHING BELOW WAS CHANGED BY S3 AND NOTHING BELOW STOPS CHECKING.  A DECLARED
   signature is published verbatim -- it does not pass through `mkSimplified` --
   so `melt3Full`'s twenty-two, `melt3Deduped`'s twenty and every `= xFull` proof
   are exactly as they were.  What changed is that `melt3Full`'s set is now the
   compiler's OLD answer; read it as "the residual before S3".

   KEEP THIS FILE SEPARATE from `Helpers.e`: an annotated copy of a body in the
   same module as the original perturbs what the original infers.
-}

import Prelude
import Relation.Op as Op
import Relation.Sort as Srt
import Relation.Windowed as W
import Syntax.Relation
import Wide.Helpers

-- ==========================================================================
-- 1. `RUnion2 t r c` and its expansion are the SAME constraint
-- ==========================================================================
--
-- `RUnion2` is a class alias, not a primitive: the solver publishes it as three
-- partition constraints over two fresh row variables.  Everything in
-- `Helpers.e` that adds a column is written with the sugar, and every `.ei` in
-- the group shows the expansion, so a reader comparing source with interface
-- needs to know these are the same thing.  Both directions are checked.

-- The sugared form, as `Ai.Common.withColumn` and every window helper write it.
withColumnSugar : forall v t r c op a rel.
                  (exists o. RUnion2 t r c, r <- (v, o), AsOp op, RelationalComb rel)
               => op v a -> Field c a -> rel r -> rel t
withColumnSugar = combine_Op

-- The published form, as it comes back in `Helpers.ei`.  Defining it as the
-- sugared one proves EXPANDED |= SUGAR.
withColumnExpanded : forall v t r c op a rel.
                     (exists o ro so rs. r <- (ro, rs), c <- (so, rs),
                      t <- (ro, so, rs), r <- (v, o), AsOp op, RelationalComb rel)
                  => op v a -> Field c a -> rel r -> rel t
withColumnExpanded = withColumnSugar

-- And back the other way, which gives EQUIVALENCE outright.
withColumnSugarViaExpanded : forall v t r c op a rel.
                             (exists o. RUnion2 t r c, r <- (v, o),
                              AsOp op, RelationalComb rel)
                          => op v a -> Field c a -> rel r -> rel t
withColumnSugarViaExpanded = withColumnExpanded

-- ==========================================================================
-- 2. `rankWithin`: five published constraints, four written
-- ==========================================================================

-- Verbatim from `Helpers.ei`, and a CALL SITE for the helper at the same time.
rankWithinFull : forall k s c rel r t.
                 (exists o ro so rs. w <- (k, s), r <- (w, o), c <- (so, rs),
                  r <- (ro, rs), t <- (ro, so, rs), RelationalComb rel)
              => Row k -> Sort s -> Field c Int -> rel r -> rel t
rankWithinFull = rankWithin

-- What `Helpers.e` actually writes.  SUGAR |= FULL.
rankWithinSugar : forall k s w r t c rel.
                  (exists o. w <- (k, s), r <- (w, o), RUnion2 t r c,
                   RelationalComb rel)
               => Row k -> Sort s -> Field c Int -> rel r -> rel t
rankWithinSugar = rankWithinFull

-- FULL |= SUGAR, so the two are equivalent and the interface loses nothing.
rankWithinFullViaSugar : forall k s c rel r t.
                         (exists o ro so rs. w <- (k, s), r <- (w, o),
                          c <- (so, rs), r <- (ro, rs), t <- (ro, so, rs),
                          RelationalComb rel)
                      => Row k -> Sort s -> Field c Int -> rel r -> rel t
rankWithinFullViaSugar = rankWithinSugar

-- ==========================================================================
-- 3. `melt3`: twenty-two inferred, twenty after dedup, two after thought
-- ==========================================================================
--
-- This is the one worth reading.  The body below is `Helpers.melt3`'s, written
-- out; the constraint set is what the compiler infers for it when it carries no
-- signature, VERBATIM, in the order it prints.

melt3Full : ( t1 <- (rs, so, ro)
            , r5 <- (c1, r)
            , c <- (rs, so)
            , c <- (rs2, so2)
            , r1 <- (c1, r2, ro1, rs1)
            , RelationalComb rel
            , r22 <- (ro2, rs2)
            , t2 <- (rs1, so1, ro1)
            , t2 <- (e, r)
            , r21 <- (ro, rs)
            , r23 <- (rs1, ro1)
            , t1 <- (e, r2)
            , t <- (e, c1)
            , r1 <- (c1, r, ro, rs)
            , r4 <- (r, r2)
            , r23 <- (ro1, rs1)
            , d <- (e, a)
            , r3 <- (c1, r2)
            , c <- (rs1, so1)
            , r1 <- (r2, r, ro2, rs2)
            , r22 <- (rs2, ro2)
            , r21 <- (rs, ro)
            , t <- (rs2, so2, ro2) )
         => Field c String -> Field a b -> Field c1 b -> Field r b -> Field r2 b
         -> rel r1 -> rel d
melt3Full kf vf fa fb fc r =
  union (union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb,fc} r)))
               (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa,fc} r))))
        (rename fc vf (combine_Op (prim_Op (fieldName fc)) kf (except {fa,fb} r)))

-- The SAME set with two members deleted: `r22 <- (rs2, ro2)` and
-- `r23 <- (ro1, rs1)`, each of which is a permutation of a constraint already in
-- the list -- and the right-hand side of a partition constraint is a SET, so a
-- rotation entails the original and is pure noise.
--
-- TWO IS AN UNDERCOUNT (stage S3, 2026-09-07, `S3-SIMPLIFY.md` §6): there is a
-- THIRD permuted pair in `melt3Full`, `r21 <- (ro, rs)` beside `r21 <- (rs, ro)`,
-- and BOTH copies are still in the list below.  So the minimal set by this rule
-- is NINETEEN, not twenty, and `melt3Deduped` is a proof about a set that is
-- itself not yet duplicate-free.  It is left exactly as it was: it still checks,
-- and it still proves what it says.
--
-- Deleting them and checking `melt3Deduped = melt3Full` proves the twenty entail
-- the twenty-two, and the reverse inclusion is trivial, so the two sets are
-- EQUIVALENT.  That is the machine-checked half of E1 review finding N-11: the
-- reviewer's copy of this same body published twenty constraints and mine
-- published twenty-two, and this is exactly the difference.  Since S3 the
-- compiler does this deletion itself -- re-measured, the unannotated body infers
-- twenty partitions before the fix and nineteen after -- so the instability N-11
-- found is gone for the permuted-duplicate half of it.
melt3Deduped : ( t1 <- (rs, so, ro)
               , r5 <- (c1, r)
               , c <- (rs, so)
               , c <- (rs2, so2)
               , r1 <- (c1, r2, ro1, rs1)
               , RelationalComb rel
               , r22 <- (ro2, rs2)
               , t2 <- (rs1, so1, ro1)
               , t2 <- (e, r)
               , r21 <- (ro, rs)
               , r23 <- (rs1, ro1)
               , t1 <- (e, r2)
               , t <- (e, c1)
               , r1 <- (c1, r, ro, rs)
               , r4 <- (r, r2)
               , d <- (e, a)
               , r3 <- (c1, r2)
               , c <- (rs1, so1)
               , r1 <- (r2, r, ro2, rs2)
               , r21 <- (rs, ro)
               , t <- (rs2, so2, ro2) )
            => Field c String -> Field a b -> Field c1 b -> Field r b -> Field r2 b
            -> rel r1 -> rel d
melt3Deduped = melt3Full

-- And the other direction, so the file proves the two sets equivalent rather
-- than merely ordered: the twenty-two discharged from the twenty.
melt3FullViaDeduped : ( t1 <- (rs, so, ro)
                      , r5 <- (c1, r)
                      , c <- (rs, so)
                      , c <- (rs2, so2)
                      , r1 <- (c1, r2, ro1, rs1)
                      , RelationalComb rel
                      , r22 <- (ro2, rs2)
                      , t2 <- (rs1, so1, ro1)
                      , t2 <- (e, r)
                      , r21 <- (ro, rs)
                      , r23 <- (rs1, ro1)
                      , t1 <- (e, r2)
                      , t <- (e, c1)
                      , r1 <- (c1, r, ro, rs)
                      , r4 <- (r, r2)
                      , r23 <- (ro1, rs1)
                      , d <- (e, a)
                      , r3 <- (c1, r2)
                      , c <- (rs1, so1)
                      , r1 <- (r2, r, ro2, rs2)
                      , r22 <- (rs2, ro2)
                      , r21 <- (rs, ro)
                      , t <- (rs2, so2, ro2) )
                   => Field c String -> Field a b -> Field c1 b -> Field r b
                   -> Field r2 b -> rel r1 -> rel d
melt3FullViaDeduped = melt3Deduped

-- What a person writes, and what `Helpers.e` ships: "the input is the identity
-- columns plus the three measures, the output is the identity columns plus a key
-- and a value".  TWO constraints, one existential.  It is a SPECIALISATION, not
-- an equivalent -- it fixes the shape of the answer rather than describing every
-- intermediate -- so its body is written out, which proves the body has this
-- type.
melt3Simple : forall key val fa fb fc i r out t rel.
              (r <- (i, fa, fb, fc), out <- (i, key, val), RelationalComb rel)
           => Field key String -> Field val t
           -> Field fa t -> Field fb t -> Field fc t
           -> rel r -> rel out
melt3Simple kf vf fa fb fc r =
  union (union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb,fc} r)))
               (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa,fc} r))))
        (rename fc vf (combine_Op (prim_Op (fieldName fc)) kf (except {fa,fb} r)))

-- ==========================================================================
-- 4. `withDerived2`: eight published, four written
-- ==========================================================================

-- Verbatim from `Helpers.ei`, and a call site for the helper.
withDerived2Full : forall op1 v1 a c1 op2 v2 b c2 rel r t.
                   ( exists o2 o1 ro so rs ro1 so1 rs1.
                     r <- (v1, o1), t1 <- (v2, o2), r <- (ro, rs),
                     c2 <- (so1, rs1), t <- (ro1, so1, rs1), c1 <- (so, rs),
                     t1 <- (ro, so, rs), t1 <- (ro1, rs1),
                     AsOp op1, AsOp op2, RelationalComb rel )
                => op1 v1 a -> Field c1 a -> op2 v2 b -> Field c2 b
                -> rel r -> rel t
withDerived2Full = withDerived2

-- The same thing said once: "the intermediate is the input plus the first
-- column; the output is the intermediate plus the second; each Op reads a part
-- of the row it is applied to".  Four constraints, and it ENTAILS the eight.
withDerived2Simple : forall op1 v1 a c1 op2 v2 b c2 rel r t.
                     ( exists o1 o2. r <- (v1, o1), t1 <- (r, c1),
                       t1 <- (v2, o2), t <- (t1, c2),
                       AsOp op1, AsOp op2, RelationalComb rel )
                  => op1 v1 a -> Field c1 a -> op2 v2 b -> Field c2 b
                  -> rel r -> rel t
withDerived2Simple = withDerived2Full
