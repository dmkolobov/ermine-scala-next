/-
# NameLossClosed -- the concretise-first system is CLOSED under the non-generative rules

`NameLoss` shows that concretising `u` before the fold deletes the name `u <- (x, y)`, and
that the concretised system is exactly the input plus `u <- ((|c|))` (`orderB_eq`).  It
shows the fact `t <- ((|c|), z)` is not THERE (`orderB_lacks_fact`).  This file shows it is
not REACHABLE either: no sequence of non-generative steps (`-Dermine.genRules=cut` minus
the two minting rules, which the single-pass loop never re-runs on this input) from the
concretise-first system ever produces the fact, the goal `t <- ((|c, d|))`, or a name for
the pair `x ++ y`.

The proof is a closure argument.  The saturated set the Scala solver reaches in the failing
order, read off the step trace, is the eight partitions

    R <- ((|k, c|))   R <- ((|k|), x, y)   D <- ((|d|))   D <- (x, z)   t <- (x, y, z)
    u <- ((|c|))      t <- (y, D)          t <- ((|d|), y)

-- the last two being the CSE fold of `D <- (x, z)` against `t <- (x, y, z)` and the
substitution of `D <- ((|d|))` into it.  The Lean `CutStep.reuse` rule also emits the
degenerate second conclusion `D <- (D)` (the reduce of the name against itself), which the
Scala drops; it is included so that the set is literally closed.  `Cl_closed` checks, rule
by rule and premise pair by premise pair, that every non-generative step from `Cl` lands
inside `Cl`; `NonGenStep.mono` lifts steps along inclusion; `reach_subset_Cl` iterates.

## Contents

* §1  `Cl`, the closed set, and `mem_Cl_iff`.
* §2  Per-rule closure: `cancel_closed`, `subst_closed`, `selfSubst_closed`,
      `commonPart_closed`, `splitReuse_closed`, `fold_closed`, `reuse_closed`; assembled
      into `Cl_closed`.
* §3  Monotonicity (`NonGenStep.mono`) and reachability (`reach_subset_Cl`).
* §4  The concretise-first system is inside `Cl` (`orderB_subset_Cl`); hence
      `orderB_stuck`: no non-generative derivation from it reaches the fact, the goal, or a
      name for `x ++ y`.  `keep_vs_delete` states the contrast with `keep_recovers_fact`.
-/
import Rowpartition.NameLoss

namespace Rowpartition
namespace NameLoss

/-! ## 1. The closed set -/

/-- `D <- (D)`: the degenerate second conclusion of `CutStep.reuse` on `(D <- (x, z),
t <- (x, y, z))` with name `D` -- the reduce of the name against itself. -/
def dSelf : Constraint := mk D {D} ∅

/-- The saturated set the solver reaches in the concretise-first order (plus `dSelf`). -/
def Cl : System := {rConc, rDef, dConc, dDef, tDef, uConc, tFold, tD, dSelf}

/-- The closed-term recipe of `NameLoss.nl_decide`, with this file's constraints added to
the unfolding set. -/
macro "nlc_decide" : tactic => `(tactic|
  ((try simp [t, x, y, z, R, D, u, fk, fc, fd, G₀, rConc, rDef, dConc, dDef, tDef, uName,
      rSplit, uConc, tReuse, tFact, tGoal, tFold, tD, dSelf, Cl, absorbC, reduce, shared,
      Named, Names, allVars, mk_eq_iff, vset_mk, conc_mk, lhs_mk, Finset.subset_iff])
   <;> decide))

/-- Membership in `Cl`, as a nine-way disjunction ready for `rcases`. -/
theorem mem_Cl_iff {c : Constraint} :
    c ∈ Cl ↔ c = rConc ∨ c = rDef ∨ c = dConc ∨ c = dDef ∨ c = tDef ∨ c = uConc ∨
      c = tFold ∨ c = tD ∨ c = dSelf := by
  simp only [Cl, Finset.mem_insert, Finset.mem_singleton]

/-! ## 2. Closure, rule by rule

Each lemma takes the premises of one rule with the system fixed to `Cl` and shows the
constraint the rule emits is in `Cl`.  The premises are memberships, which `mem_Cl_iff`
expands into the nine constraints; every resulting case is closed, and `nlc_decide` settles
it.  The lone free variable of `CancelApp` (the left-over `z`) and of `SelfSubstApp` (the
emptied `v`) is pinned by its membership in a literal variable set. -/

/-- Cancellation from `Cl` stays in `Cl`.  The enabled instances are `(t <- (y, D),
t <- (x, y, z))` giving `D <- (x, z)`, `(t <- (y, D), t <- ((|d|), y))` giving
`D <- ((|d|))`, and the two with `D <- (D)` as first premise giving back `D <- (x, z)` and
`D <- ((|d|))`. -/
theorem cancel_closed {c d : Constraint} {v : Var} (h : CancelApp Cl c d v) :
    mk v (vset d \ vset c) (d.conc \ c.conc) ∈ Cl := by
  obtain ⟨hc, hd, hlhs, hconc, hlone⟩ := h
  have hv : v ∈ vset c := by
    have : v ∈ vset c \ vset d := by rw [hlone]; exact Finset.mem_singleton_self v
    exact (Finset.mem_sdiff.mp this).1
  rw [mem_Cl_iff] at hc hd
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  rcases hd with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hlhs hconc hlone
   simp [t, x, y, z, R, D, u, rConc, rDef, dConc, dDef, tDef, uConc, tFold, tD, dSelf] at hv) <;>
  rcases hv with rfl | rfl | rfl <;> nlc_decide

/-- Substitution from `Cl` stays in `Cl`.  The only variable that occurs on a right-hand
side and is defined is `D`, in `t <- (y, D)` and `D <- (D)`; substituting each of its three
definitions gives `t <- ((|d|), y)`, `t <- (x, y, z)`, `t <- (y, D)` and `D <- ((|d|))`,
`D <- (x, z)`, `D <- (D)`. -/
theorem subst_closed {c d : Constraint} (h : SubstApp Cl c d) :
    mk c.lhs ((vset c).erase d.lhs ∪ vset d) (c.conc ∪ d.conc) ∈ Cl := by
  obtain ⟨hc, hd, hocc⟩ := h
  rw [mem_Cl_iff] at hc hd
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  rcases hd with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hocc; nlc_decide)

/-- Self-substitution is not enabled at `Cl`: the only constraint whose left-hand variable
occurs on its right is `D <- (D)`, and it has no OTHER variable to empty. -/
theorem selfSubst_closed {c : Constraint} {v : Var} (h : SelfSubstApp Cl c v) :
    mk v ∅ ∅ ∈ Cl := by
  obtain ⟨hc, hself, hconc, hv, hne⟩ := h
  rw [mem_Cl_iff] at hc
  exfalso
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hself hconc hne
   simp [t, x, y, z, R, D, u, rConc, rDef, dConc, dDef, tDef, uConc, tFold, tD, dSelf] at hv) <;>
  rcases hv with rfl | rfl | rfl <;> nlc_decide

/-- Common partition is not enabled at `Cl`: no two constraints with distinct left-hand
sides have the same right-hand side. -/
theorem commonPart_closed {c d : Constraint} (h : CommonPartApp Cl c d) :
    mk c.lhs {d.lhs} ∅ ∈ Cl := by
  obtain ⟨hc, hd, hne, hvs, hk⟩ := h
  rw [mem_Cl_iff] at hc hd
  exfalso
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  rcases hd with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hne hvs hk; nlc_decide)

/-- `splitConcrete`'s reuse branch is not enabled at `Cl`: the only constraint with a
nonempty concrete part and two abstract variables is `R <- ((|k|), x, y)`, and nothing in
`Cl` names `{x, y}` -- that is the deleted name. -/
theorem splitReuse_closed {c : Constraint} {w : Var} (h : SplitReuseApp Cl c w) :
    mk c.lhs {w} c.conc ∈ Cl := by
  obtain ⟨hc, hconc, h2, hn⟩ := h
  obtain ⟨d, hd, rfl, hvs, hdc⟩ := hn
  rw [mem_Cl_iff] at hc hd
  exfalso
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  rcases hd with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hconc h2 hvs hdc; nlc_decide)

/-- The CSE fold from `Cl` stays in `Cl`: the one enabled instance is `D <- (x, z)` against
`t <- (x, y, z)`, which gives `t <- (y, D)`. -/
theorem fold_closed {c₁ c₂ : Constraint} (hp : CsePair Cl c₁ c₂)
    (hvs : vset c₁ = shared c₁ c₂) (hk : c₁.conc = ∅) :
    reduce c₂ (shared c₁ c₂) c₁.lhs ∈ Cl := by
  obtain ⟨hc₁, hc₂, hne, hcard⟩ := hp
  rw [mem_Cl_iff] at hc₁ hc₂
  rcases hc₁ with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  rcases hc₂ with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hne hcard hvs hk; nlc_decide)

/-- The CSE reuse from `Cl` stays in `Cl`: the pairs sharing two variables across distinct
left-hand sides are `(R <- ((|k|), x, y), t <- (x, y, z))`, whose shared `{x, y}` is
unnamed, and `(D <- (x, z), t <- (x, y, z))`, whose shared `{x, z}` is named by `D`;
the latter gives `D <- (D)` and `t <- (y, D)`. -/
theorem reuse_closed {c₁ c₂ : Constraint} {w : Var} (hp : CsePair Cl c₁ c₂)
    (hn : Names Cl w (shared c₁ c₂)) :
    reduce c₁ (shared c₁ c₂) w ∈ Cl ∧ reduce c₂ (shared c₁ c₂) w ∈ Cl := by
  obtain ⟨hc₁, hc₂, hne, hcard⟩ := hp
  obtain ⟨d, hd, rfl, hvs, hdc⟩ := hn
  rw [mem_Cl_iff] at hc₁ hc₂ hd
  rcases hc₁ with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  rcases hc₂ with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (try (exfalso; revert hne hcard; nlc_decide)) <;>
  rcases hd with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  (revert hne hcard hvs hdc; nlc_decide)

/-- **`Cl` is closed under every non-generative rule.** -/
theorem Cl_closed {G' : System} (h : NonGenStep Cl G') : G' ⊆ Cl := by
  cases h with
  | cse h =>
    cases h with
    | reuse hp hn =>
      obtain ⟨h1, h2⟩ := reuse_closed hp hn
      exact Finset.insert_subset_iff.mpr
        ⟨h1, Finset.insert_subset_iff.mpr ⟨h2, Finset.Subset.refl _⟩⟩
    | fold hp hvs hk =>
      exact Finset.insert_subset_iff.mpr ⟨fold_closed hp hvs hk, Finset.Subset.refl _⟩
  | split h =>
    cases h with
    | intro ha => exact Finset.insert_subset_iff.mpr ⟨splitReuse_closed ha, Finset.Subset.refl _⟩
  | cancel h =>
    cases h with
    | intro ha => exact Finset.insert_subset_iff.mpr ⟨cancel_closed ha, Finset.Subset.refl _⟩
  | subst h =>
    cases h with
    | intro ha => exact Finset.insert_subset_iff.mpr ⟨subst_closed ha, Finset.Subset.refl _⟩
  | selfSubst h =>
    cases h with
    | intro ha => exact Finset.insert_subset_iff.mpr ⟨selfSubst_closed ha, Finset.Subset.refl _⟩
  | commonPart h =>
    cases h with
    | intro ha =>
      exact Finset.insert_subset_iff.mpr ⟨commonPart_closed ha, Finset.Subset.refl _⟩

/-! ## 3. Monotonicity and reachability -/

/-- The premise pattern of CSE is monotone in the system. -/
theorem csePair_mono {G H : System} (hGH : G ⊆ H) {c₁ c₂ : Constraint}
    (h : CsePair G c₁ c₂) : CsePair H c₁ c₂ :=
  ⟨hGH h.mem₁, hGH h.mem₂, h.lhs_ne, h.two_le⟩

/-- The naming lookup is monotone in the system. -/
theorem names_mono {G H : System} (hGH : G ⊆ H) {w : Var} {S : Finset Var}
    (h : Names G w S) : Names H w S :=
  let ⟨d, hd, h1, h2, h3⟩ := h
  ⟨d, hGH hd, h1, h2, h3⟩

/-- **Non-generative steps lift along inclusion**: every premise is a membership or an
equation between components, and every result is `insert r G`. -/
theorem NonGenStep.mono {G H G' : System} (hGH : G ⊆ H) (h : NonGenStep G G') :
    ∃ H', NonGenStep H H' ∧ G' ⊆ H' := by
  cases h with
  | cse h =>
    cases h with
    | reuse hp hn =>
      exact ⟨_, NonGenStep.cse (CutStep.reuse (csePair_mono hGH hp) (names_mono hGH hn)),
        Finset.insert_subset_insert _ (Finset.insert_subset_insert _ hGH)⟩
    | fold hp hvs hk =>
      exact ⟨_, NonGenStep.cse (CutStep.fold (csePair_mono hGH hp) hvs hk),
        Finset.insert_subset_insert _ hGH⟩
  | split h =>
    cases h with
    | intro ha =>
      exact ⟨_, NonGenStep.split (SplitReuseStep.intro
        ⟨hGH ha.mem, ha.conc_ne, ha.two_le, names_mono hGH ha.names⟩),
        Finset.insert_subset_insert _ hGH⟩
  | cancel h =>
    cases h with
    | intro ha =>
      exact ⟨_, NonGenStep.cancel (CancelStep.intro
        ⟨hGH ha.mem₁, hGH ha.mem₂, ha.same_lhs, ha.conc_le, ha.lone⟩),
        Finset.insert_subset_insert _ hGH⟩
  | subst h =>
    cases h with
    | intro ha =>
      exact ⟨_, NonGenStep.subst (SubstStep.intro ⟨hGH ha.mem₁, hGH ha.mem₂, ha.occurs⟩),
        Finset.insert_subset_insert _ hGH⟩
  | selfSubst h =>
    cases h with
    | intro ha =>
      exact ⟨_, NonGenStep.selfSubst (SelfSubstStep.intro
        ⟨hGH ha.mem, ha.self, ha.conc_empty, ha.mem_v, ha.ne⟩),
        Finset.insert_subset_insert _ hGH⟩
  | commonPart h =>
    cases h with
    | intro ha =>
      exact ⟨_, NonGenStep.commonPart (CommonPartStep.intro
        ⟨hGH ha.mem₁, hGH ha.mem₂, ha.lhs_ne, ha.vset_eq, ha.conc_eq⟩),
        Finset.insert_subset_insert _ hGH⟩

/-- **Everything reachable by non-generative steps from inside `Cl` is inside `Cl`.** -/
theorem reach_subset_Cl {n : ℕ} {G G' : System} (hG : G ⊆ Cl) (h : NonGenSteps n G G') :
    G' ⊆ Cl := by
  induction h with
  | refl G => exact hG
  | tail _ hstep ih =>
    obtain ⟨H', hH', hsub⟩ := NonGenStep.mono (ih hG) hstep
    exact hsub.trans (Cl_closed hH')

/-! ## 4. The concretise-first system is stuck -/

/-- The input plus `u <- ((|c|))` is inside `Cl`. -/
theorem insert_uConc_G₀_subset_Cl : insert uConc G₀ ⊆ Cl := by
  intro c hc
  simp only [G₀, Finset.mem_insert, Finset.mem_singleton] at hc
  rw [mem_Cl_iff]
  rcases hc with rfl | rfl | rfl | rfl | rfl | rfl <;> simp

/-- The concretise-first system is inside `Cl`. -/
theorem orderB_subset_Cl : concretize u {fc} Grace ⊆ Cl :=
  orderB_subset.trans insert_uConc_G₀_subset_Cl

theorem tFact_not_mem_Cl : tFact ∉ Cl := by nlc_decide
theorem tGoal_not_mem_Cl : tGoal ∉ Cl := by nlc_decide
theorem not_named_Cl : ¬ Named Cl {x, y} := by nlc_decide

/-- **Concretise first, and no non-generative derivation ever recovers**: from the
concretise-first system, no sequence of non-generative steps reaches the fact
`t <- ((|c|), z)`, the goal `t <- ((|c, d|))`, or a name for the pair `x ++ y`. -/
theorem orderB_stuck {n : ℕ} {G' : System} (h : NonGenSteps n (concretize u {fc} Grace) G') :
    tFact ∉ G' ∧ tGoal ∉ G' ∧ ¬ Named G' {x, y} := by
  have hsub : G' ⊆ Cl := reach_subset_Cl orderB_subset_Cl h
  exact ⟨fun hm => tFact_not_mem_Cl (hsub hm), fun hm => tGoal_not_mem_Cl (hsub hm),
    fun hn => not_named_Cl (hn.mono hsub)⟩

/-- **The contrast.**  With the definition kept, two non-generative steps reach the fact
(`keep_recovers_fact`); with it deleted, no number of them does. -/
theorem keep_vs_delete :
    (∃ n G', NonGenSteps n (concretizeKeep u {fc} Grace) G' ∧ tFact ∈ G') ∧
    (∀ n G', NonGenSteps n (concretize u {fc} Grace) G' → tFact ∉ G') :=
  ⟨⟨2, _, keep_recovers_fact, Finset.mem_insert_self _ _⟩, fun _ _ h => (orderB_stuck h).1⟩

end NameLoss
end Rowpartition
