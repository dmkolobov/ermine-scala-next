/-
# L5 (C1): `step` refines `LoopStrict`

The four `weaken` sites of `Refine.step_refines` and the one of
`RefineConcrete.step_refines_nonlearn` are discharged here against `LoopStrict`, i.e. WITHOUT
arbitrary deletion.  What each needs is the licence `NoLoss (sys s) (sys s')`: the system the
loop keeps still entails every fact the system it left had.

The licence is earned by three facts about the queue writers, proved once here:

* `insertNP_noLoss` / `insertP_noLoss` / `concatP_noLoss` — `Q.insert` and `Q.+!` LOSE
  NOTHING.  A self-unification `a <- (a)` is dropped and is satisfied by every assignment; a
  partition the queue already holds is dropped and is still there; and `Q.+!`'s
  `CommonPartition` redirect replaces `w <- (S, K)` by `w <- (a)` only when `a <- (S, K)` is
  already in the queue, so the two together entail what was replaced;
* `trim_noLoss` — `trim` refuses exactly what the processed queue already holds.

`SEntails` is the library's own entailment (`Divergence.lean`), and `NoLoss` is
`Loop/Strict.lean`'s.
-/
import Rowpartition.Loop.Strict
import Rowpartition.Loop.RefineLearn

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. Entailment plumbing -/

/-- A self-unification is satisfied by every assignment, which is why `Q.insert` may drop
it. -/
theorem sat_self (rho : Assign) (a : Var) : Sat rho (mk a {a} (∅ : Row)) := by
  rw [sat_mk_iff]
  refine ⟨by simp, fun v _ => by simp, ?_⟩
  intro v hv w hw hvw
  rw [Finset.mem_singleton] at hv hw
  exact absurd (hv.trans hw.symm) hvw

/-- The constraint a self-unification denotes. -/
theorem toConstraint_selfUnification {p : LPart} (h : p.isSelfUnification = true) :
    p.toConstraint = mk p.lhs {p.lhs} (∅ : Row) := by
  unfold LPart.isSelfUnification at h
  cases hs : p.rhs.single? with
  | none => rw [hs] at h; exact absurd h (by simp)
  | some u =>
    rw [hs] at h
    have hu : u = p.lhs := by simpa using h
    subst hu
    unfold RHS.single? at hs
    split at hs
    · rename_i hc
      have hnil : p.rhs.conc.elems = [] := by simpa [SSet.isEmpty] using hc
      have habs : p.rhs.abstr.elems = [p.lhs] := by
        unfold SSet.single? at hs
        split at hs
        · rename_i x hx
          have hxl : x = p.lhs := by simpa using hs
          rw [hx, hxl]
        · exact absurd hs (by simp)
      unfold LPart.toConstraint
      rw [habs, hnil]
      simp
    · exact absurd hs (by simp)

/-- Two `Partition.equals`-equal partitions denote the same constraint. -/
theorem eqv_toConstraint {L : List Lbl} (hcoh : LblCoh L) {p q : LPart}
    (hp : POk L p) (hq : POk L q) (h : p.eqv q = true) : p.toConstraint = q.toConstraint :=
  (LPart.eqv_iff_toConstraint hp.abstr hq.abstr hp.conc.nodup hq.conc.nodup
    (hcoh.mono (by
      intro x hx
      rcases List.mem_append.mp hx with hx' | hx'
      · exact hp.conc.sub x hx'
      · exact hq.conc.sub x hx'))).mp h

/-! ## 2. The queue writers lose nothing

Each is stated against an arbitrary system `G` that ENTAILS everything the writer returns;
membership is the special case, and entailment is what the folds below need. -/

/-- **`Q.insert(process = false)` loses nothing.**  The two branches that do not insert `p`
are: `p` is a self-unification (satisfied by every assignment), or the queue already holds a
partition equal to `p` (whose constraint is the same). -/
theorem insertNP_noLoss {L : List Lbl} (hcoh : LblCoh L) {q : PQueue} {p : LPart}
    {G : System} (hq : QOk L q) (hp : POk L p)
    (hG : ∀ x ∈ (q.insertNP p).elems, SEntails G x.toConstraint) :
    SEntails G p.toConstraint := by
  unfold PQueue.insertNP at hG
  split at hG
  · rename_i hself
    rw [toConstraint_selfUnification hself]
    exact fun rho _ => sat_self rho p.lhs
  · split at hG
    · rename_i hpres
      obtain ⟨x, hx, hxe⟩ := List.any_eq_true.mp hpres
      have hxp : x.toConstraint = p.toConstraint :=
        eqv_toConstraint hcoh (hq x hx) hp (by
          rw [Bool.and_eq_true] at hxe; exact hxe.2)
      exact fun rho hm => hxp ▸ hG x hx rho hm
    · exact hG p (mem_insertSorted_self p q.elems)

/-- **`Q.insert(process = true)` loses nothing.**  Besides the two drops of `insertNP`, the
redirect branch replaces the insertion of `p = w <- (S, K)` by `v <- (w)` for a `v` the queue
already names with the same right-hand side; `renameLhs_sat` reads the two back together. -/
theorem insertP_noLoss {L : List Lbl} (hcoh : LblCoh L) {q : PQueue} {p : LPart}
    {G : System} (hq : QOk L q) (hp : POk L p)
    (hG : ∀ x ∈ (q.insertP p).elems, SEntails G x.toConstraint) :
    SEntails G p.toConstraint := by
  unfold PQueue.insertP at hG
  split at hG
  · rename_i hself
    rw [toConstraint_selfUnification hself]
    exact fun rho _ => sat_self rho p.lhs
  · split at hG
    · rename_i hpres
      obtain ⟨x, hx, hxe⟩ := List.any_eq_true.mp hpres
      have hxp : x.toConstraint = p.toConstraint :=
        eqv_toConstraint hcoh (hq x hx) hp (by
          rw [Bool.and_eq_true] at hxe; exact hxe.2)
      exact fun rho hm => hxp ▸ hG x hx rho hm
    · split at hG
      · rename_i v hv
        obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := rhsLookup_witness hv
        have hc0 : x0.toConstraint = (⟨v, p.rhs, none⟩ : LPart).toConstraint := by
          rw [← hx0lhs]
          exact toConstraint_congr hcoh (hq x0 hx0) hp hx0eq
        have hred : SEntails G (mk v {p.lhs} (∅ : Row)) := by
          have hpok : POk L (⟨v, RHS.ofAbstr (SSet.ofList [p.lhs]), some .commonPartition⟩ :
              LPart) := ⟨SSet.nodup_ofList _, COk.empty⟩
          have hh := insertNP_noLoss hcoh hq hpok hG
          rwa [redirect_toConstraint] at hh
        intro rho hm
        have h1 : Sat rho ((⟨v, p.rhs, none⟩ : LPart).toConstraint) :=
          hc0 ▸ hG x0 (mem_insertNP_of_mem hx0) rho hm
        have h2 : Sat rho (mk v {p.lhs} (∅ : Row)) := hred rho hm
        have hshape : (⟨v, p.rhs, none⟩ : LPart).toConstraint
            = mk v (p.rhs.abstr.elems.toFinset)
                ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
        have hshape2 : p.toConstraint
            = mk p.lhs (p.rhs.abstr.elems.toFinset)
                ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
        rw [hshape] at h1
        rw [hshape2]
        exact renameLhs_sat h1 h2
      · exact hG p (mem_insertSorted_self p q.elems)

/-- **`PQueue.++!` loses nothing.** -/
theorem concatP_noLoss {L : List Lbl} (hcoh : LblCoh L) :
    ∀ (ps : List LPart) {q : PQueue} {G : System}, QOk L q → (∀ p ∈ ps, POk L p) →
      (∀ x ∈ (q.concatP ps).elems, SEntails G x.toConstraint) →
      ∀ p ∈ ps, SEntails G p.toConstraint
  | [], _, _, _, _, _ => by simp
  | p :: ps, q, G, hq, hp, hG => by
    have hGq : ∀ x ∈ (q.insertP p).elems, SEntails G x.toConstraint :=
      fun x hx => hG x (mem_concatP_of_mem ps hx)
    have hhead : SEntails G p.toConstraint :=
      insertP_noLoss hcoh hq (hp p (by simp)) hGq
    have htail := concatP_noLoss hcoh ps (q := q.insertP p) (G := G)
      (QOk.insertP hq (hp p (by simp))) (fun d hd => hp d (by simp [hd])) hG
    intro d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hhead
    · exact htail d hd'

/-- **`PQueue.++` loses nothing.** -/
theorem concatNP_noLoss {L : List Lbl} (hcoh : LblCoh L) :
    ∀ (ps : List LPart) {q : PQueue} {G : System}, QOk L q → (∀ p ∈ ps, POk L p) →
      (∀ x ∈ (q.concatNP ps).elems, SEntails G x.toConstraint) →
      ∀ p ∈ ps, SEntails G p.toConstraint
  | [], _, _, _, _, _ => by simp
  | p :: ps, q, G, hq, hp, hG => by
    have hGq : ∀ x ∈ (q.insertNP p).elems, SEntails G x.toConstraint :=
      fun x hx => hG x (mem_concatNP_of_mem ps hx)
    have hhead : SEntails G p.toConstraint :=
      insertNP_noLoss hcoh hq (hp p (by simp)) hGq
    have htail := concatNP_noLoss hcoh ps (q := q.insertNP p) (G := G)
      (QOk.insertNP hq (hp p (by simp))) (fun d hd => hp d (by simp [hd])) hG
    intro d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hhead
    · exact htail d hd'

/-- **`PQueue(ps)` loses nothing.** -/
theorem ofListQ_noLoss {L : List Lbl} (hcoh : LblCoh L) {ps : List LPart} {G : System}
    (hp : ∀ p ∈ ps, POk L p)
    (hG : ∀ x ∈ (PQueue.ofList ps).elems, SEntails G x.toConstraint) :
    ∀ p ∈ ps, SEntails G p.toConstraint :=
  concatNP_noLoss hcoh ps (q := PQueue.empty) (fun x hx => absurd hx (List.not_mem_nil)) hp hG

/-- **`trim` loses nothing**: it refuses exactly the partitions the processed queue already
holds. -/
theorem trim_noLoss {L : List Lbl} (hcoh : LblCoh L) {ps : SSet LPart} {cs : PQueue}
    {G : System} (hcsOk : QOk L cs) (hpsOk : SOk L ps)
    (hcs : ∀ x ∈ cs.elems, SEntails G x.toConstraint)
    (hkept : ∀ x ∈ (trim ps cs).elems, SEntails G x.toConstraint) :
    ∀ p ∈ ps.elems, SEntails G p.toConstraint := by
  intro p hp
  by_cases hc : cs.contains p = true
  · obtain ⟨x, hx, hxe⟩ := List.any_eq_true.mp hc
    have hxp : x.toConstraint = p.toConstraint :=
      eqv_toConstraint hcoh (hcsOk x hx) (hpsOk p hp) (by simpa using hxe)
    exact fun rho hm => hxp ▸ hcs x hx rho hm
  · have hmem : p ∈ (trim ps cs).elems := by
      unfold trim
      exact SSet.mem_filter_iff.mpr ⟨hp, by simpa using hc⟩
    exact hkept p hmem

/-! ## 3. `sys` depends only on the two queues and the environment -/

theorem sys_congr {s t : State} (hi : s.incm = t.incm) (hp : s.proc = t.proc)
    (he : s.env = t.env) : sys s = sys t := by
  unfold sys State.parts
  rw [hi, hp, he]

/-- Membership in `sys` from the three components. -/
theorem mem_sys_of_three {s : State} {c : Constraint}
    (h : c ∈ sys s) : (∃ p ∈ s.incm.elems, p.toConstraint = c) ∨
      (∃ p ∈ s.proc.elems, p.toConstraint = c) ∨
      (∃ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 = c) := by
  rcases mem_sys.mp h with ⟨p, hp, hpc⟩ | hb
  · rcases List.mem_append.mp hp with hp' | hp'
    · exact Or.inl ⟨p, hp', hpc⟩
    · exact Or.inr (Or.inl ⟨p, hp', hpc⟩)
  · exact Or.inr (Or.inr hb)

/-! ## 4. R2.5 row 2 -- the dequeue drop -/

/-- **The `common` branch at `u = r.lhs` changes nothing.**  `unify` at equal variables
returns the queues and the environment untouched, and the dequeued partition is
`Partition.equals` to the processed partition the lookup found -- so the system the state
denotes is the SAME, and the "deletion" R2.5 row 2 names is the identity on `sys`. -/
theorem common_eq_sys {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some r.lhs)
    (h : step s = .continue s') : sys s' = sys s := by
  obtain ⟨t, hstep, hi, hp, he⟩ := common_self_drops hdq hfr
  rw [h] at hstep
  have hst : s' = t := by injection hstep
  subst hst
  obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := findRHS_witness hfr
  obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
  have hx0r : x0.toConstraint = r.toConstraint :=
    eqv_toConstraint hw.coh (hw.proc x0 hx0) (hw.incm r hrMem)
      (by simp only [LPart.eqv, Bool.and_eq_true]; exact ⟨by simp [hx0lhs], hx0eq⟩)
  apply Finset.Subset.antisymm
  · refine sys_subset (fun x hx => ?_) (fun b hb => by rw [he] at hb; exact mem_sys_of_env hb)
    rcases List.mem_append.mp hx with hx' | hx'
    · rw [hi] at hx'; exact mem_sys_of_incm (hrestMem x hx')
    · rw [hp] at hx'; exact mem_sys_of_proc hx'
  · refine sys_subset (fun x hx => ?_) (fun b hb => ?_)
    · rcases List.mem_append.mp hx with hx' | hx'
      · rcases dequeue_mem_or hdq x hx' with hx'' | rfl
        · exact mem_sys_of_incm (by rw [hi]; exact hx'')
        · rw [← hx0r]; exact mem_sys_of_proc (by rw [hp]; exact hx0)
      · exact mem_sys_of_proc (by rw [hp]; exact hx')
    · exact mem_sys_of_env (by rw [he]; exact hb)

/-- **R2.5 row 2, as a `LoopStrict` step.** -/
theorem step_strict_common_eq {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some r.lhs)
    (h : step s = .continue s') : LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  rw [common_eq_sys hw hdq hfr h]
  exact ⟨LoopStrict.drop (Finset.Subset.refl _) (NoLoss.refl _), Conserv.of_subset
    (Finset.Subset.refl _), Finset.Subset.refl _⟩

/-! ## 5. Two generic facts about an `Except`-fold -/

/-- An `Except`-fold whose step propagates errors stays in error. -/
theorem foldl_except_error {α β : Type} {f : Except String β → α → Except String β}
    (herr : ∀ (m : String) (x : α), f (.error m) x = .error m) :
    ∀ (l : List α) (m : String), l.foldl f (.error m) = .error m := by
  intro l
  induction l with
  | nil => intro m; rfl
  | cons x l ih => intro m; simp only [List.foldl_cons, herr]; exact ih m

/-- **What a successful `Except`-fold guarantees**: an invariant `P` on the accumulator, that
the accumulator only grows (`le`), and that every element of the list has left its
contribution (`C`) in the RESULT.  This is the shape `makeEmpty`'s fold is used in below. -/
theorem foldl_except_covers {α β : Type} {le : β → β → Prop} {C : α → β → Prop}
    {P : β → Prop} {Q : α → Prop} {f : Except String β → α → Except String β}
    (hrefl : ∀ a, le a a) (htrans : ∀ {a b c}, P a → P b → le a b → le b c → le a c)
    (hmonoC : ∀ {x a b}, P a → P b → le a b → C x a → C x b)
    (hstep : ∀ {a x b}, Q x → P a → f (.ok a) x = .ok b → P b ∧ le a b ∧ C x b)
    (herr : ∀ (m : String) (x : α), f (.error m) x = .error m) :
    ∀ (l : List α), (∀ x ∈ l, Q x) → ∀ {a b : β}, P a → l.foldl f (.ok a) = .ok b →
      P b ∧ le a b ∧ ∀ x ∈ l, C x b := by
  intro l
  induction l with
  | nil =>
    intro _ a b hP h
    simp only [List.foldl_nil, Except.ok.injEq] at h
    subst h
    exact ⟨hP, hrefl a, by simp⟩
  | cons x l ih =>
    intro hQ a b hP h
    simp only [List.foldl_cons] at h
    cases hfx : f (.ok a) x with
    | error m =>
      rw [hfx, foldl_except_error herr l m] at h
      exact absurd h (by simp)
    | ok a' =>
      rw [hfx] at h
      obtain ⟨hP', hle, hC⟩ := hstep (hQ x (by simp)) hP hfx
      obtain ⟨hPb, hle', hall⟩ := ih (fun y hy => hQ y (by simp [hy])) hP' h
      refine ⟨hPb, htrans hP hP' hle hle', fun y hy => ?_⟩
      rcases List.mem_cons.mp hy with rfl | hy'
      · exact hmonoC hP' hPb hle' hC
      · exact hall y hy'


/-! ## 6. Reading a constraint back through an elimination -/

/-- If `v` is known EMPTY, erasing it from a right-hand side loses nothing. -/
theorem sat_of_erase {rho : Assign} {a v : Var} {S : Finset Var} {K : Row}
    (hv : rho v = ∅) (h : Sat rho (mk a (S.erase v) K)) : Sat rho (mk a S K) := by
  rw [sat_mk_iff] at h ⊢
  obtain ⟨he, hk, hd⟩ := h
  have hbi : S.biUnion rho = (S.erase v).biUnion rho := by
    ext l
    simp only [Finset.mem_biUnion, Finset.mem_erase]
    constructor
    · rintro ⟨w, hw, hl⟩
      by_cases hwv : w = v
      · rw [hwv, hv] at hl; exact absurd hl (Finset.notMem_empty l)
      · exact ⟨w, ⟨hwv, hw⟩, hl⟩
    · rintro ⟨w, ⟨-, hw⟩, hl⟩; exact ⟨w, hw, hl⟩
  refine ⟨by rw [he, hbi], fun w hw => ?_, fun w hw z hz hwz => ?_⟩
  · by_cases hwv : w = v
    · rw [hwv, hv]; exact Finset.disjoint_empty_right K
    · exact hk w (Finset.mem_erase.mpr ⟨hwv, hw⟩)
  · by_cases hwv : w = v
    · rw [hwv, hv]; exact Finset.disjoint_empty_left (rho z)
    · by_cases hzv : z = v
      · rw [hzv, hv]; exact Finset.disjoint_empty_right (rho w)
      · exact hd w (Finset.mem_erase.mpr ⟨hwv, hw⟩) z (Finset.mem_erase.mpr ⟨hzv, hz⟩) hwz

/-- An all-variable partition whose whole and whose every part are empty is satisfied. -/
theorem sat_of_allEmpty {rho : Assign} {a : Var} {S : Finset Var}
    (ha : rho a = ∅) (hS : ∀ w ∈ S, rho w = ∅) : Sat rho (mk a S (∅ : Row)) := by
  rw [sat_mk_iff]
  refine ⟨?_, fun w _ => Finset.disjoint_empty_left (rho w), fun w hw z _ _ => ?_⟩
  · rw [ha]
    symm
    refine Finset.eq_empty_of_forall_notMem (fun l hl => ?_)
    rcases Finset.mem_union.mp hl with hl' | hl'
    · exact absurd hl' (Finset.notMem_empty l)
    · obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp hl'
      rw [hS w hw] at hlw
      exact absurd hlw (Finset.notMem_empty l)
  · rw [hS w hw]; exact Finset.disjoint_empty_left (rho z)

/-! ### The CHAMP writers keep every CONSTRAINT they were given

`SSet` membership is not preserved on the nose: `+`, `++` and `map` may replace an element by
a `Partition.equals` one (`pickRep`), and `SSet.ofList` deduplicates.  What IS preserved is
the CONSTRAINT the partition denotes, which is all `sys` sees. -/

theorem svalEq_lpart (p q : LPart) : SVal.eq p q = p.eqv q := rfl

/-- `Set + x` keeps every element it had. -/
theorem mem_incl_of_mem {α : Type} [SVal α] {s : SSet α} {x y : α} (h : x ∈ s.elems) :
    x ∈ (s.incl y).elems := by
  unfold SSet.incl
  split
  · exact h
  · split
    · exact SSet.mem_champ.mpr (List.mem_append_left _ h)
    · exact List.mem_append_left _ h

/-- The element `Set + x` was given is there, or an equal one already was. -/
theorem mem_incl_new {α : Type} [SVal α] (s : SSet α) (y : α) :
    y ∈ (s.incl y).elems ∨ ∃ z ∈ s.elems, SVal.eq y z = true := by
  unfold SSet.incl
  split
  · rename_i hc
    exact Or.inr (List.any_eq_true.mp hc)
  · split
    · exact Or.inl (SSet.mem_champ.mpr (List.mem_append_right _ (by simp)))
    · exact Or.inl (List.mem_append_right _ (by simp))

/-- **A fold of `Set + x` keeps every constraint**, from the seed or from the list. -/
theorem toConstraint_mem_foldl_incl {L : List Lbl} (hcoh : LblCoh L) :
    ∀ (ys : List LPart) {a : SSet LPart}, SOk L a → (∀ y ∈ ys, POk L y) →
      ∀ {x : LPart}, POk L x → (x ∈ a.elems ∨ x ∈ ys) →
        ∃ z ∈ (ys.foldl SSet.incl a).elems, z.toConstraint = x.toConstraint := by
  intro ys
  induction ys with
  | nil =>
    intro a _ _ x _ hx
    rcases hx with hx' | hx'
    · exact ⟨x, hx', rfl⟩
    · exact absurd hx' (by simp)
  | cons y ys ih =>
    intro a haOk hys x hxOk hx
    have haOk' : SOk L (a.incl y) := haOk.incl (hys y (by simp))
    have hys' : ∀ z ∈ ys, POk L z := fun z hz => hys z (by simp [hz])
    rcases hx with hx' | hx'
    · exact ih haOk' hys' hxOk (Or.inl (mem_incl_of_mem hx'))
    · rcases List.mem_cons.mp hx' with rfl | hx''
      · rcases mem_incl_new a x with hnew | ⟨z, hz, hzeq⟩
        · exact ih haOk' hys' hxOk (Or.inl hnew)
        · obtain ⟨w, hw, hweq⟩ := ih haOk' hys' (haOk z hz)
            (Or.inl (mem_incl_of_mem hz))
          refine ⟨w, hw, hweq.trans ?_⟩
          exact (eqv_toConstraint hcoh hxOk (haOk z hz) (by rwa [← svalEq_lpart])).symm
      · exact ih haOk' hys' hxOk (Or.inr hx'')

/-- `Set(xs*)` keeps every constraint of `xs`. -/
theorem toConstraint_mem_ofList {L : List Lbl} (hcoh : LblCoh L) {xs : List LPart}
    (hxs : ∀ y ∈ xs, POk L y) {x : LPart} (hx : x ∈ xs) :
    ∃ z ∈ (SSet.ofList xs).elems, z.toConstraint = x.toConstraint :=
  toConstraint_mem_foldl_incl hcoh xs SOk.empty hxs (hxs x hx) (Or.inr hx)

/-- **`Set ++ Set` keeps every constraint of BOTH operands.** -/
theorem toConstraint_mem_concat {L : List Lbl} (hcoh : LblCoh L) {s t : SSet LPart}
    (hs : SOk L s) (ht : SOk L t) {x : LPart} (hx : x ∈ s.elems ∨ x ∈ t.elems) :
    ∃ z ∈ (s.concat t).elems, z.toConstraint = x.toConstraint := by
  have hxOk : POk L x := by
    cases hx with
    | inl h => exact hs x h
    | inr h => exact ht x h
  unfold SSet.concat
  split
  · -- the CHAMP union: every representative denotes the same constraint
    have hrep : ∀ y : LPart, y ∈ s.elems ++ t.elems →
        (SSet.pickRep s.elems t.elems y).toConstraint = y.toConstraint := by
      intro y hy
      have hyOk : POk L y := by
        rcases List.mem_append.mp hy with hy' | hy'
        · exact hs y hy'
        · exact ht y hy'
      unfold SSet.pickRep
      split
      · rfl
      · rename_i sy hf
        have hsyOk : POk L sy := hs sy (List.mem_of_find?_eq_some hf)
        have hsyeq : sy.eqv y = true := by
          have h0 := List.find?_some hf
          rw [← svalEq_lpart]
          simpa using h0
        split
        · rfl
        · exact eqv_toConstraint hcoh hsyOk hyOk hsyeq
    have hgo : ∀ y : LPart, y ∈ s.elems ++ t.elems →
        y ∈ SSet.champ ((s.elems.filter (fun w => !t.contains w)) ++ t.elems) →
        ∃ z ∈ (List.map (SSet.pickRep s.elems t.elems)
          (SSet.champ ((s.elems.filter (fun w => !t.contains w)) ++ t.elems))),
          z.toConstraint = y.toConstraint :=
      fun y hy hyc => ⟨SSet.pickRep s.elems t.elems y, List.mem_map.mpr ⟨y, hyc, rfl⟩, hrep y hy⟩
    rcases hx with hx' | hx'
    · by_cases hc : t.contains x = true
      · obtain ⟨y, hy, hxy⟩ := List.any_eq_true.mp hc
        obtain ⟨z, hz, hzy⟩ := hgo y (List.mem_append_right _ hy)
          (SSet.mem_champ.mpr (List.mem_append_right _ hy))
        refine ⟨z, hz, hzy.trans ?_⟩
        exact (eqv_toConstraint hcoh hxOk (ht y hy) (by rwa [← svalEq_lpart])).symm
      · exact hgo x (List.mem_append_left _ hx')
          (SSet.mem_champ.mpr (List.mem_append_left _
            (List.mem_filter.mpr ⟨hx', by simpa using hc⟩)))
    · exact hgo x (List.mem_append_right _ hx')
        (SSet.mem_champ.mpr (List.mem_append_right _ hx'))
  · exact toConstraint_mem_foldl_incl hcoh t.elems hs (fun y hy => ht y hy) hxOk hx

/-- **`Set.map` keeps every image's constraint.** -/
theorem toConstraint_mem_map {L : List Lbl} (hcoh : LblCoh L) {α : Type} [SVal α]
    {s : SSet α} {f : α → LPart} (hf : ∀ w, POk L (f w)) {w : α} (hw : w ∈ s.elems) :
    ∃ z ∈ (s.map f).elems, z.toConstraint = (f w).toConstraint := by
  have hmap : (s.map f).elems
      = ((s.elems.map f).foldl SSet.incl (⟨s.hashed, []⟩ : SSet LPart)).elems := by
    unfold SSet.map
    rw [List.foldl_map]
  rw [hmap]
  refine toConstraint_mem_foldl_incl hcoh (s.elems.map f) ?_ ?_ (hf w)
    (Or.inr (List.mem_map.mpr ⟨w, hw, rfl⟩))
  · intro z hz; exact absurd hz (by simp)
  · intro z hz; obtain ⟨u, -, rfl⟩ := List.mem_map.mp hz; exact hf u


/-- The constraint an "empty" partition denotes. -/
theorem toConstraint_empty (w : Nat) (i : Option Inference) :
    (⟨w, RHS.empty, i⟩ : LPart).toConstraint = mk w ∅ (∅ : Row) := rfl

/-- `SSet.contains` on variables is list membership. -/
theorem contains_nat_iff {s : SSet Nat} {v : Nat} : s.contains v = true ↔ v ∈ s.elems := by
  unfold SSet.contains
  rw [List.any_eq_true]
  constructor
  · rintro ⟨y, hy, he⟩
    have : v = y := by simpa [SVal.eq] using he
    exact this ▸ hy
  · intro h; exact ⟨v, h, by simp [SVal.eq]⟩

/-! ## 13. Round 2: the FORWARD direction

`L5-REVIEW.md` F2: the round-1 branch proofs discharged their `SSat` premise with L3's
`Refine.step_sat`, which is `(step_refines _).sat` and therefore reaches `LoopRel.weaken`.  The
fix is to prove the forward direction here, and it costs one generic analysis per operation,
run at two predicates:

* `P c := SEntails (sys s) c` — **nothing is invented**, which gives `SSat (sys s) → SSat
  (sys s')` with no `LoopRel` anywhere, and together with `NoLoss` gives model-set EQUALITY;
* `P c := insert c.lhs (vset c) ⊆ allVars (sys s)` — **no variable is invented**, which is the
  clause `LoopStrict.requeue` needs and which F1 says the relation must have.

The one thing both predicates have to be closed under is `Q.+!`'s `CommonPartition` redirect:
from `w <- (S, K)` and `a <- (S, K)` it emits `w <- (a)`. -/

/-- The closure both forward predicates need: the redirect. -/
def RedClosed (P : Constraint → Prop) : Prop :=
  ∀ (w a : Var) (S : Finset Var) (K : Row),
    P (mk w S K) → P (mk a S K) → P (mk w {a} (∅ : Row))

theorem insertP_forward {L : List Lbl} (hcoh : LblCoh L) {P : Constraint → Prop}
    (hred : RedClosed P) {q : PQueue} {p : LPart} (hq : QOk L q) (hp : POk L p)
    (hqP : ∀ x ∈ q.elems, P x.toConstraint) (hpP : P p.toConstraint) :
    ∀ x ∈ (q.insertP p).elems, P x.toConstraint := by
  unfold PQueue.insertP
  split
  · exact hqP
  · split
    · exact hqP
    · split
      · rename_i w hw
        obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := rhsLookup_witness hw
        have hc0 : x0.toConstraint = (⟨w, p.rhs, none⟩ : LPart).toConstraint := by
          rw [← hx0lhs]
          exact toConstraint_congr hcoh (hq x0 hx0) hp hx0eq
        have hshape : (⟨w, p.rhs, none⟩ : LPart).toConstraint
            = mk w (p.rhs.abstr.elems.toFinset)
                ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
        have hshape2 : p.toConstraint
            = mk p.lhs (p.rhs.abstr.elems.toFinset)
                ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
        have hPw : P (mk w (p.rhs.abstr.elems.toFinset)
            ((p.rhs.conc.elems.map Lbl.n).toFinset)) := by
          rw [← hshape, ← hc0]; exact hqP x0 hx0
        have hPa : P (mk p.lhs (p.rhs.abstr.elems.toFinset)
            ((p.rhs.conc.elems.map Lbl.n).toFinset)) := by rw [← hshape2]; exact hpP
        intro x hx
        rcases mem_insertNP hx with hx' | rfl
        · exact hqP x hx'
        · rw [redirect_toConstraint]
          exact hred w p.lhs _ _ hPw hPa
      · intro x hx
        rcases mem_insertSorted hx with rfl | hx'
        · exact hpP
        · exact hqP x hx'

theorem concatP_forward {L : List Lbl} (hcoh : LblCoh L) {P : Constraint → Prop}
    (hred : RedClosed P) :
    ∀ (ps : List LPart) {q : PQueue}, QOk L q → (∀ p ∈ ps, POk L p) →
      (∀ x ∈ q.elems, P x.toConstraint) → (∀ p ∈ ps, P p.toConstraint) →
      ∀ x ∈ (q.concatP ps).elems, P x.toConstraint
  | [], _, _, _, hqP, _ => hqP
  | p :: ps, q, hq, hp, hqP, hpsP =>
    concatP_forward hcoh hred ps (QOk.insertP hq (hp p (by simp)))
      (fun d hd => hp d (by simp [hd]))
      (insertP_forward hcoh hred hq (hp p (by simp)) hqP (hpsP p (by simp)))
      (fun d hd => hpsP d (by simp [hd]))

theorem foldl_concatP_forward {L : List Lbl} (hcoh : LblCoh L) {P : Constraint → Prop}
    (hred : RedClosed P) {g : LPart → PQueue} :
    ∀ (ps : List LPart) {q : PQueue}, QOk L q → (∀ p ∈ ps, QOk L (g p)) →
      (∀ x ∈ q.elems, P x.toConstraint) →
      (∀ p ∈ ps, ∀ y ∈ (g p).elems, P y.toConstraint) →
      ∀ x ∈ (ps.foldl (fun nq p => nq.concatP (g p).elems) q).elems, P x.toConstraint
  | [], _, _, _, hqP, _ => hqP
  | p :: ps, q, hq, hgOk, hqP, hgP =>
    foldl_concatP_forward hcoh hred ps
      (QOk.concatP _ _ hq (fun y hy => hgOk p (by simp) y hy))
      (fun d hd => hgOk d (by simp [hd]))
      (concatP_forward hcoh hred _ hq (fun y hy => hgOk p (by simp) y hy) hqP
        (hgP p (by simp)))
      (fun d hd => hgP d (by simp [hd]))

/-- **`makeEmpty`, forward**: any predicate closed under the redirect, under erasing `v`, and
under the `aux` propagation holds of everything the call returns. -/
theorem makeEmpty_forward {L : List Lbl} (hcoh : LblCoh L) {P : Constraint → Prop}
    (hred : RedClosed P) {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env}
    (hi : QOk L incm) (hp : QOk L proc)
    (hiP : ∀ x ∈ incm.elems, P x.toConstraint) (hpP : ∀ x ∈ proc.elems, P x.toConstraint)
    (heP : ∀ b ∈ env.binds, P (EnvVal.toConstraint b.1 b.2))
    (hvP : P (mk v ∅ (∅ : Row)))
    (hErase : ∀ (a : Var) (S : Finset Var) (K : Row), P (mk a S K) → P (mk a (S.erase v) K))
    (hProp : ∀ (S : Finset Var) (x : Var), P (mk v S (∅ : Row)) → x ∈ S → P (mk x ∅ (∅ : Row)))
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, P x.toConstraint) ∧ (∀ x ∈ np.elems, P x.toConstraint) ∧
      (∀ b ∈ e.binds, P (EnvVal.toConstraint b.1 b.2)) := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  have hnpsOk : SOk L nps := by
    refine foldl_except_inv (P := fun (S : SSet LPart) => SOk L S)
      (Q := fun (x : LPart) => POk L x) ?_ _ ?_ _ ?_ _ hnps
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        have haOk := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · split at hb
          · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact haOk
          · split at hb
            · simp only [pure, Except.pure, Except.ok.injEq] at hb
              subst hb
              exact haOk.concat (SOk.map (fun _ => POk.ofEmpty _ _))
            · exact absurd hb (by simp)
        · simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          exact haOk.incl (POk.mk' (SSet.nodup_excl hx.abstr v) hx.conc)
    · intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact hi.partition_fst _ x hx'
      · exact hp.partition_fst _ x hx'
    · intro b hb
      rw [Except.ok.injEq] at hb; subst hb; exact SOk.empty
  have hnpsP : ∀ x ∈ nps.elems, P x.toConstraint := by
    refine foldl_except_inv (P := fun (S : SSet LPart) => ∀ x ∈ S.elems, P x.toConstraint)
      (Q := fun (x : LPart) => P x.toConstraint) ?_ _ ?_ _ ?_ _ hnps
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        have haP := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · rename_i hlhs
          have hxv : x.lhs = v := by simpa using hlhs
          split at hb
          · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact haP
          · split at hb
            · rename_i hconc
              simp only [pure, Except.pure, Except.ok.injEq] at hb
              subst hb
              intro y hy
              rcases SSet.mem_concat hy with hy' | hy'
              · exact haP y hy'
              · obtain ⟨w, hw, rfl⟩ := SSet.mem_map hy'
                rw [toConstraint_empty]
                refine hProp (vset x.toConstraint) w ?_ ?_
                · rw [← hxv, ← toConstraint_conc_empty hconc]; exact hx
                · rw [LPart.vset_toConstraint]
                  exact List.mem_toFinset.mpr (SSet.mem_excl hw)
            · exact absurd hb (by simp)
        · simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          intro y hy
          rcases SSet.mem_incl hy with hy' | rfl
          · exact haP y hy'
          · rw [toConstraint_erase]
            have hxc : x.toConstraint
                = mk x.lhs (vset x.toConstraint) x.toConstraint.conc := by
              unfold LPart.toConstraint; simp only [vset_mk, conc_mk]
            exact hErase x.lhs (vset x.toConstraint) x.toConstraint.conc (hxc ▸ hx)
    · intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact hiP x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
      · exact hpP x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
    · intro b hb
      rw [Except.ok.injEq] at hb; subst hb
      intro y hy
      exact absurd hy (List.not_mem_nil)
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨rfl, rfl, rfl⟩ := h2
      refine ⟨?_, fun x hx => hpP x (List.mem_of_mem_filter hx), ?_⟩
      · refine concatP_forward hcoh hred _ (hi.partition_snd _)
          (fun x hx => hnpsOk x (SSet.mem_filter hx))
          (fun x hx => hiP x (List.mem_of_mem_filter hx))
          (fun x hx => hnpsP x (SSet.mem_filter hx))
      · intro b hb
        simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton] at hb
        rcases hb with ⟨b0, hb0, rfl⟩ | rfl
        · obtain ⟨w0, val0⟩ := b0
          cases val0 with
          | emptyRow => exact heP _ hb0
          | «alias» z =>
            dsimp only
            by_cases hzv : z = v
            · subst hzv
              rw [if_pos (by simp)]
              have := hErase w0 {z} (∅ : Row) (heP _ hb0)
              rwa [Finset.erase_singleton] at this
            · rw [if_neg (by simpa using hzv)]; exact heP _ hb0
        · exact hvP


/-- **`instantiate`, forward.** -/
theorem instantiate_forward {L : List Lbl} (hcoh : LblCoh L) {P : Constraint → Prop}
    (hred : RedClosed P) {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env}
    (hi : QOk L incm) (hp : QOk L proc)
    (hiP : ∀ x ∈ incm.elems, P x.toConstraint) (hpP : ∀ x ∈ proc.elems, P x.toConstraint)
    (heP : ∀ b ∈ env.binds, P (EnvVal.toConstraint b.1 b.2))
    (hlinkP : P (mk v {u} (∅ : Row)))
    (hRep : ∀ p : LPart, P p.toConstraint → ∀ x ∈ (replace v u p).elems, P x.toConstraint)
    (hAlias : ∀ w : Var, P (mk w {v} (∅ : Row)) → P (mk w {u} (∅ : Row)))
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, P x.toConstraint) ∧ (∀ x ∈ np.elems, P x.toConstraint) ∧
      (∀ b ∈ e.binds, P (EnvVal.toConstraint b.1 b.2)) := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    have hnpsOk : ∀ x ∈ ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems, POk L x := by
      intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact hp.partition_fst _ x hx'
      · exact hi.partition_fst _ x hx'
    have hnpsP : ∀ x ∈ ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems, P x.toConstraint := by
      intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact hpP x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
      · exact hiP x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx')))
    refine ⟨?_, fun x hx => hpP x (List.mem_of_mem_filter hx), ?_⟩
    · refine foldl_concatP_forward hcoh hred _ (hi.partition_snd _)
        (fun q hq => replace_ok (hnpsOk q hq))
        (fun x hx => hiP x (List.mem_of_mem_filter hx))
        (fun q hq => hRep q (hnpsP q hq))
    · intro b hb
      simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton] at hb
      rcases hb with ⟨b0, hb0, rfl⟩ | rfl
      · obtain ⟨w0, val0⟩ := b0
        cases val0 with
        | emptyRow => exact heP _ hb0
        | «alias» z =>
          dsimp only
          by_cases hzv : z = v
          · subst hzv
            rw [if_pos (by simp)]
            exact hAlias w0 (heP _ hb0)
          · rw [if_neg (by simpa using hzv)]; exact heP _ hb0
      · exact hlinkP

/-! ### The two predicates -/

/-- Every variable of the constraint is in `V`. -/
def VocIn (V : Finset Var) (c : Constraint) : Prop := insert c.lhs (vset c) ⊆ V

theorem redClosed_voc (V : Finset Var) : RedClosed (VocIn V) := by
  intro w a S K hw ha
  intro x hx
  rw [lhs_mk, vset_mk] at hx
  rcases Finset.mem_insert.mp hx with rfl | hx'
  · exact hw (by rw [lhs_mk]; exact Finset.mem_insert_self _ _)
  · rw [Finset.mem_singleton] at hx'; subst hx'
    exact ha (by rw [lhs_mk]; exact Finset.mem_insert_self _ _)

theorem redClosed_sent (G : System) : RedClosed (SEntails G) := by
  intro w a S K hw ha rho hm
  refine sat_link_iff.mpr ?_
  have h1 := hw rho hm
  have h2 := ha rho hm
  rw [sat_mk_iff] at h1 h2
  rw [h1.1, h2.1]

theorem allVars_of_vocIn {H : System} {V : Finset Var} (h : ∀ c ∈ H, VocIn V c) :
    allVars H ⊆ V := by
  intro w hw
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
  exact h c hc hwc

theorem vocIn_sys {s : State} {c : Constraint} (hc : c ∈ sys s) : VocIn (allVars (sys s)) c :=
  fun w hw => mem_allVars hc (by
    rcases Finset.mem_insert.mp hw with h | h
    · exact Or.inl h
    · exact Or.inr h)

/-- Everything `sys s` holds, from the three components. -/
theorem sys_forall {s : State} {P : Constraint → Prop}
    (hi : ∀ x ∈ s.incm.elems, P x.toConstraint) (hp : ∀ x ∈ s.proc.elems, P x.toConstraint)
    (he : ∀ b ∈ s.env.binds, P (EnvVal.toConstraint b.1 b.2)) : ∀ c ∈ sys s, P c := by
  intro c hc
  rcases mem_sys_of_three hc with ⟨p, hp', rfl⟩ | ⟨p, hp', rfl⟩ | ⟨b, hb, rfl⟩
  · exact hi p hp'
  · exact hp p hp'
  · exact he b hb

/-- Erasing a variable known EMPTY from a right-hand side keeps the constraint satisfied. -/
theorem sat_erase_of_empty {rho : Assign} {a v : Var} {S : Finset Var} {K : Row}
    (hv : rho v = ∅) (h : Sat rho (mk a S K)) : Sat rho (mk a (S.erase v) K) := by
  rw [sat_mk_iff] at h ⊢
  obtain ⟨he, hk, hd⟩ := h
  have hbi : (S.erase v).biUnion rho = S.biUnion rho := by
    ext l
    simp only [Finset.mem_biUnion, Finset.mem_erase]
    constructor
    · rintro ⟨w, ⟨-, hw⟩, hl⟩; exact ⟨w, hw, hl⟩
    · rintro ⟨w, hw, hl⟩
      by_cases hwv : w = v
      · rw [hwv, hv] at hl; exact absurd hl (Finset.notMem_empty l)
      · exact ⟨w, ⟨hwv, hw⟩, hl⟩
  exact ⟨by rw [he, hbi], fun w hw => hk w (Finset.mem_of_mem_erase hw),
    fun w hw z hz hwz => hd w (Finset.mem_of_mem_erase hw) z (Finset.mem_of_mem_erase hz) hwz⟩


/-- What `replace` returns. -/
theorem mem_replace {v u : Nat} {p : LPart} {x : LPart} (h : x ∈ (replace v u p).elems) :
    x = (⟨(if p.lhs == v then u else p.lhs),
          ⟨p.rhs.abstr.map (fun w => if w == v then u else w), p.rhs.conc⟩, p.inf⟩ : LPart) ∨
    (x = (⟨u, RHS.empty, some Inference.deDuplication⟩ : LPart) ∧
      p.rhs.abstr.contains v = true ∧ p.rhs.abstr.contains u = true) := by
  simp only [replace] at h
  split at h
  · rename_i hboth
    rw [Bool.and_eq_true] at hboth
    have hx := mem_ofList_queue h
    rcases List.mem_cons.mp hx with rfl | hx'
    · exact Or.inl rfl
    · rcases List.mem_cons.mp hx' with rfl | hx''
      · exact Or.inr ⟨rfl, hboth.1, hboth.2⟩
      · exact absurd hx'' (by simp)
  · have hx := mem_ofList_queue h
    rcases List.mem_cons.mp hx with rfl | hx'
    · exact Or.inl rfl
    · exact absurd hx' (by simp)

/-- **`replace` forwards entailment**: under a model of the link, every partition it returns
is a consequence of the one it was given. -/
theorem replace_forward_sent {G : System} {v u : Nat} (hvu : v ≠ u)
    (hlink : SEntails G (mk v {u} (∅ : Row))) {p : LPart} (hP : SEntails G p.toConstraint) :
    ∀ x ∈ (replace v u p).elems, SEntails G x.toConstraint := by
  intro x hx rho hm
  have hvu' : rho v = rho u := sat_link_iff.mp (hlink rho hm)
  rcases mem_replace hx with rfl | ⟨rfl, hv, hu⟩
  · rw [replace_partp_toConstraint]
    exact sat_substC hvu' (hP rho hm)
  · rw [toConstraint_empty]
    refine sat_empty_iff.mpr ?_
    have hsat := hP rho hm
    have hvS : v ∈ vset p.toConstraint := by
      rw [LPart.vset_toConstraint, List.mem_toFinset]; exact contains_nat_iff.mp hv
    have huS : u ∈ vset p.toConstraint := by
      rw [LPart.vset_toConstraint, List.mem_toFinset]; exact contains_nat_iff.mp hu
    have hdisj : Disjoint (rho v) (rho u) := hsat.disjoint_of_ne' hvS huS hvu
    rw [hvu'] at hdisj
    exact eq_empty_of_disjoint_self hdisj

/-- ... and it forwards the vocabulary. -/
theorem replace_forward_voc {V : Finset Var} {v u : Nat} (hu : u ∈ V)
    {p : LPart} (hP : VocIn V p.toConstraint) :
    ∀ x ∈ (replace v u p).elems, VocIn V x.toConstraint := by
  intro x hx
  rcases mem_replace hx with rfl | ⟨rfl, -, -⟩
  · rw [replace_partp_toConstraint]
    intro w hw
    rw [lhs_mk, vset_mk] at hw
    rcases Finset.mem_insert.mp hw with rfl | hw'
    · by_cases hl : p.lhs = v
      · rw [if_pos (by simpa using hl)]; exact hu
      · rw [if_neg (by simpa using hl)]
        exact hP (by rw [LPart.lhs_toConstraint]; exact Finset.mem_insert_self _ _)
    · obtain ⟨y, hy, rfl⟩ := Finset.mem_image.mp hw'
      by_cases hyv : y = v
      · rw [if_pos (by simpa using hyv)]; exact hu
      · rw [if_neg (by simpa using hyv)]
        exact hP (Finset.mem_insert_of_mem hy)
  · rw [toConstraint_empty]
    intro w hw
    rw [lhs_mk, vset_mk] at hw
    rcases Finset.mem_insert.mp hw with rfl | hw'
    · exact hu
    · exact absurd hw' (Finset.notMem_empty w)


/-! ## 7. R2.5 row 4 -- `makeEmpty`'s erasure -/

/-- What `makeEmpty`'s fold leaves behind for one partition it processes: nothing at all for
`v <- ()`, one `w <- ()` per part for an all-variable definition of `v`, and the partition
with `v` erased for everything else. -/
def MECover (v : Nat) (x : LPart) (S : SSet LPart) : Prop :=
  (x.lhs = v ∧ x.rhs.isEmpty = true) ∨
  (x.lhs = v ∧ x.rhs.conc.isEmpty = true ∧
    ∀ w ∈ (x.rhs.abstr.excl v).elems, ∃ z ∈ S.elems, z.toConstraint = mk w ∅ (∅ : Row)) ∨
  (¬ x.lhs = v ∧ ∃ z ∈ S.elems,
      z.toConstraint = mk x.lhs ((vset x.toConstraint).erase v) x.toConstraint.conc)

/-- **`makeEmpty` LOSES NOTHING.**  Given a system that holds everything the call RETURNS --
both queues and the environment, the retained `v <- ()` included -- every partition and every
environment fact the call was GIVEN is a consequence of it.  This is R2.5 row 4's licence: the
erasure deletes only what `v <- ()` and the erased partitions put back. -/
theorem makeEmpty_noLoss {L : List Lbl} (hcoh : LblCoh L) {ns : Names} {v : Nat}
    {incm proc : PQueue} {env : Env} {ni np : PQueue} {e : Env} {G : System}
    (hi : QOk L incm) (hp : QOk L proc)
    (hniG : ∀ x ∈ ni.elems, x.toConstraint ∈ G) (hnpG : ∀ x ∈ np.elems, x.toConstraint ∈ G)
    (heG : ∀ b ∈ e.binds, EnvVal.toConstraint b.1 b.2 ∈ G)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    mk v ∅ (∅ : Row) ∈ G ∧
    (∀ x ∈ incm.elems, SEntails G x.toConstraint) ∧
    (∀ x ∈ proc.elems, SEntails G x.toConstraint) ∧
    (∀ b ∈ env.binds, SEntails G (EnvVal.toConstraint b.1 b.2)) := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  have hqpsOk : SOk L (incm.partition (fun p => p.involves v)).1 := hi.partition_fst _
  have hppsOk : SOk L (proc.partition (fun p => p.involves v)).1 := hp.partition_fst _
  obtain ⟨hnpsOk, -, hcov⟩ :=
    foldl_except_covers (le := fun a b => ∀ y ∈ a.elems,
        ∃ z ∈ b.elems, z.toConstraint = y.toConstraint)
      (C := MECover v) (P := SOk L) (Q := POk L)
      (fun _ y hy => ⟨y, hy, rfl⟩)
      (by
        intro a b c _ _ h1 h2 y hy
        obtain ⟨z, hz, hzy⟩ := h1 y hy
        obtain ⟨w, hw, hwz⟩ := h2 z hz
        exact ⟨w, hw, hwz.trans hzy⟩)
      (by
        intro x a b _ _ hle hC
        rcases hC with hC | ⟨h1, h2, h3⟩ | ⟨h1, z, hz, hzc⟩
        · exact Or.inl hC
        · refine Or.inr (Or.inl ⟨h1, h2, fun w hw => ?_⟩)
          obtain ⟨z, hz, hzc⟩ := h3 w hw
          obtain ⟨y, hy, hyz⟩ := hle z hz
          exact ⟨y, hy, hyz.trans hzc⟩
        · obtain ⟨y, hy, hyz⟩ := hle z hz
          exact Or.inr (Or.inr ⟨h1, y, hy, hyz.trans hzc⟩))
      (by
        intro a x b hxOk haOk hb
        simp only [bind, Except.bind] at hb
        split at hb
        · rename_i hlhs
          have hxv : x.lhs = v := by simpa using hlhs
          split at hb
          · rename_i hemp
            simp only [pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            exact ⟨haOk, fun y hy => ⟨y, hy, rfl⟩, Or.inl ⟨hxv, hemp⟩⟩
          · split at hb
            · rename_i hconc
              simp only [pure, Except.pure, Except.ok.injEq] at hb
              subst hb
              have hgOk : ∀ w : Nat,
                  POk L (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart) :=
                fun w => POk.ofEmpty _ _
              have hmOk : SOk L ((x.rhs.abstr.excl v).map
                  (fun w => (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart))) :=
                SOk.map (fun w => hgOk w)
              refine ⟨haOk.concat hmOk,
                fun y hy => toConstraint_mem_concat hcoh haOk hmOk (Or.inl hy),
                Or.inr (Or.inl ⟨hxv, hconc, fun w hw => ?_⟩)⟩
              obtain ⟨z, hz, hzc⟩ := toConstraint_mem_map hcoh (f := fun w =>
                (⟨w, RHS.empty, some Inference.partitionEmpty⟩ : LPart)) hgOk hw
              obtain ⟨y, hy, hyz⟩ := toConstraint_mem_concat hcoh haOk hmOk (Or.inr hz)
              exact ⟨y, hy, hyz.trans (hzc.trans (toConstraint_empty w _))⟩
            · exact absurd hb (by simp)
        · rename_i hlhs
          simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          have hhOk : POk L (⟨x.lhs, x.rhs.erase v, x.inf⟩ : LPart) :=
            POk.mk' (SSet.nodup_excl hxOk.abstr v) hxOk.conc
          refine ⟨haOk.incl hhOk, fun y hy => ⟨y, mem_incl_of_mem hy, rfl⟩,
            Or.inr (Or.inr ⟨by simpa using hlhs, ?_⟩)⟩
          rcases mem_incl_new a (⟨x.lhs, x.rhs.erase v, x.inf⟩ : LPart) with hnew | ⟨z, hz, hzeq⟩
          · exact ⟨_, hnew, toConstraint_erase x v x.inf⟩
          · refine ⟨z, mem_incl_of_mem hz, ?_⟩
            rw [← toConstraint_erase x v x.inf]
            exact (eqv_toConstraint hcoh hhOk (haOk z hz) (by rwa [← svalEq_lpart])).symm)
      (by intro m x; simp only [bind, Except.bind])
      _
      (by
        intro x hx
        rcases SSet.mem_concat hx with hx' | hx'
        · exact hqpsOk x hx'
        · exact hppsOk x hx')
      SOk.empty hnps
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨rfl, rfl, rfl⟩ := h2
      have hvG : mk v ∅ (∅ : Row) ∈ G := by
        refine heG (v, EnvVal.emptyRow) ?_
        simp [Env.instantiate]
      have hkept : ∀ x ∈ (trim nps (proc.partition (fun p => p.involves v)).2).elems,
          SEntails G x.toConstraint :=
        concatP_noLoss hcoh _ (hi.partition_snd _)
          (fun x hx => hnpsOk x (SSet.mem_filter hx))
          (fun x hx rho hm => hm _ (hniG x hx))
      have hnpsEnt : ∀ x ∈ nps.elems, SEntails G x.toConstraint :=
        trim_noLoss hcoh (hp.partition_snd _) hnpsOk
          (fun x hx rho hm => hm _ (hnpG x hx)) hkept
      have hcover : ∀ x : LPart, MECover v x nps → SEntails G x.toConstraint := by
        intro x hC rho hm
        have hv0 : rho v = ∅ := sat_empty_iff.mp (hm _ hvG)
        rcases hC with ⟨h1, h2⟩ | ⟨h1, h2, h3⟩ | ⟨h1, z, hz, hzc⟩
        · rw [toConstraint_of_isEmpty h2, h1]; exact hm _ hvG
        · rw [toConstraint_conc_empty h2, h1]
          refine sat_of_allEmpty (h1 ▸ hv0) (fun w hw => ?_)
          rw [LPart.vset_toConstraint, List.mem_toFinset] at hw
          -- since brief B1 the propagation excludes `v` itself, so `w = v` is no longer
          -- covered by `nps`; it does not need to be -- `v <- ()` is RETAINED in the
          -- environment, which is exactly `hv0`.
          by_cases hwv : w = v
          · subst hwv; exact hv0
          · obtain ⟨z, hz, hzc⟩ := h3 w (SSet.mem_excl_iff.mpr ⟨hw, hwv⟩)
            have := hnpsEnt z hz rho hm
            rw [hzc] at this
            exact sat_empty_iff.mp this
        · have hsat := hnpsEnt z hz rho hm
          rw [hzc] at hsat
          have hxc : x.toConstraint
              = mk x.lhs (vset x.toConstraint) x.toConstraint.conc := by
            unfold LPart.toConstraint; simp only [vset_mk, conc_mk]
          rw [hxc]
          exact sat_of_erase hv0 hsat
      have hinvolves : ∀ (x : LPart), (x ∈ incm.elems ∨ x ∈ proc.elems) →
          x.involves v = true → SEntails G x.toConstraint := by
        intro x hx hiv
        have hxOk : POk L x := by
          rcases hx with h | h
          · exact hi x h
          · exact hp x h
        have hstep1 : ∃ y ∈ ((incm.partition (fun p => p.involves v)).1.concat
            (proc.partition (fun p => p.involves v)).1).elems,
            y.toConstraint = x.toConstraint := by
          rcases hx with hx' | hx'
          · obtain ⟨y, hy, hyx⟩ := toConstraint_mem_ofList hcoh
              (xs := (incm.elems.filter (fun p => p.involves v)).reverse)
              (fun z hz => hi z (List.mem_of_mem_filter (List.mem_reverse.mp hz)))
              (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hx', hiv⟩))
            obtain ⟨w, hw, hwy⟩ := toConstraint_mem_concat hcoh hqpsOk hppsOk (Or.inl hy)
            exact ⟨w, hw, hwy.trans hyx⟩
          · obtain ⟨y, hy, hyx⟩ := toConstraint_mem_ofList hcoh
              (xs := (proc.elems.filter (fun p => p.involves v)).reverse)
              (fun z hz => hp z (List.mem_of_mem_filter (List.mem_reverse.mp hz)))
              (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hx', hiv⟩))
            obtain ⟨w, hw, hwy⟩ := toConstraint_mem_concat hcoh hqpsOk hppsOk (Or.inr hy)
            exact ⟨w, hw, hwy.trans hyx⟩
        obtain ⟨y, hy, hyx⟩ := hstep1
        rw [← hyx]
        exact hcover y (hcov y hy)
      refine ⟨hvG, fun x hx => ?_, fun x hx => ?_, fun b hb rho hm => ?_⟩
      · by_cases hiv : x.involves v = true
        · exact hinvolves x (Or.inl hx) hiv
        · refine fun rho hm => hm _ (hniG x (mem_concatP_of_mem _ ?_))
          exact List.mem_filter.mpr ⟨hx, by simpa using hiv⟩
      · by_cases hiv : x.involves v = true
        · exact hinvolves x (Or.inr hx) hiv
        · exact fun rho hm => hm _ (hnpG x (List.mem_filter.mpr ⟨hx, by simpa using hiv⟩))
      · have hv0 : rho v = ∅ := sat_empty_iff.mp (hm _ hvG)
        obtain ⟨w0, val0⟩ := b
        cases val0 with
        | emptyRow =>
          refine hm _ (heG (w0, EnvVal.emptyRow) ?_)
          simp only [Env.instantiate, List.mem_append, List.mem_map]
          exact Or.inl ⟨(w0, EnvVal.emptyRow), hb, rfl⟩
        | «alias» z =>
          by_cases hzv : z = v
          · subst hzv
            have hw0 : mk w0 ∅ (∅ : Row) ∈ G := by
              refine heG (w0, EnvVal.emptyRow) ?_
              simp only [Env.instantiate, List.mem_append, List.mem_map]
              exact Or.inl ⟨(w0, EnvVal.alias z), hb, by simp⟩
            have hw0e : rho w0 = ∅ := sat_empty_iff.mp (hm _ hw0)
            change Sat rho (mk w0 {z} (∅ : Row))
            refine sat_of_allEmpty hw0e (fun x hx => ?_)
            rw [Finset.mem_singleton] at hx
            subst hx
            exact hv0
          · refine hm _ (heG (w0, EnvVal.alias z) ?_)
            simp only [Env.instantiate, List.mem_append, List.mem_map]
            refine Or.inl ⟨(w0, EnvVal.alias z), hb, ?_⟩
            simp [hzv]


/-- **R2.5 row 4, as a `LoopStrict` step.**  The `empty` branch is one `emptyRemove`: `v <- ()`
is retained in the environment, satisfiability is preserved (L3's `step_sat`), and nothing is
lost. -/
theorem step_strict_empty {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : step s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  obtain ⟨-, hrestOk⟩ := QOk.dequeue hw.incm hdq
  have hlink : LinkOrEmptyStep s := by
    intro r0 rest0 hd0
    rw [dequeue_unique hdq hd0]
    exact Or.inr (Or.inl hem)
  obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := step_empty_branch hdq hfr hem
  rw [h] at hstep
  cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
  | error m => rw [hres] at hstep; exact absurd hstep (by simp)
  | ok w =>
    obtain ⟨ni, np, e⟩ := w
    rw [hres] at hstep
    simp only [StepResult.continue.injEq] at hstep
    have hi' : s'.incm = ni := by rw [hstep]
    have hp' : s'.proc = np := by rw [hstep]
    have he' : s'.env = e := by rw [hstep]
    obtain ⟨hvG, hincm, hproc, henv⟩ := makeEmpty_noLoss hw.coh hrestOk hw.proc
      (G := sys s') (fun x hx => mem_sys_of_incm (by rw [hi']; exact hx))
      (fun x hx => mem_sys_of_proc (by rw [hp']; exact hx))
      (fun b hb => mem_sys_of_env (by rw [he']; exact hb)) hres
    obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
    have hvsys : mk r.lhs ∅ (∅ : Row) ∈ sys s := by
      rw [← toConstraint_of_isEmpty hem]; exact mem_sys_of_incm hrMem
    -- FORWARD: nothing invented
    have hfS := makeEmpty_forward hw.coh (redClosed_sent (sys s)) hrestOk hw.proc
      (fun x hx rho hm => hm _ (mem_sys_of_incm (hrestMem x hx)))
      (fun x hx rho hm => hm _ (mem_sys_of_proc hx))
      (fun b hb rho hm => hm _ (mem_sys_of_env hb))
      (fun rho hm => hm _ hvsys)
      (fun _ _ _ hP rho hm => sat_erase_of_empty (sat_empty_iff.mp (hm _ hvsys)) (hP rho hm))
      (fun _ _ hP hx rho hm => emptyProp_sat (hP rho hm) (hm _ hvsys) hx) hres
    -- FORWARD: no variable invented
    have hfV := makeEmpty_forward hw.coh (redClosed_voc (allVars (sys s))) hrestOk hw.proc
      (fun x hx => vocIn_sys (mem_sys_of_incm (hrestMem x hx)))
      (fun x hx => vocIn_sys (mem_sys_of_proc hx))
      (fun b hb => vocIn_sys (mem_sys_of_env hb))
      (vocIn_sys hvsys)
      (fun a S K hP w hw => by
        rw [lhs_mk, vset_mk] at hw
        refine hP ?_
        rw [lhs_mk, vset_mk]
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact Finset.mem_insert_self _ _
        · exact Finset.mem_insert_of_mem (Finset.mem_of_mem_erase hw'))
      (fun S x hP hx w hw => by
        rw [lhs_mk, vset_mk] at hw
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact hP (by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_of_mem hx)
        · exact absurd hw' (Finset.notMem_empty w)) hres
    have hvoc : allVars (sys s') ⊆ allVars (sys s) :=
      allVars_of_vocIn (sys_forall (s := s')
        (fun x hx => hfV.1 x (by rw [← hi']; exact hx))
        (fun x hx => hfV.2.1 x (by rw [← hp']; exact hx))
        (fun b hb => hfV.2.2 b (by rw [← he']; exact hb)))
    have hcons : Conserv (sys s) (sys s') :=
      sys_forall (s := s')
        (fun x hx => hfS.1 x (by rw [← hi']; exact hx))
        (fun x hx => hfS.2.1 x (by rw [← hp']; exact hx))
        (fun b hb => hfS.2.2 b (by rw [← he']; exact hb))
    refine ⟨LoopStrict.requeue hvoc hcons ?_, hcons, hvoc⟩
    intro c hc
    rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
    · rcases dequeue_mem_or hdq p hp with hp' | rfl
      · exact hincm p hp'
      · rw [toConstraint_of_isEmpty hem]
        exact fun rho hm => hm _ hvG
    · exact hproc p hp
    · exact henv b hb


/-! ## 8. R2.5 rows 3 and 5 -- `instantiate`'s removal, at both argument orders -/

/-- Rewriting the left-hand side through a link the system holds. -/
theorem sat_lhs_congr {rho : Assign} {a b : Var} {S : Finset Var} {K : Row}
    (hab : rho a = rho b) (h : Sat rho (mk b S K)) : Sat rho (mk a S K) := by
  rw [sat_mk_iff] at h ⊢
  exact ⟨hab.trans h.1, h.2.1, h.2.2⟩

/-- **Reading a partition back through `replace`.**  The substitution `v := u` is invertible
under a model that satisfies the link `v <- (u)`; the one case where it collapses two parts
into one is exactly the case `replace` emits the de-duplication fact `u <- ()` for. -/
theorem sat_of_replace {rho : Assign} {a v u : Var} {S : Finset Var} {K : Row}
    (hlink : rho v = rho u) (hdedup : v ∈ S → u ∈ S → rho u = ∅)
    (h : Sat rho (mk a (S.image (fun w => if w == v then u else w)) K)) :
    Sat rho (mk a S K) := by
  set f : Var → Var := fun w => if w == v then u else w with hf
  have hfv : f v = u := by simp only [hf]; simp
  have hfw : ∀ w : Var, w ≠ v → f w = w := by
    intro w hw
    simp only [hf]
    rw [if_neg (by simpa using hw)]
  have hfr : ∀ w, rho (f w) = rho w := by
    intro w
    by_cases hw : w = v
    · subst hw; rw [hfv]; exact hlink.symm
    · rw [hfw w hw]
  have hbi : (S.image f).biUnion rho = S.biUnion rho := by
    ext l
    simp only [Finset.mem_biUnion, Finset.mem_image]
    constructor
    · rintro ⟨y, ⟨w, hw, rfl⟩, hl⟩; exact ⟨w, hw, by rwa [hfr w] at hl⟩
    · rintro ⟨w, hw, hl⟩; exact ⟨f w, ⟨w, hw, rfl⟩, by rwa [hfr w]⟩
  rw [sat_mk_iff] at h ⊢
  obtain ⟨he, hk, hd⟩ := h
  refine ⟨by rw [he, hbi], fun w hw => ?_, fun w hw z hz hwz => ?_⟩
  · rw [← hfr w]; exact hk (f w) (Finset.mem_image.mpr ⟨w, hw, rfl⟩)
  · by_cases hne : f w = f z
    · -- the two parts collapse: `{w, z} = {v, u}` and the de-duplication fact fires
      have hcol : rho w = ∅ := by
        by_cases hwv : w = v
        · subst hwv
          have hzv : z ≠ w := fun hc => hwz hc.symm
          have hzu : z = u := by rw [← hfw z hzv, ← hne, hfv]
          subst hzu
          exact hlink.trans (hdedup hw hz)
        · by_cases hzv : z = v
          · subst hzv
            have hwu : w = u := by rw [← hfw w hwv, hne, hfv]
            subst hwu
            exact hdedup hz hw
          · exact absurd ((hfw w hwv).symm.trans (hne.trans (hfw z hzv))) hwz
      rw [hcol]
      exact Finset.disjoint_empty_left (rho z)
    · rw [← hfr w, ← hfr z]
      exact hd (f w) (Finset.mem_image.mpr ⟨w, hw, rfl⟩) (f z)
        (Finset.mem_image.mpr ⟨z, hz, rfl⟩) hne

/-- **`replace` loses nothing.** -/
theorem replace_noLoss {L : List Lbl} (hcoh : LblCoh L) {v u : Nat} {p : LPart} {G : System}
    (hpOk : POk L p) (hlink : mk v {u} (∅ : Row) ∈ G)
    (hG : ∀ x ∈ (replace v u p).elems, SEntails G x.toConstraint) :
    SEntails G p.toConstraint := by
  have hpartOk : ∀ w : Nat, POk L
      (⟨w, ⟨p.rhs.abstr.map (fun x => if x == v then u else x), p.rhs.conc⟩, p.inf⟩ : LPart) :=
    fun _ => POk.mk' (SSet.nodup_map _) hpOk.conc
  have hpc : p.toConstraint = mk p.lhs (vset p.toConstraint) p.toConstraint.conc := by
    unfold LPart.toConstraint; simp only [vset_mk, conc_mk]
  intro rho hm
  have hvu : rho v = rho u := sat_link_iff.mp (hm _ hlink)
  -- the rewritten partition, and (when both variables occur) the de-duplication fact
  have hmain : ∀ (hd : v ∈ vset p.toConstraint → u ∈ vset p.toConstraint → rho u = ∅),
      SEntails G (⟨(if p.lhs == v then u else p.lhs),
        ⟨p.rhs.abstr.map (fun w => if w == v then u else w), p.rhs.conc⟩, p.inf⟩
          : LPart).toConstraint → Sat rho p.toConstraint := by
    intro hd hpart
    have h1 := hpart rho hm
    rw [replace_partp_toConstraint] at h1
    rw [hpc]
    refine sat_lhs_congr ?_ (sat_of_replace hvu hd h1)
    by_cases hl : p.lhs = v
    · rw [if_pos (by simpa using hl), hl]; exact hvu
    · rw [if_neg (by simpa using hl)]
  simp only [replace] at hG
  split at hG
  · rename_i hboth
    rw [Bool.and_eq_true] at hboth
    have hlist := ofListQ_noLoss hcoh (ps := [_, (⟨u, RHS.empty, some Inference.deDuplication⟩ :
      LPart)]) (by
        intro x hx
        rcases List.mem_cons.mp hx with rfl | hx'
        · exact hpartOk _
        · rcases List.mem_cons.mp hx' with rfl | hx''
          · exact POk.ofEmpty _ _
          · exact absurd hx'' (by simp)) hG
    have hdedup : rho u = ∅ := by
      have hh := hlist (⟨u, RHS.empty, some Inference.deDuplication⟩ : LPart) (by simp) rho hm
      rw [toConstraint_empty] at hh
      exact sat_empty_iff.mp hh
    exact hmain (fun _ _ => hdedup) (hlist _ (by simp))
  · have hlist := ofListQ_noLoss hcoh (ps := [_]) (by
      intro x hx
      rcases List.mem_cons.mp hx with rfl | hx'
      · exact hpartOk _
      · exact absurd hx' (by simp)) hG
    refine hmain (fun hv hu => ?_) (hlist _ (by simp))
    exfalso
    rename_i hnot
    rw [Bool.not_eq_true, Bool.and_eq_false_iff] at hnot
    rw [LPart.vset_toConstraint, List.mem_toFinset] at hv hu
    rcases hnot with hn | hn
    · exact absurd (contains_nat_iff.mpr hv) (by simp [RHS.contains, hn])
    · exact absurd (contains_nat_iff.mpr hu) (by simp [RHS.contains, hn])

/-- A fold of `++!` keeps everything the queue it started from had. -/
theorem mem_foldl_concatP_of_mem {g : LPart → PQueue} :
    ∀ (ps : List LPart) {q : PQueue} {x : LPart}, x ∈ q.elems →
      x ∈ (ps.foldl (fun nq p => nq.concatP (g p).elems) q).elems
  | [], _, _, h => h
  | p :: ps, q, x, h => mem_foldl_concatP_of_mem ps (mem_concatP_of_mem (g p).elems h)

/-- **A fold of `++!` loses nothing**: every partition any of its steps was asked to insert is
entailed by the queue the fold returns. -/
theorem foldl_concatP_noLoss {L : List Lbl} (hcoh : LblCoh L) {g : LPart → PQueue} :
    ∀ (ps : List LPart) {q : PQueue} {G : System}, QOk L q → (∀ p ∈ ps, QOk L (g p)) →
      (∀ x ∈ (ps.foldl (fun nq p => nq.concatP (g p).elems) q).elems,
        SEntails G x.toConstraint) →
      ∀ p ∈ ps, ∀ y ∈ (g p).elems, SEntails G y.toConstraint
  | [], _, _, _, _, _ => by simp
  | p :: ps, q, G, hq, hgOk, hG => by
    have hstep : ∀ x ∈ (q.concatP (g p).elems).elems, SEntails G x.toConstraint :=
      fun x hx => hG x (mem_foldl_concatP_of_mem ps hx)
    have hhead : ∀ y ∈ (g p).elems, SEntails G y.toConstraint :=
      concatP_noLoss hcoh _ hq (fun y hy => hgOk p (by simp) y hy) hstep
    have htail := foldl_concatP_noLoss hcoh ps (q := q.concatP (g p).elems) (G := G)
      (QOk.concatP _ _ hq (fun y hy => hgOk p (by simp) y hy))
      (fun d hd => hgOk d (by simp [hd])) hG
    intro d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hhead
    · exact htail d hd'

/-- **`instantiate` LOSES NOTHING.**  Given a system that holds everything the call RETURNS --
both queues and the environment, the retained link `v <- (u)` included -- every partition and
every environment fact the call was GIVEN is a consequence of it.  This is R2.5 rows 3 and 5:
the removal deletes only what the link and the rewritten partitions put back. -/
theorem instantiate_noLoss {L : List Lbl} (hcoh : LblCoh L) {ns : Names} {v u : Nat}
    {incm proc : PQueue} {env : Env} {ni np : PQueue} {e : Env} {G : System}
    (hi : QOk L incm) (hp : QOk L proc)
    (hniG : ∀ x ∈ ni.elems, x.toConstraint ∈ G) (hnpG : ∀ x ∈ np.elems, x.toConstraint ∈ G)
    (heG : ∀ b ∈ e.binds, EnvVal.toConstraint b.1 b.2 ∈ G)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    mk v {u} (∅ : Row) ∈ G ∧
    (∀ x ∈ incm.elems, SEntails G x.toConstraint) ∧
    (∀ x ∈ proc.elems, SEntails G x.toConstraint) ∧
    (∀ b ∈ env.binds, SEntails G (EnvVal.toConstraint b.1 b.2)) := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    have hppsOk : SOk L (proc.partition (fun p => p.involves v)).1 := hp.partition_fst _
    have hqpsOk : SOk L (incm.partition (fun p => p.involves v)).1 := hi.partition_fst _
    have hnpsOk : SOk L ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1) := by
      intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact hppsOk x hx'
      · exact hqpsOk x hx'
    have hlinkG : mk v {u} (∅ : Row) ∈ G := by
      refine heG (v, EnvVal.alias u) ?_
      simp [Env.instantiate]
    -- every partition the fold was asked to insert is entailed
    have hfold := foldl_concatP_noLoss hcoh
      (g := fun p => replace v u p)
      ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems
      (hi.partition_snd _) (fun p hp' => replace_ok (hnpsOk p hp'))
      (fun x hx rho hm => hm _ (hniG x hx))
    have hinvolves : ∀ x : LPart, (x ∈ incm.elems ∨ x ∈ proc.elems) → x.involves v = true →
        SEntails G x.toConstraint := by
      intro x hx hiv
      have hxOk : POk L x := by
        rcases hx with h' | h'
        · exact hi x h'
        · exact hp x h'
      have hmem : ∃ y ∈ ((proc.partition (fun p => p.involves v)).1.concat
          (incm.partition (fun p => p.involves v)).1).elems, y.toConstraint = x.toConstraint := by
        rcases hx with hx' | hx'
        · obtain ⟨y, hy, hyx⟩ := toConstraint_mem_ofList hcoh
            (xs := (incm.elems.filter (fun p => p.involves v)).reverse)
            (fun z hz => hi z (List.mem_of_mem_filter (List.mem_reverse.mp hz)))
            (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hx', hiv⟩))
          obtain ⟨w, hw, hwy⟩ := toConstraint_mem_concat hcoh hppsOk hqpsOk (Or.inr hy)
          exact ⟨w, hw, hwy.trans hyx⟩
        · obtain ⟨y, hy, hyx⟩ := toConstraint_mem_ofList hcoh
            (xs := (proc.elems.filter (fun p => p.involves v)).reverse)
            (fun z hz => hp z (List.mem_of_mem_filter (List.mem_reverse.mp hz)))
            (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hx', hiv⟩))
          obtain ⟨w, hw, hwy⟩ := toConstraint_mem_concat hcoh hppsOk hqpsOk (Or.inl hy)
          exact ⟨w, hw, hwy.trans hyx⟩
      obtain ⟨y, hy, hyx⟩ := hmem
      rw [← hyx]
      exact replace_noLoss hcoh (hnpsOk y hy) hlinkG (hfold y hy)
    refine ⟨hlinkG, fun x hx => ?_, fun x hx => ?_, fun b hb rho hm => ?_⟩
    · by_cases hiv : x.involves v = true
      · exact hinvolves x (Or.inl hx) hiv
      · refine fun rho hm => hm _ (hniG x (mem_foldl_concatP_of_mem _ ?_))
        exact List.mem_filter.mpr ⟨hx, by simpa using hiv⟩
    · by_cases hiv : x.involves v = true
      · exact hinvolves x (Or.inr hx) hiv
      · exact fun rho hm => hm _ (hnpG x (List.mem_filter.mpr ⟨hx, by simpa using hiv⟩))
    · have hvu : rho v = rho u := sat_link_iff.mp (hm _ hlinkG)
      obtain ⟨w0, val0⟩ := b
      cases val0 with
      | emptyRow =>
        refine hm _ (heG (w0, EnvVal.emptyRow) ?_)
        simp only [Env.instantiate, List.mem_append, List.mem_map]
        exact Or.inl ⟨(w0, EnvVal.emptyRow), hb, rfl⟩
      | «alias» z =>
        by_cases hzv : z = v
        · subst hzv
          have hw0 : mk w0 {u} (∅ : Row) ∈ G := by
            refine heG (w0, EnvVal.alias u) ?_
            simp only [Env.instantiate, List.mem_append, List.mem_map]
            exact Or.inl ⟨(w0, EnvVal.alias z), hb, by simp⟩
          change Sat rho (mk w0 {z} (∅ : Row))
          exact sat_link_iff.mpr ((sat_link_iff.mp (hm _ hw0)).trans hvu.symm)
        · refine hm _ (heG (w0, EnvVal.alias z) ?_)
          simp only [Env.instantiate, List.mem_append, List.mem_map]
          refine Or.inl ⟨(w0, EnvVal.alias z), hb, ?_⟩
          simp [hzv]


/-- **R2.5 rows 3 and 5, as `LoopStrict` steps: the `common` branch.** -/
theorem step_strict_common {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue} {u : Nat}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some u)
    (h : step s = .continue s') : LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  have hlink : LinkOrEmptyStep s := by
    intro r0 rest0 hd0
    rw [dequeue_unique hdq hd0]
    exact Or.inl (by rw [hfr]; simp)
  by_cases hru : r.lhs = u
  · exact step_strict_common_eq hw hdq (by rw [hru]; exact hfr) h
  · obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
    obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := step_common_branch hdq hfr
    rw [h] at hstep
    cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
    | error m => rw [hres] at hstep; exact absurd hstep (by simp)
    | ok w =>
      obtain ⟨ni, np, e⟩ := w
      rw [hres] at hstep
      simp only [StepResult.continue.injEq] at hstep
      have hi' : s'.incm = ni := by rw [hstep]
      have hp' : s'.proc = np := by rw [hstep]
      have he' : s'.env = e := by rw [hstep]
      have hinst : instantiate s.names r.lhs u rest s.proc s.env = .ok (ni, np, e) := by
        rw [← hres]; unfold unifyVars; rw [if_neg (by simpa using hru)]
      obtain ⟨hlinkG, hincm, hproc, henv⟩ := instantiate_noLoss hw.coh hrestOk hw.proc
        (G := sys s') (fun x hx => mem_sys_of_incm (by rw [hi']; exact hx))
        (fun x hx => mem_sys_of_proc (by rw [hp']; exact hx))
        (fun b hb => mem_sys_of_env (by rw [he']; exact hb)) hinst
      obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := findRHS_witness hfr
      have hc0 : x0.toConstraint = (⟨u, r.rhs, none⟩ : LPart).toConstraint := by
        rw [← hx0lhs]
        exact toConstraint_congr hw.coh (hw.proc x0 hx0) hrOk hx0eq
      obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
      have hrsys : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
      have hx0sys : x0.toConstraint ∈ sys s := mem_sys_of_proc hx0
      have hrshape : r.toConstraint
          = mk r.lhs (r.rhs.abstr.elems.toFinset)
              ((r.rhs.conc.elems.map Lbl.n).toFinset) := rfl
      have hx0shape : x0.toConstraint
          = mk u (r.rhs.abstr.elems.toFinset)
              ((r.rhs.conc.elems.map Lbl.n).toFinset) := hc0
      have hlinkS : SEntails (sys s) (mk r.lhs {u} (∅ : Row)) :=
        redClosed_sent (sys s) r.lhs u _ _ (fun rho hm => hrshape ▸ hm _ hrsys)
          (fun rho hm => hx0shape ▸ hm _ hx0sys)
      have huV : u ∈ allVars (sys s) := by
        have := lhs_mem_allVars hx0sys
        rwa [hx0shape, lhs_mk] at this
      have hrV : r.lhs ∈ allVars (sys s) := by
        have := lhs_mem_allVars hrsys
        rwa [hrshape, lhs_mk] at this
      have hlinkV : VocIn (allVars (sys s)) (mk r.lhs {u} (∅ : Row)) := by
        intro w hw
        rw [lhs_mk, vset_mk] at hw
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact hrV
        · rw [Finset.mem_singleton] at hw'; subst hw'; exact huV
      have hfS := instantiate_forward hw.coh (redClosed_sent (sys s)) hrestOk hw.proc
        (fun x hx rho hm => hm _ (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx rho hm => hm _ (mem_sys_of_proc hx))
        (fun b hb rho hm => hm _ (mem_sys_of_env hb)) hlinkS
        (fun q hq => replace_forward_sent (by simpa using hru) hlinkS hq)
        (fun w hP rho hm => sat_link_iff.mpr
          ((sat_link_iff.mp (hP rho hm)).trans (sat_link_iff.mp (hlinkS rho hm)))) hinst
      have hfV := instantiate_forward hw.coh (redClosed_voc (allVars (sys s))) hrestOk hw.proc
        (fun x hx => vocIn_sys (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx => vocIn_sys (mem_sys_of_proc hx))
        (fun b hb => vocIn_sys (mem_sys_of_env hb)) hlinkV
        (fun q hq => replace_forward_voc huV hq)
        (fun w hP y hy => by
          rw [lhs_mk, vset_mk] at hy
          rcases Finset.mem_insert.mp hy with rfl | hy'
          · exact hP (by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_self _ _)
          · rw [Finset.mem_singleton] at hy'; subst hy'; exact huV) hinst
      have hvoc : allVars (sys s') ⊆ allVars (sys s) :=
        allVars_of_vocIn (sys_forall (s := s')
          (fun x hx => hfV.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfV.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfV.2.2 b (by rw [← he']; exact hb)))
      have hcons : Conserv (sys s) (sys s') :=
        sys_forall (s := s')
          (fun x hx => hfS.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfS.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfS.2.2 b (by rw [← he']; exact hb))
      refine ⟨LoopStrict.requeue hvoc hcons ?_, hcons, hvoc⟩
      intro c hc
      rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
      · rcases dequeue_mem_or hdq p hp with hp' | rfl
        · exact hincm p hp'
        · intro rho hm
          have h1 : Sat rho ((⟨u, p.rhs, none⟩ : LPart).toConstraint) :=
            hc0 ▸ hproc x0 hx0 rho hm
          have h2 : rho p.lhs = rho u := sat_link_iff.mp (hm _ hlinkG)
          have hshape : (⟨u, p.rhs, none⟩ : LPart).toConstraint
              = mk u (p.rhs.abstr.elems.toFinset)
                  ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
          have hshape2 : p.toConstraint
              = mk p.lhs (p.rhs.abstr.elems.toFinset)
                  ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
          rw [hshape] at h1
          rw [hshape2]
          exact sat_lhs_congr h2 h1
      · exact hproc p hp
      · exact henv b hb

/-- **R2.5 row 5, as a `LoopStrict` step: the lone-variable `unify` branch**, where the
arguments are SWAPPED -- `unify(u, v)` on a dequeued `v <- (u)` binds `u`, not `v`. -/
theorem step_strict_unify {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue} {u : Nat}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hsg : r.rhs.single? = some u) (h : step s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  have hlink : LinkOrEmptyStep s := by
    intro r0 rest0 hd0
    rw [dequeue_unique hdq hd0]
    exact Or.inr (Or.inr (by rw [hsg]; simp))
  obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
  obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := step_unify_branch hdq hfr hsg
  rw [h] at hstep
  cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
  | error m => rw [hres] at hstep; exact absurd hstep (by simp)
  | ok w =>
    obtain ⟨ni, np, e⟩ := w
    rw [hres] at hstep
    simp only [StepResult.continue.injEq] at hstep
    have hi' : s'.incm = ni := by rw [hstep]
    have hp' : s'.proc = np := by rw [hstep]
    have he' : s'.env = e := by rw [hstep]
    have hrc : r.toConstraint = mk r.lhs {u} (∅ : Row) := toConstraint_of_single hsg
    by_cases hur : u = r.lhs
    · -- `unify` at equal variables is the identity, and `r` is a self-unification
      have hids : ni = rest ∧ np = s.proc ∧ e = s.env := by
        rw [unifyVars, if_pos (by simpa using hur)] at hres
        rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
        exact ⟨hres.1.symm, hres.2.1.symm, hres.2.2.symm⟩
      have hsub : sys s' ⊆ sys s := by
        refine sys_subset (fun x hx => ?_) (fun b hb => ?_)
        · rcases List.mem_append.mp hx with hx' | hx'
          · rw [hi', hids.1] at hx'
            exact mem_sys_of_incm ((PQueue.dequeue_mem hdq).2 x hx')
          · rw [hp', hids.2.1] at hx'; exact mem_sys_of_proc hx'
        · rw [he', hids.2.2] at hb; exact mem_sys_of_env hb
      have hnl : NoLoss (sys s) (sys s') := by
        intro c hc rho hm
        rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
        · rcases dequeue_mem_or hdq p hp with hp' | rfl
          · exact hm _ (mem_sys_of_incm (by rw [hi', hids.1]; exact hp'))
          · rw [hrc, hur]; exact sat_self rho p.lhs
        · exact hm _ (mem_sys_of_proc (by rw [hp', hids.2.1]; exact hp))
        · exact hm _ (mem_sys_of_env (by rw [he', hids.2.2]; exact hb))
      exact ⟨LoopStrict.drop hsub hnl, Conserv.of_subset hsub, allVars_mono hsub⟩
    · have hinst : instantiate s.names u r.lhs rest s.proc s.env = .ok (ni, np, e) := by
        rw [← hres]; unfold unifyVars; rw [if_neg (by simpa using hur)]
      obtain ⟨hlinkG, hincm, hproc, henv⟩ := instantiate_noLoss hw.coh hrestOk hw.proc
        (G := sys s') (fun x hx => mem_sys_of_incm (by rw [hi']; exact hx))
        (fun x hx => mem_sys_of_proc (by rw [hp']; exact hx))
        (fun b hb => mem_sys_of_env (by rw [he']; exact hb)) hinst
      obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
      have hrsys : mk r.lhs {u} (∅ : Row) ∈ sys s := by
        rw [← hrc]; exact mem_sys_of_incm hrMem
      have hlinkS : SEntails (sys s) (mk u {r.lhs} (∅ : Row)) :=
        fun rho hm => linkSymm_sat (hm _ hrsys)
      have hrV : r.lhs ∈ allVars (sys s) := lhs_mem_allVars hrsys
      have huV : u ∈ allVars (sys s) :=
        mem_allVars hrsys (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self u))
      have hlinkV : VocIn (allVars (sys s)) (mk u {r.lhs} (∅ : Row)) := by
        intro w hw
        rw [lhs_mk, vset_mk] at hw
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact huV
        · rw [Finset.mem_singleton] at hw'; subst hw'; exact hrV
      have hfS := instantiate_forward hw.coh (redClosed_sent (sys s)) hrestOk hw.proc
        (fun x hx rho hm => hm _ (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx rho hm => hm _ (mem_sys_of_proc hx))
        (fun b hb rho hm => hm _ (mem_sys_of_env hb)) hlinkS
        (fun q hq => replace_forward_sent (by simpa using hur) hlinkS hq)
        (fun w hP rho hm => sat_link_iff.mpr
          ((sat_link_iff.mp (hP rho hm)).trans (sat_link_iff.mp (hlinkS rho hm)))) hinst
      have hfV := instantiate_forward hw.coh (redClosed_voc (allVars (sys s))) hrestOk hw.proc
        (fun x hx => vocIn_sys (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx => vocIn_sys (mem_sys_of_proc hx))
        (fun b hb => vocIn_sys (mem_sys_of_env hb)) hlinkV
        (fun q hq => replace_forward_voc hrV hq)
        (fun w hP y hy => by
          rw [lhs_mk, vset_mk] at hy
          rcases Finset.mem_insert.mp hy with rfl | hy'
          · exact hP (by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_self _ _)
          · rw [Finset.mem_singleton] at hy'; subst hy'; exact hrV) hinst
      have hvoc : allVars (sys s') ⊆ allVars (sys s) :=
        allVars_of_vocIn (sys_forall (s := s')
          (fun x hx => hfV.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfV.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfV.2.2 b (by rw [← he']; exact hb)))
      have hcons : Conserv (sys s) (sys s') :=
        sys_forall (s := s')
          (fun x hx => hfS.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfS.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfS.2.2 b (by rw [← he']; exact hb))
      refine ⟨LoopStrict.requeue hvoc hcons ?_, hcons, hvoc⟩
      intro c hc
      rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
      · rcases dequeue_mem_or hdq p hp with hp' | rfl
        · exact hincm p hp'
        · intro rho hm
          rw [hrc]
          exact linkSymm_sat (hm _ hlinkG)
      · exact hproc p hp
      · exact henv b hb


/-! ## 9. The three environment branches, against `LoopStrict` -/

/-- **Refinement against `LoopStrict` for the `common`, `empty` and `unify` branches** -- the
analogue of L3's `Refine.step_refines`, with every use of `LoopRel.weaken` replaced by one of
the licensed deletions of R2.5 rows 2-5.  `LoopRel.weaken` appears nowhere in this proof or in
anything it depends on. -/
theorem step_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  cases hdq : s.incm.dequeue with
  | none =>
    exfalso
    simp only [step] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    cases hfr : s.proc.findRHS r.rhs with
    | some u => exact step_strict_common hw hdq hfr h
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · exact step_strict_empty hw hdq hfr hem h
      · rcases hb r rest hdq with hh | hh | hh
        · rw [hfr] at hh; exact absurd hh (by simp)
        · exact absurd hh hem
        · obtain ⟨u, hu⟩ := Option.isSome_iff_exists.mp hh
          exact step_strict_unify hw hdq hfr hu h

theorem step_refines_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopStrictRun (sys s) (sys s') :=
  Relation.ReflTransGen.single (step_strict hw hb h).1

/-- **... and the step is counted as MINT-FREE**, so `LoopStrictSteps.allVars_card_le` charges
it nothing.  This is the form the loop-level bound needs. -/
theorem step_steps_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : LoopStrictSteps 0 (sys s) (sys s') :=
  LoopStrictSteps.keep (LoopStrictSteps.refl _) (step_strict hw hb h).1
    (step_strict hw hb h).2.2

/-- **Satisfiability along a `LoopStrict` step**, and the fact that makes `LoopStrict` worth
having: the step LOSES NOTHING. -/
theorem step_noLoss_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s') :=
  (step_strict hw hb h).1.no_loss

/-- **... and it INVENTS nothing**: every constraint of the system it reaches is a consequence
of the system it left.  Together with `step_noLoss_strict` this is model-set EQUALITY. -/
theorem step_conserv_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : Conserv (sys s) (sys s') :=
  (step_strict hw hb h).2.1

/-- **The three environment branches do not move the model set at all.** -/
theorem step_models_iff {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') (rho : Assign) :
    SModels rho (sys s) ↔ SModels rho (sys s') :=
  ⟨fun hm => (step_conserv_strict hw hb h).models hm,
   fun hm => (step_noLoss_strict hw hb h).models hm⟩

/-- **`Refine.step_sat` without `LoopRel`** (`L5-REVIEW.md` F2): satisfiability along the three
environment branches, proved from the forward analysis rather than from L3's `step_refines`,
whose `weaken` uses this stage exists to remove. -/
theorem step_sat_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : SSat (sys s) → SSat (sys s') :=
  fun hs => (step_strict hw hb h).1.sat hs

/-- **The vocabulary does not grow at an environment branch.** -/
theorem step_allVars_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStep s)
    (h : step s = .continue s') : allVars (sys s') ⊆ allVars (sys s) :=
  (step_strict hw hb h).2.2


/-! ## 10. R2.5 row 6: what `destructiveSub` deletes that nothing puts back

The `concrete` branch's deletion is licensed only on SATISFIABLE input, and the reason is
`cancellation`: with `rhs1` a bare concrete row (`RHS.ofConcr fs`, no variable parts) its
first branch needs `xs.size == 1` and there are no `xs` at all, and its second needs
`ys.size == 1`.  So against a DEFINITION of `v` that is itself a bare concrete row --
`v <- ((|C|))` with `C ⊆ fs` -- `cancellation` emits NOTHING, `destructiveSub` deletes the
definition (it has fewer than two abstract parts, so `keepDefs` does not save it) and the fact
`C = fs` is not recorded anywhere.  On satisfiable input that costs nothing, because a model
forces `C = fs`; on unsatisfiable input it is a genuine loss, and it is why R2.5 row 6's
licence has to be conditional. -/

/-- A set with no elements loses none by `removedAll`. -/
theorem elems_removedAll_nil {α : Type} [SVal α] {s : SSet α} (hs : s.elems = [])
    (t : SSet α) : (s.removedAll t).elems = [] := by
  unfold SSet.removedAll
  suffices h : ∀ (xs : List α) (a : SSet α), a.elems = [] →
      (xs.foldl SSet.excl a).elems = [] by exact h t.elems s hs
  intro xs
  induction xs with
  | nil => intro a ha; exact ha
  | cons y ys ih =>
    intro a ha
    refine ih (a.excl y) (List.eq_nil_iff_forall_not_mem.mpr (fun z hz => ?_))
    have hz' := SSet.mem_excl hz
    rw [ha] at hz'
    exact absurd hz' (by simp)

/-- **`cancellation` says nothing about two bare concrete rows.**  This is the gap R2.5 row 6's
licence has to work around: `makeConcrete v fs` deletes a definition `v <- ((|C|))` and the
`can` fold contributes nothing in its place. -/
theorem cancellation_bare (v : Nat) (fs cs : SSet Lbl) :
    cancellation v (RHS.ofConcr fs) (RHS.ofConcr cs) = SSet.empty := by
  unfold cancellation
  have h1 : ((RHS.ofConcr fs).abstr.removedAll
      ((RHS.ofConcr fs).abstr.inter (RHS.ofConcr cs).abstr)).size = 0 := by
    unfold SSet.size
    rw [elems_removedAll_nil rfl]
    rfl
  have h2 : ((RHS.ofConcr cs).abstr.removedAll
      ((RHS.ofConcr fs).abstr.inter (RHS.ofConcr cs).abstr)).size = 0 := by
    unfold SSet.size
    rw [elems_removedAll_nil rfl]
    rfl
  rw [if_neg (by simp [h1]), if_neg (by simp [h2])]

/-! ## 11. What the loop's own reverse lookups can SEE

`sys s` is the whole system the state denotes.  The loop's `concRows` / `resolvents` lookups
scan the two QUEUES only (`Constraints.scala:1410-1418`), and `makeEmpty` moves `v <- ()` out
of the queues into the environment -- which is exactly the mismatch `L3-REVIEW.md` §6d names.
`qsys` is the intermediate notion the C3 measure needs: the queues PLUS the retained empty-row
facts, and NOT the aliases. -/

/-- The empty-row facts the environment retains. -/
def envEmptySys (e : Env) : System :=
  (e.binds.filterMap (fun b => match b.2 with
    | .emptyRow => some (Rowpartition.mk b.1 ∅ (∅ : Row))
    | .alias _ => none)).toFinset

/-- **The queue-visible system**: what the loop's own lookups could see if they read the
retained `v <- ()` facts back (which is what `-Dermine.emptyRow` makes them do), and nothing
else.  `qsys s ⊆ sys s`, and the difference is exactly the ALIAS facts. -/
def qsys (s : State) : System :=
  (s.parts.map LPart.toConstraint).toFinset ∪ envEmptySys s.env

theorem qsys_subset_sys (s : State) : qsys s ⊆ sys s := by
  intro c hc
  rcases Finset.mem_union.mp hc with hc' | hc'
  · exact Finset.mem_union_left _ hc'
  · refine Finset.mem_union_right _ ?_
    obtain ⟨b, hb, hbc⟩ := List.mem_filterMap.mp (List.mem_toFinset.mp hc')
    obtain ⟨w, val⟩ := b
    cases val with
    | emptyRow =>
      simp only [Option.some.injEq] at hbc
      exact List.mem_toFinset.mpr (List.mem_map.mpr ⟨(w, EnvVal.emptyRow), hb, hbc⟩)
    | «alias» z => exact absurd hbc (by simp)


/-! ## 12. R2.5 row 7: the `learn` branch DELETES NOTHING

L3's sixth residual `weaken` (R2.5 row 7) is not a deletion: at a `learn` step every partition
of both queues survives and the dequeued one joins `proc`, so the system the state denotes only
GROWS.  The `weaken` is an artifact of building the derived system `H` first and cutting down
to `sys s'` afterwards. -/

theorem step_learn_env {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') : s'.env = s.env := by
  simp only [step, State.log] at h
  rw [hd] at h
  dsimp only at h
  rw [h1] at h
  dsimp only at h
  rw [if_neg (by simp [h2]), if_neg (by simp [h3]), h4] at h
  dsimp only at h
  cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
  | error m => rw [hlp] at h; exact absurd h (by simp)
  | ok w =>
    obtain ⟨learned, su⟩ := w
    rw [hlp] at h
    simp only [StepResult.continue.injEq] at h
    subst h
    simp [foldl_log_env]

/-- **The `learn` branch adds and never removes.** -/
theorem step_learn_sys_mono {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') : sys s ⊆ sys s' := by
  obtain ⟨hproc, learned, hincm⟩ := step_learn_shape hd h1 h2 h3 h4 h
  have henv := step_learn_env hd h1 h2 h3 h4 h
  refine sys_subset (fun x hx => ?_) (fun b hb => mem_sys_of_env (by rw [henv]; exact hb))
  rcases List.mem_append.mp hx with hx' | hx'
  · rcases dequeue_mem_or hd x hx' with hx'' | rfl
    · exact mem_sys_of_incm (by rw [hincm]; exact mem_concatP_of_mem _ hx'')
    · exact mem_sys_of_proc (by rw [hproc]; exact learn_insertNP_self h1 h4)
  · exact mem_sys_of_proc (by rw [hproc]; exact mem_insertNP_of_mem hx')

/-- ... so it loses nothing, trivially. -/
theorem step_learn_noLoss {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') : NoLoss (sys s) (sys s') :=
  NoLoss.of_subset (step_learn_sys_mono hd h1 h2 h3 h4 h)

/-- Every dispatch branch except `concrete`. -/
def NonConcreteStep (s : State) : Prop :=
  ∀ r rest, s.incm.dequeue = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨ r.rhs.abstr.isEmpty = false

/-- **The loop loses information at most at the `concrete` branch.**  `common`, `empty`,
`unify` and `learn` all leave a system that entails everything the system they left had. -/
theorem step_noLoss {s s' : State} (hw : Wf s) (hb : NonConcreteStep s)
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
      · cases hsg : r.rhs.single? with
        | some u => exact (step_strict_unify hw hdq hfr hsg h).1.no_loss
        | none =>
          have habs : r.rhs.abstr.isEmpty = false := by
            rcases hb r rest hdq with hh | hh | hh
            · rw [hfr] at hh; exact absurd hh (by simp)
            · exact absurd hh hem
            · exact hh
          exact step_learn_noLoss hdq hfr (by simpa using hem) habs hsg h


/-! ## 14. Round 2: the `empty` branch's elimination IS `makeEmptyE`

`L5-REVIEW.md` §10(1) asks for the loop's real step to be connected to the operator's output.
For R2.5 row 4 that connection is made here: `sys s` is `mk`-shaped, a successful `makeEmpty`
call means no constraint of `sys s` defines `v` with a concrete part, and therefore
`LoopStrict (sys s) (makeEmptyE r.lhs (sys s))` is a step of the relation. -/

/-- Every constraint a state denotes is `mk`-shaped. -/
theorem mkShaped_sys (s : State) : MkShaped (sys s) := by
  have key : ∀ (a : Var) (S : Finset Var) (k : Row),
      (mk a S k) = mk (mk a S k).lhs (vset (mk a S k)) (mk a S k).conc := by
    intro a S k; rw [lhs_mk, vset_mk, conc_mk]
  intro c hc
  rcases mem_sys_of_three hc with ⟨p, -, rfl⟩ | ⟨p, -, rfl⟩ | ⟨b, -, rfl⟩
  · exact key _ _ _
  · exact key _ _ _
  · obtain ⟨w, val⟩ := b
    cases val
    · exact key _ _ _
    · exact key _ _ _

/-- **A successful `makeEmpty` means no queue definition of `v` carries a label** -- the `die`
arm (`"Incompatible instantiations"`) is exactly the case it rejects. -/
theorem makeEmpty_defs_conc_empty {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    ∀ x ∈ ((incm.partition (fun p => p.involves v)).1.concat
           (proc.partition (fun p => p.involves v)).1).elems,
      x.lhs = v → x.rhs.conc.isEmpty = true := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, -⟩ := except_bind_ok h
  refine (foldl_except_covers (le := fun (_ _ : SSet LPart) => True)
    (C := fun (x : LPart) (_ : SSet LPart) => x.lhs = v → x.rhs.conc.isEmpty = true)
    (P := fun (_ : SSet LPart) => True) (Q := fun (_ : LPart) => True)
    (fun _ => trivial) (fun _ _ _ _ => trivial) (fun _ _ _ hC => hC) ?_
    (by intro m x; simp only [bind, Except.bind]) _ (fun _ _ => trivial) trivial hnps).2.2
  intro a x b _ _ hb
  simp only [bind, Except.bind] at hb
  refine ⟨trivial, trivial, ?_⟩
  intro hxv
  split at hb
  · split at hb
    · rename_i hemp
      have : x.rhs.abstr.isEmpty = true ∧ x.rhs.conc.isEmpty = true := by
        simpa [RHS.isEmpty] using hemp
      exact this.2
    · split at hb
      · assumption
      · exact absurd hb (by simp)
  · rename_i hlhs
    exact absurd hxv (by simpa using hlhs)

/-- **R2.5 row 4, connected to the library operator.**  At the `empty` branch the first step of
the loop's transition is literally `KeyedEmpty.makeEmptyE`; `step_strict_empty`'s `requeue`
then carries it to `sys s'`. -/
theorem step_empty_makeEmptyE {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : step s = .continue s') :
    LoopStrict (sys s) (Rowpartition.KeyedEmpty.makeEmptyE r.lhs (sys s)) := by
  obtain ⟨hrOk, hrestOk⟩ := QOk.dequeue hw.incm hdq
  obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
  obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := step_empty_branch hdq hfr hem
  rw [h] at hstep
  cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
  | error m => rw [hres] at hstep; exact absurd hstep (by simp)
  | ok w =>
    obtain ⟨ni, np, e⟩ := w
    rw [hres] at hstep
    have hvsys : mk r.lhs ∅ (∅ : Row) ∈ sys s := by
      rw [← toConstraint_of_isEmpty hem]; exact mem_sys_of_incm hrMem
    have hqpsOk : SOk s.labels (rest.partition (fun p => p.involves r.lhs)).1 :=
      hrestOk.partition_fst _
    have hppsOk : SOk s.labels (s.proc.partition (fun p => p.involves r.lhs)).1 :=
      hw.proc.partition_fst _
    have hdefs := makeEmpty_defs_conc_empty hres
    have hnobind : s.env.contains r.lhs = false := by
      simp only [makeEmpty] at hres
      obtain ⟨nps0, -, h2⟩ := except_bind_ok hres
      split at h2
      · exact absurd h2 (by simp)
      · split at h2
        · exact absurd h2 (by simp)
        · rename_i hcb; simpa using hcb
    refine emptyRemove_step (mkShaped_sys s) hvsys ?_
    intro c hc hlhs
    rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
    · -- a partition of `incm`: it is `r` itself, or it survives into `rest`
      rcases dequeue_mem_or hdq p hp with hp' | rfl
      · have hiv : p.involves r.lhs = true := by
          simp only [LPart.involves, Bool.or_eq_true]
          exact Or.inl (by simpa using hlhs)
        obtain ⟨y, hy, hyp⟩ := toConstraint_mem_ofList hw.coh
          (xs := (rest.elems.filter (fun q => q.involves r.lhs)).reverse)
          (fun z hz => hrestOk z (List.mem_of_mem_filter (List.mem_reverse.mp hz)))
          (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hp', hiv⟩))
        obtain ⟨z, hz, hzy⟩ := toConstraint_mem_concat hw.coh hqpsOk hppsOk (Or.inl hy)
        have hzl : z.lhs = r.lhs := by
          have : z.toConstraint.lhs = p.toConstraint.lhs := by rw [hzy, hyp]
          simpa using this.trans hlhs
        have := hdefs z hz hzl
        have hnil : z.rhs.conc.elems = [] := by simpa [SSet.isEmpty] using this
        have hzc : z.toConstraint.conc = ∅ := by
          simp only [LPart.conc_toConstraint, hnil, List.map_nil, List.toFinset_nil]
        rw [← hyp, ← hzy]; exact hzc
      · rw [toConstraint_of_isEmpty hem]; rfl
    · have hiv : p.involves r.lhs = true := by
        simp only [LPart.involves, Bool.or_eq_true]
        exact Or.inl (by simpa using hlhs)
      obtain ⟨y, hy, hyp⟩ := toConstraint_mem_ofList hw.coh
        (xs := (s.proc.elems.filter (fun q => q.involves r.lhs)).reverse)
        (fun z hz => hw.proc z (List.mem_of_mem_filter (List.mem_reverse.mp hz)))
        (List.mem_reverse.mpr (List.mem_filter.mpr ⟨hp, hiv⟩))
      obtain ⟨z, hz, hzy⟩ := toConstraint_mem_concat hw.coh hqpsOk hppsOk (Or.inr hy)
      have hzl : z.lhs = r.lhs := by
        have : z.toConstraint.lhs = p.toConstraint.lhs := by rw [hzy, hyp]
        simpa using this.trans hlhs
      have := hdefs z hz hzl
      have hnil : z.rhs.conc.elems = [] := by simpa [SSet.isEmpty] using this
      have hzc : z.toConstraint.conc = ∅ := by
        simp only [LPart.conc_toConstraint, hnil, List.map_nil, List.toFinset_nil]
      rw [← hyp, ← hzy]; exact hzc
    · -- an environment fact: its key would have to be `r.lhs`, which is unbound
      exfalso
      obtain ⟨w0, val0⟩ := b
      have hw0 : w0 = r.lhs := by
        cases val0
        · exact (by simpa [EnvVal.toConstraint] using hlhs : w0 = r.lhs)
        · exact (by simpa [EnvVal.toConstraint] using hlhs : w0 = r.lhs)
      subst hw0
      cases hf : s.env.binds.find? (fun q => q.1 == r.lhs) with
      | none => exact (List.find?_eq_none.mp hf) (r.lhs, val0) hb (by simp)
      | some y =>
        have hcon : s.env.contains r.lhs = true := by
          unfold Env.contains Env.lookup; rw [hf]; rfl
        rw [hnobind] at hcon
        exact absurd hcon (by simp)


end Rowpartition.Loop
