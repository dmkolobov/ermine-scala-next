# Follow-ups from the row-constraint and editor work (2026-09-01)

Everything below is OPEN. Context, evidence and reproduction commands live in
`tracker/ROW-CONSTRAINT-STATE.md` (read its "Traps" section first — it will save
real time) and `tracker/TICKET-row-constraint-decision.md`.

Landed on `scala3-migration` in `03a288d..606f6ae`: `cut` and the per-concrete-label
refutation check adopted as compiler defaults, three example corpora, the Lean
development, and three LSP fixes.

## 1. Label-check diagnostics blame the module, not the call site — DONE 2026-09-02

Was: `Subst.solve` searched the input constraints for a `Part` mentioning the offending
field and died at its location, restricted to the file being compiled. When the
offending constraint was not in that file the blame fell back to the module header and
the user learned only the field name (`witness03_grounded_call.e` and
`unsound03_inferred_headers.e` reported `1:1`); and under `-Dermine.labelCheckEarly`
11 of 26 messages blamed a stdlib signature outright, because "the file being compiled"
was read off the constraint set's own location, which for a set assembled from a stdlib
helper's instantiated type WAS the stdlib.

Root cause, two layers, neither in the check itself:

- a scheme's constraints kept the location of the SIGNATURE that stated them when the
  scheme was instantiated at a use, so a constraint reached through `except` sat at
  `Relation/Row.e:51:48` however many times the user's file called `except`;
- and `Term.sub` replaced a substituted `Var`'s V wholesale, so every reference to a
  let- or module-bound name carried the BINDER's position (`App.loc = e1.loc`), and a
  type error in `bad = helper x` was reported at the line defining `helper` --
  `der04` reported `38:1`, the definition, not `40:7`, the call.

Fix: `Subst.instantiatedAt` re-locates a scheme's row constraints (and their `Exists`)
to the occurrence that instantiates them, in `inferType`'s `Var` case; `Term.sub` keeps
the occurrence's location (`vp at v.loc`, the discipline `Relocatable.preserveLoc`
already applied to the module-level maps); `Subst.solve`'s blame takes "the file being
compiled" from `tml`, prefers the constraint whose left-hand variable is the partition
`labelClash` refuted (it now returns it), and reports at the underlying `Pos`, so
`Inferred.report`'s "inferred from" no longer trails the reason clause;
`mkSimplified.normalPart`'s "Fields appear twice" dies at the constraint rather than at
its left-hand type variable, whose location was the stdlib signature that declared it.

Measured (`tracker/tools/corpus-run.sh`, one JVM per file, both sides from snapshotted
class directories so recompiling could not leak into a run): 66-file corpus, location
fixes alone (`-Dermine.labelCheckEarly=false`): 0 verdicts change, 16 messages move --
10 from a definition to its call site (`der04-08`, `dup01`, `dup02`, `inc07`,
`inf01/02/04`), 4 out of the stdlib (`der03`, `dup05`, `dup07`, `dup08`), and `dup06`
gains a position it never had. With the early check on top (now the default): 26
label-check messages, every one in the user's file at the call site; see
`core/examples/shouldfail/RESULTS.md`. 34-file `incomplete/`: verdicts identical (18
LOADED / 16 REJECTED, no timeouts), 16 messages move to call sites; `witness03`
`1:1 -> 32:16`, `unsound03` `1:1 -> 81:16`, `unsound01` `104:18 -> 120:7` -- its
signature is satisfiable (the control `good` proves it), so the call is the right blame.
`core/test` 903/904 (known failure only), `lsp-smoke` PASS 82.

This is what unblocked `-Dermine.labelCheckEarly` (`TICKET-row-solver-8abc.md`, "A
second, free change").

## 2. `bin/ermine` cannot resolve a module hierarchy; the editor now can

`lsp/Resident.scala` (commit `793ae57`) resolves sibling imports against the module
hierarchy root. The CLI has no equivalent, so

    bin/ermine core/examples/Ai/ClinicalTrial.e

still reports `Module not found: 'Ai.Common'` unless `Common.e` is passed first.
The editor and the CLI should agree.

## 3. `Constraints.disjunction sound` has been failing for a long time

Its generator discards every case: "Gave up after only 0 passed tests. 501 tests
were discarded." It is the one failure in `core/test` (910 of 911 since item 4 added
seven properties; 903 of 904 before) and predates all of this work. Fix the generator or retire the property — a permanently red test
teaches everyone to ignore the suite.

## 4. The module loader StackOverflows on batch loads — FIXED 2026-09-03

`StreamTUtils`'s dependency-order computation is iterative now, and a whole corpus loads
in ONE `bin/ermine` invocation: 66 files in 19 s against 19m22s one file per JVM.

**The mechanism.** `chop` — the depth-first walk that prunes the import forest — recursed
once per SIBLING as well as once per level (`bs <- chop(us)` inside the `State[Set[A],
Forest[A]]` bind), so its stack depth was the NUMBER OF NODES in the graph rather than the
depth of the graph, and every frame carried the `IndexedStateT.flatMap` /
`IdInstances.bind` group with it; `postOrder` flattened each tree with a left-nested lazy
`Stream` append, which is quadratic. The caller that overflows is not the loader's own
import graph, which is small, but the constraint solver's `Constraints.Q.TypeVarGraph`
(`Constraints.scala` ~425), which re-runs `reverseTopSort` over ALL of its nodes on every
edge it adds.

**The reproduction is bigger than this ticket used to say.** Its original text — "overflows
after roughly two modules of `core/examples/incomplete/` in one `bin/ermine` invocation" —
does not hold at 98e7bf2 under the current defaults (`cut`, `labelCheckEarly`, `resGuard`,
`splitKey`): the 66-file corpus loads in one JVM without overflowing, and so do
`incomplete/`'s 34 files. What still overflowed
was all 110 in one JVM: `java.lang.StackOverflowError` at
`StreamTUtils$.chop$$anonfun$1(StreamTUtils.scala:124)` — the `if (s contains v)` line —
under 60 repetitions of that frame group, 293 s in, on `incomplete/gu05` after the 66-file
corpus, with 41 of the 110 files never attempted. `-Xss1g` was tried in earlier work and
burned 13 CPU-minutes without loading a module, so depth was never the whole story.

**The fix** is in `core/src/main/scala/com/clarifi/reporting/util/StreamTUtils.scala`:
`chop`, `prune`, `dfs`, `postOrder` and `reverseTopSort` use an explicit stack, a visited
set and an accumulated result. Public signatures are unchanged — `chop` still returns
`State[Set[A], Forest[A]]`, `prune`/`dfs` still build a `Forest` — `generate` and `Tree`
are untouched, and `reverseTopSort` no longer builds the intermediate forest at all. The
requirement was not "a topological sort" but "the SAME order, node for node": load order
feeds the id supply and ids reach published types. `TestStreamTUtils` keeps the old
definitions verbatim as a private `Reference` and compares the two on random 16-vertex
graphs (dense, cyclic, with repeated edges and repeated roots) — the emitted order, the
pruned forest, `chop`'s final visited set, and `postOrder` per tree, 100 cases each — plus
a DAG ordering property and two regressions at 50,000 vertices, a chain and a flat forest,
which the recursive definitions cannot do at all. Positive controls: reversing the new
order falsifies 4 of the properties, reversing the pruned children falsifies 2 others.

**Failure attribution.** `bin/ermine`'s failure line now names the file — `Unable to load
module from '<path>'` (`Console.loadProject`) — because in a batch the bare message
identified nothing. The verdict scripts grep the unchanged prefix `Unable to load module`.
A module that FAILS in a batch leaves nothing behind: `ConsoleEnv.session`
(`Console.scala` ~214) snapshots `sessionEnv.copy` and restores it on `Death`, which is
why 43 rejections in one JVM do not disturb the modules after them. Anything that is not a
`Death` — a `StackOverflowError`, an OOM — reaches `main`'s catch-all instead and takes
the rest of the command line with it, which is exactly what the pre-fix 110-file run did.

**The batch mode.** `tracker/tools/corpus-run.sh --batch` loads a whole corpus in ONE JVM
and splits the combined output back into the per-file `.out` files every verdict tool reads
(`tracker/tools/batch-split.py`, which refuses to split a run that did not produce one
terminator line per file). `keptdef-sweep.sh --batch` does the same one JVM per corpus
DIRECTORY; its per-`solve` segmentation survives, because the `solve` record carries the
solve's source loc and `keptdef-mints.py --filter` picks one file's solves out of a group's
trace — checked on `incomplete/np01` in a three-module batch against a per-file run: 605
solve segments and every kept-definition count identical (150 dequeues, 82 with a concrete
part, 33 mints, 48 reuses, 1 keyed). `ei-diff.sh --batch` can only manage FIVE FILES at a
time and still does not come out whole — its sweep needs interfaces ENABLED, and that makes
the accumulation below much more expensive. PER FILE REMAINS THE DEFAULT in all three: a batch compiles each module in
a session that already holds every module ahead of it on the command line, and that is not
the same compilation as a virgin session.

Measured 2026-09-03 in a worktree at 98e7bf2 + this fix, one class set, on a machine
shared with another agent's sweep (the wall-clocks are upper bounds; the ratio is the
honest part):

| gate | per file | --batch |
|---|---|---|
| 66-file corpus, wall | **19m 22s** (1161.6 s) | **19.5 s** — 60x |
| `incomplete/`, 34 files, wall | **7m 31s** (450.9 s) | **15.4 s** — 29x |
| 66-file verdicts | 23 LOADED / 43 REJECTED | **identical**, 0 of 66 differ in verdict |
| 34-file verdicts | 18 LOADED / 16 REJECTED | **identical**, 0 of 34 differ in verdict |
| `shouldfail/` | 40/40 REJECTED | 40/40 REJECTED |
| diagnostic TEXT | — | **6 of 66 and 1 of 34 differ** (see below) |
| one `ei-diff.sh` sweep, wall | **13m 45s** (818 s) | **8m 41s** (521 s) — 1.6x, chunked by 5 |
| published `.ei` (`ei-classify.py`) | CONTROL, two per-file sweeps of one build: **6 of 188 interfaces differ**; 1902 bindings identical, 25 order-only, 5 alpha-equivalent, 1 other, **0 weaker** | **18 of 185 differ**; 1855 identical, 41 order-only, 11 alpha-equivalent, 12 other, **0 weaker** — and 3 interfaces MISSING, two of them because a chunk hit its 180 s cap |

The message differences are not verdict changes and not noise: same file, same source
position, same field, a different clause of the same refutation — `Row partitions are
unsatisfiable at field 'Shouldfail.Der06.b': the whole contains it but no part does`
per file against `... a part contains it but the whole does not` in a batch. Both modes
are STABLE run to run (a second batch differs from the first on 0 of 66; a per-file re-run
of the seven files reproduces the per-file wording exactly), so the difference is
attributable to batching: the label check reaches its refutation through a different
witness when the session already holds the modules ahead of it.

**The accumulation cliff, which is the real limit on batching.** A module's solve gets
dramatically more expensive as the session fills up, and the effect is in `Constraints`
(`learnPartitions`, `substitution`, `PQueue.contains`), not in the loader.
`incomplete/gu05`, measured 2026-09-03 on one class set:

| how it is loaded | interfaces on | interfaces off |
|---|---|---|
| alone | **1.09 s** | 0.41 s in the 34-file batch |
| behind `gu01` + `gu04` in one JVM | **26.94 s** | 7.46 s |
| behind the 66-file corpus | — | **not finished after 200 s** |

So: do not merge the two corpora into one JVM, and do not batch a sweep that needs
interfaces written. `ei-diff.sh --batch` chunks by five for this reason and still loses two
chunks of the 110-file corpus to its 180 s cap; it is for A/Bs where BOTH sides are
batched, so the losses are symmetric.

## 5. Audit `checkFile`'s environment handling generally

Two bugs were found there in one session, both in code whose comments described
behaviour it did not implement:

- sibling imports resolved against the file's own directory rather than the module
  hierarchy root (`793ae57`);
- the module's own BUILTINS were scrubbed away, because `Lib` installs them under
  the module they belong to and the scrub went by module name alone (`8c7b952`).
  `Session.reloadChangedModules` had always guarded this with
  `|| builtinEnv.contains(...)`; `checkFile` claimed to scrub "the way :reload's
  scrubber does" and did not.

The remaining scrubbed tables and the `fastMode` path deserve the same scrutiny.

## 6. Hover on declaration sites

Uses of `field` and `foreign` names hover (`73b4600`); the declaration heads do
not, because the renamer emits occurrences for references, not for declaration
heads.

**Warning, tried and reverted.** Making `collectHeads` bind foreign names BROKE
THE COMPILER: `Native/Throwable.e` began reporting `undefined type` and the stdlib
stopped loading. The change was two cases in `walkHeads` plus a `bindForeign`
helper, excluding `SForeignData` because it binds a type. Why binding a foreign
TERM name corrupts TYPE resolution is not understood. Understand that before
retrying — it points at something real in the renamer's namespace model.

## 7. Hover on local binders — "all values should be hoverable"

`Definitions.index` returns `None` for any binder whose kind is not `TopLevel`,
commented `local binder types: perf-ticket territory`. Local inferred types are not
retained anywhere the editor path can see them, so this is a design change with a
measured cost, not a patch. It is the remaining gap against the stated goal that
every value be hoverable.

## 8. Row-solver work not finished — ANSWERED 2026-09-01

Full write-up, with the Lean theorem names and the measurements:
**`tracker/TICKET-row-solver-8abc.md`**. Summary of the three bullets as they stood:

- **8a, the label check on the saturated set.** LICENSED. The old justification was
  wrong twice over — `forced_mono` is monotone in the SYSTEM and `q.expand` is not a
  superset of `q` (it deletes and renames), and the code never implemented rule 6's
  unsound documented form in the first place. The correct licence is
  `Rowpartition.refute_saturated_sound` (`Rowpartition/Saturate.lean`): a satisfiable
  input stays satisfiable through any run of the solver, so a refutation on the
  saturated set really does refute the input. Behind `-Dermine.labelCheckSaturated`,
  default off. The implication is STRICT (`satStep_not_reflecting`): a refutation-only
  check may move there, an acceptance check may not.
- **8b, `reduce`'s second case.** SETTLED, and the answer is NEGATIVE.
  `Rowpartition/Splice.lean` proves the splice sound (`splice_sat`, `reduce2_models`)
  and exactly conservative for ONE splice (`spliceG_backward`), but
  `DroppedPartition.dropped_can_lose` exhibits a satisfiable four-variable system with
  no concrete labels at all on which the emitted residual FAILS to entail a consequence
  of the input. The cause is precise: `reduce` never rewrites a LEFT-hand side, so an
  ambiguous variable that also heads a constraint in the published list is left with
  nothing tying it to the rest. `dropped_loses_nothing` is the positive half, under the
  hypothesis (`hlhs`) that the counterexample violates.
- **8c, making the cut terminate.** DONE, with a dichotomy. Guarding `resolution` with
  the resolvent reverse lookup is provably not a semantic change
  (`Rowpartition/ResGuard.lean`), makes the rule terminate on every SATISFIABLE system
  with an explicit bound (`guarded_terminates_of_satisfiable`), and does NOT restore
  termination in general (`gSeed_diverges`) — the surviving divergent seeds are all
  unsatisfiable, and the per-label check refutes THAT witness at one label
  (`gSeed_refuted`). [CORRECTED 2026-09-02: this used to say "so the two defences are
  complementary". They are not, in general: the check refutes only what propagation can
  force, and `Rowpartition/DefaultDiverge.lean` (`not_CRule`) exhibits an unsatisfiable
  eight-constraint system on which the shipped rule set diverges and which the input check
  does not refute — see `tracker/PROMPT-default-termination.md` and
  `ROW-CONSTRAINT-STATE.md`.] Behind `-Dermine.resGuard`,
  default off. Measured on a probe family built for the purpose: there is a second
  cliff driven by `resolution` on a WELL-TYPED program, and the guard removes it.

## 9. OPEN QUESTION (not a confirmed defect): is signature resolution order-fragile?

Found 2026-09-02 while diffing `.ei` interfaces for item 8b. For the same source the
compiler sometimes publishes `Relation (|..6 fields..|)` and sometimes
`forall t. (..4 constraints..) => Relation t`, decided by ordering with no semantic
content — `Ai/ClinicalTrial` and `Ai/HeadcountPlan` show both forms with the deciding
perturbation swapped, on structurally identical constraint sets.

**Corrected the same day: the headline claim is UNSUPPORTED.** The two modules are not
comparable — one has a downstream use that pins the row and the other does not — and both
observations follow directly from what the flag does, without any appeal to fragility. No
problem has been demonstrated in the shipped compiler. The deciding experiment (perturb
something semantically irrelevant and see whether resolution flips) has NOT been run; if it
comes back clean the ticket should be withdrawn, not downgraded. Loosely related to the
ten-site determinism inventory in
`TICKET-row-constraint-decision.md`, with a worse symptom than the reordering that
inventory describes: it changes the type a user programs against, it propagates to callers,
and it is invisible to a multiset comparison of constraints.

Full write-up, witness, reproduction and the ordered list of what to establish first:
**`tracker/TICKET-signature-resolution-fragility.md`**.

## 10. Skolem-emptiness errors still blame the module header

`sk03_field_copy_append_self.e` and `sk05_derived_skolem_field_copy.e` (error class 4,
written 2026-09-01 to reach skolem escape through the stdlib's `EField` existential) report

    sk03_field_copy_append_self.e:1:1: .../modules/Field.e:22:24: Cannot unify skolem variable with empty relation

The INNER position is right and deliberate: `Field.e:22:24` is the
`data EField a = forall r . EField (Field r a)` declaration where the skolemised row was
bound, and the headers say so. The OUTER position, `1:1`, is the module-header fallback
again: `makeEmpty` (`Constraints.scala:1061`) dies at the ambient `tml`, which for a
top-level binding group is the module's location, so the user's `bad = ...` line is never
named. Item 1's fix does not reach it because this path is a solver rule, not the
label-check blame in `Subst.solve`. `sk01`/`sk02`/`sk04` are unaffected only because
their existential is declared in the file being compiled.

Fix when wanted: give `makeEmpty`'s report the same treatment as item 1 -- blame the input
constraint that forced the skolem empty (now located at the call site), falling back to
`tml` only when none is in the compiled file. Expected result:
`sk03...e:31:7: ... Field.e:22:24: Cannot unify skolem variable with empty relation`.
Deliberately NOT done 2026-09-02; the two cases are documented in
`core/examples/shouldfail/RESULTS.md` (2026-09-02 section) as the only messages that still
carry a stdlib position.

## 11. `makeEmpty` propagated the empty fact to the variable being emptied — FIXED 2026-09-04

**The defect.** `Constraints.makeEmpty`'s `aux` mapped over ALL of a right-hand side's
abstract part, INCLUDING the variable the call is about to bind empty:

```scala
case RHSAbstr(abstr) => s ++ abstr.map(v => Partition(v, RHSEmpty(), PartitionEmpty))
```

(the inner lambda's `v` shadows the outer one). So a self-referential definition
`v <- (v, w)` in either queue made `makeEmpty v` manufacture `v <- ()` **for `v` itself**;
that partition is re-enqueued, dequeued, and calls `makeEmpty v` a SECOND time, where
`Subst.instantiateType` refuses the re-binding and the solve dies:

    panic: reinstantiated type v6 to ConcreteRho(-,Set()) but it was already bound
    to ConcreteRho(-,Set())

— note both sides are the SAME value: the panic refuses a NO-OP re-binding, on a program
that is perfectly satisfiable. `selfSubstitution`, twelve lines above, already used
`(abstr - v)`; the two had simply drifted apart.

**Why it is a user-visible bug, not a curiosity.** Whether the second `makeEmpty` step
happens at all depends on the queue's priority order, which depends on the ids allocated
before the solve. So a VALID program is accepted or rejected according to how many type
variables the compiler happened to allocate earlier — the same order-dependence class as the
NameLoss ticket. And the self-reference need not be written by the user: the loop DERIVES it
(`SplitKeyed`), so 3 of the 14 witness seeds have no self-referential input at all.

**How it was found.** The L5 witness hunt (`tracker/loopmodel/L5-TERMINATION.md` §0,
root-caused in `L5-REVIEW.md` §6.2/§6.3/§6.4, findings F3/F4 in its §9): 1,500 empty-biased systems that are satisfiable BY
CONSTRUCTION, run through the Lean loop model, then the interesting individuals replayed
through the real `Subst.solve`. Minimised to
`tracker/repro/satterm/seeds/PANIC3.json` — `v7 <- (v4, v6)`, `v6 <- (v6, v7)`,
`v9 <- (v5, (|l100|))`, satisfied by `v4 = v5 = v6 = v7 = ()`, `v9 = (|l100|)` — which
panicked at **11 of 100 id bases**. Over the fourteen panicking hunt seeds at bases 0–99 the
shipped compiler panicked at **534 of 1400 runs (38%)**, from 1/100 on `e00438` to 78/100 on
`e01228` and `e01479`; the hunt's 5-base sample had shown only 29.

**The premise shape ships in the standard library.** The B1 reviewer scanned all seven corpus
row traces (1,082,449 records) for a multi-part self-reference and found exactly one, in
`core/src/main/resources/modules/Layout/Report.e`: `r <- (o, r)`, produced on **every boot, in
every corpus group**. It never reaches `makeEmpty`'s `aux` — `selfSubstitution`, the sister
rule that already excluded `v`, dissolves it first — and the solve lifted verbatim into a seed
plus two perturbations sweeps **100/100 SOLVED at bases 0–99 on the PRE-FIX compiler**, so the
corpus really was safe. But the ingredient was already being compiled every day, and only the
dequeue order separated it from the panic. Nor was the panic a rare order coincidence: the
reviewer's `RS5` — `v0 <- (v0,v1)`, `v1 <- (v1,v2)`, `v2 <- (v2,v0)`, `v9 <- (v5,(|l100|))`,
satisfiable — was **rejected by the shipped compiler at 100% of 50 bases** (SOLVED 50/50 after
the fix). Three self-referential constraints instead of one make it a certainty.

**The fix** (brief B1, `tracker/loopmodel/B1-FIX.md`): `abstr.map` → `(abstr - v).map`, with
the shadowing lambda parameter renamed. Sound because `v <- ()` is recorded by that same
call's `instantiateType`. The REJECTED alternative was uncommenting the tolerant
`case Some(t) if e == t => warn` at `Subst.scala:182`: it masks the symptom and removes the
only enforcement of the queue-hygiene invariant the loop model's lemmas rely on. The `die`
stays as a genuine invariant check.

**Gates** (full table in `tracker/loopmodel/B1-FIX.md`): `PANIC3` 89/11 → **100/100 SOLVED**;
the 14 hunt seeds **866/534 → 1400/0**; the other 17 tracked seeds byte-identical at bases
0–19, draw counts included; `crule` `W` and `gseed` still REJECTED 100/100; corpus verdicts
identical (66: 23 LOADED / 43 REJECTED with `shouldfail/` 40/40; `--incomplete` 34: 18/16) and
per-file messages identical; `.ei` sweep 0 published types weakened (the churn it does show is
the size a same-configuration control produces on its own); `repl-smoke` and `lsp-smoke` pass;
`core/test` 913/914 with only item 3's `disjunction sound` starvation. The Lean model was
mirrored in lock-step (`Loop/Step.lean:126`) — `lake build Rowpartition` 841 jobs, `Audit.lean`
**0 non-standard axioms** over 3058 theorems, `TestLoopTrace` 708/708 segments agree with
`PANIC3` in the population, the L1 seed sweep 180/180 and the L2 corpus replay 148,705
segments, 0 differing. The reviewer added a stronger measurement still: the whole 66-file
corpus row trace is **byte-identical pre and post, 363,570 records**. That matters because the
no-op is measured, not structural — the removed `v <- ()` was a visible EMPTY-ROW CARRIER for
`learnPartitions`' `concRows` lookup (`Constraints.scala:1410-1418`, feeding
`findConcRow`/`findEmptyRow`, which guard `splitRow` and `resRow`, both default ON), so in a
state whose only carrier was that manufactured partition the fix could in principle turn a
reuse into a mint. Unobserved everywhere measured (identical `drawn`/`bound`/`residual` on all
866 both-sides-solved hunt runs, identical `DRAWN` histograms on all 18 tracked seeds, and the
byte-identical corpus trace).

**Left open.** (a) The `QueueHygiene` preservation proof: the fix removes the counterexample
that made the invariant false, so `queueHygiene_no_rebind` could be turned into a proof that
this panic is UNREACHABLE rather than merely unobserved — L5 round-3 work, not attempted.
(b) The ALIAS form of the same `die` ("reinstantiated type v to u", when the second binding is
an alias rather than `ConcreteRho(-,Set())`), raised by L5 §0 and examined by the B1 reviewer
(`B1-REVIEW.md` §5b): it is the same line `Subst.scala:184`, reached from the same two call
sites (`incorporateAll`'s `common` and `unify` branches), with the same root cause — during the
partition loop only `makeEmpty` and `instantiate` bind anything, both remove every partition
involving their variable, and after this fix neither re-emits one. By reading there is no path
to it post-fix; by experiment, 6,000 alias-biased satisfiable solves post-fix died zero times,
and the 141 pre-fix deaths in that population were all the `ConcreteRho` form. That is a
reading plus a measurement, not a proof — the proof is (a).

## 12. `subsumeType` does not terminate on one dateDiff refutation (found 2026-09-16, JSON Stage 3 landings) — CLOSED 2026-09-17: IT TERMINATES; the test harness did not

`TestDateAndScan."a dateDiff combine over a relation WITHOUT the dates is now REJECTED (B1)"` asks the checker
to refuse `combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people` with `people : [ name ]`.
Run ALONE (`sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'`) the property never returns: one RUNNABLE
thread in `Subst.subsumeType (Subst.scala:648) -> SubstEnv.kindVars (:169) -> Kind.kindVars (Kind.scala:96) ->
HasKindVars.mapHasKindVars.vars (:125) -> Type.vars (Type.scala:649-653)` recursing, 28 CPU-minutes observed,
GC idle. Reproduced on scala3-migration 478a369c (pre-JSON), json-encode 3eba80f8 and json-runner 85d95531;
inside a full core/test it passes when the Supply ids it meets are favourable (every landing run up to 1170/1170)
and wedged three full runs on 2026-09-16 when two new suites shifted the order. `subsumeType` recomputes
`hm.kindVars` over the WHOLE substitution environment per call, unmemoised; on a refutation search that grows the
env that is quadratic at best and exponential over shared kind DAGs. Quarantined 2026-09-16 behind
`-Dermine.test.dateDiffReject=true` (GATE-POLICY.md). Owner: whoever owns `Subst`; not a JSON item. Evidence:
jstacks and logs under the 2026-09-16 session scratchpad (`land/j3c-full-coretest.log`, `das-on-json-encode.log`,
`das-on-scala3-migration.log`), tracker/json-stage3/report-J3c.md "core/test wedge, investigated".

**CLOSED 2026-09-17 (M2 of the `subsume-termination` programme; `tracker/satterm/SUBSUME-M2.md`).**
The premise above is refuted, by measurement and by proof, and the quarantine is lifted.

* **The check returns.** S0 instrumented `Subst.scala` behind `-Dermine.subsumeTrace` (default OFF,
  `tracker/satterm/SUBSUME-STAGE0.md` §3) and ran the B1 module through `bin/ermine`: it is REFUSED
  in **0.06-0.09 s** ("Row partitions are unsatisfiable at field 'Bad.startDate'") at every one of
  seventeen `Supply` id bases, and the escape check at `:648` RETURNED on all **492,200** traced
  calls, with `hm.types` never exceeding 1,566 entries, 0 cycles in 984,400 walks and 0 budget hits
  (§1.3, §1.5, §1.6, §1.8). The S0 review reproduced it and also ran the suite ALONE at the default
  `minSuccessfulTests` to a GREEN finish in 1,099 s -- "never returns" is refuted by a completed run.
* **And it cannot fail to return.** `runV_steps` in `tracker/lean/Rowpartition/SubsumeEscape.lean`
  proves the `:648` walk is a total function of the expression, following no binding (the jstack
  frames above are a hot loop, not a cycle: `VarT(v) => v.extract.vars` reads the variable's KIND
  annotation). `Rowpartition/Loop/{RejectTerm,EnvBound}.lean` bound the row loop at the shipped
  defaults. Both audited with no non-standard axiom.
* **What actually took twenty minutes** was the harness: `ErmineFixture.no` rewrote a refutation to
  *passed*, not *proved*, so ScalaCheck ran **100 complete checks** of this one fixed program, each
  re-reading the import closure (~9.1 s). S2's `ErmineFixture.rejects` gives the identical verdict as
  *proved*, in one evaluation: the suite ALONE went **1,282 s -> 181-195 s**, and a full `core/test`
  on `scala3-migration` **1,698 s -> 524 s** (`tracker/satterm/SUBSUME-STAGE2.md` §2.1, §4.1).
* **The editor hazard is a gate, not a worry.** The resident language server answers this exact
  program with the row-label diagnostic **58 ms** after the `didOpen` (`tracker/lsp-tests/RowUnsat.e`,
  five checks in `tracker/tools/lsp-client.py`).
* **What remains, and where it lives.** `:648` is still an unmemoised whole-environment walk and it is
  expensive -- 2.79 s of a 12.2 s `bin/ermine` boot (23 %), 45.4 s of a 184 s suite run (24.7 %), 12.1x
  the `:365` walk. That is a PERFORMANCE item, not a termination one, and it is filed in
  `tracker/TICKET-perf-type-inference.md` (P7 Step 1: a memo table keyed on object identity, or the
  `sks`/`sts`-restricted walk S1a proved gives the same verdict). Nothing about it is a reason to gate
  a test.
