# Stage 2 — `-Dermine.splitKey`: the KEYED split guard in `Constraints.scala`, measured

Date 2026-09-03, branch `scala3-migration`. Written with the flag OFF by default; **the default was flipped to ON later the same day** (decision recorded in §C.2/§C.5, post-flip re-run in `tracker/TICKET-sat-termination.md` §3d).
Stage 1 (the Lean) is `tracker/satterm/KEYED-SPLIT.md` / `tracker/lean/Rowpartition/KeyedSplit.lean`.

Toolchain for every command below:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
cd /home/dmitry/research/ermine/ermine-scala
```

Scratch (raw outputs):
`/tmp/claude-1000/-home-dmitry-research-ermine/880c725d-c5b2-4825-899b-634a7c1fc265/scratchpad/stage2/`

Machine note: the user's LSP server (`com.clarifi.reporting.ermine.lsp.Main`, pid 74446,
started 09:47, ~0.9 GB, idle) was running for the whole session.  It was NOT killed (it is
the editor); it is idle and its CPU time did not move during the timed runs, which is
recorded per-run in §B4.

---

## Part A — the implementation

### A.1 The change (`core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, LF, unchanged)

Four edits, +118/−9 lines, all comment-heavy:

1. **`case object SplitKeyed extends Inference`** (line ~697) — provenance for the keyed
   reuse branch, so `-Dermine.rowTrace` can count it.  `Inference` is never inspected and
   `Partition.equals`/`hashCode` ignore it, so the tag is behaviour-neutral.
2. **`GenRules.splitKey`** (line ~816):
   `val splitKey: Boolean = System.getProperty("ermine.splitKey", "false") == "true"`,
   read once at class-init like every other flag, documented with the Lean that licenses it
   (`terminatesOnSatKeyed`, `keyed_vs_syntactic`, `ksplit_reuse_sat` /
   `KSplitStep.reuse_models_iff`, `ksplit_mint_conservativeExt`) and with the explicit scope
   limit (nothing about ill-typed input).  `toString` gains `+splitkey`.
3. **`splitConcrete`** gains `resolvent: Fields => Option[TypeVar] = _ => none` and a third
   branch inside the existing mint branch.  Order of the match is unchanged, so behaviour is
   unchanged when the group lookup hits and when `!GenRules.splitMints`:

   ```scala
   case None    =>
     (if (GenRules.splitKey) resolvent(concr) else none) match {
       case Some(w) => Set(Partition(w, RHSAbstr(abstr), SplitKeyed))   // kSplitReuseResult
       case None    => val u = fresh(...); Set(Partition(u, RHSAbstr(abstr), SplitConcrete),
                                              Partition(v, RHS(Set(u), concr), SplitConcrete))
     }
   ```

   `fresh` is called only in the mint branch, so the keyed reuse draws no id from the
   `Supply` (it does shift the id sequence relative to flag-off, exactly as the `cut`
   adoption did — see B2/B3).
4. **`learnPartitions`** passes `findResolvent(Set())` as that argument, and the `resolvents`
   comment now says it serves both flags.

### A.2 Correspondence with `KSplitStep` — exact, with the one nil difference

Documented at `splitConcrete` in the source.  Writing `c` for the premise
`v <- (abstr, concr)`:

| Scala branch | Lean |
|---|---|
| `rhss(RHSAbstr(abstr)) = Some(u)` → `v <- (u, concr)` | `Cut.SplitReuseApp` / `splitReuseResult`, which is a `NonGenStep` of `KDefaultStep` — **kept verbatim**, `splitKey` must not touch it (the brief's instruction, and the calculus's) |
| `splitKey` ∧ `resolvent(concr) = Some(w)` → `w <- (abstr)` | `KSplitReuseApp G c w` (`mk c.lhs {w} c.conc ∈ G`); emits `mk w (vset c) ∅` = `kSplitReuseResult` |
| otherwise → mint | `KSplitApp` (`¬ Resolved G c.lhs c.conc` = `resolvent(concr) = None`); emits `Cut.splitResult` |

`Resolved G v K` is `∃ z, mk v {z} K ∈ G` (`ResGuard.lean:79`).  `findResolvent(Set())(k)`
returns `Some(w)` iff some partition `v <- (w, k)` with a LONE abstract variable is in
`proc ++ incm`.  That is `Resolved` restricted to the `v` at hand, which is all the rule
asks about.

**The one difference, and it is nil in effect.**  `findResolvent` ranges over `proc ++ incm`
= `G` minus the premise `c` itself: `incorporateAll` returns the dequeued partition to
`proc` only after `learnPartitions` returns.  `c` cannot witness its own key — a witness has
a SINGLE abstract variable and `splitConcrete` reaches the guard only with `2 ≤ |abstr|` —
so `¬Resolved (G \ {c}) v concr ≡ ¬Resolved G v concr`.  The current batch `s` is likewise
not a difference: `splitConcrete` is the INITIAL value of `learnPartitions`' fold, so no
batch partition exists yet, and `findResolvent(Set())` is literally `findResolvent(s)` at
`s = ∅`.  **The Scala implements `KSplitStep` exactly; nothing was approximated.**

### A.3 Compile and unit tests

```
$ sbt -batch core/compile                       # ONCE; every A/B below uses these classes
[success] Total time: 11 s, completed Sep 3, 2026, 10:02:08 AM
$ sbt -batch -J-Xmx3g core/Test/compile
[success] Total time: 7 s
```

Flag actually read (`Test / fork := false` in `build.sbt:94`, so the test JVM is the sbt
JVM and `_JAVA_OPTIONS` is the way in):

```
$ CP=$(cat target/ermine-classpath)
$ echo 'System.out.println(com.clarifi.reporting.ermine.Constraints.GenRules$.MODULE$.toString());' \
    | jshell -q --class-path "$CP" -R-Dermine.splitKey=true -
cut+label-early+resguard+splitkey
$ ... same without -R                       ->  cut+label-early+resguard
$ _JAVA_OPTIONS="-Dermine.splitKey=true" sbt -batch 'eval "splitKey=" + System.getProperty("ermine.splitKey")'
Picked up _JAVA_OPTIONS: -Dermine.splitKey=true
[info] ans: String = splitKey=true
```

`core/test`, same classes, one run each:

```
$ sbt -batch -J-Xmx3g core/test
[info] Failed: Total 904, Failed 1, Errors 0, Passed 903        (258 s)
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.

$ _JAVA_OPTIONS="-Dermine.splitKey=true" sbt -batch -J-Xmx3g core/test
[info] Failed: Total 904, Failed 1, Errors 0, Passed 903        (269 s)
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
```

**903/904 on both sides, the same single failure — the known `Constraints.disjunction sound`
generator starvation (0 passed, 501 discarded), unrelated to this flag.**  In particular
`Constraints.split concrete sound` passes under the flag; note that that property calls
`splitConcrete` with the 4-argument signature, so it exercises the DEFAULT `resolvent =
_ => none`, i.e. the mint path — the keyed branch's own soundness evidence is
`ksplit_reuse_sat` plus B0/B6 below, not this property.

### A.4 Instruments added for this stage (untracked, `tracker/tools/`, inert)

* **`tracker/tools/splitkey-counts.py`** — counts `splitConcrete`'s three branches in a
  `-Dermine.rowTrace` log, segmenting by `solve` record the way `keptdef-mints.py` does
  (`--filter core/examples` attributes to the module, `-Dermine.loadInSeries=true`
  required).  The arithmetic: a MINT emits two `SplitConcrete` learn records, one with an
  EMPTY concrete part (`u <- (abs,)`) and one with a nonempty one (`v <- (u, con)`); a
  syntactic REUSE emits only the second; a keyed reuse emits one `SplitKeyed` record.  So
  `mints = #(SplitConcrete, empty con)`, `syntactic reuses = #(SplitConcrete, nonempty con)
  − mints`, `keyed reuses = #SplitKeyed`.
  Positive control (both non-zero classes reachable): on `tracker/repro/satterm`'s W2 base 0
  it reports `mint=1 keyed=0` with the flag off and `mint=0 keyed=1` with it on.
* **`tracker/tools/splitkey-sweep.sh`** — `keptdef-sweep.sh`'s shape: one serialized
  `-Dermine.rowTrace` `bin/ermine` run per `core/examples/**/*.e` (110), analysed by the
  above.  Uses `-Dermine.useInterface=false`, so it neither reads nor WRITES `.ei` and can
  run beside an `ei-diff.sh` sweep without clobbering it.  `SPLITKEY=true` switches sides.
* **`tracker/tools/ei-classify.py`** — classifies a pair of flattened `.ei` snapshots (as
  `ei-diff.sh` writes them) per binding into `identical` / `order-only` / `alpha-equivalent`
  / `concrete->polymorphic` (WEAKER, the blocker) / `polymorphic->concrete` (STRONGER) /
  `other`, by sorting binder lists, constraint lists and partition right-hand sides and then
  searching for a bijection of the bound type variables (bodies unified token-wise first,
  constraint multisets matched with backtracking).  This is the classification
  `TICKET-substitution-gap.md` §4 used; its script lived in session scratch and is gone.
  Positive control on a hand-built pair exercising all six verdicts:

  ```
  == bindings by verdict: {'identical': 1, 'order-only': 2, 'alpha-equivalent': 1,
                           'polymorphic->concrete': 1, 'concrete->polymorphic': 1, 'other': 1}
  ```

  so a later "0 weaker" is a measurement, not a silent instrument.

---

## Part B — the gates

Every gate below uses the SAME class files (`sbt -batch core/compile` at 10:02:08; no
recompile between sides), flag off vs `-Dermine.splitKey=true`.

### B0. Seed replays — the positive controls

```
$ tracker/repro/satterm/sweep.sh <seed> 0 99                                   # off
$ ERMINE_JAVA_OPTS="-Dermine.splitKey=true" tracker/repro/satterm/sweep.sh <seed> 0 99   # on
$ tracker/repro/crule/sweep.sh <sys> 0 99                                      # off / on likewise
$ [_JAVA_OPTIONS=-Dermine.splitKey=true] KEEPMINT_TRACE=... tracker/repro/keepmint/run.sh
```

(`crule/run.sh` and `satterm/run.sh` both read `ERMINE_JAVA_OPTS`; `keepmint/run.sh` does
NOT, so the flag went in through `_JAVA_OPTIONS`, confirmed by the JVM's own
`Picked up _JAVA_OPTIONS: -Dermine.splitKey=true` in the log.  Each side's header line
`genRules=…` is `GenRules.toString`, so every run states which side it is.)

| seed | side | verdicts, 100 bases | ids drawn from the `Supply` per base |
|---|---|---|---|
| W2 | off | SOLVED 100 / REJ 0 / HANG 0 / OOM 0 | 1 ×67, 2 ×33 |
| **W2** | **on** | **SOLVED 100** / 0 / 0 / 0 | **0 ×100** |
| H2 | off | SOLVED 100 / 0 / 0 / 0 | 3 ×100 |
| **H2** | **on** | **SOLVED 100** / 0 / 0 / 0 | **2 ×38, 3 ×62** |
| NE6 | off | SOLVED 100 / 0 / 0 / 0 | median 4, max 19 (2×13, 3×23, 4×15, 5×21, 6×9, 7×5, 8×3, 9×1, 11×1, 13×4, 14×1, 15×2, 16×1, 19×1) |
| **NE6** | **on** | **SOLVED 100** / 0 / 0 / 0 | median 3, max 18 (1×22, 2×19, 3×14, 4×20, 5×11, 6×2, 7×4, 10×1, 11×1, 12×3, 14×1, 15×1, 18×1) |
| CRule `W` (unsat) | off | SOLVED 0 / **REJECTED 100** / 0 / 0 | — |
| CRule `W` (unsat) | on | SOLVED 0 / **REJECTED 100** / 0 / 0 | — |
| `gseed` (unsat) | off | SOLVED 0 / **REJECTED 100** / 0 / 0 | — |
| `gseed` (unsat) | on | SOLVED 0 / **REJECTED 100** / 0 / 0 | — |

The two unsatisfiable systems are **byte-identical off vs on apart from the header line**
(`diff` after stripping the `in N ms` field: 2 differing lines, both the `genRules=` banner)
— same messages, same distribution (`W`: `Fields appear twice in row: Set(Repro.l1/l2/…)`
from `RHS.merge`; `gseed`: `Row partitions are unsatisfiable at field 'Repro.l1'` from the
label check).  Nothing about ill-typed input moved, as the theorem's scope says.

**The keyed branch firing, traced (base 0 of `W2`, `run.sh trace W2 0`):**

```
splitKey=OFF   genRules=cut+label-early+resguard
  records=20 steps=7 (common=1 empty=1 learn=4 unify=1) learn=7 (new=5 seen=2)
  byRule: Cancellation=3 CommonSubexpression=1 SplitConcrete=2 Substitution=1
  IDS distinct=4 input=3 fresh(minted)=1 (id 3)  supply-drawn=2
    step  learn  ^free0 <- (^free1 ^free2,k)
    learn new   SplitConcrete: ^ambiguous(free)3 <- (^free1 ^free2,)     <- MINT
    learn new   SplitConcrete: ^free0 <- (^ambiguous(free)3,k)
    …  sat: SplitConcrete p^0 <- (^3, k)

splitKey=ON    genRules=cut+label-early+resguard+splitkey
  records=12 steps=4 (empty=1 learn=3) learn=2 (new=2 seen=0)
  byRule: SelfSubstitution=1 SplitKeyed=1
  IDS distinct=3 input=3 fresh(minted)=0  supply-drawn=0
    step  learn  ^free0 <- (^free1 ^free2,k)
    learn new   SplitKeyed: ^free2 <- (^free1 ^free2,)                   <- KEYED REUSE
    step  learn  SplitKeyed: ^free2 <- (^free1 ^free2,)
    learn new   SelfSubstitution: ^free1 <- (,)
    step  empty  SelfSubstitution: ^free1 <- (,)
    step  learn  ^free0 <- (^free2,k)
    …  sat: INPUT p^0 <- (e2^2, k)
```

This is `KeyedSplit.lean` §6 executed: `W2` itself carries `p <- (e2, (|k|))`, so the key is
closed from the start (`W2_resolved`), the mint is refused (`W2_not_keyed_mint0`), the reuse
emits the self-partition `e2 <- (e1, e2)` (`W2_keyed_reuse0`) and self-substitution derives
`e1 <- ()` (`W2_keyed_reuse0_selfSubst`).  The solved result differs only in the NAME:
off `e2 := 3` with residual `Part(p^0, [(|k|), 3])`; on `e2 := unbound` with residual
`Part(p^0, [(|k|), e2^2])` — the same row, named by the input variable instead of a mint.

**KeepMint instance** (`tracker/repro/keepmint/run.sh`, 8 id bases × 4 input orders):
**identical on both sides** — 33 solve segments, 64 `makeConcrete` steps, 16 kept-definition
dequeues, 16 with a concrete part, **16 MINTED / 0 REUSED / 0 neither**, all 32 `base …
order …: solved: u=…` lines byte-identical, `SplitKeyed` learn records **0 on both sides**.
Correct and expected: that system is `u <- (x, y, (|k|)); u <- (|k, c|); R <- (u, z)` and
carries no `u <- (z, (|k|))`, so the key is OPEN and the keyed rule mints exactly as the
shipped one does.  It is the control showing the flag does not simply suppress every split
mint.

### B1. Stdlib boot

```
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.useInterface=false [-Dermine.splitKey=true]" bin/ermine </dev/null
```

| run | off, wall / program's own `Loaded 129 modules (s)` | on, wall / `Loaded 129 modules (s)` |
|---|---|---|
| 1 | 13.42 s / 12.34 s | 12.51 s / 11.66 s |
| 2 | 12.27 s / 11.43 s | 12.45 s / 11.59 s |
| 3 | 13.03 s / 12.15 s | 12.47 s / 11.54 s |

**129 modules loaded on both sides, all six runs.**  Boot time is the same within noise
(off 11.43–12.34, on 11.54–11.66; the off side's spread is larger than the gap).

Traced (`-Dermine.rowTrace`, `-Dermine.loadInSeries=true`, one run per side):

| | off | on |
|---|---|---|
| trace records | 60,088 | 60,088 |
| `learn` records | 1,631 | 1,631 |
| `SplitConcrete` learn records | **0** | **0** |
| `SplitKeyed` learn records | — | **0** |
| `CommonSubexpression` | 785 | 785 |
| `Resolution` | 0 | 0 |

**The two trace files are byte-identical (`cmp` says so).**  The stdlib boot cannot see this
flag: `splitConcrete` never fires in it at all — the same population fact
`TICKET-substitution-gap.md` §7.9 and `keptdef-sweep.sh` record (0 `makeConcrete` steps in
the boot, and `resolution` fires zero times too, which is why `resGuard` needed
`gen-res-star.py` to be measured).  The full boot stdout differs on exactly one line off vs
on, the loader progress bar, which carries per-run wall-clocks — the normalisation trap
`ROW-CONSTRAINT-STATE.md` documents.

### B2. Corpus verdicts

```
$ ERMINE_JAVA_OPTS="-Xmx2g"                            tracker/tools/corpus-run.sh              <outA>
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.splitKey=true"     tracker/tools/corpus-run.sh              <outB>
$ ERMINE_JAVA_OPTS="-Xmx2g"                            tracker/tools/corpus-run.sh --incomplete <incA>
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.splitKey=true"     tracker/tools/corpus-run.sh --incomplete <incB>
$ tracker/tools/corpus-verdicts.py <outA> <outB>        # and <incA> <incB>
```

(`corpus-run.sh` deletes `core/examples/**/*.ei` before each run and passes
`-Dermine.useInterface=false`, which is what makes the second side re-run the solver.)

| corpus | side | LOADED | REJECTED | UNKNOWN | total |
|---|---|---|---|---|---|
| examples + `Ai/` + `shouldfail/` | off | **23** | **43** | 0 | 66 |
| examples + `Ai/` + `shouldfail/` | on | **23** | **43** | 0 | 66 |
| `incomplete/` | off | **18** | **16** | 0 | 34 |
| `incomplete/` | on | **18** | **16** | 0 | 34 |

* `shouldfail/`: **40 of 40 REJECTED on both sides**, 0 modules loading.
* **`incomplete/`: `0 of 34 files differ`** — verdicts and messages identical.
* Main corpus, first pass: `1 of 66 files differ`, and it was a MESSAGE, not a verdict —
  `shouldfail/der01_rename_onto_existing_column.e`, same file, same location `41:7`, same
  refuted field `Shouldfail.Der01.b`, different clause of `Constraints.checkLabel`:
  off `a part contains it but the whole does not` vs on `two parts of one partition both
  contain it`.

  **Investigated (B7), and it is NOT the flag.**  (i) With `-Dermine.loadInSeries=true` both
  sides give the SAME message (`two parts …`).  (ii) `splitConcrete` does not fire at all in
  that module: a traced run reports `mint=0 synreuse=0 keyed=0` over its 14 solves on both
  sides.  (iii) 56 repeat runs with the flag OFF under the corpus conditions — 6 sequential,
  12 sequential at `-Xmx2g`, 18 as six concurrent JVMs, and one per
  `-XX:ActiveProcessorCount ∈ {1,2,3,4,6,8,12}` — every one printed `two parts …`.  (iv) The
  whole side A was therefore RE-RUN (66 files, identical invocation):

  ```
  $ tracker/tools/corpus-verdicts.py <outA-rerun> <outB>     ->  0 of 66 files differ
  $ tracker/tools/corpus-verdicts.py <outA>       <outA-rerun>
      MESSAGE shouldfail_der01_rename_onto_existing_column.e.out  (the same pair)
                                                              ->  1 of 66 files differ
  ```

  So the two OFF runs of the same build differ from each other on exactly this file, and the
  re-run agrees with the flag-ON side everywhere.  This is the parallel-module-load
  non-determinism the tracker already documents (`g1-diff.sh`: "thread timing otherwise
  reaches `.ei` bytes through the solver's id-hash queue"); `checkLabel` keeps the FIRST
  clash it propagates to, and which clause that is depends on the order of the input
  partition list, which is keyed on variable ids.  Both clauses are correct refutations of
  the same field.

* **Whole-output text diff** (boot progress bar and `(N.NN seconds)` timings normalised, the
  normalisation `ROW-CONSTRAINT-STATE.md` requires): **0 of 66** on the main corpus
  (A-rerun vs B) and **0 of 34** on `incomplete/`.

**Gate verdict: 0 verdict differences, 0 message differences, `shouldfail/` 40/40 on both
sides — as expected.**

### B3. Published types (`.ei`)

```
$ tracker/tools/ei-diff.sh <out> "-Dermine.splitKey=true"      # 2 x 110 example modules,
                                                              # interfaces ENABLED (else nothing is written)
$ tracker/tools/ei-classify.py <out>/A <out>/B
```

`ei-diff.sh` covers all 110 `core/examples/**/*.e` and snapshots BOTH trees — the example
interfaces and the 129-module stdlib under `core/target/scala-3.3.8/classes/modules` —
**188 interfaces, 1932 bindings**, none missing on either side (`only-in-A -  only-in-B -`).

**The gate needed two controls,** because `ROW-CONSTRAINT-STATE.md` and `g1-diff.sh` both
record that stdlib interfaces churn between two runs of ONE build ("thread timing otherwise
reaches `.ei` bytes through the solver's id-hash queue — measured on `lookbackJoin`").  So
four full sweeps were run — A and A′ with the default flags, B and B′ with
`-Dermine.splitKey=true` — and all six pairs classified:

| comparison | interfaces differing | bindings: identical / order-only / alpha-eq / **weaker** / other |
|---|---|---|
| **A vs A′** (same flags, control) | **4** of 188 | 1911 / 21 / 0 / **0** / 1 (`Relation.lookbackJoin`) |
| **B vs B′** (same flag, control) | **1** of 188 | 1927 / 4 / 2 / **0** / 0 (`Relation/Predicate`) |
| A vs B | 5 of 188 | 1921 / 8 / 3 / **0** / 1 |
| A′ vs B | 5 of 188 | 1907 / 21 / 3 / **0** / 2 |
| A′ vs B′ | 4 of 188 | 1913 / 17 / 1 / **0** / 2 |

**No signature became weaker anywhere — `concrete->polymorphic` is 0 in every comparison.**

Subtracting the control churn (an interface that differs between two runs of the SAME
configuration is not evidence about the flag), the interfaces attributable to the flag are
the ones that differ in BOTH off/on comparisons and in NEITHER same-configuration one:

| interface / binding | verdict |
|---|---|
| `incomplete/RunCalibration.scaledRuns` | **alpha-equivalent** — 7 constraints on both sides, matched by a bijection of the seven existentials (`a,rs,b,o,c,d,so` ↦ `c,rs,d,o,a,b,so`).  Found only after the matcher stopped sorting right-hand sides by their ORIGINAL names — a sort that is not preserved by the bijection; see the note in `ei-classify.py`. |
| `incomplete/np01_add_or_recompute.inferredRestate` | **7 -> 8 constraints, one extra existential.  Not weaker; equivalent.**  Hand-classified below. |

Everything else — `Layout/Chart` (`seriesW`, `seriesWE`), `Layout/Report` (`bubble`,
`structuredBar`), `Relation/Op` (17 bindings), `Relation/Predicate` (6), `Relation`
(`lookbackJoin`) — is stdlib, is order-only or alpha-equivalent, and **appears in a
same-configuration control**: `Relation/Predicate` differs between the two flag-ON runs, and
`Layout/*`, `Relation/Op`, `lookbackJoin` between the two flag-OFF runs.  That is the churn
the tracker documents, not this flag; consistently with B1, `splitConcrete` never fires in a
stdlib boot at all.

**`np01.inferredRestate`, by hand.**  Write `K3 = (|unitCost, unitPrice, qty|)`,
`K4 = K3 ⊎ (|revenue|)`.

```
A (off): t1 <- (K4, rs, a)        t <- (K4, rs, so1, a)     (|margin|)  <- (rs, so1)
         (|revenue|) <- (rs1, so) r  <- (K3, rs1, a, rs)    t1 <- (K3, rs1, so, a, rs)
         RelationalComb rel                                        [7 constraints]
B (on):  t1 <- (K4, rs, a)        t <- (K4, rs, so, a)      (|margin|)  <- (rs, so)
         (|revenue|) <- (rs1, so1) r <- (K3, rs1, b)        t1 <- (K3, rs1, so1, b)
         r  <- (K3, b, rs1)       RelationalComb rel                [8 constraints]
```

B carries one extra existential `b` and one extra constraint, `r <- (K3, b, rs1)`, which is
`r <- (K3, rs1, b)` with the right-hand side in the other order — the redundant-by-order
duplicate `TICKET-substitution-gap.md` §4 already saw on this same corpus.  Modulo that, B
is A with `b` standing for the pair `(a, rs)`, and **`b` is FORCED**: from
`t1 <- (K4, rs, a)` and `t1 <- (K3, rs1, so1, b)` with `(|revenue|) <- (rs1, so1)` and
`K4 = K3 ⊎ (|revenue|)`, both right-hand sides reduce to `K4 ⊎ …`, so `b = rs ⊎ a`.
Substituting that back turns B's `r <- (K3, rs1, b)` into A's `r <- (K3, rs1, a, rs)` and
B's `t1 <- (K3, rs1, so1, b)` into A's `t1 <- (K3, rs1, so, a, rs)`.  The two contexts are
therefore equivalent on the published variables `(rel, r, t)`: a **conservative extension at
a name**, which is exactly what `ksplit_mint_conservativeExt` says a split mint is.  Neither
side is weaker.  (Note the direction: it is the flag-ON side that carries the extra name —
`np01` is also the one module in B6 where the flag produces MORE mints, 101 -> 108.)

### B4. Timing — one JVM at a time, nothing else running

Driver: `<scratch>/b4/bench.sh` — `ERMINE_JAVA_OPTS="-Xmx2g -Dermine.useInterface=false
[-Dermine.splitKey=true]" bin/ermine <file> </dev/null`, wall from `date +%s.%N`,
`module_s` from the program's own `Importing module 'X' (s seconds)` line.  Instances from
`tracker/tools/gen-res-star.py --star-to 9`, `gen-row-stress.py --from 10 --to 14`,
`gen-row-overlap.py --costar-to 8`, as `tracker/satterm/measure/REPORT.md` produced them.
Machine: nothing else running (`ps` showed 0 other JVMs bar the idle LSP server), 10 GB free.

| module | off, module s | on, module s | ratio |
|---|---|---|---|
| ResStar5 | 0.21 | 0.19 | 0.90 |
| ResStar6 | 0.63 | 0.51 | 0.81 |
| ResStar7 | 1.98 | 2.01 | 1.02 |
| ResStar8 | 13.66 | 13.14 | 0.96 |
| ResStar9 | 89.00 | 85.20 | 0.96 |
| RowStress10 | 0.21 | 0.19 | 0.90 |
| RowStress14 | 0.45 | 0.49 | 1.09 |
| CoStar8 | 0.06 | 0.05 | — |
| **`incomplete/gu05_star_join_4dim_concrete_signature`** | **6.14** | **1.22** | **0.20** |

**The prediction held everywhere except gu05, and there it is a 5x WIN.**  ResStar is
unchanged, as predicted: its mints are `resolution`'s, and `splitConcrete` has no premise on
that family at all (`measure/REPORT.md` §1.3: 0 SplitConcrete firings at every m).  RowStress
and CoStar carry no concrete labels, so the split rule cannot fire there either.  The ±4-10 %
scatter is inside the ±15 % `measure/REPORT.md` records for repeats of the same run.

`gu05` repeated three times per side, one JVM at a time:

```
gu05 run1 off wall=18.40 boot=11.41 module=6.15      run1 on wall=13.54 boot=11.46 module=1.24
gu05 run2 off wall=18.52 boot=11.32 module=6.33      run2 on wall=14.35 boot=12.14 module=1.31
gu05 run3 off wall=18.36 boot=11.22 module=6.29      run3 on wall=13.34 boot=11.22 module=1.24
```

**Traced (B7), the mechanism.**  `-Dermine.rowTrace`, default (parallel) loading, one run per
side:

| | off | on |
|---|---|---|
| the big solve `gu05…e(62:1)`: `nIn` / `nParts` | 12 / 18 | 12 / 18 |
| its saturated set `nSat` | **1372** | **458** |
| its derived count `nDerived` | 1296 | 400 |
| trace records | 167,799 | 79,834 |
| `learn` records | 103,258 | 19,022 |
| `learn` new / seen | 56,664 / 46,594 | 10,826 / 8,196 |
| Substitution / CSE / Cancellation / Resolution | 56,914 / 28,867 / 12,768 / 3,635 | 10,469 / 3,328 / 3,565 / 1,335 |
| split MINTS (bare `SplitConcrete` records) | **69** | **42** |
| `SplitKeyed` (keyed reuses) | 0 | **5** |
| module time this run | 7.54 s | 1.55 s |

**Five keyed reuses cut the saturated set by 3x and the derivations by 5.4x.**  That is the
same shape as the `resGuard` adoption's win on the same file (12.0 s -> 1.1 s): one mint
avoided early removes a whole subtree of `Substitution`/`CSE` re-derivations over the names
it would have introduced.  `gu05` is the corpus maximum for solver work
(`measure/REPORT.md` §3), so this is the flag's effect at the corpus's worst point.

**A caveat that matters for B6.**  With `-Dermine.loadInSeries=true` — which the traced
sweep REQUIRES, because the analyser segments by `solve` record — `gu05`'s expensive solve
does not happen at all: the same module reports `nSat=83`, 16 split mints and 0.28-0.35 s of
module time on both sides.  The 1372-partition solve is a property of the PARALLEL loader.
So B6's per-module counts below are counts under the serialized loader and UNDERSTATE the
population the shipped compiler actually sees (gu05: 16 mints / 2 keyed serialized, 69 mints
/ 5 keyed parallel).  They are still a valid off-vs-on comparison, because both sides are
serialized.

### B5. REPL and LSP smoke

`repl-smoke.sh` and `lsp-smoke.sh` invoke `java` directly with a fixed option list and do
NOT read `ERMINE_JAVA_OPTS`, so the flag went in through `_JAVA_OPTIONS` (visible in the LSP
run's own log line `Picked up _JAVA_OPTIONS: -Dermine.splitKey=true`; `repl-smoke.sh`'s
`sed -n '/Loaded [0-9]* modules/,$p'` discards that banner line before the comparison, which
is why it does not disturb the golden diff).

| | off | on |
|---|---|---|
| `repl-smoke.sh` | PASS aliasing (2), relations (6), scoping (4), smoke (23) — **4/4 suites, 35 checks** | **identical, 4/4, 35 checks** |
| `lsp-smoke.sh` | **PASS lsp (98 checks)** | **PASS lsp (98 checks)** |

### B6. Trace-based population: does the keyed branch fire on real code?

```
$ tracker/tools/splitkey-sweep.sh        <out>/off      # 110 modules, one JVM each
$ SPLITKEY=true tracker/tools/splitkey-sweep.sh <out>/on
```

110 `core/examples/**/*.e`, one serialized (`-Dermine.loadInSeries=true`)
`-Dermine.rowTrace` run per module, `-Dermine.useInterface=false`, counts attributed to
solves located under `core/examples` by `splitkey-counts.py`.  (The two sides were run
CONCURRENTLY — they write no `.ei` and the counts are deterministic given
`loadInSeries`, so contention cannot move them; nothing here is a timing figure.)

| | off | on |
|---|---|---|
| modules | 110 | 110 |
| **verdicts (LOADED/REJECTED/TIMEOUT)** | — | **identical on all 110, 0 differ** |
| split MINTS | **692** | **637** |
| syntactic reuses | 531 | 577 |
| **keyed reuses (`SplitKeyed`)** | — | **77** |
| modules in which `splitConcrete` fires at all | 37 | 37 |
| **modules in which the KEYED branch fires** | — | **18** |
| modules with fewer mints on / more / same | — | **17 / 1 / 92** |

**The keyed branch is not dead code on real programs: 77 firings across 18 of 110 modules,
replacing 55 net mints (692 -> 637, −8 %).**  Per module (only the rows that move):

| module | verdict | mint off | mint on | syn off | syn on | keyed |
|---|---|---|---|---|---|---|
| `Ai/BatteryCycling.e` | LOADED | 29 | 23 | 16 | 11 | 3 |
| `Ai/ClinicalTrial.e` | LOADED | 19 | 15 | 9 | 7 | 2 |
| `Ai/FiscalCalendar.e` | LOADED | 18 | 17 | 9 | 12 | 2 |
| `Ai/GridTelemetry.e` | LOADED | 49 | 44 | 28 | 27 | 6 |
| `Ai/HeadcountPlan.e` | LOADED | 39 | 36 | 22 | 26 | 5 |
| `Ai/IncidentSeverity.e` | LOADED | 36 | 34 | 25 | 21 | 4 |
| `Ai/RevenueByPeriod.e` | LOADED | 39 | 36 | 14 | 18 | 4 |
| `Ai/SalesByRegion.e` | LOADED | 33 | 31 | 20 | 15 | 3 |
| `Ai/SupplyChainInventory.e` | LOADED | 50 | 40 | 28 | 25 | 7 |
| `Ai/TelescopeTime.e` | LOADED | 41 | 35 | 22 | 21 | 5 |
| `incomplete/RevenueShare.e` | LOADED | 31 | 23 | 49 | 46 | 8 |
| `incomplete/TargetList.e` | LOADED | 3 | 2 | 0 | 0 | 2 |
| `incomplete/RunCalibration.e` | LOADED | 25 | 23 | 42 | 42 | 2 |
| `incomplete/gu05_star_join_4dim…` | LOADED | 16 | 14 | 32 | 32 | 2 |
| `incomplete/gu08_label_inline.e` | LOADED | 21 | 18 | 12 | 14 | 2 |
| **`incomplete/np01_add_or_recompute.e`** | LOADED | **101** | **108** | 124 | 178 | 13 |
| `incomplete/np02_which_table_supplies_the_measure.e` | LOADED | 18 | 16 | 14 | 11 | 2 |
| `incomplete/np05_label_column_no_escape.e` | LOADED | 27 | 25 | 15 | 21 | 5 |

The population is exactly the one the earlier sweeps predicted: all ten `Ai/` reports (the
modules with concrete signatures, hence with `makeConcrete` steps, hence with
`splitConcrete` premises — `keptdef-sweep.sh`'s 27-module population) plus eight
`incomplete/` modules; **zero in the stdlib boot** (B1) and zero in the label-free families
(B4).

**`np01` is the one module where the flag produces MORE mints (101 -> 108, with 13 keyed
reuses and 54 more syntactic reuses).**  It is also the module whose `.ei` changed in B3.
The keyed reuse is not a subset of the shipped rule (`split_mint_not_keyed`): where it
reuses, it emits a DIFFERENT partition (`w <- (abstr)` instead of `u <- (abstr)`,
`v <- (u, concr)`), and that partition takes part in later CSE/substitution steps that can
open groups the shipped side never sees, so a later split can mint where it previously
reused.  The net effect on this module is +7 mints and one extra existential in the
published type (B3), with no verdict change and no measurable time change.  This is the
`DefaultStep`/`KDefaultStep` incomparability showing up on real code, and it is the reason
the corpus and `.ei` gates were needed at all.

### B7. Every gate that differed from expectation, with its mechanism

Three did.  All three were traced to the end; none is a blocker.

1. **B2, `shouldfail/der01`: one message differed.**  NOT the flag — two flag-OFF runs of the
   same build differ from each other on exactly this line, and a re-run of the whole OFF side
   agrees with the ON side on all 66 files.  `splitConcrete` does not fire in that module at
   all (`mint=0 synreuse=0 keyed=0` over its 14 solves, both sides).  Mechanism:
   `Constraints.checkLabel` keeps the FIRST contradiction it unit-propagates to, and which
   clause that is depends on the order of the input partition list, which is keyed on
   variable ids, which the parallel module loader perturbs.  56 repeat runs with the flag OFF
   (sequential, six-way concurrent, and one per `-XX:ActiveProcessorCount ∈ {1,2,3,4,6,8,12}`)
   all printed the ON side's clause.  Both clauses are correct refutations of the same field
   at the same location.  Full detail in B2.
2. **B4, `gu05`: predicted "unchanged", measured 5x faster** (6.14 -> 1.22 s of module time,
   3 runs each).  Mechanism traced in B4: five keyed reuses in the module's single large
   solve take its saturated set from 1372 to 458 partitions and its `learn` records from
   103,258 to 19,022.  The prediction was right about ResStar/RowStress/CoStar — those are
   `resolution`'s mints or have no concrete labels — and wrong about the one corpus module
   where `splitConcrete` mints heavily inside one solve.
3. **B6/B3, `np01`: the flag produced MORE mints (101 -> 108) and a bigger published
   context** (7 -> 8 constraints, one extra existential).  Mechanism in B6/B3: the two
   calculi are incomparable, so a keyed reuse can change which groups later firings see; the
   resulting extra name is FORCED by the remaining constraints (shown in B3), so the
   published type is equivalent, not weaker.

One further deviation, of method rather than of result: **`splitConcrete`'s population under
the serialized loader is smaller than under the shipped parallel one** (gu05: 16 mints
serialized, 69 parallel).  B6 had to serialize — the trace analyser segments by `solve`
record — so its 692/637/77 are a lower bound on what the shipped compiler does.  B4's traces,
which do not need segmentation, were taken under the default parallel loader.

---

## Part C — the path to default

### C.1 The gate table

| gate | expected | flag OFF | flag ON | verdict |
|---|---|---|---|---|
| `sbt core/compile` | clean | ok (11 s) | same classes | PASS |
| `core/test` | 903/904, known `disjunction sound` starvation | **903/904**, that failure | **903/904**, that failure | PASS |
| B0 satterm W2/H2/NE6, 100 bases each | no hang, no rejection | 300/300 SOLVED | **300/300 SOLVED** | PASS |
| B0 W2 supply draws | (control: must move) | 1 ×67, 2 ×33 | **0 ×100** | PASS, non-vacuous |
| B0 `SplitKeyed` in the W2 base-0 trace | must fire | 0 | **1** (then `SelfSubstitution: e1 <- ()`) | PASS |
| B0 crule `W`, `gseed`, 100 bases each | still rejected | 100/100 REJECTED | **100/100 REJECTED**, output byte-identical bar the banner | PASS |
| B0 KeepMint control | mints on both (key is open) | 16 mint / 0 reuse | **16 mint / 0 reuse, 0 keyed**, all 32 lines identical | PASS |
| B1 stdlib boot | 129 modules | 129, 11.43–12.34 s | **129**, 11.54–11.66 s | PASS |
| B1 boot `SplitKeyed` vs `SplitConcrete` | (population fact) | 0 / 0 | **0 / 0**, traces byte-identical | PASS (flag invisible there) |
| B2 examples corpus | 23 LOADED / 43 REJECTED, 0 differ | 23/43 | **23/43**, **0 of 66 differ** | PASS |
| B2 `shouldfail/` | 40/40 rejected | 40/40 | **40/40** | PASS |
| B2 `incomplete/` | 18/16, 0 differ | 18/16 | **18/16**, **0 of 34 differ** | PASS |
| B3 published types | no signature weaker | control A vs A′: 4 of 188 churn | **0 weaker in every comparison**; 2 bindings attributable, 1 alpha-equivalent + 1 equivalent-with-a-forced-name | PASS |
| B4 ResStar 5–9, RowStress 10/14, CoStar8 | unchanged | — | ratios 0.81–1.09 | PASS |
| B4 `gu05` | unchanged (predicted) | 6.14/6.33/6.29 s | **1.22/1.24/1.31 s (5x faster)** | PASS, better than expected |
| B5 `repl-smoke` | 4/4 | 4/4 (35 checks) | **4/4 (35 checks)** | PASS |
| B5 `lsp-smoke` | 98/98 | 98/98 | **98/98** | PASS |
| B6 keyed firings on real code | non-zero, or say so | — | **77 firings, 18 of 110 modules**; mints 692 -> 637 | PASS, non-vacuous |
| B6 verdicts over 110 modules | unchanged | — | **0 differ** | PASS |

### C.2 The one-line diff that would flip the default — APPLIED 2026-09-03

*(Applied later the same day, with the ADOPTED comment below; the text that follows is as written before the decision.)*

`core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, line 817:

```diff
-    val splitKey: Boolean = System.getProperty("ermine.splitKey", "false") == "true"
+    val splitKey: Boolean = System.getProperty("ermine.splitKey", "true") == "true"
```

and the comment above it, line 815, must change from

```
     * DEFAULT OFF pending the adoption gates in `tracker/satterm/KEYED-SPLIT-STAGE2.md`.
     * `-Dermine.splitKey=true` enables it. */
```

to an ADOPTED paragraph in the shape the other four flags use — what it is, the Lean that
licenses it, the gates, and the escape hatch — e.g.

```
     * ADOPTED <date>: DEFAULT ON.  `-Dermine.splitKey=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-SPLIT-STAGE2.md`):
     *   - proved not a semantic change (`ksplit_reuse_sat`, `KSplitStep.reuse_models_iff`,
     *     `ksplit_mint_conservativeExt`) and TERMINATING on every satisfiable system in
     *     every run order (`terminatesOnSatKeyed`), with the shipped guard's version of the
     *     same statement proved FALSE (`keyed_vs_syntactic`), so the boundary is known;
     *   - 66-file example corpus and 34-file incompleteness corpus: 0 files differ,
     *     verdicts identical (23/43 and 18/16), `shouldfail/` 40/40 still rejected;
     *   - 188 published interfaces / 1932 bindings: no signature weaker; the only two
     *     bindings attributable to the flag are alpha-equivalent and equivalent-modulo-a-
     *     forced-name, everything else appears in a same-configuration control run;
     *   - `core/test` 903/904 with the flag ON, the one failure being the pre-existing
     *     `Constraints.disjunction sound` generator; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *   - and it is not merely insurance: `core/examples/incomplete/gu05_star_join_4dim_
     *     concrete_signature.e` goes from ~6.2s of module time to ~1.2s, a 5x reduction,
     *     because five keyed reuses take its largest solve from 1372 saturated partitions
     *     to 458.  The branch fires 77 times over 18 of the 110 example modules (and zero
     *     stdlib ones), so the corpus zeros above are the guard running on real code. */
```

`ROW-CONSTRAINT-STATE.md` would gain an ADOPTED entry in the same shape as `resGuard`'s and
`labelCheckEarly`'s, and `KEYED-SPLIT.md` §6's "The flag is not implemented / that is
Stage 2" bullet and `KeyedSplit.lean`'s closing "**The flag is not implemented.**" line would
be updated.

### C.3 What would be re-run after the flip, and what `toString` prints

Re-run the same gates against the NEW default with no flags, which is how `cut`,
`labelCheck`, `resGuard` and `labelCheckEarly` were each confirmed:

* `sbt -batch core/compile`, then `sbt -batch -J-Xmx3g core/test` (expect 903/904);
* `tracker/tools/corpus-run.sh` and `--incomplete`, compared against a
  `-Dermine.splitKey=false` side (the flag inverts: the RESTORE side now needs the property);
* `tracker/tools/ei-diff.sh <out> "-Dermine.splitKey=false"`, classified with
  `tracker/tools/ei-classify.py`, **with a same-configuration control sweep**, because 4 of
  188 interfaces churn between two runs of one build;
* `tracker/tools/repl-smoke.sh`, `tracker/tools/lsp-smoke.sh`;
* `tracker/repro/satterm/sweep.sh` W2/H2/NE6 and `tracker/repro/crule/sweep.sh` W/gseed;
* the `gu05` and ResStar timings, one JVM at a time.

`GenRules.toString` — printed by `tracker/repro/*/run.sh`'s banner and by anything that logs
the configuration — becomes

```
cut+label-early+resguard+splitkey                 (the new default, no properties)
cut+label-early+resguard                          (with -Dermine.splitKey=false)
```

### C.4 The honest scope

* **What becomes true for the first time.**  `terminatesOnSatKeyed` bounds EVERY productive
  run of the additive keyed calculus, in EVERY order, from every satisfiable input, with the
  explicit bound `KRun.length_le : n ≤ M·2^M·2^|L|`.  With the shipped guard the same
  statement is FALSE (`DefaultSatDiverge.not_TerminatesOnSat`, witness `W2`).  So after the
  flip the loop's termination on well-typed input stops resting on the three unproved
  order-properties the tracker lists (name travel, eager unification of singleton links,
  eager `makeEmpty`) and rests on a theorem about the rule set instead.
* **What does NOT become true.**  (i) **Ill-typed input is untouched.**  `KDefaultStep` still
  contains guarded resolution, which diverges on the unsatisfiable `ResGuardDiverge.gSeed`;
  the measure needs a model and there is none.  The label check and `RHS.merge` remain the
  only defences there, and `DefaultDiverge.not_CRule` still exhibits an unsatisfiable system
  the input check does not refute.  B0 measures this: `gseed` and `W` behave identically on
  both sides.  (ii) **The theorem is about the ADDITIVE relation, not about
  `incorporateAll`.**  The real loop deletes and renames (`makeEmpty`, `makeConcrete`,
  `unify`, `dedup`) and is not a sub-relation of any additive relation in the development;
  `NameLoss.orderB_remint_enabled` shows deletion can re-enable a mint, and for the KEYED
  guard the witness deletion would remove is `p <- (z, K)`, which is exactly what
  `makeConcrete`/`destructiveSub` absorb.  Whether the keyed guard survives the loop layer is
  NOT answered by Stage 1 or by this measurement.  (iii) **The keyed reuse emits a different
  NAME than a mint would** — `w <- (abstr)` for an existing `w`, not `u <- (abstr)` for a
  fresh `u`.  That is precisely what B3 measures, and the measurement is: 0 weaker
  signatures, one alpha-equivalent binding, one equivalent-modulo-a-forced-name binding.
  (iv) **The two calculi are incomparable, not nested** (`split_mint_not_keyed`); B6's `np01`
  row is that fact on real code, and it means "fewer mints" is a tendency (17 modules), not a
  guarantee (1 module goes the other way).

### C.5 Recommendation

**ADOPT WITH CAVEATS.**

The reasons, all measured above:

1. Every adoption gate this project uses is GREEN, and each was run with a positive control
   first: `core/test` 903/904 both sides; corpus 0 of 66 and 0 of 34 differ with
   `shouldfail/` 40/40; 188 interfaces with **no signature weaker**; `repl-smoke` 4/4;
   `lsp-smoke` 98/98; 129 stdlib modules; 300/300 satisfiable seeds solved and 200/200
   unsatisfiable seeds rejected.
2. It is not insurance only.  `gu05`, the corpus's worst solve, drops **6.2 s -> 1.2 s** of
   module time, by taking that solve from 1372 to 458 saturated partitions — the same kind of
   win, on the same file, that carried `resGuard`.  Corpus-wide the split rule mints 8 %
   less (692 -> 637 under the serialized loader).
3. The branch demonstrably runs on real code — 77 firings over 18 of 110 modules — so the
   zeros in the corpus and `.ei` gates are the guard working, not the guard sleeping.
4. It buys a THEOREM where there was none: termination on every satisfiable input in every
   run order, replacing a statement that is provably false for the shipped guard.

The caveats — none of them blocking, all of them things to write down at the flip:

* **It is a behaviour change, not a refactor.**  Ids shift, one published type in
  `incomplete/np01` gains an existential (equivalent, and forced), and on that module the
  flag produces MORE split mints, not fewer.  Anything downstream that compares `.ei` bytes
  against a stored baseline will see churn — and, as B3 shows, would see churn anyway.
* **It does nothing for ill-typed input**, which is where the remaining unproved risk lives
  (`not_CRule`).  Adopting this must not be recorded as closing that.
* **The theorem is about the additive relation.**  The loop layer (deletion, renaming) is
  still unproved, and for the keyed guard the deletion that could re-open a key is exactly
  `makeConcrete`'s.  A Stage 3 asking "does the keyed guard survive `destructiveSub`?" is the
  natural follow-up, in the shape `KeepInert.lean` has for the shipped rules.
* **B6's population figures are a lower bound** (serialized loader); the shipped parallel
  loader gives `gu05` alone 69 mints and 5 keyed reuses where the serialized one gives 16
  and 2.

The user decides.  Nothing was flipped, nothing was committed — *at the time of writing; decided ADOPT later the same day, flipped and committed.*

---

## Files touched

| file | what | state |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala` | `SplitKeyed` tag, `GenRules.splitKey` (**default off**), `splitConcrete`'s `resolvent` parameter and keyed-reuse branch, `learnPartitions` call site, comments | modified, LF preserved, NOT committed |
| `tracker/satterm/KEYED-SPLIT-STAGE2.md` | this report | new |
| `tracker/tools/splitkey-counts.py` | trace analyser for the three split branches | new, untracked |
| `tracker/tools/splitkey-sweep.sh` | 110-module traced sweep | new, untracked |
| `tracker/tools/ei-classify.py` | `.ei` signature classifier | new, untracked |

No default was changed.  The pre-existing uncommitted edits in the tree (the Lean modules,
the tracker documents, the `resGuard` comment in `Constraints.scala`) were left alone.
