# The loop model: making the Lean and the compiler agree

Started 2026-09-04. Owner of the plan: the orchestrating session; every stage is implemented by
one agent and reviewed by another, against the acceptance criteria written here BEFORE the stage
starts. Nothing advances on an implementer's word alone.

## Why

Every termination result in `tracker/lean/Rowpartition/` is about a RELATION: the rule set
applied in any order, with one or two of the loop's deletions added. Every measurement is about
`Constraints.incorporateAll`, which applies the rules in ONE order with four properties no relation
states — single pass over each partition, eager `makeEmpty`, eager `unify` of singleton links,
names travelling with their groups. Stages 3–7b of `TICKET-sat-termination.md` show the cost of
that gap in both directions: the relations diverge where the loop does not (W3, W4, G7), and a
rule the relations prove bounded (Stage 7's `emptyRow`) is 1.9× slower in the loop because the
mint it suppresses was the queue's only garbage collector (Stage 7b). The transcription modules
(`KeyedSplitScala`, `KeyedRowScala`, `KeyedEmptyScala`) connect single rule branches to the
relations, but the connection between the Scala and the Lean is still made BY READING.

The goal: a Lean model of the loop itself, tested against the compiler by trace over the whole
corpus, with the theorems proved about that model, and the trace test kept in `core/test` so the
two cannot drift apart silently.

## The stages

### L1 — the loop as a Lean FUNCTION (not a relation)

State: the two queues in their REAL order (the priority-search finger tree keyed by `PSQK` and
popped through `TypeVarGraph` — `Constraints.Q`, ≈ lines 403–640), the substitution environment
(`SubstEnv`: empty / concrete / alias bindings), the id supply, and the trace emitted so far.
`step : State → StepResult` (continue / done / died-with-message) dispatches exactly as
`incorporateAll` does (≈ line 1109): common partition → `unify`; `RHSEmpty` → `makeEmpty`;
`RHSConcr` → `makeConcrete`/`destructiveSub` (keepDefs, `srs`); singleton → `unify`; otherwise
`learnPartitions` folding the rules over `proc` under the SHIPPED flags (`cut`, `labelCheckEarly`,
`resGuard`, `splitKey`, `splitRow`, `resRow`; `emptyRow` OFF), then `trim`/`++!`. All definitions
computable (no `Classical`, no `sorry`, no `partial` without a fuel argument); an executable
`looptrace` that reads a `json:` seed (the `tracker/repro/satterm` / `rowclosure.py` format) plus
an id base and prints a trace in the `-Dermine.rowTrace` TSV format.

Acceptance: (a) `lake build Rowpartition` and the audit green; (b) the module reuses
`Rowpartition.Constraint`/`mk`/`vset` so later refinement proofs connect; (c) for the six tracked
seeds (`W2`, `H2`, `NE6`, `W3`, `W4`, `G7`) at ten id bases each, the Lean trace and the Scala
trace agree step for step after id/label normalisation, OR every disagreement is listed with its
cause in the report; (d) a written table, Scala function → Lean definition, covering every
function `incorporateAll` reaches, with "not modelled" entries stated (e.g. skolem checks,
`Located` errors) and why they do not matter for the seeds.

### L2 — trace equivalence over the corpus

A harness (`tracker/tools/looptrace-diff.py` + a Scala dump of every solve's input at its id
base, or a `rowTrace` extension that records the input system and base) that runs the Lean model
on EVERY solve segment of the 110-module example corpus and the 129-module stdlib boot, diffs
against the compiler's trace, and classifies mismatches. Batch mode makes the compiler side
minutes. Acceptance: 0 unexplained mismatches over both corpora, with every explained class
either fixed in the model or recorded as a deliberate abstraction with its scope (e.g. "the
model does not check skolems; no corpus solve reaches that branch"). Random systems from
`rowclosure.py`'s generator at 2,000 seeds, same criterion.

### L3 — theorems about the model

(i) Each `step` is a composite of relation steps already in the development (refinement:
`step s = s'` → the systems are related by a run of `K2StarLoopStep ∪ makeEmptyD ∪ unify-step`),
which transfers soundness. (ii) TERMINATION of iterated `step` on satisfiable input — the
theorem this whole programme is for — with a measure over queue content and mints; the four
order properties are now lemmas about `step`, not hypotheses. (iii) The Stage 7b question:
with the single pass built in, does the fallback mint chain? (iv) The state invariants the
bridge assumes (`Loop/Bridge.lean`'s four `Nodup` hypotheses, L1 review F6, and the `LblCoh`
hypothesis added in L2, L2 review F5) are proved preserved by `step` from every initial state
`Seed`/`Replay` builds, so the bridge applies to every reachable state. Acceptance: (i)
and (ii) proved or refuted with a witness the compiler reproduces; (iii) decided; (iv) proved;
audit green.

### L4 — the trace test in `core/test`

A ScalaCheck property: generated systems + the tracked seeds, run through `Subst.solve` with
the trace on and through the Lean model (via the `looptrace` executable, or a Scala port of
the model checked against it), traces equal. Acceptance: the property runs in the ordinary
`core/test`, fails on an injected divergence (positive control), and `tracker/lean/README.md`
records that a solver change must keep it green.

### L5 — the tighter relation and the loop-level mint bound (split out of L3 on 2026-09-04)

L3 proved (iv), (i) for every branch (`step_refines_all`), and (iii); (ii) is neither proved nor
refuted, for a structural reason the L3 review established: the refinement relation `LoopRel` has a
`weaken` constructor admitting arbitrary deletion, so no measure is monotone along its runs and none
of the library's mint bounds (`hmeas`, `gmeas`) transports. The L3 report's R2.5 catalogue lists the
six loop deletions that `weaken` stands for, with the Scala each must model (the `empty` dequeue,
which is `makeEmptyE` up to the `++!` redirect; the `concrete` dequeue, which is `concretizeSrs` up
to `keepDefs` and `can`; the dequeue drop; the queue drops; `instantiate`'s removal; the `unify`
site). L5 is: define `LoopStrict` with exactly those deletions as constructors, re-prove
`step_refines_all` against it, and then prove the loop-level mint bound — or produce a satisfiable
well-formed witness on which `run` exhausts any fuel, replayed through the compiler.

Acceptance: `LoopStrict` has no arbitrary-deletion constructor; every `step` refines it under the
same hypotheses as `step_refines_all`; either `Terminates s₀` for every satisfiable `Wf s₀` with an
explicit bound (the order properties, already lemmas, plus a mint budget that survives the six
deletions), or a compiler-reproduced witness; audit green. Expected to take more than one round;
the reviewer's §6d is the starting analysis.

## Review protocol (every stage)

A second agent, briefed with the stage's brief, its report and `git diff`, and told to trust
nothing it has not re-run: rebuild, re-audit, re-run the differential traces, read the Scala
and the Lean side by side for every dispatch branch and rule, and look specifically for
`Classical`/`sorry`/`partial`/unstated fuel, order differences, and "not modelled" entries that
matter. Findings ranked, each with CONFIRMED (re-run) or PLAUSIBLE (read only). The orchestrator
sends confirmed findings back to the implementer; a stage advances only when the reviewer's
list is empty or every remaining item is recorded in the report as accepted scope.

### Known scope limits carried by every later stage
* The trace-equivalence population is the SERIALIZED loader (`-Dermine.loadInSeries=true`). The
  parallel loader — the shipped path — interleaves records of concurrent solves; gu05's
  1,372-partition solve exists only there. Closing it needs a thread id on every trace record
  and a segmenter that uses it (candidate L4 item). **PARTIALLY CLOSED by L4 (2026-09-04)** —
  the MECHANISM exists and works, the POPULATION has not moved: every
  `RowTrace` record ends with a thread id, `looptrace-diff.py --demux` regroups a parallel
  trace so each solve's records are contiguous, and `Ai` (83,942 segments, 12 threads) and
  `incomplete/gu05` (54,235 segments, 12 threads, including the 458-partition solve that the
  serialized loader never produces) both replay and agree completely. Still open within it:
  the parallel sweep is **2 of the 8 corpus groups**, and its `incomplete` half is one FILE
  (`gu05`), not the group; `looptrace-corpus.sh` still DEFAULTS to `LOOPTRACE_SERIES=true`, so
  the routine population remains the serialized loader; its per-file TIMEOUT cut (`incomplete/`)
  cuts at the last `sin` regardless of thread, which is only safe for a serialized trace
  (it fails LOUDLY if it ever fires — see `L4-TEST.md`); and `looptrace --replay` still cannot
  demultiplex, so the regroup is an external step a future runner has to remember. (L4 review,
  F3: do not read this bullet as closed.)
* `Disjunction` is covered by seeds only; a corpus sweep with it on finishes on neither side.
* `emptyRow` (default off): the model's per-solve environment misses carriers the compiler's
  whole-inference environment has (M4, 37 segments).
* Building the initial queue from a raw constraint list is not under corpus test: non-partition
  elements' hash/equals classes are taken from the trace (L2 review F3).

## Status

| stage | implementer | reviewer | state |
|---|---|---|---|
| L1 | agent (2026-09-04) | agent (2026-09-04), three rounds | **ADVANCED 2026-09-04.** `tracker/lean/Rowpartition/Loop/` (13 files) + `lake exe looptrace` + `tracker/tools/looptrace-diff.py`; reports `tracker/loopmodel/L1-MODEL.md`, `L1-REVIEW.md`. Final: 1,301 trace comparisons (6 tracked + 11 regression seeds + two fuzzes) and 2,572 hash-set-level JVM comparisons, 0 differing; build 832, Audit 2508/0. Review found and fixed two CHAMP-semantics bugs (sub-node inlining on removal; both early returns of `concat`). Carried forward: F6 → L3 (iv); F7 (`V.ty` inferred from id) → L2 blocker. |
| L2 | agent (2026-09-04) | agent (2026-09-04): FIX-THEN-ADVANCE, no correctness defect, eight documentation findings, all applied | **ADVANCED 2026-09-04.** Every SERIALIZED corpus solve (stdlib boot + 110 examples: 26,864 row-carrying segments, 12,310 distinct solves, the boot at 42 id bases) and 2,000 random systems replay byte for byte at the compiler's ids; 920,611 segments re-run by the reviewer. `RowTrace` gained four inert replay records (`sin`/`slbl`/`svar`/`scon`); model gaps fixed: `makeEmpty`'s skolem refusal, `Supply`'s block boundary; accepted: M4 (`emptyRow` only). Reports `tracker/loopmodel/L2-CORPUS.md`, `L2-REVIEW.md`. Build 833, Audit 2530/0. |
| L3 | agent (2026-09-04), two rounds | agent (2026-09-04), three sections | **ADVANCED 2026-09-04, with (ii) carried forward as L5.** (iv) `Wf` PROVED (closes L1 F6, L2 F5); (i) PROVED for every branch: `step_refines_all` under the shipped-off flags (`emptyRow`, `disjRule`, `cseMints`) and the supply invariants `SupOk`/`SupFresh` (satisfied by every replay state), all ten `LoopRel` constructors live, both minting rules inside the theorem, the `¬Named` guard discharged; 4 of 7 deaths proved refutations, 3 classified as not; (iii) DECIDED — trim refuses what proc holds, both of escape 1's premises PROVED (`NoSelfUnif`, and `NoInfRow` after the re-review's R-B — the four-writer argument, no order reasoning needed), leaving only the seven-way rule case analysis of `learn_no_self_rederive`; escape 2 benign on the compiler (seed c012); (ii) NOT proved: the six residual `weaken` sites (R2.5) are the `LoopStrict` spec. Modules `Loop/{Wf,Order,Refine,RefineConcrete,RefineLearn}.lean`; reports `L3-THEOREMS.md`, `L3-REVIEW.md`. Closing items R-A (the sixth `weaken` row, the `unify` branch), R-C (the summary now says `SupOk`/`SupFresh` are per-state hypotheses carried by `RunSupOk`, not an invariant) and R-B done. Build 838, Audit 2935/0, 0 `sorry`, 31 headline theorems on standard axioms. |
| L4 | agent (2026-09-04), two rounds | agent (2026-09-04): F1 CONFIRMED and fixed, final ADVANCE | **ADVANCED 2026-09-04.** `core/test` carries `TestLoopTrace`: a child JVM runs the shipped `Subst.solve` at exact id bases on 17 tracked seeds × 6 bases + 600 generated satisfiable systems (702 solves, ~3 s), compared record for record with `lake exe looptrace`; rule switches `-Dermine.*` forwarded to both sides (ten settings 702/702; `disjunction=true` fails loudly as the compiler child does not finish); two positive controls asserted non-vacuously; a missing Lean binary SKIPS, every compiler-side failure FAILS. Trace records carry a thread id; `--demux` regroups parallel-loader traces; `Ai` and `gu05` under the parallel loader replay and agree incl. gu05's 458-partition solve. core/test 913/914 (the known starvation). Reach: 9 of 16 `Inference` kinds fire in the property (`ResolutionRow`, `PartitionEmpty`, `CommonPartition`, `Disjunction` never; corpus sweep for those). Reports `L4-TEST.md`, `L4-REVIEW.md`. |
| L5 | agent (2026-09-04), two rounds | agent (2026-09-04): round 1 FIX-THEN-ADVANCE (deletions admitted growth; weaken reached transitively), round 2 ADVANCE with the remaining work carried forward; new obstacle R-4 (`requeue`'s licence is semantic, so `Carried` is not preserved and `hmeas` can increase along a legal step) | **ADVANCED 2026-09-04 with (ii) STILL OPEN.** `Loop/{Strict,StrictStep,StrictBound}.lean`: `LoopStrict` with the library operators as deletions (`substOut`, `makeEmptyE`, `concretizeSrs`, `drop`, `requeue`), vocabulary bound PROVED (`LoopStrictSteps.allVars_card_le`: +m over m minting steps), refinement weaken-free (reviewer's Deps.lean: 23 roots clean) for 3 of 5 branches, `step_empty_makeEmptyE`, `QueueHygiene` + `queueHygiene_no_rebind` (the panic is unreachable under it; the invariant is false for the unfixed model — B1), localisation theorems. Carried forward, in priority: R-4 (syntactic `Carried` conjunct on `requeue` or dissolve it), make `step_empty_makeEmptyE` load-bearing and widen `substOut` with the dedup fact, `QueueHygiene` preservation after B1, `concrete`/`learn` branches and C2, then the mint bound. Termination is NOT proved. Build 841, Audit 3058/0. Reports `L5-TERMINATION.md`, `L5-REVIEW.md`. |
| B1 | agent (2026-09-04), Parts A+B | agent (2026-09-04): ADVANCE | **ADVANCED 2026-09-04 (commit pending the user's word).** `makeEmpty`'s propagation excludes the emptied variable (`(abstr - v)`, as `selfSubstitution` already did); mirrored in `Loop/Step.lean`, six proof sites moved, `makeEmpty_aux_excludes_self`. Gates: PANIC3 89/11 → 100/100; the 14 hunt seeds 866/534 → 1400/0; the reviewer's RS5 (satisfiable, rejected at 100% of bases before) fixed; the other 17 seeds byte-identical; corpus verdicts identical and the full 66-file row trace (363,570 records) BYTE-IDENTICAL pre/post; .ei 0 weaker; TestLoopTrace 708/708 with PANIC3; L1/L2 replays agree (7 corpus groups, 450,064 segments); core/test 913/914; the alias form of the same die has no path after the fix (6,000 alias-biased solves). The premise shape occurs in the shipped stdlib (`Layout/Report.e`) but is dissolved by `selfSubstitution` first. Reports `B1-FIX.md`, `B1-REVIEW.md`; ticket item 11. |

Constraints throughout: the tree carries uncommitted Stage 7 work (`git status`); agents touch
only their own new files plus the root import line; no commits by agents; disk is tight (no
`lake exe cache get`, no new `require`, no new Lean project); one sbt at a time, never during a
`bin/ermine` sweep.
