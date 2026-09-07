/-
# S4: the written-partition normalisation is an EQUIVALENCE, not a weakening

`tracker/loopmodel/S4-DESIGN.md` option (i).  When one left-hand side `v` carries `k` reads

    v <- (x_1, F_1)   …   v <- (x_k, F_k)          (each a LONE-ABSTRACT premise)

— which is exactly what `k` projections `p ! f_i` of one open-row record parameter give
(`S4-DESIGN.md` §1, measured off the compiler's `scon` records) — the normalisation replaces
all `k` of them by the single WRITTEN partition and its `k` re-expressions:

    v <- (c, F)          F = F_1 ∪ … ∪ F_k,  c fresh
    x_i <- (c, F \ F_i)  for each i

This file proves, in the `Sat` / `SEntails` vocabulary of `Rowpartition/Divergence.lean`
(the one `Loop/Strict.lean`'s `NoLoss` and `Conserv` are stated in), that the replacement
loses nothing and invents nothing:

* `read_of_top` — each ORIGINAL read is a semantic consequence of the two replacements, with
  no side condition beyond `F_i ⊆ F`.  This is `Loop/Strict.lean`'s `NoLoss`, and it is what
  makes the DELETION of the premises legitimate: `noloss_of_top` states it for a system.
* `top_sat` / `reexpr_sat` — every model of the reads extends, by the UNIQUE choice
  `c := v \ F`, to a model of both replacements.  Together with `read_of_top` that is
  satisfiability-equivalence in both directions (`ssat_topRewrite_iff`), and it is the same
  status the shipped `resolution` mint has: the introduced name is FORCED, not free
  (`top_forced`), so this is a conservative (definitional) extension, not a plain entailment
  in the old vocabulary — the old vocabulary has no name for `v \ F`.  The existentially
  closed form IS entailed, which is `read_of_top` read backwards.

**Round 2 (2026-09-07, after `S4A-REVIEW.md` G-1).**  Round 1 stated the extension for the
FAMILY only — its freshness premises were `c ≠ v` and `c ≠ x_i`, which say nothing about the rest
of the system, while the shipped `resolution` mint's `Cut.ResApp` carries `fresh : z ∉ allVars G`.
`ssat_rewrite_fwd` below is the whole-SYSTEM direction with that premise, proved from the
library's own `sModels_setVar`; it is the reviewer's `GapCheck.lean`, adopted verbatim in
substance.  Round 1 also wrote the extension with `Function.update` where the library uses
`setVar`; §0 proves they agree and everything below is now stated in `setVar`.  §5 answers the
brief's question "which `LoopStrict` constructor is it?" — **two steps, not one**.

Round 1 also cited a theorem `ssat_topRewrite_iff` that does not exist (G-8); the pair that does
the work is `models_rewrite` (forwards, family) / `ssat_rewrite_fwd` (forwards, system) and
`reads_of_rewrite` (backwards).

Run: `cd tracker/lean && lake env lean ../loopmodel/S4Top.lean`.
-/
import Rowpartition.Divergence
import Rowpartition.Loop.Strict

namespace Rowpartition
namespace S4

open Finset

/-! ## 0. `setVar` is the library's `Function.update` (G-1) -/

/-- The library states its extension lemmas about `setVar` (`Divergence.lean:217`); this file
used to state its own about `Function.update`.  They are the same function, so `sModels_setVar`
applies to everything below without a rewrite at each use. -/
theorem setVar_eq_update (rho : Assign) (z : Var) (r : Row) :
    setVar rho z r = Function.update rho z r := by
  funext w
  by_cases h : w = z
  · subst h; simp [setVar]
  · simp [setVar, h]

/-! ## 1. A read pins its concrete part inside the left-hand row -/

/-- `v <- (x, C)` gives `rho v = C ∪ rho x` with `C` and `rho x` disjoint, so `C ⊆ rho v`
and `rho x` is exactly `rho v \ C`. -/
theorem read_eq {rho : Assign} {v x : Var} {C : Row} (h : Sat rho (mk v {x} C)) :
    rho v = C ∪ rho x ∧ Disjoint C (rho x) := by
  rw [sat_mk_iff] at h
  obtain ⟨he, hk, _⟩ := h
  refine ⟨by simpa using he, hk x (by simp)⟩

theorem conc_subset_lhs {rho : Assign} {v x : Var} {C : Row} (h : Sat rho (mk v {x} C)) :
    C ⊆ rho v := by
  rw [(read_eq h).1]; exact subset_union_left

theorem rem_eq {rho : Assign} {v x : Var} {C : Row} (h : Sat rho (mk v {x} C)) :
    rho x = rho v \ C := by
  obtain ⟨he, hd⟩ := read_eq h
  ext l
  simp only [he, mem_sdiff, mem_union]
  constructor
  · intro hl; exact ⟨Or.inr hl, fun hC => (disjoint_left.mp hd) hC hl⟩
  · rintro ⟨hl | hl, hn⟩
    · exact absurd hl hn
    · exact hl

/-! ## 2. NoLoss: each original read follows from the two replacements -/

/-- **The deletion is legitimate.**  `v <- (c, F)` and `x <- (c, F \ C)` with `C ⊆ F` entail
the read `v <- (x, C)` — no freshness, no side condition, nothing about the rest of the
system. -/
theorem read_of_top {rho : Assign} {v x c : Var} {C F : Row} (hCF : C ⊆ F)
    (htop : Sat rho (mk v {c} F)) (hre : Sat rho (mk x {c} (F \ C))) :
    Sat rho (mk v {x} C) := by
  obtain ⟨hev, hdv⟩ := read_eq htop
  obtain ⟨hex, hdx⟩ := read_eq hre
  rw [sat_mk_iff]
  refine ⟨?_, ?_, ?_⟩
  · have : C ∪ rho x = F ∪ rho c := by
      rw [hex, ← union_assoc, union_sdiff_of_subset hCF]
    simpa using this ▸ hev
  · intro w hw
    have hwx : w = x := by simpa using hw
    subst hwx
    rw [hex]
    refine disjoint_union_right.mpr ⟨?_, ?_⟩
    · exact disjoint_sdiff_self_right
    · exact (disjoint_left.mpr (fun l hl hlc =>
        (disjoint_left.mp hdv) (hCF hl) hlc))
  · intro w hw w' hw' hne
    simp only [mem_singleton] at hw hw'
    exact absurd (hw.trans hw'.symm) hne

/-- The system form: after the rewrite the system still entails every read it deleted. -/
theorem noloss_of_top {G : System} {v x c : Var} {C F : Row} (hCF : C ⊆ F)
    (htop : mk v {c} F ∈ G) (hre : mk x {c} (F \ C) ∈ G) :
    SEntails G (mk v {x} C) :=
  fun _ hm => read_of_top hCF (hm _ htop) (hm _ hre)

/-! ## 3. Conserv, modulo the fresh name: the carrier is FORCED -/

/-- The introduced name is not free: any model of `v <- (c, F)` has `rho c = rho v \ F`.
This is the `resolvent_unique` of `ResGuard.lean` for the k-ary rule, and it is why the
rewrite is a CONSERVATIVE extension rather than an arbitrary addition. -/
theorem top_forced {rho : Assign} {v c : Var} {F : Row} (h : Sat rho (mk v {c} F)) :
    rho c = rho v \ F := rem_eq h

/-- `F = ⋃ F_i` sits inside the left-hand row when every `F_i` does. -/
theorem union_subset_lhs {rho : Assign} {v : Var} {fam : List (Var × Row)}
    (h : ∀ p ∈ fam, Sat rho (mk v {p.1} p.2)) :
    fam.foldr (fun p a => p.2 ∪ a) ∅ ⊆ rho v := by
  induction fam with
  | nil => simp
  | cons p ps ih =>
    simp only [List.foldr_cons]
    exact union_subset (conc_subset_lhs (h p (by simp)))
      (ih (fun q hq => h q (by simp [hq])))

/-- **The extension exists.**  With `c` fresh (distinct from `v`) and `F ⊆ rho v`, the update
`c := rho v \ F` satisfies the written partition. -/
theorem top_sat {rho : Assign} {v c : Var} {F : Row} (hne : c ≠ v) (hF : F ⊆ rho v) :
    Sat (setVar rho c (rho v \ F)) (mk v {c} F) := by
  rw [sat_mk_iff]
  have hv : setVar rho c (rho v \ F) v = rho v := by simp [setVar, Ne.symm hne]
  have hc : setVar rho c (rho v \ F) c = rho v \ F := by simp [setVar]
  refine ⟨?_, ?_, ?_⟩
  · simpa [hv, hc] using (union_sdiff_of_subset hF).symm
  · intro w hw
    have : w = c := by simpa using hw
    subst this
    simpa [hc] using disjoint_sdiff_self_right
  · intro w hw w' hw' hne'
    simp only [mem_singleton] at hw hw'
    exact absurd (hw.trans hw'.symm) hne'

/-- **The extension satisfies the re-expressions.**  The same update turns each read
`v <- (x, C)` into `x <- (c, F \ C)`. -/
theorem reexpr_sat {rho : Assign} {v x c : Var} {C F : Row}
    (hne : c ≠ v) (hnx : c ≠ x) (hCF : C ⊆ F) (hF : F ⊆ rho v)
    (hread : Sat rho (mk v {x} C)) :
    Sat (setVar rho c (rho v \ F)) (mk x {c} (F \ C)) := by
  have hx : setVar rho c (rho v \ F) x = rho x := by simp [setVar, Ne.symm hnx]
  have hc : setVar rho c (rho v \ F) c = rho v \ F := by simp [setVar]
  rw [sat_mk_iff]
  refine ⟨?_, ?_, ?_⟩
  · simp only [Finset.singleton_biUnion, hc, hx, rem_eq hread]
    ext l
    simp only [mem_union, mem_sdiff]
    constructor
    · rintro ⟨hl, hn⟩
      by_cases hlF : l ∈ F
      · exact Or.inl ⟨hlF, hn⟩
      · exact Or.inr ⟨hl, hlF⟩
    · rintro (⟨hl, hn⟩ | ⟨hl, hn⟩)
      · exact ⟨hF hl, hn⟩
      · exact ⟨hl, fun hlC => hn (hCF hlC)⟩
  · intro w hw
    have : w = c := by simpa using hw
    subst this
    rw [hc]
    exact disjoint_left.mpr (fun l hl hl' => (mem_sdiff.mp hl').2 (mem_sdiff.mp hl).1)
  · intro w hw w' hw' hne'
    simp only [mem_singleton] at hw hw'
    exact absurd (hw.trans hw'.symm) hne'

/-! ## 4. The two halves, as one statement about a system -/

/-- Every model of the reads extends to a model of the whole rewritten family. -/
theorem models_rewrite {rho : Assign} {v c : Var} {fam : List (Var × Row)} {F : Row}
    (hne : c ≠ v) (hnx : ∀ p ∈ fam, c ≠ p.1) (hCF : ∀ p ∈ fam, p.2 ⊆ F) (hF : F ⊆ rho v)
    (h : ∀ p ∈ fam, Sat rho (mk v {p.1} p.2)) :
    Sat (setVar rho c (rho v \ F)) (mk v {c} F) ∧
    ∀ p ∈ fam, Sat (setVar rho c (rho v \ F)) (mk p.1 {c} (F \ p.2)) :=
  ⟨top_sat hne hF, fun p hp => reexpr_sat hne (hnx p hp) (hCF p hp) hF (h p hp)⟩

/-- …and the rewritten family gives every read back. -/
theorem reads_of_rewrite {rho : Assign} {v c : Var} {fam : List (Var × Row)} {F : Row}
    (hCF : ∀ p ∈ fam, p.2 ⊆ F)
    (htop : Sat rho (mk v {c} F))
    (hre : ∀ p ∈ fam, Sat rho (mk p.1 {c} (F \ p.2))) :
    ∀ p ∈ fam, Sat rho (mk v {p.1} p.2) :=
  fun p hp => read_of_top (hCF p hp) htop (hre p hp)

/-! ## 4b. The WHOLE-SYSTEM forward direction, with genuine freshness (G-1)

`models_rewrite` above is about the family.  Part B needs `SSat G → SSat G'` for the whole
system, which is the obligation `LoopStrict.sat` discharges for every existing constructor and
which the shipped mint gets from `Cut.ResApp`'s `fresh : z ∉ allVars G`.  With the same premise
it follows from the library's own `sModels_setVar`. -/

/-- **The system-level extension.**  `G` is the whole system, `fam` the `k` reads at `v`, `F`
their union.  If `c` is fresh for ALL of `G`, every model of `G` extends — at the forced value
`rho v \ F` — to a model of `G` together with the top partition and the `k` re-expressions. -/
theorem ssat_rewrite_fwd {G : System} {v c : Var} {F : Row} {fam : List (Var × Row)}
    (hfresh : c ∉ allVars G) (hne : fam ≠ [])
    (hread : ∀ p ∈ fam, mk v {p.1} p.2 ∈ G)
    (hFv : ∀ p ∈ fam, p.2 ⊆ F)
    (hFsub : ∀ rho, SModels rho G → F ⊆ rho v)
    {rho : Assign} (hm : SModels rho G) :
    SModels (setVar rho c (rho v \ F)) G ∧
    Sat (setVar rho c (rho v \ F)) (mk v {c} F) ∧
    (∀ p ∈ fam, Sat (setVar rho c (rho v \ F)) (mk p.1 {c} (F \ p.2))) := by
  have hF : F ⊆ rho v := hFsub rho hm
  have hcv : c ≠ v := by
    rintro rfl
    rcases fam with _ | ⟨p, ps⟩
    · exact hne rfl
    · exact hfresh (lhs_mem_allVars (hread p (by simp)))
  refine ⟨sModels_setVar hfresh _ hm, top_sat hcv hF, fun p hp => ?_⟩
  have hcx : c ≠ p.1 := by
    rintro rfl
    exact hfresh (mem_allVars (hread p hp) (Or.inr (by simp)))
  exact reexpr_sat hcv hcx (hFv p hp) hF (hm _ (hread p hp))

/-- `F ⊆ rho v` is not an extra assumption: it follows from the reads themselves. -/
theorem F_subset_of_reads {G : System} {v : Var} {fam : List (Var × Row)}
    (hread : ∀ p ∈ fam, mk v {p.1} p.2 ∈ G) :
    ∀ rho, SModels rho G → fam.foldr (fun p a => p.2 ∪ a) ∅ ⊆ rho v :=
  fun _ hm => union_subset_lhs (fun p hp => hm _ (hread p hp))

/-! ## 5. Which `LoopStrict` constructor it is: TWO steps, not one

The brief asks; the answer is that the rewrite is not one step of `Loop/Strict.lean`'s relation
but two, and neither of them is `requeue` or `weaken`.

1. an ADDITIVE mint, shaped exactly like `res : ResStep G G' → LoopStrict G G'` — a new
   constructor whose application carries `fresh : c ∉ allVars G`.  Its `NoLoss` is
   `NoLoss.of_subset` (`topAdd_noLoss`), its `SSat` obligation is `ssat_rewrite_fwd`;
2. then `drop` deleting the `k` reads, with the `NoLoss` premise discharged by
   `noloss_of_top` (`topDrop`).

`requeue` cannot be used: it demands `allVars G' ⊆ allVars G`, and a genuinely fresh `c` breaks
that by construction (`topAdd_escapes`).  `weaken` is what `Loop/Strict.lean` exists to
eliminate. -/

/-- The `k + 1` constraints the mint adds. -/
def topAdds (v c : Var) (F : Row) (fam : List (Var × Row)) : System :=
  insert (mk v {c} F) ((fam.map (fun p => mk p.1 {c} (F \ p.2))).toFinset)

/-- The `k` reads the drop deletes. -/
def topReads (v : Var) (fam : List (Var × Row)) : System :=
  (fam.map (fun p => mk v {p.1} p.2)).toFinset

theorem mem_topReads {v : Var} {fam : List (Var × Row)} {d : Constraint} :
    d ∈ topReads v fam ↔ ∃ p ∈ fam, d = mk v {p.1} p.2 := by
  simp [topReads, List.mem_toFinset, eq_comm]

theorem top_mem_topAdds {v c : Var} {F : Row} {fam : List (Var × Row)} :
    mk v {c} F ∈ topAdds v c F fam := Finset.mem_insert_self _ _

theorem reexpr_mem_topAdds {v c : Var} {F : Row} {fam : List (Var × Row)} {p : Var × Row}
    (hp : p ∈ fam) : mk p.1 {c} (F \ p.2) ∈ topAdds v c F fam :=
  Finset.mem_insert_of_mem (List.mem_toFinset.mpr (List.mem_map_of_mem hp))

/-- **Step 1 is additive, so it loses nothing for free.** -/
theorem topAdd_noLoss (G : System) (v c : Var) (F : Row) (fam : List (Var × Row)) :
    Loop.NoLoss G (G ∪ topAdds v c F fam) :=
  Loop.NoLoss.of_subset Finset.subset_union_left

/-- **Step 1 escapes `G`'s vocabulary**, which is exactly why it cannot be a `requeue`. -/
theorem topAdd_escapes {G : System} {v c : Var} {F : Row} {fam : List (Var × Row)}
    (hfresh : c ∉ allVars G) : ¬ allVars (G ∪ topAdds v c F fam) ⊆ allVars G := by
  intro hsub
  exact hfresh (hsub (mem_allVars (Finset.mem_union_right _ top_mem_topAdds)
    (Or.inr (by simp [vset, mk]))))

/-- **Step 2 is a `drop`.**  Given that the added constraints survive the deletion, the system
that remains entails every read that was deleted, so `LoopStrict.drop` applies. -/
theorem topDrop {G' : System} {v c : Var} {F : Row} {fam : List (Var × Row)}
    (hCF : ∀ p ∈ fam, p.2 ⊆ F)
    (htop : mk v {c} F ∈ G' \ topReads v fam)
    (hre : ∀ p ∈ fam, mk p.1 {c} (F \ p.2) ∈ G' \ topReads v fam) :
    Loop.LoopStrict G' (G' \ topReads v fam) := by
  refine Loop.LoopStrict.drop Finset.sdiff_subset (fun d hd rho hm => ?_)
  by_cases hdr : d ∈ topReads v fam
  · obtain ⟨p, hp, rfl⟩ := mem_topReads.mp hdr
    exact read_of_top (hCF p hp) (hm _ htop) (hm _ (hre p hp))
  · exact hm d (Finset.mem_sdiff.mpr ⟨hd, hdr⟩)

end S4
end Rowpartition

#print axioms Rowpartition.S4.read_eq
#print axioms Rowpartition.S4.conc_subset_lhs
#print axioms Rowpartition.S4.rem_eq
#print axioms Rowpartition.S4.read_of_top
#print axioms Rowpartition.S4.noloss_of_top
#print axioms Rowpartition.S4.top_forced
#print axioms Rowpartition.S4.union_subset_lhs
#print axioms Rowpartition.S4.top_sat
#print axioms Rowpartition.S4.reexpr_sat
#print axioms Rowpartition.S4.models_rewrite
#print axioms Rowpartition.S4.reads_of_rewrite
#print axioms Rowpartition.S4.setVar_eq_update
#print axioms Rowpartition.S4.ssat_rewrite_fwd
#print axioms Rowpartition.S4.F_subset_of_reads
#print axioms Rowpartition.S4.mem_topReads
#print axioms Rowpartition.S4.topAdd_noLoss
#print axioms Rowpartition.S4.topAdd_escapes
#print axioms Rowpartition.S4.topDrop
