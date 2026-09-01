/-
# Cutting the minting branch of `commonSubexpression`

`Constraints.scala:1089-1113` implements Ermine's common-subexpression rule.  Given two
partitions `v <- rhs1`, `u <- rhs2` whose abstract right-hand sides share
`int = abstr1 ∩ abstr2` with `|int| >= 2`, it takes one of THREE branches:

* **(a) REUSE** -- the reverse lookup `rhss(RHSAbstr(int))` finds an existing partition
  `z <- int`; emit `v <- (abstr1 \ int) ∪ {z} ∪ concr1` and
  `u <- (abstr2 \ int) ∪ {z} ∪ concr2`;
* **(b) FOLD** -- `rhs1` IS `int` as a bare abstract right-hand side; emit
  `u <- (abstr2 \ int) ∪ {v} ∪ concr2` (and symmetrically for `rhs2`);
* **(c) MINT** -- otherwise allocate a FRESH `z` and emit `z <- int` together with both
  rewritten premises.

The proposed cut replaces branch (c) by the empty set, keeping (a) and (b).  This file
formalises all three branches and proves what is actually provable about the cut.

## Results

**Section 1** defines the branches as a step relation on `Divergence.System`, MINT being
a separate constructor (`CseBranch.mint`, which is `Divergence.CseStep`) from REUSE and
FOLD (`CutStep`).  `CutStep.toBranch` and `CutSteps.toBranchSteps` record that every run
of the cut solver is a run of the full solver.  `fold_first_conclusion_vacuous` explains
why branch (b) emits ONE constraint where (a) emits two: under (b)'s guard the missing
conclusion is the vacuous self-partition `a <- a`.

**Section 2, meaning preservation.**  `sat_reduce_of_denotes` is the core lemma: if a
variable already denotes the union of a sub-group of a satisfied constraint's right-hand
side, the contracted constraint is satisfied by the SAME assignment.  Hence branches (a)
and (b) are outright ENTAILMENT (`reuse_entails`, `fold_entails`), and a cut step does not
change the model set at all (`CutStep.models_iff`).  Branch (c) mints, so entailment is
not even well-formed for it; the right statement is `Rules.ConservativeExt`, transported
to systems as `SConservativeExt` and shown to agree with it (`sConservativeExt_iff`).
`mint_conservativeExt` proves it.  `cut_preserves_meaning` is the conclusion: any cut run
and any full run from the same input are equisatisfiable and, over the input's own
vocabulary, entail exactly the same constraints.  **Dropping branch (c) cannot change the
set of models.**

**Section 3, refutation monotonicity.**  `unsat_mono`: unsatisfiability of a subsystem is
inherited by every supersystem.  `unsat_not_antitone`: the converse is false, with an
explicit two-constraint counterexample.  (The task statement of this section names the
TRUE direction and calls it false; both directions are settled here, see the note above
`unsat_mono`.)  A solver refutes by SYNTACTIC error conditions, abstracted here as a
`Refuter` -- sound and monotone.  Then `cut_never_wrongly_refutes`: anything a cut run
refutes really has no model, so the cut never rejects a well-typed program.  And
`refuter_can_miss`: a sound monotone refuter can fire only on the larger of two systems,
so deriving fewer constraints can lose a refutation.  `complete_refuter_unaffected`
pins where such a loss can come from: NOT from lost semantic information -- every branch
preserves satisfiability -- but only from the incompleteness of the syntactic checks.
**The cut's risk is accepting an ill-typed program, never rejecting a well-typed one**
(`cut_risk_is_one_sided`).

**Section 4, what the kept branches do.**  They are non-generative (`CutStep.allVars_eq`)
and strictly contracting (`card_vset_reduce_lt`); `CutStep.new_constraints` characterises
their output completely -- every new constraint has the same left-hand side and the same
concrete part as an existing one, variables from the existing vocabulary, strictly
smaller arity, and is entailed.  Everything a cut run derives therefore lives in one
explicit finite set (`bound`), so productive cut chains have length at most
`(bound G₀).card` (`CutChain.length_le`): **branches (a) and (b) fire only finitely often
on a fixed variable set.**

**Section 5, termination of the cut rule set: a NEGATIVE result, as expected.**  The cut
leaves `splitConcrete` and `resolution` minting.  They are not alike.  `splitConcrete`
consults the same reverse lookup before minting; section 5.2 turns that guard into a
strictly decreasing measure (`SplitStep.cands_lt`), so split-minting terminates on its
own (`split_terminates`).  `resolution` takes no `rhss` argument at all and mints on
every match, so one fixed pair of premises admits chains of EVERY length
(`resSeed_diverges`), mirroring `Divergence.seed_diverges` for the branch being cut.
Consequently no `ℕ`-valued measure decreases on every step of the cut rule set
(`cut_no_decreasing_measure`), and the finiteness argument of section 4 fails for an
identifiable reason: a single resolution step leaves the vocabulary bound
(`ResStep.escapes`).  **The cut does not terminate** (`cut_does_not_terminate`).

**Section 6** checks non-vacuity: branch (a) fires, branch (b) fires, and on
`Divergence.seed` only branch (c) can fire (`cut_removes_something`), so the cut is not a
no-op.  **Section 7** is the summary table and an explicit list of what is NOT proved.

## Relation to the rest of the development

`Rules.rule9` proves the same soundness statement for the MINT branch on list-shaped
systems; `Divergence` proves that MINT alone diverges and that a saturated set is
exponential.  This file adds the branch-by-branch analysis those two do not do, and the
only genuinely new semantic ingredient is `sat_reduce_of_denotes`: `Divergence.sat_reduce`
needs freshness and an updated assignment because it is stated for a minted name, whereas
for an EXISTING name no update is needed and plain entailment holds.
-/
import Rowpartition.Rules
import Rowpartition.Divergence
import Mathlib.Data.Finset.Prod

namespace Rowpartition

/-! ## 1. The three branches -/

/-- `S` is already NAMED in `G`: some constraint of `G` is the bare abstract partition
`d <- S`.  This is the Scala `rhss(RHSAbstr(int))` reverse lookup, as a predicate. -/
def Named (G : System) (S : Finset Var) : Prop := ∃ d ∈ G, vset d = S ∧ d.conc = ∅

instance (G : System) (S : Finset Var) : Decidable (Named G S) :=
  inferInstanceAs (Decidable (∃ d ∈ G, vset d = S ∧ d.conc = ∅))

/-- `z` is the name `G` gives to `S`. -/
def Names (G : System) (z : Var) (S : Finset Var) : Prop :=
  ∃ d ∈ G, d.lhs = z ∧ vset d = S ∧ d.conc = ∅

theorem Names.named {G : System} {z : Var} {S : Finset Var} (h : Names G z S) : Named G S := by
  obtain ⟨d, hd, -, h2, h3⟩ := h
  exact ⟨d, hd, h2, h3⟩

theorem Named.mono {G G' : System} (hsub : G ⊆ G') {S : Finset Var} (h : Named G S) :
    Named G' S := by
  obtain ⟨d, hd, h2, h3⟩ := h
  exact ⟨d, hsub hd, h2, h3⟩

theorem Names.mem_allVars {G : System} {z : Var} {S : Finset Var} (h : Names G z S) :
    z ∈ allVars G := by
  obtain ⟨d, hd, rfl, -, -⟩ := h
  exact lhs_mem_allVars hd

/-- The premise pattern shared by all three branches. -/
structure CsePair (G : System) (c₁ c₂ : Constraint) : Prop where
  mem₁ : c₁ ∈ G
  mem₂ : c₂ ∈ G
  lhs_ne : c₁.lhs ≠ c₂.lhs
  two_le : 2 ≤ (shared c₁ c₂).card

theorem CsePair.toApp {G : System} {c₁ c₂ : Constraint} (h : CsePair G c₁ c₂) {z : Var}
    (hz : z ∉ allVars G) : CseApp G c₁ c₂ z :=
  ⟨h.mem₁, h.mem₂, h.lhs_ne, h.two_le, hz⟩

/-- Branch (a) REUSE. -/
def reuseResult (G : System) (c₁ c₂ : Constraint) (z : Var) : System :=
  insert (reduce c₁ (shared c₁ c₂) z) (insert (reduce c₂ (shared c₁ c₂) z) G)

/-- Branch (b) FOLD. -/
def foldResult (G : System) (c₁ c₂ : Constraint) : System :=
  insert (reduce c₂ (shared c₁ c₂) c₁.lhs) G

theorem subset_reuseResult (G : System) (c₁ c₂ : Constraint) (z : Var) :
    G ⊆ reuseResult G c₁ c₂ z := fun c hc => by
  simp only [reuseResult, Finset.mem_insert]
  exact Or.inr (Or.inr hc)

theorem subset_foldResult (G : System) (c₁ c₂ : Constraint) : G ⊆ foldResult G c₁ c₂ :=
  fun _ hc => Finset.mem_insert_of_mem hc

/-- The cut rule: branches (a) and (b) only. -/
inductive CutStep : System → System → Prop
  | reuse {G : System} {c₁ c₂ : Constraint} {z : Var} :
      CsePair G c₁ c₂ → Names G z (shared c₁ c₂) → CutStep G (reuseResult G c₁ c₂ z)
  | fold {G : System} {c₁ c₂ : Constraint} :
      CsePair G c₁ c₂ → vset c₁ = shared c₁ c₂ → c₁.conc = ∅ →
      CutStep G (foldResult G c₁ c₂)

/-- The full rule: all three branches. -/
inductive CseBranch : System → System → Prop
  | reuse {G : System} {c₁ c₂ : Constraint} {z : Var} :
      CsePair G c₁ c₂ → Names G z (shared c₁ c₂) → CseBranch G (reuseResult G c₁ c₂ z)
  | fold {G : System} {c₁ c₂ : Constraint} :
      CsePair G c₁ c₂ → vset c₁ = shared c₁ c₂ → c₁.conc = ∅ →
      CseBranch G (foldResult G c₁ c₂)
  | mint {G : System} {c₁ c₂ : Constraint} {z : Var} :
      CseApp G c₁ c₂ z → CseBranch G (cseResult G c₁ c₂ z)

theorem CutStep.toBranch {G G' : System} (h : CutStep G G') : CseBranch G G' := by
  cases h with
  | reuse hp hn => exact CseBranch.reuse hp hn
  | fold hp h1 h2 => exact CseBranch.fold hp h1 h2

theorem CseStep.toBranch {G G' : System} (h : CseStep G G') : CseBranch G G' := by
  cases h with | intro happ => exact CseBranch.mint happ

theorem CutStep.subset {G G' : System} (h : CutStep G G') : G ⊆ G' := by
  cases h with
  | reuse => exact subset_reuseResult _ _ _ _
  | fold => exact subset_foldResult _ _ _

theorem CseBranch.subset {G G' : System} (h : CseBranch G G') : G ⊆ G' := by
  cases h with
  | reuse => exact subset_reuseResult _ _ _ _
  | fold => exact subset_foldResult _ _ _
  | mint => exact subset_cseResult _ _ _ _

/-! ### FOLD is REUSE with the premise as its own name

`fold_names` says that under FOLD's guard the premise `c₁` IS a naming constraint for the
shared block, so in THIS model branch (b) is an instance of branch (a) and the only
conclusion (a) would add on top is vacuous (`fold_first_conclusion_vacuous`).

A caveat about the Scala, so the gloss is not over-read.  Here `CsePair.mem₁` puts `c₁`
inside `G`, which is what makes `Named G (shared c₁ c₂)` hold.  In `Constraints.scala`
the reverse lookup is `findRHS(incm, proc, s)` (`:748`), which searches the incoming
queue, the processed queue and the accumulator -- but `learnPartitions` (`:833`) is
called with `v <- rhs1` as "the rule we're about to add", so the premise is in NONE of
the three.  That is exactly why the FOLD branch is reachable in the real solver instead
of being shadowed by REUSE: it is live code.  So "branch (b) is branch (a) in disguise"
is a theorem about this model and about the RULE, not a claim that Ermine's REUSE branch
would have fired first. -/

theorem fold_names {G : System} {c₁ c₂ : Constraint} (hp : CsePair G c₁ c₂)
    (h1 : vset c₁ = shared c₁ c₂) (h2 : c₁.conc = ∅) : Names G c₁.lhs (shared c₁ c₂) :=
  ⟨c₁, hp.mem₁, rfl, h1, h2⟩

/-- Under the FOLD guard the FIRST conclusion REUSE would emit is `a <- a`, a vacuous
self-partition; that is exactly why the Scala emits only the second. -/
theorem fold_first_conclusion_vacuous {c₁ c₂ : Constraint} (h1 : vset c₁ = shared c₁ c₂)
    (h2 : c₁.conc = ∅) :
    reduce c₁ (shared c₁ c₂) c₁.lhs = mk c₁.lhs {c₁.lhs} ∅ := by
  rw [reduce, h2, ← h1, Finset.sdiff_self]
  rfl

theorem foldResult_eq {G : System} {c₁ c₂ : Constraint} (h1 : vset c₁ = shared c₁ c₂)
    (h2 : c₁.conc = ∅) :
    reuseResult G c₁ c₂ c₁.lhs = insert (mk c₁.lhs {c₁.lhs} ∅) (foldResult G c₁ c₂) := by
  rw [reuseResult, foldResult, fold_first_conclusion_vacuous h1 h2]

/-! ### The Scala's symmetric FOLD case

`commonSubexpression` has TWO fold cases, `rhs1 == rhsCommon` and `rhs2 == rhsCommon`.
`CutStep.fold` is the first.  The second is an INSTANCE of it, because `shared` is
symmetric -- so modelling one case loses nothing. -/

theorem shared_comm (c₁ c₂ : Constraint) : shared c₁ c₂ = shared c₂ c₁ :=
  Finset.inter_comm _ _

theorem CsePair.symm {G : System} {c₁ c₂ : Constraint} (h : CsePair G c₁ c₂) :
    CsePair G c₂ c₁ :=
  ⟨h.mem₂, h.mem₁, h.lhs_ne.symm, by rw [shared_comm]; exact h.two_le⟩

/-- **The second fold case is derivable.**  If it is the SECOND premise that is the shared
block, the cut still fires, emitting `reduce c₁ (shared c₁ c₂) c₂.lhs`. -/
theorem fold_symm {G : System} {c₁ c₂ : Constraint} (hp : CsePair G c₁ c₂)
    (h1 : vset c₂ = shared c₁ c₂) (h2 : c₂.conc = ∅) :
    CutStep G (insert (reduce c₁ (shared c₁ c₂) c₂.lhs) G) := by
  have := CutStep.fold hp.symm (by rw [← shared_comm]; exact h1) h2
  rwa [foldResult, shared_comm c₂ c₁] at this



/-! ## 2. Meaning preservation -/

/-- **The core lemma.**  If `rho` satisfies `c` and the variable `z` happens to denote
the union of a sub-group `S` of `c`'s right-hand side, then `rho` ALREADY satisfies the
contracted constraint.  No freshness, no update of `rho`: this is plain entailment. -/
theorem sat_reduce_of_denotes {rho : Assign} {c : Constraint} {S : Finset Var} {z : Var}
    (hc : Sat rho c) (hS : S ⊆ vset c) (hz : rho z = S.biUnion rho) :
    Sat rho (reduce c S z) := by
  have hkey : ∀ {u t : Var}, u ∈ S → t ∈ vset c → t ∉ S → Disjoint (rho u) (rho t) :=
    fun hu ht htS => hc.disjoint_of_ne' (hS hu) ht (fun h => htS (h ▸ hu))
  rw [reduce, sat_mk_iff]
  refine ⟨?_, ?_, ?_⟩
  · rw [Finset.biUnion_insert, hz, biUnion_split rho hS]
    exact hc.eq_biUnion
  · intro v hv
    rcases Finset.mem_insert.mp hv with rfl | hv'
    · rw [hz]
      exact disjoint_biUnion_right' fun u hu => hc.disjoint_conc' (hS hu)
    · exact hc.disjoint_conc' (Finset.mem_sdiff.mp hv').1
  · intro v hv w hw hvw
    rcases Finset.mem_insert.mp hv with rfl | hv'
    · rcases Finset.mem_insert.mp hw with rfl | hw'
      · exact absurd rfl hvw
      · obtain ⟨hw1, hw2⟩ := Finset.mem_sdiff.mp hw'
        rw [hz]
        exact disjoint_biUnion_left' fun u hu => hkey hu hw1 hw2
    · obtain ⟨hv1, hv2⟩ := Finset.mem_sdiff.mp hv'
      rcases Finset.mem_insert.mp hw with rfl | hw'
      · rw [hz]
        exact (disjoint_biUnion_left' fun u hu => hkey hu hv1 hv2).symm
      · exact hc.disjoint_of_ne' hv1 (Finset.mem_sdiff.mp hw').1 hvw

/-- A named group really denotes its union under any model. -/
theorem Names.denotes {G : System} {z : Var} {S : Finset Var} (h : Names G z S)
    {rho : Assign} (hm : SModels rho G) : rho z = S.biUnion rho := by
  obtain ⟨d, hd, rfl, rfl, hconc⟩ := h
  have := (hm d hd).eq_biUnion
  rwa [hconc, Finset.empty_union] at this

/-- **Branch (a) is entailment.**  Both conclusions of REUSE are semantic consequences
of the premises -- no fresh variable, nothing to extend. -/
theorem reuse_entails {G : System} {c₁ c₂ : Constraint} {z : Var} (hp : CsePair G c₁ c₂)
    (hn : Names G z (shared c₁ c₂)) :
    SEntails G (reduce c₁ (shared c₁ c₂) z) ∧ SEntails G (reduce c₂ (shared c₁ c₂) z) := by
  constructor <;> intro _ hm
  · exact sat_reduce_of_denotes (hm c₁ hp.mem₁) (shared_subset_left _ _) (hn.denotes hm)
  · exact sat_reduce_of_denotes (hm c₂ hp.mem₂) (shared_subset_right _ _) (hn.denotes hm)

/-- **Branch (b) is entailment.**  The single conclusion of FOLD is a semantic
consequence of the premises. -/
theorem fold_entails {G : System} {c₁ c₂ : Constraint} (hp : CsePair G c₁ c₂)
    (h1 : vset c₁ = shared c₁ c₂) (h2 : c₁.conc = ∅) :
    SEntails G (reduce c₂ (shared c₁ c₂) c₁.lhs) := fun _ hm =>
  sat_reduce_of_denotes (hm c₂ hp.mem₂) (shared_subset_right _ _)
    ((fold_names hp h1 h2).denotes hm)

/-- **The kept branches do not change the models at all.**  Not merely
satisfiability-preserving, not merely conservative over the old vocabulary: the model
SET is literally unchanged, because the emitted constraints are entailed. -/
theorem CutStep.models_iff {G G' : System} (h : CutStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := by
  refine ⟨fun hm => ?_, fun hm => SModels.mono h.subset hm⟩
  cases h with
  | @reuse c₁ c₂ z hp hn =>
    obtain ⟨e₁, e₂⟩ := reuse_entails hp hn
    intro c hc
    simp only [reuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact e₁ rho hm
    · exact e₂ rho hm
    · exact hm c hc
  | @fold c₁ c₂ hp h1 h2 =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact fold_entails hp h1 h2 rho hm
    · exact hm c hc'

theorem CutStep.satisfiable_iff {G G' : System} (h : CutStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') :=
  exists_congr h.models_iff

theorem CutStep.entails_iff {G G' : System} (h : CutStep G G') (c : Constraint) :
    SEntails G c ↔ SEntails G' c := by
  simp only [SEntails]
  exact forall_congr' fun rho => imp_congr (h.models_iff rho) Iff.rfl

/-! ### Conservative extension: the correct statement for the MINTING branch -/

/-- `Rules.ConservativeExt`, transported to systems-as-finsets. -/
def SConservativeExt (G : System) (u : Var) (G' : System) : Prop :=
  (∀ rho, SModels rho G → ∃ rho', (∀ v, v ≠ u → rho' v = rho v) ∧ SModels rho' G') ∧
    (∀ rho, SModels rho G' → SModels rho G)

/-- The transported notion IS `Rules.ConservativeExt`. -/
theorem sConservativeExt_iff (G : System) (u : Var) (G' : System) :
    SConservativeExt G u G' ↔ ConservativeExt G.toList u G'.toList := by
  unfold SConservativeExt ConservativeExt
  simp only [sModels_iff_models]

/-- **Branch (c) is a conservative extension.**  Every model of the premises extends,
CHANGING ONLY the fresh `z`, to a model of the conclusion; and every model of the
conclusion already models the premises.  (This is the best available: `z` is new, so
outright entailment is not even well-formed.) -/
theorem mint_conservativeExt {G : System} {c₁ c₂ : Constraint} {z : Var}
    (happ : CseApp G c₁ c₂ z) : SConservativeExt G z (cseResult G c₁ c₂ z) := by
  refine ⟨fun rho hm => ?_, fun _ hm => SModels.mono (subset_cseResult _ _ _ _) hm⟩
  have hc₁ := hm c₁ happ.mem₁
  have hc₂ := hm c₂ happ.mem₂
  have hz₁ : z ∉ vset c₁ := fun hh => happ.fresh (mem_allVars happ.mem₁ (Or.inr hh))
  have hz₂ : z ∉ vset c₂ := fun hh => happ.fresh (mem_allVars happ.mem₂ (Or.inr hh))
  have hzl₁ : z ≠ c₁.lhs := fun hh => happ.fresh (hh ▸ lhs_mem_allVars happ.mem₁)
  have hzl₂ : z ≠ c₂.lhs := fun hh => happ.fresh (hh ▸ lhs_mem_allVars happ.mem₂)
  refine ⟨setVar rho z ((shared c₁ c₂).biUnion rho), fun _ hv => setVar_of_ne rho _ hv, ?_⟩
  intro c hc
  simp only [cseResult, Finset.mem_insert] at hc
  rcases hc with rfl | rfl | rfl | hc
  · exact sat_name hc₁ (shared_subset_left _ _) hz₁
  · exact sat_reduce hc₁ (shared_subset_left _ _) hz₁ hzl₁
  · exact sat_reduce hc₂ (shared_subset_right _ _) hz₂ hzl₂
  · exact sModels_setVar happ.fresh _ hm c hc

/-- The kept branches are conservative extensions too -- degenerately, at ANY variable
and with the IDENTITY extension, since they add nothing that needed a new name. -/
theorem CutStep.conservativeExt {G G' : System} (h : CutStep G G') (u : Var) :
    SConservativeExt G u G' :=
  ⟨fun rho hm => ⟨rho, fun _ _ => rfl, (h.models_iff rho).mp hm⟩,
    fun rho hm => (h.models_iff rho).mpr hm⟩

/-! ### The three branches together -/

theorem CseBranch.satisfiable_iff {G G' : System} (h : CseBranch G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | reuse hp hn => exact (CutStep.reuse hp hn).satisfiable_iff
  | fold hp h1 h2 => exact (CutStep.fold hp h1 h2).satisfiable_iff
  | mint happ => exact (CseStep.intro happ).satisfiable_iff

theorem CseBranch.entails_iff {G G' : System} (h : CseBranch G G') {c : Constraint}
    (hlhs : c.lhs ∈ allVars G) (hvs : vset c ⊆ allVars G) :
    SEntails G' c ↔ SEntails G c := by
  cases h with
  | reuse hp hn => exact ((CutStep.reuse hp hn).entails_iff c).symm
  | fold hp h1 h2 => exact ((CutStep.fold hp h1 h2).entails_iff c).symm
  | mint happ => exact (CseStep.intro happ).entails_iff hlhs hvs

/-! ### Iterating -/

/-- `BranchSteps n G G'`: `G'` is reachable from `G` by `n` steps of the FULL rule (any
of the three branches).  This is the shipped solver's common-subexpression search. -/
inductive BranchSteps : ℕ → System → System → Prop
  | refl (G : System) : BranchSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      BranchSteps n G G' → CseBranch G' G'' → BranchSteps (n + 1) G G''

/-- `CutSteps n G G'`: `G'` is reachable from `G` by `n` steps of the CUT rule -- only
branches (a) and (b). -/
inductive CutSteps : ℕ → System → System → Prop
  | refl (G : System) : CutSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      CutSteps n G G' → CutStep G' G'' → CutSteps (n + 1) G G''

/-- **Every run of the cut solver is a run of the full solver.**  The cut only removes
step opportunities; it adds none. -/
theorem CutSteps.toBranchSteps {n : ℕ} {G G' : System} (h : CutSteps n G G') :
    BranchSteps n G G' := by
  induction h with
  | refl G => exact BranchSteps.refl G
  | tail _ hstep ih => exact BranchSteps.tail ih hstep.toBranch

theorem BranchSteps.subset {n : ℕ} {G G' : System} (h : BranchSteps n G G') : G ⊆ G' := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep ih => exact ih.trans hstep.subset

theorem CutSteps.subset {n : ℕ} {G G' : System} (h : CutSteps n G G') : G ⊆ G' :=
  h.toBranchSteps.subset

theorem BranchSteps.satisfiable_iff {n : ℕ} {G₀ G : System} (h : BranchSteps n G₀ G) :
    (∃ rho, SModels rho G₀) ↔ (∃ rho, SModels rho G) := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep ih => exact ih.trans hstep.satisfiable_iff

theorem BranchSteps.entails_iff {n : ℕ} {G₀ G : System} (h : BranchSteps n G₀ G)
    {c : Constraint} (hlhs : c.lhs ∈ allVars G₀) (hvs : vset c ⊆ allVars G₀) :
    SEntails G c ↔ SEntails G₀ c := by
  induction h with
  | refl => exact Iff.rfl
  | @tail n G G' G'' hsteps hstep ih =>
    have hsub := allVars_mono hsteps.subset
    exact (hstep.entails_iff (hsub hlhs) (hvs.trans hsub)).trans (ih hlhs hvs)

/-- Along a CUT-ONLY run the model set never moves at all: the same assignments model
the input and every system derived from it. -/
theorem CutSteps.models_iff {n : ℕ} {G₀ G : System} (h : CutSteps n G₀ G) (rho : Assign) :
    SModels rho G₀ ↔ SModels rho G := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep ih => exact ih.trans (hstep.models_iff rho)

/-! ### The conclusion of section 2 -/

/-- **Dropping branch (c) cannot change the set of models.**  Take any run of the cut
solver and any run of the full solver from the same input.  Then the two derived systems
are equisatisfiable, and over the input's own vocabulary they entail exactly the same
constraints -- namely exactly what the input entailed.  The cut is meaning-preserving. -/
theorem cut_preserves_meaning {n m : ℕ} {G₀ Gcut Gfull : System}
    (hcut : CutSteps n G₀ Gcut) (hfull : BranchSteps m G₀ Gfull) :
    ((∃ rho, SModels rho Gcut) ↔ (∃ rho, SModels rho Gfull)) ∧
      ∀ c : Constraint, c.lhs ∈ allVars G₀ → vset c ⊆ allVars G₀ →
        (SEntails Gcut c ↔ SEntails Gfull c) := by
  refine ⟨?_, fun c hlhs hvs => ?_⟩
  · exact (hcut.toBranchSteps.satisfiable_iff).symm.trans hfull.satisfiable_iff
  · exact (hcut.toBranchSteps.entails_iff hlhs hvs).trans
      (hfull.entails_iff hlhs hvs).symm

/-! ## 3. Refutation monotonicity: which way the cut can go wrong

The task statement of this section, as posed, reads: "`G ⊆ G'` implies
`(¬ ∃ rho, Models rho G) → (¬ ∃ rho, Models rho G')` is FALSE in general but the useful
direction holds: unsatisfiability of the SMALLER set implies unsatisfiability of the
larger".  Those are the SAME statement, and it is the TRUE one (`unsat_mono`).  What is
false is its CONVERSE (`unsat_not_antitone`): unsatisfiability of the larger set does
not imply unsatisfiability of the smaller.  Both are proved below. -/

/-- **The useful direction.**  Adding constraints can only destroy models, so
unsatisfiability of a subsystem is inherited by every supersystem. -/
theorem unsat_mono {G G' : System} (hsub : G ⊆ G') (h : ¬ ∃ rho, SModels rho G) :
    ¬ ∃ rho, SModels rho G' := by
  rintro ⟨rho, hm⟩
  exact h ⟨rho, SModels.mono hsub hm⟩

/-! ### The converse fails -/

namespace RefuteEx

/-- `x <- (|1|)`. -/
def cA : Constraint := ⟨0, [], ({1} : Finset Label)⟩

/-- `x <- (|2|)`. -/
def cB : Constraint := ⟨0, [], ({2} : Finset Label)⟩

/-- A satisfiable one-constraint system. -/
def GA : System := {cA}

/-- Its unsatisfiable one-constraint extension. -/
def GB : System := {cA, cB}

theorem sub : GA ⊆ GB := by
  intro c hc
  rw [GA, Finset.mem_singleton] at hc
  simp [GB, hc]

theorem GA_sat : ∃ rho, SModels rho GA := by
  refine ⟨fun _ => ({1} : Finset Label), ?_⟩
  intro c hc
  rw [GA, Finset.mem_singleton] at hc
  subst hc
  exact (sat_zero _ 0 _).mpr rfl

theorem GB_unsat : ¬ ∃ rho, SModels rho GB := by
  rintro ⟨rho, hm⟩
  have h1 : rho 0 = ({1} : Finset Label) := (sat_zero rho 0 _).mp (hm cA (by simp [GB]))
  have h2 : rho 0 = ({2} : Finset Label) := (sat_zero rho 0 _).mp (hm cB (by simp [GB]))
  rw [h1] at h2
  have : (1 : Label) ∈ ({2} : Finset Label) := by rw [← h2]; simp
  simp at this

end RefuteEx

/-- **The converse is false.**  `GA ⊆ GB` with `GB` unsatisfiable and `GA` satisfiable:
a system can be refutable only because of constraints its subsystem does not contain. -/
theorem unsat_not_antitone :
    ¬ ∀ G G' : System, G ⊆ G' → (¬ ∃ rho, SModels rho G') → (¬ ∃ rho, SModels rho G) :=
  fun h => h RefuteEx.GA RefuteEx.GB RefuteEx.sub RefuteEx.GB_unsat RefuteEx.GA_sat

/-! ### What that means for the cut

A solver does not report "unsatisfiable" by exhibiting the absence of a model; it reports
it when a syntactic ERROR CONDITION fires on some derived constraint.  Abstract that as a
`Refuter`: a predicate on systems that is SOUND (it only fires on genuinely unsatisfiable
systems) and MONOTONE (deriving more constraints can only make it fire more).  Ermine's
error conditions 10 and 11 are of this shape; `Fires11` below is condition 11. -/

/-- A syntactic refutation test: sound, and monotone in the derived set. -/
structure Refuter where
  /-- the test fires on this system -/
  fires : System → Prop
  /-- it only fires on genuinely unsatisfiable systems -/
  sound : ∀ G, fires G → ¬ ∃ rho, SModels rho G
  /-- deriving more constraints can only make it fire more -/
  mono : ∀ G G' : System, G ⊆ G' → fires G → fires G'

/-- **No run of the solver -- cut or full -- can wrongly refute.**  If a sound refuter
fires on anything reachable from `G₀`, then `G₀` itself has no model: the program really
is ill-typed. -/
theorem run_refutation_sound (R : Refuter) {n : ℕ} {G₀ G : System} (h : BranchSteps n G₀ G)
    (hfire : R.fires G) : ¬ ∃ rho, SModels rho G₀ :=
  fun hsat => R.sound G hfire (h.satisfiable_iff.mp hsat)

/-- **The cut never rejects a well-typed program.**  Specialisation of
`run_refutation_sound` to cut-only runs.  Note the proof route: the cut derives FEWER
constraints, so whatever it derives is a subset of what the full solver derives; but the
argument does not even need that -- soundness of the refuter plus meaning preservation of
the cut run is enough. -/
theorem cut_never_wrongly_refutes (R : Refuter) {n : ℕ} {G₀ G : System}
    (h : CutSteps n G₀ G) (hfire : R.fires G) : ¬ ∃ rho, SModels rho G₀ :=
  run_refutation_sound R h.toBranchSteps hfire

/-! ### The other half: a monotone refuter CAN be lost by deriving less -/

/-- Error condition 11 as a refuter: `a` has a fully concrete partition `C`, and some
other partition of `a` has a concrete part not inside `C`. -/
def Fires11 (G : System) : Prop :=
  ∃ c ∈ G, ∃ d ∈ G, c.lhs = d.lhs ∧ vset c = ∅ ∧ ¬ d.conc ⊆ c.conc

theorem fires11_sound (G : System) (h : Fires11 G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, d, hd, hlhs, hvs, hsub⟩ := h
  have hc' : rho c.lhs = c.conc := by
    have hb := (hm c hc).eq_biUnion
    rw [hvs] at hb
    simpa using hb
  have hd' : d.conc ⊆ rho d.lhs := (hm d hd).conc_subset_lhs
  rw [← hlhs, hc'] at hd'
  exact hsub hd'

theorem fires11_mono (G G' : System) (hsub : G ⊆ G') (h : Fires11 G) : Fires11 G' := by
  obtain ⟨c, hc, d, hd, h1, h2, h3⟩ := h
  exact ⟨c, hsub hc, d, hsub hd, h1, h2, h3⟩

/-- Ermine's error condition 11, packaged as a `Refuter`. -/
def refuter11 : Refuter := ⟨Fires11, fires11_sound, fires11_mono⟩

theorem fires11_GB : Fires11 RefuteEx.GB := by
  refine ⟨RefuteEx.cA, by simp [RefuteEx.GB], RefuteEx.cB, by simp [RefuteEx.GB], rfl, rfl, ?_⟩
  intro hsub
  have : (2 : Label) ∈ ({1} : Finset Label) := hsub (by simp [RefuteEx.cB])
  simp at this

theorem not_fires11_GA : ¬ Fires11 RefuteEx.GA := by
  rintro ⟨c, hc, d, hd, -, -, h3⟩
  rw [RefuteEx.GA, Finset.mem_singleton] at hc hd
  subst hc; subst hd
  exact h3 (Finset.Subset.refl _)

/-- **A sound monotone refuter can fire on the larger derived set and not on the
smaller.**  So a saturation that derives fewer constraints can FAIL to refute. -/
theorem refuter_can_miss :
    ∃ (R : Refuter) (G G' : System),
      G ⊆ G' ∧ R.fires G' ∧ ¬ R.fires G ∧ (∃ rho, SModels rho G) :=
  ⟨refuter11, RefuteEx.GA, RefuteEx.GB, RefuteEx.sub, fires11_GB, not_fires11_GA,
    RefuteEx.GA_sat⟩

/-- **Where a lost refutation can come from, and where it cannot.**  A COMPLETE refuter
-- one that fires exactly on the unsatisfiable systems -- is untouched by any branch,
minting included, because every branch preserves satisfiability.  So any refutation the
cut can lose is attributable purely to the INCOMPLETENESS of the solver's syntactic
error conditions, never to a loss of semantic information. -/
theorem complete_refuter_unaffected {G G' : System} (h : CseBranch G G') (R : System → Prop)
    (hcomp : ∀ H : System, R H ↔ ¬ ∃ rho, SModels rho H) : R G ↔ R G' := by
  rw [hcomp, hcomp]
  exact not_congr h.satisfiable_iff

/-- **The risk direction, in one statement.**  (i) Whatever a cut run refutes really is
unrefutable-by-model, so the cut never rejects a well-typed program; (ii) a sound
monotone refuter can nevertheless fire only on the larger derived set, so the cut can
fail to reject an ill-typed one.  The cut's risk is ACCEPTING an ill-typed program,
never REJECTING a well-typed one. -/
theorem cut_risk_is_one_sided :
    (∀ (R : Refuter) (n : ℕ) (G₀ G : System), CutSteps n G₀ G → R.fires G →
        ¬ ∃ rho, SModels rho G₀) ∧
      (∃ (R : Refuter) (G G' : System),
        G ⊆ G' ∧ R.fires G' ∧ ¬ R.fires G ∧ (∃ rho, SModels rho G)) :=
  ⟨fun R _ _ _ h hfire => cut_never_wrongly_refutes R h hfire, refuter_can_miss⟩

/-! ## 4. What the kept branches still do

Branches (a) and (b) are NON-GENERATIVE: every variable they mention is already in the
system.  Their conclusions are contractions -- same left-hand side, same concrete part,
strictly smaller arity -- and they are entailed (section 2).  On a fixed vocabulary they
can therefore only fire finitely often. -/

theorem allVars_insert (c : Constraint) (G : System) :
    allVars (insert c G) = insert c.lhs (vset c) ∪ allVars G := by
  simp [allVars, Finset.biUnion_insert]

theorem allVars_insert_eq_of_subset {c : Constraint} {G : System}
    (h : insert c.lhs (vset c) ⊆ allVars G) : allVars (insert c G) = allVars G := by
  rw [allVars_insert]
  exact Finset.union_eq_right.mpr h

@[simp] theorem reduce_lhs (c : Constraint) (S : Finset Var) (z : Var) :
    (reduce c S z).lhs = c.lhs := rfl

@[simp] theorem reduce_conc (c : Constraint) (S : Finset Var) (z : Var) :
    (reduce c S z).conc = c.conc := rfl

@[simp] theorem vset_reduce (c : Constraint) (S : Finset Var) (z : Var) :
    vset (reduce c S z) = insert z (vset c \ S) := by
  rw [reduce, vset_mk]

theorem vset_reduce_subset {G : System} {c : Constraint} (hc : c ∈ G) {S : Finset Var}
    {z : Var} (hz : z ∈ allVars G) : vset (reduce c S z) ⊆ allVars G := by
  rw [vset_reduce]
  intro v hv
  rcases Finset.mem_insert.mp hv with rfl | hv'
  · exact hz
  · exact vset_subset_allVars hc (Finset.mem_sdiff.mp hv').1

theorem reduce_vars_subset {G : System} {c : Constraint} (hc : c ∈ G) {S : Finset Var}
    {z : Var} (hz : z ∈ allVars G) :
    insert (reduce c S z).lhs (vset (reduce c S z)) ⊆ allVars G := by
  intro v hv
  rcases Finset.mem_insert.mp hv with rfl | hv'
  · exact lhs_mem_allVars (c := c) hc
  · exact vset_reduce_subset hc hz hv'

/-- **The kept branches are non-generative.**  A REUSE or FOLD step introduces no
variable the system did not already mention.  Contrast `CseApp.fresh`: MINT introduces
one by construction. -/
theorem CutStep.allVars_eq {G G' : System} (h : CutStep G G') : allVars G' = allVars G := by
  cases h with
  | @reuse c₁ c₂ z hp hn =>
    have h2 : allVars (insert (reduce c₂ (shared c₁ c₂) z) G) = allVars G :=
      allVars_insert_eq_of_subset (reduce_vars_subset hp.mem₂ hn.mem_allVars)
    rw [reuseResult,
      allVars_insert_eq_of_subset (c := reduce c₁ (shared c₁ c₂) z)
        (by rw [h2]; exact reduce_vars_subset hp.mem₁ hn.mem_allVars), h2]
  | @fold c₁ c₂ hp _ _ =>
    exact allVars_insert_eq_of_subset (reduce_vars_subset hp.mem₂ (lhs_mem_allVars hp.mem₁))

theorem CutSteps.allVars_eq {n : ℕ} {G₀ G : System} (h : CutSteps n G₀ G) :
    allVars G = allVars G₀ := by
  induction h with
  | refl => rfl
  | tail _ hstep ih => rw [hstep.allVars_eq]; exact ih

/-- **The kept branches strictly contract.**  Replacing a shared group of at least two
variables by its single name lowers the arity of the constraint. -/
theorem card_vset_reduce_lt {c : Constraint} {S : Finset Var} {z : Var} (hS : S ⊆ vset c)
    (h2 : 2 ≤ S.card) : (vset (reduce c S z)).card < (vset c).card := by
  have hcard : (vset c \ S).card = (vset c).card - S.card := Finset.card_sdiff_of_subset hS
  have hle : S.card ≤ (vset c).card := Finset.card_le_card hS
  have hins : (vset (reduce c S z)).card ≤ (vset c \ S).card + 1 := by
    rw [vset_reduce]; exact Finset.card_insert_le _ _
  omega

/-- **Characterisation of what a kept branch adds.**  Every constraint of the successor
system is either already present, or is a CONTRACTION of one that is: same left-hand
side, same concrete part, variables drawn from the existing vocabulary, strictly smaller
arity -- and entailed by the system it was derived from. -/
theorem CutStep.new_constraints {G G' : System} (h : CutStep G G') (c : Constraint)
    (hc : c ∈ G') :
    c ∈ G ∨ ∃ d ∈ G, c.lhs = d.lhs ∧ c.conc = d.conc ∧ vset c ⊆ allVars G ∧
      (vset c).card < (vset d).card ∧ SEntails G c := by
  cases h with
  | @reuse c₁ c₂ z hp hn =>
    simp only [reuseResult, Finset.mem_insert] at hc
    obtain ⟨e₁, e₂⟩ := reuse_entails hp hn
    rcases hc with rfl | rfl | hc
    · exact Or.inr ⟨c₁, hp.mem₁, rfl, rfl, vset_reduce_subset hp.mem₁ hn.mem_allVars,
        card_vset_reduce_lt (shared_subset_left _ _) hp.two_le, e₁⟩
    · exact Or.inr ⟨c₂, hp.mem₂, rfl, rfl, vset_reduce_subset hp.mem₂ hn.mem_allVars,
        card_vset_reduce_lt (shared_subset_right _ _) hp.two_le, e₂⟩
    · exact Or.inl hc
  | @fold c₁ c₂ hp h1 h2 =>
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact Or.inr ⟨c₂, hp.mem₂, rfl, rfl,
        vset_reduce_subset hp.mem₂ (lhs_mem_allVars hp.mem₁),
        card_vset_reduce_lt (shared_subset_right _ _) hp.two_le, fold_entails hp h1 h2⟩
    · exact Or.inl hc'

/-! ### The kept branches fire only finitely often

Everything a cut run can derive lives in one explicit finite set: constraints in
`mk`-normal form whose left-hand side and variables come from the input's vocabulary and
whose concrete part is one of the input's. -/

/-- The concrete parts occurring in a system. -/
def concs (G : System) : Finset Row := G.image Constraint.conc

/-- All `mk`-normal constraints over a vocabulary `V` and a set `K` of concrete parts. -/
def normalForms (V : Finset Var) (K : Finset Row) : System :=
  ((V ×ˢ V.powerset) ×ˢ K).image (fun p => mk p.1.1 p.1.2 p.2)

/-- The finite set inside which every cut run from `G` stays. -/
def bound (G : System) : System := G ∪ normalForms (allVars G) (concs G)

theorem mem_normalForms {V : Finset Var} {K : Finset Row} {a : Var} {S : Finset Var} {k : Row}
    (ha : a ∈ V) (hS : S ⊆ V) (hk : k ∈ K) : mk a S k ∈ normalForms V K :=
  Finset.mem_image.mpr ⟨((a, S), k), by
    simp only [Finset.mem_product, Finset.mem_powerset]
    exact ⟨⟨ha, hS⟩, hk⟩, rfl⟩

theorem allVars_normalForms (V : Finset Var) (K : Finset Row) : allVars (normalForms V K) ⊆ V := by
  intro v hv
  obtain ⟨c, hc, hv'⟩ := Finset.mem_biUnion.mp hv
  obtain ⟨⟨⟨a, S⟩, k⟩, hp, rfl⟩ := Finset.mem_image.mp hc
  simp only [Finset.mem_product, Finset.mem_powerset] at hp
  simp only [lhs_mk, vset_mk, Finset.mem_insert] at hv'
  rcases hv' with rfl | hv''
  · exact hp.1.1
  · exact hp.1.2 hv''

theorem concs_normalForms (V : Finset Var) (K : Finset Row) : concs (normalForms V K) ⊆ K := by
  intro k hk
  obtain ⟨c, hc, rfl⟩ := Finset.mem_image.mp hk
  obtain ⟨⟨⟨a, S⟩, j⟩, hp, rfl⟩ := Finset.mem_image.mp hc
  simp only [Finset.mem_product] at hp
  simpa using hp.2

theorem allVars_union (G H : System) : allVars (G ∪ H) = allVars G ∪ allVars H := by
  ext v
  simp only [allVars, Finset.mem_biUnion, Finset.mem_union]
  constructor
  · rintro ⟨c, hc | hc, h⟩
    · exact Or.inl ⟨c, hc, h⟩
    · exact Or.inr ⟨c, hc, h⟩
  · rintro (⟨c, hc, h⟩ | ⟨c, hc, h⟩)
    · exact ⟨c, Or.inl hc, h⟩
    · exact ⟨c, Or.inr hc, h⟩

theorem subset_bound (G : System) : G ⊆ bound G := Finset.subset_union_left

theorem allVars_bound (G : System) : allVars (bound G) = allVars G := by
  rw [bound, allVars_union]
  exact Finset.union_eq_left.mpr (allVars_normalForms _ _)

theorem concs_bound (G : System) : concs (bound G) ⊆ concs G := by
  rw [bound, concs, Finset.image_union]
  exact Finset.union_subset (Finset.Subset.refl _) (concs_normalForms _ _)

theorem reduce_mem_bound {G₀ G : System} (hG : G ⊆ bound G₀) {c : Constraint} (hc : c ∈ G)
    {S : Finset Var} {z : Var} (hz : z ∈ allVars G) : reduce c S z ∈ bound G₀ := by
  have hav : allVars G ⊆ allVars G₀ := by
    have h := allVars_mono hG
    rwa [allVars_bound] at h
  rw [reduce]
  refine Finset.mem_union_right _ (mem_normalForms (hav (lhs_mem_allVars hc)) ?_ ?_)
  · intro v hv
    rcases Finset.mem_insert.mp hv with rfl | hv'
    · exact hav hz
    · exact hav (vset_subset_allVars hc (Finset.mem_sdiff.mp hv').1)
  · exact concs_bound G₀ (Finset.mem_image_of_mem _ (hG hc))

theorem CutStep.bound_invariant {G₀ G G' : System} (hG : G ⊆ bound G₀) (h : CutStep G G') :
    G' ⊆ bound G₀ := by
  cases h with
  | @reuse c₁ c₂ z hp hn =>
    intro c hc
    simp only [reuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · exact reduce_mem_bound hG hp.mem₁ hn.mem_allVars
    · exact reduce_mem_bound hG hp.mem₂ hn.mem_allVars
    · exact hG hc
  | @fold c₁ c₂ hp _ _ =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact reduce_mem_bound hG hp.mem₂ (lhs_mem_allVars hp.mem₁)
    · exact hG hc'

/-- A cut run in which every step actually enlarges the system.  (Without this the rule
can be "applied" forever to no effect, re-deriving constraints already present; that is
not divergence, it is idling, and every implementation deduplicates.) -/
inductive CutChain : ℕ → System → System → Prop
  | refl (G : System) : CutChain 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      CutChain n G G' → CutStep G' G'' → G' ≠ G'' → CutChain (n + 1) G G''

theorem CutChain.toSteps {n : ℕ} {G G' : System} (h : CutChain n G G') : CutSteps n G G' := by
  induction h with
  | refl G => exact CutSteps.refl G
  | tail _ hstep _ ih => exact CutSteps.tail ih hstep

theorem CutChain.bounded {n : ℕ} {G₀ G : System} (h : CutChain n G₀ G) : G ⊆ bound G₀ := by
  induction h with
  | refl G => exact subset_bound G
  | tail _ hstep _ ih => exact hstep.bound_invariant ih

theorem CutChain.card_ge {n : ℕ} {G₀ G : System} (h : CutChain n G₀ G) :
    G₀.card + n ≤ G.card := by
  induction h with
  | refl => omega
  | @tail n G G' G'' _ hstep hne ih =>
    have : G'.card < G''.card :=
      Finset.card_lt_card (Finset.ssubset_iff_subset_ne.mpr ⟨hstep.subset, hne⟩)
    omega

/-- **The kept branches terminate.**  Any chain of productive REUSE/FOLD steps from `G₀`
has length at most `(bound G₀).card`: they can only ever fire finitely often on a fixed
vocabulary. -/
theorem CutChain.length_le {n : ℕ} {G₀ G : System} (h : CutChain n G₀ G) :
    G₀.card + n ≤ (bound G₀).card :=
  le_trans h.card_ge (Finset.card_le_card h.bounded)

/-- The same, as an explicit bound depending only on the input. -/
theorem cut_branches_terminate (G₀ : System) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), CutChain n G₀ G → n ≤ N :=
  ⟨(bound G₀).card, fun n G h => by have := h.length_le; omega⟩

/-! ## 5. Does the CUT rule set terminate?  No.

The cut removes branch (c) of `commonSubexpression` and nothing else.  Two minting rules
survive, and they are NOT alike:

* `splitConcrete` (`Constraints.scala:816`) consults the reverse lookup
  (`rhss(RHSAbstr(abstr))`) BEFORE minting, so it mints only for a variable group nothing
  yet names.  Section 5.2 turns that guard into a decreasing measure: split-minting alone
  terminates.
* `resolution` (`Constraints.scala:1047`) takes NO `rhss` argument.  It calls `fresh`
  unconditionally whenever its two premises match.  Section 5.1 shows the consequence:
  one fixed pair of premises admits step chains of EVERY length, exactly as
  `Divergence.seed_diverges` does for the branch the cut removes.

So the honest answer to "does the cut terminate?" is NO, and the reason is precise: the
finiteness argument of section 4 rests on `allVars` never growing, and `resolution`
breaks that on its first step (`ResStep.escapes`). -/

/-! ### 5.1 `resolution` alone diverges -/

/-- The premises of `resolution`:

```
a <- C+ D* x        (here: `mk v {x} C`)
a <- y  D* E+       (here: `mk v {y} D`)
```

with a genuinely fresh `z`.  There is no "already named" side condition, because the
Scala rule has none. -/
structure ResApp (G : System) (v x y : Var) (C D : Row) (z : Var) : Prop where
  /-- the first premise is in the system -/
  mem₁ : mk v {x} C ∈ G
  /-- the second premise is in the system -/
  mem₂ : mk v {y} D ∈ G
  /-- `tops`, the fields of the first premise not shared -- the rule's guard -/
  tops : C \ D ≠ ∅
  /-- `bots`, the fields of the second premise not shared -- the rule's guard -/
  bots : D \ C ≠ ∅
  /-- `z` is a genuinely fresh variable -/
  fresh : z ∉ allVars G

/-- The three constraints `resolution` emits. -/
def resResult (G : System) (v x y : Var) (C D : Row) (z : Var) : System :=
  insert (mk v {z} (C ∪ D)) (insert (mk x {z} (D \ C)) (insert (mk y {z} (C \ D)) G))

/-- One application of the resolution rule. -/
inductive ResStep : System → System → Prop
  | intro {G : System} {v x y : Var} {C D : Row} {z : Var} :
      ResApp G v x y C D z → ResStep G (resResult G v x y C D z)

theorem subset_resResult (G : System) (v x y : Var) (C D : Row) (z : Var) :
    G ⊆ resResult G v x y C D z := fun c hc => by
  simp only [resResult, Finset.mem_insert]
  exact Or.inr (Or.inr (Or.inr hc))

theorem ResStep.subset {G G' : System} (h : ResStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact subset_resResult _ _ _ _ _ _ _

/-- Every resolution step introduces a variable the system did not have. -/
theorem ResStep.fresh_var {G G' : System} (h : ResStep G G') :
    ∃ z, z ∈ allVars G' ∧ z ∉ allVars G := by
  cases h with
  | @intro v x y C D z happ =>
    exact ⟨z, mem_allVars (Finset.mem_insert_self _ _) (Or.inr (by simp)), happ.fresh⟩

/-- **`resolution` escapes the vocabulary bound of section 4** on its very first step.
This is precisely why the argument that terminates the kept branches does not extend to
the cut rule set. -/
theorem ResStep.escapes {G G' : System} (h : ResStep G G') : ¬ G' ⊆ bound G := by
  intro hsub
  obtain ⟨z, hz', hz⟩ := h.fresh_var
  have h1 : allVars G' ⊆ allVars G := by
    have h2 := allVars_mono hsub
    rwa [allVars_bound] at h2
  exact hz (h1 hz')

theorem ResStep.ssubset {G G' : System} (h : ResStep G G') : G ⊂ G' := by
  cases h with
  | @intro v x y C D z happ =>
    refine (Finset.ssubset_iff_of_subset (subset_resResult _ v x y C D z)).mpr
      ⟨mk v {z} (C ∪ D), Finset.mem_insert_self _ _, fun hmem => ?_⟩
    exact happ.fresh (mem_allVars hmem (Or.inr (by simp)))

theorem ResStep.card_lt {G G' : System} (h : ResStep G G') : G.card < G'.card :=
  Finset.card_lt_card h.ssubset

/-- A resolution step is always available on a matching pair: freshness never blocks it,
and -- unlike `splitConcrete` -- nothing else does either. -/
theorem res_exists_step {G : System} {v x y : Var} {C D : Row} (h₁ : mk v {x} C ∈ G)
    (h₂ : mk v {y} D ∈ G) (ht : C \ D ≠ ∅) (hb : D \ C ≠ ∅) : ∃ G', ResStep G G' := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars G)
  exact ⟨_, ResStep.intro ⟨h₁, h₂, ht, hb, hz⟩⟩

/-- `ResSteps n G G'`: `G'` is reachable from `G` by exactly `n` resolution steps. -/
inductive ResSteps : ℕ → System → System → Prop
  | refl (G : System) : ResSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      ResSteps n G G' → ResStep G' G'' → ResSteps (n + 1) G G''

theorem ResSteps.subset {n : ℕ} {G G' : System} (h : ResSteps n G G') : G ⊆ G' := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep ih => exact ih.trans hstep.subset

/-- Chains of every length exist: one matching pair of premises can be re-used forever,
because each application needs only a new fresh name and the pair is never consumed. -/
theorem res_steps_exists {G : System} {v x y : Var} {C D : Row} (h₁ : mk v {x} C ∈ G)
    (h₂ : mk v {y} D ∈ G) (ht : C \ D ≠ ∅) (hb : D \ C ≠ ∅) (n : ℕ) :
    ∃ G', ResSteps n G G' ∧ G.card + n ≤ G'.card := by
  induction n with
  | zero => exact ⟨G, ResSteps.refl G, by omega⟩
  | succ n ih =>
    obtain ⟨G', hsteps, hcard⟩ := ih
    obtain ⟨G'', hstep⟩ :=
      res_exists_step (hsteps.subset h₁) (hsteps.subset h₂) ht hb
    have := hstep.card_lt
    exact ⟨G'', ResSteps.tail hsteps hstep, by omega⟩

theorem res_steps_measure {μ : System → ℕ} (hμ : ∀ G G', ResStep G G' → μ G' < μ G)
    {n : ℕ} {G G' : System} (h : ResSteps n G G') : μ G' + n ≤ μ G := by
  induction h with
  | refl => omega
  | @tail n G G' G'' _ hstep ih =>
    have := hμ G' G'' hstep
    omega

/-! #### A concrete divergent seed for the surviving rule

`a <- (|1|) x` and `a <- (|2|) y`: the two concrete parts differ in both directions, so
`tops` and `bots` are both nonempty and `resolution` fires -- and keeps firing on the
same two premises, with a new name each time. -/

/-- `a <- (|1|) x`. -/
def resSeed₁ : Constraint := mk 0 {1} ({1} : Row)

/-- `a <- (|2|) y`. -/
def resSeed₂ : Constraint := mk 0 {2} ({2} : Row)

/-- The two-constraint divergent seed for `resolution`. -/
def resSeed : System := {resSeed₁, resSeed₂}

theorem resSeed_tops : ({1} : Row) \ {2} ≠ ∅ := by decide

theorem resSeed_bots : ({2} : Row) \ {1} ≠ ∅ := by decide

/-- **The rule set that survives the cut does not terminate.**  From `resSeed` there are
resolution chains of every length, and the working set grows by at least one constraint
per step.  Compare `Divergence.seed_diverges`, which says the same of the branch the cut
REMOVES: cutting branch (c) does not remove the phenomenon, it only removes one of its
sources. -/
theorem resSeed_diverges (n : ℕ) : ∃ G, ResSteps n resSeed G ∧ resSeed.card + n ≤ G.card :=
  res_steps_exists (v := 0) (x := 1) (y := 2) (C := {1}) (D := {2})
    (Finset.mem_insert_self _ _)
    (Finset.mem_insert_of_mem (Finset.mem_singleton_self _)) resSeed_tops resSeed_bots n

/-- **No measure into `ℕ` decreases on every resolution step.** -/
theorem res_no_decreasing_measure :
    ¬ ∃ μ : System → ℕ, ∀ G G', ResStep G G' → μ G' < μ G := by
  rintro ⟨μ, hμ⟩
  obtain ⟨G, hsteps, -⟩ := resSeed_diverges (μ resSeed + 1)
  have := res_steps_measure hμ hsteps
  omega

/-! ### 5.2 `splitConcrete` is different: its reverse lookup IS a measure -/

/-- The premises of `splitConcrete`.  The `unnamed` field is the Scala's
`rhss(RHSAbstr(abstr)) == None`: the rule mints only when nothing yet names the group. -/
structure SplitApp (G : System) (c : Constraint) (u : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- the reverse lookup missed: nothing names this group yet -/
  unnamed : ¬ Named G (vset c)
  /-- `u` is a genuinely fresh variable -/
  fresh : u ∉ allVars G

/-- The two constraints `splitConcrete` emits. -/
def splitResult (G : System) (c : Constraint) (u : Var) : System :=
  insert (mk u (vset c) ∅) (insert (mk c.lhs {u} c.conc) G)

/-- One application of the split-concrete rule. -/
inductive SplitStep : System → System → Prop
  | intro {G : System} {c : Constraint} {u : Var} :
      SplitApp G c u → SplitStep G (splitResult G c u)

theorem subset_splitResult (G : System) (c : Constraint) (u : Var) :
    G ⊆ splitResult G c u := fun d hd => by
  simp only [splitResult, Finset.mem_insert]
  exact Or.inr (Or.inr hd)

theorem SplitStep.subset {G G' : System} (h : SplitStep G G') : G ⊆ G' := by
  cases h with | intro _ => exact subset_splitResult _ _ _

/-- The variable groups `splitConcrete` could still name: those carried by a constraint
with a nonempty concrete part and at least two variables, and not yet named. -/
def splitCands (G : System) : Finset (Finset Var) :=
  ((G.filter (fun c => c.conc ≠ ∅ ∧ 2 ≤ (vset c).card)).image vset).filter
    (fun S => ¬ Named G S)

theorem mem_splitCands {G : System} {S : Finset Var} :
    S ∈ splitCands G ↔
      (∃ c ∈ G, vset c = S ∧ c.conc ≠ ∅ ∧ 2 ≤ (vset c).card) ∧ ¬ Named G S := by
  constructor
  · intro h
    rw [splitCands, Finset.mem_filter] at h
    obtain ⟨him, hnn⟩ := h
    obtain ⟨c, hc, rfl⟩ := Finset.mem_image.mp him
    rw [Finset.mem_filter] at hc
    exact ⟨⟨c, hc.1, rfl, hc.2.1, hc.2.2⟩, hnn⟩
  · rintro ⟨⟨c, hc, rfl, h1, h2⟩, hnn⟩
    rw [splitCands, Finset.mem_filter]
    exact ⟨Finset.mem_image.mpr ⟨c, Finset.mem_filter.mpr ⟨hc, h1, h2⟩, rfl⟩, hnn⟩

/-- **The reverse lookup is a termination measure for `splitConcrete`.**  Each mint names
a group that had no name, and neither emitted constraint is itself a candidate (one has
an empty concrete part, the other arity one), so no new candidate is ever created. -/
theorem SplitStep.cands_lt {G G' : System} (h : SplitStep G G') :
    (splitCands G').card < (splitCands G).card := by
  cases h with
  | @intro c u happ =>
    have hsub : splitCands (splitResult G c u) ⊆ (splitCands G).erase (vset c) := by
      intro S hS
      rw [mem_splitCands] at hS
      obtain ⟨⟨d, hd, hvd, hdc, hdcard⟩, hnn⟩ := hS
      have hd' : d ∈ G := by
        simp only [splitResult, Finset.mem_insert] at hd
        rcases hd with rfl | rfl | hd
        · exact absurd rfl hdc
        · exfalso; simp at hdcard
        · exact hd
      refine Finset.mem_erase.mpr ⟨?_, ?_⟩
      · rintro rfl
        exact hnn ⟨mk u (vset c) ∅, Finset.mem_insert_self _ _, by simp, rfl⟩
      · exact mem_splitCands.mpr ⟨⟨d, hd', hvd, hdc, hdcard⟩,
          fun hn => hnn (hn.mono (subset_splitResult _ c u))⟩
    have hmem : vset c ∈ splitCands G :=
      mem_splitCands.mpr ⟨⟨c, happ.mem, rfl, happ.conc_ne, happ.two_le⟩, happ.unnamed⟩
    exact lt_of_le_of_lt (Finset.card_le_card hsub) (Finset.card_erase_lt_of_mem hmem)

/-- `SplitSteps n G G'`: `G'` is reachable from `G` by exactly `n` split-concrete steps. -/
inductive SplitSteps : ℕ → System → System → Prop
  | refl (G : System) : SplitSteps 0 G G
  | tail {n : ℕ} {G G' G'' : System} :
      SplitSteps n G G' → SplitStep G' G'' → SplitSteps (n + 1) G G''

/-- **`splitConcrete` terminates**, its reverse lookup notwithstanding the fresh name:
every chain from `G₀` is at most `(splitCands G₀).card` long. -/
theorem SplitSteps.length_le {n : ℕ} {G₀ G : System} (h : SplitSteps n G₀ G) :
    (splitCands G).card + n ≤ (splitCands G₀).card := by
  induction h with
  | refl => omega
  | @tail n G G' G'' _ hstep ih =>
    have := hstep.cands_lt
    omega

theorem split_terminates (G₀ : System) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), SplitSteps n G₀ G → n ≤ N :=
  ⟨(splitCands G₀).card, fun n G h => by have := h.length_le; omega⟩

/-! ### 5.3 The verdict on the cut rule set -/

/-- The rule set that survives the cut: the two kept CSE branches, plus the two other
generative rules the ticket leaves alone. -/
inductive CutRule : System → System → Prop
  | keep {G G' : System} : CutStep G G' → CutRule G G'
  | res {G G' : System} : ResStep G G' → CutRule G G'
  | split {G G' : System} : SplitStep G G' → CutRule G G'

/-- **NEGATIVE RESULT.  There is no measure into `ℕ` that decreases on every step of the
cut rule set** -- so the standard finiteness argument does not merely fail to apply, no
well-founded `ℕ`-ranking of systems exists at all.  The obstruction is `resolution`,
which mints unconditionally; the kept CSE branches (section 4) and `splitConcrete`
(section 5.2) each terminate on their own. -/
theorem cut_no_decreasing_measure :
    ¬ ∃ μ : System → ℕ, ∀ G G', CutRule G G' → μ G' < μ G := by
  rintro ⟨μ, hμ⟩
  exact res_no_decreasing_measure ⟨μ, fun G G' h => hμ G G' (CutRule.res h)⟩

/-- **What was achieved in section 5: a NEGATIVE result.**  The cut rule set does not
terminate.  (i) `resolution` alone admits chains of every length from a two-constraint
seed, growing the system by a constraint per step; (ii) hence no `ℕ`-valued measure
decreases on every cut-rule step; (iii) the section-4 finiteness argument fails for a
specific, identifiable reason -- a resolution step leaves the vocabulary bound at once. -/
theorem cut_does_not_terminate :
    (∀ n : ℕ, ∃ G, ResSteps n resSeed G ∧ resSeed.card + n ≤ G.card) ∧
      (¬ ∃ μ : System → ℕ, ∀ G G', CutRule G G' → μ G' < μ G) ∧
      (∀ G G' : System, ResStep G G' → ¬ G' ⊆ bound G) :=
  ⟨resSeed_diverges, cut_no_decreasing_measure, fun _ _ h => h.escapes⟩

/-! ## 6. Non-vacuity

Three checks that none of the above is about an empty situation: branch (a) can fire,
branch (b) can fire, and there are systems on which ONLY branch (c) can fire -- so the
cut genuinely removes derivations. -/

namespace CutExample

/-- `a <- (p, q, r)`. -/
def d₁ : Constraint := mk 0 {2, 3, 4} ∅

/-- `b <- (p, q, s)`. -/
def d₂ : Constraint := mk 1 {2, 3, 5} ∅

/-- `w <- (p, q)` -- an existing name for the shared group. -/
def dn : Constraint := mk 6 {2, 3} ∅

/-- `a <- (p, q)` -- a premise that IS the shared group. -/
def e₁ : Constraint := mk 0 {2, 3} ∅

/-- A system on which branch (a) fires. -/
def GReuse : System := {d₁, d₂, dn}

/-- A system on which branch (b) fires. -/
def GFold : System := {e₁, d₂}

theorem shared₁₂ : shared d₁ d₂ = {2, 3} := by
  rw [d₁, d₂, shared, vset_mk, vset_mk]; decide

theorem sharedE : shared e₁ d₂ = {2, 3} := by
  rw [e₁, d₂, shared, vset_mk, vset_mk]; decide

/-- **Branch (a) fires.** -/
theorem reuse_fires : CutStep GReuse (reuseResult GReuse d₁ d₂ 6) := by
  refine CutStep.reuse ⟨by simp [GReuse], by simp [GReuse], by decide, ?_⟩
    ⟨dn, by simp [GReuse], rfl, ?_, rfl⟩
  · rw [shared₁₂]; decide
  · rw [shared₁₂, dn, vset_mk]

/-- **Branch (b) fires.** -/
theorem fold_fires : CutStep GFold (foldResult GFold e₁ d₂) := by
  refine CutStep.fold ⟨by simp [GFold], by simp [GFold], by decide, ?_⟩ ?_ rfl
  · rw [sharedE]; decide
  · rw [sharedE, e₁, vset_mk]

end CutExample

/-- **The cut really removes derivations.**  On `Divergence.seed` -- two constraints
sharing exactly two variables -- the shared group has no name in the system and neither
premise IS the shared group, so branches (a) and (b) are both inapplicable to that pair,
while branch (c) fires.  So the cut is not a no-op, and section 2's meaning-preservation
theorem is not vacuous. -/
theorem cut_removes_something :
    ¬ Named seed (shared seed₁ seed₂) ∧ vset seed₁ ≠ shared seed₁ seed₂ ∧
      vset seed₂ ≠ shared seed₁ seed₂ ∧
      ∃ z, CseBranch seed (cseResult seed seed₁ seed₂ z) := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · rw [seed_shared]
    rintro ⟨d, hd, hv, -⟩
    rw [seed, Finset.mem_insert, Finset.mem_singleton] at hd
    rcases hd with rfl | rfl
    · rw [seed₁, vset_mk] at hv; exact absurd hv (by decide)
    · rw [seed₂, vset_mk] at hv; exact absurd hv (by decide)
  · rw [seed_shared, seed₁, vset_mk]; decide
  · rw [seed_shared, seed₂, vset_mk]; decide
  · obtain ⟨z, hz⟩ := exists_fresh (allVars seed)
    exact ⟨z, CseBranch.mint ⟨Finset.mem_insert_self _ _,
      Finset.mem_insert_of_mem (Finset.mem_singleton_self _), seed_lhs_ne, seed_guard, hz⟩⟩

/-! ## 7. Summary

| question | answer | theorem |
| --- | --- | --- |
| is branch (a) sound? | yes, by outright ENTAILMENT | `reuse_entails` |
| is branch (b) sound? | yes, by outright ENTAILMENT | `fold_entails` |
| is branch (c) sound? | yes, as a CONSERVATIVE EXT at the new variable | `mint_conservativeExt` |
| does the cut change the models? | no, not on any run | `cut_preserves_meaning` |
| can the cut wrongly refute? | NO, for any sound refuter | `cut_never_wrongly_refutes` |
| can the cut miss a refutation? | yes, for a sound MONOTONE refuter | `refuter_can_miss` |
| ... by losing information? | no -- only via incomplete checks | `complete_refuter_unaffected` |
| are the kept branches generative? | no | `CutStep.allVars_eq` |
| what do they derive? | entailed contractions of existing constraints | `CutStep.new_constraints` |
| do the kept branches terminate? | YES, on a fixed vocabulary | `CutChain.length_le` |
| does the CUT RULE SET terminate? | **NO** | `cut_does_not_terminate` |

The last line is the honest negative outcome the task anticipated, and section 5 locates
it exactly.  Of the two minting rules the cut leaves alone, `splitConcrete` consults the
reverse lookup before minting and therefore terminates by itself (`split_terminates`);
`resolution` does not consult anything and mints on every match, so one fixed pair of
premises drives chains of every length (`resSeed_diverges`).  A resolution step leaves
the finite vocabulary that bounds the kept branches on its first application
(`ResStep.escapes`), which is precisely why section 4's argument does not extend.

### What is NOT proved here

* That the 23 measured contact points of branch (c) with emitted output ever ACTUALLY
  change a refutation.  Section 3 shows the risk direction abstractly and exhibits a
  sound monotone refuter that fires only on the larger of two systems; that pair is
  hand-built, NOT derived by a MINT step.  Whether any real Ermine program's refutation
  depends on a minted variable is an empirical question this file does not settle.
* Termination of the cut rule set on the constraint systems Ermine actually generates.
  `resSeed` is a legal system; whether Ermine's front end can emit two partitions of the
  same variable each with a single abstract part and incomparable concrete parts is,
  again, empirical.  What is proved is that no measure argument can rule it out.
* Any interaction between the rules.  `SplitSteps` chains are split-only and
  `ResSteps` chains resolution-only; `CutChain`s are (a)/(b)-only.  Interleaved chains
  are not analysed, and the split measure of section 5.2 is NOT invariant under
  REUSE steps, which can create new split candidates. -/


end Rowpartition
