module Algebra.Helpers where

{- GENERIC RELATIONAL-ALGEBRA HELPERS shared by the reports in this directory.

   Every function here is ROW-POLYMORPHIC: it names only the columns it needs
   and carries the rest through as a row variable. A partition constraint
   `r <- (k, o)` reads "the row r is exactly the disjoint union of k and o", so
   a caller may pass any relation carrying the named columns plus anything
   else, and `o` is the anonymous remainder the helper never looks at.

   ------------------------------------------------------------------------
   THREE RULES THIS FILE OBEYS, and why.

   1. EVERY HELPER HAS AN EXPLICIT SIGNATURE. Without one the compiler
      publishes whatever residual it inferred, and every call site re-solves
      that instead of the set the author meant; `Algebra/SoftSchema.e`'s
      `pivoted` shows what that costs -- eleven existentials and five
      `RUnion2`s for a five-column pivot. With a signature the definition is
      cheap and the published interface says what the author intended.

   2. NO HELPER TAKES A PREDICATE OR A CONDITIONAL Op. The conditional stays
      at the call site and the helper takes ready-made relations, `Row`s and
      `Field`s. `Ai/Common.e` gives a performance reason for this -- a helper
      bundling `if`'s `RUnion3` on top of `combine`'s `RUnion2` is reported
      there as not finishing at all. THAT DID NOT REPRODUCE (2026-09-06): the
      construction checks in 0.53 s at the adopted defaults and 0.48 s at the
      pre-adoption ones (`tracker/loopmodel/E2-EXAMPLES.md` section 4). The
      rule is kept on readability grounds, not on that measurement.

   3. THE SIGNATURES ARE WRITTEN IN THE `Has`/PARTITION FORM A PERSON WOULD
      WRITE, not the inferred residual. `Algebra/Signatures.e` proves for
      three of them -- `antiJoin`, `dedupeBy`, `groupSum` -- that the
      hand-written form and the inferred one entail each other.
   ------------------------------------------------------------------------

   WHAT THE ROW SOLVER SEES HERE that the older corpus never showed it:
   `joinWithDefault`'s `exists c s.` (the stdlib's only existentially
   quantified row constraints) instantiated at a call site; a partition
   constraint threaded through a RECURSIVE definition (`closure`);
   `Relation.Process` aggregators used as the group function of `groupBy`.
-}

import Prelude
import Layout
import Layout.Scan as Sc
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Aggregate as Agg
import Relation.Process as Proc
import Syntax.Relation

-- ===================================================================== joins
--
-- Ermine's `join` is a NATURAL join: the key is whatever column names the two
-- operands share. That is convenient and dangerous in equal measure, so the
-- first four helpers here are about saying which key you meant.

-- | Left outer join filling ONE missing column with a constant.
--
-- This is `Relation.joinWithDefault` under a name that says which side
-- survives. Its constraint set is the only place in the stdlib where row
-- variables are EXISTENTIALLY quantified (`exists c s.`): `c` is the join key
-- the two operands share, `s` is everything else the left side carries, and
-- neither is determined by the argument types alone -- the solver has to
-- invent them at each call site. `extra` is the column the right side adds and
-- the default fills in.
lookupOr : forall rel extra a r1 r2 r3.
           (exists c s. r1 <- (c, s), r2 <- (c, extra), r3 <- (c, s, extra),
            PrimitiveAtom a, RelationalComb rel)
        => Field extra a -> a -> rel r1 -> rel r2 -> rel r3
lookupOr = joinWithDefault

-- | Left outer join filling a WHOLE RECORD of missing columns.
--
-- The generalisation of `lookupOr` to a dimension that adds more than one
-- column. Read `t` twice: it is the dimension's NON-KEY row (`r2 <- (s, t)`)
-- AND the default record's row, so the record must name exactly the columns
-- the dimension adds -- not a subset, not a superset. One column too few and
-- the module does not check; `shouldfail/alg01` is that mistake.
enrich : (RelationalComb rel, r1 <- (r, s), r2 <- (s, t), r3 <- (r, s, t))
      => rel r1 -> rel r2 -> {..t} -> rel r3
enrich = leftJoinOr

-- | `enrich` with the arguments the other way round: keep every row of the
-- SECOND operand and default the first operand's private columns.
enrichRight : (RelationalComb rel, r1 <- (r, s), r2 <- (s, t), r3 <- (r, s, t))
           => rel r1 -> rel r2 -> {..r} -> rel r3
enrichRight = rightJoinOr

-- | The rows of `r` whose key appears in `probe` -- SQL's `WHERE key IN (...)`.
--
-- Projecting `probe` down to the key row first is what makes this a semi-join
-- rather than a join: the projection has exactly the key columns, so the
-- natural join cannot widen `r`, and the result row is `r` unchanged.
semiJoin : (RelationalComb rel, r <- (k, o), p <- (k, q))
        => Row k -> rel p -> rel r -> rel r
semiJoin ks probe r = join r (project ks probe)

-- | The rows of `r` whose key does NOT appear in `probe` -- SQL's `NOT IN`.
--
-- `difference` demands both operands have the SAME header, which is exactly
-- why the semi-join above had to be header-preserving.
antiJoin : (RelationalComb rel, r <- (k, o), p <- (k, q))
        => Row k -> rel p -> rel r -> rel r
antiJoin ks probe r = difference r (semiJoin ks probe r)

-- | Set intersection: the rows present in BOTH operands.
--
-- Ermine has no `intersect` primitive because it does not need one -- a
-- natural join of two relations with identical headers IS the intersection,
-- and the type says so: one row variable, used three times.
intersectRows : RelationalComb rel => rel r -> rel r -> rel r
intersectRows = join

-- | Set difference, spelled out for symmetry with `intersectRows`.
exceptRows : RelationalComb rel => rel r -> rel r -> rel r
exceptRows = difference

-- | Set union. Named beside its two siblings so all three set primitives read
-- alike and carry the same warning in their type: ONE row variable used three
-- times, so both operands must have the SAME header. There is no implicit
-- projection and no column reordering.
unionRows : RelationalComb rel => rel r -> rel r -> rel r
unionRows = union

-- | A join that will not silently degenerate into a cartesian product: the
-- `Field` argument is a WITNESS that the two operands share at least that one
-- column. `Relation.join1` under a name that says what the witness is for.
joinOn1 : (Relational rel, ra <- (k, r1), rb <- (k, r2), r <- (k, r1, r2))
       => Field k a -> rel ra -> rel rb -> rel r
joinOn1 = join1

-- | A join whose key must be EXACTLY the given row. If the two operands share
-- any other column the module does not type-check -- the usual way a natural
-- join goes wrong.
joinOnExactly : (Relational rel, r1 <- (k, t1), r2 <- (k, t2), r <- (k, t1, t2))
             => Row k -> rel r1 -> rel r2 -> rel r
joinOnExactly = joinBy

-- | A join whose key must CONTAIN the given row -- the head of a compound key,
-- with the tail left to inference. This is the `joinBy'` split: `kh` is named,
-- `kt` is solved for.
joinOnAtLeast : (Relational rel, r1 <- (kh, kt, t1), r2 <- (kh, kt, t2),
                 r <- (kh, kt, t1, t2))
             => Row kh -> rel r1 -> rel r2 -> rel r
joinOnAtLeast = joinBy'

-- | `lookupOr` with the operands the other way round: `Relation`'s
-- `rightJoinWithDefault`. The DIMENSION comes first and the fact table second,
-- and it is the fact table's rows that survive -- the mirror image of
-- `lookupOr`, and the reason both exist is that a pipeline reads better one way
-- round or the other depending on which relation you started from.
lookupOrRight : forall rel extra a r1 r2 r3.
                (exists c s. r1 <- (c, s), r2 <- (c, extra), r3 <- (c, s, extra),
                 PrimitiveAtom a, RelationalComb rel)
             => Field extra a -> a -> rel r2 -> rel r1 -> rel r3
lookupOrRight = rightJoinWithDefault

-- | The RAW right outer join: every row of the second operand survives and the
-- first operand's private columns are NULL where nothing matched.
--
-- "Unsafe" is the stdlib's word and it means the result's column types lie: a
-- column declared `String` comes back holding nulls. `enrich`/`lookupOr` exist
-- to make that safe by supplying a value, and this is what they are built on.
-- Note the class: `RelationalComp`, which appears in three commented-out
-- signatures and this one, and nowhere else in the stdlib.
rightOuter : (RelationalComp rel, r1 <- (r, s), r2 <- (s, t), r3 <- (r, s, t))
          => rel r1 -> rel r2 -> rel r3
rightOuter = unsafeRightJoin

-- | Overwrite a column from a lookup table, KEEPING the original value where
-- the table has no row for it. `Relation.partialLookup`: `key` is the column
-- being translated (present in both operands), `val` the translation the table
-- supplies. The result has the SAME header as the input -- `val` is folded into
-- `key`, not added beside it.
--
-- The third constraint is the one stage S3b (2026-09-11) had to add, here and in
-- `Relation.partialLookup` itself: the fold goes through `partialLookup'`, whose
-- result row is `key + val + o`, so the translation column must not ALREADY be
-- one of the input's other columns. `kv <- (key, val)` makes `val` disjoint from
-- `key` and `r <- (key, o)` makes `o` disjoint from `key`; neither makes `val`
-- disjoint from `o`, and with `val` inside `o` the body's own row is
-- unsatisfiable while the call was accepted anyway.
translate : ( exists r2
            . RelationalComb rel, PrimitiveAtom a
            , kv <- (key, val), r <- (key, o)
            , r2 <- (key, val, o) )
         => Field key a -> Field val a -> rel kv -> rel r -> rel r
translate = partialLookup

-- | `translate` without folding the value back into the key: BOTH columns
-- survive, so the reader can see which rows the lookup missed.
--
-- `Relation.partialLookup'`, which `partialLookup` calls and then hides under
-- an `except` and a `rename`. The interesting part is what stays visible: the
-- new column is `coalesce' val key`, so where the table had no row it holds the
-- KEY's own value, and comparing the two columns is how you audit the lookup.
translateKeeping : (RelationalComb rel, PrimitiveAtom a, kv <- (key, val),
                    r <- (key, base), r2 <- (key, val, base))
                => Field key a -> Field val a -> rel kv -> rel r -> rel r2
translateKeeping = partialLookup'

-- =================================================================== columns

-- | Copy a column under a second name, keeping the original. The remainder `o`
-- is what makes this generic; the constraint pair is the reason `carry f f`
-- (copying onto itself) is a type error rather than a no-op.
carry : (Relational rel, ri <- (src, o), ro <- (src, dst, o))
     => Field src a -> Field dst a -> rel ri -> rel ro
carry = copyColumn

-- | Rename `from` to `to`, where the relation does NOT already carry `to`.
--
-- This -- not `Relation.UnifyFields.unify1` -- is how two differently-named
-- schemas are made joinable; see the note at the bottom of this file. The
-- signature is worth reading twice: the untouched remainder `o` appears in
-- BOTH partitions, which is the shape the solver has to cancel a concrete
-- left-hand side against before it can see whether `to` collides.
alias : (RelationalComb rel, r <- (from, o), out <- (to, o))
     => Field from a -> Field to a -> rel r -> rel out
alias = rename

-- | Rename `from` to `to`, DROPPING the column that was called `to` already.
--
-- `Relation.rename'`. The difference from `alias` is one constraint: `to`
-- appears on the INPUT side too, so this is a type error exactly when `alias`
-- would work and vice versa. Ermine has no helper that does whichever is
-- needed -- the choice is in the type, so the caller has to make it.
overwriteWith : (RelationalComb rel, r <- (from, to, o), out <- (to, o))
             => Field from a -> Field to a -> rel r -> rel out
overwriteWith = rename'

-- ================================================================== grouping

-- | Total a measure per key. `k` is the grouping row, `m` the measure, and the
-- result is the key columns plus the measure -- everything else is gone,
-- which is what `out <- (k, m)` says.
groupSum : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m),
            PrimitiveNum n)
        => Row k -> Field m n -> rel kv -> Mem out
groupSum ks amt r = groupBy ks (sumBy amt) r

-- | Mean of a measure per key. Identical shape to `groupSum`; the only
-- difference is the aggregate.
groupMean : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m),
             PrimitiveNum n)
         => Row k -> Field m n -> rel kv -> Mem out
groupMean ks amt r = groupBy ks (meanBy amt) r

-- | The `n` rows of each group that sort HIGHEST by `ord`, whole rows kept.
--
-- Note what the group function sees: `groupBy` hands it the NON-key part of
-- the row (`v`), so `ord` must be inside `v` -- `v <- (ord, o)` -- and grouping
-- by a column you also want to rank by is a type error.
groupTop : (Relational rel, kv <- (k, v), v <- (ord, o))
        => Row k -> Row ord -> Int -> rel kv -> Mem kv
groupTop ks ord n r = groupBy ks (topK ord n) r

-- | The `n` LOWEST rows of each group by `ord`.
groupBottom : (Relational rel, kv <- (k, v), v <- (ord, o))
           => Row k -> Row ord -> Int -> rel kv -> Mem kv
groupBottom ks ord n r = groupBy ks (bottomK ord n) r

-- | One row per key: the one that sorts highest by `ord`. Latest-wins
-- deduplication when `ord` is a timestamp or a version number.
dedupeBy : (Relational rel, kv <- (k, v), v <- (ord, o))
        => Row k -> Row ord -> rel kv -> Mem kv
dedupeBy ks ord r = groupTop ks ord 1 r

-- | The single highest row of the WHOLE relation by `ord` (`Relation.firstBy`).
-- Beware the names: `firstBy` is the top of a DESCENDING limit and `lastBy` the
-- top of an ascending one, so `pickHighest` is `firstBy` and `pickLowest` is
-- `lastBy`.
pickHighest : Has r ord => Row ord -> [..r] -> [..r]
pickHighest = firstBy

pickLowest : Has r ord => Row ord -> [..r] -> [..r]
pickLowest = lastBy

-- ===================================================== Relation.Process pipes
--
-- `Relation.Process` aggregators are not `Relation.Aggregate` aggregates: they
-- are opaque process symbols evaluated by the backend, and they take a whole
-- relation to a one-row one. That makes them exactly the right shape for
-- `groupBy`'s group function, which is what these two do.

-- | Median of a measure per key -- an aggregate `Relation.Aggregate` does not
-- have, because a median cannot be computed incrementally.
groupMedian : (Relational rel, kv <- (k, v), v <- (m, o), out <- (k, m),
               PrimitiveNum n)
           => Row k -> Field m n -> rel kv -> Mem out
groupMedian ks m r = groupBy ks (medianBy_Proc m) r

-- | Weighted mean of `m` with weights `wt`, per key. Two measure columns go in
-- and one comes out, so `v` is partitioned three ways.
groupWeightedMean : (Relational rel, kv <- (k, v), v <- (wt, m, o),
                     out <- (k, m), PrimitiveNum n)
                 => Row k -> Field wt n -> Field m n -> rel kv -> Mem out
groupWeightedMean ks wf mf r = groupBy ks (weightedMeanBy_Proc wf mf) r

-- | A RUNNING TOTAL, which Ermine has no window function for.
--
-- For each row, the sum of `amt` over every row whose `ord` is at most this
-- row's. The mechanism is the one every SQL dialect without `OVER` has to use:
-- take a second copy of the relation with its two columns RENAMED (so the join
-- is a deliberate cartesian product rather than an accidental natural join),
-- filter the product down to the pairs that satisfy `<=`, and group. The two
-- renames go to GUID-named scratch columns from `withFieldCopy`, so the helper
-- cannot collide with anything in the caller's row.
--
-- The cost is quadratic in the number of rows, which is what a self-join
-- running total costs everywhere. `Relation.Scan` does it in one pass but
-- cannot give the answer back as a relation; `Algebra/Comprehensions.e`
-- computes both and says which is which.
runningTotal : (r <- (ord, amt, o), out <- (r, tot), PrimitiveNum n)
            => Field ord k -> Field amt n -> Field tot n -> Mem r -> Mem out
runningTotal ordF amtF totF r =
  withFieldCopy ordF (o' ->
  withFieldCopy amtF (a' ->
    let prior = rename amtF a' (rename ordF o' (r # {ordF, amtF}))
        pairs = filter_Pred (col_Op o' <=_Pred col_Op ordF) (join prior (r # {ordF}))
        sums  = rename a' totF (groupBy {ordF} (sumBy a') pairs)
    in join r sums))

-- ================================================================ hierarchies

-- | Compose two edge relations: an (a,b) edge followed by a (b,c) edge gives
-- an (a,c) edge.
--
-- The scratch column is the interesting part. Joining "to" against "from"
-- means both must be called the SAME thing, and the result must then be called
-- neither -- so `withFieldCopy` mints a column name that provably collides with
-- nothing (it is a GUID), the join happens on it, and it is projected away
-- again. The row variable `e` never leaves the helper.
composeEdges : (e <- (from, to))
            => Field from a -> Field to a -> [..e] -> [..e] -> [..e]
composeEdges f t ab bc = withFieldCopy t (m ->
  except {m} (join (rename t m ab) (rename f m bc)))

-- | Transitive closure of an edge relation by PATH DOUBLING: after `n` rounds
-- every path of length up to 2^n is present. Four rounds cover any tree
-- sixteen levels deep, which is more than any hierarchy in this directory.
--
-- This is the one recursive definition in the library, and it is worth knowing
-- what the recursion costs the type checker: the constraint `e <- (from, to)`
-- has to be discharged at the recursive call as well as at the top, and
-- `materialize` at each round keeps the relational expression from growing
-- exponentially alongside it.
closure : (e <- (from, to))
       => Field from a -> Field to a -> Int -> [..e] -> [..e]
closure f t n e =
  if (n <=_Primitive 0)
     e
     (closure f t (n - 1) (materialize (union e (composeEdges f t e e))))

-- | The rows of a parent/child hierarchy that are nobody's parent: the leaves.
-- `Relation.leafRows`, which is a set difference against a self-join.
leaves : (r <- (parent, child, o))
      => Field parent n -> Field child n -> [..r] -> [..r]
leaves = leafRows

-- ===================================================================== scans
--
-- `Relation.Scan` is a different animal from the rest of this file: a Scan is
-- a CPS computation over a vector of records, so its answer type `z` is fixed
-- by whoever runs it. `Layout.Scan` fixes it to `Report`, which is why these
-- two helpers mention `Report` in their types even though they do no layout.

-- | One group per key, folded to a ONE-COLUMN relation holding the total.
--
-- The input must already be projected to the key and the measure: `sumBy'`
-- constrains the aggregate's `Op` row to be the whole group row, so anything
-- else in the row would have to appear in the `Op` too. That is why the
-- signature says `r <- (h, m)` and not `r <- (h, m, o)` -- there is no
-- remainder to carry.
scanTotals : (r <- (h, m), PrimitiveNum n)
          => Field h k -> Field m n -> Field tot n
          -> [..r] -> Scan_Sc (Report f z) (k, Relation tot)
scanTotals key amt tot r = sumBy'_Sc (col_Op amt) tot (groupBy1_Sc key r)

-- | One group per key, folded to a one-column relation holding the row count.
-- `count'` has no `Op` argument, so this one CAN carry a remainder.
scanCounts : (r <- (h, o))
          => Field h k -> Field c Int -> [..r] -> Scan_Sc (Report f z) (k, Relation c)
scanCounts key cf r = count'_Sc cf (groupBy1_Sc key r)

{- ------------------------------------------------------------------------
   WHAT IS NOT HERE, AND WHY.

   `Relation.UnifyFields.unify1` is the stdlib's advertised way to make two
   differently-named schemas joinable, and it CANNOT DO THAT. Its signature was

       unify1 : (r <- (h,f,t), r2 <- (h,f2,t))          -- before stage S3b
             => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]

   which constrains the two operands to agree on everything but one column each
   (`h` and `t` are shared) and leaves `f1` -- the column being renamed --
   mentioned in NO constraint at all. Feeding it a source keyed on `custId` and
   a target keyed on `customerId` is rejected:

       Row partitions are unsatisfiable at field 'customerId':
       the whole contains it but no part does

   The only calls that check are ones where both operands have the SAME header,
   in which case it is a self-semi-join under a key alias, not a unification.
   `Algebra/Customer360.e` documents the measurement; `alias` above is what
   the reports use instead.

   Stage S3b (2026-09-11) corrected the signature to

       unify1 : (r2 <- (f1,f2,p), r <- (f2,p,u))
             => Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]

   -- `f1` and `f2` are columns of the second operand, and the first carries `f2`
   and the shared part `p` -- which says what the body does and no longer leaves
   `f1` unconstrained. It does NOT make the function a unification: the operands
   still have to share `f2 + p`, so the finding above stands, and the self-alias
   call in `Customer360.e` still checks (a tighter reading that the survey
   recommended, `r2 <- (h,f1,f2,t)` with `r <- (h,f2,t)`, would have refused it --
   `tracker/loopmodel/SIG-3b-CORRECTIONS.md` 2).
   ------------------------------------------------------------------------ -}
