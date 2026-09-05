/-
# The bridge: a loop partition IS a `Rowpartition.Constraint`

The relational development speaks of `Rowpartition.Constraint` in `mk a S k` form -- a
left-hand variable, a FINSET of right-hand variables and a FINSET of labels.  The loop model
cannot use that type directly: the queue's key is `rhs.hashCode`, `Partition.toString` prints
`abs.mkString(" ")`, and `learnPartitions` returns a `Set[Partition]` the caller ITERATES, so
the model has to carry the sets' iteration order and each partition's `Inference` tag.

This module gives the total conversion both ways and proves it a bijection between the
`mk`-form constraints and the CANONICAL loop partitions, so the L3 refinement proofs can move
between the two vocabularies.  It also proves the fact those proofs will actually use: the
model's own notion of partition equality -- `LPart.eqv`, which is `Partition.equals`, and is
what the queue and every `Set[Partition]` compare with -- is EQUALITY OF THE CONSTRAINTS.

Along the way it establishes that `SSet` really is a set: `champSort`, the CHAMP iteration
order, is a permutation, so no `SSet` operation can duplicate or lose an element.
-/
import Rowpartition.Loop.State
import Rowpartition.Divergence

namespace Rowpartition.Loop

open Rowpartition
open scoped List

/-! ## 1. `champSort` is a permutation -/

section Perm

variable {α : Type}

/-- Adding one element to bucket `j` of a bucket table permutes the flattened table. -/
theorem flatten_map_range_update (g : Nat → List α) (a : α) :
    ∀ (n j : Nat), j < n →
      (((List.range n).map (fun i => if i = j then a :: g i else g i)).flatten).Perm
        (a :: (((List.range n).map g).flatten)) := by
  intro n
  induction n with
  | zero => intro j hj; omega
  | succ n ih =>
    intro j hj
    rw [List.range_succ]
    simp only [List.map_append, List.flatten_append, List.map_cons, List.map_nil,
      List.flatten_cons, List.flatten_nil, List.append_nil]
    rcases Nat.lt_or_ge j n with h | h
    · rw [if_neg (by omega : ¬ (n = j))]
      calc
        (((List.range n).map (fun i => if i = j then a :: g i else g i)).flatten) ++ g n
            ~ (a :: (((List.range n).map g).flatten)) ++ g n := (ih j h).append_right (g n)
        _ = a :: ((((List.range n).map g).flatten) ++ g n) := rfl
    · have hjn : j = n := by omega
      subst hjn
      rw [if_pos rfl]
      have : ∀ i ∈ List.range j, (if i = j then a :: g i else g i) = g i := by
        intro i hi
        rw [if_neg]
        exact Nat.ne_of_lt (List.mem_range.mp hi)
      rw [List.map_congr_left this]
      exact List.perm_middle

/-- Two bucket tables concatenated table-wise. -/
theorem flatten_append_perm (f g : Nat → List α) :
    ∀ (l : List Nat),
      (((l.map f).flatten) ++ ((l.map g).flatten)).Perm ((l.map (fun i => f i ++ g i)).flatten)
  | [] => by simp
  | i :: l => by
    simp only [List.map_cons, List.flatten_cons]
    have ih := flatten_append_perm f g l
    calc
      (f i ++ ((l.map f).flatten)) ++ (g i ++ ((l.map g).flatten))
          = f i ++ (((l.map f).flatten) ++ (g i ++ ((l.map g).flatten))) := by
            rw [List.append_assoc]
      _ ~ f i ++ (g i ++ (((l.map f).flatten) ++ ((l.map g).flatten))) := by
            refine List.Perm.append_left _ ?_
            rw [← List.append_assoc, ← List.append_assoc]
            exact List.Perm.append_right _ (List.perm_append_comm)
      _ ~ f i ++ (g i ++ ((l.map (fun i => f i ++ g i)).flatten)) :=
            List.Perm.append_left _ (List.Perm.append_left _ ih)
      _ = (f i ++ g i) ++ ((l.map (fun i => f i ++ g i)).flatten) := by rw [List.append_assoc]

/-- Bucket tables that agree up to permutation flatten to permutations. -/
theorem flatten_map_perm (f g : Nat → List α) :
    ∀ (l : List Nat), (∀ i ∈ l, (f i).Perm (g i)) →
      ((l.map f).flatten).Perm ((l.map g).flatten)
  | [], _ => by simp
  | i :: l, h => by
    simp only [List.map_cons, List.flatten_cons]
    exact List.Perm.append (h i (by simp))
      (flatten_map_perm f g l (fun j hj => h j (by simp [hj])))

/-- Bucketing a list by a key below `n` and concatenating the buckets in key order is a
permutation of the list. -/
theorem flatten_buckets_perm (key : α → Nat) (n : Nat) :
    ∀ (xs : List α), (∀ x ∈ xs, key x < n) →
      (((List.range n).map (fun i => xs.filter (fun x => key x == i))).flatten).Perm xs := by
  intro xs
  induction xs with
  | nil => intro _; simp
  | cons a t ih =>
    intro h
    have ha : key a < n := h a (by simp)
    have ht : ∀ x ∈ t, key x < n := fun x hx => h x (by simp [hx])
    have step : ∀ i, (a :: t).filter (fun x => key x == i) =
        (if i = key a then a :: t.filter (fun x => key x == i)
         else t.filter (fun x => key x == i)) := by
      intro i
      rw [List.filter_cons]
      by_cases hi : i = key a
      · subst hi; simp
      · have hne : ¬ (key a = i) := fun hh => hi hh.symm
        simp [hne, hi]
    rw [List.map_congr_left (fun i _ => step i)]
    refine ((flatten_map_range_update (fun i => t.filter (fun x => key x == i)) a n
      (key a) ha).trans ?_)
    exact (ih ht).cons a

end Perm

namespace SSet

variable {α : Type} [SVal α]

/-- The CHAMP order is a permutation of the elements: nothing is duplicated or dropped. -/
theorem champSort_perm : ∀ (d shift : Nat) (xs : List α), (champSort d shift xs).Perm xs := by
  intro d
  induction d with
  | zero => intro shift xs; exact List.Perm.refl xs
  | succ d ih =>
    intro shift xs
    simp only [champSort]
    by_cases h : xs.length ≤ 1
    · simp [h]
    · simp only [h, if_false]
      set key : α → Nat := fun x => champMask (improve (SVal.hsh x)) shift with hkey
      set B : Nat → List α := fun i => xs.filter (fun x => key x == i) with hB
      have hcat : ∀ i,
          ((if (B i).length == 1 then B i else []) ++
           (if (B i).length == 1 then [] else champSort d (shift + 5) (B i))).Perm (B i) := by
        intro i
        by_cases hl : (B i).length == 1
        · simp [hl]
        · simp only [hl, if_false, List.nil_append, List.append_nil]
          exact ih (shift + 5) (B i)
      refine (flatten_append_perm _ _ (List.range 32)).trans ?_
      refine (List.Perm.trans ?_ (flatten_buckets_perm key 32 xs
        (fun x _ => champMask_lt _ _)))
      exact flatten_map_perm _ _ (List.range 32) (fun i _ => hcat i)


/-- `champ` is a permutation of its input. -/
theorem champ_perm (xs : List α) : (champ xs).Perm xs := champSort_perm 7 0 xs

/-- The elements of an `SSet` are pairwise distinct. -/
def Nodup (s : SSet α) : Prop := s.elems.Nodup

end SSet

/-! ## 2. Every `SSet` really is a set -/

/-- What Scala's `Set` needs of `equals`: it must DECIDE equality.  True of the two element
types that appear inside an `RHS` -- row variables and labels -- and deliberately FALSE of
`LPart` and `RHS` themselves, whose `equals` ignores the `Inference` tag and the sets'
iteration order.  That asymmetry is the whole reason this file exists. -/
class LawfulSVal (α : Type) [SVal α] : Prop where
  eq_iff : ∀ a b : α, SVal.eq a b = true ↔ a = b

instance : LawfulSVal Nat := ⟨fun a b => by simp [SVal.eq, svalNat]⟩

instance : LawfulSVal Lbl := ⟨fun a b => by simp [SVal.eq, svalLbl]⟩

namespace SSet

variable {α : Type} [SVal α]

theorem contains_iff [LawfulSVal α] (s : SSet α) (x : α) :
    s.contains x = true ↔ x ∈ s.elems := by
  unfold contains
  rw [List.any_eq_true]
  constructor
  · rintro ⟨y, hy, h⟩; rwa [(LawfulSVal.eq_iff x y).mp h]
  · intro h; exact ⟨x, h, (LawfulSVal.eq_iff x x).mpr rfl⟩

theorem nodup_empty : (empty : SSet α).Nodup := List.nodup_nil

theorem nodup_excl {s : SSet α} (h : s.Nodup) (x : α) : (s.excl x).Nodup := by
  unfold excl Nodup
  split
  · exact ((champ_perm _).nodup_iff).mpr (List.Nodup.filter _ h)
  · exact List.Nodup.filter _ h

theorem nodup_filter {s : SSet α} (h : s.Nodup) (p : α → Bool) : (s.filter p).Nodup := by
  unfold filter Nodup
  split
  · exact ((champ_perm _).nodup_iff).mpr (List.Nodup.filter _ h)
  · exact List.Nodup.filter _ h

theorem nodup_incl [LawfulSVal α] {s : SSet α} (h : s.Nodup) (x : α) : (s.incl x).Nodup := by
  unfold incl Nodup
  split
  · exact h
  · rename_i hc
    have hx : x ∉ s.elems := fun hm => by
      rw [(contains_iff s x).mpr hm] at hc; exact hc rfl
    have hnd : (s.elems ++ [x]).Nodup :=
      List.Nodup.append h (List.nodup_singleton x) (List.disjoint_singleton.mpr hx)
    split
    · exact ((champ_perm _).nodup_iff).mpr hnd
    · exact hnd

theorem nodup_foldl_incl [LawfulSVal α] :
    ∀ (l : List α) (s : SSet α), s.Nodup → (l.foldl incl s).Nodup
  | [], _, h => h
  | x :: l, s, h => nodup_foldl_incl l (s.incl x) (nodup_incl h x)

theorem nodup_foldl_incl_map {β : Type} [SVal β] [LawfulSVal β] (f : α → β) :
    ∀ (l : List α) (s : SSet β), s.Nodup → (l.foldl (fun acc x => acc.incl (f x)) s).Nodup
  | [], _, h => h
  | x :: l, s, h => nodup_foldl_incl_map f l (s.incl (f x)) (nodup_incl h (f x))

theorem nodup_ofList [LawfulSVal α] (xs : List α) : (ofList xs).Nodup :=
  nodup_foldl_incl xs empty nodup_empty

theorem nodup_map {β : Type} [SVal β] [LawfulSVal β] {s : SSet α} (f : α → β) :
    (s.map f).Nodup := by
  unfold map
  exact nodup_foldl_incl_map f _ ⟨s.hashed, []⟩ (show ([] : List β).Nodup from List.nodup_nil)

/-- With a lawful `equals`, `concat`'s CHAMP branch rewrites nothing: the representative it
substitutes for a shared element is EQUAL to the one it replaces. -/
theorem nodup_concat [LawfulSVal α] {s t : SSet α} (hs : s.Nodup) (ht : t.Nodup) :
    (s.concat t).Nodup := by
  unfold concat Nodup
  split
  · have hid : ∀ x : α, pickRep s.elems t.elems x = x := by
      intro x
      unfold pickRep
      cases hf : s.elems.find? (fun y => SVal.eq y x) with
      | none => simp
      | some sx =>
        have hb : SVal.eq sx x = true := by
          have := List.find?_some hf; simpa using this
        have hsx : sx = x := (LawfulSVal.eq_iff sx x).mp hb
        simp [hsx]
    rw [List.map_congr_left (g := id) (fun x _ => hid x), List.map_id]
    have hnd : ((s.elems.filter (fun x => !t.contains x)) ++ t.elems).Nodup := by
      refine List.Nodup.append (List.Nodup.filter _ hs) ht ?_
      intro a ha hb
      have h2 : (!t.contains a) = true := (List.mem_filter.mp ha).2
      exact absurd ((contains_iff t a).mpr hb) (by simpa using h2)
    exact ((champ_perm _).nodup_iff).mpr hnd
  · exact nodup_foldl_incl _ _ hs

theorem nodup_removedAll {s t : SSet α} (h : s.Nodup) : (s.removedAll t).Nodup := by
  unfold removedAll
  induction t.elems generalizing s with
  | nil => exact h
  | cons x l ih => exact ih (nodup_excl h x)

theorem nodup_inter {s t : SSet α} (h : s.Nodup) : (s.inter t).Nodup := nodup_filter h _

/-- For duplicate-free sets, Scala's `equals` -- `size == that.size && subsetOf(that)` -- is
equality of the underlying finite sets. -/
theorem eqv_iff_toFinset [LawfulSVal α] [DecidableEq α] {s t : SSet α}
    (hs : s.Nodup) (ht : t.Nodup) :
    s.eqv t = true ↔ s.elems.toFinset = t.elems.toFinset := by
  have hcard : s.elems.toFinset.card = s.elems.length := List.toFinset_card_of_nodup hs
  have hcard' : t.elems.toFinset.card = t.elems.length := List.toFinset_card_of_nodup ht
  unfold eqv subsetOf size
  simp only [Bool.and_eq_true, beq_iff_eq]
  constructor
  · rintro ⟨hlen, hsub⟩
    have hsub' : s.elems.toFinset ⊆ t.elems.toFinset := by
      intro a ha
      exact List.mem_toFinset.mpr
        ((contains_iff t a).mp ((List.all_eq_true.mp hsub) a (List.mem_toFinset.mp ha)))
    exact Finset.eq_of_subset_of_card_le hsub' (by rw [hcard, hcard', hlen])
  · intro h
    have hlen : s.elems.length = t.elems.length := by
      rw [← hcard, ← hcard', h]
    refine ⟨hlen, List.all_eq_true.mpr (fun a ha => ?_)⟩
    exact (contains_iff t a).mpr (List.mem_toFinset.mp (h ▸ List.mem_toFinset.mpr ha))

end SSet

/-! ## 3. The conversion, and the bijection -/

/-- The `Rowpartition.Constraint` a loop partition denotes. -/
def LPart.toConstraint (p : LPart) : Constraint :=
  Rowpartition.mk p.lhs p.rhs.abstr.elems.toFinset (p.rhs.conc.elems.map Lbl.n).toFinset

/-- The canonical loop partition of a constraint: both sets sorted, no provenance tag, and
the representation flag the Scala would carry at that size. -/
def LPart.ofConstraint (c : Constraint) : LPart :=
  { lhs := c.lhs,
    rhs :=
      ⟨⟨decide (4 < (slist (vset c)).length), slist (vset c)⟩,
       ⟨decide (4 < (c.conc.sort (· ≤ ·)).length),
        (c.conc.sort (· ≤ ·)).map (fun n => ({ n := n } : Lbl))⟩⟩,
    inf := none }

@[simp] theorem LPart.lhs_toConstraint (p : LPart) : p.toConstraint.lhs = p.lhs := rfl

@[simp] theorem LPart.vset_toConstraint (p : LPart) :
    vset p.toConstraint = p.rhs.abstr.elems.toFinset := vset_mk _ _ _

@[simp] theorem LPart.conc_toConstraint (p : LPart) :
    p.toConstraint.conc = (p.rhs.conc.elems.map Lbl.n).toFinset := rfl

/-- `ofConstraint` is a section of `toConstraint` on every `mk`-form constraint -- which is
every constraint the relational development builds. -/
theorem LPart.toConstraint_ofConstraint (a : Var) (S : Finset Var) (k : Finset Label) :
    (LPart.ofConstraint (Rowpartition.mk a S k)).toConstraint = Rowpartition.mk a S k := by
  unfold LPart.ofConstraint LPart.toConstraint
  have h2 : ((k.sort (· ≤ ·)).map (fun n => ({ n := n } : Lbl))).map Lbl.n
      = k.sort (· ≤ ·) := by
    rw [List.map_map]; exact List.map_id_fun' ▸ rfl
  simp only [lhs_mk, conc_mk, vset_mk, h2, slist_toFinset, Finset.sort_toFinset]

/-- The two constraints agree exactly when the partitions have the same left-hand variable
and the same two underlying sets. -/
theorem LPart.toConstraint_eq_iff (p q : LPart) :
    p.toConstraint = q.toConstraint ↔
      p.lhs = q.lhs ∧
      p.rhs.abstr.elems.toFinset = q.rhs.abstr.elems.toFinset ∧
      (p.rhs.conc.elems.map Lbl.n).toFinset = (q.rhs.conc.elems.map Lbl.n).toFinset := by
  constructor
  · intro h; exact mk_inj h
  · rintro ⟨h1, h2, h3⟩
    unfold LPart.toConstraint
    rw [h1, h2, h3]

/-- Two labels of ONE solve with the same table index are the SAME label.

L1's `Lbl` was a bare number, so `Lbl.n` was injective by construction and the two lemmas
below needed no hypothesis.  L2's `Lbl` carries the `Name` the compiler hashes and prints
(module, string, fixity `con`, `Global`/`Local`) alongside the index, because the corpus's
labels are real qualified names — so `n` is injective on the labels of one solve, not on the
type.  `RowTrace.solveInput` numbers a solve's labels out of a `LinkedHashMap[Name, Int]`
keyed by Scala's own `Name.equals`, which is exactly this property for every label list the
loop can build from one input; stating it as a hypothesis keeps it checkable rather than
assumed. -/
def LblCoh (l : List Lbl) : Prop := ∀ x ∈ l, ∀ y ∈ l, x.n = y.n → x = y

theorem LblCoh.mono {l m : List Lbl} (h : LblCoh m) (hs : ∀ x ∈ l, x ∈ m) : LblCoh l :=
  fun x hx y hy hn => h x (hs x hx) y (hs y hy) hn

theorem mem_map_n_of_mem {l : List Lbl} {x : Lbl} (h : x ∈ l) : x.n ∈ l.map Lbl.n :=
  List.mem_map.mpr ⟨x, h, rfl⟩

/-- On a coherent list the label sets can be compared either side of `Lbl.n`. -/
theorem toFinset_map_n_iff {l m : List Lbl} (hc : LblCoh (l ++ m)) :
    (l.map Lbl.n).toFinset = (m.map Lbl.n).toFinset ↔ l.toFinset = m.toFinset := by
  constructor
  · intro h
    ext x
    simp only [List.mem_toFinset]
    constructor
    · intro hx
      have hn : x.n ∈ m.map Lbl.n := by
        have hxn := Finset.ext_iff.mp h x.n
        simp only [List.mem_toFinset] at hxn
        exact hxn.mp (mem_map_n_of_mem hx)
      obtain ⟨y, hy, hyx⟩ := List.mem_map.mp hn
      have hxy : x = y :=
        hc x (List.mem_append_left _ hx) y (List.mem_append_right _ hy) hyx.symm
      rw [hxy]; exact hy
    · intro hx
      have hn : x.n ∈ l.map Lbl.n := by
        have hxn := Finset.ext_iff.mp h x.n
        simp only [List.mem_toFinset] at hxn
        exact hxn.mpr (mem_map_n_of_mem hx)
      obtain ⟨y, hy, hyx⟩ := List.mem_map.mp hn
      have hxy : x = y :=
        hc x (List.mem_append_right _ hx) y (List.mem_append_left _ hy) hyx.symm
      rw [hxy]; exact hy
  · intro h
    ext y
    simp only [List.mem_toFinset, List.mem_map]
    constructor
    · rintro ⟨z, hz, rfl⟩
      exact ⟨z, List.mem_toFinset.mp ((Finset.ext_iff.mp h z).mp (List.mem_toFinset.mpr hz)), rfl⟩
    · rintro ⟨z, hz, rfl⟩
      exact ⟨z, List.mem_toFinset.mp ((Finset.ext_iff.mp h z).mpr (List.mem_toFinset.mpr hz)), rfl⟩

/-- The MODEL's notion of partition equality is the RELATION's.  `LPart.eqv` is
`Partition.equals`, which is what the queue's `insert` and every `Set[Partition]` compare
with, and it ignores the `Inference` tag and both sets' iteration order -- exactly the data
`toConstraint` forgets. -/
theorem LPart.eqv_iff_toConstraint {p q : LPart}
    (hpa : p.rhs.abstr.Nodup) (hqa : q.rhs.abstr.Nodup)
    (hpc : p.rhs.conc.Nodup) (hqc : q.rhs.conc.Nodup)
    (hcoh : LblCoh (p.rhs.conc.elems ++ q.rhs.conc.elems)) :
    p.eqv q = true ↔ p.toConstraint = q.toConstraint := by
  rw [LPart.toConstraint_eq_iff, toFinset_map_n_iff hcoh]
  unfold LPart.eqv RHS.eqv
  simp only [Bool.and_eq_true, beq_iff_eq,
    SSet.eqv_iff_toFinset hpa hqa, SSet.eqv_iff_toFinset hpc hqc]

end Rowpartition.Loop
