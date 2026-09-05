# Brief: L3 — theorems about the loop model

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`. LEAN ONLY (no Scala
edits, no sbt); `bin/ermine` and the repro harness may be used to replay a witness. Lean project
`tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); Scala toolchain for replays
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`.
The tree may carry uncommitted L2 files; touch only your own new modules, `tracker/lean/Rowpartition.lean`
(import lines), additive edits to `tracker/lean/README.md`, the plan's L3 row, and your report.

READ FIRST: `tracker/LOOP-MODEL-PLAN.md` (L3's acceptance criteria (i)–(iv) are the contract; the
"Known scope limits" section), `tracker/loopmodel/L1-MODEL.md` (the model; §3 dequeue order; §8
correspondence), `tracker/loopmodel/L1-REVIEW.md` (F6: the bridge's `Nodup` hypotheses have no
invariant tying them to `step`), `tracker/loopmodel/L2-CORPUS.md` and `L2-REVIEW.md` (what the
model is now KNOWN to reproduce, and its abstractions), then the Lean: `Rowpartition/Loop/State.lean`,
`Queue.lean`, `Rules.lean`, `Step.lean`, `Bridge.lean` (the map to `Rowpartition.Constraint`; its
hypotheses `Nodup…`, `LblCoh`), and the relation library the model must refine:
`Rowpartition/KeyedRow.lean` (`K2SplitStep`, `K2ResStep`, `K2StarLoopStep`, `concretizeSrs`,
`Carried`, `hmeas`, `mintsBoundedOnSatKeyed2Star`), `KeyedEmpty.lean` (`makeEmptyD`, `makeEmptyE`,
`K3LoopStep`, `mintsBoundedOnSat_emptyPersisting`, `mintsBoundedOnSatKeyed3E`), `KeyedSplit.lean`,
`ResGuardTerm.lean` (`gmeas`), `Saturate.lean` (`SatStep`, incl. `rename`), `NameLoss.lean`,
`DefaultTerm.lean` (vocabulary/forms bounds), and the README's module map. Also
`tracker/TICKET-sat-termination.md` §3e–§3i and `tracker/satterm/KEYED-EMPTY-STAGE7B.md` §3 (the
queue-GC mechanism, for (iii)).

## Deliverables, in this order (each is a checkpoint; write the report as you go)

### (iv) Well-formedness — first, because everything else stands on it
Define `Wf : State → Prop` collecting every hypothesis `Bridge.lean` needs (`Nodup` of the queues
and sets, `LblCoh`, and whatever else the bridge's lemmas assume), prove `Wf` for every state the
model can start from (`Seed.lean`'s construction and `Replay.lean`'s reconstruction), and prove
`step_wf : Wf s → step s = .continue s' → Wf s'`. Then restate the bridge's results for reachable
states with no side hypotheses. If some hypothesis is NOT preserved, that is a finding about the
model or the bridge: report it, do not weaken `Wf` silently.

### (i) Refinement — the model's steps are runs of the relations
Define `sys : State → System` (the abstract constraint set a state denotes: the queues' partitions
plus the environment's facts — decide and JUSTIFY how empty/concrete/alias bindings are represented
as constraints; `makeEmptyE`'s "retain `v <- ()`" is the precedent) and prove, for `Wf s`,
`step s = .continue s' → LoopRel* (sys s) (sys s')` for a relation `LoopRel` you assemble from the
EXISTING constructors (`K2StarLoopStep`, `makeEmptyD`/`E`, `concretizeSrs`, the non-generative
rules) plus whatever the loop does that no relation has — name each new constructor (candidates:
`unify`'s rewrite-and-remove, the `common` redirect, `trim`/`++!` dedup as no-ops on sets, `dedup`'s
`w <- ()`, resolution's/split's fresh-name draws from the Supply) and prove its SOUNDNESS
(`SModels rho G → SModels rho G'`, one direction, as the deleting steps have). Corollaries:
`step` preserves satisfiability along `continue`; and for the `died` cases that are refutations
(`labelClash`, the merge/duplicate-field deaths, `ensureSuperset`, the `Incompatible
instantiations` death), `died` implies the INPUT system has no model — prove which deaths are
refutations and list any that are not (the skolem refusal is a kinding error, not a refutation:
say so). Adequacy of the whole model is then: every `continue` step is sound, every refuting
`died` is sound.

### (ii) Termination — the theorem this programme exists for
State `Terminates s₀ := ∃ n, run s₀ n ≠ .fuelOut` (iterated `step` reaches `done` or `died` within
`n` steps) and prove it for every `Wf s₀` whose `sys s₀` is satisfiable — with an explicit bound if
you can (the shape to try: each dequeue removes one partition and the enqueued derivations are
bounded by a mint budget — `hmeas`/`gmeas` from the relation library — plus the finite vocabulary
(`DefaultTerm.forms`); the four order properties are now LEMMAS about `step`: single pass (a
processed partition is never re-dequeued unless a rule re-derives it and `trim` lets it through —
prove exactly when), eager `makeEmpty`, eager `unify`, name travel). Outcomes, say which:
(T1) proved with a bound; (T2) proved under a stated extra hypothesis, or a partial bound, with the
missing lemma named exactly and why it resists; (W) a witness `Wf s₀`, satisfiable, on which `run`
exhausts any fuel — then replay it through the COMPILER (`tracker/repro/satterm/run.sh` with a `json:`
seed built from `s₀`) and report whether the compiler hangs, which would be a real bug, or
diverges from the model, which would be an L2 gap. Unsatisfiable input is OUT of scope (every
relation bound needs a model; `not_CRule` stands) — but state whether `step` can loop on it.

### (iii) The Stage 7b question, as a lemma about the loop
Stage 7b's variant (reuse if it adds a fact, else the shipped mint) re-opens the empty-row loophole in
the ANY-ORDER relation because the same premise pair can fire again after its conclusions are
absorbed. In the loop, prove or refute: a premise pair `(v <- (x, C), v <- (y, D))` is examined by
`resolution` at most once per solve unless one of the two is re-derived and passes `trim` — and
whether a re-derivation of an identical partition can pass `trim`. That lemma, plus the single-pass
lemma from (ii), decides whether the variant's mint can chain in the loop. Report the answer with
its scope (the model has flag `emptyRow`; the variant itself is in the `emptyrow-profiling`
worktree, not in the model — if a faithful answer needs the variant modelled, say so rather than
model it here).

## Constraints
`lake build Rowpartition` green and `lake env lean Audit.lean` ending in `declarations using a
non-standard axiom: 0` at every checkpoint (2530 theorems / 833 jobs before you — record the new
figures); `#print axioms` for every headline theorem in a SCRATCH file under
`/home/dmitry/.claude/jobs/880c725d/tmp/L3/`, never in a module; no `sorry` left in a committed-shape
module (a checkpoint with `sorry` may be reported as PARTIAL, but say so and quantify); never
`lake exe cache get`, no new `require`, no new Lean project, never touch `~/research/leanwork`,
`CutSearch.lean` stays out of the root import list; disk is tight; no commits; `pkill -f` matches
itself. Traps: `decide` cannot see through `mk`/`slist` (`simp [vset_mk, ...]` first); no `norm_num`;
`Finset.card_insert_of_notMem`; `Finset.mem_insert` must not share a simp call with
`Finset.forall_mem_insert`.

## Report
`tracker/loopmodel/L3-THEOREMS.md` (write EARLY, keep current): for each of (iv), (i), (ii), (iii)
the statements VERBATIM, the outcome (proved / partial with the missing piece / refuted with the
witness and its compiler replay), the new relation constructors with their soundness lemmas, the
list of `died` paths and which are refutations, the audit/build figures, files with line counts,
and anything you could not prove, stated plainly with original and proved statements side by side
if you weakened anything. Update the plan's L3 row and the README additively.
