/-
# The minting branch introduces no concrete label

`Cut.lean` settles the SEMANTIC question about cutting branch (c) of
`commonSubexpression`: the models never move (`cut_preserves_meaning`), so a lost
refutation could only ever come from the incompleteness of the solver's SYNTACTIC error
conditions (`complete_refuter_unaffected`).  That leaves the empirical question the
measurements raise.  A 40-case should-fail corpus is rejected 40/40 by the shipped
solver and 40/40 by the cut, with identical messages; three of Ermine's five error
conditions -- duplicated field, incompatible instantiations, infinite row -- are about
CONCRETE LABELS.  This file explains why that is not a coincidence.

Verbatim from `Constraints.scala`, the minting branch emits

```
Partition(z, rhsCommon, ...)                          -- conc = EMPTY
Partition(v, RHS((abstr1 -- int) + z, concr1), ...)   -- conc = concr1, the premise's own
Partition(u, RHS((abstr2 -- int) + z, concr2), ...)   -- conc = concr2, the premise's own
```

so the only concrete parts it can emit are `∅` and the two it was handed.

## Results

**Section 1** defines the two notions of concrete content: `concs G`, the finset of
concrete PARTS occurring in a system (already in `Cut.lean`), and `concLabelsS G`, the
finset of LABELS they mention.  Multiplicity is not represented -- `System` is a
`Finset Constraint` -- and section 2 explains why the finset is the right object anyway.

**Section 2, one step.**  `concs_cseResult` is the sharp statement:
`concs (cseResult G c₁ c₂ z) = insert ∅ (concs G)`, and modulo the empty part the two
are literally equal (`concs_cseResult_sdiff`).  At the level of labels there is not even
an empty-part caveat: `CseStep.concLabelsS_eq` says a minting step preserves the label
set ON THE NOSE.  The same holds for the kept branches (`CutStep.concs_eq`, which needs
no `insert ∅`), for `splitConcrete`, and -- this is the one that is not obvious -- for
`resolution` (`ResStep.concLabelsS_eq`), whose conclusions carry `C ∪ D`, `D \ C` and
`C \ D` built from its premises' own concrete parts.

**Section 3, the closure -- the honest part.**  The two invariants behave differently.

* The LABEL invariant survives everything: `FullSteps.concLabelsS_eq` proves
  `concLabelsS G = concLabelsS G₀` along any run of the WHOLE rule set (all three CSE
  branches, `resolution`, `splitConcrete`).  So outcome (i) holds for labels.
* The PART invariant does NOT survive the closure, and the failure is caused by a MINT
  step.  `mint_enables_new_concrete_part` exhibits a three-constraint system `GE` on
  which `resolution` cannot fire at all, a mint step that makes it fire, and the
  resulting new concrete part `{1,6}` -- neither empty nor present in `GE`.  So outcome
  (ii) holds for parts, with a concrete counterexample, and it is exactly the scenario
  the task anticipated: minting enables a later step whose conclusion has a concrete
  part not previously present.

The mechanism is worth stating: `resolution` needs two premises of arity ONE with the
same left-hand side, and a mint step is the thing that turns an arity-`k` premise into
an arity-one one (`reduce c₁ int z` has right-hand side `{z}` exactly when
`vset c₁ = int`).  That is a real interaction, not an artefact.

**Section 4, the payoff.**  A refuter fires on syntax, so the right question is which
syntactic tests a branch can TURN ON.  `Shadowed G c` is the syntactic sufficient
condition: `c` has at least one right-hand variable, and either an empty concrete part
or the left-hand side and concrete part of a constraint already in `G`.  A
`ConcRefuter` is a `Refuter` that `Shadowed` additions cannot turn on.  All three CSE
branches, and `splitConcrete`, emit only `Shadowed` constraints
(`CseBranch.fires_imp`, `SplitStep.fires_imp`), whence

> `cut_cannot_lose_concrete_refutation`: for a `ConcRefuter`, any cut run, any full run
> and the INPUT all fire together.

Ermine's incompatible-instantiations condition (`refuterIncompat`) and condition 11
(`refuter11`, from `Cut.lean`) are `ConcRefuter`s.

**The weaker statement, and exactly what is missing.**  The infinite-row condition is
`∃ c ∈ G, c.lhs ∈ vset c ∧ c.conc ≠ ∅`, which reads a variable fact (`lhs ∈ vset`) as
well as a concrete one, and it is NOT a `ConcRefuter`: `reuse_can_create_infinite_row`
builds a REUSE step -- a branch the cut KEEPS -- that turns it on.  For it the right
class is `MintBlindRefuter`, blind to the stronger `MintShadowed` (which additionally
tracks self-loops), and the theorem is one-sided in the safe direction:
`mint_run_fires_iff` says a MINT-ONLY run cannot turn an infinite-row test on, so
`cut_keeps_mintBlind_refutations` transfers it to any cut run.  What is NOT proved is
the mixed case: a full run that interleaves mint with reuse/fold, whose reuse steps use
minted material as premises, is not simulated by any cut run here.  Section 5 says so
explicitly.
-/
import Rowpartition.Cut

namespace Rowpartition

/-! ## 1. The concrete content of a system

Two projections.  `concs` (defined in `Cut.lean`) is the set of concrete PARTS; the new
`concLabelsS` is the set of LABELS those parts mention.  They are genuinely different
invariants -- section 3 breaks the first and keeps the second.

A word on multiplicity.  The task allows a multiset of concrete parts.  `System` is a
`Finset Constraint`, so a system does not record how many times a constraint occurs and
a multiset of concrete parts would be an artefact of the representation, not of the
solver: the minting branch emits `concr1` a second time, but as a constraint with a
DIFFERENT right-hand side, which the finset of parts already accounts for.  The finset
is therefore the faithful object, and it is what is used below. -/

/-- Every concrete label mentioned by a system. -/
def concLabelsS (G : System) : Finset Label := G.biUnion Constraint.conc

theorem mem_concLabelsS {G : System} {l : Label} :
    l ∈ concLabelsS G ↔ ∃ c ∈ G, l ∈ c.conc := by
  simp [concLabelsS]

/-- The systems-as-finsets version agrees with `Basic.concLabels`. -/
theorem concLabelsS_eq_concLabels (G : System) : concLabelsS G = concLabels G.toList := by
  ext l
  rw [mem_concLabelsS, mem_concLabels]
  simp

theorem conc_subset_concLabelsS {G : System} {c : Constraint} (hc : c ∈ G) :
    c.conc ⊆ concLabelsS G := fun _ hl => mem_concLabelsS.mpr ⟨c, hc, hl⟩

theorem concLabelsS_mono {G G' : System} (h : G ⊆ G') : concLabelsS G ⊆ concLabelsS G' := by
  intro l hl
  obtain ⟨c, hc, hlc⟩ := mem_concLabelsS.mp hl
  exact mem_concLabelsS.mpr ⟨c, h hc, hlc⟩

theorem mem_concs {G : System} {k : Row} : k ∈ concs G ↔ ∃ c ∈ G, c.conc = k := by
  simp [concs]

theorem conc_mem_concs {G : System} {c : Constraint} (hc : c ∈ G) : c.conc ∈ concs G :=
  mem_concs.mpr ⟨c, hc, rfl⟩

theorem concs_mono {G G' : System} (h : G ⊆ G') : concs G ⊆ concs G' := by
  intro k hk
  obtain ⟨c, hc, rfl⟩ := mem_concs.mp hk
  exact conc_mem_concs (h hc)

/-- The workhorse for every label-preservation proof below: a supersystem whose
constraints mention no new label has the same label set. -/
theorem concLabelsS_eq_of_subset {G G' : System} (hsub : G ⊆ G')
    (h : ∀ c ∈ G', c.conc ⊆ concLabelsS G) : concLabelsS G' = concLabelsS G := by
  refine Finset.Subset.antisymm (fun l hl => ?_) (concLabelsS_mono hsub)
  obtain ⟨c, hc, hlc⟩ := mem_concLabelsS.mp hl
  exact h c hc hlc

/-! ## 2. One step

The minting branch first, then the branches the cut keeps, then the two other generative
rules the cut leaves alone. -/

/-- **What the minting branch can emit.**  Every constraint of the successor system is
either already present, or has concrete part `∅`, `c₁.conc` or `c₂.conc` -- and the
latter two are the PREMISES' OWN.  This is the Scala verbatim: `rhsCommon` carries no
concrete part, and the two rewritten premises carry `concr1` and `concr2`. -/
theorem mint_conc {G : System} {c₁ c₂ : Constraint} {z : Var} {c : Constraint}
    (hc : c ∈ cseResult G c₁ c₂ z) :
    c ∈ G ∨ c.conc = ∅ ∨ c.conc = c₁.conc ∨ c.conc = c₂.conc := by
  simp only [cseResult, Finset.mem_insert] at hc
  rcases hc with rfl | rfl | rfl | hc
  · exact Or.inr (Or.inl rfl)
  · exact Or.inr (Or.inr (Or.inl rfl))
  · exact Or.inr (Or.inr (Or.inr rfl))
  · exact Or.inl hc

/-- **The sharp one-step statement for concrete PARTS.**  A minting step adds the empty
part and nothing else. -/
theorem concs_cseResult {G : System} {c₁ c₂ : Constraint} (h₁ : c₁ ∈ G) (h₂ : c₂ ∈ G)
    (z : Var) : concs (cseResult G c₁ c₂ z) = insert ∅ (concs G) := by
  refine Finset.Subset.antisymm (fun k hk => ?_) ?_
  · obtain ⟨c, hc, rfl⟩ := mem_concs.mp hk
    rcases mint_conc hc with hc' | hc' | hc' | hc'
    · exact Finset.mem_insert_of_mem (conc_mem_concs hc')
    · exact hc' ▸ Finset.mem_insert_self _ _
    · exact hc' ▸ Finset.mem_insert_of_mem (conc_mem_concs h₁)
    · exact hc' ▸ Finset.mem_insert_of_mem (conc_mem_concs h₂)
  · intro k hk
    rcases Finset.mem_insert.mp hk with rfl | hk'
    · exact conc_mem_concs (G := cseResult G c₁ c₂ z)
        (c := mk z (shared c₁ c₂) ∅) (Finset.mem_insert_self _ _)
    · exact concs_mono (subset_cseResult G c₁ c₂ z) hk'

/-- The same, with the empty part quotiented out: apart from `∅`, minting changes the
set of concrete parts NOT AT ALL. -/
theorem concs_cseResult_sdiff {G : System} {c₁ c₂ : Constraint} (h₁ : c₁ ∈ G) (h₂ : c₂ ∈ G)
    (z : Var) : concs (cseResult G c₁ c₂ z) \ {∅} = concs G \ {∅} := by
  rw [concs_cseResult h₁ h₂ z]
  ext k
  simp only [Finset.mem_sdiff, Finset.mem_insert, Finset.mem_singleton]
  tauto

/-- **The headline one-step claim.**  A minting step introduces no concrete label that
was not already present -- and loses none either: the label set is preserved exactly,
with no empty-part caveat. -/
theorem CseStep.concLabelsS_eq {G G' : System} (h : CseStep G G') :
    concLabelsS G' = concLabelsS G := by
  cases h with
  | @intro c₁ c₂ z happ =>
    refine concLabelsS_eq_of_subset (subset_cseResult _ _ _ _) fun c hc => ?_
    rcases mint_conc hc with hc' | hc' | hc' | hc'
    · exact conc_subset_concLabelsS hc'
    · rw [hc']; exact Finset.empty_subset _
    · rw [hc']; exact conc_subset_concLabelsS happ.mem₁
    · rw [hc']; exact conc_subset_concLabelsS happ.mem₂

/-! ### The kept branches

Sharper still: `reduce` copies its premise's concrete part verbatim, so the kept
branches do not even add `∅`. -/

theorem cutStep_conc {G G' : System} (h : CutStep G G') {c : Constraint} (hc : c ∈ G') :
    ∃ d ∈ G, c.conc = d.conc := by
  cases h with
  | @reuse c₁ c₂ z hp _ =>
    simp only [reuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact ⟨c₁, hp.mem₁, rfl⟩
    · exact ⟨c₂, hp.mem₂, rfl⟩
    · exact ⟨c, hc, rfl⟩
  | @fold c₁ c₂ hp _ _ =>
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact ⟨c₂, hp.mem₂, rfl⟩
    · exact ⟨c, hc', rfl⟩

/-- **The kept branches preserve the concrete parts exactly.** -/
theorem CutStep.concs_eq {G G' : System} (h : CutStep G G') : concs G' = concs G := by
  refine Finset.Subset.antisymm (fun k hk => ?_) (concs_mono h.subset)
  obtain ⟨c, hc, rfl⟩ := mem_concs.mp hk
  obtain ⟨d, hd, hcd⟩ := cutStep_conc h hc
  exact hcd ▸ conc_mem_concs hd

theorem CutStep.concLabelsS_eq {G G' : System} (h : CutStep G G') :
    concLabelsS G' = concLabelsS G := by
  refine concLabelsS_eq_of_subset h.subset fun c hc => ?_
  obtain ⟨d, hd, hcd⟩ := cutStep_conc h hc
  rw [hcd]
  exact conc_subset_concLabelsS hd

/-- All three branches together. -/
theorem CseBranch.concLabelsS_eq {G G' : System} (h : CseBranch G G') :
    concLabelsS G' = concLabelsS G := by
  cases h with
  | reuse hp hn => exact (CutStep.reuse hp hn).concLabelsS_eq
  | fold hp h1 h2 => exact (CutStep.fold hp h1 h2).concLabelsS_eq
  | mint happ => exact (CseStep.intro happ).concLabelsS_eq

/-! ### The two other generative rules

`splitConcrete` behaves like minting: an empty part and a verbatim copy.  `resolution`
does NOT -- it builds `C ∪ D`, `D \ C` and `C \ D`, which are new PARTS.  But every
label in them comes from `C` or `D`, which are its premises' own concrete parts, so the
LABEL invariant survives it. -/

theorem SplitStep.concLabelsS_eq {G G' : System} (h : SplitStep G G') :
    concLabelsS G' = concLabelsS G := by
  cases h with
  | @intro c u happ =>
    refine concLabelsS_eq_of_subset (subset_splitResult _ _ _) fun d hd => ?_
    simp only [splitResult, Finset.mem_insert] at hd
    rcases hd with rfl | rfl | hd
    · exact Finset.empty_subset _
    · exact conc_subset_concLabelsS (c := c) happ.mem
    · exact conc_subset_concLabelsS hd

/-- **`resolution` preserves the label set** even though it does not preserve the set of
parts: `C ∪ D`, `D \ C` and `C \ D` are all built from `C` and `D`. -/
theorem ResStep.concLabelsS_eq {G G' : System} (h : ResStep G G') :
    concLabelsS G' = concLabelsS G := by
  cases h with
  | @intro v x y C D z happ =>
    have hC : C ⊆ concLabelsS G := conc_subset_concLabelsS (c := mk v {x} C) happ.mem₁
    have hD : D ⊆ concLabelsS G := conc_subset_concLabelsS (c := mk v {y} D) happ.mem₂
    refine concLabelsS_eq_of_subset (subset_resResult _ _ _ _ _ _ _) fun d hd => ?_
    simp only [resResult, Finset.mem_insert] at hd
    rcases hd with rfl | rfl | rfl | hd
    · exact Finset.union_subset hC hD
    · exact (Finset.sdiff_subset).trans hD
    · exact (Finset.sdiff_subset).trans hC
    · exact conc_subset_concLabelsS hd

/-! ## 3. The closure

Item 3 of the task.  A minting step could in principle enable a LATER step whose
conclusion has a concrete part not previously present.  It CAN -- and does, via
`resolution`.  The label invariant nevertheless survives the whole rule set. -/

/-- The complete rule set under discussion: all three CSE branches, `resolution` and
`splitConcrete`.  (The cut removes exactly the `mint` case of `CseBranch`.) -/
inductive FullRule : System → System → Prop
  | cse {G G' : System} : CseBranch G G' → FullRule G G'
  | res {G G' : System} : ResStep G G' → FullRule G G'
  | split {G G' : System} : SplitStep G G' → FullRule G G'

theorem FullRule.concLabelsS_eq {G G' : System} (h : FullRule G G') :
    concLabelsS G' = concLabelsS G := by
  cases h with
  | cse h => exact h.concLabelsS_eq
  | res h => exact h.concLabelsS_eq
  | split h => exact h.concLabelsS_eq

/-- `FullSteps n G G'`: `G'` is reachable from `G` by `n` steps of the whole rule set. -/
inductive FullSteps : ℕ → System → System → Prop
  | refl (G : System) : FullSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      FullSteps n G G' → FullRule G' G'' → FullSteps (n + 1) G G''

/-- **Outcome (i), for labels.**  The set of concrete labels is an invariant of the
ENTIRE closure: no rule of the solver -- minting included -- ever mentions a label the
input did not. -/
theorem FullSteps.concLabelsS_eq {n : ℕ} {G₀ G : System} (h : FullSteps n G₀ G) :
    concLabelsS G = concLabelsS G₀ := by
  induction h with
  | refl => rfl
  | tail _ hstep ih => rw [hstep.concLabelsS_eq]; exact ih

theorem BranchSteps.concLabelsS_eq {n : ℕ} {G₀ G : System} (h : BranchSteps n G₀ G) :
    concLabelsS G = concLabelsS G₀ := by
  induction h with
  | refl => rfl
  | tail _ hstep ih => rw [hstep.concLabelsS_eq]; exact ih

theorem CutSteps.concLabelsS_eq {n : ℕ} {G₀ G : System} (h : CutSteps n G₀ G) :
    concLabelsS G = concLabelsS G₀ := h.toBranchSteps.concLabelsS_eq

theorem CseBranch.concs_subset {G G' : System} (h : CseBranch G G') :
    concs G' ⊆ insert ∅ (concs G) := by
  cases h with
  | reuse hp hn => rw [(CutStep.reuse hp hn).concs_eq]; exact Finset.subset_insert _ _
  | fold hp h1 h2 => rw [(CutStep.fold hp h1 h2).concs_eq]; exact Finset.subset_insert _ _
  | @mint c₁ c₂ z happ =>
    rw [concs_cseResult happ.mem₁ happ.mem₂ z]

/-- The PART invariant does survive an all-CSE closure, which is the closure the cut is
about: any run of the three branches only ever adds the empty part.  Section 3's
counterexample needs `resolution` as well as minting, and that is exactly the point --
minting is what makes `resolution` applicable. -/
theorem BranchSteps.concs_subset {n : ℕ} {G₀ G : System} (h : BranchSteps n G₀ G) :
    concs G ⊆ insert ∅ (concs G₀) := by
  induction h with
  | refl G => exact Finset.subset_insert _ _
  | @tail n G G' G'' _ hstep ih =>
    intro k hk
    rcases Finset.mem_insert.mp (hstep.concs_subset hk) with rfl | hk'
    · exact Finset.mem_insert_self _ _
    · exact ih hk'

/-! ### Outcome (ii): a MINT step enables a new concrete PART

The scenario the task asks to look for, realised.  `resolution` fires on two premises of
arity ONE with the same left-hand side, and its conclusions carry the genuinely new
concrete parts `C ∪ D`, `D \ C`, `C \ D`.  A mint step is precisely what can turn a
premise of arity `k` into one of arity one: `reduce c₁ int z` has right-hand side `{z}`
exactly when `vset c₁ = int`.

```
GE:   a <- (p, q, (|1|))          -- arity 2: resolution cannot use it
      b <- (p, q, r)
      a <- (s, (|6|))             -- arity 1, but there is no second arity-1 partition of a

MINT on the first two (int = {p,q}, fresh z):
      z <- (p, q)
      a <- (z, (|1|))             -- NOW arity 1, and its left-hand side is `a`
      b <- (r, z)

RESOLUTION on  a <- (z, (|1|))  and  a <- (s, (|6|)):
      a <- (w, (|1,6|))           -- the concrete part {1,6} is NEW
```
-/

namespace NewConcEx

/-- `a <- (p, q, (|1|))` -- arity two, so `resolution` cannot use it. -/
def a₁ : Constraint := mk 0 {2, 3} ({1} : Row)

/-- `b <- (p, q, r)`. -/
def a₂ : Constraint := mk 1 {2, 3, 4} (∅ : Row)

/-- `a <- (s, (|6|))` -- arity one, but it has no partner. -/
def a₃ : Constraint := mk 0 {5} ({6} : Row)

/-- The three-constraint input. -/
def GE : System := {a₁, a₂, a₃}

theorem sharedE : shared a₁ a₂ = {2, 3} := by
  rw [a₁, a₂, shared, vset_mk, vset_mk]; decide

theorem freshE : (7 : Var) ∉ allVars GE := by
  intro h
  rw [allVars, Finset.mem_biUnion] at h
  obtain ⟨c, hc, hv⟩ := h
  simp only [GE, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl <;> revert hv <;> simp [a₁, a₂, a₃]

/-- The mint step's side conditions hold. -/
theorem appE : CseApp GE a₁ a₂ 7 :=
  ⟨by simp [GE], by simp [GE], by decide, by rw [sharedE]; decide, freshE⟩

/-- The system after the mint step. -/
def GM : System := cseResult GE a₁ a₂ 7

/-- The rewritten first premise has arity ONE, which is what makes `resolution`
applicable to it. -/
theorem red₁ : reduce a₁ (shared a₁ a₂) 7 = mk 0 {7} ({1} : Row) := by
  have h : insert (7 : Var) ((({2, 3} : Finset Var)) \ {2, 3}) = ({7} : Finset Var) := by decide
  rw [reduce, sharedE, a₁, vset_mk, h]
  rfl

theorem mem_red₁ : mk 0 {7} ({1} : Row) ∈ GM := by
  rw [← red₁, GM, cseResult]
  exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)

theorem mem_a₃ : mk 0 {5} ({6} : Row) ∈ GM :=
  subset_cseResult GE a₁ a₂ 7 (by simp [GE, a₃])

/-- **`resolution` cannot fire on the input at all.**  It needs two arity-one partitions
of the SAME variable; `GE` has exactly one arity-one constraint. -/
theorem no_res_GE : ∀ H : System, ¬ ResStep GE H := by
  intro H h
  cases h with
  | @intro v x y C D z happ =>
    have key : ∀ {w u : Var} {K : Row}, mk w {u} K ∈ GE → K = {6} := by
      intro w u K hmem
      simp only [GE, Finset.mem_insert, Finset.mem_singleton] at hmem
      rcases hmem with hmem | hmem | hmem
      · rw [a₁] at hmem
        have hs := (mk_inj hmem).2.1
        have := congrArg Finset.card hs
        simp at this
      · rw [a₂] at hmem
        have hs := (mk_inj hmem).2.1
        have := congrArg Finset.card hs
        simp at this
      · rw [a₃] at hmem
        exact (mk_inj hmem).2.2
    have hC := key happ.mem₁
    have hD := key happ.mem₂
    exact happ.tops (by rw [hC, hD]; decide)

/-- The resolution step that the mint step unlocked, with its brand-new concrete part
`{1} ∪ {6}`. -/
theorem res_after_mint (z : Var) (hz : z ∉ allVars GM) :
    ResStep GM (resResult GM 0 7 5 ({1} : Row) ({6} : Row) z) :=
  ResStep.intro ⟨mem_red₁, mem_a₃, by decide, by decide, hz⟩

theorem new_part_mem (z : Var) :
    ({1, 6} : Row) ∈ concs (resResult GM 0 7 5 ({1} : Row) ({6} : Row) z) := by
  refine conc_mem_concs (c := mk 0 {z} (({1} : Row) ∪ {6})) ?_
  exact Finset.mem_insert_self _ _

theorem new_part_not_old : ({1, 6} : Row) ∉ insert (∅ : Row) (concs GE) := by
  intro h
  rcases Finset.mem_insert.mp h with h' | h'
  · exact absurd h' (by decide)
  · obtain ⟨c, hc, hcc⟩ := mem_concs.mp h'
    simp only [GE, Finset.mem_insert, Finset.mem_singleton] at hc
    rcases hc with rfl | rfl | rfl
    · rw [a₁, conc_mk] at hcc; exact absurd hcc (by decide)
    · rw [a₂, conc_mk] at hcc; exact absurd hcc (by decide)
    · rw [a₃, conc_mk] at hcc; exact absurd hcc (by decide)

end NewConcEx

/-- **OUTCOME (ii), LOUDLY.**  The set of concrete PARTS is NOT preserved by the closure,
and the culprit is the minting branch.  There is a system `GE` on which `resolution`
cannot fire at all; a single MINT step produces `GM`, on which it can; and the resulting
system carries the concrete part `{1,6}`, which is neither empty nor present in `GE`.

So the invariant of section 2 -- "the emitted concrete parts are exactly `∅`, `concr1`
and `concr2`" -- is a genuine ONE-STEP theorem that does NOT lift to the closure at the
level of parts.  What lifts is the LABEL invariant (`FullSteps.concLabelsS_eq`), and
indeed `{1,6} ⊆ concLabelsS GE = {1,6}`. -/
theorem mint_enables_new_concrete_part :
    ∃ (G G' G'' : System), (∀ H : System, ¬ ResStep G H) ∧ CseStep G G' ∧ ResStep G' G'' ∧
      ¬ concs G'' ⊆ insert ∅ (concs G) := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars NewConcEx.GM)
  refine ⟨NewConcEx.GE, NewConcEx.GM, _, NewConcEx.no_res_GE, CseStep.intro NewConcEx.appE,
    NewConcEx.res_after_mint z hz, fun hsub => ?_⟩
  exact NewConcEx.new_part_not_old (hsub (NewConcEx.new_part_mem z))

/-- The same situation seen through the LABEL invariant, which does hold: the new part
`{1,6}` mentions only labels the input already had. -/
theorem new_part_labels_are_old :
    concLabelsS NewConcEx.GE = ({1, 6} : Finset Label) := by
  ext l
  rw [mem_concLabelsS]
  constructor
  · rintro ⟨c, hc, hlc⟩
    simp only [NewConcEx.GE, Finset.mem_insert, Finset.mem_singleton] at hc
    rcases hc with rfl | rfl | rfl
    · rw [NewConcEx.a₁, conc_mk] at hlc
      exact Finset.mem_insert.mpr (Or.inl (Finset.mem_singleton.mp hlc))
    · rw [NewConcEx.a₂, conc_mk] at hlc
      exact absurd hlc (by simp)
    · rw [NewConcEx.a₃, conc_mk] at hlc
      exact Finset.mem_insert_of_mem hlc
  · intro hl
    rcases Finset.mem_insert.mp hl with rfl | hl'
    · exact ⟨NewConcEx.a₁, by simp [NewConcEx.GE], by rw [NewConcEx.a₁, conc_mk]; simp⟩
    · rw [Finset.mem_singleton] at hl'
      subst hl'
      exact ⟨NewConcEx.a₃, by simp [NewConcEx.GE], by rw [NewConcEx.a₃, conc_mk]; simp⟩

/-! ## 4. The payoff: concrete-label refuters

A solver does not refute by exhibiting the absence of a model; it refutes when a
syntactic ERROR CONDITION fires (`Cut.Refuter`).  So the operative question is not "what
does a branch mean" but "which syntactic tests can a branch TURN ON".

`Shadowed G c` is the syntactic sufficient condition for "`c` shows nothing concrete
that `G` does not already show": `c` has at least one right-hand VARIABLE -- so it is
not a fully concrete partition -- and either its concrete part is empty, or some
constraint of `G` already carries `c`'s left-hand side together with `c`'s concrete
part.  Every constraint every CSE branch emits is `Shadowed`, and so is every
constraint `splitConcrete` emits. -/

/-- `c` adds no concrete information to `G`: it has a right-hand variable, and either an
empty concrete part or the left-hand side and concrete part of a constraint of `G`. -/
def Shadowed (G : System) (c : Constraint) : Prop :=
  vset c ≠ ∅ ∧ (c.conc = ∅ ∨ ∃ d ∈ G, d.lhs = c.lhs ∧ d.conc = c.conc)

theorem Shadowed.mono {G G' : System} (hsub : G ⊆ G') {c : Constraint} (h : Shadowed G c) :
    Shadowed G' c := by
  refine ⟨h.1, ?_⟩
  rcases h.2 with h' | ⟨d, hd, h1, h2⟩
  · exact Or.inl h'
  · exact Or.inr ⟨d, hsub hd, h1, h2⟩

theorem ne_empty_of_two_le_card {S : Finset Var} (h : 2 ≤ S.card) : S ≠ ∅ := by
  intro he
  rw [he] at h
  simp at h

/-- The naming constraint `z <- int` is `Shadowed`: its concrete part is EMPTY, and
`int.size >= 2` gives it a right-hand variable. -/
theorem shadowed_name {G : System} {S : Finset Var} (h : 2 ≤ S.card) (z : Var) :
    Shadowed G (mk z S ∅) :=
  ⟨by rw [vset_mk]; exact ne_empty_of_two_le_card h, Or.inl rfl⟩

/-- A rewritten premise is `Shadowed`: `reduce` copies the left-hand side and the
concrete part of the premise verbatim, and `insert z _` is never empty. -/
theorem shadowed_reduce {G : System} {c : Constraint} (hc : c ∈ G) (S : Finset Var) (z : Var) :
    Shadowed G (reduce c S z) :=
  ⟨by rw [vset_reduce]; exact Finset.insert_ne_empty _ _, Or.inr ⟨c, hc, rfl, rfl⟩⟩

/-- A refuter that no `Shadowed` addition can turn on: its firing depends only on the
concrete content of the system.  This is the class the payoff theorem is about. -/
structure ConcRefuter extends Refuter where
  /-- adding a constraint that shows nothing concretely new cannot make the test fire -/
  blind : ∀ (G : System) (c : Constraint), Shadowed G c → fires (insert c G) → fires G

/-! ### Every branch emits only `Shadowed` constraints -/

/-- **The minting branch cannot turn a concrete-label test on.**  All three emitted
constraints are `Shadowed`: `z <- int` has an empty concrete part, and the two rewritten
premises carry their own premises' concrete parts. -/
theorem CseStep.fires_imp (R : ConcRefuter) {G G' : System} (h : CseStep G G')
    (hf : R.fires G') : R.fires G := by
  cases h with
  | @intro c₁ c₂ z happ =>
    rw [cseResult] at hf
    have h1 := R.blind _ _ (shadowed_name happ.two_le z) hf
    have h2 := R.blind _ _
      ((shadowed_reduce happ.mem₁ (shared c₁ c₂) z).mono (Finset.subset_insert _ _)) h1
    exact R.blind _ _ (shadowed_reduce happ.mem₂ (shared c₁ c₂) z) h2

/-- The kept branches cannot turn one on either. -/
theorem CutStep.fires_imp (R : ConcRefuter) {G G' : System} (h : CutStep G G')
    (hf : R.fires G') : R.fires G := by
  cases h with
  | @reuse c₁ c₂ z hp _ =>
    rw [reuseResult] at hf
    have h1 := R.blind _ _
      ((shadowed_reduce hp.mem₁ (shared c₁ c₂) z).mono (Finset.subset_insert _ _)) hf
    exact R.blind _ _ (shadowed_reduce hp.mem₂ (shared c₁ c₂) z) h1
  | @fold c₁ c₂ hp _ _ =>
    rw [foldResult] at hf
    exact R.blind _ _ (shadowed_reduce hp.mem₂ (shared c₁ c₂) c₁.lhs) hf

theorem CseBranch.fires_imp (R : ConcRefuter) {G G' : System} (h : CseBranch G G')
    (hf : R.fires G') : R.fires G := by
  cases h with
  | reuse hp hn => exact (CutStep.reuse hp hn).fires_imp R hf
  | fold hp h1 h2 => exact (CutStep.fold hp h1 h2).fires_imp R hf
  | mint happ => exact (CseStep.intro happ).fires_imp R hf

/-- `splitConcrete` is in the same class: it emits a naming constraint and a verbatim
copy of its premise's concrete part. -/
theorem SplitStep.fires_imp (R : ConcRefuter) {G G' : System} (h : SplitStep G G')
    (hf : R.fires G') : R.fires G := by
  cases h with
  | @intro c u happ =>
    rw [splitResult] at hf
    have hs1 : Shadowed (insert (mk c.lhs {u} c.conc) G) (mk u (vset c) ∅) :=
      ⟨by rw [vset_mk]; exact ne_empty_of_two_le_card happ.two_le, Or.inl rfl⟩
    have hs2 : Shadowed G (mk c.lhs {u} c.conc) :=
      ⟨by rw [vset_mk]; exact Finset.singleton_ne_empty _, Or.inr ⟨c, happ.mem, rfl, rfl⟩⟩
    exact R.blind _ _ hs2 (R.blind _ _ hs1 hf)

/-! ### Lifting to whole runs -/

theorem BranchSteps.fires_imp {n : ℕ} {G₀ G : System} (h : BranchSteps n G₀ G)
    (R : ConcRefuter) (hf : R.fires G) : R.fires G₀ := by
  induction h with
  | refl => exact hf
  | tail _ hstep ih => exact ih (hstep.fires_imp R hf)

/-- **A concrete-label test fires on a full CSE run iff it fires on the INPUT.**  The
whole common-subexpression search -- minting included -- is invisible to it. -/
theorem ConcRefuter.branchSteps_fires_iff (R : ConcRefuter) {n : ℕ} {G₀ G : System}
    (h : BranchSteps n G₀ G) : R.fires G ↔ R.fires G₀ :=
  ⟨fun hf => h.fires_imp R hf, fun hf => R.mono G₀ G h.subset hf⟩

theorem ConcRefuter.cutSteps_fires_iff (R : ConcRefuter) {n : ℕ} {G₀ G : System}
    (h : CutSteps n G₀ G) : R.fires G ↔ R.fires G₀ :=
  R.branchSteps_fires_iff h.toBranchSteps

/-- **THE PAYOFF.  The cut cannot lose a concrete-label refutation.**  Take any run of
the cut solver and any run of the full solver from the same input.  For a refuter whose
firing depends only on the concrete content, the two fire together -- and both fire
exactly when the INPUT already does.  There is nothing for the minting branch to
contribute, so removing it costs nothing. -/
theorem cut_cannot_lose_concrete_refutation (R : ConcRefuter) {n m : ℕ}
    {G₀ Gcut Gfull : System} (hcut : CutSteps n G₀ Gcut) (hfull : BranchSteps m G₀ Gfull) :
    (R.fires Gcut ↔ R.fires Gfull) ∧ (R.fires Gcut ↔ R.fires G₀) :=
  ⟨(R.cutSteps_fires_iff hcut).trans (R.branchSteps_fires_iff hfull).symm,
    R.cutSteps_fires_iff hcut⟩

/-! ### Two of Ermine's error conditions are `ConcRefuter`s -/

/-- **Incompatible instantiations**: two fully concrete partitions of the same variable
with different concrete parts. -/
def FiresIncompat (G : System) : Prop :=
  ∃ c ∈ G, ∃ d ∈ G, c.lhs = d.lhs ∧ vset c = ∅ ∧ vset d = ∅ ∧ c.conc ≠ d.conc

theorem firesIncompat_sound (G : System) (h : FiresIncompat G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, d, hd, hlhs, hvc, hvd, hne⟩ := h
  have hc' : rho c.lhs = c.conc := by
    have hb := (hm c hc).eq_biUnion
    rw [hvc] at hb
    simpa using hb
  have hd' : rho d.lhs = d.conc := by
    have hb := (hm d hd).eq_biUnion
    rw [hvd] at hb
    simpa using hb
  rw [hlhs, hd'] at hc'
  exact hne hc'.symm

theorem firesIncompat_mono (G G' : System) (hsub : G ⊆ G') (h : FiresIncompat G) :
    FiresIncompat G' := by
  obtain ⟨c, hc, d, hd, h1, h2, h3, h4⟩ := h
  exact ⟨c, hsub hc, d, hsub hd, h1, h2, h3, h4⟩

/-- Incompatible instantiations, as a `ConcRefuter`: neither role can be played by a
`Shadowed` constraint, because both require an EMPTY right-hand variable set. -/
def refuterIncompat : ConcRefuter where
  fires := FiresIncompat
  sound := firesIncompat_sound
  mono := firesIncompat_mono
  blind := by
    rintro G c hs ⟨a, ha, b, hb, h1, h2, h3, h4⟩
    have ha' : a ∈ G := by
      rcases Finset.mem_insert.mp ha with rfl | ha'
      · exact absurd h2 hs.1
      · exact ha'
    have hb' : b ∈ G := by
      rcases Finset.mem_insert.mp hb with rfl | hb'
      · exact absurd h3 hs.1
      · exact hb'
    exact ⟨a, ha', b, hb', h1, h2, h3, h4⟩

/-- Ermine's error condition 11 (`Cut.refuter11`) upgraded to a `ConcRefuter`.  A
`Shadowed` constraint cannot play the fully-concrete role (it has a variable), and it
cannot play the offending role either: its concrete part is either empty -- and `∅` is a
subset of everything -- or already carried by a constraint of `G` with the same
left-hand side. -/
def refuter11' : ConcRefuter where
  fires := Fires11
  sound := fires11_sound
  mono := fires11_mono
  blind := by
    rintro G c hs ⟨a, ha, b, hb, hab, hva, hsub⟩
    have ha' : a ∈ G := by
      rcases Finset.mem_insert.mp ha with rfl | ha'
      · exact absurd hva hs.1
      · exact ha'
    rcases Finset.mem_insert.mp hb with rfl | hb'
    · rcases hs.2 with hce | ⟨d, hd, hdl, hdc⟩
      · exact absurd (by rw [hce]; exact Finset.empty_subset _) hsub
      · exact ⟨a, ha', d, hd, by rw [hab, hdl], hva, by rw [hdc]; exact hsub⟩
    · exact ⟨a, ha', b, hb', hab, hva, hsub⟩

/-- Non-vacuity: `refuterIncompat` and `refuter11'` really do fire on something, and the
payoff theorem therefore says something. -/
theorem concRefuters_nonvacuous :
    refuterIncompat.fires RefuteEx.GB ∧ refuter11'.fires RefuteEx.GB := by
  refine ⟨⟨RefuteEx.cA, by simp [RefuteEx.GB], RefuteEx.cB, by simp [RefuteEx.GB], rfl,
    by simp [RefuteEx.cA, vset], by simp [RefuteEx.cB, vset], ?_⟩, fires11_GB⟩
  intro h
  simp [RefuteEx.cA, RefuteEx.cB] at h

/-! ### The weaker class: the infinite-row condition

Ermine's third concrete-label error condition, INFINITE ROW, needs `lhs ∈ rhs` AND a
non-empty concrete part.  The second half is concrete, the first is not: it is a fact
about the right-hand VARIABLES.  That extra half puts the condition outside
`ConcRefuter` -- and, remarkably, the branch that breaks it is one the cut KEEPS
(`reuse_can_create_infinite_row` below).

For it the right notion is `MintShadowed`, which additionally tracks self-loops: the
minting branch cannot create one, because its new variable is fresh, so `reduce c S z`
has `c.lhs` on its right only when `c` already did. -/

/-- As `Shadowed`, and additionally: `c` self-loops only where a constraint of `G` with
`c`'s left-hand side and concrete part already self-loops.  The naming case now also
records that a fresh name never occurs in its own right-hand side. -/
def MintShadowed (G : System) (c : Constraint) : Prop :=
  vset c ≠ ∅ ∧
    ((c.conc = ∅ ∧ c.lhs ∉ vset c) ∨
      ∃ d ∈ G, d.lhs = c.lhs ∧ d.conc = c.conc ∧ (c.lhs ∈ vset c → d.lhs ∈ vset d))

theorem MintShadowed.toShadowed {G : System} {c : Constraint} (h : MintShadowed G c) :
    Shadowed G c := by
  refine ⟨h.1, ?_⟩
  rcases h.2 with ⟨h1, -⟩ | ⟨d, hd, h1, h2, -⟩
  · exact Or.inl h1
  · exact Or.inr ⟨d, hd, h1, h2⟩

theorem MintShadowed.mono {G G' : System} (hsub : G ⊆ G') {c : Constraint}
    (h : MintShadowed G c) : MintShadowed G' c := by
  refine ⟨h.1, ?_⟩
  rcases h.2 with h' | ⟨d, hd, h1, h2, h3⟩
  · exact Or.inl h'
  · exact Or.inr ⟨d, hsub hd, h1, h2, h3⟩

/-- The naming constraint `z <- int` with `z` FRESH: empty concrete part, and `z` does
not occur in `int`, because `int` lives in the old vocabulary. -/
theorem mintShadowed_name {G : System} {S : Finset Var} (h2 : 2 ≤ S.card)
    (hS : S ⊆ allVars G) {z : Var} (hz : z ∉ allVars G) : MintShadowed G (mk z S ∅) :=
  ⟨by rw [vset_mk]; exact ne_empty_of_two_le_card h2,
    Or.inl ⟨rfl, by rw [vset_mk]; exact fun hmem => hz (hS hmem)⟩⟩

/-- A premise rewritten with a FRESH name: it self-loops only if the premise did, since
`c.lhs ≠ z`. -/
theorem mintShadowed_reduce {G : System} {c : Constraint} (hc : c ∈ G) {z : Var}
    (hz : z ∉ allVars G) (S : Finset Var) : MintShadowed G (reduce c S z) := by
  refine ⟨by rw [vset_reduce]; exact Finset.insert_ne_empty _ _,
    Or.inr ⟨c, hc, rfl, rfl, fun hmem => ?_⟩⟩
  rw [vset_reduce] at hmem
  rcases Finset.mem_insert.mp hmem with hz' | hmem'
  · exfalso
    apply hz
    rw [← hz']
    exact lhs_mem_allVars (c := c) hc
  · exact (Finset.mem_sdiff.mp hmem').1

/-- A refuter that no `MintShadowed` addition can turn on.  Weaker than `ConcRefuter`
(every `ConcRefuter` is one), and it is the class the infinite-row condition lives in. -/
structure MintBlindRefuter extends Refuter where
  /-- adding a constraint whose concrete facts AND self-loops are already visible cannot
  make the test fire -/
  blind : ∀ (G : System) (c : Constraint), MintShadowed G c → fires (insert c G) → fires G

/-- Every concrete-label refuter is mint-blind. -/
def ConcRefuter.toMintBlind (R : ConcRefuter) : MintBlindRefuter where
  toRefuter := R.toRefuter
  blind G c h hf := R.blind G c h.toShadowed hf

/-- **The minting branch cannot turn a mint-blind test on either.**  This is the sharp
form of "the minting branch introduces no concrete label": even a test that also reads
self-loops sees nothing new. -/
theorem CseStep.mintBlind_fires_imp (R : MintBlindRefuter) {G G' : System} (h : CseStep G G')
    (hf : R.fires G') : R.fires G := by
  cases h with
  | @intro c₁ c₂ z happ =>
    have hS : shared c₁ c₂ ⊆ allVars G :=
      (shared_subset_left c₁ c₂).trans (vset_subset_allVars happ.mem₁)
    rw [cseResult] at hf
    have h1 := R.blind _ _
      ((mintShadowed_name happ.two_le hS happ.fresh).mono
        (le_trans (Finset.subset_insert _ _) (Finset.subset_insert _ _))) hf
    have h2 := R.blind _ _
      ((mintShadowed_reduce happ.mem₁ happ.fresh (shared c₁ c₂)).mono
        (Finset.subset_insert _ _)) h1
    exact R.blind _ _ (mintShadowed_reduce happ.mem₂ happ.fresh (shared c₁ c₂)) h2

/-- `splitConcrete` mints too, and is equally invisible. -/
theorem SplitStep.mintBlind_fires_imp (R : MintBlindRefuter) {G G' : System}
    (h : SplitStep G G') (hf : R.fires G') : R.fires G := by
  cases h with
  | @intro c u happ =>
    rw [splitResult] at hf
    have hs1 : MintShadowed (insert (mk c.lhs {u} c.conc) G) (mk u (vset c) ∅) :=
      ⟨by rw [vset_mk]; exact ne_empty_of_two_le_card happ.two_le,
        Or.inl ⟨rfl, by
          rw [vset_mk]
          exact fun hmem => happ.fresh (vset_subset_allVars happ.mem hmem)⟩⟩
    have hs2 : MintShadowed G (mk c.lhs {u} c.conc) :=
      ⟨by rw [vset_mk]; exact Finset.singleton_ne_empty _,
        Or.inr ⟨c, happ.mem, rfl, rfl, by
          rw [vset_mk, lhs_mk]
          intro hmem
          exact absurd ((Finset.mem_singleton.mp hmem) ▸ lhs_mem_allVars happ.mem)
            happ.fresh⟩⟩
    exact R.blind _ _ hs2 (R.blind _ _ hs1 hf)

theorem CseSteps.mintBlind_fires_imp {n : ℕ} {G₀ G : System} (h : CseSteps n G₀ G)
    (R : MintBlindRefuter) (hf : R.fires G) : R.fires G₀ := by
  induction h with
  | refl => exact hf
  | tail _ hstep ih => exact ih (hstep.mintBlind_fires_imp R hf)

/-- **A MINT-ONLY run cannot turn a mint-blind test on.**  Compare
`ConcRefuter.branchSteps_fires_iff`, which allows the kept branches too. -/
theorem mint_run_fires_iff (R : MintBlindRefuter) {n : ℕ} {G₀ G : System}
    (h : CseSteps n G₀ G) : R.fires G ↔ R.fires G₀ :=
  ⟨fun hf => h.mintBlind_fires_imp R hf, fun hf => R.mono G₀ G h.subset hf⟩

/-- **The weaker payoff.**  For a mint-blind refuter -- infinite row included -- whatever
a MINTING run refutes, the input already refutes, and hence so does every cut run.  The
minting branch is not the source of any such refutation. -/
theorem cut_keeps_mintBlind_refutations (R : MintBlindRefuter) {n m : ℕ}
    {G₀ Gmint Gcut : System} (hmint : CseSteps n G₀ Gmint) (hcut : CutSteps m G₀ Gcut)
    (hf : R.fires Gmint) : R.fires Gcut :=
  R.mono G₀ Gcut hcut.subset (hmint.mintBlind_fires_imp R hf)

/-! ### Infinite row -/

/-- **Infinite row**: a variable occurs on its own right-hand side together with a
non-empty concrete part.  `a <- (a, ..., (|K|))` forces `K ⊆ rho a` and `K ∩ rho a = ∅`,
so `K = ∅`. -/
def FiresInf (G : System) : Prop := ∃ c ∈ G, c.lhs ∈ vset c ∧ c.conc ≠ ∅

theorem firesInf_sound (G : System) (h : FiresInf G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, hself, hne⟩ := h
  obtain ⟨l, hl⟩ := Finset.nonempty_iff_ne_empty.mpr hne
  have h1 : l ∈ rho c.lhs := (hm c hc).conc_subset_lhs hl
  exact Finset.disjoint_left.mp ((hm c hc).disjoint_conc' hself) hl h1

theorem firesInf_mono (G G' : System) (hsub : G ⊆ G') (h : FiresInf G) : FiresInf G' := by
  obtain ⟨c, hc, h1, h2⟩ := h
  exact ⟨c, hsub hc, h1, h2⟩

/-- Infinite row as a `MintBlindRefuter`: a `MintShadowed` addition either has an empty
concrete part or inherits its self-loop from a constraint already present. -/
def refuterInf : MintBlindRefuter where
  fires := FiresInf
  sound := firesInf_sound
  mono := firesInf_mono
  blind := by
    rintro G c hs ⟨a, ha, h1, h2⟩
    rcases Finset.mem_insert.mp ha with rfl | ha'
    · rcases hs.2 with ⟨hce, -⟩ | ⟨d, hd, hdl, hdc, hdself⟩
      · exact absurd hce h2
      · exact ⟨d, hd, hdself h1, by rw [hdc]; exact h2⟩
    · exact ⟨a, ha', h1, h2⟩

/-- **The minting branch never creates an infinite-row refutation.** -/
theorem mint_never_creates_infinite_row {G G' : System} (h : CseStep G G')
    (hf : FiresInf G') : FiresInf G := h.mintBlind_fires_imp refuterInf hf

/-! ### But a KEPT branch can create one

`GI` names `{p,q}` as `z` and also partitions `z` itself as `z <- (p, q, (|7|))`.  That
system is unsatisfiable, but no error condition fires on it.  One REUSE step rewrites
the second partition through the name `z`, producing the self-loop `z <- (z, (|7|))`,
and the infinite-row condition fires.  So the infinite-row test is genuinely NOT a
`ConcRefuter` -- and the branch that breaks it is one the cut KEEPS, so the exposure is
in the safe direction: the cut can fire MORE here, never less. -/

/-- **Duplicated field**: the row `c.lhs` is a PART of `d`, and `c`'s concrete part
shares a label with `d`'s.  Then that label is both inside `rho c.lhs` and disjoint from
it.  Like infinite row, this reads a variable fact (`c.lhs ∈ vset d`) as well as a
concrete one. -/
def FiresDup (G : System) : Prop :=
  ∃ c ∈ G, ∃ d ∈ G, c.lhs ∈ vset d ∧ ¬ Disjoint c.conc d.conc

theorem firesDup_sound (G : System) (h : FiresDup G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, d, hd, hmem, hnd⟩ := h
  have h1 : c.conc ⊆ rho c.lhs := (hm c hc).conc_subset_lhs
  have h2 : Disjoint d.conc (rho c.lhs) := (hm d hd).disjoint_conc' hmem
  exact hnd (Finset.disjoint_left.mpr fun l hl hl' => Finset.disjoint_left.mp h2 hl' (h1 hl))

theorem firesDup_mono (G G' : System) (hsub : G ⊆ G') (h : FiresDup G) : FiresDup G' := by
  obtain ⟨c, hc, d, hd, h1, h2⟩ := h
  exact ⟨c, hsub hc, d, hsub hd, h1, h2⟩

namespace InfRowEx

/-- `z <- (p, q)` -- the existing name for the shared block. -/
def n₁ : Constraint := mk 5 {2, 3} (∅ : Row)

/-- `a <- (p, q, r)`. -/
def n₂ : Constraint := mk 0 {2, 3, 4} (∅ : Row)

/-- `z <- (p, q, (|7|))` -- a second partition of the NAME itself. -/
def n₃ : Constraint := mk 5 {2, 3} ({7} : Row)

/-- The three-constraint input on which no error condition fires. -/
def GI : System := {n₁, n₂, n₃}

theorem sharedI : shared n₂ n₃ = {2, 3} := by
  rw [n₂, n₃, shared, vset_mk, vset_mk]; decide

theorem pairI : CsePair GI n₂ n₃ :=
  ⟨by simp [GI], by simp [GI], by decide, by rw [sharedI]; decide⟩

theorem namesI : Names GI 5 (shared n₂ n₃) :=
  ⟨n₁, by simp [GI], rfl, by rw [sharedI, n₁, vset_mk], rfl⟩

/-- The reuse step rewrites `z <- (p, q, (|7|))` into the self-loop `z <- (z, (|7|))`. -/
theorem red₃ : reduce n₃ (shared n₂ n₃) 5 = mk 5 {5} ({7} : Row) := by
  have h : insert (5 : Var) ((({2, 3} : Finset Var)) \ {2, 3}) = ({5} : Finset Var) := by decide
  rw [reduce, sharedI, n₃, vset_mk, h]
  rfl

theorem stepI : CutStep GI (reuseResult GI n₂ n₃ 5) := CutStep.reuse pairI namesI

theorem mem_red₃ : mk 5 {5} ({7} : Row) ∈ reuseResult GI n₂ n₃ 5 := by
  rw [← red₃, reuseResult]
  exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)

theorem fires_after : FiresInf (reuseResult GI n₂ n₃ 5) :=
  ⟨mk 5 {5} ({7} : Row), mem_red₃, by simp, by simp⟩

theorem not_fires_before : ¬ FiresInf GI := by
  rintro ⟨c, hc, h1, h2⟩
  simp only [GI, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl
  · exact h2 (by simp [n₁])
  · exact h2 (by simp [n₂])
  · revert h1; simp [n₃]

/-- The very same step creates a DUPLICATED FIELD as well: `z <- (z, (|7|))` has the
label `7` both in its own concrete part and inside the part `z` it is asking for. -/
theorem firesDup_after : FiresDup (reuseResult GI n₂ n₃ 5) :=
  ⟨mk 5 {5} ({7} : Row), mem_red₃, mk 5 {5} ({7} : Row), mem_red₃, by simp, by simp⟩

theorem not_firesDup_before : ¬ FiresDup GI := by
  rintro ⟨c, hc, d, hd, hmem, hnd⟩
  have hcne : c.conc ≠ ∅ := fun h => hnd (by rw [h]; simp)
  have hdne : d.conc ≠ ∅ := fun h => hnd (by rw [h]; simp)
  have hc3 : c = n₃ := by
    simp only [GI, Finset.mem_insert, Finset.mem_singleton] at hc
    rcases hc with rfl | rfl | rfl
    · exact absurd (by simp [n₁]) hcne
    · exact absurd (by simp [n₂]) hcne
    · rfl
  have hd3 : d = n₃ := by
    simp only [GI, Finset.mem_insert, Finset.mem_singleton] at hd
    rcases hd with rfl | rfl | rfl
    · exact absurd (by simp [n₁]) hdne
    · exact absurd (by simp [n₂]) hdne
    · rfl
  rw [hc3, hd3] at hmem
  revert hmem
  simp [n₃]

end InfRowEx

/-- **A branch the cut KEEPS can create an infinite-row refutation.**  So the
infinite-row condition is not blind to the kept branches, and the cut's exposure on it is
one-sided in the safe direction. -/
theorem reuse_can_create_infinite_row :
    ∃ G G' : System, CutStep G G' ∧ FiresInf G' ∧ ¬ FiresInf G :=
  ⟨InfRowEx.GI, _, InfRowEx.stepI, InfRowEx.fires_after, InfRowEx.not_fires_before⟩

/-- **Exactly what is missing, as a theorem.**  The infinite-row condition is NOT a
`ConcRefuter`: no refuter in that class can have it as its firing predicate.  Hence
`cut_cannot_lose_concrete_refutation` does not apply to it and the weaker
`cut_keeps_mintBlind_refutations` -- mint-only runs -- is the best this file proves. -/
theorem firesInf_not_concRefuter : ¬ ∃ R : ConcRefuter, ∀ G, R.fires G ↔ FiresInf G := by
  rintro ⟨R, hR⟩
  obtain ⟨G, G', hstep, hfire, hnot⟩ := reuse_can_create_infinite_row
  exact hnot ((hR G).mp (hstep.fires_imp R ((hR G').mpr hfire)))

/-- The duplicated-field condition is in the same position as infinite row: the SAME
reuse step creates it.  So it too is outside `ConcRefuter`, and for the same reason --
it reads variable structure, not only concrete parts. -/
theorem reuse_can_create_duplicated_field :
    ∃ G G' : System, CutStep G G' ∧ FiresDup G' ∧ ¬ FiresDup G :=
  ⟨InfRowEx.GI, _, InfRowEx.stepI, InfRowEx.firesDup_after, InfRowEx.not_firesDup_before⟩

theorem firesDup_not_concRefuter : ¬ ∃ R : ConcRefuter, ∀ G, R.fires G ↔ FiresDup G := by
  rintro ⟨R, hR⟩
  obtain ⟨G, G', hstep, hfire, hnot⟩ := reuse_can_create_duplicated_field
  exact hnot ((hR G).mp (hstep.fires_imp R ((hR G').mpr hfire)))

/-- **The two-sided picture for the three concrete-label conditions.**  All three are
sound refutation tests; MINTING can turn none of them on; and for the two that read only
concrete parts the cut is exactly as strong as the full solver. -/
theorem three_conditions_summary :
    (∀ G : System, FiresIncompat G → ¬ ∃ rho, SModels rho G) ∧
      (∀ G : System, Fires11 G → ¬ ∃ rho, SModels rho G) ∧
      (∀ G : System, FiresInf G → ¬ ∃ rho, SModels rho G) ∧
      (∀ G : System, FiresDup G → ¬ ∃ rho, SModels rho G) ∧
      (∀ G G' : System, CseStep G G' → FiresInf G' → FiresInf G) :=
  ⟨firesIncompat_sound, fires11_sound, firesInf_sound, firesDup_sound,
    fun _ _ h hf => mint_never_creates_infinite_row h hf⟩

/-! ## 5. Summary

| question | answer | theorem |
| --- | --- | --- |
| what concrete parts can MINT emit? | `∅`, `concr1`, `concr2` -- the premises' own | `mint_conc` |
| ... so what happens to the part set? | `insert ∅` of the old one, exactly | `concs_cseResult` |
| ... modulo `∅`? | literally unchanged | `concs_cseResult_sdiff` |
| does MINT add a concrete LABEL? | **no**, exactly preserved | `CseStep.concLabelsS_eq` |
| do the KEPT branches? | no -- not even `∅` is added | `CutStep.concs_eq` |
| does `splitConcrete`? | no | `SplitStep.concLabelsS_eq` |
| does `resolution`? | no LABELS, but yes new PARTS | `ResStep.concLabelsS_eq` |
| is the LABEL set a closure invariant? | **yes, whole rule set** | `FullSteps.concLabelsS_eq` |
| is the PART set a closure invariant? | **NO** | `mint_enables_new_concrete_part` |
| is the PART set invariant for CSE-only runs? | yes, up to `∅` | `BranchSteps.concs_subset` |
| can MINT turn a concrete-label test on? | no | `CseStep.fires_imp` |
| can the KEPT branches? | not a `ConcRefuter` one | `CutStep.fires_imp` |
| **can the cut lose a concrete refutation?** | **NO** | `cut_cannot_lose_concrete_refutation` |
| is incompatible-instantiations such a test? | yes | `refuterIncompat` |
| is condition 11 such a test? | yes | `refuter11'` |
| is infinite-row such a test? | **no** | `firesInf_not_concRefuter` |
| is duplicated-field such a test? | **no** | `firesDup_not_concRefuter` |
| ... can MINT turn infinite-row on? | no | `mint_never_creates_infinite_row` |
| ... can a KEPT branch? | yes -- the SAFE direction | `reuse_can_create_infinite_row` |

### The claim, and how much of it is proved

> The minting branch introduces no concrete label that was not already present, and
> therefore cannot enable or disable any refutation that depends only on concrete
> labels.

The first half is proved outright and at the strongest available scope: not just for one
step (`CseStep.concLabelsS_eq`) but for the closure of the entire rule set
(`FullSteps.concLabelsS_eq`).

The second half is proved for refutations that depend only on the concrete content in
the precise sense of `ConcRefuter`, and there the result is stronger than "cut fires iff
full fires": both fire exactly when the INPUT does
(`cut_cannot_lose_concrete_refutation`).  Two of the three concrete-label error
conditions are in the class.

### What is NOT proved

* **The part-level invariant does not lift, and minting is the reason.**  This is a real
  negative finding, not a proof gap: `mint_enables_new_concrete_part` exhibits a system
  on which `resolution` cannot fire, a mint step that makes it fire, and a resulting new
  concrete part.  The mechanism is that minting lowers arity, and `resolution` needs
  arity-one premises.  A refuter that reads concrete PARTS rather than labels is
  therefore not covered by section 4, and the cut could in principle change its verdict
  by removing that enabling step -- in the direction of firing LESS.
* **The infinite-row condition, on mixed runs.**  `refuterInf` is only mint-blind, so
  `mint_run_fires_iff` covers MINT-ONLY runs.  A full run that interleaves minting with
  reuse/fold, where a reuse step uses minted material as its premise or its name, is not
  simulated by any cut run here.  `reuse_can_create_infinite_row` shows the missing case
  is not vacuous.  What IS known: the branch that creates such firings is one the cut
  keeps, so this gap is exposure in the direction of the cut firing MORE, which is safe
  by `cut_never_wrongly_refutes`.
* **Ermine's duplicated-field condition** is in the same position as infinite row:
  `FiresDup` reads `c.lhs ∈ vset d` as well as the two concrete parts, and the SAME reuse
  step creates it (`reuse_can_create_duplicated_field`,
  `firesDup_not_concRefuter`).  Only the two conditions that read `conc` alone are
  certified by section 4.
* **Whether the shipped solver's checks are exactly these.**  `Fires11`, `FiresIncompat`
  and `FiresInf` are models of Ermine's error conditions, faithful to their stated
  shape; the correspondence with `Constraints.scala` is by inspection, not by proof. -/


end Rowpartition
