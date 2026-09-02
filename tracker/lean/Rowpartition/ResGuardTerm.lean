/-
# The guarded resolution rule terminates on every satisfiable system

`ResGuard.lean` adds to `resolution` (`Constraints.scala`, `def resolution`) the reverse lookup that
`splitConcrete` already has: mint a fresh name for the resolvent `v \ (C ∪ D)` only when
`G` does not already carry one.  That file settles the SEMANTICS of the repair (the guard
moves neither the model set nor the entailed constraints).  This file settles the positive
half of its TERMINATION.

The argument has two halves, and neither works alone.

* **Combinatorial.**  Under the guard a mint for the pair (left-hand side `v`, resolvent
  key `K = C ∪ D`) can fire at most once: afterwards `mk v {z} K ∈ G`, so `Resolved G v K`
  holds, and the system only grows.  All concrete parts stay inside the finite label set
  `L` of the input, because the rule forms only `C ∪ D`, `D \ C`, `C \ D` (`ConcSub`).
  So each variable carries a budget of at most `2 ^ L.card` mints (`unfired`).
* **Semantic.**  That alone bounds nothing, because minting CREATES variables, each with a
  fresh budget.  What bounds it is the model: `mk v {z} K` forces `rho z = rho v \ K`, and
  the rule's own guard `tops ≠ ∅` forces `K` to meet `rho v`, so the minted variable's row
  is STRICTLY SMALLER than its parent's.

Weighting each variable's remaining budget by a large power of the cardinality of the row
it denotes therefore gives a measure that a mint strictly decreases and a reuse does not
increase (`gmeas`).  Hence `GRun.length_le` and `guarded_terminates_of_satisfiable`: from a
satisfiable input, every run of the guarded rule that actually enlarges the system has
length at most `((allVars G₀).card + gmeas L rho G₀) ^ 2 * 2 ^ L.card`.

Nothing here is claimed about UNSATISFIABLE systems: the measure is defined against a
model, and without one the whole argument evaporates.  That case is the subject of
`ResGuardDiverge.lean`; see the Summary at the end.
-/
import Rowpartition.ResGuard
import Rowpartition.Compare

namespace Rowpartition

/-! ## 1. The concrete parts never leave a fixed finite label set -/

/-- Every label occurring in a concrete part of the system. -/
def labelsOf (G : System) : Finset Label := G.biUnion Constraint.conc

/-- `ConcSub L G`: every concrete part of `G` is drawn from the label set `L`. -/
def ConcSub (L : Finset Label) (G : System) : Prop := ∀ c ∈ G, c.conc ⊆ L

/-- A system's own labels bound it. -/
theorem labelsOf_concSub (G : System) : ConcSub (labelsOf G) G :=
  fun _ hc => Finset.subset_biUnion_of_mem Constraint.conc hc

/-- Fewer constraints, fewer labels. -/
theorem ConcSub.mono {L : Finset Label} {G G' : System} (h : ConcSub L G) (hsub : G' ⊆ G) :
    ConcSub L G' := fun c hc => h c (hsub hc)

/-- **The guarded rule invents no label.**  Both branches emit only `C ∪ D`, `D \ C` and
`C \ D`, built from concrete parts already in the system, so the label set of the input is
an invariant of the whole run. -/
theorem GResStep.concSub {L : Finset Label} {G G' : System} (h : GResStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @mint v x y C D z hp _ _ =>
    have hC : C ⊆ L := hcs _ hp.mem₁
    have hD : D ⊆ L := hcs _ hp.mem₂
    intro c hc
    simp only [resResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | rfl | hc
    · exact Finset.union_subset hC hD
    · exact Finset.sdiff_subset.trans hD
    · exact Finset.sdiff_subset.trans hC
    · exact hcs c hc
  | @reuse v x y C D z hp _ =>
    have hC : C ⊆ L := hcs _ hp.mem₁
    have hD : D ⊆ L := hcs _ hp.mem₂
    intro c hc
    simp only [resReuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact Finset.sdiff_subset.trans hD
    · exact Finset.sdiff_subset.trans hC
    · exact hcs c hc

/-! ## 2. What the two branches do to the vocabulary -/

/-- Adding a constraint with one variable part, whose left-hand side is already known,
adds exactly that one variable. -/
theorem allVars_insert_lone {G : System} {a b : Var} {K : Row} (ha : a ∈ allVars G) :
    allVars (insert (mk a {b} K) G) = insert b (allVars G) := by
  rw [allVars_insert]
  ext u
  simp only [lhs_mk, vset_mk, Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  constructor
  · rintro ((rfl | rfl) | hu)
    · exact Or.inr ha
    · exact Or.inl rfl
    · exact Or.inr hu
  · rintro (rfl | hu)
    · exact Or.inl (Or.inr rfl)
    · exact Or.inr hu

/-- **A mint adds exactly one variable**: the fresh name, and nothing else. -/
theorem allVars_resResult {G : System} {v x y : Var} {C D : Row} (z : Var)
    (hv : v ∈ allVars G) (hx : x ∈ allVars G) (hy : y ∈ allVars G) :
    allVars (resResult G v x y C D z) = insert z (allVars G) := by
  have h3 : allVars (insert (mk y {z} (C \ D)) G) = insert z (allVars G) :=
    allVars_insert_lone hy
  have h2 : allVars (insert (mk x {z} (D \ C)) (insert (mk y {z} (C \ D)) G))
      = insert z (allVars G) := by
    rw [allVars_insert_lone (by rw [h3]; exact Finset.mem_insert_of_mem hx), h3,
      Finset.insert_idem]
  rw [resResult, allVars_insert_lone (by rw [h2]; exact Finset.mem_insert_of_mem hv), h2,
    Finset.insert_idem]

/-- **A reuse adds no variable at all**: that is the point of the guard. -/
theorem allVars_resReuseResult {G : System} {x y z : Var} {C D : Row}
    (hx : x ∈ allVars G) (hy : y ∈ allVars G) (hz : z ∈ allVars G) :
    allVars (resReuseResult G x y C D z) = allVars G := by
  have h2 : allVars (insert (mk y {z} (C \ D)) G) = allVars G := by
    rw [allVars_insert_lone hy, Finset.insert_eq_self.mpr hz]
  rw [resReuseResult, allVars_insert_lone (by rw [h2]; exact hx), h2,
    Finset.insert_eq_self.mpr hz]

/-! ## 3. The budget: how many resolvent keys are still open at a variable -/

/-- The number of resolvent keys at `v` that the guard has NOT yet closed off: the subsets
of `L` for which `G` carries no name of `v \ K`.  This counts what is LEFT rather than what
is done, so that the measure below needs no truncated subtraction. -/
def unfired (L : Finset Label) (G : System) (v : Var) : ℕ :=
  (L.powerset.filter (fun K => ¬ Resolved G v K)).card

/-- A variable's budget is at most the number of subsets of `L`. -/
theorem unfired_le_pow (L : Finset Label) (G : System) (v : Var) :
    unfired L G v ≤ 2 ^ L.card := by
  rw [unfired, ← Finset.card_powerset L]
  exact Finset.card_filter_le _ _

/-- **Budgets only shrink.**  The guard is monotone in the system, so a larger system has
closed off at least as many keys. -/
theorem unfired_le {L : Finset Label} {G G' : System} (hsub : G ⊆ G') (v : Var) :
    unfired L G' v ≤ unfired L G v := by
  refine Finset.card_le_card ?_
  intro K hK
  rw [Finset.mem_filter] at hK ⊢
  exact ⟨hK.1, fun hr => hK.2 (hr.mono hsub)⟩

/-- **A mint spends one unit of budget.**  If the guard was open at the key `K ⊆ L` and the
successor system names `v \ K`, the budget at `v` has strictly dropped.  This is the exact
analogue of `Cut.SplitStep.cands_lt` for `resolution`'s reverse lookup. -/
theorem unfired_lt {L : Finset Label} {G G' : System} {v z : Var} {K : Row}
    (hsub : G ⊆ G') (hKL : K ⊆ L) (hg : ¬ Resolved G v K) (hmem : mk v {z} K ∈ G') :
    unfired L G' v + 1 ≤ unfired L G v := by
  have hss : L.powerset.filter (fun J => ¬ Resolved G' v J)
      ⊆ (L.powerset.filter (fun J => ¬ Resolved G v J)).erase K := by
    intro J hJ
    rw [Finset.mem_filter] at hJ
    refine Finset.mem_erase.mpr
      ⟨?_, Finset.mem_filter.mpr ⟨hJ.1, fun hr => hJ.2 (hr.mono hsub)⟩⟩
    rintro rfl
    exact hJ.2 (resolved_of_mem hmem)
  have hKmem : K ∈ L.powerset.filter (fun J => ¬ Resolved G v J) :=
    Finset.mem_filter.mpr ⟨Finset.mem_powerset.mpr hKL, hg⟩
  exact lt_of_le_of_lt (Finset.card_le_card hss) (Finset.card_erase_lt_of_mem hKmem)

/-! ## 4. The arithmetic that makes the weights work

One step down in the exponent buys a whole budget's worth of weight.  That is why a mint,
which spends one unit at the parent but hands a full fresh budget to the minted variable,
still decreases the total: the minted variable denotes a strictly smaller row. -/

/-- With base `B + 1`, a full budget `B` at any exponent is beaten by a single unit at any
strictly larger one. -/
theorem budget_mul_pow_lt (B : ℕ) {k r : ℕ} (h : k < r) :
    B * (B + 1) ^ k < (B + 1) ^ r := by
  have hpos : 0 < (B + 1) ^ k := Nat.pow_pos (Nat.succ_pos B)
  have hmul : (B + 1) ^ k * (B + 1) = B * (B + 1) ^ k + (B + 1) ^ k := by
    rw [Nat.mul_add, Nat.mul_one, Nat.mul_comm ((B + 1) ^ k) B]
  calc B * (B + 1) ^ k < B * (B + 1) ^ k + (B + 1) ^ k := Nat.lt_add_of_pos_right hpos
    _ = (B + 1) ^ k * (B + 1) := hmul.symm
    _ = (B + 1) ^ (k + 1) := (pow_succ _ _).symm
    _ ≤ (B + 1) ^ r := Nat.pow_le_pow_right (Nat.succ_pos B) h

/-! ## 5. The measure, and what the two branches do to it -/

/-- The termination measure: each variable's remaining budget, weighted by a power of the
cardinality of the row it denotes.  The base `2 ^ L.card + 1` is one more than the largest
budget, so that one step down in the exponent outweighs a whole budget — which is exactly
what a mint costs and what it buys. -/
def gmeas (L : Finset Label) (rho : Assign) (G : System) : ℕ :=
  ∑ v ∈ allVars G, unfired L G v * (2 ^ L.card + 1) ^ (rho v).card

/-- The measure only reads the assignment on the system's own vocabulary. -/
theorem gmeas_congr {L : Finset Label} {rho rho' : Assign} {G : System}
    (h : ∀ u ∈ allVars G, rho u = rho' u) : gmeas L rho G = gmeas L rho' G :=
  Finset.sum_congr rfl fun u hu => by rw [h u hu]

/-- Splitting a sum off at one member of the index set. -/
theorem sum_erase_split {s : Finset Var} {v : Var} (hv : v ∈ s) (f : Var → ℕ) :
    ∑ u ∈ s, f u = f v + ∑ u ∈ s.erase v, f u := by
  have h := Finset.sum_insert (f := f) (Finset.notMem_erase v s)
  rw [Finset.insert_erase hv] at h
  exact h

/-- **The minted variable denotes a strictly smaller row than the variable it splits.**
The resolvent constraint `v <- (z, C ∪ D)` forces `rho z = rho v \ (C ∪ D)`, and the rule's
own guard `tops = C \ D ≠ ∅` supplies a label of `C ⊆ rho v` that `rho z` must omit.  This
is the semantic half of the termination argument, and the half that fails without a
model. -/
theorem mint_rank_lt {G : System} {v x y z : Var} {C D : Row} {rho : Assign}
    (hp : ResPair G v x y C D) (hm : SModels rho (resResult G v x y C D z)) :
    (rho z).card < (rho v).card := by
  have hmem : mk v {z} (C ∪ D) ∈ resResult G v x y C D z := Finset.mem_insert_self _ _
  have hres := hm _ hmem
  rw [sat_lone_iff] at hres
  obtain ⟨heq, hdis⟩ := hres
  obtain ⟨l, hl⟩ := Finset.nonempty_iff_ne_empty.mpr hp.tops
  have hlCD : l ∈ C ∪ D := Finset.mem_union_left _ (Finset.mem_sdiff.mp hl).1
  have hlv : l ∈ rho v := by rw [heq]; exact Finset.mem_union_left _ hlCD
  have hlz : l ∉ rho z := Finset.disjoint_left.mp hdis hlCD
  have hsub : rho z ⊆ rho v := by rw [heq]; exact Finset.subset_union_right
  exact Finset.card_lt_card ((Finset.ssubset_iff_of_subset hsub).mpr ⟨l, hlv, hlz⟩)

/-- **A mint strictly decreases the measure.**  The parent `v` pays one unit of budget at
weight `Φ ^ (rho v).card`; the minted variable `z` receives a whole fresh budget, but at
weight `Φ ^ (rho z).card` with `(rho z).card < (rho v).card`, and a whole budget there is
worth less than the single unit the parent gave up.  Every other variable's budget can only
have shrunk. -/
theorem GResStep.mint_gmeas_lt {L : Finset Label} {G G' : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hg : ¬ Resolved G v (C ∪ D)) (hz : z ∉ allVars G)
    (hcs : ConcSub L G) {rho : Assign} (hG' : G' = resResult G v x y C D z)
    (hm : SModels rho G') : gmeas L rho G' < gmeas L rho G := by
  have hm' : SModels rho (resResult G v x y C D z) := by rw [← hG']; exact hm
  have hv : v ∈ allVars G := lhs_mem_allVars hp.mem₁
  have hx : x ∈ allVars G := mem_allVars hp.mem₁ (Or.inr (by simp))
  have hy : y ∈ allVars G := mem_allVars hp.mem₂ (Or.inr (by simp))
  have hsub : G ⊆ G' := by rw [hG']; exact subset_resResult _ _ _ _ _ _ _
  have hmem : mk v {z} (C ∪ D) ∈ G' := by rw [hG']; exact Finset.mem_insert_self _ _
  have hAV : allVars G' = insert z (allVars G) := by
    rw [hG']; exact allVars_resResult z hv hx hy
  have hCL : C ⊆ L := hcs _ hp.mem₁
  have hDL : D ⊆ L := hcs _ hp.mem₂
  have hrank : (rho z).card < (rho v).card := mint_rank_lt hp hm'
  -- the minted variable's entire budget is worth less than one unit at the parent
  have hzterm : unfired L G' z * (2 ^ L.card + 1) ^ (rho z).card
      < (2 ^ L.card + 1) ^ (rho v).card :=
    lt_of_le_of_lt (Nat.mul_le_mul (unfired_le_pow L G' z) (Nat.le_refl _))
      (budget_mul_pow_lt (2 ^ L.card) hrank)
  -- the parent pays one unit
  have hvterm : unfired L G' v * (2 ^ L.card + 1) ^ (rho v).card
      + (2 ^ L.card + 1) ^ (rho v).card
      ≤ unfired L G v * (2 ^ L.card + 1) ^ (rho v).card := by
    have h1 : unfired L G' v + 1 ≤ unfired L G v :=
      unfired_lt hsub (Finset.union_subset hCL hDL) hg hmem
    have h2 : (unfired L G' v + 1) * (2 ^ L.card + 1) ^ (rho v).card
        ≤ unfired L G v * (2 ^ L.card + 1) ^ (rho v).card :=
      Nat.mul_le_mul h1 (Nat.le_refl _)
    rw [Nat.add_mul, Nat.one_mul] at h2
    exact h2
  -- everybody else's budget only shrank
  have hrest : ∑ u ∈ (allVars G).erase v, unfired L G' u * (2 ^ L.card + 1) ^ (rho u).card
      ≤ ∑ u ∈ (allVars G).erase v, unfired L G u * (2 ^ L.card + 1) ^ (rho u).card :=
    Finset.sum_le_sum fun u _ => Nat.mul_le_mul (unfired_le hsub u) (Nat.le_refl _)
  -- assemble
  have hsplitG : gmeas L rho G
      = unfired L G v * (2 ^ L.card + 1) ^ (rho v).card
        + ∑ u ∈ (allVars G).erase v, unfired L G u * (2 ^ L.card + 1) ^ (rho u).card :=
    sum_erase_split hv (fun u => unfired L G u * (2 ^ L.card + 1) ^ (rho u).card)
  have hsplit2 : ∑ u ∈ allVars G, unfired L G' u * (2 ^ L.card + 1) ^ (rho u).card
      = unfired L G' v * (2 ^ L.card + 1) ^ (rho v).card
        + ∑ u ∈ (allVars G).erase v, unfired L G' u * (2 ^ L.card + 1) ^ (rho u).card :=
    sum_erase_split hv (fun u => unfired L G' u * (2 ^ L.card + 1) ^ (rho u).card)
  have hsplitG' : gmeas L rho G'
      = unfired L G' z * (2 ^ L.card + 1) ^ (rho z).card
        + (unfired L G' v * (2 ^ L.card + 1) ^ (rho v).card
          + ∑ u ∈ (allVars G).erase v, unfired L G' u * (2 ^ L.card + 1) ^ (rho u).card) := by
    rw [gmeas, hAV, Finset.sum_insert hz, hsplit2]
  rw [hsplitG, hsplitG']
  omega

/-- **A reuse does not increase the measure.**  It introduces no variable and changes no
assignment; it can only close off further keys. -/
theorem GResStep.reuse_gmeas_le {L : Finset Label} {G G' : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hr : mk v {z} (C ∪ D) ∈ G)
    (hG' : G' = resReuseResult G x y C D z) (rho : Assign) :
    gmeas L rho G' ≤ gmeas L rho G := by
  have hx : x ∈ allVars G := mem_allVars hp.mem₁ (Or.inr (by simp))
  have hy : y ∈ allVars G := mem_allVars hp.mem₂ (Or.inr (by simp))
  have hz : z ∈ allVars G := mem_allVars hr (Or.inr (by simp))
  have hsub : G ⊆ G' := by rw [hG']; exact subset_resReuseResult _ _ _ _ _ _
  have hAV : allVars G' = allVars G := by
    rw [hG']; exact allVars_resReuseResult hx hy hz
  rw [gmeas, gmeas, hAV]
  exact Finset.sum_le_sum fun u _ => Nat.mul_le_mul (unfired_le hsub u) (Nat.le_refl _)

/-! ## 6. Runs of the guarded rule -/

/-- A run of the guarded rule in which every step really enlarges the system.  Without that
side condition a "run" can idle forever, re-deriving constraints already present; that is
not divergence, and every implementation deduplicates.  `Cut.CutChain` carries the same
condition for the same reason. -/
inductive GRun : ℕ → System → System → Prop
  | refl (G : System) : GRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      GRun n G₀ G → GResStep G G' → G ⊂ G' → GRun (n + 1) G₀ G'

/-- A run only adds constraints. -/
theorem GRun.subset {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) : G₀ ⊆ G := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep _ ih => exact ih.trans hstep.subset

/-- A run of length `n` has added at least `n` constraints. -/
theorem GRun.card_ge {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) : G₀.card + n ≤ G.card := by
  induction h with
  | refl => omega
  | @tail n G₀ G G' _hrun _hstep hss ih =>
    have := Finset.card_lt_card hss
    omega

/-- The label set of the input bounds the whole run. -/
theorem GRun.concSub {L : Finset Label} {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) :
    ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hcs => hstep.concSub (ih hcs)

/-- **The invariant that drives the bound.**  Along a run from a SATISFIABLE input, the
number of variables plus the measure never grows: a mint adds one variable and drops the
measure by at least one, a reuse does neither.  The model is carried along, changing only
on freshly minted variables. -/
theorem GRun.invariant {L : Finset Label} {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) :
    ∀ (rho₀ : Assign), SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧
        (allVars G).card + gmeas L rho G ≤ (allVars G₀).card + gmeas L rho₀ G₀ := by
  induction h with
  | refl G =>
    intro rho₀ hm _
    exact ⟨rho₀, hm, Nat.le_refl _⟩
  | @tail n G₀ G G' hrun hstep _hss ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hbound⟩ := ih rho₀ hm hcs
    have hcsG : ConcSub L G := hrun.concSub hcs
    cases hstep with
    | @mint v x y C D z hp hg hzf =>
      obtain ⟨rho', hm', hagree⟩ := mint_extend hp hzf hmr
      have hcong : gmeas L rho' G = gmeas L rho G :=
        (gmeas_congr fun u hu => (hagree u hu).symm).symm
      have hlt : gmeas L rho' (resResult G v x y C D z) < gmeas L rho' G :=
        GResStep.mint_gmeas_lt hp hg hzf hcsG rfl hm'
      have hv : v ∈ allVars G := lhs_mem_allVars hp.mem₁
      have hx : x ∈ allVars G := mem_allVars hp.mem₁ (Or.inr (by simp))
      have hy : y ∈ allVars G := mem_allVars hp.mem₂ (Or.inr (by simp))
      have hcard : (allVars (resResult G v x y C D z)).card = (allVars G).card + 1 := by
        rw [allVars_resResult z hv hx hy]
        exact Finset.card_insert_of_notMem hzf
      exact ⟨rho', hm', by omega⟩
    | @reuse v x y C D z hp hr =>
      have hmr' : SModels rho (resReuseResult G x y C D z) :=
        (GResStep.reuse_models_iff hp hr rho).mpr hmr
      have hle : gmeas L rho (resReuseResult G x y C D z) ≤ gmeas L rho G :=
        GResStep.reuse_gmeas_le hp hr rfl rho
      have hx : x ∈ allVars G := mem_allVars hp.mem₁ (Or.inr (by simp))
      have hy : y ∈ allVars G := mem_allVars hp.mem₂ (Or.inr (by simp))
      have hzz : z ∈ allVars G := mem_allVars hr (Or.inr (by simp))
      have hAV : allVars (resReuseResult G x y C D z) = allVars G :=
        allVars_resReuseResult hx hy hzz
      rw [hAV]
      exact ⟨rho, hmr', by omega⟩

/-- **The vocabulary of a run is bounded by the input alone.**  This is the step the
unguarded rule cannot take: `Cut.ResStep.escapes` says its vocabulary grows without
bound. -/
theorem GRun.allVars_card_le {L : Finset Label} {n : ℕ} {G₀ G : System} (h : GRun n G₀ G)
    (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    (allVars G).card ≤ (allVars G₀).card + gmeas L rho G₀ := by
  obtain ⟨rho', -, hb⟩ := h.invariant rho hm hcs
  omega

/-! ## 7. The shape bound: what a run can possibly contain

The measure bounds the VOCABULARY of a run.  Everything the rule emits has one variable
part and a concrete part inside `L`, so a bounded vocabulary bounds the whole system. -/

/-- Every constraint the guarded rule can emit has this shape: one left-hand variable and
one right-hand variable, both drawn from `V`, and a concrete part drawn from `L`. -/
def unaryForms (V : Finset Var) (L : Finset Label) : System :=
  (V ×ˢ V ×ˢ L.powerset).image (fun t => mk t.1 {t.2.1} t.2.2)

/-- Membership in `unaryForms` is exactly the shape condition. -/
theorem mem_unaryForms {V : Finset Var} {L : Finset Label} {a b : Var} {K : Row}
    (ha : a ∈ V) (hb : b ∈ V) (hK : K ⊆ L) : mk a {b} K ∈ unaryForms V L := by
  refine Finset.mem_image.mpr ⟨(a, b, K), ?_, rfl⟩
  simp only [Finset.mem_product, Finset.mem_powerset]
  exact ⟨ha, hb, hK⟩

/-- A bigger vocabulary admits more shapes. -/
theorem unaryForms_mono {V V' : Finset Var} (h : V ⊆ V') (L : Finset Label) :
    unaryForms V L ⊆ unaryForms V' L := by
  intro c hc
  obtain ⟨t, ht, rfl⟩ := Finset.mem_image.mp hc
  simp only [Finset.mem_product, Finset.mem_powerset] at ht
  exact mem_unaryForms (h ht.1) (h ht.2.1) ht.2.2

/-- There are at most `|V|² · 2^|L|` such shapes. -/
theorem card_unaryForms_le (V : Finset Var) (L : Finset Label) :
    (unaryForms V L).card ≤ V.card * V.card * 2 ^ L.card := by
  refine le_trans Finset.card_image_le ?_
  rw [Finset.card_product, Finset.card_product, Finset.card_powerset]
  exact Nat.le_of_eq (Nat.mul_assoc _ _ _).symm

/-- **Everything a step adds has the unary shape**, over the successor's own vocabulary and
the ambient label set. -/
theorem GResStep.new_unary {L : Finset Label} {G G' : System} (h : GResStep G G')
    (hcs : ConcSub L G) : G' ⊆ G ∪ unaryForms (allVars G') L := by
  cases h with
  | @mint v x y C D z hp _ _ =>
    have hCL : C ⊆ L := hcs _ hp.mem₁
    have hDL : D ⊆ L := hcs _ hp.mem₂
    have hs : G ⊆ resResult G v x y C D z := subset_resResult _ _ _ _ _ _ _
    have hv : v ∈ allVars (resResult G v x y C D z) :=
      allVars_mono hs (lhs_mem_allVars hp.mem₁)
    have hx : x ∈ allVars (resResult G v x y C D z) :=
      allVars_mono hs (mem_allVars hp.mem₁ (Or.inr (by simp)))
    have hy : y ∈ allVars (resResult G v x y C D z) :=
      allVars_mono hs (mem_allVars hp.mem₂ (Or.inr (by simp)))
    have hzz : z ∈ allVars (resResult G v x y C D z) :=
      mem_allVars (Finset.mem_insert_self _ _) (Or.inr (by simp))
    intro c hc
    simp only [resResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | rfl | hc
    · exact Finset.mem_union_right _ (mem_unaryForms hv hzz (Finset.union_subset hCL hDL))
    · exact Finset.mem_union_right _ (mem_unaryForms hx hzz (Finset.sdiff_subset.trans hDL))
    · exact Finset.mem_union_right _ (mem_unaryForms hy hzz (Finset.sdiff_subset.trans hCL))
    · exact Finset.mem_union_left _ hc
  | @reuse v x y C D z hp hr =>
    have hCL : C ⊆ L := hcs _ hp.mem₁
    have hDL : D ⊆ L := hcs _ hp.mem₂
    have hs : G ⊆ resReuseResult G x y C D z := subset_resReuseResult _ _ _ _ _ _
    have hx : x ∈ allVars (resReuseResult G x y C D z) :=
      allVars_mono hs (mem_allVars hp.mem₁ (Or.inr (by simp)))
    have hy : y ∈ allVars (resReuseResult G x y C D z) :=
      allVars_mono hs (mem_allVars hp.mem₂ (Or.inr (by simp)))
    have hzz : z ∈ allVars (resReuseResult G x y C D z) :=
      allVars_mono hs (mem_allVars hr (Or.inr (by simp)))
    intro c hc
    simp only [resReuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact Finset.mem_union_right _ (mem_unaryForms hx hzz (Finset.sdiff_subset.trans hDL))
    · exact Finset.mem_union_right _ (mem_unaryForms hy hzz (Finset.sdiff_subset.trans hCL))
    · exact Finset.mem_union_left _ hc

/-- **A whole run stays inside the input plus the shapes over its own vocabulary.** -/
theorem GRun.subset_unaryForms {L : Finset Label} {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) :
    ConcSub L G₀ → G ⊆ G₀ ∪ unaryForms (allVars G) L := by
  induction h with
  | refl G => exact fun _ => Finset.subset_union_left
  | @tail n G₀ G G' hrun hstep _hss ih =>
    intro hcs
    have hmono : unaryForms (allVars G) L ⊆ unaryForms (allVars G') L :=
      unaryForms_mono (allVars_mono hstep.subset) L
    have hnew : G' ⊆ G ∪ unaryForms (allVars G') L := hstep.new_unary (hrun.concSub hcs)
    intro c hc
    rcases Finset.mem_union.mp (hnew hc) with h1 | h1
    · rcases Finset.mem_union.mp (ih hcs h1) with h2 | h2
      · exact Finset.mem_union_left _ h2
      · exact Finset.mem_union_right _ (hmono h2)
    · exact Finset.mem_union_right _ h1

/-! ## 8. Termination -/

/-- **The length of a run is bounded by the input alone.**  The bound is explicit: the
vocabulary can grow to at most `(allVars G₀).card + gmeas L rho G₀` variables, and the
system to at most the square of that times `2 ^ L.card` constraints, one of which is added
per step. -/
theorem GRun.length_le {L : Finset Label} {n : ℕ} {G₀ G : System} (h : GRun n G₀ G)
    (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    n ≤ ((allVars G₀).card + gmeas L rho G₀) ^ 2 * 2 ^ L.card := by
  have h1 : G₀.card + n ≤ G.card := h.card_ge
  have h2 : G.card ≤ G₀.card + (unaryForms (allVars G) L).card :=
    le_trans (Finset.card_le_card (h.subset_unaryForms hcs)) (Finset.card_union_le _ _)
  have h3 : (unaryForms (allVars G) L).card
      ≤ (allVars G).card * (allVars G).card * 2 ^ L.card := card_unaryForms_le _ _
  have h4 : (allVars G).card ≤ (allVars G₀).card + gmeas L rho G₀ :=
    h.allVars_card_le rho hm hcs
  have h5 : (allVars G).card * (allVars G).card * 2 ^ L.card
      ≤ ((allVars G₀).card + gmeas L rho G₀) ^ 2 * 2 ^ L.card := by
    rw [pow_two]
    exact Nat.mul_le_mul (Nat.mul_le_mul h4 h4) (Nat.le_refl _)
  exact Nat.le_of_add_le_add_left
    (le_trans h1 (le_trans h2 (Nat.add_le_add (Nat.le_refl _) (le_trans h3 h5))))

/-- **The guarded rule terminates on every satisfiable system.**  From a system with a
model there is a bound, computed from the input alone, on the length of every run of the
guarded rule that actually enlarges the system.  Contrast `Cut.resSeed_diverges`: the
UNGUARDED rule admits chains of every length from a two-constraint input, and
`Cut.res_no_decreasing_measure` says no `ℕ`-valued measure can decrease on all its steps.
The guard supplies one — but only against a model. -/
theorem guarded_terminates_of_satisfiable (G₀ : System) (rho : Assign)
    (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), GRun n G₀ G → n ≤ N :=
  ⟨((allVars G₀).card + gmeas (labelsOf G₀) rho G₀) ^ 2 * 2 ^ (labelsOf G₀).card,
    fun _ _ h => h.length_le rho hm (labelsOf_concSub G₀)⟩

/-- **Contrast with the unguarded rule, on the very system that separates them.**
`Cut.resSeed` is satisfiable (`Compare.resSeed_satisfiable`) and the unguarded rule admits
chains of every length from it (`Cut.resSeed_diverges`).  The guarded rule does not: every
productive run from `resSeed` is shorter than a fixed bound. -/
theorem guarded_bound_for_resSeed :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), GRun n resSeed G → n ≤ N := by
  obtain ⟨rho, hm⟩ := Compare.resSeed_satisfiable
  exact guarded_terminates_of_satisfiable resSeed rho hm

/-! ## 9. Non-vacuity

A bound on the length of every run says nothing unless runs exist.  They do: the guard is
open on `Cut.resSeed`, so the first step of the divergent unguarded chain is also a guarded
one.  What the guard removes is the SECOND and every later firing on that pair. -/

/-- `resSeed` does not already name the resolvent `v \ {1, 2}`: its two concrete parts are
`{1}` and `{2}`, and neither is `{1} ∪ {2}`. -/
theorem resSeed_not_resolved : ¬ Resolved resSeed 0 (({1} : Row) ∪ {2}) := by
  intro h
  obtain ⟨z, hz⟩ := (resolved_iff _ _ _).mp h
  simp only [resSeed, resSeed₁, resSeed₂, Finset.mem_insert, Finset.mem_singleton] at hz
  rcases hz with h1 | h1
  · exact absurd (mk_inj h1).2.2 (by decide)
  · exact absurd (mk_inj h1).2.2 (by decide)

/-- **The guarded rule fires on the divergent seed.**  So `guarded_bound_for_resSeed` bounds
a nonempty set of runs: the mint the unguarded rule performs first is performed by the
guarded rule too. -/
theorem gRun_one_resSeed : ∃ G : System, GRun 1 resSeed G := by
  obtain ⟨z, hzf⟩ := exists_fresh (allVars resSeed)
  have hp : ResPair resSeed 0 1 2 ({1} : Row) ({2} : Row) :=
    ⟨Finset.mem_insert_self _ _, Finset.mem_insert_of_mem (Finset.mem_singleton_self _),
      resSeed_tops, resSeed_bots⟩
  exact ⟨resResult resSeed 0 1 2 {1} {2} z,
    GRun.tail (GRun.refl resSeed) (GResStep.mint hp resSeed_not_resolved hzf)
      (GResStep.mint_toResStep hp hzf).ssubset⟩

/-! ## Summary

**What is established.**  The guarded `resolution` of `ResGuard.lean` terminates on every
SATISFIABLE input, with an explicit bound: for `L := labelsOf G₀` and any model `rho` of
`G₀`, no run of the guarded rule that actually enlarges the system exceeds
`((allVars G₀).card + gmeas L rho G₀) ^ 2 * 2 ^ L.card` steps
(`GRun.length_le`, `guarded_terminates_of_satisfiable`).  Two ingredients are needed and
neither suffices alone.  The guard gives each pair (left-hand side, resolvent key) at most
one mint, and since the rule builds only `C ∪ D`, `D \ C` and `C \ D` from concrete parts
already present, the keys live in the fixed finite set `L.powerset` — that is `unfired`,
the count of keys still open at a variable, which `unfired_lt` shows a mint strictly
lowers.  But mints CREATE variables, each with a fresh budget, so counting keys alone
bounds nothing.  The model closes the gap: `mint_rank_lt` shows the minted variable denotes
a strictly smaller row than the variable it splits, so weighting each variable's remaining
budget by `(2 ^ L.card + 1) ^ (row cardinality)` — the measure `gmeas` — makes a mint
strictly decreasing (`GResStep.mint_gmeas_lt`) and a reuse non-increasing
(`GResStep.reuse_gmeas_le`).  The measure then bounds the vocabulary
(`GRun.allVars_card_le`) and the shape of what the rule emits bounds the system
(`GRun.subset_unaryForms`), which bounds the number of steps.  `gRun_one_resSeed` checks
the bound is not vacuous, and `guarded_bound_for_resSeed` states the contrast on the very
system that carries `Cut.resSeed_diverges`.

**What is NOT established.**  Nothing at all about UNSATISFIABLE systems.  The measure is
defined against a model and `mint_rank_lt` is false without one: with no assignment there
is no row whose cardinality can decrease, and the combinatorial half of the argument by
itself permits an unbounded supply of fresh variables each carrying a full budget.  This is
not an artefact of the proof — it is the subject of `ResGuardDiverge.lean`.  Nor is
anything claimed about the guarded rule in combination with the other surviving rules
(`Cut.CutRule`), nor about runs that idle: `GRun` requires `G ⊂ G'`, so the bound is on
productive steps only. -/

end Rowpartition
