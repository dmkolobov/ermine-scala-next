/-
# L5 round 3 (R3.5): the residual, stated exactly, and the bound it yields

Round 3 proves ingredient (B) of `L5-TERMINATION.md` §C3.1 for every `LoopStrict` constructor
that can have it (`Carried.lean`, `LoopStrict.carried_step`) and the vocabulary SNAPSHOT bound
that follows along carried-preserving runs (`LoopStrictKRun.allVars_card_le` -- not a mint
count; see the note there).  It also proves that the
loop's own steps CANNOT satisfy the (B) clause over `sys`: after an elimination the only
constraint about the eliminated variable is the retained alias link, which carries the key `∅`
and no other (`carried_iff_of_link_only`, `substOut_breaks_carried`), and `Q.+!`'s
`CommonPartition` redirect destroys a `ConcCarried` parent outright
(`redirect_breaks_carried`, below).  So the measure has to be taken over `qsys` -- the
queue-visible system, which drops the alias facts -- exactly as §C3.1's table says.

This module states what remains, as one `Prop` (`QStepDichotomy`), and proves that it is
SUFFICIENT for a loop-level VOCABULARY SNAPSHOT bound, with the explicit bound
`|allVars (qsys s₀)| + hmeas L rho (qsys s₀)` on the queue-visible vocabulary held at any one
state.  It is NOT sufficient for a mint COUNT and not for `Terminates`; both gaps are recorded
on `run_qsys_allVars_card_le` and in `L5-TERMINATION.md` §R3.5.  The outcome for R3.5 is
therefore **(T2) with the exact remaining lemma**, not (T1) and not (W).
-/
import Rowpartition.Loop.Draws

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

/-! ## 1. The third place `Carried` is destroyed: `Q.+!`'s redirect

`insertP`'s `CommonPartition` redirect replaces the insertion of `w <- (S, K)` into a queue
that already holds `a <- (S, K)` by the insertion of `w <- (a)` (`Loop/Queue.lean`).  The two
systems have the same models -- `w <- (a)` with `a <- (S,K)` says exactly what `w <- (S,K)`
says -- but the SYNTACTIC guard does not see it: a `ConcCarried` witness needs a concrete
definition of `w` itself.  This is the redirect analogue of `substOut_breaks_carried`, and it
is the reason (B) is open over `qsys` as well as over `sys`. -/

/-- **The `CommonPartition` redirect destroys a `ConcCarried` parent.**  `G` holds
`v3 <- ((|l0,l1|))` and `v2 <- ((|l1|))`; inserting `v1 <- ((|l0,l1|))` carries the key
`(v1, {l0})`, and inserting the redirect's `v1 <- (v3)` instead does not, although the two
insertions are logically equivalent over `G`. -/
theorem redirect_breaks_carried :
    ∃ (G : System) (w a : Var) (S : Finset Var) (K J : Row),
      mk a S K ∈ G ∧ Carried (insert (mk w S K) G) w J ∧
        ¬ Carried (insert (mk w {a} (∅ : Row)) G) w J := by
  refine ⟨{mk 3 ∅ ({0, 1} : Row), mk 2 ∅ ({1} : Row)}, 1, 3, ∅, {0, 1}, {0}, by simp, ?_, ?_⟩
  · refine Carried.of_conc (z := 2) (C := ({0, 1} : Row)) (Finset.mem_insert_self _ _) ?_
    have h : ({0, 1} : Row) \ ({0} : Row) = ({1} : Row) := by decide
    rw [h]
    simp
  · rintro (h | h)
    · obtain ⟨z, hz⟩ := (resolved_iff _ 1 ({0} : Row)).mp h
      simp only [Finset.mem_insert, Finset.mem_singleton,
        Rowpartition.NameLoss.mk_eq_iff] at hz
      rcases hz with ⟨-, -, hc⟩ | ⟨h1, -, -⟩ | ⟨h1, -, -⟩
      · exact absurd hc.symm (by decide)
      · exact absurd h1 (by decide)
      · exact absurd h1 (by decide)
    · obtain ⟨C, z, hC, -⟩ := (concCarried_iff _ 1 ({0} : Row)).mp h
      simp only [Finset.mem_insert, Finset.mem_singleton,
        Rowpartition.NameLoss.mk_eq_iff] at hC
      rcases hC with ⟨-, hS, -⟩ | ⟨h1, -, -⟩ | ⟨h1, -, -⟩
      · exact absurd hS.symm (Finset.singleton_ne_empty 3)
      · exact absurd h1 (by decide)
      · exact absurd h1 (by decide)

/-! ## 1b. (A)'s worse half is vacuous on satisfiable input

`L5-TERMINATION.md` §C3.2 localises the (A) mismatch to two cases: the keys `K ⊇ C` of a
queue-visible parent with concrete row `C` (`concCarried_of_conc_subset`), and the
parent-already-empty case, which carries EVERY key at once (`concCarried_parent_empty`).  The
second is the dangerous one, and it is vacuous at a MINT on satisfiable input: a mint's parent
is the dequeued left-hand side, whose right-hand side has a NONEMPTY concrete part, so the
system cannot also hold `v <- ()`.  (Round 2 could only say this was "vacuous exactly when
`QueueHygiene` holds"; with R3.3's `step_queueHygiene` that reading is available too, but the
satisfiability argument below needs no invariant at all.) -/

/-- The dequeued partition denotes a constraint of the system. -/
theorem dequeued_mem_sys {s : State} {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) : r.toConstraint ∈ sys s :=
  mem_sys_of_incm (PQueue.dequeue_mem hdq).1

/-- **A dequeued partition with a nonempty concrete part forbids `v <- ()`.** -/
theorem dequeued_not_empty_of_sat {s : State} (hsat : SSat (sys s)) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hconc : r.rhs.conc.isEmpty = false) :
    mk r.lhs ∅ (∅ : Row) ∉ sys s := by
  intro hmem
  obtain ⟨rho, hm⟩ := hsat
  have h0 : rho r.lhs = ∅ := sat_empty_iff.mp (hm _ hmem)
  have hr := hm _ (dequeued_mem_sys hdq)
  have hrc : r.toConstraint
      = mk r.lhs (r.rhs.abstr.elems.toFinset) ((r.rhs.conc.elems.map Lbl.n).toFinset) := rfl
  rw [hrc, sat_mk_iff] at hr
  have hne : r.rhs.conc.elems ≠ [] := by
    intro hnil
    exact absurd (by simp [SSet.isEmpty, hnil] : r.rhs.conc.isEmpty = true) (by simp [hconc])
  obtain ⟨x, hx⟩ : ∃ x, x ∈ r.rhs.conc.elems := by
    cases hl : r.rhs.conc.elems with
    | nil => exact absurd hl hne
    | cons y l => exact ⟨y, by simp⟩
  have hin : x.n ∈ (r.rhs.conc.elems.map Lbl.n).toFinset :=
    List.mem_toFinset.mpr (List.mem_map.mpr ⟨x, hx, rfl⟩)
  have : x.n ∈ rho r.lhs := by
    rw [hr.1]; exact Finset.mem_union_left _ hin
  rw [h0] at this
  exact absurd this (Finset.notMem_empty _)

/-- **§C3.2's localisation, sharpened.**  Whatever `ConcCarried` mismatch remains at a mint's
parent, its parent row `C` is NONEMPTY -- so the residual is the `C ⊆ K` half only, which is
`2^{|L \ C|}` keys per parent and not "every key at once". -/
theorem concCarried_parent_nonempty {s : State} (hsat : SSat (sys s)) {r : LPart}
    {rest : PQueue} (hdq : s.incm.dequeue = some (r, rest)) (hconc : r.rhs.conc.isEmpty = false)
    {K : Row} (h : ConcCarried (qsys s) r.lhs K) :
    ∃ C : Row, C ≠ ∅ ∧ mk r.lhs ∅ C ∈ qsys s ∧ ∃ z, mk z ∅ (C \ K) ∈ qsys s := by
  obtain ⟨C, z, hC, hz⟩ := (concCarried_iff (qsys s) r.lhs K).mp h
  refine ⟨C, ?_, hC, z, hz⟩
  rintro rfl
  exact dequeued_not_empty_of_sat hsat hdq hconc (qsys_subset_sys s hC)

/-! ## 1c. The exportable half of the next step: `Q.+!` COVERS what it is given

`R3.5.2b` names the covering lemma the `CarrPresOn` clause needs.  Its queue half is here: after
`concatP`, the queue holds SOMETHING with the inserted partition's right-hand side -- the
partition itself, or the `CommonPartition` redirect's match, which is exactly the case in which
the insertion is logically redundant and syntactically invisible.  The only escape is a
self-unification, which `Q.insert` refuses and `Order.NoSelfUnif` excludes from every reachable
state. -/

theorem sset_eqv_refl {α : Type} [SVal α] [LawfulSVal α] (s : SSet α) : s.eqv s = true := by
  simp only [SSet.eqv, SSet.subsetOf, Bool.and_eq_true, beq_self_eq_true, true_and,
    List.all_eq_true]
  exact fun x hx => (SSet.contains_iff s x).mpr hx

theorem rhs_eqv_refl (r : RHS) : r.eqv r = true := by
  simp only [RHS.eqv, Bool.and_eq_true]
  exact ⟨sset_eqv_refl _, sset_eqv_refl _⟩

theorem insertP_covers {q : PQueue} {p : LPart} :
    (∃ x ∈ (q.insertP p).elems, x.rhs.eqv p.rhs = true) ∨ p.isSelfUnification = true := by
  unfold PQueue.insertP
  split
  · rename_i hs; exact Or.inr hs
  · split
    · rename_i hd
      obtain ⟨x, hx, hxe⟩ := List.any_eq_true.mp hd
      exact Or.inl ⟨x, hx, (Bool.and_eq_true _ _).mp hxe |>.2 |> fun h =>
        (Bool.and_eq_true _ _).mp h |>.2⟩
    · split
      · rename_i w hw
        obtain ⟨x0, hx0, hx0eq, -⟩ := rhsLookup_witness hw
        exact Or.inl ⟨x0, mem_insertNP_of_mem hx0, hx0eq⟩
      · exact Or.inl ⟨p, mem_insertSorted_self p q.elems, rhs_eqv_refl _⟩

theorem concatP_covers : ∀ (ps : List LPart) (q : PQueue) (p : LPart), p ∈ ps →
    (∃ x ∈ (q.concatP ps).elems, x.rhs.eqv p.rhs = true) ∨ p.isSelfUnification = true
  | [], _, _, hp => absurd hp (by simp)
  | d :: ps, q, p, hp => by
    rcases List.mem_cons.mp hp with rfl | hp'
    · rcases insertP_covers (q := q) (p := p) with ⟨x, hx, hxe⟩ | hs
      · exact Or.inl ⟨x, mem_concatP_of_mem ps hx, hxe⟩
      · exact Or.inr hs
    · exact concatP_covers ps (q.insertP d) p hp'

/-! ## 2. The exact remaining lemma -/

/-- **THE REMAINING LEMMA.**  Every `continue` step of the loop is, on the QUEUE-VISIBLE system
`qsys`, one of two things:

* one of the library's KEYED steps `K2StarStep` -- which is ingredient (A) of §C3.1: the loop's
  own mint guard (`findRHS`/`findResolvent`/`findConcRow` missing) must imply the relation's
  (`¬ Carried (qsys s) v K`).  §C3.2 localises the gap to the keys `K ⊇ C` of a queue-visible
  parent with concrete row `C` once the environment holds one empty-row fact, and R3.3's
  `QueueHygiene` kills the parent-already-empty half of that;
* or a step that keeps every carried key of every variable it still has, adds no variable and
  no label, and keeps the model -- which is ingredient (B).  Over `sys` this clause is FALSE
  (`substOut_breaks_carried`); over `qsys` the alias facts are gone, so the elimination case is
  `carried_substOut_of_ne`, and what is left open is the `Q.+!` redirect
  (`redirect_breaks_carried`) and `trim`. -/
def QStepDichotomy (L : Finset Label) : Prop :=
  ∀ (s s' : State) (rho : Assign), Wf s → SModels rho (qsys s) → ConcSub L (qsys s) →
    step s = .continue s' →
    K2StarStep (qsys s) (qsys s') ∨
      (allVars (qsys s') ⊆ allVars (qsys s) ∧ ConcSub L (qsys s') ∧
        CarrPresOn (qsys s) (qsys s') ∧ SModels rho (qsys s'))

/-! ## 3. ... and the bound it yields, assembled -/

/-- One step, under the remaining lemma: the potential does not grow. -/
theorem qstep_pot_le {L : Finset Label} (h : QStepDichotomy L) {s s' : State} {rho : Assign}
    (hw : Wf s) (hm : SModels rho (qsys s)) (hcs : ConcSub L (qsys s))
    (hst : step s = .continue s') :
    ∃ rho', SModels rho' (qsys s') ∧ ConcSub L (qsys s') ∧
      Pot L rho' (qsys s') ≤ Pot L rho (qsys s) := by
  rcases h s s' rho hw hm hcs hst with hk | ⟨hvoc, hcs', hcar, hm'⟩
  · obtain ⟨rho', hm', -, hb⟩ := hk.measure_step hcs hm
    exact ⟨rho', hm', hk.concSub hcs, hb⟩
  · refine ⟨rho, hm', hcs', ?_⟩
    have h1 : hmeas L rho (qsys s') ≤ hmeas L rho (qsys s) := hcar.hmeas_le rho hvoc
    have h2 : (allVars (qsys s')).card ≤ (allVars (qsys s)).card := Finset.card_le_card hvoc
    simp only [Pot]
    omega

/-- **The loop-level bound, conditional on the remaining lemma.**  Along a run from a state
whose queue-visible system has a model, the potential never grows. -/
theorem run_qsys_invariant {L : Finset Label} (h : QStepDichotomy L) :
    ∀ (n : Nat) (s : State), Wf s → ∀ rho : Assign, SModels rho (qsys s) → ConcSub L (qsys s) →
      ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') →
        ∃ rho', SModels rho' (qsys s') ∧ Pot L rho' (qsys s') ≤ Pot L rho (qsys s)
  | 0, s, _, rho, hm, _, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres
      subst hres
      exact ⟨rho, hm, Nat.le_refl _⟩
  | n + 1, s, hw, rho, hm, hcs, s', hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [step_done hst]
        exact ⟨rho, hm, Nat.le_refl _⟩
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      obtain ⟨rho1, hm1, hcs1, hb1⟩ := qstep_pot_le h hw hm hcs hst
      obtain ⟨rho2, hm2, hb2⟩ :=
        run_qsys_invariant h n s0 (step_wf hw hst) rho1 hm1 hcs1 s' hres
      exact ⟨rho2, hm2, le_trans hb2 hb1⟩

/-- **THE LOOP-LEVEL VOCABULARY SNAPSHOT BOUND, conditional on the remaining lemma.**  The
queue-visible vocabulary AT EVERY STATE a run reaches is bounded by the initial one plus the
initial measure.

**This is not a bound on how many times the loop mints** (`L5-REVIEW.md` round 3, F-2).  The
loop's `qsys` SHRINKS at an elimination -- a `common`/`unify` step writes the alias into `env`,
and `qsys` excludes aliases, so the eliminated variable leaves the queue-visible vocabulary --
so a mint(+1)/elimination(-1) alternation keeps `|allVars (qsys ·)|` flat while minting without
limit, and nothing here forbids it.  A genuine mint count needs either a productivity condition
on the counted step or a monotone carrier, and neither is in the tree. -/
theorem run_qsys_allVars_card_le {L : Finset Label} (h : QStepDichotomy L) (n : Nat)
    (s : State) (hw : Wf s) (rho : Assign) (hm : SModels rho (qsys s)) (hcs : ConcSub L (qsys s))
    (s' : State) (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    (allVars (qsys s')).card ≤ (allVars (qsys s)).card + hmeas L rho (qsys s) := by
  obtain ⟨rho', -, hb⟩ := run_qsys_invariant h n s hw rho hm hcs s' hres
  simp only [Pot] at hb
  omega

/-- The same SNAPSHOT bound at the labels the input carries, so that it depends on the input
alone.  Again: it bounds the queue-visible vocabulary held at once, not the mint count. -/
theorem run_qsys_bound {s0 : State} (h : QStepDichotomy (labelsOf (qsys s0))) (n : Nat)
    (hw : Wf s0) (rho : Assign) (hm : SModels rho (qsys s0)) (s' : State)
    (hres : run s0 n = .solved s' ∨ run s0 n = .outOfFuel s') :
    (allVars (qsys s')).card
      ≤ (allVars (qsys s0)).card + hmeas (labelsOf (qsys s0)) rho (qsys s0) :=
  run_qsys_allVars_card_le h n s0 hw rho hm (labelsOf_concSub _) s' hres

end Rowpartition.Loop
