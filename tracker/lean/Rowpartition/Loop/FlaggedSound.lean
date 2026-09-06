/-
# D1 Part B: the soundness theorems, TRANSPORTED to the flagged driver

The user's question for the Part B commit was "are we sure we are not introducing
unsoundness", and the answer has to be a theorem rather than a reading.  This module carries
S1's four soundness results across the two flags.

WHICH STEP THE REPLAY ACTUALLY RUNS, stated once so that the rest is unambiguous.  The record
path is `PolicyReplay.solveSeedP`, whose loop is `runSP pol d0 bud`, whose step is
`stepSP pol a s`.  Three equations pin it to the loop the development already proves things
about, and all three are `rfl` or one `simp`:

* `stepSP_shipped : stepSP .shipped a s = stepS s` -- the DEFAULT policy is S2's step;
* `stepSP_of_rowSound_off : s.flags.rowSoundBare = false -> stepSP pol a s = stepP pol a s` --
  with S2's layer (i) off, which is the shipped setting, it is the plain policy step;
* `stepP_shipped : stepP .shipped a s = step s` (`Loop/Policy.lean`) -- and at the default
  policy THAT is `step`, definitionally.

So at the shipped defaults the flagged driver IS the loop of S1 and S2, and every theorem they
prove applies unchanged.  What this module adds is the two flags moved OFF their defaults.

**THE BUDGET is transported completely** (SS1-SS3): the budgeted loop's answers are the shipped
loop's answers, plus one new death, and that death is added to the `NonRefutation` exception
list so that "the loop rejected" can never be read as "the input is unsatisfiable" when the
loop merely ran out of budget.

**THE POLICY is transported for the ACCEPTANCE branch** (SS4) and NOT for the rest; SS5 says
exactly what is missing and why it is not a paperwork item.  `tracker/loopmodel/D1-CHANGE.md`
carries the same statement, and Part B does not claim more.
-/
import Rowpartition.Loop.NoFalseAccept
import Rowpartition.Loop.PolicyReplay

namespace Rowpartition.Loop

/-! ## SS0. Which step the replay runs -/

/-- With S2's layer (i) off -- the shipped setting -- the replay's step is the plain policy
step. -/
theorem stepSP_of_rowSound_off {pol : Policy} {a : Aux} {s : State}
    (h : s.flags.rowSoundBare = false) : stepSP pol a s = stepP pol a s := by
  simp only [stepSP, h, Bool.false_and, Bool.false_eq_true, if_false]
  split <;> rfl

/-! ## SS1. The budgeted loop answers what the shipped loop answers

`budget_never_accepts` (`Loop/Budget.lean`) is the `.solved` half.  This is the `.outOfFuel`
half, and with it every `run_*` theorem whose conclusion is about those two answers transports
to `runBud` with no new proof at all. -/

/-- A budgeted run that runs out of FUEL ran out of fuel unbudgeted: it never took the budget
branch, so it followed `step` at every dequeue. -/
theorem runBud_outOfFuel {d0 b : Nat} : ∀ (n : Nat) {s s' : State},
    runBud d0 b s n = .outOfFuel s' → run s n = .outOfFuel s'
  | 0, s, s', h => by simpa only [runBud, run] using h
  | n + 1, s, s', h => by
    by_cases hb : d0 + b < s.su.drawn
    · simp only [runBud, stepBud, if_pos hb] at h
      exact absurd h (by simp)
    · simp only [runBud, stepBud_of_le (by omega : s.su.drawn ≤ d0 + b)] at h
      simp only [run]
      cases hst : step s with
      | done s0 => rw [hst] at h; exact absurd h (by simp)
      | died m s0 => rw [hst] at h; exact absurd h (by simp)
      | «continue» s0 =>
        rw [hst] at h
        simp only [] at h
        exact runBud_outOfFuel n h

/-- **OUTPUT SOUNDNESS under the budget.**  `Loop/Sound.lean`'s `run_noLoss` says an accepted
or fuel-exhausted run of a SATISFIABLE input loses nothing; the budgeted run's two such answers
are the shipped run's, so it loses nothing either. -/
theorem runBud_noLoss {d0 b : Nat} (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s))
    (s' : State) (hres : runBud d0 b s n = .solved s' ∨ runBud d0 b s n = .outOfFuel s') :
    NoLoss (sys s) (sys s') :=
  run_noLoss n hw hem hdj hcse hb hsat s'
    (hres.elim (fun h => Or.inl (budget_never_accepts n h))
               (fun h => Or.inr (runBud_outOfFuel n h)))

/-- **SATISFIABILITY is preserved under the budget.** -/
theorem runBud_sat_all {d0 b : Nat} (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s))
    (s' : State) (hres : runBud d0 b s n = .solved s' ∨ runBud d0 b s n = .outOfFuel s') :
    SSat (sys s') :=
  run_sat_all n hw hem hdj hcse hb hsat s'
    (hres.elim (fun h => Or.inl (budget_never_accepts n h))
               (fun h => Or.inr (runBud_outOfFuel n h)))

/-- **REFINEMENT under the budget**: every model of the budgeted output is a model of the
input, which is the licence for applying the substitution the loop wrote. -/
theorem runBud_models {d0 b : Nat} {n : Nat} {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s))
    {s' : State} (hres : runBud d0 b s n = .solved s' ∨ runBud d0 b s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s) :=
  run_models hw hem hdj hcse hb hsat
    (hres.elim (fun h => Or.inl (budget_never_accepts n h))
               (fun h => Or.inr (runBud_outOfFuel n h)))

/-! ## SS2. Rejection soundness under the budget

The budget adds ONE death to the loop, and it is a resource limit and not a refutation, so it
joins the skolem refusal on the `NonRefutation` exception list.  Leaving it off would be exactly
the unsoundness the user asked about: "the loop rejected" would license "the input has no
model", and budget exhaustion licenses nothing of the sort. -/

/-- The budget's death, as a predicate on the message. -/
def BudgetDeath (m : String) : Prop :=
  ∃ (site : String) (d0 b n : Nat), m = budgetMsg site d0 b n

/-- The exception list for the budgeted loop: the skolem refusal, or budget exhaustion. -/
def NonRefutationB (ns : Names) (m : String) : Prop :=
  NonRefutation ns m ∨ BudgetDeath m

/-- **REJECTION SOUNDNESS under the budget.**  A budgeted run that rejects with a message that
is neither the skolem refusal nor budget exhaustion has refuted its input. -/
theorem runBud_rejects_unsat {d0 b : Nat} : ∀ (n : Nat) {s : State}, Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOk n s → QueueHygiene s →
    ∀ (m : String) (s' : State), runBud d0 b s n = .rejected m s' →
      ¬ NonRefutationB s.names m → ¬ SSat (sys s)
  | 0, s, _, _, _, _, _, _, m, s', hres, _ => by
    simp only [runBud] at hres; exact absurd hres (by simp)
  | n + 1, s, hw, hem, hdj, hcse, hb, hq, m, s', hres, hnr => by
    by_cases hbud : d0 + b < s.su.drawn
    · -- the budget fired: the message is on the exception list, so the hypothesis is false
      simp only [runBud, stepBud, if_pos hbud] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨rfl, -⟩ := hres
      exact absurd (Or.inr ⟨s.site, d0, b, s.su.drawn, rfl⟩) hnr
    · simp only [runBud, stepBud_of_le (by omega : s.su.drawn ≤ d0 + b)] at hres
      cases hst : step s with
      | done s0 => rw [hst] at hres; exact absurd hres (by simp)
      | died m0 s0 =>
        rw [hst] at hres
        rw [RunResult.rejected.injEq] at hres
        obtain ⟨rfl, -⟩ := hres
        rcases step_died_refutes hw hq hst with hh | hh
        · exact hh
        · exact absurd (Or.inl hh) hnr
      | «continue» s0 =>
        rw [hst] at hres
        simp only [] at hres
        intro hsat
        refine runBud_rejects_unsat n (step_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
          (step_queueHygiene hdj hb.1 hb.2.1 hq hst) m s' hres ?_
          (step_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat)
        · rw [step_flags hst]; exact hem
        · rw [step_flags hst]; exact hdj
        · rw [step_flags hst]; exact hcse
        · rw [step_names hst]; exact hnr

/-- ...and on a solve with no skolem, where the ONLY exception is budget exhaustion. -/
theorem runBud_rejects_unsat_noSkolem {d0 b : Nat} (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hq : QueueHygiene s)
    (hsk : ∀ v, s.names.isSkolem v = false)
    (m : String) (s' : State) (hres : runBud d0 b s n = .rejected m s')
    (hnb : ¬ BudgetDeath m) : ¬ SSat (sys s) :=
  runBud_rejects_unsat n hw hem hdj hcse hb hq m s' hres
    (by rintro (⟨v, hv, -⟩ | hbd)
        · rw [hsk v] at hv; exact absurd hv (by simp)
        · exact hnb hbd)

/-! ## SS3. S2's no-false-acceptance chain, under the budget

`solve_noFalseAccept` and `solve_accepted_faithful` are about a run that DOES NOT REJECT.  The
budgeted run does not reject exactly when the shipped run does not reject and the budget never
fired, so the chain carries over with the same hypotheses. -/

/-- A shipped rejection forces a budgeted rejection: either the budget fired first, which is
itself a rejection, or the budgeted run followed `step` to the same death. -/
theorem runBud_rejects_of_run_rejects {d0 b : Nat} : ∀ (n : Nat) {s : State} {m : String}
    {s' : State}, run s n = .rejected m s' → ∃ m0 s0, runBud d0 b s n = .rejected m0 s0
  | 0, s, m, s', hc => by simp only [run] at hc; exact absurd hc (by simp)
  | n + 1, s, m, s', hc => by
    by_cases hbud : d0 + b < s.su.drawn
    · exact ⟨budgetMsg s.site d0 b s.su.drawn, s, by
        simp only [runBud, stepBud, if_pos hbud]⟩
    · simp only [run] at hc
      cases hst : step s with
      | done s0 => rw [hst] at hc; exact absurd hc (by simp)
      | died m0 s0 =>
        exact ⟨m0, s0, by
          simp only [runBud, stepBud_of_le (by omega : s.su.drawn ≤ d0 + b), hst]⟩
      | «continue» s0 =>
        rw [hst] at hc
        simp only [] at hc
        obtain ⟨m1, s1, h1⟩ := runBud_rejects_of_run_rejects (d0 := d0) (b := b) n hc
        exact ⟨m1, s1, by
          simp only [runBud, stepBud_of_le (by omega : s.su.drawn ≤ d0 + b), hst]
          exact h1⟩

/-- **The no-false-acceptance hypothesis transports.**  S2's `solve_noFalseAccept` and
`solve_accepted_faithful` are conditional on "the solve does not reject"; a budgeted run that
does not reject gives that hypothesis for the shipped run, so both theorems apply to the
budgeted driver with nothing else changed. -/
theorem runBud_not_rejected {d0 b : Nat} (n : Nat) {s : State}
    (h : ∀ m s', runBud d0 b s n ≠ .rejected m s') : ∀ m s', run s n ≠ .rejected m s' := by
  intro m s' hc
  obtain ⟨m0, s0, h0⟩ := runBud_rejects_of_run_rejects (d0 := d0) (b := b) n hc
  exact h m0 s0 h0

/-! ## SS4. The POLICY: the acceptance branch

`dequeuePol_none` (`Loop/Policy.lean` §6) is what makes this true, and this is the theorem that
uses it: under ANY policy, the flagged loop can only accept a solve whose incoming queue is
EMPTY.  A `pop` that answered `none` early would make `incorporateAll` return `proc` and the
solve accept without saturating; that is the one way a dequeue order could introduce
unsoundness all by itself, and it is ruled out for every policy. -/

/-- **Under any policy, `.done` means the queue is empty.** -/
theorem stepP_done_dequeue {pol : Policy} {a : Aux} {s s' : State}
    (h : stepP pol a s = .done s') : s.incm.elems = [] := by
  simp only [stepP, State.log] at h
  split at h
  · rename_i hnone; exact dequeuePol_none hnone
  · exfalso; repeat' split at h
    all_goals exact absurd h (by simp)

/-- ...and the state it accepts at is the state it was given. -/
theorem stepP_done {pol : Policy} {a : Aux} {s s' : State}
    (h : stepP pol a s = .done s') : s' = s := by
  simp only [stepP, State.log] at h
  split at h
  · exact (StepResult.done.injEq _ _ ▸ h).symm
  · exfalso; repeat' split at h
    all_goals exact absurd h (by simp)

/-- The same for the replay's step, which is the one the differential runs. -/
theorem stepSP_done_dequeue {pol : Policy} {a : Aux} {s s' : State}
    (h : stepSP pol a s = .done s') : s.incm.elems = [] := by
  simp only [stepSP] at h
  split at h
  · rename_i hnone; exact stepP_done_dequeue h
  · split at h
    · split at h
      · exact absurd h (by simp)
      · exact stepP_done_dequeue h
    · exact stepP_done_dequeue h

/-! ## SS5. The POLICY: transported in full, by `Loop/PolicyStep.lean` and `Loop/PolicyTerm.lean`

**This section used to be a FINDING and is now a pointer.**  When this module was written the
budget was transported completely (SS1-SS3) and the policy only for the acceptance branch (SS4);
the rest of S1 was measured, not proved, and the gap was 1,221 proof lines across 22 theorems
that unfold `step` (the inventory is `tracker/loopmodel/D1-CHANGE.md` SS5, written as a spec for
whoever closed it).  It was closed on 2026-09-06 by a separate agent, in two modules that leave
every original theorem untouched:

* `Loop/PolicyStep.lean` -- SOUNDNESS for every policy: `stepP_refines_all`, `runP_sat_all`,
  `runP_noLoss` (and `runP_noLoss_or`), `runP_rejects_unsat` and `runP_rejects_unsat_noSkolem`,
  plus the `*_recovers` corollaries;
* `Loop/PolicyTerm.lean` -- TERMINATION under a budget for every policy: `budgetP_terminates`
  and `budgetP_terminates_of_buildQueue`, which carry `hb0 : b ≠ 0` because `runSP` reads a
  budget of `0` as OFF.

So the reading of SS4 is now the weakest of the guarantees rather than the whole of them, and
what this module still contributes on its own is the BUDGET half (SS1-SS3) and the statement of
which step the replay runs (SS0).  What remains unproved for either flag is what `budget_terminates`
never gave: an a-priori FUEL number, which needs a bound on dequeues per draw -- the open problem
of `L5-TERMINATION.md` SSR8.6b -- and which no amount of transporting supplies. -/

end Rowpartition.Loop
