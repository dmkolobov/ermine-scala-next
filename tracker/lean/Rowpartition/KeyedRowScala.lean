/-
# The Scala `splitConcrete` / `resolution` WITH the concrete-row reuse are steps of `KeyedRow`

`KeyedRow.lean` (Stage 4) defines the widened guard `Carried = Resolved ∨ ConcCarried`, the
four-branch split `K2SplitStep` and the three-branch resolution `K2ResStep`, and proves that
with BOTH guards widened this way the loop-extended calculus mints boundedly on every
satisfiable input, in every run order (`mintsBoundedOnSatKeyed2Star`).  Stage 5 implements
the two branches in `Constraints.scala` behind `-Dermine.splitRow` and `-Dermine.resRow`
(both DEFAULT OFF).  This module is the transcription: the two rules as functions, mirroring
the source's branch order, with the lookups entering as RESULTS meeting a specification, and
adequacy — every system either rule returns is a step of `KeyedRow`'s relation.

It is the Stage 5 counterpart of `KeyedSplitScala.lean`, and it is written the same way.

## What the Scala's lookup actually is, and how it differs from `mk v ∅ C ∈ G`

`learnPartitions` builds, in ONE pass over `proc ++ incm`, a map `concRows : Map[Fields,
TypeVar]` of every BARE CONCRETE partition `u <- ((|con|))` (`RHS(abs, con)` with
`abs.isEmpty`) and, on the way, `myRow : Option[Fields]` — the bare concrete row of the `v`
at hand.  `findConcRow(k)` is then

    myRow.filter(k subsetOf _).flatMap(C => concRows.get(C -- k))

so it differs from the Lean's `∃ C, mk v ∅ C ∈ G ∧ mk z ∅ (C \ K) ∈ G` in exactly two ways,
and BOTH are modelled here rather than argued away:

1. **`v`'s concrete row is a single `Option`, not an existential.**  The fold keeps one row
   per variable (the last one it meets).  `MyRowSpec` below is that `Option`.
2. **`k ⊆ C` is asked explicitly**, which `K2RowApp` does not ask (its soundness proof
   derives it from the model, `concRow_reuse_sat`).

Both differences are in the SAFE direction for the reuse branch — a hit is still a
`K2RowApp` — but they are NOT safe for free at the MINT branch, whose guard `¬ Carried`
quantifies over ALL `C`.  Under a MODEL they cost nothing: `conc_unique_of_model` says a
variable has at most one concrete row, and the premise plus the model force `k ⊆ C`
(`conc_key_subset_of_model` below).  So the adequacy theorems here take `SModels rho G` as a
hypothesis — which is the scope the termination theorems quantify over anyway
(`mintsBoundedOnSatKeyed2Star` is a statement about satisfiable input).  Without a model the
Scala's mint is NOT provably a `K2MintApp`, and that is stated, not hidden:
`concRow_none_uncarried` is exactly where the model is used.

**Where the concrete row lives in the compiler** (the faithfulness note the Lean cannot
supply, recorded here because it is what justifies reading `concRows` as `mk v ∅ C ∈ G` at
all).  A NONEMPTY concrete row of `v` is a bare partition in the QUEUES and nowhere else:
`makeConcrete` does not call `instantiateType`, and it returns the dequeued partition to
`proc` (`nproc + Partition(v, RHSConcr(fs))`).  The EMPTY row is the exception — `makeEmpty`
writes `v := ConcreteRho(∅)` into the `SubstEnv` and DELETES every partition mentioning `v`,
so an already-emptied variable is invisible to `concRows`.  `unify` likewise moves
`v := VarT(u)` into the `SubstEnv` and removes `v`'s partitions.  The lookup is therefore a
LOWER bound on `∈ G`: it can miss where the Lean would hit, never the other way round, so
every firing is a genuine step and the extra misses only mean extra mints.

## What is proved

* §1  `MyRowSpec`, `ConcRowSpec`, inhabited (`myRowLookup`, `concRowLookup`).
* §2  The dequeued premise is invisible to the new lookup — `bare_erase_iff` and its two
      spec-level corollaries.  The reason is new: a `concRows` witness is a BARE partition
      and both rules reach the lookup with a NONEMPTY variable set.
* §3  `scalaRowSplit`, the FOUR branches of `splitConcrete` in the source's order, with
      `scalaRowSplit_eq_none_iff` pinning the only no-op to the early return, and
      **`scalaRowSplit_step` / `scalaRowSplit_defaultStep`: every system it returns is a
      `K2SplitStep` / `K2DefaultStep` of `G`**.
* §4  `scalaRowRes`, the THREE branches of `resolution` in the source's order, with
      `scalaRowRes_eq_none_iff` and **`scalaRowRes_step` / `scalaRowRes_starStep`**.
* §5  The two rules together: `scalaRowSplit_starStep`, and `conc_key_subset_of_model` /
      `concRow_none_uncarried`, the place the model is used.

## Scope

`GenRules.splitMints` and `GenRules.resolves` are at their shipped default here; with
`splitMints = false` the third branch returns `Set()`, which is a no-op and a step of no
calculus, and is not modelled.  `-Dermine.splitKey` is ON (its branch is `K2SplitStep.key`);
with it off the third lookup is still asked, which is a configuration `scalaRowSplit` does
not model either.  Nothing here is about `incorporateAll`'s loop: these are the ADDITIVE
rules, and the deletions are `KeyedRow`'s `concretizeSrs`, a separate constructor.

One difference of the SHIPPED `resGuard` lookup, pre-existing and not introduced by Stage 5:
`findResolvent(s)` also consults the current BATCH `s` of partitions this fold has derived
but not yet added to the system, so `ResolventSpec` on `G.erase c` is what `resolution` sees
only when `s = ∅` (which is exactly `splitConcrete`'s case).  The NEW lookup does not consult
`s` at all, so `ConcRowSpec (G.erase c)` is literally what the Scala computes.
-/
import Rowpartition.KeyedRow
import Rowpartition.KeyedSplitScala

namespace Rowpartition

open NameLoss (denotes_of_conc)
open KeyedLoop (conc_unique_of_model)

namespace KeyedRow

/-! ## 1. The specifications of the two new lookups -/

/-- **Specification of `learnPartitions`' `concRows._2`** — the bare concrete row of the `v`
at hand, which the one-pass fold records as a single `Option[Fields]`.  `some C` means
`v <- ((|C|))` is in the system; `none` means no bare concrete partition of `v` is. -/
def MyRowSpec (H : System) (v : Var) : Option Row → Prop
  | some C => mk v ∅ C ∈ H
  | none => ∀ C : Row, mk v ∅ C ∉ H

/-- **Specification of `findConcRow`** — `myRow.filter(k subsetOf _).flatMap(C =>
concRows.get(C -- k))`.  `some w` is the branch's premise, together with the `k ⊆ C` the
Scala asks and `K2RowApp` does not.  `none` is what the MINT guard gets: with the row `C`
the fold recorded, either `K ⊄ C` or nothing carries `C \ K`. -/
def ConcRowSpec (H : System) (K : Row) : Option Row → Option Var → Prop
  | C?, some w => ∃ C, C? = some C ∧ K ⊆ C ∧ mk w ∅ (C \ K) ∈ H
  | C?, none => ∀ C, C? = some C → K ⊆ C → ∀ w, mk w ∅ (C \ K) ∉ H

/-- A lookup meeting `MyRowSpec`; the existential is bounded by `H` exactly as
`ConcCarried`'s is, so that the `if` is decidable, and the choice of witness is
`Exists.choose`, which is why this is `noncomputable` and why adequacy is stated for ANY
result meeting the specification. -/
noncomputable def myRowLookup (H : System) (v : Var) : Option Row :=
  if h : ∃ C ∈ H.image Constraint.conc, mk v ∅ C ∈ H then some h.choose else none

theorem myRowLookup_spec (H : System) (v : Var) : MyRowSpec H v (myRowLookup H v) := by
  unfold myRowLookup
  by_cases h : ∃ C ∈ H.image Constraint.conc, mk v ∅ C ∈ H
  · rw [dif_pos h]
    exact h.choose_spec.2
  · rw [dif_neg h]
    intro C hC
    exact h ⟨C, Finset.mem_image.mpr ⟨mk v ∅ C, hC, rfl⟩, hC⟩

/-- A lookup meeting `ConcRowSpec`, bounded the same way. -/
noncomputable def concRowLookup (H : System) (K : Row) : Option Row → Option Var
  | none => none
  | some C =>
      if h : K ⊆ C ∧ ∃ w ∈ allVars H, mk w ∅ (C \ K) ∈ H then some h.2.choose else none

theorem concRowLookup_spec (H : System) (K : Row) (C? : Option Row) :
    ConcRowSpec H K C? (concRowLookup H K C?) := by
  cases C? with
  | none =>
    change ∀ C, (none : Option Row) = some C → _
    intro C hC
    exact absurd hC (by simp)
  | some C =>
    by_cases h : K ⊆ C ∧ ∃ w ∈ allVars H, mk w ∅ (C \ K) ∈ H
    · rw [show concRowLookup H K (some C) = some h.2.choose by
            simp only [concRowLookup]; rw [dif_pos h]]
      exact ⟨C, rfl, h.1, h.2.choose_spec.2⟩
    · rw [show concRowLookup H K (some C) = none by
            simp only [concRowLookup]; rw [dif_neg h]]
      change ∀ C', (some C : Option Row) = some C' → _
      intro C' hC' hsub w hw
      cases Option.some.inj hC'
      exact h ⟨hsub, ⟨w, lhs_mem_allVars hw, hw⟩⟩

/-! ## 2. The dequeued premise is invisible to the new lookup

`splitConcrete` and `resolution` are both called from `learnPartitions`, which
`incorporateAll` calls BEFORE returning the dequeued partition `c` to `proc`.  So the
lookups see `G.erase c`.  For the CONCRETE-ROW lookup the reason this is not a difference is
a third one, different from both of `KeyedSplitScala`'s: its witnesses are BARE partitions
(`vset = ∅`), and both rules reach it with a NONEMPTY variable set — `2 ≤ |vset c|` for the
split, `vset c = {x}` for resolution. -/

/-- **A bare partition is never the dequeued premise**, as long as the premise mentions at
least one variable. -/
theorem bare_erase_iff {G : System} {c : Constraint} (hc : vset c ≠ ∅) (u : Var) (R : Row) :
    mk u ∅ R ∈ G.erase c ↔ mk u ∅ R ∈ G := by
  constructor
  · exact fun h => (Finset.mem_erase.mp h).2
  · intro h
    refine Finset.mem_erase.mpr ⟨?_, h⟩
    intro hEq
    apply hc
    rw [← hEq]
    simp

theorem myRowSpec_erase_iff {G : System} {c : Constraint} (hc : vset c ≠ ∅) (v : Var)
    (r : Option Row) : MyRowSpec (G.erase c) v r ↔ MyRowSpec G v r := by
  cases r with
  | some C => exact bare_erase_iff hc v C
  | none =>
    constructor
    · intro h C hC; exact h C ((bare_erase_iff hc v C).mpr hC)
    · intro h C hC; exact h C ((bare_erase_iff hc v C).mp hC)

theorem concRowSpec_erase_iff {G : System} {c : Constraint} (hc : vset c ≠ ∅) (K : Row)
    (C? : Option Row) (r : Option Var) :
    ConcRowSpec (G.erase c) K C? r ↔ ConcRowSpec G K C? r := by
  cases r with
  | some w =>
    constructor
    · rintro ⟨C, h1, h2, h3⟩; exact ⟨C, h1, h2, (bare_erase_iff hc w (C \ K)).mp h3⟩
    · rintro ⟨C, h1, h2, h3⟩; exact ⟨C, h1, h2, (bare_erase_iff hc w (C \ K)).mpr h3⟩
  | none =>
    constructor
    · intro h C hC hsub w hw; exact h C hC hsub w ((bare_erase_iff hc w (C \ K)).mpr hw)
    · intro h C hC hsub w hw; exact h C hC hsub w ((bare_erase_iff hc w (C \ K)).mp hw)

/-! ## 3. The four-branch `splitConcrete` -/

/-- **`splitConcrete` with the Stage 5 branch, branch for branch and in the source's order.**
`none` is the Scala's `Set()` — the early return `concr.isEmpty || abstr.size < 2`; `some G'`
is `G` plus the emitted partitions.  The four branches are: syntactic reuse, keyed reuse,
CONCRETE-ROW reuse, mint.  The third and second emit the SAME conclusion,
`kSplitReuseResult`, which is why the Scala's two branches differ only in their `Inference`
tag (`SplitKeyed` / `SplitRow`). -/
def scalaRowSplit (G : System) (c : Constraint) (u : Var)
    (rhss resolvent concRow : Option Var) : Option System :=
  if c.conc = ∅ ∨ (vset c).card < 2 then none
  else
    match rhss with
    | some d => some (splitReuseResult G c d)
    | none =>
      match resolvent with
      | some w => some (kSplitReuseResult G c w)
      | none =>
        match concRow with
        | some w => some (kSplitReuseResult G c w)
        | none => some (splitResult G c u)

/-- **The only no-op is the early return.**  Once past `concr.isEmpty || abstr.size < 2` the
rule always emits, whichever of the four branches it takes. -/
theorem scalaRowSplit_eq_none_iff (G : System) (c : Constraint) (u : Var)
    (rhss resolvent concRow : Option Var) :
    scalaRowSplit G c u rhss resolvent concRow = none ↔ (c.conc = ∅ ∨ (vset c).card < 2) := by
  by_cases hg : c.conc = ∅ ∨ (vset c).card < 2
  · simp [scalaRowSplit, hg]
  · simp only [scalaRowSplit, if_neg hg]
    cases rhss with
    | some d => simp [hg]
    | none => cases resolvent with
      | some w => simp [hg]
      | none => cases concRow <;> simp [hg]

private theorem split_guard {c : Constraint} (hne : c.conc ≠ ∅)
    (hcard : 2 ≤ (vset c).card) : ¬ (c.conc = ∅ ∨ (vset c).card < 2) := by
  rintro (h | h)
  · exact hne h
  · omega

theorem scalaRowSplit_syntactic (G : System) (c : Constraint) (u d : Var)
    (resolvent concRow : Option Var) (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaRowSplit G c u (some d) resolvent concRow = some (splitReuseResult G c d) := by
  simp [scalaRowSplit, if_neg (split_guard hne hcard)]

theorem scalaRowSplit_keyed (G : System) (c : Constraint) (u w : Var) (concRow : Option Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaRowSplit G c u none (some w) concRow = some (kSplitReuseResult G c w) := by
  simp [scalaRowSplit, if_neg (split_guard hne hcard)]

/-- Branch 3, the NEW one: the concrete-row lookup hit. -/
theorem scalaRowSplit_row (G : System) (c : Constraint) (u w : Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaRowSplit G c u none none (some w) = some (kSplitReuseResult G c w) := by
  simp [scalaRowSplit, if_neg (split_guard hne hcard)]

theorem scalaRowSplit_mint (G : System) (c : Constraint) (u : Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaRowSplit G c u none none none = some (splitResult G c u) := by
  simp [scalaRowSplit, if_neg (split_guard hne hcard)]

/-- A nonempty variable set, from the `2 ≤ |vset c|` guard. -/
private theorem vset_ne_of_two_le {c : Constraint} (hcard : 2 ≤ (vset c).card) :
    vset c ≠ ∅ := by
  intro h
  rw [h] at hcard
  simp at hcard

/-! ### 3.1 Where the model is used

The reuse branches need no model.  The MINT branch does, because its guard `¬ Carried`
quantifies over every concrete row of `c.lhs` while the Scala's fold keeps one. -/

/-- **The premise and a concrete definition force `K ⊆ C`**, which is the side condition the
Scala asks explicitly and `K2RowApp` does not.  This is `key_subset_of_model` with an
arbitrary variable set in place of the lone witness's. -/
theorem conc_key_subset_of_model {rho : Assign} {G : System} {c : Constraint} {C : Row}
    (hm : SModels rho G) (hmem : c ∈ G) (hC : mk c.lhs ∅ C ∈ G) : c.conc ⊆ C := by
  have h := (hm _ hmem).conc_subset_lhs
  rwa [denotes_of_conc hC hm] at h

/-- **The Scala's `none` really is `¬ ConcCarried`, under a model.**  The two gaps —
one recorded row instead of an existential, and the explicit `K ⊆ C` — are closed by
`conc_unique_of_model` and `conc_key_subset_of_model` respectively.  This is the ONE place
the adequacy theorems need `SModels`. -/
theorem concRow_none_uncarried {rho : Assign} {G : System} {c : Constraint}
    {C? : Option Row} (hm : SModels rho G) (hmem : c ∈ G) (hvs : vset c ≠ ∅)
    (hmy : MyRowSpec (G.erase c) c.lhs C?)
    (hcr : ConcRowSpec (G.erase c) c.conc C? none) :
    ¬ ConcCarried G c.lhs c.conc := by
  intro hcc
  obtain ⟨C, z, hC, hz⟩ := (concCarried_iff G c.lhs c.conc).mp hcc
  have hCe : mk c.lhs ∅ C ∈ G.erase c := (bare_erase_iff hvs c.lhs C).mpr hC
  cases C? with
  | none => exact hmy C hCe
  | some C₀ =>
    have hC₀ : mk c.lhs ∅ C₀ ∈ G.erase c := hmy
    have hC₀G : mk c.lhs ∅ C₀ ∈ G := (bare_erase_iff hvs c.lhs C₀).mp hC₀
    have hEq : C = C₀ := conc_unique_of_model hm hC hC₀G
    subst hEq
    exact hcr C rfl (conc_key_subset_of_model hm hmem hC) z
      ((bare_erase_iff hvs z (C \ c.conc)).mpr hz)

/-- **ADEQUACY FOR THE SPLIT.  Every branch the Scala takes is a step of `K2SplitStep`.**
The four lookups are computed on `G.erase c` — the current system minus the dequeued premise,
which is what `incorporateAll` hands `learnPartitions` — and `u` is the id `fresh` would
draw.  The model is needed only at the mint branch (`concRow_none_uncarried`). -/
theorem scalaRowSplit_step {G : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (G.erase c) c.lhs C?)
    (hcr : ConcRowSpec (G.erase c) c.conc C? concRow)
    (h : scalaRowSplit G c u rhss resolvent concRow = some G') : K2SplitStep G G' := by
  by_cases hg : c.conc = ∅ ∨ (vset c).card < 2
  · rw [scalaRowSplit.eq_def, if_pos hg] at h
    exact absurd h (by simp)
  obtain ⟨hne, hlt⟩ := not_or.mp hg
  have hcard : 2 ≤ (vset c).card := Nat.not_lt.mp hlt
  have hvs : vset c ≠ ∅ := vset_ne_of_two_le hcard
  cases rhss with
  | some d =>
    rw [scalaRowSplit_syntactic G c u d resolvent concRow hne hcard, Option.some.injEq] at h
    subst h
    have hd : Names (G.erase c) d (vset c) := hr
    exact K2SplitStep.syn ⟨hmem, hne, hcard, (names_erase_iff hne d (vset c)).mp hd⟩
  | none =>
    have hunnamed : ¬ Named G (vset c) := by
      have : ¬ Named (G.erase c) (vset c) := hr
      exact fun hn => this ((named_erase_iff hne (vset c)).mpr hn)
    cases resolvent with
    | some w =>
      rw [scalaRowSplit_keyed G c u w concRow hne hcard, Option.some.injEq] at h
      subst h
      have hw : mk c.lhs {w} c.conc ∈ G.erase c := hres
      exact K2SplitStep.key ⟨hmem, hne, hcard, hunnamed, (Finset.mem_erase.mp hw).2⟩
    | none =>
      have hnr : ¬ Resolved G c.lhs c.conc := by
        have : ¬ Resolved (G.erase c) c.lhs c.conc := hres
        exact (ksplit_guard_erase_iff hcard).mp this
      cases concRow with
      | some w =>
        rw [scalaRowSplit_row G c u w hne hcard, Option.some.injEq] at h
        subst h
        obtain ⟨C, hC?, hsub, hcarr⟩ := hcr
        subst hC?
        have hlhs : mk c.lhs ∅ C ∈ G := (bare_erase_iff hvs c.lhs C).mp hmy
        exact K2SplitStep.row ⟨hmem, hne, hcard, hunnamed, hlhs,
          (bare_erase_iff hvs w (C \ c.conc)).mp hcarr⟩
      | none =>
        rw [scalaRowSplit_mint G c u hne hcard, Option.some.injEq] at h
        subst h
        refine K2SplitStep.mint ⟨hmem, hne, hcard, hunnamed, ?_, hfresh⟩
        rintro (hr' | hcc)
        · exact hnr hr'
        · exact concRow_none_uncarried hm hmem hvs hmy hcr hcc

/-- ...hence a step of the additive calculus `K2DefaultStep` (guarded `resolution` as
shipped), which is the relation `MintsBoundedOnSatKeyed2` is about. -/
theorem scalaRowSplit_defaultStep {G : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (G.erase c) c.lhs C?)
    (hcr : ConcRowSpec (G.erase c) c.conc C? concRow)
    (h : scalaRowSplit G c u rhss resolvent concRow = some G') : K2DefaultStep G G' :=
  K2DefaultStep.split (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr h)

/-- ...and of the fully rekeyed `K2StarStep`, the relation `mintsBoundedOnSatKeyed2Star` is
about. -/
theorem scalaRowSplit_starStep {G : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (G.erase c) c.lhs C?)
    (hcr : ConcRowSpec (G.erase c) c.conc C? concRow)
    (h : scalaRowSplit G c u rhss resolvent concRow = some G') : K2StarStep G G' :=
  K2StarStep.split (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr h)

/-- The rule only ever ADDS constraints... -/
theorem scalaRowSplit_subset {G : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (G.erase c) c.lhs C?)
    (hcr : ConcRowSpec (G.erase c) c.conc C? concRow)
    (h : scalaRowSplit G c u rhss resolvent concRow = some G') : G ⊆ G' :=
  (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr h).subset

/-- ...and, on a modelled system, keeps the model, moving it only at a minted name. -/
theorem scalaRowSplit_extend {G : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (hr : RhssSpec (G.erase c) (vset c) rhss)
    (hres : ResolventSpec (G.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (G.erase c) c.lhs C?)
    (hcr : ConcRowSpec (G.erase c) c.conc C? concRow)
    (h : scalaRowSplit G c u rhss resolvent concRow = some G') :
    ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v :=
  K2SplitStep.extend hm (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr h)

/-! ## 4. The three-branch `resolution`

`def resolution` is reached with the dequeued premise `c₁ = v <- (x, (|C|))` and a partition
`c₂ = v <- (y, (|D|))` already in `proc`; its guard is `tops = C \ D ≠ ∅` and
`bots = D \ C ≠ ∅`, which is `ResGuard.ResPair`.  The reuse branches emit
`x <- (w, D \ C)`, `y <- (w, C \ D)` = `resReuseResult`; the mint additionally emits
`v <- (z, C ∪ D)`.  `fresh` is drawn before the match in the Scala, so `z` exists in every
branch and the id sequence does not move — modelled here by taking `z` as a parameter that
only the mint branch uses. -/

def scalaRowRes (G : System) (v x y : Var) (C D : Row) (z : Var)
    (resolvent concRow : Option Var) : Option System :=
  if C \ D = ∅ ∨ D \ C = ∅ then none
  else
    match resolvent with
    | some w => some (resReuseResult G x y C D w)
    | none =>
      match concRow with
      | some w => some (resReuseResult G x y C D w)
      | none => some (resResult G v x y C D z)

/-- **The only no-op is the `tops`/`bots` early return** (the `Set()` the source returns
with the comment "Such cases are handled by cancellation"). -/
theorem scalaRowRes_eq_none_iff (G : System) (v x y : Var) (C D : Row) (z : Var)
    (resolvent concRow : Option Var) :
    scalaRowRes G v x y C D z resolvent concRow = none ↔ (C \ D = ∅ ∨ D \ C = ∅) := by
  by_cases hg : C \ D = ∅ ∨ D \ C = ∅
  · simp only [scalaRowRes, if_pos hg]
    exact iff_of_true trivial hg
  · simp only [scalaRowRes, if_neg hg]
    refine ⟨fun h => absurd h ?_, fun h => absurd h hg⟩
    cases resolvent with
    | some w => simp
    | none => cases concRow with
      | some w => simp
      | none => simp

private theorem res_guard {C D : Row} (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    ¬ (C \ D = ∅ ∨ D \ C = ∅) := by
  rintro (h | h)
  · exact htops h
  · exact hbots h

theorem scalaRowRes_reuse (G : System) (v x y : Var) (C D : Row) (z w : Var)
    (concRow : Option Var) (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaRowRes G v x y C D z (some w) concRow = some (resReuseResult G x y C D w) := by
  simp only [scalaRowRes, if_neg (res_guard htops hbots)]

/-- Branch 2, the NEW one. -/
theorem scalaRowRes_row (G : System) (v x y : Var) (C D : Row) (z w : Var)
    (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaRowRes G v x y C D z none (some w) = some (resReuseResult G x y C D w) := by
  simp only [scalaRowRes, if_neg (res_guard htops hbots)]

theorem scalaRowRes_mint (G : System) (v x y : Var) (C D : Row) (z : Var)
    (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaRowRes G v x y C D z none none = some (resResult G v x y C D z) := by
  simp only [scalaRowRes, if_neg (res_guard htops hbots)]

/-- **The dequeued premise cannot witness the RESOLVENT key**, for a reason
`KeyedSplitScala.resolved_erase_iff` cannot use: `vset (mk v {x} C)` has card 1, not 2, so
the argument is about the ROW instead — a witness carries `C ∪ D` and the premise carries
`C`, and `D \ C ≠ ∅` keeps them apart. -/
theorem resolved_erase_iff_row {G : System} {v x : Var} {C K : Row} (hne : K ≠ C) :
    Resolved (G.erase (mk v {x} C)) v K ↔ Resolved G v K := by
  constructor
  · exact Resolved.mono fun _ hd => (Finset.mem_erase.mp hd).2
  · intro h
    obtain ⟨w, hw⟩ := (resolved_iff G v K).mp h
    refine resolved_of_mem (Finset.mem_erase.mpr ⟨?_, hw⟩)
    intro hEq
    apply hne
    have : (mk v {w} K).conc = (mk v {x} C).conc := by rw [hEq]
    simpa using this

/-- The resolvent row is not either premise's row. -/
private theorem union_ne_left {C D : Row} (hbots : D \ C ≠ ∅) : C ∪ D ≠ C := by
  intro h
  apply hbots
  have hDC : D ⊆ C := by
    intro l hl
    have : l ∈ C ∪ D := Finset.mem_union_right _ hl
    rwa [h] at this
  exact Finset.sdiff_eq_empty_iff_subset.mpr hDC

/-- **ADEQUACY FOR RESOLUTION.  Every branch the Scala takes is a step of `K2ResStep`.**
The lookups are computed on `G.erase c₁`, `c₁ = mk v {x} C` being the dequeued premise; the
model is needed only at the mint branch, and for the same reason as in the split. -/
theorem scalaRowRes_step {G : System} {v x y : Var} {C D : Row} {z : Var}
    {resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hp : ResPair G v x y C D) (hfresh : z ∉ allVars G)
    (hres : ResolventSpec (G.erase (mk v {x} C)) v (C ∪ D) resolvent)
    (hmy : MyRowSpec (G.erase (mk v {x} C)) v C?)
    (hcr : ConcRowSpec (G.erase (mk v {x} C)) (C ∪ D) C? concRow)
    (h : scalaRowRes G v x y C D z resolvent concRow = some G') : K2ResStep G G' := by
  have hvs : vset (mk v {x} C) ≠ ∅ := by simp
  have hUC : C ∪ D ≠ C := union_ne_left hp.bots
  cases resolvent with
  | some w =>
    rw [scalaRowRes_reuse G v x y C D z w concRow hp.tops hp.bots, Option.some.injEq] at h
    subst h
    have hw : mk v {w} (C ∪ D) ∈ G.erase (mk v {x} C) := hres
    exact K2ResStep.reuse hp (Finset.mem_erase.mp hw).2
  | none =>
    have hnr : ¬ Resolved G v (C ∪ D) := by
      have hh : ¬ Resolved (G.erase (mk v {x} C)) v (C ∪ D) := hres
      exact fun hr => hh ((resolved_erase_iff_row hUC).mpr hr)
    cases concRow with
    | some w =>
      rw [scalaRowRes_row G v x y C D z w hp.tops hp.bots, Option.some.injEq] at h
      subst h
      obtain ⟨F, hC?, hsub, hcarr⟩ := hcr
      subst hC?
      exact K2ResStep.row hp ((bare_erase_iff hvs v F).mp hmy)
        ((bare_erase_iff hvs w (F \ (C ∪ D))).mp hcarr)
    | none =>
      rw [scalaRowRes_mint G v x y C D z hp.tops hp.bots, Option.some.injEq] at h
      subst h
      refine K2ResStep.mint hp ?_ hfresh
      rintro (hr' | hcc)
      · exact hnr hr'
      · obtain ⟨F, w, hF, hw⟩ := (concCarried_iff G v (C ∪ D)).mp hcc
        have hFe : mk v ∅ F ∈ G.erase (mk v {x} C) := (bare_erase_iff hvs v F).mpr hF
        cases C? with
        | none => exact hmy F hFe
        | some F₀ =>
          have hF₀ : mk v ∅ F₀ ∈ G.erase (mk v {x} C) := hmy
          have hF₀G : mk v ∅ F₀ ∈ G := (bare_erase_iff hvs v F₀).mp hF₀
          have hEq : F = F₀ := conc_unique_of_model hm hF hF₀G
          subst hEq
          have hCF : C ⊆ F := by
            have h1 := (hm _ hp.mem₁).conc_subset_lhs
            rw [conc_mk, lhs_mk, denotes_of_conc hF hm] at h1
            exact h1
          have hDF : D ⊆ F := by
            have h2 := (hm _ hp.mem₂).conc_subset_lhs
            rw [conc_mk, lhs_mk, denotes_of_conc hF hm] at h2
            exact h2
          exact hcr F rfl (Finset.union_subset hCF hDF) w
            ((bare_erase_iff hvs w (F \ (C ∪ D))).mpr hw)

/-- ...hence a step of the fully rekeyed additive calculus, the one
`mintsBoundedOnSatKeyed2Star` bounds. -/
theorem scalaRowRes_starStep {G : System} {v x y : Var} {C D : Row} {z : Var}
    {resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hp : ResPair G v x y C D) (hfresh : z ∉ allVars G)
    (hres : ResolventSpec (G.erase (mk v {x} C)) v (C ∪ D) resolvent)
    (hmy : MyRowSpec (G.erase (mk v {x} C)) v C?)
    (hcr : ConcRowSpec (G.erase (mk v {x} C)) (C ∪ D) C? concRow)
    (h : scalaRowRes G v x y C D z resolvent concRow = some G') : K2StarStep G G' :=
  K2StarStep.res (scalaRowRes_step hm hp hfresh hres hmy hcr h)

theorem scalaRowRes_subset {G : System} {v x y : Var} {C D : Row} {z : Var}
    {resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hp : ResPair G v x y C D) (hfresh : z ∉ allVars G)
    (hres : ResolventSpec (G.erase (mk v {x} C)) v (C ∪ D) resolvent)
    (hmy : MyRowSpec (G.erase (mk v {x} C)) v C?)
    (hcr : ConcRowSpec (G.erase (mk v {x} C)) (C ∪ D) C? concRow)
    (h : scalaRowRes G v x y C D z resolvent concRow = some G') : G ⊆ G' :=
  (scalaRowRes_step hm hp hfresh hres hmy hcr h).subset

theorem scalaRowRes_extend {G : System} {v x y : Var} {C D : Row} {z : Var}
    {resolvent concRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho G) (hp : ResPair G v x y C D) (hfresh : z ∉ allVars G)
    (hres : ResolventSpec (G.erase (mk v {x} C)) v (C ∪ D) resolvent)
    (hmy : MyRowSpec (G.erase (mk v {x} C)) v C?)
    (hcr : ConcRowSpec (G.erase (mk v {x} C)) (C ∪ D) C? concRow)
    (h : scalaRowRes G v x y C D z resolvent concRow = some G') :
    ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v :=
  K2ResStep.extend hm (scalaRowRes_step hm hp hfresh hres hmy hcr h)

/-! ## 5. The closed lookups, and the two rules together -/

/-- `splitConcrete` with all four lookups resolved. -/
noncomputable def scalaRowSplitOf (G : System) (c : Constraint) (u : Var) : Option System :=
  scalaRowSplit G c u (rhssLookup (G.erase c) (vset c))
    (resolventLookup (G.erase c) c.lhs c.conc)
    (concRowLookup (G.erase c) c.conc (myRowLookup (G.erase c) c.lhs))

/-- **Adequacy for the closed split function.** -/
theorem scalaRowSplitOf_step {G : System} {c : Constraint} {u : Var} {G' : System}
    {rho : Assign} (hm : SModels rho G) (hmem : c ∈ G) (hfresh : u ∉ allVars G)
    (h : scalaRowSplitOf G c u = some G') : K2SplitStep G G' :=
  scalaRowSplit_step hm hmem hfresh (rhssLookup_spec _ _) (resolventLookup_spec _ _ _)
    (myRowLookup_spec _ _) (concRowLookup_spec _ _ _) h

/-- `resolution` with all three lookups resolved. -/
noncomputable def scalaRowResOf (G : System) (v x y : Var) (C D : Row) (z : Var) :
    Option System :=
  scalaRowRes G v x y C D z (resolventLookup (G.erase (mk v {x} C)) v (C ∪ D))
    (concRowLookup (G.erase (mk v {x} C)) (C ∪ D)
      (myRowLookup (G.erase (mk v {x} C)) v))

/-- **Adequacy for the closed resolution function.** -/
theorem scalaRowResOf_step {G : System} {v x y : Var} {C D : Row} {z : Var} {G' : System}
    {rho : Assign} (hm : SModels rho G) (hp : ResPair G v x y C D) (hfresh : z ∉ allVars G)
    (h : scalaRowResOf G v x y C D z = some G') : K2ResStep G G' :=
  scalaRowRes_step hm hp hfresh (resolventLookup_spec _ _ _) (myRowLookup_spec _ _)
    (concRowLookup_spec _ _ _) h

/-- **The two flags together.**  Every step either extended rule takes from a modelled system
is a step of `K2StarStep` — the relation whose loop extension `mintsBoundedOnSatKeyed2Star`
proves mints boundedly on every satisfiable input in every run order.  That is the whole
claim Stage 5 makes for `-Dermine.splitRow` + `-Dermine.resRow` at the level of the rules;
the loop's single pass and `common` remain unmodelled. -/
theorem scalaRow_starStep {G : System} {G' : System} {rho : Assign} (hm : SModels rho G) :
    (∀ (c : Constraint) (u : Var), c ∈ G → u ∉ allVars G →
        scalaRowSplitOf G c u = some G' → K2StarStep G G') ∧
    (∀ (v x y : Var) (C D : Row) (z : Var), ResPair G v x y C D → z ∉ allVars G →
        scalaRowResOf G v x y C D z = some G' → K2StarStep G G') :=
  ⟨fun _ _ hmem hfresh h => K2StarStep.split (scalaRowSplitOf_step hm hmem hfresh h),
   fun _ _ _ _ _ _ hp hfresh h => K2StarStep.res (scalaRowResOf_step hm hp hfresh h)⟩

end KeyedRow
end Rowpartition
