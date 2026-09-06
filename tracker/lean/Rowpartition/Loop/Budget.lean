/-
# D1 (A1): the DRAW BUDGET — a solve that stops, and stops by REJECTING

`tracker/loopmodel/briefs/brief-D1.md`, and the decision it records (user, 2026-09-05):
termination of `Constraints.incorporateAll` is not a property of the algorithm — eight L5
rounds looked for one and both mint factors are unbounded on the evidence
(`L5-TERMINATION.md` §R8.6, round-8 review Y-19) — so it is ENGINEERED.  This module is the
engineering, on the model: a cap on the number of FRESH IDS ONE SOLVE MAY DRAW, checked by
the loop driver, whose exhaustion is a `Death` with a diagnostic.

THE UNIT IS DRAWS, not dequeues, and that is not a convenience: every termination theorem the
stage has is about `Sup.drawn` (`VocFix.terminates_of_drawsAtMost`: a solve that draws
boundedly many ids terminates), and no theorem bounds dequeues per draw — that is the open
problem `L5-TERMINATION.md` §R8.6b names.  So a draw cap is exactly the quantity the existing
proof can convert into termination, and a dequeue cap is not.

WHERE THE CHECK SITS.  `stepBud` tests the budget BEFORE the dequeue, on the state it is
given, and dies with THAT state.  Two consequences, both wanted:

* the death changes nothing — `stepBud_died_sys` gives `sys s' = sys s` for the budget death
  by `rfl` and for the loop's own deaths by `Refine.step_died_sys`;
* a solve may overshoot the budget by ONE STEP's draws before it is stopped, which
  `Draws.learnPartitions_drawn` bounds by `1 + proc.size`.  The compiler's own check will sit
  at the two minting sites (`splitConcrete` and `resolution`, the only two rules that call
  `fresh` under the shipped flags — `Loop/Draws.lean`), where it fires on the draw itself and
  there is no overshoot; the model's is one dequeue coarser and therefore stops a SUPERSET of
  the solves the compiler's would let through.  `tracker/loopmodel/D1-DESIGN.md` §2 states the
  difference; nothing below depends on which of the two sites is used.

NOTHING HERE IS ON BY DEFAULT.  `stepBud` and `runBud` are new functions; `step` and `run` are
untouched, so every existing theorem and the L2 corpus differential are about the same loop
they were about before.  The executable reaches the budget only through `--budget=<n>`, and
`runBud_eq_run` says what "off" means: a run that never exceeds the cap is the shipped run,
record for record.
-/
import Rowpartition.Loop.Depth

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. The budget, and the loop under it -/

/-- The diagnostic.  It names the SITE (the solve, as every trace record does), the number of
fresh ids THE LOOP drew — `Sup.drawn` minus the count at the loop's start, which is what
`buildQueue`'s own mints leave behind — and the budget itself, so that the message says which
knob to turn. -/
def budgetMsg (site : String) (d0 b n : Nat) : String :=
  "Row solver budget exhausted at " ++ site ++ ": the loop drew " ++ toString (n - d0) ++
  " fresh row variables, budget " ++ toString b ++
  " (-Dermine.solveBudget); the row constraints are too large or the solver is not converging"

/-- One dequeue under a budget of `b` fresh ids over the count `d0` the loop started with.
The check is made on the state the step is given, so the death reports THAT state. -/
def stepBud (d0 b : Nat) (s : State) : StepResult :=
  if d0 + b < s.su.drawn then .died (budgetMsg s.site d0 b s.su.drawn) s else step s

/-- Iterate `stepBud`.  The fuel is a bound on dequeues, exactly as `run`'s is; the BUDGET is
what makes the loop stop, and the fuel is still what makes the function total. -/
def runBud (d0 b : Nat) : State → Nat → RunResult
  | s, 0 => .outOfFuel s
  | s, n + 1 =>
    match stepBud d0 b s with
    | .done s' => .solved s'
    | .died m s' => .rejected m s'
    | .continue s' => runBud d0 b s' n

/-- The termination predicate for the budgeted loop, the same shape as `Order.Terminates`. -/
def TerminatesB (d0 b : Nat) (s : State) : Prop := ∃ n : Nat, Finished (runBud d0 b s n)

/-! ## 2. The budget is inert until it fires -/

/-- Below the cap, a budgeted step IS the step. -/
theorem stepBud_of_le {d0 b : Nat} {s : State} (h : s.su.drawn ≤ d0 + b) :
    stepBud d0 b s = step s := by
  simp only [stepBud, if_neg (by omega : ¬ d0 + b < s.su.drawn)]

/-- **The flag off.**  A run no state of which exceeds the cap is the shipped run — the same
answer and the same final state, hence the same trace.  This is why the L2 corpus differential
is untouched while the budget is not set: with `--budget=0` the executable does not call
`runBud` at all, and with any cap the run above is `run` unless the cap is reached. -/
theorem runBud_eq_run {d0 b : Nat} : ∀ (n : Nat) (s : State),
    (∀ t, Reaches s t → t.su.drawn ≤ d0 + b) → runBud d0 b s n = run s n
  | 0, s, _ => rfl
  | n + 1, s, h => by
    simp only [runBud, run, stepBud_of_le (h s (Reaches.refl s))]
    cases hst : step s with
    | done s' => rfl
    | died m s' => rfl
    | «continue» s' =>
      simp only []
      exact runBud_eq_run n s'
        (fun t ht => h t (reaches_trans ((Reaches.refl s).tail hst) ht))

/-! ## 3. `budget_never_accepts` -/

/-- The budget death, and the loop's own deaths, leave the denoted system alone: the state
reported is the state the step was given.  `Refine.step_died_sys` is the same fact for `step`,
and this is its shape for `stepBud`. -/
theorem stepBud_died_sys {d0 b : Nat} {s s' : State} {m : String}
    (h : stepBud d0 b s = .died m s') : sys s' = sys s := by
  simp only [stepBud] at h
  split at h
  · cases h; rfl
  · exact step_died_sys h

/-- **BUDGET EXHAUSTION IS A REJECTION**, with the diagnostic, at the unchanged state. -/
theorem budget_exhausted_rejects {d0 b : Nat} {s : State} (h : d0 + b < s.su.drawn) (n : Nat) :
    runBud d0 b s (n + 1) = .rejected (budgetMsg s.site d0 b s.su.drawn) s := by
  simp only [runBud, stepBud, if_pos h]

/-- **`budget_never_accepts`.**  Whatever the budgeted loop ACCEPTS, the shipped loop accepts,
in the same number of dequeues and at the same final state.  So no solve is accepted BECAUSE
of the budget: exhaustion can only turn an acceptance into the rejection above, never the
other way round, and the substitution an accepted solve publishes is the one the shipped loop
published.  (With `stepBud_died_sys` this is the pair the brief asks for: exhaustion is
`.died`, and `sys` is unchanged.) -/
theorem budget_never_accepts {d0 b : Nat} : ∀ (n : Nat) {s s' : State},
    runBud d0 b s n = .solved s' → run s n = .solved s'
  | 0, s, s', h => by simp only [runBud] at h; exact absurd h (by simp)
  | n + 1, s, s', h => by
    by_cases hb : d0 + b < s.su.drawn
    · simp only [runBud, stepBud, if_pos hb] at h
      exact absurd h (by simp)
    · simp only [runBud, stepBud_of_le (by omega : s.su.drawn ≤ d0 + b)] at h
      simp only [run]
      cases hst : step s with
      | done s0 => rw [hst] at h; simpa using h
      | died m s0 => rw [hst] at h; exact absurd h (by simp)
      | «continue» s0 =>
        rw [hst] at h
        simp only [] at h
        exact budget_never_accepts n h

/-! ## 4. `budget_terminates` -/

/-- More fuel cannot hurt the budgeted loop either. -/
theorem runBud_mono {d0 b : Nat} : ∀ (n : Nat) (s : State),
    Finished (runBud d0 b s n) → Finished (runBud d0 b s (n + 1))
  | 0, s, h => by simp only [runBud, Finished] at h
  | n + 1, s, h => by
    simp only [runBud] at h ⊢
    cases hst : stepBud d0 b s with
    | done s0 => rw [hst] at h; exact h
    | died m s0 => rw [hst] at h; exact h
    | «continue» s0 => rw [hst] at h; exact runBud_mono n s0 h

/-- A shipped run that finishes makes the budgeted run finish, in no more dequeues: the
budgeted loop either follows it or dies earlier. -/
theorem terminatesB_of_finished {d0 b : Nat} : ∀ (n : Nat) (s : State),
    Finished (run s n) → Finished (runBud d0 b s n)
  | 0, s, h => by simp only [run, Finished] at h
  | n + 1, s, h => by
    simp only [run] at h
    by_cases hb : d0 + b < s.su.drawn
    · simp only [runBud, stepBud, if_pos hb]; trivial
    · simp only [runBud, stepBud_of_le (by omega : s.su.drawn ≤ d0 + b)]
      cases hst : step s with
      | done s0 => rw [hst] at h; exact h
      | died m s0 => rw [hst] at h; exact h
      | «continue» s0 => rw [hst] at h; exact terminatesB_of_finished n s0 h

/-- ...and a shipped run that reaches a state over the cap makes the budgeted run DIE: the
budgeted loop follows the shipped one until the check fires, and it must fire, because the
state it would have to reach is over the cap. -/
theorem terminatesB_of_over {d0 b : Nat} : ∀ (k : Nat) {s t : State},
    Runs k s t → d0 + b < t.su.drawn → TerminatesB d0 b s
  | 0, s, t, hr, hd => by
    simp only [Runs] at hr
    subst hr
    exact ⟨1, by simp only [runBud, stepBud, if_pos hd]; trivial⟩
  | k + 1, s, t, hr, hd => by
    obtain ⟨s0, hstep, hrest⟩ := hr
    by_cases hb : d0 + b < s.su.drawn
    · exact ⟨1, by simp only [runBud, stepBud, if_pos hb]; trivial⟩
    · obtain ⟨n, hn⟩ := terminatesB_of_over k hrest hd
      exact ⟨n + 1, by
        simp only [runBud, stepBud, if_neg hb, hstep]
        exact hn⟩

/-- **`budget_terminates`.**  Under a draw budget EVERY solve stops, at exactly the
hypotheses `VocFix.terminates_of_drawsAtMost` needs — the three shipped flag settings and the
invariants L3/L5 discharge at an initial state.  The two cases are the two ways a budget can
end a run, and the first is `terminates_of_drawsAtMost` itself:

* the shipped loop never exceeds the cap, so it draws boundedly many ids, so it TERMINATES
  (`terminates_of_drawsAtMost` with `k := b`), and the budgeted loop follows it;
* some reachable state exceeds the cap, and then the check fires at or before it.

Note what this does NOT give: an a-priori FUEL number.  Converting a draw budget into a
dequeue bound needs a bound on dequeues per draw, which is the open problem of
`L5-TERMINATION.md` §R8.6b; `Terminates` here is the same existential `Order.Terminates` is. -/
theorem budget_terminates {b : Nat} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    TerminatesB s.su.drawn b s := by
  by_cases hbd : ∀ t, Reaches s t → t.su.drawn ≤ s.su.drawn + b
  · obtain ⟨n, hn⟩ := terminates_of_drawsAtMost hem hdj hcse hw hnd hok hfr hqh hki hkp hbd
    exact ⟨n, terminatesB_of_finished n s hn⟩
  · push Not at hbd
    obtain ⟨t, hrt, hgt⟩ := hbd
    obtain ⟨k, hk⟩ := runs_of_reaches hrt
    exact terminatesB_of_over k hk hgt

/-- The corollary at a solve's own initial state, where `EnvNodup`, both `KDist`s and
`QueueHygiene` are free: **every solve run under a draw budget stops.** -/
theorem budget_terminates_of_buildQueue {b : Nat} {cs : List CsItem} {su : Sup} {q : PQueue}
    {su' : Sup} {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z))) :
    TerminatesB su'.drawn b (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  exact budget_terminates hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) (kdist_ofList ps) (by simp [initState, PQueue.empty, KDist])

end Rowpartition.Loop
