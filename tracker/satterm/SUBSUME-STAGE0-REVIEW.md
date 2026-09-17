# SUBSUME-STAGE0-REVIEW — review of S0 (diagnosis), `subsume-termination`

Reviewer: Opus, 2026-09-16. I did not write the stage. Stage worktree
`~/research/ermine/ermine-scala-wt-subsume-s0`, branch `subsume-s0`, UNCOMMITTED
(`Subst.scala` +239/−2, `SUBSUME-STAGE0.md`). Read in order: `briefs/brief-review.md`,
`briefs/brief-S-common.md`, `PROMPT-subsume-termination.md` Part B, `SUBSUME-PLAN.md`,
`briefs/brief-S0.md`, `SUBSUME-STAGE0.md` (714 lines), then the diff. The two landed Lean
reports (`../ermine-scala-wt-subsume/tracker/satterm/SUBSUME-STAGE1A.md`, `-1B.md`) were read
for the S0 numbers they cite.

My logs and scripts: `<r>` = `/home/dmitry/research/ermine/scratch-subsume/review-s0/`.
The implementer's: `<s>` = `/home/dmitry/research/ermine/scratch-subsume/s0/`.

---

## VERDICT: FIX-THEN-LAND

The stage's central result stands and I reproduced it: **the check terminates on the B1
program, the ScalaCheck property does not, and the difference is `minSuccessfulTests = 100`.**
I verified the extrapolation the report could only make on a slope — a default-N run of the
suite alone, which the implementer never saw finish, **finishes in 18 min 19 s and is GREEN** (§2.2). H1 and H2 are refuted
by the logs as claimed; H3 survives only in the report's corrected form.

What must be fixed before this lands is **one class of number, not the conclusion**: every
cost figure attributed to `Subst.scala:648` is the sum of per-call INTEGER-millisecond values
over calls that are individually sub-millisecond, so 96.7 % of them contribute 0. Those figures
understate the escape check by an order of magnitude (§3, finding 1), and S1A has already built
on one of them ("`:648` is ~1 % of the hang"). The instrumentation contains an accurate
nanosecond accumulator four lines above (`cse`), so this is a small fix and a re-derivation, not
a re-run of the stage.

## 1. What the report claims, and what its logs actually say

Every headline number was re-derived from the implementer's own logs (not from the report's
tables). Unless a row says otherwise, the log says exactly what the report says.

| report claim | §  | my check on the log | verdict |
|---|---|---|---|
| `bin/ermine` refuses `Bad.e` in 0.06–0.10 s | §0, §1.3 | my own run, `<r>/cli-bad.log`: `Row partitions are unsatisfiable at field 'Bad.startDate'`, **0.07 s** for the module, 12.16 s wall of which 11.24 s is the 129-module boot (`<r>/cli-bad.time`) | **CONFIRMED** |
| 9.1 s per extra B1 test, linear over N=1…16 | §6.2 | `<s>/nscale-summary.txt`: 184/191/209/249/321 s at N=1/2/4/8/16; marginals 7.0/9.0/10.0/9.0; slope (321−184)/15 = **9.13 s** | **CONFIRMED** |
| `minSuccessfulTests` default 100, `workers=1` | §0 | `<s>/scparam/result.txt`, reflection against the shipped `scalacheck_3-1.15.4.jar` | **CONFIRMED** |
| `no(...)` maps Proof→False, False→True, so a rejection is *passed* and never *proved* | §0, §5.5 | `TestErmine.scala:220-223` (`no`), `:231-235` (`sessionProof` returns `proved`); the B1 property is `no(typeChecks(...))` at `TestDateAndScan.scala:185-192` | **CONFIRMED by reading** |
| max `hm.types.size` = 1,566 in all runs | §1.7 | all four traces: 1566 / 1566 / 1566 (+ CLI) | **CONFIRMED** |
| max kind-walk tree nodes 35,921; DAG 16,327/16,328; depth 23 | §1.5, §1.7 | identical in all three suite traces | **CONFIRMED** |
| tree/DAG ratio never above 4.39 | §5.2 | max ratio **4.386** (193/44) in each of the three traces | **CONFIRMED** |
| 0 cycles | §5.3 | `cyclicKV=true` and `cyclicTV=true` occur **0 times** in 171,286 + 93,377 + 218,006 = 482,669 escape records (plus 9,531 in the CLI trace) | **CONFIRMED** |
| `rowSoundBudgetHits = solveBudgetHits = 0` | §1.7 | 0 in every record of every trace | **CONFIRMED** |
| `rowSoundNodes` 9–10 per run | §1.7 | 9 / 10 / **33** — the fourth traced run (`subsume-trace-default.tsv.gz`) reaches 33 | **finding 3** |
| the refused module's own check is 8 escape checks over a 13-entry substitution | §1.8 | `rowtrace/cli-bad.subsume.tsv`, main thread: **8** records, t = 21,971…22,021 ms, mean types 6.0, max 13, max treeKV 21 | **CONFIRMED** |
| one library boot = 9,531 escape checks | §1.7, §1.10 | 9,531 in the CLI trace | **CONFIRMED** |
| corpus 89 LOADED / 79 REJECTED / 0 UNKNOWN over 168 | §6.1 | `<s>/corpus-base.log` last line, on the PATCHED tree | **CONFIRMED** |
| id base does not change the verdict; 76 % of segments move | §1.9 | `<s>/rowtrace/trace-ab-0-64.txt` (41,278/54,258 CONTENT-DIFFERS), `ab-runs.txt` (same verdict both bases), `slbl0.txt` = `slbl64.txt` | **CONFIRMED** |
| every id base refuses | §1.6 | `<s>/idsweep/summary.txt`: **17** bases (not 16 — `base-256` too), rc=0 and one verdict line each | CONFIRMED (count is 17) |
| total time in `:648` = 5.50 s (run A) / 2.17 s (min1) / 0.18 s (CLI) | §1.5, §1.7 | the sums are right and the METHOD is wrong — see **finding 1** | **DISPUTED** |
| `checkSkolemEscape:365` = 3,913 ms over 40,013 calls | §1.5, §1.7 | `cseMs`/`cseCalls` in the last escape record; this one IS a nanosecond accumulator (`Subst.scala:2295`) and is sound | **CONFIRMED** |
| `TestLoopTrace` with the model binary — "see §6.3" | §6.1 | `<s>/looptrace-base2.log` **does not exist**; §6.3's `rc=0 … 2 s` line is the SKIPPED run — see **finding 2** and §2.3 | **DISPUTED** |

**One thing in the logs that looks alarming and is not.** `<s>/compile.log` ends `EXIT=1`, but
the error is `Not a valid command: scalacheck-binding` — a mistyped sbt project id, after
`core/compile` and `core/copyResources` had both reported `[success]`. `<s>/compile2.log` is the
run that compiled the patched file (`compiling 1 Scala source`, `[success]`), and the only
warnings it emits are the two pre-existing `VarK` auto-apply deprecations at `Subst.scala:1750`
/`:1753`, which the patch merely shifts by two lines. The instrumentation introduces **no new
warning and no new dependency** (it uses `java.io`, `java.util`, `java.util.concurrent.atomic`
only).

## 2. What I re-ran myself

All from the stage worktree, `PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/
ermine-toolchain/bin:$PATH`, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=4
-Dermine.useInterface=false"`, background jobs harness-tracked, killed by recorded PID.

### 2.1 The B1 suite alone at `-minSuccessfulTests 1` — PASSES

```
sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan -- -minSuccessfulTests 1'
```
`<r>/min1.log`: `… REJECTED (B1): OK, passed 1 tests`, `Passed: Total 12, Failed 0, Errors 0,
Passed 12`, **179 s** (the report's 184/180 s). Reproduced exactly, on the patched tree.

### 2.2 The B1 suite alone at the DEFAULT `minSuccessfulTests` — it FINISHES, in 18 min 19 s

This is the run the stage never had: both of the implementer's default-N runs were killed
(625 s and ~408 s), so §0's "about 18 minutes" was an extrapolation off a five-point slope.
I ran it to completion with a 25-minute deadline and a `jcmd Thread.print` every 60 s
(`<r>/run-default.sh`, log `<r>/defaultN.log`, sampler `<r>/run-default.out`, dumps
`<r>/stacks/s-*.txt`):

```
sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'      # no -minSuccessfulTests
…
+ … a dateDiff combine over a relation WITHOUT the dates is now REJECTED (B1): OK, passed 100 tests.
Passed: Total 12, Failed 0, Errors 0, Passed 12
[success] Total time: 1099 s (18:19)
```

**1,099 s against the report's predicted 184 + 99 × 9.13 = 1,088 s — within 1 %.** The property
is not a hang: it is a hundred library-scale checks that all return, and the suite is GREEN at
the shipped default. Part B's *"the property never returns"* is refuted by a completed run, not
merely by a slope.

The sampler's JVM CPU series is the other half of the arithmetic: 1:44 at t=60 s rising linearly
to **20:20 at t=1,080 s**, i.e. 1.09 CPU-seconds per wall-second once the other eleven
properties finish at t≈200 s — one busy thread plus JIT/GC, no GC storm, no second runaway.
Part B's *"28 CPU-minutes seen"* is the same order of magnitude for a JVM that was ALSO running
other suites and was killed before the tail ended; it needs no non-returning call to explain it.

**The frames.** I took 18 dumps; 15 of them catch the B1 thread (`pool-5-thread-10`, the only
ermine thread left after t≈240 s) and they show **14 distinct top frames** —
`Subst.unifyType(Subst.scala:321)`, `Subst.mkSimplified(Subst.scala:2146)`,
`AppT.subst(Type.scala:228)`, `VarT.subst(Type.scala:245)`, `Type$$anon$5.vars(Type.scala:708)`,
`HashMapBuilder.update`, `MapOps.map`, `BitmapIndexedSetNode.updated`, `List.prependedAll`,
`IndexedSeqOps.knownSize`, `SetOps.concat`, `BoxesRunTime.equals2`, `Need.value0$lzyINIT1` and a
method-handle bootstrap — with **5** of those stacks inside `scalaparsers` (the thread is
re-parsing a library module) and **0** anywhere in the `:648` kind walk. **No dump of mine
contains `Type.scala:651` at all** (`grep -l` over all 18), and neither does any of the
implementer's twelve (`<s>/stacks/sampler.log`). Across both runs, 30 timed dumps, exactly ONE
(`<s>/stacks/sample-5`) lands in the frames Part B calls "always in these frames".
`<r>/classify.sh`, output in `<r>/classify-out.txt`.

### 2.3 `TestLoopTrace` WITH the model binary — the baseline the stage owes, run

```
sbt -Dermine.looptrace=/home/dmitry/research/ermine/ermine-scala-wt-json-wrappers/tracker/lean/\
.lake/build/bin/looptrace 'core/testOnly *TestLoopTrace'
```
(`<r>/looptrace-bin.log`, 14 s wall, 11 s in sbt, 9,416 ms in the model comparison):

```
[loop model trace] 720 solves (20 seed x 6 bases + 600 generated); 720 segments; 720 agree;
  #summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0
[loop model trace] control (id base +1): 46 of 720 disagree; control (--flags=nongen): 58 of 720
Passed: Total 3, Failed 0, Errors 0, Passed 3
```

**720/720, skipped 0, both negative controls firing (46 and 58)** — identical to the recorded
baseline in `tracker/LSP-FFI-TOLERANCE.md:424` and to `tracker/GATE-POLICY.md:14`'s 720/720.
The property name in the test source is *"the Lean loop model reproduces the compiler's trace,
segment for segment"*, and the flag is `-Dermine.looptrace` (`TestLoopTrace.scala:108`;
`skip = true` is reserved for exactly one reason — the model binary missing —
`TestLoopTrace.scala:610-618`). **This is the number S0's §6.1 should carry**, not the 3/3 of a
self-skipped run. The model gate is green on the patched tree.

### 2.4 The control the stage queued and never ran: another suite ahead of it in the same JVM

The question behind it is the one §4.3 answers: if a full `core/test` runs this property cheaply,
a cross-suite cache would have to be why. Two runs, same JVM, `TestScopes` (30 properties, its
own `ErmineFixture`) ahead of `TestDateAndScan` (`<r>/run-after.sh`, logs `<r>/control-N1.log`,
`<r>/control-N8.log`):

| run | wall | tests | B1 |
|---|---|---|---|
| `TestScopes` + `TestDateAndScan -- -minSuccessfulTests 1` | **177 s** | Total 42, Failed 0 | passed 1 |
| `TestScopes` + `TestDateAndScan -- -minSuccessfulTests 8` | **257 s** | Total 42, Failed 0 | passed 8 |

**Marginal cost of one more B1 test with a suite ahead of it: (257 − 177)/7 = 11.4 s.**
Alone (the implementer's `<s>/nscale-*.log`): (249 − 184)/7 = 9.3 s. A preceding suite in the
same JVM does **not** make the repetitions cheaper — it makes them marginally dearer, which is
what one expects when another suite's threads are still in the pool. (Note also that `TestScopes`
costs the wall clock almost nothing here: 177 s for 42 tests against 179–184 s for 12, because
sbt runs the suites' properties concurrently.)

That is the empirical half of §4.3: there is no cheap full-suite path for this property, so
nothing needs to explain one.

### 2.5 `bin/ermine` on the report's `repro/Bad.e` — refused in well under a second

```
ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=4 -Dermine.useInterface=false" \
  bin/ermine <s>/repro/Bad.e
```
`<r>/cli-bad.log`, `<r>/cli-bad.time`: `Loaded 129 modules (11.24 seconds)`, then

```
…/repro/Bad.e:14:7: Row partitions are unsatisfiable at field 'Bad.startDate':
  the whole contains it but no part does
Unable to load module from '…/repro/Bad.e' (0.07 seconds)
```

**0.07 s for the module**, 12.16 s wall / 33.3 s CPU for the whole boot-and-refuse. Confirmed.
This run also doubles as the **flag-OFF check**: no `-Dermine.subsumeTrace`, and the only lines
in the output containing "subsume" are the worktree path — the instrumentation emits **nothing**
and the refusal is unchanged (same message, same location as the pristine tree's in
`<s>/repro/cli-run1.log`).

## 3. Findings

### Finding 1 (MUST FIX) — every `:648` cost figure is floor-summed integer milliseconds, and understates the escape check by roughly an order of magnitude

`core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala:2320-2331` (`SubsumeTrace.phase`)
logs `ms = (System.nanoTime - t) / 1000000L` per call and keeps **no accumulator**. The report
then sums those per-call integers:

* run A (default N, killed): `kindVars` 3,457 ms + `fskvs` 2,044 ms = the report's **5.50 s**;
* min1: 1,340 + 826 = the report's **2,166 ms**;
* CLI boot: the report's **177 ms**.

I re-derived them from the same traces (`<r>/`, one `awk` over each `.tsv.gz`) and they are
arithmetically right. **The method is not.** Of 93,377 `kindVars` calls in run A, only 3,058
(3.3 %) recorded 1 ms or more; the other 90,319 each recorded **0** while taking anything in
[0, 1) ms. The report reads that as "96.7 % of calls are under a millisecond" (true) and then as
"total 5.50 s" (false: it is a lower bound whose hidden mass is up to 90 s in the same run).

The same trace supports a much better estimator. `phase` timestamps each begin and end line with
absolute milliseconds, and `floor(t+d) − floor(t)` is **unbiased** for `d` over many calls, so
summing the begin→end timestamp differences estimates the true total (inflated only by the one
flushed `log` write inside each interval):

| run | calls per half | report's floor-sum | timestamp-difference estimate | `cse` (`:365`) ACCURATE nanos, same run |
|---|---|---|---|---|
| CLI `bin/ermine Bad.e` | 9,531 | **177 ms** | `fskvs` 1,541 + `kindVars` 1,820 = **3,361 ms** | 286 ms / 2,226 calls = 128 µs per walk |
| suite, `-minSuccessfulTests 1` | 171,286 | **2,166 ms** | 23,374 + 25,406 = **48,780 ms** | 3,913 ms / 40,013 = 98 µs per walk |
| suite, default N (killed) | 93,377 | **5,501 ms** | 16,232 + 18,442 = **34,674 ms** | 2,793 ms / 21,936 = 127 µs per walk |

The third column is an upper bound (it contains one buffered-and-flushed `log` write per
interval), the second a lower bound; the fourth is the honest anchor, because `cse`
(`Subst.scala:2305-2318`) accumulates NANOSECONDS in an `AtomicLong` and logs nothing inside the
timed region. At ~100 µs per whole-environment walk and two walks per `subsumeType`, `:648`
costs of the order of **30–40 s** in the min1 suite, i.e. **10–25 %** of it — not the
"2.2 s of a 184 s run" and "at most about 3 %" of §5.1, and not S1A's "`:648` is ~1 % of the
hang" (`SUBSUME-STAGE1A.md:289, :396, :488`), which is inherited from this figure.

**The report's own two numbers are mutually inconsistent, which is the cheapest way to see it.**
§1.7's CLI column has `:365` at 286 ms / 2,226 calls = **128 µs per whole-environment walk**
(accurate) and `:648` at 177 ms / 9,531 calls = **18 µs per call** (floor-summed) — i.e. it says
that TWO whole-environment walks cost seven times LESS than one. They cannot both be right, and
the accurate one is the larger.

**Failure scenario — and it has already fired.** §5.5 consequence 1 ("a memoised escape check
would be worth about 2.2 s of a 184 s suite run … the cost that would actually repay attention
is `checkSkolemEscape` (`:365`)") has been taken up by both landed Lean stages:
`SUBSUME-STAGE1A.md:289/:396/:488` ("`:648` is ~1 % of the hang", "make `:648` cheaper is not a
fix"), `SUBSUME-STAGE1A-REVIEW.md:226/:262` ("`:365` costs **3.9 s** against `:648`'s 2.2 s",
called urgent), and `SUBSUME-STAGE1B-REVIEW.md:215`. On the corrected numbers that comparison
**inverts**: `:365` is 40,013 single walks (3.9 s, accurately measured); `:648` is 171,286 calls
× TWO walks in the same run, so of the order of 30–40 s. Whatever S2 or the P7 item does, it
should start at `:648`, not at `:365` — the opposite of what three documents now say.

**Fix.** Give `phase` the treatment `cse` already has — one `AtomicLong` of nanos per phase name
(four lines), emit the totals in the `escape` record next to `cseMs`, re-run the three traced
runs (each is one command and under 6 minutes), and re-derive §0.1, §1.5, §1.7, §5.1, §5.5
consequence 1 and §8.1. Until then, every `:648` total in the report must be marked
*lower bound* and the "3 %"/"1 %" framing withdrawn — including the note S1A took from it.
Nothing in the stage's ANSWER changes: per-call maxima (16 ms / 29 ms), the 0 cycles, the
maxima of §1.7 and the reproduction are all counts or per-call floors and stand.

### Finding 2 (MUST FIX) — the `TestLoopTrace` baseline row cites a log that does not exist

`SUBSUME-STAGE0.md` §6.1, row *"`TestLoopTrace` (with the model binary) … see §6.3"*, log
`<s>/looptrace-base2.log`. **That file does not exist** (`ls` says so), and §6.3's line
`looptrace rc=0 : [success] Total time: 2 s` is the OTHER run — `<s>/looptrace-base.log`, whose
body reads `[loop model trace] SKIPPED: the Lean model executable is absent (…/tracker/lean/
.lake/build/bin/looptrace)` twice, then `Total 3, Failed 0`. §8.5 admits the run was killed at
the budget, but a reader of §6.1/§6.3 is told the gate ran with the binary.

This matters because **3/3 is not the baseline for that suite**: `tracker/GATE-POLICY.md:14` and
`tracker/LSP-FFI-TOLERANCE.md:255` both record `TestLoopTrace` at **720/720** with the model
built, and a self-skipping property is green precisely when the model is missing. Landing S0
with "3/3" as the recorded baseline would let a later stage compare a real 720-test run against
a number that means "not run".

**Fix.** Replace the row with the run I did (§2.3) or say plainly "not run; the baseline is the
skipped 3/3". I ran it with the binary the common brief points at — numbers in §2.3.

### Finding 3 (SHOULD FIX, arithmetic in cited figures)

* §0.1 *"0 cycles in 984,024 identity-marked walks (492,012 escape checks across four traced
  runs: 9,531 + 171,286 + 93,377 + 218,006)"* — those four counts sum to **492,200**, so the
  walk count is **984,400**. §5.3 gives a third figure for the same quantity (*"~548,000"*,
  which is 2 × 274,194, i.e. the three-run subset of §1.7). One quantity, three numbers.
* §1.6 and §0.1 say **sixteen** id bases; `<s>/idsweep/summary.txt` has **seventeen** rows
  (`base-256` as well). The conclusion is unaffected; the count is quoted twice.
* §1.7 and §5.5 say `labelDecide` spends *"9–10 decision nodes in an entire run"*; the fourth
  traced run (`<s>/subsume-trace-default.tsv.gz`) ends at `rowSoundNodes=33`. Still five orders
  of magnitude below the 200,000-node budget, so the argument holds — the quoted range does not.
* §3 says tracing costs *"roughly three times"* the wall clock and gives its own two numbers in
  the same sentence: 336 s traced against 184 s untraced, which is **1.8×**. (The per-thread
  view in `<s>/subsume-trace-default.tsv.gz` says something else again: the B1 thread managed
  5.9 boots in 407 s, i.e. ~69 s per test against 9.1 s untraced. Whichever figure is meant, it
  should be one figure with a log behind it — it is the factor every traced timing is divided
  by.)

### Finding 4 (SHOULD FIX before this ships as a permanent facility) — the flag-OFF cost, and an abandoned measurement thread

1. `Subst.scala:2305` (`cse`), `:2320` (`phase`) and `:2269` (`enter`) are ordinary `def`s with
   by-name/parameter arguments, so with the flag OFF each `subsumeType` still allocates three
   `Function0`s and `checkSkolemEscape` one, on a path the report itself says runs 171,286 times
   per suite. The report names this in §8.6 and leaves it. In Scala 3 the fix is one keyword —
   `inline def` — or hoisting `if (SubsumeTrace.enabled)` to the call site. JIT escape analysis
   probably erases them, but "probably" is not what a permanent facility on the
   explicit-signature path should rest on, and no A/B was run.
2. `Subst.scala:2334-2356` (`measure`): after `th.join(deadlineMs)` the method returns
   `measure=TIMEOUT` and **leaves the daemon thread running**. With tracing ON and one deadline
   hit, an abandoned 512 MB-stack walk keeps a core busy for the rest of the JVM's life and
   silently inflates every later timing in the same run. No trace in `<s>/` shows
   `measure=TIMEOUT`, so nothing measured here is affected; add an interrupt/abort flag before
   anyone runs this on a bigger program.

### Finding 5 (SCOPE — what should land, and what should stay in scratch)

+239 lines, of which the `Walk` cost model (`Subst.scala:2361-2429`) is about 110: a second,
hand-written copy of `Type.typeHasKindVars.vars` (`Type.scala:649-659`) and
`Type.typeHasTypeVars.vars` (`:707-714`). I checked it case by case against both originals and
it is faithful where it matters (every constructor that recurses in the original recurses in the
model; `Forall`'s `-- vs` and `Exists`' `-- xs` are dropped, which can only make the model's node
count an under-count, never an over-count — so "0 cycles" and "ratio ≤ 4.39" are sound). But
nothing pins it: the next case added to `Type.vars` leaves the model silently wrong, and a
silently wrong cost model is exactly what refuted H1 and H2 here.

My recommendation to the orchestrator (not a blocker): land `enter`/`atEscape`/`phase`/`cse`
with finding 1's accumulators — they are the parts a later stage will re-run — and either
(a) keep `Walk` with one unit test that pins `treeKV`/`dagKV`/`cyclicKV` on a hand-built term
with a shared subterm, or (b) move `Walk` to `tracker/satterm/subsume-walk-model.patch` and
apply it when a walk question comes back. Either is cheap; landing 110 unverified duplicated
lines on the hot path with no test is the option I would not take.

### Finding 6 (REPORT WORDING) — the frame evidence is stronger than the report says, and the limit of what it can say

§1.2 says the samples put the thread in "four different places", "one of at least five".
Running my own classifier (`<r>/classify.sh`) over the implementer's 12 samples and 2 probes,
the B1 thread (`pool-5-thread-5`) appears in **ten distinct top frames**, of which exactly
**one** (`sample-5`) is the `:648` kind walk, and **two** are inside `scalaparsers`
(`Parsing.blockComment(ParsingUtil.scala:148)`, `Commit.map(ParseResult.scala:30)`). A thread
inside a single non-returning `subsumeType` call cannot be in the parser; that one observation
refutes "one call that never returns" on its own, and the report buries it. `<s>/stacks/
sampler.log` adds the blunt version: **0 of 12 samples had any frame at `Type.scala:651`**,
the line Part B says the thread is "always" in.

What the report should also say, and does not: Part B's dumps were taken on other trees
(`json-encode 3eba80f8`, `json-runner 85d95531`) and are not in `<s>/`, so the honest claim is
**"not reproduced here"**, not "did not happen". With ~1/12 of samples landing in the walk, three
independent single dumps all landing there is ~0.06 % — so the earlier evidence was most likely
a small, correlated sample (one dump per JVM, or several within one walk), not a contradiction
that needs explaining away. The prompt's rule stands either way: the measurement wins.

## 4. The point I was asked to dispute hardest: does the harness explanation survive Part B's evidence?

**It does.** I re-read the mechanism from the sources rather than from the report, and I
re-ran the two ends of it.

### 4.1 The mechanism, from the source

* `TestDateAndScan.scala:185-192` is `no(typeChecks(...))`. `typeChecks`
  (`TestErmine.scala:177-182`) is `sessionProof`, which returns `Prop.proved` on success and
  `falsified` on `Death` (`:231-235`). `no` (`:220-223`) rewrites `False → True` and everything
  else → `False`. A successful REJECTION therefore ends as `True` — *passed*, never *proved* —
  and ScalaCheck short-circuits only on `Proof`. So the property runs
  `minSuccessfulTests = 100` complete checks (`scalacheck 1.15.4`, `<s>/scparam/result.txt`),
  while the other eleven properties in the file return `Proof` and stop at one. That is exactly
  the "11 of 12 finish" signature Part B reports.
* Each of the hundred tests re-checks the whole import closure. `loadStatements`
  (`TestErmine.scala:133-157`) first calls `loadModules(imports.keySet)`, which for the B1
  property's `onlyTest = Map("Test" -> fx.all)` (`TestDateAndScan.scala:46`) is a no-op —
  `baseEnv` already carries `"Test" -> CheckMethod.Interface` (`TestErmine.scala:86`) — so the
  expensive imports named inside the generated `module Test` source (`Prelude`, `Relation.Op`,
  `Syntax.Relation` and their closure) are loaded into the throw-away copy `mkEnv` (`:96-98`)
  and discarded.
* Nothing short-circuits the CHECK: the fixture's session is `_useInterface = Some(false)`
  (`TestErmine.scala:83`), and `Dep.make`'s `preChecked` returns `None` whenever
  `!s.useInterface` (`Session.scala:592-608`).
* `Session.depCache` (`Session.scala:110`, `:403-412`) is a process-global
  `ConcurrentHashMap[SourceFile, (Long, Dep)]`: shared across suites in one JVM, keyed on file +
  mtime, and it caches the **parse**, never a check result.

### 4.2 Is "100 iterations" consistent with the jstack samples? Yes — more so than the report argues

See finding 6: across the implementer's 12 samples and 2 probes the B1 thread appears in **ten**
distinct top frames, only one of them the `:648` kind walk, **two of them inside the parser**;
`<s>/stacks/sampler.log` records **0 of 12** samples with any frame at `Type.scala:651`. My own
default-N run (§2.2) adds independent samples with the same shape. A thread that is re-parsing
`ParsingUtil.scala:148` is not inside a non-returning `subsumeType` call; a thread sampled in
`Subst.solve`'s `PQueue`, in `unifyType`, in `Type.sub`, in `HashSet.concat` and in `Free.resume`
across successive minutes is running many checks, not one.

The report's `enter`-counter is the clean form of the same argument and it is the right
instrument: `enter` and `escape` records are equal in number in every trace (171,286 / 171,286;
218,006 / 218,006; 93,378 / 93,377 in the run that was KILLED mid-call), so no `subsumeType`
call is missing its escape record — "one call that never returns" would show as a growing gap.

### 4.3 Then what makes the same 100 iterations cheap inside a full `core/test`? Nothing does

This is the question the report never asks, and the answer is not a cache:

* the 9.1 s marginal is **already the warm-cache figure** — within one suite run, tests 2…N
  reuse test 1's parses through the same process-global `depCache`, so a suite running ahead of
  it can only warm what test 1 warms anyway (measured in §2.4);
* therefore a full `core/test` pays the SAME ~18 minutes for this one property — measured, not
  inferred: §2.2's run of the suite ALONE at the shipped default took **1,099 s and passed**.
  The recorded full runs that "PASSED every time" absorbed it — the property is simply the last
  thing in the run to finish — and the three landing runs that "wedged" were, on this evidence,
  **killed before the tail ended**, not hung. (If any of those three runs was killed after more
  than ~20 minutes of the B1 property ALONE holding one thread, that would be a datum this
  review cannot reproduce and the orchestrator should say so; nothing in `<s>/` or `<r>/`
  records the wall clock at which they were abandoned.)

So the earlier cross-suite-cache story is **half right, in a precise sense worth recording**:
a cross-suite, process-global cache does exist (`Session.depCache`) and is shared by every suite
in the JVM — but it caches parses, so it can neither make the repetitions cheap nor cause a
non-return. What two suites ahead of B1 really change is (a) the wall clock the watcher is
waiting on, and (b) the `Supply` id base (E11c), which moves 76 % of the library's trace
segments (`<s>/rowtrace/trace-ab-0-64.txt`) and was measured to change nothing about this
refusal (`<s>/idsweep/`, 17 bases, verdict and 0.06–0.09 s module time at every one).

### 4.4 One loose thread in the id-base data that the report does not flag

`<s>/idsweep/base-16.log` boots the library in **26.79 s** against 12.35–12.79 s at every other
base, with the module refusal still 0.09 s. §1.6 quotes the range "12.9–27.8 s wall" without
noticing that it is a **2× outlier confined to the library boot**. It is the only datum in the
stage that suggests an id base can double a check's cost, and it is precisely the shape that
would make "two new suites ran before it" matter. Not a blocker — the refusal is invariant — but
it belongs in the open questions, with one repeat run at that base to see whether it is noise.

### 4.5 The CPU arithmetic, and "28 CPU-minutes"

§0 equates "about 18 minutes" of WALL clock with Part B's "28 CPU-minutes seen" without
converting units; they are different quantities and the report should not treat one as the
other. My run gives both: 1,099 s wall, and a JVM CPU series rising linearly to **20 min 20 s**
at t = 1,080 s (`<r>/run-default.out`) — 12 properties, JIT and GC included, on an otherwise
idle machine. A landing-run JVM that also ran other suites and was abandoned before the tail
ended would plausibly show ~28 CPU-minutes on the same mechanism. The point stands either way:
CPU time accumulating at ~1.1 cores with the thread moving through the parser, the unifier, the
solver queue and the walks is a hundred checks, not one that never returns.

## 5. The answer I would sign, and which hypotheses survive

> **Does the checker terminate on a refused row program (`subsumeType`'s escape check)?**

**YES for this input and this path — as a MEASUREMENT, not a theorem.** Specifically, and this
is the form I would sign:

1. The B1 module is **refused** by the compiler in **0.06–0.09 s** — my own run 0.07 s
   (`<r>/cli-bad.log`), the implementer's 17 id bases 0.06–0.09 s (`<s>/idsweep/`), warm
   interfaces 0.07 s and 0.20 s (`<s>/cli-useinterface.log`) — by the bare row-label check
   (12 `slbl` records), never reaching `labelDecide` in earnest (9–33 nodes per run) and never
   touching a budget (`rowSoundBudgetHits = solveBudgetHits = 0` in every record of every trace).
2. The escape check at `:648` **returned on every traced call** — 492,200 calls across four
   runs, worst single call 29 ms, `hm.types.size` ≤ 1,566, walk depth ≤ 23, tree/DAG ≤ 4.39.
3. **No cycle exists**: 0 in 984,400 identity-marked walks, and none is constructible —
   `Type`/`Kind`/`V` are strict case classes with no by-name or mutable field, and
   `typeHasKindVars.vars` descends into `v.extract` (the KIND ANNOTATION, `Type.scala:653`,
   `Kind.scala:58/65`), never into a binding. I verified that reading against the sources.
4. The thing that does not return *quickly* is the **ScalaCheck property**, and it does return:
   I ran it to completion rather than extrapolating (§2.2) — 100 library-scale re-checks,
   **1,099 s, 12/12 green**. "Never returns" is refuted, not merely explained.

What I would **not** sign: (a) any statement about what share of a run `:648` costs — finding 1;
(b) the word *terminates* as a theorem — S0 measured, the theorems are S1A's and S1B's, and
S1B's `SubstBlowup.chain_blowup` shows a substitution entry of `2^(n+1) − 1` nodes is
constructible in principle by the general `instantiateType` (not by the row solver), so the
question is answered for this path, not for the checker; (c) that no input can diverge — the
fixture environment was never swept over id bases (only the CLI was), which the report states
honestly in §8.3 and which §4.4's 2× boot outlier keeps alive.

**H1 (finite but explosive): REFUTED.** Bounded `hm.types` (max 1,566, median 64), bounded walk
(35,921 tree nodes, depth 23), and the tree/DAG ratio never above 4.39 — so the fourth mechanism
the brief asked about, exponential unfolding of a shared subterm, is absent too. The maxima are
identical in the run that refuses in 0.06 s and in the run that does not return.

**H2 (cyclic substitution): REFUTED, and Part B's wording is wrong about the code.**
`v.extract` is the kind annotation; the walk follows no binding; 0 cycles measured; a cyclic
term cannot be built. The orchestrator's reading in `SUBSUME-PLAN.md` is confirmed. There is no
occurs-check hole to fix on this path.

**H3 (the walk is the victim): SURVIVES only in the corrected, weaker half** — `:648` is where
the thread was sampled. H3's own proposed mechanism ("the rejection path grows the environment
or diverges before `subsumeType`") is refuted as well: the environment does not grow, and every
check of this module terminates everywhere it was run.

### The shape the next stage should take

**Not S2 as briefed, and not S3** — I agree with the report: there is no termination defect at
`:648` to memoise away, and a budget would add a failure mode where none exists (it would also
have to bound a computation whose true cost is now unmeasured — finding 1 — which is the wrong
order). Instead:

1. **A harness stage (1–2 h, Scala, no `Subst.scala`).** (a) Give `ErmineFixture` a `rejects(…)`
   that catches `Death` and returns `Prop.proved` — and FALSIFIES if the load succeeds —
   instead of `no(typeChecks(…))`, whose `False → True` rewrite is what asks ScalaCheck for a
   hundred library-scale checks (`TestErmine.scala:220-223`). Measured saving: **915 s** — the
   suite is 1,099 s at the shipped default (§2.2) and 179–184 s at one test — off every full
   `core/test`, and it removes the false "hang" signal that started this programme.
   (b) Adopt brief-S2's deadline pin anyway: every rejection case on a deadline thread that
   FAILS rather than hangs (the `(iso)` idiom), so that a real divergence becomes a red test in
   bounded time instead of wedging a landing run. Gate: Tier 0, the B1 property alone three
   times and inside the suite once; no Tier 1 is owed, since no solver file changes.
2. **Then, only if the programme wants the title question CLOSED rather than measured**: the
   unsatisfiable-row-program GENERATOR brief-S2 already specifies, pointed at the SOLVER with a
   deadline, swept over id bases **in the fixture environment** — the one environment S0 did not
   sweep — plus one repeat at the base-16 outlier (§4.4). That is the only experiment left that
   could still produce a divergence, and it is cheap.
3. **The cost work is a perf-roadmap item (P7 Step 1), not this programme's** — but it needs
   finding 1's corrected numbers first, and it should start with `checkSkolemEscape:365` (one
   whole-environment walk per ALTERNATIVE, `inferAltTypesPrime:1171`, 40,013 walks per suite,
   98 µs each, accurately measured) before `:648`.

## 6. What I did not re-run, and housekeeping

* **Not re-run, cited from the implementer's logs** (per brief-review): the corpus batch
  (`<s>/corpus-base.log`, 89/79/0 over 168 — read, not re-executed), the `-minSuccessfulTests`
  2/4/16 points (`<s>/nscale-*.log`), the 17-base id sweep (`<s>/idsweep/`), the two traced
  `rowTrace` CLI runs and `trace-ab.py` (`<s>/rowtrace/`), and the `-Dermine.solveDet=true`
  run (`<s>/solvedet-default.log`). All three `.tsv.gz` traces and the CLI `.tsv` were
  re-processed by me from scratch rather than read off the report's tables.
* **No whole-corpus run, no full `core/test`, no Lean build** — none is owed by this stage and
  the review brief forbids them.
* **Hygiene.** No commits. `find core -name '*.ei'` = **0** (my `bin/ermine` runs used
  `-Dermine.useInterface=false`). `tracker/repl-classpath.txt` untouched. `git status` in the
  stage worktree shows only `Subst.scala`, `SUBSUME-STAGE0.md` (the stage's own, unchanged by
  me) and this review file. Background jobs were harness-tracked with logs and carried a
  25-minute deadline that killed by the recorded PID; in the event nothing had to be killed —
  every run finished on its own. No `nohup`, no `setsid`, no `pkill`.
* **My artefacts**, all under `<r>` = `/home/dmitry/research/ermine/scratch-subsume/review-s0/`:
  `cli-bad.log`, `cli-bad.time`, `min1.log`, `defaultN.log`, `run-default.sh`,
  `run-default.out`, `stacks/s-*.txt`, `run-after.sh`, `control-N1.log`, `control-N8.log`,
  `looptrace-bin.log`, `classify.sh`, `classify-out.txt`, `run-after.out`, `sec*.md` (drafts of
  this file).

---

## 7. Re-check of the applied fixes — 2026-09-16 (same reviewer)

Scope: ONLY my six findings, the corrected numbers, and the worktree's shape. I did not re-open
anything I had already confirmed. My re-check logs: `<r>/recheck-cli-flagoff.{log,time}`.

### 7.1 VERDICT: **LAND**

All six findings are addressed, the corrected figures re-derive exactly from the new traces, and
the flag-OFF path is unchanged on the rebuilt tree. Three residuals below are cosmetic and none
blocks the commit.

### 7.2 The instrumentation (findings 1 and 4), read in the diff

`Subst.scala` is now **+157/−2**, and the audit passes on every point:

* **Nanoseconds, accumulated.** `fskvsNanos`/`kvNanos`/`cseNanos` plus `fskvsMax`/`kvMax`/`cseMax`
  are `AtomicLong`s; `bump` does `addAndGet` and a CAS loop for the max. The totals ride on the
  `escape` record (`fskvsNs`, `kvNs`, `cseNs`, and the `…MaxNs`), which is what made them
  re-derivable by me below.
* **Nothing is logged inside a timed region.** `phaseFskvs`/`phaseKindVars` are
  `nanoTime → body → bump(…, nanoTime − t)`; the `bump` argument is evaluated before the call, so
  the accumulator itself is outside the measured interval. The old per-call `log` is gone.
* **No `Function0` when OFF.** `enter`, `atEscape`, `cse`, `phaseFskvs`, `phaseKindVars` are all
  `inline def` with `inline body: A`, each opening `if (!enabled)`; `enter`/`atEscape` delegate to
  non-inline `*Slow` methods so the call sites stay small. The by-name closure of the first
  version is gone from all four sites.
* **`measure` is gone** — with it the 512 MB-stack daemon thread, the `deadlineMs` property and
  the abandoned-thread hazard of my finding 4.2. No new dependency (`java.io`,
  `java.util.concurrent.atomic` only).
* **The `Walk` cost model is archived verbatim** at `<s>/subsume-walk-model.patch` (finding 5,
  option (b)), and the evidence it produced is still on disk in the four original traces
  (`<s>/subsume-trace-*.tsv.gz`, `<s>/rowtrace/cli-bad.subsume.tsv`), so §5.2/§5.3's 0-cycles and
  ratio ≤ 4.39 remain checkable.
* **Compile.** `<s>/compile5.log`: `EXIT=0`, 0 errors, **15 warnings — the same 15 as the
  pre-fix `compile2.log`**, site for site modulo the line shift. The `inline def`s add none.

### 7.3 The corrected numbers — I re-derived BOTH totals, not one

One `awk` over the last `escape` record of each new trace (`<s>/ns-trace-cli.tsv`,
`<s>/ns-trace-min1.tsv`), reading `fskvsNs`/`kvNs`/`cseNs`/`cseCalls`:

| | escapes | `fskvs` | `kindVars` | **`:648` total** | `:365` (`cse`) | ratio | per-call max |
|---|---|---|---|---|---|---|---|
| `bin/ermine Bad.e` | 9,531 | 1.290 s | 1.496 s | **2.785 s** | 0.238 s / 2,226 = 107 µs | **11.70×** | 2.8 / 3.4 ms |
| suite `-minSuccessfulTests 1` | 171,286 | **21.071 s** | **24.347 s** | **45.418 s** | 3.749 s / 40,013 = 94 µs | **12.11×** | 5.3 / 5.8 ms |

Every figure the implementer reports (2.79 s, 45.42 s, 21.07 s, 24.35 s, 12.1×, 23 %, 24.7 %)
matches my independent derivation. Two corroborations worth recording:

* the corrected total is **within 7 % of the timestamp-difference upper bound I gave in finding 1**
  (48.78 s against the true 45.42 s), which retro-validates the estimator and the order-of-
  magnitude claim;
* the **transposition worry of finding 1 is now immaterial**: the new instrumentation costs ~3 %
  on the suite (traced 191 s, `<s>/ns-min1.log`, against 189 s untraced, `<s>/flagoff.log`) and
  ~10 % on the CLI boot (13.29 s traced against 12.01 s in my own untraced re-run). 45.418 s is
  23.8 % of the traced run's own 191 s and 24.7 % of the 184 s untraced figure — the same number
  either way.

### 7.4 The other findings

| finding | state |
|---|---|
| 1 cost figures | **FIXED** (§7.2, §7.3); §5.1 restated to 49.2 s / ~27 % with the old "3 %" explicitly withdrawn; §1.5's run-A bullet withdraws its 5.50 s |
| 2 `TestLoopTrace` | **FIXED** — §6.1 row now reads 720 solves / 720 segments / 720 agree, `skipped=0`, controls 46 and 58, credited to the reviewer's `<r>/looptrace-bin.log` |
| 3 arithmetic | **FIXED** — 492,200 / 984,400 / "seventeen" bases / `rowSoundNodes` 33 in the fourth run / tracing **1.8×** |
| 4 flag-OFF cost, abandoned thread | **FIXED** — `inline def`s, `measure` removed |
| 5 scope of the landing | **FIXED** as option (b) — `Walk` archived to scratch, `Subst.scala` down from +239 to +157 |
| 6 frame census | **FIXED** — §1.2 carries the 30-dump census (ten + fourteen distinct frames, one in the walk, eight in `scalaparsers`, none at `Type.scala:651`) and the "not reproduced here" limit; §1.6 carries the base-16 26.79 s outlier and §8 a repeat run at that base |

**Ticket** (`tracker/TICKET-perf-type-inference.md`, +15 lines): quotes 2.79 s / 23 %,
45.4 s / 24.7 %, 107 µs and 94 µs per `:365` walk, 12.1×, and says **"Start at `:648`, not at
`:365`"**. Consistent with §7.3 and with the P7 Step 1 framing.

**§0.2's six replacement sentences** — three for `SUBSUME-STAGE1A.md` (:289, :396, :488), two for
`SUBSUME-STAGE1A-REVIEW.md` (:226, :262), one for `SUBSUME-STAGE1B-REVIEW.md` (:215) — all six
say what the corrected data says: 45 s / 25 % of a 184 s suite, about 12× `:365`, `fskvs` 21.1 s
and `kindVars` 24.3 s, `:365` 3.7 s against `:648`'s 45 s, "six RUNNABLE samples" (matching the
§1.2 census). Each preserves the conclusion of the document it edits — correctly: no theorem and
no verdict moves, only the quantity and the direction of the "which site is costlier" comparison.

**Flag OFF, on the rebuilt tree, by me**: `bin/ermine <s>/repro/Bad.e` →
`Row partitions are unsatisfiable at field 'Bad.startDate'`, module **0.07 s**, wall 12.94 s,
`Loaded 129 modules (12.01 s)`, and **zero trace records on stdout or stderr**
(`<r>/recheck-cli-flagoff.log`). The implementer's `<s>/flagoff.log` is 12/12 in 189 s.

**Worktree**: exactly four modified files — `Subst.scala` (+157/−2),
`tracker/TICKET-perf-type-inference.md`, `tracker/satterm/SUBSUME-STAGE0.md`, and this review
(mine; untouched by the implementer, 516 lines before this section). `find core -name '*.ei'` =
**0**; `tracker/repl-classpath.txt` untouched. Nothing else changed.

### 7.5 Residuals (all cosmetic, none blocking)

1. **`SUBSUME-STAGE0.md` §0.2, the maxima sentence.** *"Per-call maxima (counts and per-call
   floors, which were always sound) are unchanged: `fskvs` max 5289.4 us, `kindVars` max
   5813.4 us"* — they are **not** unchanged: the first report's min1 row gave 6 ms / 12 ms, from
   a different build that also ran the now-removed `measure` thread. What is true is that the
   counts and the per-call floors were sound *as floors*. Fix: drop "are unchanged" and say
   "the accurate maxima on the fixed build are 5,289 µs (`fskvs`) and 5,813 µs (`kindVars`),
   against the first build's floor-based 6 ms / 12 ms".
2. **`SUBSUME-STAGE0.md` §1.5, "Run B".** The paragraph still reads "`:648` total **2,166 ms**,
   `checkSkolemEscape:365` **3,913 ms**" with no inline withdrawal, although the run-A bullet
   directly above it withdraws its own figure and §0.2 lists 2,166 ms as the OLD floor-sum. Fix:
   append "(floor-sum, withdrawn — §0.2: 45.4 s and 3.75 s on the nanosecond build)".
3. **`Subst.scala`, `SubsumeTrace.cse`.** `cseCalls.incrementAndGet()` sits INSIDE the timed
   region (between `body` and `System.nanoTime - t`), unlike `phaseFskvs`/`phaseKindVars`, which
   time the body alone. The bias is one uncontended atomic increment (~10–30 ns) on a 94–107 µs
   walk — 0.03 %, immaterial to every number in the report — but move the increment below the
   `bump` for symmetry, since `:365`'s figure is now the anchor the ticket is written against.

