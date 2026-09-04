/-
# Stage 6: `makeEmpty` as a DELETING step -- does the mint bound survive it?

`Rowpartition.KeyedRow` (Stage 4) bounds minting on satisfiable input for the loop-extended,
fully rekeyed calculus `K2StarLoopStep` -- the keyed/row rules, guarded resolution with its
row branch, and ONE deleting step, the concretisation `concretizeSrs`.  The whole content of
that stage is the invariant `carried_concretizeSrs`: a CARRIED key stays carried under the
concretisation, so `ResGuardTerm`'s budget survives a step that deletes.

The compiler has a SECOND deleting step, `Constraints.makeEmpty` (`Constraints.scala`), and it
deletes precisely the carrier of the EMPTY row:

```scala
  def makeEmpty(v, incm, proc) = {
    def aux(s, rhs) = rhs match {
      case RHSEmpty()      => s                                          -- nothing to propagate
      case RHSAbstr(abstr) => s ++ abstr.map(x => Partition(x, RHSEmpty()))  -- the PROPAGATION
      case _               => tml.die("Incompatible instantiations of '" + v + "'")
    }
    val (pps, procd) = proc partition ruleInvolves(v)     -- v leaves BOTH queues
    val (qps, incmg) = incm partition ruleInvolves(v)
    val nps = (qps ++ pps).foldLeft(Set()) { case (s, Partition(u, rhs, inf)) =>
      if (u == v) aux(s, rhs) else s + Partition(u, rhs - v, inf) }   -- MENTIONS re-emitted
    instantiateType(v, ConcreteRho(Loc.builtin, Set()))   -- `v := ()` goes to the SubstEnv
    (incmg ++! trim(nps, procd), procd)
  }
```

`makeEmptyD` below is that function, read as a system-to-system map: the constraints that do
not involve `v` unchanged, every MENTION of `v` re-emitted with `v` erased, the PROPAGATION
`x <- ()` for every `x` in a bare abstract definition `v <- (xs)` of `v`, and NOTHING for
`v` itself -- the Scala moves `v := ()` into the substitution environment, so `v` is never
again a carrier or a witness in the queues, which is exactly what
`KEYED-ROW-STAGE5.md` §A.3 traced and what makes 74 of the corpus's 157 kept-definition mints
unreachable for the concrete-row lookup.  A definition of `v` with a NONEMPTY concrete part is
dropped here; `makeEmpty_conc_unsat` records that such a system has no model at all, which is
the `tml.die` arm.

## What is proved

* `makeEmptyD_sound` -- one direction: a model of `G` in which `v` is empty models the image
  (the step DELETES, so the converse is false and is not claimed);
* `makeEmpty_conc_unsat` -- the `die` arm, from `Saturate.empty_conc_unsat`;
* `allVars_makeEmptyD_subset`, `makeEmptyD_concSub` -- no new variable, no new label;
* **the hole, as a theorem** (`carried_not_invariant`, `hmeas_increases`): `Carried` is NOT an
  invariant of `makeEmptyD`, and Stage 4's potential `|allVars G| + hmeas L rho G` STRICTLY
  INCREASES on a two-constraint satisfiable system.  The missing piece is named exactly: a
  carrier of the EMPTY row, which is what the step deletes;
* **the conditional invariant** (`carried_makeEmptyD`): if the image still knows SOME variable
  empty, every carried key survives, at every variable of the image;
* **(T2)** `mintsBoundedOnSat_emptyPersisting`: the Stage 4 bound, unchanged, for every run of
  `K3LoopStep = K2StarLoopStep ∪ makeEmptyD` whose `makeEmpty` steps leave an empty-row
  carrier behind (`K3LoopRunEP`, an ORDER hypothesis on runs);
* **(T1) for the repaired step** `mintsBoundedOnSatKeyed3E`: keep `v <- ()` -- i.e. let the
  reverse lookup see the substitution environment -- and the bound holds unconditionally,
  in every order, with Stage 4's bound verbatim.

`MintsBoundedOnSatKeyed3` itself, over the faithful step with no hypothesis, is stated
(`MintsBoundedOnSatKeyed3`) and is neither proved nor refuted here.
-/
import Rowpartition.KeyedRow
import Rowpartition.Saturate

namespace Rowpartition

open NameLoss (denotes_of_conc mk_eq_iff)
open KeyedRow (Carried ConcCarried concCarried_iff uncarried hmeas uncarried_le_of_carried
  K2StarLoopStep K2StarLoopRun carried_concretizeSrs)

namespace KeyedEmpty

/-! ## 1. `makeEmpty`, read as a system-to-system map

Three pieces, one per arm of the Scala fold. -/

/-- `ruleInvolves(v)`: the partitions `makeEmpty` pulls out of both queues. -/
def Involves (v : Var) (c : Constraint) : Prop := c.lhs = v ∨ v ∈ vset c

instance (v : Var) (c : Constraint) : Decidable (Involves v c) :=
  inferInstanceAs (Decidable (c.lhs = v ∨ v ∈ vset c))

/-- The partitions `makeEmpty` never touches. -/
def keepPart (v : Var) (G : System) : System := G.filter (fun c => c.lhs ≠ v ∧ v ∉ vset c)

/-- Every MENTION `u <- (S ∪ {v}, K)` of `v`, re-emitted as `u <- (S, K)` (`rhs - v`). -/
def erasePart (v : Var) (G : System) : System :=
  (G.filter (fun c => c.lhs ≠ v ∧ v ∈ vset c)).image
    (fun c => mk c.lhs ((vset c).erase v) c.conc)

/-- The PROPAGATION: a definition `v <- (xs)` with only abstract parts (`RHSAbstr`) forces
every `x ∈ xs` empty.  A definition `v <- ()` (`RHSEmpty`) propagates nothing, and a
definition with a nonempty concrete part is the `die` arm -- dropped here, and
`makeEmpty_conc_unsat` says the system had no model. -/
def propPart (v : Var) (G : System) : System :=
  (G.filter (fun c => c.lhs = v ∧ c.conc = ∅)).biUnion
    (fun c => (vset c).image (fun x => mk x ∅ (∅ : Row)))

/-- **`makeEmpty`, faithfully.**  Note what is NOT here: `v <- ()` itself.  The Scala calls
`instantiateType(v, ConcreteRho(Set()))`, which writes the fact into the `SubstEnv` and NOT
back into either queue, so no later reverse lookup can find `v` as a carrier of the empty
row.  `makeEmptyE` below is the variant that keeps it. -/
def makeEmptyD (v : Var) (G : System) : System :=
  keepPart v G ∪ erasePart v G ∪ propPart v G

/-- **The repaired variant**: `v <- ()` retained, i.e. the reverse lookup is allowed to see
the substitution environment.  Nothing about `makeEmptyD` depends on this definition; §6
proves the bound for it separately, and §5 proves the bound for `makeEmptyD` under a
hypothesis instead. -/
def makeEmptyE (v : Var) (G : System) : System := insert (mk v ∅ (∅ : Row)) (makeEmptyD v G)

theorem mem_makeEmptyD {v : Var} {G : System} {c : Constraint} :
    c ∈ makeEmptyD v G ↔
      (c ∈ G ∧ c.lhs ≠ v ∧ v ∉ vset c) ∨
      (∃ d ∈ G, d.lhs ≠ v ∧ v ∈ vset d ∧ c = mk d.lhs ((vset d).erase v) d.conc) ∨
      (∃ d ∈ G, d.lhs = v ∧ d.conc = ∅ ∧ ∃ x ∈ vset d, c = mk x ∅ (∅ : Row)) := by
  simp only [makeEmptyD, keepPart, erasePart, propPart, Finset.mem_union, Finset.mem_filter,
    Finset.mem_image, Finset.mem_biUnion]
  constructor
  · rintro ((⟨hc, h1, h2⟩ | ⟨d, ⟨hd, h1, h2⟩, rfl⟩) | ⟨d, ⟨hd, h1, h2⟩, x, hx, rfl⟩)
    · exact Or.inl ⟨hc, h1, h2⟩
    · exact Or.inr (Or.inl ⟨d, hd, h1, h2, rfl⟩)
    · exact Or.inr (Or.inr ⟨d, hd, h1, h2, x, hx, rfl⟩)
  · rintro (⟨hc, h1, h2⟩ | ⟨d, hd, h1, h2, rfl⟩ | ⟨d, hd, h1, h2, x, hx, rfl⟩)
    · exact Or.inl (Or.inl ⟨hc, h1, h2⟩)
    · exact Or.inl (Or.inr ⟨d, ⟨hd, h1, h2⟩, rfl⟩)
    · exact Or.inr ⟨d, ⟨hd, h1, h2⟩, x, hx, rfl⟩

theorem mem_makeEmptyE {v : Var} {G : System} {c : Constraint} :
    c ∈ makeEmptyE v G ↔ c = mk v ∅ (∅ : Row) ∨ c ∈ makeEmptyD v G := Finset.mem_insert

theorem makeEmptyD_subset_E (v : Var) (G : System) : makeEmptyD v G ⊆ makeEmptyE v G :=
  Finset.subset_insert _ _

/-! ## 2. Soundness (one direction), and the `die` arm -/

/-- An empty variable may be erased from any right-hand side: the union does not move and the
disjointness conditions only get weaker.  This is `Canonical.sat_erase_empty` in the
set-shaped `mk` form the rest of the development uses. -/
theorem sat_erase_of_empty {rho : Assign} {c : Constraint} {v : Var}
    (hc : Sat rho c) (hv : rho v = ∅) :
    Sat rho (mk c.lhs ((vset c).erase v) c.conc) := by
  have hu : (vset c).biUnion rho = ((vset c).erase v).biUnion rho := by
    ext l
    simp only [Finset.mem_biUnion]
    constructor
    · rintro ⟨w, hw, hl⟩
      by_cases hwv : w = v
      · rw [hwv, hv] at hl; exact absurd hl (Finset.notMem_empty l)
      · exact ⟨w, Finset.mem_erase.mpr ⟨hwv, hw⟩, hl⟩
    · rintro ⟨w, hw, hl⟩
      exact ⟨w, Finset.mem_of_mem_erase hw, hl⟩
  rw [sat_mk_iff]
  refine ⟨by rw [hc.eq_biUnion, hu], ?_, ?_⟩
  · intro w hw; exact hc.disjoint_conc' (Finset.mem_of_mem_erase hw)
  · intro w hw z hz hwz
    exact hc.disjoint_of_ne' (Finset.mem_of_mem_erase hw) (Finset.mem_of_mem_erase hz) hwz

/-- The PROPAGATION is entailed: `v <- (xs)` with `rho v = ∅` forces every `x ∈ xs` empty. -/
theorem sat_prop_of_empty {rho : Assign} {c : Constraint} {v x : Var}
    (hc : Sat rho c) (hlhs : c.lhs = v) (hconc : c.conc = ∅) (hv : rho v = ∅)
    (hx : x ∈ vset c) : Sat rho (mk x ∅ (∅ : Row)) := by
  have h := hc.eq_biUnion
  rw [hlhs, hv, hconc, Finset.empty_union] at h
  have hx0 : rho x = ∅ := by
    refine Finset.eq_empty_of_forall_notMem (fun l hl => ?_)
    have hmem : l ∈ (vset c).biUnion rho := Finset.mem_biUnion.mpr ⟨x, hx, hl⟩
    rw [← h] at hmem
    exact absurd hmem (Finset.notMem_empty l)
  rw [sat_mk_iff]
  exact ⟨by simp [hx0], by simp, by simp⟩

/-- **`makeEmptyD` is sound, in the one direction a DELETING step admits.**  The converse
fails for the same reason `Saturate.SatStep.weaken`'s does: constraints are removed. -/
theorem makeEmptyD_sound {v : Var} {G : System} (he : mk v ∅ (∅ : Row) ∈ G) {rho : Assign}
    (hm : SModels rho G) : SModels rho (makeEmptyD v G) := by
  have hv : rho v = ∅ := denotes_of_conc he hm
  intro c hc
  rcases mem_makeEmptyD.mp hc with ⟨hcG, -, -⟩ | ⟨d, hd, -, -, rfl⟩ | ⟨d, hd, h1, h2, x, hx, rfl⟩
  · exact hm c hcG
  · exact sat_erase_of_empty (hm d hd) hv
  · exact sat_prop_of_empty (hm d hd) h1 h2 hv hx

theorem makeEmptyE_sound {v : Var} {G : System} (he : mk v ∅ (∅ : Row) ∈ G) {rho : Assign}
    (hm : SModels rho G) : SModels rho (makeEmptyE v G) := by
  intro c hc
  rcases mem_makeEmptyE.mp hc with rfl | hc
  · exact hm _ he
  · exact makeEmptyD_sound he hm c hc

/-- **The `die` arm** (`tml.die("Incompatible instantiations of ...")`): a variable cannot be
both empty and have fields.  `Saturate.empty_conc_unsat` in `mk` shape; `makeEmptyD` simply
DROPS such a definition, which this lemma says costs nothing, because the system it was in
had no model. -/
theorem makeEmpty_conc_unsat {G : System} {v : Var} {c : Constraint}
    (he : mk v ∅ (∅ : Row) ∈ G) (hc : c ∈ G) (hlhs : c.lhs = v) (hne : c.conc ≠ ∅) :
    ¬ ∃ rho, SModels rho G := by
  refine empty_conc_unsat (v := v) (c := c) ?_ hc hlhs hne
  have : (mk v ∅ (∅ : Row)) = (⟨v, [], (∅ : Finset Label)⟩ : Constraint) := by
    simp [mk, slist]
  rwa [this] at he

/-! ## 3. Vocabulary and labels -/

theorem allVars_makeEmptyD_subset (v : Var) (G : System) :
    allVars (makeEmptyD v G) ⊆ allVars G := by
  intro w hw
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
  rcases mem_makeEmptyD.mp hc with ⟨hcG, -, -⟩ | ⟨d, hd, -, -, rfl⟩ | ⟨d, hd, -, -, x, hx, rfl⟩
  · rcases Finset.mem_insert.mp hwc with h | h
    · exact mem_allVars hcG (Or.inl h)
    · exact mem_allVars hcG (Or.inr h)
  · rw [lhs_mk, vset_mk] at hwc
    rcases Finset.mem_insert.mp hwc with rfl | h
    · exact lhs_mem_allVars hd
    · exact mem_allVars hd (Or.inr (Finset.mem_of_mem_erase h))
  · rw [lhs_mk, vset_mk] at hwc
    rcases Finset.mem_insert.mp hwc with rfl | h
    · exact mem_allVars hd (Or.inr hx)
    · exact absurd h (Finset.notMem_empty _)

theorem allVars_makeEmptyE_subset {v : Var} {G : System} (he : mk v ∅ (∅ : Row) ∈ G) :
    allVars (makeEmptyE v G) ⊆ allVars G := by
  refine (allVars_mono (Finset.Subset.refl _)).trans ?_
  intro w hw
  obtain ⟨c, hc, hwc⟩ := Finset.mem_biUnion.mp hw
  rcases mem_makeEmptyE.mp hc with rfl | hc
  · rw [lhs_mk, vset_mk] at hwc
    rcases Finset.mem_insert.mp hwc with rfl | h
    · exact lhs_mem_allVars he
    · exact absurd h (Finset.notMem_empty _)
  · exact allVars_makeEmptyD_subset v G (Finset.mem_biUnion.mpr ⟨c, hc, hwc⟩)

theorem makeEmptyD_concSub {L : Finset Label} {v : Var} {G : System} (hcs : ConcSub L G) :
    ConcSub L (makeEmptyD v G) := by
  intro c hc
  rcases mem_makeEmptyD.mp hc with ⟨hcG, -, -⟩ | ⟨d, hd, -, -, rfl⟩ | ⟨d, -, -, -, x, -, rfl⟩
  · exact hcs c hcG
  · rw [conc_mk]; exact hcs d hd
  · rw [conc_mk]; exact Finset.empty_subset _

theorem makeEmptyE_concSub {L : Finset Label} {v : Var} {G : System} (hcs : ConcSub L G) :
    ConcSub L (makeEmptyE v G) := by
  intro c hc
  rcases mem_makeEmptyE.mp hc with rfl | hc
  · rw [conc_mk]; exact Finset.empty_subset _
  · exact makeEmptyD_concSub hcs c hc

/-- **The emptied variable leaves the vocabulary -- unless it mentions itself.**  Every
constraint of the image either avoids `v` outright or is one of the propagated `x <- ()`; so
if `v` survives at all, it survives as `v <- ()` itself, which the SELF-mention
`v <- (v, ...)` propagates.  In that one case the fact the Scala moved to the environment is
back in the system, and §4 shows every key at `v` is then carried. -/
theorem empty_of_mem_allVars {v : Var} {G : System} (hv : v ∈ allVars (makeEmptyD v G)) :
    mk v ∅ (∅ : Row) ∈ makeEmptyD v G := by
  obtain ⟨c, hc, hvc⟩ := Finset.mem_biUnion.mp hv
  rcases mem_makeEmptyD.mp hc with ⟨-, h1, h2⟩ | ⟨d, -, h1, -, rfl⟩ | ⟨d, -, -, -, x, -, rfl⟩
  · rcases Finset.mem_insert.mp hvc with h | h
    · exact absurd h.symm h1
    · exact absurd h h2
  · rw [lhs_mk, vset_mk] at hvc
    rcases Finset.mem_insert.mp hvc with h | h
    · exact absurd h.symm h1
    · exact absurd rfl (Finset.ne_of_mem_erase h)
  · rw [lhs_mk, vset_mk] at hvc
    rcases Finset.mem_insert.mp hvc with rfl | h
    · exact hc
    · exact absurd h (Finset.notMem_empty _)

/-! ## 4. The invariant, and the hole

`Carried` is the Stage 4 guard: `Resolved G v K ∨ ConcCarried G v K`.  Under `makeEmptyD v`
there are exactly two ways it can be lost at a variable `w ≠ v`, and BOTH ask for the same
missing constraint:

* a lone witness `w <- (v, K)` becomes the bare CONCRETE definition `w <- ((|K|))`, so the
  key `(w, K)` is carried iff something denotes `K \ K = ∅`;
* a concrete-row carrier `z = v` (`v <- ((|C \ K|))`, so `C \ K = ∅` under a model) is
  deleted, and the replacement must again denote `∅`.

So the invariant holds exactly when the image still knows SOME variable empty. -/

/-- `G` names the empty row. -/
def EmptyKnown (G : System) : Prop := ∃ e : Var, mk e ∅ (∅ : Row) ∈ G

/-- **The conditional invariant, at every variable other than the emptied one.**  Stated for
any superset of the image, so that `makeEmptyE` can use it with its own retained `v <- ()`
as the witness. -/
theorem carried_of_makeEmptyD_subset {G G' : System} {v w e : Var} {K : Row} {rho : Assign}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (hsub : makeEmptyD v G ⊆ G')
    (hE : mk e ∅ (∅ : Row) ∈ G') (hwv : w ≠ v) (h : Carried G w K) : Carried G' w K := by
  have hv : rho v = ∅ := denotes_of_conc he hm
  rcases h with h | h
  · obtain ⟨z, hz⟩ := (resolved_iff G w K).mp h
    by_cases hzv : z = v
    · -- the witness is a MENTION of `v`: it is re-emitted as the bare `w <- ((|K|))`
      subst hzv
      have himg : mk w ∅ K ∈ G' := by
        refine hsub (mem_makeEmptyD.mpr (Or.inr (Or.inl ⟨mk w {z} K, hz, ?_, ?_, ?_⟩)))
        · rw [lhs_mk]; exact hwv
        · rw [vset_mk]; exact Finset.mem_singleton_self z
        · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]
      exact KeyedRow.Carried.of_conc himg (by rw [Finset.sdiff_self]; exact hE)
    · -- the witness involves `v` nowhere, so it survives untouched
      refine KeyedRow.Carried.of_resolved (resolved_of_mem (hsub (mem_makeEmptyD.mpr
        (Or.inl ⟨hz, ?_, ?_⟩))))
      · rw [lhs_mk]; exact hwv
      · rw [vset_mk]; exact fun hh => hzv (Finset.mem_singleton.mp hh).symm
  · obtain ⟨C, z, hC, hz⟩ := (concCarried_iff G w K).mp h
    have hCmem : mk w ∅ C ∈ G' := by
      refine hsub (mem_makeEmptyD.mpr (Or.inl ⟨hC, ?_, ?_⟩))
      · rw [lhs_mk]; exact hwv
      · rw [vset_mk]; exact Finset.notMem_empty v
    by_cases hzv : z = v
    · -- the carrier of the complement row IS the emptied variable
      subst hzv
      have : C \ K = ∅ := by rw [← hv]; exact (denotes_of_conc hz hm).symm
      exact KeyedRow.Carried.of_conc hCmem (by rw [this]; exact hE)
    · refine KeyedRow.Carried.of_conc hCmem (hsub (mem_makeEmptyD.mpr (Or.inl ⟨hz, ?_, ?_⟩)))
      · rw [lhs_mk]; exact hzv
      · rw [vset_mk]; exact Finset.notMem_empty v

/-- **At the emptied variable itself**, whenever it is still in the vocabulary at all, every
key is carried: the only way it survives is as `v <- ()`, which carries `(v, K)` for every
`K`, being both the concrete definition and the carrier of `∅ \ K = ∅`. -/
theorem carried_self_of_mem_allVars {G : System} {v : Var} {K : Row}
    (hv : v ∈ allVars (makeEmptyD v G)) : Carried (makeEmptyD v G) v K := by
  have h := empty_of_mem_allVars hv
  exact KeyedRow.Carried.of_conc h (by rw [Finset.empty_sdiff]; exact h)

/-- **The conditional invariant, assembled.**  If the image still names the empty row, every
key carried before the step is carried after it, at every variable of the image. -/
theorem carried_makeEmptyD {G : System} {v w : Var} {K : Row} {rho : Assign}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (hE : EmptyKnown (makeEmptyD v G))
    (hw : w ∈ allVars (makeEmptyD v G)) (h : Carried G w K) :
    Carried (makeEmptyD v G) w K := by
  by_cases hwv : w = v
  · subst hwv; exact carried_self_of_mem_allVars hw
  · obtain ⟨e, hEe⟩ := hE
    exact carried_of_makeEmptyD_subset hm he (Finset.Subset.refl _) hEe hwv h

/-- **The REPAIRED step keeps the invariant unconditionally.**  Retaining `v <- ()` -- i.e.
letting the reverse lookup consult the substitution environment -- supplies the one missing
constraint in every case, at every variable. -/
theorem carried_makeEmptyE {G : System} {v w : Var} {K : Row} {rho : Assign}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (h : Carried G w K) :
    Carried (makeEmptyE v G) w K := by
  have hEe : mk v ∅ (∅ : Row) ∈ makeEmptyE v G := Finset.mem_insert_self _ _
  by_cases hwv : w = v
  · subst hwv
    exact KeyedRow.Carried.of_conc hEe (by rw [Finset.empty_sdiff]; exact hEe)
  · exact carried_of_makeEmptyD_subset hm he (makeEmptyD_subset_E v G) hEe hwv h

/-! ## 5. The measure, and the two bounds -/

/-- `KeyedRow.hmeas_le_of_carried` with the hypothesis restricted to the variables the
successor actually has -- which is what the emptied variable needs, since it usually leaves
the vocabulary entirely. -/
theorem hmeas_le_of_carried_on {L : Finset Label} {G G' : System} (rho : Assign)
    (hAV : allVars G' ⊆ allVars G)
    (hcar : ∀ w ∈ allVars G', ∀ K, Carried G w K → Carried G' w K) :
    hmeas L rho G' ≤ hmeas L rho G := by
  have h1 : hmeas L rho G'
      ≤ ∑ w ∈ allVars G', uncarried L G w * (2 ^ L.card + 1) ^ (rho w).card :=
    Finset.sum_le_sum fun w hw =>
      Nat.mul_le_mul (uncarried_le_of_carried (hcar w hw)) (Nat.le_refl _)
  exact h1.trans (Finset.sum_le_sum_of_subset hAV)

/-- One `makeEmptyD` step, under the hypothesis that the image still names the empty row. -/
theorem makeEmptyD_measure_step {L : Finset Label} {G : System} {v : Var} {rho : Assign}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) (hE : EmptyKnown (makeEmptyD v G)) :
    SModels rho (makeEmptyD v G) ∧
      (allVars (makeEmptyD v G)).card + hmeas L rho (makeEmptyD v G)
        ≤ (allVars G).card + hmeas L rho G := by
  refine ⟨makeEmptyD_sound he hm, ?_⟩
  have hAV := allVars_makeEmptyD_subset v G
  have hle : hmeas L rho (makeEmptyD v G) ≤ hmeas L rho G :=
    hmeas_le_of_carried_on rho hAV (fun w hw K hK => carried_makeEmptyD hm he hE hw hK)
  have hcard := Finset.card_le_card hAV
  omega

/-- One `makeEmptyE` step -- no hypothesis. -/
theorem makeEmptyE_measure_step {L : Finset Label} {G : System} {v : Var} {rho : Assign}
    (hm : SModels rho G) (he : mk v ∅ (∅ : Row) ∈ G) :
    SModels rho (makeEmptyE v G) ∧
      (allVars (makeEmptyE v G)).card + hmeas L rho (makeEmptyE v G)
        ≤ (allVars G).card + hmeas L rho G := by
  refine ⟨makeEmptyE_sound he hm, ?_⟩
  have hAV := allVars_makeEmptyE_subset he
  have hle : hmeas L rho (makeEmptyE v G) ≤ hmeas L rho G :=
    hmeas_le_of_carried_on rho hAV (fun _ _ _ hK => carried_makeEmptyE hm he hK)
  have hcard := Finset.card_le_card hAV
  omega

/-! ## 6. The relations and the statements -/

/-- **The Stage 6 relation.**  Stage 4's fully rekeyed loop-extended calculus, plus the
faithful `makeEmpty`. -/
inductive K3LoopStep : System → System → Prop
  | star {G G' : System} : K2StarLoopStep G G' → K3LoopStep G G'
  | empty {G : System} {v : Var} :
      mk v ∅ (∅ : Row) ∈ G → makeEmptyD v G ≠ G → K3LoopStep G (makeEmptyD v G)

inductive K3LoopRun : ℕ → System → System → Prop
  | refl (G : System) : K3LoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      K3LoopRun n G₀ G → K3LoopStep G G' → G ≠ G' → K3LoopRun (n + 1) G₀ G'

/-- **The Stage 6 question**, the Stage 4 statement for K3 runs. -/
def MintsBoundedOnSatKeyed3 : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K3LoopRun n G₀ G → (allVars G).card ≤ N

/-- **The ORDER hypothesis on runs**: every `makeEmpty` step leaves an empty-row carrier
behind.  `makeEmptyD v G` names the empty row exactly when the PROPAGATION fires (`v` had a
bare abstract definition `v <- (xs)` with `xs ≠ ∅`) or some other variable was already known
empty -- so this is precisely "the empty facts `makeEmpty` derives are taken, and are still
there when the split's reverse lookup runs". -/
inductive K3LoopRunEP : ℕ → System → System → Prop
  | refl (G : System) : K3LoopRunEP 0 G G
  | star {n : ℕ} {G₀ G G' : System} :
      K3LoopRunEP n G₀ G → K2StarLoopStep G G' → G ≠ G' → K3LoopRunEP (n + 1) G₀ G'
  | empty {n : ℕ} {G₀ G : System} {v : Var} :
      K3LoopRunEP n G₀ G → mk v ∅ (∅ : Row) ∈ G → EmptyKnown (makeEmptyD v G) →
      makeEmptyD v G ≠ G → K3LoopRunEP (n + 1) G₀ (makeEmptyD v G)

theorem K3LoopRunEP.toK3 {n : ℕ} {G₀ G : System} (h : K3LoopRunEP n G₀ G) :
    K3LoopRun n G₀ G := by
  induction h with
  | refl G => exact K3LoopRun.refl G
  | star _ hstep hne ih => exact K3LoopRun.tail ih (K3LoopStep.star hstep) hne
  | empty _ hmem _ hne ih => exact K3LoopRun.tail ih (K3LoopStep.empty hmem hne) (Ne.symm hne)

/-- The repaired relation: `makeEmptyE` in place of `makeEmptyD`. -/
inductive K3ELoopStep : System → System → Prop
  | star {G G' : System} : K2StarLoopStep G G' → K3ELoopStep G G'
  | empty {G : System} {v : Var} :
      mk v ∅ (∅ : Row) ∈ G → makeEmptyE v G ≠ G → K3ELoopStep G (makeEmptyE v G)

inductive K3ELoopRun : ℕ → System → System → Prop
  | refl (G : System) : K3ELoopRun 0 G G
  | tail {n : ℕ} {G₀ G G' : System} :
      K3ELoopRun n G₀ G → K3ELoopStep G G' → G ≠ G' → K3ELoopRun (n + 1) G₀ G'

def MintsBoundedOnSatKeyed3E : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K3ELoopRun n G₀ G → (allVars G).card ≤ N

/-! ### 6.1 The invariant along a run -/

theorem K3LoopRunEP.concSub {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K3LoopRunEP n G₀ G) : ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl => exact id
  | star _ hstep _ ih => exact fun hcs => hstep.concSub (ih hcs)
  | empty _ _ _ _ ih => exact fun hcs => makeEmptyD_concSub (ih hcs)

theorem K3ELoopRun.concSub {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K3ELoopRun n G₀ G) : ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl => exact id
  | tail _ hstep _ ih =>
    intro hcs
    cases hstep with
    | star hs => exact hs.concSub (ih hcs)
    | empty _ _ => exact makeEmptyE_concSub (ih hcs)

theorem K3LoopRunEP.invariant {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K3LoopRunEP n G₀ G) :
    ∀ (rho₀ : Assign), SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧
        (allVars G).card + hmeas L rho G ≤ (allVars G₀).card + hmeas L rho₀ G₀ := by
  induction h with
  | refl G => intro rho₀ hm _; exact ⟨rho₀, hm, Nat.le_refl _⟩
  | @star n G₀ G G' hrun hstep _ ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hb⟩ := ih rho₀ hm hcs
    obtain ⟨rho', hm', -, hb'⟩ := hstep.measure_step (hrun.concSub hcs) hmr
    exact ⟨rho', hm', le_trans hb' hb⟩
  | @empty n G₀ G v hrun hmem hE _ ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hb⟩ := ih rho₀ hm hcs
    obtain ⟨hm', hb'⟩ := makeEmptyD_measure_step (L := L) hmr hmem hE
    exact ⟨rho, hm', le_trans hb' hb⟩

theorem K3ELoopRun.invariant {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : K3ELoopRun n G₀ G) :
    ∀ (rho₀ : Assign), SModels rho₀ G₀ → ConcSub L G₀ →
      ∃ rho, SModels rho G ∧
        (allVars G).card + hmeas L rho G ≤ (allVars G₀).card + hmeas L rho₀ G₀ := by
  induction h with
  | refl G => intro rho₀ hm _; exact ⟨rho₀, hm, Nat.le_refl _⟩
  | @tail n G₀ G G' hrun hstep _ ih =>
    intro rho₀ hm hcs
    obtain ⟨rho, hmr, hb⟩ := ih rho₀ hm hcs
    cases hstep with
    | star hs =>
      obtain ⟨rho', hm', -, hb'⟩ := hs.measure_step (hrun.concSub hcs) hmr
      exact ⟨rho', hm', le_trans hb' hb⟩
    | @empty v hmem _ =>
      obtain ⟨hm', hb'⟩ := makeEmptyE_measure_step (L := L) hmr hmem
      exact ⟨rho, hm', le_trans hb' hb⟩

/-! ### 6.2 (T2) and (T1) -/

/-- **(T2) -- the bound survives `makeEmpty` under the ORDER hypothesis.**  Every run of the
Stage 6 relation whose `makeEmpty` steps leave an empty-row carrier behind has the Stage 4
bound, verbatim: `|allVars G₀| + hmeas (labelsOf G₀) rho G₀`. -/
theorem mintsBoundedOnSat_emptyPersisting (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), K3LoopRunEP n G₀ G → (allVars G).card ≤ N :=
  ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀, fun _ _ h => by
    obtain ⟨rho', -, hb⟩ := h.invariant rho hm (labelsOf_concSub G₀)
    omega⟩

/-- **(T1) for the repaired step.**  Keep `v <- ()` in the system -- i.e. let the reverse
lookup see the emptied variable -- and minting is BOUNDED on satisfiable input for the whole
Stage 6 calculus, in every order, with no hypothesis on the run. -/
theorem mintsBoundedOnSatKeyed3E : MintsBoundedOnSatKeyed3E :=
  fun G₀ rho hm =>
    ⟨(allVars G₀).card + hmeas (labelsOf G₀) rho G₀, fun _ _ h => by
      obtain ⟨rho', -, hb⟩ := h.invariant rho hm (labelsOf_concSub G₀)
      omega⟩

/-! ## 7. The hole, as a theorem

`Carried` is NOT an invariant of the faithful step.  The counterexample is three constraints
and needs no minting at all: a lone witness `w <- (v, K)` whose abstract part is the emptied
variable is re-emitted as the bare concrete `w <- ((|K|))`, and the key `(w, K)` then asks for
a carrier of `K \ K = ∅` -- which is exactly the `v <- ()` the step deleted. -/

section Hole

/-- the emptied variable -/
abbrev v0 : Var := 0
/-- the variable whose key is lost -/
abbrev v1 : Var := 1
abbrev l1 : Label := 1
abbrev l2 : Label := 2

/-- the key, and the row `v1` denotes -/
def EE6 : Row := {l1, l2}

/-- `v0 <- ()`, `v1 <- ((|l1,l2|))`, `v1 <- (v0, (|l1,l2|))`. -/
def G6 : System := {mk v0 ∅ (∅ : Row), mk v1 ∅ EE6, mk v1 {v0} EE6}

def rho6 : Assign := fun v => if v = v1 then EE6 else ∅

theorem rho6_v0 : rho6 v0 = ∅ := by decide
theorem rho6_v1 : rho6 v1 = EE6 := by simp [rho6]

theorem G6_models : SModels rho6 G6 := by
  intro c hc
  simp only [G6, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl
  · rw [sat_mk_iff]; refine ⟨by simp [rho6_v0], by simp, by simp⟩
  · rw [sat_mk_iff]; refine ⟨by simp [rho6_v1], by simp, by simp⟩
  · rw [sat_mk_iff]
    refine ⟨by simp [rho6_v1, rho6_v0], ?_, by simp⟩
    intro w hw
    rw [Finset.mem_singleton] at hw
    subst hw
    simp [rho6_v0]

theorem G6_satisfiable : ∃ rho, SModels rho G6 := ⟨rho6, G6_models⟩

theorem G6_empty_mem : mk v0 ∅ (∅ : Row) ∈ G6 := by
  simp [G6]

/-- **The image, computed.**  Both the untouched `v1 <- ((|l1,l2|))` and the re-emission of
`v1 <- (v0, (|l1,l2|))` collapse onto the same bare concrete definition, and there is no
propagation: `v0`'s only definition is `v0 <- ()` itself (`RHSEmpty`, the arm of `aux` that
derives nothing). -/
theorem makeEmptyD_G6 : makeEmptyD v0 G6 = {mk v1 ∅ EE6} := by
  ext c
  rw [Finset.mem_singleton]
  constructor
  · intro hc
    rcases mem_makeEmptyD.mp hc with ⟨hcG, h1, h2⟩ | ⟨d, hd, h1, h2, rfl⟩ |
      ⟨d, hd, h1, h2, x, hx, rfl⟩
    · simp only [G6, Finset.mem_insert, Finset.mem_singleton] at hcG
      rcases hcG with rfl | rfl | rfl
      · exact absurd (lhs_mk v0 ∅ (∅ : Row)) h1
      · rfl
      · exact absurd (by rw [vset_mk]; exact Finset.mem_singleton_self v0) h2
    · simp only [G6, Finset.mem_insert, Finset.mem_singleton] at hd
      rcases hd with rfl | rfl | rfl
      · exact absurd (lhs_mk v0 ∅ (∅ : Row)) h1
      · exact absurd (by rw [vset_mk] at h2; exact h2) (Finset.notMem_empty v0)
      · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]
    · simp only [G6, Finset.mem_insert, Finset.mem_singleton] at hd
      rcases hd with rfl | rfl | rfl
      · rw [vset_mk] at hx; exact absurd hx (Finset.notMem_empty x)
      · exact absurd (h1 ▸ (lhs_mk v1 ∅ EE6)) (by decide)
      · exact absurd (h1 ▸ (lhs_mk v1 {v0} EE6)) (by decide)
  · rintro rfl
    refine mem_makeEmptyD.mpr (Or.inl ⟨?_, ?_, ?_⟩)
    · simp [G6]
    · rw [lhs_mk]; decide
    · rw [vset_mk]; exact Finset.notMem_empty v0

theorem EE6_ne_empty : EE6 ≠ ∅ := by decide

/-- **Before**: the key `(v1, EE6)` is carried, by the lone witness `v1 <- (v0, (|l1,l2|))`. -/
theorem carried_G6 : Carried G6 v1 EE6 :=
  KeyedRow.Carried.of_resolved (resolved_of_mem (by
    simp only [G6, Finset.mem_insert, Finset.mem_singleton]; exact Or.inr (Or.inr rfl)))

/-- **After**: it is not.  `Resolved` fails because the erasure emptied the abstract part;
`ConcCarried` fails because the complement row is `EE6 \ EE6 = ∅` and nothing denotes `∅` any
more -- `v0 <- ()` went into the substitution environment. -/
theorem not_carried_G6 : ¬ Carried (makeEmptyD v0 G6) v1 EE6 := by
  rw [makeEmptyD_G6]
  rintro (h | h)
  · obtain ⟨z, hz⟩ := (resolved_iff _ v1 EE6).mp h
    rw [Finset.mem_singleton, mk_eq_iff] at hz
    exact absurd hz.2.1 (Finset.singleton_ne_empty z)
  · obtain ⟨C, z, hC, hz⟩ := (concCarried_iff _ v1 EE6).mp h
    rw [Finset.mem_singleton, mk_eq_iff] at hC hz
    rw [hC.2.2, Finset.sdiff_self] at hz
    exact EE6_ne_empty hz.2.2.symm

/-- **`Carried` is not an invariant of `makeEmptyD`.**  This is the one step at which Stage
4's argument fails, and the missing constraint is named exactly: a carrier of the EMPTY row. -/
theorem carried_not_invariant :
    ∃ (G : System) (v w : Var) (K : Row) (rho : Assign),
      SModels rho G ∧ mk v ∅ (∅ : Row) ∈ G ∧
        Carried G w K ∧ ¬ Carried (makeEmptyD v G) w K :=
  ⟨G6, v0, v1, EE6, rho6, G6_models, G6_empty_mem, carried_G6, not_carried_G6⟩

/-! ### 7.1 ... and Stage 4's potential really does go UP -/

/-- the label budget of `G6` -/
def L6 : Finset Label := {l1, l2}

theorem allVars_G6 : allVars G6 = {v0, v1} := by decide +kernel

theorem allVars_G6' : allVars (makeEmptyD v0 G6) = {v1} := by
  rw [makeEmptyD_G6]; decide +kernel

/-- The emptied variable spends no budget: `v0 <- ()` carries every key at `v0`. -/
theorem uncarried_G6_v0 : uncarried L6 G6 v0 = 0 := by
  rw [uncarried, Finset.card_eq_zero, Finset.filter_eq_empty_iff]
  intro K _
  exact not_not.mpr
    (KeyedRow.Carried.of_conc G6_empty_mem (by rw [Finset.empty_sdiff]; exact G6_empty_mem))

theorem G6'_subset : makeEmptyD v0 G6 ⊆ G6 := by
  rw [makeEmptyD_G6]
  intro c hc
  rw [Finset.mem_singleton] at hc
  subst hc
  simp [G6]

/-- **One more key is open after the step than before it.**  The image is a SUBSET of `G6`, so
it carries no key `G6` did not; and it fails to carry `(v1, EE6)`, which `G6` did. -/
theorem uncarried_G6_v1_lt : uncarried L6 G6 v1 < uncarried L6 (makeEmptyD v0 G6) v1 := by
  refine Finset.card_lt_card ⟨?_, ?_⟩
  · intro K hK
    rw [Finset.mem_filter] at hK ⊢
    exact ⟨hK.1, fun hc => hK.2 (hc.mono G6'_subset)⟩
  · intro hss
    have hmem : EE6 ∈ L6.powerset.filter (fun K => ¬ Carried (makeEmptyD v0 G6) v1 K) :=
      Finset.mem_filter.mpr ⟨Finset.mem_powerset.mpr (by decide), not_carried_G6⟩
    exact (Finset.mem_filter.mp (hss hmem)).2 carried_G6

theorem two_le_weight : 2 ≤ (2 ^ L6.card + 1) ^ (rho6 v1).card := by
  have h1 : 2 ≤ 2 ^ L6.card + 1 := by
    have := Nat.one_le_two_pow (n := L6.card); omega
  have h2 : (rho6 v1).card ≠ 0 := by rw [rho6_v1]; decide
  exact h1.trans (Nat.le_self_pow h2 _)

/-- **Stage 4's potential `|allVars G| + hmeas L rho G` STRICTLY INCREASES** across one
faithful `makeEmpty` step of a satisfiable system.  So `K2StarLoopStep.measure_step` has no
analogue here, and the Stage 4 proof does not merely need a new lemma: its measure is wrong
for this step. -/
theorem hmeas_increases :
    (allVars G6).card + hmeas L6 rho6 G6
      < (allVars (makeEmptyD v0 G6)).card + hmeas L6 rho6 (makeEmptyD v0 G6) := by
  have hs : hmeas L6 rho6 G6
      = uncarried L6 G6 v0 * (2 ^ L6.card + 1) ^ (rho6 v0).card
        + uncarried L6 G6 v1 * (2 ^ L6.card + 1) ^ (rho6 v1).card := by
    rw [hmeas, allVars_G6, Finset.sum_insert (by decide), Finset.sum_singleton]
  have hs' : hmeas L6 rho6 (makeEmptyD v0 G6)
      = uncarried L6 (makeEmptyD v0 G6) v1 * (2 ^ L6.card + 1) ^ (rho6 v1).card := by
    rw [hmeas, allVars_G6', Finset.sum_singleton]
  have hc : (allVars G6).card = 2 := by rw [allVars_G6]; decide
  have hc' : (allVars (makeEmptyD v0 G6)).card = 1 := by rw [allVars_G6']; decide
  have hstep : uncarried L6 G6 v1 + 1 ≤ uncarried L6 (makeEmptyD v0 G6) v1 :=
    uncarried_G6_v1_lt
  have hmul : (uncarried L6 G6 v1 + 1) * (2 ^ L6.card + 1) ^ (rho6 v1).card
      ≤ uncarried L6 (makeEmptyD v0 G6) v1 * (2 ^ L6.card + 1) ^ (rho6 v1).card :=
    Nat.mul_le_mul hstep (Nat.le_refl _)
  rw [Nat.add_mul, Nat.one_mul] at hmul
  rw [hs, hs', hc, hc', uncarried_G6_v0]
  have := two_le_weight
  omega

end Hole

/-! ## 8. The mechanism notes, checked

The brief's notes, each turned into a lemma. -/

/-- **Note 1 -- an erased witness becomes a CONCRETE DEFINITION.**  `makeEmpty` does not
re-express `u <- (v, K)` as anything clever: it erases `v`, and what is left is
`u <- ((|K|))`, a bare concrete partition.  So `u` IS made concrete by the step, and
`K2RowApp.lhsConc` -- the premise of the concrete-row split branch -- is available at `u`. -/
theorem emptied_mention_conc {G : System} {u v : Var} {K : Row}
    (hu : mk u {v} K ∈ G) (huv : u ≠ v) : mk u ∅ K ∈ makeEmptyD v G := by
  refine mem_makeEmptyD.mpr (Or.inr (Or.inl ⟨mk u {v} K, hu, ?_, ?_, ?_⟩))
  · rw [lhs_mk]; exact huv
  · rw [vset_mk]; exact Finset.mem_singleton_self v
  · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]

/-- **Note 1, second half -- and it IS a carrier for other keys.**  Any key `(w, J)` whose
complement row is exactly `K` is carried by the erased witness's residue.  So the deletion is
not uniformly destructive: what it destroys is the key `(u, K)` itself, whose complement is
`K \ K = ∅`. -/
theorem carrier_of_emptied_mention {G : System} {u v w : Var} {C J K : Row}
    (hw : mk w ∅ C ∈ G) (hwv : w ≠ v) (hu : mk u {v} K ∈ G) (huv : u ≠ v) (hCJ : C \ J = K) :
    Carried (makeEmptyD v G) w J := by
  have h1 : mk w ∅ C ∈ makeEmptyD v G := by
    refine mem_makeEmptyD.mpr (Or.inl ⟨hw, ?_, ?_⟩)
    · rw [lhs_mk]; exact hwv
    · rw [vset_mk]; exact Finset.notMem_empty v
  have h2 : mk u ∅ (C \ J) ∈ makeEmptyD v G := by
    rw [hCJ]; exact emptied_mention_conc hu huv
  exact KeyedRow.Carried.of_conc h1 h2

/-- **Note 2 -- the hole, stated positively.**  At the key the erasure closes on itself, the
carrier needed is one of the EMPTY row: `ConcCarried` at `(u, K)` through the residue
`u <- ((|K|))` asks for `mk z ∅ (K \ K) = mk z ∅ ∅`.  `carried_not_invariant` shows nothing
supplies it in general; `carried_of_makeEmptyD_subset` shows anything that does is enough. -/
theorem carried_emptied_key_of_emptyKnown {G : System} {u v e : Var} {K : Row}
    (hu : mk u {v} K ∈ G) (huv : u ≠ v) (hE : mk e ∅ (∅ : Row) ∈ makeEmptyD v G) :
    Carried (makeEmptyD v G) u K :=
  KeyedRow.Carried.of_conc (emptied_mention_conc hu huv)
    (by rw [Finset.sdiff_self]; exact hE)

/-- **Note 3 -- the PROPAGATION is the only automatic source of the missing carrier.**  A
bare abstract definition `v <- (xs)` of the emptied variable puts `x <- ()` in the image for
every `x ∈ xs`; that is `aux`'s `RHSAbstr` arm, and it is what saves the split premise whose
group the mint would have named. -/
theorem emptyKnown_of_bare_abstr {G : System} {v x : Var} {S : Finset Var}
    (hd : mk v S (∅ : Row) ∈ G) (hx : x ∈ S) : EmptyKnown (makeEmptyD v G) :=
  ⟨x, mem_makeEmptyD.mpr (Or.inr (Or.inr ⟨mk v S ∅, hd, lhs_mk _ _ _, conc_mk _ _ _,
    x, by rw [vset_mk]; exact hx, rfl⟩))⟩

/-- **Note 3b -- the second source**: another variable already known empty simply survives,
being a bare partition headed by something other than `v`. -/
theorem emptyKnown_of_other {G : System} {v e : Var} (hne : e ≠ v)
    (h : mk e ∅ (∅ : Row) ∈ G) : EmptyKnown (makeEmptyD v G) :=
  ⟨e, mem_makeEmptyD.mpr (Or.inl ⟨h, by rw [lhs_mk]; exact hne,
    by rw [vset_mk]; exact Finset.notMem_empty v⟩)⟩

/-- **Note 3c -- the third source**: a BARE lone mention `e <- (v)` of the emptied variable is
re-emitted as `e <- ()`, so the erasure itself can manufacture the carrier. -/
theorem emptyKnown_of_bare_mention {G : System} {v e : Var} (hne : e ≠ v)
    (h : mk e {v} (∅ : Row) ∈ G) : EmptyKnown (makeEmptyD v G) :=
  ⟨e, mem_makeEmptyD.mpr (Or.inr (Or.inl ⟨mk e {v} ∅, h, by rw [lhs_mk]; exact hne,
    by rw [vset_mk]; exact Finset.mem_singleton_self v,
    by rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]⟩))⟩

/-- **... and those three are ALL the sources.**  So the order hypothesis of §6 is a decidable
condition on the system at the step, not an oracle: `makeEmptyD v G` names the empty row iff
some other variable was already known empty, or `v` occurs alone and bare in some right-hand
side, or `v` has a bare abstract definition with a nonempty group. -/
theorem emptyKnown_makeEmptyD {G : System} {v : Var} (h : EmptyKnown (makeEmptyD v G)) :
    (∃ e, e ≠ v ∧ mk e ∅ (∅ : Row) ∈ G) ∨
    (∃ d ∈ G, d.lhs ≠ v ∧ v ∈ vset d ∧ (vset d).erase v = ∅ ∧ d.conc = ∅) ∨
    (∃ d ∈ G, d.lhs = v ∧ d.conc = ∅ ∧ (vset d).Nonempty) := by
  obtain ⟨e, he⟩ := h
  rcases mem_makeEmptyD.mp he with ⟨hcG, h1, h2⟩ | ⟨d, hd, h1, h2, heq⟩ |
    ⟨d, hd, h1, h2, x, hx, -⟩
  · exact Or.inl ⟨e, by rw [lhs_mk] at h1; exact h1, hcG⟩
  · obtain ⟨-, hS, hK⟩ := mk_inj heq
    exact Or.inr (Or.inl ⟨d, hd, h1, h2, hS.symm, hK.symm⟩)
  · exact Or.inr (Or.inr ⟨d, hd, h1, h2, ⟨x, hx⟩⟩)

/-- **Note 4 -- under a model, an emptied `lhs` really does force its whole group empty.**
`rho u = K` and `u <- (S, K)` give `rho x = ∅` for every `x ∈ S`.  The point of §8.1 is that
this is a SEMANTIC fact: the constraint `x <- ()` is not thereby in the system, and in the
any-order relation nothing puts it there before the premise is dequeued. -/
theorem group_forced_empty {G : System} {rho : Assign} {u : Var} {K : Row} {c : Constraint}
    (hm : SModels rho G) (hconc : mk u ∅ K ∈ G) (hc : c ∈ G) (hlhs : c.lhs = u)
    (hK : c.conc = K) {x : Var} (hx : x ∈ vset c) : rho x = ∅ := by
  have hu : rho u = K := denotes_of_conc hconc hm
  have h := (hm c hc).eq_biUnion
  rw [hlhs, hu, hK] at h
  refine Finset.eq_empty_of_forall_notMem (fun l hl => ?_)
  have hmem : l ∈ K ∪ (vset c).biUnion rho :=
    Finset.mem_union_right _ (Finset.mem_biUnion.mpr ⟨x, hx, hl⟩)
  rw [← h] at hmem
  have hdis : Disjoint c.conc (rho x) := (hm c hc).disjoint_conc' hx
  rw [hK] at hdis
  exact Finset.disjoint_left.mp hdis hmem hl

/-! ### 8.1 The 74-of-157 population, formalised

A satisfiable system in which the split premise's group is FORCED EMPTY, no variable is known
empty, and the mint therefore fires -- every premise of `KeyedRow.K2MintApp` holds.  This is
the shape `KEYED-ROW-STAGE5.md` §B7-2 counted 74 times in the corpus: `v` concrete, `K = C`,
complement the empty row, carrier deleted by `makeEmpty`. -/

section Population

abbrev p7 : Var := 0
abbrev x7 : Var := 1
abbrev y7 : Var := 2
abbrev u7 : Var := 3
abbrev k7 : Label := 1

/-- the premise's concrete part, which is also the whole of `rho p7` -/
def K7 : Row := {k7}

/-- `p <- ((|k|))` and the kept premise `p <- (x, y, (|k|))`. -/
def G7 : System := {mk p7 ∅ K7, mk p7 {x7, y7} K7}

def rho7 : Assign := fun v => if v = p7 then K7 else ∅

theorem rho7_p7 : rho7 p7 = K7 := by decide
theorem rho7_group : ∀ w ∈ ({x7, y7} : Finset Var), rho7 w = ∅ := by decide

theorem biUnion_group : ({x7, y7} : Finset Var).biUnion rho7 = ∅ := by
  refine Finset.eq_empty_of_forall_notMem (fun l hl => ?_)
  obtain ⟨w, hw, hlw⟩ := Finset.mem_biUnion.mp hl
  rw [rho7_group w hw] at hlw
  exact absurd hlw (Finset.notMem_empty l)

theorem G7_models : SModels rho7 G7 := by
  intro c hc
  simp only [G7, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl
  · rw [sat_mk_iff]; exact ⟨by simp [rho7_p7], by simp, by simp⟩
  · rw [sat_mk_iff]
    refine ⟨by rw [rho7_p7, biUnion_group, Finset.union_empty], ?_, ?_⟩
    · intro w hw
      rw [rho7_group w hw]
      exact Finset.disjoint_empty_right _
    · intro w hw z hz _
      rw [rho7_group w hw]
      exact Finset.disjoint_empty_left _

theorem G7_satisfiable : ∃ rho, SModels rho G7 := ⟨rho7, G7_models⟩

/-- **Nothing in the system denotes the empty row** -- the emptied carriers are in the
substitution environment, where the reverse lookup cannot see them. -/
theorem G7_not_emptyKnown : ¬ EmptyKnown G7 := by
  rintro ⟨e, he⟩
  simp only [G7, Finset.mem_insert, Finset.mem_singleton, mk_eq_iff] at he
  rcases he with ⟨-, -, h⟩ | ⟨-, h, -⟩
  · exact absurd h.symm (by decide)
  · exact absurd h.symm (by decide)

/-- ... and the group of the premise is forced empty all the same. -/
theorem G7_group_empty (w : Var) (hw : w ∈ ({x7, y7} : Finset Var)) : rho7 w = ∅ :=
  group_forced_empty (G := G7) (u := p7) (K := K7) (c := mk p7 {x7, y7} K7) G7_models
    (by simp [G7]) (by simp [G7]) (lhs_mk _ _ _) (conc_mk _ _ _) (by rw [vset_mk]; exact hw)

theorem G7_not_named : ¬ Named G7 (vset (mk p7 {x7, y7} K7)) := by
  rintro ⟨d, hd, hv, hc⟩
  simp only [G7, Finset.mem_insert, Finset.mem_singleton] at hd
  rcases hd with rfl | rfl
  · rw [vset_mk, vset_mk] at hv; exact absurd hv.symm (by decide)
  · rw [conc_mk] at hc; exact absurd hc (by decide)

theorem G7_not_carried : ¬ Carried G7 p7 K7 := by
  rintro (h | h)
  · obtain ⟨z, hz⟩ := (resolved_iff G7 p7 K7).mp h
    simp only [G7, Finset.mem_insert, Finset.mem_singleton, mk_eq_iff] at hz
    rcases hz with ⟨-, h, -⟩ | ⟨-, h, -⟩
    · exact absurd h (Finset.singleton_ne_empty z)
    · have hcard := congrArg Finset.card h
      rw [Finset.card_singleton] at hcard
      exact absurd hcard (by decide)
  · obtain ⟨C, z, hC, hz⟩ := (concCarried_iff G7 p7 K7).mp h
    simp only [G7, Finset.mem_insert, Finset.mem_singleton, mk_eq_iff] at hC hz
    have hCK : C = K7 := by
      rcases hC with ⟨-, -, h⟩ | ⟨-, h, -⟩
      · exact h
      · exact absurd h.symm (by decide)
    rw [hCK, Finset.sdiff_self] at hz
    rcases hz with ⟨-, -, h⟩ | ⟨-, h, -⟩
    · exact absurd h.symm (by decide)
    · exact absurd h.symm (by decide)

theorem u7_fresh : u7 ∉ allVars G7 := by
  intro h
  obtain ⟨c, hc, hu⟩ := Finset.mem_biUnion.mp h
  simp only [G7, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl <;> rw [lhs_mk, vset_mk] at hu <;> revert hu <;> decide

/-- **The mint fires.**  Every premise of the Stage 4 mint holds on a SATISFIABLE system whose
split group is forced empty: the syntactic lookup misses, the keyed lookup misses, and the
concrete-row lookup misses because the only carrier it could use is a variable denoting `∅`,
which `makeEmpty` has removed from the queues.  This is the 74-of-157 population. -/
theorem G7_mints : KeyedRow.K2MintApp G7 (mk p7 {x7, y7} K7) u7 where
  mem := by simp [G7]
  conc_ne := by rw [conc_mk]; decide
  two_le := by rw [vset_mk]; decide
  unnamed := G7_not_named
  uncarried := by rw [lhs_mk, conc_mk]; exact G7_not_carried
  fresh := u7_fresh

/-- ... and putting the deleted carrier back blocks it.  One bare `e <- ()` -- the fact the
Scala moved into the `SubstEnv` -- turns the mint into a `K2RowApp` reuse. -/
theorem G7_blocked (e : Var) : Carried (insert (mk e ∅ (∅ : Row)) G7) p7 K7 := by
  have h1 : mk p7 ∅ K7 ∈ insert (mk e ∅ (∅ : Row)) G7 :=
    Finset.mem_insert_of_mem (by simp [G7])
  have h2 : mk e ∅ (K7 \ K7) ∈ insert (mk e ∅ (∅ : Row)) G7 := by
    rw [Finset.sdiff_self]; exact Finset.mem_insert_self _ _
  exact KeyedRow.Carried.of_conc h1 h2

end Population

end KeyedEmpty
end Rowpartition
