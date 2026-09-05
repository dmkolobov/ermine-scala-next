/-
# L5 round 3 (R3.3): `QueueHygiene` is preserved by `step`

`StrictBound.lean` states the invariant

    QueueHygiene s := ∀ p ∈ s.parts, ∀ v, s.env.contains v = true → p.involves v = false

("no partition of either queue is headed by, or mentions, a variable the environment has
already bound") and proves `queueHygiene_no_rebind`: under it the reinstantiation panic
`instantiateType` raises is unreachable.  Round 2 could not prove PRESERVATION, because it was
FALSE: `makeEmpty`'s `aux` propagated the empty fact to every variable of a right-hand side,
INCLUDING the variable being emptied, so a self-referential `v <- (v, w)` made `makeEmpty v`
manufacture `v <- ()` for `v` itself, which was re-enqueued and dequeued into a second
`makeEmpty v`.  That is the compiler bug of `L5-TERMINATION.md` §0, fixed on both sides in
`B1-FIX.md` (`abstr.map` became `(abstr - v).map`, mirrored at `Loop/Step.lean:126`).

This module proves the preservation the fix makes possible.  The mechanism is one predicate,

    Avoids B c  :=  ¬ B c.lhs ∧ ∀ w ∈ vset c, ¬ B w

run through `StrictStep.lean`'s round-2 forward machinery (`insertP_forward`,
`concatP_forward`, `foldl_concatP_forward`), which is exactly `RedClosed`-parametric and
therefore applies to it.  Two facts are needed of each queue writer: that it keeps the OLD
bound set avoided (which every branch does, since every partition it writes is built from
partitions that already avoided it), and that it makes the NEWLY bound variable avoided, which
is what `makeEmpty`'s `(abstr - v)` and `instantiate`'s `replace` respectively do.
-/
import Rowpartition.Loop.StrictBound

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. Avoiding a set of variables -/

/-- **`c` mentions no variable of `B`.**  `B` is a predicate rather than a `Finset` because
the two uses -- "the environment's bound variables" and "the single variable this step is
about to bind" -- are naturally predicates, and the forward machinery is parametric. -/
def Avoids (B : Var → Prop) (c : Constraint) : Prop :=
  ¬ B c.lhs ∧ ∀ w ∈ vset c, ¬ B w

theorem redClosed_avoids (B : Var → Prop) : RedClosed (Avoids B) := by
  intro w a S K hw ha
  refine ⟨hw.1, ?_⟩
  intro x hx
  rw [vset_mk, Finset.mem_singleton] at hx
  subst hx
  exact ha.1

theorem Avoids.mono {B B' : Var → Prop} (h : ∀ v, B' v → B v) {c : Constraint}
    (hc : Avoids B c) : Avoids B' c :=
  ⟨fun hb => hc.1 (h _ hb), fun w hw hb => hc.2 w hw (h _ hb)⟩

/-- `Avoids` of a partition's constraint, spelled in the partition's own vocabulary. -/
theorem avoids_toConstraint_iff {B : Var → Prop} {p : LPart} :
    Avoids B p.toConstraint ↔ (¬ B p.lhs ∧ ∀ w ∈ p.rhs.abstr.elems, ¬ B w) := by
  simp only [Avoids, LPart.lhs_toConstraint, LPart.vset_toConstraint, List.mem_toFinset]

/-- **The bridge to `QueueHygiene`'s `involves`.** -/
theorem notInvolves_iff_avoids {p : LPart} {v : Nat} :
    p.involves v = false ↔ Avoids (fun w => w = v) p.toConstraint := by
  rw [avoids_toConstraint_iff]
  simp only [LPart.involves, RHS.contains, Bool.or_eq_false_iff, beq_eq_false_iff_ne, ne_eq]
  constructor
  · rintro ⟨h1, h2⟩
    refine ⟨h1, fun w hw hwv => ?_⟩
    subst hwv
    exact absurd (contains_nat_iff.mpr hw) (by simp [h2])
  · rintro ⟨h1, h2⟩
    refine ⟨h1, ?_⟩
    cases hc : p.rhs.abstr.contains v with
    | false => rfl
    | true => exact absurd rfl (h2 v (contains_nat_iff.mp hc))

/-! ## 2. The environment's bound variables -/

theorem Env.contains_iff {e : Env} {v : Nat} : e.contains v = true ↔ ∃ b ∈ e.binds, b.1 = v := by
  unfold Env.contains Env.lookup
  constructor
  · intro h
    cases hf : e.binds.find? (fun p => p.1 == v) with
    | none => rw [hf] at h; simp at h
    | some b =>
      exact ⟨b, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf⟩
  · rintro ⟨b, hb, rfl⟩
    cases hf : e.binds.find? (fun p => p.1 == b.1) with
    | none => exact absurd (List.find?_eq_none.mp hf b hb) (by simp)
    | some _ => simp

/-- `instantiate` adds exactly one bound variable. -/
theorem Env.contains_instantiate {e : Env} {v w : Nat} {val : EnvVal} :
    (e.instantiate v val).contains w = true ↔ e.contains w = true ∨ w = v := by
  rw [Env.contains_iff, Env.contains_iff]
  simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton]
  constructor
  · rintro ⟨b, hb | hb, rfl⟩
    · obtain ⟨b0, hb0, rfl⟩ := hb
      exact Or.inl ⟨b0, hb0, rfl⟩
    · subst hb; exact Or.inr rfl
  · rintro (⟨b, hb, rfl⟩ | rfl)
    · exact ⟨(b.1, _), Or.inl ⟨b, hb, rfl⟩, rfl⟩
    · exact ⟨(w, val), Or.inr rfl, rfl⟩

/-- The predicate `QueueHygiene` is stated at. -/
def Bound (e : Env) (v : Var) : Prop := e.contains v = true

theorem queueHygiene_iff {s : State} :
    QueueHygiene s ↔ ∀ p ∈ s.parts, Avoids (Bound s.env) p.toConstraint := by
  constructor
  · intro h p hp
    refine ⟨fun hb => ?_, fun w hw hb => ?_⟩
    · have := h p hp p.lhs hb
      rw [notInvolves_iff_avoids, avoids_toConstraint_iff] at this
      exact this.1 rfl
    · have := h p hp w hb
      rw [notInvolves_iff_avoids, avoids_toConstraint_iff] at this
      rw [LPart.vset_toConstraint, List.mem_toFinset] at hw
      exact this.2 w hw rfl
  · intro h p hp v hv
    rw [notInvolves_iff_avoids, avoids_toConstraint_iff]
    have hc := avoids_toConstraint_iff.mp (h p hp)
    exact ⟨fun hh => hc.1 (hh ▸ hv), fun w hw hh => hc.2 w hw (hh ▸ hv)⟩

/-! ## 3. The queue writers keep `Avoids`

The same four writers `Order.lean`'s `QNoSelf` goes through, at this predicate.  `Q.+!`'s
`CommonPartition` redirect is the only one that needs an argument: it emits `w <- (a)` where
`w` is the left-hand side of a partition ALREADY in the queue and `a` the left-hand side of
the one being inserted, so both names are ones the caller already vouched for. -/

theorem insertNP_avoids {B : Var → Prop} {q : PQueue} {p x : LPart}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) (hp : Avoids B p.toConstraint)
    (h : x ∈ (q.insertNP p).elems) : Avoids B x.toConstraint := by
  rcases mem_insertNP h with h' | rfl
  · exact hq x h'
  · exact hp

theorem insertP_avoids {B : Var → Prop} {q : PQueue} {p x : LPart}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) (hp : Avoids B p.toConstraint)
    (h : x ∈ (q.insertP p).elems) : Avoids B x.toConstraint := by
  unfold PQueue.insertP at h
  split at h
  · exact hq x h
  · split at h
    · exact hq x h
    · split at h
      · rename_i w hw
        obtain ⟨x0, hx0, -, hx0lhs⟩ := rhsLookup_witness hw
        rcases mem_insertNP h with h' | rfl
        · exact hq x h'
        · rw [avoids_toConstraint_iff]
          refine ⟨?_, ?_⟩
          · show ¬ B w
            rw [← hx0lhs]
            exact (avoids_toConstraint_iff.mp (hq x0 hx0)).1
          · intro y hy
            have : y ∈ [p.lhs] := SSet.mem_ofList hy
            rw [List.mem_singleton] at this
            subst this
            exact (avoids_toConstraint_iff.mp hp).1
      · rcases mem_insertSorted h with rfl | h'
        · exact hp
        · exact hq x h'

theorem concatNP_avoids {B : Var → Prop} : ∀ (ps : List LPart) {q : PQueue},
    (∀ y ∈ q.elems, Avoids B y.toConstraint) → (∀ p ∈ ps, Avoids B p.toConstraint) →
    ∀ x ∈ (q.concatNP ps).elems, Avoids B x.toConstraint
  | [], _, hq, _ => hq
  | p :: ps, _, hq, hps =>
    concatNP_avoids ps (fun y hy => insertNP_avoids hq (hps p (by simp)) hy)
      (fun d hd => hps d (by simp [hd]))

theorem concatP_avoids {B : Var → Prop} : ∀ (ps : List LPart) {q : PQueue},
    (∀ y ∈ q.elems, Avoids B y.toConstraint) → (∀ p ∈ ps, Avoids B p.toConstraint) →
    ∀ x ∈ (q.concatP ps).elems, Avoids B x.toConstraint
  | [], _, hq, _ => hq
  | p :: ps, _, hq, hps =>
    concatP_avoids ps (fun y hy => insertP_avoids hq (hps p (by simp)) hy)
      (fun d hd => hps d (by simp [hd]))

theorem foldl_concatP_avoids {B : Var → Prop} {g : LPart → PQueue} :
    ∀ (ps : List LPart) {q : PQueue}, (∀ y ∈ q.elems, Avoids B y.toConstraint) →
      (∀ p ∈ ps, ∀ y ∈ (g p).elems, Avoids B y.toConstraint) →
      ∀ x ∈ (ps.foldl (fun nq p => nq.concatP (g p).elems) q).elems, Avoids B x.toConstraint
  | [], _, hq, _ => hq
  | p :: ps, q, hq, hg =>
    foldl_concatP_avoids ps (concatP_avoids _ hq (hg p (by simp)))
      (fun d hd => hg d (by simp [hd]))

theorem filter_avoids {B : Var → Prop} {q : PQueue} {f : LPart → Bool}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) :
    ∀ x ∈ (q.filter f).elems, Avoids B x.toConstraint :=
  fun x hx => hq x (List.mem_of_mem_filter hx)

theorem partition_snd_avoids {B : Var → Prop} {q : PQueue} {f : LPart → Bool}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) :
    ∀ x ∈ (q.partition f).2.elems, Avoids B x.toConstraint :=
  fun x hx => hq x (List.mem_of_mem_filter hx)

theorem partition_fst_avoids {B : Var → Prop} {q : PQueue} {f : LPart → Bool}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) :
    ∀ x ∈ (q.partition f).1.elems, Avoids B x.toConstraint :=
  fun x hx => hq x (List.mem_of_mem_filter (List.mem_reverse.mp (SSet.mem_ofList hx)))

/-- The partitions the `involves v` split LEAVES BEHIND avoid `v` as well as `B`. -/
theorem partition_snd_avoids_self {B : Var → Prop} {v : Nat} {q : PQueue}
    (hq : ∀ y ∈ q.elems, Avoids B y.toConstraint) :
    ∀ x ∈ (q.partition (fun p => p.involves v)).2.elems,
      Avoids (fun w => B w ∨ w = v) x.toConstraint := by
  intro x hx
  have hmem : x ∈ q.elems := List.mem_of_mem_filter hx
  have hinv : x.involves v = false := by
    have := List.of_mem_filter hx
    simpa using this
  have h1 := avoids_toConstraint_iff.mp (hq x hmem)
  have h2 := avoids_toConstraint_iff.mp (notInvolves_iff_avoids.mp hinv)
  rw [avoids_toConstraint_iff]
  exact ⟨fun hh => hh.elim h1.1 h2.1, fun w hw hh => hh.elim (h1.2 w hw) (h2.2 w hw)⟩

/-! ## 4. `makeEmpty` -- where the B1 fix is load-bearing

Every partition the call returns avoids the OLD bound set (each is built from one that did)
AND avoids the newly bound `v`: the erasure removes `v` from the right-hand side and is only
taken when the left-hand side is not `v`, and the propagation ranges over `abstr.excl v` --
the `(abstr - v)` of `B1-FIX.md`.  With `abstr` in place of `abstr.excl v` the second
conjunct of `hProp` below is FALSE, and with it the whole invariant. -/

theorem makeEmpty_avoids {B : Var → Prop} {ns : Names} {v : Nat} {incm proc : PQueue}
    {env : Env} {ni np : PQueue} {e : Env}
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint) ∧
      (∀ x ∈ np.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint) := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  have hnpsP : ∀ x ∈ nps.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint := by
    refine foldl_except_inv
      (P := fun (S : SSet LPart) => ∀ x ∈ S.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint)
      (Q := fun (x : LPart) => Avoids B x.toConstraint) ?_ _ ?_ _ ?_ _ hnps
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        have haP := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        have hxA := avoids_toConstraint_iff.mp hx
        split at hb
        · split at hb
          · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact haP
          · split at hb
            · simp only [pure, Except.pure, Except.ok.injEq] at hb
              subst hb
              intro y hy
              rcases SSet.mem_concat hy with hy' | hy'
              · exact haP y hy'
              · obtain ⟨w, hw, rfl⟩ := SSet.mem_map hy'
                rw [avoids_toConstraint_iff]
                obtain ⟨hwm, hwv⟩ := SSet.mem_excl_iff.mp hw
                refine ⟨?_, fun y' hy'' => absurd hy'' (by simp [RHS.empty, SSet.empty])⟩
                rintro (hb' | rfl)
                · exact hxA.2 w hwm hb'
                · exact hwv rfl
            · exact absurd hb (by simp)
        · rename_i hlhs
          simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          intro y hy
          rcases SSet.mem_incl hy with hy' | rfl
          · exact haP y hy'
          · rw [avoids_toConstraint_iff]
            refine ⟨?_, ?_⟩
            · rintro (hb' | hb')
              · exact hxA.1 hb'
              · exact absurd (by simpa using hb' : (x.lhs == v) = true) (by simp [hlhs])
            · intro w hw
              obtain ⟨hwm, hwv⟩ := SSet.mem_excl_iff.mp hw
              rintro (hb' | rfl)
              · exact hxA.2 w hwm hb'
              · exact hwv rfl
    · intro x hx
      rcases SSet.mem_concat hx with hx' | hx'
      · exact partition_fst_avoids hi x hx'
      · exact partition_fst_avoids hp x hx'
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
      refine ⟨?_, partition_snd_avoids_self hp⟩
      exact concatP_avoids _ (partition_snd_avoids_self hi)
        (fun x hx => hnpsP x (SSet.mem_filter hx))

/-! ## 5. `instantiate` -- `replace` rewrites every occurrence of the eliminated variable -/

theorem replace_avoids {B : Var → Prop} {v u : Nat} {p x : LPart}
    (hvu : v ≠ u) (hu : ¬ B u) (hp : Avoids B p.toConstraint)
    (h : x ∈ (replace v u p).elems) :
    Avoids (fun w => B w ∨ w = v) x.toConstraint := by
  have hpA := avoids_toConstraint_iff.mp hp
  have hkey : ∀ w ∈ p.rhs.abstr.elems, ¬ (B (if w == v then u else w) ∨
      (if w == v then u else w) = v) := by
    intro w hw
    by_cases hwv : w = v
    · rw [if_pos (by simpa using hwv)]
      rintro (hb | rfl)
      · exact hu hb
      · exact hvu rfl
    · rw [if_neg (by simpa using hwv)]
      rintro (hb | rfl)
      · exact hpA.2 w hw hb
      · exact hwv rfl
  have hlhs : ¬ (B (if p.lhs == v then u else p.lhs) ∨ (if p.lhs == v then u else p.lhs) = v) := by
    by_cases hwv : p.lhs = v
    · rw [if_pos (by simpa using hwv)]
      rintro (hb | rfl)
      · exact hu hb
      · exact hvu rfl
    · rw [if_neg (by simpa using hwv)]
      rintro (hb | rfl)
      · exact hpA.1 hb
      · exact hwv rfl
  have hdedup : Avoids (fun w => B w ∨ w = v)
      (⟨u, RHS.empty, some Inference.deDuplication⟩ : LPart).toConstraint := by
    rw [avoids_toConstraint_iff]
    refine ⟨?_, fun y hy => absurd hy (by simp [RHS.empty, SSet.empty])⟩
    rintro (hb | rfl)
    · exact hu hb
    · exact hvu rfl
  have hpartp : Avoids (fun w => B w ∨ w = v)
      (⟨if p.lhs == v then u else p.lhs,
        ⟨p.rhs.abstr.map (fun w => if w == v then u else w), p.rhs.conc⟩, p.inf⟩
        : LPart).toConstraint := by
    rw [avoids_toConstraint_iff]
    refine ⟨hlhs, ?_⟩
    intro y hy
    obtain ⟨w, hw, rfl⟩ := SSet.mem_map hy
    exact hkey w hw
  simp only [replace] at h
  split at h
  · have h' := mem_ofList_queue h
    simp only [List.mem_cons, List.not_mem_nil, or_false] at h'
    rcases h' with rfl | rfl
    · exact hpartp
    · exact hdedup
  · have h' := mem_ofList_queue h
    simp only [List.mem_cons, List.not_mem_nil, or_false] at h'
    subst h'
    exact hpartp

theorem instantiate_avoids {B : Var → Prop} {ns : Names} {v u : Nat} {incm proc : PQueue}
    {env : Env} {ni np : PQueue} {e : Env} (hvu : v ≠ u) (hu : ¬ B u)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint) ∧
      (∀ x ∈ np.elems, Avoids (fun w => B w ∨ w = v) x.toConstraint) := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, -⟩ := h
    refine ⟨?_, partition_snd_avoids_self hp⟩
    refine foldl_concatP_avoids _ (partition_snd_avoids_self hi) ?_
    intro q hq y hy
    have hqA : Avoids B q.toConstraint := by
      rcases SSet.mem_concat hq with hq' | hq'
      · exact partition_fst_avoids hp q hq'
      · exact partition_fst_avoids hi q hq'
    exact replace_avoids hvu hu hqA hy

/-! ## 6. `makeConcrete` -- the `concrete` branch binds nothing, so the bound set is fixed

Everything `destructiveSub` and `cancellation` write is assembled out of right-hand sides that
were already in a queue, so the argument is a pure propagation with no new binding. -/

theorem rhsMerge_avoids {B : Var → Prop} {r s : RHS} {nrhs : RHS} {es : SSet Nat}
    (hr : ∀ w ∈ r.abstr.elems, ¬ B w) (hs : ∀ w ∈ s.abstr.elems, ¬ B w)
    (h : rhsMerge r s = .ok (nrhs, es)) :
    (∀ w ∈ nrhs.abstr.elems, ¬ B w) ∧ (∀ w ∈ es.elems, ¬ B w) := by
  simp only [rhsMerge] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    refine ⟨fun w hw => ?_, fun w hw => ?_⟩
    · rcases SSet.mem_concat (SSet.mem_removedAll hw) with hw' | hw'
      · exact hr w hw'
      · exact hs w hw'
    · exact hr w (SSet.mem_inter hw)
  · exact absurd h (by simp)

theorem rhsSubstitute_avoids {B : Var → Prop} {r : RHS} {v : Nat} {sub : RHS} {nrhs : RHS}
    {es : SSet Nat} (hr : ∀ w ∈ r.abstr.elems, ¬ B w) (hs : ∀ w ∈ sub.abstr.elems, ¬ B w)
    (h : rhsSubstitute r v sub = .ok (nrhs, es)) :
    (∀ w ∈ nrhs.abstr.elems, ¬ B w) ∧ (∀ w ∈ es.elems, ¬ B w) := by
  simp only [rhsSubstitute] at h
  split at h
  · refine rhsMerge_avoids ?_ hs h
    intro w hw
    exact hr w (SSet.mem_excl hw)
  · rw [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨hr, fun w hw => absurd hw (by simp [SSet.empty])⟩

theorem subReduce_avoids {B : Var → Prop} {v : Nat} {sub : RHS}
    (hs : ∀ w ∈ sub.abstr.elems, ¬ B w)
    (acc : Except String (SSet LPart)) (r : LPart) (hr : Avoids B r.toConstraint)
    (hacc : ∀ b, acc = .ok b → ∀ x ∈ b.elems, Avoids B x.toConstraint) :
    ∀ b, (do
        let s ← acc
        if r.rhs.contains v then
          let (nrhs, es) ← rhsSubstitute r.rhs v sub
          let s := s.concat (es.map (fun w =>
            (⟨w, RHS.empty, some Inference.deDuplication⟩ : LPart)))
          return s.incl ⟨r.lhs, nrhs, r.inf⟩
        else return s) = .ok b → ∀ x ∈ b.elems, Avoids B x.toConstraint := by
  intro b hb
  cases hacc' : acc with
  | error m => rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
  | ok a =>
    have haP := hacc a hacc'
    rw [hacc'] at hb
    simp only [bind, Except.bind] at hb
    have hrA := avoids_toConstraint_iff.mp hr
    split at hb
    · cases hsub : rhsSubstitute r.rhs v sub with
      | error m => rw [hsub] at hb; simp only [Except.bind] at hb; exact absurd hb (by simp)
      | ok w =>
        obtain ⟨nrhs, es⟩ := w
        rw [hsub] at hb
        simp only [Except.bind, pure, Except.pure, Except.ok.injEq] at hb
        subst hb
        obtain ⟨hn, he⟩ := rhsSubstitute_avoids hrA.2 hs hsub
        intro x hx
        rcases SSet.mem_incl hx with hx' | rfl
        · rcases SSet.mem_concat hx' with hx'' | hx''
          · exact haP x hx''
          · obtain ⟨w0, hw0, rfl⟩ := SSet.mem_map hx''
            rw [avoids_toConstraint_iff]
            exact ⟨he w0 hw0, fun y hy => absurd hy (by simp [RHS.empty, SSet.empty])⟩
        · rw [avoids_toConstraint_iff]
          exact ⟨hrA.1, hn⟩
    · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact haP

theorem subPartitions_avoids {B : Var → Prop} {v : Nat} {sub : RHS} {proc incm : PQueue}
    {S : SSet LPart} (hs : ∀ w ∈ sub.abstr.elems, ¬ B w)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (h : subPartitions v sub proc incm = .ok S) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  simp only [subPartitions] at h
  refine foldl_except_inv
    (P := fun (S : SSet LPart) => ∀ x ∈ S.elems, Avoids B x.toConstraint)
    (Q := fun (x : LPart) => Avoids B x.toConstraint)
    (fun acc x hx hacc => subReduce_avoids hs acc x hx hacc) _
    (fun x hx => hi x (List.mem_of_mem_filter hx)) _ ?_ _ h
  refine foldl_except_inv
    (P := fun (S : SSet LPart) => ∀ x ∈ S.elems, Avoids B x.toConstraint)
    (Q := fun (x : LPart) => Avoids B x.toConstraint)
    (fun acc x hx hacc => subReduce_avoids hs acc x hx hacc) _ hp _ ?_
  intro b hb
  rw [Except.ok.injEq] at hb
  subst hb
  intro y hy
  exact absurd hy (by simp [SSet.empty])

theorem destructiveSub_avoids {B : Var → Prop} {v : Nat} {rhs : RHS} {incm proc : PQueue}
    {ni np : PQueue} (hs : ∀ w ∈ rhs.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) :
    (∀ x ∈ ni.elems, Avoids B x.toConstraint) ∧ (∀ x ∈ np.elems, Avoids B x.toConstraint) := by
  simp only [destructiveSub] at h
  obtain ⟨srs, hsrs, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨rfl, rfl⟩ := h2
  have hsrsP : ∀ x ∈ srs.elems, Avoids B x.toConstraint := by
    refine foldl_except_inv
      (P := fun (S : SSet LPart) => ∀ x ∈ S.elems, Avoids B x.toConstraint)
      (Q := fun (r : RHS) => ∀ w ∈ r.abstr.elems, ¬ B w) ?_ _ ?_ _ ?_ _ hsrs
    · intro acc r hr hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        have haP := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        cases hsp : subPartitions v r (proc.partition (fun p => p.lhs == v)).2
            (incm.partition (fun p => p.lhs == v)).2 with
        | error m => rw [hsp] at hb; simp only [Except.bind] at hb; exact absurd hb (by simp)
        | ok S =>
          rw [hsp] at hb
          simp only [Except.bind, pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          intro x hx
          rcases SSet.mem_concat hx with hx' | hx'
          · exact haP x hx'
          · exact subPartitions_avoids hr (partition_snd_avoids hp)
              (partition_snd_avoids hi) hsp x hx'
    · intro r hr
      obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr
      have : Avoids B q.toConstraint := by
        rcases SSet.mem_concat hq with hq' | hq'
        · exact partition_fst_avoids hp q hq'
        · exact partition_fst_avoids hi q hq'
      exact (avoids_toConstraint_iff.mp this).2
    · intro b hb
      exact subPartitions_avoids hs (partition_snd_avoids hp) (partition_snd_avoids hi) hb
  have hnproc : ∀ x ∈ (if srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then proc else (proc.partition (fun p => p.lhs == v)).2.filter
        (fun p => p.lhs != v && !p.rhs.contains v)).elems, Avoids B x.toConstraint := by
    split
    · exact hp
    · exact filter_avoids (partition_snd_avoids hp)
  have hnincm : ∀ x ∈ (if srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then incm else (incm.partition (fun p => p.lhs == v)).2.filter
        (fun p => p.lhs != v && !p.rhs.contains v)).elems, Avoids B x.toConstraint := by
    split
    · exact hi
    · exact filter_avoids (partition_snd_avoids hi)
  have hnproc2 : ∀ x ∈ (if !(srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty))
      then (if srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then proc else (proc.partition (fun p => p.lhs == v)).2.filter
        (fun p => p.lhs != v && !p.rhs.contains v)).concatNP
        (((proc.partition (fun p => p.lhs == v)).1.filter
          (fun p => decide (p.rhs.abstr.size ≥ 2))).elems)
      else (if srs.isEmpty && !(((proc.partition (fun p => p.lhs == v)).1.concat
        (incm.partition (fun p => p.lhs == v)).1).isEmpty)
      then proc else (proc.partition (fun p => p.lhs == v)).2.filter
        (fun p => p.lhs != v && !p.rhs.contains v))).elems, Avoids B x.toConstraint := by
    split
    · exact concatNP_avoids _ hnproc
        (fun d hd => partition_fst_avoids hp d (SSet.mem_filter hd))
    · exact hnproc
  refine ⟨?_, hnproc2⟩
  refine concatP_avoids _ ?_ (fun d hd => hsrsP d (SSet.mem_filter hd))
  split
  · exact concatP_avoids _ hnincm
      (fun d hd => partition_fst_avoids hi d (SSet.mem_filter hd))
  · exact hnincm

theorem foldl_concat_avoids {B : Var → Prop} {α : Type} {g : α → SSet LPart} :
    ∀ (l : List α) (acc : SSet LPart), (∀ x ∈ acc.elems, Avoids B x.toConstraint) →
      (∀ a ∈ l, ∀ x ∈ (g a).elems, Avoids B x.toConstraint) →
      ∀ x ∈ (l.foldl (fun s a => s.concat (g a)) acc).elems, Avoids B x.toConstraint
  | [], _, hacc, _ => hacc
  | a :: l, acc, hacc, hg =>
    foldl_concat_avoids l (acc.concat (g a))
      (fun x hx => (SSet.mem_concat hx).elim (hacc x) (hg a (by simp) x))
      (fun d hd => hg d (by simp [hd]))

/-- `cancellation`'s conclusion is headed by, and mentions, only variables of the two
right-hand sides it cancels. -/
theorem cancellation_avoids {B : Var → Prop} {v : Nat} {rhs1 rhs2 : RHS}
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ B w) :
    ∀ x ∈ (cancellation v rhs1 rhs2).elems, Avoids B x.toConstraint := by
  intro x hx
  simp only [cancellation] at hx
  split at hx
  · split at hx
    · rename_i y ys hys
      have hy : y ∈ rhs1.abstr.elems :=
        SSet.mem_removedAll (t := rhs1.abstr.inter rhs2.abstr) (by rw [hys]; exact List.mem_cons_self)
      have hx' := SSet.mem_ofList hx
      rw [List.mem_singleton] at hx'
      subst hx'
      rw [avoids_toConstraint_iff]
      exact ⟨h1 y hy, fun w hw => h2 w (SSet.mem_removedAll hw)⟩
    · exact absurd hx (by simp [SSet.empty])
  · split at hx
    · split at hx
      · rename_i y ys hys
        have hy : y ∈ rhs2.abstr.elems :=
          SSet.mem_removedAll (t := rhs1.abstr.inter rhs2.abstr)
            (by rw [hys]; exact List.mem_cons_self)
        have hx' := SSet.mem_ofList hx
        rw [List.mem_singleton] at hx'
        subst hx'
        rw [avoids_toConstraint_iff]
        exact ⟨h2 y hy, fun w hw => h1 w (SSet.mem_removedAll hw)⟩
      · exact absurd hx (by simp [SSet.empty])
    · exact absurd hx (by simp [SSet.empty])

theorem makeConcrete_avoids {B : Var → Prop} {v : Nat} {fs : SSet Lbl} {incm proc : PQueue}
    {ni np : PQueue} (hv : ¬ B v)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    (∀ x ∈ ni.elems, Avoids B x.toConstraint) ∧ (∀ x ∈ np.elems, Avoids B x.toConstraint) := by
  simp only [makeConcrete] at h
  obtain ⟨u1, -, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  obtain ⟨nincm, nproc⟩ := w
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨rfl, rfl⟩ := h3
  have hempty : ∀ w ∈ (RHS.ofConcr fs).abstr.elems, ¬ B w := by
    intro w hw'; exact absurd hw' (by simp [RHS.ofConcr, SSet.empty])
  obtain ⟨hni, hnp⟩ := destructiveSub_avoids hempty hi hp hw
  have hrhss : ∀ r ∈ (((SSet.ofList proc.elems).filter (fun p => p.lhs == v)).map
        (fun p => p.rhs)).concat
      (((SSet.ofList incm.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)) |>.elems,
      ∀ w ∈ r.abstr.elems, ¬ B w := by
    intro r hr
    rcases SSet.mem_concat hr with hr' | hr'
    · obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr'
      exact (avoids_toConstraint_iff.mp
        (hp q (SSet.mem_ofList (SSet.mem_filter hq)))).2
    · obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr'
      exact (avoids_toConstraint_iff.mp
        (hi q (SSet.mem_ofList (SSet.mem_filter hq)))).2
  refine ⟨?_, ?_⟩
  · refine concatP_avoids _ hni ?_
    refine foldl_concat_avoids (g := fun r => cancellation v (RHS.ofConcr fs) r) _ _
      (fun x hx => absurd hx (by simp [SSet.empty])) ?_
    intro r hr
    exact cancellation_avoids hempty (hrhss r hr)
  · intro x hx
    refine insertNP_avoids hnp ?_ hx
    rw [avoids_toConstraint_iff]
    exact ⟨hv, fun y hy => absurd hy (by simp [RHS.ofConcr, SSet.empty])⟩

/-! ## 7. The `learn` branch: the rules name only queue variables and fresh ids

The `learn` branch binds nothing, so the bound set is fixed; what has to be shown is that no
rule's conclusion NAMES a bound variable.  Every name a rule writes comes from one of three
places: the two premises' right-hand sides, a reverse lookup (which returns the left-hand side
or the lone variable part of a partition already in a queue or in the batch), or the supply.
The third needs `SupAvoids`, which the supply invariant `SupFresh` supplies at every state a
replay reaches, since a bound variable is a variable of `sys s`. -/

/-- No id the supply can still hand out is bound. -/
def SupAvoids (B : Var → Prop) (su : Sup) : Prop := ∀ z, Sup.Reach su z → ¬ B z

theorem SupAvoids.fresh_avoids {B : Var → Prop} {su : Sup} (hok : SupOk su)
    (h : SupAvoids B su) : ¬ B (su.fresh).1 := h _ (fresh_reach hok)

theorem SupAvoids.next {B : Var → Prop} {su : Sup} (hok : SupOk su) (h : SupAvoids B su) :
    SupAvoids B (su.fresh).2 := fun z hz => h z (fresh_reach_mono hok z hz).1

theorem supAvoids_of_supFresh {su : Sup} {G : System} (h : SupFresh su G) {B : Var → Prop}
    (hB : ∀ v, B v → v ∈ allVars G) : SupAvoids B su :=
  fun z hz hb => h z hz (hB z hb)

theorem avoids_mk_of {B : Var → Prop} {a : Nat} {r : RHS} {i : Option Inference}
    (ha : ¬ B a) (hr : ∀ w ∈ r.abstr.elems, ¬ B w) :
    Avoids B (⟨a, r, i⟩ : LPart).toConstraint := avoids_toConstraint_iff.mpr ⟨ha, hr⟩

theorem avoids_empty_rhs {B : Var → Prop} {a : Nat} {i : Option Inference} (ha : ¬ B a) :
    Avoids B (⟨a, RHS.empty, i⟩ : LPart).toConstraint :=
  avoids_mk_of ha (fun w hw => absurd hw (by simp [RHS.empty, SSet.empty]))

theorem avoids_conc_rhs {B : Var → Prop} {a : Nat} {c : SSet Lbl} {i : Option Inference}
    (ha : ¬ B a) : Avoids B (⟨a, RHS.ofConcr c, i⟩ : LPart).toConstraint :=
  avoids_mk_of ha (fun w hw => absurd hw (by simp [RHS.ofConcr, SSet.empty]))

theorem selfSubstitution_avoids {B : Var → Prop} {ns : Names} {v : Nat} {abstr : SSet Nat}
    {concr : SSet Lbl} {S : SSet LPart} (ha : ∀ w ∈ abstr.elems, ¬ B w)
    (h : selfSubstitution ns v abstr concr = .ok S) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  simp only [selfSubstitution] at h
  split at h
  · rw [Except.ok.injEq] at h
    subst h
    intro x hx
    obtain ⟨w, hw, rfl⟩ := SSet.mem_map hx
    exact avoids_empty_rhs (ha w (SSet.mem_excl hw))
  · exact absurd h (by simp)

theorem splitConcrete_avoids {B : Var → Prop} {fl : Flags} {v : Nat} {abstr : SSet Nat}
    {concr : SSet Lbl} {rhss : RHS → Option Nat} {resolvent concRow emptyRow : SSet Lbl → Option Nat}
    {su : Sup} (hok : SupOk su) (hsu : SupAvoids B su) (hv : ¬ B v)
    (ha : ∀ w ∈ abstr.elems, ¬ B w)
    (hr : ∀ r w, rhss r = some w → ¬ B w)
    (hres : ∀ k w, resolvent k = some w → ¬ B w)
    (hcr : ∀ k w, concRow k = some w → ¬ B w) :
    (∀ x ∈ (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).1.elems,
        Avoids B x.toConstraint) ∧
      SupOk (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2 ∧
      SupAvoids B (splitConcrete fl v abstr concr rhss resolvent concRow emptyRow su).2 := by
  have hone : ∀ (u : Nat), ¬ B u → ∀ w ∈ (SSet.ofList [u] : SSet Nat).elems, ¬ B w := by
    intro u hu w hw
    have := SSet.mem_ofList hw
    rw [List.mem_singleton] at this
    subst this; exact hu
  unfold splitConcrete
  split
  · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hok, hsu⟩
  · split
    · rename_i u hu
      refine ⟨fun x hx => ?_, hok, hsu⟩
      have hx' := SSet.mem_ofList hx
      rw [List.mem_singleton] at hx'
      subst hx'
      exact avoids_mk_of hv (hone u (hr _ _ hu))
    · split
      · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hok, hsu⟩
      · split
        · rename_i w hw
          refine ⟨fun x hx => ?_, hok, hsu⟩
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
            refine ⟨fun x hx => ?_, hok, hsu⟩
            have hx' := SSet.mem_ofList hx
            rw [List.mem_singleton] at hx'
            subst hx'
            have hwB : ¬ B w := by
              split at hw
              · exact hcr _ _ hw
              · exact absurd hw (by simp)
            exact avoids_mk_of hwB (by simpa [RHS.ofAbstr] using ha)
          · split
            · refine ⟨fun x hx => ?_, hok, hsu⟩
              obtain ⟨w, hw, rfl⟩ := SSet.mem_map hx
              exact avoids_empty_rhs (ha w hw)
            · split
              rename_i u su2 hfr
              refine ⟨fun x hx => ?_, ?_, ?_⟩
              · have hx' := SSet.mem_ofList hx
                simp only [List.mem_cons, List.not_mem_nil, or_false] at hx'
                have huB : ¬ B u := by
                  have := hsu.fresh_avoids hok
                  rw [hfr] at this; exact this
                rcases hx' with rfl | rfl
                · exact avoids_mk_of huB (by simpa [RHS.ofAbstr] using ha)
                · exact avoids_mk_of hv (hone u huB)
              · have := fresh_supOk hok
                rw [hfr] at this; exact this
              · have := hsu.next hok
                rw [hfr] at this; exact this

theorem mem_of_single? {α : Type} [SVal α] {s : SSet α} {x : α} (h : s.single? = some x) :
    x ∈ s.elems := by
  unfold SSet.single? at h
  split at h
  · rename_i y heq
    simp only [Option.some.injEq] at h
    subst h
    rw [heq]
    exact List.mem_cons_self
  · exact absurd h (by simp)

theorem resolution_avoids {B : Var → Prop} {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hok : SupOk su) (hsu : SupAvoids B su) (hv : ¬ B v)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ B w)
    (hres : ∀ k w, resolvent k = some w → ¬ B w)
    (hcr : ∀ k w, concRow k = some w → ¬ B w) :
    (∀ x ∈ (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).1.elems,
        Avoids B x.toConstraint) ∧
      SupOk (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2 ∧
      SupAvoids B (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2 := by
  have hone : ∀ (u : Nat), ¬ B u → ∀ w ∈ (SSet.ofList [u] : SSet Nat).elems, ¬ B w := by
    intro u hu w hw
    have := SSet.mem_ofList hw
    rw [List.mem_singleton] at this
    subst this; exact hu
  simp only [resolution]
  split
  · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hok, hsu⟩
  · split
    · rename_i x y hx0 hy0
      have hxB : ¬ B x := h1 x (mem_of_single? hx0)
      have hyB : ¬ B y := h2 y (mem_of_single? hy0)
      have hokz : SupOk (su.fresh).2 := fresh_supOk hok
      have hsuz : SupAvoids B (su.fresh).2 := hsu.next hok
      have hzB : ¬ B (su.fresh).1 := hsu.fresh_avoids hok
      split
      · exact ⟨fun c hc => absurd hc (by simp [SSet.empty]), hokz, hsuz⟩
      · split
        · rename_i w hw
          have hwB : ¬ B w := by
            split at hw
            · exact hres _ _ hw
            · exact absurd hw (by simp)
          refine ⟨fun c hc => ?_, hokz, hsuz⟩
          have hc' := SSet.mem_ofList hc
          simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
          rcases hc' with rfl | rfl
          · exact avoids_mk_of hxB (hone w hwB)
          · exact avoids_mk_of hyB (hone w hwB)
        · split
          · rename_i w hw
            have hwB : ¬ B w := by
              split at hw
              · exact hcr _ _ hw
              · exact absurd hw (by simp)
            refine ⟨fun c hc => ?_, hokz, hsuz⟩
            have hc' := SSet.mem_ofList hc
            simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
            rcases hc' with rfl | rfl
            · exact avoids_mk_of hxB (hone w hwB)
            · exact avoids_mk_of hyB (hone w hwB)
          · split
            · refine ⟨fun c hc => ?_, hokz, hsuz⟩
              have hc' := SSet.mem_ofList hc
              simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
              rcases hc' with rfl | rfl
              · exact avoids_conc_rhs hxB
              · exact avoids_conc_rhs hyB
            · refine ⟨fun c hc => ?_, hokz, hsuz⟩
              have hc' := SSet.mem_ofList hc
              simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
              rcases hc' with rfl | rfl | rfl
              · exact avoids_mk_of hv (hone _ hzB)
              · exact avoids_mk_of hxB (hone _ hzB)
              · exact avoids_mk_of hyB (hone _ hzB)
    · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hok, hsu⟩

theorem subBody_avoids {B : Var → Prop} {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS}
    {S : SSet LPart} (hu : ¬ B u)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ B w)
    (h : subBody v rhs1 u rhs2 = .ok S) : ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  simp only [subBody] at h
  split at h
  · cases hs : rhsSubstitute rhs2 v rhs1 with
    | error m => rw [hs] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨nrhs, es⟩ := w
      rw [hs] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
      subst h
      obtain ⟨hn, he⟩ := rhsSubstitute_avoids h2 h1 hs
      intro x hx
      rcases SSet.mem_incl hx with hx' | rfl
      · obtain ⟨w0, hw0, rfl⟩ := SSet.mem_map hx'
        exact avoids_empty_rhs (he w0 hw0)
      · exact avoids_mk_of hu hn
  · simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    intro x hx
    exact absurd hx (by simp [SSet.empty])

theorem substitution_avoids {B : Var → Prop} {v : Nat} {rhs1 : RHS} {u : Nat} {rhs2 : RHS}
    {S : SSet LPart} (hv : ¬ B v) (hu : ¬ B u)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ B w)
    (h : substitution v rhs1 u rhs2 = .ok S) : ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  simp only [substitution] at h
  obtain ⟨S1, hS1, h2'⟩ := except_bind_ok h
  obtain ⟨S2, hS2, h3⟩ := except_bind_ok h2'
  simp only [pure, Except.pure, Except.ok.injEq] at h3
  subst h3
  intro x hx
  rcases SSet.mem_concat hx with hx' | hx'
  · exact subBody_avoids hu h1 h2 hS1 x hx'
  · exact subBody_avoids hv h2 h1 hS2 x hx'

theorem commonSubexpression_avoids {B : Var → Prop} {fl : Flags} {v : Nat} {rhs1 : RHS}
    {u : Nat} {rhs2 : RHS} {rhss : RHS → Option Nat} {su : Sup}
    (hok : SupOk su) (hsu : SupAvoids B su) (hv : ¬ B v) (hu : ¬ B u)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h2 : ∀ w ∈ rhs2.abstr.elems, ¬ B w)
    (hr : ∀ r w, rhss r = some w → ¬ B w) :
    (∀ x ∈ (commonSubexpression fl v rhs1 u rhs2 rhss su).1.elems, Avoids B x.toConstraint) ∧
      SupOk (commonSubexpression fl v rhs1 u rhs2 rhss su).2 ∧
      SupAvoids B (commonSubexpression fl v rhs1 u rhs2 rhss su).2 := by
  have hincl : ∀ (a : SSet Nat) (t : SSet Nat) (z : Nat), (∀ w ∈ a.elems, ¬ B w) → ¬ B z →
      ∀ w ∈ ((a.removedAll t).incl z).elems, ¬ B w := by
    intro a t z ha hz w hw
    rcases SSet.mem_incl hw with hw' | rfl
    · exact ha w (SSet.mem_removedAll hw')
    · exact hz
  simp only [commonSubexpression]
  split
  · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hok, hsu⟩
  · split
    · rename_i z hz
      have hzB : ¬ B z := hr _ _ hz
      refine ⟨fun c hc => ?_, hok, hsu⟩
      have hc' := SSet.mem_ofList hc
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
      rcases hc' with rfl | rfl
      · exact avoids_mk_of hv (hincl _ _ _ h1 hzB)
      · exact avoids_mk_of hu (hincl _ _ _ h2 hzB)
    · split
      · refine ⟨fun c hc => ?_, hok, hsu⟩
        have hc' := SSet.mem_ofList hc
        rw [List.mem_singleton] at hc'
        subst hc'
        exact avoids_mk_of hu (hincl _ _ _ h2 hv)
      · split
        · refine ⟨fun c hc => ?_, hok, hsu⟩
          have hc' := SSet.mem_ofList hc
          rw [List.mem_singleton] at hc'
          subst hc'
          exact avoids_mk_of hv (hincl _ _ _ h1 hu)
        · split
          · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hok, hsu⟩
          · have hokz : SupOk (su.fresh).2 := fresh_supOk hok
            have hsuz : SupAvoids B (su.fresh).2 := hsu.next hok
            have hzB : ¬ B (su.fresh).1 := hsu.fresh_avoids hok
            refine ⟨fun c hc => ?_, hokz, hsuz⟩
            have hc' := SSet.mem_ofList hc
            simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
            rcases hc' with rfl | rfl | rfl
            · exact avoids_mk_of hzB (fun w hw =>
                h1 w (SSet.mem_inter (by simpa [RHS.ofAbstr] using hw)))
            · exact avoids_mk_of hv (hincl _ _ _ h1 hzB)
            · exact avoids_mk_of hu (hincl _ _ _ h2 hzB)

theorem disjunction_avoids {B : Var → Prop} {rhs1 rhs2 rhs3 : RHS} {su : Sup}
    (hok : SupOk su) (hsu : SupAvoids B su)
    (h1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w) (h3 : ∀ w ∈ rhs3.abstr.elems, ¬ B w) :
    (∀ x ∈ (disjunction rhs1 rhs2 rhs3 su).1.elems, Avoids B x.toConstraint) ∧
      SupOk (disjunction rhs1 rhs2 rhs3 su).2 ∧
      SupAvoids B (disjunction rhs1 rhs2 rhs3 su).2 := by
  have hokz : SupOk (su.fresh).2 := fresh_supOk hok
  have hsuz : SupAvoids B (su.fresh).2 := hsu.next hok
  have hzB : ¬ B (su.fresh).1 := hsu.fresh_avoids hok
  have habsc : ∀ w ∈ (((rhs1.abstr.inter rhs2.abstr).removedAll
      ((rhs1.abstr.inter rhs2.abstr).inter rhs3.abstr)).incl (su.fresh).1).elems, ¬ B w := by
    intro w hw
    rcases SSet.mem_incl hw with hw' | rfl
    · exact h1 w (SSet.mem_inter (SSet.mem_removedAll hw'))
    · exact hzB
  have habsu : ∀ w ∈ ((((rhs3.abstr.removedAll
      ((rhs1.abstr.inter rhs3.abstr).removedAll
        ((rhs1.abstr.inter rhs2.abstr).inter rhs3.abstr))).removedAll
      ((rhs2.abstr.inter rhs3.abstr).removedAll
        ((rhs1.abstr.inter rhs2.abstr).inter rhs3.abstr))).removedAll
      ((rhs1.abstr.inter rhs2.abstr).inter rhs3.abstr))).elems, ¬ B w := by
    intro w hw
    exact h3 w (SSet.mem_removedAll (SSet.mem_removedAll (SSet.mem_removedAll hw)))
  simp only [disjunction]
  split
  · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hokz, hsuz⟩
  · split
    · exact ⟨fun x hx => absurd hx (by simp [SSet.empty]), hokz, hsuz⟩
    · rename_i u heq
      refine ⟨fun c hc => ?_, hokz, hsuz⟩
      have hc' := SSet.mem_ofList hc
      rw [List.mem_singleton] at hc'
      subst hc'
      exact avoids_mk_of (habsu u (by rw [heq]; exact List.mem_cons_self)) habsc
    · have hokus : SupOk (((su.fresh).2).fresh).2 := fresh_supOk hokz
      have hsuus : SupAvoids B (((su.fresh).2).fresh).2 := hsuz.next hokz
      have husB : ¬ B (((su.fresh).2).fresh).1 := hsuz.fresh_avoids hokz
      refine ⟨fun c hc => ?_, hokus, hsuus⟩
      have hc' := SSet.mem_ofList hc
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc'
      rcases hc' with rfl | rfl
      · exact avoids_mk_of husB (by simpa [RHS.ofAbstr] using habsu)
      · exact avoids_mk_of husB habsc

/-! ### 7.1 The reverse lookups return names the queues already carry -/

theorem flPut_values {m : List (SSet Lbl × Nat)} {k : SSet Lbl} {u : Nat} {P : Nat → Prop}
    (hm : ∀ q ∈ m, P q.2) (hu : P u) : ∀ q ∈ flPut m k u, P q.2 := by
  intro q hq
  unfold flPut at hq
  split at hq
  · obtain ⟨q0, hq0, rfl⟩ := List.mem_map.mp hq
    split
    · exact hu
    · exact hm q0 hq0
  · rcases List.mem_append.mp hq with hq' | hq'
    · exact hm q hq'
    · rw [List.mem_singleton] at hq'; subst hq'; exact hu

theorem flGet_value {m : List (SSet Lbl × Nat)} {k : SSet Lbl} {u : Nat} {P : Nat → Prop}
    (hm : ∀ q ∈ m, P q.2) (h : flGet m k = some u) : P u := by
  unfold flGet at h
  cases hf : m.find? (fun p => p.1.eqv k) with
  | none => rw [hf] at h; simp at h
  | some q =>
    rw [hf] at h
    simp only [Option.map_some, Option.some.injEq] at h
    subst h
    exact hm q (List.mem_of_find?_eq_some hf)

/-- Both maps of the lookup table hold only names the queues already carry. -/
def LkAvoids (B : Var → Prop) (l : Lookups) : Prop :=
  (∀ q ∈ l.resolvents, ¬ B q.2) ∧ (∀ q ∈ l.rows, ¬ B q.2)

theorem foldl_mkLookups_avoids {B : Var → Prop} {v : Nat} :
    ∀ (ps : List LPart) (l0 : Lookups), LkAvoids B l0 →
      (∀ p ∈ ps, Avoids B p.toConstraint) →
      LkAvoids B (ps.foldl (fun (l : Lookups) (p : LPart) =>
        let l := match p.rhs.abstrSingle? with
          | some w => if p.lhs == v then { l with resolvents := flPut l.resolvents p.rhs.conc w }
                      else l
          | none => l
        if p.rhs.abstr.isEmpty then
          { l with rows := flPut l.rows p.rhs.conc p.lhs,
                   myRow := if p.lhs == v then some p.rhs.conc else l.myRow }
        else l) l0)
  | [], _, hl0, _ => hl0
  | p :: ps, l0, hl0, hps => by
    refine foldl_mkLookups_avoids ps _ ?_ (fun d hd => hps d (by simp [hd]))
    have hpA := avoids_toConstraint_iff.mp (hps p (by simp))
    have hstep : LkAvoids B (match p.rhs.abstrSingle? with
        | some w => if p.lhs == v then { l0 with resolvents := flPut l0.resolvents p.rhs.conc w }
                    else l0
        | none => l0) := by
      split
      · rename_i w hw
        split
        · exact ⟨flPut_values (P := fun z => ¬ B z) hl0.1 (hpA.2 w (mem_of_single? hw)), hl0.2⟩
        · exact hl0
      · exact hl0
    dsimp only
    split
    · exact ⟨hstep.1, flPut_values (P := fun z => ¬ B z) hstep.2 hpA.1⟩
    · exact hstep

theorem mkLookups_avoids {B : Var → Prop} {v : Nat} {incm proc : PQueue}
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint) :
    LkAvoids B (mkLookups v incm proc) := by
  simp only [mkLookups]
  exact foldl_mkLookups_avoids _ _
    (foldl_mkLookups_avoids _ _ ⟨by simp, by simp⟩ hp) hi

theorem findRHS_avoids {B : Var → Prop} {q : PQueue} {r : RHS} {w : Nat}
    (hq : ∀ x ∈ q.elems, Avoids B x.toConstraint) (h : q.findRHS r = some w) : ¬ B w := by
  unfold PQueue.findRHS at h
  cases hf : q.elems.find? (fun x => x.rhs.eqv r) with
  | none => rw [hf] at h; simp at h
  | some x =>
    rw [hf] at h
    simp only [Option.map_some, Option.some.injEq] at h
    subst h
    exact (avoids_toConstraint_iff.mp (hq x (List.mem_of_find?_eq_some hf))).1

theorem findRHS3_avoids {B : Var → Prop} {ps cs : PQueue} {s : SSet LPart} {r : RHS} {w : Nat}
    (hps : ∀ x ∈ ps.elems, Avoids B x.toConstraint)
    (hcs : ∀ x ∈ cs.elems, Avoids B x.toConstraint)
    (hs : ∀ x ∈ s.elems, Avoids B x.toConstraint)
    (h : findRHS3 ps cs s r = some w) : ¬ B w := by
  unfold findRHS3 at h
  split at h
  · rename_i u hu
    simp only [Option.some.injEq] at h
    subst h
    exact findRHS_avoids hcs hu
  · split at h
    · rename_i u hu
      simp only [Option.some.injEq] at h
      subst h
      exact findRHS_avoids hps hu
    · cases hf : s.elems.find? (fun x => x.rhs.eqv r) with
      | none => rw [hf] at h; simp at h
      | some x =>
        rw [hf] at h
        simp only [Option.map_some, Option.some.injEq] at h
        subst h
        exact (avoids_toConstraint_iff.mp (hs x (List.mem_of_find?_eq_some hf))).1

theorem findResolvent_avoids {B : Var → Prop} {v : Nat} {l : Lookups} {s : SSet LPart}
    {k : SSet Lbl} {w : Nat} (hl : LkAvoids B l)
    (hs : ∀ x ∈ s.elems, Avoids B x.toConstraint)
    (h : findResolvent v l s k = some w) : ¬ B w := by
  unfold findResolvent at h
  split at h
  · rename_i u hu
    simp only [Option.some.injEq] at h
    subst h
    obtain ⟨x, hx, hxu⟩ := List.exists_of_findSome?_eq_some hu
    split at hxu
    · rename_i y hy
      split at hxu
      · simp only [Option.some.injEq] at hxu
        subst hxu
        exact (avoids_toConstraint_iff.mp (hs x hx)).2 y (mem_of_single? hy)
      · exact absurd hxu (by simp)
    · exact absurd hxu (by simp)
  · exact flGet_value (P := fun z => ¬ B z) hl.1 h

theorem findConcRow_avoids {B : Var → Prop} {l : Lookups} {k : SSet Lbl} {w : Nat}
    (hl : LkAvoids B l) (h : findConcRow l k = some w) : ¬ B w := by
  unfold findConcRow at h
  split at h
  · exact absurd h (by simp)
  · split at h
    · exact flGet_value (P := fun z => ¬ B z) hl.2 h
    · exact absurd h (by simp)

/-! ### 7.2 `learnPartitions`

`disjunction` is excluded by the shipped flag, exactly as `RefineLearn.step_refines_all`
excludes it: the RULE is fine (`disjunction_avoids` above), but its two call sites are inner
folds over `proc` whose plumbing would double the length of this proof for a branch the
plan's "Known scope limits" already scopes to seeds. -/

theorem learnPartitions_avoids {B : Var → Prop} {fl : Flags} {ns : Names} {env : Env}
    {v : Nat} {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hdj : fl.disjRule = false)
    (hok : SupOk su) (hsu : SupAvoids B su) (hv : ¬ B v)
    (hr1 : ∀ w ∈ rhs1.abstr.elems, ¬ B w)
    (hi : ∀ x ∈ incm.elems, Avoids B x.toConstraint)
    (hp : ∀ x ∈ proc.elems, Avoids B x.toConstraint)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ∀ x ∈ S.elems, Avoids B x.toConstraint := by
  simp only [learnPartitions] at h
  split at h
  · obtain ⟨S0, hS0, h2⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
    obtain ⟨rfl, -⟩ := h2
    exact selfSubstitution_avoids hr1 hS0
  · have hlk : LkAvoids B (mkLookups v incm proc) := mkLookups_avoids hi hp
    have hcr : ∀ k w, (if fl.splitRow || fl.resRow then
        findConcRow (mkLookups v incm proc) k else none) = some w → ¬ B w := by
      intro k w hw
      split at hw
      · exact findConcRow_avoids hlk hw
      · exact absurd hw (by simp)
    refine (foldl_except_inv
      (P := fun (a : SSet LPart × Sup) =>
        (∀ x ∈ a.1.elems, Avoids B x.toConstraint) ∧ SupOk a.2 ∧ SupAvoids B a.2)
      (Q := fun (x : LPart) => Avoids B x.toConstraint) ?_ _ hp _ ?_ _ h).1
    · intro acc p2 hp2 hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        obtain ⟨aS, asu⟩ := a
        have haP := hacc _ hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        have hp2A := avoids_toConstraint_iff.mp hp2
        split at hb
        · have hrs := resolution_avoids (B := B) (fl := fl) (v := v) (rhs1 := rhs1)
            (rhs2 := p2.rhs)
            (resolvent := fun k => findResolvent v (mkLookups v incm proc) aS k)
            (concRow := fun k => if fl.splitRow || fl.resRow then
              findConcRow (mkLookups v incm proc) k else none)
            (emptyRow := fun k => if fl.emptyRow then
              findEmptyRow env (mkLookups v incm proc) k else none)
            haP.2.1 haP.2.2 hv hr1 hp2A.2
            (fun k w hw => findResolvent_avoids hlk haP.1 hw) hcr
          have hcan := cancellation_avoids (B := B) (v := v) hr1 hp2A.2
          simp only [hdj, Bool.not_false, eq_self_iff_true, if_true,
            pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          refine ⟨fun x hx => ?_, hrs.2.1, hrs.2.2⟩
          rcases SSet.mem_concat hx with hx' | hx'
          · rcases SSet.mem_concat hx' with hx'' | hx''
            · rcases SSet.mem_concat hx'' with hx3 | hx3
              · exact haP.1 x hx3
              · exact hrs.1 x hx3
            · exact hcan x hx''
          · exact absurd hx' (by simp [SSet.empty])
        · have hcse := commonSubexpression_avoids (B := B) (fl := fl) (v := v) (rhs1 := rhs1)
            (u := p2.lhs) (rhs2 := p2.rhs)
            (rhss := fun r => findRHS3 incm proc aS r)
            haP.2.1 haP.2.2 hv hp2A.1 hr1 hp2A.2
            (fun r w hw => findRHS3_avoids hi hp haP.1 hw)
          cases hsub : substitution v rhs1 p2.lhs p2.rhs with
          | error m => rw [hsub] at hb; simp only [Except.bind] at hb; exact absurd hb (by simp)
          | ok sps =>
            rw [hsub] at hb
            simp only [Except.bind, hdj, Bool.not_false, eq_self_iff_true,
              if_true, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            refine ⟨fun x hx => ?_, hcse.2.1, hcse.2.2⟩
            rcases SSet.mem_concat hx with hx' | hx'
            · rcases SSet.mem_concat hx' with hx'' | hx''
              · rcases SSet.mem_concat hx'' with hx3 | hx3
                · exact haP.1 x hx3
                · exact hcse.1 x hx3
              · exact substitution_avoids hv hp2A.1 hr1 hp2A.2 hsub x hx''
            · exact absurd hx' (by simp [SSet.empty])
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      exact splitConcrete_avoids (B := B) hok hsu hv hr1
        (fun r w hw => findRHS3_avoids hi hp (fun x hx => absurd hx (by simp [SSet.empty])) hw)
        (fun k w hw => findResolvent_avoids hlk
          (fun x hx => absurd hx (by simp [SSet.empty])) hw) hcr

/-! ## 8. `QueueHygiene` is preserved by `step`

This is the theorem `B1-FIX.md` §5a leaves to round 3, and the one that certifies the fix:
with `makeEmpty`'s propagation excluding the emptied variable it goes through, and the
`makeEmpty` case is the only one that needed the change. -/

theorem bound_mem_allVars {s : State} {v : Nat} (h : s.env.contains v = true) :
    v ∈ allVars (sys s) := by
  obtain ⟨b, hb, hbv⟩ := Env.contains_iff.mp h
  obtain ⟨w, val⟩ := b
  have hm := mem_sys_of_env (s := s) hb
  subst hbv
  cases val with
  | emptyRow => exact lhs_mem_allVars hm
  | «alias» u => exact lhs_mem_allVars hm

theorem supAvoids_bound {s : State} (hfr : SupFresh s.su (sys s)) :
    SupAvoids (Bound s.env) s.su :=
  supAvoids_of_supFresh hfr (fun _ hv => bound_mem_allVars hv)

/-- **`QueueHygiene` is preserved by every `continue` step.** -/
theorem step_queueHygiene {s s' : State} (hdj : s.flags.disjRule = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : step s = .continue s') : QueueHygiene s' := by
  rw [queueHygiene_iff] at h0 ⊢
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h0 x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h0 x (List.mem_append_right _ hx)
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (PQueue.dequeue_mem hdq).1
    have hrestMem : ∀ x ∈ rest.elems, x ∈ s.incm.elems := (PQueue.dequeue_mem hdq).2
    have hrest : ∀ x ∈ rest.elems, Avoids (Bound s.env) x.toConstraint :=
      fun x hx => hi0 x (hrestMem x hx)
    have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
    split at h
    · rename_i u hu
      have huB : ¬ Bound s.env u := findRHS_avoids hp0 hu
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
          intro x hx
          rcases List.mem_append.mp hx with hx' | hx'
          · exact hrest x hx'
          · exact hp0 x hx'
        · rename_i hne
          have hvu : r.lhs ≠ u := by simpa using hne
          obtain ⟨hni, hnp⟩ := instantiate_avoids hvu huB hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs (.alias u) := (instantiate_env_len hres).2.2
          intro x hx
          refine Avoids.mono (B := fun w => Bound s.env w ∨ w = r.lhs) ?_ ?_
          · intro w0 hw0
            rw [Bound, henv] at hw0
            exact Env.contains_instantiate.mp hw0
          · rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx'
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨hni, hnp⟩ := makeEmpty_avoids hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs .emptyRow := (makeEmpty_env_len hres).2.2
          intro x hx
          refine Avoids.mono (B := fun w => Bound s.env w ∨ w = r.lhs) ?_ ?_
          · intro w0 hw0
            rw [Bound, henv] at hw0
            exact Env.contains_instantiate.mp hw0
          · rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx'
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨hni, hnp⟩ := makeConcrete_avoids hrA.1 hrest hp0 hres
            intro x hx
            rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx'
        · split at h
          · rename_i u hsg
            have huB : ¬ Bound s.env u := by
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
                intro x hx
                rcases List.mem_append.mp hx with hx' | hx'
                · exact hrest x hx'
                · exact hp0 x hx'
              · rename_i hne
                have hvu : u ≠ r.lhs := by simpa using hne
                obtain ⟨hni, hnp⟩ := instantiate_avoids hvu hrA.1 hrest hp0 hres
                have henv : e = s.env.instantiate u (.alias r.lhs) := (instantiate_env_len hres).2.2
                intro x hx
                refine Avoids.mono (B := fun w => Bound s.env w ∨ w = u) ?_ ?_
                · intro w0 hw0
                  rw [Bound, henv] at hw0
                  exact Env.contains_instantiate.mp hw0
                · rcases List.mem_append.mp hx with hx' | hx'
                  · exact hni x hx'
                  · exact hnp x hx'
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              have hlearn := learnPartitions_avoids hdj hok (supAvoids_bound hfr) hrA.1 hrA.2
                hrest hp0 hlp
              intro x hx
              simp only [foldl_log_env]
              rcases List.mem_append.mp hx with hx' | hx'
              · exact concatP_avoids _ hrest
                  (fun d hd => hlearn d (SSet.mem_filter hd)) x hx'
              · exact insertNP_avoids hp0 (hi0 r hrMem) hx'

/-- The brief's name for the theorem above. -/
theorem QueueHygiene.step {s s' : State} (hdj : s.flags.disjRule = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : Rowpartition.Loop.step s = .continue s') : QueueHygiene s' :=
  step_queueHygiene hdj hok hfr h0 h

/-! ## 9. From the initial states, and the corollary about the panic -/

/-- **Every state `Seed.solve` builds is hygienic**: it starts with an EMPTY environment
(`Seed.lean:135`, `env := {}`), so there is nothing for a partition to mention.  Note this is
"every state the seed loader builds", not "every `Wf` initial state" -- `Wf` is `QOk` on both
queues plus `LblCoh` and says nothing about `env` (`L5-REVIEW.md` round 3, Q-2). -/
theorem queueHygiene_of_env_nil {s : State} (h : s.env.binds = []) : QueueHygiene s := by
  intro p _ v hv
  exact absurd (Env.contains_iff.mp hv) (by rw [h]; simp)

theorem queueHygiene_initial {q : PQueue} (fl : Flags) (ns : Names) (site : String) (su : Sup)
    (lo : Nat) (t : List String) :
    QueueHygiene { incm := q, proc := PQueue.empty, env := {}, su := su, trace := t,
                   flags := fl, names := ns, site := site, su0 := lo } :=
  queueHygiene_of_env_nil rfl

/-- **Hygiene holds at every state a run reaches** -- CONDITIONALLY.  `RunSupOk n s` is
`RefineLearn.lean`'s per-state supply hypothesis (`SupOk` and `SupFresh` at every state of the
run), which L3 records is NOT an invariant; it is what the `learn` branch of
`step_queueHygiene` needs, and it is not discharged anywhere.  So this theorem, and with it the
unreachability of the reinstantiation panic along a whole run, is conditional on `RunSupOk` and
on `disjRule = false` (`L5-REVIEW.md` round 3, Q-1).  `step_queueHygiene` itself carries only
the single-state `SupOk`/`SupFresh`. -/
theorem run_queueHygiene : ∀ (n : Nat) {s : State}, s.flags.disjRule = false → RunSupOk n s →
    QueueHygiene s → ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → QueueHygiene s'
  | 0, s, _, _, hq, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact hq
  | n + 1, s, hdj, hb, hq, s', hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [step_done hst]
        exact hq
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      refine run_queueHygiene n ?_ (hb.2.2 s0 hst)
        (step_queueHygiene hdj hb.1 hb.2.1 hq hst) s' hres
      rw [step_flags hst]; exact hdj

/-- A `died` step changes nothing but the trace, so hygiene survives a REFUTATION too. -/
theorem step_died_parts {s s' : State} {m : String} (h : Rowpartition.Loop.step s = .died m s') :
    s'.parts = s.parts ∧ s'.env = s.env := by
  simp only [step, State.log] at h
  repeat' split at h
  all_goals (cases h <;> exact ⟨rfl, rfl⟩)

theorem step_died_queueHygiene {s s' : State} {m : String} (h0 : QueueHygiene s)
    (h : Rowpartition.Loop.step s = .died m s') : QueueHygiene s' := by
  obtain ⟨hp, he⟩ := step_died_parts h
  intro p hpm v hv
  rw [hp] at hpm
  rw [he] at hv
  exact h0 p hpm v hv

/-- **Hygiene holds at every state a run reaches, refutations included** -- under the same
unproved `RunSupOk` hypothesis as `run_queueHygiene`. -/
theorem run_queueHygiene' : ∀ (n : Nat) {s : State}, s.flags.disjRule = false → RunSupOk n s →
    QueueHygiene s → ∀ s' m, run s n = .rejected m s' → QueueHygiene s'
  | 0, s, _, _, _, s', m, hres => by
    simp only [run] at hres; exact absurd hres (by simp)
  | n + 1, s, hdj, hb, hq, s', m, hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0 => rw [hst] at hres; exact absurd hres (by simp)
    | died m0 s0 =>
      rw [hst] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨-, rfl⟩ := hres
      exact step_died_queueHygiene hq hst
    | «continue» s0 =>
      rw [hst] at hres
      refine run_queueHygiene' n ?_ (hb.2.2 s0 hst)
        (step_queueHygiene hdj hb.1 hb.2.1 hq hst) s' m hres
      rw [step_flags hst]; exact hdj

/-- **The reinstantiation panic is unreachable from a hygienic state.**  `instantiateType`'s
`die` fires exactly when the variable the step is about to bind is already bound, and every
one of the three variables a `step` can bind -- the dequeued left-hand side (`makeEmpty` at
the `empty` branch, `instantiate` at `common`), its lone variable part (`instantiate` at
`unify`) and the `common` partner -- is unbound at a hygienic state.  With
`run_queueHygiene` and `queueHygiene_initial` this closes `B1-FIX.md`'s open item: the panic
`L5-TERMINATION.md` §0 exhibits on the UNFIXED compiler has no path on the fixed one. -/
theorem queueHygiene_binds_unbound {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) :
    s.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → s.env.contains u = false) ∧
      (∀ u, s.proc.findRHS r.rhs = some u → s.env.contains u = false) := by
  have hrMem : r ∈ s.incm.elems := (PQueue.dequeue_mem hdq).1
  rw [queueHygiene_iff] at h
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h x (List.mem_append_right _ hx)
  have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
  refine ⟨?_, ?_, ?_⟩
  · cases hc : s.env.contains r.lhs with
    | false => rfl
    | true => exact absurd hc hrA.1
  · intro u hu
    cases hc : s.env.contains u with
    | false => rfl
    | true => exact absurd hc (hrA.2 u (contains_nat_iff.mp hu))
  · intro u hu
    cases hc : s.env.contains u with
    | false => rfl
    | true => exact absurd hc (findRHS_avoids hp0 hu)

/-- `instantiate`'s ONLY error is the reinstantiation panic, so at an unbound variable it
always succeeds. -/
theorem instantiate_ok_of_unbound {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    (h : env.contains v = false) :
    ∃ ni np, instantiate ns v u incm proc env
      = .ok (ni, np, env.instantiate v (.alias u)) := by
  simp only [instantiate]
  rw [if_neg (by simp [h])]
  exact ⟨_, _, rfl⟩

/-- **At a hygienic state neither link branch can die.**  This is the sharpest form of the
corollary: `instantiate` has exactly one error arm, and `queueHygiene_binds_unbound` says the
variable it is about to bind is unbound at both of its call sites. -/
theorem step_link_no_death {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) :
    (∀ u, s.proc.findRHS r.rhs = some u →
        ∃ w, unifyVars s.names r.lhs u rest s.proc s.env = .ok w) ∧
      (∀ u, r.rhs.single? = some u →
        ∃ w, unifyVars s.names u r.lhs rest s.proc s.env = .ok w) := by
  obtain ⟨hlhs, habs, hcom⟩ := queueHygiene_binds_unbound h hdq
  refine ⟨fun u _ => ?_, fun u hu => ?_⟩
  · unfold unifyVars
    split
    · exact ⟨_, rfl⟩
    · obtain ⟨ni, np, hok⟩ := instantiate_ok_of_unbound (ns := s.names) (u := u)
        (incm := rest) (proc := s.proc) hlhs
      exact ⟨_, hok⟩
  · have huB : s.env.contains u = false := by
      refine habs u ?_
      have : r.rhs.abstr.single? = some u := by
        unfold RHS.single? at hu
        split at hu
        · exact hu
        · exact absurd hu (by simp)
      exact contains_nat_iff.mpr (mem_of_single? this)
    unfold unifyVars
    split
    · exact ⟨_, rfl⟩
    · obtain ⟨ni, np, hok⟩ := instantiate_ok_of_unbound (ns := s.names) (u := r.lhs)
        (incm := rest) (proc := s.proc) huB
      exact ⟨_, hok⟩

end Rowpartition.Loop
