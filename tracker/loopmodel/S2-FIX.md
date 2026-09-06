# S2 FIX — NO FALSE ACCEPTANCE, Part A: the Scala change and its gates

2026-09-06.  Worktree `~/research/ermine/ermine-scala-wt-s2`, branch `row-sound` off `fde996a`
(`scala3-migration`).  Brief `tracker/loopmodel/briefs/brief-S2.md`; design note
`tracker/loopmodel/S2-DESIGN.md`; the bug is `tracker/loopmodel/S1-REVIEW.md` §2.3–§2.6, §7.1 and
Appendix B.  **Part A only.**  Part B (the Lean mirror and the theorems) starts on the
orchestrator's go, after S1 is committed.  No commit was made anywhere.  Nothing in the main
checkout was written: both sides of every A/B were run FROM THE WORKTREE against a COPY of the
main checkout's class directories, which also keeps every path in a trace identical.

**Every flag introduced here defaults to OFF.**  Adoption is the user's decision, not this
stage's.

## 0. Outcome

**A-done.**  All A3 gates green (nothing changes with the flags off), all A4 gates green
(every unsatisfiable seed rejected, no satisfiable seed rejected, no substitution moved), and
the A5 corpus list is **EMPTY**: over 100 corpus files in the two tracked corpora and 145 files
over the eight `looptrace-corpus` groups, **not one program is newly rejected**, and exactly one
already-rejected module reports a different clause of the same refutation.  §7 lists what could
not be done.

The headline numbers:

| | flags OFF (shipped) | flags ON |
|---|---|---|
| the 6 compiler-confirmed UNSATISFIABLE seeds, 20 bases each | **5 of 6 SOLVED** at some base; the 6th dies by an internal panic | **0 SOLVED of 120**, each with the field-naming diagnostic |
| the reviewer's 665-seed false-acceptance population, 1 330 runs | **404 SOLVED** | **0 SOLVED** |
| 3 840 satisfiable-by-construction seeds × 10 bases | 38 400 SOLVED | 38 400 SOLVED, **byte-identical substitutions** |
| 8 corpus groups, 2 355 430 solves | — | **0 verdicts move, 1 message moves**, 0 newly rejected |
| published interfaces, 185 modules / 1 919 bindings | — | **identical to the main checkout's** |
| `core/test` / `TestLoopTrace` | 913/914, 714/714 agree | **913/914, 714/714 agree** (identical).  912/914 on the reviewer's run — the suite has at least two flaky properties, §P5 |
| `perf-bench.sh batch` cold median | 12.78 s | 12.89 s (inside the run-to-run spread) |

| | |
|---|---|
| flags | `-Dermine.rowSound` (master) + `.bare` / `.saturated` / `.decide` / `.budget`, **all OFF** |
| diff | `Constraints.scala` +357/−9, `Subst.scala` +102/−3, `RowTrace.scala` +29/−0 = **488 / 12** over 3 files; 276 of the 488 added lines are code, the rest comment |
| new files | `tracker/loopmodel/S2-DESIGN.md`, `tracker/loopmodel/S2-FIX.md` |
| toolchain | `~/.local/ermine-toolchain/jdk-21.0.12.1+1`, `-XX:ActiveProcessorCount=2`, one JVM at a time |

---

## 1. The change

| layer | flag (default OFF) | where | what |
|---|---|---|---|
| (i) | `-Dermine.rowSound.bare` | `Constraints.makeConcrete` → new `ensureExactly` | at a BARE definition `v <- ((\|C\|))` and a concrete instantiation `v := ((\|fs\|))`, require `C = fs`, not `C ⊆ fs`.  Same death as `ensureSuperset` ("Row types failed to unify", S1 death site 7).  Sound by `Loop/Sound.lean`'s `bare_refutes`. |
| (ii) | `-Dermine.rowSound.saturated` | `Subst.solve`, after `q.expand` | `labelClash` on the SATURATED set as well as on the input.  Sound by `Rowpartition.refute_saturated_sound`.  Independent of `GenRules.labelCheck`, so it can be measured alone. |
| (iii) | `-Dermine.rowSound.decide` | `Constraints.labelDecide`, called from `Subst.solve` after `labelCheckEarly`, before `q.expand` | a COMPLETE per-label decision — unit propagation plus case split — on the solve's LIVE INPUT (§3 of the design note).  Passing means a model was CONSTRUCTED and CHECKED against every partition. |
| — | `-Dermine.rowSound.budget=<n>` (200000) | — | decision nodes per label for (iii); on exhaustion NO VERDICT, counted and traced. |

`-Dermine.rowSound=true` turns all three on; each sub-flag overrides the master in either
direction.  `GenRules.toString` gains `+rsbare`/`+rssat`/`+rsdecide`, empty at the defaults.
New `RowTrace` records: `rsound <site> <loc> <kind> <detail>` with `kind` in
`bare | sat | decide | env | budget | ok`, all inside `if (RowTrace.enabled)`.

The exact property the fix targets, what "the input" is (S1 review **Z-6**: `solve` does not
`substType` its input and `SubstEnv` is long-lived), the diagnostics and the cost model are in
`tracker/loopmodel/S2-DESIGN.md` §2–§6.  In one line: *if `solve` returns with
`-Dermine.rowSound.decide` on and the budget was not exhausted, the row constraints it was
given, closed under the environment's bindings of the variables they mention, have a model.*

---

## 2. A3 — the flags OFF: nothing changes

| # | gate | command | result |
|---|---|---|---|
| A3-1 | `core/test` | `sbt -batch -J-Xmx3g -Dermine.looptrace=<main>/tracker/lean/.lake/build/bin/looptrace core/test` | **Total 914, Passed 913, Failed 1, Errors 0** (230 s).  The one failure is the known `Constraints.disjunction sound` starvation ("Gave up after only 0 passed tests. 501 tests were discarded"), unrelated. **PASS** — but see §P5 (V-4): the reviewer's run is **912/914**, the extra failure being a date-formatting flake in `writers`.  **Neither figure is a constant**; the suite has at least two properties with random seeds that can give up. |
| A3-2 | `TestLoopTrace` | same run | **714 solves (19 seeds × 6 bases + 600 generated); 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0**, 10 614 ms.  Both properties pass, and so does the positive control (id base +1: 53 of 714 disagree; `--flags=nongen`: 65 of 714).  Run with the flags OFF, as the brief instructs — the model has no `rowSound` and would disagree with the flags on until Part B.  The worktree has no Lean build, so the binary is the main checkout's, via `-Dermine.looptrace` (this is why B1's gate 2b read SKIPPED; here it ran). **PASS** |
| A3-3 | L2 corpus row trace, all eight groups, worktree-with-flags-off vs the MAIN checkout's classes | `trace-only.sh` (the compiler side of `tracker/tools/looptrace-corpus.sh` verbatim: `-Dermine.loadInSeries=true -Dermine.useInterface=false -Dermine.rowTrace=<file>`, `incomplete` per file) | **All 8 groups BYTE-IDENTICAL** over **2 355 430 solve segments**, 0 timeouts, 0 dropped, after canonicalising the stdlib class-directory prefix.  **PASS** — see the table below |
| A3-4 | the compiler's own output on those eight groups | same runs | **all 8 groups identical** modulo wall-clock times.  **PASS** |
| A3-5 | published `.ei` | `ei-sweep.sh` (`ei-diff.sh`'s sweep, parameterised by classpath; batch, chunk 5, interfaces ENABLED), FOUR sides incl. a same-configuration control | **PASS: 0 signatures weaker.**  MAIN vs worktree-with-flags-ON: **0 of 185 interfaces, 1 919 bindings identical**.  The single interface that moves anywhere is reproduced by the CONTROL, so it is sweep churn, not the change.  Full table in **§8** |
| A3-6 | the 18+2 tracked seeds at 10 bases, per-seed flags (`RE` → `-Dermine.emptyRow=true`, `D1`–`D4` → `-Dermine.labelCheck=false`), worktree vs MAIN classes | `SatTermRepro sweep json:<seed> 0 9`, 20 seeds × 10 bases = 200 runs | **byte-identical**, the only differing field being the `in NNN ms` wall clock the harness prints.  14 seeds SOLVED 10/10 (CHAIN COLL G7 H2 LBL NE6 NP01 PANIC3 RE RR W2 W3 W4 slow/GU05MIN), 6 REJECTED 10/10 (D1 D2 D3 D4 REF SUP). **PASS** |

### 2.1 The row-trace comparison in full

Both sides were run FROM THE WORKTREE, so every path in the trace is the same except the stdlib
module tree, which lives inside the class directory and is therefore a property of where the
classes are, not of the compiler.  With that one prefix canonicalised the two traces are equal
byte for byte:

| group | files | segments | md5 (identical on both sides) |
|---|---|---|---|
| boot | 0 | 54 199 | `ac9b905f9a89112ccb0b2d4890cf108f` |
| top | 15 | 92 673 | `72b12dd6bebd87b6b9bd6c7b77e4b1b2` |
| Ai | 11 | 83 942 | `c145fb8f04fb3ef39355316ed962dce2` |
| shouldfail | 40 | 56 032 | `c556ac308fff79ecdd195ec0b6e63bce` |
| bugs | 2 | 54 235 | `f4b6ee7368e0c37522f544fb6f8aaea5` |
| guide | 2 | 54 244 | `a473879d5fa3d7300662ccbe660e39fc` |
| shouldfail-controls | 5 | 54 739 | `85d1758d7ff372aa5055d81c54fe8875` |
| incomplete | 35 | 1 905 366 | `7a9925ad5f612299ed0d1a15c9690cbf` |
| **total** | **110** (+35 in `incomplete`) | **2 355 430** | |

(The raw md5s differ only because the two class roots have different path lengths:
`$T/main-snap/core/classes` against `…/ermine-scala-wt-s2/core/target/scala-3.3.8/classes`.
Nothing else in 2.36 M segments differs.)

---

## 3. A4 — the flags ON: every unsatisfiable seed rejected, no satisfiable one

### 3.1 `tracker/repro/satterm/seeds/unsat/` — the six compiler-confirmed witnesses

`run.sh sweep json:<seed> 300 319`, 20 bases each, `-Dermine.rowSound=true`:

| seed | shipped (flags off) | flags ON | the label the diagnostic names |
|---|---|---|---|
| `MIN1` | **SOLVED 20/20** | REJECTED 20/20 | `l35` |
| `FALSE-ACCEPT-1` (`u00019`) | **SOLVED 20/20** | REJECTED 20/20 | `l35` |
| `MIN2` | SOLVED 4/20 | REJECTED 20/20 | `l17` |
| `FALSE-ACCEPT-2` (`x00002`) | **SOLVED 4/20** | REJECTED 20/20 | `l17` |
| `PANIC-1` (`u00020`) | REJECTED by an internal `Subst.reduce` PANIC | REJECTED 20/20, a proper diagnostic | `l4` |
| `SURV1` (`U11/u00857`) | **SOLVED 20/20** | REJECTED 20/20 | `l20` |
| `ENV-LINK` (post-review, §P2) | **SOLVED 20/20** | REJECTED 20/20 | `l0` |

(The shipped column is measured at bases 300–319 here, not quoted from the S1 review: **S2
review V-5** caught this table saying "SOLVED at 300, 301" for `SURV1` where it is 20/20, and
a bare "SOLVED" for `FALSE-ACCEPT-2` where the count is 4/20.  Both corrected 2026-09-06.)

**140 runs, SOLVED = 0.**  Every label is the one the S1 review names (§2.3 `l35`, §2.5 `l17`,
§2.4 `l4`, §7.1 `l20`).  `PANIC-1`'s panic — an internal error with no source location — becomes
`Row partitions are unsatisfiable at field 'l4'`.

Per-layer, same 6 seeds × 20 bases, one flag at a time (SOLVED count):

| seed | flags off | (i) `bare` | (ii) `saturated` | (iii) `decide` |
|---|---|---|---|---|
| `MIN1` | 20 | 20 | **0** | **0** |
| `FALSE-ACCEPT-1` | 20 | 20 | **0** | **0** |
| `MIN2` | 4 | **0** | **0** | **0** |
| `FALSE-ACCEPT-2` | 20 | **0** | **0** | **0** |
| `PANIC-1` | 0 (panic) | **0** | **0** | **0** |
| `SURV1` | 20 | 20 | 20 | **0** |

which is exactly the review's prediction: (i) closes the bare-row hole (`MIN2`, `FALSE-ACCEPT-2`,
`PANIC-1`), (ii) closes everything but the seed it names as surviving, (iii) closes all six.

### 3.2 The reviewer's whole false-acceptance population — 665 seeds

`review-S1/bighunt.tsv`'s 665 distinct seeds at the two bases the hunt used (300, 301) =
**1 330 runs**, through the shipped `Subst.solve` (one JVM, `BulkRun`, `SatTermRepro`'s own seed
loader / system builder / capped runner):

| configuration | SOLVED | REJECTED |
|---|---|---|
| flags OFF (the shipped compiler) | **404** | 926 |
| (i) `bare` alone | 361 | 969 |
| (ii) `saturated` alone | **20** | 1 310 |
| (iii) `decide` alone | **0** | 1 330 |
| all three (`-Dermine.rowSound=true`) | **0** | **1 330** |

Two of those figures are independent confirmations of the S1 review's own classification of
this population: the shipped compiler's 404 is the review's "no panic — the compiler returns
`SOLVED`: 404 of 1 166" (§7), and (ii)'s residual 20 is the review's "20 runs / 10 seeds the
§7.1 fix misses" (§7.1).

**Every one of the 1 330 rejections is the diagnostic naming a field** — 0 of 1 330 rejected by
anything else, and 0 with no label in the message.  The labels were then checked TWICE:

* against the reviewer's oracle (`classify-big2.tsv`): of the 1 166 runs it classified,
  **1 159 name the same label**; the other 7 name a different one;
* against an INDEPENDENT brute-force per-label checker written from the semantics for this
  stage (`labelsat.py`: enumerate every assignment of `[l ∈ rho v]`, keep the ones under which
  every partition's parts are pairwise disjoint and union to its whole).  Over the **667
  distinct (seed, label) refutations**, **0 are satisfiable at the named label** — including
  all 7 disagreements, each of which is a system unsatisfiable at BOTH labels
  (`U12/u00373` l18 and l29, `U12/u01151` l12/l39, `U12/u01748` l14/l22, `U14/u00476` l2/l31,
  `U16/u00508` l32/l33).

So: no false acceptance left in the population, and no unsound refutation in it either.

### 3.3 No false rejection — the satisfiable seeds

*Round 8's hunt corpus*, 3 840 seeds that are SATISFIABLE BY CONSTRUCTION (`L5r8/hunt/gen5.py`
fixes a valuation first and re-verifies every emitted constraint), × bases 0–9 = **38 400 runs**
per configuration:

| | SOLVED | REJECTED | HANG | OOM |
|---|---|---|---|---|
| flags OFF | 38 400 | 0 | 0 | 0 |
| `-Dermine.rowSound=true` | **38 400** | 0 | 0 | 0 |

and the two runs' **substitutions are byte-identical**: `diff` over the 38 400 result lines
(seed, base, verdict, the full `v0 := … ; v1 := …` substitution) is **empty**, md5
`f60e522eddf3be5e6dc5fc6f99fec385` on both sides.  Budget exhaustions: **0**.  Total decision
nodes over the 38 400 runs: 40 005 (≈ 1 per solve — propagation settles almost everything and
the case split is what closes the rest).

*The tracked seeds*, 20 seeds × bases 0–9 with their per-seed flags: verdicts identical
(14 SOLVED 10/10, 6 REJECTED 10/10) and every SOLVED substitution identical.  The only change
anywhere is the MESSAGE on `D1`–`D4`, and it has a cause worth recording (§6.2).

### 3.3b `seeds/slow/GU05` — the slow seed

`seeds/slow/GU05.json`, bases 0–9, 60 s cap (this is the seed that is in `slow/` because it
diverges at most bases):

| | SOLVED | REJECTED | HANG |
|---|---|---|---|
| flags OFF | 3 | **0** | 7 |
| `-Dermine.rowSound=true` | 3 | **0** | 7 |

Same verdicts, same per-base outcome, and the `DRAWN` histogram matches to within the sampling
of a timed-out run (`743 1091 10518 11201 12786 16431 18760 19225 23256 25083` against
`743 1091 10868 11273 12700 16374 18671 19225 23356 25043` — a HANG's draw count is read at the
moment the cap fires).  **The check does not refute it and does not change its shape.**

### 3.3c The sub-flags and the budget do what they say

| check | result |
|---|---|
| `-Dermine.rowSound=true -Dermine.rowSound.bare=false` | `GenRules` prints `…+rssat+rsdecide` — the master is overridden per layer in both directions; `MIN2` still REJECTED 2/2 (by (iii)) |
| `-Dermine.rowSound.bare=true` alone | `GenRules` prints `…+rsbare`; `MIN2` REJECTED 2/2 (by (i)) |
| `-Dermine.rowSound.decide=true -Dermine.rowSound.budget=0` on `SURV1` | **SOLVED 2/2** — the search gives up, `LabelNoVerdict`, and NOTHING is refuted.  This is the fail-safe working, and it is why P carries the budget as a hypothesis rather than hiding it |
| the same with `budget=1` | REJECTED 2/2 — one decision node is all `SURV1` needs |

### 3.4 `core/test` and `TestLoopTrace` with the flag ON

The brief says to run these with the flag OFF, because the Lean model has no `rowSound` layer
and would be expected to disagree; §2 gates A3-1/A3-2 are that run.  The flags-ON run was done
as well, and the expected disagreement **did not happen**:

```
sbt -batch -J-Xmx3g -Dermine.rowSound=true -Dermine.looptrace=<main>/…/looptrace core/test
[info] Failed: Total 914, Failed 1, Errors 0, Passed 913
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. …
[loop model trace] 714 solves; 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0
                   nonpart=0 rejected=36 fuel=0
```

Identical to the flags-OFF run in every figure, `rejected=36` included.  The reason is §6.1's
placement: (iii) runs AFTER `labelCheckEarly`, which `TestLoopTrace` leaves on, so every seed
the suite refutes is refuted before (iii) can speak, and its 600 generated systems are
satisfiable by construction so (iii) passes them with a model.  `TestLoopTrace` will still need
Part B's mirror for a configuration that reaches (iii) — `D1`–`D4` under `labelCheck=false`
(§6.2) is exactly such a configuration — but at the suite's own flags there is nothing to
mirror yet.

---

## 4. A5 — the corpus with the flags ON

### 4.1 The list of newly rejected programs: **EMPTY**

| corpus | files | flags OFF | flags ON | verdicts moved | messages moved |
|---|---|---|---|---|---|
| `corpus-run.sh --batch` (examples + Ai + shouldfail) | 66 | 23 LOADED / 43 REJECTED, `shouldfail/` **40/40** | 23 LOADED / 43 REJECTED, `shouldfail/` **40/40** | **0** | **1** |
| `corpus-run.sh --incomplete --batch` | 34 | 18 LOADED / 16 REJECTED | 18 LOADED / 16 REJECTED | **0** | **0** |
| the eight `looptrace-corpus` groups (`boot top Ai shouldfail bugs guide shouldfail-controls incomplete`) | 145 | — | — | **0** | **1** (+1 batch artefact, §4.3) |

**Not one program in either corpus is newly rejected.**  The one message that moves is on a
module that ALREADY fails:

| file | flags OFF | flags ON | what changed |
|---|---|---|---|
| `core/examples/shouldfail/inf04_except_recursive.e` | `:22:7: Row partitions are unsatisfiable at field 'Shouldfail.Inf04.a': two parts of one partition both contain it` | `:20:10: Row partitions are unsatisfiable at field 'Shouldfail.Inf04.a': a part contains it but the whole does not` | still REJECTED, same file, SAME FIELD, an earlier line and a different clause of the same refutation |

Reproduced PER FILE (a virgin session), not only in a batch, so it is a real difference and not
session churn.

### 4.2 The check really ran — and one solve in 2.36 M needed the environment

From the `rsound` records of the flags-ON eight-group run:

| kind | boot | top | Ai | shouldfail | bugs | guide | sf-controls | incomplete | total |
|---|---|---|---|---|---|---|---|---|---|
| `ok` (a model built and CHECKED at every mentioned label) | 54 199 | 92 673 | 83 942 | 56 003 | 54 235 | 54 244 | 54 739 | 1 905 357 | **2 355 392** |
| `decide` (refuted) | 0 | 0 | 0 | **1** | 0 | 0 | 0 | 0 | **1** |
| `env` (the live input needed `SubstEnv` facts) | 0 | 0 | 0 | **1** | 0 | 0 | 0 | 0 | **1** |
| `budget` (no verdict) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `bare` (i) / `sat` (ii) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |

So (iii) decided **every** solve the corpus performs, and the corpus contains **no** row system
that any of the three layers refutes — except one, and the two records above are the SAME solve:

```
rsound  inferImplicitBindingTypes  core/examples/shouldfail/inf04_except_recursive.e(1:1)  env     1  0
rsound  inferImplicitBindingTypes  core/examples/shouldfail/inf04_except_recursive.e(1:1)  decide  Shouldfail.Inf04.a  r2^339510  0  a part contains it but the whole does not
```

That is worth spelling out, because it is S1 review **Z-6** appearing in real code and nowhere
else.  In the whole corpus exactly ONE `solve` is handed constraints mentioning a variable the
long-lived `SubstEnv` already binds; adding that one binding as a fact (1 fact, **0 opaque**)
is what refutes the module, at 0 decision nodes — pure propagation on the LIVE input, which the
shipped check cannot see because it reads the input unsubstituted.  Every other solve in the
corpus has an empty environment intersection, which is why deciding `q` alone would have been
almost, but not exactly, the same property.

### 4.2b The corpus trace with the flags ON, minus the new records

A sharper form of the same statement.  Strip the new `rsound` records from the flags-ON trace
and compare what is left with the flags-OFF trace, group by group:

| group | result |
|---|---|
| boot, top, Ai, bugs, guide, shouldfail-controls, incomplete | **BYTE-IDENTICAL** (2 299 398 segments) |
| shouldfail | 260 record lines differ, of 56 032 segments |

and those 260 lines are confined to three files in one JVM: `inf04_except_recursive.e` (11 lines
— the module that is now refuted earlier) and `inf05_union_two_fields.e` (128) and
`inf06_row_minus.e` (52) plus the stdlib `Relation/Row.e` solves they instantiate, which follow
`inf04` in the same session and see shifted ids.  Both remain REJECTED, and per file both report
exactly what they report with the flags off.

So: with all three layers on, the solver does the same thing on 2.36 M solves except in the one
module where it now refutes.

### 4.3 The one batch-only difference, and why it is not a difference

In the eight-group run `shouldfail/inf05_union_two_fields.e` also differed (field
`Shouldfail.Inf05.b` at 23:30 → `Shouldfail.Inf05.a` at 23:18).  Per file it does NOT:

```
inf05, per file, flags OFF : 23:18 … at field 'Shouldfail.Inf05.a': a part contains it but the whole does not
inf05, per file, flags ON  : 23:18 … at field 'Shouldfail.Inf05.a'  (identical)
```

`inf04` is refuted a few ids earlier with the flags on, which shifts every id after it in that
one JVM, and the blame CLAUSE is id-order dependent — the same batch-only churn `B1-FIX.md`
gate 4d measured and the reason `corpus-run.sh`'s header keeps per-file as the default.  In the
canonical `corpus-run.sh --batch` gate (a different chunking) `inf05` does not differ at all:
1 of 66 there, and it is `inf04`.

---

## 5. The cost

### 5.1 The P1 harness, batch mode, three interleaved rounds

`tracker/tools/perf-bench.sh batch -n 5`, cold (interface-free, full inference), 129-module
stdlib closure, a FRESH JVM per rep, `PERF_JVM_PROPS="-XX:ActiveProcessorCount=2 [-Dermine.rowSound=true]"`.
The machine was NOT quiet — a desktop session with a browser — so `PERF_MAX_LOAD` was raised
and the 1-minute load average is recorded with every round, as the harness prints it.

| round | flags OFF median (min–max, spread) | load | flags ON median (min–max, spread) | load |
|---|---|---|---|---|
| 1 | **12.81 s** (12.51–12.89, 0.38) | 1.68 | **12.89 s** (12.72–13.01, 0.29) | 3.43 |
| 2 | **12.72 s** (12.64–12.97, 0.33) | 2.68 | **12.62 s** (12.43–12.91, 0.48) | 2.64 |
| 3 | **12.78 s** (12.67–12.88, 0.21) | 3.10 | **13.00 s** (12.53–13.23, 0.70) | 2.67 |
| median of medians | **12.78 s** | | **12.89 s** | |

**+0.11 s, +0.9 %** — smaller than the within-round spread (0.21–0.70 s) and the sign flips
between rounds (round 2 has the flags ON *faster*).  Read as: **no batch cost the harness can
resolve on this machine**, not as a measured 0.9 % regression.  `ei_after=0` on every run, so
every rep really was interface-free.  Machine `dmitry-Z370P-D3`, OpenJDK 21.0.12.1, heap 3984 MB.

### 5.2 (iii)'s own bill, per solve, from the trace

Over the eight groups (2 355 392 decided solves):

| | |
|---|---|
| total time inside `decideLabels` | **0.69 s** (689 506 µs) for the whole corpus |
| total decision nodes | 1 051 |
| budget exhaustions | **0** |
| solves with at least one input partition | 26 404 of 2 355 392 (1.1 %) — the row solver is called 2.36 M times and almost every call has no row constraint at all |
| over those 26 404: median | **7 µs** |
| p90 / p99 / p99.9 | 19 µs / 94 µs / 1 597 µs |
| solves that mention any label (so the decision has real work) | **7 834**, i.e. 0.33 % — 12 380 per-label decisions in all |
| largest INPUT partition count anywhere | **18** |

**The per-solve maximum.**  The corpus's most expensive decision is
`incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)`: **10 labels, 18 input partitions,
4 decision nodes, 3.5–3.7 ms** (3730 / 3672 / 3521 µs over three separate module loads, so it
is reproducible and not a scheduling artefact).  It is the ONLY solve in that whole module load
with a mentioned label — 1 of 54 235 — so the figure is the cost of running that code path
COLD, interpreted, exactly once; the next most expensive solve in the same run is 34 µs.  Over
the whole corpus only **7 834** of the 2 355 392 solves mention a label at all (12 380 per-label
decisions), which is why that path never becomes hot.
Four solves elsewhere in the corpus billed 4–6 ms with **zero labels and zero partitions**,
i.e. the decision did no work at all and the time is JVM noise around a `System.nanoTime` pair.

**On `gu05`'s 1 372 partitions.**  That figure is the SATURATED set (458 with the shipped
`splitKey`).  (iii) runs on the INPUT, and gu05's largest input is 18 partitions — which is why
an NP-complete check costs milliseconds here.  Layer (ii), which does read the saturated set,
is one `labelClash` pass and is included in the §5.1 measurement (all three flags were on).

---

## 6. Notes a reviewer should have

### 6.1 Where (iii) sits, and why

AFTER `labelCheckEarly`, BEFORE `q.expand`.  After the early check so that an input unit
propagation already refutes reports exactly the message it reports today — which is why the
corpus delta in §4 is (iii)'s OWN refutations and not a re-wording of existing ones.  Before
`expand` because refuting an unsatisfiable input before the saturation can diverge on it is
half the point (`Rowpartition/ResGuardDiverge.lean`).

### 6.2 (iii) is NOT gated on `GenRules.labelCheck`, and that pre-empts `D1`–`D4`

The four tracked seeds `D1`–`D4` exist to exercise four `die` paths (`selfSubstitution`,
`RHS.merge`, `makeEmpty`'s `aux`, `ensureSuperset`) and they need `-Dermine.labelCheck=false`
to be reached at all.  Since (iii) carries the theorem, it must run whether or not the shipped
propagation is switched on — so with `labelCheck=false` AND `rowSound.decide=true` all four
report the field diagnostic instead:

| seed | `labelCheck=false` alone | + (i) `bare` | + (ii) `saturated` | + (iii) `decide` |
|---|---|---|---|---|
| `D1` | `Infinite row partition for 'v0^0'` | unchanged | unchanged | `… at field 'l1': two parts …` |
| `D2` | `Fields appear twice in row: Set(l1)` | unchanged | unchanged | `… at field 'l1': two parts …` |
| `D3` | `Incompatible instantiations of 'v0^0'` | **`Row types failed to unify`** (this is (i) firing) | unchanged | `… at field 'l1': a part contains it …` |
| `D4` | `Row types failed to unify` | unchanged | unchanged | `… at field 'l2': the whole contains it but no part does` |

All four stay REJECTED 10/10 at bases 0–9.  A death-site sweep that wants those four paths
should keep `-Dermine.rowSound.decide=false`, which is exactly what the sub-flags are for.
Part B's L2 replay has to mirror this: the model will otherwise take a different branch on
these seeds.

### 6.3 What (iii) treats as existentially quantified

Skolem row variables, like `labelClash` always has.  A model with skolems free is weaker than
"the program type-checks", so P (design note §2) is a statement about satisfiability with every
variable existential.  It costs nothing in the refutation direction and it is stated rather than
assumed.

### 6.4 Fail-safe by construction

A branch that assigns every bit without a clash is verified against every partition before SAT
is returned; if that verification ever fails the answer is `LabelNoVerdict`, never UNSAT.  A bug
in the propagator can therefore cost a refutation but cannot cause a false rejection.  Same for
the budget, and for a `SubstEnv` binding that is not row-shaped (counted as `opaque`, skipped;
**0 over the whole corpus**).

---

## 7. What could NOT be done — side by side

| asked for | done | not done, and why |
|---|---|---|
| A3 `.ei` unchanged with the flags off | four batch sweeps (MAIN classes, worktree-OFF, worktree-ON, and a same-configuration CONTROL), §8 | a PER-FILE sweep — the mode every adopted measurement uses — was not run: `ei-diff.sh`'s own header measures a side at 13m45s per file, four sides would be ~55 min of it, and the batch mode is symmetric across sides, which is the condition its header sets for using it.  The control makes the batch's own churn measurable, which is what the per-file mode would have bought. |
| A4 `core/test` with the flags on | **run** — 913/914, the same single known failure, and `TestLoopTrace` still 714/714 (§3.4) | nothing outstanding.  What that run does NOT establish is that the model and the compiler agree in a configuration that actually reaches (iii): at the suite's flags `labelCheckEarly` gets there first.  Part B has to mirror (iii) before `D1`–`D4` under `-Dermine.labelCheck=false` can be replayed. |
| A5 "list EVERY newly rejected program, with the violated label and the source location" | the list is EMPTY, and §4.1 says so with the two corpora's verdict counts | nothing withheld.  The single message that moves (`inf04`) is given with its field, both positions and both clauses. |
| the per-solve maximum of (iii) | §5.2 | it is a COLD number: the corpus never runs the labelled path often enough to JIT it (1 501 labelled decisions in 2.36 M solves), so no steady-state per-solve figure exists to quote.  The corpus's total bill (0.69 s) and the warm percentiles are given instead. |
| costs on a quiet machine | measured three interleaved rounds and recorded the load with each | the machine was not quiet (load 1.7–3.5; a desktop session, and a Lean build in the main checkout for part of the window).  `PERF_MAX_LOAD` was raised deliberately rather than the guard being silently defeated, and the conclusion drawn from §5.1 is "no resolvable cost", not a figure. |
| REPL / LSP smokes (`repl-smoke.sh`, `lsp-smoke.sh`) | not run | not in the S2 brief's gate list (they are B1's 6a/6b).  `tracker/repl-classpath.txt` WAS regenerated for the worktree to run `perf-bench.sh` and is restored to its committed content (§9), so the diff Part B applies is the three source files alone. |
| Part B | not started | by instruction: it begins on the orchestrator's go, after S1 is committed. |

---

## 8. The published interfaces (`.ei`)

Method: `ei-diff.sh`'s own `sweep`, parameterised by CLASSPATH instead of by flags (batch,
chunk 5, interfaces deliberately ENABLED — `-Dermine.useInterface=false` suppresses writing as
well as reading and would leave nothing to diff), run from the worktree over the same 110 `.e`
sources for every side, with the stdlib root canonicalised in the flattened snapshot names so
the class sets line up.  Every side captured **185 interfaces / 1 919 bindings** (the figure
`ei-diff.sh`'s own header documents for batch mode: two chunks reach the 180 s timeout, the same
two on every side — chunk 4 at `Incomplete.Gu04` and chunk 7 at `Incomplete.Np05`), and the
chunk logs are identical across sides apart from timings and the stdlib path.

| A | B | interfaces differing | bindings |
|---|---|---|---|
| MAIN classes | worktree, flags OFF | **1** (`STDLIB_Relation.ei`) | 1 910 identical, 7 order-only, 1 alpha-equivalent, 1 other; **0 concrete→polymorphic (WEAKER)**, 0 polymorphic→concrete |
| worktree, flags OFF | worktree, flags ON | **1** (`STDLIB_Relation.ei`, the same one, back the other way) | same counts |
| **MAIN classes** | **worktree, flags ON** | **0** | **1 919 identical** |
| worktree, flags OFF | worktree, flags OFF **(same-configuration CONTROL)** | **1** — the same interface, the same verdicts | 1 910 identical, 7 order-only, 1 alpha-equivalent, 1 other |
| MAIN classes | the CONTROL run | **0** | **1 919 identical** |

The third row is the one to read.  The MAIN checkout's compiler and this worktree's compiler
**with all three layers ON** publish **byte-identical interfaces for all 185 modules and all
1 919 bindings**.  The one interface that moves is `Relation.lookbackJoin`, whose residual goes
from 10 constraints to 9 and back, and it moves in the flags-OFF run — i.e. against the
direction any flag effect would have.  The batch sweep is not bit-stable (`ei-diff.sh`'s header
says so, `B1-FIX.md` gate 5b measured it: a same-configuration control there differed on 2 of
156 interfaces on its own), and the mechanism is visible here: two chunks are KILLED at the 180 s
timeout, so whether they had rewritten `Relation.ei` before the kill is decided by wall clock.
**The control proves it.**  Sweeping the worktree with the flags OFF a SECOND time, in exactly
the same configuration, reproduces the difference exactly — 1 of 185, `STDLIB_Relation.ei`, the
same 7 order-only / 1 alpha-equivalent / 1 other split — and that control run then agrees with
the MAIN checkout on all 185 interfaces.  Three of the four sweeps (MAIN, worktree-with-flags-ON,
and the control) are identical to each other; the odd one out is a flags-OFF run, which is the
configuration that is supposed to change nothing.  So none of the churn is attributable to this
change, and there is no binding left to classify by hand.

**No published signature is weaker under any configuration**, which is the property this gate
exists to check.

---

## 9. Hygiene

* **No commit** was made in the worktree, the main checkout, or any sibling worktree.
* **Nothing in the main checkout was written.**  Both sides of every A/B ran from the worktree;
  the main checkout's compiler was measured through a COPY of its class directories
  (`main-snap/`), which is also what makes every path in the row traces line up.  `git status`
  in the main checkout shows only the S1 agent's own files.
* `.ei` files: the corpus harnesses delete them before and after every run; the `.ei` sweeps
  delete both trees' before each side and again at the end.  The main checkout's
  `core/examples` holds **0**, and the 129 under its `classes/modules` are from 2026-09-04,
  before this stage.
* `tracker/repl-classpath.txt` in a fresh worktree points at the MAIN checkout's classes, so
  `perf-bench.sh` would have measured the wrong compiler; it was regenerated for the worktree
  before §5.1 and RESTORED to its committed content afterwards.
* Traces are gzipped; scratch is `/home/dmitry/.claude/jobs/880c725d/tmp/S2/`.
* One JVM at a time throughout, `-XX:ActiveProcessorCount=2`, long runs under `setsid nohup`
  with a log.

---

## 10. How to re-run everything in this report

```bash
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
cd ~/research/ermine/ermine-scala-wt-s2
sbt -batch core/compile
sbt -batch 'export core/fullClasspath' | grep -v '^\[' | tail -1 | tr -d '\n' > target/ermine-classpath

# A3-1/A3-2  (the looptrace binary lives in the MAIN checkout; the worktree has no Lean build)
sbt -batch -J-Xmx3g -Dermine.looptrace=$HOME/research/ermine/ermine-scala/tracker/lean/.lake/build/bin/looptrace core/test

# A4-1  the six compiler-confirmed unsatisfiable seeds
M=$HOME/research/ermine/ermine-scala/tracker/repro/satterm/seeds/unsat
for s in MIN1 MIN2 SURV1 PANIC-1 FALSE-ACCEPT-1 FALSE-ACCEPT-2; do
  ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.rowSound=true -XX:ActiveProcessorCount=2" \
    tracker/repro/satterm/run.sh sweep json:$M/$s.json 300 319 | grep SUMMARY
done      # SOLVED=0 REJECTED=20, six times

# A4-2/A4-3  the populations, one JVM each (BulkRun reuses SatTermRepro's own loader/runner)
#   scratch: /home/dmitry/.claude/jobs/880c725d/tmp/S2/{BulkRun.scala,bulk.sh,pop665.txt,hunt3840.txt}
bulk.sh pop665.txt   300 301 pop665-off.tsv
bulk.sh pop665.txt   300 301 pop665-on.tsv  -Dermine.rowSound=true     # 0 SOLVED of 1330
bulk.sh hunt3840.txt   0   9 hunt-off.tsv
bulk.sh hunt3840.txt   0   9 hunt-on.tsv    -Dermine.rowSound=true     # diff: empty
python3 labelsat.py <seed.json> <label>     # the independent per-label oracle

# A3-3 / A5  the corpus, both sides, from the worktree
ERMINE_CP=<main-snap/classpath> trace-only.sh <out>                    # main classes
trace-only.sh <out>                                                    # worktree, flags off
trace-only.sh <out> -Dermine.rowSound=true                             # worktree, flags on
ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Dermine.rowSound=true" \
  tracker/tools/corpus-run.sh --batch <out>                            # 23 LOADED / 43 REJECTED
ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Dermine.rowSound=true" \
  tracker/tools/corpus-run.sh --incomplete --batch <out>               # 18 LOADED / 16 REJECTED

# A5 cost
PERF_MAX_LOAD=6 PERF_JVM_PROPS="-XX:ActiveProcessorCount=2 -Dermine.rowSound=true" \
  tracker/tools/perf-bench.sh batch -n 5
```

Scratch inventory (`/home/dmitry/.claude/jobs/880c725d/tmp/S2/`): `BulkRun.scala` /
`BulkRunMain.scala` (many seeds in one JVM, against the worktree's and the main checkout's
classes), `bulk.sh`, `tracked.sh` (the 20 tracked seeds with their per-seed flags),
`trace-only.sh` (the compiler side of `looptrace-corpus.sh`), `ei-sweep.sh` (`ei-diff.sh`'s
sweep parameterised by classpath), `labelsat.py` (the independent brute-force per-label
oracle), `pop665.txt`, `hunt3840.txt`, `main-snap/` (the main checkout's classes, copied),
and the result files named throughout.

---
---

# PART B — the model mirror and the theorems

2026-09-06, MAIN checkout `/home/dmitry/research/ermine/ermine-scala` on `5c08363` (S1
committed).  Part A's three-file Scala diff was applied here with `git apply` and confirmed
before anything else was touched (§B0).  No commit was made.

## B-outcome

**B-done.**  The three layers are mirrored in the model behind the same flag names, all
DEFAULT OFF; the L2 differential agrees on every one of the **2 355 430** corpus solve
segments with the flags OFF and on every one of the **2 355 428** with them ON (two solves
fewer, because `shouldfail/inf04` is refuted earlier — see §B4-1); `TestLoopTrace` passes with
the flag forwarded to BOTH sides; the development builds at 861 jobs and audits at **3 888
theorems / 0 non-standard axioms**; and the headline theorem is

> `solve_noFalseAccept` — with layer (iii) on and its budget not exhausted, a solve that does
> not reject says the constraints it was given, together with the environment facts, HAVE A
> MODEL.

which is the converse of S1 and the hypothesis `run_noLoss` and `solve_sound` are conditional
on.  **No pre-existing theorem module was touched and no existing theorem changed.**
Adoption (default ON) remains the user's decision and was not made here.

## B0. The Scala diff on `5c08363`

| step | result |
|---|---|
| `git apply --check` of the worktree's `git diff` over the three files | **applies cleanly** (the files are byte-identical to `fde996a` on `5c08363`) |
| `git apply`, then `cmp` against the worktree | all three files identical to the worktree's |
| `sbt -batch core/compile` | success, 8 s |
| `sbt -batch -J-Xmx3g -Dermine.looptrace=… "core/testOnly *TestLoopTrace"`, flags OFF | **714 solves; 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0** |
| `seeds/unsat/MIN2.json` at bases 300–319, flags OFF | **SOLVED at 300, 303, 307, 315** — the same 4 of 20 the S1 review reports |
| the same with `-Dermine.rowSound=true` | **SOLVED=0, REJECTED=20** |

## B1. One addition to the Scala: the `senv` replay record

Part A's §4.2 measured that in the whole corpus exactly ONE `solve` is handed constraints
mentioning a variable the long-lived `SubstEnv` already binds (S1 review **Z-6**), and that
that one binding is what refutes `shouldfail/inf04_except_recursive.e`.  A replay cannot
reproduce a flags-ON trace without it: the trace recorded only the COUNT.

So `RowTrace.solveInput` now also writes, **only under `-Dermine.rowSound.decide`**, one

```
senv  site  loc  v<id>  <term>
```

per environment binding of a variable the input mentions, in `scon`'s own term language.  It
is written from `solveInput` rather than from the check so that the label and variable tables
already carry anything the facts mention (`term` extends both, and the `slbl`/`svar` blocks
are emitted afterwards).  `Subst.solve` passes `hm.types`; nothing else changed.

**The flags-OFF trace is unaffected**, and that is measured, not argued: the eight-group
corpus trace taken on MAIN after this change is **byte-identical to Part A's**, group for
group, over 2 355 430 segments (stdlib class-root canonicalised, as in Part A §2.1), and the
flags-OFF trace contains **0** `senv` records.

## B2. The Lean mirror — files and shape

| file | lines | what |
|---|---|---|
| `tracker/lean/Rowpartition/Loop/Decide.lean` | NEW | the three layers, EXECUTABLE: `ensureExactly`/`bareExact`/`stepS`/`runS` (i), and `forcedBy`/`propagate`/`modelChecks`/`searchLabel`/`decideLabel`/`labelDecide` (iii).  Layer (ii) is `labelClash` on the saturated set and needs nothing new. |
| `tracker/lean/Rowpartition/Loop/NoFalseAccept.lean` | NEW | the theorems (§B3). |
| `tracker/lean/Rowpartition/Loop/State.lean` | +17/−1 | the four `Flags` fields and `toStr`. **Flag plumbing only.** |
| `tracker/lean/Rowpartition/Loop/Main.lean` | +~16 | the `--flags` tokens `rowsound`, `rsbare`, `rssat`, `rsdecide`, `norsbare`, `norssat`, `norsdecide`, `rsbudget=<n>`.  **Plumbing only.** |
| `tracker/lean/Rowpartition/Loop/Replay.lean` | +33/−3 | the `senv` record: a `Segment.envs` field, its parse arm, `finish`, and `Segment.envFacts` / `envOpaque`.  **Plumbing only.** |
| `tracker/lean/Rowpartition/Loop/Seed.lean` | +~14 | `solveSeed` gains an `envFacts` parameter (defaulted, so every existing caller is unchanged), calls `labelDecide` between the early check and the loop, `runS` instead of `run`, and `labelClash` on the saturated set — each guarded by its flag, all OFF by default. |

**No pre-existing THEOREM module was touched**, and no existing theorem changed or gained a
hypothesis.  The reason is the shape of `stepS`: layer (i) is a PRE-CHECK in front of `step`'s
`concrete` branch, so `stepS` can only turn a continuation into a death and never move one
(`stepS_continue`).  Every S1 theorem about `step` therefore applies verbatim with the flag on.

## B3. The theorems

Verbatim statements.  Everything below is in `tracker/lean/Rowpartition/Loop/NoFalseAccept.lean`.

### The headline

```lean
/-- **NO FALSE ACCEPTANCE.**  With layer (iii) on, a solve that does NOT reject says the
system it was given — the queue's partitions TOGETHER WITH the environment facts the trace's
`senv` records carry (S1 review Z-6; `S2-DESIGN.md` §3) — HAS A MODEL. -/
theorem solve_noFalseAccept {L : List Lbl} (hcoh : LblCoh L)
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeed fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED") :
    SSat ((((q.elems ++ envFacts).map LPart.toConstraint)).toFinset)
```

Read it against S1: `run_noLoss`, `run_models` and `solve_sound` are all conditional on
`SSat (sys s₀)`, exactly where they have to be.  **This is what supplies that hypothesis.**
Chained with S1: with the flag on and the budget intact, an accepted solve's output system
entails every input constraint and every model of the output is a model of the input
(`solve_sound` (A) applied at the `SSat` this theorem provides).

The two provisos are the ones `S2-DESIGN.md` §2 states and refuses to hide.  `hbud` is "the
search was not cut short": a cut is `NoVerdict`, refutes nothing, is counted
(`GenRules.rowSoundBudgetHits`) and never fired on the corpus (Part A §4.2).  `hnd`/`hmem`/
`hcoh` are the vocabulary side conditions — an abstract part is duplicate-free (`Wf`, and
`wf_of_nodup (by decide)` at a seed) and the solve's labels are coherent (`LblCoh`, the
hypothesis `Loop/Reject.lean` already carries).

### Completeness — the theorem that matters

```lean
/-- **LAYER (iii) IS COMPLETE.**  If the decision passes, the system HAS A MODEL — one that
was constructed label by label and checked against every constraint. -/
theorem labelDecide_sat_ssat {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart} {budget : Nat}
    (hnd : ∀ p ∈ ps, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ ps, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (h : (labelDecide ps budget).1 = .sat) :
    SSat ((ps.map LPart.toConstraint).toFinset)
```

"Constructed and checked" is literal.  `searchLabel` returns a model only from a LEAF at which
`modelChecks` — at most one part carries the label, and the whole carries it iff exactly one
does, read off every partition directly — returned `true`; `searchLabel_checks` says so, and
`decideLabel_sat` turns it into `LModels`.  The label-wise assembly is
`Rowpartition.satisfiable_iff_forall_label` (Basic.lean), with `bmodels_false_of_not_mem` for
every label the system does not mention.

### Soundness

```lean
/-- **LAYER (iii) IS SOUND.**  A refutation means the system has NO model. -/
theorem labelDecide_refuted_unsat {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart}
    {budget : Nat} (hnd : ∀ p ∈ ps, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ ps, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    {l : Lbl} {a : Nat} {w : String} (h : (labelDecide ps budget).1 = .refuted l a w) :
    ¬ SSat ((ps.map LPart.toConstraint).toFinset)
```

resting on the two halves the coordinator asked for:

```lean
/-- **The soundness of one propagation step.**  At a model, `forcedBy` never refuses, and
every bit it forces is the model's. -/
theorem forcedBy_sound (hag : Agree bits b) (hsat : LSat b l p) :
    forcedBy l bits p = some (fbBits l bits p) ∧ ∀ w ∈ fbBits l bits p, b w.1 = w.2.1

/-- **The refutation is real.**  A search that ends `none` WITHOUT being cut short has ruled
out every assignment extending the bits it started from. -/
theorem searchLabel_sound (hm : LModels b l ps) {vs : List Nat} :
    ∀ (d : Nat) {bits nodes budget n},
      searchLabel ps l vs d bits nodes budget = (none, n, false) → ¬ Agree bits b
```

`forcedBy` is `Constraints.checkLabel`'s five rules with their five message strings; the
content of its soundness is the same as `Rowpartition.LabelAlgo.algoWrite_forced`, re-proved
against the vocabulary the CODE reads (an `SSet` of abstract parts as a list) rather than the
relational `Constraint`.  `Loop/Json.lean`'s own `checkLabel` is not re-used because it does
not hand the derived bits back.

### The label-wise decomposition, and the bridge to it

`Rowpartition.satisfiable_iff_forall_label` (`Basic.lean`, pre-existing) is exactly the
decomposition: `(∃ rho, Models rho G) ↔ ∀ l, ∃ b, BModels b l G`, with the finite-support
reconstruction in the `←` direction; `bmodels_false_of_not_mem` covers a label the system does
not mention.  What S2 adds is the bridge from the loop's own shadow:

```lean
/-- **The loop's Boolean shadow IS `Rowpartition.BSat`.** -/
theorem lsat_iff_bsat {L : List Lbl} (hcoh : LblCoh L) {p : LPart} {l : Lbl} (hl : l ∈ L)
    (hnd : p.rhs.abstr.elems.Nodup) (hmem : ∀ x ∈ p.rhs.conc.elems, x ∈ L) (b : Nat → Bool) :
    LSat b l p ↔ BSat b l.n p.toConstraint

/-- `BSat` in counting form: at most one part carries the label, and the whole carries it iff
exactly one does. -/
theorem bsat_iff_count (b : Var → Bool) (lab : Label) (c : Constraint) :
    BSat b lab c ↔
      (c.vars.countP b + (if lab ∈ c.conc then 1 else 0) ≤ 1 ∧
       b c.lhs = decide (c.vars.countP b + (if lab ∈ c.conc then 1 else 0) = 1))
```

### Layer (i): the new death, and why no S1 theorem moved

```lean
/-- With layer (i) off, `stepS` IS `step`. -/
theorem stepS_of_flag_off {s : State} (h : s.flags.rowSoundBare = false) : stepS s = step s

/-- **`stepS` can only turn a continuation into a DEATH.** -/
theorem stepS_continue {s s' : State} (h : stepS s = .continue s') : step s = .continue s'

/-- **THE NEW DEATH IS A REFUTATION.**  Layer (i) refuses only when a BARE definition of the
dequeued variable carries a different concrete row from the one being installed — and a system
with two different bare rows for one variable has no model. -/
theorem bare_death_refutes {L : List Lbl} (hcoh : LblCoh L) {s : State} {r : LPart}
    {rest : PQueue} (hdq : s.incm.dequeue = some (r, rest))
    (hra : r.rhs.abstr.isEmpty = true) (hrn : r.rhs.conc.elems.Nodup)
    (hrL : ∀ x ∈ r.rhs.conc.elems, x ∈ L)
    {p : LPart} (hp : p ∈ s.proc.elems ++ rest.elems) (hlhs : p.lhs = r.lhs)
    (hpa : p.rhs.abstr.isEmpty = true) (hpn : p.rhs.conc.elems.Nodup)
    (hpL : ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hne : p.rhs.conc.eqv r.rhs.conc = false) :
    ¬ SSat (sys s)
```

`bare_death_refutes` is `Loop/Sound.lean`'s `bare_refutes` at the loop's vocabulary, and
`bareExact_error` names the offending definition out of the fold.  **`stepS_continue` is why
no existing theorem needed a new hypothesis**: `step_noLoss_all`, `step_noLoss_or`,
`step_queueHygiene`, `step_died_refutes` and everything built on them apply to `stepS` through
it, unchanged.  (S1's death-site census gains one entry — the layer-(i) `ensureExactly` — and
it lands on the SAME message as `ensureSuperset`, S1 death site 7, which
`Loop/Reject.lean` already classifies as a refutation.)

### The seeds, in the kernel

Every line below is checked by `rfl` — the kernel re-runs the loop and the decision.

| seed | shipped loop | layer (iii) |
|---|---|---|
| `MIN1` | `isSolvedB (runS (seedS0 {} min1Seed 300) 200) = true` — **the loop ACCEPTS it** | `(labelDecide (seedQ min1Seed 300).elems 200000).1 = .refuted (Lbl.repro 35) 305 (searchReason 2)` |
| `MIN2` | `… = true` — accepted at this id base | `… = .refuted (Lbl.repro 17) 304 (searchReason 1)` |
| `SURV1` | `… = true` — accepted | `… = .refuted (Lbl.repro 20) 303 (searchReason 1)` |
| `NP01` | accepted | `(labelDecide (seedQ npSeed 300).elems 200000).1 = .sat`, and `isSolvedB (runS (seedS0 rsFlags npSeed 300) 400) = true` |

with

```lean
def searchReason (n : Nat) : String :=
  "no assignment of this field to the parts satisfies every partition (complete search, " ++
  toString n ++ " cases; unit propagation alone does not see it)"
```

The labels and the case counts are the COMPILER's: `MIN1` at `l35` in 2 cases, `MIN2` at `l17`
in 1, `SURV1` at `l20` in 1 — the same three labels the S1 review names and the same three
messages Part A measured on the compiler (§3.1).

**One thing the kernel cannot check here, and why.**  The facts above are about `runS` and
`labelDecide`, not about `solveSeed`: the early label check `solveSeed` calls
(`Loop/Json.lean`'s `checkLabel`) is compiled by WELL-FOUNDED recursion and does not reduce
definitionally, so no `rfl` can pass through it.  That is a pre-existing property of the L1
model — `Loop/Solve.lean`'s own seed instantiations go through `run` for the same reason — and
it costs nothing: the loop and the decision are exactly the two halves the theorems are about,
and the end-to-end verdict is what the L2 differential measures on 2.36 M real solves.

## B4. Gates

### B4-0 Build and audit

| gate | command | result |
|---|---|---|
| the whole development builds | `lake build Rowpartition` | **Build completed successfully (861 jobs)** — 859 before S2, +2 for the two new modules |
| axiom audit | `lake env lean Audit.lean` | **Rowpartition theorems audited: 3888; declarations using a non-standard axiom: 0** (3804 before S2, so S2 adds 84 audited theorems and no axiom) |
| the executable | `lake build looptrace` | **Build completed successfully (1664 jobs)** (1662 before) |
| `#print axioms` over every new declaration | scratch `Axioms.lean`, 43 declarations | **43 of 43 use only `[propext, Classical.choice, Quot.sound]`** — 38 all three, 2 `[propext, Quot.sound]`, 3 `[propext]`.  **0 non-standard.** |
| `sorry` / `axiom` / `partial` / `native_decide` / `unsafe` / `opaque` / `implemented_by` / `admit` / `#exit` in the two new modules | grep | **0 occurrences, both files** |
| pre-existing Lean modules | `git diff --stat -- tracker/lean/` | **`Main.lean` +23/−3, `Replay.lean` +36/−3, `Seed.lean` +23/−3, `State.lean` +18/−1 — four DRIVER files, flag plumbing, the `senv` parse and the flag-guarded calls; plus `Rowpartition.lean` +26 (two imports and their doc entries) and `README.md` +2.  NO theorem module touched, no existing theorem changed or weakened.** |
| `core/test` on the main checkout, flags OFF | `sbt -batch -J-Xmx3g core/test` | **Total 914, Passed 913, Failed 1** — the known `Constraints.disjunction sound` starvation, the same one Part A §2 records, and `TestLoopTrace` 714/714 inside it.  This is the whole suite AFTER the `senv` record and the `flagMap` entries, so neither moved anything. |

### B4-1 The L2 differential

The compiler side is the eight-group corpus trace generated ON THE MAIN CHECKOUT with the
patch applied (§B1), the model side is `looptrace --replay`, and the comparison is
`tracker/tools/looptrace-diff.py --segments --per-thread`, exactly as
`tracker/tools/looptrace-corpus.sh` runs them; only the compiler half is skipped, because the
traces already exist.

**Flags OFF — every group agrees, segment for segment.**

| group | segments | agree | skip | hashdiff | eqdiff | model |
|---|---|---|---|---|---|---|
| boot | 54 199 | **54 199** | 0 | 0 | 0 | 0.96 s |
| top | 92 673 | **92 673** | 0 | 0 | 0 | 1.9 s |
| Ai | 83 942 | **83 942** | 0 | 0 | 0 | 19.4 s |
| shouldfail | 56 032 | **56 032** | 0 | 0 | 0 | 1.1 s |
| bugs | 54 235 | **54 235** | 0 | 0 | 0 | 0.96 s |
| guide | 54 244 | **54 244** | 0 | 0 | 0 | 0.96 s |
| shouldfail-controls | 54 739 | **54 739** | 0 | 0 | 0 | 1.0 s |
| incomplete | 1 905 366 | **1 905 366** | 0 | 0 | 0 | 85.5 s |
| **total** | **2 355 430** | **2 355 430** | **0** | **0** | **0** | |

which is the L2 baseline unchanged — the model with the flags off is the model that was there.

**Flags ON** (`--flags=rowsound` on the model, `-Dermine.rowSound=true` on the compiler):
the FIRST run disagreed on one segment (see below); after the one-token fix it is:

| group | segments | agree | skip | hashdiff | eqdiff |
|---|---|---|---|---|---|
| boot | 54 199 | **54 199** | 0 | 0 | 0 |
| top | 92 673 | **92 673** | 0 | 0 | 0 |
| Ai | 83 942 | **83 942** | 0 | 0 | 0 |
| shouldfail | 56 030 | **56 030** | 0 | 0 | 0 |
| bugs | 54 235 | **54 235** | 0 | 0 | 0 |
| guide | 54 244 | **54 244** | 0 | 0 | 0 |
| shouldfail-controls | 54 739 | **54 739** | 0 | 0 | 0 |
| incomplete | 1 905 366 | **1 905 366** | 0 | 0 | 0 |
| **total** | **2 355 428** | **2 355 428** | **0** | **0** | **0** |

The flags-ON corpus has **two fewer solves in `shouldfail`** (56 030 against 56 032) for a
reason worth naming: `inf04_except_recursive.e` is refuted EARLIER, so two solves that used to
follow it in that session never happen.  That is the fix working, and the model reproduces it
— the compiler's trace and the model's replay have the same 56 030 segments.

### B4-2 `TestLoopTrace` with the flag forwarded

```
=== TestLoopTrace flags OFF
[loop model trace] 714 solves (19 seed x 6 bases + 600 generated); 714 segments; 714 agree;
                   #summary segments=714 replayed=714 skipped=0 hashdiff=0 eqdiff=0
                            nonpart=0 rejected=36 fuel=0
[loop model trace] control (id base +1): 53 of 714 disagree; control (--flags=nongen): 65 of 714

=== TestLoopTrace -Dermine.rowSound=true
[loop model trace] rule flags forwarded to both sides: -Dermine.rowSound=true  ->  --flags=rowsound
[loop model trace] 714 solves (19 seed x 6 bases + 600 generated); 714 segments; 714 agree;
                   #summary segments=714 replayed=714 skipped=0 hashdiff=0 eqdiff=0
                            nonpart=0 rejected=36 fuel=0
[loop model trace] control (id base +1): 53 of 714 disagree; control (--flags=nongen): 65 of 714
```

**Identical in every figure, `rejected=36` included** — and the first line of the second run is
the point: the property now says out loud which flag it forwarded and which model token it
used, so a run under `-Dermine.rowSound=true` really tests that configuration on both sides.
The positive control still detects an injected divergence at 53 of 714 segments, so the
comparison has not gone slack.

`TestLoopTrace.flagMap` gained the seven S2 entries (`ermine.rowSound` → `rowsound`, and each
layer's property → `rsbare` / `rssat` / `rsdecide` and their `no…` forms), so
`sbt -Dermine.rowSound=true "core/testOnly *TestLoopTrace"` now really tests the configuration
it names on BOTH sides.  Before this the property would have run the compiler with the flag and
the model without it — which is exactly the silent-default trap the L4 review (F2) put the map
there to close.  **Answer to "does the model's `--flags` need a new token": yes, and there are
now eight** (`rowsound`, `rsbare`, `rssat`, `rsdecide`, `norsbare`, `norssat`, `norsdecide`,
and `rsbudget=<n>`), all in `Loop/Main.lean`'s `applyFlag`.

### B4-3 The differential harness

`replay-only.sh` (scratch) is `looptrace-corpus.sh`'s SECOND half verbatim — `looptrace
--replay` on the trace, then `looptrace-diff.py --segments --per-thread` — with the compiler
half skipped because §B1's traces already exist.  Both sides read the SAME trace file, so the
segment indices line up by construction, and each group's raw trace is deleted after its
replay (disk).

## B5. What could NOT be done — Part B, side by side

| asked for | done | not done, and why |
|---|---|---|
| the L2 differential with the flags ON, `0 skipped / 0 hashdiff / 0 eqdiff` | §B4-1 | the reason it can be run AT ALL is §B1's `senv` record: the trace previously carried only the COUNT of environment facts, and the one corpus solve that needs them (`shouldfail/inf04`) would otherwise have made the model take a branch the compiler did not.  That is a Scala change beyond Part A's three files, and it is declared rather than slipped in. |
| a kernel `rfl` for the seeds END TO END (`solveSeed`) | the loop (`runS`) and the decision (`labelDecide`) are checked in the kernel; the `solveSeed` composition is not | `Loop/Json.lean`'s `checkLabel` — the early label check `solveSeed` calls — is compiled by WELL-FOUNDED recursion and does not reduce definitionally, so no `rfl` passes through it.  Pre-existing (`Loop/Solve.lean`'s own seeds go through `run` for the same reason), and the end-to-end verdict is what the differential measures on 2.36 M solves. |
| the model's propagation to be the compiler's, instruction for instruction | the same five rules, the same five messages, the same fixpoint and the same verdict | the compiler's propagation is WORKLIST-driven, the model's is PASS-based (like `Loop/Json.lean`'s `checkLabel`, which transcribes the Scala `checkLabel`).  They can differ in WHICH partition is blamed for a clash and hence in the message; nothing compares that — `looptrace-diff.py`'s `KEEP` is `step learn in inpart sat solve`, and a refutation emits no record on either side.  Stated in the module header, not buried. |
| `bareExact` to fold over the same collection as `makeConcrete` | it folds over the PARTITIONS in queue order; `makeConcrete` folds over the `SSet` of right-hand SIDES | the set of right-hand sides checked is the same and the check is a conjunction, so the VERDICT is identical; only which of several failing definitions supplies the message can differ.  Chosen because it makes `bareExact_error` a straightforward fold induction instead of an `SSet.ofList`/`filter`/`map`/`concat` membership chain. |
| layer (ii) mirrored with its own theorem | it is `labelClash` on `ps`, and its soundness is the pre-existing `Rowpartition.refute_saturated_sound` | what is NOT proved here is the relation between the MODEL's saturated set (`s.proc.elems` at `.done`) and the compiler's `q.expand` — S1 already states that the two agree only through the L2 differential, not through a theorem, and S2 does not close that gap.  Layer (ii) is therefore evidence-backed (Part A §3.2: it catches 384 of the 404) and cited-sound, not newly proved. |

## B6. Hygiene (Part B)

* **No commit.**  The main checkout's working tree carries S2's changes and nothing else;
  `tracker/LOOP-MODEL-PLAN.md` and `tracker/LOOP-MODEL-HANDOFF.md` were already modified by
  the orchestrator and were touched only in S2's own row (additively, at the end).
* `tracker/lean/Rowpartition/CutSearch.lean` is still NOT in the root import list, as
  `ROW-CONSTRAINT-STATE.md` requires.
* No `lake exe cache get`, no new `require`, no new Lean project, nothing under
  `~/research/leanwork` touched.
* Scratch is `/home/dmitry/.claude/jobs/880c725d/tmp/S2/`; traces are gzipped and each group's
  raw copy is deleted after its replay.
* One JVM at a time, `-XX:ActiveProcessorCount=2`, long runs under `setsid nohup` with a log.

**A bug the differential caught, and it is worth recording.**  The first flags-ON run
disagreed on exactly ONE segment of 2 355 430 — `shouldfail/inf04_except_recursive.e`, the one
solve in the whole corpus whose input mentions a variable the `SubstEnv` already binds:

```
class length+  1
  [length+] seg 55292  inferImplicitBindingTypes  core/examples/shouldfail/inf04_except_recursive.e(1:1)
      lean : step  inferImplicitBindingTypes  learn  ^free339512 <- (^free339510,Shouldfail.Inf04.a)  incm=0  proc=0
      scala: <none>
```

The compiler refuted before the loop and wrote nothing; the model ran the loop.  The cause was
NOT the decision: `Loop/Main.lean`'s STREAMING replay loop keeps its own record dispatch, and
`senv` had been added to `Replay.lean`'s `parseSegments` (used by the batch path) and not to
it, so the streaming path threw the environment facts away.  One token later the two agree.
That is the differential doing its job on the single segment in 2.36 M where it could.

## B7. How to re-run Part B

```bash
cd ~/research/ermine/ermine-scala/tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition          # 861 jobs
lake env lean Audit.lean         # 3888 theorems / 0 non-standard axioms
lake build looptrace             # 1664 jobs
lake env lean <scratch>/Axioms.lean   # 43 declarations, all [propext, Classical.choice, Quot.sound]

# the corpus traces (compiler side), from the repo root
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
trace-only.sh <out-off>                          # flags off
trace-only.sh <out-on> -Dermine.rowSound=true    # flags on

# the differential (model side), for each
replay-only.sh <out-off> <rep-off>
replay-only.sh <out-on>  <rep-on> --flags=rowsound

# the property, both ways
sbt -batch -J-Xmx3g "core/testOnly *TestLoopTrace"
sbt -batch -J-Xmx3g -Dermine.rowSound=true "core/testOnly *TestLoopTrace"
```

`trace-only.sh` and `replay-only.sh` are the two halves of `tracker/tools/looptrace-corpus.sh`,
split so a trace can be replayed twice without recompiling the corpus; both live in the
scratch directory named in Part A §10.

## B8. Files, with line counts

Corrected 2026-09-06 from `git diff --numstat` (S2 review **V-6**: the first version of this
table was hand-kept and drifted).  Figures below INCLUDE the post-review changes of §P1–§P5.

| file | +/− | status |
|---|---|---|
| `core/src/main/scala/…/Constraints.scala` | **+405 / −9** | layers (i) and (iii), the flags, the per-solve cap |
| `core/src/main/scala/…/Subst.scala` | **+119 / −4** | layers (ii) and (iii) in `solve`, the live input, the no-verdict warning |
| `core/src/main/scala/…/RowTrace.scala` | **+84 / −1** | the `rsound` and `senv` records |
| `core/src/test/scala/…/loopmodel/TestLoopTrace.scala` | **+36 / −8** | the S2 `flagMap` entries and the numeric-flag forwarding |
| `tracker/repro/satterm/SatTermRepro.scala` | **+98 / −6** | the seed `env` block, the two-solve run, the `env` mode |
| `tracker/repro/satterm/seeds/unsat/ENV-LINK.json` | **3 (new)** | the review's third mechanism, tracked |
| `tracker/repro/satterm/seeds/unsat/README.md` | **+8** | the `env` block and the new seed |
| `tracker/lean/Rowpartition/Loop/Decide.lean` | **349 (new)** | the three layers, executable |
| `tracker/lean/Rowpartition/Loop/NoFalseAccept.lean` | **1 149 (new)** | the theorems |
| `tracker/lean/Rowpartition/Loop/State.lean` | **+21 / −1** | five `Flags` fields and `toStr` |
| `tracker/lean/Rowpartition/Loop/Main.lean` | **+25 / −3** | nine `--flags` tokens, `senv` in the streaming loop |
| `tracker/lean/Rowpartition/Loop/Replay.lean` | **+33 / −3** | the `senv` record and `Segment.envFacts` |
| `tracker/lean/Rowpartition/Loop/Seed.lean` | **+21 / −3** | layers (ii)/(iii) in `solveSeed`, `runS` for (i) |
| `tracker/lean/Rowpartition.lean` | **+26** | the two imports and their doc entries |
| `tracker/lean/README.md` | **+3 / −1** (the two rows and the V-7 headline correction) | two additive rows |
| `tracker/ROW-CONSTRAINT-STATE.md` | **+76** | one additive dated section |
| `tracker/LOOP-MODEL-PLAN.md` / `LOOP-MODEL-HANDOFF.md` | **+40 / +36** | the S2 row and the orchestrator's own edits |
| `tracker/loopmodel/S2-DESIGN.md` | **255 (new)** | the design note |
| `tracker/loopmodel/S2-FIX.md` | **1 229 (new)** | this report |
| | **whole change: `git diff --numstat` = +1 031 / −39, plus 2 985 lines of new files** | |

**Four pre-existing Lean modules touched, all DRIVER files** (`State`, `Main`, `Replay`,
`Seed`): **+100 / −10**.  No theorem module touched, no existing theorem changed, and none
gained a hypothesis — `runS_of_flag_off` LOST one (§P4, V-9).

## B9. The chain, end to end

What S1 and S2 together now say about one `Subst.solve`, with `-Dermine.rowSound.decide=true`
and its budget intact:

1. **If the solve REJECTS**, the input system has no model — S1's `run_rejects_unsat` /
   `solve_sound` (B), with S2's `bare_death_refutes` covering the one new death and
   `labelDecide_refuted_unsat` covering the new diagnostic.
2. **If the solve RETURNS**, the constraints it was given (with the environment applied) HAVE
   a model — S2's `solve_noFalseAccept`.  This is the statement the type checker actually
   needs and the one S1 could not make.
3. **And then**, because (2) supplies `SSat (sys s₀)`, S1's `run_noLoss` and `run_models`
   apply: the output system entails every input constraint and every model of the output is a
   model of the input.

The gap that remains after all of it is the same one S1 named and S2 does not close:
`Subst.reduce`, which runs AFTER the loop, is not modelled, and it is where `PANIC-1`'s
internal error lives.  With layer (i) on, `PANIC-1` is refuted before `reduce` ever sees it
(Part A §3.1) — but that is a measurement on one seed, not a theorem about `reduce`.

## B10. What the model costs

The replay's own wall time, same machine, same traces, model side only:

| group | flags OFF | flags ON |
|---|---|---|
| boot | 0.96 s | 1.24 s |
| top | 1.88 s | 2.26 s |
| Ai | 19.4 s | 20.9 s |
| shouldfail | 1.12 s | 1.41 s |
| bugs / guide / sf-controls | 0.96 / 0.96 / 1.02 s | 1.24 / 1.24 / 1.31 s |
| incomplete | 85.5 s | 95.3 s |

about **+12 %** with all three layers on, which is the decision running on every segment; with
them off the model is the shipped one and `TestLoopTrace` takes 10.8 s against the pre-S2
10.5 s, i.e. inside the noise.  Nothing here is a compiler cost — that is Part A §5.

---
---

# POST-REVIEW — 2026-09-06, after `tracker/loopmodel/S2-REVIEW.md` (ADVANCE)

The review's verdict was ADVANCE with thirteen findings, and it named three prerequisites for
ever flipping the default.  This section records what changed, old value against new.  **The
flags still DEFAULT OFF**; nothing here is an adoption.

## P1. V-1 — the chain to S1 is now a THEOREM, not prose

*Old:* `solve_noFalseAccept` concluded `SSat (q ∪ E)`; §B9 argued in three prose points that
S1's `run_noLoss` then applies.  The review was right that the restriction step
`SSat (q ∪ E) → SSat q` and the composition were nowhere in Lean.

*New:* three declarations in `Loop/NoFalseAccept.lean` §9b.

```lean
/-- Satisfiability is antitone: a model of a bigger system models every subsystem. -/
theorem ssat_of_subset {G G' : System} (hsub : G ⊆ G') (h : SSat G') : SSat G

/-- The queue's constraints are part of the live input. -/
theorem sys_subset_live {q : PQueue} {envFacts : List LPart} {su : Sup} {tr : List String}
    {fl : Flags} {ns : Names} {site : String} {z : Nat} :
    sys (initState q su tr fl ns site z) ⊆
      (((q.elems ++ envFacts).map LPart.toConstraint)).toFinset

/-- **THE CHAIN.**  With layer (iii) on and its budget intact, a solve that ACCEPTS is
FAITHFUL: the loop lost nothing, every model of the output system is a model of the input
system, and the two are satisfiable together. -/
theorem solve_accepted_faithful {L : List Lbl} (hcoh : LblCoh L)
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup} {tr : List String} {z : Nat}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeed fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED")
    (n : Nat) (hw : Wf (initState q su1 tr fl ns site z))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hb : RunSupOk n (initState q su1 tr fl ns site z))
    {s' : State}
    (hres : run (initState q su1 tr fl ns site z) n = .solved s' ∨
            run (initState q su1 tr fl ns site z) n = .outOfFuel s') :
    NoLoss (sys (initState q su1 tr fl ns site z)) (sys s') ∧
    (∀ rho, SModels rho (sys s') → SModels rho (sys (initState q su1 tr fl ns site z))) ∧
    (SSat (sys (initState q su1 tr fl ns site z)) ↔ SSat (sys s'))
```

The hypotheses after `hacc` are S1's own, exactly as `solve_sound` carries them.  §B9's prose
argument is now a corollary of this rather than a substitute for it.

## P2. V-2 + adoption prerequisite (1) — the environment-fact path is a TRACKED gate

*Old:* `SatTermRepro.runCapped` built a fresh `SubstEnv` per run, so all 38 400 report runs and
all 6 300 of the reviewer's had `facts = 0`.  Layer (iii)'s environment path — the reason
`envFacts`, the `senv` record and the theorem's `E` exist — was exercised by ONE corpus solve
and by no gate at all; the `VarT` link arm and the transitive closure by nothing.

*New:*

* **The seed format takes an `"env"` block**: a FIRST solve, run in the SAME `SubstEnv`, in the
  same shape as `"cons"`.  `Seed` gains `env`, `Sys` gains `envParts`, and `runCapped` solves
  it before the solve under test.  With no `"env"` key nothing changes, so every existing seed
  and gate is untouched.
* **`tracker/repro/satterm/seeds/unsat/ENV-LINK.json`** is the review's THIRD mechanism as a
  tracked seed: `env` binds `v4 := v0` (a `VarT` link, no concrete row anywhere), then
  `v3 <- (v0,v4)`, `v3 <- ((|l0|))`.  Under the binding `rho v0 = rho v4`, and they are
  disjoint parts of `v3`, so both are empty and `rho v3 = ∅` against `rho v3 = {l0}`.

  | | shipped | `-Dermine.rowSound=true` |
  |---|---|---|
  | `run.sh sweep json:…/ENV-LINK.json 300 319` | **SOLVED 20/20** | **REJECTED 20/20**, at `l0` |

  The shipped residual says it plainly: `Part(ConcreteRho(l0), List(v4^302, v4^302))` —
  `{l0} <- (v4, v4)`, false for every `v4`, published unchecked.
* **`run.sh env`** is the reviewer's `EnvProbe` as a tracked nine-case mode: concrete bindings,
  alias chains, a pure `VarT` link, a case split under a binding, and the two bare-row cases,
  each with the verdict layer (iii) SHOULD give.

  | | cases | differing from the flag-ON expectation |
  |---|---|---|
  | shipped | 9 | **4** — and each of the four is an unsatisfiable system the compiler ACCEPTS |
  | `-Dermine.rowSound=true` | 9 | **0** |

  The four satisfiable cases (`SAT-1`…`SAT-4`) are SOLVED at both settings: **no false
  rejection on the path the theorem is about.**  The mode exits non-zero on a difference only
  when `rowSound.decide` is on, so it is meaningful to run both ways.

## P3. V-12 + V-3 + adoption prerequisite (2) — a per-SOLVE cap, and a VISIBLE signal

*Old:* one budget, per LABEL, so a solve's worst case was `#labels × 0.2 s` (the reviewer
measured 0.20 s to spend 200 000 nodes on one label, and the budget really fires on a
10-pigeon pigeonhole).  Exhaustion — the one condition under which the theorem says nothing —
was visible only through `GenRules.rowSoundBudgetHits`, which the compiler never reads, and a
`rsound … budget` trace record needing `-Dermine.rowTrace`.

*New:*

* `-Dermine.rowSound.solveBudget=<n>`, **default 1000000**, caps the decision nodes ONE SOLVE
  may spend summed over its labels.  `labelDecide` threads the spend and never lets one label
  claim more than the solve has left; a label reached after the cap is `NoVerdict` like any
  other exhaustion.  Mirrored in the model (`Flags.rowSoundSolveBudget`, `decideFrom`, the
  `--flags=rssolvebudget=<n>` token).
* **A no-verdict now prints a line on stderr**, naming the site and the field:

  ```
  warning: the row soundness check gave NO VERDICT at <loc> (field 'l': <reason>);
           this solve is accepted on the shipped rules alone
  ```

  It cannot fire at the shipped defaults, because the whole check is off.
**Both caps, and the warning, measured directly** (`seeds/unsat/SURV1.json`, bases 300–301):

| configuration | verdict | stderr |
|---|---|---|
| `decide=true` (defaults) | REJECTED 2/2 | — |
| `decide=true budget=0` | **SOLVED 2/2** | `warning: … NO VERDICT … (field 'Repro.l20': search budget exhausted after 1 decisions); this solve is accepted on the shipped rules alone` |
| `decide=true solveBudget=0` | **SOLVED 2/2** | `warning: … NO VERDICT … (field 'Repro.l20': the solve's decision budget of 0 nodes was spent before this field was decided); …` |

and where the per-solve cap actually BITES — three disjoint 10/9 pigeonholes, one per label,
each of which exhausts the per-label budget (the reviewer's `php09` × 3, scratch):

| per-label | per-solve | solve time |
|---|---|---|
| 200 000 | 100 000 000 (effectively uncapped) | **1 188 ms** |
| 200 000 | 200 000 (the default's shape, one label's worth) | **732 ms** |

The guarantee is the arithmetic one: the nodes a solve spends are at most `solveBudget`,
where before they were at most `#labels × budget`.  On the corpus neither cap has ever fired.

* **V-3**: `TestLoopTrace` gains a `numericFlags` table (`ermine.rowSound.budget` →
  `rsbudget=<v>`, `.solveBudget` → `rssolvebudget=<v>`) and forwards them to the child JVM and
  to the model.  *Old:* `-Dermine.rowSound.budget=1 "core/testOnly *TestLoopTrace"` ran the
  compiler at budget 1 and the model at 200 000, silently — precisely the trap `flagMap`
  exists to close.

## P4. V-8, V-9, V-13 — the small ones

| finding | old | new |
|---|---|---|
| **V-8a** | the `RowTrace` FORMAT block said the `budget` record's detail is `<label>\t<budget>` | the code and the doc now agree: `<label>\t<cause>\t<reason>`, `cause` ∈ `budget`, `checkfail` |
| **V-8b** | `rowSoundBudgetHits` counted BOTH no-verdict causes, so a counter named for the budget could absorb a propagator bug | `LabelNoVerdict` carries `exhausted`; `rowSoundBudgetHits` counts budget exhaustion and the new `rowSoundCheckFails` counts the fail-safe |
| **V-9** | `runS_of_flag_off` carried an undischarged `hstep` hypothesis | discharged with the pre-existing `Loop/RefineLearn.lean:1472` `step_flags`; the theorem is now unconditional |
| **V-13a** | the comment said "the FIRST refutation in label order"; `labels` is a `Set[Name]` and the order is HASH order | documented in `Constraints.labelDecide` and in the model's `mentionedLabels`: it decides only WHICH of several refuting labels is reported, never whether the system is refuted |
| **V-13b** | `firstAt`/`firstWhy` persist across search branches | documented in `Constraints.decideLabel`: the LABEL cannot move (it is fixed by the caller's loop), only the blamed VARIABLE, which `rowUnsat` uses to prefer one input `Part` over another with a real fallback either way.  Resetting per branch would pick a different arbitrary clash, not a better one |

## P5. V-4 … V-7, V-10, V-11 — the prose

* **V-4**: `core/test` is **913/914 on my runs and 912/914 on the reviewer's**.  The extra
  failure is `Legends & presentations.extra args are ignored` (`TestLegend`, a date-range
  formatting property in `writers` with a random ScalaCheck seed) — a flake, unreachable from
  `Constraints`/`Subst`/`RowTrace`.  **The suite has at least two flaky properties**; neither
  figure should be quoted as a constant.
* **V-5**: §3.1's shipped column corrected — `SURV1` **20/20**, `FALSE-ACCEPT-1` **20/20**,
  `FALSE-ACCEPT-2` **4/20**, all re-measured here rather than quoted.
* **V-6**: §B8's line counts replaced with `git diff --numstat` (§P6).
* **V-7**: `tracker/lean/README.md`'s S1 headline counts were still 859 / 3804-0 / 1662; now
  861 / 3888-0 / 1664, and the two S2 rows' line counts are current.
* **V-10**: `tracker/ROW-CONSTRAINT-STATE.md` now names all THREE provisos — the budget, the
  opaque `SubstEnv` binding, and the skolem/existential reading of "satisfiable" — and carries
  the review's third false-acceptance mechanism in the bug list.
* **V-11**, worth saying plainly: **the L2 differential is blind to layer (iii)'s verdicts
  except through segment truncation.**  `looptrace-diff.py`'s `KEEP` is
  `step learn in inpart sat solve`; the `rsound` and `senv` records are not compared, and a
  refutation emits no record on either side.  "2 355 428 agreeing segments with the flags ON"
  means **the two sides die in the same places**, not that they refute the same label with the
  same reason.  What pins THAT is the seed cross-check, and it is exact: the compiler's
  messages on `MIN1`/`MIN2`/`SURV1` carry "complete search, 2 / 1 / 1 cases", matching
  `min1_decide_refutes` / `min2_decide_refutes` / `surv1_decide_refutes`'s `searchReason 2 / 1
  / 1` in the kernel.

## P6. Post-review gates

| gate | command | result |
|---|---|---|
| the whole development builds | `lake build Rowpartition` | **861 jobs, success** |
| axiom audit | `lake env lean Audit.lean` | **3 898 theorems audited; 0 using a non-standard axiom** (3 888 before the post-review round: the chain theorem and the `decideFrom` lemmas) |
| the executable | `lake build looptrace` | **1 664 jobs, success** |
| `#print axioms`, now 50 declarations | scratch `Axioms2.lean` | **50 of 50 standard — 0 non-standard** |
| `core/test` | `sbt -batch -J-Xmx3g core/test` | **Total 914, Passed 913, Failed 1** — the known `Constraints.disjunction sound` starvation, and nothing else (the reviewer's second failure is the `writers` date flake, §P5) |
| `TestLoopTrace`, flags OFF | `sbt -batch "core/testOnly *TestLoopTrace"` | **714 solves; 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0 rejected=36**; controls 53/714 and 65/714 |
| `TestLoopTrace`, `-Dermine.rowSound=true` | forwarded to both sides | `rule flags forwarded to both sides: -Dermine.rowSound=true  ->  --flags=rowsound`; **714/714 agree**, every figure identical to the OFF run |
| the env gate, both ways | `run.sh env` | **shipped: 9 cases, 4 differ (the bug, three of them previously unrecorded); ON: 9 cases, 0 differ.  PASS** |
| `ENV-LINK.json` × 20 bases, both ways | `run.sh sweep json:…/ENV-LINK.json 300 319` | **shipped SOLVED 20/20; ON REJECTED 20/20 at `l0`.  PASS** |
| the six older `seeds/unsat/` seeds, shipped counts re-measured | `run.sh sweep` | `MIN1` 20/20, `FALSE-ACCEPT-1` 20/20, `MIN2` 4/20, `FALSE-ACCEPT-2` 4/20, `SURV1` 20/20 SOLVED; `PANIC-1` panics.  **PASS** (V-5) |
| both caps and the warning | §P3 | **PASS** |
| V-3, the numeric flags really forwarded | `sbt -Dermine.rowSound=true -Dermine.rowSound.budget=1 -Dermine.rowSound.solveBudget=7 "core/testOnly *TestLoopTrace"` | `rule flags forwarded to both sides: -Dermine.rowSound=true -Dermine.rowSound.budget=1 -Dermine.rowSound.solveBudget=7  ->  --flags=rowsound,rsbudget=1,rssolvebudget=7`, **714/714 agree**.  Before this change the two numbers went to the compiler alone. |

Not re-run after the post-review round, and stated as such: the eight-group **L2 differential**
(§B4-1) and the **`.ei` sweep** (§8).  Neither can have moved — the post-review Scala change is
confined to layer (iii)'s budget bookkeeping and a stderr line that cannot fire with the flags
off, the flags-off path is untouched, and `TestLoopTrace` (which exercises the model against
the compiler on 714 solves at both settings) is green.  A reviewer who wants them re-run has
`replay-only.sh` and §B7.

