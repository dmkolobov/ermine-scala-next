/-
# L3 (ii) and (iii): the ORDER properties, as lemmas about `step`

`tracker/LOOP-MODEL-PLAN.md` names four properties that `Constraints.incorporateAll` has and
no relation of the development states: a SINGLE PASS over each partition, EAGER `makeEmpty`,
EAGER `unify` of singleton links, and NAMES TRAVELLING with their groups.  In L1 and L2 they
were observations about the Scala; here they are theorems about `step`.

The single-pass property is also the whole of question (iii): Stage 7b's fallback mint can
chain only if the same premise pair can be examined twice, and it can be examined twice only
if one of the two partitions is re-enqueued after being processed.
-/
import Rowpartition.Loop.Refine

namespace Rowpartition.Loop

open Rowpartition

set_option linter.unusedSimpArgs false

/-! ## 1. Termination, stated -/

/-- A bounded run that did not run out of fuel. -/
def Finished : RunResult → Prop
  | .outOfFuel _ => False
  | _ => True

/-- **The termination predicate**: iterated `step` reaches `done` or `died` within some
number of dequeues. -/
def Terminates (s : State) : Prop := ∃ n : Nat, Finished (run s n)

/-- More fuel cannot hurt. -/
theorem run_mono : ∀ (n : Nat) (s : State), Finished (run s n) → Finished (run s (n + 1))
  | 0, s, h => by simp only [run, Finished] at h
  | n + 1, s, h => by
    simp only [run] at h ⊢
    cases hst : step s with
    | done s0 => rw [hst] at h; exact h
    | died m s0 => rw [hst] at h; exact h
    | «continue» s0 => rw [hst] at h; exact run_mono n s0 h

/-- The empty queue terminates at once. -/
theorem terminates_of_empty {s : State} (h : s.incm.dequeue = none) : Terminates s := by
  refine ⟨1, ?_⟩
  simp only [run]
  have : step s = .done s := by simp only [step]; rw [h]
  rw [this]
  trivial

/-! ## 2. The dispatch is a decision procedure on the dequeued partition

`step` looks at the dequeued partition and nothing else to choose its branch, and it tries
the branches in this order: a COMMON partition (the same right-hand side is already
processed), then `makeEmpty`, then `makeConcrete`, then the singleton `unify`, and only then
`learnPartitions`.  So `makeEmpty` and `unify` are EAGER: no rule can fire on a partition
whose right-hand side is empty or a lone variable. -/

/-- **Eager `makeEmpty`.**  A dequeued `v <- ()` whose right-hand side no processed partition
shares goes straight to `makeEmpty`; `learnPartitions` is not called. -/
theorem step_empty_branch {s : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = true) :
    ∃ st : State, st.incm = s.incm ∧ st.proc = s.proc ∧ st.env = s.env ∧ st.names = s.names ∧
      step s = (match makeEmpty s.names r.lhs rest s.proc s.env with
        | .error m => .died m st
        | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }) := by
  refine ⟨s.log ("step\t" ++ s.site ++ "\t" ++ "empty" ++ "\t" ++ r.toStr s.names ++
    "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size),
    rfl, rfl, rfl, rfl, ?_⟩
  simp only [step, State.log]
  rw [hd]
  dsimp only
  rw [h1]
  dsimp only
  rw [if_pos h2]
  rfl

/-- **Eager `unify`.**  A dequeued `v <- (u)` goes straight to `unify`; no rule fires. -/
theorem step_unify_branch {s : State} {r : LPart} {rest : PQueue} {u : Nat}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h4 : r.rhs.single? = some u) :
    ∃ st : State, st.incm = s.incm ∧ st.proc = s.proc ∧ st.env = s.env ∧ st.names = s.names ∧
      step s = (match unifyVars s.names u r.lhs rest s.proc s.env with
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
  simp only [step, State.log]
  rw [hd]
  dsimp only
  rw [h1]
  dsimp only
  rw [if_neg (by simp [h2]), if_neg (by simp [h3]), h4]
  rfl

/-- **Eager `unify` of a common partition.**  When a processed partition already has the
dequeued right-hand side, the step is a unification and no rule fires. -/
theorem step_common_branch {s : State} {r : LPart} {rest : PQueue} {u : Nat}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = some u) :
    ∃ st : State, st.incm = s.incm ∧ st.proc = s.proc ∧ st.env = s.env ∧ st.names = s.names ∧
      step s = (match unifyVars s.names r.lhs u rest s.proc s.env with
        | .error m => .died m st
        | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }) := by
  refine ⟨s.log ("step\t" ++ s.site ++ "\t" ++ ("common:" ++ toString u) ++ "\t" ++
    r.toStr s.names ++ "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size),
    rfl, rfl, rfl, rfl, ?_⟩
  simp only [step, State.log]
  rw [hd]
  dsimp only
  rw [h1]
  rfl

/-- The shape of a `learn` step. -/
theorem step_learn_shape {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') :
    s'.proc = s.proc.insertNP r ∧
      ∃ learned : SSet LPart, s'.incm = rest.concatP (trim learned s.proc).elems := by
  simp only [step, State.log] at h
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

/-! ## 3. The SINGLE PASS -/

theorem mem_insertSorted_of_mem {p x : LPart} :
    ∀ {l : List LPart}, x ∈ l → x ∈ PQueue.insertSorted p l
  | [], h => by cases h
  | y :: l, h => by
    unfold PQueue.insertSorted
    split
    · rcases List.mem_cons.mp h with rfl | h'
      · exact List.mem_cons_self ..
      · exact List.mem_cons_of_mem _ (mem_insertSorted_of_mem h')
    · exact List.mem_cons_of_mem _ h

theorem mem_insertSorted_self (p : LPart) : ∀ (l : List LPart), p ∈ PQueue.insertSorted p l
  | [] => by simp [PQueue.insertSorted]
  | y :: l => by
    unfold PQueue.insertSorted
    split
    · exact List.mem_cons_of_mem _ (mem_insertSorted_self p l)
    · exact List.mem_cons_self ..

theorem mem_insertNP_of_mem {q : PQueue} {p x : LPart} (h : x ∈ q.elems) :
    x ∈ (q.insertNP p).elems := by
  unfold PQueue.insertNP
  split
  · exact h
  · split
    · exact h
    · exact mem_insertSorted_of_mem h

theorem mem_insertP_of_mem {q : PQueue} {p x : LPart} (h : x ∈ q.elems) :
    x ∈ (q.insertP p).elems := by
  unfold PQueue.insertP
  split
  · exact h
  · split
    · exact h
    · split
      · exact mem_insertNP_of_mem h
      · exact mem_insertSorted_of_mem h

theorem mem_concatNP_of_mem : ∀ (ps : List LPart) {q : PQueue} {x : LPart},
    x ∈ q.elems → x ∈ (q.concatNP ps).elems
  | [], _, _, h => h
  | _ :: ps, _, _, h => mem_concatNP_of_mem ps (mem_insertNP_of_mem h)

theorem mem_concatP_of_mem : ∀ (ps : List LPart) {q : PQueue} {x : LPart},
    x ∈ q.elems → x ∈ (q.concatP ps).elems
  | [], _, _, h => h
  | _ :: ps, _, _, h => mem_concatP_of_mem ps (mem_insertP_of_mem h)

/-- A partition the queue-level `CommonPartition` redirect creates: a NAMING constraint
`w <- (a)`, not a re-derivation of anything. -/
def IsRedirect (x : LPart) : Prop :=
  ∃ w a : Nat, x = ⟨w, RHS.ofAbstr (SSet.ofList [a]), some Inference.commonPartition⟩

theorem mem_insertP {q : PQueue} {p x : LPart} (h : x ∈ (q.insertP p).elems) :
    x ∈ q.elems ∨ x = p ∨ IsRedirect x := by
  unfold PQueue.insertP at h
  split at h
  · exact Or.inl h
  · split at h
    · exact Or.inl h
    · split at h
      · rename_i w _
        rcases mem_insertNP h with h' | rfl
        · exact Or.inl h'
        · exact Or.inr (Or.inr ⟨w, p.lhs, rfl⟩)
      · rcases mem_insertSorted h with rfl | h'
        · exact Or.inr (Or.inl rfl)
        · exact Or.inl h'

theorem mem_concatP : ∀ (ps : List LPart) (q : PQueue) {x : LPart},
    x ∈ (q.concatP ps).elems → x ∈ q.elems ∨ x ∈ ps ∨ IsRedirect x
  | [], _, _, h => Or.inl h
  | p :: ps, q, x, h => by
    rcases mem_concatP ps (q.insertP p) h with h' | h' | h'
    · rcases mem_insertP h' with h'' | rfl | h''
      · exact Or.inl h''
      · exact Or.inr (Or.inl (by simp))
      · exact Or.inr (Or.inr h'')
    · exact Or.inr (Or.inl (by simp [h']))
    · exact Or.inr (Or.inr h')

/-- **`trim` refuses everything the processed queue already holds.**  This is the mechanism
of the single pass: a rule may re-derive a partition, but the re-derivation does not reach
the incoming queue while `proc` still carries it. -/
theorem trim_refuses {ps : SSet LPart} {cs : PQueue} {x : LPart}
    (hx : x ∈ (trim ps cs).elems) : ∀ y ∈ cs.elems, y.eqv x = false := by
  have h := (SSet.mem_filter_iff (α := LPart)).mp hx
  intro y hy
  cases hyx : y.eqv x with
  | false => rfl
  | true =>
    exfalso
    have : cs.contains x = true := List.any_eq_true.mpr ⟨y, hy, hyx⟩
    rw [this] at h
    exact absurd h.2 (by simp)

/-- At a `learn` step the dequeued partition really is inserted into `proc`: it is not a
self-unification (its right-hand side is not a lone variable) and `proc` does not already
hold it (its right-hand side is not `findRHS`-visible). -/
theorem learn_insertNP_self {q : PQueue} {r : LPart} (h1 : q.findRHS r.rhs = none)
    (h4 : r.rhs.single? = none) : r ∈ (q.insertNP r).elems := by
  have hfindnone : q.elems.find? (fun x => x.rhs.eqv r.rhs) = none := by
    unfold PQueue.findRHS at h1
    cases hh : q.elems.find? (fun x => x.rhs.eqv r.rhs) with
    | none => rfl
    | some z => rw [hh] at h1; exact absurd h1 (by simp)
  unfold PQueue.insertNP
  have hself : r.isSelfUnification = false := by unfold LPart.isSelfUnification; rw [h4]
  rw [if_neg (by simp [hself])]
  have hpres : ¬ (q.elems.any
      (fun x => PQueue.keyEq (PQueue.keyOf x) (PQueue.keyOf r) && x.eqv r) = true) := by
    intro hc
    obtain ⟨y, hy, hyr⟩ := List.any_eq_true.mp hc
    rw [Bool.and_eq_true] at hyr
    have hy2 : y.rhs.eqv r.rhs = true := by
      have := hyr.2
      unfold LPart.eqv at this
      rw [Bool.and_eq_true] at this
      exact this.2
    exact (List.find?_eq_none.mp hfindnone y hy) (by simpa using hy2)
  rw [if_neg hpres]
  exact mem_insertSorted_self r q.elems

/-- **The single pass, in one statement.**  At a `learn` step the dequeued partition joins
`proc`, everything already in `proc` stays, and everything the step ENQUEUES is
`Partition.equals`-distinct from every partition of `proc`.  So no partition of `proc` is
re-enqueued by a `learn` step: a re-derivation of an identical partition does NOT pass
`trim`. -/
theorem learn_single_pass {s s' : State} {r : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') :
    (∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∧
    r ∈ s'.proc.elems ∧
    (∀ x ∈ s'.incm.elems, x ∈ rest.elems ∨ (∀ y ∈ s.proc.elems, y.eqv x = false) ∨
      IsRedirect x) := by
  obtain ⟨hproc, learned, hincm⟩ := step_learn_shape hd h1 h2 h3 h4 h
  refine ⟨fun p hp => by rw [hproc]; exact mem_insertNP_of_mem hp, ?_, ?_⟩
  · rw [hproc]; exact learn_insertNP_self h1 h4
  · intro x hx
    rw [hincm] at hx
    rcases mem_concatP _ _ hx with hx' | hx' | hx'
    · exact Or.inl hx'
    · exact Or.inr (Or.inl (trim_refuses hx'))
    · exact Or.inr (Or.inr hx')


/-! ## 4. What can leave the processed queue -/

theorem mem_partition_snd {q : PQueue} {f : LPart → Bool} {x : LPart}
    (hx : x ∈ q.elems) (hf : f x = false) : x ∈ (q.partition f).2.elems :=
  List.mem_filter.mpr ⟨hx, by simp [hf]⟩

theorem destructiveSub_proc_mono {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) :
    ∀ p ∈ proc.elems, p.involves v = false → p ∈ np.elems := by
  intro p hp hinv
  rw [LPart.involves, Bool.or_eq_false_iff] at hinv
  have hne : ¬(p.lhs = v) := by simpa using hinv.1
  simp only [destructiveSub] at h
  obtain ⟨srs, hsrs, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨-, rfl⟩ := h2
  split
  · refine mem_concatNP_of_mem _ ?_
    split
    · exact hp
    · exact List.mem_filter.mpr ⟨mem_partition_snd hp hinv.1, by simp [hne, hinv.2]⟩
  · split
    · exact hp
    · exact List.mem_filter.mpr ⟨mem_partition_snd hp hinv.1, by simp [hne, hinv.2]⟩

theorem makeConcrete_proc_mono {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (h : makeConcrete v fs incm proc = .ok (ni, np)) :
    ∀ p ∈ proc.elems, p.involves v = false → p ∈ np.elems := by
  intro p hp hinv
  simp only [makeConcrete] at h
  obtain ⟨u1, hu1, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨-, rfl⟩ := h3
  exact mem_insertNP_of_mem (destructiveSub_proc_mono hw p hp hinv)

theorem instantiate_proc_mono {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : instantiate ns v u incm proc env = .ok (ni, np, e)) :
    ∀ p ∈ proc.elems, p.involves v = false → p ∈ np.elems := by
  intro p hp hinv
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨-, rfl, -⟩ := h
    exact mem_partition_snd hp hinv

theorem makeEmpty_proc_mono {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) :
    ∀ p ∈ proc.elems, p.involves v = false → p ∈ np.elems := by
  intro p hp hinv
  simp only [makeEmpty] at h
  obtain ⟨u1, hu1, h2⟩ := except_bind_ok h
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨-, rfl, -⟩ := h2
      exact mem_partition_snd hp hinv

/-- **A partition leaves the processed queue only if it MENTIONS the variable the step
eliminates.**  This is the single pass in its general form: `learn` never removes anything
(take any `v`), and each of the three eliminating branches removes exactly the partitions
that name the variable it binds or concretises. -/
theorem step_proc_mono {s s' : State} (h : step s = .continue s') :
    ∃ v : Nat, ∀ p ∈ s.proc.elems, p.involves v = false → p ∈ s'.proc.elems := by
  simp only [step, State.log] at h
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
        refine ⟨r.lhs, ?_⟩
        simp only [unifyVars] at hres
        split at hres
        · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
          obtain ⟨-, rfl, -⟩ := hres
          exact fun p hp _ => hp
        · exact instantiate_proc_mono hres
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact ⟨r.lhs, makeEmpty_proc_mono hres⟩
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact ⟨r.lhs, makeConcrete_proc_mono hres⟩
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              refine ⟨u, ?_⟩
              simp only [unifyVars] at hres
              split at hres
              · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
                obtain ⟨-, rfl, -⟩ := hres
                exact fun p hp _ => hp
              · exact instantiate_proc_mono hres
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨0, fun p hp _ => mem_insertNP_of_mem hp⟩

/-! ## 5. The processed queue grows strictly at a `learn` step -/

/-- The constraints the processed queue holds. -/
def procSys (s : State) : System := (s.proc.elems.map LPart.toConstraint).toFinset

/-- **Every `learn` step adds a genuinely new constraint to the processed queue.**  The
dequeued partition is not `Partition.equals` to anything already processed -- otherwise the
dispatch would have taken the COMMON branch -- so `procSys` strictly grows. -/
theorem learn_procSys_lt {s s' : State} {r : LPart} {rest : PQueue} (hw : Wf s)
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (h : step s = .continue s') :
    (procSys s).card < (procSys s').card := by
  obtain ⟨hproc, -⟩ := step_learn_shape hd h1 h2 h3 h4 h
  obtain ⟨hrMem, -⟩ := PQueue.dequeue_mem hd
  have hfindnone : s.proc.elems.find? (fun x => x.rhs.eqv r.rhs) = none := by
    unfold PQueue.findRHS at h1
    cases hh : s.proc.elems.find? (fun x => x.rhs.eqv r.rhs) with
    | none => rfl
    | some z => rw [hh] at h1; exact absurd h1 (by simp)
  have hnew : r.toConstraint ∉ procSys s := by
    intro hc
    obtain ⟨y, hy, hyr⟩ := List.mem_map.mp (List.mem_toFinset.mp hc)
    have heq : y.eqv r = true :=
      (LPart.eqv_iff_toConstraint_of_wf hw (List.mem_append_right _ hy)
        (List.mem_append_left _ hrMem)).mpr hyr
    unfold LPart.eqv at heq
    rw [Bool.and_eq_true] at heq
    exact (List.find?_eq_none.mp hfindnone y hy) (by simpa using heq.2)
  have hset : procSys s' = insert r.toConstraint (procSys s) := by
    unfold procSys
    rw [hproc]
    ext c
    simp only [List.mem_toFinset, List.mem_map, Finset.mem_insert]
    constructor
    · rintro ⟨y, hy, rfl⟩
      rcases mem_insertNP hy with hy' | rfl
      · exact Or.inr ⟨y, hy', rfl⟩
      · exact Or.inl rfl
    · rintro (rfl | ⟨y, hy, rfl⟩)
      · exact ⟨r, learn_insertNP_self h1 h4, rfl⟩
      · exact ⟨y, mem_insertNP_of_mem hy, rfl⟩
  rw [hset, Finset.card_insert_of_notMem hnew]
  omega


/-! ## 6. (iii) The Stage 7b question

Stage 7b's variant of `splitConcrete` (reuse if it adds a fact, else the shipped mint)
re-opens the empty-row loophole in the ANY-ORDER relation because the same premise pair can
fire again after its conclusions have been absorbed.  In the LOOP it cannot, and the reason
is the single pass.

`resolution` is called from `learnPartitions`' fold over `proc` with `rhs1` the DEQUEUED
partition's right-hand side and `rhs2` that of a processed partition at the same left-hand
side.  So its premise pair is always `(r, p₂)` with `r` dequeued and `p₂ ∈ proc`.  After the
step both are in `proc`, and everything the step enqueues is `Partition.equals`-distinct from
every partition `proc` already held -- so `p₂` cannot come back by re-derivation.  The one
partition `trim` does NOT protect is `r` itself: it is returned to `proc` only AFTER `trim`
has run, so a rule that re-derives `r` in the same batch does enqueue it.  That
re-enqueueing is self-cancelling: at its next dequeue `proc.findRHS` finds `r`, the COMMON
branch fires with `u = r.lhs`, and `unify` at equal variables is the identity, so the
partition is simply dropped. -/
theorem res_pair_single_pass {s s' : State} {r p₂ : LPart} {rest : PQueue}
    (hd : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = false) (h3 : r.rhs.abstr.isEmpty = false)
    (h4 : r.rhs.single? = none) (hp₂ : p₂ ∈ s.proc.elems) (h : step s = .continue s') :
    r ∈ s'.proc.elems ∧ p₂ ∈ s'.proc.elems ∧
      ∀ x ∈ s'.incm.elems, x ∈ rest.elems ∨ p₂.eqv x = false ∨ IsRedirect x := by
  obtain ⟨hkeep, hr, hnew⟩ := learn_single_pass hd h1 h2 h3 h4 h
  refine ⟨hr, hkeep p₂ hp₂, ?_⟩
  intro x hx
  rcases hnew x hx with hx' | hx' | hx'
  · exact Or.inl hx'
  · exact Or.inr (Or.inl (hx' p₂ hp₂))
  · exact Or.inr (Or.inr hx')

/-- **... and a re-derivation that DOES pass `trim` is dropped at its next dequeue.**  If a
partition `x` equal to a processed `y` is dequeued, the dispatch takes the COMMON branch, and
when `x.lhs = y.lhs` that branch is `unify` at equal variables, which returns the queues
unchanged -- `x` is simply gone. -/
theorem common_self_drops {s : State} {rest : PQueue} {x : LPart}
    (hd : s.incm.dequeue = some (x, rest)) (hlhs : s.proc.findRHS x.rhs = some x.lhs) :
    ∃ s' : State, step s = .continue s' ∧ s'.incm = rest ∧ s'.proc = s.proc ∧
      s'.env = s.env := by
  obtain ⟨st, hi, hp, he, hn, hstep⟩ := step_common_branch hd hlhs
  refine ⟨{ st with incm := rest, proc := s.proc, env := s.env }, ?_, rfl, rfl, rfl⟩
  rw [hstep, unifyVars, if_pos (by simp)]


/-! ## 7. (ii) A quantitative bound on the `learn` steps -/

/-- The dispatch conditions of a `learn` step. -/
def IsLearnStep (s : State) : Prop :=
  ∃ (r : LPart) (rest : PQueue), s.incm.dequeue = some (r, rest) ∧
    s.proc.findRHS r.rhs = none ∧ r.rhs.isEmpty = false ∧ r.rhs.abstr.isEmpty = false ∧
    r.rhs.single? = none

/-- `n` consecutive `learn` steps from `s` to `t`. -/
def LearnChain : Nat → State → State → Prop
  | 0, s, t => s = t
  | n + 1, s, t => ∃ s' : State, IsLearnStep s ∧ step s = .continue s' ∧ LearnChain n s' t

/-- **Every `learn` step is paid for by a new processed constraint.**  A chain of `n`
consecutive `learn` steps raises the number of distinct constraints in the processed queue by
at least `n`.  So the number of consecutive `learn` steps is bounded by the size of the
constraint vocabulary the run can reach -- which is what the label-pool invariant of
`Wf.lean` bounds on the concrete side, and what a bound on MINTING would bound on the
variable side. -/
theorem learnChain_card : ∀ (n : Nat) {s t : State}, Wf s → LearnChain n s t →
    (procSys s).card + n ≤ (procSys t).card
  | 0, s, t, _, h => by simp only [LearnChain] at h; subst h; omega
  | n + 1, s, t, hw, h => by
    obtain ⟨s', ⟨r, rest, hd, h1, h2, h3, h4⟩, hstep, hrest⟩ := h
    have hlt := learn_procSys_lt hw hd h1 h2 h3 h4 hstep
    have := learnChain_card n (step_wf hw hstep) hrest
    omega


/-! ## 8. A death in the `empty` branch, at the level of `step` -/

/-- **The loop-level extraction for the `Incompatible instantiations` death.**  Every death of
the `empty` dispatch branch either REFUTES the system the dying state denotes -- and
`step_died_sys` says that is the system its predecessor denoted -- or is one of the two
messages that are not refutations: the SKOLEM refusal (a kinding error) and the
reinstantiation panic (an internal-invariant failure).  This is the statement that plugs
straight into `run_refutes_all`. -/
theorem step_died_empty {s s' : State} {m : String} {r : LPart} {rest : PQueue}
    (hdq : s.incm.dequeue = some (r, rest)) (h1 : s.proc.findRHS r.rhs = none)
    (h2 : r.rhs.isEmpty = true) (h : step s = .died m s') :
    ¬ SSat (sys s') ∨
      m = "Cannot unify skolem variable with empty relation " ++ varStr s.names r.lhs ∨
      m = "panic: reinstantiated type " ++ varStr s.names r.lhs ++ " to ConcreteRho(-,Set())" ++
          " but it was already bound" := by
  obtain ⟨hrMem, hrestMem⟩ := PQueue.dequeue_mem hdq
  obtain ⟨st, hi, hp, he, hn, hstep⟩ := step_empty_branch hdq h1 h2
  rw [hstep] at h
  cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
  | ok w =>
    obtain ⟨ni, np, e⟩ := w
    rw [hres] at h
    exact absurd h (by simp)
  | error m0 =>
    rw [hres] at h
    simp only [StepResult.died.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    have hd := makeEmpty_died (G := sys s)
      (fun x hx => mem_sys_of_incm (hrestMem x hx))
      (fun x hx => mem_sys_of_proc hx)
      (by rw [← toConstraint_of_isEmpty h2]; exact mem_sys_of_incm hrMem) hres
    rcases hd with hd | hd | hd
    · refine Or.inl ?_
      have hstepd : step s = .died m0 st := by rw [hstep, hres]
      rw [step_died_sys hstepd]
      exact hd
    · exact Or.inr (Or.inl hd)
    · exact Or.inr (Or.inr hd)



/-! ## 9. No partition of either queue is a SELF-UNIFICATION

`Q.insert` drops `a <- (a)` at every insertion (`Constraints.scala:492`), and every other
writer of either queue is a filter of an existing one.  So the property is an invariant, and
it is the missing premise of the review's F4 case analysis (`cancellation`'s and
`substitution`'s conclusions can only equal the dequeued premise if `proc` holds a
self-unification). -/

/-- Every partition of both queues is a genuine partition, not `a <- (a)`. -/
def NoSelfUnif (s : State) : Prop := ∀ p ∈ s.parts, p.isSelfUnification = false

def QNoSelf (q : PQueue) : Prop := ∀ p ∈ q.elems, p.isSelfUnification = false

theorem QNoSelf.insertNP {q : PQueue} {x : LPart} (h : QNoSelf q) : QNoSelf (q.insertNP x) := by
  intro p hp
  unfold PQueue.insertNP at hp
  split at hp
  · exact h p hp
  · rename_i hns
    split at hp
    · exact h p hp
    · rcases mem_insertSorted hp with rfl | hp'
      · simpa using hns
      · exact h p hp'

theorem QNoSelf.insertP {q : PQueue} {x : LPart} (h : QNoSelf q) : QNoSelf (q.insertP x) := by
  intro p hp
  unfold PQueue.insertP at hp
  split at hp
  · exact h p hp
  · rename_i hns
    split at hp
    · exact h p hp
    · split at hp
      · exact QNoSelf.insertNP h p hp
      · rcases mem_insertSorted hp with rfl | hp'
        · simpa using hns
        · exact h p hp'

theorem QNoSelf.concatNP : ∀ (ps : List LPart) {q : PQueue}, QNoSelf q → QNoSelf (q.concatNP ps)
  | [], _, h => h
  | _ :: ps, _, h => QNoSelf.concatNP ps (QNoSelf.insertNP h)

theorem QNoSelf.concatP : ∀ (ps : List LPart) {q : PQueue}, QNoSelf q → QNoSelf (q.concatP ps)
  | [], _, h => h
  | _ :: ps, _, h => QNoSelf.concatP ps (QNoSelf.insertP h)

theorem QNoSelf.foldl {α : Type} {f : PQueue → α → PQueue}
    (hf : ∀ q x, QNoSelf q → QNoSelf (f q x)) :
    ∀ (l : List α) (q : PQueue), QNoSelf q → QNoSelf (l.foldl f q)
  | [], _, h => h
  | x :: l, q, h => QNoSelf.foldl hf l (f q x) (hf q x h)

theorem QNoSelf.filter {q : PQueue} (h : QNoSelf q) (f : LPart → Bool) :
    QNoSelf (q.filter f) := fun p hp => h p (List.mem_of_mem_filter hp)

theorem QNoSelf.partition_snd {q : PQueue} (h : QNoSelf q) (f : LPart → Bool) :
    QNoSelf (q.partition f).2 := fun p hp => h p (List.mem_of_mem_filter hp)

theorem QNoSelf.dequeue {q : PQueue} {r : LPart} {rest : PQueue} (h : QNoSelf q)
    (hd : q.dequeue = some (r, rest)) : QNoSelf rest :=
  fun p hp => h p ((PQueue.dequeue_mem hd).2 p hp)

theorem instantiate_noSelf {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : QNoSelf incm) (hp : QNoSelf proc)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) : QNoSelf ni ∧ QNoSelf np := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, -⟩ := h
    exact ⟨QNoSelf.foldl (fun q x hq => QNoSelf.concatP _ hq) _ _ (hi.partition_snd _),
      hp.partition_snd _⟩


theorem makeEmpty_noSelf {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hi : QNoSelf incm) (hp : QNoSelf proc)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) : QNoSelf ni ∧ QNoSelf np := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨rfl, rfl, -⟩ := h2
      exact ⟨QNoSelf.concatP _ (hi.partition_snd _), hp.partition_snd _⟩


theorem destructiveSub_noSelf {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (hi : QNoSelf incm) (hp : QNoSelf proc)
    (h : destructiveSub v rhs incm proc = .ok (ni, np)) : QNoSelf ni ∧ QNoSelf np := by
  simp only [destructiveSub] at h
  obtain ⟨srs, hsrs, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨rfl, rfl⟩ := h2
  constructor
  · refine QNoSelf.concatP _ ?_
    split
    · exact QNoSelf.concatP _ (by split; exacts [hi, (hi.partition_snd _).filter _])
    · split
      · exact hi
      · exact (hi.partition_snd _).filter _
  · split
    · exact QNoSelf.concatNP _ (by split; exacts [hp, (hp.partition_snd _).filter _])
    · split
      · exact hp
      · exact (hp.partition_snd _).filter _

theorem makeConcrete_noSelf {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hi : QNoSelf incm) (hp : QNoSelf proc)
    (h : makeConcrete v fs incm proc = .ok (ni, np)) : QNoSelf ni ∧ QNoSelf np := by
  simp only [makeConcrete] at h
  obtain ⟨u1, hu1, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨rfl, rfl⟩ := h3
  obtain ⟨hni, hnp⟩ := destructiveSub_noSelf hi hp hw
  exact ⟨QNoSelf.concatP _ hni, QNoSelf.insertNP hnp⟩

/-- **No partition of either queue is ever a self-unification.** -/
theorem step_noSelf {s s' : State} (hi : QNoSelf s.incm) (hp : QNoSelf s.proc)
    (h : step s = .continue s') : QNoSelf s'.incm ∧ QNoSelf s'.proc := by
  simp only [step, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    have hrest : QNoSelf rest := hi.dequeue hdq
    split at h
    · rename_i u _
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
          obtain ⟨rfl, rfl, -⟩ := hres
          exact ⟨hrest, hp⟩
        · exact instantiate_noSelf hrest hp hres
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact makeEmpty_noSelf hrest hp hres
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact makeConcrete_noSelf hrest hp hres
        · split at h
          · rename_i u _
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
                obtain ⟨rfl, rfl, -⟩ := hres
                exact ⟨hrest, hp⟩
              · exact instantiate_noSelf hrest hp hres
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact ⟨QNoSelf.concatP _ hrest, QNoSelf.insertNP hp⟩

/-- The invariant, as a statement about the state. -/
theorem step_NoSelfUnif {s s' : State} (h0 : NoSelfUnif s) (h : step s = .continue s') :
    NoSelfUnif s' := by
  obtain ⟨h1, h2⟩ := step_noSelf (fun p hp => h0 p (List.mem_append_left _ hp))
    (fun p hp => h0 p (List.mem_append_right _ hp)) h
  intro p hp
  rcases List.mem_append.mp hp with hp' | hp'
  · exact h1 p hp'
  · exact h2 p hp'

/-- **The processed queue holds no self-unification** -- the premise the review's F4 case
analysis needs. -/
theorem proc_no_self_unification {s : State} (h : NoSelfUnif s) :
    ∀ p ∈ s.proc.elems, p.isSelfUnification = false :=
  fun p hp => h p (List.mem_append_right _ hp)

/-- The initial state of a solve satisfies it: `PQueue.ofList` inserts through `Q.insert`. -/
theorem noSelfUnif_initial {q : PQueue} {ps : List LPart} (hq : q = PQueue.ofList ps)
    (fl : Flags) (ns : Names) (site : String) (e : Env) (su : Sup) (lo : Nat) (t : List String) :
    NoSelfUnif { incm := q, proc := PQueue.empty, env := e, su := su, trace := t,
                 flags := fl, names := ns, site := site, su0 := lo } := by
  intro p hp
  rcases List.mem_append.mp hp with hp' | hp'
  · rw [hq] at hp'
    exact QNoSelf.concatNP _ (by intro x hx; cases hx) p hp'
  · cases hp'


/-! ## 10. The processed queue holds no INFINITE-ROW partition either

`u <- (u, C)` with `C` nonempty is `selfSubstitution`'s death (`Constraints.scala:1157`), and
the L3 re-review's R-B observes that it never sits in `proc` for a reason that needs no order
argument: `proc` has exactly four writers, three of them filters of itself, and the fourth --
`proc + r` at the end of `incorporateAll`'s general branch -- is reached only when
`learnPartitions` RETURNED, which for a self-mentioning left-hand side already forces the
concrete part empty. -/

/-- The shape `selfSubstitution` dies on: the left-hand variable is one of its own parts and
the concrete part is nonempty. -/
def PInfRow (p : LPart) : Prop :=
  p.rhs.abstr.contains p.lhs = true ∧ p.rhs.conc.isEmpty = false

instance (p : LPart) : Decidable (PInfRow p) := inferInstanceAs (Decidable (_ ∧ _))

def QNoInf (q : PQueue) : Prop := ∀ p ∈ q.elems, ¬ PInfRow p

/-- Every partition of the PROCESSED queue is a partition `selfSubstitution` would not die
on. -/
def NoInfRow (s : State) : Prop := QNoInf s.proc

theorem QNoInf.insertNP {q : PQueue} {x : LPart} (h : QNoInf q) (hx : ¬ PInfRow x) :
    QNoInf (q.insertNP x) := by
  intro p hp
  rcases mem_insertNP hp with hp' | rfl
  · exact h p hp'
  · exact hx

theorem QNoInf.concatNP : ∀ (ps : List LPart) (q : PQueue), QNoInf q →
    (∀ p ∈ ps, ¬ PInfRow p) → QNoInf (q.concatNP ps)
  | [], _, h, _ => h
  | p :: ps, q, h, hps =>
    QNoInf.concatNP ps (q.insertNP p) (QNoInf.insertNP h (hps p (by simp)))
      (fun r hr => hps r (by simp [hr]))

theorem QNoInf.filter {q : PQueue} (h : QNoInf q) (f : LPart → Bool) : QNoInf (q.filter f) :=
  fun p hp => h p (List.mem_of_mem_filter hp)

theorem QNoInf.partition_snd {q : PQueue} (h : QNoInf q) (f : LPart → Bool) :
    QNoInf (q.partition f).2 := fun p hp => h p (List.mem_of_mem_filter hp)

/-- **`learnPartitions` returning already excludes the infinite-row shape** -- this is the
one-line fact the re-review's four-writer argument turns on, and it is about `.ok`, not about
when the partition would be dequeued. -/
theorem learnPartitions_notInfRow {fl : Flags} {ns : Names} {env : Env} {v : Nat} {rhs1 : RHS}
    {incm proc : PQueue} {su : Sup} {S : SSet LPart} {su' : Sup}
    (h : learnPartitions fl ns env v rhs1 incm proc su = .ok (S, su')) :
    ¬ (rhs1.abstr.contains v = true ∧ rhs1.conc.isEmpty = false) := by
  rintro ⟨hc, hne⟩
  simp only [learnPartitions] at h
  rw [if_pos hc] at h
  cases hss : selfSubstitution ns v rhs1.abstr rhs1.conc with
  | error m => rw [hss] at h; simp only [bind, Except.bind] at h; exact absurd h (by simp)
  | ok T =>
    simp only [selfSubstitution] at hss
    split at hss
    · rename_i hce; exact absurd hce (by simp [hne])
    · exact absurd hss (by simp)

theorem instantiate_noInf {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hp : QNoInf proc)
    (h : instantiate ns v u incm proc env = .ok (ni, np, e)) : QNoInf np := by
  simp only [instantiate] at h
  split at h
  · exact absurd h (by simp)
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    obtain ⟨-, rfl, -⟩ := h
    exact hp.partition_snd _

theorem makeEmpty_noInf {ns : Names} {v : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (hp : QNoInf proc)
    (h : makeEmpty ns v incm proc env = .ok (ni, np, e)) : QNoInf np := by
  simp only [makeEmpty] at h
  obtain ⟨nps, hnps, h2⟩ := except_bind_ok h
  split at h2
  · exact absurd h2 (by simp)
  · split at h2
    · exact absurd h2 (by simp)
    · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h2
      obtain ⟨-, rfl, -⟩ := h2
      exact hp.partition_snd _

theorem destructiveSub_noInf {v : Nat} {rhs : RHS} {incm proc : PQueue} {ni np : PQueue}
    (hp : QNoInf proc) (h : destructiveSub v rhs incm proc = .ok (ni, np)) : QNoInf np := by
  simp only [destructiveSub] at h
  obtain ⟨srs, hsrs, h2⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h2
  obtain ⟨-, rfl⟩ := h2
  split
  · refine QNoInf.concatNP _ _ (by split; exacts [hp, (hp.partition_snd _).filter _]) ?_
    intro x hx
    exact hp x (List.mem_of_mem_filter (List.mem_reverse.mp
      (SSet.mem_ofList (SSet.mem_filter hx))))
  · split
    · exact hp
    · exact (hp.partition_snd _).filter _

theorem makeConcrete_noInf {v : Nat} {fs : SSet Lbl} {incm proc : PQueue} {ni np : PQueue}
    (hp : QNoInf proc) (h : makeConcrete v fs incm proc = .ok (ni, np)) : QNoInf np := by
  simp only [makeConcrete] at h
  obtain ⟨u1, hu1, h2⟩ := except_bind_ok h
  obtain ⟨w, hw, h3⟩ := except_bind_ok h2
  simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at h3
  obtain ⟨-, rfl⟩ := h3
  refine QNoInf.insertNP (destructiveSub_noInf hp hw) ?_
  rintro ⟨hcon, -⟩
  exact absurd hcon (by simp [RHS.ofConcr, SSet.contains, SSet.empty])

/-- **The processed queue never holds `u <- (u, C)` with `C` nonempty.** -/
theorem step_NoInfRow {s s' : State} (h0 : NoInfRow s) (h : step s = .continue s') :
    NoInfRow s' := by
  simp only [NoInfRow] at h0 ⊢
  simp only [step, State.log] at h
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
        simp only [unifyVars] at hres
        split at hres
        · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at hres
          obtain ⟨-, rfl, -⟩ := hres
          exact h0
        · exact instantiate_noInf h0 hres
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact makeEmpty_noInf h0 hres
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact makeConcrete_noInf h0 hres
        · split at h
          · rename_i u _
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
                obtain ⟨-, rfl, -⟩ := hres
                exact h0
              · exact instantiate_noInf h0 hres
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              exact QNoInf.insertNP h0 (learnPartitions_notInfRow hlp)

/-- The initial state satisfies it: `proc` starts empty. -/
theorem noInfRow_initial {q : PQueue} (fl : Flags) (ns : Names) (site : String) (e : Env)
    (su : Sup) (lo : Nat) (t : List String) :
    NoInfRow { incm := q, proc := PQueue.empty, env := e, su := su, trace := t,
               flags := fl, names := ns, site := site, su0 := lo } := by
  intro p hp
  cases hp

end Rowpartition.Loop
