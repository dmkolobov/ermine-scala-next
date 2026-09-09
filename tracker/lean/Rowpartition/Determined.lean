/-
# Rose's Definition 13, the determinacy closure: what it licenses in Ermine, and what it does not

Stage R3 of `tracker/LOOP-MODEL-PLAN.md`.  An INVESTIGATION: nothing here changes the solver.

> **Definition 13.**  We define `T⁺_Ψ` as the smallest set `U` such that
> * `T ⊆ U`; and,
> * if `ζ₁ ⊙ ζ₂ ∼ ζ₃ ∈ Ψ`, and `fv(ζ₁, ζ₂) ⊆ U`, then `fv(ζ₃) ⊆ U`.
>
> **Definition 14.**  A type scheme `∀T.Ψ ⇒ τ` is *coherent* if `T ⊆ fv(τ)⁺_Ψ`.  A term `M`
> is coherent if its principal type scheme is coherent.
>
> -- Morris & McKinna, *Abstracting Extensible Data Types*, POPL 2019 (Rose), §5.

**WHAT R2 LEAVES FOR THIS FILE** (`R2-ROSE-THEORY.md` §5, `R2-REVIEW.md` K-10).  Definition 13
mentions neither `⇒` nor models: it is a closure on the PREDICATES of `Ψ`.  Two facts are
inherited and load-bearing -- `Rose.sat_iff_pfold`, which says one Ermine constraint IS one
combination predicate of `⟨𝒫fin(L), ⊎, ∅⟩` and so licenses restating Definition 13's clause
N-ARILY (`fv(all parts) ⊆ U ⟹ fv(lhs) ⊆ U`), and `Rose.labelAlgebra` being a genuine
PARTIAL MONOID, which is what makes "determined" mean anything: in a partial monoid the
combination is a FUNCTION of the parts wherever it is defined.  Nothing from the entailment
half is needed or used.  Theorem 15 is unavailable as a GUARANTEE -- Definition 14 defines
coherence of a TERM through its PRINCIPAL type scheme and Ermine has no principality theorem
(`ROSE-COMPARISON.md` §1.5) -- so Definition 13 is imported as a CRITERION.

**WHAT IS BUILT.**

* §1-3  the closure.  `roseAdd` is Definition 13's clause n-arily; `cancelAdd` is Ermine's
  STRICTLY LARGER clause, which the memo names: cancellation determines a PART from the whole
  and the other parts, because the concrete part is always known.  `Determined G U` is the
  least fixed point of both, `RoseDetermined G U` of the first alone, and both are proved to
  be closure operators -- EXTENSIVE (`subset_determined`), MONOTONE (`determined_mono`), CLOSED
  (`determined_closed`), LEAST (`determined_least`) and IDEMPOTENT (`determined_idem`).
  `determined_union_disjoint` is what licenses the R3 INSTRUMENT to read its seed off the
  partitions rather than off `fv(τ)`: widening the seed by variables the system does not
  mention widens the closure by exactly those variables and by nothing else.
* §4    **the theorem that gives them meaning**: `determined_unique`.  Two models of `G` that
  agree on `U` agree on everything `U` determines.  Rose's clause needs the whole to be a
  function of the parts; cancellation needs a part to be a function of the whole and the rest,
  and that is `Sat.eq_sdiff`, disjointness and completeness together.
* §5-6  non-vacuity.  Each clause fires on its own instance; the closures are separated
  (`RuleFires.rose_lt_det`); and `PivotTest.pivotData`'s residual is worked in both readings.
* §7    **R3.2(a): the candidate splice guard is REFUTED, in both directions.**  Determinedness
  does not make `Subst.reduce`'s splice conservative (`determined_splice_not_conservative`, on
  `Splice.DroppedPartition`, where the lost consequence is stated in the universal vocabulary
  alone), and the splice can be conservative when the variable is determined by neither closure
  (`undetermined_splice_is_conservative`).  The binding condition remains `splice_entails_iff`'s
  `hlhs`, which is SYNTACTIC and therefore invisible to a closure on models.
* §8    **R3.2(b): the deletion licence is REFUTED**, twice: a dead existential whose value IS
  determined by its parts is not deletable (`DeadTwoParts.two_parts_not_deletable`, the
  partiality of the monoid), and an existential neither determined by nor determining the
  universals is not deletable either (`DeadUndetermined.undetermined_not_deletable`).  What IS
  licensed is `dead_delete_of_pairwise`: deletion is sound exactly when the remainder already
  forces the parts to COMBINE, and unconditionally when there is at most one part.
* §9-11 **R3.2(c): the row-ambiguity criterion**, `RowAmbiguous`, with the theorem that gives
  it content (`witness_unique_of_not_rowAmbiguous`: a unique witness), the `∀T`-versus-`exists`
  reading, an incompleteness witness, and the two derived predicates of `modules/Constraint.e`
  -- `Has` is determined by CANCELLATION only, which is the measured reason Ermine's closure is
  larger than Rose's.
* §13   the clause the MEASUREMENT then says is still missing: RESOLUTION (`resAdd`,
  `Determined3`), which eliminates a SUB-partition as a block.  Seven of the ten signatures
  hand-checked in `R3-DETERMINED.md` §4 are flagged by the two-clause closure and determined
  after all, always by this step; `NotEq.res_cures` is the smallest of them, the stdlib `(!=)`.
  `determined3_unique` re-proves the uniqueness theorem for the enlarged closure, so a stage 2
  needs the number and not the theorem.
-/
import Rowpartition.Basic
import Rowpartition.Rules
import Rowpartition.Divergence
import Rowpartition.Canonical
import Rowpartition.Splice
import Rowpartition.RoseTheory

namespace Rowpartition

/-! ## 1. Iterating a monotone, extensive map on a finite carrier -/

section Fix
variable {α : Type*}

theorem subset_iterate {f : Finset α → Finset α} (hext : ∀ D, D ⊆ f D) :
    ∀ (n : ℕ) (D : Finset α), D ⊆ f^[n] D := by
  intro n
  induction n with
  | zero => intro D; simp
  | succ n ih =>
    intro D
    rw [Function.iterate_succ_apply']
    exact (ih D).trans (hext _)

theorem iterate_stable {f : Finset α → Finset α} {D : Finset α} {i : ℕ}
    (h : f (f^[i] D) = f^[i] D) : ∀ j, i ≤ j → f^[j] D = f^[i] D := by
  intro j hij
  induction j, hij using Nat.le_induction with
  | base => rfl
  | succ j hij ih => rw [Function.iterate_succ_apply', ih, h]

theorem card_iterate_ge {f : Finset α → Finset α} (hext : ∀ D, D ⊆ f D) (D : Finset α) :
    ∀ n, (∀ k, k < n → f (f^[k] D) ≠ f^[k] D) → D.card + n ≤ (f^[n] D).card := by
  intro n
  induction n with
  | zero => intro _; simp
  | succ n ih =>
    intro h
    have hn := ih (fun k hk => h k (by omega))
    have hsub : f^[n] D ⊆ f^[n+1] D := by
      rw [Function.iterate_succ_apply']; exact hext _
    have hne : f^[n] D ≠ f^[n+1] D := by
      rw [Function.iterate_succ_apply']
      exact fun hh => h n (by omega) hh.symm
    have hlt : (f^[n] D).card < (f^[n+1] D).card :=
      Finset.card_lt_card (Finset.ssubset_iff_subset_ne.mpr ⟨hsub, hne⟩)
    omega

theorem iterate_subset {f : Finset α → Finset α} {W : Finset α}
    (hW : ∀ E, E ⊆ W → f E ⊆ W) : ∀ (n : ℕ) {D : Finset α}, D ⊆ W → f^[n] D ⊆ W := by
  intro n
  induction n with
  | zero => intro D h; simpa using h
  | succ n ih =>
    intro D h
    rw [Function.iterate_succ_apply']
    exact hW _ (ih h)

theorem iterate_fixed {f : Finset α → Finset α} (hext : ∀ D, D ⊆ f D) {W D : Finset α}
    (hDW : D ⊆ W) (hW : ∀ E, E ⊆ W → f E ⊆ W) {n : ℕ} (hn : W.card ≤ D.card + n) :
    f (f^[n] D) = f^[n] D := by
  classical
  by_cases hex : ∃ k, k ≤ n ∧ f (f^[k] D) = f^[k] D
  · obtain ⟨k, hk, hfk⟩ := hex
    rw [iterate_stable hfk n hk, hfk]
  · simp only [not_exists, not_and] at hex
    have hall : ∀ k, k < n + 1 → f (f^[k] D) ≠ f^[k] D := fun k hk => hex k (by omega)
    have h1 := card_iterate_ge hext D (n+1) hall
    have h2 : f^[n+1] D ⊆ W := iterate_subset hW _ hDW
    have h3 := Finset.card_le_card h2
    omega

theorem iterate_mono {f g : Finset α → Finset α}
    (hfg : ∀ D, f D ⊆ g D) (hg : ∀ D E, D ⊆ E → g D ⊆ g E) :
    ∀ (n : ℕ) (D : Finset α), f^[n] D ⊆ g^[n] D := by
  intro n
  induction n with
  | zero => intro D; simp
  | succ n ih =>
    intro D
    rw [Function.iterate_succ_apply', Function.iterate_succ_apply']
    exact (hfg _).trans (hg _ _ (ih D))

theorem iterate_mono_arg {f : Finset α → Finset α} (hf : ∀ D E, D ⊆ E → f D ⊆ f E) :
    ∀ (n : ℕ) {D E : Finset α}, D ⊆ E → f^[n] D ⊆ f^[n] E := by
  intro n
  induction n with
  | zero => intro D E h; simpa using h
  | succ n ih =>
    intro D E h
    rw [Function.iterate_succ_apply', Function.iterate_succ_apply']
    exact hf _ _ (ih h)

end Fix

/-! ## 2. The two clauses and the closure -/

/-- **The licence R2 leaves for the n-ary restatement.**  One Ermine constraint IS one
combination predicate of the partial monoid `⟨𝒫fin(L), ⊎, ∅⟩` (`Rose.sat_iff_pfold`):
the left-hand row is the value of the PARTIAL FOLD of the parts, hence a FUNCTION of them
wherever the fold is defined.  That, and nothing about entailment, is what Definition 13's
clause needs. -/
theorem lhs_eq_pfold {rho : Assign} {c : Constraint} (h : Sat rho c) :
    Rose.labelAlgebra.pfold (parts rho c) = some (rho c.lhs) := (Rose.sat_iff_pfold rho c).mp h

/-- **Rose's Definition 13, n-ary: the whole is determined by the parts.** -/
def roseAdd (G : System) (D : Finset Var) : Finset Var :=
  (G.filter (fun c => vset c ⊆ D)).image Constraint.lhs

/-- **Ermine's extra clause: CANCELLATION.** -/
def cancelAdd (G : System) (D : Finset Var) : Finset Var :=
  G.biUnion (fun c => if c.lhs ∈ D then (vset c).filter (fun v => (vset c).erase v ⊆ D) else ∅)

def roseStep (G : System) (D : Finset Var) : Finset Var := D ∪ roseAdd G D

def detStep (G : System) (D : Finset Var) : Finset Var := D ∪ roseAdd G D ∪ cancelAdd G D

theorem mem_roseAdd {G : System} {D : Finset Var} {a : Var} :
    a ∈ roseAdd G D ↔ ∃ c ∈ G, vset c ⊆ D ∧ c.lhs = a := by
  simp only [roseAdd, Finset.mem_image, Finset.mem_filter]
  constructor
  · rintro ⟨c, ⟨hc, hs⟩, rfl⟩; exact ⟨c, hc, hs, rfl⟩
  · rintro ⟨c, hc, hs, rfl⟩; exact ⟨c, ⟨hc, hs⟩, rfl⟩

theorem mem_cancelAdd {G : System} {D : Finset Var} {v : Var} :
    v ∈ cancelAdd G D ↔ ∃ c ∈ G, c.lhs ∈ D ∧ v ∈ vset c ∧ (vset c).erase v ⊆ D := by
  simp only [cancelAdd, Finset.mem_biUnion]
  constructor
  · rintro ⟨c, hc, hv⟩
    by_cases h : c.lhs ∈ D
    · rw [if_pos h, Finset.mem_filter] at hv; exact ⟨c, hc, h, hv.1, hv.2⟩
    · rw [if_neg h] at hv; exact absurd hv (Finset.notMem_empty v)
  · rintro ⟨c, hc, hl, hv, hs⟩
    exact ⟨c, hc, by rw [if_pos hl, Finset.mem_filter]; exact ⟨hv, hs⟩⟩

/-! ## 3. The closure -/

/-- `D` is closed under Rose's clause. -/
def RoseClosed (G : System) (D : Finset Var) : Prop := ∀ c ∈ G, vset c ⊆ D → c.lhs ∈ D

/-- `D` is closed under cancellation. -/
def CancelClosed (G : System) (D : Finset Var) : Prop :=
  ∀ c ∈ G, c.lhs ∈ D → ∀ v ∈ vset c, (vset c).erase v ⊆ D → v ∈ D

/-- `D` is closed under both clauses. -/
def DetClosed (G : System) (D : Finset Var) : Prop := RoseClosed G D ∧ CancelClosed G D

/-- **Rose's closure**: iterate Rose's clause alone. -/
def RoseDetermined (G : System) (U : Finset Var) : Finset Var :=
  (roseStep G)^[(allVars G).card] U

/-- **Ermine's closure**: iterate both clauses. -/
def Determined (G : System) (U : Finset Var) : Finset Var :=
  (detStep G)^[(allVars G).card] U

/-! ### The step maps -/

theorem subset_roseStep (G : System) (D : Finset Var) : D ⊆ roseStep G D :=
  Finset.subset_union_left

theorem subset_detStep (G : System) (D : Finset Var) : D ⊆ detStep G D :=
  Finset.Subset.trans Finset.subset_union_left Finset.subset_union_left

theorem roseAdd_subset_allVars (G : System) (D : Finset Var) : roseAdd G D ⊆ allVars G := by
  intro a ha
  obtain ⟨c, hc, _, rfl⟩ := mem_roseAdd.mp ha
  exact lhs_mem_allVars hc

theorem cancelAdd_subset_allVars (G : System) (D : Finset Var) : cancelAdd G D ⊆ allVars G := by
  intro v hv
  obtain ⟨c, hc, _, hvc, _⟩ := mem_cancelAdd.mp hv
  exact mem_allVars hc (Or.inr hvc)

theorem roseStep_subset (G : System) {W D : Finset Var} (hA : allVars G ⊆ W) (h : D ⊆ W) :
    roseStep G D ⊆ W :=
  Finset.union_subset h ((roseAdd_subset_allVars G D).trans hA)

theorem detStep_subset (G : System) {W D : Finset Var} (hA : allVars G ⊆ W) (h : D ⊆ W) :
    detStep G D ⊆ W :=
  Finset.union_subset (Finset.union_subset h ((roseAdd_subset_allVars G D).trans hA))
    ((cancelAdd_subset_allVars G D).trans hA)

theorem roseAdd_mono (G : System) {D E : Finset Var} (h : D ⊆ E) : roseAdd G D ⊆ roseAdd G E := by
  intro a ha
  obtain ⟨c, hc, hs, rfl⟩ := mem_roseAdd.mp ha
  exact mem_roseAdd.mpr ⟨c, hc, hs.trans h, rfl⟩

theorem cancelAdd_mono (G : System) {D E : Finset Var} (h : D ⊆ E) :
    cancelAdd G D ⊆ cancelAdd G E := by
  intro v hv
  obtain ⟨c, hc, hl, hvc, hs⟩ := mem_cancelAdd.mp hv
  exact mem_cancelAdd.mpr ⟨c, hc, h hl, hvc, hs.trans h⟩

theorem roseStep_mono (G : System) {D E : Finset Var} (h : D ⊆ E) : roseStep G D ⊆ roseStep G E :=
  Finset.union_subset_union h (roseAdd_mono G h)

theorem detStep_mono (G : System) {D E : Finset Var} (h : D ⊆ E) : detStep G D ⊆ detStep G E :=
  Finset.union_subset_union (Finset.union_subset_union h (roseAdd_mono G h)) (cancelAdd_mono G h)

theorem roseStep_subset_detStep (G : System) (D : Finset Var) : roseStep G D ⊆ detStep G D :=
  Finset.subset_union_left

/-- `D` is a fixed point of `detStep` exactly when it is closed under both clauses. -/
theorem detStep_eq_iff_closed (G : System) (D : Finset Var) :
    detStep G D = D ↔ DetClosed G D := by
  constructor
  · intro h
    refine ⟨fun c hc hs => ?_, fun c hc hl v hv hs => ?_⟩
    · exact h ▸ Finset.mem_union_left _
        (Finset.mem_union_right _ (mem_roseAdd.mpr ⟨c, hc, hs, rfl⟩))
    · exact h ▸ Finset.mem_union_right _ (mem_cancelAdd.mpr ⟨c, hc, hl, hv, hs⟩)
  · rintro ⟨hr, hcn⟩
    refine Finset.Subset.antisymm ?_ (subset_detStep G D)
    intro a ha
    rcases Finset.mem_union.mp ha with h1 | h2
    · rcases Finset.mem_union.mp h1 with h | h
      · exact h
      · obtain ⟨c, hc, hs, rfl⟩ := mem_roseAdd.mp h; exact hr c hc hs
    · obtain ⟨c, hc, hl, hv, hs⟩ := mem_cancelAdd.mp h2; exact hcn c hc hl _ hv hs

theorem roseStep_eq_iff_closed (G : System) (D : Finset Var) :
    roseStep G D = D ↔ RoseClosed G D := by
  constructor
  · intro h c hc hs
    exact h ▸ Finset.mem_union_right _ (mem_roseAdd.mpr ⟨c, hc, hs, rfl⟩)
  · intro hr
    refine Finset.Subset.antisymm ?_ (subset_roseStep G D)
    intro a ha
    rcases Finset.mem_union.mp ha with h | h
    · exact h
    · obtain ⟨c, hc, hs, rfl⟩ := mem_roseAdd.mp h; exact hr c hc hs

/-! ### `Determined` is a closure operator -/

/-- EXTENSIVE. -/
theorem subset_determined (G : System) (U : Finset Var) : U ⊆ Determined G U :=
  subset_iterate (subset_detStep G) _ U

theorem subset_roseDetermined (G : System) (U : Finset Var) : U ⊆ RoseDetermined G U :=
  subset_iterate (subset_roseStep G) _ U

/-- MONOTONE. -/
theorem determined_mono (G : System) {U V : Finset Var} (h : U ⊆ V) :
    Determined G U ⊆ Determined G V :=
  iterate_mono_arg (fun _ _ => detStep_mono G) _ h

theorem roseDetermined_mono (G : System) {U V : Finset Var} (h : U ⊆ V) :
    RoseDetermined G U ⊆ RoseDetermined G V :=
  iterate_mono_arg (fun _ _ => roseStep_mono G) _ h

/-- **Ermine's closure contains Rose's.** -/
theorem roseDetermined_subset (G : System) (U : Finset Var) :
    RoseDetermined G U ⊆ Determined G U :=
  iterate_mono (roseStep_subset_detStep G) (fun _ _ => detStep_mono G) _ U

/-- CLOSED: the iteration really has reached a fixed point. -/
theorem determined_closed (G : System) (U : Finset Var) : DetClosed G (Determined G U) := by
  refine (detStep_eq_iff_closed G _).mp ?_
  exact iterate_fixed (subset_detStep G) (W := U ∪ allVars G) Finset.subset_union_left
    (fun E hE => detStep_subset G Finset.subset_union_right hE)
    (le_trans (Finset.card_union_le _ _) (by omega))

theorem roseDetermined_closed (G : System) (U : Finset Var) :
    RoseClosed G (RoseDetermined G U) := by
  refine (roseStep_eq_iff_closed G _).mp ?_
  exact iterate_fixed (subset_roseStep G) (W := U ∪ allVars G) Finset.subset_union_left
    (fun E hE => roseStep_subset G Finset.subset_union_right hE)
    (le_trans (Finset.card_union_le _ _) (by omega))

/-- LEAST: any closed superset of `U` contains the closure. -/
theorem determined_least {G : System} {U D : Finset Var} (hU : U ⊆ D) (hD : DetClosed G D) :
    Determined G U ⊆ D := by
  have hstep : detStep G D ⊆ D := le_of_eq ((detStep_eq_iff_closed G D).mpr hD)
  have : ∀ n, (detStep G)^[n] U ⊆ D := by
    intro n
    induction n with
    | zero => simpa using hU
    | succ n ih =>
      rw [Function.iterate_succ_apply']
      exact (detStep_mono G ih).trans hstep
  exact this _

theorem roseDetermined_least {G : System} {U D : Finset Var} (hU : U ⊆ D)
    (hD : RoseClosed G D) : RoseDetermined G U ⊆ D := by
  have hstep : roseStep G D ⊆ D := le_of_eq ((roseStep_eq_iff_closed G D).mpr hD)
  have : ∀ n, (roseStep G)^[n] U ⊆ D := by
    intro n
    induction n with
    | zero => simpa using hU
    | succ n ih =>
      rw [Function.iterate_succ_apply']
      exact (roseStep_mono G ih).trans hstep
  exact this _

/-- IDEMPOTENT. -/
theorem determined_idem (G : System) (U : Finset Var) :
    Determined G (Determined G U) = Determined G U :=
  Finset.Subset.antisymm
    (determined_least (Finset.Subset.refl _) (determined_closed G U))
    (subset_determined G _)

theorem roseDetermined_idem (G : System) (U : Finset Var) :
    RoseDetermined G (RoseDetermined G U) = RoseDetermined G U :=
  Finset.Subset.antisymm
    (roseDetermined_least (Finset.Subset.refl _) (roseDetermined_closed G U))
    (subset_roseDetermined G _)

/-! ### The seed outside the system does not matter

This is what licenses the INSTRUMENT to read `U₀` off the partitions rather than off `fv(τ)`:
both clauses quantify over constraints, so a seed variable the system does not mention can
never enable either of them. -/

theorem roseAdd_union_disjoint (G : System) (D X : Finset Var) (hX : ∀ v ∈ X, v ∉ allVars G) :
    roseAdd G (D ∪ X) = roseAdd G D := by
  ext a
  simp only [mem_roseAdd]
  constructor
  · rintro ⟨c, hc, hs, rfl⟩
    refine ⟨c, hc, ?_, rfl⟩
    intro w hw
    rcases Finset.mem_union.mp (hs hw) with h | h
    · exact h
    · exact absurd (mem_allVars hc (Or.inr hw)) (hX w h)
  · rintro ⟨c, hc, hs, rfl⟩
    exact ⟨c, hc, hs.trans Finset.subset_union_left, rfl⟩

theorem cancelAdd_union_disjoint (G : System) (D X : Finset Var) (hX : ∀ v ∈ X, v ∉ allVars G) :
    cancelAdd G (D ∪ X) = cancelAdd G D := by
  ext v
  simp only [mem_cancelAdd]
  constructor
  · rintro ⟨c, hc, hl, hv, hs⟩
    refine ⟨c, hc, ?_, hv, ?_⟩
    · rcases Finset.mem_union.mp hl with h | h
      · exact h
      · exact absurd (lhs_mem_allVars hc) (hX _ h)
    · intro w hw
      rcases Finset.mem_union.mp (hs hw) with h | h
      · exact h
      · exact absurd (mem_allVars hc (Or.inr (Finset.mem_of_mem_erase hw))) (hX w h)
  · rintro ⟨c, hc, hl, hv, hs⟩
    exact ⟨c, hc, Finset.mem_union_left _ hl, hv, hs.trans Finset.subset_union_left⟩

theorem detStep_union_disjoint (G : System) (D X : Finset Var) (hX : ∀ v ∈ X, v ∉ allVars G) :
    detStep G (D ∪ X) = detStep G D ∪ X := by
  simp only [detStep, roseAdd_union_disjoint G D X hX, cancelAdd_union_disjoint G D X hX]
  ac_rfl

/-- **Widening the seed by variables the system does not mention widens the closure by exactly
those variables.**  So the instrument's `U₀` -- the non-existential variables the ROW
constraints mention -- decides the criterion exactly as `fv(τ) ∪ universals` would. -/
theorem determined_union_disjoint (G : System) (U X : Finset Var)
    (hX : ∀ v ∈ X, v ∉ allVars G) : Determined G (U ∪ X) = Determined G U ∪ X := by
  have key : ∀ n (D : Finset Var), (detStep G)^[n] (D ∪ X) = (detStep G)^[n] D ∪ X := by
    intro n
    induction n with
    | zero => intro D; simp
    | succ n ih =>
      intro D
      rw [Function.iterate_succ_apply', Function.iterate_succ_apply', ih D,
        detStep_union_disjoint G _ X hX]
  exact key _ U

/-- The corollary the `ramb` record rests on: for a variable the system mentions, the verdict
does not move when the seed is widened outside the system. -/
theorem mem_determined_union_disjoint {G : System} {U X : Finset Var} {v : Var}
    (hX : ∀ w ∈ X, w ∉ allVars G) (hv : v ∈ allVars G) :
    v ∈ Determined G (U ∪ X) ↔ v ∈ Determined G U := by
  rw [determined_union_disjoint G U X hX, Finset.mem_union]
  exact ⟨fun h => h.elim id (fun hh => absurd hv (hX v hh)), Or.inl⟩

/-! ## 4. Why "determined" means something: the uniqueness theorem -/

/-- **Cancellation, semantically.**  In a partition, each variable part is the whole minus
the concrete part and the other variable parts. -/
theorem Sat.eq_sdiff {rho : Assign} {c : Constraint} (h : Sat rho c) {v : Var}
    (hv : v ∈ vset c) :
    rho v = rho c.lhs \ (c.conc ∪ ((vset c).erase v).biUnion rho) := by
  ext l
  simp only [Finset.mem_sdiff, Finset.mem_union, Finset.mem_biUnion, Finset.mem_erase]
  constructor
  · intro hl
    refine ⟨?_, ?_⟩
    · rw [h.eq_biUnion]
      exact Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨v, hv, hl⟩)
    · rintro (hc | ⟨w, ⟨hwv, hw⟩, hlw⟩)
      · exact Finset.disjoint_left.mp (h.disjoint_conc' hv) hc hl
      · exact Finset.disjoint_left.mp (h.disjoint_of_ne' hv hw (Ne.symm hwv)) hl hlw
  · rintro ⟨hl, hn⟩
    rw [h.eq_biUnion] at hl
    rcases Finset.mem_union.mp hl with hc | hb
    · exact absurd (Or.inl hc) hn
    · obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp hb
      by_cases hwv : w = v
      · exact hwv ▸ hlw
      · exact absurd (Or.inr ⟨w, ⟨hwv, hw⟩, hlw⟩) hn

/-- Two assignments agree on the finite set `U`. -/
def AgreeOn (rho rho' : Assign) (U : Finset Var) : Prop := ∀ v ∈ U, rho v = rho' v

theorem AgreeOn.mono {rho rho' : Assign} {U V : Finset Var} (h : AgreeOn rho rho' V)
    (hUV : U ⊆ V) : AgreeOn rho rho' U := fun v hv => h v (hUV hv)

theorem agree_biUnion {rho rho' : Assign} {D S : Finset Var} (h : AgreeOn rho rho' D)
    (hS : S ⊆ D) : S.biUnion rho = S.biUnion rho' :=
  Finset.biUnion_congr rfl (fun v hv => h v (hS hv))

/-- Rose's clause preserves agreement: the whole is a FUNCTION of the parts (this is where
the partial monoid of `Rose.labelAlgebra` is doing the work). -/
theorem agree_roseAdd {G : System} {rho rho' : Assign} {D : Finset Var}
    (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (roseAdd G D) := by
  intro a ha
  obtain ⟨c, hc, hs, rfl⟩ := mem_roseAdd.mp ha
  rw [(hm c hc).eq_biUnion, (hm' c hc).eq_biUnion, agree_biUnion hD hs]

/-- Cancellation preserves agreement: a part is a FUNCTION of the whole and the other parts. -/
theorem agree_cancelAdd {G : System} {rho rho' : Assign} {D : Finset Var}
    (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (cancelAdd G D) := by
  intro v hv
  obtain ⟨c, hc, hl, hvc, hs⟩ := mem_cancelAdd.mp hv
  rw [(hm c hc).eq_sdiff hvc, (hm' c hc).eq_sdiff hvc, hD _ hl, agree_biUnion hD hs]

theorem agree_roseStep {G : System} {rho rho' : Assign} {D : Finset Var}
    (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (roseStep G D) := by
  intro a ha
  rcases Finset.mem_union.mp ha with h | h
  · exact hD a h
  · exact agree_roseAdd hm hm' hD a h

theorem agree_detStep {G : System} {rho rho' : Assign} {D : Finset Var}
    (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (detStep G D) := by
  intro a ha
  rcases Finset.mem_union.mp ha with h1 | h2
  · exact agree_roseStep hm hm' hD a h1
  · exact agree_cancelAdd hm hm' hD a h2

theorem agree_iterate {rho rho' : Assign} {f : Finset Var → Finset Var}
    (hstep : ∀ D, AgreeOn rho rho' D → AgreeOn rho rho' (f D)) :
    ∀ (n : ℕ) (D : Finset Var), AgreeOn rho rho' D → AgreeOn rho rho' (f^[n] D) := by
  intro n
  induction n with
  | zero => intro D h; simpa using h
  | succ n ih =>
    intro D h
    rw [Function.iterate_succ_apply']
    exact hstep _ (ih D h)

/-- **THE THEOREM THAT GIVES THE CLOSURE ITS MEANING.**  Two models of `G` that agree on `U`
agree on every variable `U` determines. -/
theorem determined_unique {G : System} {U : Finset Var} {rho rho' : Assign}
    (hm : SModels rho G) (hm' : SModels rho' G) (hU : AgreeOn rho rho' U) :
    AgreeOn rho rho' (Determined G U) :=
  agree_iterate (fun _ h => agree_detStep hm hm' h) _ U hU

/-- The same for Rose's closure alone. -/
theorem roseDetermined_unique {G : System} {U : Finset Var} {rho rho' : Assign}
    (hm : SModels rho G) (hm' : SModels rho' G) (hU : AgreeOn rho rho' U) :
    AgreeOn rho rho' (RoseDetermined G U) :=
  agree_iterate (fun _ h => agree_roseStep hm hm' h) _ U hU

/-! ## 5. Non-vacuity: each rule fires, and the closures differ -/

namespace RuleFires

/-- `a <- (x, y)`, with `a = 0`, `x = 1`, `y = 2`. -/
def G : System := {⟨0, [1, 2], ∅⟩}

/-- ROSE's clause fires: the parts determine the whole. -/
theorem rose_fires : (0 : Var) ∈ RoseDetermined G {1, 2} := by decide

/-- CANCELLATION fires: the whole and one part determine the other. -/
theorem cancel_fires : (2 : Var) ∈ Determined G {0, 1} := by decide

/-- ...and Rose's clause alone does NOT get there.  This is the separation: Ermine's closure
is STRICTLY larger. -/
theorem cancel_not_rose : (2 : Var) ∉ RoseDetermined G {0, 1} := by decide

theorem rose_lt_det : RoseDetermined G {0, 1} ⊂ Determined G {0, 1} := by decide

end RuleFires

/-! ## 6. `PivotTest.pivotData`: the corpus's one known incoherent residual -/

namespace Pivot

/-- The residual `(|Issue, Key, Value|) <- ((|Key|), i, v3)` on its own, with its carrier. -/
def bare : System := {⟨3, [], {0, 1, 2}⟩, ⟨3, [1, 2], {1}⟩}

/-- The residual as the compiler actually publishes it, which also carries the link
`s <- ((|Sector, Price, MarketCap|), i)`. -/
def full : System := {⟨3, [], {0, 1, 2}⟩, ⟨3, [1, 2], {1}⟩, ⟨0, [1], {3, 4, 5}⟩}

/-- `U₀`: the published type is `forall s. (...) => Mem s`, so `fv(tau) = {s}`. -/
def U : Finset Var := {0}

/-! ### On the bare constraint, NOTHING determines `i` or `v3` -/

theorem bare_rose : RoseDetermined bare U = {0, 3} := by decide
theorem bare_det : Determined bare U = {0, 3} := by decide
theorem bare_i_undet : (1 : Var) ∉ Determined bare U := by decide
theorem bare_v3_undet : (2 : Var) ∉ Determined bare U := by decide

/-- Two models of the bare residual agreeing on `U₀` and differing at `i` -- two of the
four solutions of `i ⊎ v3 = {Issue, Value}`. -/
def rho1 : Assign :=
  fun w => if w = 3 then {0,1,2} else if w = 1 then {0} else if w = 2 then {2} else ∅
def rho2 : Assign :=
  fun w => if w = 3 then {0,1,2} else if w = 1 then {2} else if w = 2 then {0} else ∅

theorem rho1_models : SModels rho1 bare := by
  intro c hc
  simp only [bare, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl <;> exact ⟨by decide, by decide⟩

theorem rho2_models : SModels rho2 bare := by
  intro c hc
  simp only [bare, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl <;> exact ⟨by decide, by decide⟩

theorem rho_agree : AgreeOn rho1 rho2 U := by
  intro v hv
  simp only [U, Finset.mem_singleton] at hv
  subst hv; decide

/-- **The undeterminedness is REAL, not an artefact of the closure**: two models, agreeing
on the whole universal vocabulary, that disagree at `i`. -/
theorem bare_genuinely_ambiguous :
    SModels rho1 bare ∧ SModels rho2 bare ∧ AgreeOn rho1 rho2 U ∧ rho1 1 ≠ rho2 1 :=
  ⟨rho1_models, rho2_models, rho_agree, by decide⟩

/-! ### On the residual the compiler really publishes, ERMINE's closure determines both -/

theorem full_rose : RoseDetermined full U = {0, 3} := by decide
theorem full_det : Determined full U = {0, 1, 2, 3} := by decide

/-- **The verdict DEPENDS on which closure you use.**  Rose's clause alone leaves `i` and
`v3` undetermined -- which is the reading `R2-REVIEW.md` K-9 records.  Ermine's
cancellation clause determines both: `i = s \ {Sector, Price, MarketCap}` and then
`v3 = {Issue, Key, Value} \ ({Key} ∪ i)`. -/
theorem full_separation :
    (1 : Var) ∉ RoseDetermined full U ∧ (2 : Var) ∉ RoseDetermined full U ∧
      (1 : Var) ∈ Determined full U ∧ (2 : Var) ∈ Determined full U := by decide

/-- The full residual is satisfiable, so the previous theorem is not vacuous. -/
def rhoF : Assign :=
  fun w => if w = 3 then {0,1,2} else if w = 1 then {0} else if w = 2 then {2}
           else if w = 0 then {0,3,4,5} else ∅

theorem rhoF_models : SModels rhoF full := by
  intro c hc
  simp only [full, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl <;> exact ⟨by decide, by decide⟩

/-- ...and by `determined_unique`, every model of the full residual is pinned at `i` and
`v3` by its value at `s`. -/
theorem full_unique {rho rho' : Assign} (h : SModels rho full) (h' : SModels rho' full)
    (hs : rho 0 = rho' 0) : rho 1 = rho' 1 ∧ rho 2 = rho' 2 := by
  have hU : AgreeOn rho rho' U := by
    intro v hv
    simp only [U, Finset.mem_singleton] at hv
    subst hv; exact hs
  have h1 := determined_unique h h' hU
  rw [full_det] at h1
  exact ⟨h1 1 (by decide), h1 2 (by decide)⟩

end Pivot

/-! ## 7. R3.2(a) — the candidate splice guard, refuted in BOTH directions -/

namespace SpliceGuard13

/-! ### The guard licenses a splice that LOSES a consequence -/

/-- `Splice.DroppedPartition`'s system as a `System`: `b <- (v)`, `b <- (y)`, `v <- (x)`,
with `v = 0` the ambiguous variable, `x = 1`, `y = 2`, `b = 3`. -/
def Gs : System := {⟨3, [0], ∅⟩, ⟨3, [2], ∅⟩, ⟨0, [1], ∅⟩}

/-- `U₀ = vars \ es`: everything but the one existential. -/
def U0 : Finset Var := {1, 2, 3}

theorem Gs_eq : DroppedPartition.G.toFinset = Gs := by decide

/-- **`v` IS determined**, and already by ROSE's clause alone: `v <- (x)` is in the
residual and `x` is universal. -/
theorem v_determined :
    (0 : Var) ∈ RoseDetermined Gs U0 ∧ (0 : Var) ∈ Determined Gs U0 := by decide

/-- The consequence that is lost lives entirely in the universal vocabulary. -/
theorem c_over_U0 : insert DroppedPartition.c.lhs (vset DroppedPartition.c) ⊆ U0 := by decide

/-- **REFUTED: determinedness does NOT make the splice conservative.**  Every hypothesis
of the candidate guard holds -- `v` is determined by the residual from the universal
vocabulary, under Rose's closure and a fortiori under Ermine's -- and the splice still
drops a consequence of the input that is stated in the universal vocabulary alone.
The condition that fails is `splice_entails_iff`'s `hlhs`, which is SYNTACTIC (`v` heads a
constraint of the emitted list) and therefore invisible to any closure on models. -/
theorem determined_splice_not_conservative :
    (0 : Var) ∈ RoseDetermined Gs U0 ∧
      (0 : Var) ∈ Determined Gs U0 ∧
      DroppedPartition.G.toFinset = Gs ∧
      insert DroppedPartition.c.lhs (vset DroppedPartition.c) ⊆ U0 ∧
      Entails DroppedPartition.G DroppedPartition.c ∧
      ¬ Entails (spliceG DroppedPartition.v DroppedPartition.p DroppedPartition.G)
        DroppedPartition.c :=
  ⟨v_determined.1, v_determined.2, Gs_eq, c_over_U0,
    DroppedPartition.entails_c, DroppedPartition.not_entails⟩

/-! ### ...and it BLOCKS a splice that is conservative -/

/-- `b <- (v, w)`, `b <- (x, w)`, with `v = 0`, `x = 1`, `b = 3`, `w = 4`.  `x` is the only
universal: `v`, `w` and `b` are all existential. -/
def Hl : List Constraint := [⟨3, [0, 4], ∅⟩, ⟨3, [1, 4], ∅⟩]
def Hs : System := {⟨3, [0, 4], ∅⟩, ⟨3, [1, 4], ∅⟩}
def V0 : Finset Var := {1}

/-- The partition the saturated set offers: `v <- (x)`.  It is not in the residual. -/
def p : Constraint := ⟨0, [1], ∅⟩

theorem Hs_eq : Hl.toFinset = Hs := by decide

/-- **`v` is NOT determined**, under either closure. -/
theorem v_undetermined :
    (0 : Var) ∉ RoseDetermined Hs V0 ∧ (0 : Var) ∉ Determined Hs V0 := by decide

/-- ...and yet the input entails `v <- (x)`: cancel `w` from both constraints. -/
theorem entails_p : Entails Hl p := by
  intro rho hm
  have h1 : Sat rho (⟨3, [0, 4], ∅⟩ : Constraint) := hm _ (by simp [Hl])
  have h2 : Sat rho (⟨3, [1, 4], ∅⟩ : Constraint) := hm _ (by simp [Hl])
  have e1 := h1.eq_sdiff (v := 0) (by decide)
  have e2 := h2.eq_sdiff (v := 1) (by decide)
  have hv : (vset (⟨3, [0, 4], ∅⟩ : Constraint)).erase 0 = {4} := by decide
  have hw : (vset (⟨3, [1, 4], ∅⟩ : Constraint)).erase 1 = {4} := by decide
  rw [hv] at e1
  rw [hw] at e2
  exact (sat_eqc rho 0 1).mpr (by rw [e1, e2])

/-- **REFUTED the other way: the splice is conservative and the guard blocks it.**
`splice_entails_iff` applies -- `v` heads nothing in the residual, and both concrete-part
conditions are vacuous -- so the residual entails exactly the `v`-free consequences of the
input, while `v` is in neither closure. -/
theorem undetermined_splice_is_conservative :
    (0 : Var) ∉ RoseDetermined Hs V0 ∧ (0 : Var) ∉ Determined Hs V0 ∧
      Hl.toFinset = Hs ∧ Entails Hl p ∧
      ∀ c : Constraint, (0 : Var) ≠ c.lhs → (0 : Var) ∉ c.vars →
        (Entails (spliceG 0 p Hl) c ↔ Entails Hl c) := by
  refine ⟨v_undetermined.1, v_undetermined.2, Hs_eq, entails_p, ?_⟩
  intro c h1 h2
  refine splice_entails_iff (v := 0) (p := p) rfl entails_p ?_ ?_ ?_ ⟨h1, h2⟩
  · decide
  · intro d _ _; simp [p]
  · intro d _ _; rfl

end SpliceGuard13

/-! ## 8. Published residuals, and R3.2(b) — the deletion licence -/

/-- What `Subst.generalize` publishes: a set of EXISTENTIALLY bound row variables and the
constraint system over them.  (`ROSE-COMPARISON.md` §4.1's `Residual`, restated here
because that file's `CanonSpec.lean` is scratch and never entered the library.) -/
structure Residual where
  /-- The variables `generalize` binds existentially. -/
  ex : Finset Var
  /-- The published partitions. -/
  sys : System
deriving DecidableEq

/-- The reading a CALL SITE has of a published qualification: the universals are fixed by
the caller, the existentials are the callee's to choose. -/
def Holds (rho : Assign) (R : Residual) : Prop :=
  ∃ rho' : Assign, (∀ v, v ∉ R.ex → rho' v = rho v) ∧ SModels rho' R.sys

def REntails (R S : Residual) : Prop := ∀ rho, Holds rho R → Holds rho S

def REquiv (R S : Residual) : Prop := REntails R S ∧ REntails S R

/-- Deleting a constraint can only weaken, so `REquiv` after a deletion is one implication. -/
theorem rEntails_erase (R : Residual) (c : Constraint) : REntails R ⟨R.ex, R.sys.erase c⟩ := by
  rintro rho ⟨rho', hag, hm⟩
  exact ⟨rho', hag, fun d hd => hm d (Finset.mem_of_mem_erase hd)⟩

/-- A DEAD existential: `v` is bound existentially, it is the left-hand side of exactly one
constraint `c`, and it occurs nowhere else in the system. -/
def DeadEx (R : Residual) (v : Var) (c : Constraint) : Prop :=
  v ∈ R.ex ∧ c ∈ R.sys ∧ c.lhs = v ∧ v ∉ vset c ∧
    ∀ d ∈ R.sys.erase c, d.lhs ≠ v ∧ v ∉ vset d

/-- **What Definition 13 licenses about deleting a dead existential: the VALUE, and only
the value.**  A dead existential's defining constraint may be deleted exactly when the
remaining system already forces its right-hand side to COMBINE -- that is, to be pairwise
disjoint.  Definition 13 says the whole is determined by the parts; it does not say the
parts combine, because the row algebra is a PARTIAL monoid (`Rose.labelAlgebra`), and
the definedness of the combination is a genuine constraint on the parts. -/
theorem dead_delete_of_pairwise {R : Residual} {v : Var} {c : Constraint}
    (h : DeadEx R v c)
    (hdisj : ∀ rho, SModels rho (R.sys.erase c) → (parts rho c).Pairwise Disjoint) :
    REquiv R ⟨R.ex, R.sys.erase c⟩ := by
  obtain ⟨hvex, hcmem, hclhs, hvc, hrest⟩ := h
  refine ⟨rEntails_erase R c, ?_⟩
  rintro rho ⟨sigma, hag, hm⟩
  refine ⟨setVar sigma v (c.conc ∪ (vset c).biUnion sigma), ?_, ?_⟩
  · intro w hw
    rw [setVar_of_ne _ _ (by rintro rfl; exact hw hvex)]
    exact hag w hw
  · intro d hd
    rcases eq_or_ne d c with rfl | hdc
    · -- the deleted constraint, satisfied by construction
      have hagree : ∀ w ∈ d.vars, setVar sigma v (d.conc ∪ (vset d).biUnion sigma) w = sigma w :=
        fun w hw => setVar_of_ne _ _ (by rintro rfl; exact hvc (List.mem_toFinset.mpr hw))
      constructor
      · rw [hclhs, setVar_self, parts, List.foldr_cons, foldr_union_map]
        congr 1
        exact Finset.biUnion_congr rfl (fun w hw => (hagree w (List.mem_toFinset.mp hw)).symm)
      · have hp : parts (setVar sigma v (d.conc ∪ (vset d).biUnion sigma)) d = parts sigma d := by
          simp only [parts, List.cons.injEq, true_and]
          exact List.map_congr_left hagree
        rw [hp]
        exact hdisj sigma hm
    · have hde : d ∈ R.sys.erase c := Finset.mem_erase.mpr ⟨hdc, hd⟩
      obtain ⟨hdl, hdv⟩ := hrest d hde
      refine (sat_congr_of_agree (rho := sigma) ?_).mp (hm d hde)
      intro w hw
      refine (setVar_of_ne _ _ ?_).symm
      rintro rfl
      rcases hw with rfl | hw
      · exact hdl rfl
      · exact hdv hw

/-- The unconditional case: a dead existential whose definition has AT MOST ONE part.
There is nothing for the parts to be disjoint from, so the deletion is licensed outright. -/
theorem dead_delete_of_le_one_part {R : Residual} {v : Var} {c : Constraint}
    (h : DeadEx R v c) (hp : c.vars = [] ∨ (c.conc = ∅ ∧ ∃ u, c.vars = [u])) :
    REquiv R ⟨R.ex, R.sys.erase c⟩ := by
  refine dead_delete_of_pairwise h (fun rho _ => ?_)
  rcases hp with hnil | ⟨hc, u, hu⟩
  · simp [parts, hnil]
  · simp [parts, hu, hc]

/-! ### ...and the two refutations -/

namespace DeadTwoParts

/-- `v <- (x, y)` with `v = 0` a dead existential, `x = 1`, `y = 2` universal. -/
def c : Constraint := ⟨0, [1, 2], ∅⟩
def R : Residual := ⟨{0}, {c}⟩
def R' : Residual := ⟨{0}, ∅⟩

theorem dead : DeadEx R 0 c := by
  refine ⟨by decide, by decide, rfl, by decide, ?_⟩
  intro d hd
  simp [R, c] at hd

/-- Rose's clause DOES determine `v` here: the whole is determined by the parts. -/
theorem v_determined : (0 : Var) ∈ RoseDetermined R.sys {1, 2} := by decide

theorem erase_eq : R.sys.erase c = R'.sys := by decide

/-- The refuting caller: `x` and `y` both `{0}`, which the deleted constraint forbids. -/
def rhoBad : Assign := fun _ => {0}

/-- **REFUTED: a dead existential whose value is determined by its parts is NOT deletable.**
The constraint `v <- (x, y)` also says `x` and `y` are DISJOINT, and that survives the
existential quantification of `v`.  The gap is exactly the partiality of the row algebra. -/
theorem two_parts_not_deletable : ¬ REquiv R R' := by
  rintro ⟨-, hback⟩
  obtain ⟨tau, hag, hm⟩ := hback rhoBad ⟨rhoBad, fun _ _ => rfl, by intro d hd; simp [R'] at hd⟩
  have hs : Sat tau c := hm c (by decide)
  have hd : Disjoint (tau 1) (tau 2) := hs.disjoint_of_ne' (by decide) (by decide) (by decide)
  have h1 : tau 1 = ({0} : Row) := hag 1 (by decide)
  have h2 : tau 2 = ({0} : Row) := hag 2 (by decide)
  rw [h1, h2] at hd
  exact absurd (eq_empty_of_disjoint_self hd) (by decide)

end DeadTwoParts

namespace DeadUndetermined

/-- `a <- (v, w, (|Foo|))` with `Foo = 0`: `a = 0` is the only UNIVERSAL, `v = 1` and
`w = 2` are existential. -/
def c : Constraint := ⟨0, [1, 2], {0}⟩
def R : Residual := ⟨{1, 2}, {c}⟩
def R' : Residual := ⟨{1, 2}, ∅⟩

/-- `U₀`, the universal vocabulary of the residual. -/
def U0 : Finset Var := {0}

theorem U0_eq : allVars R.sys \ R.ex = U0 := by decide

/-- `v` is NOT determined by the universal vocabulary, under either closure... -/
theorem v_undetermined :
    (1 : Var) ∉ RoseDetermined R.sys U0 ∧ (1 : Var) ∉ Determined R.sys U0 := by decide

/-- ...and knowing `v` determines nothing in the universal vocabulary either. -/
theorem v_determines_nothing :
    (0 : Var) ∉ RoseDetermined R.sys {1} ∧ (0 : Var) ∉ Determined R.sys {1} := by decide

theorem erase_eq : R.sys.erase c = R'.sys := by decide

/-- **REFUTED: "neither determined by nor determining the universals" does NOT license the
deletion.**  The constraint still says `Foo ∈ a`, which is a restriction on the universal
`a` and survives the existential quantification of `v` and `w`. -/
theorem undetermined_not_deletable : ¬ REquiv R R' := by
  rintro ⟨-, hback⟩
  obtain ⟨tau, hag, hm⟩ :=
    hback (fun _ => ∅) ⟨fun _ => ∅, fun _ _ => rfl, by intro d hd; simp [R'] at hd⟩
  have hs : Sat tau c := hm c (by decide)
  have hsub : c.conc ⊆ tau c.lhs := hs.conc_subset_lhs
  have h0 : tau 0 = (∅ : Row) := hag 0 (by decide)
  have : (0 : Label) ∈ tau 0 := hsub (by decide)
  rw [h0] at this
  exact absurd this (by decide)

end DeadUndetermined

/-! ### S5.1 (ticket C12) — the deletion licence with the UNIVERSAL on the LEFT

`dead_delete_of_pairwise` and `dead_delete_of_le_one_part` are both about a dead
EXISTENTIAL on the LEFT of the deleted constraint: `v <- (...)` with `v` bound by the
`exists`.  The shape four stdlib signatures actually publish is the mirror image --
the left-hand side is a variable the CALLER fixes (a universal), and it is the PARTS
that are existential and occur nowhere else (`tracker/TICKET-stdlib-findings.md` C12
says FIVE; the fifth, `sumBy'`, was hand-fixed in the source by stage F3 the day after
C12 was written.  `R3-REVIEW.md` M-3 is the observation that R3's theorems do not
cover this shape):

    count : forall (f: * -> *) z k (r: rho). (exists (t: a) (h: b). r <- (h, t)) => ...

Every row splits, so that qualification constrains no caller: take `t := rho r` and
`h := ∅`.  `tauto_delete` is the general form -- `k ≥ 1` existential parts, NO concrete
labels, every part fresh with respect to the rest of the system -- and `tauto_delete_two`
is the two-part instance C12 states.

WHICH SIDE CONDITIONS ARE NECESSARY, AND WHICH ARE NOT.  Three of them live in the
SHAPE of the statement rather than in a hypothesis -- the parts are all existential
(`⟨ex ∪ P, ..⟩` against `⟨ex, ..⟩`), the concrete part is empty (`mk r P ∅`), and the
deleted constraint is a single `insert` -- and three are hypotheses: `hne`, `hr`,
`hfresh`.  FOUR of those five conditions are load-bearing and each has a witness; the
fifth, `hr`, is NOT necessary.  (The S5 review, finding Q-3, is what established this:
the first version of this section cited `DeadTwoParts.two_parts_not_deletable` for
`hfresh`, and that theorem has the WRONG ORIENTATION -- its deleted constraint's
left-hand side is the existential and its parts are universal, which is R3's mirror
shape, not this one.  `RevHfresh` and `RevUnivPart` below are the reviewer's witnesses,
adopted here; `tauto_delete_no_hr` is the reviewer's proof that `hr` can go.)

* A CONCRETE part is not allowed: `DeadUndetermined.undetermined_not_deletable` is
  `a <- (v, w, (|Foo|))` with `v`, `w` existential and fresh, and it is NOT deletable --
  the constraint still says `Foo ∈ rho a`, which is about the universal.  That IS this
  theorem's orientation (`R.ex = {1,2}`, lhs `0` universal): it is `tauto_delete` with
  `∅` replaced by `{0}`.
* A UNIVERSAL part is not allowed -- the Scala side condition `vs.forall(ex)`:
  `RevUnivPart.univ_part_needed`, `r = 0`, parts `{1, 2}` with `1` universal.
* A part occurring ELSEWHERE is not allowed -- `hfresh`:
  `RevHfresh.hfresh_needed`, `r = 0`, `P = {1}`, `G = {2 <- (1)}`, `ex = ∅`, where every
  other hypothesis holds and the equivalence still fails.
* `k = 0` is not allowed -- `hne`: `r <- ()` says `rho r = ∅`, a genuine condition on the
  universal, and `TautoEmpty.tauto_empty_not_deletable` proves it.
* `hr : r ∉ P` IS NOT NECESSARY: `tauto_delete_no_hr` proves the same conclusion without
  it, by taking `r` itself as the distinguished part when `r ∈ P`.  `tauto_delete` keeps
  it because the proof reads more simply with it and because the Scala side condition is
  narrower still -- there `r ∉ P` FOLLOWS from `!ex(r) && vs.forall(ex)`.

C12 also carries `t ≠ h`, and it is not a hypothesis here.  In the `Finset` formulation
`{t, h}` with `t = h` IS the singleton `{t}`, i.e. the `k = 1` case, which the same
theorem covers.  BUT NOTE WHAT THAT DOES AND DOES NOT SAY: it says the theorem has
nothing to exclude, NOT that a surface constraint `r <- (t, t)` is a tautology.  That
one asserts `t` disjoint from ITSELF, which forces `rho t = ∅` and `rho r = ∅` with it,
and it is a different constraint from `mk r {t} ∅`.  The solver collapses a repeated
variable part before it can reach a residual (`RHS.build` moves it into the forced-empty
set; `LoopRel.dedup`, sound by `dedup_sat`), and the implementation of this deletion
rejects a repeated part outright rather than relying on that.
-/

namespace Tauto

/-- The witness that discharges a fresh, all-existential, label-free split: one
distinguished part takes the whole of the left-hand side, every other part is empty. -/
def wit (sigma : Assign) (r p0 : Var) (P : Finset Var) : Assign :=
  fun v => if v = p0 then sigma r else if v ∈ P then ∅ else sigma v

@[simp] theorem wit_p0 (sigma : Assign) (r p0 : Var) (P : Finset Var) :
    wit sigma r p0 P p0 = sigma r := by simp [wit]

theorem wit_of_mem {sigma : Assign} {r p0 : Var} {P : Finset Var} {v : Var}
    (hv : v ∈ P) (hne : v ≠ p0) : wit sigma r p0 P v = ∅ := by simp [wit, hne, hv]

theorem wit_of_not_mem {sigma : Assign} {r p0 : Var} {P : Finset Var} {v : Var}
    (hP : v ∉ P) (hp0 : p0 ∈ P) : wit sigma r p0 P v = sigma v := by
  have hne : v ≠ p0 := by rintro rfl; exact hP hp0
  simp [wit, hne, hP]

end Tauto

/-- **C12, the general theorem.**  A partition whose left-hand side is any variable
outside the parts, whose parts are ALL existential, carry NO concrete labels, and occur
in NO other constraint of the system, may be deleted together with its parts: the
residual before and after have exactly the same callers.

The forward direction is NOT `rEntails_erase`: the existential set shrinks as well as
the system, so the dropped variables have to be re-tied to the caller's assignment. -/
theorem tauto_delete {ex : Finset Var} {G : System} {r : Var} {P : Finset Var}
    (hne : P.Nonempty) (hr : r ∉ P) (hfresh : ∀ p ∈ P, p ∉ allVars G) :
    REquiv ⟨ex ∪ P, insert (mk r P ∅) G⟩ ⟨ex, G⟩ := by
  classical
  obtain ⟨p0, hp0⟩ := hne
  constructor
  · rintro rho ⟨sigma, hag, hm⟩
    refine ⟨fun v => if v ∈ ex then sigma v else rho v, ?_, ?_⟩
    · intro v hv
      exact if_neg hv
    · intro d hd
      refine (sat_congr_of_agree (rho := sigma) ?_).mp (hm d (Finset.mem_insert_of_mem hd))
      intro w hw
      by_cases hwe : w ∈ ex
      · exact (if_pos hwe).symm
      · have hwP : w ∉ P := fun hp => hfresh w hp (mem_allVars hd hw)
        exact (hag w (fun hh => (Finset.mem_union.mp hh).elim hwe hwP)).trans
          (if_neg hwe).symm
  · rintro rho ⟨sigma, hag, hm⟩
    refine ⟨Tauto.wit sigma r p0 P, ?_, ?_⟩
    · intro v hv
      have hv' : v ∉ ex ∧ v ∉ P := by
        constructor <;> intro hh <;> exact hv (Finset.mem_union.mpr (by simp [hh]))
      rw [Tauto.wit_of_not_mem hv'.2 hp0]
      exact hag v hv'.1
    · have hbi : P.biUnion (Tauto.wit sigma r p0 P) = sigma r := by
        ext l
        simp only [Finset.mem_biUnion]
        constructor
        · rintro ⟨p, hpP, hl⟩
          by_cases hp : p = p0
          · subst hp; simpa using hl
          · rw [Tauto.wit_of_mem hpP hp] at hl; simp at hl
        · intro hl; exact ⟨p0, hp0, by simpa using hl⟩
      intro d hd
      rcases Finset.mem_insert.mp hd with rfl | hdG
      · rw [sat_mk_iff]
        refine ⟨?_, ?_, ?_⟩
        · rw [Tauto.wit_of_not_mem hr hp0, hbi, Finset.empty_union]
        · intro v _; exact Finset.disjoint_empty_left _
        · intro v hv w hw hvw
          by_cases hv0 : v = p0
          · have hw0 : w ≠ p0 := fun hh => hvw (hv0.trans hh.symm)
            rw [Tauto.wit_of_mem hw hw0]; exact Finset.disjoint_empty_right _
          · rw [Tauto.wit_of_mem hv hv0]; exact Finset.disjoint_empty_left _
      · refine (sat_congr_of_agree (rho := sigma) ?_).mp (hm d hdG)
        intro w hw
        exact (Tauto.wit_of_not_mem (fun hp => hfresh w hp (mem_allVars hdG hw)) hp0).symm

/-- **C12 as stated**: the two-part instance.  `r` universal, `t` and `h` existential
and occurring in no other published constraint. -/
theorem tauto_delete_two {ex : Finset Var} {G : System} {r t h : Var}
    (hrt : r ≠ t) (hrh : r ≠ h) (ht : t ∉ allVars G) (hh : h ∉ allVars G) :
    REquiv ⟨ex ∪ {t, h}, insert (mk r {t, h} ∅) G⟩ ⟨ex, G⟩ := by
  refine tauto_delete ⟨t, by simp⟩ (by simp [hrt, hrh]) ?_
  intro p hp
  rcases Finset.mem_insert.mp hp with rfl | hp'
  · exact ht
  · rw [Finset.mem_singleton.mp hp']; exact hh

/-- **`hr` is not necessary** (S5 review, Q-4).  The same `REquiv` without `r ∉ P`: when
`r ∈ P`, take `r` ITSELF as the distinguished part and the witness still works.  Kept as a
separate declaration rather than as the primary statement because every use -- the Scala
side condition included -- has `r ∉ P` on hand, and the shorter proof of `tauto_delete` is
the one worth reading. -/
theorem tauto_delete_no_hr {ex : Finset Var} {G : System} {r : Var} {P : Finset Var}
    (hne : P.Nonempty) (hfresh : ∀ p ∈ P, p ∉ allVars G) :
    REquiv ⟨ex ∪ P, insert (mk r P ∅) G⟩ ⟨ex, G⟩ := by
  classical
  by_cases hr : r ∈ P
  · constructor
    · rintro rho ⟨sigma, hag, hm⟩
      refine ⟨fun v => if v ∈ ex then sigma v else rho v, ?_, ?_⟩
      · intro v hv
        exact if_neg hv
      · intro d hd
        refine (sat_congr_of_agree (rho := sigma) ?_).mp (hm d (Finset.mem_insert_of_mem hd))
        intro w hw
        by_cases hwe : w ∈ ex
        · exact (if_pos hwe).symm
        · have hwP : w ∉ P := fun hp => hfresh w hp (mem_allVars hd hw)
          exact (hag w (fun hh => (Finset.mem_union.mp hh).elim hwe hwP)).trans (if_neg hwe).symm
    · rintro rho ⟨sigma, hag, hm⟩
      refine ⟨Tauto.wit sigma r r P, ?_, ?_⟩
      · intro v hv
        have hv' : v ∉ ex ∧ v ∉ P := by
          constructor <;> intro hh <;> exact hv (Finset.mem_union.mpr (by simp [hh]))
        rw [Tauto.wit_of_not_mem hv'.2 hr]
        exact hag v hv'.1
      · have hbi : P.biUnion (Tauto.wit sigma r r P) = sigma r := by
          ext l
          simp only [Finset.mem_biUnion]
          constructor
          · rintro ⟨p, hpP, hl⟩
            by_cases hp : p = r
            · subst hp; simpa using hl
            · rw [Tauto.wit_of_mem hpP hp] at hl; simp at hl
          · intro hl; exact ⟨r, hr, by simpa using hl⟩
        intro d hd
        rcases Finset.mem_insert.mp hd with rfl | hdG
        · rw [sat_mk_iff]
          refine ⟨?_, ?_, ?_⟩
          · rw [Tauto.wit_p0, hbi, Finset.empty_union]
          · intro v _; exact Finset.disjoint_empty_left _
          · intro v hv w hw hvw
            by_cases hv0 : v = r
            · have hw0 : w ≠ r := fun hh => hvw (hv0.trans hh.symm)
              rw [Tauto.wit_of_mem hw hw0]; exact Finset.disjoint_empty_right _
            · rw [Tauto.wit_of_mem hv hv0]; exact Finset.disjoint_empty_left _
        · refine (sat_congr_of_agree (rho := sigma) ?_).mp (hm d hdG)
          intro w hw
          exact (Tauto.wit_of_not_mem (fun hp => hfresh w hp (mem_allVars hdG hw)) hr).symm
  · exact tauto_delete hne hr hfresh

/-! #### The corpus shape, and every side condition that cannot be dropped

`RevHfresh` and `RevUnivPart` are the S5 reviewer's, adopted verbatim from
`review-S5/Probe.lean` with their names kept so the review's `#print axioms` lines
reproduce against this file. -/

namespace ScanCount

/-- `Layout.Scan.count`'s published residual, as a `Residual`: `r = 0` is the
UNIVERSAL, `h = 1` and `t = 2` are the existentials, and there is nothing else. -/
def c : Constraint := mk 0 {1, 2} ∅
def R : Residual := ⟨{1, 2}, {c}⟩
def R' : Residual := ⟨∅, ∅⟩

/-- The published qualification of `count` says nothing: it is `REquiv` to the empty
residual, which is what `mkSimplified` now publishes. -/
theorem count_tautology : REquiv R R' := by
  have h : REquiv ⟨(∅ : Finset Var) ∪ {1, 2}, insert (mk 0 {1, 2} ∅) (∅ : System)⟩
                  ⟨(∅ : Finset Var), (∅ : System)⟩ :=
    tauto_delete_two (by decide) (by decide) (by decide) (by decide)
  simpa [R, R', c] using h

end ScanCount

namespace TautoEmpty

/-- `r <- ()`: the `k = 0` case.  `r = 0` is universal; there are no parts. -/
def c : Constraint := mk 0 ∅ ∅
def R : Residual := ⟨∅, {c}⟩
def R' : Residual := ⟨∅, ∅⟩

/-- **`P.Nonempty` is necessary.**  With no parts the constraint says `rho r = ∅`,
which is a condition on the universal and does not survive deletion. -/
theorem tauto_empty_not_deletable : ¬ REquiv R R' := by
  rintro ⟨-, hback⟩
  obtain ⟨tau, hag, hm⟩ :=
    hback (fun _ => ({0} : Row)) ⟨fun _ => ({0} : Row), fun _ _ => rfl,
      by intro d hd; simp [R'] at hd⟩
  have hs : Sat tau c := hm c (by simp [R])
  have h0 : tau 0 = ({0} : Row) := hag 0 (by simp [R])
  have he := hs.eq_biUnion
  simp only [c, lhs_mk, conc_mk, vset_mk, Finset.biUnion_empty, Finset.empty_union] at he
  rw [h0] at he
  simp at he

end TautoEmpty

namespace RevHfresh

/-- `r <- (t)` with `t` existential, and `t` ALSO a part of `2 <- (t)` in the rest of the
system.  `r = 0`, `P = {1}`, `G = {2 <- (1)}`, `ex = ∅`. -/
def cT : Constraint := mk 0 {1} ∅
def d  : Constraint := mk 2 {1} ∅
def G  : System := {d}
def R  : Residual := ⟨(∅ : Finset Var) ∪ {1}, insert cT G⟩
def R' : Residual := ⟨(∅ : Finset Var), G⟩

/-- every hypothesis of `tauto_delete` except `hfresh` holds here -/
theorem hyps : ({1} : Finset Var).Nonempty ∧ (0 : Var) ∉ ({1} : Finset Var) :=
  ⟨⟨1, by decide⟩, by decide⟩

def rho : Assign := fun v => if v = 1 then {0} else ∅

theorem holds_R : Holds rho R := by
  refine ⟨fun _ => ∅, ?_, ?_⟩
  · intro v hv
    have hv1 : v ≠ 1 := by
      rintro rfl; exact hv (by simp [R])
    simp [rho, hv1]
  · intro c hc
    have : c = cT ∨ c = d := by
      rcases Finset.mem_insert.mp hc with h | h
      · exact Or.inl h
      · exact Or.inr (Finset.mem_singleton.mp h)
    rcases this with rfl | rfl <;> simp [cT, d, sat_mk_iff]

theorem not_holds_R' : ¬ Holds rho R' := by
  rintro ⟨tau, hag, hm⟩
  have h1 : tau 1 = rho 1 := hag 1 (by simp [R'])
  have h2 : tau 2 = rho 2 := hag 2 (by simp [R'])
  have hs : Sat tau d := hm d (by simp [R', G])
  unfold d at hs
  rw [sat_mk_iff] at hs
  have := hs.1
  simp only [Finset.empty_union, Finset.singleton_biUnion] at this
  rw [h1, h2] at this
  simp [rho] at this

/-- **`hfresh` IS necessary.**  Nothing here is about disjointness: the surviving
constraint `2 <- (1)` pins the part to the rest of the system, so the caller cannot
re-choose it. -/
theorem hfresh_needed : ¬ REquiv R R' := fun h => not_holds_R' (h.1 rho holds_R)

end RevHfresh

namespace RevUnivPart

/-- `r <- (u, e)` with `u` UNIVERSAL and `e` existential: `r = 0`, parts `{1, 2}`,
`ex = {2}`.  This is C12's orientation; `DeadTwoParts` is R3's mirror of it. -/
def c : Constraint := mk 0 {1, 2} ∅
def R  : Residual := ⟨{2}, {c}⟩
def R' : Residual := ⟨{2}, (∅ : System)⟩

def rho : Assign := fun v => if v = 1 then {0} else ∅

theorem holds_R' : Holds rho R' :=
  ⟨rho, fun _ _ => rfl, by intro d hd; simp [R'] at hd⟩

theorem not_holds_R : ¬ Holds rho R := by
  rintro ⟨tau, hag, hm⟩
  have h0 : tau 0 = rho 0 := hag 0 (by simp [R])
  have h1 : tau 1 = rho 1 := hag 1 (by simp [R])
  have hs : Sat tau c := hm c (by simp [R])
  unfold c at hs
  rw [sat_mk_iff] at hs
  have he := hs.1
  have hmem : (0 : Label) ∈ tau 0 := by
    rw [he]
    simp only [Finset.mem_union, Finset.mem_biUnion]
    exact Or.inr ⟨1, by decide, by rw [h1]; simp [rho]⟩
  rw [h0] at hmem
  simp [rho] at hmem

/-- **A universal part is a real containment**, so the deletion needs every part to be
existential -- which in `tauto_delete` is carried by the SHAPE (`⟨ex ∪ P, ..⟩` against
`⟨ex, ..⟩`) and in `Subst.deleteTautologies` by `vs.forall(ex)`. -/
theorem univ_part_needed : ¬ REquiv R R' := fun h => not_holds_R (h.2 rho holds_R')

end RevUnivPart

/-! ## 9. R3.2(c) — Definition 14 as a ROW-AMBIGUITY criterion -/

/-- **The criterion.**  A published `exists es. cs => tau` is ROW-AMBIGUOUS when some
existential is not determined by the universal vocabulary.

`U₀` is taken to be `allVars cs \ ex`, and that is EXACTLY `fv(tau) ∪ universals` as far as
the closure can tell: a variable of `tau` that occurs in no constraint can never be used by
either clause, since both quantify over constraints of the system.

THE `∀T` VERSUS `exists` READING (`R2-REVIEW.md` K-9(3)).  Rose's Definition 14 is about
`∀T.Ψ ⇒ τ` and its payoff, Theorem 15, is coherence of ELABORATION: two derivations of the
same term produce βη-equal programs.  Ermine binds these variables EXISTENTIALLY, and
`Holds` above is the reading that gives: the callee chooses the witness.  So the criterion
transfers as a statement about the WITNESS, not about elaboration -- which is
`witness_unique_of_not_rowAmbiguous` below -- and Ermine's rows are erased at run time (a
`Row r` carries its field types as a value, `modules/Relation/Row.e`), so an undetermined row
existential cannot change what the program computes.  The payoff here is PRECISION of the
published type, not soundness of elaboration.  Theorem 15 itself is unavailable in any case:
Definition 14 defines coherence of a TERM through its PRINCIPAL type scheme, and Ermine has
no principality theorem (`ROSE-COMPARISON.md` §1.5), so Definition 14 is not merely unmet but
not yet well-defined.  Definition 13 is imported as a CRITERION. -/
def RowAmbiguous (R : Residual) : Prop :=
  ∃ v ∈ R.ex, v ∉ Determined R.sys (allVars R.sys \ R.ex)

/-- The same criterion with Rose's clause alone. -/
def RoseRowAmbiguous (R : Residual) : Prop :=
  ∃ v ∈ R.ex, v ∉ RoseDetermined R.sys (allVars R.sys \ R.ex)

/-- Rose's closure is smaller, so Rose's criterion flags at least as much. -/
theorem roseRowAmbiguous_of_rowAmbiguous {R : Residual} (h : RowAmbiguous R) :
    RoseRowAmbiguous R := by
  obtain ⟨v, hv, hnd⟩ := h
  exact ⟨v, hv, fun hh => hnd (roseDetermined_subset _ _ hh)⟩

/-- **What the criterion buys: a UNIQUE witness.**  If no existential escapes the closure,
then any two witnesses a call site could choose agree on every variable the system mentions.
This is the row-level analogue of Rose's coherence conclusion. -/
theorem witness_unique_of_not_rowAmbiguous {R : Residual} (h : ¬ RowAmbiguous R)
    {rho sigma tau : Assign}
    (hs1 : ∀ v, v ∉ R.ex → sigma v = rho v) (hs2 : SModels sigma R.sys)
    (ht1 : ∀ v, v ∉ R.ex → tau v = rho v) (ht2 : SModels tau R.sys) :
    ∀ v ∈ allVars R.sys, sigma v = tau v := by
  simp only [RowAmbiguous, not_exists, not_and, not_not] at h
  have hU : AgreeOn sigma tau (allVars R.sys \ R.ex) := by
    intro v hv
    have hvx : v ∉ R.ex := (Finset.mem_sdiff.mp hv).2
    rw [hs1 v hvx, ht1 v hvx]
  have hall := determined_unique hs2 ht2 hU
  intro v hv
  by_cases hvx : v ∈ R.ex
  · exact hall v (h v hvx)
  · exact hall v (subset_determined _ _ (Finset.mem_sdiff.mpr ⟨hv, hvx⟩))

/-! ### The criterion is SOUND but not COMPLETE -/

namespace CriterionIncomplete

/-- `a <- (v, v, w)`: the repeated part is forced empty (`Sat.eq_empty_of_dup`), so `v` is
semantically pinned in every model, and neither closure sees it. -/
def c : Constraint := ⟨0, [1, 1, 2], ∅⟩
def R : Residual := ⟨{1, 2}, {c}⟩

theorem U0_eq : allVars R.sys \ R.ex = {0} := by decide

/-- The criterion FLAGS `v`... -/
theorem flagged : RowAmbiguous R := by
  refine ⟨1, by decide, ?_⟩
  rw [U0_eq]
  decide

/-- ...but `v` is empty in every model, hence determined by nothing at all. -/
theorem v_forced_empty : ∀ rho, SModels rho R.sys → rho 1 = ∅ := by
  intro rho hm
  exact (hm c (by decide)).eq_empty_of_dup (v := 1) (by decide)

/-- **The criterion is not complete**: it flags a residual whose flagged existential has
exactly one value in every model.  A syntactic closure cannot see a semantic forcing. -/
theorem sound_not_complete :
    RowAmbiguous R ∧ (∀ rho rho', SModels rho R.sys → SModels rho' R.sys → rho 1 = rho' 1) :=
  ⟨flagged, fun rho rho' h h' => by rw [v_forced_empty rho h, v_forced_empty rho' h']⟩

end CriterionIncomplete

/-! ## 10. The two derived predicates of `modules/Constraint.e` -/

namespace Derived

/-- `type Has a b = exists c. a <- (b, c)` -- Rose's containment `b ≼ a`, which Rose keeps
PRIMITIVE and Ermine spells out with a minted existential complement.  `a = 0`, `b = 1`,
`c = 2`. -/
def has : Residual := ⟨{2}, {⟨0, [1, 2], ∅⟩}⟩

/-- `type Disj a b = exists c. c <- (a, b)` -- `a | b`.  `a = 0`, `b = 1`, `c = 2`. -/
def disj : Residual := ⟨{2}, {⟨2, [0, 1], ∅⟩}⟩

theorem has_U0 : allVars has.sys \ has.ex = {0, 1} := by decide
theorem disj_U0 : allVars disj.sys \ disj.ex = {0, 1} := by decide

/-- **`Has`'s complement is determined -- but only by CANCELLATION.**  Rose's clause alone
calls `Has` ambiguous; Ermine's larger closure does not, and it is right: `c = a \ b`. -/
theorem has_needs_cancellation :
    RoseRowAmbiguous has ∧ ¬ RowAmbiguous has := by
  constructor
  · exact ⟨2, by decide, by rw [has_U0]; decide⟩
  · simp only [RowAmbiguous, not_exists, not_and, not_not, has_U0]
    intro v hv
    have : v = 2 := by simpa [has] using hv
    subst this
    decide

/-- Disjointness, by contrast, is Rose's own clause: the whole `c` is determined by the
parts `a` and `b`. -/
theorem disj_is_rose : ¬ RoseRowAmbiguous disj := by
  simp only [RoseRowAmbiguous, not_exists, not_and, not_not, disj_U0]
  intro v hv
  have : v = 2 := by simpa [disj] using hv
  subst this
  decide

end Derived

/-! ## 11. `pivotData` under the criterion -/

namespace Pivot

/-- The published residual, as a `Residual`: `i` and `v3` existential, `s` universal.  The
carrier `p = 3` for the concrete left-hand side is existential too (it is minted). -/
def R : Residual := ⟨{1, 2, 3}, full⟩

theorem R_U0 : allVars R.sys \ R.ex = U := by decide

/-- **Rose's criterion flags `pivotData`; Ermine's does not.**  Both verdicts are correct
statements about their own closure, and Ermine's is the one the models support: by
`full_unique`, the value of `s` pins `i` and `v3`.  What makes the residual look ambiguous
is reading the constraint `(|Issue,Key,Value|) <- ((|Key|), i, v3)` on its own, which is how
`TICKET-row-constraint-decision.md` §1.3 quotes it -- and on its own it IS ambiguous
(`bare_genuinely_ambiguous`). -/
theorem criterion_split : RoseRowAmbiguous R ∧ ¬ RowAmbiguous R := by
  constructor
  · exact ⟨1, by decide, by rw [R_U0]; decide⟩
  · simp only [RowAmbiguous, not_exists, not_and, not_not, R_U0]
    intro v hv
    have : v = 1 ∨ v = 2 ∨ v = 3 := by simpa [R] using hv
    rcases this with rfl | rfl | rfl <;> decide

end Pivot

/-! ## 13. The clause the MEASUREMENT says is missing: RESOLUTION

`R3-DETERMINED.md` §4 hand-checks ten of the signatures the criterion flags and finds seven of
them determined after all, always for the same reason: the residual holds a partition and a
SUB-partition of it, and eliminating the sub-partition as a block determines what is left.
`(!=)` of `modules/Relation/Predicate.e` is the smallest instance —

    b <- (f, e)     a1 <- (e, d)     c <- (f, e, d)

with `a1`, `b`, `c` universal.  `c` and `b` together give `c <- (b, d)`, so `d = c \ b`, and then
plain cancellation finishes.  That step is the solver's own `resolution` (rule 6); the closure of
§2 does not have it.  This section adds it and re-proves the uniqueness theorem, so that a stage
2 has the theorem in hand and only needs the number. -/

/-- **RESOLUTION, as a determinacy clause.**  If `c` is a sub-partition of `d` -- every variable
part and every concrete label of `c` is one of `d`'s -- and both left-hand sides are known, then
`d`'s remaining variable parts are determined once all but one of them is. -/
def resAdd (G : System) (D : Finset Var) : Finset Var :=
  G.biUnion (fun d =>
    G.biUnion (fun c =>
      if c.lhs ∈ D ∧ d.lhs ∈ D ∧ vset c ⊆ vset d ∧ c.conc ⊆ d.conc then
        (vset d \ vset c).filter (fun v => ((vset d \ vset c).erase v) ⊆ D)
      else ∅))

theorem mem_resAdd {G : System} {D : Finset Var} {v : Var} :
    v ∈ resAdd G D ↔ ∃ d ∈ G, ∃ c ∈ G, c.lhs ∈ D ∧ d.lhs ∈ D ∧ vset c ⊆ vset d ∧
      c.conc ⊆ d.conc ∧ v ∈ vset d \ vset c ∧ ((vset d \ vset c).erase v) ⊆ D := by
  simp only [resAdd, Finset.mem_biUnion]
  constructor
  · rintro ⟨d, hd, c, hc, hv⟩
    by_cases h : c.lhs ∈ D ∧ d.lhs ∈ D ∧ vset c ⊆ vset d ∧ c.conc ⊆ d.conc
    · rw [if_pos h, Finset.mem_filter] at hv
      exact ⟨d, hd, c, hc, h.1, h.2.1, h.2.2.1, h.2.2.2, hv.1, hv.2⟩
    · rw [if_neg h] at hv; exact absurd hv (Finset.notMem_empty v)
  · rintro ⟨d, hd, c, hc, h1, h2, h3, h4, h5, h6⟩
    exact ⟨d, hd, c, hc, by rw [if_pos ⟨h1, h2, h3, h4⟩, Finset.mem_filter]; exact ⟨h5, h6⟩⟩

/-- The variable parts of `d` other than `v`, split along the sub-partition `c`. -/
theorem erase_eq_union {c d : Constraint} {v : Var} (hsub : vset c ⊆ vset d)
    (hv : v ∈ vset d) (hvc : v ∉ vset c) :
    (vset d).erase v = vset c ∪ ((vset d \ vset c).erase v) := by
  ext w
  simp only [Finset.mem_erase, Finset.mem_union, Finset.mem_sdiff]
  constructor
  · rintro ⟨hwv, hwd⟩
    by_cases h : w ∈ vset c
    · exact Or.inl h
    · exact Or.inr ⟨hwv, hwd, h⟩
  · rintro (h | ⟨hwv, hwd, -⟩)
    · exact ⟨by rintro rfl; exact hvc h, hsub h⟩
    · exact ⟨hwv, hwd⟩

/-- The set `Sat.eq_sdiff` subtracts, re-expressed through the sub-partition's left-hand side. -/
theorem sdiff_set_eq {rho : Assign} {c d : Constraint} (hc : Sat rho c) {v : Var}
    (hsub : vset c ⊆ vset d) (hconc : c.conc ⊆ d.conc) (hv : v ∈ vset d) (hvc : v ∉ vset c) :
    d.conc ∪ ((vset d).erase v).biUnion rho
      = d.conc ∪ rho c.lhs ∪ ((vset d \ vset c).erase v).biUnion rho := by
  rw [erase_eq_union hsub hv hvc]
  refine Finset.Subset.antisymm (fun l hl => ?_) (fun l hl => ?_)
  · rcases Finset.mem_union.mp hl with h | h
    · exact Finset.mem_union_left _ (Finset.mem_union_left _ h)
    · obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp h
      rcases Finset.mem_union.mp hw with h1 | h1
      · refine Finset.mem_union_left _ (Finset.mem_union_right _ ?_)
        rw [hc.eq_biUnion]
        exact Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨w, h1, hlw⟩)
      · exact Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨w, h1, hlw⟩)
  · rcases Finset.mem_union.mp hl with h | h
    · rcases Finset.mem_union.mp h with h1 | h1
      · exact Finset.mem_union_left _ h1
      · rw [hc.eq_biUnion] at h1
        rcases Finset.mem_union.mp h1 with h2 | h2
        · exact Finset.mem_union_left _ (hconc h2)
        · obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp h2
          exact Finset.mem_union_right _
            (Finset.mem_biUnion.mpr ⟨w, Finset.mem_union_left _ hw, hlw⟩)
    · obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp h
      exact Finset.mem_union_right _
        (Finset.mem_biUnion.mpr ⟨w, Finset.mem_union_right _ hw, hlw⟩)

/-- **RESOLUTION preserves agreement**, so the enlarged closure still has the uniqueness
theorem.  Nothing but `Sat.eq_sdiff` and `Sat.eq_biUnion` is used. -/
theorem agree_resAdd {G : System} {rho rho' : Assign} {D : Finset Var}
    (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (resAdd G D) := by
  intro v hv
  obtain ⟨d, hd, c, hc, hcl, hdl, hsub, hconc, hvd, hrest⟩ := mem_resAdd.mp hv
  have hv1 : v ∈ vset d := (Finset.mem_sdiff.mp hvd).1
  have hv2 : v ∉ vset c := (Finset.mem_sdiff.mp hvd).2
  rw [(hm d hd).eq_sdiff hv1, (hm' d hd).eq_sdiff hv1,
    sdiff_set_eq (hm c hc) hsub hconc hv1 hv2, sdiff_set_eq (hm' c hc) hsub hconc hv1 hv2,
    hD _ hdl, hD _ hcl, agree_biUnion hD hrest]

/-! ### The three-clause closure -/

def resStep (G : System) (D : Finset Var) : Finset Var := detStep G D ∪ resAdd G D

/-- The closure of §2 together with resolution. -/
def Determined3 (G : System) (U : Finset Var) : Finset Var :=
  (resStep G)^[(allVars G).card] U

theorem subset_resStep (G : System) (D : Finset Var) : D ⊆ resStep G D :=
  (subset_detStep G D).trans Finset.subset_union_left

theorem resAdd_subset_allVars (G : System) (D : Finset Var) : resAdd G D ⊆ allVars G := by
  intro v hv
  obtain ⟨d, hd, _c, _hc, _h1, _h2, _h3, _h4, hvd, _h6⟩ := mem_resAdd.mp hv
  exact mem_allVars hd (Or.inr (Finset.mem_sdiff.mp hvd).1)

theorem resAdd_mono (G : System) {D E : Finset Var} (h : D ⊆ E) : resAdd G D ⊆ resAdd G E := by
  intro v hv
  obtain ⟨d, hd, c, hc, h1, h2, h3, h4, h5, h6⟩ := mem_resAdd.mp hv
  exact mem_resAdd.mpr ⟨d, hd, c, hc, h h1, h h2, h3, h4, h5, h6.trans h⟩

theorem resStep_mono (G : System) {D E : Finset Var} (h : D ⊆ E) : resStep G D ⊆ resStep G E :=
  Finset.union_subset_union (detStep_mono G h) (resAdd_mono G h)

theorem resStep_subset (G : System) {W D : Finset Var} (hA : allVars G ⊆ W) (h : D ⊆ W) :
    resStep G D ⊆ W :=
  Finset.union_subset (detStep_subset G hA h) ((resAdd_subset_allVars G D).trans hA)

theorem subset_determined3 (G : System) (U : Finset Var) : U ⊆ Determined3 G U :=
  subset_iterate (subset_resStep G) _ U

/-- Ermine's two-clause closure is contained in the three-clause one. -/
theorem determined_subset_determined3 (G : System) (U : Finset Var) :
    Determined G U ⊆ Determined3 G U :=
  iterate_mono (fun _ => Finset.subset_union_left) (fun _ _ => resStep_mono G) _ U

theorem determined3_mono (G : System) {U V : Finset Var} (h : U ⊆ V) :
    Determined3 G U ⊆ Determined3 G V :=
  iterate_mono_arg (fun _ _ => resStep_mono G) _ h

theorem agree_resStep {G : System} {rho rho' : Assign} {D : Finset Var}
    (hm : SModels rho G) (hm' : SModels rho' G) (hD : AgreeOn rho rho' D) :
    AgreeOn rho rho' (resStep G D) := by
  intro a ha
  rcases Finset.mem_union.mp ha with h | h
  · exact agree_detStep hm hm' hD a h
  · exact agree_resAdd hm hm' hD a h

/-- **The uniqueness theorem survives the third clause.** -/
theorem determined3_unique {G : System} {U : Finset Var} {rho rho' : Assign}
    (hm : SModels rho G) (hm' : SModels rho' G) (hU : AgreeOn rho rho' U) :
    AgreeOn rho rho' (Determined3 G U) :=
  agree_iterate (fun _ h => agree_resStep hm hm' h) _ U hU

/-! ### The instance the measurement asks for -/

namespace NotEq

/-- `modules/Relation/Predicate.e`'s `(!=)`, row constraints only:
`b <- (f, e)`, `a1 <- (e, d)`, `c <- (f, e, d)`, with `a1 = 0`, `b = 1`, `c = 2` universal and
`d = 3`, `e = 4`, `f = 5` existential. -/
def G : System := {⟨1, [5, 4], ∅⟩, ⟨0, [4, 3], ∅⟩, ⟨2, [5, 4, 3], ∅⟩}
def U : Finset Var := {0, 1, 2}

/-- The two-clause closure determines NOTHING here -- this is the flag the instrument raises. -/
theorem two_clause : Determined G U = U := by decide

/-- With resolution, all three existentials are determined. -/
theorem three_clause : Determined3 G U = {0, 1, 2, 3, 4, 5} := by decide

/-- **The measured false positive, and its cure, as one theorem.** -/
theorem res_cures :
    Determined G U = U ∧ Determined3 G U = {0, 1, 2, 3, 4, 5} ∧
      ∀ rho rho' : Assign, SModels rho G → SModels rho' G →
        (∀ v ∈ U, rho v = rho' v) → (rho 3 = rho' 3 ∧ rho 4 = rho' 4 ∧ rho 5 = rho' 5) := by
  refine ⟨two_clause, three_clause, fun rho rho' hm hm' hU => ?_⟩
  have h := determined3_unique hm hm' hU
  rw [three_clause] at h
  exact ⟨h 3 (by decide), h 4 (by decide), h 5 (by decide)⟩

end NotEq

/-! ## 12. Summary

WHAT IS ESTABLISHED.

* `Determined` / `RoseDetermined` are closure operators on `Finset Var` (extensive, monotone,
  idempotent), each the LEAST set containing `U` and closed under its clauses
  (`determined_least`, `roseDetermined_least`), and Ermine's contains Rose's
  (`roseDetermined_subset`) STRICTLY (`RuleFires.rose_lt_det`).
* `determined_unique` -- the whole point.  Determinedness is a genuine functional dependency:
  two models agreeing on `U` agree on `Determined G U`.  The proof needs no fixed-point
  property, only that each clause preserves agreement.
* `determined_splice_not_conservative` and `undetermined_splice_is_conservative` -- the
  candidate guard on `Subst.reduce`'s splice is INDEPENDENT of conservativity in both
  directions.
* `dead_delete_of_pairwise` / `dead_delete_of_le_one_part` -- what deletion IS licensed by;
  `DeadTwoParts.two_parts_not_deletable` and `DeadUndetermined.undetermined_not_deletable` --
  what it is not.
* `RowAmbiguous`, `witness_unique_of_not_rowAmbiguous`, and
  `CriterionIncomplete.sound_not_complete` -- the criterion, its content, and its one-sidedness.
* `resAdd` / `Determined3` / `determined3_unique` -- §13, the clause the R3 MEASUREMENT says is
  missing (the solver's own `resolution`), with the uniqueness theorem re-proved for it and
  `NotEq.res_cures` as the instance: the stdlib `(!=)` residual, which the two-clause closure
  flags and the three-clause closure determines.  Nothing measures how often it fires; that is
  the stage-2 number `R3-DETERMINED.md` §5 asks for.

WHAT IS NOT.

* Nothing here says the closure is CHEAP to compute, nor that the compiler computes it: the
  Scala instrument of stage R3 computes the same two clauses on the residual it sees, and the
  correspondence between the two is an observation about the code, not a theorem.
* Nothing here is an entailment result.  `Determined` is a closure on the syntax of `G`;
  `CriterionIncomplete` is the standing reminder that models can force what syntax cannot see.
* `Holds` reads the published existentials as the CALLEE's choice.  Rose's Definition 14 reads
  them universally.  The two readings are not identified anywhere in this file, and Theorem 15
  is not transferred.
-/

end Rowpartition
