/-
# KeepInert -- can the kept definitions mint?

`destructiveSub` (`Constraints.scala`, `val keepDefs`, 2026-09-02) now keeps, when a variable
`u` is concretised to `C`, the definitions of `u` with two or more abstract parts -- the
Scala predicate is `abs.size >= 2`, with NO condition on the concrete part.  The faithful
model is `NameLoss.concretizeKeep u C G = concretize u C G ∪ kept u G`, where `kept u G`
is `G.filter (fun c => c.lhs = u ∧ 2 ≤ (vset c).card)`.  Soundness is done
(`NameLoss.concretizeKeep_sound`).  What stands in for termination is the prose of
`TICKET-substitution-gap.md` §7:

> The kept definitions re-enable only the reuse/fold branch of `commonSubexpression` and
> `substitution`, which mint nothing; `resolution` needs single-variable forms, which a
> two-abstract definition is not.

**The question.**  For every kept constraint, does no minting rule (`SplitStep`,
`GResStep`) fire on the kept system that did not fire on the deleting one -- i.e. is the
delta `NonGenStep`-only?

**The answer.**

* `GResStep` is INERT -- the half of the prose that is TRUE.  Both branches of guarded
  resolution, and the guard `Resolved` itself, look only at single-variable constraints
  `mk v {x} C`, and a kept definition has at least two variables.  So every guarded
  resolution step on `concretizeKeep u C G` is a step on `concretize u C G` with the kept
  part carried along unchanged (`keep_gres_inert`), and so is every run
  (`keep_gres_runs_inert`).  Since the loop `incorporateAll` performs a subset of the rule
  set's steps, an inertness result for the rule set transfers to the loop.
* `SplitStep` is NOT inert as stated -- the prose omitted `splitConcrete`.  `SplitApp`
  (`Cut.lean` §5.2) fires on any constraint with a nonempty concrete part and two or more
  variables whose group is unnamed, and a kept definition `u <- (x, y, (|k|))` with `k ≠ ∅`
  is exactly such a premise.  `KeepMint` below is the three-constraint counterexample:
  `keep_mints` (a split fires on the kept system), `concretize_no_split` (none fires on
  the deleting one), `prose_false` (the transfer statement, refuted).
* What IS true of `SplitStep`: (i) for kept definitions with an EMPTY concrete part -- the
  bare names `u <- (x, y)` the `NameLoss` story is about -- the delta is `NonGenStep`-only
  for both minting rules (`keep_mint_inert_of_bare`, `keep_gres_inert`); (ii) a split whose
  premise is a kept definition with a nonempty concrete part is a mint that was ALREADY
  enabled on the INPUT `G` (`keep_split_of_kept`, `KeepMint.mint_enabled_on_input`): the
  kept definition is in `G`, and `Named` is monotone.  Relative to the input no new
  minting rule application appears; relative to the deleting `concretize` one does.

**The hypothesis the prose omitted** is therefore the kept definition's CONCRETE PART.
The `NameLoss` instance has it empty (`uName = u <- (x, y)`), so there the fix is
`NonGenStep`-only; the Scala predicate does not require it.

**Scala branches.**  In `destructiveSub`, `keepDefs = !(srs.isEmpty && keep)`.  On the
`srs.isEmpty && keep` branch NOTHING is deleted (`nproc0 = proc`, `nincm0 = incm`), so every
definition of `v`, of any arity, survives there already; on the other branch the filter `p`
drops every definition and mention of `v`, and `pps.filter(defs)` / `qps.filter(defs)`
re-add the definitions with `abs.size >= 2` -- the `incm` ones back onto the INCOMING
queue, i.e. they are re-examined at dequeue.  `concretizeKeep` models this branch (the one
with a mention of `u`); both branches keep the ≥2-abstract definitions.

**Direction of transfer.**  The rule-set relations here are additive and unordered; the
loop is single-pass and examines each partition once at dequeue.  A rule-set INERTNESS
result (`keep_gres_inert`, `keep_mint_inert_of_bare`) transfers to the loop because the
loop's steps are a subset of the rule set's.  A rule-set COUNTEREXAMPLE
(`KeepMint.keep_mints`) only says the loop MAY mint: whether it does depends on the kept
partition being dequeued after the concretisation -- which, on the `incm` side, it is.

## Contents

* §1  `kept`, and the general inertness lemmas over an arbitrary part `D` all of whose
      members have two or more variables: `mem_of_lone`, `resolved_union_iff`,
      `resPair_union_iff`, `resResult_union`, `resReuseResult_union`,
      `GResStep.of_union`, `GResSteps.of_union`.
* §2  Specialised to `concretizeKeep`: `keep_gres_inert`, `keep_gres_runs_inert`.
* §3  `SplitStep`: `split_of_union_left`, `splitResult_union`, `keep_split_bare_inert`,
      `keep_split_of_kept`, `keep_mint_inert_of_bare`.
* §4  `KeepMint`: the counterexample to the prose as stated.
-/
import Rowpartition.NameLoss
import Rowpartition.ResGuard

namespace Rowpartition
namespace KeepInert

open NameLoss (concretize concretizeKeep absorbC mk_eq_iff)

/-! ## 1. The kept part, and inertness over an arbitrary two-variable part -/

/-- The definitions `destructiveSub` keeps: those of `u` with two or more abstract parts
(the Scala `pps.filter(defs)` / `qps.filter(defs)` with `defs = abs.size >= 2`). -/
def kept (u : Var) (G : System) : System :=
  G.filter (fun c => c.lhs = u ∧ 2 ≤ (vset c).card)

/-- `concretizeKeep` is the deleting concretisation plus the kept part, by definition. -/
theorem concretizeKeep_eq (u : Var) (C : Row) (G : System) :
    concretizeKeep u C G = concretize u C G ∪ kept u G := rfl

theorem kept_card {u : Var} {G : System} {c : Constraint} (hc : c ∈ kept u G) :
    2 ≤ (vset c).card :=
  (Finset.mem_filter.mp hc).2.2

theorem kept_lhs {u : Var} {G : System} {c : Constraint} (hc : c ∈ kept u G) : c.lhs = u :=
  (Finset.mem_filter.mp hc).2.1

theorem kept_mem_G {u : Var} {G : System} {c : Constraint} (hc : c ∈ kept u G) : c ∈ G :=
  (Finset.mem_filter.mp hc).1

theorem kept_subset (u : Var) (G : System) : kept u G ⊆ G := Finset.filter_subset _ _

/-- The kept part is an inert part in the sense of the lemmas below. -/
theorem kept_two_le (u : Var) (G : System) : ∀ d ∈ kept u G, 2 ≤ (vset d).card :=
  fun _ hd => kept_card hd

/-- A single-variable constraint of `K ∪ D` is in `K` when every member of `D` has two or
more variables. -/
theorem mem_of_lone {K D : System} (hD : ∀ d ∈ D, 2 ≤ (vset d).card) {v x : Var} {C : Row}
    (h : mk v {x} C ∈ K ∪ D) : mk v {x} C ∈ K := by
  rcases Finset.mem_union.mp h with h | h
  · exact h
  · exact absurd (hD _ h) (by simp)

/-- The resolvent lookup does not see the inert part. -/
theorem resolved_union_iff {K D : System} (hD : ∀ d ∈ D, 2 ≤ (vset d).card) {v : Var}
    {R : Row} : Resolved (K ∪ D) v R ↔ Resolved K v R := by
  rw [resolved_iff, resolved_iff]
  constructor
  · rintro ⟨z, hz⟩; exact ⟨z, mem_of_lone hD hz⟩
  · rintro ⟨z, hz⟩; exact ⟨z, Finset.mem_union_left _ hz⟩

/-- The premises of `resolution` do not see the inert part. -/
theorem resPair_union_iff {K D : System} (hD : ∀ d ∈ D, 2 ≤ (vset d).card) {v x y : Var}
    {C E : Row} : ResPair (K ∪ D) v x y C E ↔ ResPair K v x y C E := by
  constructor
  · rintro ⟨h1, h2, h3, h4⟩; exact ⟨mem_of_lone hD h1, mem_of_lone hD h2, h3, h4⟩
  · rintro ⟨h1, h2, h3, h4⟩
    exact ⟨Finset.mem_union_left _ h1, Finset.mem_union_left _ h2, h3, h4⟩

theorem resResult_union (K D : System) (v x y : Var) (C E : Row) (z : Var) :
    resResult (K ∪ D) v x y C E z = resResult K v x y C E z ∪ D := by
  simp only [resResult, Finset.insert_union]

theorem resReuseResult_union (K D : System) (x y : Var) (C E : Row) (z : Var) :
    resReuseResult (K ∪ D) x y C E z = resReuseResult K x y C E z ∪ D := by
  simp only [resReuseResult, Finset.insert_union]

/-- **Guarded resolution is inert on a two-variable part.**  Every guarded step on `K ∪ D`
is a guarded step on `K` with `D` carried along unchanged. -/
theorem GResStep.of_union {K D : System} (hD : ∀ d ∈ D, 2 ≤ (vset d).card) {G'' : System}
    (h : GResStep (K ∪ D) G'') : ∃ G''', GResStep K G''' ∧ G'' = G''' ∪ D := by
  cases h with
  | @mint v x y C E z hp hr hz =>
    refine ⟨resResult K v x y C E z, GResStep.mint ((resPair_union_iff hD).mp hp) ?_ ?_,
      resResult_union K D v x y C E z⟩
    · exact fun hr' => hr ((resolved_union_iff hD).mpr hr')
    · exact fun hz' => hz (allVars_mono Finset.subset_union_left hz')
  | @reuse v x y C E z hp hm =>
    exact ⟨resReuseResult K x y C E z, GResStep.reuse ((resPair_union_iff hD).mp hp)
      (mem_of_lone hD hm), resReuseResult_union K D x y C E z⟩

theorem gresSteps_of_union_aux {D : System} (hD : ∀ d ∈ D, 2 ≤ (vset d).card) {n : ℕ}
    {H G'' : System} (h : GResSteps n H G'') :
    ∀ K, H = K ∪ D → ∃ G''', GResSteps n K G''' ∧ G'' = G''' ∪ D := by
  induction h with
  | refl G => exact fun K hK => ⟨K, GResSteps.refl K, hK⟩
  | @tail n G G' G'' _ hstep ih =>
    intro K hK
    obtain ⟨G₁, h₁, rfl⟩ := ih K hK
    obtain ⟨G₂, h₂, rfl⟩ := GResStep.of_union hD hstep
    exact ⟨G₂, GResSteps.tail h₁ h₂, rfl⟩

/-- **... and so is every guarded run**: the inert part is never touched, so it stays
inert. -/
theorem GResSteps.of_union {K D : System} (hD : ∀ d ∈ D, 2 ≤ (vset d).card) {n : ℕ}
    {G'' : System} (h : GResSteps n (K ∪ D) G'') :
    ∃ G''', GResSteps n K G''' ∧ G'' = G''' ∪ D :=
  gresSteps_of_union_aux hD h K rfl

/-! ## 2. Specialised to the kept definitions

This is the half of the prose that is TRUE: `resolution` (guarded or not -- `GResStep.mint`
is `ResStep` with the guard added, `GResStep.mint_toResStep`) needs single-variable
premises, and its guard `Resolved` looks only at single-variable constraints.  The kept
definitions have two or more variables, so every guarded resolution step on the kept
system is one on the deleting system, with the kept part carried along.  Since the loop's
steps are a subset of the rule set's, this transfers to `incorporateAll`. -/

/-- **`GResStep` is inert on the kept definitions.** -/
theorem keep_gres_inert {u : Var} {C : Row} {G G'' : System}
    (h : GResStep (concretizeKeep u C G) G'') :
    ∃ G''', GResStep (concretize u C G) G''' ∧ G'' = G''' ∪ kept u G := by
  rw [concretizeKeep_eq] at h
  exact GResStep.of_union (kept_two_le u G) h

/-- **... and so is every guarded run.** -/
theorem keep_gres_runs_inert {u : Var} {C : Row} {G G'' : System} {n : ℕ}
    (h : GResSteps n (concretizeKeep u C G) G'') :
    ∃ G''', GResSteps n (concretize u C G) G''' ∧ G'' = G''' ∪ kept u G := by
  rw [concretizeKeep_eq] at h
  exact GResSteps.of_union (kept_two_le u G) h

/-! ## 3. `splitConcrete`

The exact sense in which "the delta is `NonGenStep`-only" holds for the minting rules:
for `GResStep` always (§2), and for `SplitStep` when the kept definitions are BARE
(`keep_mint_inert_of_bare`).  A kept definition with a nonempty concrete part is a
`SplitApp` premise on the kept system exactly when it was one on the INPUT
(`keep_split_of_kept`); `KeepMint` shows this can happen while the deleting system admits
no split at all. -/

/-- A split on `K ∪ D` whose premise lies in `K` is a split on `K`: `Named` and `allVars`
are monotone. -/
theorem split_of_union_left {K D : System} {c : Constraint} {w : Var}
    (h : SplitApp (K ∪ D) c w) (hc : c ∈ K) : SplitApp K c w :=
  ⟨hc, h.conc_ne, h.two_le, fun hn => h.unnamed (hn.mono Finset.subset_union_left),
    fun hw => h.fresh (allVars_mono Finset.subset_union_left hw)⟩

theorem splitResult_union (K D : System) (c : Constraint) (w : Var) :
    splitResult (K ∪ D) c w = splitResult K c w ∪ D := by
  simp only [splitResult, Finset.insert_union]

/-- No split fires on a constraint with an empty concrete part, on any system. -/
theorem split_needs_conc {K : System} {c : Constraint} {w : Var} (hconc : c.conc = ∅) :
    ¬ SplitApp K c w :=
  fun h => h.conc_ne hconc

/-- **A bare kept definition is present in the kept system and inert for `splitConcrete`.**
(`u <- (x, y)` -- the `NameLoss` case.) -/
theorem keep_split_bare_inert {u : Var} {C : Row} {G : System} {c : Constraint} {w : Var}
    (hc : c ∈ kept u G) (hconc : c.conc = ∅) :
    c ∈ concretizeKeep u C G ∧ ¬ SplitApp (concretizeKeep u C G) c w :=
  ⟨Finset.mem_union_right _ hc, split_needs_conc hconc⟩

/-- **A split on a kept definition was already enabled on the input.**  The kept definition
`c` is in `G`; its concrete part and arity are what they were; and if `G` named `vset c`
by some `d`, then `d` survives into the kept system -- as a kept definition if `d.lhs = u`
(it has the same arity as `c`), and untouched by `absorbC` otherwise (`u ∉ vset d = vset c`,
the hypothesis `hself`, which holds whenever `c` is a definition of `u` that does not
mention `u` on its own right-hand side) -- contradicting `h.unnamed`. -/
theorem keep_split_of_kept {u : Var} {C : Row} {G : System} {c : Constraint} {w : Var}
    (hc : c ∈ kept u G) (hself : u ∉ vset c) (h : SplitApp (concretizeKeep u C G) c w) :
    ∃ w', SplitApp G c w' := by
  obtain ⟨w', hw'⟩ := exists_fresh (allVars G)
  refine ⟨w', kept_mem_G hc, h.conc_ne, h.two_le, ?_, hw'⟩
  rintro ⟨d, hdG, hdv, hdc⟩
  apply h.unnamed
  refine ⟨d, ?_, hdv, hdc⟩
  by_cases hdu : d.lhs = u
  · -- `d` is itself a kept definition of `u`
    exact Finset.mem_union_right _
      (Finset.mem_filter.mpr ⟨hdG, hdu, by rw [hdv]; exact h.two_le⟩)
  · -- `d` does not mention `u`, so the concretisation leaves it untouched
    apply Finset.mem_union_left
    apply Finset.mem_insert_of_mem
    refine Finset.mem_image.mpr ⟨d, Finset.mem_filter.mpr ⟨hdG, hdu⟩, ?_⟩
    have hud : u ∉ vset d := by rw [hdv]; exact hself
    unfold absorbC
    rw [if_neg hud]

/-- **For bare kept definitions the delta is `NonGenStep`-only for `splitConcrete` too.**
When every kept definition has an empty concrete part, no split on the kept system has a
kept premise, so every split on the kept system is a split on the deleting system with
the kept part carried along. -/
theorem keep_mint_inert_of_bare {u : Var} {C : Row} {G G'' : System}
    (hbare : ∀ d ∈ kept u G, d.conc = ∅) (h : SplitStep (concretizeKeep u C G) G'') :
    ∃ G''', SplitStep (concretize u C G) G''' ∧ G'' = G''' ∪ kept u G := by
  rw [concretizeKeep_eq] at h
  cases h with
  | @intro c w happ =>
    have hcK : c ∈ concretize u C G := by
      rcases Finset.mem_union.mp happ.mem with hc | hc
      · exact hc
      · exact absurd (hbare c hc) happ.conc_ne
    exact ⟨_, SplitStep.intro (split_of_union_left happ hcK),
      splitResult_union _ _ _ _⟩

/-- **The weakest true version, in one statement.**  Every split on the kept system either
is a split on the deleting system with the kept part carried along (the delta is
`NonGenStep`-only there), or has as its premise a kept definition with a NONEMPTY
concrete part -- and by `keep_split_of_kept` that mint was already enabled on the input
`G`.  `KeepMint` shows the second disjunct is inhabited. -/
theorem keep_split_cases {u : Var} {C : Row} {G G'' : System}
    (h : SplitStep (concretizeKeep u C G) G'') :
    (∃ G''', SplitStep (concretize u C G) G''' ∧ G'' = G''' ∪ kept u G) ∨
    (∃ c ∈ kept u G, ∃ w, c.conc ≠ ∅ ∧ SplitApp (concretizeKeep u C G) c w ∧
      G'' = splitResult (concretizeKeep u C G) c w) := by
  cases h with
  | @intro c w happ =>
    rcases Finset.mem_union.mp happ.mem with hc | hc
    · exact Or.inl ⟨_, SplitStep.intro (split_of_union_left happ hc),
        splitResult_union _ _ _ _⟩
    · exact Or.inr ⟨c, hc, w, happ.conc_ne, happ, rfl⟩

/-! ## 4. The counterexample to the prose as stated

    u <- (x, y, (|k|))      u <- ((|k, c|))      R <- (u, z)

`u` has a mention (`R <- (u, z)`), so this is the `srs`-nonempty branch `keepDefs` guards.
Concretising `u := (|k, c|)` deletes the definition `u <- (x, y, (|k|))` and rewrites the
mention to `R <- (z, (|k, c|))`; the repaired step keeps the definition.  On the deleting
system no minting rule fires at all; on the kept system `splitConcrete` fires on the kept
definition -- and it was enabled on the INPUT already.

What the Scala does with this instance: a kept definition still on the incoming queue
(`qps.filter(defs)`) goes back onto it and is examined at dequeue -- `splitConcrete` then
mints `n <- (x, y)` and `u <- (n, (|k|))`, and cancellation of the latter against
`u <- ((|k, c|))` gives `n <- ((|c|))`, a NEW concrete fact the deleting solver never
derived.  A kept definition already processed (`pps.filter(defs)`) goes back into `proc`
and is not re-examined; it was examined before the deletion, when the same mint was
already enabled on the input (`mint_enabled_on_input`).  (A prose remark; the
cancellation is not formalised here.) -/
namespace KeepMint

/-- The concretised variable. -/
abbrev u : Var := 0
/-- The first abstract part of its kept definition. -/
abbrev x : Var := 1
/-- The second abstract part of its kept definition. -/
abbrev y : Var := 2
/-- The variable that mentions `u`. -/
abbrev R : Var := 3
/-- The other part of the mention. -/
abbrev z : Var := 4
/-- The field `k`. -/
abbrev fk : Label := 10
/-- The field `c`. -/
abbrev fc : Label := 11

/-- `u <- (x, y, (|k|))`: the definition with two abstract parts AND a concrete part. -/
def uDef : Constraint := mk u {x, y} {fk}
/-- `u <- ((|k, c|))`: the concrete value. -/
def uConc : Constraint := mk u ∅ {fk, fc}
/-- `R <- (u, z)`: the mention. -/
def rMention : Constraint := mk R {u, z} ∅
/-- The input. -/
def G : System := {uDef, uConc, rMention}
/-- The value `u` is concretised to. -/
def C : Row := {fk, fc}
/-- `R <- (z, (|k, c|))`: the mention after `absorbC`. -/
def rSub : Constraint := mk R {z} {fk, fc}

/-- The closed-term recipe (`NameLoss.nl_decide`, over this file's own abbreviations):
unfold everything down to `mk`-shaped constraints over literal finsets, split `mk = mk`
into component equations, and let `decide` settle the residue.  `decide` cannot see
through `mk` (`slist` is a `Finset.sort`), so every `mk` must be gone first. -/
macro "km_decide" : tactic => `(tactic|
  ((try simp [u, x, y, R, z, fk, fc, G, C, uDef, uConc, rMention, rSub, kept, absorbC, Named,
      allVars, mk_eq_iff, vset_mk, conc_mk, lhs_mk, Finset.subset_iff])
   <;> decide))

theorem uDef_mem : uDef ∈ G := by simp [G]

theorem absorb_rMention : absorbC u C rMention = rSub := by km_decide

theorem filter_G : G.filter (fun c => c.lhs ≠ u) = {rMention} := by
  ext c
  simp only [G, Finset.mem_filter, Finset.mem_insert, Finset.mem_singleton]
  constructor
  · rintro ⟨rfl | rfl | rfl, h⟩
    · exact absurd rfl h
    · exact absurd rfl h
    · rfl
  · rintro rfl
    exact ⟨Or.inr (Or.inr rfl), by km_decide⟩

/-- **The deleting concretisation**: the definition is gone, the mention is rewritten. -/
theorem concretize_eq : concretize u C G = {uConc, rSub} := by
  rw [concretize, filter_G, Finset.image_singleton, absorb_rMention]
  rfl

theorem kept_eq : kept u G = {uDef} := by
  ext c
  simp only [kept, G, Finset.mem_filter, Finset.mem_insert, Finset.mem_singleton]
  constructor
  · rintro ⟨rfl | rfl | rfl, h⟩
    · rfl
    · exact absurd h (by km_decide)
    · exact absurd h (by km_decide)
  · rintro rfl
    exact ⟨Or.inl rfl, by km_decide⟩

/-- **The repaired concretisation**: the same, plus the kept definition. -/
theorem keep_eq : concretizeKeep u C G = insert uDef (concretize u C G) := by
  rw [concretizeKeep_eq, kept_eq, Finset.union_comm, ← Finset.insert_eq]

theorem uDef_mem_keep : uDef ∈ concretizeKeep u C G := by
  rw [keep_eq]; exact Finset.mem_insert_self _ _

/-- The split on the kept definition, with the fresh name `9`. -/
theorem keep_split_app : SplitApp (concretizeKeep u C G) uDef 9 := by
  refine ⟨uDef_mem_keep, by km_decide, by km_decide, ?_, ?_⟩
  · rw [keep_eq, concretize_eq]; km_decide
  · rw [keep_eq, concretize_eq]; km_decide

/-- **The kept system mints.** -/
theorem keep_mints : ∃ G', SplitStep (concretizeKeep u C G) G' :=
  ⟨_, SplitStep.intro keep_split_app⟩

/-- **The deleting system does not**: both its members have at most one variable. -/
theorem concretize_no_split : ∀ G', ¬ SplitStep (concretize u C G) G' := by
  intro G' h
  cases h with
  | @intro c w happ =>
    have hm := happ.mem
    have h2 := happ.two_le
    rw [concretize_eq] at hm
    simp only [Finset.mem_insert, Finset.mem_singleton] at hm
    rcases hm with rfl | rfl <;> revert h2 <;> km_decide

/-- No resolution pair on the deleting system: it has a single single-variable
constraint, and `tops` needs two with different concrete parts. -/
theorem concretize_no_pair {v a b : Var} {Ca Cb : Row}
    (hp : ResPair (concretize u C G) v a b Ca Cb) : False := by
  have h1 := hp.mem₁
  have h2 := hp.mem₂
  have ht := hp.tops
  rw [concretize_eq] at h1 h2
  simp only [uConc, rSub, Finset.mem_insert, Finset.mem_singleton, mk_eq_iff,
    Finset.singleton_ne_empty, Finset.singleton_inj, false_and, and_false, false_or] at h1 h2
  obtain ⟨rfl, rfl, rfl⟩ := h1
  obtain ⟨-, -, rfl⟩ := h2
  exact ht (by decide)

/-- **Neither system admits a guarded resolution step.** -/
theorem concretize_no_gres : ∀ G', ¬ GResStep (concretize u C G) G' := by
  intro G' h
  cases h with
  | @mint v a b Ca Cb w hp _ _ => exact concretize_no_pair hp
  | @reuse v a b Ca Cb w hp _ => exact concretize_no_pair hp

theorem keep_no_gres : ∀ G', ¬ GResStep (concretizeKeep u C G) G' := by
  intro G' h
  obtain ⟨G''', h', -⟩ := keep_gres_inert h
  exact concretize_no_gres G''' h'

/-- **The same mint was open on the INPUT**: `keepDefs` did not create it; deletion had
removed it. -/
theorem mint_enabled_on_input : ∃ w, SplitApp G uDef w :=
  ⟨9, uDef_mem, by km_decide, by km_decide, by km_decide, by km_decide⟩

/-- The kept-premise split is the one `keep_split_of_kept` predicts. -/
theorem keep_split_of_kept_here : ∃ w', SplitApp G uDef w' :=
  keep_split_of_kept (by rw [kept_eq]; exact Finset.mem_singleton_self _) (by km_decide)
    keep_split_app

/-- **No split on the kept system transfers to the deleting system, even without
bookkeeping**: the crisp refutation. -/
theorem no_split_transfer :
    ¬ (∀ (v : Var) (K : Row) (H H'' : System), SplitStep (concretizeKeep v K H) H'' →
        ∃ H''', SplitStep (concretize v K H) H''') := by
  intro hall
  obtain ⟨G', hG'⟩ := keep_mints
  obtain ⟨G''', h⟩ := hall u C G G' hG'
  exact concretize_no_split G''' h

/-- **The prose as stated is false for `splitConcrete`**: "the delta is `NonGenStep`-only",
read as `keep_mint_inert_of_bare` without its bareness hypothesis, fails on this
instance. -/
theorem prose_false :
    ¬ (∀ (v : Var) (K : Row) (H H'' : System), SplitStep (concretizeKeep v K H) H'' →
        ∃ H''', SplitStep (concretize v K H) H''' ∧ H'' = H''' ∪ kept v H) := by
  intro hall
  exact no_split_transfer fun v K H H'' h =>
    let ⟨H''', h', _⟩ := hall v K H H'' h
    ⟨H''', h'⟩

end KeepMint

end KeepInert
end Rowpartition
