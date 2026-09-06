/-
# L5 round 7: the VOCABULARY-FIXED fragment

Round 6 proved `Terminates` for the no-concrete-labels fragment (`Loop/NoConc.lean`), which
covers every row-constraint solve the standard library performs and a quarter of the example
corpus.  The round-6 review (W-9) measured what the next fragment can be worth and refuted the
naive widening: "neither generative rule can fire on the INPUT" is NOT closed under `step` --
111 example solves fire a rule anyway, unblocked by a partition `substitution` or
`commonSubexpression` derived.  The honest target it names is the VOCABULARY-FIXED condition,
"no id ever enters a partition", worth 97.6 % of the example corpus.

This module proves termination for that condition.  Three things have to be replaced, and they
are exactly where `NoConc` was used beyond fixing the vocabulary:

1. the LABEL bound.  `procSys_card_le` and `kdist_length_le` used `conc = []` to make
   `(lhs, abstract parts)` a separating map; with labels the map has to carry the concrete
   part and the bound picks up a `2^|L|` factor.  So the loop must be shown not to invent a
   label -- which §1 gets for free from L3's refinement, because every `LoopRel` constructor
   preserves `ConcSub`;
2. the VOCABULARY clause for `learn`.  `learnPartitions_avoidsV` needed
   `rhs1.conc.elems = []` and `rhs1.abstrSingle? = none` to kill `splitConcrete` and
   `resolution`.  §2 replaces both by the hypothesis that the step DRAWS NO ID, which is what
   the corpus condition is;
3. the `concrete` dispatch branch, which `step_trichotomy` discharged by `exfalso`.  §4 finds
   what decreases on it: `makeConcrete v fs` leaves `v <- ((|fs|))` in the processed queue,
   `ensureSuperset` forces every concrete row of `v` already present to be a SUBSET of `fs`,
   and the dispatch's own `findRHS` miss forces it to be a PROPER subset -- so the
   downward-closed set of `(variable, concrete row)` pairs the processed queue carries
   strictly grows, and it is bounded by `|V| · 2^|L|`.
-/
import Rowpartition.Loop.NoConc

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. The loop invents no label

`Loop/Refine.lean`'s `step_refines_all` gives `LoopRun (sys s) (sys s')` for every dispatch
branch.  Every one of `LoopRel`'s eleven constructors emits concrete parts built from the
premises' -- union, difference, or none at all -- so `ConcSub L` transports along the whole
refinement, and the label vocabulary of a solve is its input's.  No new rule analysis is
needed: the four calculus constructors already have their `concSub` lemmas, `weaken` is
deletion, and the five loop-specific ones emit `mk _ _ K` with `K` a premise's row or `∅`. -/

/-- `Cut.ResStep` invents no label: it emits `C ∪ D`, `D \ C` and `C \ D`.  (`GResStep`'s
mint branch, which `ResGuardTerm.GResStep.concSub` proves, at the unguarded rule.) -/
theorem ResStep.concSub {L : Finset Label} {G G' : System} (h : ResStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro v x y C D z hp =>
    have hC : C ⊆ L := hcs _ hp.mem₁
    have hD : D ⊆ L := hcs _ hp.mem₂
    intro c hc
    simp only [resResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | rfl | hc
    · exact Finset.union_subset hC hD
    · exact Finset.sdiff_subset.trans hD
    · exact Finset.sdiff_subset.trans hC
    · exact hcs c hc

/-- **One abstract loop step invents no label.** -/
theorem LoopRel.concSub {L : Finset Label} {G G' : System} (h : LoopRel G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | nongen h => exact NonGenStep.concSub h hcs
  | split h => exact KeyedRow.K2SplitStep.concSub h hcs
  | res h => exact ResStep.concSub h hcs
  | splitFree h => exact SplitStep.concSub h hcs
  | kres h => exact KeyedRow.K2ResStep.concSub h hcs
  | weaken h => exact hcs.mono h
  | @renameLhs a b S K hmem _ =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc
    · rw [conc_mk]; simpa only [conc_mk] using hcs _ hmem
    · exact hcs c hc
  | @linkSymm a b _ =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc
    · simp
    · exact hcs c hc
  | @emptyProp a x S _ _ _ =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc
    · simp
    · exact hcs c hc
  | @dedup cc v x S S' K K' _ _ _ _ _ =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc
    · simp
    · exact hcs c hc

/-- ...and therefore a whole run of them. -/
theorem LoopRun.concSub {L : Finset Label} {G G' : System} (h : LoopRun G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  induction h with
  | refl => exact hcs
  | tail _ hstep ih => exact LoopRel.concSub hstep ih

/-- The flags never move along a run. -/
theorem reaches_flags_eq {s t : State} (hr : Reaches s t) : t.flags = s.flags := by
  induction hr with
  | refl => rfl
  | tail _ hstep ih => rw [step_flags hstep, ih]

/-- **The step invents no label.**  `step_refines_all`'s hypotheses are the shipped flags and
L3's supply invariant, both of which travel along a run (`reaches_invariants`). -/
theorem step_concSub {L : Finset Label} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (hcs : ConcSub L (sys s)) (h : step s = .continue s') : ConcSub L (sys s') :=
  LoopRun.concSub (step_refines_all hw hem hdj hcse hok hfr h) hcs

/-- ...and therefore every state a run reaches has the input's labels. -/
theorem reaches_concSub {L : Finset Label} {s t : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hcs : ConcSub L (sys s)) (hr : Reaches s t) : ConcSub L (sys t) := by
  induction hr with
  | refl => exact hcs
  | @tail t0 u0 hr0 hstep ih =>
    obtain ⟨hdj0, hcse0, hok0, hfr0, -⟩ := reaches_invariants hdj hcse hok hfr h0 hr0
    have hem0 : t0.flags.emptyRow = false := by
      rw [reaches_flags_eq hr0]; exact hem
    exact step_concSub (reaches_wf hw hr0) hem0 hdj0 hcse0 hok0 hfr0 ih hstep

/-- A state's own labels bound it, so `L` is not an assumption either: it is
`labelsOf (sys s)` of the initial state. -/
theorem concSub_self (s : State) : ConcSub (labelsOf (sys s)) (sys s) := labelsOf_concSub _

/-! ## 2. The two counting bounds, with labels

`NoConc.lean`'s `procSys_card_le` and `kdist_length_le` used `conc = []` to land in
`forms V ∅` and to make `(lhs, abstract parts)` a separating map.  With `ConcSub L` in hand
both go through at `forms V L`, and the separating map is `LPart.toConstraint` itself --
`Wf.LPart.eqv_iff_toConstraint_of_wf` says `Partition.equals` IS equality of the constraint,
with no side conditions, for two partitions of a well-formed state. -/

/-- Every partition of the state is one of the `|V| · 2^|V| · 2^|L|` shapes. -/
theorem toConstraint_mem_formsL {V : Finset Var} {L : Finset Label} {s : State} {p : LPart}
    (hv : InVoc V s) (hcs : ConcSub L (sys s)) (hp : p ∈ s.parts) :
    p.toConstraint ∈ forms V L := by
  have hpA := avoids_toConstraint_iff.mp (hv.1 p hp)
  rw [mem_forms]
  refine ⟨isCanonical_mk _ _ _, ?_, ?_, hcs _ (mem_sys_of_part hp)⟩
  · simpa [LPart.toConstraint] using not_not.mp hpA.1
  · intro w hw
    simp only [LPart.toConstraint, vset_mk, List.mem_toFinset] at hw
    exact not_not.mp (hpA.2 w hw)

theorem procSys_subset_formsL {V : Finset Var} {L : Finset Label} {s : State}
    (hv : InVoc V s) (hcs : ConcSub L (sys s)) : procSys s ⊆ forms V L := by
  intro c hc
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hc)
  exact toConstraint_mem_formsL hv hcs (List.mem_append_right _ hp)

/-- **Bound two, with labels.** -/
theorem procSys_card_leL {V : Finset Var} {L : Finset Label} {s : State}
    (hv : InVoc V s) (hcs : ConcSub L (sys s)) :
    (procSys s).card ≤ V.card * 2 ^ V.card * 2 ^ L.card :=
  le_trans (Finset.card_le_card (procSys_subset_formsL hv hcs)) (card_forms_le V L)

/-- **Bound three, with labels.**  The queue's own de-duplication (`KDist`) makes
`LPart.toConstraint` injective on any sublist of the state's partitions. -/
theorem kdist_length_leL {V : Finset Var} {L : Finset Label} {s : State} {l : List LPart}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s))
    (hsub : ∀ p ∈ l, p ∈ s.parts) (hk : KDist l) :
    l.length ≤ V.card * 2 ^ V.card * 2 ^ L.card := by
  have hnd : (l.map LPart.toConstraint).Nodup := by
    rw [List.Nodup, List.pairwise_map]
    refine List.Pairwise.imp_of_mem ?_ hk
    intro a b ha hb hab heq
    have hwa := hw.nodup (hsub a ha)
    have hwb := hw.nodup (hsub b hb)
    have hab1 : a.eqv b = true :=
      (LPart.eqv_iff_toConstraint_of_wf hw (hsub a ha) (hsub b hb)).mpr heq
    have hab2 : b.eqv a = true :=
      (LPart.eqv_iff_toConstraint_of_wf hw (hsub b hb) (hsub a ha)).mpr heq.symm
    rcases hab with hr | hr
    · rw [keyEq_of_eqv hwa.1 hwa.2 hwb.1 hwb.2 hab1, hab1] at hr; simp at hr
    · rw [keyEq_of_eqv hwb.1 hwb.2 hwa.1 hwa.2 hab2, hab2] at hr; simp at hr
  have hmem : ∀ x ∈ (l.map LPart.toConstraint).toFinset, x ∈ forms V L := by
    intro x hx
    obtain ⟨p, hp, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hx)
    exact toConstraint_mem_formsL hv hcs (hsub p hp)
  calc l.length = (l.map LPart.toConstraint).length := by simp
    _ = (l.map LPart.toConstraint).toFinset.card := (List.toFinset_card_of_nodup hnd).symm
    _ ≤ (forms V L).card := Finset.card_le_card hmem
    _ ≤ V.card * 2 ^ V.card * 2 ^ L.card := card_forms_le V L

/-! ## 3. The vocabulary, when the loop draws no id

`NoConc.lean`'s `learnPartitions_avoidsV` killed `splitConcrete` by `concr.isEmpty` and
`resolution` by `rhs1.abstrSingle? = none`.  Neither is available with labels: the dequeued
premise of a `learn` step may be `v <- (x, (|C|))`, which is not `single?` and IS
`abstrSingle?`, and that is exactly the shape the round-6 review's 111 solves have.  What
replaces both is the hypothesis that the STEP DREW NO ID, which is the corpus condition and
which the model reports per solve.

`resolution` draws inside the lone-variable arm and BEFORE its guards, so "it did not draw"
already says "it returned nothing"; `splitConcrete` draws only in its last branch, so "it did
not draw" says "it took a reuse branch", and every reuse branch names a variable one of the
three lookups produced. -/

/-- Drawing moves `drawn`. -/
theorem fresh_drawn_ne (su : Sup) : (su.fresh).2.drawn ≠ su.drawn := by
  rw [fresh_drawn]; omega

/-- **`resolution` that does not draw returns nothing.**  The `fresh` sits before the
intersection test and before all three reuse lookups (`Constraints.scala:1772`), so the only
way past the lone-variable pattern costs an id. -/
theorem resolution_noDraw {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2.drawn = su.drawn) :
    (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).1 = SSet.empty := by
  revert h
  simp only [resolution]
  split
  · exact fun _ => rfl
  · split
    · have hd := fresh_drawn su
      split
      · exact fun hh => absurd (hd ▸ hh) (by omega)
      · split
        · exact fun hh => absurd (hd ▸ hh) (by omega)
        · split
          · exact fun hh => absurd (hd ▸ hh) (by omega)
          · split
            · exact fun hh => absurd (hd ▸ hh) (by omega)
            · exact fun hh => absurd (hd ▸ hh) (by omega)
    · exact fun _ => rfl

/-- `resolution` never gives an id back. -/
theorem resolution_drawn_ge {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    su.drawn ≤ (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2.drawn := by
  simp only [resolution]
  split
  · exact Nat.le_refl _
  · split
    · have hd : (su.fresh).2.drawn = su.drawn + 1 := fresh_drawn su
      split
      · exact hd ▸ Nat.le_succ _
      · split
        · exact hd ▸ Nat.le_succ _
        · split
          · exact hd ▸ Nat.le_succ _
          · split
            · exact hd ▸ Nat.le_succ _
            · exact hd ▸ Nat.le_succ _
    · exact Nat.le_refl _

/-- ...nor does `splitConcrete`. -/
theorem splitConcrete_drawn_ge {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    su.drawn ≤ (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2.drawn := by
  unfold splitConcrete
  split
  · exact Nat.le_refl _
  · split
    · exact Nat.le_refl _
    · split
      · exact Nat.le_refl _
      · split
        · exact Nat.le_refl _
        · split
          · exact Nat.le_refl _
          · split
            · exact Nat.le_refl _
            · split
              rename_i u su2 hfr
              have hd := fresh_drawn su
              rw [hfr] at hd
              rw [hd]
              exact Nat.le_succ _

/-- **`splitConcrete` that does not draw names only what the lookups gave it.**  The mint is
the last of five branches and the only one that calls `fresh`; the other four emit `v`, the
premise's abstract parts, and a variable one of `rhss` / `resolvent` / `concRow` returned.
This is `Hygiene.splitConcrete_avoids` with the `SupAvoids B su` hypothesis -- which a
vocabulary bound cannot have, since a fresh id is by definition outside `V` -- traded for
"the call did not draw". -/
theorem splitConcrete_avoidsV {B : Var → Prop} {fl : Flags} {v : Nat} {abstr : SSet Nat}
    {concr : SSet Lbl} {rhss : RHS → Option Nat}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hv : ¬ B v) (ha : ∀ w ∈ abstr.elems, ¬ B w)
    (hr : ∀ r w, rhss r = some w → ¬ B w)
    (hres : ∀ k w, resolvent k = some w → ¬ B w)
    (hcr : ∀ k w, concRow k = some w → ¬ B w)
    (hnd : (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2.drawn
             = su.drawn) :
    ∀ x ∈ (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).1.elems,
      Avoids B x.toConstraint := by
  have hone : ∀ (u : Nat), ¬ B u → ∀ w ∈ (SSet.ofList [u] : SSet Nat).elems, ¬ B w := by
    intro u hu w hw
    have := SSet.mem_ofList hw
    rw [List.mem_singleton] at this
    subst this; exact hu
  revert hnd
  unfold splitConcrete
  split
  · exact fun _ x hx => absurd hx (by simp [SSet.empty])
  · split
    · rename_i u hu
      refine fun _ x hx => ?_
      have hx' := SSet.mem_ofList hx
      rw [List.mem_singleton] at hx'
      subst hx'
      exact avoids_mk_of hv (hone u (hr _ _ hu))
    · split
      · exact fun _ x hx => absurd hx (by simp [SSet.empty])
      · split
        · rename_i w hw
          refine fun _ x hx => ?_
          have hx' := SSet.mem_ofList hx
          rw [List.mem_singleton] at hx'
          subst hx'
          have hwB : ¬ B w := by
            split at hw
            · exact hres _ _ hw
            · exact absurd hw (by simp)
          exact avoids_mk_of hwB (by simpa [RHS.ofAbstr] using ha)
        · split
          · rename_i w hw
            refine fun _ x hx => ?_
            have hx' := SSet.mem_ofList hx
            rw [List.mem_singleton] at hx'
            subst hx'
            have hwB : ¬ B w := by
              split at hw
              · exact hcr _ _ hw
              · exact absurd hw (by simp)
            exact avoids_mk_of hwB (by simpa [RHS.ofAbstr] using ha)
          · split
            · refine fun _ x hx => ?_
              obtain ⟨w, hw, rfl⟩ := SSet.mem_map hx
              exact avoids_empty_rhs (ha w hw)
            · split
              rename_i u su2 hfr
              have hd := fresh_drawn su
              rw [hfr] at hd
              exact fun hbad => absurd (hd ▸ hbad) (by omega)

/-- **The vocabulary clause for the `learn` branch, when the step draws no id.**  Every
partition `learnPartitions` derives mentions only variables the premises already mention.
The fold carries two facts: the supply's `drawn` never goes down, and while it has not moved
every partition derived so far is over the old vocabulary -- so the hypothesis "the whole
call drew nothing" propagates backwards to every one of its rule applications. -/
theorem learnPartitions_avoidsV_noDraw {B : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hv : ¬ B v) (hr1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su'))
    (hnd : su'.drawn = su.drawn) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  have hlk : LkAvoids B (mkLookups v incm proc) := mkLookups_avoids hi hp
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, hS0, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    exact selfSubstitution_avoids hr1 hS0
  · refine (foldl_except_inv
        (P := fun (a : SSet LPart × Sup) =>
          su.drawn ≤ a.2.drawn ∧
            (a.2.drawn = su.drawn → ∀ x ∈ a.1.elems, Avoids B x.toConstraint))
        (Q := fun (x : LPart) => Avoids B x.toConstraint) ?_ _ hp _ ?_ _ h).2 hnd
    · intro acc p2 hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        obtain ⟨haD, haA⟩ := hacc _ hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        have hp2A := avoids_toConstraint_iff.mp hp2
        split at hb
        · -- resolution / cancellation
          cases hres : resolution fl v rhs1 p2.rhs
              (fun k => findResolvent v (mkLookups v incm proc) aS k)
              (fun k => if fl.splitRow || fl.resRow then
                findConcRow (mkLookups v incm proc) k else none)
              (fun k => if fl.emptyRow then
                findEmptyRow env (mkLookups v incm proc) k else none) asu with
          | mk rps nsu =>
            have hge : asu.drawn ≤ nsu.drawn := by
              have := resolution_drawn_ge (fl := fl) (v := v) (rhs1 := rhs1) (rhs2 := p2.rhs)
                (resolvent := fun k => findResolvent v (mkLookups v incm proc) aS k)
                (concRow := fun k => if fl.splitRow || fl.resRow then
                  findConcRow (mkLookups v incm proc) k else none)
                (emptyRow := fun k => if fl.emptyRow then
                  findEmptyRow env (mkLookups v incm proc) k else none) (su := asu)
              rw [hres] at this; exact this
            rw [hres] at hb
            simp only [hdj, Bool.not_false, if_true, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            refine ⟨(le_trans haD hge : su.drawn ≤ nsu.drawn), fun hz => ?_⟩
            have hz' : nsu.drawn = su.drawn := hz
            have hasu : asu.drawn = su.drawn := Nat.le_antisymm (hz' ▸ hge) haD
            have hemp : rps = SSet.empty := by
              have hnd' : (resolution fl v rhs1 p2.rhs
                  (fun k => findResolvent v (mkLookups v incm proc) aS k)
                  (fun k => if fl.splitRow || fl.resRow then
                    findConcRow (mkLookups v incm proc) k else none)
                  (fun k => if fl.emptyRow then
                    findEmptyRow env (mkLookups v incm proc) k else none) asu).2.drawn
                    = asu.drawn := by rw [hres]; exact hz'.trans hasu.symm
              have := resolution_noDraw hnd'
              rw [hres] at this; exact this
            intro x hx
            rcases SSet.mem_concat hx with hx' | hx'
            · rcases SSet.mem_concat hx' with hx'' | hx''
              · rcases SSet.mem_concat hx'' with hx3 | hx3
                · exact haA hasu x hx3
                · rw [hemp] at hx3; exact absurd hx3 (by simp [SSet.empty])
              · exact cancellation_avoids (B := B) (v := v) hr1 hp2A.2 x hx''
            · exact absurd hx' (by simp [SSet.empty])
        · -- commonSubexpression / substitution
          have hcs : (commonSubexpression fl v rhs1 p2.lhs p2.rhs
              (fun r => findRHS3 incm proc aS r) asu).2 = asu :=
            commonSubexpression_su_of_cut hcse
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m => rw [hsub] at hb; simp only [] at hb; exact absurd hb (by simp)
          | ok sps =>
            rw [hsub] at hb
            simp only [hdj, Bool.not_false, if_true, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            refine ⟨(by rw [hcs]; exact haD :
              su.drawn ≤ (commonSubexpression fl v rhs1 p2.lhs p2.rhs
                (fun r => findRHS3 incm proc aS r) asu).2.drawn), fun hz => ?_⟩
            have hz0 : (commonSubexpression fl v rhs1 p2.lhs p2.rhs
                (fun r => findRHS3 incm proc aS r) asu).2.drawn = su.drawn := hz
            have hz' : asu.drawn = su.drawn := by rw [hcs] at hz0; exact hz0
            have hcc := commonSubexpression_avoids_cut (B := B) (fl := fl) (v := v) (rhs1 := rhs1)
              (u := p2.lhs) (rhs2 := p2.rhs) (rhss := fun r => findRHS3 incm proc aS r)
              (su := asu) hcse hv hp2A.1 hr1 hp2A.2
              (fun r w hw => findRHS3_avoids hi hp (fun x hx => haA hz' x hx) hw)
            intro x hx
            rcases SSet.mem_concat hx with hx' | hx'
            · rcases SSet.mem_concat hx' with hx'' | hx''
              · rcases SSet.mem_concat hx'' with hx3 | hx3
                · exact haA hz' x hx3
                · exact hcc x hx3
              · exact substitution_avoids (B := B) hv hp2A.1 hr1 hp2A.2 hsub x hx''
            · exact absurd hx' (by simp [SSet.empty])
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      exact ⟨splitConcrete_drawn_ge, fun hz =>
        splitConcrete_avoidsV hv hr1 (fun r w hw => findRHS3_avoids hi hp
            (fun x hx => absurd hx (by simp [SSet.empty])) hw)
          (fun k w hw => findResolvent_avoids hlk
            (fun x hx => absurd hx (by simp [SSet.empty])) hw)
          (fun k w hw => by
            split at hw
            · exact findConcRow_avoids hlk hw
            · exact absurd hw (by simp)) hz⟩

/-- **The vocabulary does not grow at a step that draws no id.**  All five dispatch branches,
including `concrete`, which `NoConc.step_inVoc` discharged by `exfalso`: `makeConcrete` builds
`cancellation`s of the dequeued row against `v`'s own definitions and re-expresses the rest by
`destructiveSub`, and `Hygiene.makeConcrete_avoids` already covers it at any `B`. -/
theorem step_inVoc_noDraw {V : Finset Var} {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h0 : InVoc V s)
    (h : step s = .continue s') (hnd : s'.su.drawn = s.su.drawn) : InVoc V s' := by
  obtain ⟨h0p, h0e⟩ := h0
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
    fun x hx => h0p x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
    fun x hx => h0p x (List.mem_append_right _ hx)
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (PQueue.dequeue_mem hdq).1
    have hrest : ∀ x ∈ rest.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
      fun x hx => hi0 x ((PQueue.dequeue_mem hdq).2 x hx)
    have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
    have hfin : ∀ {ni np : PQueue} {e : Env},
        (∀ x ∈ ni.elems, Avoids (fun w => w ∉ V) x.toConstraint) →
        (∀ x ∈ np.elems, Avoids (fun w => w ∉ V) x.toConstraint) →
        (∀ b ∈ e.binds, Avoids (fun w => w ∉ V) (EnvVal.toConstraint b.1 b.2)) →
        InVoc V { incm := ni, proc := np, env := e, su := s.su, trace := s.trace,
                  flags := s.flags, names := s.names, site := s.site, su0 := s.su0 } := by
      intro ni np e h1 h2 h3
      refine ⟨fun p hp => ?_, h3⟩
      rcases List.mem_append.mp hp with hp' | hp'
      · exact h1 p hp'
      · exact h2 p hp'
    split at h
    · -- common
      rename_i u hu
      have huB : ¬ (u ∉ V) := findRHS_avoids hp0 hu
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        simp only [unifyVars] at hres
        split at hres
        · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
          obtain ⟨rfl, rfl, rfl⟩ := hres
          exact hfin hrest hp0 h0e
        · rename_i hne
          obtain ⟨hni, hnp⟩ := instantiate_avoids (by simpa using hne) huB hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs (.alias u) := (instantiate_env_len hres).2.2
          refine hfin (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hni x hx))
            (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hnp x hx)) ?_
          rw [henv]
          exact avoids_env_instantiate h0e hrA.1 (fun u0 hu0 => by
            rw [EnvVal.alias.injEq] at hu0; exact hu0 ▸ huB)
    · split at h
      · -- empty
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨hni, hnp⟩ := makeEmpty_avoids hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs .emptyRow := (makeEmpty_env_len hres).2.2
          refine hfin (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hni x hx))
            (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hnp x hx)) ?_
          rw [henv]
          exact avoids_env_instantiate h0e hrA.1 (by simp)
      · split at h
        · -- concrete
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨hni, hnp⟩ := makeConcrete_avoids hrA.1 hrest hp0 hres
            exact hfin hni hnp h0e
        · split at h
          · -- unify
            rename_i u hsg
            have huB : ¬ (u ∉ V) := by
              refine hrA.2 u ?_
              have : r.rhs.abstr.single? = some u := by
                unfold RHS.single? at hsg
                split at hsg
                · exact hsg
                · exact absurd hsg (by simp)
              exact mem_of_single? this
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simp only [unifyVars] at hres
              split at hres
              · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                obtain ⟨rfl, rfl, rfl⟩ := hres
                exact hfin hrest hp0 h0e
              · rename_i hne
                obtain ⟨hni, hnp⟩ := instantiate_avoids (by simpa using hne) hrA.1 hrest hp0 hres
                have henv : e = s.env.instantiate u (.alias r.lhs) := (instantiate_env_len hres).2.2
                refine hfin (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hni x hx))
                  (fun x hx => Avoids.mono (fun w hw => Or.inl hw) (hnp x hx)) ?_
                rw [henv]
                exact avoids_env_instantiate h0e huB (fun u0 hu0 => by
                  rw [EnvVal.alias.injEq] at hu0; exact hu0 ▸ hrA.1)
          · -- learn
            cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              have hnd2 : su2.drawn = s.su.drawn := hnd
              have hlearn := learnPartitions_avoidsV_noDraw (B := fun w => w ∉ V) hdj hcse
                hrA.1 hrA.2 hrest hp0 hlp hnd2
              refine ⟨fun x hx => ?_, h0e⟩
              rcases List.mem_append.mp hx with hx' | hx'
              · exact concatP_avoids _ hrest
                  (fun d hd => hlearn d (SSet.mem_filter hd)) x hx'
              · exact insertNP_avoids hp0 (hi0 r hrMem) hx'

/-! ## 4. The `concrete` branch: what grows

`NoConc.step_trichotomy` discharged the `concrete` dispatch branch by `exfalso` -- with no
labels the right-hand side is `RHSEmpty` and the `empty` branch takes it first.  With labels
the branch fires (1,305 times on the `top` corpus group, 1,556 on `Ai`), and `makeConcrete`
neither binds a variable nor grows the processed set: `destructiveSub` DELETES.  What it does
do is install `v <- ((|fs|))`, and three facts make that a measure:

* `ensureSuperset` (`Constraints.scala:1608`) fails the whole step unless every concrete row
  already recorded for `v` is a SUBSET of `fs`;
* the dispatch reached `makeConcrete` only because `proc.findRHS r.rhs` MISSED, so no
  processed partition has right-hand side `((|fs|))` -- the subset is PROPER;
* `destructiveSub` deletes only partitions that mention `v`, and a bare concrete row mentions
  no variable, so every OTHER variable's rows survive.

So the downward-closed set of pairs `(variable, concrete row it is known to contain)` that
the processed queue carries strictly GROWS at a `concrete` step, is unchanged at a `learn`
step and at a `common`/`unify` step at equal variables, and lives inside `V ×ˢ L.powerset`. -/

/-- The elements of a `partition`'s discarded half were in the queue. -/
theorem mem_of_partition_fst {q : PQueue} {f : LPart → Bool} {x : LPart}
    (h : x ∈ (q.partition f).1.elems) : x ∈ q.elems :=
  List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList h))

theorem mem_of_partition_snd {q : PQueue} {f : LPart → Bool} {x : LPart}
    (h : x ∈ (q.partition f).2.elems) : x ∈ q.elems := List.mem_of_mem_filter h

/-- **`destructiveSub` adds nothing to the processed queue.** -/
theorem destructiveSub_proc_sub {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) : ∀ x ∈ np.elems, x ∈ proc.elems := by
  simp only [destructiveSub] at h
  obtain ⟨srs, -, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨-, rfl⟩ := h2
  intro x hx
  split at hx
  · rcases mem_concatNP _ _ hx with hx' | hx'
    · split at hx'
      · exact hx'
      · exact mem_of_partition_snd (List.mem_of_mem_filter hx')
    · exact mem_of_partition_fst (SSet.mem_filter hx')
  · split at hx
    · exact hx
    · exact mem_of_partition_snd (List.mem_of_mem_filter hx)

/-- **`destructiveSub` keeps every processed partition that does not mention `v`.** -/
theorem destructiveSub_proc_keep {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) {x : LPart} (hx : x ∈ proc.elems)
    (hl : (x.lhs == v) = false) (hc : x.rhs.contains v = false) : x ∈ np.elems := by
  simp only [destructiveSub] at h
  obtain ⟨srs, -, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨-, rfl⟩ := h2
  have hin : ∀ (Q : PQueue), x ∈ Q.elems → x ∈ (if srs.isEmpty && !(((proc.partition
        (fun p => p.lhs == v)).1.concat (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then proc else Q).elems := by
    intro Q hQ
    split
    · exact hx
    · exact hQ
  have hbase : x ∈ ((proc.partition (fun p => p.lhs == v)).2.filter
      (fun p => p.lhs != v && !p.rhs.contains v)).elems := by
    refine List.mem_filter.mpr ⟨mem_partition_snd hx hl, ?_⟩
    rw [Bool.and_eq_true, Bool.not_eq_true', bne_iff_ne, ne_eq]
    exact ⟨by simpa using hl, hc⟩
  have hmid := hin _ hbase
  split
  · exact mem_concatNP_of_mem _ hmid
  · exact hmid

/-! ### 4.1 `makeConcrete`, three facts -/

/-- `ensureSuperset`'s fold propagates an error. -/
theorem ens_foldl_error {fs : SSet Lbl} : ∀ (l : List RHS) (m : String),
    l.foldl (fun (acc : Except String Unit) (r : RHS) => acc.bind
      (fun _ => ensureSuperset r.conc fs)) (.error m) = .error m
  | [], m => rfl
  | r :: l, m => by
    simp only [List.foldl_cons, Except.bind]
    exact ens_foldl_error l m

/-- ...so a successful fold means every check passed. -/
theorem ens_foldl_ok {fs : SSet Lbl} : ∀ (l : List RHS) (acc : Except String Unit) (u : Unit),
    l.foldl (fun (acc : Except String Unit) (r : RHS) => acc.bind
      (fun _ => ensureSuperset r.conc fs)) acc = .ok u →
    ∀ r ∈ l, r.conc.subsetOf fs = true
  | [], _, _, _, _, hr => absurd hr (by simp)
  | r :: l, acc, u, h, x, hx => by
    simp only [List.foldl_cons] at h
    have hok : ∃ w, acc.bind (fun _ => ensureSuperset r.conc fs) = .ok w := by
      cases hb : acc.bind (fun _ => ensureSuperset r.conc fs) with
      | error m => rw [hb, ens_foldl_error l m] at h; exact absurd h (by simp)
      | ok w => exact ⟨w, rfl⟩
    obtain ⟨w, hw⟩ := hok
    have hsub : r.conc.subsetOf fs = true := by
      cases hacc : acc with
      | error m => rw [hacc] at hw; simp only [Except.bind] at hw; exact absurd hw (by simp)
      | ok a =>
        rw [hacc] at hw
        simp only [Except.bind, ensureSuperset] at hw
        split at hw
        · assumption
        · exact absurd hw (by simp)
    rcases List.mem_cons.mp hx with rfl | hx'
    · exact hsub
    · rw [hw] at h
      exact ens_foldl_ok l _ u h x hx'

/-- **`makeConcrete` keeps every processed partition that does not mention `v`.** -/
theorem makeConcrete_proc_keep {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (h : makeConcrete v fs incm proc = .ok (ni, np)) {x : LPart} (hx : x ∈ proc.elems)
    (hl : (x.lhs == v) = false) (hc : x.rhs.contains v = false) : x ∈ np.elems := by
  simp only [makeConcrete] at h
  obtain ⟨u1, -, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  obtain ⟨nincm, nproc⟩ := w
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨-, rfl⟩ := h3
  exact mem_insertNP_of_mem (destructiveSub_proc_keep hw hx hl hc)

/-- **`makeConcrete` adds nothing to the processed queue but the row it installs.** -/
theorem makeConcrete_proc_sub {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∀ x ∈ np.elems, x ∈ proc.elems ∨ x = (⟨v, RHS.ofConcr fs, none⟩ : LPart) := by
  simp only [makeConcrete] at h
  obtain ⟨u1, -, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  obtain ⟨nincm, nproc⟩ := w
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨-, rfl⟩ := h3
  intro x hx
  rcases mem_insertNP hx with hx' | rfl
  · exact Or.inl (destructiveSub_proc_sub hw x hx')
  · exact Or.inr rfl

/-- **The row `makeConcrete` installs really lands in the processed queue.**  `Q.insert`
refuses a self-unification and a partition already present at the same search key; the first
is impossible for a bare concrete row and the second would have been found by the dispatch's
own `proc.findRHS`, which missed. -/
theorem makeConcrete_row_mem {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (h : makeConcrete v fs incm proc = .ok (ni, np)) (hfs : fs.isEmpty = false)
    (hno : ∀ y ∈ proc.elems, y.rhs.eqv (RHS.ofConcr fs) = false) :
    (⟨v, RHS.ofConcr fs, none⟩ : LPart) ∈ np.elems := by
  simp only [makeConcrete] at h
  obtain ⟨u1, -, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  obtain ⟨nincm, nproc⟩ := w
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨-, rfl⟩ := h3
  have hself : (⟨v, RHS.ofConcr fs, none⟩ : LPart).isSelfUnification = false := by
    simp [LPart.isSelfUnification, RHS.single?, RHS.ofConcr, hfs]
  have hany : (nproc.elems.any (fun x => PQueue.keyEq (PQueue.keyOf x)
      (PQueue.keyOf (⟨v, RHS.ofConcr fs, none⟩ : LPart)) &&
      x.eqv (⟨v, RHS.ofConcr fs, none⟩ : LPart))) = false := by
    rw [List.any_eq_false]
    intro y hy hcontra
    simp only [Bool.and_eq_true] at hcontra
    have hyp : y ∈ proc.elems := destructiveSub_proc_sub hw y hy
    have hy2 : y.rhs.eqv (RHS.ofConcr fs) = true := by
      simp only [LPart.eqv, Bool.and_eq_true] at hcontra
      exact hcontra.2.2
    rw [hno y hyp] at hy2
    exact absurd hy2 (by simp)
  rw [PQueue.insertNP, if_neg (by simp [hself]), if_neg (by simp [hany])]
  exact (insertSorted_perm _ nproc.elems).mem_iff.mpr List.mem_cons_self

/-! ### 4.0 Reading `ensureSuperset` out of `makeConcrete`'s two `Set` layers

`makeConcrete` runs its check over `rhss`, an `SSet RHS` built by `map` from a `filter` of an
`SSet LPart` and then `concat`ted with the incoming half.  `SVal RHS` is `RHS.eqv`, NOT
structural equality, so `p.rhs` need not be an ELEMENT of that set: what is available is a
representative.  These four lemmas say a representative is always there and that a subset
relation on the concrete part survives the trip, which is all the measure needs. -/

/-- `subsetOf` on labels is ordinary inclusion. -/
theorem subsetOfL_iff {s t : SSet Lbl} : s.subsetOf t = true ↔ ∀ x ∈ s.elems, x ∈ t.elems := by
  simp only [SSet.subsetOf, List.all_eq_true]
  exact ⟨fun h x hx => (SSet.contains_iff t x).mp (h x hx),
    fun h x hx => (SSet.contains_iff t x).mpr (h x hx)⟩

theorem subsetOfL_trans {s t u : SSet Lbl} (h1 : s.subsetOf t = true) (h2 : t.subsetOf u = true) :
    s.subsetOf u = true :=
  subsetOfL_iff.mpr (fun x hx => subsetOfL_iff.mp h2 _ (subsetOfL_iff.mp h1 x hx))

/-- An `RHS.eqv` gives inclusion of the concrete parts one way... -/
theorem conc_sub_of_eqv {a b : RHS} (h : RHS.eqv a b = true) : a.conc.subsetOf b.conc = true := by
  simp only [RHS.eqv, Bool.and_eq_true, SSet.eqv, beq_iff_eq] at h
  exact h.2.2

/-- ...and, on duplicate-free rows, the other way too. -/
theorem conc_sub_of_eqv' {a b : RHS} (ha : a.conc.Nodup) (hb : b.conc.Nodup)
    (h : RHS.eqv a b = true) : b.conc.subsetOf a.conc = true := by
  have he : a.conc.eqv b.conc = true := by
    simp only [RHS.eqv, Bool.and_eq_true] at h; exact h.2
  have := (SSet.eqv_iff_toFinset ha hb).mp he
  refine subsetOfL_iff.mpr (fun x hx => ?_)
  exact List.mem_toFinset.mp (this ▸ List.mem_toFinset.mpr hx)

theorem mem_foldl_incl_map {α β : Type} [SVal α] [SVal β] {f : α → β} :
    ∀ (l : List α) (acc : SSet β) {z : β}, z ∈ acc.elems →
      z ∈ (l.foldl (fun a x => a.incl (f x)) acc).elems
  | [], _, _, h => h
  | x :: l, acc, z, h => mem_foldl_incl_map l _ (mem_incl_of_mem h)

/-- **A representative survives a fold of `incl`.** -/
theorem foldl_incl_witness {α β : Type} [SVal α] [SVal β] {f : α → β} {x : α}
    (hrefl : ∀ b : β, SVal.eq b b = true) :
    ∀ (l : List α) (acc : SSet β), x ∈ l →
      ∃ z ∈ (l.foldl (fun a y => a.incl (f y)) acc).elems, SVal.eq (f x) z = true := by
    intro l
    induction l with
    | nil => intro _ h; exact absurd h (by simp)
    | cons y l ih =>
      intro acc h
      rcases List.mem_cons.mp h with rfl | h'
      · have hnew : ∃ z ∈ (acc.incl (f x)).elems, SVal.eq (f x) z = true := by
          unfold SSet.incl
          split
          · rename_i hc
            simp only [SSet.contains, List.any_eq_true] at hc
            obtain ⟨z, hz, hzx⟩ := hc
            exact ⟨z, hz, hzx⟩
          · split
            · exact ⟨f x, SSet.mem_champ.mpr (List.mem_append_right _ (by simp)), hrefl _⟩
            · exact ⟨f x, List.mem_append_right _ (by simp), hrefl _⟩
        obtain ⟨z, hz, hzx⟩ := hnew
        exact ⟨z, mem_foldl_incl_map l _ hz, hzx⟩
      · exact ih _ h'

/-- **A representative survives `map`.** -/
theorem map_witness {α β : Type} [SVal α] [SVal β] {s : SSet α} {f : α → β} {x : α}
    (hrefl : ∀ b : β, SVal.eq b b = true) (hx : x ∈ s.elems) :
    ∃ z ∈ (s.map f).elems, SVal.eq (f x) z = true :=
  foldl_incl_witness hrefl s.elems _ hx

/-- **A representative survives `concat`, up to inclusion of the concrete part.**  The CHAMP
union may keep the LEFT operand's copy of a label set (`SSet.pickRep`), which is why the
duplicate-free hypothesis is needed: without it `RHS.eqv` is not symmetric. -/
theorem concat_witness {s t : SSet RHS} (hnd : ∀ r ∈ s.elems ++ t.elems, r.conc.Nodup)
    {x z : RHS} (hz : z ∈ s.elems) (hxz : RHS.eqv x z = true) :
    ∃ r ∈ (s.concat t).elems, x.conc.subsetOf r.conc = true := by
  have hpick : ∀ y : RHS, y ∈ s.elems ++ t.elems → x.conc.subsetOf y.conc = true →
      x.conc.subsetOf (SSet.pickRep s.elems t.elems y).conc = true := by
    intro y hy hxy
    unfold SSet.pickRep
    split
    · exact hxy
    · rename_i sy hf
      have hsy : sy ∈ s.elems := List.mem_of_find?_eq_some hf
      have hsyy : RHS.eqv sy y = true := by
        have h0 := List.find?_some hf
        simpa [SVal.eq] using h0
      split
      · exact hxy
      · exact subsetOfL_trans hxy
          (conc_sub_of_eqv' (hnd sy (List.mem_append_left _ hsy)) (hnd y hy) hsyy)
  unfold SSet.concat
  split
  · -- the CHAMP union
    by_cases hc : t.contains z = true
    · simp only [SSet.contains, List.any_eq_true] at hc
      obtain ⟨y, hy, hzy⟩ := hc
      refine ⟨SSet.pickRep s.elems t.elems y,
        List.mem_map.mpr ⟨y, SSet.mem_champ.mpr (List.mem_append_right _ hy), rfl⟩, ?_⟩
      exact hpick y (List.mem_append_right _ hy)
        (subsetOfL_trans (conc_sub_of_eqv hxz) (conc_sub_of_eqv (by simpa [SVal.eq] using hzy)))
    · refine ⟨SSet.pickRep s.elems t.elems z,
        List.mem_map.mpr ⟨z, SSet.mem_champ.mpr (List.mem_append_left _
          (List.mem_filter.mpr ⟨hz, by simpa using hc⟩)), rfl⟩, ?_⟩
      exact hpick z (List.mem_append_left _ hz) (conc_sub_of_eqv hxz)
  · exact ⟨z, mem_foldl_incl_map (f := fun r : RHS => r) t.elems _ hz, conc_sub_of_eqv hxz⟩

/-- `SSet.ofList` keeps a representative of every element. -/
theorem ofList_witness {β : Type} [SVal β] {l : List β} {x : β}
    (hrefl : ∀ b : β, SVal.eq b b = true) (hx : x ∈ l) :
    ∃ z ∈ (SSet.ofList l).elems, SVal.eq x z = true := by
  have h := foldl_incl_witness (f := (id : β → β)) hrefl l SSet.empty hx
  simpa [SSet.ofList] using h

theorem lpart_eqv_refl (p : LPart) : p.eqv p = true := by
  simp only [LPart.eqv, Bool.and_eq_true, beq_self_eq_true, true_and]
  exact rhs_eqv_refl _

/-- **`ensureSuperset`, extracted**: every concrete row already recorded for `v` in the
processed queue is a subset of the row `makeConcrete` is installing
(`Constraints.scala:1608`).  Three `Set` layers stand between the check and the partition --
`SSet.ofList`, `filter`+`map`, `concat` -- and none of them preserves the partition itself,
only a representative, so the conclusion is proved by chasing `subsetOf` through all three. -/
theorem makeConcrete_superset {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hcp : ∀ q ∈ proc.elems, q.rhs.conc.Nodup) (hci : ∀ q ∈ incm.elems, q.rhs.conc.Nodup)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∀ p ∈ proc.elems, p.lhs = v → p.rhs.conc.subsetOf fs = true := by
  simp only [makeConcrete] at h
  obtain ⟨u1, hu1, -⟩ := except_bind_ok h
  intro p hp hlv
  have hall : ∀ r ∈ (((((SSet.ofList proc.elems).filter (fun q => q.lhs == v)).map
        (fun q => q.rhs)).concat
      (((SSet.ofList incm.elems).filter (fun q => q.lhs == v)).map
        (fun q => q.rhs)))).elems, r.conc.subsetOf fs = true :=
    ens_foldl_ok _ _ u1 hu1
  have hnd : ∀ r ∈ ((((SSet.ofList proc.elems).filter (fun q => q.lhs == v)).map
        (fun q => q.rhs))).elems ++ ((((SSet.ofList incm.elems).filter (fun q => q.lhs == v)).map
        (fun q => q.rhs))).elems, r.conc.Nodup := by
    intro r hr
    rcases List.mem_append.mp hr with hr' | hr'
    · obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr'
      exact hcp q (SSet.mem_ofList (SSet.mem_filter_iff.mp hq).1)
    · obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr'
      exact hci q (SSet.mem_ofList (SSet.mem_filter_iff.mp hq).1)
  obtain ⟨q, hq, hpq⟩ := ofList_witness (l := proc.elems) (x := p) lpart_eqv_refl hp
  have hqv : (q.lhs == v) = true := by
    simp only [SVal.eq, LPart.eqv, Bool.and_eq_true, beq_iff_eq] at hpq
    simp [← hpq.1, hlv]
  obtain ⟨z, hz, hqz⟩ := map_witness
    (s := (SSet.ofList proc.elems).filter (fun (w : LPart) => w.lhs == v))
    (f := fun (w : LPart) => w.rhs) rhs_eqv_refl (SSet.mem_filter_iff.mpr ⟨hq, hqv⟩)
  obtain ⟨r, hr, hzr⟩ := concat_witness
    (t := ((SSet.ofList incm.elems).filter (fun q => q.lhs == v)).map (fun q => q.rhs))
    hnd hz (by simpa [SVal.eq] using hqz)
  have hpq2 : p.rhs.conc.subsetOf q.rhs.conc = true := by
    simp only [SVal.eq, LPart.eqv, Bool.and_eq_true] at hpq
    exact conc_sub_of_eqv hpq.2
  exact subsetOfL_trans hpq2 (subsetOfL_trans hzr (hall r hr))

/-! ### 4.2 The potential the `concrete` branch lowers -/

/-- **The rows the processed queue carries, downward closed.**  `(u, C)` is in it when some
bare concrete partition `u <- ((|D|))` of `proc` has `C ⊆ D`.  Downward closure is what makes
it monotone: a `concrete` step at `u` DELETES `u`'s old rows, but `ensureSuperset` has
already forced each of them inside the new one, so no pair is lost. -/
def rowSet (V : Finset Var) (L : Finset Label) (s : State) : Finset (Var × Finset Label) :=
  (V ×ˢ L.powerset).filter (fun q =>
    s.proc.elems.any (fun p => p.lhs == q.1 && p.rhs.abstr.elems.isEmpty &&
      decide (q.2 ⊆ p.toConstraint.conc)))

theorem mem_rowSet_iff {V : Finset Var} {L : Finset Label} {s : State}
    {q : Var × Finset Label} :
    q ∈ rowSet V L s ↔ (q.1 ∈ V ∧ q.2 ⊆ L) ∧
      ∃ p ∈ s.proc.elems, p.lhs = q.1 ∧ p.rhs.abstr.elems = [] ∧ q.2 ⊆ p.toConstraint.conc := by
  simp only [rowSet, Finset.mem_filter, Finset.mem_product, Finset.mem_powerset,
    List.any_eq_true, Bool.and_eq_true, beq_iff_eq, List.isEmpty_iff, decide_eq_true_eq]
  constructor
  · rintro ⟨h1, p, hp, ⟨hl, ha⟩, hc⟩; exact ⟨h1, p, hp, hl, ha, hc⟩
  · rintro ⟨h1, p, hp, hl, ha, hc⟩; exact ⟨h1, p, hp, ⟨hl, ha⟩, hc⟩

theorem rowSet_card_le {V : Finset Var} {L : Finset Label} {s : State} :
    (rowSet V L s).card ≤ V.card * 2 ^ L.card := by
  refine le_trans (Finset.card_le_card (Finset.filter_subset _ _)) ?_
  rw [Finset.card_product, Finset.card_powerset]

/-- The potential is monotone in the bare rows the processed queue keeps. -/
theorem rowSet_subset_of {V : Finset Var} {L : Finset Label} {s t : State}
    (h : ∀ p ∈ s.proc.elems, p.rhs.abstr.elems = [] → p ∈ t.proc.elems) :
    rowSet V L s ⊆ rowSet V L t := by
  intro q hq
  obtain ⟨h1, p, hp, hl, ha, hc⟩ := mem_rowSet_iff.mp hq
  exact mem_rowSet_iff.mpr ⟨h1, p, h p hp ha, hl, ha, hc⟩

/-- Two rows with no variable parts have equivalent abstract halves. -/
theorem eqv_empty_abstr {a b : SSet Nat} (ha : a.elems = []) (hb : b.elems = []) :
    a.eqv b = true := by simp [SSet.eqv, SSet.size, SSet.subsetOf, ha, hb]

/-- **The `concrete` branch strictly grows the potential.** -/
theorem rowSet_lt_concrete {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s)) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest))
    (hfind : s.proc.findRHS r.rhs = none)
    (hne : r.rhs.isEmpty = false) (hab : r.rhs.abstr.isEmpty = true)
    (hmk : makeConcrete r.lhs r.rhs.conc rest s.proc = .ok (s'.incm, s'.proc)) :
    (rowSet V L s).card < (rowSet V L s').card := by
  have hrMem : r ∈ s.incm.elems := (PQueue.dequeue_mem hdq).1
  have hrPart : r ∈ s.parts := List.mem_append_left _ hrMem
  have habN : r.rhs.abstr.elems = [] := by simpa [SSet.isEmpty] using hab
  have hfs : r.rhs.conc.isEmpty = false := by
    simp only [RHS.isEmpty, Bool.and_eq_false_iff, hab] at hne
    rcases hne with h | h
    · exact absurd h (by simp)
    · exact h
  -- no processed partition has the dequeued right-hand side, hence none is a bare `((|fs|))`
  have hnofind : ∀ y ∈ s.proc.elems, y.rhs.eqv r.rhs = false := by
    intro y hy
    cases hf : (s.proc.elems.find? (fun x => x.rhs.eqv r.rhs)) with
    | some z => rw [PQueue.findRHS, hf] at hfind; exact absurd hfind (by simp)
    | none => simpa using List.find?_eq_none.mp hf y hy
  have hno : ∀ y ∈ s.proc.elems, y.rhs.eqv (RHS.ofConcr r.rhs.conc) = false := by
    intro y hy
    cases hyy : y.rhs.eqv (RHS.ofConcr r.rhs.conc) with
    | false => rfl
    | true =>
      exfalso
      simp only [RHS.eqv, RHS.ofConcr, Bool.and_eq_true] at hyy
      have hya : y.rhs.abstr.elems = [] := by
        have := hyy.1
        simp only [SSet.eqv, SSet.size, SSet.empty, Bool.and_eq_true, beq_iff_eq,
          List.length_nil] at this
        exact List.eq_nil_of_length_eq_zero this.1
      have : y.rhs.eqv r.rhs = true := by
        simp only [RHS.eqv, Bool.and_eq_true]
        exact ⟨eqv_empty_abstr hya habN, hyy.2⟩
      rw [hnofind y hy] at this; exact absurd this (by simp)
  have hrow : (⟨r.lhs, RHS.ofConcr r.rhs.conc, none⟩ : LPart) ∈ s'.proc.elems :=
    makeConcrete_row_mem hmk hfs hno
  have hcncp : ∀ q ∈ s.proc.elems, q.rhs.conc.Nodup :=
    fun q hq => (hw.nodup (List.mem_append_right _ hq)).2
  have hcnci : ∀ q ∈ rest.elems, q.rhs.conc.Nodup :=
    fun q hq => (hw.nodup (List.mem_append_left _ ((PQueue.dequeue_mem hdq).2 q hq))).2
  have hsup := makeConcrete_superset hcncp hcnci hmk
  -- every recorded row of `r.lhs` is inside the new one
  have hsupN : ∀ p ∈ s.proc.elems, p.lhs = r.lhs →
      p.toConstraint.conc ⊆ r.toConstraint.conc := by
    intro p hp hl x hx
    simp only [LPart.conc_toConstraint, List.mem_toFinset, List.mem_map] at hx ⊢
    obtain ⟨y, hy, rfl⟩ := hx
    exact ⟨y, subsetOfL_iff.mp (hsup p hp hl) y hy, rfl⟩
  have hsub : rowSet V L s ⊆ rowSet V L s' := by
    intro q hq
    obtain ⟨h1, p, hp, hl, ha, hc⟩ := mem_rowSet_iff.mp hq
    by_cases hlv : p.lhs = r.lhs
    · refine mem_rowSet_iff.mpr ⟨h1, ⟨r.lhs, RHS.ofConcr r.rhs.conc, none⟩, hrow, ?_, ?_, ?_⟩
      · rw [← hl, hlv]
      · simp [RHS.ofConcr, SSet.empty]
      · refine subset_trans hc ?_
        have := hsupN p hp hlv
        simpa [LPart.conc_toConstraint, RHS.ofConcr] using this
    · refine mem_rowSet_iff.mpr ⟨h1, p, ?_, hl, ha, hc⟩
      refine makeConcrete_proc_keep hmk hp (by simpa using hlv) ?_
      simp [RHS.contains, SSet.contains, ha]
  refine Finset.card_lt_card (Finset.ssubset_iff_of_subset hsub |>.mpr ?_)
  refine ⟨(r.lhs, r.toConstraint.conc), ?_, ?_⟩
  · refine mem_rowSet_iff.mpr ⟨⟨?_, ?_⟩, ⟨r.lhs, RHS.ofConcr r.rhs.conc, none⟩, hrow, rfl,
      by simp [RHS.ofConcr, SSet.empty], by simp [LPart.conc_toConstraint, RHS.ofConcr]⟩
    · exact not_not.mp (avoids_toConstraint_iff.mp (hv.1 r hrPart)).1
    · exact hcs _ (mem_sys_of_part hrPart)
  · intro hbad
    obtain ⟨-, p, hp, hl, ha, hc⟩ := mem_rowSet_iff.mp hbad
    have hEq : p.toConstraint.conc = r.toConstraint.conc :=
      Finset.Subset.antisymm (hsupN p hp hl) hc
    have hcoh : LblCoh (p.rhs.conc.elems ++ r.rhs.conc.elems) := by
      refine hw.coh.mono ?_
      intro x hx
      rcases List.mem_append.mp hx with hx' | hx'
      · exact State.mem_labels (List.mem_append_right _ hp) hx'
      · exact State.mem_labels hrPart hx'
    have hfin : p.rhs.conc.elems.toFinset = r.rhs.conc.elems.toFinset :=
      (toFinset_map_n_iff hcoh).mp (by simpa [LPart.conc_toConstraint] using hEq)
    have hce : p.rhs.conc.eqv r.rhs.conc = true :=
      (SSet.eqv_iff_toFinset (hcncp p hp) (hw.nodup hrPart).2).mpr hfin
    have : p.rhs.eqv r.rhs = true := by
      simp only [RHS.eqv, Bool.and_eq_true]
      exact ⟨eqv_empty_abstr ha habN, hce⟩
    rw [hnofind p hp] at this; exact absurd this (by simp)

/-! ## 5. The four kinds of step, and the measure they bound

`NoConc.step_trichotomy`'s three cases become four.  The new one is the `concrete` branch,
which changes neither the environment nor (monotonically) anything else -- what it moves is
§4's potential. -/

/-- The `concrete` dispatch branch, with everything the potential argument needs. -/
def IsConcStep (s s' : State) : Prop :=
  ∃ (r : LPart) (rest : PQueue), s.incm.dequeue = some (r, rest) ∧
    s.proc.findRHS r.rhs = none ∧ r.rhs.isEmpty = false ∧ r.rhs.abstr.isEmpty = true ∧
    makeConcrete r.lhs r.rhs.conc rest s.proc = .ok (s'.incm, s'.proc)

/-- **The quadrichotomy.**  Every `continue` step either
* is a `learn` step -- the processed set strictly grows and nothing is deleted from it;
* is a `concrete` step -- the environment is unchanged and §4's potential strictly grows;
* binds a variable -- the environment grows by exactly one;
* or is a `common`/`unify` at EQUAL variables -- nothing changes but the queue's length. -/
theorem step_quadrichotomy {s s' : State} (h : step s = .continue s') :
    (IsLearnStep s ∧ s'.env = s.env ∧ ∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length) ∨
    (IsConcStep s s' ∧ s'.env = s.env) := by
  simp only [step, State.log] at h
  cases hd : s.incm.dequeue with
  | none => rw [hd] at h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at h
    dsimp only at h
    have hlen : rest.elems.length + 1 = s.incm.elems.length := dequeue_length_lt hd
    split at h
    · -- common
      rename_i u hfind
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        by_cases hvu : r.lhs = u
        · rw [unifyVars, if_pos (by simp [hvu])] at hu
          simp only [Except.ok.injEq, Prod.mk.injEq] at hu
          obtain ⟨h1, h2, h3⟩ := hu
          exact Or.inr (Or.inr (Or.inl ⟨h3.symm, h2.symm, by rw [← h1]; exact hlen⟩))
        · rw [unifyVars, if_neg (by simpa using hvu)] at hu
          exact Or.inr (Or.inl (instantiate_env_len hu).1)
    · rename_i hfind
      split at h
      · -- empty
        cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Or.inr (Or.inl (makeEmpty_env_len hu).1)
      · rename_i hne
        split at h
        · -- concrete
          rename_i hab
          cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hu] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hu] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Or.inr (Or.inr (Or.inr
              ⟨⟨r, rest, hd, by simpa using hfind, by simpa using hne, hab, hu⟩, rfl⟩))
        · rename_i hab
          split at h
          · -- unify
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              by_cases hvu : u = r.lhs
              · rw [unifyVars, if_pos (by simp [hvu])] at hu
                simp only [Except.ok.injEq, Prod.mk.injEq] at hu
                obtain ⟨h1, h2, h3⟩ := hu
                exact Or.inr (Or.inr (Or.inl ⟨h3.symm, h2.symm, by rw [← h1]; exact hlen⟩))
              · rw [unifyVars, if_neg (by simpa using hvu)] at hu
                exact Or.inr (Or.inl (instantiate_env_len hu).1)
          · -- learn
            rename_i hsingle
            cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact Or.inl ⟨⟨r, rest, hd, hfind, by simpa using hne, by simpa using hab,
                hsingle⟩, rfl, fun p hp => mem_insertNP_of_mem hp⟩

/-- The lexicographic measure, flattened: the environment's room to grow weighs most, then
§4's potential, then the processed set's room, then the incoming queue's own length. -/
def measure4 (P Q E R : Nat) (V : Finset Var) (L : Finset Label) (s : State) : Nat :=
  (E - s.env.binds.length) * ((R + 1) * ((P + 1) * (Q + 1))) +
    (R - (rowSet V L s).card) * ((P + 1) * (Q + 1)) +
    (P - (procSys s).card) * (Q + 1) + s.incm.elems.length

theorem measure4_arith {P Q E R ae be ce de ae' be' ce' de' : Nat}
    (hbe' : be' ≤ R) (hce' : ce' ≤ P) (hde' : de' ≤ Q) (hae' : ae' ≤ E)
    (hcase : (ae' = ae ∧ be ≤ be' ∧ ce < ce') ∨ (ae' = ae + 1) ∨
      (ae' = ae ∧ be ≤ be' ∧ ce' = ce ∧ de' + 1 = de) ∨ (ae' = ae ∧ be < be')) :
    (E - ae') * ((R + 1) * ((P + 1) * (Q + 1))) + (R - be') * ((P + 1) * (Q + 1)) +
        (P - ce') * (Q + 1) + de'
      < (E - ae) * ((R + 1) * ((P + 1) * (Q + 1))) + (R - be) * ((P + 1) * (Q + 1)) +
        (P - ce) * (Q + 1) + de := by
  have hK2 : (P + 1) * (Q + 1) = P * (Q + 1) + (Q + 1) := Nat.succ_mul P (Q + 1)
  have hK1 : (R + 1) * ((P + 1) * (Q + 1)) = R * ((P + 1) * (Q + 1)) + (P + 1) * (Q + 1) :=
    Nat.succ_mul R _
  have hPM : (P - ce') * (Q + 1) ≤ P * (Q + 1) := Nat.mul_le_mul_right _ (Nat.sub_le _ _)
  have hRM : (R - be') * ((P + 1) * (Q + 1)) ≤ R * ((P + 1) * (Q + 1)) :=
    Nat.mul_le_mul_right _ (Nat.sub_le _ _)
  rcases hcase with ⟨rfl, hb, hc⟩ | hae | ⟨rfl, hb, hc, hdd⟩ | ⟨rfl, hb⟩
  · have h1 : (R - be') * ((P + 1) * (Q + 1)) ≤ (R - be) * ((P + 1) * (Q + 1)) :=
      Nat.mul_le_mul_right _ (by omega)
    have h2 : (P - ce') * (Q + 1) ≤ (P - ce - 1) * (Q + 1) := Nat.mul_le_mul_right _ (by omega)
    have h3 : (P - ce - 1) * (Q + 1) + (Q + 1) = (P - ce) * (Q + 1) := by
      rw [← Nat.succ_mul]; congr 1; omega
    omega
  · subst hae
    have h4 : (E - (ae + 1)) * ((R + 1) * ((P + 1) * (Q + 1))) +
        ((R + 1) * ((P + 1) * (Q + 1))) = (E - ae) * ((R + 1) * ((P + 1) * (Q + 1))) := by
      rw [← Nat.succ_mul]; congr 1; omega
    omega
  · have h1 : (R - be') * ((P + 1) * (Q + 1)) ≤ (R - be) * ((P + 1) * (Q + 1)) :=
      Nat.mul_le_mul_right _ (by omega)
    subst hc
    omega
  · have h1 : (R - be') * ((P + 1) * (Q + 1)) ≤ (R - be - 1) * ((P + 1) * (Q + 1)) :=
      Nat.mul_le_mul_right _ (by omega)
    have h2 : (R - be - 1) * ((P + 1) * (Q + 1)) + ((P + 1) * (Q + 1))
        = (R - be) * ((P + 1) * (Q + 1)) := by
      rw [← Nat.succ_mul]; congr 1; omega
    omega

/-- **The measure strictly decreases at every step**, given the four bounds -- with NO
fragment hypothesis on the step itself.  What the hypotheses buy is the potential: `InVoc`
and `ConcSub` are what make `rowSet` the right thing to count. -/
theorem measure4_lt {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s))
    (hR' : (rowSet V L s').card ≤ R) (hP' : (procSys s').card ≤ P)
    (hQ' : s'.incm.elems.length ≤ Q) (hE' : s'.env.binds.length ≤ E)
    (h : step s = .continue s') :
    measure4 P Q E R V L s' < measure4 P Q E R V L s := by
  simp only [measure4]
  refine measure4_arith hR' hP' hQ' hE' ?_
  rcases step_quadrichotomy h with
    ⟨⟨r, rest, hd, h1, h2, h3, h4⟩, henv, hpr⟩ | henv | ⟨he, hp, hc⟩ | ⟨⟨r, rest, hd, h1, h2, h3, hmk⟩, henv⟩
  · exact Or.inl ⟨by rw [henv],
      Finset.card_le_card (rowSet_subset_of (fun p hp' _ => hpr p hp')),
      learn_procSys_lt hw hd h1 h2 h3 h4 h⟩
  · exact Or.inr (Or.inl henv)
  · exact Or.inr (Or.inr (Or.inl ⟨by rw [he],
      Finset.card_le_card (rowSet_subset_of (fun p hp' _ => by rw [hp]; exact hp')),
      by rw [procSys, procSys, hp], hc⟩))
  · exact Or.inr (Or.inr (Or.inr ⟨by rw [henv],
      rowSet_lt_concrete hw hv hcs hd h1 h2 h3 hmk⟩))

/-- **Termination, reduced to four bounds.** -/
theorem terminates_of_bounds4_aux {P Q E R : Nat} {V : Finset Var} {L : Finset Label} :
    ∀ (n : Nat) (s : State), measure4 P Q E R V L s ≤ n →
    (∀ t, Reaches s t → Wf t) → (∀ t, Reaches s t → InVoc V t) →
    (∀ t, Reaches s t → ConcSub L (sys t)) →
    (∀ t, Reaches s t → (rowSet V L t).card ≤ R) →
    (∀ t, Reaches s t → (procSys t).card ≤ P) →
    (∀ t, Reaches s t → t.incm.elems.length ≤ Q) →
    (∀ t, Reaches s t → t.env.binds.length ≤ E) →
    Finished (run s (n + 1))
  | 0, s, hm, hw, hv, hcs, hr, hp, hq, he => by
    simp only [run]
    cases hst : step s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      exfalso
      have := measure4_lt (hw s (Reaches.refl s)) (hv s (Reaches.refl s))
        (hcs s (Reaches.refl s)) (hr s' ((Reaches.refl s).tail hst))
        (hp s' ((Reaches.refl s).tail hst)) (hq s' ((Reaches.refl s).tail hst))
        (he s' ((Reaches.refl s).tail hst)) hst
      omega
  | n + 1, s, hm, hw, hv, hcs, hr, hp, hq, he => by
    simp only [run]
    cases hst : step s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      have hlt := measure4_lt (hw s (Reaches.refl s)) (hv s (Reaches.refl s))
        (hcs s (Reaches.refl s)) (hr s' ((Reaches.refl s).tail hst))
        (hp s' ((Reaches.refl s).tail hst)) (hq s' ((Reaches.refl s).tail hst))
        (he s' ((Reaches.refl s).tail hst)) hst
      refine terminates_of_bounds4_aux n s' (by omega)
        (fun t ht => hw t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hv t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hcs t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hr t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hp t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hq t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => he t (reaches_trans ((Reaches.refl s).tail hst) ht))

theorem terminates_of_bounds4 {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {s : State}
    (hw : ∀ t, Reaches s t → Wf t) (hv : ∀ t, Reaches s t → InVoc V t)
    (hcs : ∀ t, Reaches s t → ConcSub L (sys t))
    (hr : ∀ t, Reaches s t → (rowSet V L t).card ≤ R)
    (hp : ∀ t, Reaches s t → (procSys t).card ≤ P)
    (hq : ∀ t, Reaches s t → t.incm.elems.length ≤ Q)
    (he : ∀ t, Reaches s t → t.env.binds.length ≤ E) : Terminates s :=
  ⟨measure4 P Q E R V L s + 1,
    terminates_of_bounds4_aux (measure4 P Q E R V L s) s (le_refl _) hw hv hcs hr hp hq he⟩

/-! ## 6. The queue invariant on the `concrete` branch, and the theorem

`NoConc.step_kdist` discharges the `concrete` branch by `exfalso` too, so the queue bound has
to be re-proved there.  It is entirely mechanical: `destructiveSub` and `makeConcrete` build
their queues out of `filter`, `partition`, `concatP`, `concatNP` and `insertNP`, and `KDist`
survives every one of them because the queue's own de-duplication test is what establishes
it. -/

theorem kdist_destructiveSub {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (hi : KDist incm.elems) (hp : KDist proc.elems)
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) :
    KDist ni.elems ∧ KDist np.elems := by
  simp only [destructiveSub] at h
  obtain ⟨srs, -, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨rfl, rfl⟩ := h2
  have hnp : KDist (if srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then proc else (proc.partition (fun p => p.lhs == v)).2.filter
        (fun p => p.lhs != v && !p.rhs.contains v)).elems := by
    split
    · exact hp
    · exact kdist_filter (kdist_partition_snd hp)
  have hni : KDist (if srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then incm else (incm.partition (fun p => p.lhs == v)).2.filter
        (fun p => p.lhs != v && !p.rhs.contains v)).elems := by
    split
    · exact hi
    · exact kdist_filter (kdist_partition_snd hi)
  refine ⟨?_, ?_⟩
  · refine kdist_concatP _ ?_
    split
    · exact kdist_concatP _ hni
    · exact hni
  · split
    · exact kdist_concatNP _ hnp
    · exact hnp

theorem kdist_makeConcrete {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hi : KDist incm.elems) (hp : KDist proc.elems)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    KDist ni.elems ∧ KDist np.elems := by
  simp only [makeConcrete] at h
  obtain ⟨u1, -, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  obtain ⟨nincm, nproc⟩ := w
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨rfl, rfl⟩ := h3
  obtain ⟨k1, k2⟩ := kdist_destructiveSub hi hp hw
  exact ⟨kdist_concatP _ k1, kdist_insertNP k2⟩

/-- **The queue invariant, off the no-labels fragment.**  `NoConc.step_kdist` with the
`concrete` branch proved rather than excluded. -/
theorem step_kdist' {s s' : State} (hi : KDist s.incm.elems)
    (hp : KDist s.proc.elems) (h : step s = .continue s') :
    KDist s'.incm.elems ∧ KDist s'.proc.elems := by
  simp only [step, State.log] at h
  cases hd : s.incm.dequeue with
  | none => rw [hd] at h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at h
    dsimp only at h
    have hrest : KDist rest.elems := kdist_dequeue hd hi
    split at h
    · rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact kdist_unifyVars hrest hp hu
    · split at h
      · cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact kdist_makeEmpty hrest hp hu
      · split at h
        · cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hu] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hu] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact kdist_makeConcrete hrest hp hu
        · split at h
          · rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact kdist_unifyVars hrest hp hu
          · cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨kdist_concatP _ hrest, kdist_insertNP hp⟩

theorem reaches_kdist {s t : State} (hi : KDist s.incm.elems) (hp : KDist s.proc.elems)
    (hr : Reaches s t) : KDist t.incm.elems ∧ KDist t.proc.elems := by
  induction hr with
  | refl => exact ⟨hi, hp⟩
  | tail _ hstep ih => exact step_kdist' ih.1 ih.2 hstep

/-! ## 7. The fragment, and `Terminates`

The condition is RUN-LEVEL and it has to be: the round-6 review (W-9) refuted the
input-checkable widening -- of the 9,256 example solves on which neither generative rule can
fire ON THE INPUT, 111 fire one anyway, because `substitution` and `commonSubexpression`
manufacture a partition with a nonempty concrete part and two abstract parts, which is
exactly `splitConcrete`'s firing shape.  So "no generative rule can fire" is not an invariant
and cannot be the fragment.  What IS checkable per solve is what the run does, and the model
reports it: `looptrace --replay <trace> --cycle` prints `grew=` and `drawn=` for every solve
of a corpus trace. -/

/-- **The vocabulary-fixed condition**: every state the run reaches mentions only variables
of `V`.  With `V := allVars (sys s)` this is "the loop invents no variable". -/
def VocFixed (V : Finset Var) (s : State) : Prop := ∀ t, Reaches s t → InVoc V t

/-- **The loop draws no id along the run.**  A SUFFICIENT condition for `VocFixed`, and a
strictly stronger one: `resolution` takes its id before its guards, so a REUSE costs an id
without putting one into a partition. -/
def NoDraw (s : State) : Prop :=
  ∀ t t', Reaches s t → step t = .continue t' → t'.su.drawn = t.su.drawn

/-- **Preservation**: a run that draws no id keeps the vocabulary of its input. -/
theorem vocFixed_of_noDraw {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : NoDraw s) : VocFixed (allVars (sys s)) s := by
  intro t ht
  induction ht with
  | refl => exact inVoc_self s
  | @tail t0 u0 hr0 hstep ih =>
    have hfl := reaches_flags_eq hr0
    exact step_inVoc_noDraw (by rw [hfl]; exact hdj) (by rw [hfl]; exact hcse) ih hstep
      (h t0 u0 hr0 hstep)

/-- **`Terminates` ON THE VOCABULARY-FIXED FRAGMENT, with an explicit bound.**  No hypothesis
restricts the SHAPE of the input: labels are allowed, both generative rules may fire, and the
`concrete` dispatch branch may be taken.  What is assumed is that no state the run reaches
mentions a variable outside `V`. -/
theorem vocFixed_terminates {V : Finset Var} {L : Finset Label} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixed V s) : Terminates s := by
  have hcsr : ∀ t, Reaches s t → ConcSub L (sys t) :=
    fun t ht => reaches_concSub hw hem hdj hcse hok hfr hqh hcs ht
  exact terminates_of_bounds4
    (P := V.card * 2 ^ V.card * 2 ^ L.card) (Q := V.card * 2 ^ V.card * 2 ^ L.card)
    (E := V.card) (R := V.card * 2 ^ L.card)
    (fun t ht => reaches_wf hw ht) hvf hcsr
    (fun _ _ => rowSet_card_le)
    (fun t ht => procSys_card_leL (hvf t ht) (hcsr t ht))
    (fun t ht => kdist_length_leL (reaches_wf hw ht) (hvf t ht) (hcsr t ht)
      (fun p hp => List.mem_append_left _ hp) (reaches_kdist hki hkp ht).1)
    (fun t ht => env_len_le_card (hvf t ht) (reaches_envNodup hnd ht))

/-- The same, as the explicit FUEL. -/
theorem vocFixed_run {V : Finset Var} {L : Finset Label} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixed V s) :
    Finished (run s (measure4 (V.card * 2 ^ V.card * 2 ^ L.card)
      (V.card * 2 ^ V.card * 2 ^ L.card) V.card (V.card * 2 ^ L.card) V L s + 1)) := by
  have hcsr : ∀ t, Reaches s t → ConcSub L (sys t) :=
    fun t ht => reaches_concSub hw hem hdj hcse hok hfr hqh hcs ht
  exact terminates_of_bounds4_aux _ s (le_refl _)
    (fun t ht => reaches_wf hw ht) hvf hcsr
    (fun _ _ => rowSet_card_le)
    (fun t ht => procSys_card_leL (hvf t ht) (hcsr t ht))
    (fun t ht => kdist_length_leL (reaches_wf hw ht) (hvf t ht) (hcsr t ht)
      (fun p hp => List.mem_append_left _ hp) (reaches_kdist hki hkp ht).1)
    (fun t ht => env_len_le_card (hvf t ht) (reaches_envNodup hnd ht))

/-- **The headline: a solve on which the loop draws no id TERMINATES.**  `V` and `L` are the
input's own vocabulary and label pool, so neither is an assumption. -/
theorem noDraw_terminates {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) (h : NoDraw s) : Terminates s :=
  vocFixed_terminates (L := labelsOf (sys s)) hem hdj hcse hw hnd hok hfr hqh
    (concSub_self s) hki hkp (vocFixed_of_noDraw hdj hcse h)

/-- The state both `Seed.solve` and `Replay.replay` build: the queue `PQueue.build`
returned, an empty processed queue and an empty environment. -/
def initState (q : PQueue) (su : Sup) (tr : List String) (fl : Flags) (ns : Names)
    (site : String) (z : Nat) : State :=
  { incm := q, proc := PQueue.empty, env := {}, su := su, trace := tr, flags := fl,
    names := ns, site := site, su0 := z }

/-- **The corollary a reviewer applies to a real solve.**  `EnvNodup`, the two `KDist`s and
`QueueHygiene` are free at an initial state, so what is left is the three shipped flags, L3's
supply invariant and the run-level condition itself. -/
theorem vocFixed_terminates_of_buildQueue {V : Finset Var} {L : Finset Label}
    {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z)))
    (hcs : ConcSub L (sys (initState q su' tr fl ns site z)))
    (hvf : VocFixed V (initState q su' tr fl ns site z)) :
    Terminates (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  refine vocFixed_terminates hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) hcs (kdist_ofList ps) ?_ hvf
  simp [initState, PQueue.empty, KDist]

/-- ...and the same with the run-level condition replaced by the id count, which is what the
model reports (`looptrace --replay <trace> --cycle`, the `drawn=` column). -/
theorem noDraw_terminates_of_buildQueue {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z)))
    (h : NoDraw (initState q su' tr fl ns site z)) :
    Terminates (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  refine noDraw_terminates hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) (kdist_ofList ps) ?_ h
  simp [initState, PQueue.empty, KDist]

/-! ## 8. The condition is DECIDABLE per solve

`NoDraw` quantifies over `Reaches`, which is not a decidable predicate; but on a run that
FINISHES it is a finite check, and `NoDrawB` is that check.  So the certification is not only
measurable by the harness -- it is discharged inside Lean, by `decide`, for any given solve. -/

/-- Run the loop for `n` dequeues, checking at each that the supply did not move. -/
def NoDrawB : Nat → State → Bool
  | 0, s => match step s with
    | .continue _ => false
    | _ => true
  | n + 1, s => match step s with
    | .continue s' => (s'.su.drawn == s.su.drawn) && NoDrawB n s'
    | _ => true

theorem noDrawB_reaches : ∀ {n : Nat} {s t : State}, NoDrawB n s = true → Reaches s t →
    ∃ m, NoDrawB m t = true := by
  intro n s t h hr
  induction hr with
  | refl => exact ⟨n, h⟩
  | @tail t0 u0 _ hstep ih =>
    obtain ⟨m, hm⟩ := ih
    cases m with
    | zero => rw [NoDrawB, hstep] at hm; exact absurd hm (by simp)
    | succ k =>
      rw [NoDrawB, hstep] at hm
      simp only [Bool.and_eq_true] at hm
      exact ⟨k, hm.2⟩

/-- **The check is sound.** -/
theorem noDraw_of_noDrawB {n : Nat} {s : State} (h : NoDrawB n s = true) : NoDraw s := by
  intro t t' hr hst
  obtain ⟨m, hm⟩ := noDrawB_reaches h hr
  cases m with
  | zero => rw [NoDrawB, hst] at hm; exact absurd hm (by simp)
  | succ k =>
    rw [NoDrawB, hst] at hm
    simp only [Bool.and_eq_true, beq_iff_eq] at hm
    exact hm.1

/-! ## 9. The fragment is inhabited OUTSIDE round 6's

A four-constraint input with labels on which the `concrete` dispatch branch fires -- so
`NoConc` is false and `noConc_terminates` does not apply -- and on which the loop draws no
id, so this round's theorem does.  The supply is a REAL one (`blk` ahead of `hi`), not
`Sup.ofSeed`, whose `blk = 0` makes `SupFresh` false; that is the same supply shape a corpus
replay reads out of its `sin` record. -/

section Witness
set_option maxRecDepth 40000

def vSeed : Seed :=
  { name := "vocfix",
    cons := [⟨0, [], [0, 1]⟩, ⟨1, [0, 2], []⟩, ⟨2, [3], []⟩, ⟨4, [1], []⟩],
    rhoKeys := [] }

/-- A supply the way the compiler hands one to `Subst.solve`: a live block below a global
counter that is ahead of it.  `Sup.ofSeed`'s `blk = 0` would make `SupFresh` false. -/
def vSu : Sup := { lo := 10, hi := 1000, blk := 1000, bsz := 1024 }

def vNs : Names := (seedSystem vSeed 5).2

def vQ : PQueue :=
  match buildQueue (seedSystem vSeed 5).1 vSu with
  | .ok (q, _) => q
  | .error _ => PQueue.empty

def vSu2 : Sup :=
  match buildQueue (seedSystem vSeed 5).1 vSu with
  | .ok (_, su) => su
  | .error _ => vSu

theorem vBuild : buildQueue (seedSystem vSeed 5).1 vSu = .ok (vQ, vSu2) := by rfl

def vS0 : State := initState vQ vSu2 [] {} vNs "vocfix" 10

theorem vS0_size : vS0.incm.elems.length = 4 := by rfl

theorem vS0_hasLabel : vS0.parts.any (fun p => !p.rhs.conc.elems.isEmpty) = true := by rfl

/-- The input CARRIES labels, so round 6's fragment does not contain it. -/
theorem vS0_notNoConc : ¬ NoConc vS0 := by
  intro h
  obtain ⟨p, hp, hne⟩ := List.any_eq_true.mp vS0_hasLabel
  rw [h p hp] at hne
  simp at hne

/-- The run takes a `concrete` dispatch step -- the branch `NoConc.step_trichotomy` and
`NoConc.step_kdist` discharge by `exfalso`. -/
theorem vS0_concrete : isConcDispatch vS0 = true := by rfl

theorem vS0_solved : Finished (run vS0 40) := by trivial

/-- ...and draws no id, which is this round's condition. -/
theorem vS0_noDrawB : NoDrawB 20 vS0 = true := by rfl

theorem vS0_noDraw : NoDraw vS0 := noDraw_of_noDrawB vS0_noDrawB

theorem vS0_sup : vS0.su.lo = 10 ∧ vS0.su.hi = 1000 ∧ vS0.su.blk = 1000 ∧ vS0.su.bsz = 1024 :=
  ⟨by rfl, by rfl, by rfl, by rfl⟩

theorem vS0_supOk : SupOk vS0.su :=
  ⟨by rw [vS0_sup.1, vS0_sup.2.1]; omega,
   by rw [vS0_sup.2.1, vS0_sup.2.2.1],
   by rw [vS0_sup.2.2.2]; omega⟩

/-- Every variable of the state is one of the seed's five, all below the supply's floor. -/
theorem vS0_parts_lt : (vS0.parts.all (fun p => p.lhs < 10 &&
    p.rhs.abstr.elems.all (fun w => w < 10))) = true := by rfl

theorem vS0_env_nil : vS0.env.binds = [] := by rfl

theorem vS0_supFresh : SupFresh vS0.su (sys vS0) := by
  intro z hz hmem
  obtain ⟨c, hc, hzc⟩ := Finset.mem_biUnion.mp hmem
  have hlt : z < 10 := by
    rcases mem_sys.mp hc with ⟨p, hp, rfl⟩ | ⟨b, hb, -⟩
    · have hall := List.all_eq_true.mp vS0_parts_lt p hp
      simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at hall
      rcases Finset.mem_insert.mp hzc with rfl | hz2
      · simpa using hall.1
      · have := hall.2 z (by simpa [LPart.toConstraint] using hz2)
        simpa using this
    · rw [vS0_env_nil] at hb; exact absurd hb (by simp)
  obtain ⟨hlo, hhi, hblk, -⟩ := vS0_sup
  rcases hz with ⟨h2, -⟩ | h2
  · rw [hlo] at h2; omega
  · rw [hblk] at h2; omega

/-- **The theorem applies**, on standard axioms, to an input round 6's does not cover. -/
theorem vS0_terminates : Terminates vS0 := by
  obtain ⟨ps, hps⟩ := buildQueue_ofList vBuild
  refine noDraw_terminates (by rfl) (by rfl) (by rfl)
    (wf_seed vSeed 5 vBuild {} vNs "vocfix" 10)
    (envNodup_initial {} vNs "vocfix" vSu2 [] 10) vS0_supOk vS0_supFresh
    (queueHygiene_of_env_nil vS0_env_nil) ?_ ?_ vS0_noDraw
  · show KDist vQ.elems
    rw [hps]; exact kdist_ofList ps
  · show KDist PQueue.empty.elems
    simp [PQueue.empty, KDist]

end Witness

/-! ## 10. Termination is a TAIL property of the draws

`noDraw_terminates` asks the loop never to draw.  It is enough that it STOPS drawing: a run
that reaches a state after which nothing is drawn terminates, because termination transports
backwards along `Runs`.  The contrapositive is the sharp statement this stage has been after
since round 4 -- **a divergent solve must draw ids at cofinally many steps**, so non-termination
lives entirely in the generative rules and nowhere else. -/

theorem runs_snoc : ∀ {n : Nat} {s t u : State}, Runs n s t → step t = .continue u →
    Runs (n + 1) s u
  | 0, s, t, u, h, hst => by
    simp only [Runs] at h; subst h; exact ⟨u, hst, rfl⟩
  | n + 1, s, t, u, h, hst => by
    obtain ⟨s', hstep, hrest⟩ := h
    exact ⟨s', hstep, runs_snoc hrest hst⟩

theorem runs_of_reaches {s t : State} (h : Reaches s t) : ∃ n, Runs n s t := by
  induction h with
  | refl => exact ⟨0, rfl⟩
  | @tail t0 u0 _ hstep ih =>
    obtain ⟨n, hn⟩ := ih
    exact ⟨n + 1, runs_snoc hn hstep⟩

theorem terminates_of_runs {n : Nat} {s t : State} (h : Runs n s t) (ht : Terminates t) :
    Terminates s := by
  obtain ⟨m, hm⟩ := ht
  exact ⟨n + m, by rw [h.run_eq n m]; exact hm⟩

/-- **Termination transports backwards along `Reaches`.** -/
theorem terminates_of_reaches {s t : State} (h : Reaches s t) (ht : Terminates t) :
    Terminates s := by
  obtain ⟨n, hn⟩ := runs_of_reaches h
  exact terminates_of_runs hn ht

/-- The loop stops drawing at some point. -/
def EventuallyNoDraw (s : State) : Prop := ∃ t, Reaches s t ∧ NoDraw t

/-- **A solve that stops drawing TERMINATES.** -/
theorem terminates_of_eventuallyNoDraw {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : EventuallyNoDraw s) : Terminates s := by
  obtain ⟨t, hr, hnd0⟩ := h
  obtain ⟨hdj', hcse', hok', hfr', hqh'⟩ := reaches_invariants hdj hcse hok hfr hqh hr
  obtain ⟨hki', hkp'⟩ := reaches_kdist hki hkp hr
  have hfl := reaches_flags_eq hr
  exact terminates_of_reaches hr
    (noDraw_terminates (by rw [hfl]; exact hem) hdj' hcse' (reaches_wf hw hr)
      (reaches_envNodup hnd hr) hok' hfr' hqh' hki' hkp' hnd0)

/-- **A DIVERGENT solve draws at cofinally many steps.**  The contrapositive: at every state
a non-terminating run reaches, some later step still draws an id.  So non-termination is
localised entirely in `splitConcrete` and `resolution` -- the four non-generative branches and
the whole of `learnPartitions`' folding half cannot cause it. -/
theorem draws_cofinally_of_not_terminates {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ Terminates s) : ∀ t, Reaches s t → ¬ NoDraw t :=
  fun t hr hnd0 =>
    h (terminates_of_eventuallyNoDraw hem hdj hcse hw hnd hok hfr hqh hki hkp ⟨t, hr, hnd0⟩)

/-- ...and it has no fixed vocabulary: for EVERY finite `V` some reachable state mentions a
variable outside it. -/
theorem not_vocFixed_of_not_terminates {L : Finset Label} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ Terminates s) : ∀ V : Finset Var, ¬ VocFixed V s :=
  fun V hvf => h (vocFixed_terminates hem hdj hcse hw hnd hok hfr hqh hcs hki hkp hvf)

/-! ## 11. The only way to diverge is to mint without bound

`terminates_of_eventuallyNoDraw` is a TAIL condition, so on a run already observed to finish
it certifies nothing new.  This section replaces it by a CARDINAL one: a run that draws at
most `k` ids in total terminates, whatever `k` is.  Its contrapositive is the statement the
stage has been aiming at since round 4 -- **a divergent solve draws unboundedly many ids** --
and, unlike the tail version, its hypothesis is the sort of thing a mint bound could supply. -/

/-- The supply's draw count never goes down inside `learnPartitions`. -/
theorem learnPartitions_drawn_ge {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    su.drawn ≤ su'.drawn := by
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, -, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨-, rfl⟩ := h2
    exact Nat.le_refl _
  · refine foldl_except_inv
      (P := fun (a : SSet LPart × Sup) => su.drawn ≤ a.2.drawn)
      (Q := fun (_ : LPart) => True) ?_ _ (fun _ _ => trivial) _ ?_ _ h
    · intro acc p2 _hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        have haD : su.drawn ≤ asu.drawn := hacc _ hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · cases hres : resolution fl v rhs1 p2.rhs
              (fun k => findResolvent v (mkLookups v incm proc) aS k)
              (fun k => if fl.splitRow || fl.resRow then
                findConcRow (mkLookups v incm proc) k else none)
              (fun k => if fl.emptyRow then
                findEmptyRow env (mkLookups v incm proc) k else none) asu with
          | mk rps nsu =>
            have hge : asu.drawn ≤ nsu.drawn := by
              have := resolution_drawn_ge (fl := fl) (v := v) (rhs1 := rhs1) (rhs2 := p2.rhs)
                (resolvent := fun k => findResolvent v (mkLookups v incm proc) aS k)
                (concRow := fun k => if fl.splitRow || fl.resRow then
                  findConcRow (mkLookups v incm proc) k else none)
                (emptyRow := fun k => if fl.emptyRow then
                  findEmptyRow env (mkLookups v incm proc) k else none) (su := asu)
              rw [hres] at this; exact this
            rw [hres] at hb
            simp only [hdj, Bool.not_false, if_true, pure, Except.pure,
              Except.ok.injEq] at hb
            subst hb
            exact (le_trans haD hge : su.drawn ≤ nsu.drawn)
        · have hcs : (commonSubexpression fl v rhs1 p2.lhs p2.rhs
              (fun r => findRHS3 incm proc aS r) asu).2 = asu :=
            commonSubexpression_su_of_cut hcse
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m => rw [hsub] at hb; simp only [] at hb; exact absurd hb (by simp)
          | ok sps =>
            rw [hsub] at hb
            simp only [hdj, Bool.not_false, if_true, pure, Except.pure,
              Except.ok.injEq] at hb
            subst hb
            show su.drawn ≤ (commonSubexpression fl v rhs1 p2.lhs p2.rhs
              (fun r => findRHS3 incm proc aS r) asu).2.drawn
            rw [hcs]; exact haD
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      exact splitConcrete_drawn_ge

/-- **A step never gives an id back.** -/
theorem step_drawn_ge {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : step s = .continue s') :
    s.su.drawn ≤ s'.su.drawn := by
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact Nat.le_refl _
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Nat.le_refl _
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Nat.le_refl _
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact Nat.le_refl _
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              dsimp only at h
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact (learnPartitions_drawn_ge hdj hcse hlp : s.su.drawn ≤ su2.drawn)

theorem reaches_drawn_ge {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hr : Reaches s t) : s.su.drawn ≤ t.su.drawn := by
  induction hr with
  | refl => exact Nat.le_refl _
  | @tail t0 u0 hr0 hstep ih =>
    have hfl := reaches_flags_eq hr0
    exact le_trans ih (step_drawn_ge (by rw [hfl]; exact hdj) (by rw [hfl]; exact hcse) hstep)

/-- **A divergent solve draws UNBOUNDEDLY many ids.** -/
theorem drawn_unbounded_of_not_terminates {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ Terminates s) : ∀ n : Nat, ∃ t, Reaches s t ∧ s.su.drawn + n ≤ t.su.drawn := by
  intro n
  induction n with
  | zero => exact ⟨s, Reaches.refl s, by omega⟩
  | succ k ih =>
    obtain ⟨t, hrt, hdt⟩ := ih
    obtain ⟨hdj', hcse', hok', hfr', hqh'⟩ := reaches_invariants hdj hcse hok hfr hqh hrt
    have hfl := reaches_flags_eq hrt
    obtain ⟨hki', hkp'⟩ := reaches_kdist hki hkp hrt
    have hnt : ¬ Terminates t := fun ht => h (terminates_of_reaches hrt ht)
    have := draws_cofinally_of_not_terminates (by rw [hfl]; exact hem) hdj' hcse'
      (reaches_wf hw hrt) (reaches_envNodup hnd hrt) hok' hfr' hqh' hki' hkp' hnt t
      (Reaches.refl t)
    simp only [NoDraw, not_forall] at this
    obtain ⟨u, u', hru, hstep, hne⟩ := this
    have h1 : t.su.drawn ≤ u.su.drawn := reaches_drawn_ge hdj' hcse' hru
    have hflu := reaches_flags_eq hru
    have h2 : u.su.drawn ≤ u'.su.drawn := step_drawn_ge
      (by rw [hflu, hfl]; exact hdj) (by rw [hflu, hfl]; exact hcse) hstep
    exact ⟨u', reaches_trans hrt (hru.tail hstep), by omega⟩

/-- **A solve that draws BOUNDEDLY many ids terminates.**  This is the per-class lemma the
residue needs: `k` is not required to be zero, only to exist. -/
theorem terminates_of_drawsAtMost {k : Nat} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ∀ t, Reaches s t → t.su.drawn ≤ s.su.drawn + k) : Terminates s := by
  by_contra hnt
  obtain ⟨t, hrt, hdt⟩ := drawn_unbounded_of_not_terminates hem hdj hcse hw hnd hok hfr hqh
    hki hkp hnt (k + 1)
  have := h t hrt
  omega

end Rowpartition.Loop
