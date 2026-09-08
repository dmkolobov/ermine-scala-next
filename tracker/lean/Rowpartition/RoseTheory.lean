/-
# Ermine's row constraints ARE a row theory in Rose's sense (stage R2)

`tracker/ROSE-COMPARISON.md` §3 rank 2 rejects the correspondence "between Ermine's rule set
and Rose's axioms" -- vacuous in one direction and false in the other -- and keeps the useful
half:

> What to prove instead.  That `⟨Ermine's constraints, =, LoopRel-derivability⟩` **is a row
> theory in Rose's sense**, with the row algebra `⟨𝒫fin(L), ⊎, ∅⟩`, and that there is a **row
> theory homomorphism** into Rose's simple rows.

This file does that at the MODEL level.  Nothing here changes the compiler, and nothing here
is about the loop's *order*: it is a statement about the RELATION `LoopRel`
(`Loop/Refine.lean`) and the semantics `Sat` (`Basic.lean`).

**SOURCES.**  The first round of this stage could not obtain the paper and said so.  The R2
REVIEW obtained it (Morris & McKinna, *Abstracting Extensible Data Types: Or, Rows by Any Other
Name*, PACMPL 3(POPL) art. 12, 2019; the Wayback Machine's 2025-07-21 snapshot of the ACM CC-BY
PDF) and checked every definition clause by clause -- `tracker/loopmodel/R2-REVIEW.md` §1.  Every
quotation below is now from the PAPER, through that review, and the numbering is the paper's:
**Definition 1** the row theory `⟨R, ∼, ⇒⟩`, **Definition 2** the row algebra (a partial monoid)
plus the three conditions for `f : R → M` to be a MODEL, **Definition 6** the row theory
homomorphism.  (The brief's R2.1 swaps 1 and 2; the paper does not.)

**THE FIRST CAVEAT, verbatim from the brief and from `ROSE-COMPARISON.md` §3 rank 2**: `weaken`
deletes and is not monotone in the Definition-1 sense, so the theory is `LoopRel` minus
`weaken`, with deletions handled by `NoLoss`.

**THE SECOND CAVEAT, and it is STRUCTURAL.**  Dropping `weaken` is necessary but *not
sufficient*.  Definition 2's second model condition reads, verbatim:

> If `P ⇒ ψ`, then for each ground substitution `θ` on **`fv(P,ψ)`**, `f ⊨ θP` implies `f ⊨ θψ`.

`θ` ranges over `fv(P, ψ)` -- *including the variables that occur only in the conclusion*.  A
MINT puts a fresh variable in `fv(ψ) \ fv(P)`, where `θ` is free to send it anywhere.  So **no
minting rule can be an entailment rule in Rose's sense, in any row theory**: this is not an
accident of Ermine's rules, it is forced by the definition.  Four of the nine constructors that
survive dropping `weaken` -- `split`, `res`, `splitFree`, `kres` -- mint, so Definition 2's
soundness FAILS for the full non-deleting fragment (`nd_derives_not_entails`, a kernel-checked
witness), and the row theory exhibited here is built on the MINT-FREE non-deleting fragment
`MFStep`.  The dual observation is `ROSE-COMPARISON.md` §1.1's last bullet: Rose's predicate
language has no existential, `type Has a b = exists c. a <- (b, c)` is Ermine's workaround at
the surface, and a mint is the same workaround at solve time.

**WHAT THE MINTING FRAGMENT DOES SATISFY.**  Three statements of increasing strength, all
proved below.  (i) satisfiability preservation, `ndRun_ssat`, from `LoopRel.sat`.  (ii)
model EXTENSION, `ndStep_extend` / `ndRun_extend`: every model of the input extends to a model
of the output, changing only names the input did not have.  (iii) and therefore **Definition 2's
soundness restricted to the input's own vocabulary**, `nd_derives_sound_on_vocab` -- mints
included.  So the mints are outside `⇒` *only for conclusions that mention the minted name*,
which is what a mint is for.  The library already had (iii) for the CSE mint:
`Cut.CseStep.entails_iff` and `Cut.cut_preserves_meaning`, "over the input's own vocabulary,
entail exactly the same constraints".  What is genuinely outside a Definition-2-sound relation
is `weaken` alone.

**WHAT IS NOT A MINT.**  `MFStep.nongen` is `SplitNecessary.NonGenStep`, which bundles six
sub-relations, one of which is `SplitReuseStep` -- `splitConcrete`'s REUSE branch -- and another
`Cut.CutStep`, CSE's reuse and fold.  So `splitConcrete` is not wholly outside `⇒`; only its
minting branch is.

## Three narrowings, and two gaps, all deliberate

* `RowAlgebra.assoc` is the two-sided Kleene equation; **the paper's condition is
  one-directional** ("if `m₁ · (m₂ · m₃)` is defined, then it is equal to `(m₁ · m₂) · m₃`").
  Ours implies the paper's, so every `RowAlgebra` here IS a Rose row algebra -- the safe
  direction -- but the class is smaller.
* `PMap T` carries an explicit `Finset` domain, so `simpleAlgebra T` is the **finite-domain
  sub-algebra** of Example 3's `⟨L ⇀ T, ⊔, ∅⟩`: closed under `⊔`, containing `∅`, a legitimate
  row algebra, but not literally the paper's carrier.
* `AlgHom` is **strict** (it preserves undefinedness too); the paper's partial monoid
  homomorphisms are not required to be.
* **Arity.**  Rose's combination predicate is BINARY and comes with a companion containment
  predicate `≼`; Ermine's `<-` is n-ary and has no `≼`.  One n-ary Ermine constraint is a
  *conjunction* of Rose predicates with an existential intermediate (`ROSE-COMPARISON.md` §1.2:
  `a <- (b,c,d)` is `b ⊙ u ∼ a, c ⊙ d ∼ u`) -- and that intermediate is the same existential the
  mints supply, so the arity gap and the mint failure are one phenomenon.  `sat_iff_pfold` is a
  statement about the ALGEBRA, where the n-ary fold is unimpeachable.
* **`∼` and its lifting.**  Definition 1's `∼` is an equivalence on ROWS, and Ermine's rows are
  `Finset Label`, so Rose's `∼simp` ("identifies sequences up to permutation") really is `=`
  here -- that is `ROSE-COMPARISON.md` §1.1 row 5, and `perm_already_equal` is its instance.  At
  the PREDICATE level the story is different and is stated twice, deliberately: `ermineTheory`
  takes `psim = Eq`, which is the smallest equivalence Definition 1 permits and is forced,
  because permuting a `Constraint`'s `vars` LIST gives a DISTINCT predicate (`perm_ne`) that no
  `MFStep` derivation can produce; `ermineSemTheory` takes `psim = PermSim`, the permutation
  equivalence, and discharges every Definition-1 clause at it (`permSim_sat` proves the model
  set does not move).  The two theories differ only in `⇒`: derivability, versus semantic
  consequence.

## Contents

* §1  Definition 2's row algebras, and Ermine's `⟨𝒫fin(L), ⊎, ∅⟩`
* §2  `Sat` IS the algebra: `sat_iff_pfold`
* §3  Definition 1's row theories
* §4  The two fragments of `LoopRel`, both inclusions, and derivability
* §5  Ermine as a row theory: `ermine_isRowTheory`, `ermineSem_isRowTheory`
* §6  The caveats, as theorems, and the vocabulary-restricted repair
* §7  Rose's simple rows: `SimpleRowTransport`, and **Definition 6** proper
* §8  Non-vacuity, and one incompleteness witness
-/
import Rowpartition.Loop.Strict
import Rowpartition.NameLossClosed

namespace Rowpartition
namespace Rose

open Rowpartition.Loop
open Rowpartition.KeyedRow

/-! ## 1. Rose's Definition 2: row algebras

> *row algebra*: any **partial monoid** `⟨M, ·, ε⟩` (Definition 2).  A model is a map
> `f : R → M` sound for `∼` and for `⇒`.  (`ROSE-COMPARISON.md` §0.)

The memo records the phrase "partial monoid" and not its unfolding, so the unfolding here is
the standard one: a partial binary operation, a two-sided unit, and associativity in the KLEENE
sense (both sides undefined, or both defined and equal), which for an `Option`-valued operation
is the equation on `bind` below.  Partiality is essential and is Rose's own Example 3: `⊔` is
"defined iff the domains are disjoint". -/

/-- **Definition 2 (row algebra).**  A partial monoid `⟨M, op, eps⟩`: `op` is partial
(`Option`-valued), `eps` is a two-sided unit, and `op` is associative in the Kleene sense. -/
structure RowAlgebra (M : Type*) where
  /-- The partial binary operation `·`. -/
  op : M → M → Option M
  /-- The unit `ε`. -/
  eps : M
  /-- `ε` is a left unit, and in particular `op eps m` is always DEFINED. -/
  eps_left : ∀ m, op eps m = some m
  /-- `ε` is a right unit. -/
  eps_right : ∀ m, op m eps = some m
  /-- Kleene associativity.  **NARROWER than the paper**, whose condition is one-directional
  ("if `m₁ · (m₂ · m₃)` is defined, then it is equal to `(m₁ · m₂) · m₃`").  This implies the
  paper's, so every `RowAlgebra` is a Rose row algebra; the class is smaller. -/
  assoc : ∀ a b c, (op a b).bind (fun ab => op ab c) = (op b c).bind (fun bc => op a bc)

namespace RowAlgebra

variable {M : Type*}

/-- The partial fold of the algebra's operation over a list of parts.  `pfold L = some u`
says "the parts `L` combine, and their combination is `u`" -- Rose's n-ary combination
predicate, which is what one Ermine constraint asserts (§2). -/
def pfold (A : RowAlgebra M) : List M → Option M
  | [] => some A.eps
  | m :: ms => (A.pfold ms).bind (fun r => A.op m r)

@[simp] theorem pfold_nil (A : RowAlgebra M) : A.pfold [] = some A.eps := rfl

@[simp] theorem pfold_cons (A : RowAlgebra M) (m : M) (ms : List M) :
    A.pfold (m :: ms) = (A.pfold ms).bind (fun r => A.op m r) := rfl

end RowAlgebra

/-- A presentation of a partial monoid by a TOTAL merge guarded by disjointness of a "key"
row.  Both algebras this file needs -- Ermine's `⟨𝒫fin(L), ⊎, ∅⟩` and Rose's simple rows
`⟨L ⇀ T, ⊔, ∅⟩` -- are of this shape, so the associativity bookkeeping is done once. -/
structure Mergeable (M : Type*) where
  /-- The domain of a value: what disjointness is tested on. -/
  key : M → Row
  /-- The total merge, meaningful only at disjoint keys. -/
  merge : M → M → M
  /-- The unit. -/
  one : M
  /-- The unit has empty key. -/
  key_one : key one = ∅
  /-- Keys add up. -/
  key_merge : ∀ a b, key (merge a b) = key a ∪ key b
  /-- Left unit. -/
  one_merge : ∀ a, merge one a = a
  /-- Right unit. -/
  merge_one : ∀ a, merge a one = a
  /-- Associativity of the total merge. -/
  merge_assoc : ∀ a b c, merge (merge a b) c = merge a (merge b c)

namespace Mergeable

variable {M : Type*}

/-- The partial monoid a `Mergeable` presents: `a · b` is defined exactly when the keys are
disjoint. -/
def toAlgebra (P : Mergeable M) : RowAlgebra M where
  op a b := if Disjoint (P.key a) (P.key b) then some (P.merge a b) else none
  eps := P.one
  eps_left m := by
    have h : Disjoint (P.key P.one) (P.key m) := by rw [P.key_one]; simp
    rw [if_pos h, P.one_merge]
  eps_right m := by
    have h : Disjoint (P.key m) (P.key P.one) := by rw [P.key_one]; simp
    rw [if_pos h, P.merge_one]
  assoc a b c := by
    by_cases hab : Disjoint (P.key a) (P.key b) <;>
      by_cases hbc : Disjoint (P.key b) (P.key c) <;>
        by_cases hac : Disjoint (P.key a) (P.key c) <;>
          simp [hab, hbc, hac, P.key_merge, Finset.disjoint_union_left,
            Finset.disjoint_union_right, P.merge_assoc]

@[simp] theorem toAlgebra_op (P : Mergeable M) (a b : M) :
    P.toAlgebra.op a b = if Disjoint (P.key a) (P.key b) then some (P.merge a b) else none := rfl

@[simp] theorem toAlgebra_eps (P : Mergeable M) : P.toAlgebra.eps = P.one := rfl

end Mergeable

/-- **Ermine's row algebra, as a `Mergeable`**: finite label sets, disjoint union, `∅`.
`ROSE-COMPARISON.md` §1.1 row 1: "finite label sets under **partial** disjoint union; unit
`∅`". -/
def labelMerge : Mergeable Row where
  key := id
  merge := (· ∪ ·)
  one := ∅
  key_one := rfl
  key_merge _ _ := rfl
  one_merge := Finset.empty_union
  merge_one := Finset.union_empty
  merge_assoc := Finset.union_assoc

/-- **Ermine's row algebra `⟨𝒫fin(L), ⊎, ∅⟩`**, a row algebra in the sense of Definition 2. -/
def labelAlgebra : RowAlgebra Row := labelMerge.toAlgebra

@[simp] theorem labelAlgebra_eps : labelAlgebra.eps = (∅ : Row) := rfl

@[simp] theorem labelAlgebra_op (s t : Row) :
    labelAlgebra.op s t = if Disjoint s t then some (s ∪ t) else none := rfl

/-! ## 2. Ermine's `Sat` IS the algebra's combination predicate

This is the step that makes the whole exercise more than a naming convention: `Basic.lean`'s
`Sat` -- "the left-hand row is the union of the parts, and the parts are pairwise disjoint" --
is EXACTLY "the algebra's partial operation, folded over the parts, is defined and equals the
whole".  Nothing about Ermine's semantics has to be adjusted to make it Rose-shaped. -/

/-- A finset is disjoint from a `foldr`-union iff it is disjoint from every member. -/
theorem disjoint_foldr_iff (x : Row) (L : List Row) :
    Disjoint x (L.foldr (· ∪ ·) ∅) ↔ ∀ y ∈ L, Disjoint x y := by
  constructor
  · intro h y hy
    exact h.mono_right (fun l hl => (mem_foldr_union L l).mpr ⟨y, hy, hl⟩)
  · intro h
    rw [Finset.disjoint_left]
    intro l hl hl'
    obtain ⟨y, hy, hly⟩ := (mem_foldr_union L l).mp hl'
    exact (Finset.disjoint_left.mp (h y hy)) hl hly

/-- **The label algebra's fold is disjointness-plus-union.** -/
theorem pfold_label (L : List Row) (u : Row) :
    labelAlgebra.pfold L = some u ↔ (L.Pairwise Disjoint ∧ u = L.foldr (· ∪ ·) ∅) := by
  induction L generalizing u with
  | nil =>
    constructor
    · intro h
      have h' : (∅ : Row) = u := by simpa using h
      exact ⟨List.Pairwise.nil, by simpa using h'.symm⟩
    · rintro ⟨-, rfl⟩
      simp
  | cons x L ih =>
    have hstep : labelAlgebra.pfold (x :: L)
        = (labelAlgebra.pfold L).bind (fun r => labelAlgebra.op x r) := rfl
    rw [hstep]
    cases hp : labelAlgebra.pfold L with
    | none =>
      have hnone : ((none : Option Row).bind fun r => labelAlgebra.op x r) = none := rfl
      rw [hnone]
      constructor
      · intro h; exact absurd h (by simp)
      · rintro ⟨hpw, rfl⟩
        rw [(ih (L.foldr (· ∪ ·) ∅)).mpr ⟨hpw.of_cons, rfl⟩] at hp
        exact absurd hp (by simp)
    | some v =>
      have hsome : ((some v).bind fun r => labelAlgebra.op x r) = labelAlgebra.op x v := rfl
      rw [hsome, labelAlgebra_op]
      obtain ⟨hpw, rfl⟩ := (ih v).mp hp
      simp only [List.pairwise_cons, List.foldr_cons]
      by_cases hd : Disjoint x (L.foldr (· ∪ ·) ∅)
      · rw [if_pos hd]
        simp only [Option.some.injEq]
        constructor
        · rintro rfl
          exact ⟨⟨fun y hy => (disjoint_foldr_iff x L).mp hd y hy, hpw⟩, rfl⟩
        · rintro ⟨-, rfl⟩; rfl
      · rw [if_neg hd]
        constructor
        · intro h; exact absurd h (by simp)
        · rintro ⟨⟨hy, -⟩, rfl⟩
          exact absurd ((disjoint_foldr_iff x L).mpr hy) hd

/-- **One Ermine partition constraint is one combination predicate of the row algebra.**
`Sat rho c` holds exactly when the algebra's operation, folded over `c`'s parts under `rho`,
is DEFINED (that is the disjointness) and equals `rho c.lhs` (that is the completeness). -/
theorem sat_iff_pfold (rho : Assign) (c : Constraint) :
    Sat rho c ↔ labelAlgebra.pfold (parts rho c) = some (rho c.lhs) := by
  simp only [Sat, pfold_label]
  exact and_comm

/-! ## 3. Rose's Definition 1: row theories

The paper, verbatim (R2-REVIEW §1):

> **Definition 1.** A row theory is a 3-tuple ⟨R, ∼, ⇒⟩, as follows.
> • R is a set of syntactic rows (that is, of well-formed **ground** row type expressions). We
>   impose no further restriction on R at this level of abstraction …
> • Relation ∼ is an equivalence relation on R …
> • Relation ⇒ is an entailment relation on row predicates (ζ₁ ≼ ζ₂ and ζ₁ ⊙ ζ₂ ∼ ζ₃), invariant
>   with respect to ∼, satisfying monotonicity (P ⇒ ψ if ψ ∈ P) and transitivity (P, Q ⇒ ϕ if
>   P ⇒ ψ and Q,ψ ⇒ ϕ).

Two readings are this file's, not the paper's, and are flagged as such:

* the context `P` is a `Finset` of predicates.  The paper writes sets, with no finiteness; a
  `System` is finite, so this NARROWS.
* `∼`-invariance is stated with an explicit lifting `psim` of `∼` from rows to predicates and a
  two-sided pointwise correspondence of contexts.  The paper gives no more than the phrase
  "invariant with respect to ∼".

Note "**ground**": Rose's `R` is the ground rows.  Ermine's are the concrete label sets, `Row`
-- NOT `Type.scala`'s `VarT | ConcreteRho`, whose variable case is not ground.  The variables
live in the PREDICATES, where Definition 2's ground substitution `θ` sends them into `R`; and
`θ` is exactly an Ermine `Assign`. -/

/-- **Definition 1 (row theory).**  Syntactic rows `R`, predicates `P`, an equivalence `sim` on
rows with its lifting `psim` to predicates, and an entailment relation `ent` that is monotone,
transitive and `sim`-invariant. -/
structure RowTheory (R : Type*) (P : Type*) [DecidableEq P] where
  /-- `∼`, the equivalence on syntactic rows. -/
  sim : R → R → Prop
  /-- The lifting of `∼` to predicates (this file's reading; see the section docstring). -/
  psim : P → P → Prop
  /-- `⇒`, entailment of a predicate by a finite context. -/
  ent : Finset P → P → Prop
  /-- `∼` is an equivalence. -/
  sim_equivalence : Equivalence sim
  /-- so is its lifting. -/
  psim_equivalence : Equivalence psim
  /-- **Monotonicity**: `P ⇒ ψ` if `ψ ∈ P`. -/
  ent_mono : ∀ {Γ : Finset P} {ψ : P}, ψ ∈ Γ → ent Γ ψ
  /-- **Transitivity**: `P, Q ⇒ φ` if `P ⇒ ψ` and `Q, ψ ⇒ φ`. -/
  ent_trans : ∀ {Γ Δ : Finset P} {ψ φ : P}, ent Γ ψ → ent (insert ψ Δ) φ → ent (Γ ∪ Δ) φ
  /-- **`∼`-invariance**. -/
  ent_sim : ∀ {Γ Γ' : Finset P} {ψ ψ' : P}, ent Γ ψ → psim ψ ψ' →
    (∀ c ∈ Γ, ∃ d ∈ Γ', psim c d) → (∀ d ∈ Γ', ∃ c ∈ Γ, psim d c) → ent Γ' ψ'

/-! ## 4. The two fragments of `LoopRel`, both inclusions, and derivability

`LoopRel` (`Loop/Refine.lean`) has eleven constructors in nine groups.  Two fragments matter:

* `NDStep` -- **`LoopRel` minus `weaken`**, the fragment the brief names.  It is non-deleting
  (`NDStep.subset`), so Definition 1's monotonicity is available; but four of its constructors
  MINT, and a mint is not an entailment (§6).
* `MFStep` -- `NDStep` minus the four minting constructors.  Every step of it preserves MODELS,
  not merely satisfiability, which is Definition 2's soundness condition (`MFStep.models`). -/

/-- **The mint-free non-deleting fragment of `LoopRel`**: `nongen` (CSE reuse and fold,
`splitConcrete`'s syntactic reuse, cancellation, substitution, self-substitution, common
partition) together with the four conclusion-adding constructors `renameLhs`, `linkSymm`,
`emptyProp` and `dedup`.  Constructors are `Loop.LoopRel`'s own, verbatim. -/
inductive MFStep : System → System → Prop
  /-- `SplitNecessary.NonGenStep`, imported unchanged. -/
  | nongen {G G' : System} : NonGenStep G G' → MFStep G G'
  /-- `replace`'s `f p.lhs` -- an alias rewrites the LEFT-hand side. -/
  | renameLhs {G : System} {a b : Var} {S : Finset Var} {K : Row} :
      mk a S K ∈ G → mk a {b} (∅ : Row) ∈ G → MFStep G (insert (mk b S K) G)
  /-- `unify(u, v)` on `v <- (u)` instantiates `u := v`: the link read backwards. -/
  | linkSymm {G : System} {a b : Var} :
      mk a {b} (∅ : Row) ∈ G → MFStep G (insert (mk b {a} (∅ : Row)) G)
  /-- `makeEmpty`'s `aux`: an empty whole forces every part empty. -/
  | emptyProp {G : System} {a x : Var} {S : Finset Var} :
      mk a S (∅ : Row) ∈ G → mk a ∅ (∅ : Row) ∈ G → x ∈ S →
      MFStep G (insert (mk x ∅ (∅ : Row)) G)
  /-- `RHS.merge`'s returned `es`: a variable twice among disjoint parts is empty. -/
  | dedup {G : System} {c v x : Var} {S S' : Finset Var} {K K' : Row} :
      mk c S K ∈ G → mk v S' K' ∈ G → v ∈ S → x ∈ S.erase v → x ∈ S' →
      MFStep G (insert (mk x ∅ (∅ : Row)) G)

/-- **The non-deleting fragment of `LoopRel`**: everything except `weaken`.  The four
constructors `split`, `res`, `splitFree`, `kres` are the MINTING ones. -/
inductive NDStep : System → System → Prop
  /-- the mint-free part -/
  | mf {G G' : System} : MFStep G G' → NDStep G G'
  /-- `splitConcrete`: syntactic, keyed and concrete-row reuse and the MINT. -/
  | split {G G' : System} : K2SplitStep G G' → NDStep G G'
  /-- `resolution`'s MINT. -/
  | res {G G' : System} : ResStep G G' → NDStep G G'
  /-- `splitConcrete`'s MINT under `Cut.SplitApp`'s syntactic guard. -/
  | splitFree {G G' : System} : SplitStep G G' → NDStep G G'
  /-- `resolution`'s guarded and concrete-row reuse. -/
  | kres {G G' : System} : K2ResStep G G' → NDStep G G'

theorem MFStep.toLoopRel {G G' : System} (h : MFStep G G') : LoopRel G G' := by
  cases h with
  | nongen h => exact LoopRel.nongen h
  | renameLhs h1 h2 => exact LoopRel.renameLhs h1 h2
  | linkSymm h1 => exact LoopRel.linkSymm h1
  | emptyProp h1 h2 hx => exact LoopRel.emptyProp h1 h2 hx
  | dedup h1 h2 hv hx hx' => exact LoopRel.dedup h1 h2 hv hx hx'

theorem NDStep.toLoopRel {G G' : System} (h : NDStep G G') : LoopRel G G' := by
  cases h with
  | mf h => exact h.toLoopRel
  | split h => exact LoopRel.split h
  | res h => exact LoopRel.res h
  | splitFree h => exact LoopRel.splitFree h
  | kres h => exact LoopRel.kres h

theorem MFStep.toND {G G' : System} (h : MFStep G G') : NDStep G G' := NDStep.mf h

/-- **The first fragment identity, the hard direction**: every `LoopRel` step is an `NDStep` or
a DELETION.  With `NDStep.toLoopRel` this is "`NDStep` = `LoopRel` minus `weaken`", both ways.
`LoopRel` has **TEN** constructors (`Loop/Refine.lean:345`): `nongen`, `split`, `res`,
`splitFree`, `kres`, `weaken`, `renameLhs`, `linkSymm`, `emptyProp`, `dedup`.  (`ROSE-COMPARISON.md`
§0 says eleven; it is ten -- see that file's dated correction.) -/
theorem loopRel_split {G G' : System} (h : LoopRel G G') : NDStep G G' ∨ G' ⊆ G := by
  cases h with
  | nongen h => exact Or.inl (NDStep.mf (MFStep.nongen h))
  | split h => exact Or.inl (NDStep.split h)
  | res h => exact Or.inl (NDStep.res h)
  | splitFree h => exact Or.inl (NDStep.splitFree h)
  | kres h => exact Or.inl (NDStep.kres h)
  | weaken hsub => exact Or.inr hsub
  | renameLhs h1 h2 => exact Or.inl (NDStep.mf (MFStep.renameLhs h1 h2))
  | linkSymm h1 => exact Or.inl (NDStep.mf (MFStep.linkSymm h1))
  | emptyProp h1 h2 hx => exact Or.inl (NDStep.mf (MFStep.emptyProp h1 h2 hx))
  | dedup h1 h2 hv hx hx' => exact Or.inl (NDStep.mf (MFStep.dedup h1 h2 hv hx hx'))

/-- **The second fragment identity, the hard direction**: every `NDStep` is mint-free or one of
the four minting constructors.  With `MFStep.toND` this is "`MFStep` = `NDStep` minus the four
mints", both ways. -/
theorem ndStep_split {G G' : System} (h : NDStep G G') :
    MFStep G G' ∨ K2SplitStep G G' ∨ ResStep G G' ∨ SplitStep G G' ∨ K2ResStep G G' := by
  cases h with
  | mf h => exact Or.inl h
  | split h => exact Or.inr (Or.inl h)
  | res h => exact Or.inr (Or.inr (Or.inl h))
  | splitFree h => exact Or.inr (Or.inr (Or.inr (Or.inl h)))
  | kres h => exact Or.inr (Or.inr (Or.inr (Or.inr h)))

/-- **The fragment really is non-deleting.**  This is what `weaken` fails and what Definition
1's monotonicity needs. -/
theorem MFStep.subset {G G' : System} (h : MFStep G G') : G ⊆ G' := by
  cases h with
  | nongen h => exact h.subset
  | renameLhs _ _ => exact Finset.subset_insert _ _
  | linkSymm _ => exact Finset.subset_insert _ _
  | emptyProp _ _ _ => exact Finset.subset_insert _ _
  | dedup _ _ _ _ _ => exact Finset.subset_insert _ _

theorem NDStep.subset {G G' : System} (h : NDStep G G') : G ⊆ G' := by
  cases h with
  | mf h => exact h.subset
  | split h => exact h.subset
  | res h => exact h.subset
  | splitFree h => exact h.subset
  | kres h => exact h.subset

/-- **Definition 2's soundness condition, one step at a time**: a mint-free step preserves
every model, not merely satisfiability.  `nongen` is `NonGenStep.models_iff` (an `iff`: "the
model set never moves"); the other four are `Refine.lean`'s `*_sat` lemmas. -/
theorem MFStep.models {G G' : System} (h : MFStep G G') {rho : Assign} (hm : SModels rho G) :
    SModels rho G' := by
  cases h with
  | nongen h => exact (h.models_iff rho).mp hm
  | renameLhs h1 h2 =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact renameLhs_sat (hm _ h1) (hm _ h2)
    · exact hm c hc'
  | linkSymm h1 =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact linkSymm_sat (hm _ h1)
    · exact hm c hc'
  | emptyProp h1 h2 hx =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact emptyProp_sat (hm _ h1) (hm _ h2) hx
    · exact hm c hc'
  | dedup h1 h2 hv hx hx' =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact dedup_sat (hm _ h1) (hm _ h2) hv hx hx'
    · exact hm c hc'

/-- The mint-free fragment in the library's own vocabulary: it **loses nothing**
(`Loop.NoLoss`, trivially, because it deletes nothing) and **invents nothing**
(`Loop.Conserv`), which together are model-set EQUALITY.  `Conserv` is exactly Definition 2's
soundness condition read constraint by constraint, and it is what a MINT fails. -/
theorem MFStep.noLoss {G G' : System} (h : MFStep G G') : NoLoss G G' :=
  NoLoss.of_subset h.subset

theorem MFStep.conserv {G G' : System} (h : MFStep G G') : Conserv G G' :=
  fun c hc _ hm => h.models hm c hc

/-- **Mint-free steps lift along inclusion.**  For `nongen` this is
`NameLossClosed.NonGenStep.mono`; for the other four every premise is a membership. -/
theorem MFStep.mono {G H G' : System} (hGH : G ⊆ H) (h : MFStep G G') :
    ∃ H', MFStep H H' ∧ G' ⊆ H' := by
  cases h with
  | nongen h =>
    obtain ⟨H', hH', hsub⟩ := NameLoss.NonGenStep.mono hGH h
    exact ⟨H', MFStep.nongen hH', hsub⟩
  | renameLhs h1 h2 =>
    exact ⟨_, MFStep.renameLhs (hGH h1) (hGH h2), Finset.insert_subset_insert _ hGH⟩
  | linkSymm h1 =>
    exact ⟨_, MFStep.linkSymm (hGH h1), Finset.insert_subset_insert _ hGH⟩
  | emptyProp h1 h2 hx =>
    exact ⟨_, MFStep.emptyProp (hGH h1) (hGH h2) hx, Finset.insert_subset_insert _ hGH⟩
  | dedup h1 h2 hv hx hx' =>
    exact ⟨_, MFStep.dedup (hGH h1) (hGH h2) hv hx hx', Finset.insert_subset_insert _ hGH⟩

/-- **Plain derivability**: `c` is reached by a run of `Step` from `G`. -/
def Derives (Step : System → System → Prop) (G : System) (c : Constraint) : Prop :=
  ∃ H : System, Relation.ReflTransGen Step G H ∧ c ∈ H

/-- **Derivability in every context**, which is what an ENTAILMENT relation must be: `c` is
derivable not only from `G` but from every system that contains `G`.  This is the library's
own `Refine.Adds` idiom ("A constraint the relation can add to ANY system reachable from `G`
that still contains `G`"), and it is what makes Definition 1's transitivity provable without a
frame lemma for the minting rules -- whose freshness side conditions have none. -/
def Ent (Step : System → System → Prop) (G : System) (c : Constraint) : Prop :=
  ∀ H : System, G ⊆ H → Derives Step H c

theorem Ent.derives {Step : System → System → Prop} {G : System} {c : Constraint}
    (h : Ent Step G c) : Derives Step G c := h G (Finset.Subset.refl G)

/-- **Definition 1's monotonicity**, for any step relation. -/
theorem ent_of_mem {Step : System → System → Prop} {G : System} {c : Constraint} (hc : c ∈ G) :
    Ent Step G c := fun _ hGH => ⟨_, Relation.ReflTransGen.refl, hGH hc⟩

/-- A run of a non-deleting relation is non-deleting. -/
theorem run_subset {Step : System → System → Prop}
    (hs : ∀ G G' : System, Step G G' → G ⊆ G') {G H : System}
    (h : Relation.ReflTransGen Step G H) : G ⊆ H := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep ih => exact ih.trans (hs _ _ hstep)

/-- **Definition 1's transitivity**, for any NON-DELETING step relation. -/
theorem ent_trans {Step : System → System → Prop}
    (hs : ∀ G G' : System, Step G G' → G ⊆ G') {Γ Δ : System} {ψ φ : Constraint}
    (h1 : Ent Step Γ ψ) (h2 : Ent Step (insert ψ Δ) φ) : Ent Step (Γ ∪ Δ) φ := by
  intro H hH
  obtain ⟨H1, hrun1, hψ⟩ := h1 H (fun c hc => hH (Finset.mem_union_left _ hc))
  have hHH1 : H ⊆ H1 := run_subset hs hrun1
  obtain ⟨H2, hrun2, hφ⟩ := h2 H1 (by
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact hψ
    · exact hHH1 (hH (Finset.mem_union_right _ hc')))
  exact ⟨H2, hrun1.trans hrun2, hφ⟩

/-- **Definition 1's `∼`-invariance**, for `∼` = `=`: free, as `ROSE-COMPARISON.md` §3 rank 2
says it is ("`∼`-invariance -- free, `mk` takes a `Finset`"). -/
theorem ent_eq_inv {Step : System → System → Prop} {Γ Γ' : System} {ψ ψ' : Constraint}
    (h : Ent Step Γ ψ) (hp : ψ = ψ') (h1 : ∀ c ∈ Γ, ∃ d ∈ Γ', c = d)
    (h2 : ∀ d ∈ Γ', ∃ c ∈ Γ, d = c) : Ent Step Γ' ψ' := by
  subst hp
  have hΓ : Γ = Γ' := by
    ext a
    constructor
    · intro ha; obtain ⟨d, hd, rfl⟩ := h1 a ha; exact hd
    · intro ha; obtain ⟨c, hc, rfl⟩ := h2 a ha; exact hc
  exact hΓ ▸ h

/-- `∼`-invariance AT THE LEVEL OF ROWS, spelt out: permuting a row's own members is
EQUALITY, because `mk`'s argument is a `Finset` (`mk a S k = ⟨a, slist S, k⟩` canonicalises).
This is what `ROSE-COMPARISON.md` §1.1 row 5 means by "Rose's `∼simp` … is Ermine's `Set`", and
it is Definition 1's `∼` clause, which is about rows.  It is NOT a statement about permuting a
PREDICATE's right-hand side -- see `perm_ne` and `PermSim` in §5. -/
theorem perm_already_equal (a x y z : Var) (K : Row) : mk a {x, y, z} K = mk a {z, x, y} K := by
  have h : ({x, y, z} : Finset Var) = {z, x, y} := by ext v; simp; tauto
  rw [h]

/-- Runs of the mint-free fragment lift along inclusion. -/
theorem mfRun_mono {G H G' : System} (hGH : G ⊆ H)
    (h : Relation.ReflTransGen MFStep G G') :
    ∃ H', Relation.ReflTransGen MFStep H H' ∧ G' ⊆ H' := by
  induction h with
  | refl => exact ⟨H, Relation.ReflTransGen.refl, hGH⟩
  | @tail b c _ hstep ih =>
    obtain ⟨H1, hrun1, hb⟩ := ih
    obtain ⟨H2, hstep2, hc⟩ := MFStep.mono hb hstep
    exact ⟨H2, hrun1.tail hstep2, hc⟩

/-- **The context closure costs NOTHING on the mint-free fragment**: `Ent MFStep` and
`Derives MFStep` are the same relation, so Ermine's `⇒` is plain derivability and `Ent` was not
chosen to make transitivity cheap at the price of a smaller `⇒`.  It costs something only on
`NDStep`, where the minting rules' freshness side condition has no frame lemma -- which is
exactly why §6's open question is stated there and not here. -/
theorem ent_iff_derives {G : System} {c : Constraint} :
    Ent MFStep G c ↔ Derives MFStep G c := by
  constructor
  · exact Ent.derives
  · rintro ⟨H, hrun, hc⟩ H0 hGH0
    obtain ⟨H', hrun', hsub⟩ := mfRun_mono hGH0 hrun
    exact ⟨H', hrun', hsub hc⟩

/-- **The mint-free fragment is NON-GENERATIVE**: it never touches the vocabulary.  `nongen` is
`DefaultTerm.NonGenStep.allVars_eq`; the other four insert a constraint over variables the
premises already mention. -/
theorem MFStep.allVars {G G' : System} (h : MFStep G G') : allVars G' = allVars G := by
  have hsub := allVars_mono h.subset
  refine Finset.Subset.antisymm ?_ hsub
  cases h with
  | nongen h => exact le_of_eq h.allVars_eq
  | @renameLhs a b S K h1 h2 =>
    intro v hv
    obtain ⟨d, hd, hvd⟩ := Finset.mem_biUnion.mp hv
    rcases Finset.mem_insert.mp hd with rfl | hd'
    · rcases Finset.mem_insert.mp hvd with rfl | hv'
      · exact mem_allVars h2 (Or.inr (by simp))
      · exact mem_allVars h1 (Or.inr (by simpa using hv'))
    · exact Finset.mem_biUnion.mpr ⟨d, hd', hvd⟩
  | @linkSymm a b h1 =>
    intro v hv
    obtain ⟨d, hd, hvd⟩ := Finset.mem_biUnion.mp hv
    rcases Finset.mem_insert.mp hd with rfl | hd'
    · rcases Finset.mem_insert.mp hvd with rfl | hv'
      · exact mem_allVars h1 (Or.inr (by simp))
      · have hva : v = a := by simpa using hv'
        exact hva ▸ lhs_mem_allVars h1
    · exact Finset.mem_biUnion.mpr ⟨d, hd', hvd⟩
  | @emptyProp a x S h1 h2 hx =>
    intro v hv
    obtain ⟨d, hd, hvd⟩ := Finset.mem_biUnion.mp hv
    rcases Finset.mem_insert.mp hd with rfl | hd'
    · have hvx : v = x := by simpa using hvd
      exact hvx ▸ mem_allVars h1 (Or.inr (by simpa using hx))
    · exact Finset.mem_biUnion.mpr ⟨d, hd', hvd⟩
  | @dedup c w x S S' K K' h1 h2 hv hx hx' =>
    intro v hvv
    obtain ⟨d, hd, hvd⟩ := Finset.mem_biUnion.mp hvv
    rcases Finset.mem_insert.mp hd with rfl | hd'
    · have hvx : v = x := by simpa using hvd
      exact hvx ▸ mem_allVars h2 (Or.inr (by simpa using hx'))
    · exact Finset.mem_biUnion.mpr ⟨d, hd', hvd⟩

theorem mfRun_allVars {G H : System} (h : Relation.ReflTransGen MFStep G H) :
    allVars H = allVars G := by
  induction h with
  | refl => rfl
  | tail _ hstep ih => rw [MFStep.allVars hstep]; exact ih

/-! ## 5. Ermine as a row theory

Rose's `R` is the set of GROUND rows, so Ermine's `R` is `Row = Finset Label`, the model map
`f` is the identity (a ground Ermine row IS an element of the algebra), and Rose's ground
substitution `θ` is an Ermine `Assign`.  `Type.scala`'s `VarT | ConcreteRho` is NOT `R`: its
variable case is not ground, and those variables are exactly what `θ` sends into `R`. -/

/-- **Definition 2's `ζ₀`**: `f(ζ₀) = ε` outright, with `f = id`.  At the SOLVER level, where
a row expression is always a variable (`PQueue.build` mints a variable for a non-variable
left-hand side), the empty row is not a row but is SAID by the constraint `a <- ()`;
`zeta0_constraint` records that reading too. -/
def zeta0 : Row := ∅

@[simp] theorem f_zeta0 : (id : Row → Row) zeta0 = labelAlgebra.eps := rfl

/-- The solver-level reading of `ζ₀`: `a <- ()` says exactly `f(a) = ε`. -/
theorem zeta0_constraint (rho : Assign) (a : Var) :
    Sat rho (mk a ∅ (∅ : Row)) ↔ rho a = labelAlgebra.eps := sat_empty_iff

/-- **Ermine's entailment relation `⇒`**: derivability, in every context, in the mint-free
non-deleting fragment of `LoopRel`.  By `ent_iff_derives` this is plain derivability. -/
abbrev EEnt : System → Constraint → Prop := Ent MFStep

/-- **`⇒` is sound for the algebra** -- Definition 2's second condition.  Assembled from
`NonGenStep.models_iff` and `Refine.lean`'s four `*_sat` lemmas through `MFStep.models`. -/
theorem mfRun_models {G H : System} (h : Relation.ReflTransGen MFStep G H) {rho : Assign}
    (hm : SModels rho G) : SModels rho H := by
  induction h with
  | refl => exact hm
  | tail _ hstep ih => exact hstep.models ih

theorem eEnt_sound {G : System} {c : Constraint} (h : EEnt G c) : SEntails G c := by
  intro rho hm
  obtain ⟨H, hrun, hc⟩ := h.derives
  exact mfRun_models hrun hm c hc

/-- **Ermine's row theory** `⟨Row, =, ⇒⟩`: Definition 1's clauses, discharged.  `∼` is `=` on
ROWS, which is the correct instance and not a discretisation (`perm_already_equal`); `psim` is
`=` on PREDICATES, which is the smallest lifting Definition 1 permits and is FORCED here,
because permuting a `Constraint`'s `vars` list gives a distinct predicate (`perm_ne`) that no
`MFStep` derivation produces.  `ermineSemTheory` below is the same predicates and the same
algebra with `psim` the full permutation equivalence, at the price of taking `⇒` semantic. -/
def ermineTheory : RowTheory Row Constraint where
  sim := Eq
  psim := Eq
  ent := EEnt
  sim_equivalence := eq_equivalence
  psim_equivalence := eq_equivalence
  ent_mono := ent_of_mem
  ent_trans h1 h2 := Rose.ent_trans (fun _ _ h => h.subset) h1 h2
  ent_sim h hp h1 h2 := ent_eq_inv h hp h1 h2

/-- **Definition 2's conditions for a MODEL**, in the paper's own shape: `f : R → M`, a ground
substitution `θ : Var → R`, and `f ⊨ θψ` written `hold θ ψ`.  `conc` reads a constraint's
concrete part as a ground row.

`pred_algebraic` is not one of the three bulleted conditions; it is the paper's DEFINITION of
`⊨`, "we write `f ⊨ ζ₁ ⊙ ζ₂ ∼ ζ₃` if `f(ζ₁) · f(ζ₂) = f(ζ₃)`", recast n-arily because Ermine's
`Sat` is given independently in `Basic.lean` and has to be shown to agree.  Without it `hold`
could be any relation and the model conditions would say nothing about the algebra.

The three conditions proper are CONDITIONS, not theorems -- `ROSE-COMPARISON.md` §2 row 4:
"Soundness of `⇒` against the semantics is a **condition in Definition 2** for a map `f : R → M`
to count as a *model* … not a theorem." -/
structure IsModel {R M : Type*} (A : RowAlgebra M) (T : RowTheory R Constraint)
    (f : R → M) (conc : Row → R) (hold : (Var → R) → Constraint → Prop) (z : R) : Prop where
  /-- `∼`-soundness: `ζ₁ ∼ ζ₂` implies `f(ζ₁) = f(ζ₂)` -/
  sim_sound : ∀ z₁ z₂, T.sim z₁ z₂ → f z₁ = f z₂
  /-- the paper's definition of `⊨`, n-arily -/
  pred_algebraic : ∀ (θ : Var → R) (c : Constraint),
    hold θ c ↔
      A.pfold (f (conc c.conc) :: c.vars.map (fun v => f (θ v))) = some (f (θ c.lhs))
  /-- **soundness of `⇒` for the algebra**, over every ground substitution -/
  ent_sound : ∀ (Γ : System) (ψ : Constraint), T.ent Γ ψ →
    ∀ θ : Var → R, (∀ c ∈ Γ, hold θ c) → hold θ ψ
  /-- a `ζ₀ ∈ R` with `f(ζ₀) = ε` -/
  unit : f z = A.eps

/-- **THE MAIN THEOREM.**  Ermine's partition constraints, with `∼` = `=` on rows and `⇒` =
derivability in the mint-free non-deleting fragment of `LoopRel`, are a ROW THEORY in Rose's
Definition-1 sense (`ermineTheory`), and the identity on ground rows makes `Sat` a MODEL over
the row algebra `⟨𝒫fin(L), ⊎, ∅⟩` in Rose's Definition-2 sense, with `ζ₀ = (||)`. -/
theorem ermine_isRowTheory : IsModel labelAlgebra ermineTheory id id Sat zeta0 where
  sim_sound _ _ h := by rw [h]
  pred_algebraic rho c := sat_iff_pfold rho c
  ent_sound _ _ h rho hm := eEnt_sound h rho hm
  unit := f_zeta0

/-! ### The permutation equivalence, and the second row theory

`ermineTheory.psim` is `Eq`, which Definition 1 permits and which the derivability relation
forces.  Rose's `∼simp` "identifies sequences up to permutation"; at the predicate level that is
`PermSim`, and it is NOT `Eq` on `Constraint`, whose `vars` field is a `List`.  Everything below
discharges Definition 1 at `PermSim` -- for the SEMANTIC entailment relation, which is a row
theory over the same algebra and the one Definition 13 (R3) lives in. -/

/-- Rose's `∼simp` at the predicate level: same whole, same concrete part, and the variable
parts permuted.  Multiplicity is kept -- `dedup` exists precisely because `[x, x]` and `[x]` are
NOT interchangeable. -/
def PermSim (c d : Constraint) : Prop :=
  c.lhs = d.lhs ∧ c.vars.Perm d.vars ∧ c.conc = d.conc

theorem permSim_equivalence : Equivalence PermSim where
  refl _ := ⟨rfl, List.Perm.refl _, rfl⟩
  symm h := ⟨h.1.symm, h.2.1.symm, h.2.2.symm⟩
  trans h1 h2 := ⟨h1.1.trans h2.1, h1.2.1.trans h2.2.1, h1.2.2.trans h2.2.2⟩

/-- Permuted right-hand sides are DISTINCT predicates: the reviewer's witness, as a theorem. -/
theorem perm_ne : (⟨0, [1, 2], (∅ : Row)⟩ : Constraint) ≠ ⟨0, [2, 1], (∅ : Row)⟩ := by decide

/-- **… with identical model sets.**  Invariance of the semantics under the permutation
equivalence: the parts differ by a permutation, and both halves of `Sat` -- the union and the
pairwise disjointness -- are permutation-invariant. -/
theorem permSim_sat {c d : Constraint} (h : PermSim c d) (rho : Assign) :
    Sat rho c ↔ Sat rho d := by
  have hp : (parts rho c).Perm (parts rho d) := by
    rw [parts, parts, h.2.2]
    exact (h.2.1.map rho).cons _
  have hfold : (parts rho c).foldr (· ∪ ·) ∅ = (parts rho d).foldr (· ∪ ·) ∅ := by
    ext l
    simp only [mem_foldr_union]
    exact ⟨fun ⟨t, ht, hl⟩ => ⟨t, hp.mem_iff.mp ht, hl⟩,
      fun ⟨t, ht, hl⟩ => ⟨t, hp.mem_iff.mpr ht, hl⟩⟩
  have hpw : (parts rho c).Pairwise Disjoint ↔ (parts rho d).Pairwise Disjoint :=
    hp.pairwise_iff (fun hd => hd.symm)
  simp only [Sat, h.1, hfold, hpw]

/-- Two systems that correspond pointwise up to `PermSim` have the same models. -/
def PermSimSys (Γ Γ' : System) : Prop :=
  (∀ c ∈ Γ, ∃ d ∈ Γ', PermSim c d) ∧ (∀ d ∈ Γ', ∃ c ∈ Γ, PermSim d c)

theorem permSimSys_models {Γ Γ' : System} (h : PermSimSys Γ Γ') {rho : Assign}
    (hm : SModels rho Γ) : SModels rho Γ' := by
  intro d hd
  obtain ⟨c, hc, hsim⟩ := h.2 d hd
  exact (permSim_sat hsim rho).mpr (hm c hc)

/-- **`SEntails` IS invariant under the permutation equivalence** -- Definition 1's
`∼`-invariance clause, discharged at Rose's `∼simp` rather than at the discrete equivalence. -/
theorem permSim_sEntails {Γ Γ' : System} {ψ ψ' : Constraint} (h : SEntails Γ ψ)
    (hψ : PermSim ψ ψ') (hΓ : PermSimSys Γ Γ') : SEntails Γ' ψ' := by
  intro rho hm
  exact (permSim_sat hψ rho).mp
    (h rho (permSimSys_models ⟨hΓ.2, hΓ.1⟩ hm))

/-- **The second row theory**: the same rows, the same predicates and the same algebra, with
`⇒` the SEMANTIC consequence relation and `∼` lifted to predicates as Rose's `∼simp`.  Every
Definition-1 clause is discharged at the permutation equivalence.  This is the row theory in
which Rose's Definition 13 (the determinacy closure R3 needs) is stated: Definition 13 mentions
neither `⇒` nor models, only the predicates. -/
def ermineSemTheory : RowTheory Row Constraint where
  sim := Eq
  psim := PermSim
  ent := SEntails
  sim_equivalence := eq_equivalence
  psim_equivalence := permSim_equivalence
  ent_mono := fun hc _ hm => hm _ hc
  ent_trans := fun {Γ Δ ψ φ} h1 h2 rho hm => by
    refine h2 rho ?_
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact h1 rho (fun d hd => hm d (Finset.mem_union_left _ hd))
    · exact hm c (Finset.mem_union_right _ hc')
  ent_sim := fun h hψ h1 h2 => permSim_sEntails h hψ ⟨h1, h2⟩

/-- and it is a model in Definition 2's sense too, for the same algebra and the same `ζ₀`. -/
theorem ermineSem_isRowTheory : IsModel labelAlgebra ermineSemTheory id id Sat zeta0 where
  sim_sound _ _ h := by rw [h]
  pred_algebraic rho c := sat_iff_pfold rho c
  ent_sound _ _ h rho hm := h rho hm
  unit := f_zeta0

/-- **OPEN, and the reason `ermineTheory.psim` is `Eq`.**  Discharging Definition 1's
`∼`-invariance at `PermSim` for the DERIVABILITY relation would need every `MFStep` constructor
to be replayable modulo a permutation of right-hand sides.  It is not available cheaply: the
constructors' premises are memberships of `mk`-BUILT constraints (`mk a S K = ⟨a, slist S, K⟩`),
and a `PermSim`-variant of such a premise is a different `Constraint`, so nothing matches.
Proving it means proving permutation-invariance for `NonGenStep`'s six sub-relations, which live
in other modules.  Stated as a `Prop`, in the library's `Goal_*` idiom. -/
def Goal_eEnt_permInvariant : Prop :=
  ∀ (Γ Γ' : System) (ψ ψ' : Constraint),
    EEnt Γ ψ → PermSim ψ ψ' → PermSimSys Γ Γ' → EEnt Γ' ψ'

/-! ## 6. The caveats, as theorems, and the vocabulary-restricted repair

Two conditions of the definitions FAIL for wider fragments, both failures are exhibited rather
than asserted -- and the minting failure is then REPAIRED, on the vocabulary the input already
had (`nd_derives_sound_on_vocab`), which is the statement that explains why the compiler's
mints are harmless. -/

/-- **`weaken` deletes.**  It is `LoopRel`'s only non-monotone constructor, and this is why
the theory is `LoopRel` MINUS `weaken`.  The library's own record of what the deletions cost is
`Loop.weaken_not_strict` (`weaken` fails `NoLoss`); this is the syntactic half. -/
theorem weaken_not_subset : ∃ G G' : System, LoopRel G G' ∧ ¬ G ⊆ G' := by
  refine ⟨{mk 0 ∅ (∅ : Row)}, ∅, LoopRel.weaken (Finset.empty_subset _), ?_⟩
  intro h
  exact absurd (h (Finset.mem_singleton_self _)) (Finset.notMem_empty _)

/-- The satisfiability-level soundness the MINTING fragment does have: `LoopRel.sat`,
"every constructor preserves satisfiability".  This is a CONSERVATIVE EXTENSION statement, not
an entailment: it says the minted system still has a model, not that every model of the input
is one. -/
theorem ndRun_ssat {G H : System} (h : Relation.ReflTransGen NDStep G H) : SSat G → SSat H := by
  induction h with
  | refl => exact id
  | tail _ hstep ih => exact fun hs => hstep.toLoopRel.sat (ih hs)

/-- The full non-deleting fragment still meets **Definition 1** -- it is non-deleting, so
monotonicity and transitivity go through unchanged.  What it does NOT meet is Definition 2's
soundness (`nd_derives_not_entails`). -/
def ndTheory : RowTheory Row Constraint where
  sim := Eq
  psim := Eq
  ent := Ent NDStep
  sim_equivalence := eq_equivalence
  psim_equivalence := eq_equivalence
  ent_mono := ent_of_mem
  ent_trans h1 h2 := Rose.ent_trans (fun _ _ h => h.subset) h1 h2
  ent_sim h hp h1 h2 := ent_eq_inv h hp h1 h2

namespace MintWitness

/-! ### The mint is not an entailment

`splitConcrete` on `a <- (x, y, (|ℓ|))` mints `u` and emits `u <- (x, y)`.  Every model of the
input that gives `u` a nonempty row refutes the emitted constraint, because `u` is unconstrained
in the input.  Variables `a = 0`, `x = 1`, `y = 2`, `u = 3`; the single label is `0`. -/

/-- the premise `a <- (x, y, (|ℓ|))` -/
def c₀ : Constraint := mk 0 ({1, 2} : Finset Var) ({0} : Row)

/-- the one-constraint input system -/
def G₀ : System := {c₀}

/-- the minted variable -/
def u : Var := 3

/-- what `splitConcrete` emits over it -/
def minted : Constraint := mk u ({1, 2} : Finset Var) (∅ : Row)

theorem fresh_u : u ∉ allVars G₀ := by
  simp [allVars, G₀, c₀, u]

theorem unnamed : ¬ Named G₀ (vset c₀) := by
  rintro ⟨d, hd, -, hconc⟩
  rw [G₀, Finset.mem_singleton] at hd
  subst hd
  simp [c₀] at hconc

theorem splitApp : SplitApp G₀ c₀ u where
  mem := Finset.mem_singleton_self _
  conc_ne := by simp [c₀]
  two_le := by simp only [c₀, vset_mk]; decide
  unnamed := unnamed
  fresh := fresh_u

/-- one non-deleting step: `splitConcrete`'s mint -/
theorem step : NDStep G₀ (splitResult G₀ c₀ u) := NDStep.splitFree (SplitStep.intro splitApp)

theorem minted_mem : minted ∈ splitResult G₀ c₀ u := by
  have h : minted = mk u (vset c₀) (∅ : Row) := by simp [minted, c₀]
  rw [h, splitResult]
  exact Finset.mem_insert_self _ _

theorem derives : Derives NDStep G₀ minted :=
  ⟨_, Relation.ReflTransGen.single step, minted_mem⟩

/-- the model of the input that refutes the minted constraint -/
def rho₀ : Assign := fun v => if v = 1 ∨ v = 2 then (∅ : Row) else ({0} : Row)

theorem rho₀_parts (v : Var) (hv : v ∈ ({1, 2} : Finset Var)) : rho₀ v = ∅ := by
  rcases Finset.mem_insert.mp hv with rfl | hv'
  · simp [rho₀]
  · rw [Finset.mem_singleton] at hv'; subst hv'; simp [rho₀]

theorem models : SModels rho₀ G₀ := by
  intro c hc
  rw [G₀, Finset.mem_singleton] at hc
  subst hc
  rw [c₀, sat_mk_iff]
  refine ⟨by simp [rho₀], ?_, ?_⟩
  · intro v hv; rw [rho₀_parts v hv]; simp
  · intro v hv w hw _; rw [rho₀_parts v hv, rho₀_parts w hw]; simp

theorem not_sat_minted : ¬ Sat rho₀ minted := by
  rw [minted, sat_mk_iff]
  rintro ⟨he, -, -⟩
  simp [rho₀, u] at he

theorem not_entails : ¬ SEntails G₀ minted := fun h => not_sat_minted (h rho₀ models)

end MintWitness

/-- **Definition 2's soundness condition FAILS for the full non-deleting fragment.**  `weaken`
is not the only constructor that has to go: a MINT adds a constraint over a variable the input
does not constrain, so plain derivability in `LoopRel` minus `weaken` is not entailment.  This
is `Loop/Strict.lean`'s `Conserv` ("A MINT fails this (the fresh variable is unconstrained by
`G`)") turned into a witness. -/
theorem nd_derives_not_entails :
    ∃ (G : System) (c : Constraint), Derives NDStep G c ∧ ¬ SEntails G c :=
  ⟨MintWitness.G₀, MintWitness.minted, MintWitness.derives, MintWitness.not_entails⟩

/-- **The gap between `LoopRel.sat` and Definition 2's soundness, on one witness.**  The
minting step preserves SATISFIABILITY (`LoopRel.sat`, and so `ndRun_ssat`) and fails
`Loop.Conserv` -- it invents a constraint the input does not entail.  The brief's R2.2 (2)
expected Definition 2's soundness to come "from `LoopRel.sat`, restricted to the fragment";
these two lines are why it cannot, and why `EEnt` is built on `MFStep`. -/
theorem split_not_conserv :
    ¬ Conserv MintWitness.G₀ (splitResult MintWitness.G₀ MintWitness.c₀ MintWitness.u) :=
  fun h => MintWitness.not_entails (h MintWitness.minted MintWitness.minted_mem)

theorem split_preserves_ssat :
    SSat MintWitness.G₀ → SSat (splitResult MintWitness.G₀ MintWitness.c₀ MintWitness.u) :=
  fun h => (MintWitness.step.toLoopRel).sat h

/-! ### The repair: the minting fragment IS Definition-2 sound on the input's vocabulary

`nd_derives_not_entails` says a mint's conclusion need not be entailed.  It says so about a
conclusion whose left-hand side is the MINTED name, and that is the only case.  Restrict the
conclusion to the vocabulary the input already had and the FULL non-deleting fragment -- mints
included -- satisfies Definition 2's soundness condition.

Every ingredient was already in the library; nothing new is proved here, five lemmas are
assembled: `KeyedRow.K2SplitStep.extend`, `KeyedRow.K2ResStep.extend`, `Rowpartition.mint_extend`
(resolution), `SplitNecessary.split_mint_conservativeExt`, and `Divergence.sat_congr_of_agree`.
The library already carries the same statement for the CSE mint -- `Cut.CseStep.entails_iff`,
`Cut.CseBranch.entails_iff`, and `Cut.cut_preserves_meaning`, whose wording is "over the input's
own vocabulary, entail exactly the same constraints". -/

/-- **Every non-deleting step extends every model, changing only fresh names.** -/
theorem ndStep_extend {G G' : System} (h : NDStep G G') {rho : Assign}
    (hm : SModels rho G) : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | mf h => exact ⟨rho, h.models hm, fun _ _ => rfl⟩
  | split h => exact K2SplitStep.extend hm h
  | kres h => exact K2ResStep.extend hm h
  | res h =>
    cases h with
    | @intro v x y C D z happ =>
      exact Rowpartition.mint_extend ⟨happ.mem₁, happ.mem₂, happ.tops, happ.bots⟩ happ.fresh hm
  | splitFree h =>
    cases h with
    | @intro c u happ =>
      obtain ⟨rho', hag, hm'⟩ := (split_mint_conservativeExt happ).1 rho hm
      exact ⟨rho', hm', fun v hv => hag v (fun hh => happ.fresh (hh ▸ hv))⟩

theorem ndRun_extend {G H : System} (h : Relation.ReflTransGen NDStep G H) {rho : Assign}
    (hm : SModels rho G) : ∃ rho', SModels rho' H ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  induction h with
  | refl => exact ⟨rho, hm, fun _ _ => rfl⟩
  | @tail B C hrun hstep ih =>
    obtain ⟨rho1, hm1, hag1⟩ := ih
    obtain ⟨rho2, hm2, hag2⟩ := ndStep_extend hstep hm1
    exact ⟨rho2, hm2, fun v hv =>
      (hag2 v (allVars_mono (run_subset (fun _ _ h => h.subset) hrun) hv)).trans (hag1 v hv)⟩

/-- **THE REPAIR.**  Derivability in the FULL non-deleting fragment -- mints included -- IS
Definition 2's soundness, provided the derived constraint is phrased in the vocabulary the input
already had.  `nd_derives_not_entails` is not a counterexample to this: its minted `u <- (x, y)`
has `u ∉ allVars G₀`, which is the whole point of a mint. -/
theorem nd_derives_sound_on_vocab {G : System} {c : Constraint}
    (h : Derives NDStep G c) (hlhs : c.lhs ∈ allVars G) (hvs : vset c ⊆ allVars G) :
    SEntails G c := by
  obtain ⟨H, hrun, hc⟩ := h
  intro rho hm
  obtain ⟨rho', hm', hag⟩ := ndRun_extend hrun hm
  refine (sat_congr_of_agree (rho := rho) (rho' := rho') ?_).mpr (hm' c hc)
  rintro v (rfl | hv)
  · exact (hag _ hlhs).symm
  · exact (hag _ (hvs hv)).symm

/-- … and therefore for the context-closed reading as well. -/
theorem nd_ent_sound_on_vocab {G : System} {c : Constraint}
    (h : Ent NDStep G c) (hlhs : c.lhs ∈ allVars G) (hvs : vset c ⊆ allVars G) :
    SEntails G c := nd_derives_sound_on_vocab h.derives hlhs hvs

/-- **OPEN, and a curiosity rather than the question that matters.**  `nd_derives_sound_on_vocab`
settles the minting fragment for every conclusion inside the input's vocabulary; what is left
open is only the conclusions OUTSIDE it, under the CONTEXT-CLOSED reading.  `Ent NDStep G c`
demands a derivation of `c` from EVERY `H ⊇ G`, and a mint of a NAMED variable is blocked in any
`H` that already mentions it -- so `nd_derives_not_entails` (a `Derives`, not an `Ent`) does not
refute it.  **PROVING** it needs a closure argument over the five rule families, of the kind
`NameLossClosed.lean` carries: that no derivation from a blocking `H` reaches such a conclusion.
**REFUTING** it needs the opposite, a construction whose conclusion survives freshness blocking
in every context -- for instance a mint composed with `emptyProp`/`dedup`/`renameLhs` so that
what survives names only old variables.  (The first round of this stage stated these two
directions the wrong way round.) -/
def Goal_nd_ent_sound_off_vocab : Prop :=
  ∀ (G : System) (c : Constraint), Ent NDStep G c → SEntails G c

/-! ## 7. Rose's simple rows: the two notions the paper distinguishes

Example 3's carrier is *partial functions* from `L` to `T` with `⊔` defined iff the domains are
disjoint, and `⟨L ⇀ T, ⊔, ∅⟩` is ASSERTED (footnote 2, not proved) to be an algebra for the
simple row theory.  Ermine's algebra is that one composed with `dom`, `T` collapsed to a point
(`ROSE-COMPARISON.md` §1.1 row 2).

**The paper keeps TWO notions apart, and so does this section.**  Definition 6, verbatim:

> **Definition 6.** A function h : R₁ → R₂, extended to predicates in the obvious fashion, is a
> **row theory homomorphism** (or simply: homomorphism) from ⟨R, ∼, ⇒⟩ to ⟨R′, ∼′, ⇒′⟩ if
> ζ₁ ∼ ζ₂ implies that h(ζ₁) ∼′ h(ζ₂) and P ⇒ ψ implies that h(P) ⇒′ h(ψ).
>
> **Row algebras are related by partial monoid homomorphisms.** … Given that f is a model of
> ⟨R, ∼, ⇒⟩ in ⟨M, ·, ϵ⟩, and g is a model of ⟨R′, ∼′, ⇒′⟩ in ⟨M′, ·′, ϵ′⟩, if there is a row
> theory homomorphism from R to R′, then there is a corresponding partial monoid homomorphism
> from M to M′. **Under the same assumptions, if there is a partial monoid homomorphism j from M
> to M′, and for every ζ ∈ R, there is a ζ′ ∈ R′ such that j(f(ζ)) = g(ζ′), there is a row theory
> homomorphism from R to R′.**

So Definition 6 has exactly two clauses, both SYNTACTIC, on a map between syntactic row sets.
It says nothing about `⊎`, nothing about `ε` and nothing about models.  Maps of ALGEBRAS are the
paper's separate notion, named in the very next sentence.

**The first round of this stage got this wrong** and called its algebra-plus-transport bundle
"Definition 6"; `ROSE-COMPARISON.md` §3 rank 2's own bullet ("the inclusion composed with
`dom : (L ⇀ T) → 𝒫(L)`") is the same misreading, and `dom` runs OUT of Rose's algebra into
Ermine's besides.  Both are corrected here and in that file.  This section now carries:

* `dom_hom`, `lift_algHom` -- the paper's **partial monoid homomorphisms**;
* `SimpleRowTransport` -- one of those bundled with model-level transport of `SEntails`.  A
  useful notion, and NOT Definition 6;
* `Def6Hom` -- **Definition 6 itself**, stated with the two clauses of the quotation, and
  `ermine_to_simple_hom`, which discharges it into `simpleTheory tau`.

**The obstruction, and what `simpleTheory` costs.**  Definition 6 into Rose's OWN simple row
theory -- the one whose `⇒′` is `⇒simp` -- is out of reach, for two reasons worth recording.
(i) `⇒simp`'s two ground axiom schemes fire only on fully spelt-out rows (`ROSE-COMPARISON.md`
§1.3), so `Witness.ent_x` (`{a <- (x,y), a <- ()} ⇒ x <- ()`) has no `⇒simp` counterpart; and
§1.3's finding is that `⇒simp` derives NONE of Ermine's eleven rules.  (ii) "h extended to
predicates in the obvious fashion" is not well defined here: `Basic.lean`'s `Constraint` is
`⟨lhs : Var, vars : List Var, conc⟩`, so **Ermine has no ground predicates at all** -- every
constraint is over variables, and a map on rows induces a map on predicates only once an
assignment is supplied.  `Def6Hom` therefore takes the extension `hp` as DATA, and
`ermine_to_simple_hom` supplies `id`, which works because `simpleTheory tau`'s predicates are
the same `Constraint` syntax read in the other algebra.  What `simpleTheory tau` is NOT is
Rose's `⇒simp`: its `⇒′` is the SEMANTIC consequence relation of the simple-row algebra along
the `tau`-slice.  Definition 6 quantifies over any two row theories, so that is a legitimate
target -- but the target must be named honestly, and it is.

**The paper's bridge** is the other route, and its side condition is exactly the `tau`-slice:
`bridge_side_condition` below.  Here it is cheap, because a ground simple row IS an element of
the simple-row algebra (`g = id`), so the bridge reduces to surjectivity of `g`.  The bridge
itself is prose in the paper and is not proved there or here. -/

/-- Rose's Example-3 carrier `L ⇀ T`: a partial map from labels to field types, as a total
function into `Option T` with an explicit finite domain. -/
structure PMap (T : Type*) where
  /-- the partial function -/
  fn : Label → Option T
  /-- its domain -/
  dom : Row
  /-- the domain is the domain -/
  dom_spec : ∀ l, l ∈ dom ↔ (fn l).isSome

namespace PMap

variable {T : Type*}

/-- Left-biased choice on `Option`, which is what `⊔` is on a disjoint overlap. -/
def orFirst (x y : Option T) : Option T :=
  match x with
  | some t => some t
  | none => y

@[simp] theorem orFirst_none (y : Option T) : orFirst (none : Option T) y = y := rfl

@[simp] theorem orFirst_some (t : T) (y : Option T) : orFirst (some t) y = some t := rfl

theorem orFirst_none_right (x : Option T) : orFirst x (none : Option T) = x := by
  cases x <;> rfl

theorem orFirst_assoc (x y z : Option T) :
    orFirst (orFirst x y) z = orFirst x (orFirst y z) := by
  cases x <;> rfl

@[simp] theorem isSome_orFirst (x y : Option T) :
    (orFirst x y).isSome = (x.isSome || y.isSome) := by
  cases x <;> simp

/-- Two partial maps with the same function are equal: the domain is determined. -/
theorem ext' {m n : PMap T} (h : ∀ l, m.fn l = n.fn l) : m = n := by
  obtain ⟨f, d, hd⟩ := m
  obtain ⟨f', d', hd'⟩ := n
  have hf : f = f' := funext h
  subst hf
  have hdd : d = d' := Finset.ext fun l => (hd l).trans (hd' l).symm
  subst hdd
  rfl

/-- The empty partial map: Rose's `∅`. -/
def one (T : Type*) : PMap T where
  fn := fun _ => none
  dom := ∅
  dom_spec := by simp

/-- The union of two partial maps, meaningful at disjoint domains: Rose's `⊔`. -/
def merge (m n : PMap T) : PMap T where
  fn l := orFirst (m.fn l) (n.fn l)
  dom := m.dom ∪ n.dom
  dom_spec l := by
    simp only [Finset.mem_union, m.dom_spec l, n.dom_spec l, isSome_orFirst, Bool.or_eq_true]

@[simp] theorem dom_one (T : Type*) : (one T).dom = ∅ := rfl

@[simp] theorem fn_one (T : Type*) (l : Label) : (one T).fn l = none := rfl

@[simp] theorem dom_merge (m n : PMap T) : (merge m n).dom = m.dom ∪ n.dom := rfl

@[simp] theorem fn_merge (m n : PMap T) (l : Label) :
    (merge m n).fn l = orFirst (m.fn l) (n.fn l) := rfl

theorem one_merge (m : PMap T) : merge (one T) m = m := ext' fun _ => by simp

theorem merge_one (m : PMap T) : merge m (one T) = m :=
  ext' fun l => by simp [orFirst_none_right]

theorem merge_assoc (a b c : PMap T) : merge (merge a b) c = merge a (merge b c) :=
  ext' fun l => by simp [orFirst_assoc]

end PMap

/-- Rose's simple-row algebra as a `Mergeable`. -/
def pmapMerge (T : Type*) : Mergeable (PMap T) where
  key := PMap.dom
  merge := PMap.merge
  one := PMap.one T
  key_one := rfl
  key_merge _ _ := rfl
  one_merge := PMap.one_merge
  merge_one := PMap.merge_one
  merge_assoc := PMap.merge_assoc

/-- **Rose's simple-row algebra `⟨L ⇀ T, ⊔, ∅⟩`** (Example 3), a row algebra in the sense of
Definition 2. -/
def simpleAlgebra (T : Type*) : RowAlgebra (PMap T) := (pmapMerge T).toAlgebra

@[simp] theorem simpleAlgebra_eps (T : Type*) : (simpleAlgebra T).eps = PMap.one T := rfl

@[simp] theorem simpleAlgebra_op {T : Type*} (m n : PMap T) :
    (simpleAlgebra T).op m n =
      if Disjoint m.dom n.dom then some (PMap.merge m n) else none := rfl

/-- A homomorphism of row algebras.  STRICT: it preserves definedness in both directions,
which is what "preserves `⊎`" has to mean for a PARTIAL operation. -/
structure AlgHom {M N : Type*} (A : RowAlgebra M) (B : RowAlgebra N) (h : M → N) : Prop where
  /-- it preserves `ε` -/
  map_eps : h A.eps = B.eps
  /-- it preserves `⊎`, definedness included -/
  map_op : ∀ a b, (A.op a b).map h = B.op (h a) (h b)

/-- A homomorphism transports the n-ary combination predicate. -/
theorem AlgHom.pfold {M N : Type*} {A : RowAlgebra M} {B : RowAlgebra N} {h : M → N}
    (H : AlgHom A B h) (L : List M) : (A.pfold L).map h = B.pfold (L.map h) := by
  induction L with
  | nil => simp [H.map_eps]
  | cons x L ih =>
    simp only [RowAlgebra.pfold_cons, List.map_cons]
    cases hp : A.pfold L with
    | none =>
      have hb : B.pfold (L.map h) = none := by rw [hp] at ih; simpa using ih.symm
      simp [hb]
    | some v =>
      have hb : B.pfold (L.map h) = some (h v) := by rw [hp] at ih; simpa using ih.symm
      have hl : ((some v).bind fun r => A.op x r) = A.op x v := rfl
      have hr : ((some (h v)).bind fun r => B.op (h x) r) = B.op (h x) (h v) := rfl
      rw [hb, hl, hr]
      exact H.map_op x v

/-- **`dom` is a row-algebra homomorphism** from Rose's simple rows onto Ermine's label sets.
This is `ROSE-COMPARISON.md` §1.1 row 2 as a theorem: Ermine's algebra is Rose's simple-row
algebra composed with `dom`, `T` collapsed to a point. -/
theorem dom_hom (T : Type*) : AlgHom (simpleAlgebra T) labelAlgebra PMap.dom where
  map_eps := rfl
  map_op m n := by
    simp only [simpleAlgebra_op, labelAlgebra_op]
    split <;> simp

/-- The section: a label set becomes a partial map once a field type is chosen for each label.
`lift tau` is the map INTO Rose's simple rows the brief asks for. -/
def lift {T : Type*} (tau : Label → T) (K : Row) : PMap T where
  fn l := if l ∈ K then some (tau l) else none
  dom := K
  dom_spec l := by by_cases h : l ∈ K <;> simp [h]

@[simp] theorem dom_lift {T : Type*} (tau : Label → T) (K : Row) : (lift tau K).dom = K := rfl

@[simp] theorem fn_lift {T : Type*} (tau : Label → T) (K : Row) (l : Label) :
    (lift tau K).fn l = if l ∈ K then some (tau l) else none := rfl

theorem lift_injective {T : Type*} (tau : Label → T) : Function.Injective (lift tau) :=
  fun _ _ h => by simpa using congrArg PMap.dom h

theorem lift_union {T : Type*} (tau : Label → T) (s t : Row) :
    lift tau (s ∪ t) = PMap.merge (lift tau s) (lift tau t) :=
  PMap.ext' fun l => by
    by_cases h1 : l ∈ s <;> by_cases h2 : l ∈ t <;> simp [h1, h2]

/-- **The algebra half of the homomorphism (R2.3).**  `lift tau` maps Ermine's row algebra
`⟨𝒫fin(L), ⊎, ∅⟩` into Rose's simple rows `⟨L ⇀ T, ⊔, ∅⟩`, preserving `⊎` (definedness
included) and `ε`.  Its retraction is `dom` (`dom_lift`), which is a homomorphism the other way
(`dom_hom`); at `T = Unit` the two are mutually inverse (`lift_dom_unit`), which is the exact
sense in which Ermine IMPLEMENTS Rose's simple row theory. -/
theorem lift_algHom {T : Type*} (tau : Label → T) :
    AlgHom labelAlgebra (simpleAlgebra T) (lift tau) where
  map_eps := PMap.ext' fun l => by simp
  map_op s t := by
    simp only [labelAlgebra_op, simpleAlgebra_op, dom_lift]
    by_cases hd : Disjoint s t
    · simp [hd, lift_union]
    · simp [hd]

/-- At `T = Unit`, `lift` and `dom` are mutually inverse: **Ermine's row algebra IS Rose's
simple-row algebra with the field types collapsed to a point.** -/
theorem lift_dom_unit (m : PMap Unit) : lift (fun _ => ()) m.dom = m :=
  PMap.ext' fun l => by
    by_cases h : l ∈ m.dom
    · have hs : (m.fn l).isSome := (m.dom_spec l).mp h
      cases hm : m.fn l with
      | none => rw [hm] at hs; simp at hs
      | some x => cases x; simp [h]
    · have hs : ¬ (m.fn l).isSome := fun hs => h ((m.dom_spec l).mpr hs)
      cases hm : m.fn l with
      | none => simp [h]
      | some x => rw [hm] at hs; simp at hs

/-- One Ermine constraint read as a combination predicate in the SIMPLE row algebra: the field
types of the concrete part are supplied by `tau`, because an Ermine row has nowhere to carry
them (`ROSE-COMPARISON.md` §1.1 row 2). -/
def SatS {T : Type*} (tau : Label → T) (sigma : Var → PMap T) (c : Constraint) : Prop :=
  (simpleAlgebra T).pfold (lift tau c.conc :: c.vars.map sigma) = some (sigma c.lhs)

/-- **Every Rose simple-row model is an Ermine model**, via `dom`. -/
theorem satS_dom {T : Type*} (tau : Label → T) (sigma : Var → PMap T) (c : Constraint)
    (h : SatS tau sigma c) : Sat (fun v => (sigma v).dom) c := by
  rw [sat_iff_pfold]
  have hh := (dom_hom T).pfold (lift tau c.conc :: c.vars.map sigma)
  rw [SatS] at h
  rw [h] at hh
  simpa [parts, List.map_map, Function.comp_def] using hh.symm

/-- **On the `tau`-slice the two satisfaction relations AGREE.**  Together with `satS_dom` this
is the precise sense in which Ermine's predicates are Rose's simple-row predicates. -/
theorem satS_lift_iff {T : Type*} (tau : Label → T) (rho : Assign) (c : Constraint) :
    SatS tau (fun v => lift tau (rho v)) c ↔ Sat rho c := by
  have hmap : lift tau c.conc :: c.vars.map (fun v => lift tau (rho v))
      = (parts rho c).map (lift tau) := by
    simp [parts, List.map_map, Function.comp_def]
  rw [SatS, hmap, ← (lift_algHom tau).pfold, sat_iff_pfold]
  cases hp : labelAlgebra.pfold (parts rho c) with
  | none => simp
  | some v =>
    simp only [Option.map_some, Option.some.injEq]
    exact ⟨fun h => lift_injective tau h, fun h => congrArg (lift tau) h⟩

/-- **The homomorphism preserves entailment.**  Every Ermine entailment -- in particular every
`⇒` of `ermineTheory`, by `eEnt_sound` -- is an entailment of the simple-row reading, along the
section `lift tau`. -/
theorem ermine_to_simple_entails {T : Type*} (tau : Label → T) {G : System} {c : Constraint}
    (h : SEntails G c) (rho : Assign)
    (hm : ∀ d ∈ G, SatS tau (fun v => lift tau (rho v)) d) :
    SatS tau (fun v => lift tau (rho v)) c :=
  (satS_lift_iff tau rho c).mpr (h rho fun d hd => (satS_lift_iff tau rho d).mp (hm d hd))

theorem eEnt_to_simple {T : Type*} (tau : Label → T) {G : System} {c : Constraint}
    (h : EEnt G c) (rho : Assign)
    (hm : ∀ d ∈ G, SatS tau (fun v => lift tau (rho v)) d) :
    SatS tau (fun v => lift tau (rho v)) c :=
  ermine_to_simple_entails tau (eEnt_sound h) rho hm

/-- **NOT Definition 6.**  A partial monoid homomorphism of the two algebras bundled with
model-level transport of the predicates and of `SEntails`.  The paper has both halves, but
under its OTHER heading ("Row algebras are related by partial monoid homomorphisms") and with
no `pred` clause at all -- `pred` is a semantic coherence condition of this file's.  Named for
what it is. -/
structure SimpleRowTransport {T : Type*} (tau : Label → T) (h : Row → PMap T) : Prop where
  /-- the row map is a PARTIAL MONOID homomorphism: it preserves `⊎` and `ε` -/
  alg : AlgHom labelAlgebra (simpleAlgebra T) h
  /-- it transports the PREDICATES: an Ermine constraint is the same assertion read in the
  simple-row algebra along the map -/
  pred : ∀ (rho : Assign) (c : Constraint), Sat rho c ↔ SatS tau (fun v => h (rho v)) c
  /-- and therefore SEMANTIC consequence -/
  ent : ∀ (G : System) (c : Constraint), SEntails G c →
    ∀ rho : Assign, (∀ d ∈ G, SatS tau (fun v => h (rho v)) d) →
      SatS tau (fun v => h (rho v)) c

/-- For every choice `tau` of field types, `lift tau` transports Ermine's row algebra, its
predicates and its semantic consequence into Rose's simple rows.  Composed with `dom` it is the
identity (`dom_lift`), and at `T = Unit` the two are mutually inverse (`lift_dom_unit`). -/
theorem ermine_to_simple_transport {T : Type*} (tau : Label → T) :
    SimpleRowTransport tau (lift tau) where
  alg := lift_algHom tau
  pred rho c := (satS_lift_iff tau rho c).symm
  ent _ _ h rho hm := ermine_to_simple_entails tau h rho hm

/-- **Definition 6 (row theory homomorphism), verbatim in its two clauses**: a function
`h : R₁ → R₂` on SYNTACTIC rows, together with its extension `hp` to predicates, such that
`∼` maps into `∼′` and `⇒` maps into `⇒′`.

`hp` is a PARAMETER, not derived.  The paper says "extended to predicates in the obvious
fashion"; Ermine has no ground predicates for that to mean anything (§7's docstring), so the
extension must be supplied. -/
structure Def6Hom {R₁ P₁ R₂ P₂ : Type*} [DecidableEq P₁] [DecidableEq P₂]
    (T₁ : RowTheory R₁ P₁) (T₂ : RowTheory R₂ P₂) (h : R₁ → R₂) (hp : P₁ → P₂) : Prop where
  /-- `ζ₁ ∼ ζ₂` implies `h(ζ₁) ∼′ h(ζ₂)` -/
  map_sim : ∀ z₁ z₂, T₁.sim z₁ z₂ → T₂.sim (h z₁) (h z₂)
  /-- `P ⇒ ψ` implies `h(P) ⇒′ h(ψ)` -/
  map_ent : ∀ (Γ : Finset P₁) (ψ : P₁), T₁.ent Γ ψ → T₂.ent (Γ.image hp) (hp ψ)

/-- Satisfaction of an Ermine constraint in the simple-row algebra, along the `tau`-slice. -/
def SatSlice {T : Type*} (tau : Label → T) (rho : Assign) (c : Constraint) : Prop :=
  SatS tau (fun v => lift tau (rho v)) c

/-- **The TARGET row theory.**  Rows are Rose's ground simple rows `L ⇀ T`, `∼′` is `=`, and
`⇒′` is SEMANTIC consequence in the simple-row algebra along the `tau`-slice.  This is a row
theory over Rose's simple-row ALGEBRA; it is **not** Rose's `⇒simp`, which derives none of
Ermine's rules (`ROSE-COMPARISON.md` §1.3) and into which no Definition-6 map is available. -/
def simpleTheory {T : Type*} (tau : Label → T) : RowTheory (PMap T) Constraint where
  sim := Eq
  psim := Eq
  ent := fun Γ ψ => ∀ rho : Assign, (∀ d ∈ Γ, SatSlice tau rho d) → SatSlice tau rho ψ
  sim_equivalence := eq_equivalence
  psim_equivalence := eq_equivalence
  ent_mono := fun hc _ hm => hm _ hc
  ent_trans := fun {Γ Δ ψ φ} h1 h2 rho hm => by
    refine h2 rho ?_
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact h1 rho (fun d hd => hm d (Finset.mem_union_left _ hd))
    · exact hm c (Finset.mem_union_right _ hc')
  ent_sim := fun {Γ Γ' ψ ψ'} h hp h1 h2 => by
    subst hp
    have hΓ : Γ = Γ' := by
      ext a
      constructor
      · intro ha; obtain ⟨d, hd, rfl⟩ := h1 a ha; exact hd
      · intro ha; obtain ⟨c, hc, rfl⟩ := h2 a ha; exact hc
    exact hΓ ▸ h

/-- **THE HOMOMORPHISM (R2.3), and it really is Definition 6.**  `lift tau` on ground rows,
with the identity on predicates, is a row theory homomorphism from `ermineTheory` to
`simpleTheory tau`: it maps `∼` into `∼′` and `⇒` into `⇒′`.  The `⇒` clause is the composite
`eEnt_sound` then `satS_lift_iff` -- i.e. Ermine's derivability, made semantic, read in the
simple-row algebra.  What is NOT claimed is a map into Rose's `⇒simp`; see §7's docstring. -/
theorem ermine_to_simple_hom {T : Type*} (tau : Label → T) :
    Def6Hom ermineTheory (simpleTheory tau) (lift tau) id where
  map_sim _ _ h := congrArg (lift tau) h
  map_ent Γ ψ h := by
    rw [Finset.image_id]
    intro rho hm
    exact (satS_lift_iff tau rho ψ).mpr
      (eEnt_sound h rho (fun d hd => (satS_lift_iff tau rho d).mp (hm d hd)))

/-- **The paper's bridge, side condition discharged.**  The bridge asks for a partial monoid
homomorphism `j` from `M` to `M′` such that for every `ζ ∈ R` there is a `ζ′ ∈ R′` with
`j(f(ζ)) = g(ζ′)`.  Take `j = lift tau` (`lift_algHom`), `f = id` and `g = id`: the condition
holds, and CHOOSING `tau` is choosing the witness family -- so the bridge's side condition and
this module's `tau`-slice are the same restriction.  It is cheap here only because a ground
simple row IS an element of the simple-row algebra.  The bridge's conclusion is prose in the
paper and is not proved there or here; `ermine_to_simple_hom` reaches Definition 6 directly
instead. -/
theorem bridge_side_condition {T : Type*} (tau : Label → T) (z : Row) :
    ∃ z' : PMap T, lift tau (id z) = id z' := ⟨lift tau z, rfl⟩

/-! ## 8. Non-vacuity, and one incompleteness witness (R2.5)

Concrete constraint sets, derivations in the fragment, and models.  `Witness` and
`LiveRules` are the NON-VACUITY: `EEnt` is not the empty relation, every constructor of `MFStep`
is inhabited, and `IsModel` is not vacuously satisfied.  `taut_entailed` together with
`eEnt_empty_false` is the opposite kind of fact and is labelled as such -- an INCOMPLETENESS
witness for the exhibited `⇒`, which is honest because Definition 2 asks only for soundness. -/

namespace Witness

/-! `G = { a <- (x, y), a <- () }` at `a = 0`, `x = 1`, `y = 2`.  Two `emptyProp` steps derive
`x <- ()` and `y <- ()`. -/

/-- `a <- (x, y)` -/
def cAll : Constraint := mk 0 ({1, 2} : Finset Var) (∅ : Row)

/-- `a <- ()` -/
def cEmpty : Constraint := mk 0 (∅ : Finset Var) (∅ : Row)

/-- the input -/
def G : System := {cAll, cEmpty}

theorem cAll_mem : cAll ∈ G := Finset.mem_insert_self _ _

theorem cEmpty_mem : cEmpty ∈ G := Finset.mem_insert_of_mem (Finset.mem_singleton_self _)

/-- `x <- ()` is derivable in the mint-free fragment from EVERY context containing `G`. -/
theorem ent_x : EEnt G (mk 1 ∅ (∅ : Row)) := by
  intro H hGH
  refine ⟨insert (mk 1 ∅ (∅ : Row)) H, Relation.ReflTransGen.single ?_,
    Finset.mem_insert_self _ _⟩
  exact MFStep.emptyProp (hGH cAll_mem) (hGH cEmpty_mem) (by decide)

/-- and so is `y <- ()` -/
theorem ent_y : EEnt G (mk 2 ∅ (∅ : Row)) := by
  intro H hGH
  refine ⟨insert (mk 2 ∅ (∅ : Row)) H, Relation.ReflTransGen.single ?_,
    Finset.mem_insert_self _ _⟩
  exact MFStep.emptyProp (hGH cAll_mem) (hGH cEmpty_mem) (by decide)

/-- **soundness, instantiated**: what `⇒` derives, `⊨` entails -/
theorem entails_x : SEntails G (mk 1 ∅ (∅ : Row)) := eEnt_sound ent_x

/-- a two-step run of the fragment reaching both conclusions at once -/
theorem run_both : ∃ H : System, Relation.ReflTransGen MFStep G H ∧
    mk 1 ∅ (∅ : Row) ∈ H ∧ mk 2 ∅ (∅ : Row) ∈ H := by
  have s1 : MFStep G (insert (mk 1 ∅ (∅ : Row)) G) :=
    MFStep.emptyProp cAll_mem cEmpty_mem (by decide)
  have s2 : MFStep (insert (mk 1 ∅ (∅ : Row)) G)
      (insert (mk 2 ∅ (∅ : Row)) (insert (mk 1 ∅ (∅ : Row)) G)) :=
    MFStep.emptyProp (Finset.mem_insert_of_mem cAll_mem)
      (Finset.mem_insert_of_mem cEmpty_mem) (by decide)
  exact ⟨_, (Relation.ReflTransGen.single s1).tail s2,
    Finset.mem_insert_of_mem (Finset.mem_insert_self _ _), Finset.mem_insert_self _ _⟩

/-- the model -/
def rhoW : Assign := fun _ => ∅

theorem models : SModels rhoW G := by
  intro c hc
  rcases Finset.mem_insert.mp hc with rfl | hc'
  · rw [cAll, sat_mk_iff]; exact ⟨by simp [rhoW], by simp [rhoW], by simp [rhoW]⟩
  · rw [Finset.mem_singleton] at hc'
    subst hc'
    rw [cEmpty, sat_mk_iff]; exact ⟨by simp [rhoW], by simp [rhoW], by simp [rhoW]⟩

/-- and it is a model of the derived conclusion too, as soundness says it must be -/
theorem models_conclusion : Sat rhoW (mk 1 ∅ (∅ : Row)) := entails_x rhoW models

/-- the same instance in the SIMPLE-ROW reading, at `T = Unit` -/
theorem simple_models :
    ∀ d ∈ G, SatS (fun _ => ()) (fun v => lift (fun _ => ()) (rhoW v)) d :=
  fun d hd => (satS_lift_iff (fun _ => ()) rhoW d).mpr (models d hd)

end Witness

namespace LiveRules

/-! ### Every constructor of `MFStep` is inhabited

`Witness` exercises `emptyProp` only.  These three cover the rest, so no branch of the fragment
is dead, and `dedup_sound` is a second non-trivial entailment derived from a non-empty system.
(`nongen` is `NonGenStep`, whose six sub-relations are instantiated throughout the library.) -/

/-- `dedup`: `G = { 0 <- (1,2), 1 <- (2) }` derives `2 <- ()`. -/
theorem dedup_live :
    MFStep {mk 0 ({1, 2} : Finset Var) (∅ : Row), mk 1 ({2} : Finset Var) (∅ : Row)}
      (insert (mk 2 ∅ (∅ : Row))
        {mk 0 ({1, 2} : Finset Var) (∅ : Row), mk 1 ({2} : Finset Var) (∅ : Row)}) :=
  MFStep.dedup (Finset.mem_insert_self _ _)
    (Finset.mem_insert_of_mem (Finset.mem_singleton_self _)) (by decide) (by decide) (by decide)

/-- **A second non-vacuity instance, with a non-trivial conclusion**: `⇒` derives `2 <- ()` from
a two-constraint system that says nothing about `2` being empty, and soundness turns that into
an `SEntails`. -/
theorem dedup_sound :
    SEntails {mk 0 ({1, 2} : Finset Var) (∅ : Row), mk 1 ({2} : Finset Var) (∅ : Row)}
      (mk 2 ∅ (∅ : Row)) :=
  eEnt_sound (fun H hGH =>
    ⟨_, Relation.ReflTransGen.single
      (MFStep.dedup (hGH (Finset.mem_insert_self _ _))
        (hGH (Finset.mem_insert_of_mem (Finset.mem_singleton_self _)))
        (by decide) (by decide) (by decide)),
     Finset.mem_insert_self _ _⟩)

/-- `renameLhs`: `G = { 0 <- (5,6), 0 <- (1) }` derives `1 <- (5,6)`. -/
theorem renameLhs_live :
    MFStep {mk 0 ({5, 6} : Finset Var) (∅ : Row), mk 0 ({1} : Finset Var) (∅ : Row)}
      (insert (mk 1 ({5, 6} : Finset Var) (∅ : Row))
        {mk 0 ({5, 6} : Finset Var) (∅ : Row), mk 0 ({1} : Finset Var) (∅ : Row)}) :=
  MFStep.renameLhs (Finset.mem_insert_self _ _)
    (Finset.mem_insert_of_mem (Finset.mem_singleton_self _))

/-- `linkSymm`: `G = { 0 <- (1) }` derives `1 <- (0)`. -/
theorem linkSymm_live :
    MFStep {mk 0 ({1} : Finset Var) (∅ : Row)}
      (insert (mk 1 ({0} : Finset Var) (∅ : Row)) {mk 0 ({1} : Finset Var) (∅ : Row)}) :=
  MFStep.linkSymm (Finset.mem_singleton_self _)

end LiveRules

/-- The tautology `a <- (a)` is SEMANTICALLY entailed by the EMPTY system --
`ROSE-COMPARISON.md` §4.5's `Goal_taut_is_trivial`, and the reason `Subst.mkSimplified`
publishing it is noise rather than information (§3 rank 1 item 2, fixed in stage S3).  It is a
statement about `SEntails`; `eEnt_empty_false` shows it is NOT an instance of the row theory's
`⇒`, so it is not non-vacuity evidence for `EEnt`. -/
theorem taut_entailed (r : Var) : SEntails (∅ : System) (mk r {r} (∅ : Row)) := by
  intro rho _
  rw [sat_mk_iff]
  refine ⟨by simp, by simp, ?_⟩
  intro v hv w hw hvw
  rw [Finset.mem_singleton] at hv hw
  exact absurd (hv.trans hw.symm) hvw

/-- **AN INCOMPLETENESS WITNESS for the exhibited `⇒`.**  `MFStep` is non-generative
(`MFStep.allVars`), so a derivation from `∅` stays inside the empty vocabulary and `EEnt ∅ c`
is FALSE for every `c` that mentions a variable -- `a <- (a)` included, which `taut_entailed`
shows the SEMANTICS does entail.  Definition 2 asks only that `⇒` be sound, never that it be
complete (`ROSE-COMPARISON.md` §1.3: Rose's `⇒` "is a *parameter*"), so this is a scope fact and
not a defect; it is recorded so the two relations are not confused. -/
theorem eEnt_empty_false (r : Var) : ¬ EEnt (∅ : System) (mk r {r} (∅ : Row)) := by
  intro h
  obtain ⟨H, hrun, hc⟩ := h.derives
  have hav : allVars H = allVars (∅ : System) := mfRun_allVars hrun
  have hr : r ∈ allVars H := lhs_mem_allVars hc
  rw [hav] at hr
  simp [allVars] at hr

end Rose
end Rowpartition
