/-
# L5 round 3 (R3.1): `Carried`-preservation, and exactly where the loop breaks it

`L5-REVIEW.md`'s round-2 finding **R-4** is the obstacle this module addresses.  `LoopStrict`'s
`requeue` constructor is licensed SEMANTICALLY (`Conserv` and `NoLoss`, i.e. model-set equality,
plus a vocabulary bound) while `KeyedRow.Carried` -- the guard the mint budget `hmeas` is built
on -- is SYNTACTIC.  So a legal `requeue` step can destroy a `Carried` witness, `uncarried`
strictly increases and `hmeas` goes UP; ingredient (B) of `L5-TERMINATION.md` §C3.1 ("every
non-minting step preserves `Carried` and adds no variable") is unavailable from the relation.

What this module does, in order:

1. names the preservation property (`CarrPres`, and the relativised `CarrPresOn` that
   `KeyedEmpty.hmeas_le_of_carried_on` actually consumes);
2. proves `Carried`-preservation for every `LoopStrict` constructor that CAN have it -- the
   nine additive rule constructors, `emptyRemove` (`KeyedEmpty.carried_makeEmptyE`),
   `concRemove` (`KeyedRow.carried_concretizeSrs`), and `instRemove` AT EVERY VARIABLE BUT THE
   ELIMINATED ONE (`carried_substOut_of_ne`, new).  That is `carried_step`;
3. shows that the three that cannot have it really cannot: `substOut_breaks_carried` at the
   eliminated variable (which is `L5-TERMINATION.md` §C3.1's table row 1 as a theorem rather
   than as prose) and `carried_not_monotone_under_deletion` for `drop`;
4. gives the relation `LoopStrictK` -- `LoopStrict` with the syntactic `CarrPres` conjunct
   supplied at exactly the constructors that need it -- for which the reviewer's
   `requeue_breaks_carried` is unprovable, and proves along it that the potential
   `(allVars G).card + hmeas L rho G` never grows, hence the **vocabulary SNAPSHOT bound**
   `LoopStrictKRun.allVars_card_le`: on satisfiable input no run of carried-preserving steps
   and KEYED mints ever HOLDS more than `|allVars G₀| + hmeas L rho G₀` variables at once.
   It does NOT bound the number of counted steps -- see the note on that theorem.

So ingredient (B) is available exactly for `LoopStrictK`, and the loop-level question becomes
which of the loop's steps are `LoopStrictK` steps.  `carried_iff_of_link_only` answers it for
`common`/`unify`, and the answer is NEGATIVE and unconditional over `sys`: after an
elimination the only constraint about the eliminated variable is the retained link, which
carries the key `∅` and no other.  That is why `L5-TERMINATION.md` §C3.1 puts the measure over
`qsys` and not over `sys`.
-/
import Rowpartition.Loop.StrictStep

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty
open Rowpartition.NameLoss (mk_eq_iff)

/-! ## 1. The preservation property -/

/-- **`G'` keeps every key `G` carries.**  This is ingredient (B) of `L5-TERMINATION.md`
§C3.1, as a relation on systems. -/
def CarrPres (G G' : System) : Prop := ∀ w K, Carried G w K → Carried G' w K

/-- The relativised form: only the variables the successor still HAS need keep their keys.
This is what `KeyedEmpty.hmeas_le_of_carried_on` consumes, and it is strictly weaker -- a
variable that leaves the vocabulary entirely costs nothing. -/
def CarrPresOn (G G' : System) : Prop :=
  ∀ w ∈ allVars G', ∀ K, Carried G w K → Carried G' w K

/-- Preservation at every variable BUT `v`.  This is the exact strength of `substOut v u`
(`carried_substOut_of_ne` and `substOut_breaks_carried` together). -/
def CarrPresOff (v : Var) (G G' : System) : Prop :=
  ∀ w, w ≠ v → ∀ K, Carried G w K → Carried G' w K

theorem CarrPres.of_subset {G G' : System} (h : G ⊆ G') : CarrPres G G' :=
  fun _ _ hc => hc.mono h

theorem CarrPres.refl (G : System) : CarrPres G G := CarrPres.of_subset (Finset.Subset.refl G)

theorem CarrPres.trans {G G' G'' : System} (h1 : CarrPres G G') (h2 : CarrPres G' G'') :
    CarrPres G G'' := fun w K hc => h2 w K (h1 w K hc)

theorem CarrPres.on {G G' : System} (h : CarrPres G G') : CarrPresOn G G' :=
  fun w _ K hc => h w K hc

theorem CarrPresOn.refl (G : System) : CarrPresOn G G := (CarrPres.refl G).on

theorem CarrPresOff.on {v : Var} {G G' : System} (h : CarrPresOff v G G')
    (hv : v ∉ allVars G') : CarrPresOn G G' :=
  fun w hw K hc => h w (fun hh => hv (hh ▸ hw)) K hc

/-- **What the preservation property buys.**  `KeyedEmpty.hmeas_le_of_carried_on`, in the
vocabulary of this module. -/
theorem CarrPresOn.hmeas_le {L : Finset Label} {G G' : System} (rho : Assign)
    (hAV : allVars G' ⊆ allVars G) (h : CarrPresOn G G') :
    hmeas L rho G' ≤ hmeas L rho G :=
  hmeas_le_of_carried_on rho hAV h

/-! ## 2. `substOut`, the one operator the library had no `Carried` lemma for

`KeyedEmpty.carried_makeEmptyE` and `KeyedRow.carried_concretizeSrs` are the library's;
`instantiate`'s removal is the operator `Loop.substOut` introduced in round 2, and this is its
analogue.  It is the FULL truth about it: preservation holds at every variable but the
eliminated one, and fails there. -/

/-- `substOut` keeps a constraint that mentions `v` nowhere. -/
theorem mem_substOut_of_notInvolves {v u : Var} {G : System} {c : Constraint} (hc : c ∈ G)
    (hl : c.lhs ≠ v) (hv : v ∉ vset c) : c ∈ substOut v u G :=
  mem_substOut.mpr (Or.inr (Or.inl ⟨hc, hl, hv⟩))

/-- The image of a `mk`-shaped constraint under the substitution, computed. -/
theorem substC_mk (v u : Var) (a : Var) (S : Finset Var) (K : Row) :
    substC v u (mk a S K) =
      mk (if a == v then u else a) (S.image (fun w => if w == v then u else w)) K := by
  simp only [substC, lhs_mk, vset_mk, conc_mk]
  rfl

/-- **`substOut` preserves `Carried` at every variable but the one it eliminates.**  A lone
witness `w <- (v, K)` becomes `w <- (u, K)`; a concrete definition `w <- ((|C|))` mentions `v`
nowhere and is kept verbatim; a complement carrier `v <- ((|C \ K|))` becomes
`u <- ((|C \ K|))`.  In every case the shape of the witness survives. -/
theorem carried_substOut_of_ne {G : System} {v u w : Var} {K : Row} (hw : w ≠ v)
    (h : Carried G w K) : Carried (substOut v u G) w K := by
  rcases h with h | h
  · obtain ⟨z, hz⟩ := (resolved_iff G w K).mp h
    by_cases hzv : z = v
    · subst hzv
      have himg : substC z u (mk w {z} K) = mk w {u} K := by
        rw [substC_mk, if_neg (by simpa using hw), Finset.image_singleton, if_pos (by simp)]
      refine Carried.of_resolved (resolved_of_mem (G := substOut z u G) (z := u) ?_)
      exact mem_substOut.mpr (Or.inr (Or.inr ⟨mk w {z} K, hz,
        Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self z), himg.symm⟩))
    · refine Carried.of_resolved (resolved_of_mem (z := z) (mem_substOut_of_notInvolves hz ?_ ?_))
      · rw [lhs_mk]; exact hw
      · rw [vset_mk]; exact fun hh => hzv (Finset.mem_singleton.mp hh).symm
  · obtain ⟨C, z, hC, hz⟩ := (concCarried_iff G w K).mp h
    have hCmem : mk w ∅ C ∈ substOut v u G :=
      mem_substOut_of_notInvolves hC (by rw [lhs_mk]; exact hw)
        (by rw [vset_mk]; exact Finset.notMem_empty v)
    by_cases hzv : z = v
    · subst hzv
      have himg : substC z u (mk z ∅ (C \ K)) = mk u ∅ (C \ K) := by
        rw [substC_mk, if_pos (by simp), Finset.image_empty]
      exact Carried.of_conc hCmem (z := u) (mem_substOut.mpr (Or.inr (Or.inr
        ⟨mk z ∅ (C \ K), hz, Or.inl (by rw [lhs_mk]), himg.symm⟩)))
    · exact Carried.of_conc hCmem (mem_substOut_of_notInvolves hz (by rw [lhs_mk]; exact hzv)
        (by rw [vset_mk]; exact Finset.notMem_empty v))

theorem carrPresOff_substOut (v u : Var) (G : System) : CarrPresOff v G (substOut v u G) :=
  fun _ hw _ hc => carried_substOut_of_ne hw hc

/-! ### 2.1 ... and it FAILS at the eliminated variable

`substOut` retains the link `v <- (u)`, so `v` stays in `allVars`, while every carrier for `v`
has been rewritten to `u`.  This is `L5-TERMINATION.md` §C3.1's table row 1 -- "(B) fails for
`sys s` at `instantiate`" -- as a theorem rather than as prose, and it is the reason the
loop's `common` and `unify` branches cannot be given a `Carried`-preserving licence over
`sys`. -/

/-- **After an elimination, the eliminated variable carries only the empty key.**  If the only
constraint of `G` with left-hand side `v` is the link `v <- (u)`, then `Carried G v K` forces
`K = ∅`: `Resolved` must use that very link, whose concrete part is empty, and `ConcCarried`
would need a concrete definition of `v`, which the link is not. -/
theorem carried_iff_of_link_only {G : System} {v u : Var} {K : Row}
    (h : ∀ c ∈ G, c.lhs = v → c = mk v {u} (∅ : Row)) (hc : Carried G v K) : K = ∅ := by
  rcases hc with hc | hc
  · obtain ⟨z, hz⟩ := (resolved_iff G v K).mp hc
    have := h _ hz (by rw [lhs_mk])
    exact (mk_eq_iff.mp this).2.2
  · obtain ⟨C, z, hC, -⟩ := (concCarried_iff G v K).mp hc
    have := h _ hC (by rw [lhs_mk])
    exact absurd (mk_eq_iff.mp this).2.1.symm (Finset.singleton_ne_empty u)

/-- The witness system: `v0 <- (v1)`, `v0 <- ((|l5|))`, `v2 <- ()`. -/
def GA : System := {mk 0 {1} (∅ : Row), mk 0 ∅ ({5} : Row), mk 2 ∅ (∅ : Row)}

theorem GA_link : mk 0 {1} (∅ : Row) ∈ GA := by simp [GA]

/-- `v0` carries the key `{l5}`: it has the concrete definition `v0 <- ((|l5|))` and `v2`
denotes `{l5} \ {l5} = ∅`. -/
theorem GA_carried : Carried GA 0 ({5} : Row) := by
  refine Carried.of_conc (z := 2) (C := ({5} : Row)) ?_ ?_
  · simp [GA]
  · rw [Finset.sdiff_self]; simp [GA]

/-- Every constraint of `substOut 0 1 GA` with left-hand side `0` is the retained link. -/
theorem substOut_GA_lhs_zero :
    ∀ c ∈ substOut 0 1 GA, c.lhs = 0 → c = mk 0 {1} (∅ : Row) := by
  intro c hc hl
  rcases mem_substOut.mp hc with rfl | ⟨-, hne, -⟩ | ⟨d, hd, -, rfl⟩
  · rfl
  · exact absurd hl hne
  · rw [substC] at hl ⊢
    simp only [lhs_mk] at hl
    by_cases hdv : d.lhs = 0
    · rw [if_pos (by simpa using hdv)] at hl; exact absurd hl (by decide)
    · rw [if_neg (by simpa using hdv)] at hl; exact absurd hl hdv

/-- **`substOut` does NOT preserve `Carried` at the variable it eliminates.**  `v0` carries
the key `(v0, {l5})` through its own concrete definition and `v2 <- ()`; after
`instantiate(v0 := v1)` the definition reads `v1 <- ((|l5|))` and the only constraint left
about `v0` is the retained link, which carries the key `∅` and no other. -/
theorem substOut_breaks_carried :
    ∃ (G : System) (v u : Var) (K : Row), mk v {u} (∅ : Row) ∈ G ∧
      Carried G v K ∧ ¬ Carried (substOut v u G) v K := by
  refine ⟨GA, 0, 1, {5}, GA_link, GA_carried, fun hc => ?_⟩
  have := carried_iff_of_link_only substOut_GA_lhs_zero hc
  exact absurd this (by decide)

/-! ## 3. `drop` breaks it too

`L5-REVIEW.md` R-4 exhibits a `requeue` step that destroys a `ConcCarried` witness by
re-expressing `v1 <- ((|l0,l1|))` as `v1 <- (v0, v2)` -- the same system logically, over the
same three variables.  `drop` breaks it for a simpler reason, recorded here so that the two
constructors that need the licence are both documented in the tree: deleting a constraint
leaves `Carried` unprotected, because `Carried` is monotone under ADDITION only. -/

/-- The reviewer's `GG`: `v1 <- ((|l0,l1|))`, `v0 <- ((|l0|))`, `v2 <- ((|l1|))`. -/
def GB : System := {mk 1 ∅ ({0, 1} : Row), mk 0 ∅ ({0} : Row), mk 2 ∅ ({1} : Row)}

theorem GB_carried : Carried GB 1 ({0} : Row) := by
  refine Carried.of_conc (z := 2) (C := ({0, 1} : Row)) ?_ ?_
  · simp [GB]
  · have h : ({0, 1} : Row) \ ({0} : Row) = ({1} : Row) := by decide
    rw [h]; simp [GB]

/-- **`Carried` is not monotone under deletion**, so `drop` needs the licence too. -/
theorem carried_not_monotone_under_deletion :
    ∃ (G G' : System) (w : Var) (K : Row), G' ⊆ G ∧ Carried G w K ∧ ¬ Carried G' w K := by
  refine ⟨GB, {mk 0 ∅ ({0} : Row), mk 2 ∅ ({1} : Row)}, 1, {0}, ?_, GB_carried, ?_⟩
  · intro c hc
    simp only [Finset.mem_insert, Finset.mem_singleton] at hc
    simp only [GB, Finset.mem_insert, Finset.mem_singleton]
    rcases hc with rfl | rfl
    · exact Or.inr (Or.inl rfl)
    · exact Or.inr (Or.inr rfl)
  · rintro (h | h)
    · obtain ⟨z, hz⟩ := (resolved_iff _ 1 ({0} : Row)).mp h
      simp only [Finset.mem_insert, Finset.mem_singleton, mk_eq_iff] at hz
      rcases hz with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ <;> exact absurd h1 (by decide)
    · obtain ⟨C, z, hC, -⟩ := (concCarried_iff _ 1 ({0} : Row)).mp h
      simp only [Finset.mem_insert, Finset.mem_singleton, mk_eq_iff] at hC
      rcases hC with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ <;> exact absurd h1 (by decide)

/-! ## 4. `carried_step`: the constructors that need no licence

This is ingredient (B) of `L5-TERMINATION.md` §C3.1, for every `LoopStrict` constructor that
can have it.  The nine rule constructors are additive; `emptyRemove` is
`KeyedEmpty.carried_makeEmptyE`; `concRemove` is `KeyedRow.carried_concretizeSrs`; and
`instRemove` is `carried_substOut_of_ne` above, which is preservation OFF the eliminated
variable and -- by `substOut_breaks_carried` -- no more. -/

/-- **`carried_step`.**  Every `LoopStrict` step that is not a mint preserves `Carried`, given
the licence at the three constructors that need one: `drop`, `requeue` (whose targets are not
functions of `G`) and `instRemove` (whose target retains the eliminated name).

The fourteen cases divide as follows, and the count matters (`L5-REVIEW.md` round 3, F-1):

* **seven are proved outright** -- five by ADDITIVITY (`nongen`, `renameLhs`, `linkSymm`,
  `emptyProp`, `dedup`, all via `CarrPres.of_subset`) and two by the library's own `Carried`
  lemmas (`emptyRemove` by `KeyedEmpty.carried_makeEmptyE`, `concRemove` by
  `KeyedRow.carried_concretizeSrs`).  Those two are the only reason the theorem needs a MODEL
  and not merely `SSat`: both operators lose a fact on unsatisfiable input;
* **four are VACUOUS** under `hmint` -- `split`, `res`, `splitFree`, `kres` are exactly
  `IsMint`, so those cases close by `absurd`, not by an argument about `Carried`;
* **three are passed through** as the hypotheses `hdrop`, `hinst`, `hreq`.  The theorem proves
  nothing at them; it isolates them, and `substOut_breaks_carried`,
  `carried_not_monotone_under_deletion` and `L5-REVIEW.md`'s `requeue_breaks_carried` show
  that none of the three can be discharged. -/
theorem LoopStrict.carried_step {G G' : System} {rho : Assign} (hm : SModels rho G)
    (h : LoopStrict G G') (hmint : ¬ IsMint G G')
    (hdrop : G' ⊆ G → CarrPres G G')
    (hinst : (∃ v u : Var, G' = substOut v u G) → CarrPres G G')
    (hreq : allVars G' ⊆ allVars G → Conserv G G' → NoLoss G G' → CarrPres G G') :
    CarrPres G G' := by
  cases h with
  | nongen hh => exact CarrPres.of_subset hh.subset
  | split hh => exact absurd (Or.inl hh) hmint
  | res hh => exact absurd (Or.inr (Or.inl hh)) hmint
  | splitFree hh => exact absurd (Or.inr (Or.inr (Or.inl hh))) hmint
  | kres hh => exact absurd (Or.inr (Or.inr (Or.inr hh))) hmint
  | renameLhs _ _ => exact CarrPres.of_subset (Finset.subset_insert _ _)
  | linkSymm _ => exact CarrPres.of_subset (Finset.subset_insert _ _)
  | emptyProp _ _ _ => exact CarrPres.of_subset (Finset.subset_insert _ _)
  | dedup _ _ _ _ _ => exact CarrPres.of_subset (Finset.subset_insert _ _)
  | drop hsub _ => exact hdrop hsub
  | instRemove _ _ => exact hinst ⟨_, _, rfl⟩
  | emptyRemove hv _ => exact fun _ _ hc => carried_makeEmptyE hm hv hc
  | concRemove hv _ => exact fun _ _ hc => carried_concretizeSrs hm hv hc
  | requeue hvoc hcons hnl => exact hreq hvoc hcons hnl

/-- **A non-minting `LoopStrict` step keeps the model it started with.**  `LoopStrict.sat`
only says satisfiability survives, extending the assignment at a mint; off the minting
constructors the SAME assignment works, which is what a measure argument needs. -/
theorem LoopStrict.models_of_notMint {G G' : System} {rho : Assign} (h : LoopStrict G G')
    (hmint : ¬ IsMint G G') (hmod : SModels rho G) : SModels rho G' := by
  cases h with
  | nongen hh => exact (hh.models_iff rho).mp hmod
  | split hh => exact absurd (Or.inl hh) hmint
  | res hh => exact absurd (Or.inr (Or.inl hh)) hmint
  | splitFree hh => exact absurd (Or.inr (Or.inr (Or.inl hh))) hmint
  | kres hh => exact absurd (Or.inr (Or.inr (Or.inr hh))) hmint
  | renameLhs h1 h2 =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact renameLhs_sat (hmod _ h1) (hmod _ h2)
    · exact hmod c hc'
  | linkSymm h1 =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact linkSymm_sat (hmod _ h1)
    · exact hmod c hc'
  | emptyProp h1 h2 hx =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact emptyProp_sat (hmod _ h1) (hmod _ h2) hx
    · exact hmod c hc'
  | dedup h1 h2 hv hx hx' =>
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact dedup_sat (hmod _ h1) (hmod _ h2) hv hx hx'
    · exact hmod c hc'
  | drop hsub _ => exact SModels.mono hsub hmod
  | instRemove hlink _ => exact substOut_sound hlink rho hmod
  | emptyRemove hv _ => exact makeEmptyE_sound hv hmod
  | concRemove hv _ => exact concretizeSrs_sound hv rho hmod
  | requeue _ hcons _ => exact hcons.models hmod

/-! ## 5. `LoopStrictK`: `LoopStrict` with the conjunct supplied, and the SNAPSHOT BOUND

`L5-REVIEW.md` R-4's acceptance is that `requeue_breaks_carried` become unprovable.  It cannot
become unprovable for `LoopStrict` ITSELF without weakening the three branch refinements that
are already proved -- `step_strict_common`, `step_strict_empty` and `step_strict_unify` all go
through `requeue`, and §2.1 shows two of them cannot be given the conjunct at all.  So the
conjunct is supplied here, in a relation that refines `LoopStrict`.

The mints are the KEYED ones (`KeyedRow.K2StarStep`, i.e. `NonGenStep`, `K2SplitStep` and
`K2ResStep`): these are the rules whose guard is `¬ Carried`, and they are what the shipped
flags `splitKey`/`splitRow`/`resGuard`/`resRow` select.  `Cut.ResStep` and `Cut.SplitStep`,
the unguarded mints `LoopStrict` also carries, spend no budget and are deliberately outside
the relation. -/

/-- The potential `KeyedRow`'s bound is stated with. -/
def Pot (L : Finset Label) (rho : Assign) (G : System) : ℕ :=
  (allVars G).card + hmeas L rho G

/-- **A run of carried-preserving `LoopStrict` steps and keyed mints, with the mints counted.**
A `keep` step is any `LoopStrict` step that does not mint, adds no variable and no label, and
keeps every carried key of every variable it still has. -/
inductive LoopStrictKRun (L : Finset Label) : ℕ → System → System → Prop
  | refl (G : System) : LoopStrictKRun L 0 G G
  | keep {n : ℕ} {G₀ G G' : System} :
      LoopStrictKRun L n G₀ G → LoopStrict G G' → ¬ IsMint G G' →
      allVars G' ⊆ allVars G → ConcSub L G' → CarrPresOn G G' →
      LoopStrictKRun L n G₀ G'
  | mint {n : ℕ} {G₀ G G' : System} :
      LoopStrictKRun L n G₀ G → K2StarStep G G' → LoopStrictKRun L (n + 1) G₀ G'

/-- Every keyed step is a `LoopStrict` step, so a `LoopStrictKRun` is a `LoopStrictRun`. -/
theorem k2StarStep_toStrict {G G' : System} (h : K2StarStep G G') : LoopStrict G G' := by
  cases h with
  | nongen hh => exact LoopStrict.nongen hh
  | split hh => exact LoopStrict.split hh
  | res hh => exact LoopStrict.kres hh

theorem LoopStrictKRun.toRun {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : LoopStrictKRun L n G₀ G) : LoopStrictRun G₀ G := by
  induction h with
  | refl => exact Relation.ReflTransGen.refl
  | keep _ hstep _ _ _ _ ih => exact ih.tail hstep
  | mint _ hstep ih => exact ih.tail (k2StarStep_toStrict hstep)

/-- **The invariant that drives the bound.**  Along such a run from a satisfiable input the
potential never grows -- the keyed mints by `KeyedRow.K2StarStep.measure_step`, and every
other step by `CarrPresOn.hmeas_le`, which is ingredient (B). -/
theorem LoopStrictKRun.invariant {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : LoopStrictKRun L n G₀ G) :
    ∀ rho₀ : Assign, SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧ ConcSub L G ∧ Pot L rho G ≤ Pot L rho₀ G₀ := by
  induction h with
  | refl G => intro rho₀ hm hcs; exact ⟨rho₀, hm, hcs, Nat.le_refl _⟩
  | @keep n G₀ G G' _ hstep hmint hvoc hcs' hcar ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, -, hb⟩ := ih rho₀ hm hcs
    refine ⟨rho, hstep.models_of_notMint hmint hmr, hcs', le_trans ?_ hb⟩
    have h1 : hmeas L rho G' ≤ hmeas L rho G := hcar.hmeas_le rho hvoc
    have h2 : (allVars G').card ≤ (allVars G).card := Finset.card_le_card hvoc
    simp only [Pot]
    omega
  | @mint n G₀ G G' _ hstep ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hcsr, hb⟩ := ih rho₀ hm hcs
    obtain ⟨rho', hm', -, hb'⟩ := hstep.measure_step hcsr hmr
    exact ⟨rho', hm', hstep.concSub hcsr, le_trans hb' hb⟩

/-- **THE VOCABULARY SNAPSHOT BOUND for the carried-preserving fragment.**  This is what
ingredient (B) is for: on satisfiable input, no run of `LoopStrict` steps that keep every
carried key, interleaved with the KEYED mints, ever HOLDS more than
`|allVars G₀| + hmeas L rho G₀` variables at once.

**It does NOT bound `n`, the number of counted steps** (`L5-REVIEW.md` round 3, F-2, which
exhibits a run reaching every `n` from a fixed satisfiable system).  Two reasons, both
deliberate features of this relation and both absent from the library's `K2StarLoopRun`:
`mint` carries no productivity side condition (the library's `tail` carries `G ≠ G'`, and
`K2StarStep` includes the NON-generative `NonGenStep`, so a counted step need not change
anything), and `keep` permits `allVars G' ⊊ allVars G`, so a minted variable can LEAVE again --
which the loop really does do, since a `common`/`unify` step writes the alias into `env` and
`qsys` excludes aliases.  The library's card bound does bound its mint count only because its
systems grow monotonically; this one's do not.  **Bounding how many times the loop mints is an
open item, not a corollary of this.** -/
theorem LoopStrictKRun.allVars_card_le {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : LoopStrictKRun L n G₀ G) (rho : Assign) (hm : SModels rho G₀) (hcs : ConcSub L G₀) :
    (allVars G).card ≤ (allVars G₀).card + hmeas L rho G₀ := by
  obtain ⟨rho', -, -, hb⟩ := h.invariant rho hm hcs
  simp only [Pot] at hb
  omega

/-- The same SNAPSHOT bound at the labels the input carries, so that it depends on `G₀` alone.
(Named `vocab_snapshot_bound`, not `mints_bounded`: see the note above -- `n` does not appear
in the conclusion and is not bounded by it.) -/
theorem LoopStrictKRun.vocab_snapshot_bound {G₀ : System} (rho : Assign) (hm : SModels rho G₀) :
    ∀ (n : ℕ) (G : System), LoopStrictKRun (labelsOf G₀) n G₀ G →
      (allVars G).card ≤ (allVars G₀).card + hmeas (labelsOf G₀) rho G₀ :=
  fun _ _ h => h.allVars_card_le rho hm (labelsOf_concSub G₀)

end Rowpartition.Loop
