# SUBSUME-STAGE0 — diagnosis: does the checker terminate on a refused row program?

Stage S0 of the `subsume-termination` programme (`tracker/PROMPT-subsume-termination.md`,
brief `tracker/satterm/briefs/brief-S0.md`). Worktree
`~/research/ermine/ermine-scala-wt-subsume-s0`, branch `subsume-s0`, base `scala3-migration`
478a369c. **No fix; measurement only. Nothing committed.**

Scratch, and every log path below, is relative to
`<s>` = `/home/dmitry/research/ermine/scratch-subsume/s0/`.

---

## 0. The answer, before the evidence

**The title question's answer on this tree is YES: the check terminates on the B1 program,
and it terminates fast.** The same program is refused

* by `bin/ermine` in **0.06–0.10 s** (`<s>/repro/cli-run1.log`, `<s>/rowtrace/cli-bad.log`),
  with `Row partitions are unsatisfiable at field 'Bad.startDate': the whole contains it but
  no part does` — a bare row-label refutation that never reaches the escape check; and
* inside `ErmineFixture`, in the very suite that hangs, when the property is asked for **one**
  test instead of a hundred: `a dateDiff combine over a relation WITHOUT the dates is now
  REJECTED (B1): OK, passed 1 tests`, whole suite green, `Total 12, Failed 0`
  (`<s>/repro-min1.log`).

**What does not return is the ScalaCheck PROPERTY, not the check.** `ErmineFixture.no`
(`scalacheck-binding/src/main/scala/TestErmine.scala:220-223`) maps `Proof -> False` and
`False -> True`; a successful rejection therefore yields status `True`, which is *passed* and
not *proved*, so ScalaCheck does **not** stop after one test and runs `minSuccessfulTests`
(default **100**) complete checks of the same module. Every other property in the suite goes
through `sessionProof` and returns `Prop.Proof`, which short-circuits at one test — which is
exactly why 11 of 12 finish and this one does not.

Each of those hundred tests re-type-checks the module's whole import closure, and the cost is
**linear and measured**: the suite alone takes 184 / 191 / 209 / 249 / 321 s at
`-minSuccessfulTests` 1 / 2 / 4 / 8 / 16, i.e. **9.1 s per additional test**, so the shipped
default of 100 predicts 184 + 99 x 9.13 = **1,088 s**. **The S0 reviewer ran it to completion
and it is 1,099 s — within 1 % — `passed 100 tests`, `Total 12, Failed 0`**
(`<r>/defaultN.log`). Part B's *"never returns"* is therefore refuted by a finished run, not
merely explained. Their JVM CPU series rises linearly to **20 min 20 s** at t = 1,080 s, which
is the same order as Part B's "28 CPU-minutes seen" for a JVM that was also running other
suites — wall clock and CPU time are different quantities and this report should not have
equated them (S0 review §4.5).

**Of Part B's three hypotheses, H1 and H2 are REFUTED and H3 survives** — in a sharper form
than Part B states it: the rejection path does not grow the environment either. See §5. On the
refused module itself the escape check is **eight walks over a thirteen-entry substitution**
(§1.8); across a whole suite it is **45.4 s of 184 s, 24.7 %** — a genuine performance item,
now ticketed, and not a hang (§0.2).

### 0.1 For S1a and S1b: the interim numbers you cited are UNCHANGED

Every figure the two Lean lanes were given mid-stage held to the end of the stage, on a larger
sample:

| cited interim | final |
|---|---|
| `hm.types.size` max 1,566 | **1,566** — and it is the same maximum in the run that refuses the module in 0.06 s, in the suite that passes, and in the suite that does not return (§1.7) |
| 0 cycles in 186,754 walks | **0 cycles in 984,400 identity-marked walks** (492,200 escape checks across four traced runs: 9,531 + 171,286 + 93,377 + 218,006) |
| 0 budget hits | **`rowSoundBudgetHits = 0`, `solveBudgetHits = 0`** in every run; `labelDecide` spends 9–10 nodes per RUN (§1.7) |
| the check takes 0.06 s | **0.06–0.10 s**, at all seventeen `Supply` id bases swept (§1.3, §1.6), and the refused module's own escape-check work is **8 calls over a 13-entry substitution** (§1.8) |
| the property runs it 100 times | **confirmed**: ScalaCheck 1.15.4 `Test.Parameters.default.minSuccessfulTests = 100, workers = 1`, read by reflection from the shipped jar (`<s>/scparam/result.txt`), and the cost is **9.1 s per test, linear** over N = 1…16 (§6.2) |

**One number DID move, and it is not in the table above because it was never in the table:**
the *cost share* of `:648`. Every `:648` total in the first report was a floor-sum of integer
milliseconds and understated the walk by 15.7x–21x; corrected, `:648` is **45.4 s of a 184 s
suite (24.7 %)** and **12.1x** `checkSkolemEscape:365`, not half of it. **§0.2 has the
correction and the exact replacement sentences for the three landed documents that quote the
old figure.** Nothing in S1a's or S1b's theorems depends on it.

**The stage's central claim was also strengthened by the reviewer, not by me:** the default-N
run that I only ever extrapolated, they ran to completion — `passed 100 tests`,
`Total 12, Failed 0`, **1,099 s** (`<r>/defaultN.log`), against my predicted 184 + 99 x 9.13 =
1,088 s, within 1 %. Part B's *"the property never returns"* is refuted by a completed run.

Nothing else moved. **Two things were added that S1a and S1b did not have**: the tree/DAG ratio of
the walk never exceeds **4.39** (so there is no exponential unfolding of shared structure — the
mechanism nobody had named, §5.2), and **one ScalaCheck test costs exactly one library boot**,
counted at 9,537 escape checks against `bin/ermine`'s 9,531 (§1.10).

### 0.2 Corrections propagated — the `:648` cost figures were a FLOOR-SUM, and they inverted a comparison three landed documents now repeat

The S0 review's finding 1 is correct and this is the correction. The first version of
`SubsumeTrace.phase` logged `(System.nanoTime - t) / 1000000L` **per call** and kept no
accumulator; the report then summed those integers. **96.7 % of calls are sub-millisecond**, so
each contributed **0**, and every `:648` total in the first report was a lower bound that
understated the true cost by about an order of magnitude. `cse` (`:365`) was always a
nanosecond `AtomicLong` and was always right — which is why the old §1.7 said, impossibly, that
TWO whole-environment walks cost seven times LESS than one.

`phase` now has `cse`'s treatment: one `AtomicLong` of nanos and one of max-nanos per half,
nothing logged inside the timed region, totals carried on the `escape` record. Both traces were
re-run on the fixed build (`<s>/compile5.log`, `<s>/ns-trace-cli.tsv`, `<s>/ns-trace-min1.tsv`,
`<s>/ns-cli.log`, `<s>/ns-min1.log`).

| | escape checks | `:648` OLD floor-sum | `:648` **CORRECTED** | understated by | per `subsumeType` | `:365` (always accurate) |
|---|---|---|---|---|---|---|
| `bin/ermine Bad.e` (12.2 s wall) | 9,531 | 177 ms | **2.79 s — 23 % of the run** | **15.7x** | 292 us | 0.24 s / 2,226 calls = 107 us per walk |
| suite, `-minSuccessfulTests 1` (184 s untraced) | 171,286 | 2,166 ms | **45.4 s — 25 % of the run** | **21.0x** | 265 us | 3.75 s / 40,013 calls = 94 us per walk |

Per-call maxima are now accurate (the first build's per-call integer floors were 6 ms / 12 ms;
the counts were always sound): `fskvs` max 5289.4 us, `kindVars` max 5813.4 us in the suite run.

**The comparison inverts.** `:365` is ONE whole-environment walk per ALTERNATIVE; `:648` is
TWO per `subsumeType`, and there are four times as many of the latter. On the corrected numbers
**`:648` costs about 12 times `:365`, not half of it.** Any cost work — P7 Step 1, or an
S2 that ever gets briefed on performance — must start at `:648`.

**Three LANDED documents quote the wrong figure.** They are not mine to edit; the exact
replacements are below, for the orchestrator to apply as a doc edit at landing.

**(a) `SUBSUME-STAGE1A.md`, three places (:289, :396, :488).**

> OLD (:289): Together with S0's measurement that `:648` is ~1 % of the hang, the honest
> reading is that **S2's brief should not be "make `:648` cheaper"**;
>
> NEW: S0's cost measurement has been CORRECTED (S0 review finding 1; `SUBSUME-STAGE0.md` §0.2):
> the first figure was a floor-sum of integer milliseconds and `:648` in fact costs 45 s of a
> 184 s suite run (25 %), about 12 times `checkSkolemEscape:365`. The honest reading is
> unchanged and rests on this stage's THEOREM rather than on that number: **S2's brief should
> not be "make `:648` cheaper"**, because making it cheaper cannot be the fix for a check that
> terminates —

> OLD (:396): taken
> with S0's measurement that `:648` is ~1 % of the hang, **"make `:648` cheaper" is not a
> brief this stage supports**.
>
> NEW: and — notwithstanding S0's
> CORRECTED measurement that `:648` is 25 % of a suite run, not ~1 % (`SUBSUME-STAGE0.md` §0.2) —
> **"make `:648` cheaper" is still not a brief this stage supports**, because it is a performance
> item and not a fix.

> OLD (:488): With S0's measurement that `:648` is ~1 % of the hang, S2's
> brief should not be "make `:648` cheaper"
>
> NEW: S0's measurement has been corrected to 25 % of a suite run (§0.2 there), which
> strengthens the PERFORMANCE case and changes nothing here: S2's brief should still not be
> "make `:648` cheaper"

**(b) `SUBSUME-STAGE1A-REVIEW.md`, two places (:226, :262).**

> OLD (:226): (As it happens S0's independent measurement vindicates the conclusion — `:648` is
> 2.2 s of a 184 s suite — so this is a wording fix, not a result change.)
>
> NEW: (S0's independent measurement has since been CORRECTED — `:648` is 45 s of a 184 s
> suite, 25 %, not 2.2 s (`SUBSUME-STAGE0.md` §0.2) — which makes this wording fix MORE
> important, not less: a bound on node visits must not be read as a bound on time.)

> OLD (:262): S0's measurements make
> this urgent rather than pedantic: in the 12-property suite `:365` costs **3.9 s** against `:648`'s
> **2.2 s**, and two of its five RUNNABLE stack samples land there
>
> NEW: S0's CORRECTED measurements make
> this urgent rather than pedantic: in the 12-property suite `:365` costs **3.7 s** against `:648`'s
> **45 s** — the ordering is the OPPOSITE of the figure this review was given
> (`SUBSUME-STAGE0.md` §0.2) — and two of the six RUNNABLE stack samples land there

**(c) `SUBSUME-STAGE1B-REVIEW.md`, one place (:215).**

> OLD: skips the `kindVars` half, and memoises the wrong traversal — the one S0 measured at
> 2,044 ms rather than the one at 3,457 ms.
>
> NEW: skips the `kindVars` half, and memoises the wrong traversal — on S0's CORRECTED
> nanosecond figures the `fskvs` half is 21.1 s and the `kindVars` half 24.3 s
> (`SUBSUME-STAGE0.md` §0.2), not 2,044 ms and 3,457 ms.

Nothing in any of the three CONCLUSIONS changes: S1a's termination theorem, S1b's bound, and
this stage's answer to the title question all stand. What changes is one quantity, and the
direction of one "which site is costlier" comparison.

---

## 1. What was measured

### 1.1 The reproduction, alone

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
sbt core/compile core/copyResources                       # <s>/compile.log
sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'  # <s>/repro-alone.log
```

11 of 12 properties finished by t≈95 s; the B1 rejection property did not return. Killed by
PID at **elapsed 625 s, cpu 431 s** (`<s>/stacks/probe-b.txt` header line). Heap was not the
problem: `jcmd GC.heap_info` at that moment read `used 437180K` of a 1 GB G1 heap.

Twelve `jcmd <pid> Thread.print` samples at 30 s and two later probes are in
`<s>/stacks/sample-*.txt`, `<s>/stacks/probe-a.txt`, `<s>/stacks/probe-b.txt`;
`<s>/stacks/sampler.log` is the sampler's own log.

### 1.2 The sampled frames are NOT one place (Part B's "always in these frames" does not hold here)

Of the B1 thread's samples, four were **BLOCKED** on `ErmineFixture.literalLock`
(`TestErmine.scala:153`) while another property held it, and the RUNNABLE ones were in **four
different places**:

| sample | deepest frames | call site |
|---|---|---|
| `sample-4` | `Constraints$Q$PQueue.++:699 <- PQueue$.apply:809 <- build:838` | `Subst.solve:1421 <- trySolveOn:1719 <- inferType:1095` |
| `sample-5` | `ArrowK.vars(Kind.scala:58) <- Type$$anon$3.vars:653 / :649 <- HasKindVars$$anon$3.vars(Kind.scala:125) <- Kind$.kindVars:96 <- SubstEnv.kindVars:169` | **`subsumeType:648`** `<- inferType:1062 <- inferAltTypesPrime:1159 <- typeCheckExplicitBinding:763` |
| `sample-7` | `Q$.popSmallCanon:678 <- pop:557 <- dequeue:719 <- incorporateAll:1709` | `PQueue.expand:780/787 <- Subst.solve:1637 <- inferImplicitBindingTypes:944` |
| `probe-a` | `Type$$anon$5.vars:708/:707 <- HasTypeVars$$anon$6.vars:771 <- Type$.fskvs:666` | **`checkSkolemEscape:365`** `<- inferAltTypesPrime:1171` |
| `probe-b` | 83 nested `Vars$$anon$1.apply(Vars.scala:23)` under `Vars$$anon$4.apply:57` | same `checkSkolemEscape:365`, in the TRAVERSAL rather than the construction phase |
| `sample-8` | `scalaparsers.Parsing.blockComment(ParsingUtil.scala:148)` | `SurfaceParsers$.module:997 <- NewPipeline$.readModule:80 <- Session$.load:872 <- loadStatements:154` — **re-parsing a library module** |

So `Subst.scala:648` is **one of at least five** places this thread is found, three of them are
not `subsumeType` at all, one of them (`sample-4`, `sample-7`) is the row-constraint solver's
queue, and one is the PARSER. That alone puts the weight on H3 rather than on the escape
check — and `sample-8` is the first hint of §4's answer.

**The full sample, classified (S0 review §2.2 and finding 6, `<r>/classify-out.txt`).** Across
my twelve samples plus two probes and the reviewer's eighteen dumps of a completed default-N
run — **30 timed thread dumps in total** — the B1 thread appears in **ten distinct top frames**
in mine and **fourteen** in the reviewer's. Exactly **ONE** of the thirty (`sample-5`) lands in
the `:648` kind walk; **eight** land inside `scalaparsers` (the thread is re-parsing a library
module); and **not one of the thirty has any frame at `Type.scala:651`** — the line Part B says
the thread is "always" in.

**What this can and cannot say.** Part B's three dumps were taken on other trees
(`json-encode 3eba80f8`, `json-runner 85d95531`) and are not in `<s>/`, so the honest claim is
**"not reproduced here"**, not "did not happen". With about one sample in twelve landing in the
walk, three independent single dumps all landing there is ~0.06 % — most likely a small,
correlated sample (one dump per JVM, or several taken inside one walk) rather than a
contradiction that needs explaining away. A thread sampled in `ParsingUtil.scala:148` cannot be
inside a single non-returning `subsumeType` call, and that one observation refutes "one call
that never returns" on its own.

### 1.3 The favourable order: the same program under `bin/ermine`

`<s>/repro/Bad.e` is the B1 program as a module (`<s>/repro/Good.e` is its passing twin):

```
bin/ermine <s>/repro/Good.e   # loads,   13.2 s wall (12.9 s of it stdlib boot)
bin/ermine <s>/repro/Bad.e    # REFUSED, 12.9 s wall; the module itself takes 0.06 s
```
`<s>/repro/cli-run1.log`. The refutation is

```
<s>/repro/Bad.e:14:7: Row partitions are unsatisfiable at field 'Bad.startDate':
  the whole contains it but no part does
```

With interfaces left at their shipped default (`useInterface=true`) it is refused just as
fast, and on the second, interface-warm run the same refutation is reported at a different
field/clause — `'Bad.endDate': a part contains it but the whole does not`, 0.20 s
(`<s>/cli-useinterface.log`). Both are the row-label check (`slbl` records), not the escape
check.

### 1.4 The row trace of the favourable run

```
java -Dermine.rowTrace=<s>/rowtrace/cli-bad.trace ... Console <s>/repro/Bad.e
tracker/tools/rowtrace-summary.py <s>/rowtrace/cli-bad.trace
```
(`<s>/rowtrace/cli-bad.log`, 174,832 records):

| | whole run (stdlib + module) | records mentioning `Bad.e` |
|---|---|---|
| `solve` calls | 54,257 | 33 |
| carrying a row constraint | 380 | — |
| input partitions | 761 | 28 |
| saturated partitions | 1,066 | 59 |
| derived partitions | 379 | — |
| `slbl` (label check) | 12 | **12, all of them** |

The path **does** go through the row-label machinery, and the twelve `slbl` records
(`<s>/rowtrace/cli-bad.module.trace`) are where the refutation comes from. Derivation rules
on this module: `Resolution`, `Cancellation`, `CommonSubexpression`, `Substitution`,
`SplitConcrete`, `SplitKeyed`.

### 1.5 The instrumented numbers (the heart of the stage)

`-Dermine.subsumeTrace=true -Dermine.subsumeTrace.out=<file>` (§3) records, for every
`subsumeType` entry and again at the escape check, the substitution's size and the exact cost
model of the two `vars` recursions, computed in DAG time.

**Run A — the un-returning run, default 100 tests, traced**
(`<s>/subsume-trace-alone-100tests.tsv.gz`, 560,263 records, killed after ~380 s):

| quantity | mean | p50 | p90 | p99 | max |
|---|---|---|---|---|---|
| `hm.types.size` at the escape check | 272.5 | 64 | 964 | 1480 | **1566** |
| tree nodes the KIND walk visits | 6,779 | 1,101 | 24,645 | 35,124 | **35,921** |
| distinct objects (DAG) it reaches | 3,057 | 576 | 10,999 | 15,953 | 16,328 |
| walk depth | 12.9 | 11 | 19 | 23 | **23** |
| tree/DAG ratio | 1.92 | — | — | 2.57 | **4.39** |

* escape checks executed: **93,377**
* cycles found: **0** (`cyclicKV=false` and `cyclicTV=false` on every one of the 93,377
  records, i.e. 186,754 identity-marked walks)
* the duration distribution over those 93,377 calls (`<s>/phase-ms.txt`): **96.7 %** of
  `kindVars` calls and **98.1 %** of `fskvs` calls are under a millisecond, max 16 ms / 29 ms
  — which is exactly why the first version's per-call integer-millisecond log floor-summed to
  almost nothing (§0.2)
* **total time inside `Subst.scala:648`: the floor-sum said 5.50 s; it is a LOWER BOUND and
  the figure is withdrawn.** The nanosecond re-run of the same suite shape puts `:648` at
  **45.4 s of a 184 s run (24.7 %)** — see §0.2. This run (default N, killed) was not re-run;
  the corrected pair of runs is the CLI boot and the `-minSuccessfulTests 1` suite.
* `checkSkolemEscape`'s environment walk (`:365`): 21,936 calls, **2,793 ms** total, and
  **not one call reached the 50 ms per-call log threshold** — `grep -c '\tcse\t'` is 0 in all
  three traces, so no single whole-environment walk anywhere took 50 ms
* `GenRules.rowSoundBudgetHits = 0`, `GenRules.solveBudgetHits = 0`,
  `GenRules.rowSoundNodes = 10` for the entire run

**Run B — the same suite with `-- -minSuccessfulTests 1`, traced**
(`<s>/subsume-trace-min1.tsv.gz`, 1,027,716 records, `<s>/repro-min1.log`): identical maxima
(`maxTypes=1566`, `maxTreeKV=35,921`, `maxDepth=23`), 0 cycles in 171,286 escape checks,
`:648` total **2,166 ms** (WITHDRAWN: a floor-sum lower bound; the nanosecond re-run gives **45.4 s**, §0.2),
`checkSkolemEscape:365` **3,913 ms** over 40,013 calls (accurate).
**The suite passed: `Total 12, Failed 0, Errors 0, Passed 12`, 336 s with tracing on.**

(The large traces are gzipped in place: `subsume-trace-alone-100tests.tsv.gz`,
`subsume-trace-min1.tsv.gz`, `rowtrace/cli-bad.trace.gz`.)

### 1.6 The id-base sweep (the order-dependence, tested directly)

`V.hashCode` *is* the variable id (`Vars.scala`), and both order reads E11c names are
functions of the absolute id base. `<s>/harness/IdBase.java` (a scratch fixture; no compiler
source is touched) advances the global `Supply` by N blocks of 1,024 before handing over to
`Console.main`. Sweeping N over `{0,1,2,3,4,6,8,12,16,24,32,48,64,96,128,192,256}` (seventeen bases)
(`<s>/idsweep/summary.txt`, per-run logs `<s>/idsweep/base-*.log`):

**every single run refused the module, in 12.9–27.8 s wall (the check itself 0.06–0.2 s).**
Shifting the id base alone, in the CLI environment, does **not** reproduce the hang.

**One outlier inside that range, flagged by the S0 review (§4.4) and not by me.**
`<s>/idsweep/base-16.log` boots the library in **26.79 s** against 12.35–12.79 s at every
other base, while its module refusal is still **0.09 s**. It is a 2x outlier **confined to the
library boot**, and it is the only datum in this stage suggesting an id base can double a
check's cost. The refusal is invariant, so it changes no conclusion — but it is exactly the
shape that would make "two new suites ran before it" matter, and it deserves one repeat run at
that base to see whether it is machine noise (§8.3).

### 1.7 The comparison that settles it

The same instrumentation on three runs — the run that does not return, the run that does, and
the `bin/ermine` run that refuses the module in 0.06 s — reaches **the same maxima**:

| | `bin/ermine Bad.e` (REFUSES, 0.06 s) | suite, `-minSuccessfulTests 1` (PASSES, 336 s) | suite, default 100 (DOES NOT RETURN, killed ~380 s) |
|---|---|---|---|
| escape checks executed | 9,531 | 171,286 | 93,377 |
| max `hm.types.size` | **1,566** | **1,566** | **1,566** |
| max tree nodes, kind walk | **35,921** | **35,921** | **35,921** |
| max DAG nodes | 16,325 | 16,327 | 16,328 |
| max walk depth | **23** | **23** | **23** |
| cycles found | 0 | 0 | 0 |
| slowest single kindVars / fskvs | 2 ms / 8 ms | 12 ms / 6 ms | 16 ms / 29 ms |
| total ms in `:648` — FLOOR-SUM, **withdrawn** (§0.2) | 177 | 2,166 | 5,501 |
| total in `:648` — **CORRECTED nanos** | **2.79 s (23 % of the run)** | **45.42 s (24.7 % of 184 s)** | not re-run |
| total in `checkSkolemEscape:365` (always nanos, always sound) | 286 ms → **238 ms** (2,226 calls, 107 us/walk) | 3,913 ms → **3,749 ms** (40,013 calls, 94 us/walk) | 2,793 ms (21,936 calls) |
| `rowSoundBudgetHits` / `solveBudgetHits` | 0 / 0 | 0 / 0 | 0 / 0 |
| `rowSoundNodes` (labelDecide) | 9 | 9 | 10 (33 in the fourth traced run) |

Logs: `<s>/rowtrace/cli-bad.subsume.tsv`, `<s>/subsume-trace-min1.tsv.gz`,
`<s>/subsume-trace-alone-100tests.tsv.gz`.

The maxima are identical because they are reached during the **standard-library boot**, which
all three runs do — §1.8 shows the refused module's own check is far smaller. On the CORRECTED
nanosecond figures the two whole-environment escape walks together cost **49.2 s** in a
12-property suite whose untraced wall clock is **184 s** — `:648` **45.4 s** and `:365`
**3.7 s** (§0.2). That is a quarter of the run and a real performance item, and it still cannot
be the difference between a run that answers and one that does not: the SAME `:648` share
(23 %) is paid by the `bin/ermine` run that refuses the module in 0.07 s.

**Does the path go through `labelDecide`, and does any budget count?** `labelDecide` spends
**9–33 decision nodes in an entire run** (9 / 9 / 10 / 33 across the four traced runs) and `rowSoundBudgetHits` is **0**; the draw budget
(`-Dermine.solveBudget`, default 20,000, `smallcanon` order) never fired either
(`solveBudgetHits = 0`). **Neither existing budget covers this, and neither is being
exhausted.** The refutation comes from the cheap bare label check (the twelve `slbl` records
of §1.4), not from the decision procedure.

### 1.8 The escape check ON THE REFUSED PROGRAM ITSELF

The maxima of §1.7 belong to the parallel **library loader** (thread 74 of the `bin/ermine`
run, `hm.types.size` 1,566 at t = 21.8 s). The refused module's own check is the last 50 ms of
that run, on the main thread, and is tiny:

```
awk -F'\t' '$2==1 && $3=="escape"' <s>/rowtrace/cli-bad.subsume.tsv
  ->  8 escape checks, t = 21,971..22,021 ms
      hm.types.size  mean 6.0, max 13
      kind-walk tree nodes max 21
```

**Eight escape checks over a thirteen-entry substitution is what the "escaping-skolem check"
costs on the program Part B says it hangs in.**

### 1.9 `trace-ab.py`: does the id base change the PATH? (brief step 5)

The brief asks for the two row traces compared with `trace-ab.py`. A segment-paired diff of
the hanging run against the finishing one is not available — the hanging run is a hundred
repetitions of the finishing one, so the segments do not pair. What IS available, and is the
question underneath it, is the same program at two **id bases**, both of which finish:

```
java ... -Dermine.rowTrace=<s>/rowtrace/base0.trace  -cp <s>/harness:... IdBase 0  <s>/repro/Bad.e
java ... -Dermine.rowTrace=<s>/rowtrace/base64.trace -cp <s>/harness:... IdBase 64 <s>/repro/Bad.e
tracker/tools/trace-ab.py <s>/rowtrace/base0.trace <s>/rowtrace/base64.trace --name idbase-0-vs-64
```

```
idbase-0-vs-64  segments=54258  CONTENT-DIFFERS=41278  KINDCOUNT-DIFFERS=10436
                PERMUTATION-ONLY=2544  sinmoved=54258
```
(`<s>/rowtrace/trace-ab-0-64.txt`, `<s>/rowtrace/ab-runs.txt`.)

So shifting the base by 64 blocks of 1,024 ids moves **76 % of all 54,258 segments in
content** — the E11c order-dependence is real and pervasive across the library boot. And yet:

* the **verdict is the same**: `unsatisfiable at field 'Bad.startDate'` in both, 174,832 vs
  174,829 records, same wall time;
* the **refused module's own trace is unchanged** (`<s>/rowtrace/base0.trace.gz`, `base64.trace.gz`), record kind for record kind —
  `59 sat, 54 learn, 46 svar, 38 scon, 34 sin, 33 solve, 33 rsound, 28 inpart, 24 in, 24 ex,
  19 step, 12 slbl, 12 ramb, 9 splice, 9 detm, 5 concr` on **both** sides;
* the twelve `slbl` label-check records are **identical once ids are erased**
  (`diff <s>/rowtrace/slbl0.txt <s>/rowtrace/slbl64.txt` is empty).

**The order-dependence changes the path taken through the library and changes nothing about
this refusal.** It is why the defect hid; it is not the defect.

### 1.10 One test = one library boot, counted

The default-100 run again, traced, killed by its own 600 s deadline
(`<s>/repro-default-traced.log`, `<s>/subsume-trace-default.tsv.gz`): **218,006 escape checks** in
407 s of wall clock, `hm.types.size` max **1,566**, **0 cycles**, and the whole of `:648`
costing **603 ms** (kindVars) + **341 ms** (fskvs) — under a second, in a run that was killed
for not finishing.

Broken down by the thread each ScalaCheck property runs on, against the **9,531** escape
checks one complete `bin/ermine` library boot costs (§1.7):

| thread | escape checks | boots |
|---|---|---|
| 117 | 56,201 | 5.90 |
| 111 | 47,685 | 5.00 |
| 112 | 28,611 | 3.00 |
| 123 | 28,611 | 3.00 |
| 118 | 9,537 | 1.00 |
| 125 | 9,537 | 1.00 |
| 115 | 9,495 | 1.00 |
| 114 | 9,443 | 0.99 |
| 116 | 9,443 | 0.99 |
| 119 | 9,443 | 0.99 |

Every count is a whole multiple of **9,537** to within half a percent, and 9,537 is what one
complete `bin/ermine` library boot costs. That is the measurement behind §4: **one
`loadStatements` — one ScalaCheck test — is one library boot.** The properties that load once
sit at one; those that load several times (the A3 zone loops call `defAndEval` per zone) sit
at three or five; and the B1 property accumulates one more boot per test for as long as it is
allowed to run, which the shipped `minSuccessfulTests = 100` makes a hundred.

(With tracing on each test is about three times its untraced cost, which is why the run was
killed at five boots on its busiest thread rather than at a hundred. The untraced per-test
figure is the 9.1 s of §6.2.)

---

## 2. Reading the walk before instrumenting it (brief step 2), settled with line references

### 2.1 Does `VarT(v) => v.extract.vars` follow the variable's BINDING or its KIND?

**Its KIND. The orchestrator's reading is CONFIRMED; Part B's H2 wording loses.**

`VarT(v)` carries `v : TypeVar = V[Kind]` (`Type.scala:238`, `case class VarT(v: TypeVar)`).
`V` is `case class V[+A](loc, id, name, ty, extract: A)` (`Vars.scala`), so `v.extract` is the
variable's **kind annotation**, an ordinary `Kind`, and `.vars` there is `Kind.vars`, whose
only recursive case is `ArrowK.vars = i.vars ++ o.vars` (`Kind.scala:58`) and whose variable
case is `VarK(v).vars = Vars(v)` (`Kind.scala:65`). `HasKindVars` for `V[A]`
(`Kind.scala:134-135`) is the same pattern. **Nothing in either `vars` recursion reads
`hm.types`**; the only place a binding enters at all is `mapHasKindVars.vars`
(`Kind.scala:124-125`), which iterates the substitution's *values* once, non-recursively.

Two further arguments, and the measurement, agree:

* `Type`, `Kind` and `V` are strict case classes, so a term whose object graph contains a
  cycle **cannot be constructed** — there is no by-name field and no mutable one to tie a
  knot with. `vars` recurses on structure only, so it terminates on every value that exists.
* The instrumentation marks nodes as in-progress with an `IdentityHashMap` while it replays
  the same recursion; a back-edge would set `cyclic`. It was **false in every one of the
  ~186,000 walks** of §1.5. Part B's H2 is dead twice over.

### 2.2 Where is the traversal forced, and how many times?

There are **two** traversals per `hm.kindVars.filter(...)`, not one:

1. **Construction is eager.** `Vars.++` (`Vars.scala:22-24`) allocates one closure and is
   O(1) — but building `vars(AppT(e1,e2)) = vars(e1) ++ vars(e2)` first *recursively builds
   both operands*, so merely forming the view walks every node of every type in `hm.types`.
   There is **no memo table and no identity check**, so the cost is the **tree** size: a
   shared subterm is re-entered once per path that reaches it. `SubstEnv.kindVars`
   (`Subst.scala:169`) is `Kind.kindVars(kinds) ++ Kind.kindVars(types)`, i.e. two such
   constructions joined by one lazy node; `mapHasKindVars.vars` (`Kind.scala:124-125`) is a
   `foldRight` that does this for every entry of the map.
2. **`.filter` then walks it again, strictly.** `Vars` extends `ForeachIterable`
   (`ForeachIterable.scala:17-21`), whose `iterator` **materialises the whole variable Vector**
   by running `foreach`, i.e. `Vars.apply(Set(), f)` — the closure tree is traversed a second
   time with an immutable seen-`Set` threaded through it, and only then is the predicate
   applied.

The two phases are visible in the samples: `sample-5`'s frames
(`Type$$anon$3.vars <- Kind$.kindVars:96 <- SubstEnv.kindVars:169 <- subsumeType:648`) are
**construction**; `probe-b`'s 83 nested `Vars$$anon$1.apply(Vars.scala:23)` under
`Type$.fskvs:666` are **traversal**.

* **Is the `++` at `:648` strict?** Yes — by then both operands are the strict collections
  `.filter` returned, and `Iterable.concat` on them is strict. It is not the expensive part.
* **Does anything re-evaluate `hm.kindVars`?** No. `fskvs` and `kindVars` are `def`s on
  `SubstEnv` (`Subst.scala:168-169`) and each is mentioned once at `:648`; `escs` is consumed
  only by `nonEmpty` at `:649` (the other use, `:657`, is commented out).
* **Evaluation order.** `hm.fskvs.filter(...)` is fully evaluated **before** `hm.kindVars`,
  which is why a sample can be in either.
* The same whole-`hm.types` walk is run by `checkSkolemEscape` (`Subst.scala:365`,
  `fskvs(hm.types -- mask)`), from `inferAltTypesPrime:1171` — once per alternative, not once
  per binding. Two of the six RUNNABLE samples were there, not at `:648`.

---

## 3. What was built

**One file changed: `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala`**
(+239 / -2; `git diff --stat`). Three call sites and one new top-level object, all behind
`-Dermine.subsumeTrace` (**default OFF**, `val`-read once, the `RowTrace.enabled` idiom):

| site | change |
|---|---|
| `subsumeType` entry (patched `:616-618`; pristine `:613`) | `val stid = SubsumeTrace.enter(hm, sig)` — returns `0L` and does nothing when off; one line per call, so "one call that never returns" and "many calls that each return" (which produce the SAME jstack) are told apart by counting |
| before the escape check (patched `:653`; pristine `:648`) | `SubsumeTrace.atEscape(stid, sks, sts, hm)` — sizes, budget counters, and the DAG-time cost model |
| the escape check itself (patched `:654-655`) | each half wrapped in `SubsumeTrace.phaseFskvs(...)` / `phaseKindVars(...)`, an `inline def` identity when off: same expression, same order, evaluated exactly once, **nothing logged inside the timed region** |
| `checkSkolemEscape` (patched `:367`; pristine `:365`) | `SubsumeTrace.cse(hm)(...)` around `fskvs(hm.types -- mask).filter(ss(_))`, counted and summed always, logged per call above `-Dermine.subsumeTrace.cseMs` (default 50 ms) |

**Two changes the S0 review required, both applied (findings 1, 4 and 5).**

* **Timing is nanoseconds, accumulated.** `phaseFskvs`/`phaseKindVars`/`cse` each add to an
  `AtomicLong` of nanos and to an `AtomicLong` of max-nanos; the totals ride on the `escape`
  record. The first version logged `nanos / 1000000L` per call and the report summed those
  integers — a floor-sum over calls that are 96.7 % sub-millisecond, understating `:648` by
  **21x** in the suite and **15.7x** in the CLI boot. §0.2 is the correction.
* **`enter`, `atEscape`, `phaseFskvs`, `phaseKindVars` and `cse` are `inline def`s** whose
  first act is `if (!enabled)`, so with the flag OFF the by-name body is inlined at the call
  site and **no `Function0` is allocated** on a path that runs 171,286 times per suite
  (finding 4.1).
* **The `Walk` cost model and its `measure` thread are GONE from `Subst.scala`** (finding 5,
  option (b), and finding 4.2's abandoned 512 MB-stack thread with it). They were 110 lines of
  hand-copied `Type.vars` with nothing pinning them, and their answers — `treeKV`/`dagKV`/
  `depthKV`/`cyclicKV`, i.e. 0 cycles in 984,400 walks and tree/DAG ≤ 4.39 — are already
  recorded in §1.5/§1.7 and were re-derived independently by the reviewer. The model is
  preserved verbatim as **`<s>/subsume-walk-model.patch`** (100 lines) for whoever needs a
  walk-shape question answered again; re-apply it inside `object SubsumeTrace`. **The landing
  surface is therefore the four counters and nothing else.**

**What the instrumentation costs when it is ON, and why that does not distort the figures.**
*(This applies to the FIRST version, which produced the four `.tsv.gz` traces; the corrected
build has no measurement thread and writes two records per call instead of six, and its suite
run is 191 s against 184 s untraced — 1.04x.)* Each `atEscape` started a short-lived
measurement thread and each record was written with a flush, so a traced run's WALL CLOCK is **1.8x** an untraced one (the 12-property suite:
336 s traced against 184 s untraced — the S0 review's finding 3 corrected an earlier
"roughly three times" in this sentence, which its own two numbers contradicted). Every number quoted in this report is therefore either a
COUNT or a `System.nanoTime` interval taken INSIDE `phase`/`cse` with the logging outside the
timer — never a share of a traced run's wall clock. The untraced timings of §6 are the ones
used for cost claims.

Other artefacts, all under `<s>/` and none in the repository:
`repro/Bad.e`, `repro/Good.e` (the B1 program and its twin as modules);
`harness/IdBase.java` + `.class` (the scratch id-base fixture of §1.6);
`stacks/`, `idsweep/`, `rowtrace/`, `corpus-base/`, and the `.tsv` traces.

---

## 4. What actually takes the time, and why the sampler kept landing on `vars`

Each ScalaCheck *test* of the B1 property runs `ErmineFixture.typeChecks`, which calls
`loadStatements` (`TestErmine.scala:133-157`): it evicts the dynamic `Test` literal from the
process-global `Session.depCache`, calls `Session.load(file)`, and evicts it again — under
`ErmineFixture.literalLock`. `mkEnv` is a copy of `baseEnv`, and the failing load never writes
back (only `loadModules` does, `TestErmine.scala:102-114`), so **every test re-reads and
re-checks the module's whole import closure**. The cost of one test is therefore of the order
of a library boot, not of the four-line program:

* `bin/ermine` spends **12.9 s booting the library and 0.06 s on `Bad.e`**
  (`<s>/repro/cli-run1.log`);
* the escape-check counts of §1.7 say the same thing from the other side: one
  `bin/ermine` boot is 9,531 escape checks, and the 12-property suite is 171,286 — about
  14,000 per property, i.e. each property re-does a large fraction of a boot;
* the jstack samples of §1.2 catch the B1 thread in `SurfaceParsers.module`
  (`sample-8`, deepest frame `Parsing.blockComment(ParsingUtil.scala:148)` — it is parsing a
  library module) and blocked on the literal lock as often as in the solver or the walk;
* and the direct measurement: **9.1 s per additional test** (§6.2) against a `bin/ermine`
  library boot of **12.9 s** — about 70 % of a boot, repeated a hundred times.

Two details of the fixture make each test pay in full:

* the B1 properties pass `onlyTest = Map("Test" -> fx.all)` (`TestDateAndScan.scala:46`), and
  `baseEnv` already lists `"Test" -> CheckMethod.Interface` (`TestErmine.scala:86`), so
  `loadStatements`' write-back call `loadModules(imports.keySet)` is a **no-op** — the
  modules that actually cost (`Prelude`, `Relation.Op`, `Syntax.Relation` and their closure)
  are imported by the generated `module Test` source and are loaded into the *copy*, which is
  thrown away;
* the fixture's `SessionEnv` is built with `_useInterface = Some(false)`
  (`TestErmine.scala:83-84`), so there is no `.ei` short-circuit: every test **re-type-checks**
  the closure. `Session.depCache` is process-global and saves the *parse* (`Session.scala:110,
  403-412`), but `Dep.make` still runs `loadModule` for every import a session has not
  already loaded (`Session.scala:592-608`, `:872-875`).

So the un-returning property is **100 library-scale checks**, each of which terminates. That
is why the sampler finds the thread in a different part of the checker every time, and why
`Subst.scala:648` — a fixed share of every check, about a quarter of it on the corrected
figures (§0.2) — still comes up in only one of thirty dumps: the walk is fast per call
(median well under a millisecond) and the check is long, so a sampler finds the thread almost
anywhere in it.

---

## 5. THE TITLE QUESTION, AND WHICH OF H1/H2/H3 SURVIVE

### 5.1 The answer

> *Does the checker terminate on a refused row program?*

**YES**, on every measurement this stage could take.

* The escape check at `Subst.scala:648` returned on **every one of the 274,194 calls** traced
  across the three runs of §1.7 (9,531 + 171,286 + 93,377), the slowest single call being
  **5.8 ms** on the corrected build (29 ms on the first). In the whole 12-property suite
  `:648` costs **45.4 s** and `checkSkolemEscape:365` another **3.7 s** — 49.2 s of checker
  work in a suite whose untraced wall clock is **184 s** (§6), i.e. about **27 %**. *(The
  first version of this sentence said "at most about 3 %", from a floor-summed figure; see
  §0.2. The share is large, and it is the same share in the run that refuses the module in
  0.07 s — so it is a cost, not a hang.)*
* The B1 program itself is REFUSED — in 0.06 s by `bin/ermine` (which is what the LSP runs),
  at every one of the seventeen `Supply` id bases swept in §1.6, and inside the fixture when the
  property is asked for one test.
* This is a **measurement, not a theorem**. The theorem is S1a's, and §2.1 says what it should
  be: `vars` recurses on the structure of values built by strict case classes, so the term
  graph is acyclic by construction and the structural recursion terminates. The invariant to
  state is *acyclicity of the term graph*, and it is not a solver invariant at all — it is a
  property of the constructors. S1a should either prove that and note that the interesting
  question is the COST, or produce the witness that refutes it.

### 5.2 H1 — "finite but explosive": **REFUTED**

`restrictTypes` leaves nothing enormous behind. Over 274,194 escape checks: `hm.types.size`
never exceeded **1,566** (mean 272, median 64); the kind walk never visited more than
**35,921** nodes (mean 6,779, median 1,101) against a DAG of 16,328; the **tree/DAG ratio
never exceeded 4.39** (mean 1.92, p99 2.57), so there is no exponential unfolding of a shared
subterm either — the fourth mechanism the brief asked me to look for **is not present**. The
walk depth never exceeded 23. And the maxima are **identical** in the run that refuses the
module in 0.06 s and in the run that does not return (§1.7), which by itself rules the escape
check out as the difference.

### 5.3 H2 — "cyclic substitution": **REFUTED, twice**

Part B's wording — *"`VarT(v) => v.extract.vars` (`Type.scala:653`) follows a variable's
binding"* — is **wrong about the code**: `v.extract` is the variable's KIND ANNOTATION
(`V[Kind]`), `Kind.vars` bottoms out at `VarK(v).vars = Vars(v)` (`Kind.scala:65`), and
neither `vars` recursion ever reads `hm.types` (§2.1). The orchestrator's reading in
`SUBSUME-PLAN.md` is confirmed. Independently, the instrumentation marks nodes in progress
with an `IdentityHashMap` and reports a back-edge: **0 cycles in 984,400 identity-marked
walks** — two per escape record over all 492,200 records of the four traced runs. And structurally, `Type`/`Kind`/`V` are strict case
classes with no by-name or mutable field, so a cyclic term cannot be constructed at all.
**There is no occurs-check hole here to fix**, and S1b should not expect to find a cyclic
binding on this path.

### 5.4 H3 — "the walk is the victim": **SURVIVES, with a correction**

The walk is indeed the victim and not the cause. But H3's proposed mechanism — *"the rejection
path itself grows the environment or diverges BEFORE `subsumeType`"* — is **also refuted in
its first half**: the environment does not grow (§5.2), and `hm.types.size` at the escape
check is *smaller* late in a check than during the library boot. Nor does the path diverge:
one check of the B1 module terminates everywhere it was run.

What is true is the weaker and more prosaic half: **`:648` is only where the thread was
sampled.** The thread is equally often in `Subst.solve`'s queue (`sample-4`, `sample-7`), in
`checkSkolemEscape`'s environment walk (`probe-a`, `probe-b`), in the parser (`sample-8`), or
BLOCKED on the fixture's literal lock (4 of 12 samples) — because the harness is running the
whole check **one hundred times** (§0, §4). `Subst.scala:648` is about a quarter of each check
on the corrected figures (§0.2) and yet appears in one of thirty dumps — because it is spread
over 171,286 sub-millisecond calls rather than concentrated in one long one, which is itself
evidence against "one call that never returns".

### 5.5 What the defect actually is

`ErmineFixture.no` (`TestErmine.scala:220-223`) rewrites `Prop.Proof` to `False` and `False`
to `True`. A rejection property therefore reports **passed**, never **proved**, so ScalaCheck
does not short-circuit and runs `minSuccessfulTests` tests — **100**, confirmed by reflection
against the shipped jar: `scalacheck 1.15.4 Test.Parameters.default: minSuccessfulTests=100
workers=1` (`<s>/scparam/result.txt`). Each of those tests re-reads and re-checks the module's
whole import closure (§4). The other eleven properties in the suite return `Prop.Proof` and
stop at one test, which is exactly the "11 of 12 finish" signature.

Three consequences for the programme, stated plainly because the prompt says the document
loses when a measurement contradicts it:

1. **S2's premise does not hold as written.** There is no termination defect at `:648` to fix.
   A cheaper or memoised escape check is a *performance* change and not a fix for a hang — but
   it is a **much larger** performance change than the first version of this report said, and
   it is at the **opposite site**. Corrected (§0.2): `:648` costs **45.4 s of a 184 s suite
   run (24.7 %)**, two whole-environment walks on each of 171,286 calls;
   `checkSkolemEscape:365`, one walk per ALTERNATIVE from `inferAltTypesPrime:1171`, costs
   **3.7 s over 40,013 walks (94 µs each)**. **`:648` is 12.1x `:365`, not half of it.** The
   first version of this sentence said the reverse, from a floor-summed figure, and three
   landed documents repeated it — §0.2 carries the replacement sentences. Either way this is
   roadmap P7 Step 1's territory (now ticketed in `tracker/TICKET-perf-type-inference.md`),
   not this programme's.
2. **S3's premise does not hold either.** A budget bounds a computation that may not
   terminate; this one terminates, and neither existing budget (`rowSound`, `solveBudget`) so
   much as counted (§1.7). Budgeting `:648` would add a failure mode where there is currently
   none.
3. **The LSP hazard Part B names is not reproduced.** `lsp/Resident.scala:104-108` builds its
   resident session with `_typeCheck = Some(true)`, `_useInterface = Some(false)` and
   `Prelude`/`Layout` already loaded, and `checkFile` (`:232`) checks one file against it —
   which is the `bin/ermine` shape, warm. On this program that is **0.06 s**, at every id base
   swept (§1.6). Nothing in this stage's evidence supports "a server that pins a core forever"
   for this input. The general point — that `lsp/Diagnostics.scala` runs a check to completion
   on the dispatch thread with nothing to cancel it — stands as a design risk, and is already
   ticketed out of scope by the prompt.

The thing that *is* worth fixing is in the test harness, and it is one line: a rejection
property should assert the rejection once (`Prop.proved` after catching `Death`) instead of
asking ScalaCheck for a hundred identical library-scale checks. That is a `TestErmine.no`
change, outside this programme's brief, and it is why the property is already gated behind
`-Dermine.test.dateDiffReject=true` on `json-encode` (commit dd9e0316).

---

## 6. Gates and baselines

S0 changes nothing that ships: the only edit is behind `-Dermine.subsumeTrace`, **default
OFF**, and no verdict, no default and no trace record moved. No Tier 1 is owed for a stage
that adds a flag nobody reads. What is recorded here are the **baselines the later stages
need** (brief step 7) and the timings the cost claims rest on.

### 6.1 Baselines on this tree

| gate | command | result | log |
|---|---|---|---|
| compile | `sbt core/compile core/copyResources` | green | `<s>/compile.log`, `compile2.log`, `compile3.log` |
| corpus verdicts | `tracker/tools/corpus-run.sh --batch <s>/corpus-base` + `corpus-verdicts.py` | **89 LOADED, 79 REJECTED, 0 UNKNOWN, 168 total** — exactly the prompt's figure, unmoved | `<s>/corpus-base.log`, `<s>/corpus-base/` |
| `TestLoopTrace` (no model binary) | `sbt 'core/testOnly *TestLoopTrace'` | 3 / 3, but the model-agreement property **SKIPS itself** — `.lake/build/bin/looptrace` is absent in this worktree, so this is **NOT a baseline**: a self-skipping property is green precisely when the model is missing | `<s>/looptrace-base.log` |
| `TestLoopTrace` (with the model binary) — **THE BASELINE** | same, `-Dermine.looptrace=<wt-json-wrappers>/tracker/lean/.lake/build/bin/looptrace` | **720 solves / 720 segments / 720 agree**, `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`, both negative controls firing (id base +1: 46 of 720 disagree; `--flags=nongen`: 58 of 720); `Total 3, Failed 0` — identical to `tracker/GATE-POLICY.md:14`'s recorded 720/720. **Run by the S0 REVIEWER, not by me**: my own attempt was queued and killed at the budget (§8.5) | `<r>/looptrace-bin.log`, `<r>` = `scratch-subsume/review-s0/` |

`.ei` hygiene: `find core -name '*.ei'` is **0**. The 129 interfaces the `useInterface`
experiment of §1.3 wrote under `core/target` were deleted. `tracker/repl-classpath.txt` is
untouched; `target/ermine-classpath` was regenerated locally and is git-ignored.

### 6.2 The cost of the property, measured (untraced, one sbt JVM per point)

`sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan -- -minSuccessfulTests N'`
(`<s>/nscale-summary.txt`, per-run logs `<s>/nscale-N.log`):

| N (tests of the B1 property) | wall | B1 passed | marginal cost per test |
|---|---|---|---|
| 1 | 184 s | yes | — |
| 2 | 191 s | yes | 7.0 s |
| 4 | 209 s | yes | 9.0 s |
| 8 | 249 s | yes | 10.0 s |
| 16 | 321 s | yes | 9.0 s |

The slope is **9.1 s per additional B1 test** (from N=1 to N=16), so the shipped default of 100 tests costs about **1088 s = 18 min** of pure repetition on top of the 184 s the other eleven properties need. That is the "28 CPU-minutes" of Part B.

### 6.3 Raw result lines from the remaining runs

* `NSCALE DONE`
* `looptrace rc=0 : [success] Total time: 2 s, completed Sep 16, 2026, 4:47:17 PM`
* `solveDet-defaultN rc=124 wall=361s props=11 b1passed=0`
* `defaultN-traced KILLED at budget (wall ~408s of its 600s deadline; 9/12 properties green, B1 still running)`
* `ns-min1 (corrected nanos) rc=0 wall=195s : Passed: Total 12, Failed 0 -- :648 = 45.42 s (fskvs 21.07 + kindVars 24.35), :365 = 3.75 s / 40,013 calls`
* `ns-cli  (corrected nanos) : Bad.e REFUSED 0.07 s -- :648 = 2.79 s of a 12.2 s boot (23 %), :365 = 0.24 s / 2,226 calls`
* `flag-OFF rc=0 wall=189s : Passed: Total 12, Failed 0 -- ZERO instrumentation records emitted`

(`<s>/looptrace-base.log`, `<s>/looptrace-base2.log`, `<s>/solvedet-default.log`,
`<s>/solvedet-n16.log`, `<s>/repro-default-traced.log`, `<s>/filter-n1.log`,
`<s>/filter-n100.log`, `<s>/control-twosuites.log`.)

### 6.4 Every command, with its log

All from the worktree root with
`PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`.

| what | command | log |
|---|---|---|
| build | `sbt core/compile core/copyResources` | `compile*.log` |
| the hang, alone | `sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'` | `repro-alone.log`, `stacks/` |
| thread samples | `jcmd <pid> Thread.print` every 30 s, 12 samples + 2 probes | `stacks/sample-*.txt`, `stacks/probe-*.txt` |
| the program as a module | `bin/ermine <s>/repro/Bad.e` (and `Good.e`) | `repro/cli-run1.log` |
| interfaces on | same, without `-Dermine.useInterface=false`, twice | `cli-useinterface.log` |
| row trace, favourable | `java -Dermine.rowTrace=... Console <s>/repro/Bad.e` + `rowtrace-summary.py` | `rowtrace/cli-bad.{log,trace.gz,module.trace}` |
| instrumented, default N | `sbt -Dermine.subsumeTrace=true -Dermine.subsumeTrace.out=... 'core/testOnly ...TestDateAndScan'` | `subsume-trace-alone-100tests.tsv.gz` |
| instrumented, N=1 | same `+ -- -minSuccessfulTests 1` | `repro-min1.log`, `subsume-trace-min1.tsv.gz` |
| id-base sweep | `java -cp <s>/harness:... IdBase <k> <s>/repro/Bad.e`, k in 16 values | `idsweep/` |
| cost scaling | `sbt 'core/testOnly ...TestDateAndScan -- -minSuccessfulTests N'`, N=1,2,4,8,16 | `nscale-*.log` |
| corpus baseline | `tracker/tools/corpus-run.sh --batch <s>/corpus-base` | `corpus-base.log` |
| model gate | `sbt -Dermine.looptrace=<wrappers>/tracker/lean/.lake/build/bin/looptrace 'core/testOnly *TestLoopTrace'` | `looptrace-base2.log` |
| id-base A/B | two traced CLI runs (`IdBase 0` / `IdBase 64`) + `tracker/tools/trace-ab.py` | `rowtrace/base{0,64}.trace`, `rowtrace/trace-ab-0-64.txt` |
| ScalaCheck default | reflection against the shipped `scalacheck_3-1.15.4.jar` | `scparam/result.txt` |
| **corrected timings, CLI** | `java -Dermine.subsumeTrace=true -Dermine.subsumeTrace.out=… Console <s>/repro/Bad.e` on the fixed build | `ns-cli.log`, `ns-trace-cli.tsv` |
| **corrected timings, suite** | `sbt -Dermine.subsumeTrace=true -Dermine.subsumeTrace.out=… 'core/testOnly …TestDateAndScan -- -minSuccessfulTests 1'` | `ns-min1.log`, `ns-trace-min1.tsv`, `ns-summary.txt` |
| flag-OFF check | the same suite with no `-Dermine.subsumeTrace` | `flagoff.log` |

---

## 7. The E11b connection (brief step 8) — one paragraph, and no reopening

E11c (`tracker/loopmodel/E11c-SOLVEDET.md`) established that the residual the solver publishes
is a function of the **absolute id base**, through two reads: `SCC.scala:46`'s Tarjan driver
over an id-keyed `Map` (and `V.hashCode` *is* the id), and `Subst.scala:1630`'s
`q.expand.toList`, read out of a finger tree whose measure is `RHS.hashCode` — a MurmurHash of
raw ids, not monotone, so a constant shift of the base permutes the saturated list that
`Subst.reduce`'s non-confluent right fold then consumes. That is the same order-dependence
that hid this defect: every ScalaCheck test of the B1 property runs at a **different id base**
(`Supply.getBlock` advances monotonically for the life of the JVM, `Supply.scala:5-16`), and
so does the same property run after a different set of suites — which is exactly the
"11 of 12 finish, and which one hangs depends on what ran before it" shape reported on
2026-09-16. It is the reason the defect *hid*; it is **not** the cause of the non-return, which is the
100-fold repetition of §0 — and on the evidence of §1.6 and §6 the id base does not even
change the per-test cost measurably. This stage does not reopen E11b: the E11b residual
nondeterminism is parked by the user, `-Dermine.solveDet` stays default OFF, and the
`-Dermine.solveDet=true` run recorded in §6 is one run for information only.

---

## 8. Open questions, and what the next stages need from S0

1. **For S1a.** The invariant to state is NOT a solver invariant. `Type.typeHasKindVars.vars`
   and `Type.typeHasTypeVars.vars` recurse on the structure of terms built by **strict case
   classes** (`Type.scala`, `Kind.scala`, `Vars.scala`), consult no substitution, and were
   measured acyclic in 984,400 identity-marked walks (§5.3). The interesting theorem is
   therefore about **cost**, not termination: the walk pays the **tree** size of `hm.types`
   (no memo table, `Vars.++` construction is eager, `.filter` materialises through
   `ForeachIterable.iterator`), and the measured tree/DAG ratio never exceeded **4.39**
   (§5.2). The `sks`/`sts`-restricted variant the brief proposes is still worth proving
   equivalent — it is the honest form of the P7 Step 1 optimisation — and on the CORRECTED
   figures it is worth **45.4 s of a 184 s suite run** rather than the ~2 s the first version
   of this report quoted (§0.2). It is still not a termination fix, and S1a's theorem, not this
   number, is why.
2. **For S1b.** Do not expect a cyclic binding on this path: there is none, and there cannot
   be one in an immutable strict-constructor term (§5.3). The rejection path this input takes
   is the **bare row-label check** — twelve `slbl` records, the refutation being
   `startDate: the whole contains it but no part does`
   (`<s>/rowtrace/cli-bad.module.trace`) — and it reaches a verdict in 0.06 s. `labelDecide`
   spends 9–33 nodes in an entire run and no budget ever fires. If S1b wants an unsatisfiable
   input that stresses the loop, this one does not.
3. **Still open, and NOT answered by this stage.** Whether some *other* id base or some
   *other* refused row program can make one check diverge. The sweep of §1.6 covered seventeen
   bases in the CLI environment and found none; the fixture environment was not swept
   (it costs a suite run per base). A generator of unsatisfiable row programs — the one
   brief-S2 asks for — remains the right instrument, but it should be pointed at the SOLVER
   with a deadline, not at `:648`. **Add to it one repeat run at id base 16**, the 26.79 s
   library boot of §1.6 — the only datum in this stage where an id base doubles anything.
4. **A reproduction the reviewer and S2 can rerun** (brief step 6). There is no program
   smaller than B1 that hangs, because B1 does not hang: `<s>/repro/Bad.e` is the whole
   program as a module and `bin/ermine` refuses it in 0.06 s. The **property** is what to
   reproduce, and the pair is
   ```
   # the hang: times out, and the log shows the other 11 properties green
   timeout 200 sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan -- -f REJECTED -minSuccessfulTests 100'
   # the control: the SAME property, one test, passes
   sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan -- -f REJECTED -minSuccessfulTests 1'
   ```
   (`<s>/filter-n100.log`, `<s>/filter-n1.log`; the `-f`/`-propFilter` and
   `-s`/`-minSuccessfulTests` flags are ScalaCheck 1.15.4's, verified against the shipped jar).
   The `bin/ermine` one-liner — `bin/ermine <s>/repro/Bad.e` — is the sub-second version and
   the one that matters for the LSP.
5. **NOT DONE — the four things the brief asks for that this stage did not finish** (the
   3 h budget ran out; each is queued rather than blocked, and none of them can change §5's
   verdict, which rests on measurements already taken):
   * STILL NOT RUN — the **property-filtered reproduction pair** (`-f REJECTED` at `-minSuccessfulTests` 100
     and 1) was written and queued but killed at the budget — `<s>/filter-n1.log` and
     `<s>/filter-n100.log` are empty. The unfiltered equivalents ARE measured
     (`<s>/nscale-*.log`, `<s>/repro-min1.log`), so the reproduction stands; only the
     one-property convenience form is unrun. `-f`/`-propFilter` was verified to exist in the
     shipped `scalacheck_3-1.15.4.jar`.
   * the **"another suite ahead of it in one JVM" control** — queued and killed by me;
     **the S0 REVIEWER ran it** (`<r>/control-N1.log`, `<r>/control-N8.log`): `TestScopes` +
     `TestDateAndScan` is 177 s at N=1 and 257 s at N=8, a marginal **11.4 s per B1 test**
     against **9.3 s** alone. A preceding suite in the same JVM does **not** make the
     repetitions cheaper — it makes them marginally dearer. That closes §4's open half: there
     is no cheap full-suite path for this property, so nothing needs to explain one.
   * `TestLoopTrace` **with** the model binary — queued and killed by me; **the S0 REVIEWER
     ran it**, 720/720/720 with both negative controls firing (`<r>/looptrace-bin.log`), and
     that is the baseline §6.1 now carries. My own `<s>/looptrace-base2.log` does not exist;
     the first version of §6.1 cited it, which was the review's finding 2.
   * STILL NOT RUN — `-Dermine.solveDet=true` was run only at the **default** N, where it timed out exactly
     as the flag-off run does (361 s, 11 of 12); the informative comparison
     (`solveDet=true` at `-minSuccessfulTests 16` against the 321 s of §6.2) was queued and
     killed, `<s>/solvedet-n16.log` is empty.
6. **FIXED, not open** (S0 review finding 4). The `phase`/`cse`/`enter` wrappers took their
   argument by name and allocated a `Function0` per call even with the flag off, three per
   `subsumeType` on a path that runs 171,286 times a suite; they are now `inline def`s whose
   first act is `if (!enabled)`, so the body is inlined at the call site and nothing is
   allocated. The `measure` helper — which abandoned a live 512 MB-stack daemon thread on a
   deadline hit — is gone with the `Walk` model (§3). **A flag-OFF run of the suite confirms
   the facility is silent and the result unchanged**: `<s>/flagoff.log`, zero instrumentation
   records, `Total 12, Failed 0`.

---

## Landing gates (orchestrator's gate run, 2026-09-16)

Run by the orchestrator on the tree being landed — `~/research/ermine/ermine-scala-wt-subsume-s0`
at **00abe6e6** (branch `subsume-s0`, merged with `subsume-termination`) — with the pre-change
tree `~/research/ermine/ermine-scala-wt-subsume` at **7f2a00a5** (branch `subsume-termination`,
Scala byte-identical to `scala3-migration` 478a369c) as the A side of every differential. The
only Scala difference between the two trees is `Subst.scala` **+157 / −2**, all of it behind
`-Dermine.subsumeTrace` (**default OFF**). Logs, traces and snapshots are under
`<g>` = `/home/dmitry/research/ermine/scratch-subsume/gates-s0/`. Nothing was committed, and the only file either tree gained is this section: `tracker/repl-classpath.txt` was regenerated from each worktree's own `target/ermine-classpath` per GATE-POLICY's worktree rule and **restored afterwards** (`git checkout`), so both trees are otherwise clean and `find core -name '*.ei'` is 0 on both.

**Tier 1 was run in full even though S0 ships no behaviour change**, because `Subst.scala` is in
the diff and the policy keys Tier 1 on the file, not on the intent.

| # | gate | command | result | log |
|---|---|---|---|---|
| a | compile (Tier 0) | `sbt core/compile core/copyResources` | **rc=0**, `[success] Total time: 2 s` + `0 s` (tree already built at 17:40; `SubsumeTrace$.class` present in `core/target/scala-3.3.8/classes`) | `<g>/compile-s0.log` |
| b | model agreement (Tier 0) | `sbt -Dermine.looptrace=<wt-json-wrappers>/tracker/lean/.lake/build/bin/looptrace 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**; `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; both negative controls firing (id base +1: **46 of 720**; `--flags=nongen`: **58 of 720**); `Passed: Total 3, Failed 0, Errors 0, Passed 3`. Identical to §6.1's baseline and to `GATE-POLICY.md:14` | `<g>/looptrace-test.log` |
| c | corpus verdicts (Tier 0) | `tracker/tools/corpus-run.sh --batch <g>/corpus-s0` then `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**; the per-file verdict **and message** listing `diff`s against S0's baseline listing (`scratch-subsume/s0/corpus-base`) at **0 lines** — byte-identical, no file differs | `<g>/corpus-s0.log`, `<g>/verdicts-s0.txt`, `<g>/verdicts-baseline.txt`, `<g>/verdicts-diff.txt` (empty) |
| d | REPL smoke (Tier 0) | `tracker/tools/repl-smoke.sh` | **8 / 8 groups PASS, 66 checks, 0 FAIL** — the recorded baseline (`E11a-CANON.md:343`, "8 groups / 66 checks") | `<g>/repl-smoke.log` |
| d | LSP smoke (Tier 0) | `tracker/tools/lsp-smoke.sh` | **`PASS lsp (573 checks)`**, rc=0. **The brief's "577" is not this tree's number** — see the note below; the pre-change tree gives the identical **573** | `<g>/lsp-smoke.log`, control `<g>/lsp-smoke-A.log` |
| e | L2 corpus differential (Tier 1) | `LOOPTRACE_BIN=<wt-json-wrappers>/…/looptrace LOOPTRACE_PAR=3 tracker/tools/looptrace-corpus.sh <g>/looptrace` | **18 groups, 3,210,869 segments, `agree` = `segments` on EVERY group**; per group `skip=0`, `hashdiff=0`, `eqdiff=0`, `fuel=0`, `rc=0`, `timeouts=0`, `dropped=0`; `incomplete` 1,905,712 / 1,905,712 with 0 dropped. Wall 20 min (`LOOPTRACE_PAR=3`), model binary from `ermine-scala-wt-json-wrappers` | `<g>/looptrace-corpus.log`, `<g>/looptrace/results.txt` |
| f | trace A/B, all record kinds (Tier 1) | `tracker/tools/trace-ab.py` on `boot` and `Wide`, both sides `-Dermine.loadInSeries=true`, identical JVM flags | **IDENTICAL on both groups**: `boot` 54,209 / 54,209, `Wide` 116,420 / 116,420, `sinmoved=0`, exit **0**, **0 differing segments** across all sixteen record kinds | `<g>/trace-ab-boot.txt`, `<g>/trace-ab-Wide.txt`, traces `<g>/trace-A|B/`, normalised `<g>/norm-A|B/` |
| g | interface sweep (Tier 1) | `tracker/tools/ei-diff.sh --batch --snapshot <g>/ei-{A,B} "-Dermine.loadInSeries=true"`, one side per tree, then byte-compare + `ei-classify.py` | **274 interfaces on each side, 0 present on one side only, 0 of 274 differing by `cmp`**; `ei-classify.py`: `0 of 274 interfaces differ`, `bindings by verdict: {'identical': 3523}` | `<g>/ei-A.log`, `<g>/ei-B.log`, `<g>/ei-names.diff` (empty), `<g>/ei-content.diff`, `<g>/ei-classify.txt` |
| h | G1 signature drift (Tier 1) | `tracker/tools/g1-validate.sh` | **rc=0, 9 / 9 PASS, 0 FAIL** — seven mutation fixtures, the two-boot self-agreement (`129 files, 1447 signatures, EQUIVALENT`) and the hard baseline-drift check (`no drift from tracker/g1-baseline`). The checked-in `tracker/g1-baseline` was NOT re-cut | `<g>/g1-validate.log` |

### Notes on the two figures that are not the ones the brief predicted

**`lsp-smoke.sh` 573, not 577 — NOT a regression.** Every recorded run in the trackers since LSP
6.2c is **573** (`E11a-CANON.md:344`, `:461`, `:570`; `E11a-REVIEW.md:535`, `:571`;
`LSP-6.2c-HEADS.md:235`, `:514`; `LSP-6.2c-REVIEW.md:476`; `E11c-SOLVEDET.md:403`). The 577
appears once, in `tracker/PROMPT-subsume-termination.md:82`, in the **Tier 2 adoption** list,
immediately before "*and* a new smoke case that opens the B1 program in the resident session" —
i.e. 577 is the target **after a fix stage adds that fixture**. S0 adds no fixture, and the
control settles it: the **pre-change tree scores the same 573** (`<g>/lsp-smoke-A.log`). Green.

**`trace-ab.py` needs the worktree path normalised, and that is what makes it IDENTICAL.** Run
raw, the two traces differ on 46,223 of `boot`'s 54,209 segments — and the only differing field
is the **absolute path of the tree** inside every `sin`/`solve`/`rsound` location record
(`…/ermine-scala-wt-subsume/core/target/…` against `…/ermine-scala-wt-subsume-s0/core/target/…`),
because the stdlib is loaded from each worktree's own `target`. With
`sed 's|/home/dmitry/research/ermine/<tree>/|<TREE>/|g'` applied to both sides, **every segment of
both groups is IDENTICAL**. Two controls back this up: the record-kind census is equal
side-for-side over both groups (`solve`/`sin`/`rsound` 170,629 each, `learn` 62,300, `slbl` 40,501,
`svar` 27,497, `step` 20,936, `ramb` 19,992, `sat` 18,469, `scon` 16,861, `inpart` 14,003, `in`
13,652, `concr` 3,244, `splice` 2,974, `detm` 2,974, `ex` 2,467 — all sixteen kinds), and a
**same-build control** (the pre-change tree's `boot` traced twice) is **54,209 IDENTICAL,
`sinmoved=0`** — the method's noise floor on this group is zero (`<g>/trace-ab-control.txt`).

### Per-group detail of gate (e), `<g>/looptrace/results.txt`

| group | files | segments | agree | skip | model |
|---|---|---|---|---|---|
| boot | 0 | 54,209 | 54,209 | 0 | 1.7 s |
| top | 15 | 92,747 | 92,747 | 0 | 3.6 s |
| Ai | 11 | 83,964 | 83,964 | 0 | 30 s |
| Wide | 12 | 116,420 | 116,420 | 0 | 572 s |
| Wide-shouldfail | 4 | 55,787 | 55,787 | 0 | 1.9 s |
| Present | 14 | 131,406 | 131,406 | 0 | 64 s |
| Present-shouldfail | 7 | 59,503 | 59,503 | 0 | 1.8 s |
| Time | 12 | 125,386 | 125,386 | 0 | 136 s |
| Time-shouldfail | 5 | 55,908 | 55,908 | 0 | 1.9 s |
| Algebra | 13 | 101,039 | 101,039 | 0 | 71 s |
| Algebra-shouldfail | 7 | 55,401 | 55,401 | 0 | 2.1 s |
| Lang | 15 | 94,542 | 94,542 | 0 | 12 s |
| Lang-shouldfail | 8 | 58,789 | 58,789 | 0 | 1.5 s |
| shouldfail | 50 | 56,291 | 56,291 | 0 | 1.8 s |
| bugs | 2 | 54,245 | 54,245 | 0 | 1.6 s |
| guide | 2 | 54,254 | 54,254 | 0 | 1.5 s |
| shouldfail-controls | 7 | 55,266 | 55,266 | 0 | 1.6 s |
| incomplete (per file) | 35 | 1,905,712 | 1,905,712 | 0 | 125 s |
| **total** | | **3,210,869** | **3,210,869** | **0** | |

`.ei` hygiene: every interface written under `core/` by these gates was deleted afterwards —
`find core -name '*.ei'` is **0** on both trees.

### Verdict

**GREEN. No gate deviates from its expected number**, and the two figures that differ from the
brief's prediction are explained above and are not regressions: `lsp-smoke` 573 is this tree's
recorded baseline on BOTH trees (the brief's 577 is its Tier-2 adoption target, which assumes a
smoke fixture S0 does not add), and `trace-ab`'s raw cross-worktree difference is the embedded
absolute tree path, which normalises to **0 differing segments across all sixteen record kinds**,
against a same-build control whose noise floor is zero. The instrumentation is inert with the
flag off, exactly as §6 claims: identical verdicts, identical published interfaces, identical
traces, identical inferred signatures, and the Lean model still reproduces every one of
3,210,869 solves.
