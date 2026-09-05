# L4 review — the trace test in `core/test`, and the parallel loader

Reviewer agent, 2026-09-04. Protocol: `tracker/loopmodel/briefs/brief-review.md` — trust nothing
not re-run. Under review: the unstaged L4 changes — `RowTrace.scala`'s thread-id column,
`core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/{TestLoopTrace,LoopTraceChild}.scala`,
`tracker/tools/looptrace-diff.py`, `tracker/tools/looptrace-corpus.sh`,
`tracker/loopmodel/L4-TEST.md`, and the additive README / plan edits. Pre-existing and NOT under
review: the staged L2 state, the unstaged L3 Lean modules
(`Loop/{Wf,Order,Refine,RefineConcrete,RefineLearn}.lean` + the root import lines), and whatever
the running L5 agent adds under `tracker/lean/`. No Lean file was edited or rebuilt by this
review; nothing outside this report and
`/home/dmitry/.claude/jobs/880c725d/tmp/review-L4/` was written.

## 0. Verdict

**FIX-THEN-ADVANCE.** Everything the report claims that I re-ran, reproduced — to the digit where
the number is deterministic (702/702, 47, 59, 914/913, 83,942, 54,235, nSat 458) and to the
expected timing jitter where it is not (threads 13 vs 12, interleaved 6,156/5,512 vs 5,599/5,212,
raw-control skips 116 vs 132). The compiler side is the shipped `Subst.solve` with nothing
stubbed, the child JVM demonstrably runs the freshly compiled classes, the generator's
satisfiability check is sound, and the thread column is inert on the default path. The headline
Part B claim I checked by itself and not by inference: the 458-partition solve is segment 54226 of
my own demuxed parallel `gu05` trace, and its 18,747 model records equal the compiler's 18,747
byte for byte.

One required fix, F1: **the property turns a failure of the compiler side into a PASS.** Every
`Left` of `setup` — child JVM crashed, child JVM did not finish in 180 s, no trace written, any
exception — prints `SKIPPED:` and returns `Prop.proved`. I reproduced this: with a deliberately
broken job the child exits 1 and `core/testOnly` reports `Passed 3`. The case that matters is the
timeout: a solver change that makes `incorporateAll` diverge — the exact failure this whole
programme is about — makes the guard property green. Everything else I found (F2-F5) is
documentation or a nit.

Required before advance:
* **F1** — only `leanBin.canExecute == false` may skip; the other five `Left`s must falsify.

Recommended, not blocking: F2 (state the property's rule coverage in the README rule, six of the
fifteen `Inference` kinds never fire in the 702 solves), F3 (the plan's scope-limit item is
partially, not fully, closed — 2 of 8 groups swept under the parallel loader).

## 1. The default path in `RowTrace.scala` — PASS

`git diff` on `RowTrace.scala` is +33/−1: a doc block, `nextTid` (an `AtomicInteger`), `tid0` (a
`ThreadLocal[String]`), `def tid`, and

```scala
  def log(record: => String): Unit =
    if (enabled) {
      val line = record + "\t" + tid
      out.synchronized { out.println(line); out.flush() }
    }
```

The thread id is read **inside** `if (enabled)` (`RowTrace.scala:157-161`); with
`-Dermine.rowTrace` unset `log` is the same single boolean test on a `val` it was before, and the
by-name `record` is still not forced. The only added cost on a traced-off run is two object
allocations at `RowTrace`'s own class initialisation (`AtomicInteger`, `ThreadLocal`) — not per
call, not per solve. `enabled` is still `val enabled = path.nonEmpty` (line 108) and `log` is the
only emitter of a record body, which is what makes the column reach every record type without a
per-call-site change. **Confirmed by reading; no divergence from the report's claim.**

## 2. Part A re-run — every number reproduced

`ps` was clear of `java`/`bin/ermine` before each `sbt`; only the L5 agent's `looptrace` processes
(native Lean) and the L4 stage's own `big.tsv` replay were running. One `sbt` at a time throughout.

| command | result | report says |
|---|---|---|
| `sbt -batch -J-Xmx3g core/test` | **Total 914, Failed 1, Errors 0, Passed 913**, 282 s; the one failure is `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded` | 914 / 913 / the same starvation ✓ |
| — its property line | `702 solves (17 seed x 6 bases + 600 generated); 702 segments; 702 agree; 8031 ms; #summary segments=702 replayed=702 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=49 fuel=0` | 702/702, 8,670 ms ✓ (8,031 here) |
| — its control line | `control (id base +1): 47 of 702 segments disagree; control (--flags=nongen): 59 of 702` | 47 / 59 ✓ |
| `sbt -batch -Dermine.looptrace.inject=idbase core/testOnly …TestLoopTrace` | **rc=1**, `Falsified after 0 passed tests`, `segments scala=702 lean=702 agree=655 bad=47`, `Failed: Total 3, Failed 1, Passed 2` | ✓ identical |
| `… -Dermine.looptrace.inject=nongen …` | **rc=1**, `agree=643 bad=59`, `Failed 1, Passed 2` | ✓ (the report quotes only the idbase transcript; the nongen numbers match its 59) |
| `… -Dermine.looptrace=/nonexistent/looptrace …` | **rc=0**, `SKIPPED: the Lean model executable is absent …`, `Passed: Total 3, Failed 0, Passed 3`, 2 s | ✓ |

The sample is deterministic: three separate runs produced byte-identical 702 / 47 / 59.

**Independent cross-check of the Scala comparison.** `TestLoopTrace.compare` is a
re-implementation of `looptrace-diff.py --segments`; a bug there would make the property vacuous
in a way the property itself cannot see. I re-ran the python tool on the artefacts the test
keeps under `-Dermine.looptrace.keep=true`:

```
model-honest.out  vs trace.tsv : segments 702/702, AGREE 702, SKIP 0, hashdiff 0, eqdiff 0   exit 0
model-shifted.out vs trace.tsv : AGREE 655, class learn 47                                    exit 1
model-nongen.out  vs trace.tsv : AGREE 643, class in 16 / learn 8 / step 35                   exit 1
```

The python agrees with the Scala on all three, segment count and disagreement count. The first
divergence it prints for the shifted replay is the same one the report quotes
(`seg 36 G7@0`, `^ambiguous(free)5` vs `4`).

**L2 review F8 (exit status), re-verified independently.** I injected a `#hashdiff 5 1` line and,
separately, an `#eqdiff 5 2` line into an otherwise perfect model output:

```
hd exit=1   AGREE 702   hashdiff segments: 1
ed exit=1   AGREE 702   eqdiff  segments: 1
```

so `--segments` now exits non-zero on a hash/equals-class disagreement even when every record
matches. `TestLoopTrace.compare` does the same (`l.hashdiff > 0 || l.eqdiff > 0` ⇒ `bad`), so the
two sides of F8 agree.

## 3. The two test sources against `SatTermRepro` and `Subst.solve`

### 3a. Is the compiler side the shipped path? — YES

`LoopTraceChild.main` builds, per job, `new Part(Loc.builtin, VarT(v), rhs)` and
`new Exists(Loc.builtin, List(), parts)` and calls `RowTrace.withSite(site)(Subst.solve(ex))` with
a fresh `SubstEnv`, a reflectively constructed `Supply` and `tml = Loc.builtin`. Read against
`tracker/repro/satterm/SatTermRepro.scala` (`system`, `runCapped`) and
`tracker/repro/nameloss/Replay.scala` (`supplyAt`, `tv`, `part`), the construction is the same one
line for line:

| | `SatTermRepro` / `Replay` | `LoopTraceChild` |
|---|---|---|
| variable | `V(Loc.builtin, id, Some(Local(name)), Free, Rho(Loc.builtin))` | identical (`tv`, line 62) |
| ids | `base + i` over `vars.distinct.sorted` | identical (`build`, line 68) |
| supply | private ctor, `(lo, lo + 100000)` | identical (`supplyAt`, line 51) |
| label | `Global("Repro", "l" + n)` | identical (`label`, line 60) |
| constraint | `new Part(...)`, raw, bypassing the smart constructor | identical |
| system | `new Exists(loc, List(), parts)`, raw, so `solve` receives the written order | identical |
| entry | `Subst.solve` | `Subst.solve` |

Nothing is stubbed: `solve` runs `RowTrace.solveInput`, `PQueue.build`, `Constraints.incorporateAll`
and `reduce` for real. The difference from production is *input construction*, not solver
substitution: the child never passes `ex.nf`, its systems carry no existentials (`ex` records: 0
in the 702-solve trace) and every variable is `Free` and named. Those shapes are covered by L2's
corpus, not by this property — worth a line in the report, not a defect.

Coverage the 702 solves actually reach, measured on the kept trace:

* all five dispatch branches — `empty` 818, `concrete` 674, `learn` 619, `unify` 450, `common` 157;
* nine of the fifteen `Inference` kinds — `Substitution` 194, `Cancellation` 189, `SplitConcrete`
  121, `CommonSubexpression` 118, `SelfSubstitution` 61, `Resolution` 21, `SplitKeyed` 18,
  `DeDuplication` 18, `SplitRow` 3 (`learn` records: 487 new, 256 seen);
* **never reached**: `ResolutionRow`, `SplitEmpty`, `ResolutionEmpty`, `CommonSubexpressionMint`,
  `PartitionEmpty`, `CommonPartition` (see F2).

### 3b. Is the child's classpath the classes the test runs under? — YES, verified

`childClasspath()` seeds a `LinkedHashSet` with the code sources of `LoopTraceChild`, `RowTrace`
and `scalaparsers.Supply` **first**, then the `URLClassLoader` chain, then `java.class.path` last;
first match wins in the child, so nothing appended later can shadow the classes sbt just loaded.
Empirically: the trace the child wrote has **ten** fields on its `sin` records and every record
ends in `t0` — the thread column exists only in this working tree's uncommitted `RowTrace.scala`,
so the child cannot have loaded a stale `core/target` or a published jar. A stale-classes failure
would also be loud rather than silent, since the parent's `SinFields = 9` detection would then
strip a real field.

One real gap, no false pass: `-Dermine.*` properties are **not** forwarded to the child. The child
always runs the shipped defaults (`ermine.genRules=cut`, `splitKey`, `splitRow`, `resRow`,
`labelCheckEarly`, `resGuard` on; `emptyRow`, `disjunction` off) and `looptrace` is invoked with
no `--flags`, i.e. also the shipped defaults, so the two sides still agree and `sbt
-Dermine.splitKey=false core/test` is green — but it did not test `splitKey=false`. A change to a
*default in the source* is caught (the child picks it up, the model does not). Worth one sentence
in the test header.

### 3c. Is the generator's satisfiability check sound? — YES

`satSets(rho, lhs, vs, ks)` requires `Σ|part| == |⋃part|` (pairwise disjointness) and
`⋃part == rho(lhs)` for `parts = ks :: vs.map(rho)` — exactly the semantics of
`lhs <- (v…, (|K|))`, and exactly `rowclosure.py`'s `sat_sets`. Every constraint is checked
against the **same** `rho` before it is kept, so `rho` is a model of the whole system.

The two ways such a check is usually unsound are closed by construction:
* **a repeated variable in the group** would make `Σ|part| == |⋃part|` pass for empty rows. It
  cannot occur: `cands` is a shuffle of `(0 until k).filter(v => v != a && rho(v).nonEmpty …)`, so
  `group` is distinct and disjoint from `empties`, and the self branch is `a :: empties` with `a ∉
  empties`.
* **the built constraint differing from the checked one**: `ks.isEmpty` builds *no* concrete part
  and `satSets` contributes `∅` to the union — the same constraint. `a <- ()` is generated (59.5 %
  of systems have one) and is satisfiable exactly when `rho(a) = ∅`, which is what the check asks.

Observationally: of the 49 deaths in the 702 solves, the 36 refutations (`Row partitions are
unsatisfiable at field 'Repro.lN'`, in the three documented shapes) are **all** from the six seeds
written to be refuted — `D1 D2 D3 D4 REF SUP`, six bases each — and the 13 generated-system deaths
are **all** `panic: reinstantiated type vN^N to ConcreteRho(-,Set()) but it was already bound to
ConcreteRho(-,Set())`, the known non-refutation `L3-THEOREMS.md` lists. **No generated system was
refuted**, which is the observable consequence of the check being sound. The report's account of
this (36 + 13, 2.2 % against L2's 2.4 %) is exact.

Sample shape, measured from the kept `jobs.tsv` (the property asserts only ≥ 10 %):

| | of 600 |
|---|---|
| a right-hand side with ≥ 2 abstract parts | 296 (49.3 %) |
| a concrete part | 424 (70.7 %) |
| an empty right-hand side `a <- ()` | 357 (59.5 %) |
| a self-partition `a <- (a, …)` | 174 (29.0 %) |
| constraints per system | 2–6, mean 4.0 |

The seed side is `17 × 6 = 102` jobs; the seeds are read from the JSON files, so `W2` here is
`seeds/W2.json` (label `l100`, constraints in file order) rather than `SatTermRepro`'s hard-coded
`W2` (label `k`) — the same system up to renaming, but not the same trace as L1's. Ids match
L1/L2's convention exactly (`v_i ↦ base + i`, `Supply` from `base + n`).

### 3d. What the comparison compares — six record types of thirteen

`Keep = {step, learn, in, inpart, sat, solve}`, identical to `looptrace-diff.py`'s `KEEP`. So:

* **compared, record for record, as raw strings including the site and location columns**:
  `step` (branch + partition + queue sizes), `learn` (new/seen + rule + partition), `in`
  (the input row constraints), `inpart` (the built queue), `sat` (the saturated set), `solve`
  (the summary line: rows, input partitions, nSat, derived, concrete, arities, per-rule counts).
  A missing or extra record of any of these shows up as `length±`.
* **used as INPUT to the replay, so wrong content shows up as a wrong replay rather than as a
  comparison**: `sin`, `slbl`, `svar`, `scon` (plus the model's own `#hashdiff`/`#eqdiff`
  cross-checks on `scon`, which the property treats as failures).
* **not compared at all**: `concr` (647 records), `splice` (41), `ex` (0 here) — post-loop
  `reduce` output and existential bindings, outside the model, exactly as in L2.

The verdict is compared implicitly and adequately: a died solve writes no `solve` record and the
model answers `#REJECTED`, so a solved/died disagreement is a `length±` on the `solve` record.
`compare` cannot silently compare nothing — the property asserts `nScala == jobs.length` (702) and
`nScala == nLean` and `agree == nScala`.

## 4. Part B — the thread column, the tools, the parallel replay

### 4a. The column reaches every record type — verified

On a 120,031-record serialized `gu05` trace, all thirteen record types carry it and **0 lines**
have a last field that is not `t<N>`:

```
concr 26  ex 448  in 772  inpart 762  learn 2943  sat 1110  scon 2027  sin 54235
slbl 10  solve 54235  splice 249  step 1444  svar 1770        (all with_tid = count)
```

identical to the report's census. On the child JVM's own 702-solve trace, likewise, single thread
`t0`, `sin` with ten fields.

### 4b. The three python tools — re-run with and without the column

Same trace, once as written and once with `sed 's/\t[^\t]*$//'`:

| tool | with column vs without |
|---|---|
| `tracker/tools/keptdef-mints.py` | **byte-identical** (1,050 bytes each) |
| `tracker/tools/splitkey-counts.py` | identical apart from the file NAME it echoes |
| `tracker/tools/rowtrace-summary.py` | identical apart from the file NAME it echoes |

and structurally: none of the three indexes a record from the end (`grep -n '\[-1\]'` empty; they
use fixed positions such as `rec[7]`). The Lean parsers in `Loop/Replay.lean` end every pattern in
`_` or `rest` (`startSegment`'s `blk :: bsz :: nr :: _`, `svar`'s `rest.headD ""`, `scon`'s
`rest.headD ""` after `kind`), so a trailing field is ignored — and the corpus replays below,
which read traces carrying the column, are the empirical proof.

### 4c. `--demux`, re-run

`Ai` group, shipped (parallel) loader, my own run of
`LOOPTRACE_GROUPS=Ai LOOPTRACE_SERIES=false tracker/tools/looptrace-corpus.sh`:

```
Ai  files=11  ermine=21s(rc=0,timeouts=0,dropped=0)  segments=83942  threads=13  demux=6156
    model=19839ms(rc=0)  agree=83942  skip=0
```

`incomplete/gu05`, shipped loader, by hand (trace → demux → replay → diff):

```
ermine rc=0 secs=20  segments=54235  records=137506
demux: segments=54235 threads=13 interleaved=5512 dropped-records=0
PERMUTATION: yes            (sort of input == sort of output, byte for byte)
raw     par.tsv    : 54235 segments, 2580 of them contain more than one `solve` record
demuxed par.dx.tsv : 54235 segments, 0
```

Both segment counts are L2's and the report's to the digit (83,942 and 54,235); the thread count
(13 vs 12) and the interleaving counts (6,156 / 5,512 vs 5,599 / 5,212; 2,580 vs the report's
2,354 and L2's 1,654) are thread timing, as the report says.

**The control — the demux is load-bearing.** The same raw parallel `Ai` trace replayed without the
regroup: `AGREE 83826, SKIP 116, exit 1`, every skip of the interleaving shape
(`skip: scon count 0 != nCs 1`). The report measured 132; the difference is again timing. With the
regroup: 0.

### 4d. Can `--demux` misgroup? — a positive argument, plus a check with demonstrated power

The regroup is "group by thread id, cut at that thread's own `sin`, emit each group whole".
Three things have to hold, and all three do:

1. **A record belongs to exactly one solve.** `RowTrace.log` synchronises `println` + `flush` on
   one lock, so a line is never split or interleaved with another line.
2. **A solve's records all carry one thread id.** `RowTrace.site` is a `ThreadLocal` set by
   `withSite` on the calling thread, and `solve` is an ordinary synchronous call, so every record
   of a solve is written by the thread that entered `withSite` — the same thread that wrote its
   `sin` from inside `solveInput`. There is no continuation or executor between them. A solve
   therefore *cannot* migrate; the case the report flags is impossible rather than merely absent.
3. **Segment order does not matter to either side.** `Loop/Replay.lean`'s `replay` is a pure
   function of ONE segment: the `Supply` comes from that segment's own `sin` (`lo hi blk bsz`,
   `Replay.lean:99`), nothing is threaded between segments. And both sides read the same regrouped
   file, so `--segments` and `parseSegments` number the segments identically.

And the detector, in case (2) were ever wrong: within a demuxed segment every record must carry the
segment's own `site`, and every record type that has a `loc` must carry the segment's `loc`. I ran
that check over four traces:

| trace | segments | records with a foreign `site` | with a foreign `loc` |
|---|---|---|---|
| `Ai`, parallel, DEMUXED | 83,942 | **0** | **0** |
| `Ai`, parallel, RAW | 83,942 | 2,170 | 3,786 |
| `gu05`, parallel, RAW | 54,235 | 2,254 | 3,446 |
| `gu05`, SERIALIZED | 54,235 | **0** | **0** |
| `gu05`, parallel, DEMUXED | 54,235 | **0** | **0** |

The check has power (thousands of hits on the raw traces) and fires nowhere after the regroup: the
demuxed parallel trace is site/loc-homogeneous exactly like a serialized one. The residual blind
spot is two solves that share BOTH site and loc AND swap threads mid-solve, which (2) rules out.

**The per-file TIMEOUT cut** (`looptrace-corpus.sh:78-81`, only for `LOOPTRACE_PERFILE` groups,
i.e. `incomplete/`) drops everything from the LAST `sin` in FILE order. Under the parallel loader
that is wrong — up to one segment per thread can be left truncated instead of one — but the
failure is LOUD, not silent: a truncated segment either loses its `scon` block and the model
answers `skip: scon count != nCs` (a `SKIP`, counted as bad, exit 1), or loses trailing `step`/
`solve` records and the model, which recomputes rather than copies, produces more records than the
compiler side (`length+`, counted as bad). It cannot produce a false agreement. It did not fire in
either run here (`timeouts=0 dropped=0`; gu05 finished in 20 s of a 120 s budget). The report
names this correctly as an open edge; I would add "and it fails loudly if it ever fires".

### 4e. The 458-partition solve is in the population and agrees

On my own parallel `gu05` trace the largest solve is

```
solve  mkSimplified-extinct  …/incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)
       rows=12 inParts=18 nSat=458 derived=400 concrete=true  arities=2;2;2;2;2;2;2;2;3;3;3;3
       Cancellation:31,CommonSubexpression:61,Resolution:7,ResolutionRow:9,SplitConcrete:53,
       SplitKeyed:3,SplitRow:1,Substitution:235          t12
```

— `nSat` 458 on thread `t12`, against **83** for the same location in the serialized trace (I
re-measured that too), which is the point: this solve exists only under the parallel loader. The
next largest solve in the same trace has `nSat` 31.

*(Section 5 records the outcome of my own replay of the whole demuxed parallel trace.)*

### 4f. Two regressions the report claims, re-run

* **The column's auto-detection is not one-way.** The same L2 model output compared against the
  `gu05` serialized trace WITH the column and against the same trace with the column stripped
  (`sed 's/\t[^\t]*$//'`, i.e. a pre-L4 trace) both give `segments 54235/54235, AGREE 54235,
  exit 0`.
* **`--demux` is a byte-identical copy on a serialized trace**, `cmp` silent — both with the
  column (`threads=1 interleaved=0 dropped=0`) and on the stripped file. Nothing about the L2
  path changes.
* **The L1 PLAIN-mode diffs on the six tracked seeds**, re-run from the stage's stored files:
  `W2 11, H2 61, NE6 48, W3 24, W4 13, G7 22` records, all AGREE, exit 0 — the report's numbers
  exactly. (One trap for a later reader: `l1/W2-0.tsv` is the trace of `SatTermRepro`'s
  HARD-CODED `W2` — label `k`, constraints in the other order — and does NOT match the model run
  on `seeds/W2.json`; the file that does is `l1/W2j-0.tsv`, and it agrees. The seed file and the
  built-in are the same system up to renaming, not the same trace.)

## 5. The `gu05` replays

### 5a. My own parallel replay of the whole file, shipped flags

```
model rc=0 secs=640          diff exit=0
segments: scala=54235 lean=54235 compared=54235
AGREE   54235      SKIP 0      hashdiff segments: 0      eqdiff segments: 0
threads: 13  t0=7 t1=22 t2=30 t3=10 t4=848 t5=25090 t6=7337 t7=1747 t8=1949 t9=7041
             t10=4154 t11=5964 t12=36
#summary  segments=54235 replayed=54235 skipped=0 hashdiff=0 eqdiff=0 nonpart=1013 rejected=0 fuel=0
```

All 54,235 segments of the demuxed parallel trace agree (the report: the same 54,235, 631 s
against my 640 s, `nonpart=1013` identical). And the 458-partition solve in particular, checked on
its own rather than inferred from the total — it is segment **54226** of the demuxed file:

```
segment 54226 (the 458-partition solve):  model records=18747  compiler records=18747  EQUAL=True
  last record: solve  mkSimplified-extinct  …/gu05_star_join_4dim_concrete_signature.e(62:1)
               12  18  458  400  true  2;2;2;2;2;2;2;2;3;3;3;3  Cancellation:31,…
```

18,747 records on each side, byte for byte, ending in the `solve` record that says 458. The
brief's headline question is answered, on a trace I took, demuxed, replayed and diffed myself.

### 5b. The 1,456-partition `splitKey=false` solve — still running, still undecided

The process the L4 stage left behind (`.../tmp/L4/gu05nk/big.model.{out,rc}`, PID 1230012,
`looptrace --replay big.tsv --flags=nosplitkey` under `timeout 21600`) is **still running as this
review closes**: 57 min elapsed, 57 min CPU, RSS 31 MB, **`big.model.out` still 0 bytes and no
`big.model.rc`** (the report wrote it down at 31 min of CPU; it has since spent another 26). It is replaying a single-segment file, so it emits nothing at all until that
segment finishes. The 458-partition version of the same solve costs the model roughly 570 s, so
this is already 6× that and counting; the run will be killed by its own `timeout 21600` at about
00:15, and the answer, if it comes, will be in `big.model.rc`. RSS is small, so this is CPU in the model's set operations, not thrashing — consistent
with `L2-CORPUS.md` §9 naming `SSet.champSort`'s per-element re-hashing as the model's cost
centre.

**Nothing may be concluded from it either way**, and the report says exactly that. The brief's
question ("does gu05's big solve now replay and agree?") is answered YES at the SHIPPED flags,
where the same solve saturates 458; the flag-off variant has no model-side result. I agree with
the report's handling: it is a model PERFORMANCE item, not a disagreement, and it belongs in a
later stage together with the `champSort` fix (which touches definitions `Bridge.lean` reasons
about, so it was rightly out of scope for a stage forbidden to edit Lean).

## 6. Acceptance criteria (`tracker/LOOP-MODEL-PLAN.md`, stage L4)

| criterion | verdict | evidence |
|---|---|---|
| "a ScalaCheck property: generated systems + the tracked seeds, run through `Subst.solve` with the trace on and through the Lean model, traces equal" | **PASS** | 17 seed files × 6 id bases + 600 generated satisfiable systems = 702 solves, 702 segments, **702 agree** byte for byte, `hashdiff=0 eqdiff=0 skipped=0`. Compiler side is `Subst.solve` in a child JVM (§3a); model side is `lake exe looptrace --replay` at the compiler's own ids |
| "the property runs in the ordinary `core/test`" | **PASS** | my `sbt -batch -J-Xmx3g core/test`: `Total 914, Failed 1, Passed 913`, the three properties among them, 282 s; the single failure is the pre-existing `Constraints.disjunction sound` starvation |
| "fails on an injected divergence (positive control)" | **PASS**, with F1 | `inject=idbase` → rc 1, 47 bad; `inject=nongen` → rc 1, 59 bad. The always-on control property additionally asserts both injections are detected, so an ordinary run cannot pass with a comparison that detects nothing. **But** the property does not fail when its own compiler side fails — F1 |
| "`tracker/lean/README.md` records that a solver change must keep it green" | **PASS** | `### L4` section, first paragraph, block-quoted as THE RULE, both directions (solver change → property; model change → L2 corpus replay), including what a SKIP means. F2 asks for one sentence on what the property does not reach |
| brief: skip cleanly without the Lean binary | **PASS** | `-Dermine.looptrace=/nonexistent` → `Passed 3`, 2 s, message naming `lake build looptrace` |
| brief: whole property under ~60 s | **PASS** | 2.6–2.9 s isolated, 8.0–8.7 s inside a loaded full `core/test` |
| brief: fix L2 review F8 (`--segments` exit status) | **PASS** | verified independently with injected `#hashdiff` and `#eqdiff` lines: exit 1 in both, while `AGREE` stays 702 |
| brief: thread id on every record, readers unaffected | **PASS** | all 13 record types, 0 lines without one; `keptdef-mints.py` byte-identical, `splitkey-counts.py` / `rowtrace-summary.py` identical but for the echoed filename; no tool indexes from the end; Lean parsers end in `_`/`rest` |
| brief: demultiplex and replay the parallel loader on `gu05` and `Ai` | **PASS** | my own runs: `Ai` 83,942/83,942 agree (13 threads, 6,156 interleaved); `gu05` 54,235 segments demuxed from a 137,506-record parallel trace, permutation-checked, and replayed (§5a) |
| brief: does gu05's big solve now replay and agree? | **PASS at the shipped flags** | `nSat` 458 at `gu05…e(62:1)` against 83 serialized, inside a run in which every segment agrees. The `splitKey=false` 1,456 variant is undecided (§5b), which the report states plainly |

**Can the plan's first "known scope limit" be dropped?** No — and the L4 edit does not quite drop
it: it strikes the paragraph through, labels it "**CLOSED by L4**", and then lists two things
still open inside it. I would keep the bullet and downgrade the label to PARTIALLY CLOSED, because
what is closed is the MECHANISM, not the population:

* the parallel sweep is 2 of the 8 corpus groups — and the `incomplete` half of it is one FILE
  (`gu05`), not the group;
* `looptrace-corpus.sh` still defaults to `LOOPTRACE_SERIES=true`, so the routine population
  remains the serialized loader;
* the per-file TIMEOUT cut is not thread-aware (loud if it fires, §4d);
* `looptrace --replay` still cannot demultiplex, so the regroup is an external step that a future
  runner has to remember (the report's open item 3).

The wording change is a nit; the substance — "the parallel loader can now be compared, and where
it has been compared it agrees completely" — is correct and is a real advance.

## 7. Findings

### F1 — CONFIRMED, required fix. A failure of the property's compiler side is reported as a PASS

`TestLoopTrace.scala:443-512` (`lazy val setup`) returns `Left(String)` for **six** different
situations, and `TestLoopTrace.scala:517-520` (`skipping`), reached at lines 533 and 552, turns every one of them into
`Prop.proved` with a printed line. Only the first is a skip; the other five are failures:

| `Left` | line | what it really is |
|---|---|---|
| the Lean binary is absent | 445 | a legitimate SKIP |
| no seeds and no generated systems | 449 | the population vanished |
| **the child JVM did not finish in 180 s** | 478 | **a solver that diverges — the failure this whole programme exists to study** |
| the child JVM exited non-zero | 479 | the solver threw, or the child could not start |
| the child wrote no trace | 480 | the instrumentation broke |
| `catch { case e: Throwable => Left("setup failed: " + e) }` | 512 | anything else, including a classpath discovery failure |

Reproduced. With `-Dsatterm.seeds` pointed at a scratch copy of the seed directory containing one
file whose name has a tab in it (so the wire line's `base` field is unparseable and
`LoopTraceChild.main:100` throws outside its per-job `try`):

```
$ sbt -batch -Dsatterm.seeds=<scratch>/seeds "core/testOnly …TestLoopTrace"      # exit 0
[loop model trace] SKIPPED: the tracing child JVM exited 1:
Exception in thread "main" java.lang.NumberFormatException: For input string: "NAME@0"
        at …LoopTraceChild$.main$$anonfun$1(LoopTraceChild.scala:100)
[info] + loop model trace.the Lean loop model reproduces the compiler's trace, segment for segment: OK, proved property.
[info] + loop model trace.positive control: an injected divergence IS detected: OK, proved property.
[info] Passed: Total 3, Failed 0, Errors 0, Passed 3
```

`core/test` is green and 0 of the 702 solves were compared. The tab is contrived; the branch is
not — the same `Left` is taken when the child cannot start, when the solver throws during class
initialisation, and (line 478) when a solve does not terminate in 180 s. A regression test whose
whole purpose is to notice that the solver's loop changed must not answer "proved" when the
solver's loop hangs.

Fix (small, local): give `setup`'s left side a reason — e.g.
`Left((skip: Boolean, why: String))` — and in both properties

```scala
  case Left((true, why))  => skipping(why)                       // the binary is absent
  case Left((false, why)) => (Prop.falsified :| ("the trace property could not run: " + why))
```

with `leanBin.canExecute` the only `true` (lines 533 and 552). Nothing else changes; the skip path stays exactly as it
is and `-Dermine.looptrace=/nonexistent` must still print `Passed 3`.

### F2 — CONFIRMED, documentation. The README's rule overstates the property's reach

`tracker/lean/README.md`'s L4 rule says the property "fails the moment `Subst.solve` emits a record
the Lean model does not". Measured on the trace the 702 solves actually write, six of the fifteen
`Constraints.Inference` kinds never fire: **`ResolutionRow`, `SplitEmpty`, `ResolutionEmpty`,
`CommonSubexpressionMint`, `PartitionEmpty`, `CommonPartition`** (`ResolutionRow` fires 9 times in
one gu05 solve alone, so the corpus does reach it). Nor does the property reach: solves with
existential variables (`ex` records: 0), `Skolem`/`Ambiguous` input variables, inputs that have
been through `.nf`, or any non-default flag (`-Dermine.*` is not forwarded to the child, §3b).

Consequence: a solver or model change confined to `resRow`, `emptyRow`, `disjunction`, or the
empty-group split branches passes `core/test` and is caught only by the L2 corpus sweep, which is
NOT part of `core/test`. That is a reasonable division of labour, but the rule should say it.
Recommend one sentence in the README rule and in `TestLoopTrace`'s header naming the rules the
702 solves reach and pointing at `looptrace-corpus.sh` for the rest. (Optional, cheap, not
required: add one seed that fires `ResolutionRow`.)

### F3 — minor, documentation. "CLOSED" should read "PARTIALLY CLOSED"

See §6's last block. The plan's bullet already lists what is still open, so this is wording, not
substance. Do not delete the bullet.

### F4 — minor, PLAUSIBLE, already in the report. The per-file TIMEOUT cut

`looptrace-corpus.sh:78-81` cuts at the last `sin` in FILE order, which under the parallel loader
leaves up to one truncated segment per thread instead of one. The report names it (open item 2). I
add the part that decides how urgent it is: **it cannot cause a false agreement.** A truncated
segment either loses its `scon` block (`skip: scon count != nCs` → SKIP → bad → exit 1) or loses
trailing records the model recomputes (`length+` → bad). It did not fire in any run here
(`timeouts=0 dropped=0`). Fix when convenient: cut per thread at that thread's last `sin`.

A related case I checked and found safe: in a `LOOPTRACE_PERFILE` group the per-file traces are
CONCATENATED, and thread ids restart at `t0` in each JVM. That does not merge segments across
files, because a thread's first record in the next file is its own `sin`, which flushes whatever
that id had open. Records that precede a thread's first `sin` are dropped and counted
(`dropped-records=`), and none of them is a compared record type.

### F5 — nits

* the report's file table says `TestLoopTrace.scala` 575 lines and `looptrace-diff.py` 507; they
  are 576 and 508.
* `compare` (and `looptrace-diff.py`) treat a `#skip` segment as bad but a `#FUEL` one only as a
  note. In practice a fuel-exhausted segment is caught anyway, as a `length-` on the records, and
  `#summary … fuel=0` is printed; asserting `fuel=0` and `skipped=0` from the summary line would
  be a belt-and-braces improvement.
* the property tests the LOOP, not the construction of its input: both sides are driven by the
  compiler's own `sin`/`scon` records, so a change *before* `RowTrace.solveInput` moves both sides
  together. That is L2 review F3's scope limit, inherited; worth a line in the test header.

### What I did NOT re-run

The other six corpus groups under either loader (L2's territory), the whole `incomplete` group,
the `emptyRow`/`disjunction` abstractions, and any Lean build or audit — this stage edits no Lean
and the L5 agent is mid-flight in that directory. `core/test` was run once, in full, plus four
`testOnly` invocations; never concurrently, and never while a `bin/ermine` sweep was running.


---

## 8. Final check after the fixes — 2026-09-04, second round

The implementer applied F1 and F2-F5 and went further: the `-Dermine.*` rule switches are now
forwarded to the child JVM and mapped to the model's `--flags`. Five checks, `ps` clear of
`java`/`bin/ermine` before each `sbt`, one `sbt` at a time.

| check | command | result |
|---|---|---|
| **F1 reproduction — must FAIL now** | `sbt -batch -Dsatterm.seeds=<scratch seeds with the tab-named file> core/testOnly …TestLoopTrace` | **rc 1**, `[loop model trace] FAILED, no comparison was made: the tracing child JVM exited 1:`, `Failed: Total 3, Failed 2, Errors 0, Passed 1`. The same input that returned `Passed 3` before now falsifies both trace properties. **F1 CLOSED.** |
| skip path — must still SKIP | `sbt -batch -Dermine.looptrace=/nonexistent/looptrace …` | **rc 0**, `SKIPPED: the Lean model executable is absent …`, `Passed: Total 3, Failed 0, Passed 3` |
| normal run | `sbt -batch core/testOnly …TestLoopTrace` | **rc 0**, `702 solves; 702 segments; 702 agree; 3025 ms; skipped=0 hashdiff=0 eqdiff=0 fuel=0`, controls `47 of 702 (576 records mint)` and `--flags=nongen 59 of 702`, `Passed 3` |
| a forwarded flag | `sbt -batch -Dermine.emptyRow=true -Dermine.looptrace.keep=true …` | **rc 0**, `rule flags forwarded to both sides: -Dermine.emptyRow=true  ->  --flags=emptyrow`, `702 segments; 702 agree`, controls `39 of 702 (512 records mint)` and `59 of 702`, `Passed 3` |
| does the flag actually bite? | rule census on that run's kept trace | **`SplitEmpty` 12 and `ResolutionEmpty` 4 now fire** (`learn G7@0 new SplitEmpty: ^free2 <- (,)`), and the rest of the census shifts with them (`SplitConcrete` 121 → 109, `CommonSubexpression` 118 → 112, `Resolution` 21 → 15). Two of the six rules F2 listed as out of reach are now inside the property, and the model matches the compiler on all 702 segments with `emptyRow` on — so the M4 abstraction does not bite in the per-solve setting |

**The reworked positive control, read.** It still asserts something real under every setting the
test accepts, for three reasons:

1. **The rule-set injection is asserted UNCONDITIONALLY** (`s.controlFlags.bad.nonEmpty`,
   `TestLoopTrace.scala:728-730`), with `controlToken` = `nongen`, or `all` when the run is
   already `nongen` so that the injection is never a no-op. If that injection ever failed to be
   detected the property fails loudly; it cannot become vacuous.
2. **The id-base injection is guarded, not weakened.** `nMints` counts records mentioning
   `^ambiguous(free)` in the compiler's own trace, and the assertion is
   `nMints == 0 || control.bad.nonEmpty`. That is the honest form: shifting the `Supply` can only
   move an id that was MINTED, so under `-Dermine.genRules=nongen` the injection has no power and
   asserting it would assert something false. The count is printed on every run (576 shipped, 512
   under `emptyRow`), so a configuration in which it silently switched itself off would be visible
   — and even then item 1 still stands.
3. **An unknown flag cannot degrade the run silently.** `modelFlags` is `Left` for any
   `-Dermine.*` value with no model token, and that `Left` is `fail(...)`, i.e. falsified, not
   skipped. I checked the coverage: `grep getProperty("ermine.` over `core/src/main` yields
   exactly `genRules, disjunction, labelCheck, labelCheckEarly, resGuard, splitKey, splitRow,
   resRow, emptyRow` plus `rowTrace` and `useInterface`, which are not rule switches — so every
   solver rule switch the compiler reads is either forwarded or rejected. Nothing can be set on
   one side only.

F2 (README rule + `L4-TEST.md`), F3 (the plan's bullet now reads **PARTIALLY CLOSED** and lists
all four residuals), F4 (the loud-failure note) and F5 (`#FUEL` counted as a failure in `compare`,
plus the new `skipped=0 fuel=0` assertion on the model's own `#summary`) are all in. One nit
survives, deliberately: `looptrace-diff.py`'s `segments_main` still classes `#FUEL` as a note
rather than a class of its own — harmless, since such a segment is caught as a `length-`
mismatch, and the Scala side and the `#summary` assertion both flag it.

### Verdict: **ADVANCE**

Nothing on my list remains. The property now fails when the model and the compiler disagree, fails
when its own compiler side cannot run, skips only when the Lean binary is absent, tests the
configuration it was asked to test, and carries a control that is never vacuous. `core/test`:
**914 total, 913 passed**, the single failure the pre-existing `Constraints.disjunction sound`
starvation.

Two things to carry forward, neither an L4 item: the parallel-loader POPULATION is still 2 of 8
corpus groups (the plan's bullet now says so), and the model's replay of the 1,456-partition
`splitKey=false` `gu05` solve remains undecided on performance grounds (§5b) — at the last check
it had spent 57 minutes of CPU without emitting its segment, and it is a `champSort` cost, not a
disagreement.
