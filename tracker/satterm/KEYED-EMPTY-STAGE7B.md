# Stage 7b — isolating the `-Dermine.emptyRow` regression on `gu05`, and the delivery that removes it

Date 2026-09-04.  Worktree `/home/dmitry/research/ermine/ermine-scala-wt-prof`, branch
`emptyrow-profiling` = `2411296` + Stage 7's uncommitted change.  Nothing is committed here.

Stage 7 is `tracker/satterm/KEYED-EMPTY-STAGE7.md`; its §B7-4 is the open finding this stage
closes: `incomplete/gu05_star_join_4dim_concrete_signature.e` costs ~1.05 s under the default
and ~2.0 s under `-Dermine.emptyRow=true`, while deriving FEWER partitions.

| tag | properties |
|---|---|
| `D` | none — the shipped default (`cut+label-early+resguard+splitkey+splitrow+resrow`) |
| `E` | `-Dermine.emptyRow=true` (`...+emptyrow`) — Stage 7 as shipped |
| `V` | `-Dermine.emptyRow=true` with §4's no-op guard — the delivery |

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/stage7b/`.

**Conclusion up front:** the regression is not overhead the branch adds — it is the branch's
intended effect.  `resolution`'s empty-row branch suppresses a mint, and on `gu05` that mint
is the vehicle by which the solver learns that 135 rows are `∅`; each of those discoveries
deletes ~43 partitions from the queues.  At **283 of the corpus's 293** firings the branch's
two conclusions are ALREADY in the system, so the suppression buys nothing at all.  The
delivery is a **no-op guard** on that branch: take it only when it adds a fact.  `gu05` goes
1.93 s → **1.09 s** (default 1.07 s), the `SplitEmpty` population and the whole kept-definition
mint reduction are kept, and every correctness gate is green.

## §0 Reproduction, in the worktree

`bin/ermine` runs verified by `ps` to use
`/home/dmitry/research/ermine/ermine-scala-wt-prof/core/target/scala-3.3.8/classes`.
One JVM at a time, machine idle; the figure is the program's own
`Importing module 'Incomplete.Gu05' (N seconds)`.

| run | `D` | `E` |
|---|---|---|
| r1 | 1.13 | 1.90 |
| r2 | 1.08 | 1.95 |
| r3 | 1.02 | 1.90 |
| **median** | **1.08** | **1.90** |

The regression reproduces on this build: **+0.82 s, 1.76×.**

## §1 The cause, from the trace

`-Dermine.rowTrace` on both sides, steps and `learn` records attributed to the solve segment
they precede (`stage7b/tr.py`, `sz.py`); only solves under `gu05...e` are counted.

**All of it is ONE solve** — `gu05...e(62:1)`, the `wideOrderLines` body, the module's single
expensive saturation.  Of the module's 26 solve segments, that one accounts for 1,192,526 of
the 1,192,526 extra queue-work units; every other segment has the same step count and the same
`Σ(incm+proc)` on both sides, to the unit.

| | `D` | `E` |
|---|---|---|
| dequeues (`step` records) in that solve | 1,278 | **2,366** |
| `Σ(incm+proc)` at dequeue — the O(&#124;Q&#124;)-per-step work | **298,463** | **1,490,989** (5.0×) |
| mean queue length at a `learn` dequeue | 230 | **663** |
| saturated set of that solve (`solve` record, `ps`) | **458** | **1,389** |
| ...of which derived | 400 | 1,311 |
| `Substitution` in the saturated set | 235 | **862** |
| `CommonSubexpression` | 61 | 188 |
| `SplitConcrete` | 53 | **163** |
| `Cancellation` | 31 | 85 |
| `Resolution` | 7 | 2 |
| `ResolutionEmpty` | — | 0 |

**And the reason the queue grows is that `makeEmpty` stops running.**  Per-branch net change
in `|incm|+|proc|` across the whole trace:

| branch | `D` n | `D` Σ&Delta;size | `E` n | `E` Σ&Delta;size |
|---|---|---|---|---|
| `learn` | 1,987 | **+7,997** | 3,026 | +2,172 |
| **`empty`** | **165** | **−7,037** (−42.7 each) | **33** | **−36** (−1.1 each) |
| `common` | 189 | −256 | 341 | −422 |
| `concrete` | 59 | −178 | 80 | −249 |
| `unify` | 44 | −69 | 46 | −77 |
| final size | | **457** | | **1,388** |

`makeEmpty` is the queue's only bulk-shrinking operation: it deletes every partition mentioning
the emptied variable and re-inserts the mentions with it erased, which collapses many of them
onto partitions already present.  Under `D` it fires 165 times and removes 7,037 partitions.
Under `E` the empty-row branch replaces the mint that would have become empty, so the carrier
never exists, `z <- ()` is never derived, `makeEmpty` fires 33 times and removes 36.

## §2 The five hypotheses, each measured

Instrumentation: a temporary `S7B` counter object in `Constraints.scala` behind
`-Dermine.s7bStats=true` (dumped by a shutdown hook, so the default path is a single
`Boolean` test), plus two temporary per-rule gates and a temporary `resMode` switch.  **All of
it is reverted; the final tree is Stage 7 plus the variant of §4 and nothing else.**

**H1 — per-emission `makeEmpty` passes.  REFUTED, and backwards.**  `gu05` fires
`SplitEmpty` **zero** times (Stage 7 §B6), so no `x <- ()` is emitted at all; and the flag
makes the compiler run FEWER `makeEmpty` passes, not more.  Counted directly
(`S7B makeEmpty`): `D` n=165, Σ&#124;incm&#124;+&#124;proc&#124; at entry = 45,041, partitions
deleted = 7,092; `E` n=33, ..., deleted = 36.  From the trace, `Σ(incm+proc)` over `empty`
steps is 44,905 under `D` and 535 under `E`.

**H2 — redundant emissions.  MEASURED, and it is the branch's normal case — but it is not the
cost.**  A census over the 19 modules Stage 7 §B6 lists as firing (per file,
`-Dermine.loadInSeries=true -Dermine.useInterface=false`, as B6):

| branch | firings | emitted | already in `proc ∪ incm` | BOTH conclusions already there |
|---|---|---|---|---|
| `SplitEmpty` | **65** (matches B6 exactly) | 130 | **0** | — |
| `ResolutionEmpty` | 293 | 586 | 570 | **283 (96.6 %)** |

The split branch never emits a fact the system already has.  The resolution branch almost
always does: at 283 of 293 firings BOTH conclusions are present, so the branch's whole effect
there is to suppress the mint.  On `gu05` it is 41 of 42 (and 744 of 747 in a non-serialized
load); on `np01`, 59 of 68.

**H3 — queue perturbation / `RHS.hashCode`.  REFUTED as a mechanism of its own.**
`Q.rhsLookup` does NOT scan the queue: `insert` hands it `req`, the equal-right-hand-side-hash
slice, and the slice is essentially always empty or a singleton — over a whole `gu05` run it
is entered 8,674 times (`D`) / 3,480 times (`E`) and scans **35 / 39 partitions in total**.
The queue counters do move (`Q.part` 55,007 → 86,002, `PQueue.contains` 26,423 → 57,120), but
in proportion to the number of dequeues and the size of the queues, which is §1's effect, not
a hashing effect: `insert` itself falls 11,940 → 7,798 and `heapify` is flat
(63,522 → 66,766 partitions re-hung).

**H4 — the environment scan.  REFUTED, quantitatively.**  `envEmptyRow` is forced 335 times
on a whole `gu05` run and walks **7,162 map entries in total** (≈ 21 per forcing); on `np01`,
71 forcings over 10,045 entries.  That is microseconds.  Stage 7 §A.2 predicted this would be
the cost and §B7-4's JFR already said it was not; the counter settles it.

**H5 — trajectory.  CONFIRMED, and it is the whole of it** — see §1.  It is not a *different*
solve that got slower: it is the SAME solve saturating to a set three times the size.

## §3 The mechanism, link by link

Every link below is measured on the two `gu05` traces, not inferred.

1. **The empty-row branch fires exactly where the default would mint and then immediately
   prove the mint EMPTY.**  The branch's own precondition is
   `myRow = Some(C)` with `C = all`, i.e. `v <- ((|F|))` is present with `F = all`.  The
   default's first conclusion is `v <- (z, all)`; cancellation of that against `v <- ((|F|))`
   has `fs = con1 -- conInt = ∅` and `xs = {z}`, so it derives **`z <- ()`**.
2. **That is where `D`'s `makeEmpty` passes come from.**  Of `D`'s 165 `empty` dequeues on
   `gu05`, **133 carry the `Cancellation` tag** (`E`: 1), and by variable provenance —
   the inference tag of the first record in the trace that mentions the emptied variable —
   **135 of the 165 are variables first introduced by a `Resolution` mint** (`E`: 3).  The
   other 30 (21 `INPUT`, 9 `PartitionEmpty`) are identical on both sides.

   | where the emptied variable was first seen | `D` | `E` |
   |---|---|---|
   | `Resolution` (a mint) | **135** | **3** |
   | `INPUT` | 21 | 21 |
   | `PartitionEmpty` | 9 | 9 |
   | total `makeEmpty` passes | **165** | **33** |

3. **`makeEmpty` is the queue's only bulk-shrinking operation.**  It partitions both queues on
   `ruleInvolves(v)`, drops the definitions of `v`, and re-inserts every mention with `v`
   erased — which collapses many of them onto partitions already present — and, through `aux`,
   turns any definition `v <- (a, b, …)` into `a <- ()`, `b <- ()`, so emptiness cascades.
   Counted: `D` removes **7,092** partitions this way (mean 43 per pass), `E` removes **36**.
4. **So the saturation runs on.**  With the pruning gone, the one expensive solve saturates to
   **1,389** partitions instead of 458, over **2,366** dequeues instead of 1,278, at a mean
   queue length of **663** instead of 230 — `Σ(incm+proc)` over all dequeues **298,463 →
   1,490,989, a factor of 5.0**.
5. **And 5.0× on that number is the 0.8 s.**  Fitting `t = R + c·Σ|Q|` to the two medians
   (1.08 s at 298,463 and 1.90 s at 1,490,989) gives `c ≈ 0.69 µs` per queue element visited
   and `R ≈ 0.88 s` of parsing, kind inference and free-variable collection — which is the
   split Stage 7's JFR reported independently (parser 27 %, free-variable collection 32.5 %).
   The model is two points through two unknowns, so it is a consistency check, not evidence on
   its own; what it does say is that the measured queue work and the measured time are the same
   size, and §4's variants confirm it by moving both together.

**In one sentence: the regression is not overhead the branch adds, it is the branch's intended
effect.**  The mint it suppresses was not waste — on `gu05` it is the vehicle by which the
solver discovers that 135 rows are `∅`, and each of those discoveries deletes ~43 partitions.


## §4 The variants, measured

All six configurations below were timed **in one class set** — the instrumented build, whose
counters are compile-time present and runtime off (one `Boolean` test), with two temporary
per-rule gates and a `resMode` switch — so nothing here is a build-to-build comparison.
One JVM at a time, `ps` polled for idleness before every run, three runs each.

| # | configuration | r1 | r2 | r3 | median | vs `D` |
|---|---|---|---|---|---|---|
| — | `D` the default | 1.10 | 1.06 | 1.08 | **1.08** | 1.00 |
| — | `E` Stage 7 as shipped | 1.88 | 1.98 | 1.94 | **1.94** | **1.80** |
| a | `E`, SPLIT branch only (resolution's disabled) | 1.03 | 1.08 | 1.06 | **1.06** | 0.98 |
| b | `E`, RESOLUTION branch only (split's disabled) | 1.94 | 2.17 | 1.97 | **1.97** | 1.82 |
| c | `E`, resolution branch emits NOTHING when both conclusions are redundant | 2.02 | 1.96 | 1.91 | **1.96** | 1.81 |
| **d** | **`E`, resolution branch falls through to the MINT when both are redundant** | 1.03 | 1.08 | 1.04 | **1.04** | **0.96** |

**(b) against (a) locates it: the whole regression is `resolution`'s branch**, on a module where
the split branch never fires.  **(c) against (d) is the decisive pair.**  Both see exactly the
same firings; (c) removes the redundant emissions and keeps the mint suppressed — and is
**as slow as `E`**; (d) keeps the emissions available but restores the mint — and is **as fast
as `D`**.  So it is not the emitting that costs, it is the not-minting.  That is the brief's V1
(a filter on redundant emissions) refuted as a repair, by direct measurement, and the reason
V2 (a batched `makeEmpty`) and V3 (a cached `envEmptyRow`) were not built: H1 and H4, the
hypotheses they answer, are the two the counters refuted outright.

**(d) is the delivery.**  Its emitted set is Stage 7's wherever the branch adds a fact, and the
shipped default's guarded mint wherever it does not — see §6 for what that means for the Lean.

### The delivery variant against `D` and `E`, one class set, the full bench

Timed with the delivery variant compiled and a single temporary `-Dermine.s7bNoGuard` switch
(since removed) selecting Stage 7's unguarded shape, so `D` / `E` / `V` are again one class set.
`Ai/HeadcountPlan` needs `Ai/Common.e` on the command line and was run with it and
`-Dermine.loadInSeries=true`.  Module seconds:

| instance | `D` | `E` (Stage 7) | `V` (variant) |
|---|---|---|---|
| **`incomplete/gu05`** ×3 | 1.07 / 1.04 / 1.09 | **1.93 / 1.96 / 1.90** | **0.99 / 1.11 / 1.09** |
| ResStar5 ×2 | 0.18 / 0.17 | 0.19 / 0.17 | 0.18 / 0.19 |
| ResStar6 ×2 | 0.44 / 0.47 | 0.50 / 0.45 | 0.52 / 0.45 |
| ResStar7 ×2 | 1.88 / 1.87 | 1.96 / 1.78 | 1.84 / 1.81 |
| ResStar8 ×2 | 11.74 / 11.83 | 12.22 / 11.76 | 11.87 / 11.84 |
| `incomplete/np01` ×2 | 0.44 / 0.42 | 0.51 / 0.50 | 0.53 / 0.47 |
| `Accumulate` ×2 | 0.11 / 0.10 | 0.10 / 0.12 | 0.13 / 0.11 |
| `Ai/HeadcountPlan` ×2 | 0.86 / 0.84 | 0.81 / 0.83 | 0.84 / 0.82 |

`gu05` is fixed.  Everything else is where Stage 7 left it, including **`np01`'s +0.06 s, which
the variant does NOT remove** — and should not: `np01` is the corpus's heaviest `SplitEmpty`
user (14 firings) and the variant keeps that branch untouched.  Stage 7 §B4 put that movement
inside `np01`'s own spread and this run agrees (`V` 0.53 / 0.47 straddles `E`'s 0.51 / 0.50).

### And the trajectory is `D`'s again

The same trace analysis as §1, on the delivery build:

| `gu05`, the one expensive solve | `D` | `E` | `V` |
|---|---|---|---|
| saturated set | **458** | 1,389 | **458** |
| derived | 400 | 1,311 | 400 |
| dequeues | 1,278 | 2,366 | **1,276** |
| `Σ(incm+proc)` | 298,463 | 1,490,989 | **298,755** (+0.1 %) |
| `makeEmpty` passes | 135 | 3 | **133** |


## §5 What the variant costs in population, stated plainly

`keptdef-sweep.sh`'s PER-FILE mode (`-XX:ActiveProcessorCount=2 -Xmx1500m
-Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=…`, `Ai/Common.e`
first for the `Ai` group — the same invocation the sweep uses), restricted to the 19 modules
Stage 7 §B6 lists as firing, on the variant.  `D` and `E` are Stage 7 §B6's own per-module
figures.  Whole-trace partition counts, and the kept-definition mints:

| module | kept-def MINTS `D` → `E` → **`V`** | `SplitEmpty` parts `V` | `ResolutionEmpty` parts `E` → **`V`** | `Resolution` `D` → `E` → **`V`** |
|---|---|---|---|---|
| `Ai/BatteryCycling` | 7 → 3 → **3** | 8 | 8 → **0** | 52 → 27 → 48 |
| `Ai/ClinicalTrial` | 4 → 2 → **2** | 6 | 5 → **0** | 31 → 22 → 37 |
| `Ai/FiscalCalendar` | 4 → 1 → **1** | 4 | 5 → **0** | 56 → 15 → 24 |
| `Ai/GridTelemetry` | 9 → 5 → **5** | 8 | 21 → **0** | 81 → 43 → 81 |
| `Ai/HeadcountPlan` | 9 → 4 → **4** | 10 | 26 → **0** | 113 → 42 → 84 |
| `Ai/IncidentSeverity` | 10 → 4 → **4** | 10 | 29 → **0** | 98 → 48 → 112 |
| `Ai/RevenueByPeriod` | 9 → 5 → **5** | 10 | 21 → **0** | 68 → 44 → 86 |
| `Ai/SalesByRegion` | 8 → 3 → **3** | 8 | 11 → **0** | 59 → 33 → 57 |
| `Ai/SupplyChainInventory` | 9 → 4 → **4** | 10 | 30 → **0** | 94 → 49 → 105 |
| `Ai/TelescopeTime` | 8 → 4 → **5** | 10 | 18 → **0** | 63 → 40 → 69 |
| `GridExample` | 2 → 0 → **0** | 4 | 3 → **0** | 12 → 6 → 12 |
| `SoftRelation` | 3 → 3 → **3** | 0 | 1 → **0** | 6 → 3 → 6 |
| `incomplete/.probeC` | 5 → 5 → **5** | 0 | 54 → **0** | 156 → 63 → 156 |
| `incomplete/RevenueShare` | 3 → 1 → **1** | 2 | 4 → **0** | 47 → 38 → 47 |
| `incomplete/RunCalibration` | 1 → 0 → **0** | 2 | 2 → **0** | 18 → 15 → 18 |
| **`incomplete/gu05`** | 6 → 6 → **6** | 0 | 44 → **1** | 125 → 31 → 116 |
| `incomplete/gu08` | 6 → 3 → **3** | 6 | 4 → **0** | 65 → 25 → 37 |
| `incomplete/np01` | 32 → 16 → **16** | 28 | 75 → **8** | 345 → 158 → 399 |
| `incomplete/np05` | 8 → 2 → **2** | 6 | 5 → **0** | 93 → 28 → 46 |
| **total over the 19** | **143 → 71 → 72** | **132** (`E`: 130 corpus-wide) | **366 → 9** | |

Read plainly:

* **The kept-definition mint reduction — Stage 7's headline, 154 → 82 corpus-wide — is kept
  in full.**  Over these 19 modules it is 143 → 71 under Stage 7 and **143 → 72** under the
  variant; the one difference is `Ai/TelescopeTime` (4 → 5).  That population belongs to
  the SPLIT branch, which the variant does not touch.
* **`SplitEmpty` is untouched**: 132 partitions against Stage 7's corpus-wide 130 (the 2 are
  trajectory, from the resolution branch minting again).
* **`ResolutionEmpty` all but disappears: 366 → 9.**  That is the price, and it is exactly the
  283-of-293 no-op population: the branch now fires only where it adds a fact (once in `gu05`,
  eight partitions' worth in `np01`).  With it goes most of Stage 7's `Resolution`-conclusion
  reduction (1,644 → 792 corpus-wide); the variant's per-module `Resolution` counts sit near
  the default's, sometimes below it (`np05` 93 → 46, `gu08` 65 → 37, `FiscalCalendar` 56 → 24)
  and sometimes above (`np01` 345 → 399, `IncidentSeverity` 98 → 112) — trajectory, not a rule change.

So the honest summary of the trade is: **the variant keeps all of the split branch's value and
almost none of the resolution branch's, and buys back the 1.8× on `gu05` with that.**  Stage 7
measured the resolution branch's value as a count of derived conclusions; §1–§3 show that on
`gu05` those conclusions were not the point — the mints they replaced were doing the pruning.

## §6 The Lean

**No Lean was changed and none is needed, but the variant does NOT emit a subset of Stage 7's
facts, and that is said here rather than glossed.**

At a firing the variant now takes one of two steps, chosen by whether the reuse's conclusions
are already in the system:

* **it adds a fact** → exactly Stage 7's step, `Set(x <- ((|bots|)), y <- ((|tops|)))`, which is
  `KeyedEmptyScala.resEmptyReuse_compose` / `resEmpty_two_steps`, adequate by
  `scalaEmptyRes_run` and bounded by `scalaEmptyRes_bounded`;
* **it adds nothing** → exactly the SHIPPED DEFAULT's guarded mint,
  `Set(v <- (z, all), x <- (z, bots), y <- (z, tops))`, which is `ResGuard`'s `GResStep.mint`
  (and `KeyedRow.K2ResStep.mint_toGRes` for the keyed reading).  `z` is the id `resolution`
  already drew before the match, so the `Supply` sequence is unchanged in both arms — the
  invariant `resGuard` was written to preserve.

Both arms are steps of relations the Lean already has, so every partition the variant emits is
entailed and the bound arguments still apply arm by arm.  What is **not** available off the
shelf is a single relation whose steps are "this arm or that arm depending on membership": the
choice is made on the compiler's queues, and `EmptyRowSpec` says nothing about it.  Per the
brief this is reported, not patched: **if a combined bound is wanted, that is a new Lean
obligation and a Stage 8 item, not something this stage invented a theorem for.**

The split branch is untouched, so `KeyedEmptyScala.splitEmpty_two_steps` / `scalaEmptySplit_run`
apply to it verbatim.

`tracker/lean/` is byte-identical to Stage 7 (`Rowpartition/KeyedEmptyScala.lean` and the
`Rowpartition.lean` / `README.md` edits are Stage 7's, unmodified).

## §7 Correctness gates on the winning variant

All four on the DELIVERY build (no instrumentation, no temporary switch), `V` =
`-Dermine.emptyRow=true`.

| gate | result |
|---|---|
| **`G7` seed, 100 bases** (`tracker/repro/satterm/run.sh sweep json:…/G7.json 0 99`) | `D`: SOLVED=100, `DRAWN 1:x100`.  `V`: SOLVED=100, **`DRAWN 0:x100`** — the Stage 7 result, unchanged, because the split branch is unguarded |
| **`corpus-run.sh --batch`, both corpora, `D` vs `V`** | `verdicts.txt` **byte-identical** on both (66 and 34 files); `shouldfail/` **40/40 REJECTED on both sides**; 0 of 34 files differ at all; 4 of 66 differ in MESSAGE only |
| ...the 4 message differences, re-run PER FILE ×2 on both sides | `der01`, `der02`, `der06`, `der07`: **all four identical**, `D` and `V`, both runs — the documented `--batch` session-id clause drift (Stage 7 §B7-2, `TICKET-editor-and-solver-followups.md` item 4), not the flag |
| **`keptdef-sweep.sh` per file, the 19 firing modules** | §5 — `SplitEmpty` 132 (Stage 7: 130 corpus-wide), kept-definition mints 143 → 72 (Stage 7: 71), `ResolutionEmpty` **366 → 9**, which is the guard doing what it says |
| **`core/test`** | `D` 910/911, `V` 910/911, the same single known failure `Constraints.disjunction sound: Gave up after only 0 passed tests` |

One flake, recorded because it happened: the FIRST `core/test` run on the default also failed
`Interface round-trip.new-pipeline cold write, fresh warm read, same answers` ("Expected
Some(Interface) but got Some(Full)").  Re-run on the same classes it passed, and the variant's
run passed it too; it is a file-system-timing property, unrelated to this change.

## §8 The variant, in full

`git diff` of the variant ALONE — i.e. against the Stage 7 tree, not against `2411296`.  The
same file is at `/home/dmitry/.claude/jobs/880c725d/tmp/stage7b-variant.diff`.

```diff
--- a/core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala
+++ b/core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala
@@ -744,7 +744,13 @@
    *  a mint would name denotes `∅`, so the two conclusions the `resGuard` reuse emits,
    *  `x <- (z, D \ C)` and `y <- (z, C \ D)`, become the bare concrete `x <- ((|D \ C|))`
    *  and `y <- ((|C \ D|))`, which is what this branch emits.  Behaviour-neutral as a tag,
-   *  as above. */
+   *  as above.
+   *
+   *  STAGE 7b (`tracker/satterm/KEYED-EMPTY-STAGE7B.md`) puts a NO-OP GUARD in front of this
+   *  branch: it is taken only when at least one of the two conclusions is not already in the
+   *  system.  See the guard's own note at `def resolution`; the tag is emitted only where the
+   *  branch is actually taken, so a `SplitEmpty`/`ResolutionEmpty` census still counts
+   *  firings and not attempts. */
   case object ResolutionEmpty      extends Inference
 
   /** Which generative rules are allowed to mint fresh variables.
@@ -1021,6 +1027,20 @@
      * `def resolution`.  Scope: nothing here is about ill-typed input, and `unify` -- the
      * other deletion that moves a fact into the `SubstEnv` -- is still unmodelled.
      *
+     * STAGE 7b (`tracker/satterm/KEYED-EMPTY-STAGE7B.md`) -- the one gate Stage 7 failed, and
+     * its repair.  With the branch taken UNCONDITIONALLY, `incomplete/gu05` cost 1.9x
+     * (1.08 s -> 1.93 s).  Isolated: at 283 of the corpus's 293 `resolution` firings BOTH
+     * conclusions are already in the system, so the branch's whole effect there is to
+     * SUPPRESS the mint -- and on `gu05` that mint is not waste.  `v <- (z, all)` cancels
+     * against the `v <- ((|F|))` the lookup itself requires, giving `z <- ()`; `makeEmpty z`
+     * is the queue's only bulk-shrinking operation.  135 of the default's 165 `makeEmpty`
+     * passes on `gu05` are on such a mint, and they delete 7,092 partitions between them; with
+     * the branch on, 3 are, and the same saturation runs to 1,389 partitions instead of 458.
+     * So `resolution`'s branch carries a guard: take it only when it adds a fact.  The SPLIT
+     * branch has no guard and needs none -- it emits `x <- ()`, which drives `makeEmpty`
+     * itself, and its emission is measured never redundant (0 of 130 over the 19 firing
+     * modules).
+     *
      * DEFAULT OFF pending the adoption gates in `tracker/satterm/KEYED-EMPTY-STAGE7.md`.
      * `-Dermine.emptyRow=true` enables it. */
     val emptyRow: Boolean = System.getProperty("ermine.emptyRow", "false") == "true"
@@ -1298,6 +1318,13 @@
    * `v <- (u, concr)`, cancellation against `v <- ((|C|))` derives `u <- ()`, and
    * `makeEmpty u`'s `aux` emits these same partitions.  The rule does in every order what
    * the mint plus cancellation plus `makeEmpty` do in some. */
+  /* STAGE 7b (`tracker/satterm/KEYED-EMPTY-STAGE7B.md`).  Unlike `resolution`'s empty-row
+   * branch, the one below carries NO no-op guard, and needs none.  Two measured reasons.
+   * (i) What it emits is `x <- ()`, which `incorporateAll` dequeues into `makeEmpty` -- so it
+   * DRIVES the bulk deletion that Stage 7b found the resolution branch was suppressing,
+   * rather than skipping it.  (ii) Its emission is never redundant: over the 19 modules of
+   * the example corpus that fire it, 0 of 130 emitted `x <- ()` name a variable already bound
+   * empty in the `SubstEnv` or already queued empty (§2 of that report). */
   def splitConcrete(v: TypeVar, abstr: Set[TypeVar], concr: Fields, rhss: RHS => Option[TypeVar],
                     resolvent: Fields => Option[TypeVar] = _ => none,
                     concRow: Fields => Option[TypeVar] = _ => none,
@@ -1347,6 +1374,11 @@
    * `learnPartitions` call. */
   private val noConcRow: Fields => Option[TypeVar] = _ => none
 
+  /* The no-op test that is passed when `-Dermine.emptyRow` is off: one shared constant, so
+   * the default allocates no closure per `learnPartitions` call.  See the STAGE 7b note at
+   * `def resolution`. */
+  private val noKnown: Partition => Boolean = _ => false
+
   /* When the above special case rules haven't fired, we need to collect
    * up new rules based on the rule we're about to add, and the other
    * rules that have been incorporated already.
@@ -1462,13 +1494,23 @@
       }
       val emptyRow: Fields => Option[TypeVar] =
         if (GenRules.emptyRow) findEmptyRow else noConcRow
+      /* Stage 7b's no-op guard (see `def resolution`): "is this conclusion already in the
+       * system?".  `PQueue.contains` is a keyed finger-tree split, not a scan, and this is
+       * consulted only at a firing of the empty-row branch -- twice -- so it costs two
+       * O(log n) splits per firing and nothing at all with the flag off, where the shared
+       * `noKnown` constant is passed instead.  Like `concRows` it ranges over `proc ++ incm`
+       * and NOT the current batch `s`; a conclusion derived earlier in this same batch
+       * therefore reads as "new", which errs towards the mint, i.e. towards the shipped
+       * default. */
+      val known: Partition => Boolean =
+        if (GenRules.emptyRow) (p => (proc contains p) || (incm contains p)) else noKnown
       proc.foldLeft[Set[Partition]](
            splitConcrete(v, rhs1.abstr, rhs1.concr, findRHS(incm, proc, Set()),
                          findResolvent(Set()), concRow, emptyRow)
          ){
            case (s, Partition(u, rhs2, _)) =>
              if(u == v) {
-               val rps = resolution(v, rhs1, rhs2, findResolvent(s), concRow, emptyRow)
+               val rps = resolution(v, rhs1, rhs2, findResolvent(s), concRow, emptyRow, known)
                val cps = cancellation(v, rhs1, rhs2)
                val dps = if(!GenRules.disjRule) Nil else proc.toList.flatMap {
                  case Partition(w, rhs3, _) if w != v => disjunction(rhs3, rhs1, rhs2) ++ disjunction(rhs3, rhs2, rhs1)
@@ -1758,7 +1800,8 @@
   def resolution(v: TypeVar, rhs1: RHS, rhs2: RHS,
                  resolvent: Fields => Option[TypeVar] = _ => none,
                  concRow: Fields => Option[TypeVar] = _ => none,
-                 emptyRow: Fields => Option[TypeVar] = _ => none)(implicit su: Supply): Set[Partition] =
+                 emptyRow: Fields => Option[TypeVar] = _ => none,
+                 known: Partition => Boolean = _ => false)(implicit su: Supply): Set[Partition] =
     if (!GenRules.resolves) Set() else (rhs1, rhs2) match {
     case (RHS(Single(x), concr1), RHS(Single(y), concr2)) =>
       val z = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))
@@ -1784,18 +1827,31 @@
                 Set(Partition(x, RHS(Set(w), bots), ResolutionRow),
                     Partition(y, RHS(Set(w), tops), ResolutionRow))
               case None =>
+                def mint: Set[Partition] =
+                  Set(Partition(v, RHS(Set(z), all), Resolution),
+                      Partition(x, RHS(Set(z), bots), Resolution),
+                      Partition(y, RHS(Set(z), tops), Resolution))
                 (if (GenRules.emptyRow) emptyRow(all) else none) match {
                   case Some(_) =>
                     // EMPTY-ROW REUSE (Stage 7): `v <- ((|F|))` with `F = all`, so the
                     // resolvent row is `∅` and some `z <- ()` is known.  The two conclusions
                     // of the reuse with `z` denoting `∅` are these bare concrete ones; the
                     // carrier is not mentioned, and nothing is minted.
-                    Set(Partition(x, RHSConcr(bots), ResolutionEmpty),
-                        Partition(y, RHSConcr(tops), ResolutionEmpty))
-                  case None =>
-                    Set(Partition(v, RHS(Set(z), all), Resolution),
-                        Partition(x, RHS(Set(z), bots), Resolution),
-                        Partition(y, RHS(Set(z), tops), Resolution))
+                    val bot = Partition(x, RHSConcr(bots), ResolutionEmpty)
+                    val top = Partition(y, RHSConcr(tops), ResolutionEmpty)
+                    // THE NO-OP GUARD (Stage 7b, `tracker/satterm/KEYED-EMPTY-STAGE7B.md`).
+                    // If BOTH conclusions are already in the system the reuse adds nothing --
+                    // and all it does is suppress a mint that the default would immediately
+                    // have proved EMPTY (`v <- (z, all)` against `v <- ((|F|))` cancels to
+                    // `z <- ()`), whose `makeEmpty` is the queue's only bulk-shrinking
+                    // operation and, through `makeEmpty`'s `aux`, the way the solver
+                    // discovers that other variables are `∅` too.  Measured: on
+                    // `incomplete/gu05` that suppression costs 1.9x (458 -> 1,389 partitions
+                    // in one saturation).  So take the reuse only when it actually adds a
+                    // fact, and otherwise take the shipped guarded mint.  283 of the corpus's
+                    // 293 firings are this case; the 10 that are not keep the reuse.
+                    if (known(bot) && known(top)) mint else Set(bot, top)
+                  case None => mint
                 }
             }
         }
```

## §9 What is left unexplained

1. **Why the resolution branch's conclusions are already present at 96.6 % of firings is not
   fully explained.**  It is consistent with the branch's own precondition (`v <- ((|F|))` with
   `F = all` means `x` and `y` are already pinned to concrete rows, which `makeConcrete` may
   already have derived by cancellation), but the census counts the outcome; it does not prove
   the derivation that gets there.  Ten firings are NOT redundant, and nothing here says what
   distinguishes them.
2. **The 5.0× / 1.8× gap.**  `Σ(incm+proc)` grows 5.0× while module time grows 1.8×.  The
   two-point fit in §3-5 attributes the difference to a ~0.9 s fixed cost outside the row
   solver, which agrees with Stage 7's JFR split, but a fit through two points is a
   consistency check and not a measurement of `R`.
3. **`np01`'s +0.06 s survives the variant** and is attributed to the split branch by
   elimination (the variant keeps only that branch's firings there), not by an isolating
   experiment on `np01` itself.
4. **`gu05`'s firing count depends on how the module is loaded**: 42 empty-row firings under
   `-Dermine.loadInSeries=true`, 747 without it.  Nothing downstream of this stage depends on
   which figure is used — the redundancy rate is ≥ 97.6 % either way, and the timing runs are
   all in the non-serialized mode the regression was reported in — but the sensitivity itself
   is unexplained and is the same order-sensitivity `keptdef-sweep.sh`'s header warns about.
5. **No combined Lean bound for the guarded rule** (§6).

## §10 Recommendation

Stage 7's own recommendation was "not something to make a default", and the reason was this
regression.  With the guard, the reason is gone: `gu05` is at the default's cost, every gate is
green, and the population Stage 7 was actually after — the kept-definition mints, 154 → 82 — is
kept in full.  What the guard gives up is the resolution branch's conclusion-count reduction,
which §1–§3 show was not a saving on the module that mattered.

**The flag is still DEFAULT OFF and nothing was committed.**  What this stage delivers is the
shape in which `-Dermine.emptyRow` could be proposed for default, plus the §9 items and the
Stage 8 Lean obligation of §6 as the remaining work.
