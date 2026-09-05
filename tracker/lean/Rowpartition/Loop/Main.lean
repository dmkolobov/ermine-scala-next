/-
# `looptrace`: the model as an executable

    lake exe looptrace <seed.json> <base> [fuel] [--verdict] [--site=<s>] [--flags=...]
    lake exe looptrace --replay <trace.tsv> [--flags=...] [--fuel=N] [--from=I] [--to=J]

Prints the `-Dermine.rowTrace` TSV of ONE `Subst.solve` on the seed at that id base -- the
`step` and `learn` records of the loop, then the `in`, `inpart` and `sat` population records
and the `solve` line -- so that it can be diffed against the compiler's own trace with
`tracker/tools/looptrace-diff.py`.

`--verdict` prints `SOLVED` / `REJECTED <msg>` / `FUEL` and the loop's bindings in the repro
harness's `v0 := ...` shape instead.

`--mints` (L5 round 5) prints the per-KEY `splitConcrete` mint tally of the same solve
instead of the trace: a `mints` summary line with the verdict, the dequeue count, the ids
drawn, the largest number of mints at ONE key and the number of keys minted at more than
once, then one `key` line per key and one `mint` line per minting step.  `Loop/Pump.lean`
computes it from `splitConcrete`'s own supply, so the instrument is the rule itself; the
`cmax`/`ckey`/`carrier` columns are the wider count -- every fresh CARRIER installed at the
dequeued left-hand side, which is `resolution`'s mint as well as `splitConcrete`'s, and is
the round-4 hunt's detector.

`--flags=a,b,c` turns individual `GenRules` switches on or off: `all`, `cut`, `nongen`,
`disj`, `nolabel`, `lateLabel`, `noresguard`, `nosplitkey`, `nosplitrow`, `noresrow`,
`emptyrow`.  With no `--flags` the SHIPPED defaults are used.

`--replay` (stage L2) reads a compiler `-Dermine.rowTrace` file, reconstructs EVERY solve in
it from its `sin`/`slbl`/`svar`/`scon` records, runs the model on each, and prints the
model's records for each -- ONE process for a whole corpus file, not one per solve.  Each
segment is announced by a `#seg <i> <site> <loc>` line so `tracker/tools/looptrace-diff.py`
can pair the model's segments with the compiler's, and a segment that cannot be replayed
gets `#skip <i> <reason>` instead of records.  The trailing `#summary` line carries the
counts.  Segments are numbered from 0 in file order; `--from`/`--to` restrict the range.
-/
import Rowpartition.Loop.Replay
import Rowpartition.Loop.Pump

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

/-- Read the `--flags=` option. -/
def flagsOf (opts : List String) : Flags :=
  match (opts.find? (fun a => a.startsWith "--flags=")).map (fun a => (a.drop 8).toString) with
  | none => ({} : Flags)
  | some s => (s.splitOn ",").foldl applyFlag ({} : Flags)

/-- Read a `--key=<nat>` option. -/
def natOpt (opts : List String) (key : String) (dflt : Nat) : Nat :=
  match (opts.find? (fun a => a.startsWith key)).bind (fun a => (a.drop key.length).toNat?) with
  | some n => n
  | none => dflt

/-- `--replay`: every solve of a compiler trace, through the model.

STREAMING, one segment at a time: a corpus trace can be hundreds of megabytes (a diverging
`incomplete/` module writes about 8 MB/s for as long as it is left running), and reading it
whole would hold every line of it live.  The outer loop is a bounded `for` rather than a
recursion, because nothing under `Loop/` may be `partial`; the bound is a line count no trace
approaches, and running into it is reported. -/
def replayMain (path : String) (opts : List String) : IO UInt32 := do
  let fl := flagsOf opts
  let fuel := natOpt opts "--fuel=" 2000000
  let lo := natOpt opts "--from=" 0
  let hi := natOpt opts "--to=" 1000000000
  let maxLines := natOpt opts "--maxlines=" 2000000000
  let h ← IO.FS.Handle.mk path IO.FS.Mode.read
  let mut cur : Option Segment := none
  let mut i : Nat := 0            -- index of the segment in `cur`
  let mut nSeg := 0
  let mut nRun := 0
  let mut nSkip := 0
  let mut nHash := 0
  let mut nEq := 0
  let mut nOther := 0
  let mut nRej := 0
  let mut nFuel := 0
  let mut eof := false
  let mut hitBound := true
  -- Replay the segment just completed.
  let flush : Nat → Segment → IO (Nat × Nat × Nat × Nat × Nat × Nat) := fun j g => do
    if !(lo ≤ j && j ≤ hi) then
      return (0, 0, 0, 0, 0, 0)
    IO.println s!"#seg\t{j}\t{g.site}\t{g.loc}"
    match replay fl fuel g with
    | .error m =>
      IO.println s!"#skip\t{j}\t{m}"
      return (0, 1, 0, 0, 0, 0)
    | .ok out =>
      let mut hd := 0
      let mut ed := 0
      let mut rj := 0
      let mut fu := 0
      if out.hashDiffs > 0 then
        hd := 1
        IO.println s!"#hashdiff\t{j}\t{out.hashDiffs}"
      if out.eqDiffs > 0 then
        ed := 1
        IO.println s!"#eqdiff\t{j}\t{out.eqDiffs}"
      if out.verdict == "REJECTED" then
        rj := 1
      if out.verdict == "FUEL" then
        fu := 1
      for r in out.records do IO.println r
      if out.verdict != "SOLVED" then IO.println s!"#{out.verdict}\t{j}\t{out.message}"
      return (1, 0, hd, ed, rj, fu)
  for _ in [0:maxLines] do
    let raw ← h.getLine
    if raw.isEmpty then
      eof := true
      hitBound := false
      break
    -- `getLine` keeps the terminator; strip it without depending on `String.trimRight`,
    -- whose result type moved in recent Lean releases.
    let ln := String.ofList (raw.toList.filter (fun c => c != '\n' && c != '\r'))
    let f := ln.splitOn "\t"
    match f.head? with
    | some "sin" =>
      match cur with
      | some g =>
        let (a, b, c, d, e, k) ← flush i g.finish
        nRun := nRun + a
        nSkip := nSkip + b
        nHash := nHash + c
        nEq := nEq + d
        nRej := nRej + e
        nFuel := nFuel + k
        if !g.allParts then
          nOther := nOther + 1
        i := i + 1
      | none => pure ()
      cur := some (startSegment f)
      nSeg := nSeg + 1
    | some "slbl" | some "svar" | some "scon" =>
      match cur with
      | some g => cur := some (addRecord g f)
      | none => pure ()
    | _ => pure ()
  match cur with
  | some g =>
    let (a, b, c, d, e, k) ← flush i g.finish
    nRun := nRun + a
    nSkip := nSkip + b
    nHash := nHash + c
    nEq := nEq + d
    nRej := nRej + e
    nFuel := nFuel + k
    if !g.allParts then
      nOther := nOther + 1
  | none => pure ()
  if hitBound && !eof then IO.eprintln s!"# --maxlines={maxLines} reached before EOF"
  IO.println s!"#summary\tsegments={nSeg}\treplayed={nRun}\tskipped={nSkip}\thashdiff={nHash}\teqdiff={nEq}\tnonpart={nOther}\trejected={nRej}\tfuel={nFuel}"
  return (if nSkip == 0 && nHash == 0 && nEq == 0 then 0 else 1)

/-- The entry point. -/
def mainImpl (args : List String) : IO UInt32 := do
  let positional := args.filter (fun a => !a.startsWith "--")
  let opts := args.filter (fun a => a.startsWith "--")
  if opts.contains "--replay" then
    match positional with
    | path :: _ => return (← replayMain path opts)
    | _ => IO.eprintln "usage: looptrace --replay <trace.tsv>"; return 2
  match positional with
  | path :: baseS :: rest => do
    let base := (baseS.toNat?).getD 0
    let fuel := (rest.head?.bind (·.toNat?)).getD 100000
    let fl := flagsOf opts
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
        let out := solveSeed fl site "-" parts ns (Sup.ofSeed ns.supplyLo) fuel
        if opts.contains "--mints" then
          let (parts', su1) := (parts, Sup.ofSeed ns.supplyLo)
          match buildQueue parts' su1 with
          | .error m => IO.println s!"mints\tREJECTED\tsteps=0\tdrawn=0\tmax=0\tremint=0\t{m}"
          | .ok (q, su2) =>
            let st0 : State :=
              { incm := q, proc := PQueue.empty, env := {}, su := su2, trace := [], flags := fl,
                names := ns, site := site, su0 := (Sup.ofSeed ns.supplyLo).lo }
            let rep := pumpRun fuel st0 {}
            IO.println s!"mints\t{rep.verdict}\tsteps={rep.steps}\tdrawn={rep.drawn}\tmax={rep.maxAtKey}\tremint={rep.remintKeys}\tcmax={rep.maxAtCKey}\tcremint={rep.remintCKeys}"
            for (k, n) in rep.tally do
              IO.println s!"key\t{k.1}\t{String.intercalate "," (k.2.toList.map (fun l => toString l.n))}\t{n}"
            for (k, n) in rep.ctally do
              IO.println s!"ckey\t{k.1}\t{String.intercalate "," (k.2.toList.map (fun l => toString l.n))}\t{n}"
            for (i, v, ls) in rep.mints do
              IO.println s!"mint\t{i}\t{v}\t{String.intercalate "," (ls.map toString)}"
            for (i, v, ls) in rep.carriers do
              IO.println s!"carrier\t{i}\t{v}\t{String.intercalate "," (ls.map toString)}"
            for (i, v, ls, ws) in rep.carrAt do
              IO.println s!"carr\t{i}\t{v}\t{String.intercalate "," (ls.map toString)}\t{String.intercalate "," (ws.map toString)}"
            for (i, w) in rep.binds do
              IO.println s!"bind\t{i}\t{w}"
            IO.println s!"v0\t{String.intercalate "," ((stateVars st0).toList.map toString)}"
        else if opts.contains "--verdict" then
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
    IO.eprintln ("usage: looptrace <seed.json> <base> [fuel] [--verdict] [--site=S] [--flags=..]\n" ++
                 "       looptrace --replay <trace.tsv> [--flags=..] [--fuel=N] [--from=I] [--to=J]")
    return 2

end Rowpartition.Loop

def main (args : List String) : IO UInt32 := Rowpartition.Loop.mainImpl args
