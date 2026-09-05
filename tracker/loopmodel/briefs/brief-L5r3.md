# Brief: L5 round 3 — the loop-level mint bound, continued (fresh implementer)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, clean tree at `52da5b8`
(everything through stage B1 is committed; the bug that made `QueueHygiene` false is FIXED on both
sides). LEAN ONLY; `bin/ermine`/`tracker/repro/satterm/run.sh` may replay a witness; no sbt, no Scala
edits, no commits. Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`).

READ FIRST, in order: `tracker/LOOP-MODEL-PLAN.md` (the L5 section and its row: what is proved, what is
open); `tracker/loopmodel/L5-REVIEW.md` in full — its round-2 section ends with the PRIORITY LIST this
round follows, and its R-4 (`requeue`'s licence is semantic: `Requeue.lean` in the reviewer's scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-L5/` proves `requeue_breaks_carried`, so `hmeas` can
increase along a legal `LoopStrict` step) is the obstacle; `tracker/loopmodel/L5-TERMINATION.md` (§R2.*
for the current statements, verbatim; §C3 for the `qsys` argument; §C3.4 for the branch counts);
`tracker/loopmodel/B1-FIX.md` §5 (what the fix changed in `Loop/Step.lean` and the six proof sites); then
the modules `Loop/{Strict,StrictStep,StrictBound}.lean`, `Loop/{Refine,RefineLearn,Order,Wf,Step}.lean`,
and the library `KeyedRow.lean` (`Carried`, `hmeas`, `carried_concretizeSrs`), `KeyedEmpty.lean`,
`ResGuardTerm.lean`.

## Checkpoints, in the reviewer's priority order (each leaves build and audit green; report as you go)

R3.1 **R-4.** Either add a syntactic conjunct to `requeue` that preserves `Carried` (and prove the loop's
     actual re-emissions — `++!`'s redirect, `trim`, `replace`'s dedup — satisfy it), or dissolve
     `requeue` into exact operators. Then prove `Carried`-preservation (`carried_step`) for every
     non-minting `LoopStrict` step, the analogue of `carried_concretizeSrs`. This is the ingredient (B)
     of §C3.1 that has been missing since round 1; state it verbatim.
R3.2 Make `step_empty_makeEmptyE` load-bearing (the `empty` branch's refinement goes through
     `emptyRemove`, not `requeue`), and widen `substOut` with `replace`'s de-duplication fact so
     `instRemove` goes live. Report the constructor-use table.
R3.3 **`QueueHygiene` preserved by `step`** (`QueueHygiene.step`), now that `makeEmpty`'s propagation
     excludes the emptied variable; then `queueHygiene_run` from the initial states, and the corollary
     that the reinstantiation panic is unreachable from any `Wf` initial state. This is the theorem that
     certifies B1.
R3.4 The `concrete` branch (row 6 of R2.5: `concretizeSrs` plus `keepDefs`/`can`, backwards through
     `subPartitions`/`destructiveSub`/`makeConcrete`) and the `learn` branch of the strict refinement,
     so `step_refines_strict` covers all five branches under `step_refines_all`'s hypotheses; and C2's
     vocabulary lemma for `learn` so `SupOk`/`SupFresh` are preserved by `step` (a learn step may draw
     more than one id — say how many).
R3.5 **The bound.** With R3.1 and R3.4, `hmeas` over the right system is non-increasing at every
     non-minting step and decreasing at every mint that the relation's guard permits; the residual is
     the loop mints the relation's guard would refuse (the `qsys` localisation: the parent-concrete
     case where the queue lookup misses an environment carrier). Bound those separately — each such
     mint names a row the environment already knows, and `QueueHygiene` + the single pass should give
     at most one per (premise, key) — and assemble `Terminates s₀` for every satisfiable `Wf s₀` with an
     explicit bound; or state the exact remaining lemma and hunt a witness (empty-biased seeds, the
     `rowclosure.py` generator, adversarial bases), replaying any candidate through the compiler.

Outcome for R3.5, say which: T1 with a bound / T2 with the missing lemma / W with a compiler replay.
Do not weaken statements silently; if a checkpoint is PARTIAL say so and quantify. Constraints as
always: audit 0 non-standard axioms (3058 theorems / 841 jobs before you), `#print axioms` in scratch
under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r3/`, no `sorry` in a finished module, never `lake exe
cache get`, no new `require`, no new Lean project, never touch `~/research/leanwork`, `CutSearch.lean`
out of the root import list, disk is tight, `pkill -f` matches itself. Traps: `decide` cannot see
through `mk`/`slist` (`simp [vset_mk, ...]` first); no `norm_num`; `Finset.card_insert_of_notMem`;
`Finset.mem_insert` must not share a simp call with `Finset.forall_mem_insert`.

## Report
Append a dated "Round 3" section to `tracker/loopmodel/L5-TERMINATION.md`: per checkpoint the statements
VERBATIM and the outcome; the constructor-use table; the audit/build figures; files with line counts;
what you could not prove, with original and proved statements side by side. Update the plan's L5 row
and the README additively. A reviewer re-runs everything.
