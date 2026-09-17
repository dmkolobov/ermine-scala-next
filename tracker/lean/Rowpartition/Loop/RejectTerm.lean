/-
# S1b: does REFUTATION terminate?  The budget at the SHIPPED defaults, and the whole of
`Subst.solve` around the loop

`tracker/satterm/briefs/brief-S1b.md`, deliverable 1.  The programme question
(`tracker/PROMPT-subsume-termination.md`) is whether the checker terminates on a REFUSED row
program; H3 says the rejection path grows the environment or diverges BEFORE `subsumeType`'s
escape check.  This module answers the loop half of that for the configuration the compiler
actually ships, and `Loop/EnvBound.lean` answers the environment half.

WHAT WAS ALREADY THERE, and it is cited rather than re-proved.  `Loop/Budget.lean`'s
`budget_terminates` and `Loop/PolicyTerm.lean`'s `budgetP_terminates` say: under a DRAW budget
`b ≠ 0` every solve stops, under any dequeue policy, at `VocFix.terminates_of_drawsAtMost`'s
hypotheses.  The unit is DRAWS because that is the quantity a termination theorem exists for;
converting it into a dequeue bound is `L5-TERMINATION.md` §R8.6b and is OPEN, so what is
proved is the existential `Terminates`, never an a-priori fuel.

WHAT WAS NOT, and is the gap this module closes.  `budgetP_terminates` carries the hypothesis
`s.flags.rowSoundBare = false` -- S2's layer (i) OFF.  That flag has been DEFAULT ON since
2026-09-06 (`Constraints.GenRules.rowSoundBare`, `tracker/loopmodel/A1-ADOPTION.md`; the
model's `Flags.rowSoundBare` defaults `true` too), so at the SHIPPED defaults the theorem does
not apply as stated, and `runSP` -- the driver the corpus replay and every adopted-default run
go through -- was not covered by any termination theorem at all.  The repair is not a new
argument: layer (i) is a PRE-CHECK that can only turn a continuation into a DEATH
(`NoFalseAccept.stepS_continue` states this for the shipped order), so a run of `stepSP`
either follows the run of `stepP` or stops sooner.  `stepSP_cases` is that dichotomy for the
policy driver and §2 re-proves the two transport lemmas from it, with the flag hypothesis
DELETED rather than weakened.

§3 then states the question the brief asks in the shape `Subst.solve` has: `solveSeedP` is the
WHOLE of `Subst.solve` -- `buildQueue`, the `topNormalise` rewrite, `labelCheckEarly`'s unit
propagation, S2 layer (iii)'s `labelDecide`, the loop, and the late `labelClash` -- and
`solveSeedP_terminates` says every one of those layers, not just the loop, returns a verdict.
The layers around the loop need no termination hypothesis of their own because each is a TOTAL
function in this model (`labelDecide` carries its own two node budgets, `Flags.rowSoundBudget`
/ `.rowSoundSolveBudget`, exactly as `Constraints.labelDecide` does); the loop is the only one
that takes a fuel, so the whole solve stops exactly when the loop does.

WHAT THIS DOES NOT COVER, stated here so the report and the reader agree:

* `subsumeType`'s POST-solve steps -- the `for (r <- rs) entails(qs,r)` loop, `SigEntail.enforce`,
  `restrictTypes` and the escaping-skolem walk at `Subst.scala:648` -- are not `Subst.solve` at
  all.  The escape walk over what the LOOP writes is `Loop/EnvBound.lean` §4;
* the fuel is existential, not a formula in the input (R8.6b);
* `buildQueue` runs BEFORE the budget window opens (the budget counts from `su1.drawn`), so its
  own mints -- `PQueue.build` mints for a `Part` with a non-variable left-hand side, 8 of the
  373 boot inputs, round-6 review W-6b -- are not budgeted.  It is a fold over the input list
  and terminates for that reason, not because of the budget.
-/
import Rowpartition.Loop.PolicyTerm
import Rowpartition.Loop.PolicyReplay

namespace Rowpartition.Loop

variable {pol : Policy} {aux : Aux}

/-! ## 1. S2 layer (i) can only die EARLIER

`stepSP` is `stepP` with `Loop/Decide.lean`'s bare-row pre-check in front of the `concrete`
branch.  The pre-check reads the state and the dequeued partition and either passes -- in which
case the step IS `stepP`'s -- or raises `ensureExactly`'s death.  It never moves a
continuation, which is the whole reason S1's theorems needed no hypothesis about it
(`NoFalseAccept.stepS_continue`); this is the same fact in the form a termination transport
needs, for the policy driver. -/

/-- **The dichotomy.**  Either layer (i) passes and the budgeted driver's step is the policy
loop's own step, or it dies -- and a death is a FINISHED run. -/
theorem stepSP_cases (pol : Policy) (a : Aux) (s : State) :
    stepSP pol a s = stepP pol a s ∨ ∃ m t, stepSP pol a s = .died m t := by
  unfold stepSP
  split
  · exact Or.inl rfl
  · split
    · split
      · exact Or.inr ⟨_, _, rfl⟩
      · exact Or.inl rfl
    · exact Or.inl rfl

/-! ## 2. Termination with layer (i) ON: `budgetP_terminates` without its flag hypothesis -/

/-- `PolicyTerm.terminatesBP_of_finished` with `rowSoundBare = false` DELETED.  A policy run
that finishes makes the budgeted driver finish in no more dequeues: at each dequeue the driver
either takes the same step (`stepSP_cases`, left) or dies (right), and a death is finished. -/
theorem terminatesBP_of_finished_any {d0 b : Nat} : ∀ (n : Nat) (a : Aux) (s : State),
    Finished (runP pol a s n) → Finished (runSP pol d0 b a s n)
  | 0, a, s, h => by simp only [runP, Finished] at h
  | n + 1, a, s, h => by
    simp only [runP] at h
    by_cases hb : b != 0 && d0 + b < s.su.drawn
    · rw [runSP, if_pos hb]; trivial
    · rw [runSP, if_neg hb]
      rcases stepSP_cases pol a s with heq | ⟨m, t, heq⟩
      · rw [heq]
        cases hst : stepP pol a s with
        | done s0 => rw [hst] at h; exact h
        | died m s0 => rw [hst] at h; exact h
        | «continue» s0 =>
          rw [hst] at h
          exact terminatesBP_of_finished_any n _ s0 h
      · rw [heq]; trivial

/-- `PolicyTerm.terminatesBP_of_over` with `rowSoundBare = false` DELETED.  A policy run that
reaches a state over the cap makes the budgeted driver stop: it follows the run until the
budget check fires, unless layer (i) kills it first. -/
theorem terminatesBP_of_over_any {d0 b : Nat} (hb0 : b ≠ 0) :
    ∀ (k : Nat) {a c : Aux} {s t : State},
    RunsP pol k a s c t → d0 + b < t.su.drawn → TerminatesBP pol d0 b a s
  | 0, a, c, s, t, hr, hd => by
    simp only [RunsP] at hr
    obtain ⟨rfl, rfl⟩ := hr
    exact ⟨1, by rw [runSP, if_pos (by simp [hb0, hd])]; trivial⟩
  | k + 1, a, c, s, t, hr, hd => by
    obtain ⟨s0, hstep, hrest⟩ := hr
    by_cases hb : b != 0 && d0 + b < s.su.drawn
    · exact ⟨1, by rw [runSP, if_pos hb]; trivial⟩
    · rcases stepSP_cases pol a s with heq | ⟨m, t', heq⟩
      · obtain ⟨n, hn⟩ := terminatesBP_of_over_any hb0 k hrest hd
        exact ⟨n + 1, by rw [runSP, if_neg hb, heq, hstep]; exact hn⟩
      · exact ⟨1, by rw [runSP, if_neg hb, heq]; trivial⟩

/-- **`budgetSP_terminates`: at the SHIPPED defaults every solve's loop stops.**
`PolicyTerm.budgetP_terminates` with its `rowSoundBare = false` hypothesis deleted, so the
statement covers the adopted configuration -- `-Dermine.dequeuePolicy=smallcanon`,
`-Dermine.solveBudget=20000`, `-Dermine.rowSound=true` -- rather than only the configuration
with S2 layer (i) turned off.  Everything else is unchanged: the three rule flags at their
shipped settings, the invariants L3/L5 discharge at an initial state, and a nonzero cap
(`b ≠ 0` is `runSP`'s own `b != 0` guard, which is how "budget off" is spelled).

`TerminatesBP` is an EXISTENTIAL over the fuel, exactly as `Order.Terminates` is; no a-priori
dequeue bound is claimed and none is available (`L5-TERMINATION.md` §R8.6b). -/
theorem budgetSP_terminates {b : Nat} {a : Aux} {s : State} (hb0 : b ≠ 0)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    TerminatesBP pol s.su.drawn b a s := by
  by_cases hbd : ∀ c t, ReachesP pol a s c t → t.su.drawn ≤ s.su.drawn + b
  · obtain ⟨n, hn⟩ := terminatesP_of_drawsAtMost hem hdj hcse hw hnd hok hfr hqh hki hkp hbd
    exact ⟨n, terminatesBP_of_finished_any n a s hn⟩
  · push Not at hbd
    obtain ⟨c, t, hrt, hgt⟩ := hbd
    obtain ⟨k, hk⟩ := runsP_of_reachesP hrt
    exact terminatesBP_of_over_any hb0 k hk hgt

/-- **The initial-state corollary, likewise repaired.**  `PolicyTerm.budgetP_terminates_of_buildQueue`
(`PolicyTerm.lean:1059`) carries the same `rowSoundBare = false` hypothesis, so at the shipped
defaults the corollary was as unusable as the theorem; this is its proof verbatim with that
hypothesis deleted.  `EnvNodup`, `QueueHygiene` and both `KDist`s are free at a solve's own
initial state, so what is left to supply is `Wf`, `SupOk` and `SupFresh` of the built queue.

The `rowSoundBare = false` hypothesis ALSO gates ten further declarations that this stage does
NOT repair -- the `runSP_*` soundness family (`PolicyStep.lean:2046`-`:2209`) and
`NoFalseAccept.lean:791`/`:801` -- and `PolicyStep.lean:2037`'s prose still calls that setting
"the shipped setting", which has been wrong since 2026-09-06.  They are mechanically closable
from `stepSP_cases` (layer (i) only adds DEATHS), but that is a stage of its own; see
`tracker/satterm/SUBSUME-STAGE1B.md` §6. -/
theorem budgetSP_terminates_of_buildQueue {b : Nat} {a : Aux} {cs : List CsItem} {su : Sup}
    {q : PQueue} {su' : Sup} {fl : Flags} {ns : Names} {site : String} {tr : List String}
    {z : Nat} (hb0 : b ≠ 0) (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z)) (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z))) :
    TerminatesBP pol su'.drawn b a (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  exact budgetSP_terminates hb0 hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) (kdist_ofList ps) (by simp [initState, PQueue.empty, KDist])

/-! ## 3. The whole of `Subst.solve`, not only its loop -/

/-- The state `solveSeedP` hands the loop: the built (and, under `-Dermine.topNormalise`,
rewritten) queue, an EMPTY processed queue and an EMPTY environment.  Written out here so the
hypotheses of §3's theorem can name it; it is `Seed.solveSeed`'s `st0` and `solveSeedP`'s,
field for field. -/
def seedInit (fl : Flags) (ns : Names) (site : String) (q : PQueue) (su : Sup) (lo : Nat) :
    State :=
  { incm := q, proc := PQueue.empty, env := {}, su := su, trace := [], flags := fl,
    names := ns, site := site, su0 := lo }

theorem seedInit_envNodup {fl : Flags} {ns : Names} {site : String} {q : PQueue} {su : Sup}
    {lo : Nat} : EnvNodup (seedInit fl ns site q su lo) := by
  simp [EnvNodup, seedInit]

theorem seedInit_queueHygiene {fl : Flags} {ns : Names} {site : String} {q : PQueue} {su : Sup}
    {lo : Nat} : QueueHygiene (seedInit fl ns site q su lo) :=
  queueHygiene_of_env_nil rfl

theorem seedInit_kdist_proc {fl : Flags} {ns : Names} {site : String} {q : PQueue} {su : Sup}
    {lo : Nat} : KDist (seedInit fl ns site q su lo).proc.elems := by
  simp [seedInit, PQueue.empty, KDist]

/-- A finished budgeted run is a verdict, never `FUEL`. -/
theorem verdict_ne_fuel_of_finished {d0 b n : Nat} {a : Aux} {s : State}
    (h : Finished (runSP pol d0 b a s n)) :
    ∀ s', runSP pol d0 b a s n ≠ .outOfFuel s' := by
  intro s' hr
  rw [hr] at h
  exact h

/-- **`solveSeedP_terminates`: the whole of `Subst.solve` returns a verdict.**  Not only the
loop: the value `solveSeedP` computes is the queue build, the `topNormalise` rewrite,
`labelCheckEarly`'s clash check, S2 layer (iii)'s `labelDecide` (budgeted by
`Flags.rowSoundBudget` / `.rowSoundSolveBudget`, as `Constraints.labelDecide` is), the loop,
and the late `labelClash` -- and for some fuel the verdict is one of `SOLVED` / `REJECTED`,
never `FUEL`.

The hypotheses are `budgetSP_terminates`'s, named at the state the driver actually builds:
`hq` and `htn` pin the queue the loop is started on, and `Wf`/`SupOk`/`SupFresh`/`KDist` are
the input-level invariants every termination theorem of this development carries.  `EnvNodup`
and `QueueHygiene` are FREE here, because the environment starts empty.

The fuel is existential.  What this theorem says is that no layer of `Subst.solve` can hang
while the loop stops -- which is the half of H3 the model can settle; the other half, the
environment the loop leaves, is `Loop/EnvBound.lean`. -/
theorem solveSeedP_terminates {bud : Nat} {fl : Flags} {site loc : String} {cs : List CsItem}
    {ns : Names} {su0 : Sup} {envFacts : List LPart} {q0 q : PQueue} {su0' su1 : Sup}
    {tn : List (Nat × Nat × SSet Lbl)}
    (hb0 : effBudget pol bud ≠ 0)
    (hq : buildQueue cs su0 = .ok (q0, su0'))
    (htn : topNormalise fl.topNormalise q0 su0' = (q, su1, tn))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (seedInit fl ns site q su1 su0.lo))
    (hok : SupOk su1)
    (hfr : SupFresh su1 (sys (seedInit fl ns site q su1 su0.lo)))
    (hki : KDist q.elems) :
    ∃ fuel, (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict ≠ "FUEL" := by
  obtain ⟨n, hn⟩ :=
    budgetSP_terminates (pol := pol) (b := effBudget pol bud)
      (a := Aux.init pol (seedInit fl ns site q su1 su0.lo))
      (s := seedInit fl ns site q su1 su0.lo)
      hb0 (by simpa [seedInit] using hem) (by simpa [seedInit] using hdj)
      (by simpa [seedInit] using hcse) hw seedInit_envNodup
      (by simpa [seedInit] using hok) hfr seedInit_queueHygiene
      (by simpa [seedInit] using hki) seedInit_kdist_proc
  simp only [seedInit] at hn
  refine ⟨n, ?_⟩
  simp only [solveSeedP, hq, htn]
  split
  · simp
  · split
    · simp
    · split
      · simp
      · rename_i hrun
        rw [hrun] at hn
        exact absurd hn (by simp [Finished])
      · split <;> simp

end Rowpartition.Loop
