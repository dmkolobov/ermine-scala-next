import Rowpartition.Basic
import Mathlib.Data.Finset.Card

/-!
# A terminating canonicaliser for row-partition constraints

Ermine's row rules split into GENERATIVE ones (split-concrete, resolution,
common-subexpression, disjunction -- all of which mint fresh variables) and
NON-GENERATIVE ones.  This file implements the non-generative half and settles what
running it to a fixpoint actually buys.

Six rules are implemented, as the constructors of `Step`:

* `occurs`      -- `a <- (a, R)` says exactly that every other part is empty (this is
                   Ermine's self-substitution; it also deletes the vacuous `r <- (r)`);
* `selfDedup`   -- a variable repeated on the right is forced empty;
* `absorb`      -- empty propagation AND concrete instantiation, in one rule;
* `dedup`       -- duplicate constraints, RECOGNISED UP TO PERMUTATION of the RHS;
* `common`      -- common-partition unification;
* `unify`       -- singleton RHS, `a <- (b)`, i.e. the equation `a = b`.

Cancellation and definitional substitution are NOT implemented (see the file's closing
remarks in section 11 and the report).

## What is proved

* **(i) Termination.**  `Step.decreasing`: every rule strictly decreases the explicit
  lexicographic measure `(distinct variables, total RHS size, number of constraints)`,
  whose order is well-founded (`lexLt_wf`, proved from scratch).  `no_infinite_descent`
  turns that into the statement that no infinite reduction sequence exists, and
  `exists_fuel` that the fuelled driver always reaches a normal form.
* **(iii) Meaning preservation.**  `Step.preserves`: each rule preserves the set of
  models EXACTLY -- not merely up to the eliminated variables.  That sharper statement
  is available because a `State` keeps its eliminated variables in a `solved` list,
  read back as the partition constraint `a <- (b)`, which in this language IS the
  equation `a = b` (`sat_eqc`).  Hence also `Step.satisfiable_iff` and
  `Step.entails_iff`, and for the driver `canonN_preserves` / `canonN_entails`.
* **(iv) Sound and complete simplifier, incomplete decision procedure.**  The first half
  is `canonN_entails`; the second is `CriticalPair.normal_form_can_be_unsat`, an
  unsatisfiable normal form.
* **(ii) Confluence -- REFUTED.**  `CriticalPair.not_locally_confluent` and
  `not_joinable` exhibit a critical pair between `occurs` and `absorb` that does not
  join: the two results are distinct normal forms.  `Orientation.results_differ` gives a
  second, independent (and repairable) ambiguity on a SATISFIABLE system.

Two side conditions the informal rule statements omit are also isolated and shown
necessary: `unsat_of_occurs` and `absorb_guard_needed`.
-/

namespace Rowpartition

/-! ## 1. `SatL`: satisfaction as a relation between a row and a list of parts -/

/-- `s` is the disjoint union of the list of parts `L`. -/
def SatL (s : Row) (L : List Row) : Prop :=
  s = L.foldr (· ∪ ·) ∅ ∧ L.Pairwise Disjoint

theorem sat_iff_satL (rho : Assign) (c : Constraint) :
    Sat rho c ↔ SatL (rho c.lhs) (parts rho c) := Iff.rfl

/-- Test for a non-empty row. -/
def ne0 (t : Row) : Bool := decide (t ≠ ∅)

theorem foldr_union_perm {L L' : List Row} (h : L.Perm L') :
    L.foldr (· ∪ ·) ∅ = L'.foldr (· ∪ ·) ∅ := by
  ext a
  rw [mem_foldr_union, mem_foldr_union]
  exact exists_congr fun s => and_congr_left' h.mem_iff

theorem pairwise_disjoint_perm {L L' : List Row} (h : L.Perm L') :
    L.Pairwise Disjoint ↔ L'.Pairwise Disjoint :=
  h.pairwise_iff (fun hd => Disjoint.symm hd)

theorem satL_perm {s : Row} {L L' : List Row} (h : L.Perm L') : SatL s L ↔ SatL s L' := by
  unfold SatL
  rw [foldr_union_perm h, pairwise_disjoint_perm h]

theorem foldr_union_filter (L : List Row) :
    (L.filter ne0).foldr (· ∪ ·) ∅ = L.foldr (· ∪ ·) ∅ := by
  ext a
  rw [mem_foldr_union, mem_foldr_union]
  constructor
  · rintro ⟨s, hs, ha⟩; exact ⟨s, (List.mem_filter.mp hs).1, ha⟩
  · rintro ⟨s, hs, ha⟩
    refine ⟨s, List.mem_filter.mpr ⟨hs, ?_⟩, ha⟩
    simp only [ne0, decide_eq_true_eq]
    intro h; rw [h] at ha; simp at ha

theorem pairwise_disjoint_filter (L : List Row) :
    (L.filter ne0).Pairwise Disjoint ↔ L.Pairwise Disjoint := by
  induction L with
  | nil => simp
  | cons x L ih =>
    by_cases hx : x = ∅
    · subst hx
      rw [List.filter_cons_of_neg (by simp [ne0]), List.pairwise_cons]
      simp only [Finset.disjoint_empty_left, implies_true, true_and]
      exact ih
    · rw [List.filter_cons_of_pos (by simp [ne0, hx]), List.pairwise_cons, List.pairwise_cons]
      refine and_congr ?_ ih
      constructor
      · intro h y hy
        by_cases hy0 : y = ∅
        · subst hy0; simp
        · exact h y (List.mem_filter.mpr ⟨hy, by simp [ne0, hy0]⟩)
      · intro h y hy; exact h y (List.mem_filter.mp hy).1

/-- `SatL` only sees the non-empty parts. -/
theorem satL_filter {s : Row} (L : List Row) : SatL s (L.filter ne0) ↔ SatL s L := by
  unfold SatL
  rw [foldr_union_filter, pairwise_disjoint_filter]

/-- **The congruence principle for `SatL`.**  Satisfaction depends only on the
MULTISET OF NON-EMPTY PARTS: empty parts are invisible and order is irrelevant. -/
theorem satL_congr {s : Row} {L L' : List Row} (h : (L.filter ne0).Perm (L'.filter ne0)) :
    SatL s L ↔ SatL s L' := by
  rw [← satL_filter L, ← satL_filter L', satL_perm h]

/-- Merging two adjacent parts: exactly the disjointness of the two is lost. -/
theorem satL_merge {s x y : Row} {L : List Row} :
    SatL s (x :: y :: L) ↔ SatL s ((x ∪ y) :: L) ∧ Disjoint x y := by
  constructor
  · rintro ⟨heq, hp⟩
    rw [List.pairwise_cons, List.pairwise_cons] at hp
    obtain ⟨hx, hy, hL⟩ := hp
    refine ⟨⟨?_, ?_⟩, hx y (by simp)⟩
    · simpa [Finset.union_assoc] using heq
    · rw [List.pairwise_cons]
      exact ⟨fun z hz => Finset.disjoint_union_left.mpr ⟨hx z (by simp [hz]), hy z hz⟩, hL⟩
  · rintro ⟨⟨heq, hp⟩, hd⟩
    rw [List.pairwise_cons] at hp
    obtain ⟨hxy, hL⟩ := hp
    refine ⟨by simpa [Finset.union_assoc] using heq, ?_⟩
    rw [List.pairwise_cons, List.pairwise_cons]
    refine ⟨?_, fun z hz => (Finset.disjoint_union_left.mp (hxy z hz)).2, hL⟩
    intro z hz
    rcases List.mem_cons.mp hz with rfl | hz'
    · exact hd
    · exact (Finset.disjoint_union_left.mp (hxy z hz')).1

/-- A part equal to the whole forces every other part to be empty. -/
theorem satL_cons_self {s : Row} {L : List Row} :
    SatL s (s :: L) ↔ ∀ t ∈ L, t = ∅ := by
  constructor
  · rintro ⟨heq, hp⟩
    rw [List.pairwise_cons] at hp
    intro t ht
    have hsub : t ⊆ s := by
      intro a ha
      rw [heq, List.foldr_cons, Finset.mem_union]
      exact Or.inr ((mem_foldr_union L a).mpr ⟨t, ht, ha⟩)
    have hdj := hp.1 t ht
    rw [Finset.eq_empty_iff_forall_notMem]
    intro a ha
    exact (Finset.disjoint_left.mp hdj) (hsub ha) ha
  · intro h
    have hfold : L.foldr (· ∪ ·) ∅ = ∅ := by
      rw [Finset.eq_empty_iff_forall_notMem]
      intro a ha
      obtain ⟨t, ht, hat⟩ := (mem_foldr_union L a).mp ha
      rw [h t ht] at hat
      simp at hat
    refine ⟨by rw [List.foldr_cons, hfold, Finset.union_empty], ?_⟩
    rw [List.pairwise_cons]
    refine ⟨fun t ht => by rw [h t ht]; simp, ?_⟩
    exact pairwise_of_forall_mem (fun a ha b _ => by rw [h a ha]; simp)


/-! ## 2. Constraint-level rewriting lemmas

Each lemma below is exactly the semantic content of one non-generative rule. -/

/-- **Master elimination lemma.**  If a variable `b` of the right-hand side is known to
denote the concrete row `k`, it may be absorbed into the concrete part -- and the ONLY
thing that is lost is the disjointness `Disjoint c.conc k`.  That side condition is the
guard the rule must carry; without it the rewrite is unsound (see `concInst_unsound`). -/
theorem sat_absorb {rho : Assign} {c : Constraint} {b : Var} {k : Row}
    (hb : b ∈ c.vars) (hk : rho b = k) :
    Sat rho c ↔ (Sat rho ⟨c.lhs, c.vars.erase b, c.conc ∪ k⟩ ∧ Disjoint c.conc k) := by
  have hmv : (c.vars.map rho).Perm (k :: (c.vars.erase b).map rho) := by
    rw [← hk]
    exact (List.perm_cons_erase hb).map rho
  have hperm : (parts rho c).Perm (c.conc :: k :: (c.vars.erase b).map rho) :=
    List.Perm.cons _ hmv
  rw [sat_iff_satL, satL_perm hperm, satL_merge]
  rfl

/-- **Empty propagation.**  A variable known to be empty may simply be deleted. -/
theorem sat_erase_empty {rho : Assign} {c : Constraint} {b : Var} (hb : b ∈ c.vars)
    (hk : rho b = ∅) : Sat rho c ↔ Sat rho ⟨c.lhs, c.vars.erase b, c.conc⟩ := by
  rw [sat_absorb hb hk]
  simp

/-- **Self-de-duplication.**  A variable occurring at least twice on the right is forced
empty; deleting one occurrence and recording `b = ∅` is an exact rewrite. -/
theorem sat_dedup_var {rho : Assign} {c : Constraint} {b : Var} (hb : 2 ≤ c.vars.count b) :
    Sat rho c ↔ (Sat rho ⟨c.lhs, c.vars.erase b, c.conc⟩ ∧ rho b = ∅) := by
  have hmem : b ∈ c.vars := List.count_pos_iff.mp (by omega)
  constructor
  · intro h
    have h0 : rho b = ∅ := h.eq_empty_of_dup hb
    exact ⟨(sat_erase_empty hmem h0).mp h, h0⟩
  · rintro ⟨h, h0⟩
    exact (sat_erase_empty hmem h0).mpr h

/-- **Occurs.**  A constraint whose left-hand variable also occurs on the right is
completely determined: it says exactly that the concrete part and all the OTHER parts
are empty.  (In particular `r <- (r)` is vacuous, and `r <- (r, (|Foo|))` is
unsatisfiable.) -/
theorem sat_occurs {rho : Assign} {c : Constraint} (ha : c.lhs ∈ c.vars) :
    Sat rho c ↔ (c.conc = ∅ ∧ ∀ v ∈ c.vars.erase c.lhs, rho v = ∅) := by
  have hmv : (c.vars.map rho).Perm (rho c.lhs :: (c.vars.erase c.lhs).map rho) :=
    (List.perm_cons_erase ha).map rho
  have hperm : (parts rho c).Perm
      (rho c.lhs :: (c.conc :: (c.vars.erase c.lhs).map rho)) :=
    ((List.Perm.cons _ hmv).trans (List.Perm.swap _ _ _))
  rw [sat_iff_satL, satL_perm hperm, satL_cons_self]
  simp only [List.mem_cons, List.mem_map, forall_eq_or_imp]
  refine and_congr Iff.rfl ?_
  constructor
  · intro h v hv; exact h _ ⟨v, hv, rfl⟩
  · rintro h t ⟨v, hv, rfl⟩; exact h v hv

/-- Satisfaction is invariant under permuting the right-hand side. -/
theorem sat_congr_perm {rho : Assign} {c d : Constraint} (hl : c.lhs = d.lhs)
    (hc : c.conc = d.conc) (hv : c.vars.Perm d.vars) : Sat rho c ↔ Sat rho d := by
  rw [sat_iff_satL, sat_iff_satL, hl]
  exact satL_perm (by rw [parts, parts, hc]; exact List.Perm.cons _ (hv.map rho))

/-- **Common-partition unification.**  Two constraints with the same right-hand side (up
to permutation) force their left-hand variables to be equal. -/
theorem eq_lhs_of_common {rho : Assign} {c d : Constraint} (hc : c.conc = d.conc)
    (hv : c.vars.Perm d.vars) (h1 : Sat rho c) (h2 : Sat rho d) : rho c.lhs = rho d.lhs := by
  rw [h1.eq_union, h2.eq_union]
  refine foldr_union_perm ?_
  rw [parts, parts, hc]
  exact List.Perm.cons _ (hv.map rho)

/-- **Singleton right-hand side.**  `a <- (b)` is precisely the equation `a = b`.
This is also how an eliminated variable is recorded in the solved part. -/
@[simp] theorem sat_eqc (rho : Assign) (a b : Var) :
    Sat rho ⟨a, [b], ∅⟩ ↔ rho a = rho b := by
  rw [sat_one]
  simp


/-! ## 3. Substitution of one variable for another -/

/-- `substV a b` sends `a` to `b` and fixes everything else. -/
def substV (a b v : Var) : Var := if v = a then b else v

def substC (a b : Var) (c : Constraint) : Constraint :=
  ⟨substV a b c.lhs, c.vars.map (substV a b), c.conc⟩

def substG (a b : Var) (G : List Constraint) : List Constraint := G.map (substC a b)

theorem substV_apply {rho : Assign} {a b : Var} (h : rho a = rho b) (v : Var) :
    rho (substV a b v) = rho v := by
  unfold substV
  split
  · next hv => rw [hv, h]
  · rfl

theorem parts_substC {rho : Assign} {a b : Var} (h : rho a = rho b) (c : Constraint) :
    parts rho (substC a b c) = parts rho c := by
  simp only [parts, substC, List.map_map]
  congr 1
  exact List.map_congr_left (fun v _ => substV_apply h v)

/-- Substituting equals for equals does not change satisfaction. -/
theorem sat_substC {rho : Assign} {a b : Var} (h : rho a = rho b) (c : Constraint) :
    Sat rho (substC a b c) ↔ Sat rho c := by
  unfold Sat
  rw [parts_substC h]
  simp only [substC, substV_apply h]

/-! ## 4. States, and `Models` plumbing -/

/-- A canonicaliser state: a list of already-solved variable identifications `(a, b)`
meaning "`a` was eliminated in favour of `b`", plus the working constraint list. -/
structure State where
  /-- Eliminated variables, each paired with its representative. -/
  solved : List (Var × Var)
  /-- The working constraint set. -/
  cs : List Constraint

/-- A solved pair, read back as the partition constraint `a <- (b)` -- i.e. `a = b`. -/
def eqConstraint (p : Var × Var) : Constraint := ⟨p.1, [p.2], ∅⟩

/-- The constraint system a state denotes: the solved equations together with the
working set.  Nothing is thrown away, so meaning can be preserved ON THE NOSE. -/
def State.toSystem (s : State) : List Constraint := s.solved.map eqConstraint ++ s.cs

theorem models_perm {rho : Assign} {G G' : List Constraint} (h : G.Perm G') :
    Models rho G ↔ Models rho G' :=
  ⟨fun hm c hc => hm c (h.mem_iff.mpr hc), fun hm c hc => hm c (h.mem_iff.mp hc)⟩


/-- Peel one (occurrence of a) constraint off a system. -/
theorem models_erase {rho : Assign} {G : List Constraint} {c : Constraint} (hc : c ∈ G) :
    Models rho G ↔ (Sat rho c ∧ Models rho (G.erase c)) := by
  rw [models_perm (List.perm_cons_erase hc), models_cons]

theorem models_eqs {rho : Assign} {vs : List Var} :
    Models rho (vs.map (fun v => (⟨v, [], ∅⟩ : Constraint))) ↔ ∀ v ∈ vs, rho v = ∅ := by
  constructor
  · intro h v hv
    exact (sat_zero rho v ∅).mp (h _ (List.mem_map_of_mem hv))
  · intro h c hc
    obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hc
    exact (sat_zero rho v ∅).mpr (h v hv)

theorem models_substG {rho : Assign} {a b : Var} (h : rho a = rho b) (G : List Constraint) :
    Models rho (substG a b G) ↔ Models rho G := by
  constructor
  · intro hm c hc
    exact (sat_substC h c).mp (hm _ (List.mem_map_of_mem hc))
  · intro hm c hc
    obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hc
    exact (sat_substC h d).mpr (hm d hd)

/-! ## 5. The measure -/

/-- The set of variables occurring in a list of variables. -/
def varSet : List Var → Finset Var
  | [] => ∅
  | v :: l => insert v (varSet l)

@[simp] theorem mem_varSet {v : Var} : ∀ {l : List Var}, v ∈ varSet l ↔ v ∈ l := by
  intro l
  induction l with
  | nil => simp [varSet]
  | cons w l ih => simp [varSet, ih]

/-- All variables of one constraint. -/
def cvars (c : Constraint) : Finset Var := insert c.lhs (varSet c.vars)

@[simp] theorem mem_cvars {v : Var} {c : Constraint} :
    v ∈ cvars c ↔ v = c.lhs ∨ v ∈ c.vars := by simp [cvars]

/-- All variables of a constraint system. -/
def varsOf (G : List Constraint) : Finset Var := (G.map cvars).foldr (· ∪ ·) ∅

theorem mem_varsOf {v : Var} {G : List Constraint} :
    v ∈ varsOf G ↔ ∃ c ∈ G, v ∈ cvars c := by
  rw [varsOf, mem_foldr_union]
  simp

theorem varsOf_subset {G H : List Constraint} (h : ∀ c ∈ G, cvars c ⊆ varsOf H) :
    varsOf G ⊆ varsOf H := by
  intro v hv
  obtain ⟨c, hc, hvc⟩ := mem_varsOf.mp hv
  exact h c hc hvc

theorem cvars_subset_varsOf {G : List Constraint} {c : Constraint} (hc : c ∈ G) :
    cvars c ⊆ varsOf G := fun _ hv => mem_varsOf.mpr ⟨c, hc, hv⟩

/-- Total size of all right-hand sides. -/
def rhsSize : List Constraint → Nat
  | [] => 0
  | c :: G => c.vars.length + rhsSize G

@[simp] theorem rhsSize_append (G H : List Constraint) :
    rhsSize (G ++ H) = rhsSize G + rhsSize H := by
  induction G with
  | nil => simp [rhsSize]
  | cons c G ih => simp [rhsSize, ih]; omega

theorem rhsSize_perm {G H : List Constraint} (h : G.Perm H) : rhsSize G = rhsSize H := by
  induction h with
  | nil => rfl
  | cons x _ ih => simp [rhsSize, ih]
  | swap x y l => simp [rhsSize]; omega
  | trans _ _ ih1 ih2 => rw [ih1, ih2]

theorem rhsSize_erase {G : List Constraint} {c : Constraint} (hc : c ∈ G) :
    rhsSize (G.erase c) + c.vars.length = rhsSize G := by
  rw [rhsSize_perm (List.perm_cons_erase hc)]
  simp [rhsSize]
  omega

theorem rhsSize_substG (a b : Var) (G : List Constraint) :
    rhsSize (substG a b G) = rhsSize G := by
  induction G with
  | nil => rfl
  | cons c G ih => simp [substG, rhsSize, substC] at *; omega

theorem length_erase_le {G : List Constraint} {c : Constraint} :
    (G.erase c).length ≤ G.length := List.erase_sublist.length_le

theorem varsOf_erase {G : List Constraint} {c : Constraint} :
    varsOf (G.erase c) ⊆ varsOf G :=
  varsOf_subset (fun _ hd => cvars_subset_varsOf (List.mem_of_mem_erase hd))

theorem mem_cvars_substC {v a b : Var} {c : Constraint} (hv : v ∈ cvars (substC a b c)) :
    ∃ w ∈ cvars c, v = substV a b w := by
  rw [mem_cvars] at hv
  simp only [substC, List.mem_map] at hv
  rcases hv with rfl | ⟨w, hw, rfl⟩
  · exact ⟨c.lhs, by simp, rfl⟩
  · exact ⟨w, by simp [hw], rfl⟩

theorem varsOf_substG_subset {a b : Var} (hne : a ≠ b) {G H : List Constraint}
    (hsub : varsOf G ⊆ varsOf H) (hb : b ∈ varsOf H) :
    varsOf (substG a b G) ⊆ (varsOf H).erase a := by
  intro v hv
  obtain ⟨c', hc', hvc⟩ := mem_varsOf.mp hv
  simp only [substG, List.mem_map] at hc'
  obtain ⟨c, hc, rfl⟩ := hc'
  obtain ⟨w, hw, rfl⟩ := mem_cvars_substC hvc
  have hwH : w ∈ varsOf H := hsub (mem_varsOf.mpr ⟨c, hc, hw⟩)
  by_cases hwa : w = a
  · subst hwa
    rw [substV, if_pos rfl]
    exact Finset.mem_erase.mpr ⟨Ne.symm hne, hb⟩
  · rw [substV, if_neg hwa]
    exact Finset.mem_erase.mpr ⟨hwa, hwH⟩

theorem card_varsOf_substG_lt {a b : Var} (hne : a ≠ b) {G H : List Constraint}
    (hsub : varsOf G ⊆ varsOf H) (ha : a ∈ varsOf H) (hb : b ∈ varsOf H) :
    (varsOf (substG a b G)).card < (varsOf H).card := by
  have h1 := Finset.card_le_card (varsOf_substG_subset hne hsub hb)
  rw [Finset.card_erase_of_mem ha] at h1
  have h2 : 0 < (varsOf H).card := Finset.card_pos.mpr ⟨a, ha⟩
  omega

/-! ### The lexicographic order on measures, and its well-foundedness -/

/-- Lexicographic order on `(distinct variables, total RHS size, number of
constraints)`. -/
def LexLt : Nat × Nat × Nat → Nat × Nat × Nat → Prop := fun x y =>
  x.1 < y.1 ∨ (x.1 = y.1 ∧ (x.2.1 < y.2.1 ∨ (x.2.1 = y.2.1 ∧ x.2.2 < y.2.2)))

/-- The three-component comparison we actually use: each component may only go down,
and at least one must strictly go down. -/
theorem lexLt_of {n r m n' r' m' : Nat} (h1 : n' ≤ n) (h2 : r' ≤ r) (h3 : m' ≤ m)
    (h : n' < n ∨ r' < r ∨ m' < m) : LexLt (n', r', m') (n, r, m) := by
  unfold LexLt
  simp only
  omega

theorem acc_lex : ∀ n r m : Nat, Acc LexLt (n, r, m) := by
  intro n
  induction n using Nat.strong_induction_on with
  | _ n ihn =>
    intro r
    induction r using Nat.strong_induction_on with
    | _ r ihr =>
      intro m
      induction m using Nat.strong_induction_on with
      | _ m ihm =>
        refine Acc.intro _ ?_
        rintro ⟨n', r', m'⟩ h
        unfold LexLt at h
        simp only at h
        rcases h with h | ⟨he, h | ⟨he2, h⟩⟩
        · exact ihn n' h r' m'
        · subst he; exact ihr r' h m'
        · subst he; subst he2; exact ihm m' h

theorem lexLt_wf : WellFounded LexLt := ⟨fun x => acc_lex x.1 x.2.1 x.2.2⟩


/-! ## 6. The non-generative rules, as a one-step relation

Six rules, none of which mints a fresh variable.  `absorb` covers both *empty
propagation* (`k = ∅`) and *concrete instantiation* (`k ≠ ∅`). -/

inductive Step : State → State → Prop where
  /-- **Occurs / self-substitution.**  `a <- (a, R, (||))` says exactly that every other
  part is empty; the constraint is replaced by those equations. -/
  | occurs {sv : List (Var × Var)} {cs : List Constraint} {c : Constraint}
      (hc : c ∈ cs) (ha : c.lhs ∈ c.vars) (hz : c.conc = ∅) :
      Step ⟨sv, cs⟩
        ⟨sv, (c.vars.erase c.lhs).map (fun v => ⟨v, [], ∅⟩) ++ cs.erase c⟩
  /-- **Right-hand-side de-duplication.**  A variable repeated on the right is forced
  empty; drop one occurrence and record the equation `v = ∅`. -/
  | selfDedup {sv : List (Var × Var)} {cs : List Constraint} {c : Constraint} {v : Var}
      (hc : c ∈ cs) (hv : 2 ≤ c.vars.count v) :
      Step ⟨sv, cs⟩
        ⟨sv, ⟨c.lhs, c.vars.erase v, c.conc⟩ :: ⟨v, [], ∅⟩ :: cs.erase c⟩
  /-- **Empty propagation / concrete instantiation.**  A variable with a fully concrete
  definition `b <- ((|k|))` is absorbed into the concrete part of any other constraint
  that mentions it.  GUARDED by `Disjoint c.conc k`; see `absorb_guard_needed`. -/
  | absorb {sv : List (Var × Var)} {cs : List Constraint} {c : Constraint} {b : Var}
      {k : Row}
      (hc : c ∈ cs) (hd : (⟨b, [], k⟩ : Constraint) ∈ cs.erase c) (hb : b ∈ c.vars)
      (hdis : Disjoint c.conc k) :
      Step ⟨sv, cs⟩ ⟨sv, ⟨c.lhs, c.vars.erase b, c.conc ∪ k⟩ :: cs.erase c⟩
  /-- **Constraint de-duplication**, up to permutation of the right-hand side. -/
  | dedup {sv : List (Var × Var)} {cs : List Constraint} {c d : Constraint}
      (hc : c ∈ cs) (hd : d ∈ cs.erase c) (hl : c.lhs = d.lhs) (hk : c.conc = d.conc)
      (hv : c.vars.Perm d.vars) :
      Step ⟨sv, cs⟩ ⟨sv, cs.erase c⟩
  /-- **Common-partition unification.**  Two constraints with the same right-hand side
  (up to permutation) force their left-hand variables equal. -/
  | common {sv : List (Var × Var)} {cs : List Constraint} {c d : Constraint}
      (hc : c ∈ cs) (hd : d ∈ cs.erase c) (hk : c.conc = d.conc) (hv : c.vars.Perm d.vars)
      (hne : c.lhs ≠ d.lhs) :
      Step ⟨sv, cs⟩ ⟨(c.lhs, d.lhs) :: sv, substG c.lhs d.lhs cs⟩
  /-- **Singleton right-hand side.**  `a <- (b)` is the equation `a = b`: eliminate `a`. -/
  | unify {sv : List (Var × Var)} {cs : List Constraint} {a b : Var}
      (hc : (⟨a, [b], ∅⟩ : Constraint) ∈ cs) (hne : a ≠ b) :
      Step ⟨sv, cs⟩ ⟨(a, b) :: sv, substG a b (cs.erase ⟨a, [b], ∅⟩)⟩

/-! ## 7. Termination -/

/-- The measure: distinct variables, then total right-hand-side size, then number of
constraints -- compared lexicographically. -/
def Meas (cs : List Constraint) : Nat × Nat × Nat :=
  ((varsOf cs).card, rhsSize cs, cs.length)

theorem lexLt_fst {n r m n' r' m' : Nat} (h : n' < n) : LexLt (n', r', m') (n, r, m) := by
  unfold LexLt; simp only; omega

theorem lexLt_snd {n r m n' r' m' : Nat} (h1 : n' ≤ n) (h2 : r' < r) :
    LexLt (n', r', m') (n, r, m) := by unfold LexLt; simp only; omega

theorem lexLt_thd {n r m n' r' m' : Nat} (h1 : n' ≤ n) (h2 : r' ≤ r) (h3 : m' < m) :
    LexLt (n', r', m') (n, r, m) := by unfold LexLt; simp only; omega

theorem card_varsOf_le {G H : List Constraint} (h : ∀ c ∈ G, cvars c ⊆ varsOf H) :
    (varsOf G).card ≤ (varsOf H).card := Finset.card_le_card (varsOf_subset h)

theorem rhsSize_eqs (l : List Var) :
    rhsSize (l.map (fun v => (⟨v, [], ∅⟩ : Constraint))) = 0 := by
  induction l with
  | nil => rfl
  | cons v l ih => simp [rhsSize, ih]

theorem length_erase_lt {G : List Constraint} {c : Constraint} (hc : c ∈ G) :
    (G.erase c).length < G.length := by
  rw [List.length_erase_of_mem hc]
  have : 0 < G.length := List.length_pos_of_mem hc
  omega

/-- **Every rule strictly decreases the measure.**  This is the heart of the design. -/
theorem Step.decreasing {s s' : State} (h : Step s s') : LexLt (Meas s'.cs) (Meas s.cs) := by
  cases h with
  | @occurs sv cs c hc ha hz =>
    have hlen : 1 ≤ c.vars.length := List.length_pos_of_mem ha
    have hers := rhsSize_erase hc
    refine lexLt_snd (card_varsOf_le ?_) ?_
    · intro c' hc'
      rcases List.mem_append.mp hc' with h1 | h1
      · obtain ⟨v, hv, rfl⟩ := List.mem_map.mp h1
        intro w hw
        rw [mem_cvars] at hw
        simp only [List.not_mem_nil, or_false] at hw
        subst hw
        exact cvars_subset_varsOf hc (mem_cvars.mpr (Or.inr (List.mem_of_mem_erase hv)))
      · exact cvars_subset_varsOf (List.mem_of_mem_erase h1)
    · simp only [rhsSize_append, rhsSize_eqs]
      omega
  | @selfDedup sv cs c v hc hv =>
    have hmem : v ∈ c.vars := List.count_pos_iff.mp (by omega)
    have hlen : (c.vars.erase v).length < c.vars.length := by
      rw [List.length_erase_of_mem hmem]
      have := List.length_pos_of_mem hmem
      omega
    have hers := rhsSize_erase hc
    refine lexLt_snd (card_varsOf_le ?_) ?_
    · intro c' hc'
      simp only [List.mem_cons] at hc'
      rcases hc' with rfl | rfl | h1
      · intro w hw
        rw [mem_cvars] at hw
        exact cvars_subset_varsOf hc
          (mem_cvars.mpr (hw.imp id (fun h => List.mem_of_mem_erase h)))
      · intro w hw
        rw [mem_cvars] at hw
        simp only [List.not_mem_nil, or_false] at hw
        subst hw
        exact cvars_subset_varsOf hc (mem_cvars.mpr (Or.inr hmem))
      · exact cvars_subset_varsOf (List.mem_of_mem_erase h1)
    · simp only [rhsSize, List.length_nil]
      omega
  | @absorb sv cs c b k hc hd hb hdis =>
    have hlen : (c.vars.erase b).length < c.vars.length := by
      rw [List.length_erase_of_mem hb]
      have := List.length_pos_of_mem hb
      omega
    have hers := rhsSize_erase hc
    refine lexLt_snd (card_varsOf_le ?_) ?_
    · intro c' hc'
      simp only [List.mem_cons] at hc'
      rcases hc' with rfl | h1
      · intro w hw
        rw [mem_cvars] at hw
        exact cvars_subset_varsOf hc
          (mem_cvars.mpr (hw.imp id (fun h => List.mem_of_mem_erase h)))
      · exact cvars_subset_varsOf (List.mem_of_mem_erase h1)
    · simp only [rhsSize]
      omega
  | @dedup sv cs c d hc hd hl hk hv =>
    have hers := rhsSize_erase hc
    refine lexLt_thd (card_varsOf_le ?_) ?_ (length_erase_lt hc)
    · exact fun c' hc' => cvars_subset_varsOf (List.mem_of_mem_erase hc')
    · dsimp only; omega
  | @common sv cs c d hc hd hk hv hne =>
    refine lexLt_fst ?_
    exact card_varsOf_substG_lt hne (fun _ h => h)
      (cvars_subset_varsOf hc (mem_cvars.mpr (Or.inl rfl)))
      (cvars_subset_varsOf (List.mem_of_mem_erase hd) (mem_cvars.mpr (Or.inl rfl)))
  | @unify sv cs a b hc hne =>
    refine lexLt_fst ?_
    exact card_varsOf_substG_lt hne varsOf_erase
      (cvars_subset_varsOf hc (mem_cvars.mpr (Or.inl rfl)))
      (cvars_subset_varsOf hc (mem_cvars.mpr (Or.inr (by simp))))

/-- **No infinite reduction sequence.**  The canonicaliser terminates on every input. -/
theorem no_infinite_descent (f : Nat → State) (h : ∀ i, Step (f i) (f (i + 1))) : False := by
  have key : ∀ x, Acc LexLt x → ∀ g : Nat → State, (∀ i, Step (g i) (g (i + 1))) →
      Meas (g 0).cs = x → False := by
    intro x hx
    induction hx with
    | intro y _ ih =>
      intro g hg hgy
      exact ih (Meas (g 1).cs) (hgy ▸ (hg 0).decreasing) (fun i => g (i + 1))
        (fun i => hg (i + 1)) rfl
  exact key _ (lexLt_wf.apply _) f h rfl


/-! ## 8. Meaning preservation

Because eliminated variables are RETAINED in the solved part -- read back as the
partition constraint `a <- (b)`, which is exactly the equation `a = b` -- meaning is
preserved on the nose: no quantifier over substitutions is needed in the statement. -/

theorem preserves_of_cs {rho : Assign} {sv : List (Var × Var)} {cs cs' : List Constraint}
    (h : Models rho cs ↔ Models rho cs') :
    Models rho (State.toSystem ⟨sv, cs⟩) ↔ Models rho (State.toSystem ⟨sv, cs'⟩) := by
  simp only [State.toSystem, models_append, h]

theorem models_toSystem_cons {rho : Assign} {a b : Var} {sv : List (Var × Var)}
    {cs : List Constraint} :
    Models rho (State.toSystem ⟨(a, b) :: sv, cs⟩) ↔
      (rho a = rho b ∧ Models rho (State.toSystem ⟨sv, cs⟩)) := by
  simp only [State.toSystem, List.map_cons, List.cons_append, models_cons, eqConstraint,
    sat_eqc]

/-- **Soundness AND completeness of the simplifier.**  Every rule preserves the set of
models of the system EXACTLY. -/
theorem Step.preserves {s s' : State} (h : Step s s') (rho : Assign) :
    Models rho s.toSystem ↔ Models rho s'.toSystem := by
  cases h with
  | @occurs sv cs c hc ha hz =>
    refine preserves_of_cs ?_
    rw [models_erase hc, models_append, models_eqs, sat_occurs ha, hz]
    simp
  | @selfDedup sv cs c v hc hv =>
    refine preserves_of_cs ?_
    rw [models_erase hc, sat_dedup_var hv, models_cons, models_cons, sat_zero]
    tauto
  | @absorb sv cs c b k hc hd hb hdis =>
    refine preserves_of_cs ?_
    rw [models_erase hc, models_cons]
    constructor
    · rintro ⟨h1, h2⟩
      have hk : rho b = k := (sat_zero rho b k).mp (h2 _ hd)
      exact ⟨((sat_absorb hb hk).mp h1).1, h2⟩
    · rintro ⟨h1, h2⟩
      have hk : rho b = k := (sat_zero rho b k).mp (h2 _ hd)
      exact ⟨(sat_absorb hb hk).mpr ⟨h1, hdis⟩, h2⟩
  | @dedup sv cs c d hc hd hl hk hv =>
    refine preserves_of_cs ?_
    rw [models_erase hc]
    exact ⟨fun h => h.2, fun h => ⟨(sat_congr_perm hl hk hv).mpr (h _ hd), h⟩⟩
  | @common sv cs c d hc hd hk hv hne =>
    rw [models_toSystem_cons]
    constructor
    · intro h
      have h' : Models rho (sv.map eqConstraint ++ cs) := h
      have hcs : Models rho cs := (models_append.mp h').2
      have heq : rho c.lhs = rho d.lhs :=
        eq_lhs_of_common hk hv (hcs _ hc) (hcs _ (List.mem_of_mem_erase hd))
      exact ⟨heq, (preserves_of_cs (models_substG heq cs).symm).mp h⟩
    · rintro ⟨heq, h⟩
      exact (preserves_of_cs (models_substG heq cs).symm).mpr h
  | @unify sv cs a b hc hne =>
    have hstep : rho a = rho b →
        (Models rho cs ↔ Models rho (substG a b (cs.erase (⟨a, [b], ∅⟩ : Constraint)))) := by
      intro heq
      rw [models_substG heq]
      exact (models_erase hc).trans (and_iff_right ((sat_eqc rho a b).mpr heq))
    rw [models_toSystem_cons]
    constructor
    · intro h
      have h' : Models rho (sv.map eqConstraint ++ cs) := h
      have heq : rho a = rho b := (sat_eqc rho a b).mp ((models_append.mp h').2 _ hc)
      exact ⟨heq, (preserves_of_cs (hstep heq)).mp h⟩
    · rintro ⟨heq, h⟩
      exact (preserves_of_cs (hstep heq)).mpr h

/-- Each step preserves satisfiability. -/
theorem Step.satisfiable_iff {s s' : State} (h : Step s s') :
    (∃ rho, Models rho s.toSystem) ↔ (∃ rho, Models rho s'.toSystem) :=
  exists_congr fun rho => h.preserves rho

/-- Each step preserves entailment in both directions: the input and the output are
LOGICALLY EQUIVALENT constraint systems. -/
theorem Step.entails_iff {s s' : State} (h : Step s s') (c : Constraint) :
    Entails s.toSystem c ↔ Entails s'.toSystem c :=
  ⟨fun he rho hm => he rho ((h.preserves rho).mpr hm),
   fun he rho hm => he rho ((h.preserves rho).mp hm)⟩


/-! ## 9. An executable, deterministic implementation -/

/-- First success in a list. -/
def firstSome {α β : Type} (f : α → Option β) : List α → Option β
  | [] => none
  | a :: l => match f a with
    | some b => some b
    | none => firstSome f l

theorem firstSome_eq_some {α β : Type} {f : α → Option β} :
    ∀ {l : List α} {b : β}, firstSome f l = some b → ∃ a ∈ l, f a = some b := by
  intro l
  induction l with
  | nil => intro b h; simp [firstSome] at h
  | cons a l ih =>
    intro b h
    simp only [firstSome] at h
    cases hfa : f a with
    | none =>
      simp only [hfa] at h
      obtain ⟨x, hx, hfx⟩ := ih h
      exact ⟨x, by simp [hx], hfx⟩
    | some c =>
      simp only [hfa, Option.some.injEq] at h
      exact ⟨a, by simp, by rw [hfa, h]⟩

/-- Dual of `firstSome_eq_some`: if the search fails, it failed at every entry. -/
theorem firstSome_eq_none {α β : Type} {f : α → Option β} :
    ∀ {l : List α}, firstSome f l = none → ∀ a ∈ l, f a = none := by
  intro l
  induction l with
  | nil => intro _ a ha; cases ha
  | cons a l ih =>
    intro h b hb
    simp only [firstSome] at h
    cases hfa : f a with
    | some c => simp only [hfa] at h; exact absurd h (by simp)
    | none =>
      simp only [hfa] at h
      rcases List.mem_cons.mp hb with rfl | hb'
      · exact hfa
      · exact ih h b hb'

def tryOccurs (sv : List (Var × Var)) (cs : List Constraint) (c : Constraint) : Option State :=
  if c.lhs ∈ c.vars ∧ c.conc = ∅ then
    some ⟨sv, (c.vars.erase c.lhs).map (fun v => ⟨v, [], ∅⟩) ++ cs.erase c⟩
  else none

def trySelfDedup (sv : List (Var × Var)) (cs : List Constraint) (c : Constraint) :
    Option State :=
  firstSome (fun v =>
    if 2 ≤ c.vars.count v then
      some (⟨sv, ⟨c.lhs, c.vars.erase v, c.conc⟩ :: ⟨v, [], ∅⟩ :: cs.erase c⟩ : State)
    else none) c.vars

def tryAbsorb (sv : List (Var × Var)) (cs : List Constraint) (c : Constraint) : Option State :=
  firstSome (fun d =>
    if d.vars = [] ∧ d.lhs ∈ c.vars ∧ Disjoint c.conc d.conc then
      some (⟨sv, ⟨c.lhs, c.vars.erase d.lhs, c.conc ∪ d.conc⟩ :: cs.erase c⟩ : State)
    else none) (cs.erase c)

def tryUnify (sv : List (Var × Var)) (cs : List Constraint) (c : Constraint) : Option State :=
  firstSome (fun b =>
    if c = (⟨c.lhs, [b], ∅⟩ : Constraint) ∧ c.lhs ≠ b then
      some (⟨(c.lhs, b) :: sv, substG c.lhs b (cs.erase ⟨c.lhs, [b], ∅⟩)⟩ : State)
    else none) c.vars

def tryDedup (sv : List (Var × Var)) (cs : List Constraint) (c : Constraint) : Option State :=
  firstSome (fun d =>
    if c.lhs = d.lhs ∧ c.conc = d.conc ∧ c.vars.Perm d.vars then
      some (⟨sv, cs.erase c⟩ : State)
    else none) (cs.erase c)

def tryCommon (sv : List (Var × Var)) (cs : List Constraint) (c : Constraint) : Option State :=
  firstSome (fun d =>
    if c.conc = d.conc ∧ c.vars.Perm d.vars ∧ c.lhs ≠ d.lhs then
      some (⟨(c.lhs, d.lhs) :: sv, substG c.lhs d.lhs cs⟩ : State)
    else none) (cs.erase c)

/-- **The canonicaliser's one step**: deterministic, and total as a partial function. -/
def stepFn (s : State) : Option State :=
  firstSome (fun f => firstSome (f s.solved s.cs) s.cs)
    [tryOccurs, trySelfDedup, tryAbsorb, tryUnify, tryDedup, tryCommon]

theorem tryOccurs_sound {sv cs c s'} (hc : c ∈ cs) (h : tryOccurs sv cs c = some s') :
    Step ⟨sv, cs⟩ s' := by
  rw [tryOccurs] at h
  split at h
  · next hcond =>
      simp only [Option.some.injEq] at h
      subst h
      exact Step.occurs hc hcond.1 hcond.2
  · exact absurd h (by simp)

theorem trySelfDedup_sound {sv cs c s'} (hc : c ∈ cs) (h : trySelfDedup sv cs c = some s') :
    Step ⟨sv, cs⟩ s' := by
  obtain ⟨v, _, hv⟩ := firstSome_eq_some h
  split at hv
  · next hcond =>
      simp only [Option.some.injEq] at hv
      subst hv
      exact Step.selfDedup hc hcond
  · exact absurd hv (by simp)

theorem tryAbsorb_sound {sv cs c s'} (hc : c ∈ cs) (h : tryAbsorb sv cs c = some s') :
    Step ⟨sv, cs⟩ s' := by
  obtain ⟨d, hd, hv⟩ := firstSome_eq_some h
  split at hv
  · next hcond =>
      simp only [Option.some.injEq] at hv
      subst hv
      obtain ⟨h1, h2, h3⟩ := hcond
      have hd' : (⟨d.lhs, [], d.conc⟩ : Constraint) ∈ cs.erase c := by rw [← h1]; exact hd
      exact Step.absorb hc hd' h2 h3
  · exact absurd hv (by simp)

theorem tryUnify_sound {sv cs c s'} (hc : c ∈ cs) (h : tryUnify sv cs c = some s') :
    Step ⟨sv, cs⟩ s' := by
  obtain ⟨b, _, hv⟩ := firstSome_eq_some h
  split at hv
  · next hcond =>
      simp only [Option.some.injEq] at hv
      subst hv
      obtain ⟨h1, h2⟩ := hcond
      exact Step.unify (by rw [← h1]; exact hc) h2
  · exact absurd hv (by simp)

theorem tryDedup_sound {sv cs c s'} (hc : c ∈ cs) (h : tryDedup sv cs c = some s') :
    Step ⟨sv, cs⟩ s' := by
  obtain ⟨d, hd, hv⟩ := firstSome_eq_some h
  split at hv
  · next hcond =>
      simp only [Option.some.injEq] at hv
      subst hv
      exact Step.dedup hc hd hcond.1 hcond.2.1 hcond.2.2
  · exact absurd hv (by simp)

theorem tryCommon_sound {sv cs c s'} (hc : c ∈ cs) (h : tryCommon sv cs c = some s') :
    Step ⟨sv, cs⟩ s' := by
  obtain ⟨d, hd, hv⟩ := firstSome_eq_some h
  split at hv
  · next hcond =>
      simp only [Option.some.injEq] at hv
      subst hv
      exact Step.common hc hd hcond.1 hcond.2.1 hcond.2.2
  · exact absurd hv (by simp)

/-- The implementation only ever performs genuine rule steps. -/
theorem stepFn_sound {s s' : State} (h : stepFn s = some s') : Step s s' := by
  obtain ⟨f, hf, hfs⟩ := firstSome_eq_some h
  obtain ⟨c, hc, hcs⟩ := firstSome_eq_some hfs
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hf
  rcases hf with rfl | rfl | rfl | rfl | rfl | rfl
  · exact tryOccurs_sound hc hcs
  · exact trySelfDedup_sound hc hcs
  · exact tryAbsorb_sound hc hcs
  · exact tryUnify_sound hc hcs
  · exact tryDedup_sound hc hcs
  · exact tryCommon_sound hc hcs

/-- The fuelled driver. -/
def canonN : Nat → State → State
  | 0, s => s
  | n + 1, s => match stepFn s with
    | none => s
    | some s' => canonN n s'

theorem canonN_preserves (n : Nat) (s : State) (rho : Assign) :
    Models rho (canonN n s).toSystem ↔ Models rho s.toSystem := by
  induction n generalizing s with
  | zero => exact Iff.rfl
  | succ n ih =>
    rw [canonN]
    cases hs : stepFn s with
    | none => exact Iff.rfl
    | some s' =>
      change Models rho (canonN n s').toSystem ↔ Models rho s.toSystem
      rw [ih s']
      exact ((stepFn_sound hs).preserves rho).symm

/-- **Enough fuel always exists**: the driver reaches a normal form. -/
theorem exists_fuel (s : State) : ∃ n, stepFn (canonN n s) = none := by
  have key : ∀ x, Acc LexLt x → ∀ t : State, Meas t.cs = x →
      ∃ n, stepFn (canonN n t) = none := by
    intro x hx
    induction hx with
    | intro y _ ih =>
      intro t hty
      cases hs : stepFn t with
      | none => exact ⟨0, hs⟩
      | some t' =>
        obtain ⟨n, hn⟩ := ih (Meas t'.cs) (hty ▸ (stepFn_sound hs).decreasing) t' rfl
        refine ⟨n + 1, ?_⟩
        rw [canonN]
        simp only [hs]
        exact hn
  exact key _ (lexLt_wf.apply _) s rfl

/-- **The canonicaliser.**  Every constraint system reduces, in finitely many steps, to a
normal form with EXACTLY the same models. -/
theorem canonicalise (s : State) :
    ∃ t : State, stepFn t = none ∧ ∀ rho, Models rho t.toSystem ↔ Models rho s.toSystem := by
  obtain ⟨n, hn⟩ := exists_fuel s
  exact ⟨canonN n s, hn, fun rho => canonN_preserves n s rho⟩


/-- Multi-step reduction. -/
inductive Steps : State → State → Prop where
  | refl (s : State) : Steps s s
  | tail {s t u : State} : Steps s t → Step t u → Steps s u

/-- A state from which no rule applies. -/
def NormalForm (s : State) : Prop := ∀ t, ¬ Step s t

theorem Steps.eq_of_normalForm {s t : State} (hn : NormalForm s) (h : Steps s t) : t = s := by
  induction h with
  | refl => rfl
  | tail _ hst ih => exact absurd (ih ▸ hst) (hn _)

/-- Sound and complete as a SIMPLIFIER: entailment is unchanged by canonicalisation. -/
theorem canonN_entails (n : Nat) (s : State) (c : Constraint) :
    Entails (canonN n s).toSystem c ↔ Entails s.toSystem c :=
  ⟨fun h rho hm => h rho ((canonN_preserves n s rho).mpr hm),
   fun h rho hm => h rho ((canonN_preserves n s rho).mp hm)⟩

/-! ### The implementation's fixpoint really is a normal form

`stepFn_sound` says the driver only performs genuine steps.  The converse -- that when
the driver stops, no rule of `Step` applies at all -- is what makes `canonicalise` a
NORMAL FORM theorem rather than merely "the implementation ran out of moves".  It is
proved by replaying each of the six constructors against the corresponding `try...`
search. -/

/-- Every `try...` combinator that `stepFn` consults reports `none` at every
constraint of a state on which `stepFn` reports `none`. -/
theorem stepFn_eq_none {s : State} (h : stepFn s = none) :
    ∀ f ∈ [tryOccurs, trySelfDedup, tryAbsorb, tryUnify, tryDedup, tryCommon],
      ∀ c ∈ s.cs, f s.solved s.cs c = none := by
  intro f hf c hc
  rw [stepFn] at h
  exact firstSome_eq_none (firstSome_eq_none h f hf) c hc

/-- **The implementation is EXHAUSTIVE.**  If `stepFn` reports no step, then NO rule
of the calculus applies: the state is a `NormalForm`.  Together with `stepFn_sound`
this pins `stepFn` to `Step` exactly. -/
theorem stepFn_complete {s : State} (h : stepFn s = none) : NormalForm s := by
  have key := stepFn_eq_none h
  intro t hstep
  cases hstep with
  | @occurs sv cs c hc hlhs hconc =>
    have hn := key tryOccurs (by simp) c hc
    rw [tryOccurs] at hn
    split at hn
    · exact absurd hn (by simp)
    · next hnot => exact hnot ⟨hlhs, hconc⟩
  | @selfDedup sv cs c v hc hcount =>
    have hvmem : v ∈ c.vars := by
      by_contra hnm
      rw [List.count_eq_zero.mpr hnm] at hcount
      omega
    have hn := key trySelfDedup (by simp) c hc
    rw [trySelfDedup] at hn
    have hv := firstSome_eq_none hn v hvmem
    split at hv
    · exact absurd hv (by simp)
    · next hnot => exact hnot hcount
  | @absorb sv cs c b k hc hd hb hdisj =>
    have hn := key tryAbsorb (by simp) c hc
    rw [tryAbsorb] at hn
    have hv := firstSome_eq_none hn ⟨b, [], k⟩ hd
    split at hv
    · exact absurd hv (by simp)
    · next hnot => exact hnot ⟨rfl, hb, hdisj⟩
  | @dedup sv cs c d hc hd hlhs hconc hperm =>
    have hn := key tryDedup (by simp) c hc
    rw [tryDedup] at hn
    have hv := firstSome_eq_none hn d hd
    split at hv
    · exact absurd hv (by simp)
    · next hnot => exact hnot ⟨hlhs, hconc, hperm⟩
  | @common sv cs c d hc hd hconc hperm hne =>
    have hn := key tryCommon (by simp) c hc
    rw [tryCommon] at hn
    have hv := firstSome_eq_none hn d hd
    split at hv
    · exact absurd hv (by simp)
    · next hnot => exact hnot ⟨hconc, hperm, hne⟩
  | @unify sv cs a b hc hne =>
    have hn := key tryUnify (by simp) ⟨a, [b], ∅⟩ hc
    rw [tryUnify] at hn
    have hv := firstSome_eq_none hn b (by simp)
    split at hv
    · exact absurd hv (by simp)
    · next hnot => exact hnot ⟨rfl, hne⟩

/-- **The canonicaliser, sharpened.**  Every constraint system reduces, in finitely
many steps, to a state on which NO rule applies and which has exactly the same models
as the input.  This is `canonicalise` with `stepFn t = none` upgraded to the
rule-level `NormalForm t`. -/
theorem canonicalise_normalForm (s : State) :
    ∃ t : State, NormalForm t ∧ ∀ rho, Models rho t.toSystem ↔ Models rho s.toSystem := by
  obtain ⟨n, hn⟩ := exists_fuel s
  exact ⟨canonN n s, stepFn_complete hn, fun rho => canonN_preserves n s rho⟩

/-! ## 10. Two guards that the informal rule statements omit

Both are places where the "obvious" rule is UNSOUND (it turns an unsatisfiable system
into a satisfiable one) unless a side condition is imposed. -/

/-- A constraint whose left-hand variable occurs on its right with a NON-EMPTY concrete
part is unsatisfiable.  So the `occurs` rule must carry `c.conc = ∅`; the remaining case
is a detected contradiction, not a rewrite. -/
theorem unsat_of_occurs {c : Constraint} (ha : c.lhs ∈ c.vars) (hz : c.conc ≠ ∅)
    (rho : Assign) : ¬ Sat rho c := fun h => hz ((sat_occurs ha).mp h).1

/-- **The `absorb` guard is necessary.**  `a <- (b, (|{5}|))` together with `b = {5}` is
UNSATISFIABLE, but absorbing `b` without checking `Disjoint c.conc k` yields
`a = {5}`, which is satisfiable.  So concrete instantiation without the disjointness
check silently loses unsatisfiability. -/
theorem absorb_guard_needed :
    (¬ ∃ rho, Models rho [(⟨0, [1], {5}⟩ : Constraint), ⟨1, [], {5}⟩]) ∧
      (∃ rho, Models rho [(⟨0, [], {5} ∪ {5}⟩ : Constraint), ⟨1, [], {5}⟩]) := by
  constructor
  · rintro ⟨rho, hm⟩
    have h1 : Sat rho ⟨0, [1], {5}⟩ := hm _ (by simp)
    have h2 : rho 1 = {5} := (sat_zero rho 1 _).mp (hm _ (by simp))
    have hd : Disjoint ({5} : Row) (rho 1) := h1.disjoint_conc (by simp)
    rw [h2] at hd
    have : (5 : Label) ∈ ({5} : Row) := by simp
    exact (Finset.disjoint_left.mp hd this) this
  · refine ⟨fun _ => {5}, ?_⟩
    intro c hc
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl <;> simp

/-! ## 11. The rule set is NOT confluent

`occurs` and `absorb` form a critical pair that does not join.  Take

    G  =  [ a <- (a, b) ,  b <- ((|{7}|)) ]

* `occurs` fires on the first constraint (its concrete part is empty), replacing it by
  `b <- ((||))`, i.e. `b = ∅`;
* `absorb` fires instead on `b`, rewriting the first constraint to `a <- (a, (|{7}|))`
  -- and that constraint now has a NON-EMPTY concrete part, so `occurs` is permanently
  blocked on it.

Both results are normal forms, and they are different.  Both are (correctly)
unsatisfiable, so meaning is preserved -- but the NORMAL FORM IS NOT UNIQUE, and no
orientation convention repairs this: the two rules genuinely destroy each other's
applicability. -/

namespace CriticalPair

/-- `a <- (a, b)`. -/
def cA : Constraint := ⟨0, [0, 1], ∅⟩
/-- `b <- ((|{7}|))`. -/
def cB : Constraint := ⟨1, [], {7}⟩
/-- The ambiguous system. -/
def S : State := ⟨[], [cA, cB]⟩
/-- The `occurs` result. -/
def S1 : State := ⟨[], [⟨1, [], ∅⟩, cB]⟩
/-- The `absorb` result. -/
def S2 : State := ⟨[], [⟨0, [0], {7}⟩, cB]⟩

theorem step_S1 : Step S S1 :=
  Step.occurs (c := cA) (by simp) (by decide) rfl

theorem step_S2 : Step S S2 := by
  have key : Step S ⟨[], [⟨0, [0], (∅ : Finset Label) ∪ {7}⟩, cB]⟩ :=
    Step.absorb (c := cA) (b := 1) (k := {7}) (by simp) (by simp [cA, cB])
      (by simp [cA]) (by simp [cA])
  have h : (∅ : Finset Label) ∪ ({7} : Finset Label) = {7} := by simp
  rwa [h] at key

theorem normal_S1 : NormalForm S1 := by
  intro t ht
  cases ht with
  | @occurs sv cs c hc ha hz =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> simp [cB] at ha
  | @selfDedup sv cs c v hc hv =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> simp [cB] at hv
  | @absorb sv cs c b k hc hd hb hdis =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> simp [cB] at hb
  | @dedup sv cs c d hc hd hl hk hv =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> (simp [cB] at hd; subst hd; simp [cB] at hk)
  | @common sv cs c d hc hd hk hv hne =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> (simp [cB] at hd; subst hd; simp [cB] at hk)
  | @unify sv cs a b hc hne => simp [cB] at hc

theorem normal_S2 : NormalForm S2 := by
  intro t ht
  cases ht with
  | @occurs sv cs c hc ha hz =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl
      · simp at hz
      · simp [cB] at ha
  | @selfDedup sv cs c v hc hv =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl
      · simp only [List.count_cons, List.count_nil] at hv
        split at hv <;> omega
      · simp [cB] at hv
  | @absorb sv cs c b k hc hd hb hdis =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl
      · simp [cB] at hd
        obtain ⟨rfl, -, -⟩ := hd
        simp at hb
      · simp [cB] at hb
  | @dedup sv cs c d hc hd hl hk hv =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> (simp [cB] at hd; subst hd; simp [cB] at hl)
  | @common sv cs c d hc hd hk hv hne =>
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> (simp [cB] at hd; subst hd; simp [cB] at hv)
  | @unify sv cs a b hc hne => simp [cB] at hc

theorem S1_ne_S2 : S1 ≠ S2 := by
  intro h
  rw [S1, S2] at h
  simp [cB] at h

/-- **Local confluence FAILS.**  `S` steps to two DISTINCT normal forms. -/
theorem not_locally_confluent :
    Step S S1 ∧ Step S S2 ∧ S1 ≠ S2 ∧ NormalForm S1 ∧ NormalForm S2 :=
  ⟨step_S1, step_S2, S1_ne_S2, normal_S1, normal_S2⟩

/-- ... hence the two results have no common reduct: normal forms are NOT unique. -/
theorem not_joinable : ¬ ∃ t, Steps S1 t ∧ Steps S2 t := by
  rintro ⟨t, h1, h2⟩
  exact S1_ne_S2 ((h1.eq_of_normalForm normal_S1).symm.trans (h2.eq_of_normalForm normal_S2))

/-- Meaning IS preserved along both branches, as the general theorem guarantees: both
results are unsatisfiable, like the input. -/
theorem both_branches_unsat :
    (¬ ∃ rho, Models rho S1.toSystem) ∧ (¬ ∃ rho, Models rho S2.toSystem) := by
  constructor
  · rintro ⟨rho, hm⟩
    have h1 : rho 1 = ∅ := (sat_zero rho 1 _).mp (hm _ (by simp [S1, State.toSystem]))
    have h2 : rho 1 = {7} := (sat_zero rho 1 _).mp (hm _ (by simp [S1, cB, State.toSystem]))
    rw [h1] at h2
    exact absurd h2.symm (by simp)
  · rintro ⟨rho, hm⟩
    have h1 : Sat rho ⟨0, [0], {7}⟩ := hm _ (by simp [S2, State.toSystem])
    exact unsat_of_occurs (by simp) (by simp) rho h1

/-- **The canonicaliser is not a decision procedure.**  `S1` is a normal form and is
unsatisfiable: no non-generative rule detects the contradiction `b = ∅ ∧ b = {7}`. -/
theorem normal_form_can_be_unsat : NormalForm S1 ∧ ¬ ∃ rho, Models rho S1.toSystem :=
  ⟨normal_S1, both_branches_unsat.1⟩

end CriticalPair

/-! ### A second, independent ambiguity: the ORIENTATION of `common`

`common` may unify the two left-hand variables in either direction, and the two results
differ.  Unlike the `occurs`/`absorb` pair this one IS repairable -- always eliminate the
larger variable -- but it shows that the rule as usually stated is not a function.  The
system below is SATISFIABLE, so this is not an artefact of contradictory input. -/

namespace Orientation

/-- `x <- (z, (|{5}|))` and `y <- (z, (|{5}|))`: forces `x = y`, and is satisfiable. -/
def T : State := ⟨[], [⟨1, [3], {5}⟩, ⟨2, [3], {5}⟩]⟩

theorem T_sat : ∃ rho, Models rho T.toSystem := by
  refine ⟨fun v => if v = 3 then {9} else {5, 9}, ?_⟩
  intro c hc
  simp only [T, State.toSystem, List.map_nil, List.nil_append, List.mem_cons,
    List.not_mem_nil, or_false] at hc
  rcases hc with rfl | rfl <;> (rw [sat_one]; constructor <;> decide)

theorem step_left : Step T ⟨[(1, 2)], substG 1 2 T.cs⟩ :=
  Step.common (c := ⟨1, [3], {5}⟩) (d := ⟨2, [3], {5}⟩) (by simp) (by simp) rfl
    (List.Perm.refl _) (by decide)

theorem step_right : Step T ⟨[(2, 1)], substG 2 1 T.cs⟩ :=
  Step.common (c := ⟨2, [3], {5}⟩) (d := ⟨1, [3], {5}⟩) (by simp) (by simp) rfl
    (List.Perm.refl _) (by decide)

theorem results_differ :
    (⟨[(1, 2)], substG 1 2 T.cs⟩ : State) ≠ ⟨[(2, 1)], substG 2 1 T.cs⟩ := by
  intro h
  simp at h

end Orientation


/-! ## 12. The two known defects of the existing Scala solver

The Scala implementation is known to emit a vacuous `r <- (r)` and to emit the same
constraint twice under a permuted right-hand side.  Both are removed by rules that this
file proves meaning-preserving and measure-decreasing. -/

/-- A vacuous `r <- (r)` is deleted outright. -/
theorem step_vacuous (sv : List (Var × Var)) (r : Var) (G : List Constraint) :
    Step ⟨sv, ⟨r, [r], ∅⟩ :: G⟩ ⟨sv, G⟩ := by
  have h := Step.occurs (sv := sv) (cs := (⟨r, [r], ∅⟩ : Constraint) :: G)
    (c := ⟨r, [r], ∅⟩) (by simp) (by simp) rfl
  simpa using h

/-- A duplicate under a PERMUTED right-hand side is recognised and deleted. -/
theorem step_perm_dup (sv : List (Var × Var)) (a v w : Var) (k : Row)
    (G : List Constraint) :
    Step ⟨sv, ⟨a, [v, w], k⟩ :: ⟨a, [w, v], k⟩ :: G⟩ ⟨sv, ⟨a, [w, v], k⟩ :: G⟩ := by
  have h := Step.dedup (sv := sv)
    (cs := (⟨a, [v, w], k⟩ : Constraint) :: ⟨a, [w, v], k⟩ :: G)
    (c := ⟨a, [v, w], k⟩) (d := ⟨a, [w, v], k⟩) (by simp) (by simp) rfl rfl
    (List.Perm.swap w v [])
  simpa using h

/-! ## 13. A worked example (checked by computation)

    r <- (r)                 -- vacuous
    x <- (y, z)              -- and the same again with the RHS permuted
    x <- (z, y)
    z <- ((|{7}|))
    p <- (q)

canonicalises to `x <- (y, (|{7}|))`, `z <- ((|{7}|))`, with `p := q` recorded in the
solved part.  The vacuous constraint, the permuted duplicate and the singleton
right-hand side have all gone, and `z`'s concrete definition has been instantiated. -/

/-- The example system of section 13. -/
def demo : State :=
  ⟨[], [⟨9, [9], ∅⟩, ⟨0, [1, 2], ∅⟩, ⟨0, [2, 1], ∅⟩, ⟨2, [], {7}⟩, ⟨5, [6], ∅⟩]⟩

example : (canonN 20 demo).cs = [⟨0, [1], {7}⟩, ⟨2, [], {7}⟩] := by rfl

example : (canonN 20 demo).solved = [(5, 6)] := by rfl

example : stepFn (canonN 20 demo) = none := by rfl

/-- ... and the normal form has exactly the models of the input. -/
example (rho : Assign) :
    Models rho (canonN 20 demo).toSystem ↔ Models rho demo.toSystem :=
  canonN_preserves 20 demo rho

end Rowpartition
