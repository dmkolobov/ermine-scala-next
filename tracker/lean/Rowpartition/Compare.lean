import Rowpartition.Basic
import Rowpartition.Rules
import Rowpartition.Canonical
import Rowpartition.Divergence
import Rowpartition.Cut

/-!
# Clean calculus versus the five-line cut: the side-by-side

`Canonical.lean` builds a FULLY NON-GENERATIVE calculus -- six rules, not one of which
mints a variable -- and settles what it buys.  `Cut.lean` formalises the competing
proposal: leave Ermine's solver alone except for five lines, deleting the MINT branch of
`commonSubexpression` (`Constraints.scala:1104-1111`, guarded in the source by
`GenRules.cseMints`).  This file is the comparison the exercise is for: **what does the
clean calculus prove that the cut does not?**

Where `Cut.lean` already settles a question, this file CITES it rather than reproving it,
and adds what the comparison needs and neither file has:

* **§1 termination.**  `resStep_canonical_measure_increases`: `Canonical.Meas` -- the
  lexicographic measure whose descent IS the clean calculus's termination proof --
  strictly INCREASES on every retained `resolution` step, in its dominant coordinate.
  `resStep_canonical_measure_fails` states the negative directly.  So the clean calculus's
  argument does not merely fail to apply to the cut, it is refuted for it.  The bridge
  `varsOf_toList` makes this a statement about the ACTUAL measure, not a look-alike.
  `resSeed_satisfiable`: `Cut.resSeed`, the two-constraint system carrying
  `Cut.resSeed_diverges`, is SATISFIABLE -- so the obstruction is not an artefact of
  contradictory input; the correct answer on that input is "satisfiable", and no measure
  argument can certify that the retained rule ever gets there.
* **§2 meaning preservation.**  Both have it; the statements are not the same statement.
  `res_not_model_preserving` refutes model-set equality for a minting step, which is what
  makes the cut's meaning preservation a weaker claim about a weaker object than
  `Canonical.Step.preserves`.  `res_conservative` and `split_conservative` supply, from
  `Rules.rule6`/`rule4`, the weaker claim that does hold for the rules the cut retains --
  `Cut.lean` proves conservativity for branch (c), not for those two.
  `vocabulary_restriction_necessary` shows the vocabulary restriction in
  `Cut.cut_preserves_meaning`'s entailment clause cannot be dropped.
* **§3-4 confluence and decidability.**  `Cut.lean` does not ask these.  `FullCutStep` is
  the clean calculus's six rules PLUS every generative rule the cut retains, and
  `full_cut_not_locally_confluent`, `full_cut_not_joinable`,
  `full_cut_normal_form_can_be_unsat` show the cut inherits both of `Canonical`'s negative
  results.  Inheritance is not automatic: each requires showing that all five retained
  generative rules are blocked on both critical-pair results.
* **§5** the table, and `bottom_line`, which conjoins the headline facts.

## Modelling choices, stated honestly

1. §3-4 take the non-generative rules in `Canonical`'s REPLACING form (they erase what
   they rewrite) and the generative rules in Ermine's ADDITIVE form (they only add).  That
   is the fair reading of "the solver with branch (c) removed" against "the clean
   calculus", and the reading most favourable to the cut: replacing rules are strictly
   stronger.  The non-confluence of §3 does depend on it: read additively, neither premise
   is destroyed and this particular pair would join.  That observation is not formalised
   here -- no additive form of `occurs`/`absorb` is defined -- and it is why §5's closing
   list records the additive reading as an open question rather than a settled one.
2. `FullCutStep`'s generative constructors are deliberately MORE permissive than the
   source: `splitMint` omits the `unnamed` guard of `Cut.SplitApp`, and `splitReuse`
   covers the complementary case, so between them they fire whenever `splitConcrete`
   could.  A more permissive rule set makes a normal-form claim stronger, never weaker.
3. Measured on one 129-module boot, only `commonSubexpression` fires among the generative
   rules: `resolution` and `splitConcrete` never fire once, and `disjunction` is disabled.
   Nothing below contradicts that.  A measurement over one workload is not a termination
   theorem, and §1's seed is a satisfiable two-constraint system on which the retained
   rules have reduction chains of every length.
-/

namespace Rowpartition
namespace Compare

/-! ## 0. Bridging `Canonical`'s measure to `Divergence`'s systems

`Canonical` measures lists of constraints, `Divergence` and `Cut` work with finsets.  To
say "the clean calculus's own measure fails for the cut" and mean the actual measure, the
two variable counts have to be identified. -/

/-- `Canonical`'s variable set (on lists) and `Divergence`'s (on finsets) agree. -/
theorem varsOf_toList (G : System) : varsOf G.toList = allVars G := by
  ext v
  rw [mem_varsOf]
  simp only [Finset.mem_toList, mem_cvars, allVars, Finset.mem_biUnion, Finset.mem_insert,
    vset, List.mem_toFinset]

/-- The lexicographic order is asymmetric, so "increases" really does refute
"decreases". -/
theorem lexLt_asymm {x y : Nat × Nat × Nat} (h : LexLt x y) : ¬ LexLt y x := by
  unfold LexLt at *
  omega


/-! ## 1. Termination: the one property the clean calculus has and the cut does not

Cited on the clean side: `Canonical.Step.decreasing` (every rule strictly decreases
`Meas` in `LexLt`) and `Canonical.no_infinite_descent` (hence no infinite reduction
sequence).

Cited on the cut side, from `Cut.lean`: `Cut.CutChain.length_le` and
`Cut.cut_branches_terminate` (the kept common-subexpression branches fire only finitely
often); `Cut.split_terminates` (`splitConcrete`'s reverse lookup is itself a measure);
`Cut.res_no_decreasing_measure` and `Cut.cut_does_not_terminate` (`resolution` mints
unconditionally, so the cut rule set admits no `ℕ`-valued decreasing measure).

What is added here is the sharper form of the negative.  `Cut.lean` says no measure exists.
This section says something more specific and more damaging to the analogy: the SPECIFIC
measure that carries the clean calculus's termination proof strictly INCREASES on a
retained step, in its dominant coordinate.  There is therefore no repair of the clean
argument that could be transported to the cut. -/

/-- A retained `resolution` step strictly enlarges the vocabulary. -/
theorem resStep_allVars_card_lt {G G' : System} (h : ResStep G G') :
    (allVars G).card < (allVars G').card := by
  obtain ⟨z, hz', hz⟩ := h.fresh_var
  exact Finset.card_lt_card
    ((Finset.ssubset_iff_of_subset (allVars_mono h.subset)).mpr ⟨z, hz', hz⟩)

/-- **`Canonical`'s measure goes the WRONG way on a rule the cut retains**, and in its
most significant coordinate.  `Canonical.Step.decreasing` asserts `LexLt (Meas s'.cs)
(Meas s.cs)` for every rule of the clean calculus; here the same `LexLt` holds in the
opposite direction. -/
theorem resStep_canonical_measure_increases {G G' : System} (h : ResStep G G') :
    LexLt (Meas G.toList) (Meas G'.toList) := by
  have hv : (varsOf G.toList).card < (varsOf G'.toList).card := by
    rw [varsOf_toList, varsOf_toList]; exact resStep_allVars_card_lt h
  unfold LexLt Meas
  simp only
  omega

/-- ... hence the clean calculus's measure certainly does not decrease on the cut: its
termination argument is not merely unavailable for the cut, it is refuted for it. -/
theorem resStep_canonical_measure_fails {G G' : System} (h : ResStep G G') :
    ¬ LexLt (Meas G'.toList) (Meas G.toList) :=
  lexLt_asymm (resStep_canonical_measure_increases h)

/-! ### The divergent seed is satisfiable

`Cut.resSeed_diverges` exhibits reduction chains of every length from a two-constraint
system.  It does not say whether that system has a model.  It does -- so the obstruction is
not an artefact of contradictory input: the correct answer on this input is "satisfiable",
and section 5.1 of `Cut.lean` shows no measure can certify that the rule reaches it.  This
is the same shape as `Divergence.coStar_satisfiable` for the branch being cut. -/

/-- A model of `Cut.resSeed`: `a = {1,2}`, `x = {2}`, `y = {1}`. -/
def rhoRes : Assign := fun v => if v = 0 then {1, 2} else if v = 1 then {2} else {1}

theorem rhoRes_models : SModels rhoRes resSeed := by
  intro c hc
  simp only [resSeed, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl
  · change Sat rhoRes (mk 0 {1} ({1} : Row))
    rw [sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩ <;> decide
  · change Sat rhoRes (mk 0 {2} ({2} : Row))
    rw [sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩ <;> decide

/-- **The seed carrying `Cut.resSeed_diverges` is SATISFIABLE.**  So the obstruction is
not an artefact of contradictory input: the correct answer on this input is
"satisfiable". -/
theorem resSeed_satisfiable : ∃ rho, SModels rho resSeed := ⟨rhoRes, rhoRes_models⟩

/-- **The termination separation, as one statement.**  The clean calculus terminates.  So
do the cut's kept common-subexpression branches.  The cut RULE SET admits no `ℕ`-valued
decreasing measure at all -- the obstruction living on an input that has a model -- and
the clean calculus's own measure runs strictly BACKWARDS on the rule responsible. -/
theorem termination_separation :
    (∀ f : ℕ → State, (∀ i, Step (f i) (f (i + 1))) → False) ∧
    (∀ G₀ : System, ∃ N : ℕ, ∀ (n : ℕ) (G : System), CutChain n G₀ G → n ≤ N) ∧
    (¬ ∃ μ : System → ℕ, ∀ G G', CutRule G G' → μ G' < μ G) ∧
    (∃ rho, SModels rho resSeed) ∧
    (∀ G G' : System, ResStep G G' → LexLt (Meas G.toList) (Meas G'.toList)) :=
  ⟨no_infinite_descent, cut_branches_terminate, cut_no_decreasing_measure,
   resSeed_satisfiable, fun _ _ h => resStep_canonical_measure_increases h⟩

/-! ## 2. Meaning preservation: both have it, and the statements differ

* `Canonical.Step.preserves` is an EQUALITY OF MODEL SETS in the same variable space:
  `∀ rho, Models rho s.toSystem ↔ Models rho s'.toSystem`.  It holds for EVERY rule,
  because a `State` retains its eliminated variables in `solved`, so nothing is quantified
  away.
* `Cut.CutStep.models_iff` is the same statement for the cut's KEPT branches -- they derive
  only entailed consequences, so they too preserve the model set exactly.
* For the rules the cut RETAINS the statement is unavailable, and not by accident: a model
  of the premises assigns the minted `z` whatever it likes.  `res_not_model_preserving`
  exhibits one.  What survives is a CONSERVATIVE EXTENSION (`res_conservative`,
  `split_conservative`, from `Rules.rule6`/`rule4`): every model of the premises extends,
  by changing only `z`, to a model of the conclusion.  That yields satisfiability-iff and
  entailment-iff, but the entailment-iff is RESTRICTED to the old vocabulary, and
  `vocabulary_restriction_necessary` shows the restriction is load-bearing.

So "meaning preservation" is proved for both, but for the cut it is an equivalence of
theories over the input vocabulary, not an identity of model sets. -/

/-- Cited: every rule of the clean calculus preserves the model set exactly. -/
theorem canonical_preserves_models (s s' : State) (h : Step s s') (rho : Assign) :
    Models rho s.toSystem ↔ Models rho s'.toSystem := h.preserves rho

/-- Cited from `Cut.lean`: so does every KEPT branch of the cut. -/
theorem cut_branch_preserves_models (G G' : System) (h : CutStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G' := h.models_iff rho

/-- The half a monotone rule gets for free. -/
theorem resStep_models_downward {G G' : System} (h : ResStep G G') {rho : Assign}
    (hm : SModels rho G') : SModels rho G := SModels.mono h.subset hm

/-- **A retained minting step does NOT preserve the model set.**  Take the satisfiable
seed and the model that sends the fresh `z` to `{9}`: it models the premises and refutes
the conclusion `a <- (z, (|{1,2}|))`, because that constraint forces `rho z ⊆ rho a`.
This is the precise sense in which the cut's meaning preservation is a weaker statement
than `Canonical.Step.preserves`. -/
theorem res_not_model_preserving :
    ∃ (G G' : System) (rho : Assign), ResStep G G' ∧ SModels rho G ∧ ¬ SModels rho G' := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars resSeed)
  have hm₁ : resSeed₁ ∈ resSeed := Finset.mem_insert_self _ _
  have hm₂ : resSeed₂ ∈ resSeed := Finset.mem_insert_of_mem (Finset.mem_singleton_self _)
  have hz0 : (0 : Var) ≠ z := fun h => hz (h ▸ lhs_mem_allVars hm₁)
  refine ⟨resSeed, resResult resSeed 0 1 2 {1} {2} z, setVar rhoRes z {9},
    ResStep.intro ⟨hm₁, hm₂, resSeed_tops, resSeed_bots, hz⟩,
    sModels_setVar hz _ rhoRes_models, ?_⟩
  intro hm
  have hsat : Sat (setVar rhoRes z {9}) (mk 0 {z} (({1} : Row) ∪ {2})) :=
    hm _ (Finset.mem_insert_self _ _)
  have hsub := hsat.subset_lhs (v := z) (by simp [mk])
  simp only [lhs_mk, setVar_self] at hsub
  rw [setVar_of_ne _ _ hz0] at hsub
  have h9 : (9 : Label) ∈ rhoRes 0 := hsub (by simp)
  simp [rhoRes] at h9

/-- Cited and instantiated: the retained `resolution` IS a conservative extension.  This is
`Rules.rule6` with `C := C₁ \ C₂`, `D := C₁ ∩ C₂`, `E := C₂ \ C₁`, i.e. exactly the
`tops`/`bots` split the Scala computes.  `Cut.mint_conservativeExt` does this for the
branch being CUT; this does it for a branch being KEPT. -/
theorem res_conservative {a x y z : Var} {C₁ C₂ : Finset Label}
    (haz : a ≠ z) (hxz : x ≠ z) (hyz : y ≠ z) :
    ConservativeExt [⟨a, [x], C₁⟩, ⟨a, [y], C₂⟩] z
      [⟨a, [z], C₁ ∪ C₂⟩, ⟨x, [z], C₂ \ C₁⟩, ⟨y, [z], C₁ \ C₂⟩] := by
  have hCD : Disjoint (C₁ \ C₂) (C₁ ∩ C₂) := by
    rw [Finset.disjoint_left]; intro l hl hl'
    exact (Finset.mem_sdiff.mp hl).2 (Finset.mem_inter.mp hl').2
  have hDE : Disjoint (C₁ ∩ C₂) (C₂ \ C₁) := by
    rw [Finset.disjoint_left]; intro l hl hl'
    exact (Finset.mem_sdiff.mp hl').2 (Finset.mem_inter.mp hl).1
  have e1 : (C₁ \ C₂) ∪ (C₁ ∩ C₂) = C₁ := by
    ext l
    simp only [Finset.mem_union, Finset.mem_sdiff, Finset.mem_inter]
    tauto
  have e2 : (C₁ ∩ C₂) ∪ (C₂ \ C₁) = C₂ := by
    ext l
    simp only [Finset.mem_union, Finset.mem_sdiff, Finset.mem_inter]
    tauto
  have e3 : (C₁ \ C₂) ∪ (C₁ ∩ C₂) ∪ (C₂ \ C₁) = C₁ ∪ C₂ := by
    ext l
    simp only [Finset.mem_union, Finset.mem_sdiff, Finset.mem_inter]
    tauto
  have e4 : (C₂ \ C₁) \ (C₁ \ C₂) = C₂ \ C₁ := by
    ext l
    simp only [Finset.mem_sdiff]
    tauto
  have e5 : (C₁ \ C₂) \ (C₂ \ C₁) = C₁ \ C₂ := by
    ext l
    simp only [Finset.mem_sdiff]
    tauto
  have h := rule6 (a := a) (x := x) (y := y) (z := z) (C := C₁ \ C₂) (D := C₁ ∩ C₂)
    (E := C₂ \ C₁) hCD hDE haz hxz hyz
  rwa [e3, e1, e2, e4, e5] at h

/-- Cited and instantiated: the retained `splitConcrete` is a conservative extension
(`Rules.rule4`). -/
theorem split_conservative {a u : Var} {xs : List Var} {C : Finset Label} (hau : a ≠ u)
    (hxu : u ∉ xs) :
    ConservativeExt [⟨a, xs, C⟩] u [⟨u, xs, (∅ : Finset Label)⟩, ⟨a, [u], C⟩] :=
  rule4 hau hxu

/-- **The vocabulary restriction in `Cut.cut_preserves_meaning` cannot be dropped.**  That
theorem's entailment clause is stated for constraints over the INPUT vocabulary, and it has
to be: a single branch-(c) step entails `z <- x++` for its own minted `z`, and the premises
do not -- the all-empty assignment with `z := {9}` models them and refutes it.  So "the cut
loses nothing" is a statement about the user's variables; about minted ones the cut and the
uncut solver genuinely disagree. -/
theorem vocabulary_restriction_necessary :
    ∃ (G G' : System) (c : Constraint), CseStep G G' ∧ SEntails G' c ∧ ¬ SEntails G c := by
  obtain ⟨z, hz⟩ := exists_fresh (allVars seed)
  have hm₁ : seed₁ ∈ seed := Finset.mem_insert_self _ _
  have hm₂ : seed₂ ∈ seed := Finset.mem_insert_of_mem (Finset.mem_singleton_self _)
  refine ⟨seed, cseResult seed seed₁ seed₂ z, mk z (shared seed₁ seed₂) ∅,
    CseStep.intro ⟨hm₁, hm₂, seed_lhs_ne, seed_guard, hz⟩,
    fun rho hm => hm _ (Finset.mem_insert_self _ _), ?_⟩
  intro hent
  have hempty : SModels (fun _ => (∅ : Row)) seed := by
    intro c hc
    simp only [seed, Finset.mem_insert, Finset.mem_singleton] at hc
    rcases hc with rfl | rfl
    · change Sat (fun _ => (∅ : Row)) (mk 0 {2, 3, 4} ∅)
      rw [sat_mk_iff]
      refine ⟨?_, by simp, by simp⟩
      ext l
      simp
    · change Sat (fun _ => (∅ : Row)) (mk 1 {2, 3, 5} ∅)
      rw [sat_mk_iff]
      refine ⟨?_, by simp, by simp⟩
      ext l
      simp
  have hm := sModels_setVar hz ({9} : Row) hempty
  have hsat := hent _ hm
  have hz9 := (sat_mk_iff _ z (shared seed₁ seed₂) ∅).mp hsat
  rw [setVar_self, Finset.empty_union] at hz9
  have hb : (shared seed₁ seed₂).biUnion (setVar (fun _ => (∅ : Row)) z {9}) = ∅ := by
    ext l
    simp only [Finset.mem_biUnion, Finset.notMem_empty, iff_false, not_exists]
    intro v
    rintro ⟨hv, hl⟩
    have hvne : v ≠ z := fun h =>
      hz (h ▸ vset_subset_allVars hm₁ (shared_subset_left seed₁ seed₂ hv))
    rw [setVar_of_ne _ _ hvne] at hl
    simp at hl
  rw [hb] at hz9
  simp at hz9

/-- **The precise difference in strength**, as one statement: model-set equality for the
clean calculus and for the cut's kept branches, one direction only for a retained minting
step, and a counterexample to the other. -/
theorem preservation_strength :
    (∀ s s' : State, Step s s' → ∀ rho, Models rho s.toSystem ↔ Models rho s'.toSystem) ∧
    (∀ G G' : System, CutStep G G' → ∀ rho, SModels rho G ↔ SModels rho G') ∧
    (∀ G G' : System, ResStep G G' → ∀ rho, SModels rho G' → SModels rho G) ∧
    (∃ (G G' : System) (rho : Assign), ResStep G G' ∧ SModels rho G ∧ ¬ SModels rho G') :=
  ⟨fun _ _ h rho => h.preserves rho, fun _ _ h rho => h.models_iff rho,
   fun _ _ h _ hm => resStep_models_downward h hm, res_not_model_preserving⟩


/-! ## 3. Confluence: the cut inherits the failure

`Canonical.CriticalPair` refutes local confluence for the clean calculus: on

    G = [ a <- (a, b) ,  b <- ((|{7}|)) ]

`occurs` gives `[b <- ((||)), b <- ((|{7}|))]` and `absorb` gives
`[a <- (a, (|{7}|)), b <- ((|{7}|))]`, two DISTINCT normal forms.

Both rules are ones the cut leaves alone, so the expected answer is that the cut inherits
the failure.  Expected is not proved: for the cut, "normal form" is a stronger claim,
because five generative rules must also be blocked.  `FullCutStep` is the clean calculus
plus all of them, and `cutNormalForm_of` isolates what has to be checked. -/

/-- The cut's one-step relation on states: `Canonical`'s six rules, plus every generative
rule the cut retains.  Branch (c) is the only thing absent. -/
inductive FullCutStep : State → State → Prop where
  /-- any rule of the fully non-generative calculus -/
  | canon {s s' : State} (h : Step s s') : FullCutStep s s'
  /-- common subexpression, branch (a) REUSE: the shared block already has a name -/
  | cseReuse {sv : List (Var × Var)} {cs : List Constraint} {c₁ c₂ : Constraint} {z : Var}
      (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁.lhs ≠ c₂.lhs)
      (hbig : 2 ≤ (shared c₁ c₂).card)
      (hz : ∃ d ∈ cs, d.lhs = z ∧ vset d = shared c₁ c₂ ∧ d.conc = ∅) :
      FullCutStep ⟨sv, cs⟩
        ⟨sv, reduce c₁ (shared c₁ c₂) z :: reduce c₂ (shared c₁ c₂) z :: cs⟩
  /-- common subexpression, branch (b) FOLD: the first premise IS the shared block -/
  | cseFold {sv : List (Var × Var)} {cs : List Constraint} {c₁ c₂ : Constraint}
      (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (hne : c₁.lhs ≠ c₂.lhs)
      (hbig : 2 ≤ (shared c₁ c₂).card) (hv : vset c₁ = shared c₁ c₂) (hk : c₁.conc = ∅) :
      FullCutStep ⟨sv, cs⟩ ⟨sv, reduce c₂ (shared c₁ c₂) c₁.lhs :: cs⟩
  /-- `splitConcrete`, minting branch -- RETAINED by the cut -/
  | splitMint {sv : List (Var × Var)} {cs : List Constraint} {c : Constraint} {u : Var}
      (hc : c ∈ cs) (hk : c.conc ≠ ∅) (hbig : 2 ≤ (vset c).card) (hu : u ∉ varsOf cs) :
      FullCutStep ⟨sv, cs⟩ ⟨sv, mk u (vset c) ∅ :: mk c.lhs {u} c.conc :: cs⟩
  /-- `splitConcrete`, reuse branch -- RETAINED by the cut -/
  | splitReuse {sv : List (Var × Var)} {cs : List Constraint} {c : Constraint} {u : Var}
      (hc : c ∈ cs) (hk : c.conc ≠ ∅) (hbig : 2 ≤ (vset c).card)
      (hu : ∃ d ∈ cs, d.lhs = u ∧ vset d = vset c ∧ d.conc = ∅) :
      FullCutStep ⟨sv, cs⟩ ⟨sv, mk c.lhs {u} c.conc :: cs⟩
  /-- `resolution` -- RETAINED by the cut, and it always mints -/
  | resMint {sv : List (Var × Var)} {cs : List Constraint} {a x y : Var}
      {C₁ C₂ : Finset Label} {z : Var}
      (h₁ : mk a {x} C₁ ∈ cs) (h₂ : mk a {y} C₂ ∈ cs)
      (ht : C₁ \ C₂ ≠ ∅) (hb : C₂ \ C₁ ≠ ∅) (hz : z ∉ varsOf cs) :
      FullCutStep ⟨sv, cs⟩
        ⟨sv, mk a {z} (C₁ ∪ C₂) :: mk x {z} (C₂ \ C₁) :: mk y {z} (C₁ \ C₂) :: cs⟩

/-- A state from which no rule of the cut applies. -/
def FullCutNormalForm (s : State) : Prop := ∀ t, ¬ FullCutStep s t

/-- Multi-step reduction for the cut. -/
inductive FullCutSteps : State → State → Prop where
  | refl (s : State) : FullCutSteps s s
  | tail {s t u : State} : FullCutSteps s t → FullCutStep t u → FullCutSteps s u

theorem FullCutSteps.eq_of_normalForm {s t : State} (hn : FullCutNormalForm s)
    (h : FullCutSteps s t) : t = s := by
  induction h with
  | refl => rfl
  | tail _ hst ih => exact absurd (ih ▸ hst) (hn _)

/-- Every constraint of the shape a `resolution` premise must have carries exactly one
right-hand variable. -/
theorem card_vset_res_premise {a x : Var} {C : Finset Label} :
    (vset (mk a {x} C)).card = 1 := by simp

/-- **A sufficient criterion for a cut normal form.**  If the state is a normal form for
the clean calculus, no constraint carries two or more right-hand variables, and no two
`resolution` premises have crossing concrete parts, then no rule of the cut applies.  The
first hypothesis kills `Canonical`'s six rules, the second kills all four
common-subexpression and split branches at once (each needs a block of size at least two),
and the third kills `resolution`. -/
theorem fullCutNormalForm_of {sv : List (Var × Var)} {cs : List Constraint}
    (hcanon : NormalForm ⟨sv, cs⟩)
    (hsmall : ∀ c ∈ cs, (vset c).card ≤ 1)
    (hres : ∀ (a x y : Var) (C₁ C₂ : Finset Label),
      mk a {x} C₁ ∈ cs → mk a {y} C₂ ∈ cs → C₁ \ C₂ = ∅ ∨ C₂ \ C₁ = ∅) :
    FullCutNormalForm ⟨sv, cs⟩ := by
  intro t ht
  cases ht with
  | canon h => exact hcanon _ h
  | @cseReuse _ _ c₁ c₂ z h₁ h₂ hne hbig hz =>
    have hle : (shared c₁ c₂).card ≤ (vset c₁).card :=
      Finset.card_le_card (shared_subset_left c₁ c₂)
    have := hsmall c₁ h₁
    omega
  | @cseFold _ _ c₁ c₂ h₁ h₂ hne hbig hv hk =>
    have hle : (shared c₁ c₂).card ≤ (vset c₁).card :=
      Finset.card_le_card (shared_subset_left c₁ c₂)
    have := hsmall c₁ h₁
    omega
  | @splitMint _ _ c u hc hk hbig hu =>
    have := hsmall c hc
    omega
  | @splitReuse _ _ c u hc hk hbig hu =>
    have := hsmall c hc
    omega
  | @resMint _ _ a x y C₁ C₂ z h₁ h₂ ht hb hz =>
    rcases hres a x y C₁ C₂ h₁ h₂ with h | h
    · exact ht h
    · exact hb h

open CriticalPair in
theorem full_cut_step_S1 : FullCutStep S S1 := FullCutStep.canon step_S1

open CriticalPair in
theorem full_cut_step_S2 : FullCutStep S S2 := FullCutStep.canon step_S2

open CriticalPair in
/-- The `occurs` result is a normal form for the WHOLE cut rule set: every constraint in it
has an empty right-hand side, so all five retained generative rules are blocked. -/
theorem full_cut_normal_S1 : FullCutNormalForm S1 := by
  refine fullCutNormalForm_of normal_S1 ?_ ?_
  · intro c hc
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl <;> simp [vset, cB]
  · intro a x y C₁ C₂ h₁ h₂
    exfalso
    have hone : (vset (mk a {x} C₁)).card = 1 := card_vset_res_premise
    simp only [List.mem_cons, List.not_mem_nil, or_false] at h₁
    rcases h₁ with h | h <;> (rw [h] at hone; simp [vset, cB] at hone)

open CriticalPair in
/-- The `absorb` result is a normal form for the whole cut rule set too.  Here the block is
tighter: `a <- (a, (|{7}|))` DOES have the shape of a `resolution` premise, but the only
other constraint has a different left-hand side, so the rule can pair it only with itself
-- and then `tops` is empty. -/
theorem full_cut_normal_S2 : FullCutNormalForm S2 := by
  refine fullCutNormalForm_of normal_S2 ?_ ?_
  · intro c hc
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with rfl | rfl <;> simp [vset, cB]
  · intro a x y C₁ C₂ h₁ h₂
    have hone₁ : (vset (mk a {x} C₁)).card = 1 := card_vset_res_premise
    have hone₂ : (vset (mk a {y} C₂)).card = 1 := card_vset_res_premise
    simp only [List.mem_cons, List.not_mem_nil, or_false] at h₁ h₂
    have e₁ : C₁ = ({7} : Finset Label) := by
      rcases h₁ with h | h
      · exact congrArg Constraint.conc h
      · rw [h] at hone₁; simp [vset, cB] at hone₁
    have e₂ : C₂ = ({7} : Finset Label) := by
      rcases h₂ with h | h
      · exact congrArg Constraint.conc h
      · rw [h] at hone₂; simp [vset, cB] at hone₂
    left
    rw [e₁, e₂]
    simp

open CriticalPair in
/-- **The cut inherits the failure of local confluence.**  `S` steps to two DISTINCT
states, each a normal form for the ENTIRE cut rule set.  Deleting branch (c) does not touch
the ambiguity, because the ambiguity is between two rules the cut leaves alone. -/
theorem full_cut_not_locally_confluent :
    FullCutStep S S1 ∧ FullCutStep S S2 ∧ S1 ≠ S2 ∧
      FullCutNormalForm S1 ∧ FullCutNormalForm S2 :=
  ⟨full_cut_step_S1, full_cut_step_S2, S1_ne_S2, full_cut_normal_S1, full_cut_normal_S2⟩

open CriticalPair in
/-- ... hence the two results have no common reduct under the cut either: normal forms are
not unique for the cut, as they are not for the clean calculus. -/
theorem full_cut_not_joinable : ¬ ∃ t, FullCutSteps S1 t ∧ FullCutSteps S2 t := by
  rintro ⟨t, h1, h2⟩
  exact S1_ne_S2 ((h1.eq_of_normalForm full_cut_normal_S1).symm.trans
    (h2.eq_of_normalForm full_cut_normal_S2))

/-! ## 4. Decision procedure: the cut inherits that failure too -/

open CriticalPair in
/-- **The cut inherits `Canonical.CriticalPair.normal_form_can_be_unsat`.**  `S1` says
`b = ∅` and `b = {7}` at once; it is unsatisfiable, and no rule of the cut -- generative or
not -- detects the contradiction.  Neither proposal is a decision procedure, and neither
is closer to being one: deciding satisfiability comes from `Fragment.lean`, not from
adding or removing a generative rule. -/
theorem full_cut_normal_form_can_be_unsat :
    FullCutNormalForm S1 ∧ ¬ ∃ rho, Models rho S1.toSystem :=
  ⟨full_cut_normal_S1, both_branches_unsat.1⟩


/-! ## 5. The bottom line

Read the table as: what is PROVED, and where.  "clean calculus" is `Canonical.lean`; "the
cut" is `Cut.lean` together with this file.  A row marked NO means the negative is PROVED,
not that the positive is merely missing; the one exception is row 1, where what is proved
is rows 1a-1c, i.e. no measure exists and chains of every length do.

| # | property | clean calculus | THE CUT |
| - | --- | --- | --- |
| 1 | terminates | **YES** | **NO** (see 1a-1c) |
| 1a | ... under `Canonical.Meas` | descends | *increases* |
| 1b | ... under any measure | has one | none exists |
| 1c | ... is the bad input at least unsat? | -- | no, it has a model |
| 1d | ... kept CSE branches alone | (n/a) | **YES** |
| 1e | ... `splitConcrete` alone | (n/a) | **YES** |
| 1f | ... `resolution` alone | (n/a) | **NO** |
| 2 | model sets preserved, every rule | **YES** | **NO** |
| 2a | ... on the kept CSE branches | (n/a) | **YES** |
| 2b | ... on the retained minting rules | (n/a) | **NO**, only conservative ext |
| 2c | loses no consequence vs. uncut | (n/a) | **YES**, over input vocabulary |
| 2d | ... may that restriction drop? | (n/a) | **NO** |
| 3 | confluent | **NO** | **NO**, inherited |
| 4 | decides satisfiability | **NO** | **NO**, inherited |

Row by row, the theorems:

* 1 `Step.decreasing`, `no_infinite_descent` | `Cut.cut_does_not_terminate`
* 1a `Step.decreasing` | `resStep_canonical_measure_increases`, `..._fails`
* 1b (`Meas` is one) | `Cut.cut_no_decreasing_measure`
* 1c -- | `resSeed_satisfiable` together with `Cut.resSeed_diverges`
* 1d -- | `Cut.cut_branches_terminate`, `Cut.CutChain.length_le`
* 1e -- | `Cut.split_terminates`
* 1f -- | `Cut.res_no_decreasing_measure`
* 2 `Step.preserves` | `res_not_model_preserving`
* 2a -- | `Cut.CutStep.models_iff`
* 2b -- | `res_conservative`, `split_conservative` (from `Rules.rule6`, `rule4`)
* 2c -- | `Cut.cut_preserves_meaning`
* 2d -- | `vocabulary_restriction_necessary`
* 3 `not_locally_confluent`, `not_joinable` | `full_cut_not_locally_confluent`,
  `full_cut_not_joinable`
* 4 `normal_form_can_be_unsat` | `full_cut_normal_form_can_be_unsat`

### The three buckets the question asks for

**(i) Proved for BOTH.**  Meaning preservation -- once rows 2 and 2b are kept apart, since
they are different statements.  The failure of confluence, and the failure to decide
satisfiability: the cut inherits both of the clean calculus's negative results unchanged,
and inheriting them is a theorem here, not an observation, because a normal form for the
cut has to survive five further rules.

**(ii) Proved for the CLEAN CALCULUS ONLY.**  **Termination.**  That is the whole
difference, and it is the property the exercise was about.  Also model-set-equality
meaning preservation for *every* rule: the cut has it on the branches it keeps and provably
lacks it on the rules it retains.

**(iii) Proved for NEITHER.**  The POSITIVE forms of rows 3 and 4: confluence, uniqueness
of normal forms, and decidability of satisfiability.  Both calculi refute them rather than
establish them, which is why the same items appear in bucket (i) as shared *failures*.
Neither proposal is nearer to them than the other, and nothing about the generative rules
is what stands in the way -- `Canonical` §11 and `Fragment.lean` locate the obstruction and
the repair respectively.

### Verdict

The five-line cut is a real improvement and a principled one LOCALLY.  The branch it
deletes is exactly the one with no decreasing measure (`Divergence.no_decreasing_measure`);
the branches it keeps are non-generative (`Cut.CutStep.allVars_eq`), exactly
meaning-preserving (`Cut.CutStep.models_iff`), and terminating
(`Cut.cut_branches_terminate`).  Nothing about that is accidental, and the cut's risk is
one-sided: it can accept an ill-typed program, never reject a well-typed one
(`Cut.cut_never_wrongly_refutes`, `Cut.cut_risk_is_one_sided`).

It is not a principled CALCULUS.  It does not deliver termination and cannot, because the
`GenRules` flag that turns `cseMints` off leaves `splitMints` and `resolves` on, and
`resolution` mints unconditionally.  The clean calculus's finiteness argument does not
merely fail to transfer: its measure runs backwards on the very first retained minting step
(row 1a).  Whether the cut terminates on real workloads is an empirical question -- measured,
`resolution` and `splitConcrete` fire zero times in a 129-module boot -- and an empirical
answer is not a termination theorem.  A termination theorem for Ermine's row solver requires
cutting all three minting sites, which is `Canonical`'s rule set.

So: the cut is a convenient object with one principled component.  The clean calculus is the
principled object.  What the clean calculus proves and the cut does not is exactly one
thing, and it is the thing the whole exercise is about.

### What this comparison does NOT settle

* Whether the cut changes what Ermine INFERS.  Row 2c is about entailment over the input
  vocabulary; Ermine's residual partitions become part of an inferred type, and the 23
  measured splices of branch-(c) output into committed output are syntactic changes no
  theorem here models.
* Whether the cut terminates on the systems Ermine's front end actually emits.  `Cut.resSeed`
  is a legal and satisfiable system; whether the front end can emit it is empirical.
* Whether §3's non-confluence survives a purely ADDITIVE reading of the non-generative
  rules.  It is stated for the replacing reading, which is `Canonical`'s; `occurs` and
  `absorb` destroy each other's applicability only because they erase, and read additively
  this particular pair would join.  No additive form of the six rules is defined here, so
  the additive confluence question is open, not answered in either direction.
* Interleaving.  `Cut.lean` analyses (a)/(b)-chains, split-chains and resolution-chains
  separately; `FullCutStep` puts every rule in one relation but is used here only for
  normal forms, where interleaving cannot arise.
-/

/-- **The comparison, as one theorem.**  In order: termination for the clean calculus, for
the cut's kept branches, and its failure for the cut rule set (on satisfiable input, with
the clean calculus's own measure running backwards); model-set preservation for the clean
calculus, for the kept branches, and its refutation for a retained minting rule; the
inherited failure of confluence; the inherited failure to decide satisfiability. -/
theorem bottom_line :
    (∀ f : ℕ → State, (∀ i, Step (f i) (f (i + 1))) → False) ∧
    (∀ G₀ : System, ∃ N : ℕ, ∀ (n : ℕ) (G : System), CutChain n G₀ G → n ≤ N) ∧
    (¬ ∃ μ : System → ℕ, ∀ G G', CutRule G G' → μ G' < μ G) ∧
    (∃ rho, SModels rho resSeed) ∧
    (∀ G G' : System, ResStep G G' → LexLt (Meas G.toList) (Meas G'.toList)) ∧
    (∀ s s' : State, Step s s' → ∀ rho, Models rho s.toSystem ↔ Models rho s'.toSystem) ∧
    (∀ G G' : System, CutStep G G' → ∀ rho, SModels rho G ↔ SModels rho G') ∧
    (∃ (G G' : System) (rho : Assign), ResStep G G' ∧ SModels rho G ∧ ¬ SModels rho G') ∧
    (FullCutStep CriticalPair.S CriticalPair.S1 ∧
      FullCutStep CriticalPair.S CriticalPair.S2 ∧
      CriticalPair.S1 ≠ CriticalPair.S2 ∧ FullCutNormalForm CriticalPair.S1 ∧
      FullCutNormalForm CriticalPair.S2) ∧
    (NormalForm CriticalPair.S1 ∧ FullCutNormalForm CriticalPair.S1 ∧
      ¬ ∃ rho, Models rho CriticalPair.S1.toSystem) :=
  ⟨no_infinite_descent, cut_branches_terminate, cut_no_decreasing_measure,
   resSeed_satisfiable, fun _ _ h => resStep_canonical_measure_increases h,
   fun _ _ h rho => h.preserves rho, fun _ _ h rho => h.models_iff rho,
   res_not_model_preserving, full_cut_not_locally_confluent,
   ⟨CriticalPair.normal_S1, full_cut_normal_S1, CriticalPair.both_branches_unsat.1⟩⟩

end Compare
end Rowpartition



