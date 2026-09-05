# B1 — the `makeEmpty` self-propagation panic: the Scala fix and its gates

**Status: PARTS A AND B COMPLETE, 2026-09-04.  No commits on either side.**  Part A was gated
in the worktree `ermine-scala-wt-b1` (branch `makeempty-self-fix`); Part B — the Lean mirror,
the trace property and the replays — is in the MAIN checkout, §5 and §6.

Found by the L5 witness hunt (`tracker/loopmodel/L5-TERMINATION.md` §0, root-caused by
`L5-REVIEW.md` §6.2 (the two binding steps, traced), §6.3 (the root cause) and §6.4 (why `Subst.scala:183` is the wrong layer); findings F3/F4 are tabulated in its §9).  A SATISFIABLE three-constraint system makes the shipped
`Subst.solve` die with `panic: reinstantiated type v6 to ConcreteRho(-,Set()) but it was
already bound to ConcreteRho(-,Set())` at 11 of 100 id bases: acceptance of a valid program
depended on how many type variables the compiler happened to allocate before the solve.

## 1. The bug and the diff

`Constraints.makeEmpty`'s `aux` propagated the "is empty" fact to EVERY variable of a
right-hand side, INCLUDING the variable being emptied.  So a self-referential definition
`v <- (v, w)` in either queue made `makeEmpty v` manufacture `v <- ()` for `v` itself; that
partition is re-enqueued, dequeued, and calls `makeEmpty v` a SECOND time, where
`instantiateType`'s `die` refuses the (no-op) re-binding.  `selfSubstitution`, twelve lines
above, already excluded the variable with `(abstr - v)`.  The self-reference need not be in
the input — the loop derives it (`SplitKeyed`); 3 of L5's 14 panicking hunt seeds have no
self-referential input.

`core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, `makeEmpty`'s `aux`
(was line 1564).  The inner lambda's parameter shadowed the outer `v`, so it is renamed to `u`:

```diff
     def aux(s: Set[Partition], rhs: RHS): Set[Partition] = rhs match {
       case RHSEmpty()      => s
-      case RHSAbstr(abstr) => s ++ abstr.map(v => Partition(v, RHSEmpty(), PartitionEmpty))
+      // The emptied variable is EXCLUDED from the propagation: a self-referential
+      // definition v <- (v, w) would otherwise manufacture `v <- ()` for v itself, which is
+      // re-enqueued and dequeued into a SECOND makeEmpty(v), and instantiateType's `die`
+      // rejects the (no-op) re-binding -- "panic: reinstantiated type v to
+      // ConcreteRho(-,Set()) but it was already bound to ConcreteRho(-,Set())" on a
+      // SATISFIABLE program, at whichever id bases the queue order lets the second step run
+      // (11 of 100 for tracker/repro/satterm/seeds/PANIC3.json; the self-reference need not
+      // be in the input -- the loop derives it).  `selfSubstitution` above uses (abstr - v)
+      // for the same reason.  Sound: `v <- ()` is recorded by this very call's
+      // instantiateType below.
+      case RHSAbstr(abstr) => s ++ (abstr - v).map(u => Partition(u, RHSEmpty(), PartitionEmpty))
       case _               => tml.die("Incompatible instantiations of '" + v + "'")
     }
```

It is sound: `v <- ()` is recorded by this very call's `instantiateType(v, ConcreteRho(-, Set()))`
below.  One caveat on "changes nothing else", which is a MEASURED claim and not a structural
one: the removed partition was not inert while it sat in a queue.  `learnPartitions`' `concRows`
lookup (`Constraints.scala:1410-1418`) folds over `proc ++ incm` and indexes every partition
with an empty abstract part, so a self-manufactured `v <- ()` was a visible EMPTY-ROW CARRIER
for `findConcRow`/`findEmptyRow` — the lookups that guard `splitRow` and `resRow`, both DEFAULT
ON.  In a state whose only empty-row carrier was that manufactured partition, removing it could
in principle turn a reuse into a mint.  It is unobserved everywhere it has been measured:
identical `drawn`, `bound` and `residual` on all 866 both-sides-solved hunt runs, identical
`DRAWN` histograms on all 18 tracked seeds at 20 bases, and a **byte-identical 66-file corpus
row trace, 363,570 records pre and post** (`B1-REVIEW.md` §3c/§3d, F5).  It leaves the `die` in place as a genuine invariant check, so `EnvNodup` /
`makeEmpty_env_len` / L5 §C3.4's branch table survive.  The rejected alternative was
uncommenting the tolerant `case Some(t) if e == t => warn` at `Subst.scala:182`: that masks the
symptom and removes the only enforcement of queue hygiene, which the model's lemmas rely on.

**The premise shape is not exotic: it is compiled every day.**  The reviewer scanned all seven
corpus row traces (1,082,449 records) for a multi-part self-referential partition and found
exactly one — in the SHIPPED STANDARD LIBRARY.  `core/src/main/resources/modules/Layout/Report.e`
yields `r <- (o, r)` on **every boot, in every corpus group**.  The corpus is nevertheless safe,
and safe robustly: that partition is dequeued and dissolved by `selfSubstitution` — the sister
rule that already excluded `v` — before any `makeEmpty` touches it, and the solve lifted
verbatim into a seed plus two perturbations sweeps **100/100 SOLVED at bases 0–99 on the
PRE-FIX compiler**.  So the honest reading of L5 §6.5's "the shape is expressible" is stronger
than it sounds: the ingredient is already in the standard library, and only the dequeue order
separates it from the panic.  `PANIC3` and `RS5` are exactly the case where the order does not
spare us — the self-referential partition sits in `proc` while `v <- ()` arrives from another
rule.

**Nor was it a rare coincidence of queue order.**  `PANIC3` fails at 11% of bases, but the
reviewer's `RS5` — `v0 <- (v0,v1)`, `v1 <- (v1,v2)`, `v2 <- (v2,v0)`, `v9 <- (v5,(|l100|))`,
satisfiable with everything empty and `v9 = {l100}` — was **REJECTED by the shipped compiler at
100% of 50 bases**, every one the reinstantiation panic, and is SOLVED 50/50 after the fix.
Three self-referential constraints instead of one turn the order-dependence into a certainty.

New tracked seed `tracker/repro/satterm/seeds/PANIC3.json` (minimised by L5), with its model:

    {"rho": {"4": [], "5": [], "6": [], "7": [], "9": [100]},
     "cons": [[7,[4,6],[]], [6,[6,7],[]], [9,[5],[100]]]}

i.e. `v7 <- (v4, v6)`, `v6 <- (v6, v7)`, `v9 <- (v5, (|l100|))`, satisfied by
`v4 = v5 = v6 = v7 = ()`, `v9 = (|l100|)`.

## 2. Gate table

All "before" figures are the MAIN checkout's classes (read-only: seeds and `crule` replay it
directly through `target/ermine-classpath`; the corpus and interface sweeps run in the
WORKTREE against a COPY of main's class directories, so nothing in the main checkout is
written).  Toolchain `~/.local/ermine-toolchain/jdk-21.0.12.1+1`, one sbt at a time.

| # | gate | before (main classes) | after (worktree) | verdict |
|---|---|---|---|---|
| 1 | `sbt -batch core/compile` | — | success, 39 s, 472 warnings (all pre-existing) | PASS |
| 2 | `sbt -batch -J-Xmx3g core/test` | — | **Total 914, Passed 913, Failed 1, Errors 0** (296 s) | PASS — the one failure is the known `Constraints.disjunction sound` starvation ("Gave up after only 0 passed tests. 501 tests were discarded"), unrelated to this change |
| 2b | `TestLoopTrace` | — | **SKIPPED**, both properties | expected: the Lean `looptrace` binary is not built in the worktree (`…/ermine-scala-wt-b1/tracker/lean/.lake/build/bin/looptrace` absent), so the trace-equality property does not run here at all. It is Part B's gate, in the main checkout. |
| 3a | `satterm/sweep.sh json:…/PANIC3.json 0 99` | **SOLVED=89 REJECTED=11** HANG=0 OOM=0 | **SOLVED=100** REJECTED=0 HANG=0 OOM=0, `DRAWN 0:x100` | PASS |
| 3b | 18 tracked seeds `seeds/*.json` (CHAIN COLL D1–D4 G7 H2 LBL NE6 PANIC3 REF RE RR SUP W2 W3 W4), bases 0–19, per-seed flags per `L1-MODEL.md` §6e (`RE` `-Dermine.emptyRow=true`; `D1–D4` `-Dermine.labelCheck=false`) | see below | see below | PASS — the ONLY difference in the whole normalised sweep (verdict line per base + `DRAWN` histogram + `SUMMARY`) is PANIC3's two panics (bases 6, 13) becoming SOLVED; all 17 other seeds byte-identical, draw counts included |
| 3c | `crule/sweep.sh W 0 99` | REJECTED 100/100 | REJECTED 100/100 | PASS |
| 3d | `crule/sweep.sh gseed 0 99` | REJECTED 100/100 | REJECTED 100/100 | PASS |
| 3e | L5's 14 panicking hunt seeds (`e00246 e00282 e00327 e00359 e00438 e00559 e00593 e00660 e00842 e01127 e01217 e01228 e01264 e01479`), bases 0–99 = 1400 runs | **SOLVED=866 REJECTED=534** (all 534 the reinstantiation panic) | **SOLVED=1400 REJECTED=0 HANG=0 OOM=0** | PASS — none still dies |
| 4a | corpus `corpus-run.sh --batch`, main 66 | 23 LOADED / 43 REJECTED, `shouldfail/` **40/40** | 23 LOADED / 43 REJECTED, `shouldfail/` **40/40** | PASS — verdicts identical |
| 4b | corpus `--incomplete --batch`, 34 | 18 LOADED / 16 REJECTED | 18 LOADED / 16 REJECTED | PASS — verdicts identical |
| 4c | batch determinism control (main classes, second `--batch` run vs the first) | **0 of 66 differ** | — | the batch is deterministic per class set, so a batch message difference is attributable, not churn |
| 4d | corpus MESSAGES | 6 of 66 + 2 of 34 texts differ | — | 2 of those 8 are only my snapshot root in a stdlib path (`sk03`, `sk05`) and are not differences at all. The other 6 (`der01 der02 der06 der07`, `np03b`, `unsound04`) are a DIFFERENT CLAUSE of the SAME refutation at the SAME field and the SAME line:column — the blame-clause choice, which is id-order dependent. **Per-file re-run of all 8 on both class sets: 0 of 8 differ**, so in a virgin session (the mode every adopted measurement uses) the messages are unchanged; the clause only moves in a batch session, where the module is compiled with every earlier module resident. No verdict moves either way. |
| 5 | published types: per-file `.ei` sweep, worktree classes vs main classes, 110 modules | 156 interfaces captured | 156 interfaces captured | **3 of 156 interfaces differ** (`stdlib_Chart`, `stdlib_Op`, `stdlib_Report`); bindings **1544 identical, 21 order-only, 0 concrete->polymorphic (WEAKER), 0 polymorphic->concrete, 0 other, 0 only-in-A/only-in-B**. PASS: **0 weaker.** |
| 5b | same-checkout CONTROL (worktree classes swept twice, identical configuration) | — | — | **2 of 156 differ** on its own: 1542 identical, **21 order-only, 2 alpha-equivalent**, 0 weaker, 0 other. The sweep is not bit-stable run to run, and the control's churn is the SAME size as the A/B churn (21 order-only either way) and touches a partly different set of interfaces (`stdlib_Op`, `stdlib_Predicate`). So nothing in gate 5 is attributable to the fix; there is no binding left to hand-classify. |
| 6a | `tracker/tools/repl-smoke.sh` | — | **PASS** aliasing (2), relations (6), scoping (4), smoke (23) — 4/4 groups, 35 checks | PASS |
| 6b | `tracker/tools/lsp-smoke.sh` | — | **PASS** lsp (98 checks) | PASS |

**Notes on the table.**

3b per-seed totals, identical on both sides except PANIC3 (bases 0–19, 20 runs each):
CHAIN COLL G7 H2 LBL NE6 RE RR W2 W3 W4 = SOLVED 20/20; D1 D2 D3 D4 REF SUP = REJECTED 20/20
(the six deliberate refutations, `D3` being `makeEmpty`'s own `Incompatible instantiations`
die — untouched by this change); PANIC3 18/2 before, **20/0 after**.

3e is a much larger effect than L5's 5-base sample showed: over 100 bases the fourteen seeds
panic at 534 of 1400 (38%), from 1 of 100 (`e00438`) to 78 of 100 (`e01228`, `e01479`).

`ei-diff.sh` expresses its second side as FLAGS, and here the two sides are two CLASS SETS, so
its per-file `sweep` was re-run as a driver parameterised by classpath instead
(`/home/dmitry/.claude/jobs/880c725d/tmp/B1/ei-sweep.sh`: same per-file loop, same
`Ai/Common.e` hoist, interfaces deliberately ENABLED, `.ei` deleted before each side, the
snapshot flattened by module name with the stdlib prefix canonicalised so the two roots line
up), and the two snapshots classified with `tracker/tools/ei-classify.py`.  Both sides ran
IN THE WORKTREE, over the same 110 `.e` sources; only the class directories differ, and the
main checkout's are used through a COPY, so no `.ei` is ever written into the main tree.
A side takes about 13.5 min, matching `ei-diff.sh`'s documented per-file cost.

`tracker/repl-classpath.txt` in a fresh worktree points at the MAIN checkout's classes, so the
smokes would have measured the wrong compiler; it was regenerated for the worktree
(`sbt -batch 'export core/fullClasspath'`) before 6a/6b and RESTORED to its committed content
afterwards, so the diff Part B applies is the Constraints change alone.

## 3. Summary

Every gate the brief lists passes.  The fix removes 534 of 534 panics over the fourteen
witness seeds at bases 0-99 and 11 of 11 on `PANIC3`, and changes NOTHING else that any gate
can see: identical corpus verdicts (23/43, 18/16, `shouldfail/` 40/40), identical per-file
diagnostics, 913/914 in `core/test` with only the known `disjunction sound` starvation, both
smokes green, and no published type made weaker.  The only residue is cosmetic and inside the
noise the controls themselves produce: six modules print a different CLAUSE of the same
refutation when the corpus is loaded as ONE BATCH (never per file), and three stdlib
interfaces reorder binders (the same 21 order-only bindings a control sweep produces on its
own).  Both are the id-order churn any change to minting produces.

## 4. Housekeeping

* Worktree `/home/dmitry/research/ermine/ermine-scala-wt-b1`, branch `makeempty-self-fix`.
  **No commits.**  `git status` is exactly: `M Constraints.scala`, `?? B1-FIX.md`,
  `?? seeds/PANIC3.json`.
* The MAIN checkout was never written: it was read only through `bin/ermine`'s classpath and
  the `satterm`/`crule` replay drivers (their generated classes went to scratch via
  `SATTERM_OUT`/`CRULE_OUT`), and the corpus and interface sweeps ran against a COPY of its
  class directories.  Its `.ei` inventory is unchanged (0 under `core/examples`, 129 under
  `core/target/.../classes/modules`).
* All `.ei` files this work generated in the worktree were deleted; scratch, logs and the
  captured snapshots are under `/home/dmitry/.claude/jobs/880c725d/tmp/B1/`.  No `rowTrace`
  was enabled, so there is no trace file to gzip.

## 5. Part B: the model mirror

The model change is one line, `tracker/lean/Rowpartition/Loop/Step.lean:126`, inside
`makeEmpty`'s fold (the `p.lhs == v` / `p.rhs.conc.isEmpty` arm):

```lean
-          return s.concat (p.rhs.abstr.map (fun w => (⟨w, RHS.empty, some .partitionEmpty⟩ : LPart)))
+          return s.concat ((p.rhs.abstr.excl v).map (fun w => (⟨w, RHS.empty, some .partitionEmpty⟩ : LPart)))
```

matching `Loop/Rules.lean:55`, where `selfSubstitution` already writes `(abstr.excl v).map …`.
Without the mirror L2/L4's trace equality breaks on any input that reaches the arm.

### 5a. The proofs that had to move, and why

Six sites, in five files.  Every one of them is a place that TRANSCRIBES the fold body or
reasons about what the propagation emits; none is a weakening of a result.

| file / declaration | what changed |
|---|---|
| `Loop/Step.lean:126` | the model change itself |
| `Loop/Wf.lean`, `makeEmpty_ok` | its `set F := <fold body>` transcribes the arm verbatim; updated to `(p.rhs.abstr.excl v)` |
| `Loop/Refine.lean`, `makeEmpty_died` | same verbatim `set F :=` transcription; same update |
| `Loop/Refine.lean`, `makeEmpty_run` | the `adds_list` call names the constraints the step ADDS: now `(x.rhs.abstr.excl v).elems.map (fun w => mk w ∅ ∅)`. Its `LoopRel.emptyProp` premise wants `w ∈ vset x.toConstraint`, which is now `(SSet.mem_excl_iff.mp hw).1`. Strictly fewer facts are claimed to be added, so the refinement is easier, not weaker. |
| `Loop/StrictStep.lean`, `makeEmpty_forward` | the emitted `w` now comes from the excluded set; `List.mem_toFinset.mpr hw` becomes `List.mem_toFinset.mpr (SSet.mem_excl hw)` |
| `Loop/StrictStep.lean`, `MECover` + `makeEmpty_noLoss` | `MECover`'s middle disjunct quantified over `x.rhs.abstr.elems`; it now quantifies over `(x.rhs.abstr.excl v).elems`, because the emitted set no longer covers `v`. **The consumer needed one new case** and it is the interesting one: in `makeEmpty_noLoss`'s `hcover`, the `w = v` branch is discharged by `hv0 : rho v = ∅`, which comes from the RETAINED environment fact `v <- ()` (`hvG`) — i.e. the fact the old propagation was redundantly re-manufacturing was already available from the environment all along. That is the soundness of the Scala fix, in the model. |
| `Loop/StrictBound.lean`, `makeEmpty_aux_emits_self` | **replaced** by `makeEmpty_aux_excludes_self`, in the same shape as `selfSubstitution_excludes_self` (`∀ y ∈ S.elems, y.lhs ≠ v`), with the same proof body. The round-2 lemma stated the OLD behaviour and is now false. |

`QueueHygiene` and `queueHygiene_no_rebind` are **left exactly as they were**, as instructed.
What has changed is their status: `makeEmpty_aux_excludes_self` removes the counterexample
that made `QueueHygiene` false for the model, so the invariant is now **provable in
principle** — but the preservation proof (`QueueHygiene.step`) is NOT attempted here.  That is
L5 round-3 work, and it is the last thing standing between `queueHygiene_no_rebind` and a
proof that the reinstantiation panic is unreachable rather than merely unobserved.

### 5b. Part B's gates

| # | gate | result |
|---|---|---|
| B1 | `lake build Rowpartition` | **success, 841 jobs** (the same job count as before the change) |
| B2 | `lake env lean Audit.lean` | **3058 theorems audited; declarations using a non-standard axiom: 0** |
| B3 | `lake build looptrace` | success, 24 jobs |
| B4 | `sbt -batch core/compile` (main, after `git apply` of the worktree diff) | success |
| B5 | `sbt -batch 'core/testOnly *LoopTrace*'` | **Total 3, Failed 0, Passed 3.** `708 solves (18 seed × 6 bases + 600 generated); 708 segments; 708 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`. The seed count is **18, up from 17: `PANIC3` is in the population.** Both positive controls still detected (id base +1: 47 of 708 disagree; `--flags=nongen`: 59 of 708). |
| B6 | L1 seed sweep, `looptrace-diff.py --sweep`, all **18** tracked seeds × bases 0–9, compiler traces regenerated with the NEW classes, per-seed flags on both sides (`RE` `emptyrow`, `D1–D4` `nolabel`) | **all 180 comparisons agree**, PANIC3 `ok` at every base |
| B7 | L2 corpus replay, `looptrace-corpus.sh`, groups `top` and `shouldfail` | `top` 15 files, **92,673 segments, 92,673 agree, skip=0**; `shouldfail` 40 files, **56,032 segments, 56,032 agree, skip=0**. **0 differing**, exit 0. |
| B8 | `sbt -batch -J-Xmx3g core/test` (main) | **Total 914, Passed 913, Failed 1** — the known `Constraints.disjunction sound` starvation only. `TestLoopTrace` runs for real here (the Lean binary is built), and passes. |

The main checkout's `PANIC3` sweep was re-run against the newly compiled classes as a direct
check that the applied diff is live: **SOLVED 100/100, `DRAWN 0:x100`** (was 89/11).

## 6. Status and what is left

* Both trees carry the fix; **no commits** were made in either.  The main checkout's change
  set for this work is `Constraints.scala`, `Loop/{Step,Wf,Refine,StrictStep,StrictBound}.lean`,
  the new `seeds/PANIC3.json`, this file, and the three doc updates (`TICKET-editor-and-solver-
  followups.md` item, `ROW-CONSTRAINT-STATE.md` paragraph, `LOOP-MODEL-PLAN.md` B1 row).  The
  L5 files (`Loop/{Strict,StrictStep,StrictBound}.lean`, `L5-*.md`, the `Strict` imports in
  `Rowpartition.lean`) are preserved; `StrictStep.lean` and `StrictBound.lean` are edited only
  at the sites §5a lists.
* **Not done, deliberately:** the `QueueHygiene` preservation proof (L5 round 3, see §5a).
* **The ALIAS form of the same `die`** — "reinstantiated type v to u", when the second binding
  is an alias rather than `ConcreteRho(-,Set())` — was raised by L5 §0 and has since been
  examined by the B1 reviewer (`B1-REVIEW.md` §5b).  It is the SAME line, `Subst.scala:184`,
  reached from the SAME two call sites (`incorporateAll`'s `common` and `unify` branches), and
  it has the SAME root cause: during the partition loop only `makeEmpty` and `instantiate` bind
  anything, both remove every partition involving their variable, and after this fix neither
  re-emits one (`instantiate`'s extra `DeDuplication` partition is headed by the unbound `u`).
  So by reading there is no path to it after the fix; and by experiment, 6,000 alias-biased
  satisfiable solves post-fix produced zero deaths, while the 141 pre-fix deaths in that same
  population were all the `ConcreteRho` form and none the alias form.  This is a reading plus a
  measurement, **not a proof of unreachability** — that is `QueueHygiene.step` again.

