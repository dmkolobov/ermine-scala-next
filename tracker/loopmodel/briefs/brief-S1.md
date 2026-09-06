# Brief: S1 — SOUNDNESS of `Constraints.incorporateAll`, as a theorem about the loop model

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`; start from a CLEAN tree at the
commit the orchestrator names (rounds 1–8 of L5 committed). Lean project `tracker/lean/`
(`export PATH=$HOME/.elan/bin:$PATH`). LEAN ONLY: no Scala edits, no sbt, no commits; `bin/ermine` /
`tracker/repro/satterm/run.sh` only to sanity-check a seed if you need one.

THE DECISION THIS STAGE IMPLEMENTS (user, 2026-09-05): after eight rounds, termination of the shipped loop is a
property of real inputs rather than of the algorithm, and the last two rounds measured runs instead of proving the
algorithm. From here on: SOUNDNESS is what gets PROVED (this stage); termination is ENGINEERED in a later design
stage (a budget plus a structural change at the label-set width factor, proved on the model, trace-tested,
perf-measured). This stage is a pure proving stage: no census, no hunt, no corpus run is asked for.

WHAT "SOUNDNESS" MEANS HERE, in the type checker's terms. The loop takes the input system `sys s₀` (the queue's
partitions plus the environment's facts, `Loop/Refine.lean:295`) and either finishes (`.solved` / `.outOfFuel`)
with an environment (the substitution the type checker applies) and a residual queue, or dies with a message
(`.rejected`). The type checker is sound if
  (A) OUTPUT SOUNDNESS — an accepted program is well-typed: every model of the OUTPUT system is a model of the
      INPUT system. In the library's vocabulary that is `NoLoss (sys s₀) (sys s_final)` (`Loop/Strict.lean:47`:
      every input constraint is a consequence of the output), with the companion `Conserv`/satisfiability
      direction saying the loop never conjures a solution out of nothing; and
  (B) REJECTION SOUNDNESS — a rejected program is ill-typed: `run s₀ n = .rejected m s'` implies `¬ SSat (sys s₀)`,
      except for an explicit, finite list of messages that are not refutations (the skolem message; panics).

WHAT ALREADY EXISTS (read these first, they are most of the work):
* Forward direction, all five branches: `RefineLearn.run_sat_all` (satisfiability preserved along any run under the
  shipped flags and `RunSupOk`), `step_refines_all`, `LoopRel.sat`.
* Backward direction (`NoLoss`): `LoopStrict.no_loss` / `LoopStrictRun.no_loss` (`Loop/Strict.lean:287,310`) for the
  strict relation with its exact deletions (`drop`, `instRemove`, `emptyRemove`, `concRemove`, `requeue`, `dedup`);
  `StrictStep.step_noLoss` (`Loop/StrictStep.lean:1805`) for `NonConcreteStep` — i.e. FOUR of the five dispatch
  branches (`common`, `empty`, `unify`, `learn`); `step_noLoss_strict` + `step_conserv_strict` = model-set
  EQUALITY for the three environment branches. The `concrete` branch's `NoLoss` is the missing piece ("row 6" of
  L5 rounds 2–4: `concretizeSrs_sound`, `concRemove`, `cancellation_bare`, `destructiveSub_run`,
  `makeConcrete_run`, `ensureSuperset` — see `L5-TERMINATION.md` §R2.5 row 6, §R3.4, and `B1-FIX.md` §5).
* Rejection: `RefineLearn.run_refutes_all` takes `¬ SSat (sys s')` as a HYPOTHESIS (contraposed preservation);
  only the `empty` branch discharges it (`Order.step_died_empty`, with the skolem and the reinstantiation-panic
  messages as the two exceptions). The system-level refutation lemmas for the other death sites exist
  (`Refine.selfSubst_refutes`, `merge_refutes`, `incompatible_refutes`, `ensureSuperset_refutes`,
  `makeEmpty_died`); the LOOP-level extraction from `learnPartitions` / `makeConcrete` internals down to
  "the premises are members of `sys s`" is NOT written (`L3-THEOREMS.md` §2, "messages 1, 2 and 7").
* Out of scope by construction, to be STATED not proved: `Subst.reduce` (post-loop, not modelled — L2 "Known scope
  limits"); `labelClash` / `labelCheckEarly` (pre-loop; `LabelAlgo`'s own theorem — cite it); `Loc`/blame.
* `QueueHygiene` (B1 certification: the reinstantiation panic is unreachable from any `Wf` initial state under
  `RunSupOk`) — use it to shrink the exception list.

## Checkpoints, in order (build + audit green at each; report as you go)

S1.1 **`NoLoss` on the `concrete` branch.** Prove `step_noLoss_concrete` and hence
     `step_noLoss_all : Wf s → (shipped flags) → SupOk/SupFresh → step s = .continue s' → NoLoss (sys s) (sys s')`
     for ALL five branches. The `concrete` step records `v := ((|fs|))` in the environment (so `sys s'` contains
     that fact), deletes every partition mentioning `v` (`destructiveSub`), and emits their instances
     (`subPartitions`, `can`); `ensureSuperset` has checked every recorded row of `v` is inside `fs`. Show each
     deleted partition is entailed by the environment fact plus its emitted instance (this is `concRemove`'s
     licence, `concretizeSrs_sound`, lifted through `destructiveSub_run`/`makeConcrete_run`). If a deletion turns
     out NOT to be entailed, that is a soundness bug: reproduce it on the compiler with a seed and report at once.
S1.2 **Output soundness along a run.** `run_noLoss : … → (run s n = .solved s' ∨ run s n = .outOfFuel s') →
     NoLoss (sys s) (sys s')` from S1.1 by induction (the shape of `run_sat_all`); then the model-set statement
     `∀ rho, SModels rho (sys s') → SModels rho (sys s)` and, with `run_sat_all`, `SSat (sys s) ↔ SSat (sys s')`.
     State precisely what the ENVIRONMENT's facts are as constraints (`EnvVal.toConstraint`: alias, empty,
     concrete) so the reader sees the substitution the type checker applies IS part of `sys s'`.
S1.3 **Rejection soundness, every death site.** Enumerate every `.died`/`.error` message the five branches can
     raise (grep `Loop/{Step,Rules,Queue}.lean`), and for each prove either `¬ SSat (sys s)` at the state where it
     is raised (the loop-level extraction: premises ∈ `sys s`, then the existing `*_refutes` lemma) or list it as a
     NON-refutation with a one-line reason. Assemble
     `run_rejects_unsat : … → run s n = .rejected m s' → m ∉ NonRefutation → ¬ SSat (sys s)`
     with `NonRefutation` an explicit finite predicate. Use `QueueHygiene` to remove the reinstantiation panic
     from the list; say what the skolem message means (a rigid variable the constraint semantics treats as
     flexible — a genuine type error, not an unsatisfiable system) and keep it on the list.
S1.4 **The `Subst.solve`-shaped statement.** From `buildQueue`/`initState` (as `VocFix.vocFixed_terminates_of_buildQueue`
     does): one theorem `solve_sound` packaging S1.2 and S1.3 for an initial state, with every hypothesis
     discharged from the input (`Wf`, `QueueHygiene`, `EnvNodup`, `SupOk`/`SupFresh` from the seed's own numbers;
     `RunSupOk` from `runSupOk_of`). Instantiate it in Lean on two tracked seeds (one accepted, one rejected —
     e.g. `seeds/NP01.json` and a refuted seed such as `REF.json`/`LBL.json`) at their real supply, and on the
     compiler check the same two seeds agree (`run.sh`). Then write the reader-facing section: what the type
     checker consumes (environment + residual partitions), which theorem covers each, and the three stated scope
     limits (`Subst.reduce`, `labelClash`, `Loc`).
S1.5 **State it.** Add a dated "Soundness" section to `tracker/ROW-CONSTRAINT-STATE.md` (what is proved, verbatim
     statements, hypotheses, scope limits), a new plan section/row for S1 in `tracker/LOOP-MODEL-PLAN.md` if the
     orchestrator has not already added one (do not rewrite an existing one), and the README rows.

Outcomes, say which: (P) both (A) and (B) proved for all branches with the exception list explicit; (P-) (A) proved,
(B) partial with the exact death sites still open, named; (BUG) a deletion or death that is not sound, with a
compiler-reproduced seed.

Constraints as always: audit 0 non-standard axioms (figures at your start are in the orchestrator's launch
message), `#print axioms` for every new declaration in scratch under `/home/dmitry/.claude/jobs/880c725d/tmp/S1/`,
no `sorry` in a finished module, no silent weakening (side-by-side table), never `lake exe cache get`, no new
`require`, no new project, never touch `~/research/leanwork`, `CutSearch.lean` out of the root import list, disk
tight, `pkill -f` matches itself (kill by PID), long runs under `setsid nohup` with a log (background shells are
capped at ten minutes). Traps: `decide` cannot see through `mk`/`slist` (`simp [vset_mk, …]` first); no `norm_num`;
`Finset.card_insert_of_notMem`; `Finset.mem_insert` not in one simp call with `Finset.forall_mem_insert`; a
`by rfl` that re-runs a solve in the kernel costs minutes and can OOM `lake build` — keep instantiations small.

## Report
New file `tracker/loopmodel/S1-SOUNDNESS.md` — write it EARLY and keep it current: per checkpoint the statements
VERBATIM and the outcome; the death-site table (message, branch, refutation lemma or non-refutation reason); the
side-by-side table for anything weakened; audit/build figures; files with line counts; what you could not prove,
original and proved statements side by side. A reviewer re-runs everything.
