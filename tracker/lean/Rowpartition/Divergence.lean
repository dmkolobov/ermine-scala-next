/-
# Why the row-partition solver diverges: a structural account

The Ermine constraint solver (`Constraints.scala`) blows up on inputs that look small.
Measured on the real compiler:

* **Family A** -- `N` left-nested `join`s in one unannotated definition.  Each `join`
  contributes `a <- (d, e)`, `b <- (e, f)`, `c <- (d, e, f)`.  Solve times
  `N = 4 : 0.03 s`, `5 : 0.13 s`, `6 : 0.79 s`, `7 : 10.94 s`, `8 : killed at > 138 s`.
  The successive ratios are `4.3x`, `6.1x`, `13.8x` -- the ratio itself grows.
* **Family B**, the *co-star*: `m` constraints
  `x_i <- (b_0, .., b_{m-1} minus b_i)`.  Times `m = 4 : 0.03 s`, `5 : 0.09 s`,
  `6 : 0.68 s`, `7 : 6.38 s`.
* In BOTH families the retained residual is EXACTLY the input, verbatim.  The entire
  search is discarded work.

This file replaces those measurements with theorems.  The hot rule, per profiling, is
`commonSubexpression`:

```
a <- C* E* x++ y*
b <- D* E* x++ z*
-----------------
 w <- x++          (w fresh)
 a <- C* E* w y*
 b <- D* E* w z*
```

fired whenever two constraints with DIFFERENT left-hand sides share at least two
right-hand variables (`int.size >= 2` in the source), and ADDING its conclusions to the
working set.

## What is proved

1. `CseStep`, the rule as a monotone step relation on finite constraint systems, with a
   genuinely fresh name (section 3).
2. **Conservativity** (section 4).  `CseStep.extend`: every model of the premises extends
   to a model of the conclusion, changing only the fresh variable.  Hence
   `CseSteps.entails_iff` / `coStar_residual`: for every system reachable from `G0` by any
   number of steps and every constraint over `G0`'s own vocabulary, the reachable system
   entails it iff `G0` already did.  Nothing the search generates is a new constraint on
   the user's variables -- the input is already a complete residual.  This is the
   design-relevant result: it says the search is not merely slow, it is *pointless* on
   these inputs.
3. **An exponential lower bound on the saturated set** (section 5).  `coStar_card_lower`:
   any system that contains the `m`-constraint co-star system and is closed under
   common-subexpression naming has at least `2 ^ m - m - 2` constraints.  The proof
   builds the whole intersection lattice of the co-star right-hand sides by induction on
   the number of deleted base variables.
4. **No decreasing measure** (section 6).  All three standard syntactic termination
   measures -- constraint count, total variable occurrences, and the multiset of
   right-hand-side sizes -- strictly INCREASE on every step (`cseStep_measures_increase`).
   Much more strongly, `no_decreasing_measure`: there is NO measure into `Nat` that
   decreases on every rule application, because with genuinely fresh names one applicable
   pair of premises can be re-used forever (`seed_diverges`).  A single `join` call
   already contains such a pair (`joinTriple_diverges`), which is why Family A diverges
   too.
5. The co-star system is satisfiable (`coStar_satisfiable`), so the solver's correct
   answer on it is "satisfiable, residual = input" -- reached, per (3), only after
   `2 ^ m`-sized work.

## Two idealisations, stated honestly

* Section 5 assumes CANONICAL naming: the fresh variable for a shared row is a function
  `nm` of the row (perfect hash-consing, which the implementation approximates with its
  `rhss` reverse lookup).  This is the solver's BEST case; the bound says even perfect
  sharing does not avoid the blow-up.  With genuinely fresh names the set is at least as
  large, but proving that needs bookkeeping this file does not do (see the notes at the
  end of section 5).
* `CseClosed` is a *fixpoint* condition; it does not assert that the fixpoint is reached.
  The dichotomy is nevertheless complete: either the solver saturates, and then section 5
  bounds it below by `2 ^ m - m - 2`, or it does not, and then section 6 says no
  `Nat`-valued measure can certify that it ever will.

## What is NOT here

* The other generative rules (`resolution`, `cancellation`, `substitution`,
  `disjunction`).  Only `commonSubexpression` is modelled, because only it is named by
  the profiler.  Adding rules can only make a saturated set larger, so the lower bound of
  section 5 survives; the conservativity theorem of section 4 does NOT automatically
  survive and would have to be redone per rule.
* Family A is not modelled constraint-by-constraint; section 7 only shows that one
  `join` call contains a divergent seed.
* Any upper bound: nothing here says the saturation is *only* exponential.
-/
import Rowpartition.Basic
import Mathlib.Data.Finset.Card
import Mathlib.Data.Finset.Powerset
import Mathlib.Data.Finset.Lattice.Fold
import Mathlib.Data.Finset.Sort
import Mathlib.Logic.Equiv.Finset
import Mathlib.Algebra.Order.BigOperators.Group.Finset

namespace Rowpartition

/-! ## 1. Constraints with a set-shaped right-hand side

`Constraint.vars` is a list, but the solver manipulates `Set[TypeVar]`.  This section
gives the set view and the workhorse unfolding lemma `sat_mk_iff`. -/

/-- The set of variables occurring on the right of a constraint. -/
def vset (c : Constraint) : Finset Var := c.vars.toFinset

/-- A canonical duplicate-free listing of a finite variable set. -/
def slist (S : Finset Var) : List Var := S.sort (· ≤ ·)

@[simp] theorem mem_slist {S : Finset Var} {v : Var} : v ∈ slist S ↔ v ∈ S :=
  Finset.mem_sort _

@[simp] theorem slist_toFinset (S : Finset Var) : (slist S).toFinset = S :=
  Finset.sort_toFinset _ _

theorem slist_nodup (S : Finset Var) : (slist S).Nodup := Finset.sort_nodup _ _

/-- Canonical constraint with a *set* right-hand side. -/
def mk (a : Var) (S : Finset Var) (k : Finset Label) : Constraint := ⟨a, slist S, k⟩

@[simp] theorem vset_mk (a : Var) (S : Finset Var) (k : Finset Label) :
    vset (mk a S k) = S := slist_toFinset S

@[simp] theorem lhs_mk (a : Var) (S : Finset Var) (k : Finset Label) : (mk a S k).lhs = a := rfl
@[simp] theorem conc_mk (a : Var) (S : Finset Var) (k : Finset Label) : (mk a S k).conc = k := rfl

theorem mk_inj {a b : Var} {S T : Finset Var} {k j : Finset Label}
    (h : mk a S k = mk b T j) : a = b ∧ S = T ∧ k = j :=
  ⟨congrArg Constraint.lhs h, by simpa using congrArg vset h, congrArg Constraint.conc h⟩

theorem foldr_union_map (rho : Assign) (L : List Var) :
    (L.map rho).foldr (· ∪ ·) ∅ = L.toFinset.biUnion rho := by
  ext l
  rw [mem_foldr_union]
  simp

theorem Sat.eq_biUnion {rho : Assign} {c : Constraint} (h : Sat rho c) :
    rho c.lhs = c.conc ∪ (vset c).biUnion rho := by
  have := h.eq_union
  rwa [parts, List.foldr_cons, foldr_union_map] at this

theorem Sat.disjoint_conc' {rho : Assign} {c : Constraint} (h : Sat rho c) {v : Var}
    (hv : v ∈ vset c) : Disjoint c.conc (rho v) :=
  h.disjoint_conc (List.mem_toFinset.mp hv)

theorem Sat.disjoint_of_ne' {rho : Assign} {c : Constraint} (h : Sat rho c) {v w : Var}
    (hv : v ∈ vset c) (hw : w ∈ vset c) (hvw : v ≠ w) : Disjoint (rho v) (rho w) :=
  h.disjoint_of_ne (List.mem_toFinset.mp hv) (List.mem_toFinset.mp hw) hvw

theorem sat_mk_iff (rho : Assign) (a : Var) (S : Finset Var) (k : Finset Label) :
    Sat rho (mk a S k) ↔
      rho a = k ∪ S.biUnion rho ∧
      (∀ v ∈ S, Disjoint k (rho v)) ∧
      (∀ v ∈ S, ∀ w ∈ S, v ≠ w → Disjoint (rho v) (rho w)) := by
  constructor
  · intro h
    exact ⟨by simpa using h.eq_biUnion, fun v hv => h.disjoint_conc' (by simpa using hv),
      fun v hv w hw hvw => h.disjoint_of_ne' (by simpa using hv) (by simpa using hw) hvw⟩
  · rintro ⟨he, hk, hd⟩
    constructor
    · simpa [mk, parts, foldr_union_map] using he
    · simp only [parts, mk, List.pairwise_cons]
      refine ⟨fun s hs => ?_, ?_⟩
      · obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
        exact hk v (mem_slist.mp hv)
      · rw [List.pairwise_map]
        exact (slist_nodup S).pairwise_of_forall_ne
          fun v hv w hw hvw => hd v (mem_slist.mp hv) w (mem_slist.mp hw) hvw

/-- `Sat` only depends on the assignment at the variables the constraint mentions. -/
theorem sat_congr_of_agree {rho rho' : Assign} {c : Constraint}
    (h : ∀ v, v = c.lhs ∨ v ∈ vset c → rho v = rho' v) : Sat rho c ↔ Sat rho' c := by
  have hp : parts rho c = parts rho' c := by
    simp only [parts, List.cons.injEq, true_and]
    exact List.map_congr_left fun v hv => h v (Or.inr (List.mem_toFinset.mpr hv))
  simp only [Sat, hp, h c.lhs (Or.inl rfl)]

/-! ## 2. Constraint systems as finite sets -/

/-- A constraint system: a finite set of partition constraints. -/
abbrev System := Finset Constraint

/-- `rho` models every constraint of the system. -/
def SModels (rho : Assign) (G : System) : Prop := ∀ c ∈ G, Sat rho c

/-- Semantic entailment for systems-as-finsets. -/
def SEntails (G : System) (c : Constraint) : Prop := ∀ rho, SModels rho G → Sat rho c

theorem sModels_iff_models (rho : Assign) (G : System) :
    SModels rho G ↔ Models rho G.toList := by
  simp only [SModels, Models, Finset.mem_toList]

theorem sEntails_iff_entails (G : System) (c : Constraint) :
    SEntails G c ↔ Entails G.toList c := by
  simp only [SEntails, Entails, sModels_iff_models]

theorem SModels.mono {rho : Assign} {G G' : System} (hsub : G ⊆ G') (h : SModels rho G') :
    SModels rho G := fun c hc => h c (hsub hc)

/-- Every variable mentioned anywhere in the system. -/
def allVars (G : System) : Finset Var := G.biUnion (fun c => insert c.lhs (vset c))

theorem mem_allVars {G : System} {c : Constraint} (hc : c ∈ G) {v : Var}
    (hv : v = c.lhs ∨ v ∈ vset c) : v ∈ allVars G :=
  Finset.mem_biUnion.mpr ⟨c, hc, by
    rcases hv with rfl | hv
    · exact Finset.mem_insert_self _ _
    · exact Finset.mem_insert_of_mem hv⟩

theorem lhs_mem_allVars {G : System} {c : Constraint} (hc : c ∈ G) : c.lhs ∈ allVars G :=
  mem_allVars hc (Or.inl rfl)

theorem vset_subset_allVars {G : System} {c : Constraint} (hc : c ∈ G) :
    vset c ⊆ allVars G := fun _ hv => mem_allVars hc (Or.inr hv)

theorem allVars_mono {G G' : System} (h : G ⊆ G') : allVars G ⊆ allVars G' :=
  Finset.biUnion_subset_biUnion_of_subset_left _ h

/-- Pointwise update of an assignment. -/
def setVar (rho : Assign) (z : Var) (r : Row) : Assign := fun v => if v = z then r else rho v

@[simp] theorem setVar_self (rho : Assign) (z : Var) (r : Row) : setVar rho z r z = r := by
  simp [setVar]

theorem setVar_of_ne (rho : Assign) {z v : Var} (r : Row) (h : v ≠ z) :
    setVar rho z r v = rho v := by
  simp [setVar, h]

/-- Updating at a variable the system does not mention leaves all its models intact. -/
theorem sModels_setVar {rho : Assign} {G : System} {z : Var} (hz : z ∉ allVars G) (r : Row)
    (h : SModels rho G) : SModels (setVar rho z r) G := by
  intro c hc
  refine (sat_congr_of_agree (rho := rho) (rho' := setVar rho z r) ?_).mp (h c hc)
  intro v hv
  refine (setVar_of_ne rho r ?_).symm
  rintro rfl
  exact hz (mem_allVars hc hv)

/-! ## 3. The common-subexpression rule

The Scala implementation (`Constraints.scala`, `commonSubexpression`) fires on two
constraints with DIFFERENT left-hand sides whose right-hand variable sets share at
least two variables:

```
a <- C* E* x++ y*
b <- D* E* x++ z*
-----------------
 w <- x++          (w fresh)
 a <- C* E* w y*
 b <- D* E* w z*
```

Here `x++` is the whole intersection of the two variable sets, and the guard is
`int.size >= 2`.  The generated constraints are ADDED to the working set; nothing is
thrown away, which is why a "step" below is monotone. -/

/-- The shared sub-row of two constraints: the intersection of their variable sets. -/
def shared (c₁ c₂ : Constraint) : Finset Var := vset c₁ ∩ vset c₂

/-- A constraint with its shared part replaced by the single variable `z`. -/
def reduce (c : Constraint) (S : Finset Var) (z : Var) : Constraint :=
  mk c.lhs (insert z (vset c \ S)) c.conc

/-- The three constraints the rule emits, added to the working set. -/
def cseResult (G : System) (c₁ c₂ : Constraint) (z : Var) : System :=
  insert (mk z (shared c₁ c₂) ∅)
    (insert (reduce c₁ (shared c₁ c₂) z) (insert (reduce c₂ (shared c₁ c₂) z) G))

/-- The side conditions under which the rule fires, with `z` genuinely fresh. -/
structure CseApp (G : System) (c₁ c₂ : Constraint) (z : Var) : Prop where
  /-- the first premise is in the system -/
  mem₁ : c₁ ∈ G
  /-- the second premise is in the system -/
  mem₂ : c₂ ∈ G
  /-- the rule fires only across DIFFERENT left-hand sides -/
  lhs_ne : c₁.lhs ≠ c₂.lhs
  /-- the guard `int.size >= 2` -/
  two_le : 2 ≤ (shared c₁ c₂).card
  /-- `z` is a genuinely fresh variable -/
  fresh : z ∉ allVars G

/-- One application of the common-subexpression rule. -/
inductive CseStep : System → System → Prop
  | intro {G : System} {c₁ c₂ : Constraint} {z : Var} :
      CseApp G c₁ c₂ z → CseStep G (cseResult G c₁ c₂ z)

theorem subset_cseResult (G : System) (c₁ c₂ : Constraint) (z : Var) :
    G ⊆ cseResult G c₁ c₂ z := by
  intro c hc
  simp only [cseResult, Finset.mem_insert]
  exact Or.inr (Or.inr (Or.inr hc))

theorem CseStep.subset {G G' : System} (h : CseStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact subset_cseResult _ _ _ _

theorem shared_subset_left (c₁ c₂ : Constraint) : shared c₁ c₂ ⊆ vset c₁ :=
  Finset.inter_subset_left

theorem shared_subset_right (c₁ c₂ : Constraint) : shared c₁ c₂ ⊆ vset c₂ :=
  Finset.inter_subset_right

/-! ## 4. Conservativity: the generated constraints say nothing new -/

theorem disjoint_biUnion_left' {rho : Assign} {S : Finset Var} {t : Row}
    (h : ∀ v ∈ S, Disjoint (rho v) t) : Disjoint (S.biUnion rho) t := by
  rw [Finset.disjoint_left]
  intro l hl hlt
  obtain ⟨v, hv, hlv⟩ := Finset.mem_biUnion.mp hl
  exact Finset.disjoint_left.mp (h v hv) hlv hlt

theorem disjoint_biUnion_right' {rho : Assign} {S : Finset Var} {t : Row}
    (h : ∀ v ∈ S, Disjoint t (rho v)) : Disjoint t (S.biUnion rho) :=
  (disjoint_biUnion_left' fun v hv => (h v hv).symm).symm

theorem biUnion_split (rho : Assign) {S T : Finset Var} (hST : S ⊆ T) :
    S.biUnion rho ∪ (T \ S).biUnion rho = T.biUnion rho := by
  ext l
  simp only [Finset.mem_union, Finset.mem_biUnion, Finset.mem_sdiff]
  constructor
  · rintro (⟨v, hv, hl⟩ | ⟨v, ⟨hv, -⟩, hl⟩)
    · exact ⟨v, hST hv, hl⟩
    · exact ⟨v, hv, hl⟩
  · rintro ⟨v, hv, hl⟩
    by_cases hs : v ∈ S
    · exact Or.inl ⟨v, hs, hl⟩
    · exact Or.inr ⟨v, ⟨hv, hs⟩, hl⟩

/-- The fresh name really does denote the shared sub-row: `w <- x++` is satisfied by the
extended assignment. -/
theorem sat_name {rho : Assign} {c : Constraint} {S : Finset Var} {z : Var}
    (hc : Sat rho c) (hS : S ⊆ vset c) (hz : z ∉ vset c) :
    Sat (setVar rho z (S.biUnion rho)) (mk z S ∅) := by
  have hagree : ∀ v ∈ S, setVar rho z (S.biUnion rho) v = rho v := fun v hv =>
    setVar_of_ne rho _ (fun h => hz (h ▸ hS hv))
  rw [sat_mk_iff]
  refine ⟨?_, fun v _ => by simp, fun v hv w hw hvw => ?_⟩
  · rw [setVar_self, Finset.empty_union, Finset.biUnion_congr rfl hagree]
  · rw [hagree v hv, hagree w hw]
    exact hc.disjoint_of_ne' (hS hv) (hS hw) hvw

/-- The rewritten premise `a <- C* E* w y*` is satisfied by the extended assignment. -/
theorem sat_reduce {rho : Assign} {c : Constraint} {S : Finset Var} {z : Var}
    (hc : Sat rho c) (hS : S ⊆ vset c) (hz : z ∉ vset c) (hzl : z ≠ c.lhs) :
    Sat (setVar rho z (S.biUnion rho)) (reduce c S z) := by
  have hagree : ∀ v ∈ vset c, setVar rho z (S.biUnion rho) v = rho v := fun v hv =>
    setVar_of_ne rho _ (fun h => hz (h ▸ hv))
  have hsd : (vset c \ S).biUnion (setVar rho z (S.biUnion rho)) = (vset c \ S).biUnion rho :=
    Finset.biUnion_congr rfl fun v hv => hagree v (Finset.mem_sdiff.mp hv).1
  rw [reduce, sat_mk_iff]
  refine ⟨?_, ?_, ?_⟩
  · rw [Finset.biUnion_insert, setVar_self, hsd, biUnion_split rho hS,
      setVar_of_ne rho _ (Ne.symm hzl)]
    exact hc.eq_biUnion
  · intro v hv
    rcases Finset.mem_insert.mp hv with rfl | hv'
    · rw [setVar_self]
      exact disjoint_biUnion_right' fun u hu => hc.disjoint_conc' (hS hu)
    · obtain ⟨hv1, -⟩ := Finset.mem_sdiff.mp hv'
      rw [hagree v hv1]
      exact hc.disjoint_conc' hv1
  · intro v hv w hw hvw
    rcases Finset.mem_insert.mp hv with rfl | hv'
    · rcases Finset.mem_insert.mp hw with rfl | hw'
      · exact absurd rfl hvw
      · obtain ⟨hw1, hw2⟩ := Finset.mem_sdiff.mp hw'
        rw [setVar_self, hagree w hw1]
        exact disjoint_biUnion_left' fun u hu =>
          hc.disjoint_of_ne' (hS hu) hw1 (fun h => hw2 (h ▸ hu))
    · obtain ⟨hv1, hv2⟩ := Finset.mem_sdiff.mp hv'
      rcases Finset.mem_insert.mp hw with rfl | hw'
      · rw [setVar_self, hagree v hv1]
        exact (disjoint_biUnion_left' fun u hu =>
          hc.disjoint_of_ne' (hS hu) hv1 (fun h => hv2 (h ▸ hu))).symm
      · obtain ⟨hw1, -⟩ := Finset.mem_sdiff.mp hw'
        rw [hagree v hv1, hagree w hw1]
        exact hc.disjoint_of_ne' hv1 hw1 hvw

/-- **Every model of the premises extends to a model of the conclusion**, changing only
the fresh variable.  So a CSE step neither loses nor gains information about the
original vocabulary. -/
theorem CseStep.extend {G G' : System} (h : CseStep G G') {rho : Assign} (hm : SModels rho G) :
    ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | @intro c₁ c₂ z happ =>
    have hc₁ := hm c₁ happ.mem₁
    have hc₂ := hm c₂ happ.mem₂
    have hz₁ : z ∉ vset c₁ := fun hh => happ.fresh (mem_allVars happ.mem₁ (Or.inr hh))
    have hz₂ : z ∉ vset c₂ := fun hh => happ.fresh (mem_allVars happ.mem₂ (Or.inr hh))
    have hzl₁ : z ≠ c₁.lhs := fun hh => happ.fresh (hh ▸ lhs_mem_allVars happ.mem₁)
    have hzl₂ : z ≠ c₂.lhs := fun hh => happ.fresh (hh ▸ lhs_mem_allVars happ.mem₂)
    refine ⟨setVar rho z ((shared c₁ c₂).biUnion rho), ?_, ?_⟩
    · intro c hc
      simp only [cseResult, Finset.mem_insert] at hc
      rcases hc with rfl | rfl | rfl | hc
      · exact sat_name hc₁ (shared_subset_left _ _) hz₁
      · exact sat_reduce hc₁ (shared_subset_left _ _) hz₁ hzl₁
      · exact sat_reduce hc₂ (shared_subset_right _ _) hz₂ hzl₂
      · exact sModels_setVar happ.fresh _ hm c hc
    · intro v hv
      exact setVar_of_ne rho _ (fun hh => happ.fresh (hh ▸ hv))

theorem CseStep.satisfiable_iff {G G' : System} (h : CseStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  constructor
  · rintro ⟨rho, hm⟩
    obtain ⟨rho', hm', -⟩ := h.extend hm
    exact ⟨rho', hm'⟩
  · rintro ⟨rho, hm⟩
    exact ⟨rho, SModels.mono h.subset hm⟩

/-- **One step is a conservative extension.**  On any constraint phrased in the OLD
vocabulary, the enlarged system entails exactly what the old one did. -/
theorem CseStep.entails_iff {G G' : System} (h : CseStep G G') {c : Constraint}
    (hlhs : c.lhs ∈ allVars G) (hvs : vset c ⊆ allVars G) :
    SEntails G' c ↔ SEntails G c := by
  constructor
  · intro hent rho hm
    obtain ⟨rho', hm', hagree⟩ := h.extend hm
    refine (sat_congr_of_agree (rho := rho) (rho' := rho') ?_).mpr (hent rho' hm')
    intro v hv
    rcases hv with rfl | hv'
    · exact (hagree _ hlhs).symm
    · exact (hagree _ (hvs hv')).symm
  · intro hent rho hm
    exact hent rho (SModels.mono h.subset hm)

/-! ### Iterating -/

/-- `CseSteps n G G'`: `G'` is reachable from `G` by exactly `n` CSE steps. -/
inductive CseSteps : ℕ → System → System → Prop
  | refl (G : System) : CseSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} : CseSteps n G G' → CseStep G' G'' → CseSteps (n + 1) G G''

theorem CseSteps.subset {n : ℕ} {G G' : System} (h : CseSteps n G G') : G ⊆ G' := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep ih => exact ih.trans hstep.subset

/-- **The residual is the input.**  For every system reachable from `G₀` by any number of
common-subexpression steps, and every constraint over the ORIGINAL vocabulary, the
reachable system entails it iff `G₀` already did.  Nothing generated by the search is a
new constraint on the user's variables: the whole search is discarded work. -/
theorem CseSteps.entails_iff {n : ℕ} {G₀ G : System} (h : CseSteps n G₀ G) {c : Constraint}
    (hlhs : c.lhs ∈ allVars G₀) (hvs : vset c ⊆ allVars G₀) :
    SEntails G c ↔ SEntails G₀ c := by
  induction h with
  | refl => exact Iff.rfl
  | @tail n G G' G'' hsteps hstep ih =>
    have hsub := allVars_mono hsteps.subset
    exact (hstep.entails_iff (hsub hlhs) (hvs.trans hsub)).trans (ih hlhs hvs)

theorem CseSteps.satisfiable_iff {n : ℕ} {G₀ G : System} (h : CseSteps n G₀ G) :
    (∃ rho, SModels rho G₀) ↔ (∃ rho, SModels rho G) := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep ih => exact ih.trans hstep.satisfiable_iff

/-! ## 5. The co-star family and canonical (hash-consed) naming -/

/-- The `m` shared base variables `b_0 .. b_{m-1}`. -/
def bv (i : ℕ) : Var := 3 * i

/-- The `m` left-hand sides `x_0 .. x_{m-1}` of the co-star system. -/
def xv (i : ℕ) : Var := 3 * i + 1

/-- The CANONICAL name of a common subexpression.  Modelling the best case for the
solver: a perfect hash-cons, so the same shared row is always named by the same
variable.  (The implementation approximates this with its `rhss` reverse lookup.) -/
def nm (S : Finset Var) : Var := 3 * Encodable.encode S + 2

theorem bv_injective : Function.Injective bv := by
  intro i j h
  have h' : (3 * i : ℕ) = 3 * j := h
  omega

theorem xv_injective : Function.Injective xv := by
  intro i j h
  have h' : (3 * i + 1 : ℕ) = 3 * j + 1 := h
  omega

theorem nm_injective : Function.Injective nm := by
  intro S T h
  have h' : (3 * Encodable.encode S + 2 : ℕ) = 3 * Encodable.encode T + 2 := h
  exact Encodable.encode_injective (by omega)

theorem xv_ne_nm (i : ℕ) (S : Finset Var) : xv i ≠ nm S := by
  intro h
  have h' : (3 * i + 1 : ℕ) = 3 * Encodable.encode S + 2 := h
  omega

theorem bv_ne_nm (i : ℕ) (S : Finset Var) : bv i ≠ nm S := by
  intro h
  have h' : (3 * i : ℕ) = 3 * Encodable.encode S + 2 := h
  omega

/-- The base row variables shared by every co-star constraint. -/
def base (m : ℕ) : Finset Var := (Finset.range m).image bv

@[simp] theorem mem_base {m : ℕ} {v : Var} : v ∈ base m ↔ ∃ i < m, bv i = v := by
  simp [base]

theorem card_base (m : ℕ) : (base m).card = m := by
  rw [base, Finset.card_image_of_injective _ bv_injective, Finset.card_range]

/-- **Family B, the co-star system**: `x_i <- (b_0, .., b_{m-1} minus b_i)`, for `i < m`.
`m` constraints, each of arity `m - 1`, all over the same `m` base variables. -/
def coStar (m : ℕ) : System :=
  (Finset.range m).image (fun i => mk (xv i) (base m \ {bv i}) ∅)

theorem mem_coStar {m i : ℕ} (hi : i < m) : mk (xv i) (base m \ {bv i}) ∅ ∈ coStar m :=
  Finset.mem_image.mpr ⟨i, Finset.mem_range.mpr hi, rfl⟩

theorem card_coStar (m : ℕ) : (coStar m).card = m := by
  rw [coStar, Finset.card_image_of_injective, Finset.card_range]
  intro i j h
  exact xv_injective (mk_inj h).1

theorem lhs_of_mem_coStar {m : ℕ} {c : Constraint} (hc : c ∈ coStar m) :
    ∃ i, c.lhs = xv i := by
  obtain ⟨i, -, rfl⟩ := Finset.mem_image.mp hc
  exact ⟨i, rfl⟩

/-- Closure of a system under the CANONICAL-naming form of the common-subexpression
rule.  This is a WEAKER requirement than the real rule: it demands only that the shared
row acquire its canonical name, not that the two premises also be rewritten. -/
def CseClosed (G : System) : Prop :=
  ∀ c₁ ∈ G, ∀ c₂ ∈ G, c₁.lhs ≠ c₂.lhs → 2 ≤ (shared c₁ c₂).card →
    mk (nm (shared c₁ c₂)) (shared c₁ c₂) ∅ ∈ G

theorem sdiff_inter_sdiff (X A B : Finset Var) : (X \ A) ∩ (X \ B) = X \ (A ∪ B) := by
  ext v
  simp only [Finset.mem_inter, Finset.mem_sdiff, Finset.mem_union]
  tauto

/-! ### The lattice of shared rows

Every co-subset of the base obtainable by removing at least two base variables is named
in any saturated system.  The induction is on the number of removed variables. -/

theorem named_sdiff {m : ℕ} {G : System} (hcl : CseClosed G) (hsub : coStar m ⊆ G) :
    ∀ (n : ℕ) (T : Finset Var), T.card = n → T ⊆ base m → 2 ≤ n →
      2 ≤ (base m \ T).card → mk (nm (base m \ T)) (base m \ T) ∅ ∈ G := by
  intro n
  induction n with
  | zero => intro _ _ _ h; omega
  | succ n ih =>
    intro T hcard hTsub _ hbig
    rcases Nat.lt_or_ge n 2 with hn | hn
    · -- base case: exactly two base variables removed; intersect two INPUT constraints
      have h2 : T.card = 2 := by omega
      obtain ⟨a, b, hab, rfl⟩ := Finset.card_eq_two.mp h2
      have ha : a ∈ base m := hTsub (Finset.mem_insert_self _ _)
      have hb : b ∈ base m := hTsub (Finset.mem_insert_of_mem (Finset.mem_singleton_self _))
      obtain ⟨i, hi, rfl⟩ := mem_base.mp ha
      obtain ⟨j, hj, rfl⟩ := mem_base.mp hb
      have hij : i ≠ j := fun h => hab (by rw [h])
      have key : shared (mk (xv i) (base m \ {bv i}) ∅) (mk (xv j) (base m \ {bv j}) ∅)
          = base m \ {bv i, bv j} := by
        rw [shared, vset_mk, vset_mk]
        ext v
        simp only [Finset.mem_inter, Finset.mem_sdiff, Finset.mem_insert, Finset.mem_singleton]
        tauto
      have := hcl _ (hsub (mem_coStar hi)) _ (hsub (mem_coStar hj))
        (by simp only [lhs_mk]; exact fun h => hij (xv_injective h))
        (by rw [key]; exact hbig)
      rwa [key] at this
    · -- inductive step: peel off one removed variable and intersect with the input
      have hne : T.Nonempty := Finset.card_pos.mp (by omega)
      obtain ⟨t, ht⟩ := hne
      obtain ⟨i, hi, rfl⟩ := mem_base.mp (hTsub ht)
      have hT' : (T.erase (bv i)).card = n := by
        rw [Finset.card_erase_of_mem ht, hcard]
        omega
      have hun : T.erase (bv i) ∪ {bv i} = T := by
        rw [Finset.union_comm, Finset.singleton_union, Finset.insert_erase ht]
      have hmono : base m \ T ⊆ base m \ T.erase (bv i) :=
        Finset.sdiff_subset_sdiff (Finset.Subset.refl _) (Finset.erase_subset _ _)
      have hbig' : 2 ≤ (base m \ T.erase (bv i)).card :=
        le_trans hbig (Finset.card_le_card hmono)
      have hIH := ih (T.erase (bv i)) hT' ((Finset.erase_subset _ _).trans hTsub) hn hbig'
      have key : shared (mk (nm (base m \ T.erase (bv i))) (base m \ T.erase (bv i)) ∅)
          (mk (xv i) (base m \ {bv i}) ∅) = base m \ T := by
        rw [shared, vset_mk, vset_mk, sdiff_inter_sdiff, hun]
      have := hcl _ hIH _ (hsub (mem_coStar hi))
        (by simp only [lhs_mk]; exact fun h => xv_ne_nm i _ h.symm)
        (by rw [key]; exact hbig)
      rwa [key] at this

/-- The family of base-subsets that a saturated system must name: everything of size at
least 2 that is missing at least 2 base variables. -/
def Fam (m : ℕ) : Finset (Finset Var) :=
  (base m).powerset.filter (fun S => 2 ≤ S.card ∧ S.card + 2 ≤ m)

theorem named_of_mem_Fam {m : ℕ} {G : System} (hcl : CseClosed G) (hsub : coStar m ⊆ G)
    {S : Finset Var} (hS : S ∈ Fam m) : mk (nm S) S ∅ ∈ G := by
  simp only [Fam, Finset.mem_filter, Finset.mem_powerset] at hS
  obtain ⟨hSsub, h2, h3⟩ := hS
  have hself : base m \ (base m \ S) = S := Finset.sdiff_sdiff_eq_self hSsub
  have hcS : S.card ≤ m := by
    rw [← card_base m]; exact Finset.card_le_card hSsub
  have hcard : (base m \ S).card = m - S.card := by
    rw [Finset.card_sdiff, Finset.inter_eq_left.mpr hSsub, card_base]
  have := named_sdiff hcl hsub (base m \ S).card (base m \ S) rfl Finset.sdiff_subset
    (by omega) (by rw [hself]; omega)
  rwa [hself] at this

/-! ### Counting the family -/

theorem card_Fam (m : ℕ) : 2 ^ m ≤ (Fam m).card + 2 * m + 2 := by
  rcases Nat.eq_zero_or_pos m with rfl | hm
  · have h1 : (2 : ℕ) ^ 0 = 1 := rfl
    omega
  have hbc : (base m).card = m := card_base m
  have htot : (base m).powerset.card = 2 ^ m := by rw [Finset.card_powerset, hbc]
  have hsplit : (Fam m).card
      + ((base m).powerset.filter (fun S => ¬(2 ≤ S.card ∧ S.card + 2 ≤ m))).card
      = 2 ^ m := by
    rw [Fam, ← htot]
    exact Finset.card_filter_add_card_filter_not _
  have hsub : ((base m).powerset.filter (fun S => ¬(2 ≤ S.card ∧ S.card + 2 ≤ m))) ⊆
      ((Finset.powersetCard 0 (base m) ∪ Finset.powersetCard 1 (base m)) ∪
       (Finset.powersetCard (m - 1) (base m) ∪ Finset.powersetCard m (base m))) := by
    intro S hS
    rw [Finset.mem_filter, Finset.mem_powerset] at hS
    obtain ⟨hSsub, hnp⟩ := hS
    have hle : S.card ≤ m := by rw [← hbc]; exact Finset.card_le_card hSsub
    have hcases : S.card = 0 ∨ S.card = 1 ∨ S.card = m - 1 ∨ S.card = m := by omega
    simp only [Finset.mem_union, Finset.mem_powersetCard]
    rcases hcases with h | h | h | h
    · exact Or.inl (Or.inl ⟨hSsub, h⟩)
    · exact Or.inl (Or.inr ⟨hSsub, h⟩)
    · exact Or.inr (Or.inl ⟨hSsub, h⟩)
    · exact Or.inr (Or.inr ⟨hSsub, h⟩)
  have c0 : (Finset.powersetCard 0 (base m)).card = 1 := by
    rw [Finset.card_powersetCard, hbc]; simp
  have c1 : (Finset.powersetCard 1 (base m)).card = m := by
    rw [Finset.card_powersetCard, hbc]; simp
  have cm : (Finset.powersetCard m (base m)).card = 1 := by
    rw [Finset.card_powersetCard, hbc]; simp
  have cm1 : (Finset.powersetCard (m - 1) (base m)).card = m := by
    rw [Finset.card_powersetCard, hbc, Nat.choose_symm hm, Nat.choose_one_right]
  have hb : ((base m).powerset.filter (fun S => ¬(2 ≤ S.card ∧ S.card + 2 ≤ m))).card
      ≤ 2 * m + 2 := by
    calc ((base m).powerset.filter (fun S => ¬(2 ≤ S.card ∧ S.card + 2 ≤ m))).card
        ≤ ((Finset.powersetCard 0 (base m) ∪ Finset.powersetCard 1 (base m)) ∪
            (Finset.powersetCard (m - 1) (base m) ∪ Finset.powersetCard m (base m))).card :=
          Finset.card_le_card hsub
      _ ≤ (Finset.powersetCard 0 (base m) ∪ Finset.powersetCard 1 (base m)).card
            + (Finset.powersetCard (m - 1) (base m) ∪ Finset.powersetCard m (base m)).card :=
          Finset.card_union_le _ _
      _ ≤ ((Finset.powersetCard 0 (base m)).card + (Finset.powersetCard 1 (base m)).card)
            + ((Finset.powersetCard (m - 1) (base m)).card
               + (Finset.powersetCard m (base m)).card) :=
          Nat.add_le_add (Finset.card_union_le _ _) (Finset.card_union_le _ _)
      _ = 2 * m + 2 := by rw [c0, c1, cm1, cm]; omega
  omega

/-! ### The exponential lower bound -/

/-- The constraints naming the family. -/
def names (m : ℕ) : System := (Fam m).image (fun S => mk (nm S) S ∅)

theorem names_subset {m : ℕ} {G : System} (hcl : CseClosed G) (hsub : coStar m ⊆ G) :
    names m ⊆ G := by
  intro c hc
  obtain ⟨S, hS, rfl⟩ := Finset.mem_image.mp hc
  exact named_of_mem_Fam hcl hsub hS

theorem card_names (m : ℕ) : (names m).card = (Fam m).card :=
  Finset.card_image_of_injective _ fun _ _ h => (mk_inj h).2.1

theorem disjoint_names_coStar (m : ℕ) : Disjoint (names m) (coStar m) := by
  rw [Finset.disjoint_left]
  intro c hc hc'
  obtain ⟨S, -, rfl⟩ := Finset.mem_image.mp hc
  obtain ⟨i, hi⟩ := lhs_of_mem_coStar hc'
  exact xv_ne_nm i S hi.symm

/-- **THE MAIN LOWER BOUND.**  Any system that contains the `m`-constraint co-star
system and is closed under common-subexpression naming has at least `2 ^ m - m - 2`
constraints.  The search space is exponential in the arity of a *single* definition,
even under the idealisation that naming is perfectly hash-consed. -/
theorem coStar_card_lower {m : ℕ} {G : System} (hcl : CseClosed G) (hsub : coStar m ⊆ G) :
    2 ^ m ≤ G.card + m + 2 := by
  have h1 : names m ∪ coStar m ⊆ G := Finset.union_subset (names_subset hcl hsub) hsub
  have h2 : (names m ∪ coStar m).card = (Fam m).card + m := by
    rw [Finset.card_union_of_disjoint (disjoint_names_coStar m), card_names, card_coStar]
  have h3 : (Fam m).card + m ≤ G.card := by
    rw [← h2]; exact Finset.card_le_card h1
  have h4 := card_Fam m
  omega

/-- The same bound written with truncated subtraction. -/
theorem coStar_card_lower' {m : ℕ} {G : System} (hcl : CseClosed G) (hsub : coStar m ⊆ G) :
    2 ^ m - m - 2 ≤ G.card := by
  have := coStar_card_lower hcl hsub
  omega

/-- Concretely, at the measured size `m = 7` (6.38 s in the real solver) any saturated
system carries at least 119 constraints. -/
theorem coStar_seven {G : System} (hcl : CseClosed G) (hsub : coStar 7 ⊆ G) :
    119 ≤ G.card := by
  have h := coStar_card_lower hcl hsub
  have h7 : (2 : ℕ) ^ 7 = 128 := rfl
  omega

/-! ### What the canonical-naming hypothesis costs

`CseClosed` demands only that the shared row acquire ITS CANONICAL name `nm S`; it does
not demand that the two premises also be rewritten, so it is a strictly weaker closure
condition than the real rule and the bound above is correspondingly strong.

The one genuine idealisation is that naming is a FUNCTION of the named row.  It is used
in exactly one place: the induction step of `named_sdiff` intersects the naming
constraint of `base m \ T'` with an input constraint, and the rule fires only across
different left-hand sides, which `nm_injective` and `xv_ne_nm` supply.  With genuinely
fresh names one would have to rule out the (semantically absurd, syntactically legal)
possibility that the namer of `base m \ T'` happens to carry the left-hand side `x_i` of
the very input constraint it must be intersected with.  Doing so needs an invariant
about which variables can name which rows that this file does not develop; it is left as
a paper-level remark.  Note the direction of the gap: genuinely fresh naming produces a
DIFFERENT constraint per application, so the true saturated set is at least as large --
the idealisation is the solver's best case, not ours.

Note also the off-by-one against the informal target `2 ^ m - m - 1`.  The co-sets of
size `m - 1` -- the right-hand sides `base m \ {b_i}` of the inputs themselves -- are
NOT named by `nm`: they are the intersection of no two distinct constraints of the
system, and they carry the input left-hand sides `x_i` instead.  So the named family is
exactly `{S : 2 <= |S| <= m - 2}`, of size `2 ^ m - 2 * m - 2`, and adding the `m` inputs
gives `2 ^ m - m - 2`. -/

/-! ## 6. No decreasing measure

The rule as written GROWS the working set, and with genuinely fresh names it can be
applied to the very same pair of premises forever.  Consequently none of the standard
syntactic termination measures works, and in fact NO measure into `ℕ` works. -/

theorem CseStep.ssubset {G G' : System} (h : CseStep G G') : G ⊂ G' := by
  cases h with
  | @intro c₁ c₂ z happ =>
    refine (Finset.ssubset_iff_of_subset (subset_cseResult _ _ _ _)).mpr
      ⟨mk z (shared c₁ c₂) ∅, Finset.mem_insert_self _ _, fun hmem => ?_⟩
    exact happ.fresh (lhs_mem_allVars hmem)

/-- Measure 1: the number of constraints.  It STRICTLY INCREASES. -/
theorem CseStep.card_lt {G G' : System} (h : CseStep G G') : G.card < G'.card :=
  Finset.card_lt_card h.ssubset

/-- Measure 2: total variable occurrences (plus one per constraint). -/
def occ (G : System) : ℕ := ∑ c ∈ G, (c.vars.length + 1)

/-- Measure 2 STRICTLY INCREASES. -/
theorem CseStep.occ_lt {G G' : System} (h : CseStep G G') : occ G < occ G' := by
  cases h with
  | @intro c₁ c₂ z happ =>
    refine Finset.sum_lt_sum_of_subset (subset_cseResult _ _ _ _)
      (i := mk z (shared c₁ c₂) ∅) (Finset.mem_insert_self _ _) (fun hmem => ?_)
      (Nat.succ_pos _) (fun j _ _ => Nat.zero_le _)
    exact happ.fresh (lhs_mem_allVars hmem)

/-- Measure 3: the multiset of right-hand-side sizes, ordered by the sub-multiset
order (which the Dershowitz–Manna multiset order extends). -/
def rhsSizes (G : System) : Multiset ℕ := G.val.map (fun c => (vset c).card)

/-- Measure 3 STRICTLY INCREASES: the old multiset is a PROPER sub-multiset of the new
one, so it is smaller in the sub-multiset order and in every order extending it. -/
theorem CseStep.rhsSizes_lt {G G' : System} (h : CseStep G G') : rhsSizes G < rhsSizes G' := by
  have hle : rhsSizes G ≤ rhsSizes G' :=
    Multiset.map_le_map (Finset.val_le_iff_val_subset.mpr fun x hx => h.subset hx)
  refine lt_of_le_of_ne hle fun heq => ?_
  have hc : (rhsSizes G).card = (rhsSizes G').card := congrArg Multiset.card heq
  rw [rhsSizes, rhsSizes, Multiset.card_map, Multiset.card_map] at hc
  have hcard : G.card = G'.card := hc
  have := h.card_lt
  omega

/-- **All three standard syntactic measures go the WRONG way on every step.** -/
theorem cseStep_measures_increase {G G' : System} (h : CseStep G G') :
    G.card < G'.card ∧ occ G < occ G' ∧ rhsSizes G < rhsSizes G' :=
  ⟨h.card_lt, h.occ_lt, h.rhsSizes_lt⟩

/-- A step is always available on a pair of premises satisfying the guard: freshness can
never block the rule, because the label/variable universe is unbounded. -/
theorem exists_step {G : System} {c₁ c₂ : Constraint} (h₁ : c₁ ∈ G) (h₂ : c₂ ∈ G)
    (hne : c₁.lhs ≠ c₂.lhs) (hbig : 2 ≤ (shared c₁ c₂).card) :
    ∃ G', CseStep G G' ∧ G ⊆ G' := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars G)
  exact ⟨cseResult G c₁ c₂ z, CseStep.intro ⟨h₁, h₂, hne, hbig, hz⟩,
    subset_cseResult _ _ _ _⟩

/-- Chains of EVERY length exist: one applicable pair of premises can be re-used
forever, because each application needs only a new fresh name. -/
theorem steps_exists {G : System} {c₁ c₂ : Constraint} (h₁ : c₁ ∈ G) (h₂ : c₂ ∈ G)
    (hne : c₁.lhs ≠ c₂.lhs) (hbig : 2 ≤ (shared c₁ c₂).card) (n : ℕ) :
    ∃ G', CseSteps n G G' ∧ G.card + n ≤ G'.card := by
  induction n with
  | zero => exact ⟨G, CseSteps.refl G, by omega⟩
  | succ n ih =>
    obtain ⟨G', hsteps, hcard⟩ := ih
    obtain ⟨G'', hstep, -⟩ := exists_step (hsteps.subset h₁) (hsteps.subset h₂) hne hbig
    have := hstep.card_lt
    exact ⟨G'', CseSteps.tail hsteps hstep, by omega⟩

theorem steps_measure {μ : System → ℕ} (hμ : ∀ G G', CseStep G G' → μ G' < μ G)
    {n : ℕ} {G G' : System} (h : CseSteps n G G') : μ G' + n ≤ μ G := by
  induction h with
  | refl => omega
  | @tail n G G' G'' _ hstep ih =>
    have := hμ G' G'' hstep
    omega

/-! ### A concrete divergent seed

`a <- (p, q, r)` and `b <- (p, q, s)`: the shared row `{p, q}` has size 2, so the rule
fires, and it keeps firing on the same two premises with a new name each time. -/

/-- `a <- (p, q, r)`. -/
def seed₁ : Constraint := mk 0 {2, 3, 4} ∅

/-- `b <- (p, q, s)`. -/
def seed₂ : Constraint := mk 1 {2, 3, 5} ∅

/-- The two-constraint divergent seed. -/
def seed : System := {seed₁, seed₂}

theorem seed_shared : shared seed₁ seed₂ = {2, 3} := by
  rw [seed₁, seed₂, shared, vset_mk, vset_mk]
  decide

theorem seed_guard : 2 ≤ (shared seed₁ seed₂).card := by
  rw [seed_shared]; decide

theorem seed_lhs_ne : seed₁.lhs ≠ seed₂.lhs := by decide

/-- **The common-subexpression rule does not terminate.**  From `seed` there are chains
of every length, and the working set grows by at least one constraint per step. -/
theorem seed_diverges (n : ℕ) : ∃ G, CseSteps n seed G ∧ seed.card + n ≤ G.card :=
  steps_exists (Finset.mem_insert_self _ _)
    (Finset.mem_insert_of_mem (Finset.mem_singleton_self _)) seed_lhs_ne seed_guard n

/-- **There is NO measure into `ℕ` that decreases on every rule application.**  This is
the sharp form of "no decreasing measure": not merely that the usual candidates fail,
but that no well-founded `ℕ`-valued ranking of constraint systems exists at all. -/
theorem no_decreasing_measure :
    ¬ ∃ μ : System → ℕ, ∀ G G', CseStep G G' → μ G' < μ G := by
  rintro ⟨μ, hμ⟩
  obtain ⟨G, hsteps, -⟩ := seed_diverges (μ seed + 1)
  have := steps_measure hμ hsteps
  omega

/-! ## 7. The co-star system is satisfiable, and its residual is itself -/

theorem bv_ne_xv (i j : ℕ) : bv i ≠ xv j := by
  intro h
  have h' : (3 * i : ℕ) = 3 * j + 1 := h
  omega

theorem xv_notMem_base (m i : ℕ) : xv i ∉ base m := by
  intro h
  obtain ⟨j, -, hj⟩ := mem_base.mp h
  exact bv_ne_xv j i hj

/-- A model of the co-star system: each base variable gets its own singleton row and
`x_i` gets everything except `b_i`.  (Every variable is `3 * k`, `3 * k + 1` or
`3 * k + 2`, so `v / 3` recovers the index of an `x`.) -/
def rhoStar (m : ℕ) : Assign := fun v => if v ∈ base m then {v} else base m \ {bv (v / 3)}

theorem rhoStar_base {m : ℕ} {v : Var} (hv : v ∈ base m) : rhoStar m v = {v} := by
  simp [rhoStar, hv]

theorem rhoStar_xv (m i : ℕ) : rhoStar m (xv i) = base m \ {bv i} := by
  have h2 : xv i / 3 = i := by
    have h : ((3 * i + 1) / 3 : ℕ) = i := by omega
    exact h
  simp only [rhoStar, if_neg (xv_notMem_base m i), h2]

theorem biUnion_singleton_self (S : Finset Var) : S.biUnion (fun v => ({v} : Row)) = S := by
  ext l; simp

theorem sat_coStar (m i : ℕ) : Sat (rhoStar m) (mk (xv i) (base m \ {bv i}) ∅) := by
  rw [sat_mk_iff]
  refine ⟨?_, fun v _ => Finset.disjoint_empty_left _, fun v hv w hw hvw => ?_⟩
  · rw [rhoStar_xv, Finset.empty_union,
      Finset.biUnion_congr (rfl : base m \ {bv i} = base m \ {bv i})
        (fun v hv => rhoStar_base (Finset.mem_sdiff.mp hv).1),
      biUnion_singleton_self]
  · rw [rhoStar_base (Finset.mem_sdiff.mp hv).1, rhoStar_base (Finset.mem_sdiff.mp hw).1]
    exact Finset.disjoint_singleton.mpr hvw

/-- The co-star system is satisfiable -- so the solver's answer really is "yes, and the
residual is what you gave me". -/
theorem coStar_satisfiable (m : ℕ) : ∃ rho, SModels rho (coStar m) := by
  refine ⟨rhoStar m, fun c hc => ?_⟩
  obtain ⟨i, -, rfl⟩ := Finset.mem_image.mp hc
  exact sat_coStar m i

/-- **Family B: the entire search is discarded work.**  Whatever the solver derives from
the co-star system, over the co-star system's own vocabulary it entails exactly what the
input entailed.  Combined with `coStar_card_lower`, the solver does `2 ^ m`-sized work to
return its input. -/
theorem coStar_residual {m n : ℕ} {G : System} (h : CseSteps n (coStar m) G) {c : Constraint}
    (hlhs : c.lhs ∈ allVars (coStar m)) (hvs : vset c ⊆ allVars (coStar m)) :
    SEntails G c ↔ SEntails (coStar m) c := h.entails_iff hlhs hvs

/-! ### Family A: the join chain also seeds divergence

One `join` call contributes `a <- (d, e)`, `b <- (e, f)`, `c <- (d, e, f)`.  The first
and third premises already share TWO variables, so the rule fires inside a single call;
`CseSteps` chains of every length exist from one `join`. -/

/-- The three constraints contributed by one `join` call, with `a, b, c, d, e, f`
instantiated to `0, 1, 5, 2, 3, 4`. -/
def joinTriple : System := {mk 0 {2, 3} ∅, mk 1 {3, 4} ∅, mk 5 {2, 3, 4} ∅}

theorem joinTriple_shared : shared (mk 0 {2, 3} ∅) (mk 5 {2, 3, 4} ∅) = {2, 3} := by
  rw [shared, vset_mk, vset_mk]; decide

theorem joinTriple_diverges (n : ℕ) :
    ∃ G, CseSteps n joinTriple G ∧ joinTriple.card + n ≤ G.card := by
  refine steps_exists (c₁ := mk 0 {2, 3} ∅) (c₂ := mk 5 {2, 3, 4} ∅)
    (Finset.mem_insert_self _ _)
    (Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (Finset.mem_singleton_self _)))
    (by decide) ?_ n
  rw [joinTriple_shared]; decide

end Rowpartition
