/-
# L5 round 3 (R3.4 / C2): how many ids a `learn` step draws

The brief asks, of C2's vocabulary lemma for `learn`: "a learn step may draw more than one id --
say how many".  This module answers it exactly, as a theorem about `Sup.drawn`, the counter the
model carries for the harness's `drawn=` report and which `Sup.fresh` increments on both arms.

Under the SHIPPED flags (`disjunction` off, `genRules=cut` so `commonSubexpression` does not
mint) the answer is

    (learnPartitions ... su).su'.drawn ≤ su.drawn + 1 + proc.elems.length

and it is TIGHT in shape: `splitConcrete` draws at most one, at the top; the fold over `proc`
draws at most one per processed partition, and only through `resolution`, whose `fresh` is taken
BEFORE its guards (so a reuse costs an id too -- `Rules.lean`'s comment, and the reason
`e00346` draws 1,033 ids at one base).  With `-Dermine.disjunction` on the bound is false: each
`disjunction` call draws one or two more, and there are two nested folds over `proc` per step.
-/
import Rowpartition.Loop.Factor
import Rowpartition.Loop.Hygiene

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. One draw -/

theorem fresh_drawn (su : Sup) : (su.fresh).2.drawn = su.drawn + 1 := by
  unfold Sup.fresh
  split <;> rfl

/-! ## 2. The four rules that can draw -/

/-- `splitConcrete` draws at most one id, in its final branch. -/
theorem splitConcrete_drawn {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2.drawn
      ≤ su.drawn + 1 := by
  unfold splitConcrete
  split
  · exact Nat.le_succ _
  · split
    · exact Nat.le_succ _
    · split
      · exact Nat.le_succ _
      · split
        · exact Nat.le_succ _
        · split
          · exact Nat.le_succ _
          · split
            · exact Nat.le_succ _
            · split
              rename_i u su2 hfr
              have hd := fresh_drawn su
              rw [hfr] at hd
              exact le_of_eq hd

/-- `resolution` draws at most one id -- taken BEFORE the guards, so a reuse costs one too. -/
theorem resolution_drawn {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup} :
    (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2.drawn ≤ su.drawn + 1 := by
  simp only [resolution]
  split
  · exact Nat.le_succ _
  · split
    · have hd := fresh_drawn su
      split
      · exact le_of_eq hd
      · split
        · exact le_of_eq hd
        · split
          · exact le_of_eq hd
          · split
            · exact le_of_eq hd
            · exact le_of_eq hd
    · exact Nat.le_succ _

/-- Under `genRules=cut` -- the shipped setting -- `commonSubexpression` draws NOTHING: its
minting branch is the only one that calls `fresh`, and the flag switches it off. -/
theorem commonSubexpression_no_draw {fl : Flags} {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS}
    {rhss : RHS → Option Nat} {su : Sup} (hcse : fl.cseMints = false) :
    (commonSubexpression fl v rhs1 u rhs2 rhss su).2 = su := by
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
          · rename_i hh
            exact absurd hcse (by simpa using hh)

/-! ## 3. The fold over `proc`, and `learnPartitions` -/

/-- Each pass of `incorporateAll`'s `learnPartitions` fold draws at most one id, so a fold over
`ps` draws at most `ps.length`.  Stated over the fold's own body so that no rule's shape is
restated. -/
theorem foldl_learn_drawn {fl : Flags} {v : Nat} {rhs1 : RHS} {incm proc : PQueue}
    {l : Lookups} {env : Env} (hdj : fl.disjRule = false) (hcse : fl.cseMints = false) :
    ∀ (ps : List LPart) (acc : Except String (SSet LPart × Sup)) (k : Nat),
      (∀ a, acc = .ok a → a.2.drawn ≤ k) →
      ∀ b, (ps.foldl
        (fun (acc : Except String (SSet LPart × Sup)) (p2 : LPart) => do
          let (s, su) ← acc
          let u := p2.lhs
          let rhs2 := p2.rhs
          if u == v then
            let (rps, su) := resolution fl v rhs1 rhs2 (fun k => findResolvent v l s k)
              (fun k => if fl.splitRow || fl.resRow then findConcRow l k else none)
              (fun k => if fl.emptyRow then findEmptyRow env l k else none) su
            let cps := cancellation v rhs1 rhs2
            let dps :=
              if !fl.disjRule then (SSet.empty, su)
              else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
                if p3.lhs != v then
                  let (d1, s1) := disjunction p3.rhs rhs1 rhs2 a.2
                  let (d2, s2) := disjunction p3.rhs rhs2 rhs1 s1
                  (a.1.concat (d1.concat d2), s2)
                else a) (SSet.empty, su)
            return ((s.concat rps).concat cps |>.concat dps.1, dps.2)
          else
            let (csps, su) := commonSubexpression fl v rhs1 u rhs2
              (fun r => findRHS3 incm proc s r) su
            let sps ← substitution v rhs1 u rhs2
            let dps :=
              if !fl.disjRule then (SSet.empty, su)
              else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
                if p3.lhs == u && !(rhs2.eqv p3.rhs) then
                  let (d1, s1) := disjunction rhs1 rhs2 p3.rhs a.2
                  let (d2, s2) := disjunction rhs1 p3.rhs rhs2 s1
                  (a.1.concat (d1.concat d2), s2)
                else if p3.lhs == v && !(rhs1.eqv p3.rhs) then
                  let (d1, s1) := disjunction rhs2 rhs1 p3.rhs a.2
                  let (d2, s2) := disjunction rhs2 p3.rhs rhs1 s1
                  (a.1.concat (d1.concat d2), s2)
                else a) (SSet.empty, su)
            return ((s.concat csps).concat sps |>.concat dps.1, dps.2)) acc) = .ok b →
        b.2.drawn ≤ k + ps.length
  | [], acc, k, hacc, b, hb => by simpa using hacc b hb
  | p :: ps, acc, k, hacc, b, hb => by
    have hstep : ∀ b0, (do
        let (s, su) ← acc
        let u := p.lhs
        let rhs2 := p.rhs
        if u == v then
          let (rps, su) := resolution fl v rhs1 rhs2 (fun k => findResolvent v l s k)
            (fun k => if fl.splitRow || fl.resRow then findConcRow l k else none)
            (fun k => if fl.emptyRow then findEmptyRow env l k else none) su
          let cps := cancellation v rhs1 rhs2
          let dps :=
            if !fl.disjRule then (SSet.empty, su)
            else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
              if p3.lhs != v then
                let (d1, s1) := disjunction p3.rhs rhs1 rhs2 a.2
                let (d2, s2) := disjunction p3.rhs rhs2 rhs1 s1
                (a.1.concat (d1.concat d2), s2)
              else a) (SSet.empty, su)
          return ((s.concat rps).concat cps |>.concat dps.1, dps.2)
        else
          let (csps, su) := commonSubexpression fl v rhs1 u rhs2
            (fun r => findRHS3 incm proc s r) su
          let sps ← substitution v rhs1 u rhs2
          let dps :=
            if !fl.disjRule then (SSet.empty, su)
            else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
              if p3.lhs == u && !(rhs2.eqv p3.rhs) then
                let (d1, s1) := disjunction rhs1 rhs2 p3.rhs a.2
                let (d2, s2) := disjunction rhs1 p3.rhs rhs2 s1
                (a.1.concat (d1.concat d2), s2)
              else if p3.lhs == v && !(rhs1.eqv p3.rhs) then
                let (d1, s1) := disjunction rhs2 rhs1 p3.rhs a.2
                let (d2, s2) := disjunction rhs2 p3.rhs rhs1 s1
                (a.1.concat (d1.concat d2), s2)
              else a) (SSet.empty, su)
          return ((s.concat csps).concat sps |>.concat dps.1, dps.2)) = .ok b0 →
        b0.2.drawn ≤ k + 1 := by
      intro b0 hb0
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb0; simp only [bind, Except.bind] at hb0; exact absurd hb0 (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        have ha : asu.drawn ≤ k := hacc _ hacc'
        rw [hacc'] at hb0
        simp only [bind, Except.bind] at hb0
        split at hb0
        · simp only [hdj, Bool.not_false, if_true, pure, Except.pure,
            Except.ok.injEq] at hb0
          subst hb0
          exact le_trans (resolution_drawn (fl := fl) (v := v) (rhs1 := rhs1) (rhs2 := p.rhs)
            (resolvent := fun k => findResolvent v l aS k)
            (concRow := fun k => if fl.splitRow || fl.resRow then findConcRow l k else none)
            (emptyRow := fun k => if fl.emptyRow then findEmptyRow env l k else none)
            (su := asu)) (by omega)
        · cases hsub : substitution v rhs1 p.lhs p.rhs with
          | error m =>
            rw [hsub] at hb0; simp only [] at hb0; exact absurd hb0 (by simp)
          | ok sps =>
            rw [hsub] at hb0
            simp only [hdj, Bool.not_false, if_true, pure,
              Except.pure, Except.ok.injEq] at hb0
            subst hb0
            have heq := commonSubexpression_no_draw (fl := fl) (v := v) (rhs1 := rhs1)
              (u := p.lhs) (rhs2 := p.rhs) (rhss := fun r => findRHS3 incm proc aS r)
              (su := asu) hcse
            have hgoal : (commonSubexpression fl v rhs1 p.lhs p.rhs
                (fun r => findRHS3 incm proc aS r) asu).2.drawn ≤ k + 1 := by
              rw [heq]; omega
            exact hgoal
    have hrec := foldl_learn_drawn (fl := fl) (v := v) (rhs1 := rhs1) (incm := incm)
      (proc := proc) (l := l) (env := env) hdj hcse ps _ (k + 1) hstep b hb
    simp only [List.length_cons]
    omega

/-- **How many ids a `learn` step draws.**  At most one for `splitConcrete` and at most one per
processed partition for `resolution`, under the shipped flags.  This is the quantitative half
of C2's question. -/
theorem learnPartitions_drawn {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    su'.drawn ≤ su.drawn + 1 + proc.elems.length := by
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, -, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨-, rfl⟩ := h2
    omega
  · refine foldl_learn_drawn hdj hcse _ _ (su.drawn + 1) ?_ (S, su') h
    intro a ha
    rw [Except.ok.injEq] at ha
    subst ha
    exact splitConcrete_drawn

/-! ## 4. A vocabulary clause for `learn` -- weaker than C2's

`learnPartitions_avoids` is parametric in the predicate `B`, and taking `B` to be the COMPLEMENT
of "a variable the queues already had, or an id the supply can still hand out" turns it into the
statement that no rule invents a name out of thin air.

**This is NOT the clause C2 needs** (`L5-REVIEW.md` round 3, F-4).  C2 -- `SupFresh` PRESERVED by
`step` -- needs "in the old vocabulary, or one of the ids THIS step actually drew"; the clause
below says "or ANY id the supply can ever hand out", which is the whole tail of the supply and
so cannot preserve `SupFresh` at all.  `learnPartitions_drawn` above counts the drawn ids; the
strengthening that intersects the two is what C2 is still missing, and it is not written. -/

/-- Every name a rule writes is a variable the queues already had or an id the supply can still
hand out.  Weaker than C2's clause -- see the section note. -/
theorem learnPartitions_vocab {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup} {V : Finset Var}
    (hdj : fl.disjRule = false) (hv : v ∈ V) (hr1 : ∀ w ∈ rhs1.abstr.elems, w ∈ V)
    (hi : ∀ x ∈ incm.elems, x.lhs ∈ V ∧ ∀ w ∈ x.rhs.abstr.elems, w ∈ V)
    (hp : ∀ x ∈ proc.elems, x.lhs ∈ V ∧ ∀ w ∈ x.rhs.abstr.elems, w ∈ V)
    (hok : SupOk su)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∀ x ∈ S.elems, (x.lhs ∈ V ∨ Sup.Reach su x.lhs) ∧
      ∀ w ∈ x.rhs.abstr.elems, (w ∈ V ∨ Sup.Reach su w) := by
  set B : Var → Prop := fun w => ¬ (w ∈ V ∨ Sup.Reach su w) with hB
  have key := learnPartitions_avoids (B := B) hdj hok
    (fun z hz hb => hb (Or.inr hz))
    (fun hb => hb (Or.inl hv))
    (fun w hw hb => hb (Or.inl (hr1 w hw)))
    (fun x hx => avoids_toConstraint_iff.mpr
      ⟨fun hb => hb (Or.inl (hi x hx).1), fun w hw hb => hb (Or.inl ((hi x hx).2 w hw))⟩)
    (fun x hx => avoids_toConstraint_iff.mpr
      ⟨fun hb => hb (Or.inl (hp x hx).1), fun w hw hb => hb (Or.inl ((hp x hx).2 w hw))⟩) h
  intro x hx
  obtain ⟨h1, h2⟩ := avoids_toConstraint_iff.mp (key x hx)
  exact ⟨not_not.mp h1, fun w hw => not_not.mp (h2 w hw)⟩

end Rowpartition.Loop
