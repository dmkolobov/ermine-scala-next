/-
# The Scala `splitConcrete` is a step of the keyed calculus — as a theorem

`KeyedSplit.lean` defines the rekeyed split (`KSplitApp` / `KSplitReuseApp` / `KSplitStep`)
and proves the calculus `KDefaultStep` terminates on every satisfiable system.  The shipped
implementation (`Constraints.scala`, `def splitConcrete`, under `-Dermine.splitKey`, DEFAULT
ON since 2026-09-03) was then argued to *be* that rule, in a comment at the rule.  The
argument had one soft spot, and it was prose:

> `findResolvent` ranges over `proc ++ incm`, i.e. the current system MINUS the premise `c`
> being dequeued (`incorporateAll` returns `c` to `proc` only after `learnPartitions`
> returns).  `c` cannot witness its own key — a witness has a SINGLE abstract variable and
> `splitConcrete` reaches the guard only with `2 ≤ |abstr|` — so the Scala guard is the Lean
> guard, not an approximation of it.

This module discharges that, and the same question for the OTHER lookup, then states the
whole three-branch rule as a function and proves every branch it takes is a `KDefaultStep`.

## What is proved

**§1, the erase lemmas.**  Both reverse lookups return the same answers on `G.erase c` as on
`G`, each for its own reason:

* `resolved_erase_iff` — for the KEYED lookup, because a witness `mk v {z} K` has
  `|vset| = 1` while `c` reaches the rule only with `2 ≤ |vset c|`.  This is the prose
  above, verbatim.  `ksplit_guard_erase_iff` states it in the guard's own vocabulary
  (`¬ Resolved (G.erase c) c.lhs c.conc ↔ ¬ Resolved G c.lhs c.conc`), and
  `ksplitApp_erase_iff` / `ksplitReuseApp_erase_iff` say that the rules `KSplitApp` and
  `KSplitReuseApp` are unchanged when their lookup is computed on `G.erase c`.  (Note the
  guard, not the whole `KSplitApp G c u`: the premise `mem : c ∈ G` is of course false of
  `G.erase c`, which is why the honest statement quantifies the guard alone.)
* `named_erase_iff` / `names_erase_iff` — for the SYNTACTIC lookup `rhss(RHSAbstr(abstr))`,
  which `findRHS` likewise computes on `incm ++ proc`.  Here the reason is different: a
  witness is a BARE partition `d <- S` with `d.conc = ∅`, and `splitConcrete` reaches the
  lookup only with `c.conc ≠ ∅`.  The prose never mentioned this second gap; it closes the
  same way.

**§2, the rule as a function.**  `scalaSplit G c u rhss resolvent` mirrors `splitConcrete`
branch for branch and in order: the early return `concr.isEmpty || abstr.size < 2` (as
`none`, the Scala's `Set()`), then syntactic reuse, then keyed reuse, then mint.  The two
lookups enter as RESULTS, constrained by their specifications `RhssSpec` / `ResolventSpec`
(the brief's second option, and the cleaner one: it commits to no particular search order,
which the Scala's `Set`/`Map` iteration does not fix either).  `rhssLookup` /
`resolventLookup` and their `_spec` lemmas exhibit results satisfying the specifications, so
nothing here is vacuous, and `scalaSplitOf` is the resulting closed function of `(G, c, u)`.

**The adequacy theorem is `scalaSplit_step`**: with the lookups computed on `G.erase c`,
exactly as the implementation computes them, every system `scalaSplit` returns is a
`KDefaultStep` of `G` — the syntactic branch through `NonGenStep.split`, the keyed branch
through `KSplitStep.reuse`, the mint through `KSplitStep.mint`.  `scalaSplitOf_step` is the
same for the closed function.  `scalaSplit_eq_none_iff` pins the no-op case to the early
return alone, so nothing is silently dropped.

## Scope

`GenRules.splitKey` and `GenRules.splitMints` are both at their shipped default `true`
here.  With `splitMints = false` the third branch returns `Set()` (a no-op, and not a step
of any calculus); with `splitKey = false` the third branch is `Cut.SplitApp` / `SplitStep`,
i.e. `DefaultDiverge.DefaultStep`, which is what `KeyedSplit.keyed_vs_syntactic` says does
NOT terminate.  Neither flag setting is modelled by `scalaSplit`.

Nothing here is about `incorporateAll`'s loop: `KDefaultStep` is the ADDITIVE relation,
`splitConcrete` returns a `Set[Partition]` the caller adds, and the deletions the real loop
performs are outside the calculus (`KeyedSplit`, "Scope", says the same).
-/
import Rowpartition.KeyedSplit

namespace Rowpartition

/-! ## 1. The dequeued premise is invisible to both reverse lookups

`splitConcrete` is called from `learnPartitions`, which `incorporateAll` calls BEFORE
returning the dequeued partition `c` to `proc`.  So both lookups see `G.erase c`, not `G`.
Neither difference is a difference. -/

/-- **The keyed lookup does not see the premise anyway.**  A witness for the key
`(v, K)` is `mk v {z} K`, whose variable set is the singleton `{z}`; the premise `c`
reaches `splitConcrete`'s guard only with `2 ≤ |vset c|`, so `c` is never such a witness
and erasing it changes no answer.  This is the Scala comment at `def splitConcrete`, made
a theorem. -/
theorem resolved_erase_iff {G : System} {c : Constraint} (hc : 2 ≤ (vset c).card)
    (v : Var) (K : Row) : Resolved (G.erase c) v K ↔ Resolved G v K := by
  constructor
  · exact Resolved.mono fun _ hd => (Finset.mem_erase.mp hd).2
  · intro h
    obtain ⟨z, hz⟩ := (resolved_iff G v K).mp h
    refine resolved_of_mem (Finset.mem_erase.mpr ⟨?_, hz⟩)
    intro hEq
    have h1 : (vset (mk v {z} K)).card = 1 := by simp
    rw [hEq] at h1
    omega

/-- The same statement in the guard's own vocabulary: the keyed MINT guard computed on
`G.erase c`, as `findResolvent` computes it, is the guard `KSplitApp.unresolved` asks for. -/
theorem ksplit_guard_erase_iff {G : System} {c : Constraint} (hc : 2 ≤ (vset c).card) :
    ¬ Resolved (G.erase c) c.lhs c.conc ↔ ¬ Resolved G c.lhs c.conc :=
  not_congr (resolved_erase_iff hc c.lhs c.conc)

/-- **`KSplitApp` is unchanged when its lookup is computed on `G.erase c`.**  Stated as the
conjunction of the premises rather than as `KSplitApp (G.erase c) c u ↔ KSplitApp G c u`,
which is false for the trivial reason that `mem : c ∈ G` fails on `G.erase c`: it is the
GUARD that is insensitive to the erase, and the other premises are the caller's. -/
theorem ksplitApp_erase_iff {G : System} {c : Constraint} {u : Var} :
    KSplitApp G c u ↔
      (c ∈ G ∧ c.conc ≠ ∅ ∧ 2 ≤ (vset c).card ∧
        ¬ Resolved (G.erase c) c.lhs c.conc ∧ u ∉ allVars G) := by
  constructor
  · intro h
    exact ⟨h.mem, h.conc_ne, h.two_le,
      (ksplit_guard_erase_iff h.two_le).mpr h.unresolved, h.fresh⟩
  · rintro ⟨h1, h2, h3, h4, h5⟩
    exact ⟨h1, h2, h3, (ksplit_guard_erase_iff h3).mp h4, h5⟩

/-- **`KSplitReuseApp` likewise**: the witness the Scala finds in `proc ++ incm` is a
witness in `G`, and conversely. -/
theorem ksplitReuseApp_erase_iff {G : System} {c : Constraint} {w : Var} :
    KSplitReuseApp G c w ↔
      (c ∈ G ∧ c.conc ≠ ∅ ∧ 2 ≤ (vset c).card ∧ mk c.lhs {w} c.conc ∈ G.erase c) := by
  constructor
  · intro h
    have h3 := h.two_le
    refine ⟨h.mem, h.conc_ne, h3, Finset.mem_erase.mpr ⟨?_, h.witness⟩⟩
    intro hEq
    have h1 : (vset (mk c.lhs {w} c.conc)).card = 1 := by simp
    rw [hEq] at h1
    omega
  · rintro ⟨h1, h2, h3, h4⟩
    exact ⟨h1, h2, h3, (Finset.mem_erase.mp h4).2⟩

/-- **The SYNTACTIC lookup does not see the premise either**, for a different reason: its
witnesses are BARE partitions (`d.conc = ∅`) and `splitConcrete` runs only when
`c.conc ≠ ∅`.  `findRHS(incm, proc, Set())` therefore also computes the lookup of
`Cut.SplitApp` / `SplitNecessary.SplitReuseApp` exactly. -/
theorem named_erase_iff {G : System} {c : Constraint} (hc : c.conc ≠ ∅) (S : Finset Var) :
    Named (G.erase c) S ↔ Named G S := by
  constructor
  · exact Named.mono fun _ hd => (Finset.mem_erase.mp hd).2
  · rintro ⟨d, hd, h2, h3⟩
    exact ⟨d, Finset.mem_erase.mpr ⟨fun hEq => hc (by rw [← hEq]; exact h3), hd⟩, h2, h3⟩

/-- The named version of `named_erase_iff`: the erase does not change WHICH variable the
syntactic lookup may return, either. -/
theorem names_erase_iff {G : System} {c : Constraint} (hc : c.conc ≠ ∅) (z : Var)
    (S : Finset Var) : Names (G.erase c) z S ↔ Names G z S := by
  constructor
  · rintro ⟨d, hd, h1, h2, h3⟩
    exact ⟨d, (Finset.mem_erase.mp hd).2, h1, h2, h3⟩
  · rintro ⟨d, hd, h1, h2, h3⟩
    exact ⟨d, Finset.mem_erase.mpr ⟨fun hEq => hc (by rw [← hEq]; exact h3), hd⟩, h1, h2, h3⟩

/-! ## 2. `splitConcrete` as a function, and its adequacy

The two lookups enter as RESULTS satisfying a specification, not as a particular search:
the Scala's `rhss` and `resolvent` are `Option[TypeVar]`-valued arguments too, and which
witness a `Set`/`Map` traversal returns is not fixed by the source. -/

/-- **Specification of `rhss(RHSAbstr(abstr))`** — `Constraints.findRHS`, computed on
`incm ++ proc`.  `some d` means `d` names the group; `none` means nothing does. -/
def RhssSpec (H : System) (S : Finset Var) : Option Var → Prop
  | some d => Names H d S
  | none => ¬ Named H S

/-- **Specification of `findResolvent(Set())(concr)`** — `learnPartitions`' `resolvents`
map, computed on `proc ++ incm`.  `some w` means `v <- (w, K)` is present; `none` is
`¬ Resolved`.  (The batch argument `s` is `Set()` here: `splitConcrete` is the initial value
of `learnPartitions`' fold, so no partition of the batch exists yet.) -/
def ResolventSpec (H : System) (v : Var) (K : Row) : Option Var → Prop
  | some w => mk v {w} K ∈ H
  | none => ¬ Resolved H v K

/-- **`splitConcrete`, branch for branch.**  `none` is the Scala's `Set()` — the early
return `concr.isEmpty || abstr.size < 2`; `some G'` is `G` plus the emitted partitions.
The three branches are, in the source's order: syntactic reuse, keyed reuse, mint. -/
def scalaSplit (G : System) (c : Constraint) (u : Var) (rhss resolvent : Option Var) :
    Option System :=
  if c.conc = ∅ ∨ (vset c).card < 2 then none
  else
    match rhss with
    | some d => some (splitReuseResult G c d)
    | none =>
      match resolvent with
      | some w => some (kSplitReuseResult G c w)
      | none => some (splitResult G c u)

/-- **The only no-op is the early return.**  Once past `concr.isEmpty || abstr.size < 2`
the rule always emits, whichever branch it takes. -/
theorem scalaSplit_eq_none_iff (G : System) (c : Constraint) (u : Var)
    (rhss resolvent : Option Var) :
    scalaSplit G c u rhss resolvent = none ↔ (c.conc = ∅ ∨ (vset c).card < 2) := by
  by_cases hg : c.conc = ∅ ∨ (vset c).card < 2
  · simp [scalaSplit, hg]
  · simp only [scalaSplit, if_neg hg]
    cases rhss with
    | some d => simp [hg]
    | none => cases resolvent <;> simp [hg]

/-- Past the early return the rule fires. -/
theorem scalaSplit_fires (G : System) (c : Constraint) (u : Var) (rhss resolvent : Option Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    ∃ G', scalaSplit G c u rhss resolvent = some G' := by
  cases h : scalaSplit G c u rhss resolvent with
  | none =>
    rcases (scalaSplit_eq_none_iff G c u rhss resolvent).mp h with h' | h'
    · exact absurd h' hne
    · omega
  | some G' => exact ⟨G', rfl⟩

/-- The guard, as the negation the `if` tests. -/
private theorem scalaSplit_guard {c : Constraint} (hne : c.conc ≠ ∅)
    (hcard : 2 ≤ (vset c).card) : ¬ (c.conc = ∅ ∨ (vset c).card < 2) := by
  rintro (h | h)
  · exact hne h
  · omega

/-- Branch 1, SYNTACTIC REUSE: `rhss(RHSAbstr(abstr)) = Some(d)` emits `v <- (d, concr)`. -/
theorem scalaSplit_syntactic (G : System) (c : Constraint) (u d : Var)
    (resolvent : Option Var) (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaSplit G c u (some d) resolvent = some (splitReuseResult G c d) := by
  simp [scalaSplit, if_neg (scalaSplit_guard hne hcard)]

/-- Branch 2, KEYED REUSE: `resolvent(concr) = Some(w)` emits `w <- (abstr)`. -/
theorem scalaSplit_keyed (G : System) (c : Constraint) (u w : Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaSplit G c u none (some w) = some (kSplitReuseResult G c w) := by
  simp [scalaSplit, if_neg (scalaSplit_guard hne hcard)]

/-- Branch 3, MINT: both lookups missed, so `fresh` is drawn and both conclusions emitted. -/
theorem scalaSplit_mint (G : System) (c : Constraint) (u : Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaSplit G c u none none = some (splitResult G c u) := by
  simp [scalaSplit, if_neg (scalaSplit_guard hne hcard)]

/-- **ADEQUACY.  Every branch the Scala takes is a step of the adopted calculus.**  The two
lookups are computed on `G.erase c` — the current system minus the dequeued premise, which
is what `incorporateAll` hands `learnPartitions` — and `u` is the id `fresh` would draw.
Whatever `scalaSplit` returns, it is a `KDefaultStep` of `G`: the syntactic branch as a
non-generative `SplitReuseStep`, the keyed branch as `KSplitStep.reuse`, the mint as
`KSplitStep.mint`. -/
theorem scalaSplit_step {G : System} {c : Constraint} {u : Var} {rhss resolvent : Option Var}
    {G' : System} (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (h : scalaSplit G c u rhss resolvent = some G') : KDefaultStep G G' := by
  by_cases hg : c.conc = ∅ ∨ (vset c).card < 2
  · rw [scalaSplit.eq_def, if_pos hg] at h
    exact absurd h (by simp)
  obtain ⟨hne, hlt⟩ := not_or.mp hg
  have hcard : 2 ≤ (vset c).card := Nat.not_lt.mp hlt
  cases rhss with
  | some d =>
    rw [scalaSplit_syntactic G c u d resolvent hne hcard, Option.some.injEq] at h
    subst h
    have hd : Names (G.erase c) d (vset c) := hr
    exact KDefaultStep.nongen (NonGenStep.split
      (SplitReuseStep.intro ⟨hmem, hne, hcard, (names_erase_iff hne d (vset c)).mp hd⟩))
  | none =>
    cases resolvent with
    | some w =>
      rw [scalaSplit_keyed G c u w hne hcard, Option.some.injEq] at h
      subst h
      have hw : mk c.lhs {w} c.conc ∈ G.erase c := hres
      exact KDefaultStep.split (KSplitStep.reuse
        (ksplitReuseApp_erase_iff.mpr ⟨hmem, hne, hcard, hw⟩))
    | none =>
      rw [scalaSplit_mint G c u hne hcard, Option.some.injEq] at h
      subst h
      have hnr : ¬ Resolved (G.erase c) c.lhs c.conc := hres
      exact KDefaultStep.split (KSplitStep.mint
        (ksplitApp_erase_iff.mpr ⟨hmem, hne, hcard, hnr, hfresh⟩))

/-- Two immediate consequences of adequacy: the rule only ever ADDS constraints... -/
theorem scalaSplit_subset {G : System} {c : Constraint} {u : Var}
    {rhss resolvent : Option Var} {G' : System} (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (h : scalaSplit G c u rhss resolvent = some G') : G ⊆ G' :=
  (scalaSplit_step hmem hfresh hr hres h).subset

/-- ...and it never changes satisfiability, in either direction. -/
theorem scalaSplit_satisfiable_iff {G : System} {c : Constraint} {u : Var}
    {rhss resolvent : Option Var} {G' : System} (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (h : scalaSplit G c u rhss resolvent = some G') :
    (∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G') :=
  (scalaSplit_step hmem hfresh hr hres h).satisfiable_iff

/-! ### 2.1 The specifications are inhabited, and the erase is invisible to them

`scalaSplit` is only as good as its hypotheses, so here are lookups that satisfy them. -/

/-- A lookup meeting `RhssSpec`.  `Named` is decidable (`SplitNecessary`), so this is the
`if` the Scala's `findRHS` is; the choice of witness is `Exists.choose`, which is why the
definition is `noncomputable` and why the adequacy theorem is stated for ANY result meeting
the specification. -/
noncomputable def rhssLookup (H : System) (S : Finset Var) : Option Var :=
  if h : Named H S then some h.choose.lhs else none

theorem rhssLookup_spec (H : System) (S : Finset Var) : RhssSpec H S (rhssLookup H S) := by
  unfold rhssLookup
  by_cases h : Named H S
  · rw [dif_pos h]
    exact ⟨h.choose, h.choose_spec.1, rfl, h.choose_spec.2.1, h.choose_spec.2.2⟩
  · rw [dif_neg h]
    exact h

/-- A lookup meeting `ResolventSpec`. -/
noncomputable def resolventLookup (H : System) (v : Var) (K : Row) : Option Var :=
  if h : Resolved H v K then some h.choose else none

theorem resolventLookup_spec (H : System) (v : Var) (K : Row) :
    ResolventSpec H v K (resolventLookup H v K) := by
  unfold resolventLookup
  by_cases h : Resolved H v K
  · rw [dif_pos h]
    exact h.choose_spec.2
  · rw [dif_neg h]
    exact h

/-- **The erase is invisible to the syntactic specification**, because `c.conc ≠ ∅`. -/
theorem rhssSpec_erase_iff {G : System} {c : Constraint} (hc : c.conc ≠ ∅) (S : Finset Var)
    (r : Option Var) : RhssSpec (G.erase c) S r ↔ RhssSpec G S r := by
  cases r with
  | some d =>
    change Names (G.erase c) d S ↔ Names G d S
    exact names_erase_iff hc d S
  | none =>
    change ¬ Named (G.erase c) S ↔ ¬ Named G S
    exact not_congr (named_erase_iff hc S)

/-- **The erase is invisible to the keyed specification**, because `2 ≤ |vset c|`. -/
theorem resolventSpec_erase_iff {G : System} {c : Constraint} (hc : 2 ≤ (vset c).card)
    (K : Row) (r : Option Var) :
    ResolventSpec (G.erase c) c.lhs K r ↔ ResolventSpec G c.lhs K r := by
  cases r with
  | some w =>
    change mk c.lhs {w} K ∈ G.erase c ↔ mk c.lhs {w} K ∈ G
    constructor
    · intro hw
      exact (Finset.mem_erase.mp hw).2
    · intro hw
      refine Finset.mem_erase.mpr ⟨?_, hw⟩
      intro hEq
      have h1 : (vset (mk c.lhs {w} K)).card = 1 := by simp
      rw [hEq] at h1
      omega
  | none =>
    change ¬ Resolved (G.erase c) c.lhs K ↔ ¬ Resolved G c.lhs K
    exact not_congr (resolved_erase_iff hc c.lhs K)

/-- `splitConcrete` with both lookups resolved: a closed function of the system, the
premise and the fresh id. -/
noncomputable def scalaSplitOf (G : System) (c : Constraint) (u : Var) : Option System :=
  scalaSplit G c u (rhssLookup (G.erase c) (vset c)) (resolventLookup (G.erase c) c.lhs c.conc)

/-- **Adequacy for the closed function.**  Every system the Scala's `splitConcrete` produces
from a premise of `G`, with a genuinely fresh `u`, is a step of `KDefaultStep` — and so, by
`KeyedSplit.terminatesOnSatKeyed`, a step of a calculus that halts on every satisfiable
input. -/
theorem scalaSplitOf_step {G : System} {c : Constraint} {u : Var} {G' : System}
    (hmem : c ∈ G) (hfresh : u ∉ allVars G) (h : scalaSplitOf G c u = some G') :
    KDefaultStep G G' :=
  scalaSplit_step hmem hfresh (rhssLookup_spec _ _) (resolventLookup_spec _ _ _) h

end Rowpartition
