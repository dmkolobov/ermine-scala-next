/-
# L5 round 6 (R6.3): the NO-CONCRETE-LABELS fragment

The round-5 review's V-13 asks for the fragment the CORPUS actually lives in, and names it:
inputs whose partitions carry **no concrete labels at all**.  On such a state

* `splitConcrete` refuses at its first guard (`concr.isEmpty`), so the split mint is
  syntactically unreachable and no id is drawn there;
* `resolution` needs two LONE-variable premises, and the dequeued premise of a `learn` step
  with no labels has two or more abstract parts -- so the pattern match fails and `resolution`
  returns the empty set **without reaching its `fresh`**.  (The review expected the weaker
  statement "no fresh variable enters a partition, but an id is still drawn"; on this fragment
  the draw does not happen either, because `resolution` draws INSIDE the lone-variable case.)
* `makeConcrete`'s dispatch branch needs an all-concrete right-hand side, which is `RHSEmpty`
  here, so the `empty` branch takes it first;
* and every remaining rule -- `selfSubstitution`, `cancellation`, `commonSubexpression`,
  `substitution`, `disjunction` -- builds its concrete parts out of `concat`, `inter` and
  `removedAll` of the premises' concrete parts, so it cannot invent a label.

Hence `NoConc` is preserved (`step_noConc`, `run_noConc`) and the supply never moves: on this
fragment the loop is entirely NON-GENERATIVE.  §7-§10 turn that into TERMINATION with an
explicit bound (`noConc_terminates`, `noConc_run`, `noConc_terminates_of_input`): the
vocabulary is fixed (§9), so the environment and the processed set are bounded by it, and the
queue's own de-duplication bounds the queue (§10).

The measurement is in `tracker/loopmodel/L5-TERMINATION.md`'s round-6 section: every one of
the 373 row-carrying solves of the 129-module stdlib boot is in the fragment, and so is a
quarter of the example corpus.  So `Subst.solve` is proved to terminate on the whole standard
library boot.
-/
import Rowpartition.Loop.Cycle

namespace Rowpartition.Loop

open Rowpartition

variable {α : Type} [SVal α]

/-! ## 1. Empty sets stay empty -/

theorem nil_of_notMem {l : List α} (h : ∀ x, x ∉ l) : l = [] :=
  List.eq_nil_iff_forall_not_mem.mpr h

theorem nil_filter {s : SSet α} (h : s.elems = []) (p : α → Bool) :
    (s.filter p).elems = [] :=
  nil_of_notMem (fun x hx => by
    have hm := SSet.mem_filter hx; rw [h] at hm; simp at hm)

theorem nil_excl {s : SSet α} (h : s.elems = []) (y : α) : (s.excl y).elems = [] :=
  nil_of_notMem (fun x hx => by
    have hm := SSet.mem_excl hx; rw [h] at hm; simp at hm)

theorem nil_inter {s t : SSet α} (h : s.elems = []) : (s.inter t).elems = [] :=
  nil_of_notMem (fun x hx => by
    have hm := SSet.mem_inter hx; rw [h] at hm; simp at hm)

theorem nil_removedAll {s t : SSet α} (h : s.elems = []) : (s.removedAll t).elems = [] :=
  nil_of_notMem (fun x hx => by
    have hm := SSet.mem_removedAll hx; rw [h] at hm; simp at hm)

theorem nil_concat {s t : SSet α} (hs : s.elems = []) (ht : t.elems = []) :
    (s.concat t).elems = [] :=
  nil_of_notMem (fun x hx => by
    rcases SSet.mem_concat hx with hm | hm
    · rw [hs] at hm; simp at hm
    · rw [ht] at hm; simp at hm)

theorem isEmpty_of_nil {s : SSet α} (h : s.elems = []) : s.isEmpty = true := by
  simp [SSet.isEmpty, h]

/-! ## 2. The fragment -/

/-- **The no-concrete-labels fragment.**  No partition of either queue carries a field label.
The state is a system of pure decompositions `a <- (b, c, ...)` over row variables. -/
def NoConc (s : State) : Prop := ∀ p ∈ s.parts, p.rhs.conc.elems = []

theorem NoConc.incm {s : State} (h : NoConc s) {p : LPart} (hp : p ∈ s.incm.elems) :
    p.rhs.conc.elems = [] := h p (List.mem_append_left _ hp)

theorem NoConc.proc {s : State} (h : NoConc s) {p : LPart} (hp : p ∈ s.proc.elems) :
    p.rhs.conc.elems = [] := h p (List.mem_append_right _ hp)

/-- On the fragment `RHS.single?` is exactly `RHS.abstrSingle?`: the dispatch's lone-variable
test and `resolution`'s premise pattern coincide, which is why a `learn` step's dequeued
premise is not a `resolution` premise. -/
theorem single_eq_abstrSingle {r : RHS} (h : r.conc.elems = []) :
    r.single? = r.abstrSingle? := by
  unfold RHS.single? RHS.abstrSingle?
  rw [if_pos (isEmpty_of_nil h)]

/-! ## 3. Every rule keeps the concrete parts empty -/

theorem rhsMerge_conc {r t : RHS} (hr : r.conc.elems = []) (ht : t.conc.elems = [])
    {n : RHS} {es : SSet Nat} (h : rhsMerge r t = .ok (n, es)) : n.conc.elems = [] := by
  simp only [rhsMerge] at h
  split at h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    rw [← h.1]
    exact nil_concat hr ht
  · exact absurd h (by simp)

theorem rhsSubstitute_conc {r : RHS} {v : Nat} {t : RHS} (hr : r.conc.elems = [])
    (ht : t.conc.elems = []) {n : RHS} {es : SSet Nat}
    (h : rhsSubstitute r v t = .ok (n, es)) : n.conc.elems = [] := by
  simp only [rhsSubstitute] at h
  split at h
  · exact rhsMerge_conc (show (r.erase v).conc.elems = [] from hr) ht h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    rw [← h.1]; exact hr

theorem selfSubstitution_conc {ns : Names} {v : Nat} {a : SSet Nat} {c : SSet Lbl}
    {S : SSet LPart} (h : selfSubstitution ns v a c = .ok S) :
    ∀ x ∈ S.elems, x.rhs.conc.elems = [] := by
  simp only [selfSubstitution] at h
  split at h
  · rw [Except.ok.injEq] at h
    subst h
    intro x hx
    obtain ⟨w, -, rfl⟩ := SSet.mem_map hx
    rfl
  · exact absurd h (by simp)

/-- **`splitConcrete` is unreachable**: its first guard refuses an empty concrete part, so it
returns nothing and does not draw. -/
theorem splitConcrete_noConc {fl : Flags} {v : Nat} {abstr : SSet Nat} {concr : SSet Lbl}
    {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : concr.elems = []) :
    splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su = (SSet.empty, su) := by
  simp only [splitConcrete]
  rw [if_pos (by simp [isEmpty_of_nil h])]

/-- **`resolution` is unreachable** at a premise with two or more abstract parts: the
lone-variable pattern fails before the `fresh`, so nothing is emitted AND no id is drawn. -/
theorem resolution_noConc {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (h : rhs1.abstrSingle? = none) :
    resolution fl v rhs1 rhs2 resolvent concRow emptyRow su = (SSet.empty, su) := by
  simp only [resolution]
  split
  · rfl
  · rw [h]

theorem cancellation_conc {v : Nat} {rhs1 rhs2 : RHS} (h1 : rhs1.conc.elems = [])
    (h2 : rhs2.conc.elems = []) :
    ∀ x ∈ (cancellation v rhs1 rhs2).elems, x.rhs.conc.elems = [] := by
  intro x hx
  simp only [cancellation] at hx
  split at hx
  · split at hx
    · have hx' := SSet.mem_ofList hx
      rw [List.mem_singleton] at hx'
      subst hx'
      exact nil_removedAll h2
    · exact absurd hx (by simp [SSet.empty])
  · split at hx
    · split at hx
      · have hx' := SSet.mem_ofList hx
        rw [List.mem_singleton] at hx'
        subst hx'
        exact nil_removedAll h1
      · exact absurd hx (by simp [SSet.empty])
    · exact absurd hx (by simp [SSet.empty])

theorem subBody_conc {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS} {S : SSet LPart}
    (h1 : rhs1.conc.elems = []) (h2 : rhs2.conc.elems = [])
    (h : subBody v rhs1 u rhs2 = .ok S) : ∀ x ∈ S.elems, x.rhs.conc.elems = [] := by
  simp only [subBody] at h
  split at h
  · cases hs : rhsSubstitute rhs2 v rhs1 with
    | error m => rw [hs] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨nrhs, es⟩ := w
      rw [hs] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
      subst h
      intro x hx
      rcases SSet.mem_incl hx with hx' | rfl
      · obtain ⟨w0, -, rfl⟩ := SSet.mem_map hx'
        rfl
      · exact rhsSubstitute_conc h2 h1 hs
  · simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    intro x hx
    exact absurd hx (by simp [SSet.empty])

theorem substitution_conc {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS} {S : SSet LPart}
    (h1 : rhs1.conc.elems = []) (h2 : rhs2.conc.elems = [])
    (h : substitution v rhs1 u rhs2 = .ok S) : ∀ x ∈ S.elems, x.rhs.conc.elems = [] := by
  simp only [substitution] at h
  obtain ⟨S1, hS1, h2'⟩ := except_bind_ok h
  obtain ⟨S2, hS2, h3⟩ := except_bind_ok h2'
  simp only [pure, Except.pure, Except.ok.injEq] at h3
  subst h3
  intro x hx
  rcases SSet.mem_concat hx with hx' | hx'
  · exact subBody_conc h1 h2 hS1 x hx'
  · exact subBody_conc h2 h1 hS2 x hx'

theorem commonSubexpression_conc {fl : Flags} {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS}
    {rhss : RHS → Option Nat} {su : Sup} (h1 : rhs1.conc.elems = [])
    (h2 : rhs2.conc.elems = []) :
    ∀ x ∈ (commonSubexpression fl v rhs1 u rhs2 rhss su).1.elems, x.rhs.conc.elems = [] := by
  have hmem : ∀ (l : List LPart), (∀ y ∈ l, y.rhs.conc.elems = []) →
      ∀ x ∈ (SSet.ofList l).elems, x.rhs.conc.elems = [] :=
    fun l hl x hx => hl x (SSet.mem_ofList hx)
  have hempty : ∀ x ∈ (SSet.empty : SSet LPart).elems, x.rhs.conc.elems = [] := by
    intro x hx; exact absurd hx (by simp [SSet.empty])
  simp only [commonSubexpression]
  split
  · exact hempty
  · split
    · exact hmem _ (by intro y hy; simp only [List.mem_cons, List.not_mem_nil, or_false] at hy
                       rcases hy with rfl | rfl
                       · exact h1
                       · exact h2)
    · split
      · exact hmem _ (by intro y hy; simp only [List.mem_singleton] at hy; subst hy; exact h2)
      · split
        · exact hmem _ (by intro y hy; simp only [List.mem_singleton] at hy; subst hy; exact h1)
        · split
          · exact hempty
          · exact hmem _ (by
              intro y hy
              simp only [List.mem_cons, List.not_mem_nil, or_false] at hy
              rcases hy with rfl | rfl | rfl
              · rfl
              · exact h1
              · exact h2)

/-- `commonSubexpression` draws only in its minting branch, which `genRules=cut` closes. -/
theorem commonSubexpression_su_of_cut {fl : Flags} {v : Nat} {rhs1 : RHS} {u : Nat}
    {rhs2 : RHS} {rhss : RHS → Option Nat} {su : Sup} (hcse : fl.cseMints = false) :
    (commonSubexpression fl v rhs1 u rhs2 rhss su).2 = su := by
  simp only [commonSubexpression]
  repeat' split
  all_goals first | rfl | (rename_i h; simp [hcse] at h)

/-! ## 4. `learnPartitions` on the fragment: nothing derived carries a label, and the
supply does not move -/

/-- **The `learn` step, on the fragment.**  With no labels in the dequeued premise or in the
processed queue, `learnPartitions` derives only label-free partitions and draws no id: the two
generative rules are refused before their `fresh` (`splitConcrete_noConc`,
`resolution_noConc`), `commonSubexpression`'s mint is closed by `genRules=cut` and
`disjunction` is off. -/
theorem learnPartitions_noConc {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hc1 : rhs1.conc.elems = []) (hsg : rhs1.abstrSingle? = none)
    (hp : ∀ x ∈ proc.elems, x.rhs.conc.elems = [])
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    su' = su ∧ ∀ x ∈ S.elems, x.rhs.conc.elems = [] := by
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, hS0, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    exact ⟨rfl, selfSubstitution_conc hS0⟩
  · refine foldl_except_inv
      (P := fun (a : SSet LPart × Sup) =>
        a.2 = su ∧ (∀ x ∈ a.1.elems, x.rhs.conc.elems = []))
      (Q := fun (x : LPart) => x.rhs.conc.elems = []) ?_ _ hp _ ?_ _ h
    · intro acc p2 hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        obtain ⟨hasu, haC⟩ := hacc _ hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · -- resolution / cancellation
          rw [resolution_noConc (fl := fl) (v := v) (rhs2 := p2.rhs)
            (resolvent := fun k => findResolvent v (mkLookups v incm proc) aS k)
            (concRow := fun k => if fl.splitRow || fl.resRow then
              findConcRow (mkLookups v incm proc) k else none)
            (emptyRow := fun k => if fl.emptyRow then
              findEmptyRow env (mkLookups v incm proc) k else none) (su := asu) hsg] at hb
          simp only [hdj, Bool.not_false, if_true, pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          refine ⟨hasu, fun x hx => ?_⟩
          rcases SSet.mem_concat hx with hx' | hx'
          · rcases SSet.mem_concat hx' with hx'' | hx''
            · rcases SSet.mem_concat hx'' with hx3 | hx3
              · exact haC x hx3
              · exact absurd hx3 (by simp [SSet.empty])
            · exact cancellation_conc hc1 hp2 x hx''
          · exact absurd hx' (by simp [SSet.empty])
        · -- commonSubexpression / substitution
          have hcs : (commonSubexpression fl v rhs1 p2.lhs p2.rhs
              (fun r => findRHS3 incm proc aS r) asu).2 = asu :=
            commonSubexpression_su_of_cut hcse
          have hcc := commonSubexpression_conc (fl := fl) (v := v) (rhs1 := rhs1)
            (u := p2.lhs) (rhs2 := p2.rhs) (rhss := fun r => findRHS3 incm proc aS r)
            (su := asu) hc1 hp2
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m => rw [hsub] at hb; simp only [] at hb; exact absurd hb (by simp)
          | ok sps =>
            rw [hsub] at hb
            simp only [hdj, Bool.not_false, if_true, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            rw [hcs]
            refine ⟨hasu, fun x hx => ?_⟩
            rcases SSet.mem_concat hx with hx' | hx'
            · rcases SSet.mem_concat hx' with hx'' | hx''
              · rcases SSet.mem_concat hx'' with hx3 | hx3
                · exact haC x hx3
                · exact hcc x hx3
              · exact substitution_conc hc1 hp2 hsub x hx''
            · exact absurd hx' (by simp [SSet.empty])
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      rw [splitConcrete_noConc (fl := fl) (v := v) (abstr := rhs1.abstr)
        (rhss := fun r => findRHS3 incm proc SSet.empty r)
        (resolvent := fun k => findResolvent v (mkLookups v incm proc) SSet.empty k)
        (concRow := fun k => if fl.splitRow || fl.resRow then
          findConcRow (mkLookups v incm proc) k else none)
        (emptyRow := fun k => if fl.emptyRow then
          findEmptyRow env (mkLookups v incm proc) k else none) (su := su) hc1]
      exact ⟨rfl, fun x hx => absurd hx (by simp [SSet.empty])⟩


/-! ## 5. The queue operations keep the concrete parts empty -/

/-- The property, as a predicate on one partition, so that `Loop/Fragment.lean`'s
`P`-parametric membership lemmas apply verbatim. -/
def CF (p : LPart) : Prop := p.rhs.conc.elems = []

theorem cf_link (a b : Nat) :
    CF ⟨a, RHS.ofAbstr (SSet.ofList [b]), some .commonPartition⟩ := rfl

theorem replace_conc {v u : Nat} {p : LPart} (hp : CF p) :
    ∀ x ∈ (replace v u p).elems, CF x := by
  unfold replace
  split
  · refine ofListQ_mem (P := CF) _ ?_
    intro x hx
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hx
    rcases hx with rfl | rfl
    · exact hp
    · rfl
  · refine ofListQ_mem (P := CF) _ ?_
    intro x hx
    rw [List.mem_singleton] at hx
    subst hx
    exact hp

theorem instantiate_conc {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env}
    (hi : ∀ p ∈ incm.elems, CF p) (hp : ∀ p ∈ proc.elems, CF p)
    (hok : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, CF x) ∧ (∀ x ∈ np.elems, CF x) := by
  have hnps : ∀ x ∈ ((proc.partition (fun p => p.involves v)).1.concat
      (incm.partition (fun p => p.involves v)).1).elems, CF x :=
    sset_concat_mem (partition_fst_mem hp) (partition_fst_mem hi)
  have hmem := foldl_concatP_mem (P := CF) (fun _ _ => cf_link _ _) v u
      ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems
      (incm.partition (fun p => p.involves v)).2
      (fun q hq => replace_conc (hnps q hq)) (partition_snd_mem hi)
  rw [instantiate_eq] at hok
  split at hok
  · exact absurd hok (by simp)
  · simp only [Except.ok.injEq, Prod.mk.injEq] at hok
    obtain ⟨hni, hnp, -⟩ := hok
    exact ⟨hni ▸ hmem, hnp ▸ partition_snd_mem hp⟩

theorem unifyVars_conc {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env}
    (hi : ∀ p ∈ incm.elems, CF p) (hp : ∀ p ∈ proc.elems, CF p)
    (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, CF x) ∧ (∀ x ∈ np.elems, CF x) := by
  unfold unifyVars at h
  split at h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨h1, h2, -⟩ := h
    exact ⟨h1 ▸ hi, h2 ▸ hp⟩
  · exact instantiate_conc hi hp h

theorem makeEmpty_conc {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env}
    (hi : ∀ p ∈ incm.elems, CF p) (hp : ∀ p ∈ proc.elems, CF p)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, CF x) ∧ (∀ x ∈ np.elems, CF x) := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  have hnpsP : ∀ x ∈ nps.elems, CF x := by
    refine foldl_except_inv
      (P := fun (S : SSet LPart) => ∀ x ∈ S.elems, CF x)
      (Q := fun (x : LPart) => CF x) ?_ _ ?_ _ ?_ _ hnps
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        have haP := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · split at hb
          · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact haP
          · split at hb
            · simp only [pure, Except.pure, Except.ok.injEq] at hb
              subst hb
              intro y hy
              rcases SSet.mem_concat hy with hy' | hy'
              · exact haP y hy'
              · obtain ⟨w, -, rfl⟩ := SSet.mem_map hy'
                rfl
            · exact absurd hb (by simp)
        · simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          intro y hy
          rcases SSet.mem_incl hy with hy' | rfl
          · exact haP y hy'
          · exact hx
    · intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact partition_fst_mem hi x hx'
      · exact partition_fst_mem hp x hx'
    · intro b hb
      rw [Except.ok.injEq] at hb; subst hb
      intro y hy
      exact absurd hy List.not_mem_nil
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨rfl, rfl, -⟩ := h2
      refine ⟨?_, partition_snd_mem hp⟩
      exact concatP_mem (P := CF) (fun _ _ => cf_link _ _) _ _
        (fun x hx => hnpsP x (SSet.mem_filter hx)) (partition_snd_mem hi)

/-! ## 6. `NoConc` is preserved, and no id is drawn -/

theorem noConc_of {st : State} (h1 : ∀ x ∈ st.incm.elems, CF x)
    (h2 : ∀ x ∈ st.proc.elems, CF x) : NoConc st := by
  intro q hq
  rcases List.mem_append.mp hq with hq' | hq'
  · exact h1 q hq'
  · exact h2 q hq'


/-- **The step, on the fragment.**  `NoConc` is an invariant of `step`, the `concrete`
dispatch branch is unreachable, and the supply does not move: the fragment is closed under
the loop and the loop is non-generative on it. -/
theorem step_noConc {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : NoConc s) (hst : step s = .continue s') :
    NoConc s' ∧ s'.su = s.su ∧ s'.flags = s.flags := by
  have hi : ∀ p ∈ s.incm.elems, CF p := fun p hp => h.incm hp
  have hp : ∀ p ∈ s.proc.elems, CF p := fun p hp => h.proc hp
  simp only [step, State.log] at hst
  cases hd : s.incm.dequeue with
  | none => rw [hd] at hst; exact absurd hst (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at hst
    dsimp only at hst
    have hrC : CF r := hi r (PQueue.dequeue_mem hd).1
    have hrest : ∀ x ∈ rest.elems, CF x := fun x hx => hi x ((PQueue.dequeue_mem hd).2 x hx)
    split at hst
    · -- common
      rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at hst; exact absurd hst (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at hst
        simp only [StepResult.continue.injEq] at hst
        obtain ⟨h1, h2⟩ := unifyVars_conc hrest hp hu
        subst hst
        exact ⟨noConc_of h1 h2, rfl, rfl⟩
    · split at hst
      · -- empty
        cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at hst; exact absurd hst (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at hst
          simp only [StepResult.continue.injEq] at hst
          obtain ⟨h1, h2⟩ := makeEmpty_conc hrest hp hu
          subst hst
          exact ⟨noConc_of h1 h2, rfl, rfl⟩
      · split at hst
        · -- concrete: UNREACHABLE, because an empty concrete part and an empty abstract part
          -- make the right-hand side `RHSEmpty`, which the previous branch has taken.
          exfalso
          rename_i hne hab
          exact hne (by simp [RHS.isEmpty, hab, isEmpty_of_nil hrC])
        · split at hst
          · -- unify
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at hst; exact absurd hst (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at hst
              simp only [StepResult.continue.injEq] at hst
              obtain ⟨h1, h2⟩ := unifyVars_conc hrest hp hu
              subst hst
              exact ⟨noConc_of h1 h2, rfl, rfl⟩
          · -- learn
            rename_i hsingle
            cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at hst; exact absurd hst (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at hst
              dsimp only at hst
              obtain ⟨tr1, hf1⟩ := foldl_log_state
                (fun (a : State) (p : LPart) =>
                  "learn\t" ++ a.site ++ "\t" ++
                    (if s.proc.contains p then "seen" else "new") ++ "\t" ++ p.toStr a.names)
                learned.elems
                { s with trace := ("step\t" ++ s.site ++ "\t" ++ "learn" ++ "\t" ++
                    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++
                    toString s.proc.size) :: s.trace }
              rw [hf1] at hst
              simp only [StepResult.continue.injEq] at hst
              obtain ⟨hsu, hlC⟩ := learnPartitions_noConc hdj hcse hrC
                (by rw [← single_eq_abstrSingle hrC]; exact hsingle) hp hu
              subst hst
              refine ⟨?_, hsu, rfl⟩
              refine noConc_of (concatP_mem (P := CF) (fun _ _ => cf_link _ _) _ _
                (fun x hx => hlC x (SSet.mem_filter hx)) hrest) ?_
              exact insertNP_mem (P := CF) hrC hp

/-- ...and therefore along a whole run. -/
theorem run_noConc : ∀ (n : Nat) {s s' : State}, s.flags.disjRule = false →
    s.flags.cseMints = false → NoConc s → Runs n s s' →
    NoConc s' ∧ s'.su = s.su ∧ s'.flags = s.flags
  | 0, s, s', _, _, h, hr => by simp only [Runs] at hr; subst hr; exact ⟨h, rfl, rfl⟩
  | n + 1, s, s', hdj, hcse, h, hr => by
    obtain ⟨t, hstep, hrest⟩ := hr
    obtain ⟨ht, hsu, hfl⟩ := step_noConc hdj hcse h hstep
    obtain ⟨h1, h2, h3⟩ := run_noConc n (s := t) (by rw [hfl]; exact hdj)
      (by rw [hfl]; exact hcse) ht hrest
    exact ⟨h1, by rw [h2, hsu], by rw [h3, hfl]⟩


/-! ## 7. The three kinds of step, and the measure they bound

This is the reduction R6.2 asks for, proved here because R6.3 needs it too.  On the fragment
every `continue` step is one of three kinds, and each moves one of three quantities:

* a `learn` step strictly GROWS the processed set (`Order.learn_procSys_lt`: the dequeued
  premise is `Partition.equals`-new, or the COMMON branch would have fired) and leaves the
  environment alone;
* a `common`/`unify`/`empty` step at DISTINCT variables strictly grows the environment
  (`StrictBound.instantiate_env_len` / `makeEmpty_env_len`: `instantiateType` panics on a
  variable already bound, so each of these branches adds exactly one binding);
* a `common`/`unify` step at EQUAL variables changes nothing at all except that the dequeued
  partition is gone -- `unify` at equal variables is the identity (`Order.common_self_drops`),
  so the incoming queue strictly shrinks.

So `Terminates` follows from three BOUNDS along the run: on the environment, on the processed
set and on the incoming queue.  All three are bounds by the VOCABULARY; §9 proves the
vocabulary is fixed on the fragment and discharges the first two, §10 discharges the third
from the queue's own de-duplication, and `noConc_terminates` is the result.  The reduction
`terminates_of_bounds` is stated separately because it is also R6.2's residual: in the GENERAL
case the three hypotheses are exactly what is missing. -/

theorem reaches_trans {s t u : State} (h1 : Reaches s t) (h2 : Reaches t u) : Reaches s u := by
  induction h2 with
  | refl => exact h1
  | tail _ hstep ih => exact ih.tail hstep

/-- The trichotomy.  On the fragment the `concrete` branch is unreachable, so these three
cases are exhaustive. -/
theorem step_trichotomy {s s' : State} (hnc : NoConc s) (h : step s = .continue s') :
    (IsLearnStep s ∧ s'.env = s.env) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length) := by
  have hi : ∀ p ∈ s.incm.elems, CF p := fun p hp => hnc.incm hp
  simp only [step, State.log] at h
  cases hd : s.incm.dequeue with
  | none => rw [hd] at h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at h
    dsimp only at h
    have hrC : CF r := hi r (PQueue.dequeue_mem hd).1
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
          exact Or.inr (Or.inr ⟨h3.symm, h2.symm, by rw [← h1]; exact hlen⟩)
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
        · exfalso
          rename_i hab
          exact hne (by simp [RHS.isEmpty, hab, isEmpty_of_nil hrC])
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
                exact Or.inr (Or.inr ⟨h3.symm, h2.symm, by rw [← h1]; exact hlen⟩)
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
                hsingle⟩, rfl⟩

/-! ### The measure -/

/-- The lexicographic measure, flattened: the environment's room to grow weighs most, then
the processed set's, then the incoming queue's own length. -/
def measure3 (P Q E : Nat) (s : State) : Nat :=
  (E - s.env.binds.length) * ((P + 1) * (Q + 1)) +
    (P - (procSys s).card) * (Q + 1) + s.incm.elems.length

theorem measure3_arith {P Q E ae be ce ae' be' ce' : Nat}
    (hbe' : be' ≤ P) (hce' : ce' ≤ Q) (hae' : ae' ≤ E)
    (hcase : (ae' = ae ∧ be < be') ∨ (ae' = ae + 1) ∨ (ae' = ae ∧ be' = be ∧ ce' + 1 = ce)) :
    (E - ae') * ((P + 1) * (Q + 1)) + (P - be') * (Q + 1) + ce'
      < (E - ae) * ((P + 1) * (Q + 1)) + (P - be) * (Q + 1) + ce := by
  have hK : (P + 1) * (Q + 1) = P * (Q + 1) + (Q + 1) := Nat.succ_mul P (Q + 1)
  have hPM : (P - be') * (Q + 1) ≤ P * (Q + 1) :=
    Nat.mul_le_mul_right _ (Nat.sub_le _ _)
  rcases hcase with ⟨rfl, hlt⟩ | hae | ⟨rfl, hb, hc⟩
  · have h1 : (P - be') * (Q + 1) ≤ (P - be - 1) * (Q + 1) :=
      Nat.mul_le_mul_right _ (by omega)
    have h2 : (P - be - 1) * (Q + 1) + (Q + 1) = (P - be) * (Q + 1) := by
      rw [← Nat.succ_mul]
      congr 1
      omega
    omega
  · subst hae
    have h3 : (E - (ae + 1)) * ((P + 1) * (Q + 1)) + ((P + 1) * (Q + 1))
        = (E - ae) * ((P + 1) * (Q + 1)) := by
      rw [← Nat.succ_mul]
      congr 1
      omega
    omega
  · subst hb
    omega

/-- **The measure strictly decreases at every step of the fragment**, given the three
bounds. -/
theorem measure3_lt {P Q E : Nat} {s s' : State} (hw : Wf s) (hnc : NoConc s)
    (hP' : (procSys s').card ≤ P) (hQ' : s'.incm.elems.length ≤ Q)
    (hE' : s'.env.binds.length ≤ E) (h : step s = .continue s') :
    measure3 P Q E s' < measure3 P Q E s := by
  simp only [measure3]
  refine measure3_arith hP' hQ' hE' ?_
  rcases step_trichotomy hnc h with ⟨⟨r, rest, hd, h1, h2, h3, h4⟩, henv⟩ | henv | ⟨he, hp, hc⟩
  · exact Or.inl ⟨by rw [henv], learn_procSys_lt hw hd h1 h2 h3 h4 h⟩
  · exact Or.inr (Or.inl henv)
  · exact Or.inr (Or.inr ⟨by rw [he], by rw [procSys, procSys, hp], hc⟩)

/-- **Termination, reduced to three bounds.**  If, at every state the run reaches, the
environment, the processed set and the incoming queue stay below fixed bounds, the loop
terminates -- with the explicit fuel `measure3 P Q E s + 1`.

This is the exact residual of R6.2: `trim` and the single pass make the processed set grow at
every `learn` step, and the other two branches are paid for by the environment and by the
queue; what is missing is only that the three quantities are BOUNDED, and each of the three
is bounded by the vocabulary. -/
theorem terminates_of_bounds_aux {P Q E : Nat} : ∀ (n : Nat) (s : State),
    measure3 P Q E s ≤ n →
    (∀ t, Reaches s t → Wf t) → (∀ t, Reaches s t → NoConc t) →
    (∀ t, Reaches s t → (procSys t).card ≤ P) →
    (∀ t, Reaches s t → t.incm.elems.length ≤ Q) →
    (∀ t, Reaches s t → t.env.binds.length ≤ E) →
    Finished (run s (n + 1))
  | 0, s, hm, hw, hnc, hp, hq, he => by
    simp only [run]
    cases hst : step s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      exfalso
      have := measure3_lt (hw s (Reaches.refl s)) (hnc s (Reaches.refl s))
        (hp s' ((Reaches.refl s).tail hst)) (hq s' ((Reaches.refl s).tail hst))
        (he s' ((Reaches.refl s).tail hst)) hst
      omega
  | n + 1, s, hm, hw, hnc, hp, hq, he => by
    simp only [run]
    cases hst : step s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      have hlt := measure3_lt (hw s (Reaches.refl s)) (hnc s (Reaches.refl s))
        (hp s' ((Reaches.refl s).tail hst)) (hq s' ((Reaches.refl s).tail hst))
        (he s' ((Reaches.refl s).tail hst)) hst
      refine terminates_of_bounds_aux n s' (by omega)
        (fun t ht => hw t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hnc t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hp t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => hq t (reaches_trans ((Reaches.refl s).tail hst) ht))
        (fun t ht => he t (reaches_trans ((Reaches.refl s).tail hst) ht))

theorem terminates_of_bounds {P Q E : Nat} {s : State}
    (hw : ∀ t, Reaches s t → Wf t) (hnc : ∀ t, Reaches s t → NoConc t)
    (hp : ∀ t, Reaches s t → (procSys t).card ≤ P)
    (hq : ∀ t, Reaches s t → t.incm.elems.length ≤ Q)
    (he : ∀ t, Reaches s t → t.env.binds.length ≤ E) : Terminates s :=
  ⟨measure3 P Q E s + 1,
    terminates_of_bounds_aux (measure3 P Q E s) s (le_refl _) hw hnc hp hq he⟩


/-! ## 8. R6.2: termination recast as "`incm` empties", and the saturation residual

The round-5 review's V-13 R6.2 asks for termination to be restated as a statement about
`trim` rather than about a measure: `proc` is monotone except at the three deleting branches,
each `learn` dequeue moves one partition from `incm` to `proc`, and `trim` refuses anything
`proc` already holds -- so **termination is saturation of the derived set**.  §8 states that
and finds the gap. -/

/-- A state the loop cannot step from. -/
def Stuck (t : State) : Prop := ∀ t', step t ≠ .continue t'

theorem stuck_iff {t : State} :
    Stuck t ↔ ((∃ u, step t = .done u) ∨ (∃ m u, step t = .died m u)) := by
  constructor
  · intro h
    cases hst : step t with
    | done u => exact Or.inl ⟨u, rfl⟩
    | died m u => exact Or.inr ⟨m, u, rfl⟩
    | «continue» u => exact absurd hst (h u)
  · rintro (⟨u, hu⟩ | ⟨m, u, hu⟩) <;> intro t' hc <;> rw [hc] at hu <;> simp at hu

/-- **`done` IS the empty incoming queue.**  `step`'s only `done` is its first branch. -/
theorem step_done_dequeue {t u : State} (h : step t = .done u) : t.incm.dequeue = none := by
  simp only [step, State.log] at h
  split at h
  · assumption
  · exfalso
    repeat' split at h
    all_goals exact absurd h (by simp)

theorem stuck_of_dequeue_none {t : State} (h : t.incm.dequeue = none) : Stuck t := by
  refine stuck_iff.mpr (Or.inl ⟨t, ?_⟩)
  simp only [step]
  rw [h]

/-- **Termination is reaching a stuck state.** -/
theorem terminates_iff_stuck {s : State} :
    Terminates s ↔ ∃ (n : Nat) (t : State), Runs n s t ∧ Stuck t := by
  constructor
  · rintro ⟨n, hn⟩
    have key : ∀ (k : Nat) (s0 : State), Finished (run s0 k) →
        ∃ (m : Nat) (t : State), Runs m s0 t ∧ Stuck t := by
      intro k
      induction k with
      | zero => intro s0 h; simp only [run, Finished] at h
      | succ j ih =>
        intro s0 h
        simp only [run] at h
        cases hst : step s0 with
        | done u =>
          exact ⟨0, s0, rfl, fun t' hc => by rw [hc] at hst; simp at hst⟩
        | died m u =>
          exact ⟨0, s0, rfl, fun t' hc => by rw [hc] at hst; simp at hst⟩
        | «continue» u =>
          rw [hst] at h
          obtain ⟨m, t, hr, hs⟩ := ih u h
          exact ⟨m + 1, t, ⟨u, hst, hr⟩, hs⟩
    exact key n s hn
  · rintro ⟨n, t, hr, hs⟩
    refine ⟨n + 1, ?_⟩
    rw [hr.run_eq n 1]
    simp only [run]
    cases hst : step t with
    | done u => trivial
    | died m u => trivial
    | «continue» u => exact absurd hst (hs u)

/-- **"`incm` empties" is the recast R6.2 asks for.**  On a run that does not DIE -- which is
what round 3's `run_refutes_all` gives on a satisfiable input, every death of the loop being a
refutation of the system it was handed -- `Terminates` is exactly "the incoming queue
empties". -/
theorem terminates_iff_incm_empties {s : State}
    (hnd : ∀ (n : Nat) (t : State), Runs n s t → ∀ m u, step t ≠ .died m u) :
    Terminates s ↔ ∃ (n : Nat) (t : State), Runs n s t ∧ t.incm.dequeue = none := by
  rw [terminates_iff_stuck]
  constructor
  · rintro ⟨n, t, hr, hs⟩
    rcases stuck_iff.mp hs with ⟨u, hu⟩ | ⟨m, u, hu⟩
    · exact ⟨n, t, hr, step_done_dequeue hu⟩
    · exact absurd hu (hnd n t hr m u)
  · rintro ⟨n, t, hr, hq⟩
    exact ⟨n, t, hr, stuck_of_dequeue_none hq⟩

/-! ### The two halves of saturation -/

/-- **Half one, PROVED (round 3, `Order.trim_refuses`, restated here as the membership
form).**  `trim` refuses everything the processed queue already holds, so nothing a `learn`
step enqueues is a partition `proc` has seen. -/
theorem trim_notContains (ps : SSet LPart) (cs : PQueue) :
    ∀ x ∈ (trim ps cs).elems, cs.contains x = false := by
  intro x hx
  simpa using (SSet.mem_filter_iff.mp hx).2

/-- **Half two, the one that is missing: GUARD COMPLETENESS.**  Once the loop has minted at a
key, the reuse guards refuse every later mint at that key. -/
def GuardComplete : Prop :=
  ∀ (s s' t t' : State) (v : Nat) (K : SSet Lbl),
    step s = .continue s' → MintsAt s s' v K → Reaches s' t → step t = .continue t' →
    ¬ MintsAt t t' v K

/-- **AND IT IS FALSE**, on round 5's own six-constraint satisfiable witness, which the
compiler solves: the loop mints at `(v2, pKey)` at step 5 and again at step 12, because
`cancellation` + `makeEmpty` withdrew the carrier the first mint installed and the guard
`findResolvent` therefore has nothing to find.  Round 5's `cS0` refutes it a second time with
`makeConcrete` in place of `makeEmpty`, and the round-5 reviewer's `climb/L4/best11.json`
refutes it TEN times over at one key. -/
theorem guardComplete_false : ¬ GuardComplete := fun h =>
  h (pAt 5) (pAt 6) (pAt 12) (pAt 13) 2 pKey pStep5 pMint5 pReach6_12 pStep12 pMint12

/-- The positive residual that survives the refutation, and the one `terminates_of_bounds`
consumes: the derived set is bounded along the run. -/
def ProcSaturates (s : State) : Prop := ∃ P : Nat, ∀ t, Reaches s t → (procSys t).card ≤ P

/-- **The residual, assembled.**  On the fragment, saturation of the derived set together with
the two bounds it does not itself give -- on the queue and on the environment -- IS
termination.  Each of the three is a bound by the vocabulary (R6.3.3). -/
theorem terminates_of_saturation {s : State} {Q E : Nat}
    (hw : ∀ t, Reaches s t → Wf t) (hnc : ∀ t, Reaches s t → NoConc t)
    (hsat : ProcSaturates s)
    (hq : ∀ t, Reaches s t → t.incm.elems.length ≤ Q)
    (he : ∀ t, Reaches s t → t.env.binds.length ≤ E) : Terminates s := by
  obtain ⟨P, hP⟩ := hsat
  exact terminates_of_bounds (P := P) (Q := Q) (E := E) hw hnc hP hq he


/-! ## 9. The VOCABULARY on the fragment

§7's three bounds all need one thing: a fixed `V` with every variable of every reachable state
inside it.  This is what round 5 left open in general, and on the fragment it closes, because
no id is ever drawn (§6) and no rule invents a name.  `Loop/Hygiene.lean`'s `Avoids B` machinery is parametric in `B`, and with
`B := (· ∉ V)` the statement "every variable of `p` is in `V`" is `Avoids B p.toConstraint`
(`avoids_toConstraint_iff`).  Every rule lemma there is usable at that `B` EXCEPT
`commonSubexpression_avoids`, which carries a `SupAvoids B su` hypothesis -- true of "the
variables the environment has bound", false of "the variables of `V`" -- and needs it only for
the minting branch that `genRules=cut` closes.  §9 supplies the cut variant and then the fold
and the step. -/

/-- `commonSubexpression` under `genRules=cut`: the minting branch is dead, so no hypothesis
about the supply is needed and the conclusion holds at ANY `B`. -/
theorem commonSubexpression_avoids_cut {B : Var → Prop} {fl : Flags} {v : Nat} {rhs1 : RHS}
    {u : Nat} {rhs2 : RHS} {rhss : RHS → Option Nat} {su : Sup}
    (hcse : fl.cseMints = false) (hv : ¬ B v) (hu : ¬ B u)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ B w)
    (hr : ∀ r w, rhss r = some w → ¬ B w) :
    ∀ x ∈ (commonSubexpression fl v rhs1 u rhs2 rhss su).1.elems, Avoids B x.toConstraint := by
  have hincl : ∀ (a : SSet Nat) (t : SSet Nat) (z : Nat), (∀ w ∈ a.elems, ¬ B w) → ¬ B z →
      ∀ w ∈ ((a.removedAll t).incl z).elems, ¬ B w := by
    intro a t z ha hz w hw
    rcases SSet.mem_incl hw with hw' | rfl
    · exact ha w (SSet.mem_removedAll hw')
    · exact hz
  simp only [commonSubexpression]
  split
  · exact fun x hx => absurd hx (by simp [SSet.empty])
  · split
    · rename_i z hz
      have hzB : ¬ B z := hr _ _ hz
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
          · rename_i hbad
            exact absurd hcse (by simp at hbad; simp [hbad])


/-- **The vocabulary clause for the `learn` branch, on the fragment.**  Every partition
`learnPartitions` derives mentions only variables the premises already mention.  This is the
clause `Loop/Supply.lean`'s `learnPartitions_new` could not give: its conclusion is
`Avoids (New Old su')`, i.e. "old OR unreachable", and the second disjunct is what a
vocabulary bound cannot afford.  On the fragment it can be dropped, because neither generative
rule fires. -/
theorem learnPartitions_avoidsV {B : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hc1 : rhs1.conc.elems = []) (hsg : rhs1.abstrSingle? = none)
    (hv : ¬ B v) (hr1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  have hlk : LkAvoids B (mkLookups v incm proc) := mkLookups_avoids hi hp
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, hS0, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    exact selfSubstitution_avoids hr1 hS0
  · refine foldl_except_inv
      (P := fun (a : SSet LPart × Sup) => ∀ x ∈ a.1.elems, Avoids B x.toConstraint)
      (Q := fun (x : LPart) => Avoids B x.toConstraint) ?_ _ hp _ ?_ _ h
    · intro acc p2 hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        have haA := hacc _ hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        have hp2A := avoids_toConstraint_iff.mp hp2
        split at hb
        · -- resolution / cancellation
          rw [resolution_noConc (fl := fl) (v := v) (rhs2 := p2.rhs)
            (resolvent := fun k => findResolvent v (mkLookups v incm proc) aS k)
            (concRow := fun k => if fl.splitRow || fl.resRow then
              findConcRow (mkLookups v incm proc) k else none)
            (emptyRow := fun k => if fl.emptyRow then
              findEmptyRow env (mkLookups v incm proc) k else none) (su := asu) hsg] at hb
          simp only [hdj, Bool.not_false, if_true, pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          intro x hx
          rcases SSet.mem_concat hx with hx' | hx'
          · rcases SSet.mem_concat hx' with hx'' | hx''
            · rcases SSet.mem_concat hx'' with hx3 | hx3
              · exact haA x hx3
              · exact absurd hx3 (by simp [SSet.empty])
            · exact cancellation_avoids (B := B) (v := v) hr1 hp2A.2 x hx''
          · exact absurd hx' (by simp [SSet.empty])
        · -- commonSubexpression / substitution
          have hcs : (commonSubexpression fl v rhs1 p2.lhs p2.rhs
              (fun r => findRHS3 incm proc aS r) asu).2 = asu :=
            commonSubexpression_su_of_cut hcse
          have hcc := commonSubexpression_avoids_cut (B := B) (fl := fl) (v := v) (rhs1 := rhs1)
            (u := p2.lhs) (rhs2 := p2.rhs) (rhss := fun r => findRHS3 incm proc aS r)
            (su := asu) hcse hv hp2A.1 hr1 hp2A.2
            (fun r w hw => findRHS3_avoids hi hp haA hw)
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m => rw [hsub] at hb; simp only [] at hb; exact absurd hb (by simp)
          | ok sps =>
            rw [hsub] at hb
            simp only [hdj, Bool.not_false, if_true, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            intro x hx
            rcases SSet.mem_concat hx with hx' | hx'
            · rcases SSet.mem_concat hx' with hx'' | hx''
              · rcases SSet.mem_concat hx'' with hx3 | hx3
                · exact haA x hx3
                · exact hcc x hx3
              · exact substitution_avoids (B := B) hv hp2A.1 hr1 hp2A.2 hsub x hx''
            · exact absurd hx' (by simp [SSet.empty])
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      rw [splitConcrete_noConc (fl := fl) (v := v) (abstr := rhs1.abstr)
        (rhss := fun r => findRHS3 incm proc SSet.empty r)
        (resolvent := fun k => findResolvent v (mkLookups v incm proc) SSet.empty k)
        (concRow := fun k => if fl.splitRow || fl.resRow then
          findConcRow (mkLookups v incm proc) k else none)
        (emptyRow := fun k => if fl.emptyRow then
          findEmptyRow env (mkLookups v incm proc) k else none) (su := su) hc1]
      exact fun x hx => absurd hx (by simp [SSet.empty])


/-! ### 9.2 The step, and the run -/

/-- **Every variable of the state is in `V`** -- in either queue and in the environment. -/
def InVoc (V : Finset Var) (s : State) : Prop :=
  (∀ p ∈ s.parts, Avoids (fun w => w ∉ V) p.toConstraint) ∧
    (∀ b ∈ s.env.binds, Avoids (fun w => w ∉ V) (EnvVal.toConstraint b.1 b.2))

/-- **The vocabulary does not grow, on the fragment.**  No id is drawn (`step_noConc`), no
generative rule fires, and every rule builds its conclusion out of names the premises already
carry -- so `V` is fixed. -/
theorem step_inVoc {V : Finset Var} {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hnc : NoConc s) (h0 : InVoc V s)
    (h : step s = .continue s') : InVoc V s' := by
  obtain ⟨h0p, h0e⟩ := h0
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
    fun x hx => h0p x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
    fun x hx => h0p x (List.mem_append_right _ hx)
  have hci : ∀ p ∈ s.incm.elems, CF p := fun p hp => hnc.incm hp
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (PQueue.dequeue_mem hdq).1
    have hrest : ∀ x ∈ rest.elems, Avoids (fun w => w ∉ V) x.toConstraint :=
      fun x hx => hi0 x ((PQueue.dequeue_mem hdq).2 x hx)
    have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
    have hrC : CF r := hci r hrMem
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
        · -- concrete: unreachable
          exfalso
          rename_i hne hab
          exact hne (by simp [RHS.isEmpty, hab, isEmpty_of_nil hrC])
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
            rename_i hsingle
            rename_i hab
            rename_i hne
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
              have hlearn := learnPartitions_avoidsV (B := fun w => w ∉ V) hdj hcse hrC
                (by rw [← single_eq_abstrSingle hrC]; exact hsingle) hrA.1 hrA.2 hrest hp0 hlp
              refine ⟨fun x hx => ?_, h0e⟩
              rcases List.mem_append.mp hx with hx' | hx'
              · exact concatP_avoids _ hrest
                  (fun d hd => hlearn d (SSet.mem_filter hd)) x hx'
              · exact insertNP_avoids hp0 (hi0 r hrMem) hx'


/-! ### 9.3 The invariants along a run, and two of the three bounds -/

theorem reaches_wf {s t : State} (hw : Wf s) (hr : Reaches s t) : Wf t := by
  induction hr with
  | refl => exact hw
  | tail _ hstep ih => exact step_wf ih hstep

theorem reaches_envNodup {s t : State} (hn : EnvNodup s) (hr : Reaches s t) : EnvNodup t := by
  induction hr with
  | refl => exact hn
  | tail _ hstep ih => exact step_envNodup ih hstep

/-- **The fragment's invariants, along the whole run.** -/
theorem reaches_noConc_inVoc {V : Finset Var} {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hnc : NoConc s) (h0 : InVoc V s) (hr : Reaches s t) :
    NoConc t ∧ InVoc V t ∧ t.flags = s.flags := by
  induction hr with
  | refl => exact ⟨hnc, h0, rfl⟩
  | @tail t0 u0 _ hstep ih =>
    obtain ⟨h1, h2, h3⟩ := ih
    have hdj' : t0.flags.disjRule = false := by rw [h3]; exact hdj
    have hcse' : t0.flags.cseMints = false := by rw [h3]; exact hcse
    obtain ⟨h1', -, h3'⟩ := step_noConc hdj' hcse' h1 hstep
    exact ⟨h1', step_inVoc hdj' hcse' h1 h2 hstep, by rw [h3', h3]⟩

/-- **Bound one: the environment.**  Every binding names a variable of `V`, and no variable is
bound twice (`StrictBound.step_envNodup`, because `instantiateType` panics on a rebinding). -/
theorem env_len_le_card {V : Finset Var} {s : State} (h : InVoc V s) (hnd : EnvNodup s) :
    s.env.binds.length ≤ V.card := by
  have hsub : (s.env.binds.map Prod.fst).toFinset ⊆ V := by
    intro x hx
    obtain ⟨b, hb, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hx)
    have hlhs : (EnvVal.toConstraint b.1 b.2).lhs = b.1 := by
      obtain ⟨w, val⟩ := b; cases val <;> rfl
    have := (h.2 b hb).1
    rw [hlhs] at this
    exact not_not.mp this
  calc s.env.binds.length = (s.env.binds.map Prod.fst).length := by simp
    _ = (s.env.binds.map Prod.fst).toFinset.card := (List.toFinset_card_of_nodup hnd).symm
    _ ≤ V.card := Finset.card_le_card hsub

/-- **Bound two: the processed set.**  Every processed partition is a `mk`-shaped constraint
over `V` with an empty concrete part, so it is one of `DefaultTerm.forms V ∅`. -/
theorem procSys_subset_forms {V : Finset Var} {s : State} (h : InVoc V s) (hnc : NoConc s) :
    procSys s ⊆ forms V (∅ : Finset Label) := by
  intro c hc
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hc)
  have hpA := avoids_toConstraint_iff.mp (h.1 p (List.mem_append_right _ hp))
  have hpC : p.rhs.conc.elems = [] := hnc.proc hp
  rw [mem_forms]
  refine ⟨?_, ?_, ?_, ?_⟩
  · exact isCanonical_mk _ _ _
  · simpa [LPart.toConstraint] using not_not.mp hpA.1
  · intro w hw
    simp only [LPart.toConstraint, vset_mk, List.mem_toFinset] at hw
    exact not_not.mp (hpA.2 w hw)
  · simp [LPart.toConstraint, hpC]

theorem procSys_card_le {V : Finset Var} {s : State} (h : InVoc V s) (hnc : NoConc s) :
    (procSys s).card ≤ V.card * 2 ^ V.card := by
  have h1 : (procSys s).card ≤ (forms V (∅ : Finset Label)).card :=
    Finset.card_le_card (procSys_subset_forms h hnc)
  have h2 := card_forms_le V (∅ : Finset Label)
  simpa using le_trans h1 h2


/-! ## 10. The third bound, and `Terminates`

The queue's own de-duplication is what bounds its length.  `Q.insert` (`PQueue.insertNP` and
`PQueue.insertP`) refuses a partition that is already in the queue AT THE SAME SEARCH KEY, and
the test it makes is one-directional (`x.eqv p` for the elements `x` already present), so what
an insertion establishes for a PAIR is that at least one of the two directions fails -- which
is symmetric, and therefore a `List.Pairwise` invariant (`KDist`).

Turning that into a length bound needs one fact nothing in the development had: that
`Partition.equals` implies equality of the SEARCH KEY, i.e. that `RHS.hashCode` does not depend
on a set's iteration order.  It does not, and the reason is arithmetic:
`MurmurHash3.unorderedHash` folds a sum, an exclusive-or and a product, all commutative and
associative on a Java `int`, so it is invariant under permutation (`unorderedHash_perm`), and
two `equals`-equal `Set`s of a well-formed state are permutations of each other.  With that,
`(lhs, the SET of abstract parts)` separates the queue's elements on the fragment, and the
queue is no longer than `|V| · 2^|V|`. -/


theorem uh_fold_perm {l1 l2 : List I32} (h : l1.Perm l2) (z : I32 × I32 × I32 × Nat) :
    l1.foldl (fun acc hh => (acc.1 + hh, acc.2.1 ^^^ hh, acc.2.2.1 * (hh ||| 1), acc.2.2.2 + 1)) z
      = l2.foldl (fun acc hh =>
          (acc.1 + hh, acc.2.1 ^^^ hh, acc.2.2.1 * (hh ||| 1), acc.2.2.2 + 1)) z := by
  refine h.foldl_eq' ?_ z
  rintro x - y - ⟨a, b, c, n⟩
  simp only [Prod.mk.injEq]
  refine ⟨?_, ?_, ?_⟩
  · rw [UInt32.add_assoc, UInt32.add_comm x y, ← UInt32.add_assoc]
  · rw [UInt32.xor_assoc, UInt32.xor_comm x y, ← UInt32.xor_assoc]
  · exact ⟨by rw [UInt32.mul_assoc, UInt32.mul_comm (x ||| 1) (y ||| 1), ← UInt32.mul_assoc],
      trivial⟩

theorem unorderedHash_perm {l1 l2 : List I32} (h : l1.Perm l2) (seed : I32) :
    Murmur.unorderedHash l1 seed = Murmur.unorderedHash l2 seed := by
  simp only [Murmur.unorderedHash]
  rw [uh_fold_perm h]

theorem sset_hsh_of_eqv {α : Type} [SVal α] [LawfulSVal α] [DecidableEq α] {s t : SSet α}
    (hs : s.Nodup) (ht : t.Nodup) (h : s.eqv t = true) : s.hsh = t.hsh := by
  have hperm : s.elems.Perm t.elems :=
    List.perm_of_nodup_nodup_toFinset_eq hs ht ((SSet.eqv_iff_toFinset hs ht).mp h)
  simp only [SSet.hsh, Murmur.setHash]
  exact unorderedHash_perm (hperm.map _) _

theorem rhs_hshOf_of_eqv {r t : RHS} (hra : r.abstr.Nodup) (hrc : r.conc.Nodup)
    (hta : t.abstr.Nodup) (htc : t.conc.Nodup) (h : r.eqv t = true) : r.hshOf = t.hshOf := by
  unfold RHS.eqv at h
  rw [Bool.and_eq_true] at h
  simp only [RHS.hshOf, sset_hsh_of_eqv hra hta h.1, sset_hsh_of_eqv hrc htc h.2]

theorem keyEq_of_eqv {p q : LPart} (hpa : p.rhs.abstr.Nodup) (hpc : p.rhs.conc.Nodup)
    (hqa : q.rhs.abstr.Nodup) (hqc : q.rhs.conc.Nodup) (h : p.eqv q = true) :
    PQueue.keyEq (PQueue.keyOf p) (PQueue.keyOf q) = true := by
  unfold LPart.eqv at h
  rw [Bool.and_eq_true] at h
  simp only [PQueue.keyEq, PQueue.keyOf, rhs_hshOf_of_eqv hpa hpc hqa hqc h.2]
  simp only [beq_self_eq_true, Bool.true_and]
  have : p.lhs = q.lhs := by simpa using h.1
  simp [this]

/-- The queue's own de-duplication test, symmetrised. -/
def KRel (a b : LPart) : Prop :=
  (PQueue.keyEq (PQueue.keyOf a) (PQueue.keyOf b) && a.eqv b) = false ∨
    (PQueue.keyEq (PQueue.keyOf b) (PQueue.keyOf a) && b.eqv a) = false

def KDist (l : List LPart) : Prop := l.Pairwise KRel

theorem krel_symm {a b : LPart} (h : KRel a b) : KRel b a := h.symm

theorem insertSorted_perm (p : LPart) :
    ∀ l : List LPart, (PQueue.insertSorted p l).Perm (p :: l)
  | [] => List.Perm.refl _
  | x :: t => by
    simp only [PQueue.insertSorted]
    split
    · exact ((insertSorted_perm p t).cons x).trans (List.Perm.swap p x t)
    · exact List.Perm.refl _

theorem kdist_insertSorted {p : LPart} {l : List LPart} (h : KDist l)
    (hp : ∀ x ∈ l, KRel p x) : KDist (PQueue.insertSorted p l) :=
  ((insertSorted_perm p l).pairwise_iff (fun {_ _} => krel_symm)).mpr
    (List.pairwise_cons.mpr ⟨hp, h⟩)

theorem krel_of_any_false {q : PQueue} {p : LPart}
    (hno : q.elems.any (fun x => PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) && x.eqv p)
      = false) : ∀ x ∈ q.elems, KRel p x := by
  have hno' : ∀ x ∈ q.elems, PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) = true →
      x.eqv p = false := by simpa using hno
  intro x hx
  refine Or.inr ?_
  cases hk : PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) with
  | false => simp
  | true => simp [hno' x hx hk]

theorem kdist_insertNP {q : PQueue} {p : LPart} (h : KDist q.elems) :
    KDist (q.insertNP p).elems := by
  unfold PQueue.insertNP
  split
  · exact h
  · split
    · exact h
    · rename_i hno
      exact kdist_insertSorted h (krel_of_any_false (by simpa using hno))

theorem kdist_insertP {q : PQueue} {p : LPart} (h : KDist q.elems) :
    KDist (q.insertP p).elems := by
  unfold PQueue.insertP
  split
  · exact h
  · split
    · exact h
    · rename_i hno
      have hk := krel_of_any_false (q := q) (p := p) (by simpa using hno)
      split
      · exact kdist_insertNP h
      · exact kdist_insertSorted h hk

theorem kdist_concatP : ∀ (ps : List LPart) {q : PQueue}, KDist q.elems →
    KDist (q.concatP ps).elems
  | [], q, h => by simpa [PQueue.concatP] using h
  | p :: t, q, h => by
    simp only [PQueue.concatP, List.foldl_cons]
    have := kdist_concatP t (q := q.insertP p) (kdist_insertP h)
    simpa [PQueue.concatP] using this

theorem kdist_concatNP : ∀ (ps : List LPart) {q : PQueue}, KDist q.elems →
    KDist (q.concatNP ps).elems
  | [], q, h => by simpa [PQueue.concatNP] using h
  | p :: t, q, h => by
    simp only [PQueue.concatNP, List.foldl_cons]
    have := kdist_concatNP t (q := q.insertNP p) (kdist_insertNP h)
    simpa [PQueue.concatNP] using this

theorem kdist_ofList (ps : List LPart) : KDist (PQueue.ofList ps).elems :=
  kdist_concatNP ps (by simp [PQueue.empty, KDist])

theorem kdist_filter {q : PQueue} {f : LPart → Bool} (h : KDist q.elems) :
    KDist (q.filter f).elems := List.Pairwise.filter _ h

theorem kdist_partition_snd {q : PQueue} {f : LPart → Bool} (h : KDist q.elems) :
    KDist (q.partition f).2.elems := List.Pairwise.filter _ h

theorem kdist_sublist {l1 l2 : List LPart} (hs : l1.Sublist l2) (h : KDist l2) : KDist l1 :=
  h.sublist hs

theorem kdist_dequeue {q : PQueue} {r : LPart} {rest : PQueue}
    (hd : q.dequeue = some (r, rest)) (h : KDist q.elems) : KDist rest.elems := by
  simp only [PQueue.dequeue] at hd
  split at hd
  · exact absurd hd (by simp)
  · rename_i e0 tl he
    split at hd
    · exact absurd hd (by simp)
    · rename_i i hi
      split at hd
      · exact absurd hd (by simp)
      · rename_i z hg
        simp only [Option.some.injEq, Prod.mk.injEq] at hd
        obtain ⟨-, hr⟩ := hd
        rw [← hr]
        exact kdist_sublist (by rw [he]; exact List.eraseIdx_sublist _ _) h

theorem kdist_foldl_concatP (v u : Nat) : ∀ (l : List LPart) (q : PQueue), KDist q.elems →
    KDist (l.foldl (fun nq p => nq.concatP (replace v u p).elems) q).elems
  | [], q, h => h
  | p :: t, q, h => by
    simp only [List.foldl_cons]
    exact kdist_foldl_concatP v u t _ (kdist_concatP _ h)

theorem kdist_instantiate {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : KDist incm.elems) (hp : KDist proc.elems)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    KDist ni.elems ∧ KDist np.elems := by
  rw [instantiate_eq] at h
  split at h
  · exact absurd h (by simp)
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨hni, hnp, -⟩ := h
    exact ⟨hni ▸ kdist_foldl_concatP v u _ _ (kdist_partition_snd hi),
      hnp ▸ kdist_partition_snd hp⟩

theorem kdist_unifyVars {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : KDist incm.elems) (hp : KDist proc.elems)
    (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) :
    KDist ni.elems ∧ KDist np.elems := by
  unfold unifyVars at h
  split at h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨h1, h2, -⟩ := h
    exact ⟨h1 ▸ hi, h2 ▸ hp⟩
  · exact kdist_instantiate hi hp h

theorem kdist_makeEmpty {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : KDist incm.elems) (hp : KDist proc.elems)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    KDist ni.elems ∧ KDist np.elems := by
  simp only [makeEmpty] at h
  obtain ⟨nps, -, h2⟩ := except_bind_ok h
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨rfl, rfl, -⟩ := h2
      exact ⟨kdist_concatP _ (kdist_partition_snd hi), kdist_partition_snd hp⟩

theorem step_kdist {s s' : State} (hnc : NoConc s) (hi : KDist s.incm.elems)
    (hp : KDist s.proc.elems) (h : step s = .continue s') :
    KDist s'.incm.elems ∧ KDist s'.proc.elems := by
  have hci : ∀ p ∈ s.incm.elems, CF p := fun p hp0 => hnc.incm hp0
  simp only [step, State.log] at h
  cases hd : s.incm.dequeue with
  | none => rw [hd] at h; exact absurd h (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at h
    dsimp only at h
    have hrC : CF r := hci r (PQueue.dequeue_mem hd).1
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
        · exfalso
          rename_i hne hab
          exact hne (by simp [RHS.isEmpty, hab, isEmpty_of_nil hrC])
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

/-- The separating map: on the fragment a partition is determined, up to `Partition.equals`,
by its left-hand side and the SET of its abstract parts. -/
def sepMap (p : LPart) : Nat × Finset Nat := (p.lhs, p.rhs.abstr.elems.toFinset)

theorem kdist_length_le {V : Finset Var} {s : State} {l : List LPart}
    (hw : Wf s) (hnc : NoConc s) (hv : InVoc V s)
    (hsub : ∀ p ∈ l, p ∈ s.parts) (hk : KDist l) :
    l.length ≤ V.card * 2 ^ V.card := by
  have hnd : (l.map sepMap).Nodup := by
    rw [List.Nodup, List.pairwise_map]
    refine List.Pairwise.imp_of_mem ?_ hk
    intro a b ha hb hab heq
    simp only [sepMap, Prod.mk.injEq] at heq
    have hwa := hw.nodup (hsub a ha)
    have hwb := hw.nodup (hsub b hb)
    have hca : a.rhs.conc.elems = [] := hnc a (hsub a ha)
    have hcb : b.rhs.conc.elems = [] := hnc b (hsub b hb)
    have hconc : a.rhs.conc.eqv b.rhs.conc = true :=
      (SSet.eqv_iff_toFinset hwa.2 hwb.2).mpr (by rw [hca, hcb])
    have hconc' : b.rhs.conc.eqv a.rhs.conc = true :=
      (SSet.eqv_iff_toFinset hwb.2 hwa.2).mpr (by rw [hca, hcb])
    have habs : a.rhs.abstr.eqv b.rhs.abstr = true :=
      (SSet.eqv_iff_toFinset hwa.1 hwb.1).mpr heq.2
    have habs' : b.rhs.abstr.eqv a.rhs.abstr = true :=
      (SSet.eqv_iff_toFinset hwb.1 hwa.1).mpr heq.2.symm
    have hab1 : a.eqv b = true := by
      simp only [LPart.eqv, RHS.eqv, Bool.and_eq_true]
      exact ⟨by simp [heq.1], habs, hconc⟩
    have hab2 : b.eqv a = true := by
      simp only [LPart.eqv, RHS.eqv, Bool.and_eq_true]
      exact ⟨by simp [heq.1], habs', hconc'⟩
    rcases hab with hr | hr
    · rw [keyEq_of_eqv hwa.1 hwa.2 hwb.1 hwb.2 hab1, hab1] at hr; simp at hr
    · rw [keyEq_of_eqv hwb.1 hwb.2 hwa.1 hwa.2 hab2, hab2] at hr; simp at hr
  have hmem : ∀ x ∈ (l.map sepMap).toFinset, x ∈ V ×ˢ V.powerset := by
    intro x hx
    obtain ⟨p, hp, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hx)
    have hpA := avoids_toConstraint_iff.mp (hv.1 p (hsub p hp))
    refine Finset.mem_product.mpr ⟨not_not.mp hpA.1, ?_⟩
    refine Finset.mem_powerset.mpr ?_
    intro w hw
    exact not_not.mp (hpA.2 w (List.mem_toFinset.mp hw))
  calc l.length = (l.map sepMap).length := by simp
    _ = (l.map sepMap).toFinset.card := (List.toFinset_card_of_nodup hnd).symm
    _ ≤ (V ×ˢ V.powerset).card := Finset.card_le_card hmem
    _ = V.card * 2 ^ V.card := by simp

/-- Every state is `InVoc` at its OWN vocabulary, so the `V` of the bounds is not an
assumption: it is `allVars (sys s)` of the initial state. -/
theorem inVoc_self (s : State) : InVoc (allVars (sys s)) s := by
  refine ⟨fun p hp => ?_, fun b hb => ?_⟩
  · rw [avoids_toConstraint_iff]
    refine ⟨not_not.mpr (lhs_mem_allVars_sys hp), fun w hw => ?_⟩
    refine not_not.mpr (vset_subset_allVars_sys hp ?_)
    simpa [LPart.toConstraint] using hw
  · have hc : EnvVal.toConstraint b.1 b.2 ∈ sys s := mem_sys_of_env hb
    exact ⟨not_not.mpr (lhs_mem_allVars hc), fun w hw => not_not.mpr (vset_subset_allVars hc hw)⟩

theorem reaches_inv {V : Finset Var} {s t : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s) (hnc : NoConc s)
    (hv : InVoc V s) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hr : Reaches s t) :
    Wf t ∧ EnvNodup t ∧ NoConc t ∧ InVoc V t ∧ KDist t.incm.elems ∧ KDist t.proc.elems ∧
      t.flags = s.flags := by
  induction hr with
  | refl => exact ⟨hw, hnd, hnc, hv, hki, hkp, rfl⟩
  | @tail t0 u0 _ hstep ih =>
    obtain ⟨w1, w2, w3, w4, w5, w6, w7⟩ := ih
    have hdj' : t0.flags.disjRule = false := by rw [w7]; exact hdj
    have hcse' : t0.flags.cseMints = false := by rw [w7]; exact hcse
    obtain ⟨n1, -, n3⟩ := step_noConc hdj' hcse' w3 hstep
    obtain ⟨k1, k2⟩ := step_kdist w3 w5 w6 hstep
    exact ⟨step_wf w1 hstep, step_envNodup w2 hstep, n1,
      step_inVoc hdj' hcse' w3 w4 hstep, k1, k2, by rw [n3, w7]⟩

/-- **`Terminates` ON THE FRAGMENT, with an explicit bound.** -/
theorem noConc_terminates {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s) (hnc : NoConc s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) : Terminates s := by
  have hv : InVoc (allVars (sys s)) s := inVoc_self s
  have key := fun t (ht : Reaches s t) => reaches_inv hdj hcse hw hnd hnc hv hki hkp ht
  refine terminates_of_bounds (P := (allVars (sys s)).card * 2 ^ (allVars (sys s)).card)
    (Q := (allVars (sys s)).card * 2 ^ (allVars (sys s)).card)
    (E := (allVars (sys s)).card)
    (fun t ht => (key t ht).1) (fun t ht => (key t ht).2.2.1) ?_ ?_ ?_
  · intro t ht
    obtain ⟨-, -, hn, hvv, -, -, -⟩ := key t ht
    exact procSys_card_le hvv hn
  · intro t ht
    obtain ⟨hww, -, hn, hvv, hk, -, -⟩ := key t ht
    exact kdist_length_le hww hn hvv (fun p hp => List.mem_append_left _ hp) hk
  · intro t ht
    obtain ⟨-, hnn, -, hvv, -, -, -⟩ := key t ht
    exact env_len_le_card hvv hnn

/-- The same, as the explicit FUEL. -/
theorem noConc_run {s : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s) (hnc : NoConc s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    Finished (run s
      (measure3 ((allVars (sys s)).card * 2 ^ (allVars (sys s)).card)
        ((allVars (sys s)).card * 2 ^ (allVars (sys s)).card) (allVars (sys s)).card s + 1)) := by
  have hv : InVoc (allVars (sys s)) s := inVoc_self s
  have key := fun t (ht : Reaches s t) => reaches_inv hdj hcse hw hnd hnc hv hki hkp ht
  refine terminates_of_bounds_aux _ s (le_refl _)
    (fun t ht => (key t ht).1) (fun t ht => (key t ht).2.2.1) ?_ ?_ ?_
  · intro t ht
    obtain ⟨-, -, hn, hvv, -, -, -⟩ := key t ht
    exact procSys_card_le hvv hn
  · intro t ht
    obtain ⟨hww, -, hn, hvv, hk, -, -⟩ := key t ht
    exact kdist_length_le hww hn hvv (fun p hp => List.mem_append_left _ hp) hk
  · intro t ht
    obtain ⟨-, hnn, -, hvv, -, -, -⟩ := key t ht
    exact env_len_le_card hvv hnn

/-- **The corollary for a real solve.**  An INITIAL state -- `proc` and `env` empty and the
incoming queue built by `Json.buildQueue`, which is the shape both `Seed.solve` and
`Replay.replay` construct -- whose INPUT partitions carry no concrete label TERMINATES. -/
theorem noConc_terminates_of_input {ps : List LPart} {fl : Flags} {ns : Names} {site : String}
    {su : Sup} {tr : List String} {z : Nat}
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hconc : ∀ p ∈ (PQueue.ofList ps).elems, p.rhs.conc.elems = [])
    (hw : Wf { incm := PQueue.ofList ps, proc := PQueue.empty, env := {}, su := su,
               trace := tr, flags := fl, names := ns, site := site, su0 := z }) :
    Terminates { incm := PQueue.ofList ps, proc := PQueue.empty, env := {}, su := su,
                 trace := tr, flags := fl, names := ns, site := site, su0 := z } := by
  refine noConc_terminates hdj hcse hw (envNodup_initial fl ns site su tr z) ?_
    (kdist_ofList ps) (by simp [PQueue.empty, KDist])
  intro p hp
  rcases List.mem_append.mp hp with hp' | hp'
  · exact hconc p hp'
  · exact absurd hp' (by simp [PQueue.empty])


/-- `Json.buildQueue` builds the incoming queue with `PQueue.ofList`, which is what makes an
initial state's queue `KDist`. -/
theorem buildQueue_ofList {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    (h : buildQueue cs su = .ok (q, su')) : ∃ ps : List LPart, q = PQueue.ofList ps := by
  simp only [buildQueue] at h
  obtain ⟨w, -, h2⟩ := except_bind_ok h
  obtain ⟨ps, su2⟩ := w
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  exact ⟨ps, h2.1.symm⟩

/-- **The theorem a reviewer applies to a real solve.**  Both `Seed.solve` and
`Replay.replay` build `{ incm := q, proc := empty, env := {}, ... }` with
`buildQueue cs su = .ok (q, su')`; `Wf` of that state is `Wf.wf_initial` / `Wf.wf_seed` /
`Wf.wf_replay`.  If the built queue carries no concrete label -- which is what the corpus
measurement tests, and what all 373 row-carrying stdlib-boot solves satisfy -- the solve
TERMINATES. -/
theorem noConc_terminates_of_buildQueue {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hconc : ∀ p ∈ q.elems, p.rhs.conc.elems = [])
    (hw : Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := tr,
               flags := fl, names := ns, site := site, su0 := z }) :
    Terminates { incm := q, proc := PQueue.empty, env := {}, su := su', trace := tr,
                 flags := fl, names := ns, site := site, su0 := z } := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  exact noConc_terminates_of_input hdj hcse hconc hw


/-! ## 11. The fragment is inhabited, and it is inside the satisfiable class -/

/-- **The fragment is inhabited by a state that runs.**  Three label-free constraints over
five variables, at id base 5. -/
def nSeed : Seed :=
  { name := "noconc",
    cons := [⟨0, [1, 2], []⟩, ⟨0, [3, 4], []⟩, ⟨3, [1], []⟩],
    rhoKeys := [0, 1, 2, 3, 4] }

def nNs : Names := (seedSystem nSeed 5).2

def nS0 : State :=
  match buildQueue (seedSystem nSeed 5).1 (Sup.ofSeed nNs.supplyLo) with
  | .error _ =>
    { incm := PQueue.empty, proc := PQueue.empty, env := {}, su := Sup.ofSeed 0,
      trace := [], flags := {}, names := nNs, site := "noconc", su0 := 0 }
  | .ok (q, su1) =>
    { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := {},
      names := nNs, site := "noconc", su0 := (Sup.ofSeed nNs.supplyLo).lo }

theorem nS0_size : nS0.incm.elems.length = 3 := rfl

theorem nS0_noConc : NoConc nS0 := by
  intro p hp
  revert p
  exact (by decide : ∀ p ∈ nS0.parts, p.rhs.conc.elems = [])

theorem nS0_solved : Finished (run nS0 40) := trivial

theorem nS0_nodraw :
    (match run nS0 40 with | .solved s => s.su.drawn | _ => 99) = 0 := rfl


/-- **The fragment is entirely inside the SATISFIABLE class**, so the plan's acceptance
criterion ("for every satisfiable `Wf s₀`") costs nothing here: a system with no concrete
label is satisfied by sending every variable to the EMPTY row. -/
theorem ssat_of_no_conc {G : System} (h : ∀ c ∈ G, c.conc = (∅ : Finset Label)) : SSat G := by
  refine ⟨fun _ => (∅ : Finset Label), fun c hc => ?_⟩
  constructor
  · simp only [parts, h c hc]
    induction c.vars with
    | nil => simp
    | cons x t ih => simpa using ih
  · simp only [parts, h c hc]
    refine List.Pairwise.cons (fun b hb => ?_) ?_
    · simp only [List.mem_map] at hb
      obtain ⟨y, -, rfl⟩ := hb
      simp [Disjoint]
    · refine List.pairwise_map.mpr ?_
      exact List.pairwise_iff_forall_sublist.mpr (fun _ _ _ => by simp)

end Rowpartition.Loop
