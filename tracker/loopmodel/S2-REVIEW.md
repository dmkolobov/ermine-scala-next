# S2 REVIEW — NO FALSE ACCEPTANCE: an independent re-run of the fix and its theorems

2026-09-06.  Reviewer's scratch `/home/dmitry/.claude/jobs/880c725d/tmp/review-S2/`.  Main
checkout `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `5c08363`
(S1 committed) with S2's uncommitted files in place.  Under review: `tracker/loopmodel/S2-FIX.md`
(Part A §0–§10 and Part B §B0–§B10), `tracker/loopmodel/S2-DESIGN.md`, the Scala diff over
`Constraints.scala` / `Subst.scala` / `RowTrace.scala` / `TestLoopTrace.scala`, the new
`Loop/Decide.lean` + `Loop/NoFalseAccept.lean`, the four Lean driver edits, and the prose
deliverables.  Findings are prefixed `V-`.  Nothing outside this file and the scratch directory
was written; no commits.

---

## 0. Verdict

**ADVANCE.**

Everything load-bearing reproduces.  I rebuilt the Lean development, re-ran the audit, re-ran
`#print axioms` over a LARGER declaration set than the report checked, read the Scala change line
by line, and re-ran every headline gate with my own harness against the MAIN checkout's classes
rather than the worktree's.  **Every headline number in `S2-FIX.md` that I re-measured came out
identical**, including the two that matter most — 0 SOLVED of 120 on the unsatisfiable seeds with
the labels the S1 review names, and 404 → 0 SOLVED over the 665-seed population — and the two
that are easiest to get wrong: the `shouldfail` group loses exactly TWO segments with the flags on
(56 032 → 56 030), and the compiler's own refutation messages on `MIN1`/`MIN2`/`SURV1` carry the
case counts 2 / 1 / 1 that the Lean kernel `rfl`s assert.

I hunted for a FALSE REJECTION with two generators of my own (1 600 fresh satisfiable-by-
construction systems, 4 800 runs, biased toward bare rows, alias chains and forced case splits)
and with a two-solve probe that exercises the environment-fact path the seed harness cannot reach.
**No false rejection was found**, and the reading of `decideLabel` line by line says there cannot
be one from the algorithm: all five propagation rules are forced-implications, the branch is
exhaustive, and SAT is only returned from a leaf whose total assignment was re-checked against
every partition.

The findings below are real but none of them is a soundness defect in the fix.  The largest,
`V-1`, is that the Part B description's phrase "chained with `run_noLoss`" is satisfied in prose
(§B9) and not in Lean.  I read the plan's ACCEPTANCE line literally — "all Part A gates green with
the numbers; `solve_noFalseAccept` proved with the decision procedure's completeness; audit 0
non-standard axioms; the corpus list delivered; report `S2-FIX.md`; reviewed" — and every clause of
it is met, which is why the verdict is ADVANCE rather than FIX-THEN-ADVANCE.  **If the
orchestrator reads "chained with `run_noLoss`" as part of acceptance, this is FIX-THEN-ADVANCE with
a ~15-line fix** (one antitonicity lemma and one corollary); nothing else would change.

**Adoption recommendation is a separate paragraph at the end (§8): NOT YET — three cheap
prerequisites first.**

---

## 1. Rebuild, re-audit, re-test — done with my own hands

| # | command | claimed | measured | |
|---|---|---|---|---|
| R-1 | `lake build Rowpartition` | 861 jobs | **Build completed successfully (861 jobs)** | ✓ |
| R-2 | `lake env lean Audit.lean` | 3 888 / 0 | **Rowpartition theorems audited: 3888; declarations using a non-standard axiom: 0** | ✓ |
| R-3 | `lake build looptrace` | 1 664 jobs | **Build completed successfully (1664 jobs)** | ✓ |
| R-4 | grep the two new modules for `sorry` / `axiom` / `partial` / `unsafe` / `native_decide` / `opaque` / `implemented_by` / `admit` / `#exit` / `Classical` (as a keyword) | 0 | **0 occurrences in both files** | ✓ |
| R-5 | `#print axioms` over EVERY new declaration | 43 declarations | I enumerated **86** `theorem`/`def` declarations across `Decide.lean` (30) and `NoFalseAccept.lean` (60 incl. instances/inductives); **78 are addressable from outside the module and all 78 print only `[propext, Classical.choice, Quot.sound]`** (59 all three, 5 `[propext]`, 3 `[propext, Quot.sound]`, 11 "does not depend on any axioms"). The remaining 8 are `private` and cannot be named from a scratch file; they are covered transitively (every public theorem that uses them is clean). **0 non-standard.** | ✓ (superset of the claim) |
| R-6 | `git diff --stat -- tracker/lean/` | four driver files + the root import list + README | **`Main.lean` +20/−3, `Replay.lean` +33/−3, `Seed.lean` +20/−3, `State.lean` +17/−1, `Rowpartition.lean` +26/−0, `README.md` +2/−0.  NO theorem module touched.**  I read all four diffs: `State` adds four `Flags` fields (all defaulting off/200000) and three `toStr` suffixes; `Main` adds eight `applyFlag` tokens and `senv` to the streaming replay dispatch; `Replay` adds the `Segment.envs` field, the `senv` parse arm, `finish`, `envFacts`, `envOpaque`; `Seed` adds the two flag-guarded calls and `runS`. Flag plumbing and the `senv` record, nothing else. | ✓ |
| R-7 | verbatim check of every quoted Lean statement | — | **all 7 ` ```lean ` blocks in `S2-FIX.md` occur verbatim (whitespace-normalised) in the sources**, checked mechanically | ✓ |
| R-8 | `sbt core/test` (flags off) | 913/914, `TestLoopTrace` 714/714 | **Total 914, Passed 912, Failed 2** — see `V-4`; `TestLoopTrace` inside it: **714 solves; 714 segments; 714 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0**, controls 53/714 and 65/714 | partial (see `V-4`) |
| R-9 | `core/testOnly *TestLoopTrace` with `-Dermine.rowSound=true` | 714/714 with the flag forwarded | **`[loop model trace] rule flags forwarded to both sides: -Dermine.rowSound=true -> --flags=rowsound`**, then **714 solves; 714 agree; hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0**, controls unchanged | ✓ |
| R-10 | `CutSearch.lean` out of the root import list | — | **still out** | ✓ |

---

## 2. The Scala change, read line by line

### 2.1 (a) Flags OFF is a no-op

I found every new branch and checked it is dead at the defaults.

| site | guard | dead with flags off? |
|---|---|---|
| `Constraints.makeConcrete`'s fold, the new `case RHS(abstr, concr) if GenRules.rowSoundBare && abstr.isEmpty` | `GenRules.rowSoundBare` (a `val`, read once at class init) | **yes** — the guard is evaluated per RHS but a `case class` pattern is field reads only; no allocation, and the arm falls through to the shipped `ensureSuperset` case |
| `Subst.solve`: `if (GenRules.rowSoundDecide) decideLabels()` and `if (GenRules.rowSoundSat) checkSaturated(...)` | the two flags | **yes** — `liveInput`, `labelDecide` and the `System.nanoTime` pair are all inside `decideLabels` |
| `RowTrace.rowSound` | `if (enabled)`, both arguments by-name | **yes** |
| `RowTrace.solveInput`'s `envRecs` | `if (enabled)` (whole body) **and** `if (!Constraints.GenRules.rowSoundDecide) Nil` | **yes** |

Unconditional changes, all of which I checked are behaviour-preserving:

* `rowUnifyDeath` factored out of `ensureSuperset` — the same `die` with the same five `:/:`
  fragments in the same order.
* `checkLabels`'s body factored into `rowUnsat` — same statements, same order, same `die`.
* `GenRules.toString` gains three suffixes, **empty at the defaults** (I confirmed by running:
  `genRules=cut+label-early+resguard+splitkey+splitrow+resrow` with the flags off, and
  `…+rsbare+rssat+rsdecide` with `-Dermine.rowSound=true`).
* `RowTrace.solveInput` gains a defaulted `env: Map[TypeVar, Type]` parameter and `Subst.solve`
  passes `hm.types`.  This is a reference read at a call site that is already inside
  `if (enabled)` at the callee; nothing is allocated.
* three `AtomicLong`s in `GenRules` (`rowSoundBudgetHits`, `rowSoundNodes`, `rowSoundMaxNanos`),
  allocated once at class init and only written from `decideLabels`.

The measured evidence agrees: the flags-OFF `top` and `shouldfail` traces I generated myself
replay to **92 673 / 92 673** and **56 032 / 56 032** agreeing segments with `skipped=0
hashdiff=0 eqdiff=0`, i.e. the model that was there before still matches the compiler exactly.

### 2.2 (b) Layer (i) — `ensureExactly` at a bare definition

`Constraints.scala:1711-1717`.  The new arm fires exactly when `GenRules.rowSoundBare` and the
definition's `abstr` is empty; every other definition still goes to `ensureSuperset`.  It is
reached only from the `concrete` branch of `incorporateAll`
(`Constraints.scala:1219`, `makeConcrete(v, concr, rest, proc)`), i.e. when the DEQUEUED
partition is a bare `v <- ((|fs|))`, so `fs` is an assertion `rho v = fs` and not a lower bound —
`makeConcrete` itself re-publishes it as `Partition(v, RHSConcr(fs))` in `nproc`.  A second bare
definition `v <- ((|C|))` in `proc ++ rest` with `C ≠ fs` is therefore two different values for
one row: a genuine refutation, and exactly `Loop/Sound.lean`'s `bare_refutes`.

**Can it refuse a satisfiable state?**  I checked the three shapes the brief names.

* *Label aliasing.*  `Fields = Set[Name]` and the whole row solver already identifies a field
  with its `Name`: `ensureSuperset` uses `subsetOf`, `RHS.build` uses `intersect`, `checkLabel`
  uses `contains`.  If two distinct `Name`s could denote one field, `ensureSuperset` would
  already die on `C = {a}` / `fs = {a'}`.  Layer (i) adds no new identification assumption.
* *`srs`-empty.*  `srs` governs the DELETION inside `destructiveSub`, not the check; the check
  runs before it and unconditionally.  There is no state in which the deletion is skipped and the
  equality is nonetheless not forced.
* *An empty right-hand side.*  `RHS(Set(), Set())` matches the new arm with `concr = ∅`, so
  `v <- ()` against `v := ((|fs|))` with `fs` non-empty now dies where `ensureSuperset` passed.
  That is correct: `Partition(w, RHS(), DeDuplication)` is `subPartitions`' way of saying
  `rho w = ∅` (a variable that appeared twice in one right-hand side), so it is an equation, not
  a bound.

Measured: layer (i) alone takes `MIN2` and `FALSE-ACCEPT-2` from SOLVED to REJECTED, and takes
`D3` from `Incompatible instantiations` to `Row types failed to unify` — the report's §6.2 table,
which I did not re-run in full.

### 2.3 (c) Layer (ii) — `labelClash` on the saturated set

`Subst.scala:1286-1287`: `var ps = q.expand.toList; if (GenRules.rowSoundSat) checkSaturated(ps.map(_.tup))`.
`PQueue.expand` is where `incorporateAll` runs, so `ps` IS the saturated set at the loop's
`.done`, and the check runs **after the loop and before `reduce`** (`reduce` is the last line of
`solve`, `Subst.scala:1359`) — which is the placement the brief asks about.  It is not gated on
`GenRules.labelCheck`, and it runs before the trace's `sat`/`inpart`/`in` records are written, so
a layer-(ii) refutation suppresses them; the model's `solveSeed` returns `records := s.trace.reverse`
on the same path.  The corpus never exercises this (0 `sat` records), so the two record shapes
have not been compared on a real trace — noted in `V-11`.

Soundness is cited, not proved here: `Rowpartition.refute_saturated_sound`.  §B5 is honest that
the relation between the MODEL's `s.proc.elems` and the compiler's `q.expand` is a differential
result, not a theorem.

### 2.4 (d) Layer (iii) — `labelDecide`

**The five propagation rules are `checkLabel`'s.**  I compared them rule by rule against
`Constraints.checkLabel` (`Constraints.scala:2045-2093`):

| rule | `checkLabel` | `propagate` | forced? |
|---|---|---|---|
| `ones > 1` → clash "two parts of one partition both contain it" | yes | yes | ✓ (`sum ≤ 1` violated) |
| `ones == 1` → whole true, every unknown part false | yes, with `unknown` snapshotted BEFORE the whole is set | yes, `unk` snapshotted identically | ✓ (`sum ≥ 1 ∧ sum ≤ 1 ⇒ sum = 1 ⇒ b[v]=1`; a second true part would make `sum = 2`) |
| whole false → clash if the concrete part carries it, every unknown part false | yes | yes | ✓ |
| `ones == 0 ∧ unknown = ∅` → whole false | yes | yes | ✓ |
| whole true ∧ `ones == 0` → clash if no unknown, force the single unknown true | yes | yes | ✓ |

Two differences, both harmless: `checkLabel` keeps applying rules inside one partition after a
clash (`propagate` short-circuits on `!conflict`), and `checkLabel` is a repeat-until-fixpoint
pass while `propagate` is worklist-driven.  The rules are monotone forced-implications, so the
least fixpoint is the same; only WHICH partition is blamed for a clash can differ.  The
worklist's re-queue set is `occ(u) = { k : u = lhs(k) ∨ u ∈ parts(k) }`, which is exactly the
partitions whose constraint can change when `u` is assigned, so the fixpoint is reached.

**The case split is exhaustive.**  `search()` picks the first unassigned bit, tries `b = 2`
(false) then `b = 1` (true) — `while (!res && b >= 1 && !budgetOut)` starting from `b = 2` — and
undoes the trail down to `mark` between branches.  Because propagation only ever derives forced
bits, pruning a branch closed by propagation prunes no model.

**The SAT verdict is checked against every partition.**  `verify()` (`Constraints.scala`, the
`def verify(): Boolean` inside `decideLabel`) walks `k = 0 … m-1` — every partition of the input
list — and requires `ones ≤ 1 ∧ (ones == 1) == (bits(lhs) == 1)`.  That is `sum ≤ 1 ∧ b[v] = sum`
verbatim.  `search()` returns `some` only from a leaf at which `verify()` was true; if it is
false, `checkFailed` is set and the verdict is `LabelNoVerdict`, **never** `LabelRefuted`.  The
Lean mirrors this exactly (`modelChecks`, `searchLabel`'s `if modelChecks … else (none, nodes, true)`
— the `true` is the CUT flag, so a failed check can never reach the "no assignment exists" arm).

**Budget.**  `budget` bounds `nodes`, incremented once per decision node, per LABEL
(`decideLabel(ps, l, budget)` is called with the same budget for each label and returns its own
count).  On `nodes > budget` the search sets `budgetOut` and unwinds; the verdict is
`LabelNoVerdict`, `GenRules.rowSoundBudgetHits` is incremented, a `rsound … budget` record is
written, and **nothing is refuted**.  `labelDecide` keeps scanning labels past a no-verdict and
still reports a refutation found at a later label, which is sound.  I verified the fail-safe
directly: `-Dermine.rowSound.decide=true -Dermine.rowSound.budget=0` on `SURV1` gives SOLVED
(the report's §3.3c), and my whole re-run recorded `budgetHits=0` in every configuration.

**"The live input".**  `Subst.scala`'s `liveInput` takes `q.toList.map(_.tup)` and closes the
variables the partitions mention over `hm.types`: `VarT(u)` → the link `v <- (u)` and `u` is
queued; `ConcreteRho(_, f)` → `v <- ((|f|))`; `Con(_, n, _, _)` → `v <- ((|n|))`; anything else is
counted `opaque` and SKIPPED.  Three checks:

1. *Is `Con` as a singleton row right?*  Yes — `RHS.build` reads `Con(_, n, _, _)` in a row
   position as the field `n` (`Constraints.scala:416`), and `RowTrace`'s own `st` renders it
   `(|n|)`.  The fact is the compiler's own reading.
2. *Is skipping an opaque binding SOUND?*  Yes, and the design note says the right thing.
   Dropping a fact weakens the system, so a refutation of `q ∪ E'` with `E' ⊆ E` still refutes
   `q ∪ E`.  What it costs is COMPLETENESS: the theorem then says only that the SUB-system
   `q ∪ E'` has a model, which does not entail that the real system does.  So with `opaque > 0`
   the guarantee `P` degrades to "no refutation was found", exactly as `S2-DESIGN.md` §3 states.
   The `rsound env` record makes it measurable; the corpus measured 0.
3. *Can a fact be WRONG (a false rejection)?*  Only if `hm.types` could hold a binding that is not
   a consequence of the state the solve runs in.  I looked for speculative binding with rollback:
   `Subst.scala` contains **no** `catch` at all, `hm.types` is only ever written by
   `instantiateType` (`:186`) and only ever narrowed by `restrictTypes` (`:153`), and the file's
   own header says a `Death` aborts rather than backtracks.  So every binding present at the
   solve is a commitment, and every fact derived from it is true.  I could not construct a false
   rejection from the environment, and my probe (§4.5) confirms the satisfiable cases stay SOLVED.

**Where it runs.**  `Subst.scala:1284-1287`: after `if (GenRules.labelCheckEarly) checkLabels(...)`,
before `q.expand`, and therefore before `reduce` publishes anything.  A refutation kills the solve
before the substitution is published — which is the point.  One consequence the report flags and
I confirm: (iii) is NOT gated on `GenRules.labelCheck`, so under `-Dermine.labelCheck=false` it
pre-empts the `D1`–`D4` death-site seeds.

### 2.5 Could a REJECTED verdict from (iii) be a FALSE rejection?

From the reading above: not from the algorithm.  Propagation derives only forced bits; the split
is exhaustive; SAT is exhibited and re-checked; the only way to lose is to lose a REFUTATION.
From the environment: not unless `hm.types` could hold a retracted binding, and it cannot.

Empirically I tried hard to find one (§4.4, §4.5) and did not.

---

## 3. What the theorems say

### 3.1 Hypotheses, one by one

`solve_noFalseAccept` (`NoFalseAccept.lean:904`):

| hypothesis | kind |
|---|---|
| `hcoh : LblCoh L` | vocabulary side condition; the same hypothesis `Loop/Reject.lean` already carries |
| `hq : buildQueue cs su0 = .ok (q, su1)` | discharged from the input (it is what the replay does) |
| `hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) = none` | **implied by `hacc`** (a clash makes `solveSeed` reject), so WLOG, but stated rather than derived — a caller must still discharge it |
| `hflag : fl.rowSoundDecide = true` | the flag |
| `hnd`, `hmem` | vocabulary side conditions on `q.elems ++ envFacts` (`Nodup` abstract parts, concrete labels in `L`), decidable at a seed |
| `hbud : ∀ l w, (labelDecide …).1 ≠ .noVerdict l w` | **the budget proviso**, checkable at run time (the compiler counts it) |
| `hacc : verdict ≠ "REJECTED"` | the thing being assumed |

Conclusion: `SSat (((q.elems ++ envFacts).map LPart.toConstraint).toFinset)` — **the live input as
Part A defines it**, queue plus environment facts.  That is the right object.

**When the budget is exhausted the theorem says nothing.**  `hbud` is a hypothesis, not a
disjunct; there is no weaker conclusion ("either satisfiable or the budget fired") stated.  That
is defensible — the compiler counts exhaustions, so the hypothesis is a measurable side
condition — but it does mean the *guarantee* is conditional on a run-time observation, not on the
code alone.

**Is `verdict ≠ "REJECTED"` the right notion of "accepted"?**  For the MODEL, yes: `solveSeed`'s
other verdicts are `"FUEL"` (`.outOfFuel`) and the solved case, and `.outOfFuel` is not an
acceptance in the compiler (the compiler has no fuel).  For the COMPILER the answer is weaker in
one respect the design note states and I confirm: `Subst.reduce` runs AFTER the check and is not
modelled, so a solve can still die there — `PANIC-1`'s reinstantiation panic is exactly that, and
my own probe produced a fresh instance of the same panic on a satisfiable system (§4.5, case
`SAT-5`), at BOTH flag settings.  A panic is a rejection, so it costs nothing for no-false-
ACCEPTANCE; it means the converse ("satisfiable ⇒ accepted") is still false, which nobody claims.
The skolem message (S1's single `NonRefutation`) is a rejection-soundness exception and is
untouched by S2.

### 3.2 Completeness, soundness, decomposition

* `labelDecide_sat_ssat` (COMPLETE) and `labelDecide_refuted_unsat` (SOUND) are stated exactly as
  quoted, and both rest on real work: `forcedBy_sound` (at a model the guard is false and every
  forced bit is the model's), `propagate_sound`, `searchLabel_checks` and `searchLabel_sound`.
  I read `searchLabel_sound`'s proof: it is a genuine induction on the depth with the CUT flag
  handled correctly — the `(none, n, true)` arms are all discharged by `simp at h`, so nothing is
  concluded from a cut search.
* **The label-wise decomposition is PROVED, not assumed** — but it is pre-existing:
  `Rowpartition.satisfiable_iff_forall_label` (`Basic.lean`) is the decomposition, and what S2
  adds is the BRIDGE `bsat_iff_count` / `lsat_iff_bsat` / `lmodels_iff_bmodels` from the loop's
  `LSat` to `Rowpartition.BSat`, plus `bmodels_false_of_not_mem` for unmentioned labels.  That is
  the right division of labour and it is stated correctly in §B3.
* **(B) rejection soundness stays complete.**  The new deaths are refutations:
  `bare_death_refutes` for layer (i) and `labelDecide_refuted_unsat` for layer (iii); layer (ii)
  is `refute_saturated_sound`.  Layer (i)'s death lands on the SAME message as `ensureSuperset`
  (S1 death site 7), so S1's census is extended by a site, not by a message — and
  `stepS_continue` is what keeps every S1 `step` theorem literally true.  I checked
  `stepS_continue`'s proof: three nested `split`s, the `.died` arm killed by `absurd h (by simp)`.

### 3.3 The chain — **V-1**

`solve_noFalseAccept`'s conclusion is `SSat (q ∪ E)`.  S1's `run_noLoss` / `run_models` /
`solve_sound` are conditional on `SSat (sys s₀)`, and `sys_initState_eq` proves
`sys (initState q …) = (q.elems.map LPart.toConstraint).toFinset` — the QUEUE alone.  Composing
the two needs one more step, `SSat (q ∪ E) → SSat q`, and **neither that step nor the composition
is stated anywhere in Lean**: `NoFalseAccept.lean`'s only occurrences of `run_noLoss` are in the
module docstring (line 7) and `solve_noFalseAccept`'s docstring (line 902).  §B9 gives the chain
as a three-point prose argument.  See `V-1`.

---

## 4. The gates, re-run

All of the following were run against the MAIN checkout's compiled classes (not the worktree's),
through my own copy of the S2 `BulkRun` driver (`review-S2/classes`, `review-S2/rbulk.sh`), one
JVM at a time, `-XX:ActiveProcessorCount=2`.

### 4.1 `seeds/unsat/` × 20 bases (300–319)

| seed | flags OFF (mine) | report's OFF | flags ON (mine) | label |
|---|---|---|---|---|
| `MIN1` | SOLVED **20**/20 | 20/20 | REJECTED 20/20 | `l35` |
| `FALSE-ACCEPT-1` | SOLVED **20**/20 | "SOLVED" | REJECTED 20/20 | `l35` |
| `MIN2` | SOLVED **4**/20 | 4/20 | REJECTED 20/20 | `l17` |
| `FALSE-ACCEPT-2` | SOLVED **4**/20 | "SOLVED" | REJECTED 20/20 | `l17` |
| `PANIC-1` | 0 SOLVED (panic) | 0 (panic) | REJECTED 20/20 | `l4` |
| `SURV1` | SOLVED **20**/20 | *"SOLVED at 300, 301"* (`V-5`) | REJECTED 20/20 | `l20` |

**120 runs with the flags on, SOLVED = 0, and 0 of 120 rejected by anything other than the
field-naming diagnostic.**  `budgetHits=0`, 145 decision nodes over the 120 runs.

The messages at base 300 are, verbatim:

```
MIN1  : … at field 'l35': no assignment of this field to the parts satisfies every partition (complete search, 2 cases; …)
MIN2  : … at field 'l17': … (complete search, 1 cases; …)
SURV1 : … at field 'l20': … (complete search, 1 cases; …)
```

which are **exactly** the three kernel facts `min1_decide_refutes` (`searchReason 2`),
`min2_decide_refutes` (`searchReason 1`) and `surv1_decide_refutes` (`searchReason 1`).  This is
the sharpest compiler↔model agreement in the stage and it is not something the L2 differential
can see (`V-11`), so I record it as an independent confirmation of §B3's claim that "the case
counts are the COMPILER's".

### 4.2 The whole 665-seed false-acceptance population (the brief asked for 500)

`review-S1/`'s 665 seeds at bases 300 and 301 = **1 330 runs**:

| configuration | SOLVED | REJECTED | report |
|---|---|---|---|
| flags OFF | **404** | 926 | 404 ✓ |
| `-Dermine.rowSound=true` | **0** | **1 330** | 0 ✓ |

**0 of 1 330 rejections are by anything other than the field diagnostic**, over 39 distinct
labels.  `budgetHits=0`, 1 579 decision nodes.

### 4.3 500 round-8 hunt seeds (satisfiable by construction) at 3 bases

500 seeds sampled across the whole `L5r8/hunt/grid` (every 7th path, all 80 grid cells
represented) × bases 0–2 = **1 500 runs**:

| | SOLVED | REJECTED |
|---|---|---|
| flags OFF | 1 500 | 0 |
| `-Dermine.rowSound=true` | **1 500** | **0** |

and the two result files — seed, base, verdict and the FULL substitution — are **byte-identical**,
md5 `e1704e0d166a15a0c76de4f438d53c8b` on both sides.  `budgetHits=0`.

### 4.4 A NEW hunt for FALSE REJECTIONS (mine)

Two generators, both of which fix a valuation `rho` first and ASSERT every emitted constraint true
under it before writing it (`review-S2/revgen.py`, `review-S2/revgen2.py`):

* **`revgen`** — 800 seeds, four styles: bare rows equal to their instantiation, deep alias
  chains (`v <- (u)` with `rho u = rho v`, planted by giving several variables the same row),
  abstract-heavy partitions, and a mix; 6–16 variables, 6–24 labels, 6–28 constraints.
* **`revgen2`** — 800 seeds engineered so unit propagation CANNOT decide: singleton "atom" rows
  and EMPTY atoms composed into wholes, the wholes pinned by a bare row and their parts left
  abstract, so the label's carrier is genuinely ambiguous and the search must branch.

| | runs | SOLVED off | SOLVED on | REJECTED on | decision nodes | budget hits |
|---|---|---|---|---|---|---|
| `revgen` × bases 0–2 | 2 400 | 2 400 | **2 400** | **0** | 5 513 | 0 |
| `revgen2` × bases 0–2 | 2 400 | 2 400 | **2 400** | **0** | 11 681 (≈ 4.9/run — the split really fires) | 0 |

Substitutions byte-identical off vs on in both hunts (`diff` empty).  **No false rejection.**

One number of mine that is larger than the report's: the largest single `decideLabels` bill I
measured is **13.1 ms** (`revgen2`) and **10.5 ms** (`revgen`), against the report's corpus
maximum of 3.5–3.7 ms.  These are synthetic 20-variable systems and the path is cold, but it says
the per-solve worst case is a property of the system, not a corpus constant — relevant to
adoption (§8).

### 4.5 The environment-fact path, which no gate reaches — `V-2`

`SatTermRepro.runCapped` builds a **fresh `SubstEnv` per run**, so all 38 400 report runs, all
6 300 of my seed runs and every seed in `seeds/unsat/` have `facts = 0`: the layer-(iii) "live
input" is just `q`.  The corpus reaches it exactly ONCE (`shouldfail/inf04`).  I therefore wrote a
probe that runs TWO solves in ONE `SubstEnv` (`review-S2/EnvProbe.scala`) and got:

| case | env after the first solve | flags OFF | flags ON |
|---|---|---|---|
| second solve consistent with the binding | `v0 := (\|l0,l1\|)` | SOLVED | **SOLVED** |
| `v3 <- (v0,(\|l0\|))`, unsat ONLY through the binding | `v0 := (\|l0,l1\|)` | **SOLVED** | REJECTED at `l0`, "two parts of one partition both contain it" |
| the same through an alias | `v0, v4 := (\|l0,l1\|)` | **SOLVED** | REJECTED at `l0` |
| alias chain, consistent | `v0, v4 := (\|l0,l1\|)` | SOLVED | **SOLVED** |
| many labels under a binding | `v0 := (\|l0..l3\|)` | SOLVED | **SOLVED** |
| **`v4 := v0` (a `VarT` link, no concrete anywhere)**, then `v3 <- (v0,v4)`, `v3 <- ((\|l0\|))` | `v4 := v0^1000` | **SOLVED** | REJECTED at `l0`, complete search, 1 case |
| bare row EQUAL to its instantiation | — | SOLVED | **SOLVED** (layer (i) correctly silent) |
| bare row a PROPER subset | — | REJECTED | REJECTED |

Three things follow.  (1) The environment path works, including the `VarT` link case that the
corpus does not exercise: `v4 := v0` plus `v3 <- (v0,v4)` forces `rho v0 = rho v4 = ∅` hence
`rho v3 = ∅`, contradicting `v3 <- ((|l0|))` — a **third mechanism** by which the shipped compiler
accepts an unsatisfiable system, found by me and not previously recorded.  (2) The satisfiable
cases under a binding are all still SOLVED — no false rejection.  (3) The case `SAT-5` (a case
split under a binding) dies at BOTH settings with `panic: reinstantiated type v0^1000 to v7^1001
but it was already bound` — a PRE-EXISTING panic in the same family as `PANIC-1`, identical off
and on, and a reminder that `reduce`/`instantiate` remain unmodelled.

### 4.6 The corpus, flags ON vs OFF

`tracker/tools/looptrace-corpus.sh`, groups `top` and `shouldfail`, one run each way:

| group | flags | segments | agree | skipped | hashdiff | eqdiff |
|---|---|---|---|---|---|---|
| top | OFF | 92 673 | 92 673 | 0 | 0 | 0 |
| shouldfail | OFF | 56 032 | 56 032 | 0 | 0 | 0 |
| top | **ON** (`-Dermine.rowSound=true` / `--flags=rowsound`) | 92 673 | **92 673** | 0 | **0** | **0** |
| shouldfail | **ON** | **56 030** | **56 030** | 0 | **0** | **0** |

The `56 032 → 56 030` drop is the report's §B4-1 exactly: two solves that used to follow
`inf04_except_recursive.e` never happen because it is refuted earlier.  The model reproduces it.

Compiler output, `diff` with the `(N seconds)` timing lines removed:

* `top`: **no difference at all**.
* `shouldfail`: **two lines**, both on modules that already fail —
  * `inf04_except_recursive.e`: `:22:7 … 'Shouldfail.Inf04.a': two parts of one partition both contain it` → `:20:10 … 'Shouldfail.Inf04.a': a part contains it but the whole does not`.  Same file, same field, earlier position, different clause.  **The message move reproduced.**
  * `inf05_union_two_fields.e`: `:23:30 … 'Shouldfail.Inf05.b'` → `:23:18 … 'Shouldfail.Inf05.a'`.  This is the batch-only id-shift artefact of §4.3 — my run is one JVM per group, i.e. a batch — and the report says per file it does not move.

**No program is newly rejected in either group.**

### 4.7 The two tracked corpora

`tracker/tools/corpus-run.sh --batch` and `--incomplete --batch`, each way:

| corpus | flags OFF | flags ON | verdicts moved | messages moved |
|---|---|---|---|---|
| 66-file (examples + Ai + shouldfail) | 23 LOADED / 43 REJECTED, `shouldfail/` 40/40 | 23 LOADED / 43 REJECTED, `shouldfail/` **40/40** | **0** | **1** (`inf04`, the same field, `:22:7` → `:20:10`, "two parts of one partition both contain it" → "a part contains it but the whole does not") |
| 34-file `incomplete/` | 18 LOADED / 16 REJECTED | 18 LOADED / 16 REJECTED | **0** | **0** (`diff` of the verdict listings is EMPTY) |

Identical to `S2-FIX.md` §4.1, figure for figure.

### 4.8 The new records, and the flags-off trace

From my own traces:

| group | flags | `rsound` records | `senv` records | kinds |
|---|---|---|---|---|
| top | OFF | **0** | **0** | — |
| shouldfail | OFF | **0** | **0** | — |
| top | ON | 92 673 | 0 | 92 673 `ok` |
| shouldfail | ON | 56 005 | **1** | 56 003 `ok`, **1 `decide`**, **1 `env`** |

exactly the report's §4.2 numbers for these two groups, including the single environment-using
solve.  And the sharper form of §4.2b reproduces: **strip the `rsound`/`senv` records from the
flags-ON `top` trace and it is BYTE-IDENTICAL to the flags-OFF one** (md5
`6d3c53a332692a14cc99e13f1e1665a8` both sides, 240 192 lines).  `shouldfail` differs on 136/124
lines, confined to `inf04_except_recursive.e`, `inf05_union_two_fields.e`, `inf06_row_minus.e` and
the stdlib `Relation/Row.e` solves they instantiate — the id shift the report explains.

### 4.9 Cost

`tracker/tools/perf-bench.sh batch -n 3`, `PERF_JVM_PROPS="-XX:ActiveProcessorCount=2 [-Dermine.rowSound=true]"`,
two interleaved rounds, cold, interface-free (`ei_after=0` on every run), load recorded:

| round | flags OFF median (min–max, spread) | load before | flags ON median (min–max, spread) | load before |
|---|---|---|---|---|
| 1 | **12.72 s** (12.65–12.88, 0.23) | 0.55 | **12.84 s** (12.82–12.96, 0.14) | 1.86 |
| 2 | **12.69 s** (12.68–12.73, 0.05) | 2.50 | **12.80 s** (12.71–12.90, 0.19) | 4.88 |
| median of medians | **12.705 s** | | **12.82 s** | |

**+0.115 s, +0.9 %** — the report's figure to two decimals.  One nuance where I read the data
slightly differently: in MY two rounds the sign did **not** flip (ON slower by 0.12 and 0.11 s,
and in round 2 that difference is larger than either round's spread), whereas the report's round 2
had ON faster and concluded "no batch cost the harness can resolve".  My interleave is confounded
the other way — ON always ran second, at a higher load — so I would state it as *"at most about
1 %, direction consistent in two rounds, not separable from the load drift"* rather than "no
resolvable difference".  Either reading supports the same conclusion for adoption.

**And the number the report does not have: what the budget costs when it FIRES.**  I encoded
PIGEONHOLE as a one-label row system (p pigeons, h holes, `w_i <- (x[i][*])` + `w_i <- ((|l0|))`
for exactly-one-hole, `u_j <- (x[*][j])` for at-most-one-pigeon; UNSAT for p = h+1, and DPLL on it
is exponential — `review-S2/php.py`):

| instance | variables | flags ON |
|---|---|---|
| php04 … php08 (5/4 … 9/8) | 26 … 89 | **REJECTED**, correctly, at `l0` |
| **php09 (10 pigeons, 9 holes)** | 109 | **SOLVED** — the budget fired |
| **php10 (11 pigeons, 10 holes)** | 131 | **SOLVED** — the budget fired |

`budgetHits=2`, total 580 713 decision nodes over the seven runs, and
**`maxDecideMicros = 201 623`, i.e. 0.20 s to spend the 200 000-node budget on ONE label.**

Read three ways.  (1) The fail-safe is real and behaves exactly as designed: exhaustion is
`LabelNoVerdict`, nothing is refuted, an unsatisfiable system is ACCEPTED rather than mis-rejected.
(2) The budget is per LABEL and there is no per-SOLVE cap, so the worst case a solve can pay is
`#labels × 0.2 s` — about 8 s for a 40-label solve, on top of everything else.  (3) When it fires
in a production build the ONLY signals are `GenRules.rowSoundBudgetHits` (never read by the
compiler) and a `rsound … budget` trace record that requires `-Dermine.rowTrace`.  With the
default flipped ON and no tracing, a budget exhaustion — the exact condition under which the
theorem says nothing — is invisible.  See `V-12` and §8.

### 4.10 The budget and the sub-flags, verified directly

| check | result |
|---|---|
| `-Dermine.rowSound.decide=true -Dermine.rowSound.budget=0` on `SURV1`, bases 300–301 | **SOLVED 2/2**, `budgetHits=2` — nothing refuted |
| the same with `budget=1` | **REJECTED 2/2**, `budgetHits=0` |
| `-Dermine.rowSound=true -Dermine.rowSound.bare=false` | `genRules=…+rssat+rsdecide` (no `+rsbare`); all six unsat seeds still REJECTED |
| `-Dermine.rowSound=true` | `genRules=…+rsbare+rssat+rsdecide` |
| flags off | `genRules=cut+label-early+resguard+splitkey+splitrow+resrow` — unchanged |

### 4.11 What I did NOT re-run

The `.ei` sweep (§8 of the report, four sides), the 18+2 tracked seeds at 10 bases (A3-6), the
3 840-seed hunt in full (I sampled 500), the six remaining `looptrace-corpus` groups, and the
per-layer table of §3.1/§6.2.  Everything I did re-run agreed, and the four sides of the `.ei`
sweep are argued from a same-configuration CONTROL that I consider methodologically sound.

---

## 5. Prose, deliverables, acceptance

* **`tracker/ROW-CONSTRAINT-STATE.md`'s new section** — dated, additive, placed above the S1 BUG
  section.  It says **DEFAULT OFF** three times, names all five flags, states the theorem and
  both of its named provisos in the right place ("budget not exhausted"), and gives the corpus
  and cost figures.  What it does NOT say is the **opaque-binding** proviso or the
  skolem/existential reading of "satisfiable", both of which `S2-DESIGN.md` §2–§3 states
  explicitly.  `V-10`.
* **`tracker/lean/README.md`** — two additive rows, accurate in substance; `NoFalseAccept.lean`
  is given as 1 022 lines (it is 1 025), and the section's headline counts at line 636 are still
  the pre-S2 "Build 859, Audit 3804/0; `lake build looptrace` 1662".  `V-7`.
* **`tracker/lean/Rowpartition.lean`** — two imports and two doc entries; `CutSearch` still out.
* **The plan's S2 row and section** — the row is a faithful, quantitative summary; every figure in
  it that I re-measured is right except `core/test` "913/914" (`V-4`).  The section's acceptance
  list is met **except** the clause "`solve_noFalseAccept`: flag on ∧ solved ⇒ `SSat (sys s₀)`,
  chained with `run_noLoss`": the delivered conclusion is `SSat (q ∪ envFacts)` — a better object
  — but the chaining is prose, not Lean (`V-1`).
* **§B5's side-by-side** — five entries, all accurate and all things I independently confirmed:
  `Loop/Json.lean`'s `checkLabel` is well-founded so no end-to-end `solveSeed` `rfl`; pass-based
  vs worklist propagation (verdict-equal, blame-different); layer (ii) cited-sound only, with the
  `q.expand` ↔ `s.proc.elems` gap named; `bareExact` folding over partitions rather than the
  `SSet` of right-hand sides; `Subst.reduce` unmodelled.  **Two items are missing from it**: the
  un-chained `run_noLoss` (`V-1`) and `runS_of_flag_off`'s undischarged hypothesis (`V-9`).
* **`S2-DESIGN.md`** — the best document of the three.  §2's statement of P, §3's table of what
  becomes a fact and why facts rather than a substitution (the `Supply`-draw argument is correct
  and important), §4's account of the fail-safe, §6's cost model.  I checked the `Supply` claim:
  `PQueue.build` does mint for a non-variable left-hand side (`Constraints.scala:684`), so
  rebuilding a queue from `cs map substType` really would move every subsequent id.

---

## 6. Findings, ranked

Severity: **M** medium, **L** low, **I** informational.  None is a soundness defect in the fix.

| # | sev | where | what |
|---|---|---|---|
| **V-1** | **M** | `tracker/lean/Rowpartition/Loop/NoFalseAccept.lean:904-925` vs `S2-FIX.md` §B9 / `LOOP-MODEL-PLAN.md` S2 acceptance | **The chain to S1 is prose, not a theorem.**  `solve_noFalseAccept` concludes `SSat ((q.elems ++ envFacts).map LPart.toConstraint).toFinset`; S1's `run_noLoss`/`run_models`/`solve_sound` need `SSat (sys s₀)`, and `sys_initState_eq` gives `sys s₀` = the QUEUE's constraints alone.  The composition needs the restriction step `SSat (q ∪ E) → SSat q` and then the application of `run_noLoss`; **neither is stated in Lean** — the only occurrences of `run_noLoss` in the module are two docstrings (lines 7 and 902).  §B9 states the three-point chain in prose and the plan's acceptance sentence says "chained with `run_noLoss`".  **Fix:** one lemma (SSat is antitone in the constraint set — S1 already has `unsat_mono`-style machinery) plus a five-line corollary `solve_noFalseAccept_models`.  Until then, "accepted ⇒ the output's models are models of the input" is an argument, not a theorem. |
| **V-2** | **M** | `Subst.scala` `liveInput`; `tracker/repro/satterm/SatTermRepro.scala` `runCapped` | **Layer (iii)'s environment-fact path — the part the theorem's `envFacts` and the whole `senv` replay record exist for — is exercised by exactly ONE solve in the world.**  `runCapped` builds a fresh `SubstEnv` per run, so every seed gate (38 400 in the report, 6 300 of mine) has `facts = 0`; the corpus has one (`shouldfail/inf04`).  The `VarT(u)` link arm and the transitive closure are covered by **nothing** in the tracked gates.  I wrote a two-solve probe (`review-S2/EnvProbe.scala`, §4.5) that exercises all of it and found no defect — and found a third compiler-level false acceptance in the process — but the probe is mine and unowned.  **Fix:** land a two-solve mode in `SatTermRepro` (or the probe itself) as a tracked gate before the default is flipped. |
| **V-3** | **L** | `core/src/test/.../TestLoopTrace.scala:355-366` vs `Loop/Main.lean` `applyFlag` | **`-Dermine.rowSound.budget` has no `flagMap` entry**, so it is not in `setFlags`, not in the `bad` check, and not forwarded: `sbt -Dermine.rowSound.budget=1 "core/testOnly *TestLoopTrace"` runs the compiler at budget 1 and the model at 200 000, silently.  That is precisely the trap the L4 review's F2 put `flagMap` there to close.  The Lean side has `rsbudget=<n>`; only the Scala map is missing it.  (§B4-2's "there are now eight … all in `Loop/Main.lean`'s `applyFlag`" is true of Lean and does not claim Scala parity, so this is a gap, not a misstatement.) |
| **V-4** | **L** | `S2-FIX.md` §0/§2/§3.4, plan's S2 row | **`core/test` is 912/914 on my run, not 913/914.**  The second failure is `Legends & presentations.extra args are ignored` (`TestLegend`, failing seed `55XofbkwXKF_59IpW4C_nMI4V9dY1BPWyIHT_KQFTUL=`, "Expected 5/23/12–1/20/47 but got 5/23/12–1/22/21") — a date-range formatting property in the `writers` module with a random ScalaCheck seed, unreachable from `Constraints`/`Subst`/`RowTrace`.  It is a flake, NOT an S2 regression; but the suite has at least two flaky properties and "913/914" is recorded as if it were a constant. |
| **V-5** | **L** | `S2-FIX.md` §3.1, first table | **The shipped column for `SURV1` says "SOLVED at 300, 301"; it is SOLVED at 20/20** (my measurement, and the report's OWN per-layer table two rows below says 20).  `FALSE-ACCEPT-2`'s shipped column says "SOLVED" where the count is 4/20.  The first table understates the bug and disagrees with the second. |
| **V-6** | **L** | `S2-FIX.md` §B8 | **The line-count table does not match `git diff --numstat`**: `RowTrace.scala` +58/−1 (actual **+77/−1**), `Subst.scala` +103/−3 (actual **+103/−4**), `TestLoopTrace.scala` +11/−1 (actual **+13/−2**), `Main.lean` +23/−3 (actual **+20/−3**), `Replay.lean` +36/−3 (**+33/−3**), `Seed.lean` +23/−3 (**+20/−3**), `State.lean` +18/−1 (**+17/−1**), `NoFalseAccept.lean` 1 025 not 1 022 (the README says 1 022 too).  Substance unaffected; the "four driver files, +100/−10" summary is +90/−10. |
| **V-7** | **L** | `tracker/lean/README.md:636` | The section's headline counts are still **"Build 859, Audit 3804/0; `lake build looptrace` 1662"** although the two new rows below them make it 861 / 3888 / 1664. |
| **V-8** | **L** | `RowTrace.scala` FORMAT block vs `Subst.scala` `decideLabels` | The doc says the `budget` record's detail is `<label>\t<budget>`; the code writes `<label>\t<reason>`.  And `GenRules.rowSoundBudgetHits` is incremented for BOTH `LabelNoVerdict` causes — budget exhaustion and the "a complete assignment failed its own check" fail-safe — so a counter named `budgetHits` would silently absorb a propagator bug, and "0 budget exhaustions" is really "0 no-verdicts".  (Conservative in the safe direction; the conflation is the issue.) |
| **V-9** | **L** | `NoFalseAccept.lean:740` | `runS_of_flag_off` carries an **undischarged** hypothesis `hstep : ∀ s s', step s = .continue s' → s'.flags.rowSoundBare = s.flags.rowSoundBare`, which `Rowpartition.Loop.step_flags` (`Loop/RefineLearn.lean:1472`, pre-existing, `s'.flags = s.flags`) proves outright.  Nothing in the development discharges it, so "with the flag off `runS` IS `run`" is currently a conditional statement.  One-line fix. |
| **V-10** | **L** | `tracker/ROW-CONSTRAINT-STATE.md`, the new section | Names the budget proviso but **not** the opaque-binding gap (a non-row-shaped `SubstEnv` binding is skipped, so the completeness half is not claimed for that solve) nor the skolem/existential reading of "satisfiable".  Both are in `S2-DESIGN.md` §2–§3; the state file is the document people read first. |
| **V-11** | **I** | `tracker/tools/looptrace-diff.py` `KEEP` | **The L2 differential is blind to layer (iii)'s verdicts except through segment truncation.**  `KEEP` is `step learn in inpart sat solve`; the new `rsound`/`senv` records are not compared, and a refutation emits no record on either side.  So "2 355 428 agreeing segments with the flags ON" says the two sides DIE IN THE SAME PLACES, not that they refute the same label with the same reason or spend the same nodes.  What actually pins that is the seed cross-check, and I confirmed it independently: the compiler's messages on `MIN1`/`MIN2`/`SURV1` at base 300 carry "complete search, **2** / **1** / **1** cases", matching `min1_decide_refutes`/`min2_decide_refutes`/`surv1_decide_refutes`'s `searchReason 2` / `1` / `1` exactly.  Worth saying out loud in the report, because §B4-1 reads as if the differential covered the new layer. |
| **V-12** | **I → M if the default is flipped** | `Constraints.decideLabel`, `Subst.decideLabels` | **The budget is per LABEL with no per-SOLVE cap, and its exhaustion is invisible without `-Dermine.rowTrace`.**  Measured (§4.9): 200 000 nodes costs **0.20 s** on a 109-variable single-label pigeonhole, and the budget really does fire on php09/php10.  Worst case per solve is therefore `#labels × 0.2 s`.  At default OFF this is a note; with the default ON it is the one way a valid program's compile time can move by seconds, and the one condition under which the theorem lapses — with no diagnostic. |
| **V-13** | **I** | `Constraints.labelDecide` / `decideLabel` | Two small blame/ordering nits, neither affecting the verdict: (a) the comment says "the FIRST refutation in label order" but `labels` is a `Set[Name]` and the iteration is HASH order — deterministic per build, not sorted, which is why 7 of the report's 667 (seed, label) refutations name a different label from the oracle's; (b) `firstAt`/`firstWhy` are never reset between search branches, so a search-refutation's blame variable is "the first clash seen anywhere in the search", which need not belong to the partition that closes the proof. |

**Nothing CONFIRMED as a false rejection.**  4 800 runs over 1 600 fresh satisfiable-by-
construction systems (two generators, one of them built specifically to force case splits), 1 500
runs over the round-8 hunt, and eight hand-built environment cases: **zero** rejections that the
flags-off compiler did not also make, and every substitution byte-identical.

---

## 7. Every number of mine that differs from the implementer's

| quantity | report | mine |
|---|---|---|
| `core/test` | 913 / 914, one known failure | **912 / 914, two failures** — the second is a `TestLegend` date-formatting flake (`V-4`) |
| `SURV1` at the shipped flags, bases 300–319 | "SOLVED at 300, 301" (§3.1 first table) | **SOLVED 20/20** (agrees with the report's own second table) |
| `FALSE-ACCEPT-2` at the shipped flags | "SOLVED" | **SOLVED 4/20** |
| `#print axioms` coverage | 43 declarations | **78** addressable declarations of 86; same conclusion (0 non-standard) |
| `perf-bench batch` | 12.78 → 12.89 s, "sign flips between rounds", "no resolvable cost" | 12.705 → **12.82 s**; **sign did not flip** in my two rounds (+0.12, +0.11), but ON always ran at a higher load — I would say "≤ 1 %, not separable from load drift" |
| the per-solve maximum of layer (iii) | 3.5–3.7 ms (corpus) | **13.1 ms** on synthetic 20-variable systems, and **201.6 ms** when the budget is spent (pigeonhole) — the corpus figure is not a bound |
| budget exhaustions | 0 (corpus and all gates) | 0 everywhere the report measured; **2 on my pigeonhole instances**, which is the fail-safe working |
| §B8 line counts | see `V-6` | `git diff --numstat` |
| `NoFalseAccept.lean` length | 1 022 (README) / 1 025 (§B8) | **1 025** |

Everything else I re-measured is identical: 861 jobs, 3 888 theorems / 0 non-standard axioms,
1 664 jobs, `TestLoopTrace` 714/714 both ways with the forwarding line, 0 SOLVED of 120 with the
four labels `l35`/`l17`/`l4`/`l20`, 404 → 0 over 1 330 population runs, 1 500 hunt runs with
byte-identical substitutions, `top` 92 673/92 673 and `shouldfail` **56 032 → 56 030**/56 030
agreeing segments with 0 hashdiff and 0 eqdiff, 23 LOADED / 43 REJECTED and 18 LOADED /
16 REJECTED unchanged, `shouldfail/` 40/40, exactly one message move (`inf04`, same field), the
`inf05` batch artefact, 92 673 + 56 003 `ok` records with **one** `decide` and **one** `env`, the
flags-OFF trace with **zero** new records, and the flags-ON `top` trace byte-identical to the
flags-OFF one once the new records are stripped.

---

## 8. Adoption (default ON) — recommendation

**Not yet.  Three cheap prerequisites, then yes.**

The evidence for flipping is strong and I reproduced all of it: on 145 corpus files and two
tracked corpora **not one valid program changes verdict**, the only message that moves is on a
module that already fails, published interfaces are unchanged, `perf-bench` moves by at most ~1 %
in a load-confounded measurement, layer (iii) decides 2.36 M solves for 0.69 s in total, and the
substitutions of 40 000+ satisfiable runs are byte-identical.  Against that, the bug being fixed is
real, minimal (five constraints), reproducible on the shipped compiler at 20/20 bases, and — as my
probe shows — has at least three distinct mechanisms rather than the two recorded, the third being
mediated by the long-lived `SubstEnv` and therefore invisible to every seed gate.

What I would want before the flip:

1. **A tracked gate for the environment-fact path** (`V-2`).  Today the entire `liveInput`
   closure, the `senv` record and the theorem's `envFacts` parameter rest on ONE corpus solve.
   `review-S2/EnvProbe.scala` is 70 lines and covers the concrete, the `Con`, the `VarT` link and
   the transitive cases both ways; adopting it (or a two-solve mode in `SatTermRepro`) turns the
   riskiest surface from "measured once" into "measured every run".
2. **A per-SOLVE budget, or a time budget, plus a visible signal on exhaustion** (`V-12`).  The
   per-label budget costs 0.20 s to spend and there is no cap on how many labels may spend it, so
   a pathological module can add `#labels × 0.2 s` to a compile with no diagnostic and no
   `-Dermine.rowTrace`.  A per-solve node cap (or a `System.nanoTime` deadline) plus at least a
   one-line stderr note — or a counter the driver prints — makes the one condition under which the
   theorem lapses observable in production.
3. **The chain stated in Lean** (`V-1`).  The reason to flip the default is the sentence "an
   accepted program's row constraints have a model, and the substitution the checker publishes is
   faithful to them".  The first half is `solve_noFalseAccept`; the second is S1's `run_noLoss`
   applied at it, and that application is currently prose.  It is a lemma and a corollary.

Residual risks I would accept:

* **The budget's no-verdict path** is fail-safe by construction (accept, never reject) and I
  verified it directly at `budget=0` and on pigeonhole.  Its only cost is that the guarantee
  becomes conditional on a run-time observation — which is why (2) above is about visibility, not
  about correctness.
* **Opaque `SubstEnv` bindings** are skipped, which is sound for refutation and lossy for
  completeness; measured 0 over the corpus, and the counter exists.  Acceptable, but it belongs in
  `ROW-CONSTRAINT-STATE.md` (`V-10`) so that a future reader does not over-read `P`.
* **The worklist/pass difference** between compiler and model can only change which partition is
  blamed and hence the message text; the verdict is the least fixpoint of the same monotone rules
  either way, and nothing in the differential compares messages.  I would not hold the flip for it,
  but it does mean a diagnostic-text regression would not be caught — worth one golden test on
  `inf04`'s new message if the default is flipped, since that is the one user-visible change on the
  whole corpus.
* **Layer (ii)** is cited-sound rather than newly proved, and its saturated-set ↔ `q.expand`
  relation is a differential result.  It contributed nothing on the corpus (0 records).  If the
  flip is wanted with the smallest possible risk surface, **(i) + (iii) alone** buy the entire
  measured benefit (layer (iii) alone takes the 665-seed population to 0 and refutes all six
  witnesses); layer (ii) is the only one of the three whose soundness is not proved at the loop's
  own vocabulary.

---

## 9. How to re-run this review

```bash
# Lean
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition && lake env lean Audit.lean && lake build looptrace
lake env lean <scratch>/AxiomsRev.lean         # 78 declarations, generated by the snippet in <scratch>

# Scala, from the repo root
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
sbt -batch -J-Xmx3g -J-XX:ActiveProcessorCount=2 -Dermine.looptrace=tracker/lean/.lake/build/bin/looptrace core/test
sbt -batch -J-Xmx3g -Dermine.rowSound=true -Dermine.looptrace=… "core/testOnly *TestLoopTrace"

# the seed gates (<scratch>/rbulk.sh is S2's bulk.sh repointed at the MAIN checkout's classes)
rbulk.sh unsat6.txt   300 319 unsat-{off,on}.tsv  [-Dermine.rowSound=true]
rbulk.sh pop665.txt   300 301 pop665-{off,on}.tsv [-Dermine.rowSound=true]
rbulk.sh hunt500.txt    0   2 hunt500-{off,on}.tsv
python3 revgen.py revseeds 800 ; python3 revgen2.py rev2seeds 800   # the false-rejection hunts
python3 php.py phpseeds                                            # the budget measurement
java -cp <scratch>/classes:$(cat target/ermine-classpath) EnvProbe  # the environment probe

# the corpus and the differential
LOOPTRACE_GROUPS='top shouldfail' tracker/tools/looptrace-corpus.sh <out-off>
LOOPTRACE_GROUPS='top shouldfail' LOOPTRACE_JAVA=-Dermine.rowSound=true \
  LOOPTRACE_FLAGS=--flags=rowsound tracker/tools/looptrace-corpus.sh <out-on>
ERMINE_JAVA_OPTS='-XX:ActiveProcessorCount=2 [-Dermine.rowSound=true]' tracker/tools/corpus-run.sh [--incomplete] --batch <out>
PERF_MAX_LOAD=6 PERF_JVM_PROPS='-XX:ActiveProcessorCount=2 [-Dermine.rowSound=true]' tracker/tools/perf-bench.sh batch -n 3
```

Scratch inventory (`/home/dmitry/.claude/jobs/880c725d/tmp/review-S2/`): `leanbuild.log`,
`AxiomsRev.lean` / `axioms.out` / `names.txt`, `coretest-off.log`, `tlt-on.log`, `classes/`
(`BulkRun` + `EnvProbe` against the MAIN checkout), `rbulk.sh`, `unsat6.txt`, `unsat-{off,on}.tsv`,
`pop665-{off,on}.tsv`, `hunt500-{off,on}.tsv`, `revgen.py` / `revseeds/` / `rev-{off,on}.tsv`,
`revgen2.py` / `rev2seeds/` / `rev2-{off,on}.tsv`, `xact.py` / `xseeds/`, `php.py` / `phpseeds/` /
`php-on.tsv`, `EnvProbe.scala`, `lt-{off,on}/` (traces gzipped), `c-{off,on}/`, `ci-{off,on}/`,
`perf-{off,on}-{1,2}/`, `sf.diff`, `constraints.diff`.  No `.ei` was left under `core/examples`
(the harnesses delete them; I re-checked).
