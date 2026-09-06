# Brief: D1-T — the POLICY TRANSPORT: re-prove the loop's soundness theorems for the policy-parameterised step

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`; the tree holds D1 Part B's
UNCOMMITTED files (Scala behind flags default OFF; Lean `Loop/{PolicyReplay,FlaggedSound}.lean`, driver edits;
`D1-CHANGE.md`). LEAN ONLY: no Scala edits, no sbt, no commits; do not edit any pre-existing theorem module and
do not edit D1-B's `PolicyReplay.lean`/`FlaggedSound.lean` (import them). Lean `export PATH=$HOME/.elan/bin:$PATH`
in `tracker/lean/`; build with `lake build Rowpartition` and `lake env lean Audit.lean` — NEVER `lake build
looptrace` (relinking the binary mid-run breaks the differential runs that may still use it); the root import
list `Rowpartition.lean` is shared with D1-B's edits: re-read it immediately before editing and append your one
import line at the end of the `Loop` block.

WHY THIS STAGE EXISTS. D1 Part A proved (`Loop/Policy.lean`) that the loop's proofs consume the dequeue only
through `DequeueShape q r rest := ∃ i, q.elems[i]? = some r ∧ rest = ⟨q.elems.eraseIdx i, q.graph⟩`, proved for
the shipped `Q.pop` and for every alternative policy (`dequeuePol_shape`), with `shape_mem`, `shape_mem_or`,
`shape_length_lt`, `shape_kdist`, `dequeuePol_unique`, `dequeuePol_none`. D1 Part B then found that the actual
transport — re-running the theorems that unfold the dispatch against the policy-parameterised step — is 22
theorems across 11 modules, ~1,221 proof lines, and did NOT do it. The user asked "are we sure we are not
introducing unsoundness"; the orchestrator's answer requires the transport to be THEOREMS before D1-B is
committed. Under the shipped policy nothing is at risk (`stepP_shipped`/`stepSP_shipped` are `rfl`); under a
non-shipped policy soundness is currently evidence (0 verdict differences over 2,301,195 corpus solves), not
theorem.

READ FIRST: `tracker/loopmodel/D1-CHANGE.md` §5 — the TRANSPORT SPEC written for you: §5a the recommended shape
(new `Loop/PolicyStep.lean` importing `FlaggedSound`; originals untouched; final theorems `stepP_refines_all`,
`runP_sat_all`, `runP_noLoss`, `runP_rejects_unsat` with `NonRefutationB`, and the S2 chain for `runSP` via a
policy version of `runBud_not_rejected`); §5b the 22 theorems with module, line range, size and the exact
dequeue facts each uses — only five use any dequeue lemma (`step_supFresh`, `step_queueHygiene`,
`step_refines_learn`, `step_refines`, `step_died_refutes`, plus `step_refines_nonlearn`/`step_noLoss_concrete`);
`dequeue_length_lt`/`dequeue_sub`/`kdist_dequeue` appear in none; the other seventeen change only in the opening
line; §5c the two substitutions (`simp only [stepP, State.log] at h; split at h`; `shape_mem (dequeuePol_shape
hdq)` for `PQueue.dequeue_mem hdq`; `.1` on `dequeuePol_unique`) and how `Aux` rides along (bind `∀ pol a` in
front; no soundness statement mentions it); §5d the six traps, above all: alpha-equivalent `match`es compile to
DIFFERENT matcher constants, so a helper lemma will not unify with the code's `match` — prove those goals inline.
Then `Loop/Policy.lean` §5–§6, `Loop/FlaggedSound.lean`, `Loop/Budget.lean`, and the originals in
`Loop/{Refine,RefineLearn,RefineConcrete,Order,Hygiene,Draws,Wf,Sound,Reject,StrictStep,Solve}.lean`.

## Checkpoints, in order (build + audit green at each; report as you go)

T1 `Loop/PolicyStep.lean`: the step-level copies for `stepP pol a` (and hence `stepSP` when `rowSoundBare` is
   off, `stepSP_of_rowSound_off`; and the budgeted `stepBud`/`runBud` forms if D1-B's driver runs those — say
   which step the replay ACTUALLY runs and prove the others equal it when their flags are off): `stepP_qok`,
   `stepP_envNodup`/`stepP_su`, `stepP_supFresh`, `stepP_queueHygiene`, `stepP_drawn_le`, `stepP_refines`,
   `stepP_refines_nonlearn`, `stepP_refines_learn` → `stepP_refines_all`, `stepP_noLoss_*` → `stepP_noLoss_all`
   / `stepP_noLoss_or`, `stepP_died_refutes` — every one proved from `DequeueShape` + the `shape_*` facts,
   original statements' hypotheses unchanged except the policy parameter. If ANY of them does not go through
   for some policy, that is a FINDING: report it at once with the exact goal, do not weaken silently.
T2 The run-level theorems for the policy run (`runP`/`runSP`): `runP_sat_all`, `runP_noLoss`, `runP_models`,
   `runP_ssat_iff`, `runP_rejects_unsat` (exception list `NonRefutationB`), and the S2 chain
   (`solveP_noFalseAccept`, `solveP_accepted_faithful` or the policy version of `runBud_not_rejected`).
T3 The acceptance fact is used where it matters: the `.solved` case of the policy run relies on
   `stepP_done_dequeue` (accept only on an empty queue) — show it in the proof, not only as a lemma.
T4 `#print axioms` for every new declaration in scratch `/home/dmitry/.claude/jobs/880c725d/tmp/D1T/`
   (standard axioms only), no `sorry`, `lake build Rowpartition` + `Audit.lean` green; quote every final theorem
   verbatim in a new section of `tracker/loopmodel/D1-CHANGE.md` ("§6 Transport — DONE"), with a table
   original → transported (name, module, lines), and update the plan's D1 row and the README additively.

Outcomes, say which: (T-done) all 22 transported and the run-level theorems proved for every policy;
(T-partial) the list of theorems that resist, with the goal each is stuck on and whether it is a policy that
breaks it (a FINDING) or a proof-engineering obstacle. Constraints as always: audit 0 non-standard axioms, no
silent weakening (side-by-side table), never `lake exe cache get`, no new `require`, no new project, never touch
`~/research/leanwork`, `CutSearch.lean` out of the root import list, disk tight, `pkill -f` matches itself, long
runs under `setsid nohup` with a log. Traps: `decide` cannot see through `mk`/`slist`; no `norm_num`;
`Finset.mem_insert` not with `Finset.forall_mem_insert`; the matcher-constant trap above. Report early.
