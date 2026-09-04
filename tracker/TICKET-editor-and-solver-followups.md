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
