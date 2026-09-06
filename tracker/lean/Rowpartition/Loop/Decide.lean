/-
# S2: the three NO-FALSE-ACCEPTANCE layers, executable

The model half of `tracker/loopmodel/S2-DESIGN.md`, mirroring the Scala the same stage put
behind flags in `Constraints.scala` / `Subst.scala`.  **Every flag defaults to OFF**
(`Flags.rowSoundBare`, `.rowSoundSat`, `.rowSoundDecide`), and with them off every definition
here reduces to the shipped one:

* `stepS` is `step` (`stepS_of_flag_off`),
* `runS` is `run` (`runS_of_flag_off`),
* and `solveSeed` never calls `labelDecide` or the saturated `labelClash`.

## The three layers

* **(i) `bareExact`** — `Constraints.makeConcrete`'s compatibility fold with `ensureSuperset`
  replaced by `ensureExactly` at a definition with NO abstract part.  It is written as a
  PRE-CHECK ahead of `step`'s `concrete` branch rather than as a change to `makeConcrete`,
  which is what keeps every S1 theorem about `step` literally true: `stepS` can only turn a
  `.continue`/`.done` into a `.died` (`stepS_continue`), never move a continuation.
* **(ii)** is `labelClash` on the SATURATED set, and lives in `Seed.lean` beside the input
  check it duplicates; nothing new is needed here.
* **(iii) `labelDecide`** — the COMPLETE per-label decision: `checkLabel`'s five propagation
  rules to a fixpoint, then a CASE SPLIT.  A branch that assigns every bit is CHECKED against
  every partition (`modelChecks`) before SAT is returned, so "passes" means "a model was
  exhibited and verified".  A budget bounds the decision nodes per label; on exhaustion the
  answer is `NoVerdict` and nothing is refuted.

## One deliberate difference from the Scala, and why it is harmless

The compiler's propagation is WORKLIST-driven (`Constraints.decideLabel`); this one is
PASS-based, exactly like `Loop/Json.lean`'s `checkLabel` and the Scala `checkLabel` it
transcribes.  Both compute the least fixpoint of the same five monotone rules, so they agree
on the VERDICT (clash or not, and the assignment when there is no clash); they can disagree
on WHICH partition is blamed for a clash and hence on the message.  Nothing compares those:
`tracker/tools/looptrace-diff.py`'s `KEEP` is `step learn in inpart sat solve`, and a
refutation contributes no record at all — the compiler dies before `q.expand`, and so does
the model.
-/
import Rowpartition.Loop.Json

namespace Rowpartition.Loop

/-! ## 1. Layer (i): bare-row exactness -/

/-- `Constraints.ensureExactly` (S2 layer (i)).  Same death as `ensureSuperset` — S1's death
site 7 — raised on `C ≠ fs` rather than on `C ⊄ fs`. -/
def ensureExactly (sub sup : SSet Lbl) : Except String Unit :=
  if sub.eqv sup then .ok ()
  else .error ("Row types failed to unify: R1 = " ++ labelSetStr sub ++ " R2 = " ++
               labelSetStr sup)

/-- `makeConcrete`'s compatibility fold under the flag: `ensureExactly` at a BARE definition
of `v` (no abstract part), `ensureSuperset` at every other.  Same order as `makeConcrete`'s
own fold — `proc` then `incm` — so the message is the one the compiler prints. -/
def bareExact (v : Nat) (fs : SSet Lbl) (incm proc : PQueue) : Except String Unit :=
  ((proc.elems ++ incm.elems).filter (fun p => p.lhs == v)).foldl
    (fun (acc : Except String Unit) (p : LPart) => do
      let _ ← acc
      if p.rhs.abstr.isEmpty then ensureExactly p.rhs.conc fs else ensureSuperset p.rhs.conc fs)
    (.ok ())

/-- `step` with layer (i) in front of its `concrete` branch.  The pre-check runs exactly
where `makeConcrete`'s fold runs — after the `step` record is written, before anything is
deleted — so a refusal produces the compiler's records and then dies. -/
def stepS (s : State) : StepResult :=
  match s.incm.dequeue with
  | none => step s
  | some (r, rest) =>
    if s.flags.rowSoundBare && (s.proc.findRHS r.rhs).isNone &&
        !r.rhs.isEmpty && r.rhs.abstr.isEmpty then
      match bareExact r.lhs r.rhs.conc rest s.proc with
      | .error m =>
        .died m (s.log ("step\t" ++ s.site ++ "\tconcrete\t" ++ r.toStr s.names ++
                        "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size))
      | .ok _ => step s
    else step s

/-- Iterate `stepS`.  Same shape as `run`; the fuel is a bound on dequeues. -/
def runS : State → Nat → RunResult
  | s, 0 => .outOfFuel s
  | s, n + 1 =>
    match stepS s with
    | .done s' => .solved s'
    | .died m s' => .rejected m s'
    | .continue s' => runS s' n

/-! ## 2. Layer (iii): the complete per-label decision -/

/-- The answer for ONE label. -/
inductive DecideRes where
  /-- A total assignment that was CHECKED against every partition. -/
  | sat (bits : List (Nat × Bool))
  /-- No assignment exists; `at_` is the partition (by left-hand variable) at which the
  search's first clash was found, and `why` the rule that found it. -/
  | unsat (at_ : Nat) (why : String)
  /-- The search stopped without an answer.  Refutes NOTHING. -/
  | noVerdict (why : String)
deriving Repr, Inhabited

/-- The variables of a partition list, in order of first appearance. -/
def decideVars (ps : List LPart) : List Nat :=
  (ps.foldl (fun acc p => acc ++ (p.lhs :: p.rhs.abstr.toList)) []).eraseDups

/-- Look a bit up. -/
def bitOf (bits : List (Nat × Bool)) (v : Nat) : Option Bool :=
  (bits.find? (fun q => q.1 == v)).map (·.2)

/-- The assignment a bit list denotes: unset reads as `false`. -/
def bitFun (bits : List (Nat × Bool)) : Nat → Bool := fun v => bitOf bits v == some true

/-! ### The Boolean shadow at one label, in the loop's own vocabulary

`Rowpartition.BSat` is stated over a `Constraint`, whose variable part is a DEDUPLICATED
sorted list; the loop carries an `SSet`, and the propagation reads `abstr.toList`.  `LSat` is
the same predicate over the list the code actually reads, and §5 relates the two. -/

/-- How many parts of `p` carry `l` under `b`. -/
def lcount (b : Nat → Bool) (l : Lbl) (p : LPart) : Nat :=
  (p.rhs.abstr.toList.filter b).length + (if p.rhs.conc.contains l then 1 else 0)

/-- `p`'s Boolean shadow at `l`: at most one part carries the label, and the whole carries
it iff exactly one part does. -/
def LSat (b : Nat → Bool) (l : Lbl) (p : LPart) : Prop :=
  lcount b l p ≤ 1 ∧ b p.lhs = decide (lcount b l p = 1)

/-- The shadow of a whole partition list. -/
def LModels (b : Nat → Bool) (l : Lbl) (ps : List LPart) : Prop := ∀ p ∈ ps, LSat b l p

instance (b : Nat → Bool) (l : Lbl) (p : LPart) : Decidable (LSat b l p) := by
  unfold LSat; infer_instance

/-! ### Propagation

`forcedBy` is `Constraints.checkLabel`'s five rules for ONE partition, returning every bit
they force at once instead of writing them in sequence; the five message strings are the
compiler's.  The Scala applies the rules in order inside one pass and re-reads the map
between them, this returns them together and lets the merge find the disagreement -- the same
least fixpoint, and the same conclusion in the one place the two orders differ (a variable
that is a part of its own partition is forced BOTH ways, which is a refutation either way;
`Rowpartition.LabelAlgo.algo_selfPart_refuted`).

The compiler's own propagation is WORKLIST-driven where this is pass-based.  Both compute the
least fixpoint of the same rules, so they agree on the VERDICT; they can differ on which
partition is blamed for a clash, and nothing compares that (`looptrace-diff.py`'s `KEEP`). -/

/-! The five rules are factored into a GUARD (the three refusals) and the bits they force,
so that soundness splits into "at a model the guard is false" and "every forced bit is the
model's". -/

/-- How many parts of `p` are already KNOWN to carry `l`, plus the concrete part. -/
def onesOf (l : Lbl) (bits : List (Nat × Bool)) (p : LPart) : Nat :=
  p.rhs.abstr.toList.countP (fun u => bitOf bits u == some true) +
    (if p.rhs.conc.contains l then 1 else 0)

/-- The parts of `p` not yet decided. -/
def unkOf (bits : List (Nat × Bool)) (p : LPart) : List Nat :=
  p.rhs.abstr.toList.filter (fun u => (bitOf bits u).isNone)

/-- The three shapes in which one partition is ALREADY violated by what is known: two parts
carry the label; the whole is known absent while the concrete part carries it; the whole is
known present while nothing can carry it. -/
def fbGuard (l : Lbl) (bits : List (Nat × Bool)) (p : LPart) : Prop :=
  1 < onesOf l bits p ∨
  (bitOf bits p.lhs = some false ∧ p.rhs.conc.contains l = true) ∨
  (bitOf bits p.lhs = some true ∧ onesOf l bits p = 0 ∧ unkOf bits p = [])

instance (l : Lbl) (bits : List (Nat × Bool)) (p : LPart) : Decidable (fbGuard l bits p) := by
  unfold fbGuard; infer_instance

/-- The bits the five rules force, with the message the compiler prints for each. -/
def fbBits (l : Lbl) (bits : List (Nat × Bool)) (p : LPart) : List (Nat × Bool × String) :=
  (if onesOf l bits p = 1 then
     (p.lhs, true, "a part contains it but the whole does not") ::
       (unkOf bits p).map (fun u => (u, false, "two parts of one partition both contain it"))
   else []) ++
  (if bitOf bits p.lhs = some false then
     (unkOf bits p).map (fun u => (u, false, "a part contains it but the whole does not"))
   else []) ++
  (if onesOf l bits p = 0 ∧ unkOf bits p = [] then
     [(p.lhs, false, "the whole contains it but no part does")] else []) ++
  (if bitOf bits p.lhs = some true ∧ onesOf l bits p = 0 then
     match unkOf bits p with
     | [u] => [(u, true, "the whole contains it but no part can")]
     | _ => []
   else [])

/-- The bits one partition forces, or `none` for an immediate contradiction. -/
def forcedBy (l : Lbl) (bits : List (Nat × Bool)) (p : LPart) :
    Option (List (Nat × Bool × String)) :=
  if fbGuard l bits p then none else some (fbBits l bits p)

/-- Merge one forced bit into the assignment.  A bit that disagrees with one already there is
a CLASH -- which is where `setVar`'s `note` fires in the Scala. -/
def mergeBit (st : List (Nat × Bool) × Bool × Option (Nat × String)) (at_ : Nat)
    (w : Nat × Bool × String) : List (Nat × Bool) × Bool × Option (Nat × String) :=
  if st.2.2.isSome then st else
  match bitOf st.1 w.1 with
  | some b0 => if b0 == w.2.1 then st else (st.1, st.2.1, some (at_, w.2.2))
  | none => (st.1 ++ [(w.1, w.2.1)], true, st.2.2)

/-- ONE pass over every partition. -/
def onePass (ps : List LPart) (l : Lbl)
    (st0 : List (Nat × Bool) × Bool × Option (Nat × String)) :
    List (Nat × Bool) × Bool × Option (Nat × String) :=
  ps.foldl (fun st p =>
    if st.2.2.isSome then st else
    match forcedBy l st.1 p with
    | none => (st.1, st.2.1, some (p.lhs, "two parts of one partition both contain it"))
    | some ws => ws.foldl (fun a w => mergeBit a p.lhs w) st) st0

/-- Iterate `onePass` to a fixpoint: a pass that sets nothing stops it, and the fuel is one
pass per bit the propagation can possibly set, plus two. -/
def propagate (ps : List LPart) (l : Lbl) :
    Nat → List (Nat × Bool) → List (Nat × Bool) × Option (Nat × String)
  | 0, bits => (bits, none)
  | f + 1, bits =>
    let (bits', changed, clash) := onePass ps l (bits, false, none)
    match clash with
    | some c => (bits', some c)
    | none => if changed then propagate ps l f bits' else (bits', none)

/-- **The check that makes "passes" mean something.**  A TOTAL assignment read back against
every partition directly: at most one part carries the label, and the whole carries it iff
exactly one part does.  Nothing derived, nothing cached. -/
def modelChecks (ps : List LPart) (l : Lbl) (bits : List (Nat × Bool)) : Bool :=
  ps.all (fun p => decide (LSat (bitFun bits) l p))

/-! ### The case split

`searchLabel` is DPLL for one label: propagate, then branch on the first unassigned bit,
FALSE first.  The answer is `some m` for a model that has been CHECKED, and `none` otherwise,
with a `cut` flag saying whether the search was cut short: `cut = false` with `none` is "no
assignment exists", `cut = true` with `none` is NO VERDICT and refutes nothing.  `budget`
bounds the decision NODES and is the hypothesis the completeness theorem carries; `d` bounds
the recursion (one decision assigns at least its own variable, so the number of variables is
enough, and running out is a cut like any other). -/

/-- Structural recursion on `d`, deliberately: a well-founded definition does not reduce in
the KERNEL, and §10 of `Loop/NoFalseAccept.lean` checks the three witness seeds by `rfl`. -/
def searchLabel (ps : List LPart) (l : Lbl) (vs : List Nat) :
    Nat → List (Nat × Bool) → Nat → Nat → Option (List (Nat × Bool)) × Nat × Bool
  | 0, _, nodes, _ => (none, nodes, true)
  | d + 1, bits, nodes, budget =>
    match vs.find? (fun v => (bitOf bits v).isNone) with
    | none => if modelChecks ps l bits then (some bits, nodes, false) else (none, nodes, true)
    | some v =>
      if budget ≤ nodes then (none, nodes, true)
      else
        match propagate ps l (vs.length + 2) (bits ++ [(v, false)]) with
        | (_, some _) =>
          -- the FALSE branch is closed by propagation, which is sound: not a cut
          match propagate ps l (vs.length + 2) (bits ++ [(v, true)]) with
          | (_, some _) => (none, nodes + 1, false)
          | (b1, none) => searchLabel ps l vs d b1 (nodes + 1) budget
        | (b0, none) =>
          match searchLabel ps l vs d b0 (nodes + 1) budget with
          | (some m, n, c) => (some m, n, c)
          | (none, n, true) => (none, n, true)
          | (none, n, false) =>
            match propagate ps l (vs.length + 2) (bits ++ [(v, true)]) with
            | (_, some _) => (none, n, false)
            | (b1, none) => searchLabel ps l vs d b1 n budget

/-- One label, decided completely. -/
def decideLabel (ps : List LPart) (l : Lbl) (budget : Nat) : DecideRes × Nat :=
  let vs := decideVars ps
  let blame := (ps.head?.map (·.lhs)).getD 0
  match propagate ps l (vs.length + 2) [] with
  | (_, some (a, why)) => (.unsat a why, 0)
  | (bits, none) =>
    match searchLabel ps l vs (vs.length + 1) bits 0 budget with
    | (some m, n, _) => (.sat m, n)
    | (none, n, true) =>
      (.noVerdict ("the search was cut short after " ++ toString n ++
        " decisions (budget " ++ toString budget ++ "); nothing is refuted"), n)
    | (none, n, false) =>
      (.unsat blame ("no assignment of this field to the parts satisfies every partition" ++
        " (complete search, " ++ toString n ++ " cases; unit propagation alone does not" ++
        " see it)"), n)

/-- The labels a partition list mentions -- `labelClash`'s own range, as a set.  The compiler
folds them into an `SSet` and iterates it in HASH order (S2 review V-13a); this collects them
into a list in partition order.  The SET is the same, so only WHICH of several refuting labels
is reported can differ, never whether the system is refuted -- a refutation at any label is a
refutation of the system.  The same is true of the blamed VARIABLE inside one label (V-13b):
the search keeps the first clash it saw anywhere, which need not belong to the branch that
closes the proof.  Neither is compared by anything: `looptrace-diff.py`'s `KEEP` excludes the
`rsound` records, and a refutation emits none. -/
def mentionedLabels (ps : List LPart) : List Lbl :=
  ps.flatMap (fun p => p.rhs.conc.toList)

theorem mem_mentionedLabels {ps : List LPart} {x : Lbl} :
    x ∈ mentionedLabels ps ↔ ∃ p ∈ ps, x ∈ p.rhs.conc.elems := by
  rw [mentionedLabels, List.mem_flatMap]
  simp [SSet.toList]

/-- The verdict for a whole partition list. -/
inductive DecideVerdict where
  /-- Every mentioned label's problem has a model, and every model was checked. -/
  | sat
  /-- No model at `label`. -/
  | refuted (label : Lbl) (at_ : Nat) (why : String)
  /-- The search stopped without an answer at `label`.  Refutes nothing. -/
  | noVerdict (label : Lbl) (why : String)
deriving Repr, Inhabited

/-- Decide a list of labels in order, stopping at the SOLVE's node cap.

TWO caps, and either can lapse the theorem: `budget` bounds the nodes at ONE label and
`solveBudget` their SUM over the solve (S2 review V-12 -- the per-label budget alone bounds
the worst case at `#labels` times the per-label cost).  A label reached after the solve's cap
is spent is `noVerdict` and refutes nothing, exactly like a per-label exhaustion. -/
def decideFrom (ps : List LPart) (budget solveBudget : Nat) :
    List Lbl → Nat → List (Lbl × DecideRes × Nat)
  | [], _ => []
  | l :: ls, spent =>
    if solveBudget ≤ spent then
      (l, .noVerdict ("the solve's decision budget of " ++ toString solveBudget ++
         " nodes was spent before this field was decided"), 0) ::
        decideFrom ps budget solveBudget ls spent
    else
      let (r, n) := decideLabel ps l (min budget (solveBudget - spent))
      (l, r, n) :: decideFrom ps budget solveBudget ls (spent + n)

/-- Every mentioned label, decided. -/
def decideAll (ps : List LPart) (budget solveBudget : Nat) : List (Lbl × DecideRes × Nat) :=
  decideFrom ps budget solveBudget (mentionedLabels ps) 0

/-- **Layer (iii).**  Decide every mentioned label; a refutation wins, else a no-verdict,
else SAT.  Returns the verdict, the decision nodes spent, and how many labels were decided.

Every label is decided even when an earlier one already refuted: it costs a few microseconds
on a corpus whose solves mention at most ten labels, and it is what makes "SAT means every
label was decided SAT" a one-line consequence of `List.findSome?_eq_none_iff`. -/
def labelDecide (ps : List LPart) (budget solveBudget : Nat) : DecideVerdict × Nat × Nat :=
  let rs := decideAll ps budget solveBudget
  let nodes := (rs.map (fun r => r.2.2)).foldl (· + ·) 0
  match rs.findSome? (fun r => match r.2.1 with | .unsat a w => some (r.1, a, w) | _ => none) with
  | some (l, a, w) => (.refuted l a w, nodes, rs.length)
  | none =>
    match rs.findSome? (fun r => match r.2.1 with | .noVerdict w => some (r.1, w) | _ => none) with
    | some (l, w) => (.noVerdict l w, nodes, rs.length)
    | none => (.sat, nodes, rs.length)

/-- The diagnostic the compiler raises for a layer-(ii) or layer-(iii) refutation. -/
def rowUnsatMsg (l : Lbl) (why : String) : String :=
  "Row partitions are unsatisfiable at field '" ++ Lbl.toStr l ++ "': " ++ why

end Rowpartition.Loop
