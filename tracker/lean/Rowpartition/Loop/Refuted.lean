/-
# L5 round 4 (R4.1): the residual `QStepDichotomy` is FALSE, at an INITIAL state

Round 3 (`Loop/Residual.lean`) nominated one `Prop` as everything that stands between the
model and a loop-level bound, and proved it sufficient for the bound.  The round-3 review's
F-5 asked the obvious question first: `QStepDichotomy` quantifies over every `Wf` state, and
`Wf` is only `QOk` on the two queues plus `LblCoh`, so the statement is much stronger than
the induction that consumes it needs -- is it even true?

It is not.  This module exhibits ONE state and ONE step that refute it, and the state is not
a pathological `Wf` state: it is an INITIAL state -- `proc` empty, `env` empty -- of a
three-constraint SATISFIABLE input, i.e. exactly the shape `Seed.solve` builds
(`Hygiene.queueHygiene_initial`).  So relativising the residual to reachable states, or
adding round 3's invariants (`QueueHygiene`, `NoSelfUnif`, `NoInfRow`, `SupOk`, `SupFresh`),
cannot rescue it: all of them hold at the witness, and the witness is reached in zero steps.

The mechanism is the one `Residual.redirect_breaks_carried` describes, fired by the loop
itself rather than by a hypothetical pair of successors:

```
  v0 <- ()            v2 <- (v0, (|l0|))          v1 <- ((|l0|))
```

`v0` is the deepest variable, so the `empty` branch runs first.  `makeEmpty v0` erases `v0`
from `v2 <- (v0, (|l0|))`, leaving the bare concrete definition `v2 <- ((|l0|))`, and
re-inserts it with `Q.++!` -- into a queue that already holds `v1 <- ((|l0|))`.  The
`CommonPartition` redirect fires and inserts `v1 <- (v2)` INSTEAD.  The key `(v2, {l0})`,
carried before the step by the lone witness `v2 <- (v0, (|l0|))`, is carried by nothing
after it, and `v2` is still in the queue-visible vocabulary.  So neither disjunct holds: the
first fails because `K2StarStep` is additive and the premise is gone, the second because
`CarrPresOn` fails at `(v2, {l0})`.

§5 goes further: at this step the ROUND-3 POTENTIAL ITSELF strictly increases, for EVERY
model of the successor (`qstep_pot_increases`).  So the failure is not a slack in how the
dichotomy is phrased -- no repair of it that keeps `Pot` as the measure can be true.

§6 states the relativisation the review asked for (`QStepDichotomy'`, over states REACHABLE
from an initial one), re-proves the round-3 chain from it (`run_qsys_bound'`), and then
refutes it too by the same witness.  The relativisation is a sound proof route; it is just
as false.
-/
import Rowpartition.Loop.Residual

set_option maxRecDepth 4000

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

/-! ## 1. The witness: an initial state of a satisfiable three-constraint input -/

/-- The single label of the witness, `Repro.l0` in the harness's numbering. -/
def wLbl : Lbl := { n := 0, glob := true, mod := "Repro", str := "l0", con := 1 }

/-- `v0 <- ()`. -/
def wV : LPart := ⟨0, ⟨⟨false, []⟩, ⟨false, []⟩⟩, none⟩

/-- `v1 <- ((|l0|))` -- the partition the redirect will match. -/
def wA : LPart := ⟨1, ⟨⟨false, []⟩, ⟨false, [wLbl]⟩⟩, none⟩

/-- `v2 <- (v0, (|l0|))` -- the lone witness that carries the key `(v2, {l0})`. -/
def wW : LPart := ⟨2, ⟨⟨false, [0]⟩, ⟨false, [wLbl]⟩⟩, none⟩

/-- `v1 <- (v2)`, what `Q.++!`'s `CommonPartition` redirect inserts in place of
`v2 <- ((|l0|))`. -/
def wR : LPart := ⟨1, ⟨⟨false, [2]⟩, ⟨false, []⟩⟩, some .commonPartition⟩

/-- No variable is named and none is a skolem. -/
def wNames : Names := { named := [], tys := [], supplyLo := 100 }

/-- A coherent supply well clear of `{0, 1, 2}`. -/
def wSup : Sup := { lo := 100, hi := 100000, blk := 200000, bsz := 1024, drawn := 0 }

/-- **The witness state.**  `proc` and `env` are EMPTY: this is the shape `Seed.solve`
builds, the one `queueHygiene_initial` is stated for. -/
def wS : State :=
  { incm := PQueue.ofList [wW, wV, wA], proc := PQueue.empty, env := {},
    su := wSup, trace := [], flags := {}, names := wNames, site := "t0", su0 := 100 }

/-- Its successor, named through `step` itself so that no reduction is assumed. -/
def wS' : State :=
  match step wS with
  | .continue t => t
  | .done t => t
  | .died _ t => t

/-- The model: `rho v0 = {}`, `rho v1 = rho v2 = {l0}`. -/
def wRho : Assign := fun v => if v = 0 then ∅ else {0}

/-! ## 2. The step, and the two queue-visible systems -/

/-- **The witness takes a `continue` step.** -/
theorem wS_step : step wS = .continue wS' := rfl

theorem wS_parts : wS.parts = [wV, wW, wA] := rfl
theorem wS'_parts : wS'.parts = [wR, wA] := rfl
theorem wS_env : wS.env.binds = [] := rfl
theorem wS'_env : wS'.env.binds = [(0, EnvVal.emptyRow)] := rfl
theorem wS_proc : wS.proc = PQueue.empty := rfl

theorem wV_toConstraint : wV.toConstraint = mk 0 ∅ (∅ : Row) := by
  simp [LPart.toConstraint, wV]
theorem wA_toConstraint : wA.toConstraint = mk 1 ∅ ({0} : Row) := by
  simp [LPart.toConstraint, wA, wLbl]
theorem wW_toConstraint : wW.toConstraint = mk 2 {0} ({0} : Row) := by
  simp [LPart.toConstraint, wW, wLbl]
theorem wR_toConstraint : wR.toConstraint = mk 1 {2} (∅ : Row) := by
  simp [LPart.toConstraint, wR]

/-- **The queue-visible system before the step.** -/
theorem qsys_wS :
    qsys wS = ({mk 0 ∅ (∅ : Row), mk 1 ∅ ({0} : Row), mk 2 {0} ({0} : Row)} : System) := by
  have h : qsys wS
      = ({mk 0 ∅ (∅ : Row), mk 2 {0} ({0} : Row), mk 1 ∅ ({0} : Row)} : System) := by
    simp [qsys, wS_parts, wS_env, envEmptySys, wV_toConstraint, wA_toConstraint,
      wW_toConstraint]
  rw [h]
  ext c
  simp only [Finset.mem_insert, Finset.mem_singleton]
  tauto

/-- **... and after it.**  `v2`'s definition is gone -- the redirect replaced it by
`v1 <- (v2)` -- and `v0 <- ()` is now an environment fact. -/
theorem qsys_wS' :
    qsys wS' = ({mk 1 ∅ ({0} : Row), mk 1 {2} (∅ : Row), mk 0 ∅ (∅ : Row)} : System) := by
  have h : qsys wS'
      = ({mk 1 {2} (∅ : Row), mk 1 ∅ ({0} : Row), mk 0 ∅ (∅ : Row)} : System) := by
    simp [qsys, wS'_parts, wS'_env, envEmptySys, wR_toConstraint, wA_toConstraint]
  rw [h]
  ext c
  simp only [Finset.mem_insert, Finset.mem_singleton]
  tauto

/-- With an empty environment the two systems coincide. -/
theorem sys_wS : sys wS = qsys wS := by
  simp [sys, qsys, Env.sys, envEmptySys, wS_env]

/-! ## 3. The witness is well formed, satisfiable, and initial -/

theorem wS_wf : Wf wS := by
  refine wf_of_nodup ?_ ?_ ?_
  · intro p hp
    have he : wS.incm.elems = [wV, wW, wA] := rfl
    rw [he] at hp
    rcases List.mem_cons.mp hp with rfl | hp1
    · exact ⟨by simp [wV, SSet.Nodup], by simp [wV, SSet.Nodup]⟩
    rcases List.mem_cons.mp hp1 with rfl | hp2
    · exact ⟨by simp [wW, SSet.Nodup], by simp [wW, SSet.Nodup]⟩
    rcases List.mem_cons.mp hp2 with rfl | hp3
    · exact ⟨by simp [wA, SSet.Nodup], by simp [wA, SSet.Nodup]⟩
    · simp at hp3
  · intro p hp
    have he : wS.proc.elems = [] := rfl
    rw [he] at hp
    simp at hp
  · intro x hx y hy _
    have hl : wS.labels = [wLbl, wLbl] := rfl
    rw [hl] at hx hy
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hx hy
    rcases hx with rfl | rfl <;> rcases hy with rfl | rfl <;> rfl

theorem wS_models : SModels wRho (qsys wS) := by
  rw [qsys_wS]
  intro c hc
  simp only [Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl
  · rw [sat_mk_iff]; exact ⟨by simp [wRho], by simp, by simp⟩
  · rw [sat_mk_iff]; exact ⟨by simp [wRho], by simp, by simp⟩
  · rw [sat_mk_iff]
    refine ⟨by simp [wRho], ?_, ?_⟩
    · intro v hv
      simp only [Finset.mem_singleton] at hv
      subst hv
      simp [wRho]
    · intro v hv w hw hvw
      simp only [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw

theorem wS_sat : SSat (sys wS) := by rw [sys_wS]; exact ⟨wRho, wS_models⟩

theorem wS_concSub {L : Finset Label} (hL : (0 : Label) ∈ L) : ConcSub L (qsys wS) := by
  rw [qsys_wS]
  intro c hc
  simp only [Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl
  · exact Finset.empty_subset _
  · exact Finset.singleton_subset_iff.mpr hL
  · exact Finset.singleton_subset_iff.mpr hL

/-- **Every invariant round 3 supplies holds at the witness**, because it is an initial
state: the environment is empty, so nothing is bound; `proc` is empty, so no processed
partition is a self-unification or an infinite row; and the supply is coherent and clear of
the vocabulary. -/
theorem wS_queueHygiene : QueueHygiene wS := queueHygiene_of_env_nil wS_env

theorem wS_noSelfUnif : NoSelfUnif wS := by
  intro p hp
  rw [wS_parts] at hp
  rcases List.mem_cons.mp hp with rfl | hp1
  · rfl
  rcases List.mem_cons.mp hp1 with rfl | hp2
  · rfl
  rcases List.mem_cons.mp hp2 with rfl | hp3
  · rfl
  · simp at hp3

theorem wS_noInfRow : NoInfRow wS := by
  intro p hp
  have he : wS.proc.elems = [] := rfl
  rw [he] at hp
  simp at hp

theorem wS_supOk : SupOk wS.su := ⟨by decide, by decide, by decide⟩

/-- The queue-visible vocabulary of the witness, before the step. -/
theorem allVars_qsys_wS : allVars (qsys wS) = ({0, 1, 2} : Finset Var) := by
  rw [qsys_wS]
  simp only [allVars, Finset.biUnion_insert, Finset.singleton_biUnion, lhs_mk, vset_mk]
  decide

/-- ... and after it: the same three variables. -/
theorem allVars_qsys_wS' : allVars (qsys wS') = ({0, 1, 2} : Finset Var) := by
  rw [qsys_wS']
  simp only [allVars, Finset.biUnion_insert, Finset.singleton_biUnion, lhs_mk, vset_mk]
  decide

theorem wS_supFresh : SupFresh wS.su (sys wS) := by
  intro z hz hmem
  rw [sys_wS, allVars_qsys_wS] at hmem
  simp only [Finset.mem_insert, Finset.mem_singleton] at hmem
  have hlo : wS.su.lo = 100 := rfl
  have hblk : wS.su.blk = 200000 := rfl
  rcases hz with ⟨h1, -⟩ | h1
  · rw [hlo] at h1; rcases hmem with rfl | rfl | rfl <;> omega
  · rw [hblk] at h1; rcases hmem with rfl | rfl | rfl <;> omega

/-! ## 4. The refutation -/

theorem wS_memW : mk 2 {0} ({0} : Row) ∈ qsys wS := by rw [qsys_wS]; simp

theorem wS'_notMemW : mk 2 {0} ({0} : Row) ∉ qsys wS' := by
  rw [qsys_wS']
  simp only [Finset.mem_insert, Finset.mem_singleton, Rowpartition.NameLoss.mk_eq_iff]
  rintro (⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩) <;> exact absurd h (by decide)

theorem wS'_mem2 : (2 : Var) ∈ allVars (qsys wS') := by
  refine mem_allVars (c := mk 1 {2} (∅ : Row)) ?_ (Or.inr (by simp))
  rw [qsys_wS']; simp

theorem wS_carried2 : Carried (qsys wS) 2 ({0} : Row) :=
  Carried.of_resolved (resolved_of_mem wS_memW)

theorem wS'_notCarried2 : ¬ Carried (qsys wS') 2 ({0} : Row) := by
  rintro (h | h)
  · obtain ⟨z, hz⟩ := (resolved_iff _ 2 ({0} : Row)).mp h
    rw [qsys_wS'] at hz
    simp only [Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ | ⟨h1, -, -⟩ <;> exact absurd h1 (by decide)
  · obtain ⟨C, z, hC, -⟩ := (concCarried_iff _ 2 ({0} : Row)).mp h
    rw [qsys_wS'] at hC
    simp only [Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ | ⟨h1, -, -⟩ <;> exact absurd h1 (by decide)

/-- **THE RESIDUAL IS FALSE.**  `QStepDichotomy L` fails for every label pool that contains
the witness's one label -- in particular for `labelsOf (qsys wS)`, the pool `run_qsys_bound`
is stated at.  The refuting state is INITIAL, so no relativisation to reachable states and no
invariant of round 3 can save it (§3). -/
theorem qStepDichotomy_false {L : Finset Label} (hL : (0 : Label) ∈ L) :
    ¬ QStepDichotomy L := by
  intro h
  rcases h wS wS' wRho wS_wf wS_models (wS_concSub hL) wS_step with hk | ⟨-, -, hcar, -⟩
  · exact wS'_notMemW (hk.subset wS_memW)
  · exact wS'_notCarried2 (hcar 2 wS'_mem2 ({0} : Row) wS_carried2)

/-- The label pool `run_qsys_bound` takes. -/
theorem labelsOf_qsys_wS : (0 : Label) ∈ labelsOf (qsys wS) := by
  refine Finset.mem_biUnion.mpr ⟨mk 1 ∅ ({0} : Row), ?_, by simp⟩
  rw [qsys_wS]; simp

theorem qStepDichotomy_labelsOf_false : ¬ QStepDichotomy (labelsOf (qsys wS)) :=
  qStepDichotomy_false labelsOf_qsys_wS


/-! ## 4b. The witness is a benign, terminating solve -- and the COMPILER takes the same step

The refutation is not about a divergent or a rejected run.  The model solves this input in
three dequeues, drawing no id, and the three `step` records below are the records the SHIPPED
compiler emits for the same input at id base 0 -- branch, partition, `incm=`, `proc=`; the
compiler's carry two further columns (the seed's name with its id base, and the JVM thread)
that the model's `site` field stands in for --
(`-Dermine.rowTrace`, `tracker/repro/satterm/run.sh sweep json:... 0 4`): `SOLVED`, `drawn=0`,
`v0 := ConcreteRho(-,Set()); v1 := v2 := ConcreteRho(-,Set(l0))`.  So the step that refutes
the residual is a step the compiler really takes. -/

theorem wS_trace :
    (match run wS 20 with
      | .solved s => s.trace.reverse
      | .rejected _ s => s.trace.reverse
      | .outOfFuel s => s.trace.reverse) =
      ["step\tt0\tempty\t^free0 <- (,)\tincm=2\tproc=0",
       "step\tt0\tunify:2\tCommonPartition: ^free1 <- (^free2,)\tincm=1\tproc=0",
       "step\tt0\tconcrete\t^free1 <- (,Repro.l0)\tincm=0\tproc=0"] := rfl

/-- The witness solve TERMINATES, in three dequeues. -/
theorem wS_solved : ∃ s, run wS 20 = .solved s := ⟨_, rfl⟩

/-! ## 5. The round-3 POTENTIAL strictly increases at this step

The refutation above is of the dichotomy as stated.  This section shows that the failure is
not slack in the statement: at the same step, and for EVERY model of the successor, the
potential `Pot L rho G = |allVars G| + hmeas L rho G` that `qstep_pot_le` and
`run_qsys_invariant` propagate is strictly LARGER after the step than before.  So no repair
of `QStepDichotomy` that keeps `Pot` as the measure over `qsys` can be true either. -/

/-- The one-label pool of the witness. -/
abbrev wL : Finset Label := {0}

theorem wL_powerset : wL.powerset = ({∅, {0}} : Finset Row) := by decide

theorem carried_wS_0 (K : Row) : Carried (qsys wS) 0 K := by
  refine Carried.of_conc (z := 0) (C := (∅ : Row)) ?_ ?_ <;> rw [qsys_wS] <;> simp

theorem carried_wS_1 (K : Row) : Carried (qsys wS) 1 K := by
  rcases Finset.eq_empty_or_nonempty (({0} : Row) \ K) with h | h
  · refine Carried.of_conc (z := 0) (C := ({0} : Row)) ?_ ?_ <;> rw [qsys_wS]
    · simp
    · rw [h]; simp
  · have hK : ({0} : Row) \ K = ({0} : Row) := by
      obtain ⟨x, hx⟩ := h
      simp only [Finset.mem_sdiff, Finset.mem_singleton] at hx
      ext y
      simp only [Finset.mem_sdiff, Finset.mem_singleton]
      constructor
      · rintro ⟨rfl, -⟩; rfl
      · rintro rfl; exact ⟨rfl, by rw [← hx.1]; exact hx.2⟩
    refine Carried.of_conc (z := 1) (C := ({0} : Row)) ?_ ?_ <;> rw [qsys_wS]
    · simp
    · rw [hK]; simp

theorem not_carried_wS_2_empty : ¬ Carried (qsys wS) 2 (∅ : Row) := by
  rintro (h | h)
  · obtain ⟨z, hz⟩ := (resolved_iff _ 2 (∅ : Row)).mp h
    rw [qsys_wS] at hz
    simp only [Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ | ⟨-, -, h1⟩
    · exact absurd h1 (by decide)
    · exact absurd h1 (by decide)
    · exact absurd h1.symm (by decide)
  · obtain ⟨C, z, hC, -⟩ := (concCarried_iff _ 2 (∅ : Row)).mp h
    rw [qsys_wS] at hC
    simp only [Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ | ⟨-, h1, -⟩
    · exact absurd h1 (by decide)
    · exact absurd h1 (by decide)
    · exact absurd h1.symm (Finset.singleton_ne_empty 0)

theorem carried_wS'_0 (K : Row) : Carried (qsys wS') 0 K := by
  refine Carried.of_conc (z := 0) (C := (∅ : Row)) ?_ ?_ <;> rw [qsys_wS'] <;> simp

theorem carried_wS'_1 (K : Row) : Carried (qsys wS') 1 K := by
  rcases Finset.eq_empty_or_nonempty (({0} : Row) \ K) with h | h
  · refine Carried.of_conc (z := 0) (C := ({0} : Row)) ?_ ?_ <;> rw [qsys_wS']
    · simp
    · rw [h]; simp
  · have hK : ({0} : Row) \ K = ({0} : Row) := by
      obtain ⟨x, hx⟩ := h
      simp only [Finset.mem_sdiff, Finset.mem_singleton] at hx
      ext y
      simp only [Finset.mem_sdiff, Finset.mem_singleton]
      constructor
      · rintro ⟨rfl, -⟩; rfl
      · rintro rfl; exact ⟨rfl, by rw [← hx.1]; exact hx.2⟩
    refine Carried.of_conc (z := 1) (C := ({0} : Row)) ?_ ?_ <;> rw [qsys_wS']
    · simp
    · rw [hK]; simp

theorem not_carried_wS'_2 (K : Row) : ¬ Carried (qsys wS') 2 K := by
  rintro (h | h)
  · obtain ⟨z, hz⟩ := (resolved_iff _ 2 K).mp h
    rw [qsys_wS'] at hz
    simp only [Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ | ⟨h1, -, -⟩ <;> exact absurd h1 (by decide)
  · obtain ⟨C, z, hC, -⟩ := (concCarried_iff _ 2 K).mp h
    rw [qsys_wS'] at hC
    simp only [Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h1, -, -⟩ | ⟨h1, -, -⟩ | ⟨h1, -, -⟩ <;> exact absurd h1 (by decide)

theorem uncarried_wS_0 : uncarried wL (qsys wS) 0 = 0 := by
  rw [uncarried, Finset.card_eq_zero, Finset.filter_eq_empty_iff]
  exact fun {K} _ => not_not.mpr (carried_wS_0 K)

theorem uncarried_wS_1 : uncarried wL (qsys wS) 1 = 0 := by
  rw [uncarried, Finset.card_eq_zero, Finset.filter_eq_empty_iff]
  exact fun {K} _ => not_not.mpr (carried_wS_1 K)

theorem uncarried_wS_2 : uncarried wL (qsys wS) 2 = 1 := by
  rw [uncarried, wL_powerset, Finset.filter_insert, if_pos not_carried_wS_2_empty,
    Finset.filter_singleton, if_neg (not_not.mpr wS_carried2)]
  decide

theorem uncarried_wS'_0 : uncarried wL (qsys wS') 0 = 0 := by
  rw [uncarried, Finset.card_eq_zero, Finset.filter_eq_empty_iff]
  exact fun {K} _ => not_not.mpr (carried_wS'_0 K)

theorem uncarried_wS'_1 : uncarried wL (qsys wS') 1 = 0 := by
  rw [uncarried, Finset.card_eq_zero, Finset.filter_eq_empty_iff]
  exact fun {K} _ => not_not.mpr (carried_wS'_1 K)

theorem uncarried_wS'_2 : uncarried wL (qsys wS') 2 = 2 := by
  rw [uncarried, wL_powerset,
    Finset.filter_true_of_mem (fun K _ => not_carried_wS'_2 K)]
  decide

/-- Every model of the successor agrees with `wRho` on the whole vocabulary: the successor
system pins all three variables. -/
theorem wS'_model_pinned {rho : Assign} (h : SModels rho (qsys wS')) :
    rho 0 = ∅ ∧ rho 1 = {0} ∧ rho 2 = {0} := by
  rw [qsys_wS'] at h
  have h0 := h (mk 0 ∅ (∅ : Row)) (by simp)
  have h1 := h (mk 1 ∅ ({0} : Row)) (by simp)
  have h2 := h (mk 1 {2} (∅ : Row)) (by simp)
  rw [sat_mk_iff] at h0 h1 h2
  refine ⟨by simpa using h0.1, by simpa using h1.1, ?_⟩
  have : rho 1 = rho 2 := by simpa using h2.1
  rw [← this]; simpa using h1.1

theorem hmeas_wS : hmeas wL wRho (qsys wS) = 3 := by
  rw [hmeas, allVars_qsys_wS,
    show ({0, 1, 2} : Finset Var) = insert 0 (insert 1 {2}) from rfl,
    Finset.sum_insert (by decide), Finset.sum_insert (by decide), Finset.sum_singleton,
    uncarried_wS_0, uncarried_wS_1, uncarried_wS_2]
  simp [wRho]

theorem hmeas_wS' {rho : Assign} (h : SModels rho (qsys wS')) :
    hmeas wL rho (qsys wS') = 6 := by
  obtain ⟨h0, h1, h2⟩ := wS'_model_pinned h
  rw [hmeas, allVars_qsys_wS',
    show ({0, 1, 2} : Finset Var) = insert 0 (insert 1 {2}) from rfl,
    Finset.sum_insert (by decide), Finset.sum_insert (by decide), Finset.sum_singleton,
    uncarried_wS'_0, uncarried_wS'_1, uncarried_wS'_2, h0, h1, h2]
  simp

/-- **The potential STRICTLY INCREASES at the witness step**, for every model of the
successor.  `Pot` is the measure `qstep_pot_le` and `run_qsys_invariant` propagate, so this
refutes not just the dichotomy but the propagation itself, at a reachable step of a
satisfiable input. -/
theorem qstep_pot_increases {rho : Assign} (h : SModels rho (qsys wS')) :
    Pot wL wRho (qsys wS) < Pot wL rho (qsys wS') := by
  rw [Pot, Pot, allVars_qsys_wS, allVars_qsys_wS', hmeas_wS, hmeas_wS' h]
  decide

/-- ... so the CONCLUSION of `qstep_pot_le` is false at this step. -/
theorem qstep_pot_le_false :
    ¬ (∃ rho', SModels rho' (qsys wS') ∧ ConcSub wL (qsys wS') ∧
        Pot wL rho' (qsys wS') ≤ Pot wL wRho (qsys wS)) := by
  rintro ⟨rho', hm, -, hle⟩
  exact absurd hle (Nat.not_le.mpr (qstep_pot_increases hm))


/-! ## 6. The relativisation the review asked for -- sound, and just as false

The round-3 review's item (2) asks for the residual RELATIVISED to the states the loop
actually reaches, since `run_qsys_invariant`'s induction only ever applies it there.  That
relativisation is stated here (`QStepDichotomy'`), and the whole round-3 chain is re-proved
from it (`run_qsys_bound'`): reachability threads through the fuel induction exactly as
well-formedness does, so the route is sound.

It does not help.  The witness of §4 is an INITIAL state, reached in zero steps, and every
invariant round 3 supplies holds there (§3), so `QStepDichotomy'` is refuted by the same
step -- and so is any further strengthening of the hypothesis by those invariants. -/

/-- The shape `Seed.solve` and `Replay` build: nothing processed, nothing bound. -/
def Initial (s : State) : Prop := s.proc = PQueue.empty ∧ s.env.binds = []

/-- `t` is reached from `s` by `continue` steps of the loop. -/
inductive Reaches : State → State → Prop
  | refl (s : State) : Reaches s s
  | tail {s t u : State} : Reaches s t → step t = .continue u → Reaches s u

theorem wS_initial : Initial wS := ⟨wS_proc, wS_env⟩

/-- **THE RESIDUAL, RELATIVISED** to states reachable from an initial one. -/
def QStepDichotomy' (L : Finset Label) : Prop :=
  ∀ (s0 s s' : State) (rho : Assign), Initial s0 → Reaches s0 s →
    Wf s → SModels rho (qsys s) → ConcSub L (qsys s) → step s = .continue s' →
    K2StarStep (qsys s) (qsys s') ∨
      (allVars (qsys s') ⊆ allVars (qsys s) ∧ ConcSub L (qsys s') ∧
        CarrPresOn (qsys s) (qsys s') ∧ SModels rho (qsys s'))

theorem qstep_pot_le' {L : Finset Label} (h : QStepDichotomy' L) {s0 s s' : State}
    {rho : Assign} (hi : Initial s0) (hr : Reaches s0 s) (hw : Wf s)
    (hm : SModels rho (qsys s)) (hcs : ConcSub L (qsys s)) (hst : step s = .continue s') :
    ∃ rho', SModels rho' (qsys s') ∧ ConcSub L (qsys s') ∧
      Pot L rho' (qsys s') ≤ Pot L rho (qsys s) := by
  rcases h s0 s s' rho hi hr hw hm hcs hst with hk | ⟨hvoc, hcs', hcar, hm'⟩
  · obtain ⟨rho', hm', -, hb⟩ := hk.measure_step hcs hm
    exact ⟨rho', hm', hk.concSub hcs, hb⟩
  · refine ⟨rho, hm', hcs', ?_⟩
    have h1 : hmeas L rho (qsys s') ≤ hmeas L rho (qsys s) := hcar.hmeas_le rho hvoc
    have h2 : (allVars (qsys s')).card ≤ (allVars (qsys s)).card := Finset.card_le_card hvoc
    simp only [Pot]
    omega

/-- The round-3 run-level invariant, re-proved from the relativised residual. -/
theorem run_qsys_invariant' {L : Finset Label} (h : QStepDichotomy' L) {s0 : State}
    (hi : Initial s0) :
    ∀ (n : Nat) (s : State), Reaches s0 s → Wf s → ∀ rho : Assign, SModels rho (qsys s) →
      ConcSub L (qsys s) → ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') →
        ∃ rho', SModels rho' (qsys s') ∧ Pot L rho' (qsys s') ≤ Pot L rho (qsys s)
  | 0, s, _, _, rho, hm, _, s', hres => by
    simp only [run] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres
      subst hres
      exact ⟨rho, hm, Nat.le_refl _⟩
  | n + 1, s, hr, hw, rho, hm, hcs, s', hres => by
    simp only [run] at hres
    cases hst : step s with
    | done s0' =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [step_done hst]
        exact ⟨rho, hm, Nat.le_refl _⟩
      · exact absurd hres (by simp)
    | died m0 s0' => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s1 =>
      rw [hst] at hres
      obtain ⟨rho1, hm1, hcs1, hb1⟩ := qstep_pot_le' h hi hr hw hm hcs hst
      obtain ⟨rho2, hm2, hb2⟩ :=
        run_qsys_invariant' h hi n s1 (Reaches.tail hr hst) (step_wf hw hst) rho1 hm1 hcs1 s' hres
      exact ⟨rho2, hm2, le_trans hb2 hb1⟩

/-- **The round-3 bound, re-proved from the relativised residual.**  So relativising is a
sound proof route -- the induction carries `Reaches s0 ·` exactly as it carries `Wf`. -/
theorem run_qsys_bound' {L : Finset Label} (h : QStepDichotomy' L) {s0 : State}
    (hi : Initial s0) (n : Nat) (hw : Wf s0) (rho : Assign) (hm : SModels rho (qsys s0))
    (hcs : ConcSub L (qsys s0)) (s' : State)
    (hres : run s0 n = .solved s' ∨ run s0 n = .outOfFuel s') :
    (allVars (qsys s')).card ≤ (allVars (qsys s0)).card + hmeas L rho (qsys s0) := by
  obtain ⟨rho', -, hb⟩ :=
    run_qsys_invariant' h hi n s0 (Reaches.refl s0) hw rho hm hcs s' hres
  simp only [Pot] at hb
  omega

/-- **... and the relativised residual is FALSE TOO**, by the same witness: it is initial,
so it is reachable in zero steps. -/
theorem qStepDichotomy'_false {L : Finset Label} (hL : (0 : Label) ∈ L) :
    ¬ QStepDichotomy' L := by
  intro h
  rcases h wS wS wS' wRho wS_initial (Reaches.refl wS) wS_wf wS_models (wS_concSub hL) wS_step
    with hk | ⟨-, -, hcar, -⟩
  · exact wS'_notMemW (hk.subset wS_memW)
  · exact wS'_notCarried2 (hcar 2 wS'_mem2 ({0} : Row) wS_carried2)

/-- **Adding round 3's invariants does not help either**: every one of them holds at the
witness, so any dichotomy hypothesising them is refuted by the same step. -/
theorem wS_invariants :
    Initial wS ∧ Wf wS ∧ QueueHygiene wS ∧ NoSelfUnif wS ∧ NoInfRow wS ∧
      SupOk wS.su ∧ SupFresh wS.su (sys wS) ∧ SSat (sys wS) ∧
      wS.flags.disjRule = false ∧ wS.flags.emptyRow = false ∧ wS.flags.cseMints = false :=
  ⟨wS_initial, wS_wf, wS_queueHygiene, wS_noSelfUnif, wS_noInfRow, wS_supOk, wS_supFresh,
   wS_sat, rfl, rfl, rfl⟩

end Rowpartition.Loop
