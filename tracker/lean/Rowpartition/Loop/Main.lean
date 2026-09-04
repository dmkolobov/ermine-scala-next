/-
# `looptrace`: the model as an executable

    lake exe looptrace <seed.json> <base> [fuel] [--verdict] [--site=<s>] [--flags=...]

Prints the `-Dermine.rowTrace` TSV of ONE `Subst.solve` on the seed at that id base -- the
`step` and `learn` records of the loop, then the `in`, `inpart` and `sat` population records
and the `solve` line -- so that it can be diffed against the compiler's own trace with
`tracker/tools/looptrace-diff.py`.

`--verdict` prints `SOLVED` / `REJECTED <msg>` / `FUEL` and the loop's bindings in the repro
harness's `v0 := ...` shape instead.

`--flags=a,b,c` turns individual `GenRules` switches on or off: `all`, `cut`, `nongen`,
`disj`, `nolabel`, `lateLabel`, `noresguard`, `nosplitkey`, `nosplitrow`, `noresrow`,
`emptyrow`.  With no `--flags` the SHIPPED defaults are used.
-/
import Rowpartition.Loop.Seed

namespace Rowpartition.Loop

/-- Apply one `--flags` token. -/
def applyFlag (f : Flags) : String → Flags
  | "all" => { f with cseMints := true, splitMints := true, resolves := true }
  | "cut" => { f with cseMints := false, splitMints := true, resolves := true }
  | "nongen" => { f with cseMints := false, splitMints := false, resolves := false }
  | "disj" => { f with disjRule := true }
  | "nolabel" => { f with labelCheck := false }
  | "lateLabel" => { f with labelCheckEarly := false }
  | "noresguard" => { f with resGuard := false }
  | "nosplitkey" => { f with splitKey := false }
  | "nosplitrow" => { f with splitRow := false }
  | "noresrow" => { f with resRow := false }
  | "emptyrow" => { f with emptyRow := true }
  | _ => f

/-- The entry point. -/
def mainImpl (args : List String) : IO UInt32 := do
  let positional := args.filter (fun a => !a.startsWith "--")
  let opts := args.filter (fun a => a.startsWith "--")
  match positional with
  | path :: baseS :: rest => do
    let base := (baseS.toNat?).getD 0
    let fuel := (rest.head?.bind (·.toNat?)).getD 100000
    let flagArg := (opts.find? (fun a => a.startsWith "--flags=")).map (fun a => (a.drop 8).toString)
    let fl := match flagArg with
      | none => ({} : Flags)
      | some s => (s.splitOn ",").foldl applyFlag ({} : Flags)
    let site := match (opts.find? (fun a => a.startsWith "--site=")).map (fun a => (a.drop 7).toString) with
      | some s => s
      | none => "json:" ++ path ++ "@" ++ toString base
    let txt ← IO.FS.readFile path
    match Lean.Json.parse txt with
    | .error e => IO.eprintln s!"bad json: {e}"; return 2
    | .ok j =>
      match Seed.ofJson j with
      | .error e => IO.eprintln s!"bad seed: {e}"; return 2
      | .ok seed =>
        let (parts, ns) := seedSystem seed base
        let out := solveSeed fl site parts ns fuel
        if opts.contains "--verdict" then
          IO.println s!"genRules={fl.toStr}  base={base}  supply={ns.supplyLo}"
          match out.verdict with
          | "SOLVED" =>
            IO.println s!"SOLVED   {bindingsStr ns out.env}  [bound={out.env.size} drawn={out.drawn} sat={out.sat.length}]"
          | "REJECTED" => IO.println s!"REJECTED {out.message}  [drawn={out.drawn}]"
          | _ => IO.println s!"FUEL     [drawn={out.drawn}]"
        else
          for r in out.records do IO.println r
          if out.verdict != "SOLVED" then
            IO.eprintln s!"# {out.verdict} {out.message}"
        return 0
  | _ =>
    IO.eprintln "usage: looptrace <seed.json> <base> [fuel] [--verdict] [--site=S] [--flags=..]"
    return 2

end Rowpartition.Loop

def main (args : List String) : IO UInt32 := Rowpartition.Loop.mainImpl args
