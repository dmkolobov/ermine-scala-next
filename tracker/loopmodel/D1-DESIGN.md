# D1 — ENGINEERED termination and order-robustness: the design

Stage D1 of `tracker/LOOP-MODEL-PLAN.md`, brief `tracker/loopmodel/briefs/brief-D1.md`.
**Part A only** (Lean and measurement; no Scala, no sbt, no commits).  Part B — the flagged
change to `Constraints.scala` — starts only on the orchestrator's go, and §6 is its
specification.

## 0. Why this stage exists

Eight L5 rounds looked for a termination proof of `Constraints.incorporateAll` and did not
find one.  What they found instead (`L5-TERMINATION.md` §R8.6, round-8 review Y-19) is that
both factors of the only bound the stage has — `chainBound n m D R = n · D · (2^m · R)^D` —
are unbounded on the evidence: `D` (chain depth) reaches 5 and `R` (draws at one dequeue key)
reaches 20 on inputs a quarter of GU05's size, and neither has stopped climbing.  So
termination is **engineered**, in two pieces that have to arrive together:

1. a **draw BUDGET** that makes every solve stop, whose exhaustion is a REJECTION with a
   diagnostic and never an acceptance (§1–§2, proved in `Loop/Budget.lean`);
2. an **ORDER-ROBUSTNESS** change, because a budget alone would make `GU05.json` type-check or
   fail *by id base* — it costs 743 draws at one base and 47,000–81,481 at others, a
   like-for-like 1,210× in wall clock, decided by nothing but `PQueue`'s `hashCode`-keyed
   priority (`L5-TERMINATION.md` §R8.0a; `PERF-ROADMAP.md` P10) — and *type-checks by id base*
   is worse than slow (§3–§5, measured with `Loop/Policy.lean`).

The design rule from Stage 7b governs both: a guard may replace a mint by a NAME for the same
row, never by SILENCE (`tracker/satterm/KEYED-EMPTY-STAGE7B.md`).  Neither piece here
suppresses a mint: the budget stops the whole solve and says so, and a dequeue policy changes
only WHICH partition is looked at next.

## 1. The budget, specified

**Unit: fresh ids drawn by the loop, per solve** — `Sup.drawn` at the end minus `Sup.drawn` at
the loop's first dequeue (the `drawn - drawn0` of the `--depth` and `--policy` instruments).
Not dequeues.  This is not a convenience:

* every termination theorem the stage has is about `Sup.drawn`.  `VocFix.terminates_of_drawsAtMost`
  says in so many words that a solve which draws boundedly many ids terminates, so a DRAW cap is
  the quantity the existing proof converts into termination;
* no theorem bounds dequeues per draw — that is the open problem `L5-TERMINATION.md` §R8.6b
  names — so a DEQUEUE cap would be a second engineering decision with no proof behind it.

**Where it is checked.**  At the two minting sites, which under the shipped flags
(`genRules=cut`, `disjunction` off) are the only two rules that call `Supply.fresh`:
`splitConcrete` (at most one draw per dequeue, the initial value of `learnPartitions`' fold) and
`resolution` (at most one per processed partition, taken BEFORE its guards, so a reuse costs an
id too).  `Loop/Draws.lean`'s `learnPartitions_drawn` is that inventory:
`su'.drawn ≤ su.drawn + 1 + proc.elems.length`.

The MODEL checks one dequeue coarser — `stepBud` tests the budget before the dequeue and dies
with the state it was given — and the difference is stated rather than hidden: the model may
overshoot the budget by one step's draws, at most `1 + proc.size` by the theorem above, before
it stops.  Nothing in §2 depends on which of the two is used; the compiler's own check will sit
in a counting wrapper around `fresh`, where it fires on the draw itself.

**What it raises.**  A `Death` — the same class `ensureSuperset` and `makeEmpty` raise, so it
travels the existing rejection path — carrying the site, the loop's draw count and the budget:

```
Row solver budget exhausted at <site>: the loop drew <n> fresh row variables,
budget <b> (-Dermine.solveBudget); the row constraints are too large or the solver
is not converging
```

**The value.**  Measured, over the whole eight-group corpus (`tmp/D1/depth-shipped.tsv.gz`,
2,301,195 solve segments, every one replayed):

| quantity | value |
|---|---|
| corpus MAXIMUM loop draws in one solve | **149** (`incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)`, segment 54234, 281 dequeues) |
| corpus total loop draws | 1,845 |
| corpus total dequeues | 69,207 |
| solves that draw at all | 343 of 2,301,195 |
| `GU05.json`, best measured base | 743 draws (base 2), 221 ms on the compiler |
| `GU05.json`, worst measured base that COMPLETES | **81,481** draws (base 6), 371,199 ms |
| `GU05.json`, base 4 | drew past the harness's 100,000-id window; no verdict |

PROPOSED BUDGET: **`ermine.solveBudget = 20000`** fresh ids per solve, adopted together with
the order policy of §5.

* margin over the corpus maximum: **134×** (20,000 / 149);
* margin over the worst base of the worst known input AFTER the order fix (§5e): `smallcanon`
  draws 306 on `GU05` at every one of 25 bases and at most 328 anywhere in the corpus, so the
  budget clears the worst measured solve by **61x** — and clears it at EVERY id base, which is
  the property a budget needs in order not to turn a type error into a lottery;
* implied wall clock: GU05 spends 267 s on 47,317 draws (133 s unloaded), i.e. ≈ 5.6 ms/draw at
  the pathological end, so 20,000 draws is of the order of a minute — long enough that no
  healthy compile is near it, short enough that the failure is a message and not a hang;
* the budget is **useless without §5**: at 20,000, GU05 under the SHIPPED order is accepted at
  the fast bases and rejected at the slow ones.  That is the outcome the brief calls worse than
  slow, and it is why the two ship together or not at all.

## 2. The budget in Lean (`Rowpartition/Loop/Budget.lean`)

Nothing existing is touched: `step`, `run` and `PQueue.dequeue` are unchanged, `stepBud` and
`runBud` are new, and `run` is what every earlier theorem is still about.  The two theorems the
brief asks for, VERBATIM (review T-6 — an earlier version of this file said they were quoted and
then paraphrased them):

```lean
theorem budget_terminates {b : Nat} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    TerminatesB s.su.drawn b s

theorem budget_never_accepts {d0 b : Nat} : ∀ (n : Nat) {s s' : State},
    runBud d0 b s n = .solved s' → run s n = .solved s'
```

and the three that go with them:

```lean
theorem stepBud_died_sys {d0 b : Nat} {s s' : State} {m : String}
    (h : stepBud d0 b s = .died m s') : sys s' = sys s

theorem budget_exhausted_rejects {d0 b : Nat} {s : State} (h : d0 + b < s.su.drawn) (n : Nat) :
    runBud d0 b s (n + 1) = .rejected (budgetMsg s.site d0 b s.su.drawn) s

theorem runBud_eq_run {d0 b : Nat} : ∀ (n : Nat) (s : State),
    (∀ t, Reaches s t → t.su.drawn ≤ d0 + b) → runBud d0 b s n = run s n
```

In prose, their shapes are

* `budget_terminates` — under exactly the hypotheses of `VocFix.terminates_of_drawsAtMost`,
  `TerminatesB s.su.drawn b s` for EVERY budget `b`.  The proof is a two-case split and the
  first case IS `terminates_of_drawsAtMost`: either no reachable state exceeds the cap, so the
  loop draws boundedly many ids and therefore terminates, and the budgeted loop follows it; or
  some reachable state does, and the check fires at or before it.  What this does NOT give is an
  a-priori FUEL number — converting a draw budget into a dequeue bound needs the missing
  dequeues-per-draw bound — and `TerminatesB` is the same existential `Order.Terminates` is;
* `budget_never_accepts` — whatever the budgeted loop ACCEPTS, the shipped loop accepts, in the
  same number of dequeues and at the same final state.  So exhaustion can only turn an
  acceptance into a rejection, never the other way round, and an accepted solve publishes the
  substitution the shipped loop published.  With `stepBud_died_sys` (`sys s' = sys s` at every
  death, the budget's included — `Refine.step_died_sys`'s shape) this is the pair the brief
  asks for.

And `runBud_eq_run`: a run no state of which exceeds the cap is `run`, answer and final state.
That is why the L2 corpus differential is untouched — with the budget off the executable does
not call `runBud` at all, and with a budget set the run is `run` unless the cap is reached.

## 3. The order policies (`Rowpartition/Loop/Policy.lean`)

`Loop/Queue.lean` reproduces `Q.pop` exactly — the deepest variable in the reverse-topological
order, then the smallest `rhs.hashCode` as a signed Java `int`, then the most recently inserted
— which is what lets the model try other orders with no Scala change at all.

`stepP` is `step` with one line replaced (the dequeue call) and `stepP_shipped : stepP .shipped a s = step s`
is `rfl`, so the default IS the shipped loop definitionally, not up to a lemma.  This is the
shape S2's `Loop/Decide.lean` `stepS` has, and for the same reason.

| policy | rule |
|---|---|
| `shipped` | `Q.pop`, unchanged; the DEFAULT everywhere |
| `concfirst` | partitions whose right-hand side carries a CONCRETE part first; ties by the shipped order |
| `smallrhs` | fewest right-hand-side parts first (`|abstr| + (conc ? 1 : 0)`, the partition's arity); ties by the shipped order |
| `fifo` | earliest ARRIVAL BATCH first: input partitions are batch 0, a partition derived at dequeue `k` is batch `k`; within a batch, the shipped order.  A true per-insertion FIFO would need an arrival counter on `Partition`, which neither `LPart` nor the Scala carries |
| `canon` | the shipped order with EVERY ID REPLACED BY ITS FIRST-OCCURRENCE RANK: the reverse-topological sort is recomputed over rank-ordered nodes and rank-ordered edge sets, and `rhs.hashCode` is replaced by the sorted ranks of the right-hand side's variables and the sorted indices of its labels |
| `smallcanon` | `smallrhs`'s ARITY as the primary key and `canon`'s id order as the whole of the tie-break — added after the first four were measured, because the measurement said what the combination had to be (§5) |

**The rank IS the id order**, which is why `canon` needs no rank table, in the model or in the
compiler: every input variable of a solve precedes every mint (`SupOk`/`SupFresh`), and
`Supply.fresh` is monotone — inside a block it returns `lo` and increments, and at a boundary it
returns the global counter `blk`, which is past every id ever issued.  So `rank v < rank w ↔ v < w`,
and `canon` compares ids by ORDER.  It is base-independent because a change of base shifts every id
of the solve by the same amount, which is exactly what the 25-base sweep varies.  The contrast with
the shipped key is the point: `rhs.hashCode` is the case-class hash of a `Set[TypeVar]`, a Murmur
mix that is a pseudo-random function of exactly those ids, so the shipped order moves wholesale with
the base while an id ORDER does not move at all.

## 4. The measurements

Instrument: `looptrace ... --policy=<name> [--budget=<n>]`, on a `json:` seed and under
`--replay` over a corpus trace, printing one `pol` line per solve — verdict, dequeues, `drawn`,
`drawn0`.  Cross-check on the whole `boot` group: at `--policy=shipped` the `pol` lines'
`steps`/`drawn`/`drawn0` are IDENTICAL to `--depth`'s over all 54,199 segments, which is the
runtime witness for `stepP_shipped`.

Corpus: round 8's eight-group traces, `tmp/L5r8/{traces,inc}/*.tsv.gz`, 2,301,195 solve
segments (`gzip -t` clean).  Seeds: `slow/GU05.json` and `slow/GU05MIN.json` at 25 id bases, and
the tracked seeds at 10.

## 5. The policy table, and the winner

Every figure below is reproducible with the commands in `tmp/D1/COMMANDS.md`.  A SIXTH policy,
`smallCanon`, was added after the first four were measured, because the measurement said what
the combination had to be: `smallRhs` collapses `GU05`'s COST and `canon` collapses its SPREAD,
and neither alone does both.  `smallCanon` is `smallRhs`'s arity as the primary key with
`canon`'s id order as the whole of the tie-break.

### 5a The corpus: all eight groups, 2,301,195 solve segments, per policy

`looptrace --replay <group> --policy=<p> --fuel=3000`, one `pol` line per solve.

| policy | segments | dequeues | vs shipped | loop draws | vs shipped | solves worse > 2x (deq) | (draws) | max draws | max deq | verdict diffs |
|---|---|---|---|---|---|---|---|---|---|---|
| `shipped` | 2,301,195 | 69,207 | — | 1,845 | — | — | — | 149 | 281 | — |
| `concfirst` | *see 5d — the census does not finish; on the 1,460,524 segments it did cover (26 of 41 groups, `Ai` cut at 60,477 of 83,942) it spends 44,699 dequeues and 2,864 draws against `shipped`'s 41,009 and 884 on the same segments: **+9.0 %** and **+224 %**, with 38 solves worse by > 2x and one solve hitting the 500-dequeue fuel* | | | | | | | | | |
| `smallrhs` | 2,301,195 | 69,650 | **+0.64 %** | 3,872 | +110 % | 1 | 16 | 1,612 | 1,108 | **0** |
| `fifo` | 2,301,188 | 73,896 | +6.8 %¹ | 4,934 | +167 %¹ | 10 | 109 | 316 | 294 | **0** |
| `canon` | 2,301,188 | 69,953 | +1.1 %¹ | 1,628 | −12 %¹ | 2 | 6 | **93** | **211** | **0** |
| **`smallcanon`** | 2,301,195 | **68,940** | **−0.39 %** | 2,485 | +35 % | **0** | 21 | 328 | 381 | **0** |

¹ **These two percentages compare against the FULL shipped totals and are therefore wrong**
(review T-4).  On the population `canon` and `fifo` actually cover, `shipped` spends **68,926**
dequeues and **1,696** loop draws, so the like-for-like figures are `canon` **+1.49 % dequeues /
−4.0 % draws** and `fifo` **+7.21 % / +191 %**.  `smallrhs`'s and `smallcanon`'s percentages cover
the full 2,301,195 and are sound as printed.

**None of the five policies whose census FINISHED changes a single verdict** over 2,301,188–2,301,195
solves each — which is the empirical form of "every policy dequeues the same partitions" (§5f is the
theorem).  `concfirst` is the exception and the sixth: it turns
`gu05_star_join_4dim_concrete_signature#54234` from SOLVED into FUEL (review T-5).  Two caveats on
its row, both of which make it incomparable rather than merely worse: its census ran at
**`--fuel=500`** where the other five ran at `--fuel=3000` (its `max deq` of 500 is the cap, not a
measurement), and it covers 1,460,524 of the 2,301,195 segments.  A further caveat that applies to
ALL six rows: `replayPolicyOne` (`Loop/Main.lean`) deliberately does not apply the early label check,
so "verdict" here is the LOOP's verdict, not the whole of `Subst.solve`'s (review T-14.5).  `canon` and `fifo` are SEVEN
segments short of the full count (review T-4: `gu05_star_join_4dim_concrete_signature` segments
**54228…54234** — six rows missing plus one truncated mid-write by the `timeout` kill), and the
last of the seven is the informative one: the corpus's hardest solve, segment 54234, **does not
finish under either within 1,800 s** (`tmp/D1/logs/hard1-canon.log`, `hard1-fifo.log`, both `rc=124`; its
five trivial neighbours, all `steps=0`, are in `tmp/D1/tail5-*.tsv`).  So `canon`'s **−12 %**
draws is a figure that excludes a solve `canon` cannot complete at all, and `smallcanon` is the
only candidate that both completes that solve (381 dequeues, 328 draws, against `shipped`'s 281
and 149 — 2.2x) and reduces the corpus total.

### 5b The 19 tracked seeds at 10 id bases (950 runs per policy set)

`tracker/repro/satterm/seeds/*.json`, `looptrace <seed> <base> 20000 --policy=<p>`.

| policy | total dequeues | total loop draws | worst per-seed DRAW ratio over the 10 bases | verdict diffs |
|---|---|---|---|---|
| `shipped` | 2,008 | 293 | **15.0** (`NE6`: 1 draw at one base, 15 at another) | — |
| `concfirst` | 4,584 | 1,436 | **19.0** (`NE6`) | 0 |
| `smallrhs` | 1,929 | 421 | 1.8 (`NE6`) | 0 |
| `fifo` | 3,095 | 958 | 3.0 (`H2`, `RE`, `W4`) | 0 |
| `canon` | 2,130 | 300 | **1.00** — every seed | 0 |
| **`smallcanon`** | **1,860** | 410 | **1.00** — every seed, and the DEQUEUE counts are identical too | 0 |

### 5c `GU05` and `GU05MIN` at 25 id bases

Two measurements, because the model is about 170x slower per dequeue than the compiler and
cannot run the SHIPPED order to completion at `GU05`'s slow bases at all (base 2: compiler
221 ms, model 38 s unloaded).  The shipped spread is therefore quoted from the COMPILER
(`L5-TERMINATION.md` §R8.0a/§R8.4c) and the model is used for the candidates.

**(i) draws at a fixed 200-dequeue budget, over all 25 bases** — the base-sensitivity probe,
affordable for every policy:

| policy | `GU05` draws@200 | ratio | distinct values | `GU05MIN` draws@200 | ratio | distinct |
|---|---|---|---|---|---|---|
| `shipped` | 22 … 245 | **11.1** | 24 of 25 | 23 … 46 | 2.00 | 12 |
| `concfirst` | 33 … 220 (8 bases) | 6.7 | 8 of 8 | 33 … 88 | 2.67 | 12 |
| `smallrhs` | 65 … 172 | 2.65 | 23 of 25 | 71 … 115 | 1.62 | 11 |
| `fifo` | *(not run)* | | | 101 … 188 | 1.86 | 14 |
| `canon` | **65 … 65** | **1.00** | **1** | **20 … 20** | **1.00** | **1** |
| **`smallcanon`** | **107 … 107** | **1.00** | **1** | **78 … 78** | **1.00** | **1** |

**(ii) run to completion, 25 bases** (`--fuel=100000`, wall-clock cap as stated):

| policy | cap | verdicts | loop draws | **max/min** |
|---|---|---|---|---|
| `shipped` (COMPILER, §R8.0a) | 60–2400 s | 11 SOLVED at 60 s, 4 more at 300–600 s, 12 bases with no verdict | 743 … **81,481** (base 4 exceeds the harness's 100,000-id window) | **≥ 110** |
| `shipped` (model) | 90–150 s | 5 SOLVED, 20 TIMEOUT | 743 … 1,091 on the 5 that finish | — (the model cannot reach the slow bases) |
| `concfirst` (model) | 90 s | 24 TIMEOUT of 24 run | — | — |
| `fifo` (model) | 90 s | TIMEOUT at both bases run | — | — |
| `smallrhs` (model) | 150 s | **24 SOLVED**, 1 TIMEOUT (base 6) | 65 … 706 | **10.9** |
| `canon` (model) | 150–400 s | TIMEOUT at every base run (0…6 at 150 s, 0 at 240 s and at fuel 400 in 108 s); and it does not finish the CORPUS's instance of the same system in 1,800 s either (§5a) | — | 1.00 by (i), but it does not converge |
| **`smallcanon`** (model) | 150 s | **25 SOLVED** | **306 at every base** | **1.00** |

`GU05MIN` is not run to completion by ANY policy in the model: `smallrhs` misses a 150 s cap at
all 25 bases, `smallcanon` misses a 900 s cap at base 0, and the seed was reduced
(`L5-TERMINATION.md` §R8.4e) precisely so that it still misses a 600-dequeue fuel.  Its comparison is (i), the fixed-fuel one, where `smallcanon` and
`canon` are the only two with a single distinct value across 25 bases.

### 5d `concfirst` is not merely worse, it is intractable

It is the policy that dequeues the partitions carrying a CONCRETE part first — which is exactly
the premise `splitConcrete`, the loop's minting rule, fires on.  It therefore mints as early and
as often as it can, and the measurements say so: 1,436 draws over the tracked seeds against
`shipped`'s 293 (+390 %), `NP01` at 121–149 draws against 17–20, `GU05` TIMEOUT at all 25 bases,
and a corpus census that does not finish (`Ai` exhausts a 600 s cap at `--fuel=500`; the census
row above is omitted rather than reported from a truncated run).

### 5e The winner

**`smallcanon`.**  Against the brief's bar — "makes `GU05`'s spread ≤ 10x while not increasing
corpus dequeues by more than a few percent" — it is

* `GU05` spread **1.00x** (306 draws at every one of 25 bases), against `shipped`'s ≥ 110x, and
  the worst base drops from 81,481 draws to 306 — a **266x** reduction in the maximum, which
  divides a COMPILER figure (81,481, `L5-TERMINATION.md` §R8.0a) by a MODEL one (306): the compiler
  has never been run under a policy, so the ratio is indicative and Part B's gate 8 is what settles
  it (review T-7);
* corpus dequeues **68,940 vs 69,207: −0.39 %**, i.e. it does not increase them at all;
* not one solve in 2,301,195 gets worse by more than 2x in dequeues, and not one verdict moves;
* base-invariant on every tracked seed as well, in dequeues as well as draws.

**And it has a mechanism, not only a measurement** (review T-11).  `Loop/Dequeue.lean`'s own R5.3
result is that `Q.++!` refuses to insert `p` when some `u ∈ p.rhs` is already queued and inserts the
LINK `u <- (p.lhs)` instead, adding the edge `u → p.lhs` — which makes `p.lhs` a CHILD of `u`, so
under the reverse-topological priority *every partition of the swallowed variable is dequeued before
the link that would repair it: the repair is scheduled last, exactly when it is needed first*.  **A
link has arity 1.**  An arity-primary order therefore dequeues every repair link BEFORE the
arity-≥ 2 partitions it repairs, which is precisely the pathology R5.3 documents for the shipped
order.  That is why `smallrhs` and `smallcanon` both collapse `GU05`'s cost while `canon` — which
keeps the graph priority primary — does not, and it is why `smallcanon` is the only policy that
*reduces* corpus dequeues.

Its one cost is corpus loop draws, 2,485 against 1,845 (+35 %), concentrated in the corpus's
hardest solve; `canon` alone looks better there (1,628) but the comparison is not like for like — on the population
it covers the figure is −4.0 %, not −12 % (review T-4) — and it does not converge on `GU05`.
The runner-up is `smallrhs`, which gets `GU05`'s worst base to 706 draws but keeps a 10.9x
spread and is not order-canonical, so a budget set for it would still be a budget that can be
hit by id base.

**What the winner makes the budget safe.**  With `smallcanon` the largest loop draw count
anywhere measured is 328 (the corpus) and 306 (`GU05`, at every base), so the proposed
`ermine.solveBudget = 20000` clears the worst measured solve by **61x** and the corpus maximum
by 134x, and — this is the point of §0 — it clears it AT EVERY ID BASE, which is what a budget
needs in order not to turn a type error into a lottery.


## 5f. A3 — soundness and termination under another order

**Which hypotheses of `solve_sound` mention the order: none.**  They are
`buildQueue cs su = .ok (q, su')`, `fl.emptyRow = false`, `fl.disjRule = false`,
`fl.cseMints = false`, `Wf`, `SupOk` and `SupFresh` — three flag settings, the queue's
well-formedness and L3's supply invariant.  Nothing about `pop`.

That is necessary but not sufficient, because the CONCLUSION is about `run`, which calls `step`,
which calls `s.incm.dequeue`.  The precise question is what the proofs use of that call, and the
answer is machine-checkable:

| lemma | what it says | uses |
|---|---|---|
| `PQueue.dequeue_mem` (`Loop/Wf.lean:331`) | the dequeued partition was in the queue, and so was everything left | 36 |
| `dequeue_mem_or` (`Loop/RefineLearn.lean:1331`) | nothing but the dequeued partition is lost | 9 |
| `dequeue_length_lt` (`Loop/Dequeue.lean:79`) | the queue got strictly shorter | 3 |
| `kdist_dequeue` (`Loop/NoConc.lean:1381`) | the key-distinctness invariant survives | 2 |
| `dequeue_sub` (`Loop/Dequeue.lean:118`) | the rest is a subset | 2 |
| `dequeue_unique` (`Loop/RefineConcrete.lean:637`) | `pop` is a function | 13 |
| **`dequeue_prio_min`** (`Loop/Dequeue.lean:50`) | **the dequeued partition has minimal graph priority — the ONLY order-dependent lemma** | **1**, and that one use is inside `Loop/Dequeue.lean` itself, to prove `dequeue_not_of_lt` |
| `dequeue_not_of_lt` (`Loop/Dequeue.lean:140`) | the order is served strictly | **0** |

and the only places outside `Loop/Dequeue.lean` that unfold `PQueue.dequeue` at all are the three
that prove the structural lemmas above (`Loop/Wf.lean:333`, `Loop/NoConc.lean:1383`,
`Loop/RefineLearn.lean:1333`).  The greps are in `tmp/D1/a3-greps.txt`; the counts exclude each lemma's own statement and the doc comments.

`Loop/Policy.lean` §5 turns that reading into a theorem.  `DequeueShape q r rest` is
`∃ i, q.elems[i]? = some r ∧ rest = ⟨q.elems.eraseIdx i, q.graph⟩`; `dequeue_shape` proves it for
`Q.pop` and `dequeuePol_shape` for every policy, and `shape_mem`, `shape_mem_or` and
`shape_length_lt` derive the facts above from it alone.  So transporting S1 to another order is
not a matter of weakening a hypothesis — no hypothesis has to change — it is a matter of re-running
the same proofs with `stepP pol` in place of `step`, which is mechanical and is Part B's mirror
job, not Part A's.

**Termination on the certified fragments is order-independent for the same reason.**
`Loop/NoConc.lean`'s `noConc_terminates` and `Loop/VocFix.lean`'s `vocFixed_terminates` /
`noDraw_terminates` measure the state (the queue's length, the environment's size, the vocabulary),
never the order in which the queue is served; the one place the ORDER could have entered is
`dequeue_prio_min`, and neither fragment uses it.  `Loop/Depth.lean`'s `terminates_of_chainRun`
likewise counts draws by depth and key, not by position.

**The audit with the policy flag on** is the same audit: `lake build Rowpartition` 863 jobs and
`Audit.lean` **3,936** theorems / 0 non-standard axioms as reviewed (review T-7 corrected 3,935),
and **3,953** after §6's post-review additions with `Loop/Policy.lean` and `Loop/Budget.lean`
in the root import list, and no existing module edited (`git status`: only the root's import list
and the executable `Loop/Main.lean`).

## 6. What Part B would change in Scala (specification; NOT started)

Two system properties, **both default OFF**, read once in `Constraints.GenRules` beside
`splitKey` / `splitRow` / `resRow` / `rowSound` (`Constraints.scala:785-1120`):

```scala
val solveBudget: Int =                      // 0 = off, the DEFAULT
  try System.getProperty("ermine.solveBudget", "0").toInt catch { case _: Throwable => 0 }
val dequeuePolicy: String =                 // "shipped" = off, the DEFAULT
  System.getProperty("ermine.dequeuePolicy", "shipped")
```

### 6a The budget

* a counting wrapper around the loop's two minting sites — `Constraints.scala:1441`
  (`splitConcrete`'s `fresh`) and `:1887` (`resolution`'s `fresh`), the only two the shipped
  flags leave live — increments a per-solve counter and, when it passes `solveBudget`, raises
  `Death(budgetMsg)` with the site, the count and the budget.  **The counter is the whole
  mechanism** — there is no `Supply`-side baseline to read: `scalaparsers.Supply` has no `drawn`
  field, only private `lo`/`hi` (which `RowTrace.supplyBounds` reaches by reflection), and `lo` is
  not a draw count across block boundaries anyway (review T-10).  Counting at the two wrapped call
  sites gives LOOP draws by construction and excludes `PQueue.build`'s mint (`:684`) automatically,
  because that is a third call site and is not wrapped.  **The counter must be reset at the LOOP's
  own entry**, unconditionally, with save/restore because solves nest, and it must be a
  `ThreadLocal` because the shipped loader solves on several threads — NOT at `RowTrace.withSite`,
  which is a no-op unless `-Dermine.rowTrace` is set, so a counter reset there would never reset in
  a normal compile and the budget would fire on whichever solve pushed the MODULE's cumulative draw
  count past the limit (review T-1, the most serious finding against this specification);
* `incorporateAll` needs no change at all: the `Death` travels the path `ensureSuperset` and
  `makeEmpty` already use, which is what makes exhaustion a REJECTION and not an acceptance —
  `Loop/Budget.lean`'s `budget_never_accepts` is the theorem that this is the whole of it;
* with `solveBudget = 0` no counter is read and no branch is taken, which is the sense in which
  `runBud_eq_run` says the trace is untouched;
* **AND THE BUDGET IS COUPLED TO THE POLICY** (added 2026-09-06, after the D1B review; §0 already
  argued it and Part B first shipped it as a warning only).  `-Dermine.solveBudget` is IGNORED
  unless `-Dermine.dequeuePolicy` is non-shipped, and the message says `is IGNORED … Set
  -Dermine.dequeuePolicy=smallcanon to enable the budget`.  The reason is measured, not
  hypothetical: under the shipped order a solve's draw count depends on the ID BASE, and the
  reviewer reproduced `-Dermine.solveBudget=20000` REJECTING a satisfiable `GU05` at base 0 after
  56 s while bases 1 and 2 accept it in under a second — a well-typed program failing by id base,
  which is worse than slow.  A `System.err` warning is not enough on its own: it is printed at
  class-initialisation time and an `sbt` or LSP session swallows it.  The model's drivers apply
  the same rule (`Loop/Policy.lean`'s `effBudget`, used by `polCensus` and
  `PolicyReplay.solveSeedP`) and the trace's `sin` record carries the EFFECTIVE budget, so the L2
  differential stays exact under every combination of the two flags.  It is deliberately a DRIVER
  rule and not a change to `stepBud`/`stepPB`/`runSP`, so no theorem statement moves.

### 6b The dequeue policy

* `Q.pop` (`Constraints.scala:543`) is the whole of the change: today it is
  `q.split(k => k._1.map(_._1) == priority)` on the finger tree's own measure.  A policy takes
  the same `(q, graph)` and returns the same `Option[(Partition, PSQI)]`; the SHIPPED branch is
  the existing body, unchanged and taken when `dequeuePolicy == "shipped"`, so the finger tree's
  fast path is not slowed for the default;
* the winner of §5 is the only alternative that has to be written.  `PQueue.dequeue`
  (`:583`) passes the policy through; nothing else in `Constraints.scala` moves;
* whatever auxiliary state the winning policy needs (an arrival BATCH counter for `fifo`, a
  first-occurrence RANK table for `canon`) is threaded on the `PQueue`, as a field next to
  `graph`, and is built where `graph` is built.

**Review T-2, folded in.**  `Q.pop` is not "the whole of it" without two further statements.
(i) The finger tree's measure `PSQK` (`Constraints.scala:468`, built by `pr` at `:471`) carries
`(graph.sort(lhs), (rhs.hashCode, lhs.hashCode))` and its monoid minimises only the FIRST
component; `smallcanon`'s primary key is the partition's ARITY, which the measure does not carry.
So Part B must either extend `PSQK`/`pr` with a min-arity component — which is something else in
`Constraints.scala` moving — or scan the queue linearly per dequeue, which is what the model does
and which makes the loop O(n) per dequeue on a queue that reaches hundreds of partitions on `GU05`.
**Decide by measurement**, and run gate 7 (`perf-bench.sh batch`) with the policy ON as well as off.
(ii) The canonical key must **not** displace `rhs.hashCode` in the tree's sort order:
`PQueue.findRHS` (`:614`), `PQueue.contains` (`:634`) and `Q.insert`/`sandwich` (`:509`) are
finger-tree RANGE SPLITS on `(rhs.hashCode, lhs.hashCode)` and return wrong answers, silently, if
the tree stops being sorted by that key.  A policy that only chooses a different ELEMENT and
re-joins `lhs <++> rest` is safe; one that re-measures the tree under a new key is not.

**A third item, found while starting Part B and not in the review: `canonKey`'s LABEL component is
not implementable as written.**  `Loop/Policy.lean`'s `canonKey` orders a right-hand side's concrete
part by `Lbl.n` — the label's index in the solve's `slbl` table — and `slbl` is a TRACE artefact:
`RowTrace.solveInput` builds it, and the compiler at solve time has no such table.  The fix is to
order labels by the `Name` itself — `(module, string, fixity.con)`, which every `Name` carries, is
base-independent for the same reason ids-by-order are, and needs no table on either side.  This is a
change to the MODEL as well as to the Scala (`canonKey`'s label component becomes the name triple
instead of `l.n`), it belongs to the Lean mirror of §6c, and it obliged a re-run of the `smallcanon`
census to confirm the §5 figures.

**Done, 2026-09-06, and NOTHING MOVED.**  `Loop/Policy.lean`'s `canonKey` now orders labels by
`lblKey` — `(kind, module, string, con)`, the tags `Name.hashCode` uses, with the strings as code
points and `canonSep` separating the components — and the three measurements were re-run against
the pre-change artefacts (`tmp/D1/PREKEY-*`):

| measurement | result |
|---|---|
| `smallcanon` corpus census, all 41 traces | **byte-identical**, 2,301,195 rows |
| the 19 tracked seeds at 10 bases (190 runs) | **identical** |
| `GU05` at 25 id bases, run to completion | **identical** — 414 dequeues / 306 loop draws at every base |

So §5's figures stand as printed, and the two label orders never break a tie differently on this
corpus.

### 6c The model mirror

`Loop/Policy.lean`'s `Policy` and `Loop/Budget.lean`'s `stepBud` already exist and are already
what the compiler would do; what Part B adds is the TRACE side, so that a policy-on or budget-on
compiler trace can be replayed: the `sin` record gains the policy name and the budget, and
`Loop/Replay.lean`'s `Segment` reads them, so `looptrace --replay` reproduces a policy-on trace
the way it reproduces a `rowSound`-on trace today (S2 review V-3).

### 6d The gates Part B must pass

With BOTH flags OFF first — nothing may change:

1. `core/test` 913/914 (the one known failure);
2. `TestLoopTrace` 714/714;
3. the L2 corpus differential over the eight groups: byte-identical row trace, `AGREE` on every
   segment, `hashdiff = eqdiff = 0`;
4. the published `.ei` interfaces identical to the main checkout's.

Then with the flags ON:

5. the same differential under `--policy=<winner>` / `--budget=<n>` on both sides: the model and
   the compiler agree segment for segment under the new order (this is what 6c is for);
6. `core/test` again, and the corpus list of programs whose VERDICT changes — which must be
   empty, and which the model already predicts (§5's `verdict-diff` column);
7. `tracker/tools/perf-bench.sh batch` before/after, against the P1 baselines;
8. `GU05.json` at 25 id bases ON THE COMPILER under the new order — the spread in draws and in
   wall clock, which is P10's own acceptance test — and `gu05_star_join_4dim_concrete_signature.e`'s
   real module load time;
9. the budget's own gate: a run of the whole corpus at the proposed budget, in which it must
   never fire.

Adoption (turning either default ON) is the USER's decision and is not made in Part B.

## 7. What Part A did NOT do

* **The compiler was not run under any policy or budget.**  Part A is model and measurement
  only; every GU05 figure for a CANDIDATE order is the model's.  The model's draw counts are
  the compiler's where both finish (`GU05` bases 1 and 2: model 1,091 and 743, compiler 1,091
  and 743 — `L5-TERMINATION.md` §R8.4c), which is the licence for using it as the oracle.
* **The model cannot run the SHIPPED order on `GU05` to completion at the slow bases.**  It is
  about 170x slower per dequeue than the compiler (base 2: 221 ms vs 38 s unloaded), so 19 of
  25 bases are wall-clock TIMEOUTs.  The shipped spread in the table is the COMPILER's, from
  §R8.0a, and is quoted as such.
* **`budget_terminates` gives no a-priori FUEL number.**  Converting a draw budget into a
  dequeue bound needs a bound on dequeues per draw, which is `L5-TERMINATION.md` §R8.6b's open
  problem; `TerminatesB` is the same existential `Order.Terminates` is.
* **S1's soundness theorems are not re-proved against `stepP`.**  §5f says what the transport
  needs — nothing but `DequeueShape`, which every policy satisfies — and identifies the single
  order-dependent lemma in the development (`dequeue_prio_min`, used once, to prove a lemma
  used nowhere).  Re-running the proofs with `stepP pol` is mechanical and belongs to Part B's
  mirror.
* **`fifo` is BATCH fifo, not per-insertion fifo**, because neither `LPart` nor Scala's
  `Partition` carries an arrival counter (§3).
* **`concfirst`'s corpus census does not finish** (§5a footnote): the row is over the 26 of 41
  groups it covered.
* **`canon` and `fifo` are one segment short** of the full corpus count, and it is not a
  measurement I failed to take: the corpus's hardest solve,
  `gu05_star_join_4dim_concrete_signature` segment 54234, DOES NOT FINISH under either within
  1,800 s (`tmp/D1/logs/hard1-canon.log`, `hard1-fifo.log`, both `rc=124`, confirmed
  2026-09-06 08:20).  Their totals are therefore lower bounds, and `canon`'s "−12 % draws" in
  particular EXCLUDES a solve `canon` cannot complete; `smallcanon`'s and `smallrhs`'s totals
  include it.
* **`GU05MIN` is not run to completion by any policy** (§5c).
* **Substitution identity across policies was not compared** — only verdicts (0 differences in
  2,301,195 corpus solves and 950 seed runs).  A different order legitimately derives a
  different saturated set; what S1 promises is `run_noLoss`, not identity, and the verdict is
  the observable a user sees.

## 8. Post-review corrections (2026-09-06, after `tracker/loopmodel/D1-REVIEW.md`, verdict ADVANCE)

The reviewer re-ran every load-bearing number and reproduced them, most to the digit; the findings
are T-1…T-14.  T-1, T-2, T-9, T-13 and T-14 are **Part B** items and are folded into §6.  What
changed in this file and in the Lean, old value → new:

| # | where | old | new |
|---|---|---|---|
| T-3 | `Loop/Policy.lean` | `DequeueShape` covers only a SUCCESSFUL dequeue, and §5 claimed it was "everything the development's proofs use" | §6 adds **`dequeuePol_none`** (`dequeuePol pol a q = none → q.elems = []`) for `Q.pop` and all five alternatives — the `none` branch IS `stepP`'s acceptance, so a `pop` that answered `none` on a non-empty queue would make the solve accept WITHOUT SATURATING — plus `dequeuePol_nil`, `shape_kdist` and `dequeuePol_unique`, so the inventory is complete on both branches.  Build 863, audit **3,953 / 0** (was 3,936), `looptrace` 1,668; the executable's behaviour is unchanged (`--policy=shipped` still reproduces `--depth` over `boot`'s 54,199 segments, and `--policy=smallcanon` reproduces its own census row for row) |
| T-4 | §5a | `canon`/`fifo` are "two segments short"; `canon` −12 % draws / +1.1 % dequeues, `fifo` +167 % / +6.8 % | **seven** segments short (`gu05…` 54228–54234); on the common population `shipped` spends 68,926 dequeues / 1,696 draws, so `canon` is **+1.49 % / −4.0 %** and `fifo` **+7.21 % / +191 %**.  Footnote ¹ added to the table |
| T-5 | §5a | "No policy changes a single verdict" | true of the **five** policies whose census finished; `concfirst` turns `gu05…#54234` SOLVED → FUEL, and its census ran at `--fuel=500` against the others' 3,000, so its row is incomparable.  Also recorded: `replayPolicyOne` skips the early label check, so "verdict" is the LOOP's |
| T-6 | §2 | claimed the theorems were quoted verbatim, then paraphrased them | all five statements now quoted verbatim from `Loop/Budget.lean` |
| T-7 | §5f | `Audit.lean` "3,935" | **3,936** as reviewed, 3,953 after T-3 |
| T-7 | plan row | `Loop/Policy.lean` "423 lines" | **442** as reviewed, **726** after T-3 |
| T-7 | `Rowpartition.lean` doc | lists four alternatives, omits `smallCanon` — the winner | all five listed, and `dequeuePol_none` named |
| T-7 | `Policy.lean` §5 | "five facts"; uses 40 / 10 / 4 / 3 | **six** facts; **36 / 9 / 3 / 2** (+ `kdist_dequeue` 2, `dequeue_unique` 13) — which is what §5f's table already said; "four alternatives" → **five** |
| T-7 | §5e | "266x reduction in the maximum" | same figure, now labelled as a COMPILER numerator over a MODEL denominator, with Part B's gate 8 named as what settles it |
| T-10 | §6a | "its baseline is the `Supply`'s `drawn`" | deleted — `scalaparsers.Supply` has no `drawn`, only private `lo`/`hi`, and `lo` is not a draw count across block boundaries.  The call-site counter IS the mechanism, and it excludes `PQueue.build`'s mint because that call site is not wrapped |
| T-1 | §6a | "the counter is reset where `RowTrace.site` is" | **reset at the LOOP's entry, unconditionally, `ThreadLocal`, with save/restore because solves nest** — `RowTrace.withSite` is a no-op unless `-Dermine.rowTrace` is set, so a reset there would never fire and the budget would trip on a MODULE's cumulative draws |
| T-11 | §5e | the winner was justified by measurement alone | the MECHANISM named: `Q.++!`'s repair link has arity 1, so an arity-primary order dequeues it FIRST — reversing the pathology `Loop/Dequeue.lean` §R5.3 documents for the shipped order ("the repair is scheduled last, exactly when it is needed first") |

Not changed, and why: T-8 (the census sweep's `rc` codes) needs no action — the reviewer confirmed
the `patchgroups.sh` merge is complete; T-12 is an inventory the reviewer checked and agreed with.
