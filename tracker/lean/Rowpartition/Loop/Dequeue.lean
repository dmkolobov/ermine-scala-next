/-
# L5 round 5 (R5.3): the DEQUEUE ORDER, and why it does not repair the redirect

The round-4 review's T-9 names the dequeue order as "the cheapest untried lever": no measure
of rounds 1-4 uses it, and in R4.1's witness the link `Q.++!` manufactures is dequeued at
once, so the carrier the redirect destroys is only transiently lost.  The proposed lemma is

> under the real order, between a carrier's loss at the redirect and the next examination of
> its key, the carrier is re-established.

**It is false, and the order is the reason it is false.**  `Q.++!` refuses to insert `p` when
some `u <- p.rhs` is already in the queue and inserts the LINK `u <- (p.lhs)` instead; and
`PQueue.+` extends the type-variable graph with the edge `u -> p.lhs`, which makes `p.lhs` a
CHILD of `u`.  `Q.pop` takes the minimum of `graph.sort`, a reverse-topological order --
children before parents -- so every partition of the swallowed variable `p.lhs` is dequeued
BEFORE the link that would repair it.  The repair is scheduled last, exactly when it is
needed first.

* §1  `Q.pop` returns a partition of minimal priority (`dequeue_prio_min`), and the
      corollary that a strictly smaller priority is always served first
      (`dequeue_not_of_lt`).
* §2  the redirect's equation, and the edge it adds (`insertP_redirect`, `insertNP_edge`).
* §3  `RepairBeforeExam`, stated over `Reaches`, and REFUTED on `Loop.mS0` -- R4.1's own
      four-constraint satisfiable witness, where the key `(v1, {l0})` loses its carrier at
      the redirect and is examined by the VERY NEXT dequeue, which MINTS at it while the
      link is still sitting in the queue.  `mS1.incm.graph.prio 1 = 3 < 4 = prio 2` is why.
-/
import Rowpartition.Loop.Pump

set_option maxRecDepth 100000

namespace Rowpartition.Loop

/-! ## 1. `Q.pop` is a minimum -/

theorem foldl_min_le_init : ∀ (l : List Nat) (a : Nat), l.foldl Nat.min a ≤ a
  | [], a => le_refl a
  | x :: t, a => le_trans (foldl_min_le_init t (Nat.min a x)) (Nat.min_le_left a x)

theorem foldl_min_le_mem : ∀ (l : List Nat) (a x : Nat), x ∈ l → l.foldl Nat.min a ≤ x
  | [], _, _, hx => by simp at hx
  | y :: t, a, x, hx => by
    rcases List.mem_cons.mp hx with rfl | ht
    · exact le_trans (foldl_min_le_init t (Nat.min a x)) (Nat.min_le_right a x)
    · exact foldl_min_le_mem t (Nat.min a y) x ht

/-- **`Q.pop` returns a partition of MINIMAL priority.**  `Constraints.Q.pop` splits the
finger tree on "the prefix's minimum priority equals the whole tree's", so the element it
returns minimises `graph.sort(lhs)` over the whole queue. -/
theorem dequeue_prio_min {q : PQueue} {r : LPart} {rest : PQueue}
    (h : q.dequeue = some (r, rest)) :
    ∀ p ∈ q.elems, q.graph.prio r.lhs ≤ q.graph.prio p.lhs := by
  intro p hp
  simp only [PQueue.dequeue] at h
  split at h
  · rename_i he; rw [he] at hp; simp at hp
  · rename_i e0 tl he
    split at h
    · exact absurd h (by simp)
    · rename_i i hi
      split at h
      · exact absurd h (by simp)
      · rename_i z hg
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨hz, -⟩ := h
        obtain ⟨hlt, hpi, -⟩ := List.findIdx?_eq_some_iff_getElem.mp hi
        obtain ⟨hlt2, hzz⟩ := List.getElem?_eq_some_iff.mp hg
        rw [hz] at hzz
        rw [hzz] at hpi
        have hrm : q.graph.prio r.lhs =
            ((e0 :: tl).map (fun x => q.graph.prio x.lhs)).foldl Nat.min (q.graph.prio e0.lhs) :=
          by simpa using hpi
        rw [hrm]
        refine foldl_min_le_mem _ _ _ ?_
        refine List.mem_map.mpr ⟨p, ?_, rfl⟩
        rw [← he]; exact hp

/-- **A dequeue removes exactly one partition.** -/
theorem dequeue_length_lt {q : PQueue} {r : LPart} {rest : PQueue}
    (h : q.dequeue = some (r, rest)) : rest.elems.length + 1 = q.elems.length := by
  simp only [PQueue.dequeue] at h
  split at h
  · exact absurd h (by simp)
  · rename_i e0 tl he
    split at h
    · exact absurd h (by simp)
    · rename_i i hi
      split at h
      · exact absurd h (by simp)
      · rename_i z hg
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨-, hr⟩ := h
        obtain ⟨hlt, -, -⟩ := List.findIdx?_eq_some_iff_getElem.mp hi
        rw [he, ← hr]
        simp only [List.length_eraseIdx, hlt, if_pos]
        omega

/-- **The dequeued partition is in the queue.** -/
theorem dequeue_mem {q : PQueue} {r : LPart} {rest : PQueue}
    (h : q.dequeue = some (r, rest)) : r ∈ q.elems := by
  simp only [PQueue.dequeue] at h
  split at h
  · exact absurd h (by simp)
  · rename_i e0 tl he
    split at h
    · exact absurd h (by simp)
    · rename_i i hi
      split at h
      · exact absurd h (by simp)
      · rename_i z hg
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨hz, -⟩ := h
        obtain ⟨hlt2, hzz⟩ := List.getElem?_eq_some_iff.mp hg
        rw [he, ← hz, ← hzz]
        exact List.getElem_mem hlt2

/-- **The queue only shrinks at a dequeue.** -/
theorem dequeue_sub {q : PQueue} {r : LPart} {rest : PQueue}
    (h : q.dequeue = some (r, rest)) : ∀ x ∈ rest.elems, x ∈ q.elems := by
  intro x hx
  simp only [PQueue.dequeue] at h
  split at h
  · exact absurd h (by simp)
  · rename_i e0 tl he
    split at h
    · exact absurd h (by simp)
    · rename_i i hi
      split at h
      · exact absurd h (by simp)
      · rename_i z hg
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨-, hr⟩ := h
        rw [← hr] at hx
        rw [he]
        exact List.eraseIdx_subset hx

/-- **The order is served strictly.**  A partition whose left-hand side has a strictly
smaller priority than `u`'s is dequeued before any partition at `u`: `pop` cannot return the
latter while the former is in the queue. -/
theorem dequeue_not_of_lt {q : PQueue} {r : LPart} {rest : PQueue} {p : LPart}
    (h : q.dequeue = some (r, rest)) (hp : p ∈ q.elems)
    (hlt : q.graph.prio p.lhs < q.graph.prio r.lhs) : False :=
  absurd (dequeue_prio_min h p hp) (by omega)

/-! ## 2. The redirect, and the edge it adds -/

/-- **`Q.++!`'s redirect, as an equation.**  A right-hand side already present in the queue
turns the insertion of `p` into the insertion of the LINK `u <- (p.lhs)` -- so `p` itself,
and every fact it carried, is not inserted. -/
theorem insertP_redirect {q : PQueue} {p : LPart} {u : Nat}
    (h1 : p.isSelfUnification = false)
    (h2 : q.elems.any (fun x => PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) && x.eqv p)
            = false)
    (h3 : q.rhsLookup p.rhs = some u) :
    q.insertP p =
      q.insertNP ⟨u, RHS.ofAbstr (SSet.ofList [p.lhs]), some .commonPartition⟩ := by
  simp only [PQueue.insertP, h1, h2, h3, Bool.false_eq_true, if_false]

/-- **`PQueue.+` extends the graph with the partition's own edges**, so the link
`u <- (p.lhs)` makes `p.lhs` a CHILD of `u` in the type-variable graph -- and
`StreamTUtils.reverseTopSort` puts children first. -/
theorem insertNP_graph {q : PQueue} {p : LPart} (h1 : p.isSelfUnification = false)
    (h2 : q.elems.any (fun x => PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf p) && x.eqv p)
            = false) :
    (q.insertNP p).graph = (q.graph.addPart p).1 := by
  simp only [PQueue.insertNP, h1, h2, Bool.false_eq_true, if_false]

/-! ## 3. The repair claim, and its refutation -/

/-- **R5.3, stated.**  "Between a carrier's loss and the next examination of its key, the
carrier is re-established": if a step destroys every carrier of `(v, K)` and the key's
variable is dequeued again at a later state `t`, then `t` carries the key again. -/
def RepairBeforeExam : Prop :=
  ∀ (s s' t : State) (v : Nat) (K : SSet Lbl) (r : LPart) (rest : PQueue),
    step s = .continue s' → carriersOf s v K ≠ [] → carriersOf s' v K = [] →
    Reaches s' t → t.incm.dequeue = some (r, rest) → r.lhs = v →
    carriersOf t v K ≠ []

/-- The key R4.1's redirect destroys: `v1`'s row `{l0}`. -/
def rKey : SSet Lbl := SSet.ofList [wLbl]

/-- Before the redirect the key is carried, by `v1 <- (v0, (|l0|))`. -/
theorem rCarried : carriersOf mS0 1 rKey = [0] := rfl

/-- After it, by nothing: `Q.++!` swallowed the bare `v1 <- ((|l0|))` onto the twin
`v2 <- ((|l0|))` and left the link `v2 <- (v1)` in its place. -/
theorem rLost : carriersOf mS1 1 rKey = [] := rfl

/-- The link is in the queue... -/
theorem rLink : mS1.incm.elems = [mR, mD, mC] := rfl

/-- ...and it is NOT what the next dequeue takes: the very next examination is at `v1`, the
swallowed variable itself. -/
theorem rNext : (mS1.incm.dequeue.map (fun p => p.1.lhs)) = some 1 := rfl

/-- The reason, in the graph: the redirect put the link at `v2`, and `v2` is `v1`'s PARENT,
so `v1` is served first. -/
theorem rPrio : mS1.incm.graph.prio 1 < mS1.incm.graph.prio 2 := by decide

/-- And the examination MINTS -- at the key the redirect had just uncarried. -/
theorem rMints : splitMintKey mS1 = some (1, rKey) := rfl

/-- The queue the second dequeue leaves behind. -/
def mRest : PQueue :=
  match mS1.incm.dequeue with
  | some (_, q) => q
  | none => PQueue.empty

theorem rDequeue : mS1.incm.dequeue = some (mD, mRest) := rfl

/-- **`RepairBeforeExam` IS FALSE.**  R4.1's four-constraint satisfiable witness: the
redirect at step one destroys every carrier of `(v1, {l0})`, and step two dequeues `v1`'s own
premise and mints at the key, with the repairing link still in the queue.  The dequeue order
does not merely fail to help; it is what schedules the link last. -/
theorem repairBeforeExam_false : ¬ RepairBeforeExam := by
  intro h
  exact h mS0 mS1 mS1 1 rKey mD mRest mS0_step (by rw [rCarried]; simp) rLost
    (Reaches.refl mS1) rDequeue rfl rLost

/-- What DOES re-establish the carrier is the mint itself, one step later: the loop pays for
the redirect's damage with a fresh id. -/
theorem rReCarried : carriersOf mS2 1 rKey = [100] := rfl

end Rowpartition.Loop
