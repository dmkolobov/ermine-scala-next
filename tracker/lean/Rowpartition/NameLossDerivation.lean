/-
# NameLossDerivation -- the fold-first derivation of `t <- ((|c, d|))`

`NameLoss.lean` isolates the race inside `Constraints.incorporateAll`: at the state `Grace`
the common-subexpression fold of `t <- (x, y, z)` against the minted name `u <- (x, y)`
competes with the concretisation of `u`.  Concretising first deletes the name, and the fact
`t <- ((|c|), z)` is never derived (`orderB_lacks_fact`; `NameLossClosed.lean` shows the
concretise-first system is closed).  This file records the OTHER order -- the derivation the
Scala solver actually performs in the pinning run -- as an explicit chain of the solver's
step relation `SatStep` (`Saturate.lean`), from `Grace` to a system containing the goal
`t <- ((|c, d|))`.

The eleven steps, each adding one constraint (`resolution` and `splitConcrete` add three
and two):

     1. fold      `t <- (x, y, z)` against `u <- (x, y)`         ==> `t <- (z, u)`
     2. subst     `u := (|c|)` into it                            ==> `t <- ((|c|), z)`
     3. fold      `t <- (x, y, z)` against `D <- (x, z)`         ==> `t <- (y, D)`
     4. subst     `D := (|d|)` into it                            ==> `t <- ((|d|), y)`
     5. resolve   `t <- ((|c|), z)` with `t <- ((|d|), y)`       ==> `t <- ((|c, d|), v)`,
                                                                    `z <- ((|d|), v)`,
                                                                    `y <- ((|c|), v)`
     6. subst     `z := ((|d|), v)` into `D <- (x, z)`            ==> `D <- ((|d|), x, v)`
     7. split     the pair `x, v` gets a name                     ==> `s <- (x, v)`,
                                                                    `D <- ((|d|), s)`
     8. cancel    the mention against `D <- ((|d|))`             ==> `s <- ()`
     9. empty     `s <- ()` and `s <- (x, v)`                     ==> `x <- ()`
    10. empty     ... and                                         ==> `v <- ()`
    11. erase     `v` leaves `t <- ((|c, d|), v)`                 ==> `t <- ((|c, d|))`

Steps 1-8 are cut-calculus steps (`CutRuleStep`: the non-generative rules, the mint of
`splitConcrete`, and `resolution`); steps 9-11 are `makeEmpty`, which the cut calculus does
not contain and `SatStep` does.  The two mints, `v` (resolution) and `s` (split), are the
only fresh names the derivation needs.

## Contents

* §1  The two minted variables and the twelve derived constraints.
* §2  The twelve systems `S1`..`S11` (`S0` is `Grace`), each a literal `insert`.
* §3  One theorem per step: the rule's premises, the identification of its result with the
      named constraint, and `SatStep Sᵢ Sᵢ₊₁`.
* §4  The chain: `SatSteps 11 Grace S11` with `tGoal ∈ S11` (`orderA_steps`,
      `orderA_derives_goal`); from the input, thirteen steps (`input_derives_goal`); and
      the semantic fact it pairs with, `SEntails G₀ tGoal` (`derived_entailed`).
-/
import Rowpartition.NameLoss

namespace Rowpartition
namespace NameLoss

/-! ## 1. The minted variables and the derived constraints -/

/-- The name `resolution` mints for the common remainder of `t <- ((|c|), z)` and
`t <- ((|d|), y)`. -/
abbrev v : Var := 7
/-- The name `splitConcrete` mints for the pair `x ++ v`. -/
abbrev s : Var := 8

/-- `t <- ((|c, d|), v)`: the resolvent of `t <- ((|c|), z)` and `t <- ((|d|), y)`. -/
def tRes : Constraint := mk t {v} {fc, fd}
/-- `z <- ((|d|), v)`: the first remainder resolution emits. -/
def zRes : Constraint := mk z {v} {fd}
/-- `y <- ((|c|), v)`: the second. -/
def yRes : Constraint := mk y {v} {fc}
/-- `D <- ((|d|), x, v)`: `D <- (x, z)` with `z := ((|d|), v)`. -/
def dSub : Constraint := mk D {x, v} {fd}
/-- `s <- (x, v)`: the name `splitConcrete` mints for the pair. -/
def sName : Constraint := mk s {x, v} ∅
/-- `D <- ((|d|), s)`: the mention that comes with it. -/
def dS : Constraint := mk D {s} {fd}
/-- `s <- ()`: cancellation of the mention against `D <- ((|d|))`. -/
def sEmpty : Constraint := mk s ∅ ∅
/-- `x <- ()`, in the raw list shape `makeEmpty` emits. -/
def xEmpty : Constraint := ⟨x, [], ∅⟩
/-- `v <- ()`, likewise. -/
def vEmpty : Constraint := ⟨v, [], ∅⟩

/-! ## 2. The systems -/

/-- After step 1. -/
def S1 : System := insert tReuse Grace
/-- After step 2. -/
def S2 : System := insert tFact S1
/-- After step 3. -/
def S3 : System := insert tFold S2
/-- After step 4. -/
def S4 : System := insert tD S3
/-- After step 5. -/
def S5 : System := insert tRes (insert zRes (insert yRes S4))
/-- After step 6. -/
def S6 : System := insert dSub S5
/-- After step 7. -/
def S7 : System := insert sName (insert dS S6)
/-- After step 8. -/
def S8 : System := insert sEmpty S7
/-- After step 9. -/
def S9 : System := insert xEmpty S8
/-- After step 10. -/
def S10 : System := insert vEmpty S9
/-- After step 11: the goal is in. -/
def S11 : System := insert tGoal S10

/-- `NameLoss.nl_decide` with this file's constraints and systems added to the simp set:
unfold everything down to `mk`-shaped constraints over literal finsets, split `mk = mk`
into component equations, and let `decide` settle the residual closed propositions. -/
macro "nld_decide" : tactic => `(tactic|
  ((try simp [t, x, y, z, R, D, u, v, s, fk, fc, fd, G₀, Grace, rConc, rDef, dConc, dDef,
      tDef, uName, rSplit, uConc, tReuse, tFact, tGoal, tFold, tD, tRes, zRes, yRes, dSub,
      sName, dS, sEmpty, xEmpty, vEmpty, S1, S2, S3, S4, S5, S6, S7, S8, reduce, shared,
      Named, Names, allVars, mk_eq_iff, vset_mk, conc_mk, lhs_mk, Finset.subset_iff])
   <;> decide))

/-- Membership of a named constraint in one of the literal systems: unfold the `insert`
chain and find the reflexive disjunct. -/
macro "nlc_mem" : tactic => `(tactic|
  simp [S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, Grace, G₀])

/-! ## 3. The steps -/

/-- **Step 1** -- the fold at `Grace` (`NameLoss.fold_step`, `NameLoss.fold_eq`). -/
theorem step1 : SatStep Grace S1 := by
  unfold S1
  rw [← fold_eq]
  exact SatStep.cutRule (CutRuleStep.nongen (NonGenStep.cse fold_step))

/-- Step 2's premises: `u <- ((|c|))` is substituted into `t <- (z, u)`. -/
theorem subst2_app : SubstApp S1 tReuse uConc :=
  ⟨by nlc_mem, by nlc_mem, by nld_decide⟩

theorem subst2_eq : substResult S1 tReuse uConc = S2 := by
  rw [substResult, subst_eq]; rfl

/-- **Step 2** -- `t <- ((|c|), z)`, the fact (`NameLoss.subst_eq`). -/
theorem step2 : SatStep S1 S2 := by
  rw [← subst2_eq]
  exact SatStep.cutRule (CutRuleStep.nongen (NonGenStep.subst (SubstStep.intro subst2_app)))

/-- Step 3's premises: `t <- (x, y, z)` shares `x ++ z` with `D <- (x, z)`, which is the
bare name of that pair. -/
theorem fold3_app : CsePair S2 dDef tDef :=
  ⟨by nlc_mem, by nlc_mem, by nld_decide, by nld_decide⟩

theorem fold3_step : CutStep S2 (foldResult S2 dDef tDef) :=
  CutStep.fold fold3_app (by nld_decide) rfl

theorem reduce3_eq : reduce tDef (shared dDef tDef) dDef.lhs = tFold := by nld_decide

theorem fold3_eq : foldResult S2 dDef tDef = S3 := by
  rw [foldResult, reduce3_eq]; rfl

/-- **Step 3** -- `t <- (y, D)`. -/
theorem step3 : SatStep S2 S3 := by
  rw [← fold3_eq]
  exact SatStep.cutRule (CutRuleStep.nongen (NonGenStep.cse fold3_step))

/-- Step 4's premises: `D <- ((|d|))` is substituted into `t <- (y, D)`. -/
theorem subst4_app : SubstApp S3 tFold dConc :=
  ⟨by nlc_mem, by nlc_mem, by nld_decide⟩

theorem subst4_eq' :
    mk tFold.lhs ((vset tFold).erase dConc.lhs ∪ vset dConc) (tFold.conc ∪ dConc.conc) = tD := by
  nld_decide

theorem subst4_eq : substResult S3 tFold dConc = S4 := by
  rw [substResult, subst4_eq']; rfl

/-- **Step 4** -- `t <- ((|d|), y)`. -/
theorem step4 : SatStep S3 S4 := by
  rw [← subst4_eq]
  exact SatStep.cutRule (CutRuleStep.nongen (NonGenStep.subst (SubstStep.intro subst4_app)))

theorem tFact_mem_S4 : tFact ∈ S4 := by nlc_mem
theorem tD_mem_S4 : tD ∈ S4 := by nlc_mem

/-- Step 5's premises: `t <- ((|c|), z)` and `t <- ((|d|), y)` partition the same variable
with one abstract part each, their concrete parts differ in both directions, and `v` is
fresh (the system's variables are `0`..`6`). -/
theorem res5_app : ResApp S4 t z y {fc} {fd} v :=
  ⟨tFact_mem_S4, tD_mem_S4, by nld_decide, by nld_decide, by nld_decide⟩

theorem res5_eq_t : mk t {v} ({fc} ∪ {fd}) = tRes := by nld_decide
theorem res5_eq_z : mk z {v} ({fd} \ {fc}) = zRes := by nld_decide
theorem res5_eq_y : mk y {v} ({fc} \ {fd}) = yRes := by nld_decide

theorem res5_eq : resResult S4 t z y {fc} {fd} v = S5 := by
  rw [resResult, res5_eq_t, res5_eq_z, res5_eq_y]; rfl

/-- **Step 5** -- resolution: `t <- ((|c, d|), v)`, `z <- ((|d|), v)`, `y <- ((|c|), v)`. -/
theorem step5 : SatStep S4 S5 := by
  rw [← res5_eq]
  exact SatStep.cutRule (CutRuleStep.res (ResStep.intro res5_app))

/-- Step 6's premises: `z <- ((|d|), v)` is substituted into `D <- (x, z)`. -/
theorem subst6_app : SubstApp S5 dDef zRes :=
  ⟨by nlc_mem, by nlc_mem, by nld_decide⟩

theorem subst6_eq' :
    mk dDef.lhs ((vset dDef).erase zRes.lhs ∪ vset zRes) (dDef.conc ∪ zRes.conc) = dSub := by
  nld_decide

theorem subst6_eq : substResult S5 dDef zRes = S6 := by
  rw [substResult, subst6_eq']; rfl

/-- **Step 6** -- `D <- ((|d|), x, v)`. -/
theorem step6 : SatStep S5 S6 := by
  rw [← subst6_eq]
  exact SatStep.cutRule (CutRuleStep.nongen (NonGenStep.subst (SubstStep.intro subst6_app)))

/-- Step 7's premises: `D <- ((|d|), x, v)` has a concrete part and two abstract parts,
nothing in the system names `x ++ v`, and `s` is fresh (the variables are `0`..`7`). -/
theorem split7_app : SplitApp S6 dSub s :=
  ⟨by nlc_mem, by nld_decide, by nld_decide, by nld_decide, by nld_decide⟩

theorem split7_eq : splitResult S6 dSub s = S7 := by
  simp only [splitResult, S7, sName, dS, dSub, vset_mk, lhs_mk, conc_mk]

/-- **Step 7** -- the mint: `s <- (x, v)` and `D <- ((|d|), s)`. -/
theorem step7 : SatStep S6 S7 := by
  rw [← split7_eq]
  exact SatStep.cutRule (CutRuleStep.mint (SplitStep.intro split7_app))

/-- Step 8's premises: `D <- ((|d|), s)` against `D <- ((|d|))` -- same variable, the
concrete part contained, exactly one variable left over. -/
theorem cancel8_app : CancelApp S7 dS dConc s :=
  ⟨by nlc_mem, by nlc_mem, rfl, by nld_decide, by nld_decide⟩

theorem cancel8_eq' : mk s (vset dConc \ vset dS) (dConc.conc \ dS.conc) = sEmpty := by
  nld_decide

theorem cancel8_eq : cancelResult S7 dS dConc s = S8 := by
  rw [cancelResult, cancel8_eq']; rfl

/-- **Step 8** -- `s <- ()`. -/
theorem step8 : SatStep S7 S8 := by
  rw [← cancel8_eq]
  exact SatStep.cutRule (CutRuleStep.nongen (NonGenStep.cancel (CancelStep.intro cancel8_app)))

/-- The cancellation result in the raw list shape `makeEmpty` reads: `slist ∅ = []`. -/
theorem sEmpty_raw : (⟨s, [], ∅⟩ : Constraint) = sEmpty := by simp [sEmpty, mk, slist]

theorem sEmpty_raw_mem_S8 : (⟨s, [], ∅⟩ : Constraint) ∈ S8 := by
  rw [sEmpty_raw]; exact Finset.mem_insert_self _ _

theorem sName_mem_S8 : sName ∈ S8 := by nlc_mem

/-- `x` is a part of the name `s <- (x, v)`. -/
theorem x_mem_sName : x ∈ sName.vars := by simp [sName, mk]
/-- ... and so is `v`. -/
theorem v_mem_sName : v ∈ sName.vars := by simp [sName, mk]

/-- **Step 9** -- `makeEmpty`, propagation: `s <- ()` and `s <- (x, v)` make `x` empty. -/
theorem step9 : SatStep S8 S9 := by
  unfold S9 xEmpty
  exact SatStep.empty sEmpty_raw_mem_S8 sName_mem_S8 rfl x_mem_sName

theorem sEmpty_raw_mem_S9 : (⟨s, [], ∅⟩ : Constraint) ∈ S9 :=
  Finset.mem_insert_of_mem sEmpty_raw_mem_S8

theorem sName_mem_S9 : sName ∈ S9 := Finset.mem_insert_of_mem sName_mem_S8

/-- **Step 10** -- `makeEmpty`, propagation: ... and `v` empty. -/
theorem step10 : SatStep S9 S10 := by
  unfold S10 vEmpty
  exact SatStep.empty sEmpty_raw_mem_S9 sName_mem_S9 rfl v_mem_sName

theorem vEmpty_raw_mem_S10 : (⟨v, [], ∅⟩ : Constraint) ∈ S10 := Finset.mem_insert_self _ _

theorem tRes_mem_S10 : tRes ∈ S10 := by nlc_mem

/-- `v` is the one abstract part of `t <- ((|c, d|), v)`. -/
theorem v_mem_tRes : v ∈ tRes.vars := by simp [tRes, mk]

/-- Erasing `v` from `t <- ((|c, d|), v)` is the goal: `slist {v} = [v]`, `[v].erase v = []`,
`slist ∅ = []`. -/
theorem erase11_eq : (⟨tRes.lhs, tRes.vars.erase v, tRes.conc⟩ : Constraint) = tGoal := by
  simp [tRes, tGoal, mk, slist]

/-- **Step 11** -- `makeEmpty`, erasure: the empty `v` leaves `t <- ((|c, d|), v)`, and `t`
is pinned. -/
theorem step11 : SatStep S10 S11 := by
  unfold S11
  rw [← erase11_eq]
  exact SatStep.eraseEmpty vEmpty_raw_mem_S10 tRes_mem_S10 v_mem_tRes

/-! ## 4. The chain -/

/-- **The fold-first derivation**: eleven solver steps from the race state reach `S11`. -/
theorem orderA_steps : SatSteps 11 Grace S11 :=
  SatSteps.tail (SatSteps.tail (SatSteps.tail (SatSteps.tail (SatSteps.tail (SatSteps.tail
    (SatSteps.tail (SatSteps.tail (SatSteps.tail (SatSteps.tail (SatSteps.tail
      (SatSteps.refl _) step1) step2) step3) step4) step5) step6) step7) step8) step9)
        step10) step11

theorem tGoal_mem_S11 : tGoal ∈ S11 := Finset.mem_insert_self _ _

/-- **Order A derives the goal**: from `Grace`, the solver's step relation reaches a system
containing `t <- ((|c, d|))`.  Contrast `NameLoss.orderB_lacks_fact`: in the other order
the fact of step 2 is never available, and the derivation does not exist. -/
theorem orderA_derives_goal : ∃ n G', SatSteps n Grace G' ∧ tGoal ∈ G' :=
  ⟨11, S11, orderA_steps, tGoal_mem_S11⟩

/-- A cut-calculus chain is a solver chain. -/
theorem cutRuleSteps_satSteps {n : ℕ} {G G' : System} (h : CutRuleSteps n G G') :
    SatSteps n G G' := by
  induction h with
  | refl G => exact SatSteps.refl G
  | tail _ hstep ih => exact SatSteps.tail ih (SatStep.cutRule hstep)

/-- Solver chains compose. -/
theorem satSteps_trans {m n : ℕ} {G G' G'' : System} (h₁ : SatSteps m G G')
    (h₂ : SatSteps n G' G'') : SatSteps (m + n) G G'' := by
  induction h₂ with
  | refl _ => exact h₁
  | tail _ hstep ih => exact SatSteps.tail (ih h₁) hstep

/-- **From the input**: `NameLoss.grace_reached` (two cut steps to `Grace`) followed by the
eleven above -- thirteen solver steps from the five input partitions to the goal. -/
theorem input_derives_goal : SatSteps 13 G₀ S11 ∧ tGoal ∈ S11 :=
  ⟨satSteps_trans (cutRuleSteps_satSteps grace_reached) orderA_steps, tGoal_mem_S11⟩

/-- **The derivation is sound** -- the semantic fact it pairs with, `NameLoss.G₀_entails_goal`:
`t = (|c, d|)` holds in every model of the input.  (Every `SatStep` preserves
satisfiability, `Saturate.SatSteps.sat_mono`; the goal it reaches here is moreover entailed.) -/
theorem derived_entailed : SEntails G₀ tGoal := G₀_entails_goal

end NameLoss
end Rowpartition
