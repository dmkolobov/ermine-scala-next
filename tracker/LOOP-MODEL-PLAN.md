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
bridge assumes (`Loop/Bridge.lean`'s `Nodup` hypotheses, L1 review F6) are proved preserved by
`step` from the initial state, so the bridge applies to every reachable state. Acceptance: (i)
and (ii) proved or refuted with a witness the compiler reproduces; (iii) decided; (iv) proved;
audit green.

### L4 — the trace test in `core/test`

A ScalaCheck property: generated systems + the tracked seeds, run through `Subst.solve` with
the trace on and through the Lean model (via the `looptrace` executable, or a Scala port of
the model checked against it), traces equal. Acceptance: the property runs in the ordinary
`core/test`, fails on an injected divergence (positive control), and `tracker/lean/README.md`
records that a solver change must keep it green.

## Review protocol (every stage)

A second agent, briefed with the stage's brief, its report and `git diff`, and told to trust
nothing it has not re-run: rebuild, re-audit, re-run the differential traces, read the Scala
and the Lean side by side for every dispatch branch and rule, and look specifically for
`Classical`/`sorry`/`partial`/unstated fuel, order differences, and "not modelled" entries that
matter. Findings ranked, each with CONFIRMED (re-run) or PLAUSIBLE (read only). The orchestrator
sends confirmed findings back to the implementer; a stage advances only when the reviewer's
list is empty or every remaining item is recorded in the report as accepted scope.

## Status

| stage | implementer | reviewer | state |
|---|---|---|---|
| L1 | agent (2026-09-04) | agent (2026-09-04), three rounds | **ADVANCED 2026-09-04.** `tracker/lean/Rowpartition/Loop/` (13 files) + `lake exe looptrace` + `tracker/tools/looptrace-diff.py`; reports `tracker/loopmodel/L1-MODEL.md`, `L1-REVIEW.md`. Final: 1,301 trace comparisons (6 tracked + 11 regression seeds + two fuzzes) and 2,572 hash-set-level JVM comparisons, 0 differing; build 832, Audit 2508/0. Review found and fixed two CHAMP-semantics bugs (sub-node inlining on removal; both early returns of `concat`). Carried forward: F6 → L3 (iv); F7 (`V.ty` inferred from id) → L2 blocker. |
| L2 | agent (2026-09-04) | — | LAUNCHED; brief `tracker/loopmodel/briefs/brief-L2.md` |
| L3 | | | |
| L4 | | | |

Constraints throughout: the tree carries uncommitted Stage 7 work (`git status`); agents touch
only their own new files plus the root import line; no commits by agents; disk is tight (no
`lake exe cache get`, no new `require`, no new Lean project); one sbt at a time, never during a
`bin/ermine` sweep.
