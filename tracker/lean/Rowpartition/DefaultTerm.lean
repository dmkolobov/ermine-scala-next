/-
# DefaultTerm -- does the SHIPPED rule set terminate on every SATISFIABLE input?

`DefaultDiverge.lean` defines the shipped rule set as a step relation, `DefaultStep`
(`NonGenStep` + `splitConcrete`'s mint + guarded `resolution`), and shows it diverges on an
UNSATISFIABLE input (`CRule.W`).  The complementary question is open: from a SATISFIABLE
input, is every productive run bounded?  This file states it (`TerminatesOnSat`) and proves
the structural lemmas the natural argument needs, stopping exactly at the step nothing
proves.

## Two layers

The question is about the ADDITIVE rule set: `DefaultStep` only inserts conclusions.  The
real `incorporateAll` loop also deletes and renames (`Saturate.SatStep`: `makeEmpty`,
`makeConcrete` -- absorb and DELETE definitions --, `rename`/`unify`, `dedup`, `weaken`),
and deleting a guard's witness can re-enable a mint (`NameLoss.orderB_remint_enabled`), so
the real loop is NOT a sub-relation of `DefaultSteps`.  Nothing here transfers to that
layer; `Constraints.scala`'s `keepDefs` (2026-09-02) is a repair on that layer, not this
one.

## What is proved

* §1-2  `DefaultRun n G₀ G`: productive runs, mirroring `ResGuardTerm.GRun`; `TerminatesOnSat`.
* §3    No non-generative rule touches the vocabulary (`NonGenStep.allVars_eq`); each mint
        adds exactly one fresh variable and the guarded reuse none
        (`DefaultStep.allVars_cases`); no rule invents a label (`DefaultStep.concSub`).
* §4-5  `forms V L`, the finitely many `mk`-shaped constraints over a vocabulary and label
        set.  A constraint is NOT determined by `(lhs, vset, conc)` -- `vars` is a list --
        but everything a rule EMITS is `mk`-shaped (`DefaultStep.new_canonical`), so no
        canonicity assumption on the input is needed: `DefaultRun.subset_forms`,
        `DefaultRun.length_le_forms` (a run is no longer than the number of shapes over its
        FINAL vocabulary), and hence `unbounded_vocab_of_unbounded_run`: an unbounded run
        has an unbounded vocabulary.  Sharper: `terminatesOnSat_iff_vocabBounded` -- the
        question IS whether the vocabulary stays bounded.
* §6    The model extends along every step and every run, forced at the minted variable
        (`DefaultStep.extend`, `DefaultRun.extend`); the split child's row is strictly
        smaller than its parent's (`split_rank_lt`), as the resolution child's already was
        (`ResGuardTerm.mint_rank_lt`, restated as `res_rank_lt`).
* §7    The parent relation `MintParent G G' p c`; `mintParent_rank_lt` (rank measured in
        the extended model); rows shrink down the relation (`mintParent_row_subset`), so
        every row along a run sits inside an input row (`DefaultRun.extend_row_subset`,
        `DefaultRun.rank_le`) -- the bounded-depth half of a König argument.
* §8    `CountRun P n m`: runs with the steps satisfying `P` counted.  The mints of a run
        are exactly its vocabulary growth (`CountRun.mints_eq_allVars_growth`,
        `unbounded_mints_of_unbounded_run`, `terminatesOnSat_iff_mintsBounded`).
        Resolution mints at a fixed parent number at most `2 ^ |L|`
        (`CountRun.res_branching_le`, `resBranchingBounded`).  Split mints at a fixed
        parent are injective into the named groups of that parent in the FINAL system
        (`CountRun.split_branching_le`) -- and that is all.

## What is not proved

`TerminatesOnSat` itself, in either direction.  §9 states the gap and names the missing
hypothesis (`SplitBranchingBounded`): a bound, from the input, on the number of distinct
groups a variable can acquire along a run would close the question through König's lemma
(`SplitBranchingBounded → TerminatesOnSat`, not formalised here); nothing bounds it, because
substitution, cancellation and CSE reuse build new groups out of names minted elsewhere,
and empty-row variables may recur inside groups.  The search for a satisfiable input that
exploits this is `tracker/tools/rowclosure.py` (the explorer's task; results to be recorded
by the orchestrator).
-/
import Rowpartition.DefaultDiverge
import Rowpartition.ResGuardTerm

namespace Rowpartition

/-! ## 1. Productive runs of the shipped rule set

`DefaultSteps` (in `DefaultDiverge`) counts steps; a "run" here is a chain of shipped steps
each of which really enlarges the system, exactly as `ResGuardTerm.GRun` does for the
guarded rule alone.  Without the side condition a chain can idle forever re-deriving what
it already has; every implementation deduplicates, so that is not divergence. -/

/-- A productive run of the shipped rule set: `n` steps of `DefaultStep`, each adding at
least one constraint. -/
inductive DefaultRun : ℕ → System → System → Prop
  | refl (G : System) : DefaultRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      DefaultRun n G₀ G → DefaultStep G G' → G ⊂ G' → DefaultRun (n + 1) G₀ G'

/-- A run only adds constraints. -/
theorem DefaultRun.subset {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) : G₀ ⊆ G := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep _ ih => exact ih.trans hstep.subset

/-- A run of length `n` has added at least `n` constraints. -/
theorem DefaultRun.card_ge {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    G₀.card + n ≤ G.card := by
  induction h with
  | refl => omega
  | @tail n G₀ G G' _ _ hss ih =>
    have := Finset.card_lt_card hss
    omega

/-- Every productive run is a chain of shipped steps. -/
theorem DefaultRun.toDefaultSteps {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    DefaultSteps n G₀ G := by
  induction h with
  | refl G => exact DefaultSteps.refl G
  | tail _ hstep _ ih => exact DefaultSteps.tail ih hstep

/-- A run is equisatisfiable with its input. -/
theorem DefaultRun.satisfiable_iff {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    (∃ rho, SModels rho G₀) ↔ (∃ rho, SModels rho G) :=
  h.toDefaultSteps.satisfiable_iff

/-- Every productive run of the guarded rule alone is a productive run of the shipped
rule set. -/
theorem DefaultRun.of_gRun {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) : DefaultRun n G₀ G := by
  induction h with
  | refl G => exact DefaultRun.refl G
  | tail _ hstep hss ih => exact DefaultRun.tail ih (DefaultStep.gres hstep) hss

theorem DefaultRun.trans {m n : ℕ} {G G' G'' : System} (h₁ : DefaultRun m G G')
    (h₂ : DefaultRun n G' G'') : DefaultRun (m + n) G G'' := by
  induction h₂ with
  | refl => exact h₁
  | tail _ hstep hss ih => exact DefaultRun.tail (ih h₁) hstep hss

/-! ## 2. The question -/

/-- **The question.**  From every SATISFIABLE input, is the length of every productive run
of the shipped rule set bounded?  This is the additive rule set `DefaultStep`
(`NonGenStep` + `splitConcrete`'s mint + guarded `resolution`); the real `incorporateAll`
loop also deletes and renames (`Saturate.SatStep`: `makeEmpty`, `makeConcrete`,
`rename`/`unify`, `dedup`, `weaken`), and that is a separate layer -- deletion of a guard's
witness can re-enable a mint (`NameLoss.orderB_remint_enabled`), so the real loop is not a
sub-relation of `DefaultSteps`, and nothing about it follows from an answer here. -/
def TerminatesOnSat : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), DefaultRun n G₀ G → n ≤ N

/-! ## 3. Vocabulary and labels

Every rule other than the two mints leaves the vocabulary unchanged, and no rule invents a
label. -/

/-! ### 3.1 The non-generative rules do not touch the vocabulary -/

theorem SplitReuseStep.allVars_eq {G G' : System} (h : SplitReuseStep G G') :
    allVars G' = allVars G := by
  cases h with
  | @intro c u happ =>
    refine allVars_insert_eq_of_subset ?_
    intro v hv
    simp only [lhs_mk, vset_mk, Finset.mem_insert, Finset.mem_singleton] at hv
    rcases hv with rfl | rfl
    · exact lhs_mem_allVars happ.mem
    · exact happ.names.mem_allVars

theorem CancelStep.allVars_eq {G G' : System} (h : CancelStep G G') :
    allVars G' = allVars G := by
  cases h with
  | @intro c d z happ =>
    refine allVars_insert_eq_of_subset ?_
    intro v hv
    simp only [lhs_mk, vset_mk, Finset.mem_insert] at hv
    rcases hv with rfl | hv
    · have hz : v ∈ vset c \ vset d := by
        rw [happ.lone]; exact Finset.mem_singleton_self _
      exact vset_subset_allVars happ.mem₁ (Finset.mem_sdiff.mp hz).1
    · exact vset_subset_allVars happ.mem₂ (Finset.mem_sdiff.mp hv).1

theorem SubstStep.allVars_eq {G G' : System} (h : SubstStep G G') :
    allVars G' = allVars G := by
  cases h with
  | @intro c d happ =>
    refine allVars_insert_eq_of_subset ?_
    intro v hv
    simp only [lhs_mk, vset_mk, Finset.mem_insert, Finset.mem_union, Finset.mem_erase] at hv
    rcases hv with rfl | ⟨-, hv⟩ | hv
    · exact lhs_mem_allVars happ.mem₁
    · exact vset_subset_allVars happ.mem₁ hv
    · exact vset_subset_allVars happ.mem₂ hv

theorem SelfSubstStep.allVars_eq {G G' : System} (h : SelfSubstStep G G') :
    allVars G' = allVars G := by
  cases h with
  | @intro c v happ =>
    refine allVars_insert_eq_of_subset ?_
    intro w hw
    simp only [lhs_mk, vset_mk, Finset.mem_insert, Finset.notMem_empty, or_false] at hw
    rw [hw]
    exact vset_subset_allVars happ.mem happ.mem_v

theorem CommonPartStep.allVars_eq {G G' : System} (h : CommonPartStep G G') :
    allVars G' = allVars G := by
  cases h with
  | @intro c d happ =>
    refine allVars_insert_eq_of_subset ?_
    intro v hv
    simp only [lhs_mk, vset_mk, Finset.mem_insert, Finset.mem_singleton] at hv
    rcases hv with rfl | rfl
    · exact lhs_mem_allVars happ.mem₁
    · exact lhs_mem_allVars happ.mem₂

/-- **No non-generative rule changes the vocabulary.** -/
theorem NonGenStep.allVars_eq {G G' : System} (h : NonGenStep G G') :
    allVars G' = allVars G := by
  cases h with
  | cse h => exact h.allVars_eq
  | split h => exact h.allVars_eq
  | cancel h => exact h.allVars_eq
  | subst h => exact h.allVars_eq
  | selfSubst h => exact h.allVars_eq
  | commonPart h => exact h.allVars_eq

/-! ### 3.2 The two mints add exactly one variable; the guarded reuse adds none -/

theorem allVars_splitResult {G : System} {c : Constraint} (hc : c ∈ G) (u : Var) :
    allVars (splitResult G c u) = insert u (allVars G) := by
  rw [splitResult, allVars_insert, allVars_insert]
  ext v
  simp only [lhs_mk, vset_mk, Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  constructor
  · rintro ((rfl | hv) | (rfl | rfl) | hv)
    · exact Or.inl rfl
    · exact Or.inr (vset_subset_allVars hc hv)
    · exact Or.inr (lhs_mem_allVars hc)
    · exact Or.inl rfl
    · exact Or.inr hv
  · rintro (rfl | hv)
    · exact Or.inl (Or.inl rfl)
    · exact Or.inr (Or.inr hv)

/-- **A split mint adds exactly one variable**, the fresh name. -/
theorem SplitStep.allVars_eq_insert {G G' : System} (h : SplitStep G G') :
    ∃ u, u ∉ allVars G ∧ allVars G' = insert u (allVars G) := by
  cases h with
  | @intro c u happ => exact ⟨u, happ.fresh, allVars_splitResult happ.mem u⟩

/-- The guarded rule's REUSE branch does not touch the vocabulary
(`ResGuardTerm.allVars_resReuseResult`, with the membership side conditions discharged). -/
theorem GResStep.reuse_allVars_eq {G : System} {v x y z : Var} {C D : Row}
    (hp : ResPair G v x y C D) (hr : mk v {z} (C ∪ D) ∈ G) :
    allVars (resReuseResult G x y C D z) = allVars G :=
  allVars_resReuseResult (mem_allVars hp.mem₁ (Or.inr (by simp)))
    (mem_allVars hp.mem₂ (Or.inr (by simp))) (mem_allVars hr (Or.inr (by simp)))

/-- The guarded rule's MINT branch adds exactly the fresh name
(`ResGuardTerm.allVars_resResult`, with the side conditions discharged). -/
theorem GResStep.mint_allVars_eq {G : System} {v x y : Var} {C D : Row}
    (hp : ResPair G v x y C D) (z : Var) :
    allVars (resResult G v x y C D z) = insert z (allVars G) :=
  allVars_resResult z (lhs_mem_allVars hp.mem₁) (mem_allVars hp.mem₁ (Or.inr (by simp)))
    (mem_allVars hp.mem₂ (Or.inr (by simp)))

/-- A guarded step either keeps the vocabulary or adds one fresh variable. -/
theorem GResStep.allVars_cases {G G' : System} (h : GResStep G G') :
    allVars G' = allVars G ∨ ∃ z, z ∉ allVars G ∧ allVars G' = insert z (allVars G) := by
  cases h with
  | @mint v x y C D z hp _ hz => exact Or.inr ⟨z, hz, GResStep.mint_allVars_eq hp z⟩
  | @reuse v x y C D z hp hr => exact Or.inl (GResStep.reuse_allVars_eq hp hr)

/-- **Every shipped step either keeps the vocabulary or adds exactly one fresh variable.** -/
theorem DefaultStep.allVars_cases {G G' : System} (h : DefaultStep G G') :
    allVars G' = allVars G ∨ ∃ z, z ∉ allVars G ∧ allVars G' = insert z (allVars G) := by
  cases h with
  | nongen h => exact Or.inl h.allVars_eq
  | mint h => exact Or.inr h.allVars_eq_insert
  | gres h => exact h.allVars_cases

theorem DefaultStep.allVars_card_le {G G' : System} (h : DefaultStep G G') :
    (allVars G').card ≤ (allVars G).card + 1 := by
  rcases h.allVars_cases with hV | ⟨z, hz, hV⟩
  · rw [hV]; exact Nat.le_succ _
  · rw [hV, Finset.card_insert_of_notMem hz]

/-- A run of `n` steps adds at most `n` variables. -/
theorem DefaultRun.allVars_card_le {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    (allVars G).card ≤ (allVars G₀).card + n := by
  induction h with
  | refl => omega
  | tail _ hstep _ ih =>
    have := hstep.allVars_card_le
    omega

/-! ### 3.3 No rule invents a label -/

theorem CutStep.concSub {L : Finset Label} {G G' : System} (h : CutStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @reuse c₁ c₂ z hp _ =>
    intro c hc
    simp only [reuseResult, Finset.mem_insert] at hc
    rcases hc with rfl | rfl | hc
    · rw [reduce_conc]; exact hcs _ hp.mem₁
    · rw [reduce_conc]; exact hcs _ hp.mem₂
    · exact hcs c hc
  | @fold c₁ c₂ hp _ _ =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc
    · rw [reduce_conc]; exact hcs _ hp.mem₂
    · exact hcs c hc

theorem SplitReuseStep.concSub {L : Finset Label} {G G' : System} (h : SplitReuseStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro c u happ =>
    intro d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · rw [conc_mk]; exact hcs c happ.mem
    · exact hcs d hd

theorem CancelStep.concSub {L : Finset Label} {G G' : System} (h : CancelStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro c d z happ =>
    intro e he
    rcases Finset.mem_insert.mp he with rfl | he
    · rw [conc_mk]; exact Finset.sdiff_subset.trans (hcs d happ.mem₂)
    · exact hcs e he

theorem SubstStep.concSub {L : Finset Label} {G G' : System} (h : SubstStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro c d happ =>
    intro e he
    rcases Finset.mem_insert.mp he with rfl | he
    · rw [conc_mk]; exact Finset.union_subset (hcs c happ.mem₁) (hcs d happ.mem₂)
    · exact hcs e he

theorem SelfSubstStep.concSub {L : Finset Label} {G G' : System} (h : SelfSubstStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro c v _ =>
    intro e he
    rcases Finset.mem_insert.mp he with rfl | he
    · rw [conc_mk]; exact Finset.empty_subset _
    · exact hcs e he

theorem CommonPartStep.concSub {L : Finset Label} {G G' : System} (h : CommonPartStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro c d _ =>
    intro e he
    rcases Finset.mem_insert.mp he with rfl | he
    · rw [conc_mk]; exact Finset.empty_subset _
    · exact hcs e he

theorem NonGenStep.concSub {L : Finset Label} {G G' : System} (h : NonGenStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | cse h => exact h.concSub hcs
  | split h => exact h.concSub hcs
  | cancel h => exact h.concSub hcs
  | subst h => exact h.concSub hcs
  | selfSubst h => exact h.concSub hcs
  | commonPart h => exact h.concSub hcs

theorem SplitStep.concSub {L : Finset Label} {G G' : System} (h : SplitStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @intro c u happ =>
    intro d hd
    simp only [splitResult, Finset.mem_insert] at hd
    rcases hd with rfl | rfl | hd
    · rw [conc_mk]; exact Finset.empty_subset _
    · rw [conc_mk]; exact hcs c happ.mem
    · exact hcs d hd

/-- **No shipped rule invents a label**: every concrete part a rule emits is a union or a
difference of concrete parts already present. -/
theorem DefaultStep.concSub {L : Finset Label} {G G' : System} (h : DefaultStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | nongen h => exact h.concSub hcs
  | mint h => exact h.concSub hcs
  | gres h => exact h.concSub hcs

/-- The label set of the input bounds the whole run. -/
theorem DefaultRun.concSub {L : Finset Label} {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hcs => hstep.concSub (ih hcs)

/-! ## 4. The finite space of constraints over a vocabulary

Over a vocabulary `V` and a label set `L` there are finitely many `mk`-shaped constraints.
`Constraint.vars` is a LIST, so a constraint is in general NOT determined by its
`(lhs, vset, conc)`: `⟨a, [x, x], k⟩` and `⟨a, [x], k⟩` have the same triple.  What every
rule EMITS, however, is `mk`-shaped (`DefaultStep.new_canonical`), so a run stays inside
the input plus the finitely many shapes over its own vocabulary, without any assumption on
the input's constraints. -/

/-- All `mk`-shaped constraints whose left-hand side and variables come from `V` and whose
concrete part is drawn from `L`.  Compare `Cut.normalForms`, which fixes the concrete parts
to a given finite set, and `ResGuardTerm.unaryForms`, which fixes the arity to one. -/
def forms (V : Finset Var) (L : Finset Label) : System :=
  (V ×ˢ V.powerset ×ˢ L.powerset).image (fun p => mk p.1 p.2.1 p.2.2)

/-- A constraint is CANONICAL if it is the `mk` of its own components: its variable list is
the sorted, duplicate-free listing of its variable set. -/
def IsCanonical (c : Constraint) : Prop := c = mk c.lhs (vset c) c.conc

/-- Every constraint of the system is canonical. -/
def Canonical (G : System) : Prop := ∀ c ∈ G, IsCanonical c

/-- Everything `mk` builds is canonical. -/
theorem isCanonical_mk (a : Var) (S : Finset Var) (k : Row) : IsCanonical (mk a S k) := by
  simp [IsCanonical]

/-- ...and not everything is: `⟨0, [0, 0], ∅⟩` has the components of `mk 0 {0} ∅` and is a
different constraint.  So `IsCanonical` is a genuine restriction, `mk c.lhs (vset c) c.conc = c`
is FALSE for arbitrary `c`, and the first conjunct of `mem_forms` cannot be dropped. -/
theorem exists_not_isCanonical : ∃ c : Constraint, ¬ IsCanonical c := by
  refine ⟨⟨0, [0, 0], ∅⟩, fun h => ?_⟩
  have hv := congrArg Constraint.vars h
  simp [mk, slist, vset] at hv

theorem mk_mem_forms {V : Finset Var} {L : Finset Label} {a : Var} {S : Finset Var} {k : Row}
    (ha : a ∈ V) (hS : S ⊆ V) (hk : k ⊆ L) : mk a S k ∈ forms V L :=
  Finset.mem_image.mpr ⟨(a, S, k), by
    simp only [Finset.mem_product, Finset.mem_powerset]
    exact ⟨ha, hS, hk⟩, rfl⟩

/-- **Membership in `forms` is exactly the shape condition, for canonical constraints.**
The canonicity conjunct is not an artefact: a non-canonical constraint with the right
components is never in `forms`, because `forms` contains only `mk`-shaped constraints. -/
theorem mem_forms {V : Finset Var} {L : Finset Label} {c : Constraint} :
    c ∈ forms V L ↔ IsCanonical c ∧ c.lhs ∈ V ∧ vset c ⊆ V ∧ c.conc ⊆ L := by
  constructor
  · intro h
    obtain ⟨⟨a, S, k⟩, hp, rfl⟩ := Finset.mem_image.mp h
    simp only [Finset.mem_product, Finset.mem_powerset] at hp
    refine ⟨isCanonical_mk a S k, ?_⟩
    simp only [lhs_mk, vset_mk, conc_mk]
    exact ⟨hp.1, hp.2.1, hp.2.2⟩
  · rintro ⟨hc, ha, hS, hk⟩
    have := mk_mem_forms ha hS hk
    rwa [← hc] at this

/-- There are at most `|V| · 2^|V| · 2^|L|` shapes. -/
theorem card_forms_le (V : Finset Var) (L : Finset Label) :
    (forms V L).card ≤ V.card * 2 ^ V.card * 2 ^ L.card := by
  refine le_trans Finset.card_image_le ?_
  rw [Finset.card_product, Finset.card_product, Finset.card_powerset, Finset.card_powerset]
  exact Nat.le_of_eq (Nat.mul_assoc _ _ _).symm

/-- A bigger vocabulary allows more shapes. -/
theorem forms_mono {V V' : Finset Var} (h : V ⊆ V') (L : Finset Label) :
    forms V L ⊆ forms V' L := by
  intro c hc
  rw [mem_forms] at hc ⊢
  exact ⟨hc.1, h hc.2.1, hc.2.2.1.trans h, hc.2.2.2⟩

/-- A canonical system with labels in `L` sits inside the shapes over its own vocabulary. -/
theorem subset_forms {L : Finset Label} {G : System} (hcan : Canonical G) (hcs : ConcSub L G) :
    G ⊆ forms (allVars G) L := by
  intro c hc
  rw [mem_forms]
  exact ⟨hcan c hc, lhs_mem_allVars hc, vset_subset_allVars hc, hcs c hc⟩

/-! ### 4.1 Everything a rule emits is canonical -/

/-- Every constraint of `G'` not in `G` is `mk`-shaped: the case split behind the two
statements below. -/
theorem DefaultStep.new_canonical {G G' : System} (h : DefaultStep G G') {c : Constraint}
    (hc : c ∈ G') : c ∈ G ∨ IsCanonical c := by
  cases h with
  | nongen h =>
    cases h with
    | cse h =>
      cases h with
      | @reuse c₁ c₂ z _ _ =>
        simp only [reuseResult, Finset.mem_insert] at hc
        rcases hc with rfl | rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
      | @fold c₁ c₂ _ _ _ =>
        rcases Finset.mem_insert.mp hc with rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
    | split h =>
      cases h with
      | intro _ =>
        rcases Finset.mem_insert.mp hc with rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
    | cancel h =>
      cases h with
      | intro _ =>
        rcases Finset.mem_insert.mp hc with rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
    | subst h =>
      cases h with
      | intro _ =>
        rcases Finset.mem_insert.mp hc with rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
    | selfSubst h =>
      cases h with
      | intro _ =>
        rcases Finset.mem_insert.mp hc with rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
    | commonPart h =>
      cases h with
      | intro _ =>
        rcases Finset.mem_insert.mp hc with rfl | hc
        · exact Or.inr (isCanonical_mk _ _ _)
        · exact Or.inl hc
  | mint h =>
    cases h with
    | intro _ =>
      simp only [splitResult, Finset.mem_insert] at hc
      rcases hc with rfl | rfl | hc
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inl hc
  | gres h =>
    cases h with
    | mint _ _ _ =>
      simp only [resResult, Finset.mem_insert] at hc
      rcases hc with rfl | rfl | rfl | hc
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inl hc
    | reuse _ _ =>
      simp only [resReuseResult, Finset.mem_insert] at hc
      rcases hc with rfl | rfl | hc
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inl hc

/-- Canonicity is preserved by every shipped step. -/
theorem DefaultStep.canonical {G G' : System} (h : DefaultStep G G') (hcan : Canonical G) :
    Canonical G' := fun c hc => (h.new_canonical hc).elim (hcan c) id

theorem DefaultRun.canonical {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    Canonical G₀ → Canonical G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hcan => hstep.canonical (ih hcan)

/-- **Every step adds only shapes over the successor's own vocabulary.** -/
theorem DefaultStep.new_forms {L : Finset Label} {G G' : System} (h : DefaultStep G G')
    (hcs : ConcSub L G) : G' ⊆ G ∪ forms (allVars G') L := by
  intro c hc
  rcases h.new_canonical hc with hG | hcan
  · exact Finset.mem_union_left _ hG
  · exact Finset.mem_union_right _ (mem_forms.mpr
      ⟨hcan, lhs_mem_allVars hc, vset_subset_allVars hc, h.concSub hcs c hc⟩)

/-- **A run stays inside the input plus the shapes over its own vocabulary.**  No
assumption on the input's constraints is needed: whatever shape they have, they are
carried along unchanged, and everything added is `mk`-shaped. -/
theorem DefaultRun.subset_forms {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : DefaultRun n G₀ G) : ConcSub L G₀ → G ⊆ G₀ ∪ forms (allVars G) L := by
  induction h with
  | refl G => exact fun _ => Finset.subset_union_left
  | @tail n G₀ G G' hrun hstep _ ih =>
    intro hcs
    have hmono : forms (allVars G) L ⊆ forms (allVars G') L :=
      forms_mono (allVars_mono hstep.subset) L
    have hnew : G' ⊆ G ∪ forms (allVars G') L := hstep.new_forms (hrun.concSub hcs)
    intro c hc
    rcases Finset.mem_union.mp (hnew hc) with h1 | h1
    · rcases Finset.mem_union.mp (ih hcs h1) with h2 | h2
      · exact Finset.mem_union_left _ h2
      · exact Finset.mem_union_right _ (hmono h2)
    · exact Finset.mem_union_right _ h1

/-! ## 5. A run is bounded by its final vocabulary

Over a fixed vocabulary there are finitely many shapes, and each productive step adds one.
So a run's length is bounded by the number of shapes over the vocabulary it ENDS with.  A
run that is not bounded therefore cannot keep its vocabulary bounded: it must mint, and
mint, and mint. -/

/-- **The length of a run is at most the number of shapes over its final vocabulary.** -/
theorem DefaultRun.length_le_forms {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : DefaultRun n G₀ G) (hcs : ConcSub L G₀) : n ≤ (forms (allVars G) L).card := by
  have h1 : G₀.card + n ≤ G.card := h.card_ge
  have h2 : G.card ≤ G₀.card + (forms (allVars G) L).card :=
    le_trans (Finset.card_le_card (h.subset_forms hcs)) (Finset.card_union_le _ _)
  omega

/-- The same, in closed form. -/
theorem DefaultRun.length_le {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : DefaultRun n G₀ G) (hcs : ConcSub L G₀) :
    n ≤ (allVars G).card * 2 ^ (allVars G).card * 2 ^ L.card :=
  (h.length_le_forms hcs).trans (card_forms_le _ _)

/-- **Mint-free runs are bounded by the input alone**: a run that ends with the vocabulary
it started with -- so one in which no mint fired (`DefaultStep.allVars_cases`) -- is no
longer than the number of shapes over the input's vocabulary. -/
theorem DefaultRun.length_le_of_allVars_eq {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : DefaultRun n G₀ G) (hcs : ConcSub L G₀) (hV : allVars G = allVars G₀) :
    n ≤ (forms (allVars G₀) L).card := by
  rw [← hV]; exact h.length_le_forms hcs

/-- The closed-form bound is monotone in the vocabulary size. -/
theorem formsBound_mono {a b : ℕ} (h : a ≤ b) (k : ℕ) :
    a * 2 ^ a * 2 ^ k ≤ b * 2 ^ b * 2 ^ k :=
  Nat.mul_le_mul (Nat.mul_le_mul h (Nat.pow_le_pow_right (Nat.succ_pos 1) h)) (Nat.le_refl _)

/-- A run longer than the bound for `M` variables ends with more than `M` variables. -/
theorem DefaultRun.allVars_card_gt {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : DefaultRun n G₀ G) (hcs : ConcSub L G₀) {M : ℕ}
    (hn : M * 2 ^ M * 2 ^ L.card < n) : M < (allVars G).card := by
  by_contra hlt
  have hle : (allVars G).card ≤ M := Nat.le_of_not_lt hlt
  have h1 := h.length_le hcs
  have h2 := formsBound_mono hle L.card
  omega

/-- **An unbounded run has an unbounded vocabulary.**  If runs from `G₀` of every length
exist, then runs from `G₀` ending with more than any given number of variables exist -- and
since every non-mint step keeps the vocabulary and every mint adds exactly one variable
(`DefaultStep.allVars_cases`; exactly, `CountRun.mints_eq_allVars_growth` in §8), that is:
with more than any given number of mints (`unbounded_mints_of_unbounded_run`, §8). -/
theorem unbounded_vocab_of_unbounded_run {L : Finset Label} {G₀ : System} (hcs : ConcSub L G₀)
    (hdiv : ∀ N, ∃ n G, DefaultRun n G₀ G ∧ N < n) :
    ∀ M, ∃ n G, DefaultRun n G₀ G ∧ M < (allVars G).card := by
  intro M
  obtain ⟨n, G, hrun, hn⟩ := hdiv (M * 2 ^ M * 2 ^ L.card)
  exact ⟨n, G, hrun, hrun.allVars_card_gt hcs hn⟩

/-! ### 5.1 The question is exactly a question about the vocabulary -/

/-- **The question, restated on the vocabulary**: from every satisfiable input, the number
of variables of every system a run reaches is bounded by the input. -/
def VocabBoundedOnSat : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ B : ℕ, ∀ (n : ℕ) (G : System), DefaultRun n G₀ G → (allVars G).card ≤ B

/-- **Termination is exactly a bounded vocabulary.**  A bounded run adds boundedly many
variables (`DefaultRun.allVars_card_le`); a bounded vocabulary bounds the run
(`DefaultRun.length_le`).  So `TerminatesOnSat` asks precisely whether the shipped rules can
mint without end from a satisfiable input -- nothing else can go on for ever. -/
theorem terminatesOnSat_iff_vocabBounded : TerminatesOnSat ↔ VocabBoundedOnSat := by
  constructor
  · intro h G₀ rho hm
    obtain ⟨N, hN⟩ := h G₀ rho hm
    exact ⟨(allVars G₀).card + N, fun n G hrun =>
      le_trans hrun.allVars_card_le (Nat.add_le_add_left (hN n G hrun) _)⟩
  · intro h G₀ rho hm
    obtain ⟨B, hB⟩ := h G₀ rho hm
    refine ⟨B * 2 ^ B * 2 ^ (labelsOf G₀).card, fun n G hrun => ?_⟩
    exact le_trans (hrun.length_le (labelsOf_concSub G₀)) (formsBound_mono (hB n G hrun) _)

/-! ## 6. The forced model extension

A model of the premises extends along every step, changing only the minted variable, whose
row is FORCED: a split child denotes the union of its group, a resolution child denotes
`rho v \ (C ∪ D)`. -/

/-- **A split mint extends every model**, by the forced value.  (`split_mint_conservativeExt`
states this with the extension existentially quantified; here it is the explicit
`setVar`.) -/
theorem split_extend {G : System} {c : Constraint} {u : Var} (happ : SplitApp G c u)
    {rho : Assign} (hm : SModels rho G) :
    SModels (setVar rho u ((vset c).biUnion rho)) (splitResult G c u) := by
  have hc := hm c happ.mem
  have hu : u ∉ vset c := fun hh => happ.fresh (mem_allVars happ.mem (Or.inr hh))
  have hul : u ≠ c.lhs := fun hh => happ.fresh (hh ▸ lhs_mem_allVars happ.mem)
  intro d hd
  simp only [splitResult, Finset.mem_insert] at hd
  rcases hd with rfl | rfl | hd
  · exact sat_name hc (Finset.Subset.refl _) hu
  · rw [← reduce_self]
    exact sat_reduce hc (Finset.Subset.refl _) hu hul
  · exact sModels_setVar happ.fresh _ hm d hd

/-- **The group of a split premise denotes a strictly smaller row than its left-hand
side**: the union of the group is `rho c.lhs \ c.conc`, and `c.conc` is a nonempty subset
of `rho c.lhs`. -/
theorem split_group_rank_lt {G : System} {c : Constraint} {u : Var} (happ : SplitApp G c u)
    {rho : Assign} (hm : SModels rho G) :
    ((vset c).biUnion rho).card < (rho c.lhs).card := by
  have hc := hm c happ.mem
  have heq := hc.eq_biUnion
  obtain ⟨l, hl⟩ := Finset.nonempty_iff_ne_empty.mpr happ.conc_ne
  have hlv : l ∈ rho c.lhs := by rw [heq]; exact Finset.mem_union_left _ hl
  have hlB : l ∉ (vset c).biUnion rho := by
    intro hB
    obtain ⟨v, hv, hlv'⟩ := Finset.mem_biUnion.mp hB
    exact Finset.disjoint_left.mp (hc.disjoint_conc' hv) hl hlv'
  have hsub : (vset c).biUnion rho ⊆ rho c.lhs := by
    rw [heq]; exact Finset.subset_union_right
  exact Finset.card_lt_card ((Finset.ssubset_iff_of_subset hsub).mpr ⟨l, hlv, hlB⟩)

/-- **The split child denotes a strictly smaller row than its parent**, in every model of
the successor: `c.lhs <- (u, c.conc)` forces `rho u = rho c.lhs \ c.conc` with `c.conc`
nonempty.  This is the split analogue of `ResGuardTerm.mint_rank_lt`. -/
theorem split_rank_lt {G : System} {c : Constraint} {u : Var} (happ : SplitApp G c u)
    {rho : Assign} (hm : SModels rho (splitResult G c u)) :
    (rho u).card < (rho c.lhs).card := by
  have h := hm _ (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
  rw [sat_lone_iff] at h
  obtain ⟨heq, hdis⟩ := h
  obtain ⟨l, hl⟩ := Finset.nonempty_iff_ne_empty.mpr happ.conc_ne
  have hlv : l ∈ rho c.lhs := by rw [heq]; exact Finset.mem_union_left _ hl
  have hlu : l ∉ rho u := Finset.disjoint_left.mp hdis hl
  have hsub : rho u ⊆ rho c.lhs := by rw [heq]; exact Finset.subset_union_right
  exact Finset.card_lt_card ((Finset.ssubset_iff_of_subset hsub).mpr ⟨l, hlv, hlu⟩)

/-- **The resolution child denotes a strictly smaller row than its parent**
(`ResGuardTerm.mint_rank_lt`, restated in the vocabulary of this file). -/
theorem res_rank_lt {G : System} {v x y z : Var} {C D : Row} (hp : ResPair G v x y C D)
    {rho : Assign} (hm : SModels rho (resResult G v x y C D z)) :
    (rho z).card < (rho v).card :=
  mint_rank_lt hp hm

/-- **Every shipped step extends every model**, changing the assignment only at the fresh
variable, if any: a non-generative step and a guarded reuse keep the assignment, a split
mint sets the child to the union of its group, a resolution mint sets it to the resolvent
(`ResGuard.mint_extend`). -/
theorem DefaultStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : DefaultStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | nongen h => exact ⟨rho, (h.models_iff rho).mp hm, fun _ _ => rfl⟩
  | mint h =>
    cases h with
    | @intro c u happ =>
      refine ⟨setVar rho u ((vset c).biUnion rho), split_extend happ hm, ?_⟩
      intro v hv
      exact setVar_of_ne rho _ (fun hh => happ.fresh (hh ▸ hv))
  | gres h =>
    cases h with
    | @mint v x y C D z hp _ hz => exact mint_extend hp hz hm
    | @reuse v x y C D z hp hr =>
      exact ⟨rho, (GResStep.reuse_models_iff hp hr rho).mpr hm, fun _ _ => rfl⟩

/-- **The model extends along a run**: a model of the input extends to a model of every
system the run reaches, agreeing with it on the input's vocabulary. -/
theorem DefaultRun.extend {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    ∀ rho₀ : Assign, SModels rho₀ G₀ →
      ∃ rho, SModels rho G ∧ ∀ v ∈ allVars G₀, rho v = rho₀ v := by
  induction h with
  | refl G => exact fun rho₀ hm => ⟨rho₀, hm, fun _ _ => rfl⟩
  | @tail n G₀ G G' hrun hstep _ ih =>
    intro rho₀ hm
    obtain ⟨rho, hmr, hag⟩ := ih rho₀ hm
    obtain ⟨rho', hm', hag'⟩ := hstep.extend hmr
    exact ⟨rho', hm', fun v hv => (hag' v (allVars_mono hrun.subset hv)).trans (hag v hv)⟩

/-! ## 7. The parent relation

A mint has a PARENT -- the variable whose row the child's row is carved out of -- and the
child's row is strictly smaller than the parent's in every model of the successor.  The
parent of a split child is the left-hand side of the split premise; the parent of a
resolution child is the variable both premises partition. -/

/-- The step `G → G'` is a resolution mint on `p` with fresh child `c`. -/
def ResMintAt (G G' : System) (p c : Var) : Prop :=
  ∃ x y C D, ResPair G p x y C D ∧ ¬ Resolved G p (C ∪ D) ∧ c ∉ allVars G ∧
    G' = resResult G p x y C D c

/-- The step `G → G'` is a split mint on a premise with left-hand side `p`, with fresh
child `c`. -/
def SplitMintAt (G G' : System) (p c : Var) : Prop :=
  ∃ d, SplitApp G d c ∧ d.lhs = p ∧ G' = splitResult G d c

/-- The step `G → G'` mints `c` with parent `p`. -/
def MintParent (G G' : System) (p c : Var) : Prop :=
  SplitMintAt G G' p c ∨ ResMintAt G G' p c

theorem SplitMintAt.defaultStep {G G' : System} {p c : Var} (h : SplitMintAt G G' p c) :
    DefaultStep G G' := by
  obtain ⟨d, happ, -, rfl⟩ := h
  exact DefaultStep.mint (SplitStep.intro happ)

theorem ResMintAt.defaultStep {G G' : System} {p c : Var} (h : ResMintAt G G' p c) :
    DefaultStep G G' := by
  obtain ⟨x, y, C, D, hp, hg, hc, rfl⟩ := h
  exact DefaultStep.gres (GResStep.mint hp hg hc)

theorem MintParent.defaultStep {G G' : System} {p c : Var} (h : MintParent G G' p c) :
    DefaultStep G G' :=
  h.elim SplitMintAt.defaultStep ResMintAt.defaultStep

/-- The child is fresh. -/
theorem MintParent.fresh {G G' : System} {p c : Var} (h : MintParent G G' p c) :
    c ∉ allVars G := by
  rcases h with ⟨d, happ, -, -⟩ | ⟨x, y, C, D, -, -, hc, -⟩
  · exact happ.fresh
  · exact hc

/-- The parent is an existing variable. -/
theorem MintParent.parent_mem {G G' : System} {p c : Var} (h : MintParent G G' p c) :
    p ∈ allVars G := by
  rcases h with ⟨d, happ, rfl, -⟩ | ⟨x, y, C, D, hp, -, -, -⟩
  · exact lhs_mem_allVars happ.mem
  · exact lhs_mem_allVars hp.mem₁

/-- A mint adds exactly its child to the vocabulary. -/
theorem MintParent.allVars_eq {G G' : System} {p c : Var} (h : MintParent G G' p c) :
    allVars G' = insert c (allVars G) := by
  rcases h with ⟨d, happ, -, rfl⟩ | ⟨x, y, C, D, hp, -, -, rfl⟩
  · exact allVars_splitResult happ.mem c
  · exact GResStep.mint_allVars_eq hp c

/-- **Every shipped step either keeps the vocabulary or is a mint with a parent.** -/
theorem DefaultStep.allVars_eq_or_mint {G G' : System} (h : DefaultStep G G') :
    allVars G' = allVars G ∨ ∃ p c, MintParent G G' p c := by
  cases h with
  | nongen h => exact Or.inl h.allVars_eq
  | mint h =>
    cases h with
    | @intro d u happ => exact Or.inr ⟨d.lhs, u, Or.inl ⟨d, happ, rfl, rfl⟩⟩
  | gres h =>
    cases h with
    | @mint v x y C D z hp hg hz => exact Or.inr ⟨v, z, Or.inr ⟨x, y, C, D, hp, hg, hz, rfl⟩⟩
    | @reuse v x y C D z hp hr => exact Or.inl (GResStep.reuse_allVars_eq hp hr)

/-- **The child's row is strictly smaller than the parent's**, in every model of the
successor system.  The rank is measured in the EXTENDED model: `DefaultStep.extend`
supplies one that agrees with any model of the predecessor on the old vocabulary, and the
parent is in the old vocabulary (`MintParent.parent_mem`), so the parent's rank is the
same before and after.  This is the lemma a König-style argument needs: along an infinite
run every variable's rank is bounded by the input's, and every mint goes strictly down. -/
theorem mintParent_rank_lt {G G' : System} {p c : Var} (h : MintParent G G' p c)
    {rho' : Assign} (hm : SModels rho' G') : (rho' c).card < (rho' p).card := by
  rcases h with ⟨d, happ, rfl, rfl⟩ | ⟨x, y, C, D, hp, -, -, rfl⟩
  · exact split_rank_lt happ hm
  · exact res_rank_lt hp hm

/-- The same, with the model of the predecessor made explicit: the parent's rank under
`rho` is the parent's rank under the extension. -/
theorem mintParent_rank_lt' {G G' : System} {p c : Var} (h : MintParent G G' p c)
    {rho : Assign} (hm : SModels rho G) :
    ∃ rho', SModels rho' G' ∧ (∀ v ∈ allVars G, rho' v = rho v) ∧
      (rho' c).card < (rho p).card := by
  obtain ⟨rho', hm', hag⟩ := h.defaultStep.extend hm
  refine ⟨rho', hm', hag, ?_⟩
  rw [← hag p h.parent_mem]
  exact mintParent_rank_lt h hm'

/-! ### 7.1 Rows only shrink down the parent relation

More than the cardinality: the child's ROW is contained in the parent's, so along a run
every variable's row is contained in the row of some INPUT variable.  This is the "bounded
depth" half of the König argument: a chain of parents from any variable back to the input
has length at most the cardinality of an input row. -/

/-- The child's row is contained in the parent's, in every model of the successor. -/
theorem mintParent_row_subset {G G' : System} {p c : Var} (h : MintParent G G' p c)
    {rho' : Assign} (hm : SModels rho' G') : rho' c ⊆ rho' p := by
  rcases h with ⟨d, happ, rfl, rfl⟩ | ⟨x, y, C, D, hp, -, -, rfl⟩
  · have hs := hm _ (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
    rw [sat_lone_iff] at hs
    rw [hs.1]; exact Finset.subset_union_right
  · have hs := hm _ (Finset.mem_insert_self _ _)
    rw [sat_lone_iff] at hs
    rw [hs.1]; exact Finset.subset_union_right

/-- **Every row along a run sits inside an input row.**  The model of the input extends to
the whole run (`DefaultRun.extend`), and every variable the run has minted denotes a subset
of what some input variable denotes. -/
theorem DefaultRun.extend_row_subset {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) :
    ∀ rho₀ : Assign, SModels rho₀ G₀ →
      ∃ rho, SModels rho G ∧ (∀ v ∈ allVars G₀, rho v = rho₀ v) ∧
        ∀ v ∈ allVars G, ∃ w ∈ allVars G₀, rho v ⊆ rho₀ w := by
  induction h with
  | refl G =>
    exact fun rho₀ hm => ⟨rho₀, hm, fun _ _ => rfl, fun v hv => ⟨v, hv, Finset.Subset.refl _⟩⟩
  | @tail n G₀ G G' hrun hstep _ ih =>
    intro rho₀ hm
    obtain ⟨rho, hmr, hag, hrow⟩ := ih rho₀ hm
    obtain ⟨rho', hm', hag'⟩ := hstep.extend hmr
    refine ⟨rho', hm', fun v hv => (hag' v (allVars_mono hrun.subset hv)).trans (hag v hv), ?_⟩
    intro v hv
    rcases hstep.allVars_eq_or_mint with hV | ⟨p, c, hmp⟩
    · rw [hV] at hv
      obtain ⟨w, hw, hsub⟩ := hrow v hv
      exact ⟨w, hw, (hag' v hv).symm ▸ hsub⟩
    · rw [hmp.allVars_eq, Finset.mem_insert] at hv
      rcases hv with rfl | hv
      · obtain ⟨w, hw, hsub⟩ := hrow p hmp.parent_mem
        refine ⟨w, hw, (mintParent_row_subset hmp hm').trans ?_⟩
        rw [hag' p hmp.parent_mem]; exact hsub
      · obtain ⟨w, hw, hsub⟩ := hrow v hv
        exact ⟨w, hw, (hag' v hv).symm ▸ hsub⟩

/-- **The rank of every variable along a run is bounded by the input**: by the largest row
any input variable denotes. -/
theorem DefaultRun.rank_le {n : ℕ} {G₀ G : System} (h : DefaultRun n G₀ G) {rho₀ : Assign}
    (hm : SModels rho₀ G₀) :
    ∃ rho, SModels rho G ∧ (∀ v ∈ allVars G₀, rho v = rho₀ v) ∧
      ∀ v ∈ allVars G, (rho v).card ≤ (allVars G₀).sup (fun w => (rho₀ w).card) := by
  obtain ⟨rho, hmr, hag, hrow⟩ := h.extend_row_subset rho₀ hm
  refine ⟨rho, hmr, hag, fun v hv => ?_⟩
  obtain ⟨w, hw, hsub⟩ := hrow v hv
  exact (Finset.card_le_card hsub).trans (Finset.le_sup (f := fun w => (rho₀ w).card) hw)

/-! ## 8. Counting the mints of a run

`DefaultRun` is a proposition, so the steps of a run cannot be counted from it.  `CountRun P`
carries, as a second index, the number of steps that satisfy `P`; every run counts
(`DefaultRun.exists_countRun`), and a counted run is a run (`CountRun.toDefaultRun`). -/

/-- A productive run of the shipped rule set, `n` steps long, in which exactly `m` of the
steps satisfy `P`. -/
inductive CountRun (P : System → System → Prop) : ℕ → ℕ → System → System → Prop
  | refl (G : System) : CountRun P 0 0 G G
  | hit {n m : ℕ} {G₀ G G' : System} :
      CountRun P n m G₀ G → DefaultStep G G' → G ⊂ G' → P G G' →
      CountRun P (n + 1) (m + 1) G₀ G'
  | miss {n m : ℕ} {G₀ G G' : System} :
      CountRun P n m G₀ G → DefaultStep G G' → G ⊂ G' → ¬ P G G' →
      CountRun P (n + 1) m G₀ G'

theorem CountRun.toDefaultRun {P : System → System → Prop} {n m : ℕ} {G₀ G : System}
    (h : CountRun P n m G₀ G) : DefaultRun n G₀ G := by
  induction h with
  | refl G => exact DefaultRun.refl G
  | hit _ hstep hss _ ih => exact DefaultRun.tail ih hstep hss
  | miss _ hstep hss _ ih => exact DefaultRun.tail ih hstep hss

theorem CountRun.count_le {P : System → System → Prop} {n m : ℕ} {G₀ G : System}
    (h : CountRun P n m G₀ G) : m ≤ n := by
  induction h with
  | refl => exact Nat.le_refl _
  | hit _ _ _ _ ih => omega
  | miss _ _ _ _ ih => omega

/-- Every run counts, for every predicate. -/
theorem DefaultRun.exists_countRun (P : System → System → Prop) {n : ℕ} {G₀ G : System}
    (h : DefaultRun n G₀ G) : ∃ m, CountRun P n m G₀ G := by
  induction h with
  | refl G => exact ⟨0, CountRun.refl G⟩
  | @tail n G₀ G G' _ hstep hss ih =>
    obtain ⟨m, hc⟩ := ih
    by_cases hP : P G G'
    · exact ⟨m + 1, CountRun.hit hc hstep hss hP⟩
    · exact ⟨m, CountRun.miss hc hstep hss hP⟩

/-! ### 8.1 All mints: exactly the growth of the vocabulary -/

/-- The step `G → G'` is a mint (of either kind). -/
def IsMint (G G' : System) : Prop := ∃ p c, MintParent G G' p c

/-- **The number of mints along a run is exactly the number of variables it added.** -/
theorem CountRun.mints_eq_allVars_growth {n m : ℕ} {G₀ G : System}
    (h : CountRun IsMint n m G₀ G) : (allVars G).card = (allVars G₀).card + m := by
  induction h with
  | refl => rfl
  | @hit n m G₀ G G' _ _ _ hP ih =>
    obtain ⟨p, c, hmp⟩ := hP
    rw [hmp.allVars_eq, Finset.card_insert_of_notMem hmp.fresh, ih, Nat.add_assoc]
  | @miss n m G₀ G G' _ hstep _ hP ih =>
    rcases hstep.allVars_eq_or_mint with hV | ⟨p, c, hmp⟩
    · rw [hV, ih]
    · exact absurd ⟨p, c, hmp⟩ hP

/-- **An unbounded run has unboundedly many mints.**  If runs from `G₀` of every length
exist, then for every `M` some run from `G₀` performs more than `M` mints. -/
theorem unbounded_mints_of_unbounded_run {L : Finset Label} {G₀ : System} (hcs : ConcSub L G₀)
    (hdiv : ∀ N, ∃ n G, DefaultRun n G₀ G ∧ N < n) :
    ∀ M, ∃ n m G, CountRun IsMint n m G₀ G ∧ M < m := by
  intro M
  obtain ⟨n, G, hrun, hM⟩ := unbounded_vocab_of_unbounded_run hcs hdiv (M + (allVars G₀).card)
  obtain ⟨m, hc⟩ := hrun.exists_countRun IsMint
  have := hc.mints_eq_allVars_growth
  exact ⟨n, m, G, hc, by omega⟩

/-- **The question, restated on the mints**: from every satisfiable input, the number of
mints along every run is bounded by the input. -/
def MintsBoundedOnSat : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ B : ℕ, ∀ (n m : ℕ) (G : System), CountRun IsMint n m G₀ G → m ≤ B

/-- Bounded vocabulary and bounded mints are the same thing
(`CountRun.mints_eq_allVars_growth`). -/
theorem vocabBounded_iff_mintsBounded : VocabBoundedOnSat ↔ MintsBoundedOnSat := by
  constructor
  · intro h G₀ rho hm
    obtain ⟨B, hB⟩ := h G₀ rho hm
    refine ⟨B, fun n m G hc => ?_⟩
    have h1 := hc.mints_eq_allVars_growth
    have h2 := hB n G hc.toDefaultRun
    omega
  · intro h G₀ rho hm
    obtain ⟨B, hB⟩ := h G₀ rho hm
    refine ⟨(allVars G₀).card + B, fun n G hrun => ?_⟩
    obtain ⟨m, hc⟩ := hrun.exists_countRun IsMint
    have h1 := hc.mints_eq_allVars_growth
    have h2 := hB n m G hc
    omega

/-- **Termination is exactly boundedly many mints.**  This is the form in which §9 states
what is missing: a bound on the mints is a bound on the branching of the parent relation
(§8.2, §8.3) together with its depth (§7.1). -/
theorem terminatesOnSat_iff_mintsBounded : TerminatesOnSat ↔ MintsBoundedOnSat :=
  terminatesOnSat_iff_vocabBounded.trans vocabBounded_iff_mintsBounded

/-! ### 8.2 Resolution mints at a fixed parent: at most `2 ^ |L|`

Each resolution mint at `p` closes off one resolvent key `C ∪ D ⊆ L` (`unfired_lt`), and
no step reopens a key (`unfired_le`).  So the guard bounds the resolution BRANCHING of the
parent relation by the input's label set alone. -/

/-- The step `G → G'` is a resolution mint with parent `p`. -/
def IsResMintAt (p : Var) (G G' : System) : Prop := ∃ c, ResMintAt G G' p c

/-- A resolution mint at `p` spends one unit of `p`'s budget. -/
theorem ResMintAt.unfired_lt {L : Finset Label} {G G' : System} {p c : Var}
    (h : ResMintAt G G' p c) (hcs : ConcSub L G) : unfired L G' p + 1 ≤ unfired L G p := by
  obtain ⟨x, y, C, D, hp, hg, -, rfl⟩ := h
  exact Rowpartition.unfired_lt (subset_resResult _ _ _ _ _ _ _)
    (Finset.union_subset (hcs _ hp.mem₁) (hcs _ hp.mem₂)) hg (Finset.mem_insert_self _ _)

/-- Along a run, the resolution mints at `p` are paid for out of `p`'s INPUT budget. -/
theorem CountRun.res_budget {L : Finset Label} {p : Var} {n m : ℕ} {G₀ G : System}
    (h : CountRun (IsResMintAt p) n m G₀ G) :
    ConcSub L G₀ → unfired L G p + m ≤ unfired L G₀ p := by
  induction h with
  | refl G => exact fun _ => Nat.le_refl _
  | @hit n m G₀ G G' hrun _ _ hP ih =>
    intro hcs
    obtain ⟨c, hres⟩ := hP
    have h1 := hres.unfired_lt (hrun.toDefaultRun.concSub hcs)
    have h2 := ih hcs
    omega
  | @miss n m G₀ G G' _ hstep _ _ ih =>
    intro hcs
    have h1 := unfired_le (L := L) hstep.subset p
    have h2 := ih hcs
    omega

/-- **Resolution branching is bounded by the label set**: along any run from an input
whose labels lie in `L`, at most `2 ^ |L|` resolution mints have parent `p`. -/
theorem CountRun.res_branching_le {L : Finset Label} {p : Var} {n m : ℕ} {G₀ G : System}
    (h : CountRun (IsResMintAt p) n m G₀ G) (hcs : ConcSub L G₀) : m ≤ 2 ^ L.card := by
  have h1 := h.res_budget hcs
  have h2 := unfired_le_pow L G₀ p
  omega

/-! ### 8.3 Split mints at a fixed parent: bounded only by the FINAL system

Each split mint at `p` names a group of `p`'s that was unnamed (`SplitApp.unnamed`), and
names are never lost in the additive calculus.  So the split mints at `p` along a run are
injective into the NAMED groups of `p` in the final system -- and that is all: nothing
here bounds the number of distinct groups a variable can acquire from the input.  Compare
§8.2, where the keys live in `L.powerset`, a set fixed by the input. -/

/-- The step `G → G'` is a split mint with parent `p`. -/
def IsSplitMintAt (p : Var) (G G' : System) : Prop := ∃ c, SplitMintAt G G' p c

/-- The groups of `p` in `G` that some constraint of `G` names. -/
def namedGroupsAt (p : Var) (G : System) : Finset (Finset Var) :=
  ((G.filter (fun d => d.lhs = p)).image vset).filter (fun S => Named G S)

theorem namedGroupsAt_mono {p : Var} {G G' : System} (hsub : G ⊆ G') :
    namedGroupsAt p G ⊆ namedGroupsAt p G' := by
  intro S hS
  simp only [namedGroupsAt, Finset.mem_filter, Finset.mem_image] at hS ⊢
  obtain ⟨⟨d, hd, rfl⟩, hn⟩ := hS
  exact ⟨⟨d, ⟨hsub hd.1, hd.2⟩, rfl⟩, hn.mono hsub⟩

/-- A split mint at `p` adds a new named group of `p`. -/
theorem SplitMintAt.namedGroupsAt_lt {G G' : System} {p c : Var} (h : SplitMintAt G G' p c) :
    (namedGroupsAt p G).card + 1 ≤ (namedGroupsAt p G').card := by
  obtain ⟨d, happ, rfl, rfl⟩ := h
  have hsub : G ⊆ splitResult G d c := subset_splitResult _ _ _
  have hmem : vset d ∈ namedGroupsAt d.lhs (splitResult G d c) := by
    simp only [namedGroupsAt, Finset.mem_filter, Finset.mem_image]
    exact ⟨⟨d, ⟨hsub happ.mem, rfl⟩, rfl⟩,
      ⟨mk c (vset d) ∅, Finset.mem_insert_self _ _, vset_mk _ _ _, conc_mk _ _ _⟩⟩
  have hnot : vset d ∉ namedGroupsAt d.lhs G := by
    intro hh
    exact happ.unnamed (Finset.mem_filter.mp hh).2
  exact Finset.card_lt_card
    ((Finset.ssubset_iff_of_subset (namedGroupsAt_mono hsub)).mpr ⟨vset d, hmem, hnot⟩)

/-- Along a run, the split mints at `p` are injective into the named groups of `p` in the
final system. -/
theorem CountRun.split_budget {p : Var} {n m : ℕ} {G₀ G : System}
    (h : CountRun (IsSplitMintAt p) n m G₀ G) :
    (namedGroupsAt p G₀).card + m ≤ (namedGroupsAt p G).card := by
  induction h with
  | refl G => exact Nat.le_refl _
  | @hit n m G₀ G G' _ _ _ hP ih =>
    obtain ⟨c, hs⟩ := hP
    have h1 := hs.namedGroupsAt_lt
    omega
  | @miss n m G₀ G G' _ hstep _ _ ih =>
    have h1 := Finset.card_le_card (namedGroupsAt_mono (p := p) hstep.subset)
    omega

/-- **Split branching is bounded by the final system's named groups at the parent** -- and,
in this file, by nothing smaller.  Bounding `(namedGroupsAt p G).card` from the INPUT, for
every `G` a run can reach, is exactly the open question stated at `TerminatesOnSat`. -/
theorem CountRun.split_branching_le {p : Var} {n m : ℕ} {G₀ G : System}
    (h : CountRun (IsSplitMintAt p) n m G₀ G) : m ≤ (namedGroupsAt p G).card := by
  have := h.split_budget
  omega

/-! ## 9. The gap

**What would close the question.**  Suppose every parent had bounded branching: a bound
`B G₀`, computed from the input, on the number of children any one variable can acquire
along any run.  Then a run from a satisfiable input is a tree of mints in which every node
has at most `B G₀` children (`MintParent`), every child's rank is strictly below its
parent's (`mintParent_rank_lt`), and every rank is at most the largest input row
(`DefaultRun.rank_le`), so every root-to-leaf chain has bounded length; a finitely
branching tree of bounded depth is finite (König), so the vocabulary is bounded, so by
`DefaultRun.length_le_forms` the run is bounded: `TerminatesOnSat`.

**What is known about branching.**  Resolution branching is bounded, by `2 ^ |L|`
(`CountRun.res_branching_le`).  Split branching is bounded only by the number of named
groups at the parent in the FINAL system (`CountRun.split_branching_le`); nothing bounds
that from the input.  A variable acquires a new group whenever substitution, cancellation
or CSE reuse rewrites one of its constraints with names minted elsewhere, and empty-row
variables may recur inside groups without violating disjointness.  Whether some
satisfiable input lets that happen without end is the question this file leaves open;
`tracker/tools/rowclosure.py` searches for one.

The two branching statements, side by side.  For resolution the bound is a THEOREM of the
input (`resBranchingBounded`); for split it is a DEFINITION -- the hypothesis the König
argument would consume, and the one nothing here supplies (`SplitBranchingBounded`). -/

/-- **Resolution branching is bounded by the input**: one bound, `2 ^ |labelsOf G₀|`, on the
resolution mints at every parent along every run (`CountRun.res_branching_le`). -/
theorem resBranchingBounded (G₀ : System) :
    ∃ B : ℕ, ∀ (p : Var) (n m : ℕ) (G : System), CountRun (IsResMintAt p) n m G₀ G → m ≤ B :=
  ⟨2 ^ (labelsOf G₀).card, fun _ _ _ _ h => h.res_branching_le (labelsOf_concSub G₀)⟩

/-- **The missing hypothesis.**  From every satisfiable input, one bound on the split mints at
every parent along every run.  `SplitBranchingBounded → TerminatesOnSat` is the König step
sketched above (bounded branching at every parent, `resBranchingBounded` for the other kind;
bounded depth, `DefaultRun.rank_le` with `mintParent_rank_lt`); it is NOT formalised here, and
`SplitBranchingBounded` itself is neither proved nor refuted.  `CountRun.split_branching_le`
is all that is known: the bound exists in the FINAL system, not from the input. -/
def SplitBranchingBounded : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ B : ℕ, ∀ (p : Var) (n m : ℕ) (G : System), CountRun (IsSplitMintAt p) n m G₀ G → m ≤ B

end Rowpartition
