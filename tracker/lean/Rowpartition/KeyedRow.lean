/-
# KeyedRow -- the CONCRETE-ROW reuse, and minting under the loop's deletions

`KeyedLoop.lean` (Stage 3) proves that the keyed split guard does NOT survive
`makeConcrete` / `destructiveSub`: the guard's witness `v <- (z, K)` is exactly what the
concretisation deletes (as a definition, `notMem_lone_lhs`) or rewrites away (as a mention,
`notMem_lone_mention`), and the satisfiable `W3` mints for ever.  Two things about that
model are LESS than the compiler does, and both are repaired here.

1. **The `srs` re-expression.**  When the Scala concretises `u := C`, `makeConcrete`'s own
   `cancellation` turns every ONE-abstract definition `u <- (z, K)` into the concrete fact
   `z <- ((|C \ K|))` before `destructiveSub` drops it (`Constraints.scala`, `val can`,
   `val srs`, and the `keepDefs` comment "a definition with ONE abstract part is
   re-expressed by `makeConcrete`'s cancellation").  `NameLoss.concretizeKeep` drops the
   definition and derives nothing.  `concretizeSrs` below adds the re-expression.
2. **The syntactic-first lookup.**  `splitConcrete` asks `rhss(RHSAbstr(abstr))` BEFORE the
   keyed lookup; `KeyedSplit.KSplitApp` has no `¬ Named` premise (`KEYED-LOOP-STAGE3.md`
   §2.4).  Every non-syntactic branch of the split relation below carries `¬ Named G (vset
   c)`, so the §2.4 gap is closed for this relation: its mint is a mint the shipped rule
   would take.

## The rule this file studies

For a split premise `c = v <- (S, K)` with `K ≠ ∅` and `2 ≤ |S|`, `splitConcrete`'s reverse
lookups, in the source's order, plus one more:

```
syn   (shipped)     Names G d S                    ==>  v <- (d, K)      SplitReuseStep
key   (shipped)     mk v {z} K ∈ G                 ==>  z <- (S)         SplitKeyed
row   (NEW)         mk v ∅ C ∈ G, mk z ∅ (C \ K) ∈ G  ==>  z <- (S)
mint  (otherwise)   fresh w                        ==>  w <- (S),  v <- (w, K)
```

`row` obeys the design rule of `ROW-CONSTRAINT-STATE.md` -- a NAME, never silence.  It is
sound because a concrete definition of `v` together with a concrete definition of the
complement row IS a name for `v \ K`: `conc_lone_sat` says the pair entails the lone
constraint `v <- (z, K)`, from which `ksplit_reuse_sat` gives `z <- (S)` unchanged
(`concRow_reuse_sat`).  The mint's guard is correspondingly the disjunction

```
Carried G v K  :=  Resolved G v K  ∨  ConcCarried G v K
```

and the whole point of the stage is that `Carried` -- unlike `Resolved` -- is PRESERVED by
the concretisation (`carried_concretizeSrs`): the two ways a key witness dies are exactly
the two ways it turns into a concrete-row carrier.

## What is proved

* §1-2  `ConcCarried` / `Carried`, decidable; `conc_lone_sat`, `concRow_reuse_sat`.
* §3    `srsOf`, `concretizeSrs`, `concretizeSrs_sound`, `concretizeKeep_subset_srs`,
        `concDef_persists` -- a concrete definition, once present, is present for ever.
* §4    `carried_concretizeSrs` -- **once carried, always carried**, the key invariant, and
        its two corollaries `carried_of_deleted_def` (failure mode 1) and
        `carried_of_absorbed_mention` (failure mode 2).
* §5    The extended split relation `K2SplitStep`, the loop relation `K2LoopStep`,
        `K2LoopRun`, `MintsBoundedOnSatKeyed2`.
* §6    The measure `uncarried` / `hmeas` (`ResGuardTerm.unfired` / `gmeas` with `Carried`
        in place of `Resolved`), and **(T1) for the relation with resolution rekeyed the
        same way**: `mintsBoundedOnSatKeyed2Star`, with the explicit bound
        `|allVars G₀| + hmeas L rho G₀`.
* §7    **(W) for the relation with guarded resolution AS SHIPPED**: `W4`, three
        constraints, satisfiable, mints for ever -- with NO split step at all.  So no
        change to `splitConcrete` alone can make the loop-extended calculus terminate;
        `resolution`'s guard has the same disease and needs the same cure.
* §8    The Stage 3 witness, re-run: at `concretizeSrs u C W3` the `row` branch fires and
        the mint is refused (`W3_row_reuse`, `W3_not_mintable`).  The engine of
        `KeyedLoop.W3_mints_unbounded` cannot start under this rule.
-/
import Rowpartition.KeyedLoop

namespace Rowpartition

open NameLoss (absorbC concretize concretizeKeep concretizeKeep_sound denotes_of_conc)
open KeyedLoop (mem_concretizeKeep absorbC_of_notMem absorbC_lhs notMem_vset_absorbC
  allVars_concretizeKeep_subset resolved_of_concretizeKeep conc_unique_of_model)

namespace KeyedRow

/-! ## 1. The two ways a key can be carried -/

/-- **The concrete-row carrier.**  `v` has a concrete definition `v <- ((|C|))` and some
variable `z` has the concrete definition `z <- ((|C \ K|))`.  Between them they NAME the row
`v \ K` -- which is what a lone witness `v <- (z, K)` names, and what a split mint at the key
`(v, K)` would have minted a name for.  The existentials are bounded by `G` so that the
predicate is decidable, which the budget of §6 needs; `concCarried_iff` says the bound costs
nothing. -/
def ConcCarried (G : System) (v : Var) (K : Row) : Prop :=
  ∃ C ∈ G.image Constraint.conc, mk v ∅ C ∈ G ∧ ∃ z ∈ allVars G, mk z ∅ (C \ K) ∈ G

instance (G : System) (v : Var) (K : Row) : Decidable (ConcCarried G v K) :=
  inferInstanceAs (Decidable (∃ C ∈ G.image Constraint.conc, mk v ∅ C ∈ G ∧
    ∃ z ∈ allVars G, mk z ∅ (C \ K) ∈ G))

theorem concCarried_iff (G : System) (v : Var) (K : Row) :
    ConcCarried G v K ↔ ∃ (C : Row) (z : Var), mk v ∅ C ∈ G ∧ mk z ∅ (C \ K) ∈ G := by
  constructor
  · rintro ⟨C, -, hC, z, -, hz⟩
    exact ⟨C, z, hC, hz⟩
  · rintro ⟨C, z, hC, hz⟩
    exact ⟨C, Finset.mem_image.mpr ⟨mk v ∅ C, hC, rfl⟩, hC, z, lhs_mem_allVars hz, hz⟩

/-- **The guard of the extended rule.**  A key `(v, K)` is CARRIED when the system names
`v \ K` either as a lone witness (`Resolved`, the shipped keyed guard) or as a pair of
concrete definitions (`ConcCarried`, the new clause). -/
def Carried (G : System) (v : Var) (K : Row) : Prop := Resolved G v K ∨ ConcCarried G v K

instance (G : System) (v : Var) (K : Row) : Decidable (Carried G v K) :=
  inferInstanceAs (Decidable (Resolved G v K ∨ ConcCarried G v K))

theorem Carried.of_resolved {G : System} {v : Var} {K : Row} (h : Resolved G v K) :
    Carried G v K := Or.inl h

theorem Carried.of_conc {G : System} {v z : Var} {C K : Row} (hv : mk v ∅ C ∈ G)
    (hz : mk z ∅ (C \ K) ∈ G) : Carried G v K :=
  Or.inr ((concCarried_iff G v K).mpr ⟨C, z, hv, hz⟩)

theorem Carried.mono {G G' : System} (hsub : G ⊆ G') {v : Var} {K : Row}
    (h : Carried G v K) : Carried G' v K := by
  rcases h with h | h
  · exact Or.inl (h.mono hsub)
  · obtain ⟨C, z, hC, hz⟩ := (concCarried_iff G v K).mp h
    exact Carried.of_conc (hsub hC) (hsub hz)

/-! ## 2. Soundness of the concrete-row reuse -/

/-- A bare concrete definition says what its variable denotes. -/
theorem conc_denotes {rho : Assign} {v : Var} {C : Row} (h : Sat rho (mk v ∅ C)) :
    rho v = C := by
  rw [sat_mk_iff] at h
  simpa using h.1

/-- **The concrete-row carrier really is a name.**  Under a model, `v <- ((|C|))` and
`z <- ((|C \ K|))` together entail the lone constraint `v <- (z, K)` -- provided `K ⊆ C`,
which the split premise `v <- (S, K)` itself supplies (`concRow_reuse_sat`).  This is the
one semantic fact the whole stage rests on. -/
theorem conc_lone_sat {rho : Assign} {v z : Var} {C K : Row}
    (hv : Sat rho (mk v ∅ C)) (hz : Sat rho (mk z ∅ (C \ K))) (hK : K ⊆ C) :
    Sat rho (mk v {z} K) := by
  rw [sat_lone_iff, conc_denotes hv, conc_denotes hz]
  refine ⟨?_, Finset.disjoint_sdiff⟩
  ext l
  simp only [Finset.mem_union, Finset.mem_sdiff]
  constructor
  · intro hl
    by_cases hlK : l ∈ K
    · exact Or.inl hlK
    · exact Or.inr ⟨hl, hlK⟩
  · rintro (hl | ⟨hl, -⟩)
    · exact hK hl
    · exact hl

/-- **Soundness of the CONCRETE-ROW REUSE branch.**  With `rho v = K ⊎ rho S`, `rho v = C`
and `rho z = C \ K` one gets `rho z = rho S`, so the bare `z <- (S)` the branch emits is
entailed.  The style is `ksplit_reuse_sat` / `KSplitStep.reuse_models_iff` -- indeed this is
`ksplit_reuse_sat` applied to the lone constraint `conc_lone_sat` manufactures. -/
theorem concRow_reuse_sat {rho : Assign} {v z : Var} {S : Finset Var} {C K : Row}
    (hc : Sat rho (mk v S K)) (hv : Sat rho (mk v ∅ C)) (hz : Sat rho (mk z ∅ (C \ K))) :
    Sat rho (mk z S ∅) := by
  have hK : K ⊆ C := by
    have h := hc.conc_subset_lhs
    rw [conc_mk, lhs_mk, conc_denotes hv] at h
    exact h
  exact ksplit_reuse_sat hc (conc_lone_sat hv hz hK)

/-! ## 3. The deletion step, made faithful to `srs`

`destructiveSub` deletes the definitions of `v` with fewer than two abstract parts, but
`makeConcrete` has already run `cancellation` against every one of them: a ONE-abstract
definition `v <- (z, K)` yields `z <- ((|C \ K|))`, which survives the deletion.  So in the
compiler a carrier of the complement row exists the MOMENT the witness dies.  `srsOf` is
that set of re-expressions. -/

/-- The facts `makeConcrete`'s cancellation derives from the ONE-abstract definitions of `u`
before `destructiveSub` drops them. -/
def srsOf (u : Var) (C : Row) (G : System) : System :=
  (allVars G).biUnion (fun z =>
    (G.filter (fun c => c = mk u {z} c.conc)).image (fun c => mk z ∅ (C \ c.conc)))

theorem mem_srsOf {u : Var} {C : Row} {G : System} {d : Constraint} :
    d ∈ srsOf u C G ↔ ∃ (z : Var) (K : Row), mk u {z} K ∈ G ∧ d = mk z ∅ (C \ K) := by
  simp only [srsOf, Finset.mem_biUnion, Finset.mem_image, Finset.mem_filter]
  constructor
  · rintro ⟨z, -, c, ⟨hcG, hceq⟩, rfl⟩
    exact ⟨z, c.conc, hceq ▸ hcG, rfl⟩
  · rintro ⟨z, K, hmem, rfl⟩
    refine ⟨z, mem_allVars hmem (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self z)),
      mk u {z} K, ⟨hmem, by rw [conc_mk]⟩, by rw [conc_mk]⟩

/-- **The concretisation as the compiler performs it**: `NameLoss.concretizeKeep` -- the
rewrite of mentions, the deletion of the thin definitions and the retention of the fat
ones -- TOGETHER WITH the cancellation facts the thin definitions are re-expressed as. -/
def concretizeSrs (u : Var) (C : Row) (G : System) : System :=
  concretizeKeep u C G ∪ srsOf u C G

theorem concretizeKeep_subset_srs (u : Var) (C : Row) (G : System) :
    concretizeKeep u C G ⊆ concretizeSrs u C G := Finset.subset_union_left

theorem mem_concretizeSrs {u : Var} {C : Row} {G : System} {c : Constraint} :
    c ∈ concretizeSrs u C G ↔ c ∈ concretizeKeep u C G ∨
      ∃ (z : Var) (K : Row), mk u {z} K ∈ G ∧ c = mk z ∅ (C \ K) := by
  simp only [concretizeSrs, Finset.mem_union, mem_srsOf]

theorem concDef_mem_concretizeSrs (u : Var) (C : Row) (G : System) :
    mk u ∅ C ∈ concretizeSrs u C G :=
  concretizeKeep_subset_srs u C G (mem_concretizeKeep.mpr (Or.inl rfl))

/-- When the concretised variable has no ONE-abstract definition there is nothing to
re-express, and the faithful step coincides with Stage 3's. -/
theorem srsOf_eq_empty {u : Var} {C : Row} {G : System}
    (h : ∀ (z : Var) (K : Row), mk u {z} K ∉ G) : srsOf u C G = ∅ := by
  ext d
  simp only [mem_srsOf, Finset.notMem_empty, iff_false, not_exists]
  rintro z K ⟨hmem, -⟩
  exact h z K hmem

theorem concretizeSrs_eq_concretizeKeep {u : Var} {C : Row} {G : System}
    (h : ∀ (z : Var) (K : Row), mk u {z} K ∉ G) :
    concretizeSrs u C G = concretizeKeep u C G := by
  rw [concretizeSrs, srsOf_eq_empty h, Finset.union_empty]

/-- **The side condition, stated honestly.**  `srsOf` writes `C \ K` unconditionally; the
fact it stands for is cancellation, whose guard is `K ⊆ C`.  Under a model that guard is
automatic -- a system carrying both `u <- ((|C|))` and `u <- (z, K)` forces `K ⊆ C` -- so
nothing is hidden: soundness below is stated for modelled systems only. -/
theorem key_subset_of_model {rho : Assign} {u z : Var} {C K : Row} {G : System}
    (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (hw : mk u {z} K ∈ G) : K ⊆ C := by
  have h := (hm _ hw).conc_subset_lhs
  rw [conc_mk, lhs_mk, denotes_of_conc hc hm] at h
  exact h

/-- Each re-expression is a semantic consequence: `rho z = C \ K`. -/
theorem srs_sat {rho : Assign} {u z : Var} {C K : Row} {G : System}
    (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (hw : mk u {z} K ∈ G) :
    Sat rho (mk z ∅ (C \ K)) := by
  have h1 : rho u = C := denotes_of_conc hc hm
  have h2 := hm _ hw
  rw [sat_lone_iff, h1] at h2
  obtain ⟨he, hd⟩ := h2
  have hzz : C \ K = rho z := by
    rw [he]
    ext l
    simp only [Finset.mem_sdiff, Finset.mem_union]
    constructor
    · rintro ⟨hl | hl, hnk⟩
      · exact absurd hl hnk
      · exact hl
    · intro hl
      exact ⟨Or.inr hl, fun hk => Finset.disjoint_left.mp hd hk hl⟩
  rw [sat_mk_iff]
  refine ⟨?_, by simp, by simp⟩
  simpa using hzz.symm

/-- **The faithful deletion step is sound.**  `concretizeKeep_sound` extended by the
cancellation facts. -/
theorem concretizeSrs_sound {u : Var} {C : Row} {G : System} (hmem : mk u ∅ C ∈ G) :
    ∀ rho, SModels rho G → SModels rho (concretizeSrs u C G) := by
  intro rho hm c hc
  rcases mem_concretizeSrs.mp hc with hc | ⟨z, K, hw, rfl⟩
  · exact concretizeKeep_sound hmem rho hm c hc
  · exact srs_sat hm hmem hw

/-- The re-expressions add no variable. -/
theorem allVars_srsOf_subset {u : Var} {C : Row} {G : System} :
    allVars (srsOf u C G) ⊆ allVars G := by
  intro v hv
  obtain ⟨c, hc, hvc⟩ := Finset.mem_biUnion.mp hv
  obtain ⟨z, K, hw, rfl⟩ := mem_srsOf.mp hc
  rcases Finset.mem_insert.mp hvc with h1 | h1
  · rw [lhs_mk] at h1
    subst h1
    exact mem_allVars hw (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self _))
  · rw [vset_mk] at h1
    exact absurd h1 (Finset.notMem_empty v)

/-- **The faithful deletion adds no variable either.** -/
theorem allVars_concretizeSrs_subset {u : Var} {C : Row} {G : System} (hmem : mk u ∅ C ∈ G) :
    allVars (concretizeSrs u C G) ⊆ allVars G := by
  intro v hv
  obtain ⟨c, hc, hvc⟩ := Finset.mem_biUnion.mp hv
  rcases Finset.mem_union.mp hc with hc | hc
  · exact allVars_concretizeKeep_subset hmem (Finset.mem_biUnion.mpr ⟨c, hc, hvc⟩)
  · exact allVars_srsOf_subset (Finset.mem_biUnion.mpr ⟨c, hc, hvc⟩)

theorem conc_absorbC_subset (u : Var) (C : Row) (c : Constraint) :
    (absorbC u C c).conc ⊆ c.conc ∪ C := by
  unfold absorbC
  split_ifs
  · rw [conc_mk]
  · exact Finset.subset_union_left

/-- **The faithful deletion invents no label.** -/
theorem concretizeSrs_concSub {L : Finset Label} {u : Var} {C : Row} {G : System}
    (hmem : mk u ∅ C ∈ G) (hcs : ConcSub L G) : ConcSub L (concretizeSrs u C G) := by
  have hCL : C ⊆ L := by have := hcs _ hmem; rwa [conc_mk] at this
  intro c hc
  rcases mem_concretizeSrs.mp hc with hc | ⟨z, K, -, rfl⟩
  · rcases mem_concretizeKeep.mp hc with rfl | ⟨d, hd, -, rfl⟩ | ⟨hcG, -, -⟩
    · rw [conc_mk]; exact hCL
    · exact (conc_absorbC_subset u C d).trans (Finset.union_subset (hcs d hd) hCL)
    · exact hcs c hcG
  · rw [conc_mk]
    exact Finset.sdiff_subset.trans hCL

/-- **A concrete definition, once present, is present for ever.**  The variable it defines
is not the one being concretised, so `absorbC` leaves it alone (its right-hand side is
empty, so it mentions nothing) and it is carried into the image. -/
theorem concDef_persists_of_ne {p u : Var} {D C : Row} {G : System}
    (h : mk p ∅ D ∈ G) (hpu : p ≠ u) : mk p ∅ D ∈ concretizeSrs u C G :=
  concretizeKeep_subset_srs u C G (mem_concretizeKeep.mpr (Or.inr (Or.inl
    ⟨mk p ∅ D, h, by rw [lhs_mk]; exact hpu,
      absorbC_of_notMem (by rw [vset_mk]; exact Finset.notMem_empty u)⟩)))

/-- **`concDef_persists`.**  Under a model the previous lemma needs no side condition: if the
concretised variable is the one being defined, `conc_unique_of_model` says the two rows agree
and the concretisation re-inserts exactly that definition. -/
theorem concDef_persists {p u : Var} {D C : Row} {G : System} {rho : Assign}
    (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (h : mk p ∅ D ∈ G) :
    mk p ∅ D ∈ concretizeSrs u C G := by
  by_cases hpu : p = u
  · rw [hpu] at h ⊢
    rw [conc_unique_of_model hm h hc]
    exact concDef_mem_concretizeSrs u C G
  · exact concDef_persists_of_ne h hpu

/-! ## 4. **Once carried, always carried**

Stage 3's two failure modes, and what each of them leaves behind once `srs` is faithful. -/

/-- **Failure mode 1, repaired.**  The concretisation DELETES the key witness `u <- (z, K)`
(`KeyedLoop.notMem_lone_lhs`) -- and the `srs` re-expression puts `z <- ((|C \ K|))` in its
place, which together with the new `u <- ((|C|))` CARRIES the key `(u, K)`.  No model is
needed: the two constraints are there by construction. -/
theorem carried_of_deleted_def {G : System} {u z : Var} {C K : Row} (hw : mk u {z} K ∈ G) :
    Carried (concretizeSrs u C G) u K :=
  Carried.of_conc (concDef_mem_concretizeSrs u C G)
    (Finset.mem_union_right _ (mem_srsOf.mpr ⟨z, K, hw, rfl⟩))

/-- **Failure mode 2, repaired.**  A key witness whose abstract part IS the concretised
variable is rewritten by `absorbC` into the bare `v <- ((|K ∪ C|))`
(`KeyedLoop.notMem_lone_mention`) -- and that image, together with the new `u <- ((|C|))`,
carries the key, because `(K ∪ C) \ K = C` once `K ∩ C = ∅`, which a model forces.  This is
the mode the Stage 3 divergence runs on. -/
theorem carried_of_absorbed_mention {G : System} {u v : Var} {C K : Row} {rho : Assign}
    (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (hw : mk v {u} K ∈ G) (hvu : v ≠ u) :
    Carried (concretizeSrs u C G) v K := by
  have hdis : Disjoint K C := by
    have h := hm _ hw
    rw [sat_lone_iff, denotes_of_conc hc hm] at h
    exact h.2
  have himg : mk v ∅ (K ∪ C) ∈ concretizeSrs u C G := by
    refine concretizeKeep_subset_srs u C G (mem_concretizeKeep.mpr (Or.inr (Or.inl
      ⟨mk v {u} K, hw, by rw [lhs_mk]; exact hvu, ?_⟩)))
    unfold absorbC
    rw [if_pos (by rw [vset_mk]; exact Finset.mem_singleton_self u)]
    rw [vset_mk, conc_mk, lhs_mk, Finset.erase_singleton]
  have hsd : (K ∪ C) \ K = C := by
    ext l
    simp only [Finset.mem_sdiff, Finset.mem_union]
    constructor
    · rintro ⟨hl | hl, hnk⟩
      · exact absurd hl hnk
      · exact hl
    · intro hl
      exact ⟨Or.inr hl, fun hk => Finset.disjoint_left.mp hdis hk hl⟩
  exact Carried.of_conc himg (by rw [hsd]; exact concDef_mem_concretizeSrs u C G)

/-- **The key invariant of Stage 4.**  Every key the system carries, it still carries after
`makeConcrete`.  `KeyedLoop.resolved_of_concretizeKeep` could only say this for the keys the
concretisation does not touch; with the `srs` re-expression and the concrete-row clause the
two ways a witness dies both END in a carrier, so `Carried` -- unlike `Resolved` -- is an
invariant of the deleting step. -/
theorem carried_concretizeSrs {G : System} {u v : Var} {C K : Row} {rho : Assign}
    (hm : SModels rho G) (hc : mk u ∅ C ∈ G) (h : Carried G v K) :
    Carried (concretizeSrs u C G) v K := by
  rcases h with h | h
  · obtain ⟨w, hw⟩ := (resolved_iff G v K).mp h
    by_cases hvu : v = u
    · rw [hvu] at hw ⊢
      exact carried_of_deleted_def hw
    · by_cases hwu : w = u
      · rw [hwu] at hw
        exact carried_of_absorbed_mention hm hc hw hvu
      · exact Carried.of_resolved ((resolved_of_concretizeKeep hw hvu hwu).mono
          (concretizeKeep_subset_srs u C G))
  · obtain ⟨F, s, hF, hs⟩ := (concCarried_iff G v K).mp h
    exact Carried.of_conc (concDef_persists hm hc hF) (concDef_persists hm hc hs)

/-! ## 5. The extended split rule

`splitConcrete`'s three reverse lookups, in the source's order, plus the mint.  Every
non-syntactic branch carries `¬ Named G (vset c)`, which `KeyedSplit.KSplitApp` does not:
that is the faithfulness gap `KEYED-LOOP-STAGE3.md` §2.4 records, closed here. -/

/-- **The premises of the MINT.**  `Cut.SplitApp` and `KeyedSplit.KSplitApp` at once -- both
reverse lookups must miss -- with the keyed lookup widened from `Resolved` to `Carried`. -/
structure K2MintApp (G : System) (c : Constraint) (u : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- the SYNTACTIC lookup missed (`rhss(RHSAbstr(abstr))`), asked FIRST -/
  unnamed : ¬ Named G (vset c)
  /-- the KEYED lookup, widened by the concrete-row clause, missed -/
  uncarried : ¬ Carried G c.lhs c.conc
  /-- `u` is a genuinely fresh variable -/
  fresh : u ∉ allVars G

/-- **The premises of the KEYED REUSE** (shipped since 2026-09-03, `SplitKeyed`). -/
structure K2KeyApp (G : System) (c : Constraint) (u : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- the SYNTACTIC lookup missed -/
  unnamed : ¬ Named G (vset c)
  /-- the keyed reverse lookup hit -/
  witness : mk c.lhs {u} c.conc ∈ G

/-- **The premises of the CONCRETE-ROW REUSE** -- the Stage 4 clause.  The premise's
left-hand side has a concrete definition `((|C|))` and some variable already carries the
complement row `C \ K`; that variable is the name the mint would have created. -/
structure K2RowApp (G : System) (c : Constraint) (u : Var) (C : Row) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- the SYNTACTIC lookup missed -/
  unnamed : ¬ Named G (vset c)
  /-- the premise's left-hand side is concrete -/
  lhsConc : mk c.lhs ∅ C ∈ G
  /-- ... and `u` carries the complement row -/
  carrier : mk u ∅ (C \ c.conc) ∈ G

/-- **The extended `splitConcrete`.**  `syn` is `SplitNecessary.SplitReuseStep`, the shipped
syntactic reuse; `key` is `KeyedSplit.KSplitStep.reuse`; `row` is NEW; `mint` emits exactly
what `Cut.splitResult` emits, under the widened guard. -/
inductive K2SplitStep : System → System → Prop
  | syn {G : System} {c : Constraint} {u : Var} :
      SplitReuseApp G c u → K2SplitStep G (splitReuseResult G c u)
  | key {G : System} {c : Constraint} {u : Var} :
      K2KeyApp G c u → K2SplitStep G (kSplitReuseResult G c u)
  | row {G : System} {c : Constraint} {u : Var} {C : Row} :
      K2RowApp G c u C → K2SplitStep G (kSplitReuseResult G c u)
  | mint {G : System} {c : Constraint} {u : Var} :
      K2MintApp G c u → K2SplitStep G (splitResult G c u)

/-- **Every mint of this relation is a mint the SHIPPED rule takes.**  `¬ Named` is the
syntactic lookup `splitConcrete` asks first, and `¬ Carried` implies `¬ Resolved`, the keyed
one.  This is the `KEYED-LOOP-STAGE3.md` §2.4 gap closed: `Cut.SplitApp` and
`KeyedSplit.KSplitApp` both hold, so the relation studied here is not more permissive than the
compiler at its GENERATIVE branch. -/
theorem K2MintApp.toSplitApp {G : System} {c : Constraint} {u : Var} (h : K2MintApp G c u) :
    SplitApp G c u ∧ KSplitApp G c u :=
  ⟨⟨h.mem, h.conc_ne, h.two_le, h.unnamed, h.fresh⟩,
   ⟨h.mem, h.conc_ne, h.two_le, fun hr => h.uncarried (Carried.of_resolved hr), h.fresh⟩⟩

theorem K2SplitStep.subset {G G' : System} (h : K2SplitStep G G') : G ⊆ G' := by
  cases h with
  | syn _ => exact subset_splitReuseResult _ _ _
  | key _ => exact subset_kSplitReuseResult _ _ _
  | row _ => exact subset_kSplitReuseResult _ _ _
  | mint _ => exact subset_splitResult _ _ _

/-- The keyed branch of the extended rule is `KeyedSplit`'s, with one more premise. -/
theorem K2KeyApp.toKSplitReuseApp {G : System} {c : Constraint} {u : Var}
    (h : K2KeyApp G c u) : KSplitReuseApp G c u := ⟨h.mem, h.conc_ne, h.two_le, h.witness⟩

theorem K2RowApp.name_mem_allVars {G : System} {c : Constraint} {u : Var} {C : Row}
    (h : K2RowApp G c u C) : u ∈ allVars G := lhs_mem_allVars h.carrier

theorem allVars_kSplitReuseResult' {G : System} {c : Constraint} {u : Var}
    (hmem : c ∈ G) (hu : u ∈ allVars G) : allVars (kSplitReuseResult G c u) = allVars G := by
  refine allVars_insert_eq_of_subset ?_
  intro v hv
  simp only [lhs_mk, vset_mk, Finset.mem_insert] at hv
  rcases hv with rfl | hv
  · exact hu
  · exact vset_subset_allVars hmem hv

/-- **Every extended split step either keeps the vocabulary or adds exactly one fresh
variable** -- and only the MINT does the latter. -/
theorem K2SplitStep.allVars_cases {G G' : System} (h : K2SplitStep G G') :
    allVars G' = allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G) := by
  cases h with
  | syn h => exact Or.inl (SplitReuseStep.allVars_eq (SplitReuseStep.intro h))
  | key h => exact Or.inl (allVars_kSplitReuseResult h.toKSplitReuseApp)
  | row h => exact Or.inl (allVars_kSplitReuseResult' h.mem h.name_mem_allVars)
  | mint h => exact Or.inr ⟨_, h.fresh, allVars_splitResult h.mem _⟩

/-- **The concrete-row branch does not move the model set at all** -- the statement
`KSplitStep.reuse_models_iff` makes for the keyed branch. -/
theorem K2RowApp.models_iff {G : System} {c : Constraint} {u : Var} {C : Row}
    (happ : K2RowApp G c u C) (rho : Assign) :
    SModels rho (kSplitReuseResult G c u) ↔ SModels rho G := by
  constructor
  · exact SModels.mono (subset_kSplitReuseResult _ _ _)
  · intro hm d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · exact concRow_reuse_sat (sat_mk_of_sat (hm c happ.mem)) (hm _ happ.lhsConc)
        (hm _ happ.carrier)
    · exact hm d hd

/-- **Soundness of one extended split step**: the model is carried along, moving only at the
minted name. -/
theorem K2SplitStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : K2SplitStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | syn h =>
    exact ⟨rho, (SplitReuseStep.models_iff (SplitReuseStep.intro h) rho).mp hm, fun _ _ => rfl⟩
  | key h =>
    exact ⟨rho, (KSplitStep.reuse_models_iff h.toKSplitReuseApp rho).mpr hm, fun _ _ => rfl⟩
  | row h => exact ⟨rho, (h.models_iff rho).mpr hm, fun _ _ => rfl⟩
  | mint h =>
    refine ⟨setVar rho _ ((vset _).biUnion rho), ksplit_extend h.mem h.fresh hm, ?_⟩
    exact fun v hv => setVar_of_ne rho _ (fun hh => h.fresh (hh ▸ hv))

theorem K2SplitStep.concSub {L : Finset Label} {G G' : System} (h : K2SplitStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @syn c u happ =>
    intro d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · rw [conc_mk]; exact hcs c happ.mem
    · exact hcs d hd
  | @key c u happ =>
    intro d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · rw [conc_mk]; exact Finset.empty_subset _
    · exact hcs d hd
  | @row c u C happ =>
    intro d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · rw [conc_mk]; exact Finset.empty_subset _
    · exact hcs d hd
  | @mint c u happ =>
    intro d hd
    simp only [splitResult, Finset.mem_insert] at hd
    rcases hd with rfl | rfl | hd
    · rw [conc_mk]; exact Finset.empty_subset _
    · rw [conc_mk]; exact hcs c happ.mem
    · exact hcs d hd

/-! ## 6. The loop-extended calculi

Two of them.  `K2LoopStep` keeps guarded `resolution` exactly as shipped, and is the
relation the Stage 4 question is literally about.  `K2StarLoopStep` rekeys `resolution`'s
guard on `Carried` too -- one more application of the same idea -- and is the relation the
termination theorem of §7 holds for.  §8 shows why the difference matters. -/

/-- The additive calculus with the extended split: every non-generative rule, the extended
`splitConcrete`, and guarded `resolution` AS SHIPPED (`ResGuard.GResStep`). -/
inductive K2DefaultStep : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → K2DefaultStep G G'
  | split {G G' : System} : K2SplitStep G G' → K2DefaultStep G G'
  | gres {G G' : System} : GResStep G G' → K2DefaultStep G G'

/-- ... plus the loop's own concretisation, made faithful to `srs`. -/
inductive K2LoopStep : System → System → Prop
  | additive {G G' : System} : K2DefaultStep G G' → K2LoopStep G G'
  | concrete {G : System} {u : Var} {C : Row} :
      mk u ∅ C ∈ G → concretizeSrs u C G ≠ G → K2LoopStep G (concretizeSrs u C G)

/-- Productive runs, `KeyedLoop.KLoopRun`'s side condition verbatim. -/
inductive K2LoopRun : ℕ → System → System → Prop
  | refl (G : System) : K2LoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      K2LoopRun n G₀ G → K2LoopStep G G' → G ≠ G' → K2LoopRun (n + 1) G₀ G'

/-- **The Stage 4 question.**  Not run LENGTH -- the any-order relation permits add/delete
cycles -- but VOCABULARY: since only a mint enlarges the vocabulary, a bound on
`(allVars G).card` is a bound on the number of mints. -/
def MintsBoundedOnSatKeyed2 : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K2LoopRun n G₀ G → (allVars G).card ≤ N

/-- **Guarded `resolution`, rekeyed the same way as the split.**  `mint` asks `¬ Carried`
rather than `¬ Resolved`; `reuse` is the shipped keyed branch; `row` is the new
concrete-row branch, sound for exactly the reason the split's is
(`K2ResStep.row_models_iff`). -/
inductive K2ResStep : System → System → Prop
  | mint {G : System} {v x y : Var} {C D : Row} {z : Var} :
      ResPair G v x y C D → ¬ Carried G v (C ∪ D) → z ∉ allVars G →
      K2ResStep G (resResult G v x y C D z)
  | reuse {G : System} {v x y : Var} {C D : Row} {z : Var} :
      ResPair G v x y C D → mk v {z} (C ∪ D) ∈ G →
      K2ResStep G (resReuseResult G x y C D z)
  | row {G : System} {v x y : Var} {C D F : Row} {z : Var} :
      ResPair G v x y C D → mk v ∅ F ∈ G → mk z ∅ (F \ (C ∪ D)) ∈ G →
      K2ResStep G (resReuseResult G x y C D z)

/-- The additive calculus with BOTH guards rekeyed. -/
inductive K2StarStep : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → K2StarStep G G'
  | split {G G' : System} : K2SplitStep G G' → K2StarStep G G'
  | res {G G' : System} : K2ResStep G G' → K2StarStep G G'

/-- ... plus the faithful concretisation. -/
inductive K2StarLoopStep : System → System → Prop
  | additive {G G' : System} : K2StarStep G G' → K2StarLoopStep G G'
  | concrete {G : System} {u : Var} {C : Row} :
      mk u ∅ C ∈ G → concretizeSrs u C G ≠ G → K2StarLoopStep G (concretizeSrs u C G)

inductive K2StarLoopRun : ℕ → System → System → Prop
  | refl (G : System) : K2StarLoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      K2StarLoopRun n G₀ G → K2StarLoopStep G G' → G ≠ G' → K2StarLoopRun (n + 1) G₀ G'

/-- The same question for the fully rekeyed calculus. -/
def MintsBoundedOnSatKeyed2Star : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K2StarLoopRun n G₀ G → (allVars G).card ≤ N

/-! ### 6.1 Basic facts about the rekeyed resolution -/

/-- Every rekeyed resolution MINT is a shipped guarded mint: `Carried` is weaker than
`Resolved`, so the new guard refuses strictly more. -/
theorem K2ResStep.mint_toGRes {G : System} {v x y : Var} {C D : Row} {z : Var}
    (hp : ResPair G v x y C D) (hg : ¬ Carried G v (C ∪ D)) (hz : z ∉ allVars G) :
    GResStep G (resResult G v x y C D z) :=
  GResStep.mint hp (fun hr => hg (Carried.of_resolved hr)) hz

theorem K2ResStep.subset {G G' : System} (h : K2ResStep G G') : G ⊆ G' := by
  cases h with
  | mint _ _ _ => exact subset_resResult _ _ _ _ _ _ _
  | reuse _ _ => exact subset_resReuseResult _ _ _ _ _ _
  | row _ _ _ => exact subset_resReuseResult _ _ _ _ _ _

/-- **The concrete-row branch of resolution does not move the model set.**  `conc_lone_sat`
manufactures the resolvent `v <- (z, C ∪ D)` out of the two concrete definitions, and
`ResGuard.reuse_sat` then draws both conclusions unchanged. -/
theorem K2ResStep.row_models_iff {G : System} {v x y z : Var} {C D F : Row}
    (hp : ResPair G v x y C D) (hF : mk v ∅ F ∈ G) (hz : mk z ∅ (F \ (C ∪ D)) ∈ G)
    (rho : Assign) : SModels rho (resReuseResult G x y C D z) ↔ SModels rho G := by
  constructor
  · exact SModels.mono (subset_resReuseResult _ _ _ _ _ _)
  · intro hm
    have hlone : Sat rho (mk v {z} (C ∪ D)) := by
      refine conc_lone_sat (hm _ hF) (hm _ hz) ?_
      have h1 : C ⊆ rho v := conc_subset_of_sat (hm _ hp.mem₁)
      have h2 : D ⊆ rho v := conc_subset_of_sat (hm _ hp.mem₂)
      rw [conc_denotes (hm _ hF)] at h1 h2
      exact Finset.union_subset h1 h2
    intro c hc
    simp only [resReuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact (reuse_sat (hm _ hp.mem₁) (hm _ hp.mem₂) hlone).1
    · exact (reuse_sat (hm _ hp.mem₁) (hm _ hp.mem₂) hlone).2
    · exact hm c hc

theorem concSub_resReuseResult {L : Finset Label} {G : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hcs : ConcSub L G) :
    ConcSub L (resReuseResult G x y C D z) := by
  have hC : C ⊆ L := hcs _ hp.mem₁
  have hD : D ⊆ L := hcs _ hp.mem₂
  intro c hc
  simp only [resReuseResult, Finset.mem_insert] at hc
  rcases hc with rfl | rfl | hc
  · rw [conc_mk]; exact Finset.sdiff_subset.trans hD
  · rw [conc_mk]; exact Finset.sdiff_subset.trans hC
  · exact hcs c hc

theorem K2ResStep.concSub {L : Finset Label} {G G' : System} (h : K2ResStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @mint v x y C D z hp hg hz => exact (K2ResStep.mint_toGRes hp hg hz).concSub hcs
  | @reuse v x y C D z hp _ => exact concSub_resReuseResult hp hcs
  | @row v x y C D F z hp _ _ => exact concSub_resReuseResult hp hcs

theorem K2ResStep.allVars_cases {G G' : System} (h : K2ResStep G G') :
    allVars G' = allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G) := by
  cases h with
  | @mint v x y C D z hp _ hz =>
    exact Or.inr ⟨z, hz, allVars_resResult z (lhs_mem_allVars hp.mem₁)
      (mem_allVars hp.mem₁ (Or.inr (by simp))) (mem_allVars hp.mem₂ (Or.inr (by simp)))⟩
  | @reuse v x y C D z hp hr =>
    exact Or.inl (allVars_resReuseResult (mem_allVars hp.mem₁ (Or.inr (by simp)))
      (mem_allVars hp.mem₂ (Or.inr (by simp))) (mem_allVars hr (Or.inr (by simp))))
  | @row v x y C D F z hp _ hz =>
    exact Or.inl (allVars_resReuseResult (mem_allVars hp.mem₁ (Or.inr (by simp)))
      (mem_allVars hp.mem₂ (Or.inr (by simp))) (lhs_mem_allVars hz))

theorem K2ResStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : K2ResStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | @mint v x y C D z hp _ hz => exact mint_extend hp hz hm
  | @reuse v x y C D z hp hr =>
    exact ⟨rho, (GResStep.reuse_models_iff hp hr rho).mpr hm, fun _ _ => rfl⟩
  | @row v x y C D F z hp hF hz =>
    exact ⟨rho, (K2ResStep.row_models_iff hp hF hz rho).mpr hm, fun _ _ => rfl⟩

theorem K2StarStep.subset {G G' : System} (h : K2StarStep G G') : G ⊆ G' := by
  cases h with
  | nongen h => exact h.subset
  | split h => exact h.subset
  | res h => exact h.subset

theorem K2StarStep.concSub {L : Finset Label} {G G' : System} (h : K2StarStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | nongen h => exact (DefaultStep.nongen h).concSub hcs
  | split h => exact h.concSub hcs
  | res h => exact h.concSub hcs

/-! ## 7. The measure, and (T1) for the fully rekeyed calculus

`ResGuardTerm.unfired` / `gmeas` verbatim, with `Carried` in place of `Resolved`.  What is
new is that this budget survives the DELETION (`carried_concretizeSrs`), which is exactly
what `Resolved`'s does not (`KeyedLoop.notMem_lone_lhs`, `notMem_lone_mention`). -/

/-- The number of keys at `v` that are not yet carried. -/
def uncarried (L : Finset Label) (G : System) (v : Var) : ℕ :=
  (L.powerset.filter (fun K => ¬ Carried G v K)).card

theorem uncarried_le_pow (L : Finset Label) (G : System) (v : Var) :
    uncarried L G v ≤ 2 ^ L.card := by
  rw [uncarried, ← Finset.card_powerset L]
  exact Finset.card_filter_le _ _

/-- **Budgets only shrink**, for any successor that preserves carrying -- which includes
both the additive steps (by monotonicity) and the concretisation (by
`carried_concretizeSrs`). -/
theorem uncarried_le_of_carried {L : Finset Label} {G G' : System} {v : Var}
    (hcar : ∀ K, Carried G v K → Carried G' v K) : uncarried L G' v ≤ uncarried L G v := by
  refine Finset.card_le_card ?_
  intro K hK
  rw [Finset.mem_filter] at hK ⊢
  exact ⟨hK.1, fun hr => hK.2 (hcar K hr)⟩

theorem uncarried_le {L : Finset Label} {G G' : System} (hsub : G ⊆ G') (v : Var) :
    uncarried L G' v ≤ uncarried L G v :=
  uncarried_le_of_carried (fun _ hr => hr.mono hsub)

/-- **A mint spends one unit of budget**, exactly as `ResGuardTerm.unfired_lt`. -/
theorem uncarried_lt {L : Finset Label} {G G' : System} {v : Var} {K : Row}
    (hsub : G ⊆ G') (hKL : K ⊆ L) (hg : ¬ Carried G v K) (hc : Carried G' v K) :
    uncarried L G' v + 1 ≤ uncarried L G v := by
  have hss : L.powerset.filter (fun J => ¬ Carried G' v J)
      ⊆ (L.powerset.filter (fun J => ¬ Carried G v J)).erase K := by
    intro J hJ
    rw [Finset.mem_filter] at hJ
    refine Finset.mem_erase.mpr
      ⟨?_, Finset.mem_filter.mpr ⟨hJ.1, fun hr => hJ.2 (hr.mono hsub)⟩⟩
    rintro rfl
    exact hJ.2 hc
  have hKmem : K ∈ L.powerset.filter (fun J => ¬ Carried G v J) :=
    Finset.mem_filter.mpr ⟨Finset.mem_powerset.mpr hKL, hg⟩
  exact lt_of_le_of_lt (Finset.card_le_card hss) (Finset.card_erase_lt_of_mem hKmem)

/-- The termination measure: `ResGuardTerm.gmeas` with `uncarried` for `unfired`. -/
def hmeas (L : Finset Label) (rho : Assign) (G : System) : ℕ :=
  ∑ v ∈ allVars G, uncarried L G v * (2 ^ L.card + 1) ^ (rho v).card

theorem hmeas_congr {L : Finset Label} {rho rho' : Assign} {G : System}
    (h : ∀ u ∈ allVars G, rho u = rho' u) : hmeas L rho G = hmeas L rho' G :=
  Finset.sum_congr rfl fun u hu => by rw [h u hu]

/-- **Any successor that preserves carrying and adds no variable does not increase the
measure.**  This covers every non-generative rule, every reuse branch of either minting
rule, and -- the point of the stage -- the CONCRETISATION. -/
theorem hmeas_le_of_carried {L : Finset Label} {G G' : System} (rho : Assign)
    (hAV : allVars G' ⊆ allVars G) (hcar : ∀ v K, Carried G v K → Carried G' v K) :
    hmeas L rho G' ≤ hmeas L rho G := by
  have h1 : hmeas L rho G'
      ≤ ∑ v ∈ allVars G', uncarried L G v * (2 ^ L.card + 1) ^ (rho v).card :=
    Finset.sum_le_sum fun v _ => Nat.mul_le_mul (uncarried_le_of_carried (hcar v)) (Nat.le_refl _)
  exact h1.trans (Finset.sum_le_sum_of_subset hAV)

/-- **The mint lemma, once, for both minting rules.**  The parent `v` pays one unit of budget
at the key `K ⊆ L`, which the guard guaranteed uncarried and which the successor carries; the
fresh `z` receives a whole budget, but at a strictly smaller exponent, and a whole budget
there is worth less than the single unit the parent gave up (`budget_mul_pow_lt`). -/
theorem hmeas_mint_lt {L : Finset Label} {G G' : System} {v z : Var} {K : Row} {rho : Assign}
    (hsub : G ⊆ G') (hz : z ∉ allVars G) (hAV : allVars G' = insert z (allVars G))
    (hv : v ∈ allVars G) (hKL : K ⊆ L) (hg : ¬ Carried G v K) (hc' : Carried G' v K)
    (hrank : (rho z).card < (rho v).card) : hmeas L rho G' < hmeas L rho G := by
  have hzterm : uncarried L G' z * (2 ^ L.card + 1) ^ (rho z).card
      < (2 ^ L.card + 1) ^ (rho v).card :=
    lt_of_le_of_lt (Nat.mul_le_mul (uncarried_le_pow L G' z) (Nat.le_refl _))
      (budget_mul_pow_lt (2 ^ L.card) hrank)
  have hvterm : uncarried L G' v * (2 ^ L.card + 1) ^ (rho v).card
      + (2 ^ L.card + 1) ^ (rho v).card
      ≤ uncarried L G v * (2 ^ L.card + 1) ^ (rho v).card := by
    have h1 : uncarried L G' v + 1 ≤ uncarried L G v := uncarried_lt hsub hKL hg hc'
    have h2 : (uncarried L G' v + 1) * (2 ^ L.card + 1) ^ (rho v).card
        ≤ uncarried L G v * (2 ^ L.card + 1) ^ (rho v).card :=
      Nat.mul_le_mul h1 (Nat.le_refl _)
    rw [Nat.add_mul, Nat.one_mul] at h2
    exact h2
  have hrest : ∑ w ∈ (allVars G).erase v, uncarried L G' w * (2 ^ L.card + 1) ^ (rho w).card
      ≤ ∑ w ∈ (allVars G).erase v, uncarried L G w * (2 ^ L.card + 1) ^ (rho w).card :=
    Finset.sum_le_sum fun w _ => Nat.mul_le_mul (uncarried_le hsub w) (Nat.le_refl _)
  have hsplitG : hmeas L rho G
      = uncarried L G v * (2 ^ L.card + 1) ^ (rho v).card
        + ∑ w ∈ (allVars G).erase v, uncarried L G w * (2 ^ L.card + 1) ^ (rho w).card :=
    sum_erase_split hv (fun w => uncarried L G w * (2 ^ L.card + 1) ^ (rho w).card)
  have hsplit2 : ∑ w ∈ allVars G, uncarried L G' w * (2 ^ L.card + 1) ^ (rho w).card
      = uncarried L G' v * (2 ^ L.card + 1) ^ (rho v).card
        + ∑ w ∈ (allVars G).erase v, uncarried L G' w * (2 ^ L.card + 1) ^ (rho w).card :=
    sum_erase_split hv (fun w => uncarried L G' w * (2 ^ L.card + 1) ^ (rho w).card)
  have hsplitG' : hmeas L rho G'
      = uncarried L G' z * (2 ^ L.card + 1) ^ (rho z).card
        + (uncarried L G' v * (2 ^ L.card + 1) ^ (rho v).card
          + ∑ w ∈ (allVars G).erase v, uncarried L G' w * (2 ^ L.card + 1) ^ (rho w).card) := by
    rw [hmeas, hAV, Finset.sum_insert hz, hsplit2]
  rw [hsplitG, hsplitG']
  omega

/-! ### 7.1 One step of the fully rekeyed calculus -/

/-- The bookkeeping for every step that adds no variable. -/
theorem measure_step_of_nongenerative {L : Finset Label} {G G' : System} {rho : Assign}
    (hsub : G ⊆ G') (hAV : allVars G' = allVars G) (hm' : SModels rho G') :
    ∃ rho', SModels rho' G' ∧ (∀ v ∈ allVars G, rho' v = rho v) ∧
      (allVars G').card + hmeas L rho' G' ≤ (allVars G).card + hmeas L rho G := by
  refine ⟨rho, hm', fun _ _ => rfl, ?_⟩
  have hle : hmeas L rho G' ≤ hmeas L rho G :=
    hmeas_le_of_carried rho (le_of_eq hAV) (fun _ _ hr => hr.mono hsub)
  rw [hAV]
  omega

/-- The bookkeeping for a mint: one more variable, one less unit of budget at a strictly
larger exponent. -/
theorem measure_step_of_mint {L : Finset Label} {G G' : System} {v z : Var} {K : Row}
    {rho rho' : Assign}
    (hsub : G ⊆ G') (hz : z ∉ allVars G) (hAV : allVars G' = insert z (allVars G))
    (hv : v ∈ allVars G) (hKL : K ⊆ L) (hg : ¬ Carried G v K) (hc' : Carried G' v K)
    (hagree : ∀ w ∈ allVars G, rho' w = rho w)
    (hrank : (rho' z).card < (rho' v).card) :
    (allVars G').card + hmeas L rho' G' ≤ (allVars G).card + hmeas L rho G := by
  have hcong : hmeas L rho' G = hmeas L rho G := hmeas_congr hagree
  have hlt : hmeas L rho' G' < hmeas L rho' G := hmeas_mint_lt hsub hz hAV hv hKL hg hc' hrank
  have hcard : (allVars G').card = (allVars G).card + 1 := by
    rw [hAV]; exact Finset.card_insert_of_notMem hz
  omega

theorem K2StarStep.measure_step {L : Finset Label} {G G' : System} (h : K2StarStep G G')
    (hcs : ConcSub L G) {rho : Assign} (hm : SModels rho G) :
    ∃ rho', SModels rho' G' ∧ (∀ v ∈ allVars G, rho' v = rho v) ∧
      (allVars G').card + hmeas L rho' G' ≤ (allVars G).card + hmeas L rho G := by
  cases h with
  | nongen h =>
    exact measure_step_of_nongenerative h.subset h.allVars_eq ((h.models_iff rho).mp hm)
  | split hs =>
    cases hs with
    | @syn c u happ =>
      exact measure_step_of_nongenerative (subset_splitReuseResult _ _ _)
        (SplitReuseStep.allVars_eq (SplitReuseStep.intro happ))
        ((SplitReuseStep.models_iff (SplitReuseStep.intro happ) rho).mp hm)
    | @key c u happ =>
      exact measure_step_of_nongenerative (subset_kSplitReuseResult _ _ _)
        (allVars_kSplitReuseResult happ.toKSplitReuseApp)
        ((KSplitStep.reuse_models_iff happ.toKSplitReuseApp rho).mpr hm)
    | @row c u C happ =>
      exact measure_step_of_nongenerative (subset_kSplitReuseResult _ _ _)
        (allVars_kSplitReuseResult' happ.mem happ.name_mem_allVars) ((happ.models_iff rho).mpr hm)
    | @mint c u happ =>
      have hm' : SModels (setVar rho u ((vset c).biUnion rho)) (splitResult G c u) :=
        ksplit_extend happ.mem happ.fresh hm
      have hagree : ∀ w ∈ allVars G, setVar rho u ((vset c).biUnion rho) w = rho w :=
        fun w hw => setVar_of_ne rho _ (fun hh => happ.fresh (hh ▸ hw))
      refine ⟨_, hm', hagree, ?_⟩
      refine measure_step_of_mint (subset_splitResult _ _ _) happ.fresh
        (allVars_splitResult happ.mem u) (lhs_mem_allVars happ.mem) (hcs c happ.mem)
        happ.uncarried
        (Carried.of_resolved (resolved_of_mem
          (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)))) hagree ?_
      exact ksplit_rank_lt happ.conc_ne hm'
  | res hr =>
    cases hr with
    | @mint v x y C D z hp hg hz =>
      obtain ⟨rho', hm', hagree⟩ := mint_extend hp hz hm
      have hv : v ∈ allVars G := lhs_mem_allVars hp.mem₁
      have hx : x ∈ allVars G := mem_allVars hp.mem₁ (Or.inr (by simp))
      have hy : y ∈ allVars G := mem_allVars hp.mem₂ (Or.inr (by simp))
      refine ⟨rho', hm', hagree, ?_⟩
      exact measure_step_of_mint (subset_resResult _ _ _ _ _ _ _) hz
        (allVars_resResult z hv hx hy) hv
        (Finset.union_subset (hcs _ hp.mem₁) (hcs _ hp.mem₂)) hg
        (Carried.of_resolved (resolved_of_mem (Finset.mem_insert_self _ _))) hagree
        (mint_rank_lt hp hm')
    | @reuse v x y C D z hp hres =>
      exact measure_step_of_nongenerative (subset_resReuseResult _ _ _ _ _ _)
        (allVars_resReuseResult (mem_allVars hp.mem₁ (Or.inr (by simp)))
          (mem_allVars hp.mem₂ (Or.inr (by simp))) (mem_allVars hres (Or.inr (by simp))))
        ((GResStep.reuse_models_iff hp hres rho).mpr hm)
    | @row v x y C D F z hp hF hz =>
      exact measure_step_of_nongenerative (subset_resReuseResult _ _ _ _ _ _)
        (allVars_resReuseResult (mem_allVars hp.mem₁ (Or.inr (by simp)))
          (mem_allVars hp.mem₂ (Or.inr (by simp))) (lhs_mem_allVars hz))
        ((K2ResStep.row_models_iff hp hF hz rho).mpr hm)

/-- **The concretisation does not increase the measure.**  `carried_concretizeSrs` is the
whole content: the budget is spent on CARRIED keys, and the deletion carries every key it
had.  This is the step at which `ResGuardTerm.gmeas` fails (`KeyedLoop`). -/
theorem K2StarLoopStep.measure_step {L : Finset Label} {G G' : System}
    (h : K2StarLoopStep G G') (hcs : ConcSub L G) {rho : Assign} (hm : SModels rho G) :
    ∃ rho', SModels rho' G' ∧ (∀ v ∈ allVars G, rho' v = rho v) ∧
      (allVars G').card + hmeas L rho' G' ≤ (allVars G).card + hmeas L rho G := by
  cases h with
  | additive h => exact h.measure_step hcs hm
  | @concrete u C hmem _ =>
    refine ⟨rho, concretizeSrs_sound hmem rho hm, fun _ _ => rfl, ?_⟩
    have hAV := allVars_concretizeSrs_subset hmem
    have hle : hmeas L rho (concretizeSrs u C G) ≤ hmeas L rho G :=
      hmeas_le_of_carried rho hAV (fun _ _ hr => carried_concretizeSrs hm hmem hr)
    have hcard := Finset.card_le_card hAV
    omega

theorem K2StarLoopStep.concSub {L : Finset Label} {G G' : System} (h : K2StarLoopStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | additive h => exact h.concSub hcs
  | @concrete u C hmem _ => exact concretizeSrs_concSub hmem hcs

theorem K2StarLoopRun.concSub {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K2StarLoopRun n G₀ G) : ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hcs => hstep.concSub (ih hcs)

/-- **The invariant that drives the bound.**  Along a run of the fully rekeyed calculus from
a SATISFIABLE input -- concretisations included -- the number of variables plus the measure
never grows. -/
theorem K2StarLoopRun.invariant {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K2StarLoopRun n G₀ G) :
    ∀ (rho₀ : Assign), SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧
        (allVars G).card + hmeas L rho G ≤ (allVars G₀).card + hmeas L rho₀ G₀ := by
  induction h with
  | refl G => intro rho₀ hm _; exact ⟨rho₀, hm, Nat.le_refl _⟩
  | @tail n G₀ G G' hrun hstep _ ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hb⟩ := ih rho₀ hm hcs
    obtain ⟨rho', hm', -, hb'⟩ := hstep.measure_step (hrun.concSub hcs) hmr
    exact ⟨rho', hm', le_trans hb' hb⟩

/-- **(T1) The vocabulary of a run is bounded by the input alone.** -/
theorem K2StarLoopRun.allVars_card_le {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K2StarLoopRun n G₀ G) (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    (allVars G).card ≤ (allVars G₀).card + hmeas L rho G₀ := by
  obtain ⟨rho', -, hb⟩ := h.invariant rho hm hcs
  omega

/-- **(T1), the headline.**  Minting is BOUNDED on satisfiable input for the loop-extended
calculus in which BOTH minting guards are keyed on `Carried` and the concretisation carries
its `srs` re-expression: no run, in any order, ever exceeds
`|allVars G₀| + hmeas (labelsOf G₀) rho G₀` variables, and only a mint enlarges the
vocabulary. -/
theorem mintsBoundedOnSatKeyed2Star : MintsBoundedOnSatKeyed2Star :=
  fun G₀ rho hm =>
    ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀,
      fun _ _ h => h.allVars_card_le rho hm (labelsOf_concSub G₀)⟩

/-! ### 7.2 The split fragment on its own

Guarded `resolution` is the only rule of `K2LoopStep` that §8 shows unbounded, so it is
worth recording that everything else is bounded: `K2SplitLoopStep` is `K2LoopStep` without
`resolution`, and it embeds in the fully rekeyed calculus. -/

/-- The extended split plus the non-generative rules plus the faithful concretisation --
`K2LoopStep` with guarded `resolution` removed. -/
inductive K2SplitLoopStep : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → K2SplitLoopStep G G'
  | split {G G' : System} : K2SplitStep G G' → K2SplitLoopStep G G'
  | concrete {G : System} {u : Var} {C : Row} :
      mk u ∅ C ∈ G → concretizeSrs u C G ≠ G → K2SplitLoopStep G (concretizeSrs u C G)

inductive K2SplitLoopRun : ℕ → System → System → Prop
  | refl (G : System) : K2SplitLoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      K2SplitLoopRun n G₀ G → K2SplitLoopStep G G' → G ≠ G' → K2SplitLoopRun (n + 1) G₀ G'

theorem K2SplitLoopStep.toStar {G G' : System} (h : K2SplitLoopStep G G') :
    K2StarLoopStep G G' := by
  cases h with
  | nongen h => exact K2StarLoopStep.additive (K2StarStep.nongen h)
  | split h => exact K2StarLoopStep.additive (K2StarStep.split h)
  | concrete hmem hne => exact K2StarLoopStep.concrete hmem hne

theorem K2SplitLoopRun.toStar {n : ℕ} {G₀ G : System} (h : K2SplitLoopRun n G₀ G) :
    K2StarLoopRun n G₀ G := by
  induction h with
  | refl G => exact K2StarLoopRun.refl G
  | tail _ hstep hne ih => exact K2StarLoopRun.tail ih hstep.toStar hne

/-- **(T1) for the split fragment**: with the concrete-row reuse and the faithful `srs`, the
extended `splitConcrete` mints boundedly on satisfiable input under the loop's deletions, in
every order. -/
theorem mintsBoundedOnSat_splitFragment (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K2SplitLoopRun n G₀ G → (allVars G).card ≤ N :=
  ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀,
    fun _ _ h => h.toStar.allVars_card_le rho hm (labelsOf_concSub G₀)⟩

/-! ## 8. (W) for the calculus with guarded `resolution` AS SHIPPED

The Stage 4 clause repairs `splitConcrete`.  It does NOT repair `resolution`, whose mint is
guarded by `Resolved` alone -- and `resolution` has exactly the same disease: the resolvent
`v <- (z, C ∪ D)` it installs is a MENTION of the fresh `z`, so concretising `z` absorbs it
(`KeyedLoop.notMem_lone_mention`) and re-opens the key, while the two premises
`v <- (x, C)`, `v <- (y, D)` are untouched.  `W4` is that engine on three constraints and no
split step at all.

    W4 :  v <- ((|a, b, c|)),   v <- (x, (|a|)),   v <- (y, (|b|))
          model  v = {a,b,c},  x = {b,c},  y = {a,c}

Round: MINT the resolvent `w`, CANCEL it against `v <- ((|a,b,c|))` to get `w <- ((|c|))`,
`makeConcrete w`.  The absorbed resolvent leaves `v <- ((|a,b,c|))`, which was already there,
so the round adds exactly one variable and restores its own hypotheses. -/

/-- The variable both premises partition. -/
abbrev pv : Var := 0
/-- The lone abstract part of the first premise. -/
abbrev px : Var := 1
/-- The lone abstract part of the second premise. -/
abbrev py : Var := 2
/-- The field `a`. -/
abbrev la : Label := 1
/-- The field `b`. -/
abbrev lb : Label := 2
/-- The field `c`, the one neither premise names -- it is what makes the complement
nonempty. -/
abbrev lc : Label := 3

/-- The first premise's concrete part. -/
def CC : Row := {la}
/-- The second premise's concrete part. -/
def DD : Row := {lb}
/-- The concrete value of `pv`. -/
def EE : Row := {la, lb, lc}
/-- The resolvent key `C ∪ D`. -/
def KK : Row := {la, lb}
/-- The row the minted resolvent denotes. -/
def RR : Row := {lc}

theorem CC_union_DD : CC ∪ DD = KK := by decide
theorem EE_sdiff_KK : EE \ KK = RR := by decide
theorem KK_subset_EE : KK ⊆ EE := by decide

def W4conc : Constraint := mk pv ∅ EE
def W4p1 : Constraint := mk pv {px} CC
def W4p2 : Constraint := mk pv {py} DD

/-- **The witness.**  Three constraints, three variables, three labels; satisfiable
(`W4_models`); no split premise anywhere (every right-hand side has at most one variable, so
`splitConcrete`'s `abstr.size >= 2` guard never fires). -/
def W4 : System := {W4conc, W4p1, W4p2}

def rho4 : Assign :=
  fun w => if w = pv then EE else if w = px then EE \ CC else if w = py then EE \ DD else ∅

theorem W4_models : SModels rho4 W4 := by
  intro c hc
  simp only [W4, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl
  · rw [W4conc, sat_mk_iff]
    refine ⟨by simp [rho4, EE], by simp, by simp⟩
  · rw [W4p1, sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩
    · simp only [Finset.singleton_biUnion]
      decide
    · intro v hv
      rw [Finset.mem_singleton] at hv
      subst hv
      decide
    · intro v hv w hw hvw
      rw [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw
  · rw [W4p2, sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩
    · simp only [Finset.singleton_biUnion]
      decide
    · intro v hv
      rw [Finset.mem_singleton] at hv
      subst hv
      decide
    · intro v hv w hw hvw
      rw [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw

theorem W4_satisfiable : ∃ rho, SModels rho W4 := ⟨rho4, W4_models⟩

/-- **The invariant the engine restores every round.**  `pv` is concrete, it has two lone
premises with incomparable concrete parts, and the resolvent key is OPEN. -/
structure W4Inv (G : System) : Prop where
  intro ::
  /-- the concrete value of `pv` -/
  conc : W4conc ∈ G
  /-- the first premise -/
  p1 : W4p1 ∈ G
  /-- the second premise -/
  p2 : W4p2 ∈ G
  /-- the resolvent key is open -/
  unres : ¬ Resolved G pv KK

theorem W4_inv : W4Inv W4 := by
  refine ⟨by simp [W4], by simp [W4], by simp [W4], ?_⟩
  intro hr
  obtain ⟨s, hs⟩ := (resolved_iff _ _ _).mp hr
  simp only [W4, W4conc, W4p1, W4p2, Finset.mem_insert, Finset.mem_singleton] at hs
  rcases hs with hh | hh | hh
  · exact absurd (NameLoss.mk_eq_iff.mp hh).2.1 (Finset.singleton_ne_empty s)
  · exact absurd (NameLoss.mk_eq_iff.mp hh).2.2 (by decide)
  · exact absurd (NameLoss.mk_eq_iff.mp hh).2.2 (by decide)

/-- The system after the round's resolution MINT. -/
def S1 (G : System) (w : Var) : System := resResult G pv px py CC DD w

/-- ... and after the round's CANCELLATION. -/
def S2 (G : System) (w : Var) : System := insert (mk w ∅ RR) (S1 G w)

theorem mem_S2 (G : System) (w : Var) {c : Constraint} :
    c ∈ S2 G w ↔ c = mk w ∅ RR ∨ c = mk pv {w} (CC ∪ DD) ∨ c = mk px {w} (DD \ CC) ∨
      c = mk py {w} (CC \ DD) ∨ c ∈ G := by
  simp only [S2, S1, resResult, Finset.mem_insert]

theorem subset_S1 (G : System) (w : Var) : G ⊆ S1 G w := subset_resResult _ _ _ _ _ _ _

theorem subset_S2 (G : System) (w : Var) : G ⊆ S2 G w := fun _ hc =>
  Finset.mem_insert_of_mem (subset_S1 G w hc)

/-- **The round.**  Three productive steps of `K2LoopStep` -- and the FIRST of them is a
guarded-resolution mint, not a split: nothing in `W4` is a split premise at all. -/
theorem W4Inv.round {G : System} (h : W4Inv G) :
    ∃ G', K2LoopRun 3 G G' ∧ KeyedLoop.KLoopRun 3 G G' ∧ W4Inv G' ∧
      (allVars G).card < (allVars G').card := by
  obtain ⟨w, hw⟩ := exists_fresh (allVars G)
  have hpvG : pv ∈ allVars G := lhs_mem_allVars h.conc
  have hpxG : px ∈ allVars G :=
    mem_allVars h.p1 (Or.inr (by rw [W4p1, vset_mk]; exact Finset.mem_singleton_self px))
  have hpyG : py ∈ allVars G :=
    mem_allVars h.p2 (Or.inr (by rw [W4p2, vset_mk]; exact Finset.mem_singleton_self py))
  have hwpv : w ≠ pv := by rintro rfl; exact hw hpvG
  have hwpx : w ≠ px := by rintro rfl; exact hw hpxG
  have hwpy : w ≠ py := by rintro rfl; exact hw hpyG
  have hkey_notmem : ∀ s : Var, mk pv {s} KK ∉ G := fun s hs => h.unres (resolved_of_mem hs)
  have hpair : ResPair G pv px py CC DD := ⟨h.p1, h.p2, by decide, by decide⟩
  -- STEP 1: the guarded resolution MINT
  have hstep1 : K2LoopStep G (S1 G w) :=
    K2LoopStep.additive (K2DefaultStep.gres
      (GResStep.mint hpair (by rw [CC_union_DD]; exact h.unres) hw))
  have hmem1 : mk pv {w} KK ∈ S1 G w := by
    rw [← CC_union_DD]
    exact Finset.mem_insert_self _ _
  have hne1 : G ≠ S1 G w := fun hh => hkey_notmem w (hh ▸ hmem1)
  -- STEP 2: the CANCELLATION against the concrete value
  have hcancelApp : CancelApp (S1 G w) (mk pv {w} (CC ∪ DD)) W4conc w := by
    refine ⟨Finset.mem_insert_self _ _, subset_S1 G w h.conc, rfl, ?_, ?_⟩
    · rw [conc_mk, W4conc, conc_mk, CC_union_DD]; exact KK_subset_EE
    · rw [vset_mk, W4conc, vset_mk, Finset.sdiff_empty]
  have hcancelEq : cancelResult (S1 G w) (mk pv {w} (CC ∪ DD)) W4conc w = S2 G w := by
    simp only [cancelResult, S2, W4conc, vset_mk, conc_mk, Finset.empty_sdiff, CC_union_DD,
      EE_sdiff_KK]
  have hstep2 : K2LoopStep (S1 G w) (S2 G w) := by
    rw [← hcancelEq]
    exact K2LoopStep.additive (K2DefaultStep.nongen
      (NonGenStep.cancel (CancelStep.intro hcancelApp)))
  have hne2 : S1 G w ≠ S2 G w := by
    intro hh
    have hmem : mk w ∅ RR ∈ S1 G w := hh ▸ (show mk w ∅ RR ∈ S2 G w by simp [S2])
    simp only [S1, resResult, Finset.mem_insert] at hmem
    rcases hmem with h1 | h1 | h1 | h1
    · exact absurd (NameLoss.mk_eq_iff.mp h1).2.1.symm (Finset.singleton_ne_empty w)
    · exact absurd (NameLoss.mk_eq_iff.mp h1).2.1.symm (Finset.singleton_ne_empty w)
    · exact absurd (NameLoss.mk_eq_iff.mp h1).2.1.symm (Finset.singleton_ne_empty w)
    · exact hw (lhs_mem_allVars h1)
  -- STEP 3: `makeConcrete w` -- the destructive rewrite of the resolvent MENTION
  have hmemR : mk w ∅ RR ∈ S2 G w := (mem_S2 G w).mpr (Or.inl rfl)
  have hres3 : ¬ Resolved (concretizeSrs w RR (S2 G w)) pv KK := by
    intro hr
    obtain ⟨s, hs⟩ := (resolved_iff _ _ _).mp hr
    rcases mem_concretizeSrs.mp hs with hs | ⟨t, K', -, heq⟩
    · rcases mem_concretizeKeep.mp hs with heq | ⟨d, hd, hdw, hab⟩ | ⟨-, h1, -⟩
      · exact absurd (NameLoss.mk_eq_iff.mp heq).2.1 (Finset.singleton_ne_empty s)
      · by_cases hmem : w ∈ vset d
        · have habs : absorbC w RR d = mk d.lhs ((vset d).erase w) (d.conc ∪ RR) := by
            unfold absorbC; rw [if_pos hmem]
          rw [habs] at hab
          have hcc : d.conc ∪ RR = KK := (NameLoss.mk_eq_iff.mp hab).2.2
          have hfc : lc ∈ KK := by
            rw [← hcc]; exact Finset.mem_union_right _ (by decide)
          exact absurd hfc (by decide)
        · rw [absorbC_of_notMem hmem] at hab
          subst hab
          rcases (mem_S2 G w).mp hd with heq | heq | heq | heq | hmemG
          · exact absurd (NameLoss.mk_eq_iff.mp heq).2.1 (Finset.singleton_ne_empty s)
          · have hsw : s = w := by
              have h5 : s ∈ ({w} : Finset Var) := by
                rw [← (NameLoss.mk_eq_iff.mp heq).2.1]; exact Finset.mem_singleton_self s
              exact Finset.mem_singleton.mp h5
            exact hmem (by rw [vset_mk, hsw]; exact Finset.mem_singleton_self w)
          · exact absurd (NameLoss.mk_eq_iff.mp heq).1 (by decide)
          · exact absurd (NameLoss.mk_eq_iff.mp heq).1 (by decide)
          · exact hkey_notmem s hmemG
      · rw [lhs_mk] at h1; exact hwpv h1.symm
    · exact absurd (NameLoss.mk_eq_iff.mp heq).2.1 (Finset.singleton_ne_empty s)
  have hsub3 : G ⊆ concretizeSrs w RR (S2 G w) :=
    fun c hc => concretizeKeep_subset_srs w RR (S2 G w)
      (KeyedLoop.subset_concretizeKeep_of_fresh (subset_S2 G w) hw hc)
  have hne3 : S2 G w ≠ concretizeSrs w RR (S2 G w) := by
    intro hh
    have hmemKey : mk pv {w} KK ∈ S2 G w := by
      rw [← CC_union_DD]
      exact (mem_S2 G w).mpr (Or.inr (Or.inl rfl))
    exact hres3 (resolved_of_mem (hh ▸ hmemKey))
  have hstep3 : K2LoopStep (S2 G w) (concretizeSrs w RR (S2 G w)) :=
    K2LoopStep.concrete hmemR (Ne.symm hne3)
  have hwmem : w ∈ allVars (concretizeSrs w RR (S2 G w)) :=
    mem_allVars (concDef_mem_concretizeSrs w RR (S2 G w)) (Or.inl rfl)
  have hcard : (allVars G).card < (allVars (concretizeSrs w RR (S2 G w))).card :=
    Finset.card_lt_card ((Finset.ssubset_iff_of_subset (allVars_mono hsub3)).mpr ⟨w, hwmem, hw⟩)
  -- the SAME three steps are steps of Stage 3's `KLoopStep`: `srsOf` is empty here, because
  -- the freshly minted `w` has no one-abstract definition to re-express
  have hsrsNone : ∀ (s : Var) (K' : Row), mk w {s} K' ∉ S2 G w := by
    intro s K' hmemw
    rcases (mem_S2 G w).mp hmemw with heq | heq | heq | heq | hmemG
    · exact absurd (NameLoss.mk_eq_iff.mp heq).2.1 (Finset.singleton_ne_empty s)
    · exact hwpv (NameLoss.mk_eq_iff.mp heq).1
    · exact hwpx (NameLoss.mk_eq_iff.mp heq).1
    · exact hwpy (NameLoss.mk_eq_iff.mp heq).1
    · exact hw (lhs_mem_allVars hmemG)
  have hEq : concretizeSrs w RR (S2 G w) = concretizeKeep w RR (S2 G w) :=
    concretizeSrs_eq_concretizeKeep hsrsNone
  have hstep1' : KeyedLoop.KLoopStep G (S1 G w) :=
    KeyedLoop.KLoopStep.additive (KDefaultStep.gres
      (GResStep.mint hpair (by rw [CC_union_DD]; exact h.unres) hw))
  have hstep2' : KeyedLoop.KLoopStep (S1 G w) (S2 G w) := by
    rw [← hcancelEq]
    exact KeyedLoop.KLoopStep.additive (KDefaultStep.nongen
      (NonGenStep.cancel (CancelStep.intro hcancelApp)))
  have hstep3' : KeyedLoop.KLoopStep (S2 G w) (concretizeSrs w RR (S2 G w)) := by
    rw [hEq]
    exact KeyedLoop.KLoopStep.concrete hmemR (by rw [← hEq]; exact Ne.symm hne3)
  refine ⟨concretizeSrs w RR (S2 G w), ?_, ?_,
    ⟨hsub3 h.conc, hsub3 h.p1, hsub3 h.p2, hres3⟩, hcard⟩
  · exact K2LoopRun.tail (K2LoopRun.tail (K2LoopRun.tail (K2LoopRun.refl G) hstep1 hne1)
      hstep2 hne2) hstep3 hne3
  · exact KeyedLoop.KLoopRun.tail (KeyedLoop.KLoopRun.tail
      (KeyedLoop.KLoopRun.tail (KeyedLoop.KLoopRun.refl G) hstep1' hne1) hstep2' hne2)
      hstep3' hne3

theorem K2LoopRun.append {m n : ℕ} {G₀ G G' : System} (h1 : K2LoopRun m G₀ G)
    (h2 : K2LoopRun n G G') : K2LoopRun (m + n) G₀ G' := by
  revert h1
  induction h2 with
  | refl G => intro h1; simpa using h1
  | tail _ hstep hne ih =>
    intro h1
    rw [← Nat.add_assoc]
    exact K2LoopRun.tail (ih h1) hstep hne

theorem W4Inv.run {G : System} (h : W4Inv G) (n : ℕ) :
    ∃ G', K2LoopRun (3 * n) G G' ∧ KeyedLoop.KLoopRun (3 * n) G G' ∧ W4Inv G' ∧
      (allVars G).card + n ≤ (allVars G').card := by
  induction n with
  | zero => exact ⟨G, K2LoopRun.refl G, KeyedLoop.KLoopRun.refl G, h, by omega⟩
  | succ n ih =>
    obtain ⟨G', hrun, hrunK, hinv, hcard⟩ := ih
    obtain ⟨G'', hrun', hrunK', hinv', hcard'⟩ := hinv.round
    have h3 : 3 * (n + 1) = 3 * n + 3 := by omega
    refine ⟨G'', ?_, ?_, hinv', by omega⟩
    · rw [h3]; exact hrun.append hrun'
    · rw [h3]; exact hrunK.append hrunK'

theorem allVars_W4 : allVars W4 = {pv, px, py} := by
  simp only [allVars, W4, W4conc, W4p1, W4p2, Finset.biUnion_insert, Finset.singleton_biUnion,
    vset_mk, lhs_mk]
  decide

theorem card_allVars_W4 : (allVars W4).card = 3 := by rw [allVars_W4]; decide

/-- **(W).**  For every `n` the satisfiable `W4` admits a productive run of `3 * n` loop
steps whose vocabulary has grown by `n` variables -- i.e. `n` mints, since only a mint
enlarges the vocabulary.  Every one of them is a guarded-RESOLUTION mint. -/
theorem W4_mints_unbounded (n : ℕ) :
    ∃ G, K2LoopRun (3 * n) W4 G ∧ n + 3 ≤ (allVars G).card := by
  obtain ⟨G, hrun, -, -, hcard⟩ := W4_inv.run n
  refine ⟨G, hrun, ?_⟩
  rw [card_allVars_W4] at hcard
  omega

/-- **The loop-layer divergence needs no split step.**  The very same run is a run of Stage
3's `KeyedLoop.KLoopStep` -- on this witness the faithful deletion and `concretizeKeep`
coincide, because the freshly minted `w` has no one-abstract definition for `srsOf` to
re-express.  So `KeyedLoop.not_TerminatesOnSatKeyedLoop` has a witness in which
`splitConcrete` never fires at all: `W4`'s right-hand sides all have at most one variable, so
its `abstr.size >= 2` guard is never met.  Stage 3's `W3` does not have this property. -/
theorem W4_kloop_mints_unbounded (n : ℕ) :
    ∃ G, KeyedLoop.KLoopRun (3 * n) W4 G ∧ n + 3 ≤ (allVars G).card := by
  obtain ⟨G, -, hrunK, -, hcard⟩ := W4_inv.run n
  refine ⟨G, hrunK, ?_⟩
  rw [card_allVars_W4] at hcard
  omega

/-- **... and so it refutes Stage 3's statement too.**  A second, split-free proof of
`KeyedLoop.not_TerminatesOnSatKeyedLoop`. -/
theorem W4_not_TerminatesOnSatKeyedLoop : ¬ KeyedLoop.TerminatesOnSatKeyedLoop := by
  intro hT
  obtain ⟨N, hN⟩ := hT W4 rho4 W4_models
  obtain ⟨G, hrun, -⟩ := W4_kloop_mints_unbounded (N + 1)
  have := hN _ G hrun
  omega

/-- **The Stage 4 answer for the relation with `resolution` AS SHIPPED: (W).**  The
concrete-row reuse bounds the SPLIT (`mintsBoundedOnSat_splitFragment`) and cannot bound the
calculus, because guarded resolution's own guard is still keyed on `Resolved`, which the
deletion destroys. -/
theorem not_MintsBoundedOnSatKeyed2 : ¬ MintsBoundedOnSatKeyed2 := by
  intro hT
  obtain ⟨N, hN⟩ := hT W4 rho4 W4_models
  obtain ⟨G, hrun, hcard⟩ := W4_mints_unbounded (N + 1)
  have := hN _ G hrun
  omega

/-- **The contrast, in one statement.**  Rekeying BOTH guards on `Carried` and carrying the
`srs` re-expression bounds minting on every satisfiable input in every order; rekeying only
the split does not. -/
theorem keyed2_star_vs_shipped_res :
    MintsBoundedOnSatKeyed2Star ∧ ¬ MintsBoundedOnSatKeyed2 :=
  ⟨mintsBoundedOnSatKeyed2Star, not_MintsBoundedOnSatKeyed2⟩

/-! ## 9. Reading the headline, and soundness of the loop relations

`W4_mints_unbounded` and the bound of §7 are both statements about VOCABULARY.  They say
what they are meant to say because only a MINT enlarges the vocabulary. -/

theorem K2DefaultStep.allVars_cases {G G' : System} (h : K2DefaultStep G G') :
    allVars G' = allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G) := by
  cases h with
  | nongen h => exact Or.inl h.allVars_eq
  | split h => exact h.allVars_cases
  | gres h => exact h.allVars_cases

theorem K2StarStep.allVars_cases {G G' : System} (h : K2StarStep G G') :
    allVars G' = allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G) := by
  cases h with
  | nongen h => exact Or.inl h.allVars_eq
  | split h => exact h.allVars_cases
  | res h => exact h.allVars_cases

/-- **Every loop step either keeps the vocabulary, shrinks it, or adds exactly one fresh
variable** -- and only the two mints do the last. -/
theorem K2LoopStep.allVars_cases {G G' : System} (h : K2LoopStep G G') :
    allVars G' ⊆ allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G) := by
  cases h with
  | additive h =>
    rcases h.allVars_cases with hV | hV
    · exact Or.inl (le_of_eq hV)
    · exact Or.inr hV
  | concrete hmem _ => exact Or.inl (allVars_concretizeSrs_subset hmem)

theorem K2StarLoopStep.allVars_cases {G G' : System} (h : K2StarLoopStep G G') :
    allVars G' ⊆ allVars G ∨ ∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G) := by
  cases h with
  | additive h =>
    rcases h.allVars_cases with hV | hV
    · exact Or.inl (le_of_eq hV)
    · exact Or.inr hV
  | concrete hmem _ => exact Or.inl (allVars_concretizeSrs_subset hmem)

/-- **Soundness of one loop step.**  One direction only: a concretise step deletes, so a
model of the successor need not model the predecessor. -/
theorem K2LoopStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : K2LoopStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | additive h =>
    cases h with
    | nongen h => exact ⟨rho, (h.models_iff rho).mp hm, fun _ _ => rfl⟩
    | split h => exact K2SplitStep.extend hm h
    | gres h => exact KDefaultStep.extend hm (KDefaultStep.gres h)
  | concrete hmem _ => exact ⟨rho, concretizeSrs_sound hmem rho hm, fun _ _ => rfl⟩

theorem K2StarLoopStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : K2StarLoopStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | additive h =>
    cases h with
    | nongen h => exact ⟨rho, (h.models_iff rho).mp hm, fun _ _ => rfl⟩
    | split h => exact K2SplitStep.extend hm h
    | res h => exact K2ResStep.extend hm h
  | concrete hmem _ => exact ⟨rho, concretizeSrs_sound hmem rho hm, fun _ _ => rfl⟩

theorem K2LoopStep.sat_mono {G G' : System} (h : K2LoopStep G G') :
    (∃ rho, SModels rho G) → ∃ rho, SModels rho G' := by
  rintro ⟨rho, hm⟩
  obtain ⟨rho', hm', -⟩ := h.extend hm
  exact ⟨rho', hm'⟩

theorem K2LoopRun.sat_mono {n : ℕ} {G₀ G : System} (h : K2LoopRun n G₀ G) :
    (∃ rho, SModels rho G₀) → ∃ rho, SModels rho G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hs => hstep.sat_mono (ih hs)

/-! ## 10. The Stage 3 witness, re-run under the Stage 4 rule

`KeyedLoop.W3 = {u <- ((|k,c|)), u <- (z, (|k|)), u <- (x, y, (|k|))}`.  Stage 3's
`concretizeKeep u C W3` is `W3sat = {u <- ((|k,c|)), u <- (x, y, (|k|))}`, at which BOTH of
the shipped lookups miss and the re-mint is enabled (`KeyedLoop.W3sat_remint_enabled`).  With
the `srs` re-expression the same step reaches `W3sat` PLUS `z <- ((|c|))`, and there the
CONCRETE-ROW branch fires: no mint, and the name the compiler's `common` would produce after
the fact is produced by the rule instead. -/

theorem srsOf_W3 :
    srsOf KeyedLoop.u KeyedLoop.C KeyedLoop.W3 = {mk KeyedLoop.z ∅ KeyedLoop.D} := by
  ext d
  rw [mem_srsOf, Finset.mem_singleton]
  constructor
  · rintro ⟨z', K', hmem, rfl⟩
    simp only [KeyedLoop.W3, KeyedLoop.W3conc, KeyedLoop.W3key, KeyedLoop.W3def,
      Finset.mem_insert, Finset.mem_singleton] at hmem
    rcases hmem with hh | hh | hh
    · exact absurd (NameLoss.mk_eq_iff.mp hh).2.1 (Finset.singleton_ne_empty z')
    · obtain ⟨-, hs, hk⟩ := NameLoss.mk_eq_iff.mp hh
      have hz : z' = KeyedLoop.z := Finset.singleton_injective hs
      rw [hz, hk, KeyedLoop.C_sdiff_K]
    · obtain ⟨-, hs, -⟩ := NameLoss.mk_eq_iff.mp hh
      have h5 : KeyedLoop.x ∈ ({z'} : Finset Var) := by rw [hs]; decide
      have h6 : KeyedLoop.y ∈ ({z'} : Finset Var) := by rw [hs]; decide
      rw [Finset.mem_singleton] at h5 h6
      exact absurd (h5.trans h6.symm) (by decide)
  · rintro rfl
    exact ⟨KeyedLoop.z, KeyedLoop.K, by simp [KeyedLoop.W3, KeyedLoop.W3key],
      by rw [KeyedLoop.C_sdiff_K]⟩

/-- **What the FAITHFUL `makeConcrete u` reaches**: Stage 3's `W3sat` together with the
cancellation fact `z <- ((|c|))` that `makeConcrete` derives from the definition it is about
to delete. -/
theorem W3srs_eq : concretizeSrs KeyedLoop.u KeyedLoop.C KeyedLoop.W3
    = insert (mk KeyedLoop.z ∅ KeyedLoop.D) KeyedLoop.W3sat := by
  rw [concretizeSrs, KeyedLoop.W3_concretize_eq, srsOf_W3]
  ext c
  simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  tauto

/-- **The key the Stage 3 engine re-opened is CARRIED.** -/
theorem W3_carried :
    Carried (concretizeSrs KeyedLoop.u KeyedLoop.C KeyedLoop.W3) KeyedLoop.u KeyedLoop.K :=
  carried_of_deleted_def
    (show mk KeyedLoop.u {KeyedLoop.z} KeyedLoop.K ∈ KeyedLoop.W3 by
      simp [KeyedLoop.W3, KeyedLoop.W3key])

/-- **So the Stage 3 re-mint is refused**, for every candidate fresh name. -/
theorem W3_not_mintable (w : Var) :
    ¬ K2MintApp (concretizeSrs KeyedLoop.u KeyedLoop.C KeyedLoop.W3) KeyedLoop.W3def w :=
  fun happ => happ.uncarried W3_carried

/-- **... and the CONCRETE-ROW branch fires instead**, emitting exactly `z <- (x, y)` -- the
constraint the shipped loop reaches only afterwards, by `common`-unifying the re-minted name
with `z`.  `KEYED-LOOP-STAGE3.md` §3.1 measures that unification at 55 of 55 bases; here it
is the rule. -/
theorem W3_row_reuse :
    K2RowApp (concretizeSrs KeyedLoop.u KeyedLoop.C KeyedLoop.W3) KeyedLoop.W3def
      KeyedLoop.z KeyedLoop.C := by
  have hmemDef : KeyedLoop.W3def ∈ concretizeSrs KeyedLoop.u KeyedLoop.C KeyedLoop.W3 := by
    rw [W3srs_eq]; simp [KeyedLoop.W3sat]
  refine ⟨hmemDef, ?_, ?_, ?_, ?_, ?_⟩
  · rw [KeyedLoop.W3def, conc_mk]; exact KeyedLoop.K_ne
  · rw [KeyedLoop.W3def, vset_mk]; decide
  · rw [KeyedLoop.W3def, vset_mk]
    rintro ⟨d, hd, hvs, hc⟩
    rw [W3srs_eq] at hd
    simp only [KeyedLoop.W3sat, KeyedLoop.W3conc, KeyedLoop.W3def, Finset.mem_insert,
      Finset.mem_singleton] at hd
    rcases hd with rfl | rfl | rfl
    · rw [vset_mk] at hvs; exact absurd hvs.symm (by decide)
    · rw [vset_mk] at hvs; exact absurd hvs.symm (by decide)
    · rw [conc_mk] at hc; exact absurd hc KeyedLoop.K_ne
  · rw [KeyedLoop.W3def, lhs_mk]
    exact concDef_mem_concretizeSrs _ _ _
  · rw [KeyedLoop.W3def, conc_mk, KeyedLoop.C_sdiff_K, W3srs_eq]
    simp

end KeyedRow
end Rowpartition
