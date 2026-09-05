/-
# L5 (C1): `LoopStrict` — the refinement relation with no arbitrary deletion

`Loop/Refine.lean`'s `LoopRel` carries `weaken : G' ⊆ G → LoopRel G G'`, an ARBITRARY
deletion, so no measure is monotone along a `LoopRun` and none of the library's mint bounds
transports (`L3-REVIEW.md` §6d, F8).  `LoopStrict` replaces it.

**Round 2 (after `L5-REVIEW.md` F1).**  Round 1's `emptyRemove` / `instRemove` / `concRemove`
constrained `G'` only by one membership fact, `SSat G → SSat G'` and `NoLoss G G'`, which
licenses arbitrary satisfiability-preserving ADDITION — the reviewer's `Growth.lean` builds a
`LoopStrictRun` of unbounded vocabulary from a fixed satisfiable system.  They are now the
LIBRARY OPERATORS applied to `G`:

| R2.5 row | the Scala | constructor | `G'` |
|---|---|---|---|
| 2, 7 | the dequeue drop; `trim`, `++!`, `Q.insert` refusing | `drop` | any `G' ⊆ G` that loses nothing |
| 3, 5 | `instantiate`'s removal, at BOTH argument orders | `instRemove` | `substOut v u G` |
| 4 | `makeEmpty`'s erasure | `emptyRemove` | `KeyedEmpty.makeEmptyE v G` |
| 6 | `destructiveSub` with `keepDefs` and `can` | `concRemove` | `KeyedRow.concretizeSrs v C G` |
| — | `Q.+!`'s `CommonPartition` redirect, which is in NONE of those operators' images (R2.2) | `requeue` | any `G'` LOGICALLY EQUIVALENT to `G` over `G`'s vocabulary |

so that **only the four MINTING constructors can enlarge the vocabulary**, which is
`LoopStrict.allVars_subset_of_notMint` / `LoopStrictSteps.allVars_card_le` below, and
`no_growth_without_mint` is the refutation of the reviewer's witness.

Two licences appear throughout:

* `NoLoss G G' := ∀ c ∈ G, SEntails G' c` — the system the loop keeps still entails every fact
  the system it left had.  `LoopRel.weaken` fails it (`weaken_not_strict`), and
  `LoopStrict.no_loss` proves that no `LoopStrict` step and no run of them ever loses a fact;
* `Conserv G G' := ∀ c ∈ G', SEntails G c` — nothing is invented.  Together with `NoLoss` it is
  model-set EQUALITY, which is what the queue's own rewriting does.

The nine non-deleting constructors are `LoopRel`'s own, verbatim.
-/
import Rowpartition.Loop.Order

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

/-! ## 1. Losing nothing, and inventing nothing -/

/-- **`G'` loses nothing of `G`**: every constraint of `G` is a consequence of `G'`.  This is
the licence every deleting constructor of `LoopStrict` carries, and `LoopRel.weaken` does
not. -/
def NoLoss (G G' : System) : Prop := ∀ c ∈ G, SEntails G' c

/-- **`G'` invents nothing**: every constraint of `G'` is a consequence of `G`.  A MINT fails
this (the fresh variable is unconstrained by `G`); the queue's own rewriting does not. -/
def Conserv (G G' : System) : Prop := ∀ c ∈ G', SEntails G c

theorem NoLoss.of_subset {G G' : System} (h : G ⊆ G') : NoLoss G G' :=
  fun _ hc _ hm => hm _ (h hc)

theorem NoLoss.refl (G : System) : NoLoss G G := NoLoss.of_subset (Finset.Subset.refl G)

theorem NoLoss.trans {G G' G'' : System} (h1 : NoLoss G G') (h2 : NoLoss G' G'') :
    NoLoss G G'' := by
  intro c hc rho hm
  exact h1 c hc rho (fun d hd => h2 d hd rho hm)

/-- The models of `G'` are models of `G`, which is what "loses nothing" means semantically. -/
theorem NoLoss.models {G G' : System} (h : NoLoss G G') {rho : Assign}
    (hm : SModels rho G') : SModels rho G := fun c hc => h c hc rho hm

theorem Conserv.models {G G' : System} (h : Conserv G G') {rho : Assign}
    (hm : SModels rho G) : SModels rho G' := fun c hc => h c hc rho hm

theorem Conserv.of_subset {G G' : System} (h : G' ⊆ G) : Conserv G G' :=
  fun _ hc _ hm => hm _ (h hc)

/-! ## 2. `instantiate`'s removal, as an operator on systems -/

/-- One constraint under the substitution `v := u`. -/
def substC (v u : Var) (c : Constraint) : Constraint :=
  mk (if c.lhs == v then u else c.lhs)
    ((vset c).image (fun w => if w == v then u else w)) c.conc

/-- **`instantiate`'s removal**: every constraint that MENTIONS `v` (as its left-hand side or
among its parts) is replaced by its image under `v := u`, the others are kept verbatim, and the
link `v <- (u)` is retained -- in the environment, which `sys` models.  This is `Constraints.
instantiate`'s `partition (_ involves v)` / `replace` / `instantiateType` as one function. -/
def substOut (v u : Var) (G : System) : System :=
  insert (mk v {u} (∅ : Row))
    ((G.filter (fun c => c.lhs ≠ v ∧ v ∉ vset c)) ∪
      (G.filter (fun c => c.lhs = v ∨ v ∈ vset c)).image (substC v u))

theorem mem_substOut {v u : Var} {G : System} {c : Constraint} :
    c ∈ substOut v u G ↔ c = mk v {u} (∅ : Row) ∨
      (c ∈ G ∧ c.lhs ≠ v ∧ v ∉ vset c) ∨
      (∃ d ∈ G, (d.lhs = v ∨ v ∈ vset d) ∧ c = substC v u d) := by
  simp only [substOut, Finset.mem_insert, Finset.mem_union, Finset.mem_filter,
    Finset.mem_image]
  constructor
  · rintro (rfl | (⟨h1, h2, h3⟩ | ⟨d, ⟨hd, hdv⟩, rfl⟩))
    · exact Or.inl rfl
    · exact Or.inr (Or.inl ⟨h1, h2, h3⟩)
    · exact Or.inr (Or.inr ⟨d, hd, hdv, rfl⟩)
  · rintro (rfl | ⟨h1, h2, h3⟩ | ⟨d, hd, hdv, rfl⟩)
    · exact Or.inl rfl
    · exact Or.inr (Or.inl ⟨h1, h2, h3⟩)
    · exact Or.inr (Or.inr ⟨d, ⟨hd, hdv⟩, rfl⟩)

/-- **The substitution is sound**: under a model of the link, a constraint's image is
satisfied.  The one case where the image has FEWER parts than the constraint -- `v` and `u`
both among them -- is safe because the original forces `rho u = ∅`. -/
theorem sat_substC {rho : Assign} {v u : Var} {c : Constraint} (hvu : rho v = rho u)
    (h : Sat rho c) : Sat rho (substC v u c) := by
  set f : Var → Var := fun w => if w == v then u else w with hf
  have hfr : ∀ w, rho (f w) = rho w := by
    intro w
    by_cases hw : w = v
    · subst hw; simp only [hf, beq_self_eq_true, if_pos]; exact hvu.symm
    · simp only [hf]
      rw [if_neg (by simpa using hw)]
  have hlhs : rho (if c.lhs == v then u else c.lhs) = rho c.lhs := by
    by_cases hl : c.lhs = v
    · rw [if_pos (by simpa using hl), hl]; exact hvu.symm
    · rw [if_neg (by simpa using hl)]
  have hbi : ((vset c).image f).biUnion rho = (vset c).biUnion rho := by
    ext l
    simp only [Finset.mem_biUnion, Finset.mem_image]
    constructor
    · rintro ⟨y, ⟨w, hw, rfl⟩, hl⟩; exact ⟨w, hw, by rwa [hfr w] at hl⟩
    · rintro ⟨w, hw, hl⟩; exact ⟨f w, ⟨w, hw, rfl⟩, by rwa [hfr w]⟩
  have hc : Sat rho (mk c.lhs (vset c) c.conc) := by
    rw [sat_mk_iff]
    exact ⟨by simpa using h.eq_biUnion, fun w hw => h.disjoint_conc' hw,
      fun w hw z hz hwz => h.disjoint_of_ne' hw hz hwz⟩
  rw [sat_mk_iff] at hc
  obtain ⟨he, hk, hd⟩ := hc
  rw [substC, sat_mk_iff]
  refine ⟨by rw [hlhs, he, hbi], fun y hy => ?_, fun y hy z hz hyz => ?_⟩
  · obtain ⟨w, hw, rfl⟩ := Finset.mem_image.mp hy
    rw [hfr w]; exact hk w hw
  · obtain ⟨w, hw, rfl⟩ := Finset.mem_image.mp hy
    obtain ⟨x, hx, rfl⟩ := Finset.mem_image.mp hz
    have hwx : w ≠ x := by rintro rfl; exact hyz rfl
    rw [hfr w, hfr x]
    exact hd w hw x hx hwx

/-- **`substOut` is sound.** -/
theorem substOut_sound {v u : Var} {G : System} (hlink : mk v {u} (∅ : Row) ∈ G) :
    ∀ rho, SModels rho G → SModels rho (substOut v u G) := by
  intro rho hm c hc
  have hvu : rho v = rho u := sat_link_iff.mp (hm _ hlink)
  rcases mem_substOut.mp hc with rfl | ⟨hcG, -, -⟩ | ⟨d, hd, -, rfl⟩
  · exact hm _ hlink
  · exact hm c hcG
  · exact sat_substC hvu (hm d hd)

/-- **`substOut` adds no variable.** -/
theorem allVars_substOut_subset {v u : Var} {G : System} (hlink : mk v {u} (∅ : Row) ∈ G) :
    allVars (substOut v u G) ⊆ allVars G := by
  have hu : u ∈ allVars G :=
    mem_allVars hlink (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self u))
  intro w hw
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
  rcases mem_substOut.mp hc with rfl | ⟨hcG, -, -⟩ | ⟨d, hd, -, rfl⟩
  · rw [lhs_mk, vset_mk] at hwc
    rcases Finset.mem_insert.mp hwc with rfl | h
    · exact lhs_mem_allVars hlink
    · rw [Finset.mem_singleton] at h; subst h; exact hu
  · exact mem_allVars hcG (by
      rcases Finset.mem_insert.mp hwc with h | h
      · exact Or.inl h
      · exact Or.inr h)
  · rw [substC, lhs_mk, vset_mk] at hwc
    rcases Finset.mem_insert.mp hwc with h | h
    · subst h
      by_cases hl : d.lhs = v
      · rw [if_pos (by simpa using hl)]; exact hu
      · rw [if_neg (by simpa using hl)]; exact lhs_mem_allVars hd
    · obtain ⟨x, hx, rfl⟩ := Finset.mem_image.mp h
      by_cases hx' : x = v
      · rw [if_pos (by simpa using hx')]; exact hu
      · rw [if_neg (by simpa using hx')]; exact mem_allVars hd (Or.inr hx)

/-! ## 3. `LoopStrict` -/

/-- **One abstract step of the loop, with no arbitrary deletion.**  The first nine
constructors are `LoopRel`'s, verbatim; `weaken` is replaced by the deletions of
`L3-THEOREMS.md` R2.5, each stated as the OPERATOR the Scala applies. -/
inductive LoopStrict : System → System → Prop
  /-- CSE reuse and fold, `splitConcrete`'s syntactic reuse, cancellation, substitution,
  self-substitution, common partition -- `SplitNecessary.NonGenStep`. -/
  | nongen {G G' : System} : NonGenStep G G' → LoopStrict G G'
  /-- `splitConcrete`: keyed (`splitKey`) and concrete-row (`splitRow`) reuse and the
  `Carried`-guarded mint -- `KeyedRow.K2SplitStep`. -/
  | split {G G' : System} : K2SplitStep G G' → LoopStrict G G'
  /-- `resolution`'s mint -- `Cut.ResStep`. -/
  | res {G G' : System} : ResStep G G' → LoopStrict G G'
  /-- `splitConcrete`'s MINT with `Cut.SplitApp`'s SYNTACTIC guard. -/
  | splitFree {G G' : System} : SplitStep G G' → LoopStrict G G'
  /-- `resolution`'s guarded (`resGuard`) and concrete-row (`resRow`) reuse. -/
  | kres {G G' : System} : K2ResStep G G' → LoopStrict G G'
  /-- `replace`'s `f p.lhs` -- an alias rewrites the LEFT-hand side. -/
  | renameLhs {G : System} {a b : Var} {S : Finset Var} {K : Row} :
      mk a S K ∈ G → mk a {b} (∅ : Row) ∈ G → LoopStrict G (insert (mk b S K) G)
  /-- `unify(u, v)` on `v <- (u)` instantiates `u := v`: the link read backwards. -/
  | linkSymm {G : System} {a b : Var} :
      mk a {b} (∅ : Row) ∈ G → LoopStrict G (insert (mk b {a} (∅ : Row)) G)
  /-- `makeEmpty`'s `aux` -- `makeEmptyD`'s `propPart`, as a single conclusion. -/
  | emptyProp {G : System} {a x : Var} {S : Finset Var} :
      mk a S (∅ : Row) ∈ G → mk a ∅ (∅ : Row) ∈ G → x ∈ S →
      LoopStrict G (insert (mk x ∅ (∅ : Row)) G)
  /-- `RHS.merge`'s returned `es` and `replace`'s two-element queue. -/
  | dedup {G : System} {c v x : Var} {S S' : Finset Var} {K K' : Row} :
      mk c S K ∈ G → mk v S' K' ∈ G → v ∈ S → x ∈ S.erase v → x ∈ S' →
      LoopStrict G (insert (mk x ∅ (∅ : Row)) G)
  /-- **R2.5 rows 2 and 7 — the dequeue drop and the queue drops.**  The dequeued partition
  leaves `incm`; `trim` refuses what `proc` already holds, `++!` refuses what the target queue
  already holds, `Q.insert` refuses a self-unification.  In every case what is dropped is one
  the system that remains still ENTAILS -- the licence `weaken` lacks. -/
  | drop {G G' : System} : G' ⊆ G → NoLoss G G' → LoopStrict G G'
  /-- **R2.5 rows 3 and 5 — `instantiate`'s removal**, at both argument orders, as the
  operator `substOut`. -/
  | instRemove {G : System} {v u : Var} :
      mk v {u} (∅ : Row) ∈ G → NoLoss G (substOut v u G) →
      LoopStrict G (substOut v u G)
  /-- **R2.5 row 4 — `makeEmpty`'s erasure**, as the library operator `makeEmptyE`, which is
  `makeEmptyD` with `v <- ()` RETAINED. -/
  | emptyRemove {G : System} {v : Var} :
      mk v ∅ (∅ : Row) ∈ G → NoLoss G (makeEmptyE v G) →
      LoopStrict G (makeEmptyE v G)
  /-- **R2.5 row 6 — `destructiveSub`'s deletion**, as the library operator `concretizeSrs`,
  i.e. `concretizeKeep` (which is `concretize` widened by the kept two-abstract definitions,
  the 2026-09-02 `keepDefs` repair) union the `srs` re-expression.  Its `NoLoss` premise is
  the one `cancellation_bare` shows cannot be dropped. -/
  | concRemove {G : System} {v : Var} {C : Row} :
      mk v ∅ C ∈ G → NoLoss G (concretizeSrs v C G) →
      LoopStrict G (concretizeSrs v C G)
  /-- **The queue's own rewriting.**  `Q.+!`'s `CommonPartition` redirect replaces an
  insertion of `w <- (S, K)` by `w <- (a)` when `a <- (S, K)` is already in the queue; that
  constraint is in NONE of the three operators' images (R2.2), so the loop's `sys s'` is
  reached from the operator's output by this step.  `G'` must be logically EQUIVALENT to `G`
  (`Conserv` and `NoLoss` together) and over `G`'s vocabulary: it can neither be stronger, nor
  weaker, nor name a variable `G` does not. -/
  | requeue {G G' : System} :
      allVars G' ⊆ allVars G → Conserv G G' → NoLoss G G' → LoopStrict G G'

/-- A run of the tighter relation. -/
abbrev LoopStrictRun : System → System → Prop := Relation.ReflTransGen LoopStrict

/-! ## 4. Soundness, and the theorem that says the deletions are not arbitrary -/

/-- **Every `LoopStrict` step preserves satisfiability.** -/
theorem LoopStrict.sat {G G' : System} (h : LoopStrict G G') : SSat G → SSat G' := by
  rintro ⟨rho, hm⟩
  cases h with
  | nongen h => exact ⟨rho, (h.models_iff rho).mp hm⟩
  | split h => obtain ⟨rho', hm', -⟩ := K2SplitStep.extend hm h; exact ⟨rho', hm'⟩
  | res h => exact h.satisfiable_iff.mp ⟨rho, hm⟩
  | splitFree h => exact h.satisfiable_iff.mp ⟨rho, hm⟩
  | kres h => obtain ⟨rho', hm', -⟩ := K2ResStep.extend hm h; exact ⟨rho', hm'⟩
  | renameLhs h1 h2 =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact renameLhs_sat (hm _ h1) (hm _ h2)
    · exact hm c hc'
  | linkSymm h1 =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact linkSymm_sat (hm _ h1)
    · exact hm c hc'
  | emptyProp h1 h2 hx =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact emptyProp_sat (hm _ h1) (hm _ h2) hx
    · exact hm c hc'
  | dedup h1 h2 hv hx hx' =>
    refine ⟨rho, fun c hc => ?_⟩
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact dedup_sat (hm _ h1) (hm _ h2) hv hx hx'
    · exact hm c hc'
  | drop hsub _ => exact ⟨rho, SModels.mono hsub hm⟩
  | instRemove hlink _ => exact ⟨rho, substOut_sound hlink rho hm⟩
  | emptyRemove hv _ => exact ⟨rho, makeEmptyE_sound hv hm⟩
  | concRemove hv _ => exact ⟨rho, concretizeSrs_sound hv rho hm⟩
  | requeue _ hcons _ => exact ⟨rho, hcons.models hm⟩

/-- **`LoopStrict` never loses a fact.**  This is the property `LoopRel.weaken` fails: every
constraint of the system a step leaves is a consequence of the system it reaches.  The nine
rule constructors satisfy it because they are ADDITIVE; the deleting ones carry it. -/
theorem LoopStrict.no_loss {G G' : System} (h : LoopStrict G G') : NoLoss G G' := by
  cases h with
  | nongen h => exact NoLoss.of_subset h.subset
  | split h => exact NoLoss.of_subset h.subset
  | res h => exact NoLoss.of_subset h.subset
  | splitFree h => exact NoLoss.of_subset h.subset
  | kres h => exact NoLoss.of_subset h.subset
  | renameLhs _ _ => exact NoLoss.of_subset (Finset.subset_insert _ _)
  | linkSymm _ => exact NoLoss.of_subset (Finset.subset_insert _ _)
  | emptyProp _ _ _ => exact NoLoss.of_subset (Finset.subset_insert _ _)
  | dedup _ _ _ _ _ => exact NoLoss.of_subset (Finset.subset_insert _ _)
  | drop _ hnl => exact hnl
  | instRemove _ hnl => exact hnl
  | emptyRemove _ hnl => exact hnl
  | concRemove _ hnl => exact hnl
  | requeue _ _ hnl => exact hnl

theorem LoopStrictRun.sat {G G' : System} (h : LoopStrictRun G G') : SSat G → SSat G' := by
  induction h with
  | refl => exact id
  | tail _ hstep ih => exact fun hs => hstep.sat (ih hs)

/-- **A whole run loses nothing.** -/
theorem LoopStrictRun.no_loss {G G' : System} (h : LoopStrictRun G G') : NoLoss G G' := by
  induction h with
  | refl => exact NoLoss.refl _
  | tail _ hstep ih => exact ih.trans hstep.no_loss

/-! ## 5. The vocabulary: only a MINT can enlarge it

This is what `L5-REVIEW.md` F1 asked for.  Round 1's constructors admitted arbitrary
satisfiability-preserving addition, so `(allVars ·).card` was unbounded along a run from a
fixed system (the reviewer's `no_mint_bound_along_strict`).  With the operators in place the
only constructors that touch the vocabulary are the four built on the library's minting
relations, and each adds at most one variable. -/

/-- A step built on one of the library's MINTING relations.  `K2SplitStep` and `K2ResStep`
have reuse branches that mint nothing; the predicate is deliberately coarse, so
`allVars_subset_of_notMint` is the strongest of the two statements. -/
def IsMint (G G' : System) : Prop :=
  K2SplitStep G G' ∨ ResStep G G' ∨ SplitStep G G' ∨ K2ResStep G G'

/-- **A `LoopStrict` step that is not built on a minting relation adds no variable.** -/
theorem LoopStrict.allVars_subset_of_notMint {G G' : System} (h : LoopStrict G G')
    (hm : ¬ IsMint G G') : allVars G' ⊆ allVars G := by
  cases h with
  | nongen h => exact (NonGenStep.allVars_eq h).subset
  | split h => exact absurd (Or.inl h) hm
  | res h => exact absurd (Or.inr (Or.inl h)) hm
  | splitFree h => exact absurd (Or.inr (Or.inr (Or.inl h))) hm
  | kres h => exact absurd (Or.inr (Or.inr (Or.inr h))) hm
  | renameLhs h1 h2 =>
    refine allVars_insert_subset ?_ ?_
    · rw [lhs_mk]
      exact mem_allVars h2 (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self _))
    · rw [vset_mk]
      intro w hw; exact mem_allVars h1 (Or.inr (by rw [vset_mk]; exact hw))
  | linkSymm h1 =>
    refine allVars_insert_subset ?_ ?_
    · rw [lhs_mk]
      exact mem_allVars h1 (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self _))
    · rw [vset_mk]
      intro w hw
      rw [Finset.mem_singleton] at hw; subst hw
      exact lhs_mem_allVars h1
  | emptyProp h1 _ hx =>
    refine allVars_insert_subset ?_ ?_
    · rw [lhs_mk]; exact mem_allVars h1 (Or.inr (by rw [vset_mk]; exact hx))
    · rw [vset_mk]; exact fun w hw => absurd hw (Finset.notMem_empty w)
  | dedup h1 _ _ hx _ =>
    refine allVars_insert_subset ?_ ?_
    · rw [lhs_mk]
      exact mem_allVars h1 (Or.inr (by rw [vset_mk]; exact Finset.mem_of_mem_erase hx))
    · rw [vset_mk]; exact fun w hw => absurd hw (Finset.notMem_empty w)
  | drop hsub _ => exact allVars_mono hsub
  | instRemove hlink _ => exact allVars_substOut_subset hlink
  | emptyRemove hv _ => exact allVars_makeEmptyE_subset hv
  | concRemove hv _ => exact allVars_concretizeSrs_subset hv
  | requeue hv _ _ => exact hv

/-- A `ResStep` adds exactly the fresh name. -/
theorem resStep_allVars_eq_insert {G G' : System} (h : ResStep G G') :
    ∃ z, allVars G' = insert z (allVars G) := by
  cases h with
  | @intro v x y C D z happ =>
    exact ⟨z, allVars_resResult z (lhs_mem_allVars happ.mem₁)
      (mem_allVars happ.mem₁ (Or.inr (by simp))) (mem_allVars happ.mem₂ (Or.inr (by simp)))⟩

/-- **A minting step adds at most one variable.** -/
theorem IsMint.allVars_card_le {G G' : System} (h : IsMint G G') :
    (allVars G').card ≤ (allVars G).card + 1 := by
  have key : allVars G' = allVars G ∨ ∃ w, allVars G' = insert w (allVars G) := by
    rcases h with h | h | h | h
    · rcases h.allVars_cases with h' | ⟨w, -, h'⟩
      · exact Or.inl h'
      · exact Or.inr ⟨w, h'⟩
    · obtain ⟨z, hz⟩ := resStep_allVars_eq_insert h; exact Or.inr ⟨z, hz⟩
    · obtain ⟨u, -, hu⟩ := h.allVars_eq_insert; exact Or.inr ⟨u, hu⟩
    · rcases h.allVars_cases with h' | ⟨w, -, h'⟩
      · exact Or.inl h'
      · exact Or.inr ⟨w, h'⟩
  rcases key with h' | ⟨w, h'⟩
  · rw [h']; omega
  · rw [h']; exact Finset.card_insert_le _ _

/-- **Every `LoopStrict` step adds at most one variable.** -/
theorem LoopStrict.allVars_card_le {G G' : System} (h : LoopStrict G G') :
    (allVars G').card ≤ (allVars G).card + 1 := by
  by_cases hm : IsMint G G'
  · exact hm.allVars_card_le
  · exact le_trans (Finset.card_le_card (h.allVars_subset_of_notMint hm)) (by omega)

/-- A run of `LoopStrict` in which exactly `m` steps are built on a minting relation. -/
inductive LoopStrictSteps : Nat → System → System → Prop
  | refl (G : System) : LoopStrictSteps 0 G G
  | keep {m : Nat} {G G' G'' : System} :
      LoopStrictSteps m G G' → LoopStrict G' G'' → allVars G'' ⊆ allVars G' →
      LoopStrictSteps m G G''
  | mint {m : Nat} {G G' G'' : System} :
      LoopStrictSteps m G G' → LoopStrict G' G'' → LoopStrictSteps (m + 1) G G''

theorem LoopStrictSteps.toRun {m : Nat} {G G' : System} (h : LoopStrictSteps m G G') :
    LoopStrictRun G G' := by
  induction h with
  | refl => exact Relation.ReflTransGen.refl
  | keep _ hstep _ ih => exact ih.tail hstep
  | mint _ hstep ih => exact ih.tail hstep

/-- **Every run is counted**: the mint count exists. -/
theorem LoopStrictRun.toSteps {G G' : System} (h : LoopStrictRun G G') :
    ∃ m, LoopStrictSteps m G G' := by
  induction h with
  | refl => exact ⟨0, LoopStrictSteps.refl _⟩
  | @tail b c _ hstep ih =>
    obtain ⟨m, hm⟩ := ih
    by_cases hmi : allVars c ⊆ allVars b
    · exact ⟨m, LoopStrictSteps.keep hm hstep hmi⟩
    · exact ⟨m + 1, LoopStrictSteps.mint hm hstep⟩

/-- **THE VOCABULARY BOUND.**  Along a `LoopStrict` run the vocabulary is bounded by the
vocabulary of the system it started from plus the number of MINTING steps.  This is what
`L5-REVIEW.md` F1 asks for, and it is what Round 1's relation did not have. -/
theorem LoopStrictSteps.allVars_card_le {m : Nat} {G G' : System}
    (h : LoopStrictSteps m G G') : (allVars G').card ≤ (allVars G).card + m := by
  induction h with
  | refl => omega
  | keep _ _ hnm ih => exact le_trans (Finset.card_le_card hnm) ih
  | mint _ hstep ih =>
    have := hstep.allVars_card_le
    omega

/-- ... and a MINT-FREE run does not touch the vocabulary at all. -/
theorem LoopStrictSteps.allVars_subset {m : Nat} {G G' : System} (h : LoopStrictSteps m G G') :
    m = 0 → allVars G' ⊆ allVars G := by
  induction h with
  | refl => intro _; exact Finset.Subset.refl _
  | keep _ _ hnm ih => intro hm; exact hnm.trans (ih hm)
  | mint _ _ _ => intro hm; exact absurd hm (by omega)

/-- A run none of whose steps is built on one of the library's MINTING relations. -/
inductive MintFreeRun : System → System → Prop
  | refl (G : System) : MintFreeRun G G
  | tail {G G' G'' : System} :
      MintFreeRun G G' → LoopStrict G' G'' → ¬ IsMint G' G'' → MintFreeRun G G''

theorem MintFreeRun.toSteps {G G' : System} (h : MintFreeRun G G') :
    LoopStrictSteps 0 G G' := by
  induction h with
  | refl => exact LoopStrictSteps.refl _
  | tail _ hstep hnm ih =>
    exact LoopStrictSteps.keep ih hstep (hstep.allVars_subset_of_notMint hnm)

theorem MintFreeRun.allVars_subset {G G' : System} (h : MintFreeRun G G') :
    allVars G' ⊆ allVars G := h.toSteps.allVars_subset rfl

/-- **The refutation of `L5-REVIEW.md`'s `no_mint_bound_along_strict`.**  Its witness runs from
the fixed satisfiable system `{0 <- ()}` to systems of unbounded vocabulary using `emptyRemove`
alone.  With `emptyRemove` restated as the library operator, no MINT-FREE run out of that
system reaches more than one variable. -/
theorem no_growth_without_mint {G' : System}
    (h : MintFreeRun {mk 0 ∅ (∅ : Row)} G') : (allVars G').card ≤ 1 := by
  have hsub := h.allVars_subset
  have hav : allVars {mk 0 ∅ (∅ : Row)} ⊆ {0} := by
    intro w hw
    obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
    rw [Finset.mem_singleton] at hc
    subst hc
    rw [lhs_mk, vset_mk] at hwc
    rcases Finset.mem_insert.mp hwc with rfl | h
    · exact Finset.mem_singleton_self _
    · exact absurd h (Finset.notMem_empty w)
  exact le_trans (Finset.card_le_card (hsub.trans hav)) (by simp)


/-! ## 7. The library operators as `LoopStrict` steps -/

/-- Systems all of whose constraints are `mk`-shaped -- which every `sys s` is, because
`LPart.toConstraint` and `EnvVal.toConstraint` both build one. -/
def MkShaped (G : System) : Prop := ∀ c ∈ G, c = mk c.lhs (vset c) c.conc

/-- If `v` is known EMPTY, erasing it from a right-hand side loses nothing. -/
theorem sat_of_erase' {rho : Assign} {a v : Var} {S : Finset Var} {K : Row}
    (hv : rho v = ∅) (h : Sat rho (mk a (S.erase v) K)) : Sat rho (mk a S K) := by
  rw [sat_mk_iff] at h ⊢
  obtain ⟨he, hk, hd⟩ := h
  have hbi : S.biUnion rho = (S.erase v).biUnion rho := by
    ext l
    simp only [Finset.mem_biUnion, Finset.mem_erase]
    constructor
    · rintro ⟨w, hw, hl⟩
      by_cases hwv : w = v
      · rw [hwv, hv] at hl; exact absurd hl (Finset.notMem_empty l)
      · exact ⟨w, ⟨hwv, hw⟩, hl⟩
    · rintro ⟨w, ⟨-, hw⟩, hl⟩; exact ⟨w, hw, hl⟩
  refine ⟨by rw [he, hbi], fun w hw => ?_, fun w hw z hz hwz => ?_⟩
  · by_cases hwv : w = v
    · rw [hwv, hv]; exact Finset.disjoint_empty_right K
    · exact hk w (Finset.mem_erase.mpr ⟨hwv, hw⟩)
  · by_cases hwv : w = v
    · rw [hwv, hv]; exact Finset.disjoint_empty_left (rho z)
    · by_cases hzv : z = v
      · rw [hzv, hv]; exact Finset.disjoint_empty_right (rho w)
      · exact hd w (Finset.mem_erase.mpr ⟨hwv, hw⟩) z (Finset.mem_erase.mpr ⟨hzv, hz⟩) hwz

/-- An all-variable partition whose whole and whose every part are empty is satisfied. -/
theorem sat_of_allEmpty' {rho : Assign} {a : Var} {S : Finset Var}
    (ha : rho a = ∅) (hS : ∀ w ∈ S, rho w = ∅) : Sat rho (mk a S (∅ : Row)) := by
  rw [sat_mk_iff]
  refine ⟨?_, fun w _ => Finset.disjoint_empty_left (rho w), fun w hw z _ _ => ?_⟩
  · rw [ha]
    symm
    refine Finset.eq_empty_of_forall_notMem (fun l hl => ?_)
    rcases Finset.mem_union.mp hl with hl' | hl'
    · exact absurd hl' (Finset.notMem_empty l)
    · obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp hl'
      rw [hS w hw] at hlw
      exact absurd hlw (Finset.notMem_empty l)
  · rw [hS w hw]; exact Finset.disjoint_empty_left (rho z)

/-- **`makeEmptyE` loses nothing** on a `mk`-shaped system in which no constraint defines `v`
with a concrete part -- which is exactly the `die` arm `makeEmpty` rejects
(`makeEmpty_conc_unsat`: such a system has no model anyway). -/
theorem makeEmptyE_noLoss {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    NoLoss G (makeEmptyE v G) := by
  intro c hc rho hm
  have hvE : mk v ∅ (∅ : Row) ∈ makeEmptyE v G := mem_makeEmptyE.mpr (Or.inl rfl)
  have hv0 : rho v = ∅ := sat_empty_iff.mp (hm _ hvE)
  have hcs : c = mk c.lhs (vset c) c.conc := hshape c hc
  by_cases hlhs : c.lhs = v
  · -- the PROPAGATION: `v`'s definition has no concrete part, so every part is empty
    have hconc : c.conc = ∅ := hdefs c hc hlhs
    rw [hcs, hconc]
    refine sat_of_allEmpty' (by rw [hlhs]; exact hv0) (fun w hw => ?_)
    have hmem : mk w ∅ (∅ : Row) ∈ makeEmptyE v G :=
      mem_makeEmptyE.mpr (Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inr
        ⟨c, hc, hlhs, hconc, w, hw, rfl⟩))))
    exact sat_empty_iff.mp (hm _ hmem)
  · by_cases hvin : v ∈ vset c
    · -- the ERASURE
      have hmem : mk c.lhs ((vset c).erase v) c.conc ∈ makeEmptyE v G :=
        mem_makeEmptyE.mpr (Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inl
          ⟨c, hc, hlhs, hvin, rfl⟩))))
      rw [hcs]
      exact sat_of_erase' hv0 (hm _ hmem)
    · -- KEPT verbatim
      exact hm _ (mem_makeEmptyE.mpr (Or.inr (mem_makeEmptyD.mpr (Or.inl ⟨hc, hlhs, hvin⟩))))

/-- **`makeEmptyE` IS a `LoopStrict` step**, on the systems the loop's `empty` branch reaches:
this is the constructor `L5-REVIEW.md` §10(1) names, applied. -/
theorem emptyRemove_step {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    LoopStrict G (makeEmptyE v G) :=
  LoopStrict.emptyRemove hv (makeEmptyE_noLoss hshape hv hdefs)

/-! ## 8. `LoopStrict` against `LoopRel` -/

/-- **Every ADDITIVE `LoopRel` step is a `LoopStrict` step.**  All nine of `LoopRel`'s RULE
constructors are additive, and a `weaken` step that is additive is the identity -- so this says
exactly that `LoopStrict` restricts `LoopRel` in its DELETIONS and nowhere else, and it is what
makes the nine rule constructors of `LoopStrict` live. -/
theorem LoopStrict.of_rel {G G' : System} (h : LoopRel G G') (hsub : G ⊆ G') :
    LoopStrictRun G G' := by
  cases h with
  | nongen h => exact Relation.ReflTransGen.single (LoopStrict.nongen h)
  | split h => exact Relation.ReflTransGen.single (LoopStrict.split h)
  | res h => exact Relation.ReflTransGen.single (LoopStrict.res h)
  | splitFree h => exact Relation.ReflTransGen.single (LoopStrict.splitFree h)
  | kres h => exact Relation.ReflTransGen.single (LoopStrict.kres h)
  | renameLhs h1 h2 => exact Relation.ReflTransGen.single (LoopStrict.renameLhs h1 h2)
  | linkSymm h1 => exact Relation.ReflTransGen.single (LoopStrict.linkSymm h1)
  | emptyProp h1 h2 hx => exact Relation.ReflTransGen.single (LoopStrict.emptyProp h1 h2 hx)
  | dedup h1 h2 hv hx hx' =>
      exact Relation.ReflTransGen.single (LoopStrict.dedup h1 h2 hv hx hx')
  | weaken hs =>
    have heq : G = G' := Finset.Subset.antisymm hsub hs
    subst heq
    exact Relation.ReflTransGen.refl

/-- ... and every subset-shaped `LoopStrict` step is a `LoopRel.weaken` step. -/
theorem LoopStrict.toRel_of_subset {G G' : System} (hsub : G' ⊆ G) : LoopRel G G' :=
  LoopRel.weaken hsub

/-- **`LoopRel.weaken` is not a `LoopStrict` step.**  Deleting the only constraint of
`{0 <- ((|1|))}` is a `weaken` step; it is not a `LoopStrict` step, because the empty system
does not entail `0 <- ((|1|))`. -/
theorem weaken_not_strict :
    ∃ G G' : System, LoopRel G G' ∧ ¬ NoLoss G G' := by
  refine ⟨{mk 0 ∅ ({1} : Row)}, ∅, LoopRel.weaken (Finset.empty_subset _), ?_⟩
  intro hnl
  have h := hnl (mk 0 ∅ ({1} : Row)) (Finset.mem_singleton_self _) (fun _ => (∅ : Row))
    (fun c hc => absurd hc (Finset.notMem_empty c))
  rw [sat_mk_iff] at h
  have h1 : (1 : Label) ∈ (∅ : Row) := by rw [h.1]; simp
  exact absurd h1 (Finset.notMem_empty 1)

/-- ... and therefore no `LoopStrict` step performs it. -/
theorem weaken_not_strict' : ¬ LoopStrict {mk 0 ∅ ({1} : Row)} ∅ := by
  intro h
  have hs := h.no_loss (mk 0 ∅ ({1} : Row)) (Finset.mem_singleton_self _)
    (fun _ => (∅ : Row)) (fun c hc => absurd hc (Finset.notMem_empty c))
  rw [sat_mk_iff] at hs
  have h1 : (1 : Label) ∈ (∅ : Row) := by rw [hs.1]; simp
  exact absurd h1 (Finset.notMem_empty 1)

end Rowpartition.Loop
