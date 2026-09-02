# The substitution gap: a race on the variable ids, not the redundant partition

Answer to `tracker/PROMPT-substitution-gap.md` (2026-09-02). Everything below is measured
with an instrument named next to the number; nothing is inherited.

## 1. The answer

**The redundant partition is a symptom.** `Ai/HeadcountPlan.labelled` publishes the concrete
9-field row or the constrained polymorphic type according to the VARIABLE IDS the solve
receives -- the same three partitions pin `t` at 103 of 200 contiguous id bases and fail at
the other 97, with the redundant partition absent; adding it to regime A's input leaves `t`
pinned; removing either copy from regime B's leaves it unpinned; and swapping only the ids
between the two shapes flips both. (§3, instrument: `tracker/repro/nameloss/run.sh`, a
harness that calls `Subst.solve` on the exact constraint lists with the exact ids, verified
to reproduce both regimes' trace summaries byte-for-byte: A `sat=13 derived=7
CSE:2,Split:2,Subst:3` pinned, B `sat=12 derived=6 CSE:2,Split:2,Subst:2` unpinned.)

**The mechanism is a race inside `Constraints.incorporateAll`** between the concretisation of
a split-minted name and the common-subexpression fold that needs it (§2). Read off the
step trace (instrument: the `step`/`learn` records added to `RowTrace` today, §5) and then
confirmed causally: keeping the deleted definitions (first behind a flag, then -- on the
user's decision -- unconditionally, §7) makes all 574 harness configurations pin and makes
both real build orders publish the same concrete signature for every binding in
`HeadcountPlan.ei` (§4).

**The order is a function of the ids** through the priority-queue key: `pop` takes the
leftmost element of minimum `graph.sort(lhs)`, and the finger tree is kept ordered by
`(rhs.hashCode, lhs.hashCode)` -- so `graph.sort` is PRIMARY and the hash pair breaks
ties. `graph.sort` is an index into `reverseTopSort(newNodes.toStream)` over a
`Set[TypeVar]` (hash order once the set exceeds four elements), recomputed whenever a new
edge violates the current order -- which a mint always does, and is why the MINT ids
participate; `V.hashCode = id`. These are sites (1) and (2) of the ten-site inventory in
`TICKET-row-constraint-decision.md` §7 (which lists their roles the other way round, hash
pair primary and topological sort as tie-break -- corrected in §6). The inventory's
occurrence-rank prescription would make the outcome deterministic, but NOT complete: it
would fix one of the two orders for every module, and which one is a coin toss the
ranking decides. Completeness needs the deletion fixed (§7).

## 2. The mechanism, on the smallest input that shows it

Three constraints (`tracker/lean/Rowpartition/NameLoss.lean` §2; harness `minimal`):

    (|k, c|) <- ((|k|), x, y)        (|d|) <- (x, z)        t <- (x, y, z)

Semantically `x = ()`, `y = (|c|)`, `z = (|d|)`, `t = (|c, d|)` (proved:
`NameLoss.G₀_entails_goal`). `PQueue.build` turns the two concrete left-hand sides into
fresh variables `R`, `D` with two partitions each, five partitions in all. Under the default
`genRules=cut`:

1. `R <- ((|k|), x, y)` is dequeued: `splitConcrete` MINTS a name for the pair,
   `u <- (x, y)`, plus the mention `R <- ((|k|), u)`.
2. `R <- ((|k|), u)` against `R <- ((|k, c|))`: cancellation gives `u <- ((|c|))`.
3. `u <- ((|c|))` is dequeued on the `concrete` branch: `makeConcrete` -> `destructiveSub`.
   Because `u` HAS a mention (`R <- ((|k|), u)`), `srs` is nonempty and the filter
   `p` at `Constraints.scala` `destructiveSub` deletes every partition with `u` on the left
   or the right. The mention is rewritten to `R <- ((|k, c|))`, already present. The
   definition `u <- (x, y)` is simply gone: `cancellation(u, (|c|), (x, y))` can re-express a
   definition with ONE abstract part (`ys.size == 1`), not two.
4. `t <- (x, y, z)` is dequeued. It shares `x ++ y` with `R <- ((|k|), x, y)`.
   `commonSubexpression` under the cut has two branches, reuse (`rhss(rhsCommon)` hits) and
   fold (one side IS the common part); `cseMints` is false. Nothing names `{x, y}` any more,
   so it learns nothing. `t` is never pinned: the saturated set is exactly the eight
   partitions `{R <- (|k,c|), R <- ((|k|),x,y), D <- (|d|), D <- (x,z), t <- (x,y,z),
   u <- (|c|), t <- (y, D), t <- ((|d|), y)}` (trace, `sat` records at id base 1).

In the other order `t <- (x, y, z)` is dequeued BEFORE step 3, the reuse fires while
`u <- (x, y)` is still in `proc`, `t <- (z, u)` is learnt, and step 3 rewrites it to
`t <- ((|c|), z)` -- a partition of `t` carrying the concrete row. Resolution against
`t <- ((|d|), y)` then mints `v` with `y <- ((|c|), v)`, `z <- ((|d|), v)`, substitution puts
`z`'s definition into `D <- (x, z)`, a second split names `(x, v)`, cancellation against
`D <- (|d|)` empties it, `makeEmpty` empties `x` and `v`, and `t <- ((|c, d|))` follows
(trace at id base 0; formalised as `NameLossDerivation.orderA_derives_goal`, §5).

Two remarks the Lean makes precise:

* The loss is DERIVATIONAL, not semantic. The concretise-first system still contains
  `R <- ((|k|), x, y)` and `R <- ((|k, c|))`, which say `x ++ y = (|c|)`; it entails
  `t = (|c, d|)` (`NameLoss.orderB_entails_goal`). What it has lost is the NAME, and under
  the cut only a name lets the fold fire.
* The rule set could recover; the LOOP cannot. `splitConcrete`'s guard (the reverse lookup
  misses) is satisfied again after the deletion, so a re-split of `R <- ((|k|), x, y)` is
  ENABLED (`NameLoss.orderB_remint_enabled`). But `incorporateAll` examines a partition once,
  at its dequeue, and nothing re-enqueues `R <- ((|k|), x, y)`. So the additive calculus
  the Lean development models is complete on this input and the single-pass implementation
  of it is not.

## 3. Evidence (harness, `tracker/repro/nameloss/run.sh`)

Exact replays with the real ids, default flags:

| input | `t` |
|---|---|
| regime A, exact 3 partitions, ids 615048.. | 9-field row |
| regime B, exact 4 partitions (redundant one present), ids 506328.. | unpinned |
| B minus the redundant partition (either copy) | unpinned |
| A plus a redundant partition | 9-field row |
| A's shape with B's ids; B's shape with A's ids | both unpinned |

Id sweeps (goal reached / configurations):

| shape | 200 contiguous bases | 24 input-id permutations | 50 mint-id offsets, inputs fixed |
|---|---|---|---|
| A (3 partitions) | 103 | 0 | 45 |
| B (4, with the duplicate) | 56 | 6 | 43 |
| B minus the duplicate | 90 | 24 | 46 |
| minimal instance, split mints the name | 90 | 24 | 46 |
| minimal instance, name given as input `(|c|) <- (x, y)` | 200 | 24 | 50 |
| any of the above with the definitions kept (then `-Dermine.keepConcreteDefs=true`, now unconditional) | all | all | all |
| any of the above with `-Dermine.genRules=all` (CSE mints) | all | all | all |

The third column is the cleanest statement: with the input ids FIXED, changing only where
`Supply` hands out the minted ids flips the outcome. The "name given as input" row is the
control for the mechanism: when nothing mentions the name, `destructiveSub` takes its
`srs.isEmpty && keep` branch and keeps the definitions, and the race cannot be lost.

`resGuard` on/off changes none of these numbers.

## 4. The causal test in the real compiler

Measured while the change was still behind `-Dermine.keepConcreteDefs=true` (later made
unconditional, §7; `destructiveSub`, on the nonempty-`srs` branch; keeps the definitions
of the concretised variable that have two or more abstract parts):

| | regime A | regime B |
|---|---|---|
| default | `labelled : Relation (|9 fields|)`; module solve `rows=3 sat=13` | `forall t. (exists a rs so. ...) => Relation t`; `rows=4 sat=12` |
| flag on | `Relation (|9 fields|)`; every module-level solve `rows=0` | identical `.ei` to regime A, byte for byte |

(`regimes2.sh`, both sides delete every `.ei` first; the flag-on `.ei` for A is also
identical to the default A.) With the flag every constraint of `labelled` is discharged by
the per-subexpression `trySolveOn` solves, which is why the module-level solve sees nothing.

Corpus-wide interface diff (`tracker/tools/ei-diff.sh`, examples + stdlib, every `.ei`
deleted on both sides): 188 interfaces
captured on each side, none missing on either (so nothing timed out at 120 s with the flag),
**10 differ**, classified by a matcher that compares signatures up to constraint order,
right-hand-side order and renaming of existentials (`Exp6`-adjacent script, session scratch):

| interface | binding(s) | verdict |
|---|---|---|
| `Ai/HeadcountPlan` | `labelled`, `withUnitCost` | polymorphic -> concrete 9-field row (the target) |
| `Ai/BatteryCycling` | `withHealth` | polymorphic -> concrete row (same mechanism, same `combine` shape) |
| `Ai/RevenueByPeriod` | `labelled` | polymorphic -> concrete row |
| `incomplete/RunCalibration` | `scaledRuns` | still polymorphic; 7 constraints -> 6: the flag side no longer carries the pair `a <- (K, b, rs)`, `a <- (K, rs, b)` -- the redundant-by-order duplicate again -- and is otherwise alpha-equivalent |
| `PivotTest` | `pivotData`, `pivotData2` | alpha-equivalent (existentials renamed) |
| `SoftRelation` | `showWordstats` | right-hand-side order only |
| `Layout/Chart`, `Layout/Report` | 4 bindings | constraint order only |
| `Relation/Op` | 17 bindings | constraint order only |
| `Relation/Predicate` | 6 bindings | alpha-equivalent (`(<=)`, `(>=)` have 13 constraints each; matched by backtracking) |

No interface got weaker. The order-only churn is itself evidence for §6: the flag changes
which variables get minted, the ids shift, and every id-keyed order downstream shifts with
them.

Compile time, whole `bin/ermine` run including JVM start and stdlib load, three runs each,
medians (instrument: `date +%s.%N` around `bin/ermine`, `.ei` deleted before every run;
the machine was also running Lean elaborations for part of this, so treat ±1 s as noise):

| module(s) | deleting (old default) | keeping (then the flag, now the default) |
|---|---|---|
| `Ai/Common.e` + `Ai/HeadcountPlan.e` | 14.1 s | 13.8 s |
| `Ai/Common.e` + `Ai/BatteryCycling.e` | 13.7 s | 14.1 s |
| `PivotTest.e` | 15.1 s | 13.1 s |
| `Accumulate.e` | 14.9 s | 15.2 s |

No measurable cost. The trace-level counts for HeadcountPlan agree: the same 60425 (A) and
2462 (B) solves with the flag as without, and FEWER splices (B: 100 -> 65).

## 5. What is proved (`tracker/lean/Rowpartition/`)

All three files type-check with `lake env lean` (exit 0, no output) and use no axiom
beyond the standard three; they are NOT yet imported by the root `Rowpartition.lean` (see
§7).

`NameLoss.lean`:

| theorem | says |
|---|---|
| `concretize_sound` | `makeConcrete`'s rewrite-and-delete is sound: with `u <- ((|C|))` in the system, every model of the system models `concretize u C G` |
| `concretizeKeep_sound` | keeping the definitions is sound (they were there) |
| `grace_reached` | the cut reaches the race state `Grace` from the input in two steps (split-mint, cancellation) |
| `orderA_has_fact` | fold then concretise: `t <- ((|c|), z)` is in the result |
| `orderB_lacks_fact`, `orderB_eq` | concretise first: it is not, and the result is exactly the input plus `u <- ((|c|))` |
| `G₀_entails_goal`, `orderB_entails_goal` | the input, and the concretise-first system, entail `t = (|c, d|)` |
| `orderB_remint_enabled` | `SplitApp` holds again on `R <- ((|k|), x, y)` after the deletion |
| `keep_recovers_fact` | with the definition kept, fold + substitution recover the fact in two non-generative steps |

`NameLossClosed.lean`: 20 theorems. `Cl` is the nine-constraint set (the eight of the trace plus the
degenerate `D <- (D)` that the Lean `reuse` rule emits and the Scala drops).

| theorem | says |
|---|---|
| `Cl_closed` | every `NonGenStep` from `Cl` stays inside `Cl` -- proved rule by rule (`cancel_closed`, `subst_closed`, `selfSubst_closed`, `commonPart_closed`, `splitReuse_closed`, `fold_closed`, `reuse_closed`), by exhausting the 81 constraint pairs per rule; the only enabled instances are the ones the hand analysis predicted, nothing had to be added to `Cl` |
| `NonGenStep.mono`, `reach_subset_Cl` | the rules are monotone in the system, so everything reachable from a subset of `Cl` stays in `Cl` |
| `orderB_subset_Cl` | the concretise-first system is a subset of `Cl` |
| `orderB_stuck` | **no non-generative derivation from the concretise-first system contains `t <- ((|c|), z)`, or `t <- ((|c, d|))`, or any name for `{x, y}`** |
| `keep_vs_delete` | side by side: with the definition kept, a non-generative derivation reaches the fact; with it deleted, none does |

`NameLossDerivation.lean`: 53 theorems. The eleven-step derivation as eleven literal systems `S1 .. S11`
with a `SatStep` between each pair -- fold, substitution, fold, substitution, resolution
(mint `v`), substitution, split (mint `s`), cancellation to `s <- ()`, two `makeEmpty`
propagations and one erasure -- ending in `tGoal ∈ S11`.

| theorem | says |
|---|---|
| `orderA_steps`, `tGoal_mem_S11` | `SatSteps 11 Grace S11` and `t <- ((|c, d|)) ∈ S11` |
| `orderA_derives_goal` | `∃ n G', SatSteps n Grace G' ∧ tGoal ∈ G'` |
| `input_derives_goal` | composed with `grace_reached`: `SatSteps 13 G₀ S11 ∧ tGoal ∈ S11` -- from the INPUT, thirteen steps of the solver's own relation pin `t` |
| `derived_entailed` | and the semantic side, re-exported: `SEntails G₀ tGoal` |

So the same input, under the same step relation, has one run that pins `t` and one that
provably cannot; the difference is one `concretize` applied before or after one fold. Root
`Rowpartition.lean` now imports all three; `lake build Rowpartition` succeeds (809 jobs)
and `Audit.lean` reports 1625 theorems audited, 0 using a non-standard axiom (was 1465).
Each of the fifteen headline theorems above also reports exactly
`[propext, Classical.choice, Quot.sound]` under `#print axioms`.

The model of the Scala step is `concretize u C G := insert (mk u ∅ C) ((G.filter (·.lhs ≠ u)).image (absorbC u C))`
with `absorbC` the `subPartitions` rewrite. An independent read of `destructiveSub` against
this definition: an adversarial reviewer
(read-only, session workflow) tried to refute seven claims and refuted none. Its caveats,
all inert on the instance but worth recording: (i) Scala's `srs` also contains, for every
mention and every OLD definition of `u`, the rewrite of the mention under that definition
(`destructiveSub`'s foldLeft over `(pps ++ qps).map(_._2)`), so in general `concretize`
UNDER-approximates what the solver keeps; here that extra rewrite is `R <- ((|k|), x, y)`,
already present, and the trace's `proc` count (4 -> 3) matches `orderB_eq` exactly.
(ii) Rewritten copies go to `incm` and are re-examined; the set model has no such split
and is therefore never stronger than the solver. (iii) `RHS.merge` and `ensureSuperset` die
on a concrete clash where `absorbC` silently unions -- refutation paths only. (iv) The
"examined once" claim is per residence in `proc`: `makeConcrete`'s cancellations and
`instantiate`'s `replace` output are re-enqueued without `trim`, but a partition already in
`proc` is then consumed by the common-partition branch (`unify(v, v)`), never re-learnt; a
partition can be re-examined only if a destructive step first deletes it and something
re-derives it, which does not happen here. (v) The pinning chain is resolution ->
substitution -> split -> cancellation -> `makeEmpty` -> common-partition -> substitution;
the empties and substitutions are load-bearing, not just resolution and cancellation.

## 6. Consequences for standing documents

* **`TICKET-row-constraint-decision.md` §7, the ten-site inventory.** Sites (1) and (2) are
  the sites at work here, so the inventory is right that the order leaks through them.
  Three corrections:
  0. The roles are inverted: the inventory calls (1) the hash pair "the PSQ key" and (2)
     `reverseTopSort` "tie-breaking". In `Q.pr`/`pop` the topological index is the priority
     and the hash pair orders the tree, i.e. breaks ties. (Reviewer's reading of
     `Constraints.scala` :464-527, confirmed against the traces.)
  1. Right-hand-side ORDER is not cosmetic at a site the inventory does not list:
     `Exists.apply` (`Type.scala` ~295) builds its constraint list with `p.toSet.toList`,
     and `Part.equals` compares the right-hand side as a LIST. Two partitions that are equal
     as sets survive as two constraints iff their lists differ -- measured: the four-Part
     regime-B list collapses to 3 constraints when the duplicate's order matches, stays at 4
     when it does not (`Exp6`). That is why regime B "receives a redundant constraint" at
     all. It is an eleventh site, and an occurrence-rank comparator does not touch it; the
     fix there is to dedup Parts up to permutation of the right-hand side (or to canonicalise
     the list in `Part.apply`).
  2. Determinism is not completeness. Ranking the queue by occurrence would pin every
     module to ONE of its orders; on this input that is a 103-to-97 coin toss decided by
     the rank. The published type would stop flapping with build history and might land on
     the polymorphic side for good.
* **The brief's live hypothesis** ("`Partition` equality includes `inf`, so `insert`'s dedup
  lets two same-`_1`/`_2` partitions survive") is refuted by measurement: `Partition.equals`
  and `hashCode` ignore provenance (explicit overrides, `Constraints.scala` ~792), and
  inserting three provenance-variants into a `PQueue` leaves one partition (`Exp6`). Site (7)
  (the `Set[Partition]` folds into `++!`) is not involved: the two copies of the redundant
  constraint become partitions on two DIFFERENT fresh variables in `PQueue.build`, and are
  merged by the common-partition rule, not by `insert`.
* **`ROW-CONSTRAINT-STATE.md`'s** description of regime B as "receives a redundant
  constraint and is one Substitution short" is accurate as a description and wrong as a
  causal reading; the Substitution it is short of is the one that rewrites `t <- (z, u)`,
  which was never learnt.

## 7. The fix, adopted: keep the definitions

Proposed behind `-Dermine.keepConcreteDefs` (default off) and measured as above; then, on
the user's decision (2026-09-02), made UNCONDITIONAL and the property removed. The change
is confined to `destructiveSub`: on the branch that rewrites mentions of the concretised
variable, its definitions with two or more abstract parts are kept (in `proc` or `incm`,
wherever they were) instead of deleted. Definitions with one abstract part are still
re-expressed by `makeConcrete`'s cancellation as before; the `srs.isEmpty && keep` branch,
which always kept everything, is unchanged.

Licence: `Rowpartition.NameLoss.concretizeKeep_sound` (the kept partitions were already in
the set) and `keep_recovers_fact` / `NameLossClosed.keep_vs_delete` (the fold the deletion
blocked now fires). Measurements: §3 (574/574 harness configurations pin, re-run under the
unconditional build: identical), §4 (corpus interface diff, timing).

What was NOT re-proved, and what stands in for it:

* Termination. The kept definitions re-enable only the reuse/fold branch of
  `commonSubexpression` and `substitution`, which mint nothing; `resolution` needs
  single-variable forms, which a two-abstract definition is not. The sweep covers every
  `.e` under `core/examples/` including `incomplete/` at a 120 s cap with no timeout, and
  the six `.slow` divergence seeds were timed separately (§4).
* The common-partition branch can now unify a later same-right-hand-side variable with a
  concrete one (`unify(w, v)`, or `v` renamed to `w` through `++!` on the `incm` side);
  sound, and the pre-existing keep branch already produced the same states. The corpus
  diff is the measurement.
* `Subst.reduce`'s splice sees the kept `u <- (x, y)` with `u` ambiguous; for a
  split-minted `u` no input constraint mentions it, so the splice is a no-op. For an INPUT
  variable made concrete, the fold order in `reduce` decides whether the concrete case or
  the splice reaches the residual first -- a signature-form change already possible on the
  keep branch, and none appeared in the corpus diff.

Re-measured under the UNCONDITIONAL build (no property; `regimes`-style sweep of every
`.e` under `core/examples/` incl. `incomplete/`, 120 s cap, every `.ei` deleted first;
session script `sweep-new.sh`, snapshot `C`; compared with the matcher of §4 against the
two saved snapshots, `A` = old deleting default and `B` = old build with the flag):

| comparison | result |
|---|---|
| files compiled | 110, all exit 0, none timed out; slowest `Accumulate.e` at 13.0 s |
| interfaces captured | 188, same set as both earlier sides |
| `C` vs `A` (fix vs old default) | the same 10 interfaces as the flag run, same classification: 4 bindings polymorphic -> concrete (`HeadcountPlan.labelled`, `.withUnitCost`, `BatteryCycling.withHealth`, `RevenueByPeriod.labelled`), `RunCalibration.scaledRuns` loses its redundant duplicate, everything else alpha-equivalent -- plus `Relation.ei`, see next row |
| `C` vs `B` (unconditional vs flag) | identical except `Relation.ei` (`lookbackJoin`, `minRowBy`, `partialLookup'`) and `Relation/Op.ei` (`negate`): binder renamings and constraint order, and one more constraint on `lookbackJoin` |
| the `Relation.ei` difference, re-tested | thread-timing noise, not the change: compiling `Accumulate.e` six times under the SAME new build gave `lookbackJoin` the `A`/`B` form five times and the `C` form once; `-Dermine.loadInSeries=true` gives a third, stable form. `Relation/Op.ei` likewise churns between two runs of one build (18 lines, all alpha-equivalent). `tracker/tools/g1-diff.sh` documents exactly this: "thread timing otherwise reaches `.ei` bytes through the solver's id-hash queue -- measured on lookbackJoin". |
| the six `.slow` divergence seeds (`gu02`, `gu03`, `gu07`, `gu09`, `np05a`, `np05c`) + `gu01` | all exit 0 in 12.7-13.1 s each -- JVM start plus stdlib load, i.e. the solve itself is negligible, as under the cut before |
| harness (`tracker/repro/nameloss/run.sh`) | 574 of 574 configurations pin, all three HeadcountPlan shapes and both minimal instances |

Consequence for the reproducer: under the fixed solver every row of the harness pins, so
`tracker/repro/nameloss/run.sh` is now a regression check, not a demonstration of the
race. To see the race, reinstate the deletion (`val keepDefs = false` in
`destructiveSub`) or check out the tree before this change.

## 8. Instruments added today (all inert unless `-Dermine.rowTrace` is set)

* `Subst.solve`: `in`/`ex`/`inpart`/`sat` records -- the constraint list as received (the
  one place a `Part`'s right-hand-side ORDER is still visible), the built partitions and
  the saturated set with provenance.
* `Constraints.incorporateAll`: `step` (one per dequeue, naming the branch) and `learn`
  (one per learnt partition, `new`/`seen`).
* `tracker/repro/nameloss/`: the replay harness (§3); the two-regime script (`regimes2.sh`)
  lives in the session scratchpad only.

Note for anyone re-reading the traces: the A `rows=3` module-level solve the brief quotes is
`withUnitCost` (`costPerFte`), not `labelled`; in regime A `labelled` is discharged entirely
by `trySolveOn`.
