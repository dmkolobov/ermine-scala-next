/-
# The bridge to Pottier's constraint language

Pottier, *A Constraint-Based Presentation and Generalization of Rows* (LICS 2003),
solves the record-concatenation problem WITHOUT a row-extension term and WITHOUT ever
allocating a fresh row variable.  Ermine solves what looks like the same problem with a
single primitive, PARTITION.  This file asks the mechanical question:

> **is Pottier's symmetric-concatenation constraint the same relation as Ermine's binary
> partition?**

and answers YES, exactly (`bridge`), together with a precise account of where the two
systems come apart.

## What is specialised, and why

Pottier's framework (Definition 2) is parameterised by a finite LATTICE of symbols per
kind.  Example 1 instantiates the field kind with the flat lattice
`{⊥_field, Abs, Pre, ⊤_field}` and gives `Pre` a type argument (`a(Pre) = {content}`).
Ermine differs in exactly two ways, and both are forced by the language:

* an Ermine row is a SET OF LABELS -- field types are declared globally and must be
  primitive -- so Pottier's `Pre τ` degenerates to a bare presence bit.  Definition 3
  makes a ground row a TOTAL family indexed by all of `𝓛`; with a two-element,
  argument-free field algebra that family is exactly a presence predicate
  `Label → Bool`, which is `PRow` below;
* Ermine has NO SUBTYPING.  `Abs` and `Pre` are deliberately incomparable in Pottier
  ("because that is required to assign a sound type to record concatenation"), so on the
  two-element subset `{Abs, Pre}` the induced order is the DISCRETE one -- which is
  equality.  `SymLe` below is therefore `Eq`, and section 12 collects the consequences:
  Pottier's Theorem 1 (every model is a lattice) fails outright, and the join-of-lower-
  bounds witness of his Theorem 4 degenerates to the everywhere-absent assignment.

## Contents

1.  presence symbols: `Abs`, `Pre`, `SymLe`, and the failure of the lattice property;
2.  ground rows and assignments (Definitions 3, 5);
3.  FILTERS (§2.3) as a finite-or-cofinite label set, with the Boolean algebra and
    Pottier's "apparent" labels (Definition 8);
4.  row terms `ρ ::= α | ∂φ` and the two filtered constraint forms, with Figure 3's
    satisfaction judgement quoted verbatim;
5.  symmetric concatenation (§4), quoted verbatim, and its per-label reading;
6.  **THE BRIDGE**: `bridge`, both inclusions;
7.  sharpness: the relation is symmetric in the two ARGUMENTS but not in the RESULT;
8.  the n-ary case, as a chain of binary concatenations, at bit level and at row level;
9.  the concrete part of an Ermine constraint IS a Pottier filter;
10. the whole-system corollary, via `sat_iff_forall_label`;
11. a NEGATIVE result: the TERNARY Ermine partition is not expressible by Pottier
    constraints over its own four variables -- intermediates are unavoidable;
12. where subtyping is essential: Pottier's join-of-lower-bounds witness degenerates;
13. a second negative result: with the REAL field lattice in place, the three
    constraints do not determine the result at all, so the bridge's exactness is a
    consequence of dropping subtyping and not something inherited from the paper;
14. non-vacuity checks.

Nothing here is admitted: no `sorry`, no `axiom`, no `native_decide`.
-/
import Rowpartition.Basic
import Rowpartition.Fragment
import Mathlib.Data.Finset.Lattice.Fold

namespace Rowpartition
namespace Pottier

/-! ## 1. Presence symbols: `𝒮_field` cut down to `{Abs, Pre}`

Example 1 of the paper: "Let `𝒮_field` be the flat lattice whose elements other than
`⊥_field` and `⊤_field` are `Abs` and `Pre`. … `a(Pre) = {content}`".  Ermine has no
field types, so `a(Pre) = ∅`; and an Ermine row label is either present or absent, never
`⊥` or `⊤`.  What survives is the two-element ANTICHAIN `{Abs, Pre}`, which we encode as
`Bool` with `Pre = true`. -/

/-- Pottier's `Abs`. -/
abbrev Abs : Bool := false

/-- Pottier's `Pre`, stripped of its type argument. -/
abbrev Pre : Bool := true

/-- Pottier's `≤_field`, restricted to `{Abs, Pre}`.

`Abs` and `Pre` are incomparable in `𝒮_field`, so the order induced on the subset
`{Abs, Pre}` is the discrete order, i.e. EQUALITY.  This single definition is where
"Ermine has no subtyping" enters the formalisation; everything downstream is a theorem
about it. -/
def SymLe (x y : Bool) : Prop := x = y

theorem symLe_iff (x y : Bool) : SymLe x y ↔ x = y := Iff.rfl

theorem symLe_refl (x : Bool) : SymLe x x := rfl

/-- The specialised order is SYMMETRIC.  In Pottier's system `τ₁ ≤ τ₂` and `τ₂ ≤ τ₁` are
different constraints; here they are the same one.  Consequently "lower bound" and
"upper bound" are not distinguishable notions -- see section 12. -/
theorem symLe_symm {x y : Bool} (h : SymLe x y) : SymLe y x := h.symm

/-- **Pottier's Theorem 1 fails in the Ermine specialisation.**  `Theorem 1  Every
`(𝕋^ς_κ, ≤^ς_κ)` forms a lattice.`  Here `Abs` and `Pre` have no common upper bound at
all, so the specialised model is not even a join-semilattice.  Theorem 1 is invoked BY
NAME inside the proof of Theorem 4 to supply the least upper bounds out of which the
canonical witness is built; this lemma is why that proof strategy cannot be transported. -/
theorem no_upper_bound : ¬ ∃ z : Bool, SymLe Abs z ∧ SymLe Pre z := by
  rintro ⟨z, h1, h2⟩
  rw [symLe_iff] at h1 h2
  exact Bool.noConfusion (h1.trans h2.symm)

/-! ## 2. Ground rows and ground assignments (Definitions 3 and 5)

```
Definition 3  The family of models 𝕋^ς_κ is the greatest solution to the following
equations:
  𝕋^Type_κ = {s(t̄_p) ; s ∈ 𝒮_κ ∧ ∀p ∈ a(s)  t_p ∈ 𝕋^{sort(p)}_{kind(p)}}
  𝕋^Row_κ = {(t̄_ℓ) ; ∀ℓ ∈ 𝓛  t_ℓ ∈ 𝕋^Type_κ}
```
A ground row is a TOTAL family indexed by every label; absence is the VALUE `Abs` at
that label, not the omission of the label.  With `𝒮_field = {Abs, Pre}` and `a(Pre) = ∅`
the family collapses to a presence predicate.

```
Definition 5  A ground assignment φ is a total sort- and kind-preserving mapping from
the variables into the model.
```
-/

/-- A ground row of sort `Row`, kind `field`, Ermine-specialised (Definition 3). -/
abbrev PRow := Label → Bool

/-- A ground assignment, restricted to row variables (Definition 5). -/
abbrev PAssign := Var → PRow

/-- Definition 4, row clause: `(t̄_ℓ) ≤^Row (t̄′_ℓ) ⟺ ∀ℓ ∈ 𝓛, t_ℓ ≤^Type t′_ℓ`.  Rows are
compared POINTWISE; a filtered constraint restricts the quantifier to the filter. -/
def RowLe (r₁ r₂ : PRow) : Prop := ∀ l, SymLe (r₁ l) (r₂ l)

/-- The Ermine row assignment `rho`, read as a Pottier ground assignment.  A finite label
set becomes its characteristic function -- which is precisely `Basic.proj`, transposed. -/
def toPAssign (rho : Assign) : PAssign := fun v l => decide (l ∈ rho v)

theorem toPAssign_apply (rho : Assign) (v : Var) (l : Label) :
    toPAssign rho v l = proj rho l v := rfl

/-! ## 3. Filters (§2.3)

```
Let a filter L be a finite or cofinite subset of 𝓛.  Filters are machine representable
and are preserved by finitary union, intersection, and complement.
```

REPRESENTATION CHOICE.  We use a two-constructor inductive type carrying a `Finset
Label` -- definitionally `Finset Label ⊕ Finset Label`, with named constructors for
legibility.  The alternative, a predicate `Label → Prop` bundled with a proof that it is
finite or cofinite, was rejected: every Boolean operation would then have to combine
those proofs, and nothing anywhere in this file needs a filter's finiteness as a
*hypothesis*.  With the inductive representation, membership is DECIDABLE by
computation, `union`/`inter`/`compl` are total computable functions, `𝓛` and `∅` are
literals, and every proof is a two-way case split followed by ordinary `Finset`
reasoning.  That is exactly Pottier's own justification ("machine representable"). -/

/-- A filter: a finite or cofinite set of row labels. -/
inductive Filter' where
  /-- The finite filter `S`. -/
  | fin (S : Finset Label)
  /-- The cofinite filter `𝓛 \ S`. -/
  | cofin (S : Finset Label)
  deriving DecidableEq

namespace Filter'

/-- Membership in a filter. -/
def mem : Filter' → Label → Prop
  | .fin S, l => l ∈ S
  | .cofin S, l => l ∉ S

instance : ∀ (L : Filter') (l : Label), Decidable (L.mem l)
  | .fin S, l => inferInstanceAs (Decidable (l ∈ S))
  | .cofin S, l => inferInstanceAs (Decidable (l ∉ S))

/-- The full filter `𝓛`. -/
def full : Filter' := .cofin ∅

/-- The empty filter. -/
def empty : Filter' := .fin ∅

@[simp] theorem mem_full (l : Label) : full.mem l := by simp [full, mem]

@[simp] theorem mem_empty (l : Label) : ¬ empty.mem l := by simp [empty, mem]

@[simp] theorem mem_fin (S : Finset Label) (l : Label) : (Filter'.fin S).mem l ↔ l ∈ S :=
  Iff.rfl

@[simp] theorem mem_cofin (S : Finset Label) (l : Label) :
    (Filter'.cofin S).mem l ↔ l ∉ S := Iff.rfl

/-- Complement. -/
def compl : Filter' → Filter'
  | .fin S => .cofin S
  | .cofin S => .fin S

/-- Union. -/
def union : Filter' → Filter' → Filter'
  | .fin S, .fin T => .fin (S ∪ T)
  | .fin S, .cofin T => .cofin (T \ S)
  | .cofin S, .fin T => .cofin (S \ T)
  | .cofin S, .cofin T => .cofin (S ∩ T)

/-- Intersection. -/
def inter : Filter' → Filter' → Filter'
  | .fin S, .fin T => .fin (S ∩ T)
  | .fin S, .cofin T => .fin (S \ T)
  | .cofin S, .fin T => .fin (T \ S)
  | .cofin S, .cofin T => .cofin (S ∪ T)

@[simp] theorem mem_compl (L : Filter') (l : Label) : L.compl.mem l ↔ ¬ L.mem l := by
  cases L <;> simp [compl, mem]

@[simp] theorem mem_union (L₁ L₂ : Filter') (l : Label) :
    (L₁.union L₂).mem l ↔ L₁.mem l ∨ L₂.mem l := by
  cases L₁ <;> cases L₂ <;>
    simp [union, mem, Finset.mem_sdiff, Finset.mem_inter, Finset.mem_union] <;> tauto

@[simp] theorem mem_inter (L₁ L₂ : Filter') (l : Label) :
    (L₁.inter L₂).mem l ↔ L₁.mem l ∧ L₂.mem l := by
  cases L₁ <;> cases L₂ <;>
    simp [inter, mem, Finset.mem_sdiff, Finset.mem_inter, Finset.mem_union]
  tauto

/-- Filters are Boolean-closed and have a decidable emptiness test -- which §5 of the
paper identifies as the ONLY properties the development (bar the complexity analysis)
uses.  Emptiness: a finite filter is empty iff its payload is; a cofinite one never is,
because `𝓛` is infinite. -/
theorem exists_mem_cofin (S : Finset Label) : ∃ l, (Filter'.cofin S).mem l := by
  refine ⟨S.sup id + 1, fun h => ?_⟩
  have h2 : S.sup id + 1 ≤ S.sup id := Finset.le_sup (f := id) h
  exact absurd h2 (Nat.not_succ_le_self _)

/-- Pottier's *apparent* labels (Definition 8): "a row label `ℓ` is apparent in a set `L`
iff either `L` is finite and `ℓ ∈ L`, or `L` is cofinite and `ℓ ∉ L`".  In this
representation that is exactly the payload finset. -/
def apparent : Filter' → Finset Label
  | .fin S => S
  | .cofin S => S

@[simp] theorem apparent_fin (S : Finset Label) : (Filter'.fin S).apparent = S := rfl

@[simp] theorem apparent_cofin (S : Finset Label) : (Filter'.cofin S).apparent = S := rfl

/-- Definition 8, first disjunct: a FINITE filter's apparent labels are its members. -/
theorem mem_apparent_fin (S : Finset Label) (l : Label) :
    l ∈ (Filter'.fin S).apparent ↔ (Filter'.fin S).mem l := Iff.rfl

/-- Definition 8, second disjunct: a COFINITE filter's apparent labels are its
NON-members.  So "apparent" is not "belongs to"; it is "explicitly mentioned". -/
theorem mem_apparent_cofin (S : Finset Label) (l : Label) :
    l ∈ (Filter'.cofin S).apparent ↔ ¬ (Filter'.cofin S).mem l := by
  simp

/-- **No rule makes new row labels apparent** (the finiteness invariant behind Theorem 2
and behind the parameter `m` of Theorem 7): the labels apparent in a union are among
those apparent in the operands. -/
theorem apparent_union_subset (L₁ L₂ : Filter') :
    (L₁.union L₂).apparent ⊆ L₁.apparent ∪ L₂.apparent := by
  cases L₁ <;> cases L₂ <;>
    simp only [union, apparent_fin, apparent_cofin] <;>
    intro l hl <;>
    simp_all [Finset.mem_sdiff, Finset.mem_inter, Finset.mem_union]

/-- The same for intersection, which is what (TRANS-ROW) propagates through. -/
theorem apparent_inter_subset (L₁ L₂ : Filter') :
    (L₁.inter L₂).apparent ⊆ L₁.apparent ∪ L₂.apparent := by
  cases L₁ <;> cases L₂ <;>
    simp only [inter, apparent_fin, apparent_cofin] <;>
    intro l hl <;>
    simp_all [Finset.mem_sdiff, Finset.mem_inter, Finset.mem_union]

/-- A transcription-level caveat, made precise.  The paper says "the row labels apparent
in `L₁ ∪ L₂` **are those** apparent in `L₁` or `L₂`", which reads as an equality; only
the inclusion `apparent_union_subset` is true, and only the inclusion is needed (nothing
must become apparent that was not).  Here is the failure of equality: `{1} ∪ 𝓛\{1,2}` is
`𝓛\{2}`, in which `1` is no longer apparent. -/
theorem apparent_union_ne :
    ¬ ∀ L₁ L₂ : Filter', (L₁.union L₂).apparent = L₁.apparent ∪ L₂.apparent := by
  intro h
  have := h (.fin {1}) (.cofin {1, 2})
  simp only [union, apparent_fin, apparent_cofin] at this
  have h1 : (1 : Label) ∈ ({1} : Finset Label) ∪ ({1, 2} : Finset Label) := by decide
  rw [← this] at h1
  simp [Finset.mem_sdiff] at h1

end Filter'

/-! ## 4. Terms and constraints

The grammar of §2.3, specialised.  Row terms are `ρ ::= α | ∂φ`: **there is no
`(ℓ : τ ; ρ)` constructor at all** -- that is the move that removes the need for fresh
"rest of the row" variables.  Definition 6 interprets `∂τ` as the CONSTANT row:
"`φ(∂τ) = (φ(τ))‾` … the row that maps every row label to `φ(τ)`."  With field types
gone, `φ` above is just a presence symbol, so `∂Abs` is the empty record's row and
`∂Pre` the everywhere-present one. -/

/-- A row term: a variable, or Rémy's constant row `∂s`. -/
inductive RowTerm where
  /-- A row variable `α`. -/
  | var (a : Var)
  /-- The constant row `∂s`. -/
  | const (s : Bool)
  deriving DecidableEq

/-- Definition 6, extended to terms. -/
def RowTerm.eval (ψ : PAssign) : RowTerm → PRow
  | .var a => ψ a
  | .const s => fun _ => s

@[simp] theorem RowTerm.eval_var (ψ : PAssign) (a : Var) :
    (RowTerm.var a).eval ψ = ψ a := rfl

@[simp] theorem RowTerm.eval_const (ψ : PAssign) (s : Bool) (l : Label) :
    (RowTerm.const s).eval ψ l = s := rfl

/-- The two filtered constraint forms of the grammar

```
C ::= ∃α.C | C ∧ C | true | false | τ ≤ τ | L : τ ≤ τ | L : s ≤ τ ? τ ≤ τ
```

that mention rows.  (The unfiltered form `τ₁ ≤ τ₂` on *types* is redundant: "`τ₁ ≤ τ₂`
and `L : ∂τ₁ ≤ ∂τ₂` are logically equivalent when `L` is nonempty".  Conjunction is a
list, and neither `∃` nor `false` is needed for the bridge.) -/
inductive PConstr where
  /-- `L : τ₁ ≤ τ₂`. -/
  | sub (L : Filter') (t₁ t₂ : RowTerm)
  /-- `L : s ≤ τ₀ ? τ₁ ≤ τ₂`.  Figure 2 requires the condition symbol `s` to be a PRIME
  (join-irreducible) element of `𝒮_κ`.  In the two-element antichain every element is
  vacuously prime, so the side condition is discharged for both `Abs` and `Pre`. -/
  | cond (L : Filter') (s : Bool) (t₀ t₁ t₂ : RowTerm)
  deriving DecidableEq

/-- **Figure 3, "Constraint satisfaction"** (premises above the line):

```
φ(τ₁) ≤ φ(τ₂) / φ ⊢ τ₁ ≤ τ₂        ∀ℓ ∈ L   φ(τ₁).ℓ ≤ φ(τ₂).ℓ / φ ⊢ L : τ₁ ≤ τ₂

∀ℓ ∈ L   s ≤ φ(τ₀).ℓ ⇒ φ(τ₁).ℓ ≤ φ(τ₂).ℓ / φ ⊢ L : s ≤ τ₀ ? τ₁ ≤ τ₂
```

Note that in the conditional form the label quantification and the case analysis are
INTERLEAVED: the implication is per-label, inside the filter. -/
def PSat (ψ : PAssign) : PConstr → Prop
  | .sub L t₁ t₂ => ∀ l, L.mem l → SymLe (t₁.eval ψ l) (t₂.eval ψ l)
  | .cond L s t₀ t₁ t₂ =>
      ∀ l, L.mem l → SymLe s (t₀.eval ψ l) → SymLe (t₁.eval ψ l) (t₂.eval ψ l)

/-- The unfiltered comparison is the full-filter one: `𝓛 : τ₁ ≤ τ₂` is exactly
Definition 4's pointwise `≤^Row`.  (§2.4: "`τ₁ ≤ τ₂` and `L : ∂τ₁ ≤ ∂τ₂` are logically
equivalent when `L` is nonempty".) -/
theorem psat_sub_full (ψ : PAssign) (t₁ t₂ : RowTerm) :
    PSat ψ (.sub .full t₁ t₂) ↔ RowLe (t₁.eval ψ) (t₂.eval ψ) := by
  constructor
  · intro h l; exact h l (Filter'.mem_full l)
  · intro h l _; exact h l

/-- Satisfaction of a conjunction. -/
def PModels (ψ : PAssign) (C : List PConstr) : Prop := ∀ κ ∈ C, PSat ψ κ

theorem pmodels_cons {ψ : PAssign} {κ : PConstr} {C : List PConstr} :
    PModels ψ (κ :: C) ↔ PSat ψ κ ∧ PModels ψ C := by
  constructor
  · intro h; exact ⟨h κ (by simp), fun d hd => h d (by simp [hd])⟩
  · rintro ⟨hκ, hC⟩ d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hκ
    · exact hC d hd'

theorem pmodels_append {ψ : PAssign} {C D : List PConstr} :
    PModels ψ (C ++ D) ↔ PModels ψ C ∧ PModels ψ D := by
  constructor
  · intro h; exact ⟨fun κ hκ => h κ (by simp [hκ]), fun κ hκ => h κ (by simp [hκ])⟩
  · rintro ⟨hC, hD⟩ κ hκ
    rcases List.mem_append.mp hκ with h | h
    · exact hC κ h
    · exact hD κ h

/-! ## 5. Symmetric record concatenation (§4)

```
Symmetric concatenation (+) has type

  ∀φ₁φ₂φ₃[ 𝓛 : Abs ≤ φ₁ ? φ₂ ≤ φ₃
         ∧ 𝓛 : Abs ≤ φ₂ ? φ₁ ≤ φ₃
         ∧ 𝓛 : Pre ≤ φ₁ ? φ₂ ≤ Abs].
           {φ₁} → {φ₂} → {φ₃}

The first two constraints encode the semantics of record concatenation: if a field is
missing from one argument, it is read from the other.  The third constraint prevents a
field from being present in both arguments at once.  All constraints carry the full
filter 𝓛, because concatenation behaves uniformly with respect to all field labels.
```

ARGUMENT ORDER.  The type is `{φ₁} → {φ₂} → {φ₃}`, so `φ₁` and `φ₂` are the two
ARGUMENT rows and `φ₃` is the RESULT row.  Ermine's `a <- (x, y)` puts the RESULT on the
left: `a` is the row being partitioned.  The correspondence is therefore

    φ₁ ↦ x     φ₂ ↦ y     φ₃ ↦ a

and `concatSystem` below takes its arguments in Pottier's order `(arg₁, arg₂, result)`.
In the third constraint `Abs` occurs in a row position, so it abbreviates the constant
row `∂Abs` (compare "the empty record has type `{∂Abs}`"). -/

/-- Pottier's three conditional constraints for symmetric concatenation, on
`(arg₁, arg₂, result)`. -/
def concatSystem (f₁ f₂ f₃ : Var) : List PConstr :=
  [ .cond .full Abs (.var f₁) (.var f₂) (.var f₃),
    .cond .full Abs (.var f₂) (.var f₁) (.var f₃),
    .cond .full Pre (.var f₁) (.var f₂) (.const Abs) ]

/-- The per-label reading of the three constraints, on the bits
`(arg₁, arg₂, result) = (p, q, r)`:

* `Abs ≤ φ₁ ? φ₂ ≤ φ₃`  reads  `p = Abs → q = r`;
* `Abs ≤ φ₂ ? φ₁ ≤ φ₃`  reads  `q = Abs → p = r`;
* `Pre ≤ φ₁ ? φ₂ ≤ ∂Abs` reads `p = Pre → q = Abs`. -/
def PottierConcatBit (p q r : Bool) : Prop :=
  (SymLe Abs p → SymLe q r) ∧ (SymLe Abs q → SymLe p r) ∧ (SymLe Pre p → SymLe q Abs)

/-- The three constraints, applied to a single-label bit vector `b`, on the variables
`(arg₁, arg₂, result) = (x, y, a)`. -/
def PottierConcat (b : Var → Bool) (x y a : Var) : Prop :=
  PottierConcatBit (b x) (b y) (b a)

/-- `concatSystem` is satisfied exactly when its per-label reading holds at every label.
This is the content of Figure 3 for a full filter; it is where the "∀ℓ ∈ 𝓛" of the
scheme is discharged. -/
theorem pmodels_concatSystem (ψ : PAssign) (f₁ f₂ f₃ : Var) :
    PModels ψ (concatSystem f₁ f₂ f₃) ↔
      ∀ l, PottierConcatBit (ψ f₁ l) (ψ f₂ l) (ψ f₃ l) := by
  simp only [concatSystem, pmodels_cons, PottierConcatBit, PSat, RowTerm.eval_var,
    RowTerm.eval_const, Filter'.mem_full, forall_const]
  constructor
  · rintro ⟨h1, h2, h3, -⟩ l
    exact ⟨h1 l, h2 l, h3 l⟩
  · intro h
    refine ⟨fun l => (h l).1, fun l => (h l).2.1, fun l => (h l).2.2, ?_⟩
    intro κ hκ
    simp at hκ

/-! ## 6. THE BRIDGE

Ermine's binary partition with empty concrete part is `a <- (x, y)`, i.e. the constraint
`⟨a, [x, y], ∅⟩`, whose per-label Boolean shadow is `BSat`. -/

/-- The per-label reading of Ermine's binary partition: the result bit is the OR of the
argument bits, and the argument bits are not both set. -/
def ErmineConcatBit (p q r : Bool) : Prop := r = (p || q) ∧ ¬(p = true ∧ q = true)

/-- `BSat` at a binary, concrete-free constraint, unfolded.  The head of `bparts` is
`decide (l ∈ ∅) = false`, which contributes nothing to either conjunct. -/
theorem bsat_binary (b : Var → Bool) (l : Label) (a x y : Var) :
    BSat b l ⟨a, [x, y], ∅⟩ ↔ ErmineConcatBit (b x) (b y) (b a) := by
  simp only [BSat, bparts, ErmineConcatBit, List.map_cons, List.map_nil, List.foldr_cons,
    List.foldr_nil, List.pairwise_cons, List.mem_cons, List.not_mem_nil,
    Finset.notMem_empty, decide_false, Bool.false_or, Bool.or_false, List.Pairwise.nil,
    and_true, or_false, IsEmpty.forall_iff, forall_eq]
  tauto

/-- The two per-label relations are the same relation on bits. -/
theorem ermineConcatBit_iff_pottier (p q r : Bool) :
    ErmineConcatBit p q r ↔ PottierConcatBit p q r := by
  cases p <;> cases q <;> cases r <;>
    simp [ErmineConcatBit, PottierConcatBit, SymLe]

/-- **THE BRIDGE.**  Pottier's symmetric-concatenation constraint and Ermine's binary
partition are the same relation, label by label.

`⟨a, [x, y], ∅⟩` is Ermine's `a <- (x, y)`: `a` is the LEFT-HAND SIDE, i.e. the row being
partitioned, and `x`, `y` are the two parts.  `PottierConcat b x y a` puts `x` and `y` in
Pottier's ARGUMENT positions `φ₁`, `φ₂` and `a` in his RESULT position `φ₃`, matching
`{φ₁} → {φ₂} → {φ₃}`. -/
theorem bridge (b : Var → Bool) (l : Label) (a x y : Var) :
    BSat b l ⟨a, [x, y], ∅⟩ ↔ PottierConcat b x y a :=
  (bsat_binary b l a x y).trans (ermineConcatBit_iff_pottier _ _ _)

/-- The row-level form of the bridge: an Ermine assignment satisfies the binary partition
iff, read as a Pottier ground assignment, it satisfies the concatenation scheme.  This is
`sat_iff_forall_label` composed with `bridge`. -/
theorem sat_iff_pmodels_concatSystem (rho : Assign) (a x y : Var) :
    Sat rho ⟨a, [x, y], ∅⟩ ↔ PModels (toPAssign rho) (concatSystem x y a) := by
  rw [sat_iff_forall_label, pmodels_concatSystem]
  exact forall_congr' fun l => bridge (proj rho l) l a x y


/-! ## 7. Sharpness of the bridge: which positions matter

The relation is SYMMETRIC in Pottier's two argument positions `φ₁`, `φ₂` -- which is why
the scheme gets away with a single disjointness constraint (`𝓛 : Pre ≤ φ₁ ? φ₂ ≤ Abs`)
rather than two.  It is NOT symmetric in the result position, so the bridge really does
pin down which variable is Ermine's left-hand side. -/

/-- Swapping the two ARGUMENTS is invisible: `Pre ≤ φ₁ ? φ₂ ≤ Abs` already says
`¬(φ₁ = Pre ∧ φ₂ = Pre)`, which is symmetric. -/
theorem pottierConcatBit_comm (p q r : Bool) :
    PottierConcatBit p q r ↔ PottierConcatBit q p r := by
  cases p <;> cases q <;> cases r <;> simp [PottierConcatBit, SymLe]

theorem pottierConcat_comm (b : Var → Bool) (x y a : Var) :
    PottierConcat b x y a ↔ PottierConcat b y x a :=
  pottierConcatBit_comm _ _ _

/-- Swapping an ARGUMENT with the RESULT is visible.  Take `x` present, `y` absent, `a`
present: Ermine's `a <- (x, y)` holds at that label, but reading `a` as an argument and
`y` as the result makes `a` and `x` both `Pre`, which the third constraint forbids.  So
`bridge` would be FALSE with the positions permuted -- the argument order in
`PottierConcat` is load-bearing. -/
theorem bridge_result_position_sharp :
    ∃ (b : Var → Bool) (l : Label) (a x y : Var),
      BSat b l ⟨a, [x, y], ∅⟩ ∧ ¬ PottierConcat b a x y := by
  refine ⟨fun v => if v = 2 then false else true, 0, 0, 1, 2, ?_, ?_⟩
  · rw [bsat_binary]
    exact ⟨rfl, by simp⟩
  · rintro ⟨-, -, h3⟩
    exact Bool.noConfusion (h3 rfl)

/-! ## 8. The n-ary case: a chain of binary concatenations

Ermine's `a <- (b₁, …, bₙ)` is n-ary in one step.  Pottier's `+` is binary, so the n-ary
constraint arises from a nest of concatenations `b₁ + (b₂ + (⋯ + {}))`, each step
carrying its own instance of the scheme and its own INTERMEDIATE row variable; the empty
record at the bottom is `{∂Abs}`.  The intermediates are existentially quantified, and at
a single label an existentially quantified row variable contributes exactly one
existentially quantified bit.  That is `PChainBit`.  Both the bit-level and the row-level
chains are proved equal to the flat Ermine relation. -/

/-- The flat Ermine relation on part-bits (this is literally `BSat`, with the parts
abstracted). -/
def ErmineFlatBit (ps : List Bool) (r : Bool) : Prop :=
  r = ps.foldr (· || ·) false ∧ ps.Pairwise (fun x y => ¬(x = true ∧ y = true))

theorem bsat_iff_flatBit (b : Var → Bool) (l : Label) (c : Constraint) :
    BSat b l c ↔ ErmineFlatBit (bparts b l c) (b c.lhs) := Iff.rfl

/-- A part known ABSENT at this label contributes nothing. -/
theorem flatBit_false_cons (ps : List Bool) (r : Bool) :
    ErmineFlatBit (false :: ps) r ↔ ErmineFlatBit ps r := by
  simp only [ErmineFlatBit, List.foldr_cons, Bool.false_or, List.pairwise_cons]
  constructor
  · rintro ⟨h1, -, h3⟩
    exact ⟨h1, h3⟩
  · rintro ⟨h1, h2⟩
    exact ⟨h1, fun q _ hq => Bool.noConfusion hq.1, h2⟩

/-- A part known PRESENT at this label forces the left-hand side present and every other
part absent. -/
theorem flatBit_true_cons (ps : List Bool) (r : Bool) :
    ErmineFlatBit (true :: ps) r ↔ r = true ∧ ∀ q ∈ ps, q = false := by
  simp only [ErmineFlatBit, List.foldr_cons, Bool.true_or, List.pairwise_cons]
  constructor
  · rintro ⟨hr, hp, -⟩
    refine ⟨hr, fun q hq => ?_⟩
    by_contra hne
    exact hp q hq ⟨trivial, by simpa using hne⟩
  · rintro ⟨hr, hall⟩
    refine ⟨hr, fun q hq h2 => ?_, ?_⟩
    · rw [hall q hq] at h2
      exact Bool.noConfusion h2.2
    · refine pairwise_of_forall_mem fun q hq q' hq' => ?_
      rw [hall q hq]
      rintro ⟨h, -⟩
      exact Bool.noConfusion h

/-- Disjointness from a whole union is disjointness from each part. -/
theorem not_and_foldr_or (p : Bool) (ps : List Bool) :
    ¬(p = true ∧ ps.foldr (· || ·) false = true) ↔ ∀ q ∈ ps, ¬(p = true ∧ q = true) := by
  constructor
  · rintro h q hq ⟨hp, hq'⟩
    exact h ⟨hp, (foldr_or_eq_true ps).mpr ⟨q, hq, hq'⟩⟩
  · rintro h ⟨hp, hf⟩
    obtain ⟨q, hq, hq'⟩ := (foldr_or_eq_true ps).mp hf
    exact h q hq ⟨hp, hq'⟩

/-- The right-nested chain of Pottier concatenations, at one label:
`a <- (b₁, t₁)`, `t₁ <- (b₂, t₂)`, …, `t_{n-1} <- (bₙ, t_n)`, `t_n = ∂Abs`. -/
def PChainBit : List Bool → Bool → Prop
  | [], r => SymLe r Abs
  | p :: ps, r => ∃ t, PChainBit ps t ∧ PottierConcatBit p t r

/-- **The n-ary bridge, at bit level.**  The chain of binary Pottier concatenations,
with its intermediates existentially quantified, is exactly Ermine's flat n-ary
partition. -/
theorem pchainBit_iff_flat (ps : List Bool) (r : Bool) :
    PChainBit ps r ↔ ErmineFlatBit ps r := by
  induction ps generalizing r with
  | nil => simp [PChainBit, ErmineFlatBit, SymLe]
  | cons p ps ih =>
    rw [PChainBit]
    constructor
    · rintro ⟨t, ht, hc⟩
      rw [← ermineConcatBit_iff_pottier] at hc
      obtain ⟨ht1, ht2⟩ := (ih t).mp ht
      obtain ⟨hr, hd⟩ := hc
      refine ⟨by rw [hr, ht1]; rfl, List.pairwise_cons.mpr ⟨?_, ht2⟩⟩
      rw [ht1] at hd
      exact (not_and_foldr_or p ps).mp hd
    · rintro ⟨hr, hd⟩
      rw [List.pairwise_cons] at hd
      refine ⟨ps.foldr (· || ·) false, (ih _).mpr ⟨rfl, hd.2⟩, ?_⟩
      rw [← ermineConcatBit_iff_pottier]
      exact ⟨hr, (not_and_foldr_or p ps).mpr hd.1⟩

/-- A one-element chain: the single part must equal the whole. -/
theorem pchainBit_singleton (p r : Bool) : PChainBit [p] r ↔ r = p := by
  rw [pchainBit_iff_flat]
  simp [ErmineFlatBit]

/-- A two-element chain is one Pottier concatenation, no intermediate needed. -/
theorem pchainBit_pair (p q r : Bool) : PChainBit [p, q] r ↔ PottierConcatBit p q r := by
  rw [pchainBit_iff_flat, ← ermineConcatBit_iff_pottier]
  simp [ErmineFlatBit, ErmineConcatBit]

/-- The n-ary bridge, phrased on an Ermine constraint with an empty concrete part. -/
theorem bsat_iff_pchainBit (b : Var → Bool) (l : Label) (a : Var) (vs : List Var) :
    BSat b l ⟨a, vs, ∅⟩ ↔ PChainBit (vs.map b) (b a) := by
  rw [bsat_iff_flatBit, pchainBit_iff_flat]
  have : bparts b l ⟨a, vs, ∅⟩ = false :: vs.map b := by
    simp [bparts]
  rw [this, flatBit_false_cons]

/-- **Exactly one intermediate suffices for the ternary case**: `a <- (x, y, z)` is
`t <- (y, z)` followed by `a <- (x, t)`, two instances of Pottier's scheme.  Read
together with `ternary_not_definable` (section 11), this pins the cost of the encoding
down: ZERO intermediates is impossible, ONE is enough. -/
theorem ternary_via_one_intermediate (b : Var → Bool) (l : Label) (a x y z : Var) :
    BSat b l ⟨a, [x, y, z], ∅⟩ ↔
      ∃ t : Bool, PottierConcatBit (b y) (b z) t ∧ PottierConcatBit (b x) t (b a) := by
  rw [bsat_iff_pchainBit]
  simp only [List.map_cons, List.map_nil]
  rw [PChainBit]
  exact exists_congr fun t => and_congr_left' (pchainBit_pair _ _ _)

/-! ### The same, at row level

Nothing above needs the per-label decomposition: the chain equivalence holds verbatim for
finite label sets, with `||` replaced by `∪` and Boolean exclusivity by `Disjoint`.  The
row-level form makes it visible that the intermediates are ROWS -- honest existentially
quantified row variables, exactly what a nest of `+` applications introduces. -/

/-- One binary Pottier concatenation, at row level. -/
def PConcatRow (p q r : Row) : Prop := r = p ∪ q ∧ Disjoint p q

/-- The chain, at row level; the bottom of the chain is the empty record `{∂Abs}`. -/
def PChainRow : List Row → Row → Prop
  | [], r => r = ∅
  | p :: ps, r => ∃ t, PChainRow ps t ∧ PConcatRow p t r

/-- The flat Ermine relation on rows (this is literally `Sat`, with the parts
abstracted). -/
def ErmineFlatRow (ps : List Row) (r : Row) : Prop :=
  r = ps.foldr (· ∪ ·) ∅ ∧ ps.Pairwise Disjoint

theorem sat_iff_flatRow (rho : Assign) (c : Constraint) :
    Sat rho c ↔ ErmineFlatRow (parts rho c) (rho c.lhs) := Iff.rfl

theorem disjoint_foldr_union (p : Row) (ps : List Row) :
    Disjoint p (ps.foldr (· ∪ ·) ∅) ↔ ∀ q ∈ ps, Disjoint p q := by
  simp only [Finset.disjoint_left]
  constructor
  · intro h q hq l hl hlq
    exact h hl ((mem_foldr_union ps l).mpr ⟨q, hq, hlq⟩)
  · intro h l hl hmem
    obtain ⟨q, hq, hlq⟩ := (mem_foldr_union ps l).mp hmem
    exact h q hq hl hlq

theorem flatRow_empty_cons (ps : List Row) (r : Row) :
    ErmineFlatRow (∅ :: ps) r ↔ ErmineFlatRow ps r := by
  simp only [ErmineFlatRow, List.foldr_cons, Finset.empty_union, List.pairwise_cons]
  constructor
  · rintro ⟨h1, -, h3⟩
    exact ⟨h1, h3⟩
  · rintro ⟨h1, h2⟩
    exact ⟨h1, fun q _ => by simp, h2⟩

/-- **The n-ary bridge, at row level.** -/
theorem pchainRow_iff_flat (ps : List Row) (r : Row) :
    PChainRow ps r ↔ ErmineFlatRow ps r := by
  induction ps generalizing r with
  | nil => simp [PChainRow, ErmineFlatRow]
  | cons p ps ih =>
    rw [PChainRow]
    constructor
    · rintro ⟨t, ht, hr, hd⟩
      obtain ⟨ht1, ht2⟩ := (ih t).mp ht
      refine ⟨by rw [hr, ht1]; rfl, List.pairwise_cons.mpr ⟨?_, ht2⟩⟩
      rw [ht1] at hd
      exact (disjoint_foldr_union p ps).mp hd
    · rintro ⟨hr, hd⟩
      rw [List.pairwise_cons] at hd
      refine ⟨ps.foldr (· ∪ ·) ∅, (ih _).mpr ⟨rfl, hd.2⟩, hr, ?_⟩
      exact (disjoint_foldr_union p ps).mpr hd.1

/-- **`a <- (b₁, …, bₙ)` is a chain of `n` symmetric concatenations.**  No per-label
detour: the equivalence is between honest row assignments. -/
theorem sat_iff_pchainRow (rho : Assign) (a : Var) (vs : List Var) :
    Sat rho ⟨a, vs, ∅⟩ ↔ PChainRow (vs.map rho) (rho a) := by
  rw [sat_iff_flatRow, pchainRow_iff_flat]
  have : parts rho ⟨a, vs, ∅⟩ = (∅ : Row) :: vs.map rho := rfl
  rw [this, flatRow_empty_cons]

/-! ## 9. Ermine's concrete part IS a Pottier filter

§2.3: "The introduction of filters compensates the omission of the standard row
constructor `(ℓ : · ; ·)` by offering a way of not treating all row labels uniformly."
§4 shows the idiom on non-strict extension: "the first constraint uses a singleton filter
to indicate that the field `ℓ` is present with type `α` in the new record, while the
second constraint uses a cosingleton filter to indicate that all fields other than `ℓ`
have the same status as in the original record."

An Ermine constraint `a <- (b₁, …, bₙ, (|k|))` says precisely: on the FINITE filter `k`,
`a` is `Pre` and every `bᵢ` is `Abs`; off `k`, `a` is the concatenation of the `bᵢ`.  So
`Constraint.conc` is a finite filter and nothing else. -/

/-- The concrete part of a constraint, encoded with a finite filter. -/
def concEncoding (a : Var) (vs : List Var) (k : Finset Label) : List PConstr :=
  .sub (.fin k) (.var a) (.const Pre) ::
    vs.map (fun v => .sub (.fin k) (.var v) (.const Abs))

theorem pmodels_map_sub (ψ : PAssign) (vs : List Var) (k : Finset Label) :
    PModels ψ (vs.map (fun v => .sub (.fin k) (.var v) (.const Abs))) ↔
      ∀ v ∈ vs, ∀ l ∈ k, ψ v l = Abs := by
  constructor
  · intro h v hv l hl
    exact h _ (List.mem_map.mpr ⟨v, hv, rfl⟩) l hl
  · intro h κ hκ
    obtain ⟨v, hv, rfl⟩ := List.mem_map.mp hκ
    exact fun l hl => h v hv l hl

theorem pmodels_concEncoding (ψ : PAssign) (a : Var) (vs : List Var) (k : Finset Label) :
    PModels ψ (concEncoding a vs k) ↔ ∀ l ∈ k, ψ a l = Pre ∧ ∀ v ∈ vs, ψ v l = Abs := by
  rw [concEncoding, pmodels_cons, pmodels_map_sub]
  constructor
  · rintro ⟨h1, h2⟩ l hl
    exact ⟨h1 l hl, fun v hv => h2 v hv l hl⟩
  · intro h
    exact ⟨fun l hl => (h l hl).1, fun v hv l hl => (h l hl).2 v hv⟩

/-- The per-label shadow splits along the concrete part: ON the filter it is total
information, OFF it the constraint is the concrete-free partition. -/
theorem bsat_split (b : Var → Bool) (l : Label) (a : Var) (vs : List Var)
    (k : Finset Label) :
    BSat b l ⟨a, vs, k⟩ ↔
      (if l ∈ k then b a = Pre ∧ ∀ v ∈ vs, b v = Abs else BSat b l ⟨a, vs, ∅⟩) := by
  have hb : bparts b l ⟨a, vs, k⟩ = decide (l ∈ k) :: vs.map b := rfl
  have hb0 : bparts b l ⟨a, vs, (∅ : Finset Label)⟩ = false :: vs.map b := by simp [bparts]
  by_cases hl : l ∈ k
  · rw [if_pos hl, bsat_iff_flatBit, hb, decide_eq_true hl, flatBit_true_cons]
    simp only [List.mem_map, forall_exists_index, and_imp]
    constructor
    · rintro ⟨h1, h2⟩
      exact ⟨h1, fun v hv => h2 _ v hv rfl⟩
    · rintro ⟨h1, h2⟩
      exact ⟨h1, fun _ v hv he => he ▸ h2 v hv⟩
  · rw [if_neg hl, bsat_iff_flatBit, bsat_iff_flatBit, hb, hb0,
      decide_eq_false hl]

/-- **The concrete part is a filter.**  `Sat` splits into a filtered pair of Pottier
constraints on `k` and the concrete-free partition off `k`. -/
theorem sat_iff_filter_split (rho : Assign) (a : Var) (vs : List Var) (k : Finset Label) :
    Sat rho ⟨a, vs, k⟩ ↔
      PModels (toPAssign rho) (concEncoding a vs k) ∧
        ∀ l, l ∉ k → BSat (proj rho l) l ⟨a, vs, ∅⟩ := by
  rw [sat_iff_forall_label, pmodels_concEncoding]
  constructor
  · intro h
    refine ⟨fun l hl => ?_, fun l hl => ?_⟩
    · have := (bsat_split (proj rho l) l a vs k).mp (h l)
      rw [if_pos hl] at this
      exact this
    · have := (bsat_split (proj rho l) l a vs k).mp (h l)
      rw [if_neg hl] at this
      exact this
  · rintro ⟨h1, h2⟩ l
    rw [bsat_split]
    by_cases hl : l ∈ k
    · rw [if_pos hl]; exact h1 l hl
    · rw [if_neg hl]; exact h2 l hl

/-! ## 10. The whole-system corollary

For the fragment Pottier's scheme actually covers -- binary, concrete-free constraints,
i.e. exactly `a <- (x, y)` -- Ermine satisfaction of a SYSTEM is equivalent to Pottier
satisfaction of its encoding, both for a fixed assignment and for satisfiability. -/

/-- The fragment `a <- (x, y)`. -/
def BinAbstract (G : List Constraint) : Prop := ∀ c ∈ G, ∃ a x y, c = ⟨a, [x, y], ∅⟩

theorem BinAbstract.abstract {G : List Constraint} (h : BinAbstract G) : Abstract G := by
  intro c hc
  obtain ⟨a, x, y, rfl⟩ := h c hc
  rfl

/-- The Pottier encoding of one Ermine constraint. -/
def encodeC (c : Constraint) : List PConstr :=
  match c.vars with
  | [x, y] => concatSystem x y c.lhs
  | _ => []

@[simp] theorem encodeC_binary (a x y : Var) (k : Finset Label) :
    encodeC ⟨a, [x, y], k⟩ = concatSystem x y a := rfl

/-- The Pottier encoding of a system. -/
def encode (G : List Constraint) : List PConstr := G.flatMap encodeC

theorem mem_encode {G : List Constraint} {κ : PConstr} :
    κ ∈ encode G ↔ ∃ c ∈ G, κ ∈ encodeC c := by
  simp [encode, List.mem_flatMap]

theorem pmodels_encode (ψ : PAssign) (G : List Constraint) :
    PModels ψ (encode G) ↔ ∀ c ∈ G, PModels ψ (encodeC c) := by
  constructor
  · intro h c hc κ hκ; exact h κ (mem_encode.mpr ⟨c, hc, hκ⟩)
  · intro h κ hκ
    obtain ⟨c, hc, hκ'⟩ := mem_encode.mp hκ
    exact h c hc κ hκ'

/-- **Whole-system bridge.**  A row assignment models an Ermine system iff, read as a
Pottier ground assignment, it satisfies the encoding of that system. -/
theorem models_iff_pmodels (rho : Assign) (G : List Constraint) (h : BinAbstract G) :
    Models rho G ↔ PModels (toPAssign rho) (encode G) := by
  rw [pmodels_encode]
  constructor
  · intro hm c hc
    obtain ⟨a, x, y, rfl⟩ := h c hc
    rw [encodeC_binary, ← sat_iff_pmodels_concatSystem]
    exact hm _ hc
  · intro hp c hc
    obtain ⟨a, x, y, rfl⟩ := h c hc
    rw [sat_iff_pmodels_concatSystem]
    exact hp _ hc

/-- **Whole-system bridge, satisfiability form.**  The `←` direction is the interesting
one: a Pottier ground assignment is a TOTAL family over all labels and need not have
finite support, so it is not directly an Ermine assignment.  `satisfiable_iff_forall_label`
rebuilds one, label by label, with support inside the (finite) concrete labels. -/
theorem satisfiable_iff_psatisfiable (G : List Constraint) (h : BinAbstract G) :
    (∃ rho, Models rho G) ↔ ∃ ψ, PModels ψ (encode G) := by
  constructor
  · rintro ⟨rho, hm⟩
    exact ⟨toPAssign rho, (models_iff_pmodels rho G h).mp hm⟩
  · rintro ⟨ψ, hψ⟩
    rw [satisfiable_iff_forall_label]
    intro l
    refine ⟨fun v => ψ v l, ?_⟩
    intro c hc
    obtain ⟨a, x, y, rfl⟩ := h c hc
    rw [bridge]
    have := (pmodels_encode ψ G).mp hψ _ hc
    rw [encodeC_binary, pmodels_concatSystem] at this
    exact this l

/-! ### The general shape, for constraints of any arity and any concrete part

Sections 8 and 9 together give the complete Pottier reading of an ARBITRARY Ermine
constraint `a <- (b₁, …, bₙ, (|k|))`, with no restriction to the binary concrete-free
case: on the finite filter `k` it is a pair of filtered subtyping constraints, and off
`k` it is a chain of `n - 1` symmetric concatenations.  The intermediates of the chain
stay existentially quantified, which is why this statement needs no freshness
bookkeeping -- and it is also why it cannot be pushed further into a single list of
`PConstr`s without choosing names for them. -/

/-- The complete Pottier reading of one Ermine constraint. -/
theorem sat_iff_filter_and_chain (rho : Assign) (a : Var) (vs : List Var)
    (k : Finset Label) :
    Sat rho ⟨a, vs, k⟩ ↔
      PModels (toPAssign rho) (concEncoding a vs k) ∧
        ∀ l, l ∉ k → PChainBit (vs.map (proj rho l)) (proj rho l a) := by
  rw [sat_iff_filter_split]
  exact and_congr Iff.rfl
    (forall_congr' fun l => imp_congr Iff.rfl (bsat_iff_pchainBit _ l a vs))

/-- The complete Pottier reading of an Ermine SYSTEM.  This is the general form of the
whole-system corollary; `models_iff_pmodels` is the special case in which every
constraint is binary and concrete-free, and there the chain collapses to a single
`concatSystem` with no intermediate at all. -/
theorem models_iff_filter_and_chain (rho : Assign) (G : List Constraint) :
    Models rho G ↔ ∀ c ∈ G,
      PModels (toPAssign rho) (concEncoding c.lhs c.vars c.conc) ∧
        ∀ l, l ∉ c.conc →
          PChainBit (c.vars.map (proj rho l)) (proj rho l c.lhs) := by
  constructor
  · intro hm c hc
    exact (sat_iff_filter_and_chain rho c.lhs c.vars c.conc).mp (hm c hc)
  · intro h c hc
    exact (sat_iff_filter_and_chain rho c.lhs c.vars c.conc).mpr (h c hc)

/-! ## 11. A negative result: the TERNARY partition needs intermediates

Section 8 encodes `a <- (b₁, …, bₙ)` as a CHAIN, introducing `n - 1` intermediate row
variables.  Is that detour avoidable -- could Pottier constraints over the constraint's
own variables express the n-ary relation directly?  For `n = 3`, NO.

The argument is finite and per-label.  At a fixed label a filter contributes only
"fires / does not fire", and a constraint whose filter misses the label imposes nothing
there (so it is vacuously valid on any relation and at any point, and may be dropped).
What remains is an ATOM over the four variables `p, q, s` (the parts) and `r` (the
result) and the two constant rows `∂Abs`, `∂Pre`, in one of the two shapes of the
grammar.  `PAtom` below enumerates them; there are 468.

`ternary_atom_sound` says: EVERY atom that holds throughout the ternary partition
relation also holds at the point `(Abs, Abs, Abs, Pre)`, which is not in the relation
(it asserts a label present in the result and in none of the three parts).  Hence no
conjunction of atoms cuts the relation out.

The quantification is over an arbitrary LIST of atoms, so a would-be encoding gains
nothing by varying its filters from label to label: whatever set of atoms fires at a
given label, that set would have to cut out the relation there, and none does.  The
enumeration is also generous -- it lets condition terms and both sides of an equality
range over constants as well as variables, which Figure 1's sorting partly forbids -- so
the impossibility is if anything understated.  Section 8's
`ternary_via_one_intermediate` shows that a single intermediate repairs it. -/

/-- A term of the four-variable per-label language: one of the constraint's variables, or
one of the two constant rows. -/
inductive PT where
  /-- First part. -/    | vp
  /-- Second part. -/   | vq
  /-- Third part. -/    | vs
  /-- The result. -/    | vr
  /-- `∂Abs`. -/        | cAbs
  /-- `∂Pre`. -/        | cPre
  deriving DecidableEq

/-- Value of a term at the label under consideration. -/
def PT.val (p q s r : Bool) : PT → Bool
  | .vp => p
  | .vq => q
  | .vs => s
  | .vr => r
  | .cAbs => Abs
  | .cPre => Pre

/-- An atom: what a single Pottier constraint says at a single label it covers. -/
inductive PAtom where
  /-- `τ₁ ≤ τ₂`, i.e. `τ₁ = τ₂`. -/
  | eq (t₁ t₂ : PT)
  /-- `s ≤ τ₀ ? τ₁ ≤ τ₂`. -/
  | cond (c : Bool) (t₀ t₁ t₂ : PT)
  deriving DecidableEq

/-- Evaluation of an atom. -/
def PAtom.eval (p q s r : Bool) : PAtom → Bool
  | .eq t₁ t₂ => t₁.val p q s r == t₂.val p q s r
  | .cond c t₀ t₁ t₂ =>
      !(c == t₀.val p q s r) || (t₁.val p q s r == t₂.val p q s r)

/-- The ternary Ermine partition `r <- (p, q, s)`, at one label. -/
def ternary (p q s r : Bool) : Bool :=
  (r == (p || q || s)) && !(p && q) && !(p && s) && !(q && s)

theorem ternary_iff_flat (p q s r : Bool) :
    ternary p q s r = true ↔ ErmineFlatBit [p, q, s] r := by
  cases p <;> cases q <;> cases s <;> cases r <;>
    simp [ternary, ErmineFlatBit]

theorem bsat_iff_ternary (b : Var → Bool) (l : Label) (a x y z : Var) :
    BSat b l ⟨a, [x, y, z], ∅⟩ ↔ ternary (b x) (b y) (b z) (b a) = true := by
  rw [ternary_iff_flat, bsat_iff_flatBit]
  have : bparts b l ⟨a, [x, y, z], ∅⟩ = false :: [b x, b y, b z] := by simp [bparts]
  rw [this, flatBit_false_cons]

/-- **The key finite check.**  Every atom valid throughout the ternary partition is also
valid at `(Abs, Abs, Abs, Pre)`.  468 atoms x 16 points, decided by the kernel. -/
theorem ternary_atom_sound (A : PAtom)
    (h : ∀ p q s r, ternary p q s r = true → A.eval p q s r = true) :
    A.eval Abs Abs Abs Pre = true := by
  -- the relation has exactly four points
  have h1 := h false false false false rfl
  have h2 := h true false false true rfl
  have h3 := h false true false true rfl
  have h4 := h false false true true rfl
  clear h
  cases A with
  | eq t₁ t₂ =>
      revert h1 h2 h3 h4
      cases t₁ <;> cases t₂ <;> decide
  | cond c t₀ t₁ t₂ =>
      revert h1 h2 h3 h4
      cases c <;> cases t₀ <;> cases t₁ <;> cases t₂ <;> decide

/-- `(Abs, Abs, Abs, Pre)` is not in the relation: it puts a label in the result and in
none of the parts. -/
theorem ternary_bad : ternary Abs Abs Abs Pre = false := rfl

/-- **The ternary Ermine partition is not definable by Pottier constraints over its own
four variables.**  Intermediate row variables -- the chain of section 8 -- are therefore
not a presentational convenience but a necessity.

Note the contrast this draws.  Pottier's "(none of the rules requires fresh variables to
be allocated") is a statement about the SOLVER: closure never mints a variable.  It is
not a statement about constraint GENERATION, which introduces one row variable per
sub-expression, hence one intermediate per `+` in a nest.  Ermine's n-ary partition
compresses that nest into a single constraint; the price is a relation Pottier's grammar
cannot state in one atom. -/
theorem ternary_not_definable (C : List PAtom) :
    ¬ (∀ p q s r, (∀ A ∈ C, A.eval p q s r = true) ↔ ternary p q s r = true) := by
  intro h
  have hbad : ∀ A ∈ C, A.eval Abs Abs Abs Pre = true := by
    intro A hA
    refine ternary_atom_sound A fun p q s r hpqsr => ?_
    exact (h p q s r).mpr hpqsr A hA
  have := (h Abs Abs Abs Pre).mp hbad
  rw [ternary_bad] at this
  exact Bool.noConfusion this

/-! ## 12. Where subtyping is essential

Pottier's Theorem 4 -- "If `C` is closed and does not contain false, then `C` is
satisfiable" -- is proved (long version, p. 7) by exhibiting a canonical model:

```
  φ(α) = ⊔ φ(lb(α))‾        if ⊢ α : Type
  φ(α) = (⊔ φ(lb_ℓ(α)))‾    if ⊢ α : Row
…  The existence of least upper bounds is guaranteed by Theorem 1.
```

with `lb_ℓ(α) = {τ ; {ℓ} : ∂τ ≤ α ∈ C}`, and the conditional case additionally needs the
condition symbol to be PRIME: "because `s` must be a prime element of its symbol lattice,
this implies `s ≤ φ(τ)` for *some* `τ ∈ lb(α)`".

Both ingredients are vacuous in the Ermine specialisation.  Theorem 1 fails outright
(`no_upper_bound`).  Primality is trivial: in a two-element antichain every element is
join-irreducible because there are no nontrivial joins to be irreducible with respect to.
And the construction itself degenerates, in two steps. -/

/-- `lb_ℓ(α)`, specialised: the constant lower bounds of `α` at the label `l`.  With
field types gone, a constant row `∂τ` is a bare presence symbol, so the set is a list of
bits. -/
def lbOf (α : Var) (l : Label) : PConstr → Option Bool
  | .sub L (.const t) (.var β) => if β = α ∧ L.mem l then some t else none
  | _ => none

def lbAt (C : List PConstr) (α : Var) (l : Label) : List Bool := C.filterMap (lbOf α l)

/-- **First degeneration: a lower-bound set is never more than one value.**  Because `≤`
has collapsed to `=` (`SymLe`), a constant "lower" bound is an EQUATION; two distinct
ones make the system unsatisfiable.  So on any satisfiable system `lb_ℓ(α)` consists of
copies of the single value `φ(α).ℓ`, and `⊔ lb_ℓ(α)` does not form a join at all -- it
reads off a value that was already forced.  That is unification, not lattice-theoretic
saturation, and it is why the proof of Theorem 4 has no equality-only analogue. -/
theorem lbAt_eq_of_pmodels {C : List PConstr} {ψ : PAssign} (h : PModels ψ C)
    (α : Var) (l : Label) : ∀ t ∈ lbAt C α l, t = ψ α l := by
  intro t ht
  rw [lbAt, List.mem_filterMap] at ht
  obtain ⟨κ, hκC, hκ⟩ := ht
  cases κ with
  | cond L u s₀ s₁ s₂ => simp [lbOf] at hκ
  | sub L t₁ t₂ =>
    cases t₁ with
    | var w => simp [lbOf] at hκ
    | const u =>
      cases t₂ with
      | const w => simp [lbOf] at hκ
      | var β =>
        simp only [lbOf] at hκ
        by_cases hc : β = α ∧ L.mem l
        · rw [if_pos hc] at hκ
          have hu : u = t := Option.some.inj hκ
          subst hu
          obtain ⟨rfl, hmem⟩ := hc
          exact h _ hκC l hmem
        · rw [if_neg hc] at hκ
          exact absurd hκ (by simp)

/-- Pottier's canonical witness, specialised.  There is no join in `{Abs, Pre}`
(`no_upper_bound`), so `⊔` has to be READ in some ambient order; we take the two-element
chain `Abs < Pre`, whose join is `||`.  The choice turns out not to matter -- see
`lbAt_encode`. -/
def joinWitness (C : List PConstr) : PAssign :=
  fun α l => (lbAt C α l).foldr (· || ·) false

theorem mem_encodeC {c : Constraint} {κ : PConstr} (h : κ ∈ encodeC c) :
    ∃ L t s₀ s₁ s₂, κ = .cond L t s₀ s₁ s₂ := by
  unfold encodeC at h
  split at h
  · simp only [concatSystem, List.mem_cons, List.not_mem_nil, or_false] at h
    rcases h with rfl | rfl | rfl <;> exact ⟨_, _, _, _, _, rfl⟩
  · simp at h

/-- **Second degeneration: on an Ermine encoding the lower-bound sets are all EMPTY.**
`concatSystem` consists of three CONDITIONAL constraints and nothing else; there is not a
single unconditional subtyping constraint for `lb_ℓ` to collect. -/
theorem lbAt_encode (G : List Constraint) (α : Var) (l : Label) :
    lbAt (encode G) α l = [] := by
  rw [lbAt, List.filterMap_eq_nil_iff]
  intro κ hκ
  obtain ⟨c, -, hc⟩ := mem_encode.mp hκ
  obtain ⟨L, t, s₀, s₁, s₂, rfl⟩ := mem_encodeC hc
  rfl

/-- Consequently the witness is the everywhere-`Abs` assignment, whatever reading of `⊔`
one picks: all readings agree on the empty set's join, namely the bottom element. -/
theorem joinWitness_encode (G : List Constraint) :
    joinWitness (encode G) = fun _ _ => Abs := by
  funext α l
  change (lbAt (encode G) α l).foldr (· || ·) false = Abs
  rw [lbAt_encode]
  rfl

theorem toPAssign_empty : toPAssign (fun _ => (∅ : Row)) = fun _ _ => Abs := by
  funext v l
  simp [toPAssign]

/-- **The Ermine analogue of Theorem 4, and the point of this section.**  Pottier's
canonical witness, transported to the encoding of an Ermine system, IS the everywhere-
empty row assignment.  And the everywhere-empty assignment does model every abstract
system -- but that is `Rowpartition.models_empty`, a two-line direct verification
(`sat_empty`: every part is `∅`, so the union is `∅` and disjointness is free).  Nothing
in it mentions an order, a join, Theorem 1, or primality.  The theorem statements
coincide; the proofs have nothing in common. -/
theorem theorem4_analogue (G : List Constraint) (h : Abstract G) : ∃ rho, Models rho G :=
  satisfiable_of_abstract h

/-- The witness of `theorem4_analogue`, read as a Pottier ground assignment, is exactly
`joinWitness` of the encoding. -/
theorem joinWitness_eq_toPAssign_empty (G : List Constraint) :
    joinWitness (encode G) = toPAssign (fun _ => (∅ : Row)) := by
  rw [joinWitness_encode, toPAssign_empty]

/-- Closing the loop: on the binary abstract fragment, Pottier's canonical witness really
does satisfy the encoded system.  The construction reaches the right answer; it just
carries no information while doing so. -/
theorem pmodels_joinWitness (G : List Constraint) (h : BinAbstract G) :
    PModels (joinWitness (encode G)) (encode G) := by
  rw [joinWitness_eq_toPAssign_empty, ← models_iff_pmodels _ _ h]
  exact models_empty h.abstract


/-! ## 13. The bridge is EXACT only because subtyping is gone

The bridge is an equality of relations, so it is tempting to read it as "Pottier's
concatenation constraint IS Ermine's partition".  That reading is wrong in the original
system, and this section says exactly how.

Take Pottier's actual field lattice from Example 1: the FLAT lattice on
`{⊥_field, Abs, Pre, ⊤_field}`, in which `Abs` and `Pre` are incomparable but "do have a
common supertype `⊤_field`, so width subtyping is present".  Interpret the three
conditional constraints there, with a genuine `≤`.  Then:

* on the two-element subset `{Abs, Pre}` the relation is EXACTLY `PottierConcatBit`
  (`concat4_iff_bit`) -- so the specialisation of section 5 is faithful, not a guess;
* but on the full lattice the constraints do NOT determine the result: with both
  arguments `Abs`, the result may be `Abs` OR `⊤_field`
  (`concat4_result_underdetermined`).  They constrain the result only FROM BELOW, which
  is all a subtyping system ever needs.

So `⊤_field` -- the join that Theorem 1 supplies, and whose absence in the Ermine model
is `no_upper_bound` -- is precisely what stops Pottier's concatenation from being a
functional, exact partition.  Removing subtyping is what makes the bridge an equality. -/

/-- Pottier's `𝒮_field` in full: the flat lattice on `{⊥, Abs, Pre, ⊤}`. -/
inductive Sym4 where
  /-- `⊥_field`. -/ | bot
  /-- `Abs`. -/     | abs
  /-- `Pre`. -/     | pre
  /-- `⊤_field`. -/ | top
  deriving DecidableEq

/-- `≤_field` on the flat lattice: `⊥` below everything, `⊤` above everything, `Abs` and
`Pre` incomparable. -/
def Sym4.le : Sym4 → Sym4 → Bool
  | .bot, _ => true
  | _, .top => true
  | .abs, .abs => true
  | .pre, .pre => true
  | _, _ => false

theorem Sym4.le_refl (x : Sym4) : Sym4.le x x = true := by cases x <;> rfl

theorem Sym4.le_trans (x y z : Sym4) :
    Sym4.le x y = true → Sym4.le y z = true → Sym4.le x z = true := by
  cases x <;> cases y <;> cases z <;> decide

theorem Sym4.le_antisymm (x y : Sym4) :
    Sym4.le x y = true → Sym4.le y x = true → x = y := by
  cases x <;> cases y <;> decide

/-- `Abs` and `Pre` are incomparable, exactly as the paper requires. -/
theorem Sym4.abs_pre_incomparable :
    Sym4.le .abs .pre = false ∧ Sym4.le .pre .abs = false := ⟨rfl, rfl⟩

/-- …but they have a common upper bound, `⊤_field`: "they do have a common supertype
`⊤_field`, so width subtyping is present".  Compare `no_upper_bound`, which says this
element is exactly what the Ermine model does not have. -/
theorem Sym4.le_top (x : Sym4) : Sym4.le x .top = true := by cases x <;> rfl

/-- The three conditional constraints of the concatenation scheme, interpreted at one
label in the FULL field lattice, with a genuine subtyping `≤`. -/
def Concat4 (p q r : Sym4) : Bool :=
  (!(Sym4.le .abs p) || Sym4.le q r) &&
  (!(Sym4.le .abs q) || Sym4.le p r) &&
  (!(Sym4.le .pre p) || Sym4.le q .abs)

/-- The `{Abs, Pre}` embedding. -/
def Sym4.ofBool : Bool → Sym4
  | false => .abs
  | true => .pre

/-- **The specialisation of section 5 is faithful.**  On the two-element subset
`{Abs, Pre}` -- the only field symbols an Ermine row can exhibit -- Pottier's three
constraints, read with the real subtyping order, define exactly `PottierConcatBit`.  So
nothing was lost or invented when `≤` was replaced by `=`. -/
theorem concat4_iff_bit (p q r : Bool) :
    Concat4 (Sym4.ofBool p) (Sym4.ofBool q) (Sym4.ofBool r) = true ↔
      PottierConcatBit p q r := by
  cases p <;> cases q <;> cases r <;>
    simp [Concat4, Sym4.ofBool, Sym4.le, PottierConcatBit, SymLe]

/-- **But on the full lattice the result is not determined.**  Both arguments `Abs`
admits the result `Abs` and the result `⊤_field`.  Ermine's partition is functional in
the parts (`Sat` forces `rho a` to be the union), so the two relations differ as soon as
`⊤_field` is in the model. -/
theorem concat4_result_underdetermined :
    Concat4 .abs .abs .abs = true ∧ Concat4 .abs .abs .top = true ∧
      (Sym4.abs ≠ Sym4.top) := by
  refine ⟨rfl, rfl, ?_⟩
  intro h
  exact Sym4.noConfusion h

/-- The sharp form: in the full lattice the concatenation relation is not a function of
its arguments, so it cannot be the graph of any partition operator. -/
theorem concat4_not_functional :
    ¬ ∀ p q r r', Concat4 p q r = true → Concat4 p q r' = true → r = r' := by
  intro h
  exact Sym4.noConfusion (h .abs .abs .abs .top rfl rfl)

/-- Whereas after the collapse to equality it IS a function of its arguments: the result
bit is forced to be the OR of the argument bits.  That is the exactness the bridge
records. -/
theorem pottierConcatBit_functional (p q r r' : Bool) :
    PottierConcatBit p q r → PottierConcatBit p q r' → r = r' := by
  rw [← ermineConcatBit_iff_pottier, ← ermineConcatBit_iff_pottier]
  rintro ⟨h1, -⟩ ⟨h2, -⟩
  rw [h1, h2]

/-! ## 14. Non-vacuity

Three concrete instances, so that nothing above is true by accident. -/

section Sanity

/-- `a <- (x, y)` at a label where `x` is present: Ermine and Pottier both accept. -/
example : PottierConcat (fun v => if v = 1 then true else if v = 2 then false else true)
    1 2 0 :=
  (bridge _ 7 0 1 2).mp (by rw [bsat_binary]; exact ⟨rfl, by simp⟩)

/-- Both arguments present: Pottier's third constraint rejects, and so does Ermine's
disjointness. -/
example : ¬ PottierConcat (fun _ => true) 1 2 0 := by
  rintro ⟨-, -, h3⟩
  exact Bool.noConfusion (h3 rfl)

/-- A whole system: `a <- (x, y)` and `x <- (u, v)`, satisfied by
`u = {1}, v = {2}, x = {1,2}, y = {3}, a = {1,2,3}`.  Verified through the encoding, so
it exercises `models_iff_pmodels` in the forward direction. -/
example :
    PModels (toPAssign (fun v =>
        if v = 0 then ({1, 2, 3} : Row) else if v = 1 then {1, 2}
        else if v = 2 then {3} else if v = 3 then {1} else {2}))
      (encode [⟨0, [1, 2], ∅⟩, ⟨1, [3, 4], ∅⟩]) := by
  rw [← models_iff_pmodels]
  · intro c hc
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl
    · rw [sat_two]; refine ⟨by decide, by decide, by decide, by decide⟩
    · rw [sat_two]; refine ⟨by decide, by decide, by decide, by decide⟩
  · intro c hc
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl
    · exact ⟨0, 1, 2, rfl⟩
    · exact ⟨1, 3, 4, rfl⟩

end Sanity

end Pottier
end Rowpartition
