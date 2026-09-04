/-
# Stage 7: the Scala `splitConcrete` / `resolution` WITH the EMPTY-ROW branch

`KeyedEmpty.lean` (Stage 6) adds the compiler's second deleting step, `makeEmpty`, to the
Stage 4 relation.  Its answer is (T2)/(T1): `Carried` fails to be an invariant of the
faithful step `makeEmptyD` in exactly one way -- the deleted `v <- ()` was the carrier of the
EMPTY row (`carried_not_invariant`) -- and RETAINING that fact (`makeEmptyE`) restores the
bound unconditionally (`mintsBoundedOnSatKeyed3E`).  `G7_mints` is the 74-of-157 corpus
population as a theorem, and `G7_blocked` says one visible `e <- ()` turns each such mint
into a reuse.

Stage 7 implements that in `Constraints.scala` behind `-Dermine.emptyRow` (DEFAULT OFF).
This module is the transcription, written as `KeyedRowScala.lean` is.

## What the compiler does, and the two places it departs from `K2RowApp`

The Scala lookup is `learnPartitions`' `findEmptyRow`:

    lazy val envEmptyRow: Option[TypeVar] =
      hm.types.collectFirst { case (z, ConcreteRho(_, fs)) if fs.isEmpty => z }
    def findEmptyRow(k: Fields): Option[TypeVar] = {
      val (rows, myRow) = concRows
      myRow.filter(c => (k subsetOf c) && (c -- k).isEmpty)
           .flatMap(_ => rows.get(Set[Name]()) orElse envEmptyRow)
    }

i.e. Stage 5's `findConcRow` with the complement pinned to the EMPTY row, and with a SECOND
source for the carrier: the substitution environment, where `makeEmpty` left the fact
(`instantiateType(v, ConcreteRho(∅))`) after deleting every partition that mentions `v`.
So the state this module models is NOT the queues alone but

    H  =  the queues  ∪  the retained facts of the environment,

which is exactly the system `makeEmptyE` produces, and `SoleFact H z` below is what
"`makeEmpty` deleted every partition mentioning `z`" says about a retained carrier.

1. **The lookup is `ConcRowSpec` at `C \ K = ∅`** (`EmptyRowSpec`, `emptyRowSpec_toConcRow`),
   so a HIT is a `KeyedRow.K2RowApp H c z C` -- the Stage 4 reuse -- on that state.
2. **What the branch EMITS is not `K2RowApp`'s conclusion.**  The Lean reuse emits
   `z <- (vset c)`; the compiler must not, because `z` is instantiated and out of the queues,
   and a partition about it would reach `makeEmpty` a second time.  It emits the PROPAGATION
   instead, `x <- ()` for every `x ∈ vset c`, and `emptyReuse_compose` is the theorem that
   makes the two agree: on a state where `z`'s only occurrence is the retained fact,

       makeEmptyE z (kSplitReuseResult H c z)  =  H ∪ emptyProp (vset c),

   so the Scala's ONE step is the Lean reuse COMPOSED WITH ITS FORCED `empty` STEP --
   `splitEmpty_two_steps : K3ELoopRun 2 H (splitEmptyResult H c)`.  The same for resolution
   (`resEmptyReuse_compose`, `resEmpty_two_steps`), where the emitted conclusions are the
   reuse's two with the carrier's row substituted in: `x <- ((|D \ C|))`, `y <- ((|C \ D|))`.

Hence the headline `scalaEmptySplit_run` / `scalaEmptyRes_run`: every system either extended
rule returns is reachable from the state by a run of `K3ELoopStep`, whose vocabulary
`mintsBoundedOnSatKeyed3E` bounds -- `scalaEmptySplit_bounded` states the bound explicitly.

## Soundness needs no carrier at all

`splitEmpty_models_iff` and `resEmpty_models_iff`: what the branches emit is entailed by the
PREMISE alone (`KeyedEmpty.group_forced_empty` for the split, `res_empty_forced` for
resolution).  The carrier is asked for because it is what makes the step a step of the
RELATION that has the bound, not because the emission would otherwise be unsound.  That is
also why the Scala may use a carrier from a wider scope than the current solve without
risking a wrong conclusion (report §A.3).

## Scope

* The adequacy theorems take `SoleFact H z` for the carrier -- the retained fact is `z`'s only
  occurrence.  In the shipped configuration that is automatic: with `-Dermine.splitRow` /
  `-Dermine.resRow` ON, a carrier still sitting in a queue is taken by the Stage 5 branch
  BEFORE this one, so the empty-row branch is reached only with an environment carrier, whose
  partitions `makeEmpty` has deleted.  With the Stage 5 flags off and this one on, the branch
  can fire on a queued `w <- ()`; the emission is still entailed, but the two-step reading
  above does not apply.
* As in Stage 5, the MINT branch needs a model (`KeyedRow.concRow_none_uncarried`), and
  nothing here is about ill-typed input or about `incorporateAll`'s single pass.
-/
import Rowpartition.KeyedEmpty
import Rowpartition.KeyedRowScala

namespace Rowpartition

open NameLoss (denotes_of_conc mk_eq_iff)
open KeyedRow (Carried ConcCarried concCarried_iff MyRowSpec ConcRowSpec bare_erase_iff
  K2RowApp K2SplitStep K2ResStep K2StarStep K2StarLoopStep K2MintApp
  scalaRowSplit scalaRowRes scalaRowSplit_step scalaRowRes_step myRowLookup myRowLookup_spec
  concRowLookup concRowLookup_spec hmeas)

namespace KeyedEmpty

/-! ## 1. The retained carrier -/

/-- **`makeEmpty` deleted every partition that mentions `z`.**  After `makeEmpty z`, the
compiler holds the fact `z <- ()` in the `SubstEnv` and NOTHING else about `z`: both queues
were filtered by `ruleInvolves(z)`.  Read on the state `H` = queues ∪ retained facts, that is
exactly this predicate. -/
def SoleFact (H : System) (z : Var) : Prop := ∀ c ∈ H, Involves z c → c = mk z ∅ (∅ : Row)

theorem SoleFact.lhs_ne {H : System} {z : Var} (h : SoleFact H z) {c : Constraint}
    (hc : c ∈ H) (hne : c ≠ mk z ∅ (∅ : Row)) : c.lhs ≠ z :=
  fun hlhs => hne (h c hc (Or.inl hlhs))

/-- No variable of a right-hand side in `H` is the retained carrier. -/
theorem SoleFact.notMem_vset {H : System} {z : Var} (h : SoleFact H z) {c : Constraint}
    (hc : c ∈ H) : z ∉ vset c := by
  intro hz
  have := h c hc (Or.inr hz)
  rw [this, vset_mk] at hz
  exact absurd hz (Finset.notMem_empty z)

/-! ## 2. The specification of the new lookup -/

/-- **Specification of `findEmptyRow`.**  It is `ConcRowSpec` with the complement pinned to
the EMPTY row (`C \ K = ∅`, i.e. `C = K`), and with the carrier allowed to come from the
retained facts as well as from the queues -- both live in `H`. -/
def EmptyRowSpec (H : System) (K : Row) : Option Row → Option Var → Prop
  | C?, some z => ∃ C, C? = some C ∧ K ⊆ C ∧ C \ K = ∅ ∧ mk z ∅ (∅ : Row) ∈ H
  | C?, none => ∀ C, C? = some C → K ⊆ C → C \ K = ∅ → ∀ z, mk z ∅ (∅ : Row) ∉ H

/-- **A hit is a `ConcRowSpec` hit**, hence a `K2RowApp`: the emptied variable carries the
empty complement. -/
theorem emptyRowSpec_toConcRow {H : System} {K : Row} {C? : Option Row} {z : Var}
    (h : EmptyRowSpec H K C? (some z)) : ConcRowSpec H K C? (some z) := by
  obtain ⟨C, hC?, hsub, hdiff, hz⟩ := h
  exact ⟨C, hC?, hsub, by rw [hdiff]; exact hz⟩

/-- A lookup meeting the specification, with the existential bounded by `H` so the `if` is
decidable -- exactly as `KeyedRow.concRowLookup` is. -/
noncomputable def emptyRowLookup (H : System) (K : Row) : Option Row → Option Var
  | none => none
  | some C =>
    if h : K ⊆ C ∧ C \ K = ∅ ∧ ∃ z ∈ allVars H, mk z ∅ (∅ : Row) ∈ H then
      some h.2.2.choose
    else none

theorem emptyRowLookup_spec (H : System) (K : Row) (C? : Option Row) :
    EmptyRowSpec H K C? (emptyRowLookup H K C?) := by
  cases C? with
  | none => intro C hC; exact absurd hC (by simp)
  | some C =>
    by_cases h : K ⊆ C ∧ C \ K = ∅ ∧ ∃ z ∈ allVars H, mk z ∅ (∅ : Row) ∈ H
    · rw [emptyRowLookup, dif_pos h]
      exact ⟨C, rfl, h.1, h.2.1, h.2.2.choose_spec.2⟩
    · rw [emptyRowLookup, dif_neg h]
      intro C' hC' hsub hdiff z hz
      apply h
      cases hC'
      exact ⟨hsub, hdiff, z, lhs_mem_allVars hz, hz⟩

/-! ## 3. What the two branches emit -/

/-- The PROPAGATION: `x <- ()` for every `x` of the premise's group.  This is
`KeyedEmpty.propPart` applied to the Lean reuse's conclusion (`emptyReuse_compose`). -/
def emptyProp (S : Finset Var) : System := S.image (fun x => mk x ∅ (∅ : Row))

theorem mem_emptyProp {S : Finset Var} {c : Constraint} :
    c ∈ emptyProp S ↔ ∃ x ∈ S, c = mk x ∅ (∅ : Row) := by
  simp only [emptyProp, Finset.mem_image]
  constructor
  · rintro ⟨x, hx, rfl⟩; exact ⟨x, hx, rfl⟩
  · rintro ⟨x, hx, rfl⟩; exact ⟨x, hx, rfl⟩

/-- `splitConcrete`'s fifth branch: the premise stays, the group is forced empty. -/
def splitEmptyResult (G : System) (c : Constraint) : System := G ∪ emptyProp (vset c)

/-- `resolution`'s fourth branch: the reuse's two conclusions with the carrier's row (`∅`)
substituted for the carrier. -/
def resEmptyResult (G : System) (x y : Var) (C D : Row) : System :=
  insert (mk x ∅ (D \ C)) (insert (mk y ∅ (C \ D)) G)

theorem subset_splitEmptyResult (G : System) (c : Constraint) : G ⊆ splitEmptyResult G c :=
  fun _ h => Finset.mem_union_left _ h

theorem subset_resEmptyResult (G : System) (x y : Var) (C D : Row) :
    G ⊆ resEmptyResult G x y C D := fun _ h =>
  Finset.mem_insert_of_mem (Finset.mem_insert_of_mem h)

/-! ## 4. Both emissions are ENTAILED -- with no carrier anywhere -/

theorem sat_empty_mk {rho : Assign} {x : Var} (h : rho x = ∅) : Sat rho (mk x ∅ (∅ : Row)) := by
  rw [sat_mk_iff]
  exact ⟨by simp [h], by simp, by simp⟩

/-- **The split branch does not move the model set.**  `group_forced_empty` is the whole
content: a concrete definition of `c.lhs` whose row is the premise's own concrete part forces
every variable of the premise's group to denote `∅`. -/
theorem splitEmpty_models_iff {rho : Assign} {G : System} {c : Constraint} {K : Row}
    (hconc : mk c.lhs ∅ K ∈ G) (hc : c ∈ G) (hK : c.conc = K) :
    SModels rho (splitEmptyResult G c) ↔ SModels rho G := by
  constructor
  · exact SModels.mono (subset_splitEmptyResult G c)
  · intro hm d hd
    rcases Finset.mem_union.mp hd with h | h
    · exact hm d h
    · obtain ⟨x, hx, rfl⟩ := mem_emptyProp.mp h
      exact sat_empty_mk (group_forced_empty hm hconc hc rfl hK hx)

/-- **The premise and a concrete definition of its left-hand side pin the lone variable.**
`v <- (x, C)` with `v <- ((|F|))` forces `rho x = F \ C`. -/
theorem res_empty_forced {rho : Assign} {G : System} {v x : Var} {C F : Row}
    (hm : SModels rho G) (h1 : mk v {x} C ∈ G) (hF : mk v ∅ F ∈ G) : rho x = F \ C := by
  have hsat := (hm _ h1).eq_biUnion
  rw [lhs_mk, conc_mk, vset_mk, Finset.singleton_biUnion, denotes_of_conc hF hm] at hsat
  have hdis : Disjoint C (rho x) := by
    have := (hm _ h1).disjoint_conc' (c := mk v {x} C) (v := x) (by rw [vset_mk]; simp)
    rwa [conc_mk] at this
  ext l
  constructor
  · intro hl
    refine Finset.mem_sdiff.mpr ⟨?_, ?_⟩
    · rw [hsat]; exact Finset.mem_union_right _ hl
    · exact fun hC => Finset.disjoint_left.mp hdis hC hl
  · intro hl
    obtain ⟨hlF, hlC⟩ := Finset.mem_sdiff.mp hl
    rw [hsat] at hlF
    rcases Finset.mem_union.mp hlF with h | h
    · exact absurd h hlC
    · exact h

/-- When the resolvent row is empty the two premises' rows exhaust `F`. -/
theorem res_empty_F {rho : Assign} {G : System} {v x y : Var} {C D F : Row}
    (hm : SModels rho G) (hp : ResPair G v x y C D) (hF : mk v ∅ F ∈ G)
    (hFCD : F \ (C ∪ D) = ∅) : F = C ∪ D := by
  have hCF : C ⊆ F := by
    have h := (hm _ hp.mem₁).conc_subset_lhs
    rwa [conc_mk, lhs_mk, denotes_of_conc hF hm] at h
  have hDF : D ⊆ F := by
    have h := (hm _ hp.mem₂).conc_subset_lhs
    rwa [conc_mk, lhs_mk, denotes_of_conc hF hm] at h
  exact Finset.Subset.antisymm (Finset.sdiff_eq_empty_iff_subset.mp hFCD)
    (Finset.union_subset hCF hDF)

/-- **The resolution branch does not move the model set** either: with the resolvent row
empty, `rho x = D \ C` and `rho y = C \ D` are forced. -/
theorem resEmpty_models_iff {rho : Assign} {G : System} {v x y : Var} {C D F : Row}
    (hm : SModels rho G) (hp : ResPair G v x y C D) (hF : mk v ∅ F ∈ G)
    (hFCD : F \ (C ∪ D) = ∅) : SModels rho (resEmptyResult G x y C D) := by
  have hFeq : F = C ∪ D := res_empty_F hm hp hF hFCD
  have hx : rho x = D \ C := by
    rw [res_empty_forced hm hp.mem₁ hF, hFeq]
    ext l; simp only [Finset.mem_sdiff, Finset.mem_union]; tauto
  have hy : rho y = C \ D := by
    rw [res_empty_forced hm hp.mem₂ hF, hFeq]
    ext l; simp only [Finset.mem_sdiff, Finset.mem_union]; tauto
  intro d hd
  rcases Finset.mem_insert.mp hd with rfl | hd
  · rw [sat_mk_iff]; exact ⟨by simp [hx], by simp, by simp⟩
  rcases Finset.mem_insert.mp hd with rfl | hd
  · rw [sat_mk_iff]; exact ⟨by simp [hy], by simp, by simp⟩
  · exact hm d hd

/-! ## 5. The composition: the Scala step is the Lean reuse plus its forced `empty` step -/

/-- **The split.**  On a state where the carrier's only occurrence is the retained fact,
`makeEmptyE z` applied to the Lean reuse's conclusion adds exactly the propagation and
removes nothing. -/
theorem emptyReuse_compose {H : System} {z : Var} {S : Finset Var}
    (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H) :
    makeEmptyE z (insert (mk z S ∅) H) = H ∪ emptyProp S := by
  ext c
  rw [mem_makeEmptyE, Finset.mem_union]
  constructor
  · rintro (rfl | hc)
    · exact Or.inl he
    rcases mem_makeEmptyD.mp hc with ⟨hmem, hlhs, -⟩ | ⟨d, hd, hlhs, hvs, rfl⟩ |
      ⟨d, hd, hlhs, hconc, x, hx, rfl⟩
    · rcases Finset.mem_insert.mp hmem with rfl | h
      · exact absurd (lhs_mk z S ∅) hlhs
      · exact Or.inl h
    · rcases Finset.mem_insert.mp hd with rfl | h
      · exact absurd (lhs_mk z S ∅) hlhs
      · exact absurd (hsole.notMem_vset h) (by simpa using hvs)
    · rcases Finset.mem_insert.mp hd with rfl | h
      · rw [vset_mk] at hx
        exact Or.inr (mem_emptyProp.mpr ⟨x, hx, rfl⟩)
      · rw [hsole d h (Or.inl hlhs), vset_mk] at hx
        exact absurd hx (Finset.notMem_empty x)
  · rintro (hc | hc)
    · by_cases hinv : Involves z c
      · exact Or.inl (hsole c hc hinv)
      · refine Or.inr (mem_makeEmptyD.mpr (Or.inl ⟨Finset.mem_insert_of_mem hc, ?_, ?_⟩))
        · exact fun h => hinv (Or.inl h)
        · exact fun h => hinv (Or.inr h)
    · obtain ⟨x, hx, rfl⟩ := mem_emptyProp.mp hc
      exact Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inr
        ⟨mk z S ∅, Finset.mem_insert_self _ _, lhs_mk _ _ _, conc_mk _ _ _, x,
          by rw [vset_mk]; exact hx, rfl⟩)))

/-- **Resolution.**  Same statement for `resReuseResult`: the two conclusions have their
carrier ERASED, which is the Scala's substituted `∅`, and nothing else moves. -/
theorem resEmptyReuse_compose {H : System} {z x y : Var} {C D : Row}
    (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H) (hx : x ≠ z) (hy : y ≠ z) :
    makeEmptyE z (resReuseResult H x y C D z) = resEmptyResult H x y C D := by
  have hxz : (mk x {z} (D \ C)).lhs ≠ z := by rw [lhs_mk]; exact hx
  have hyz : (mk y {z} (C \ D)).lhs ≠ z := by rw [lhs_mk]; exact hy
  ext c
  rw [mem_makeEmptyE, resEmptyResult, Finset.mem_insert, Finset.mem_insert]
  constructor
  · rintro (rfl | hc)
    · exact Or.inr (Or.inr he)
    rcases mem_makeEmptyD.mp hc with ⟨hmem, hlhs, hvs⟩ | ⟨d, hd, hlhs, hvs, rfl⟩ |
      ⟨d, hd, hlhs, hconc, w, hw, rfl⟩
    · simp only [resReuseResult, Finset.mem_insert] at hmem
      rcases hmem with rfl | rfl | h
      · exact absurd (by rw [vset_mk]; simp) hvs
      · exact absurd (by rw [vset_mk]; simp) hvs
      · exact Or.inr (Or.inr h)
    · simp only [resReuseResult, Finset.mem_insert] at hd
      rcases hd with rfl | rfl | h
      · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]; exact Or.inl rfl
      · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]; exact Or.inr (Or.inl rfl)
      · exact absurd (hsole.notMem_vset h) (by simpa using hvs)
    · simp only [resReuseResult, Finset.mem_insert] at hd
      rcases hd with rfl | rfl | h
      · exact absurd hlhs hxz
      · exact absurd hlhs hyz
      · rw [hsole d h (Or.inl hlhs), vset_mk] at hw
        exact absurd hw (Finset.notMem_empty w)
  · have hmemH : ∀ d ∈ H, d ∈ resReuseResult H x y C D z := fun d hd =>
      subset_resReuseResult H x y C D z hd
    rintro (rfl | rfl | hc)
    · refine Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inl ⟨mk x {z} (D \ C), ?_, hxz, ?_, ?_⟩)))
      · simp [resReuseResult]
      · rw [vset_mk]; simp
      · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]
    · refine Or.inr (mem_makeEmptyD.mpr (Or.inr (Or.inl ⟨mk y {z} (C \ D), ?_, hyz, ?_, ?_⟩)))
      · simp [resReuseResult]
      · rw [vset_mk]; simp
      · rw [lhs_mk, vset_mk, conc_mk, Finset.erase_singleton]
    · by_cases hinv : Involves z c
      · exact Or.inl (hsole c hc hinv)
      · refine Or.inr (mem_makeEmptyD.mpr (Or.inl ⟨hmemH c hc, ?_, ?_⟩))
        · exact fun h => hinv (Or.inl h)
        · exact fun h => hinv (Or.inr h)

/-! ## 6. The two branches as steps of the repaired relation -/

theorem run_of_splitStep {H G' : System} (h : K2SplitStep H G') : ∃ n, K3ELoopRun n H G' := by
  by_cases hEq : H = G'
  · subst hEq; exact ⟨0, K3ELoopRun.refl H⟩
  · exact ⟨1, K3ELoopRun.tail (K3ELoopRun.refl H)
      (K3ELoopStep.star (K2StarLoopStep.additive (K2StarStep.split h))) hEq⟩

theorem run_of_resStep {H G' : System} (h : K2ResStep H G') : ∃ n, K3ELoopRun n H G' := by
  by_cases hEq : H = G'
  · subst hEq; exact ⟨0, K3ELoopRun.refl H⟩
  · exact ⟨1, K3ELoopRun.tail (K3ELoopRun.refl H)
      (K3ELoopStep.star (K2StarLoopStep.additive (K2StarStep.res h))) hEq⟩

private theorem vset_ne_of_two_le {c : Constraint} (hcard : 2 ≤ (vset c).card) : vset c ≠ ∅ := by
  intro h; rw [h] at hcard; simp at hcard

/-- **The split branch is TWO steps of `K3ELoopStep`**: the Stage 4 concrete-row reuse at the
carrier of the empty row, then the `makeEmptyE` step that reuse forces.  Their composite adds
exactly what the Scala emits (`emptyReuse_compose`). -/
theorem splitEmpty_two_steps {H : System} {c : Constraint} {z : Var} {C : Row}
    (happ : K2RowApp H c z C) (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H) :
    K3ELoopRun 2 H (splitEmptyResult H c) := by
  have hvs : vset c ≠ ∅ := vset_ne_of_two_le happ.two_le
  have hnotIn : mk z (vset c) ∅ ∉ H := by
    intro hin
    exact happ.unnamed ⟨mk z (vset c) ∅, hin, vset_mk _ _ _, conc_mk _ _ _⟩
  have hself : mk z (vset c) ∅ ∈ kSplitReuseResult H c z := Finset.mem_insert_self _ _
  have hne1 : H ≠ kSplitReuseResult H c z := by
    intro hEq; rw [← hEq] at hself; exact hnotIn hself
  have hcomp : makeEmptyE z (kSplitReuseResult H c z) = splitEmptyResult H c :=
    emptyReuse_compose hsole he
  have hnotIn2 : mk z (vset c) ∅ ∉ splitEmptyResult H c := by
    intro hin
    rcases Finset.mem_union.mp hin with h | h
    · exact hnotIn h
    · obtain ⟨x, -, hx⟩ := mem_emptyProp.mp h
      exact hvs (mk_eq_iff.mp hx).2.1
  have hne2 : makeEmptyE z (kSplitReuseResult H c z) ≠ kSplitReuseResult H c z := by
    rw [hcomp]; intro hEq; rw [hEq] at hnotIn2; exact hnotIn2 hself
  have hmemE : mk z ∅ (∅ : Row) ∈ kSplitReuseResult H c z := Finset.mem_insert_of_mem he
  have hrun : K3ELoopRun 2 H (makeEmptyE z (kSplitReuseResult H c z)) :=
    K3ELoopRun.tail
      (K3ELoopRun.tail (K3ELoopRun.refl H)
        (K3ELoopStep.star (K2StarLoopStep.additive (K2StarStep.split (K2SplitStep.row happ))))
        hne1)
      (K3ELoopStep.empty hmemE hne2) (Ne.symm hne2)
  rwa [hcomp] at hrun

/-- **The resolution branch is TWO steps** as well: `K2ResStep.row` at the carrier of the
empty resolvent row, then its forced `makeEmptyE`, whose erasure turns the reuse's two
conclusions into the bare concrete ones the Scala emits. -/
theorem resEmpty_two_steps {H : System} {v x y z : Var} {C D F : Row}
    (hp : ResPair H v x y C D) (hF : mk v ∅ F ∈ H) (hFCD : F \ (C ∪ D) = ∅)
    (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H) :
    K3ELoopRun 2 H (resEmptyResult H x y C D) := by
  have hx : x ≠ z := by
    intro hEq
    have := hsole.notMem_vset hp.mem₁
    rw [vset_mk] at this
    exact this (by simp [hEq])
  have hy : y ≠ z := by
    intro hEq
    have := hsole.notMem_vset hp.mem₂
    rw [vset_mk] at this
    exact this (by simp [hEq])
  have hcarr : mk z ∅ (F \ (C ∪ D)) ∈ H := by rw [hFCD]; exact he
  have hnotIn : mk x {z} (D \ C) ∉ H := by
    intro hin
    have := hsole.notMem_vset hin
    rw [vset_mk] at this
    exact this (Finset.mem_singleton_self z)
  have hself : mk x {z} (D \ C) ∈ resReuseResult H x y C D z := Finset.mem_insert_self _ _
  have hne1 : H ≠ resReuseResult H x y C D z := by
    intro hEq; rw [← hEq] at hself; exact hnotIn hself
  have hcomp : makeEmptyE z (resReuseResult H x y C D z) = resEmptyResult H x y C D :=
    resEmptyReuse_compose hsole he hx hy
  have hnotIn2 : mk x {z} (D \ C) ∉ resEmptyResult H x y C D := by
    intro hin
    rcases Finset.mem_insert.mp hin with h | h
    · exact absurd (mk_eq_iff.mp h).2.1 (by simp)
    rcases Finset.mem_insert.mp h with h | h
    · exact absurd (mk_eq_iff.mp h).2.1 (by simp)
    · exact hnotIn h
  have hne2 : makeEmptyE z (resReuseResult H x y C D z) ≠ resReuseResult H x y C D z := by
    rw [hcomp]; intro hEq; rw [hEq] at hnotIn2; exact hnotIn2 hself
  have hmemE : mk z ∅ (∅ : Row) ∈ resReuseResult H x y C D z :=
    subset_resReuseResult H x y C D z he
  have hrun : K3ELoopRun 2 H (makeEmptyE z (resReuseResult H x y C D z)) :=
    K3ELoopRun.tail
      (K3ELoopRun.tail (K3ELoopRun.refl H)
        (K3ELoopStep.star (K2StarLoopStep.additive (K2StarStep.res (K2ResStep.row hp hF hcarr))))
        hne1)
      (K3ELoopStep.empty hmemE hne2) (Ne.symm hne2)
  rwa [hcomp] at hrun

/-! ## 7. The rules, branch for branch -/

/-- **`splitConcrete` with the Stage 7 branch**, in the source's order: syntactic reuse,
keyed reuse, concrete-row reuse, EMPTY-ROW reuse, mint. -/
def scalaEmptySplit (G : System) (c : Constraint) (u : Var)
    (rhss resolvent concRow emptyRow : Option Var) : Option System :=
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
        | none =>
          match emptyRow with
          | some _ => some (splitEmptyResult G c)
          | none => some (splitResult G c u)

private theorem esplit_guard {c : Constraint} (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    ¬ (c.conc = ∅ ∨ (vset c).card < 2) := by
  rintro (h | h)
  · exact hne h
  · omega

theorem scalaEmptySplit_eq_none_iff (G : System) (c : Constraint) (u : Var)
    (rhss resolvent concRow emptyRow : Option Var) :
    scalaEmptySplit G c u rhss resolvent concRow emptyRow = none ↔
      (c.conc = ∅ ∨ (vset c).card < 2) := by
  by_cases hg : c.conc = ∅ ∨ (vset c).card < 2
  · simp [scalaEmptySplit, hg]
  · simp only [scalaEmptySplit, if_neg hg]
    cases rhss with
    | some d => simp [hg]
    | none => cases resolvent with
      | some w => simp [hg]
      | none => cases concRow with
        | some w => simp [hg]
        | none => cases emptyRow <;> simp [hg]

theorem scalaEmptySplit_syntactic (G : System) (c : Constraint) (u d : Var)
    (resolvent concRow emptyRow : Option Var) (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaEmptySplit G c u (some d) resolvent concRow emptyRow = some (splitReuseResult G c d) := by
  simp [scalaEmptySplit, if_neg (esplit_guard hne hcard)]

theorem scalaEmptySplit_keyed (G : System) (c : Constraint) (u w : Var)
    (concRow emptyRow : Option Var) (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaEmptySplit G c u none (some w) concRow emptyRow = some (kSplitReuseResult G c w) := by
  simp [scalaEmptySplit, if_neg (esplit_guard hne hcard)]

theorem scalaEmptySplit_row (G : System) (c : Constraint) (u w : Var) (emptyRow : Option Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaEmptySplit G c u none none (some w) emptyRow = some (kSplitReuseResult G c w) := by
  simp [scalaEmptySplit, if_neg (esplit_guard hne hcard)]

/-- Branch 4, the NEW one: the empty-row lookup hit, and the rule emits the PROPAGATION. -/
theorem scalaEmptySplit_empty (G : System) (c : Constraint) (u z : Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaEmptySplit G c u none none none (some z) = some (splitEmptyResult G c) := by
  simp [scalaEmptySplit, if_neg (esplit_guard hne hcard)]

theorem scalaEmptySplit_mint (G : System) (c : Constraint) (u : Var)
    (hne : c.conc ≠ ∅) (hcard : 2 ≤ (vset c).card) :
    scalaEmptySplit G c u none none none none = some (splitResult G c u) := by
  simp [scalaEmptySplit, if_neg (esplit_guard hne hcard)]

/-- **`resolution` with the Stage 7 branch**: reuse, concrete-row reuse, EMPTY-ROW reuse,
mint. -/
def scalaEmptyRes (G : System) (v x y : Var) (C D : Row) (z : Var)
    (resolvent concRow emptyRow : Option Var) : Option System :=
  if C \ D = ∅ ∨ D \ C = ∅ then none
  else
    match resolvent with
    | some w => some (resReuseResult G x y C D w)
    | none =>
      match concRow with
      | some w => some (resReuseResult G x y C D w)
      | none =>
        match emptyRow with
        | some _ => some (resEmptyResult G x y C D)
        | none => some (resResult G v x y C D z)

private theorem eres_guard {C D : Row} (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    ¬ (C \ D = ∅ ∨ D \ C = ∅) := by
  rintro (h | h)
  · exact htops h
  · exact hbots h

theorem scalaEmptyRes_eq_none_iff (G : System) (v x y : Var) (C D : Row) (z : Var)
    (resolvent concRow emptyRow : Option Var) :
    scalaEmptyRes G v x y C D z resolvent concRow emptyRow = none ↔ (C \ D = ∅ ∨ D \ C = ∅) := by
  by_cases hg : C \ D = ∅ ∨ D \ C = ∅
  · simp only [scalaEmptyRes, if_pos hg]; exact iff_of_true trivial hg
  · simp only [scalaEmptyRes, if_neg hg]
    refine ⟨fun h => absurd h ?_, fun h => absurd h hg⟩
    cases resolvent with
    | some w => simp
    | none => cases concRow with
      | some w => simp
      | none => cases emptyRow <;> simp

theorem scalaEmptyRes_reuse (G : System) (v x y : Var) (C D : Row) (z w : Var)
    (concRow emptyRow : Option Var) (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaEmptyRes G v x y C D z (some w) concRow emptyRow
      = some (resReuseResult G x y C D w) := by
  simp only [scalaEmptyRes, if_neg (eres_guard htops hbots)]

theorem scalaEmptyRes_row (G : System) (v x y : Var) (C D : Row) (z w : Var)
    (emptyRow : Option Var) (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaEmptyRes G v x y C D z none (some w) emptyRow
      = some (resReuseResult G x y C D w) := by
  simp only [scalaEmptyRes, if_neg (eres_guard htops hbots)]

/-- Branch 3, the NEW one. -/
theorem scalaEmptyRes_empty (G : System) (v x y : Var) (C D : Row) (z w : Var)
    (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaEmptyRes G v x y C D z none none (some w) = some (resEmptyResult G x y C D) := by
  simp only [scalaEmptyRes, if_neg (eres_guard htops hbots)]

theorem scalaEmptyRes_mint (G : System) (v x y : Var) (C D : Row) (z : Var)
    (htops : C \ D ≠ ∅) (hbots : D \ C ≠ ∅) :
    scalaEmptyRes G v x y C D z none none none = some (resResult G v x y C D z) := by
  simp only [scalaEmptyRes, if_neg (eres_guard htops hbots)]

/-! ## 8. Adequacy -/

/-- **ADEQUACY FOR THE SPLIT.**  Every system the five-branch rule returns is REACHABLE from
the state by a run of `K3ELoopStep` -- one step for the four Stage 5 branches, TWO for the new
one (the reuse and the `makeEmptyE` it forces).  The model is needed only at the mint branch,
`SoleFact` only at the new one. -/
theorem scalaEmptySplit_run {H : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow emptyRow : Option Var} {C? : Option Row} {G' : System}
    {rho : Assign} (hm : SModels rho H) (hmem : c ∈ H) (hfresh : u ∉ allVars H)
    (hsole : ∀ z, emptyRow = some z → SoleFact H z)
    (hr : RhssSpec (H.erase c) (vset c) rhss)
    (hres : ResolventSpec (H.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (H.erase c) c.lhs C?)
    (hcr : ConcRowSpec (H.erase c) c.conc C? concRow)
    (hem : EmptyRowSpec (H.erase c) c.conc C? emptyRow)
    (h : scalaEmptySplit H c u rhss resolvent concRow emptyRow = some G') :
    ∃ n, K3ELoopRun n H G' := by
  by_cases hg : c.conc = ∅ ∨ (vset c).card < 2
  · rw [(scalaEmptySplit_eq_none_iff H c u rhss resolvent concRow emptyRow).mpr hg] at h
    exact absurd h (by simp)
  obtain ⟨hne, hlt⟩ := not_or.mp hg
  have hcard : 2 ≤ (vset c).card := Nat.not_lt.mp hlt
  have hvs : vset c ≠ ∅ := vset_ne_of_two_le hcard
  cases hrhss : rhss with
  | some d =>
    subst hrhss
    rw [scalaEmptySplit_syntactic H c u d resolvent concRow emptyRow hne hcard,
      Option.some.injEq] at h
    subst h
    exact run_of_splitStep (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr
      (KeyedRow.scalaRowSplit_syntactic H c u d resolvent concRow hne hcard))
  | none =>
    subst hrhss
    cases hresolvent : resolvent with
    | some w =>
      subst hresolvent
      rw [scalaEmptySplit_keyed H c u w concRow emptyRow hne hcard, Option.some.injEq] at h
      subst h
      exact run_of_splitStep (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr
        (KeyedRow.scalaRowSplit_keyed H c u w concRow hne hcard))
    | none =>
      subst hresolvent
      cases hconcRow : concRow with
      | some w =>
        subst hconcRow
        rw [scalaEmptySplit_row H c u w emptyRow hne hcard, Option.some.injEq] at h
        subst h
        exact run_of_splitStep (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr
          (KeyedRow.scalaRowSplit_row H c u w hne hcard))
      | none =>
        subst hconcRow
        cases hempty : emptyRow with
        | none =>
          subst hempty
          rw [scalaEmptySplit_mint H c u hne hcard, Option.some.injEq] at h
          subst h
          exact run_of_splitStep (scalaRowSplit_step hm hmem hfresh hr hres hmy hcr
            (KeyedRow.scalaRowSplit_mint H c u hne hcard))
        | some z =>
          subst hempty
          rw [scalaEmptySplit_empty H c u z hne hcard, Option.some.injEq] at h
          subst h
          obtain ⟨C, hC?, hsub, hdiff, hz⟩ := hem
          subst hC?
          have hlhsConc : mk c.lhs ∅ C ∈ H := (bare_erase_iff hvs c.lhs C).mp hmy
          have heH : mk z ∅ (∅ : Row) ∈ H := (bare_erase_iff hvs z ∅).mp hz
          have hunnamed : ¬ Named H (vset c) := by
            have hnn : ¬ Named (H.erase c) (vset c) := hr
            exact fun hn => hnn ((named_erase_iff hne (vset c)).mpr hn)
          have hcarrier : mk z ∅ (C \ c.conc) ∈ H := by rw [hdiff]; exact heH
          exact ⟨2, splitEmpty_two_steps ⟨hmem, hne, hcard, hunnamed, hlhsConc, hcarrier⟩
            (hsole z rfl) heH⟩

/-- **ADEQUACY FOR RESOLUTION**, the same statement. -/
theorem scalaEmptyRes_run {H : System} {v x y : Var} {C D : Row} {z : Var}
    {resolvent concRow emptyRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho H) (hp : ResPair H v x y C D) (hfresh : z ∉ allVars H)
    (hsole : ∀ e, emptyRow = some e → SoleFact H e)
    (hres : ResolventSpec (H.erase (mk v {x} C)) v (C ∪ D) resolvent)
    (hmy : MyRowSpec (H.erase (mk v {x} C)) v C?)
    (hcr : ConcRowSpec (H.erase (mk v {x} C)) (C ∪ D) C? concRow)
    (hem : EmptyRowSpec (H.erase (mk v {x} C)) (C ∪ D) C? emptyRow)
    (h : scalaEmptyRes H v x y C D z resolvent concRow emptyRow = some G') :
    ∃ n, K3ELoopRun n H G' := by
  have hvs : vset (mk v {x} C) ≠ ∅ := by simp
  cases hresolvent : resolvent with
  | some w =>
    subst hresolvent
    rw [scalaEmptyRes_reuse H v x y C D z w concRow emptyRow hp.tops hp.bots,
      Option.some.injEq] at h
    subst h
    exact run_of_resStep (scalaRowRes_step hm hp hfresh hres hmy hcr
      (KeyedRow.scalaRowRes_reuse H v x y C D z w concRow hp.tops hp.bots))
  | none =>
    subst hresolvent
    cases hconcRow : concRow with
    | some w =>
      subst hconcRow
      rw [scalaEmptyRes_row H v x y C D z w emptyRow hp.tops hp.bots, Option.some.injEq] at h
      subst h
      exact run_of_resStep (scalaRowRes_step hm hp hfresh hres hmy hcr
        (KeyedRow.scalaRowRes_row H v x y C D z w hp.tops hp.bots))
    | none =>
      subst hconcRow
      cases hempty : emptyRow with
      | none =>
        subst hempty
        rw [scalaEmptyRes_mint H v x y C D z hp.tops hp.bots, Option.some.injEq] at h
        subst h
        exact run_of_resStep (scalaRowRes_step hm hp hfresh hres hmy hcr
          (KeyedRow.scalaRowRes_mint H v x y C D z hp.tops hp.bots))
      | some e =>
        subst hempty
        rw [scalaEmptyRes_empty H v x y C D z e hp.tops hp.bots, Option.some.injEq] at h
        subst h
        obtain ⟨F, hC?, hsub, hdiff, he⟩ := hem
        subst hC?
        have hFH : mk v ∅ F ∈ H := (bare_erase_iff hvs v F).mp hmy
        have heH : mk e ∅ (∅ : Row) ∈ H := (bare_erase_iff hvs e ∅).mp he
        exact ⟨2, resEmpty_two_steps hp hFH hdiff (hsole e rfl) heH⟩

/-! ## 9. The bound -/

/-- **The Stage 4 bound covers the extended rules.**  Whatever either rule returns, the
vocabulary of the result is bounded by `|allVars H| + hmeas (labelsOf H) rho H` -- the bound
of `KeyedEmpty.mintsBoundedOnSatKeyed3E`, which is Stage 4's verbatim. -/
theorem bounded_of_run {H G' : System} {rho : Assign} (hm : SModels rho H) {n : ℕ}
    (hrun : K3ELoopRun n H G') :
    (allVars G').card ≤ (allVars H).card + hmeas (labelsOf H) rho H := by
  obtain ⟨rho', -, hb⟩ := hrun.invariant (L := labelsOf H) rho hm (labelsOf_concSub H)
  omega

theorem scalaEmptySplit_bounded {H : System} {c : Constraint} {u : Var}
    {rhss resolvent concRow emptyRow : Option Var} {C? : Option Row} {G' : System}
    {rho : Assign} (hm : SModels rho H) (hmem : c ∈ H) (hfresh : u ∉ allVars H)
    (hsole : ∀ z, emptyRow = some z → SoleFact H z)
    (hr : RhssSpec (H.erase c) (vset c) rhss)
    (hres : ResolventSpec (H.erase c) c.lhs c.conc resolvent)
    (hmy : MyRowSpec (H.erase c) c.lhs C?)
    (hcr : ConcRowSpec (H.erase c) c.conc C? concRow)
    (hem : EmptyRowSpec (H.erase c) c.conc C? emptyRow)
    (h : scalaEmptySplit H c u rhss resolvent concRow emptyRow = some G') :
    (allVars G').card ≤ (allVars H).card + hmeas (labelsOf H) rho H := by
  obtain ⟨n, hrun⟩ := scalaEmptySplit_run hm hmem hfresh hsole hr hres hmy hcr hem h
  exact bounded_of_run hm hrun

theorem scalaEmptyRes_bounded {H : System} {v x y : Var} {C D : Row} {z : Var}
    {resolvent concRow emptyRow : Option Var} {C? : Option Row} {G' : System} {rho : Assign}
    (hm : SModels rho H) (hp : ResPair H v x y C D) (hfresh : z ∉ allVars H)
    (hsole : ∀ e, emptyRow = some e → SoleFact H e)
    (hres : ResolventSpec (H.erase (mk v {x} C)) v (C ∪ D) resolvent)
    (hmy : MyRowSpec (H.erase (mk v {x} C)) v C?)
    (hcr : ConcRowSpec (H.erase (mk v {x} C)) (C ∪ D) C? concRow)
    (hem : EmptyRowSpec (H.erase (mk v {x} C)) (C ∪ D) C? emptyRow)
    (h : scalaEmptyRes H v x y C D z resolvent concRow emptyRow = some G') :
    (allVars G').card ≤ (allVars H).card + hmeas (labelsOf H) rho H := by
  obtain ⟨n, hrun⟩ := scalaEmptyRes_run hm hp hfresh hsole hres hmy hcr hem h
  exact bounded_of_run hm hrun

/-! ## 10. The closed lookups -/

/-- `splitConcrete` with all five lookups resolved. -/
noncomputable def scalaEmptySplitOf (H : System) (c : Constraint) (u : Var) : Option System :=
  scalaEmptySplit H c u (rhssLookup (H.erase c) (vset c))
    (resolventLookup (H.erase c) c.lhs c.conc)
    (concRowLookup (H.erase c) c.conc (myRowLookup (H.erase c) c.lhs))
    (emptyRowLookup (H.erase c) c.conc (myRowLookup (H.erase c) c.lhs))

theorem scalaEmptySplitOf_run {H : System} {c : Constraint} {u : Var} {G' : System}
    {rho : Assign} (hm : SModels rho H) (hmem : c ∈ H) (hfresh : u ∉ allVars H)
    (hsole : ∀ z, emptyRowLookup (H.erase c) c.conc (myRowLookup (H.erase c) c.lhs) = some z →
      SoleFact H z)
    (h : scalaEmptySplitOf H c u = some G') : ∃ n, K3ELoopRun n H G' :=
  scalaEmptySplit_run hm hmem hfresh hsole (rhssLookup_spec _ _) (resolventLookup_spec _ _ _)
    (myRowLookup_spec _ _) (concRowLookup_spec _ _ _) (emptyRowLookup_spec _ _ _) h

/-- `resolution` with all four lookups resolved. -/
noncomputable def scalaEmptyResOf (H : System) (v x y : Var) (C D : Row) (z : Var) :
    Option System :=
  scalaEmptyRes H v x y C D z (resolventLookup (H.erase (mk v {x} C)) v (C ∪ D))
    (concRowLookup (H.erase (mk v {x} C)) (C ∪ D) (myRowLookup (H.erase (mk v {x} C)) v))
    (emptyRowLookup (H.erase (mk v {x} C)) (C ∪ D) (myRowLookup (H.erase (mk v {x} C)) v))

theorem scalaEmptyResOf_run {H : System} {v x y : Var} {C D : Row} {z : Var} {G' : System}
    {rho : Assign} (hm : SModels rho H) (hp : ResPair H v x y C D) (hfresh : z ∉ allVars H)
    (hsole : ∀ e, emptyRowLookup (H.erase (mk v {x} C)) (C ∪ D)
        (myRowLookup (H.erase (mk v {x} C)) v) = some e → SoleFact H e)
    (h : scalaEmptyResOf H v x y C D z = some G') : ∃ n, K3ELoopRun n H G' :=
  scalaEmptyRes_run hm hp hfresh hsole (resolventLookup_spec _ _ _) (myRowLookup_spec _ _)
    (concRowLookup_spec _ _ _) (emptyRowLookup_spec _ _ _) h

end KeyedEmpty
end Rowpartition
