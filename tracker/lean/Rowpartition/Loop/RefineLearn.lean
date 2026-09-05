/-
# L3 (i), round 2: the `learn` branch

`Loop/Refine.lean` refines the three ENVIRONMENT branches and `Loop/RefineConcrete.lean` the
`concrete` one.  This file adds the fifth and last, `learnPartitions` -- the branch that
MINTS, and therefore the only one that needs the two things the others did not:

* a FRESHNESS invariant for the id supply, because `Cut.SplitApp.fresh` and `Cut.ResApp.fresh`
  ask for `z ∉ allVars G` and the loop's `z` comes from `Supply.fresh`.  `Sup.ofSeed` is NOT
  touched: `⟨lo, lo + 100000, 0, 1024⟩` is faithful to `tracker/repro/nameloss/Replay.scala`'s
  `new Supply(lo, lo + 100000)` and to `scalaparsers/Supply.scala`'s process-global
  `private var block: Int = 0`, so the repro harness's supply really is non-injective past
  100 000 draws and freshness really has to be a HYPOTHESIS.  The REPLAY path satisfies it:
  `Replay.lean`'s `Segment.sup` reads `blk`/`bsz` from the trace's `sin` record
  (`RowTrace.scala`), i.e. the compiler's real global counter, which is always ahead of the
  block it handed out;
* the rules themselves, each as `∃ H, LoopRun G H ∧ G ⊆ H ∧ (conclusions ∈ H)`, the shape
  `replace_run` / `subPartitions_run` / `cancellation_run` already have.

The three flag-guarded branches that the shipped defaults switch OFF -- `commonSubexpression`'s
mint (`genRules=all`), `disjunction` and the `emptyRow` reuse -- are excluded by hypotheses on
`Flags`, which is what the plan's "Known scope limits" already scopes out (M4, and disjunction
by seeds only).
-/
import Rowpartition.Loop.RefineConcrete

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

set_option linter.unusedSimpArgs false

/-! ## 1. The id supply: reachability, well-formedness, freshness -/

/-- The ids the supply can still hand out.  `fresh` returns `lo` while `lo ≠ hi` and then
jumps to the global block counter `blk`, so every future id is either in `[lo, hi)` or at
`blk` or beyond. -/
def Sup.Reach (su : Sup) (z : Nat) : Prop := (su.lo ≤ z ∧ z < su.hi) ∨ su.blk ≤ z

/-- The supply is coherent: its block is nonempty, the global counter is ahead of it, and a
block holds at least two ids.  True of every supply the COMPILER hands `Subst.solve` (the
`sin` record carries the real `Supply.block`); false of `Sup.ofSeed`, whose `blk = 0` is the
repro harness's real, process-global starting counter. -/
structure SupOk (su : Sup) : Prop where
  /-- the current block is not exhausted-and-inverted -/
  lohi : su.lo ≤ su.hi
  /-- the global counter is ahead of the current block -/
  ahead : su.hi ≤ su.blk
  /-- a block holds at least two ids -/
  bsz : 2 ≤ su.bsz

/-- No id the supply can still produce is already in use. -/
def SupFresh (su : Sup) (G : System) : Prop := ∀ z, Sup.Reach su z → z ∉ allVars G

/-- `Supply.fresh` inside the current block. -/
theorem fresh_lt {su : Sup} (h : su.lo ≠ su.hi) :
    su.fresh = (su.lo, { su with lo := su.lo + 1, drawn := su.drawn + 1 }) := by
  unfold Sup.fresh; rw [if_pos (by simpa using h)]

/-- `Supply.fresh` when the block is exhausted: it takes the next global block. -/
theorem fresh_eq {su : Sup} (h : su.lo = su.hi) :
    su.fresh = (su.blk,
      { su with lo := su.blk + 1, hi := su.blk + su.bsz - 1, blk := su.blk + su.bsz,
                drawn := su.drawn + 1 }) := by
  unfold Sup.fresh; rw [if_neg (by simpa using h)]

theorem fresh_reach {su : Sup} (h : SupOk su) : Sup.Reach su (su.fresh).1 := by
  obtain ⟨hlohi, hahead, hbsz⟩ := h
  unfold Sup.Reach
  by_cases hne : su.lo = su.hi
  · rw [fresh_eq hne]; exact Or.inr (by omega)
  · rw [fresh_lt hne]; exact Or.inl ⟨by omega, by omega⟩

theorem fresh_supOk {su : Sup} (h : SupOk su) : SupOk (su.fresh).2 := by
  obtain ⟨hlohi, hahead, hbsz⟩ := h
  by_cases hne : su.lo = su.hi
  · rw [fresh_eq hne]; exact ⟨by dsimp only; omega, by dsimp only; omega, by dsimp only; omega⟩
  · rw [fresh_lt hne]; exact ⟨by dsimp only; omega, by dsimp only; omega, by dsimp only; omega⟩

theorem fresh_reach_mono {su : Sup} (h : SupOk su) :
    ∀ z, Sup.Reach (su.fresh).2 z → Sup.Reach su z ∧ z ≠ (su.fresh).1 := by
  obtain ⟨hlohi, hahead, hbsz⟩ := h
  intro z hz
  unfold Sup.Reach at hz ⊢
  by_cases hne : su.lo = su.hi
  · rw [fresh_eq hne] at hz ⊢
    dsimp only at hz ⊢
    rcases hz with ⟨h1, h2⟩ | h1
    · exact ⟨Or.inr (by omega), by omega⟩
    · exact ⟨Or.inr (by omega), by omega⟩
  · rw [fresh_lt hne] at hz ⊢
    dsimp only at hz ⊢
    rcases hz with ⟨h1, h2⟩ | h1
    · exact ⟨Or.inl ⟨by omega, by omega⟩, by omega⟩
    · exact ⟨Or.inr (by omega), by omega⟩

theorem SupFresh.mono_allVars {su : Sup} {G G' : System} (h : SupFresh su G)
    (hsub : allVars G' ⊆ allVars G) : SupFresh su G' :=
  fun z hz hmem => h z hz (hsub hmem)

theorem SupFresh.sub {su : Sup} {G G' : System} (h : SupFresh su G) (hsub : G' ⊆ G) :
    SupFresh su G' := h.mono_allVars (allVars_mono hsub)

theorem SupFresh.step {su : Sup} {G G' : System} (hok : SupOk su) (h : SupFresh su G)
    (hv : ∀ w ∈ allVars G', w ∈ allVars G ∨ w = (su.fresh).1) : SupFresh (su.fresh).2 G' := by
  intro z hz hmem
  obtain ⟨hr, hne⟩ := fresh_reach_mono hok z hz
  rcases hv z hmem with hh | rfl
  · exact h z hr hh
  · exact hne rfl

/-- The drawn id is fresh: this is exactly `Cut.SplitApp.fresh` / `Cut.ResApp.fresh`. -/
theorem fresh_notMem {su : Sup} {G : System} (hok : SupOk su) (h : SupFresh su G) :
    (su.fresh).1 ∉ allVars G := h _ (fresh_reach hok)

/-! ## 2. Adding a constraint over variables already in play -/

theorem SupFresh.insertOf {su : Sup} {G : System} {c : Constraint} (h : SupFresh su G)
    (h1 : c.lhs ∈ allVars G) (h2 : vset c ⊆ allVars G) : SupFresh su (insert c G) :=
  h.mono_allVars (allVars_insert_subset h1 h2)

/-- The variables of a partition of a state are in the vocabulary the state denotes. -/
theorem lhs_mem_allVars_sys {s : State} {p : LPart} (hp : p ∈ s.parts) :
    p.lhs ∈ allVars (sys s) := lhs_mem_allVars (mem_sys_of_part hp)

theorem vset_subset_allVars_sys {s : State} {p : LPart} (hp : p ∈ s.parts) :
    vset p.toConstraint ⊆ allVars (sys s) := vset_subset_allVars (mem_sys_of_part hp)


/-! ## 3. The rules of `learnPartitions`, one at a time -/

/-- **`selfSubstitution`** is `SelfSubstStep`. -/
theorem selfSubstitution_run {G : System} {ns : Names} {v : Nat} {a : SSet Nat} {c : SSet Lbl}
    {S : SSet LPart} (hmem : mk v a.fs (cfs c) ∈ G) (hv : v ∈ a.fs)
    (h : selfSubstitution ns v a c = .ok S) : ∀ p ∈ S.elems, Adds G p.toConstraint := by
  simp only [selfSubstitution] at h
  split at h
  · rename_i hce
    rw [Except.ok.injEq] at h
    subst h
    have hmem0 : mk v a.fs (∅ : Row) ∈ G := by
      rwa [cfs_eq_empty_iff.mp hce] at hmem
    intro p hp
    obtain ⟨u, hu, rfl⟩ := SSet.mem_map hp
    have huv : u ∈ a.fs ∧ u ≠ v := by
      have := SSet.mem_excl_iff.mp hu
      exact ⟨List.mem_toFinset.mpr this.1, this.2⟩
    intro H hGH
    refine LoopRel.nongen (NonGenStep.selfSubst ?_)
    have happ : SelfSubstApp H (mk v a.fs (∅ : Row)) u :=
      ⟨hGH hmem0, by rw [lhs_mk, vset_mk]; exact hv, rfl,
        by rw [vset_mk]; exact huv.1, huv.2⟩
    have hst := SelfSubstStep.intro happ
    have hgoal : (⟨u, RHS.empty, some Inference.selfSubstitution⟩ : LPart).toConstraint
        = mk u ∅ (∅ : Row) := rfl
    rw [hgoal]
    simpa only [selfSubstResult] using hst
  · exact absurd h (by simp)

/-- **`cancellation`, in general position** (`RefineConcrete.cancellation_run` is the special
case `rhs1 = RHS.ofConcr fs`, where only the second branch can fire).  Both branches are
`CancelStep`, with the two premises swapped. -/
theorem cancellationG_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {v : Nat} {r1 r2 : RHS}
    (h1L : ∀ x ∈ r1.conc.elems, x ∈ L) (h2L : ∀ x ∈ r2.conc.elems, x ∈ L)
    (h1 : mk v r1.abstr.fs (cfs r1.conc) ∈ G) (h2 : mk v r2.abstr.fs (cfs r2.conc) ∈ G) :
    ∀ p ∈ (cancellation v r1 r2).elems, Adds G p.toConstraint := by
  -- the two set-difference computations, once each
  have hfsA : (r1.abstr.removedAll (r1.abstr.inter r2.abstr)).fs = r1.abstr.fs \ r2.abstr.fs := by
    rw [SSet.fs_removedAll, SSet.fs_inter]
    ext x; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  have hfsB : (r2.abstr.removedAll (r1.abstr.inter r2.abstr)).fs = r2.abstr.fs \ r1.abstr.fs := by
    rw [SSet.fs_removedAll, SSet.fs_inter]
    ext x; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  have hcfsA : cfs (r1.conc.removedAll (r1.conc.inter r2.conc)) = cfs r1.conc \ cfs r2.conc := by
    rw [cfs_removedAll hcoh h1L (fun x hx => h1L x (SSet.mem_inter hx)), cfs_inter hcoh h1L h2L]
    ext n; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  have hcfsB : cfs (r2.conc.removedAll (r1.conc.inter r2.conc)) = cfs r2.conc \ cfs r1.conc := by
    rw [cfs_removedAll hcoh h2L (fun x hx => h1L x (SSet.mem_inter hx)), cfs_inter hcoh h1L h2L]
    ext n; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  intro z hz
  simp only [cancellation] at hz
  split at hz
  · rename_i hb1
    rw [Bool.and_eq_true] at hb1
    split at hz
    · rename_i x tl hx
      have hlone : r1.abstr.fs \ r2.abstr.fs = {x} := by
        have hlen : (r1.abstr.removedAll (r1.abstr.inter r2.abstr)).elems.length = 1 := by
          have := hb1.2; simpa [SSet.size] using this
        rw [hx] at hlen
        simp only [List.length_cons] at hlen
        have htl : tl = [] := List.eq_nil_of_length_eq_zero (by omega)
        rw [← hfsA, SSet.fs, hx, htl]
        simp
      have hconle : cfs r1.conc ⊆ cfs r2.conc := by
        have hg : (r1.conc.removedAll (r1.conc.inter r2.conc)).isEmpty = true := by
          have := hb1.1; simpa using this
        have hgg := cfs_eq_empty_iff.mp hg
        rw [hcfsA] at hgg
        intro n hn
        by_contra hnf
        exact absurd (hgg ▸ Finset.mem_sdiff.mpr ⟨hn, hnf⟩) (Finset.notMem_empty n)
      rw [List.mem_singleton.mp (SSet.mem_ofList hz)]
      intro H hGH
      refine LoopRel.nongen (NonGenStep.cancel ?_)
      have happ : CancelApp H (mk v r1.abstr.fs (cfs r1.conc)) (mk v r2.abstr.fs (cfs r2.conc)) x :=
        ⟨hGH h1, hGH h2, rfl, by rw [conc_mk, conc_mk]; exact hconle,
          by rw [vset_mk, vset_mk]; exact hlone⟩
      have hst := CancelStep.intro happ
      have hgoal : (⟨x, ⟨r2.abstr.removedAll (r1.abstr.inter r2.abstr),
          r2.conc.removedAll (r1.conc.inter r2.conc)⟩, some Inference.cancellation⟩
          : LPart).toConstraint
          = mk x (r2.abstr.fs \ r1.abstr.fs) (cfs r2.conc \ cfs r1.conc) := by
        rw [toConstraint_eq, hfsB, hcfsB]
      rw [hgoal]
      simpa only [cancelResult, vset_mk, conc_mk] using hst
    · cases hz
  · split at hz
    · rename_i hb2
      rw [Bool.and_eq_true] at hb2
      split at hz
      · rename_i y tl hy
        have hlone : r2.abstr.fs \ r1.abstr.fs = {y} := by
          have hlen : (r2.abstr.removedAll (r1.abstr.inter r2.abstr)).elems.length = 1 := by
            have := hb2.2; simpa [SSet.size] using this
          rw [hy] at hlen
          simp only [List.length_cons] at hlen
          have htl : tl = [] := List.eq_nil_of_length_eq_zero (by omega)
          rw [← hfsB, SSet.fs, hy, htl]
          simp
        have hconle : cfs r2.conc ⊆ cfs r1.conc := by
          have hg : (r2.conc.removedAll (r1.conc.inter r2.conc)).isEmpty = true := by
            have := hb2.1; simpa using this
          have hgg := cfs_eq_empty_iff.mp hg
          rw [hcfsB] at hgg
          intro n hn
          by_contra hnf
          exact absurd (hgg ▸ Finset.mem_sdiff.mpr ⟨hn, hnf⟩) (Finset.notMem_empty n)
        rw [List.mem_singleton.mp (SSet.mem_ofList hz)]
        intro H hGH
        refine LoopRel.nongen (NonGenStep.cancel ?_)
        have happ : CancelApp H (mk v r2.abstr.fs (cfs r2.conc))
            (mk v r1.abstr.fs (cfs r1.conc)) y :=
          ⟨hGH h2, hGH h1, rfl, by rw [conc_mk, conc_mk]; exact hconle,
            by rw [vset_mk, vset_mk]; exact hlone⟩
        have hst := CancelStep.intro happ
        have hgoal : (⟨y, ⟨r1.abstr.removedAll (r1.abstr.inter r2.abstr),
            r1.conc.removedAll (r1.conc.inter r2.conc)⟩, some Inference.cancellation⟩
            : LPart).toConstraint
            = mk y (r1.abstr.fs \ r2.abstr.fs) (cfs r1.conc \ cfs r2.conc) := by
          rw [toConstraint_eq, hfsA, hcfsA]
        rw [hgoal]
        simpa only [cancelResult, vset_mk, conc_mk] using hst
      · cases hz
    · cases hz


/-- What one rule's run must establish: a reachable system holding the rule's conclusions,
with the supply invariant re-established for the supply the rule RETURNS. -/
def RuleRun (G : System) (S : SSet LPart) (su' : Sup) (H : System) : Prop :=
  LoopRun G H ∧ G ⊆ H ∧ (∀ p ∈ S.elems, p.toConstraint ∈ H) ∧ SupOk su' ∧ SupFresh su' H

theorem RuleRun.ofAdds {G : System} {S : SSet LPart} {su : Sup} (hok : SupOk su)
    (hfr : SupFresh su G) (h : ∀ p ∈ S.elems, Adds G p.toConstraint)
    (h1 : ∀ p ∈ S.elems, p.lhs ∈ allVars G)
    (h2 : ∀ p ∈ S.elems, vset p.toConstraint ⊆ allVars G) :
    ∃ H : System, RuleRun G S su H := by
  obtain ⟨H, hrun, hsub, hmem, hv⟩ := adds_list_vars (G := G) (S.elems.map LPart.toConstraint)
    (by intro c hc; obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hc; exact h p hp)
    (by intro c hc; obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hc; exact h1 p hp)
    (by intro c hc; obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hc; exact h2 p hp)
  exact ⟨H, hrun, hsub, fun p hp => hmem _ (List.mem_map.mpr ⟨p, hp, rfl⟩), hok,
    hfr.mono_allVars hv⟩

theorem RuleRun.empty {G : System} {su : Sup} (hok : SupOk su) (hfr : SupFresh su G) :
    ∃ H : System, RuleRun G (SSet.empty : SSet LPart) su H :=
  ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, (by intro p hp; cases hp), hok, hfr⟩

/-- **`subBody`** is `subst_one_run`: `SubstStep` plus one `SubstStep` per de-duplicated
variable. -/
theorem subBody_run {G : System} {v u : Nat} {r1 r2 : RHS} {S : SSet LPart} {su : Sup}
    (hok : SupOk su) (hfr : SupFresh su G)
    (h1 : mk v r1.abstr.fs (cfs r1.conc) ∈ G) (h2 : mk u r2.abstr.fs (cfs r2.conc) ∈ G)
    (h : subBody v r1 u r2 = .ok S) : ∃ H : System, RuleRun G S su H := by
  simp only [subBody] at h
  split at h
  · rename_i hcv
    cases hrs : rhsSubstitute r2 v r1 with
    | error m => rw [hrs] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨nrhs, es⟩ := w
      rw [hrs] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
      subst h
      obtain ⟨H, hrun, hsub, hc, hdd, hv⟩ :=
        subst_one_run (r := (⟨u, r2, none⟩ : LPart)) (i := some Inference.substitution)
          h2 h1 hcv hrs
      refine ⟨H, hrun, hsub, ?_, hok, hfr.mono_allVars hv⟩
      intro p hp
      rcases SSet.mem_incl hp with hp' | rfl
      · obtain ⟨w0, hw0, rfl⟩ := SSet.mem_map hp'
        exact hdd w0 hw0
      · exact hc
  · simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    exact RuleRun.empty hok hfr

/-- Where `cancellation`'s conclusions live: its left-hand side is one of the premises'
right-hand variables, and its right-hand variables come from the premises. -/
theorem cancellation_vars {v : Nat} {r1 r2 : RHS} :
    ∀ p ∈ (cancellation v r1 r2).elems,
      (p.lhs ∈ r1.abstr.fs ∨ p.lhs ∈ r2.abstr.fs) ∧
      vset p.toConstraint ⊆ r1.abstr.fs ∪ r2.abstr.fs := by
  have hfsA : (r1.abstr.removedAll (r1.abstr.inter r2.abstr)).fs
      = r1.abstr.fs \ r2.abstr.fs := by
    rw [SSet.fs_removedAll, SSet.fs_inter]
    ext x; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  have hfsB : (r2.abstr.removedAll (r1.abstr.inter r2.abstr)).fs
      = r2.abstr.fs \ r1.abstr.fs := by
    rw [SSet.fs_removedAll, SSet.fs_inter]
    ext x; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  intro z hz
  simp only [cancellation] at hz
  split at hz
  · split at hz
    · rename_i x tl hx
      rw [List.mem_singleton.mp (SSet.mem_ofList hz)]
      have hxm : x ∈ r1.abstr.fs \ r2.abstr.fs := by
        rw [← hfsA, SSet.fs, List.mem_toFinset, hx]; exact List.mem_cons_self ..
      refine ⟨Or.inl (Finset.mem_sdiff.mp hxm).1, ?_⟩
      rw [toConstraint_eq, vset_mk, hfsB]
      exact (Finset.sdiff_subset).trans Finset.subset_union_right
    · cases hz
  · split at hz
    · split at hz
      · rename_i y tl hy
        rw [List.mem_singleton.mp (SSet.mem_ofList hz)]
        have hym : y ∈ r2.abstr.fs \ r1.abstr.fs := by
          rw [← hfsB, SSet.fs, List.mem_toFinset, hy]; exact List.mem_cons_self ..
        refine ⟨Or.inr (Finset.mem_sdiff.mp hym).1, ?_⟩
        rw [toConstraint_eq, vset_mk, hfsA]
        exact (Finset.sdiff_subset).trans Finset.subset_union_left
      · cases hz
    · cases hz

/-- **`substitution`** is `subBody` twice. -/
theorem substitution_run {G : System} {v u : Nat} {r1 r2 : RHS} {S : SSet LPart} {su : Sup}
    (hok : SupOk su) (hfr : SupFresh su G)
    (h1 : mk v r1.abstr.fs (cfs r1.conc) ∈ G) (h2 : mk u r2.abstr.fs (cfs r2.conc) ∈ G)
    (h : substitution v r1 u r2 = .ok S) : ∃ H : System, RuleRun G S su H := by
  simp only [substitution] at h
  cases ha : subBody v r1 u r2 with
  | error m => rw [ha] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
  | ok S1 =>
    cases hb : subBody u r2 v r1 with
    | error m => rw [ha, hb] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok S2 =>
      rw [ha, hb] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
      subst h
      obtain ⟨H1, hrun1, hsub1, hm1, hok1, hfr1⟩ := subBody_run hok hfr h1 h2 ha
      obtain ⟨H2, hrun2, hsub2, hm2, hok2, hfr2⟩ :=
        subBody_run hok1 hfr1 (hsub1 h2) (hsub1 h1) hb
      refine ⟨H2, hrun1.trans hrun2, hsub1.trans hsub2, ?_, hok2, hfr2⟩
      intro p hp
      rcases SSet.mem_concat hp with hp' | hp'
      · exact hsub2 (hm1 p hp')
      · exact hm2 p hp'


/-- The size of a duplicate-free `SSet` is the cardinality of the finite set it denotes. -/
theorem size_eq_card {α : Type} [SVal α] [LawfulSVal α] [DecidableEq α] {s : SSet α}
    (h : s.Nodup) : s.size = s.fs.card := by
  rw [SSet.fs, List.toFinset_card_of_nodup h, SSet.size]

/-- An `SSet Lbl` that is `Set`-equal to the empty set denotes the empty label set. -/
theorem cfs_of_eqv_empty {c : SSet Lbl} (h : c.eqv SSet.empty = true) : cfs c = ∅ := by
  rw [SSet.eqv, Bool.and_eq_true] at h
  have hlen : c.elems.length = 0 := by simpa [SSet.size, SSet.empty] using h.1
  have hnil : c.elems = [] := List.eq_nil_of_length_eq_zero hlen
  simp [cfs, hnil]

/-- At `genRules=cut` `commonSubexpression` never draws an id. -/
theorem commonSubexpression_su {fl : Flags} (hcse : fl.cseMints = false) (v u : Nat)
    (r1 r2 : RHS) (rhss : RHS → Option Nat) (su : Sup) :
    (commonSubexpression fl v r1 u r2 rhss su).2 = su := by
  simp only [commonSubexpression]
  split
  · rfl
  · split
    · rfl
    · split
      · rfl
      · split
        · rfl
        · split
          · rfl
          · rename_i hcm
            exact absurd hcse (by simpa using hcm)

/-- **`commonSubexpression`**, at the shipped `genRules=cut` where it never mints: the reuse
branch is `CutStep.reuse` and the two folding branches are `CutStep.fold`. -/
theorem commonSubexpression_run {G : System} {fl : Flags} {v u : Nat} {r1 r2 : RHS}
    {rhss : RHS → Option Nat} {su : Sup}
    (hcse : fl.cseMints = false) (hok : SupOk su) (hfr : SupFresh su G) (hne : v ≠ u)
    (hn1 : r1.abstr.Nodup) (hn2 : r2.abstr.Nodup)
    (h1 : mk v r1.abstr.fs (cfs r1.conc) ∈ G) (h2 : mk u r2.abstr.fs (cfs r2.conc) ∈ G)
    (hlk : ∀ z, rhss (RHS.ofAbstr (r1.abstr.inter r2.abstr)) = some z →
      _root_.Rowpartition.Names G z (r1.abstr.fs ∩ r2.abstr.fs)) :
    ∃ H : System, RuleRun G (commonSubexpression fl v r1 u r2 rhss su).1 su H := by
  have hintfs : (r1.abstr.inter r2.abstr).fs = r1.abstr.fs ∩ r2.abstr.fs := SSet.fs_inter _ _
  have hshared : shared (mk v r1.abstr.fs (cfs r1.conc)) (mk u r2.abstr.fs (cfs r2.conc))
      = r1.abstr.fs ∩ r2.abstr.fs := by rw [shared, vset_mk, vset_mk]
  have hsharedS : shared (mk u r2.abstr.fs (cfs r2.conc)) (mk v r1.abstr.fs (cfs r1.conc))
      = r2.abstr.fs ∩ r1.abstr.fs := by rw [shared, vset_mk, vset_mk]
  have hA : r1.abstr.fs ⊆ allVars G := by
    have := vset_subset_allVars h1; rwa [vset_mk] at this
  have hB : r2.abstr.fs ⊆ allVars G := by
    have := vset_subset_allVars h2; rwa [vset_mk] at this
  have hvA : v ∈ allVars G := by have := lhs_mem_allVars h1; rwa [lhs_mk] at this
  have huA : u ∈ allVars G := by have := lhs_mem_allVars h2; rwa [lhs_mk] at this
  simp only [commonSubexpression]
  split
  · exact RuleRun.empty hok hfr
  · rename_i hsz
    have htwo : 2 ≤ (r1.abstr.fs ∩ r2.abstr.fs).card := by
      have hc := size_eq_card (SSet.nodup_inter hn1 (t := r2.abstr))
      rw [hintfs] at hc
      omega
    have hpair : CsePair G (mk v r1.abstr.fs (cfs r1.conc)) (mk u r2.abstr.fs (cfs r2.conc)) :=
      ⟨h1, h2, by rw [lhs_mk, lhs_mk]; exact hne, by rw [hshared]; exact htwo⟩
    have hpairS : CsePair G (mk u r2.abstr.fs (cfs r2.conc)) (mk v r1.abstr.fs (cfs r1.conc)) :=
      ⟨h2, h1, by rw [lhs_mk, lhs_mk]; exact fun hh => hne hh.symm,
        by rw [hsharedS, Finset.inter_comm]; exact htwo⟩
    split
    · rename_i z hz
      have hzn := hlk z hz
      have hzA : z ∈ allVars G := by
        obtain ⟨d, hd, hdz, -, -⟩ := hzn
        exact hdz ▸ lhs_mem_allVars hd
      have hg1 : (⟨v, ⟨(r1.abstr.removedAll (r1.abstr.inter r2.abstr)).incl z, r1.conc⟩,
          some Inference.commonSubexpression⟩ : LPart).toConstraint
          = mk v (insert z (r1.abstr.fs \ (r1.abstr.fs ∩ r2.abstr.fs))) (cfs r1.conc) := by
        rw [toConstraint_eq, SSet.fs_incl, SSet.fs_removedAll, hintfs]
      have hg2 : (⟨u, ⟨(r2.abstr.removedAll (r1.abstr.inter r2.abstr)).incl z, r2.conc⟩,
          some Inference.commonSubexpression⟩ : LPart).toConstraint
          = mk u (insert z (r2.abstr.fs \ (r1.abstr.fs ∩ r2.abstr.fs))) (cfs r2.conc) := by
        rw [toConstraint_eq, SSet.fs_incl, SSet.fs_removedAll, hintfs]
      have hst : CutStep G (reuseResult G (mk v r1.abstr.fs (cfs r1.conc))
          (mk u r2.abstr.fs (cfs r2.conc)) z) :=
        CutStep.reuse hpair (by rw [hshared]; exact hzn)
      rw [reuseResult, reduce, reduce, hshared, lhs_mk, lhs_mk, vset_mk, vset_mk,
        conc_mk, conc_mk] at hst
      refine ⟨_, Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.cse hst)), ?_, ?_,
        hok, ?_⟩
      · exact (Finset.subset_insert _ _).trans (Finset.subset_insert _ _)
      · intro p hp
        rcases List.mem_cons.mp (SSet.mem_ofList hp) with rfl | hp'
        · rw [hg1]; exact Finset.mem_insert_self _ _
        · rw [List.mem_singleton] at hp'; subst hp'
          rw [hg2]; exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
      · refine hfr.mono_allVars ?_
        refine (allVars_insert_subset ?_ ?_).trans (allVars_insert_subset ?_ ?_)
        · rw [lhs_mk]
          exact allVars_mono (Finset.subset_insert _ _) hvA
        · rw [vset_mk]
          exact (Finset.insert_subset hzA ((Finset.sdiff_subset).trans hA)).trans
            (allVars_mono (Finset.subset_insert _ _))
        · rw [lhs_mk]; exact huA
        · rw [vset_mk]; exact Finset.insert_subset hzA ((Finset.sdiff_subset).trans hB)
    · split
      · rename_i hf1
        rw [RHS.eqv, Bool.and_eq_true] at hf1
        have hvs1 : r1.abstr.fs = r1.abstr.fs ∩ r2.abstr.fs := by
          rw [← hintfs]
          exact (SSet.eqv_iff_toFinset hn1 (SSet.nodup_inter hn1)).mp hf1.1
        have hc1 : cfs r1.conc = ∅ := cfs_of_eqv_empty hf1.2
        have hg : (⟨u, ⟨(r2.abstr.removedAll (r1.abstr.inter r2.abstr)).incl v, r2.conc⟩,
            some Inference.commonSubexpression⟩ : LPart).toConstraint
            = mk u (insert v (r2.abstr.fs \ (r1.abstr.fs ∩ r2.abstr.fs))) (cfs r2.conc) := by
          rw [toConstraint_eq, SSet.fs_incl, SSet.fs_removedAll, hintfs]
        have hst : CutStep G (foldResult G (mk v r1.abstr.fs (cfs r1.conc))
            (mk u r2.abstr.fs (cfs r2.conc))) :=
          CutStep.fold hpair (by rw [vset_mk, hshared]; exact hvs1) (by rw [conc_mk]; exact hc1)
        rw [foldResult, reduce, hshared, lhs_mk, vset_mk, conc_mk] at hst
        refine ⟨_, Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.cse hst)),
          Finset.subset_insert _ _, ?_, hok, ?_⟩
        · intro p hp
          rw [List.mem_singleton.mp (SSet.mem_ofList hp), hg]
          exact Finset.mem_insert_self _ _
        · refine hfr.mono_allVars (allVars_insert_subset ?_ ?_)
          · rw [lhs_mk]; exact huA
          · rw [vset_mk]; exact Finset.insert_subset hvA ((Finset.sdiff_subset).trans hB)
      · split
        · rename_i hf2
          rw [RHS.eqv, Bool.and_eq_true] at hf2
          have hvs2 : r2.abstr.fs = r2.abstr.fs ∩ r1.abstr.fs := by
            rw [Finset.inter_comm, ← hintfs]
            exact (SSet.eqv_iff_toFinset hn2 (SSet.nodup_inter hn1)).mp hf2.1
          have hc2 : cfs r2.conc = ∅ := cfs_of_eqv_empty hf2.2
          have hg : (⟨v, ⟨(r1.abstr.removedAll (r1.abstr.inter r2.abstr)).incl u, r1.conc⟩,
              some Inference.commonSubexpression⟩ : LPart).toConstraint
              = mk v (insert u (r1.abstr.fs \ (r2.abstr.fs ∩ r1.abstr.fs))) (cfs r1.conc) := by
            rw [toConstraint_eq, SSet.fs_incl, SSet.fs_removedAll, hintfs, Finset.inter_comm]
          have hst : CutStep G (foldResult G (mk u r2.abstr.fs (cfs r2.conc))
              (mk v r1.abstr.fs (cfs r1.conc))) :=
            CutStep.fold hpairS (by rw [vset_mk, hsharedS]; exact hvs2)
              (by rw [conc_mk]; exact hc2)
          rw [foldResult, reduce, hsharedS, lhs_mk, vset_mk, conc_mk] at hst
          refine ⟨_, Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.cse hst)),
            Finset.subset_insert _ _, ?_, hok, ?_⟩
          · intro p hp
            rw [List.mem_singleton.mp (SSet.mem_ofList hp), hg]
            exact Finset.mem_insert_self _ _
          · refine hfr.mono_allVars (allVars_insert_subset ?_ ?_)
            · rw [lhs_mk]; exact hvA
            · rw [vset_mk]; exact Finset.insert_subset huA ((Finset.sdiff_subset).trans hA)
        · split
          · exact RuleRun.empty hok hfr
          · rename_i hcm
            exact absurd hcse (by simpa using hcm)


theorem opt_if_some {b : Bool} {o : Option Nat} {w : Nat}
    (h : (if b = true then o else none) = some w) : o = some w := by
  split at h
  · exact h
  · exact absurd h (by simp)

theorem fs_ofList_singleton (a : Nat) : (SSet.ofList [a]).fs = ({a} : Finset Var) := by
  rw [SSet.fs, ofList_singleton]; simp

/-- **`splitConcrete`** at the shipped flags: syntactic reuse is `SplitReuseStep`, the keyed
reuse is `K2SplitStep.key`, the concrete-row reuse is `K2SplitStep.row`, and the MINT is
`Cut.SplitStep` -- whose only guard, `¬ Named`, is exactly the syntactic lookup missing. -/
theorem splitConcrete_run {G : System} {fl : Flags} {v : Nat} {a : SSet Nat} {c : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hem : fl.emptyRow = false) (hok : SupOk su) (hfr : SupFresh su G) (hna : a.Nodup)
    (hmem : mk v a.fs (cfs c) ∈ G)
    (hsyn : ∀ w, rhss (RHS.ofAbstr a) = some w → _root_.Rowpartition.Names G w a.fs)
    (hsynNone : cfs c ≠ ∅ → 2 ≤ a.fs.card → rhss (RHS.ofAbstr a) = none →
      ¬ _root_.Rowpartition.Named G a.fs)
    (hres : ∀ w, resolvent c = some w → mk v {w} (cfs c) ∈ G)
    (hrow : ∀ w, concRow c = some w →
      ∃ C : Row, mk v ∅ C ∈ G ∧ mk w ∅ (C \ cfs c) ∈ G) :
    ∃ H : System, RuleRun G (splitConcrete fl v a c rhss resolvent concRow emptyRow su).1
      (splitConcrete fl v a c rhss resolvent concRow emptyRow su).2 H := by
  have hAG : a.fs ⊆ allVars G := by have := vset_subset_allVars hmem; rwa [vset_mk] at this
  have hvA : v ∈ allVars G := by have := lhs_mem_allVars hmem; rwa [lhs_mk] at this
  have hempty : cfs (SSet.empty : SSet Lbl) = ∅ := rfl
  simp only [splitConcrete]
  split
  · exact RuleRun.empty hok hfr
  · rename_i hguard
    simp only [Bool.or_eq_true, decide_eq_true_eq, not_or, Nat.not_lt] at hguard
    have hconc_ne : cfs c ≠ ∅ := by
      intro hh
      exact hguard.1 (cfs_eq_empty_iff.mpr hh)
    have htwo : 2 ≤ a.fs.card := by
      have hc := size_eq_card hna
      have h2 := hguard.2
      omega
    split
    · rename_i w hw
      have hn := hsyn w hw
      have hwA : w ∈ allVars G := by
        obtain ⟨d, hd, hdw, -, -⟩ := hn
        exact hdw ▸ lhs_mem_allVars hd
      have hg : (⟨v, ⟨SSet.ofList [w], c⟩, some Inference.splitConcrete⟩ : LPart).toConstraint
          = mk v {w} (cfs c) := by rw [toConstraint_eq, fs_ofList_singleton]
      have hst : SplitReuseStep G (splitReuseResult G (mk v a.fs (cfs c)) w) :=
        SplitReuseStep.intro ⟨hmem, by rw [conc_mk]; exact hconc_ne,
          by rw [vset_mk]; exact htwo, by rw [vset_mk]; exact hn⟩
      rw [splitReuseResult, lhs_mk, conc_mk] at hst
      refine ⟨_, Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.split hst)),
        Finset.subset_insert _ _, ?_, hok, ?_⟩
      · intro p hp
        rw [List.mem_singleton.mp (SSet.mem_ofList hp), hg]
        exact Finset.mem_insert_self _ _
      · refine hfr.mono_allVars (allVars_insert_subset ?_ ?_)
        · rw [lhs_mk]; exact hvA
        · rw [vset_mk]; simpa using hwA
    · rename_i hnone
      have hunnamed := hsynNone hconc_ne htwo hnone
      split
      · exact RuleRun.empty hok hfr
      · split
        · rename_i w hw
          have hwit := hres w (opt_if_some hw)
          have hwA : w ∈ allVars G := by
            have := vset_subset_allVars hwit; rw [vset_mk] at this
            exact Finset.singleton_subset_iff.mp this
          have hg : (⟨w, RHS.ofAbstr a, some Inference.splitKeyed⟩ : LPart).toConstraint
              = mk w a.fs ∅ := rfl
          have hst : K2SplitStep G (kSplitReuseResult G (mk v a.fs (cfs c)) w) :=
            K2SplitStep.key ⟨hmem, by rw [conc_mk]; exact hconc_ne, by rw [vset_mk]; exact htwo,
              by rw [vset_mk]; exact hunnamed, by rw [lhs_mk, conc_mk]; exact hwit⟩
          rw [kSplitReuseResult, vset_mk] at hst
          refine ⟨_, Relation.ReflTransGen.single (LoopRel.split hst),
            Finset.subset_insert _ _, ?_, hok, ?_⟩
          · intro p hp
            rw [List.mem_singleton.mp (SSet.mem_ofList hp), hg]
            exact Finset.mem_insert_self _ _
          · refine hfr.mono_allVars (allVars_insert_subset ?_ ?_)
            · rw [lhs_mk]; exact hwA
            · rw [vset_mk]; exact hAG
        · split
          · rename_i w hw
            obtain ⟨C, hC, hcar⟩ := hrow w (opt_if_some hw)
            have hwA : w ∈ allVars G := by
              have := lhs_mem_allVars hcar; rwa [lhs_mk] at this
            have hg : (⟨w, RHS.ofAbstr a, some Inference.splitRow⟩ : LPart).toConstraint
                = mk w a.fs ∅ := rfl
            have hst : K2SplitStep G (kSplitReuseResult G (mk v a.fs (cfs c)) w) :=
              K2SplitStep.row (C := C) ⟨hmem, by rw [conc_mk]; exact hconc_ne,
                by rw [vset_mk]; exact htwo, by rw [vset_mk]; exact hunnamed,
                by rw [lhs_mk]; exact hC, by rw [conc_mk]; exact hcar⟩
            rw [kSplitReuseResult, vset_mk] at hst
            refine ⟨_, Relation.ReflTransGen.single (LoopRel.split hst),
              Finset.subset_insert _ _, ?_, hok, ?_⟩
            · intro p hp
              rw [List.mem_singleton.mp (SSet.mem_ofList hp), hg]
              exact Finset.mem_insert_self _ _
            · refine hfr.mono_allVars (allVars_insert_subset ?_ ?_)
              · rw [lhs_mk]; exact hwA
              · rw [vset_mk]; exact hAG
          · split
            · rename_i w hw
              rw [hem] at hw
              exact absurd hw (by simp)
            · -- the MINT
              have hfresh : (su.fresh).1 ∉ allVars G := fresh_notMem hok hfr
              have hg1 : (⟨(su.fresh).1, RHS.ofAbstr a, some Inference.splitConcrete⟩
                  : LPart).toConstraint = mk (su.fresh).1 a.fs ∅ := rfl
              have hg2 : (⟨v, ⟨SSet.ofList [(su.fresh).1], c⟩, some Inference.splitConcrete⟩
                  : LPart).toConstraint = mk v {(su.fresh).1} (cfs c) := by
                rw [toConstraint_eq, fs_ofList_singleton]
              have hst : SplitStep G (splitResult G (mk v a.fs (cfs c)) (su.fresh).1) :=
                SplitStep.intro ⟨hmem, by rw [conc_mk]; exact hconc_ne,
                  by rw [vset_mk]; exact htwo, by rw [vset_mk]; exact hunnamed, hfresh⟩
              rw [splitResult, vset_mk, lhs_mk, conc_mk] at hst
              refine ⟨_, Relation.ReflTransGen.single (LoopRel.splitFree hst), ?_, ?_,
                fresh_supOk hok, ?_⟩
              · exact (Finset.subset_insert _ _).trans (Finset.subset_insert _ _)
              · intro p hp
                rcases List.mem_cons.mp (SSet.mem_ofList hp) with rfl | hp'
                · rw [hg1]; exact Finset.mem_insert_self _ _
                · rw [List.mem_singleton] at hp'; subst hp'
                  rw [hg2]; exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
              · refine SupFresh.step hok hfr ?_
                intro w hw
                rw [allVars_insert, allVars_insert] at hw
                simp only [Finset.mem_union, Finset.mem_insert, lhs_mk, vset_mk, conc_mk] at hw
                rcases hw with (rfl | hw') | ((rfl | hw') | hw')
                · exact Or.inr rfl
                · exact Or.inl (hAG hw')
                · exact Or.inl hvA
                · rw [Finset.mem_singleton] at hw'; exact Or.inr hw'
                · exact Or.inl hw'


theorem fs_of_abstrSingle {r : RHS} {x : Nat} (h : r.abstrSingle? = some x) :
    r.abstr.fs = ({x} : Finset Var) := by
  unfold RHS.abstrSingle? SSet.single? at h
  split at h
  · rename_i y hy
    rw [Option.some.injEq] at h
    subst h
    rw [SSet.fs, hy]
    simp
  · exact absurd h (by simp)

/-- **`resolution`** at the shipped flags: the guarded reuse is `K2ResStep.reuse`, the
concrete-row reuse is `K2ResStep.row`, and the MINT is `Cut.ResStep`, whose `ResApp` has no
guard beyond the two premises, the two nonempty differences and freshness. -/
theorem resolution_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {fl : Flags} {v : Nat}
    {r1 r2 : RHS} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hem : fl.emptyRow = false) (hok : SupOk su) (hfr : SupFresh su G)
    (h1L : ∀ x ∈ r1.conc.elems, x ∈ L) (h2L : ∀ x ∈ r2.conc.elems, x ∈ L)
    (h1 : mk v r1.abstr.fs (cfs r1.conc) ∈ G) (h2 : mk v r2.abstr.fs (cfs r2.conc) ∈ G)
    (hres : ∀ w, resolvent (r1.conc.concat r2.conc) = some w →
      mk v {w} (cfs r1.conc ∪ cfs r2.conc) ∈ G)
    (hrow : ∀ w, concRow (r1.conc.concat r2.conc) = some w →
      ∃ F : Row, mk v ∅ F ∈ G ∧ mk w ∅ (F \ (cfs r1.conc ∪ cfs r2.conc)) ∈ G) :
    ∃ H : System, RuleRun G (resolution fl v r1 r2 resolvent concRow emptyRow su).1
      (resolution fl v r1 r2 resolvent concRow emptyRow su).2 H := by
  have hvA : v ∈ allVars G := by have := lhs_mem_allVars h1; rwa [lhs_mk] at this
  have htops : cfs (r1.conc.removedAll (r1.conc.inter r2.conc)) = cfs r1.conc \ cfs r2.conc := by
    rw [cfs_removedAll hcoh h1L (fun x hx => h1L x (SSet.mem_inter hx)), cfs_inter hcoh h1L h2L]
    ext n; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  have hbots : cfs (r2.conc.removedAll (r1.conc.inter r2.conc)) = cfs r2.conc \ cfs r1.conc := by
    rw [cfs_removedAll hcoh h2L (fun x hx => h1L x (SSet.mem_inter hx)), cfs_inter hcoh h1L h2L]
    ext n; simp only [Finset.mem_sdiff, Finset.mem_inter]; tauto
  have hall : cfs (r1.conc.concat r2.conc) = cfs r1.conc ∪ cfs r2.conc := cfs_concat _ _
  simp only [resolution]
  split
  · exact RuleRun.empty hok hfr
  · split
    · rename_i x y hx hy
      have hfsx : r1.abstr.fs = ({x} : Finset Var) := fs_of_abstrSingle hx
      have hfsy : r2.abstr.fs = ({y} : Finset Var) := fs_of_abstrSingle hy
      have hxA : x ∈ allVars G := by
        have := vset_subset_allVars h1; rw [vset_mk, hfsx] at this
        exact Finset.singleton_subset_iff.mp this
      have hyA : y ∈ allVars G := by
        have := vset_subset_allVars h2; rw [vset_mk, hfsy] at this
        exact Finset.singleton_subset_iff.mp this
      have hm1 : mk v {x} (cfs r1.conc) ∈ G := by rwa [hfsx] at h1
      have hm2 : mk v {y} (cfs r2.conc) ∈ G := by rwa [hfsy] at h2
      split
      · -- `tops` or `bots` empty: no conclusion, but the id was drawn
        refine ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G,
          (by intro p hp; cases hp), fresh_supOk hok, ?_⟩
        exact SupFresh.step hok hfr (fun w hw => Or.inl hw)
      · rename_i hne
        simp only [Bool.or_eq_true, not_or] at hne
        have hpair : ResPair G v x y (cfs r1.conc) (cfs r2.conc) := by
          refine ⟨hm1, hm2, ?_, ?_⟩
          · intro hh
            exact hne.1 (cfs_eq_empty_iff.mpr (by rw [htops]; exact hh))
          · intro hh
            exact hne.2 (cfs_eq_empty_iff.mpr (by rw [hbots]; exact hh))
        have hgx : ∀ (w : Nat) (i : Option Inference),
            (⟨x, ⟨SSet.ofList [w], r2.conc.removedAll (r1.conc.inter r2.conc)⟩, i⟩
              : LPart).toConstraint = mk x {w} (cfs r2.conc \ cfs r1.conc) := by
          intro w i; rw [toConstraint_eq, fs_ofList_singleton, hbots]
        have hgy : ∀ (w : Nat) (i : Option Inference),
            (⟨y, ⟨SSet.ofList [w], r1.conc.removedAll (r1.conc.inter r2.conc)⟩, i⟩
              : LPart).toConstraint = mk y {w} (cfs r1.conc \ cfs r2.conc) := by
          intro w i; rw [toConstraint_eq, fs_ofList_singleton, htops]
        split
        · rename_i w hw
          have hwit := hres w (opt_if_some hw)
          have hwA : w ∈ allVars G := by
            have := vset_subset_allVars hwit; rw [vset_mk] at this
            exact Finset.singleton_subset_iff.mp this
          have hst : K2ResStep G (resReuseResult G x y (cfs r1.conc) (cfs r2.conc) w) :=
            K2ResStep.reuse hpair hwit
          rw [resReuseResult] at hst
          refine ⟨_, Relation.ReflTransGen.single (LoopRel.kres hst),
            (Finset.subset_insert _ _).trans (Finset.subset_insert _ _), ?_,
            fresh_supOk hok, ?_⟩
          · intro p hp
            rcases List.mem_cons.mp (SSet.mem_ofList hp) with rfl | hp'
            · rw [hgx]; exact Finset.mem_insert_self _ _
            · rw [List.mem_singleton] at hp'; subst hp'
              rw [hgy]; exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
          · refine SupFresh.step hok hfr ?_
            intro w0 hw0
            rw [allVars_insert, allVars_insert] at hw0
            simp only [Finset.mem_union, Finset.mem_insert, lhs_mk, vset_mk,
              Finset.mem_singleton] at hw0
            rcases hw0 with (rfl | rfl) | ((rfl | rfl) | hw0')
            · exact Or.inl hxA
            · exact Or.inl hwA
            · exact Or.inl hyA
            · exact Or.inl hwA
            · exact Or.inl hw0'
        · split
          · rename_i w hw
            obtain ⟨F, hF, hcar⟩ := hrow w (opt_if_some hw)
            have hwA : w ∈ allVars G := by
              have := lhs_mem_allVars hcar; rwa [lhs_mk] at this
            have hst : K2ResStep G (resReuseResult G x y (cfs r1.conc) (cfs r2.conc) w) :=
              K2ResStep.row hpair hF hcar
            rw [resReuseResult] at hst
            refine ⟨_, Relation.ReflTransGen.single (LoopRel.kres hst),
              (Finset.subset_insert _ _).trans (Finset.subset_insert _ _), ?_,
              fresh_supOk hok, ?_⟩
            · intro p hp
              rcases List.mem_cons.mp (SSet.mem_ofList hp) with rfl | hp'
              · rw [hgx]; exact Finset.mem_insert_self _ _
              · rw [List.mem_singleton] at hp'; subst hp'
                rw [hgy]; exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
            · refine SupFresh.step hok hfr ?_
              intro w0 hw0
              rw [allVars_insert, allVars_insert] at hw0
              simp only [Finset.mem_union, Finset.mem_insert, lhs_mk, vset_mk,
                Finset.mem_singleton] at hw0
              rcases hw0 with (rfl | rfl) | ((rfl | rfl) | hw0')
              · exact Or.inl hxA
              · exact Or.inl hwA
              · exact Or.inl hyA
              · exact Or.inl hwA
              · exact Or.inl hw0'
          · split
            · rename_i w hw
              rw [hem] at hw
              exact absurd hw (by simp)
            · -- the MINT
              have hfresh : (su.fresh).1 ∉ allVars G := fresh_notMem hok hfr
              have hgv : (⟨v, ⟨SSet.ofList [(su.fresh).1], r1.conc.concat r2.conc⟩,
                  some Inference.resolution⟩ : LPart).toConstraint
                  = mk v {(su.fresh).1} (cfs r1.conc ∪ cfs r2.conc) := by
                rw [toConstraint_eq, fs_ofList_singleton, hall]
              have hst : ResStep G
                  (resResult G v x y (cfs r1.conc) (cfs r2.conc) (su.fresh).1) :=
                ResStep.intro ⟨hpair.mem₁, hpair.mem₂, hpair.tops, hpair.bots, hfresh⟩
              rw [resResult] at hst
              refine ⟨_, Relation.ReflTransGen.single (LoopRel.res hst), ?_, ?_,
                fresh_supOk hok, ?_⟩
              · exact ((Finset.subset_insert _ _).trans (Finset.subset_insert _ _)).trans
                  (Finset.subset_insert _ _)
              · intro p hp
                rcases List.mem_cons.mp (SSet.mem_ofList hp) with rfl | hp'
                · rw [hgv]; exact Finset.mem_insert_self _ _
                · rcases List.mem_cons.mp hp' with rfl | hp''
                  · rw [hgx]
                    exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
                  · rw [List.mem_singleton] at hp''; subst hp''
                    rw [hgy]
                    exact Finset.mem_insert_of_mem (Finset.mem_insert_of_mem
                      (Finset.mem_insert_self _ _))
              · refine SupFresh.step hok hfr ?_
                intro w0 hw0
                rw [allVars_insert, allVars_insert, allVars_insert] at hw0
                simp only [Finset.mem_union, Finset.mem_insert, lhs_mk, vset_mk,
                  Finset.mem_singleton] at hw0
                rcases hw0 with (rfl | rfl) | ((rfl | rfl) | ((rfl | rfl) | hw0'))
                · exact Or.inl hvA
                · exact Or.inr rfl
                · exact Or.inl hxA
                · exact Or.inr rfl
                · exact Or.inl hyA
                · exact Or.inr rfl
                · exact Or.inl hw0'
    · exact RuleRun.empty hok hfr


/-! ## 4. The three reverse lookups are SOUND: what they find is really in the system -/

theorem findRHS3_witness {ps cs : PQueue} {S : SSet LPart} {r : RHS} {w : Nat}
    (h : findRHS3 ps cs S r = some w) :
    ∃ p, (p ∈ ps.elems ∨ p ∈ cs.elems ∨ p ∈ S.elems) ∧ p.rhs.eqv r = true ∧ p.lhs = w := by
  simp only [findRHS3] at h
  split at h
  · rename_i u hu
    obtain ⟨p, hp, he, hl⟩ := findRHS_witness hu
    rw [Option.some.injEq] at h
    exact ⟨p, Or.inr (Or.inl hp), he, by rw [hl, h]⟩
  · split at h
    · rename_i u hu
      obtain ⟨p, hp, he, hl⟩ := findRHS_witness hu
      rw [Option.some.injEq] at h
      exact ⟨p, Or.inl hp, he, by rw [hl, h]⟩
    · cases hf : S.elems.find? (fun p => p.rhs.eqv r) with
      | none => rw [hf] at h; exact absurd h (by simp)
      | some p =>
        rw [hf] at h
        simp only [Option.map_some, Option.some.injEq] at h
        exact ⟨p, Or.inr (Or.inr (List.mem_of_find?_eq_some hf)),
          by simpa using List.find?_some hf, h⟩

theorem findRHS_none {q : PQueue} {r : RHS} (h : q.findRHS r = none) :
    ∀ p ∈ q.elems, p.rhs.eqv r = false := by
  intro p hp
  unfold PQueue.findRHS at h
  cases hf : q.elems.find? (fun x => x.rhs.eqv r) with
  | none => simpa using List.find?_eq_none.mp hf p hp
  | some z => rw [hf] at h; exact absurd h (by simp)

theorem findRHS3_none {ps cs : PQueue} {S : SSet LPart} {r : RHS}
    (h : findRHS3 ps cs S r = none) :
    ∀ p, (p ∈ ps.elems ∨ p ∈ cs.elems ∨ p ∈ S.elems) → p.rhs.eqv r = false := by
  simp only [findRHS3] at h
  split at h
  · exact absurd h (by simp)
  · rename_i hcs
    split at h
    · exact absurd h (by simp)
    · rename_i hps
      intro p hp
      rcases hp with hp' | hp' | hp'
      · exact findRHS_none hps p hp'
      · exact findRHS_none hcs p hp'
      · cases hf : S.elems.find? (fun x => x.rhs.eqv r) with
        | none => simpa using List.find?_eq_none.mp hf p hp'
        | some z => rw [hf] at h; exact absurd h (by simp)

theorem flGet_witness {m : List (SSet Lbl × Nat)} {k : SSet Lbl} {w : Nat}
    (h : flGet m k = some w) : ∃ kv ∈ m, kv.1.eqv k = true ∧ kv.2 = w := by
  unfold flGet at h
  cases hf : m.find? (fun p => p.1.eqv k) with
  | none => rw [hf] at h; exact absurd h (by simp)
  | some kv =>
    rw [hf] at h
    simp only [Option.map_some, Option.some.injEq] at h
    exact ⟨kv, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf, h⟩

/-- What `mkLookups` maintains: every entry of either map, and the recorded own row, comes
from a partition of the two queues. -/
structure LookupsOk (Q : List LPart) (v : Nat) (l : Lookups) : Prop where
  res : ∀ kv ∈ l.resolvents, ∃ p ∈ Q, p.lhs = v ∧ p.rhs.abstrSingle? = some kv.2 ∧
    p.rhs.conc = kv.1
  rows : ∀ kv ∈ l.rows, ∃ p ∈ Q, p.lhs = kv.2 ∧ p.rhs.abstr.isEmpty = true ∧ p.rhs.conc = kv.1
  myRow : ∀ c, l.myRow = some c → ∃ p ∈ Q, p.lhs = v ∧ p.rhs.abstr.isEmpty = true ∧
    p.rhs.conc = c

theorem mem_flPut {m : List (SSet Lbl × Nat)} {k : SSet Lbl} {w : Nat} {kv : SSet Lbl × Nat}
    (h : kv ∈ flPut m k w) : kv ∈ m ∨ kv = (k, w) := by
  unfold flPut at h
  split at h
  · obtain ⟨q, hq, rfl⟩ := List.mem_map.mp h
    split
    · exact Or.inr rfl
    · exact Or.inl hq
  · rcases List.mem_append.mp h with h' | h'
    · exact Or.inl h'
    · exact Or.inr (by simpa using h')

theorem mkLookups_ok (v : Nat) (incm proc : PQueue) :
    LookupsOk (proc.elems ++ incm.elems) v (mkLookups v incm proc) := by
  have hstep : ∀ (l : Lookups) (p : LPart), p ∈ proc.elems ++ incm.elems →
      LookupsOk (proc.elems ++ incm.elems) v l →
      LookupsOk (proc.elems ++ incm.elems) v
        (let l' := match p.rhs.abstrSingle? with
          | some w => if p.lhs == v then { l with resolvents := flPut l.resolvents p.rhs.conc w }
                      else l
          | none => l
        if p.rhs.abstr.isEmpty then
          { l' with rows := flPut l'.rows p.rhs.conc p.lhs,
                    myRow := if p.lhs == v then some p.rhs.conc else l'.myRow }
        else l') := by
    intro l p hp hl
    have hl' : LookupsOk (proc.elems ++ incm.elems) v
        (match p.rhs.abstrSingle? with
          | some w => if p.lhs == v then { l with resolvents := flPut l.resolvents p.rhs.conc w }
                      else l
          | none => l) := by
      split
      · rename_i w hw
        split
        · rename_i hlhs
          refine ⟨?_, hl.rows, hl.myRow⟩
          intro kv hkv
          rcases mem_flPut hkv with hkv' | rfl
          · exact hl.res kv hkv'
          · exact ⟨p, hp, by simpa using hlhs, hw, rfl⟩
        · exact hl
      · exact hl
    set l0 := (match p.rhs.abstrSingle? with
      | some w => if p.lhs == v then { l with resolvents := flPut l.resolvents p.rhs.conc w }
                  else l
      | none => l) with hl0
    show LookupsOk (proc.elems ++ incm.elems) v
      (if p.rhs.abstr.isEmpty then
        { l0 with rows := flPut l0.rows p.rhs.conc p.lhs,
                  myRow := if p.lhs == v then some p.rhs.conc else l0.myRow }
      else l0)
    split
    · rename_i hab
      refine ⟨hl'.res, ?_, ?_⟩
      · intro kv hkv
        rcases mem_flPut hkv with hkv' | rfl
        · exact hl'.rows kv hkv'
        · exact ⟨p, hp, rfl, hab, rfl⟩
      · intro c hc
        split at hc
        · rename_i hlhs
          rw [Option.some.injEq] at hc
          exact ⟨p, hp, by simpa using hlhs, hab, hc⟩
        · exact hl'.myRow c hc
    · exact hl'
  simp only [mkLookups]
  refine foldl_inv (P := LookupsOk (proc.elems ++ incm.elems) v)
    (Q := fun p => p ∈ proc.elems ++ incm.elems)
    (fun l p hp hl => hstep l p hp hl) _ (fun p hp => List.mem_append_right _ hp) _ ?_
  exact foldl_inv (P := LookupsOk (proc.elems ++ incm.elems) v)
    (Q := fun p => p ∈ proc.elems ++ incm.elems)
    (fun l p hp hl => hstep l p hp hl) _ (fun p hp => List.mem_append_left _ hp) _
    ⟨by simp, by simp, by simp⟩


theorem findSome?_mem {α β : Type} {f : α → Option β} :
    ∀ {l : List α} {b : β}, l.findSome? f = some b → ∃ a ∈ l, f a = some b
  | [], _, h => by simp [List.findSome?] at h
  | x :: t, b, h => by
    simp only [List.findSome?] at h
    cases hx : f x with
    | none =>
      rw [hx] at h
      obtain ⟨a, ha, hfa⟩ := findSome?_mem h
      exact ⟨a, by simp [ha], hfa⟩
    | some y =>
      rw [hx] at h
      simp only [Option.some.injEq] at h
      exact ⟨x, by simp, by rw [hx, h]⟩

theorem cfs_congr {L : List Lbl} (hcoh : LblCoh L) {c1 c2 : SSet Lbl} (h1 : COk L c1)
    (h2 : COk L c2) (h : c1.eqv c2 = true) : cfs c1 = cfs c2 := by
  have hfin : c1.elems.toFinset = c2.elems.toFinset :=
    (SSet.eqv_iff_toFinset h1.nodup h2.nodup).mp h
  have := (toFinset_map_n_iff (l := c1.elems) (m := c2.elems)
    (hcoh.mono (by
      intro x hx
      rcases List.mem_append.mp hx with hx' | hx'
      · exact h1.sub x hx'
      · exact h2.sub x hx'))).mpr hfin
  exact this

/-- The SYNTACTIC reverse lookup: what it finds NAMES the group. -/
theorem findRHS3_names {L : List Lbl} (hcoh : LblCoh L) {ps cs : PQueue} {S : SSet LPart}
    {a : SSet Nat} {w : Nat} {H : System} (hna : a.Nodup)
    (hQ : ∀ p, (p ∈ ps.elems ∨ p ∈ cs.elems ∨ p ∈ S.elems) → POk L p ∧ p.toConstraint ∈ H)
    (h : findRHS3 ps cs S (RHS.ofAbstr a) = some w) :
    _root_.Rowpartition.Names H w a.fs := by
  obtain ⟨p, hp, he, hl⟩ := findRHS3_witness h
  obtain ⟨hpok, hpH⟩ := hQ p hp
  have hc : p.toConstraint = (⟨p.lhs, RHS.ofAbstr a, none⟩ : LPart).toConstraint :=
    toConstraint_congr (q := (⟨0, RHS.ofAbstr a, none⟩ : LPart)) hcoh hpok
      ⟨hna, COk.empty⟩ he
  refine ⟨p.toConstraint, hpH, ?_, ?_, ?_⟩
  · rw [LPart.lhs_toConstraint, hl]
  · rw [hc]
    show vset (mk p.lhs (RHS.ofAbstr a).abstr.fs (cfs (RHS.ofAbstr a).conc)) = a.fs
    rw [vset_mk]
    rfl
  · rw [hc]
    show (mk p.lhs (RHS.ofAbstr a).abstr.fs (cfs (RHS.ofAbstr a).conc)).conc = ∅
    rw [conc_mk]
    rfl

/-- The KEYED reverse lookup: what it finds is a lone-variable definition of `v`. -/
theorem findResolvent_sound {L : List Lbl} (hcoh : LblCoh L) {v : Nat} {l : Lookups}
    {S : SSet LPart} {k : SSet Lbl} {w : Nat} {H : System} {Q : List LPart}
    (hlk : LookupsOk Q v l) (hQ : ∀ p ∈ Q, POk L p ∧ p.toConstraint ∈ H)
    (hS : ∀ p ∈ S.elems, POk L p ∧ p.toConstraint ∈ H) (hk : COk L k)
    (h : findResolvent v l S k = some w) : mk v {w} (cfs k) ∈ H := by
  have hmk : ∀ p : LPart, POk L p → p.toConstraint ∈ H → p.lhs = v →
      p.rhs.abstrSingle? = some w → p.rhs.conc.eqv k = true → mk v {w} (cfs k) ∈ H := by
    intro p hpok hpH hlhs hsing heq
    have h1 : p.toConstraint = mk v {w} (cfs p.rhs.conc) := by
      rw [toConstraint_eq, hlhs, fs_of_abstrSingle hsing]
    rw [h1, cfs_congr hcoh hpok.conc hk heq] at hpH
    exact hpH
  simp only [findResolvent] at h
  split at h
  · rename_i w0 hw0
    rw [Option.some.injEq] at h
    subst h
    obtain ⟨p, hp, hfp⟩ := findSome?_mem hw0
    split at hfp
    · rename_i w1 hw1
      split at hfp
      · rename_i hg
        rw [Option.some.injEq] at hfp
        subst hfp
        rw [Bool.and_eq_true] at hg
        obtain ⟨hpok, hpH⟩ := hS p hp
        exact hmk p hpok hpH (by simpa using hg.1) hw1 hg.2
      · exact absurd hfp (by simp)
    · exact absurd hfp (by simp)
  · obtain ⟨kv, hkv, hkeq, rfl⟩ := flGet_witness h
    obtain ⟨p, hp, hlhs, hsing, hconc⟩ := hlk.res kv hkv
    obtain ⟨hpok, hpH⟩ := hQ p hp
    exact hmk p hpok hpH hlhs hsing (by rw [hconc]; exact hkeq)


theorem fs_of_isEmpty {α : Type} [SVal α] [DecidableEq α] {s : SSet α} (h : s.isEmpty = true) :
    s.fs = ∅ := by
  have : s.elems = [] := by simpa [SSet.isEmpty] using h
  simp [SSet.fs, this]

/-- The CONCRETE-ROW reverse lookup: what it finds is a carrier of the complement row. -/
theorem findConcRow_sound {L : List Lbl} (hcoh : LblCoh L) {v : Nat} {l : Lookups}
    {k : SSet Lbl} {w : Nat} {H : System} {Q : List LPart}
    (hlk : LookupsOk Q v l) (hQ : ∀ p ∈ Q, POk L p ∧ p.toConstraint ∈ H) (hk : COk L k)
    (h : findConcRow l k = some w) :
    ∃ C : Row, mk v ∅ C ∈ H ∧ mk w ∅ (C \ cfs k) ∈ H := by
  simp only [findConcRow] at h
  split at h
  · exact absurd h (by simp)
  · rename_i c hc
    split at h
    · obtain ⟨kv, hkv, hkeq, rfl⟩ := flGet_witness h
      obtain ⟨p, hp, hlhs, hab, hconc⟩ := hlk.myRow c hc
      obtain ⟨hpok, hpH⟩ := hQ p hp
      obtain ⟨q, hq, hqlhs, hqab, hqconc⟩ := hlk.rows kv hkv
      obtain ⟨hqok, hqH⟩ := hQ q hq
      have hcOk : COk L c := hconc ▸ hpok.conc
      refine ⟨cfs c, ?_, ?_⟩
      · have hpc : p.toConstraint = mk v ∅ (cfs c) := by
          rw [toConstraint_eq, hlhs, hconc, fs_of_isEmpty hab]
        rw [← hpc]; exact hpH
      · have hqc : q.toConstraint = mk kv.2 ∅ (cfs (c.removedAll k)) := by
          rw [toConstraint_eq, hqlhs, fs_of_isEmpty hqab]
          congr 1
          exact cfs_congr hcoh hqok.conc (hcOk.removedAll k) (by rw [hqconc]; exact hkeq)
        rw [cfs_removedAll hcoh hcOk.sub hk.sub] at hqc
        rw [← hqc]; exact hqH
    · exact absurd h (by simp)

/-! ## 5. `learnPartitions` -/

/-- **The `learn` batch is a run of `LoopRel`.**  Every partition `learnPartitions` derives is
a `LoopRel`-consequence of the system the state denotes, at the shipped flags. -/
theorem learnPartitions_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {fl : Flags}
    {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup}
    {S : SSet LPart} {su' : Sup}
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hok : SupOk su) (hfr : SupFresh su G)
    (hpOk : QOk L proc) (hiOk : QOk L incm) (hrOk : ROk L rhs1)
    (hpG : ∀ p ∈ proc.elems, p.toConstraint ∈ G) (hiG : ∀ p ∈ incm.elems, p.toConstraint ∈ G)
    (hrG : mk v rhs1.abstr.fs (cfs rhs1.conc) ∈ G)
    (hunnamed : cfs rhs1.conc ≠ ∅ → 2 ≤ rhs1.abstr.fs.card →
      findRHS3 incm proc SSet.empty (RHS.ofAbstr rhs1.abstr) = none →
      ¬ _root_.Rowpartition.Named G rhs1.abstr.fs)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∃ H : System, RuleRun G S su' H := by
  have hAG : rhs1.abstr.fs ⊆ allVars G := by
    have := vset_subset_allVars hrG; rwa [vset_mk] at this
  have hQall : ∀ p ∈ proc.elems ++ incm.elems, POk L p ∧ p.toConstraint ∈ G := by
    intro p hp
    rcases List.mem_append.mp hp with hp' | hp'
    · exact ⟨hpOk p hp', hpG p hp'⟩
    · exact ⟨hiOk p hp', hiG p hp'⟩
  simp only [learnPartitions] at h
  split at h
  · -- `selfSubstitution`
    rename_i hself
    cases hss : selfSubstitution ns v rhs1.abstr rhs1.conc with
    | error m => rw [hss] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok T =>
      rw [hss] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      have hv : v ∈ rhs1.abstr.fs :=
        List.mem_toFinset.mpr ((SSet.contains_iff rhs1.abstr v).mp hself)
      refine RuleRun.ofAdds hok hfr (selfSubstitution_run hrG hv hss) ?_ ?_
      · intro p hp
        simp only [selfSubstitution] at hss
        split at hss
        · rw [Except.ok.injEq] at hss
          subst hss
          obtain ⟨u, hu, rfl⟩ := SSet.mem_map hp
          exact hAG (List.mem_toFinset.mpr (SSet.mem_excl_iff.mp hu).1)
        · exact absurd hss (by simp)
      · intro p hp
        simp only [selfSubstitution] at hss
        split at hss
        · rw [Except.ok.injEq] at hss
          subst hss
          obtain ⟨u, hu, rfl⟩ := SSet.mem_map hp
          simp [toConstraint_eq, SSet.fs, RHS.empty, SSet.empty]
        · exact absurd hss (by simp)
  · -- the general case
    set l := mkLookups v incm proc with hlDef
    have hlkOk : LookupsOk (proc.elems ++ incm.elems) v l := mkLookups_ok v incm proc
    -- the concrete-row lookup, once
    have hrowSound : ∀ (Hx : System) (k : SSet Lbl) (w : Nat), COk L k →
        (∀ p ∈ proc.elems ++ incm.elems, POk L p ∧ p.toConstraint ∈ Hx) →
        (if fl.splitRow || fl.resRow then findConcRow l k else none) = some w →
        ∃ C : Row, mk v ∅ C ∈ Hx ∧ mk w ∅ (C \ cfs k) ∈ Hx := by
      intro Hx k w hk hQ hw
      exact findConcRow_sound hcoh hlkOk hQ hk (opt_if_some hw)
    have hresSound : ∀ (Hx : System) (B : SSet LPart) (k : SSet Lbl) (w : Nat), COk L k →
        (∀ p ∈ proc.elems ++ incm.elems, POk L p ∧ p.toConstraint ∈ Hx) →
        (∀ p ∈ B.elems, POk L p ∧ p.toConstraint ∈ Hx) →
        findResolvent v l B k = some w → mk v {w} (cfs k) ∈ Hx := by
      intro Hx B k w hk hQ hB hw
      exact findResolvent_sound hcoh hlkOk hQ hB hk hw
    refine (foldl_except_inv
      (P := fun (x : SSet LPart × Sup) => SOk L x.1 ∧ ∃ H : System, RuleRun G x.1 x.2 H)
      (Q := fun p => p ∈ proc.elems) ?_ _ (fun p hp => hp) _ ?_ _ h).2
    · -- ONE step of the fold
      intro acc p2 hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok x =>
        obtain ⟨hSOk, H, hrunH, hsubH, hmH, hokH, hfrH⟩ := hacc x hacc'
        have hQH : ∀ p ∈ proc.elems ++ incm.elems, POk L p ∧ p.toConstraint ∈ H :=
          fun p hp => ⟨(hQall p hp).1, hsubH (hQall p hp).2⟩
        have hBH : ∀ p ∈ x.1.elems, POk L p ∧ p.toConstraint ∈ H :=
          fun p hp => ⟨hSOk p hp, hmH p hp⟩
        have hrGH : mk v rhs1.abstr.fs (cfs rhs1.conc) ∈ H := hsubH hrG
        have hp2H : p2.toConstraint ∈ H := hsubH (hpG p2 hp2)
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · -- `u == v`: resolution and cancellation
          rename_i hu
          have hup2 : p2.lhs = v := by simpa using hu
          have hp2c : mk v p2.rhs.abstr.fs (cfs p2.rhs.conc) ∈ H := by
            rw [← hup2, ← toConstraint_eq]; exact hp2H
          have hallC : COk L (rhs1.conc.concat p2.rhs.conc) :=
            hrOk.conc.concat (hpOk p2 hp2).conc
          obtain ⟨H1, hrun1, hsub1, hm1, hok1, hfr1⟩ := resolution_run hcoh (fl := fl)
            (resolvent := fun k => findResolvent v l x.1 k)
            (concRow := fun k => if fl.splitRow || fl.resRow then findConcRow l k else none)
            (emptyRow := fun k => if fl.emptyRow then findEmptyRow env l k else none)
            hem hokH hfrH hrOk.conc.sub (hpOk p2 hp2).conc.sub hrGH hp2c
            (fun w hw => by
              have := hresSound H x.1 _ w hallC hQH hBH hw
              rwa [cfs_concat] at this)
            (fun w hw => by
              obtain ⟨C, hC, hcar⟩ := hrowSound H _ w hallC hQH hw
              exact ⟨C, hC, by rwa [cfs_concat] at hcar⟩)
          obtain ⟨H2, hrun2, hsub2, hm2, hok2, hfr2⟩ :=
            RuleRun.ofAdds hok1 hfr1
              (cancellationG_run hcoh hrOk.conc.sub (hpOk p2 hp2).conc.sub
                (hsub1 hrGH) (hsub1 hp2c))
              (by
                intro p hp
                rcases (cancellation_vars p hp).1 with hh | hh
                · exact allVars_mono (hsubH.trans hsub1) (hAG hh)
                · refine allVars_mono (hsubH.trans hsub1) ?_
                  have := vset_subset_allVars (hpG p2 hp2)
                  rw [toConstraint_eq, vset_mk] at this
                  exact this hh)
              (by
                intro p hp
                refine (cancellation_vars p hp).2.trans ?_
                refine Finset.union_subset ?_ ?_
                · exact hAG.trans (allVars_mono (hsubH.trans hsub1))
                · have := vset_subset_allVars (hpG p2 hp2)
                  rw [toConstraint_eq, vset_mk] at this
                  exact this.trans (allVars_mono (hsubH.trans hsub1)))
          rw [hdj] at hb
          simp only [Bool.not_false] at hb
          rw [if_pos trivial] at hb
          simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          refine ⟨?_, H2, hrunH.trans (hrun1.trans hrun2), ?_, ?_, hok2, hfr2⟩
          · refine SOk.concat (SOk.concat (SOk.concat hSOk
              (resolution_ok hrOk (hpOk p2 hp2).rhsOk _ _ _ _))
              (cancellation_ok hrOk (hpOk p2 hp2).rhsOk)) SOk.empty
          · exact (hsubH.trans hsub1).trans hsub2
          · intro p hp
            rcases SSet.mem_concat hp with hp' | hp'
            · rcases SSet.mem_concat hp' with hp'' | hp''
              · rcases SSet.mem_concat hp'' with hp3 | hp3
                · exact hsub2 (hsub1 (hmH p hp3))
                · exact hsub2 (hm1 p hp3)
              · exact hm2 p hp''
            · cases hp'
        · -- `u ≠ v`: common subexpression and substitution
          rename_i hu
          have hup2 : p2.lhs ≠ v := by simpa using hu
          have hp2c : mk p2.lhs p2.rhs.abstr.fs (cfs p2.rhs.conc) ∈ H := by
            rw [← toConstraint_eq]; exact hp2H
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m =>
            rw [hsub] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
          | ok T =>
            rw [hsub] at hb
            obtain ⟨H1, hrun1, hsub1, hm1, hok1, hfr1⟩ := commonSubexpression_run
              (fl := fl) (rhss := fun r => findRHS3 incm proc x.1 r)
              hcse hokH hfrH (fun hh => hup2 hh.symm) hrOk.abstr (hpOk p2 hp2).abstr
              hrGH hp2c
              (fun z hz => by
                have := findRHS3_names hcoh (SSet.nodup_inter hrOk.abstr)
                  (H := H) (a := rhs1.abstr.inter p2.rhs.abstr)
                  (by
                    intro p hp
                    rcases hp with hp' | hp' | hp'
                    · exact hQH p (List.mem_append_right _ hp')
                    · exact hQH p (List.mem_append_left _ hp')
                    · exact hBH p hp') hz
                rwa [SSet.fs_inter] at this)
            obtain ⟨H2, hrun2, hsub2, hm2, hok2, hfr2⟩ :=
              substitution_run hok1 hfr1 (hsub1 hrGH) (hsub1 hp2c) hsub
            rw [hdj] at hb
            simp only [Bool.not_false] at hb
            rw [if_pos trivial] at hb
            simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            rw [commonSubexpression_su hcse]
            refine ⟨?_, H2, hrunH.trans (hrun1.trans hrun2), ?_, ?_, hok2, hfr2⟩
            · refine SOk.concat (SOk.concat (SOk.concat hSOk
                (commonSubexpression_ok hrOk (hpOk p2 hp2).rhsOk _ _))
                (substitution_ok hrOk (hpOk p2 hp2).rhsOk hsub)) SOk.empty
            · exact (hsubH.trans hsub1).trans hsub2
            · intro p hp
              rcases SSet.mem_concat hp with hp' | hp'
              · rcases SSet.mem_concat hp' with hp'' | hp''
                · rcases SSet.mem_concat hp'' with hp3 | hp3
                  · exact hsub2 (hsub1 (hmH p hp3))
                  · exact hsub2 (hm1 p hp3)
                · exact hm2 p hp''
              · cases hp'
    · -- the fold's INITIAL value: `splitConcrete`
      intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      refine ⟨splitConcrete_ok hrOk.abstr hrOk.conc _ _ _ _ _, ?_⟩
      exact splitConcrete_run (fl := fl) hem hok hfr hrOk.abstr hrG
        (fun w hw => findRHS3_names hcoh hrOk.abstr
          (by
            intro p hp
            rcases hp with hp' | hp' | hp'
            · exact hQall p (List.mem_append_right _ hp')
            · exact hQall p (List.mem_append_left _ hp')
            · cases hp') hw)
        hunnamed
        (fun w hw => hresSound G SSet.empty _ w hrOk.conc hQall (by intro p hp; cases hp) hw)
        (fun w hw => hrowSound G _ w hrOk.conc hQall hw)


/-! ## 6. The `learn` dispatch branch -/

/-- The `learn` records the general branch writes touch the TRACE and nothing else. -/
theorem foldl_log_env (f : State → LPart → String) :
    ∀ (l : List LPart) (st : State),
      (l.foldl (fun a p => ({ a with trace := f a p :: a.trace } : State)) st).env = st.env
  | [], _ => rfl
  | p :: l, st => foldl_log_env f l { st with trace := f st p :: st.trace }

theorem foldl_log_flags (f : State → LPart → String) :
    ∀ (l : List LPart) (st : State),
      (l.foldl (fun a p => ({ a with trace := f a p :: a.trace } : State)) st).flags = st.flags
  | [], _ => rfl
  | p :: l, st => foldl_log_flags f l { st with trace := f st p :: st.trace }


theorem mem_eraseIdx_or {α : Type} : ∀ (l : List α) (i : Nat) (x : α), x ∈ l →
    x ∈ l.eraseIdx i ∨ l[i]? = some x
  | [], _, _, h => by cases h
  | a :: t, 0, x, h => by
    rcases List.mem_cons.mp h with rfl | h'
    · exact Or.inr rfl
    · exact Or.inl (by simpa using h')
  | a :: t, j + 1, x, h => by
    rcases List.mem_cons.mp h with rfl | h'
    · exact Or.inl (by simp)
    · rcases mem_eraseIdx_or t j x h' with hh | hh
      · exact Or.inl (by simp [hh])
      · exact Or.inr (by simpa using hh)

theorem dequeue_mem_or {q : PQueue} {r : LPart} {rest : PQueue}
    (hd : q.dequeue = some (r, rest)) : ∀ x ∈ q.elems, x ∈ rest.elems ∨ x = r := by
  simp only [PQueue.dequeue] at hd
  split at hd
  · exact absurd hd (by simp)
  · rename_i e0 rest0 he
    split at hd
    · exact absurd hd (by simp)
    · rename_i i hi
      split at hd
      · exact absurd hd (by simp)
      · rename_i p hp
        rw [Option.some_inj, Prod.mk.injEq] at hd
        obtain ⟨rfl, hrest⟩ := hd
        intro x hx
        rw [he] at hx
        rcases mem_eraseIdx_or (e0 :: rest0) i x hx with hh | hh
        · exact Or.inl (by rw [← hrest]; exact hh)
        · exact Or.inr (by rw [hp] at hh; exact (Option.some.injEq _ _ ▸ hh).symm ▸ rfl)

/-- **Refinement of the `learn` branch.**  At the shipped flags, and with the supply
invariant, every `learn` step is a run of `LoopRel`. -/
theorem step_refines_learn {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (hb : ¬ NonLearnStep s) (h : step s = .continue s') : LoopRun (sys s) (sys s') := by
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
    obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
    have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_incm (hrestMem x hx)
    have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_proc hx
    have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s :=
      fun b hb' => mem_sys_of_env hb'
    have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
    -- the branch conditions
    have hfr0 : s.proc.findRHS r.rhs = none := by
      cases hh : s.proc.findRHS r.rhs with
      | none => rfl
      | some u =>
        exact absurd (fun r0 rest0 hd0 => Or.inl (by
          rw [dequeue_unique hdq hd0, hh]; rfl)) hb
    have hne : r.rhs.isEmpty = false := by
      cases hh : r.rhs.isEmpty with
      | false => rfl
      | true =>
        exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inl (by
          rw [dequeue_unique hdq hd0]; exact hh))) hb
    have hab : r.rhs.abstr.isEmpty = false := by
      cases hh : r.rhs.abstr.isEmpty with
      | false => rfl
      | true =>
        exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inr (Or.inl (by
          rw [dequeue_unique hdq hd0]; exact hh)))) hb
    have hsg : r.rhs.single? = none := by
      cases hh : r.rhs.single? with
      | none => rfl
      | some u =>
        exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inr (Or.inr (by
          rw [dequeue_unique hdq hd0, hh]; rfl)))) hb
    rw [hfr0] at h
    dsimp only at h
    rw [if_neg (by simp [hne]), if_neg (by simp [hab]), hsg] at h
    dsimp only at h
    cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
    | error m => rw [hlp] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨learned, su2⟩ := w
      rw [hlp] at h
      simp only [StepResult.continue.injEq] at h
      subst h
      have hrc : mk r.lhs r.rhs.abstr.fs (cfs r.rhs.conc) ∈ sys s := by
        rw [← toConstraint_eq]; exact hrG
      obtain ⟨H, hrunH, hsubH, hmH, hokH, hfrH⟩ :=
        learnPartitions_run hw.coh hem hdj hcse hok hfr hw.proc hrestOk hrOk.rhsOk
          hprocG hrestG hrc
          (by
            -- the syntactic lookup missing really is `¬ Named (sys s)`
            intro hcne htwo hnone
            rintro ⟨d, hd, hvset, hconc⟩
            rcases mem_sys.mp hd with ⟨p, hp, rfl⟩ | ⟨be, hbe, rfl⟩
            · have hpe : p.rhs.eqv (RHS.ofAbstr r.rhs.abstr) = true := by
                have hnil : p.rhs.conc.elems = [] := by
                  by_contra hcon
                  obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil _ hcon
                  have : y.n ∈ p.toConstraint.conc :=
                    List.mem_toFinset.mpr (List.mem_map.mpr ⟨y, hy, rfl⟩)
                  rw [hconc] at this
                  exact absurd this (Finset.notMem_empty _)
                have hab2 : p.rhs.abstr.elems.toFinset = r.rhs.abstr.elems.toFinset := by
                  have := hvset
                  rw [LPart.vset_toConstraint] at this
                  exact this
                rw [RHS.eqv, Bool.and_eq_true]
                refine ⟨(SSet.eqv_iff_toFinset (hw.nodup hp).1 hrOk.abstr).mpr hab2, ?_⟩
                rw [SSet.eqv, Bool.and_eq_true]
                exact ⟨by simp [SSet.size, hnil, RHS.ofAbstr, SSet.empty],
                  by simp [SSet.subsetOf, hnil]⟩
              rcases List.mem_append.mp hp with hp' | hp'
              · rcases dequeue_mem_or hdq p hp' with hp'' | rfl
                · exact absurd hpe (by rw [findRHS3_none hnone p (Or.inl hp'')]; simp)
                · exact hcne (by rw [← hconc]; rfl)
              · exact absurd hpe (by rw [findRHS3_none hnone p (Or.inr (Or.inl hp'))]; simp)
            · obtain ⟨w0, val0⟩ := be
              cases val0 with
              | emptyRow =>
                have : (0 : Nat) < 2 := by omega
                rw [← hvset] at htwo
                simp only [EnvVal.toConstraint, vset_mk, Finset.card_empty] at htwo
                omega
              | «alias» z =>
                rw [← hvset] at htwo
                simp only [EnvVal.toConstraint, vset_mk, Finset.card_singleton] at htwo
                omega)
          hlp
      -- the queue insertion
      obtain ⟨H2, hrun2, hsub2, hres⟩ := concatP_run hw.coh (trim learned s.proc).elems
        hrestOk (fun x hx =>
          (SOk.trim (L := s.labels) (q := s.proc)
            (learnPartitions_ok hrOk.rhsOk hw.proc hlp)) x hx)
        (fun x hx => hsubH (hrestG x hx))
        (fun x hx => hmH x (SSet.mem_filter hx))
      refine ((hrunH.trans hrun2).tail (LoopRel.weaken (sys_subset (fun x hx => ?_) ?_)))
      · rcases List.mem_append.mp hx with hx' | hx'
        · exact hres x hx'
        · rcases mem_insertNP hx' with hx'' | rfl
          · exact hsub2 (hsubH (hprocG x hx''))
          · exact hsub2 (hsubH hrG)
      · intro b hb'
        simp only [foldl_log_env] at hb'
        exact hsub2 (hsubH (henvG b hb'))


/-! ## 7. Every branch, and along a run -/

/-- `step` never changes the flags. -/
theorem step_flags {s s' : State} (h : step s = .continue s') : s'.flags = s.flags := by
  simp only [step, State.log] at h
  repeat' split at h
  all_goals (cases h <;> simp only [foldl_log_flags])

/-- **Refinement, for EVERY dispatch branch.**  This is the plan's (i) for the whole of
`step`, at the shipped flags and under the supply invariant. -/
theorem step_refines_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') : LoopRun (sys s) (sys s') := by
  by_cases hb : NonLearnStep s
  · exact step_refines_nonlearn hw hb h
  · exact step_refines_learn hw hem hdj hcse hok hfr hb h

/-- **Satisfiability is preserved by every `continue` step.** -/
theorem step_sat_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (step_refines_all hw hem hdj hcse hok hfr h).sat

/-- The supply invariant, carried along a run.  It is a HYPOTHESIS at each state rather than
an invariant: making it one needs the vocabulary clause threaded through the `*_run` lemmas of
the four non-minting branches as well (see `L3-THEOREMS.md`, Round 2). -/
def RunSupOk : Nat → State → Prop
  | 0, _ => True
  | n + 1, s => SupOk s.su ∧ SupFresh s.su (sys s) ∧ ∀ s', step s = .continue s' → RunSupOk n s'

/-- **Satisfiability along a run, with no restriction on the branches taken.** -/
theorem run_sat_all : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → SSat (sys s')
  | 0, s, _, _, _, _, _, hsat, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact hsat
  | n + 1, s, hw, hem, hdj, hcse, hb, hsat, s', hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [step_done hst]
        exact hsat
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      refine run_sat_all n (step_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
        (step_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat) s' hres
      · rw [step_flags hst]; exact hem
      · rw [step_flags hst]; exact hdj
      · rw [step_flags hst]; exact hcse

/-- **A refuting death refutes the INPUT**, with no restriction on the branches taken. -/
theorem run_refutes_all : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' → ¬ SSat (sys s') → ¬ SSat (sys s)
  | 0, s, _, _, _, _, _, m, s', hres, _ => by
    simp only [run] at hres; exact absurd hres (by simp)
  | n + 1, s, hw, hem, hdj, hcse, hb, m, s', hres, hns => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 => rw [hst] at hres; exact absurd hres (by simp)
    | died m0 s0 =>
      rw [hst] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨-, rfl⟩ := hres
      rw [step_died_sys hst] at hns
      exact hns
    | «continue» s0 =>
      rw [hst] at hres
      intro hsat
      refine run_refutes_all n (step_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst) m s' hres hns
        (step_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat)
      · rw [step_flags hst]; exact hem
      · rw [step_flags hst]; exact hdj
      · rw [step_flags hst]; exact hcse


end Rowpartition.Loop
