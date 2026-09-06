/-
# S1 (A): OUTPUT SOUNDNESS — the loop loses nothing, at EVERY dispatch branch

`Loop/StrictStep.lean`'s `step_noLoss` covers four of the five branches (`common`, `empty`,
`unify`, `learn`) under `NonConcreteStep`.  This file closes the fifth — `concrete`, the one
that DELETES — and runs the licence along a whole run.

The `concrete` branch dequeues `v <- ((|fs|))`, records that fact in `proc`, and calls
`makeConcrete v fs`, which

* checks with `ensureSuperset` that every definition of `v` still in the queues carries only
  labels of `fs`;
* emits `cancellation v ((|fs|)) r` for each such definition `r`;
* calls `destructiveSub`, which -- WHEN `srs` IS NON-EMPTY, i.e. when something other than
  `v`'s own definitions mentions `v` (`Constraints.scala:1643-1644`, `Loop/Step.lean:175-177`:
  `if ((srs isEmpty) && keep) proc else procd filter p`) -- DELETES every partition that
  mentions `v` (emitting its image under `v := ((|fs|))` in `srs`) and every definition of `v`
  with FEWER THAN TWO abstract parts (`keepDefs` retains the rest).  When `srs` IS empty
  nothing is deleted at all (S1 review Z-4).

Three of those four deletions are licensed, and the fourth is not:

| deleted | what replaces it | entailed? |
|---|---|---|
| `a <- (S, K)`, `v ∈ S` | its image `a <- (S \ v, K ∪ fs)` in `srs`, and `v <- ((|fs|))` | YES |
| `v <- (a, (|K|))`, ONE part | `a <- ((|fs \ K|))` from `cancellation`, and `v <- ((|fs|))` | YES |
| `v <- (S, (|K|))` with `|S| ≥ 2` | nothing: `keepDefs` puts it back | YES, it is still there |
| `v <- ((|C|))` (NO abstract part) | NOTHING (`cancellation_bare`) | **only when `C = fs`** |

and the last line is not a bug in this proof, it is the shipped compiler's behaviour: with
`C ⊆ fs` (which `ensureSuperset` permits -- it is `subsetOf`, `Constraints.scala:312`), `C ≠
fs` and `srs` non-empty, the fact `v <- ((|C|))` is dropped and never re-derived.  That case is
exactly the case in which the system the step starts from has NO MODEL — `bare_refutes` — so
the honest licence is the DISJUNCTION

  `NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)`

which is `step_noLoss_all` below, equivalently `SSat (sys s) → NoLoss (sys s) (sys s')`.
`L5-TERMINATION.md` §C1.5 predicted precisely this ("`concRemove`'s third field will have to
read `SSat G → NoLoss G G'`"); S1 proves it and localises it to the ONE shape.

**AND THE SHAPE IS REACHED (S1 review, 2026-09-05, Z-2).**  `BareAgree` FAILS at a state the
SHIPPED flags reach from a `labelCheckEarly`-passing `buildQueue` input:
`tracker/repro/satterm/seeds/unsat/MIN2.json`, step 9, where `v1` carries both `((|l17,l38|))`
and the `cancellation`-derived `((|l38|))`, `srs` is non-empty, and the row is deleted; the
shipped COMPILER then returns `SOLVED` on that UNSATISFIABLE input at 4 of 20 id bases.  The
theorems below are unaffected — on every one of the 1,166 measured false acceptances the
residual was itself unsatisfiable, so `NoLoss` holds there vacuously — but the informal
reading "an accepted program is well-typed" is a refutation-COMPLETENESS claim the loop does
not have, and MIN2 is a counterexample to it.
-/
import Rowpartition.Loop.StrictStep
import Rowpartition.Loop.Supply

namespace Rowpartition.Loop

open Rowpartition

set_option linter.unusedSimpArgs false

/-! ## 1. `SVal`-quotient membership

`Loop/StrictStep.lean` proves "a `Set` operation keeps every CONSTRAINT it was given" for
`SSet LPart` (`toConstraint_mem_foldl_incl` and friends).  `makeConcrete` builds an
`SSet RHS` — its `rhss` — so the same three lemmas are needed one type up.  They are stated
once, for an arbitrary value function `φ` that is constant on `SVal.eq`-classes of the
elements a predicate `Q` admits; the `LPart` instances are `StrictStep`'s. -/

section Val

variable {α β : Type} [SVal α] {Q : α → Prop} {φ : α → β}

/-- A fold of `Set + x` keeps every value of `φ`, from the seed or from the list. -/
theorem val_mem_foldl_incl (hφ : ∀ x y : α, Q x → Q y → SVal.eq x y = true → φ x = φ y) :
    ∀ (ys : List α) {a : SSet α}, (∀ z ∈ a.elems, Q z) → (∀ y ∈ ys, Q y) →
      ∀ {x : α}, Q x → (x ∈ a.elems ∨ x ∈ ys) →
        ∃ z ∈ (ys.foldl SSet.incl a).elems, φ z = φ x := by
  intro ys
  induction ys with
  | nil =>
    intro a _ _ x _ hx
    rcases hx with hx' | hx'
    · exact ⟨x, hx', rfl⟩
    · exact absurd hx' (by simp)
  | cons y ys ih =>
    intro a haQ hys x hxQ hx
    have haQ' : ∀ z ∈ (a.incl y).elems, Q z := by
      intro z hz
      rcases SSet.mem_incl hz with hz' | hzy
      · exact haQ z hz'
      · exact hzy ▸ hys y (by simp)
    have hys' : ∀ z ∈ ys, Q z := fun z hz => hys z (by simp [hz])
    rcases hx with hx' | hx'
    · exact ih haQ' hys' hxQ (Or.inl (mem_incl_of_mem hx'))
    · rcases List.mem_cons.mp hx' with rfl | hx''
      · rcases mem_incl_new a x with hnew | ⟨z, hz, hzeq⟩
        · exact ih haQ' hys' hxQ (Or.inl hnew)
        · obtain ⟨w, hw, hweq⟩ := ih haQ' hys' (haQ z hz) (Or.inl (mem_incl_of_mem hz))
          exact ⟨w, hw, hweq.trans (hφ x z hxQ (haQ z hz) hzeq).symm⟩
      · exact ih haQ' hys' hxQ (Or.inr hx'')

/-- `Set.map` keeps every image's value. -/
theorem val_mem_map {γ : Type} [SVal γ]
    (hφ : ∀ x y : α, Q x → Q y → SVal.eq x y = true → φ x = φ y)
    {s : SSet γ} {f : γ → α} (hf : ∀ w ∈ s.elems, Q (f w)) {w : γ} (hw : w ∈ s.elems) :
    ∃ z ∈ (s.map f).elems, φ z = φ (f w) := by
  have hmap : (s.map f).elems
      = ((s.elems.map f).foldl SSet.incl (⟨s.hashed, []⟩ : SSet α)).elems := by
    unfold SSet.map
    rw [List.foldl_map]
  rw [hmap]
  refine val_mem_foldl_incl hφ (s.elems.map f) (by intro z hz; exact absurd hz (by simp)) ?_
    (hf w hw) (Or.inr (List.mem_map.mpr ⟨w, hw, rfl⟩))
  intro z hz
  obtain ⟨u, hu, rfl⟩ := List.mem_map.mp hz
  exact hf u hu

/-- `Set ++ Set` keeps every value of BOTH operands. -/
theorem val_mem_concat (hφ : ∀ x y : α, Q x → Q y → SVal.eq x y = true → φ x = φ y)
    {s t : SSet α} (hs : ∀ z ∈ s.elems, Q z) (ht : ∀ z ∈ t.elems, Q z)
    {x : α} (hx : x ∈ s.elems ∨ x ∈ t.elems) :
    ∃ z ∈ (s.concat t).elems, φ z = φ x := by
  have hxQ : Q x := by
    cases hx with
    | inl h => exact hs x h
    | inr h => exact ht x h
  unfold SSet.concat
  split
  · have hrep : ∀ y : α, y ∈ s.elems ++ t.elems →
        φ (SSet.pickRep s.elems t.elems y) = φ y := by
      intro y hy
      have hyQ : Q y := by
        rcases List.mem_append.mp hy with hy' | hy'
        · exact hs y hy'
        · exact ht y hy'
      unfold SSet.pickRep
      split
      · rfl
      · rename_i sy hf
        have hsyQ : Q sy := hs sy (List.mem_of_find?_eq_some hf)
        have hsyeq : SVal.eq sy y = true := by
          have h0 := List.find?_some hf
          simpa using h0
        split
        · rfl
        · exact hφ sy y hsyQ hyQ hsyeq
    have hgo : ∀ y : α, y ∈ s.elems ++ t.elems →
        y ∈ SSet.champ ((s.elems.filter (fun w => !t.contains w)) ++ t.elems) →
        ∃ z ∈ (List.map (SSet.pickRep s.elems t.elems)
          (SSet.champ ((s.elems.filter (fun w => !t.contains w)) ++ t.elems))),
          φ z = φ y :=
      fun y hy hyc => ⟨SSet.pickRep s.elems t.elems y, List.mem_map.mpr ⟨y, hyc, rfl⟩, hrep y hy⟩
    rcases hx with hx' | hx'
    · by_cases hc : t.contains x = true
      · obtain ⟨y, hy, hxy⟩ := List.any_eq_true.mp hc
        obtain ⟨z, hz, hzy⟩ := hgo y (List.mem_append_right _ hy)
          (SSet.mem_champ.mpr (List.mem_append_right _ hy))
        exact ⟨z, hz, hzy.trans (hφ x y hxQ (ht y hy) hxy).symm⟩
      · exact hgo x (List.mem_append_left _ hx')
          (SSet.mem_champ.mpr (List.mem_append_left _
            (List.mem_filter.mpr ⟨hx', by simpa using hc⟩)))
    · exact hgo x (List.mem_append_right _ hx')
        (SSet.mem_champ.mpr (List.mem_append_right _ hx'))
  · exact val_mem_foldl_incl hφ t.elems hs ht hxQ hx

end Val

/-! ## 2. What licenses each of `makeConcrete`'s deletions, semantically

Three lemmas, each of the shape "the constraint the loop DELETED is a consequence of what it
put in its place".  Together with `bare_refutes` — the ONE shape for which no such lemma
holds — they are the whole content of the `concrete` branch's `NoLoss`. -/

/-- A bare concrete row PINS the variable. -/
theorem sat_bare {rho : Assign} {v : Var} {C : Row} (h : Sat rho (mk v ∅ C)) : rho v = C := by
  have := (sat_mk_iff rho v ∅ C).mp h
  simpa using this.1

/-- **`destructiveSub`'s rewritten mention is a licence.**  `a <- (S, K)` with `v ∈ S` is
deleted and `a <- (S \ v, K ∪ fs)` emitted; with the recorded `v <- ((|fs|))` the two entail
what was deleted.  `K ∩ fs = ∅` is `RHS.merge`'s own success condition — it is the case it
dies in otherwise. -/
theorem sat_of_subst_image {rho : Assign} {a v : Var} {S : Finset Var} {K F : Row}
    (hv : v ∈ S) (hdis : Disjoint K F)
    (himg : Sat rho (mk a (S.erase v) (K ∪ F))) (hcon : Sat rho (mk v ∅ F)) :
    Sat rho (mk a S K) := by
  have hrv : rho v = F := sat_bare hcon
  obtain ⟨he, hk, hd⟩ := (sat_mk_iff rho a (S.erase v) (K ∪ F)).mp himg
  have hsplit : S.biUnion rho = rho v ∪ (S.erase v).biUnion rho := by
    conv_lhs => rw [← Finset.insert_erase hv]
    rw [Finset.biUnion_insert]
  refine (sat_mk_iff rho a S K).mpr ⟨?_, ?_, ?_⟩
  · rw [he, hsplit, hrv]
    ext l
    simp only [Finset.mem_union]
    tauto
  · intro w hw
    by_cases hwv : w = v
    · subst hwv; rw [hrv]; exact hdis
    · exact (hk w (Finset.mem_erase.mpr ⟨hwv, hw⟩)).mono_left Finset.subset_union_left
  · have key : ∀ w ∈ S, ∀ x ∈ S, w ≠ x → w = v → Disjoint (rho w) (rho x) := by
      intro w _ x hx hwx hwv
      have hxe : x ∈ S.erase v :=
        Finset.mem_erase.mpr ⟨fun hh => hwx (hwv.trans hh.symm), hx⟩
      rw [hwv, hrv]
      exact (hk x hxe).mono_left Finset.subset_union_right
    intro w hw x hx hwx
    by_cases hwv : w = v
    · exact key w hw x hx hwx hwv
    · by_cases hxv : x = v
      · exact (key x hx w hw (Ne.symm hwx) hxv).symm
      · exact hd w (Finset.mem_erase.mpr ⟨hwv, hw⟩) x (Finset.mem_erase.mpr ⟨hxv, hx⟩) hwx

/-- **`makeConcrete`'s cancellation is a licence.**  `v <- (a, (|K|))` is deleted and
`a <- ((|fs \ K|))` emitted; with `v <- ((|fs|))` the two entail what was deleted.  `K ⊆ fs`
is `ensureSuperset`'s own success condition. -/
theorem sat_of_cancel_image {rho : Assign} {v a : Var} {K F : Row} (hsub : K ⊆ F)
    (hcon : Sat rho (mk v ∅ F)) (himg : Sat rho (mk a ∅ (F \ K))) :
    Sat rho (mk v {a} K) := by
  have hrv : rho v = F := sat_bare hcon
  have hra : rho a = F \ K := sat_bare himg
  refine (sat_mk_iff rho v {a} K).mpr ⟨?_, ?_, ?_⟩
  · rw [hrv, Finset.singleton_biUnion, hra]
    ext l
    simp only [Finset.mem_union, Finset.mem_sdiff]
    constructor
    · intro hl; by_cases hk : l ∈ K
      · exact Or.inl hk
      · exact Or.inr ⟨hl, hk⟩
    · rintro (hl | ⟨hl, -⟩)
      · exact hsub hl
      · exact hl
  · intro w hw
    rw [Finset.mem_singleton] at hw
    subst hw
    rw [hra]
    exact Finset.disjoint_right.mpr (fun l hl => (Finset.mem_sdiff.mp hl).2)
  · intro w hw x hx hwx
    rw [Finset.mem_singleton] at hw hx
    exact absurd (hw.trans hx.symm) hwx

/-- **The ONE deletion that is not licensed**, and the reason it costs nothing: a variable
with two DIFFERENT bare concrete rows has no model at all.  `makeConcrete v fs` deletes
`v <- ((|C|))` for every `C ⊆ fs`, and emits nothing in its place (`cancellation_bare`); when
`C ≠ fs` the system it deleted it from was already unsatisfiable. -/
theorem bare_refutes {G : System} {v : Var} {C F : Row}
    (h1 : mk v ∅ C ∈ G) (h2 : mk v ∅ F ∈ G) (hne : C ≠ F) : ¬ SSat G := by
  rintro ⟨rho, hm⟩
  exact hne ((sat_bare (hm _ h1)).symm.trans (sat_bare (hm _ h2)))

/-! ## 3. `subPartitions` REWRITES every mention of `v`, it does not just delete it -/

/-- The accumulator of a derivation fold only grows, up to the constraint a partition
denotes: `SSet.incl` and `SSet.concat` may replace a partition by an `equals`-equal one. -/
def Keeps (A B : SSet LPart) : Prop :=
  ∀ y ∈ A.elems, ∃ z ∈ B.elems, z.toConstraint = y.toConstraint

theorem Keeps.refl (A : SSet LPart) : Keeps A A := fun y hy => ⟨y, hy, rfl⟩

theorem Keeps.trans {A B C : SSet LPart} (h1 : Keeps A B) (h2 : Keeps B C) : Keeps A C := by
  intro y hy
  obtain ⟨z, hz, hzy⟩ := h1 y hy
  obtain ⟨w, hw, hwz⟩ := h2 z hz
  exact ⟨w, hw, hwz.trans hzy⟩

/-- **Every partition of either queue that MENTIONS `v` leaves its image in `srs`.**  This is
the converse of `subPartitions_run`: that one says everything `subPartitions` derives is
sound, this one says nothing it should derive is missing. -/
theorem subPartitions_mem {L : List Lbl} (hcoh : LblCoh L) {v : Nat} {sub : RHS}
    {proc incm : PQueue} {S : SSet LPart}
    (hsubOk : ROk L sub) (hpOk : QOk L proc) (hiOk : QOk L incm)
    (h : subPartitions v sub proc incm = .ok S) :
    ∀ x, (x ∈ proc.elems ∨ (x ∈ incm.elems ∧ x.lhs ≠ v)) → x.rhs.contains v = true →
      ∃ nrhs es, rhsSubstitute x.rhs v sub = .ok (nrhs, es) ∧
        ∃ z ∈ S.elems, z.toConstraint = (⟨x.lhs, nrhs, x.inf⟩ : LPart).toConstraint := by
  simp only [subPartitions] at h
  set F : Except String (SSet LPart) → LPart → Except String (SSet LPart) := fun acc r => do
    let s ← acc
    if r.rhs.contains v then
      let (nrhs, es) ← rhsSubstitute r.rhs v sub
      let s := s.concat (es.map (fun w => (⟨w, RHS.empty, some .deDuplication⟩ : LPart)))
      pure (s.incl ⟨r.lhs, nrhs, r.inf⟩)
    else pure s with hF
  set C : LPart → SSet LPart → Prop := fun x T =>
    x.rhs.contains v = true → ∃ nrhs es, rhsSubstitute x.rhs v sub = .ok (nrhs, es) ∧
      ∃ z ∈ T.elems, z.toConstraint = (⟨x.lhs, nrhs, x.inf⟩ : LPart).toConstraint with hC
  have herr : ∀ (m : String) (x : LPart), F (.error m) x = .error m := by
    intro m x; rw [hF]; simp only [bind, Except.bind]
  have hmonoC : ∀ {x : LPart} {a b : SSet LPart}, SOk L a → SOk L b → Keeps a b →
      C x a → C x b := by
    intro x a b _ _ hk hCa hcv
    obtain ⟨nrhs, es, hrs, z, hz, hzc⟩ := hCa hcv
    obtain ⟨w, hw, hwz⟩ := hk z hz
    exact ⟨nrhs, es, hrs, w, hw, hwz.trans hzc⟩
  have hstep : ∀ {a : SSet LPart} {x : LPart} {b : SSet LPart}, POk L x → SOk L a →
      F (.ok a) x = .ok b → SOk L b ∧ Keeps a b ∧ C x b := by
    intro a x b hx ha hb
    rw [hF] at hb
    simp only [bind, Except.bind] at hb
    split at hb
    · rename_i hcv
      cases hrs : rhsSubstitute x.rhs v sub with
      | error m =>
        rw [hrs] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok w =>
        obtain ⟨nrhs, es⟩ := w
        rw [hrs] at hb
        simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
        subst hb
        have hdupOk : SOk L (es.map (fun w => (⟨w, RHS.empty, some Inference.deDuplication⟩
            : LPart))) := SOk.map (fun _ => POk.ofEmpty _ _)
        have hcatOk : SOk L (a.concat _) := ha.concat hdupOk
        have hnewOk : POk L (⟨x.lhs, nrhs, x.inf⟩ : LPart) :=
          ROk.part (rhsSubstitute_ok hx.rhsOk hsubOk hrs) _ _
        refine ⟨SOk.incl hcatOk hnewOk, ?_, ?_⟩
        · intro y hy
          obtain ⟨z, hz, hzy⟩ := toConstraint_mem_concat hcoh ha hdupOk (Or.inl hy)
          exact ⟨z, mem_incl_of_mem hz, hzy⟩
        · intro _
          refine ⟨nrhs, es, hrs, ?_⟩
          rcases mem_incl_new (a.concat _) (⟨x.lhs, nrhs, x.inf⟩ : LPart) with hnew | ⟨z, hz, hze⟩
          · exact ⟨_, hnew, rfl⟩
          · exact ⟨z, mem_incl_of_mem hz,
              (eqv_toConstraint hcoh hnewOk (hcatOk z hz) (by rwa [← svalEq_lpart])).symm⟩
    · rename_i hcv
      simp only [pure, Except.pure, Except.ok.injEq] at hb
      subst hb
      exact ⟨ha, Keeps.refl a, fun hh => absurd hh hcv⟩
  cases hinner : proc.elems.foldl F (.ok SSet.empty) with
  | error m => rw [hinner, foldl_except_error herr _ m] at h; exact absurd h (by simp)
  | ok A0 =>
    rw [hinner] at h
    obtain ⟨hA0Ok, -, hcov0⟩ := foldl_except_covers (le := Keeps) (C := C) (P := SOk L)
      (Q := POk L) Keeps.refl (fun _ _ h1 h2 => h1.trans h2) hmonoC hstep herr
      proc.elems hpOk SOk.empty hinner
    obtain ⟨hSOk, hkeep1, hcov1⟩ := foldl_except_covers (le := Keeps) (C := C) (P := SOk L)
      (Q := POk L) Keeps.refl (fun _ _ h1 h2 => h1.trans h2) hmonoC hstep herr
      (incm.filter (fun p => p.lhs != v)).elems
      (fun x hx => hiOk x (List.mem_of_mem_filter hx)) hA0Ok h
    intro x hx hcv
    rcases hx with hx' | ⟨hx', hne⟩
    · exact hmonoC hA0Ok hSOk hkeep1 (hcov0 x hx') hcv
    · exact hcov1 x (List.mem_filter.mpr ⟨hx', by simpa using hne⟩) hcv

/-! ## 4. The two licensed rewrites, read back at the loop's own terms -/

/-- **The image `subPartitions` derives at a CONCRETE substitution licenses the deletion.**
`x = a <- (S, K)` with `v ∈ S` is deleted; `rhsSubstitute` returns `a <- (S \ v, K ∪ fs)`, and
that plus `v <- ((|fs|))` entails `x`.  `rhsMerge`'s success is what gives `K ∩ fs = ∅`. -/
theorem sub_image_noLoss {L : List Lbl} (hcoh : LblCoh L) {G' : System} {v : Nat}
    {fs : SSet Lbl} {x : LPart} {nrhs : RHS} {es : SSet Nat} {i : Option Inference}
    (hxOk : POk L x) (hfsOk : COk L fs)
    (hcv : x.rhs.contains v = true)
    (hrs : rhsSubstitute x.rhs v (RHS.ofConcr fs) = .ok (nrhs, es))
    (himg : SEntails G' (⟨x.lhs, nrhs, i⟩ : LPart).toConstraint)
    (hcon : SEntails G' (mk v ∅ (cfs fs))) : SEntails G' x.toConstraint := by
  have hvmem : v ∈ x.rhs.abstr.fs := SSet.mem_fs.mpr (contains_nat_iff.mp hcv)
  simp only [rhsSubstitute, rhsMerge] at hrs
  rw [if_pos (show x.rhs.abstr.contains v = true from hcv)] at hrs
  split at hrs
  · rename_i hcint
    rw [Except.ok.injEq, Prod.mk.injEq] at hrs
    obtain ⟨rfl, -⟩ := hrs
    have hdis : Disjoint (cfs x.rhs.conc) (cfs fs) := by
      have h0 : cfs ((x.rhs.erase v).conc.inter (RHS.ofConcr fs).conc) = ∅ :=
        cfs_eq_empty_iff.mp hcint
      rw [cfs_inter hcoh (s := (x.rhs.erase v).conc) (t := (RHS.ofConcr fs).conc)
        (fun y hy => hxOk.conc.sub y hy) (fun y hy => hfsOk.sub y hy)] at h0
      exact Finset.disjoint_iff_inter_eq_empty.mpr h0
    have hshape : (⟨x.lhs, (⟨((x.rhs.erase v).abstr.concat (RHS.ofConcr fs).abstr).removedAll
          ((x.rhs.erase v).abstr.inter (RHS.ofConcr fs).abstr),
          (x.rhs.erase v).conc.concat (RHS.ofConcr fs).conc⟩ : RHS), i⟩ : LPart).toConstraint
        = mk x.lhs (x.rhs.abstr.fs.erase v) (cfs x.rhs.conc ∪ cfs fs) := by
      rw [toConstraint_eq]
      congr 1
      · show (((x.rhs.erase v).abstr.concat (RHS.ofConcr fs).abstr).removedAll
          ((x.rhs.erase v).abstr.inter (RHS.ofConcr fs).abstr)).fs = _
        simp [RHS.erase, RHS.ofConcr]
      · show cfs ((x.rhs.erase v).conc.concat (RHS.ofConcr fs).conc) = _
        rw [cfs_concat]
        rfl
    rw [hshape] at himg
    intro rho hm
    rw [toConstraint_eq]
    exact sat_of_subst_image hvmem hdis (himg rho hm) (hcon rho hm)
  · exact absurd hrs (by simp)

/-- **The partition `cancellation` derives licenses the deletion** of a definition of `v` with
exactly ONE abstract part.  `ensureSuperset`'s success is what gives `K ⊆ fs`. -/
theorem cancel_image_noLoss {G' : System} {v y : Nat}
    {fs : SSet Lbl} {r : RHS}
    (hone : r.abstr.elems = [y]) (hsub : r.conc.subsetOf fs = true)
    (himg : SEntails G' (mk y ∅ (cfs fs \ cfs r.conc)))
    (hcon : SEntails G' (mk v ∅ (cfs fs))) :
    SEntails G' (mk v r.abstr.fs (cfs r.conc)) := by
  have hcsub : cfs r.conc ⊆ cfs fs := by
    intro n hn
    obtain ⟨z, hz, rfl⟩ := mem_cfs.mp hn
    have := List.all_eq_true.mp hsub z hz
    obtain ⟨w, hw, hzw⟩ := List.any_eq_true.mp this
    have : z = w := by simpa [SVal.eq] using hzw
    exact mem_cfs.mpr ⟨w, hw, by rw [← this]⟩
  have hfsEq : r.abstr.fs = ({y} : Finset Var) := by
    rw [SSet.fs, hone]; simp
  rw [hfsEq]
  intro rho hm
  exact sat_of_cancel_image hcsub (hcon rho hm) (himg rho hm)

/-! ## 5. A fold of `Set ++ g r` keeps everything -/

/-- Every summand of a `concat` fold survives into the result, up to the constraint. -/
theorem foldl_concat_covers {L : List Lbl} (hcoh : LblCoh L) {γ : Type} {g : γ → SSet LPart}
    {Q : γ → Prop} (hg : ∀ r, Q r → SOk L (g r)) :
    ∀ (rs : List γ), (∀ r ∈ rs, Q r) → ∀ {A : SSet LPart}, SOk L A →
      SOk L (rs.foldl (fun s r => s.concat (g r)) A) ∧
      Keeps A (rs.foldl (fun s r => s.concat (g r)) A) ∧
      ∀ r ∈ rs, Keeps (g r) (rs.foldl (fun s r => s.concat (g r)) A) := by
  intro rs
  induction rs with
  | nil => intro _ A hA; exact ⟨hA, Keeps.refl A, by simp⟩
  | cons r rs ih =>
    intro hQ A hA
    have hA1 : SOk L (A.concat (g r)) := hA.concat (hg r (hQ r (by simp)))
    obtain ⟨hOk, hk, hall⟩ := ih (fun z hz => hQ z (by simp [hz])) hA1
    refine ⟨hOk, ?_, ?_⟩
    · exact Keeps.trans (fun z hz => toConstraint_mem_concat hcoh hA (hg r (hQ r (by simp)))
        (Or.inl hz)) hk
    · intro z hz
      rcases List.mem_cons.mp hz with rfl | hz'
      · exact Keeps.trans (fun w hw => toConstraint_mem_concat hcoh hA
          (hg z (hQ z (by simp))) (Or.inr hw)) hk
      · exact hall z hz'

/-! ## 6. `destructiveSub`, backwards

Everything either survives (possibly rewritten, possibly as an `equals`-equal copy) or is a
definition of `v` with FEWER THAN TWO abstract parts — which is exactly what `makeConcrete`'s
`cancellation` fold is there to cover. -/

theorem destructiveSub_noLoss {L : List Lbl} (hcoh : LblCoh L) {G' : System} {v : Nat}
    {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hiOk : QOk L incm) (hpOk : QOk L proc) (hfsOk : COk L fs)
    (hniG : ∀ x ∈ ni.elems, SEntails G' x.toConstraint)
    (hnpG : ∀ x ∈ np.elems, SEntails G' x.toConstraint)
    (hconG : SEntails G' (mk v ∅ (cfs fs)))
    (h : destructiveSub v (RHS.ofConcr fs) incm proc = .ok (ni, np)) :
    ∀ x ∈ incm.elems ++ proc.elems,
      SEntails G' x.toConstraint ∨ (x.lhs = v ∧ x.rhs.abstr.size < 2) := by
  simp only [destructiveSub] at h
  set pps := (proc.partition (fun p => p.lhs == v)).1 with hpps
  set procd := (proc.partition (fun p => p.lhs == v)).2 with hprocd
  set qps := (incm.partition (fun p => p.lhs == v)).1 with hqps
  set incmg := (incm.partition (fun p => p.lhs == v)).2 with hincmg
  have hppsOk : SOk L pps := hpOk.partition_fst _
  have hqpsOk : SOk L qps := hiOk.partition_fst _
  have hprocdOk : QOk L procd := hpOk.partition_snd _
  have hincmgOk : QOk L incmg := hiOk.partition_snd _
  set F : Except String (SSet LPart) → RHS → Except String (SSet LPart) := fun acc r => do
    let s ← acc
    pure (s.concat (← subPartitions v r procd incmg)) with hF
  have herrF : ∀ (m : String) (r : RHS), F (.error m) r = .error m := by
    intro m r; rw [hF]; simp only [bind, Except.bind]
  have hstepF : ∀ {a : SSet LPart} {x : RHS} {b : SSet LPart}, ROk L x → SOk L a →
      F (.ok a) x = .ok b → SOk L b ∧ Keeps a b ∧ True := by
    intro a x b hx ha hb
    rw [hF] at hb
    simp only [bind, Except.bind] at hb
    cases hsp : subPartitions v x procd incmg with
    | error m => rw [hsp] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
    | ok T =>
      rw [hsp] at hb
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
      subst hb
      have hTOk : SOk L T := subPartitions_ok hx hprocdOk hincmgOk hsp
      exact ⟨ha.concat hTOk, fun z hz => toConstraint_mem_concat hcoh ha hTOk (Or.inl hz),
        trivial⟩
  obtain ⟨srs, hsrs, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨rfl, rfl⟩ := h2
  have hrhsSetQ : ∀ r ∈ ((pps.concat qps).map (fun p => p.rhs)).elems, ROk L r := by
    intro r hr
    obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr
    exact (SOk.concat hppsOk hqpsOk q hq).rhsOk
  cases hbase : subPartitions v (RHS.ofConcr fs) procd incmg with
  | error m => rw [hbase, foldl_except_error herrF _ m] at hsrs; exact absurd hsrs (by simp)
  | ok base =>
    rw [hbase] at hsrs
    have hbaseOk : SOk L base := subPartitions_ok (ROk.ofConcr hfsOk) hprocdOk hincmgOk hbase
    obtain ⟨hsrsOk, hkeepBase, -⟩ := foldl_except_covers (le := Keeps)
      (C := fun (_ : RHS) (_ : SSet LPart) => True) (P := SOk L) (Q := ROk L)
      Keeps.refl (fun _ _ h1 h2 => h1.trans h2) (fun _ _ _ _ => trivial) hstepF herrF
      ((pps.concat qps).map (fun p => p.rhs)).elems hrhsSetQ hbaseOk hsrs
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
    have hnproc0Ok : QOk L nproc0 := by
      rw [hnproc0]; split
      · exact hpOk
      · exact hprocdOk.filter _
    have hnincm0Ok : QOk L nincm0 := by
      rw [hnincm0]; split
      · exact hiOk
      · exact hincmgOk.filter _
    have hnprocOk : QOk L nproc := by
      rw [hnproc]; split
      · exact QOk.concatNP _ _ hnproc0Ok (fun x hx => hppsOk x (SSet.mem_filter hx))
      · exact hnproc0Ok
    have hnincmOk : QOk L nincm := by
      rw [hnincm]; split
      · exact QOk.concatP _ _ hnincm0Ok (fun x hx => hqpsOk x (SSet.mem_filter hx))
      · exact hnincm0Ok
    have hnprocG : ∀ x ∈ nproc.elems, SEntails G' x.toConstraint := hnpG
    have hnincmG : ∀ x ∈ nincm.elems, SEntails G' x.toConstraint :=
      fun x hx => hniG x (mem_concatP_of_mem _ hx)
    have htrimG : ∀ x ∈ (trim srs nproc).elems, SEntails G' x.toConstraint :=
      concatP_noLoss hcoh _ hnincmOk (fun x hx => (SOk.trim hsrsOk) x hx) hniG
    have hsrsG : ∀ p ∈ srs.elems, SEntails G' p.toConstraint :=
      trim_noLoss hcoh hnprocOk hsrsOk hnprocG htrimG
    have hbaseG : ∀ p ∈ base.elems, SEntails G' p.toConstraint := by
      intro p hp
      obtain ⟨z, hz, hzp⟩ := hkeepBase p hp
      exact hzp ▸ hsrsG z hz
    -- the definitions `keepDefs` puts back
    have hkeptP : cond = false → ∀ p ∈ (pps.filter (fun b => decide (b.rhs.abstr.size ≥ 2))).elems,
        SEntails G' p.toConstraint := by
      intro hcf p hp
      have hg : ∀ x ∈ (nproc0.concatNP
          (pps.filter (fun b => decide (b.rhs.abstr.size ≥ 2))).elems).elems,
          SEntails G' x.toConstraint := by
        intro x hx
        exact hnprocG x (by rw [hnproc, if_pos (by simp [hcf])]; exact hx)
      exact concatNP_noLoss hcoh _ hnproc0Ok (fun x hx => hppsOk x (SSet.mem_filter hx)) hg p hp
    have hkeptI : cond = false → ∀ p ∈ (qps.filter (fun b => decide (b.rhs.abstr.size ≥ 2))).elems,
        SEntails G' p.toConstraint := by
      intro hcf p hp
      have hg : ∀ x ∈ (nincm0.concatP
          (qps.filter (fun b => decide (b.rhs.abstr.size ≥ 2))).elems).elems,
          SEntails G' x.toConstraint := by
        intro x hx
        exact hnincmG x (by rw [hnincm, if_pos (by simp [hcf])]; exact hx)
      exact concatP_noLoss hcoh _ hnincm0Ok (fun x hx => hqpsOk x (SSet.mem_filter hx)) hg p hp
    -- a definition of `v` in a queue has an `equals`-equal copy in `pps` / `qps`
    have hppsMem : ∀ p ∈ proc.elems, p.lhs = v →
        ∃ z ∈ pps.elems, z.toConstraint = p.toConstraint := by
      intro p hp hlv
      rw [hpps]
      simp only [PQueue.partition]
      exact toConstraint_mem_ofList hcoh
        (fun y hy => hpOk y (List.mem_of_mem_filter (List.mem_reverse.mp hy)))
        (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hp, by simpa using hlv⟩))
    have hqpsMem : ∀ p ∈ incm.elems, p.lhs = v →
        ∃ z ∈ qps.elems, z.toConstraint = p.toConstraint := by
      intro p hp hlv
      rw [hqps]
      simp only [PQueue.partition]
      exact toConstraint_mem_ofList hcoh
        (fun y hy => hiOk y (List.mem_of_mem_filter (List.mem_reverse.mp hy)))
        (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hp, by simpa using hlv⟩))
    have hsizeEq : ∀ {z p : LPart}, POk L z → POk L p → z.toConstraint = p.toConstraint →
        z.rhs.abstr.size = p.rhs.abstr.size := by
      intro z p hz hp he
      have hfe : z.rhs.abstr.fs = p.rhs.abstr.fs := by
        have := congrArg vset he
        rwa [toConstraint_eq, toConstraint_eq, vset_mk, vset_mk] at this
      rw [size_eq_card hz.abstr, size_eq_card hp.abstr, hfe]
    intro x hx
    rcases List.mem_append.mp hx with hxi | hxp
    · by_cases hlv : x.lhs = v
      · by_cases hsz : x.rhs.abstr.size < 2
        · exact Or.inr ⟨hlv, hsz⟩
        · refine Or.inl ?_
          by_cases hc : cond = true
          · exact hnincmG x (by rw [hnincm, if_neg (by simp [hc]), hnincm0, if_pos hc]; exact hxi)
          · have hcf : cond = false := by simpa using hc
            obtain ⟨z, hz, hzx⟩ := hqpsMem x hxi hlv
            have hzsz : z.rhs.abstr.size ≥ 2 := by
              rw [hsizeEq (hqpsOk z hz) (hiOk x hxi) hzx]; omega
            exact hzx ▸ hkeptI hcf z (SSet.mem_filter_iff.mpr ⟨hz, by simpa using hzsz⟩)
      · have hxg : x ∈ incmg.elems := by
          rw [hincmg]
          simp only [PQueue.partition]
          exact List.mem_filter.mpr ⟨hxi, by simpa using hlv⟩
        by_cases hcv : x.rhs.contains v = true
        · refine Or.inl ?_
          obtain ⟨nrhs, es, hrs, z, hz, hzc⟩ :=
            subPartitions_mem hcoh (ROk.ofConcr hfsOk) hprocdOk hincmgOk hbase x
              (Or.inr ⟨hxg, hlv⟩) hcv
          exact sub_image_noLoss hcoh (hiOk x hxi) hfsOk hcv hrs (hzc ▸ hbaseG z hz) hconG
        · refine Or.inl (hnincmG x ?_)
          by_cases hc : cond = true
          · rw [hnincm, if_neg (by simp [hc]), hnincm0, if_pos hc]; exact hxi
          · have hcf : cond = false := by simpa using hc
            rw [hnincm, if_pos (by simp [hcf])]
            refine mem_concatP_of_mem _ ?_
            rw [hnincm0, if_neg (by simp [hcf])]
            simp only [PQueue.filter]
            exact List.mem_filter.mpr ⟨hxg, by simp [hlv, hcv]⟩
    · by_cases hlv : x.lhs = v
      · by_cases hsz : x.rhs.abstr.size < 2
        · exact Or.inr ⟨hlv, hsz⟩
        · refine Or.inl ?_
          by_cases hc : cond = true
          · exact hnprocG x (by rw [hnproc, if_neg (by simp [hc]), hnproc0, if_pos hc]; exact hxp)
          · have hcf : cond = false := by simpa using hc
            obtain ⟨z, hz, hzx⟩ := hppsMem x hxp hlv
            have hzsz : z.rhs.abstr.size ≥ 2 := by
              rw [hsizeEq (hppsOk z hz) (hpOk x hxp) hzx]; omega
            exact hzx ▸ hkeptP hcf z (SSet.mem_filter_iff.mpr ⟨hz, by simpa using hzsz⟩)
      · have hxg : x ∈ procd.elems := by
          rw [hprocd]
          simp only [PQueue.partition]
          exact List.mem_filter.mpr ⟨hxp, by simpa using hlv⟩
        by_cases hcv : x.rhs.contains v = true
        · refine Or.inl ?_
          obtain ⟨nrhs, es, hrs, z, hz, hzc⟩ :=
            subPartitions_mem hcoh (ROk.ofConcr hfsOk) hprocdOk hincmgOk hbase x
              (Or.inl hxg) hcv
          exact sub_image_noLoss hcoh (hpOk x hxp) hfsOk hcv hrs (hzc ▸ hbaseG z hz) hconG
        · refine Or.inl (hnprocG x ?_)
          by_cases hc : cond = true
          · rw [hnproc, if_neg (by simp [hc]), hnproc0, if_pos hc]; exact hxp
          · have hcf : cond = false := by simpa using hc
            rw [hnproc, if_pos (by simp [hcf])]
            refine mem_concatNP_of_mem _ ?_
            rw [hnproc0, if_neg (by simp [hcf])]
            simp only [PQueue.filter]
            exact List.mem_filter.mpr ⟨hxg, by simp [hlv, hcv]⟩

/-! ## 7. `makeConcrete`, backwards -/

/-- `ensureSuperset` really is checked at EVERY definition of `v`. -/
theorem ensureSuperset_fold_all {fs : SSet Lbl} :
    ∀ (rs : List RHS) {u : Unit},
      rs.foldl (fun (acc : Except String Unit) (r : RHS) => do
        let _ ← acc; ensureSuperset r.conc fs) (.ok ()) = .ok u →
      ∀ r ∈ rs, r.conc.subsetOf fs = true := by
  intro rs u h
  have hstep : ∀ {a : Unit} {x : RHS} {b : Unit}, True → True →
      (do let _ ← (Except.ok a : Except String Unit); ensureSuperset x.conc fs) = .ok b →
      True ∧ True ∧ x.conc.subsetOf fs = true := by
    intro a x b _ _ hb
    simp only [bind, Except.bind, ensureSuperset] at hb
    split at hb
    · exact ⟨trivial, trivial, by assumption⟩
    · exact absurd hb (by simp)
  exact (foldl_except_covers (le := fun (_ _ : Unit) => True)
    (C := fun (r : RHS) (_ : Unit) => r.conc.subsetOf fs = true) (P := fun (_ : Unit) => True)
    (Q := fun (_ : RHS) => True) (fun _ => trivial) (fun _ _ _ _ => trivial)
    (fun _ _ _ hC => hC) hstep (by intro m x; simp only [bind, Except.bind]) rs
    (fun _ _ => trivial) trivial h).2.2

/-- **`cancellation` fires at a definition of `v` with exactly ONE abstract part**, and what it
emits is `y <- ((|fs \ K|))`.  The first branch cannot fire (a bare concrete row has no
variable part at all), which is why the NO-abstract-part case emits nothing
(`StrictStep.cancellation_bare`). -/
theorem cancellation_singleton {L : List Lbl} (hcoh : LblCoh L) {v y : Nat} {fs : SSet Lbl}
    {r : RHS} (hrOk : ROk L r) (hfsOk : COk L fs)
    (hone : r.abstr.elems = [y]) (hsub : r.conc.subsetOf fs = true) :
    ∃ z ∈ (cancellation v (RHS.ofConcr fs) r).elems,
      z.toConstraint = mk y ∅ (cfs fs \ cfs r.conc) := by
  have hcsub : cfs r.conc ⊆ cfs fs := by
    intro n hn
    obtain ⟨z, hz, rfl⟩ := mem_cfs.mp hn
    obtain ⟨w, hw, hzw⟩ := List.any_eq_true.mp (List.all_eq_true.mp hsub z hz)
    have hzeq : z = w := by simpa [SVal.eq] using hzw
    exact mem_cfs.mpr ⟨w, hw, by rw [← hzeq]⟩
  have hxs : ((RHS.ofConcr fs).abstr.removedAll
      ((RHS.ofConcr fs).abstr.inter r.abstr)).elems = [] := rfl
  have hys : (r.abstr.removedAll ((RHS.ofConcr fs).abstr.inter r.abstr)).elems
      = r.abstr.elems := rfl
  have hyseq : (r.abstr.removedAll ((RHS.ofConcr fs).abstr.inter r.abstr)).elems = [y] := by
    rw [hys]; exact hone
  have hgs0 : (r.conc.removedAll (fs.inter r.conc)).isEmpty = true := by
    refine cfs_eq_empty_iff.mpr ?_
    rw [cfs_removedAll hcoh (fun x hx => hrOk.conc.sub x hx)
        (fun x hx => hfsOk.sub x (SSet.mem_inter hx)),
      cfs_inter hcoh (fun x hx => hfsOk.sub x hx) (fun x hx => hrOk.conc.sub x hx)]
    exact Finset.sdiff_eq_empty_iff_subset.mpr (Finset.subset_inter hcsub (Finset.Subset.refl _))
  have hgs : (r.conc.removedAll ((RHS.ofConcr fs).conc.inter r.conc)).isEmpty = true := hgs0
  have hb1 : ¬ ((((RHS.ofConcr fs).conc.removedAll
        ((RHS.ofConcr fs).conc.inter r.conc)).isEmpty &&
      ((RHS.ofConcr fs).abstr.removedAll
        ((RHS.ofConcr fs).abstr.inter r.abstr)).size == 1) = true) := by
    intro hb
    rw [Bool.and_eq_true] at hb
    have hsz := hb.2
    rw [SSet.size, hxs] at hsz
    exact absurd hsz (by simp)
  have hb2 : ((r.conc.removedAll ((RHS.ofConcr fs).conc.inter r.conc)).isEmpty &&
      (r.abstr.removedAll ((RHS.ofConcr fs).abstr.inter r.abstr)).size == 1) = true := by
    rw [Bool.and_eq_true]
    refine ⟨hgs, ?_⟩
    rw [SSet.size, hyseq]
    rfl
  have e1 : ((SSet.empty.removedAll (SSet.empty.inter r.abstr)) : SSet Nat).fs
      = (∅ : Finset Var) := rfl
  have e2 : cfs (fs.removedAll (fs.inter r.conc)) = cfs fs \ cfs r.conc := by
    rw [cfs_removedAll hcoh (fun x hx => hfsOk.sub x hx)
        (fun x hx => hfsOk.sub x (SSet.mem_inter hx)),
      cfs_inter hcoh (fun x hx => hfsOk.sub x hx) (fun x hx => hrOk.conc.sub x hx)]
    ext n
    simp only [Finset.mem_sdiff, Finset.mem_inter]
    tauto
  simp only [cancellation]
  rw [if_neg hb1, if_pos hb2, hyseq]
  refine ⟨_, by rw [ofList_singleton]; exact List.mem_singleton_self _, ?_⟩
  show mk y ((SSet.empty.removedAll (SSet.empty.inter r.abstr) : SSet Nat)).fs
      (cfs (fs.removedAll (fs.inter r.conc))) = mk y ∅ (cfs fs \ cfs r.conc)
  rw [e1, e2]

/-- **`makeConcrete` loses nothing**, provided every BARE concrete definition of `v` still in
the queues records the row `fs` itself.  That proviso is `bare_refutes`' hypothesis negated:
`makeConcrete` deletes `v <- ((|C|))` and puts nothing in its place, so with `C ≠ fs` it is a
real loss — and then the system it was deleted from had no model. -/
theorem makeConcrete_noLoss {L : List Lbl} (hcoh : LblCoh L) {G' : System} {v : Nat}
    {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hiOk : QOk L incm) (hpOk : QOk L proc) (hfsOk : COk L fs)
    (hniG : ∀ x ∈ ni.elems, SEntails G' x.toConstraint)
    (hnpG : ∀ x ∈ np.elems, SEntails G' x.toConstraint)
    (hbare : ∀ x ∈ incm.elems ++ proc.elems, x.lhs = v → x.rhs.abstr.isEmpty = true →
      cfs x.rhs.conc = cfs fs)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∀ x ∈ incm.elems ++ proc.elems, SEntails G' x.toConstraint := by
  simp only [makeConcrete] at h
  set A := ((SSet.ofList proc.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs) with hA
  set B := ((SSet.ofList incm.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs) with hB
  set rhss := A.concat B with hrhss
  have hAQ : ∀ z ∈ A.elems, ROk L z := by
    intro z hz
    obtain ⟨q, hq, rfl⟩ := SSet.mem_map hz
    exact (hpOk q (SSet.mem_ofList (SSet.mem_filter hq))).rhsOk
  have hBQ : ∀ z ∈ B.elems, ROk L z := by
    intro z hz
    obtain ⟨q, hq, rfl⟩ := SSet.mem_map hz
    exact (hiOk q (SSet.mem_ofList (SSet.mem_filter hq))).rhsOk
  have hrhssOk : ∀ r ∈ rhss.elems, ROk L r := by
    intro r hr
    rcases SSet.mem_concat hr with hr' | hr'
    · exact hAQ r hr'
    · exact hBQ r hr'
  set can := rhss.elems.foldl
    (fun (s : SSet LPart) (r : RHS) => s.concat (cancellation v (RHS.ofConcr fs) r))
    SSet.empty with hcanDef
  have hcanOk : SOk L can :=
    foldl_inv (P := SOk L) (Q := ROk L)
      (fun s r hr hs => hs.concat (cancellation_ok (ROk.ofConcr hfsOk) hr)) _ hrhssOk _ SOk.empty
  obtain ⟨hcanOk', -, hcanCovers⟩ := foldl_concat_covers hcoh
    (g := fun r => cancellation v (RHS.ofConcr fs) r) (Q := ROk L)
    (fun r hr => cancellation_ok (ROk.ofConcr hfsOk) hr) rhss.elems hrhssOk SOk.empty
  obtain ⟨u1, hu1, h2⟩ := except_bind_ok h
  have hsup := ensureSuperset_fold_all rhss.elems hu1
  cases hds : destructiveSub v (RHS.ofConcr fs) incm proc with
  | error m => rw [hds] at h2; simp only [bind, Except.bind] at h2; exact absurd h2 (by simp)
  | ok w =>
    obtain ⟨dsi, dsp⟩ := w
    rw [hds] at h2
    simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    obtain ⟨hdsiOk, hdspOk⟩ := destructiveSub_ok (ROk.ofConcr hfsOk) hiOk hpOk hds
    have hkeyOk : POk L (⟨v, RHS.ofConcr fs, none⟩ : LPart) := ROk.part (ROk.ofConcr hfsOk) _ _
    have hkeyCon : (⟨v, RHS.ofConcr fs, none⟩ : LPart).toConstraint = mk v ∅ (cfs fs) := rfl
    have hdsiG : ∀ x ∈ dsi.elems, SEntails G' x.toConstraint :=
      fun x hx => hniG x (mem_concatP_of_mem _ hx)
    have hdspG : ∀ x ∈ dsp.elems, SEntails G' x.toConstraint :=
      fun x hx => hnpG x (mem_insertNP_of_mem hx)
    have hconG : SEntails G' (mk v ∅ (cfs fs)) := by
      rw [← hkeyCon]
      exact insertNP_noLoss hcoh hdspOk hkeyOk hnpG
    have hcanG : ∀ z ∈ can.elems, SEntails G' z.toConstraint :=
      concatP_noLoss hcoh can.elems hdsiOk hcanOk hniG
    have hφ : ∀ r r' : RHS, ROk L r → ROk L r' → SVal.eq r r' = true →
        mk v r.abstr.fs (cfs r.conc) = mk v r'.abstr.fs (cfs r'.conc) := by
      intro r r' hr hr' he
      have hh := eqv_toConstraint hcoh (ROk.part hr v none) (ROk.part hr' v none)
        (by simp only [LPart.eqv, beq_self_eq_true, Bool.true_and]; exact he)
      simpa only [toConstraint_eq] using hh
    have hBR : ∀ p, (p ∈ proc.elems ∨ p ∈ incm.elems) → p.lhs = v →
        ∃ r ∈ rhss.elems, mk v r.abstr.fs (cfs r.conc) = p.toConstraint := by
      intro p hp hlv
      have hkey : ∀ (q : PQueue), QOk L q → p ∈ q.elems →
          ∃ z ∈ (((SSet.ofList q.elems).filter (fun w => w.lhs == v)).map
            (fun w => w.rhs)).elems,
            mk v z.abstr.fs (cfs z.conc) = p.toConstraint := by
        intro q hqOk hpq
        obtain ⟨z, hz, hzp⟩ := toConstraint_mem_ofList hcoh hqOk hpq
        have hzOk : POk L z := hqOk z (SSet.mem_ofList hz)
        have hzlhs : z.lhs = v := by
          have := congrArg Constraint.lhs hzp
          rwa [toConstraint_eq, toConstraint_eq, lhs_mk, lhs_mk, hlv] at this
        have hzf : z ∈ ((SSet.ofList q.elems).filter (fun w => w.lhs == v)).elems :=
          SSet.mem_filter_iff.mpr ⟨hz, by simpa using hzlhs⟩
        obtain ⟨r, hr, hrz⟩ := val_mem_map (Q := ROk L)
          (φ := fun (r : RHS) => mk v r.abstr.fs (cfs r.conc)) hφ
          (f := fun (w : LPart) => w.rhs)
          (fun w hw => (hqOk w (SSet.mem_ofList (SSet.mem_filter hw))).rhsOk) hzf
        refine ⟨r, hr, hrz.trans ?_⟩
        rw [← hzp, toConstraint_eq, hzlhs]
      rcases hp with hp' | hp'
      · obtain ⟨r, hr, hrp⟩ := hkey proc hpOk hp'
        obtain ⟨r', hr', hr'r⟩ := val_mem_concat (Q := ROk L)
          (φ := fun (r : RHS) => mk v r.abstr.fs (cfs r.conc)) hφ hAQ hBQ (Or.inl hr)
        exact ⟨r', hr', hr'r.trans hrp⟩
      · obtain ⟨r, hr, hrp⟩ := hkey incm hiOk hp'
        obtain ⟨r', hr', hr'r⟩ := val_mem_concat (Q := ROk L)
          (φ := fun (r : RHS) => mk v r.abstr.fs (cfs r.conc)) hφ hAQ hBQ (Or.inr hr)
        exact ⟨r', hr', hr'r.trans hrp⟩
    intro x hx
    rcases destructiveSub_noLoss hcoh hiOk hpOk hfsOk hdsiG hdspG hconG hds x hx with
      hok | ⟨hlv, hsz⟩
    · exact hok
    · have hxOk : POk L x := by
        rcases List.mem_append.mp hx with hx' | hx'
        · exact hiOk x hx'
        · exact hpOk x hx'
      by_cases hem : x.rhs.abstr.isEmpty = true
      · have hxc : x.toConstraint = mk v ∅ (cfs fs) := by
          rw [abstr_isEmpty_toConstraint hem, hlv, hbare x hx hlv hem]
        rw [hxc]
        exact hconG
      · obtain ⟨r, hr, hrx⟩ := hBR x
          (by rcases List.mem_append.mp hx with h' | h'; exacts [Or.inr h', Or.inl h']) hlv
        have hrOk : ROk L r := hrhssOk r hr
        have hfe : r.abstr.fs = x.rhs.abstr.fs := by
          have := congrArg vset hrx
          rwa [vset_mk, toConstraint_eq, vset_mk] at this
        have hxlen : x.rhs.abstr.elems.length = 1 := by
          have h1 : x.rhs.abstr.elems ≠ [] := by
            intro hh; exact hem (by simp [SSet.isEmpty, hh])
          have h2 : x.rhs.abstr.elems.length ≥ 1 := by
            cases hl : x.rhs.abstr.elems with
            | nil => exact absurd hl h1
            | cons a l => simp [hl]
          have h3 : x.rhs.abstr.size < 2 := hsz
          rw [SSet.size] at h3
          omega
        have hrlen : r.abstr.elems.length = 1 := by
          have := size_eq_card (s := r.abstr) hrOk.abstr
          have h2 := size_eq_card (s := x.rhs.abstr) hxOk.abstr
          rw [SSet.size] at this h2
          rw [this, hfe, ← h2, hxlen]
        obtain ⟨y, hy⟩ : ∃ y, r.abstr.elems = [y] := by
          cases hl : r.abstr.elems with
          | nil => rw [hl] at hrlen; exact absurd hrlen (by simp)
          | cons a l =>
            rw [hl] at hrlen
            simp only [List.length_cons] at hrlen
            have hnil : l = [] := List.eq_nil_of_length_eq_zero (by omega)
            exact ⟨a, by rw [hnil]⟩
        obtain ⟨z, hz, hzc⟩ := cancellation_singleton hcoh hrOk hfsOk hy (hsup r hr)
        obtain ⟨w, hw, hwz⟩ := hcanCovers r hr z hz
        rw [← hrx]
        exact cancel_image_noLoss hy (hsup r hr) (by rw [← hzc, ← hwz]; exact hcanG w hw) hconG

/-- ... and the environment fact the branch RECORDS is a consequence of the output. -/
theorem makeConcrete_records {L : List Lbl} {G' : System} (hcoh : LblCoh L) {v : Nat}
    {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hiOk : QOk L incm) (hpOk : QOk L proc) (hfsOk : COk L fs)
    (hnpG : ∀ x ∈ np.elems, SEntails G' x.toConstraint)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    SEntails G' (mk v ∅ (cfs fs)) := by
  simp only [makeConcrete] at h
  obtain ⟨-, -, h2⟩ := except_bind_ok h
  cases hds : destructiveSub v (RHS.ofConcr fs) incm proc with
  | error m => rw [hds] at h2; simp only [bind, Except.bind] at h2; exact absurd h2 (by simp)
  | ok w =>
    obtain ⟨dsi, dsp⟩ := w
    rw [hds] at h2
    simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, rfl⟩ := h2
    obtain ⟨-, hdspOk⟩ := destructiveSub_ok (ROk.ofConcr hfsOk) hiOk hpOk hds
    have hkeyOk : POk L (⟨v, RHS.ofConcr fs, none⟩ : LPart) := ROk.part (ROk.ofConcr hfsOk) _ _
    have hkeyCon : (⟨v, RHS.ofConcr fs, none⟩ : LPart).toConstraint = mk v ∅ (cfs fs) := rfl
    rw [← hkeyCon]
    exact insertNP_noLoss hcoh hdspOk hkeyOk hnpG

/-! ## 8. The `concrete` branch of `step`, and then every branch

`BareAgree` is the proviso `makeConcrete_noLoss` needs, lifted to a state: at the dequeue of a
BARE CONCRETE partition `v <- ((|fs|))`, every other bare concrete definition of `v` still in
the queues records the same row.  `bareAgree_of_sat` discharges it from satisfiability, which
is the only way it can fail (`bare_refutes`). -/

/-- The `concrete` branch's proviso. -/
def BareAgree (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) → r.rhs.abstr.isEmpty = true →
    ∀ x ∈ rest.elems ++ s.proc.elems, x.lhs = r.lhs → x.rhs.abstr.isEmpty = true →
      cfs x.rhs.conc = cfs r.rhs.conc

/-- **A satisfiable state satisfies the proviso.**  Two bare concrete definitions of one
variable that disagree have no model. -/
theorem bareAgree_of_sat {s : State} (hsat : SSat (sys s)) : BareAgree s := by
  intro r rest hdq habs x hx hlv hxabs
  obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
  have hrG : mk r.lhs ∅ (cfs r.rhs.conc) ∈ sys s := by
    rw [← abstr_isEmpty_toConstraint habs]; exact mem_sys_of_incm hrMem
  have hxG : mk r.lhs ∅ (cfs x.rhs.conc) ∈ sys s := by
    rw [← hlv, ← abstr_isEmpty_toConstraint hxabs]
    rcases List.mem_append.mp hx with hx' | hx'
    · exact mem_sys_of_incm (hrestMem x hx')
    · exact mem_sys_of_proc hx'
  by_contra hne
  exact bare_refutes hxG hrG hne hsat

/-- **`NoLoss` at the `concrete` branch** — the missing fifth branch of `StrictStep.
step_noLoss`, under the proviso. -/
theorem step_noLoss_concrete {s s' : State} (hw : Wf s) (hba : BareAgree s)
    {r : LPart} {rest : PQueue} (hdq : s.incm.dequeue = some (r, rest))
    (hfr : s.proc.findRHS r.rhs = none) (hem : r.rhs.isEmpty = false)
    (habs : r.rhs.abstr.isEmpty = true) (h : step s = .continue s') :
    NoLoss (sys s) (sys s') := by
  obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
  obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
  simp only [step, State.log] at h
  rw [hdq] at h
  dsimp only at h
  rw [hfr] at h
  dsimp only at h
  rw [if_neg (by simp [hem]), if_pos habs] at h
  cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
  | error m => rw [hres] at h; exact absurd h (by simp)
  | ok w =>
    obtain ⟨ni, np⟩ := w
    rw [hres] at h
    simp only [StepResult.continue.injEq] at h
    have hniG : ∀ x ∈ ni.elems, SEntails (sys s') x.toConstraint := by
      intro x hx rho hm
      exact hm _ (by rw [← h]; exact mem_sys_of_incm hx)
    have hnpG : ∀ x ∈ np.elems, SEntails (sys s') x.toConstraint := by
      intro x hx rho hm
      exact hm _ (by rw [← h]; exact mem_sys_of_proc hx)
    have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s' := by
      intro b hb
      rw [← h]
      exact mem_sys_of_env hb
    have hbare : ∀ x ∈ rest.elems ++ s.proc.elems, x.lhs = r.lhs →
        x.rhs.abstr.isEmpty = true → cfs x.rhs.conc = cfs r.rhs.conc :=
      hba r rest hdq habs
    have hall := makeConcrete_noLoss hw.coh hrestOk hw.proc hrOk.conc hniG hnpG hbare hres
    have hkey : SEntails (sys s') (mk r.lhs ∅ (cfs r.rhs.conc)) :=
      makeConcrete_records hw.coh hrestOk hw.proc hrOk.conc hnpG hres
    intro c hc
    rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
    · rcases dequeue_mem_or hdq p hp with hp' | rfl
      · exact hall p (List.mem_append_left _ hp')
      · rw [abstr_isEmpty_toConstraint habs]; exact hkey
    · exact hall p (List.mem_append_right _ hp)
    · exact fun rho hm => hm _ (henvG b hb)

/-- **THE OUTPUT-SOUNDNESS STEP LEMMA, all five branches.**  `StrictStep.step_noLoss` covers
four of them with no proviso; the fifth needs `BareAgree`. -/
theorem step_noLoss_all {s s' : State} (hw : Wf s) (hba : BareAgree s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s') := by
  cases hdq : s.incm.dequeue with
  | none =>
    exfalso
    simp only [step] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    cases hfr : s.proc.findRHS r.rhs with
    | some u => exact (step_strict_common hw hdq hfr h).1.no_loss
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · exact (step_strict_empty hw hdq hfr hem h).1.no_loss
      · by_cases habs : r.rhs.abstr.isEmpty = true
        · exact step_noLoss_concrete hw hba hdq hfr (by simpa using hem) habs h
        · cases hsg : r.rhs.single? with
          | some u => exact (step_strict_unify hw hdq hfr hsg h).1.no_loss
          | none =>
            exact step_learn_noLoss hdq hfr (by simpa using hem) (by simpa using habs) hsg h

/-- ... at a SATISFIABLE state, with no proviso left. -/
theorem step_noLoss_sat {s s' : State} (hw : Wf s) (hsat : SSat (sys s))
    (h : step s = .continue s') : NoLoss (sys s) (sys s') :=
  step_noLoss_all hw (bareAgree_of_sat hsat) h

/-- ... and unconditionally, as a disjunction: either the step loses nothing, or the system it
started from already had no model. -/
theorem step_noLoss_or {s s' : State} (hw : Wf s) (h : step s = .continue s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s) := by
  by_cases hsat : SSat (sys s)
  · exact Or.inl (step_noLoss_sat hw hsat h)
  · exact Or.inr hsat

/-! ## 9. Along a run: OUTPUT SOUNDNESS

The system the loop returns is `sys s'` — the residual partitions of both queues PLUS the
substitution environment read as constraints,

```lean
def EnvVal.toConstraint (v : Nat) : EnvVal → Constraint
  | .emptyRow => mk v ∅ (∅ : Row)
  | .alias u => mk v {u} (∅ : Row)

def Env.sys (e : Env) : System := (e.binds.map (fun p => EnvVal.toConstraint p.1 p.2)).toFinset

def sys (s : State) : System := (s.parts.map LPart.toConstraint).toFinset ∪ s.env.sys
```

so the substitution the type checker goes on to apply IS part of the output system: an
`emptyRow` binding is the constraint `v <- ()` and an `alias` binding is `v <- (u)`. -/

/-- **OUTPUT SOUNDNESS.**  Every fact of the input system is a consequence of the output
system, at every state a run reaches — under the shipped flags, the supply invariant, and
satisfiability of the input (which is what the `concrete` branch's bare-row deletion costs;
see `bare_refutes`). -/
theorem run_noLoss : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → NoLoss (sys s) (sys s')
  | 0, s, _, _, _, _, _, _, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact NoLoss.refl _
  | n + 1, s, hw, hem, hdj, hcse, hb, hsat, s', hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [step_done hst]
        exact NoLoss.refl _
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      refine NoLoss.trans (step_noLoss_sat hw hsat hst) ?_
      refine run_noLoss n (step_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
        (step_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat) s' hres
      · rw [step_flags hst]; exact hem
      · rw [step_flags hst]; exact hdj
      · rw [step_flags hst]; exact hcse

/-- ... as a statement about MODELS: every model of the output system is a model of the
input system. -/
theorem run_models {n : Nat} {s s' : State} (hw : Wf s) (hem : s.flags.emptyRow = false)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false) (hb : RunSupOk n s)
    (hsat : SSat (sys s)) (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s) :=
  fun _ hm => (run_noLoss n hw hem hdj hcse hb hsat s' hres).models hm

/-- ... and with `RefineLearn.run_sat_all`, satisfiability in BOTH directions. -/
theorem run_ssat_iff {n : Nat} {s s' : State} (hw : Wf s) (hem : s.flags.emptyRow = false)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false) (hb : RunSupOk n s)
    (hsat : SSat (sys s)) (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    SSat (sys s) ↔ SSat (sys s') := by
  constructor
  · intro h
    exact run_sat_all n hw hem hdj hcse hb h s' hres
  · rintro ⟨rho, hm⟩
    exact ⟨rho, run_models hw hem hdj hcse hb hsat hres rho hm⟩

/-- ... and the unconditional disjunction: either the whole run loses nothing, or the input
system had no model to begin with. -/
theorem run_noLoss_or {n : Nat} {s s' : State} (hw : Wf s) (hem : s.flags.emptyRow = false)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false) (hb : RunSupOk n s)
    (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s) := by
  by_cases hsat : SSat (sys s)
  · exact Or.inl (run_noLoss n hw hem hdj hcse hb hsat s' hres)
  · exact Or.inr hsat

end Rowpartition.Loop
