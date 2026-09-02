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
were discarded." It is the one failure in `core/test`'s 903/904 and predates all of
this work. Fix the generator or retire the property — a permanently red test
teaches everyone to ignore the suite.

## 4. The module loader StackOverflows on batch loads

`StreamTUtils.chop`, in the loader's StateT stream chain, overflows after roughly
two modules of `core/examples/incomplete/` in one `bin/ermine` invocation.
PRE-EXISTING: reproduces identically with `-Dermine.genRules=all
-Dermine.labelCheck=false`. `postOrder` builds its result by left-nested lazy
`Stream` append, which is quadratic and deeply recursive.

Consequence worth knowing: **never compare two corpora by batch-loading them.**
Both runs die partway and the counts are partial; that invalidated one comparison
in this work before it was caught. Compare per-file.

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
  unsatisfiable, and the per-label check refutes the witness at one label
  (`gSeed_refuted`), so the two defences are complementary. Behind `-Dermine.resGuard`,
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
