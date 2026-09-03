/-
# KeyedLoop -- the keyed split guard against the loop layer's DELETIONS

`KeyedSplit.lean` proves that the ADDITIVE calculus `KDefaultStep` -- the non-generative
rules, the KEYED `splitConcrete` and guarded `resolution` -- terminates on every
satisfiable input in every run order (`terminatesOnSatKeyed`, bound `KRun.length_le`).
The real `Constraints.incorporateAll` is not additive.  `makeConcrete` / `destructiveSub`
(`NameLoss.concretizeKeep u C G`) DELETES every definition of `u` with fewer than two
abstract parts, REWRITES every mention of `u` by `absorbC`, and keeps `u <- ((|C|))`
together with the definitions of `u` that have two or more abstract parts (`keepDefs`).

Stage 3 asks whether the keyed guard survives that.  **It does not.**

## The two ways a key witness dies

The keyed guard mints iff `¬ Resolved G p K`, i.e. unless some `p <- (z, K)` with ONE
abstract variable is in the system.  Concretising `u` destroys every such witness that
mentions `u` at all, and the two clauses of `concretizeKeep` give one failure mode each:

* `notMem_lone_lhs` : `mk u {z} K ∉ concretizeKeep u C G` -- ALWAYS.  A witness headed by
  the concretised variable has a single abstract part, so `keepDefs` (`2 ≤ |vset|`) does
  not keep it and the deletion is unconditional.  This is the mode the Stage 3 brief
  names.
* `notMem_lone_mention` : `mk v {u} K ∉ concretizeKeep u C G` for `v ≠ u` -- ALSO always.
  A witness whose abstract part IS the concretised variable is rewritten by `absorbC` into
  `v <- ((|K ∪ C|))`, and the rewrite is DESTRUCTIVE: the premise is not retained.  This
  mode is not in the brief's sketch, and it is the one that makes the loop diverge.

What survives is exactly the complement: `resolved_of_concretizeKeep` -- a witness
`mk v {z} K` with `v ≠ u` and `z ≠ u` is untouched, so its key stays closed.

## The result: (W), a divergence witness

`W3` is three constraints on four variables and two labels, satisfiable (`rho3`,
`W3_models`):

    u <- ((|k, c|))        the concrete value          W3conc
    u <- (z, (|k|))        the KEY WITNESS             W3key
    u <- (x, y, (|k|))     the kept split premise      W3def

At `W3` the keyed guard is CLOSED (`W3_resolved`): `KSplitApp` cannot fire, and the
additive theorem applies.  One `makeConcrete` of `u` deletes the key witness and keeps the
split premise (`W3_concrete_step`, `concretizeKeep u C W3 = {W3conc, W3def}` --
`W3_concretize_eq`), and from there the loop runs for ever, three steps to the round:

1. the keyed split MINTS `w <- (x, y)` and `u <- (w, (|k|))` -- the key is closed again;
2. cancellation of `u <- (w, (|k|))` against `u <- ((|k, c|))` gives `w <- ((|c|))`;
3. `makeConcrete w` rewrites the mention `u <- (w, (|k|))` to `u <- ((|k, c|))`, which is
   already present -- so the key witness is DELETED and nothing replaces it -- while
   `keepDefs` keeps `w <- (x, y)` (two abstract parts).  The invariant is back, with one
   more variable in the vocabulary.

The brief's sketch predicted step 3 would leave `u <- (w, K)` in place and so close the key
for ever.  It does not: `w` occurs on the RIGHT of that constraint, so `absorbC` consumes
it.  `W3Inv.round`, `W3Inv.run`, `W3_diverges`, `not_TerminatesOnSatKeyedLoop`.

What the real loop does on the same input, measured (`tracker/satterm/KEYED-LOOP-STAGE3.md`):
round 0 and the first half of round 1 happen -- `makeConcrete u` deletes the key witness, the
kept `u <- (x, y, (|k|))` is dequeued afterwards and `splitConcrete` MINTS -- at 55 of 100 id
bases, and the cancellation `w <- ((|c|))` of step 2 fires at 55 of those 55.  The loop then
stops for a reason no rule of this file has: `w <- ((|c|))` has the same right-hand side as
the deleted witness's own `z <- ((|c|))`, and `incorporateAll`'s `common` branch UNIFIES the
two variables (55 of 55), so the fresh name is identified with the one the deletion removed.

The refutation is stated in the strongest form the run relation allows: `W3_mints_unbounded`
exhibits, for every `n`, a run of `3 * n + 1` steps whose vocabulary has grown by `n`.
Only a MINT enlarges the vocabulary (`KLoopStep.allVars_cases`: every other step leaves it
alone or shrinks it), so that is `n` mints -- not an oscillation between two systems.

## Scope

* This is a statement about the additive relation EXTENDED BY the concretisation step, in
  every order -- the same quantifier as `terminatesOnSatKeyed` and `not_TerminatesOnSat`.
  It is NOT a statement about `incorporateAll`, which examines each partition once, at its
  dequeue.  The measurement says the shipped loop takes round 0 and the mint of round 1 and
  then stops: nothing re-enqueues `u <- (x, y, (|k|))` a second time, and the name the mint
  produced is unified away by `common`.  Neither property is stated by any relation in this
  development -- the same single-pass gap `NameLoss.orderB_remint_enabled` records.
* The productivity side condition on a run is `G ≠ G'`, which on additive steps is exactly
  `G ⊂ G'` (`KLoopRun.ssubset_of_additive`), because `KDefaultStep` is monotone.  That
  condition alone is weak -- a concretise step that only DELETES counts as productive -- which
  is why the headline to read is `W3_mints_unbounded`, which counts fresh variables, and not
  `W3_diverges`, which counts steps.
* Nothing here changes the additive theorem.  Every deletion-free run is a `KRun`
  (`KLoopRun.of_kRun`) and `KeyedSplit.KRun.length_le` bounds it unchanged; all the
  unboundedness comes from the concretise steps.
* **The one faithfulness gap, machine-checked rather than argued.**  `KSplitApp` carries
  ONLY the keyed premise `¬ Resolved G c.lhs c.conc`; the shipped `splitConcrete` asks the
  SYNTACTIC lookup `rhss(RHSAbstr(abstr))` FIRST and mints only when both miss.  So
  `KDefaultStep` -- the relation `terminatesOnSatKeyed` bounds -- is MORE permissive than the
  compiler's rule, and this file refutes the same statement for the same relation.  The
  FIRST re-mint the concretisation enables is faithful: at `W3sat` both lookups miss
  (`W3sat_remint_enabled` gives `Cut.SplitApp` as well as `KSplitApp`), and the measurement
  finds exactly that mint in the real loop at 55 of 100 id bases.  From the SECOND round on
  the engine's mints are not the compiler's: the round's own mint leaves the bare
  `w <- (x, y)` behind and the concretisation keeps it, so the group IS named
  (`named_after_round`) and the shipped rule would take its syntactic reuse branch.
  Whether the SHIPPED rule -- both lookups, plus deletion -- terminates on satisfiable input
  is therefore still open; nothing here settles it.
-/
import Rowpartition.KeyedSplit
import Rowpartition.KeepInert

namespace Rowpartition

open NameLoss (absorbC concretize concretizeKeep concretizeKeep_sound denotes_of_conc)

namespace KeyedLoop

/-! ## 1. The concretisation step, as the loop performs it -/

/-- `absorbC` does not touch a constraint that does not mention `u`. -/
theorem absorbC_of_notMem {u : Var} {C : Row} {c : Constraint} (h : u ∉ vset c) :
    absorbC u C c = c := by
  unfold absorbC; rw [if_neg h]

/-- `absorbC` never changes a left-hand side. -/
@[simp] theorem absorbC_lhs (u : Var) (C : Row) (c : Constraint) :
    (absorbC u C c).lhs = c.lhs := by
  unfold absorbC; split_ifs <;> simp

/-- `absorbC` never adds a variable. -/
theorem vset_absorbC_subset (u : Var) (C : Row) (c : Constraint) :
    vset (absorbC u C c) ⊆ vset c := by
  unfold absorbC
  split_ifs
  · rw [vset_mk]; exact Finset.erase_subset _ _
  · exact Finset.Subset.refl _

/-- **Membership in the concretisation**, the workhorse of this section: a constraint of
`concretizeKeep u C G` is the new concrete definition, the `absorbC`-image of a constraint
of `G` not headed by `u`, or a kept definition of `u`. -/
theorem mem_concretizeKeep {u : Var} {C : Row} {G : System} {c : Constraint} :
    c ∈ concretizeKeep u C G ↔
      c = mk u ∅ C ∨ (∃ d ∈ G, d.lhs ≠ u ∧ absorbC u C d = c) ∨
        (c ∈ G ∧ c.lhs = u ∧ 2 ≤ (vset c).card) := by
  simp only [concretizeKeep, concretize, Finset.mem_union, Finset.mem_insert,
    Finset.mem_image, Finset.mem_filter]
  constructor
  · rintro (⟨rfl | ⟨d, ⟨hd, hdu⟩, rfl⟩⟩ | ⟨hc, h1, h2⟩)
    · exact Or.inl rfl
    · exact Or.inr (Or.inl ⟨d, hd, hdu, rfl⟩)
    · exact Or.inr (Or.inr ⟨hc, h1, h2⟩)
  · rintro (rfl | ⟨d, hd, hdu, rfl⟩ | ⟨hc, h1, h2⟩)
    · exact Or.inl (Or.inl rfl)
    · exact Or.inl (Or.inr ⟨d, ⟨hd, hdu⟩, rfl⟩)
    · exact Or.inr ⟨hc, h1, h2⟩

/-- **Failure mode 1 -- DELETION.**  A key witness headed by the concretised variable has a
single abstract part; `keepDefs`' `2 ≤ |vset|` test does not keep it, no image can be
headed by `u`, and the concrete definition it is replaced by is bare.  So the key `(u, K)`
is left OPEN by every concretisation of `u`, unconditionally. -/
theorem notMem_lone_lhs (u z : Var) (C K : Row) (G : System) :
    mk u {z} K ∉ concretizeKeep u C G := by
  intro h
  rcases mem_concretizeKeep.mp h with h | ⟨d, -, hdu, hd⟩ | ⟨-, -, h2⟩
  · exact absurd ((mk_inj h).2.1) (by simp)
  · exact hdu (by rw [← absorbC_lhs u C d, hd, lhs_mk])
  · rw [vset_mk, Finset.card_singleton] at h2; omega

/-- **Failure mode 2 -- the destructive REWRITE.**  A key witness whose abstract part is
the concretised variable is rewritten by `absorbC` into the bare `v <- ((|K ∪ C|))`, and
`concretize` keeps only the IMAGE: the premise itself is gone.  So the key `(v, K)` is left
open too.  This mode is invisible to `KeepInert.lean`, which only studies the kept
definitions, and it is the one the divergence of §3 runs on. -/
theorem notMem_lone_mention {u v : Var} {C K : Row} {G : System} (hne : v ≠ u) :
    mk v {u} K ∉ concretizeKeep u C G := by
  intro h
  rcases mem_concretizeKeep.mp h with h | ⟨d, -, -, hd⟩ | ⟨-, h1, -⟩
  · exact hne (mk_inj h).1
  · have : u ∉ vset (absorbC u C d) := by
      unfold absorbC
      split_ifs with hmem
      · rw [vset_mk]; exact Finset.notMem_erase _ _
      · exact hmem
    rw [hd, vset_mk] at this
    exact this (Finset.mem_singleton_self u)
  · rw [lhs_mk] at h1; exact hne h1

/-- **Which keys stay closed.**  The complement of the two failure modes: a witness
`mk v {z} K` in which the concretised variable occurs neither as the left-hand side nor as
the abstract part is untouched, so its key stays closed.  Everything `Resolved` loses at a
concretisation of `u`, it loses through `u`. -/
theorem resolved_of_concretizeKeep {u v z : Var} {C K : Row} {G : System}
    (hw : mk v {z} K ∈ G) (hv : v ≠ u) (hz : z ≠ u) :
    Resolved (concretizeKeep u C G) v K := by
  have hnm : u ∉ vset (mk v {z} K) := by
    simp only [vset_mk, Finset.mem_singleton]
    exact fun hh => hz hh.symm
  have hmem : mk v {z} K ∈ concretizeKeep u C G := by
    refine mem_concretizeKeep.mpr (Or.inr (Or.inl ⟨mk v {z} K, hw, ?_, ?_⟩))
    · simpa using hv
    · exact absorbC_of_notMem hnm
  exact resolved_of_mem hmem

/-- The concretisation adds no variable. -/
theorem allVars_concretizeKeep_subset {u : Var} {C : Row} {G : System} (hmem : mk u ∅ C ∈ G) :
    allVars (concretizeKeep u C G) ⊆ allVars G := by
  intro v hv
  obtain ⟨c, hc, hvc⟩ := Finset.mem_biUnion.mp hv
  rcases mem_concretizeKeep.mp hc with rfl | ⟨d, hd, -, rfl⟩ | ⟨hcG, -, -⟩
  · rcases Finset.mem_insert.mp hvc with rfl | hvc
    · exact lhs_mem_allVars hmem
    · simp only [vset_mk] at hvc; exact absurd hvc (Finset.notMem_empty v)
  · rcases Finset.mem_insert.mp hvc with rfl | hvc
    · rw [absorbC_lhs]; exact lhs_mem_allVars hd
    · exact mem_allVars hd (Or.inr (vset_absorbC_subset u C d hvc))
  · exact mem_allVars hcG (Finset.mem_insert.mp hvc)

/-- A system whose vocabulary misses `u` is untouched by, and survives, any concretisation
of `u`. -/
theorem subset_concretizeKeep_of_fresh {u : Var} {C : Row} {G H : System}
    (hsub : G ⊆ H) (hfresh : u ∉ allVars G) : G ⊆ concretizeKeep u C H := by
  intro c hc
  exact mem_concretizeKeep.mpr (Or.inr (Or.inl
    ⟨c, hsub hc, fun hh => hfresh (hh ▸ lhs_mem_allVars hc),
      absorbC_of_notMem fun hh => hfresh (mem_allVars hc (Or.inr hh))⟩))

/-! ### 1.1 Two facts worth having: idempotence and uniqueness -/

/-- Nothing in the image mentions `u` any more. -/
theorem notMem_vset_absorbC (u : Var) (C : Row) (c : Constraint) :
    u ∉ vset (absorbC u C c) := by
  unfold absorbC
  split_ifs with hmem
  · rw [vset_mk]; exact Finset.notMem_erase _ _
  · exact hmem

/-- **`concretizeKeep` is idempotent.**  A second concretisation of the same variable at the
same value is a no-op, so the productivity side condition of `KLoopRun` forbids repeating
one: every `makeConcrete` in a run either changes the system or is not a step. -/
theorem concretizeKeep_idem (u : Var) (C : Row) (G : System) :
    concretizeKeep u C (concretizeKeep u C G) = concretizeKeep u C G := by
  ext c
  constructor
  · intro hc
    rcases mem_concretizeKeep.mp hc with rfl | ⟨d, hd, hdu, rfl⟩ | ⟨hcG, -, -⟩
    · exact mem_concretizeKeep.mpr (Or.inl rfl)
    · rcases mem_concretizeKeep.mp hd with rfl | ⟨e, he, heu, rfl⟩ | ⟨heG, h1, -⟩
      · exact absurd (lhs_mk u ∅ C) hdu
      · rw [absorbC_of_notMem (notMem_vset_absorbC u C e)]
        exact mem_concretizeKeep.mpr (Or.inr (Or.inl ⟨e, he, heu, rfl⟩))
      · exact absurd h1 hdu
    · exact hcG
  · intro hc
    rcases mem_concretizeKeep.mp hc with rfl | ⟨d, hd, hdu, rfl⟩ | ⟨hcG, h1, h2⟩
    · exact mem_concretizeKeep.mpr (Or.inl rfl)
    · refine mem_concretizeKeep.mpr (Or.inr (Or.inl ⟨absorbC u C d, ?_, ?_, ?_⟩))
      · exact mem_concretizeKeep.mpr (Or.inr (Or.inl ⟨d, hd, hdu, rfl⟩))
      · rw [absorbC_lhs]; exact hdu
      · exact absorbC_of_notMem (notMem_vset_absorbC u C d)
    · exact mem_concretizeKeep.mpr (Or.inr (Or.inr ⟨hc, h1, h2⟩))

/-- **One concretisation per variable, under a model.**  If a system with a model gives `u`
two concrete definitions they are the same, so along a run from a satisfiable input the
value a variable is concretised to is determined by the model. -/
theorem conc_unique_of_model {u : Var} {C C' : Row} {G : System} {rho : Assign}
    (hm : SModels rho G) (h : mk u ∅ C ∈ G) (h' : mk u ∅ C' ∈ G) : C = C' :=
  (denotes_of_conc h hm).symm.trans (denotes_of_conc h' hm)

/-! ## 2. The loop-extended relation -/

/-- **The additive calculus plus the loop's concretisation.**  `additive` is
`KeyedSplit.KDefaultStep`: every non-generative rule, the KEYED `splitConcrete` (mint and
reuse) and guarded `resolution`.  `concrete` is `makeConcrete` / `destructiveSub` as the
compiler performs it (`NameLoss.concretizeKeep`, unconditional `keepDefs` since `a4b62c0`):
it needs the concrete definition `u <- ((|C|))` to be present, and it must change the
system.

This is the relation `KeyedSplit.KDefaultStep` is missing: it DELETES. -/
inductive KLoopStep : System → System → Prop
  | additive {G G' : System} : KDefaultStep G G' → KLoopStep G G'
  | concrete {G : System} {u : Var} {C : Row} :
      mk u ∅ C ∈ G → concretizeKeep u C G ≠ G → KLoopStep G (concretizeKeep u C G)

/-- **Productive runs.**  The side condition is uniform: a step must CHANGE the system.  On
an additive step that is exactly `KRun`'s and `DefaultRun`'s `G ⊂ G'`
(`KLoopRun.ssubset_of_additive`), since `KDefaultStep` is monotone; on a concretise step it
is the `concretizeKeep u C G ≠ G` the constructor already carries, so `KLoopRun` counts
precisely the steps that do something. -/
inductive KLoopRun : ℕ → System → System → Prop
  | refl (G : System) : KLoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      KLoopRun n G₀ G → KLoopStep G G' → G ≠ G' → KLoopRun (n + 1) G₀ G'

/-- On an additive step the uniform side condition is `G ⊂ G'`. -/
theorem KLoopRun.ssubset_of_additive {G G' : System} (h : KDefaultStep G G') (hne : G ≠ G') :
    G ⊂ G' := ⟨h.subset, fun hh => hne (Finset.Subset.antisymm h.subset hh)⟩

/-- **Every keyed loop step either keeps the vocabulary or adds exactly one fresh
variable.**  The concretisation can only shrink it; only the two mints enlarge it, by one.
This is what makes `W3_mints_unbounded` a statement about MINTS. -/
theorem KLoopStep.allVars_cases {G G' : System} (h : KLoopStep G G') :
    allVars G' ⊆ allVars G ∨ ∃ z, z ∉ allVars G ∧ allVars G' = insert z (allVars G) := by
  cases h with
  | additive h =>
    rcases h.allVars_cases with hV | ⟨z, hz, hV⟩
    · exact Or.inl (le_of_eq hV)
    · exact Or.inr ⟨z, hz, hV⟩
  | concrete hmem _ => exact Or.inl (allVars_concretizeKeep_subset hmem)

theorem KLoopStep.allVars_card_le {G G' : System} (h : KLoopStep G G') :
    (allVars G').card ≤ (allVars G).card + 1 := by
  rcases h.allVars_cases with hV | ⟨z, hz, hV⟩
  · exact le_trans (Finset.card_le_card hV) (Nat.le_succ _)
  · rw [hV, Finset.card_insert_of_notMem hz]

/-! ### 2.1 Soundness -/

/-- **The concretise step preserves the model itself** (`NameLoss.concretizeKeep_sound`:
the deleted definitions were consequences of what remains, and the kept ones were in the
system already). -/
theorem KLoopStep.concrete_models {G : System} {u : Var} {C : Row} {rho : Assign}
    (hmem : mk u ∅ C ∈ G) (hm : SModels rho G) : SModels rho (concretizeKeep u C G) :=
  concretizeKeep_sound hmem rho hm

/-- **Soundness of one step**: the model is carried along, unchanged on the old vocabulary.
On an additive mint it is extended at the fresh variable (`KDefaultStep.extend`); on a
concretise step it does not move at all. -/
theorem KLoopStep.extend {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : KLoopStep G G') : ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v := by
  cases h with
  | additive h => exact KDefaultStep.extend hm h
  | concrete hmem _ => exact ⟨rho, KLoopStep.concrete_models hmem hm, fun _ _ => rfl⟩

/-- **Soundness of one step, in the satisfiability form.**  One direction only: a
concretise step DELETES, so a model of the successor need not model the predecessor. -/
theorem KLoopStep.sat_mono {G G' : System} (h : KLoopStep G G') :
    (∃ rho, SModels rho G) → ∃ rho, SModels rho G' := by
  rintro ⟨rho, hm⟩
  obtain ⟨rho', hm', -⟩ := h.extend hm
  exact ⟨rho', hm'⟩

/-- **Soundness of a run**: every system a run from a satisfiable input reaches is
satisfiable.  Again one direction only, for the same reason. -/
theorem KLoopRun.sat_mono {n : ℕ} {G₀ G : System} (h : KLoopRun n G₀ G) :
    (∃ rho, SModels rho G₀) → ∃ rho, SModels rho G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih => exact fun hs => hstep.sat_mono (ih hs)

/-- **A deletion-free run is an additive run**, so `KeyedSplit.KRun.length_le` bounds it
unchanged: everything this file refutes is about the concretise steps. -/
theorem KLoopRun.of_kRun {n : ℕ} {G₀ G : System} (h : KRun n G₀ G) : KLoopRun n G₀ G := by
  induction h with
  | refl G => exact KLoopRun.refl G
  | tail _ hstep hss ih =>
    exact KLoopRun.tail ih (KLoopStep.additive hstep) (fun hh => absurd hh (ne_of_lt hss))

/-- **The question, for the loop-extended relation.**  The analogue of
`KeyedSplit.TerminatesOnSatKeyed`, which is TRUE.  §3 refutes this one. -/
def TerminatesOnSatKeyedLoop : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KLoopRun n G₀ G → n ≤ N


/-! ## 3. The witness: the keyed guard does NOT survive the loop layer

Four variables, two labels, three constraints. -/

/-- The variable the loop concretises first. -/
abbrev u : Var := 0
/-- The abstract part of the KEY WITNESS `u <- (z, (|k|))`. -/
abbrev z : Var := 1
/-- The first abstract part of the kept split premise. -/
abbrev x : Var := 2
/-- The second abstract part of the kept split premise. -/
abbrev y : Var := 3
/-- The field `k`: the concrete part of the split premise, i.e. the KEY. -/
abbrev fk : Label := 7
/-- The field `c`: what is left of `u` once the key is taken away. -/
abbrev fc : Label := 8

/-- The key `(|k|)`. -/
def K : Row := {fk}
/-- The concrete value `(|k, c|)` of `u`. -/
def C : Row := {fk, fc}
/-- `C \ K = (|c|)`: the value the minted name is concretised to. -/
def D : Row := {fc}

theorem C_sdiff_K : C \ K = D := by decide
theorem K_ne : K ≠ ∅ := by decide
theorem K_subset_C : K ⊆ C := by decide

/-- `u <- ((|k, c|))`: the concrete value. -/
def W3conc : Constraint := mk u ∅ C
/-- `u <- (z, (|k|))`: the KEY WITNESS.  One abstract part, so `keepDefs` will not keep it. -/
def W3key : Constraint := mk u {z} K
/-- `u <- (x, y, (|k|))`: the split premise.  Two abstract parts, so `keepDefs` keeps it. -/
def W3def : Constraint := mk u {x, y} K

/-- **The witness.**  Satisfiable (`W3_models`), and the keyed split guard is CLOSED on it
(`W3_resolved`), so the additive calculus cannot mint here at all. -/
def W3 : System := {W3conc, W3key, W3def}

/-- The system the first `makeConcrete` reaches: the key witness deleted, the split premise
kept. -/
def W3sat : System := {W3conc, W3def}

/-- The model. -/
def rho3 : Assign := fun v => if v = u then C else if v = z then D else if v = x then D else ∅

theorem W3_models : SModels rho3 W3 := by
  intro c hc
  simp only [W3, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl
  · rw [W3conc, sat_mk_iff]
    refine ⟨by simp [rho3, C], by simp, by simp⟩
  · rw [W3key, sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩
    · simp only [Finset.singleton_biUnion]
      decide
    · intro v hv
      rw [Finset.mem_singleton] at hv
      subst hv
      decide
    · intro v hv w hw hvw
      rw [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw
  · rw [W3def, sat_mk_iff]
    refine ⟨?_, ?_, ?_⟩
    · decide
    · intro v hv
      simp only [Finset.mem_insert, Finset.mem_singleton] at hv
      rcases hv with rfl | rfl <;> decide
    · intro v hv w hw hvw
      simp only [Finset.mem_insert, Finset.mem_singleton] at hv hw
      rcases hv with rfl | rfl <;> rcases hw with rfl | rfl <;>
        first
          | exact absurd rfl hvw
          | decide

theorem W3_satisfiable : ∃ rho, SModels rho W3 := ⟨rho3, W3_models⟩

/-- **The keyed guard is closed at the input.**  `W3key` is a witness for the key `(u, K)`,
so `KSplitApp` cannot fire on `W3def`: this is not a system on which the additive calculus
mints at all. -/
theorem W3_resolved : Resolved W3 u K := resolved_of_mem (show mk u {z} K ∈ W3 by simp [W3, W3key])

/-! ### 3.1 The first step: `makeConcrete u` deletes the key witness -/

theorem filter_W3 : W3.filter (fun c => c.lhs ≠ u) = ∅ := by
  ext c
  simp only [Finset.mem_filter, Finset.notMem_empty, iff_false, not_and, not_not]
  intro hc
  simp only [W3, W3conc, W3key, W3def, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl <;> rfl

theorem kept_W3 : W3.filter (fun c => c.lhs = u ∧ 2 ≤ (vset c).card) = {W3def} := by
  ext c
  simp only [Finset.mem_filter, Finset.mem_singleton]
  constructor
  · rintro ⟨hc, -, h2⟩
    simp only [W3, W3conc, W3key, W3def, Finset.mem_insert, Finset.mem_singleton] at hc
    rcases hc with rfl | rfl | rfl
    · rw [vset_mk] at h2; simp at h2
    · rw [vset_mk] at h2; simp at h2
    · rfl
  · rintro rfl
    refine ⟨by simp [W3], rfl, ?_⟩
    rw [W3def, vset_mk]
    decide

/-- **The concretisation of `u`, computed.**  `u <- (z, (|k|))` is gone -- one abstract part,
so `keepDefs` does not keep it -- and `u <- (x, y, (|k|))` stays. -/
theorem W3_concretize_eq : concretizeKeep u C W3 = W3sat := by
  rw [concretizeKeep, concretize, filter_W3, Finset.image_empty, kept_W3]
  rw [W3sat, W3conc]
  ext c
  simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton, Finset.notMem_empty,
    or_false]

theorem W3_concretize_ne : concretizeKeep u C W3 ≠ W3 := by
  rw [W3_concretize_eq]
  intro hh
  have : W3key ∈ W3sat := hh ▸ (show W3key ∈ W3 by simp [W3])
  simp only [W3sat, W3key, W3conc, W3def, Finset.mem_insert, Finset.mem_singleton] at this
  rcases this with hh | hh
  · exact absurd (NameLoss.mk_eq_iff.mp hh).2.1 (by decide)
  · exact absurd (NameLoss.mk_eq_iff.mp hh).2.1 (by decide)

/-- **The first step of the divergent run**: `makeConcrete u`, which deletes the key
witness the keyed guard depends on. -/
theorem W3_concrete_step : KLoopStep W3 W3sat := by
  rw [← W3_concretize_eq]
  exact KLoopStep.concrete (show mk u ∅ C ∈ W3 by simp [W3, W3conc]) W3_concretize_ne

theorem W3_ne_W3sat : W3 ≠ W3sat := fun hh =>
  W3_concretize_ne (W3_concretize_eq.trans hh.symm)

/-! ### 3.2 The invariant and the round -/

/-- **The invariant the engine restores every round.**  `u` is concrete, it has a KEPT split
premise with two abstract parts and a nonempty concrete part, and the key `(u, K)` is OPEN --
so the keyed guard permits a mint. -/
structure W3Inv (G : System) : Prop where
  intro ::
  /-- the concrete value of `u` -/
  conc : mk u ∅ C ∈ G
  /-- the kept split premise -/
  kept : mk u {x, y} K ∈ G
  /-- the key is open -/
  unres : ¬ Resolved G u K

theorem W3sat_inv : W3Inv W3sat := by
  refine ⟨by simp [W3sat, W3conc], by simp [W3sat, W3def], ?_⟩
  intro hr
  obtain ⟨s, hs⟩ := (resolved_iff _ _ _).mp hr
  simp only [W3sat, W3conc, W3def, Finset.mem_insert, Finset.mem_singleton] at hs
  rcases hs with hh | hh
  · exact absurd (NameLoss.mk_eq_iff.mp hh).2.1 (Finset.singleton_ne_empty s)
  · have h5 : x ∈ ({s} : Finset Var) := by
      rw [(NameLoss.mk_eq_iff.mp hh).2.1]; decide
    have h6 : y ∈ ({s} : Finset Var) := by
      rw [(NameLoss.mk_eq_iff.mp hh).2.1]; decide
    rw [Finset.mem_singleton] at h5 h6
    exact absurd (h5.trans h6.symm) (by decide)

/-- The system after the round's keyed MINT. -/
def R1 (G : System) (w : Var) : System := insert (mk w {x, y} ∅) (insert (mk u {w} K) G)

/-- ... and after the round's CANCELLATION. -/
def R2 (G : System) (w : Var) : System := insert (mk w ∅ D) (R1 G w)

theorem mem_R2 (G : System) (w : Var) {c : Constraint} :
    c ∈ R2 G w ↔ c = mk w ∅ D ∨ c = mk w {x, y} ∅ ∨ c = mk u {w} K ∨ c ∈ G := by
  simp only [R2, R1, Finset.mem_insert]

theorem subset_R1 (G : System) (w : Var) : G ⊆ R1 G w := fun _ hc =>
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem hc)

theorem subset_R2 (G : System) (w : Var) : G ⊆ R2 G w := fun _ hc =>
  Finset.mem_insert_of_mem (subset_R1 G w hc)

/-- **The round.**  Three productive steps of `KLoopStep` from any system satisfying the
invariant: the keyed MINT, the CANCELLATION that makes the minted name concrete, and the
`makeConcrete` of the minted name -- which absorbs the mention `u <- (w, (|k|))` and so
DELETES the very key witness the mint had just installed.  The invariant is restored and the
vocabulary has grown by one. -/
theorem W3Inv.round {G : System} (h : W3Inv G) :
    ∃ G', KLoopRun 3 G G' ∧ W3Inv G' ∧ (allVars G).card < (allVars G').card := by
  obtain ⟨w, hw⟩ := exists_fresh (allVars G)
  have huG : u ∈ allVars G := lhs_mem_allVars h.conc
  have hwu : w ≠ u := by rintro rfl; exact hw huG
  have hkey_notmem : ∀ s : Var, mk u {s} K ∉ G := fun s hs => h.unres (resolved_of_mem hs)
  -- STEP 1: the keyed mint
  have hsplitEq : splitResult G (mk u {x, y} K) w = R1 G w := by
    simp only [splitResult, R1, vset_mk, lhs_mk, conc_mk]
  have hsplitApp : KSplitApp G (mk u {x, y} K) w := by
    refine ⟨h.kept, ?_, ?_, ?_, hw⟩
    · rw [conc_mk]; exact K_ne
    · rw [vset_mk]; decide
    · simp only [lhs_mk, conc_mk]; exact h.unres
  have hstep1 : KLoopStep G (R1 G w) := by
    rw [← hsplitEq]
    exact KLoopStep.additive (KDefaultStep.split (KSplitStep.mint hsplitApp))
  have hne1 : G ≠ R1 G w := by
    intro hh
    exact hkey_notmem w (hh ▸ (show mk u {w} K ∈ R1 G w by simp [R1]))
  -- STEP 2: the cancellation
  have hmemMention : mk u {w} K ∈ R1 G w := by simp [R1]
  have hcancelApp : CancelApp (R1 G w) (mk u {w} K) (mk u ∅ C) w := by
    refine ⟨hmemMention, subset_R1 G w h.conc, rfl, ?_, ?_⟩
    · rw [conc_mk, conc_mk]; exact K_subset_C
    · rw [vset_mk, vset_mk, Finset.sdiff_empty]
  have hcancelEq :
      cancelResult (R1 G w) (mk u {w} K) (mk u ∅ C) w = R2 G w := by
    simp only [cancelResult, R2, vset_mk, conc_mk, Finset.empty_sdiff, C_sdiff_K]
  have hstep2 : KLoopStep (R1 G w) (R2 G w) := by
    rw [← hcancelEq]
    exact KLoopStep.additive (KDefaultStep.nongen
      (NonGenStep.cancel (CancelStep.intro hcancelApp)))
  have hne2 : R1 G w ≠ R2 G w := by
    intro hh
    have hmem : mk w ∅ D ∈ R1 G w := hh ▸ (show mk w ∅ D ∈ R2 G w by simp [R2])
    simp only [R1, Finset.mem_insert] at hmem
    rcases hmem with h1 | h1 | h1
    · have hx : x ∈ (∅ : Finset Var) := by
        rw [(NameLoss.mk_eq_iff.mp h1).2.1]; decide
      exact absurd hx (Finset.notMem_empty x)
    · exact hwu (NameLoss.mk_eq_iff.mp h1).1
    · exact hw (lhs_mem_allVars h1)
  -- STEP 3: makeConcrete w -- the destructive rewrite of the mention
  have hmemD : mk w ∅ D ∈ R2 G w := (mem_R2 G w).mpr (Or.inl rfl)
  have hres3 : ¬ Resolved (concretizeKeep w D (R2 G w)) u K := by
    intro hr
    obtain ⟨s, hs⟩ := (resolved_iff _ _ _).mp hr
    rcases mem_concretizeKeep.mp hs with heq | ⟨d, hd, hdw, hab⟩ | ⟨-, h1, -⟩
    · exact hwu (NameLoss.mk_eq_iff.mp heq).1.symm
    · by_cases hmem : w ∈ vset d
      · have habs : absorbC w D d = mk d.lhs ((vset d).erase w) (d.conc ∪ D) := by
          unfold absorbC; rw [if_pos hmem]
        rw [habs] at hab
        have hcc : d.conc ∪ D = K := (NameLoss.mk_eq_iff.mp hab).2.2
        have hfc : fc ∈ K := by
          rw [← hcc]; exact Finset.mem_union_right _ (by decide)
        exact absurd hfc (by decide)
      · rw [absorbC_of_notMem hmem] at hab
        subst hab
        rcases (mem_R2 G w).mp hd with heq | heq | heq | hmemG
        · exact hwu (NameLoss.mk_eq_iff.mp heq).1.symm
        · exact hwu (NameLoss.mk_eq_iff.mp heq).1.symm
        · have hsw : s = w := by
            have h5 : s ∈ ({w} : Finset Var) := by
              rw [← (NameLoss.mk_eq_iff.mp heq).2.1]; exact Finset.mem_singleton_self s
            exact Finset.mem_singleton.mp h5
          exact hmem (by rw [vset_mk, hsw]; exact Finset.mem_singleton_self w)
        · exact hkey_notmem s hmemG
    · rw [lhs_mk] at h1; exact hwu h1.symm
  have hsub3 : G ⊆ concretizeKeep w D (R2 G w) :=
    subset_concretizeKeep_of_fresh (subset_R2 G w) hw
  have hne3 : R2 G w ≠ concretizeKeep w D (R2 G w) := by
    intro hh
    exact hres3 (resolved_of_mem
      (hh ▸ (show mk u {w} K ∈ R2 G w from (mem_R2 G w).mpr (Or.inr (Or.inr (Or.inl rfl))))))
  have hstep3 : KLoopStep (R2 G w) (concretizeKeep w D (R2 G w)) :=
    KLoopStep.concrete hmemD (Ne.symm hne3)
  -- the name minted this round survives as a kept definition, so the vocabulary grew
  have hwmem : mk w {x, y} ∅ ∈ concretizeKeep w D (R2 G w) :=
    mem_concretizeKeep.mpr (Or.inr (Or.inr
      ⟨(mem_R2 G w).mpr (Or.inr (Or.inl rfl)), rfl, by rw [vset_mk]; decide⟩))
  have hcard : (allVars G).card < (allVars (concretizeKeep w D (R2 G w))).card := by
    refine Finset.card_lt_card ((Finset.ssubset_iff_of_subset (allVars_mono hsub3)).mpr
      ⟨w, mem_allVars hwmem (Or.inl rfl), hw⟩)
  refine ⟨concretizeKeep w D (R2 G w), ?_, ⟨hsub3 h.conc, hsub3 h.kept, hres3⟩, hcard⟩
  exact KLoopRun.tail (KLoopRun.tail (KLoopRun.tail (KLoopRun.refl G) hstep1 hne1)
    hstep2 hne2) hstep3 hne3

/-! ### 3.3 The run, and the refutation -/

theorem KLoopRun.append {m n : ℕ} {G₀ G G' : System} (h1 : KLoopRun m G₀ G)
    (h2 : KLoopRun n G G') : KLoopRun (m + n) G₀ G' := by
  revert h1
  induction h2 with
  | refl G => intro h1; simpa using h1
  | tail _ hstep hne ih =>
    intro h1
    rw [← Nat.add_assoc]
    exact KLoopRun.tail (ih h1) hstep hne

theorem KLoopRun.exists_prefix {n : ℕ} {G₀ G : System} (h : KLoopRun n G₀ G) :
    ∀ k ≤ n, ∃ G', KLoopRun k G₀ G' := by
  induction h with
  | refl G => intro k hk; exact ⟨G, Nat.le_zero.mp hk ▸ KLoopRun.refl G⟩
  | @tail n G₀ Ga Gb hrun hstep hne ih =>
    intro k hk
    rcases Nat.lt_or_ge k (n + 1) with hlt | hge
    · exact ih k (Nat.lt_succ_iff.mp hlt)
    · exact ⟨Gb, Nat.le_antisymm hk hge ▸ KLoopRun.tail hrun hstep hne⟩

/-- **The engine, iterated.**  From any system satisfying the invariant there are runs of
length `3 * n` for every `n`, along which the vocabulary grows by `n`. -/
theorem W3Inv.run {G : System} (h : W3Inv G) (n : ℕ) :
    ∃ G', KLoopRun (3 * n) G G' ∧ W3Inv G' ∧ (allVars G).card + n ≤ (allVars G').card := by
  induction n with
  | zero => exact ⟨G, KLoopRun.refl G, h, by omega⟩
  | succ n ih =>
    obtain ⟨G', hrun, hinv, hcard⟩ := ih
    obtain ⟨G'', hrun', hinv', hcard'⟩ := hinv.round
    refine ⟨G'', ?_, hinv', by omega⟩
    have h3 : 3 * (n + 1) = 3 * n + 3 := by omega
    rw [h3]
    exact hrun.append hrun'

theorem allVars_W3sat : allVars W3sat = {u, x, y} := by
  simp only [allVars, W3sat, W3conc, W3def, Finset.biUnion_insert, Finset.singleton_biUnion,
    vset_mk, lhs_mk]
  decide

theorem card_allVars_W3sat : (allVars W3sat).card = 3 := by
  rw [allVars_W3sat]; decide

/-! ### 3.1a Both of `splitConcrete`'s reverse lookups, before and after

The shipped rule consults the SYNTACTIC lookup (`Named`, `rhss(RHSAbstr(abstr))`) FIRST and
the keyed one only on a miss.  `KSplitApp` carries only the keyed premise, so `KeyedSplit`
bounds a MORE PERMISSIVE relation than the compiler's.  These four statements pin exactly
where the two agree on this witness. -/

/-- At the input the group `{x, y}` is NOT named, so the syntactic guard would mint here.
What refuses the mint at `W3` is the KEYED guard alone (`W3_resolved`) -- `W3` is a system on
which Stage 1's change is the whole difference. -/
theorem W3_not_named : ¬ Named W3 {x, y} := by
  rintro ⟨d, hd, hvs, hc⟩
  simp only [W3, W3conc, W3key, W3def, Finset.mem_insert, Finset.mem_singleton] at hd
  rcases hd with rfl | rfl | rfl
  · rw [vset_mk] at hvs; exact absurd hvs.symm (by decide)
  · rw [vset_mk] at hvs
    have : x ∈ ({z} : Finset Var) := by rw [hvs]; decide
    exact absurd (Finset.mem_singleton.mp this) (by decide)
  · rw [conc_mk] at hc; exact absurd hc (by decide)

/-- ... and it is still not named after the concretisation. -/
theorem W3sat_not_named : ¬ Named W3sat {x, y} := by
  rintro ⟨d, hd, hvs, hc⟩
  simp only [W3sat, W3conc, W3def, Finset.mem_insert, Finset.mem_singleton] at hd
  rcases hd with rfl | rfl
  · rw [vset_mk] at hvs; exact absurd hvs.symm (by decide)
  · rw [conc_mk] at hc; exact absurd hc (by decide)

/-- **`makeConcrete` re-opens a mint that the SHIPPED rule really takes.**  At `W3sat` BOTH
of `splitConcrete`'s reverse lookups miss, so the syntactic `Cut.SplitApp` holds as well as
the keyed `KSplitApp`: this is `NameLoss.orderB_remint_enabled` for the keyed guard, and it
is what the measurement of `tracker/satterm/KEYED-LOOP-STAGE3.md` finds in the real loop at
55 of 100 id bases. -/
theorem W3sat_remint_enabled :
    SplitApp W3sat (mk u {x, y} K) 9 ∧ KSplitApp W3sat (mk u {x, y} K) 9 := by
  have hfresh : (9 : Var) ∉ allVars W3sat := by rw [allVars_W3sat]; decide
  have hmem : mk u {x, y} K ∈ W3sat := by simp [W3sat, W3def]
  have hne : (mk u {x, y} K).conc ≠ ∅ := by rw [conc_mk]; exact K_ne
  have htwo : 2 ≤ (vset (mk u {x, y} K)).card := by rw [vset_mk]; decide
  refine ⟨⟨hmem, hne, htwo, ?_, hfresh⟩, ⟨hmem, hne, htwo, ?_, hfresh⟩⟩
  · simp only [vset_mk]; exact W3sat_not_named
  · simp only [lhs_mk, conc_mk]; exact W3sat_inv.unres

/-- **Scope, machine-checked.**  The name the round mints is a BARE definition of the group
and the round's own concretisation KEEPS it (two abstract parts), so from the SECOND round
on the group is named and the shipped `splitConcrete` -- which asks `rhss(RHSAbstr(abstr))`
first -- would take its syntactic REUSE branch rather than mint.  The unbounded run of
`W3_mints_unbounded` therefore uses, from its second mint on, mints that are steps of
`KDefaultStep` but not of the compiler's rule: `KeyedSplit.lean` deliberately bounds the
more permissive relation, and this file refutes the same statement for the same relation. -/
theorem named_after_round (G : System) (w : Var) : Named (concretizeKeep w D (R2 G w)) {x, y} :=
  ⟨mk w {x, y} ∅,
    mem_concretizeKeep.mpr (Or.inr (Or.inr
      ⟨(mem_R2 G w).mpr (Or.inr (Or.inl rfl)), rfl, by rw [vset_mk]; decide⟩)),
    vset_mk _ _ _, conc_mk _ _ _⟩

/-- **The headline.**  For every `n` the satisfiable `W3` admits a productive run of
`3 * n + 1` loop steps whose vocabulary has grown by `n` variables.  Since the keyed mint is
the ONLY rule of `KLoopStep` that enlarges the vocabulary (`KLoopStep.allVars_cases`), those
are `n` MINTS: this is unbounded generation, not an oscillation between two systems. -/
theorem W3_mints_unbounded (n : ℕ) :
    ∃ G, KLoopRun (3 * n + 1) W3 G ∧ n + 3 ≤ (allVars G).card := by
  obtain ⟨G, hrun, -, hcard⟩ := W3sat_inv.run n
  refine ⟨G, ?_, ?_⟩
  · have h1 : KLoopRun 1 W3 W3sat :=
      KLoopRun.tail (KLoopRun.refl W3) W3_concrete_step W3_ne_W3sat
    have := h1.append hrun
    rwa [Nat.add_comm 1 (3 * n)] at this
  · rw [card_allVars_W3sat] at hcard; omega

/-- **`W3` admits productive loop runs of EVERY length.** -/
theorem W3_diverges (n : ℕ) : ∃ G, KLoopRun n W3 G := by
  obtain ⟨G, hrun, -⟩ := W3_mints_unbounded n
  exact hrun.exists_prefix n (by omega)

/-- **The Stage 3 answer: (W).**  The keyed split guard does NOT survive the loop layer.
`terminatesOnSatKeyed` holds for the additive relation; adding the loop's own
`makeConcrete` / `destructiveSub` step to it makes the same statement FALSE, on a
three-constraint satisfiable input. -/
theorem not_TerminatesOnSatKeyedLoop : ¬ TerminatesOnSatKeyedLoop := by
  intro hT
  obtain ⟨N, hN⟩ := hT W3 rho3 W3_models
  obtain ⟨G, hrun⟩ := W3_diverges (N + 1)
  exact absurd (hN (N + 1) G hrun) (by omega)

/-- **Round 0 loses the key by DELETION** -- failure mode 1.  `W3key` is headed by the
concretised variable and has ONE abstract part, so `keepDefs` (`2 ≤ |vset|`) does not keep
it.  This is the mode the Stage 3 brief names, and it is what opens the mint the additive
theorem refuses. -/
theorem W3_key_deleted : W3key ∈ W3 ∧ W3key ∉ concretizeKeep u C W3 :=
  ⟨by simp [W3], notMem_lone_lhs u z C K W3⟩

/-- **Every later round loses the key by the destructive REWRITE** -- failure mode 2.  The
key witness the mint installs, `u <- (w, (|k|))`, carries the freshly concretised name `w`
on its RIGHT, so `absorbC` rewrites it to `u <- ((|k, c|))` and `concretize` keeps only the
image.  The Stage 3 sketch expected this constraint to survive and close the key for good;
it does not, and that is the whole engine. -/
theorem key_absorbed {G : System} {w : Var} (hwu : u ≠ w) :
    mk u {w} K ∈ R2 G w ∧ mk u {w} K ∉ concretizeKeep w D (R2 G w) :=
  ⟨(mem_R2 G w).mpr (Or.inr (Or.inr (Or.inl rfl))), notMem_lone_mention hwu⟩

/-- **The contrast, in one statement.**  The keyed guard bounds every run of the ADDITIVE
calculus from a satisfiable input, and bounds nothing once the loop's deletion is added. -/
theorem keyed_additive_vs_loop : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSatKeyedLoop :=
  ⟨terminatesOnSatKeyed, not_TerminatesOnSatKeyedLoop⟩

end KeyedLoop
end Rowpartition
