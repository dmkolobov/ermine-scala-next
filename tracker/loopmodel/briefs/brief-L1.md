# Brief: L1 — the row-constraint loop as a Lean FUNCTION, executable, trace-comparable

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration` at `2411296` plus
UNCOMMITTED Stage 7 work (`git status` lists 9 entries: do not touch any of them except
`tracker/lean/Rowpartition.lean`, where you may add your import line(s) only). Lean project
`tracker/lean/` (Lean 4.33.1, Mathlib v4.33.1; `export PATH=$HOME/.elan/bin:$PATH`). Scala toolchain:
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`
(classes are compiled and current; you may run `bin/ermine` and the repro harness; do NOT run sbt).

READ FIRST: `tracker/LOOP-MODEL-PLAN.md` (the programme, and L1's acceptance criteria — they are
the contract), then `tracker/ROW-CONSTRAINT-STATE.md` top section, `tracker/TICKET-sat-termination.md`
§3e–§3i, `tracker/satterm/KEYED-EMPTY-STAGE7B.md` §3 (the queue-GC mechanism, which your model
must reproduce), `tracker/satterm/KEYED-ROW-STAGE5.md` §A.3 (where concrete rows live; what
`makeEmpty` and `unify` do to the queues and the environment), `tracker/lean/README.md`
(vocabulary: `Constraint`, `mk`, `vset`, `conc`, `System`; the transcription modules
`KeyedSplitScala.lean`, `KeyedRowScala.lean`, `KeyedEmptyScala.lean` show how single branches were
mirrored — you are mirroring the whole loop). Then the Scala, all of it, side by side with what
you write: `Constraints.scala` — `Q` (≈ 403–640: `PSQK`, `TypeVarGraph`, `pop`, `PQueue.dequeue`,
`contains`, `++!`, `trim`, `findRHS`), `incorporateAll` (≈ 1109), `learnPartitions` (≈ 1014–1110,
the lazy lookups), the rules (`splitConcrete`, `commonSubexpression`, `substitution`,
`cancellation`, `resolution`, `selfSubstitution`), `makeEmpty` (≈ 1407), `makeConcrete`,
`destructiveSub`, `subPartitions` (≈ 1222–1300), `unify`, `RHS`/`Partition` (`equals`/`hashCode`
ignore the `Inference` tag), `RowTrace.scala` (the TSV record format you must emit), and
`Subst.scala` (`SubstEnv`, `instantiateType`, and where `Subst.solve` calls `incorporateAll`,
including the early label check `checkLabel`/`labelClash` and how a `Death` is raised). The repro
harness `tracker/repro/satterm/SatTermRepro.scala` + `run.sh`/`sweep.sh` shows how a `json:` seed
becomes a system at an id base (variable i → base+i, labels `Repro.lN`, Supply from base+#vars)
and how a trace is produced (`run.sh trace json:<seed> <base>` with `ERMINE_JAVA_OPTS=-Dermine.rowTrace=<file>`).

## Deliverables

1. **The model**, new modules under `tracker/lean/Rowpartition/Loop/` (e.g. `State.lean`,
   `Queue.lean`, `Rules.lean`, `Step.lean`, `Trace.lean`, `Json.lean`), one umbrella
   `Rowpartition/Loop.lean` imported from the root. Requirements:
   * State = incm queue, proc queue (each modelled with the SAME ordering as `Q`: a
     priority-search structure keyed by `PSQK` and popped through the type-variable graph
     exactly as `pop` does — read `pop` and `TypeVarGraph` until you can state the dequeue
     order as a function; if it depends on `hashCode` of an id, model the id's hash as the
     identity or the real function, and SAY which), the environment (per variable: unbound /
     empty / concrete row / alias), the supply (next fresh id), the flags record (shipped
     defaults; make the flags parameters so `emptyRow` on/off and the Stage 7b variant can be
     modelled later), and the trace.
   * `step : State → StepResult` with `StepResult = continue State | done State | died String`,
     mirroring `incorporateAll`'s dispatch branch by branch, with `learnPartitions`'s fold and
     every rule under the shipped defaults, `trim`/`++!` dedup semantics, `makeEmpty`'s `aux`
     cascade and erasure, `makeConcrete`'s `srs` and `keepDefs`, `unify`'s rewrite-and-remove,
     and the `Inference` tags carried for the trace only.
   * `run : State → Nat → RunResult` with an explicit fuel; NO `partial`, no `Classical`, no
     `sorry`, no axioms beyond the standard three (the audit must stay at 0 non-standard).
   * Reuse `Rowpartition.Constraint` (`mk lhs vset conc`) as the constraint type, or give a
     total conversion both ways and prove it a bijection on the constraints the loop produces;
     the L3 refinement proofs need the two vocabularies to meet.
2. **The executable** `looptrace`: a `lean_exe` target in the existing `lakefile` (allowed: it
   is the same project; do not add a `require`), `lake exe looptrace <seed.json> <base> [fuel]`
   printing the trace in `RowTrace`'s TSV format (the `step`/`learn`/`sat`/`solve` records with
   the same columns), plus a `--verdict` mode printing SOLVED/REJECTED(msg)/FUEL and the final
   bindings in the harness's `v0 := ...` shape. Use `Lean.Json` for the seed.
3. **The differential run**: `tracker/tools/looptrace-diff.py` (new) that normalises both traces
   (ids → position of first occurrence, labels → names, drop timing columns) and diffs them
   step by step; run it for the six tracked seeds `tracker/repro/satterm/seeds/{W2,H2,NE6,W3,W4,G7}.json`
   (the first three are built into the harness by name; use `json:` files for all six — write
   `W2.json`/`H2.json`/`NE6.json` from the harness's definitions if missing) at bases 0–9. Report
   the agreement table; for every disagreement, the FIRST differing step on each side and its
   cause (a model bug you then fixed, or a compiler behaviour you list as "not modelled" with
   why). Acceptance is 0 unexplained.
4. **The correspondence table** (report §): every Scala function `incorporateAll` reaches →
   its Lean definition → faithfulness note (exact / abstracted how / not modelled and why it
   does not matter for L1's seeds). Be exhaustive; the reviewer will check it against the code.
5. **Report** `tracker/loopmodel/L1-MODEL.md` (new dir): write EARLY, keep current; the
   definitions of `State`/`step` verbatim, the dequeue-order statement, the table, the
   agreement results with commands, open items for L2. Update `tracker/LOOP-MODEL-PLAN.md`'s
   status row for L1. `tracker/lean/README.md`: a "Loop model" section and build-table rows.

## Traps (project memory)
`decide` cannot see through `mk`/`slist`; no `norm_num`; `Finset.card_insert_of_notMem`; lake keys
builds on content hashes; `CutSearch.lean` stays out of the root import list; never `lake exe cache
get`, never a new `require`, never another Lean project, never touch `~/research/leanwork`; disk is
tight; scratch only under `/home/dmitry/.claude/jobs/880c725d/tmp/L1/`. `bin/ermine` writes `.ei`
files: use `-Dermine.useInterface=false` and delete strays under `core/examples`. `pkill -f`
matches itself. No commits.

## Report back
The agreement table (seed × base → agree / first mismatch), the "not modelled" list, the
executable's invocation, build job count and audit line, files with line counts, and anything you
could not do, plainly. Do not claim agreement you did not run.
