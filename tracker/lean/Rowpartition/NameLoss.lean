/-
# NameLoss -- `makeConcrete` deletes the name a later `commonSubexpression` needs

The question (tracker/PROMPT-substitution-gap.md): `Ai/HeadcountPlan.labelled` is published
as a concrete row or as a constrained polymorphic type depending on build order alone, and
the polymorphic run receives a redundant partition.  Does the redundant partition CAUSE the
missing derivation?

It does not.  Replaying the exact module-level inputs in a harness (with the original
variable ids) shows the outcome is a function of the VARIABLE IDS ALONE: the same three
partitions pin `t` for 103 of 200 contiguous id bases and fail for the rest, with the
redundant partition present or absent.  The mechanism, read off the step trace and then
confirmed by a causal intervention (keeping the deleted definitions makes every one of 574
id configurations pin -- first behind a flag, now unconditional in `destructiveSub`), is a
RACE inside `Constraints.incorporateAll`:

* `splitConcrete` on `R <- ((|k|), x, y)` mints a NAME `u <- (x, y)` for the pair, plus the
  mention `R <- ((|k|), u)`;
* cancellation of that mention against `R <- ((|k, c|))` makes `u` concrete, `u <- ((|c|))`;
* `makeConcrete`/`destructiveSub` then rewrites every mention of `u` and DELETES every
  definition of `u`.  A definition with ONE abstract part is re-expressed by cancellation
  (`v <- (x, D)`, `v <- C` gives `x <- C \ D`); a definition with TWO OR MORE abstract parts
  has no variable-headed form without `u`, so the name `u` for `x ++ y` is simply gone;
* under the shipped cut (`-Dermine.genRules=cut`) `commonSubexpression` REUSES names and
  never mints.  So `t <- (x, y, z)`, dequeued after the deletion, shares `x ++ y` with
  `R <- ((|k|), x, y)` and finds nothing to fold against; dequeued before it, the reuse fires,
  `t <- (z, u)` is learnt, and the concretisation rewrites it to `t <- ((|c|), z)` -- the fact
  from which resolution and cancellation pin `t`.

Which of the two happens is decided by the priority-queue key, `(graph.sort(lhs),
(rhs.hashCode, lhs.hashCode))` with `V.hashCode = id`: sites (1) and (2) of the ten-site
determinism inventory in `TICKET-row-constraint-decision.md`.  The redundant partition is a
SYMPTOM of the same order-dependence one solve earlier; it is neither necessary nor
sufficient for the loss (removing either copy leaves regime B unpinned, adding one leaves
regime A pinned), and what it does change is the queue -- a fresh variable, two more
partitions, a re-sorted priority map -- i.e. the order.

This file proves the mechanism on the smallest input that exhibits it, three constraints:

    (|k, c|) <- ((|k|), x, y)      (|d|) <- (x, z)      t <- (x, y, z)

which the harness reproduces (`tracker/repro/README.md`): 90 of 200 id bases pinned `t`
under the deleting solver, 200 of 200 with the definitions kept.

## Contents

* §1  `absorbC` / `concretize` / `concretizeKeep`: the Scala concretisation as a function
      on `System`s -- the rewrite of mentions, the deletion of definitions, and the
      repaired variant that keeps the definitions with two or more abstract parts.  Both
      are SOUND (`concretize_sound`, `concretizeKeep_sound`).
* §2  The instance, and `Grace`, the state at which the race is decided: the cut reaches
      it from the input in two steps (`grace_reached`).
* §3  The critical pair.  Fold first, then concretise: `t <- ((|c|), z)` is in the result
      (`orderA_has_fact`).  Concretise first: it is not (`orderB_lacks_fact`), and the
      concretised system is exactly the input plus `u <- ((|c|))` (`orderB_eq`) -- the
      name and its mention have vanished without trace.
* §4  What the concretise-first system still knows.  It ENTAILS `t = (|c, d|)`
      (`orderB_entails_goal`): the loss is derivational, not semantic.  A re-mint of the
      name is ENABLED there (`orderB_remint_enabled`) -- the additive calculus would
      recover; the single-pass loop, which examines each partition once at dequeue, never
      performs it.  With the definition KEPT, two non-generative steps recover the fact
      (`keep_recovers_fact`).
* §5  (`NameLossClosed.lean`) No non-generative step from the concretise-first system ever
      produces the fact or the goal: the eight-constraint saturated set the solver actually
      reaches is closed under `NonGenStep`.
* §6  (`NameLossDerivation.lean`) From the fold-first system, `SatSteps` reach
      `t <- ((|c, d|))`: the derivation the solver finds in the other order.
-/
import Rowpartition.Saturate

namespace Rowpartition
namespace NameLoss

/-- `mk_inj` as an iff, so that `simp` can turn an equation between two `mk`-shaped
constraints into equations between their components -- which `decide` can then settle.
(`decide` cannot see through `mk` itself: `slist` is a `Finset.sort`, which the kernel does
not reduce.) -/
theorem mk_eq_iff {a b : Var} {S T : Finset Var} {k j : Finset Label} :
    mk a S k = mk b T j ↔ a = b ∧ S = T ∧ k = j :=
  ⟨mk_inj, by rintro ⟨rfl, rfl, rfl⟩; rfl⟩

/-! ## 1. The concretisation step -/

/-- `subPartitions`: substitute `u := C` into a constraint that mentions `u` on the right.
A constraint that does not mention `u` is returned unchanged. -/
def absorbC (u : Var) (C : Row) (c : Constraint) : Constraint :=
  if u ∈ vset c then mk c.lhs ((vset c).erase u) (c.conc ∪ C) else c

/-- `makeConcrete` / `destructiveSub` on the branch where `u` has a mention (`srs` nonempty):
every definition of `u` is DROPPED, every constraint is rewritten by `absorbC`, and
`u <- ((|C|))` is kept. -/
def concretize (u : Var) (C : Row) (G : System) : System :=
  insert (mk u ∅ C) ((G.filter (fun c => c.lhs ≠ u)).image (absorbC u C))

/-- The repaired step (`destructiveSub` since 2026-09-02, first behind a flag, now
unconditional): definitions of `u` with two or more abstract parts -- the ones cancellation
cannot re-express -- are kept. -/
def concretizeKeep (u : Var) (C : Row) (G : System) : System :=
  concretize u C G ∪ G.filter (fun c => c.lhs = u ∧ 2 ≤ (vset c).card)

theorem concretize_subset_keep (u : Var) (C : Row) (G : System) :
    concretize u C G ⊆ concretizeKeep u C G :=
  Finset.subset_union_left

/-- Substituting the value of `u` preserves satisfaction. -/
theorem sat_absorbC {rho : Assign} {u : Var} {C : Row} {c : Constraint}
    (hc : Sat rho c) (hu : rho u = C) : Sat rho (absorbC u C c) := by
  unfold absorbC
  split_ifs with hmem
  · rw [sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩
    · have hsplit : (vset c).biUnion rho = rho u ∪ ((vset c).erase u).biUnion rho := by
        conv_lhs => rw [← Finset.insert_erase hmem]
        rw [Finset.biUnion_insert]
      rw [hc.eq_biUnion, hsplit, ← hu, Finset.union_assoc]
    · intro v hv
      have hv' := Finset.mem_of_mem_erase hv
      have hne := Finset.ne_of_mem_erase hv
      exact Finset.disjoint_union_left.mpr
        ⟨hc.disjoint_conc' hv', hu ▸ hc.disjoint_of_ne' hmem hv' (Ne.symm hne)⟩
    · intro v hv w hw hvw
      exact hc.disjoint_of_ne' (Finset.mem_of_mem_erase hv) (Finset.mem_of_mem_erase hw) hvw
  · exact hc

/-- A model of `G` in which `u` denotes `C` models the concretisation. -/
theorem sModels_concretize {rho : Assign} {u : Var} {C : Row} {G : System}
    (hm : SModels rho G) (hu : rho u = C) : SModels rho (concretize u C G) := by
  intro c hc
  unfold concretize at hc
  rcases Finset.mem_insert.mp hc with rfl | hc
  · rw [sat_mk_iff]
    exact ⟨by simp [hu], by simp, by simp⟩
  · obtain ⟨d, hd, rfl⟩ := Finset.mem_image.mp hc
    exact sat_absorbC (hm d (Finset.mem_filter.mp hd).1) hu

/-- The value of a concretely defined variable. -/
theorem denotes_of_conc {rho : Assign} {u : Var} {C : Row} {G : System}
    (hmem : mk u ∅ C ∈ G) (hm : SModels rho G) : rho u = C := by
  have := (hm _ hmem).eq_biUnion
  simpa using this

/-- **`makeConcrete` is sound**: when `u <- ((|C|))` is in the system, every model of the
system models its concretisation.  (The converse fails in general: the deleted definitions
are not recoverable from the residual -- that is this file's subject.) -/
theorem concretize_sound {u : Var} {C : Row} {G : System} (hmem : mk u ∅ C ∈ G) :
    ∀ rho, SModels rho G → SModels rho (concretize u C G) :=
  fun _ hm => sModels_concretize hm (denotes_of_conc hmem hm)

/-- **Keeping the definitions is sound**: they were in the system already. -/
theorem concretizeKeep_sound {u : Var} {C : Row} {G : System} (hmem : mk u ∅ C ∈ G) :
    ∀ rho, SModels rho G → SModels rho (concretizeKeep u C G) := by
  intro rho hm c hc
  rcases Finset.mem_union.mp hc with hc | hc
  · exact concretize_sound hmem rho hm c hc
  · exact hm c (Finset.mem_filter.mp hc).1

/-! ## 2. The instance -/

/-- The published variable. -/
abbrev t : Var := 0
/-- The first variable of the shared pair. -/
abbrev x : Var := 1
/-- The second variable of the shared pair. -/
abbrev y : Var := 2
/-- The variable `t` has and `R` has not. -/
abbrev z : Var := 3
/-- The fresh variable `PQueue.build` mints for the concrete left-hand side `(|k, c|)`. -/
abbrev R : Var := 4
/-- The fresh variable `PQueue.build` mints for the concrete left-hand side `(|d|)`. -/
abbrev D : Var := 5
/-- The name `splitConcrete` mints for `x ++ y`. -/
abbrev u : Var := 6

/-- The field `k`. -/
abbrev fk : Label := 10
/-- The field `c`. -/
abbrev fc : Label := 11
/-- The field `d`. -/
abbrev fd : Label := 12

/-- `R <- ((|k, c|))`. -/
def rConc : Constraint := mk R ∅ {fk, fc}
/-- `R <- ((|k|), x, y)`. -/
def rDef : Constraint := mk R {x, y} {fk}
/-- `D <- ((|d|))`. -/
def dConc : Constraint := mk D ∅ {fd}
/-- `D <- (x, z)`. -/
def dDef : Constraint := mk D {x, z} ∅
/-- `t <- (x, y, z)`. -/
def tDef : Constraint := mk t {x, y, z} ∅

/-- The input: the five partitions `PQueue.build` produces from the three constraints. -/
def G₀ : System := {rConc, rDef, dConc, dDef, tDef}

/-- `u <- (x, y)`: the NAME `splitConcrete` mints. -/
def uName : Constraint := mk u {x, y} ∅
/-- `R <- ((|k|), u)`: the mention that comes with it. -/
def rSplit : Constraint := mk R {u} {fk}
/-- `u <- ((|c|))`: cancellation of the mention against `R <- ((|k, c|))`. -/
def uConc : Constraint := mk u ∅ {fc}

/-- The state at which the race is decided: the input, the name, its mention, and the
concrete value of the name.  Two rules are enabled: the concretisation of `u`, and the
common-subexpression fold of `t <- (x, y, z)` against the name. -/
def Grace : System := insert uConc (insert uName (insert rSplit G₀))

/-- `t <- (z, u)`: what the fold learns. -/
def tReuse : Constraint := mk t {z, u} ∅
/-- `t <- ((|c|), z)`: the fact the name carries, once `u` is concretised. -/
def tFact : Constraint := mk t {z} {fc}
/-- `t <- ((|c, d|))`: the goal -- `t` pinned. -/
def tGoal : Constraint := mk t ∅ {fc, fd}
/-- `t <- (y, D)`: the fold of `D <- (x, z)` into `t <- (x, y, z)` -- learnt in BOTH orders,
because the name `D` is an input variable that nothing ever concretises away. -/
def tFold : Constraint := mk t {y, D} ∅
/-- `t <- ((|d|), y)`: substitution of `D <- ((|d|))` into the fold. -/
def tD : Constraint := mk t {y} {fd}

/-- The closed-term recipe used throughout: unfold the instance and the rule results down
to `mk`-shaped constraints over literal finsets, split every `mk = mk` into component
equations, and let `decide` settle what is left.  (`decide` cannot see through `mk`
itself -- `slist` is a `Finset.sort`, which the kernel does not reduce -- so every `mk`
must be gone by the time it runs.) -/
macro "nl_decide" : tactic => `(tactic|
  ((try simp [t, x, y, z, R, D, u, fk, fc, fd, G₀, rConc, rDef, dConc, dDef, tDef, uName,
      rSplit, uConc, tReuse, tFact, tGoal, tFold, tD, absorbC, reduce, shared, Named, Names, allVars,
      mk_eq_iff, vset_mk, conc_mk, lhs_mk, Finset.subset_iff])
   <;> decide))

theorem rDef_mem : rDef ∈ G₀ := by simp [G₀]
theorem rConc_mem : rConc ∈ G₀ := by simp [G₀]

/-- The split mints the name: `SplitApp` holds on the input. -/
theorem split_app : SplitApp G₀ rDef u :=
  ⟨rDef_mem, by nl_decide, by nl_decide, by nl_decide, by nl_decide⟩

theorem split_eq : splitResult G₀ rDef u = insert uName (insert rSplit G₀) := by
  simp only [splitResult, uName, rSplit, rDef, vset_mk, lhs_mk, conc_mk]

/-- The cancellation of the mention against the concrete row. -/
theorem cancel_app : CancelApp (splitResult G₀ rDef u) rSplit rConc u :=
  ⟨by simp [split_eq], by simp [split_eq, rConc_mem], rfl, by nl_decide, by nl_decide⟩

theorem cancel_eq : mk u (vset rConc \ vset rSplit) (rConc.conc \ rSplit.conc) = uConc := by
  nl_decide

theorem grace_eq : cancelResult (splitResult G₀ rDef u) rSplit rConc u = Grace := by
  rw [cancelResult, cancel_eq, split_eq]; rfl

/-- **The cut reaches the race state from the input in two steps.** -/
theorem grace_reached : CutRuleSteps 2 G₀ Grace := by
  have h1 : CutRuleStep G₀ (splitResult G₀ rDef u) :=
    CutRuleStep.mint (SplitStep.intro split_app)
  have h2 : CutRuleStep (splitResult G₀ rDef u) Grace := by
    rw [← grace_eq]
    exact CutRuleStep.nongen (NonGenStep.cancel (CancelStep.intro cancel_app))
  exact CutRuleSteps.tail (CutRuleSteps.tail (CutRuleSteps.refl _) h1) h2

theorem G₀_subset_grace : G₀ ⊆ Grace :=
  (Finset.subset_insert _ _).trans ((Finset.subset_insert _ _).trans (Finset.subset_insert _ _))

theorem uName_mem_grace : uName ∈ Grace := by simp [Grace]
theorem uConc_mem_grace : uConc ∈ Grace := by simp [Grace]
theorem tDef_mem_grace : tDef ∈ Grace := G₀_subset_grace (by simp [G₀])

/-! ## 3. The critical pair -/

/-- The fold is enabled at `Grace`: `t <- (x, y, z)` against the name `u <- (x, y)`. -/
theorem fold_app : CsePair Grace uName tDef :=
  ⟨uName_mem_grace, tDef_mem_grace, by nl_decide, by nl_decide⟩

theorem fold_step : CutStep Grace (foldResult Grace uName tDef) :=
  CutStep.fold fold_app (by nl_decide) rfl

theorem reduce_eq : reduce tDef (shared uName tDef) uName.lhs = tReuse := by nl_decide

theorem fold_eq : foldResult Grace uName tDef = insert tReuse Grace := by
  rw [foldResult, reduce_eq]

/-- The concretisation is enabled at `Grace`: `u <- ((|c|))` is in it (and stays in the fold
result). -/
theorem uConc_mem_fold : uConc ∈ foldResult Grace uName tDef := by
  rw [fold_eq]; exact Finset.mem_insert_of_mem uConc_mem_grace

/-- **Order A -- fold, then concretise: the fact survives.** -/
theorem orderA_has_fact : tFact ∈ concretize u {fc} (foldResult Grace uName tDef) := by
  rw [fold_eq]
  exact Finset.mem_insert_of_mem (Finset.mem_image.mpr
    ⟨tReuse, Finset.mem_filter.mpr ⟨Finset.mem_insert_self _ _, by nl_decide⟩, by nl_decide⟩)

/-- Everything the concretise-first system contains is the input or `u <- ((|c|))`. -/
theorem orderB_subset : concretize u {fc} Grace ⊆ insert uConc G₀ := by
  intro c hc
  rcases Finset.mem_insert.mp hc with rfl | hc
  · exact Finset.mem_insert_self _ _
  · obtain ⟨d, hd, rfl⟩ := Finset.mem_image.mp hc
    obtain ⟨hdG, hdu⟩ := Finset.mem_filter.mp hd
    simp only [Grace, G₀, Finset.mem_insert, Finset.mem_singleton] at hdG
    revert hdu
    rcases hdG with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> nl_decide

/-- ... and conversely, the input survives the concretisation untouched. -/
theorem G₀_subset_orderB : G₀ ⊆ concretize u {fc} Grace := by
  intro c hc
  have hcG : c ∈ Grace := G₀_subset_grace hc
  apply Finset.mem_insert_of_mem
  simp only [G₀, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl | rfl | rfl <;>
    exact Finset.mem_image.mpr ⟨_, Finset.mem_filter.mpr ⟨hcG, by nl_decide⟩, by nl_decide⟩

/-- **Order B -- concretise first: the fact is not there ...** -/
theorem orderB_lacks_fact : tFact ∉ concretize u {fc} Grace := by
  intro h
  have := orderB_subset h
  revert this
  nl_decide

/-- **... and neither is anything else that could carry it**: the concretised system is
exactly the input plus `u <- ((|c|))`.  The name `u <- (x, y)` and its mention
`R <- ((|k|), u)` are gone; the mention was rewritten to `R <- ((|k, c|))`, which was already
there. -/
theorem orderB_eq : concretize u {fc} Grace = insert uConc G₀ :=
  Finset.Subset.antisymm orderB_subset
    (Finset.insert_subset_iff.mpr ⟨Finset.mem_insert_self _ _, G₀_subset_orderB⟩)

/-! ## 4. What the concretise-first system still knows -/

/-- `x` is empty in every model of the input: it lies under both `(|c|)` and `(|d|)`. -/
theorem x_empty {rho : Assign} (hm : SModels rho G₀) : rho x = ∅ := by
  have hR : rho R = {fk, fc} := denotes_of_conc (by simp [G₀, rConc]) hm
  have hD : rho D = {fd} := denotes_of_conc (by simp [G₀, dConc]) hm
  have h1 := (hm rDef (by simp [G₀])).eq_biUnion
  have h2 := (hm dDef (by simp [G₀])).eq_biUnion
  simp only [rDef, dDef, vset_mk, conc_mk, lhs_mk, Finset.biUnion_insert,
    Finset.singleton_biUnion, Finset.empty_union] at h1 h2
  rw [hR] at h1
  rw [hD] at h2
  ext l
  constructor
  · intro hl
    have hc : l ∈ ({fk, fc} : Row) := by rw [h1]; simp [hl]
    have hd : l ∈ ({fd} : Row) := by rw [h2]; simp [hl]
    simp only [Finset.mem_insert, Finset.mem_singleton, fk, fc, fd] at hc hd
    subst hd
    simp at hc
  · intro hl; simp at hl

/-- **The input entails the goal**: `t = (|c, d|)` in every model. -/
theorem G₀_entails_goal : SEntails G₀ tGoal := by
  intro rho hm
  have hR : rho R = {fk, fc} := denotes_of_conc (by simp [G₀, rConc]) hm
  have hD : rho D = {fd} := denotes_of_conc (by simp [G₀, dConc]) hm
  have hx := x_empty hm
  have h1 := (hm rDef (by simp [G₀])).eq_biUnion
  have h2 := (hm dDef (by simp [G₀])).eq_biUnion
  have h3 := (hm tDef (by simp [G₀])).eq_biUnion
  have hk : Disjoint ({fk} : Row) (rho y) :=
    (hm rDef (by simp [G₀])).disjoint_conc' (by simp [rDef])
  simp only [rDef, dDef, tDef, vset_mk, conc_mk, lhs_mk, Finset.biUnion_insert,
    Finset.singleton_biUnion, Finset.empty_union] at h1 h2 h3
  rw [hR, hx, Finset.empty_union] at h1
  rw [hD, hx, Finset.empty_union] at h2
  rw [hx, Finset.empty_union] at h3
  have hy : rho y = {fc} := by
    ext l
    constructor
    · intro hl
      have hmem : l ∈ ({fk, fc} : Row) := by rw [h1]; simp [hl]
      simp only [Finset.mem_insert, Finset.mem_singleton] at hmem
      rcases hmem with rfl | rfl
      · exact absurd hl (Finset.disjoint_left.mp hk (by simp))
      · simp
    · intro hl
      simp only [Finset.mem_singleton] at hl
      subst hl
      have : fc ∈ ({fk} : Row) ∪ rho y := by rw [← h1]; simp
      simp only [Finset.mem_union, Finset.mem_singleton, fk, fc] at this
      rcases this with h | h
      · exact absurd h (by decide)
      · exact h
  rw [tGoal, sat_mk_iff]
  refine ⟨?_, by simp, by simp⟩
  rw [h3, hy, ← h2]
  simp only [Finset.biUnion_empty, Finset.union_empty]
  decide

/-- **The concretise-first system entails the goal too**: the loss is derivational, not
semantic -- the concretised system still contains `R <- ((|k|), x, y)` and
`R <- ((|k, c|))`, which say `x ++ y = (|c|)` without naming the pair. -/
theorem orderB_entails_goal : SEntails (concretize u {fc} Grace) tGoal :=
  fun rho hm => G₀_entails_goal rho (SModels.mono G₀_subset_orderB hm)

/-- **A re-mint is enabled at the concretise-first system**: `R <- ((|k|), x, y)` is there,
its pair is unnamed again, and `splitConcrete` WOULD mint a new name for it -- if the rule
ever ran on that partition again.  `incorporateAll` examines each partition once, when it is
dequeued; `R <- ((|k|), x, y)` was dequeued before the deletion, and nothing re-enqueues
it.  This is the precise sense in which the loop's single pass, not the rule set, loses the
derivation. -/
theorem orderB_remint_enabled : SplitApp (concretize u {fc} Grace) rDef 9 := by
  rw [orderB_eq]
  exact ⟨Finset.mem_insert_of_mem rDef_mem, by nl_decide, by nl_decide, by nl_decide,
    by nl_decide⟩

/-! ### With the definition kept -/

theorem keep_has_name : uName ∈ concretizeKeep u {fc} Grace :=
  Finset.mem_union_right _ (Finset.mem_filter.mpr ⟨uName_mem_grace, by nl_decide⟩)

theorem keep_has_tDef : tDef ∈ concretizeKeep u {fc} Grace :=
  Finset.mem_union_left _ (G₀_subset_orderB (by simp [G₀]))

theorem keep_has_uConc : uConc ∈ concretizeKeep u {fc} Grace :=
  Finset.mem_union_left _ (Finset.mem_insert_self _ _)

theorem keep_fold_app : CsePair (concretizeKeep u {fc} Grace) uName tDef :=
  ⟨keep_has_name, keep_has_tDef, by nl_decide, by nl_decide⟩

theorem keep_fold_eq :
    foldResult (concretizeKeep u {fc} Grace) uName tDef =
      insert tReuse (concretizeKeep u {fc} Grace) := by
  rw [foldResult, reduce_eq]

theorem keep_subst_app :
    SubstApp (insert tReuse (concretizeKeep u {fc} Grace)) tReuse uConc :=
  ⟨Finset.mem_insert_self _ _, Finset.mem_insert_of_mem keep_has_uConc, by nl_decide⟩

theorem subst_eq :
    mk tReuse.lhs ((vset tReuse).erase uConc.lhs ∪ vset uConc) (tReuse.conc ∪ uConc.conc) =
      tFact := by nl_decide

theorem keep_subst_eq :
    substResult (insert tReuse (concretizeKeep u {fc} Grace)) tReuse uConc =
      insert tFact (insert tReuse (concretizeKeep u {fc} Grace)) := by
  rw [substResult, subst_eq]

/-- **With the definition kept, two non-generative steps recover the fact.** -/
theorem keep_recovers_fact :
    NonGenSteps 2 (concretizeKeep u {fc} Grace)
      (insert tFact (insert tReuse (concretizeKeep u {fc} Grace))) := by
  have h1 : NonGenStep (concretizeKeep u {fc} Grace)
      (insert tReuse (concretizeKeep u {fc} Grace)) := by
    rw [← keep_fold_eq]
    exact NonGenStep.cse (CutStep.fold keep_fold_app (by nl_decide) rfl)
  have h2 : NonGenStep (insert tReuse (concretizeKeep u {fc} Grace))
      (insert tFact (insert tReuse (concretizeKeep u {fc} Grace))) := by
    rw [← keep_subst_eq]
    exact NonGenStep.subst (SubstStep.intro keep_subst_app)
  exact NonGenSteps.tail (NonGenSteps.tail (NonGenSteps.refl _) h1) h2

end NameLoss
end Rowpartition
