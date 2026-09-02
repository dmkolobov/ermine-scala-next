/-
# Guarding `resolution` with the reverse lookup: what it buys and what it does not

`Cut.lean` §5 localises the obstruction to termination of the cut rule set precisely.
Two minting rules survive the cut and they are not alike:

* `splitConcrete` (`Constraints.scala`, `def splitConcrete`) consults the reverse lookup
  `rhss(RHSAbstr(abstr))` (`Constraints.findRHS`, `Constraints.scala`, `def findRHS`) BEFORE minting,
  so it mints only for a variable group nothing yet names.  `Cut.SplitStep.cands_lt` turns
  that guard into a strictly decreasing measure and `Cut.split_terminates` concludes.
* `resolution` (`Constraints.scala`, `def resolution`) takes no `rhss` argument at all.  It calls
  `fresh` on every matching pair, so one fixed pair of premises admits chains of every
  length (`Cut.resSeed_diverges`) and no `ℕ`-valued measure decreases on every step of the
  cut rule set (`Cut.cut_no_decreasing_measure`).

This file evaluates the obvious repair: give `resolution` the same guard.  The Scala
`resolution` emits, from `v <- (x, C)` and `v <- (y, D)` with `C \ D` and `D \ C` both
nonempty,

```
v <- (z, C ∪ D)      (z fresh)
x <- (z, D \ C)
y <- (z, C \ D)
```

The variable `z` is not *defined* by a bare abstract right-hand side the way
`splitConcrete`'s `u` is, so `Cut.Named` is not the right lookup.  What names `z` is the
FIRST conclusion: `v <- (z, C ∪ D)` says exactly `z = v \ (C ∪ D)`.  So the guard is

  `Resolved G v (C ∪ D)` : `G` already contains `v <- (z', C ∪ D)` for some `z'`,

and when it holds the rule reuses `z'` instead of minting, emitting only the two
conclusions about the lone variables.

## Results

**§1** defines the guard and the guarded rule `GResStep` (constructors `mint` and
`reuse`).

**§2, soundness.**  `reuse_sat`: under the guard the two reuse conclusions are satisfied
by the *same* assignment, so `GResStep.reuse` is pure entailment and does not move the
model set (`res_reuse_entails`, `GResStep.reuse_models_iff`).  `mint_extend` proves the mint
branch a conservative extension in the sense of `Rules.ConservativeExt`, transported to
systems.  Together: `GResStep.satisfiable_iff` and `GResStep.entails_iff` — a guarded run
is equisatisfiable with its input and entails exactly the same constraints over the
input's own vocabulary, so **the guard is not a semantic change**.

`resolvent_unique` is the sharp statement of why the guard loses nothing: any two names
for the same resolvent are forced equal in every model, so the variable the guard declines
to mint would have been *provably identical* to the one it reuses.  `guard_loses_nothing`
packages that: whenever `reuse` fires, the system it produces entails every conclusion the
unguarded rule would have derived, with the reused name in place of the fresh one.

**§3** (`ResGuardTerm.lean`) and **§4** (`ResGuardDiverge.lean`) settle termination.  The
answer is a clean dichotomy and it is stated in `Summary` at the end of `ResGuardTerm`:
the guarded rule terminates on every SATISFIABLE system and does not terminate in general.

## Relation to the rest of the development

`Cut.resResult` is reused verbatim for the mint branch: the guard changes when the rule
fires, not what it emits.  `Rules.rule6` proves the same inference sound on list-shaped
systems; the version here is stated on `Divergence.System` so that it composes with
`Cut`'s step relations.
-/
import Rowpartition.Cut

namespace Rowpartition

/-! ## 1. The guard and the guarded rule -/

/-- **The reverse lookup for `resolution`.**  `Resolved G v K` says `G` already names the
row `v \ K`: it contains a constraint `v <- (z, K)` with a single variable part.  This is
the analogue, for `resolution`, of `Cut.Named` for `splitConcrete` — both are instances of
the Scala `findRHS` reverse lookup (`Constraints.scala`, `def findRHS`), asked a different question.

Quantifying `z` over `allVars G` rather than over all of `Var` costs nothing
(`resolved_iff`) and makes the predicate decidable, which the termination measure of
`ResGuardTerm` needs. -/
def Resolved (G : System) (v : Var) (K : Row) : Prop := ∃ z ∈ allVars G, mk v {z} K ∈ G

instance (G : System) (v : Var) (K : Row) : Decidable (Resolved G v K) :=
  inferInstanceAs (Decidable (∃ z ∈ allVars G, mk v {z} K ∈ G))

/-- Any witness of the lookup is automatically in the vocabulary, so the bounded and
unbounded readings of the guard agree. -/
theorem resolved_iff (G : System) (v : Var) (K : Row) :
    Resolved G v K ↔ ∃ z, mk v {z} K ∈ G := by
  constructor
  · rintro ⟨z, -, hz⟩; exact ⟨z, hz⟩
  · rintro ⟨z, hz⟩
    exact ⟨z, mem_allVars hz (Or.inr (by simp)), hz⟩

theorem resolved_of_mem {G : System} {v z : Var} {K : Row} (h : mk v {z} K ∈ G) :
    Resolved G v K := (resolved_iff G v K).mpr ⟨z, h⟩

theorem Resolved.mono {G G' : System} (hsub : G ⊆ G') {v : Var} {K : Row}
    (h : Resolved G v K) : Resolved G' v K := by
  obtain ⟨z, hz⟩ := (resolved_iff G v K).mp h
  exact resolved_of_mem (hsub hz)

/-- The premises of `resolution`, common to both branches.  `mem₁`/`mem₂` are the two
partitions of the same variable, each with a lone variable part; `tops` and `bots` are the
Scala's guard `if (tops.isEmpty || bots.isEmpty) Set()`. -/
structure ResPair (G : System) (v x y : Var) (C D : Row) : Prop where
  /-- the first premise `v <- (x, C)` is in the system -/
  mem₁ : mk v {x} C ∈ G
  /-- the second premise `v <- (y, D)` is in the system -/
  mem₂ : mk v {y} D ∈ G
  /-- `tops = concr1 -- int` is nonempty -/
  tops : C \ D ≠ ∅
  /-- `bots = concr2 -- int` is nonempty -/
  bots : D \ C ≠ ∅

/-- What the REUSE branch emits: the two conclusions about the lone variables, named by
the resolvent the system already carries.  The first conclusion the mint branch emits,
`v <- (z, C ∪ D)`, is by hypothesis already present. -/
def resReuseResult (G : System) (x y : Var) (C D : Row) (z : Var) : System :=
  insert (mk x {z} (D \ C)) (insert (mk y {z} (C \ D)) G)

theorem subset_resReuseResult (G : System) (x y : Var) (C D : Row) (z : Var) :
    G ⊆ resReuseResult G x y C D z := fun c hc => by
  simp only [resReuseResult, Finset.mem_insert]
  exact Or.inr (Or.inr hc)

/-- **The guarded resolution rule.**  `mint` is `Cut.ResStep` with the guard added;
`reuse` is the branch the guard opens, and it is the one that makes the difference. -/
inductive GResStep : System → System → Prop
  | mint {G : System} {v x y : Var} {C D : Row} {z : Var} :
      ResPair G v x y C D → ¬ Resolved G v (C ∪ D) → z ∉ allVars G →
      GResStep G (resResult G v x y C D z)
  | reuse {G : System} {v x y : Var} {C D : Row} {z : Var} :
      ResPair G v x y C D → mk v {z} (C ∪ D) ∈ G →
      GResStep G (resReuseResult G x y C D z)

theorem GResStep.subset {G G' : System} (h : GResStep G G') : G ⊆ G' := by
  cases h with
  | mint _ _ _ => exact subset_resResult _ _ _ _ _ _ _
  | reuse _ _ => exact subset_resReuseResult _ _ _ _ _ _

/-- **Every guarded mint is an unguarded resolution step.**  The guard restricts when the
rule fires; it does not change what it emits. -/
theorem GResStep.mint_toResStep {G : System} {v x y : Var} {C D : Row} {z : Var}
    (hp : ResPair G v x y C D) (hz : z ∉ allVars G) :
    ResStep G (resResult G v x y C D z) :=
  ResStep.intro ⟨hp.mem₁, hp.mem₂, hp.tops, hp.bots, hz⟩

/-! ## 2. Soundness: the guard is not a semantic change

Everything in this section is about a single step.  The two branches need different
statements, for the same reason `Cut.lean` §2 does: REUSE introduces no variable, so plain
entailment is the right notion, while MINT introduces one, so the right notion is
`Rules.ConservativeExt`. -/

/-- The unfolding of `Sat` for a constraint with exactly one variable part.  Every proof
below is an application of this in both directions. -/
theorem sat_lone_iff (rho : Assign) (v x : Var) (C : Row) :
    Sat rho (mk v {x} C) ↔ rho v = C ∪ rho x ∧ Disjoint C (rho x) := by
  rw [sat_mk_iff]
  constructor
  · rintro ⟨he, hk, -⟩
    exact ⟨by simpa using he, hk x (Finset.mem_singleton_self x)⟩
  · rintro ⟨he, hd⟩
    refine ⟨by simpa using he, ?_, ?_⟩
    · intro w hw
      rw [Finset.mem_singleton] at hw
      exact hw ▸ hd
    · intro w hw u hu hwu
      rw [Finset.mem_singleton] at hw hu
      exact absurd (hw.trans hu.symm) hwu

/-- **The core lemma of the reuse branch.**  If the system already carries the resolvent
`v <- (z, C ∪ D)`, then both conclusions `resolution` would draw about the lone variables
hold under the *same* assignment — no extension, no fresh name.  This is the exact
analogue of `Cut.sat_reduce_of_denotes` for branch (a) of `commonSubexpression`. -/
theorem reuse_sat {rho : Assign} {v x y z : Var} {C D : Row}
    (h₁ : Sat rho (mk v {x} C)) (h₂ : Sat rho (mk v {y} D))
    (hz : Sat rho (mk v {z} (C ∪ D))) :
    Sat rho (mk x {z} (D \ C)) ∧ Sat rho (mk y {z} (C \ D)) := by
  rw [sat_lone_iff] at h₁ h₂ hz
  obtain ⟨he₁, hd₁⟩ := h₁
  obtain ⟨he₂, hd₂⟩ := h₂
  obtain ⟨hez, hdz⟩ := hz
  -- the resolvent is disjoint from both concrete parts
  have hzC : Disjoint C (rho z) := hdz.mono_left Finset.subset_union_left
  have hzD : Disjoint D (rho z) := hdz.mono_left Finset.subset_union_right
  constructor
  · rw [sat_lone_iff]
    refine ⟨?_, hdz.mono_left (Finset.sdiff_subset.trans Finset.subset_union_right)⟩
    ext l
    have e₁ := congrArg (fun s => l ∈ s) he₁
    have ez := congrArg (fun s => l ∈ s) hez
    simp only [Finset.mem_union, Finset.mem_sdiff] at e₁ ez ⊢
    have hCx : l ∈ C → l ∉ rho x := fun h => Finset.disjoint_left.mp hd₁ h
    have hCz : l ∈ C → l ∉ rho z := fun h => Finset.disjoint_left.mp hzC h
    tauto
  · rw [sat_lone_iff]
    refine ⟨?_, hdz.mono_left (Finset.sdiff_subset.trans Finset.subset_union_left)⟩
    ext l
    have e₂ := congrArg (fun s => l ∈ s) he₂
    have ez := congrArg (fun s => l ∈ s) hez
    simp only [Finset.mem_union, Finset.mem_sdiff] at e₂ ez ⊢
    have hDy : l ∈ D → l ∉ rho y := fun h => Finset.disjoint_left.mp hd₂ h
    have hDz : l ∈ D → l ∉ rho z := fun h => Finset.disjoint_left.mp hzD h
    tauto

/-- **Branch REUSE is entailment.**  Both conclusions are semantic consequences of the
system, so the guard's alternative to minting derives nothing new about the models. -/
theorem res_reuse_entails {G : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hr : mk v {z} (C ∪ D) ∈ G) :
    SEntails G (mk x {z} (D \ C)) ∧ SEntails G (mk y {z} (C \ D)) := by
  constructor
  · exact fun rho hm => (reuse_sat (hm _ hp.mem₁) (hm _ hp.mem₂) (hm _ hr)).1
  · exact fun rho hm => (reuse_sat (hm _ hp.mem₁) (hm _ hp.mem₂) (hm _ hr)).2

/-- **The reuse branch does not move the model set at all.**  Not merely
"equisatisfiable": the same assignments model the system before and after. -/
theorem GResStep.reuse_models_iff {G : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hr : mk v {z} (C ∪ D) ∈ G) (rho : Assign) :
    SModels rho (resReuseResult G x y C D z) ↔ SModels rho G := by
  constructor
  · exact SModels.mono (subset_resReuseResult _ _ _ _ _ _)
  · intro hm c hc
    simp only [resReuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact (reuse_sat (hm _ hp.mem₁) (hm _ hp.mem₂) (hm _ hr)).1
    · exact (reuse_sat (hm _ hp.mem₁) (hm _ hp.mem₂) (hm _ hr)).2
    · exact hm c hc

/-! ### The mint branch: a conservative extension -/

/-- The concrete parts of both premises sit inside the partitioned row. -/
theorem conc_subset_of_sat {rho : Assign} {v x : Var} {C : Row}
    (h : Sat rho (mk v {x} C)) : C ⊆ rho v := by
  rw [sat_lone_iff] at h
  rw [h.1]
  exact Finset.subset_union_left

/-- **The mint branch is a conservative extension.**  Every model of the premises extends
to a model of the three conclusions, changing only the fresh variable, whose value is
forced: it is `rho v \ (C ∪ D)`. -/
theorem mint_extend {G : System} {v x y : Var} {C D : Row} {z : Var}
    (hp : ResPair G v x y C D) (hz : z ∉ allVars G) {rho : Assign} (hm : SModels rho G) :
    ∃ rho', SModels rho' (resResult G v x y C D z) ∧ ∀ u ∈ allVars G, rho' u = rho u := by
  have h₁ := hm _ hp.mem₁
  have h₂ := hm _ hp.mem₂
  have hCv : C ⊆ rho v := conc_subset_of_sat h₁
  have hDv : D ⊆ rho v := conc_subset_of_sat h₂
  refine ⟨setVar rho z (rho v \ (C ∪ D)), ?_, ?_⟩
  · -- the three conclusions, then the untouched rest of the system
    have hvz : v ≠ z := fun h => hz (h ▸ lhs_mem_allVars hp.mem₁)
    have hxz : x ≠ z := fun h => hz (h ▸ mem_allVars hp.mem₁ (Or.inr (by simp)))
    have hyz : y ≠ z := fun h => hz (h ▸ mem_allVars hp.mem₂ (Or.inr (by simp)))
    have hv : setVar rho z (rho v \ (C ∪ D)) v = rho v := setVar_of_ne rho _ hvz
    have hx : setVar rho z (rho v \ (C ∪ D)) x = rho x := setVar_of_ne rho _ hxz
    have hy : setVar rho z (rho v \ (C ∪ D)) y = rho y := setVar_of_ne rho _ hyz
    rw [sat_lone_iff] at h₁ h₂
    intro c hc
    simp only [resResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | rfl | hc
    · rw [sat_lone_iff, hv, setVar_self]
      constructor
      · ext l
        simp only [Finset.mem_union, Finset.mem_sdiff]
        have : l ∈ C ∪ D → l ∈ rho v := fun h => by
          rcases Finset.mem_union.mp h with h | h
          · exact hCv h
          · exact hDv h
        tauto
      · rw [Finset.disjoint_right]
        intro l hl
        exact (Finset.mem_sdiff.mp hl).2
    · rw [sat_lone_iff, hx, setVar_self]
      refine ⟨?_, ?_⟩
      · ext l
        have e₁ := congrArg (fun s => l ∈ s) h₁.1
        simp only [Finset.mem_union, Finset.mem_sdiff] at e₁ ⊢
        have hCx : l ∈ C → l ∉ rho x := fun h => Finset.disjoint_left.mp h₁.2 h
        have : l ∈ D → l ∈ rho v := fun h => hDv h
        tauto
      · rw [Finset.disjoint_right]
        intro l hl
        obtain ⟨-, hl2⟩ := Finset.mem_sdiff.mp hl
        intro hlDC
        exact hl2 (Finset.mem_union_right _ (Finset.mem_sdiff.mp hlDC).1)
    · rw [sat_lone_iff, hy, setVar_self]
      refine ⟨?_, ?_⟩
      · ext l
        have e₂ := congrArg (fun s => l ∈ s) h₂.1
        simp only [Finset.mem_union, Finset.mem_sdiff] at e₂ ⊢
        have hDy : l ∈ D → l ∉ rho y := fun h => Finset.disjoint_left.mp h₂.2 h
        have : l ∈ C → l ∈ rho v := fun h => hCv h
        tauto
      · rw [Finset.disjoint_right]
        intro l hl
        obtain ⟨-, hl2⟩ := Finset.mem_sdiff.mp hl
        intro hlCD
        exact hl2 (Finset.mem_union_left _ (Finset.mem_sdiff.mp hlCD).1)
    · exact sModels_setVar hz _ hm c hc
  · intro u hu
    exact setVar_of_ne rho _ (fun h => hz (h ▸ hu))

/-! ### The step, both branches together -/

/-- **A guarded step preserves satisfiability in both directions.** -/
theorem GResStep.satisfiable_iff {G G' : System} (h : GResStep G G') :
    (∃ rho, SModels rho G') ↔ ∃ rho, SModels rho G := by
  constructor
  · rintro ⟨rho, hm⟩
    exact ⟨rho, SModels.mono h.subset hm⟩
  · rintro ⟨rho, hm⟩
    cases h with
    | @mint v x y C D z hp _ hz =>
      obtain ⟨rho', hm', -⟩ := mint_extend hp hz hm
      exact ⟨rho', hm'⟩
    | @reuse v x y C D z hp hr =>
      exact ⟨rho, (GResStep.reuse_models_iff hp hr rho).mpr hm⟩

/-- **A guarded step derives nothing new about the input's own vocabulary.**  For any
constraint that does not mention the freshly minted variable, the successor system entails
it exactly when the predecessor did. -/
theorem GResStep.entails_iff {G G' : System} (h : GResStep G G') {c : Constraint}
    (hc : ∀ u, u = c.lhs ∨ u ∈ vset c → u ∈ allVars G) :
    SEntails G' c ↔ SEntails G c := by
  constructor
  · intro he rho hm
    cases h with
    | @mint v x y C D z hp _ hz =>
      obtain ⟨rho', hm', hagree⟩ := mint_extend hp hz hm
      have := he rho' hm'
      exact (sat_congr_of_agree (fun u hu => (hagree u (hc u hu)).symm)).mpr this
    | @reuse v x y C D z hp hr =>
      exact he rho ((GResStep.reuse_models_iff hp hr rho).mpr hm)
  · exact fun he rho hm => he rho (SModels.mono h.subset hm)

/-! ### Why the guard loses nothing

The reuse branch is not merely *sound*; it is exactly as informative as the mint it
replaces.  The resolvent is functionally determined by the premises, so the variable the
guard declines to mint would have been provably equal to the one it reuses. -/

/-- **The resolvent is unique.**  Two names for `v \ K` denote the same row in every
model.  (No premises are needed: the two constraints alone force it.) -/
theorem resolvent_unique {rho : Assign} {v z z' : Var} {K : Row}
    (h : Sat rho (mk v {z} K)) (h' : Sat rho (mk v {z'} K)) : rho z = rho z' := by
  rw [sat_lone_iff] at h h'
  ext l
  have e := congrArg (fun s => l ∈ s) (h.1.symm.trans h'.1)
  simp only [Finset.mem_union] at e
  have hz : l ∈ K → l ∉ rho z := fun hh => Finset.disjoint_left.mp h.2 hh
  have hz' : l ∈ K → l ∉ rho z' := fun hh => Finset.disjoint_left.mp h'.2 hh
  tauto

/-- **The guard loses nothing.**  When `reuse` fires with the existing name `z`, the
system it produces already entails the conclusion the unguarded rule would have drawn
about the resolvent, and the two conclusions about the lone variables — all three with `z`
in place of the fresh name.  So the only difference between the guarded and the unguarded
rule on this pair of premises is the *name* of a variable that is forced equal either
way. -/
theorem guard_loses_nothing {G : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hr : mk v {z} (C ∪ D) ∈ G) :
    SEntails G (mk v {z} (C ∪ D)) ∧ SEntails G (mk x {z} (D \ C)) ∧
      SEntails G (mk y {z} (C \ D)) :=
  ⟨fun _ hm => hm _ hr, (res_reuse_entails hp hr).1, (res_reuse_entails hp hr).2⟩

/-- …and dually, whenever the guard *fires* the minted name is the unique row it could
have: any variable the system later shows to be a resolvent of `v` at `C ∪ D` denotes the
same row. -/
theorem mint_name_forced {G : System} {v z z' : Var} {K : Row} {rho : Assign}
    (hm : SModels rho G) (h : mk v {z} K ∈ G) (h' : mk v {z'} K ∈ G) : rho z = rho z' :=
  resolvent_unique (hm _ h) (hm _ h')

/-! ### Iterating -/

/-- `GResSteps n G G'`: `G'` is reachable from `G` by exactly `n` guarded steps. -/
inductive GResSteps : ℕ → System → System → Prop
  | refl (G : System) : GResSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      GResSteps n G G' → GResStep G' G'' → GResSteps (n + 1) G G''

theorem GResSteps.subset {n : ℕ} {G G' : System} (h : GResSteps n G G') : G ⊆ G' := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep ih => exact ih.trans hstep.subset

/-- **A guarded run is equisatisfiable with its input.** -/
theorem GResSteps.satisfiable_iff {n : ℕ} {G₀ G : System} (h : GResSteps n G₀ G) :
    (∃ rho, SModels rho G) ↔ ∃ rho, SModels rho G₀ := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep ih => exact hstep.satisfiable_iff.trans ih

/-- **A guarded run entails exactly what its input did**, over the input's own
vocabulary.  Together with `GResSteps.satisfiable_iff` this is the statement that adding
the guard is not a semantic change. -/
theorem GResSteps.entails_iff {n : ℕ} {G₀ G : System} (h : GResSteps n G₀ G)
    {c : Constraint} (hc : ∀ u, u = c.lhs ∨ u ∈ vset c → u ∈ allVars G₀) :
    SEntails G c ↔ SEntails G₀ c := by
  induction h with
  | refl => exact Iff.rfl
  | @tail n G₀ G' G'' hsteps hstep ih =>
    exact (hstep.entails_iff (fun u hu => allVars_mono hsteps.subset (hc u hu))).trans (ih hc)

end Rowpartition
