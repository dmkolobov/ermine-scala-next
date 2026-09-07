/-
# S4c: the CORRESPONDENCE LEMMA — the executable `topNormalise` IS the abstract rewrite

Stage S4c of `tracker/LOOP-MODEL-PLAN.md`; report `tracker/loopmodel/S4C-CORRESPONDENCE.md`.

S4 (`tracker/loopmodel/S4-CHANGE.md`, commit `c48f178`) added the WRITTEN-PARTITION
NORMALISATION to the row solver behind `-Dermine.topNormalise` (DEFAULT OFF), with a
trace-equal mirror in `Loop/Json.lean` (`topFamilies` / `topNormalise`) and abstract theorems
in `tracker/loopmodel/S4Top.lean`.  The S4 Part B review (`S4B-REVIEW.md` §2.2, §5.2, H-9)
made the LINK between the two a prerequisite of ever flipping the flag: every default this
programme has adopted shipped one (KeyedSplit's `d736bf9`, `K2ResStep.mint_toGRes`,
`scalaEmptyRes_run`), and this one had not.

This module IS that link, and it carries `S4Top.lean` itself (§0–§5 below, verbatim from the
scratch file, which is now a pointer) so that the abstract theorems are inside the library and
inside `Audit.lean`'s 0-non-standard-axiom count.

## What is proved about the CODE AS IT IS

* **(a)** `topFamilies_spec`: every family the selector returns meets every hypothesis the
  abstract theorems need — `fam ≠ []`, three or more DISTINCT and pairwise INCOMPARABLE parts,
  every member a READ `v <- (x, F_i)` with `x ≠ v` and `F_i` non-empty, no concrete row at `v`,
  `F = ⋃ F_i` and `F_i ⊆ F`.  The one side condition is `Wf`'s: the concrete parts are
  duplicate-free, which is what makes Scala's `Set` equality equality of the label sets.
* **(b)** `carriers_spec`: the carriers are fresh for the WHOLE input system (from the
  `Supply`'s own counter, via `RefineLearn.SupFresh`), one per family, pairwise distinct.
* **(c)** `topNormalise_sysQ`: the returned queue, read as a system, is
  `(G ∪ ⋃ topAdds) \ ⋃ topReads` over the families computed from the ORIGINAL queue.  The
  multi-family composition is `tnAdds` / `tnReads`, and the two are DISJOINT
  (`adds_notMem_reads`) — which is what freshness buys and what makes the one-pass rewrite
  independent of the fold order.
* **(d)** `topNormalise_models` / `topNormalise_noLoss` / `topNormalise_ssat_fwd` /
  `topNormalise_ssat_iff`: the executable rewrite is SATISFIABILITY-EQUIVALENT, and it loses
  nothing in `Loop/Strict.lean`'s vocabulary.  `Conserv` against the input ALONE is false for
  any mint (`S4Top.topAdd_escapes`); what holds is `topNormalise_conserv`, against the input
  together with the `k + 1` constraints the mint adds, and `topNormalise_loopStrict`, which is
  the S4c-3 answer: the deletion is a `LoopStrict.drop`, licensed by `noloss_of_top`.
* the flag-parametric bridge S4c-2 uses: `tn_models`, `tn_noLoss`, `tn_ssat_iff`, each a case
  split on the flag with `topNormalise_off` closing the OFF branch by `rfl`.

Nothing executable is restructured: `topFamilies_eq` and `topNormalise_eq` are `rfl`, so the
definitions this module reasons about are the ones `looptrace` runs.
-/
import Rowpartition.Loop.Solve


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

namespace Rowpartition.Loop
open Rowpartition

/-! ## A. `SSet` and queue helpers -/

namespace SSet
variable {α : Type} [SVal α] [LawfulSVal α]

theorem subsetOf_iff' {s t : SSet α} : s.subsetOf t = true ↔ ∀ x ∈ s.elems, x ∈ t.elems := by
  simp only [SSet.subsetOf, List.all_eq_true]
  exact ⟨fun h x hx => (SSet.contains_iff t x).mp (h x hx),
    fun h x hx => (SSet.contains_iff t x).mpr (h x hx)⟩

theorem subsetOf_refl (s : SSet α) : s.subsetOf s = true := subsetOf_iff'.mpr (fun _ h => h)

theorem eqv_refl (s : SSet α) : s.eqv s = true := by
  simp [SSet.eqv, subsetOf_refl]

/-- On duplicate-free sets `eqv` is having the same elements. -/
theorem eqv_iff_mem [DecidableEq α] {s t : SSet α} (hs : s.Nodup) (ht : t.Nodup) :
    s.eqv t = true ↔ ∀ x, x ∈ s.elems ↔ x ∈ t.elems := by
  rw [SSet.eqv_iff_toFinset hs ht]
  constructor
  · intro h x; constructor
    · intro hx; exact List.mem_toFinset.mp (h ▸ List.mem_toFinset.mpr hx)
    · intro hx; exact List.mem_toFinset.mp (h ▸ List.mem_toFinset.mpr hx)
  · intro h; ext x; simp only [List.mem_toFinset]; exact h x

end SSet

theorem eqv_refl (p : LPart) : p.eqv p = true := by
  simp [LPart.eqv, RHS.eqv, SSet.eqv_refl]

/-! ### `PQueue.ofList` keeps every non-self-unification, up to `Partition.equals` -/

theorem concatNP_repr : ∀ (xs : List LPart) (q : PQueue) {p : LPart},
    ((p ∈ xs ∧ p.isSelfUnification = false) ∨ (∃ x ∈ q.elems, x.eqv p = true)) →
    ∃ x ∈ (q.concatNP xs).elems, x.eqv p = true
  | [], q, p, h => by
    rcases h with ⟨hx, -⟩ | h
    · cases hx
    · exact h
  | y :: xs, q, p, h => by
    refine concatNP_repr xs (q.insertNP y) ?_
    rcases h with ⟨hx, hself⟩ | ⟨x, hx, hxp⟩
    · rcases List.mem_cons.mp hx with rfl | hx'
      · refine Or.inr ?_
        unfold PQueue.insertNP
        split
        · rename_i hs; exact absurd hs (by simp [hself])
        · split
          · rename_i hd
            obtain ⟨x, hx, hxx⟩ := List.any_eq_true.mp hd
            exact ⟨x, hx, (Bool.and_eq_true _ _ ▸ hxx).2⟩
          · exact ⟨p, mem_insertSorted_self p q.elems, eqv_refl p⟩
      · exact Or.inl ⟨hx', hself⟩
    · exact Or.inr ⟨x, mem_insertNP_of_mem hx, hxp⟩

/-- **Every non-self-unification survives `PQueue(ps)`, up to `Partition.equals`.**  `insertNP`
drops a self-unification and a duplicate; a duplicate leaves an `equals`-equal representative
behind. -/
theorem ofList_repr {xs : List LPart} {p : LPart} (hp : p ∈ xs)
    (hself : p.isSelfUnification = false) :
    ∃ x ∈ (PQueue.ofList xs).elems, x.eqv p = true :=
  concatNP_repr xs PQueue.empty (Or.inl ⟨hp, hself⟩)

theorem mem_ofList_elems {xs : List LPart} {x : LPart} (h : x ∈ (PQueue.ofList xs).elems) :
    x ∈ xs := by
  rcases mem_concatNP xs PQueue.empty h with h' | h'
  · cases h'
  · exact h'

/-- `PQueue(ps)` never holds a self-unification: `insertNP` refuses one. -/
theorem ofList_no_self : ∀ (xs : List LPart) (q : PQueue),
    (∀ p ∈ q.elems, p.isSelfUnification = false) →
    ∀ p ∈ (q.concatNP xs).elems, p.isSelfUnification = false
  | [], _, h => h
  | y :: xs, q, h => by
    refine ofList_no_self xs (q.insertNP y) ?_
    intro p hp
    rcases mem_insertNP hp with hp' | rfl
    · exact h p hp'
    · unfold PQueue.insertNP at hp
      split at hp
      · rename_i hs; exact absurd (h p hp) (by simp [hs])
      · rename_i hs
        simp only [Bool.not_eq_true] at hs
        exact hs

theorem ofList_selfUnif_free {xs : List LPart} {p : LPart}
    (hp : p ∈ (PQueue.ofList xs).elems) : p.isSelfUnification = false :=
  ofList_no_self xs PQueue.empty (by intro p hp; cases hp) p hp


def IsRead (p : LPart) : Bool :=
  (match p.rhs.abstrSingle? with | some x => x != p.lhs | none => false) &&
    !p.rhs.conc.isEmpty

def famOf (ps : List LPart) (v : Nat) : List LPart :=
  ps.filter (fun p => p.lhs == v && IsRead p)

def dstep (acc : List (SSet Lbl)) (c : SSet Lbl) : List (SSet Lbl) :=
  if acc.any (fun d => d.eqv c) then acc else acc ++ [c]

theorem dstep_pos {acc : List (SSet Lbl)} {c : SSet Lbl}
    (h : acc.any (fun d => d.eqv c) = true) : dstep acc c = acc := by
  simp only [dstep, h, if_pos]

theorem dstep_neg {acc : List (SSet Lbl)} {c : SSet Lbl}
    (h : ¬ (acc.any (fun d => d.eqv c) = true)) : dstep acc c = acc ++ [c] := by
  simp only [dstep]; rw [if_neg h]

def disOf (fam : List LPart) : List (SSet Lbl) :=
  (fam.map (fun p => p.rhs.conc)).foldl dstep []

def unionOf (dis : List (SSet Lbl)) : SSet Lbl := dis.foldl (fun a c => a.concat c) SSet.empty

def candOf (ps : List LPart) : List Nat :=
  (ps.filterMap (fun p => if IsRead p then some p.lhs else none)).eraseDups

theorem topFamilies_eq (q : PQueue) :
    topFamilies q = (candOf q.elems).filterMap (fun v =>
      if q.elems.any (fun p => p.lhs == v && p.rhs.abstr.isEmpty) then none
      else
        let fam := famOf q.elems v
        let dis := disOf fam
        if dis.length < 3 then none
        else if !(dis.all (fun c => dis.all (fun d => c.eqv d || !(c.subsetOf d)))) then none
        else some (v, fam, unionOf dis)) := rfl

/-! ### The de-duplicating fold -/

theorem foldl_dstep_mono : ∀ (l : List (SSet Lbl)) (acc : List (SSet Lbl)) {d : SSet Lbl},
    d ∈ acc → d ∈ l.foldl dstep acc
  | [], _, _, h => h
  | c :: l, acc, d, h => by
    refine foldl_dstep_mono l (dstep acc c) ?_
    by_cases hany : acc.any (fun d => d.eqv c) = true
    · rw [dstep_pos hany]; exact h
    · rw [dstep_neg hany]; exact List.mem_append_left _ h

theorem foldl_dstep_mem : ∀ (l : List (SSet Lbl)) (acc : List (SSet Lbl)) {d : SSet Lbl},
    d ∈ l.foldl dstep acc → d ∈ acc ∨ d ∈ l
  | [], _, _, h => Or.inl h
  | c :: l, acc, d, h => by
    rcases foldl_dstep_mem l (dstep acc c) h with h' | h'
    · by_cases hany : acc.any (fun d => d.eqv c) = true
      · rw [dstep_pos hany] at h'; exact Or.inl h'
      · rw [dstep_neg hany] at h'
        rcases List.mem_append.mp h' with h'' | h''
        · exact Or.inl h''
        · exact Or.inr (by simp [List.mem_singleton.mp h''])
    · exact Or.inr (List.mem_cons_of_mem _ h')

theorem foldl_dstep_covers : ∀ (l : List (SSet Lbl)) (acc : List (SSet Lbl)) {c : SSet Lbl},
    c ∈ l → ∃ d ∈ l.foldl dstep acc, d.eqv c = true
  | [], _, _, h => by cases h
  | c0 :: l, acc, c, h => by
    rcases List.mem_cons.mp h with rfl | h'
    · by_cases hany : acc.any (fun d => d.eqv c) = true
      · obtain ⟨d, hd, hdc⟩ := List.any_eq_true.mp hany
        exact ⟨d, foldl_dstep_mono l _ (by rw [dstep_pos hany]; exact hd), hdc⟩
      · refine ⟨c, foldl_dstep_mono l _ ?_, SSet.eqv_refl c⟩
        rw [dstep_neg hany]
        exact List.mem_append_right _ (by simp)
    · exact foldl_dstep_covers l (dstep acc c0) h'

theorem foldl_dstep_pairwise : ∀ (l : List (SSet Lbl)) (acc : List (SSet Lbl)),
    acc.Pairwise (fun c d => c.eqv d = false) →
    (l.foldl dstep acc).Pairwise (fun c d => c.eqv d = false)
  | [], _, h => h
  | c :: l, acc, h => by
    refine foldl_dstep_pairwise l (dstep acc c) ?_
    by_cases hany : acc.any (fun d => d.eqv c) = true
    · rw [dstep_pos hany]; exact h
    · rw [dstep_neg hany]
      refine List.pairwise_append.mpr ⟨h, List.pairwise_singleton _ _, ?_⟩
      intro a ha b hb
      rw [List.mem_singleton.mp hb]
      simpa using (by simpa using hany : ∀ d ∈ acc, ¬ (d.eqv c = true)) a ha

theorem disOf_sub {fam : List LPart} {c : SSet Lbl} (h : c ∈ disOf fam) :
    ∃ p ∈ fam, c = p.rhs.conc := by
  rcases foldl_dstep_mem _ [] h with h' | h'
  · cases h'
  · obtain ⟨p, hp, hpc⟩ := List.mem_map.mp h'
    exact ⟨p, hp, hpc.symm⟩

theorem disOf_covers {fam : List LPart} {p : LPart} (h : p ∈ fam) :
    ∃ d ∈ disOf fam, d.eqv p.rhs.conc = true :=
  foldl_dstep_covers _ [] (List.mem_map_of_mem h)

theorem disOf_pairwise (fam : List LPart) :
    (disOf fam).Pairwise (fun c d => c.eqv d = false) :=
  foldl_dstep_pairwise _ [] List.Pairwise.nil

/-! ### The union -/

theorem mem_foldl_concat : ∀ (l : List (SSet Lbl)) (acc : SSet Lbl) {x : Lbl},
    x ∈ (l.foldl (fun a c => a.concat c) acc).elems ↔ (x ∈ acc.elems ∨ ∃ c ∈ l, x ∈ c.elems)
  | [], _, _ => by simp
  | c :: l, acc, x => by
    rw [List.foldl_cons, mem_foldl_concat l (acc.concat c), SSet.mem_concat_iff]
    constructor
    · rintro ((h | h) | ⟨d, hd, hx⟩)
      · exact Or.inl h
      · exact Or.inr ⟨c, by simp, h⟩
      · exact Or.inr ⟨d, List.mem_cons_of_mem _ hd, hx⟩
    · rintro (h | ⟨d, hd, hx⟩)
      · exact Or.inl (Or.inl h)
      · rcases List.mem_cons.mp hd with rfl | hd'
        · exact Or.inl (Or.inr hx)
        · exact Or.inr ⟨d, hd', hx⟩

theorem mem_unionOf {dis : List (SSet Lbl)} {x : Lbl} :
    x ∈ (unionOf dis).elems ↔ ∃ c ∈ dis, x ∈ c.elems := by
  rw [unionOf, mem_foldl_concat]
  simp [SSet.empty]


/-! ### The selector's guarantee -/

theorem single?_eq_some {α : Type} [SVal α] {s : SSet α} {x : α} (h : s.single? = some x) :
    s.elems = [x] := by
  unfold SSet.single? at h
  match hh : s.elems with
  | [] => rw [hh] at h; exact absurd h (by simp)
  | [y] => rw [hh] at h; simp only [Option.some.injEq] at h; rw [h]
  | y :: z :: t => rw [hh] at h; exact absurd h (by simp)

theorem isEmpty_iff {α : Type} [SVal α] {s : SSet α} : s.isEmpty = true ↔ s.elems = [] := by
  simp [SSet.isEmpty, List.isEmpty_iff]

/-- **What `topFamilies` guarantees about one family it selects.**  Every clause of
`Constraints.topFamilies`' filter, read back as a fact about the family. -/
structure TopFam (ps : List LPart) (v : Nat) (fam : List LPart) (F : SSet Lbl) : Prop where
  /-- the family is exactly the reads at `v` -/
  eqFam : fam = famOf ps v
  /-- and `F` is the union of their distinct concrete parts -/
  eqF : F = unionOf (disOf fam)
  /-- every member is a partition of the queue... -/
  mem : ∀ p ∈ fam, p ∈ ps
  /-- ...at the left-hand side `v`... -/
  lhs : ∀ p ∈ fam, p.lhs = v
  /-- ...and is a READ `v <- (x, F_i)` with `x ≠ v`... -/
  read : ∀ p ∈ fam, ∃ x, p.rhs.abstr.elems = [x] ∧ x ≠ v
  /-- ...whose concrete part is NON-EMPTY -/
  concNe : ∀ p ∈ fam, p.rhs.conc.elems ≠ []
  /-- the family is not empty -/
  ne : fam ≠ []
  /-- `v` carries NO concrete row of its own -/
  noConc : ∀ p ∈ ps, p.lhs = v → p.rhs.abstr.elems ≠ []
  /-- there are at least three DISTINCT parts -/
  card : 3 ≤ (disOf fam).length
  /-- and they are pairwise distinct... -/
  distinct : (disOf fam).Pairwise (fun c d => c.eqv d = false)
  /-- ...and pairwise INCOMPARABLE -/
  incomp : ∀ c ∈ disOf fam, ∀ d ∈ disOf fam, c.eqv d = true ∨ c.subsetOf d = false
  /-- `F = ⋃ F_i` -/
  union : ∀ x ∈ F.elems, ∃ p ∈ fam, x ∈ p.rhs.conc.elems
  /-- `F_i ⊆ F` -/
  sub : ∀ p ∈ fam, ∀ x ∈ p.rhs.conc.elems, x ∈ F.elems

/-- **S4c-1 (a).**  Every family `topFamilies` selects meets the hypotheses of the abstract
theorems.  The one side condition is `Wf`'s: the concrete parts are duplicate-free, which is
what makes Scala's `Set` equality (`SSet.eqv`) equality of the underlying sets. -/
theorem topFamilies_spec {q : PQueue} (hnd : ∀ p ∈ q.elems, p.rhs.conc.Nodup)
    {v : Nat} {fam : List LPart} {F : SSet Lbl} (h : (v, fam, F) ∈ topFamilies q) :
    TopFam q.elems v fam F := by
  rw [topFamilies_eq, List.mem_filterMap] at h
  obtain ⟨w, -, hfw⟩ := h
  by_cases hconc : q.elems.any (fun p => p.lhs == w && p.rhs.abstr.isEmpty) = true
  · rw [if_pos hconc] at hfw; exact absurd hfw (by simp)
  rw [if_neg hconc] at hfw
  simp only at hfw
  by_cases hlen : (disOf (famOf q.elems w)).length < 3
  · rw [if_pos hlen] at hfw; exact absurd hfw (by simp)
  rw [if_neg hlen] at hfw
  by_cases hinc : (!((disOf (famOf q.elems w)).all
      (fun c => (disOf (famOf q.elems w)).all (fun d => c.eqv d || !(c.subsetOf d))))) = true
  · rw [if_pos hinc] at hfw; exact absurd hfw (by simp)
  rw [if_neg hinc] at hfw
  simp only [Option.some.injEq, Prod.mk.injEq] at hfw
  obtain ⟨rfl, rfl, rfl⟩ := hfw
  -- the filter's predicate, for a member of the family
  have hpred : ∀ p ∈ famOf q.elems w, (p.lhs == w) = true ∧ IsRead p = true := by
    intro p hp
    have := (List.mem_filter.mp hp).2
    exact Bool.and_eq_true _ _ ▸ this
  have hlhs : ∀ p ∈ famOf q.elems w, p.lhs = w :=
    fun p hp => by simpa using (hpred p hp).1
  have hmem : ∀ p ∈ famOf q.elems w, p ∈ q.elems :=
    fun p hp => List.mem_of_mem_filter hp
  have hread : ∀ p ∈ famOf q.elems w, ∃ x, p.rhs.abstr.elems = [x] ∧ x ≠ w := by
    intro p hp
    have hIR := (hpred p hp).2
    rw [IsRead, Bool.and_eq_true] at hIR
    cases hs : p.rhs.abstrSingle? with
    | none => rw [hs] at hIR; exact absurd hIR.1 (by simp)
    | some x =>
      rw [hs] at hIR
      refine ⟨x, single?_eq_some hs, ?_⟩
      have : x ≠ p.lhs := by simpa using hIR.1
      rw [← hlhs p hp]; exact this
  have hconcNe : ∀ p ∈ famOf q.elems w, p.rhs.conc.elems ≠ [] := by
    intro p hp
    have hIR := (hpred p hp).2
    rw [IsRead, Bool.and_eq_true] at hIR
    have := hIR.2
    simp only [Bool.not_eq_true'] at this
    intro hc
    rw [isEmpty_iff.mpr hc] at this
    exact absurd this (by simp)
  have hcard : 3 ≤ (disOf (famOf q.elems w)).length := by omega
  have hne : famOf q.elems w ≠ [] := by
    intro hc
    rw [hc] at hcard
    simp [disOf] at hcard
  have hall : (disOf (famOf q.elems w)).all
      (fun c => (disOf (famOf q.elems w)).all (fun d => c.eqv d || !(c.subsetOf d))) = true := by
    cases hX : (disOf (famOf q.elems w)).all
        (fun c => (disOf (famOf q.elems w)).all (fun d => c.eqv d || !(c.subsetOf d))) with
    | false => exact absurd (by rw [hX]; rfl) hinc
    | true => rfl
  have hdisNd : ∀ c ∈ disOf (famOf q.elems w), c.Nodup := by
    intro c hc
    obtain ⟨p, hp, rfl⟩ := disOf_sub hc
    exact hnd p (hmem p hp)
  refine
    { eqFam := rfl, eqF := rfl, mem := hmem, lhs := hlhs, read := hread, concNe := hconcNe,
      ne := hne, card := hcard, distinct := disOf_pairwise _,
      noConc := ?_, incomp := ?_, union := ?_, sub := ?_ }
  · intro p hp hemp hnil
    have hno : ¬ ((p.lhs == w) = true ∧ (p.rhs.abstr.isEmpty = true)) := by
      intro hcon
      exact hconc (List.any_eq_true.mpr ⟨p, hp, by simp [hcon.1, hcon.2]⟩)
    exact hno ⟨by simp [hemp], isEmpty_iff.mpr hnil⟩
  · intro c hc d hd
    have h1 := List.all_eq_true.mp hall c hc
    have h2 := List.all_eq_true.mp h1 d hd
    rcases Bool.or_eq_true _ _ |>.mp h2 with h3 | h3
    · exact Or.inl h3
    · exact Or.inr (by simpa using h3)
  · intro x hx
    obtain ⟨c, hc, hxc⟩ := mem_unionOf.mp hx
    obtain ⟨p, hp, rfl⟩ := disOf_sub hc
    exact ⟨p, hp, hxc⟩
  · intro p hp x hx
    obtain ⟨d, hd, hdp⟩ := disOf_covers hp
    have hx' : x ∈ d.elems :=
      ((SSet.eqv_iff_mem (hdisNd d hd) (hnd p (hmem p hp))).mp hdp x).mpr hx
    exact mem_unionOf.mpr ⟨d, hd, hx'⟩


abbrev Plan := Nat × List LPart × SSet Lbl

def resBlock (fam : List LPart) (c : Nat) (F : SSet Lbl) : List LPart :=
  fam.filterMap (fun p =>
    match p.rhs.abstrSingle? with
    | some x => some (⟨x, ⟨SSet.ofList [c], F.removedAll p.rhs.conc⟩,
                       some .topNormalise⟩ : LPart)
    | none => none)

def topBlock (t : Plan) (c : Nat) : List LPart :=
  (⟨t.1, ⟨SSet.ofList [c], t.2.2⟩, some .topNormalise⟩ : LPart) :: resBlock t.2.1 c t.2.2

def tnStep (acc : List LPart × Sup × List (Nat × Nat × SSet Lbl)) (t : Plan) :
    List LPart × Sup × List (Nat × Nat × SSet Lbl) :=
  let (added, su, rc) := acc
  let (c, su) := su.fresh
  let top : LPart := ⟨t.1, ⟨SSet.ofList [c], t.2.2⟩, some .topNormalise⟩
  let res := t.2.1.filterMap (fun p =>
    match p.rhs.abstrSingle? with
    | some x => some (⟨x, ⟨SSet.ofList [c], t.2.2.removedAll p.rhs.conc⟩,
                       some .topNormalise⟩ : LPart)
    | none => none)
  (added ++ (top :: res), su, rc ++ [(t.1, c, t.2.2)])

def keepOf (q : PQueue) : List LPart :=
  let dead := (topFamilies q).flatMap (fun t => t.2.1)
  q.elems.filter (fun p => !(dead.any (fun d => d.eqv p)))

theorem topNormalise_eq (on : Bool) (q : PQueue) (su : Sup) :
    topNormalise on q su =
      (if !on then (q, su, []) else
        if (topFamilies q).isEmpty then (q, su, []) else
          let r := (topFamilies q).foldl tnStep ([], su, [])
          (PQueue.ofList (keepOf q ++ r.1), r.2.1, r.2.2)) := rfl

/-- The added partitions, and the supply left, as a recursion on the plan list. -/
def addedOf : List Plan → Sup → List LPart × Sup
  | [], su => ([], su)
  | t :: ts, su =>
    let r := addedOf ts (su.fresh).2
    (topBlock t (su.fresh).1 ++ r.1, r.2)

/-- The `tnorm` trace records. -/
def recsOf : List Plan → Sup → List (Nat × Nat × SSet Lbl)
  | [], _ => []
  | t :: ts, su => (t.1, (su.fresh).1, t.2.2) :: recsOf ts (su.fresh).2

/-- The carriers, one per plan, in order. -/
def tnCarriers : List Plan → Sup → List Nat
  | [], _ => []
  | _ :: ts, su => (su.fresh).1 :: tnCarriers ts (su.fresh).2

theorem foldl_tnStep : ∀ (plans : List Plan) (a : List LPart) (su : Sup)
    (rc : List (Nat × Nat × SSet Lbl)),
    plans.foldl tnStep (a, su, rc) =
      (a ++ (addedOf plans su).1, (addedOf plans su).2, rc ++ recsOf plans su)
  | [], a, su, rc => by simp [addedOf, recsOf]
  | t :: ts, a, su, rc => by
    rw [List.foldl_cons]
    show (ts.foldl tnStep (a ++ topBlock t (su.fresh).1, (su.fresh).2,
            rc ++ [(t.1, (su.fresh).1, t.2.2)])) = _
    rw [foldl_tnStep ts]
    simp [addedOf, recsOf, List.append_assoc]

theorem carriers_reach : ∀ (plans : List Plan) (su : Sup), SupOk su →
    ∀ c ∈ tnCarriers plans su, Sup.Reach su c
  | [], _, _, _, h => by cases h
  | t :: ts, su, hok, c, h => by
    rcases List.mem_cons.mp h with rfl | h'
    · exact fresh_reach hok
    · exact (fresh_reach_mono hok c
        (carriers_reach ts (su.fresh).2 (fresh_supOk hok) c h')).1

theorem carriers_nodup : ∀ (plans : List Plan) (su : Sup), SupOk su →
    (tnCarriers plans su).Nodup
  | [], _, _ => by simp [tnCarriers]
  | t :: ts, su, hok => by
    rw [tnCarriers, List.nodup_cons]
    refine ⟨fun hc => ?_, carriers_nodup ts (su.fresh).2 (fresh_supOk hok)⟩
    exact (fresh_reach_mono hok _
      (carriers_reach ts (su.fresh).2 (fresh_supOk hok) _ hc)).2 rfl

theorem carriers_notMem : ∀ (plans : List Plan) (su : Sup) (G : System), SupOk su →
    SupFresh su G → ∀ c ∈ tnCarriers plans su, c ∉ allVars G
  | [], _, _, _, _, _, h => by cases h
  | t :: ts, su, G, hok, hfr, c, h => by
    rcases List.mem_cons.mp h with rfl | h'
    · exact fresh_notMem hok hfr
    · exact carriers_notMem ts (su.fresh).2 G (fresh_supOk hok)
        (SupFresh.step hok hfr (fun w hw => Or.inl hw)) c h'



/-! ### The block, read as constraints -/

theorem single?_of_elems {α : Type} [SVal α] {s : SSet α} {x : α} (h : s.elems = [x]) :
    s.single? = some x := by unfold SSet.single?; rw [h]

theorem fs_ofList_single (c : Nat) : (SSet.ofList [c] : SSet Nat).fs = {c} := by
  simp [SSet.fs, SSet.ofList, SSet.incl, SSet.empty, SSet.contains]

theorem toConstraint_read {p : LPart} {x v : Nat} (hx : p.rhs.abstr.elems = [x])
    (hv : p.lhs = v) : p.toConstraint = mk v {x} (cfs p.rhs.conc) := by
  rw [toConstraint_eq, hv]
  congr 1
  simp [SSet.fs, hx]

/-- The abstract family `S4Top` speaks of: each read's REMAINDER and its concrete part. -/
def famRows (fam : List LPart) : List (Var × Row) :=
  fam.map (fun p => ((p.rhs.abstrSingle?).getD 0, cfs p.rhs.conc))

theorem map_toConstraint_fam {v : Nat} : ∀ (fam : List LPart),
    (∀ p ∈ fam, ∃ x, p.rhs.abstr.elems = [x]) → (∀ p ∈ fam, p.lhs = v) →
    fam.map LPart.toConstraint = (famRows fam).map (fun pr => mk v {pr.1} pr.2)
  | [], _, _ => rfl
  | p :: fam, hx, hv => by
    obtain ⟨x, hex⟩ := hx p (by simp)
    have h1 : ((p.rhs.abstrSingle?).getD 0) = x := by
      simp [RHS.abstrSingle?, single?_of_elems hex]
    simp only [List.map_cons, famRows, h1, List.cons.injEq]
    refine ⟨toConstraint_read hex (hv p (by simp)), ?_⟩
    exact map_toConstraint_fam fam (fun q hq => hx q (by simp [hq]))
      (fun q hq => hv q (by simp [hq]))

theorem map_toConstraint_resBlock {L : List Lbl} (hcoh : LblCoh L) {c : Nat} {F : SSet Lbl}
    (hFL : ∀ x ∈ F.elems, x ∈ L) : ∀ (fam : List LPart),
    (∀ p ∈ fam, ∃ x, p.rhs.abstr.elems = [x]) →
    (∀ p ∈ fam, ∀ x ∈ p.rhs.conc.elems, x ∈ L) →
    (resBlock fam c F).map LPart.toConstraint =
      (famRows fam).map (fun pr => mk pr.1 {c} (cfs F \ pr.2))
  | [], _, _ => rfl
  | p :: fam, hx, hL => by
    obtain ⟨x, hex⟩ := hx p (by simp)
    have hs : p.rhs.abstrSingle? = some x := single?_of_elems hex
    have h1 : ((p.rhs.abstrSingle?).getD 0) = x := by simp [hs]
    have hstep : resBlock (p :: fam) c F =
        (⟨x, ⟨SSet.ofList [c], F.removedAll p.rhs.conc⟩, some .topNormalise⟩ : LPart) ::
          resBlock fam c F := by
      simp only [resBlock, List.filterMap_cons, hs]
    rw [hstep]
    simp only [List.map_cons, famRows, h1, List.cons.injEq]
    refine ⟨?_, map_toConstraint_resBlock hcoh hFL fam (fun q hq => hx q (by simp [hq]))
      (fun q hq => hL q (by simp [hq]))⟩
    rw [toConstraint_eq]
    simp only [fs_ofList_single]
    rw [cfs_removedAll hcoh hFL (hL p (by simp))]

/-- **The added block, read as a system, IS `S4Top`'s `topAdds`.** -/
theorem toFinset_topBlock {L : List Lbl} (hcoh : LblCoh L) {t : Plan} {c : Nat}
    (hx : ∀ p ∈ t.2.1, ∃ x, p.rhs.abstr.elems = [x])
    (hFL : ∀ x ∈ t.2.2.elems, x ∈ L)
    (hL : ∀ p ∈ t.2.1, ∀ x ∈ p.rhs.conc.elems, x ∈ L) :
    ((topBlock t c).map LPart.toConstraint).toFinset =
      S4.topAdds t.1 c (cfs t.2.2) (famRows t.2.1) := by
  simp only [topBlock, List.map_cons, List.toFinset_cons, S4.topAdds,
    map_toConstraint_resBlock hcoh hFL t.2.1 hx hL, toConstraint_eq, fs_ofList_single]

/-- **The deleted reads, read as a system, ARE `S4Top`'s `topReads`.** -/
theorem toFinset_reads {t : Plan}
    (hx : ∀ p ∈ t.2.1, ∃ x, p.rhs.abstr.elems = [x]) (hv : ∀ p ∈ t.2.1, p.lhs = t.1) :
    (t.2.1.map LPart.toConstraint).toFinset = S4.topReads t.1 (famRows t.2.1) := by
  rw [map_toConstraint_fam t.2.1 hx hv]; rfl


/-! ### The queue as a system -/

/-- The system a QUEUE denotes -- `sys` at an initial state, and the object S2's chain
speaks of. -/
def sysQ (q : PQueue) : System := (q.elems.map LPart.toConstraint).toFinset

@[simp] theorem mem_sysQ {q : PQueue} {d : Constraint} :
    d ∈ sysQ q ↔ ∃ p ∈ q.elems, p.toConstraint = d := by
  simp [sysQ, List.mem_toFinset, List.mem_map]

/-- **`PQueue(ps)` denotes exactly the constraints of `ps`.**  The two things the constructor
drops -- a self-unification and a duplicate -- are excluded by hypothesis and invisible to
`toConstraint` respectively. -/
theorem sysQ_ofList {L : List Lbl} (hcoh : LblCoh L) {xs : List LPart}
    (hok : ∀ p ∈ xs, POk L p) (hself : ∀ p ∈ xs, p.isSelfUnification = false) :
    sysQ (PQueue.ofList xs) = (xs.map LPart.toConstraint).toFinset := by
  ext d
  simp only [mem_sysQ, List.mem_toFinset, List.mem_map]
  constructor
  · rintro ⟨x, hx, rfl⟩; exact ⟨x, mem_ofList_elems hx, rfl⟩
  · rintro ⟨p, hp, rfl⟩
    obtain ⟨x, hx, hxp⟩ := ofList_repr hp (hself p hp)
    have hxm := mem_ofList_elems hx
    refine ⟨x, hx, ?_⟩
    refine (LPart.eqv_iff_toConstraint (hok x hxm).abstr (hok p hp).abstr
      (hok x hxm).conc.nodup (hok p hp).conc.nodup ?_).mp hxp
    refine hcoh.mono (fun y hy => ?_)
    rcases List.mem_append.mp hy with hy' | hy'
    · exact (hok x hxm).conc.sub y hy'
    · exact (hok p hp).conc.sub y hy'

/-! ### The added block is well formed -/

theorem cok_unionOf {L : List Lbl} : ∀ (dis : List (SSet Lbl)), (∀ c ∈ dis, COk L c) →
    ∀ (acc : SSet Lbl), COk L acc → COk L (dis.foldl (fun a c => a.concat c) acc)
  | [], _, _, hacc => hacc
  | c :: dis, h, acc, hacc =>
    cok_unionOf dis (fun d hd => h d (by simp [hd])) (acc.concat c)
      (hacc.concat (h c (by simp)))

theorem cok_F {L : List Lbl} {ps : List LPart} {v : Nat} {fam : List LPart} {F : SSet Lbl}
    (h : TopFam ps v fam F) (hqok : ∀ p ∈ ps, POk L p) : COk L F := by
  rw [h.eqF]
  exact cok_unionOf _ (fun c hc => by
    obtain ⟨p, hp, rfl⟩ := disOf_sub hc
    exact (hqok p (h.mem p hp)).conc) SSet.empty COk.empty

/-- Every partition the rewrite ADDS is well formed at the same pool. -/
theorem pok_topBlock {L : List Lbl} {ps : List LPart} {t : Plan} {c : Nat}
    (h : TopFam ps t.1 t.2.1 t.2.2) (hqok : ∀ p ∈ ps, POk L p) :
    ∀ d ∈ topBlock t c, POk L d := by
  have hF : COk L t.2.2 := cok_F h hqok
  intro d hd
  rcases List.mem_cons.mp hd with rfl | hd'
  · exact ⟨SSet.nodup_ofList _, hF⟩
  · simp only [resBlock, List.mem_filterMap] at hd'
    obtain ⟨p, hp, hpd⟩ := hd'
    cases hs : p.rhs.abstrSingle? with
    | none => rw [hs] at hpd; exact absurd hpd (by simp)
    | some x =>
      rw [hs] at hpd
      simp only [Option.some.injEq] at hpd
      subst hpd
      exact ⟨SSet.nodup_ofList _, hF.removedAll _⟩

/-- ...and is NOT a self-unification: its right-hand side carries the FRESH carrier, and a
self-unification's carries the left-hand side, which is a variable of the system. -/
theorem topBlock_not_self {t : Plan} {c : Nat} (hc : c ≠ t.1)
    (hcx : ∀ p ∈ t.2.1, ∀ x, p.rhs.abstr.elems = [x] → c ≠ x) :
    ∀ d ∈ topBlock t c, d.isSelfUnification = false := by
  intro d hd
  have hne : ∀ (u : Nat) (r : SSet Lbl) (i : Option Inference),
      u ≠ c → (⟨u, ⟨SSet.ofList [c], r⟩, i⟩ : LPart).isSelfUnification = false := by
    intro u r i hu
    unfold LPart.isSelfUnification RHS.single?
    by_cases hr : r.isEmpty = true
    · simp only [hr, if_pos]
      show (SSet.single? (SSet.ofList [c])).elim false (fun y => y == u) = false
      simp [SSet.ofList, SSet.incl, SSet.empty, SSet.contains, SSet.single?, Ne.symm hu]
    · simp [hr]
  rcases List.mem_cons.mp hd with rfl | hd'
  · exact hne t.1 t.2.2 _ (Ne.symm hc)
  · simp only [resBlock, List.mem_filterMap] at hd'
    obtain ⟨p, hp, hpd⟩ := hd'
    cases hs : p.rhs.abstrSingle? with
    | none => rw [hs] at hpd; exact absurd hpd (by simp)
    | some x =>
      rw [hs] at hpd
      simp only [Option.some.injEq] at hpd
      subst hpd
      exact hne x _ _ (Ne.symm (hcx p hp x (single?_eq_some hs)))


/-! ### The multi-family aggregate -/

/-- `⋃ topAdds` over the families, with the carriers the supply draws, in order. -/
def tnAdds : List Plan → Sup → System
  | [], _ => ∅
  | t :: ts, su =>
    S4.topAdds t.1 (su.fresh).1 (cfs t.2.2) (famRows t.2.1) ∪ tnAdds ts (su.fresh).2

/-- `⋃ topReads` over the families. -/
def tnReads : List Plan → System
  | [] => ∅
  | t :: ts => S4.topReads t.1 (famRows t.2.1) ∪ tnReads ts

/-- The reads the rewrite deletes. -/
def deadOf (plans : List Plan) : List LPart := plans.flatMap (fun t => t.2.1)

theorem keepOf_eq (q : PQueue) :
    keepOf q =
      q.elems.filter (fun p => !((deadOf (topFamilies q)).any (fun d => d.eqv p))) := rfl

namespace TopFam

variable {L : List Lbl} {ps : List LPart} {v : Nat} {fam : List LPart} {F : SSet Lbl}

theorem absSingle (h : TopFam ps v fam F) : ∀ p ∈ fam, ∃ x, p.rhs.abstr.elems = [x] :=
  fun p hp => by obtain ⟨x, hx, -⟩ := h.read p hp; exact ⟨x, hx⟩

theorem labF (h : TopFam ps v fam F) (hqok : ∀ p ∈ ps, POk L p) : ∀ x ∈ F.elems, x ∈ L :=
  fun x hx => by
    obtain ⟨p, hp, hxp⟩ := h.union x hx
    exact (hqok p (h.mem p hp)).conc.sub x hxp

theorem labC (h : TopFam ps v fam F) (hqok : ∀ p ∈ ps, POk L p) :
    ∀ p ∈ fam, ∀ x ∈ p.rhs.conc.elems, x ∈ L :=
  fun p hp x hx => (hqok p (h.mem p hp)).conc.sub x hx

end TopFam

theorem tnAdds_eq {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart}
    (hqok : ∀ p ∈ ps, POk L p) : ∀ (plans : List Plan) (su : Sup),
    (∀ t ∈ plans, TopFam ps t.1 t.2.1 t.2.2) →
    (((addedOf plans su).1).map LPart.toConstraint).toFinset = tnAdds plans su
  | [], su, _ => by simp [addedOf, tnAdds]
  | t :: ts, su, h => by
    have ht := h t (by simp)
    show (((topBlock t (su.fresh).1 ++ (addedOf ts (su.fresh).2).1)).map
      LPart.toConstraint).toFinset = _
    rw [List.map_append, List.toFinset_append,
      toFinset_topBlock hcoh ht.absSingle (ht.labF hqok) (ht.labC hqok),
      tnAdds_eq hcoh hqok ts (su.fresh).2 (fun s hs => h s (by simp [hs]))]
    rfl

theorem tnReads_eq : ∀ (plans : List Plan),
    (∀ t ∈ plans, (∀ p ∈ t.2.1, ∃ x, p.rhs.abstr.elems = [x]) ∧ (∀ p ∈ t.2.1, p.lhs = t.1)) →
    ((deadOf plans).map LPart.toConstraint).toFinset = tnReads plans
  | [], _ => by simp [deadOf, tnReads]
  | t :: ts, h => by
    have ht := h t (by simp)
    show (((t.2.1 ++ deadOf ts)).map LPart.toConstraint).toFinset = _
    rw [List.map_append, List.toFinset_append, toFinset_reads ht.1 ht.2,
      tnReads_eq ts (fun s hs => h s (by simp [hs]))]
    rfl

theorem mem_deadOf {plans : List Plan} {p : LPart} (h : p ∈ deadOf plans) :
    ∃ t ∈ plans, p ∈ t.2.1 := by
  simpa [deadOf] using List.mem_flatMap.mp h

/-- **Every constraint the rewrite ADDS mentions a carrier.** -/
theorem mem_tnAdds_carrier : ∀ (plans : List Plan) (su : Sup) {d : Constraint},
    d ∈ tnAdds plans su → ∃ c ∈ tnCarriers plans su, c ∈ vset d
  | [], _, _, h => by simp [tnAdds] at h
  | t :: ts, su, d, h => by
    rcases Finset.mem_union.mp h with h' | h'
    · refine ⟨(su.fresh).1, by simp [tnCarriers], ?_⟩
      rcases Finset.mem_insert.mp h' with rfl | h''
      · simp
      · obtain ⟨pr, -, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp h'')
        simp
    · obtain ⟨c, hc, hcd⟩ := mem_tnAdds_carrier ts (su.fresh).2 h'
      exact ⟨c, by simp [tnCarriers, hc], hcd⟩


/-! ### The standing hypotheses, and the vocabulary facts they give -/

/-- The side conditions of the correspondence.  `coh`/`qok` are `Wf`'s own (`Wf.coh`,
`Wf.incm`), `self` is what `PQueue.build` gives for free (`buildQueue_no_self`), and
`sup`/`fresh` are `RefineLearn`'s supply invariant, the one `Cut.ResApp.fresh` needs. -/
structure TnOk (L : List Lbl) (q : PQueue) (su : Sup) : Prop where
  coh : LblCoh L
  qok : QOk L q
  self : ∀ p ∈ q.elems, p.isSelfUnification = false
  sup : SupOk su
  fresh : SupFresh su (sysQ q)

theorem eqv_iff_toC {L : List Lbl} (hcoh : LblCoh L) {x p : LPart}
    (hx : POk L x) (hp : POk L p) : x.eqv p = true ↔ x.toConstraint = p.toConstraint := by
  refine LPart.eqv_iff_toConstraint hx.abstr hp.abstr hx.conc.nodup hp.conc.nodup ?_
  refine hcoh.mono (fun y hy => ?_)
  rcases List.mem_append.mp hy with hy' | hy'
  · exact hx.conc.sub y hy'
  · exact hp.conc.sub y hy'

theorem lhs_mem_allVars_q {q : PQueue} {p : LPart} (hp : p ∈ q.elems) :
    p.lhs ∈ allVars (sysQ q) := by
  have := lhs_mem_allVars (G := sysQ q) (c := p.toConstraint) (mem_sysQ.mpr ⟨p, hp, rfl⟩)
  simpa using this

theorem abstr_mem_allVars_q {q : PQueue} {p : LPart} {x : Nat} (hp : p ∈ q.elems)
    (hx : x ∈ p.rhs.abstr.elems) : x ∈ allVars (sysQ q) := by
  refine mem_allVars (G := sysQ q) (c := p.toConstraint) (mem_sysQ.mpr ⟨p, hp, rfl⟩) (Or.inr ?_)
  simpa using hx

theorem plans_topFam {L : List Lbl} {q : PQueue} (hqok : QOk L q) :
    ∀ t ∈ topFamilies q, TopFam q.elems t.1 t.2.1 t.2.2 :=
  fun _ ht => topFamilies_spec (fun p hp => (hqok p hp).conc.nodup) ht

theorem deadOf_sub {L : List Lbl} {q : PQueue} (hqok : QOk L q) :
    ∀ p ∈ deadOf (topFamilies q), p ∈ q.elems := by
  intro p hp
  obtain ⟨t, ht, hpt⟩ := mem_deadOf hp
  exact (plans_topFam hqok t ht).mem p hpt

/-! ### The added partitions are well formed and mint-shaped -/

theorem pok_addedOf {L : List Lbl} {ps : List LPart} (hqok : ∀ p ∈ ps, POk L p) :
    ∀ (plans : List Plan) (su : Sup), (∀ t ∈ plans, TopFam ps t.1 t.2.1 t.2.2) →
      ∀ d ∈ (addedOf plans su).1, POk L d
  | [], _, _, d, hd => by simp [addedOf] at hd
  | t :: ts, su, h, d, hd => by
    rcases List.mem_append.mp hd with hd' | hd'
    · exact pok_topBlock (h t (by simp)) hqok d hd'
    · exact pok_addedOf hqok ts (su.fresh).2 (fun s hs => h s (by simp [hs])) d hd'

theorem addedOf_not_self {q : PQueue} : ∀ (plans : List Plan) (su : Sup),
    (∀ t ∈ plans, TopFam q.elems t.1 t.2.1 t.2.2) → SupOk su → SupFresh su (sysQ q) →
      ∀ d ∈ (addedOf plans su).1, d.isSelfUnification = false
  | [], _, _, _, _, d, hd => by simp [addedOf] at hd
  | t :: ts, su, h, hok, hfr, d, hd => by
    have ht := h t (by simp)
    have hfresh : (su.fresh).1 ∉ allVars (sysQ q) := fresh_notMem hok hfr
    rcases List.mem_append.mp hd with hd' | hd'
    · refine topBlock_not_self ?_ ?_ d hd'
      · intro hc
        obtain ⟨p, hp⟩ := List.exists_mem_of_ne_nil _ ht.ne
        exact hfresh (hc ▸ (ht.lhs p hp) ▸ lhs_mem_allVars_q (ht.mem p hp))
      · intro p hp x hx hc
        exact hfresh (hc ▸ abstr_mem_allVars_q (ht.mem p hp) (by rw [hx]; simp))
    · exact addedOf_not_self ts (su.fresh).2 (fun s hs => h s (by simp [hs])) (fresh_supOk hok)
        (SupFresh.step hok hfr (fun w hw => Or.inl hw)) d hd'

/-! ### The rewrite ADDS nothing it also deletes -/

theorem adds_notMem_reads {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su)
    {d : Constraint} (hd : d ∈ tnAdds (topFamilies q) su) : d ∉ tnReads (topFamilies q) := by
  intro hr
  obtain ⟨c, hc, hcd⟩ := mem_tnAdds_carrier _ _ hd
  rw [← tnReads_eq (topFamilies q) (fun t ht =>
    ⟨(plans_topFam H.qok t ht).absSingle, (plans_topFam H.qok t ht).lhs⟩)] at hr
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hr)
  refine carriers_notMem _ _ _ H.sup H.fresh c hc ?_
  exact mem_allVars (mem_sysQ.mpr ⟨p, deadOf_sub H.qok p hp, rfl⟩) (Or.inr hcd)


/-! ### S4c-1 (c): the returned queue, read as a system -/

theorem sysQ_keepOf {L : List Lbl} {q : PQueue} (hcoh : LblCoh L) (hqok : QOk L q) :
    ((keepOf q).map LPart.toConstraint).toFinset = sysQ q \ tnReads (topFamilies q) := by
  have hreads := tnReads_eq (topFamilies q) (fun t ht =>
    ⟨(plans_topFam hqok t ht).absSingle, (plans_topFam hqok t ht).lhs⟩)
  ext d
  rw [← hreads]
  simp only [List.mem_toFinset, List.mem_map, Finset.mem_sdiff, mem_sysQ]
  constructor
  · rintro ⟨p, hp, rfl⟩
    rw [keepOf_eq, List.mem_filter] at hp
    have hp2 : (deadOf (topFamilies q)).any (fun d => d.eqv p) = false := by
      have := hp.2; simpa using this
    refine ⟨⟨p, hp.1, rfl⟩, ?_⟩
    rintro hc
    obtain ⟨d0, hd0, hd0e⟩ := hc
    have hEq : d0.eqv p = true :=
      (eqv_iff_toC hcoh (hqok d0 (deadOf_sub hqok d0 hd0)) (hqok p hp.1)).mpr hd0e
    rw [List.any_eq_true.mpr ⟨d0, hd0, hEq⟩] at hp2
    exact absurd hp2 (by simp)
  · rintro ⟨⟨p, hp, rfl⟩, hnr⟩
    refine ⟨p, ?_, rfl⟩
    rw [keepOf_eq, List.mem_filter]
    refine ⟨hp, ?_⟩
    cases hany : (deadOf (topFamilies q)).any (fun d => d.eqv p) with
    | false => simp
    | true =>
      exfalso
      obtain ⟨d0, hd0, hd0e⟩ := List.any_eq_true.mp hany
      exact hnr ⟨d0, hd0,
        (eqv_iff_toC hcoh (hqok d0 (deadOf_sub hqok d0 hd0)) (hqok p hp)).mp hd0e⟩

/-- **S4c-1 (c).  The queue the rewrite returns, read as a system, is
`(G ∪ ⋃ topAdds) \ ⋃ topReads`** over the families computed from the ORIGINAL queue -- one
pass, no family seeing another's rewrite. -/
theorem topNormalise_sysQ {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su) :
    sysQ (topNormalise true q su).1 =
      (sysQ q ∪ tnAdds (topFamilies q) su) \ tnReads (topFamilies q) := by
  have hplans := plans_topFam H.qok
  by_cases hemp : (topFamilies q).isEmpty = true
  · have hnil : topFamilies q = [] := List.isEmpty_iff.mp hemp
    rw [topNormalise_eq]
    simp only [Bool.not_true, Bool.false_eq_true, if_false, hnil, tnAdds, tnReads]
    simp
  · have hpok : ∀ p ∈ keepOf q ++ (addedOf (topFamilies q) su).1, POk L p := by
      intro p hp
      rcases List.mem_append.mp hp with hp' | hp'
      · rw [keepOf_eq] at hp'; exact H.qok p (List.mem_of_mem_filter hp')
      · exact pok_addedOf H.qok _ _ hplans p hp'
    have hself : ∀ p ∈ keepOf q ++ (addedOf (topFamilies q) su).1,
        p.isSelfUnification = false := by
      intro p hp
      rcases List.mem_append.mp hp with hp' | hp'
      · rw [keepOf_eq] at hp'; exact H.self p (List.mem_of_mem_filter hp')
      · exact addedOf_not_self _ _ hplans H.sup H.fresh p hp'
    rw [topNormalise_eq]
    simp only [Bool.not_true, Bool.false_eq_true, if_false, hemp, if_false, foldl_tnStep,
      List.nil_append]
    rw [sysQ_ofList H.coh hpok hself, List.map_append, List.toFinset_append,
      sysQ_keepOf H.coh H.qok, tnAdds_eq H.coh H.qok _ _ hplans]
    ext d
    simp only [Finset.mem_union, Finset.mem_sdiff]
    constructor
    · rintro (⟨h1, h2⟩ | h1)
      · exact ⟨Or.inl h1, h2⟩
      · exact ⟨Or.inr h1, adds_notMem_reads H h1⟩
    · rintro ⟨h1 | h1, h2⟩
      · exact Or.inl ⟨h1, h2⟩
      · exact Or.inr h1


/-! ### S4c-1 (d): the rewrite is satisfiability-equivalent -/

namespace TopFam

variable {L : List Lbl} {ps : List LPart} {v : Nat} {fam : List LPart} {F : SSet Lbl}

theorem subCfs (h : TopFam ps v fam F) : ∀ pr ∈ famRows fam, pr.2 ⊆ cfs F := by
  intro pr hpr
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hpr
  intro n hn
  simp only [mem_cfs] at hn ⊢
  obtain ⟨x, hx, rfl⟩ := hn
  exact ⟨x, h.sub p hp x hx, rfl⟩

theorem famRows_ne (h : TopFam ps v fam F) : famRows fam ≠ [] := by
  intro hc
  exact h.ne (List.eq_nil_of_map_eq_nil hc)

theorem cfs_union (h : TopFam ps v fam F) :
    ∀ n ∈ cfs F, ∃ pr ∈ famRows fam, n ∈ pr.2 := by
  intro n hn
  simp only [mem_cfs] at hn
  obtain ⟨x, hx, rfl⟩ := hn
  obtain ⟨p, hp, hxp⟩ := h.union x hx
  exact ⟨_, List.mem_map_of_mem hp, by simp only [mem_cfs]; exact ⟨x, hxp, rfl⟩⟩

theorem read_mem {q : PQueue} (h : TopFam q.elems v fam F) :
    ∀ pr ∈ famRows fam, Rowpartition.mk v {pr.1} pr.2 ∈ sysQ q := by
  intro pr hpr
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hpr
  refine mem_sysQ.mpr ⟨p, h.mem p hp, ?_⟩
  obtain ⟨x, hx, -⟩ := h.read p hp
  rw [toConstraint_read hx (h.lhs p hp)]
  simp [RHS.abstrSingle?, single?_of_elems hx]

end TopFam

theorem mem_tnReads : ∀ (plans : List Plan) {d : Constraint}, d ∈ tnReads plans →
    ∃ t ∈ plans, ∃ pr ∈ famRows t.2.1, d = mk t.1 {pr.1} pr.2
  | [], _, h => by simp [tnReads] at h
  | t :: ts, d, h => by
    rcases Finset.mem_union.mp h with h' | h'
    · obtain ⟨pr, hpr, hd⟩ := S4.mem_topReads.mp h'
      exact ⟨t, by simp, pr, hpr, hd⟩
    · obtain ⟨s, hs, pr, hpr, hd⟩ := mem_tnReads ts h'
      exact ⟨s, by simp [hs], pr, hpr, hd⟩

theorem tnAdds_plan : ∀ (plans : List Plan) (su : Sup) {t : Plan}, t ∈ plans →
    ∃ c, S4.topAdds t.1 c (cfs t.2.2) (famRows t.2.1) ⊆ tnAdds plans su
  | [], _, _, h => by cases h
  | s :: ts, su, t, h => by
    rcases List.mem_cons.mp h with rfl | h'
    · exact ⟨(su.fresh).1, Finset.subset_union_left⟩
    · obtain ⟨c, hc⟩ := tnAdds_plan ts (su.fresh).2 h'
      exact ⟨c, hc.trans Finset.subset_union_right⟩

theorem mem_sysQ_of_tnAdds {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su)
    {d : Constraint} (hd : d ∈ tnAdds (topFamilies q) su) :
    d ∈ sysQ (topNormalise true q su).1 := by
  rw [topNormalise_sysQ H]
  exact Finset.mem_sdiff.mpr ⟨Finset.mem_union_right _ hd, adds_notMem_reads H hd⟩

/-- **The rewrite loses nothing**: every model of the REWRITTEN queue models the original
one.  `S4Top.read_of_top`, at every family, with the deleted reads recovered from the
written partition and its re-expressions. -/
theorem topNormalise_models {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su)
    {rho : Assign} (hm : SModels rho (sysQ (topNormalise true q su).1)) :
    SModels rho (sysQ q) := by
  intro d hd
  by_cases hr : d ∈ tnReads (topFamilies q)
  · obtain ⟨t, ht, pr, hpr, rfl⟩ := mem_tnReads _ hr
    obtain ⟨c, hcsub⟩ := tnAdds_plan (topFamilies q) su ht
    exact S4.read_of_top ((plans_topFam H.qok t ht).subCfs pr hpr)
      (hm _ (mem_sysQ_of_tnAdds H (hcsub S4.top_mem_topAdds)))
      (hm _ (mem_sysQ_of_tnAdds H (hcsub (S4.reexpr_mem_topAdds hpr))))
  · refine hm d ?_
    rw [topNormalise_sysQ H]
    exact Finset.mem_sdiff.mpr ⟨Finset.mem_union_left _ hd, hr⟩

theorem topNormalise_noLoss {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su) :
    NoLoss (sysQ q) (sysQ (topNormalise true q su).1) :=
  fun d hd _ hm => topNormalise_models H hm d hd

/-- **Beyond the mint the rewrite invents nothing**: everything the returned queue holds is
a consequence of the input TOGETHER WITH the `k + 1` constraints the mint adds.  `Conserv`
against the input alone is FALSE for any mint, and `S4Top.topAdd_escapes` is why. -/
theorem topNormalise_conserv {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su) :
    Conserv (sysQ q ∪ tnAdds (topFamilies q) su) (sysQ (topNormalise true q su).1) :=
  Conserv.of_subset (by rw [topNormalise_sysQ H]; exact Finset.sdiff_subset)

/-- **S4c-3.**  The rewrite as a step of `Loop/Strict.lean`'s relation: the deletion is a
`drop`, licensed by the `NoLoss` the written partition supplies.  (The mint itself is the
step `S4Top` §5 describes and `LoopStrict` has no constructor for -- it is an ADDITION with a
fresh name, shaped like `res`.) -/
theorem topNormalise_loopStrict {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su) :
    LoopStrict (sysQ q ∪ tnAdds (topFamilies q) su) (sysQ (topNormalise true q su).1) := by
  refine LoopStrict.drop ?_ ?_
  · rw [topNormalise_sysQ H]; exact Finset.sdiff_subset
  · intro d hd rho hmm
    rcases Finset.mem_union.mp hd with hd' | hd'
    · exact topNormalise_models H hmm d hd'
    · exact hmm d (mem_sysQ_of_tnAdds H hd')

/-! #### The forward direction: every model extends -/

theorem allVars_topAdds_sub {G : System} {v c : Var} {F : Row} {fam : List (Var × Row)}
    (hread : ∀ pr ∈ fam, mk v {pr.1} pr.2 ∈ G) (hne : fam ≠ []) :
    ∀ w ∈ allVars (S4.topAdds v c F fam), w ∈ allVars G ∨ w = c := by
  intro w hw
  obtain ⟨d, hd, hwd⟩ := Finset.mem_biUnion.mp hw
  have hv : v ∈ allVars G := by
    obtain ⟨pr, hpr⟩ := List.exists_mem_of_ne_nil _ hne
    exact lhs_mem_allVars (hread pr hpr)
  rcases Finset.mem_insert.mp hd with rfl | hd'
  · rcases Finset.mem_insert.mp hwd with hw' | hw'
    · exact Or.inl (by simpa [hw'] using hv)
    · exact Or.inr (by simpa using hw')
  · obtain ⟨pr, hpr, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hd')
    rcases Finset.mem_insert.mp hwd with hw' | hw'
    · exact Or.inl (by
        rw [show w = pr.1 from by simpa using hw']
        exact mem_allVars (hread pr hpr) (Or.inr (by simp)))
    · exact Or.inr (by simpa using hw')

/-- **Every model of the input extends to a model of the input plus every family's block.**
One `S4Top.ssat_rewrite_fwd` per family, with the carrier fresh for the system AS IT STANDS
after the previous families' mints -- which is the supply invariant, not an assumption. -/
theorem ssat_addAll : ∀ (plans : List Plan) (su : Sup) (G : System),
    SupOk su → SupFresh su G →
    (∀ t ∈ plans, ∀ pr ∈ famRows t.2.1, mk t.1 {pr.1} pr.2 ∈ G) →
    (∀ t ∈ plans, ∀ pr ∈ famRows t.2.1, pr.2 ⊆ cfs t.2.2) →
    (∀ t ∈ plans, famRows t.2.1 ≠ []) →
    (∀ t ∈ plans, ∀ n ∈ cfs t.2.2, ∃ pr ∈ famRows t.2.1, n ∈ pr.2) →
    ∀ {rho : Assign}, SModels rho G → ∃ rho', SModels rho' (G ∪ tnAdds plans su)
  | [], su, G, _, _, _, _, _, _, rho, hm => ⟨rho, by simpa [tnAdds] using hm⟩
  | t :: ts, su, G, hok, hfr, hread, hFv, hne, hFun, rho, hm => by
    have hfresh : (su.fresh).1 ∉ allVars G := fresh_notMem hok hfr
    have hFsub : ∀ rho, SModels rho G → cfs t.2.2 ⊆ rho t.1 := by
      intro rho' hmm n hn
      obtain ⟨pr, hpr, hnp⟩ := hFun t (by simp) n hn
      exact S4.conc_subset_lhs (hmm _ (hread t (by simp) pr hpr)) hnp
    obtain ⟨hG1, htop, hres⟩ := S4.ssat_rewrite_fwd hfresh (hne t (by simp))
      (hread t (by simp)) (hFv t (by simp)) hFsub hm
    have hmod1 : SModels (setVar rho (su.fresh).1 (rho t.1 \ cfs t.2.2))
        (G ∪ S4.topAdds t.1 (su.fresh).1 (cfs t.2.2) (famRows t.2.1)) := by
      intro d hd
      rcases Finset.mem_union.mp hd with hd' | hd'
      · exact hG1 d hd'
      · rcases Finset.mem_insert.mp hd' with rfl | hd''
        · exact htop
        · obtain ⟨pr, hpr, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hd'')
          exact hres pr hpr
    have hfr1 : SupFresh (su.fresh).2
        (G ∪ S4.topAdds t.1 (su.fresh).1 (cfs t.2.2) (famRows t.2.1)) := by
      refine SupFresh.step hok hfr ?_
      intro w hw
      rw [allVars_union] at hw
      rcases Finset.mem_union.mp hw with hw' | hw'
      · exact Or.inl hw'
      · exact allVars_topAdds_sub (hread t (by simp)) (hne t (by simp)) w hw'
    obtain ⟨rho', hrho'⟩ := ssat_addAll ts (su.fresh).2
      (G ∪ S4.topAdds t.1 (su.fresh).1 (cfs t.2.2) (famRows t.2.1))
      (fresh_supOk hok) hfr1
      (fun s hs pr hpr => Finset.mem_union_left _ (hread s (by simp [hs]) pr hpr))
      (fun s hs => hFv s (by simp [hs])) (fun s hs => hne s (by simp [hs]))
      (fun s hs => hFun s (by simp [hs])) hmod1
    exact ⟨rho', by rw [tnAdds, ← Finset.union_assoc]; exact hrho'⟩

/-- **The rewrite preserves satisfiability forwards.** -/
theorem topNormalise_ssat_fwd {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su)
    (h : SSat (sysQ q)) : SSat (sysQ (topNormalise true q su).1) := by
  obtain ⟨rho, hm⟩ := h
  obtain ⟨rho', hm'⟩ := ssat_addAll (topFamilies q) su (sysQ q) H.sup H.fresh
    (fun t ht => (plans_topFam H.qok t ht).read_mem)
    (fun t ht => (plans_topFam H.qok t ht).subCfs)
    (fun t ht => (plans_topFam H.qok t ht).famRows_ne)
    (fun t ht => (plans_topFam H.qok t ht).cfs_union) hm
  refine ⟨rho', ?_⟩
  rw [topNormalise_sysQ H]
  exact fun d hd => hm' d (Finset.mem_sdiff.mp hd).1

/-- **S4c-1 (d).  The executable rewrite is SATISFIABILITY-EQUIVALENT.** -/
theorem topNormalise_ssat_iff {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su) :
    SSat (sysQ q) ↔ SSat (sysQ (topNormalise true q su).1) := by
  constructor
  · exact topNormalise_ssat_fwd H
  · rintro ⟨rho, hm⟩
    exact ⟨rho, topNormalise_models H hm⟩


/-! ### Discharging the side conditions from the code, and the flag split -/

/-- `PQueue.build` never returns a self-unification: `Q.insert` refuses one. -/
theorem buildQueue_no_self {cs : List CsItem} {su su' : Sup} {q : PQueue}
    (h : buildQueue cs su = .ok (q, su')) : ∀ p ∈ q.elems, p.isSelfUnification = false := by
  simp only [buildQueue] at h
  obtain ⟨⟨ps, su0⟩, -, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨rfl, -⟩ := h2
  intro p hp
  exact ofList_selfUnif_free hp

/-- **With the flag OFF the rewrite is the identity and draws nothing.** -/
@[simp] theorem topNormalise_off (q : PQueue) (su : Sup) :
    topNormalise false q su = (q, su, []) := rfl

/-- One carrier per family. -/
theorem tnCarriers_length : ∀ (plans : List Plan) (su : Sup),
    (tnCarriers plans su).length = plans.length
  | [], _ => rfl
  | _ :: ts, su => by simp [tnCarriers, tnCarriers_length ts (su.fresh).2]

/-- The `tnorm` records the rewrite prints carry exactly those carriers. -/
theorem recsOf_carriers : ∀ (plans : List Plan) (su : Sup),
    (recsOf plans su).map (fun r => r.2.1) = tnCarriers plans su
  | [], _ => rfl
  | _ :: ts, su => by simp [recsOf, tnCarriers, recsOf_carriers ts (su.fresh).2]

/-- **S4c-1 (b), packaged.**  Every carrier is fresh for the WHOLE input system, there is one
per family, and they are pairwise distinct. -/
theorem carriers_spec {L : List Lbl} {q : PQueue} {su : Sup} (H : TnOk L q su) :
    (∀ c ∈ tnCarriers (topFamilies q) su, c ∉ allVars (sysQ q)) ∧
    (tnCarriers (topFamilies q) su).length = (topFamilies q).length ∧
    (tnCarriers (topFamilies q) su).Nodup :=
  ⟨carriers_notMem _ _ _ H.sup H.fresh, tnCarriers_length _ _, carriers_nodup _ _ H.sup⟩

/-! ### The two directions with the FLAG as a parameter (S4c-2's bridge) -/

/-- **Whatever the flag, the queue the checks read loses nothing of the queue
`buildQueue` returned.** -/
theorem tn_models {L : List Lbl} {q : PQueue} {su : Sup} (on : Bool) (H : TnOk L q su)
    {rho : Assign} (hm : SModels rho (sysQ (topNormalise on q su).1)) : SModels rho (sysQ q) := by
  cases on
  · simpa using hm
  · exact topNormalise_models H hm

theorem tn_noLoss {L : List Lbl} {q : PQueue} {su : Sup} (on : Bool) (H : TnOk L q su) :
    NoLoss (sysQ q) (sysQ (topNormalise on q su).1) :=
  fun d hd _ hm => tn_models on H hm d hd

/-- **...and is satisfiable exactly when it is.** -/
theorem tn_ssat_iff {L : List Lbl} {q : PQueue} {su : Sup} (on : Bool) (H : TnOk L q su) :
    SSat (sysQ q) ↔ SSat (sysQ (topNormalise on q su).1) := by
  cases on
  · simp
  · exact topNormalise_ssat_iff H


/-! ### The vocabulary of the input, and `SupFresh` in a form a caller can check -/

theorem mem_allVars_sysQ {q : PQueue} {w : Nat} (h : w ∈ allVars (sysQ q)) :
    ∃ p ∈ q.elems, w = p.lhs ∨ w ∈ p.rhs.abstr.elems := by
  obtain ⟨d, hd, hw⟩ := Finset.mem_biUnion.mp h
  obtain ⟨p, hp, rfl⟩ := mem_sysQ.mp hd
  refine ⟨p, hp, ?_⟩
  rcases Finset.mem_insert.mp hw with hw' | hw'
  · exact Or.inl (by simpa using hw')
  · exact Or.inr (by simpa using hw')

/-- `SupFresh` at a queue reduces to a statement about the ids the queue MENTIONS -- which is
how a caller discharges `TnOk.fresh` without unfolding `allVars`. -/
theorem supFresh_sysQ {q : PQueue} {su : Sup}
    (h : ∀ p ∈ q.elems, ∀ w, (w = p.lhs ∨ w ∈ p.rhs.abstr.elems) → ¬ Sup.Reach su w) :
    SupFresh su (sysQ q) := by
  intro z hz hmem
  obtain ⟨p, hp, hw⟩ := mem_allVars_sysQ hmem
  exact h p hp z hw hz

/-- **`TnOk` DISCHARGED FROM THE CODE.**  `qok` is `Wf.buildQueue_qok`, `self` is
`buildQueue_no_self` above; what is left is `LblCoh` (`Wf.coh`) and the supply invariant
`SupOk`/`SupFresh`, which every run-level theorem of this development already carries and
`Supply.lean` proves is preserved by `step`. -/
theorem tnOk_of_buildQueue {L : List Lbl} {cs : List CsItem} {su su' : Sup} {q : PQueue}
    (hcoh : LblCoh L) (hcs : ∀ c ∈ cs, CsItem.InPool L c)
    (hq : buildQueue cs su = .ok (q, su'))
    (hok : SupOk su') (hfr : SupFresh su' (sysQ q)) : TnOk L q su' :=
  ⟨hcoh, buildQueue_qok hcs hq, buildQueue_no_self hq, hok, hfr⟩

/-! ### NOT VACUOUS: a queue the selector fires on, with `TnOk` discharged

Three reads at one left-hand side with distinct singleton parts -- the shape `k` projections
of one open-row record parameter give (`S4-DESIGN.md` §1), and the smallest one the `k ≥ 3`
trigger accepts.  Every fact below is checked IN THE KERNEL. -/

private def exP (x : Nat) (l : Nat) : LPart :=
  ⟨1, ⟨SSet.ofList [x], SSet.ofList [Lbl.repro l]⟩, none⟩

private def exQ : PQueue := ⟨[exP 2 1, exP 3 2, exP 4 3], Graph.empty⟩
private def exL : List Lbl := [Lbl.repro 1, Lbl.repro 2, Lbl.repro 3]
private def exSu : Sup := ⟨100, 200, 300, 1024, 0⟩

set_option maxRecDepth 10000 in
/-- The selector FIRES: one family, at `v = 1`, with three reads and `|F| = 3`. -/
theorem exQ_fires :
    ((topFamilies exQ).map (fun t => (t.1, t.2.1.length, t.2.2.elems.length))) = [(1, 3, 3)] := by
  decide

set_option maxRecDepth 10000 in
/-- ...and the correspondence's side conditions hold. -/
theorem exQ_tnOk : TnOk exL exQ exSu := by
  refine ⟨by unfold LblCoh; decide, ?_, by decide, ⟨by decide, by decide, by decide⟩, ?_⟩
  · intro p hp
    have hp' : p = exP 2 1 ∨ p = exP 3 2 ∨ p = exP 4 3 := by simpa [exQ] using hp
    rcases hp' with rfl | rfl | rfl <;>
      exact ⟨by decide, ⟨by decide, by
        simp [exP, exL, SSet.ofList, SSet.incl, SSet.empty, SSet.contains]⟩⟩
  · have hb : ∀ p ∈ exQ.elems, p.lhs ≤ 4 ∧ ∀ w ∈ p.rhs.abstr.elems, w ≤ 4 := by decide
    refine supFresh_sysQ ?_
    intro p hp w hw hc
    have hle : w ≤ 4 := by
      rcases hw with rfl | hw
      · exact (hb p hp).1
      · exact (hb p hp).2 w hw
    simp only [Sup.Reach, exSu] at hc
    omega

/-- ...so (c) applies to it, at the digit. -/
theorem exQ_sys : sysQ (topNormalise true exQ exSu).1 =
    (sysQ exQ ∪ tnAdds (topFamilies exQ) exSu) \ tnReads (topFamilies exQ) :=
  topNormalise_sysQ exQ_tnOk

/-- ...and so does (d). -/
theorem exQ_equiv : SSat (sysQ exQ) ↔ SSat (sysQ (topNormalise true exQ exSu).1) :=
  topNormalise_ssat_iff exQ_tnOk

end Rowpartition.Loop
