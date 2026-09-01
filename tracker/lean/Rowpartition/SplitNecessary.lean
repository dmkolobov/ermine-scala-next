/-
# `splitConcrete` is load-bearing: why the fully non-generative variant is unsound

`Constraints.scala:816` implements Ermine's split-concrete rule.  Given a partition
`a <- C+ x++` whose concrete part `C+` is NON-EMPTY and whose abstract part has at least
two variables, it consults the reverse lookup `rhss(RHSAbstr(abstr))` and takes one of
two branches:

* **REUSE** -- an existing variable `u` already has `x++` as its bare abstract
  right-hand side; emit `a <- C+ u` alone;
* **MINT** -- nothing names `x++` yet; allocate a FRESH `u` and emit `u <- x++`
  together with `a <- C+ u`.

`-Dermine.genRules=nongen` deletes the MINT branch (and every other minting branch);
`-Dermine.genRules=cut` deletes only `commonSubexpression`'s mint and keeps this one.
Measured on the 40-case should-fail corpus (`core/examples/shouldfail/RESULTS.md`):
`cut` reproduces the shipped compiler exactly, 40/40 with identical messages, while
`nongen` **loses five refutations**.  Three of the five --
`der06_shared_two_var_remainder`, `der07_shared_three_var_remainder`,
`der08_shared_remainder_relations` -- are duplicated-field contradictions visible only
through DERIVED constraints.

This file explains that measurement at the level of the calculus.

## Results

**Section 1** formalises both branches as step relations on `Divergence.System`:
`SplitReuseStep` and (already in `Cut`) `SplitStep`, packaged as `SplitBranch`.

**Section 2** proves them sound.  REUSE is outright ENTAILMENT (`split_reuse_entails`),
so it does not move the model set at all (`SplitReuseStep.models_iff`); MINT introduces a
name the premises do not have, so the correct statement is `Cut.SConservativeExt`, proved
as `split_mint_conservativeExt`.  Both preserve satisfiability in both directions
(`SplitBranch.satisfiable_iff`), which is what makes the whole question one about
SYNTAX, never about meaning.

**Section 3** adds the remaining non-generative rules -- cancellation
(`Constraints.scala:1017`, in the sharp `fs.isEmpty && xs.size == 1` form the code
actually uses), substitution (`Constraints.scala:1076`), self-substitution
(`Constraints.scala:801`) and common partition (rule 8 of the header comment) -- each
proved to be outright entailment, and collects them with the kept CSE branches into
`NonGenStep`, the fully non-generative calculus.  `CutRuleStep` adds split-minting and
resolution: the rule set that survives the cut.  (De-duplication needs a repeated
right-hand variable and so cannot arise in the set-shaped model at all; `disjunction` is
commented out in the implementation.)

**Section 4** models the concrete-label error conditions as `Cut.Refuter`s: `FiresMerge`
is error class 1, DUPLICATED FIELD, exactly as `RHS.merge` tests it
(`Constraints.scala:329`, `"Fields appear twice in row"` -- the exact message all three
`der0{6,7,8}` cases produce), and `FiresInfRow` is error class 2, INFINITE ROW, as
`selfSubstitution` raises it.  Both are sound and monotone.

**Section 5, the witness.**  `derSystem` is `der06` written out as four partition
constraints.  It is UNSATISFIABLE (`derSystem_unsat`, proved directly, not via the
refuter).  `der_cut_refutes`: three `CutRuleStep`s -- one split-MINT, one split-REUSE,
one cancellation -- reach a system on which `FiresMerge` fires.  Every step after the mint
is non-generative.

**Section 6, the impossibility.**  `Blocked G R` says: no constraint of `G` defines a
member of `R`, every right-hand side is either empty or the whole of `R`, no constraint
whose right-hand side is `R` has an empty concrete part, and `2 ≤ R.card`.  Then
(`Blocked.no_nongenStep`, `Blocked.no_resStep`) **NOT ONE rule of the non-generative
calculus applies, nor does resolution**: CSE reuse and split-reuse need `R` to be named,
CSE fold needs a naming premise, cancellation needs a LONE leftover variable, resolution
needs an arity-one premise, substitution needs a defined right-hand variable,
self-substitution needs `c.lhs ∈ vset c`, and common partition needs two constraints with
identical right-hand sides.  The only rules that can fire are the two that MINT.  Blocked systems are therefore stuck under `NonGenStep`
(`Blocked.nongen_stuck`), and no concrete-label refuter fires on them
(`Blocked.not_firesMerge`, `Blocked.not_firesInfRow`).  `derSystem` is Blocked, so:

  **`split_necessary`** -- `derSystem` is unsatisfiable; the cut refutes it in three
  steps; the non-generative calculus cannot take a single step from it and none of the
  three modelled error conditions fires on it.  A Lean-level account of the measured
  `nongen` regression on `der06`/`der07`/`der08`.

**Section 7** states the rule hierarchy this establishes.

## The mechanism in one line

Cancellation is what turns a partition into information about a single variable, and it
needs the leftover to be a LONE variable (`xs.size == 1`, `Constraints.scala:1029`).  A
two-variable remainder is therefore inert until some rule gives it ONE name -- and only a
MINTING rule can do that when nothing names it yet.  That is `Blocked.no_nongenStep`,
and it is why `nongen` accepts `der06`.
-/
import Rowpartition.Cut

namespace Rowpartition

/-! ## 1. `splitConcrete` as a step relation, both branches

The MINT branch is `Cut.SplitApp` / `Cut.splitResult` / `Cut.SplitStep`, already defined
(section 5.2 of `Cut`, where it was used only for termination).  Here is the REUSE
branch, and the two together. -/

/-- The premises of `splitConcrete`'s REUSE branch: a nonempty concrete part, at least
two abstract variables, and an EXISTING variable `u` whose bare abstract right-hand side
is exactly that group.  This is the Scala's `rhss(RHSAbstr(abstr))` returning
`Some(u)`. -/
structure SplitReuseApp (G : System) (c : Constraint) (u : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- the reverse lookup hit: `u` already names this group -/
  names : Names G u (vset c)

/-- The single constraint the REUSE branch emits: `Partition(v, RHS(Set(u), concr))`. -/
def splitReuseResult (G : System) (c : Constraint) (u : Var) : System :=
  insert (mk c.lhs {u} c.conc) G

/-- One application of `splitConcrete`, REUSE branch. -/
inductive SplitReuseStep : System → System → Prop
  | intro {G : System} {c : Constraint} {u : Var} :
      SplitReuseApp G c u → SplitReuseStep G (splitReuseResult G c u)

/-- Either branch of `splitConcrete`. -/
inductive SplitBranch : System → System → Prop
  | reuse {G G' : System} : SplitReuseStep G G' → SplitBranch G G'
  | mint {G G' : System} : SplitStep G G' → SplitBranch G G'

theorem subset_splitReuseResult (G : System) (c : Constraint) (u : Var) :
    G ⊆ splitReuseResult G c u := fun _ hd => Finset.mem_insert_of_mem hd

theorem SplitReuseStep.subset {G G' : System} (h : SplitReuseStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact subset_splitReuseResult _ _ _

theorem SplitBranch.subset {G G' : System} (h : SplitBranch G G') : G ⊆ G' := by
  cases h with
  | reuse h => exact h.subset
  | mint h => exact h.subset

/-- **Both branches emit the same rewritten premise.**  `a <- C+ u` is the contraction of
`a <- C+ x++` that replaces the WHOLE right-hand side by `u`; so `splitConcrete` is
`Cut.reduce` at `S = vset c`, and the MINT branch adds the naming constraint on top.
This identification is what lets section 2 reuse `Cut.sat_reduce_of_denotes` and
`Divergence.sat_reduce` verbatim. -/
theorem reduce_self (c : Constraint) (u : Var) :
    reduce c (vset c) u = mk c.lhs {u} c.conc := by
  rw [reduce, Finset.sdiff_self]
  simp

/-! ## 2. Soundness

Exactly as for `commonSubexpression` in `Cut`: the non-minting branch is plain
entailment, and the minting branch is a conservative extension at the minted variable.
Neither can change which systems have models. -/

/-- **The REUSE branch is outright ENTAILMENT.**  When `u` already names the group, the
rewritten premise `a <- C+ u` is a semantic consequence of the system -- no fresh
variable, nothing to extend, `Rules.ConservativeExt` not even needed. -/
theorem split_reuse_entails {G : System} {c : Constraint} {u : Var}
    (h : SplitReuseApp G c u) : SEntails G (mk c.lhs {u} c.conc) := by
  intro rho hm
  rw [← reduce_self]
  exact sat_reduce_of_denotes (hm c h.mem) (Finset.Subset.refl _) (h.names.denotes hm)

/-- The REUSE branch does not move the model set at all. -/
theorem SplitReuseStep.models_iff {G G' : System} (h : SplitReuseStep G G')
    (rho : Assign) : SModels rho G ↔ SModels rho G' := by
  refine ⟨fun hm => ?_, fun hm => SModels.mono h.subset hm⟩
  cases h with
  | @intro c u happ =>
    intro d hd
    simp only [splitReuseResult, Finset.mem_insert] at hd
    rcases hd with rfl | hd'
    · exact split_reuse_entails happ rho hm
    · exact hm d hd'

/-- **The MINT branch is a conservative extension.**  Every model of the premises
extends, CHANGING ONLY the fresh `u`, to a model of the two emitted constraints; and
every model of those already models the premises.  This is `Rules.rule4` for
systems-as-finsets; the proof is `Divergence.sat_name` and `Divergence.sat_reduce` at
`S = vset c`, via `reduce_self`. -/
theorem split_mint_conservativeExt {G : System} {c : Constraint} {u : Var}
    (happ : SplitApp G c u) : SConservativeExt G u (splitResult G c u) := by
  refine ⟨fun rho hm => ?_, fun _ hm => SModels.mono (subset_splitResult _ _ _) hm⟩
  have hc := hm c happ.mem
  have hu : u ∉ vset c := fun hh => happ.fresh (mem_allVars happ.mem (Or.inr hh))
  have hul : u ≠ c.lhs := fun hh => happ.fresh (hh ▸ lhs_mem_allVars happ.mem)
  refine ⟨setVar rho u ((vset c).biUnion rho), fun _ hv => setVar_of_ne rho _ hv, ?_⟩
  intro d hd
  simp only [splitResult, Finset.mem_insert] at hd
  rcases hd with rfl | rfl | hd
  · exact sat_name hc (Finset.Subset.refl _) hu
  · rw [← reduce_self]
    exact sat_reduce hc (Finset.Subset.refl _) hu hul
  · exact sModels_setVar happ.fresh _ hm d hd

/-- `Cut.SConservativeExt` preserves satisfiability both ways.  (`Cut` proves this for
`Rules.ConservativeExt`; this is the systems-as-finsets restatement, so it can be applied
without a round trip through `sConservativeExt_iff`.) -/
theorem SConservativeExt.satisfiable_iff {G G' : System} {u : Var}
    (h : SConservativeExt G u G') : (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  constructor
  · rintro ⟨rho, hm⟩
    obtain ⟨rho', -, hm'⟩ := h.1 rho hm
    exact ⟨rho', hm'⟩
  · rintro ⟨rho, hm⟩
    exact ⟨rho, h.2 rho hm⟩

theorem SplitStep.satisfiable_iff {G G' : System} (h : SplitStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | @intro c u happ =>
    exact SConservativeExt.satisfiable_iff (split_mint_conservativeExt happ)

/-- **Neither branch of `splitConcrete` changes satisfiability.**  So nothing that
follows is about a loss of semantic information: it is entirely about whether a
SYNTACTIC error condition becomes applicable. -/
theorem SplitBranch.satisfiable_iff {G G' : System} (h : SplitBranch G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | reuse h => exact exists_congr h.models_iff
  | mint h => exact h.satisfiable_iff


/-! ## 3. The other non-generative rules

Two more rules of `Constraints.scala` are needed: cancellation, which is what turns a
partition into information about a SINGLE variable, and substitution, which is where the
duplicated-field error is actually raised.  Both are stated in the `mk`/`Finset` form the
solver works in, and both are proved to be outright entailment. -/

/-- Membership in the left-hand row, in set form. -/
theorem Sat.mem_lhs_iff' {rho : Assign} {c : Constraint} (h : Sat rho c) (l : Label) :
    l ∈ rho c.lhs ↔ l ∈ c.conc ∨ ∃ v ∈ vset c, l ∈ rho v := by
  rw [h.eq_biUnion]
  simp only [Finset.mem_union, Finset.mem_biUnion]

/-- Every variable part sits inside the left-hand row, in set form. -/
theorem Sat.subset_lhs' {rho : Assign} {c : Constraint} (h : Sat rho c) {v : Var}
    (hv : v ∈ vset c) : rho v ⊆ rho c.lhs :=
  h.subset_lhs (List.mem_toFinset.mp hv)

/-- The bridge between the `mk`/`Finset` form used here and the list form `Rules` states
its theorems in, at the arity-one shape `resolution` needs. -/
theorem sat_mk_singleton (rho : Assign) (a x : Var) (K : Finset Label) :
    Sat rho (mk a {x} K) ↔ Sat rho ⟨a, [x], K⟩ := by
  rw [sat_mk_iff, sat_one]
  simp

/-- `Divergence.sModels_setVar` for an arbitrary assignment that agrees off `z`. -/
theorem sModels_of_agree {G : System} {z : Var} {rho rho' : Assign} (hz : z ∉ allVars G)
    (hag : ∀ v, v ≠ z → rho' v = rho v) (hm : SModels rho G) : SModels rho' G := by
  intro c hc
  refine (sat_congr_of_agree (rho := rho) (rho' := rho') ?_).mp (hm c hc)
  intro v hv
  exact (hag v (fun hh => hz (hh ▸ mem_allVars hc hv))).symm

/-! ### Cancellation

```
a <- C* x* z
a <- C* x* D* y*
----------------
   z <- D* y*
```

in the sharp form `Constraints.scala:1017` implements: with `absInt = abs1 & abs2`,
`xs = abs1 -- absInt`, `fs = con1 -- (con1 & con2)`, it fires when `fs.isEmpty` (that is,
`con1 ⊆ con2`) and `xs.size == 1`, emitting `xs.head <- (abs2 -- absInt, con2 -- con1)`.
**The `xs.size == 1` guard is the hinge of this whole file**: a leftover of two or more
variables makes cancellation inapplicable, and nothing else can produce a fully concrete
partition of a remainder variable. -/

/-- The premises of cancellation. -/
structure CancelApp (G : System) (c d : Constraint) (z : Var) : Prop where
  /-- the first premise is in the system -/
  mem₁ : c ∈ G
  /-- the second premise is in the system -/
  mem₂ : d ∈ G
  /-- both partition the same variable -/
  same_lhs : c.lhs = d.lhs
  /-- the guard `fs.isEmpty` -/
  conc_le : c.conc ⊆ d.conc
  /-- the guard `xs.size == 1`: exactly one variable is left over -/
  lone : vset c \ vset d = {z}

/-- The single constraint cancellation emits. -/
def cancelResult (G : System) (c d : Constraint) (z : Var) : System :=
  insert (mk z (vset d \ vset c) (d.conc \ c.conc)) G

/-- One application of cancellation. -/
inductive CancelStep : System → System → Prop
  | intro {G : System} {c d : Constraint} {z : Var} :
      CancelApp G c d z → CancelStep G (cancelResult G c d z)

theorem subset_cancelResult (G : System) (c d : Constraint) (z : Var) :
    G ⊆ cancelResult G c d z := fun _ he => Finset.mem_insert_of_mem he

theorem CancelStep.subset {G G' : System} (h : CancelStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact subset_cancelResult _ _ _ _

/-- **Cancellation is sound**, in the sharp form the implementation uses. -/
theorem cancel_sat {rho : Assign} {c d : Constraint} {z : Var} (hc : Sat rho c)
    (hd : Sat rho d) (hlhs : c.lhs = d.lhs) (hCK : c.conc ⊆ d.conc)
    (hlone : vset c \ vset d = {z}) :
    Sat rho (mk z (vset d \ vset c) (d.conc \ c.conc)) := by
  obtain ⟨hzc1, hzc2⟩ : z ∈ vset c ∧ z ∉ vset d := by
    refine Finset.mem_sdiff.mp ?_
    rw [hlone]
    exact Finset.mem_singleton_self z
  rw [sat_mk_iff]
  refine ⟨?_, ?_, ?_⟩
  · ext l
    simp only [Finset.mem_union, Finset.mem_sdiff, Finset.mem_biUnion]
    constructor
    · intro hl
      have hla : l ∈ rho d.lhs := by rw [← hlhs]; exact hc.subset_lhs' hzc1 hl
      rcases (hd.mem_lhs_iff' l).mp hla with hdc | ⟨v, hv, hlv⟩
      · exact Or.inl ⟨hdc,
          fun hcc => Finset.disjoint_left.mp (hc.disjoint_conc' hzc1) hcc hl⟩
      · refine Or.inr ⟨v, ⟨hv, fun hvc => ?_⟩, hlv⟩
        exact Finset.disjoint_left.mp
          (hc.disjoint_of_ne' hvc hzc1 (fun h => hzc2 (h ▸ hv))) hlv hl
    · rintro (⟨hdc, hcc⟩ | ⟨v, ⟨hv, hvc⟩, hlv⟩)
      · have hla : l ∈ rho c.lhs := by rw [hlhs]; exact hd.conc_subset_lhs hdc
        rcases (hc.mem_lhs_iff' l).mp hla with h | ⟨w, hw, hlw⟩
        · exact absurd h hcc
        · have hwd : w ∉ vset d := fun hwd =>
            Finset.disjoint_left.mp (hd.disjoint_conc' hwd) hdc hlw
          have hwz : w ∈ ({z} : Finset Var) := by
            rw [← hlone]; exact Finset.mem_sdiff.mpr ⟨hw, hwd⟩
          exact (Finset.mem_singleton.mp hwz) ▸ hlw
      · have hla : l ∈ rho c.lhs := by rw [hlhs]; exact hd.subset_lhs' hv hlv
        rcases (hc.mem_lhs_iff' l).mp hla with h | ⟨w, hw, hlw⟩
        · exact absurd hlv (Finset.disjoint_left.mp (hd.disjoint_conc' hv) (hCK h))
        · have hwd : w ∉ vset d := by
            intro hwd
            exact Finset.disjoint_left.mp
              (hd.disjoint_of_ne' hwd hv (fun hh => hvc (hh ▸ hw))) hlw hlv
          have hwz : w ∈ ({z} : Finset Var) := by
            rw [← hlone]; exact Finset.mem_sdiff.mpr ⟨hw, hwd⟩
          exact (Finset.mem_singleton.mp hwz) ▸ hlw
  · intro v hv
    exact disjoint_of_subset_left (hd.disjoint_conc' (Finset.mem_sdiff.mp hv).1)
      Finset.sdiff_subset
  · intro v hv w hw hvw
    exact hd.disjoint_of_ne' (Finset.mem_sdiff.mp hv).1 (Finset.mem_sdiff.mp hw).1 hvw

/-- Cancellation as entailment. -/
theorem cancel_entails {G : System} {c d : Constraint} {z : Var} (h : CancelApp G c d z) :
    SEntails G (mk z (vset d \ vset c) (d.conc \ c.conc)) := fun _ hm =>
  cancel_sat (hm c h.mem₁) (hm d h.mem₂) h.same_lhs h.conc_le h.lone

theorem CancelStep.models_iff {G G' : System} (h : CancelStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := by
  refine ⟨fun hm => ?_, fun hm => SModels.mono h.subset hm⟩
  cases h with
  | @intro c d z happ =>
    intro e he
    simp only [cancelResult, Finset.mem_insert] at he
    rcases he with rfl | he'
    · exact cancel_entails happ rho hm
    · exact hm e he'

/-! ### Substitution

```
a <- D* b x*
 b <- E* y*
------------
a <- D* E* x* y*
```

`Constraints.scala:1076`.  This is where the duplicated-field error is raised: the
implementation computes the merged right-hand side with `RHS.merge`
(`Constraints.scala:322`), which dies with `"Fields appear twice in row"` when the two
concrete parts intersect.  Section 4 models exactly that test. -/

/-- The premises of substitution: `d`'s left-hand variable occurs on `c`'s right. -/
structure SubstApp (G : System) (c d : Constraint) : Prop where
  /-- the constraint being rewritten is in the system -/
  mem₁ : c ∈ G
  /-- the definition being substituted is in the system -/
  mem₂ : d ∈ G
  /-- the occurrence: `rhs2 contains v` -/
  occurs : d.lhs ∈ vset c

/-- The merged constraint substitution emits. -/
def substResult (G : System) (c d : Constraint) : System :=
  insert (mk c.lhs ((vset c).erase d.lhs ∪ vset d) (c.conc ∪ d.conc)) G

/-- One application of substitution. -/
inductive SubstStep : System → System → Prop
  | intro {G : System} {c d : Constraint} : SubstApp G c d → SubstStep G (substResult G c d)

theorem subset_substResult (G : System) (c d : Constraint) : G ⊆ substResult G c d :=
  fun _ he => Finset.mem_insert_of_mem he

theorem SubstStep.subset {G G' : System} (h : SubstStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact subset_substResult _ _ _

/-- **Substitution is sound**, with NO side condition.  In particular it holds even when
the two concrete parts overlap -- in that case the premises have no model at all, which
is precisely why the implementation may raise the duplicated-field error there. -/
theorem subst_sat {rho : Assign} {c d : Constraint} (hc : Sat rho c) (hd : Sat rho d)
    (hmem : d.lhs ∈ vset c) :
    Sat rho (mk c.lhs ((vset c).erase d.lhs ∪ vset d) (c.conc ∪ d.conc)) := by
  rw [sat_mk_iff]
  refine ⟨?_, ?_, ?_⟩
  · ext l
    constructor
    · intro hl
      rcases (hc.mem_lhs_iff' l).mp hl with h | ⟨v, hv, hlv⟩
      · exact Finset.mem_union_left _ (Finset.mem_union_left _ h)
      · by_cases hvd : v = d.lhs
        · subst hvd
          rcases (hd.mem_lhs_iff' l).mp hlv with h | ⟨w, hw, hlw⟩
          · exact Finset.mem_union_left _ (Finset.mem_union_right _ h)
          · exact Finset.mem_union_right _
              (Finset.mem_biUnion.mpr ⟨w, Finset.mem_union_right _ hw, hlw⟩)
        · exact Finset.mem_union_right _ (Finset.mem_biUnion.mpr
            ⟨v, Finset.mem_union_left _ (Finset.mem_erase.mpr ⟨hvd, hv⟩), hlv⟩)
    · intro hl
      rcases Finset.mem_union.mp hl with hl' | hl'
      · rcases Finset.mem_union.mp hl' with h | h
        · exact (hc.mem_lhs_iff' l).mpr (Or.inl h)
        · exact (hc.mem_lhs_iff' l).mpr (Or.inr ⟨d.lhs, hmem, hd.conc_subset_lhs h⟩)
      · obtain ⟨v, hv, hlv⟩ := Finset.mem_biUnion.mp hl'
        rcases Finset.mem_union.mp hv with hv' | hv'
        · exact (hc.mem_lhs_iff' l).mpr (Or.inr ⟨v, (Finset.mem_erase.mp hv').2, hlv⟩)
        · exact (hc.mem_lhs_iff' l).mpr (Or.inr ⟨d.lhs, hmem, hd.subset_lhs' hv' hlv⟩)
  · intro v hv
    rw [Finset.disjoint_union_left]
    rcases Finset.mem_union.mp hv with hv' | hv'
    · obtain ⟨hne, hvc⟩ := Finset.mem_erase.mp hv'
      exact ⟨hc.disjoint_conc' hvc, disjoint_of_subset_left
        (hc.disjoint_of_ne' hmem hvc (Ne.symm hne)) hd.conc_subset_lhs⟩
    · exact ⟨disjoint_of_subset_right (hc.disjoint_conc' hmem) (hd.subset_lhs' hv'),
        hd.disjoint_conc' hv'⟩
  · intro v hv w hw hvw
    rcases Finset.mem_union.mp hv with hv' | hv' <;>
      rcases Finset.mem_union.mp hw with hw' | hw'
    · exact hc.disjoint_of_ne' (Finset.mem_erase.mp hv').2 (Finset.mem_erase.mp hw').2 hvw
    · obtain ⟨hne, hvc⟩ := Finset.mem_erase.mp hv'
      exact disjoint_of_subset_right (hc.disjoint_of_ne' hvc hmem hne) (hd.subset_lhs' hw')
    · obtain ⟨hne, hwc⟩ := Finset.mem_erase.mp hw'
      exact (disjoint_of_subset_right (hc.disjoint_of_ne' hwc hmem hne)
        (hd.subset_lhs' hv')).symm
    · exact hd.disjoint_of_ne' hv' hw' hvw

/-- Substitution as entailment. -/
theorem subst_entails {G : System} {c d : Constraint} (h : SubstApp G c d) :
    SEntails G (mk c.lhs ((vset c).erase d.lhs ∪ vset d) (c.conc ∪ d.conc)) := fun _ hm =>
  subst_sat (hm c h.mem₁) (hm d h.mem₂) h.occurs

theorem SubstStep.models_iff {G G' : System} (h : SubstStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := by
  refine ⟨fun hm => ?_, fun hm => SModels.mono h.subset hm⟩
  cases h with
  | @intro c d happ =>
    intro e he
    simp only [substResult, Finset.mem_insert] at he
    rcases he with rfl | he'
    · exact subst_entails happ rho hm
    · exact hm e he'

/-! ### Self-substitution and common partition

Two more rules from the header comment of `Constraints.scala`, included so that "not one
rule applies" covers the whole informal rule set rather than only the rules the witness
derivation happens to use.  Two rules of that comment have no analogue here and need
none: DE-DUPLICATION (`a <- x b b*`) cannot fire because `vset` is a `Finset`, so a
right-hand side cannot repeat a variable; and `disjunction` is commented out in the
implementation (`Constraints.scala:1092-1099`, `Constraints.scala:1117`). -/

/-- Self-substitution (`Constraints.scala:801`), in its non-error branch:

```
a <- a b*
---------
 (b <-)*
```

It fires only when the left-hand variable occurs on its own right-hand side; with a
NONEMPTY concrete part the same premise is the infinite-row error instead. -/
structure SelfSubstApp (G : System) (c : Constraint) (v : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `rhs1.abstr contains v` -/
  self : c.lhs ∈ vset c
  /-- `concr.isEmpty` -- otherwise this is the error branch -/
  conc_empty : c.conc = ∅
  /-- the variable being emptied -/
  mem_v : v ∈ vset c
  /-- ... which is one of the `b*`, not `a` itself -/
  ne : v ≠ c.lhs

/-- The constraint self-substitution emits: `b <- ()`. -/
def selfSubstResult (G : System) (v : Var) : System := insert (mk v ∅ ∅) G

/-- One application of self-substitution. -/
inductive SelfSubstStep : System → System → Prop
  | intro {G : System} {c : Constraint} {v : Var} :
      SelfSubstApp G c v → SelfSubstStep G (selfSubstResult G v)

theorem SelfSubstStep.subset {G G' : System} (h : SelfSubstStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact fun _ he => Finset.mem_insert_of_mem he

/-- **Self-substitution is sound** (`Rules.rule1_empty` in set form). -/
theorem selfSubst_sat {rho : Assign} {c : Constraint} {v : Var} (hc : Sat rho c)
    (hself : c.lhs ∈ vset c) (hv : v ∈ vset c) (hne : v ≠ c.lhs) : Sat rho (mk v ∅ ∅) := by
  have hempty : rho v = ∅ :=
    eq_empty_of_disjoint_self
      (disjoint_of_subset_right (hc.disjoint_of_ne' hv hself hne) (hc.subset_lhs' hv))
  rw [sat_mk_iff]
  exact ⟨by simp [hempty], by simp, by simp⟩

theorem SelfSubstStep.models_iff {G G' : System} (h : SelfSubstStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := by
  refine ⟨fun hm => ?_, fun hm => SModels.mono h.subset hm⟩
  cases h with
  | @intro c v happ =>
    intro e he
    simp only [selfSubstResult, Finset.mem_insert] at he
    rcases he with rfl | he'
    · exact selfSubst_sat (hm c happ.mem) happ.self happ.mem_v happ.ne
    · exact hm e he'

/-- Common partition (rule 8 of the header comment):

```
a <- A* x*
b <- A* x*
----------
  a <- b
```

The shipped solver realises this through its RHS-keyed reverse lookup rather than as a
rule that emits a partition, but it is in the informal rule set, its conclusion IS a
naming constraint, and it is therefore worth blocking explicitly. -/
structure CommonPartApp (G : System) (c d : Constraint) : Prop where
  /-- the first premise is in the system -/
  mem₁ : c ∈ G
  /-- the second premise is in the system -/
  mem₂ : d ∈ G
  /-- distinct left-hand sides, or the conclusion is vacuous -/
  lhs_ne : c.lhs ≠ d.lhs
  /-- identical abstract parts -/
  vset_eq : vset c = vset d
  /-- identical concrete parts -/
  conc_eq : c.conc = d.conc

/-- The constraint common partition emits: `a <- b`. -/
def commonPartResult (G : System) (c d : Constraint) : System :=
  insert (mk c.lhs {d.lhs} ∅) G

/-- One application of common partition. -/
inductive CommonPartStep : System → System → Prop
  | intro {G : System} {c d : Constraint} :
      CommonPartApp G c d → CommonPartStep G (commonPartResult G c d)

theorem CommonPartStep.subset {G G' : System} (h : CommonPartStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact fun _ he => Finset.mem_insert_of_mem he

/-- **Common partition is sound** (`Rules.rule8` in set form). -/
theorem commonPart_sat {rho : Assign} {c d : Constraint} (hc : Sat rho c) (hd : Sat rho d)
    (hv : vset c = vset d) (hk : c.conc = d.conc) : Sat rho (mk c.lhs {d.lhs} ∅) := by
  have he : rho c.lhs = rho d.lhs := by rw [hc.eq_biUnion, hd.eq_biUnion, hv, hk]
  rw [sat_mk_iff]
  exact ⟨by simp [he], by simp, by simp⟩

theorem CommonPartStep.models_iff {G G' : System} (h : CommonPartStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := by
  refine ⟨fun hm => ?_, fun hm => SModels.mono h.subset hm⟩
  cases h with
  | @intro c d happ =>
    intro e he
    simp only [commonPartResult, Finset.mem_insert] at he
    rcases he with rfl | he'
    · exact commonPart_sat (hm c happ.mem₁) (hm d happ.mem₂) happ.vset_eq happ.conc_eq
    · exact hm e he'

/-! ### The two calculi

`NonGenStep` is the fully non-generative calculus (`-Dermine.genRules=nongen`): every
rule that does not call `fresh`.  `CutRuleStep` adds back the two minting rules the cut
keeps (`-Dermine.genRules=cut`): `splitConcrete`'s mint and `resolution`.  The full
solver adds `commonSubexpression`'s mint on top of that. -/

/-- The fully NON-GENERATIVE calculus: CSE reuse and fold (`Cut.CutStep`),
`splitConcrete`'s reuse branch, cancellation and substitution.  No rule here mints. -/
inductive NonGenStep : System → System → Prop
  | cse {G G' : System} : CutStep G G' → NonGenStep G G'
  | split {G G' : System} : SplitReuseStep G G' → NonGenStep G G'
  | cancel {G G' : System} : CancelStep G G' → NonGenStep G G'
  | subst {G G' : System} : SubstStep G G' → NonGenStep G G'
  | selfSubst {G G' : System} : SelfSubstStep G G' → NonGenStep G G'
  | commonPart {G G' : System} : CommonPartStep G G' → NonGenStep G G'

/-- The calculus that survives the cut: the non-generative rules, plus `splitConcrete`'s
MINT branch and `resolution`. -/
inductive CutRuleStep : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → CutRuleStep G G'
  | mint {G G' : System} : SplitStep G G' → CutRuleStep G G'
  | res {G G' : System} : ResStep G G' → CutRuleStep G G'

theorem NonGenStep.subset {G G' : System} (h : NonGenStep G G') : G ⊆ G' := by
  cases h with
  | cse h => exact h.subset
  | split h => exact h.subset
  | cancel h => exact h.subset
  | subst h => exact h.subset
  | selfSubst h => exact h.subset
  | commonPart h => exact h.subset

/-- **Every non-generative rule is entailment: the model set never moves.**  Not merely
satisfiability-preserving -- literally the same assignments. -/
theorem NonGenStep.models_iff {G G' : System} (h : NonGenStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := by
  cases h with
  | cse h => exact h.models_iff rho
  | split h => exact h.models_iff rho
  | cancel h => exact h.models_iff rho
  | subst h => exact h.models_iff rho
  | selfSubst h => exact h.models_iff rho
  | commonPart h => exact h.models_iff rho

/-- **Resolution preserves satisfiability**, both ways.  `Cut` defines `ResStep` but
proves only its divergence; this is `Rules.rule6` -- the sharp `E \ C` / `C \ E` form the
Scala implements -- transported to systems-as-finsets, with the header's shared block `D`
instantiated to `∅` (Cut's `ResApp` carries the whole concrete parts). -/
theorem ResStep.satisfiable_iff {G G' : System} (h : ResStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | @intro v x y C D z happ =>
    refine ⟨fun hsat => ?_, fun hsat => ?_⟩
    · obtain ⟨rho, hm⟩ := hsat
      have hv : v ∈ allVars G := lhs_mem_allVars happ.mem₁
      have hx : x ∈ allVars G := mem_allVars happ.mem₁ (Or.inr (by simp))
      have hy : y ∈ allVars G := mem_allVars happ.mem₂ (Or.inr (by simp))
      have hvz : v ≠ z := by rintro rfl; exact happ.fresh hv
      have hxz : x ≠ z := by rintro rfl; exact happ.fresh hx
      have hyz : y ≠ z := by rintro rfl; exact happ.fresh hy
      have h1 : Sat rho ⟨v, [x], C ∪ ∅⟩ := by
        rw [Finset.union_empty]
        exact (sat_mk_singleton rho v x C).mp (hm _ happ.mem₁)
      have h2 : Sat rho ⟨v, [y], ∅ ∪ D⟩ := by
        rw [Finset.empty_union]
        exact (sat_mk_singleton rho v y D).mp (hm _ happ.mem₂)
      obtain ⟨rho', hag, hm'⟩ :=
        (rule6 (a := v) (x := x) (y := y) (z := z) (C := C) (D := ∅) (E := D)
          (by simp) (by simp) hvz hxz hyz).1 rho (models_of_two h1 h2)
      have g1 : Sat rho' ⟨v, [z], C ∪ ∅ ∪ D⟩ := hm' _ (by simp)
      have g2 : Sat rho' ⟨x, [z], D \ C⟩ := hm' _ (by simp)
      have g3 : Sat rho' ⟨y, [z], C \ D⟩ := hm' _ (by simp)
      rw [Finset.union_empty] at g1
      refine ⟨rho', ?_⟩
      intro c hc
      simp only [resResult, Finset.mem_insert] at hc
      rcases hc with rfl | rfl | rfl | hc
      · rw [sat_mk_singleton]; exact g1
      · rw [sat_mk_singleton]; exact g2
      · rw [sat_mk_singleton]; exact g3
      · exact sModels_of_agree happ.fresh hag hm c hc
    · obtain ⟨rho, hm⟩ := hsat
      exact ⟨rho, SModels.mono (subset_resResult _ _ _ _ _ _ _) hm⟩

theorem CutRuleStep.subset {G G' : System} (h : CutRuleStep G G') : G ⊆ G' := by
  cases h with
  | nongen h => exact h.subset
  | mint h => exact h.subset
  | res h => exact h.subset

/-- **The cut calculus preserves satisfiability in both directions.**  Its one minting
rule is a conservative extension; resolution's is `Rules.rule6`. -/
theorem CutRuleStep.satisfiable_iff {G G' : System} (h : CutRuleStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | nongen h => exact exists_congr h.models_iff
  | mint h => exact h.satisfiable_iff
  | res h => exact h.satisfiable_iff

/-- `NonGenSteps n G G'`: `G'` is reachable from `G` by exactly `n` non-generative steps. -/
inductive NonGenSteps : ℕ → System → System → Prop
  | refl (G : System) : NonGenSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      NonGenSteps n G G' → NonGenStep G' G'' → NonGenSteps (n + 1) G G''

/-- `CutRuleSteps n G G'`: `G'` is reachable from `G` by exactly `n` cut-calculus steps. -/
inductive CutRuleSteps : ℕ → System → System → Prop
  | refl (G : System) : CutRuleSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      CutRuleSteps n G G' → CutRuleStep G' G'' → CutRuleSteps (n + 1) G G''

theorem CutRuleSteps.satisfiable_iff {n : ℕ} {G₀ G : System} (h : CutRuleSteps n G₀ G) :
    (∃ rho, SModels rho G₀) ↔ (∃ rho, SModels rho G) := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep ih => exact ih.trans hstep.satisfiable_iff

/-! ## 4. The concrete-label error conditions, as refuters

Three of Ermine's five error classes are about CONCRETE LABELS.  Two of them are visible
in this model -- the third, INFINITE ROW with an empty concrete part, is `rule2`, not an
error.  (Skolem escape and row mismatch are about the type checker's unifier, not about
partition constraints, and are outside this model.)  Both are `Cut.Refuter`s: sound, and
monotone in the derived set. -/

/-- **Error condition 1, DUPLICATED FIELD**, exactly as `RHS.merge` tests it
(`Constraints.scala:322-330`).  Substituting `d` into `c` -- legal because `d`'s
left-hand variable occurs on `c`'s right -- merges the two concrete parts, and the
implementation dies with `"Fields appear twice in row: " + cint` when
`cint = concr1 & concr2` is nonempty.  This is the message all three of
`der06`/`der07`/`der08` produce. -/
def FiresMerge (G : System) : Prop :=
  ∃ c ∈ G, ∃ d ∈ G, d.lhs ∈ vset c ∧ ¬ Disjoint c.conc d.conc

theorem firesMerge_sound (G : System) (h : FiresMerge G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, d, hd, hocc, hnd⟩ := h
  exact hnd (disjoint_of_subset_right ((hm c hc).disjoint_conc' hocc)
    (hm d hd).conc_subset_lhs)

theorem firesMerge_mono (G G' : System) (hsub : G ⊆ G') (h : FiresMerge G) : FiresMerge G' := by
  obtain ⟨c, hc, d, hd, h1, h2⟩ := h
  exact ⟨c, hsub hc, d, hsub hd, h1, h2⟩

/-- Ermine's duplicated-field check, packaged as a `Cut.Refuter`. -/
def refuterMerge : Refuter := ⟨FiresMerge, firesMerge_sound, firesMerge_mono⟩

/-- **Error condition 2, INFINITE ROW**, as `selfSubstitution` raises it
(`Constraints.scala:803`): `a <- C+ a b*` with `C+` nonempty.  Note the nonemptiness --
with an empty concrete part the same premise is the sound de-duplication rule
`Rules.rule1_empty`, not an error.  This is why the corpus's `inf*` cases all carry a
concrete field. -/
def FiresInfRow (G : System) : Prop := ∃ c ∈ G, c.lhs ∈ vset c ∧ c.conc ≠ ∅

theorem firesInfRow_sound (G : System) (h : FiresInfRow G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, hocc, hne⟩ := h
  exact hne (eq_empty_of_disjoint_self (disjoint_of_subset_right
    ((hm c hc).disjoint_conc' hocc) (hm c hc).conc_subset_lhs))

theorem firesInfRow_mono (G G' : System) (hsub : G ⊆ G') (h : FiresInfRow G) : FiresInfRow G' := by
  obtain ⟨c, hc, h1, h2⟩ := h
  exact ⟨c, hsub hc, h1, h2⟩

/-- Ermine's infinite-row check, packaged as a `Cut.Refuter`. -/
def refuterInfRow : Refuter := ⟨FiresInfRow, firesInfRow_sound, firesInfRow_mono⟩

/-! ## 5. The witness: `der06_shared_two_var_remainder`

```
pair : forall t u x y. (t <- ((|a|), x, y), u <- ((|b|), x, y)) => Row t -> Row u -> Int
bad  = pair abc bc                      -- abc : Row (|a,b,c|),  bc : Row (|b,c|)
```

Instantiating the two givens at `t = (|a,b,c|)` and `u = (|b,c|)` gives four partition
constraints.  They have no model: the first two force `x + y = (|b,c|)`, and then the
second given wants `u = (|b|) + x + y`, which contains `b` twice.

Nothing in the four constraints names `x + y`, and no single constraint mentions a field
twice, so no error condition fires on them as they stand.  Sections 5 and 6 are the two
halves of the measurement: the cut finds the contradiction in three steps, and the fully
non-generative calculus cannot move at all. -/

namespace Der06

/-- The row variable `t`, instantiated to `(|a, b, c|)`. -/
abbrev t : Var := 0
/-- The row variable `u`, instantiated to `(|b, c|)`. -/
abbrev u : Var := 1
/-- The first variable of the shared remainder. -/
abbrev x : Var := 2
/-- The second variable of the shared remainder. -/
abbrev y : Var := 3
/-- The name `splitConcrete` mints for the remainder. -/
abbrev w : Var := 4

/-- The field `a`. -/
abbrev fa : Label := 10
/-- The field `b`. -/
abbrev fb : Label := 11
/-- The field `c`. -/
abbrev fc : Label := 12

/-- `t <- ((|a|), x, y)` -- the first given. -/
def g₁ : Constraint := mk t {x, y} {fa}
/-- `u <- ((|b|), x, y)` -- the second given. -/
def g₂ : Constraint := mk u {x, y} {fb}
/-- `t = (|a, b, c|)` -- the instantiation of `t` at `abc`. -/
def g₃ : Constraint := mk t ∅ {fa, fb, fc}
/-- `u = (|b, c|)` -- the instantiation of `u` at `bc`. -/
def g₄ : Constraint := mk u ∅ {fb, fc}

/-- The TWO-variable remainder the two givens share.  Everything turns on its size: at
one variable cancellation would fire directly, at two it is inert until named. -/
def rem : Finset Var := {x, y}

/-- `der06`, as a constraint system. -/
def derSystem : System := {g₁, g₂, g₃, g₄}

@[simp] theorem vset_g₁ : vset g₁ = rem := by simp [g₁, rem]
@[simp] theorem vset_g₂ : vset g₂ = rem := by simp [g₂, rem]
@[simp] theorem vset_g₃ : vset g₃ = ∅ := by simp [g₃]
@[simp] theorem vset_g₄ : vset g₄ = ∅ := by simp [g₄]

theorem mem_derSystem {c : Constraint} (hc : c ∈ derSystem) :
    c = g₁ ∨ c = g₂ ∨ c = g₃ ∨ c = g₄ := by
  simpa [derSystem] using hc

theorem mem_g₁ : g₁ ∈ derSystem := by simp [derSystem]
theorem mem_g₂ : g₂ ∈ derSystem := by simp [derSystem]
theorem mem_g₃ : g₃ ∈ derSystem := by simp [derSystem]
theorem mem_g₄ : g₄ ∈ derSystem := by simp [derSystem]

/-- Nothing in the input names the remainder: the two constraints whose right-hand side
IS `{x, y}` both carry a nonempty concrete part.  This is the reverse lookup
`rhss(RHSAbstr(abstr))` returning `None`, i.e. the condition under which `splitConcrete`
reaches its minting branch. -/
theorem not_named_rem : ¬ Named derSystem rem := by
  rintro ⟨d, hd, hv, hc⟩
  rcases mem_derSystem hd with rfl | rfl | rfl | rfl
  · exact absurd hc (by simp [g₁])
  · exact absurd hc (by simp [g₂])
  · exact absurd hv (by rw [vset_g₃, rem]; decide)
  · exact absurd hv (by rw [vset_g₄, rem]; decide)

theorem w_fresh : w ∉ allVars derSystem := by
  rw [allVars]
  intro h
  obtain ⟨c, hc, hmem⟩ := Finset.mem_biUnion.mp h
  rcases mem_derSystem hc with rfl | rfl | rfl | rfl <;>
    revert hmem <;> simp [g₁, g₂, g₃, g₄] <;> decide

/-- **The witness has no model.**  Proved directly from the semantics, independently of
any refuter: `t = (|a,b,c|)` and `t <- ((|a|), x, y)` put `b` inside `x + y`, while
`u <- ((|b|), x, y)` requires `b` to be disjoint from both `x` and `y`. -/
theorem derSystem_unsat : ¬ ∃ rho, SModels rho derSystem := by
  rintro ⟨rho, hm⟩
  have h₁ := hm g₁ mem_g₁
  have h₂ := hm g₂ mem_g₂
  have h₃ := hm g₃ mem_g₃
  have e₃ : rho t = ({fa, fb, fc} : Finset Label) := by
    have h := h₃.eq_biUnion
    simpa [g₃] using h
  have hb : fb ∈ rho t := by rw [e₃]; decide
  rcases (h₁.mem_lhs_iff' fb).mp hb with h | ⟨v, hv, hlv⟩
  · revert h; simp [g₁]
  · rw [vset_g₁, ← vset_g₂] at hv
    exact Finset.disjoint_left.mp (h₂.disjoint_conc' hv) (by simp [g₂]) hlv

/-! ### The derivation the cut finds

Three steps.  Only the FIRST is generative; the other two are ordinary non-generative
rules that could not fire before it. -/

/-- `w <- (x, y)`: the name `splitConcrete` MINTS for the shared remainder. -/
def nameW : Constraint := mk w rem ∅
/-- `t <- ((|a|), w)`: the first given, re-expressed through the minted name. -/
def s₁ : Constraint := mk t {w} {fa}
/-- `u <- ((|b|), w)`: the second given, re-expressed by the REUSE branch -- the reverse
lookup now hits, so this step mints nothing. -/
def s₂ : Constraint := mk u {w} {fb}
/-- `w = (|b, c|)`: what cancellation extracts once the remainder has ONE name. -/
def canc : Constraint := mk w ∅ ({fb, fc} : Finset Label)

/-- After `splitConcrete` mints. -/
def der1 : System := insert nameW (insert s₁ derSystem)
/-- After `splitConcrete` reuses the minted name on the second given. -/
def der2 : System := insert s₂ der1
/-- After cancellation.  `FiresMerge` fires here. -/
def der3 : System := insert canc der2

theorem der1_eq : splitResult derSystem g₁ w = der1 := by
  simp [splitResult, der1, nameW, s₁, g₁, rem]

theorem der2_eq : splitReuseResult der1 g₂ w = der2 := rfl

theorem der3_eq : cancelResult der2 s₁ g₃ w = der3 := by
  have e1 : vset g₃ \ vset s₁ = (∅ : Finset Var) := by simp [s₁]
  have e2 : g₃.conc \ s₁.conc = ({fb, fc} : Finset Label) := by decide
  rw [cancelResult, e1, e2, der3, canc]

/-- **Step 1 -- the mint.**  `splitConcrete` fires on `t <- ((|a|), x, y)`: the concrete
part is nonempty, there are two abstract variables, and nothing names them. -/
theorem step_mint : SplitStep derSystem der1 :=
  der1_eq ▸ SplitStep.intro
    ⟨mem_g₁, by simp [g₁], by rw [vset_g₁]; decide, by rw [vset_g₁]; exact not_named_rem,
      w_fresh⟩

theorem mem_nameW : nameW ∈ der1 := Finset.mem_insert_self _ _
theorem mem_s₁ : s₁ ∈ der1 := Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
theorem mem_g₂' : g₂ ∈ der1 := Finset.mem_insert_of_mem (Finset.mem_insert_of_mem mem_g₂)
theorem mem_g₃' : g₃ ∈ der2 := Finset.mem_insert_of_mem
  (Finset.mem_insert_of_mem (Finset.mem_insert_of_mem mem_g₃))
theorem mem_s₁' : s₁ ∈ der2 := Finset.mem_insert_of_mem mem_s₁
theorem mem_s₂ : s₂ ∈ der2 := Finset.mem_insert_self _ _

/-- **Step 2 -- non-generative.**  `splitConcrete` fires again, on the SECOND given; this
time the reverse lookup hits the name minted in step 1, so the REUSE branch applies. -/
theorem step_reuse : SplitReuseStep der1 der2 :=
  der2_eq ▸ SplitReuseStep.intro
    ⟨mem_g₂', by simp [g₂], by rw [vset_g₂]; decide,
      ⟨nameW, mem_nameW, rfl, by simp [nameW, rem], rfl⟩⟩

/-- **Step 3 -- non-generative.**  Cancellation of `t <- ((|a|), w)` against
`t = (|a,b,c|)`.  This is the step the `xs.size == 1` guard blocks before the mint: the
leftover here is the LONE variable `w`, whereas in the input it was the two-element
`{x, y}`. -/
theorem step_cancel : CancelStep der2 der3 :=
  der3_eq ▸ CancelStep.intro ⟨mem_s₁', mem_g₃', rfl, by simp [s₁, g₃], by simp [s₁]⟩

/-- **The duplicated-field condition fires.**  `u <- ((|b|), w)` and `w = (|b,c|)`:
substituting the second into the first merges `(|b|)` with `(|b,c|)`, and `b` appears
twice.  This is verbatim the error the shipped compiler reports for `der06`:
`Fields appear twice in row: Set(Shouldfail.Der06.b)`. -/
theorem fires_der3 : FiresMerge der3 :=
  ⟨s₂, Finset.mem_insert_of_mem mem_s₂, canc, Finset.mem_insert_self _ _,
    by simp [s₂, canc],
    by rw [Finset.not_disjoint_iff]; exact ⟨fb, by simp [s₂], by simp [canc]⟩⟩

/-- The three steps, as a run of the cut calculus. -/
theorem der_cut_steps : CutRuleSteps 3 derSystem der3 :=
  (((CutRuleSteps.refl derSystem).tail (CutRuleStep.mint step_mint)).tail
      (CutRuleStep.nongen (NonGenStep.split step_reuse))).tail
    (CutRuleStep.nongen (NonGenStep.cancel step_cancel))

/-- **The cut refutes the witness**, and the refutation is sound -- an independent
confirmation of `derSystem_unsat` that goes through the refuter and the calculus rather
than through the semantics. -/
theorem der_cut_refutes : CutRuleSteps 3 derSystem der3 ∧ FiresMerge der3 ∧
    ¬ ∃ rho, SModels rho derSystem :=
  ⟨der_cut_steps, fires_der3,
    fun hsat => firesMerge_sound der3 fires_der3 (der_cut_steps.satisfiable_iff.mp hsat)⟩

/-- **`commonSubexpression`'s minting branch would also do it.**  Under
`-Dermine.genRules=all` both generative rules fire on this pair; under `cut` only
`splitConcrete` does, which is why the cut loses nothing here.  (`Cut.CseStep` is the
branch the cut removes.) -/
theorem cse_mint_also_applies : ∃ G, CseStep derSystem G := by
  refine ⟨_, CseStep.intro (c₁ := g₁) (c₂ := g₂) (z := w)
    ⟨mem_g₁, mem_g₂, by decide, ?_, w_fresh⟩⟩
  rw [shared, vset_g₁, vset_g₂, Finset.inter_self]
  decide

end Der06

/-! ## 6. Why the non-generative calculus cannot get there

The whole of section 5 after the first step used only non-generative rules.  So the
question is exactly: can the non-generative calculus reach a firing state from
`derSystem` on its own?  It cannot -- and the reason is structural, not arithmetic.
`Blocked G R` isolates it. -/

/-- **The blocking invariant.**  `R` is a variable group of size at least two such that,
in `G`:

* no constraint DEFINES a member of `R` (`lhs_notMem`) -- so `R`'s variables occur only
  on right-hand sides;
* every right-hand side is either empty or the WHOLE of `R` (`vset_shape`) -- `R` never
  splits, and no other group appears;
* no constraint whose right-hand side is `R` has an empty concrete part (`unnamed`) --
  so nothing NAMES `R`.

`derSystem` satisfies this with `R = {x, y}`.  The three clauses are exactly what defeat
the three ways a rule could get a grip: substitution needs a defined right-hand variable,
cancellation needs a leftover of size one, and reuse needs a name. -/
structure Blocked (G : System) (R : Finset Var) : Prop where
  /-- the group has at least two variables -- this is what cancellation cannot handle -/
  two_le : 2 ≤ R.card
  /-- no constraint of `G` defines a member of `R` -/
  lhs_notMem : ∀ c ∈ G, c.lhs ∉ R
  /-- every right-hand side is empty or the whole group -/
  vset_shape : ∀ c ∈ G, vset c = ∅ ∨ vset c = R
  /-- nothing names the group -/
  unnamed : ∀ c ∈ G, vset c = R → c.conc ≠ ∅
  /-- no two constraints with different left-hand sides have the SAME right-hand side --
  which is what would let common partition mint a name by identifying them -/
  distinct : ∀ c ∈ G, ∀ d ∈ G, c.lhs ≠ d.lhs → vset c = vset d → c.conc ≠ d.conc

theorem Blocked.not_named {G : System} {R : Finset Var} (h : Blocked G R) : ¬ Named G R := by
  rintro ⟨d, hd, hv, hc⟩
  exact h.unnamed d hd hv hc

theorem Blocked.vset_subset {G : System} {R : Finset Var} (h : Blocked G R) {c : Constraint}
    (hc : c ∈ G) : vset c ⊆ R := by
  rcases h.vset_shape c hc with hv | hv
  · rw [hv]; exact Finset.empty_subset _
  · rw [hv]

/-- Under the invariant, a right-hand side of size at least two is exactly `R`. -/
theorem Blocked.vset_eq_of_two_le {G : System} {R : Finset Var} (h : Blocked G R)
    {c : Constraint} (hc : c ∈ G) (hcard : 2 ≤ (vset c).card) : vset c = R := by
  rcases h.vset_shape c hc with hv | hv
  · rw [hv] at hcard; simp at hcard
  · exact hv

/-- Under the invariant, a CSE pair's shared group is exactly `R`. -/
theorem Blocked.shared_eq {G : System} {R : Finset Var} (h : Blocked G R)
    {c₁ c₂ : Constraint} (h₁ : c₁ ∈ G) (h₂ : c₂ ∈ G) (hcard : 2 ≤ (shared c₁ c₂).card) :
    vset c₁ = R ∧ vset c₂ = R ∧ shared c₁ c₂ = R := by
  have e₁ : vset c₁ = R := by
    rcases h.vset_shape c₁ h₁ with hv | hv
    · rw [shared, hv, Finset.empty_inter] at hcard; simp at hcard
    · exact hv
  have e₂ : vset c₂ = R := by
    rcases h.vset_shape c₂ h₂ with hv | hv
    · rw [shared, hv, Finset.inter_empty] at hcard; simp at hcard
    · exact hv
  exact ⟨e₁, e₂, by rw [shared, e₁, e₂, Finset.inter_self]⟩

/-! ### Rule by rule -/

/-- CSE reuse and fold are blocked: both need `R` to be named, and it is not. -/
theorem Blocked.no_cutStep {G : System} {R : Finset Var} (h : Blocked G R) {G' : System}
    (hstep : CutStep G G') : False := by
  cases hstep with
  | @reuse c₁ c₂ z hp hn =>
    obtain ⟨-, -, hs⟩ := h.shared_eq hp.mem₁ hp.mem₂ hp.two_le
    exact h.not_named (hs ▸ hn.named)
  | @fold c₁ c₂ hp h1 h2 =>
    obtain ⟨-, -, hs⟩ := h.shared_eq hp.mem₁ hp.mem₂ hp.two_le
    exact h.unnamed c₁ hp.mem₁ (h1.trans hs) h2

/-- `splitConcrete`'s REUSE branch is blocked: it too needs `R` to be named. -/
theorem Blocked.no_splitReuseStep {G : System} {R : Finset Var} (h : Blocked G R)
    {G' : System} (hstep : SplitReuseStep G G') : False := by
  cases hstep with
  | @intro c v happ =>
    exact h.not_named
      ((h.vset_eq_of_two_le happ.mem happ.two_le) ▸ happ.names.named)

/-- **Cancellation is blocked: this is the hinge.**  Its `xs.size == 1` guard asks for a
leftover of exactly one variable, and under the invariant every leftover is `∅` or `R`,
of size `0` or at least `2`. -/
theorem Blocked.no_cancelStep {G : System} {R : Finset Var} (h : Blocked G R) {G' : System}
    (hstep : CancelStep G G') : False := by
  cases hstep with
  | @intro c d z happ =>
    have hcard : (vset c \ vset d).card = 1 := by rw [happ.lone]; simp
    have h2 := h.two_le
    rcases h.vset_shape c happ.mem₁ with hc | hc <;>
      rcases h.vset_shape d happ.mem₂ with hd | hd <;> rw [hc, hd] at hcard
    · simp at hcard
    · simp at hcard
    · rw [Finset.sdiff_empty] at hcard; omega
    · rw [Finset.sdiff_self] at hcard; simp at hcard

/-- Substitution is blocked: it needs a right-hand variable that some constraint DEFINES,
and no member of `R` is defined. -/
theorem Blocked.no_substStep {G : System} {R : Finset Var} (h : Blocked G R) {G' : System}
    (hstep : SubstStep G G') : False := by
  cases hstep with
  | @intro c d happ =>
    exact h.lhs_notMem d happ.mem₂ (h.vset_subset happ.mem₁ happ.occurs)

/-- Resolution is blocked too -- so this is not a statement about the non-generative
fragment only.  `resolution` matches `RHS(Single(x), _)`: it needs a premise of arity
exactly one, and under the invariant every arity is `0` or at least `2`. -/
theorem Blocked.no_resStep {G : System} {R : Finset Var} (h : Blocked G R) {G' : System}
    (hstep : ResStep G G') : False := by
  cases hstep with
  | @intro v xv yv C D z happ =>
    have he : vset (Rowpartition.mk v {xv} C) = ∅ ∨ vset (Rowpartition.mk v {xv} C) = R :=
      h.vset_shape _ happ.mem₁
    rw [vset_mk] at he
    have h2 := h.two_le
    rcases he with he | he
    · exact absurd he (by simp)
    · rw [← he, Finset.card_singleton] at h2
      omega

/-- Self-substitution is blocked: it needs the left-hand variable on its own right, and
under the invariant left-hand sides are outside `R` while right-hand sides are inside. -/
theorem Blocked.no_selfSubstStep {G : System} {R : Finset Var} (h : Blocked G R)
    {G' : System} (hstep : SelfSubstStep G G') : False := by
  cases hstep with
  | @intro c v happ =>
    exact h.lhs_notMem c happ.mem (h.vset_subset happ.mem happ.self)

/-- Common partition is blocked: it needs two constraints with the same right-hand side
and different left-hand sides, which `distinct` forbids. -/
theorem Blocked.no_commonPartStep {G : System} {R : Finset Var} (h : Blocked G R)
    {G' : System} (hstep : CommonPartStep G G') : False := by
  cases hstep with
  | @intro c d happ =>
    exact h.distinct c happ.mem₁ d happ.mem₂ happ.lhs_ne happ.vset_eq happ.conc_eq

/-- **NOT ONE non-generative rule applies to a blocked system.** -/
theorem Blocked.no_nongenStep {G : System} {R : Finset Var} (h : Blocked G R) {G' : System}
    (hstep : NonGenStep G G') : False := by
  cases hstep with
  | cse hs => exact h.no_cutStep hs
  | split hs => exact h.no_splitReuseStep hs
  | cancel hs => exact h.no_cancelStep hs
  | subst hs => exact h.no_substStep hs
  | selfSubst hs => exact h.no_selfSubstStep hs
  | commonPart hs => exact h.no_commonPartStep hs

/-- **A blocked system is STUCK under the non-generative calculus**: its only
non-generative saturation is itself. -/
theorem Blocked.nongen_stuck {R : Finset Var} : ∀ {n : ℕ} {G G' : System},
    NonGenSteps n G G' → Blocked G R → G' = G ∧ n = 0 := by
  intro n G G' hsteps
  induction hsteps with
  | refl => exact fun _ => ⟨rfl, rfl⟩
  | @tail m Ga Gb Gc _ hstep ih =>
    intro hb
    obtain ⟨rfl, -⟩ := ih hb
    exact absurd hstep fun hs => hb.no_nongenStep hs

/-! ### And no concrete-label refuter fires

Both surviving error conditions need a variable that is BOTH defined by one constraint
and used on the right of another.  The invariant forbids that outright. -/

/-- The duplicated-field condition cannot fire on a blocked system. -/
theorem Blocked.not_firesMerge {G : System} {R : Finset Var} (h : Blocked G R) :
    ¬ FiresMerge G := by
  rintro ⟨c, hc, d, hd, hocc, -⟩
  exact h.lhs_notMem d hd (h.vset_subset hc hocc)

/-- The infinite-row condition cannot fire on a blocked system. -/
theorem Blocked.not_firesInfRow {G : System} {R : Finset Var} (h : Blocked G R) :
    ¬ FiresInfRow G := by
  rintro ⟨c, hc, hocc, -⟩
  exact h.lhs_notMem c hc (h.vset_subset hc hocc)

/-- **The general theorem.**  A blocked system defeats the non-generative calculus
completely: it cannot move, and neither concrete-label error condition fires on it -- no
matter how unsatisfiable it is.  The next section exhibits an unsatisfiable member of the
class. -/
theorem blocked_defeats_nongen {G : System} {R : Finset Var} (h : Blocked G R) :
    (∀ (n : ℕ) (G' : System), NonGenSteps n G G' → G' = G) ∧
      ¬ FiresMerge G ∧ ¬ FiresInfRow G :=
  ⟨fun _ _ hs => (Blocked.nongen_stuck hs h).1, h.not_firesMerge, h.not_firesInfRow⟩

/-! ### The witness is blocked -/

namespace Der06

/-- **`der06` satisfies the blocking invariant** at its two-variable remainder.  All four
clauses read off the four constraints: `t` and `u` are never on the right; the two givens
have right-hand side exactly `{x, y}` and the two instantiations have none; both givens
carry a nonempty concrete part, so nothing names `{x, y}`; and no two constraints with
different left-hand sides agree on BOTH parts. -/
theorem blocked_derSystem : Blocked derSystem rem := by
  refine ⟨by decide, ?_, ?_, ?_, ?_⟩
  · intro c hc
    rcases mem_derSystem hc with rfl | rfl | rfl | rfl <;> decide
  · intro c hc
    rcases mem_derSystem hc with rfl | rfl | rfl | rfl
    · exact Or.inr vset_g₁
    · exact Or.inr vset_g₂
    · exact Or.inl vset_g₃
    · exact Or.inl vset_g₄
  · intro c hc hv
    rcases mem_derSystem hc with rfl | rfl | rfl | rfl
    · simp [g₁]
    · simp [g₂]
    · rw [vset_g₃] at hv; exact absurd hv (by rw [rem]; decide)
    · rw [vset_g₄] at hv; exact absurd hv (by rw [rem]; decide)
  · intro c hc d hd hne hv
    rcases mem_derSystem hc with rfl | rfl | rfl | rfl <;>
      rcases mem_derSystem hd with rfl | rfl | rfl | rfl <;>
        revert hne hv <;> simp [g₁, g₂, g₃, g₄] <;> decide

/-- Error condition 11 does not fire on the input either: both instantiations DO subsume
the concrete parts of their givens (`(|a|) ⊆ (|a,b,c|)` and `(|b|) ⊆ (|b,c|)`).  The
contradiction is genuinely invisible to every syntactic check the input admits. -/
theorem not_fires11 : ¬ Fires11 derSystem := by
  rintro ⟨c, hc, d, hd, hlhs, hvs, hsub⟩
  rcases mem_derSystem hc with rfl | rfl | rfl | rfl <;>
    rcases mem_derSystem hd with rfl | rfl | rfl | rfl <;>
      revert hlhs hvs hsub <;> simp [g₁, g₂, g₃, g₄]

/-- **On the witness, the ONLY applicable rule is a minting one.**  Every non-generative
rule is blocked, resolution is blocked, and both `splitConcrete`'s mint and
`commonSubexpression`'s mint fire.  Under `-Dermine.genRules=cut` the first of those
survives; under `nongen` neither does, and the solver is stuck on its input. -/
theorem only_minting_applies :
    (∀ G, ¬ NonGenStep derSystem G) ∧ (∀ G, ¬ ResStep derSystem G) ∧
      (∃ G, SplitStep derSystem G) ∧ (∃ G, CseStep derSystem G) :=
  ⟨fun _ hs => blocked_derSystem.no_nongenStep hs,
    fun _ hs => blocked_derSystem.no_resStep hs,
    ⟨der1, step_mint⟩, cse_mint_also_applies⟩

/-- **THE MAIN RESULT: `splitConcrete`'s minting branch is necessary for a refutation.**

1. `derSystem` -- `der06` written out -- has NO MODEL.
2. The calculus that survives the cut refutes it in three steps: one `splitConcrete`
   MINT, then two non-generative steps (`splitConcrete` REUSE and cancellation), after
   which the duplicated-field condition fires -- the very error the shipped compiler
   reports.
3. The fully non-generative calculus cannot take a SINGLE step from `derSystem`, so its
   only saturation of the input is the input.
4. And on the input, none of the three modelled error conditions fires.

Together: an unsatisfiable program that `-Dermine.genRules=cut` rejects and
`-Dermine.genRules=nongen` accepts, with the reason exhibited as a proof rather than as
a measurement.  This is the Lean-level account of the measured `der06` / `der07` /
`der08` regressions. -/
theorem split_necessary :
    (¬ ∃ rho, SModels rho derSystem) ∧
      (CutRuleSteps 3 derSystem der3 ∧ FiresMerge der3) ∧
      (∀ (n : ℕ) (G : System), NonGenSteps n derSystem G → G = derSystem) ∧
      (¬ FiresMerge derSystem ∧ ¬ FiresInfRow derSystem ∧ ¬ Fires11 derSystem) :=
  ⟨derSystem_unsat, ⟨der_cut_steps, fires_der3⟩,
    fun _ _ hs => (Blocked.nongen_stuck hs blocked_derSystem).1,
    blocked_derSystem.not_firesMerge, blocked_derSystem.not_firesInfRow, not_fires11⟩

end Der06

/-! ## 7. The rule hierarchy

Everything above separates into two layers, and the separation is the practical result.

### Layer 1 -- SEMANTICS.  No rule is load-bearing.

Every non-generative rule is outright ENTAILMENT, so it does not move the model set by a
single assignment (`NonGenStep.models_iff`); every minting rule is a CONSERVATIVE
EXTENSION, so it preserves satisfiability in both directions
(`split_mint_conservativeExt`, `ResStep.satisfiable_iff`, and `Cut.mint_conservativeExt`
for the branch that was cut).  A refuter that fires exactly on the unsatisfiable systems
therefore fires on the input iff it fires on anything derived from it, whichever rules
are enabled (`complete_refuter_indifferent`).  **Removing any rule, or all of them, is
sound: it can never make the solver reject a well-typed program**
(`cutRule_never_wrongly_refutes`).

### Layer 2 -- SYNTAX.  Some rules are load-bearing after all.

Ermine does not refute by exhibiting the absence of a model; it refutes when a syntactic
error condition matches a constraint it has DERIVED.  Those conditions are incomplete, so
what matters is not what a rule means but what shapes it makes available.  `Blocked`
identifies a class of systems on which the entire non-generative calculus AND resolution
are inapplicable, and on which the duplicated-field and infinite-row conditions cannot
match; `Der06.derSystem` is an unsatisfiable member of that class.  So:

| rule | semantic role | syntactic role |
| --- | --- | --- |
| CSE reuse (a) | entailment; removable | contraction; no refutation depends on it here |
| CSE fold (b) | entailment; removable | ditto |
| CSE mint (c) | conservative ext | names a shared group -- the cut removes it |
| `splitConcrete` reuse | entailment; removable | needed AFTER a name exists |
| **`splitConcrete` mint** | conservative ext | **LOAD-BEARING** (`Der06.split_necessary`) |
| cancellation | entailment; removable | the only rule that isolates ONE variable; needs a lone leftover |
| substitution | entailment; removable | where the duplicated-field error is raised |
| self-substitution | entailment; removable | blocked on `Blocked` systems |
| common partition | entailment; removable | blocked on `Blocked` systems |
| `resolution` | conservative ext | blocked on `Blocked` systems; diverges (`Cut`) |

### What an implementer may and may not remove

* **May remove, with no change to any verdict on `der06`-shaped input:** nothing that is
  merely a contraction.  Formally: a rule whose removal leaves the system still able to
  reach a firing state.  This file does not prove such a removal safe in general -- it
  proves the CONVERSE for one rule, which is the direction that matters.
* **May NOT remove: at least one rule that mints a name for a shared abstract group of
  size at least two.**  In the shipped rule set the candidates are
  `commonSubexpression`'s branch (c) and `splitConcrete`'s minting branch.  The cut
  removes the first; `Der06.only_minting_applies` shows that on `der06` the second is
  then the only rule in the whole calculus that can fire, and
  `Der06.split_necessary` shows that without it the refutation is lost.  That is exactly
  the measured `cut` = 40/40, `nongen` = 35/40.
* **The reason, stated once:** cancellation is the only rule that turns a partition into
  a fully concrete fact about a single variable, and `Constraints.scala:1029` requires
  its leftover to be a LONE variable.  A remainder of two or more variables is therefore
  inert until something gives it ONE name.  When nothing names it yet, only a minting
  rule can (`Blocked.no_cutStep`, `Blocked.no_splitReuseStep`).

### What is NOT proved here

* That cancellation, substitution or the CSE branches are individually necessary for
  some other refutation.  Each is proved SOUND and shown to be used on the witness path;
  no impossibility theorem is offered for their removal.
* That `Blocked` characterises the systems `nongen` mishandles.  It is a sufficient
  condition -- one that `der06`, and by inspection `der07` and `der08`, satisfy.
* Anything about the other two lost cases, `inc08` and `mis02`.  `RESULTS.md` attributes
  them to the same mechanism (a remainder of two or more variables), but they are
  reported through the unifier, which this model does not contain.
* The within-constraint form of the duplicated-field error (`Rules.rule10`, which needs
  `Rules.RawConstraint`).  `FiresMerge` here is the substitution-time form, which is the
  one `der06` actually triggers. -/

/-- **No run of the cut calculus can wrongly refute.**  `Cut.cut_never_wrongly_refutes`
covers cut-only CSE runs; this covers the whole surviving rule set, minting included. -/
theorem cutRule_never_wrongly_refutes (R : Refuter) {n : ℕ} {G₀ G : System}
    (h : CutRuleSteps n G₀ G) (hfire : R.fires G) : ¬ ∃ rho, SModels rho G₀ :=
  fun hsat => R.sound G hfire (h.satisfiable_iff.mp hsat)

/-- **A complete refuter is indifferent to every rule.**  So no rule carries semantic
information, and any refutation a rule set can lose is lost purely to the INCOMPLETENESS
of the syntactic error conditions. -/
theorem complete_refuter_indifferent (R : System → Prop)
    (hcomp : ∀ H : System, R H ↔ ¬ ∃ rho, SModels rho H) {G G' : System}
    (h : CutRuleStep G G') : R G ↔ R G' := by
  rw [hcomp, hcomp]
  exact not_congr h.satisfiable_iff

/-- **The hierarchy, as one theorem.**

(i) The non-generative rules do not move the model set, and every cut-calculus step
preserves satisfiability both ways -- so at the level of MEANING no rule is load-bearing,
and a complete refuter cannot tell any of them apart (ii).  (iii) Nevertheless minting IS
load-bearing at the level of the solver's actual, incomplete, syntactic checks: an
unsatisfiable system that the cut calculus refutes in three steps and on which the fully
non-generative calculus cannot take even one. -/
theorem rule_hierarchy :
    (∀ G G' : System, NonGenStep G G' → ∀ rho, SModels rho G ↔ SModels rho G') ∧
      (∀ G G' : System, CutRuleStep G G' →
        ((∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G'))) ∧
      (∀ R : System → Prop, (∀ H : System, R H ↔ ¬ ∃ rho, SModels rho H) →
        ∀ G G' : System, CutRuleStep G G' → (R G ↔ R G')) ∧
      ((¬ ∃ rho, SModels rho Der06.derSystem) ∧
        CutRuleSteps 3 Der06.derSystem Der06.der3 ∧ FiresMerge Der06.der3 ∧
        (∀ (n : ℕ) (G : System), NonGenSteps n Der06.derSystem G → G = Der06.derSystem) ∧
        ¬ FiresMerge Der06.derSystem) :=
  ⟨fun _ _ h => h.models_iff, fun _ _ h => h.satisfiable_iff,
    fun R hcomp _ _ h => complete_refuter_indifferent R hcomp h,
    Der06.derSystem_unsat, Der06.der_cut_steps, Der06.fires_der3,
    (fun _ _ hs => (Blocked.nongen_stuck hs Der06.blocked_derSystem).1),
    Der06.blocked_derSystem.not_firesMerge⟩

end Rowpartition
