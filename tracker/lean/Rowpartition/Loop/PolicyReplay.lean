/-
# D1 Part B: replaying a trace UNDER A DEQUEUE POLICY

`Loop/Policy.lean` gives `stepP`, and `Loop/Main.lean`'s `--policy=` census runs it; but the
census reports counts, not RECORDS, and the gate Part B has to pass is the L2 corpus
DIFFERENTIAL under the policy — the compiler's `-Dermine.dequeuePolicy=smallcanon` trace
against the model's, record for record.  That needs `solveSeed`'s record printer driven by
`stepP` instead of `step`, which is what this module adds.

It cannot live in `Loop/Seed.lean`, where `solveSeed` is: `Seed` is imported by `Replay`, which
is imported by `Main`, while `Policy` sits on the `Depth`/`VocFix` branch of the import graph.
This module is where the two branches meet, and it imports both.

WHAT IS COPIED AND WHY.  `stepSP` is `Loop/Decide.lean`'s `stepS` with the dequeue call
replaced, exactly as `stepP` is `step` with the dequeue call replaced, and
`stepSP_shipped` is the `rfl` that says the default is unchanged.  `solveSeedP` is
`Seed.solveSeed` with `runS` replaced by `runSP`; every other line — the early label check, S2's
layer (iii), the `in`/`inpart`/`sat`/`solve` population records, the late label check — is the
same, because the policy changes WHICH partition is dequeued and nothing else.
-/
import Rowpartition.Loop.Replay
import Rowpartition.Loop.Policy

namespace Rowpartition.Loop

/-! ## 1. `stepS` under a policy -/

/-- `Loop/Decide.lean`'s `stepS`, with `pop` taking a policy.  S2's layer (i) pre-check is
applied to the partition THE POLICY dequeues, which is the only partition the step will look
at. -/
def stepSP (pol : Policy) (a : Aux) (s : State) : StepResult :=
  match dequeuePol pol a s.incm with
  | none => stepP pol a s
  | some (r, rest) =>
    if s.flags.rowSoundBare && (s.proc.findRHS r.rhs).isNone &&
        !r.rhs.isEmpty && r.rhs.abstr.isEmpty then
      match bareExact r.lhs r.rhs.conc rest s.proc with
      | .error m =>
        .died m (s.log ("step\t" ++ s.site ++ "\tconcrete\t" ++ r.toStr s.names ++
                        "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size))
      | .ok _ => stepP pol a s
    else stepP pol a s

/-- **The default is the shipped loop, definitionally** — the same guarantee `stepP_shipped`
gives for `step`, so a replay at `--policy=shipped` is the replay it always was. -/
theorem stepSP_shipped (a : Aux) (s : State) : stepSP .shipped a s = stepS s := rfl

/-- `runS` under a policy AND a draw budget, threading the policy's auxiliary state.  `b = 0`
is the budget off, which is the default everywhere.

The budget is tested BEFORE the dequeue, on the state the step is given -- the shape
`Loop/Budget.lean`'s `stepBud` has, and, since Part B, the shape `Constraints.incorporateAll`
has too: the compiler counts at its two `fresh` sites and tests once per dequeue at the top of
the loop.  So the two sides stop on the SAME dequeue and the differential can be run with the
budget on. -/
def runSP (pol : Policy) (d0 b : Nat) : Aux → State → Nat → RunResult
  | _, s, 0 => .outOfFuel s
  | a, s, n + 1 =>
    if b != 0 && d0 + b < s.su.drawn then
      .rejected (budgetMsg s.site d0 b s.su.drawn) s
    else
      match stepSP pol a s with
      | .done s' => .solved s'
      | .died m s' => .rejected m s'
      | .continue s' => runSP pol d0 b (a.next pol s') s' n

/-! ## 2. `solveSeed` under a policy -/

/-- `Seed.solveSeed`, with `runSP` in place of `runS`.  Identical in every other line. -/
def solveSeedP (pol : Policy) (bud : Nat) (fl : Flags) (site : String) (loc : String)
    (cs : List CsItem) (ns : Names) (su0 : Sup) (fuel : Nat)
    (envFacts : List LPart := []) : SolveOut :=
  let tag := "\t" ++ site ++ "\t" ++ loc ++ "\t"
  let parts := cs.filterMap CsItem.part?
  let inRecs := (withIndex parts).map (fun (p, i) =>
    "in" ++ tag ++ toString i ++ "\t" ++ ITerm.toStr ns p.lhs ++ "\t" ++
    String.intercalate " | " (p.rhs.map (ITerm.toStr ns)))
  match buildQueue cs su0 with
  | .error m =>
    { records := [], verdict := "REJECTED", message := m, env := {}, drawn := 0, sat := [] }
  | .ok (q, su1) =>
    let early :=
      if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none
    match early with
    | some (l, _, msg) =>
      { records := [],
        verdict := "REJECTED",
        message := "Row partitions are unsatisfiable at field '" ++ Lbl.toStr l ++ "': " ++ msg,
        env := {}, drawn := su1.drawn, sat := [] }
    | none =>
    match (if fl.rowSoundDecide then
             some (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                                fl.rowSoundSolveBudget).1
           else none) with
    | some (.refuted l _ why) =>
      { records := [], verdict := "REJECTED", message := rowUnsatMsg l why,
        env := {}, drawn := su1.drawn, sat := [] }
    | _ =>
      let st0 : State :=
        { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := fl,
          names := ns, site := site, su0 := su0.lo }
      -- the EFFECTIVE budget: `Policy.effBudget` mirrors the compiler's rule that
      -- `-Dermine.solveBudget` is ignored under the shipped dequeue order (D1B review).
      match runSP pol su1.drawn (effBudget pol bud) (Aux.init pol st0) st0 fuel with
      | .rejected m s =>
        { records := s.trace.reverse, verdict := "REJECTED", message := m, env := s.env,
          drawn := s.su.drawn, sat := [] }
      | .outOfFuel s =>
        { records := s.trace.reverse, verdict := "FUEL", message := "", env := s.env,
          drawn := s.su.drawn, sat := s.proc.elems }
      | .solved s =>
        let ps := s.proc.elems
        let late :=
          match (if fl.rowSoundSat then labelClash ns ps else none) with
          | some c => some c
          | none => if fl.labelCheck && !fl.labelCheckEarly then labelClash ns q.elems else none
        match late with
        | some (l, _, msg) =>
          { records := s.trace.reverse, verdict := "REJECTED",
            message := "Row partitions are unsatisfiable at field '" ++ Lbl.toStr l ++ "': " ++ msg,
            env := s.env, drawn := s.su.drawn, sat := ps }
        | none =>
          let inpartRecs :=
            (withIndex q.elems).map (fun (p, i) => popRecord "inpart" site loc ns i p)
          let satRecs := (withIndex ps).map (fun (p, i) => popRecord "sat" site loc ns i p)
          let derived := ps.filter (fun p => p.inf.isSome)
          let concrete := parts.any (fun p => (p.lhs :: p.rhs).any (fun t =>
            match t with | .concRho f => !f.isEmpty | _ => false))
          let arities := sortNats (parts.map (fun p => p.rhs.length))
          let solveRec :=
            "solve\t" ++ site ++ "\t" ++ loc ++ "\t" ++ toString parts.length ++ "\t" ++
            toString q.elems.length ++ "\t" ++ toString ps.length ++ "\t" ++
            toString derived.length ++ "\t" ++ (if concrete then "true" else "false") ++
            "\t" ++ String.intercalate ";" (arities.map toString) ++ "\t" ++ byRuleStr derived
          { records := s.trace.reverse ++ inRecs ++ inpartRecs ++ satRecs ++ [solveRec],
            verdict := "SOLVED", message := "", env := s.env, drawn := s.su.drawn,
            sat := ps }

/-! ## 3. One replayed segment, under a policy -/

/-- `Replay.replay` with `solveSeedP`.  The two cross-checks -- the `scon` hashes and the
`equals` classes -- are about the INPUT and are untouched by the order. -/
def replayP (pol : Policy) (bud : Nat) (fl : Flags) (fuel : Nat) (g : Segment) :
    Except String ReplayOut :=
  if !g.errs.isEmpty then .error (String.intercalate "; " g.errs)
  else if g.cons.length != g.nCs then
    .error ("scon count " ++ toString g.cons.length ++ " != nCs " ++ toString g.nCs)
  else if (g.cons.filterMap CsItem.part?).length != g.nRows then
    .error ("rowConstraints " ++ toString g.nRows ++ " != part items " ++
            toString (g.cons.filterMap CsItem.part?).length)
  else
    let hashDiffs :=
      ((g.cons.zip g.recHash).filter (fun (c, h) => c.hshOf != h)).length
    let idx := withIndex g.cons
    let eqDiffs :=
      ((idx.zip g.recEqid).filter (fun ((c, i), e) =>
        let first := (idx.findSome? (fun (d, j) => if CsItem.eqv d c then some j else none)).getD i
        first != e)).length
    let out := solveSeedP pol bud fl g.site g.loc g.cons g.names g.sup fuel g.envFacts
    .ok { records := out.records, hashDiffs := hashDiffs, eqDiffs := eqDiffs,
          verdict := out.verdict, message := out.message }

end Rowpartition.Loop
