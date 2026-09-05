/-
# `incorporateAll` as a function

`Constraints.scala`: `incorporateAll` (1109), `learnPartitions` (1355), `simpleSubst` (1496),
`unify`/`replace`/`instantiate` (1520-1543), `makeEmpty` (1561), `subPartitions` (1588),
`makeConcrete` (1600), `destructiveSub` (1622).

The Scala is a tail-recursive function over two queues, a mutable `SubstEnv` and a mutable
`Supply`, and it can throw.  Here it is one `step : State -> StepResult`, with the
environment and the supply in the state and `Death` as a `died` result, plus `run` with an
explicit fuel.  Nothing is `partial`, nothing is `Classical`.

The trace is emitted where the Scala emits it: one `step` record per dequeue naming the
branch, and -- in the general branch only -- one `learn` record per derived partition, in
the ITERATION ORDER of the `Set` `learnPartitions` returns, tagged `seen` or `new` by
whether `proc` already contained it BEFORE the dequeued partition was returned to it.
-/
import Rowpartition.Loop.Rules

namespace Rowpartition.Loop

/-! ## 0. A `Map[Fields, TypeVar]` -/

/-- `Map` keyed on a label set: only `get` and `+` are used. -/
def flGet (m : List (SSet Lbl × Nat)) (k : SSet Lbl) : Option Nat :=
  (m.find? (fun p => p.1.eqv k)).map (·.2)

/-- `m + (k -> v)`. -/
def flPut (m : List (SSet Lbl × Nat)) (k : SSet Lbl) (v : Nat) : List (SSet Lbl × Nat) :=
  if m.any (fun p => p.1.eqv k) then m.map (fun p => if p.1.eqv k then (k, v) else p)
  else m ++ [(k, v)]

/-! ## 1. The state -/

/-- Everything `incorporateAll` reads or writes, plus what the trace needs. -/
structure State where
  incm : PQueue
  proc : PQueue
  env : Env
  /-- The id supply, `scalaparsers.Supply` (`Sup`). -/
  su : Sup
  /-- Trace records, most recent first. -/
  trace : List String
  flags : Flags
  names : Names
  /-- `RowTrace.site`, the first column of every record. -/
  site : String
  /-- The `Supply`'s starting `lo`, kept for the report line. -/
  su0 : Nat

/-- The result of one dequeue. -/
inductive StepResult where
  | continue (s : State)
  | done (s : State)
  | died (msg : String) (s : State)

/-- The result of a bounded run. -/
inductive RunResult where
  | solved (s : State)
  | rejected (msg : String) (s : State)
  | outOfFuel (s : State)

namespace State

def log (s : State) (rec : String) : State := { s with trace := rec :: s.trace }

end State

/-! ## 2. `unify` -/

/-- `Constraints.replace`, which returns a two-element `PQueue` when `v` and `u` both occur
on the right -- the de-duplication rule.  The queue orders them by their keys, and the caller
folds them into the incoming queue in THAT order. -/
def replace (v u : Nat) (p : LPart) : PQueue :=
  let f := fun w => if w == v then u else w
  let partp : LPart := ⟨f p.lhs, ⟨p.rhs.abstr.map f, p.rhs.conc⟩, p.inf⟩
  if p.rhs.abstr.contains v && p.rhs.abstr.contains u then
    PQueue.ofList [partp, ⟨u, RHS.empty, some .deDuplication⟩]
  else PQueue.ofList [partp]

/-- `Constraints.instantiate`.  `instantiateType` panics on a variable that is already bound;
the panic is a `Death` like any other. -/
def instantiate (ns : Names) (v u : Nat) (incm proc : PQueue) (env : Env) :
    Except String (PQueue × PQueue × Env) :=
  let (pps, nproc) := proc.partition (fun p => p.involves v)
  let (qps, nincm) := incm.partition (fun p => p.involves v)
  let nps := pps.concat qps
  if env.contains v then
    .error ("panic: reinstantiated type " ++ varStr ns v ++ " to " ++ varStr ns u ++
            " but it was already bound")
  else
    let env := env.instantiate v (.alias u)
    let q := nps.elems.foldl (fun nq p => nq.concatP (replace v u p).elems) nincm
    .ok (q, nproc, env)

/-- `Constraints.unify`. -/
def unifyVars (ns : Names) (v u : Nat) (incm proc : PQueue) (env : Env) :
    Except String (PQueue × PQueue × Env) :=
  if v == u then .ok (incm, proc, env) else instantiate ns v u incm proc env

/-! ## 3. `makeEmpty` -/

/-- `Constraints.makeEmpty`.  The `aux` cascade: an empty right-hand side contributes
nothing, an all-variable one forces every part empty, a right-hand side with labels is a
contradiction.  Every partition MENTIONING `v` is erased from both queues and the fact
`v := ConcreteRho(∅)` goes into the environment, which is why an emptied variable is
invisible to the concrete-row lookups.

The SKOLEM refusal (`Constraints.scala:1577`) sits exactly where the Scala puts it: after the
`nps` fold, so an "Incompatible instantiations" contradiction still wins, and before
`instantiateType`, so the reinstantiation panic comes after.  L1 listed it as not modelled --
a `json:` seed has no skolem -- and L2 found it: five `shouldfail/sk0*` modules force a
skolem row variable empty, and until this landed the model ran on past the compiler's
death. -/
def makeEmpty (ns : Names) (v : Nat) (incm proc : PQueue) (env : Env) :
    Except String (PQueue × PQueue × Env) := do
  let (pps, procd) := proc.partition (fun p => p.involves v)
  let (qps, incmg) := incm.partition (fun p => p.involves v)
  let start : Except String (SSet LPart) := .ok SSet.empty
  let nps ← (qps.concat pps).elems.foldl
    (fun (acc : Except String (SSet LPart)) (p : LPart) => do
      let s ← acc
      if p.lhs == v then
        if p.rhs.isEmpty then return s
        else if p.rhs.conc.isEmpty then
          -- The emptied variable is EXCLUDED, mirroring `Constraints.makeEmpty`'s `(abstr - v)`
          -- (fixed 2026-09-04, brief B1): propagating the empty fact to `v` ITSELF re-enqueued
          -- `v <- ()` and made a later dequeue call `makeEmpty v` a second time, which
          -- `instantiateType` refuses -- the panic of `L5-TERMINATION.md` §0 on a SATISFIABLE
          -- input.  `selfSubstitution` (`Loop/Rules.lean`) already writes `(abstr.excl v)`.
          return s.concat ((p.rhs.abstr.excl v).map (fun w => (⟨w, RHS.empty, some .partitionEmpty⟩ : LPart)))
        else .error ("Incompatible instantiations of '" ++ varStr ns v ++ "'")
      else return s.incl ⟨p.lhs, p.rhs.erase v, p.inf⟩)
    start
  if ns.isSkolem v then
    .error ("Cannot unify skolem variable with empty relation " ++ varStr ns v)
  else if env.contains v then
    .error ("panic: reinstantiated type " ++ varStr ns v ++ " to ConcreteRho(-,Set())" ++
            " but it was already bound")
  else
    let env := env.instantiate v .emptyRow
    .ok (incmg.concatP (trim nps procd).elems, procd, env)

/-! ## 4. `subPartitions`, `destructiveSub`, `makeConcrete` -/

/-- `Constraints.subPartitions`: everything the substitution `v := sub` derives, over `proc`
then over `incm` minus `v`'s own definitions. -/
def subPartitions (v : Nat) (sub : RHS) (proc incm : PQueue) :
    Except String (SSet LPart) :=
  let reduce := fun (acc : Except String (SSet LPart)) (r : LPart) => do
    let s ← acc
    if r.rhs.contains v then
      let (nrhs, es) ← rhsSubstitute r.rhs v sub
      let s := s.concat (es.map (fun w => (⟨w, RHS.empty, some .deDuplication⟩ : LPart)))
      return s.incl ⟨r.lhs, nrhs, r.inf⟩
    else return s
  (incm.filter (fun p => p.lhs != v)).elems.foldl reduce
    (proc.elems.foldl reduce (.ok SSet.empty))

/-- `Constraints.destructiveSub`, including the 2026-09-02 `keepDefs` repair: definitions of
`v` with two or more abstract parts survive the deletion, because nothing else names the row
they name. -/
def destructiveSub (v : Nat) (rhs : RHS) (incm proc : PQueue) :
    Except String (PQueue × PQueue) := do
  let (pps, procd) := proc.partition (fun p => p.lhs == v)
  let (qps, incmg) := incm.partition (fun p => p.lhs == v)
  let keep := !(pps.concat qps).isEmpty
  let rhsSet := (pps.concat qps).map (fun p => p.rhs)
  let srs ← rhsSet.elems.foldl
    (fun (acc : Except String (SSet LPart)) (r : RHS) => do
      let s ← acc
      return s.concat (← subPartitions v r procd incmg))
    (subPartitions v rhs procd incmg)
  let pred := fun (p : LPart) => p.lhs != v && !p.rhs.contains v
  let keepDefs := !(srs.isEmpty && keep)
  let nproc0 := if srs.isEmpty && keep then proc else procd.filter pred
  let nincm0 := if srs.isEmpty && keep then incm else incmg.filter pred
  let defs := fun (p : LPart) => p.rhs.abstr.size ≥ 2
  let nproc := if keepDefs then nproc0.concatNP (pps.filter defs).elems else nproc0
  let nincm := if keepDefs then nincm0.concatP (qps.filter defs).elems else nincm0
  .ok (nincm.concatP (trim srs nproc).elems, nproc)

/-- `Constraints.ensureSuperset`.  ABSTRACTED: the Scala renders a two-row `Document`; the
model reports the same failure with a flat message.  No tracked seed reaches it. -/
def ensureSuperset (sub sup : SSet Lbl) : Except String Unit :=
  if sub.subsetOf sup then .ok ()
  else .error ("Row types failed to unify: R1 = " ++ labelSetStr sub ++ " R2 = " ++
               labelSetStr sup)

/-- `Constraints.makeConcrete`. -/
def makeConcrete (v : Nat) (fs : SSet Lbl) (incm proc : PQueue) :
    Except String (PQueue × PQueue) := do
  let rhss := ((SSet.ofList proc.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs)
  let rhss := rhss.concat
    (((SSet.ofList incm.elems).filter (fun p => p.lhs == v)).map (fun p => p.rhs))
  let _ ← rhss.elems.foldl
    (fun (acc : Except String Unit) (r : RHS) => do
      let _ ← acc
      ensureSuperset r.conc fs)
    (.ok ())
  let can := rhss.elems.foldl
    (fun (s : SSet LPart) (r : RHS) => s.concat (cancellation v (RHS.ofConcr fs) r))
    SSet.empty
  let (nincm, nproc) ← destructiveSub v (RHS.ofConcr fs) incm proc
  .ok (nincm.concatP can.elems, nproc.insertNP ⟨v, RHS.ofConcr fs, none⟩)

/-! ## 5. `learnPartitions` -/

/-- The three reverse lookups `learnPartitions` builds, over `proc` then `incm` -- i.e. the
whole current system MINUS the dequeued premise, which `incorporateAll` returns to `proc`
only after this call. -/
structure Lookups where
  /-- `con ↦ w` for every `v <- (w, con)` with a LONE variable: `Resolved G v con`. -/
  resolvents : List (SSet Lbl × Nat)
  /-- `con ↦ u` for every BARE CONCRETE `u <- ((|con|))`. -/
  rows : List (SSet Lbl × Nat)
  /-- `v`'s own concrete row, if it has one. -/
  myRow : Option (SSet Lbl)

/-- Build them in the Scala's fold order: `proc` first, then `incm`, later writes winning. -/
def mkLookups (v : Nat) (incm proc : PQueue) : Lookups :=
  let step := fun (l : Lookups) (p : LPart) =>
    let l := match p.rhs.abstrSingle? with
      | some w => if p.lhs == v then { l with resolvents := flPut l.resolvents p.rhs.conc w }
                  else l
      | none => l
    if p.rhs.abstr.isEmpty then
      { l with rows := flPut l.rows p.rhs.conc p.lhs,
               myRow := if p.lhs == v then some p.rhs.conc else l.myRow }
    else l
  incm.elems.foldl step (proc.elems.foldl step ⟨[], [], none⟩)

/-- `findResolvent(s)(k)`: the current batch first (`collectFirst` in the set's iteration
order), then the map. -/
def findResolvent (v : Nat) (l : Lookups) (s : SSet LPart) (k : SSet Lbl) : Option Nat :=
  match s.elems.findSome? (fun p =>
      match p.rhs.abstrSingle? with
      | some w => if p.lhs == v && p.rhs.conc.eqv k then some w else none
      | none => none) with
  | some w => some w
  | none => flGet l.resolvents k

/-- `findConcRow(k)`: `v`'s own row `C` with `k ⊆ C`, and a carrier of `C \ k`. -/
def findConcRow (l : Lookups) (k : SSet Lbl) : Option Nat :=
  match l.myRow with
  | none => none
  | some c => if k.subsetOf c then flGet l.rows (c.removedAll k) else none

/-- `findEmptyRow(k)`: `findConcRow` pinned to `C = k`, with the retained `SubstEnv` fact as a
second source.  Only reachable with `-Dermine.emptyRow=true`, which ships OFF. -/
def findEmptyRow (env : Env) (l : Lookups) (k : SSet Lbl) : Option Nat :=
  match l.myRow with
  | none => none
  | some c =>
    if k.subsetOf c && (c.removedAll k).isEmpty then
      match flGet l.rows SSet.empty with
      | some z => some z
      | none => (env.binds.find? (fun p => p.2 == EnvVal.emptyRow)).map (·.1)
    else none

/-- `Constraints.learnPartitions`: `splitConcrete` as the fold's initial value, then one pass
over `proc` applying `resolution`+`cancellation` at the same left-hand side and
`commonSubexpression`+`substitution` at a different one. -/
def learnPartitions (fl : Flags) (ns : Names) (env : Env) (v : Nat) (rhs1 : RHS)
    (incm proc : PQueue) (su : Sup) : Except String (SSet LPart × Sup) :=
  if rhs1.abstr.contains v then do
    let s ← selfSubstitution ns v rhs1.abstr rhs1.conc
    return (s, su)
  else
    let l := mkLookups v incm proc
    let concRow := fun k => if fl.splitRow || fl.resRow then findConcRow l k else none
    let emptyRow := fun k => if fl.emptyRow then findEmptyRow env l k else none
    let (s0, su0) :=
      splitConcrete fl v rhs1.abstr rhs1.conc
        (fun r => findRHS3 incm proc SSet.empty r)
        (fun k => findResolvent v l SSet.empty k) concRow emptyRow su
    proc.elems.foldl
      (fun (acc : Except String (SSet LPart × Sup)) (p2 : LPart) => do
        let (s, su) ← acc
        let u := p2.lhs
        let rhs2 := p2.rhs
        if u == v then
          let (rps, su) := resolution fl v rhs1 rhs2 (fun k => findResolvent v l s k)
            concRow emptyRow su
          let cps := cancellation v rhs1 rhs2
          let dps :=
            if !fl.disjRule then (SSet.empty, su)
            else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
              if p3.lhs != v then
                let (d1, s1) := disjunction p3.rhs rhs1 rhs2 a.2
                let (d2, s2) := disjunction p3.rhs rhs2 rhs1 s1
                (a.1.concat (d1.concat d2), s2)
              else a) (SSet.empty, su)
          return ((s.concat rps).concat cps |>.concat dps.1, dps.2)
        else
          let (csps, su) := commonSubexpression fl v rhs1 u rhs2
            (fun r => findRHS3 incm proc s r) su
          let sps ← substitution v rhs1 u rhs2
          let dps :=
            if !fl.disjRule then (SSet.empty, su)
            else proc.elems.foldl (fun (a : SSet LPart × Sup) (p3 : LPart) =>
              if p3.lhs == u && !(rhs2.eqv p3.rhs) then
                let (d1, s1) := disjunction rhs1 rhs2 p3.rhs a.2
                let (d2, s2) := disjunction rhs1 p3.rhs rhs2 s1
                (a.1.concat (d1.concat d2), s2)
              else if p3.lhs == v && !(rhs1.eqv p3.rhs) then
                let (d1, s1) := disjunction rhs2 rhs1 p3.rhs a.2
                let (d2, s2) := disjunction rhs2 p3.rhs rhs1 s1
                (a.1.concat (d1.concat d2), s2)
              else a) (SSet.empty, su)
          return ((s.concat csps).concat sps |>.concat dps.1, dps.2))
      (.ok (s0, su0))

/-! ## 6. The dispatch -/

/-- `incorporateAll`'s body for ONE dequeue: `proc.findRHS` (common partition) first, then
the shape of the right-hand side -- empty, concrete, a lone variable, or the general case
that calls `learnPartitions`. -/
def step (s : State) : StepResult :=
  match s.incm.dequeue with
  | none => .done s
  | some (r, rest) =>
    let stepLog := fun (st : State) (branch : String) =>
      st.log ("step\t" ++ st.site ++ "\t" ++ branch ++ "\t" ++ r.toStr st.names ++
              "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size)
    let fin := fun (st : State) (res : Except String (PQueue × PQueue × Env)) =>
      match res with
      | .error m => .died m st
      | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }
    match s.proc.findRHS r.rhs with
    | some u =>
      let st := stepLog s ("common:" ++ toString u)
      fin st (unifyVars st.names r.lhs u rest s.proc st.env)
    | none =>
      if r.rhs.isEmpty then
        let st := stepLog s "empty"
        fin st (makeEmpty st.names r.lhs rest s.proc st.env)
      else if r.rhs.abstr.isEmpty then
        let st := stepLog s "concrete"
        match makeConcrete r.lhs r.rhs.conc rest s.proc with
        | .error m => .died m st
        | .ok (ni, np) => .continue { st with incm := ni, proc := np }
      else
        match r.rhs.single? with
        | some u =>
          let st := stepLog s ("unify:" ++ toString u)
          fin st (unifyVars st.names u r.lhs rest s.proc st.env)
        | none =>
          let st := stepLog s "learn"
          match learnPartitions st.flags st.names st.env r.lhs r.rhs rest s.proc st.su with
          | .error m => .died m st
          | .ok (learned, su) =>
            let st := learned.elems.foldl
              (fun (a : State) (p : LPart) =>
                a.log ("learn\t" ++ a.site ++ "\t" ++
                       (if s.proc.contains p then "seen" else "new") ++ "\t" ++
                       p.toStr a.names)) st
            .continue { st with
              incm := rest.concatP (trim learned s.proc).elems,
              proc := s.proc.insertNP r,
              su := su }

/-- Iterate `step` under an explicit fuel.  The fuel is a bound on the number of dequeues,
not a hidden `partial`: `outOfFuel` is a distinguishable answer. -/
def run : State → Nat → RunResult
  | s, 0 => .outOfFuel s
  | s, n + 1 =>
    match step s with
    | .done s' => .solved s'
    | .died m s' => .rejected m s'
    | .continue s' => run s' n

end Rowpartition.Loop
