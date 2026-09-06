# S2 DESIGN — NO FALSE ACCEPTANCE: what the fix targets, where each layer runs, and what it costs

2026-09-06.  Worktree `~/research/ermine/ermine-scala-wt-s2`, branch `row-sound` off `fde996a`.
Brief `tracker/loopmodel/briefs/brief-S2.md`; the bug is `tracker/loopmodel/S1-REVIEW.md` §2.3–§2.6,
§7.1 and Appendix B.  **Every flag introduced here defaults to OFF.**  Adoption is the user's
decision; this note and `S2-FIX.md` are the evidence for it, not the decision.

---

## 1. The bug, in one paragraph

`Subst.solve` can return a substitution that VIOLATES a constraint it was given.  Ten seeds are
confirmed on the shipped compiler (S1 review Appendix B), the shortest five constraints long.
Two mechanisms:

* **Saturation is refutation-INCOMPLETE.**  `incorporateAll` reaches `.done` on a residual it
  never derived a contradiction from, and `Subst.reduce` publishes that residual without looking
  at it again (`MIN1`: the substitution says `rho6 = {l22}`, the input says `v6 <- (v4,(|l35|))`).
* **`makeConcrete` deletes a bare row it only checked for CONTAINMENT.**  At `v <- ((|C|))` and
  `v := ((|fs|))`, `ensureSuperset` passes `C ⊆ fs`; `destructiveSub` then drops the bare row
  (`keepDefs` keeps only definitions with ≥ 2 abstract parts, `cancellation` emits nothing for a
  bare one), so `C` is deleted with nothing in its place (`MIN2`).

`labelCheckEarly` misses both because it is UNIT PROPAGATION: sound (`LabelProp.refuted_unsat`,
`LabelAlgo`) and incomplete.  Every one of the ten seeds needs a CASE SPLIT.

---

## 2. The property the fix targets, stated at the compiler level

> **P (no false acceptance).**  Let `solve(csz)` be a call to `com.clarifi.reporting.ermine.Subst.solve`
> that RETURNS NORMALLY, under `-Dermine.rowSound.decide=true`.  Let
>
> * `cs` be the constraint list `solve` unbinds from `csz` (`unbindExists`, `Subst.scala:1127`),
> * `q = PQueue.build(Exists(l,[],cs))._1` the partitions built from it — i.e. `cs`'s row
>   constraints in the solver's own `(lhs, RHS)` normal form — and
> * `E` the set of facts `{ v <- σ(v) : v mentioned in q, σ = hm.types, σ(v) row-shaped }`,
>   closed under the variables those facts introduce (§3),
>
> then the system `q ∪ E` is SATISFIABLE: there is an assignment `rho` of a set of labels to
> every variable of `q ∪ E` under which every partition's parts are pairwise disjoint and union
> to its whole — **provided** (a) the search budget was not exhausted at any label
> (`GenRules.rowSoundBudgetHits` did not increase during the call), and (b) `σ` bound no
> mentioned variable to a non-row-shaped type (the `opaque` count of the `rsound env` record
> is 0).

Two honest qualifications, both stated rather than hidden:

* **Skolems are existential in P.**  A `Skolem` row variable cannot in fact be instantiated, so
  P's "satisfiable" is satisfiability with every variable existentially quantified.  That is
  strictly weaker than "the program type-checks", and it is the same reading `labelClash` has
  always had.  It costs nothing in the refutation direction: no model with skolems fixed exists
  if none exists with them free.
* **P is about ONE `solve`.**  The type checker's other constraints are not in scope, and P says
  nothing about `Subst.reduce`, which runs after the check and can still panic (`PANIC-1`).

The half of P that is a THEOREM rather than a measurement is layer (iii)'s: pass ⇒ a model was
CONSTRUCTED AND CHECKED (§4).  Layers (i) and (ii) contribute refutations, not the guarantee;
they are separately switchable because they are separately measurable and (ii) is nearly free.

### What P does NOT say

`solve` may still DIE — that is the point — and it may still die in `reduce` with a panic rather
than a diagnostic.  P is "accepted ⇒ the constraints have a model", the converse of S1's
`run_noLoss`/`solve_sound`, which are conditional on `SSat (sys s₀)`.  Chaining the two is Part B's
`solve_noFalseAccept`.

---

## 3. What "the input" is

S1 review **Z-6**: `Subst.solve` does NOT `substType` its input before `PQueue.build`
(`Subst.scala:1135`; `substType` is applied only at the `reduce` call, `:1260`) and
`SubstEnv.types` is a long-lived mutable map shared by the whole checker (`Subst.scala:93-102`).
So `q`'s partitions may mention variables the environment already binds, and deciding `q` alone
decides a SUB-system: sound to refute from, but not the property one wants to state.

The check therefore runs on **`q` plus the environment as FACTS**:

| `hm.types(v)` | fact added |
|---|---|
| absent | — |
| `VarT(u)` | `v <- (u)` (a link), and `u` is then looked up too |
| `ConcreteRho(_, f)` | `v <- ((\|f\|))` |
| `Con(_, n, _, _)` | `v <- ((\|n\|))` |
| anything else | none; COUNTED as `opaque` |

Adding facts rather than applying a substitution is deliberate, for two reasons.

1. **It draws no ids.**  `PQueue.build` mints a fresh variable for a non-variable left-hand side
   (`Constraints.scala:662`), so building a second queue from `cs map substType` would consume
   `Supply` ids and change every id the solve goes on to hand out — the flag would then not be
   observationally inert even in the refutation-free case.  Reading `hm.types` changes nothing.
2. **It is equisatisfiable.**  `hm.types` is idempotent (`instantiateType` substitutes the new
   binding through the whole map before inserting it), so `q ∪ E` and `q[σ]` interpret each
   other: a model of `q ∪ E` restricts to one of `q[σ]`, and a model of `q[σ]` extends by
   `rho(v) := rho(σ v)`.  The closure in the table's second row is what makes the "idempotent"
   step safe without relying on it.

The `opaque` count is traced (`rsound env`) precisely so that "this never happened" is a
measurement, and **Part B added a second record for the same reason**: `senv site loc v<id>
<term>`, one per environment fact, written by `RowTrace.solveInput` under
`-Dermine.rowSound.decide` in `scon`'s own term language.  Without it a replay cannot see the
facts and cannot reproduce a flags-ON trace — which is exactly what the L2 differential caught
on the one corpus solve where the environment matters (`S2-FIX.md` §B4-1).  When it is non-zero the decision runs on a sub-system: refutations stay sound,
P's completeness half is not claimed for that solve.

Layer (ii) reads the SATURATED set `ps = q.expand.toList` instead, with no environment facts:
the loop applies the environment itself as it goes (`makeConcrete` and `makeEmpty` call
`instantiateType`), so `ps` is already live.

---

## 4. The three layers

### (i) Bare-row exactness — `Constraints.makeConcrete`, flag `-Dermine.rowSound.bare`

`makeConcrete v fs incm proc` checks every definition of `v` with `ensureSuperset(v.loc, concr, fs)`.
For a definition with NO abstract part — a bare `v <- ((|C|))` — the semantics forces `C = fs`,
because both are definitions of the same row.  With the flag on, such a definition goes to a new
`ensureExactly`, which raises the SAME death `ensureSuperset` raises ("Row types failed to unify",
S1's death site 7) when `C ≠ fs`.  Non-bare definitions keep `ensureSuperset` unchanged.

Sound by `Rowpartition/Loop/Sound.lean`'s `bare_refutes`: two different bare rows for one variable
refute the system.  So the new death is a REFUTATION, and it is the refutation S1 already covers.

Trace record `rsound … bare <var> <C> <fs>`.

### (ii) `labelClash` on the saturated set — `Subst.solve`, flag `-Dermine.rowSound.saturated`

The same unit propagation the input already gets, run on `ps = q.expand.toList` right after
saturation.  Sound by `Rowpartition.refute_saturated_sound` (`tracker/lean/Rowpartition/Saturate.lean`),
which the code's own comment at `Subst.scala:1247-1258` already cites.  The flag for it was removed
on 2026-09-02 because it was "measured on both corpora at ZERO additional refutations" — a fact
about the corpora: it catches all six compiler-confirmed witnesses and 1 146 of the 1 166 model
false acceptances (S1 review §7.1).

It is independent of `GenRules.labelCheck`, so it can be measured on its own.

Trace record `rsound … sat <label> <lhs> <reason>`; diagnostic as in §5.

### (iii) The complete per-label decision — `Constraints.labelDecide`, flag `-Dermine.rowSound.decide`

**The decomposition.**  A partition `v <- (u₁…u_k, C)` says the parts are pairwise disjoint and
union to `v`.  Project onto ONE label `l`, with bits `b[x] = [l ∈ rho x]` and `c = [l ∈ C]`:

    b[u₁] + … + b[u_k] + c ≤ 1     and     b[v] = that sum.

The system is satisfiable **iff every label's boolean problem is**: a model is assembled label by
label, and a label that appears in no concrete set has the all-false model (`ones = 0`, `b[v] = 0`
satisfies every partition), so only the MENTIONED labels need deciding — the same label range
`labelClash` walks.

**The procedure.**  DPLL.  `propagate` is `checkLabel`'s fixpoint made worklist-driven, re-using
its five rules and its five message strings verbatim, so a refutation that propagation alone would
find is reported in the words the shipped check uses.  `search` then branches on the first
unassigned bit (FALSE first) and recurses.  A branch that assigns every bit without a clash is
**VERIFIED against every partition directly** before SAT is returned — so "passes" means "a model
was exhibited and checked", not "no rule complained".  If that verification ever fails the answer
is NO VERDICT, never UNSAT: a propagator bug can cost a refutation but cannot cause a false
rejection.

**Where it runs.**  In `Subst.solve`, AFTER `labelCheckEarly` and BEFORE `q.expand`.  After the
early check, so that an input unit propagation already refutes reports exactly today's message and
the corpus delta this stage measures is (iii)'s OWN refutations.  Before `expand`, because refuting
an unsatisfiable input before the saturation can diverge on it is half the point
(`Rowpartition/ResGuardDiverge.lean`: a four-constraint unsatisfiable system on which resolution
has derivations of every length is refuted at a single label).

**The budget.**  There are TWO caps — `budget` per label and `solveBudget` for the whole solve
— and either can lapse the theorem; both report `LabelNoVerdict`, refute nothing, are counted
(`rowSoundBudgetHits`, apart from the fail-safe's `rowSoundCheckFails`), traced, and now
**print a one-line warning on stderr naming the site**, because a condition under which the
theorem says nothing must not be invisible (S2 review V-8, V-12).

Deciding these systems is NP-complete — with a whole known present the constraint
is exactly 1-in-3-SAT, Schaefer's problem, which the shipped `checkLabel` comment already names.
`-Dermine.rowSound.budget=<n>` (default 200 000) bounds the DECISION NODES per label.  On
exhaustion the result is `LabelNoVerdict`: nothing is refuted, `GenRules.rowSoundBudgetHits` is
incremented and a `rsound … budget` record is written.  That is why P carries "the budget was not
exhausted" as a hypothesis, and why exhaustion is counted rather than silent.

Trace records `rsound … decide <label> <lhs> <nodes> <reason>`, `rsound … ok <labels> <parts>
<nodes> <micros>`, `rsound … budget <label> <reason>`, `rsound … env <facts> <opaque>`.

---

## 5. Flags and diagnostics

| property | default | layer |
|---|---|---|
| `-Dermine.rowSound=true` | `false` | master: turns all three on |
| `-Dermine.rowSound.bare=true\|false` | master | (i) bare-row exactness |
| `-Dermine.rowSound.saturated=true\|false` | master | (ii) `labelClash` on `q.expand` |
| `-Dermine.rowSound.decide=true\|false` | master | (iii) the complete decision |
| `-Dermine.rowSound.budget=<int>` | `200000` | (iii)'s node budget per label |
| `-Dermine.rowSound.solveBudget=<int>` | `1000000` | (iii)'s node budget for a whole SOLVE, summed over its labels (added after the S2 review, V-12: the per-label budget alone bounds a solve at `#labels × 0.2 s`) |

Read once at class-init in `Constraints.GenRules`, like every other row-solver switch, so a run is
a constant.  `GenRules.toString` gains `+rsbare`, `+rssat`, `+rsdecide` — empty at the defaults.

Diagnostics:

* (i) — `Row types failed to unify: R1 = … R2 = …`, the existing `ensureSuperset` death, blamed at
  the variable's location and the enclosing `Located`, i.e. death site 7 exactly.
* (ii) and (iii) — `Row partitions are unsatisfiable at field '<label>': <reason>`, the existing
  `labelClash` diagnostic, through the SAME blame search (`Subst.solve`'s `rowUnsat`, factored out
  of `checkLabels` unchanged): the input `Part`s mentioning the field whose location is in the file
  being compiled, preferring the one whose left-hand variable is the refuted partition's.
  (iii)'s own reason clause, when propagation was silent, is
  `no assignment of this field to the parts satisfies every partition (complete search, N cases;
  unit propagation alone does not see it)`.

Layer (ii) and (iii) refutations on a SATURATED or MINTED variable have no input `Part` with that
left-hand variable, so the blame falls back to the first input `Part` mentioning the label in this
file — a real source location, one constraint less precise.

---

## 6. Cost model

* (i) is a set equality where a `subsetOf` used to be: O(|C|), same order, no allocation.
* (ii) is one `labelClash` over `ps` — `L · P · V` bit-propagation for `L` mentioned labels, `P`
  saturated partitions and `V` variables, i.e. the cost the input check already pays, on the
  bigger set.  `incomplete/gu05`'s largest solve saturates to 1 372 partitions (458 with
  `splitKey`, the default), which is the corpus's worst case.
* (iii) is `L` DPLL searches.  Per label, indexing is O(P + Σ|parts|) and each propagation is
  worklist-driven, so the unit-propagation part is linear in the occurrence count; the search
  multiplies that by the number of decision NODES, which is bounded by the budget.

MEASURED (`S2-FIX.md` §5, the eight corpus groups, 2 355 392 decided solves): **0.69 s in total**,
1 051 decision nodes, **0 budget exhaustions**; over the 26 404 solves that have any row
constraint at all, median **7 µs**, p99 94 µs, p99.9 1.6 ms.  The per-solve maximum is 3.5–3.7 ms,
at `incomplete/gu05`'s one labelled solve (10 labels, **18 input partitions**, 4 decision nodes),
and it is a cold-path figure: that code runs on 7 834 of 2.36 M solves — 12 380 per-label decisions in all — never often
enough to be compiled.  Note the shape of the number that matters: gu05's 1 372-partition figure is its
SATURATED set, and (iii) reads the INPUT, whose largest instance anywhere in the corpus is 18
partitions.  `perf-bench.sh batch` shows no resolvable difference (12.78 s vs 12.89 s median of
three interleaved rounds, inside the per-round spread).

---

## 7. Byte-identity with the flags off

Nothing above is reachable at the defaults:

* (i) is a guarded `case` arm ahead of the existing one, guarded on `GenRules.rowSoundBare`;
* (ii) and (iii) are `if (GenRules.rowSound*) …` statements in `solve`;
* every new `RowTrace` record is inside `RowTrace.rowSound`, itself inside `if (enabled)`;
* `checkLabels`'s body was factored into `rowUnsat` with the same statements in the same order;
* `GenRules.toString` gains three suffixes that are empty at the defaults.

The evidence that this is so is the gate table in `S2-FIX.md`: `core/test`, `TestLoopTrace`, the
L2 corpus row trace byte-for-byte against the main tree's, the published `.ei` and the 18 tracked
seeds at ten bases.
