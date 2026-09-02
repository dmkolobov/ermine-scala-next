/-
# Ticket item 8a: may the label-clash check run on the SATURATED set?

`Subst.solve` (`Subst.scala`, `def solve`) runs the per-concrete-label refutation
`Constraints.labelClash` on `q` -- the INPUT partitions -- and NOT on `q.expand`, the
saturated set the solver actually reduces over.  Running it on the saturated set would
refute strictly more programs, because propagation is monotone in the SYSTEM
(`LabelProp.forced_mono`).  The comment at `Subst.scala` (was line 1119) records why that move is
not free: `q.expand` is not a superset of `q` -- `makeEmpty`, `makeConcrete`,
`destructiveSub` and `instantiate` all DELETE partitions and rename variables -- so
`forced_mono` does not apply, and the saturated set is a DIFFERENT system rather than a
larger one.

Since the check only ever REFUTES, what licences the move is exactly one implication:

    the input is satisfiable  ==>  the saturated set is satisfiable

(contrapositive: a refutation of the saturated set implies the input has no model).  This
file proves that implication for the rule set the shipped compiler runs
(`-Dermine.genRules=cut`), and is explicit about the four things it does not cover.

## What was already available

`SplitNecessary.CutRuleSteps.satisfiable_iff` gives the much stronger *iff* for
`CutRuleStep`: common-subexpression REUSE and FOLD, `splitConcrete` REUSE and MINT,
cancellation, substitution, self-substitution, common partition, and resolution.  That is
most of the shipped default, and it enters here verbatim as the `cutRule` constructor.

## What this file adds

Four solver behaviours that no existing step relation models.

1. **EMPTY** (`Constraints.makeEmpty`, `Constraints.scala` (was line 983)).  With `v <- ()` in the
   system and another partition of `v`: (a) every variable part of that partition is
   forced empty (`empty_forces_parts`, from `Rules.rule2_entails`); (b) every OTHER
   constraint may have `v` erased from its right-hand side (`empty_erases_var`, from
   `Canonical.sat_erase_empty`, an iff -- the erasure is exact); (c) if the other
   partition has a nonempty concrete part the system is UNSATISFIABLE
   (`empty_conc_unsat`, from `Rules.rule2_conc`) -- the Scala's
   `"Incompatible instantiations of"`.

2. **CONCRETE** (`Constraints.makeConcrete` / `subPartitions` / `destructiveSub`,
   `Constraints.scala` (was line 1021)).  With `v <- (|fs|)` in the system, every constraint
   mentioning `v` may absorb it (`concrete_absorbs`, from `Canonical.sat_absorb`, also an
   iff); and `ensureSuperset` refutes when the absorbing constraint's own concrete part
   is not contained in `fs` (`concrete_superset_unsat`, from `Rules.rule11_unsat`).

3. **RENAME** (`Constraints.unify` / `instantiate` / `replace`, `Constraints.scala` (was line 952),
   and the common-partition branch of `incorporateAll`).  With `v <- (u)` in the system,
   `rho v = rho u` (`Canonical.sat_eqc`), so every constraint may be rewritten by
   `Canonical.substC v u` (`rename_substitutes`, via `Canonical.models_substG`).  The
   Scala ALSO emits `u <- ()` whenever the rename makes a variable occur twice on one
   right-hand side (`Constraints.replace`, the `abs.contains(v) && abs.contains(u)`
   case).  That is `Rules.rule3_entails`, and it is a SEPARATE constructor here because
   the set-shaped `Divergence.vset` cannot see a duplicate at all: modelling the pair
   honestly needs the list shape.

4. **WEAKEN**.  The solver DELETES constraints on at least five paths: `incorporateAll`
   discards the dequeued rule on its common-partition, empty, concrete and singleton
   branches, and `makeEmpty`, `destructiveSub` and `instantiate` remove every partition
   mentioning the eliminated variable.  Every step relation in this development is
   monotone (`.subset : G ⊆ G'`), so deletion is unmodelled.  `SatStep.weaken` adds it in
   the one direction item 8a needs -- a model of a system models every subsystem -- and
   it is the reason the assembled theorem is an IMPLICATION and not an iff
   (`satStep_not_reflecting` exhibits the failure).

`SatStep` collects all of this; `SatSteps n` iterates it; `SatSteps.sat_mono` is the
implication above, and `refute_saturated_sound` is the licence in the form the compiler
needs.  See the Summary for the four gaps.
-/
import Rowpartition.SplitNecessary
import Rowpartition.Canonical
import Rowpartition.LabelProp

namespace Rowpartition

/-! ## 1. Constraints that determine their left-hand side

`RHSEmpty()` and `RHSConcr(fs)` are the two right-hand sides with no variable part; in
this model they are the constraints `⟨v, [], ∅⟩` and `⟨v, [], fs⟩`, and each pins its
left-hand variable to a concrete row.  `Basic.sat_zero` is that unfolding; the two
lemmas here are the System-shaped readings the steps below use. -/

/-- A fully concrete constraint in the system pins its left-hand variable. -/
theorem eq_conc_of_mem {rho : Assign} {G : System} {v : Var} {fs : Finset Label}
    (hd : (⟨v, [], fs⟩ : Constraint) ∈ G) (hm : SModels rho G) : rho v = fs :=
  (sat_zero rho v fs).mp (hm _ hd)

/-- A constraint of the system whose left-hand side is `v`, read at the components the
rules need.  (Structure eta: `c` IS `⟨c.lhs, c.vars, c.conc⟩`.) -/
theorem sat_of_lhs_eq {rho : Assign} {G : System} {v : Var} {c : Constraint}
    (hc : c ∈ G) (hlhs : c.lhs = v) (hm : SModels rho G) :
    Sat rho ⟨v, c.vars, c.conc⟩ := by
  rw [← hlhs]
  exact hm c hc

/-! ## 2. EMPTY -- `Constraints.makeEmpty`

```
  a <-
  a <- x+
 ---------
  (x <-)+
```
plus the erasure of an empty variable from every other right-hand side (`rhs - v` in the
`u != v` branch of `makeEmpty`'s fold), plus the incompatibility that the same branch
raises as an error. -/

/-- **EMPTY (a).**  If `v <- ()` and `v <- (xs, K)` are both in the system, every
variable of `xs` is empty, so the derived constraint `x <- ()` may be ADDED with no
change of models.  This is `Rules.rule2_entails` in System shape. -/
theorem empty_forces_parts {rho : Assign} {G : System} {v x : Var} {c : Constraint}
    (hd : (⟨v, [], (∅ : Finset Label)⟩ : Constraint) ∈ G) (hc : c ∈ G) (hlhs : c.lhs = v)
    (hx : x ∈ c.vars) (hm : SModels rho G) :
    SModels rho (insert ⟨x, [], (∅ : Finset Label)⟩ G) := by
  intro e he
  rcases Finset.mem_insert.mp he with rfl | he'
  · exact rule2_entails hx rho
      (models_of_two (hm _ hd) (sat_of_lhs_eq hc hlhs hm))
  · exact hm e he'

/-- **EMPTY (b).**  An empty variable may be deleted from any right-hand side that
mentions it.  `Canonical.sat_erase_empty` is an IFF, so the erased constraint says
exactly what the original did; adding it is therefore model-preserving. -/
theorem empty_erases_var {rho : Assign} {G : System} {v : Var} {c : Constraint}
    (hd : (⟨v, [], (∅ : Finset Label)⟩ : Constraint) ∈ G) (hc : c ∈ G) (hv : v ∈ c.vars)
    (hm : SModels rho G) :
    SModels rho (insert ⟨c.lhs, c.vars.erase v, c.conc⟩ G) := by
  intro e he
  rcases Finset.mem_insert.mp he with rfl | he'
  · exact (sat_erase_empty hv (eq_conc_of_mem hd hm)).mp (hm c hc)
  · exact hm e he'

/-- **EMPTY (c), a refutation.**  If `v` is empty and some other partition of `v` has a
NONEMPTY concrete part, the system has no model.  This is the `case _ => tml.die` arm of
`makeEmpty`'s `aux` (`"Incompatible instantiations of '" + v + "'"`), and it is
`Rules.rule2_conc`.  Stated as a negative result: no model exists, for any `rho`. -/
theorem empty_conc_unsat {G : System} {v : Var} {c : Constraint}
    (hd : (⟨v, [], (∅ : Finset Label)⟩ : Constraint) ∈ G) (hc : c ∈ G) (hlhs : c.lhs = v)
    (hne : c.conc ≠ ∅) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  exact hne (rule2_conc (hm _ hd) (sat_of_lhs_eq hc hlhs hm))

/-! ## 3. CONCRETE -- `Constraints.makeConcrete`, `subPartitions`, `destructiveSub`

```
  v <- (|fs|)
  u <- (S, k)      v ∈ S
 ----------------------------
  u <- (S \ {v}, k ∪ fs)
```
and `ensureSuperset` as the refutation half. -/

/-- **CONCRETE.**  A variable known to denote the concrete row `fs` is absorbed into the
concrete part of every constraint that mentions it.  `Canonical.sat_absorb` is an iff
whose extra conjunct is the disjointness `Disjoint c.conc fs`, so the forward direction
-- the one used here -- needs no side condition: satisfaction of the original constraint
already supplies it. -/
theorem concrete_absorbs {rho : Assign} {G : System} {v : Var} {fs : Finset Label}
    {c : Constraint} (hd : (⟨v, [], fs⟩ : Constraint) ∈ G) (hc : c ∈ G) (hv : v ∈ c.vars)
    (hm : SModels rho G) :
    SModels rho (insert ⟨c.lhs, c.vars.erase v, c.conc ∪ fs⟩ G) := by
  intro e he
  rcases Finset.mem_insert.mp he with rfl | he'
  · exact ((sat_absorb hv (eq_conc_of_mem hd hm)).mp (hm c hc)).1
  · exact hm e he'

/-- **CONCRETE, the refutation half.**  `makeConcrete` calls `ensureSuperset` on every
other partition of `v` before substituting.  If that partition's concrete part is not
contained in `fs`, the system has no model: `Rules.rule11_unsat`. -/
theorem concrete_superset_unsat {G : System} {v : Var} {fs : Finset Label}
    {c : Constraint} (hd : (⟨v, [], fs⟩ : Constraint) ∈ G) (hc : c ∈ G) (hlhs : c.lhs = v)
    (hns : ¬ c.conc ⊆ fs) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  exact rule11_unsat hns rho (models_of_two (hm _ hd) (sat_of_lhs_eq hc hlhs hm))

/-! ## 4. RENAME -- `Constraints.unify` / `instantiate` / `replace`

`v <- (u)` is the equation `rho v = rho u` (`Canonical.sat_eqc`), and `replace` rewrites
every partition by `v := u`.  The de-duplication side effect is section 5. -/

/-- Substituting equals for equals inside a whole SYSTEM changes nothing.  This is
`Canonical.models_substG` transported from `List Constraint` to `Finset Constraint`;
the image is taken with `Finset.image`, which merges constraints the rename makes
equal -- harmless, because `SModels` is a `∀`. -/
theorem sModels_image_substC {rho : Assign} {a b : Var} (h : rho a = rho b) (G : System) :
    SModels rho (G.image (substC a b)) ↔ SModels rho G := by
  have hiff : SModels rho (G.image (substC a b)) ↔ Models rho (substG a b G.toList) := by
    simp only [substG]
    constructor
    · intro hm c hc
      obtain ⟨f, hf, rfl⟩ := List.mem_map.mp hc
      exact hm _ (Finset.mem_image_of_mem _ (Finset.mem_toList.mp hf))
    · intro hm e he
      obtain ⟨f, hf, rfl⟩ := Finset.mem_image.mp he
      exact hm _ (List.mem_map_of_mem (Finset.mem_toList.mpr hf))
  rw [hiff, models_substG h, ← sModels_iff_models]

/-- **RENAME.**  With `v <- (u)` in the system, the whole system may be rewritten by
`substC v u` and the rewritten copy KEPT ALONGSIDE the original (the union below): every
model of the system models both halves. -/
theorem rename_substitutes {rho : Assign} {G : System} {v u : Var}
    (hd : (⟨v, [u], (∅ : Finset Label)⟩ : Constraint) ∈ G) (hm : SModels rho G) :
    SModels rho (G ∪ G.image (substC v u)) := by
  have heq : rho v = rho u := (sat_eqc rho v u).mp (hm _ hd)
  intro e he
  rcases Finset.mem_union.mp he with he' | he'
  · exact hm e he'
  · exact (sModels_image_substC heq G).mpr hm e he'

/-! ## 5. DE-DUPLICATION -- the second half of `Constraints.replace`

`replace` emits `Partition(u, RHSEmpty(), DeDuplication)` exactly when the rename makes
`u` occur twice on one right-hand side.  It has to be its own step: the set-shaped view
of a right-hand side (`Divergence.vset`) collapses the two occurrences, so no
set-shaped rule can even state the premise. -/

/-- **DE-DUPLICATION.**  A variable occurring at least twice on one right-hand side is
empty, so `w <- ()` may be added.  `Rules.rule3_entails`. -/
theorem dedup_forces_empty {rho : Assign} {G : System} {c : Constraint} {w : Var}
    (hc : c ∈ G) (hw : 2 ≤ c.vars.count w) (hm : SModels rho G) :
    SModels rho (insert ⟨w, [], (∅ : Finset Label)⟩ G) := by
  intro e he
  rcases Finset.mem_insert.mp he with rfl | he'
  · exact rule3_entails hw rho (models_of_one (hm c hc))
  · exact hm e he'

/-! ## 6. The assembled step relation

`SatStep` is the union of: the cut calculus (`SplitNecessary.CutRuleStep`), the five
behaviours above, and DELETION.  Only the last is one-directional. -/

/-- One step of the solver, as far as SATISFIABILITY is concerned. -/
inductive SatStep : System → System → Prop
  /-- Any rule of the shipped default calculus (`-Dermine.genRules=cut`). -/
  | cutRule {G G' : System} : CutRuleStep G G' → SatStep G G'
  /-- `makeEmpty`, propagation half: `v <- ()` and `v <- (xs, K)` force `x <- ()`. -/
  | empty {G : System} {v x : Var} {c : Constraint} :
      (⟨v, [], (∅ : Finset Label)⟩ : Constraint) ∈ G → c ∈ G → c.lhs = v → x ∈ c.vars →
      SatStep G (insert ⟨x, [], (∅ : Finset Label)⟩ G)
  /-- `makeEmpty`, erasure half: an empty variable leaves every other right-hand side. -/
  | eraseEmpty {G : System} {v : Var} {c : Constraint} :
      (⟨v, [], (∅ : Finset Label)⟩ : Constraint) ∈ G → c ∈ G → v ∈ c.vars →
      SatStep G (insert ⟨c.lhs, c.vars.erase v, c.conc⟩ G)
  /-- `makeConcrete` / `destructiveSub`: a concretely known variable is absorbed. -/
  | concrete {G : System} {v : Var} {fs : Finset Label} {c : Constraint} :
      (⟨v, [], fs⟩ : Constraint) ∈ G → c ∈ G → v ∈ c.vars →
      SatStep G (insert ⟨c.lhs, c.vars.erase v, c.conc ∪ fs⟩ G)
  /-- `replace`'s de-duplication emission. -/
  | dedup {G : System} {c : Constraint} {w : Var} :
      c ∈ G → 2 ≤ c.vars.count w → SatStep G (insert ⟨w, [], (∅ : Finset Label)⟩ G)
  /-- `unify` / `instantiate` / `replace`: rewrite the system by `v := u`, KEEPING the
  originals.  The Scala also removes every partition it rewrote; that deletion is the
  composite of this step with a following `weaken`. -/
  | rename {G : System} {v u : Var} :
      (⟨v, [u], (∅ : Finset Label)⟩ : Constraint) ∈ G →
      SatStep G (G ∪ G.image (substC v u))
  /-- DELETION, in the only direction item 8a needs: a model of a system models every
  subsystem.  This is the one constructor that is not an equivalence, and hence the
  reason the theorems below are implications (see `satStep_not_reflecting`). -/
  | weaken {G G' : System} : G' ⊆ G → SatStep G G'

/-- **Every step preserves satisfiability.**  Each case is the corresponding lemma above;
`cutRule` is `SplitNecessary.CutRuleStep.satisfiable_iff` (whose forward direction may
change the assignment, since `splitConcrete`'s mint and `resolution` introduce names), and
`weaken` is `Divergence.SModels.mono`. -/
theorem SatStep.sat_mono {G G' : System} (h : SatStep G G')
    (hsat : ∃ rho, SModels rho G) : ∃ rho, SModels rho G' := by
  cases h with
  | cutRule hstep => exact hstep.satisfiable_iff.mp hsat
  | empty hd hc hlhs hx =>
      obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, empty_forces_parts hd hc hlhs hx hm⟩
  | eraseEmpty hd hc hv =>
      obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, empty_erases_var hd hc hv hm⟩
  | concrete hd hc hv =>
      obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, concrete_absorbs hd hc hv hm⟩
  | dedup hc hw =>
      obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, dedup_forces_empty hc hw hm⟩
  | rename hd =>
      obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, rename_substitutes hd hm⟩
  | weaken hsub =>
      obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, SModels.mono hsub hm⟩

/-- `SatSteps n G G'`: `G'` is reachable from `G` by exactly `n` solver steps. -/
inductive SatSteps : ℕ → System → System → Prop
  | refl (G : System) : SatSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      SatSteps n G G' → SatStep G' G'' → SatSteps (n + 1) G G''

/-- **The saturation preserves satisfiability.**  A satisfiable input stays satisfiable
however many steps the solver takes.  The converse is FALSE (`satSteps_not_reflecting`). -/
theorem SatSteps.sat_mono {n : ℕ} {G₀ G : System} (h : SatSteps n G₀ G) :
    (∃ rho, SModels rho G₀) → ∃ rho, SModels rho G := by
  induction h with
  | refl => exact id
  | tail _ hstep ih => exact fun hsat => hstep.sat_mono (ih hsat)

/-! ## 7. The licence for ticket item 8a -/

/-- **Unsatisfiability of a reachable system refutes the input.**  Any sound refutation
run on the saturated set -- not only the label check -- is therefore a sound refutation of
the input. -/
theorem saturated_unsat_sound {n : ℕ} {G₀ G : System} (h : SatSteps n G₀ G)
    (hu : ¬ ∃ rho, SModels rho G) : ¬ ∃ rho, SModels rho G₀ :=
  fun hsat => hu (h.sat_mono hsat)

/-- **The licence for ticket item 8a.**  If per-label propagation clashes on a system the
solver has reached from `G₀`, then `G₀` itself has no model.  So `Subst.solve` may run
`labelClash` on `q.expand` instead of on `q` without ever rejecting a satisfiable input.
(`LabelProp.Refuted` lives on `List Constraint`; `Divergence.sModels_iff_models` is the
bridge.) -/
theorem refute_saturated_sound {n : ℕ} {G₀ G : System} (h : SatSteps n G₀ G)
    (hr : Refuted G.toList) : ¬ ∃ rho, SModels rho G₀ := by
  refine saturated_unsat_sound h ?_
  rintro ⟨rho, hm⟩
  exact refuted_unsat hr ⟨rho, (sModels_iff_models rho G).mp hm⟩

/-- **The contrapositive, in the form the compiler cares about: no false rejections.**  A
satisfiable input is never refuted at the saturated set, so moving the check cannot make
the compiler reject a well-typed program. -/
theorem saturated_not_refuted_of_sat {n : ℕ} {G₀ G : System} (h : SatSteps n G₀ G)
    (hsat : ∃ rho, SModels rho G₀) : ¬ Refuted G.toList :=
  fun hr => refute_saturated_sound h hr hsat

/-! ## 8. Negative results: the implication does not reverse

`CutRuleStep` alone gives an IFF (`SplitNecessary.CutRuleStep.satisfiable_iff`).  Adding
deletion destroys the other direction, and it must be added: the solver really does delete
(`incorporateAll` drops the dequeued rule on four of its branches; `makeEmpty`,
`destructiveSub` and `instantiate` drop every partition mentioning the eliminated
variable). -/

/-- `x = {5}` and `x = {6}` at once: the standard unsatisfiable two-constraint system
(`Basic.Counterexample.G` as a `System`). -/
def clashSystem : System := {⟨0, [], {5}⟩, ⟨0, [], {6}⟩}

/-- `clashSystem` has no model. -/
theorem clashSystem_unsat : ¬ ∃ rho, SModels rho clashSystem := by
  rintro ⟨rho, hm⟩
  have h5 : rho 0 = ({5} : Finset Label) :=
    (sat_zero rho 0 _).mp (hm _ (by simp [clashSystem]))
  have h6 : rho 0 = ({6} : Finset Label) :=
    (sat_zero rho 0 _).mp (hm _ (by simp [clashSystem]))
  rw [h5] at h6
  exact absurd h6 (by decide)

/-- The empty system is modelled by anything. -/
theorem sModels_empty (rho : Assign) : SModels rho (∅ : System) := by
  intro c hc
  exact absurd hc (Finset.notMem_empty c)

/-- **A single step does NOT reflect satisfiability.**  Deleting constraints can turn an
unsatisfiable system into a satisfiable one, so `SatStep.sat_mono` cannot be upgraded to
an iff -- which is exactly why item 8a licences running a REFUTATION-ONLY check on the
saturated set and nothing more.  A check that ACCEPTED on the saturated set would be
unsound. -/
theorem satStep_not_reflecting :
    ∃ G G' : System, SatStep G G' ∧ (∃ rho, SModels rho G') ∧ ¬ ∃ rho, SModels rho G :=
  ⟨clashSystem, ∅, SatStep.weaken (Finset.empty_subset _),
    ⟨fun _ => ∅, sModels_empty _⟩, clashSystem_unsat⟩

/-- The same, for runs: one step is a run of length one. -/
theorem satSteps_not_reflecting :
    ∃ (G G' : System), SatSteps 1 G G' ∧ (∃ rho, SModels rho G') ∧ ¬ ∃ rho, SModels rho G :=
  ⟨clashSystem, ∅, SatSteps.tail (SatSteps.refl _) (SatStep.weaken (Finset.empty_subset _)),
    ⟨fun _ => ∅, sModels_empty _⟩, clashSystem_unsat⟩

/-! ## 9. Non-vacuity

A guard against a formalisation whose premises no system can meet: the new steps really
do fire, and really do change the system. -/

/-- `x <- ()` together with `x <- (y, z)`: the shape `makeEmpty` dequeues. -/
def emptySeed : System := {⟨0, [], ∅⟩, ⟨0, [1, 2], ∅⟩}

/-- The EMPTY propagation step fires on `emptySeed`, deriving `y <- ()`. -/
theorem emptySeed_step :
    SatStep emptySeed (insert ⟨1, [], (∅ : Finset Label)⟩ emptySeed) :=
  SatStep.empty (v := 0) (c := ⟨0, [1, 2], ∅⟩) (by decide) (by decide) rfl (by decide)

/-- ...and what it derives is genuinely new, so the step strictly grows the system and
the premises of `SatStep.empty` are not vacuous. -/
theorem emptySeed_step_new :
    (⟨1, [], (∅ : Finset Label)⟩ : Constraint) ∉ emptySeed := by decide

/-- Two steps compose: `makeEmpty` first derives `y <- ()`, then erases `y` from the
right-hand side of `x <- (y, z)`, leaving `x <- (z)`. -/
theorem emptySeed_run :
    SatSteps 2 emptySeed
      (insert ⟨0, [2], (∅ : Finset Label)⟩ (insert ⟨1, [], (∅ : Finset Label)⟩ emptySeed)) :=
  SatSteps.tail (SatSteps.tail (SatSteps.refl _) emptySeed_step)
    (SatStep.eraseEmpty (v := 1) (c := ⟨0, [1, 2], ∅⟩) (by decide) (by decide) (by decide))

/-- `emptySeed` is satisfiable, so this run is one on which no refutation may fire --
`saturated_not_refuted_of_sat` applies to it. -/
theorem emptySeed_sat : ∃ rho, SModels rho emptySeed := by
  refine ⟨fun _ => ∅, ?_⟩
  intro c hc
  simp only [emptySeed, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl
  · rw [sat_zero]
  · rw [sat_two]
    exact ⟨by simp, by simp, by simp, by simp⟩

/-! ## 10. The rule that is deliberately absent

`commonSubexpression`'s MINTING branch is OFF under the shipped default
(`-Dermine.genRules=cut` deletes exactly it), so it is not a constructor of `SatStep`.
It is not a hole in the argument, only a hole in the coverage: were it switched back on,
`Divergence.CseStep.satisfiable_iff` supplies the same implication for it, and the
assembly of section 6 would go through unchanged. -/

/-- **Were the CSE mint re-enabled, it too would preserve satisfiability.**  Recorded so
the omission from `SatStep` is a coverage decision and not an unproved step.  Note this is
`Divergence.CseStep`, the CSE mint; `SatStep.cutRule` reaches `CutRuleStep.mint`, which is
`Cut.SplitStep` -- `splitConcrete`'s mint, a different rule. -/
theorem cseMint_sat_mono {G G' : System} (h : CseStep G G')
    (hsat : ∃ rho, SModels rho G) : ∃ rho, SModels rho G' :=
  h.satisfiable_iff.mp hsat

/-! ## 11. Summary

### What is established

* `SatStep` models, in one relation: the whole cut calculus (`cutRule`, via
  `SplitNecessary.CutRuleStep` -- CSE reuse and fold, `splitConcrete` reuse and mint,
  cancellation, substitution, self-substitution, common partition, resolution); the two
  halves of `makeEmpty` (`empty`, `eraseEmpty`); `makeConcrete`/`destructiveSub`
  (`concrete`); `replace`'s rename and its de-duplication emission (`rename`, `dedup`);
  and DELETION (`weaken`).  The solver's rename-and-discard is the composite
  `rename` then `weaken`.  `emptySeed_step` / `emptySeed_run` check the new steps are not
  vacuous.
* `SatStep.sat_mono` and `SatSteps.sat_mono`: **a satisfiable input stays satisfiable
  through any run of the solver.**
* `refute_saturated_sound`: if per-label propagation is `Refuted` on any system reachable
  from `G₀`, then `G₀` has no model.  This is the licence for item 8a -- `labelClash` may
  be run on `q.expand` rather than on `q`.
* `saturated_not_refuted_of_sat`: contrapositive -- a satisfiable input is never refuted
  at the saturated set.  No false rejections.
* Two refutations the saturation itself performs, proved sound independently of the
  label check: `empty_conc_unsat` (`makeEmpty`'s `"Incompatible instantiations"`) and
  `concrete_superset_unsat` (`makeConcrete`'s `ensureSuperset`).
* `satStep_not_reflecting` / `satSteps_not_reflecting`: the implication is STRICT.  A
  refutation-only check may move to the saturated set; an ACCEPTANCE check may not.

### What is NOT established

* **`Constraints.disjunction` has no Lean theorem of any kind**, here or anywhere in this
  development.  It is disabled by default (`-Dermine.disjunction=false`,
  `GenRules.disjRule`); with it enabled, NOTHING in this file applies -- `SatStep` has no
  constructor for it, and `SatSteps.sat_mono` therefore says nothing about a run that
  uses it.
* **`commonSubexpression`'s MINT branch is not a constructor of `SatStep`.**  It is off
  under the shipped default `genRules=cut`; `cseMint_sat_mono` shows the missing case
  would go through (`Divergence.CseStep.satisfiable_iff`), but the assembled theorems as
  stated do not cover a run that uses it.  Note `CutRuleStep.mint` is `Cut.SplitStep`,
  i.e. `splitConcrete`'s mint, NOT the CSE mint.
* **`Q.PQueue.build` is not modelled anywhere.**  It constructs the input partition set
  from the source constraints, and for a `Part` whose left-hand side is not a variable it
  MINTS a variable and emits two partitions for it (`Constraints.scala` (was line 659)).  So even
  the "input" system `G₀` of every theorem here is already a conservative extension of
  what the user wrote; the passage from source text to `G₀` is unverified.
* **THE WEAKEST LINK.**  Nothing anywhere relates the Scala `Constraints.checkLabel` -- an
  imperative fixpoint over a `Map[TypeVar, Boolean]`, with a `while (changed)` loop and
  first-clash-wins reporting -- to the Lean inductive `LabelProp.Forced`.  Every result
  in this file, and every soundness claim made for the label check, ASSUMES the two
  coincide: that `checkLabel` returns `Some(msg)` only when `Forced` derives both values
  for one variable.  That assumption is unproved and is the largest gap in the chain.
* Nothing here is an upper bound or a termination claim.  `Divergence` and
  `ResGuardDiverge` say the saturation may not terminate at all; item 8a is about which
  system the check reads, not about whether the solver reaches it.
* `weaken` over-approximates deletion: it permits deleting ANY subset, whereas the solver
  deletes only specific partitions.  That is the safe direction for this theorem (a
  larger step relation proves a stronger `sat_mono`), but it means `SatSteps` is NOT a
  faithful model of the solver's control flow and must not be read as one -- in
  particular no lower-bound or completeness statement about the solver follows from it. -/

end Rowpartition
