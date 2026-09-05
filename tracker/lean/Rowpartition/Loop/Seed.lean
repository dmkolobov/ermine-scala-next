/-
# Seeds, and the whole of `Subst.solve` that surrounds the loop

`tracker/repro/satterm/SatTermRepro.scala`'s `seedFromJson` / `system`, and the part of
`Subst.solve` that is not `q.expand`: the early per-label refutation, and the population
records it writes once the loop has returned.

A seed is `{"name": .., "rho": {..}, "cons": [[lhs, [vars], [labels]], ..]}`.  The harness
maps variable `i` to `base + (its position in the ascending distinct list)`, names it `v<i>`,
maps label `n` to `Global("Repro", "l" ++ n)`, and starts the `Supply` at
`base + #vars`.
-/
import Rowpartition.Loop.Json
import Lean.Data.Json

namespace Rowpartition.Loop

open Lean (Json)

/-- One seed constraint: left-hand variable, right-hand variables, right-hand labels. -/
structure SeedCon where
  lhs : Nat
  vars : List Nat
  labels : List Nat
deriving Repr

/-- A parsed seed. -/
structure Seed where
  name : String
  cons : List SeedCon
  rhoKeys : List Nat
deriving Repr

namespace Seed

private def asNat (j : Json) : Except String Nat := do
  let n ← j.getNat?
  return n

private def asNats (j : Json) : Except String (List Nat) := do
  let a ← j.getArr?
  a.toList.mapM asNat

/-- Parse the `rowclosure.py` seed format. -/
def ofJson (j : Json) : Except String Seed := do
  let name := (j.getObjValAs? String "name").toOption.getD "?"
  let consArr ← (← j.getObjVal? "cons").getArr?
  let cons ← consArr.toList.mapM (fun c => do
    let a ← c.getArr?
    match a.toList with
    | [l, vs, ks] => return { lhs := ← asNat l, vars := ← asNats vs, labels := ← asNats ks }
    | _ => .error "bad constraint")
  let rhoKeys : List Nat :=
    match j.getObjVal? "rho" with
    | .ok (.obj m) => m.toArray.toList.filterMap (fun kv => kv.1.toNat?)
    | _ => []
  return { name := name, cons := cons, rhoKeys := rhoKeys }

end Seed

/-- The variables a seed mentions, ascending and distinct: the harness's
`(cons.flatMap { case (l, vs, _) => l :: vs } ++ rho.map(_._1)).distinct.sorted`. -/
def seedVars (s : Seed) : List Nat :=
  let raw := s.cons.flatMap (fun c => c.lhs :: c.vars) ++ s.rhoKeys
  sortNats (raw.foldl (fun acc v => if acc.contains v then acc else acc ++ [v]) [])

/-- The system a seed makes at an id base: the input `Part` list, the display names, and the
first id the `Supply` will draw.  A seed's constraint list is all `Part`s, so every item is a
`CsItem.part`; the corpus replay is where `other` items appear. -/
def seedSystem (s : Seed) (base : Nat) : List CsItem × Names :=
  let vs := seedVars s
  let idOf := fun (k : Nat) => base + (vs.idxOf k)
  let named := (withIndex vs).map (fun (k, i) => (base + i, "v" ++ toString k))
  let parts := s.cons.map (fun c =>
    CsItem.part
    { lhs := ITerm.varT (idOf c.lhs),
      rhs := c.vars.map (fun v => ITerm.varT (idOf v)) ++
        (if c.labels.isEmpty then []
         else [ITerm.concRho (SSet.ofList (c.labels.map Lbl.repro))]) : IPart })
  (parts, { named := named, supplyLo := base + vs.length })

/-! ## The driver -/

/-- What one `solve` produces. -/
structure SolveOut where
  /-- Every TSV record, in the order `RowTrace` writes them. -/
  records : List String
  /-- `SOLVED`, `REJECTED` or `FUEL`. -/
  verdict : String
  /-- The message of a `Death`. -/
  message : String
  /-- The final `SubstEnv`. -/
  env : Env
  /-- Ids drawn from the `Supply`. -/
  drawn : Nat
  /-- The saturated partition set. -/
  sat : List LPart

/-- `derived.groupBy(_.inf.get.toString)` rendered as `byRule`. -/
def byRuleStr (ps : List LPart) : String :=
  let names := ps.filterMap (fun p => p.inf.map (·.toStr))
  let uniq := names.foldl (fun acc n => if acc.contains n then acc else acc ++ [n]) []
  let entries := uniq.map (fun n => n ++ ":" ++ toString (names.filter (· == n)).length)
  if entries.isEmpty then "-" else String.intercalate "," (sortStrings entries)

/-- `Subst.solve` with `-Dermine.rowTrace` on, minus `reduce`.  `loc` is the third column of
every record: `-` for a seed, the solve's own location when replaying a compiler trace.

The `in` records are `cs.flatMap(_.rowConstraints)`, which for a list of `Part`s is the list
itself -- so they are generated from the `part` items, in order.  An `other` item whose
`rowConstraints` is nonempty would break that, so the replay CHECKS it: the trace's `sin`
record carries `nRows = cs.flatMap(_.rowConstraints).length` and `Loop/Replay.lean`'s
`replay` refuses a segment where that is not the number of `part` items. -/
def solveSeed (fl : Flags) (site : String) (loc : String) (cs : List CsItem) (ns : Names)
    (su0 : Sup) (fuel : Nat) : SolveOut :=
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
      let st0 : State :=
        { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := fl,
          names := ns, site := site, su0 := su0.lo }
      match run st0 fuel with
      | .rejected m s =>
        { records := s.trace.reverse, verdict := "REJECTED", message := m, env := s.env,
          drawn := s.su.drawn, sat := [] }
      | .outOfFuel s =>
        { records := s.trace.reverse, verdict := "FUEL", message := "", env := s.env,
          drawn := s.su.drawn, sat := s.proc.elems }
      | .solved s =>
        let ps := s.proc.elems
        let late :=
          if fl.labelCheck && !fl.labelCheckEarly then labelClash ns q.elems else none
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

/-- The harness's `v0 := ...` line, over the LOOP's environment.  `Subst.reduce`, which runs
after `q.expand` and pins more variables, is outside this model, so a variable the harness
reports as a concrete row can be `unbound` here. -/
def bindingsStr (ns : Names) (env : Env) : String :=
  String.intercalate "; " (ns.named.map (fun (v, n) =>
    n ++ " := " ++
    (match env.lookup v with
     | none => "unbound"
     | some .emptyRow => "ConcreteRho(-,Set())"
     | some (.alias u) => varStr ns u)))

end Rowpartition.Loop
