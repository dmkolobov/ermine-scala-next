/-
# Soundness of every inference rule in Ermine's row-partition solver

This file formalises, and proves or refutes, each rule in the header comment of
`ermine-scala/core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`.

## How the informal rules are read

The informal rules write a right-hand side as a mixture of several concrete field sets
and several variables, e.g. `a <- C* D* x`.  The `Constraint` structure of
`Rowpartition.Basic` carries only ONE concrete part, so a right-hand side with several
concrete blocks is represented by their UNION.  Section 1 proves this is faithful:
`rsat_iff_flatten` says a multi-block right-hand side is satisfied exactly when the
union-flattened constraint is satisfied AND the concrete blocks are pairwise disjoint.
The second conjunct is exactly the content of error condition 10 (duplicated field),
which is therefore stated on the multi-block form; every other rule is stated on the
flattened form, with the disjointness of the named blocks (convention 8 of the header:
"named individuals or sequences are expected to be coherent, distinct and disjoint over
an entire inference rule") appearing as an explicit hypothesis wherever it is used.

## Fresh variables

Rules 4, 6 and 9 mint a fresh variable, so their conclusion mentions a variable that the
premises do not.  `Entails G concl` is then the WRONG statement.  The right one is
`ConservativeExt G u G'` (section 2): every model of `G` extends -- changing only `u` --
to a model of `G'`, and conversely every model of `G'` is already a model of `G`.  The
first half is what makes the solver's inference sound; the second half says the new
constraints add no information.  Freshness of `u` is used ONLY in the first half.

## Headline results

* Rules 1, 2, 3, 4, 5, 7, 8, 9, 10, 11 are sound, in general list-indexed form.
* Rule 6 (Resolution) as literally written in the header comment is UNSOUND: it derives
  `x <- C* z` where it should derive `x <- E* z` (and `y <- C* z`, not `y <- E* z`).
  See `Rule6Header`: for a satisfiable pair of premises with `C` nonempty, the premises
  together with the header's conclusion have no model at all.  The English prose above
  the rule ("each of the lone right variables contain the fields missing from THEIR
  rule") describes the correct, swapped, version, and the Scala implementation
  (`Constraints.scala`, `def resolution`) implements the correct version -- indeed it
  implements the sharper `E \ C` / `C \ E` form proved here as `rule6`, which needs no
  disjointness hypothesis between `C` and `E` at all.
-/
import Rowpartition.Basic
import Mathlib.Data.Finset.SDiff

namespace Rowpartition

/-! ## 0. Toolkit

Small lemmas for building and taking apart `Sat` at the shapes the rules use:
right-hand sides of the form `[x]`, `w :: ys`, and `L ++ M`. -/

section Toolkit

/-- Disjointness is antitone in its right argument. -/
theorem disjoint_of_subset_right {s t u : Row} (hd : Disjoint s u) (hsub : t ⊆ u) :
    Disjoint s t := by
  rw [Finset.disjoint_left] at hd ⊢
  exact fun l hl hlt => hd hl (hsub hlt)

/-- Disjointness is antitone in its left argument. -/
theorem disjoint_of_subset_left {s t u : Row} (hd : Disjoint u t) (hsub : s ⊆ u) :
    Disjoint s t := by
  rw [Finset.disjoint_left] at hd ⊢
  exact fun l hl hlt => hd (hsub hl) hlt

/-- A row disjoint from itself is empty. -/
theorem eq_empty_of_disjoint_self {s : Row} (h : Disjoint s s) : s = ∅ := by
  simpa using disjoint_self.mp h

/-- `foldr`-union distributes over list append. -/
theorem foldr_union_append (L M : List Row) :
    (L ++ M).foldr (· ∪ ·) ∅ = L.foldr (· ∪ ·) ∅ ∪ M.foldr (· ∪ ·) ∅ := by
  induction L with
  | nil => simp
  | cons s L ih => simp [ih, Finset.union_assoc]

/-- Bounded existential over an append. -/
theorem exists_mem_append {L M : List Var} (P : Var → Prop) :
    (∃ v ∈ L ++ M, P v) ↔ (∃ v ∈ L, P v) ∨ (∃ v ∈ M, P v) := by
  simp only [List.mem_append]
  constructor
  · rintro ⟨v, hv | hv, hp⟩
    · exact Or.inl ⟨v, hv, hp⟩
    · exact Or.inr ⟨v, hv, hp⟩
  · rintro (⟨v, hv, hp⟩ | ⟨v, hv, hp⟩)
    · exact ⟨v, Or.inl hv, hp⟩
    · exact ⟨v, Or.inr hv, hp⟩

/-- Bounded existential over a cons. -/
theorem exists_mem_cons {w : Var} {ys : List Var} (P : Var → Prop) :
    (∃ v ∈ w :: ys, P v) ↔ (P w ∨ ∃ v ∈ ys, P v) := by
  simp only [List.mem_cons]
  constructor
  · rintro ⟨v, rfl | hv, hp⟩
    · exact Or.inl hp
    · exact Or.inr ⟨v, hv, hp⟩
  · rintro (hp | ⟨v, hv, hp⟩)
    · exact ⟨w, Or.inl rfl, hp⟩
    · exact ⟨v, Or.inr hv, hp⟩

/-- Bounded existential over a singleton. -/
theorem exists_mem_singleton {w : Var} (P : Var → Prop) : (∃ v ∈ [w], P v) ↔ P w := by simp

variable {rho : Assign} {c : Constraint}

/-- Membership in the union of the parts. -/
theorem mem_parts_foldr (rho : Assign) (c : Constraint) (l : Label) :
    l ∈ (parts rho c).foldr (· ∪ ·) ∅ ↔ l ∈ c.conc ∨ ∃ v ∈ c.vars, l ∈ rho v := by
  rw [mem_foldr_union]
  simp [parts]

/-- Introduction rule for the disjointness half of `Sat`. -/
theorem pairwise_parts_of (hconc : ∀ v ∈ c.vars, Disjoint c.conc (rho v))
    (hvars : c.vars.Pairwise fun v w => Disjoint (rho v) (rho w)) :
    (parts rho c).Pairwise Disjoint := by
  simp only [parts, List.pairwise_cons]
  refine ⟨?_, List.pairwise_map.mpr hvars⟩
  intro s hs
  obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hs
  exact hconc v hv

/-- Introduction rule for `Sat`, stated pointwise in the label. -/
theorem sat_of (hmem : ∀ l, l ∈ rho c.lhs ↔ (l ∈ c.conc ∨ ∃ v ∈ c.vars, l ∈ rho v))
    (hconc : ∀ v ∈ c.vars, Disjoint c.conc (rho v))
    (hvars : c.vars.Pairwise fun v w => Disjoint (rho v) (rho w)) : Sat rho c :=
  ⟨by ext l; rw [mem_parts_foldr]; exact hmem l, pairwise_parts_of hconc hvars⟩

variable {a b w x y z u : Var} {xs ys zs ds : List Var} {C D E F K : Finset Label}

/-- `sat_of` at an explicit constraint literal. -/
theorem sat_mk (hmem : ∀ l, l ∈ rho a ↔ (l ∈ K ∨ ∃ v ∈ xs, l ∈ rho v))
    (hconc : ∀ v ∈ xs, Disjoint K (rho v))
    (hvars : xs.Pairwise fun v w => Disjoint (rho v) (rho w)) : Sat rho ⟨a, xs, K⟩ :=
  sat_of hmem hconc hvars

/-- Membership characterisation, at a constraint literal. -/
theorem Sat.mem_iff (h : Sat rho ⟨a, xs, K⟩) (l : Label) :
    l ∈ rho a ↔ (l ∈ K ∨ ∃ v ∈ xs, l ∈ rho v) := h.mem_lhs_iff l

/-- The union equation, at a constraint literal. -/
theorem Sat.eq_of (h : Sat rho ⟨a, xs, K⟩) :
    rho a = K ∪ (xs.map rho).foldr (· ∪ ·) ∅ := h.eq_union

/-- The concrete part is disjoint from every variable part, at a constraint literal. -/
theorem Sat.conc_disj (h : Sat rho ⟨a, xs, K⟩) {v : Var} (hv : v ∈ xs) :
    Disjoint K (rho v) := h.disjoint_conc hv

/-- Every variable part is inside the left-hand row, at a constraint literal. -/
theorem Sat.sub (h : Sat rho ⟨a, xs, K⟩) {v : Var} (hv : v ∈ xs) : rho v ⊆ rho a :=
  h.subset_lhs hv

/-- The concrete part is inside the left-hand row, at a constraint literal. -/
theorem Sat.conc_sub (h : Sat rho ⟨a, xs, K⟩) : K ⊆ rho a := h.conc_subset_lhs

/-- Pairwise disjointness of the variable parts, at a constraint literal. -/
theorem Sat.pw (h : Sat rho ⟨a, xs, K⟩) :
    xs.Pairwise fun v w => Disjoint (rho v) (rho w) := h.pairwise_vars

/-- The FIRST variable of a right-hand side is disjoint from all the later ones -- note
this is positional, so it needs no distinctness hypothesis. -/
theorem Sat.disjoint_cons_head (h : Sat rho ⟨a, b :: xs, K⟩) {v : Var} (hv : v ∈ xs) :
    Disjoint (rho b) (rho v) := by
  have hp : (b :: xs).Pairwise fun v w => Disjoint (rho v) (rho w) := h.pw
  exact (List.pairwise_cons.mp hp).1 v hv

/-- Variables in the left block of an appended right-hand side are disjoint from those in
the right block -- again positional. -/
theorem Sat.disjoint_append (h : Sat rho ⟨a, xs ++ ys, K⟩) {v : Var} (hv : v ∈ xs)
    {t : Var} (ht : t ∈ ys) : Disjoint (rho v) (rho t) := by
  have hp : (xs ++ ys).Pairwise fun v w => Disjoint (rho v) (rho w) := h.pw
  exact (List.pairwise_append.mp hp).2.2 v hv t ht

/-- Pairwise disjointness of the left block of an appended right-hand side. -/
theorem Sat.pw_append_left (h : Sat rho ⟨a, xs ++ ys, K⟩) :
    xs.Pairwise fun v w => Disjoint (rho v) (rho w) := by
  have hp : (xs ++ ys).Pairwise fun v w => Disjoint (rho v) (rho w) := h.pw
  exact (List.pairwise_append.mp hp).1

/-- Pairwise disjointness of the right block of an appended right-hand side. -/
theorem Sat.pw_append_right (h : Sat rho ⟨a, xs ++ ys, K⟩) :
    ys.Pairwise fun v w => Disjoint (rho v) (rho w) := by
  have hp : (xs ++ ys).Pairwise fun v w => Disjoint (rho v) (rho w) := h.pw
  exact (List.pairwise_append.mp hp).2.1

/-- Membership characterisation for a one-variable right-hand side. -/
theorem Sat.mem_one (h : Sat rho ⟨a, [x], K⟩) (l : Label) :
    l ∈ rho a ↔ (l ∈ K ∨ l ∈ rho x) := by
  have h' := h.mem_iff l
  rwa [exists_mem_singleton] at h'

/-- Disjointness for a one-variable right-hand side. -/
theorem Sat.disj_one (h : Sat rho ⟨a, [x], K⟩) : Disjoint K (rho x) :=
  h.conc_disj (by simp)

/-- Introduction rule for a one-variable right-hand side. -/
theorem sat_one_mk (hmem : ∀ l, l ∈ rho a ↔ (l ∈ K ∨ l ∈ rho x))
    (hd : Disjoint K (rho x)) : Sat rho ⟨a, [x], K⟩ := by
  refine sat_mk (fun l => ?_) (fun v hv => ?_) (by simp)
  · rw [exists_mem_singleton]; exact hmem l
  · rw [List.mem_singleton] at hv; subst hv; exact hd

/-- Membership characterisation for a cons right-hand side. -/
theorem Sat.mem_cons (h : Sat rho ⟨a, w :: ys, K⟩) (l : Label) :
    l ∈ rho a ↔ (l ∈ K ∨ l ∈ rho w ∨ ∃ v ∈ ys, l ∈ rho v) := by
  have h' := h.mem_iff l
  rwa [exists_mem_cons] at h'

/-- Introduction rule for a cons right-hand side. -/
theorem sat_cons_mk (hmem : ∀ l, l ∈ rho a ↔ (l ∈ K ∨ l ∈ rho w ∨ ∃ v ∈ ys, l ∈ rho v))
    (hKw : Disjoint K (rho w)) (hKy : ∀ v ∈ ys, Disjoint K (rho v))
    (hwy : ∀ v ∈ ys, Disjoint (rho w) (rho v))
    (hy : ys.Pairwise fun v t => Disjoint (rho v) (rho t)) : Sat rho ⟨a, w :: ys, K⟩ := by
  refine sat_mk (fun l => ?_) (fun v hv => ?_) (List.pairwise_cons.mpr ⟨hwy, hy⟩)
  · rw [exists_mem_cons]; exact hmem l
  · rcases List.mem_cons.mp hv with rfl | hv'
    · exact hKw
    · exact hKy v hv'

/-- Membership characterisation for an appended right-hand side. -/
theorem Sat.mem_append (h : Sat rho ⟨a, xs ++ ys, K⟩) (l : Label) :
    l ∈ rho a ↔ (l ∈ K ∨ (∃ v ∈ xs, l ∈ rho v) ∨ ∃ v ∈ ys, l ∈ rho v) := by
  have h' := h.mem_iff l
  rwa [exists_mem_append] at h'

/-- Introduction rule for an appended right-hand side. -/
theorem sat_append_mk
    (hmem : ∀ l, l ∈ rho a ↔ (l ∈ K ∨ (∃ v ∈ xs, l ∈ rho v) ∨ ∃ v ∈ ys, l ∈ rho v))
    (hK : ∀ v ∈ xs ++ ys, Disjoint K (rho v))
    (hxs : xs.Pairwise fun v t => Disjoint (rho v) (rho t))
    (hys : ys.Pairwise fun v t => Disjoint (rho v) (rho t))
    (hcross : ∀ v ∈ xs, ∀ t ∈ ys, Disjoint (rho v) (rho t)) : Sat rho ⟨a, xs ++ ys, K⟩ := by
  refine sat_mk (fun l => ?_) hK (List.pairwise_append.mpr ⟨hxs, hys, hcross⟩)
  rw [exists_mem_append]; exact hmem l

/-! ### The union of a group of variables -/

/-- The union of the rows assigned to a list of variables. -/
def rowSum (rho : Assign) (xs : List Var) : Row := (xs.map rho).foldr (· ∪ ·) ∅

theorem mem_rowSum {l : Label} : l ∈ rowSum rho xs ↔ ∃ v ∈ xs, l ∈ rho v := by
  rw [rowSum, mem_foldr_union]
  simp

theorem rowSum_congr {rho rho' : Assign} (h : ∀ v ∈ xs, rho v = rho' v) :
    rowSum rho xs = rowSum rho' xs := by
  rw [rowSum, rowSum, List.map_congr_left h]

theorem subset_rowSum {v : Var} (hv : v ∈ xs) : rho v ⊆ rowSum rho xs :=
  fun _ hl => mem_rowSum.mpr ⟨v, hv, hl⟩

theorem disjoint_rowSum_right {s : Row} (h : ∀ v ∈ xs, Disjoint s (rho v)) :
    Disjoint s (rowSum rho xs) := by
  rw [Finset.disjoint_left]
  intro l hl hl'
  obtain ⟨v, hv, hlv⟩ := mem_rowSum.mp hl'
  exact Finset.disjoint_left.mp (h v hv) hl hlv

theorem disjoint_rowSum_left {s : Row} (h : ∀ v ∈ xs, Disjoint (rho v) s) :
    Disjoint (rowSum rho xs) s := by
  rw [Finset.disjoint_left]
  intro l hl hl'
  obtain ⟨v, hv, hlv⟩ := mem_rowSum.mp hl
  exact Finset.disjoint_left.mp (h v hv) hlv hl'

/-- A constraint with an empty concrete part says exactly that its left-hand row is the
union of a pairwise-disjoint group of variables. -/
theorem sat_empty_conc :
    Sat rho ⟨u, xs, (∅ : Finset Label)⟩ ↔
      rho u = rowSum rho xs ∧ xs.Pairwise fun v t => Disjoint (rho v) (rho t) := by
  constructor
  · intro h
    refine ⟨?_, h.pw⟩
    have he := h.eq_of
    simpa [rowSum] using he
  · rintro ⟨he, hp⟩
    refine sat_mk (fun l => ?_) (fun v _ => by simp) hp
    rw [he]
    simp [mem_rowSum]

/-! ### Assignments differing at one variable -/

/-- `upd rho u s` is `rho` with the row of `u` replaced by `s`. -/
def upd (rho : Assign) (u : Var) (s : Row) : Assign := fun v => if v = u then s else rho v

@[simp] theorem upd_same (rho : Assign) (u : Var) (s : Row) : upd rho u s u = s := by
  simp [upd]

theorem upd_ne (rho : Assign) {u v : Var} (s : Row) (h : v ≠ u) : upd rho u s v = rho v := by
  simp [upd, h]

theorem upd_agrees (rho : Assign) (u : Var) (s : Row) : ∀ v, v ≠ u → upd rho u s v = rho v :=
  fun _ h => upd_ne rho s h

theorem upd_of_not_mem (rho : Assign) (u : Var) (s : Row) (hu : u ∉ xs) :
    ∀ v ∈ xs, upd rho u s v = rho v :=
  fun _ hv => upd_ne rho s fun h => hu (h ▸ hv)

/-- `Sat` only depends on the rows of the variables the constraint mentions. -/
theorem sat_congr {rho rho' : Assign} (hlhs : rho c.lhs = rho' c.lhs)
    (hv : ∀ v ∈ c.vars, rho v = rho' v) : Sat rho c ↔ Sat rho' c := by
  have hp : parts rho c = parts rho' c := by
    simp only [parts]
    rw [List.map_congr_left hv]
  unfold Sat
  rw [hp, hlhs]

/-- Transport a `Pairwise` disjointness statement along an agreeing assignment. -/
theorem pairwise_disj_congr {rho rho' : Assign} (h : ∀ v ∈ xs, rho v = rho' v)
    (hp : xs.Pairwise fun v t => Disjoint (rho v) (rho t)) :
    xs.Pairwise fun v t => Disjoint (rho' v) (rho' t) :=
  hp.imp_of_mem fun {v t} hv ht hd => by rw [← h v hv, ← h t ht]; exact hd

/-! ### Building small systems -/

theorem models_of_one {c : Constraint} (h : Sat rho c) : Models rho [c] := by
  intro d hd
  simp at hd
  subst hd
  exact h

theorem models_of_two {c d : Constraint} (h1 : Sat rho c) (h2 : Sat rho d) :
    Models rho [c, d] := by
  intro e he
  simp at he
  rcases he with rfl | rfl
  exacts [h1, h2]

theorem models_of_three {c d e : Constraint} (h1 : Sat rho c) (h2 : Sat rho d)
    (h3 : Sat rho e) : Models rho [c, d, e] := by
  intro f hf
  simp at hf
  rcases hf with rfl | rfl | rfl
  exacts [h1, h2, h3]

end Toolkit

/-! ## 1. Multi-block concrete parts, and why one concrete part is enough

The informal rules write right-hand sides with several concrete blocks, `a <- C* D* x`.
`RawConstraint` is that syntax; `flatten` unions the blocks.  `rsat_iff_flatten` shows
the flattened form loses exactly one thing: the demand that the concrete blocks be
pairwise disjoint.  That demand is error condition 10. -/

/-- A right-hand side with several concrete blocks. -/
structure RawConstraint where
  /-- The variable being partitioned. -/
  lhs : Var
  /-- The concrete blocks of the right-hand side. -/
  concs : List Row
  /-- The variable parts of the right-hand side. -/
  vars : List Var

/-- All the parts of a raw right-hand side. -/
def rparts (rho : Assign) (r : RawConstraint) : List Row := r.concs ++ r.vars.map rho

/-- Satisfaction for a raw (multi-block) constraint. -/
def RSat (rho : Assign) (r : RawConstraint) : Prop :=
  rho r.lhs = (rparts rho r).foldr (· ∪ ·) ∅ ∧ (rparts rho r).Pairwise Disjoint

/-- Union the concrete blocks into a single one. -/
def flatten (r : RawConstraint) : Constraint :=
  ⟨r.lhs, r.vars, r.concs.foldr (· ∪ ·) ∅⟩

/-- A `foldr`-union is disjoint from `t` iff each summand is. -/
theorem disjoint_foldr_union_left (L : List Row) (t : Row) :
    Disjoint (L.foldr (· ∪ ·) ∅) t ↔ ∀ s ∈ L, Disjoint s t := by
  constructor
  · intro h s hs
    refine disjoint_of_subset_left h ?_
    intro l hl
    exact mem_foldr_union L l |>.mpr ⟨s, hs, hl⟩
  · intro h
    rw [Finset.disjoint_left]
    intro l hl hlt
    obtain ⟨s, hs, hls⟩ := (mem_foldr_union L l).mp hl
    exact Finset.disjoint_left.mp (h s hs) hls hlt

/-- **Flattening is faithful.**  A multi-block right-hand side is satisfied exactly when
its union-flattened form is satisfied and the concrete blocks are pairwise disjoint. -/
theorem rsat_iff_flatten (rho : Assign) (r : RawConstraint) :
    RSat rho r ↔ Sat rho (flatten r) ∧ r.concs.Pairwise Disjoint := by
  have hfold : (rparts rho r).foldr (· ∪ ·) ∅ = (parts rho (flatten r)).foldr (· ∪ ·) ∅ := by
    simp only [rparts, parts, flatten, List.foldr_cons]
    exact foldr_union_append _ _
  have hpw : (rparts rho r).Pairwise Disjoint ↔
      ((parts rho (flatten r)).Pairwise Disjoint ∧ r.concs.Pairwise Disjoint) := by
    simp only [rparts, parts, flatten, List.pairwise_append, List.pairwise_cons]
    constructor
    · rintro ⟨hc, hm, hcross⟩
      refine ⟨⟨fun t ht => ?_, hm⟩, hc⟩
      exact (disjoint_foldr_union_left _ t).mpr fun s hs => hcross s hs t ht
    · rintro ⟨⟨hct, hm⟩, hc⟩
      refine ⟨hc, hm, fun s hs t ht => ?_⟩
      exact (disjoint_foldr_union_left _ t).mp (hct t ht) s hs
  unfold RSat Sat
  rw [hfold, hpw]
  simp only [flatten]
  tauto

/-! ## 2. Conservative extension: the correct soundness statement for a fresh variable -/

/-- `u` does not occur in the constraint `c`. -/
def NotIn (u : Var) (c : Constraint) : Prop := c.lhs ≠ u ∧ u ∉ c.vars

/-- `u` occurs nowhere in the system `G`. -/
def Fresh (u : Var) (G : List Constraint) : Prop := ∀ c ∈ G, NotIn u c

/-- **Conservative extension.**  Every model of `G` extends, by changing only `u`, to a
model of `G'`; and every model of `G'` is already a model of `G`.  This is the correct
soundness statement for an inference rule that mints the fresh variable `u`. -/
def ConservativeExt (G : List Constraint) (u : Var) (G' : List Constraint) : Prop :=
  (∀ rho, Models rho G → ∃ rho', (∀ v, v ≠ u → rho' v = rho v) ∧ Models rho' G') ∧
    (∀ rho, Models rho G' → Models rho G)

/-- A conservative extension preserves satisfiability in both directions. -/
theorem ConservativeExt.satisfiable_iff {G G' : List Constraint} {u : Var}
    (h : ConservativeExt G u G') : (∃ rho, Models rho G) ↔ (∃ rho, Models rho G') := by
  constructor
  · rintro ⟨rho, hm⟩
    obtain ⟨rho', _, hm'⟩ := h.1 rho hm
    exact ⟨rho', hm'⟩
  · rintro ⟨rho, hm⟩
    exact ⟨rho, h.2 rho hm⟩

/-- A conservative extension does not change which `u`-free constraints are entailed. -/
theorem ConservativeExt.entails_iff {G G' : List Constraint} {u : Var}
    (h : ConservativeExt G u G') {c : Constraint} (hc : NotIn u c) :
    Entails G' c ↔ Entails G c := by
  constructor
  · intro hent rho hm
    obtain ⟨rho', hag, hm'⟩ := h.1 rho hm
    refine (sat_congr (rho := rho') (rho' := rho) (hag c.lhs hc.1) ?_).mp (hent rho' hm')
    exact fun v hv => hag v fun hvu => hc.2 (hvu ▸ hv)
  · intro hent rho hm
    exact hent rho (h.2 rho hm)

/-- If a model of `G` is untouched off `u`, and `u` occurs nowhere in `G`, the modified
assignment still models `G`. -/
theorem models_of_agree {G : List Constraint} {u : Var} {rho rho' : Assign}
    (hf : Fresh u G) (hag : ∀ v, v ≠ u → rho' v = rho v) (hm : Models rho G) :
    Models rho' G := by
  intro c hc
  obtain ⟨h1, h2⟩ := hf c hc
  refine (sat_congr (rho := rho) (rho' := rho') ?_ ?_).mp (hm c hc)
  · exact (hag c.lhs h1).symm
  · exact fun v hv => (hag v fun hvu => h2 (hvu ▸ hv)).symm

/-- The practically relevant corollary: the solver KEEPS the premises and ADDS the
conclusion, and the enlarged system still has a model. -/
theorem ConservativeExt.models_append {G G' : List Constraint} {u : Var}
    (h : ConservativeExt G u G') (hf : Fresh u G) (rho : Assign) (hm : Models rho G) :
    ∃ rho', (∀ v, v ≠ u → rho' v = rho v) ∧ Models rho' (G ++ G') := by
  obtain ⟨rho', hag, hm'⟩ := h.1 rho hm
  exact ⟨rho', hag, Rowpartition.models_append.mpr ⟨models_of_agree hf hag hm, hm'⟩⟩

/-! ## 3. Rule 1: self-substitution

    a <- a b*
    ---------
      b <-

and, if the concrete part is nonempty, the premise is contradictory (the header's
"infinite fields" error condition, `a <- C+ a x*`). -/

/-- **Rule 1, first half, general form.**  In `a <- a b*` every other variable on the
right is forced empty.  The proof is POSITIONAL (`Sat.disjoint_cons_head`), so no
distinctness hypothesis is needed: the statement holds even when `a` itself reappears
among the `b`s. -/
theorem rule1_empty {rho : Assign} {a : Var} {bs : List Var} {C : Finset Label}
    (h : Sat rho ⟨a, a :: bs, C⟩) {b : Var} (hb : b ∈ bs) : rho b = ∅ :=
  eq_empty_of_disjoint_self
    (disjoint_of_subset_left (h.disjoint_cons_head hb) (h.sub (by simp [hb])))

/-- **Rule 1, second half.**  In `a <- a b*` the concrete part is forced empty. -/
theorem rule1_conc {rho : Assign} {a : Var} {bs : List Var} {C : Finset Label}
    (h : Sat rho ⟨a, a :: bs, C⟩) : C = ∅ :=
  eq_empty_of_disjoint_self (disjoint_of_subset_right (h.conc_disj (by simp)) h.conc_sub)

/-- **Rule 1 as an "infinite row" error.**  `a <- C+ a b*` with `C` nonempty has NO
model whatsoever. -/
theorem rule1_unsat {a : Var} {bs : List Var} {C : Finset Label} (hC : C ≠ ∅) (rho : Assign) :
    ¬ Sat rho ⟨a, a :: bs, C⟩ := fun h => hC (rule1_conc h)

/-- Entailment form of rule 1: `b <-` really is derivable. -/
theorem rule1_entails {a : Var} {bs : List Var} {C : Finset Label} {b : Var} (hb : b ∈ bs) :
    Entails [⟨a, a :: bs, C⟩] ⟨b, [], (∅ : Finset Label)⟩ := by
  intro rho hm
  rw [sat_zero]
  exact rule1_empty (hm ⟨a, a :: bs, C⟩ (by simp)) hb

/-- Rule 1 for an arbitrary position of the left-hand variable on the right.  Here the
distinctness hypothesis `v ≠ c.lhs` IS needed, because the argument is by name rather
than by position. -/
theorem rule1_general {rho : Assign} {c : Constraint} (h : Sat rho c) (hmem : c.lhs ∈ c.vars) :
    c.conc = ∅ ∧ ∀ v ∈ c.vars, v ≠ c.lhs → rho v = ∅ := by
  refine ⟨eq_empty_of_disjoint_self
      (disjoint_of_subset_right (h.disjoint_conc hmem) h.conc_subset_lhs), ?_⟩
  intro v hv hne
  exact eq_empty_of_disjoint_self
    (disjoint_of_subset_left (h.disjoint_of_ne hmem hv (Ne.symm hne)) (h.subset_lhs hv))

/-! ## 4. Rule 2: empty partition

    a <-
    a <- x+
    -------
    (x <-)+ -/

/-- **Rule 2, general form.**  If `a` is empty and `a <- x*`, every `x` is empty. -/
theorem rule2 {rho : Assign} {a : Var} {xs : List Var} {K : Finset Label}
    (h0 : Sat rho ⟨a, [], (∅ : Finset Label)⟩) (h : Sat rho ⟨a, xs, K⟩) {x : Var}
    (hx : x ∈ xs) : rho x = ∅ := by
  have ha : rho a = ∅ := (sat_zero rho a ∅).mp h0
  have hs : rho x ⊆ rho a := h.sub hx
  rw [ha] at hs
  simpa using hs

/-- The concrete part of the second premise is forced empty too. -/
theorem rule2_conc {rho : Assign} {a : Var} {xs : List Var} {K : Finset Label}
    (h0 : Sat rho ⟨a, [], (∅ : Finset Label)⟩) (h : Sat rho ⟨a, xs, K⟩) : K = ∅ := by
  have ha : rho a = ∅ := (sat_zero rho a ∅).mp h0
  have hs : K ⊆ rho a := h.conc_sub
  rw [ha] at hs
  simpa using hs

/-- Entailment form of rule 2. -/
theorem rule2_entails {a : Var} {xs : List Var} {K : Finset Label} {x : Var} (hx : x ∈ xs) :
    Entails [⟨a, [], (∅ : Finset Label)⟩, ⟨a, xs, K⟩] ⟨x, [], (∅ : Finset Label)⟩ := by
  intro rho hm
  rw [sat_zero]
  exact rule2 (hm ⟨a, [], ∅⟩ (by simp)) (hm ⟨a, xs, K⟩ (by simp)) hx

/-! ## 5. Rule 3: de-duplication

    a <- C* x* b b
    --------------
         b <-      -/

/-- **Rule 3, general form.**  A variable occurring at least twice on a right-hand side
is empty.  (This is `Sat.eq_empty_of_dup` from the foundations, restated as a rule.) -/
theorem rule3 {rho : Assign} {a : Var} {xs : List Var} {K : Finset Label} {b : Var}
    (h : Sat rho ⟨a, xs, K⟩) (hb : 2 ≤ xs.count b) : rho b = ∅ :=
  h.eq_empty_of_dup hb

/-- Entailment form of rule 3. -/
theorem rule3_entails {a : Var} {xs : List Var} {K : Finset Label} {b : Var}
    (hb : 2 ≤ xs.count b) : Entails [⟨a, xs, K⟩] ⟨b, [], (∅ : Finset Label)⟩ := by
  intro rho hm
  rw [sat_zero]
  exact rule3 (hm ⟨a, xs, K⟩ (by simp)) hb

/-- Rule 3 at the concrete arity `a <- C* x b b`, proved directly from positional
disjointness rather than from the `count` version. -/
theorem rule3_concrete {rho : Assign} {a x b : Var} {K : Finset Label}
    (h : Sat rho ⟨a, [x, b, b], K⟩) : rho b = ∅ := by
  have hp : ([x, b, b] : List Var).Pairwise fun v t => Disjoint (rho v) (rho t) := h.pw
  rw [List.pairwise_cons, List.pairwise_cons] at hp
  exact eq_empty_of_disjoint_self (hp.2.1 b (by simp))

/-! ## 6. Rule 4: split concrete -- FRESH VARIABLE

    a <- C+ x++
    -----------
     u <- x++    (u fresh)
     a <- C+ u

The conclusion mentions `u`, which the premise does not, so the statement is a
CONSERVATIVE EXTENSION, not an entailment.  Freshness (`hau`, `hxu`) is used only in the
forward half; the backward half holds for any `u` at all. -/

/-- `u` really is fresh for the premise of rule 4. -/
theorem rule4_fresh {a u : Var} {xs : List Var} {C : Finset Label} (hau : a ≠ u)
    (hxu : u ∉ xs) : Fresh u [⟨a, xs, C⟩] := by
  intro c hc
  simp at hc
  subst hc
  exact ⟨hau, hxu⟩

/-- **The backward half of rule 4**: the conclusion already implies the premise.  Note
that NO freshness hypothesis occurs here; freshness is needed only for the forward
half. -/
theorem rule4_back {a u : Var} {xs : List Var} {C : Finset Label} (rho : Assign)
    (hm : Models rho [⟨u, xs, (∅ : Finset Label)⟩, ⟨a, [u], C⟩]) :
    Models rho [⟨a, xs, C⟩] := by
  have h1 : Sat rho ⟨u, xs, (∅ : Finset Label)⟩ := hm _ (by simp)
  have h2 : Sat rho ⟨a, [u], C⟩ := hm _ (by simp)
  obtain ⟨he, hp⟩ := sat_empty_conc.mp h1
  refine models_of_one (sat_mk (fun l => ?_) (fun v hv => ?_) hp)
  · rw [h2.mem_one l, he, mem_rowSum]
  · refine disjoint_of_subset_right h2.disj_one ?_
    rw [he]
    exact subset_rowSum hv

/-- **Rule 4 (split concrete), general form, both halves.**  The freshness hypotheses
`hau` and `hxu` are used in the forward half only (see `rule4_back`). -/
theorem rule4 {a u : Var} {xs : List Var} {C : Finset Label} (hau : a ≠ u) (hxu : u ∉ xs) :
    ConservativeExt [⟨a, xs, C⟩] u [⟨u, xs, (∅ : Finset Label)⟩, ⟨a, [u], C⟩] := by
  constructor
  · -- forward: extend the model by giving `u` the union of the group
    intro rho hm
    have h : Sat rho ⟨a, xs, C⟩ := hm _ (by simp)
    refine ⟨upd rho u (rowSum rho xs), upd_agrees rho u _, ?_⟩
    have hxs : ∀ v ∈ xs, upd rho u (rowSum rho xs) v = rho v := upd_of_not_mem rho u _ hxu
    refine models_of_two ?_ ?_
    · refine sat_empty_conc.mpr ⟨?_, pairwise_disj_congr (fun v hv => (hxs v hv).symm) h.pw⟩
      rw [upd_same, rowSum_congr hxs]
    · refine sat_one_mk (fun l => ?_) ?_
      · rw [upd_ne rho _ hau, upd_same, h.mem_iff l, mem_rowSum]
      · rw [upd_same]
        exact disjoint_rowSum_right fun v hv => h.conc_disj hv
  · exact rule4_back

/-- Rule 4 at the concrete arity `a <- C (x1, x2)`. -/
theorem rule4_concrete {a u x1 x2 : Var} {C : Finset Label} (hau : a ≠ u) (h1 : u ≠ x1)
    (h2 : u ≠ x2) :
    ConservativeExt [⟨a, [x1, x2], C⟩] u [⟨u, [x1, x2], (∅ : Finset Label)⟩, ⟨a, [u], C⟩] :=
  rule4 hau (by simp [h1, h2])

/-! ## 7. Rule 5: cancellation

    a <- C* x* z
    a <- C* x* D* d*
    ----------------
       z <- D* d*

Stated in the sharp form the implementation actually uses (`Constraints.scala`,
`def cancellation`): the shared concrete part need only satisfy `C ⊆ K`, and the
conclusion carries `K \ C`.  The Scala code enforces `C ⊆ K` by the guard
`fs.isEmpty`, where `fs = con1 -- (con1 & con2)`. -/

/-- If `C` and `D` are disjoint, removing `C` from `C ∪ D` leaves `D`. -/
theorem union_sdiff_of_disjoint {C D : Finset Label} (h : Disjoint C D) : (C ∪ D) \ C = D := by
  ext l
  simp only [Finset.mem_sdiff, Finset.mem_union]
  constructor
  · rintro ⟨hl | hl, hn⟩
    · exact absurd hl hn
    · exact hl
  · intro hl
    exact ⟨Or.inr hl, fun hc => Finset.disjoint_left.mp h hc hl⟩

/-- **Rule 5 (cancellation), general form.** -/
theorem rule5 {rho : Assign} {a z : Var} {xs ds : List Var} {C K : Finset Label}
    (hCK : C ⊆ K) (h1 : Sat rho ⟨a, xs ++ [z], C⟩) (h2 : Sat rho ⟨a, xs ++ ds, K⟩) :
    Sat rho ⟨z, ds, K \ C⟩ := by
  have hz : z ∈ xs ++ [z] := by simp
  refine sat_mk (fun l => ?_) (fun v hv => ?_) h2.pw_append_right
  · constructor
    · intro hl
      rcases (h2.mem_append l).mp (h1.sub hz hl) with hK | ⟨v, hv, hlv⟩ | ⟨v, hv, hlv⟩
      · exact Or.inl (Finset.mem_sdiff.mpr
          ⟨hK, fun hlC => Finset.disjoint_left.mp (h1.conc_disj hz) hlC hl⟩)
      · exact absurd hl (Finset.disjoint_left.mp (h1.disjoint_append hv (by simp)) hlv)
      · exact Or.inr ⟨v, hv, hlv⟩
    · rintro (hl | ⟨v, hv, hlv⟩)
      · obtain ⟨hlK, hlC⟩ := Finset.mem_sdiff.mp hl
        rcases (h1.mem_append l).mp (h2.conc_sub hlK) with hC | ⟨v, hv, hlv⟩ | ⟨v, hv, hlv⟩
        · exact absurd hC hlC
        · exact absurd hlv (Finset.disjoint_left.mp (h2.conc_disj (by simp [hv])) hlK)
        · rw [List.mem_singleton] at hv; subst hv; exact hlv
      · rcases (h1.mem_append l).mp (h2.sub (by simp [hv]) hlv) with
          hC | ⟨t, ht, hlt⟩ | ⟨t, ht, hlt⟩
        · exact absurd hlv (Finset.disjoint_left.mp (h2.conc_disj (by simp [hv])) (hCK hC))
        · exact absurd hlv (Finset.disjoint_left.mp (h2.disjoint_append ht hv) hlt)
        · rw [List.mem_singleton] at ht; subst ht; exact hlt
  · exact disjoint_of_subset_left (h2.conc_disj (by simp [hv])) Finset.sdiff_subset

/-- **Rule 5 in the header's notation**: the second premise's concrete part is `C* D*`,
with `C*` shared with the first premise and `D*` disjoint from it (header convention 8). -/
theorem rule5_header {rho : Assign} {a z : Var} {xs ds : List Var} {C D : Finset Label}
    (hCD : Disjoint C D) (h1 : Sat rho ⟨a, xs ++ [z], C⟩) (h2 : Sat rho ⟨a, xs ++ ds, C ∪ D⟩) :
    Sat rho ⟨z, ds, D⟩ := by
  have h := rule5 Finset.subset_union_left h1 h2
  rwa [union_sdiff_of_disjoint hCD] at h

/-- Rule 5 at concrete arity: `a <- (x, z)` against `a <- (x, d1, d2)`. -/
theorem rule5_concrete {rho : Assign} {a x z d1 d2 : Var} {C D : Finset Label}
    (hCD : Disjoint C D) (h1 : Sat rho ⟨a, [x, z], C⟩) (h2 : Sat rho ⟨a, [x, d1, d2], C ∪ D⟩) :
    Sat rho ⟨z, [d1, d2], D⟩ :=
  rule5_header (xs := [x]) (ds := [d1, d2]) hCD h1 h2

/-- Entailment form of rule 5. -/
theorem rule5_entails {a z : Var} {xs ds : List Var} {C K : Finset Label} (hCK : C ⊆ K) :
    Entails [⟨a, xs ++ [z], C⟩, ⟨a, xs ++ ds, K⟩] ⟨z, ds, K \ C⟩ :=
  fun _ hm => rule5 hCK (hm ⟨a, xs ++ [z], C⟩ (by simp)) (hm ⟨a, xs ++ ds, K⟩ (by simp))

/-! ## 8. Rule 6: resolution -- FRESH VARIABLE, and a bug in the header comment

The header comment states

     a <- C* D* x
     a <- y  D* E*
    ---------------
    a <- C* D* E* z  (z fresh)
       x <- C* z
       y <- E* z

but the prose above it says "each of the lone right variables contain the fields missing
from THEIR rule", which is the SWAPPED pairing `x <- E* z`, `y <- C* z`; and the Scala
implementation (`def resolution`) computes `bots = concr2 -- (concr1 & concr2)` for `x`
and `tops = concr1 -- (concr1 & concr2)` for `y`, i.e. `x <- (E \ C) z` and
`y <- (C \ E) z`.  `rule6` below proves the implementation's version sound, with no
disjointness needed between `C` and `E`.  `Rule6Header.header_not_conservative` proves
the header comment's version UNSOUND. -/

section Resolution

variable {a x y z : Var} {C D E : Finset Label}

/-- Removing a disjoint set changes nothing. -/
theorem sdiff_eq_self_of_disjoint {s t : Row} (h : Disjoint s t) : s \ t = s := by
  ext l
  simp only [Finset.mem_sdiff]
  exact ⟨And.left, fun hl => ⟨hl, Finset.disjoint_left.mp h hl⟩⟩

/-- `z` really is fresh for the premises of rule 6. -/
theorem rule6_fresh (haz : a ≠ z) (hxz : x ≠ z) (hyz : y ≠ z) :
    Fresh z [⟨a, [x], C ∪ D⟩, ⟨a, [y], D ∪ E⟩] := by
  intro c hc
  simp at hc
  rcases hc with rfl | rfl
  · exact ⟨haz, by simp [Ne.symm hxz]⟩
  · exact ⟨haz, by simp [Ne.symm hyz]⟩

/-- **The backward half of rule 6**: the conclusion implies both premises.  NO freshness
hypothesis occurs here -- only the two disjointness side conditions that the premises
themselves force. -/
theorem rule6_back (hCD : Disjoint C D) (hDE : Disjoint D E) (rho : Assign)
    (hm : Models rho [⟨a, [z], C ∪ D ∪ E⟩, ⟨x, [z], E \ C⟩, ⟨y, [z], C \ E⟩]) :
    Models rho [⟨a, [x], C ∪ D⟩, ⟨a, [y], D ∪ E⟩] := by
  have g1 : Sat rho ⟨a, [z], C ∪ D ∪ E⟩ := hm _ (by simp)
  have g2 : Sat rho ⟨x, [z], E \ C⟩ := hm _ (by simp)
  have g3 : Sat rho ⟨y, [z], C \ E⟩ := hm _ (by simp)
  refine models_of_two ?_ ?_
  · refine sat_one_mk (fun l => ?_) ?_
    · rw [g1.mem_one l, g2.mem_one l]
      constructor
      · rintro (hl | hl)
        · rcases Finset.mem_union.mp hl with hCD' | hE
          · exact Or.inl hCD'
          · by_cases hC : l ∈ C
            · exact Or.inl (Finset.mem_union_left _ hC)
            · exact Or.inr (Or.inl (Finset.mem_sdiff.mpr ⟨hE, hC⟩))
        · exact Or.inr (Or.inr hl)
      · rintro (hl | hl | hl)
        · exact Or.inl (Finset.mem_union_left _ hl)
        · exact Or.inl (Finset.mem_union_right _ (Finset.mem_sdiff.mp hl).1)
        · exact Or.inr hl
    · rw [Finset.disjoint_left]
      intro l hl hlx
      rcases (g2.mem_one l).mp hlx with hEC | hz
      · obtain ⟨hE, hC⟩ := Finset.mem_sdiff.mp hEC
        rcases Finset.mem_union.mp hl with hC' | hD
        · exact hC hC'
        · exact Finset.disjoint_left.mp hDE hD hE
      · exact Finset.disjoint_left.mp g1.disj_one (Finset.mem_union_left _ hl) hz
  · refine sat_one_mk (fun l => ?_) ?_
    · rw [g1.mem_one l, g3.mem_one l]
      constructor
      · rintro (hl | hl)
        · rcases Finset.mem_union.mp hl with hCD' | hE
          · rcases Finset.mem_union.mp hCD' with hC | hD
            · by_cases hE : l ∈ E
              · exact Or.inl (Finset.mem_union_right _ hE)
              · exact Or.inr (Or.inl (Finset.mem_sdiff.mpr ⟨hC, hE⟩))
            · exact Or.inl (Finset.mem_union_left _ hD)
          · exact Or.inl (Finset.mem_union_right _ hE)
        · exact Or.inr (Or.inr hl)
      · rintro (hl | hl | hl)
        · rcases Finset.mem_union.mp hl with hD | hE
          · exact Or.inl (Finset.mem_union_left _ (Finset.mem_union_right _ hD))
          · exact Or.inl (Finset.mem_union_right _ hE)
        · exact Or.inl (Finset.mem_union_left _
            (Finset.mem_union_left _ (Finset.mem_sdiff.mp hl).1))
        · exact Or.inr hl
    · rw [Finset.disjoint_left]
      intro l hl hly
      rcases (g3.mem_one l).mp hly with hCE | hz
      · obtain ⟨hC, hE⟩ := Finset.mem_sdiff.mp hCE
        rcases Finset.mem_union.mp hl with hD | hE'
        · exact Finset.disjoint_left.mp hCD hC hD
        · exact hE hE'
      · refine Finset.disjoint_left.mp g1.disj_one ?_ hz
        rcases Finset.mem_union.mp hl with hD | hE
        · exact Finset.mem_union_left _ (Finset.mem_union_right _ hD)
        · exact Finset.mem_union_right _ hE

/-- **Rule 6 (resolution), general form, both halves** -- exactly the inference the Scala
`resolution` function performs.  The fresh variable is given the row `rho x ∩ rho y`.
The only side conditions are the ones forced by the premises themselves (`C` and `E`
each disjoint from `D`, because they sit in the same right-hand side as `D`). -/
theorem rule6 (hCD : Disjoint C D) (hDE : Disjoint D E)
    (haz : a ≠ z) (hxz : x ≠ z) (hyz : y ≠ z) :
    ConservativeExt [⟨a, [x], C ∪ D⟩, ⟨a, [y], D ∪ E⟩] z
      [⟨a, [z], C ∪ D ∪ E⟩, ⟨x, [z], E \ C⟩, ⟨y, [z], C \ E⟩] := by
  constructor
  · -- forward: the fresh variable is the intersection of the two lone variables
    intro rho hm
    have h1 : Sat rho ⟨a, [x], C ∪ D⟩ := hm _ (by simp)
    have h2 : Sat rho ⟨a, [y], D ∪ E⟩ := hm _ (by simp)
    have m1 := h1.mem_one
    have m2 := h2.mem_one
    have d1 : Disjoint (C ∪ D) (rho x) := h1.disj_one
    have d2 : Disjoint (D ∪ E) (rho y) := h2.disj_one
    have hCx : ∀ l, l ∈ C → l ∉ rho x := fun _ hl =>
      Finset.disjoint_left.mp d1 (Finset.mem_union_left _ hl)
    have hDx : ∀ l, l ∈ D → l ∉ rho x := fun _ hl =>
      Finset.disjoint_left.mp d1 (Finset.mem_union_right _ hl)
    have hDy : ∀ l, l ∈ D → l ∉ rho y := fun _ hl =>
      Finset.disjoint_left.mp d2 (Finset.mem_union_left _ hl)
    have hEy : ∀ l, l ∈ E → l ∉ rho y := fun _ hl =>
      Finset.disjoint_left.mp d2 (Finset.mem_union_right _ hl)
    have keyx : ∀ l, l ∈ rho x ↔ (l ∈ E \ C ∨ l ∈ rho x ∩ rho y) := by
      intro l
      constructor
      · intro hl
        rcases (m2 l).mp (h1.sub (by simp) hl) with hDE' | hy
        · rcases Finset.mem_union.mp hDE' with hD | hE
          · exact absurd hl (hDx l hD)
          · exact Or.inl (Finset.mem_sdiff.mpr ⟨hE, fun hC => hCx l hC hl⟩)
        · exact Or.inr (Finset.mem_inter.mpr ⟨hl, hy⟩)
      · rintro (hl | hl)
        · obtain ⟨hE, hC⟩ := Finset.mem_sdiff.mp hl
          rcases (m1 l).mp (h2.conc_sub (Finset.mem_union_right _ hE)) with hCD' | hx
          · rcases Finset.mem_union.mp hCD' with hC' | hD
            · exact absurd hC' hC
            · exact absurd hE (Finset.disjoint_left.mp hDE hD)
          · exact hx
        · exact (Finset.mem_inter.mp hl).1
    have keyy : ∀ l, l ∈ rho y ↔ (l ∈ C \ E ∨ l ∈ rho x ∩ rho y) := by
      intro l
      constructor
      · intro hl
        rcases (m1 l).mp (h2.sub (by simp) hl) with hCD' | hx
        · rcases Finset.mem_union.mp hCD' with hC | hD
          · exact Or.inl (Finset.mem_sdiff.mpr ⟨hC, fun hE => hEy l hE hl⟩)
          · exact absurd hl (hDy l hD)
        · exact Or.inr (Finset.mem_inter.mpr ⟨hx, hl⟩)
      · rintro (hl | hl)
        · obtain ⟨hC, hE⟩ := Finset.mem_sdiff.mp hl
          rcases (m2 l).mp (h1.conc_sub (Finset.mem_union_left _ hC)) with hDE' | hy
          · rcases Finset.mem_union.mp hDE' with hD | hE'
            · exact absurd hD (Finset.disjoint_left.mp hCD hC)
            · exact absurd hE' hE
          · exact hy
        · exact (Finset.mem_inter.mp hl).2
    have keya : ∀ l, l ∈ rho a ↔ (l ∈ C ∪ D ∪ E ∨ l ∈ rho x ∩ rho y) := by
      intro l
      constructor
      · intro hl
        rcases (m1 l).mp hl with hCD' | hx
        · exact Or.inl (Finset.mem_union_left _ hCD')
        · rcases (keyx l).mp hx with hEC | hint
          · exact Or.inl (Finset.mem_union_right _ (Finset.mem_sdiff.mp hEC).1)
          · exact Or.inr hint
      · rintro (hl | hl)
        · rcases Finset.mem_union.mp hl with hCD' | hE
          · exact (m1 l).mpr (Or.inl hCD')
          · exact h2.conc_sub (Finset.mem_union_right _ hE)
        · exact h1.sub (by simp) (Finset.mem_inter.mp hl).1
    have dax : Disjoint (C ∪ D ∪ E) (rho x ∩ rho y) := by
      rw [Finset.disjoint_left]
      intro l hl hint
      rcases Finset.mem_union.mp hl with hCD' | hE
      · exact Finset.disjoint_left.mp d1 hCD' (Finset.mem_inter.mp hint).1
      · exact hEy l hE (Finset.mem_inter.mp hint).2
    have dxs : Disjoint (E \ C) (rho x ∩ rho y) := by
      rw [Finset.disjoint_left]
      intro l hl hint
      exact hEy l (Finset.mem_sdiff.mp hl).1 (Finset.mem_inter.mp hint).2
    have dys : Disjoint (C \ E) (rho x ∩ rho y) := by
      rw [Finset.disjoint_left]
      intro l hl hint
      exact hCx l (Finset.mem_sdiff.mp hl).1 (Finset.mem_inter.mp hint).1
    refine ⟨upd rho z (rho x ∩ rho y), upd_agrees rho z _, models_of_three ?_ ?_ ?_⟩
    · refine sat_one_mk (fun l => ?_) ?_
      · rw [upd_ne rho _ haz, upd_same]; exact keya l
      · rw [upd_same]; exact dax
    · refine sat_one_mk (fun l => ?_) ?_
      · rw [upd_ne rho _ hxz, upd_same]; exact keyx l
      · rw [upd_same]; exact dxs
    · refine sat_one_mk (fun l => ?_) ?_
      · rw [upd_ne rho _ hyz, upd_same]; exact keyy l
      · rw [upd_same]; exact dys
  · exact rule6_back hCD hDE

/-- Header convention 8 ("named sequences are disjoint over an entire rule") gives
`Disjoint C E`, and then the sharp form collapses to the header's shape -- with `C` and
`E` SWAPPED relative to what the header comment writes. -/
theorem rule6_swapped (hCD : Disjoint C D) (hDE : Disjoint D E) (hCE : Disjoint C E)
    (haz : a ≠ z) (hxz : x ≠ z) (hyz : y ≠ z) :
    ConservativeExt [⟨a, [x], C ∪ D⟩, ⟨a, [y], D ∪ E⟩] z
      [⟨a, [z], C ∪ D ∪ E⟩, ⟨x, [z], E⟩, ⟨y, [z], C⟩] := by
  have h := rule6 hCD hDE haz hxz hyz
  rwa [sdiff_eq_self_of_disjoint hCE.symm, sdiff_eq_self_of_disjoint hCE] at h

end Resolution

/-! ### The header comment's resolution rule is unsound -/

namespace Rule6Header

/-- The header's first conclusion `x <- C* z` contradicts the first premise
`a <- C* D* x` as soon as `C` is nonempty: the premise makes `C` disjoint from `rho x`,
the conclusion makes `C` a subset of it. -/
theorem premise_conclusion_unsat {rho : Assign} {a x z : Var} {C D : Finset Label}
    (hC : C ≠ ∅) (h1 : Sat rho ⟨a, [x], C ∪ D⟩) (h2 : Sat rho ⟨x, [z], C⟩) : False := by
  refine hC (eq_empty_of_disjoint_self ?_)
  rw [Finset.disjoint_left]
  intro l hl hl'
  exact Finset.disjoint_left.mp h1.disj_one (Finset.mem_union_left _ hl) (h2.conc_sub hl')

/-- A concrete witness: `a = 0`, `x = 1`, `y = 2`, fresh `z = 3`,
`C = {1}`, `D = {}`, `E = {2}`. -/
def rho0 : Assign :=
  fun v => if v = 0 then ({1, 2} : Finset Label) else if v = 1 then {2}
           else if v = 2 then {1} else ∅

/-- The two premises of resolution, instantiated. -/
def G0 : List Constraint :=
  [⟨0, [1], ({1} : Finset Label) ∪ ∅⟩, ⟨0, [2], (∅ : Finset Label) ∪ {2}⟩]

/-- The header comment's conclusion, instantiated. -/
def Gheader : List Constraint :=
  [⟨0, [3], ({1} : Finset Label) ∪ ∅ ∪ {2}⟩, ⟨1, [3], ({1} : Finset Label)⟩,
    ⟨2, [3], ({2} : Finset Label)⟩]

theorem premises_sat : Models rho0 G0 := by
  refine models_of_two ?_ ?_ <;> rw [sat_one] <;> exact ⟨by decide, by decide⟩

/-- No extension of the model along the fresh variable satisfies the header's
conclusion. -/
theorem header_no_extension (rho : Assign) (hm : Models rho G0) :
    ¬ ∃ rho', (∀ v, v ≠ 3 → rho' v = rho v) ∧ Models rho' Gheader := by
  rintro ⟨rho', hag, hm'⟩
  have h1 : Sat rho ⟨0, [1], ({1} : Finset Label) ∪ ∅⟩ := hm _ (by simp [G0])
  have h1' : Sat rho' ⟨0, [1], ({1} : Finset Label) ∪ ∅⟩ := by
    refine (sat_congr (rho := rho) (rho' := rho') ?_ ?_).mp h1
    · exact (hag 0 (by decide)).symm
    · intro v hv
      rw [List.mem_singleton] at hv
      subst hv
      exact (hag 1 (by decide)).symm
  have h2 : Sat rho' ⟨1, [3], ({1} : Finset Label)⟩ := hm' _ (by simp [Gheader])
  exact premise_conclusion_unsat (by decide) h1' h2

/-- **The header comment's resolution rule is not a conservative extension**: its
premises have a model, but no extension of that model satisfies its conclusion. -/
theorem header_not_conservative : ¬ ConservativeExt G0 3 Gheader := by
  rintro ⟨hfwd, -⟩
  exact header_no_extension rho0 premises_sat (hfwd rho0 premises_sat)

/-- The sharper statement: keeping the premises (as the solver does -- the rules are
non-destructive) and adding the header's conclusion yields an UNSATISFIABLE system,
although the premises alone are satisfiable.  The solver would report a type error where
there is none. -/
theorem header_makes_unsat :
    (∃ rho, Models rho G0) ∧ ¬ ∃ rho, Models rho (G0 ++ Gheader) := by
  refine ⟨⟨rho0, premises_sat⟩, ?_⟩
  rintro ⟨rho, hm⟩
  have h1 : Sat rho ⟨0, [1], ({1} : Finset Label) ∪ ∅⟩ := hm _ (by simp [G0])
  have h2 : Sat rho ⟨1, [3], ({1} : Finset Label)⟩ := hm _ (by simp [Gheader])
  exact premise_conclusion_unsat (by decide) h1 h2

end Rule6Header

/-! ## 9. Rule 7: substitution

      a <- D* b x*
       b <- F* y*
    ----------------
    a <- D* F* x* y*  -/

/-- **Rule 7 (substitution), general form.** -/
theorem rule7 {rho : Assign} {a b : Var} {xs ys : List Var} {D F : Finset Label}
    (h1 : Sat rho ⟨a, b :: xs, D⟩) (h2 : Sat rho ⟨b, ys, F⟩) :
    Sat rho ⟨a, xs ++ ys, D ∪ F⟩ := by
  refine sat_append_mk (fun l => ?_) (fun v hv => ?_) (List.pairwise_cons.mp h1.pw).2 h2.pw
    (fun v hv t ht => ?_)
  · rw [h1.mem_cons l, h2.mem_iff l]
    simp only [Finset.mem_union]
    constructor
    · rintro (hD | (hF | hys) | hxs)
      · exact Or.inl (Or.inl hD)
      · exact Or.inl (Or.inr hF)
      · exact Or.inr (Or.inr hys)
      · exact Or.inr (Or.inl hxs)
    · rintro ((hD | hF) | hxs | hys)
      · exact Or.inl hD
      · exact Or.inr (Or.inl (Or.inl hF))
      · exact Or.inr (Or.inr hxs)
      · exact Or.inr (Or.inl (Or.inr hys))
  · rw [Finset.disjoint_union_left]
    rcases List.mem_append.mp hv with hv' | hv'
    · exact ⟨h1.conc_disj (by simp [hv']),
        disjoint_of_subset_left (h1.disjoint_cons_head hv') h2.conc_sub⟩
    · exact ⟨disjoint_of_subset_right (h1.conc_disj (by simp)) (h2.sub hv'),
        h2.conc_disj hv'⟩
  · exact disjoint_of_subset_right (h1.disjoint_cons_head hv).symm (h2.sub ht)

/-- Entailment form of rule 7. -/
theorem rule7_entails {a b : Var} {xs ys : List Var} {D F : Finset Label} :
    Entails [⟨a, b :: xs, D⟩, ⟨b, ys, F⟩] ⟨a, xs ++ ys, D ∪ F⟩ :=
  fun _ hm => rule7 (hm ⟨a, b :: xs, D⟩ (by simp)) (hm ⟨b, ys, F⟩ (by simp))

/-- Rule 7 at concrete arity: `a <- (D, b, x)` and `b <- (F, y)` give `a <- (D F, x, y)`. -/
theorem rule7_concrete {rho : Assign} {a b x y : Var} {D F : Finset Label}
    (h1 : Sat rho ⟨a, [b, x], D⟩) (h2 : Sat rho ⟨b, [y], F⟩) :
    Sat rho ⟨a, [x, y], D ∪ F⟩ :=
  rule7 (xs := [x]) (ys := [y]) h1 h2

/-! ## 10. Rule 8: common partition

    a <- A* x*
    b <- A* x*
    ----------
      a <- b    -/

/-- **Rule 8 (common partition), general form.**  Two identical right-hand sides force
their left-hand variables to be equal. -/
theorem rule8 {rho : Assign} {a b : Var} {xs : List Var} {A : Finset Label}
    (h1 : Sat rho ⟨a, xs, A⟩) (h2 : Sat rho ⟨b, xs, A⟩) : rho a = rho b := by
  rw [h1.eq_of, h2.eq_of]

/-- Entailment form of rule 8: `a <- b` is the constraint `⟨a, [b], ∅⟩`. -/
theorem rule8_entails {a b : Var} {xs : List Var} {A : Finset Label} :
    Entails [⟨a, xs, A⟩, ⟨b, xs, A⟩] ⟨a, [b], (∅ : Finset Label)⟩ := by
  intro rho hm
  refine sat_one_mk (fun l => ?_) (by simp)
  rw [rule8 (hm ⟨a, xs, A⟩ (by simp)) (hm ⟨b, xs, A⟩ (by simp))]
  simp

/-! ## 11. Rule 9: common subexpression -- FRESH VARIABLE

    a <- C* x++ y*
    b <- D* x++ z*
    --------------
       w <- x++     (w fresh)
     a <- C* w y*
     b <- D* w z*   -/

section CommonSubexpression

variable {a b w : Var} {xs ys zs : List Var} {C D : Finset Label}

/-- `w` really is fresh for the premises of rule 9. -/
theorem rule9_fresh (haw : a ≠ w) (hbw : b ≠ w) (hxw : w ∉ xs) (hyw : w ∉ ys)
    (hzw : w ∉ zs) : Fresh w [⟨a, xs ++ ys, C⟩, ⟨b, xs ++ zs, D⟩] := by
  intro c hc
  simp at hc
  rcases hc with rfl | rfl
  · exact ⟨haw, by simp [hxw, hyw]⟩
  · exact ⟨hbw, by simp [hxw, hzw]⟩

/-- Rewriting a bounded existential along an assignment that agrees on the list. -/
theorem exists_mem_congr {rho rho' : Assign} (h : ∀ v ∈ xs, rho v = rho' v) (l : Label) :
    (∃ v ∈ xs, l ∈ rho v) ↔ (∃ v ∈ xs, l ∈ rho' v) := by
  constructor
  · rintro ⟨v, hv, hl⟩; exact ⟨v, hv, by rw [← h v hv]; exact hl⟩
  · rintro ⟨v, hv, hl⟩; exact ⟨v, hv, by rw [h v hv]; exact hl⟩

/-- **The backward half of rule 9**: the three conclusions imply both premises.  NO
freshness hypothesis occurs here. -/
theorem rule9_back (rho : Assign)
    (hm : Models rho [⟨w, xs, (∅ : Finset Label)⟩, ⟨a, w :: ys, C⟩, ⟨b, w :: zs, D⟩]) :
    Models rho [⟨a, xs ++ ys, C⟩, ⟨b, xs ++ zs, D⟩] := by
  have g0 : Sat rho ⟨w, xs, (∅ : Finset Label)⟩ := hm _ (by simp)
  have g1 : Sat rho ⟨a, w :: ys, C⟩ := hm _ (by simp)
  have g2 : Sat rho ⟨b, w :: zs, D⟩ := hm _ (by simp)
  obtain ⟨he, hp⟩ := sat_empty_conc.mp g0
  refine models_of_two ?_ ?_
  · refine sat_append_mk (fun l => ?_) (fun v hv => ?_) hp (List.pairwise_cons.mp g1.pw).2
      (fun v hv t ht => ?_)
    · rw [g1.mem_cons l, he, mem_rowSum]
    · rcases List.mem_append.mp hv with hv' | hv'
      · exact disjoint_of_subset_right (g1.conc_disj (v := w) (by simp))
          (by rw [he]; exact subset_rowSum hv')
      · exact g1.conc_disj (by simp [hv'])
    · exact disjoint_of_subset_left (g1.disjoint_cons_head ht)
        (by rw [he]; exact subset_rowSum hv)
  · refine sat_append_mk (fun l => ?_) (fun v hv => ?_) hp (List.pairwise_cons.mp g2.pw).2
      (fun v hv t ht => ?_)
    · rw [g2.mem_cons l, he, mem_rowSum]
    · rcases List.mem_append.mp hv with hv' | hv'
      · exact disjoint_of_subset_right (g2.conc_disj (v := w) (by simp))
          (by rw [he]; exact subset_rowSum hv')
      · exact g2.conc_disj (by simp [hv'])
    · exact disjoint_of_subset_left (g2.disjoint_cons_head ht)
        (by rw [he]; exact subset_rowSum hv)

/-- **Rule 9 (common subexpression), general form, both halves.**  The freshness
hypotheses are used in the forward half only (see `rule9_back`). -/
theorem rule9 (haw : a ≠ w) (hbw : b ≠ w) (hxw : w ∉ xs) (hyw : w ∉ ys) (hzw : w ∉ zs) :
    ConservativeExt [⟨a, xs ++ ys, C⟩, ⟨b, xs ++ zs, D⟩] w
      [⟨w, xs, (∅ : Finset Label)⟩, ⟨a, w :: ys, C⟩, ⟨b, w :: zs, D⟩] := by
  constructor
  · -- forward: name the common group
    intro rho hm
    have h1 : Sat rho ⟨a, xs ++ ys, C⟩ := hm _ (by simp)
    have h2 : Sat rho ⟨b, xs ++ zs, D⟩ := hm _ (by simp)
    have ex : ∀ v ∈ xs, upd rho w (rowSum rho xs) v = rho v := upd_of_not_mem rho w _ hxw
    have ey : ∀ v ∈ ys, upd rho w (rowSum rho xs) v = rho v := upd_of_not_mem rho w _ hyw
    have ez : ∀ v ∈ zs, upd rho w (rowSum rho xs) v = rho v := upd_of_not_mem rho w _ hzw
    refine ⟨upd rho w (rowSum rho xs), upd_agrees rho w _, models_of_three ?_ ?_ ?_⟩
    · refine sat_empty_conc.mpr
        ⟨?_, pairwise_disj_congr (fun v hv => (ex v hv).symm) h1.pw_append_left⟩
      rw [upd_same, rowSum_congr ex]
    · refine sat_cons_mk (fun l => ?_) ?_ (fun v hv => ?_) (fun v hv => ?_)
        (pairwise_disj_congr (fun v hv => (ey v hv).symm) h1.pw_append_right)
      · rw [upd_ne rho _ haw, upd_same, exists_mem_congr ey l, h1.mem_append l, mem_rowSum]
      · rw [upd_same]
        exact disjoint_rowSum_right fun v hv => h1.conc_disj (by simp [hv])
      · rw [ey v hv]; exact h1.conc_disj (by simp [hv])
      · rw [upd_same, ey v hv]
        exact disjoint_rowSum_left fun t ht => h1.disjoint_append ht hv
    · refine sat_cons_mk (fun l => ?_) ?_ (fun v hv => ?_) (fun v hv => ?_)
        (pairwise_disj_congr (fun v hv => (ez v hv).symm) h2.pw_append_right)
      · rw [upd_ne rho _ hbw, upd_same, exists_mem_congr ez l, h2.mem_append l, mem_rowSum]
      · rw [upd_same]
        exact disjoint_rowSum_right fun v hv => h2.conc_disj (by simp [hv])
      · rw [ez v hv]; exact h2.conc_disj (by simp [hv])
      · rw [upd_same, ez v hv]
        exact disjoint_rowSum_left fun t ht => h2.disjoint_append ht hv
  · exact rule9_back

end CommonSubexpression

/-! ## 12. Error condition 10: a duplicated field

    a <- C* x* D D
    --------------
    a inconsistent

This is the one rule that needs the multi-block form of section 1: in the flattened form
`D D` collapses to `D`.  What it says is exactly that the extra conjunct of
`rsat_iff_flatten` -- pairwise disjointness of the concrete blocks -- can fail. -/

/-- **Error condition 10, general form.**  A concrete block occurring at least twice in a
raw right-hand side is empty; so a nonempty repeated block makes the constraint
unsatisfiable. -/
theorem rule10 {rho : Assign} {r : RawConstraint} {F : Row} (h : RSat rho r)
    (hF : 2 ≤ r.concs.count F) : F = ∅ := by
  have hc : r.concs.Pairwise Disjoint := ((rsat_iff_flatten rho r).mp h).2
  exact eq_empty_of_disjoint_self (pairwise_self_of_two_le_count hc hF)

/-- **Error condition 10 as unsatisfiability.** -/
theorem rule10_unsat {r : RawConstraint} {F : Row} (hF : F ≠ ∅) (hdup : 2 ≤ r.concs.count F) :
    ∀ rho, ¬ RSat rho r := fun _ h => hF (rule10 h hdup)

/-- Error condition 10 at the concrete shape `a <- C x D D`. -/
theorem rule10_concrete {a x : Var} {C F : Row} (hF : F ≠ ∅) (rho : Assign) :
    ¬ RSat rho ⟨a, [C, F, F], [x]⟩ := by
  intro h
  refine hF (eq_empty_of_disjoint_self ?_)
  have hc : ([C, F, F] : List Row).Pairwise Disjoint := ((rsat_iff_flatten rho _).mp h).2
  rw [List.pairwise_cons, List.pairwise_cons] at hc
  exact hc.2.1 F (by simp)

/-! ## 13. Error condition 11: incompatible fields

         a <- C* D*
         a <- D* E+ x*
    ------------------------
    C* doesn't subsume E+ x* -/

/-- **Error condition 11, general form.**  If `a` has a fully concrete partition `C`,
every other partition of `a` has its concrete part inside `C`. -/
theorem rule11 {rho : Assign} {a : Var} {xs : List Var} {C K : Finset Label}
    (h1 : Sat rho ⟨a, [], C⟩) (h2 : Sat rho ⟨a, xs, K⟩) : K ⊆ C := by
  have ha : rho a = C := (sat_zero rho a C).mp h1
  have hs : K ⊆ rho a := h2.conc_sub
  rwa [ha] at hs

/-- ... and each variable part too. -/
theorem rule11_vars {rho : Assign} {a : Var} {xs : List Var} {C K : Finset Label}
    (h1 : Sat rho ⟨a, [], C⟩) (h2 : Sat rho ⟨a, xs, K⟩) {v : Var} (hv : v ∈ xs) :
    rho v ⊆ C := by
  have ha : rho a = C := (sat_zero rho a C).mp h1
  have hs : rho v ⊆ rho a := h2.sub hv
  rwa [ha] at hs

/-- **Error condition 11 as unsatisfiability.** -/
theorem rule11_unsat {a : Var} {xs : List Var} {C K : Finset Label} (hn : ¬ K ⊆ C)
    (rho : Assign) : ¬ Models rho [⟨a, [], C⟩, ⟨a, xs, K⟩] :=
  fun hm => hn (rule11 (hm ⟨a, [], C⟩ (by simp)) (hm ⟨a, xs, K⟩ (by simp)))

/-- Error condition 11 in the header's notation: the second premise's concrete part is
`D* E+`, and it is the failure of `E+ ⊆ C*` that is detected. -/
theorem rule11_header {a : Var} {xs : List Var} {C D E : Finset Label} (hn : ¬ E ⊆ C)
    (rho : Assign) : ¬ Models rho [⟨a, [], C⟩, ⟨a, xs, D ∪ E⟩] := by
  refine rule11_unsat (fun hsub => hn ?_) rho
  exact fun l hl => hsub (Finset.mem_union_right _ hl)

/-! ## 14. Necessity of the side conditions

Two side conditions that the informal rules leave implicit, with counterexamples showing
they cannot be dropped. -/

section Necessity

/-- `a = {1,2}`, `x = {}`, `z = {2}`, `d = {1}`. -/
def rhoCancel : Assign :=
  fun v => if v = 0 then ({1, 2} : Finset Label) else if v = 1 then ∅
           else if v = 2 then {2} else {1}

/-- **Cancellation needs its shared concrete part to really be shared.**  Here
`a <- (|1|) (x, z)` and `a <- (|2|) (x, d)` both hold, but `C = {1}` is not a subset of
`K = {2}`, and the conclusion `z <- (K \ C) d` fails.  In the Scala implementation this
side condition is the guard `fs.isEmpty`, i.e. `con1 -- (con1 & con2) = {}`. -/
theorem rule5_needs_shared_conc :
    Sat rhoCancel ⟨0, [1] ++ [2], ({1} : Finset Label)⟩ ∧
      Sat rhoCancel ⟨0, [1] ++ [3], ({2} : Finset Label)⟩ ∧
      ¬ Sat rhoCancel ⟨2, [3], ({2} : Finset Label) \ {1}⟩ := by
  refine ⟨?_, ?_, ?_⟩
  · show Sat rhoCancel ⟨0, [1, 2], ({1} : Finset Label)⟩
    rw [sat_two]
    exact ⟨by decide, by decide, by decide, by decide⟩
  · show Sat rhoCancel ⟨0, [1, 3], ({2} : Finset Label)⟩
    rw [sat_two]
    exact ⟨by decide, by decide, by decide, by decide⟩
  · rw [sat_one]
    rintro ⟨h, -⟩
    revert h
    decide

/-- `a = {1,2}`, `x = y = {2}`, and the fresh variable starts empty. -/
def rhoRes : Assign :=
  fun v => if v = 0 then ({1, 2} : Finset Label) else if v = 3 then ∅ else {2}

/-- **The swapped-but-unsharpened resolution rule needs `Disjoint C E`.**  With
`C = E = (|1|)` and `D` empty the two premises are satisfiable, yet adding the
conclusion `a <- C* D* E* z, x <- E* z, y <- C* z` makes the system unsatisfiable.  The
sharp form `rule6` is unaffected, because there the conclusion carries `E \ C = {}`. -/
theorem rule6_swapped_needs_disjoint :
    (∃ rho, Models rho [⟨0, [1], ({1} : Finset Label) ∪ ∅⟩,
        ⟨0, [2], (∅ : Finset Label) ∪ {1}⟩]) ∧
      ¬ ∃ rho, Models rho [⟨0, [1], ({1} : Finset Label) ∪ ∅⟩,
          ⟨0, [2], (∅ : Finset Label) ∪ {1}⟩,
          ⟨0, [3], ({1} : Finset Label) ∪ ∅ ∪ {1}⟩,
          ⟨1, [3], ({1} : Finset Label)⟩, ⟨2, [3], ({1} : Finset Label)⟩] := by
  constructor
  · refine ⟨rhoRes, models_of_two ?_ ?_⟩ <;> rw [sat_one] <;> exact ⟨by decide, by decide⟩
  · rintro ⟨rho, hm⟩
    have h1 : Sat rho ⟨0, [1], ({1} : Finset Label) ∪ ∅⟩ := hm _ (by simp)
    have h2 : Sat rho ⟨1, [3], ({1} : Finset Label)⟩ := hm _ (by simp)
    exact Rule6Header.premise_conclusion_unsat (by decide) h1 h2

end Necessity

/-! ## 15. Summary

| rule | statement here | sound? |
| --- | --- | --- |
| 1 self-substitution | `rule1_empty`, `rule1_conc`, `rule1_unsat`, `rule1_general` | yes |
| 2 empty partition | `rule2`, `rule2_conc`, `rule2_entails` | yes |
| 3 de-duplication | `rule3`, `rule3_entails`, `rule3_concrete` | yes |
| 4 split concrete | `rule4` (`ConservativeExt`), `rule4_back`, `rule4_concrete` | yes |
| 5 cancellation | `rule5`, `rule5_header`, `rule5_concrete`, `rule5_entails` | yes, given `C ⊆ K` |
| 6 resolution | `rule6` (`ConservativeExt`), `rule6_back`, `rule6_swapped` | see below |
| 7 substitution | `rule7`, `rule7_entails`, `rule7_concrete` | yes |
| 8 common partition | `rule8`, `rule8_entails` | yes |
| 9 common subexpression | `rule9` (`ConservativeExt`), `rule9_back` | yes |
| 10 duplicated field | `rule10`, `rule10_unsat`, `rule10_concrete` | yes (needs `RawConstraint`) |
| 11 incompatible fields | `rule11`, `rule11_vars`, `rule11_unsat`, `rule11_header` | yes |

Rule 6 is the interesting one.  As literally written in the header comment it is
UNSOUND (`Rule6Header.header_not_conservative`, `Rule6Header.header_makes_unsat`): it
pairs each lone variable with the concrete part of its own premise, where it must be
paired with the other premise's.  Swapping them repairs the rule provided `C` and `E`
are disjoint (`rule6_swapped`; the disjointness is genuinely needed, see
`rule6_swapped_needs_disjoint`, and the header's convention 8 does declare distinct
named sequences disjoint).  The Scala implementation is sound without that proviso: it
subtracts the shared fields, deriving `x <- (E \ C) z` and `y <- (C \ E) z`, which is
`rule6`. -/

end Rowpartition
