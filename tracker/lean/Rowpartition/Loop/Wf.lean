/-
# L3 (iv): the well-formedness invariant `Wf`

`Loop/Bridge.lean` proves the fact the refinement needs -- the model's own partition
equality IS equality of the `Rowpartition.Constraint`s -- but only under five side
hypotheses: four `Nodup`s (both `SSet`s of both partitions) and `LblCoh` (two labels of one
solve with the same table index are the same label).  L1's review (F6) and L2's (F5) both
recorded that nothing tied those hypotheses to `step`.

This file ties them: `Wf : State -> Prop` collects exactly those five, `wf_seed` /
`wf_replay` prove it for every state the model can start from, `step_wf` proves it preserved
by every `continue` step, and `LPart.eqv_iff_toConstraint_of_wf` is the bridge's result
restated for a well-formed state with NO side hypotheses.
-/
import Rowpartition.Loop.Bridge
import Rowpartition.Loop.Replay

namespace Rowpartition.Loop

open Rowpartition

/- `simp only [bind, Except.bind]` is what unfolds an `Except` `do` block here.  Which of the
two names does the work depends on whether the term reached this point as `>>=` or as the
already-projected `Except.bind`, so both are always listed; the linter would ask for the
other one to be dropped in each case. -/
set_option linter.unusedSimpArgs false

/-! ## 1. Membership in the `SSet` operations

Every operation the loop performs on a set produces elements that were already in one of its
arguments.  That is what makes the label pool shrink, which is what makes `LblCoh` an
invariant. -/

namespace SSet

variable {α : Type} [SVal α]

theorem mem_champ {xs : List α} {x : α} : x ∈ champ xs ↔ x ∈ xs := (champ_perm xs).mem_iff

theorem mem_incl {s : SSet α} {x y : α} (h : x ∈ (s.incl y).elems) :
    x ∈ s.elems ∨ x = y := by
  unfold incl at h
  split at h
  · exact Or.inl h
  · split at h
    · have := mem_champ.mp h
      simpa using this
    · simpa using h

theorem mem_filter {s : SSet α} {p : α → Bool} {x : α} (h : x ∈ (s.filter p).elems) :
    x ∈ s.elems := by
  unfold SSet.filter at h
  split at h
  · exact List.mem_of_mem_filter (mem_champ.mp h)
  · exact List.mem_of_mem_filter h

theorem mem_excl {s : SSet α} {y x : α} (h : x ∈ (s.excl y).elems) : x ∈ s.elems := by
  unfold excl at h
  split at h
  · exact List.mem_of_mem_filter (mem_champ.mp h)
  · exact List.mem_of_mem_filter h

theorem mem_inter {s t : SSet α} {x : α} (h : x ∈ (s.inter t).elems) : x ∈ s.elems :=
  mem_filter h

theorem mem_foldl_incl :
    ∀ (l : List α) (s : SSet α) {x : α}, x ∈ (l.foldl incl s).elems → x ∈ s.elems ∨ x ∈ l
  | [], _, _, h => Or.inl h
  | y :: l, s, x, h => by
    rcases mem_foldl_incl l (s.incl y) h with h' | h'
    · rcases mem_incl h' with h'' | rfl
      · exact Or.inl h''
      · exact Or.inr (by simp)
    · exact Or.inr (by simp [h'])

theorem mem_pickRep (S T : List α) (x : α) : pickRep S T x = x ∨ pickRep S T x ∈ S := by
  unfold pickRep
  cases hf : S.find? (fun y => SVal.eq y x) with
  | none => exact Or.inl rfl
  | some sx =>
    simp only
    split
    · exact Or.inl rfl
    · exact Or.inr (List.mem_of_find?_eq_some hf)

theorem mem_concat {s t : SSet α} {x : α} (h : x ∈ (s.concat t).elems) :
    x ∈ s.elems ∨ x ∈ t.elems := by
  unfold concat at h
  split at h
  · obtain ⟨y, hy, rfl⟩ := List.mem_map.mp h
    have hy' : y ∈ (s.elems.filter (fun z => !t.contains z)) ++ t.elems := mem_champ.mp hy
    rcases mem_pickRep s.elems t.elems y with hp | hp
    · rw [hp]
      rcases List.mem_append.mp hy' with hh | hh
      · exact Or.inl (List.mem_of_mem_filter hh)
      · exact Or.inr hh
    · exact Or.inl hp
  · rcases mem_foldl_incl t.elems s h with h' | h'
    · exact Or.inl h'
    · exact Or.inr h'

theorem mem_foldl_excl :
    ∀ (l : List α) (s : SSet α) {x : α}, x ∈ (l.foldl excl s).elems → x ∈ s.elems
  | [], _, _, h => h
  | y :: l, s, _, h => mem_excl (mem_foldl_excl l (s.excl y) h)

theorem mem_removedAll {s t : SSet α} {x : α} (h : x ∈ (s.removedAll t).elems) :
    x ∈ s.elems := mem_foldl_excl t.elems s h

theorem mem_ofList {xs : List α} {x : α} (h : x ∈ (ofList xs).elems) : x ∈ xs := by
  rcases mem_foldl_incl xs empty h with h' | h'
  · cases h'
  · exact h'

omit [SVal α] in
theorem mem_map {β : Type} [SVal β] {s : SSet α} {f : α → β} {y : β}
    (h : y ∈ (s.map f).elems) : ∃ x ∈ s.elems, f x = y := by
  unfold SSet.map at h
  have hgen : ∀ (l : List α) (acc : SSet β),
      y ∈ ((l.foldl (fun a x => a.incl (f x)) acc).elems) →
      y ∈ acc.elems ∨ ∃ x ∈ l, f x = y := by
    intro l
    induction l with
    | nil => intro acc hy; exact Or.inl hy
    | cons z l ih =>
      intro acc hy
      rcases ih _ hy with h' | ⟨x, hx, hfx⟩
      · rcases mem_incl h' with h'' | rfl
        · exact Or.inl h''
        · exact Or.inr ⟨z, by simp, rfl⟩
      · exact Or.inr ⟨x, by simp [hx], hfx⟩
  rcases hgen s.elems ⟨s.hashed, []⟩ h with h' | h'
  · cases h'
  · exact h'

end SSet


/-! ## 2. The two per-object conditions

`COk L s`: the label set is duplicate-free and drawn from the pool `L`.
`POk L p`: the partition's variable set is duplicate-free and its label set is `COk`. -/

/-- A label set that is duplicate-free and drawn from the pool `L`. -/
structure COk (L : List Lbl) (s : SSet Lbl) : Prop where
  nodup : s.Nodup
  sub : ∀ x ∈ s.elems, x ∈ L

/-- A partition whose two sets are duplicate-free and whose labels come from the pool. -/
structure POk (L : List Lbl) (p : LPart) : Prop where
  abstr : p.rhs.abstr.Nodup
  conc : COk L p.rhs.conc

namespace COk

variable {L L' : List Lbl} {s t : SSet Lbl}

theorem mono (hL : ∀ x ∈ L, x ∈ L') (h : COk L s) : COk L' s :=
  ⟨h.nodup, fun x hx => hL x (h.sub x hx)⟩

theorem empty : COk L (SSet.empty : SSet Lbl) := ⟨SSet.nodup_empty, by simp [SSet.empty]⟩

theorem concat (hs : COk L s) (ht : COk L t) : COk L (s.concat t) :=
  ⟨SSet.nodup_concat hs.nodup ht.nodup, fun x hx => by
    rcases SSet.mem_concat hx with h | h
    · exact hs.sub x h
    · exact ht.sub x h⟩

theorem filter (hs : COk L s) (p : Lbl → Bool) : COk L (s.filter p) :=
  ⟨SSet.nodup_filter hs.nodup p, fun x hx => hs.sub x (SSet.mem_filter hx)⟩

theorem inter (hs : COk L s) (t : SSet Lbl) : COk L (s.inter t) := hs.filter _

theorem removedAll (hs : COk L s) (t : SSet Lbl) : COk L (s.removedAll t) :=
  ⟨SSet.nodup_removedAll hs.nodup, fun x hx => hs.sub x (SSet.mem_removedAll hx)⟩

theorem excl (hs : COk L s) (y : Lbl) : COk L (s.excl y) :=
  ⟨SSet.nodup_excl hs.nodup y, fun x hx => hs.sub x (SSet.mem_excl hx)⟩

theorem incl (hs : COk L s) {y : Lbl} (hy : y ∈ L) : COk L (s.incl y) :=
  ⟨SSet.nodup_incl hs.nodup y, fun x hx => by
    rcases SSet.mem_incl hx with h | rfl
    · exact hs.sub x h
    · exact hy⟩

theorem ofList {xs : List Lbl} (h : ∀ x ∈ xs, x ∈ L) : COk L (SSet.ofList xs) :=
  ⟨SSet.nodup_ofList xs, fun x hx => h x (SSet.mem_ofList hx)⟩

end COk

namespace POk

variable {L L' : List Lbl} {p : LPart}

theorem mono (hL : ∀ x ∈ L, x ∈ L') (h : POk L p) : POk L' p := ⟨h.abstr, h.conc.mono hL⟩

/-- A partition with an empty right-hand side is well formed at every pool. -/
theorem ofEmpty (v : Nat) (i : Option Inference) : POk L ⟨v, RHS.empty, i⟩ :=
  ⟨SSet.nodup_empty, COk.empty⟩

theorem mk' {v : Nat} {a : SSet Nat} {c : SSet Lbl} {i : Option Inference}
    (ha : a.Nodup) (hc : COk L c) : POk L ⟨v, ⟨a, c⟩, i⟩ := ⟨ha, hc⟩

/-- Retagging or renaming the left-hand side changes nothing. -/
theorem retag {v : Nat} {i : Option Inference} (h : POk L p) : POk L ⟨v, p.rhs, i⟩ := ⟨h.abstr, h.conc⟩

/-- Erasing a variable. -/
theorem erase (h : POk L p) (v : Nat) {u : Nat} {i : Option Inference} :
    POk L ⟨u, p.rhs.erase v, i⟩ :=
  ⟨SSet.nodup_excl h.abstr v, h.conc⟩

end POk

/-! ## 3. The same, lifted to sets and queues of partitions -/

/-- Every partition of an `SSet` is well formed. -/
def SOk (L : List Lbl) (s : SSet LPart) : Prop := ∀ p ∈ s.elems, POk L p

/-- Every partition of a queue is well formed. -/
def QOk (L : List Lbl) (q : PQueue) : Prop := ∀ p ∈ q.elems, POk L p

theorem SOk.mono {L L' : List Lbl} {s : SSet LPart} (hL : ∀ x ∈ L, x ∈ L')
    (h : SOk L s) : SOk L' s := fun p hp => (h p hp).mono hL

theorem QOk.mono {L L' : List Lbl} {q : PQueue} (hL : ∀ x ∈ L, x ∈ L')
    (h : QOk L q) : QOk L' q := fun p hp => (h p hp).mono hL

theorem SOk.empty {L : List Lbl} : SOk L (SSet.empty : SSet LPart) := by
  intro p hp; cases hp

theorem SOk.incl {L : List Lbl} {s : SSet LPart} {p : LPart} (hs : SOk L s) (hp : POk L p) :
    SOk L (s.incl p) := by
  intro q hq
  rcases SSet.mem_incl hq with h | rfl
  · exact hs q h
  · exact hp

theorem SOk.concat {L : List Lbl} {s t : SSet LPart} (hs : SOk L s) (ht : SOk L t) :
    SOk L (s.concat t) := by
  intro q hq
  rcases SSet.mem_concat hq with h | h
  · exact hs q h
  · exact ht q h

theorem SOk.filter {L : List Lbl} {s : SSet LPart} (hs : SOk L s) (f : LPart → Bool) :
    SOk L (s.filter f) := fun q hq => hs q (SSet.mem_filter hq)

theorem SOk.ofList {L : List Lbl} {ps : List LPart} (h : ∀ p ∈ ps, POk L p) :
    SOk L (SSet.ofList ps) := fun q hq => h q (SSet.mem_ofList hq)

theorem SOk.map {L : List Lbl} {s : SSet Nat} {f : Nat → LPart} (h : ∀ v, POk L (f v)) :
    SOk L (s.map f) := by
  intro q hq
  obtain ⟨x, -, rfl⟩ := SSet.mem_map hq
  exact h x

theorem QOk.filter {L : List Lbl} {q : PQueue} (h : QOk L q) (f : LPart → Bool) :
    QOk L (q.filter f) := fun p hp => h p (List.mem_of_mem_filter hp)

theorem QOk.partition_fst {L : List Lbl} {q : PQueue} (h : QOk L q) (f : LPart → Bool) :
    SOk L (q.partition f).1 := by
  intro p hp
  have := SSet.mem_ofList hp
  exact h p (List.mem_of_mem_filter (List.mem_reverse.mp this))

theorem QOk.partition_snd {L : List Lbl} {q : PQueue} (h : QOk L q) (f : LPart → Bool) :
    QOk L (q.partition f).2 := fun p hp => h p (List.mem_of_mem_filter hp)

theorem SOk.trim {L : List Lbl} {s : SSet LPart} {q : PQueue} (h : SOk L s) :
    SOk L (trim s q) := h.filter _

theorem mem_insertSorted {p x : LPart} :
    ∀ {l : List LPart}, x ∈ PQueue.insertSorted p l → x = p ∨ x ∈ l
  | [], h => Or.inl (by simp [PQueue.insertSorted] at h; exact h)
  | y :: l, h => by
    unfold PQueue.insertSorted at h
    split at h
    · rcases List.mem_cons.mp h with rfl | h'
      · exact Or.inr (by simp)
      · rcases mem_insertSorted h' with h'' | h''
        · exact Or.inl h''
        · exact Or.inr (by simp [h''])
    · rcases List.mem_cons.mp h with rfl | h'
      · exact Or.inl rfl
      · exact Or.inr h'

theorem QOk.insertNP {L : List Lbl} {q : PQueue} {p : LPart} (hq : QOk L q) (hp : POk L p) :
    QOk L (q.insertNP p) := by
  intro x hx
  unfold PQueue.insertNP at hx
  split at hx
  · exact hq x hx
  · split at hx
    · exact hq x hx
    · rcases mem_insertSorted hx with rfl | h
      · exact hp
      · exact hq x h

theorem QOk.insertP {L : List Lbl} {q : PQueue} {p : LPart} (hq : QOk L q) (hp : POk L p) :
    QOk L (q.insertP p) := by
  intro x hx
  unfold PQueue.insertP at hx
  split at hx
  · exact hq x hx
  · split at hx
    · exact hq x hx
    · split at hx
      · exact QOk.insertNP hq (POk.mk' (SSet.nodup_ofList _) COk.empty) x hx
      · rcases mem_insertSorted hx with rfl | h
        · exact hp
        · exact hq x h

theorem QOk.concatNP {L : List Lbl} :
    ∀ (ps : List LPart) (q : PQueue), QOk L q → (∀ p ∈ ps, POk L p) → QOk L (q.concatNP ps)
  | [], _, hq, _ => hq
  | p :: ps, q, hq, hp =>
    QOk.concatNP ps (q.insertNP p) (QOk.insertNP hq (hp p (by simp)))
      (fun r hr => hp r (by simp [hr]))

theorem QOk.concatP {L : List Lbl} :
    ∀ (ps : List LPart) (q : PQueue), QOk L q → (∀ p ∈ ps, POk L p) → QOk L (q.concatP ps)
  | [], _, hq, _ => hq
  | p :: ps, q, hq, hp =>
    QOk.concatP ps (q.insertP p) (QOk.insertP hq (hp p (by simp)))
      (fun r hr => hp r (by simp [hr]))

theorem QOk.ofList {L : List Lbl} {ps : List LPart} (h : ∀ p ∈ ps, POk L p) :
    QOk L (PQueue.ofList ps) := QOk.concatNP ps PQueue.empty (fun p hp => by cases hp) h

/-- Everything a dequeue returns was in the queue. -/
theorem PQueue.dequeue_mem {q : PQueue} {r : LPart} {rest : PQueue}
    (hd : q.dequeue = some (r, rest)) : r ∈ q.elems ∧ ∀ x ∈ rest.elems, x ∈ q.elems := by
  simp only [PQueue.dequeue] at hd
  split at hd
  · exact absurd hd (by simp)
  · rename_i e0 rest0 he
    split at hd
    · exact absurd hd (by simp)
    · rename_i i hi
      split at hd
      · exact absurd hd (by simp)
      · rename_i p hp
        rw [Option.some_inj, Prod.mk.injEq] at hd
        obtain ⟨rfl, hrest⟩ := hd
        refine ⟨by rw [he]; exact List.mem_of_getElem? hp, ?_⟩
        intro x hx
        rw [← hrest] at hx
        exact he ▸ ((List.eraseIdx_sublist _ i).subset hx)

theorem QOk.dequeue {L : List Lbl} {q : PQueue} {r : LPart} {rest : PQueue}
    (h : QOk L q) (hd : q.dequeue = some (r, rest)) : POk L r ∧ QOk L rest := by
  obtain ⟨h1, h2⟩ := PQueue.dequeue_mem hd
  exact ⟨h r h1, fun x hx => h x (h2 x hx)⟩


/-! ## 4. Every rule preserves the two conditions

A rule builds its conclusions out of the sets of its premises, by union, difference,
intersection and single insertions -- never out of thin air.  So both conditions travel
through every rule, and in particular the LABEL POOL never grows. -/

/-- The right-hand side of a partition, as the two conditions. -/
structure ROk (L : List Lbl) (r : RHS) : Prop where
  abstr : r.abstr.Nodup
  conc : COk L r.conc

theorem POk.rhsOk {L : List Lbl} {p : LPart} (h : POk L p) : ROk L p.rhs := ⟨h.abstr, h.conc⟩

theorem ROk.part {L : List Lbl} {r : RHS} (h : ROk L r) (v : Nat) (i : Option Inference) :
    POk L (⟨v, r, i⟩ : LPart) := ⟨h.abstr, h.conc⟩

theorem ROk.empty {L : List Lbl} : ROk L RHS.empty := ⟨SSet.nodup_empty, COk.empty⟩

theorem ROk.ofAbstr {L : List Lbl} {a : SSet Nat} (h : a.Nodup) : ROk L (RHS.ofAbstr a) :=
  ⟨h, COk.empty⟩

theorem ROk.ofConcr {L : List Lbl} {c : SSet Lbl} (h : COk L c) : ROk L (RHS.ofConcr c) :=
  ⟨SSet.nodup_empty, h⟩

theorem ROk.erase {L : List Lbl} {r : RHS} (h : ROk L r) (v : Nat) : ROk L (r.erase v) :=
  ⟨SSet.nodup_excl h.abstr v, h.conc⟩

theorem rhsMerge_ok {L : List Lbl} {r t : RHS} {n : RHS} {es : SSet Nat}
    (hr : ROk L r) (ht : ROk L t) (h : rhsMerge r t = .ok (n, es)) : ROk L n := by
  simp only [rhsMerge] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, -⟩ := h
    exact ⟨SSet.nodup_removedAll (SSet.nodup_concat hr.abstr ht.abstr),
      hr.conc.concat ht.conc⟩
  · exact absurd h (by simp)

theorem rhsSubstitute_ok {L : List Lbl} {r t n : RHS} {v : Nat} {es : SSet Nat}
    (hr : ROk L r) (ht : ROk L t) (h : rhsSubstitute r v t = .ok (n, es)) : ROk L n := by
  simp only [rhsSubstitute] at h
  split at h
  · exact rhsMerge_ok (hr.erase v) ht h
  · rw [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, -⟩ := h
    exact hr

theorem selfSubstitution_ok {L : List Lbl} {ns : Names} {v : Nat} {a : SSet Nat}
    {c : SSet Lbl} {S : SSet LPart} (h : selfSubstitution ns v a c = .ok S) : SOk L S := by
  simp only [selfSubstitution] at h
  split at h
  · rw [Except.ok.injEq] at h
    subst h
    exact SOk.map (fun _ => POk.ofEmpty _ _)
  · exact absurd h (by simp)

theorem cancellation_ok {L : List Lbl} {v : Nat} {r t : RHS} (hr : ROk L r) (ht : ROk L t) :
    SOk L (cancellation v r t) := by
  simp only [cancellation]
  split
  · split
    · exact SOk.ofList (by
        intro p hp
        rw [List.mem_singleton] at hp
        subst hp
        exact POk.mk' (SSet.nodup_removedAll ht.abstr) (ht.conc.removedAll _))
    · exact SOk.empty
  · split
    · split
      · exact SOk.ofList (by
          intro p hp
          rw [List.mem_singleton] at hp
          subst hp
          exact POk.mk' (SSet.nodup_removedAll hr.abstr) (hr.conc.removedAll _))
      · exact SOk.empty
    · exact SOk.empty

theorem splitConcrete_ok {L : List Lbl} {fl : Flags} {v : Nat} {a : SSet Nat} {c : SSet Lbl}
    (ha : a.Nodup) (hc : COk L c) (rhss : RHS → Option Nat)
    (resolvent concRow emptyRow : SSet Lbl → Option Nat) (su : Sup) :
    SOk L (splitConcrete fl v a c rhss resolvent concRow emptyRow su).1 := by
  have hsingle : ∀ (w : Nat), (SSet.ofList [w]).Nodup := fun w => SSet.nodup_ofList _
  simp only [splitConcrete]
  split
  · exact SOk.empty
  · split
    · exact SOk.ofList (by
        intro p hp; rw [List.mem_singleton] at hp; subst hp
        exact POk.mk' (hsingle _) hc)
    · split
      · exact SOk.empty
      · split
        · exact SOk.ofList (by
            intro p hp; rw [List.mem_singleton] at hp; subst hp
            exact POk.mk' ha COk.empty)
        · split
          · exact SOk.ofList (by
              intro p hp; rw [List.mem_singleton] at hp; subst hp
              exact POk.mk' ha COk.empty)
          · split
            · exact SOk.map (fun _ => POk.ofEmpty _ _)
            · exact SOk.ofList (by
                intro p hp
                rcases List.mem_cons.mp hp with rfl | hp'
                · exact POk.mk' ha COk.empty
                · rw [List.mem_singleton] at hp'; subst hp'
                  exact POk.mk' (hsingle _) hc)

theorem resolution_ok {L : List Lbl} {fl : Flags} {v : Nat} {r t : RHS}
    (hr : ROk L r) (ht : ROk L t) (resolvent concRow emptyRow : SSet Lbl → Option Nat)
    (su : Sup) : SOk L (resolution fl v r t resolvent concRow emptyRow su).1 := by
  have hsingle : ∀ (w : Nat), (SSet.ofList [w]).Nodup := fun w => SSet.nodup_ofList _
  have htops : COk L (r.conc.removedAll (r.conc.inter t.conc)) := hr.conc.removedAll _
  have hbots : COk L (t.conc.removedAll (r.conc.inter t.conc)) := ht.conc.removedAll _
  have hall : COk L (r.conc.concat t.conc) := hr.conc.concat ht.conc
  simp only [resolution]
  split
  · exact SOk.empty
  · split
    · split
      · exact SOk.empty
      · split
        · exact SOk.ofList (by
            intro p hp
            rcases List.mem_cons.mp hp with rfl | hp'
            · exact POk.mk' (hsingle _) hbots
            · rw [List.mem_singleton] at hp'; subst hp'
              exact POk.mk' (hsingle _) htops)
        · split
          · exact SOk.ofList (by
              intro p hp
              rcases List.mem_cons.mp hp with rfl | hp'
              · exact POk.mk' (hsingle _) hbots
              · rw [List.mem_singleton] at hp'; subst hp'
                exact POk.mk' (hsingle _) htops)
          · split
            · exact SOk.ofList (by
                intro p hp
                rcases List.mem_cons.mp hp with rfl | hp'
                · exact ROk.part (ROk.ofConcr hbots) _ _
                · rw [List.mem_singleton] at hp'; subst hp'
                  exact ROk.part (ROk.ofConcr htops) _ _)
            · exact SOk.ofList (by
                intro p hp
                rcases List.mem_cons.mp hp with rfl | hp'
                · exact POk.mk' (hsingle _) hall
                · rcases List.mem_cons.mp hp' with rfl | hp''
                  · exact POk.mk' (hsingle _) hbots
                  · rw [List.mem_singleton] at hp''; subst hp''
                    exact POk.mk' (hsingle _) htops)
    · exact SOk.empty

theorem subBody_ok {L : List Lbl} {v u : Nat} {r t : RHS} {S : SSet LPart}
    (hr : ROk L r) (ht : ROk L t) (h : subBody v r u t = .ok S) : SOk L S := by
  simp only [subBody] at h
  split at h
  · cases hs : rhsSubstitute t v r with
    | error m => rw [hs] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨n, es⟩ := w
      rw [hs] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
      subst h
      exact SOk.incl (SOk.map (fun _ => POk.ofEmpty _ _))
        (ROk.part (rhsSubstitute_ok ht hr hs) _ _)
  · simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    exact SOk.empty

theorem substitution_ok {L : List Lbl} {v u : Nat} {r t : RHS} {S : SSet LPart}
    (hr : ROk L r) (ht : ROk L t) (h : substitution v r u t = .ok S) : SOk L S := by
  simp only [substitution] at h
  cases h1 : subBody v r u t with
  | error m => rw [h1] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
  | ok S1 =>
    cases h2 : subBody u t v r with
    | error m =>
      rw [h1, h2] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok S2 =>
      rw [h1, h2] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
      subst h
      exact SOk.concat (subBody_ok hr ht h1) (subBody_ok ht hr h2)

theorem commonSubexpression_ok {L : List Lbl} {fl : Flags} {v u : Nat} {r t : RHS}
    (hr : ROk L r) (ht : ROk L t) (rhss : RHS → Option Nat) (su : Sup) :
    SOk L (commonSubexpression fl v r u t rhss su).1 := by
  have h1 : ∀ z : Nat, ((r.abstr.removedAll (r.abstr.inter t.abstr)).incl z).Nodup :=
    fun z => SSet.nodup_incl (SSet.nodup_removedAll hr.abstr) z
  have h2 : ∀ z : Nat, ((t.abstr.removedAll (r.abstr.inter t.abstr)).incl z).Nodup :=
    fun z => SSet.nodup_incl (SSet.nodup_removedAll ht.abstr) z
  simp only [commonSubexpression]
  split
  · exact SOk.empty
  · split
    · exact SOk.ofList (by
        intro p hp
        rcases List.mem_cons.mp hp with rfl | hp'
        · exact POk.mk' (h1 _) hr.conc
        · rw [List.mem_singleton] at hp'; subst hp'
          exact POk.mk' (h2 _) ht.conc)
    · split
      · exact SOk.ofList (by
          intro p hp; rw [List.mem_singleton] at hp; subst hp
          exact POk.mk' (h2 _) ht.conc)
      · split
        · exact SOk.ofList (by
            intro p hp; rw [List.mem_singleton] at hp; subst hp
            exact POk.mk' (h1 _) hr.conc)
        · split
          · exact SOk.empty
          · exact SOk.ofList (by
              intro p hp
              rcases List.mem_cons.mp hp with rfl | hp'
              · exact POk.mk' (SSet.nodup_inter hr.abstr) COk.empty
              · rcases List.mem_cons.mp hp' with rfl | hp''
                · exact POk.mk' (h1 _) hr.conc
                · rw [List.mem_singleton] at hp''; subst hp''
                  exact POk.mk' (h2 _) ht.conc)

theorem disjunction_ok {L : List Lbl} {r t w : RHS} (hr : ROk L r) (hw : ROk L w) (su : Sup) :
    SOk L (disjunction r t w su).1 := by
  have habsc : ∀ z : Nat,
      (((r.abstr.inter t.abstr).removedAll ((r.abstr.inter t.abstr).inter w.abstr)).incl z).Nodup :=
    fun z => SSet.nodup_incl (SSet.nodup_removedAll (SSet.nodup_inter hr.abstr)) z
  have hconC : COk L ((r.conc.inter t.conc).removedAll ((r.conc.inter t.conc).inter w.conc)) :=
    (hr.conc.inter _).removedAll _
  simp only [disjunction]
  split
  · exact SOk.empty
  · split
    · exact SOk.empty
    · exact SOk.ofList (by
        intro p hp; rw [List.mem_singleton] at hp; subst hp
        exact POk.mk' (habsc _) hconC)
    · exact SOk.ofList (by
        intro p hp
        rcases List.mem_cons.mp hp with rfl | hp'
        · exact POk.mk'
            (SSet.nodup_removedAll (SSet.nodup_removedAll (SSet.nodup_removedAll hw.abstr)))
            COk.empty
        · rw [List.mem_singleton] at hp'; subst hp'
          exact POk.mk' (habsc _) hconC)

/-! ## 5. The step-level operations -/

/-- Folding an `Except`-valued function over a list: an invariant that survives one step of
the fold survives the whole fold. -/
theorem foldl_except_inv {α β : Type} {P : β → Prop} {Q : α → Prop}
    {f : Except String β → α → Except String β}
    (hf : ∀ (acc : Except String β) (x : α), Q x → (∀ b, acc = .ok b → P b) →
      ∀ b, f acc x = .ok b → P b) :
    ∀ (l : List α), (∀ x ∈ l, Q x) → ∀ (acc : Except String β),
      (∀ b, acc = .ok b → P b) → ∀ b, l.foldl f acc = .ok b → P b := by
  intro l
  induction l with
  | nil => intro _ acc hacc b hb; exact hacc b hb
  | cons x l ih =>
    intro hQ acc hacc b hb
    exact ih (fun y hy => hQ y (by simp [hy])) (f acc x) (hf acc x (hQ x (by simp)) hacc) b hb

/-- The same for a plain (total) fold over queues. -/
theorem foldl_QOk {L : List Lbl} {α : Type} {Q : α → Prop} {f : PQueue → α → PQueue}
    (hf : ∀ q x, Q x → QOk L q → QOk L (f q x)) :
    ∀ (l : List α), (∀ x ∈ l, Q x) → ∀ (q : PQueue), QOk L q → QOk L (l.foldl f q) := by
  intro l
  induction l with
  | nil => intro _ q hq; exact hq
  | cons x l ih =>
    intro hQ q hq
    exact ih (fun y hy => hQ y (by simp [hy])) (f q x) (hf q x (hQ x (by simp)) hq)

/-- ... and for a plain fold over sets of partitions. -/
theorem foldl_SOk {L : List Lbl} {α : Type} {Q : α → Prop} {f : SSet LPart → α → SSet LPart}
    (hf : ∀ s x, Q x → SOk L s → SOk L (f s x)) :
    ∀ (l : List α), (∀ x ∈ l, Q x) → ∀ (s : SSet LPart), SOk L s → SOk L (l.foldl f s) := by
  intro l
  induction l with
  | nil => intro _ s hs; exact hs
  | cons x l ih =>
    intro hQ s hs
    exact ih (fun y hy => hQ y (by simp [hy])) (f s x) (hf s x (hQ x (by simp)) hs)

theorem replace_ok {L : List Lbl} {v u : Nat} {p : LPart} (hp : POk L p) :
    QOk L (replace v u p) := by
  have hpart : ∀ w : Nat, POk L
      (⟨w, ⟨p.rhs.abstr.map (fun x => if x == v then u else x), p.rhs.conc⟩, p.inf⟩ : LPart) :=
    fun _ => POk.mk' (SSet.nodup_map _) hp.conc
  simp only [replace]
  split
  · exact QOk.ofList (by
      intro q hq
      rcases List.mem_cons.mp hq with rfl | hq'
      · exact hpart _
      · rw [List.mem_singleton] at hq'; subst hq'; exact POk.ofEmpty _ _)
  · exact QOk.ofList (by
      intro q hq; rw [List.mem_singleton] at hq; subst hq; exact hpart _)

theorem instantiate_ok {L : List Lbl} {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : QOk L incm) (hp : QOk L proc)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) : QOk L ni ∧ QOk L np := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, -⟩ := h
    refine ⟨?_, hp.partition_snd _⟩
    refine foldl_QOk (L := L) (Q := POk L)
      (f := fun nq p => nq.concatP (replace v u p).elems) ?_ _ ?_ _ (hi.partition_snd _)
    · intro q x hx hq
      exact QOk.concatP _ _ hq (fun r hr => replace_ok hx r hr)
    · exact SOk.concat (hp.partition_fst _) (hi.partition_fst _)

theorem unifyVars_ok {L : List Lbl} {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : QOk L incm) (hp : QOk L proc)
    (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) : QOk L ni ∧ QOk L np := by
  simp only [unifyVars] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, -⟩ := h
    exact ⟨hi, hp⟩
  · exact instantiate_ok hi hp h

theorem makeEmpty_ok {L : List Lbl} {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : QOk L incm) (hp : QOk L proc)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) : QOk L ni ∧ QOk L np := by
  simp only [makeEmpty] at h
  set F : Except String (SSet LPart) → LPart → Except String (SSet LPart) := fun acc p => do
    let s ← acc
    if p.lhs == v then
      if p.rhs.isEmpty then pure s
      else if p.rhs.conc.isEmpty then
        pure (s.concat (p.rhs.abstr.map (fun w => (⟨w, RHS.empty, some .partitionEmpty⟩ : LPart))))
      else .error ("Incompatible instantiations of '" ++ varStr ns v ++ "'")
    else pure (s.incl ⟨p.lhs, p.rhs.erase v, p.inf⟩) with hF
  have hstep : ∀ (acc : Except String (SSet LPart)) (x : LPart), POk L x →
      (∀ b, acc = .ok b → SOk L b) → ∀ b, F acc x = .ok b → SOk L b := by
    intro acc x hx hacc b hb
    cases hacc' : acc with
    | error m => rw [hF] at hb; rw [hacc'] at hb; simp only [bind, Except.bind] at hb
                 exact absurd hb (by simp)
    | ok a =>
      have ha : SOk L a := hacc a hacc'
      rw [hF] at hb; rw [hacc'] at hb
      simp only [bind, Except.bind] at hb
      split at hb
      · split at hb
        · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact ha
        · split at hb
          · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb
            exact ha.concat (SOk.map (fun _ => POk.ofEmpty _ _))
          · exact absurd hb (by simp)
      · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb
        exact ha.incl (POk.mk' (SSet.nodup_excl hx.abstr v) hx.conc)
  cases hnps : ((incm.partition (fun p => p.involves v)).1.concat
      (proc.partition (fun p => p.involves v)).1).elems.foldl F (.ok SSet.empty) with
  | error m => rw [hnps] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
  | ok nps =>
    have hnpsOk : SOk L nps :=
      foldl_except_inv (P := SOk L) (Q := POk L) hstep _
        (SOk.concat (hi.partition_fst _) (hp.partition_fst _)) (.ok SSet.empty)
        (by intro b hb; rw [Except.ok.injEq] at hb; subst hb; exact SOk.empty) nps hnps
    rw [hnps] at h
    simp only [bind, Except.bind] at h
    split at h
    · exact absurd h (by simp)
    · split at h
      · exact absurd h (by simp)
      · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl, -⟩ := h
        exact ⟨QOk.concatP _ _ (hi.partition_snd _) (hnpsOk.trim (q := _)),
          hp.partition_snd _⟩


theorem subPartitions_ok {L : List Lbl} {v : Nat} {sub : RHS} {proc incm : PQueue}
    {S : SSet LPart} (hs : ROk L sub) (hp : QOk L proc) (hi : QOk L incm)
    (h : subPartitions v sub proc incm = .ok S) : SOk L S := by
  simp only [subPartitions] at h
  set F : Except String (SSet LPart) → LPart → Except String (SSet LPart) := fun acc r => do
    let s ← acc
    if r.rhs.contains v then
      let (nrhs, es) ← rhsSubstitute r.rhs v sub
      let s := s.concat (es.map (fun w => (⟨w, RHS.empty, some .deDuplication⟩ : LPart)))
      pure (s.incl ⟨r.lhs, nrhs, r.inf⟩)
    else pure s with hF
  have hstep : ∀ (acc : Except String (SSet LPart)) (x : LPart), POk L x →
      (∀ b, acc = .ok b → SOk L b) → ∀ b, F acc x = .ok b → SOk L b := by
    intro acc x hx hacc b hb
    cases hacc' : acc with
    | error m =>
      rw [hF, hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
    | ok a =>
      have ha : SOk L a := hacc a hacc'
      rw [hF, hacc'] at hb
      simp only [bind, Except.bind] at hb
      split at hb
      · cases hsub : rhsSubstitute x.rhs v sub with
        | error m => rw [hsub] at hb; simp only [bind, Except.bind] at hb
                     exact absurd hb (by simp)
        | ok w =>
          obtain ⟨nrhs, es⟩ := w
          rw [hsub] at hb
          simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          exact SOk.incl (ha.concat (SOk.map (fun _ => POk.ofEmpty _ _)))
            (ROk.part (rhsSubstitute_ok hx.rhsOk hs hsub) _ _)
      · simp only [pure, Except.pure, Except.ok.injEq] at hb; subst hb; exact ha
  refine foldl_except_inv (P := SOk L) (Q := POk L) hstep _
    (fun x hx => hi x (List.mem_of_mem_filter hx)) _ ?_ S h
  refine foldl_except_inv (P := SOk L) (Q := POk L) hstep _ hp (.ok SSet.empty)
    (by intro b hb; rw [Except.ok.injEq] at hb; subst hb; exact SOk.empty)

theorem destructiveSub_ok {L : List Lbl} {v : Nat} {rhs : RHS} {incm proc : PQueue}
    {ni np : PQueue} (hr : ROk L rhs) (hi : QOk L incm) (hp : QOk L proc)
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) : QOk L ni ∧ QOk L np := by
  simp only [destructiveSub] at h
  set pps := (proc.partition (fun p => p.lhs == v)).1 with hpps
  set procd := (proc.partition (fun p => p.lhs == v)).2 with hprocd
  set qps := (incm.partition (fun p => p.lhs == v)).1 with hqps
  set incmg := (incm.partition (fun p => p.lhs == v)).2 with hincmg
  have hppsOk : SOk L pps := hp.partition_fst _
  have hqpsOk : SOk L qps := hi.partition_fst _
  have hprocdOk : QOk L procd := hp.partition_snd _
  have hincmgOk : QOk L incmg := hi.partition_snd _
  set F : Except String (SSet LPart) → RHS → Except String (SSet LPart) := fun acc r => do
    let s ← acc
    pure (s.concat (← subPartitions v r procd incmg)) with hF
  have hstep : ∀ (acc : Except String (SSet LPart)) (x : RHS), ROk L x →
      (∀ b, acc = .ok b → SOk L b) → ∀ b, F acc x = .ok b → SOk L b := by
    intro acc x hx hacc b hb
    cases hacc' : acc with
    | error m =>
      rw [hF, hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
    | ok a =>
      have ha : SOk L a := hacc a hacc'
      rw [hF, hacc'] at hb
      simp only [bind, Except.bind] at hb
      cases hsp : subPartitions v x procd incmg with
      | error m => exact absurd hb (by rw [hsp]; simp [bind, Except.bind])
      | ok T =>
        rw [hsp] at hb
        simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
        subst hb
        exact ha.concat (subPartitions_ok hx hprocdOk hincmgOk hsp)
  cases hsrs : ((pps.concat qps).map (fun p => p.rhs)).elems.foldl F
      (subPartitions v rhs procd incmg) with
  | error m => rw [hsrs] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
  | ok srs =>
    have hsrsOk : SOk L srs := by
      refine foldl_except_inv (P := SOk L) (Q := ROk L) hstep _ ?_ _ ?_ srs hsrs
      · intro x hx
        obtain ⟨q, hq, rfl⟩ := SSet.mem_map hx
        exact (SOk.concat hppsOk hqpsOk q hq).rhsOk
      · intro b hb; exact subPartitions_ok hr hprocdOk hincmgOk hb
    rw [hsrs] at h
    simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    refine ⟨?_, ?_⟩
    · refine QOk.concatP _ _ ?_ (fun r hr => hsrsOk r (SSet.mem_filter hr))
      split
      · exact QOk.concatP _ _ (by split; exacts [hi, hincmgOk.filter _])
          (fun r hr => hqpsOk r (SSet.mem_filter hr))
      · split
        · exact hi
        · exact hincmgOk.filter _
    · split
      · exact QOk.concatNP _ _ (by split; exacts [hp, hprocdOk.filter _])
          (fun r hr => hppsOk r (SSet.mem_filter hr))
      · split
        · exact hp
        · exact hprocdOk.filter _


/-- A general fold invariant. -/
theorem foldl_inv {α β : Type} {P : β → Prop} {Q : α → Prop} {f : β → α → β}
    (hf : ∀ b x, Q x → P b → P (f b x)) :
    ∀ (l : List α), (∀ x ∈ l, Q x) → ∀ b, P b → P (l.foldl f b) := by
  intro l
  induction l with
  | nil => intro _ b hb; exact hb
  | cons x l ih =>
    intro hQ b hb
    exact ih (fun y hy => hQ y (by simp [hy])) (f b x) (hf b x (hQ x (by simp)) hb)

theorem makeConcrete_ok {L : List Lbl} {v : Nat} {fs : SSet Lbl} {incm proc : PQueue}
    {ni np : PQueue} (hfs : COk L fs) (hi : QOk L incm) (hp : QOk L proc)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) : QOk L ni ∧ QOk L np := by
  simp only [makeConcrete] at h
  set rhss := (((SSet.ofList proc.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)).concat
      (((SSet.ofList incm.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)) with hrhss
  have hrhssOk : ∀ r ∈ rhss.elems, ROk L r := by
    intro r hr
    rcases SSet.mem_concat hr with hr' | hr'
    · obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr'
      exact (hp q (SSet.mem_ofList (SSet.mem_filter hq))).rhsOk
    · obtain ⟨q, hq, rfl⟩ := SSet.mem_map hr'
      exact (hi q (SSet.mem_ofList (SSet.mem_filter hq))).rhsOk
  have hcan : SOk L (rhss.elems.foldl
      (fun (s : SSet LPart) (r : RHS) => s.concat (cancellation v (RHS.ofConcr fs) r))
      SSet.empty) :=
    foldl_inv (P := SOk L) (Q := ROk L)
      (fun s r hr hs => hs.concat (cancellation_ok (ROk.ofConcr hfs) hr)) _ hrhssOk _ SOk.empty
  cases hchk : rhss.elems.foldl
      (fun (acc : Except String Unit) (r : RHS) => do let _ ← acc; ensureSuperset r.conc fs)
      (.ok ()) with
  | error m => rw [hchk] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
  | ok _ =>
    rw [hchk] at h
    simp only [bind, Except.bind] at h
    cases hds : destructiveSub v (RHS.ofConcr fs) incm proc with
    | error m => rw [hds] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨nincm, nproc⟩ := w
      rw [hds] at h
      simp only [bind, Except.bind, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      obtain ⟨h1, h2⟩ := destructiveSub_ok (ROk.ofConcr hfs) hi hp hds
      exact ⟨QOk.concatP _ _ h1 hcan, h2.insertNP (ROk.part (ROk.ofConcr hfs) _ _)⟩

theorem learnPartitions_ok {L : List Lbl} {fl : Flags} {ns : Names} {env : Env} {v : Nat}
    {rhs1 : RHS} {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (hr : ROk L rhs1) (hp : QOk L proc)
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) : SOk L S := by
  simp only [learnPartitions] at h
  split at h
  · cases hss : selfSubstitution ns v rhs1.abstr rhs1.conc with
    | error m =>
      rw [hss] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
    | ok T =>
      rw [hss] at h
      simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, -⟩ := h
      exact selfSubstitution_ok hss
  · refine foldl_except_inv (P := fun (x : SSet LPart × Sup) => SOk L x.1) (Q := POk L)
      ?_ _ hp _ ?_ _ h
    · intro acc x hx hacc b hb
      cases hacc' : acc with
      | error m =>
        rw [hacc'] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
      | ok a =>
        have ha : SOk L a.1 := hacc a hacc'
        rw [hacc'] at hb
        simp only [bind, Except.bind] at hb
        split at hb
        · simp only [pure, Except.pure, Except.ok.injEq] at hb
          subst hb
          refine SOk.concat (SOk.concat (SOk.concat ha (resolution_ok hr hx.rhsOk _ _ _ _))
            (cancellation_ok hr hx.rhsOk)) ?_
          split
          · exact SOk.empty
          · refine foldl_inv (P := fun (y : SSet LPart × Sup) => SOk L y.1) (Q := POk L)
              ?_ _ hp _ SOk.empty
            intro b p3 hp3 hbb
            split
            · exact hbb.concat ((disjunction_ok hp3.rhsOk hx.rhsOk _).concat
                (disjunction_ok hp3.rhsOk hr _))
            · exact hbb
        · cases hsub : substitution v rhs1 x.lhs x.rhs with
          | error m =>
            rw [hsub] at hb; simp only [bind, Except.bind] at hb; exact absurd hb (by simp)
          | ok T =>
            rw [hsub] at hb
            simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq] at hb
            subst hb
            refine SOk.concat (SOk.concat (SOk.concat ha
              (commonSubexpression_ok hr hx.rhsOk _ _)) (substitution_ok hr hx.rhsOk hsub)) ?_
            split
            · exact SOk.empty
            · refine foldl_inv (P := fun (y : SSet LPart × Sup) => SOk L y.1) (Q := POk L)
                ?_ _ hp _ SOk.empty
              intro b p3 hp3 hbb
              split
              · exact hbb.concat ((disjunction_ok hr hp3.rhsOk _).concat
                  (disjunction_ok hr hx.rhsOk _))
              · split
                · exact hbb.concat ((disjunction_ok hx.rhsOk hp3.rhsOk _).concat
                    (disjunction_ok hx.rhsOk hr _))
                · exact hbb
    · intro b hb
      rw [Except.ok.injEq] at hb
      subst hb
      exact splitConcrete_ok hr.abstr hr.conc _ _ _ _ _


/-! ## 6. `step` -/

/-- **The two conditions are preserved by every `continue` step**, at a FIXED label pool:
no rule invents a label, so the pool never has to grow. -/
theorem step_qok {L : List Lbl} {s s' : State} (hi : QOk L s.incm) (hp : QOk L s.proc)
    (h : step s = .continue s') : QOk L s'.incm ∧ QOk L s'.proc := by
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hrOk, hrest⟩ := QOk.dequeue hi hdq
    split at h
    · -- `common:u`
      rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact unifyVars_ok hrest hp hu
    · split at h
      · -- `empty`
        cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact makeEmpty_ok hrest hp hu
      · split at h
        · -- `concrete`
          cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hu] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hu] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact makeConcrete_ok hrOk.conc hrest hp hu
        · split at h
          · -- `unify:u`
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact unifyVars_ok hrest hp hu
          · -- `learn`
            cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at h
              have hlearned : SOk L learned := learnPartitions_ok hrOk.rhsOk hp hu
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨QOk.concatP _ _ hrest (hlearned.trim (q := s.proc)),
                hp.insertNP hrOk⟩


/-! ## 7. The invariant, and the bridge without side hypotheses -/

/-- Every partition a state carries: the incoming queue, then the processed queue. -/
def State.parts (s : State) : List LPart := s.incm.elems ++ s.proc.elems

/-- The state's LABEL POOL: every label it mentions anywhere. -/
def State.labels (s : State) : List Lbl := s.parts.flatMap (fun p => p.rhs.conc.elems)

theorem State.mem_labels {s : State} {p : LPart} (hp : p ∈ s.parts) {x : Lbl}
    (hx : x ∈ p.rhs.conc.elems) : x ∈ s.labels := List.mem_flatMap.mpr ⟨p, hp, hx⟩

/-- **The well-formedness invariant.**  Exactly the five hypotheses `Bridge.lean`'s
`LPart.eqv_iff_toConstraint` needs: the two `SSet`s of every partition in either queue are
duplicate-free (that is the four `Nodup`s, once per partition rather than once per pair), and
the labels of the whole state are coherent -- two of them with the same table index are the
same label. -/
structure Wf (s : State) : Prop where
  /-- Every incoming partition is duplicate-free in both components. -/
  incm : QOk s.labels s.incm
  /-- ... and every processed one. -/
  proc : QOk s.labels s.proc
  /-- The label indices separate the labels of this solve. -/
  coh : LblCoh s.labels

/-- The pool condition of `QOk` is automatic for a queue that IS one of the state's queues,
so `Wf` really only asks for the four `Nodup`s and `LblCoh`. -/
theorem wf_of_nodup {s : State}
    (hi : ∀ p ∈ s.incm.elems, p.rhs.abstr.Nodup ∧ p.rhs.conc.Nodup)
    (hp : ∀ p ∈ s.proc.elems, p.rhs.abstr.Nodup ∧ p.rhs.conc.Nodup)
    (hc : LblCoh s.labels) : Wf s :=
  { incm := fun p hmem => ⟨(hi p hmem).1, ⟨(hi p hmem).2, fun _ hx =>
      State.mem_labels (List.mem_append_left _ hmem) hx⟩⟩,
    proc := fun p hmem => ⟨(hp p hmem).1, ⟨(hp p hmem).2, fun _ hx =>
      State.mem_labels (List.mem_append_right _ hmem) hx⟩⟩,
    coh := hc }

theorem Wf.nodup {s : State} (h : Wf s) {p : LPart} (hp : p ∈ s.parts) :
    p.rhs.abstr.Nodup ∧ p.rhs.conc.Nodup := by
  rcases List.mem_append.mp hp with hp' | hp'
  · exact ⟨(h.incm p hp').abstr, (h.incm p hp').conc.nodup⟩
  · exact ⟨(h.proc p hp').abstr, (h.proc p hp').conc.nodup⟩

/-- **`Wf` is preserved by every `continue` step.**  This is L1 review F6 and L2 review F5:
the bridge's hypotheses now have an invariant tying them to `step`. -/
theorem step_wf {s s' : State} (hw : Wf s) (h : step s = .continue s') : Wf s' := by
  obtain ⟨h1, h2⟩ := step_qok hw.incm hw.proc h
  have hsub : ∀ x ∈ s'.labels, x ∈ s.labels := by
    intro x hx
    obtain ⟨p, hp, hxp⟩ := List.mem_flatMap.mp hx
    rcases List.mem_append.mp hp with hp' | hp'
    · exact (h1 p hp').conc.sub x hxp
    · exact (h2 p hp').conc.sub x hxp
  exact wf_of_nodup (fun p hp => ⟨(h1 p hp).abstr, (h1 p hp).conc.nodup⟩)
    (fun p hp => ⟨(h2 p hp).abstr, (h2 p hp).conc.nodup⟩) (hw.coh.mono hsub)

/-- `done` is the empty-queue answer and changes nothing. -/
theorem step_done {s s' : State} (h : step s = .done s') : s' = s := by
  simp only [step, State.log] at h
  split at h
  · rw [StepResult.done.injEq] at h; exact h.symm
  · exfalso
    repeat' split at h
    all_goals exact absurd h (by simp)

/-- ... and therefore by any number of them. -/
theorem run_wf : ∀ (n : Nat) {s : State} {res : RunResult}, Wf s → run s n = res →
    (∀ s', (res = .solved s' ∨ res = .outOfFuel s') → Wf s')
  | 0, s, res, hw, h => by
    intro s' hs'
    rw [← h] at hs'
    simp only [run] at hs'
    rcases hs' with hs' | hs'
    · exact absurd hs' (by simp)
    · rw [RunResult.outOfFuel.injEq] at hs'; subst hs'; exact hw
  | n + 1, s, res, hw, h => by
    intro s' hs'
    rw [← h] at hs'
    simp only [run] at hs'
    cases hst : step s with
    | done s0 =>
      rw [hst] at hs'
      rcases hs' with hs' | hs'
      · rw [RunResult.solved.injEq] at hs'
        subst hs'
        exact step_done hst ▸ hw
      · exact absurd hs' (by simp)
    | died m s0 =>
      rw [hst] at hs'
      rcases hs' with hs' | hs' <;> exact absurd hs' (by simp)
    | «continue» s0 =>
      rw [hst] at hs'
      exact run_wf n (step_wf hw hst) rfl s' hs'

/-- **The bridge, restated for a reachable state.**  `LPart.eqv` -- `Partition.equals`, which
is what the queue's `insert` and every `Set[Partition]` compare with -- is equality of the
`Rowpartition.Constraint`s, with NO side hypotheses, for any two partitions of a well-formed
state. -/
theorem LPart.eqv_iff_toConstraint_of_wf {s : State} (hw : Wf s) {p q : LPart}
    (hp : p ∈ s.parts) (hq : q ∈ s.parts) :
    p.eqv q = true ↔ p.toConstraint = q.toConstraint := by
  refine LPart.eqv_iff_toConstraint (hw.nodup hp).1 (hw.nodup hq).1 (hw.nodup hp).2
    (hw.nodup hq).2 (hw.coh.mono ?_)
  intro x hx
  rcases List.mem_append.mp hx with hx' | hx'
  · exact State.mem_labels hp hx'
  · exact State.mem_labels hq hx'


/-! ## 8. Every initial state is well formed

`Seed.lean`'s `solveSeed` and `Replay.lean`'s `replay` both build the same state --
`{ incm := q, proc := empty, env := {}, ... }` with `(q, _) = buildQueue cs su` -- so one
theorem covers both, parameterised by the label pool the input draws from. -/

/-- The condition an input term must meet: its concrete row really is a SET, and every label
it names comes from the solve's label pool.  For a `json:` seed the pool is the seed's own
`Lbl.repro` labels; for a replay it is the segment's `slbl` table. -/
def ITerm.InPool (L : List Lbl) : ITerm → Prop
  | .varT _ => True
  | .concRho fs => fs.Nodup ∧ ∀ x ∈ fs.elems, x ∈ L
  | .conT n => n ∈ L
  | .otherT _ => True

/-- ... lifted to a `Part`. -/
def IPart.InPool (L : List Lbl) (p : IPart) : Prop :=
  p.lhs.InPool L ∧ ∀ t ∈ p.rhs, t.InPool L

/-- ... and to one element of the constraint list. -/
def CsItem.InPool (L : List Lbl) : CsItem → Prop
  | .part p => p.InPool L
  | .other _ _ => True

theorem mem_foldl_cons {α : Type} :
    ∀ (l : List α) (acc : List α) {x : α},
      x ∈ l.foldl (fun r t => t :: r) acc → x ∈ l ∨ x ∈ acc
  | [], _, _, h => Or.inr h
  | y :: l, acc, x, h => by
    rcases mem_foldl_cons l (y :: acc) h with h' | h'
    · exact Or.inl (by simp [h'])
    · rcases List.mem_cons.mp h' with rfl | h''
      · exact Or.inl (by simp)
      · exact Or.inr h''

/-- `Exists.apply` reorders and de-duplicates; it invents nothing. -/
theorem mem_existsApply {α : Type} [SVal α] {q : List α} {x : α}
    (h : x ∈ existsApply q) : x ∈ q := by
  simp only [existsApply] at h
  split at h
  · exact h
  · rcases mem_foldl_cons q [] (SSet.mem_ofList h) with h' | h'
    · exact h'
    · cases h'

/-- Destructuring an `Except` `do` block without having to write its body out. -/
theorem except_bind_ok {α β : Type} {x : Except String α} {f : α → Except String β} {b : β}
    (h : (x >>= f) = .ok b) : ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x with
  | error m => exact absurd h (by simp [bind, Except.bind])
  | ok a => exact ⟨a, rfl, by simpa [bind, Except.bind] using h⟩

theorem rhsBuild_ok {L : List Lbl} {ts : List ITerm} (h : ∀ t ∈ ts, ITerm.InPool L t)
    {r : RHS} {es : List Nat} (hb : rhsBuild ts = .ok (r, es)) : ROk L r := by
  simp only [rhsBuild] at hb
  obtain ⟨w, hw, hb2⟩ := except_bind_ok hb
  have hinv : w.1.Nodup ∧ COk L w.2.1 := by
    refine foldl_except_inv
      (P := fun (x : SSet Nat × SSet Lbl × SSet Nat) => x.1.Nodup ∧ COk L x.2.1)
      (Q := ITerm.InPool L) ?_ _ h _
      (by intro b hbb; rw [Except.ok.injEq] at hbb; subst hbb
          exact ⟨SSet.nodup_empty, COk.empty⟩) _ hw
    intro acc x hx hacc b hbb
    cases hacc' : acc with
    | error m =>
      rw [hacc'] at hbb; simp only [bind, Except.bind] at hbb; exact absurd hbb (by simp)
    | ok a =>
      have ha := hacc a hacc'
      rw [hacc'] at hbb
      simp only [bind, Except.bind] at hbb
      cases x with
      | varT v =>
        dsimp only at hbb
        split at hbb
        · simp only [pure, Except.pure, Except.ok.injEq] at hbb
          subst hbb; exact ⟨SSet.nodup_excl ha.1 v, ha.2⟩
        · simp only [pure, Except.pure, Except.ok.injEq] at hbb
          subst hbb; exact ⟨SSet.nodup_incl ha.1 v, ha.2⟩
      | concRho fs =>
        dsimp only at hbb
        split at hbb
        · simp only [pure, Except.pure, Except.ok.injEq] at hbb
          subst hbb
          exact ⟨ha.1, ha.2.concat ⟨hx.1, hx.2⟩⟩
        · exact absurd hbb (by simp)
      | conT n =>
        dsimp only at hbb
        simp only [pure, Except.pure, Except.ok.injEq] at hbb
        subst hbb; exact ⟨ha.1, ha.2.incl hx⟩
      | otherT hh => dsimp only at hbb; exact absurd hbb (by simp)
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at hb2
  obtain ⟨rfl, -⟩ := hb2
  exact ⟨hinv.1, hinv.2⟩

theorem partToPartitions_ok {L : List Lbl} {p : IPart} {su : Sup} (h : IPart.InPool L p)
    {ps : List LPart} {su' : Sup} (hb : partToPartitions p su = .ok (ps, su')) :
    ∀ x ∈ ps, POk L x := by
  simp only [partToPartitions] at hb
  split at hb
  · obtain ⟨w, hw, hb2⟩ := except_bind_ok hb
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at hb2
    obtain ⟨rfl, -⟩ := hb2
    intro x hx
    rcases List.mem_cons.mp hx with rfl | hx'
    · exact ROk.part (rhsBuild_ok h.2 hw) _ _
    · obtain ⟨u, -, rfl⟩ := List.mem_map.mp hx'
      exact POk.ofEmpty _ _
  · obtain ⟨w, hw, hb2⟩ := except_bind_ok hb
    obtain ⟨w2, hw2, hb3⟩ := except_bind_ok hb2
    simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at hb3
    obtain ⟨rfl, -⟩ := hb3
    intro x hx
    rcases List.mem_cons.mp hx with rfl | hx'
    · exact ROk.part (rhsBuild_ok h.2 hw) _ _
    · rcases List.mem_cons.mp hx' with rfl | hx''
      · exact ROk.part (rhsBuild_ok (by
          intro t ht; rw [List.mem_singleton] at ht; subst ht; exact h.1) hw2) _ _
      · obtain ⟨u, -, rfl⟩ := List.mem_map.mp hx''
        exact POk.ofEmpty _ _

theorem buildQueue_qok {L : List Lbl} {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    (h : ∀ c ∈ cs, CsItem.InPool L c) (hb : buildQueue cs su = .ok (q, su')) : QOk L q := by
  simp only [buildQueue] at hb
  obtain ⟨w, hw, hb2⟩ := except_bind_ok hb
  have hps : ∀ y ∈ w.1, POk L y := by
    refine foldl_except_inv (P := fun (x : List LPart × Sup) => ∀ y ∈ x.1, POk L y)
      (Q := CsItem.InPool L) ?_ _ (fun c hc => h c (mem_existsApply (mem_existsApply hc)))
      _ (by intro b hbb; rw [Except.ok.injEq] at hbb; subst hbb; intro y hy; cases hy) _ hw
    intro acc x hx hacc b hbb
    cases hacc' : acc with
    | error m =>
      rw [hacc'] at hbb; simp only [bind, Except.bind] at hbb; exact absurd hbb (by simp)
    | ok a =>
      have ha := hacc a hacc'
      rw [hacc'] at hbb
      simp only [bind, Except.bind] at hbb
      cases x with
      | other hh eq =>
        dsimp only at hbb
        simp only [pure, Except.pure, Except.ok.injEq] at hbb
        subst hbb; exact ha
      | part pp =>
        dsimp only at hbb
        obtain ⟨w2, hw2, hb3⟩ := except_bind_ok hbb
        simp only [pure, Except.pure, Except.ok.injEq] at hb3
        subst hb3
        intro y hy
        rcases List.mem_append.mp hy with hy' | hy'
        · exact ha y hy'
        · exact partToPartitions_ok hx hw2 y hy'
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at hb2
  obtain ⟨rfl, -⟩ := hb2
  exact QOk.ofList hps

/-- **Every initial state is well formed.**  This is the state `Seed.lean`'s `solveSeed` and
`Replay.lean`'s `replay` hand to `run`. -/
theorem wf_initial {L : List Lbl} {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    (hcs : ∀ c ∈ cs, CsItem.InPool L c) (hL : LblCoh L)
    (hq : buildQueue cs su = .ok (q, su'))
    (fl : Flags) (ns : Names) (site : String) (lo : Nat) :
    Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := [], flags := fl,
         names := ns, site := site, su0 := lo } := by
  have hQ : QOk L q := buildQueue_qok hcs hq
  refine wf_of_nodup (fun p hp => ⟨(hQ p hp).abstr, (hQ p hp).conc.nodup⟩)
    (fun p hp => by cases hp) (hL.mono ?_)
  intro x hx
  obtain ⟨p, hp, hxp⟩ := List.mem_flatMap.mp hx
  rcases List.mem_append.mp hp with hp' | hp'
  · exact (hQ p hp').conc.sub x hxp
  · cases hp'


/-! ### 8a. `json:` seeds

`Lbl.repro n` determines every field of the label from `n`, so the pool of a seed is
coherent by construction. -/

/-- The labels a seed can mention. -/
def Seed.pool (s : Seed) : List Lbl := s.cons.flatMap (fun c => c.labels.map Lbl.repro)

theorem lblCoh_of_repro {l : List Lbl} (h : ∀ x ∈ l, ∃ n, x = Lbl.repro n) : LblCoh l := by
  intro x hx y hy hn
  obtain ⟨a, rfl⟩ := h x hx
  obtain ⟨b, rfl⟩ := h y hy
  simp only [Lbl.repro] at hn ⊢
  subst hn
  rfl

theorem lblCoh_seedPool (s : Seed) : LblCoh s.pool := by
  refine lblCoh_of_repro ?_
  intro x hx
  obtain ⟨c, -, hx'⟩ := List.mem_flatMap.mp hx
  obtain ⟨n, -, rfl⟩ := List.mem_map.mp hx'
  exact ⟨n, rfl⟩

theorem seedSystem_inPool (s : Seed) (base : Nat) :
    ∀ c ∈ (seedSystem s base).1, CsItem.InPool s.pool c := by
  intro c hc
  simp only [seedSystem] at hc
  obtain ⟨sc, hsc, rfl⟩ := List.mem_map.mp hc
  refine ⟨trivial, ?_⟩
  intro t ht
  rcases List.mem_append.mp ht with ht' | ht'
  · obtain ⟨v, -, rfl⟩ := List.mem_map.mp ht'
    exact trivial
  · split at ht'
    · cases ht'
    · rw [List.mem_singleton] at ht'
      subst ht'
      refine ⟨SSet.nodup_ofList _, ?_⟩
      intro x hx
      exact List.mem_flatMap.mpr ⟨sc, hsc, SSet.mem_ofList hx⟩

/-- **The `json:` seed path starts well formed.** -/
theorem wf_seed (sd : Seed) (base : Nat) {su : Sup} {q : PQueue} {su' : Sup}
    (hq : buildQueue (seedSystem sd base).1 su = .ok (q, su'))
    (fl : Flags) (ns : Names) (site : String) (lo : Nat) :
    Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := [], flags := fl,
         names := ns, site := site, su0 := lo } :=
  wf_initial (seedSystem_inPool sd base) (lblCoh_seedPool sd) hq fl ns site lo


/-! ### 8b. Corpus replays

A replay's pool is the segment's `slbl` table, and the trace numbers that table 0, 1, 2, ...
`RowTrace.solveInput` numbers a solve's labels out of a `LinkedHashMap[Name, Int]`, so the
index really does determine the name -- and the parser only accepts a table whose indices
arrive in order (`slbl out of order`), which is exactly the property `LblCoh` asks for.  That
makes L2 review F5's fifth hypothesis a THEOREM about the parser rather than an assumption.

The one thing the parser does NOT establish is that a `concRho` payload is duplicate-free: it
reads a comma-separated list of indices and keeps them all.  On the compiler's side the
payload is a `Set`, so the property holds of every real trace; here it is an explicit,
decidable hypothesis (`CsItem.SetsOk`) rather than a silent assumption. -/

/-- The pool half of `InPool`. -/
def ITerm.LabelsIn (L : List Lbl) : ITerm → Prop
  | .varT _ => True
  | .concRho fs => ∀ x ∈ fs.elems, x ∈ L
  | .conT n => n ∈ L
  | .otherT _ => True

/-- The "this really is a set" half of `InPool`. -/
def ITerm.SetsOk : ITerm → Prop
  | .concRho fs => fs.Nodup
  | _ => True

def IPart.LabelsIn (L : List Lbl) (p : IPart) : Prop :=
  p.lhs.LabelsIn L ∧ ∀ t ∈ p.rhs, t.LabelsIn L

def IPart.SetsOk (p : IPart) : Prop := p.lhs.SetsOk ∧ ∀ t ∈ p.rhs, t.SetsOk

def CsItem.LabelsIn (L : List Lbl) : CsItem → Prop
  | .part p => p.LabelsIn L
  | .other _ _ => True

def CsItem.SetsOk : CsItem → Prop
  | .part p => p.SetsOk
  | .other _ _ => True

theorem ITerm.inPool_of {L : List Lbl} {t : ITerm} (h1 : t.LabelsIn L) (h2 : t.SetsOk) :
    t.InPool L := by
  cases t with
  | varT _ => exact trivial
  | concRho fs => exact ⟨h2, h1⟩
  | conT n => exact h1
  | otherT _ => exact trivial

theorem CsItem.inPool_of {L : List Lbl} {c : CsItem} (h1 : c.LabelsIn L) (h2 : c.SetsOk) :
    c.InPool L := by
  cases c with
  | part p => exact ⟨ITerm.inPool_of h1.1 h2.1, fun t ht => ITerm.inPool_of (h1.2 t ht) (h2.2 t ht)⟩
  | other _ _ => exact trivial

theorem ITerm.LabelsIn.mono {L L' : List Lbl} (hL : ∀ x ∈ L, x ∈ L') {t : ITerm}
    (h : t.LabelsIn L) : t.LabelsIn L' := by
  cases t with
  | varT _ => exact trivial
  | concRho fs => exact fun x hx => hL x (h x hx)
  | conT n => exact hL n h
  | otherT _ => exact trivial

theorem CsItem.LabelsIn.mono {L L' : List Lbl} (hL : ∀ x ∈ L, x ∈ L') {c : CsItem}
    (h : c.LabelsIn L) : c.LabelsIn L' := by
  cases c with
  | part p => exact ⟨h.1.mono hL, fun t ht => (h.2 t ht).mono hL⟩
  | other _ _ => exact trivial

/-- A label table numbered `0, 1, 2, ...` is coherent. -/
theorem lblCoh_of_table {l : List Lbl} (h : ∀ (i : Nat) (hi : i < l.length), (l[i]'hi).n = i) :
    LblCoh l := by
  intro x hx y hy hn
  obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hx
  obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem hy
  rw [h i hi, h j hj] at hn
  subst hn
  rfl

/-- What the parser maintains about a segment under construction. -/
structure SegOk (g : Segment) : Prop where
  /-- The label table is numbered by position. -/
  table : ∀ (i : Nat) (hi : i < g.labels.length), (g.labels[i]'hi).n = i
  /-- Every constraint read so far names only labels of the table. -/
  cons : ∀ c ∈ g.cons, CsItem.LabelsIn g.labels c

theorem SegOk.keep {g g' : Segment} (h : SegOk g) (hl : g'.labels = g.labels)
    (hc : ∀ c ∈ g'.cons, c ∈ g.cons ∨ CsItem.LabelsIn g.labels c) : SegOk g' :=
  { table := by rw [hl]; exact h.table,
    cons := fun c hc' => by
      rw [hl]
      rcases hc c hc' with hh | hh
      · exact h.cons c hh
      · exact hh }

theorem SegOk.appendLabel {g : Segment} (h : SegOk g) {l : Lbl}
    (hn : l.n = g.labels.length) : SegOk { g with labels := g.labels ++ [l] } := by
  refine { table := ?_, cons := ?_ }
  · intro i hi
    show (g.labels ++ [l])[i].n = i
    rw [List.length_append, List.length_singleton] at hi
    rcases Nat.lt_or_ge i g.labels.length with hlt | hge
    · rw [List.getElem_append_left hlt]; exact h.table i hlt
    · have hEq : i = g.labels.length := by omega
      subst hEq
      rw [List.getElem_append_right (by omega)]
      simpa using hn
  · intro c hc
    exact (h.cons c hc).mono (fun x hx => List.mem_append_left _ hx)

/-- Every label the parser can put into a term came out of the table. -/
theorem mem_of_bind_getElem? {L : List Lbl} {o : Option Nat} {y : Lbl}
    (hb : o.bind (fun i => L[i]?) = some y) : y ∈ L := by
  cases o with
  | none => exact absurd hb (by simp)
  | some n => exact List.mem_of_getElem? (by simpa using hb)

theorem mem_of_mem_filterMap_bind {L : List Lbl} {idxs : List String} {x : Lbl}
    (hx : x ∈ (idxs.map (fun sx => (sx.toNat?).bind (fun i => L[i]?))).filterMap id) : x ∈ L := by
  obtain ⟨o, ho, hox⟩ := List.mem_filterMap.mp hx
  obtain ⟨sIdx, -, hi⟩ := List.mem_map.mp ho
  rw [← hi] at hox
  exact mem_of_bind_getElem? (by simpa using hox)

theorem parseTerm_labelsIn {L : List Lbl} {t : String} {tm : ITerm}
    (h : parseTerm L t = .ok tm) : tm.LabelsIn L := by
  simp only [parseTerm] at h
  repeat' split at h
  all_goals cases h
  all_goals first
    | exact trivial
    | exact fun x hx => mem_of_mem_filterMap_bind hx
    | exact mem_of_bind_getElem? (by assumption)


theorem labelsIn_of_map {L : List Lbl} {terms : List String} {lt : ITerm}
    {rest : List (Except String ITerm)}
    (heq : terms.map (parseTerm L) = Except.ok lt :: rest) :
    CsItem.LabelsIn L (CsItem.part ⟨lt, rest.filterMap (fun r =>
      match r with | .ok x => some x | .error _ => none)⟩) := by
  refine ⟨?_, ?_⟩
  · have hm : Except.ok lt ∈ terms.map (parseTerm L) := by
      rw [heq]; exact List.mem_cons_self ..
    obtain ⟨t, -, ht⟩ := List.mem_map.mp hm
    exact parseTerm_labelsIn ht
  · intro x hx
    obtain ⟨r, hr, hrx⟩ := List.mem_filterMap.mp hx
    have hrmem : r ∈ terms.map (parseTerm L) := by
      rw [heq]; exact List.mem_cons_of_mem _ hr
    obtain ⟨t, -, ht⟩ := List.mem_map.mp hrmem
    cases r with
    | error m => exact absurd hrx (by simp)
    | ok y =>
      simp only [Option.some.injEq] at hrx
      subst hrx
      exact parseTerm_labelsIn ht

theorem SegOk.addRecord {g : Segment} (hg : SegOk g) (f : List String) :
    SegOk (Rowpartition.Loop.addRecord g f) := by
  simp only [Rowpartition.Loop.addRecord, Segment.err]
  repeat' split
  all_goals first
    | exact hg
    | exact hg.appendLabel (by rename_i hcond; simpa using hcond)
    | exact hg.keep rfl (fun c hc => Or.inl hc)
    | (refine hg.keep rfl ?_
       intro c hc
       rcases List.mem_cons.mp hc with rfl | hc'
       · exact Or.inr trivial
       · exact Or.inl hc')
    | (refine hg.keep rfl ?_
       intro c hc
       rcases List.mem_cons.mp hc with rfl | hc'
       · exact Or.inr (labelsIn_of_map (by assumption))
       · exact Or.inl hc')


theorem segOk_startSegment (f : List String) : SegOk (startSegment f) := by
  have hl : (startSegment f).labels = [] ∧ (startSegment f).cons = [] := by
    simp only [startSegment, Segment.err]
    repeat' split
    all_goals exact ⟨rfl, rfl⟩
  refine { table := ?_, cons := ?_ }
  · intro i hi
    rw [hl.1] at hi
    simp at hi
  · intro c hc
    rw [hl.2] at hc
    cases hc

theorem SegOk.finish {g : Segment} (h : SegOk g) : SegOk (Segment.finish g) := by
  refine h.keep rfl ?_
  intro c hc
  exact Or.inl (List.mem_reverse.mp hc)

/-- **Every segment the parser produces satisfies the invariant.**  In particular its label
table is numbered by position, which is `LblCoh`. -/
theorem segOk_parseSegments {lines : List String} {g : Segment} (h : g ∈ parseSegments lines) :
    SegOk g := by
  simp only [parseSegments] at h
  obtain ⟨g0, hg0, rfl⟩ := List.mem_map.mp h
  refine SegOk.finish ?_
  rw [List.mem_reverse] at hg0
  revert hg0
  refine foldl_inv (P := fun (acc : List Segment) => ∀ x ∈ acc, SegOk x) (Q := fun _ => True)
    ?_ lines (fun _ _ => trivial) [] (by intro x hx; cases hx) g0
  intro b ln _ hb
  repeat' split
  all_goals first
    | exact hb
    | (intro x hx
       rcases List.mem_cons.mp hx with rfl | hx'
       · exact segOk_startSegment _
       · exact hb x hx')
    | (intro x hx
       rcases List.mem_cons.mp hx with rfl | hx'
       · exact SegOk.addRecord (hb _ (List.mem_cons_self ..)) _
       · exact hb x (List.mem_cons_of_mem _ hx'))

/-- **A corpus replay starts well formed.**  The label pool is the segment's `slbl` table,
whose coherence the parser guarantees; the one thing it does not guarantee is that a
`concRho` payload is duplicate-free, which is `hsets` -- true of every trace the compiler
writes, since the payload it prints is a `Set`, and decidable here. -/
theorem wf_replay {lines : List String} {g : Segment} (hg : g ∈ parseSegments lines)
    (hsets : ∀ c ∈ g.cons, CsItem.SetsOk c)
    {q : PQueue} {su' : Sup} (hq : buildQueue g.cons g.sup = .ok (q, su'))
    (fl : Flags) (site : String) (lo : Nat) :
    Wf { incm := q, proc := PQueue.empty, env := {}, su := su', trace := [], flags := fl,
         names := g.names, site := site, su0 := lo } := by
  have hs : SegOk g := segOk_parseSegments hg
  exact wf_initial (fun c hc => CsItem.inPool_of (hs.cons c hc) (hsets c hc))
    (lblCoh_of_table hs.table) hq fl g.names site lo

end Rowpartition.Loop
