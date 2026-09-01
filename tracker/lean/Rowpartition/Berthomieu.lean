/-
# Berthomieu's `=_L`, and an expressiveness separation

Pottier & Rémy's ATTAPL chapter (§10.8) reports a device attributed to Berthomieu: where
Wand's treatment of record concatenation introduces a four-way disjunction per label --
and with it exponential-time constraint solving -- Berthomieu rewrites the constraint
using a new predicate

        R₁ =_L R₂    ("the rows R₁ and R₂ agree OUTSIDE the finite label set L")

so that, in their words, "no disjunctions are ever introduced, so that the time
complexity of constraint solving apparently remains polynomial".

This file asks whether Ermine could adopt that device, and answers NO, with a proof.

## What `=_L` is, here

Ermine's rows are finite sets of labels (`Rowpartition.Row = Finset Label`), so the
device reads

        `EqOutside L r s := ∀ l, l ∉ L → (l ∈ r ↔ l ∈ s)`.

Read against Pottier's LICS 2003 constraint language, `EqOutside L` is exactly an
*equality* constraint carried by the COFINITE filter `𝓛 \ L`: his `L : τ₁ ≤ τ₂` means
"τ₁.ℓ ≤ τ₂.ℓ for every ℓ ∈ L", and the complement turns his fusion law (union of
filters) into `EqOutside.inter` and his (TRANS-ROW) rule (intersection of filters) into
`EqOutside.trans_union`.  Both are proved below, so the correspondence is not a slogan.

## The result

Section 3 proves the SEPARATION.  Let

        `BC ::= Eq v w | EqOut L v w`

be the Berthomieu constraint language over Ermine rows, and let a system `Φ` *define* a
predicate `P` on assignments, relative to an interface `S` of visible variables, when

        `∀ rho, (∃ σ, σ agrees with rho on S ∧ σ ⊨ Φ) ↔ P rho`

-- i.e. `Φ` may use arbitrarily many auxiliary variables, existentially quantified.
Then:

* **`not_defines_partition`** -- NO system `Φ` of `BC` constraints, over ANY interface
  `S` and with ANY number of auxiliary variables, defines Ermine's binary partition
  `a <- (b, c)`.  `Φ` is not even required to be finite.

The proof is the invariance argument.  Every `BC` constraint survives the pointwise
operation "insert one label ℓ into EVERY variable at once" (`bcModels_insert`): equality
is a congruence, and inserting the same label everywhere cannot disturb agreement
outside any `L`, because at ℓ both sides become true and elsewhere nothing moves.  No
freshness hypothesis at all is needed.  But `a <- (b, c)` is destroyed by that
operation: the all-empty assignment satisfies it, and its image (every variable `{ℓ}`)
violates `Disjoint (rho b) (rho c)`.  Disjointness is exactly what `=_L` cannot see.

Section 4 turns this into a complete CLASSIFICATION (`defines_partition_iff`): a
partition constraint `⟨a, vs, k⟩` is `BC`-definable **iff** `vs` has length one and
`k = ∅` -- that is, iff it is the trivial constraint `a <- (b)`, which is just `a = b`.
Every constraint with a concrete part is out, for a second and independent reason
(`bcModels_empty`: the everywhere-empty assignment models EVERY `BC` system, so every
`BC`-definable predicate holds of it); every constraint with two or more variable parts
is out by disjointness; and `a <- ()` is out too.

Section 5 shows the separation is robust.  Extend the language with per-label presence
and absence literals -- `ℓ ∈ v`, `ℓ ∉ v`, which is what one needs to talk about
concrete label sets at all -- and the separation still holds
(`berthomieu_separation`); one only has to choose ℓ outside the finitely many labels
the literals name (in fact only the absence literals matter).  Yet that extended
language DOES define single-label record extension `a <- (b, (|ℓ|))`
(`definesX_extension`).  So the boundary is sharp: `=_L` plus presence bits reaches row
extension by a KNOWN label, and stops dead at disjoint union of two UNKNOWN rows.

Section 6 checks that `=_L` is not vacuous machinery: it is strictly stronger than plain
equality (`not_defines_eqOutside_of_isEq`), because equality-only systems are preserved
by every pointwise map of rows whereas `=_L` is not.

Section 7 proves what `=_L` CAN do for Ermine.

* `eqOutside_conc_of_sat`: every partition constraint ENTAILS a `=_L` constraint --
  outside its concrete part, the left-hand row agrees with the union of its variable
  parts.  Specialised to the leaf expansion of `Rowpartition.Fragment`, this gives
  `eqOutside_leaves`, a `=_L` reading of the normal form.
* `eq_leaves_of_abstract`: on ABSTRACT systems `kern G a = ∅`, and `EqOutside ∅` is
  equality.  Since all 345 residual partition constraints measured over the Ermine
  stdlib closure are purely abstract, every `L` that could arise on that corpus is `∅`:
  `=_L` degenerates to `=` on real Ermine residuals.
* `sat_two_iff_eqOutside`: the exact diagnosis.  `a <- (b, c)` is equivalent to
  `EqOutside (rho c) (rho a) (rho b) ∧ Disjoint (rho b) (rho c) ∧ rho c ⊆ rho a`.
  Partition IS `=_L` -- but with the exception set `L` a VARIABLE rather than a
  constant, plus disjointness.  Berthomieu's `L` is a constant, and that is precisely
  the gap the separation measures.
* `sat_ext_iff` (stated back in section 1, because section 5 needs it):
  `a <- (b, (|ℓ|))` is exactly `EqOutside {ℓ} (rho a) (rho b)` together with `ℓ ∈ rho a`
  and `ℓ ∉ rho b` -- Pottier's cosingleton-filter idiom, in Ermine's equality-only
  setting.

Section 8 adds a SECOND, independent invariance -- toggling one label in every row at
once -- and with it a second separation: Ermine's `Has a b`, that is `∃ c. a <- (b, c)`,
which is row subsumption `rho b ⊆ rho a` (`has_iff_subset`), is not definable either
(`not_defines_subset`, `not_definesX_subset`).  Label insertion cannot refute
subsumption, since it is monotone; toggling can.

## Verdict

Ermine can take `=_L` as a *derived* notion -- a compact way to state "these two rows
differ only inside this known label set", useful for printing residuals about record
extension and update, and equipped with fusion and transitivity rules that mirror
Pottier's.  Ermine CANNOT take it as a *replacement* for PARTITION: no amount of `=_L`,
equality, presence and absence, over any number of auxiliary variables, expresses
`a <- (b, c)` -- nor even the weaker `Has a b`.  Berthomieu's device buys polynomial
time in a setting whose primitive is "agree away from a FIXED set"; Ermine's primitive
is "disjoint union", which is "agree away from a VARIABLE set" plus disjointness
(`sat_two_iff_eqOutside`), and the two are not interdefinable.  The ATTAPL remark
therefore does not transfer.
-/
import Rowpartition.Fragment
import Mathlib.Data.Finset.Lattice.Fold

namespace Rowpartition

/-! ## 1. The relation `=_L`

`EqOutside L r s` is Berthomieu's `r =_L s`.  Everything in this section is elementary;
the two lemmas worth naming are `EqOutside.inter` and `EqOutside.trans_union`, which are
Pottier's fusion law and his (TRANS-ROW) rule read through the complement.  The section
closes with `sat_ext_iff`, which belongs with the positive results of section 7 but is
proved here because section 5 uses it. -/

/-- **Berthomieu's `=_L`**: the rows `r` and `s` agree outside the finite label set `L`. -/
def EqOutside (L : Finset Label) (r s : Row) : Prop := ∀ l, l ∉ L → (l ∈ r ↔ l ∈ s)

namespace EqOutside

/-- `=_L` is reflexive. -/
theorem refl (L : Finset Label) (r : Row) : EqOutside L r r := fun _ _ => Iff.rfl

/-- `=_L` is symmetric. -/
theorem symm {L : Finset Label} {r s : Row} (h : EqOutside L r s) : EqOutside L s r :=
  fun l hl => (h l hl).symm

/-- `=_L` is transitive. -/
theorem trans {L : Finset Label} {r s t : Row} (h₁ : EqOutside L r s)
    (h₂ : EqOutside L s t) : EqOutside L r t := fun l hl => (h₁ l hl).trans (h₂ l hl)

/-- Agreeing outside a smaller set is more informative. -/
theorem mono {L L' : Finset Label} {r s : Row} (hL : L ⊆ L') (h : EqOutside L r s) :
    EqOutside L' r s := fun l hl => h l fun hm => hl (hL hm)

/-- **Fusion.**  Two `=_L` facts about the same pair combine by INTERSECTING the
exception sets.  Through the complement this is Pottier's fusion law
`(L₁ : e) ∧ (L₂ : e) ≡ (L₁ ∪ L₂) : e`. -/
theorem inter {L L' : Finset Label} {r s : Row} (h : EqOutside L r s)
    (h' : EqOutside L' r s) : EqOutside (L ∩ L') r s := by
  intro l hl
  rw [Finset.mem_inter] at hl
  by_cases hm : l ∈ L
  · exact h' l fun hm' => hl ⟨hm, hm'⟩
  · exact h l hm

/-- **Composition.**  Chaining two `=_L` facts UNIONS the exception sets.  Through the
complement this is Pottier's (TRANS-ROW), whose filters intersect. -/
theorem trans_union {L L' : Finset Label} {r s t : Row} (h : EqOutside L r s)
    (h' : EqOutside L' s t) : EqOutside (L ∪ L') r t := by
  intro l hl
  rw [Finset.mem_union, not_or] at hl
  exact (h l hl.1).trans (h' l hl.2)

end EqOutside

/-- `=_L` for fixed `L` is an equivalence relation. -/
theorem eqOutside_equivalence (L : Finset Label) : Equivalence (EqOutside L) :=
  ⟨EqOutside.refl L, EqOutside.symm, EqOutside.trans⟩

/-- With no exceptions allowed, `=_L` IS equality. -/
@[simp] theorem eqOutside_empty {r s : Row} : EqOutside ∅ r s ↔ r = s := by
  constructor
  · intro h; exact Finset.ext fun l => h l (Finset.notMem_empty l)
  · rintro rfl; exact EqOutside.refl _ _

/-- The closed form: `r =_L s` iff `r` and `s` have the same part outside `L`. -/
theorem eqOutside_iff_sdiff {L : Finset Label} {r s : Row} :
    EqOutside L r s ↔ r \ L = s \ L := by
  constructor
  · intro h
    ext l
    simp only [Finset.mem_sdiff]
    exact and_congr_left fun hl => h l hl
  · intro h l hl
    have hx := Finset.ext_iff.mp h l
    simp only [Finset.mem_sdiff, hl, not_false_iff, and_true] at hx
    exact hx

/-- Two rows that both live inside `L` agree outside it, vacuously. -/
theorem eqOutside_of_subset {L : Finset Label} {r s : Row} (hr : r ⊆ L) (hs : s ⊆ L) :
    EqOutside L r s := fun _ hl => ⟨fun h => absurd (hr h) hl, fun h => absurd (hs h) hl⟩

/-- **Determination.**  `r =_L s` together with the two rows' traces on `L` pins them
down: knowing `s` and `r ∩ L` reconstructs `r` exactly. -/
theorem EqOutside.reconstruct {L : Finset Label} {r s : Row} (h : EqOutside L r s) :
    r = (s \ L) ∪ (r ∩ L) := by
  ext l
  simp only [Finset.mem_union, Finset.mem_sdiff, Finset.mem_inter]
  by_cases hl : l ∈ L
  · simp [hl]
  · simp [hl, h l hl]

/-- **Determination, sharp form.**  `=_L` plus equality of the traces on `L` is
equality. -/
theorem EqOutside.eq_of_inter {L : Finset Label} {r s : Row} (h : EqOutside L r s)
    (hi : r ∩ L = s ∩ L) : r = s := by
  ext l
  by_cases hl : l ∈ L
  · have hx := Finset.ext_iff.mp hi l
    simp only [Finset.mem_inter, hl, and_true] at hx
    exact hx
  · exact h l hl

/-- **Single-label extension, exactly.**  `a <- (b, (|ℓ|))` is `=_{ℓ}` plus two presence
bits.  This is Pottier's cosingleton-filter idiom in Ermine's equality-only setting, and
it is the constraint shape for which `=_L` really is the right notation. -/
theorem sat_ext_iff (rho : Assign) (a b : Var) (ℓ : Label) :
    Sat rho ⟨a, [b], {ℓ}⟩ ↔ EqOutside {ℓ} (rho a) (rho b) ∧ ℓ ∈ rho a ∧ ℓ ∉ rho b := by
  rw [sat_one]
  constructor
  · rintro ⟨hu, hd⟩
    have hnb : ℓ ∉ rho b := Finset.disjoint_left.mp hd (Finset.mem_singleton_self ℓ)
    refine ⟨?_, ?_, hnb⟩
    · intro l hl
      rw [hu]
      simp only [Finset.mem_union, Finset.mem_singleton]
      simp only [Finset.mem_singleton] at hl
      exact ⟨fun h => h.resolve_left hl, Or.inr⟩
    · rw [hu]
      simp
  · rintro ⟨he, ha, hb⟩
    refine ⟨?_, ?_⟩
    · ext l
      simp only [Finset.mem_union, Finset.mem_singleton]
      by_cases hl : l = ℓ
      · subst hl
        simp [ha]
      · rw [he l (by simpa using hl)]
        simp [hl]
    · rw [Finset.disjoint_singleton_left]
      exact hb

/-! ## 2. The Berthomieu constraint language, and definability

`BC` is the language the ATTAPL remark describes: equalities between row variables, and
`=_L` between row variables.  Nothing else -- in particular no partition, no
disjointness, and no way to name a concrete row. -/

/-- A Berthomieu constraint over Ermine rows. -/
inductive BC where
  /-- `rho v = rho w`. -/
  | eq (v w : Var) : BC
  /-- `rho v =_L rho w`. -/
  | eqOut (L : Finset Label) (v w : Var) : BC
  deriving DecidableEq

/-- Satisfaction of a single Berthomieu constraint. -/
def BCSat (rho : Assign) : BC → Prop
  | .eq v w => rho v = rho w
  | .eqOut L v w => EqOutside L (rho v) (rho w)

/-- Satisfaction of a system.  The system is given as a PREDICATE on constraints, so the
separation below does not even use finiteness; `(· ∈ Φ)` for a `Φ : List BC` recovers
the finite reading. -/
def BCModels (rho : Assign) (Φ : BC → Prop) : Prop := ∀ φ, Φ φ → BCSat rho φ

/-- **Definability with auxiliary variables.**  `Φ` defines the predicate `P` through
the interface `S` when the assignments whose `S`-restriction extends to a model of `Φ`
are exactly those satisfying `P`.  Variables outside `S` are the auxiliaries; taking
`S = Set.univ` is the auxiliary-free reading, `S = {a, b, c}` the reading in which `Φ`
may use as many auxiliaries as it likes. -/
def BCDefines (S : Set Var) (Φ : BC → Prop) (P : Assign → Prop) : Prop :=
  ∀ rho, (∃ σ, (∀ v ∈ S, σ v = rho v) ∧ BCModels σ Φ) ↔ P rho

/-- Non-vacuity: `BC` does define something, namely `=_L` itself. -/
theorem bcDefines_eqOut (a b : Var) (L : Finset Label) :
    BCDefines {a, b} (fun φ => φ = BC.eq a a ∨ φ = BC.eqOut L a b)
      (fun rho => EqOutside L (rho a) (rho b)) := by
  intro rho
  constructor
  · rintro ⟨σ, hag, hmod⟩
    have h : EqOutside L (σ a) (σ b) := hmod _ (Or.inr rfl)
    rwa [hag a (by simp), hag b (by simp)] at h
  · intro h
    refine ⟨rho, fun _ _ => rfl, ?_⟩
    rintro φ (rfl | rfl)
    · exact rfl
    · exact h

/-! ## 3. The invariance argument, and the separation -/

/-- **The master lemma.**  If a pointwise operation on rows preserves every model of
`Φ`, then no predicate that the operation destroys can be defined by `Φ` -- for ANY
interface `S`, hence with any number of auxiliary variables. -/
theorem not_bcDefines_of_pointwise {S : Set Var} {Φ : BC → Prop} {P : Assign → Prop}
    (F : Row → Row) (hF : ∀ σ : Assign, BCModels σ Φ → BCModels (fun v => F (σ v)) Φ)
    (rho : Assign) (h1 : P rho) (h2 : ¬ P (fun v => F (rho v))) : ¬ BCDefines S Φ P := by
  intro hdef
  obtain ⟨σ, hag, hmod⟩ := (hdef rho).mpr h1
  refine h2 ((hdef _).mp ⟨fun v => F (σ v), fun v hv => ?_, hF σ hmod⟩)
  change F (σ v) = F (rho v)
  rw [hag v hv]

/-- **The invariance.**  Inserting one and the same label into EVERY variable preserves
every Berthomieu system.  No freshness hypothesis is needed: equality is a congruence,
and at the inserted label both sides of any `=_L` become true simultaneously. -/
theorem bcModels_insert (ℓ : Label) {Φ : BC → Prop} {σ : Assign} (h : BCModels σ Φ) :
    BCModels (fun v => insert ℓ (σ v)) Φ := by
  intro φ hφ
  cases φ with
  | eq v w =>
      change insert ℓ (σ v) = insert ℓ (σ w)
      exact congrArg (insert ℓ) (h _ hφ)
  | eqOut L v w =>
      change EqOutside L (insert ℓ (σ v)) (insert ℓ (σ w))
      intro l hl
      simp only [Finset.mem_insert]
      exact or_congr_right ((h _ hφ : EqOutside L (σ v) (σ w)) l hl)

/-- The everywhere-empty assignment models EVERY Berthomieu system.  So `BC` cannot even
express "this row is nonempty", and every `BC`-definable predicate must hold of the
empty assignment. -/
theorem bcModels_empty (Φ : BC → Prop) : BCModels (fun _ => (∅ : Row)) Φ := by
  intro φ _
  cases φ with
  | eq v w => exact rfl
  | eqOut L v w => exact EqOutside.refl _ _

/-- Consequently every `BC`-definable predicate holds of the empty assignment. -/
theorem bcDefines_empty {S : Set Var} {Φ : BC → Prop} {P : Assign → Prop}
    (h : BCDefines S Φ P) : P (fun _ => (∅ : Row)) :=
  (h _).mp ⟨fun _ => ∅, fun _ _ => rfl, bcModels_empty Φ⟩

/-- A CONSTANT nonempty assignment breaks any partition with at least two variable
parts: two distinct positions of the right-hand side then carry the same nonempty row,
and `Sat` demands they be disjoint. -/
theorem not_sat_const (r : Row) (x : Label) (hx : x ∈ r) (a b b' : Var) (vs : List Var)
    (k : Finset Label) : ¬ Sat (fun _ => r) ⟨a, b :: b' :: vs, k⟩ := by
  intro h
  have hp := h.pairwise_vars
  rw [List.pairwise_cons] at hp
  have hd : Disjoint r r := hp.1 b' (by simp)
  exact Finset.disjoint_left.mp hd hx hx

/-- **THE SEPARATION.**  No system of Berthomieu constraints -- over any interface, with
any number of auxiliary variables, finite or not -- defines Ermine's binary partition
`a <- (b, c)`.  The variables `a`, `b`, `c` need not be distinct. -/
theorem not_defines_partition (S : Set Var) (Φ : BC → Prop) (a b c : Var) :
    ¬ BCDefines S Φ (fun rho => Sat rho ⟨a, [b, c], ∅⟩) := by
  refine not_bcDefines_of_pointwise (insert 0) (fun σ h => bcModels_insert 0 h)
    (fun _ => (∅ : Row)) (sat_empty rfl) ?_
  exact not_sat_const _ 0 (Finset.mem_insert_self 0 ∅) a b c [] ∅

/-- The finite reading asked for: `Φ` a finite LIST of constraints over `{a, b, c}` plus
auxiliaries. -/
theorem not_defines_partition_list (S : Set Var) (Φ : List BC) (a b c : Var) :
    ¬ BCDefines S (· ∈ Φ) (fun rho => Sat rho ⟨a, [b, c], ∅⟩) :=
  not_defines_partition S _ a b c

/-- The auxiliary-free reading, spelled out: no `BC` system is satisfied by EXACTLY the
assignments satisfying `a <- (b, c)`. -/
theorem not_defines_partition_noaux (Φ : BC → Prop) (a b c : Var) :
    ¬ (∀ rho, BCModels rho Φ ↔ Sat rho ⟨a, [b, c], ∅⟩) := by
  intro h
  refine not_defines_partition Set.univ Φ a b c fun rho => ?_
  constructor
  · rintro ⟨σ, hag, hmod⟩
    have hσ : σ = rho := funext fun v => hag v (Set.mem_univ v)
    exact (h rho).mp (hσ ▸ hmod)
  · intro hsat
    exact ⟨rho, fun _ _ => rfl, (h rho).mpr hsat⟩

/-! ## 4. Exactly which partition constraints ARE Berthomieu-definable

The separation is not an accident of the binary shape.  Only the degenerate partition
`a <- (b)` -- which is just `a = b` -- survives. -/

/-- A concrete part is already fatal: the empty assignment models every `BC` system, but
does not satisfy a partition with a nonempty concrete part. -/
theorem not_defines_of_conc_ne (S : Set Var) (Φ : BC → Prop) (a : Var) (vs : List Var)
    (k : Finset Label) (hk : k ≠ ∅) :
    ¬ BCDefines S Φ (fun rho => Sat rho ⟨a, vs, k⟩) := by
  intro h
  exact hk (Finset.subset_empty.mp (bcDefines_empty h).conc_subset_lhs)

/-- Zero or two-or-more variable parts is fatal too, by the invariance. -/
theorem not_defines_of_length_ne_one (S : Set Var) (Φ : BC → Prop) (a : Var)
    (vs : List Var) (hvs : vs.length ≠ 1) :
    ¬ BCDefines S Φ (fun rho => Sat rho ⟨a, vs, ∅⟩) := by
  refine not_bcDefines_of_pointwise (insert 0) (fun σ h => bcModels_insert 0 h)
    (fun _ => (∅ : Row)) (sat_empty rfl) ?_
  match vs, hvs with
  | [], _ =>
      intro h
      have hx : insert (0 : Label) (∅ : Row) = (∅ : Row) := (sat_zero _ a ∅).mp h
      exact Finset.notMem_empty 0 (hx ▸ Finset.mem_insert_self 0 (∅ : Row))
  | [_], hvs => exact absurd rfl hvs
  | b :: b' :: t, _ =>
      exact not_sat_const _ 0 (Finset.mem_insert_self 0 ∅) a b b' t ∅

/-- The one positive case: `a <- (b)` is `a = b`, and `BC` says that. -/
theorem defines_unary (a b : Var) :
    BCDefines {a, b} (fun φ => φ = BC.eq a b) (fun rho => Sat rho ⟨a, [b], ∅⟩) := by
  intro rho
  constructor
  · rintro ⟨σ, hag, hmod⟩
    have h : σ a = σ b := hmod _ rfl
    rw [hag a (by simp), hag b (by simp)] at h
    rw [sat_one]
    exact ⟨by rw [h, Finset.empty_union], by simp⟩
  · intro h
    refine ⟨rho, fun _ _ => rfl, ?_⟩
    rintro φ rfl
    change rho a = rho b
    have hx := ((sat_one rho a b ∅).mp h).1
    rwa [Finset.empty_union] at hx

/-- **Classification.**  A partition constraint is Berthomieu-definable exactly when it
is the trivial one-variable, no-concrete-part constraint. -/
theorem defines_partition_iff (a : Var) (vs : List Var) (k : Finset Label) :
    (∃ (S : Set Var) (Φ : BC → Prop),
      BCDefines S Φ (fun rho => Sat rho ⟨a, vs, k⟩)) ↔ (vs.length = 1 ∧ k = ∅) := by
  constructor
  · rintro ⟨S, Φ, hdef⟩
    have hk : k = ∅ := by
      by_contra hk
      exact not_defines_of_conc_ne S Φ a vs k hk hdef
    subst hk
    refine ⟨?_, rfl⟩
    by_contra hlen
    exact not_defines_of_length_ne_one S Φ a vs hlen hdef
  · rintro ⟨hlen, rfl⟩
    match vs, hlen with
    | [b], _ => exact ⟨{a, b}, _, defines_unary a b⟩

/-! ## 5. The separation survives presence and absence literals

`BC` cannot mention a concrete label at all, so one might object that the separation is
about a language too weak to be interesting.  Extend it, then, with the two per-label
literals that any label-set constraint language needs: `ℓ ∈ v` and `ℓ ∉ v`.  The
extended language DOES define single-label record extension `a <- (b, (|ℓ|))`.  It still
does not define `a <- (b, c)`. -/

/-- Berthomieu constraints extended with per-label presence and absence literals. -/
inductive BCX where
  /-- `rho v = rho w`. -/
  | eq (v w : Var) : BCX
  /-- `rho v =_L rho w`. -/
  | eqOut (L : Finset Label) (v w : Var) : BCX
  /-- `l ∈ rho v`. -/
  | pres (l : Label) (v : Var) : BCX
  /-- `l ∉ rho v`. -/
  | abs (l : Label) (v : Var) : BCX
  deriving DecidableEq

/-- Satisfaction of a single extended constraint. -/
def BCXSat (rho : Assign) : BCX → Prop
  | .eq v w => rho v = rho w
  | .eqOut L v w => EqOutside L (rho v) (rho w)
  | .pres l v => l ∈ rho v
  | .abs l v => l ∉ rho v

/-- Satisfaction of an extended system.  Here the system must be FINITE: the invariance
below needs a label that no absence literal mentions. -/
def BCXModels (rho : Assign) (Φ : List BCX) : Prop := ∀ φ ∈ Φ, BCXSat rho φ

/-- Definability in the extended language. -/
def BCXDefines (S : Set Var) (Φ : List BCX) (P : Assign → Prop) : Prop :=
  ∀ rho, (∃ σ, (∀ v ∈ S, σ v = rho v) ∧ BCXModels σ Φ) ↔ P rho

/-- The label named by a constraint, if it is a per-label literal. -/
def litLabel : BCX → Finset Label
  | .pres l _ => {l}
  | .abs l _ => {l}
  | _ => ∅

/-- The finitely many labels a system names in its literals.  This is the only place
where finiteness of `Φ` is used: `=_L` and equality impose no constraint on the choice
of a fresh label, and for `bcxModels_insert` even the presence literals do not -- only
the absence literals do. -/
def litLabels (Φ : List BCX) : Finset Label := (Φ.map litLabel).foldr (· ∪ ·) ∅

theorem mem_litLabels {Φ : List BCX} {φ : BCX} {l : Label} (hφ : φ ∈ Φ)
    (hl : l ∈ litLabel φ) : l ∈ litLabels Φ := by
  rw [litLabels, mem_foldr_union]
  exact ⟨litLabel φ, List.mem_map.mpr ⟨φ, hφ, rfl⟩, hl⟩

/-- The master lemma, for the extended language. -/
theorem not_bcxDefines_of_pointwise {S : Set Var} {Φ : List BCX} {P : Assign → Prop}
    (F : Row → Row) (hF : ∀ σ : Assign, BCXModels σ Φ → BCXModels (fun v => F (σ v)) Φ)
    (rho : Assign) (h1 : P rho) (h2 : ¬ P (fun v => F (rho v))) : ¬ BCXDefines S Φ P := by
  intro hdef
  obtain ⟨σ, hag, hmod⟩ := (hdef rho).mpr h1
  refine h2 ((hdef _).mp ⟨fun v => F (σ v), fun v hv => ?_, hF σ hmod⟩)
  change F (σ v) = F (rho v)
  rw [hag v hv]

/-- **The invariance, extended.**  Inserting a label that no absence literal mentions
into every variable still preserves every model. -/
theorem bcxModels_insert {ℓ : Label} {Φ : List BCX} (hℓ : ℓ ∉ litLabels Φ) {σ : Assign}
    (h : BCXModels σ Φ) : BCXModels (fun v => insert ℓ (σ v)) Φ := by
  intro φ hφ
  cases φ with
  | eq v w =>
      change insert ℓ (σ v) = insert ℓ (σ w)
      exact congrArg (insert ℓ) (h _ hφ)
  | eqOut L v w =>
      change EqOutside L (insert ℓ (σ v)) (insert ℓ (σ w))
      intro l hl
      simp only [Finset.mem_insert]
      exact or_congr_right ((h _ hφ : EqOutside L (σ v) (σ w)) l hl)
  | pres l v =>
      change l ∈ insert ℓ (σ v)
      exact Finset.mem_insert_of_mem (h _ hφ)
  | abs l v =>
      change l ∉ insert ℓ (σ v)
      have hne : l ≠ ℓ := fun hlℓ =>
        hℓ (hlℓ ▸ mem_litLabels hφ (Finset.mem_singleton_self l))
      simp only [Finset.mem_insert, not_or]
      exact ⟨hne, h _ hφ⟩

/-- **THE SEPARATION, in its strongest form proved here.**  Even with equalities, `=_L`,
and arbitrary presence/absence literals, no finite system defines `a <- (b, c)`. -/
theorem berthomieu_separation (S : Set Var) (Φ : List BCX) (a b c : Var) :
    ¬ BCXDefines S Φ (fun rho => Sat rho ⟨a, [b, c], ∅⟩) := by
  obtain ⟨ℓ, hℓ⟩ := exists_fresh (litLabels Φ)
  refine not_bcxDefines_of_pointwise (insert ℓ) (fun σ h => bcxModels_insert hℓ h)
    (fun _ => (∅ : Row)) (sat_empty rfl) ?_
  exact not_sat_const _ ℓ (Finset.mem_insert_self ℓ ∅) a b c [] ∅

/-- ... yet the extended language DOES define single-label record extension.  This is
Pottier's cosingleton-filter idiom: "`a` and `b` agree away from `ℓ`, `ℓ` is present in
`a` and absent from `b`". -/
theorem definesX_extension (a b : Var) (ℓ : Label) :
    BCXDefines {a, b} [BCX.eqOut {ℓ} a b, BCX.pres ℓ a, BCX.abs ℓ b]
      (fun rho => Sat rho ⟨a, [b], {ℓ}⟩) := by
  intro rho
  have key : ∀ σ : Assign,
      BCXModels σ [BCX.eqOut {ℓ} a b, BCX.pres ℓ a, BCX.abs ℓ b] ↔
        (EqOutside {ℓ} (σ a) (σ b) ∧ ℓ ∈ σ a ∧ ℓ ∉ σ b) := by
    intro σ
    constructor
    · intro h
      exact ⟨h (BCX.eqOut {ℓ} a b) (by simp), h (BCX.pres ℓ a) (by simp),
        h (BCX.abs ℓ b) (by simp)⟩
    · rintro ⟨h1, h2, h3⟩ φ hφ
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hφ
      rcases hφ with rfl | rfl | rfl
      · exact h1
      · exact h2
      · exact h3
  constructor
  · rintro ⟨σ, hag, hmod⟩
    have ha : σ a = rho a := hag a (by simp)
    have hb : σ b = rho b := hag b (by simp)
    obtain ⟨h1, h2, h3⟩ := (key σ).mp hmod
    rw [ha, hb] at h1
    rw [ha] at h2
    rw [hb] at h3
    exact (sat_ext_iff rho a b ℓ).mpr ⟨h1, h2, h3⟩
  · intro h
    exact ⟨rho, fun _ _ => rfl, (key rho).mpr ((sat_ext_iff rho a b ℓ).mp h)⟩

/-! ## 6. `=_L` is strictly stronger than `=`

Equality-only systems are preserved by EVERY pointwise map of rows; `=_L` is not.  So
the device does add expressive power -- it just does not add enough. -/

/-- The `eq`-only fragment of `BC`. -/
def IsEq : BC → Prop
  | .eq _ _ => True
  | .eqOut _ _ _ => False

/-- Equality-only systems are preserved by every pointwise map of rows. -/
theorem bcModels_map (F : Row → Row) {Φ : BC → Prop} (hΦ : ∀ φ, Φ φ → IsEq φ)
    {σ : Assign} (h : BCModels σ Φ) : BCModels (fun v => F (σ v)) Φ := by
  intro φ hφ
  cases φ with
  | eq v w =>
      change F (σ v) = F (σ w)
      exact congrArg F (h _ hφ)
  | eqOut L v w => exact absurd (hΦ _ hφ) not_false

/-- **Strictness.**  No equality-only system defines `=_{0}` between two distinct
variables.  Hence `BC` is strictly more expressive than its `eq`-only fragment. -/
theorem not_defines_eqOutside_of_isEq (S : Set Var) (Φ : BC → Prop)
    (hΦ : ∀ φ, Φ φ → IsEq φ) (a b : Var) (hab : a ≠ b) :
    ¬ BCDefines S Φ (fun rho => EqOutside {0} (rho a) (rho b)) := by
  classical
  have hba : b ≠ a := Ne.symm hab
  have e2 : (if b = a then ({0} : Row) else ∅) = ∅ := if_neg hba
  refine not_bcDefines_of_pointwise (fun r => if 0 ∈ r then insert 1 r else r)
    (fun σ h => bcModels_map (fun r => if 0 ∈ r then insert 1 r else r) hΦ h)
    (fun v => if v = a then ({0} : Row) else ∅) ?_ ?_
  · simp only [e2]
    intro l hl
    simp only [Finset.mem_singleton] at hl
    simp [hl]
  · intro hcon
    have h1 : (1 : Label) ∉ ({0} : Finset Label) := by decide
    have hx := hcon 1 h1
    simp only [e2] at hx
    simp at hx

/-! ## 7. What `=_L` genuinely does for Ermine

Everything here is a positive result: partition constraints ENTAIL `=_L` facts, the leaf
expansion of `Rowpartition.Fragment` can be read as one, and the exact gap between `=_L`
and partition can be named. -/

/-- **Partition entails `=_L`.**  Outside its concrete part, the left-hand row of a
satisfied constraint agrees with the union of its variable parts.  This is the `=_L`
shadow of every Ermine constraint. -/
theorem eqOutside_conc_of_sat {rho : Assign} {c : Constraint} (h : Sat rho c) :
    EqOutside c.conc (rho c.lhs) ((c.vars.map rho).foldr (· ∪ ·) ∅) := by
  intro l hl
  rw [h.mem_lhs_iff l, mem_foldr_union]
  simp [hl]

/-- **`=_L` reading of the leaf expansion.**  For every system and every variable, the
row of `a` agrees, outside `kern G a`, with the union of the rows of its leaves. -/
theorem eqOutside_leaves {rho : Assign} {G : List Constraint} (h : Models rho G)
    (a : Var) :
    EqOutside (kern G a) (rho a) (((leaves G a).map rho).foldr (· ∪ ·) ∅) :=
  eqOutside_conc_of_sat (sat_leaves rho G h a)

/-- **On Ermine's actual residuals, `=_L` collapses to `=`.**  All 345 residual
partition constraints measured over the stdlib closure are purely abstract, so
`kern G a = ∅` and `EqOutside ∅` is equality: the leaf expansion is a plain equation and
the exception set has nothing to hold. -/
theorem eq_leaves_of_abstract {rho : Assign} {G : List Constraint} (habs : Abstract G)
    (h : Models rho G) (a : Var) :
    rho a = ((leaves G a).map rho).foldr (· ∪ ·) ∅ := by
  have hx := eqOutside_leaves h a
  rw [kern_eq_empty habs a] at hx
  exact eqOutside_empty.mp hx

/-- **The exact diagnosis.**  Ermine's `a <- (b, c)` IS a `=_L` constraint -- with the
exception set taken to be the row of a VARIABLE, plus disjointness and containment.
Berthomieu's `L` is a constant; that difference is exactly what
`not_defines_partition` measures. -/
theorem sat_two_iff_eqOutside (rho : Assign) (a b c : Var) :
    Sat rho ⟨a, [b, c], ∅⟩ ↔
      EqOutside (rho c) (rho a) (rho b) ∧ Disjoint (rho b) (rho c) ∧ rho c ⊆ rho a := by
  rw [sat_two]
  constructor
  · rintro ⟨hu, -, -, hd⟩
    refine ⟨?_, hd, ?_⟩
    · intro l hl
      rw [hu]
      simp only [Finset.empty_union, Finset.mem_union]
      exact ⟨fun h => h.resolve_right hl, Or.inl⟩
    · rw [hu]
      intro l hl
      simp [hl]
  · rintro ⟨he, hd, hs⟩
    refine ⟨?_, by simp, by simp, hd⟩
    ext l
    simp only [Finset.empty_union, Finset.mem_union]
    constructor
    · intro h
      by_cases hl : l ∈ rho c
      · exact Or.inr hl
      · exact Or.inl ((he l hl).mp h)
    · rintro (h | h)
      · exact (he l (Finset.disjoint_left.mp hd h)).mpr h
      · exact hs h

/-- Determination in Ermine terms: if two rows are known to agree away from a concrete
label set `L`, then their traces on `L` decide equality -- a `|L|`-bit test rather than
a whole-row comparison. -/
theorem eq_iff_inter_of_eqOutside {L : Finset Label} {r s : Row} (h : EqOutside L r s) :
    r = s ↔ r ∩ L = s ∩ L :=
  ⟨fun hrs => by rw [hrs], h.eq_of_inter⟩

/-! ## 8. Ermine's `Has` is out of reach too

`Has a b` abbreviates `∃ c. a <- (b, c)` -- the row `a` contains the row `b`.
Semantically that is row SUBSUMPTION, `rho b ⊆ rho a` (`has_iff_subset`).  The
label-insertion invariance of section 3 does NOT refute it: inserting a label everywhere
preserves inclusions.  A second invariance does.  `BC` is preserved by TOGGLING one
label in every row at once, and toggling turns a row that contains the label into one
that does not, reversing an inclusion. -/

/-- Toggle the membership of `ℓ` in a row -- the symmetric difference `r Δ {ℓ}`, spelled
with `insert`, `∩` and `\` so that no further import is needed. -/
def toggle (ℓ : Label) (r : Row) : Row := (insert ℓ r) \ (r ∩ {ℓ})

theorem mem_toggle_of_ne {ℓ l : Label} {r : Row} (h : l ≠ ℓ) : l ∈ toggle ℓ r ↔ l ∈ r := by
  simp [toggle, h]

theorem mem_toggle_self {ℓ : Label} {r : Row} : ℓ ∈ toggle ℓ r ↔ ℓ ∉ r := by
  simp [toggle]

@[simp] theorem toggle_singleton (ℓ : Label) : toggle ℓ ({ℓ} : Row) = (∅ : Row) := by
  ext l
  by_cases h : l = ℓ
  · subst h; simp [mem_toggle_self]
  · simp [mem_toggle_of_ne h, h]

@[simp] theorem toggle_empty (ℓ : Label) : toggle ℓ (∅ : Row) = ({ℓ} : Row) := by
  ext l
  by_cases h : l = ℓ
  · subst h; simp [mem_toggle_self]
  · simp [mem_toggle_of_ne h, h]

/-- **The second invariance.**  Toggling one label in every variable preserves every
Berthomieu system: equality is a congruence, and `=_L` only ever compares the two sides
at the same label, where toggling negates both. -/
theorem bcModels_toggle (ℓ : Label) {Φ : BC → Prop} {σ : Assign} (h : BCModels σ Φ) :
    BCModels (fun v => toggle ℓ (σ v)) Φ := by
  intro φ hφ
  cases φ with
  | eq v w =>
      change toggle ℓ (σ v) = toggle ℓ (σ w)
      exact congrArg (toggle ℓ) (h _ hφ)
  | eqOut L v w =>
      change EqOutside L (toggle ℓ (σ v)) (toggle ℓ (σ w))
      intro l hl
      have hvw : l ∈ σ v ↔ l ∈ σ w := (h _ hφ : EqOutside L (σ v) (σ w)) l hl
      by_cases hlℓ : l = ℓ
      · subst hlℓ
        rw [mem_toggle_self, mem_toggle_self]
        exact not_congr hvw
      · rw [mem_toggle_of_ne hlℓ, mem_toggle_of_ne hlℓ]
        exact hvw

/-- The same, for the extended language, at a label no literal mentions. -/
theorem bcxModels_toggle {ℓ : Label} {Φ : List BCX} (hℓ : ℓ ∉ litLabels Φ) {σ : Assign}
    (h : BCXModels σ Φ) : BCXModels (fun v => toggle ℓ (σ v)) Φ := by
  intro φ hφ
  have hne : ∀ l : Label, l ∈ litLabel φ → l ≠ ℓ :=
    fun l hl hlℓ => hℓ (hlℓ ▸ mem_litLabels hφ hl)
  cases φ with
  | eq v w =>
      change toggle ℓ (σ v) = toggle ℓ (σ w)
      exact congrArg (toggle ℓ) (h _ hφ)
  | eqOut L v w =>
      change EqOutside L (toggle ℓ (σ v)) (toggle ℓ (σ w))
      intro l hl
      have hvw : l ∈ σ v ↔ l ∈ σ w := (h _ hφ : EqOutside L (σ v) (σ w)) l hl
      by_cases hlℓ : l = ℓ
      · subst hlℓ
        rw [mem_toggle_self, mem_toggle_self]
        exact not_congr hvw
      · rw [mem_toggle_of_ne hlℓ, mem_toggle_of_ne hlℓ]
        exact hvw
  | pres l v =>
      change l ∈ toggle ℓ (σ v)
      exact (mem_toggle_of_ne (hne l (Finset.mem_singleton_self l))).mpr (h _ hφ)
  | abs l v =>
      change l ∉ toggle ℓ (σ v)
      exact fun hm => h _ hφ ((mem_toggle_of_ne (hne l (Finset.mem_singleton_self l))).mp hm)

/-- The residual row of a partition exists exactly when the part is contained in the
whole.  This is the semantics of Ermine's `Has`. -/
theorem exists_partition_iff_subset (r s : Row) :
    (∃ t : Row, r = s ∪ t ∧ Disjoint s t) ↔ s ⊆ r := by
  constructor
  · rintro ⟨t, rfl, -⟩
    exact Finset.subset_union_left
  · intro h
    refine ⟨r \ s, ?_, ?_⟩
    · ext l
      simp only [Finset.mem_union, Finset.mem_sdiff]
      constructor
      · intro hl
        by_cases hs : l ∈ s
        · exact Or.inl hs
        · exact Or.inr ⟨hl, hs⟩
      · rintro (hl | ⟨hl, -⟩)
        · exact h hl
        · exact hl
    · rw [Finset.disjoint_left]
      intro l hl hl'
      exact (Finset.mem_sdiff.mp hl').2 hl

/-- **`Has` is subsumption.**  `∃ c. a <- (b, c)`, with `c` a variable distinct from `a`
and `b` and free to take any value, holds exactly when `rho b ⊆ rho a`. -/
theorem has_iff_subset (rho : Assign) (a b c : Var) (hac : a ≠ c) (hbc : b ≠ c) :
    (∃ t : Row, Sat (fun v => if v = c then t else rho v) ⟨a, [b, c], ∅⟩) ↔
      rho b ⊆ rho a := by
  have key : ∀ t : Row,
      Sat (fun v => if v = c then t else rho v) ⟨a, [b, c], ∅⟩ ↔
        (rho a = rho b ∪ t ∧ Disjoint (rho b) t) := by
    intro t
    rw [sat_two]
    simp [if_neg hac, if_neg hbc]
  simp only [key]
  exact exists_partition_iff_subset (rho a) (rho b)

/-- **Subsumption is not Berthomieu-definable.**  Hence neither is Ermine's `Has`. -/
theorem not_defines_subset (S : Set Var) (Φ : BC → Prop) (a b : Var) (hab : a ≠ b) :
    ¬ BCDefines S Φ (fun rho => rho b ⊆ rho a) := by
  classical
  have hba : b ≠ a := Ne.symm hab
  have e2 : (if b = a then ({0} : Row) else ∅) = ∅ := if_neg hba
  refine not_bcDefines_of_pointwise (toggle 0) (fun σ h => bcModels_toggle 0 h)
    (fun v => if v = a then ({0} : Row) else ∅) ?_ ?_
  · simp only [e2]
    exact Finset.empty_subset _
  · simp only [e2]
    intro hcon
    have h0 : (0 : Label) ∈ toggle 0 (∅ : Row) := by simp
    have hx := hcon h0
    simp at hx

/-- ... and the extended language does not reach it either. -/
theorem not_definesX_subset (S : Set Var) (Φ : List BCX) (a b : Var) (hab : a ≠ b) :
    ¬ BCXDefines S Φ (fun rho => rho b ⊆ rho a) := by
  classical
  obtain ⟨ℓ, hℓ⟩ := exists_fresh (litLabels Φ)
  have hba : b ≠ a := Ne.symm hab
  have e2 : (if b = a then ({ℓ} : Row) else ∅) = ∅ := if_neg hba
  refine not_bcxDefines_of_pointwise (toggle ℓ) (fun σ h => bcxModels_toggle hℓ h)
    (fun v => if v = a then ({ℓ} : Row) else ∅) ?_ ?_
  · simp only [e2]
    exact Finset.empty_subset _
  · simp only [e2]
    intro hcon
    have h0 : ℓ ∈ toggle ℓ (∅ : Row) := by simp
    have hx := hcon h0
    simp at hx

end Rowpartition
