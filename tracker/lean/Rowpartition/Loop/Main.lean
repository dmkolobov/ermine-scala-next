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

`--depth` (L5 round 8) prints instead the MINT CHAIN of the same solve: one `depth` summary
line with the verdict, the dequeue count, the ids drawn, the largest DEPTH of a drawn id, the
`splitConcrete` and `resolution` draw counts, THREE key counters -- `maxremint` at the guard
key and `maxcremint` at the carrier key, which are round 5's, and `maxdkey`, the largest number
of DRAWS at one dequeue key `(dequeued lhs, dequeued concrete part)`, which is the one
`Depth.Chain` needs because `resolution` takes its `fresh` before its guards and a REUSE bumps
neither of the other two -- then the input's variable / partition / label counts and the depth
histogram; then one `dm` line per DRAW with its rule, its site, the site's depth, the id, the
id's depth and its index at the dequeue key.  `Loop/Depth.lean` computes it: an id present at
the FIRST dequeue is at depth 0, an id drawn at a step whose dequeued premise has left-hand
side `v` is at depth `depth v + 1`.  `maxdepth` and `maxdkey` are the `D` and the `R` of
`Depth.terminates_of_chainRun`.

`--cycle` (L5 round 6) prints instead the STATE-CYCLE search of the same solve: one `cycle`
line with the verdict, the dequeue count, the number of DISTINCT canonical states visited,
and the first canonical and the first exact repeat, if any.  `Loop/Cycle.lean` canonicalises
a state by renaming every minted id (`id >= su0`) to its index in the state's own
first-occurrence traversal; an exact repeat is `not_Terminates` by `not_terminates_of_cycle`,
a canonical repeat is a candidate that has to be replayed.

`--flags=a,b,c` turns individual `GenRules` switches on or off: `all`, `cut`, `nongen`,
`disj`, `nolabel`, `lateLabel`, `noresguard`, `nosplitkey`, `nosplitrow`, `noresrow`,
`emptyrow`, and S2's `rowsound` / `rsbare` / `rssat` / `rsdecide` / `rsbudget=<n>` /
`rssolvebudget=<n>` (with
`norsbare` / `norssat` / `norsdecide` to switch one back off).  With no `--flags` the SHIPPED
defaults are used, and every S2 flag is OFF in them.

`--policy=<name>` (D1 round A2) prints instead ONE `pol` line per solve -- the verdict, the
dequeues and the ids drawn -- with the loop's `pop` under that dequeue order:
`shipped` (the default, and `Q.pop` itself), `concfirst`, `smallrhs`, `fifo` or `canon`
(`Loop/Policy.lean`).  `--budget=<n>` caps the fresh ids ONE SOLVE may draw and makes
exhaustion a REJECTION with a diagnostic (`Loop/Budget.lean`); `0`, the default, is off.
Both work on a `json:` seed and under `--replay`.  A budget asked for at the SHIPPED order is
IGNORED, here and in the compiler alike (`Policy.effBudget`, D1B review): under that order a
solve's draw count depends on the id base, so a budget alone would reject a well-typed program
at some bases and accept it at others.

`--trace` forces the RECORD path even when `--policy=`/`--budget=` are given, so that the L2
corpus differential can be run UNDER a policy or a budget (Part B's gate): without it those two
options select the `pol` census instead.  With no `--policy=` the policy is taken from the
trace's own `sin` record, so a compiler trace written with `-Dermine.dequeuePolicy` on replays
under that policy without being told.

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
import Rowpartition.Loop.Cycle
import Rowpartition.Loop.Depth
import Rowpartition.Loop.Policy
import Rowpartition.Loop.PolicyReplay

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
  -- S2 (`tracker/loopmodel/S2-DESIGN.md`), all DEFAULT OFF: `rowsound` is the master, and
  -- the three layers are separately switchable so each can be measured alone.
  | "rowsound" => { f with rowSoundBare := true, rowSoundSat := true, rowSoundDecide := true }
  | "rsbare" => { f with rowSoundBare := true }
  | "rssat" => { f with rowSoundSat := true }
  | "rsdecide" => { f with rowSoundDecide := true }
  | "norsbare" => { f with rowSoundBare := false }
  | "norssat" => { f with rowSoundSat := false }
  | "norsdecide" => { f with rowSoundDecide := false }
  | t =>
    -- `rsbudget=<n>`: layer (iii)'s decision-node budget per label.
    if t.startsWith "rsbudget=" then
      match (t.drop 9).toNat? with
      | some n => { f with rowSoundBudget := n }
      | none => f
    else if t.startsWith "rssolvebudget=" then
      match (t.drop 14).toNat? with
      | some n => { f with rowSoundSolveBudget := n }
      | none => f
    else f

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

/-- L5 round 7 (round-6 review W-6g): ONE segment through the cycle detector rather than
through the record printer, so `--cycle` runs over corpus replays and not only over `json:`
seeds.  The state is the one `Seed.solve` and `Replay.replay` build -- `buildQueue` of the
segment's constraint list, `proc` and `env` empty -- so the report is about exactly the solve
the compiler performed.  The early label check is deliberately NOT applied: a solve the
checker rejects before the loop starts still has a loop to search, and `labelCheckEarly`
would hide it. -/
def replayCycleOne (fl : Flags) (fuel : Nat) (g : Segment) : Except String CycleRep :=
  if !g.errs.isEmpty then .error (String.intercalate "; " g.errs)
  else if g.cons.length != g.nCs then
    .error ("scon count " ++ toString g.cons.length ++ " != nCs " ++ toString g.nCs)
  else
    match buildQueue g.cons g.sup with
    | .error m => .ok { verdict := "BUILD", witness := m }
    | .ok (q, su1) =>
      let st0 : State :=
        { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := fl,
          names := g.names, site := g.site, su0 := g.sup.lo }
      .ok (cycleRun fuel st0 [] [] {})

/-- L5 round 8: ONE segment through the MINT CHAIN instrument (`Loop/Depth.lean`), so
`--depth` runs over corpus replays.  The state is the one `Replay.replay` builds, so the
depths are those of the solve the compiler performed. -/
def replayDepthOne (fl : Flags) (fuel : Nat) (g : Segment) : Except String DepthRep :=
  if !g.errs.isEmpty then .error (String.intercalate "; " g.errs)
  else if g.cons.length != g.nCs then
    .error ("scon count " ++ toString g.cons.length ++ " != nCs " ++ toString g.nCs)
  else
    match buildQueue g.cons g.sup with
    | .error _ => .ok { verdict := "BUILD" }
    | .ok (q, su1) =>
      let st0 : State :=
        { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := fl,
          names := g.names, site := g.site, su0 := g.sup.lo }
      .ok (depthRun fuel st0 {})

/-- D1 (A2): ONE segment through the POLICY census (`Loop/Policy.lean`), so `--policy=` runs
over corpus replays.  The state is the one `Replay.replay` builds, so the counts are those of
the solve the compiler performed; the early label check is deliberately NOT applied, exactly as
`replayCycleOne` and `replayDepthOne` do not apply it, so that the four orders are compared on
the same loop and not on the checker in front of it. -/
def replayPolicyOne (fl : Flags) (pol : Policy) (bud : Nat) (fuel : Nat) (g : Segment) :
    Except String PolRep :=
  if !g.errs.isEmpty then .error (String.intercalate "; " g.errs)
  else if g.cons.length != g.nCs then
    .error ("scon count " ++ toString g.cons.length ++ " != nCs " ++ toString g.nCs)
  else
    match buildQueue g.cons g.sup with
    | .error _ => .ok { verdict := "BUILD" }
    | .ok (q, su1) =>
      let st0 : State :=
        { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := fl,
          names := g.names, site := g.site, su0 := g.sup.lo }
      .ok (polCensus pol bud fuel st0)

/-- The `pol` summary line of one solve, without the leading index/site columns. -/
def polCols (rep : PolRep) : String :=
  s!"steps={rep.steps}\tdrawn={rep.drawn}\tdrawn0={rep.drawn0}"

/-- The `--policy=` option; absent means the shipped order. -/
def policyOf (opts : List String) : Policy :=
  match (opts.find? (fun a => a.startsWith "--policy=")).bind
      (fun a => Policy.ofString ((a.drop 9).toString)) with
  | some p => p
  | none => .shipped

/-- The `depth` summary line of one solve, without the leading index/site columns. -/
def depthCols (rep : DepthRep) : String :=
  s!"steps={rep.steps}\tdrawn={rep.drawn}\tdrawn0={rep.drawn0}" ++
  s!"\tmaxdepth={rep.maxDepth}\tnsplit={rep.nSplit}\tnres={rep.nRes}" ++
  s!"\tmaxremint={rep.maxRemint}\tmaxcremint={rep.maxCRemint}\tmaxdkey={rep.maxDKey}" ++
  s!"\tnvars={rep.nVars}\tnparts={rep.nParts}\tnlbl={rep.nLbl}" ++
  s!"\thist={String.intercalate "," (rep.hist.map (fun p => s!"{p.1}:{p.2}"))}"

/-- L5 round 7: ONE segment through round 5's PER-KEY MINT instrument (`Loop/Pump.lean`),
so `--mints` runs over corpus replays too.  `max` is the largest number of `splitConcrete`
mints at ONE key `(lhs, concrete part)` and `remint` the number of keys minted at more than
once -- which is exactly the shape the round-5 pump needs. -/
def replayMintOne (fl : Flags) (fuel : Nat) (g : Segment) : Except String PumpRep :=
  if !g.errs.isEmpty then .error (String.intercalate "; " g.errs)
  else if g.cons.length != g.nCs then
    .error ("scon count " ++ toString g.cons.length ++ " != nCs " ++ toString g.nCs)
  else
    match buildQueue g.cons g.sup with
    | .error m => .ok { verdict := "BUILD" }
    | .ok (q, su1) =>
      let st0 : State :=
        { incm := q, proc := PQueue.empty, env := {}, su := su1, trace := [], flags := fl,
          names := g.names, site := g.site, su0 := g.sup.lo }
      .ok (pumpRun fuel st0 {})

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
  let cycMode := opts.contains "--cycle"
  let mintMode := opts.contains "--mints"
  let depMode := opts.contains "--depth"
  let traceMode := opts.contains "--trace"
  let polMode := !traceMode &&
    ((opts.any (fun a => a.startsWith "--policy=")) || (opts.any (fun a => a.startsWith "--budget=")))
  let polOpt : Option Policy :=
    (opts.find? (fun a => a.startsWith "--policy=")).bind
      (fun a => Policy.ofString ((a.drop 9).toString))
  let pol := polOpt.getD .shipped
  let budOpt : Option Nat :=
    (opts.find? (fun a => a.startsWith "--budget=")).bind (fun a => (a.drop 9).toNat?)
  let bud := budOpt.getD 0
  let flush : Nat → Segment → IO (Nat × Nat × Nat × Nat × Nat × Nat) := fun j g => do
    if !(lo ≤ j && j ≤ hi) then
      return (0, 0, 0, 0, 0, 0)
    if polMode then
      match replayPolicyOne fl pol bud fuel g with
      | .error m =>
        IO.println s!"#skip\t{j}\t{m}"
        return (0, 1, 0, 0, 0, 0)
      | .ok rep =>
        IO.println (s!"pol\t{j}\t{g.site}\t{g.loc}\t{rep.verdict}\t" ++ polCols rep)
        return (1, 0, 0, 0, (if rep.verdict == "REJECTED" then 1 else 0),
          (if rep.verdict == "FUEL" then 1 else 0))
    if depMode then
      match replayDepthOne fl fuel g with
      | .error m =>
        IO.println s!"#skip\t{j}\t{m}"
        return (0, 1, 0, 0, 0, 0)
      | .ok rep =>
        IO.println (s!"depth\t{j}\t{g.site}\t{g.loc}\t{rep.verdict}\t" ++ depthCols rep)
        if rep.drawn > rep.drawn0 then
          for (i, rl, v, sd, z, dz, ri) in rep.chain do
            IO.println s!"dm\t{j}\t{i}\t{rl}\t{v}\t{sd}\t{z}\t{dz}\t{ri}"
        return (1, 0, 0, 0, (if rep.verdict == "REJECTED" then 1 else 0),
          (if rep.verdict == "FUEL" then 1 else 0))
    if mintMode then
      match replayMintOne fl fuel g with
      | .error m =>
        IO.println s!"#skip\t{j}\t{m}"
        return (0, 1, 0, 0, 0, 0)
      | .ok rep =>
        IO.println (s!"mints\t{j}\t{g.site}\t{g.loc}\t{rep.verdict}\tsteps={rep.steps}" ++
          s!"\tdrawn={rep.drawn}\tmax={rep.maxAtKey}\tremint={rep.remintKeys}" ++
          s!"\tcmax={rep.maxAtCKey}\tcremint={rep.remintCKeys}\tkeys={rep.tally.length}")
        return (1, 0, 0, 0, (if rep.verdict == "REJECTED" then 1 else 0),
          (if rep.verdict == "FUEL" then 1 else 0))
    if cycMode then
      -- One `cycle` line per solve; nothing else is printed.  `parts` is the number of
      -- input partitions the model built, `grew` whether a minted id ever entered a
      -- partition, `conc` how many dequeues took the `concrete` branch.
      match replayCycleOne fl fuel g with
      | .error m =>
        IO.println s!"#skip\t{j}\t{m}"
        return (0, 1, 0, 0, 0, 0)
      | .ok rep =>
        let sc := match rep.canonHit with
          | none => "-"
          | some (i, k) => s!"{i},{k}"
        let sr := match rep.rawHit with
          | none => "-"
          | some (i, k) => s!"{i},{k}"
        -- `BUILD` means `PQueue.build` itself failed, so `cycleRun` never ran and every
        -- field below is the structure's DEFAULT.  `grew=false` would then read as
        -- "vocabulary fixed" to a census that only looks at the column, so it is printed
        -- as `?` (round-7 review X-8g).
        let sg := if rep.verdict == "BUILD" then "?" else toString rep.grew
        IO.println (s!"cycle\t{j}\t{g.site}\t{g.loc}\t{rep.verdict}\tsteps={rep.steps}" ++
          s!"\tstates={rep.distinct}\tdrawn={rep.drawn}\tgrew={sg}" ++
          s!"\tmint0={rep.mint0.length}\tmaxmint={rep.maxMint}\tconc={rep.nconc}" ++
          s!"\tdrawn0={rep.drawn0}" ++
          s!"\tnrows={g.nRows}\tcanon={sc}\texact={sr}")
        return (1, 0, 0, 0, (if rep.verdict == "REJECTED" then 1 else 0),
          (if rep.verdict == "FUEL" then 1 else 0))
    IO.println s!"#seg\t{j}\t{g.site}\t{g.loc}"
    -- D1: the policy and the budget the records are produced under.  An explicit `--policy=` /
    -- `--budget=` wins; otherwise the segment's own `sin` fields are used, which is what makes
    -- a policy-on compiler trace replay under that policy without being told.
    let segPol := (Policy.ofString g.policy).getD .shipped
    let usePol := polOpt.getD segPol
    let useBud := budOpt.getD g.budget
    match (if usePol == .shipped && useBud == 0 then replay fl fuel g
           else replayP usePol useBud fl fuel g) with
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
    | some "slbl" | some "svar" | some "scon" | some "senv" =>
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
        if !opts.contains "--trace" &&
            (opts.any (fun a => a.startsWith "--policy=") ||
             opts.any (fun a => a.startsWith "--budget=")) then
          let pol := policyOf opts
          let bud := natOpt opts "--budget=" 0
          match buildQueue parts (Sup.ofSeed ns.supplyLo) with
          | .error m => IO.println s!"pol\t{(policyOf opts).toStr}\tBUILD\t{m}"
          | .ok (q, su2) =>
            let st0 : State :=
              { incm := q, proc := PQueue.empty, env := {}, su := su2, trace := [], flags := fl,
                names := ns, site := site, su0 := (Sup.ofSeed ns.supplyLo).lo }
            let rep := polCensus pol bud fuel st0
            IO.println (s!"pol\t{pol.toStr}\tbase={base}\t{rep.verdict}\t" ++ polCols rep ++
              (if rep.msg.isEmpty then "" else s!"\t{rep.msg}"))
        else if opts.contains "--depth" then
          match buildQueue parts (Sup.ofSeed ns.supplyLo) with
          | .error m => IO.println s!"depth\tBUILD\t{m}"
          | .ok (q, su2) =>
            let st0 : State :=
              { incm := q, proc := PQueue.empty, env := {}, su := su2, trace := [], flags := fl,
                names := ns, site := site, su0 := (Sup.ofSeed ns.supplyLo).lo }
            let rep := depthRun fuel st0 {}
            IO.println (s!"depth\t{rep.verdict}\t" ++ depthCols rep)
            for (i, rl, v, sd, z, dz, ri) in rep.chain do
              IO.println s!"dm\t{i}\t{rl}\t{v}\t{sd}\t{z}\t{dz}\t{ri}"
        else if opts.contains "--cycle" then
          match buildQueue parts (Sup.ofSeed ns.supplyLo) with
          | .error m => IO.println s!"cycle\tREJECTED\tsteps=0\tstates=0\tcanon=-\texact=-\t{m}"
          | .ok (q, su2) =>
            let st0 : State :=
              { incm := q, proc := PQueue.empty, env := {}, su := su2, trace := [], flags := fl,
                names := ns, site := site, su0 := (Sup.ofSeed ns.supplyLo).lo }
            let rep := cycleRun fuel st0 [] [] {}
            let sc := match rep.canonHit with
              | none => "-"
              | some (i, j) => s!"{i},{j}"
            let sr := match rep.rawHit with
              | none => "-"
              | some (i, j) => s!"{i},{j}"
            IO.println (s!"cycle\t{rep.verdict}\tsteps={rep.steps}\tstates={rep.distinct}" ++
              s!"\tdrawn={rep.drawn}\tgrew={rep.grew}\tmint0={rep.mint0.length}" ++
              s!"\tmaxmint={rep.maxMint}\tconc={rep.nconc}\tdrawn0={rep.drawn0}" ++
              s!"\tcanon={sc}\texact={sr}")
            if rep.canonHit.isSome then IO.println s!"witness\t{rep.witness}"
        else if opts.contains "--mints" then
          let (parts', su1) := (parts, Sup.ofSeed ns.supplyLo)
          match buildQueue parts' su1 with
          | .error m => IO.println s!"mints\tREJECTED\tsteps=0\tdrawn=0\tmax=0\tremint=0\t{m}"
          | .ok (q, su2) =>
            let st0 : State :=
              { incm := q, proc := PQueue.empty, env := {}, su := su2, trace := [], flags := fl,
                names := ns, site := site, su0 := (Sup.ofSeed ns.supplyLo).lo }
            let rep := pumpRun fuel st0 {}
            IO.println (s!"mints\t{rep.verdict}\tsteps={rep.steps}\tdrawn={rep.drawn}" ++
              s!"\tmax={rep.maxAtKey}\tremint={rep.remintKeys}\tcmax={rep.maxAtCKey}" ++
              s!"\tcremint={rep.remintCKeys}\tkeys={rep.tally.length}")
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
          -- D1: `--trace` forces the RECORD path here as it does under `--replay`, and the
          -- records are produced UNDER the policy and the budget.  Without this the `json:`
          -- seed path answered `--policy=` with the `pol` census line and never printed a
          -- record, so `TestLoopTrace` -- which drives its seeds through this path -- compared
          -- a census line against a trace and was falsified before it started.
          let pol := policyOf opts
          let bud := natOpt opts "--budget=" 0
          let out :=
            if pol == .shipped && bud == 0 then out
            else solveSeedP pol bud fl site "-" parts ns (Sup.ofSeed ns.supplyLo) fuel
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
