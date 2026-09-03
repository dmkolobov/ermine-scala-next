# Explorer report: additive closure of the shipped row rules on SATISFIABLE input

Task key: explorer.  Date: 2026-09-02/03.  Tool: `tracker/tools/rowclosure.py` (Python 3.12, stdlib only,
1.5k lines, module docstring = manual).  All scratch files under
`/tmp/claude-1000/-home-dmitry-research-ermine/8ad54026-1a3a-4b68-a018-ea52aca01453/scratchpad/satterm/explorer/`
(referred to as `scratchpad/satterm/explorer/` below).  Nothing was committed; `DefaultTerm.lean` was
read, not edited.

## 0. Headline

**The shipped rule set, as the additive relation `Rowpartition.DefaultStep`, does NOT terminate on
every satisfiable input.**  The 2-constraint satisfiable seed

    a <- (e, y, (|1|)),   a <- (e, (|1|))        rho a = {1}, rho e = rho y = {}

has an infinite productive run using only CancelStep, SubstStep and the split MINT (three steps per
level, hand-derived in section 3 and machine-checked step by step).  So `DefaultTerm.TerminatesOnSat`
is false, `DefaultDiverge.Diverges` holds for a satisfiable system, and the obstruction the
orchestrator predicted at step (5) of the König argument is real: one parent (`a`, rank 1) acquires
infinitely many split children (all rank 0), one per group `{u_n, y}`, the groups being manufactured by
substituting the previous mint's name back into a constraint of `a` through an empty-row variable.
The random search finds the same mechanism in ~18% of tiny random satisfiable seeds (empties are
common in the generator), always through an empty-row variable that recurs in every group -- either an
empty of the seed or an EMPTY RESOLVENT minted by guarded resolution when C u D = rho v -- and never
without one (0 of the growing runs have a closure free of empty variables).

Two caveats, both essential.  (i) The run is a legal ORDER of DefaultSteps, but not the one a
breadth-first saturation takes: with all non-generative consequences of a round applied before the
round's mints, the group gets NAMED (`u_n <- (u_n, y)`) in the same round and the mint is blocked; the
explorer's `bfs` strategy reaches a 13-constraint fixpoint on the seed, and only mint-eager orders
(`chase`, and `mintfirst`/`dfs` on the self-partition variants) diverge.  (ii) The REAL loop is not
this relation: `bin/ermine` on the seed written as a signature terminates in 0.07 s; its row trace
shows the mint, the two cancellations, then `empty` (makeEmpty of y) and `unify` (rename e := u_1) --
the deletion/rename layer `Saturate.SatStep` models and the additive relation lacks -- and the
question for the loop is exactly whether those deletions always cut such chains.

## 1. The tool

`tracker/tools/rowclosure.py` -- see its docstring for usage, the seed format, the rule table, the
strategies and what the caps mean.  Summary of what was verified about it:

* Rules: every rule of `DefaultStep` (CutStep.reuse/fold, SplitReuseStep, SplitStep mint, CancelStep,
  SubstStep, SelfSubstStep, CommonPartStep, GResStep.mint/reuse) implemented from its Lean definition
  (read in Cut.lean, SplitNecessary.lean, ResGuard.lean, DefaultDiverge.lean, Divergence.lean for
  `mk`/`vset`/`shared`/`reduce`/`allVars`).  Finset semantics for substitution; `--scala-dedup` adds the
  `w <- ()` emissions of `SatStep.dedup`.  Fresh ids from a counter above every id in use.  Guards
  `Named`/`Resolved` re-checked at the moment a mint is applied.
* Model check: rho is extended at every mint (split child = union of its group, resolution child =
  rho v \ (C u D)) and EVERY inserted constraint is checked against rho; a violation aborts the run.
  No violation occurred in any run reported here (about 60,000 closures).
* Faithfulness/regression: the optimised enumeration of CSE reuse and resolution reuse (per
  conclusion, not per pair x name) was checked against a naive per-pair implementation on 734 closures
  (random seeds, structured families, the three calibration objects) under canonical insertion order:
  identical constraint sets and mint lists, 0 diffs, and every fixpoint re-verified by running every
  rule over the whole system (`fixpoint-UNVERIFIED` never occurred in any run).
* Calibration (section 2): `gSeed` alone under guarded resolution hits the mint cap (400 mints in 0.01 s);
  `CRule.W` hits a cap; `resSeed` reaches a verified 5-constraint fixpoint with one resolution mint.
* Strategies (the relation is nondeterministic; a fixpoint is evidence about the run taken):
  `bfs` (spec), `mintfirst`, `lazy`, `worklist` (one constraint at a time, FIFO, like incorporateAll
  without deletions), `eager`, `dfs`, `random`, `chase` (priority to constraints whose one-step
  substitution yields an unnamed split premise; the one that finds the chains).
* Cost: 20,000 random seeds x 2 strategies with an 8 s per-seed limit took about 35 min wall on 5 workers.
  The per-seed limit matters: the non-generative closure of a 12-variable seed can exceed 20,000
  constraints (substitution composes every definition with every other), and such runs are reported
  as `time`/`con-cap`, NOT as divergence.

## 2. Calibration (task item 6)

