/-
# S2: NO FALSE ACCEPTANCE — the theorems

`Loop/Decide.lean` is the executable mirror of the three flags `tracker/loopmodel/S2-DESIGN.md`
puts on `Subst.solve`; this file proves what they buy.  The headline is `solve_noFalseAccept`
(§7): with layer (iii) on and its budget not exhausted, a solve that RETURNS says the system
it was given HAS A MODEL — the converse of S1, whose `run_noLoss` / `solve_sound` are
conditional on `SSat (sys s₀)` exactly where they have to be.

The chain:

* §1-§3  `forcedBy` is SOUND: every bit it forces is true in every model, and every clash it
  reports means there is none.  These are `Constraints.checkLabel`'s five rules, and the
  content is the same as `Rowpartition.LabelAlgo`'s `algoWrite_forced` — re-proved here
  against the loop's own vocabulary (an `SSet` of abstract parts read as a list) rather than
  the relational `Constraint`, because that is what the code reads.
* §4  the SEARCH: `unsat` really means no assignment, `sat` really means one was checked.
* §5  the BRIDGE: the loop-level Boolean shadow `LSat` is `Rowpartition.BSat` at the label's
  index, under the two side conditions the vocabulary needs (`abstr` duplicate-free,
  `LblCoh`).  With `Rowpartition.satisfiable_iff_forall_label` that turns "every mentioned
  label has a checked model" into `SSat`.
* §6  layer (i): `stepS` can only turn a continuation into a DEATH (`stepS_continue`), so
  every S1 theorem about `step` transfers verbatim, and the new death is a REFUTATION
  (`bareExact_refutes`, the loop-level form of `Loop/Sound.lean`'s `bare_refutes`).
* §7  `solve_noFalseAccept`, and §8 the four seeds.
-/
import Rowpartition.Loop.Solve
import Rowpartition.Loop.Decide

namespace Rowpartition.Loop

open Rowpartition

set_option linter.unusedSimpArgs false

/-! ## 1. Counting lemmas -/

/-- Strict monotonicity of `countP` at a witness: `q` counts everything `p` does, and one
element more. -/
theorem countP_lt_of_witness {α : Type} {p q : α → Bool} :
    ∀ {L : List α}, (∀ x ∈ L, p x = true → q x = true) →
      ∀ {u : α}, u ∈ L → p u = false → q u = true → L.countP p < L.countP q
  | [], _, _, hu, _, _ => absurd hu (List.not_mem_nil)
  | a :: L, hpq, u, hu, hpu, hqu => by
    have hmono : L.countP p ≤ L.countP q :=
      List.countP_mono_left (fun x hx => hpq x (List.mem_cons_of_mem _ hx))
    rcases List.mem_cons.mp hu with rfl | hu'
    · simp only [List.countP_cons, hpu, hqu]; simp; omega
    · have ih := countP_lt_of_witness (fun x hx => hpq x (List.mem_cons_of_mem _ hx)) hu' hpu hqu
      by_cases hpa : p a = true
      · have hqa : q a = true := hpq a (List.mem_cons_self ..) hpa
        simp only [List.countP_cons, hpa, hqa]; simp; omega
      · simp only [Bool.not_eq_true] at hpa
        by_cases hqa : q a = true
        · simp only [List.countP_cons, hpa, hqa]; simp; omega
        · simp only [Bool.not_eq_true] at hqa
          simp only [List.countP_cons, hpa, hqa]; simp; omega

/-- `countP` of a disjunction is at most the sum. -/
theorem countP_or_le {α : Type} (p q : α → Bool) :
    ∀ L : List α, L.countP (fun x => p x || q x) ≤ L.countP p + L.countP q
  | [] => by simp
  | a :: L => by
    have ih := countP_or_le p q L
    rcases Bool.eq_false_or_eq_true (p a) with hp | hp <;>
      rcases Bool.eq_false_or_eq_true (q a) with hq | hq <;>
      simp only [List.countP_cons, hp, hq] <;> simp <;> omega

/-! ## 2. Agreement between a bit list and an assignment -/

/-- Every bit the list records is the assignment's. -/
def Agree (bits : List (Nat × Bool)) (b : Nat → Bool) : Prop :=
  ∀ v x, bitOf bits v = some x → b v = x

theorem agree_nil (b : Nat → Bool) : Agree [] b := by
  intro v x h; simp [bitOf] at h

/-- Reading an agreeing bit list as an assignment is the assignment, wherever it is set. -/
theorem bitFun_eq_of_agree {bits : List (Nat × Bool)} {b : Nat → Bool} (h : Agree bits b)
    {v : Nat} {x : Bool} (hv : bitOf bits v = some x) : bitFun bits v = b v := by
  rw [h v x hv]; simp [bitFun, hv]

/-- A TOTAL agreeing bit list reads back as the assignment on the variables it covers. -/
theorem bitFun_eq_of_total {bits : List (Nat × Bool)} {b : Nat → Bool} (h : Agree bits b)
    {v : Nat} (hv : (bitOf bits v).isSome = true) : bitFun bits v = b v := by
  rcases hb : bitOf bits v with _ | x
  · rw [hb] at hv; simp at hv
  · exact bitFun_eq_of_agree h hb

/-- Reading past a bit that is already recorded. -/
theorem bitOf_append_some {bits : List (Nat × Bool)} {w : Nat} {y : Bool}
    (h : bitOf bits w = some y) (v : Nat) (x : Bool) :
    bitOf (bits ++ [(v, x)]) w = some y := by
  simp only [bitOf, Option.map_eq_some_iff] at h
  obtain ⟨r, hr, hry⟩ := h
  simp [bitOf, List.find?_append, hr, hry]

/-- Reading a bit that only the appended pair can supply. -/
theorem bitOf_append_none {bits : List (Nat × Bool)} {w : Nat}
    (h : bitOf bits w = none) (v : Nat) (x : Bool) :
    bitOf (bits ++ [(v, x)]) w = if v = w then some x else none := by
  simp only [bitOf, Option.map_eq_none_iff] at h
  by_cases hv : v = w
  · subst hv; simp [bitOf, List.find?_append, h]
  · simp [bitOf, List.find?_append, h, hv, beq_iff_eq]

/-- Appending a bit the assignment agrees with keeps agreement. -/
theorem agree_append {bits : List (Nat × Bool)} {b : Nat → Bool} (h : Agree bits b)
    {v : Nat} {x : Bool} (hb : b v = x) : Agree (bits ++ [(v, x)]) b := by
  intro w y hw
  rcases hf : bitOf bits w with _ | z
  · rw [bitOf_append_none hf v x] at hw
    by_cases hv : v = w
    · subst hv; simp at hw; rw [← hw]; exact hb
    · simp [hv] at hw
  · rw [bitOf_append_some hf v x] at hw
    exact h w y (by rw [hf]; exact hw)


/-! ## 3. `forcedBy` is sound: every bit it forces is true in every model

The five clauses are `Constraints.checkLabel`'s five rules.  Writing `A` for the parts already
KNOWN to carry the label, `U` for those not yet decided and `B` for those that carry it under
a model `b`, agreement gives `A ≤ B ≤ A + U`; every clause below is that inequality together
with `LSat`'s "at most one part, and the whole iff exactly one". -/

section Forced

variable {l : Lbl} {bits : List (Nat × Bool)} {p : LPart} {b : Nat → Bool}

private def pT (bits : List (Nat × Bool)) : Nat → Bool := fun u => bitOf bits u == some true
private def pN (bits : List (Nat × Bool)) : Nat → Bool := fun u => (bitOf bits u).isNone

private theorem countP_pT_le (hag : Agree bits b) (L : List Nat) :
    L.countP (pT bits) ≤ L.countP b :=
  List.countP_mono_left (fun x _ hx => hag x true (by simpa [pT] using hx))

private theorem countP_le_pT_add_pN (hag : Agree bits b) (L : List Nat) :
    L.countP b ≤ L.countP (pT bits) + L.countP (pN bits) := by
  refine le_trans (List.countP_mono_left (fun x _ hx => ?_)) (countP_or_le _ _ L)
  rcases hb : bitOf bits x with _ | y
  · simp [pN, hb]
  · cases y with
    | true => simp [pT, hb]
    | false => rw [hag x false hb] at hx; exact absurd hx (by simp)

/-- The three counts, and the two inequalities that relate them. -/
private theorem counts (hag : Agree bits b) :
    p.rhs.abstr.toList.countP (pT bits) ≤ p.rhs.abstr.toList.countP b ∧
    p.rhs.abstr.toList.countP b ≤
      p.rhs.abstr.toList.countP (pT bits) + (unkOf bits p).length ∧
    onesOf l bits p =
      p.rhs.abstr.toList.countP (pT bits) + (if p.rhs.conc.contains l then 1 else 0) ∧
    lcount b l p =
      p.rhs.abstr.toList.countP b + (if p.rhs.conc.contains l then 1 else 0) := by
  refine ⟨countP_pT_le hag _, ?_, rfl, by simp [lcount, List.countP_eq_length_filter]⟩
  have h := countP_le_pT_add_pN (b := b) hag p.rhs.abstr.toList
  have : (unkOf bits p).length = p.rhs.abstr.toList.countP (pN bits) := by
    rw [unkOf, List.countP_eq_length_filter]; rfl
  omega

/-- At a model the guard is false: none of the three refusals fires. -/
theorem not_fbGuard_of_sat (hag : Agree bits b) (hsat : LSat b l p) : ¬ fbGuard l bits p := by
  obtain ⟨hAB, hBU, hones, hlc⟩ := counts (l := l) (p := p) hag
  obtain ⟨hle, heq⟩ := hsat
  rw [hlc] at hle heq
  rintro (h1 | ⟨hlhs, hcon⟩ | ⟨hlhs, hz, hemp⟩)
  · omega
  · have hbl : b p.lhs = false := hag p.lhs false hlhs
    rw [hbl] at heq
    have : ¬ (p.rhs.abstr.toList.countP b + (if p.rhs.conc.contains l then 1 else 0) = 1) := by
      intro hh; rw [hh] at heq; simp at heq
    simp only [hcon, if_true] at this hle
    omega
  · have hbl : b p.lhs = true := hag p.lhs true hlhs
    rw [hbl] at heq
    have h1 : p.rhs.abstr.toList.countP b + (if p.rhs.conc.contains l then 1 else 0) = 1 := by
      by_contra hne
      rw [Bool.eq_iff_iff] at heq; simp [hne] at heq
    have hU0 : (unkOf bits p).length = 0 := by rw [hemp]; rfl
    omega

/-- **The soundness of one propagation step.**  At a model, `forcedBy` never refuses, and
every bit it forces is the model's. -/
theorem forcedBy_sound (hag : Agree bits b) (hsat : LSat b l p) :
    forcedBy l bits p = some (fbBits l bits p) ∧ ∀ w ∈ fbBits l bits p, b w.1 = w.2.1 := by
  classical
  refine ⟨if_neg (not_fbGuard_of_sat hag hsat), ?_⟩
  obtain ⟨hAB, hBU, hones, hlc⟩ := counts (l := l) (p := p) hag
  obtain ⟨hle, heq⟩ := hsat
  rw [hlc] at hle heq
  set cb := (if p.rhs.conc.contains l then 1 else 0) with hcb
  set A := p.rhs.abstr.toList.countP (pT bits) with hA
  set B := p.rhs.abstr.toList.countP b with hB
  have hunkmem : ∀ u ∈ unkOf bits p, u ∈ p.rhs.abstr.toList ∧ bitOf bits u = none := by
    intro u hu
    rw [unkOf] at hu
    have h2 := List.mem_filter.mp hu
    exact ⟨h2.1, by simpa using h2.2⟩
  intro w hw
  simp only [fbBits, List.mem_append] at hw
  rcases hw with ((hw | hw) | hw) | hw
  · -- rule 1 and rule 2
    split at hw
    · rename_i hone
      rw [hones] at hone
      rcases List.mem_cons.mp hw with rfl | hw2
      · have : B + cb = 1 := by omega
        simp only []; rw [heq, this]; simp
      · simp only [List.mem_map] at hw2
        obtain ⟨u, hu, rfl⟩ := hw2
        obtain ⟨humem, hunone⟩ := hunkmem u hu
        by_contra hbu
        simp only [ne_eq, Bool.not_eq_false] at hbu
        have hlt : A < B :=
          countP_lt_of_witness (fun x _ hx => hag x true (by simpa [pT] using hx))
            humem (by simp [pT, hunone]) (by simpa using hbu)
        omega
    · exact absurd hw (by simp)
  · -- rule 3
    split at hw
    · rename_i hlhs
      simp only [List.mem_map] at hw
      obtain ⟨u, hu, rfl⟩ := hw
      obtain ⟨humem, -⟩ := hunkmem u hu
      have hbl : b p.lhs = false := hag p.lhs false hlhs
      rw [hbl] at heq
      have hne : ¬ (B + cb = 1) := by intro hh; rw [hh] at heq; simp at heq
      have hB0 : B = 0 := by omega
      have := (List.countP_eq_zero).mp (hB ▸ hB0)
      simpa using this u humem
    · exact absurd hw (by simp)
  · -- rule 4
    split at hw
    · rename_i hz
      obtain ⟨hA0, hemp⟩ := hz
      rw [hones] at hA0
      have hU0 : (unkOf bits p).length = 0 := by rw [hemp]; rfl
      simp only [List.mem_singleton] at hw
      subst hw
      have : B + cb = 0 := by omega
      simp only []; rw [heq, this]; simp
    · exact absurd hw (by simp)
  · -- rule 5
    split at hw
    · rename_i hh
      obtain ⟨hlhs, hA0⟩ := hh
      rw [hones] at hA0
      have hbl : b p.lhs = true := hag p.lhs true hlhs
      rw [hbl] at heq
      have hone : B + cb = 1 := by
        by_contra hne; rw [Bool.eq_iff_iff] at heq; simp [hne] at heq
      have hAz : A = 0 := by omega
      have hcb0 : cb = 0 := by omega
      have hB1 : B = 1 := by omega
      rcases hf : unkOf bits p with _ | ⟨u, us⟩
      · rw [hf] at hw; simp at hw
      · cases us with
        | cons _ _ => rw [hf] at hw; simp at hw
        | nil =>
          rw [hf] at hw
          simp only [List.mem_singleton] at hw
          subst hw
          obtain ⟨x, hx, hbx⟩ := List.countP_pos_iff.mp (by omega : 0 < B)
          have hxu : x = u := by
            have hxT : bitOf bits x ≠ some true := by
              intro hcon
              have : 0 < A := List.countP_pos_iff.mpr ⟨x, hx, by simp [pT, hcon]⟩
              omega
            rcases hbits : bitOf bits x with _ | y
            · have hmem : x ∈ unkOf bits p := by
                rw [unkOf]; exact List.mem_filter.mpr ⟨hx, by simp [hbits]⟩
              rw [hf] at hmem; simpa using hmem
            · cases y with
              | true => exact absurd hbits hxT
              | false => rw [hag x false hbits] at hbx; exact absurd hbx (by simp)
          subst hxu
          simpa using hbx
    · exact absurd hw (by simp)

end Forced


/-! ## 4. Propagation and the case split -/

section Search

variable {ps : List LPart} {l : Lbl} {b : Nat → Bool}

/-- The fold state `onePass` threads: no clash yet, and every bit is the model's. -/
private def StOk (b : Nat → Bool) (st : List (Nat × Bool) × Bool × Option (Nat × String)) :
    Prop := st.2.2 = none ∧ Agree st.1 b

private theorem mergeBit_sound {st : List (Nat × Bool) × Bool × Option (Nat × String)}
    {at_ : Nat} {w : Nat × Bool × String} (hst : StOk b st) (hw : b w.1 = w.2.1) :
    StOk b (mergeBit st at_ w) := by
  obtain ⟨hc, hag⟩ := hst
  cases hb : bitOf st.1 w.1 with
  | none =>
    simp only [mergeBit, hc, Option.isSome_none, Bool.false_eq_true, if_false, hb]
    exact ⟨rfl, agree_append hag hw⟩
  | some b0 =>
    have hb0 : b0 = w.2.1 := by rw [← hag w.1 b0 hb]; exact hw
    simp only [mergeBit, hc, Option.isSome_none, Bool.false_eq_true, if_false, hb, hb0,
      beq_self_eq_true, if_true]
    exact ⟨hc, hag⟩

private theorem foldl_mergeBit_sound {at_ : Nat} :
    ∀ {ws : List (Nat × Bool × String)} {st}, StOk b st → (∀ w ∈ ws, b w.1 = w.2.1) →
      StOk b (ws.foldl (fun a w => mergeBit a at_ w) st)
  | [], _, hst, _ => hst
  | w :: ws, st, hst, hall => by
    rw [List.foldl_cons]
    exact foldl_mergeBit_sound (mergeBit_sound hst (hall w (List.mem_cons_self ..)))
      (fun x hx => hall x (List.mem_cons_of_mem _ hx))

/-- **One pass never clashes at a model, and keeps every bit the model's.** -/
theorem onePass_sound (hm : LModels b l ps) :
    ∀ {qs : List LPart}, (∀ p ∈ qs, p ∈ ps) → ∀ {st}, StOk b st →
      StOk b (qs.foldl (fun st p =>
        if st.2.2.isSome then st else
        match forcedBy l st.1 p with
        | none => (st.1, st.2.1, some (p.lhs, "two parts of one partition both contain it"))
        | some ws => ws.foldl (fun a w => mergeBit a p.lhs w) st) st)
  | [], _, _, hst => hst
  | p :: qs, hsub, st, hst => by
    have hp : p ∈ ps := hsub p (List.mem_cons_self ..)
    obtain ⟨hc, hag⟩ := hst
    obtain ⟨hfb, hbits⟩ := forcedBy_sound hag (hm p hp)
    have hstep : (if st.2.2.isSome then st else
        match forcedBy l st.1 p with
        | none => (st.1, st.2.1, some (p.lhs, "two parts of one partition both contain it"))
        | some ws => ws.foldl (fun a w => mergeBit a p.lhs w) st) =
        (fbBits l st.1 p).foldl (fun a w => mergeBit a p.lhs w) st := by
      simp only [hc, Option.isSome_none, Bool.false_eq_true, if_false, hfb]
    simp only [List.foldl_cons, hstep]
    exact onePass_sound hm (fun x hx => hsub x (List.mem_cons_of_mem _ hx))
      (foldl_mergeBit_sound ⟨hc, hag⟩ hbits)

theorem onePass_ok (hm : LModels b l ps) {st} (hst : StOk b st) : StOk b (onePass ps l st) :=
  onePass_sound (ps := ps) hm (fun _ h => h) hst

/-- **Propagation never clashes at a model, and every bit it derives is the model's.** -/
theorem propagate_sound (hm : LModels b l ps) :
    ∀ (f : Nat) {bits : List (Nat × Bool)}, Agree bits b →
      (propagate ps l f bits).2 = none ∧ Agree (propagate ps l f bits).1 b
  | 0, bits, hag => ⟨rfl, hag⟩
  | f + 1, bits, hag => by
    have h := onePass_ok (ps := ps) (l := l) hm (st := (bits, false, none)) ⟨rfl, hag⟩
    obtain ⟨hc, hag'⟩ := h
    rcases hop : onePass ps l (bits, false, none) with ⟨bits', changed, clash⟩
    rw [hop] at hc hag'
    have hcl : clash = none := hc
    subst hcl
    simp only [propagate, hop]
    by_cases hch : changed = true
    · subst hch; simpa using propagate_sound hm f hag'
    · simp only [Bool.not_eq_true] at hch
      subst hch; exact ⟨rfl, hag'⟩

/-! ### The search -/

/-- A search that returns a model returns one that has been CHECKED. -/
theorem searchLabel_checks {vs : List Nat} :
    ∀ (d : Nat) {bits nodes budget m n c},
      searchLabel ps l vs d bits nodes budget = (some m, n, c) → modelChecks ps l m = true
  | 0, _, _, _, _, _, _, h => by simp [searchLabel] at h
  | d + 1, bits, nodes, budget, m, n, c, h => by
    rw [searchLabel] at h
    split at h
    · split at h
      · rename_i hchk; simp only [Prod.mk.injEq] at h
        rw [← Option.some.inj h.1]; exact hchk
      · simp at h
    · split at h
      · simp at h
      · split at h
        · split at h
          · simp at h
          · exact searchLabel_checks d h
        · split at h
          · rename_i m0 n0 c0 hrec
            simp only [Prod.mk.injEq] at h
            rw [← Option.some.inj h.1]
            exact searchLabel_checks d hrec
          · simp at h
          · split at h
            · simp at h
            · exact searchLabel_checks d h

/-- **The refutation is real.**  A search that ends `none` WITHOUT being cut short has ruled
out every assignment extending the bits it started from. -/
theorem searchLabel_sound (hm : LModels b l ps) {vs : List Nat} :
    ∀ (d : Nat) {bits nodes budget n},
      searchLabel ps l vs d bits nodes budget = (none, n, false) → ¬ Agree bits b
  | 0, _, _, _, _, h => by simp [searchLabel] at h
  | d + 1, bits, nodes, budget, n, h => by
    intro hag
    rw [searchLabel] at h
    split at h
    · split at h
      · simp at h
      · simp at h
    · rename_i v hfind
      split at h
      · simp at h
      · -- the branch the model agrees with can be neither closed by propagation nor refuted
        have hprop : ∀ (x : Bool),
            b v = x → (propagate ps l (vs.length + 2) (bits ++ [(v, x)])).2 = none ∧
              Agree (propagate ps l (vs.length + 2) (bits ++ [(v, x)])).1 b := by
          intro x hbv
          exact propagate_sound hm (vs.length + 2) (agree_append hag hbv)
        split at h
        · -- FALSE closed by propagation: the model must take TRUE
          rename_i _ c0 hp0
          have hbv : b v = true := by
            rcases hbt : b v with _ | _
            · obtain ⟨hcl, -⟩ := hprop false hbt
              rw [hp0] at hcl; exact absurd hcl (by simp)
            · rfl
          obtain ⟨hcl1, hag1⟩ := hprop true hbv
          split at h
          · rename_i _ c1 hp1; rw [hp1] at hcl1; exact absurd hcl1 (by simp)
          · rename_i b1 hp1; rw [hp1] at hag1
            exact searchLabel_sound hm d h hag1
        · -- FALSE stayed open
          rename_i b0 hp0
          rcases hbt : b v with _ | _
          · obtain ⟨-, hag0⟩ := hprop false hbt
            rw [hp0] at hag0
            split at h
            · simp at h
            · simp at h
            · rename_i n0 hrec; exact searchLabel_sound hm d hrec hag0
          · obtain ⟨hcl1, hag1⟩ := hprop true hbt
            split at h
            · simp at h
            · simp at h
            · split at h
              · rename_i _ _ hp1; rw [hp1] at hcl1; exact absurd hcl1 (by simp)
              · rename_i b1 hp1; rw [hp1] at hag1
                exact searchLabel_sound hm d h hag1

end Search


/-! ## 5. The bridge: the loop's Boolean shadow IS `Rowpartition.BSat`

`LSat` counts over the list the code reads (`abstr.toList`) and tests concrete membership with
`SSet.contains`; `BSat` is stated over a `Constraint`, whose variable part is the DEDUPLICATED
sorted list and whose concrete part is a `Finset Label` of label INDICES.  The two agree under
the two side conditions the vocabulary needs, and both are discharged where the theorem is
used: the abstract part is duplicate-free (`Wf`, and `wf_of_nodup (by decide)` at a seed), and
the solve's labels are coherent (`LblCoh`, the same hypothesis `Loop/Reject.lean` carries). -/

section Bridge

/-- At most one `true` in a list of booleans. -/
theorem pairwise_not_both_iff : ∀ {L : List Bool},
    L.Pairwise (fun x y => ¬(x = true ∧ y = true)) ↔ L.countP id ≤ 1
  | [] => by simp
  | a :: L => by
    rw [List.pairwise_cons, List.countP_cons, pairwise_not_both_iff]
    cases a with
    | false => simp
    | true =>
      simp only [id_eq, if_pos, decide_true, ite_true]
      constructor
      · rintro ⟨hall, -⟩
        have hz : L.countP id = 0 := by
          refine List.countP_eq_zero.mpr (fun x hx h => ?_)
          exact hall x hx ⟨trivial, by simpa using h⟩
        omega
      · intro h
        have hz : L.countP id = 0 := by omega
        exact ⟨fun x hx hc => (List.countP_eq_zero.mp hz x hx) (by simpa using hc.2), by omega⟩

/-- `BSat` in counting form: at most one part carries the label, and the whole carries it iff
exactly one does. -/
theorem bsat_iff_count (b : Var → Bool) (lab : Label) (c : Constraint) :
    BSat b lab c ↔
      (c.vars.countP b + (if lab ∈ c.conc then 1 else 0) ≤ 1 ∧
       b c.lhs = decide (c.vars.countP b + (if lab ∈ c.conc then 1 else 0) = 1)) := by
  classical
  have key : ∀ n : Nat, n ≤ 1 → (decide (0 < n) = decide (n = 1)) := by
    intro n hn
    match n, hn with
    | 0, _ => simp
    | 1, _ => simp
  have hcount : (bparts b lab c).countP id =
      c.vars.countP b + (if lab ∈ c.conc then 1 else 0) := by
    simp only [bparts, List.countP_cons, List.countP_map]
    by_cases hm : lab ∈ c.conc
    · simp only [hm, if_true, decide_true, id_eq, Function.comp_def]
    · simp only [hm, if_false, decide_false, id_eq, Bool.false_eq_true, Function.comp_def]
  have hor : (bparts b lab c).foldr (· || ·) false =
      decide (0 < (bparts b lab c).countP id) := by
    rcases Nat.eq_zero_or_pos ((bparts b lab c).countP id) with hz | hpos
    · rw [hz]
      simp only [Nat.lt_irrefl, decide_false]
      rw [← Bool.not_eq_true]
      intro hcon
      obtain ⟨x, hx, hxt⟩ := (foldr_or_eq_true _).mp hcon
      exact absurd (List.countP_eq_zero.mp hz x hx) (by simp [hxt])
    · rw [decide_eq_true hpos]
      obtain ⟨x, hx, hxt⟩ := List.countP_pos_iff.mp hpos
      exact (foldr_or_eq_true _).mpr ⟨x, hx, by simpa using hxt⟩
  rw [BSat, hor, pairwise_not_both_iff, hcount]
  constructor
  · rintro ⟨h1, h2⟩; exact ⟨h2, by rw [h1, key _ h2]⟩
  · rintro ⟨h1, h2⟩; exact ⟨by rw [h2, key _ h1], h1⟩


/-- `toConstraint`'s variable list is a permutation of the list the code reads, when the
abstract part is duplicate-free. -/
theorem vars_perm (p : LPart) (hnd : p.rhs.abstr.elems.Nodup) :
    p.toConstraint.vars.Perm p.rhs.abstr.toList := by
  have hv : p.toConstraint.vars = slist (p.rhs.abstr.elems.toFinset) := rfl
  rw [hv]
  exact List.perm_of_nodup_nodup_toFinset_eq (slist_nodup _) hnd (by simp [SSet.toList])

/-- Concrete membership: the `SSet` test and the constraint's label set agree, given that the
labels are coherent. -/
theorem conc_mem_iff {L : List Lbl} (hcoh : LblCoh L) {p : LPart} {l : Lbl}
    (hl : l ∈ L) (hmem : ∀ x ∈ p.rhs.conc.elems, x ∈ L) :
    (l.n ∈ p.toConstraint.conc) ↔ p.rhs.conc.contains l = true := by
  rw [LPart.conc_toConstraint]
  constructor
  · intro h
    obtain ⟨x, hx, hxn⟩ := by simpa [List.mem_toFinset, List.mem_map] using h
    have : x = l := hcoh x (hmem x hx) l hl hxn
    exact (SSet.contains_iff _ _).mpr (this ▸ hx)
  · intro h
    have := (SSet.contains_iff _ _).mp h
    simp only [List.mem_toFinset, List.mem_map]
    exact ⟨l, this, rfl⟩

/-- **The loop's Boolean shadow IS `Rowpartition.BSat`.** -/
theorem lsat_iff_bsat {L : List Lbl} (hcoh : LblCoh L) {p : LPart} {l : Lbl} (hl : l ∈ L)
    (hnd : p.rhs.abstr.elems.Nodup) (hmem : ∀ x ∈ p.rhs.conc.elems, x ∈ L) (b : Nat → Bool) :
    LSat b l p ↔ BSat b l.n p.toConstraint := by
  rw [bsat_iff_count, LSat, lcount]
  have hv : p.toConstraint.vars.countP b = (p.rhs.abstr.toList.filter b).length := by
    rw [(vars_perm p hnd).countP_eq, List.countP_eq_length_filter]
  have hc : (if l.n ∈ p.toConstraint.conc then 1 else 0) =
      (if p.rhs.conc.contains l then 1 else 0) := by
    by_cases h : p.rhs.conc.contains l = true
    · rw [if_pos ((conc_mem_iff hcoh hl hmem).mpr h)]; simp [h]
    · simp only [Bool.not_eq_true] at h
      have hnot : l.n ∉ p.toConstraint.conc := by
        intro hh
        have h2 := (conc_mem_iff hcoh hl hmem).mp hh
        rw [h] at h2; exact absurd h2 (by simp)
      rw [if_neg hnot]; simp [h]
  rw [hv, hc, LPart.lhs_toConstraint]

/-- System-level form. -/
theorem lmodels_iff_bmodels {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart} {l : Lbl}
    (hl : l ∈ L) (hnd : ∀ p ∈ ps, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ ps, ∀ x ∈ p.rhs.conc.elems, x ∈ L) (b : Nat → Bool) :
    LModels b l ps ↔ BModels b l.n (ps.map LPart.toConstraint) := by
  constructor
  · intro h c hc
    obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hc
    exact (lsat_iff_bsat hcoh hl (hnd p hp) (hmem p hp) b).mp (h p hp)
  · intro h p hp
    exact (lsat_iff_bsat hcoh hl (hnd p hp) (hmem p hp) b).mpr
      (h _ (List.mem_map.mpr ⟨p, hp, rfl⟩))

end Bridge

/-! ## 6. Layer (iii), end to end -/

section Layer3

variable {ps : List LPart} {budget : Nat}

/-- A label decided SAT hands back a CHECKED model. -/
theorem decideLabel_sat {l : Lbl} {m : List (Nat × Bool)}
    (h : (decideLabel ps l budget).1 = .sat m) : LModels (bitFun m) l ps := by
  have hchk : modelChecks ps l m = true := by
    rw [decideLabel] at h
    split at h
    · simp at h
    · rename_i bits hpp
      rcases hs : searchLabel ps l (decideVars ps) ((decideVars ps).length + 1) bits 0 budget
        with ⟨r, n, c⟩
      rw [hs] at h
      cases r with
      | none => cases c <;> simp at h
      | some m' =>
        simp only [DecideRes.sat.injEq] at h
        rw [← h]
        exact searchLabel_checks _ hs
  intro p hp
  have := List.all_eq_true.mp hchk p hp
  simpa using this

/-- **A label decided UNSAT really has no assignment.** -/
theorem decideLabel_unsat {l : Lbl} {a : Nat} {w : String}
    (h : (decideLabel ps l budget).1 = .unsat a w) : ¬ ∃ b, LModels b l ps := by
  rintro ⟨b, hm⟩
  rw [decideLabel] at h
  split at h
  · rename_i bits cl hpp
    obtain ⟨hcl, -⟩ := propagate_sound hm ((decideVars ps).length + 2) (agree_nil b)
    rw [hpp] at hcl
    exact absurd hcl (by simp)
  · rename_i bits hpp
    obtain ⟨-, hag⟩ := propagate_sound hm ((decideVars ps).length + 2) (agree_nil b)
    rw [hpp] at hag
    rcases hs : searchLabel ps l (decideVars ps) ((decideVars ps).length + 1) bits 0 budget
      with ⟨r, n, c⟩
    rw [hs] at h
    cases r with
    | some _ => simp at h
    | none =>
      cases c with
      | true => simp at h
      | false => exact searchLabel_sound hm _ hs hag

/-- What every entry of `decideFrom` guarantees: its label is one of the list's, a `sat`
entry carries a model, and an `unsat` entry really refutes.  A `noVerdict` entry — a cap that
ran out — guarantees nothing, which is the point of it. -/
theorem decideFrom_entry (ps : List LPart) (b sb : Nat) :
    ∀ (ls : List Lbl) (spent : Nat) {e : Lbl × DecideRes × Nat},
      e ∈ decideFrom ps b sb ls spent →
      e.1 ∈ ls ∧ (∀ m, e.2.1 = .sat m → LModels (bitFun m) e.1 ps) ∧
      (∀ a w, e.2.1 = .unsat a w → ¬ ∃ bb, LModels bb e.1 ps)
  | [], _, e, he => by simp [decideFrom] at he
  | x :: ls, spent, e, he => by
    rw [decideFrom] at he
    split at he
    · rcases List.mem_cons.mp he with rfl | he'
      · exact ⟨List.mem_cons_self .., by intro m hm; exact absurd hm (by simp),
               by intro a w hw; exact absurd hw (by simp)⟩
      · obtain ⟨h1, h2, h3⟩ := decideFrom_entry ps b sb ls spent he'
        exact ⟨List.mem_cons_of_mem _ h1, h2, h3⟩
    · rcases hdl : decideLabel ps x (min b (sb - spent)) with ⟨r0, n0⟩
      simp only [hdl] at he
      rcases List.mem_cons.mp he with rfl | he'
      · refine ⟨List.mem_cons_self .., ?_, ?_⟩
        · intro m hm; exact decideLabel_sat (by rw [hdl]; exact hm)
        · intro a w hw; exact decideLabel_unsat (by rw [hdl]; exact hw)
      · obtain ⟨h1, h2, h3⟩ := decideFrom_entry ps b sb ls (spent + n0) he'
        exact ⟨List.mem_cons_of_mem _ h1, h2, h3⟩

theorem mem_decideAll_label {ps : List LPart} {b sb : Nat} {e : Lbl × DecideRes × Nat}
    (he : e ∈ decideAll ps b sb) : e.1 ∈ mentionedLabels ps :=
  (decideFrom_entry ps b sb _ 0 he).1

theorem decideAll_unsat {ps : List LPart} {b sb : Nat} {e : Lbl × DecideRes × Nat}
    (he : e ∈ decideAll ps b sb) {a : Nat} {w : String} (hw : e.2.1 = .unsat a w) :
    ¬ ∃ bb, LModels bb e.1 ps :=
  (decideFrom_entry ps b sb _ 0 he).2.2 a w hw

/-- Every label of the list gets an entry, and an entry that says `sat` really carries a
model.  This is what the per-SOLVE cap costs in proof: `decideAll` is no longer a `map`. -/
theorem mem_decideFrom (ps : List LPart) (b sb : Nat) :
    ∀ (ls : List Lbl) (spent : Nat) {l : Lbl}, l ∈ ls →
      ∃ r n, (l, r, n) ∈ decideFrom ps b sb ls spent ∧
             ∀ m, r = .sat m → LModels (bitFun m) l ps
  | [], _, _, hl => absurd hl (List.not_mem_nil)
  | x :: ls, spent, l, hl => by
    rw [decideFrom]
    split
    · rcases List.mem_cons.mp hl with rfl | hl'
      · exact ⟨_, 0, List.mem_cons_self .., by intro m hm; exact absurd hm (by simp)⟩
      · obtain ⟨r, n, hmem, hsat⟩ := mem_decideFrom ps b sb ls spent hl'
        exact ⟨r, n, List.mem_cons_of_mem _ hmem, hsat⟩
    · rcases hdl : decideLabel ps x (min b (sb - spent)) with ⟨r0, n0⟩
      simp only [hdl]
      rcases List.mem_cons.mp hl with rfl | hl'
      · refine ⟨r0, n0, List.mem_cons_self .., ?_⟩
        intro m hm
        exact decideLabel_sat (by rw [hdl]; exact hm)
      · obtain ⟨r, n, hmem, hsat⟩ := mem_decideFrom ps b sb ls (spent + n0) hl'
        exact ⟨r, n, List.mem_cons_of_mem _ hmem, hsat⟩

/-- **Layer (iii) is COMPLETE.**  A pass means every mentioned label's problem was decided
SAT, with a model that was checked against every partition. -/
theorem labelDecide_sat_models {solveBudget : Nat}
    (h : (labelDecide ps budget solveBudget).1 = .sat) :
    ∀ l ∈ mentionedLabels ps, ∃ b, LModels b l ps := by
  intro l hl
  have hres : ∀ r ∈ decideAll ps budget solveBudget,
      (match r.2.1 with | .unsat a w => some (r.1, a, w) | _ => none) = none ∧
      (match r.2.1 with | .noVerdict w => some (r.1, w) | _ => none) = none := by
    rw [labelDecide] at h
    split at h
    · simp at h
    · rename_i h1
      split at h
      · simp at h
      · rename_i h2
        intro r hr
        exact ⟨List.findSome?_eq_none_iff.mp h1 r hr, List.findSome?_eq_none_iff.mp h2 r hr⟩
  obtain ⟨r, n, hmem, hsat⟩ := mem_decideFrom ps budget solveBudget (mentionedLabels ps) 0 hl
  obtain ⟨hu0, hn0⟩ := hres _ hmem
  have hu : (match r with | .unsat a w => some (l, a, w) | _ => none) = none := hu0
  have hn : (match r with | .noVerdict w => some (l, w) | _ => none) = none := hn0
  cases hd : r with
  | sat m => exact ⟨bitFun m, hsat m hd⟩
  | unsat a w => rw [hd] at hu; simp at hu
  | noVerdict w => rw [hd] at hn; simp at hn

end Layer3




/-! ## 7. Layer (iii) in the relational semantics -/

/-- **LAYER (iii) IS COMPLETE.**  If the decision passes, the system HAS A MODEL — one that
was constructed label by label and checked against every constraint. -/
theorem labelDecide_sat_ssat {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart} {budget : Nat}
    (hnd : ∀ p ∈ ps, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ ps, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    {solveBudget : Nat} (h : (labelDecide ps budget solveBudget).1 = .sat) :
    SSat ((ps.map LPart.toConstraint).toFinset) := by
  have hall : ∀ lab : Label, ∃ b, BModels b lab (ps.map LPart.toConstraint) := by
    intro lab
    by_cases hmen : ∃ x ∈ mentionedLabels ps, x.n = lab
    · obtain ⟨x, hx, rfl⟩ := hmen
      obtain ⟨b, hb⟩ := labelDecide_sat_models h x hx
      obtain ⟨p, hp, hxc⟩ := mem_mentionedLabels.mp hx
      exact ⟨b, (lmodels_iff_bmodels hcoh (hmem p hp x hxc) hnd hmem b).mp hb⟩
    · refine ⟨fun _ => false, bmodels_false_of_not_mem _ _ ?_⟩
      intro hcon
      obtain ⟨c, hc, hlc⟩ := mem_concLabels.mp hcon
      obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hc
      rw [LPart.conc_toConstraint] at hlc
      obtain ⟨x, hx, hxn⟩ := mem_cfs.mp hlc
      exact hmen ⟨x, mem_mentionedLabels.mpr ⟨p, hp, hx⟩, hxn⟩
  obtain ⟨rho, hrho⟩ := (satisfiable_iff_forall_label _).mpr hall
  exact ⟨rho, fun c hc => hrho c (List.mem_toFinset.mp hc)⟩

/-- **LAYER (iii) IS SOUND.**  A refutation means the system has NO model — so the new death
is a real one, and the compiler's `Row partitions are unsatisfiable at field 'l'` is the truth
about the program. -/
theorem labelDecide_refuted_unsat {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart}
    {budget : Nat} (hnd : ∀ p ∈ ps, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ ps, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    {solveBudget : Nat} {l : Lbl} {a : Nat} {w : String}
    (h : (labelDecide ps budget solveBudget).1 = .refuted l a w) :
    ¬ SSat ((ps.map LPart.toConstraint).toFinset) := by
  -- the refutation names a label of the list, decided `.unsat`
  have hfs : (decideAll ps budget solveBudget).findSome?
      (fun r => match r.2.1 with | .unsat a' w' => some (r.1, a', w') | _ => none) =
      some (l, a, w) := by
    rw [labelDecide] at h
    split at h
    · rename_i x hx
      obtain ⟨l0, a0, w0⟩ := x
      simp only [DecideVerdict.refuted.injEq] at h
      obtain ⟨rfl, rfl, rfl⟩ := h
      exact hx
    · split at h <;> simp at h
  obtain ⟨r, hr, hrf0⟩ := List.exists_of_findSome?_eq_some hfs
  -- the entry the search found is at a label of the list, and it says `unsat`
  have hrf : (match r.2.1 with | .unsat a' w' => some (r.1, a', w') | _ => none) =
      some (l, a, w) := hrf0
  have hboth : r.2.1 = .unsat a w ∧ r.1 = l := by
    cases hd : r.2.1 with
    | sat m => rw [hd] at hrf; simp at hrf
    | unsat a2 w2 =>
      rw [hd] at hrf
      simp only [Option.some.injEq, Prod.mk.injEq] at hrf
      obtain ⟨h1, h2, h3⟩ := hrf
      subst h2; subst h3
      exact ⟨rfl, h1⟩
    | noVerdict w2 => rw [hd] at hrf; simp at hrf
  obtain ⟨hu0, hlab⟩ := hboth
  have hl0 : r.1 ∈ mentionedLabels ps := mem_decideAll_label hr
  have hno0 : ¬ ∃ b, LModels b r.1 ps := decideAll_unsat hr hu0
  rw [hlab] at hl0 hno0
  obtain ⟨p, hp, hlc⟩ := mem_mentionedLabels.mp hl0
  rintro ⟨rho, hrho⟩
  have hmod : Models rho (ps.map LPart.toConstraint) :=
    fun c hc => hrho c (List.mem_toFinset.mpr hc)
  exact hno0 ⟨proj rho l.n,
    (lmodels_iff_bmodels hcoh (hmem p hp l hlc) hnd hmem _).mpr
      ((models_iff_forall_label rho _).mp hmod l.n)⟩

/-! ## 8. Layer (i): the new death is a refutation, and it is the ONLY change -/

section Bare

/-- With layer (i) off, `stepS` IS `step`. -/
theorem stepS_of_flag_off {s : State} (h : s.flags.rowSoundBare = false) : stepS s = step s := by
  unfold stepS
  split
  · rfl
  · rw [h]; simp

/-- With layer (i) off, `runS` IS `run`.  The flag cannot move under the loop:
`Loop/RefineLearn.lean`'s `step_flags` proves `s'.flags = s.flags` outright, so this is
unconditional (S2 review V-9 — it used to carry that as a hypothesis). -/
theorem runS_of_flag_off :
    ∀ (n : Nat) (s : State), s.flags.rowSoundBare = false → runS s n = run s n
  | 0, _, _ => rfl
  | n + 1, s, h => by
    rw [runS, run, stepS_of_flag_off h]
    cases hs : step s with
    | done s' => rfl
    | died m s' => rfl
    | «continue» s' =>
      simp only []
      exact runS_of_flag_off n s' (by rw [step_flags hs, h])

/-- **`stepS` can only turn a continuation into a DEATH.**  Whenever it continues, `step`
continues to the same state — so every S1 theorem about `step` (`step_noLoss_all`,
`step_noLoss_or`, `step_queueHygiene`, …) applies verbatim with layer (i) on, with no new
hypothesis and no weakening. -/
theorem stepS_continue {s s' : State} (h : stepS s = .continue s') : step s = .continue s' := by
  unfold stepS at h
  split at h
  · exact h
  · split at h
    · split at h
      · exact absurd h (by simp)
      · exact h
    · exact h

/-- The same for a normal finish. -/
theorem stepS_done {s s' : State} (h : stepS s = .done s') : step s = .done s' := by
  unfold stepS at h
  split at h
  · exact h
  · split at h
    · split at h
      · exact absurd h (by simp)
      · exact h
    · exact h

/-- A failing compatibility fold names the definition that failed. -/
theorem bareExact_error {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {m : String}
    (h : bareExact v fs incm proc = .error m) :
    ∃ p ∈ proc.elems ++ incm.elems, p.lhs = v ∧
      ((p.rhs.abstr.isEmpty = true ∧ p.rhs.conc.eqv fs = false) ∨
       p.rhs.conc.subsetOf fs = false) := by
  have gen : ∀ (L : List LPart) (acc : Except String Unit),
      L.foldl (fun (a : Except String Unit) (p : LPart) => do
        let _ ← a
        if p.rhs.abstr.isEmpty then ensureExactly p.rhs.conc fs
        else ensureSuperset p.rhs.conc fs) acc = .error m →
      (∃ m', acc = .error m') ∨
      ∃ p ∈ L, (p.rhs.abstr.isEmpty = true ∧ p.rhs.conc.eqv fs = false) ∨
                p.rhs.conc.subsetOf fs = false := by
    intro L
    induction L with
    | nil => intro acc hacc; exact Or.inl ⟨m, hacc⟩
    | cons p L ih =>
      intro acc hacc
      rw [List.foldl_cons] at hacc
      rcases ih _ hacc with ⟨m', hm'⟩ | ⟨q, hq, hqq⟩
      · rcases hacc0 : acc with m0 | u
        · exact Or.inl ⟨m0, rfl⟩
        · rw [hacc0] at hm'
          simp only [bind, Except.bind] at hm'
          refine Or.inr ⟨p, List.mem_cons_self .., ?_⟩
          by_cases hb : p.rhs.abstr.isEmpty = true
          · simp only [hb, if_true, ensureExactly] at hm'
            split at hm'
            · exact absurd hm' (by simp)
            · rename_i hne; exact Or.inl ⟨hb, by simpa using hne⟩
          · simp only [Bool.not_eq_true] at hb
            simp only [hb, Bool.false_eq_true, if_false, ensureSuperset] at hm'
            split at hm'
            · exact absurd hm' (by simp)
            · rename_i hne; exact Or.inr (by simpa using hne)
      · exact Or.inr ⟨q, List.mem_cons_of_mem _ hq, hqq⟩
  rcases gen _ _ h with ⟨m', hm'⟩ | ⟨p, hp, hpp⟩
  · exact absurd hm' (by simp)
  · exact ⟨p, (List.mem_filter.mp hp).1, by simpa using (List.mem_filter.mp hp).2, hpp⟩

/-- Two `SSet Lbl`s with different label INDEX sets are different sets, and conversely under
`LblCoh` — so `SSet.eqv` deciding `false` really does mean the two rows differ. -/
theorem cfs_ne_of_not_eqv {L : List Lbl} (hcoh : LblCoh L) {C F : SSet Lbl}
    (hCn : C.elems.Nodup) (hFn : F.elems.Nodup)
    (hC : ∀ x ∈ C.elems, x ∈ L) (hF : ∀ x ∈ F.elems, x ∈ L)
    (hne : C.eqv F = false) : cfs C ≠ cfs F := by
  intro heq
  refine absurd ((SSet.eqv_iff_toFinset hCn hFn).mpr ?_) (by simp [hne])
  apply Finset.ext
  intro x
  constructor
  · intro hx
    have hx' : x ∈ C.elems := List.mem_toFinset.mp hx
    have : x.n ∈ cfs F := heq ▸ mem_cfs.mpr ⟨x, hx', rfl⟩
    obtain ⟨y, hy, hyn⟩ := mem_cfs.mp this
    exact List.mem_toFinset.mpr ((hcoh y (hF y hy) x (hC x hx') hyn) ▸ hy)
  · intro hx
    have hx' : x ∈ F.elems := List.mem_toFinset.mp hx
    have : x.n ∈ cfs C := heq ▸ mem_cfs.mpr ⟨x, hx', rfl⟩
    obtain ⟨y, hy, hyn⟩ := mem_cfs.mp this
    exact List.mem_toFinset.mpr ((hcoh y (hC y hy) x (hF x hx') hyn) ▸ hy)

end Bare


/-- **THE NEW DEATH IS A REFUTATION.**  Layer (i) refuses only when a BARE definition of the
dequeued variable carries a different concrete row from the one being installed — and a system
with two different bare rows for one variable has no model.  This is `Loop/Sound.lean`'s
`bare_refutes`, at the loop's own vocabulary.

(The other way `bareExact` can refuse is `ensureSuperset`, which is the SHIPPED check raising
the SHIPPED death at the same point; layer (i) adds nothing there.) -/
theorem bare_death_refutes {L : List Lbl} (hcoh : LblCoh L) {s : State} {r : LPart}
    {rest : PQueue} (hdq : s.incm.dequeue = some (r, rest))
    (hra : r.rhs.abstr.isEmpty = true) (hrn : r.rhs.conc.elems.Nodup)
    (hrL : ∀ x ∈ r.rhs.conc.elems, x ∈ L)
    {p : LPart} (hp : p ∈ s.proc.elems ++ rest.elems) (hlhs : p.lhs = r.lhs)
    (hpa : p.rhs.abstr.isEmpty = true) (hpn : p.rhs.conc.elems.Nodup)
    (hpL : ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hne : p.rhs.conc.eqv r.rhs.conc = false) :
    ¬ SSat (sys s) := by
  have hemp : ∀ q : LPart, q.rhs.abstr.isEmpty = true →
      q.toConstraint = Rowpartition.mk q.lhs ∅ (cfs q.rhs.conc) := by
    intro q hq
    have : q.rhs.abstr.elems = [] := List.isEmpty_iff.mp hq
    simp [LPart.toConstraint, this, cfs]
  have h1 : Rowpartition.mk p.lhs ∅ (cfs p.rhs.conc) ∈ sys s := by
    rw [← hemp p hpa]
    rcases List.mem_append.mp hp with hpp | hpr
    · exact mem_sys_of_proc hpp
    · exact mem_sys_of_incm (dequeue_sub hdq _ hpr)
  have h2 : Rowpartition.mk r.lhs ∅ (cfs r.rhs.conc) ∈ sys s := by
    rw [← hemp r hra]; exact mem_sys_of_incm (dequeue_mem hdq)
  rw [hlhs] at h1
  exact bare_refutes h1 h2 (cfs_ne_of_not_eqv hcoh hpn hrn hpL hrL hne)

/-! ## 9. `solve_noFalseAccept` -/

/-- The model's `solveSeed` REJECTS whenever layer (iii) refutes: the check sits between the
early label check and the loop, exactly where `Subst.solve` runs it. -/
theorem solveSeed_rejects_of_refuted {fl : Flags} {site loc : String} {cs : List CsItem}
    {ns : Names} {su0 : Sup} {fuel : Nat} {envFacts : List LPart} {q : PQueue} {su1 : Sup}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    {l : Lbl} {a : Nat} {w : String}
    (href : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
              fl.rowSoundSolveBudget).1 = .refuted l a w) :
    (solveSeed fl site loc cs ns su0 fuel envFacts).verdict = "REJECTED" := by
  simp only [solveSeed, hq, hearly, hflag, if_true, href]

/-- **NO FALSE ACCEPTANCE.**  With layer (iii) on, a solve that does NOT reject says the
system it was given — the queue's partitions TOGETHER WITH the environment facts the trace's
`senv` records carry (S1 review Z-6; `S2-DESIGN.md` §3) — HAS A MODEL.

The two provisos are the ones `S2-DESIGN.md` §2 states and refuses to hide:

* `hbud`: the search was not cut short.  A cut is reported as `NoVerdict`, refutes nothing,
  and is counted (`GenRules.rowSoundBudgetHits`) so that "it never fired" is a measurement.
* `hnd` / `hmem` / `hcoh`: the vocabulary side conditions — an abstract part is duplicate-free
  (`Wf`, and `wf_of_nodup (by decide)` at a seed) and the solve's labels are coherent
  (`LblCoh`, the hypothesis `Loop/Reject.lean` already carries).

This is the CONVERSE of S1: `run_noLoss` and `solve_sound` are conditional on `SSat (sys s₀)`
exactly where they have to be, and this is what supplies it. -/
theorem solve_noFalseAccept {L : List Lbl} (hcoh : LblCoh L)
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeed fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED") :
    SSat ((((q.elems ++ envFacts).map LPart.toConstraint)).toFinset) := by
  have hsat : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
      fl.rowSoundSolveBudget).1 = .sat := by
    cases hv : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
        fl.rowSoundSolveBudget).1 with
    | sat => rfl
    | refuted l a w => exact absurd (solveSeed_rejects_of_refuted hq hearly hflag hv) hacc
    | noVerdict l w => exact absurd hv (hbud l w)
  exact labelDecide_sat_ssat hcoh hnd hmem hsat

/-- The queue half of the conclusion, in the `sys`-of-a-state form S1's theorems use: at an
initial state the environment is empty, so `sys` IS the queue's partitions. -/
theorem sys_initState_eq {q : PQueue} {su : Sup} {tr : List String} {fl : Flags}
    {ns : Names} {site : String} {z : Nat} :
    sys (initState q su tr fl ns site z) = (q.elems.map LPart.toConstraint).toFinset := by
  simp [sys, initState, State.parts, PQueue.empty, Env.sys]


/-! ## 9b. The chain to S1, as a theorem (S2 review V-1)

`solve_noFalseAccept` concludes `SSat (q ∪ E)`; S1's `run_noLoss` / `run_models` /
`run_ssat_iff` are conditional on `SSat (sys s₀)`, and `sys_initState_eq` says `sys s₀` is the
QUEUE's constraints alone.  The composition needs one step — satisfiability is ANTITONE in the
constraint set — and then it is S1's theorem applied at the hypothesis S2 supplies.  The review
was right that this was prose; here it is. -/

/-- Satisfiability is antitone: a model of a bigger system models every subsystem. -/
theorem ssat_of_subset {G G' : System} (hsub : G ⊆ G') (h : SSat G') : SSat G := by
  obtain ⟨rho, hm⟩ := h
  exact ⟨rho, fun c hc => hm c (hsub hc)⟩

/-- The queue's constraints are part of the live input. -/
theorem sys_subset_live {q : PQueue} {envFacts : List LPart} {su : Sup} {tr : List String}
    {fl : Flags} {ns : Names} {site : String} {z : Nat} :
    sys (initState q su tr fl ns site z) ⊆
      (((q.elems ++ envFacts).map LPart.toConstraint)).toFinset := by
  rw [sys_initState_eq]
  intro c hc
  rw [List.mem_toFinset] at hc ⊢
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hc
  exact List.mem_map.mpr ⟨p, List.mem_append_left _ hp, rfl⟩

/-- **THE CHAIN.**  With layer (iii) on and its budget intact, a solve that ACCEPTS is
FAITHFUL: the loop lost nothing, every model of the output system is a model of the input
system, and the two are satisfiable together.

This is S1 and S2 composed.  S2 supplies the `SSat (sys s₀)` that every S1 output-soundness
theorem is conditional on — that is the whole point of the stage — and the restriction step
`ssat_of_subset`/`sys_subset_live` is what carries it from the LIVE input (queue plus
environment facts) down to the queue the loop actually runs on. -/
theorem solve_accepted_faithful {L : List Lbl} (hcoh : LblCoh L)
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup} {tr : List String} {z : Nat}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeed fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED")
    -- and the S1 side conditions, exactly as `solve_sound` carries them
    (n : Nat) (hw : Wf (initState q su1 tr fl ns site z))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hb : RunSupOk n (initState q su1 tr fl ns site z))
    {s' : State}
    (hres : run (initState q su1 tr fl ns site z) n = .solved s' ∨
            run (initState q su1 tr fl ns site z) n = .outOfFuel s') :
    NoLoss (sys (initState q su1 tr fl ns site z)) (sys s') ∧
    (∀ rho, SModels rho (sys s') → SModels rho (sys (initState q su1 tr fl ns site z))) ∧
    (SSat (sys (initState q su1 tr fl ns site z)) ↔ SSat (sys s')) := by
  have hlive : SSat ((((q.elems ++ envFacts).map LPart.toConstraint)).toFinset) :=
    solve_noFalseAccept hcoh hq hearly hflag hnd hmem hbud hacc
  have hsat : SSat (sys (initState q su1 tr fl ns site z)) :=
    ssat_of_subset sys_subset_live hlive
  exact ⟨run_noLoss n hw hem hdj hcse hb hsat s' hres,
         run_models hw hem hdj hcse hb hsat hres,
         run_ssat_iff hw hem hdj hcse hb hsat hres⟩

/-! ## 10. The seeds

The three witnesses of `tracker/repro/satterm/seeds/unsat/` and one satisfiable control.  Each
fact below is checked IN THE KERNEL by `rfl`.

The kernel runs the LOOP (`runS`) and the DECISION (`labelDecide`) but not `solveSeed`: the
early label check it calls, `Loop/Json.lean`'s `checkLabel`, is compiled by WELL-FOUNDED
recursion (`decreasing_by`) and does not reduce definitionally.  That is a property of the L1
model, not of S2, and it costs nothing here — the loop and the decision are exactly the two
halves the theorems are about, and the end-to-end verdict is the L2 differential's business. -/

section Seeds
set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

/-- Layer (iii) on, nothing else moved. -/
def rsFlags : Flags := { rowSoundBare := true, rowSoundSat := true, rowSoundDecide := true }

/-- The reason clause layer (iii) gives when propagation alone was silent. -/
def searchReason (n : Nat) : String :=
  "no assignment of this field to the parts satisfies every partition (complete search, " ++
  toString n ++ " cases; unit propagation alone does not see it)"

/-- `MIN1` (S1 review Z-1): the loop reaches `.done` on a residual it never refuted.
UNSATISFIABLE at `l35`, and `labelCheckEarly` passes it. -/
def min1Seed : Seed :=
  { name := "MIN1",
    cons := [⟨6, [7, 2], []⟩, ⟨6, [4], [35]⟩, ⟨7, [3, 1], []⟩, ⟨3, [2, 0], []⟩, ⟨1, [0], [22]⟩],
    rhoKeys := [] }

/-- `MIN2` (S1 review Z-2): the bare-row hole.  UNSATISFIABLE at `l17`. -/
def min2Seed : Seed :=
  { name := "MIN2",
    cons := [⟨2, [3, 0], []⟩, ⟨3, [0, 1], []⟩, ⟨2, [1], [17]⟩, ⟨2, [], [17, 38]⟩,
             ⟨5, [2, 8], []⟩],
    rhoKeys := [] }

/-- `SURV1` (`U11/u00857`, S1 review §7.1): the seed that survives `labelClash` on the
SATURATED set too.  UNSATISFIABLE at `l20`; refuting it needs a CASE SPLIT. -/
def surv1Seed : Seed :=
  { name := "SURV1",
    cons := [⟨5, [2, 6, 0], []⟩, ⟨5, [2, 4], [1]⟩, ⟨3, [2, 1, 6], [20]⟩, ⟨3, [0, 4], []⟩],
    rhoKeys := [] }

/-- The queue one seed builds at id base 300, and the state the loop starts from. -/
def seedQ (sd : Seed) (base : Nat) : PQueue :=
  match buildQueue (seedSystem sd base).1 (Sup.ofSeed (seedSystem sd base).2.supplyLo) with
  | .ok (q, _) => q
  | .error _ => PQueue.empty

def seedS0 (fl : Flags) (sd : Seed) (base : Nat) : State :=
  match buildQueue (seedSystem sd base).1 (Sup.ofSeed (seedSystem sd base).2.supplyLo) with
  | .ok (q, su) =>
    initState q su [] fl (seedSystem sd base).2 sd.name (seedSystem sd base).2.supplyLo
  | .error _ =>
    initState PQueue.empty (Sup.ofSeed 0) [] fl (seedSystem sd base).2 sd.name 0

/-- **The bug, in the kernel.**  The shipped loop ACCEPTS `MIN1`. -/
theorem min1_loop_accepts : isSolvedB (runS (seedS0 {} min1Seed 300) 200) = true := by rfl

/-- **The fix, in the kernel.**  Layer (iii) REFUTES `MIN1`, at `l35`. -/
theorem min1_decide_refutes :
    (labelDecide (seedQ min1Seed 300).elems 200000 1000000).1 =
      .refuted (Lbl.repro 35) 305 (searchReason 2) := by rfl

/-- **The bug, in the kernel.**  The shipped loop ACCEPTS `MIN2` at this id base. -/
theorem min2_loop_accepts : isSolvedB (runS (seedS0 {} min2Seed 300) 200) = true := by rfl

/-- **The fix.**  Layer (iii) REFUTES `MIN2`, at `l17`. -/
theorem min2_decide_refutes :
    (labelDecide (seedQ min2Seed 300).elems 200000 1000000).1 =
      .refuted (Lbl.repro 17) 304 (searchReason 1) := by rfl

/-- **The bug.**  The shipped loop ACCEPTS `SURV1`. -/
theorem surv1_loop_accepts : isSolvedB (runS (seedS0 {} surv1Seed 300) 200) = true := by rfl

/-- **The fix, on the seed that survives BOTH propagations.**  Layer (iii) REFUTES `SURV1`,
at `l20`. -/
theorem surv1_decide_refutes :
    (labelDecide (seedQ surv1Seed 300).elems 200000 1000000).1 =
      .refuted (Lbl.repro 20) 303 (searchReason 1) := by rfl

/-- **`NP01` is UNCHANGED.**  Satisfiable, and layer (iii) passes it — so the fix costs the
accepted seed nothing. -/
theorem np01_decide_sat : (labelDecide (seedQ npSeed 300).elems 200000 1000000).1 = .sat := by rfl

/-- ... and the LOOP still accepts it with all three layers on.  That the loop's records do
not move is a THEOREM rather than a computation whenever layer (i) is off — `runS_of_flag_off`
— and end to end it is the L2 differential's business (`S2-FIX.md` §B4). -/
theorem np01_loop_accepts_rowSound :
    isSolvedB (runS (seedS0 rsFlags npSeed 300) 400) = true := by rfl

end Seeds

end Rowpartition.Loop
