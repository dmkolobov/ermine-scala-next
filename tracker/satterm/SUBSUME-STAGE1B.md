# SUBSUME-STAGE1B — the rejection path: the loop model on unsatisfiable inputs

Stage S1b of the `subsume-termination` programme (`tracker/PROMPT-subsume-termination.md`,
brief `tracker/satterm/briefs/brief-S1b.md`).  Lean prover, worktree
`~/research/ermine/ermine-scala-wt-subsume-s1b`, branch `subsume-s1b`.  Nothing is committed.

**S0 was still the 82-byte stub while this stage's Lean was written**, so every theorem below
was proved from the Scala, the loop model and the existing tree, with no input from it.  S0's
report appeared (partially -- §§0-3 written, §§4-6 not yet) while this document was being
drafted; §7 reconciles the two, and the two agree.  Nothing in §§1-5 was changed after reading
it.

---

## 0. The answer, in the shape the programme asks for

| question | answer |
|---|---|
| Does the row solver's **loop** terminate on this (unsatisfiable) input? | **BOUNDED** — `budgetSP_terminates`: under the shipped draw budget every solve stops, whatever the dequeue order, with S2 layer (i) ON.  Unbudgeted (`-Dermine.dequeuePolicy=shipped`, which turns the budget off) there is still NO termination theorem, and D1 measured real divergence. |
| Does the rest of **`Subst.solve`** terminate — the pre-loop checks and the post-loop ones? | **YES** for the row fragment — `solveSeedP_terminates`: `buildQueue`, `topNormalise`, `labelCheckEarly`, layer (iii)'s `labelDecide` (its own two node budgets) and the late `labelClash` are TOTAL functions of the model; the loop is the only layer that can fail to stop. |
| Can the loop leave an **enormous `SubstEnv`**? | **In TERM SIZE, no, unconditionally** — `envTermSize_eq_len`: every entry the loop writes is exactly ONE type node, so the range's total size IS its cardinality.  **In CARDINALITY, at most one entry per dequeue** (`runsP_env_len_le`) — and the dequeue count has NO a-priori bound (`TerminatesBP` is `∃ n`; §R8.6b is open), so this half is a rate, not a ceiling.  The formula is in §4. |
| Is a **cyclic binding** reachable (H2's upstream cause)? | **NO, under three named side conditions** — `stepP_noAliasChain` is per step; the run-level `runsP_noAliasChain` carries `stepP_queueHygiene`'s own hypotheses (`disjRule = false` and the per-state supply invariants `RunSupOkP`, which `Hygiene.run_queueHygiene` carries for the same reason and which is not discharged here).  Under them no alias points at a bound variable, so `noAliasChain_no_cycle` says no variable reaches itself through any chain.  And the walk at `:648` does not follow bindings anyway. |
| Then where **can** an enormous `hm.types` come from? | The general `instantiateType`, not the row solver — `SubstBlowup.chain_blowup`: `n` unifications, `n+1` bindings, every occurs check passed, no cycle, no bound variable in the range, and one entry of `2^(n+1) − 1` nodes. |

Hypotheses: **H2 is refuted for this path**, **H3's "diverges before `subsumeType`" is refuted
for the row solver under the shipped defaults** (and its "grows the environment" half is
bounded), and **H1 is not available to the row solver** — `chain_blowup` says what a program
would have to do to get it, and it is not something `incorporateAll` can do.  S0's measurements
(§7) refute H1 and H2 on the B1 input directly, by a different method, and agree.

---

## 1. What was measured (builds, audits, logs)

Everything in this stage is a proof or a build; there is no timing here (a "terminates" claim
is a theorem, per the common brief).  Commands were run from
`~/research/ermine/ermine-scala-wt-subsume-s1b/tracker/lean` with `export PATH=$HOME/.elan/bin:$PATH`.

| command | result | log |
|---|---|---|
| `lake build` (default target `Rowpartition`, with the two new modules imported from `Rowpartition/Loop.lean`) | **Build completed successfully (873 jobs)**, `EXIT=0`, no `error:` line.  **After the review fixes: 873 jobs, `EXIT=0`** (the two added theorems live in the existing two modules, so the job count does not move) | `scratch-subsume/s1b/build-full.log`, `build-full-fix.log` |
| `lake env lean Audit.lean` | **`Rowpartition theorems audited: 4733; declarations using a non-standard axiom: 0`**; **after the review fixes: `4735; … 0`** (+2, the two added theorems) | `scratch-subsume/s1b/audit.log`, `audit-fix.log` |
| `lake env lean <PrintAxiomsS1b.lean>` (44 declarations, **46 after the review fixes** — every definition and theorem in both new modules) | all on `[propext, Classical.choice, Quot.sound]` or fewer; **0 non-standard** | `scratch-subsume/s1b/axioms.log`, `axioms-fix.log` |
| `lake build looptrace` | **Build completed successfully (1670 jobs)**, `EXIT=0`.  The argument that the executable is untouched is the IMPORT GRAPH, not this number: `Loop/Main.lean`'s transitive closure does not contain `Loop.RejectTerm`, `Loop.EnvBound` or `Rowpartition.Loop` (the reviewer re-derived it: 60 modules, none of them these).  The README's own `looptrace` job count is 24 and an earlier draft of this table compared against it wrongly | `scratch-subsume/s1b/build-looptrace.log` |
| `grep -nE "sorry|partial |unsafe |native_decide|^axiom "` over both new files | no hits | — |

The worktree's pre-seeded `.lake` was NOT a full build (30 modules missing, `PolicyStep`,
`PolicyTerm`, `Sound`, `Reject`, `Solve`, `NoFalseAccept`, `TopNormalise`, `Pottier`,
`CutSearch`, `Determined` among them); the dependency build is
`scratch-subsume/s1b/build-deps.log` (`Build completed successfully (871 jobs)`).  Anyone
re-running this stage should expect that build (~25 min on a loaded box), not an incremental one.

**NO EXECUTABLE MODULE WAS CHANGED.**  `Rowpartition/Loop/Main.lean` (the `looptrace` root)
imports `Replay`, `Pump`, `Cycle`, `Depth`, `Policy`, `PolicyReplay` and NOT
`Rowpartition.Loop`, so the two new modules are outside its import graph; no rule, queue
operation, flag default or trace record moved.  This stage is therefore **not** a Tier 1
trigger for the landing.

---

## 2. What was proved

Two new modules.  Every earlier module is unchanged, so nothing proved before is weakened.

### 2.1 `Rowpartition/Loop/RejectTerm.lean` — the budget at the SHIPPED defaults, and the whole of `Subst.solve`

**What the existing theorems guarantee for this solve, cited not re-proved.**
`Loop/Budget.lean`'s `budget_terminates` and `Loop/PolicyTerm.lean`'s `budgetP_terminates`
say: under a DRAW budget `b ≠ 0`, every solve stops, under any dequeue policy, given
`emptyRow = false`, `disjRule = false`, `cseMints = false`, `Wf`, `EnvNodup`, `SupOk`,
`SupFresh`, `QueueHygiene` and both `KDist`s — the last four free at a solve's initial state
(`budgetP_terminates_of_buildQueue`).  The unit is DRAWS, and converting it into a dequeue
bound is `L5-TERMINATION.md` §R8.6b, still open; `TerminatesBP` is an existential over the
fuel, never a formula in the input.

**The gap that was there, and this stage's first finding.**  `budgetP_terminates` also
carries `s.flags.rowSoundBare = false` — S2 layer (i) OFF.  That flag has been **default ON
since 2026-09-06** (`Constraints.GenRules.rowSoundBare`, `A1-ADOPTION.md`; the model's
`Flags.rowSoundBare` defaults `true` as well).  So **at the shipped defaults no termination
theorem covered `runSP`**, which is the driver `PolicyReplay.solveSeedP` runs and therefore the
one every adopted-default corpus replay goes through.  The repair is not a new argument — layer
(i) is a pre-check that can only turn a continuation into a death — but it did have to be made:

| theorem | statement |
|---|---|
| `stepSP_cases (pol) (a) (s)` | `stepSP pol a s = stepP pol a s ∨ ∃ m t, stepSP pol a s = .died m t` — layer (i) either passes, and the step IS the policy loop's, or it dies. |
| `terminatesBP_of_finished_any (n) (a) (s)` | `Finished (runP pol a s n) → Finished (runSP pol d0 b a s n)` — `PolicyTerm`'s lemma with `rowSoundBare = false` DELETED. |
| `terminatesBP_of_over_any (hb0 : b ≠ 0) (k)` | `RunsP pol k a s c t → d0 + b < t.su.drawn → TerminatesBP pol d0 b a s` — likewise. |
| **`budgetSP_terminates`** | `b ≠ 0 → flags.emptyRow = false → flags.disjRule = false → flags.cseMints = false → Wf s → EnvNodup s → SupOk s.su → SupFresh s.su (sys s) → QueueHygiene s → KDist s.incm.elems → KDist s.proc.elems → TerminatesBP pol s.su.drawn b a s`.  **`budgetP_terminates` without its flag hypothesis**: under a draw budget every solve's loop stops, under any policy, with S2 layer (i) ON — i.e. at the configuration the compiler ships. |

| **`budgetSP_terminates_of_buildQueue`** | the initial-state corollary, repaired the same way: `PolicyTerm.lean:1059`'s proof verbatim with `hrs` deleted.  `EnvNodup`, `QueueHygiene` and both `KDist`s are free at a solve's own initial state, so only `Wf`, `SupOk` and `SupFresh` of the built queue remain.  ADDED after the review, which had verified that it elaborates. |

**The whole of `Subst.solve`, not only its loop.**  `PolicyReplay.solveSeedP` is `Subst.solve`
end to end: `buildQueue`, the `topNormalise` rewrite, `labelCheckEarly`'s `labelClash`, layer
(iii)'s `labelDecide`, the loop under the policy and the budget, and the late `labelClash`.

| theorem | statement |
|---|---|
| `seedInit` (def), `seedInit_envNodup`, `seedInit_queueHygiene`, `seedInit_kdist_proc` | the state `solveSeedP` hands the loop, and the three invariants that are free at it. |
| `verdict_ne_fuel_of_finished` | a finished budgeted run is never `.outOfFuel`. |
| **`solveSeedP_terminates`** | `effBudget pol bud ≠ 0 → buildQueue cs su0 = .ok (q0, su0') → topNormalise fl.topNormalise q0 su0' = (q, su1, tn) → fl.emptyRow = false → fl.disjRule = false → fl.cseMints = false → Wf (seedInit ..) → SupOk su1 → SupFresh su1 (sys (seedInit ..)) → KDist q.elems → ∃ fuel, (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict ≠ "FUEL"`. |

The layers around the loop need no termination hypothesis of their own **because each is a
total function in this model**: `Loop/Decide.lean`'s `propagate`, `searchLabel`, `decideLabel`
and `labelDecide` are structurally recursive, with `Flags.rowSoundBudget` (200,000 nodes per
label) and `.rowSoundSolveBudget` (1,000,000 per solve) as the Scala has them, and
`Json.labelClash` / `topNormalise` are folds.  That the model is the compiler is L2's business:
2,355,430 corpus solve segments, 0 mismatches, at the flags OFF and again under the policy.

### 2.2 `Rowpartition/Loop/EnvBound.lean` — the environment, the walk over it, and the cycle question

| theorem | statement |
|---|---|
| `stepP_env_len_le` | `stepP pol aux s = .continue s' → s'.env.binds.length ≤ s.env.binds.length + 1` — one dequeue binds at most one variable (the `concrete` and `learn` branches write nothing). |
| **`runsP_env_len_le (n)`** | `RunsP pol n a s c t → t.env.binds.length ≤ s.env.binds.length + n`. |
| `EnvVal.termSize`, `envTermSize` (defs) | the size in type nodes of what `instantiateType` is handed, and its total over the environment. |
| **`envTermSize_eq_len (e)`** | `envTermSize e = e.binds.length` — **the range's total term size IS its cardinality**, because the loop's only two writes, `VarT(u)` (`Constraints.scala:2139`) and `ConcreteRho(∅)` (`:2191`), are single nodes. |
| `runsP_envTermSize_le (n)` | `RunsP pol n a s c t → envTermSize t.env ≤ envTermSize s.env + n`. |
| `envTermSize_le_card` | `InVoc V s → EnvNodup s → envTermSize s.env ≤ V.card` (through `NoConc.env_len_le_card`). |
| `escWalk` (def), `escWalk_length_le` | `(escWalk sks e).length ≤ e.binds.length`.  **SCOPE, and it is narrower than an earlier draft of this report said:** `escWalk` models the `fskvs` HALF of `:648` only (`mapHasTypeVars.vars` folds over the map's VALUES, `Type.scala:771`); the `kindVars` half (`Subst.scala:169`, through `Kind.scala:132-134`) is NOT modelled, because `EnvVal` carries no kind component — and that is the half Part B's jstack sits in and the half S0's 35,921-node measurement is about.  The theorem bounds the ANSWER's length (it is `List.length_filterMap_le`), not the walk's cost, and there is NO equivalence theorem tying `escWalk` to `:648`.  The honest cost statement for the loop's entries is `envTermSize_eq_len` plus the `EnvVal` faithfulness note (`Loop/State.lean` §6): one node per entry leaves nothing to recurse into. |
| `runsP_escWalk_le (n)` | `RunsP pol n a s c t → (escWalk sks t.env).length ≤ s.env.binds.length + n` — the same bound along a run, with the same scope. |
| `SubstBlowup.size_bal`, `mentions_bal`, `subst1_bal`, `chain_keys`, `chain_values`, `chain_head`, `chain_head_mem` | the ingredients: a balanced tree of depth `d` has `2^(d+1) − 1` nodes and mentions only its leaf variable; binding `k ↦ app (var (k+1)) (var (k+1))` maps `bal k d` to `bal (k+1) (d+1)`; the chain's keys are `List.range (n+1)` and its values are balanced trees over the one variable it has not bound. |
| **`SubstBlowup.chain_blowup (n)`** | `((chain n).map Prod.fst).Nodup ∧ (chain n).length = n + 1 ∧ (∀ p ∈ chain n, ∀ w, Ty.mentions p.2 w → w ∉ (chain n).map Prod.fst) ∧ (∃ p ∈ chain n, p.2.size + 1 = 2 ^ (n + 1))` — **the H1 witness for the general `instantiateType`.** |
| `AliasEdge`, `NoAliasChain` (defs) | `(v, alias u) ∈ env.binds`; and the invariant *no alias points at a bound variable*. |
| `aliasEdge_source`, `noAliasChain_no_two` | the source of an edge is bound; two edges never compose. |
| **`noAliasChain_no_cycle`** | `NoAliasChain e → ∀ v, ¬ Relation.TransGen (AliasEdge e) v v` — **no variable reaches itself through any chain of bindings**, self-loop included. |
| `noAliasChain_of_binds_nil` | vacuous at `env = {}`, i.e. at every state `Seed.solve`/`Replay` builds. |
| `noAliasChain_instantiate` | `NoAliasChain e → (∀ u, val = alias u → e.contains u = false ∧ u ≠ v) → NoAliasChain (e.instantiate v val)`.  `e.contains v = false` is NOT needed — a first version assumed it and Lean reported it unused. |
| `unifyVars_env_ne` | `unifyVars` either leaves the environment alone or binds an unbound `v` to a DIFFERENT `u` (the disequality `StrictBound.unifyVars_env` does not state). |
| **`stepP_noAliasChain`** | `QueueHygiene s → NoAliasChain s.env → stepP pol aux s = .continue s' → NoAliasChain s'.env` — the invariant is preserved by every `continue` step, at every policy.  **This is a ONE-STEP statement.** |
| **`runsP_noAliasChain (n)`** | `s.flags.disjRule = false → RunSupOkP pol a n s → QueueHygiene s → NoAliasChain s.env → RunsP pol n a s c t → NoAliasChain t.env` — the run-level reading, ADDED after the review, **with its side conditions named**.  The composition is not free: `PolicyStep.stepP_queueHygiene` needs `disjRule = false` and the per-state `SupOk`/`SupFresh`, i.e. `RunSupOkP`, which is a HYPOTHESIS here exactly as `Hygiene.run_queueHygiene` carries `RunSupOk` (`Hygiene.lean:1363-1370` is explicit that it is not discharged there; `Supply.runSupOk_of` discharges the shipped-order form from an input's own supply invariants).  At a solve's initial state `NoAliasChain` and `QueueHygiene` are free. |

**Why there is no occurs check in that story, and that is the point.**
`Constraints.instantiate` (`:2139`) and `makeEmpty` (`:2191`) call `instantiateType` DIRECTLY;
they never go through `unifyType`, so `occursCheckType` (`Subst.scala:314/317`) is not on the
loop's path at all.  What keeps the environment acyclic is queue hygiene: a bound variable has
been erased from both queues, so the three variables a step can bind and the one it aliases to
are all unbound (`queueHygiene_binds_unboundP`).  For S2 this means the fix for H2, if H2 had
been the defect, would NOT have been an occurs check at `Constraints.instantiate`.

### 2.3 `#print axioms` — all 46 declarations (44 + the two added for the review)

```
'Rowpartition.Loop.stepSP_cases' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.terminatesBP_of_finished_any' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.terminatesBP_of_over_any' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.budgetSP_terminates' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.seedInit' does not depend on any axioms
'Rowpartition.Loop.seedInit_envNodup' depends on axioms: [propext]
'Rowpartition.Loop.seedInit_queueHygiene' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.seedInit_kdist_proc' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.verdict_ne_fuel_of_finished' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.solveSeedP_terminates' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.stepP_env_len_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.runsP_env_len_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.EnvVal.termSize' does not depend on any axioms
'Rowpartition.Loop.envTermSize' depends on axioms: [propext]
'Rowpartition.Loop.envTermSize_eq_len' depends on axioms: [propext, Quot.sound]
'Rowpartition.Loop.runsP_envTermSize_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.envTermSize_le_card' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.escWalk' does not depend on any axioms
'Rowpartition.Loop.escWalk_length_le' depends on axioms: [propext]
'Rowpartition.Loop.runsP_escWalk_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.SubstBlowup.Ty' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.Ty.size' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.Ty.subst1' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.Ty.mentions' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.bal' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.size_bal' depends on axioms: [propext, Quot.sound]
'Rowpartition.Loop.SubstBlowup.mentions_bal' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.subst1_bal' depends on axioms: [propext]
'Rowpartition.Loop.SubstBlowup.instEnv' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.chain' does not depend on any axioms
'Rowpartition.Loop.SubstBlowup.chain_keys' depends on axioms: [propext]
'Rowpartition.Loop.SubstBlowup.chain_values' depends on axioms: [propext, Quot.sound]
'Rowpartition.Loop.SubstBlowup.chain_head' depends on axioms: [propext]
'Rowpartition.Loop.SubstBlowup.chain_head_mem' depends on axioms: [propext]
'Rowpartition.Loop.SubstBlowup.chain_blowup' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.AliasEdge' does not depend on any axioms
'Rowpartition.Loop.NoAliasChain' does not depend on any axioms
'Rowpartition.Loop.aliasEdge_source' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.noAliasChain_no_two' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.noAliasChain_no_cycle' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.noAliasChain_of_binds_nil' depends on axioms: [propext]
'Rowpartition.Loop.noAliasChain_instantiate' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.unifyVars_env_ne' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.stepP_noAliasChain' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.budgetSP_terminates_of_buildQueue' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Loop.runsP_noAliasChain' depends on axioms: [propext, Classical.choice, Quot.sound]
```

---

## 3. What was built — every changed path

| path | change |
|---|---|
| `tracker/lean/Rowpartition/Loop/RejectTerm.lean` | NEW, 248 lines: §2.1's eleven declarations (ten, plus `budgetSP_terminates_of_buildQueue` added for review finding 1). |
| `tracker/lean/Rowpartition/Loop/EnvBound.lean` | NEW, 574 lines: §2.2's thirty-five declarations (thirty-four, plus `runsP_noAliasChain` added for review finding 4), with the `escWalk` and blow-up docstrings corrected for findings 2 and 7. |
| `tracker/lean/Rowpartition/Loop.lean` | two `import` lines and two module-map bullets.  No other content. |
| `tracker/lean/README.md` | one new section, *"S1b — the REJECTION path…"*, after the D1 section. |
| `tracker/satterm/SUBSUME-STAGE1B.md` | this report (the stub was overwritten). |

Scratch (not in the repo): `~/research/ermine/scratch-subsume/s1b/` — `build-deps.log`,
`build-full.log`, `build-full-fix.log`, `build-looptrace.log`, `audit.log`, `audit-fix.log`,
`axioms.log`, `axioms-fix.log`, `PrintAxiomsS1b.lean`, `readme-entry.md`, `TryEnv.lean`.

Nothing was committed; `tracker/repl-classpath.txt` was not touched; no `.ei` was written (no
JVM was run in this stage).

---

## 4. The environment bound, as a formula S2 can compare with S0's numbers

Let a solve start at `s₀` with `env = {}` (every `Subst.solve` does — `Seed.solve`,
`PolicyReplay.solveSeedP`, `Loop/Replay.lean`), let `n` be the number of dequeues its loop
performs, `V₀` the vocabulary of the built queue, and `b` the effective draw budget
(`Policy.effBudget`: 20,000 at the shipped defaults, 0 — i.e. off — under
`-Dermine.dequeuePolicy=shipped`).  Then, for the entries **this solve's loop** writes into
`SubstEnv.types`:

```
  cardinality   |types_loop|            ≤  n                       (runsP_env_len_le, envNodup)
  term size     Σ_{t ∈ range} size(t)   =  |types_loop|  ≤  n      (envTermSize_eq_len)
  fskvs answer  |escs from types_loop|  ≤  |types_loop| ≤  n       (escWalk_length_le;
                 the ANSWER of the `fskvs` half only -- not the cost, not the `kindVars` half)
  and, where a vocabulary is fixed,     |types_loop|  ≤  |V|       (envTermSize_le_card)
      with V ⊆ V₀ ∪ {ids drawn},  |{ids drawn}| ≤ b + (1 + |proc|)  (Draws.learnPartitions_drawn)
```

Read it as: **the row loop contributes at most one `SubstEnv.types` entry per dequeue, and
every one of them is a single type node** (`VarT(u)` or `ConcreteRho(∅)`).  It cannot produce a
`hm.types` that is large *in term size*, and it cannot produce one large in *cardinality*
without taking that many dequeues.

**What to compare with what.**  S0 measures `hm.types.size` at the entry to `subsumeType` —
that is the WHOLE `SubstEnv` of the module's inference, not one solve's loop.  So:

* if S0's `hm.types.size` is of the order of the number of row dequeues the module performed,
  the row solver accounts for it and the walk over it costs `O(size)`;
* if it is much larger, or if the map's TERM SIZES are large (an entry that is not a `VarT` or
  a `ConcreteRho`), the excess was written by `Subst.instantiateType` from `unifyType`'s
  variable arms (`Subst.scala:313-318`) — which is exactly where `chain_blowup` says an
  exponential is available.  That is S1a's fragment,
  and the two results should be read together.

---

## 5. The stage's answer to the title question, and the three hypotheses

**For the loop: BOUNDED.**  `budgetSP_terminates` is the shipped-default statement — a draw
budget makes every solve stop under any policy with S2 layer (i) on — and it is a *budget*
theorem, not a termination theorem for the algorithm: eight L5 rounds failed to find one, and
`L5-TERMINATION.md` §R8.6 records why.  Three things it does not give, all of which S2 must
keep in view:

1. **No a-priori fuel.**  `TerminatesBP` is `∃ n`.  Turning a draw bound into a dequeue bound
   needs a dequeues-per-draw bound, which is §R8.6b and open.  So "the loop stops" does not
   bound the WALL CLOCK, and a user who waits 28 CPU-minutes is not contradicted by it.
2. **The budget is coupled to the policy.**  `Constraints.GenRules` ignores
   `-Dermine.solveBudget` under `-Dermine.dequeuePolicy=shipped` (D1B review U-0), and
   `Policy.effBudget` mirrors that.  Under the shipped order the hypothesis `b ≠ 0` fails and
   **there is no termination theorem at all** — D1 Part A measured `canon` failing to finish
   `GU05`'s corpus instance in 1,800 s.
3. **`buildQueue` is outside the window.**  The budget counts draws from `su1.drawn`, after the
   queue is built; `PQueue.build`'s own mints (8 of the 373 boot inputs, round-6 review W-6b)
   are unbudgeted.  It terminates because it is a fold, not because of the budget.

**For the rest of `Subst.solve`: YES, for the row fragment.**  `solveSeedP_terminates`.  The
pre-loop layers (`labelCheckEarly`, `labelDecide` with its two node budgets, `topNormalise`)
and the post-loop `labelClash` are total functions; the loop is the only layer that can fail to
stop, and under the budget it does not.

**For `subsumeType`'s POST-solve steps: yes for the row fragment, but only ONE of the three is
a theorem here.**

* the escaping-skolem walk at `:648` — **PARTIAL, and narrower than an earlier draft of this
  report claimed.**  What is proved is `escWalk_length_le` / `runsP_escWalk_le`: a bound on the
  ANSWER of the **`fskvs` half only**, over the **loop's own entries only**.  The `kindVars`
  half (`Subst.scala:169` through `Kind.scala:132-134`) is NOT modelled — `EnvVal` carries no
  kind — and it is the half the jstack sits in and the half S0 measures at 35,921 tree nodes and
  3,457 ms.  There is NO equivalence theorem between `escWalk` and `:648`.  **`:648` as a whole
  is not proved bounded by this stage**; what is proved is that the loop's own entries are one
  node each (`envTermSize_eq_len`), so neither walk has anything to recurse into over them.
  Two code facts, not theorems: the walk never follows a BINDING — `typeHasKindVars.vars` at
  `VarT(v)` reads `v.extract`, the variable's KIND ANNOTATION (`Type.scala:651`,
  `Kind.scala:135`) — and `Type`/`Kind`/`V` are strict case classes, so no term's object graph
  can be cyclic.  The orchestrator's handoff note of 2026-09-16 said the first of these and both
  S0 and this stage confirm it; **Part B's H2 wording ("`VarT(v) => v.extract.vars` follows a
  variable's binding") is wrong, and the document loses.**
* `for (r <- rs) entails(qs,r)` — **code fact, not a theorem** (no model was built for it):
  `entails` is class-only.  On a row constraint `unfurlApp` (`Subst.scala:370-374`) matches
  only `AppT`/`Con` and returns `None` for a `Part`, so `bySuper` yields `Nil` and `byInst`
  `None`, and `entails` returns `false` without recursing.  The recursion that exists is
  through the CLASS hierarchy and instance requirements, and classes are on HOLD (user,
  2026-09-12).
* `SigEntail.enforce` — **not covered.**  It runs only for a user signature and only when `rs`
  is non-empty, and it has its own no-verdict escape, but nothing here proves it terminates.
  `restrictTypes` is `hm.types = hm.types -- xs`, a finite map difference.

**H1 — finite but explosive: NOT AVAILABLE TO THE ROW SOLVER, and (S0) not what happened.**
The row loop cannot build a big substitution (§4): one entry per dequeue, one node per entry.
`chain_blowup` states what the blow-up would take — `n` ordinary unifications through
`unifyType`'s VARIABLE arms (`Subst.scala:313-318`, where `occursCheckType` is tested and
`instantiateType` at `:254` is called; `:319`'s `AppT` arm supplies the compound term but is not
the binder), every occurs check passing, no cycle, no bound variable in the range
— so an acyclicity invariant is NOT a defence against it, and the escape walk's cost is `Σ` of
the range's TERM SIZES, which nothing in the compiler bounds.  S0 then measured that this input
does not do it: `hm.types.size` at the escape check peaks at **1,566** and the kind walk at
**35,921 tree nodes**, with the whole run spending **5.50 s** inside `Subst.scala:648`.

**H2 — cyclic substitution: REFUTED for this path, twice.**  No cycle is reachable — under the
three side conditions `runsP_noAliasChain` names (`disjRule = false`, and the per-state
`SupOk`/`SupFresh` of `RunSupOkP`, which this stage does not discharge) — and the walk would
not follow one if it were.  S0 then measured 0 cycles in 186,754 identity-marked walks, which
is the unconditional half of the answer.

**H3 — its proposed MECHANISM is refuted for the row solver; its weaker half SURVIVES.**  H3
proposed that the rejection path *"grows the environment or diverges BEFORE `subsumeType`"*:
that mechanism is refuted for the row solver at the shipped defaults — `Subst.solve` stops
(`solveSeedP_terminates`, `budgetSP_terminates`) and the environment it leaves is one node per
entry and one entry per dequeue.  H3's other half — *"`:648` is only where the thread was
sampled"* — **survives, and is exactly S0 §5.4's conclusion**, which words it as *"H3 — the
walk is the victim: SURVIVES, with a correction"*; S0 sampled the thread in four different
places and found the real cause outside the checker altogether.  There is no disagreement
between the two reports, only between an earlier draft's heading and S0's; this is the wording
that matches.  What H3 could still mean inside the compiler is that some OTHER part of the
path — the unifier, an explicit signature's `SigEntail`, or simply a large `hm.types` built by
ordinary unification — grows the map before `:648` is reached.  That is not the row solver, and
this model does not see it.

---

## 6. Open questions, and what the next stage needs from this one

1. **For S2, the licensing reading.**  If S0's trace shows a `hm.types` whose entries are
   `VarT`/`ConcreteRho` and whose cardinality is of the order of the row dequeues, then
   H1-by-the-row-solver is refuted by §4.  **Do not read `escWalk_length_le` as a licence to
   memoise only "the rest of the map":** it covers the `fskvs` half only and bounds an answer,
   not a cost, and S0 measured the `kindVars` half as the more expensive one (3,457 ms against
   2,044 ms).  A memoised or restricted escape check must address BOTH halves of `:648`, and
   `Subst.scala:169` is where the kind half is assembled.  If the map is large in TERM SIZE,
   `chain_blowup` names the mechanism and S1a's lane owns the fix.
2. **`budgetP_terminates`'s flag hypothesis** was a real hole at the shipped defaults, and the
   two termination statements are now closed: `budgetSP_terminates` and (added for the review)
   `budgetSP_terminates_of_buildQueue`.  **An earlier draft of this report said the hypothesis
   "appears nowhere else in `PolicyTerm.lean`".  That was FALSE**, and the reviewer found it.
   `rowSoundBare = false` also gates:

   * `PolicyTerm.lean:1062` — `budgetP_terminates_of_buildQueue`, the corollary of the very
     theorem this stage repaired (now superseded by the version added here);
   * **the ten-declaration `runSP_*` SOUNDNESS family**, `PolicyStep.lean:2046`
     (`runSP_eq_runP`), `:2061`, `:2080`, `:2098` (`runSP_noLoss`), `:2109` (`runSP_sat_all`),
     `:2120` (`runSP_models`), `:2132` (`runSP_solved_saturated`), `:2142`
     (`runSP_rejects_unsat`), `:2182`, `:2209`, plus `NoFalseAccept.lean:791` / `:801`;
   * and `PolicyStep.lean:2037`'s own prose, which still calls `rowSoundBare = false`
     *"the shipped setting"* — wrong since 2026-09-06 and worth correcting when that family is.

   **OPEN ITEM for the orchestrator, deliberately NOT done in this stage.**  Those ten
   declarations are the ones that license *"the loop rejected ⟹ the input has no model"*
   (`runSP_rejects_unsat`) and `runSP_noLoss`, and at the shipped defaults they say nothing.
   They look mechanically closable from `stepSP_cases` — layer (i) only ADDS deaths, and the
   statements are about `.solved` / `.outOfFuel` outcomes — but that is a stage of its own and
   must not be done silently inside a termination stage.  Until it is, **S2 must not cite any
   `runSP_*` soundness theorem at the shipped defaults.**
3. **Not proved, and worth a stage if S2 needs it:** a model of `entails`/`bySuper`/`byInst`
   (the class recursion is the only unbounded loop left on the post-solve path), and of
   `SigEntail.enforce`.  Both are OFF the row fragment; `entails` is a two-line code fact on it.
4. **Unchanged and still open:** the dequeues-per-draw bound (§R8.6b); the unbudgeted shipped
   order, where the loop has no termination theorem at all; and the `kindVars` half of `:648`,
   which no model in this tree covers (it would need kind annotations in the state, which the
   loop model deliberately does not carry).
5. **What S1b does NOT claim.**  Nothing here is about the B1 program's actual trace: no JVM
   was run in this stage.  Every statement is about the loop model, which L2 holds to the
   compiler on 2,355,430 corpus solve segments — and about `Subst.solve`, not about the type
   checker that calls it.

---

## 7. Reconciliation with S0 (read after this stage's Lean was finished)

S0's report (`~/research/ermine/ermine-scala-wt-subsume-s0/tracker/satterm/SUBSUME-STAGE0.md`,
§§0-3 at the time of reading; §§4-6 not yet written) reaches the title question by measurement
where this stage reaches it by proof.  **The two agree, and S0's headline sharpens H3 in a
direction this model could not see:** the CHECK terminates in 0.06-0.10 s; what does not return
is the ScalaCheck PROPERTY, because `ErmineFixture.no` yields `passed` rather than `proved`, so
ScalaCheck runs `minSuccessfulTests = 100` complete checks of the same module
(`TestErmine.scala:220-223`).  Nothing in the solver hangs at all.

Point by point, S0's numbers against this stage's formulas:

| S0 measurement | this stage |
|---|---|
| `hm.types.size` at the escape check: mean 272.5, p50 64, **max 1,566** | inside §4's bound with room to spare, and the number is the WHOLE module's `SubstEnv`, not one solve's loop.  The loop's own share is at most one one-node entry per dequeue |
| **0 cycles** in 186,754 identity-marked walks (`cyclicKV`/`cyclicTV` false on all 93,377 escape checks) | `stepP_noAliasChain` / `noAliasChain_no_cycle`: no cycle is REACHABLE, which is why the search found none |
| `VarT(v) => v.extract.vars` reads the variable's KIND, not its binding (S0 §2.1, with line references) | the same reading, recorded on `escWalk`; **Part B's H2 wording loses on both lanes** |
| `GenRules.solveBudgetHits = 0`, `rowSoundBudgetHits = 0`, `rowSoundNodes = 10` for the whole run | the draw budget `budgetSP_terminates` relies on never fired: this input is nowhere near it, so the loop terminated for its own reasons and the budget was insurance |
| the walk's cost is the TREE size, no memo table, tree/DAG ratio up to **4.39** (S0 §2.2) | `escWalk_length_le` is about the LOOP's entries, which are leaves and so have tree = DAG = 1.  The 4.39 is entirely the type checker's compound terms -- the same asymmetry §4 predicts |
| the sampled frames are four different places, two of them the row queue, one `checkSkolemEscape:365` | consistent: the thread is doing a hundred full checks, so it is sampled wherever the hundredth check happens to be |

**What this stage adds to S0's answer.**  S0 shows the check terminates ON THIS INPUT, at every
id base it swept.  The theorems here say what holds for EVERY input: the loop stops under the
shipped draw budget (`budgetSP_terminates`), every other layer of `Subst.solve` is total
(`solveSeedP_terminates`), the environment the loop leaves is linear in dequeues with one-node
entries (§4), and no cyclic binding is reachable from any seed or replay state.  Together they
say that if a future input DOES hang here, the row solver is not where to look — and
`chain_blowup` says where to look instead.

**One thing S0's numbers make more interesting for S2.**  `:648` cost 5.50 s over 93,377 calls
in the un-returning run and `checkSkolemEscape:365` another 2.79 s over 21,936 -- i.e. the two
environment walks are ~2 % of a 431 s CPU budget, and the escape check is NOT the cost centre
even in the pathological run.  A memoised or restricted escape check (brief-S2's first option)
would therefore be a correctness-preserving tidy-up with a small measured payoff, not the fix
for this defect; the fix for the defect is in the test harness's `no(...)`, which is S0's
finding and outside this stage.

---

## 8. The signed answer (carried from the review, §4 of `SUBSUME-STAGE1B-REVIEW.md`)

The reviewer's own formulation, reproduced here because it is the one that goes into
`SUBSUME-PLAN.md`'s running answer:

* **The loop: BOUNDED.**  Under the configuration the compiler ships —
  `dequeuePolicy=smallcanon`, `solveBudget=20000`, `rowSound=true` — every solve's loop stops,
  under any dequeue policy: `budgetSP_terminates` (and `budgetSP_terminates_of_buildQueue` at a
  solve's own initial state).  It is a BUDGET theorem, not a termination theorem for the
  algorithm (eight L5 rounds; `L5-TERMINATION.md` §R8.6); the fuel is existential and it
  therefore **bounds no wall clock**.  Under `-Dermine.dequeuePolicy=shipped` the budget is off
  (`effBudget = 0`), the hypothesis `b ≠ 0` fails, and there is **no termination theorem at
  all** — D1 measured real divergence there.
* **The rest of `Subst.solve`, row fragment: YES** — `solveSeedP_terminates`, **conditional on
  `buildQueue` succeeding and on a nonzero effective budget**.  `buildQueue`, `topNormalise`,
  `labelCheckEarly`, `labelDecide` (with its two node budgets) and the late `labelClash` are
  total functions of the model (plain `def`s, no `partial`: `Loop/Decide.lean:213, 240, 265,
  335`), so the loop is the only layer that can fail to stop.  The tie between the model and the
  compiler is L2's measured differential (2,355,430 corpus solve segments, 0 mismatches), not a
  proof.
* **`subsumeType`'s post-solve steps: PARTIAL.**  `restrictTypes` is a finite map difference
  (code fact).  `entails` on the row fragment returns `false` without recursing — `unfurlApp`
  (`Subst.scala:370-374`) returns `None` for a `Part`, so `byInst` is `None` and, when the
  givens are also `Part`s, `bySuper` is `Nil` (`:376-397`); the only recursion is through the
  class hierarchy, and classes are on HOLD.  `SigEntail.enforce` is **not covered**.  The escape
  check at `:648` has a theorem **only for the `fskvs` half, only over the LOOP's own entries,
  and only as a bound on the ANSWER's size**; **`:648` as a whole is NOT proved bounded by this
  stage**.
* **The environment the loop leaves: BOUNDED in term size unconditionally** (one node per
  entry, `envTermSize_eq_len`, because the loop's only two writes are `VarT(u)` at
  `Constraints.scala:2139` and `ConcreteRho(∅)` at `:2191`), **and in cardinality by the number
  of dequeues**, which has no a-priori bound.  It says nothing about entries made outside the
  loop.

---

## 9. Review fixes (FIX-THEN-LAND, `SUBSUME-STAGE1B-REVIEW.md`)

Every theorem was confirmed correct and none was touched; the findings were prose overclaims,
one false sentence and one missing corollary.  Applied in full:

| # | finding | where it is fixed |
|---|---|---|
| 1 | `SUBSUME-STAGE1B.md:318` was FALSE — `rowSoundBare = false` also gates `PolicyTerm.lean:1062` and the ten-declaration `runSP_*` family (`PolicyStep.lean:2046-2209`, `NoFalseAccept.lean:791/801`), and `PolicyStep.lean:2037` still calls it "the shipped setting" | §6 item 2 rewritten with the site list and an explicit OPEN item for the orchestrator (*"S2 must not cite any `runSP_*` soundness theorem at the shipped defaults"*); **`budgetSP_terminates_of_buildQueue` ADDED** (`RejectTerm.lean`, `PolicyTerm.lean:1059`'s proof verbatim minus `hrs`), listed in §2.1, §2.3, §3; the `runSP_*` family and the stale comment also recorded in the module docstring and in `README.md`'s S1b section |
| 2 | `escWalk` covers only the `fskvs` half of `:648`, bounds the ANSWER not the cost, and has no equivalence theorem | `EnvBound.lean` §3 header and both docstrings rewritten (scope stated first); report §2.2 row, §4 formula line, §5 post-solve bullet and §6 item 1 all restated; the honest cost statement is now `envTermSize_eq_len` + the `EnvVal` faithfulness note |
| 3 | §0's "Can the loop leave an enormous `SubstEnv`? NO" was stronger than the theorems | §0 row 3 split: unconditional in TERM SIZE, per-dequeue in CARDINALITY with no a-priori dequeue bound |
| 4 | `stepP_noAliasChain` is per step; the run-level reading needs `stepP_queueHygiene`'s side conditions and `RunSupOk` is not discharged | **`runsP_noAliasChain` ADDED** with `disjRule = false`, `RunSupOkP` and `QueueHygiene` named as hypotheses; `stepP_noAliasChain`'s docstring now says it is one-step; report §0 row 4, §2.2 and §5's H2 paragraph qualified |
| 5 | the `lake build looptrace` row compared against a README job count that does not exist (README records 24) | §1 row rewritten to cite the IMPORT CLOSURE (the reviewer's 60-module derivation) and to note the earlier draft's error |
| 6 | two sections numbered `## 6` | the reconciliation section is now `## 7` (and this stage's additions are §8, §9) |
| 7 | the blow-up's binding site is `Subst.scala:313-318`, not the `AppT` arm | `EnvBound.lean` §4 header and report §4/§5 now name `:313-318` (with `:254` for `instantiateType`) and say what `:319` does instead |
| 8 | the H3 heading collided with S0's "H3 SURVIVES" | §5's H3 paragraph reworded: the proposed MECHANISM is refuted for the row solver, the weaker half survives and is S0 §5.4's conclusion |

**Re-run after the fixes** (numbers in §1, logs under `~/research/ermine/scratch-subsume/s1b/`):
`lake build` **873 jobs, `EXIT=0`** (`build-full-fix.log`); `lake env lean Audit.lean`
**`Rowpartition theorems audited: 4735; declarations using a non-standard axiom: 0`**
(`audit-fix.log`); `#print axioms` over **46** declarations, the two new ones on
`[propext, Classical.choice, Quot.sound]`, **0 non-standard** (`axioms-fix.log`).  Still no
`sorry`/`partial`/`unsafe`/`native_decide`/new axiom, still no executable module changed, still
nothing committed.
