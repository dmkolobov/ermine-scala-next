/-
# L5 round 3 (R3.2): the branch refinements factored THROUGH the library operators

`L5-REVIEW.md` R-4 records that round 2's `step_empty_makeEmptyE` is a LEAF: it says
`LoopStrict (sys s) (makeEmptyE r.lhs (sys s))`, which is a step to the OPERATOR's output, and
nothing composes it with the `requeue` that reaches `sys s'`.  It also records that
`instRemove` is declared and never applied, because `substOut` omits `replace`'s
de-duplication fact `u <- ()` and so `NoLoss G (substOut v u G)` is not dischargeable in
general.

This module closes both.  The pattern is the same in each case: the operator's output `H` sits
between `sys s` and `sys s'`, and

* `LoopStrict (sys s) H` is the operator constructor (`emptyRemove` / `instRemove`);
* `LoopStrict H (sys s')` is a `requeue`, whose three clauses are obtained by COMPOSING what
  round 2 already proved -- `step_noLoss_strict`, `step_conserv_strict`, `step_allVars_strict`
  -- with the operator's own soundness and `NoLoss`.  The vocabulary clause needs the operators'
  vocabulary EQUALITIES, which are new here (`allVars_makeEmptyE_eq`, `allVars_substOut_eq`);
  the library only had the ⊆ direction.

The `hdefs` premise `makeEmptyE_noLoss` needs -- "no constraint defines `v` with a concrete
part" -- is obtained from SATISFIABILITY here (`defs_conc_empty_of_sat`) rather than by
re-running `makeEmpty_defs_conc_empty`'s fold: under a model, `v <- ()` forces every definition
of `v` to have an empty concrete part.  That is the natural hypothesis for a termination
argument, which is about satisfiable input.
-/
import Rowpartition.Loop.Carried

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

/-! ## 1. `hdefs` from satisfiability -/

/-- **Under a model, `v <- ()` forces every definition of `v` to be label-free.**  This is the
`die` arm of `makeEmpty` ("Incompatible instantiations"), read semantically. -/
theorem defs_conc_empty_of_sat {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hsat : SSat G) : ∀ c ∈ G, c.lhs = v → c.conc = ∅ := by
  obtain ⟨rho, hm⟩ := hsat
  have hv0 : rho v = ∅ := sat_empty_iff.mp (hm _ hv)
  intro c hc hlhs
  have hcs : Sat rho (mk c.lhs (vset c) c.conc) := by rw [← hshape c hc]; exact hm c hc
  rw [sat_mk_iff] at hcs
  have := hcs.1
  rw [hlhs, hv0] at this
  refine Finset.eq_empty_of_forall_notMem (fun l hl => ?_)
  have : l ∈ (∅ : Row) := by
    rw [this]
    exact Finset.mem_union_left _ hl
  exact absurd this (Finset.notMem_empty l)

/-! ## 2. The operators do not shrink the vocabulary either -/

/-- **`makeEmptyE` keeps every variable.**  The library has `allVars_makeEmptyE_subset`; the
other inclusion is what the composed refinement needs, and it holds on exactly the systems
`makeEmpty` does not die on: an erased constraint keeps its other variables, a propagated one
names the part, and `v` itself survives as the retained `v <- ()`. -/
theorem allVars_makeEmptyE_supset {G : System} {v : Var} (_hshape : MkShaped G)
    (_hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    allVars G ⊆ allVars (makeEmptyE v G) := by
  have hvE : mk v ∅ (∅ : Row) ∈ makeEmptyE v G := mem_makeEmptyE.mpr (Or.inl rfl)
  have hvmem : v ∈ allVars (makeEmptyE v G) := lhs_mem_allVars hvE
  intro w hw
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
  by_cases hlhs : c.lhs = v
  · rcases Finset.mem_insert.mp hwc with rfl | hwv
    · rw [hlhs]; exact hvmem
    · -- a PART of a definition of `v`: the propagation names it
      have hconc : c.conc = ∅ := hdefs c hc hlhs
      have hmem : mk w ∅ (∅ : Row) ∈ makeEmptyE v G :=
        mem_makeEmptyE.mpr (Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inr
          ⟨c, hc, hlhs, hconc, w, hwv, rfl⟩))))
      exact lhs_mem_allVars hmem
  · by_cases hvin : v ∈ vset c
    · have hmem : mk c.lhs ((vset c).erase v) c.conc ∈ makeEmptyE v G :=
        mem_makeEmptyE.mpr (Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inl
          ⟨c, hc, hlhs, hvin, rfl⟩))))
      rcases Finset.mem_insert.mp hwc with rfl | hwv
      · exact mem_allVars hmem (Or.inl (by rw [lhs_mk]))
      · by_cases hwv' : w = v
        · rw [hwv']; exact hvmem
        · exact mem_allVars hmem (Or.inr (by
            rw [vset_mk]; exact Finset.mem_erase.mpr ⟨hwv', hwv⟩))
    · exact mem_allVars (mem_makeEmptyE.mpr (Or.inr (mem_makeEmptyD.mpr
        (Or.inl ⟨hc, hlhs, hvin⟩)))) (by
          rcases Finset.mem_insert.mp hwc with h | h
          · exact Or.inl h
          · exact Or.inr h)

theorem allVars_makeEmptyE_eq {G : System} {v : Var} (hshape : MkShaped G)
    (hv : mk v ∅ (∅ : Row) ∈ G) (hdefs : ∀ c ∈ G, c.lhs = v → c.conc = ∅) :
    allVars (makeEmptyE v G) = allVars G :=
  Finset.Subset.antisymm (allVars_makeEmptyE_subset hv) (allVars_makeEmptyE_supset hshape hv hdefs)

/-- **`substOut` keeps every variable too.** -/
theorem allVars_substOut_supset {G : System} {v u : Var} (_hlink : mk v {u} (∅ : Row) ∈ G) :
    allVars G ⊆ allVars (substOut v u G) := by
  have hvmem : v ∈ allVars (substOut v u G) :=
    lhs_mem_allVars (mem_substOut.mpr (Or.inl rfl))
  intro w hw
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
  by_cases hinv : c.lhs = v ∨ v ∈ vset c
  · have hmem : substC v u c ∈ substOut v u G :=
      mem_substOut.mpr (Or.inr (Or.inr ⟨c, hc, hinv, rfl⟩))
    by_cases hwv : w = v
    · rw [hwv]; exact hvmem
    · rcases Finset.mem_insert.mp hwc with rfl | hwv'
      · refine mem_allVars hmem (Or.inl ?_)
        rw [substC, lhs_mk, if_neg (by simpa using hwv)]
      · refine mem_allVars hmem (Or.inr ?_)
        rw [substC, vset_mk]
        exact Finset.mem_image.mpr ⟨w, hwv', by rw [if_neg (by simpa using hwv)]⟩
  · push Not at hinv
    exact mem_allVars (mem_substOut.mpr (Or.inr (Or.inl ⟨hc, hinv.1, hinv.2⟩))) (by
      rcases Finset.mem_insert.mp hwc with h | h
      · exact Or.inl h
      · exact Or.inr h)

theorem allVars_substOut_eq {G : System} {v u : Var} (hlink : mk v {u} (∅ : Row) ∈ G) :
    allVars (substOut v u G) = allVars G :=
  Finset.Subset.antisymm (allVars_substOut_subset hlink) (allVars_substOut_supset hlink)

/-! ## 3. R3.2(a): the `empty` branch, factored through `makeEmptyE` -/

/-- **`step_empty_makeEmptyE`, made LOAD-BEARING.**  The `empty` branch's transition is the
LIBRARY OPERATOR followed by one `requeue`, not a bare `requeue`: `sys s` reaches
`makeEmptyE r.lhs (sys s)` by `emptyRemove` and `makeEmptyE r.lhs (sys s)` reaches `sys s'` by
`requeue`.  The `requeue`'s three clauses are composed out of round 2's
`step_noLoss_strict` / `step_conserv_strict` / `step_allVars_strict` and the operator's own
soundness; nothing is re-proved. -/
theorem step_empty_via_makeEmptyE {s s' : State} (hw : Wf s) (hsat : SSat (sys s))
    {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : step s = .continue s') :
    LoopStrict (sys s) (makeEmptyE r.lhs (sys s)) ∧
      LoopStrict (makeEmptyE r.lhs (sys s)) (sys s') ∧
      LoopStrictRun (sys s) (sys s') := by
  have hb : LinkOrEmptyStep s := by
    intro r0 rest0 hd0
    rw [dequeue_unique hdq hd0]
    exact Or.inr (Or.inl hem)
  obtain ⟨hrMem, -⟩ := PQueue.dequeue_mem hdq
  have hvsys : mk r.lhs ∅ (∅ : Row) ∈ sys s := by
    rw [← toConstraint_of_isEmpty hem]; exact mem_sys_of_incm hrMem
  have hdefs := defs_conc_empty_of_sat (mkShaped_sys s) hvsys hsat
  have hop : LoopStrict (sys s) (makeEmptyE r.lhs (sys s)) :=
    step_empty_makeEmptyE hw hdq hfr hem h
  have hnl : NoLoss (sys s) (makeEmptyE r.lhs (sys s)) := hop.no_loss
  have hsnd : ∀ rho, SModels rho (sys s) → SModels rho (makeEmptyE r.lhs (sys s)) :=
    fun _ hm => makeEmptyE_sound hvsys hm
  have hstepNL : NoLoss (sys s) (sys s') := step_noLoss_strict hw hb h
  have hstepCo : Conserv (sys s) (sys s') := step_conserv_strict hw hb h
  have hstepAV : allVars (sys s') ⊆ allVars (sys s) := step_allVars_strict hw hb h
  have hvoc : allVars (sys s') ⊆ allVars (makeEmptyE r.lhs (sys s)) := by
    rw [allVars_makeEmptyE_eq (mkShaped_sys s) hvsys hdefs]; exact hstepAV
  have hcons : Conserv (makeEmptyE r.lhs (sys s)) (sys s') :=
    fun c hc rho hm => hstepCo c hc rho (hnl.models hm)
  have hnl2 : NoLoss (makeEmptyE r.lhs (sys s)) (sys s') :=
    fun c hc rho hm => hsnd rho (hstepNL.models hm) c hc
  refine ⟨hop, LoopStrict.requeue hvoc hcons hnl2, ?_⟩
  exact Relation.ReflTransGen.tail (Relation.ReflTransGen.single hop)
    (LoopStrict.requeue hvoc hcons hnl2)

/-! ## 4. R3.2(b): `replace`'s de-duplication fact, and `instRemove` LIVE

`substOut` collapses the two parts `v` and `u` of a constraint that mentions both into one, so
it loses a fact -- unless the system also knows `u <- ()`, which is exactly the partition
`Constraints.replace` emits in that case (`Loop/Step.lean`'s `replace`, the `abstr.contains v &&
abstr.contains u` arm).  Two observations make `instRemove` live without touching
`Loop/Strict.lean`:

* when no constraint mentions both, nothing collapses and `NoLoss G (substOut v u G)` holds
  outright (`substOut_noLoss_of_disjoint`);
* when one does, `u <- ()` is a CONSEQUENCE of the link and that constraint's disjointness
  (`dedup_entailed`), and it is added by `LoopStrict.dedup` -- the constructor that stands for
  `RHS.merge`'s returned `es` and `replace`'s two-element queue -- so the run
  `G → insert (mk u ∅ ∅) G → substOut v u (insert (mk u ∅ ∅) G)` is a `LoopStrictRun`. -/

/-- Some constraint mentions both `v` and `u`: the case `replace` de-duplicates. -/
def NeedsDedup (v u : Var) (G : System) : Prop := ∃ c ∈ G, v ∈ vset c ∧ u ∈ vset c

/-- **`instantiate`'s removal WITH `replace`'s de-duplication fact.** -/
def substOutD (v u : Var) (G : System) : System := substOut v u (insert (mk u ∅ (∅ : Row)) G)

/-- **The de-duplication fact is a CONSEQUENCE.**  `v` and `u` are parts of one constraint, so
their rows are disjoint; the link makes them equal; so both are empty. -/
theorem dedup_entailed {G : System} {v u : Var} (hshape : MkShaped G) (hvu : v ≠ u)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hnd : NeedsDedup v u G) :
    SEntails G (mk u ∅ (∅ : Row)) := by
  obtain ⟨c, hc, hv, hu⟩ := hnd
  intro rho hm
  have hvu' : rho v = rho u := sat_link_iff.mp (hm _ hlink)
  have hcs : Sat rho (mk c.lhs (vset c) c.conc) := by rw [← hshape c hc]; exact hm c hc
  rw [sat_mk_iff] at hcs
  have hdis := hcs.2.2 v hv u hu hvu
  rw [hvu'] at hdis
  rw [sat_empty_iff]
  exact Finset.eq_empty_of_forall_notMem (fun l hl => Finset.disjoint_left.mp hdis hl hl)

/-- **When nothing collapses, `substOut` loses nothing.** -/
theorem substOut_noLoss_of_disjoint {G : System} {v u : Var} (hshape : MkShaped G)
    (_hlink : mk v {u} (∅ : Row) ∈ G) (hnd : ¬ NeedsDedup v u G) :
    NoLoss G (substOut v u G) := by
  intro c hc rho hm
  have hvu : rho v = rho u := sat_link_iff.mp (hm _ (mem_substOut.mpr (Or.inl rfl)))
  by_cases hinv : c.lhs = v ∨ v ∈ vset c
  · have hmem : substC v u c ∈ substOut v u G :=
      mem_substOut.mpr (Or.inr (Or.inr ⟨c, hc, hinv, rfl⟩))
    have himg := hm _ hmem
    rw [substC] at himg
    rw [hshape c hc]
    refine sat_lhs_congr ?_ (sat_of_replace hvu (fun hv' hu' => ?_) himg)
    · by_cases hl : c.lhs = v
      · rw [if_pos (by simpa using hl), hl]; exact hvu
      · rw [if_neg (by simpa using hl)]
    · exact absurd ⟨c, hc, hv', hu'⟩ hnd
  · push Not at hinv
    exact hm _ (mem_substOut.mpr (Or.inr (Or.inl ⟨hc, hinv.1, hinv.2⟩)))

/-- **With the de-duplication fact present, `substOut` loses nothing.** -/
theorem substOut_noLoss_of_dedup {G : System} {v u : Var} (hshape : MkShaped G)
    (_hlink : mk v {u} (∅ : Row) ∈ G) (hdd : mk u ∅ (∅ : Row) ∈ G) (hvu : v ≠ u) :
    NoLoss G (substOut v u G) := by
  intro c hc rho hm
  have hvu' : rho v = rho u := sat_link_iff.mp (hm _ (mem_substOut.mpr (Or.inl rfl)))
  have hu0 : rho u = ∅ := by
    refine sat_empty_iff.mp (hm _ (mem_substOut.mpr (Or.inr (Or.inl ⟨hdd, ?_, ?_⟩))))
    · rw [lhs_mk]; exact fun hh => hvu hh.symm
    · rw [vset_mk]; exact Finset.notMem_empty v
  by_cases hinv : c.lhs = v ∨ v ∈ vset c
  · have hmem : substC v u c ∈ substOut v u G :=
      mem_substOut.mpr (Or.inr (Or.inr ⟨c, hc, hinv, rfl⟩))
    have himg := hm _ hmem
    rw [substC] at himg
    rw [hshape c hc]
    refine sat_lhs_congr ?_ (sat_of_replace hvu' (fun _ _ => hu0) himg)
    by_cases hl : c.lhs = v
    · rw [if_pos (by simpa using hl), hl]; exact hvu'
    · rw [if_neg (by simpa using hl)]
  · push Not at hinv
    exact hm _ (mem_substOut.mpr (Or.inr (Or.inl ⟨hc, hinv.1, hinv.2⟩)))

theorem mkShaped_insert {G : System} {a : Var} {S : Finset Var} {K : Row}
    (hshape : MkShaped G) : MkShaped (insert (mk a S K) G) := by
  intro c hc
  rcases Finset.mem_insert.mp hc with rfl | hc'
  · rw [lhs_mk, vset_mk, conc_mk]
  · exact hshape c hc'

/-- **`instRemove` is LIVE**, in the case where nothing collapses. -/
theorem instRemove_step {G : System} {v u : Var} (hshape : MkShaped G)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hnd : ¬ NeedsDedup v u G) :
    LoopStrict G (substOut v u G) :=
  LoopStrict.instRemove hlink (substOut_noLoss_of_disjoint hshape hlink hnd)

/-- **`instRemove` is LIVE**, in the case where the de-duplication fact is needed: the run adds
it by `LoopStrict.dedup` first.  `substOutD v u G` is the result -- `substOut` of the system
that knows `u <- ()`. -/
theorem instRemove_step_dedup {G : System} {v u : Var} (hshape : MkShaped G) (hvu : v ≠ u)
    (hlink : mk v {u} (∅ : Row) ∈ G) (hnd : NeedsDedup v u G) :
    LoopStrictRun G (substOutD v u G) := by
  obtain ⟨c, hc, hv, hu⟩ := hnd
  have hstep1 : LoopStrict G (insert (mk u ∅ (∅ : Row)) G) := by
    refine LoopStrict.dedup (c := c.lhs) (v := v) (x := u) (S := vset c) (S' := {u})
      (K := c.conc) (K' := (∅ : Row)) ?_ hlink hv ?_ ?_
    · rw [← hshape c hc]; exact hc
    · exact Finset.mem_erase.mpr ⟨fun hh => hvu hh.symm, hu⟩
    · exact Finset.mem_singleton_self u
  have hG1 : MkShaped (insert (mk u ∅ (∅ : Row)) G) := mkShaped_insert hshape
  have hlink1 : mk v {u} (∅ : Row) ∈ insert (mk u ∅ (∅ : Row)) G :=
    Finset.mem_insert_of_mem hlink
  have hdd1 : mk u ∅ (∅ : Row) ∈ insert (mk u ∅ (∅ : Row)) G := Finset.mem_insert_self _ _
  exact Relation.ReflTransGen.tail (Relation.ReflTransGen.single hstep1)
    (LoopStrict.instRemove hlink1 (substOut_noLoss_of_dedup hG1 hlink1 hdd1 hvu))

/-! ## 5. The `unify` branch, factored through `substOut`

At the `unify` branch the dequeued partition IS the link `r.lhs <- (u)` and the loop
instantiates `u := r.lhs`, so the relation reads the link BACKWARDS (`linkSymm`, R2.5 row 5)
before the elimination.  The elimination is then `instRemove`, applied. -/

/-- **The `unify` branch's transition, factored.**  `sys s` reaches the operator's output by
`linkSymm` (plus `dedup` where `replace` de-duplicates) and `instRemove`; the operator's output
reaches `sys s'` by one `requeue`. -/
theorem step_unify_via_substOut {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    {u : Nat} (hdq : s.incm.dequeue = some (r, rest)) (_hfr : s.proc.findRHS r.rhs = none)
    (hsg : r.rhs.single? = some u) (hur : u ≠ r.lhs) (h : step s = .continue s') :
    ∃ H : System, LoopStrictRun (sys s) H ∧ LoopStrict H (sys s') ∧
      allVars H = allVars (sys s) ∧
      (H = substOut u r.lhs (insert (mk u {r.lhs} (∅ : Row)) (sys s)) ∨
        H = substOutD u r.lhs (insert (mk u {r.lhs} (∅ : Row)) (sys s))) := by
  have hb : LinkOrEmptyStep s := by
    intro r0 rest0 hd0
    rw [dequeue_unique hdq hd0]
    exact Or.inr (Or.inr (by rw [hsg]; simp))
  obtain ⟨hrMem, -⟩ := PQueue.dequeue_mem hdq
  have hrc : r.toConstraint = mk r.lhs {u} (∅ : Row) := toConstraint_of_single hsg
  have hrsys : mk r.lhs {u} (∅ : Row) ∈ sys s := by rw [← hrc]; exact mem_sys_of_incm hrMem
  set G1 : System := insert (mk u {r.lhs} (∅ : Row)) (sys s) with hG1def
  have hsym : LoopStrict (sys s) G1 := LoopStrict.linkSymm hrsys
  have hG1shape : MkShaped G1 := mkShaped_insert (mkShaped_sys s)
  have hlink1 : mk u {r.lhs} (∅ : Row) ∈ G1 := Finset.mem_insert_self _ _
  have hG1voc : allVars G1 = allVars (sys s) := by
    refine Finset.Subset.antisymm ?_ (allVars_mono (Finset.subset_insert _ _))
    refine allVars_insert_subset ?_ ?_
    · rw [lhs_mk]
      exact mem_allVars hrsys (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self u))
    · rw [vset_mk]
      intro w hw
      rw [Finset.mem_singleton] at hw; subst hw
      exact lhs_mem_allVars hrsys
  -- the tail: whatever `H` the elimination reaches, one `requeue` carries it to `sys s'`
  have htail : ∀ H : System, LoopStrictRun (sys s) H → NoLoss (sys s) H →
      (∀ rho, SModels rho (sys s) → SModels rho H) → allVars H = allVars (sys s) →
      LoopStrict H (sys s') := by
    intro H hrun hnl hsnd hvoc
    have hstepNL : NoLoss (sys s) (sys s') := step_noLoss_strict hw hb h
    have hstepCo : Conserv (sys s) (sys s') := step_conserv_strict hw hb h
    have hstepAV : allVars (sys s') ⊆ allVars (sys s) := step_allVars_strict hw hb h
    exact LoopStrict.requeue (by rw [hvoc]; exact hstepAV)
      (fun c hc rho hm => hstepCo c hc rho (hnl.models hm))
      (fun c hc rho hm => hsnd rho (hstepNL.models hm) c hc)
  by_cases hnd : NeedsDedup u r.lhs G1
  · have hrun : LoopStrictRun (sys s) (substOutD u r.lhs G1) :=
      (Relation.ReflTransGen.single hsym).trans
        (instRemove_step_dedup hG1shape hur hlink1 hnd)
    have hddE : SEntails G1 (mk r.lhs ∅ (∅ : Row)) := dedup_entailed hG1shape hur hlink1 hnd
    have hG2voc : allVars (insert (mk r.lhs ∅ (∅ : Row)) G1) = allVars G1 := by
      refine Finset.Subset.antisymm ?_ (allVars_mono (Finset.subset_insert _ _))
      refine allVars_insert_subset ?_ ?_
      · rw [lhs_mk]
        exact mem_allVars hlink1 (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self _))
      · rw [vset_mk]; exact fun w hw => absurd hw (Finset.notMem_empty w)
    have hvocH : allVars (substOutD u r.lhs G1) = allVars (sys s) := by
      rw [substOutD, allVars_substOut_eq (Finset.mem_insert_of_mem hlink1), hG2voc, hG1voc]
    refine ⟨substOutD u r.lhs G1, hrun, ?_, hvocH, Or.inr rfl⟩
    refine htail _ hrun hrun.no_loss ?_ hvocH
    intro rho hm
    have hm1 : SModels rho G1 := by
      intro c hc
      rcases Finset.mem_insert.mp hc with rfl | hc'
      · exact linkSymm_sat (hm _ hrsys)
      · exact hm c hc'
    have hm2 : SModels rho (insert (mk r.lhs ∅ (∅ : Row)) G1) := by
      intro c hc
      rcases Finset.mem_insert.mp hc with rfl | hc'
      · exact hddE rho hm1
      · exact hm1 c hc'
    exact substOut_sound (Finset.mem_insert_of_mem hlink1) rho hm2
  · have hrun : LoopStrictRun (sys s) (substOut u r.lhs G1) :=
      Relation.ReflTransGen.tail (Relation.ReflTransGen.single hsym)
        (instRemove_step hG1shape hlink1 hnd)
    have hvocH : allVars (substOut u r.lhs G1) = allVars (sys s) := by
      rw [allVars_substOut_eq hlink1]; exact hG1voc
    refine ⟨substOut u r.lhs G1, hrun, ?_, hvocH, Or.inl rfl⟩
    refine htail _ hrun hrun.no_loss ?_ hvocH
    intro rho hm
    have hm1 : SModels rho G1 := by
      intro c hc
      rcases Finset.mem_insert.mp hc with rfl | hc'
      · exact linkSymm_sat (hm _ hrsys)
      · exact hm c hc'
    exact substOut_sound hlink1 rho hm1

/-! ## 6. The `common` branch, factored the same way

At the `common` branch the link `r.lhs <- (u)` is NOT in `sys s`: it is what
`NonGenStep.commonPart` derives from the dequeued `r` and the `proc` partition whose right-hand
side `findRHS` matched.  So the run takes one ADDITIVE rule step first and is otherwise
identical to `step_unify_via_substOut`. -/

/-- **The `common` branch's transition, factored.**  `sys s` reaches the operator's output by
`nongen` (common partition), then `instRemove` (with `dedup` where `replace` de-duplicates);
the operator's output reaches `sys s'` by one `requeue`. -/
theorem step_common_via_substOut {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    {u : Nat} (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some u)
    (hru : r.lhs ≠ u) (h : step s = .continue s') :
    ∃ H : System, LoopStrictRun (sys s) H ∧ LoopStrict H (sys s') ∧
      allVars H = allVars (sys s) ∧
      (H = substOut r.lhs u (insert (mk r.lhs {u} (∅ : Row)) (sys s)) ∨
        H = substOutD r.lhs u (insert (mk r.lhs {u} (∅ : Row)) (sys s))) := by
  have hb : LinkOrEmptyStep s := by
    intro r0 rest0 hd0
    rw [dequeue_unique hdq hd0]
    exact Or.inl (by rw [hfr]; simp)
  obtain ⟨hrOk, -⟩ := QOk.dequeue hw.incm hdq
  obtain ⟨hrMem, -⟩ := PQueue.dequeue_mem hdq
  obtain ⟨x, hx, hxeq, hxl⟩ := findRHS_witness hfr
  have hxc : x.toConstraint = (⟨x.lhs, r.rhs, none⟩ : LPart).toConstraint :=
    toConstraint_congr hw.coh (hw.proc x hx) hrOk hxeq
  have hxvset : vset x.toConstraint = vset r.toConstraint := by
    rw [hxc]; rfl
  have hxconc : x.toConstraint.conc = r.toConstraint.conc := by
    rw [hxc]; rfl
  have happ : CommonPartApp (sys s) r.toConstraint x.toConstraint :=
    { mem₁ := mem_sys_of_incm hrMem
      mem₂ := mem_sys_of_proc hx
      lhs_ne := by
        simp only [LPart.lhs_toConstraint]
        rw [hxl]; exact hru
      vset_eq := hxvset.symm
      conc_eq := hxconc.symm }
  have hcp : LoopStrict (sys s) (insert (mk r.lhs {u} (∅ : Row)) (sys s)) := by
    have := LoopStrict.nongen (NonGenStep.commonPart (CommonPartStep.intro happ))
    simpa only [commonPartResult, LPart.lhs_toConstraint, hxl] using this
  set G1 : System := insert (mk r.lhs {u} (∅ : Row)) (sys s) with hG1def
  have hG1shape : MkShaped G1 := mkShaped_insert (mkShaped_sys s)
  have hlink1 : mk r.lhs {u} (∅ : Row) ∈ G1 := Finset.mem_insert_self _ _
  have hrV : r.lhs ∈ allVars (sys s) := lhs_mem_allVars (mem_sys_of_incm hrMem)
  have huV : u ∈ allVars (sys s) := by
    rw [← hxl]; exact lhs_mem_allVars (mem_sys_of_proc hx)
  have hG1voc : allVars G1 = allVars (sys s) := by
    refine Finset.Subset.antisymm ?_ (allVars_mono (Finset.subset_insert _ _))
    refine allVars_insert_subset (by rw [lhs_mk]; exact hrV) ?_
    rw [vset_mk]
    intro w hw'
    rw [Finset.mem_singleton] at hw'; subst hw'
    exact huV
  have hlinkSat : ∀ rho, SModels rho (sys s) → SModels rho G1 := by
    intro rho hm c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · have := commonPart_sat (hm _ happ.mem₁) (hm _ happ.mem₂) happ.vset_eq happ.conc_eq
      simpa only [LPart.lhs_toConstraint, hxl] using this
    · exact hm c hc'
  have htail : ∀ H : System, NoLoss (sys s) H →
      (∀ rho, SModels rho (sys s) → SModels rho H) → allVars H = allVars (sys s) →
      LoopStrict H (sys s') := by
    intro H hnl hsnd hvoc
    exact LoopStrict.requeue (by rw [hvoc]; exact step_allVars_strict hw hb h)
      (fun c hc rho hm => step_conserv_strict hw hb h c hc rho (hnl.models hm))
      (fun c hc rho hm => hsnd rho ((step_noLoss_strict hw hb h).models hm) c hc)
  by_cases hnd : NeedsDedup r.lhs u G1
  · have hrun : LoopStrictRun (sys s) (substOutD r.lhs u G1) :=
      (Relation.ReflTransGen.single hcp).trans
        (instRemove_step_dedup hG1shape hru hlink1 hnd)
    have hddE : SEntails G1 (mk u ∅ (∅ : Row)) := dedup_entailed hG1shape hru hlink1 hnd
    have hG2voc : allVars (insert (mk u ∅ (∅ : Row)) G1) = allVars G1 := by
      refine Finset.Subset.antisymm ?_ (allVars_mono (Finset.subset_insert _ _))
      refine allVars_insert_subset ?_ ?_
      · rw [lhs_mk]
        exact mem_allVars hlink1 (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self _))
      · rw [vset_mk]; exact fun w hw' => absurd hw' (Finset.notMem_empty w)
    have hvocH : allVars (substOutD r.lhs u G1) = allVars (sys s) := by
      rw [substOutD, allVars_substOut_eq (Finset.mem_insert_of_mem hlink1), hG2voc, hG1voc]
    refine ⟨substOutD r.lhs u G1, hrun, ?_, hvocH, Or.inr rfl⟩
    refine htail _ hrun.no_loss ?_ hvocH
    intro rho hm
    have hm1 := hlinkSat rho hm
    have hm2 : SModels rho (insert (mk u ∅ (∅ : Row)) G1) := by
      intro c hc
      rcases Finset.mem_insert.mp hc with rfl | hc'
      · exact hddE rho hm1
      · exact hm1 c hc'
    exact substOut_sound (Finset.mem_insert_of_mem hlink1) rho hm2
  · have hrun : LoopStrictRun (sys s) (substOut r.lhs u G1) :=
      Relation.ReflTransGen.tail (Relation.ReflTransGen.single hcp)
        (instRemove_step hG1shape hlink1 hnd)
    have hvocH : allVars (substOut r.lhs u G1) = allVars (sys s) := by
      rw [allVars_substOut_eq hlink1]; exact hG1voc
    refine ⟨substOut r.lhs u G1, hrun, ?_, hvocH, Or.inl rfl⟩
    refine htail _ hrun.no_loss ?_ hvocH
    intro rho hm
    exact substOut_sound hlink1 rho (hlinkSat rho hm)

end Rowpartition.Loop
