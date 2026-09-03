/-
# DefaultSatDiverge -- the shipped rule set does NOT terminate on every SATISFIABLE input

`DefaultTerm.lean` asks whether every productive run of the shipped rule set `DefaultStep`
(`NonGenStep` + `splitConcrete`'s mint + guarded `resolution`) from a SATISFIABLE input is
bounded (`TerminatesOnSat`), proves the structural chain the natural argument needs, and
leaves one gap: nothing bounds the number of distinct groups a variable can acquire along a
run.  This file closes the question NEGATIVELY (`not_TerminatesOnSat`): the two-constraint
satisfiable system

```
W2 = { p <- (e1, e2, (|k|)),  p <- (e2, (|k|)) }
```

admits productive runs of every length (`SatDiverge.W2_unbounded`, `SatDiverge.W2_diverges`),
so no bound `N` exists for it, although it has the model `rho p = {k, m}`, `rho e2 = {m}`,
`rho e1 = ∅` (`SatDiverge.W2_models`).  `e1` is FORCED empty by the two constraints, and that
is what the engine below exploits: every name it mints denotes `{m}` again.

## The round

Round 0 (`SatDiverge.step0`): the group `{e1, e2}` of the first constraint is unnamed (`W2`
has no bare constraint), so a split mint (`Cut.SplitApp`) mints `u₁` with `u₁ <- (e1, e2)`
and `p <- (u₁, (|k|))`.  From then on, with `u` the latest name and `cur := p <- (u, (|k|))`
present, three productive `DefaultStep`s add four constraints and one variable
(`W2Inv.round`):

1. CANCELLATION (`SplitNecessary.CancelApp` with `c := p <- (e2, (|k|))`,
   `d := p <- (u, (|k|))`, `z := e2`): same left-hand side, `k ⊆ k`, lone leftover `e2`;
   emits the alias link `e2 <- (u)`.  Model: `rho e2 = {m} = rho u`.
2. SUBSTITUTION (`SplitNecessary.SubstApp` of the link into `p <- (e1, e2, (|k|))`): emits
   `p <- (e1, u, (|k|))`.  Model: `{k} ∪ ∅ ∪ {m}`, disjoint because `rho e1 = ∅`.
3. SPLIT MINT (`Cut.SplitApp` on `p <- (e1, u, (|k|))`, fresh `u'`): the concrete part is
   nonempty, the group `{e1, u}` has two variables and is UNNAMED -- `u` occurs on a
   right-hand side only in `cur`, the link and the constraint just added, none of which is
   bare with that group -- so it emits `u' <- (e1, u)` and `p <- (u', (|k|))`.  Model
   `rho u' := rho e1 ∪ rho u = {m}`.

The invariant `W2Inv` records the three constraints the round consumes, the distinctness of
the four variables, and the freshness fact `u_fresh`: the latest name occurs on a right-hand
side only in `cur`.  That single fact discharges the split's `unnamed` guard and the
productivity of all three steps, and is re-established for `u'` after the round because `u'`
is fresh and its own definition has it on the LEFT.  `W2Inv.run` iterates the round;
`W2Inv.run_exact` fills in the intermediate lengths with the first one or two steps of the
next round.

## SCOPE -- what this settles and what it does not

`TerminatesOnSat` is quantified over ALL productive runs of the ADDITIVE relation
`DefaultStep`, in any order, with no deletion.  This file refutes exactly that statement.
It does NOT show that the real `incorporateAll` loop hangs on `W2`, and three of the loop's
features each break the engine above:

* **Names travel with their groups.**  Under a substitution-closed strategy the link
  `e2 <- (u)` is also substituted into the name's own definition `u₁ <- (e1, e2)`, giving the
  bare `u₁ <- (e1, u)` -- which NAMES the very group the next mint needs, so the split's
  reverse lookup hits and a saturating run reaches a fixpoint after one mint.  The one-step
  mechanism is `subst_names_travel` (§6); it is a lemma about one substitution, not a
  termination theorem.
* **Singleton links are unified, not substituted.**  The real loop turns `e2 <- (u)` into
  `unify e2 u` (`Saturate.SatStep`'s `rename`/`unify`), after which `p <- (e2, (|k|))` and
  `p <- (u, (|k|))` are the same constraint and cancellation has nothing to cancel.
* **`makeEmpty` erases `e1`.**  Cancelling `p <- (e1, e2, (|k|))` against `p <- (e2, (|k|))`
  derives `e1 <- ()`, and `makeEmpty` then deletes `e1` from every group, leaving no
  two-variable group for the split to name.

So what is decided here is that no bound exists for arbitrary run orders of the additive
relation.  Open: "Conjecture S" (every substitution-closed / saturating run from a
satisfiable input is bounded) and the loop-level question (whether `incorporateAll`
terminates on every satisfiable input), both on layers this file does not model.

## Contents

* §1  `W2Inv`, the invariant.
* §2  The three steps of a round, over abstract variables: `W2Inv.step_cancel`,
      `W2Inv.step_subst`, `W2Inv.not_named` / `W2Inv.step_split`.
* §3  `W2Inv.round`, `W2Inv.run`, `W2Inv.run_exact`.
* §4  The seed `SatDiverge.W2`, its model, and round 0 into the invariant.
* §5  Headline: `SatDiverge.W2_unbounded`, `SatDiverge.W2_diverges`, `SatDiverge.W2_witness`,
      `not_TerminatesOnSat`.
* §6  `subst_names_travel`, the name-travel mechanism, one substitution.
-/
import Rowpartition.DefaultTerm

namespace Rowpartition

/-! ## 1. The invariant -/

/-- **The engine's invariant.**  `G` contains the base constraint `p <- (e1, e2, (|K|))`,
its single-variable companion `p <- (e2, (|K|))`, and the current `p <- (u, (|K|))` for the
latest minted name `u`; `K` is nonempty; the four variables are pairwise distinct; and `u`
occurs on a right-hand side ONLY in `cur`.  The last fact is what makes the group `{e1, u}`
unnamed (`W2Inv.not_named`) and every step of the round productive.

The analogue of `ResGuardDiverge.GInv`. -/
structure W2Inv (G : System) (p e1 e2 u : Var) (K : Row) : Prop where
  -- the constructor is named `intro` rather than the default `mk`, so that inside the
  -- `W2Inv` namespace the canonical-constraint builder `Rowpartition.mk` stays visible
  intro ::
  /-- `p <- (e1, e2, (|K|))` -/
  base : mk p {e1, e2} K ∈ G
  /-- `p <- (e2, (|K|))` -/
  single : mk p {e2} K ∈ G
  /-- `p <- (u, (|K|))`, the current constraint on the latest name -/
  cur : mk p {u} K ∈ G
  /-- the concrete part is nonempty, so the split fires -/
  K_ne : K ≠ ∅
  /-- the partitioned variable is not one of its parts -/
  pe1 : p ≠ e1
  /-- the partitioned variable is not one of its parts -/
  pe2 : p ≠ e2
  /-- the partitioned variable is not one of its parts -/
  pu : p ≠ u
  /-- the parts are distinct -/
  e12 : e1 ≠ e2
  /-- the parts are distinct -/
  e1u : e1 ≠ u
  /-- the parts are distinct -/
  e2u : e2 ≠ u
  /-- `u` occurs on a right-hand side only in `cur` -/
  u_fresh : ∀ c ∈ G, u ∈ vset c → c = mk p {u} K

/-! ## 2. One round, over abstract variables

The three systems of a round, written out (no local definitions, so that every lemma below
can be `rw`-ed into the next):

* `G₁ := insert (mk e2 {u} ∅) G`                        -- after cancellation
* `G₂ := insert (mk p {e1, u} K) G₁`                     -- after substitution
* `G₃ := insert (mk u' {e1, u} ∅) (insert (mk p {u'} K) G₂)`  -- after the split mint
-/

section Round

variable {G : System} {p e1 e2 u : Var} {K : Row}

/-! ### 2.1 Cancellation: `p <- (e2, (|K|))` against `p <- (u, (|K|))` emits `e2 <- (u)` -/

/-- The premises of cancellation hold: same left-hand side, `K ⊆ K`, and the lone leftover
of the first premise is `e2`. -/
theorem W2Inv.cancelApp (h : W2Inv G p e1 e2 u K) :
    CancelApp G (mk p {e2} K) (mk p {u} K) e2 where
  mem₁ := h.single
  mem₂ := h.cur
  same_lhs := rfl
  conc_le := Finset.Subset.refl _
  lone := by
    rw [vset_mk, vset_mk]
    exact Finset.sdiff_eq_self_iff_disjoint.mpr (Finset.disjoint_singleton.mpr h.e2u)

/-- What cancellation emits, computed: `mk e2 ({u} \ {e2}) (K \ K) = mk e2 {u} ∅`. -/
theorem W2Inv.cancelResult_eq (h : W2Inv G p e1 e2 u K) :
    cancelResult G (mk p {e2} K) (mk p {u} K) e2 = insert (mk e2 {u} ∅) G := by
  have hs : ({u} : Finset Var) \ {e2} = {u} :=
    Finset.sdiff_eq_self_iff_disjoint.mpr (Finset.disjoint_singleton.mpr h.e2u.symm)
  simp only [cancelResult, vset_mk, conc_mk, Finset.sdiff_self, hs]

/-- The link is new: it has `u` on the right, so by `u_fresh` it could only be `cur`, whose
left-hand side is `p ≠ e2`. -/
theorem W2Inv.link_notMem (h : W2Inv G p e1 e2 u K) : mk e2 {u} ∅ ∉ G := by
  intro hmem
  have heq := h.u_fresh _ hmem (by rw [vset_mk]; exact Finset.mem_singleton_self u)
  rw [NameLoss.mk_eq_iff] at heq
  exact h.pe2 heq.1.symm

/-- **Step 1 of the round**: cancellation, one productive shipped step. -/
theorem W2Inv.step_cancel (h : W2Inv G p e1 e2 u K) :
    DefaultRun 1 G (insert (mk e2 {u} ∅) G) := by
  have hstep : DefaultStep G (insert (mk e2 {u} ∅) G) := by
    rw [← h.cancelResult_eq]
    exact DefaultStep.nongen (NonGenStep.cancel (CancelStep.intro h.cancelApp))
  exact DefaultRun.tail (DefaultRun.refl G) hstep (Finset.ssubset_insert h.link_notMem)

/-- `u_fresh` after step 1: `u` occurs on a right-hand side only in `cur` and the link. -/
theorem W2Inv.u_fresh₁ (h : W2Inv G p e1 e2 u K) :
    ∀ c ∈ insert (mk e2 {u} ∅) G, u ∈ vset c → c = mk p {u} K ∨ c = mk e2 {u} ∅ := by
  intro c hc hu
  rcases Finset.mem_insert.mp hc with rfl | hc
  · exact Or.inr rfl
  · exact Or.inl (h.u_fresh c hc hu)

/-! ### 2.2 Substitution: the link into the base constraint emits `p <- (e1, u, (|K|))` -/

/-- The premises of substitution hold: the link's left-hand side `e2` occurs on the right of
the base constraint. -/
theorem W2Inv.substApp (h : W2Inv G p e1 e2 u K) :
    SubstApp (insert (mk e2 {u} ∅) G) (mk p {e1, e2} K) (mk e2 {u} ∅) where
  mem₁ := Finset.mem_insert_of_mem h.base
  mem₂ := Finset.mem_insert_self _ _
  occurs := by
    rw [lhs_mk, vset_mk]
    exact Finset.mem_insert_of_mem (Finset.mem_singleton_self e2)

/-- The merged group: `({e1, e2}.erase e2) ∪ {u} = {e1, u}` (needs `e1 ≠ e2`). -/
theorem W2Inv.merged_vset (h : W2Inv G p e1 e2 u K) :
    ({e1, e2} : Finset Var).erase e2 ∪ {u} = {e1, u} := by
  ext v
  simp only [Finset.mem_union, Finset.mem_erase, Finset.mem_insert, Finset.mem_singleton]
  constructor
  · rintro (⟨hne, rfl | rfl⟩ | rfl)
    · exact Or.inl rfl
    · exact absurd rfl hne
    · exact Or.inr rfl
  · rintro (rfl | rfl)
    · exact Or.inl ⟨h.e12, Or.inl rfl⟩
    · exact Or.inr rfl

/-- What substitution emits, computed. -/
theorem W2Inv.substResult_eq (h : W2Inv G p e1 e2 u K) :
    substResult (insert (mk e2 {u} ∅) G) (mk p {e1, e2} K) (mk e2 {u} ∅) =
      insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G) := by
  simp only [substResult, lhs_mk, vset_mk, conc_mk, h.merged_vset, Finset.union_empty]

/-- The merged constraint is new: it has `u` on the right, so it is `cur` (but its group has
two elements) or the link (but its left-hand side is `p ≠ e2`). -/
theorem W2Inv.merged_notMem (h : W2Inv G p e1 e2 u K) :
    mk p {e1, u} K ∉ insert (mk e2 {u} ∅) G := by
  intro hmem
  have hu : u ∈ vset (mk p {e1, u} K) := by
    rw [vset_mk]; exact Finset.mem_insert_of_mem (Finset.mem_singleton_self u)
  rcases h.u_fresh₁ _ hmem hu with heq | heq
  · rw [NameLoss.mk_eq_iff] at heq
    have he1 : e1 ∈ ({u} : Finset Var) := by
      rw [← heq.2.1]; exact Finset.mem_insert_self _ _
    exact h.e1u (Finset.mem_singleton.mp he1)
  · rw [NameLoss.mk_eq_iff] at heq
    exact h.pe2 heq.1

/-- **Step 2 of the round**: substitution, one productive shipped step. -/
theorem W2Inv.step_subst (h : W2Inv G p e1 e2 u K) :
    DefaultRun 1 (insert (mk e2 {u} ∅) G)
      (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) := by
  have hstep : DefaultStep (insert (mk e2 {u} ∅) G)
      (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) := by
    rw [← h.substResult_eq]
    exact DefaultStep.nongen (NonGenStep.subst (SubstStep.intro h.substApp))
  exact DefaultRun.tail (DefaultRun.refl _) hstep (Finset.ssubset_insert h.merged_notMem)

/-- `u_fresh` after step 2: `u` occurs on a right-hand side only in `cur`, the link, and the
merged constraint. -/
theorem W2Inv.u_fresh₂ (h : W2Inv G p e1 e2 u K) :
    ∀ c ∈ insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G), u ∈ vset c →
      c = mk p {u} K ∨ c = mk e2 {u} ∅ ∨ c = mk p {e1, u} K := by
  intro c hc hu
  rcases Finset.mem_insert.mp hc with rfl | hc
  · exact Or.inr (Or.inr rfl)
  · rcases h.u_fresh₁ c hc hu with h1 | h1
    · exact Or.inl h1
    · exact Or.inr (Or.inl h1)

/-! ### 2.3 The split mint on `p <- (e1, u, (|K|))` -/

/-- **The group `{e1, u}` is unnamed in `G`.**  A bare constraint with that group has `u` on
its right, so by `u_fresh` it is `cur` -- whose concrete part is `K ≠ ∅`. -/
theorem W2Inv.not_named (h : W2Inv G p e1 e2 u K) : ¬ Named G {e1, u} := by
  rintro ⟨d, hd, hv, hc⟩
  have hu : u ∈ vset d := by
    rw [hv]; exact Finset.mem_insert_of_mem (Finset.mem_singleton_self u)
  rcases h.u_fresh d hd hu with rfl
  rw [conc_mk] at hc
  exact h.K_ne hc

/-- **The group `{e1, u}` is still unnamed after steps 1 and 2.**  The three constraints
with `u` on the right are `cur` and the merged constraint (concrete part `K ≠ ∅`) and the
link (group `{u} ≠ {e1, u}`). -/
theorem W2Inv.not_named₂ (h : W2Inv G p e1 e2 u K) :
    ¬ Named (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) {e1, u} := by
  rintro ⟨d, hd, hv, hc⟩
  have hu : u ∈ vset d := by
    rw [hv]; exact Finset.mem_insert_of_mem (Finset.mem_singleton_self u)
  rcases h.u_fresh₂ d hd hu with rfl | rfl | rfl
  · rw [conc_mk] at hc; exact h.K_ne hc
  · rw [vset_mk] at hv
    have he1 : e1 ∈ ({u} : Finset Var) := by rw [hv]; exact Finset.mem_insert_self _ _
    exact h.e1u (Finset.mem_singleton.mp he1)
  · rw [conc_mk] at hc; exact h.K_ne hc

/-- The premises of the split mint hold on `G₂` for any `u'` fresh for `G₂`. -/
theorem W2Inv.splitApp (h : W2Inv G p e1 e2 u K) {u' : Var}
    (hu' : u' ∉ allVars (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G))) :
    SplitApp (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) (mk p {e1, u} K) u' where
  mem := Finset.mem_insert_self _ _
  conc_ne := h.K_ne
  two_le := by rw [vset_mk, Finset.card_pair h.e1u]
  unnamed := by rw [vset_mk]; exact h.not_named₂
  fresh := hu'

/-- What the split emits on a two-variable group, computed. -/
theorem splitResult_mk_pair (G : System) (p e1 u u' : Var) (K : Row) :
    splitResult G (mk p {e1, u} K) u' = insert (mk u' {e1, u} ∅) (insert (mk p {u'} K) G) := by
  simp only [splitResult, vset_mk, lhs_mk, conc_mk]

/-- The vocabulary of `G` contains the four variables of the invariant. -/
theorem W2Inv.mem_allVars (h : W2Inv G p e1 e2 u K) :
    p ∈ allVars G ∧ e1 ∈ allVars G ∧ e2 ∈ allVars G ∧ u ∈ allVars G :=
  ⟨lhs_mem_allVars h.cur,
    vset_subset_allVars h.base (by rw [vset_mk]; exact Finset.mem_insert_self _ _),
    vset_subset_allVars h.base
      (by rw [vset_mk]; exact Finset.mem_insert_of_mem (Finset.mem_singleton_self _)),
    vset_subset_allVars h.cur (by rw [vset_mk]; exact Finset.mem_singleton_self _)⟩

/-- A variable fresh for `G` differs from the four variables of the invariant. -/
theorem W2Inv.fresh_ne (h : W2Inv G p e1 e2 u K) {u' : Var} (hu' : u' ∉ allVars G) :
    p ≠ u' ∧ e1 ≠ u' ∧ e2 ≠ u' ∧ u ≠ u' := by
  obtain ⟨hp, he1, he2, hu⟩ := h.mem_allVars
  exact ⟨fun hh => hu' (hh ▸ hp), fun hh => hu' (hh ▸ he1), fun hh => hu' (hh ▸ he2),
    fun hh => hu' (hh ▸ hu)⟩

/-- Steps 1 and 2 do not touch the vocabulary. -/
theorem W2Inv.allVars₂ (h : W2Inv G p e1 e2 u K) :
    allVars (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) = allVars G := by
  obtain ⟨hp, he1, he2, hu⟩ := h.mem_allVars
  have hin : allVars (insert (mk e2 {u} ∅) G) = allVars G := by
    refine allVars_insert_eq_of_subset ?_
    intro v hv
    simp only [lhs_mk, vset_mk, Finset.mem_insert, Finset.mem_singleton] at hv
    rcases hv with rfl | rfl
    · exact he2
    · exact hu
  have hout : allVars (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) =
      allVars (insert (mk e2 {u} ∅) G) := by
    refine allVars_insert_eq_of_subset ?_
    rw [hin]
    intro v hv
    simp only [lhs_mk, vset_mk, Finset.mem_insert, Finset.mem_singleton] at hv
    rcases hv with rfl | rfl | rfl
    · exact hp
    · exact he1
    · exact hu
  rw [hout, hin]

/-- **Step 3 of the round**: the split mint, one productive shipped step (adding two
constraints). -/
theorem W2Inv.step_split (h : W2Inv G p e1 e2 u K) {u' : Var}
    (hu' : u' ∉ allVars (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G))) :
    DefaultRun 1 (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G))
      (insert (mk u' {e1, u} ∅) (insert (mk p {u'} K)
        (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)))) := by
  have hstep : DefaultStep (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G))
      (insert (mk u' {e1, u} ∅) (insert (mk p {u'} K)
        (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)))) := by
    rw [← splitResult_mk_pair]
    exact DefaultStep.mint (SplitStep.intro (h.splitApp hu'))
  have hnot : mk p {u'} K ∉ insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G) :=
    fun hmem => hu' (vset_subset_allVars hmem (by rw [vset_mk]; exact Finset.mem_singleton_self _))
  exact DefaultRun.tail (DefaultRun.refl _) hstep
    (Finset.ssubset_of_ssubset_of_subset (Finset.ssubset_insert hnot) (Finset.subset_insert _ _))

/-- Both constraints the split emits are new, so step 3 adds two. -/
theorem W2Inv.split_card (h : W2Inv G p e1 e2 u K) {u' : Var}
    (hu' : u' ∉ allVars (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G))) :
    (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)).card + 2 ≤
      (insert (mk u' {e1, u} ∅) (insert (mk p {u'} K)
        (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)))).card := by
  have hu'G : u' ∉ allVars G := by rw [← h.allVars₂]; exact hu'
  obtain ⟨hpu', -, -, -⟩ := h.fresh_ne hu'G
  have h1 : mk p {u'} K ∉ insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G) :=
    fun hmem => hu' (vset_subset_allVars hmem (by rw [vset_mk]; exact Finset.mem_singleton_self _))
  have h2 : mk u' {e1, u} ∅ ∉ insert (mk p {u'} K)
      (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)) := by
    intro hmem
    rcases Finset.mem_insert.mp hmem with heq | hmem
    · rw [NameLoss.mk_eq_iff] at heq
      exact hpu' heq.1.symm
    · exact hu' (lhs_mem_allVars hmem)
  rw [Finset.card_insert_of_notMem h2, Finset.card_insert_of_notMem h1]

/-! ## 3. The round, and the run -/

/-- **One round of the engine.**  Three productive shipped steps, four new constraints, one
new variable, and the invariant handed back on the new name. -/
theorem W2Inv.round (h : W2Inv G p e1 e2 u K) :
    ∃ (G' : System) (u' : Var),
      DefaultRun 3 G G' ∧ W2Inv G' p e1 e2 u' K ∧ G.card + 4 ≤ G'.card ∧
        u' ∉ allVars G ∧ allVars G' = insert u' (allVars G) := by
  obtain ⟨u', hu'⟩ := exists_fresh (allVars (insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G)))
  have hu'G : u' ∉ allVars G := by rw [← h.allVars₂]; exact hu'
  obtain ⟨hpu', he1u', he2u', huu'⟩ := h.fresh_ne hu'G
  have hsub : G ⊆ insert (mk p {e1, u} K) (insert (mk e2 {u} ∅) G) :=
    (Finset.subset_insert _ _).trans (Finset.subset_insert _ _)
  refine ⟨_, u', (h.step_cancel.trans h.step_subst).trans (h.step_split hu'), ?_, ?_, hu'G, ?_⟩
  · -- the invariant on the new name
    refine ⟨?_, ?_, ?_, h.K_ne, h.pe1, h.pe2, hpu', h.e12, he1u', he2u', ?_⟩
    · exact Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (hsub h.base))
    · exact Finset.mem_insert_of_mem (Finset.mem_insert_of_mem (hsub h.single))
    · exact Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
    · -- `u_fresh` for `u'`: its own definition has it on the left, `cur` is the only
      -- constraint with it on the right, and it is fresh for everything older
      intro c hc hv
      rcases Finset.mem_insert.mp hc with rfl | hc
      · exfalso
        rw [vset_mk, Finset.mem_insert, Finset.mem_singleton] at hv
        rcases hv with hh | hh
        · exact he1u' hh.symm
        · exact huu' hh.symm
      rcases Finset.mem_insert.mp hc with rfl | hc
      · rfl
      · exact absurd (vset_subset_allVars hc hv) hu'
  · -- four new constraints
    have h1 := h.step_cancel.card_ge
    have h2 := h.step_subst.card_ge
    have h3 := h.split_card hu'
    omega
  · -- exactly one new variable
    rw [← splitResult_mk_pair, allVars_splitResult (Finset.mem_insert_self _ _), h.allVars₂]

/-- **`n` rounds.**  `3 n` productive shipped steps and at least `4 n` new constraints, with
the invariant handed back. -/
theorem W2Inv.run (h : W2Inv G p e1 e2 u K) (n : ℕ) :
    ∃ (G' : System) (u' : Var),
      DefaultRun (3 * n) G G' ∧ W2Inv G' p e1 e2 u' K ∧ G.card + 4 * n ≤ G'.card := by
  induction n generalizing G u with
  | zero => exact ⟨G, u, DefaultRun.refl G, h, by omega⟩
  | succ n ih =>
    obtain ⟨G₁, u₁, hrun₁, hinv₁, hcard₁, -, -⟩ := h.round
    obtain ⟨G₂, u₂, hrun₂, hinv₂, hcard₂⟩ := ih hinv₁
    refine ⟨G₂, u₂, ?_, hinv₂, by omega⟩
    rw [show 3 * (n + 1) = 3 + 3 * n by omega]
    exact hrun₁.trans hrun₂

/-- **Productive runs of EVERY length** from the invariant: whole rounds, then the first one
or two steps of the next round for the remainder. -/
theorem W2Inv.run_exact (h : W2Inv G p e1 e2 u K) (n : ℕ) : ∃ G', DefaultRun n G G' := by
  obtain ⟨k, hk | hk | hk⟩ : ∃ k, n = 3 * k ∨ n = 3 * k + 1 ∨ n = 3 * k + 2 :=
    ⟨n / 3, by omega⟩
  · obtain ⟨G', -, hrun, -, -⟩ := h.run k
    exact ⟨G', hk ▸ hrun⟩
  · obtain ⟨G', u', hrun, hinv, -⟩ := h.run k
    subst hk
    exact ⟨_, hrun.trans hinv.step_cancel⟩
  · obtain ⟨G', u', hrun, hinv, -⟩ := h.run k
    subst hk
    exact ⟨_, (hrun.trans hinv.step_cancel).trans hinv.step_subst⟩

end Round

/-! ## 4. The seed -/

namespace SatDiverge

/-- `p = 0`, the partitioned variable -/
abbrev p : Var := 0
/-- `e1 = 1`, the part the two constraints force empty -/
abbrev e1 : Var := 1
/-- `e2 = 2`, the part that carries `m` -/
abbrev e2 : Var := 2
/-- `u1 = 3`, the first minted name -/
abbrev u1 : Var := 3
/-- the label `k`, in the concrete part of both constraints -/
abbrev fk : Label := 5
/-- the label `m`, carried by `e2` and by every minted name -/
abbrev fm : Label := 6
/-- the concrete part `(|k|)` -/
abbrev K : Row := {fk}

/-- **The two-constraint witness.**

```
0 <- (1, 2, (|5|))     0 <- (2, (|5|))
```
-/
def W2 : System := {mk p {e1, e2} K, mk p {e2} K}

theorem base_mem : mk p {e1, e2} K ∈ W2 := Finset.mem_insert_self _ _

theorem single_mem : mk p {e2} K ∈ W2 :=
  Finset.mem_insert_of_mem (Finset.mem_singleton_self _)

theorem W2_card : W2.card = 2 := by
  rw [W2, Finset.card_insert_of_notMem, Finset.card_singleton]
  simp only [Finset.mem_singleton, NameLoss.mk_eq_iff]
  decide

/-! ### 4.1 The model -/

/-- The model: `rho p = {k, m}`, `rho e2 = {m}`, `rho e1 = ∅`, and every other variable --
in particular every name the engine mints -- denotes `{m}`. -/
def rho2 : Assign := fun v =>
  if v = p then {fk, fm} else if v = e2 then {fm} else if v = e1 then ∅ else {fm}

/-- **`W2` is satisfiable.** -/
theorem W2_models : SModels rho2 W2 := by
  intro c hc
  simp only [W2, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl <;> (rw [sat_mk_iff]; decide)

theorem W2_sat : ∃ rho, SModels rho W2 := ⟨rho2, W2_models⟩

/-! ### 4.2 Round 0: the split mint on the base constraint -/

/-- `W2` has no bare constraint, so nothing names `{e1, e2}`. -/
theorem W2_unnamed : ¬ Named W2 {e1, e2} := by
  rintro ⟨d, hd, -, hc⟩
  simp only [W2, Finset.mem_insert, Finset.mem_singleton] at hd
  rcases hd with rfl | rfl <;> (rw [conc_mk] at hc; exact Finset.singleton_ne_empty _ hc)

theorem u1_fresh : u1 ∉ allVars W2 := by
  simp only [allVars, W2, Finset.biUnion_insert, Finset.singleton_biUnion, lhs_mk, vset_mk]
  decide

/-- The split mint on the base constraint is enabled, with the fresh name `u1`. -/
theorem split0_app : SplitApp W2 (mk p {e1, e2} K) u1 where
  mem := base_mem
  conc_ne := Finset.singleton_ne_empty _
  two_le := by rw [vset_mk]; decide
  unnamed := by rw [vset_mk]; exact W2_unnamed
  fresh := u1_fresh

/-- The system after round 0: `u1 <- (e1, e2)` and `p <- (u1, (|k|))` added to `W2`. -/
def G₁ : System := insert (mk u1 {e1, e2} ∅) (insert (mk p {u1} K) W2)

theorem cur1_notMem : mk p {u1} K ∉ W2 := by
  simp only [W2, Finset.mem_insert, Finset.mem_singleton, NameLoss.mk_eq_iff]
  decide

/-- **Round 0**: one productive shipped step, the split mint. -/
theorem step0 : DefaultRun 1 W2 G₁ := by
  have hstep : DefaultStep W2 G₁ := by
    have := DefaultStep.mint (SplitStep.intro split0_app)
    rwa [splitResult_mk_pair] at this
  exact DefaultRun.tail (DefaultRun.refl W2) hstep
    (Finset.ssubset_of_ssubset_of_subset (Finset.ssubset_insert cur1_notMem)
      (Finset.subset_insert _ _))

/-- **The invariant holds after round 0**, on the name `u1`. -/
theorem G₁_inv : W2Inv G₁ p e1 e2 u1 K where
  base := Finset.mem_insert_of_mem (Finset.mem_insert_of_mem base_mem)
  single := Finset.mem_insert_of_mem (Finset.mem_insert_of_mem single_mem)
  cur := Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
  K_ne := Finset.singleton_ne_empty _
  pe1 := by decide
  pe2 := by decide
  pu := by decide
  e12 := by decide
  e1u := by decide
  e2u := by decide
  u_fresh := by
    intro c hc hu
    simp only [G₁, W2, Finset.mem_insert, Finset.mem_singleton] at hc
    rcases hc with rfl | rfl | rfl | rfl
    · rw [vset_mk] at hu; exact absurd hu (by decide)
    · rfl
    · rw [vset_mk] at hu; exact absurd hu (by decide)
    · rw [vset_mk] at hu; exact absurd hu (by decide)

/-! ## 5. Headline -/

/-- **Productive runs of every length from `W2`.** -/
theorem W2_every_length (n : ℕ) : ∃ G, DefaultRun n W2 G := by
  obtain _ | n := n
  · exact ⟨W2, DefaultRun.refl W2⟩
  · obtain ⟨G', hrun⟩ := G₁_inv.run_exact n
    exact ⟨G', by rw [Nat.add_comm]; exact step0.trans hrun⟩

/-- **No bound on the productive runs from `W2`**: round 0 and `N + 1` rounds are
`1 + 3 (N + 1) > N` steps. -/
theorem W2_unbounded : ∀ N, ∃ n G, DefaultRun n W2 G ∧ N < n := by
  intro N
  obtain ⟨G', -, hrun, -, -⟩ := G₁_inv.run (N + 1)
  exact ⟨1 + 3 * (N + 1), G', step0.trans hrun, by omega⟩

/-- **`W2` diverges** in `DefaultDiverge`'s exact-length sense: shipped chains of every
length, each growing the working set by at least one constraint per step. -/
theorem W2_diverges : Diverges W2 := by
  intro n
  obtain ⟨G, hrun⟩ := W2_every_length n
  exact ⟨G, hrun.toDefaultSteps, hrun.card_ge⟩

/-- **The witness**: satisfiable, and with productive shipped runs of unbounded length. -/
theorem W2_witness : (∃ rho, SModels rho W2) ∧ ∀ N, ∃ n G, DefaultRun n W2 G ∧ N < n :=
  ⟨W2_sat, W2_unbounded⟩

end SatDiverge

/-- **`TerminatesOnSat` is false.**  The satisfiable `SatDiverge.W2` has productive runs of
the shipped rule set of every length.  This is the ADDITIVE relation `DefaultStep`
quantified over all run orders; see the module docstring for what the real loop does
differently (name travel, unification of singleton links, `makeEmpty`), and for what stays
open. -/
theorem not_TerminatesOnSat : ¬ TerminatesOnSat := by
  intro h
  obtain ⟨N, hN⟩ := h SatDiverge.W2 SatDiverge.rho2 SatDiverge.W2_models
  obtain ⟨n, G, hrun, hlt⟩ := SatDiverge.W2_unbounded N
  exact absurd (hN n G hrun) (by omega)

/-! ## 6. Names travel with their groups

The mechanism by which a SATURATING run avoids the engine of §2-3.  If `n` names the group
of `c` through the bare definition `d₀ := n <- (vset c)`, and a bare link `x <- (y)` with
`x ∈ vset c` is available, then substituting the link into `d₀` is a shipped step whose
conclusion is the bare `n <- ((vset c).erase x ∪ {y})` -- which names exactly the group that
substituting the same link into `c` produces.  In the round of §2 (`c := p <- (e1, e2, (|K|))`,
`n := u₁`, `x := e2`, `y := u`) that group is `{e1, u}`, so a run that also performs THIS
substitution has `Named G {e1, u}` and the split of step 3 is not enabled.

This is a lemma about ONE substitution, not a termination theorem: it says nothing about
whether a saturating run is bounded ("Conjecture S"), only that the particular run of §2
is not substitution-closed. -/

/-- **Name travel.**  Substituting a bare link `x <- (y)` into the bare definition
`n <- (vset c)` is a shipped step, and afterwards `n` names the group substitution would
give `c`. -/
theorem subst_names_travel {G : System} {c : Constraint} {n x y : Var}
    (hd₀ : mk n (vset c) ∅ ∈ G) (hd : mk x {y} ∅ ∈ G) (hx : x ∈ vset c) :
    SubstStep G (substResult G (mk n (vset c) ∅) (mk x {y} ∅)) ∧
      Names (substResult G (mk n (vset c) ∅) (mk x {y} ∅)) n
        (vset (mk c.lhs ((vset c).erase x ∪ {y}) c.conc)) := by
  refine ⟨SubstStep.intro ⟨hd₀, hd, by rw [lhs_mk, vset_mk]; exact hx⟩, ?_⟩
  refine ⟨_, Finset.mem_insert_self _ _, rfl, ?_, ?_⟩
  · simp only [vset_mk, lhs_mk]
  · simp only [conc_mk, Finset.union_empty]

end Rowpartition
