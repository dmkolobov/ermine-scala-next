/-
# L3 (i), continued: the `concrete` branch

`Loop/Refine.lean` refines the three dispatch branches that write the substitution
ENVIRONMENT.  This file adds the fourth, `makeConcrete` / `destructiveSub` / `subPartitions`
-- the branch that deletes.  It needs one thing the other three did not: the LABEL side of
the `SSet` -> `Finset` dictionary, because `cancellation` computes a set DIFFERENCE of label
sets and `Lbl.n` is injective only on the labels of ONE solve.  That injectivity is exactly
`LblCoh`, which `Wf` carries.

The one branch left after this is `learn`, and it is the one that MINTS.
-/
import Rowpartition.Loop.Refine

namespace Rowpartition.Loop

open Rowpartition

set_option linter.unusedSimpArgs false

/-! ## 1. The label side of the dictionary -/

/-- The finite set of label INDICES an `SSet Lbl` denotes -- which is what
`LPart.toConstraint` writes into a `Rowpartition.Constraint`. -/
def cfs (s : SSet Lbl) : Finset Label := (s.elems.map Lbl.n).toFinset

@[simp] theorem mem_cfs {s : SSet Lbl} {n : Label} :
    n ∈ cfs s ↔ ∃ x ∈ s.elems, x.n = n := by
  simp [cfs, List.mem_toFinset, List.mem_map]

theorem toConstraint_conc (p : LPart) : p.toConstraint.conc = cfs p.rhs.conc := rfl

theorem toConstraint_eq (p : LPart) :
    p.toConstraint = mk p.lhs p.rhs.abstr.fs (cfs p.rhs.conc) := rfl

@[simp] theorem cfs_empty : cfs (SSet.empty : SSet Lbl) = ∅ := rfl

theorem cfs_concat (s t : SSet Lbl) : cfs (s.concat t) = cfs s ∪ cfs t := by
  ext n
  simp only [mem_cfs, Finset.mem_union]
  constructor
  · rintro ⟨x, hx, rfl⟩
    rcases SSet.mem_concat hx with h | h
    · exact Or.inl ⟨x, h, rfl⟩
    · exact Or.inr ⟨x, h, rfl⟩
  · rintro (⟨x, hx, rfl⟩ | ⟨x, hx, rfl⟩)
    · exact ⟨x, SSet.mem_concat_iff.mpr (Or.inl hx), rfl⟩
    · exact ⟨x, SSet.mem_concat_iff.mpr (Or.inr hx), rfl⟩

/-- On a COHERENT pool the label index is injective, so a set difference of label sets is a
set difference of index sets. -/
theorem cfs_removedAll {L : List Lbl} (hcoh : LblCoh L) {s t : SSet Lbl}
    (hs : ∀ x ∈ s.elems, x ∈ L) (ht : ∀ x ∈ t.elems, x ∈ L) :
    cfs (s.removedAll t) = cfs s \ cfs t := by
  ext n
  simp only [mem_cfs, Finset.mem_sdiff]
  constructor
  · rintro ⟨x, hx, rfl⟩
    obtain ⟨hxs, hxt⟩ := SSet.mem_removedAll_iff.mp hx
    refine ⟨⟨x, hxs, rfl⟩, ?_⟩
    rintro ⟨y, hy, hyn⟩
    exact hxt (hcoh x (hs x hxs) y (ht y hy) hyn.symm ▸ hy)
  · rintro ⟨⟨x, hx, rfl⟩, hn⟩
    refine ⟨x, SSet.mem_removedAll_iff.mpr ⟨hx, fun hxt => hn ⟨x, hxt, rfl⟩⟩, rfl⟩

theorem cfs_inter {L : List Lbl} (hcoh : LblCoh L) {s t : SSet Lbl}
    (hs : ∀ x ∈ s.elems, x ∈ L) (ht : ∀ x ∈ t.elems, x ∈ L) :
    cfs (s.inter t) = cfs s ∩ cfs t := by
  ext n
  simp only [mem_cfs, Finset.mem_inter]
  constructor
  · rintro ⟨x, hx, rfl⟩
    obtain ⟨hxs, hxt⟩ := SSet.mem_inter_iff.mp hx
    exact ⟨⟨x, hxs, rfl⟩, ⟨x, hxt, rfl⟩⟩
  · rintro ⟨⟨x, hx, rfl⟩, ⟨y, hy, hyn⟩⟩
    have hxy : x = y := hcoh x (hs x hx) y (ht y hy) hyn.symm
    exact ⟨x, SSet.mem_inter_iff.mpr ⟨hx, hxy ▸ hy⟩, rfl⟩

theorem cfs_eq_empty_iff {s : SSet Lbl} : s.isEmpty = true ↔ cfs s = ∅ := by
  constructor
  · intro h
    have : s.elems = [] := by simpa [SSet.isEmpty] using h
    simp [cfs, this]
  · intro h
    cases hh : s.elems with
    | nil => simp [SSet.isEmpty, hh]
    | cons y l =>
      exfalso
      have : y.n ∈ cfs s := by rw [mem_cfs]; exact ⟨y, by rw [hh]; exact List.mem_cons_self .., rfl⟩
      rw [h] at this
      exact absurd this (Finset.notMem_empty _)


/-! ## 2. `RHS.merge`, as a run -/

/-- Erasing a list of variables that are known empty, one `SubstStep` each. -/
theorem eraseAll_run {G : System} {a : Var} {T : Finset Var} {K : Row} :
    ∀ (l : List Var), mk a T K ∈ G → (∀ w ∈ l, mk w ∅ (∅ : Row) ∈ G) →
      ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ mk a (T \ l.toFinset) K ∈ H ∧
        allVars H ⊆ allVars G := by
  intro l
  induction l generalizing G T with
  | nil =>
    intro hT _
    exact ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, by simpa using hT,
      Finset.Subset.refl _⟩
  | cons w l ih =>
    intro hT hw
    have hstep : ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ mk a (T.erase w) K ∈ H ∧
        allVars H ⊆ allVars G := by
      by_cases hmem : w ∈ T
      · refine ⟨insert (mk a (T.erase w ∪ ∅) (K ∪ ∅)) G,
          Relation.ReflTransGen.single (LoopRel.nongen (NonGenStep.subst ?_)),
          Finset.subset_insert _ _, ?_, ?_⟩
        · have happ : SubstApp G (mk a T K) (mk w ∅ (∅ : Row)) :=
            ⟨hT, hw w (by simp), by rw [lhs_mk, vset_mk]; exact hmem⟩
          have hst := SubstStep.intro happ
          simpa only [substResult, lhs_mk, vset_mk, conc_mk] using hst
        · rw [Finset.union_empty, Finset.union_empty]
          exact Finset.mem_insert_self _ _
        · refine allVars_insert_subset ?_ ?_
          · rw [lhs_mk]; exact lhs_mem_allVars hT
          · rw [vset_mk, Finset.union_empty]
            exact (Finset.erase_subset _ _).trans (by
              have := vset_subset_allVars hT; rwa [vset_mk] at this)
      · exact ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G,
          by rw [Finset.erase_eq_of_notMem hmem]; exact hT, Finset.Subset.refl _⟩
    obtain ⟨H1, hrun1, hsub1, hT1, hv1⟩ := hstep
    obtain ⟨H2, hrun2, hsub2, hT2, hv2⟩ := ih (G := H1) (T := T.erase w) hT1
      (fun x hx => hsub1 (hw x (by simp [hx])))
    refine ⟨H2, hrun1.trans hrun2, hsub1.trans hsub2, ?_, hv2.trans hv1⟩
    have : T.erase w \ l.toFinset = T \ (w :: l).toFinset := by
      ext x
      simp only [Finset.mem_sdiff, Finset.mem_erase, List.toFinset_cons, Finset.mem_insert,
        List.mem_toFinset]
      tauto
    rw [← this]
    exact hT2

/-- **`RHS.substitute` as a run.**  Rewriting one partition through a definition of `v` is
`SubstStep` followed by one `SubstStep` per variable that landed twice -- and each of those is
known EMPTY by `dedup`, which is what `RHS.merge`'s returned `es` records. -/
theorem subst_one_run {G : System} {r : LPart} {v : Nat}
    {sub : RHS} {nrhs : RHS} {es : SSet Nat} {i : Option Inference}
    (hrG : r.toConstraint ∈ G) (hsubG : mk v sub.abstr.fs (cfs sub.conc) ∈ G)
    (hv : r.rhs.contains v = true)
    (h : rhsSubstitute r.rhs v sub = .ok (nrhs, es)) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      (⟨r.lhs, nrhs, i⟩ : LPart).toConstraint ∈ H ∧
      (∀ w ∈ es.elems, mk w ∅ (∅ : Row) ∈ H) ∧ allVars H ⊆ allVars G := by
  set S := r.rhs.abstr.fs with hS
  set K := cfs r.rhs.conc with hK
  set S' := sub.abstr.fs with hS'
  set K' := cfs sub.conc with hK'
  have hvS : v ∈ S := by
    rw [hS, SSet.fs, List.mem_toFinset]
    exact (SSet.contains_iff r.rhs.abstr v).mp hv
  have hrc : r.toConstraint = mk r.lhs S K := rfl
  -- unfold the merge
  simp only [rhsSubstitute] at h
  rw [if_pos (show r.rhs.abstr.contains v = true from hv)] at h
  simp only [rhsMerge] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq] at h
    simp only [RHS.erase] at h
    obtain ⟨rfl, rfl⟩ := h
    have hesFs : ((r.rhs.abstr.excl v).inter sub.abstr).fs = (S.erase v) ∩ S' := by
      rw [SSet.fs_inter, SSet.fs_excl]
    -- phase 1: the de-duplication facts
    have hSG : S ⊆ allVars G := by
      have := vset_subset_allVars (hrc ▸ hrG); rwa [vset_mk] at this
    have hS'G : S' ⊆ allVars G := by
      have := vset_subset_allVars hsubG; rwa [vset_mk] at this
    have hwmemAll : ∀ w ∈ ((r.rhs.abstr.excl v).inter sub.abstr).elems,
        w ∈ (S.erase v) ∩ S' := by
      intro w hw
      rw [← hesFs, SSet.fs, List.mem_toFinset]; exact hw
    obtain ⟨H1, hrun1, hsub1, hA, hv1⟩ := adds_list_vars (G := G)
      (((r.rhs.abstr.excl v).inter sub.abstr).elems.map (fun w => mk w ∅ (∅ : Row)))
      (by
        intro c hc
        obtain ⟨w, hw, rfl⟩ := List.mem_map.mp hc
        have hwmem := Finset.mem_inter.mp (hwmemAll w hw)
        intro Hx hHx
        exact LoopRel.dedup (hHx (hrc ▸ hrG)) (hHx hsubG) hvS hwmem.1 hwmem.2)
      (by
        intro c hc
        obtain ⟨w, hw, rfl⟩ := List.mem_map.mp hc
        rw [lhs_mk]
        exact hSG (Finset.mem_of_mem_erase (Finset.mem_inter.mp (hwmemAll w hw)).1))
      (by intro c hc; obtain ⟨w, hw, rfl⟩ := List.mem_map.mp hc; rw [vset_mk]; simp)
    -- phase 2: the substitution itself
    obtain ⟨H2, hrun2, hsub2, hc2, hv2⟩ :
        ∃ H2 : System, LoopRun G H2 ∧ H1 ⊆ H2 ∧ mk r.lhs (S.erase v ∪ S') (K ∪ K') ∈ H2 ∧
          allVars H2 ⊆ allVars H1 := by
      refine ⟨insert (mk r.lhs (S.erase v ∪ S') (K ∪ K')) H1,
        hrun1.tail (LoopRel.nongen (NonGenStep.subst ?_)),
        Finset.subset_insert _ _, Finset.mem_insert_self _ _, ?_⟩
      swap
      · refine allVars_insert_subset ?_ ?_
        · rw [lhs_mk]
          refine allVars_mono hsub1 ?_
          have := lhs_mem_allVars (show mk r.lhs S K ∈ G from hrc ▸ hrG)
          rwa [lhs_mk] at this
        · rw [vset_mk]
          exact Finset.union_subset
            ((Finset.erase_subset _ _).trans (hSG.trans (allVars_mono hsub1)))
            (hS'G.trans (allVars_mono hsub1))
      have happ : SubstApp H1 (mk r.lhs S K) (mk v S' K') :=
        ⟨hsub1 (hrc ▸ hrG), hsub1 hsubG, by rw [lhs_mk, vset_mk]; exact hvS⟩
      have hst := SubstStep.intro happ
      simpa only [substResult, lhs_mk, vset_mk, conc_mk] using hst
    -- phase 3: erase the duplicates
    obtain ⟨H3, hrun3, hsub3, hc3, hv3⟩ := eraseAll_run (G := H2) (a := r.lhs)
      (T := S.erase v ∪ S') (K := K ∪ K')
      ((r.rhs.abstr.excl v).inter sub.abstr).elems hc2
      (fun w hw => hsub2 (hA _ (List.mem_map.mpr ⟨w, hw, rfl⟩)))
    refine ⟨H3, hrun2.trans hrun3, ((hsub1.trans hsub2).trans hsub3), ?_, ?_,
      (hv3.trans hv2).trans hv1⟩
    · have hgoal : (⟨r.lhs, (⟨((r.rhs.abstr.excl v).concat sub.abstr).removedAll
          ((r.rhs.abstr.excl v).inter sub.abstr), r.rhs.conc.concat sub.conc⟩ : RHS), i⟩
          : LPart).toConstraint
          = mk r.lhs ((S.erase v ∪ S') \
              ((r.rhs.abstr.excl v).inter sub.abstr).elems.toFinset) (K ∪ K') := by
        rw [toConstraint_eq]
        congr 1
        · show (((r.rhs.abstr.excl v).concat sub.abstr).removedAll
            ((r.rhs.abstr.excl v).inter sub.abstr)).fs = _
          rw [SSet.fs_removedAll, SSet.fs_concat, SSet.fs_excl]
          rfl
        · rw [cfs_concat]
      rw [hgoal]
      exact hc3
    · intro w hw
      exact hsub3 (hsub2 (hA _ (List.mem_map.mpr ⟨w, hw, rfl⟩)))
  · exact absurd h (by simp)


/-! ## 3. `subPartitions` and `destructiveSub`, as runs -/

/-- **`Constraints.subPartitions` as a run.**  Every partition it derives is one `SubstStep`
plus one `SubstStep` per de-duplicated variable. -/
theorem subPartitions_run {G : System} {v : Nat} {sub : RHS} {proc incm : PQueue}
    {S : SSet LPart}
    (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G) (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G)
    (hsubG : mk v sub.abstr.fs (cfs sub.conc) ∈ G)
    (h : subPartitions v sub proc incm = .ok S) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧ ∀ x ∈ S.elems, x.toConstraint ∈ H := by
  simp only [subPartitions] at h
  refine foldl_except_inv
    (P := fun (T : SSet LPart) => ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      ∀ x ∈ T.elems, x.toConstraint ∈ H)
    (Q := fun (x : LPart) => x.toConstraint ∈ G) ?_ _
    (fun x hx => hiG x (List.mem_of_mem_filter hx)) _ ?_ S h
  case refine_1 =>
    intro acc x hx hacc b hb
    cases hacc' : acc with
    | error m =>
      rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
    | ok a =>
      obtain ⟨H, hrun, hsub, ha⟩ := hacc a hacc'
      rw [hacc'] at hb
      simp only [bind, Except.bind] at hb
      split at hb
      · rename_i hcv
        cases hrs : rhsSubstitute x.rhs v sub with
        | error m => rw [hrs] at hb; simp only [bind, Except.bind] at hb
                     exact absurd hb (by simp)
        | ok w =>
          obtain ⟨nrhs, es⟩ := w
          rw [hrs] at hb
          simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          obtain ⟨H1, hrun1, hsub1, hc1, hdd, -⟩ :=
            subst_one_run (i := x.inf) (hsub hx) (hsub hsubG) hcv hrs
          refine ⟨H1, hrun.trans hrun1, hsub.trans hsub1, ?_⟩
          · intro y hy
            rcases SSet.mem_incl hy with hy' | rfl
            · rcases SSet.mem_concat hy' with hy'' | hy''
              · exact hsub1 (ha y hy'')
              · obtain ⟨w0, hw0, rfl⟩ := SSet.mem_map hy''
                exact hdd w0 hw0
            · exact hc1
      · simp only [pure, Except.pure, Except.ok.injEq] at hb
        subst hb
        exact ⟨H, hrun, hsub, ha⟩
  case refine_2 =>
    refine foldl_except_inv
      (P := fun (T : SSet LPart) => ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
        ∀ x ∈ T.elems, x.toConstraint ∈ H)
      (Q := fun (x : LPart) => x.toConstraint ∈ G) ?_ _ hpG _ ?_
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨H, hrun, hsub, ha⟩ := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · rename_i hcv
          cases hrs : rhsSubstitute x.rhs v sub with
          | error m => rw [hrs] at hb; simp only [bind, Except.bind] at hb
                       exact absurd hb (by simp)
          | ok w =>
            obtain ⟨nrhs, es⟩ := w
            rw [hrs] at hb
            simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            obtain ⟨H1, hrun1, hsub1, hc1, hdd, -⟩ :=
              subst_one_run (i := x.inf) (hsub hx) (hsub hsubG) hcv hrs
            refine ⟨H1, hrun.trans hrun1, hsub.trans hsub1, ?_⟩
            intro y hy
            rcases SSet.mem_incl hy with hy' | rfl
            · rcases SSet.mem_concat hy' with hy'' | hy''
              · exact hsub1 (ha y hy'')
              · obtain ⟨w0, hw0, rfl⟩ := SSet.mem_map hy''
                exact hdd w0 hw0
            · exact hc1
        · simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          exact ⟨H, hrun, hsub, ha⟩
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      exact ⟨G, Relation.ReflTransGen.refl, Finset.Subset.refl G, by intro y hy; cases hy⟩


/-- **`Constraints.destructiveSub` as a run.**  Its `srs` re-expression is `subPartitions` at
each definition of `v`; the deletions and the kept definitions are `weaken` and membership. -/
theorem destructiveSub_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {v : Nat} {rhs : RHS}
    {incm proc : PQueue} {ni np : PQueue}
    (hiOk : QOk L incm) (hpOk : QOk L proc)
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hrhsG : mk v rhs.abstr.fs (cfs rhs.conc) ∈ G)
    (hrhsOk : ROk L rhs)
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      (∀ x ∈ ni.elems, x.toConstraint ∈ H) ∧ (∀ x ∈ np.elems, x.toConstraint ∈ H) := by
  simp only [destructiveSub] at h
  set pps := (proc.partition (fun p => p.lhs == v)).1 with hpps
  set procd := (proc.partition (fun p => p.lhs == v)).2 with hprocd
  set qps := (incm.partition (fun p => p.lhs == v)).1 with hqps
  set incmg := (incm.partition (fun p => p.lhs == v)).2 with hincmg
  have hppsG : ∀ x ∈ pps.elems, x.toConstraint ∈ G := fun x hx => hpG x
    (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx)))
  have hqpsG : ∀ x ∈ qps.elems, x.toConstraint ∈ G := fun x hx => hiG x
    (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx)))
  have hppsLhs : ∀ x ∈ pps.elems, x.lhs = v := fun x hx => by
    have := (List.mem_filter.mp (List.mem_reverse.mp (SSet.mem_ofList hx))).2
    simpa using this
  have hqpsLhs : ∀ x ∈ qps.elems, x.lhs = v := fun x hx => by
    have := (List.mem_filter.mp (List.mem_reverse.mp (SSet.mem_ofList hx))).2
    simpa using this
  have hprocdG : ∀ x ∈ procd.elems, x.toConstraint ∈ G := fun x hx => hpG x
    (List.mem_of_mem_filter hx)
  have hincmgG : ∀ x ∈ incmg.elems, x.toConstraint ∈ G := fun x hx => hiG x
    (List.mem_of_mem_filter hx)
  have hprocdOk : QOk L procd := hpOk.partition_snd _
  have hincmgOk : QOk L incmg := hiOk.partition_snd _
  have hppsOk : SOk L pps := hpOk.partition_fst _
  have hqpsOk : SOk L qps := hiOk.partition_fst _
  -- the definitions of `v` really are definitions of `v`
  have hdefG : ∀ r' ∈ ((pps.concat qps).map (fun p => p.rhs)).elems,
      mk v r'.abstr.fs (cfs r'.conc) ∈ G := by
    intro r' hr'
    obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
    rcases SSet.mem_concat hp with hp' | hp'
    · have := hppsG p hp'
      rwa [toConstraint_eq, hppsLhs p hp'] at this
    · have := hqpsG p hp'
      rwa [toConstraint_eq, hqpsLhs p hp'] at this
  have hdefOk : ∀ r' ∈ ((pps.concat qps).map (fun p => p.rhs)).elems, ROk L r' := by
    intro r' hr'
    obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
    rcases SSet.mem_concat hp with hp' | hp'
    · exact (hppsOk p hp').rhsOk
    · exact (hqpsOk p hp').rhsOk
  obtain ⟨srs, hsrs, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨rfl, rfl⟩ := h2
  -- the derived set, both as `SOk` and as constraints of a reachable system
  have hsrsAll : SOk L srs ∧ ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      ∀ x ∈ srs.elems, x.toConstraint ∈ H := by
    refine foldl_except_inv
      (P := fun (T : SSet LPart) => SOk L T ∧ ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
        ∀ x ∈ T.elems, x.toConstraint ∈ H)
      (Q := fun (r' : RHS) => ROk L r' ∧ mk v r'.abstr.fs (cfs r'.conc) ∈ G) ?_ _
      (fun r' hr' => ⟨hdefOk r' hr', hdefG r' hr'⟩) _ ?_ srs hsrs
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨haOk, H, hrun, hsub, ha⟩ := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        cases hsp : subPartitions v x procd incmg with
        | error m => rw [hsp] at hb; simp only [bind, Except.bind] at hb
                     exact absurd hb (by simp)
        | ok T =>
          rw [hsp] at hb
          simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          obtain ⟨H1, hrun1, hsub1, hT⟩ :=
            subPartitions_run (fun y hy => hsub (hprocdG y hy))
              (fun y hy => hsub (hincmgG y hy)) (hsub hx.2) hsp
          refine ⟨haOk.concat (subPartitions_ok hx.1 hprocdOk hincmgOk hsp),
            H1, hrun.trans hrun1, hsub.trans hsub1, ?_⟩
          intro y hy
          rcases SSet.mem_concat hy with hy' | hy'
          · exact hsub1 (ha y hy')
          · exact hT y hy'
    · intro b hb
      obtain ⟨H1, hrun1, hsub1, hT⟩ :=
        subPartitions_run hprocdG hincmgG hrhsG hb
      exact ⟨subPartitions_ok hrhsOk hprocdOk hincmgOk hb, H1, hrun1, hsub1, hT⟩
  obtain ⟨hsrsOk, H, hrun, hsub, hsrsG⟩ := hsrsAll
  set cond := srs.isEmpty && !(pps.concat qps).isEmpty with hcond
  set nproc0 := if cond then proc
    else procd.filter (fun p => p.lhs != v && !p.rhs.contains v) with hnproc0
  set nincm0 := if cond then incm
    else incmg.filter (fun p => p.lhs != v && !p.rhs.contains v) with hnincm0
  set nproc := if !cond then
      nproc0.concatNP (pps.filter (fun b => decide (b.rhs.abstr.size ≥ 2))).elems
    else nproc0 with hnproc
  set nincm := if !cond then
      nincm0.concatP (qps.filter (fun b => decide (b.rhs.abstr.size ≥ 2))).elems
    else nincm0 with hnincm
  have hnproc0G : ∀ x ∈ nproc0.elems, x.toConstraint ∈ G := by
    rw [hnproc0]; split
    · exact hpG
    · exact fun x hx => hprocdG x (List.mem_of_mem_filter hx)
  have hnproc0Ok : QOk L nproc0 := by
    rw [hnproc0]; split
    · exact hpOk
    · exact hprocdOk.filter _
  have hnprocG : ∀ x ∈ nproc.elems, x.toConstraint ∈ G := by
    rw [hnproc]; split
    · intro x hx
      rcases mem_concatNP _ _ hx with hx' | hx'
      · exact hnproc0G x hx'
      · exact hppsG x (SSet.mem_filter hx')
    · exact hnproc0G
  have hnincm0G : ∀ x ∈ nincm0.elems, x.toConstraint ∈ G := by
    rw [hnincm0]; split
    · exact hiG
    · exact fun x hx => hincmgG x (List.mem_of_mem_filter hx)
  have hnincm0Ok : QOk L nincm0 := by
    rw [hnincm0]; split
    · exact hiOk
    · exact hincmgOk.filter _
  have hnincmOk : QOk L nincm := by
    rw [hnincm]; split
    · exact QOk.concatP _ _ hnincm0Ok (fun x hx => hqpsOk x (SSet.mem_filter hx))
    · exact hnincm0Ok
  obtain ⟨H1, hrun1, hsub1, hnincmG⟩ :
      ∃ H1 : System, LoopRun H H1 ∧ H ⊆ H1 ∧ ∀ x ∈ nincm.elems, x.toConstraint ∈ H1 := by
    rw [hnincm]; split
    · exact concatP_run hcoh _ hnincm0Ok (fun x hx => hqpsOk x (SSet.mem_filter hx))
        (fun x hx => hsub (hnincm0G x hx)) (fun x hx => hsub (hqpsG x (SSet.mem_filter hx)))
    · exact ⟨H, Relation.ReflTransGen.refl, Finset.Subset.refl H,
        fun x hx => hsub (hnincm0G x hx)⟩
  obtain ⟨H2, hrun2, hsub2, hres⟩ := concatP_run hcoh (trim srs nproc).elems hnincmOk
    (fun x hx => hsrsOk x (SSet.mem_filter hx)) hnincmG
    (fun x hx => hsub1 (hsrsG x (SSet.mem_filter hx)))
  exact ⟨H2, (hrun.trans hrun1).trans hrun2, (hsub.trans hsub1).trans hsub2, hres,
    fun x hx => hsub2 (hsub1 (hsub (hnprocG x hx)))⟩


/-! ## 4. `makeConcrete` -/

/-- **`makeConcrete`'s cancellation fold is `CancelStep`.**  Only the SECOND branch of
`cancellation` can fire, because the concrete row's variable part is empty and the first
branch wants exactly one variable left over on that side. -/
theorem cancellation_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {v : Nat}
    {fs : SSet Lbl} {r : RHS}
    (hfsL : ∀ x ∈ fs.elems, x ∈ L) (hrL : ∀ x ∈ r.conc.elems, x ∈ L)
    (hdefG : mk v r.abstr.fs (cfs r.conc) ∈ G) (hconG : mk v ∅ (cfs fs) ∈ G) :
    ∀ z ∈ (cancellation v (RHS.ofConcr fs) r).elems, Adds G z.toConstraint := by
  have hxs : ((RHS.ofConcr fs).abstr.removedAll
      ((RHS.ofConcr fs).abstr.inter r.abstr)).elems = [] := rfl
  have hys : (r.abstr.removedAll ((RHS.ofConcr fs).abstr.inter r.abstr)).elems
      = r.abstr.elems := rfl
  intro z hz
  simp only [cancellation] at hz
  split at hz
  · rename_i hb1
    rw [Bool.and_eq_true] at hb1
    exfalso
    have hsz : ((RHS.ofConcr fs).abstr.removedAll
        ((RHS.ofConcr fs).abstr.inter r.abstr)).size = 1 := by simpa using hb1.2
    rw [SSet.size, hxs] at hsz
    exact absurd hsz (by simp)
  · split at hz
    · rename_i hb2
      rw [Bool.and_eq_true] at hb2
      split at hz
      · rename_i y tl hy
        rw [hys] at hy
        have hlen : r.abstr.elems.length = 1 := by
          have := hb2.2
          simpa [SSet.size, hys] using this
        have hone : r.abstr.elems = [y] := by
          rw [hy] at hlen
          simp only [List.length_cons] at hlen
          have htl : tl = [] := List.eq_nil_of_length_eq_zero (by omega)
          rw [hy, htl]
        have hlone : r.abstr.fs \ (∅ : Finset Var) = {y} := by
          rw [SSet.fs, hone]; simp
        have hconle : cfs r.conc ⊆ cfs fs := by
          have hg : (r.conc.removedAll (fs.inter r.conc)).isEmpty = true := hb2.1
          have hgg := cfs_eq_empty_iff.mp hg
          rw [cfs_removedAll hcoh hrL (fun x hx => hfsL x (SSet.mem_inter hx)),
            cfs_inter hcoh hfsL hrL] at hgg
          intro n hn
          by_contra hnf
          have hcon : n ∈ cfs r.conc \ (cfs fs ∩ cfs r.conc) :=
            Finset.mem_sdiff.mpr ⟨hn, fun hh => hnf (Finset.mem_inter.mp hh).1⟩
          rw [hgg] at hcon
          exact absurd hcon (Finset.notMem_empty n)
        rw [List.mem_singleton.mp (SSet.mem_ofList hz)]
        intro Hx hHx
        refine LoopRel.nongen (NonGenStep.cancel ?_)
        have happ : CancelApp Hx (mk v r.abstr.fs (cfs r.conc)) (mk v ∅ (cfs fs)) y :=
          ⟨hHx hdefG, hHx hconG, rfl, by rw [conc_mk, conc_mk]; exact hconle,
            by rw [vset_mk, vset_mk]; exact hlone⟩
        have hst := CancelStep.intro happ
        have hgoal : (⟨y, ⟨(RHS.ofConcr fs).abstr.removedAll
            ((RHS.ofConcr fs).abstr.inter r.abstr),
            (RHS.ofConcr fs).conc.removedAll ((RHS.ofConcr fs).conc.inter r.conc)⟩,
            some Inference.cancellation⟩ : LPart).toConstraint
            = mk y ((∅ : Finset Var) \ r.abstr.fs) (cfs fs \ cfs r.conc) := by
          rw [toConstraint_eq]
          congr 1
          · show ((RHS.ofConcr fs).abstr.removedAll
              ((RHS.ofConcr fs).abstr.inter r.abstr)).fs = _
            rw [SSet.fs, hxs]
            simp
          · show cfs (fs.removedAll (fs.inter r.conc)) = _
            rw [cfs_removedAll hcoh hfsL (fun x hx => hfsL x (SSet.mem_inter hx)),
              cfs_inter hcoh hfsL hrL]
            ext n
            simp only [Finset.mem_sdiff, Finset.mem_inter]
            tauto
        rw [hgoal]
        simpa only [cancelResult, vset_mk, conc_mk] using hst
      · cases hz
    · cases hz


/-- **`Constraints.makeConcrete` as a run.** -/
theorem makeConcrete_run {L : List Lbl} (hcoh : LblCoh L) {G : System} {v : Nat}
    {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hiOk : QOk L incm) (hpOk : QOk L proc)
    (hiG : ∀ x ∈ incm.elems, x.toConstraint ∈ G) (hpG : ∀ x ∈ proc.elems, x.toConstraint ∈ G)
    (hfsOk : COk L fs) (hconG : mk v ∅ (cfs fs) ∈ G)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∃ H : System, LoopRun G H ∧ G ⊆ H ∧
      (∀ x ∈ ni.elems, x.toConstraint ∈ H) ∧ (∀ x ∈ np.elems, x.toConstraint ∈ H) := by
  simp only [makeConcrete] at h
  set rhss := (((SSet.ofList proc.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)).concat
    (((SSet.ofList incm.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)) with hrhss
  have hrhssWit : ∀ r ∈ rhss.elems, ∃ p, (p ∈ proc.elems ∨ p ∈ incm.elems) ∧
      p.lhs = v ∧ p.rhs = r := by
    intro r hr
    rcases SSet.mem_concat hr with hr' | hr'
    · obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
      exact ⟨p, Or.inl (SSet.mem_ofList (SSet.mem_filter hp)),
        by simpa using (SSet.mem_filter_iff.mp hp).2, rfl⟩
    · obtain ⟨p, hp, rfl⟩ := SSet.mem_map hr'
      exact ⟨p, Or.inr (SSet.mem_ofList (SSet.mem_filter hp)),
        by simpa using (SSet.mem_filter_iff.mp hp).2, rfl⟩
  have hrhssG : ∀ r ∈ rhss.elems, mk v r.abstr.fs (cfs r.conc) ∈ G := by
    intro r hr
    obtain ⟨p, hp, hlhs, rfl⟩ := hrhssWit r hr
    rcases hp with hp' | hp'
    · have := hpG p hp'; rwa [toConstraint_eq, hlhs] at this
    · have := hiG p hp'; rwa [toConstraint_eq, hlhs] at this
  have hrhssOk : ∀ r ∈ rhss.elems, ROk L r := by
    intro r hr
    obtain ⟨p, hp, -, rfl⟩ := hrhssWit r hr
    rcases hp with hp' | hp'
    · exact (hpOk p hp').rhsOk
    · exact (hiOk p hp').rhsOk
  -- the cancellation fold
  set can := rhss.elems.foldl
    (fun (s : SSet LPart) (r : RHS) => s.concat (cancellation v (RHS.ofConcr fs) r))
    SSet.empty with hcan
  have hcanAdds : ∀ z ∈ can.elems, Adds G z.toConstraint := by
    rw [hcan]
    refine foldl_inv (P := fun (s : SSet LPart) => ∀ z ∈ s.elems, Adds G z.toConstraint)
      (Q := fun (r : RHS) => ROk L r ∧ mk v r.abstr.fs (cfs r.conc) ∈ G) ?_ _
      (fun r hr => ⟨hrhssOk r hr, hrhssG r hr⟩) _ (by intro z hz; cases hz)
    intro s r hr hs z hz
    rcases SSet.mem_concat hz with hz' | hz'
    · exact hs z hz'
    · exact cancellation_run hcoh hfsOk.sub hr.1.conc.sub hr.2 hconG z hz'
  have hcanOk : SOk L can := by
    rw [hcan]
    refine foldl_inv (P := SOk L) (Q := fun (r : RHS) => ROk L r) ?_ _
      (fun r hr => hrhssOk r hr) _ SOk.empty
    intro s r hr hs
    exact hs.concat (cancellation_ok (ROk.ofConcr hfsOk) hr)
  obtain ⟨H1, hrun1, hsub1, hcanG⟩ := adds_list (G := G) (can.elems.map LPart.toConstraint)
    (by intro c hc; obtain ⟨z, hz, rfl⟩ := List.mem_map.mp hc; exact hcanAdds z hz)
  -- the destructive substitution
  obtain ⟨u1, hu1, h2⟩ := except_bind_ok h
  cases hds : destructiveSub v (RHS.ofConcr fs) incm proc with
  | error m => rw [hds] at h2; simp only [bind, Except.bind] at h2; exact absurd h2 (by simp)
  | ok w =>
    obtain ⟨nincm, nproc⟩ := w
    rw [hds] at h2
    simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    obtain ⟨hnincmOk, hnprocOk⟩ := destructiveSub_ok (ROk.ofConcr hfsOk) hiOk hpOk hds
    obtain ⟨H2, hrun2, hsub2, hnincmG, hnprocG⟩ := destructiveSub_run hcoh hiOk hpOk
      (fun x hx => hsub1 (hiG x hx)) (fun x hx => hsub1 (hpG x hx))
      (by exact hsub1 hconG) (ROk.ofConcr hfsOk) hds
    obtain ⟨H3, hrun3, hsub3, hres⟩ := concatP_run hcoh can.elems hnincmOk hcanOk hnincmG
      (fun x hx => hsub2 (hcanG _ (List.mem_map.mpr ⟨x, hx, rfl⟩)))
    refine ⟨H3, (hrun1.trans hrun2).trans hrun3, ((hsub1.trans hsub2).trans hsub3), hres, ?_⟩
    intro x hx
    rcases mem_insertNP hx with hx' | rfl
    · exact hsub3 (hnprocG x hx')
    · exact hsub3 (hsub2 (hsub1 hconG))


/-! ## 5. The dispatch, with the `concrete` branch added -/

/-- Every dispatch branch except `learn` -- the only one that MINTS. -/
def NonLearnStep (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨
    r.rhs.abstr.isEmpty = true ∨ (r.rhs.single?).isSome = true

theorem dequeue_unique {q : PQueue} {r r0 : LPart} {rest rest0 : PQueue}
    (h1 : q.dequeue = some (r, rest)) (h2 : q.dequeue = some (r0, rest0)) : r0 = r := by
  rw [h1] at h2
  simp only [Option.some.injEq, Prod.mk.injEq] at h2
  exact h2.1.symm

theorem abstr_isEmpty_toConstraint {p : LPart} (h : p.rhs.abstr.isEmpty = true) :
    p.toConstraint = mk p.lhs ∅ (cfs p.rhs.conc) := by
  have hnil : p.rhs.abstr.elems = [] := by simpa [SSet.isEmpty] using h
  rw [toConstraint_eq, SSet.fs, hnil]
  rfl

/-- **Refinement for the four non-minting branches.** -/
theorem step_refines_nonlearn {s s' : State} (hw : Wf s) (hb : NonLearnStep s)
    (h : step s = .continue s') : LoopRun (sys s) (sys s') := by
  by_cases hlink : LinkOrEmptyStep s
  · exact step_refines hw hlink h
  · -- the `concrete` branch
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
      cases hfr : s.proc.findRHS r.rhs with
      | some u =>
        exact absurd (fun r0 rest0 hd0 => Or.inl (by
          rw [dequeue_unique hdq hd0, hfr]; rfl)) hlink
      | none =>
        rw [hfr] at h
        dsimp only at h
        by_cases hempty : r.rhs.isEmpty = true
        · exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inl (by
            rw [dequeue_unique hdq hd0]; exact hempty))) hlink
        · rw [if_neg hempty] at h
          have habs : r.rhs.abstr.isEmpty = true := by
            rcases hb r rest hdq with hh | hh | hh | hh
            · rw [hfr] at hh; exact absurd hh (by simp)
            · exact absurd hh hempty
            · exact hh
            · exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inr (by
                rw [dequeue_unique hdq hd0]; exact hh))) hlink
          rw [if_pos habs] at h
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨H, hrun, hsub, hni, hnp⟩ := makeConcrete_run hw.coh hrestOk hw.proc
              hrestG hprocG hrOk.conc
              (by rw [← abstr_isEmpty_toConstraint habs]; exact hrG) hres
            exact hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
              rcases List.mem_append.mp hx with hx' | hx'
              · exact hni x hx'
              · exact hnp x hx') (fun b hb' => hsub (henvG b hb'))))

/-- **Satisfiability is preserved along every `continue` step of the four non-minting
branches.** -/
theorem step_sat_nonlearn {s s' : State} (hw : Wf s) (hb : NonLearnStep s)
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (step_refines_nonlearn hw hb h).sat


/-- Every state of a run takes one of the four non-minting branches. -/
def RunNonLearn : Nat → State → Prop
  | 0, _ => True
  | n + 1, s => NonLearnStep s ∧ ∀ s', step s = .continue s' → RunNonLearn n s'

theorem run_sat_nonlearn : ∀ (n : Nat) {s : State}, Wf s → RunNonLearn n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → SSat (sys s')
  | 0, s, _, _, hsat, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact hsat
  | n + 1, s, hw, hb, hsat, s', hres => by
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
      exact run_sat_nonlearn n (step_wf hw hst) (hb.2 s0 hst)
        (step_sat_nonlearn hw hb.1 hst hsat) s' hres

/-- **A refuting death refutes the INPUT**, along a run of non-minting steps. -/
theorem run_refutes_nonlearn : ∀ (n : Nat) {s : State}, Wf s → RunNonLearn n s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' → ¬ SSat (sys s') → ¬ SSat (sys s)
  | 0, s, _, _, m, s', hres, _ => by simp only [run] at hres; exact absurd hres (by simp)
  | n + 1, s, hw, hb, m, s', hres, hns => by
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
      exact fun hsat => run_refutes_nonlearn n (step_wf hw hst) (hb.2 s0 hst) m s' hres hns
        (step_sat_nonlearn hw hb.1 hst hsat)

end Rowpartition.Loop
