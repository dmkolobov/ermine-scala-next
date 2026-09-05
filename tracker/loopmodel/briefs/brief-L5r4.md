# Brief: L5 round 4 — refute or relativise the residual; discharge the supply invariant; a real mint count

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, clean at `9060fbf`
(rounds 1–3 committed). LEAN ONLY; `bin/ermine`/`tracker/repro/satterm` may replay a witness; no sbt, no
Scala edits, no commits. Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`).

READ FIRST, in order: `tracker/loopmodel/L5-REVIEW.md` — the "Round-3 review — 2026-09-05" section
(S-1…S-12; its F-5, S-11 and S-12 ARE this round's specification), then the earlier sections for
context; `tracker/loopmodel/L5-TERMINATION.md` §R3 (statements verbatim, §R3.5.4 "the mint COUNT as an
explicit open item", §R3.6 the side-by-side table); `tracker/LOOP-MODEL-PLAN.md` (L5 section/row); then
the modules `Loop/{Residual,Carried,Hygiene,Factor,Draws,Strict,StrictStep,StrictBound,RefineLearn,Order,Wf,Step}.lean`
and the library `KeyedRow.lean`/`KeyedEmpty.lean`/`ResGuardTerm.lean`.

## Checkpoints, in order (build and audit green at each; report as you go)

R4.1 **Attack `QStepDichotomy` before relying on it** (review F-5). It quantifies over all `Wf` states,
     and `Wf` is only `QOk + LblCoh`. Either (a) construct a `Wf` state that refutes it, in Lean — then
     relativise: state `QStepDichotomy'` over REACHABLE states (from `Seed.solve`/`Replay`), using the
     invariants round 3 supplied (`QueueHygiene`, `NoSelfUnif`, `NoInfRow`, `Carried`-preservation),
     and re-prove `run_qsys_bound` from it; or (b) prove it as stated. Say which, with the state or the
     proof. Do not proceed to R4.3 on an unexamined dichotomy.
R4.2 **Discharge `RunSupOk`.** Prove `SupOk`/`SupFresh` preserved by `step` (the `learn` vocabulary
     clause proper — every variable of `sys s'` is old or one of the ≤ 1+|proc| drawn ids, each drawn id
     fresh; `learnPartitions_drawn` and `Draws.lean` are the start), so `run_queueHygiene` and the panic-
     unreachability corollary become UNCONDITIONAL from `Seed.solve` states (and from `Replay` states
     via the `sin` record's bounds). This makes stage B1's certification a theorem with no hypothesis.
R4.3 **A real mint count.** Choose and justify a carrier notion that is monotone along the loop's actual
     steps (review S-11's dilemma: a monotone carrier gives preservation free but breaks the guard
     identification; `qsys` gives the guard and breaks preservation at eliminations). Add the
     productivity condition to the minting constructor (as `K2StarLoopRun.tail` has), define the count of
     minting steps along a run, and prove `mints ≤ f(s₀)` for satisfiable `Wf s₀` — or the exact lemma
     that blocks it, with a witness hunt aimed at that lemma, candidates replayed through the compiler.
R4.4 If R4.1–R4.3 close: assemble `Terminates s₀` with the explicit bound (the order lemmas, the single
     pass, the mint count, `forms`), for every satisfiable `Wf s₀`. Outcome T1 / T2 (missing lemma) / W.

Constraints as before: audit 0 non-standard axioms (3186 theorems / 846 jobs before you), `#print axioms`
in scratch under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r4/`, no `sorry` in a finished module, no
silent weakening (side-by-side table), never `lake exe cache get`, no new `require`, no new project,
never touch `~/research/leanwork`, `CutSearch.lean` out of the root import list, disk tight, `pkill -f`
matches itself. Traps: `decide` cannot see through `mk`/`slist`; no `norm_num`;
`Finset.card_insert_of_notMem`; `Finset.mem_insert` not with `Finset.forall_mem_insert`.

## Report
Append a dated "Round 4" section to `tracker/loopmodel/L5-TERMINATION.md` (statements verbatim, outcomes,
the side-by-side table for anything weakened, audit/build figures, files with line counts); update the
plan's L5 row and the README additively. A reviewer re-runs everything.
