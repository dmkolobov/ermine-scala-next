module Wide.Helpers where

{- ROW-POLYMORPHIC, EXISTENTIAL-GENERATING helpers for WIDE reporting tables.

   Every helper here names only the two or three columns it needs and carries the
   rest of the row -- twenty, thirty, forty other fields -- through as a row
   variable.  That is what the partition constraints in the signatures say:
   `r <- (v, o)` reads "the row r is exactly the disjoint union of v and o", so a
   caller may pass any relation containing the named columns plus anything else,
   and `o` is the anonymous remainder the helper never looks at.

   The helpers in `Ai/Common.e` are about TREES.  These are about WIDTH: window
   functions partitioned by a generic key, pivots that turn rows into columns, and
   derived columns stacked two and three deep.  They are what a reporting library
   needs when the fact table has thirty measures and the report has to rank,
   accumulate, share out and transpose them without naming the other twenty-eight.

   ------------------------------------------------------------------------
   THE RULE THIS FILE OBEYS, and the two places it costs something.

   `Ai/Common.e` records the measurement that a helper bundling a `RUnion3` and a
   `RUnion2` in one signature did not finish.  At the defaults adopted on
   2026-09-05 (`-Dermine.rowSound` on, `dequeuePolicy=smallcanon`,
   `solveBudget=20000`) that is no longer true: measured on the same module, the
   bundled form checks in 1.28 s against the inline form's 1.06 s -- **1.2x**, not
   a cliff.  Section 5 of `tracker/loopmodel/E1-EXAMPLES.md` has the controlled
   A/B/C.

   So the rule this file follows is a preference now, not a rescue:

     KEEP EACH HELPER TO ONE ROW-UNION where it costs nothing to do so -- not
     because two is slow, but because the signature a two-union helper publishes
     is twice the size a reader has to understand (`withDerived2` publishes eight
     partition constraints, `withDerived3` twelve, against `rankWithin`'s five).

   `withDerived2` and `withDerived3` below deliberately BREAK that rule -- they
   are the measured counter-example, and their published residuals are in the
   report.

   The second place is `share`, the only helper here whose Op is an ARITHMETIC
   COMBINATION of two Ops over different rows: `(/_Op)` carries `OpBin`'s
   inclusion-exclusion lattice (`a <- (e,d), b <- (f,e), c <- (f,e,d)`) on top of
   the window's own constraints.  That was expected to be the expensive shape and
   MEASURED AS THE CHEAP ONE -- one bigger solve beats the two smaller ones of the
   `windowTotal`-then-divide spelling.  Both are kept, side by side, in
   `Wide.RevenueShare`, and the numbers are in the report.
   ------------------------------------------------------------------------

   WHAT WORKS AT RUNTIME.  These helpers all TYPE-CHECK, which is what a
   reporting library is judged on, but two of them cannot be EVALUATED in this
   repository:

     * anything built on `Relation.Pivot` panics when the relation is forced
       (`Native.Record.scalaRecord#`, a Scala 2.13 collection regression), and
     * window functions compile to real SQL only through the MS SQL emitter.

   Both are recorded, with the exact diagnosis, in
   `tracker/loopmodel/E1-EXAMPLES.md` section 7.  Nothing in this directory works
   around them; the examples are written as the library intends them to be used.
-}

import Prelude
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.Pivot as Piv
import Relation.Sort as Srt
import Relation.Windowed as W
import Syntax.Relation

-- --------------------------------------------------------- sort spellings
--
-- `Relation.Row` and `Relation.Sort` both export `single` and `empty`, and
-- Prelude re-exports both modules, so `single f` in an example is ambiguous
-- between "the one-column row" and "the one-column sort".  These three name the
-- sort side unambiguously, and every example in this directory uses them.

-- | Ascending single-column sort.
asc : forall f a. Field f a -> Sort f
asc f = single_Srt (f, Ascending)

-- | Descending single-column sort.
desc : forall f a. Field f a -> Sort f
desc f = single_Srt (f, Descending)

-- | Sort by one thing, then another: `desc points ` thenBy ' asc surname`.
thenBy : forall r r1 r2. r <- (r1, r2) => Sort r1 -> Sort r2 -> Sort r
thenBy = append_Srt

-- ------------------------------------------------------------------ windows
--
-- The nine window helpers below share one shape.  `window_W ks so frame` builds a
-- `Window w` whose row `w` is the partition columns `k` together with the sort
-- columns `s` -- that is the `w <- (k, s)` in every signature below, and it is
-- the constraint that MINTS a row variable the caller never writes down.
-- `combine_Op` then adds the computed column, contributing `RUnion2 t r c`
-- ("the output row is the input row plus the new column") and
-- `r <- (w, o)` ("the input row contains the window's columns, plus a
-- remainder").  Three constraints, one row union: the cheap shape.

-- | Competition rank within each partition: ties share a rank and the next
-- rank skips.  `rankWithin {team} (desc points) seed roster`
-- adds `seed` to a roster of any width.
rankWithin : forall k s w r t c rel.
             (exists o. w <- (k, s), r <- (w, o), RUnion2 t r c, RelationalComb rel)
          => Row k -> Sort s -> Field c Int -> rel r -> rel t
rankWithin ks so f = combine_Op (windowed_W rank_W (window_W ks so unboundedFrame_W)) f

-- | Dense rank: ties share a rank and the next rank does NOT skip.  Same
-- constraint set as `rankWithin`; the two differ only in the window function.
denseWithin : forall k s w r t c rel.
              (exists o. w <- (k, s), r <- (w, o), RUnion2 t r c, RelationalComb rel)
           => Row k -> Sort s -> Field c Int -> rel r -> rel t
denseWithin ks so f = combine_Op (windowed_W dense_W (window_W ks so unboundedFrame_W)) f

-- | A distinct 1..n per partition, ties broken arbitrarily by the sort.  Use it
-- where a rank must be a key -- "the third-largest order on this customer".
rowNumberWithin : forall k s w r t c rel.
                  (exists o. w <- (k, s), r <- (w, o), RUnion2 t r c, RelationalComb rel)
               => Row k -> Sort s -> Field c Int -> rel r -> rel t
rowNumberWithin ks so f =
  combine_Op (windowed_W rowNumber_W (window_W ks so unboundedFrame_W)) f

-- | Bucket each partition into `n` equal-sized tiles in sort order: quartiles,
-- deciles, the "top fifth of the league".  `n` is an ordinary Int, lifted to a
-- constant Op, so it contributes no columns and no constraints of its own.
nTileWithin : forall k s w r t c rel.
              (exists o. w <- (k, s), r <- (w, o), RUnion2 t r c, RelationalComb rel)
           => Row k -> Sort s -> Int -> Field c Int -> rel r -> rel t
nTileWithin ks so n f =
  combine_Op (windowed_W (nTile_W (prim_Op n)) (window_W ks so unboundedFrame_W)) f

-- | Running total of `m` within each partition, in the given order: rows
-- between unbounded preceding and current row.  The measure column `m` is
-- SEPARATE from the window's own columns -- `wm <- (m, w)` -- and that is not a
-- stylistic choice: `Relation.Windowed.windowed` unions the aggregate's row with
-- the window's row, so ordering a running total BY the column it accumulates is
-- rejected with `Fields appear twice in row`.  Order by a date or a sequence.
runningTotal : forall k s w m wm r t c n rel.
               (exists o. w <- (k, s), wm <- (m, w), r <- (wm, o), RUnion2 t r c,
                PrimitiveNum n, RelationalComb rel)
            => Row k -> Sort s -> Field m n -> Field c n -> rel r -> rel t
runningTotal ks so m f =
  combine_Op (windowed_W (windowedAggregate_W (sum_Agg (col_Op m)))
                         (window_W ks so (F_W Unbounded_W (Bounded_W 0)))) f

-- | Trailing mean of `m` over `n` rows (the current row and the `n-1` before
-- it), within each partition and in the given order.  Same constraints as
-- `runningTotal`; only the frame differs, and the frame carries no columns.
movingAverage : forall k s w m wm r t c n rel.
                (exists o. w <- (k, s), wm <- (m, w), r <- (wm, o), RUnion2 t r c,
                 PrimitiveNum n, RelationalComb rel)
             => Int -> Row k -> Sort s -> Field m n -> Field c n -> rel r -> rel t
movingAverage n ks so m f =
  combine_Op (windowed_W (windowedAggregate_W (mean_Agg (col_Op m)))
                         (window_W ks so (F_W (Bounded_W (1 - n)) (Bounded_W 0)))) f

-- | The partition's total of `m`, repeated on every row of the partition: the
-- denominator of a share-of-total, and the cheap half of `share`.  The window
-- has NO sort (`empty_Srt`) and an unbounded frame, which is the one
-- combination the SQL emitter allows without an ORDER BY.
windowTotal : forall k m wm r t c n rel.
              (exists o. wm <- (m, k), r <- (wm, o), RUnion2 t r c,
               PrimitiveNum n, RelationalComb rel)
           => Row k -> Field m n -> Field c n -> rel r -> rel t
windowTotal ks m f =
  combine_Op (windowed_W (windowedAggregate_W (sum_Agg (col_Op m)))
                         (window_W ks empty_Srt unboundedFrame_W)) f

-- | `m` divided by its partition total, in ONE column -- the report step
-- "what fraction of this region's revenue is this account?".
--
-- This is the one helper here whose Op is an ARITHMETIC COMBINATION of two Ops
-- over different rows: `col m /_Op windowed(sum m) w`.  `(/_Op)` is an `OpBin`,
-- and `OpBin`'s signature is the four-constraint inclusion-exclusion lattice
-- `a <- (e,d), b <- (f,e), c <- (f,e,d)` over the two operand rows, carried here
-- on top of the window's own `wm <- (m, k)` and `combine`'s `RUnion2`.  That is
-- the overlapping shape `Ai/Common.e` warns about, which is why it is documented
-- at this length.
--
-- MEASURED, and against expectation: at the adopted defaults it is CHEAPER than
-- the two-step spelling (`windowTotal`, then an ordinary division) -- 0.05-0.06 s
-- against 0.08-0.09 s, on a six-column row and again on a twenty-six-column one.
-- One larger solve beats two smaller ones here.  `Wide.RevenueShare` writes both
-- forms side by side, and section 5 of `tracker/loopmodel/E1-EXAMPLES.md` has the
-- reproduction.
share : forall k m wm r t c n rel.
        (exists o. wm <- (m, k), r <- (wm, o), RUnion2 t r c,
         PrimitiveNum n, RelationalComb rel)
     => Row k -> Field m n -> Field c n -> rel r -> rel t
share ks m f =
  combine_Op (col_Op m /_Op windowed_W (windowedAggregate_W (sum_Agg (col_Op m)))
                                       (window_W ks empty_Srt unboundedFrame_W)) f

-- | Rank within each partition and keep the top `n`.  The filter is on the rank
-- column the helper itself just minted, so the output row is `t`, not `r`: a
-- caller gets the rank back and can show it.
topNWithin : forall k s w r t c rel.
             (exists o u. w <- (k, s), r <- (w, o), RUnion2 t r c, t <- (c, u))
          => Row k -> Sort s -> Int -> Field c Int -> [..r] -> [..t]
topNWithin ks so n f r =
  filter_Pred (col_Op f <=_Pred prim_Op n) (rankWithin ks so f r)

-- ---------------------------------------------------------- derived columns
--
-- `Ai.Common.withColumn` adds ONE column and is the fast shape.  These two add
-- two and three, and each extra column adds another `RUnion2` and another
-- `r <- (v, o)` to the signature.  They exist to be MEASURED: this is the
-- constraint chain the census never sees from ordinary example code.

-- | Two derived columns in one call.  The intermediate row `t1` is existential:
-- the caller never names the relation that has the first column but not the
-- second.  Two row unions -- see the header note.
withDerived2 : forall v1 v2 c1 c2 a b r t1 t op1 op2 rel.
               (exists o1 o2. RUnion2 t1 r c1, r <- (v1, o1),
                              RUnion2 t t1 c2, t1 <- (v2, o2),
                AsOp op1, AsOp op2, RelationalComb rel)
            => op1 v1 a -> Field c1 a -> op2 v2 b -> Field c2 b -> rel r -> rel t
withDerived2 o1 f1 o2 f2 = combine_Op o2 f2 . combine_Op o1 f1

-- | Three derived columns, two existential intermediates, three row unions.
-- The second column may read the first and the third may read either, which is
-- why this is not just three calls to `withColumn` in the caller's eyes -- but
-- it IS three calls, and the report measures what that costs the solver.
withDerived3 : forall v1 v2 v3 c1 c2 c3 a b c r t1 t2 t op1 op2 op3 rel.
               (exists o1 o2 o3. RUnion2 t1 r c1, r <- (v1, o1),
                                 RUnion2 t2 t1 c2, t1 <- (v2, o2),
                                 RUnion2 t t2 c3, t2 <- (v3, o3),
                AsOp op1, AsOp op2, AsOp op3, RelationalComb rel)
            => op1 v1 a -> Field c1 a -> op2 v2 b -> Field c2 b
            -> op3 v3 c -> Field c3 c -> rel r -> rel t
withDerived3 o1 f1 o2 f2 o3 f3 =
  combine_Op o3 f3 . combine_Op o2 f2 . combine_Op o1 f1

-- ------------------------------------------------------------------- pivots
--
-- A `Fulcrum k v p` is the plan for turning rows into columns: `k` is the key
-- row whose VALUES become column names, `v` is the row the value Op reads, and
-- `p` is the row of columns the pivot will PRODUCE.  `p` grows by one field per
-- `pivotColumn`, which is why `consFulcrum` carries `p' <- (f, p)` and a
-- `RUnion2` over the value rows.  `pivot` then relates the narrow row to the
-- wide one: `r <- (k, v, i)` and `s <- (i, p)`, where `i` -- the identity
-- columns that survive the pivot -- is EXISTENTIAL and never written by the
-- caller.  That is the most existential-generating shape in the standard
-- library, and it is why this directory exists.

-- | Start a pivot plan: name the key column whose values become headers and the
-- value column the new columns are computed from.
startPivot : forall k v a. Field k String -> Field v a -> Fulcrum_Piv k v (||)
startPivot kf vf = nilFulcrum_Piv {kf} {vf}

-- | Add one produced column to a pivot plan: `pivotColumn q1 "Q1" period amount`
-- says "a column `q1`, holding `amount`, for the rows whose `period` is `Q1`".
-- `p' <- (f, p)` is the plan's row growing by one field; the `RUnion2` merges
-- the new column's value row into the plan's.
pivotColumn : forall f p p' v1 v2 v3 k a.
              (p' <- (f, p), RUnion2 v3 v2 v1)
           => Field f a -> String -> Field k String -> Field v1 a
           -> Fulcrum_Piv k v2 p -> Fulcrum_Piv k v3 p'
pivotColumn f keyValue kf vf ful = consFulcrum_Piv f (col_Op vf) { kf = keyValue } ful

-- | Apply a pivot plan to any relation that has the key and value columns:
-- everything else in the row is the identity `i` and survives as-is.  This is
-- `Relation.Pivot.pivot` with its signature written out, because the signature
-- is the documentation.
pivotBy : forall k v i p r s rel.
          (RelationalComb rel, r <- (k, v, i), s <- (i, p))
       => Fulcrum_Piv k v p -> rel r -> rel s
pivotBy = pivot_Piv

-- | The CONCISE pivot plan, for the common case where the produced columns can
-- be named after the key values themselves.  `pivotOnRow {Q1,Q2,Q3,Q4} amount
-- period` produces four columns called `Q1`..`Q4`, each holding `amount` for the
-- rows whose `period` is the matching string.  It is `Relation.Pivot`'s
-- `defaultFulcrum`, and it is the right tool when the key values are legal field
-- names; `pivotColumn` is the right tool when they are not, or when the produced
-- column needs a different name, a different value column or a different Op.
pivotOnRow : forall p v k a. Row p -> Field v a -> Field k String -> Fulcrum_Piv k v p
pivotOnRow = defaultFulcrum_Piv

-- | The same, but a row whose key value is missing gets a default rather than a
-- null: the default is chosen from the produced column's TYPE (zero for a
-- number, the empty string, 1970-01-01 for a date).  Use it whenever the wide
-- table is going to be summed across, where a null would poison the row.
pivotOnRowWithDefault : forall p v k a.
                        Row p -> Field v a -> Field k String
                     -> FulcrumWithDefault_Piv k v p
pivotOnRowWithDefault = defaultFulcrumWithDefault_Piv

-- | Apply a defaulted pivot plan.  Same constraints as `pivotBy`.
pivotByWithDefault : forall k v i p r s rel.
                     (RelationalComb rel, r <- (k, v, i), s <- (i, p))
                  => FulcrumWithDefault_Piv k v p -> rel r -> rel s
pivotByWithDefault = pivotWithDefault_Piv

-- ------------------------------------------------------- unpivot / "melt"
--
-- The inverse of a pivot: several columns of the SAME type collapse into one
-- key column holding their names and one value column holding their values, and
-- the rest of the row (`i`) repeats.  Each arm drops the other melted columns,
-- adds the literal column name, and renames the surviving measure to the value
-- column; the arms are then unioned.
--
-- These are the SMALL-SIGNATURE surprise of this file.  Inferred, `melt3` has a
-- 22-constraint residual over 19 existentials.  Written down as a person would
-- say it -- "the input is the identity columns plus the three measures, the
-- output is the identity columns plus a key and a value" -- it is TWO
-- constraints, and the body checks against them.  That is the same lesson as
-- `core/examples/incomplete/Signatures.e`: what the solver publishes and what
-- the function means can be very far apart, and the annotation is what closes
-- the gap.
--
-- The arity has to be fixed.  A melt over "whatever columns this row happens to
-- have" would need to iterate a row variable and mint a union per field, which
-- the type system has no way to express; see section 7 of the E1 report.

-- | Melt two columns into key/value rows.
melt2 : forall key val fa fb i r out t rel.
        (r <- (i, fa, fb), out <- (i, key, val), RelationalComb rel)
     => Field key String -> Field val t
     -> Field fa t -> Field fb t
     -> rel r -> rel out
melt2 kf vf fa fb r =
  union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb} r)))
        (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa} r)))

-- | Melt three columns into key/value rows.
melt3 : forall key val fa fb fc i r out t rel.
        (r <- (i, fa, fb, fc), out <- (i, key, val), RelationalComb rel)
     => Field key String -> Field val t
     -> Field fa t -> Field fb t -> Field fc t
     -> rel r -> rel out
melt3 kf vf fa fb fc r =
  union (union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb,fc} r)))
               (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa,fc} r))))
        (rename fc vf (combine_Op (prim_Op (fieldName fc)) kf (except {fa,fb} r)))

-- | Melt four columns into key/value rows.
melt4 : forall key val fa fb fc fd i r out t rel.
        (r <- (i, fa, fb, fc, fd), out <- (i, key, val), RelationalComb rel)
     => Field key String -> Field val t
     -> Field fa t -> Field fb t -> Field fc t -> Field fd t
     -> rel r -> rel out
melt4 kf vf fa fb fc fd r =
  union (union (rename fa vf (combine_Op (prim_Op (fieldName fa)) kf (except {fb,fc,fd} r)))
               (rename fb vf (combine_Op (prim_Op (fieldName fb)) kf (except {fa,fc,fd} r))))
        (union (rename fc vf (combine_Op (prim_Op (fieldName fc)) kf (except {fa,fb,fd} r)))
               (rename fd vf (combine_Op (prim_Op (fieldName fd)) kf (except {fa,fb,fc} r))))

-- --------------------------------------------------------------- key lookup

-- | AS OF a set of dates: for each date in `ds`, the rows of the history `r`
-- that were in force then -- the latest row at or before it, looking back
-- arbitrarily far.  This is `Relation.lookupLatest` with its signature written
-- out, because the signature is the documentation and because the body it wraps
-- (`withFieldCopy`, `nearestDate`, two renames and a join) is one of the
-- heaviest in the standard library.
--
-- This is the AS-OF JOIN.  `latestPerKey` below is NOT: read both doc comments
-- before choosing.
asOfDates : forall h t r. r <- (h, t)
         => Field h Date -> Relation h -> Relation r -> Relation r
asOfDates = lookupLatest

-- | The latest row per key: group by `ks`, and within each group keep the row
-- whose `dF` is greatest.  One constraint (`r <- (k, v)`) plus `Has v d`, which
-- is the `exists` form of the same thing -- the cheapest generic helper here.
--
-- NOT AN AS-OF JOIN, and the difference matters.  `asOfDates` answers "what did
-- the history say on each of these dates", carrying one answer per date;
-- `latestPerKey` answers "what is the most recent row for each key", carrying
-- one answer per key and no date argument at all.  A report that wants "the
-- balance as of each month end" needs the first; a report that wants "the
-- current state of every account" needs the second.  `Wide.BranchDeposits` uses
-- both, on the same table, three lines apart.
latestPerKey : forall k v d r rel.
               (r <- (k, v), Has v d, Relational rel)
            => Row k -> Field d Date -> rel r -> Mem r
latestPerKey ks dF = groupBy ks (maxRowBy dF)
