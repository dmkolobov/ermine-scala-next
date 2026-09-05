# L4 — the trace test in `core/test`, and the parallel loader brought into the population

Stage L4 of `tracker/LOOP-MODEL-PLAN.md`. Implemented 2026-09-04, reviewed the same day
(`tracker/loopmodel/L4-REVIEW.md`, verdict FIX-THEN-ADVANCE), review findings F1–F5 applied and
re-verified. Every number below was run; where something was not run, this file says so.

**What the review changed.** F1 was a real hole and is fixed: the property used to report every
failure of its own compiler side — including a child JVM that never finishes, i.e. a diverging
solver, the exact failure this programme studies — as `SKIPPED` and `Prop.proved`. Only a
missing Lean binary skips now; everything else falsifies (§"The failure modes"). F2's flag gap
is fixed rather than merely documented: `-Dermine.*` is forwarded to both sides, which added
three `Inference` kinds to the property's coverage and turned up one honest failure
(`-Dermine.disjunction=true` does not finish on the compiler side). F3/F4/F5 are documentation
and are applied where the review asked.

## Part A — the property in `core/test`

**Result. `sbt core/test` now runs the Lean loop model against the real `Subst.solve` on 702
solves — the 17 tracked seeds at six id bases plus 600 generated satisfiable systems — and
requires the two traces to be byte identical, segment for segment. All 702 agree; the whole
comparison takes 2.6 s inside a 9-12 s `testOnly`. Two injected divergences are detected.**

### The design, and why

| decision | why |
|---|---|
| the compiler side is a **CHILD JVM** | `RowTrace.enabled` is `System.getProperty("ermine.rowTrace").nonEmpty` read once into a `val`, and `core`'s tests are **not forked** (`build.sbt`: `Test / fork := false`). A test therefore cannot turn tracing on for itself: by the time it runs, another suite may already have initialised `RowTrace`, and if none has, setting the property turns the trace on for **every** solve in the whole `core/test` run — `TestConstraints` alone performs thousands — appending them all to one file. Making `enabled` a `def` or a settable switch would put a live property read (or a volatile field) on the solver's default path, which the instrumentation may not do (L2 review F7 already treats one captured thunk per solve as worth noting). So the property launches `java -Dermine.rowTrace=<file> -cp <the classpath the test is running under>` and compares the file it writes. |
| the compiler path is the **real** one | `LoopTraceChild` builds a raw `Exists` over an exact constraint list at an exact id base on a fresh `SubstEnv`, and calls `Subst.solve` — the same in-process entry `tracker/repro/satterm/SatTermRepro.scala` uses. No stdlib boot, no module loading, nothing stubbed. `PQueue.build`, `Constraints.incorporateAll` and every rule under it run for real. |
| the classpath is taken from the **test classloader** | `Test / fork := false` makes `java.class.path` sbt's launcher and useless. `childClasspath()` walks the loader chain collecting `URLClassLoader` URLs (sbt's layered loaders are `URLClassLoader`s) and adds the code sources of `LoopTraceChild`, `RowTrace` and `scalaparsers.Supply` explicitly, so the child finds both test and main classes even if sbt's loader type changes. |
| the Lean side is `lake exe looptrace --replay` | the L2 path exactly: the child's trace carries the `sin`/`slbl`/`svar`/`scon` replay records, so the model re-runs each solve **at the compiler's own ids** and the two record streams are compared raw, with no normalisation. |
| **SKIP** when the model binary is absent | `tracker/lean/.lake/build/bin/looptrace` (override: `-Dermine.looptrace=<path>`). If it is not there — no Lean toolchain, or `lake build looptrace` never run — both properties print `SKIPPED: …` and return `Prop.proved`, so `core/test` has no hard dependency on Lean or on `lake`. Verified by running with `-Dermine.looptrace=/nonexistent/looptrace` (output below). |
| **one** batch, not one JVM per case | a `forAll` that forked a JVM per generated system would cost minutes. The systems are sampled once from a real ScalaCheck `Gen` with a fixed `Seed`, written to one job file, traced by one child JVM and replayed by one `looptrace` process; the per-segment assertions are then string comparisons. That is what keeps the whole thing at 2.6 s. |

### The population

| | |
|---|---|
| tracked seeds | all 17 `tracker/repro/satterm/seeds/*.json` (`W2 H2 NE6 W3 W4 G7` + the 11 regression seeds `CHAIN COLL D1 D2 D3 D4 LBL RE REF RR SUP`) |
| id bases | `0, 7, 41, 300, 1234, 65537` — six, because `V.hashCode` **is** the id and the queue is ordered by `rhs.hashCode`, so the base decides the dequeue order |
| generated systems | 600, from `genSystem`: a port of `tracker/tools/rowclosure.py`'s `gen_random` at the parameters L2's 2,000-system sweep used (k 3-7 variables, m 2-4 labels, n 2-6 constraints, `p_empty` 0.25, `p_dup` 0.25, `p_self` 0.04, `p_full_conc` 0.08). Every constraint is checked against the model with `satSets` — `rowclosure.py`'s own `sat_sets` assertion — before it is kept, so every system is **satisfiable by construction with a witness**. A third property asserts the sample's coverage: >= 10 % of systems have a right-hand side with two or more abstract parts, and >= 10 % carry a concrete part. |
| total | **702 solves = 702 trace segments** (`JOBS 702 solved=653 died=49`), of which **49 DIE** (`#summary … rejected=49`), all with `scalaparsers.Death`: 36 are the six seeds that exist to be refuted (`D1`-`D4`, `REF`, `SUP`) at six bases each, and 13 are generated systems. A died solve is still a segment the model must reproduce — the compiler writes its `step` records and no `solve` line, and `looptrace` answers `#REJECTED` — and the property compares those segments like any other |

**The 13 deaths among the generated systems are worth naming**, because they are not
refutations: every one is `panic: reinstantiated type v<i>^<n> to ConcreteRho(-,Set()) but it
was already bound to ConcreteRho(-,Set())` — one of the two reinstantiation panics
`L3-THEOREMS.md` lists as `died` paths that are NOT refutations — on a system that has a model
by construction. The rate (13 of 600, 2.2 %) matches L2's random sweep (48 of 2,000, 2.4 %).
This is a pre-existing compiler behaviour, not something L4 introduces; what matters here is
that the model reproduces the panic at the same step, so those segments agree like the rest.
The other 36 deaths are the expected refutations (`unsatisfiable at field 'Repro.lN'`, in the
three shapes the seeds were written for).

### The numbers

```
[loop model trace] 702 solves (17 seed x 6 bases + 600 generated); 702 segments; 702 agree; 2630 ms;
#summary  segments=702  replayed=702  skipped=0  hashdiff=0  eqdiff=0  nonpart=0  rejected=49  fuel=0
[loop model trace] control (id base +1): 47 of 702 segments disagree; control (--flags=nongen): 59 of 702
[info] + loop model trace.the generated systems really are satisfiable, and cover the shapes L4 needs: OK, proved property.
[info] + loop model trace.positive control: an injected divergence IS detected: OK, proved property.
[info] + loop model trace.the Lean loop model reproduces the compiler's trace, segment for segment: OK, proved property.
[info] Passed: Total 3, Failed 0, Errors 0, Passed 3
[success] Total time: 9 s
```

2,630 ms is the whole setup: writing the job file, the child JVM (start-up included), the
honest `looptrace --replay`, the two injected replays and all three comparisons. `sbt -batch
core/testOnly …TestLoopTrace` wall clock is 9-12 s, nearly all of it sbt. **Well inside the
~60 s budget the brief sets**; the sample was raised from an initial 268 segments to 702 on
that evidence and could go further.

### The positive control

Two injections, both asserted to be DETECTED by the second property:

* **a wrong id base** — every segment's `sin` record has its `Supply` bounds moved by one, so
  the model mints at ids the compiler did not use. 47 of 702 segments disagree. (Only the
  segments that MINT can: a solve that derives nothing draws no id, and its records are
  unchanged by the shift. That is why the control asserts "some segment disagrees", not "all".)
* **a wrong rule set** — the same trace replayed under `--flags=nongen`, which turns off the
  CSE, split and resolution mints. 59 of 702 segments disagree.

The id-base control is asserted **only when the configuration actually mints**, which the
property measures rather than assumes: it counts the trace records mentioning
`^ambiguous(free)` (576 at the shipped flags) and requires the injection to be detected iff
that count is nonzero. This was found by the F2 flag forwarding, not by reading — under
`-Dermine.genRules=nongen` no rule mints, the id shift moves nothing, and the control would
otherwise have asserted something false. The rule-set injection is asserted unconditionally,
and switches from `nongen` to `all` when the run is already at `nongen`, so it is always a real
injection (`0 of 702 (0 records mint)` and `--flags=all: 60 of 702` in that configuration).

`-Dermine.looptrace.inject=idbase|nongen` makes the FIRST property compare the injected replay
instead of the honest one, which is how the control is demonstrated end to end. Its output:

```
[loop model trace] INJECTION: idbase
[loop model trace] 702 solves (…); 702 segments; 655 agree; 2890 ms; …
[info] ! loop model trace.the Lean loop model reproduces the compiler's trace, segment for segment: Falsified after 0 passed tests.
[info] > Labels of failing property:
[info] model and compiler disagree:
[info] segments scala=702 lean=702 agree=655 bad=47
[info]   [learn] seg 36 G7@0
[info]     lean : learn G7@0  new  SplitConcrete: ^ambiguous(free)5 <- (^free2 ^free3,)
[info]     scala: learn G7@0  new  SplitConcrete: ^ambiguous(free)4 <- (^free2 ^free3,)
[info]   [learn] seg 37 G7@7
[info]     lean : learn G7@7  new  SplitConcrete: ^ambiguous(free)12 <- (^free9 ^free10,)
[info]     scala: learn G7@7  new  SplitConcrete: ^ambiguous(free)11 <- (^free9 ^free10,)
[info] Failed: Total 3, Failed 1, Errors 0, Passed 2
```

### The failure modes: what skips, and what fails (review F1)

The review's required fix. `setup` can end without a comparison for six reasons, and the first
version turned all six into `SKIPPED` + `Prop.proved`. Only the first is a skip:

| `setup` cannot run because | now |
|---|---|
| the Lean model executable is absent | **SKIP** — the property has nothing to say, and `core/test` must not depend on Lean |
| the child JVM did not finish in 180 s | **FAIL** — the likeliest cause is a solve that does not terminate, which is the exact failure this programme exists to catch |
| the child JVM exited non-zero | **FAIL** — the solver threw, or the child could not start |
| the child wrote no trace | **FAIL** — the instrumentation broke |
| the population is empty | **FAIL** — nothing was compared |
| anything else (`catch Throwable`) | **FAIL**, with the exception and six frames |

`setup`'s `Left` now carries `NoRun(skip: Boolean, why: String)`; `leanBin.canExecute` is the
only `skip = true`. A failing `NoRun` prints `FAILED, no comparison was made: …` and returns
`Prop.falsified :| why`, because a comparison that did not happen is not evidence that the two
sides agree.

**Demonstrated, all three, on the reviewer's own reproduction.** A scratch copy of the seed
directory with one file whose NAME contains a tab, so the child's wire line is unparseable and
`LoopTraceChild.main` throws outside its per-job `try`:

```
$ sbt -batch -J-Xmx3g -Dsatterm.seeds=<scratch>/badseeds "core/testOnly …TestLoopTrace"
[info] > Labels of failing property:
[info] the trace property could not run, so nothing was compared: the tracing child JVM exited 1:
[info] Exception in thread "main" java.lang.NumberFormatException: For input string: "NAME@0"
[info]   at com.clarifi.reporting.ermine.loopmodel.LoopTraceChild$.main$$anonfun$1(LoopTraceChild.scala:100)
[info] Failed: Total 3, Failed 2, Errors 0, Passed 1
[error] (core / Test / testOnly) sbt.TestsFailedException: Tests unsuccessful       sbt exit=1
```

(before the fix, the same command printed `SKIPPED: …` and `Passed: Total 3, Failed 0, Passed 3`
with 0 of the 702 solves compared)

```
$ sbt -batch -J-Xmx3g -Dermine.looptrace=/nonexistent/looptrace "core/testOnly …TestLoopTrace"
[loop model trace] SKIPPED: the Lean model executable is absent (/nonexistent/looptrace); build it
  with `cd tracker/lean && lake build looptrace`, or point -Dermine.looptrace at it. `lake` itself
  is only needed for that build.
[info] + loop model trace.positive control: an injected divergence IS detected: OK, proved property.
[info] + loop model trace.the Lean loop model reproduces the compiler's trace, segment for segment: OK, proved property.
[info] + loop model trace.the generated systems really are satisfiable, and cover the shapes L4 needs: OK, proved property.
[info] Passed: Total 3, Failed 0, Errors 0, Passed 3                      [success] Total time: 2 s

$ sbt -batch -J-Xmx3g "core/testOnly …TestLoopTrace"
[info] + loop model trace.the generated systems really are satisfiable, and cover the shapes L4 needs: OK, proved property.
[loop model trace] control (id base +1): 47 of 702 segments disagree (576 records mint); control (--flags=nongen): 59 of 702
[loop model trace] 702 solves (17 seed x 6 bases + 600 generated); 702 segments; 702 agree; 2692 ms;
                   #summary segments=702 replayed=702 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=49 fuel=0
[info] + loop model trace.positive control: an injected divergence IS detected: OK, proved property.
[info] + loop model trace.the Lean loop model reproduces the compiler's trace, segment for segment: OK, proved property.
[info] Passed: Total 3, Failed 0, Errors 0, Passed 3                      [success] Total time: 4 s
```

### Rule flags, forwarded to both sides (review F2)

The property used always to run the SHIPPED defaults on both sides, whatever `-Dermine.*` the
run was given: correct, but it meant `sbt -Dermine.emptyRow=true core/test` silently tested the
default configuration. Now `flagMap` forwards each set switch to the child as `-D…` and
translates it into the model's `--flags` token; a value with no token is a hard FAILURE, not a
silent fallback. Every setting, run:

| `sbt -batch -J-Xmx3g <flag> core/testOnly …TestLoopTrace` | model `--flags` | result |
|---|---|---|
| *(none — the shipped defaults)* | — | **702/702**, controls 47 / 59 |
| `-Dermine.genRules=all` | `all` | **702/702** — and `CommonSubexpressionMint` fires **6** times |
| `-Dermine.genRules=nongen` | `nongen` | **702/702**; 0 records mint, so the id-base control is not asserted and the rule-set control switches to `--flags=all` (60 of 702) |
| `-Dermine.emptyRow=true` | `emptyrow` | **702/702** — and `SplitEmpty` **12**, `ResolutionEmpty` **4** fire |
| `-Dermine.splitKey=false` | `nosplitkey` | **702/702** |
| `-Dermine.splitRow=false` | `nosplitrow` | **702/702** |
| `-Dermine.resRow=false` | `noresrow` | **702/702** |
| `-Dermine.labelCheck=false` | `nolabel` | **702/702** |
| `-Dermine.labelCheckEarly=false` | `lateLabel` | **702/702** |
| `-Dermine.resGuard=false` | `noresguard` | **702/702** |
| `-Dermine.disjunction=true` | `disj` | **FAILS**: the CHILD (the compiler) does not finish 702 solves in 180 s |

The last row is not a model disagreement and not a regression: `L2-CORPUS.md` §4c/§10 already
records that a sweep with `Disjunction` on finishes on **neither** side (the compiler did not
get through the stdlib boot in 14 minutes; the model's `--flags=disj` replay of the boot trace
was still running after 92). What is new is that the property now SAYS so — under the old code
this was a `SKIPPED` and a pass. The child's budget is deliberately left at 180 s for 702 tiny
solves; raising it would hide exactly the signal F1 is about. The timeout message names the
flags in force and points at the `Disjunction` scope limit so the reader is not misled.

Two things this bought beyond closing the gap: `emptyRow=true` agreeing 702/702 says M4 does
not bite on self-contained per-solve systems (consistent with M4, which is about the compiler's
WHOLE-INFERENCE environment — these solves have none — and not evidence against it), and the
`genRules=all` / `emptyRow` runs add three `Inference` kinds to what `core/test` exercises.

### What the comparison checks, and what it does not

`compare` reimplements `tracker/tools/looptrace-diff.py --segments` in Scala, so the property
needs no python: the compiler side splits at `sin` (per thread, and with the L4 thread-id
column stripped), the model side at `#seg`, pairs by index and compares the `step` / `learn` /
`in` / `inpart` / `sat` / `solve` records as raw strings. A `#skip`, a nonzero `#hashdiff` or a
nonzero `#eqdiff` is a FAILURE, not an AGREE (this is L2 review F8, fixed on both sides).
`concr` / `splice` (from `reduce`, after the loop) and `ex` are outside the model and outside
the comparison, exactly as in L2. A `#FUEL` segment is a failure too (review F5), and the
property additionally asserts the model's own `#summary` line says `skipped=0` and `fuel=0`, so
the per-segment verdict and the model's tally have to agree.

**What the 702 solves REACH, measured rather than assumed** (review F2). All five dispatch
branches — `empty` 818, `concrete` 674, `learn` 619, `unify` 450, `common` 157 — and nine of the
sixteen `Constraints.Inference` kinds: `Substitution` 194, `Cancellation` 189, `SplitConcrete`
121, `CommonSubexpression` 118, `SelfSubstitution` 61, `Resolution` 21, `SplitKeyed` 18,
`DeDuplication` 18, `SplitRow` 3. Three more fire under a forwarded flag (`CommonSubexpressionMint`
6, `SplitEmpty` 12, `ResolutionEmpty` 4). **`ResolutionRow`, `PartitionEmpty`, `CommonPartition`
and `Disjunction` never fire in any configuration of this population** — the corpus does reach
`ResolutionRow` (nine times in one `gu05` solve), so a change confined to those branches is
caught by `looptrace-corpus.sh` and not by `core/test`. Note that `RR.json` and `RE.json` ARE in
the population and do NOT fire the rules they are named for: at the shipped flags the loop takes
the `concrete` branch on their input before any resolution branch becomes reachable (`RR@0`'s
four `step` records are all `concrete`). Nor does the property reach an existential (`ex`
records: 0), a `Skolem` or `Ambiguous` input variable, `.nf`-normalised input, or the
CONSTRUCTION of the loop's input — both sides replay the compiler's own `sin`/`scon` records, so
a change before `RowTrace.solveInput` moves them together (L2 review F3, inherited). All of this
is in the test's header comment and in the README rule.

### `core/test` totals

Re-run in full AFTER the review fixes (the run that counts):

```
$ sbt -batch -J-Xmx3g core/test                                                     # rc=1, 280 s
[loop model trace] 702 solves (17 seed x 6 bases + 600 generated); 702 segments; 702 agree; 7179 ms;
                   #summary segments=702 replayed=702 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=49 fuel=0
[loop model trace] control (id base +1): 47 of 702 segments disagree (576 records mint); control (--flags=nongen): 59 of 702
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
[info] Failed: Total 914, Failed 1, Errors 0, Passed 913
```

**914 tests, 913 passed, 1 failed** — identical to the pre-fix run (914/913/1, 280 s and 284 s),
so the F1/F2 changes moved nothing except the failure modes they were meant to move. The one
failure is the known `Constraints.disjunction sound` starvation, which the L2 review already
recorded as the only `core/test` failure on this tree; L4 adds 3 tests (911 -> 914) and no
failures. The 7,179 ms (8,670 ms before the fixes) is the property's setup inside the full run,
against 2,7xx ms for the same work in an isolated `testOnly` — the full run shares the machine
with the rest of the suite and, in both cases, with this stage's own background replay.

## Part B — the thread id, and the parallel loader

**Result. Every trace record now ends with a thread id; a trace written by the SHIPPED
(parallel) loader is regrouped per thread into one whose solves are contiguous, and both
sides then read that file. `Ai` under the parallel loader: 83,942 segments over 12 threads,
5,599 of them interleaved in the raw trace — 83,942 AGREE, 0 skip, 0 hashdiff, 0 eqdiff.
`incomplete/gu05` under the parallel loader: 54,235 segments over 12 threads, 5,212
interleaved — 54,235 AGREE, 0 skip, and that INCLUDES the expensive solve the serialized
loader never produces (`nSat` 458 against the serialized 83). The plan's first known scope
limit is closed.**

### The instrumentation

`RowTrace.log` appends `"\t" + tid` to every record it writes (+33/−1 lines in
`RowTrace.scala`, the only compiler file L4 touches). `tid` is a small dense integer handed
out per thread on first use (`t0`, `t1`, …) rather than `Thread.getId`, so the ids are
readable, stable across runs and narrow on a 500 MB trace. It is read inside `log`'s
`if (enabled)`, so **the default path is unchanged** — no extra field, no extra read.

Because `RowTrace.log` is the only emitter, the column reaches EVERY record type with no
per-call-site change: checked on the 120,031-record `gu05` trace, all thirteen types present
(`solve` 54,235, `sin` 54,235, `learn` 2,943, `scon` 2,027, `svar` 1,770, `step` 1,444, `sat`
1,110, `in` 772, `inpart` 762, `ex` 448, `splice` 249, `concr` 26, `slbl` 10) and **0 lines
whose last field is not `t<N>`**, likewise on the 137,493-record parallel trace.

The column is APPENDED so that every reader indexing from the START of a record keeps working.
Verified rather than assumed, by running each tool on the same 17 MB `gu05` trace twice, once
with the column and once with it stripped by `sed 's/\t[^\t]*$//'`:

| tool | result |
|---|---|
| `tracker/tools/keptdef-mints.py` | **byte-identical output** |
| `tracker/tools/splitkey-counts.py` | identical apart from the file NAME it prints |
| `tracker/tools/rowtrace-summary.py` | identical apart from the file NAME it prints |
| `Loop/Replay.lean`'s parsers | read only, not run in isolation: every record pattern ends in a `_` or a `rest` (`"slbl" :: … :: str :: _`, `"svar" :: … :: rest`, `"scon" :: … :: rest` with `rest.headD ""`, `"sin" :: … ` with `blk :: bsz :: nr :: _`), so a trailing field is ignored. Confirmed EMPIRICALLY by the regression runs below, which replay traces that carry the column and agree byte for byte |
| `looptrace-diff.py` | STRIPS it, auto-detecting from the `sin` record's field count (`--thread-column=yes|no|auto`). Checked in all three of its modes: the L1 PLAIN mode re-run on the six tracked seeds (`W2 H2 NE6 W3 W4 G7`, id-normalised against `looptrace <seed> <base>`) — **all six AGREE**, 11 / 61 / 48 / 24 / 13 / 22 records; `--segments` throughout Part B; and a **pre-L4** trace (the same `gu05` file with the column stripped) still gives 54,235/54,235 AGREE, so the auto-detection is not one-way |

### The segmenter, and why a file-level regroup was needed

`looptrace-diff.py --segments` now demultiplexes: records attach to the open segment **of their
own thread**. That fixes the compiler side. It does not fix the model side, because
`looptrace --replay` — which is a Lean file this stage may not edit — opens a segment at every
`sin` in FILE order and folds the `slbl`/`svar`/`scon` records that follow into the most recent
one, with no notion of a thread. So the script gained `--demux RAW.tsv --out DEMUX.tsv`: a
streaming regroup that emits each thread's segments whole, holding only the segment currently
open on each thread (a 500 MB trace costs a few threads' worth of records, not the file).
`looptrace-corpus.sh` inserts that step when `LOOPTRACE_SERIES=false`, and BOTH sides then read
the regrouped file, so the segment indices line up by construction. Two checks that it is only
a reordering: on the parallel `gu05` trace the output is a permutation of the input (same
`md5sum` after `sort`, 0 records dropped, same 137,493 lines), and on the SERIALIZED `gu05`
trace it is a **byte-identical copy** (`cmp` silent), so nothing about the L2 path changes.

### Regression: the serialized population still agrees, with the column present

| run | compiler | segments | threads | model | AGREE | skip | hashdiff | eqdiff |
|---|---|---|---|---|---|---|---|---|
| `Ai`, serialized | 20 s | **83,942** | 1 | 19,075 ms | **83,942** | 0 | 0 | 0 |
| `incomplete/gu05`, serialized | 16 s | **54,235** | 1 | 17.1 s | **54,235** | 0 | 0 | 0 |

Both segment counts are L2's to the digit (`L2-CORPUS.md` §4a for `Ai`, §8 for `gu05`), so the
thread column changed nothing about the L2 result.

### The parallel loader

| run | compiler | segments | threads | interleaved | model | AGREE | skip | hashdiff | eqdiff |
|---|---|---|---|---|---|---|---|---|---|
| `Ai`, parallel + demux | 20 s | **83,942** | 12 | 5,599 | 24,037 ms | **83,942** | 0 | 0 | 0 |
| `incomplete/gu05`, parallel + demux | 17 s | **54,235** | 12 | 5,212 | **631 s** | **54,235** | 0 | 0 | 0 |

"interleaved" is the number of segments into which another thread wrote between two of their
own records — exactly what the regroup repairs. The independent L2 §8 signature agrees:
**2,354 of `gu05`'s 54,235 raw parallel segments contain more than one `solve` record**
(L2 measured 1,654 on their run; the exact number is thread timing), and after the demux
**0** do, as in the serialized trace.

### The control: the demux is load-bearing

The same parallel `Ai` trace replayed WITHOUT the regroup:

```
segments: scala=83942 lean=83942 compared=83942
AGREE   83810
SKIP    132
class SKIP     132
  [SKIP] seg 2976  trySolveOn  …/modules/Primitive.e(27:24)
      lean : skip: scon count 0 != nCs 1
  [SKIP] seg 2990  trySolveOn  …/modules/Syntax/Do.e(46:8)
      lean : skip: scon count 1 != nCs 0
exit status 1
```

132 segments become unreplayable, with the interleaving signature (`scon` records of one
thread landing inside another thread's input block). They go to 0 with the regroup. Note what
this also says: the reason only 132 of the 5,599 interleaved segments broke is that the
segmenter's own per-thread demultiplexing already repairs the OUTPUT side — the model's records
are recomputed, not copied — so the file-level regroup is needed specifically for the model's
INPUT records (`sin`/`slbl`/`svar`/`scon`).

### gu05's big solve

The brief asks about "gu05's 1,372-partition solve". Its size depends on `-Dermine.splitKey`,
which was adopted 2026-09-02 and is now ON by default (`Constraints.scala:887`); the 1,372
figure in `tracker/satterm/KEYED-SPLIT-STAGE2.md` §B7 is the flag-OFF column, and §B7's flag-ON
column is 458. Measured here, on the same module, one JVM each:

| | serialized | parallel, shipped flags | parallel, `-Dermine.splitKey=false` |
|---|---|---|---|
| largest `nSat` at `gu05…e(62:1)` | **83** | **458** | **1,456** |
| trace records | 120,031 | 137,493 | 233,942 |
| model replay | 17.1 s (whole file) | 631 s (whole file) | did not finish — see below |
| replays and AGREES | yes (54,235/54,235) | **yes (54,235/54,235)** | not established |

458 reproduces `L2-CORPUS.md` §8 and `KEYED-SPLIT-STAGE2.md` §B7 exactly. 1,456 is the same
solve as their 1,372 — the exact count is decided by thread timing, which is what makes it a
parallel-loader phenomenon in the first place.

**So the answer to the brief's question is: YES at the shipped flags.** The expensive solve the
parallel loader produces — 458 saturated partitions, 400 derived, against 83 serialized —
replays in the Lean model and agrees with the compiler record for record, inside a run in which
all 54,235 of gu05's segments agree. Its own model time dominates that run: 54,223 of the
54,235 segments replay in under 60 s and the whole file takes 631 s.

**The flag-OFF variant (`nSat` 1,456) was launched and had not finished when this report was
written.** `-Dermine.splitKey=false` was traced (22 s), demuxed (54,235 segments, 12 threads,
6,267 interleaved) and the 1,456-partition segment extracted whole into its own 115,678-record
file; `looptrace --replay … --flags=nosplitkey` on it has used **79 minutes of CPU** without
producing its `#seg` line (31 min when this report was first written, 57 min when the review
closed), against roughly 570 s for the 458-partition version of the same solve. It replays a
single-segment file, so it emits nothing at all until that one segment finishes. That is a MODEL PERFORMANCE observation, not a disagreement — nothing has been compared
yet, and nothing may be concluded from it either way. It is consistent with `L2-CORPUS.md` §9,
which already names `SSet.champSort`'s per-element re-hashing as the model's cost centre and
its fix as an L4-or-later item; this stage did not take that on, because it changes a
definition `Bridge.lean` reasons about and the Lean files were off limits here.

The process was LEFT RUNNING under its own `timeout 21600` and writes
`/home/dmitry/.claude/jobs/880c725d/tmp/L4/gu05nk/big.model.out` with the outcome in
`big.model.rc`, so the answer can simply be read later; the extracted input it is replaying is
`gu05nk/big.tsv` in the same directory, and the diff to run against it is

```bash
python3 tracker/tools/looptrace-diff.py --segments \
  --lean .../gu05nk/big.model.out --scala .../gu05nk/big.tsv
```

The whole demuxed flag-off trace is `gu05nk/par.dx.tsv.gz`, regenerated by the commands below
with `-Dermine.splitKey=false` added to `ERMINE_JAVA_OPTS`.


## The exact commands

```bash
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
export PATH=$HOME/.elan/bin:$PATH

# Part A
cd tracker/lean && lake build looptrace && cd ../..     # the model executable the property needs
sbt -batch -J-Xmx3g core/test                           # the property runs among everything else
sbt -batch "core/testOnly com.clarifi.reporting.ermine.loopmodel.TestLoopTrace"
sbt -batch -Dermine.looptrace.inject=idbase  "core/testOnly …TestLoopTrace"   # the control, end to end
sbt -batch -Dermine.looptrace.inject=nongen  "core/testOnly …TestLoopTrace"
sbt -batch -Dermine.looptrace=/nonexistent   "core/testOnly …TestLoopTrace"   # the skip path
sbt -batch -Dermine.looptrace.keep=true      "core/testOnly …TestLoopTrace"   # keep the scratch trace

# Part B
LOOPTRACE_GROUPS=Ai LOOPTRACE_SERIES=false tracker/tools/looptrace-corpus.sh <outdir>
python3 tracker/tools/looptrace-diff.py --demux RAW.tsv --out DEMUX.tsv       # by hand
tracker/lean/.lake/build/bin/looptrace --replay DEMUX.tsv > model.out
python3 tracker/tools/looptrace-diff.py --segments --lean model.out --scala DEMUX.tsv --per-thread
```

`looptrace-diff.py` gained `--demux RAW --out DEMUX`, `--per-thread` and
`--thread-column=auto|yes|no`; `looptrace-corpus.sh` gained `LOOPTRACE_SERIES` (default `true`,
i.e. the L2 behaviour) and reports `threads=` and `demux=` per group.

## Files

| file | lines | what |
|---|---|---|
| `core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/TestLoopTrace.scala` | **743** | **NEW**: the three properties, the seed reader, the generator, the classpath discovery, the rule-flag forwarding and the segment comparison |
| `core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/LoopTraceChild.scala` | **119** | **NEW**: the child JVM that takes the trace through the real `Subst.solve` |
| `core/src/main/scala/com/clarifi/reporting/ermine/RowTrace.scala` | 252 (+33, -1) | the thread-id column: `nextTid`, `tid`, and `log` appending it |
| `tracker/tools/looptrace-diff.py` | 508 (+206, -16) | per-thread segmentation, `--demux`, `--per-thread`, `--thread-column`, and the F8 exit status |
| `tracker/tools/looptrace-corpus.sh` | 128 (+39, -12) | `LOOPTRACE_SERIES=false`, the demux step, `threads=`/`demux=` in the results line, and the per-file-cut note (review F4) |
| `tracker/lean/README.md` | +67 (mine) | the `### L4` subsection: THE RULE, plus (review F2) how far the property's half of it reaches. The file's unstaged diff is larger because the L3/L5 agents edit it too |
| `tracker/LOOP-MODEL-PLAN.md` | L4 row + 2 bullets | the L4 status row; the parallel-loader scope limit marked **PARTIALLY CLOSED** with what is still open (review F3, bullet KEPT, not struck through); a note on the `emptyRow` bullet |
| `tracker/loopmodel/L4-TEST.md` | this file | this report |

**No Lean file was touched** (the L3 agent is working under `tracker/lean/Rowpartition/Loop/`),
and no staged file other than `RowTrace.scala` and the two trace tools. Nothing was committed;
no stray `.ei` was left (`find core/examples -name '*.ei' | wc -l` = 0); every trace kept under
`/home/dmitry/.claude/jobs/880c725d/tmp/L4/` is gzipped. `core`'s MAIN sources compiled once,
for the `RowTrace` change (`sbt -batch core/Test/compile`, 6 s); the TEST sources recompiled a
handful of times while the property was written and again for the review fixes, which is
`core/Test/compile` only and never touches the compiler.

## What I could not do, and what is still open

1. **The parallel sweep covers `Ai` and `incomplete/gu05` only**, which is what the brief asked
   for. The other six corpus groups have not been re-run under `LOOPTRACE_SERIES=false`. There
   is no reason to expect a different answer — the mechanism is the same and `Ai` is the
   largest group — but it has not been run.
2. **`looptrace-corpus.sh`'s per-file TIMEOUT cut is not thread-aware.** When a file in a
   `LOOPTRACE_PERFILE` group (i.e. `incomplete/`) times out, the script drops everything from
   the LAST `sin` in FILE order, which is the right cut only for a serialized trace; under the
   parallel loader one segment per thread may be left truncated. Nothing in this stage hit it
   (`gu05` finished in 17 s of a 120 s budget, `Ai` is not a per-file group), and the fix is to
   cut per thread. It **cannot cause a false agreement** (review F4): a truncated segment either
   loses its `scon` block, and the model answers `skip: scon count != nCs` — a SKIP, counted as
   bad, exit 1 — or loses trailing records the model recomputes, giving `length+`, also bad.
   That is now stated in the script's header.
3. **The MODEL still cannot demultiplex.** `Loop/Replay.lean` opens a segment at every `sin` in
   file order, so the regroup has to happen in the tool before `--replay` sees the trace. That
   is a consequence of this stage not being allowed to edit Lean, not a design decision; a
   `--demux` inside `looptrace` would make the extra file unnecessary.
4. **The generated systems are a Scala PORT of `rowclosure.py`'s `gen_random`, not the python
   itself.** Same shape, same parameters, same `sat_sets` check — but `scala.util.Random` and
   Python's Mersenne Twister do not draw the same numbers, so these are not literally L2's
   2,000 systems. The property asserts the sample's coverage rather than assuming it.
5. **The 1,456-partition (`-Dermine.splitKey=false`) variant of gu05's big solve was not
   compared.** Its replay was still running when this was written; see "gu05's big solve". The
   brief's question is answered at the SHIPPED flags, where the same solve saturates 458 and
   does replay and agree, but the flag-off number in `KEYED-SPLIT-STAGE2.md` §B7 has no
   model-side result here.
6. **`Disjunction` is still seed-only** (the plan's second scope limit), and `emptyRow`'s M4
   abstraction is untouched. Neither is in L4's scope.
7. **`core/test` was not re-run on a clean tree for a before/after comparison.** The totals
   quoted are this tree's, and the arithmetic (911 -> 914 tests, +3 = the new properties) is
   the only evidence that nothing else changed.
8. The 2.6 s figure for the property's setup is from an isolated `testOnly`. Inside the full
   `core/test`, with two of this stage's own background replays competing for the machine, the
   same setup took 8.7 s. Both are far inside the ~60 s budget; neither is a floor.
