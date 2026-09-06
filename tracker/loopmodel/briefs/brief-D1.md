# Brief: D1 — ENGINEERED termination and order-robustness for `incorporateAll`

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, CLEAN at `3991a58` (L5 rounds
1–8, S1 and S2 committed; start figures: `lake build Rowpartition` 861 jobs, Audit 3898 theorems / 0 non-standard
axioms, `lake build looptrace` 1664; `-Dermine.rowSound` exists, default OFF — run every experiment at the SHIPPED
defaults unless the brief says otherwise). Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); compiler via
`bin/ermine` and `tracker/repro/satterm/run.sh` (`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS=-Dermine.useInterface=false`, one JVM at a time, `-XX:ActiveProcessorCount=2`). THIS STAGE MAY EDIT
SCALA in Part B only, behind a flag whose DEFAULT IS OFF; sbt allowed in Part B for `core/testOnly`; no default
flips; no commits.

THE DECISION THIS STAGE IMPLEMENTS (user, 2026-09-05): termination of the shipped loop is not a property of the
algorithm (eight L5 rounds; both mint factors `D` and `R` look unbounded — `L5-TERMINATION.md` §R8.6, review Y-19),
so it is ENGINEERED: (1) a BUDGET that makes every solve stop, with Lean proving the budgeted loop terminates and
that budget exhaustion is a REJECTION with a diagnostic, never an acceptance; and (2) an ORDER-ROBUSTNESS change so
that a valid program does not become budget-exhausted by hash order — the round-8 finding `GU05.json`
(`seeds/slow/`; `tracker/PERF-ROADMAP.md` P10): the same satisfiable input costs 743 draws at one id base and
47,000–81,000 at others, ≥ 1,210× in wall clock, decided by `PQueue`'s hashCode-keyed priority alone. A budget
without (2) would make GU05 type-check or fail by id base, which is worse than slow.

The design rule from Stage 7b still governs: a guard may replace a mint by a NAME for the same row, never by
silence (suppressing mints starved the queue's own cleanup and cost 1.9×; `tracker/satterm/KEYED-EMPTY-STAGE7B.md`).

READ FIRST: `L5-TERMINATION.md` §R8.0/§R8.4c/§R8.6 and §R7.1c (what `rowSet`/`ensureSuperset` make monotone);
`L5-REVIEW.md` round-8 Y-6/Y-10/Y-15; `Loop/Queue.lean` (`pop`: deepest variable in the reverse-topological order,
then smallest rhs hash, then most recent — the model reproduces the compiler's order exactly, which is why it can
try OTHER orders without touching Scala); `Loop/Depth.lean` (`--depth`), `Loop/VocFix.lean`
(`terminates_of_drawsAtMost`: a draw budget IS a termination proof); `Constraints.scala` (`incorporateAll`,
`PQueue`, `TypeVarGraph`, the `splitKey`/`splitRow`/`resRow` guards); `tracker/tools/perf-bench.sh` (P1 harness);
`tracker/loopmodel/briefs/brief-L5r8.md`, `S1-SOUNDNESS.md` and `S2-FIX.md` for the current theorem inventory
(`solve_accepted_faithful` is the soundness chain a policy change must keep intact).

## Part A — design and model experiments (LEAN + measurement only; no Scala)

A1 **The budget, specified.** Unit: fresh ids drawn by the loop per solve (the quantity every theorem is about;
   `Sup.drawn − drawn0`), not dequeues. Where it is checked (the two minting sites), what it raises (a `died`
   message naming the site, the draw count and the budget; a REJECTION), and the value: report the corpus maximum
   over all eight groups from round 8's traces (149 loop draws) and GU05's worst measured base (81,481), and
   propose a budget with a stated safety margin. In Lean: add the budget to the model behind a flag, prove
   `budget_terminates` (fuel = budget-derived, via `terminates_of_drawsAtMost`) and `budget_never_accepts`
   (exhaustion is `.died`, `sys` unchanged — `step_died_sys`'s shape); trace-equality with the compiler is
   unaffected while the flag is off (say why, then check with the L2 differential).
A2 **Order policies, on the model.** Add a dequeue-policy flag to the model's `pop` (the shipped order stays
   the default): at least (i) concrete-first (partitions with a nonempty concrete part before abstract ones,
   ties by the shipped order), (ii) smallest right-hand side first, (iii) FIFO, (iv) the shipped order with the
   id replaced by first-occurrence rank (order-canonical: independent of the id base by construction). For each
   policy: GU05 and GU05MIN at the 25 id bases (draws, dequeues, model time), NP01, the 18 tracked seeds at 10
   bases, and the whole eight-group corpus replay for draws/dequeues per solve (the model is the fast oracle;
   the corpus run is ~75 min — under `setsid nohup` with a log). Report a table: policy × {GU05 max/min ratio,
   corpus total draws, corpus total dequeues, solves that get worse by > 2×}. The winner is the policy that
   makes GU05's spread ≤ 10× while not increasing corpus dequeues by more than a few percent. If no policy does,
   say so and report the best.
A3 **Soundness and termination of the winner, on the model.** The order does not change the derived set's
   semantics (every policy dequeues the same partitions), so S1's soundness theorems must transport: state
   which hypotheses of `solve_sound` mention the order (none should) and re-check the audit with the policy flag
   on. Termination on the certified fragments (`NoConc`, `VocFixed`) is order-independent — say where the proofs
   use `pop`'s specifics, if anywhere.
A4 **Write the design** as `tracker/loopmodel/D1-DESIGN.md`: budget spec + policy winner + what Part B changes
   in Scala (the exact functions), the flag names (`ermine.solveBudget=<n>`, `ermine.dequeuePolicy=<name>`), the
   gates Part B must pass, and the performance measurements Part B must take. STOP here and report; the
   orchestrator confirms Part B.

## Part B — the flagged Scala change (only after Part A is reported and confirmed)

B1 Implement the budget and the winning policy in `Constraints.scala` behind the two flags, DEFAULT OFF, in a
   worktree; mirror both in the model so the model's flags and the compiler's agree (the trace records must
   carry the policy so `looptrace --replay` reproduces a policy-on trace).
B2 Gates, all with the flags OFF first (nothing may change): `core/test` (913/914 known), `TestLoopTrace`,
   the L2 corpus differential (byte-identical row trace), `.ei` unchanged; then with the flags ON: the same
   differential (model and compiler agree under the new policy), `core/test`, and the perf harness
   `tracker/tools/perf-bench.sh` batch mode before/after (the P1 baselines), plus GU05 at 25 bases on the
   compiler under the new order (the spread), plus gu05's real module load time.
B3 Report `tracker/loopmodel/D1-CHANGE.md` with every measurement; the plan row; adoption (default ON) is the
   USER's decision and is not made here.

Outcomes, say which: (A-done) design with a winning policy and a budget, Part B not started; (B-done) flagged
change with all gates green and the numbers; (NO-WINNER) no policy meets the bar — report the table and the
best available, and the budget alone.

Constraints as always: audit 0 non-standard axioms, `#print axioms` in scratch under
`/home/dmitry/.claude/jobs/880c725d/tmp/D1/`, no `sorry`, no silent weakening, never `lake exe cache get`, no new
`require`, no new project, never touch `~/research/leanwork`, `CutSearch.lean` out of the root import list, disk
tight (gzip traces; delete `.ei` files you cause), long runs under `setsid nohup` with a log (background shells are
capped at ten minutes), `pkill -f` matches itself, one JVM at a time. Report early and keep it current.
