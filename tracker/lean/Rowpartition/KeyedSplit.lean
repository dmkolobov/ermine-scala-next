/-
# Keying `splitConcrete`'s guard on `(left-hand side, concrete part)`

`DefaultSatDiverge.lean` refutes `TerminatesOnSat`: the shipped ADDITIVE rule set
`DefaultStep` admits productive runs of every length from the satisfiable two-constraint
system `SatDiverge.W2`.  `DefaultTerm.lean` §9 had already isolated where the argument
breaks: nothing bounds SPLIT BRANCHING, the number of children a single variable can
acquire through `splitConcrete`'s mint.  This file changes the mint's GUARD so that the
bound exists, and proves it.

## The two guards, side by side

`splitConcrete` fires on a premise `p <- (S, K)` with `K ≠ ∅` and `2 ≤ |S|`.  What differs
is the reverse lookup it consults before minting a name for `S`:

```
SYNTACTIC (shipped, Cut.SplitApp)         KEYED (this file, KSplitApp)
  ¬ Named G S                               ¬ Resolved G p K
  "no constraint of G is a bare d <- S"     "no constraint of G is p <- (z, K)"
```

The syntactic guard is keyed on the GROUP, and groups can be manufactured without end:
`W2`'s engine cancels, substitutes, and hands the split a group `{e1, u}` it has never
seen, once per round, for ever.  The keyed guard is keyed on the pair `(p, K)` — and under
a model the minted variable's row is FORCED by that pair alone,

    p <- (u, K)   forces   rho u = rho p \ K,

so all the names the syntactic guard mints for `p` at the same `K` denote the SAME row
(`ResGuard.resolvent_unique`).  This is precisely the guard `ResGuard.lean` gives
`resolution`, and `ResGuardTerm.lean` proves it enough for termination on satisfiable
input.  The keyed split witness `mk p {u} K` even has the same SHAPE as resolution's, so
`ResGuardTerm.unfired` — the number of keys `K ⊆ L` still open at `p` — is the budget for
BOTH mints, and one measure covers the whole calculus.

The keyed rule, in full:

```
KSplitApp G c u   (mint)   c ∈ G,  c.conc ≠ ∅,  2 ≤ |vset c|,
                           ¬ Resolved G c.lhs c.conc,  u ∉ allVars G
      emits   u <- (vset c)          and   c.lhs <- (u, c.conc)      (= Cut.splitResult)

KSplitReuseApp G c u       c ∈ G,  c.conc ≠ ∅,  2 ≤ |vset c|,
                           mk c.lhs {u} c.conc ∈ G
      emits   u <- (vset c)                                          (= kSplitReuseResult)
```

The reuse branch gives the EXISTING name the new group as a definition.  That is sound
because `p <- (S, K)` and `p <- (u, K)` together force `rho u = S.biUnion rho`
(`ksplit_reuse_sat`), so the branch is pure entailment, exactly as `ResGuard.reuse_sat` is
for resolution.

## What is proved

* **§1-2** `KSplitApp`, `KSplitReuseApp`, `kSplitReuseResult`, `KSplitStep`.  Soundness:
  `ksplit_reuse_sat`, `KSplitStep.reuse_models_iff` (the reuse branch does not move the
  model set at all), `ksplit_extend` / `ksplit_mint_conservativeExt` (the mint branch is a
  conservative extension at the fresh name), `KSplitStep.satisfiable_iff`.  So the keyed
  guard is not a semantic change, only a change of when the rule fires.
* **§3** `KDefaultStep` = `NonGenStep` + `KSplitStep` + `GResStep`, the shipped calculus
  with the split guard rekeyed; `KRun` (productive runs); `TerminatesOnSatKeyed`.
* **§4** The measure.  `gmeas` of `ResGuardTerm` — each variable's remaining key budget
  weighted by `(2 ^ |L| + 1) ^ (row cardinality)` — decreases strictly at BOTH mints
  (`KSplitStep.mint_gmeas_lt`, `GResStep.mint_gmeas_lt`) and never increases elsewhere
  (`gmeas_le_of_allVars_eq`).  `KRun.invariant`, `KRun.allVars_card_le`.
* **§5** `KRun.length_le`, `keyed_terminates_of_satisfiable`, `terminatesOnSatKeyed`, and
  the contrast `keyed_vs_syntactic : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSat`.  §5.1 checks
  the bound is not vacuous: both minting branches still fire (`kRun_one_resSeed`,
  `keyed_mint_fires`).
* **§6** Non-vacuity on the very counterexample.  `W2` itself carries `p <- (e2, (|k|))`, so
  the keyed guard is closed on it from the start: ROUND 0 is refused
  (`SatDiverge.W2_not_keyed_mint0`) and the keyed calculus reuses instead
  (`SatDiverge.W2_keyed_reuse0`, `SatDiverge.kRun_one_W2`), emitting the self-partition
  `e2 <- (e1, e2)` from which self-substitution derives `e1 <- ()` -- the forced-empty
  variable the whole engine runs on (`SatDiverge.W2_keyed_reuse0_selfSubst`).  And at the
  system the engine reaches after cancellation and substitution, the keyed guard REFUSES the
  round's mint (`SatDiverge.W2_keyed_no_second_mint`) because `p <- (u1, K)` is present,
  taking a reuse instead (`SatDiverge.W2_keyed_reuse`), whose conclusion `u1 <- (e1, u1)` is
  again a self-partition (`SatDiverge.W2_keyed_reuse_selfSubst`).
  `SatDiverge.W2_keyed_bound` states the bound on the same input the syntactic guard
  diverges on.

## Scope

**This is a theorem about the ADDITIVE relation, hence about every loop order.**  `KRun`
quantifies over all productive runs of `KDefaultStep` in any order, with no deletion and no
fairness assumption — the same quantifier that makes `not_TerminatesOnSat` a real
refutation.  That is what distinguishes it from the defences the shipped loop actually
relies on (name travel, eager unification of singleton links, eager `makeEmpty`), each of
which is a property of an ORDER and none of which is stated by any relation here.

**Ill-typed input is untouched.**  `KDefaultStep` still contains guarded resolution, and
guarded resolution diverges on the UNSATISFIABLE `ResGuardDiverge.gSeed`
(`gSeed_diverges`); `keyed_terminates_of_satisfiable` needs a model and there is none.  The
dichotomy of `ResGuardTerm`'s Summary is unchanged: terminates on satisfiable input, not in
general.

**`DefaultStep` is NOT a sub-relation of `KDefaultStep`.**  Every syntactically-guarded
mint that also passes the keyed guard is a keyed mint (`KSplitStep.mint_of_splitApp`), but
the converse fails in both directions: where the syntactic guard mints and the key is
already resolved, the keyed calculus REUSES (`KSplitApp.reuse_of_splitApp`), and
`split_mint_not_keyed` exhibits that situation concretely inside `W2`'s engine.  So this
file bounds a DIFFERENT relation, not a sub-relation of the shipped one; it says what
changing the guard would buy, and nothing about the guard as shipped.

**The flag is implemented and ADOPTED (Stage 2, 2026-09-03): `ermine.splitKey`, DEFAULT
ON; `-Dermine.splitKey=false` restores the syntactic guard.**  `Constraints.splitConcrete`
consults `learnPartitions`' resolvent lookup — `Resolved` restricted to the premise's lhs —
before a split mint and, on a hit, emits `kSplitReuseResult` instead; the correspondence is
written at the rule.  Measured in `tracker/satterm/KEYED-SPLIT-STAGE2.md`.  So `KDefaultStep`
is now the shipped additive rule set and `DefaultStep` the previous one.
-/
import Rowpartition.DefaultSatDiverge

namespace Rowpartition

/-! ## 1. The keyed split rule -/

/-- **The premises of the keyed MINT.**  Identical to `Cut.SplitApp` except that the
reverse lookup asks about the RESOLVENT KEY `(c.lhs, c.conc)` rather than about the group
`vset c`: mint only if no constraint of `G` already names `c.lhs \ c.conc`. -/
structure KSplitApp (G : System) (c : Constraint) (u : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- **the keyed reverse lookup missed**: nothing names `c.lhs \ c.conc` yet -/
  unresolved : ¬ Resolved G c.lhs c.conc
  /-- `u` is a genuinely fresh variable -/
  fresh : u ∉ allVars G

/-- **The premises of the keyed REUSE.**  The key is closed: `G` already carries
`c.lhs <- (u, c.conc)`, so `u` already denotes the row the mint would have named.  The
branch gives `u` the new group as a definition. -/
structure KSplitReuseApp (G : System) (c : Constraint) (u : Var) : Prop where
  /-- the premise is in the system -/
  mem : c ∈ G
  /-- `C+` is nonempty -/
  conc_ne : c.conc ≠ ∅
  /-- the guard `abstr.size >= 2` -/
  two_le : 2 ≤ (vset c).card
  /-- **the keyed reverse lookup hit**: `u` already names `c.lhs \ c.conc` -/
  witness : mk c.lhs {u} c.conc ∈ G

/-- The single constraint the keyed REUSE emits: the existing name's new definition. -/
def kSplitReuseResult (G : System) (c : Constraint) (u : Var) : System :=
  insert (mk u (vset c) ∅) G

theorem subset_kSplitReuseResult (G : System) (c : Constraint) (u : Var) :
    G ⊆ kSplitReuseResult G c u := fun _ hd => Finset.mem_insert_of_mem hd

/-- The name the reuse branch reuses is an existing variable. -/
theorem KSplitReuseApp.name_mem_allVars {G : System} {c : Constraint} {u : Var}
    (h : KSplitReuseApp G c u) : u ∈ allVars G :=
  mem_allVars h.witness (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self u))

/-- **The keyed split rule.**  `mint` emits exactly what `Cut.SplitStep` emits; only the
guard differs.  `reuse` is the branch the keyed guard opens. -/
inductive KSplitStep : System → System → Prop
  | mint {G : System} {c : Constraint} {u : Var} :
      KSplitApp G c u → KSplitStep G (splitResult G c u)
  | reuse {G : System} {c : Constraint} {u : Var} :
      KSplitReuseApp G c u → KSplitStep G (kSplitReuseResult G c u)

theorem KSplitStep.subset {G G' : System} (h : KSplitStep G G') : G ⊆ G' := by
  cases h with
  | @mint c u _ => exact subset_splitResult _ _ _
  | @reuse c u _ => exact subset_kSplitReuseResult _ _ _

/-! ## 2. Soundness: the keyed guard is not a semantic change -/

/-- Every satisfied constraint satisfies its own canonical form.  (The converse is false in
general -- `Constraint.vars` is a list -- but this direction is all that is ever needed,
and it lets the lemmas below be stated on `mk`-shaped constraints while being applied to
arbitrary premises.) -/
theorem sat_mk_of_sat {rho : Assign} {c : Constraint} (h : Sat rho c) :
    Sat rho (mk c.lhs (vset c) c.conc) :=
  (sat_mk_iff _ _ _ _).mpr ⟨h.eq_biUnion, fun _ hv => h.disjoint_conc' hv,
    fun _ hv _ hw hvw => h.disjoint_of_ne' hv hw hvw⟩

/-- **The core lemma of the keyed reuse branch.**  If `G` carries both `p <- (S, K)` and
`p <- (u, K)`, then the bare `u <- (S)` holds under the SAME assignment: both constraints
say `rho p` splits as `K` plus a disjoint remainder, so `rho u = rho p \ K = S.biUnion rho`.
This is the split analogue of `ResGuard.reuse_sat`. -/
theorem ksplit_reuse_sat {rho : Assign} {p u : Var} {S : Finset Var} {K : Row}
    (h₁ : Sat rho (mk p S K)) (h₂ : Sat rho (mk p {u} K)) : Sat rho (mk u S ∅) := by
  rw [sat_mk_iff] at h₁
  rw [sat_lone_iff] at h₂
  obtain ⟨he₁, hk₁, hd₁⟩ := h₁
  obtain ⟨he₂, hdu⟩ := h₂
  have hun : K ∪ rho u = K ∪ S.biUnion rho := he₂.symm.trans he₁
  have key : rho u = S.biUnion rho := by
    ext l
    have e : l ∈ K ∪ rho u ↔ l ∈ K ∪ S.biUnion rho := by rw [hun]
    simp only [Finset.mem_union] at e
    have hKu : l ∈ K → l ∉ rho u := fun hh => Finset.disjoint_left.mp hdu hh
    have hKS : l ∈ K → l ∉ S.biUnion rho := fun hh hb => by
      obtain ⟨v, hv, hlv⟩ := Finset.mem_biUnion.mp hb
      exact Finset.disjoint_left.mp (hk₁ v hv) hh hlv
    tauto
  rw [sat_mk_iff]
  exact ⟨by rw [Finset.empty_union, key], fun v _ => by simp, hd₁⟩

/-- **The keyed reuse branch is entailment.** -/
theorem ksplit_reuse_entails {G : System} {c : Constraint} {u : Var}
    (happ : KSplitReuseApp G c u) : SEntails G (mk u (vset c) ∅) := fun _ hm =>
  ksplit_reuse_sat (sat_mk_of_sat (hm c happ.mem)) (hm _ happ.witness)

/-- **The keyed reuse branch does not move the model set at all.**  Not merely
"equisatisfiable": the same assignments model the system before and after. -/
theorem KSplitStep.reuse_models_iff {G : System} {c : Constraint} {u : Var}
    (happ : KSplitReuseApp G c u) (rho : Assign) :
    SModels rho (kSplitReuseResult G c u) ↔ SModels rho G := by
  constructor
  · exact SModels.mono (subset_kSplitReuseResult _ _ _)
  · intro hm d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · exact ksplit_reuse_entails happ rho hm
    · exact hm d hd

/-- **The keyed mint extends every model**, by the forced value.  This is
`DefaultTerm.split_extend` with the syntactic guard dropped from the hypotheses: the
extension depends only on the premise's membership and the freshness of the name. -/
theorem ksplit_extend {G : System} {c : Constraint} {u : Var} (hmem : c ∈ G)
    (hfresh : u ∉ allVars G) {rho : Assign} (hm : SModels rho G) :
    SModels (setVar rho u ((vset c).biUnion rho)) (splitResult G c u) := by
  have hc := hm c hmem
  have hu : u ∉ vset c := fun hh => hfresh (mem_allVars hmem (Or.inr hh))
  have hul : u ≠ c.lhs := fun hh => hfresh (hh ▸ lhs_mem_allVars hmem)
  intro d hd
  simp only [splitResult, Finset.mem_insert] at hd
  rcases hd with rfl | rfl | hd
  · exact sat_name hc (Finset.Subset.refl _) hu
  · rw [← reduce_self]
    exact sat_reduce hc (Finset.Subset.refl _) hu hul
  · exact sModels_setVar hfresh _ hm d hd

/-- **The keyed mint is a conservative extension** at the minted name
(`SplitNecessary.split_mint_conservativeExt` with the syntactic guard dropped). -/
theorem ksplit_mint_conservativeExt {G : System} {c : Constraint} {u : Var}
    (happ : KSplitApp G c u) : SConservativeExt G u (splitResult G c u) :=
  ⟨fun rho hm => ⟨setVar rho u ((vset c).biUnion rho), fun _ hv => setVar_of_ne rho _ hv,
      ksplit_extend happ.mem happ.fresh hm⟩,
    fun _ hm => SModels.mono (subset_splitResult _ _ _) hm⟩

/-- **A keyed split step preserves satisfiability in both directions.** -/
theorem KSplitStep.satisfiable_iff {G G' : System} (h : KSplitStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | @mint c u happ => exact SConservativeExt.satisfiable_iff (ksplit_mint_conservativeExt happ)
  | @reuse c u happ =>
    constructor
    · rintro ⟨rho, hm⟩; exact ⟨rho, (KSplitStep.reuse_models_iff happ rho).mpr hm⟩
    · rintro ⟨rho, hm⟩; exact ⟨rho, SModels.mono (subset_kSplitReuseResult _ _ _) hm⟩

/-! ### 2.1 How the keyed guard relates to the syntactic one

The two guards are incomparable, and the honest statements are these two. -/

/-- **A syntactically-guarded mint that also passes the keyed guard is a keyed mint.**  The
emitted constraints are literally the same (`Cut.splitResult`). -/
theorem KSplitStep.mint_of_splitApp {G : System} {c : Constraint} {u : Var}
    (happ : SplitApp G c u) (hg : ¬ Resolved G c.lhs c.conc) :
    KSplitStep G (splitResult G c u) :=
  KSplitStep.mint ⟨happ.mem, happ.conc_ne, happ.two_le, hg, happ.fresh⟩

/-- **...and where it does not, the keyed calculus reuses instead of minting.**  So
`DefaultStep` is not a sub-relation of `KDefaultStep`: on such a premise the shipped rule
set mints a fresh name and the keyed one does not.  `split_mint_not_keyed` exhibits the
situation concretely, inside the engine of `DefaultSatDiverge`. -/
theorem KSplitApp.reuse_of_splitApp {G : System} {c : Constraint} {u : Var}
    (happ : SplitApp G c u) (hg : Resolved G c.lhs c.conc) :
    ∃ z, KSplitReuseApp G c z := by
  obtain ⟨z, hz⟩ := (resolved_iff G c.lhs c.conc).mp hg
  exact ⟨z, ⟨happ.mem, happ.conc_ne, happ.two_le, hz⟩⟩

/-! ## 3. The keyed calculus -/

/-- **The shipped rule set with the split guard rekeyed**: every non-generative rule
(`NonGenStep`), the KEYED `splitConcrete` (`KSplitStep`, both branches), and guarded
`resolution` (`GResStep`, both branches).  This is `DefaultDiverge.DefaultStep` with
`Cut.SplitStep` replaced by `KSplitStep`.

Like `DefaultStep` it is the ADDITIVE relation -- "one rule can fire on `G` and add its
conclusions" -- and not the single-pass `incorporateAll` loop. -/
inductive KDefaultStep : System → System → Prop
  | nongen {G G' : System} : NonGenStep G G' → KDefaultStep G G'
  | split {G G' : System} : KSplitStep G G' → KDefaultStep G G'
  | gres {G G' : System} : GResStep G G' → KDefaultStep G G'

theorem KDefaultStep.subset {G G' : System} (h : KDefaultStep G G') : G ⊆ G' := by
  cases h with
  | nongen h => exact h.subset
  | split h => exact h.subset
  | gres h => exact h.subset

/-- Every keyed rule preserves satisfiability in both directions. -/
theorem KDefaultStep.satisfiable_iff {G G' : System} (h : KDefaultStep G G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') := by
  cases h with
  | nongen h => exact exists_congr h.models_iff
  | split h => exact h.satisfiable_iff
  | gres h => exact h.satisfiable_iff.symm

/-! ### 3.1 No keyed rule invents a label -/

theorem KSplitStep.concSub {L : Finset Label} {G G' : System} (h : KSplitStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | @mint c u happ =>
    intro d hd
    simp only [splitResult, Finset.mem_insert] at hd
    rcases hd with rfl | rfl | hd
    · rw [conc_mk]; exact Finset.empty_subset _
    · rw [conc_mk]; exact hcs c happ.mem
    · exact hcs d hd
  | @reuse c u _ =>
    intro d hd
    rcases Finset.mem_insert.mp hd with rfl | hd
    · rw [conc_mk]; exact Finset.empty_subset _
    · exact hcs d hd

theorem KDefaultStep.concSub {L : Finset Label} {G G' : System} (h : KDefaultStep G G')
    (hcs : ConcSub L G) : ConcSub L G' := by
  cases h with
  | nongen h => exact (DefaultStep.nongen h).concSub hcs
  | split h => exact h.concSub hcs
  | gres h => exact (DefaultStep.gres h).concSub hcs

/-! ### 3.2 What the keyed rules do to the vocabulary -/

/-- **The keyed reuse adds no variable at all**: the name it defines is already there. -/
theorem allVars_kSplitReuseResult {G : System} {c : Constraint} {u : Var}
    (happ : KSplitReuseApp G c u) : allVars (kSplitReuseResult G c u) = allVars G := by
  refine allVars_insert_eq_of_subset ?_
  intro v hv
  simp only [lhs_mk, vset_mk, Finset.mem_insert] at hv
  rcases hv with rfl | hv
  · exact happ.name_mem_allVars
  · exact vset_subset_allVars happ.mem hv

theorem KSplitStep.allVars_cases {G G' : System} (h : KSplitStep G G') :
    allVars G' = allVars G ∨ ∃ z, z ∉ allVars G ∧ allVars G' = insert z (allVars G) := by
  cases h with
  | @mint c u happ => exact Or.inr ⟨u, happ.fresh, allVars_splitResult happ.mem u⟩
  | @reuse c u happ => exact Or.inl (allVars_kSplitReuseResult happ)

/-- **Every keyed step either keeps the vocabulary or adds exactly one fresh variable.** -/
theorem KDefaultStep.allVars_cases {G G' : System} (h : KDefaultStep G G') :
    allVars G' = allVars G ∨ ∃ z, z ∉ allVars G ∧ allVars G' = insert z (allVars G) := by
  cases h with
  | nongen h => exact Or.inl h.allVars_eq
  | split h => exact h.allVars_cases
  | gres h => exact h.allVars_cases

theorem KDefaultStep.allVars_card_le {G G' : System} (h : KDefaultStep G G') :
    (allVars G').card ≤ (allVars G).card + 1 := by
  rcases h.allVars_cases with hV | ⟨z, hz, hV⟩
  · rw [hV]; exact Nat.le_succ _
  · rw [hV, Finset.card_insert_of_notMem hz]

/-! ### 3.3 Everything a keyed rule emits is canonical -/

theorem KDefaultStep.new_canonical {G G' : System} (h : KDefaultStep G G') {c : Constraint}
    (hc : c ∈ G') : c ∈ G ∨ IsCanonical c := by
  cases h with
  | nongen h => exact (DefaultStep.nongen h).new_canonical hc
  | gres h => exact (DefaultStep.gres h).new_canonical hc
  | split h =>
    cases h with
    | @mint d u _ =>
      simp only [splitResult, Finset.mem_insert] at hc
      rcases hc with rfl | rfl | hc
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inl hc
    | @reuse d u _ =>
      rcases Finset.mem_insert.mp hc with rfl | hc
      · exact Or.inr (isCanonical_mk _ _ _)
      · exact Or.inl hc

/-- **Every keyed step adds only shapes over the successor's own vocabulary.** -/
theorem KDefaultStep.new_forms {L : Finset Label} {G G' : System} (h : KDefaultStep G G')
    (hcs : ConcSub L G) : G' ⊆ G ∪ forms (allVars G') L := by
  intro c hc
  rcases h.new_canonical hc with hG | hcan
  · exact Finset.mem_union_left _ hG
  · exact Finset.mem_union_right _ (mem_forms.mpr
      ⟨hcan, lhs_mem_allVars hc, vset_subset_allVars hc, h.concSub hcs c hc⟩)

/-! ### 3.4 Productive runs of the keyed calculus -/

/-- A productive run of the keyed rule set: `n` steps of `KDefaultStep`, each adding at
least one constraint.  The side condition is `ResGuardTerm.GRun`'s and `DefaultTerm.DefaultRun`'s:
without it a chain can idle for ever re-deriving what it already has. -/
inductive KRun : ℕ → System → System → Prop
  | refl (G : System) : KRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      KRun n G₀ G → KDefaultStep G G' → G ⊂ G' → KRun (n + 1) G₀ G'

theorem KRun.subset {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) : G₀ ⊆ G := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ hstep _ ih => exact ih.trans hstep.subset

theorem KRun.card_ge {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) : G₀.card + n ≤ G.card := by
  induction h with
  | refl => omega
  | @tail n G₀ G G' _ _ hss ih =>
    have := Finset.card_lt_card hss
    omega

theorem KRun.satisfiable_iff {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) :
    (∃ rho, SModels rho G₀) ↔ (∃ rho, SModels rho G) := by
  induction h with
  | refl => exact Iff.rfl
  | tail _ hstep _ ih => exact ih.trans hstep.satisfiable_iff

theorem KRun.concSub {L : Finset Label} {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) :
    ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hcs => hstep.concSub (ih hcs)

/-- **A keyed run stays inside the input plus the shapes over its own vocabulary.** -/
theorem KRun.subset_forms {L : Finset Label} {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) :
    ConcSub L G₀ → G ⊆ G₀ ∪ forms (allVars G) L := by
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

/-- **The length of a keyed run is at most the number of shapes over its final
vocabulary.** -/
theorem KRun.length_le_forms {L : Finset Label} {n : ℕ} {G₀ G : System} (h : KRun n G₀ G)
    (hcs : ConcSub L G₀) : n ≤ (forms (allVars G) L).card := by
  have h1 : G₀.card + n ≤ G.card := h.card_ge
  have h2 : G.card ≤ G₀.card + (forms (allVars G) L).card :=
    le_trans (Finset.card_le_card (h.subset_forms hcs)) (Finset.card_union_le _ _)
  omega

/-- **The question, for the keyed calculus.**  The analogue of `DefaultTerm.TerminatesOnSat`,
which is FALSE (`not_TerminatesOnSat`).  §5 proves this one. -/
def TerminatesOnSatKeyed : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KRun n G₀ G → n ≤ N

/-! ## 4. The measure

`ResGuardTerm.gmeas` verbatim: each variable's remaining budget of resolvent keys,
weighted by `(2 ^ |L| + 1) ^ (row cardinality)`.  What is new is that the KEYED SPLIT
spends that same budget: its witness `mk c.lhs {u} c.conc` is exactly the shape
`Resolved` looks for, so `unfired_lt` applies to it unchanged. -/

/-- **Any step that adds no variable does not increase the measure.**  This covers the
non-generative rules and BOTH reuse branches at once: budgets only shrink as the system
grows (`unfired_le`) and the index set is the same. -/
theorem gmeas_le_of_allVars_eq {L : Finset Label} {G G' : System} (hsub : G ⊆ G')
    (hAV : allVars G' = allVars G) (rho : Assign) : gmeas L rho G' ≤ gmeas L rho G := by
  rw [gmeas, gmeas, hAV]
  exact Finset.sum_le_sum fun u _ => Nat.mul_le_mul (unfired_le hsub u) (Nat.le_refl _)

theorem NonGenStep.gmeas_le {L : Finset Label} {G G' : System} (h : NonGenStep G G')
    (rho : Assign) : gmeas L rho G' ≤ gmeas L rho G :=
  gmeas_le_of_allVars_eq h.subset h.allVars_eq rho

theorem KSplitStep.reuse_gmeas_le {L : Finset Label} {G : System} {c : Constraint} {u : Var}
    (happ : KSplitReuseApp G c u) (rho : Assign) :
    gmeas L rho (kSplitReuseResult G c u) ≤ gmeas L rho G :=
  gmeas_le_of_allVars_eq (subset_kSplitReuseResult _ _ _) (allVars_kSplitReuseResult happ) rho

/-- **The keyed mint's child denotes a strictly smaller row than its parent**
(`DefaultTerm.split_rank_lt` with the syntactic guard dropped: only `c.conc ≠ ∅` is used).
This is the semantic half of the argument, and the half that fails without a model. -/
theorem ksplit_rank_lt {G : System} {c : Constraint} {u : Var} (hne : c.conc ≠ ∅)
    {rho : Assign} (hm : SModels rho (splitResult G c u)) :
    (rho u).card < (rho c.lhs).card := by
  have h := hm _ (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _))
  rw [sat_lone_iff] at h
  obtain ⟨heq, hdis⟩ := h
  obtain ⟨l, hl⟩ := Finset.nonempty_iff_ne_empty.mpr hne
  have hlv : l ∈ rho c.lhs := by rw [heq]; exact Finset.mem_union_left _ hl
  have hlu : l ∉ rho u := Finset.disjoint_left.mp hdis hl
  have hsub : rho u ⊆ rho c.lhs := by rw [heq]; exact Finset.subset_union_right
  exact Finset.card_lt_card ((Finset.ssubset_iff_of_subset hsub).mpr ⟨l, hlv, hlu⟩)

/-- **A keyed mint strictly decreases the measure.**  Word for word the argument of
`ResGuardTerm.GResStep.mint_gmeas_lt`, with the split's witness in place of resolution's:
the parent `c.lhs` pays one unit of budget at the key `c.conc ⊆ L`, which the guard
guaranteed open and which the emitted `c.lhs <- (u, c.conc)` closes; the minted `u`
receives a whole fresh budget, but at a strictly smaller exponent
(`ksplit_rank_lt`), and a whole budget there is worth less than the single unit the parent
gave up (`budget_mul_pow_lt`).  Every other variable's budget can only have shrunk. -/
theorem KSplitStep.mint_gmeas_lt {L : Finset Label} {G : System} {c : Constraint} {u : Var}
    (happ : KSplitApp G c u) (hcs : ConcSub L G) {rho : Assign}
    (hm : SModels rho (splitResult G c u)) :
    gmeas L rho (splitResult G c u) < gmeas L rho G := by
  have hp : c.lhs ∈ allVars G := lhs_mem_allVars happ.mem
  have hsub : G ⊆ splitResult G c u := subset_splitResult _ _ _
  have hmem : mk c.lhs {u} c.conc ∈ splitResult G c u :=
    Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)
  have hAV : allVars (splitResult G c u) = insert u (allVars G) :=
    allVars_splitResult happ.mem u
  have hKL : c.conc ⊆ L := hcs c happ.mem
  have hrank : (rho u).card < (rho c.lhs).card := ksplit_rank_lt happ.conc_ne hm
  -- the minted variable's entire budget is worth less than one unit at the parent
  have huterm : unfired L (splitResult G c u) u * (2 ^ L.card + 1) ^ (rho u).card
      < (2 ^ L.card + 1) ^ (rho c.lhs).card :=
    lt_of_le_of_lt (Nat.mul_le_mul (unfired_le_pow L (splitResult G c u) u) (Nat.le_refl _))
      (budget_mul_pow_lt (2 ^ L.card) hrank)
  -- the parent pays one unit
  have hpterm : unfired L (splitResult G c u) c.lhs * (2 ^ L.card + 1) ^ (rho c.lhs).card
      + (2 ^ L.card + 1) ^ (rho c.lhs).card
      ≤ unfired L G c.lhs * (2 ^ L.card + 1) ^ (rho c.lhs).card := by
    have h1 : unfired L (splitResult G c u) c.lhs + 1 ≤ unfired L G c.lhs :=
      unfired_lt hsub hKL happ.unresolved hmem
    have h2 : (unfired L (splitResult G c u) c.lhs + 1) * (2 ^ L.card + 1) ^ (rho c.lhs).card
        ≤ unfired L G c.lhs * (2 ^ L.card + 1) ^ (rho c.lhs).card :=
      Nat.mul_le_mul h1 (Nat.le_refl _)
    rw [Nat.add_mul, Nat.one_mul] at h2
    exact h2
  -- everybody else's budget only shrank
  have hrest : ∑ w ∈ (allVars G).erase c.lhs,
        unfired L (splitResult G c u) w * (2 ^ L.card + 1) ^ (rho w).card
      ≤ ∑ w ∈ (allVars G).erase c.lhs, unfired L G w * (2 ^ L.card + 1) ^ (rho w).card :=
    Finset.sum_le_sum fun w _ => Nat.mul_le_mul (unfired_le hsub w) (Nat.le_refl _)
  -- assemble
  have hsplitG : gmeas L rho G
      = unfired L G c.lhs * (2 ^ L.card + 1) ^ (rho c.lhs).card
        + ∑ w ∈ (allVars G).erase c.lhs, unfired L G w * (2 ^ L.card + 1) ^ (rho w).card :=
    sum_erase_split hp (fun w => unfired L G w * (2 ^ L.card + 1) ^ (rho w).card)
  have hsplit2 : ∑ w ∈ allVars G,
        unfired L (splitResult G c u) w * (2 ^ L.card + 1) ^ (rho w).card
      = unfired L (splitResult G c u) c.lhs * (2 ^ L.card + 1) ^ (rho c.lhs).card
        + ∑ w ∈ (allVars G).erase c.lhs,
            unfired L (splitResult G c u) w * (2 ^ L.card + 1) ^ (rho w).card :=
    sum_erase_split hp
      (fun w => unfired L (splitResult G c u) w * (2 ^ L.card + 1) ^ (rho w).card)
  have hsplitG' : gmeas L rho (splitResult G c u)
      = unfired L (splitResult G c u) u * (2 ^ L.card + 1) ^ (rho u).card
        + (unfired L (splitResult G c u) c.lhs * (2 ^ L.card + 1) ^ (rho c.lhs).card
          + ∑ w ∈ (allVars G).erase c.lhs,
              unfired L (splitResult G c u) w * (2 ^ L.card + 1) ^ (rho w).card) := by
    rw [gmeas, hAV, Finset.sum_insert happ.fresh, hsplit2]
  rw [hsplitG, hsplitG']
  omega

/-! ### 4.1 The step, packaged -/

/-- **The model extends along every keyed step**, changing the assignment only at the fresh
variable, if any (`DefaultTerm.DefaultStep.extend` for the keyed calculus). -/
theorem KDefaultStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : KDefaultStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | nongen h => exact ⟨rho, (h.models_iff rho).mp hm, fun _ _ => rfl⟩
  | split h =>
    cases h with
    | @mint c u happ =>
      refine ⟨setVar rho u ((vset c).biUnion rho), ksplit_extend happ.mem happ.fresh hm, ?_⟩
      exact fun v hv => setVar_of_ne rho _ (fun hh => happ.fresh (hh ▸ hv))
    | @reuse c u happ =>
      exact ⟨rho, (KSplitStep.reuse_models_iff happ rho).mpr hm, fun _ _ => rfl⟩
  | gres h =>
    cases h with
    | @mint v x y C D z hp _ hz => exact mint_extend hp hz hm
    | @reuse v x y C D z hp hr =>
      exact ⟨rho, (GResStep.reuse_models_iff hp hr rho).mpr hm, fun _ _ => rfl⟩

/-- **The single-step invariant.**  Along a keyed step from a modelled system, the extended
model keeps `|vocabulary| + measure` from growing: a mint adds one variable and drops the
measure by at least one, everything else does neither.  The measure of the OLD system under
the NEW model is the measure under the old one (`gmeas_congr`), since they agree on the old
vocabulary. -/
theorem KDefaultStep.measure_step {L : Finset Label} {G G' : System} (h : KDefaultStep G G')
    (hcs : ConcSub L G) {rho : Assign} (hm : SModels rho G) :
    ∃ rho', SModels rho' G' ∧ (∀ v ∈ allVars G, rho' v = rho v) ∧
      (allVars G').card + gmeas L rho' G' ≤ (allVars G).card + gmeas L rho G := by
  cases h with
  | nongen h =>
    refine ⟨rho, (h.models_iff rho).mp hm, fun _ _ => rfl, ?_⟩
    have := h.gmeas_le (L := L) rho
    rw [h.allVars_eq]
    omega
  | split hs =>
    cases hs with
    | @mint c u happ =>
      refine ⟨setVar rho u ((vset c).biUnion rho), ksplit_extend happ.mem happ.fresh hm,
        fun v hv => setVar_of_ne rho _ (fun hh => happ.fresh (hh ▸ hv)), ?_⟩
      have hcong : gmeas L (setVar rho u ((vset c).biUnion rho)) G = gmeas L rho G :=
        gmeas_congr fun w hw => setVar_of_ne rho _ (fun hh => happ.fresh (hh ▸ hw))
      have hlt : gmeas L (setVar rho u ((vset c).biUnion rho)) (splitResult G c u)
          < gmeas L (setVar rho u ((vset c).biUnion rho)) G :=
        KSplitStep.mint_gmeas_lt happ hcs (ksplit_extend happ.mem happ.fresh hm)
      have hcard : (allVars (splitResult G c u)).card = (allVars G).card + 1 := by
        rw [allVars_splitResult happ.mem u]
        exact Finset.card_insert_of_notMem happ.fresh
      omega
    | @reuse c u happ =>
      refine ⟨rho, (KSplitStep.reuse_models_iff happ rho).mpr hm, fun _ _ => rfl, ?_⟩
      have := KSplitStep.reuse_gmeas_le (L := L) happ rho
      rw [allVars_kSplitReuseResult happ]
      omega
  | gres hg =>
    cases hg with
    | @mint v x y C D z hp hgd hzf =>
      obtain ⟨rho', hm', hagree⟩ := mint_extend hp hzf hm
      refine ⟨rho', hm', hagree, ?_⟩
      have hcong : gmeas L rho' G = gmeas L rho G :=
        (gmeas_congr fun w hw => (hagree w hw).symm).symm
      have hlt : gmeas L rho' (resResult G v x y C D z) < gmeas L rho' G :=
        GResStep.mint_gmeas_lt hp hgd hzf hcs rfl hm'
      have hcard : (allVars (resResult G v x y C D z)).card = (allVars G).card + 1 := by
        rw [GResStep.mint_allVars_eq hp z]
        exact Finset.card_insert_of_notMem hzf
      omega
    | @reuse v x y C D z hp hr =>
      refine ⟨rho, (GResStep.reuse_models_iff hp hr rho).mpr hm, fun _ _ => rfl, ?_⟩
      have hle := GResStep.reuse_gmeas_le (L := L) hp hr rfl rho
      rw [GResStep.reuse_allVars_eq hp hr]
      omega

/-- **The invariant that drives the bound.**  Along a keyed run from a SATISFIABLE input,
the number of variables plus the measure never grows.  The model is carried along, changing
only on freshly minted variables. -/
theorem KRun.invariant {L : Finset Label} {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) :
    ∀ (rho₀ : Assign), SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧
        (allVars G).card + gmeas L rho G ≤ (allVars G₀).card + gmeas L rho₀ G₀ := by
  induction h with
  | refl G =>
    intro rho₀ hm _
    exact ⟨rho₀, hm, Nat.le_refl _⟩
  | @tail n G₀ G G' hrun hstep _ ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hb⟩ := ih rho₀ hm hcs
    obtain ⟨rho', hm', -, hb'⟩ := hstep.measure_step (hrun.concSub hcs) hmr
    exact ⟨rho', hm', le_trans hb' hb⟩

/-- **The vocabulary of a keyed run is bounded by the input alone.**  This is the step
`DefaultTerm.CountRun.split_branching_le` could not take for the syntactic guard, and the
reason `DefaultSatDiverge`'s engine cannot run here. -/
theorem KRun.allVars_card_le {L : Finset Label} {n : ℕ} {G₀ G : System} (h : KRun n G₀ G)
    (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    (allVars G).card ≤ (allVars G₀).card + gmeas L rho G₀ := by
  obtain ⟨rho', -, hb⟩ := h.invariant rho hm hcs
  omega

/-! ## 5. Termination -/

/-- **The length of a keyed run is bounded by the input alone.**  With
`M := |allVars G₀| + gmeas L rho G₀`, no productive run exceeds `M · 2 ^ M · 2 ^ |L|`
steps: the vocabulary can grow to at most `M` variables (`KRun.allVars_card_le`), over `M`
variables there are at most `M · 2 ^ M · 2 ^ |L|` `mk`-shaped constraints
(`DefaultTerm.card_forms_le`), and each productive step adds one. -/
theorem KRun.length_le {L : Finset Label} {n : ℕ} {G₀ G : System} (h : KRun n G₀ G)
    (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    n ≤ ((allVars G₀).card + gmeas L rho G₀) *
          2 ^ ((allVars G₀).card + gmeas L rho G₀) * 2 ^ L.card := by
  have h1 : n ≤ (allVars G).card * 2 ^ (allVars G).card * 2 ^ L.card :=
    (h.length_le_forms hcs).trans (card_forms_le _ _)
  exact h1.trans (formsBound_mono (h.allVars_card_le rho hm hcs) L.card)

/-- **The keyed calculus terminates on every satisfiable system.**  From a system with a
model there is a bound, computed from the input alone, on the length of every productive
run of `KDefaultStep` — in ANY order.  Contrast `not_TerminatesOnSat`: with the syntactic
split guard, the satisfiable `SatDiverge.W2` admits productive runs of every length. -/
theorem keyed_terminates_of_satisfiable (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KRun n G₀ G → n ≤ N :=
  ⟨((allVars G₀).card + gmeas (labelsOf G₀) rho G₀) *
      2 ^ ((allVars G₀).card + gmeas (labelsOf G₀) rho G₀) * 2 ^ (labelsOf G₀).card,
    fun _ _ h => h.length_le rho hm (labelsOf_concSub G₀)⟩

/-- **`TerminatesOnSatKeyed` holds.** -/
theorem terminatesOnSatKeyed : TerminatesOnSatKeyed :=
  fun G₀ rho hm => keyed_terminates_of_satisfiable G₀ rho hm

/-- **The contrast, in one statement.**  Rekeying `splitConcrete`'s reverse lookup from the
GROUP to the pair `(left-hand side, concrete part)` turns a false termination statement into
a true one, for the same additive rule set, the same runs, and the same class of inputs. -/
theorem keyed_vs_syntactic : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSat :=
  ⟨terminatesOnSatKeyed, not_TerminatesOnSat⟩

/-! ### 5.1 The bound is not vacuous: both minting branches still fire

A bound on the length of every run says nothing unless runs exist and mints happen.  They
do. -/

/-- Every productive run of guarded resolution alone is a productive keyed run. -/
theorem KRun.of_gRun {n : ℕ} {G₀ G : System} (h : GRun n G₀ G) : KRun n G₀ G := by
  induction h with
  | refl G => exact KRun.refl G
  | tail _ hstep hss ih => exact KRun.tail ih (KDefaultStep.gres hstep) hss

/-- **The resolution mint fires in the keyed calculus**, on `Cut.resSeed` -- the system on
which the UNGUARDED rule admits chains of every length (`Cut.resSeed_diverges`). -/
theorem kRun_one_resSeed : ∃ G : System, KRun 1 resSeed G := by
  obtain ⟨G, h⟩ := gRun_one_resSeed
  exact ⟨G, KRun.of_gRun h⟩

/-- **The keyed SPLIT mint fires too.**  On `{0 <- (1, 2, (|5|))}` the key `(0, (|5|))` is
open -- no constraint has the shape `0 <- (z, (|5|))` -- so the keyed guard mints, exactly
as the syntactic one would.  Without this the termination theorem could be true for the
uninteresting reason that the branch is unreachable. -/
theorem keyed_mint_fires : ∃ (G : System) (c : Constraint) (u : Var), KSplitApp G c u := by
  refine ⟨{mk 0 {1, 2} {5}}, mk 0 {1, 2} {5}, 3, Finset.mem_singleton_self _, ?_, ?_, ?_, ?_⟩
  · rw [conc_mk]; decide
  · rw [vset_mk]; decide
  · rintro ⟨z, -, hz⟩
    rw [conc_mk, lhs_mk, Finset.mem_singleton, NameLoss.mk_eq_iff] at hz
    have h1 : (1 : Var) ∈ ({z} : Finset Var) := by
      rw [hz.2.1]; exact Finset.mem_insert_self _ _
    have h2 : (2 : Var) ∈ ({z} : Finset Var) := by
      rw [hz.2.1]; exact Finset.mem_insert_of_mem (Finset.mem_singleton_self _)
    rw [Finset.mem_singleton] at h1 h2
    exact absurd (h1.trans h2.symm) (by decide)
  · simp only [allVars, Finset.singleton_biUnion, lhs_mk, vset_mk]
    decide

/-! ## 6. Non-vacuity: the keyed guard stops `DefaultSatDiverge`'s engine

`SatDiverge.W2` is the satisfiable system whose productive `DefaultStep` runs are unbounded.
Its engine (`W2Inv.round`) is: cancel `p <- (e2, K)` against `p <- (u, K)` for the alias link
`e2 <- (u)`; substitute it into `p <- (e1, e2, K)` for `p <- (e1, u, K)`; then MINT a name for
the never-before-seen group `{e1, u}`.  The keyed guard closes exactly the last step: the
key of the mint premise `p <- (e1, u, K)` is `(p, K)`, and `p <- (u, K)` — the very
constraint the round's cancellation used — is still in the system, so the key is
RESOLVED. -/

namespace SatDiverge

/-! ### 6.1 Round 0 is already refused

`W2` itself carries `p <- (e2, (|k|))`, a name for `p \ (|k|)`.  So the keyed guard is
closed on `W2` from the start: the split mint of round 0 (`SatDiverge.split0_app`, which the
syntactic guard allows because `W2` has no bare constraint) does not fire, and the keyed
calculus takes the reuse instead. -/

/-- **The key `(p, (|k|))` is resolved in `W2` itself**, by the second input constraint. -/
theorem W2_resolved : Resolved W2 p K := resolved_of_mem single_mem

/-- **The keyed guard refuses round 0.**  Contrast `SatDiverge.split0_app`: the syntactic
guard admits exactly this mint, and it is the first step of the divergent engine. -/
theorem W2_not_keyed_mint0 : ∀ u : Var, ¬ KSplitApp W2 (mk p {e1, e2} K) u :=
  fun _ happ => happ.unresolved W2_resolved

/-- **What the keyed calculus does on `W2` instead**: reuse the existing name `e2`, giving
it the group as a definition -- `e2 <- (e1, e2)`. -/
theorem W2_keyed_reuse0 : KSplitReuseApp W2 (mk p {e1, e2} K) e2 where
  mem := base_mem
  conc_ne := by rw [conc_mk]; exact Finset.singleton_ne_empty _
  two_le := by rw [vset_mk]; decide
  witness := single_mem

theorem W2_bare_notMem : mk e2 {e1, e2} ∅ ∉ W2 := by
  simp only [W2, Finset.mem_insert, Finset.mem_singleton, NameLoss.mk_eq_iff]
  decide

/-- **The keyed calculus does take a step from `W2`**, so `W2_keyed_bound` below bounds a
nonempty set of runs. -/
theorem kRun_one_W2 : ∃ G : System, KRun 1 W2 G :=
  ⟨_, KRun.tail (KRun.refl W2) (KDefaultStep.split (KSplitStep.reuse W2_keyed_reuse0))
      (by simp only [kSplitReuseResult, vset_mk]; exact Finset.ssubset_insert W2_bare_notMem)⟩

/-- ...and the constraint it emits is the SELF-partition `e2 <- (e1, e2)`, on which
self-substitution derives `e1 <- ()`.  The variable the whole divergent engine runs on --
the one `W2` forces empty -- is exposed in two steps instead of being carried around inside
ever-new groups. -/
theorem W2_keyed_reuse0_selfSubst :
    SelfSubstStep (kSplitReuseResult W2 (mk p {e1, e2} K) e2)
      (selfSubstResult (kSplitReuseResult W2 (mk p {e1, e2} K) e2) e1) :=
  SelfSubstStep.intro
    { mem := by rw [kSplitReuseResult, vset_mk]; exact Finset.mem_insert_self _ _
      self := by rw [lhs_mk, vset_mk]
                 exact Finset.mem_insert_of_mem (Finset.mem_singleton_self _)
      conc_empty := by rw [conc_mk]
      mem_v := by rw [vset_mk]; exact Finset.mem_insert_self _ _
      ne := by rw [lhs_mk]; decide }

/-- The system the engine reaches after the round's cancellation and substitution: `G₁`
plus the alias link `e2 <- (u1)` plus the merged premise `p <- (e1, u1, (|k|))`.  In
`DefaultSatDiverge` this is the input of `W2Inv.step_split`, the round's MINT. -/
def G₂ : System := insert (mk p {e1, u1} K) (insert (mk e2 {u1} ∅) G₁)

/-- `p <- (u1, (|k|))`, minted in round 0, survives into `G₂`. -/
theorem cur1_mem_G₂ : mk p {u1} K ∈ G₂ :=
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem
    (Finset.mem_insert_of_mem (Finset.mem_insert_self _ _)))

/-- **The key is resolved at `G₂`**: `p`'s row minus `(|k|)` already has the name `u1`. -/
theorem G₂_resolved : Resolved G₂ p K := resolved_of_mem cur1_mem_G₂

/-- **The keyed guard refuses the engine's second mint.**  No fresh name whatever makes the
round's split premise a keyed mint premise: `G₂` already carries `p <- (u1, (|k|))`.  This is
the step `W2Inv.step_split` takes once per round, for ever, under the syntactic guard. -/
theorem W2_keyed_no_second_mint : ∀ u' : Var, ¬ KSplitApp G₂ (mk p {e1, u1} K) u' :=
  fun _ happ => happ.unresolved G₂_resolved

/-- **What the keyed calculus does instead**: a REUSE, giving the existing name `u1` the new
group as a definition, `u1 <- (e1, u1)`. -/
theorem W2_keyed_reuse : KSplitReuseApp G₂ (mk p {e1, u1} K) u1 where
  mem := Finset.mem_insert_self _ _
  conc_ne := by rw [conc_mk]; exact Finset.singleton_ne_empty _
  two_le := by rw [vset_mk]; decide
  witness := cur1_mem_G₂

/-- ...and that conclusion is a SELF-partition, `u1 <- (e1, u1)`, on which
self-substitution derives `e1 <- ()` — the empty variable the whole engine runs on, made
explicit in one further step.  (`makeEmpty` then erases it in the real loop; here it is
simply derived.) -/
theorem W2_keyed_reuse_selfSubst :
    SelfSubstStep (kSplitReuseResult G₂ (mk p {e1, u1} K) u1)
      (selfSubstResult (kSplitReuseResult G₂ (mk p {e1, u1} K) u1) e1) :=
  SelfSubstStep.intro
    { mem := by rw [kSplitReuseResult, vset_mk]; exact Finset.mem_insert_self _ _
      self := by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_of_mem (Finset.mem_singleton_self _)
      conc_empty := by rw [conc_mk]
      mem_v := by rw [vset_mk]; exact Finset.mem_insert_self _ _
      ne := by rw [lhs_mk]; decide }

/-- **The bound, on the very input the syntactic guard diverges on.**  `W2` is satisfiable
(`W2_models`), so `keyed_terminates_of_satisfiable` applies: every productive run of the
KEYED calculus from `W2` is shorter than a fixed bound, while `W2_unbounded` gives runs of
the shipped calculus of every length. -/
theorem W2_keyed_bound : ∃ N : ℕ, ∀ (n : ℕ) (G : System), KRun n W2 G → n ≤ N :=
  keyed_terminates_of_satisfiable W2 rho2 W2_models

end SatDiverge

/-- **The two guards really do disagree, on a reachable system.**  At `SatDiverge.G₂` the
SYNTACTIC guard is open — the group `{e1, u1}` has no name — so `Cut.SplitApp` holds and the
shipped rule set mints; the KEYED guard is closed, so `KSplitApp` fails.  Hence
`DefaultStep` is not a sub-relation of `KDefaultStep` at the level of premises: the two
calculi are incomparable, and §5 is a theorem about the keyed one. -/
theorem split_mint_not_keyed :
    ∃ (G : System) (c : Constraint) (u : Var), SplitApp G c u ∧ ¬ KSplitApp G c u := by
  obtain ⟨u', hu'⟩ := exists_fresh (allVars (insert (mk SatDiverge.p {SatDiverge.e1, SatDiverge.u1}
    SatDiverge.K) (insert (mk SatDiverge.e2 {SatDiverge.u1} ∅) SatDiverge.G₁)))
  exact ⟨_, _, u', SatDiverge.G₁_inv.splitApp hu', SatDiverge.W2_keyed_no_second_mint u'⟩

/-! ## Summary

**What is established.**  Rekeying `splitConcrete`'s reverse lookup from the group `vset c`
to the pair `(c.lhs, c.conc)` makes the ADDITIVE shipped calculus terminate on every
SATISFIABLE input, with an explicit bound: for `L := labelsOf G₀`, a model `rho`, and
`M := |allVars G₀| + gmeas L rho G₀`, no productive run of `KDefaultStep` exceeds
`M · 2 ^ M · 2 ^ |L|` steps (`KRun.length_le`, `keyed_terminates_of_satisfiable`,
`terminatesOnSatKeyed`).  The guard change is not a semantic one: the mint branch is a
conservative extension at the fresh name (`ksplit_mint_conservativeExt`) and the reuse
branch does not move the model set at all (`KSplitStep.reuse_models_iff`).  The mechanism is
the one `ResGuardTerm` found for `resolution`: the guard makes each pair (variable, key) mintable
at most once and the keys live in the fixed finite `L.powerset`, while the model makes each
minted variable's row strictly smaller than its parent's, so a budget weighted by
`(2 ^ |L| + 1) ^ (row cardinality)` decreases at every mint and never increases elsewhere.
Both mints of the calculus spend the SAME budget, because the keyed split's witness
`c.lhs <- (u, c.conc)` has exactly the shape `Resolved` looks for.

**What is NOT established.**  Nothing about UNSATISFIABLE input: `KDefaultStep` still
contains guarded resolution, which diverges on `ResGuardDiverge.gSeed`.  Nothing about the
real `incorporateAll` loop, which deletes and renames (`Saturate.SatStep`) and is not a
sub-relation of any additive relation here.  Nothing about the SHIPPED guard: `DefaultStep`
and `KDefaultStep` are incomparable (`split_mint_not_keyed`), so `not_TerminatesOnSat`
stands unchanged for the calculus as implemented.  And nothing is implemented: no code
consults `Resolved` before a split mint. -/

end Rowpartition
