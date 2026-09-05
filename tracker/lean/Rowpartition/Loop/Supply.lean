/-
# L5 round 4 (R4.2): `SupOk` and `SupFresh` are PRESERVED by `step`

`RefineLearn.RunSupOk n s` is `SupOk` and `SupFresh` **at every state of the run** -- a
per-state hypothesis, not an invariant, and L3's row says so.  It gates two things: the
`learn` branch of `step_refines_all`, and (round 3) the run-level queue-hygiene theorems
`run_queueHygiene` / `run_queueHygiene'`, hence the B1 certification.  The round-3 review's
Q-1 and item (4) ask for it to be discharged.  This module does that.

## What was missing, and why the existing machinery could not give it

`Hygiene.lean`'s `learnPartitions_avoids` is parametric in a FIXED predicate `B` and needs
`SupAvoids B su`: *no id the supply can still hand out is `B`*.  That is exactly what a
freshness clause cannot assume of itself -- the ids a step DRAWS are ids the supply could
hand out, so with `B` "still drawable at the END of the step" the hypothesis is false.  The
clause `learnPartitions_vocab` derived from it ("in the old vocabulary or ANY reachable id")
is for the same reason too weak (round-3 review F-4).

The repair is to let the predicate move with the supply.  `New Old su w` is "`w` is not an
old name and `su` can still hand it out"; it SHRINKS as the supply is drawn from, so

* every rule's conclusion avoids `New Old (rule's OWN output supply)` -- §2, the three
  drawing rules re-proved with that conclusion, which needs no `SupAvoids` hypothesis at all;
* `New Old` is monotone along a draw (§1), so the fold's invariant
  "every name accumulated so far avoids `New Old (the current supply)`" is a genuine FORWARD
  invariant and `foldl_except_inv` carries it -- §3.

That gives C2's sharp vocabulary clause `learnPartitions_new`: every name a `learn` step
writes is an old name or an id the step has already spent.  §4 turns it into `SupFresh`
preservation for all five branches, and §5 into `RunSupOk` as a theorem and the
UNCONDITIONAL run-level queue hygiene and panic-unreachability.
-/
import Rowpartition.Loop.Refuted

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. The moving predicate -/

/-- **`w` is not an old name, and the supply `su` can still hand it out.**  This is the
predicate a step must not write, and the one that moves with the supply. -/
def New (Old : Var → Prop) (su : Sup) (w : Var) : Prop := ¬ Old w ∧ Sup.Reach su w

theorem not_new_of_old {Old : Var → Prop} {su : Sup} {w : Var} (h : Old w) :
    ¬ New Old su w := fun hn => hn.1 h

/-- Drawing only shrinks the reachable set, so `New` only shrinks. -/
theorem New.mono {Old : Var → Prop} {su su' : Sup}
    (hm : ∀ z, Sup.Reach su' z → Sup.Reach su z) {w : Var} (h : New Old su' w) :
    New Old su w := ⟨h.1, hm w h.2⟩

/-- **The drawn id is not `New` at the supply that drew it.** -/
theorem not_new_fresh {Old : Var → Prop} {su : Sup} (hok : SupOk su) :
    ¬ New Old (su.fresh).2 (su.fresh).1 :=
  fun h => (fresh_reach_mono hok _ h.2).2 rfl

/-- One draw, as a reachability inclusion. -/
theorem reach_fresh_mono {su : Sup} (hok : SupOk su) :
    ∀ z, Sup.Reach (su.fresh).2 z → Sup.Reach su z :=
  fun z hz => (fresh_reach_mono hok z hz).1

/-- A supply that is either untouched or drawn from once. -/
def SupStep (su su' : Sup) : Prop := su' = su ∨ su' = (su.fresh).2

theorem SupStep.reach {su su' : Sup} (hok : SupOk su) (h : SupStep su su') :
    ∀ z, Sup.Reach su' z → Sup.Reach su z := by
  rcases h with rfl | rfl
  · exact fun _ hz => hz
  · exact reach_fresh_mono hok

theorem SupStep.supOk {su su' : Sup} (hok : SupOk su) (h : SupStep su su') : SupOk su' := by
  rcases h with rfl | rfl
  · exact hok
  · exact fresh_supOk hok

theorem SupStep.refl (su : Sup) : SupStep su su := Or.inl rfl

/-- `Avoids` at a `New` predicate, from the old-name hypotheses a rule's premises give. -/
theorem avoids_new_of_old {Old : Var → Prop} {su : Sup} {a : Nat} {r : RHS}
    {i : Option Inference} (ha : Old a) (hr : ∀ w ∈ r.abstr.elems, Old w) :
    Avoids (New Old su) (⟨a, r, i⟩ : LPart).toConstraint :=
  avoids_mk_of (not_new_of_old ha) (fun w hw => not_new_of_old (hr w hw))

/-! ## 2. The three drawing rules, with the sharp conclusion

Each rule's conclusion avoids `New Old` **at the rule's own output supply**.  In a branch
that does not draw, the output supply is the input one and every name written is old; in the
branch that draws, the drawn id is not `New` at the supply that drew it (`not_new_fresh`).
No `SupAvoids` hypothesis appears -- that is the whole point (see the module note). -/

theorem splitConcrete_su {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    SupStep su (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2 := by
  unfold splitConcrete
  split
  · exact SupStep.refl _
  · split
    · exact SupStep.refl _
    · split
      · exact SupStep.refl _
      · split
        · exact SupStep.refl _
        · split
          · exact SupStep.refl _
          · split
            · exact SupStep.refl _
            · split
              rename_i u su2 hfr
              exact Or.inr (by rw [hfr])

theorem resolution_su {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    SupStep su (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2 := by
  simp only [resolution]
  split
  · exact SupStep.refl _
  · split
    · split
      · exact Or.inr rfl
      · split
        · exact Or.inr rfl
        · split
          · exact Or.inr rfl
          · split
            · exact Or.inr rfl
            · exact Or.inr rfl
    · exact SupStep.refl _

theorem not_new_of_reach {Old : Var → Prop} {su su' : Sup}
    (hm : ∀ z, Sup.Reach su' z → Sup.Reach su z) {w : Var} (h : ¬ New Old su w) :
    ¬ New Old su' w := fun hn => h (New.mono hm hn)

theorem splitConcrete_new {Old : Var → Prop} {fl : Flags} {v : Nat} {abstr : SSet Nat}
    {concr : SSet Lbl} {rhss : RHS → Option Nat}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} (hok : SupOk su)
    (hv : ¬ New Old su v) (ha : ∀ w ∈ abstr.elems, ¬ New Old su w)
    (hr : ∀ r w, rhss r = some w → ¬ New Old su w)
    (hres : ∀ k w, resolvent k = some w → ¬ New Old su w)
    (hcr : ∀ k w, concRow k = some w → ¬ New Old su w) :
    ∀ x ∈ (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).1.elems,
      Avoids (New Old (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2)
        x.toConstraint := by
  have hmn : ∀ w, ¬ New Old su w → ¬ New Old (su.fresh).2 w :=
    fun w h => not_new_of_reach (reach_fresh_mono hok) h
  have hone : ∀ (su0 : Sup) (u : Nat), ¬ New Old su0 u →
      ∀ w ∈ (SSet.ofList [u] : SSet Nat).elems, ¬ New Old su0 w := by
    intro su0 u hu w hw
    have := SSet.mem_ofList hw
    rw [List.mem_singleton] at this
    subst this; exact hu
  unfold splitConcrete
  split
  · exact fun x hx => absurd hx (by simp [SSet.empty])
  · split
    · rename_i u hu
      intro x hx
      have hx' := SSet.mem_ofList hx
      rw [List.mem_singleton] at hx'
      subst hx'
      exact avoids_mk_of hv (hone _ u (hr _ _ hu))
    · split
      · exact fun x hx => absurd hx (by simp [SSet.empty])
      · split
        · rename_i w hw
          intro x hx
          have hx' := SSet.mem_ofList hx
          rw [List.mem_singleton] at hx'
          subst hx'
          have hwB : ¬ New Old su w := by
            split at hw
            · exact hres _ _ hw
            · exact absurd hw (by simp)
          exact avoids_mk_of hwB (by simpa [RHS.ofAbstr] using ha)
        · split
          · rename_i w hw
            intro x hx
            have hx' := SSet.mem_ofList hx
            rw [List.mem_singleton] at hx'
            subst hx'
            have hwB : ¬ New Old su w := by
              split at hw
              · exact hcr _ _ hw
              · exact absurd hw (by simp)
            exact avoids_mk_of hwB (by simpa [RHS.ofAbstr] using ha)
          · split
            · intro x hx
              obtain ⟨w, hw, rfl⟩ := SSet.mem_map hx
              exact avoids_empty_rhs (ha w hw)
            · split
              rename_i u su2 hfr
              intro x hx
              have hx' := SSet.mem_ofList hx
              simp only [List.mem_cons, List.not_mem_nil, or_false] at hx'
              have hsu2 : su2 = (su.fresh).2 := by rw [hfr]
              have hu2 : u = (su.fresh).1 := by rw [hfr]
              have huB : ¬ New Old su2 u := by
                rw [hsu2, hu2]; exact not_new_fresh hok
              have haB : ∀ w ∈ abstr.elems, ¬ New Old su2 w := by
                intro w hw; rw [hsu2]; exact hmn w (ha w hw)
              rcases hx' with rfl | rfl
              · exact avoids_mk_of huB (by simpa [RHS.ofAbstr] using haB)
              · exact avoids_mk_of (by rw [hsu2]; exact hmn _ hv) (hone _ u huB)

theorem resolution_new {Old : Var → Prop} {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} (hok : SupOk su)
    (hv : ¬ New Old su v) (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ New Old su w)
    (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ New Old su w)
    (hres : ∀ k w, resolvent k = some w → ¬ New Old su w)
    (hcr : ∀ k w, concRow k = some w → ¬ New Old su w) :
    ∀ x ∈ (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).1.elems,
      Avoids (New Old (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2)
        x.toConstraint := by
  have hmn : ∀ w, ¬ New Old su w → ¬ New Old (su.fresh).2 w :=
    fun w h => not_new_of_reach (reach_fresh_mono hok) h
  have hone : ∀ (su0 : Sup) (u : Nat), ¬ New Old su0 u →
      ∀ w ∈ (SSet.ofList [u] : SSet Nat).elems, ¬ New Old su0 w := by
    intro su0 u hu w hw
    have := SSet.mem_ofList hw
    rw [List.mem_singleton] at this
    subst this; exact hu
  simp only [resolution]
  split
  · exact fun x hx => absurd hx (by simp [SSet.empty])
  · split
    · rename_i x y hx0 hy0
      have hxB : ¬ New Old (su.fresh).2 x := hmn _ (h1 x (mem_of_single? hx0))
      have hyB : ¬ New Old (su.fresh).2 y := hmn _ (h2 y (mem_of_single? hy0))
      have hzB : ¬ New Old (su.fresh).2 (su.fresh).1 := not_new_fresh hok
      split
      · exact fun c hc => absurd hc (by simp [SSet.empty])
      · split
        · rename_i w hw
          have hwB : ¬ New Old (su.fresh).2 w := by
            split at hw
            · exact hmn _ (hres _ _ hw)
            · exact absurd hw (by simp)
          intro c hc
          have hc' := SSet.mem_ofList hc
          simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
          rcases hc' with rfl | rfl
          · exact avoids_mk_of hxB (hone _ w hwB)
          · exact avoids_mk_of hyB (hone _ w hwB)
        · split
          · rename_i w hw
            have hwB : ¬ New Old (su.fresh).2 w := by
              split at hw
              · exact hmn _ (hcr _ _ hw)
              · exact absurd hw (by simp)
            intro c hc
            have hc' := SSet.mem_ofList hc
            simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
            rcases hc' with rfl | rfl
            · exact avoids_mk_of hxB (hone _ w hwB)
            · exact avoids_mk_of hyB (hone _ w hwB)
          · split
            · intro c hc
              have hc' := SSet.mem_ofList hc
              simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
              rcases hc' with rfl | rfl
              · exact avoids_conc_rhs hxB
              · exact avoids_conc_rhs hyB
            · intro c hc
              have hc' := SSet.mem_ofList hc
              simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
              rcases hc' with rfl | rfl | rfl
              · exact avoids_mk_of (hmn _ hv) (hone _ _ hzB)
              · exact avoids_mk_of hxB (hone _ _ hzB)
              · exact avoids_mk_of hyB (hone _ _ hzB)
    · exact fun x hx => absurd hx (by simp [SSet.empty])

/-- Under the shipped `genRules=cut`, `commonSubexpression` draws nothing
(`RefineLearn.commonSubexpression_su`), so its output supply is its input one and every name
it writes is one it was given. -/
theorem commonSubexpression_new {Old : Var → Prop} {fl : Flags} {v : Nat} {rhs1 : RHS}
    {u : Nat} {rhs2 : RHS} {rhss : RHS → Option Nat} {su : Sup} (hcse : fl.cseMints = false)
    (hv : ¬ New Old su v) (hu : ¬ New Old su u)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ New Old su w)
    (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ New Old su w)
    (hr : ∀ r w, rhss r = some w → ¬ New Old su w) :
    ∀ x ∈ (commonSubexpression fl v rhs1 u rhs2 rhss su).1.elems,
      Avoids (New Old (commonSubexpression fl v rhs1 u rhs2 rhss su).2) x.toConstraint := by
  have hincl : ∀ (a : SSet Nat) (t : SSet Nat) (z : Nat),
      (∀ w ∈ a.elems, ¬ New Old su w) → ¬ New Old su z →
      ∀ w ∈ ((a.removedAll t).incl z).elems, ¬ New Old su w := by
    intro a t z ha hz w hw
    rcases SSet.mem_incl hw with hw' | rfl
    · exact ha w (SSet.mem_removedAll hw')
    · exact hz
  simp only [commonSubexpression]
  split
  · exact fun x hx => absurd hx (by simp [SSet.empty])
  · split
    · rename_i z hz
      have hzB : ¬ New Old su z := hr _ _ hz
      intro c hc
      have hc' := SSet.mem_ofList hc
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
      rcases hc' with rfl | rfl
      · exact avoids_mk_of hv (hincl _ _ _ h1 hzB)
      · exact avoids_mk_of hu (hincl _ _ _ h2 hzB)
    · split
      · intro c hc
        have hc' := SSet.mem_ofList hc
        rw [List.mem_singleton] at hc'
        subst hc'
        exact avoids_mk_of hu (hincl _ _ _ h2 hv)
      · split
        · intro c hc
          have hc' := SSet.mem_ofList hc
          rw [List.mem_singleton] at hc'
          subst hc'
          exact avoids_mk_of hv (hincl _ _ _ h1 hu)
        · split
          · exact fun x hx => absurd hx (by simp [SSet.empty])
          · rename_i hh
            exact absurd hcse (by simpa using hh)

/-! ## 3. The `learn` step: C2's SHARP vocabulary clause

The fold's invariant is `P (S, su_i)` = "`su_i` is coherent, it can hand out no more than the
step's initial supply could, and every name accumulated so far avoids `New Old su_i`".  That
is a forward invariant precisely because `New` shrinks along a draw, which is what the fixed
`B` of `learnPartitions_avoids` could not express. -/

/-- Every name of `p` is an old one. -/
def OldPart (Old : Var → Prop) (p : LPart) : Prop :=
  Old p.lhs ∧ ∀ w ∈ p.rhs.abstr.elems, Old w

theorem avoids_new_of_oldPart {Old : Var → Prop} {su : Sup} {p : LPart}
    (h : OldPart Old p) : Avoids (New Old su) p.toConstraint :=
  avoids_toConstraint_iff.mpr ⟨not_new_of_old h.1, fun w hw => not_new_of_old (h.2 w hw)⟩

/-- **C2's sharp vocabulary clause.**  Every name a `learn` step writes is an OLD name or an
id the step has already SPENT -- so no name it writes is one the supply can still hand out.
The supply stays coherent and only shrinks. -/
theorem learnPartitions_new {Old : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hok : SupOk su) (hv : Old v)
    (hr1 : ∀ w ∈ rhs1.abstr.elems, Old w)
    (hi : ∀ x ∈ incm.elems, OldPart Old x)
    (hp : ∀ x ∈ proc.elems, OldPart Old x)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    SupOk su' ∧ (∀ z, Sup.Reach su' z → Sup.Reach su z) ∧
      ∀ x ∈ S.elems, Avoids (New Old su') x.toConstraint := by
  have hiA : ∀ (su0 : Sup), ∀ x ∈ incm.elems, Avoids (New Old su0) x.toConstraint :=
    fun su0 x hx => avoids_new_of_oldPart (hi x hx)
  have hpA : ∀ (su0 : Sup), ∀ x ∈ proc.elems, Avoids (New Old su0) x.toConstraint :=
    fun su0 x hx => avoids_new_of_oldPart (hp x hx)
  have hlk : ∀ (su0 : Sup), LkAvoids (New Old su0) (mkLookups v incm proc) :=
    fun su0 => mkLookups_avoids (hiA su0) (hpA su0)
  have hcr : ∀ (su0 : Sup), ∀ k w, (if fl.splitRow || fl.resRow then
      findConcRow (mkLookups v incm proc) k else none) = some w → ¬ New Old su0 w := by
    intro su0 k w hw
    split at hw
    · exact findConcRow_avoids (hlk su0) hw
    · exact absurd hw (by simp)
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, hS0, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    exact ⟨hok, fun _ hz => hz,
      selfSubstitution_avoids (fun w hw => not_new_of_old (hr1 w hw)) hS0⟩
  · refine foldl_except_inv
      (P := fun (a : SSet LPart × Sup) =>
        SupOk a.2 ∧ (∀ z, Sup.Reach a.2 z → Sup.Reach su z) ∧
          (∀ x ∈ a.1.elems, Avoids (New Old a.2) x.toConstraint))
      (Q := fun (x : LPart) => OldPart Old x) ?_ _ hp _ ?_ _ h
    · intro acc p2 hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        obtain ⟨haOk, haR, haA⟩ := hacc _ hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        have hvA : ¬ New Old asu v := not_new_of_old hv
        have hr1A : ∀ w ∈ rhs1.abstr.elems, ¬ New Old asu w :=
          fun w hw => not_new_of_old (hr1 w hw)
        have hp2A : ¬ New Old asu p2.lhs ∧ ∀ w ∈ p2.rhs.abstr.elems, ¬ New Old asu w :=
          ⟨not_new_of_old hp2.1, fun w hw => not_new_of_old (hp2.2 w hw)⟩
        split at hb
        · -- the resolution / cancellation arm
          have hstep : SupStep asu (resolution fl v rhs1 p2.rhs
              (fun k => findResolvent v (mkLookups v incm proc) aS k)
              (fun k => if fl.splitRow || fl.resRow then
                findConcRow (mkLookups v incm proc) k else none)
              (fun k => if fl.emptyRow then
                findEmptyRow env (mkLookups v incm proc) k else none) asu).2 := resolution_su
          have hrs := resolution_new (Old := Old) (fl := fl) (v := v) (rhs1 := rhs1)
            (rhs2 := p2.rhs)
            (resolvent := fun k => findResolvent v (mkLookups v incm proc) aS k)
            (concRow := fun k => if fl.splitRow || fl.resRow then
              findConcRow (mkLookups v incm proc) k else none)
            (emptyRow := fun k => if fl.emptyRow then
              findEmptyRow env (mkLookups v incm proc) k else none)
            haOk hvA hr1A hp2A.2
            (fun k w hw => findResolvent_avoids (hlk asu) haA hw) (hcr asu)
          simp only [hdj, Bool.not_false, if_true,
            pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          have hbR : ∀ z, Sup.Reach (resolution fl v rhs1 p2.rhs
              (fun k => findResolvent v (mkLookups v incm proc) aS k)
              (fun k => if fl.splitRow || fl.resRow then
                findConcRow (mkLookups v incm proc) k else none)
              (fun k => if fl.emptyRow then
                findEmptyRow env (mkLookups v incm proc) k else none) asu).2 z →
              Sup.Reach asu z := hstep.reach haOk
          refine ⟨hstep.supOk haOk, fun z hz => haR z (hbR z hz), fun x hx => ?_⟩
          rcases SSet.mem_concat hx with hx' | hx'
          · rcases SSet.mem_concat hx' with hx'' | hx''
            · rcases SSet.mem_concat hx'' with hx3 | hx3
              · exact Avoids.mono (fun w hw => New.mono hbR hw) (haA x hx3)
              · exact hrs x hx3
            · exact cancellation_avoids (B := New Old _) (v := v)
                (fun w hw => not_new_of_reach hbR (hr1A w hw))
                (fun w hw => not_new_of_reach hbR (hp2A.2 w hw)) x hx''
          · exact absurd hx' (by simp [SSet.empty])
        · -- the commonSubexpression / substitution arm
          have hcs : (commonSubexpression fl v rhs1 p2.lhs p2.rhs
              (fun r => findRHS3 incm proc aS r) asu).2 = asu :=
            commonSubexpression_su hcse _ _ _ _ _ _
          have hcse' := commonSubexpression_new (Old := Old) (fl := fl) (v := v) (rhs1 := rhs1)
            (u := p2.lhs) (rhs2 := p2.rhs)
            (rhss := fun r => findRHS3 incm proc aS r)
            hcse hvA hp2A.1 hr1A hp2A.2
            (fun r w hw => findRHS3_avoids (hiA asu) (hpA asu) haA hw)
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m => rw [hsub] at hb; simp only [] at hb; exact absurd hb (by simp)
          | ok sps =>
            rw [hsub] at hb
            simp only [hdj, Bool.not_false,
              if_true, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            rw [hcs] at hcse' ⊢
            refine ⟨haOk, haR, fun x hx => ?_⟩
            rcases SSet.mem_concat hx with hx' | hx'
            · rcases SSet.mem_concat hx' with hx'' | hx''
              · rcases SSet.mem_concat hx'' with hx3 | hx3
                · exact haA x hx3
                · exact hcse' x hx3
              · exact substitution_avoids (B := New Old asu) hvA hp2A.1 hr1A hp2A.2 hsub x hx''
            · exact absurd hx' (by simp [SSet.empty])
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      have hstep : SupStep su (splitConcrete fl v rhs1.abstr rhs1.conc
          (fun r => findRHS3 incm proc SSet.empty r)
          (fun k => findResolvent v (mkLookups v incm proc) SSet.empty k)
          (fun k => if fl.splitRow || fl.resRow then
            findConcRow (mkLookups v incm proc) k else none)
          (fun k => if fl.emptyRow then
            findEmptyRow env (mkLookups v incm proc) k else none) su).2 := splitConcrete_su
      exact ⟨hstep.supOk hok, hstep.reach hok,
        splitConcrete_new (Old := Old) hok (not_new_of_old hv)
          (fun w hw => not_new_of_old (hr1 w hw))
          (fun r w hw => findRHS3_avoids (hiA su) (hpA su)
            (fun x hx => absurd hx (by simp [SSet.empty])) hw)
          (fun k w hw => findResolvent_avoids (hlk su)
            (fun x hx => absurd hx (by simp [SSet.empty])) hw) (hcr su)⟩

/-! ## 4. `SupOk` and `SupFresh` are preserved by `step` -/

/-- `Avoids` for a constraint of the system, at the state's own vocabulary. -/
theorem avoids_new_of_mem_sys {s : State} {c : Constraint} (su0 : Sup) (hc : c ∈ sys s) :
    Avoids (New (fun w => w ∈ allVars (sys s)) su0) c :=
  ⟨not_new_of_old (lhs_mem_allVars hc),
    fun _w hw => not_new_of_old (vset_subset_allVars hc hw)⟩

theorem oldPart_of_mem_parts {s : State} {p : LPart} (hp : p ∈ s.parts) :
    OldPart (fun w => w ∈ allVars (sys s)) p :=
  ⟨lhs_mem_allVars_sys hp,
    fun w hw => vset_subset_allVars_sys hp (by simpa using List.mem_toFinset.mpr hw)⟩

@[simp] theorem envVal_lhs (a : Nat) (val : EnvVal) :
    (EnvVal.toConstraint a val).lhs = a := by cases val <;> rfl

/-- An environment fact avoids `B` when its variable and its value's variable do. -/
theorem avoids_envVal {B : Var → Prop} {a : Nat} {val : EnvVal} (ha : ¬ B a)
    (hval : ∀ u, val = EnvVal.alias u → ¬ B u) : Avoids B (EnvVal.toConstraint a val) := by
  cases val with
  | emptyRow => exact ⟨by simpa using ha, by simp [EnvVal.toConstraint]⟩
  | «alias» u0 =>
    refine ⟨by simpa using ha, ?_⟩
    intro w hw
    simp only [EnvVal.toConstraint, vset_mk, Finset.mem_singleton] at hw
    subst hw
    exact hval _ rfl

/-- The value's variable, when there is one. -/
theorem envVal_alias_avoids {B : Var → Prop} {a u : Nat}
    (h : Avoids B (EnvVal.toConstraint a (EnvVal.alias u))) : ¬ B u :=
  h.2 u (by simp [EnvVal.toConstraint])

/-- `instantiateType` keeps every fact's names inside the old ones plus the new binding's. -/
theorem avoids_env_instantiate {B : Var → Prop} {e : Env} {v : Nat} {val : EnvVal}
    (he : ∀ b ∈ e.binds, Avoids B (EnvVal.toConstraint b.1 b.2))
    (hv : ¬ B v) (hval : ∀ u, val = EnvVal.alias u → ¬ B u) :
    ∀ b ∈ (e.instantiate v val).binds, Avoids B (EnvVal.toConstraint b.1 b.2) := by
  intro b hb
  simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton] at hb
  rcases hb with ⟨p, hp, rfl⟩ | rfl
  · have hold := he p hp
    have hlhs : ¬ B p.1 := by simpa using hold.1
    dsimp only
    cases hpv : p.2 with
    | emptyRow => exact avoids_envVal hlhs (by simp)
    | «alias» w =>
      rw [hpv] at hold
      dsimp only
      split
      · exact avoids_envVal hlhs hval
      · exact avoids_envVal hlhs (by
          intro u hu
          simp only [EnvVal.alias.injEq] at hu
          subst hu
          exact envVal_alias_avoids hold)
  · exact avoids_envVal hv hval

theorem avoids_sys_of {B : Var → Prop} {s : State}
    (hp : ∀ p ∈ s.parts, Avoids B p.toConstraint)
    (he : ∀ b ∈ s.env.binds, Avoids B (EnvVal.toConstraint b.1 b.2)) :
    ∀ c ∈ sys s, Avoids B c := by
  intro c hc
  rcases mem_sys.mp hc with ⟨p, hp', rfl⟩ | ⟨b, hb, rfl⟩
  · exact hp p hp'
  · exact he b hb

theorem supFresh_of_avoids_sys {G : System} {Old : Var → Prop} {su0 : Sup}
    (hOld : ∀ z, Sup.Reach su0 z → ¬ Old z)
    (h : ∀ c ∈ G, Avoids (New Old su0) c) : SupFresh su0 G := by
  intro z hz hmem
  simp only [allVars, Finset.mem_biUnion] at hmem
  obtain ⟨c, hc, hzc⟩ := hmem
  have hav := h c hc
  rcases Finset.mem_insert.mp hzc with hzl | hzc'
  · exact hav.1 (hzl ▸ ⟨hOld z hz, hz⟩)
  · exact hav.2 z hzc' ⟨hOld z hz, hz⟩

/-- **`SupOk` and `SupFresh` are preserved by every `continue` step**, under the shipped
flags.  This is the rest of C2, and it makes `RunSupOk` a theorem (§5). -/
theorem step_supFresh {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') :
    SupOk s'.su ∧ (∀ z, Sup.Reach s'.su z → Sup.Reach s.su z) ∧ SupFresh s'.su (sys s') := by
  set Old : Var → Prop := fun w => w ∈ allVars (sys s) with hOldDef
  have hi0 : ∀ x ∈ s.incm.elems, OldPart Old x :=
    fun x hx => oldPart_of_mem_parts (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, OldPart Old x :=
    fun x hx => oldPart_of_mem_parts (List.mem_append_right _ hx)
  have hiA : ∀ (su0 : Sup), ∀ x ∈ s.incm.elems, Avoids (New Old su0) x.toConstraint :=
    fun su0 x hx => avoids_new_of_oldPart (hi0 x hx)
  have hpA : ∀ (su0 : Sup), ∀ x ∈ s.proc.elems, Avoids (New Old su0) x.toConstraint :=
    fun su0 x hx => avoids_new_of_oldPart (hp0 x hx)
  have heA : ∀ (su0 : Sup), ∀ b ∈ s.env.binds,
      Avoids (New Old su0) (EnvVal.toConstraint b.1 b.2) :=
    fun su0 b hb => avoids_new_of_mem_sys su0 (mem_sys_of_env hb)
  -- the conclusion, once the successor's parts and environment are known to avoid `New Old`
  have hfin : ∀ (t : State), (∀ z, Sup.Reach t.su z → Sup.Reach s.su z) →
      (∀ p ∈ t.parts, Avoids (New Old t.su) p.toConstraint) →
      (∀ b ∈ t.env.binds, Avoids (New Old t.su) (EnvVal.toConstraint b.1 b.2)) →
      SupFresh t.su (sys t) := by
    intro t hmono hparts henv
    refine supFresh_of_avoids_sys (Old := Old) (fun z hz => ?_) (avoids_sys_of hparts henv)
    exact fun hoz => hfr z (hmono z hz) hoz
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (PQueue.dequeue_mem hdq).1
    have hrestMem : ∀ x ∈ rest.elems, x ∈ s.incm.elems := (PQueue.dequeue_mem hdq).2
    have hrestP : ∀ x ∈ rest.elems, OldPart Old x := fun x hx => hi0 x (hrestMem x hx)
    have hrestA : ∀ (su0 : Sup), ∀ x ∈ rest.elems, Avoids (New Old su0) x.toConstraint :=
      fun su0 x hx => avoids_new_of_oldPart (hrestP x hx)
    have hrO : OldPart Old r := hi0 r hrMem
    split at h
    · -- the `common` branch
      rename_i u hu
      have huO : Old u := by
        obtain ⟨x, hx, hxeq, hxl⟩ := findRHS_witness hu
        exact hxl ▸ (hp0 x hx).1
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ ?_⟩
        · intro p hp
          simp only [unifyVars] at hres
          split at hres
          · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
            obtain ⟨rfl, rfl, rfl⟩ := hres
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hrestA _ p hp'
            · exact hpA _ p hp'
          · rename_i hne
            have hvu : r.lhs ≠ u := by simpa using hne
            obtain ⟨hni, hnp⟩ := instantiate_avoids (B := New Old s.su) hvu
              (not_new_of_old huO) (hrestA _) (hpA _) hres
            refine Avoids.mono (B := fun w => New Old s.su w ∨ w = r.lhs)
              (fun w hw => Or.inl hw) ?_
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hni p hp'
            · exact hnp p hp'
        · simp only [unifyVars] at hres
          split at hres
          · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
            obtain ⟨-, -, rfl⟩ := hres
            exact heA _
          · have henv : e = s.env.instantiate r.lhs (.alias u) := (instantiate_env_len hres).2.2
            rw [henv]
            exact avoids_env_instantiate (heA _) (not_new_of_old hrO.1)
              (fun u0 hu0 => by
                simp only [EnvVal.alias.injEq] at hu0
                subst hu0
                exact not_new_of_old huO)
    · split at h
      · -- the `empty` branch
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨hni, hnp⟩ := makeEmpty_avoids (B := New Old s.su) (hrestA _) (hpA _) hres
          have henv : e = s.env.instantiate r.lhs .emptyRow := (makeEmpty_env_len hres).2.2
          refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ ?_⟩
          · intro p hp
            refine Avoids.mono (B := fun w => New Old s.su w ∨ w = r.lhs)
              (fun w hw => Or.inl hw) ?_
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hni p hp'
            · exact hnp p hp'
          · rw [henv]
            exact avoids_env_instantiate (heA _) (not_new_of_old hrO.1) (by simp)
      · split at h
        · -- the `concrete` branch
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨hni, hnp⟩ := makeConcrete_avoids (B := New Old s.su)
              (not_new_of_old hrO.1) (hrestA _) (hpA _) hres
            refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ (heA _)⟩
            intro p hp
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hni p hp'
            · exact hnp p hp'
        · split at h
          · -- the `unify` branch
            rename_i u hsg
            have huO : Old u := by
              refine hrO.2 u ?_
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
              refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ ?_⟩
              · intro p hp
                simp only [unifyVars] at hres
                split at hres
                · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                  obtain ⟨rfl, rfl, rfl⟩ := hres
                  rcases List.mem_append.mp hp with hp' | hp'
                  · exact hrestA _ p hp'
                  · exact hpA _ p hp'
                · rename_i hne
                  have hvu : u ≠ r.lhs := by simpa using hne
                  obtain ⟨hni, hnp⟩ := instantiate_avoids (B := New Old s.su) hvu
                    (not_new_of_old hrO.1) (hrestA _) (hpA _) hres
                  refine Avoids.mono (B := fun w => New Old s.su w ∨ w = u)
                    (fun w hw => Or.inl hw) ?_
                  rcases List.mem_append.mp hp with hp' | hp'
                  · exact hni p hp'
                  · exact hnp p hp'
              · simp only [unifyVars] at hres
                split at hres
                · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                  obtain ⟨-, -, rfl⟩ := hres
                  exact heA _
                · have henv : e = s.env.instantiate u (.alias r.lhs) :=
                    (instantiate_env_len hres).2.2
                  rw [henv]
                  exact avoids_env_instantiate (heA _) (not_new_of_old huO)
                    (fun u0 hu0 => by
                      simp only [EnvVal.alias.injEq] at hu0
                      subst hu0
                      exact not_new_of_old hrO.1)
          · -- the `learn` branch
            cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              obtain ⟨hok2, hmono, hlearn⟩ := learnPartitions_new (Old := Old) hdj hcse hok
                hrO.1 hrO.2 hrestP hp0 hlp
              refine ⟨hok2, hmono, hfin _ hmono ?_ ?_⟩
              · intro p hp
                simp only [foldl_log_env] at hp ⊢
                rcases List.mem_append.mp hp with hp' | hp'
                · exact concatP_avoids (B := New Old su2) _ (hrestA _)
                    (fun d hd => hlearn d (SSet.mem_filter hd)) p hp'
                · exact insertNP_avoids (B := New Old su2) (hpA _) (hiA _ r hrMem) hp'
              · simp only [foldl_log_env]
                exact heA _

/-! ## 5. `RunSupOk` is a THEOREM, and the B1 certification is hypothesis-free

`RefineLearn.RunSupOk n s` unfolds to "`SupOk` and `SupFresh` at this state, and the same at
every state the run reaches".  With §4 that is an induction on the fuel, so the per-state
hypothesis the round-3 review's Q-1 flags disappears from `run_queueHygiene`,
`run_queueHygiene'` and the panic-unreachability corollary. -/

/-- **The supply invariant is an INVARIANT**, not a per-state hypothesis. -/
theorem runSupOk_of {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) :
    ∀ n : Nat, RunSupOk n s
  | 0 => trivial
  | n + 1 => by
    refine ⟨hok, hfr, fun s' hst => ?_⟩
    obtain ⟨hok', -, hfr'⟩ := step_supFresh hdj hcse hok hfr hst
    have hfl := step_flags hst
    exact runSupOk_of (by rw [hfl]; exact hdj) (by rw [hfl]; exact hcse) hok' hfr' n

/-- **Queue hygiene at every state a run reaches -- UNCONDITIONALLY.**  Round 3's
`run_queueHygiene` carried `RunSupOk n s`; it is now discharged. -/
theorem run_queueHygiene_of (n : Nat) {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) :
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → QueueHygiene s' :=
  run_queueHygiene n hdj (runSupOk_of hdj hcse hok hfr n) h0

/-- ... refutations included. -/
theorem run_queueHygiene'_of (n : Nat) {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) :
    ∀ s' m, run s n = .rejected m s' → QueueHygiene s' :=
  run_queueHygiene' n hdj (runSupOk_of hdj hcse hok hfr n) h0

/-! ### 5.1 The corollary assembled (review Q-2)

`instantiateType`'s `die` -- the reinstantiation panic of `L5-TERMINATION.md` §0 -- tests
`hm.types.get(v)` at the three variables a step can bind.  At every state reachable from a
hygienic one the test fails, so neither `makeEmpty`'s panic arm nor `instantiate`'s is taken.
This is stated over `Reaches` (`Loop/Refuted.lean` §6), which is the same reachability the
run-level theorems use, and it is now free of `RunSupOk`. -/

/-- Hygiene, the supply invariant and the flags all travel along `Reaches`. -/
theorem reaches_invariants {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hr : Reaches s t) :
    t.flags.disjRule = false ∧ t.flags.cseMints = false ∧ SupOk t.su ∧
      SupFresh t.su (sys t) ∧ QueueHygiene t := by
  induction hr with
  | refl => exact ⟨hdj, hcse, hok, hfr, h0⟩
  | tail hr hst ih =>
    obtain ⟨hdj1, hcse1, hok1, hfr1, hh1⟩ := ih
    obtain ⟨hok2, -, hfr2⟩ := step_supFresh hdj1 hcse1 hok1 hfr1 hst
    have hfl := step_flags hst
    exact ⟨by rw [hfl]; exact hdj1, by rw [hfl]; exact hcse1, hok2, hfr2,
      step_queueHygiene hdj1 hok1 hfr1 hh1 hst⟩

/-- **THE PANIC IS UNREACHABLE.**  At every state reachable from a hygienic one, the three
variables a step can bind -- the dequeued left-hand side, its variable parts and the `common`
partner -- are all UNBOUND, which is exactly the condition `Subst.instantiateType`'s `die`
tests.  No `RunSupOk` hypothesis. -/
theorem reaches_binds_unbound {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hr : Reaches s t) {r : LPart} {rest : PQueue}
    (hdq : t.incm.dequeue = some (r, rest)) :
    t.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → t.env.contains u = false) ∧
      (∀ u, t.proc.findRHS r.rhs = some u → t.env.contains u = false) :=
  queueHygiene_binds_unbound (reaches_invariants hdj hcse hok hfr h0 hr).2.2.2.2 hdq

/-- ... and therefore neither link branch can die (`instantiate` returns `ok`). -/
theorem reaches_link_no_death {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (hr : Reaches s t) {r : LPart} {rest : PQueue}
    (hdq : t.incm.dequeue = some (r, rest)) :
    (∀ u, t.proc.findRHS r.rhs = some u →
        ∃ w, unifyVars t.names r.lhs u rest t.proc t.env = .ok w) ∧
      (∀ u, r.rhs.single? = some u →
        ∃ w, unifyVars t.names u r.lhs rest t.proc t.env = .ok w) :=
  step_link_no_death (reaches_invariants hdj hcse hok hfr h0 hr).2.2.2.2 hdq

/-- **The certification, from an INITIAL state**: `Seed.solve` and `Replay` build a state with
`proc` and `env` empty, so `QueueHygiene` is free, and the only remaining hypotheses are the
two shipped flags and the supply's own coherence and freshness -- which the `sin` record's
bounds give for every replay state. -/
theorem initial_binds_unbound {s t : State} (hi : Initial s)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hr : Reaches s t)
    {r : LPart} {rest : PQueue} (hdq : t.incm.dequeue = some (r, rest)) :
    t.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → t.env.contains u = false) ∧
      (∀ u, t.proc.findRHS r.rhs = some u → t.env.contains u = false) :=
  reaches_binds_unbound hdj hcse hok hfr (queueHygiene_of_env_nil hi.2) hr hdq

end Rowpartition.Loop
