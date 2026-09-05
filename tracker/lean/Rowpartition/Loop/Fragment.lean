/-
# L5 round 5 (R5.4): a fragment on which the loop TERMINATES, with an explicit bound

Rounds 3 and 4 proved that no bound on `incorporateAll`'s vocabulary follows from any of the
three natural carriers, and R5.1-R5.3 of this round refute the two repairs that were left.
So `Terminates s₀` for every satisfiable `Wf s₀` is still open, and R5.4 asks instead for a
STATED FRAGMENT on which it is a theorem.

**The fragment: `LinkOnly`** -- no constraint of the state actually PARTITIONS.  Every
right-hand side is a lone row variable and carries no concrete labels, so the system is a
conjunction of `a <- (b)`, the row language's equality.  On it:

* `step` can only take the `common` or the `unify` branch (`linkOnly_branch`): `makeEmpty`
  needs an empty right-hand side, `makeConcrete` an empty ABSTRACT one, and `learnPartitions`
  a right-hand side that is neither -- so no rule fires and **no id is ever drawn**;
* the fragment is preserved (`linkOnly_step`), because `Constraints.replace`'s
  de-duplication arm needs TWO abstract parts;
* and the total number of partitions in the two queues STRICTLY DECREASES at every step
  (`step_qsize_lt`), because `instantiate` re-inserts at most one partition for each one it
  removed and the dequeued premise is gone.

Hence `Terminates` with the explicit bound `qsize s₀ = |incm| + |proc|`
(`linkOnly_terminates`, `linkOnly_run`).

**The residual, exactly.**  This is the fragment in which the two generative rules are
syntactically unreachable.  It says nothing about any state with a two-part right-hand side,
which is every state the corpus and every seed of the L5 hunts produce; §R5.4 of the report
measures the distance.  What is missing for the general case is unchanged and is named there.
-/
import Rowpartition.Loop.Dequeue

set_option maxRecDepth 100000

namespace Rowpartition.Loop

open Rowpartition

variable {α β : Type} [SVal α]

/-! ## 1. Sizes of the set and queue operations -/

theorem incl_length_le (s : SSet α) (x : α) :
    (s.incl x).elems.length ≤ s.elems.length + 1 := by
  unfold SSet.incl
  split
  · omega
  · split
    · simp only [(SSet.champ_perm _).length_eq, List.length_append, List.length_singleton]
      omega
    · simp only [List.length_append, List.length_singleton]
      omega

theorem foldl_incl_length_le : ∀ (l : List α) (s : SSet α),
    (l.foldl SSet.incl s).elems.length ≤ s.elems.length + l.length
  | [], s => by simp
  | x :: t, s => by
    simp only [List.foldl_cons, List.length_cons]
    have h1 := foldl_incl_length_le t (s.incl x)
    have h2 := incl_length_le s x
    omega

theorem ofList_length_le (l : List α) : (SSet.ofList l).elems.length ≤ l.length := by
  have := foldl_incl_length_le l (SSet.empty : SSet α)
  simpa [SSet.ofList, SSet.empty] using this

theorem concat_length_le (s t : SSet α) :
    (s.concat t).elems.length ≤ s.elems.length + t.elems.length := by
  unfold SSet.concat
  split
  · simp only [List.length_map, (SSet.champ_perm _).length_eq, List.length_append]
    have := List.length_filter_le (fun x => !t.contains x) s.elems
    omega
  · exact foldl_incl_length_le t.elems s

theorem length_filter_add (p : α → Bool) : ∀ l : List α,
    (l.filter p).length + (l.filter (fun x => !p x)).length = l.length
  | [] => by simp
  | x :: t => by
    have ih := length_filter_add p t
    cases hpx : p x <;> simp [List.filter_cons, hpx] <;> omega

theorem insertSorted_length (p : LPart) : ∀ l : List LPart,
    (PQueue.insertSorted p l).length = l.length + 1
  | [] => rfl
  | x :: t => by
    simp only [PQueue.insertSorted]
    split
    · simp [insertSorted_length p t]
    · simp

theorem insertNP_length_le (q : PQueue) (p : LPart) :
    (q.insertNP p).elems.length ≤ q.elems.length + 1 := by
  unfold PQueue.insertNP
  split
  · omega
  · split
    · omega
    · simp [insertSorted_length]

theorem insertP_length_le (q : PQueue) (p : LPart) :
    (q.insertP p).elems.length ≤ q.elems.length + 1 := by
  unfold PQueue.insertP
  split
  · omega
  · split
    · omega
    · split
      · exact insertNP_length_le _ _
      · simp [insertSorted_length]

theorem concatP_length_le : ∀ (ps : List LPart) (q : PQueue),
    (q.concatP ps).elems.length ≤ q.elems.length + ps.length
  | [], q => by simp [PQueue.concatP]
  | p :: t, q => by
    simp only [PQueue.concatP, List.foldl_cons, List.length_cons]
    have h1 := concatP_length_le t (q.insertP p)
    have h2 := insertP_length_le q p
    simp only [PQueue.concatP] at h1
    omega

theorem concatNP_length_le : ∀ (ps : List LPart) (q : PQueue),
    (q.concatNP ps).elems.length ≤ q.elems.length + ps.length
  | [], q => by simp [PQueue.concatNP]
  | p :: t, q => by
    simp only [PQueue.concatNP, List.foldl_cons, List.length_cons]
    have h1 := concatNP_length_le t (q.insertNP p)
    have h2 := insertNP_length_le q p
    simp only [PQueue.concatNP] at h1
    omega

theorem ofListQ_length_le (ps : List LPart) : (PQueue.ofList ps).elems.length ≤ ps.length := by
  have := concatNP_length_le ps PQueue.empty
  simpa [PQueue.ofList, PQueue.empty] using this

theorem partition_length_le (q : PQueue) (f : LPart → Bool) :
    (q.partition f).1.elems.length + (q.partition f).2.elems.length ≤ q.elems.length := by
  simp only [PQueue.partition]
  have h1 : (SSet.ofList ((q.elems.filter f).reverse)).elems.length
      ≤ (q.elems.filter f).length := by
    have := ofList_length_le ((q.elems.filter f).reverse)
    simpa using this
  have h2 := length_filter_add f q.elems
  omega

/-! ## 2. The fragment -/

/-- **The equational fragment.**  Every partition in either queue is a LINK `a <- (b)`: a
lone abstract part and no concrete labels.  Nothing in the state partitions anything. -/
def LinkOnly (s : State) : Prop :=
  ∀ p ∈ s.parts, p.rhs.conc.elems = [] ∧ p.rhs.abstr.elems.length = 1

/-- The measure: how many partitions the two queues hold. -/
def qsize (s : State) : Nat := s.incm.elems.length + s.proc.elems.length

theorem linkOnly_mem_incm {s : State} (h : LinkOnly s) {p : LPart} (hp : p ∈ s.incm.elems) :
    p.rhs.conc.elems = [] ∧ p.rhs.abstr.elems.length = 1 :=
  h p (List.mem_append_left _ hp)

theorem linkOnly_mem_proc {s : State} (h : LinkOnly s) {p : LPart} (hp : p ∈ s.proc.elems) :
    p.rhs.conc.elems = [] ∧ p.rhs.abstr.elems.length = 1 :=
  h p (List.mem_append_right _ hp)

/-- A right-hand side with one abstract part and no labels is `single?`. -/
theorem single_of_link {r : RHS} (hc : r.conc.elems = []) (ha : r.abstr.elems.length = 1) :
    ∃ u, r.single? = some u := by
  unfold RHS.single? SSet.single?
  have : r.conc.isEmpty = true := by simp [SSet.isEmpty, hc]
  rw [if_pos this]
  match hm : r.abstr.elems with
  | [] => rw [hm] at ha; simp at ha
  | [u] => exact ⟨u, by simp [hm]⟩
  | u :: v :: t => rw [hm] at ha; simp at ha

/-- ...and in particular not empty, and not label-only. -/
theorem not_isEmpty_of_link {r : RHS} (ha : r.abstr.elems.length = 1) : r.isEmpty = false := by
  unfold RHS.isEmpty SSet.isEmpty
  match hm : r.abstr.elems with
  | [] => rw [hm] at ha; simp at ha
  | u :: t => simp [hm]

/-! ## 3. `replace` under the fragment -/

/-- `Constraints.replace`'s de-duplication arm needs the SAME right-hand side to mention both
variables, which a lone abstract part cannot do unless they are equal. -/
theorem replace_length_le_one {v u : Nat} {p : LPart} (hne : v ≠ u)
    (ha : p.rhs.abstr.elems.length = 1) : (replace v u p).elems.length ≤ 1 := by
  unfold replace
  have hnot : ¬ (p.rhs.abstr.contains v = true ∧ p.rhs.abstr.contains u = true) := by
    rintro ⟨h1, h2⟩
    match hm : p.rhs.abstr.elems with
    | [] => rw [hm] at ha; simp at ha
    | [a] =>
      simp only [SSet.contains, hm, List.any_cons, List.any_nil, Bool.or_false] at h1 h2
      exact hne ((LawfulSVal.eq_iff v a).mp h1 |>.trans ((LawfulSVal.eq_iff u a).mp h2).symm)
    | a :: b :: t => rw [hm] at ha; simp at ha
  rw [if_neg (by simpa using hnot)]
  exact ofListQ_length_le _

/-! ## 4. Membership: what the queue operations can put into a queue -/

theorem sset_incl_mem {P : α → Prop} {s : SSet α} {x : α} (hx : P x)
    (hs : ∀ y ∈ s.elems, P y) : ∀ y ∈ (s.incl x).elems, P y := by
  intro y hy
  unfold SSet.incl at hy
  split at hy
  · exact hs y hy
  · split at hy
    · rcases List.mem_append.mp ((SSet.champ_perm _).mem_iff.mp hy) with h | h
      · exact hs y h
      · rw [List.mem_singleton.mp h]; exact hx
    · rcases List.mem_append.mp hy with h | h
      · exact hs y h
      · rw [List.mem_singleton.mp h]; exact hx

theorem sset_foldl_incl_mem {P : α → Prop} : ∀ (l : List α) (s : SSet α),
    (∀ x ∈ l, P x) → (∀ y ∈ s.elems, P y) → ∀ y ∈ (l.foldl SSet.incl s).elems, P y
  | [], s, _, hs => by simpa using hs
  | x :: t, s, hl, hs => by
    simp only [List.foldl_cons]
    exact sset_foldl_incl_mem t (s.incl x) (fun y hy => hl y (List.mem_cons_of_mem _ hy))
      (sset_incl_mem (hl x List.mem_cons_self) hs)

theorem sset_ofList_mem {P : α → Prop} (l : List α) (h : ∀ x ∈ l, P x) :
    ∀ y ∈ (SSet.ofList l).elems, P y :=
  sset_foldl_incl_mem l SSet.empty h (by simp [SSet.empty])

theorem sset_concat_mem {P : α → Prop} {s t : SSet α}
    (hs : ∀ y ∈ s.elems, P y) (ht : ∀ y ∈ t.elems, P y) :
    ∀ y ∈ (s.concat t).elems, P y := by
  intro y hy
  unfold SSet.concat at hy
  split at hy
  · simp only [List.mem_map] at hy
    obtain ⟨x, hx, hxy⟩ := hy
    have hmem : x ∈ s.elems.filter (fun z => !t.contains z) ++ t.elems :=
      (SSet.champ_perm _).mem_iff.mp hx
    have hPx : P x := by
      rcases List.mem_append.mp hmem with h | h
      · exact hs x (List.mem_of_mem_filter h)
      · exact ht x h
    unfold SSet.pickRep at hxy
    split at hxy
    · rw [← hxy]; exact hPx
    · rename_i sx hfind
      split at hxy
      · rw [← hxy]; exact hPx
      · rw [← hxy]; exact hs sx (List.mem_of_find?_eq_some hfind)
  · exact sset_foldl_incl_mem t.elems s ht hs y hy

theorem sset_map_mem {P : β → Prop} [SVal β] {s : SSet α} {f : α → β}
    (h : ∀ x ∈ s.elems, P (f x)) : ∀ y ∈ (s.map f).elems, P y := by
  unfold SSet.map
  have : ∀ (l : List α) (t : SSet β), (∀ x ∈ l, P (f x)) → (∀ y ∈ t.elems, P y) →
      ∀ y ∈ (l.foldl (fun acc x => acc.incl (f x)) t).elems, P y := by
    intro l
    induction l with
    | nil => intro t _ ht; simpa using ht
    | cons x r ih =>
      intro t hl ht
      simp only [List.foldl_cons]
      exact ih (t.incl (f x)) (fun z hz => hl z (List.mem_cons_of_mem _ hz))
        (sset_incl_mem (hl x List.mem_cons_self) ht)
  exact this s.elems ⟨s.hashed, []⟩ h (by simp)

theorem insertSorted_mem {P : LPart → Prop} (p : LPart) :
    ∀ (l : List LPart), P p → (∀ x ∈ l, P x) → ∀ x ∈ PQueue.insertSorted p l, P x
  | [], hp, _ => by
    intro x hx
    simp only [PQueue.insertSorted, List.mem_singleton] at hx
    exact hx ▸ hp
  | y :: t, hp, hl => by
    simp only [PQueue.insertSorted]
    split
    · intro x hx
      rcases List.mem_cons.mp hx with h | h
      · exact h ▸ hl y List.mem_cons_self
      · exact insertSorted_mem p t hp (fun z hz => hl z (List.mem_cons_of_mem _ hz)) x h
    · intro x hx
      rcases List.mem_cons.mp hx with h | h
      · exact h ▸ hp
      · exact hl x h

theorem insertNP_mem {P : LPart → Prop} {q : PQueue} {p : LPart} (hp : P p)
    (hq : ∀ x ∈ q.elems, P x) : ∀ x ∈ (q.insertNP p).elems, P x := by
  intro x hx
  unfold PQueue.insertNP at hx
  split at hx
  · exact hq x hx
  · split at hx
    · exact hq x hx
    · exact insertSorted_mem p q.elems hp hq x hx

theorem insertP_mem {P : LPart → Prop}
    (hlink : ∀ v w : Nat, P ⟨v, RHS.ofAbstr (SSet.ofList [w]), some .commonPartition⟩)
    {q : PQueue} {p : LPart} (hp : P p) (hq : ∀ x ∈ q.elems, P x) :
    ∀ x ∈ (q.insertP p).elems, P x := by
  intro x hx
  unfold PQueue.insertP at hx
  split at hx
  · exact hq x hx
  · split at hx
    · exact hq x hx
    · split at hx
      · exact insertNP_mem (hlink _ _) hq x hx
      · exact insertSorted_mem p q.elems hp hq x hx

theorem concatP_mem {P : LPart → Prop}
    (hlink : ∀ v w : Nat, P ⟨v, RHS.ofAbstr (SSet.ofList [w]), some .commonPartition⟩) :
    ∀ (ps : List LPart) (q : PQueue), (∀ p ∈ ps, P p) → (∀ x ∈ q.elems, P x) →
      ∀ x ∈ (q.concatP ps).elems, P x
  | [], q, _, hq => by simpa [PQueue.concatP] using hq
  | p :: t, q, hps, hq => by
    simp only [PQueue.concatP, List.foldl_cons]
    have := concatP_mem hlink t (q.insertP p) (fun z hz => hps z (List.mem_cons_of_mem _ hz))
      (insertP_mem hlink (hps p List.mem_cons_self) hq)
    simpa [PQueue.concatP] using this

theorem concatNP_mem {P : LPart → Prop} :
    ∀ (ps : List LPart) (q : PQueue), (∀ p ∈ ps, P p) → (∀ x ∈ q.elems, P x) →
      ∀ x ∈ (q.concatNP ps).elems, P x
  | [], q, _, hq => by simpa [PQueue.concatNP] using hq
  | p :: t, q, hps, hq => by
    simp only [PQueue.concatNP, List.foldl_cons]
    have := concatNP_mem t (q.insertNP p) (fun z hz => hps z (List.mem_cons_of_mem _ hz))
      (insertNP_mem (hps p List.mem_cons_self) hq)
    simpa [PQueue.concatNP] using this

theorem ofListQ_mem {P : LPart → Prop} (ps : List LPart) (h : ∀ p ∈ ps, P p) :
    ∀ x ∈ (PQueue.ofList ps).elems, P x :=
  concatNP_mem ps PQueue.empty h (by simp [PQueue.empty])

theorem incl_nil_length (h : Bool) (x : α) :
    ((⟨h, []⟩ : SSet α).incl x).elems.length = 1 := by
  unfold SSet.incl
  simp only [SSet.contains, List.any_nil, Bool.false_eq_true, if_false]
  split <;> simp [(SSet.champ_perm _).length_eq]

theorem map_length_of_singleton [SVal β] {s : SSet α} (f : α → β) {a : α} (h : s.elems = [a]) :
    (s.map f).elems.length = 1 := by
  unfold SSet.map
  rw [h]
  simp only [List.foldl_cons, List.foldl_nil]
  exact incl_nil_length _ _

/-! ## 5. The fragment is preserved, and the queues shrink -/

/-- `Link p`: the property `LinkOnly` asserts of every partition. -/
def Link (p : LPart) : Prop := p.rhs.conc.elems = [] ∧ p.rhs.abstr.elems.length = 1

/-- The redirect's own manufactured partition is a link. -/
theorem link_commonPartition (v w : Nat) :
    Link ⟨v, RHS.ofAbstr (SSet.ofList [w]), some .commonPartition⟩ := by
  constructor <;> rfl

/-- The image of a link under `Constraints.replace` is a link. -/
theorem replace_link {v u : Nat} {p : LPart} (hne : v ≠ u) (hp : Link p) :
    ∀ x ∈ (replace v u p).elems, Link x := by
  obtain ⟨hc, ha⟩ := hp
  unfold replace
  have hnot : ¬ (p.rhs.abstr.contains v = true ∧ p.rhs.abstr.contains u = true) := by
    rintro ⟨h1, h2⟩
    match hm : p.rhs.abstr.elems with
    | [] => rw [hm] at ha; simp at ha
    | [a] =>
      simp only [SSet.contains, hm, List.any_cons, List.any_nil, Bool.or_false] at h1 h2
      exact hne ((LawfulSVal.eq_iff v a).mp h1 |>.trans ((LawfulSVal.eq_iff u a).mp h2).symm)
    | a :: b :: t => rw [hm] at ha; simp at ha
  rw [if_neg (by simpa using hnot)]
  refine ofListQ_mem (P := Link) _ ?_
  intro x hx
  rw [List.mem_singleton.mp hx]
  refine ⟨hc, ?_⟩
  match hm : p.rhs.abstr.elems with
  | [] => rw [hm] at ha; simp at ha
  | [a] => exact map_length_of_singleton _ hm
  | a :: b :: t => rw [hm] at ha; simp at ha

/-! ## 6. `instantiate` on the fragment -/

theorem foldl_concatP_length_le (v u : Nat) : ∀ (l : List LPart) (q : PQueue),
    (∀ p ∈ l, (replace v u p).elems.length ≤ 1) →
    (l.foldl (fun nq p => nq.concatP (replace v u p).elems) q).elems.length
      ≤ q.elems.length + l.length
  | [], q, _ => by simp
  | p :: t, q, hl => by
    simp only [List.foldl_cons, List.length_cons]
    have h1 := foldl_concatP_length_le v u t (q.concatP (replace v u p).elems)
      (fun z hz => hl z (List.mem_cons_of_mem _ hz))
    have h2 := concatP_length_le (replace v u p).elems q
    have h3 := hl p List.mem_cons_self
    omega

theorem foldl_concatP_mem {P : LPart → Prop}
    (hlink : ∀ a b : Nat, P ⟨a, RHS.ofAbstr (SSet.ofList [b]), some .commonPartition⟩)
    (v u : Nat) : ∀ (l : List LPart) (q : PQueue),
    (∀ p ∈ l, ∀ x ∈ (replace v u p).elems, P x) → (∀ x ∈ q.elems, P x) →
    ∀ x ∈ (l.foldl (fun nq p => nq.concatP (replace v u p).elems) q).elems, P x
  | [], q, _, hq => by simpa using hq
  | p :: t, q, hl, hq => by
    simp only [List.foldl_cons]
    exact foldl_concatP_mem hlink v u t (q.concatP (replace v u p).elems)
      (fun z hz => hl z (List.mem_cons_of_mem _ hz))
      (concatP_mem hlink _ q (hl p List.mem_cons_self) hq)

theorem partition_fst_mem {P : LPart → Prop} {q : PQueue} {f : LPart → Bool}
    (hq : ∀ x ∈ q.elems, P x) : ∀ x ∈ (q.partition f).1.elems, P x := by
  simp only [PQueue.partition]
  refine sset_ofList_mem _ ?_
  intro x hx
  exact hq x (List.mem_of_mem_filter (List.mem_reverse.mp hx))

theorem partition_snd_mem {P : LPart → Prop} {q : PQueue} {f : LPart → Bool}
    (hq : ∀ x ∈ q.elems, P x) : ∀ x ∈ (q.partition f).2.elems, P x := by
  simp only [PQueue.partition]
  intro x hx
  exact hq x (List.mem_of_mem_filter hx)

/-- `Constraints.instantiate`, with its two pattern-`let`s spelled out. -/
theorem instantiate_eq (ns : Names) (v u : Nat) (incm proc : PQueue) (env : Env) :
    instantiate ns v u incm proc env =
      (if env.contains v then
        .error ("panic: reinstantiated type " ++ varStr ns v ++ " to " ++ varStr ns u ++
                " but it was already bound")
      else
        .ok (((proc.partition (fun p => p.involves v)).1.concat
                (incm.partition (fun p => p.involves v)).1).elems.foldl
              (fun nq p => nq.concatP (replace v u p).elems)
              (incm.partition (fun p => p.involves v)).2,
             (proc.partition (fun p => p.involves v)).2,
             env.instantiate v (.alias u))) := rfl

/-- **`Constraints.instantiate` on the fragment**: the two queues keep only links, and hold
no more partitions between them than they did. -/
theorem instantiate_link {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hne : v ≠ u)
    (hi : ∀ p ∈ incm.elems, Link p) (hp : ∀ p ∈ proc.elems, Link p)
    (hok : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, Link x) ∧ (∀ x ∈ np.elems, Link x) ∧
      ni.elems.length + np.elems.length ≤ incm.elems.length + proc.elems.length := by
  have hpps : ∀ x ∈ (proc.partition (fun p => p.involves v)).1.elems, Link x :=
    partition_fst_mem hp
  have hqps : ∀ x ∈ (incm.partition (fun p => p.involves v)).1.elems, Link x :=
    partition_fst_mem hi
  have hnproc : ∀ x ∈ (proc.partition (fun p => p.involves v)).2.elems, Link x :=
    partition_snd_mem hp
  have hnincm : ∀ x ∈ (incm.partition (fun p => p.involves v)).2.elems, Link x :=
    partition_snd_mem hi
  have hnps : ∀ x ∈ ((proc.partition (fun p => p.involves v)).1.concat
      (incm.partition (fun p => p.involves v)).1).elems, Link x :=
    sset_concat_mem hpps hqps
  have hlen := foldl_concatP_length_le v u
      ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems
      (incm.partition (fun p => p.involves v)).2
      (fun q hq => replace_length_le_one hne (hnps q hq).2)
  have hmem := foldl_concatP_mem (P := Link) (fun _ _ => link_commonPartition _ _) v u
      ((proc.partition (fun p => p.involves v)).1.concat
        (incm.partition (fun p => p.involves v)).1).elems
      (incm.partition (fun p => p.involves v)).2
      (fun q hq => replace_link hne (hnps q hq)) hnincm
  have hc := concat_length_le (proc.partition (fun p => p.involves v)).1
      (incm.partition (fun p => p.involves v)).1
  have hpi := partition_length_le incm (fun p => p.involves v)
  have hpp := partition_length_le proc (fun p => p.involves v)
  rw [instantiate_eq] at hok
  split at hok
  · exact absurd hok (by simp)
  · simp only [Except.ok.injEq, Prod.mk.injEq] at hok
    obtain ⟨hni, hnp, -⟩ := hok
    refine ⟨?_, ?_, ?_⟩
    · rw [← hni]; exact hmem
    · rw [← hnp]; exact hnproc
    · rw [← hni, ← hnp]; omega

/-- ...and `unify` either does that or does nothing at all. -/
theorem unifyVars_link {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env}
    (hi : ∀ p ∈ incm.elems, Link p) (hp : ∀ p ∈ proc.elems, Link p)
    (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) :
    (∀ x ∈ ni.elems, Link x) ∧ (∀ x ∈ np.elems, Link x) ∧
      ni.elems.length + np.elems.length ≤ incm.elems.length + proc.elems.length := by
  unfold unifyVars at h
  split at h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨h1, h2, -⟩ := h
    exact ⟨h1 ▸ hi, h2 ▸ hp, by rw [← h1, ← h2]⟩
  · rename_i hvu
    exact instantiate_link (by simpa using hvu) hi hp h

/-! ## 7. `Terminates` on the fragment -/

/-- **The step.**  On the fragment `step` can only unify, the fragment is preserved, and the
two queues lose at least one partition. -/
theorem step_linkOnly {s s' : State} (h : LinkOnly s) (hst : step s = .continue s') :
    LinkOnly s' ∧ qsize s' < qsize s := by
  unfold step at hst
  cases hd : s.incm.dequeue with
  | none => rw [hd] at hst; exact absurd hst (by simp)
  | some rr =>
    obtain ⟨r, rest⟩ := rr
    rw [hd] at hst
    simp only [State.log] at hst
    have hrl : Link r := h r (List.mem_append_left _ (dequeue_mem hd))
    have hrest : ∀ x ∈ rest.elems, Link x := fun x hx =>
      h x (List.mem_append_left _ (dequeue_sub hd x hx))
    have hproc : ∀ x ∈ s.proc.elems, Link x := fun x hx => h x (List.mem_append_right _ hx)
    have hlen : rest.elems.length + 1 = s.incm.elems.length := dequeue_length_lt hd
    split at hst
    · -- common
      rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at hst; exact absurd hst (by simp)
      | ok t =>
        obtain ⟨ni, np, e⟩ := t
        rw [hu] at hst
        simp only [StepResult.continue.injEq] at hst
        obtain ⟨h1, h2, h3⟩ := unifyVars_link hrest hproc hu
        subst hst
        exact ⟨fun p hp => by
            rcases List.mem_append.mp hp with hm | hm
            · exact h1 p hm
            · exact h2 p hm,
          by simp only [qsize]; omega⟩
    · split at hst
      · rename_i he; rw [not_isEmpty_of_link hrl.2] at he; exact absurd he (by simp)
      · split at hst
        · rename_i he
          exfalso
          have : r.rhs.abstr.elems.length = 1 := hrl.2
          simp only [SSet.isEmpty, List.isEmpty_iff] at he
          rw [he] at this
          simp at this
        · split at hst
          · -- unify
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at hst; exact absurd hst (by simp)
            | ok t =>
              obtain ⟨ni, np, e⟩ := t
              rw [hu] at hst
              simp only [StepResult.continue.injEq] at hst
              obtain ⟨h1, h2, h3⟩ := unifyVars_link hrest hproc hu
              subst hst
              exact ⟨fun p hp => by
                  rcases List.mem_append.mp hp with hm | hm
                  · exact h1 p hm
                  · exact h2 p hm,
                by simp only [qsize]; omega⟩
          · -- learn: unreachable, `single?` is `some`
            rename_i hs
            obtain ⟨w, hw⟩ := single_of_link hrl.1 hrl.2
            rw [hw] at hs
            exact absurd hs (by simp)

/-- **`Terminates` on the fragment, with the explicit bound.**  The loop finishes within
`|incm| + |proc|` dequeues. -/
theorem linkOnly_terminates_aux : ∀ (n : Nat) (s : State), qsize s ≤ n → LinkOnly s →
    Finished (run s (n + 1))
  | 0, s, hq, hl => by
    simp only [run]
    cases hst : step s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      exfalso
      have := (step_linkOnly hl hst).2
      omega
  | n + 1, s, hq, hl => by
    simp only [run]
    cases hst : step s with
    | done s' => trivial
    | died m s' => trivial
    | «continue» s' =>
      obtain ⟨hl', hlt⟩ := step_linkOnly hl hst
      exact linkOnly_terminates_aux n s' (by omega) hl'

/-- **The fragment terminates**, within `|incm| + |proc|` dequeues. -/
theorem linkOnly_terminates {s : State} (h : LinkOnly s) : Terminates s :=
  ⟨qsize s + 1, linkOnly_terminates_aux (qsize s) s (le_refl _) h⟩

/-- The same, as the bound: the run finishes at the fuel `qsize s + 1`. -/
theorem linkOnly_run {s : State} (h : LinkOnly s) : Finished (run s (qsize s + 1)) :=
  linkOnly_terminates_aux (qsize s) s (le_refl _) h

end Rowpartition.Loop
