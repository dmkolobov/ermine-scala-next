module Time.Signatures where

{- THE RESIDUALS `Time/Helpers.e` WOULD HAVE PUBLISHED, and machine-checked
   proof that the shorter ones say the same thing.

   Same method as `core/examples/incomplete/Signatures.e`. For each helper:

     xFull      -- the body carrying VERBATIM the constraint set the compiler
                   infers for it with the signature removed;
     xDeduped   -- the same set with the redundant members deleted, DEFINED AS
                   `= xFull`. That definition is the proof: checking it means
                   assuming the deduped constraints and discharging the full
                   ones, so if this module compiles then the deduped set
                   ENTAILS the full one. The full set trivially entails the
                   deduped one, being a superset. They are therefore equivalent
                   and the deleted constraints were noise.
     xSimple    -- the signature a person actually writes, a SPECIALISATION
                   rather than an equivalent, so it gets its own body written
                   out and its checking proves the body has that type. These are
                   the signatures `Helpers.e` ships.

   The inferred sets below were captured on 2026-09-06 at the adopted row-solver
   defaults (`-Dermine.rowSound` ON, `dequeuePolicy=smallcanon`,
   `solveBudget=20000`), from a module holding the same bodies with no
   signatures, by `:type` in the REPL under `-Dermine.useInterface=false`.

   ONE OF THEM IS NOT A FUNCTION OF THE PROGRAM. `nearestBy` printed a
   THIRTEEN-constraint residual on the run these were taken from and a
   TWELVE-constraint one, with different variable names and a different
   member set, on an earlier run of the identical body -- the same
   run-to-run instability `core/examples/incomplete/RunCalibration.e` documents
   for `lookbackJoin`. Only the thirteen-constraint form is transcribed here.

   AND ONE OF THEM CANNOT BE WRITTEN DOWN AT ALL: see the note on `bucketBy` at
   the foot of this file.

   ---------------------------------------------------------------------------
   STAGE S3 (2026-09-07) CHANGED WHAT THE COMPILER INFERS FOR THESE BODIES

   Every `xFull` set below was captured BEFORE stage S3's change to
   `Subst.mkSimplified` (`tracker/loopmodel/S3-SIMPLIFY.md`), which deletes two
   things from a PUBLISHED residual: the tautology `a <- (a)`, and permuted
   duplicate partitions (`NormalPart` had an `equals` that ignored the order of
   the parts and a `hashCode` that did not, so `List.distinct` never compared
   them). Re-measured against the fixed compiler, one body per scratch module:

       orZero        1 partition  -> 0    -- `v <- (v)` gone
       yearFrac365   1            -> 0    -- `out <- (out)` gone
       band3         1            -> 0    -- `v <- (v)` gone
       band4         1            -> 0    -- `v <- (v)` gone
       pctChange     5            -> 4    -- `prior <- (prior)` gone
       safeDiv       5            -> 3    -- BOTH permuted copies gone: what the
                                             compiler infers IS `safeDivDeduped`
       shiftBy       7            -> 6    -- `p <- (p)` gone
       nearestBy    10            -> 7    -- two tautologies and a permuted copy
       movingAgg     2            -> 2    -- unchanged; nothing here to delete

   (The exact pre-fix count depends on what else is in scope -- `nearestBy` is
   the run-to-run-unstable one noted above, and `safeDiv`'s five reproduce only
   with the stdlib read from interfaces. The DELETIONS do not depend on it.)

   NOTHING BELOW STOPS CHECKING, and nothing below was changed. A signature that
   carries a true-but-redundant constraint is still a legal signature, and a
   DECLARED signature is published verbatim -- it does not pass through
   `mkSimplified` -- so every `xFull`, every `xDeduped` and every `= xFull`
   proof is exactly as it was. What has changed is that the `xFull` sets are now
   the compiler's OLD answers: read them as "the residual before S3", and read
   this file as the record of what S3 removed -- which is, for the tautologies,
   precisely what `taut`/`tautIsFree` proved was safe to remove.

   KEEP THIS FILE SEPARATE from `Helpers.e`: an annotated copy of a body in the
   same module as the unannotated one perturbs what the unannotated one infers.
-}

import Prelude
import Layout
import Relation.Op as Op
import Relation.Op.Type using type Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.Aggregate.Type using type Aggregate
import Relation.Row as Rw
import Relation.Sort as Sort
import Relation.Windowed as W
import Syntax.Relation
import Date

-- =========================================== the two facts used throughout

-- `r <- (r)` is a tautology: every row is the disjoint union of itself with
-- nothing. `tautIsFree` discharges it with NO constraint whatsoever in scope,
-- which is the proof that every occurrence of it in a residual is noise.
taut : r <- (r) => Relation r -> Relation r
taut x = x

tautIsFree : Relation r -> Relation r
tautIsFree x = taut x

-- The right-hand side of a partition constraint is a SET, so permuted copies
-- entail one another and all but one of any group are noise.
perm2A : t <- (a, b) => Relation t -> Relation t
perm2A x = x
perm2B : t <- (b, a) => Relation t -> Relation t
perm2B x = perm2A x

perm4A : t <- (a, b, c, d) => Relation t -> Relation t
perm4A x = x
perm4B : t <- (b, d, a, c) => Relation t -> Relation t
perm4B x = perm4A x

-- A constraint whose LEFT-hand side occurs nowhere else asserts only that its
-- parts are pairwise disjoint, so it is discharged by any other constraint that
-- already separates them. This is the third deletion rule used below.
freshLhsIsDisjointness : t <- (a, b, c) => Relation t -> Relation t
freshLhsIsDisjointness x = x

freshLhsFromWider : (t <- (a, b, c), exists u. u <- (a, b))
                 => Relation t -> Relation t
freshLhsFromWider x = freshLhsIsDisjointness x

-- ================================================================== orZero

-- Four characters of ordinary library code, and the residual carries the
-- tautology. SINCE S3 IT DOES NOT: the compiler now infers `orZeroDeduped`'s
-- signature for this body (1 partition -> 0).
orZeroFull : (v <- (v), AsOp opc) => opc v (Nullable Double) -> Op v Double
orZeroFull x = coalesce_Op x (prim_Op 0.0)

-- The tautology deleted. Nothing is left but the class constraint.
orZeroDeduped : AsOp opc => opc v (Nullable Double) -> Op v Double
orZeroDeduped = orZeroFull

-- ============================================================== yearFrac365

-- The same tautology, from a date difference divided by a literal. Also gone
-- since S3: the inferred residual is `yearFrac365Deduped`'s (1 -> 0).
yearFrac365Full : (out <- (out), PrimitiveTemporal a)
               => Field r a -> Field r1 a -> Op out Double
yearFrac365Full s e =
  fromNumericOp_Op (dateDiff_Op days (col_Op s) (col_Op e)) /_Op prim_Op 365.0

yearFrac365Deduped : PrimitiveTemporal a => Field r a -> Field r1 a -> Op out Double
yearFrac365Deduped = yearFrac365Full

-- What `Helpers.e` ships, specialised to `Date`.
yearFrac365Simple : Field r Date -> Field r1 Date -> Op out Double
yearFrac365Simple s e =
  fromNumericOp_Op (dateDiff_Op days (col_Op s) (col_Op e)) /_Op prim_Op 365.0

-- ================================================================ pctChange

-- SIX constraints for "(a - b) / b". One is the tautology; one more is implied
-- by two others. SINCE S3 the tautology is gone from the inferred residual
-- (5 partitions -> 4); the implied one stays, because `mkSimplified` still has
-- no entailment test between surviving partitions (ROSE-COMPARISON rank 3).
pctChangeFull : ( PrimitiveNum n
                , prior <- (f, e)
                , prior <- (prior)
                , out <- (prior, d)
                , cur <- (e, d)
                , out <- (f, e, d) )
             => Field cur n -> Field prior n -> Op out n
pctChangeFull curF priorF = (col_Op curF -_Op col_Op priorF) /_Op col_Op priorF

-- `prior <- (prior)` is the tautology. `out <- (prior, d)` is entailed by
-- `prior <- (f, e)` together with `out <- (f, e, d)`: substituting the first
-- into the second gives exactly it.
pctChangeDeduped : ( PrimitiveNum n
                   , prior <- (f, e)
                   , cur <- (e, d)
                   , out <- (f, e, d) )
                => Field cur n -> Field prior n -> Op out n
pctChangeDeduped = pctChangeFull

-- What `Helpers.e` ships: one constraint, and what a person would write.
pctChangeSimple : (out <- (cur, prior), PrimitiveNum n)
               => Field cur n -> Field prior n -> Op out n
pctChangeSimple curF priorF = (col_Op curF -_Op col_Op priorF) /_Op col_Op priorF

-- ================================================================== safeDiv

-- FIVE constraints for a guarded division, and they come in PERMUTED PAIRS:
-- `out <- (so, f, e)` beside `out <- (so, e, f)`, and `den <- (e, f)` beside
-- `den <- (f, e)`. This is `if`'s `RUnion3` lattice after the solver has
-- ground it down -- and note that it did grind it down: at the adopted
-- defaults a conditional over one column costs five constraints, not the
-- unbounded chain `Ai/Common.e` measured before them.
--
-- THIS IS THE SHARPEST CASE S3 CLOSES. Both permuted copies are gone from the
-- inferred residual since 2026-09-07: the compiler now infers THREE constraints
-- for this body, and they are `safeDivDeduped`'s three, member for member. The
-- hand-deduplication below is now the compiler's own answer, and the pair
-- `safeDivDeduped = safeDivFull` is kept as the proof that it was the right
-- one.
safeDivFull : ( out <- (so, f, e)
              , den <- (e, f)
              , num <- (so, e)
              , out <- (so, e, f)
              , den <- (f, e) )
           => Field num Double -> Field den Double -> Op out Double
safeDivFull n d = if_Op (col_Op d !=_Pred prim_Op 0.0)
                        (col_Op n /_Op col_Op d)
                        (prim_Op 0.0)

-- Both permuted copies deleted.
safeDivDeduped : ( out <- (so, f, e)
                 , den <- (e, f)
                 , num <- (so, e) )
              => Field num Double -> Field den Double -> Op out Double
safeDivDeduped = safeDivFull

-- What `Helpers.e` ships.
safeDivSimple : out <- (num, den)
             => Field num Double -> Field den Double -> Op out Double
safeDivSimple n d = if_Op (col_Op d !=_Pred prim_Op 0.0)
                          (col_Op n /_Op col_Op d)
                          (prim_Op 0.0)

-- ============================================================ band3 / band4

-- TWO nested conditionals, and THREE, and the residual of each is the single
-- tautology. This is the measurement `Ai/Common.e` asked for: at the adopted
-- defaults an `Op`-returning conditional helper does NOT accumulate the
-- inclusion-exclusion lattice, however deeply it is nested, PROVIDED every
-- branch reads the same one column. SINCE S3 the residual of each is EMPTY of
-- row constraints -- `v <- (v)` is deleted, so the compiler infers
-- `band3Deduped`/`band4Deduped` themselves, and the measurement becomes "no row
-- constraint at all, however deeply nested".
band3Full : (v <- (v), Primitive a, Primitive b)
         => Field v a -> a -> b -> a -> b -> b -> Op v b
band3Full f lo loLbl hi hiLbl rest =
  if_Op (col_Op f <_Pred prim_Op lo)
        (prim_Op loLbl)
        (if_Op (col_Op f <_Pred prim_Op hi) (prim_Op hiLbl) (prim_Op rest))

band3Deduped : (Primitive a, Primitive b)
            => Field v a -> a -> b -> a -> b -> b -> Op v b
band3Deduped = band3Full

band4Full : (v <- (v), Primitive a, Primitive b)
         => Field v a -> a -> b -> a -> b -> a -> b -> b -> Op v b
band4Full f b1 l1 b2 l2 b3 l3 rest =
  if_Op (col_Op f <_Pred prim_Op b1) (prim_Op l1)
    (if_Op (col_Op f <_Pred prim_Op b2) (prim_Op l2)
      (if_Op (col_Op f <_Pred prim_Op b3) (prim_Op l3) (prim_Op rest)))

band4Deduped : (Primitive a, Primitive b)
            => Field v a -> a -> b -> a -> b -> a -> b -> b -> Op v b
band4Deduped = band4Full

-- ================================================================ movingAgg

-- TWO constraints, one of which has a left-hand side occurring nowhere else.
movingAggFull : (t <- (dateR, part, valR), t1 <- (part, dateR))
             => Aggregate valR n -> Row part -> Field dateR a -> Int -> Op t n
movingAggFull agg partRow dateF n =
  windowed_W (windowedAggregate_W agg)
             (window_W partRow (single_Sort (dateF, Ascending_Sort))
                       (F_W (Bounded_W n) (Bounded_W 0)))

-- `t1` occurs nowhere else, so `t1 <- (part, dateR)` asserts only that `part`
-- and `dateR` are disjoint -- which `t <- (dateR, part, valR)` already says.
movingAggDeduped : t <- (dateR, part, valR)
                => Aggregate valR n -> Row part -> Field dateR a -> Int -> Op t n
movingAggDeduped = movingAggFull

-- ================================================================ nearestBy

-- THIRTEEN constraints for the per-key as-of, verbatim. Two tautologies, one
-- permuted pair over four parts, one permuted pair over two, and three whose
-- left-hand side occurs nowhere else. SINCE S3 the first four of those go by
-- themselves: re-measured, this body infers 10 partitions before the fix and
-- SEVEN after. The three whose left-hand side occurs nowhere else remain --
-- deleting them needs the entailment test `mkSimplified` still does not have.
--
-- READ THE VARIABLE NAMES CAREFULLY: in the INFERRED signature below (and so in
-- `nearestByDeduped`, which must match it member for member) the compiler minted
-- `fd` for the SPARSE field and `sd` for the FINE one -- the OPPOSITE of
-- `nearestBySimple` below and of `Helpers.nearestBy`, where `sd` is the sparse
-- one. The transcription is faithful; the names are the compiler's. Compare the
-- two sets by SHAPE, not by name.
nearestByFull : ( sd <- (sd)
                , out <- (sd, fd, k, g)
                , out <- (f, e, d)
                , Primitive a
                , out <- (fd, g, k, sd)
                , r3 <- (k, sd)
                , sparse <- (f, e)
                , fine <- (e, d)
                , t <- (sd, fd)
                , fd <- (fd)
                , h <- (g, fd)
                , RelationalComb rel
                , t <- (fd, sd) )
             => Row k -> Field fd a -> rel sparse -> Field sd a -> rel fine
             -> Relation out
nearestByFull keyRow fsparse rsparse ffine rfine =
  materialize ' groupBy (snoc_Rw keyRow ffine) (maxRowBy fsparse)
                        ([| fsparse <= ffine |] (join rsparse rfine))

-- SEVEN deleted:
--   `sd <- (sd)` and `fd <- (fd)`             -- tautologies
--   `out <- (fd, g, k, sd)`                   -- permutation of the first `out`
--   `t <- (fd, sd)`                           -- permutation of `t <- (sd, fd)`
--   `t <- (sd, fd)`, `r3 <- (k, sd)`, `h <- (g, fd)`
--                                             -- left-hand sides occurring
--                                                nowhere else, so each asserts
--                                                only a disjointness that
--                                                `out <- (sd, fd, k, g)` says
nearestByDeduped : ( out <- (sd, fd, k, g)
                   , out <- (f, e, d)
                   , sparse <- (f, e)
                   , fine <- (e, d)
                   , Primitive a
                   , RelationalComb rel )
                => Row k -> Field fd a -> rel sparse -> Field sd a -> rel fine
                -> Relation out
nearestByDeduped = nearestByFull

-- What `Helpers.e` ships: four constraints in the caller's own vocabulary --
-- the sparse relation carries the key, its date and its values; the fine one
-- carries the key, its date and its values; the result carries all five.
nearestBySimple : forall k sd fd sparse fine out a.
                  (exists sv fv. sparse <- (k, sd, sv), fine <- (k, fd, fv)
                  , out <- (k, sd, sv, fd, fv), Primitive a)
               => Row k -> Field sd a -> Relation sparse
               -> Field fd a -> Relation fine -> Relation out
nearestBySimple keyRow fsparse rsparse ffine rfine =
  materialize ' groupBy (snoc_Rw keyRow ffine) (maxRowBy fsparse)
                        ([| fsparse <= ffine |] (join rsparse rfine))

-- ================================================================== shiftBy

-- NINE constraints for "add n to the index column, rename the measure". One is
-- the tautology on the index column, minted by `withFieldCopy`. SINCE S3 that
-- one is gone from the inferred residual (re-measured, 7 partitions -> 6); the
-- `r1 <- (ro, so, rs)` that `shiftByDeduped` also deletes remains, for the same
-- reason as `nearestBy`'s three.
shiftByFull : ( src <- (ro, rs)
              , r1 <- (ro, so, rs)
              , g <- (i, v)
              , RelationalComb rel
              , g <- (p, h)
              , PrimitiveNum n
              , p <- (p)
              , res <- (i, pv)
              , src <- (p, o) )
           => Field p n -> Field v a -> Field pv a -> n -> rel src -> rel res
shiftByFull pF vF pvF n r =
  withFieldCopy pF (p' ->
    r |> combine_Op (col_Op pF +_Op prim_Op n) p'
      |> rename' p' pF
      |> rename vF pvF)

-- `p <- (p)` deleted, and `r1 <- (ro, so, rs)` with it: `r1` occurs nowhere
-- else, so it asserts only that `ro`, `so` and `rs` are pairwise disjoint, and
-- `src <- (ro, rs)` plus the `combine` that introduced `so` already separate
-- them.
shiftByDeduped : ( src <- (ro, rs)
                 , g <- (i, v)
                 , RelationalComb rel
                 , g <- (p, h)
                 , PrimitiveNum n
                 , res <- (i, pv)
                 , src <- (p, o) )
              => Field p n -> Field v a -> Field pv a -> n -> rel src -> rel res
shiftByDeduped = shiftByFull

-- What `Helpers.e` ships.
shiftBySimple : forall p v pv r out n a rel.
                (exists o. r <- (p, v, o), out <- (p, pv, o)
                , PrimitiveNum n, RelationalComb rel)
             => Field p n -> Field v a -> Field pv a -> n -> rel r -> rel out
shiftBySimple pF vF pvF n r =
  withFieldCopy pF (p' ->
    r |> combine_Op (col_Op pF +_Op prim_Op n) p'
      |> rename' p' pF
      |> rename vF pvF)

{- ============================================================== bucketBy

   AND THE ONE THAT CANNOT BE TRANSCRIBED.

   `Helpers.bucketBy` is

       bucketBy startF endF dateF cal facts =
         [| startF <= dateF, dateF <= endF |] (join facts cal)

   -- eleven tokens. With its signature removed the compiler infers a type with
   THIRTY-FOUR constraints over thirty-four existentials, and among the
   existentials are FOUR of these:

       (AsOp: (rho -> a -> *) -> f)

   That is the CLASS `AsOp` itself, bound as an existential variable of a kind
   the surface syntax has no binder for; the printed type also opens with
   `forall {a}`, an implicit KIND variable. The type is therefore not re-enterable:
   there is no `xFull` for `bucketBy` because the compiler's own output for it is
   not a term of the language it accepts. (Attempting it gives a parse error at
   the `:` inside the existential binder group.)

   The cause is that the `[| ... |]` sugar is applied to field VARIABLES rather
   than to literal field names, so `Relation.Predicate.(<=)`'s `AsOp opl` /
   `AsOp opr` constraints are generalised over rather than solved. Using literal
   field names -- as every other example in the tree does -- keeps them ground.

   `Helpers.bucketBy` therefore carries the hand-written specialisation below,
   which is what a person would write and does check; the fact that the inferred
   type exists but cannot be written is recorded in
   `tracker/loopmodel/E3-EXAMPLES.md`.
-}

bucketBySimple : forall s e d cal facts out rel.
                 (exists cv fv. cal <- (s, e, cv), facts <- (d, fv)
                 , out <- (s, e, cv, d, fv), RelationalComb rel)
              => Field s Date -> Field e Date -> Field d Date
              -> rel cal -> rel facts -> rel out
bucketBySimple startF endF dateF cal facts =
  [| startF <= dateF, dateF <= endF |] (join facts cal)
