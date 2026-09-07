/-
# D1-T: the POLICY TRANSPORT — S1 and S2 re-proved for the policy-parameterised step

`tracker/loopmodel/D1-CHANGE.md` §4d reported a FINDING rather than papering over it: with
`-Dermine.dequeuePolicy` off the flagged driver IS the loop S1 and S2 are about
(`stepP_shipped`, `stepSP_shipped`, both `rfl`), but under a NON-DEFAULT policy the soundness
results were EVIDENCE — 0 verdict differences over 2,301,195 corpus solves — and not theorems.
This module closes that gap.  §5 of the same document is the transport spec it follows.

WHAT IS RE-PROVED AND FROM WHAT.  Every proof in the development consumes `pop` through the
SHAPE of a dequeue and never through the ORDER it chose in:

```lean
def DequeueShape (q : PQueue) (r : LPart) (rest : PQueue) : Prop :=
  ∃ i, q.elems[i]? = some r ∧ rest = ⟨q.elems.eraseIdx i, q.graph⟩
```

`Loop/Policy.lean` §5–§6 proves `dequeuePol_shape` (every one of the six policies has that
shape), `shape_mem`, `shape_mem_or`, `shape_length_lt`, `shape_kdist`, `dequeuePol_unique` and
`dequeuePol_none`.  The theorems below are the ORIGINALS re-run against those facts: the same
statements with `step s` replaced by `stepP pol aux s`, the same proofs with two substitutions —
the opening `simp only [step, State.log] at h` becomes `simp only [stepP, State.log] at h`, and
`PQueue.dequeue_mem hdq` becomes `shape_mem (dequeuePol_shape hdq)` (and its siblings likewise).
NO hypothesis is weakened and no statement is narrowed; the side-by-side table is
`D1-CHANGE.md` §6.

**The originals are untouched.**  `Loop/{Wf,Refine,RefineConcrete,RefineLearn,Order,Hygiene,
Supply,Mints,StrictBound,StrictStep,Sound,Reject}.lean` still prove exactly what they proved,
about `step`; this module proves the policy copies beside them, so a reviewer can diff the two
and the L2 corpus differential at the default is the differential it always was.

WHAT COMES OUT AT THE RUN LEVEL.  `runP` is `run` with `stepP` (the `Aux` threaded exactly as
`PolicyReplay.runSP` threads it), and it gets the four S1 results and S2's chain:

* `runP_sat_all`   — satisfiability is preserved, under ANY policy;
* `runP_noLoss` / `runP_models` / `runP_ssat_iff` — output soundness and refinement;
* `runP_rejects_unsat` — a rejection that is not the skolem refusal REFUTES the input;
* `runP_solved_saturated` — and an ACCEPTANCE happens only on an EMPTY queue, which is the one
  failure mode a dequeue order could introduce on its own (`stepP_done_dequeue`, used in the
  `.solved` case of the run induction and not merely stated);
* `solveP_noFalseAccept` / `solveP_accepted_faithful` — S2's chain for the policy driver.

AND FOR THE DRIVER THE REPLAY ACTUALLY RUNS.  `PolicyReplay.solveSeedP` runs `runSP pol d0 bud`,
whose step is `stepSP`.  §4 below reduces it to `runP`: with S2's layer (i) off (the shipped
setting) and the budget off it IS `runP`, and with the budget ON it is `runP` plus one new
death, which joins the skolem refusal on `FlaggedSound.NonRefutationB` — `runSP_rejects_unsat`.
That is the same discipline `FlaggedSound` applies to `runBud`, now over a policy.
-/
import Rowpartition.Loop.FlaggedSound

namespace Rowpartition.Loop

variable {pol : Policy} {aux : Aux}

/-! ## 0. The dequeue facts, in the form the transported proofs consume them -/

/-- `Wf.QOk.dequeue` for any policy: the dequeued partition and the queue that is left are
both `QOk`, because both are elements of the queue that was given. -/
theorem QOk.shape {L : List Lbl} {q : PQueue} {r : LPart} {rest : PQueue}
    (h : QOk L q) (hd : DequeueShape q r rest) : POk L r ∧ QOk L rest := by
  obtain ⟨h1, h2⟩ := shape_mem hd
  exact ⟨h r h1, fun x hx => h x (h2 x hx)⟩

/-! ## 1. The dispatch predicates, at the partition THE POLICY dequeues

`LinkOrEmptyStep`, `NonLearnStep`, `NonConcreteStep` and `BareAgree` are quantified over the
dequeue, so each needs its policy form: the branch condition is about the partition the policy
picked, not the one `Q.pop` would have picked. -/

/-- `Refine.LinkOrEmptyStep` at the policy's dequeue. -/
def LinkOrEmptyStepP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∀ r rest, dequeuePol pol aux s.incm = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨ (r.rhs.single?).isSome = true

/-- `RefineConcrete.NonLearnStep` at the policy's dequeue. -/
def NonLearnStepP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∀ r rest, dequeuePol pol aux s.incm = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨
    r.rhs.abstr.isEmpty = true ∨ (r.rhs.single?).isSome = true

/-- `StrictStep.NonConcreteStep` at the policy's dequeue. -/
def NonConcreteStepP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∀ r rest, dequeuePol pol aux s.incm = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨
    r.rhs.abstr.isEmpty = false

/-- `Sound.BareAgree` at the policy's dequeue. -/
def BareAgreeP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∀ r rest, dequeuePol pol aux s.incm = some (r, rest) → r.rhs.abstr.isEmpty = true →
    ∀ x ∈ rest.elems ++ s.proc.elems, x.lhs = r.lhs → x.rhs.abstr.isEmpty = true →
      cfs x.rhs.conc = cfs r.rhs.conc

/-- `Order.IsLearnStep` at the policy's dequeue. -/
def IsLearnStepP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∃ (r : LPart) (rest : PQueue), dequeuePol pol aux s.incm = some (r, rest) ∧
    s.proc.findRHS r.rhs = none ∧ r.rhs.isEmpty = false ∧ r.rhs.abstr.isEmpty = false ∧
    r.rhs.single? = none

/-! ## 2. The step-level transport -/

/-- **The two conditions are preserved by every `continue` step**, at a FIXED label pool:
no rule invents a label, so the pool never has to grow. -/
theorem stepP_qok {L : List Lbl} {s s' : State} (hi : QOk L s.incm) (hp : QOk L s.proc)
    (h : stepP pol aux s = .continue s') : QOk L s'.incm ∧ QOk L s'.proc := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hrOk, hrest⟩ := QOk.shape hi (dequeuePol_shape hdq)
    split at h
    · -- `common:u`
      rename_i u _
      cases hu : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hu] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hu] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact unifyVars_ok hrest hp hu
    · split at h
      · -- `empty`
        cases hu : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hu] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hu] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact makeEmpty_ok hrest hp hu
      · split at h
        · -- `concrete`
          cases hu : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hu] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hu] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact makeConcrete_ok hrOk.conc hrest hp hu
        · split at h
          · -- `unify:u`
            rename_i u _
            cases hu : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hu] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact unifyVars_ok hrest hp hu
          · -- `learn`
            cases hu : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hu] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hu] at h
              have hlearned : SOk L learned := learnPartitions_ok hrOk.rhsOk hp hu
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨QOk.concatP _ _ hrest (hlearned.trim (q := s.proc)),
                hp.insertNP hrOk⟩

/-- **`Wf` is preserved by every `continue` step.**  This is L1 review F6 and L2 review F5:
the bridge's hypotheses now have an invariant tying them to `step`. -/
theorem stepP_wf {s s' : State} (hw : Wf s) (h : stepP pol aux s = .continue s') : Wf s' := by
  obtain ⟨h1, h2⟩ := stepP_qok hw.incm hw.proc h
  have hsub : ∀ x ∈ s'.labels, x ∈ s.labels := by
    intro x hx
    obtain ⟨p, hp, hxp⟩ := List.mem_flatMap.mp hx
    rcases List.mem_append.mp hp with hp' | hp'
    · exact (h1 p hp').conc.sub x hxp
    · exact (h2 p hp').conc.sub x hxp
  exact wf_of_nodup (fun p hp => ⟨(h1 p hp).abstr, (h1 p hp).conc.nodup⟩)
    (fun p hp => ⟨(h2 p hp).abstr, (h2 p hp).conc.nodup⟩) (hw.coh.mono hsub)

/-- `step` never changes the flags. -/
theorem stepP_flags {s s' : State} (h : stepP pol aux s = .continue s') : s'.flags = s.flags := by
  simp only [stepP, State.log] at h
  repeat' split at h
  all_goals (cases h <;> simp only [foldl_log_flags])

theorem stepP_names {s s' : State} (h : stepP pol aux s = .continue s') : s'.names = s.names := by
  simp only [stepP, State.log] at h
  repeat' split at h
  all_goals (cases h <;> simp only [foldl_log_names])

/-- A `died` state denotes the system its predecessor denoted: the death is raised before
either queue or the environment is written. -/
theorem stepP_died_sys {s s' : State} {m : String} (h : stepP pol aux s = .died m s') :
    sys s' = sys s := by
  simp only [stepP, State.log] at h
  repeat' split at h
  all_goals (cases h <;> rfl)

/-- A `died` step changes nothing but the trace, so hygiene survives a REFUTATION too. -/
theorem stepP_died_parts {s s' : State} {m : String}
    (h : Rowpartition.Loop.stepP pol aux s = .died m s') :
    s'.parts = s.parts ∧ s'.env = s.env := by
  simp only [stepP, State.log] at h
  repeat' split at h
  all_goals (cases h <;> exact ⟨rfl, rfl⟩)

/-- **Eager `makeEmpty`.**  A dequeued `v <- ()` whose right-hand side no processed partition
shares goes straight to `makeEmpty`; `learnPartitions` is not called. -/
theorem stepP_empty_branch {s : State} {r : LPart} {rest : PQueue}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = true) :
    ∃ st : State, st.incm = s.incm ∧ st.proc = s.proc ∧ st.env = s.env ∧ st.names = s.names ∧
      stepP pol aux s = (match makeEmpty s.names r.lhs rest s.proc s.env with
        | .error m => .died m st
        | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }) := by
  refine ⟨s.log ("step\t" ++ s.site ++ "\t" ++ "empty" ++ "\t" ++ r.toStr s.names ++
    "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size),
    rfl, rfl, rfl, rfl, ?_⟩
  simp only [stepP, State.log]
  rw [hd]
  dsimp only
  rw [h1]
  dsimp only
  rw [if_pos h2]
  rfl

/-- **Eager `unify`.**  A dequeued `v <- (u)` goes straight to `unify`; no rule fires. -/
theorem stepP_unify_branch {s : State} {r : LPart} {rest : PQueue} {u : Nat}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h4 : r.rhs.single? = some u) :
    ∃ st : State, st.incm = s.incm ∧ st.proc = s.proc ∧ st.env = s.env ∧ st.names = s.names ∧
      stepP pol aux s = (match unifyVars s.names u r.lhs rest s.proc s.env with
        | .error m => .died m st
        | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }) := by
  have h2 : r.rhs.isEmpty = false := by
    unfold RHS.single? at h4
    split at h4
    · unfold SSet.single? at h4
      split at h4
      · rename_i y hy
        simp [RHS.isEmpty, SSet.isEmpty, hy]
      · exact absurd h4 (by simp)
    · exact absurd h4 (by simp)
  have h3 : r.rhs.abstr.isEmpty = false := by
    unfold RHS.single? at h4
    split at h4
    · unfold SSet.single? at h4
      split at h4
      · rename_i y hy; simp [SSet.isEmpty, hy]
      · exact absurd h4 (by simp)
    · exact absurd h4 (by simp)
  refine ⟨s.log ("step\t" ++ s.site ++ "\t" ++ ("unify:" ++ toString u) ++ "\t" ++
    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size),
    rfl, rfl, rfl, rfl, ?_⟩
  simp only [stepP, State.log]
  rw [hd]
  dsimp only
  rw [h1]
  dsimp only
  rw [if_neg (by simp [h2]), if_neg (by simp [h3]), h4]
  rfl

/-- **Eager `unify` of a common partition.**  When a processed partition already has the
dequeued right-hand side, the step is a unification and no rule fires. -/
theorem stepP_common_branch {s : State} {r : LPart} {rest : PQueue} {u : Nat}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = some u) :
    ∃ st : State, st.incm = s.incm ∧ st.proc = s.proc ∧ st.env = s.env ∧ st.names = s.names ∧
      stepP pol aux s = (match unifyVars s.names r.lhs u rest s.proc s.env with
        | .error m => .died m st
        | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }) := by
  refine ⟨s.log ("step\t" ++ s.site ++ "\t" ++ ("common:" ++ toString u) ++ "\t" ++
    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size),
    rfl, rfl, rfl, rfl, ?_⟩
  simp only [stepP, State.log]
  rw [hd]
  dsimp only
  rw [h1]
  rfl

/-- The shape of a `learn` step. -/
theorem stepP_learn_shape {s s' : State} {r : LPart} {rest : PQueue}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : stepP pol aux s = .continue s') :
    s'.proc = s.proc.insertNP r ∧
      ∃ learned : SSet LPart, s'.incm = rest.concatP (trim learned s.proc).elems := by
  simp only [stepP, State.log] at h
  rw [hd] at h
  dsimp only at h
  rw [h1] at h
  dsimp only at h
  rw [if_neg (by simp [h2]), if_neg (by simp [h3]), h4] at h
  dsimp only at h
  cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
  | error m => rw [hlp] at h; exact absurd h (by simp)
  | ok w =>
    obtain ⟨learned, su⟩ := w
    rw [hlp] at h
    simp only [StepResult.continue.injEq] at h
    subst h
    exact ⟨rfl, learned, rfl⟩

/-- **... and a re-derivation that DOES pass `trim` is dropped at its next dequeue.**  If a
partition `x` equal to a processed `y` is dequeued, the dispatch takes the COMMON branch, and
when `x.lhs = y.lhs` that branch is `unify` at equal variables, which returns the queues
unchanged -- `x` is simply gone. -/
theorem common_self_dropsP {s : State} {rest : PQueue} {x : LPart}
    (hd : dequeuePol pol aux s.incm = some (x, rest)) (hlhs : s.proc.findRHS x.rhs = some x.lhs) :
    ∃ s' : State, stepP pol aux s = .continue s' ∧ s'.incm = rest ∧ s'.proc = s.proc ∧
      s'.env = s.env := by
  obtain ⟨st, hi, hp, he, hn, hstep⟩ := stepP_common_branch hd hlhs
  refine ⟨{ st with incm := rest, proc := s.proc, env := s.env }, ?_, rfl, rfl, rfl⟩
  rw [hstep, unifyVars, if_pos (by simp)]

/-- **`QueueHygiene` is preserved by every `continue` step.** -/
theorem stepP_queueHygiene {s s' : State} (hdj : s.flags.disjRule = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : stepP pol aux s = .continue s') : QueueHygiene s' := by
  rw [queueHygiene_iff] at h0 ⊢
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h0 x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h0 x (List.mem_append_right _ hx)
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).1
    have hrestMem : ∀ x ∈ rest.elems, x ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).2
    have hrest : ∀ x ∈ rest.elems, Avoids (Bound s.env) x.toConstraint :=
      fun x hx => hi0 x (hrestMem x hx)
    have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
    split at h
    · rename_i u hu
      have huB : ¬ Bound s.env u := findRHS_avoids hp0 hu
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        simp only [unifyVars] at hres
        split at hres
        · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
          obtain ⟨rfl, rfl, rfl⟩ := hres
          intro x hx
          rcases List.mem_append.mp hx with hx' | hx'
          · exact hrest x hx'
          · exact hp0 x hx'
        · rename_i hne
          have hvu : r.lhs ≠ u := by simpa using hne
          obtain ⟨hni, hnp⟩ := instantiate_avoids hvu huB hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs (.alias u) := (instantiate_env_len hres).2.2
          intro x hx
          refine Avoids.mono (B := fun w => Bound s.env w ∨ w = r.lhs) ?_ ?_
          · intro w0 hw0
            rw [Bound, henv] at hw0
            exact Env.contains_instantiate.mp hw0
          · rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx'
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨hni, hnp⟩ := makeEmpty_avoids hrest hp0 hres
          have henv : e = s.env.instantiate r.lhs .emptyRow := (makeEmpty_env_len hres).2.2
          intro x hx
          refine Avoids.mono (B := fun w => Bound s.env w ∨ w = r.lhs) ?_ ?_
          · intro w0 hw0
            rw [Bound, henv] at hw0
            exact Env.contains_instantiate.mp hw0
          · rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx'
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨hni, hnp⟩ := makeConcrete_avoids hrA.1 hrest hp0 hres
            intro x hx
            rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx'
        · split at h
          · rename_i u hsg
            have huB : ¬ Bound s.env u := by
              refine hrA.2 u ?_
              have : r.rhs.abstr.single? = some u := by
                unfold RHS.single? at hsg
                split at hsg
                · exact hsg
                · exact absurd hsg (by simp)
              exact mem_of_single? this
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simp only [unifyVars] at hres
              split at hres
              · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                obtain ⟨rfl, rfl, rfl⟩ := hres
                intro x hx
                rcases List.mem_append.mp hx with hx' | hx'
                · exact hrest x hx'
                · exact hp0 x hx'
              · rename_i hne
                have hvu : u ≠ r.lhs := by simpa using hne
                obtain ⟨hni, hnp⟩ := instantiate_avoids hvu hrA.1 hrest hp0 hres
                have henv : e = s.env.instantiate u (.alias r.lhs) := (instantiate_env_len hres).2.2
                intro x hx
                refine Avoids.mono (B := fun w => Bound s.env w ∨ w = u) ?_ ?_
                · intro w0 hw0
                  rw [Bound, henv] at hw0
                  exact Env.contains_instantiate.mp hw0
                · rcases List.mem_append.mp hx with hx' | hx'
                  · exact hni x hx'
                  · exact hnp x hx'
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              have hlearn := learnPartitions_avoids hdj hok (supAvoids_bound hfr) hrA.1 hrA.2
                hrest hp0 hlp
              intro x hx
              simp only [foldl_log_env]
              rcases List.mem_append.mp hx with hx' | hx'
              · exact concatP_avoids _ hrest
                  (fun d hd => hlearn d (SSet.mem_filter hd)) x hx'
              · exact insertNP_avoids hp0 (hi0 r hrMem) hx'

/-- **The reinstantiation panic is unreachable from a hygienic state.**  `instantiateType`'s
`die` fires exactly when the variable the step is about to bind is already bound, and every
one of the three variables a `step` can bind -- the dequeued left-hand side (`makeEmpty` at
the `empty` branch, `instantiate` at `common`), its lone variable part (`instantiate` at
`unify`) and the `common` partner -- is unbound at a hygienic state.  With
`run_queueHygiene` and `queueHygiene_initial` this closes `B1-FIX.md`'s open item: the panic
`L5-TERMINATION.md` §0 exhibits on the UNFIXED compiler has no path on the fixed one. -/
theorem queueHygiene_binds_unboundP {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) :
    s.env.contains r.lhs = false ∧
      (∀ u, r.rhs.abstr.contains u = true → s.env.contains u = false) ∧
      (∀ u, s.proc.findRHS r.rhs = some u → s.env.contains u = false) := by
  have hrMem : r ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).1
  rw [queueHygiene_iff] at h
  have hi0 : ∀ x ∈ s.incm.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h x (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, Avoids (Bound s.env) x.toConstraint :=
    fun x hx => h x (List.mem_append_right _ hx)
  have hrA := avoids_toConstraint_iff.mp (hi0 r hrMem)
  refine ⟨?_, ?_, ?_⟩
  · cases hc : s.env.contains r.lhs with
    | false => rfl
    | true => exact absurd hc hrA.1
  · intro u hu
    cases hc : s.env.contains u with
    | false => rfl
    | true => exact absurd hc (hrA.2 u (contains_nat_iff.mp hu))
  · intro u hu
    cases hc : s.env.contains u with
    | false => rfl
    | true => exact absurd hc (findRHS_avoids hp0 hu)

/-- **At a hygienic state neither link branch can die.**  This is the sharpest form of the
corollary: `instantiate` has exactly one error arm, and `queueHygiene_binds_unboundP` says the
variable it is about to bind is unbound at both of its call sites. -/
theorem stepP_link_no_death {s : State} (h : QueueHygiene s) {r : LPart} {rest : PQueue}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) :
    (∀ u, s.proc.findRHS r.rhs = some u →
        ∃ w, unifyVars s.names r.lhs u rest s.proc s.env = .ok w) ∧
      (∀ u, r.rhs.single? = some u →
        ∃ w, unifyVars s.names u r.lhs rest s.proc s.env = .ok w) := by
  obtain ⟨hlhs, habs, hcom⟩ := queueHygiene_binds_unboundP h hdq
  refine ⟨fun u _ => ?_, fun u hu => ?_⟩
  · unfold unifyVars
    split
    · exact ⟨_, rfl⟩
    · obtain ⟨ni, np, hok⟩ := instantiate_ok_of_unbound (ns := s.names) (u := u)
        (incm := rest) (proc := s.proc) hlhs
      exact ⟨_, hok⟩
  · have huB : s.env.contains u = false := by
      refine habs u ?_
      have : r.rhs.abstr.single? = some u := by
        unfold RHS.single? at hu
        split at hu
        · exact hu
        · exact absurd hu (by simp)
      exact contains_nat_iff.mpr (mem_of_single? this)
    unfold unifyVars
    split
    · exact ⟨_, rfl⟩
    · obtain ⟨ni, np, hok⟩ := instantiate_ok_of_unbound (ns := s.names) (u := r.lhs)
        (incm := rest) (proc := s.proc) huB
      exact ⟨_, hok⟩

/-- **`SupOk` and `SupFresh` are preserved by every `continue` step**, under the shipped
flags.  This is the rest of C2, and it makes `RunSupOk` a theorem (§5). -/
theorem stepP_supFresh {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : stepP pol aux s = .continue s') :
    SupOk s'.su ∧ (∀ z, Sup.Reach s'.su z → Sup.Reach s.su z) ∧ SupFresh s'.su (sys s') := by
  set Old : Var → Prop := fun w => w ∈ allVars (sys s) with hOldDef
  have hi0 : ∀ x ∈ s.incm.elems, OldPart Old x :=
    fun x hx => oldPart_of_mem_parts (List.mem_append_left _ hx)
  have hp0 : ∀ x ∈ s.proc.elems, OldPart Old x :=
    fun x hx => oldPart_of_mem_parts (List.mem_append_right _ hx)
  have hiA : ∀ (su0 : Sup), ∀ x ∈ s.incm.elems, Avoids (New Old su0) x.toConstraint :=
    fun su0 x hx => avoids_new_of_oldPart (hi0 x hx)
  have hpA : ∀ (su0 : Sup), ∀ x ∈ s.proc.elems, Avoids (New Old su0) x.toConstraint :=
    fun su0 x hx => avoids_new_of_oldPart (hp0 x hx)
  have heA : ∀ (su0 : Sup), ∀ b ∈ s.env.binds,
      Avoids (New Old su0) (EnvVal.toConstraint b.1 b.2) :=
    fun su0 b hb => avoids_new_of_mem_sys su0 (mem_sys_of_env hb)
  -- the conclusion, once the successor's parts and environment are known to avoid `New Old`
  have hfin : ∀ (t : State), (∀ z, Sup.Reach t.su z → Sup.Reach s.su z) →
      (∀ p ∈ t.parts, Avoids (New Old t.su) p.toConstraint) →
      (∀ b ∈ t.env.binds, Avoids (New Old t.su) (EnvVal.toConstraint b.1 b.2)) →
      SupFresh t.su (sys t) := by
    intro t hmono hparts henv
    refine supFresh_of_avoids_sys (Old := Old) (fun z hz => ?_) (avoids_sys_of hparts henv)
    exact fun hoz => hfr z (hmono z hz) hoz
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrMem : r ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).1
    have hrestMem : ∀ x ∈ rest.elems, x ∈ s.incm.elems := (shape_mem (dequeuePol_shape hdq)).2
    have hrestP : ∀ x ∈ rest.elems, OldPart Old x := fun x hx => hi0 x (hrestMem x hx)
    have hrestA : ∀ (su0 : Sup), ∀ x ∈ rest.elems, Avoids (New Old su0) x.toConstraint :=
      fun su0 x hx => avoids_new_of_oldPart (hrestP x hx)
    have hrO : OldPart Old r := hi0 r hrMem
    split at h
    · -- the `common` branch
      rename_i u hu
      have huO : Old u := by
        obtain ⟨x, hx, hxeq, hxl⟩ := findRHS_witness hu
        exact hxl ▸ (hp0 x hx).1
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ ?_⟩
        · intro p hp
          simp only [unifyVars] at hres
          split at hres
          · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
            obtain ⟨rfl, rfl, rfl⟩ := hres
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hrestA _ p hp'
            · exact hpA _ p hp'
          · rename_i hne
            have hvu : r.lhs ≠ u := by simpa using hne
            obtain ⟨hni, hnp⟩ := instantiate_avoids (B := New Old s.su) hvu
              (not_new_of_old huO) (hrestA _) (hpA _) hres
            refine Avoids.mono (B := fun w => New Old s.su w ∨ w = r.lhs)
              (fun w hw => Or.inl hw) ?_
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hni p hp'
            · exact hnp p hp'
        · simp only [unifyVars] at hres
          split at hres
          · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
            obtain ⟨-, -, rfl⟩ := hres
            exact heA _
          · have henv : e = s.env.instantiate r.lhs (.alias u) := (instantiate_env_len hres).2.2
            rw [henv]
            exact avoids_env_instantiate (heA _) (not_new_of_old hrO.1)
              (fun u0 hu0 => by
                simp only [EnvVal.alias.injEq] at hu0
                subst hu0
                exact not_new_of_old huO)
    · split at h
      · -- the `empty` branch
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨hni, hnp⟩ := makeEmpty_avoids (B := New Old s.su) (hrestA _) (hpA _) hres
          have henv : e = s.env.instantiate r.lhs .emptyRow := (makeEmpty_env_len hres).2.2
          refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ ?_⟩
          · intro p hp
            refine Avoids.mono (B := fun w => New Old s.su w ∨ w = r.lhs)
              (fun w hw => Or.inl hw) ?_
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hni p hp'
            · exact hnp p hp'
          · rw [henv]
            exact avoids_env_instantiate (heA _) (not_new_of_old hrO.1) (by simp)
      · split at h
        · -- the `concrete` branch
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨hni, hnp⟩ := makeConcrete_avoids (B := New Old s.su)
              (not_new_of_old hrO.1) (hrestA _) (hpA _) hres
            refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ (heA _)⟩
            intro p hp
            rcases List.mem_append.mp hp with hp' | hp'
            · exact hni p hp'
            · exact hnp p hp'
        · split at h
          · -- the `unify` branch
            rename_i u hsg
            have huO : Old u := by
              refine hrO.2 u ?_
              have : r.rhs.abstr.single? = some u := by
                unfold RHS.single? at hsg
                split at hsg
                · exact hsg
                · exact absurd hsg (by simp)
              exact mem_of_single? this
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              refine ⟨hok, fun _ hz => hz, hfin _ (fun _ hz => hz) ?_ ?_⟩
              · intro p hp
                simp only [unifyVars] at hres
                split at hres
                · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                  obtain ⟨rfl, rfl, rfl⟩ := hres
                  rcases List.mem_append.mp hp with hp' | hp'
                  · exact hrestA _ p hp'
                  · exact hpA _ p hp'
                · rename_i hne
                  have hvu : u ≠ r.lhs := by simpa using hne
                  obtain ⟨hni, hnp⟩ := instantiate_avoids (B := New Old s.su) hvu
                    (not_new_of_old hrO.1) (hrestA _) (hpA _) hres
                  refine Avoids.mono (B := fun w => New Old s.su w ∨ w = u)
                    (fun w hw => Or.inl hw) ?_
                  rcases List.mem_append.mp hp with hp' | hp'
                  · exact hni p hp'
                  · exact hnp p hp'
              · simp only [unifyVars] at hres
                split at hres
                · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                  obtain ⟨-, -, rfl⟩ := hres
                  exact heA _
                · have henv : e = s.env.instantiate u (.alias r.lhs) :=
                    (instantiate_env_len hres).2.2
                  rw [henv]
                  exact avoids_env_instantiate (heA _) (not_new_of_old huO)
                    (fun u0 hu0 => by
                      simp only [EnvVal.alias.injEq] at hu0
                      subst hu0
                      exact not_new_of_old hrO.1)
          · -- the `learn` branch
            cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              obtain ⟨hok2, hmono, hlearn⟩ := learnPartitions_new (Old := Old) hdj hcse hok
                hrO.1 hrO.2 hrestP hp0 hlp
              refine ⟨hok2, hmono, hfin _ hmono ?_ ?_⟩
              · intro p hp
                simp only [foldl_log_env] at hp ⊢
                rcases List.mem_append.mp hp with hp' | hp'
                · exact concatP_avoids (B := New Old su2) _ (hrestA _)
                    (fun d hd => hlearn d (SSet.mem_filter hd)) p hp'
                · exact insertNP_avoids (B := New Old su2) (hpA _) (hiA _ r hrMem) hp'
              · simp only [foldl_log_env]
                exact heA _

/-- **How many ids one `step` can draw**: at most one for `splitConcrete` and at most one per
processed partition, under the shipped flags.  (`Draws.learnPartitions_drawn` lifted to the
dispatch; every other branch leaves the supply alone.) -/
theorem stepP_drawn_le {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : stepP pol aux s = .continue s') :
    s'.su.drawn ≤ s.su.drawn + 1 + s.proc.elems.length := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        dsimp only
        omega
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          dsimp only
          omega
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            dsimp only
            omega
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              dsimp only
              omega
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              have hb := learnPartitions_drawn hdj hcse hlp
              dsimp only
              omega

/-- **The supply moves only at a `learn` step.**  Since a fresh id is the only way a new
variable enters the system, the vocabulary can grow only at a step that `learnChain_card`
already charges a new processed constraint for. -/
theorem stepP_su {s s' : State} (h : stepP pol aux s = .continue s') :
    s'.su = s.su ∨ IsLearnStepP pol aux s := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact Or.inl rfl
    · rename_i hfr
      split at h
      · rename_i hem
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Or.inl rfl
      · rename_i hem
        split at h
        · rename_i hab
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Or.inl rfl
        · rename_i hab
          split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact Or.inl rfl
          · rename_i hsg
            exact Or.inr ⟨r, rest, hdq, hfr, by simpa using hem, by simpa using hab, hsg⟩

/-- **A variable is bound at most once**, along every run. -/
theorem stepP_envNodup {s s' : State} (h0 : EnvNodup s) (h : stepP pol aux s = .continue s') :
    EnvNodup s' := by
  unfold EnvNodup at h0 ⊢
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        rcases unifyVars_env hres with rfl | ⟨-, hc, rfl⟩
        · exact h0
        · exact env_instantiate_nodup h0 hc
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨-, hc, rfl⟩ := makeEmpty_env_len hres
          exact env_instantiate_nodup h0 hc
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact h0
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              rcases unifyVars_env hres with rfl | ⟨-, hc, rfl⟩
              · exact h0
              · exact env_instantiate_nodup h0 hc
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simpa [foldl_log_env] using h0

/-- **Refinement for the three environment branches.**  Every `continue` step the loop takes
through `common`, `empty` or `unify` is a run of `LoopRel` between the systems the two states
denote. -/
theorem stepP_refines {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStepP pol aux s)
    (h : stepP pol aux s = .continue s') : LoopRun (sys s) (sys s') := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
    obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
    have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_incm (hrestMem x hx)
    have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_proc hx
    have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s :=
      fun b hb' => mem_sys_of_env hb'
    have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
    cases hfr : s.proc.findRHS r.rhs with
    | some u =>
      rw [hfr] at h
      dsimp only at h
      obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := findRHS_witness hfr
      by_cases hru : r.lhs = u
      · rw [unifyVars, if_pos (by simpa using hru)] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        exact Relation.ReflTransGen.single (LoopRel.weaken
          (sys_subset (fun x hx => by
            rcases List.mem_append.mp hx with hx' | hx'
            · exact hrestG x hx'
            · exact hprocG x hx') henvG))
      · have hc0 : x0.toConstraint = (⟨u, r.rhs, none⟩ : LPart).toConstraint := by
          rw [← hx0lhs]
          exact toConstraint_congr hw.coh (hw.proc x0 hx0) hrOk hx0eq
        have hlinkStep : LoopRel (sys s) (insert (mk r.lhs {u} (∅ : Row)) (sys s)) := by
          refine LoopRel.nongen (NonGenStep.commonPart ?_)
          have happ : CommonPartApp (sys s) r.toConstraint x0.toConstraint := by
            refine ⟨hrG, hprocG x0 hx0, ?_, ?_, ?_⟩
            · rw [hc0]; simpa using hru
            · rw [hc0]; rfl
            · rw [hc0]; rfl
          have hst := CommonPartStep.intro happ
          unfold commonPartResult at hst
          rw [hc0] at hst
          exact hst
        have hsubG1 : sys s ⊆ insert (mk r.lhs {u} (∅ : Row)) (sys s) :=
          Finset.subset_insert _ _
        cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨H, hrun, hsub, hni, hnp, he⟩ := unifyVars_run hw.coh hrestOk hw.proc
            (fun x hx => hsubG1 (hrestG x hx)) (fun x hx => hsubG1 (hprocG x hx))
            (fun b hb' => hsubG1 (henvG b hb')) (Finset.mem_insert_self _ _) hres
          exact (Relation.ReflTransGen.single hlinkStep).trans
            (hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
              rcases List.mem_append.mp hx with hx' | hx'
              · exact hni x hx'
              · exact hnp x hx') he)))
    | none =>
      rw [hfr] at h
      dsimp only at h
      by_cases hempty : r.rhs.isEmpty = true
      · rw [if_pos hempty] at h
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨H, hrun, hsub, hni, hnp, he⟩ := makeEmpty_run hw.coh hrestOk hw.proc
            hrestG hprocG henvG (by rw [← toConstraint_of_isEmpty hempty]; exact hrG) hres
          exact hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
            rcases List.mem_append.mp hx with hx' | hx'
            · exact hni x hx'
            · exact hnp x hx') he))
      · rw [if_neg hempty] at h
        have hsing : (r.rhs.single?).isSome = true := by
          rcases hb r rest hdq with hh | hh | hh
          · rw [hfr] at hh; exact absurd hh (by simp)
          · exact absurd hh hempty
          · exact hh
        obtain ⟨u, hu⟩ := Option.isSome_iff_exists.mp hsing
        have habs : ¬(r.rhs.abstr.isEmpty = true) := by
          intro hc
          have hnil : r.rhs.abstr.elems = [] := by simpa [SSet.isEmpty] using hc
          unfold RHS.single? at hu
          split at hu
          · unfold SSet.single? at hu
            rw [hnil] at hu
            exact absurd hu (by simp)
          · exact absurd hu (by simp)
        rw [if_neg habs, hu] at h
        dsimp only at h
        have hlinkStep : LoopRel (sys s) (insert (mk u {r.lhs} (∅ : Row)) (sys s)) := by
          refine LoopRel.linkSymm (a := r.lhs) (b := u) ?_
          rw [← toConstraint_of_single hu]; exact hrG
        have hsubG1 : sys s ⊆ insert (mk u {r.lhs} (∅ : Row)) (sys s) :=
          Finset.subset_insert _ _
        cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨H, hrun, hsub, hni, hnp, he⟩ := unifyVars_run hw.coh hrestOk hw.proc
            (fun x hx => hsubG1 (hrestG x hx)) (fun x hx => hsubG1 (hprocG x hx))
            (fun b hb' => hsubG1 (henvG b hb')) (Finset.mem_insert_self _ _) hres
          exact (Relation.ReflTransGen.single hlinkStep).trans
            (hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
              rcases List.mem_append.mp hx with hx' | hx'
              · exact hni x hx'
              · exact hnp x hx') he)))

/-- **Satisfiability is preserved along every `continue` step of the three branches.** -/
theorem stepP_sat {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStepP pol aux s)
    (h : stepP pol aux s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (stepP_refines hw hb h).sat

/-- **Refinement for the four non-minting branches.** -/
theorem stepP_refines_nonlearn {s s' : State} (hw : Wf s) (hb : NonLearnStepP pol aux s)
    (h : stepP pol aux s = .continue s') : LoopRun (sys s) (sys s') := by
  by_cases hlink : LinkOrEmptyStepP pol aux s
  · exact stepP_refines hw hlink h
  · -- the `concrete` branch
    simp only [stepP, State.log] at h
    split at h
    · exact absurd h (by simp)
    · rename_i r rest hdq
      obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
      obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
      have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
        fun x hx => mem_sys_of_incm (hrestMem x hx)
      have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s :=
        fun x hx => mem_sys_of_proc hx
      have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s :=
        fun b hb' => mem_sys_of_env hb'
      have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
      cases hfr : s.proc.findRHS r.rhs with
      | some u =>
        exact absurd (fun r0 rest0 hd0 => Or.inl (by
          rw [(dequeuePol_unique hdq hd0).1, hfr]; rfl)) hlink
      | none =>
        rw [hfr] at h
        dsimp only at h
        by_cases hempty : r.rhs.isEmpty = true
        · exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inl (by
            rw [(dequeuePol_unique hdq hd0).1]; exact hempty))) hlink
        · rw [if_neg hempty] at h
          have habs : r.rhs.abstr.isEmpty = true := by
            rcases hb r rest hdq with hh | hh | hh | hh
            · rw [hfr] at hh; exact absurd hh (by simp)
            · exact absurd hh hempty
            · exact hh
            · exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inr (by
                rw [(dequeuePol_unique hdq hd0).1]; exact hh))) hlink
          rw [if_pos habs] at h
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            obtain ⟨H, hrun, hsub, hni, hnp⟩ := makeConcrete_run hw.coh hrestOk hw.proc
              hrestG hprocG hrOk.conc
              (by rw [← abstr_isEmpty_toConstraint habs]; exact hrG) hres
            exact hrun.tail (LoopRel.weaken (sys_subset (fun x hx => by
              rcases List.mem_append.mp hx with hx' | hx'
              · exact hni x hx'
              · exact hnp x hx') (fun b hb' => hsub (henvG b hb'))))

/-- **Satisfiability is preserved along every `continue` step of the four non-minting
branches.** -/
theorem stepP_sat_nonlearn {s s' : State} (hw : Wf s) (hb : NonLearnStepP pol aux s)
    (h : stepP pol aux s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (stepP_refines_nonlearn hw hb h).sat

/-- **Refinement of the `learn` branch.**  At the shipped flags, and with the supply
invariant, every `learn` step is a run of `LoopRel`. -/
theorem stepP_refines_learn {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (hb : ¬ NonLearnStepP pol aux s) (h : stepP pol aux s = .continue s') :
    LoopRun (sys s) (sys s') := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
    obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
    have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_incm (hrestMem x hx)
    have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_proc hx
    have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s :=
      fun b hb' => mem_sys_of_env hb'
    have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
    -- the branch conditions
    have hfr0 : s.proc.findRHS r.rhs = none := by
      cases hh : s.proc.findRHS r.rhs with
      | none => rfl
      | some u =>
        exact absurd (fun r0 rest0 hd0 => Or.inl (by
          rw [(dequeuePol_unique hdq hd0).1, hh]; rfl)) hb
    have hne : r.rhs.isEmpty = false := by
      cases hh : r.rhs.isEmpty with
      | false => rfl
      | true =>
        exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inl (by
          rw [(dequeuePol_unique hdq hd0).1]; exact hh))) hb
    have hab : r.rhs.abstr.isEmpty = false := by
      cases hh : r.rhs.abstr.isEmpty with
      | false => rfl
      | true =>
        exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inr (Or.inl (by
          rw [(dequeuePol_unique hdq hd0).1]; exact hh)))) hb
    have hsg : r.rhs.single? = none := by
      cases hh : r.rhs.single? with
      | none => rfl
      | some u =>
        exact absurd (fun r0 rest0 hd0 => Or.inr (Or.inr (Or.inr (by
          rw [(dequeuePol_unique hdq hd0).1, hh]; rfl)))) hb
    rw [hfr0] at h
    dsimp only at h
    rw [if_neg (by simp [hne]), if_neg (by simp [hab]), hsg] at h
    dsimp only at h
    cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
    | error m => rw [hlp] at h; exact absurd h (by simp)
    | ok w =>
      obtain ⟨learned, su2⟩ := w
      rw [hlp] at h
      simp only [StepResult.continue.injEq] at h
      subst h
      have hrc : mk r.lhs r.rhs.abstr.fs (cfs r.rhs.conc) ∈ sys s := by
        rw [← toConstraint_eq]; exact hrG
      obtain ⟨H, hrunH, hsubH, hmH, hokH, hfrH⟩ :=
        learnPartitions_run hw.coh hem hdj hcse hok hfr hw.proc hrestOk hrOk.rhsOk
          hprocG hrestG hrc
          (by
            -- the syntactic lookup missing really is `¬ Named (sys s)`
            intro hcne htwo hnone
            rintro ⟨d, hd, hvset, hconc⟩
            rcases mem_sys.mp hd with ⟨p, hp, rfl⟩ | ⟨be, hbe, rfl⟩
            · have hpe : p.rhs.eqv (RHS.ofAbstr r.rhs.abstr) = true := by
                have hnil : p.rhs.conc.elems = [] := by
                  by_contra hcon
                  obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil _ hcon
                  have : y.n ∈ p.toConstraint.conc :=
                    List.mem_toFinset.mpr (List.mem_map.mpr ⟨y, hy, rfl⟩)
                  rw [hconc] at this
                  exact absurd this (Finset.notMem_empty _)
                have hab2 : p.rhs.abstr.elems.toFinset = r.rhs.abstr.elems.toFinset := by
                  have := hvset
                  rw [LPart.vset_toConstraint] at this
                  exact this
                rw [RHS.eqv, Bool.and_eq_true]
                refine ⟨(SSet.eqv_iff_toFinset (hw.nodup hp).1 hrOk.abstr).mpr hab2, ?_⟩
                rw [SSet.eqv, Bool.and_eq_true]
                exact ⟨by simp [SSet.size, hnil, RHS.ofAbstr, SSet.empty],
                  by simp [SSet.subsetOf, hnil]⟩
              rcases List.mem_append.mp hp with hp' | hp'
              · rcases shape_mem_or (dequeuePol_shape hdq) p hp' with hp'' | rfl
                · exact absurd hpe (by rw [findRHS3_none hnone p (Or.inl hp'')]; simp)
                · exact hcne (by rw [← hconc]; rfl)
              · exact absurd hpe (by rw [findRHS3_none hnone p (Or.inr (Or.inl hp'))]; simp)
            · obtain ⟨w0, val0⟩ := be
              cases val0 with
              | emptyRow =>
                have : (0 : Nat) < 2 := by omega
                rw [← hvset] at htwo
                simp only [EnvVal.toConstraint, vset_mk, Finset.card_empty] at htwo
                omega
              | «alias» z =>
                rw [← hvset] at htwo
                simp only [EnvVal.toConstraint, vset_mk, Finset.card_singleton] at htwo
                omega)
          hlp
      -- the queue insertion
      obtain ⟨H2, hrun2, hsub2, hres⟩ := concatP_run hw.coh (trim learned s.proc).elems
        hrestOk (fun x hx =>
          (SOk.trim (L := s.labels) (q := s.proc)
            (learnPartitions_ok hrOk.rhsOk hw.proc hlp)) x hx)
        (fun x hx => hsubH (hrestG x hx))
        (fun x hx => hmH x (SSet.mem_filter hx))
      refine ((hrunH.trans hrun2).tail (LoopRel.weaken (sys_subset (fun x hx => ?_) ?_)))
      · rcases List.mem_append.mp hx with hx' | hx'
        · exact hres x hx'
        · rcases mem_insertNP hx' with hx'' | rfl
          · exact hsub2 (hsubH (hprocG x hx''))
          · exact hsub2 (hsubH hrG)
      · intro b hb'
        simp only [foldl_log_env] at hb'
        exact hsub2 (hsubH (henvG b hb'))

/-- **Refinement, for EVERY dispatch branch.**  This is the plan's (i) for the whole of
`step`, at the shipped flags and under the supply invariant. -/
theorem stepP_refines_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : stepP pol aux s = .continue s') : LoopRun (sys s) (sys s') := by
  by_cases hb : NonLearnStepP pol aux s
  · exact stepP_refines_nonlearn hw hb h
  · exact stepP_refines_learn hw hem hdj hcse hok hfr hb h

/-- **Satisfiability is preserved by every `continue` step.** -/
theorem stepP_sat_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : stepP pol aux s = .continue s') : SSat (sys s) → SSat (sys s') :=
  (stepP_refines_all hw hem hdj hcse hok hfr h).sat

/-- **The `common` branch at `u = r.lhs` changes nothing.**  `unify` at equal variables
returns the queues and the environment untouched, and the dequeued partition is
`Partition.equals` to the processed partition the lookup found -- so the system the state
denotes is the SAME, and the "deletion" R2.5 row 2 names is the identity on `sys`. -/
theorem common_eq_sysP {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some r.lhs)
    (h : stepP pol aux s = .continue s') : sys s' = sys s := by
  obtain ⟨t, hstep, hi, hp, he⟩ := common_self_dropsP hdq hfr
  rw [h] at hstep
  have hst : s' = t := by injection hstep
  subst hst
  obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := findRHS_witness hfr
  obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
  have hx0r : x0.toConstraint = r.toConstraint :=
    eqv_toConstraint hw.coh (hw.proc x0 hx0) (hw.incm r hrMem)
      (by simp only [LPart.eqv, Bool.and_eq_true]; exact ⟨by simp [hx0lhs], hx0eq⟩)
  apply Finset.Subset.antisymm
  · refine sys_subset (fun x hx => ?_) (fun b hb => by rw [he] at hb; exact mem_sys_of_env hb)
    rcases List.mem_append.mp hx with hx' | hx'
    · rw [hi] at hx'; exact mem_sys_of_incm (hrestMem x hx')
    · rw [hp] at hx'; exact mem_sys_of_proc hx'
  · refine sys_subset (fun x hx => ?_) (fun b hb => ?_)
    · rcases List.mem_append.mp hx with hx' | hx'
      · rcases shape_mem_or (dequeuePol_shape hdq) x hx' with hx'' | rfl
        · exact mem_sys_of_incm (by rw [hi]; exact hx'')
        · rw [← hx0r]; exact mem_sys_of_proc (by rw [hp]; exact hx0)
      · exact mem_sys_of_proc (by rw [hp]; exact hx')
    · exact mem_sys_of_env (by rw [he]; exact hb)

/-- **R2.5 row 2, as a `LoopStrict` step.** -/
theorem stepP_strict_common_eq {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some r.lhs)
    (h : stepP pol aux s = .continue s') : LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  rw [common_eq_sysP hw hdq hfr h]
  exact ⟨LoopStrict.drop (Finset.Subset.refl _) (NoLoss.refl _), Conserv.of_subset
    (Finset.Subset.refl _), Finset.Subset.refl _⟩

/-- **R2.5 row 4, as a `LoopStrict` step.**  The `empty` branch is one `emptyRemove`: `v <- ()`
is retained in the environment, satisfiability is preserved (L3's `stepP_sat`), and nothing is
lost. -/
theorem stepP_strict_empty {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hem : r.rhs.isEmpty = true) (h : stepP pol aux s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  obtain ⟨-, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
  have hlink : LinkOrEmptyStepP pol aux s := by
    intro r0 rest0 hd0
    rw [(dequeuePol_unique hdq hd0).1]
    exact Or.inr (Or.inl hem)
  obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := stepP_empty_branch hdq hfr hem
  rw [h] at hstep
  cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
  | error m => rw [hres] at hstep; exact absurd hstep (by simp)
  | ok w =>
    obtain ⟨ni, np, e⟩ := w
    rw [hres] at hstep
    simp only [StepResult.continue.injEq] at hstep
    have hi' : s'.incm = ni := by rw [hstep]
    have hp' : s'.proc = np := by rw [hstep]
    have he' : s'.env = e := by rw [hstep]
    obtain ⟨hvG, hincm, hproc, henv⟩ := makeEmpty_noLoss hw.coh hrestOk hw.proc
      (G := sys s') (fun x hx => mem_sys_of_incm (by rw [hi']; exact hx))
      (fun x hx => mem_sys_of_proc (by rw [hp']; exact hx))
      (fun b hb => mem_sys_of_env (by rw [he']; exact hb)) hres
    obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
    have hvsys : mk r.lhs ∅ (∅ : Row) ∈ sys s := by
      rw [← toConstraint_of_isEmpty hem]; exact mem_sys_of_incm hrMem
    -- FORWARD: nothing invented
    have hfS := makeEmpty_forward hw.coh (redClosed_sent (sys s)) hrestOk hw.proc
      (fun x hx rho hm => hm _ (mem_sys_of_incm (hrestMem x hx)))
      (fun x hx rho hm => hm _ (mem_sys_of_proc hx))
      (fun b hb rho hm => hm _ (mem_sys_of_env hb))
      (fun rho hm => hm _ hvsys)
      (fun _ _ _ hP rho hm => sat_erase_of_empty (sat_empty_iff.mp (hm _ hvsys)) (hP rho hm))
      (fun _ _ hP hx rho hm => emptyProp_sat (hP rho hm) (hm _ hvsys) hx) hres
    -- FORWARD: no variable invented
    have hfV := makeEmpty_forward hw.coh (redClosed_voc (allVars (sys s))) hrestOk hw.proc
      (fun x hx => vocIn_sys (mem_sys_of_incm (hrestMem x hx)))
      (fun x hx => vocIn_sys (mem_sys_of_proc hx))
      (fun b hb => vocIn_sys (mem_sys_of_env hb))
      (vocIn_sys hvsys)
      (fun a S K hP w hw => by
        rw [lhs_mk, vset_mk] at hw
        refine hP ?_
        rw [lhs_mk, vset_mk]
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact Finset.mem_insert_self _ _
        · exact Finset.mem_insert_of_mem (Finset.mem_of_mem_erase hw'))
      (fun S x hP hx w hw => by
        rw [lhs_mk, vset_mk] at hw
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact hP (by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_of_mem hx)
        · exact absurd hw' (Finset.notMem_empty w)) hres
    have hvoc : allVars (sys s') ⊆ allVars (sys s) :=
      allVars_of_vocIn (sys_forall (s := s')
        (fun x hx => hfV.1 x (by rw [← hi']; exact hx))
        (fun x hx => hfV.2.1 x (by rw [← hp']; exact hx))
        (fun b hb => hfV.2.2 b (by rw [← he']; exact hb)))
    have hcons : Conserv (sys s) (sys s') :=
      sys_forall (s := s')
        (fun x hx => hfS.1 x (by rw [← hi']; exact hx))
        (fun x hx => hfS.2.1 x (by rw [← hp']; exact hx))
        (fun b hb => hfS.2.2 b (by rw [← he']; exact hb))
    refine ⟨LoopStrict.requeue hvoc hcons ?_, hcons, hvoc⟩
    intro c hc
    rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
    · rcases shape_mem_or (dequeuePol_shape hdq) p hp with hp' | rfl
      · exact hincm p hp'
      · rw [toConstraint_of_isEmpty hem]
        exact fun rho hm => hm _ hvG
    · exact hproc p hp
    · exact henv b hb

/-- **R2.5 rows 3 and 5, as `LoopStrict` steps: the `common` branch.** -/
theorem stepP_strict_common {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue} {u : Nat}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) (hfr : s.proc.findRHS r.rhs = some u)
    (h : stepP pol aux s = .continue s') : LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  have hlink : LinkOrEmptyStepP pol aux s := by
    intro r0 rest0 hd0
    rw [(dequeuePol_unique hdq hd0).1]
    exact Or.inl (by rw [hfr]; simp)
  by_cases hru : r.lhs = u
  · exact stepP_strict_common_eq hw hdq (by rw [hru]; exact hfr) h
  · obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
    obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := stepP_common_branch hdq hfr
    rw [h] at hstep
    cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
    | error m => rw [hres] at hstep; exact absurd hstep (by simp)
    | ok w =>
      obtain ⟨ni, np, e⟩ := w
      rw [hres] at hstep
      simp only [StepResult.continue.injEq] at hstep
      have hi' : s'.incm = ni := by rw [hstep]
      have hp' : s'.proc = np := by rw [hstep]
      have he' : s'.env = e := by rw [hstep]
      have hinst : instantiate s.names r.lhs u rest s.proc s.env = .ok (ni, np, e) := by
        rw [← hres]; unfold unifyVars; rw [if_neg (by simpa using hru)]
      obtain ⟨hlinkG, hincm, hproc, henv⟩ := instantiate_noLoss hw.coh hrestOk hw.proc
        (G := sys s') (fun x hx => mem_sys_of_incm (by rw [hi']; exact hx))
        (fun x hx => mem_sys_of_proc (by rw [hp']; exact hx))
        (fun b hb => mem_sys_of_env (by rw [he']; exact hb)) hinst
      obtain ⟨x0, hx0, hx0eq, hx0lhs⟩ := findRHS_witness hfr
      have hc0 : x0.toConstraint = (⟨u, r.rhs, none⟩ : LPart).toConstraint := by
        rw [← hx0lhs]
        exact toConstraint_congr hw.coh (hw.proc x0 hx0) hrOk hx0eq
      obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
      have hrsys : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
      have hx0sys : x0.toConstraint ∈ sys s := mem_sys_of_proc hx0
      have hrshape : r.toConstraint
          = mk r.lhs (r.rhs.abstr.elems.toFinset)
              ((r.rhs.conc.elems.map Lbl.n).toFinset) := rfl
      have hx0shape : x0.toConstraint
          = mk u (r.rhs.abstr.elems.toFinset)
              ((r.rhs.conc.elems.map Lbl.n).toFinset) := hc0
      have hlinkS : SEntails (sys s) (mk r.lhs {u} (∅ : Row)) :=
        redClosed_sent (sys s) r.lhs u _ _ (fun rho hm => hrshape ▸ hm _ hrsys)
          (fun rho hm => hx0shape ▸ hm _ hx0sys)
      have huV : u ∈ allVars (sys s) := by
        have := lhs_mem_allVars hx0sys
        rwa [hx0shape, lhs_mk] at this
      have hrV : r.lhs ∈ allVars (sys s) := by
        have := lhs_mem_allVars hrsys
        rwa [hrshape, lhs_mk] at this
      have hlinkV : VocIn (allVars (sys s)) (mk r.lhs {u} (∅ : Row)) := by
        intro w hw
        rw [lhs_mk, vset_mk] at hw
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact hrV
        · rw [Finset.mem_singleton] at hw'; subst hw'; exact huV
      have hfS := instantiate_forward hw.coh (redClosed_sent (sys s)) hrestOk hw.proc
        (fun x hx rho hm => hm _ (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx rho hm => hm _ (mem_sys_of_proc hx))
        (fun b hb rho hm => hm _ (mem_sys_of_env hb)) hlinkS
        (fun q hq => replace_forward_sent (by simpa using hru) hlinkS hq)
        (fun w hP rho hm => sat_link_iff.mpr
          ((sat_link_iff.mp (hP rho hm)).trans (sat_link_iff.mp (hlinkS rho hm)))) hinst
      have hfV := instantiate_forward hw.coh (redClosed_voc (allVars (sys s))) hrestOk hw.proc
        (fun x hx => vocIn_sys (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx => vocIn_sys (mem_sys_of_proc hx))
        (fun b hb => vocIn_sys (mem_sys_of_env hb)) hlinkV
        (fun q hq => replace_forward_voc huV hq)
        (fun w hP y hy => by
          rw [lhs_mk, vset_mk] at hy
          rcases Finset.mem_insert.mp hy with rfl | hy'
          · exact hP (by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_self _ _)
          · rw [Finset.mem_singleton] at hy'; subst hy'; exact huV) hinst
      have hvoc : allVars (sys s') ⊆ allVars (sys s) :=
        allVars_of_vocIn (sys_forall (s := s')
          (fun x hx => hfV.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfV.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfV.2.2 b (by rw [← he']; exact hb)))
      have hcons : Conserv (sys s) (sys s') :=
        sys_forall (s := s')
          (fun x hx => hfS.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfS.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfS.2.2 b (by rw [← he']; exact hb))
      refine ⟨LoopStrict.requeue hvoc hcons ?_, hcons, hvoc⟩
      intro c hc
      rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
      · rcases shape_mem_or (dequeuePol_shape hdq) p hp with hp' | rfl
        · exact hincm p hp'
        · intro rho hm
          have h1 : Sat rho ((⟨u, p.rhs, none⟩ : LPart).toConstraint) :=
            hc0 ▸ hproc x0 hx0 rho hm
          have h2 : rho p.lhs = rho u := sat_link_iff.mp (hm _ hlinkG)
          have hshape : (⟨u, p.rhs, none⟩ : LPart).toConstraint
              = mk u (p.rhs.abstr.elems.toFinset)
                  ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
          have hshape2 : p.toConstraint
              = mk p.lhs (p.rhs.abstr.elems.toFinset)
                  ((p.rhs.conc.elems.map Lbl.n).toFinset) := rfl
          rw [hshape] at h1
          rw [hshape2]
          exact sat_lhs_congr h2 h1
      · exact hproc p hp
      · exact henv b hb

/-- **R2.5 row 5, as a `LoopStrict` step: the lone-variable `unify` branch**, where the
arguments are SWAPPED -- `unify(u, v)` on a dequeued `v <- (u)` binds `u`, not `v`. -/
theorem stepP_strict_unify {s s' : State} (hw : Wf s) {r : LPart} {rest : PQueue} {u : Nat}
    (hdq : dequeuePol pol aux s.incm = some (r, rest)) (hfr : s.proc.findRHS r.rhs = none)
    (hsg : r.rhs.single? = some u) (h : stepP pol aux s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  have hlink : LinkOrEmptyStepP pol aux s := by
    intro r0 rest0 hd0
    rw [(dequeuePol_unique hdq hd0).1]
    exact Or.inr (Or.inr (by rw [hsg]; simp))
  obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
  obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := stepP_unify_branch hdq hfr hsg
  rw [h] at hstep
  cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
  | error m => rw [hres] at hstep; exact absurd hstep (by simp)
  | ok w =>
    obtain ⟨ni, np, e⟩ := w
    rw [hres] at hstep
    simp only [StepResult.continue.injEq] at hstep
    have hi' : s'.incm = ni := by rw [hstep]
    have hp' : s'.proc = np := by rw [hstep]
    have he' : s'.env = e := by rw [hstep]
    have hrc : r.toConstraint = mk r.lhs {u} (∅ : Row) := toConstraint_of_single hsg
    by_cases hur : u = r.lhs
    · -- `unify` at equal variables is the identity, and `r` is a self-unification
      have hids : ni = rest ∧ np = s.proc ∧ e = s.env := by
        rw [unifyVars, if_pos (by simpa using hur)] at hres
        rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
        exact ⟨hres.1.symm, hres.2.1.symm, hres.2.2.symm⟩
      have hsub : sys s' ⊆ sys s := by
        refine sys_subset (fun x hx => ?_) (fun b hb => ?_)
        · rcases List.mem_append.mp hx with hx' | hx'
          · rw [hi', hids.1] at hx'
            exact mem_sys_of_incm ((shape_mem (dequeuePol_shape hdq)).2 x hx')
          · rw [hp', hids.2.1] at hx'; exact mem_sys_of_proc hx'
        · rw [he', hids.2.2] at hb; exact mem_sys_of_env hb
      have hnl : NoLoss (sys s) (sys s') := by
        intro c hc rho hm
        rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
        · rcases shape_mem_or (dequeuePol_shape hdq) p hp with hp' | rfl
          · exact hm _ (mem_sys_of_incm (by rw [hi', hids.1]; exact hp'))
          · rw [hrc, hur]; exact sat_self rho p.lhs
        · exact hm _ (mem_sys_of_proc (by rw [hp', hids.2.1]; exact hp))
        · exact hm _ (mem_sys_of_env (by rw [he', hids.2.2]; exact hb))
      exact ⟨LoopStrict.drop hsub hnl, Conserv.of_subset hsub, allVars_mono hsub⟩
    · have hinst : instantiate s.names u r.lhs rest s.proc s.env = .ok (ni, np, e) := by
        rw [← hres]; unfold unifyVars; rw [if_neg (by simpa using hur)]
      obtain ⟨hlinkG, hincm, hproc, henv⟩ := instantiate_noLoss hw.coh hrestOk hw.proc
        (G := sys s') (fun x hx => mem_sys_of_incm (by rw [hi']; exact hx))
        (fun x hx => mem_sys_of_proc (by rw [hp']; exact hx))
        (fun b hb => mem_sys_of_env (by rw [he']; exact hb)) hinst
      obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
      have hrsys : mk r.lhs {u} (∅ : Row) ∈ sys s := by
        rw [← hrc]; exact mem_sys_of_incm hrMem
      have hlinkS : SEntails (sys s) (mk u {r.lhs} (∅ : Row)) :=
        fun rho hm => linkSymm_sat (hm _ hrsys)
      have hrV : r.lhs ∈ allVars (sys s) := lhs_mem_allVars hrsys
      have huV : u ∈ allVars (sys s) :=
        mem_allVars hrsys (Or.inr (by rw [vset_mk]; exact Finset.mem_singleton_self u))
      have hlinkV : VocIn (allVars (sys s)) (mk u {r.lhs} (∅ : Row)) := by
        intro w hw
        rw [lhs_mk, vset_mk] at hw
        rcases Finset.mem_insert.mp hw with rfl | hw'
        · exact huV
        · rw [Finset.mem_singleton] at hw'; subst hw'; exact hrV
      have hfS := instantiate_forward hw.coh (redClosed_sent (sys s)) hrestOk hw.proc
        (fun x hx rho hm => hm _ (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx rho hm => hm _ (mem_sys_of_proc hx))
        (fun b hb rho hm => hm _ (mem_sys_of_env hb)) hlinkS
        (fun q hq => replace_forward_sent (by simpa using hur) hlinkS hq)
        (fun w hP rho hm => sat_link_iff.mpr
          ((sat_link_iff.mp (hP rho hm)).trans (sat_link_iff.mp (hlinkS rho hm)))) hinst
      have hfV := instantiate_forward hw.coh (redClosed_voc (allVars (sys s))) hrestOk hw.proc
        (fun x hx => vocIn_sys (mem_sys_of_incm (hrestMem x hx)))
        (fun x hx => vocIn_sys (mem_sys_of_proc hx))
        (fun b hb => vocIn_sys (mem_sys_of_env hb)) hlinkV
        (fun q hq => replace_forward_voc hrV hq)
        (fun w hP y hy => by
          rw [lhs_mk, vset_mk] at hy
          rcases Finset.mem_insert.mp hy with rfl | hy'
          · exact hP (by rw [lhs_mk, vset_mk]; exact Finset.mem_insert_self _ _)
          · rw [Finset.mem_singleton] at hy'; subst hy'; exact hrV) hinst
      have hvoc : allVars (sys s') ⊆ allVars (sys s) :=
        allVars_of_vocIn (sys_forall (s := s')
          (fun x hx => hfV.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfV.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfV.2.2 b (by rw [← he']; exact hb)))
      have hcons : Conserv (sys s) (sys s') :=
        sys_forall (s := s')
          (fun x hx => hfS.1 x (by rw [← hi']; exact hx))
          (fun x hx => hfS.2.1 x (by rw [← hp']; exact hx))
          (fun b hb => hfS.2.2 b (by rw [← he']; exact hb))
      refine ⟨LoopStrict.requeue hvoc hcons ?_, hcons, hvoc⟩
      intro c hc
      rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
      · rcases shape_mem_or (dequeuePol_shape hdq) p hp with hp' | rfl
        · exact hincm p hp'
        · intro rho hm
          rw [hrc]
          exact linkSymm_sat (hm _ hlinkG)
      · exact hproc p hp
      · exact henv b hb

/-- **Refinement against `LoopStrict` for the `common`, `empty` and `unify` branches** -- the
analogue of L3's `Refine.step_refines`, with every use of `LoopRel.weaken` replaced by one of
the licensed deletions of R2.5 rows 2-5.  `LoopRel.weaken` appears nowhere in this proof or in
anything it depends on. -/
theorem stepP_strict {s s' : State} (hw : Wf s) (hb : LinkOrEmptyStepP pol aux s)
    (h : stepP pol aux s = .continue s') :
    LoopStrict (sys s) (sys s') ∧ Conserv (sys s) (sys s') ∧
      allVars (sys s') ⊆ allVars (sys s) := by
  cases hdq : dequeuePol pol aux s.incm with
  | none =>
    exfalso
    simp only [stepP] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    cases hfr : s.proc.findRHS r.rhs with
    | some u => exact stepP_strict_common hw hdq hfr h
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · exact stepP_strict_empty hw hdq hfr hem h
      · rcases hb r rest hdq with hh | hh | hh
        · rw [hfr] at hh; exact absurd hh (by simp)
        · exact absurd hh hem
        · obtain ⟨u, hu⟩ := Option.isSome_iff_exists.mp hh
          exact stepP_strict_unify hw hdq hfr hu h

theorem stepP_learn_env {s s' : State} {r : LPart} {rest : PQueue}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : stepP pol aux s = .continue s') : s'.env = s.env := by
  simp only [stepP, State.log] at h
  rw [hd] at h
  dsimp only at h
  rw [h1] at h
  dsimp only at h
  rw [if_neg (by simp [h2]), if_neg (by simp [h3]), h4] at h
  dsimp only at h
  cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
  | error m => rw [hlp] at h; exact absurd h (by simp)
  | ok w =>
    obtain ⟨learned, su⟩ := w
    rw [hlp] at h
    simp only [StepResult.continue.injEq] at h
    subst h
    simp [foldl_log_env]

/-- **The `learn` branch adds and never removes.** -/
theorem stepP_learn_sys_mono {s s' : State} {r : LPart} {rest : PQueue}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : stepP pol aux s = .continue s') : sys s ⊆ sys s' := by
  obtain ⟨hproc, learned, hincm⟩ := stepP_learn_shape hd h1 h2 h3 h4 h
  have henv := stepP_learn_env hd h1 h2 h3 h4 h
  refine sys_subset (fun x hx => ?_) (fun b hb => mem_sys_of_env (by rw [henv]; exact hb))
  rcases List.mem_append.mp hx with hx' | hx'
  · rcases shape_mem_or (dequeuePol_shape hd) x hx' with hx'' | rfl
    · exact mem_sys_of_incm (by rw [hincm]; exact mem_concatP_of_mem _ hx'')
    · exact mem_sys_of_proc (by rw [hproc]; exact learn_insertNP_self h1 h4)
  · exact mem_sys_of_proc (by rw [hproc]; exact mem_insertNP_of_mem hx')

/-- ... so it loses nothing, trivially. -/
theorem stepP_learn_noLoss {s s' : State} {r : LPart} {rest : PQueue}
    (hd : dequeuePol pol aux s.incm = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : stepP pol aux s = .continue s') : NoLoss (sys s) (sys s') :=
  NoLoss.of_subset (stepP_learn_sys_mono hd h1 h2 h3 h4 h)

/-- **The loop loses information at most at the `concrete` branch.**  `common`, `empty`,
`unify` and `learn` all leave a system that entails everything the system they left had. -/
theorem stepP_noLoss {s s' : State} (hw : Wf s) (hb : NonConcreteStepP pol aux s)
    (h : stepP pol aux s = .continue s') : NoLoss (sys s) (sys s') := by
  cases hdq : dequeuePol pol aux s.incm with
  | none =>
    exfalso
    simp only [stepP] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    cases hfr : s.proc.findRHS r.rhs with
    | some u => exact (stepP_strict_common hw hdq hfr h).1.no_loss
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · exact (stepP_strict_empty hw hdq hfr hem h).1.no_loss
      · cases hsg : r.rhs.single? with
        | some u => exact (stepP_strict_unify hw hdq hfr hsg h).1.no_loss
        | none =>
          have habs : r.rhs.abstr.isEmpty = false := by
            rcases hb r rest hdq with hh | hh | hh
            · rw [hfr] at hh; exact absurd hh (by simp)
            · exact absurd hh hem
            · exact hh
          exact stepP_learn_noLoss hdq hfr (by simpa using hem) habs hsg h

/-- **A satisfiable state satisfies the proviso.**  Two bare concrete definitions of one
variable that disagree have no model. -/
theorem bareAgreeP_of_sat {s : State} (hsat : SSat (sys s)) : BareAgreeP pol aux s := by
  intro r rest hdq habs x hx hlv hxabs
  obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
  have hrG : mk r.lhs ∅ (cfs r.rhs.conc) ∈ sys s := by
    rw [← abstr_isEmpty_toConstraint habs]; exact mem_sys_of_incm hrMem
  have hxG : mk r.lhs ∅ (cfs x.rhs.conc) ∈ sys s := by
    rw [← hlv, ← abstr_isEmpty_toConstraint hxabs]
    rcases List.mem_append.mp hx with hx' | hx'
    · exact mem_sys_of_incm (hrestMem x hx')
    · exact mem_sys_of_proc hx'
  by_contra hne
  exact bare_refutes hxG hrG hne hsat

/-- **`NoLoss` at the `concrete` branch** — the missing fifth branch of `StrictStep.
stepP_noLoss`, under the proviso. -/
theorem stepP_noLoss_concrete {s s' : State} (hw : Wf s) (hba : BareAgreeP pol aux s)
    {r : LPart} {rest : PQueue} (hdq : dequeuePol pol aux s.incm = some (r, rest))
    (hfr : s.proc.findRHS r.rhs = none) (hem : r.rhs.isEmpty = false)
    (habs : r.rhs.abstr.isEmpty = true) (h : stepP pol aux s = .continue s') :
    NoLoss (sys s) (sys s') := by
  obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
  obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
  simp only [stepP, State.log] at h
  rw [hdq] at h
  dsimp only at h
  rw [hfr] at h
  dsimp only at h
  rw [if_neg (by simp [hem]), if_pos habs] at h
  cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
  | error m => rw [hres] at h; exact absurd h (by simp)
  | ok w =>
    obtain ⟨ni, np⟩ := w
    rw [hres] at h
    simp only [StepResult.continue.injEq] at h
    have hniG : ∀ x ∈ ni.elems, SEntails (sys s') x.toConstraint := by
      intro x hx rho hm
      exact hm _ (by rw [← h]; exact mem_sys_of_incm hx)
    have hnpG : ∀ x ∈ np.elems, SEntails (sys s') x.toConstraint := by
      intro x hx rho hm
      exact hm _ (by rw [← h]; exact mem_sys_of_proc hx)
    have henvG : ∀ b ∈ s.env.binds, EnvVal.toConstraint b.1 b.2 ∈ sys s' := by
      intro b hb
      rw [← h]
      exact mem_sys_of_env hb
    have hbare : ∀ x ∈ rest.elems ++ s.proc.elems, x.lhs = r.lhs →
        x.rhs.abstr.isEmpty = true → cfs x.rhs.conc = cfs r.rhs.conc :=
      hba r rest hdq habs
    have hall := makeConcrete_noLoss hw.coh hrestOk hw.proc hrOk.conc hniG hnpG hbare hres
    have hkey : SEntails (sys s') (mk r.lhs ∅ (cfs r.rhs.conc)) :=
      makeConcrete_records hw.coh hrestOk hw.proc hrOk.conc hnpG hres
    intro c hc
    rcases mem_sys_of_three hc with ⟨p, hp, rfl⟩ | ⟨p, hp, rfl⟩ | ⟨b, hb, rfl⟩
    · rcases shape_mem_or (dequeuePol_shape hdq) p hp with hp' | rfl
      · exact hall p (List.mem_append_left _ hp')
      · rw [abstr_isEmpty_toConstraint habs]; exact hkey
    · exact hall p (List.mem_append_right _ hp)
    · exact fun rho hm => hm _ (henvG b hb)

/-- **THE OUTPUT-SOUNDNESS STEP LEMMA, all five branches.**  `StrictStep.step_noLoss` covers
four of them with no proviso; the fifth needs `BareAgreeP`. -/
theorem stepP_noLoss_all {s s' : State} (hw : Wf s) (hba : BareAgreeP pol aux s)
    (h : stepP pol aux s = .continue s') : NoLoss (sys s) (sys s') := by
  cases hdq : dequeuePol pol aux s.incm with
  | none =>
    exfalso
    simp only [stepP] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    cases hfr : s.proc.findRHS r.rhs with
    | some u => exact (stepP_strict_common hw hdq hfr h).1.no_loss
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · exact (stepP_strict_empty hw hdq hfr hem h).1.no_loss
      · by_cases habs : r.rhs.abstr.isEmpty = true
        · exact stepP_noLoss_concrete hw hba hdq hfr (by simpa using hem) habs h
        · cases hsg : r.rhs.single? with
          | some u => exact (stepP_strict_unify hw hdq hfr hsg h).1.no_loss
          | none =>
            exact stepP_learn_noLoss hdq hfr (by simpa using hem) (by simpa using habs) hsg h

/-- ... at a SATISFIABLE state, with no proviso left. -/
theorem stepP_noLoss_sat {s s' : State} (hw : Wf s) (hsat : SSat (sys s))
    (h : stepP pol aux s = .continue s') : NoLoss (sys s) (sys s') :=
  stepP_noLoss_all hw (bareAgreeP_of_sat hsat) h

/-- ... and unconditionally, as a disjunction: either the step loses nothing, or the system it
started from already had no model. -/
theorem stepP_noLoss_or {s s' : State} (hw : Wf s) (h : stepP pol aux s = .continue s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s) := by
  by_cases hsat : SSat (sys s)
  · exact Or.inl (stepP_noLoss_sat hw hsat h)
  · exact Or.inr hsat

/-- **REJECTION SOUNDNESS, one step.**  Every message `step` can die with, at a well-formed
hygienic state, either refutes the system the state denotes or is the skolem refusal. -/
theorem stepP_died_refutes {s s' : State} {m : String} (hw : Wf s) (hq : QueueHygiene s)
    (h : stepP pol aux s = .died m s') : ¬ SSat (sys s) ∨ NonRefutation s.names m := by
  cases hdq : dequeuePol pol aux s.incm with
  | none =>
    exfalso
    simp only [stepP] at h
    rw [hdq] at h
    exact absurd h (by simp)
  | some w =>
    obtain ⟨r, rest⟩ := w
    obtain ⟨hrOk, hrestOk⟩ := QOk.shape hw.incm (dequeuePol_shape hdq)
    obtain ⟨hrMem, hrestMem⟩ := shape_mem (dequeuePol_shape hdq)
    have hrestG : ∀ x ∈ rest.elems, x.toConstraint ∈ sys s :=
      fun x hx => mem_sys_of_incm (hrestMem x hx)
    have hprocG : ∀ x ∈ s.proc.elems, x.toConstraint ∈ sys s := fun x hx => mem_sys_of_proc hx
    have hrG : r.toConstraint ∈ sys s := mem_sys_of_incm hrMem
    cases hfr : s.proc.findRHS r.rhs with
    | some u =>
      exfalso
      obtain ⟨w2, hw2⟩ := (stepP_link_no_death hq hdq).1 u hfr
      obtain ⟨ni, np, e⟩ := w2
      simp only [stepP, State.log] at h
      rw [hdq] at h
      dsimp only at h
      rw [hfr] at h
      dsimp only at h
      rw [hw2] at h
      exact absurd h (by simp)
    | none =>
      by_cases hem : r.rhs.isEmpty = true
      · obtain ⟨st, hsti, hstp, hste, hstn, hstep⟩ := stepP_empty_branch hdq hfr hem
        rw [hstep] at h
        cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | ok w2 =>
          obtain ⟨ni, np, e⟩ := w2
          rw [hres] at h
          exact absurd h (by simp)
        | error m0 =>
          rw [hres] at h
          simp only [StepResult.died.injEq] at h
          obtain ⟨rfl, -⟩ := h
          rcases makeEmpty_died_hyg hrestG hprocG
            (by rw [← toConstraint_of_isEmpty hem]; exact hrG)
            (queueHygiene_binds_unboundP hq hdq).1 hres with hh | hh
          · exact Or.inl hh
          · exact Or.inr ⟨r.lhs, hh.1, hh.2⟩
      · by_cases habs : r.rhs.abstr.isEmpty = true
        · refine Or.inl ?_
          simp only [stepP, State.log] at h
          rw [hdq] at h
          dsimp only at h
          rw [hfr] at h
          dsimp only at h
          rw [if_neg hem, if_pos habs] at h
          cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | ok w2 =>
            obtain ⟨ni, np⟩ := w2
            rw [hres] at h
            exact absurd h (by simp)
          | error m0 =>
            exact makeConcrete_died hw.coh hrestOk hw.proc hrOk.conc hrestG hprocG
              (by rw [← abstr_isEmpty_toConstraint habs]; exact hrG) hres
        · cases hsg : r.rhs.single? with
          | some u =>
            exfalso
            obtain ⟨w2, hw2⟩ := (stepP_link_no_death hq hdq).2 u hsg
            obtain ⟨ni, np, e⟩ := w2
            simp only [stepP, State.log] at h
            rw [hdq] at h
            dsimp only at h
            rw [hfr] at h
            dsimp only at h
            rw [if_neg hem, if_neg habs, hsg] at h
            dsimp only at h
            rw [hw2] at h
            exact absurd h (by simp)
          | none =>
            refine Or.inl ?_
            simp only [stepP, State.log] at h
            rw [hdq] at h
            dsimp only at h
            rw [hfr] at h
            dsimp only at h
            rw [if_neg hem, if_neg habs, hsg] at h
            dsimp only at h
            cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | ok w2 =>
              obtain ⟨learned, su⟩ := w2
              rw [hlp] at h
              exact absurd h (by simp)
            | error m0 =>
              exact learnPartitions_died hprocG (by rw [← toConstraint_eq]; exact hrG) hlp

/-! ## 3. The RUN under a policy

`runP` is `Loop/Step.lean`'s `run` with `stepP` in place of `step`, threading the policy's
auxiliary state exactly as `PolicyReplay.runSP` threads it (`Aux.next pol` after every
continuation).  `runP_shipped` is the `rfl` that says the default is the shipped run. -/

/-- The loop under a policy: `run`, with `stepP`. -/
def runP (pol : Policy) : Aux → State → Nat → RunResult
  | _, s, 0 => .outOfFuel s
  | a, s, n + 1 =>
    match stepP pol a s with
    | .done s' => .solved s'
    | .died m s' => .rejected m s'
    | .continue s' => runP pol (a.next pol s') s' n

/-- **The default is the shipped run, definitionally.** -/
theorem runP_shipped (aux : Aux) (s : State) : ∀ n, runP .shipped aux s n = run s n
  | 0 => rfl
  | n + 1 => by
    simp only [runP, run, stepP_shipped]
    cases step s with
    | done s' => rfl
    | died m s' => rfl
    | «continue» s' => exact runP_shipped _ s' n

/-- `RefineLearn.RunSupOk` along a policy run. -/
def RunSupOkP (pol : Policy) : Aux → Nat → State → Prop
  | _, 0, _ => True
  | a, n + 1, s => SupOk s.su ∧ SupFresh s.su (sys s) ∧
      ∀ s', stepP pol a s = .continue s' → RunSupOkP pol (a.next pol s') n s'

/-- **SATISFIABILITY along a policy run**, with no restriction on the branches taken —
`RefineLearn.run_sat_all` for `runP`. -/
theorem runP_sat_all : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOkP pol aux n s → SSat (sys s) →
    ∀ s', (runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') → SSat (sys s')
  | 0, aux, s, _, _, _, _, _, hsat, s', hres => by
    simp only [runP] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact hsat
  | n + 1, aux, s, hw, hem, hdj, hcse, hb, hsat, s', hres => by
    simp only [runP] at hres
    cases hst : stepP pol aux s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [stepP_done hst]
        exact hsat
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      refine runP_sat_all n (stepP_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
        (stepP_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat) s' hres
      · rw [stepP_flags hst]; exact hem
      · rw [stepP_flags hst]; exact hdj
      · rw [stepP_flags hst]; exact hcse

/-- **OUTPUT SOUNDNESS along a policy run** — `Sound.run_noLoss` for `runP`. -/
theorem runP_noLoss : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOkP pol aux n s → SSat (sys s) →
    ∀ s', (runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') →
      NoLoss (sys s) (sys s')
  | 0, aux, s, _, _, _, _, _, _, s', hres => by
    simp only [runP] at hres
    rcases hres with hres | hres
    · exact absurd hres (by simp)
    · rw [RunResult.outOfFuel.injEq] at hres; subst hres; exact NoLoss.refl _
  | n + 1, aux, s, hw, hem, hdj, hcse, hb, hsat, s', hres => by
    simp only [runP] at hres
    cases hst : stepP pol aux s with
    | done s0 =>
      rw [hst] at hres
      rcases hres with hres | hres
      · rw [RunResult.solved.injEq] at hres
        subst hres
        rw [stepP_done hst]
        exact NoLoss.refl _
      · exact absurd hres (by simp)
    | died m0 s0 => rw [hst] at hres; rcases hres with hres | hres <;> exact absurd hres (by simp)
    | «continue» s0 =>
      rw [hst] at hres
      refine NoLoss.trans (stepP_noLoss_sat hw hsat hst) ?_
      refine runP_noLoss n (stepP_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
        (stepP_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat) s' hres
      · rw [stepP_flags hst]; exact hem
      · rw [stepP_flags hst]; exact hdj
      · rw [stepP_flags hst]; exact hcse

/-- ... as a statement about MODELS — `Sound.run_models` for `runP`. -/
theorem runP_models {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (hres : runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s) :=
  fun _ hm => (runP_noLoss n hw hem hdj hcse hb hsat s' hres).models hm

/-- ... and satisfiability in BOTH directions — `Sound.run_ssat_iff` for `runP`. -/
theorem runP_ssat_iff {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (hres : runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') :
    SSat (sys s) ↔ SSat (sys s') := by
  constructor
  · intro h
    exact runP_sat_all n hw hem hdj hcse hb h s' hres
  · rintro ⟨rho, hm⟩
    exact ⟨rho, runP_models hw hem hdj hcse hb hsat hres rho hm⟩

/-- ... and the unconditional disjunction — `Sound.run_noLoss_or` for `runP`. -/
theorem runP_noLoss_or {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s)
    (hres : runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s) := by
  by_cases hsat : SSat (sys s)
  · exact Or.inl (runP_noLoss n hw hem hdj hcse hb hsat s' hres)
  · exact Or.inr hsat

/-- **A refuting death refutes the INPUT** — `RefineLearn.run_refutes_all` for `runP`. -/
theorem runP_refutes_all : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOkP pol aux n s →
    ∀ (m : String) (s' : State), runP pol aux s n = .rejected m s' → ¬ SSat (sys s') →
      ¬ SSat (sys s)
  | 0, aux, s, _, _, _, _, _, m, s', hres, _ => by
    simp only [runP] at hres; exact absurd hres (by simp)
  | n + 1, aux, s, hw, hem, hdj, hcse, hb, m, s', hres, hns => by
    simp only [runP] at hres
    cases hst : stepP pol aux s with
    | done s0 => rw [hst] at hres; exact absurd hres (by simp)
    | died m0 s0 =>
      rw [hst] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨-, rfl⟩ := hres
      rw [stepP_died_sys hst] at hns
      exact hns
    | «continue» s0 =>
      rw [hst] at hres
      intro hsat
      refine runP_refutes_all n (stepP_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst) m s' hres hns
        (stepP_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat)
      · rw [stepP_flags hst]; exact hem
      · rw [stepP_flags hst]; exact hdj
      · rw [stepP_flags hst]; exact hcse

/-- **REJECTION SOUNDNESS along a policy run** — `Reject.run_rejects_unsat` for `runP`.  A run
under ANY policy that rejects with a message that is not the skolem refusal has REFUTED its
input. -/
theorem runP_rejects_unsat : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOkP pol aux n s → QueueHygiene s →
    ∀ (m : String) (s' : State), runP pol aux s n = .rejected m s' →
      ¬ NonRefutation s.names m → ¬ SSat (sys s)
  | 0, aux, s, _, _, _, _, _, _, m, s', hres, _ => by
    simp only [runP] at hres; exact absurd hres (by simp)
  | n + 1, aux, s, hw, hem, hdj, hcse, hb, hq, m, s', hres, hnr => by
    simp only [runP] at hres
    cases hst : stepP pol aux s with
    | done s0 => rw [hst] at hres; exact absurd hres (by simp)
    | died m0 s0 =>
      rw [hst] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨rfl, -⟩ := hres
      rcases stepP_died_refutes hw hq hst with hh | hh
      · exact hh
      · exact absurd hh hnr
    | «continue» s0 =>
      rw [hst] at hres
      intro hsat
      refine runP_rejects_unsat n (stepP_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
        (stepP_queueHygiene hdj hb.1 hb.2.1 hq hst) m s' hres ?_
        (stepP_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat)
      · rw [stepP_flags hst]; exact hem
      · rw [stepP_flags hst]; exact hdj
      · rw [stepP_flags hst]; exact hcse
      · rw [stepP_names hst]; exact hnr

/-- ... and on a solve whose variables carry NO skolem, with no exception list at all. -/
theorem runP_rejects_unsat_noSkolem (n : Nat) {aux : Aux} {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hq : QueueHygiene s)
    (hsk : ∀ v, s.names.isSkolem v = false)
    (m : String) (s' : State) (hres : runP pol aux s n = .rejected m s') : ¬ SSat (sys s) :=
  runP_rejects_unsat n hw hem hdj hcse hb hq m s' hres
    (by rintro ⟨v, hv, -⟩; rw [hsk v] at hv; exact absurd hv (by simp))

/-! ## 4. ACCEPTANCE: the policy run accepts only a SATURATED state

This is the failure mode a dequeue order could introduce all by itself, and it is the one place
`dequeuePol_none` earns its keep: a `pop` that answered `none` on a NON-EMPTY queue would make
`incorporateAll` return `proc` and the solve accept WITHOUT SATURATING.  `stepP_done_dequeue`
(`FlaggedSound` §SS4) rules that out for every policy, and the theorem below is where it is
USED: the `.solved` case of the run induction. -/

/-- **Under ANY policy, an accepted run left an EMPTY incoming queue.** -/
theorem runP_solved_saturated : ∀ (n : Nat) {aux : Aux} {s s' : State},
    runP pol aux s n = .solved s' → s'.incm.elems = []
  | 0, aux, s, s', hres => by simp only [runP] at hres; exact absurd hres (by simp)
  | n + 1, aux, s, s', hres => by
    simp only [runP] at hres
    cases hst : stepP pol aux s with
    | done s0 =>
      rw [hst] at hres
      rw [RunResult.solved.injEq] at hres
      subst hres
      -- THE ACCEPTANCE FACT, at the point of use: `.done` is `dequeuePol … = none`, and
      -- `dequeuePol_none` says that happens only on an empty queue.
      rw [stepP_done hst]
      exact stepP_done_dequeue hst
    | died m0 s0 => rw [hst] at hres; exact absurd hres (by simp)
    | «continue» s0 => rw [hst] at hres; exact runP_solved_saturated n hres

/-- **The acceptance, packaged**: a policy run that ACCEPTS a satisfiable input saturated its
queue AND lost nothing.  Under the shipped policy this is `run_noLoss` plus
`NoConc.step_done_dequeue`; the content here is that it holds for `concFirst`, `smallRhs`,
`fifo`, `canon` and `smallCanon` too. -/
theorem runP_accepted_saturated_noLoss {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (hres : runP pol aux s n = .solved s') :
    s'.incm.elems = [] ∧ NoLoss (sys s) (sys s') ∧ SSat (sys s') :=
  ⟨runP_solved_saturated n hres,
   runP_noLoss n hw hem hdj hcse hb hsat s' (Or.inl hres),
   runP_sat_all n hw hem hdj hcse hb hsat s' (Or.inl hres)⟩

/-! ## 5. The driver the replay actually runs: `runSP pol d0 b`

`PolicyReplay.solveSeedP` runs `runSP pol d0 bud`, whose step is `stepSP` — the policy step with
S2's layer (i) in front of it.  Two reductions bring it back to `runP`, and they are the exact
analogues of `FlaggedSound` SS1–SS3 for the budget:

* with layer (i) off (`rowSoundBare = false`, the shipped setting) and the budget off (`b = 0`)
  the driver IS `runP`, record for record (`runSP_eq_runP`);
* with the budget ON, whatever it ACCEPTS or runs out of FUEL on, `runP` does too, and its one
  extra death is `BudgetDeath` — which is why the exception list at the run level is
  `NonRefutationB` and not `NonRefutation`. -/

/-- With S2's layer (i) off — the shipped setting — and the budget off, the replay's loop IS
the policy loop, record for record. -/
theorem runSP_eq_runP {d0 : Nat} : ∀ (n : Nat) (aux : Aux) {s : State},
    s.flags.rowSoundBare = false → runSP pol d0 0 aux s n = runP pol aux s n
  | 0, aux, s, _ => rfl
  | n + 1, aux, s, hrs => by
    simp only [runSP, runP, stepSP_of_rowSound_off hrs]
    cases hst : stepP pol aux s with
    | done s' => rfl
    | died m s' => rfl
    | «continue» s' =>
      simp only []
      exact runSP_eq_runP n _ (by rw [stepP_flags hst]; exact hrs)

/-- A budgeted policy run that runs out of FUEL ran out of fuel unbudgeted: it never took the
budget branch, so it followed `stepP` at every dequeue.  (`FlaggedSound.runBud_outOfFuel` over
a policy.) -/
theorem runSP_outOfFuel {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s s' : State},
    s.flags.rowSoundBare = false → runSP pol d0 b aux s n = .outOfFuel s' →
    runP pol aux s n = .outOfFuel s'
  | 0, aux, s, s', _, h => by simpa only [runSP, runP] using h
  | n + 1, aux, s, s', hrs, h => by
    by_cases hb : b != 0 && d0 + b < s.su.drawn
    · rw [runSP, if_pos hb] at h; exact absurd h (by simp)
    · rw [runSP, if_neg hb, stepSP_of_rowSound_off hrs] at h
      simp only [runP]
      cases hst : stepP pol aux s with
      | done s0 => rw [hst] at h; exact absurd h (by simp)
      | died m s0 => rw [hst] at h; exact absurd h (by simp)
      | «continue» s0 =>
        rw [hst] at h
        simp only [] at h
        exact runSP_outOfFuel n _ (by rw [stepP_flags hst]; exact hrs) h

/-- **The budget never makes the policy loop ACCEPT.**  (`Budget.budget_never_accepts` over a
policy.) -/
theorem runSP_never_accepts {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s s' : State},
    s.flags.rowSoundBare = false → runSP pol d0 b aux s n = .solved s' →
    runP pol aux s n = .solved s'
  | 0, aux, s, s', _, h => by simp only [runSP] at h; exact absurd h (by simp)
  | n + 1, aux, s, s', hrs, h => by
    by_cases hb : b != 0 && d0 + b < s.su.drawn
    · rw [runSP, if_pos hb] at h; exact absurd h (by simp)
    · rw [runSP, if_neg hb, stepSP_of_rowSound_off hrs] at h
      simp only [runP]
      cases hst : stepP pol aux s with
      | done s0 => rw [hst] at h; simpa using h
      | died m s0 => rw [hst] at h; exact absurd h (by simp)
      | «continue» s0 =>
        rw [hst] at h
        simp only [] at h
        exact runSP_never_accepts n _ (by rw [stepP_flags hst]; exact hrs) h

/-- **OUTPUT SOUNDNESS for the driver the replay runs** — policy AND budget AND S2's layer (i)
off, on a satisfiable input. -/
theorem runSP_noLoss {d0 b n : Nat} {aux : Aux} {s : State} (hrs : s.flags.rowSoundBare = false)
    (hw : Wf s) (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (s' : State)
    (hres : runSP pol d0 b aux s n = .solved s' ∨ runSP pol d0 b aux s n = .outOfFuel s') :
    NoLoss (sys s) (sys s') :=
  runP_noLoss n hw hem hdj hcse hb hsat s'
    (hres.elim (fun h => Or.inl (runSP_never_accepts n aux hrs h))
               (fun h => Or.inr (runSP_outOfFuel n aux hrs h)))

/-- **SATISFIABILITY is preserved by the driver the replay runs.** -/
theorem runSP_sat_all {d0 b n : Nat} {aux : Aux} {s : State} (hrs : s.flags.rowSoundBare = false)
    (hw : Wf s) (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (s' : State)
    (hres : runSP pol d0 b aux s n = .solved s' ∨ runSP pol d0 b aux s n = .outOfFuel s') :
    SSat (sys s') :=
  runP_sat_all n hw hem hdj hcse hb hsat s'
    (hres.elim (fun h => Or.inl (runSP_never_accepts n aux hrs h))
               (fun h => Or.inr (runSP_outOfFuel n aux hrs h)))

/-- **REFINEMENT for the driver the replay runs.** -/
theorem runSP_models {d0 b n : Nat} {aux : Aux} {s : State} (hrs : s.flags.rowSoundBare = false)
    (hw : Wf s) (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    {s' : State}
    (hres : runSP pol d0 b aux s n = .solved s' ∨ runSP pol d0 b aux s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s) :=
  runP_models hw hem hdj hcse hb hsat
    (hres.elim (fun h => Or.inl (runSP_never_accepts n aux hrs h))
               (fun h => Or.inr (runSP_outOfFuel n aux hrs h)))

/-- **... and an acceptance is still an acceptance on an EMPTY queue.** -/
theorem runSP_solved_saturated {d0 b n : Nat} {aux : Aux} {s s' : State}
    (hrs : s.flags.rowSoundBare = false) (hres : runSP pol d0 b aux s n = .solved s') :
    s'.incm.elems = [] :=
  runP_solved_saturated n (runSP_never_accepts n aux hrs hres)

/-- **REJECTION SOUNDNESS for the driver the replay runs**, with the budget's death on the
exception list: a rejection that is neither the skolem refusal nor budget exhaustion REFUTES
the input, under ANY policy.  This is the theorem `NonRefutationB` exists for — without it
"the loop rejected" would license "the input has no model" when the loop merely ran out of
budget. -/
theorem runSP_rejects_unsat {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s : State},
    s.flags.rowSoundBare = false → Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOkP pol aux n s → QueueHygiene s →
    ∀ (m : String) (s' : State), runSP pol d0 b aux s n = .rejected m s' →
      ¬ NonRefutationB s.names m → ¬ SSat (sys s)
  | 0, aux, s, _, _, _, _, _, _, _, m, s', hres, _ => by
    simp only [runSP] at hres; exact absurd hres (by simp)
  | n + 1, aux, s, hrs, hw, hem, hdj, hcse, hb, hq, m, s', hres, hnr => by
    by_cases hbud : b != 0 && d0 + b < s.su.drawn
    · rw [runSP, if_pos hbud] at hres
      rw [RunResult.rejected.injEq] at hres
      obtain ⟨rfl, -⟩ := hres
      exact absurd (Or.inr ⟨s.site, d0, b, s.su.drawn, rfl⟩) hnr
    · rw [runSP, if_neg hbud, stepSP_of_rowSound_off hrs] at hres
      cases hst : stepP pol aux s with
      | done s0 => rw [hst] at hres; exact absurd hres (by simp)
      | died m0 s0 =>
        rw [hst] at hres
        rw [RunResult.rejected.injEq] at hres
        obtain ⟨rfl, -⟩ := hres
        rcases stepP_died_refutes hw hq hst with hh | hh
        · exact hh
        · exact absurd (Or.inl hh) hnr
      | «continue» s0 =>
        rw [hst] at hres
        simp only [] at hres
        intro hsat
        refine runSP_rejects_unsat n _ (by rw [stepP_flags hst]; exact hrs)
          (stepP_wf hw hst) ?_ ?_ ?_ (hb.2.2 s0 hst)
          (stepP_queueHygiene hdj hb.1 hb.2.1 hq hst) m s' hres ?_
          (stepP_sat_all hw hem hdj hcse hb.1 hb.2.1 hst hsat)
        · rw [stepP_flags hst]; exact hem
        · rw [stepP_flags hst]; exact hdj
        · rw [stepP_flags hst]; exact hcse
        · rw [stepP_names hst]; exact hnr

/-- A policy rejection forces a driver rejection: either the budget fired first, which is
itself a rejection, or the driver followed `stepP` to the same death.
(`FlaggedSound.runBud_rejects_of_run_rejects` over a policy.) -/
theorem runSP_rejects_of_runP_rejects {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s : State}
    {m : String} {s' : State}, s.flags.rowSoundBare = false → runP pol aux s n = .rejected m s' →
    ∃ m0 s0, runSP pol d0 b aux s n = .rejected m0 s0
  | 0, aux, s, m, s', _, hc => by simp only [runP] at hc; exact absurd hc (by simp)
  | n + 1, aux, s, m, s', hrs, hc => by
    by_cases hbud : b != 0 && d0 + b < s.su.drawn
    · exact ⟨budgetMsg s.site d0 b s.su.drawn, s, by rw [runSP, if_pos hbud]⟩
    · simp only [runP] at hc
      cases hst : stepP pol aux s with
      | done s0 => rw [hst] at hc; exact absurd hc (by simp)
      | died m0 s0 =>
        exact ⟨m0, s0, by rw [runSP, if_neg hbud, stepSP_of_rowSound_off hrs, hst]⟩
      | «continue» s0 =>
        rw [hst] at hc
        simp only [] at hc
        obtain ⟨m1, s1, h1⟩ :=
          runSP_rejects_of_runP_rejects (d0 := d0) (b := b) n _
            (by rw [stepP_flags hst]; exact hrs) hc
        exact ⟨m1, s1, by
          rw [runSP, if_neg hbud, stepSP_of_rowSound_off hrs, hst]
          exact h1⟩

/-- **The no-false-acceptance hypothesis transports to the policy driver.**  S2's chain is
conditional on "the solve does not reject"; a driver run that does not reject gives that
hypothesis for the policy run, so `solveP_noFalseAccept` and `solveP_accepted_faithful` below
apply to the driver with nothing else changed.  (`FlaggedSound.runBud_not_rejected` over a
policy.) -/
theorem runSP_not_rejected {d0 b n : Nat} {aux : Aux} {s : State}
    (hrs : s.flags.rowSoundBare = false)
    (h : ∀ m s', runSP pol d0 b aux s n ≠ .rejected m s') :
    ∀ m s', runP pol aux s n ≠ .rejected m s' := by
  intro m s' hc
  obtain ⟨m0, s0, h0⟩ := runSP_rejects_of_runP_rejects (d0 := d0) (b := b) n aux hrs hc
  exact h m0 s0 h0

/-! ## 6. S2's chain, for the policy solve

`solveSeedP` reaches layer (iii) — the complete per-label decision — BEFORE the loop, exactly
as `solveSeed` does, and the policy changes nothing about it.  So the two S2 theorems transport
line for line, with `runP` supplying the S1 half. -/

/-- `NoFalseAccept.solveSeed_rejects_of_refuted` for the policy solve.  `htn` is that theorem's
S4 premise, for the same reason and with the same scope: the chain covers `topNormalise = false`,
the shipped configuration. -/
theorem solveSeedP_rejects_of_refuted {bud : Nat} {fl : Flags} {site loc : String}
    {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat} {envFacts : List LPart}
    {q : PQueue} {su1 : Sup}
    (htn : fl.topNormalise = false)
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    {l : Lbl} {a : Nat} {w : String}
    (href : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
              fl.rowSoundSolveBudget).1 = .refuted l a w) :
    (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict = "REJECTED" := by
  simp only [solveSeedP, hq, htn, topNormalise, Bool.not_false, if_true, hearly, hflag, href]

/-- **NO FALSE ACCEPTANCE, under any policy.**  With layer (iii) on and its budget intact, a
policy solve that does NOT reject says the system it was given HAS A MODEL. -/
theorem solveP_noFalseAccept {L : List Lbl} (hcoh : LblCoh L) {bud : Nat}
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup}
    (htn : fl.topNormalise = false)
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED") :
    SSat ((((q.elems ++ envFacts).map LPart.toConstraint)).toFinset) := by
  have hsat : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
      fl.rowSoundSolveBudget).1 = .sat := by
    cases hv : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
        fl.rowSoundSolveBudget).1 with
    | sat => rfl
    | refuted l a w => exact absurd (solveSeedP_rejects_of_refuted htn hq hearly hflag hv) hacc
    | noVerdict l w => exact absurd hv (hbud l w)
  exact labelDecide_sat_ssat hcoh hnd hmem hsat

/-- **THE CHAIN, under any policy.**  With layer (iii) on and its budget intact, a policy solve
that ACCEPTS is FAITHFUL: the loop lost nothing, every model of the output system is a model of
the input system, and the two are satisfiable together.  S1 (this module) and S2 composed. -/
theorem solveP_accepted_faithful {L : List Lbl} (hcoh : LblCoh L) {bud : Nat}
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup} {tr : List String} {z : Nat}
    (htn : fl.topNormalise = false)
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED")
    (n : Nat) (aux : Aux) (hw : Wf (initState q su1 tr fl ns site z))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hb : RunSupOkP pol aux n (initState q su1 tr fl ns site z))
    {s' : State}
    (hres : runP pol aux (initState q su1 tr fl ns site z) n = .solved s' ∨
            runP pol aux (initState q su1 tr fl ns site z) n = .outOfFuel s') :
    NoLoss (sys (initState q su1 tr fl ns site z)) (sys s') ∧
    (∀ rho, SModels rho (sys s') → SModels rho (sys (initState q su1 tr fl ns site z))) ∧
    (SSat (sys (initState q su1 tr fl ns site z)) ↔ SSat (sys s')) := by
  have hlive : SSat ((((q.elems ++ envFacts).map LPart.toConstraint)).toFinset) :=
    solveP_noFalseAccept hcoh htn hq hearly hflag hnd hmem hbud hacc
  have hsat : SSat (sys (initState q su1 tr fl ns site z)) :=
    ssat_of_subset sys_subset_live hlive
  exact ⟨runP_noLoss n hw hem hdj hcse hb hsat s' hres,
         runP_models hw hem hdj hcse hb hsat hres,
         runP_ssat_iff hw hem hdj hcse hb hsat hres⟩

/-! ## 7. NO SILENT WEAKENING: the originals, recovered

Every theorem above is the original statement with `step s` replaced by `stepP pol aux s`, so
instantiating it at `pol := .shipped` must give the original back — `stepP_shipped` is `rfl`, so
the hypothesis `step s = .continue s'` IS the hypothesis `stepP .shipped aux s = .continue s'`
and the two statements are the same proposition.  The witnesses below are that check in the
KERNEL, one per result the transport is for: each is proved by handing the shipped instance of
the policy theorem a hypothesis about `step`, with no bridging lemma in between. -/

theorem stepP_qok_recovers {L : List Lbl} {s s' : State} (aux : Aux)
    (hi : QOk L s.incm) (hp : QOk L s.proc) (h : step s = .continue s') :
    QOk L s'.incm ∧ QOk L s'.proc :=
  stepP_qok (pol := .shipped) (aux := aux) hi hp h

theorem stepP_supFresh_recovers {s s' : State} (aux : Aux)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') :
    SupOk s'.su ∧ (∀ z, Sup.Reach s'.su z → Sup.Reach s.su z) ∧ SupFresh s'.su (sys s') :=
  stepP_supFresh (pol := .shipped) (aux := aux) hdj hcse hok hfr h

theorem stepP_queueHygiene_recovers {s s' : State} (aux : Aux)
    (hdj : s.flags.disjRule = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : step s = .continue s') : QueueHygiene s' :=
  stepP_queueHygiene (pol := .shipped) (aux := aux) hdj hok hfr h0 h

theorem stepP_refines_all_recovers {s s' : State} (aux : Aux) (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : step s = .continue s') : LoopRun (sys s) (sys s') :=
  stepP_refines_all (pol := .shipped) (aux := aux) hw hem hdj hcse hok hfr h

theorem stepP_noLoss_all_recovers {s s' : State} (aux : Aux) (hw : Wf s) (hba : BareAgree s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s') :=
  stepP_noLoss_all (pol := .shipped) (aux := aux) hw
    (fun r rest hdq => hba r rest hdq) h

theorem stepP_died_refutes_recovers {s s' : State} {m : String} (aux : Aux) (hw : Wf s)
    (hq : QueueHygiene s) (h : step s = .died m s') :
    ¬ SSat (sys s) ∨ NonRefutation s.names m :=
  stepP_died_refutes (pol := .shipped) (aux := aux) hw hq h

theorem stepP_drawn_le_recovers {s s' : State} (aux : Aux)
    (hdj : s.flags.disjRule = false) (hcse : s.flags.cseMints = false)
    (h : step s = .continue s') : s'.su.drawn ≤ s.su.drawn + 1 + s.proc.elems.length :=
  stepP_drawn_le (pol := .shipped) (aux := aux) hdj hcse h

/-- The supply invariant along a run is the same predicate at the shipped policy. -/
theorem runSupOkP_shipped : ∀ (n : Nat) (aux : Aux) (s : State),
    RunSupOkP .shipped aux n s ↔ RunSupOk n s
  | 0, _, _ => Iff.rfl
  | n + 1, aux, s => by
    simp only [RunSupOkP, RunSupOk, stepP_shipped]
    refine and_congr_right (fun _ => and_congr_right (fun _ => ?_))
    exact forall_congr' (fun s' => imp_congr_right (fun _ => runSupOkP_shipped n _ s'))

theorem runP_sat_all_recovers (n : Nat) (aux : Aux) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s)) (s' : State)
    (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') : SSat (sys s') := by
  refine runP_sat_all (pol := .shipped) n hw hem hdj hcse
    ((runSupOkP_shipped n aux s).mpr hb) hsat s' ?_
  rw [runP_shipped aux s n]; exact hres

theorem runP_noLoss_recovers (n : Nat) (aux : Aux) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s)) (s' : State)
    (hres : run s n = .solved s' ∨ run s n = .outOfFuel s') : NoLoss (sys s) (sys s') := by
  refine runP_noLoss (pol := .shipped) n hw hem hdj hcse
    ((runSupOkP_shipped n aux s).mpr hb) hsat s' ?_
  rw [runP_shipped aux s n]; exact hres

theorem runP_rejects_unsat_recovers (n : Nat) (aux : Aux) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hq : QueueHygiene s)
    (m : String) (s' : State) (hres : run s n = .rejected m s')
    (hnr : ¬ NonRefutation s.names m) : ¬ SSat (sys s) := by
  refine runP_rejects_unsat (pol := .shipped) n hw hem hdj hcse
    ((runSupOkP_shipped n aux s).mpr hb) hq m s' ?_ hnr
  rw [runP_shipped aux s n]; exact hres

end Rowpartition.Loop
