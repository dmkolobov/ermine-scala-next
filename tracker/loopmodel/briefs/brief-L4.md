# Brief: L4 — the trace test in `core/test`, and the parallel loader brought into the population

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`. The tree carries a
STAGED L2 state (`git diff --cached`) and unstaged L3 Lean work by another agent (running in parallel
on `tracker/lean/Rowpartition/Loop/{Wf,Order,Refine,RefineConcrete}.lean`); touch none of those. Your
files: `core/src/test/scala/...` (new test sources), `RowTrace.scala` (Part B only, additive),
`tracker/tools/looptrace-diff.py`/`looptrace-corpus.sh` (Part B segmenter), a new
`tracker/loopmodel/L4-TEST.md`, additive edits to `tracker/lean/README.md` and the plan's L4 row.
Toolchains: Scala `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
Lean `export PATH=$HOME/.elan/bin:$PATH` (you only BUILD/RUN `lake exe looptrace`; you do not edit Lean).
sbt: one at a time, and check `ps` for any running `bin/ermine`/java replay before every sbt
invocation (the other agent may replay seeds through the compiler) — wait until none.

READ FIRST: `tracker/LOOP-MODEL-PLAN.md` (L4's acceptance criteria and the "Known scope limits"),
`tracker/loopmodel/L2-CORPUS.md` §3/§8 (the replay records, why the parallel loader cannot be
segmented, `RowTrace.log` synchronising per line), `L2-REVIEW.md` (F3/F4/F8: what the differential
does not cover; the exit-status mismatch between `looptrace-diff.py` and `looptrace`), the L1/L2 tool
headers (`tracker/tools/looptrace-diff.py`, `looptrace-corpus.sh`), `RowTrace.scala`,
`tracker/repro/satterm/SatTermRepro.scala` (a seed → a solve at an id base, in-process, no stdlib
boot), `core/src/test/scala/com/clarifi/reporting/TestConstraints.scala` and
`.../util/TestStreamTUtils.scala` (the project's ScalaCheck style; `Test / fork := false`, so a
system property must be set before `RowTrace` initialises — read how `RowTrace.enabled` is defined
and decide whether a test can enable tracing in-process or must spawn a child JVM).

## Part A — the test (the plan's L4 acceptance)

A ScalaCheck/property test in `core/test` that, for the tracked seeds under
`tracker/repro/satterm/seeds/*.json` AND generated systems (reuse `rowclosure.py`'s generator by
porting its shape to Scala, or a small generator of your own with the same coverage: ≥2 abstract
parts, concrete parts, satisfiable by construction with a model), runs each through the SOLVER with
the trace on and through the Lean model, and asserts the traces are equal record for record.
Design constraints, all to be stated in the test's header comment:
* The compiler side must be the REAL `Subst.solve`/`incorporateAll` path (the repro harness's
  in-process call is fine; no stdlib boot needed).
* Enabling the trace: `RowTrace.enabled` is a constant read once; if it cannot be enabled in-process
  without changing the inert default path, spawn a child JVM (`java -Dermine.rowTrace=… -cp …`
  with the same classpath the test runs under) — do NOT make `RowTrace` slower on the default path.
* The Lean side is `lake exe looptrace` (build it with `lake build looptrace` first; the binary is
  `tracker/lean/.lake/build/bin/looptrace`). When the binary or `lake` is absent, the test must
  SKIP with a clear message, not fail, so `core/test` does not hard-depend on the Lean toolchain —
  but when present it must run in the ordinary `sbt core/test`.
* A POSITIVE CONTROL: a second property injects a divergence (e.g. runs the model with
  `--flags=nolabel` or a wrong id base against the compiler's shipped-flags trace) and asserts the
  comparison FAILS. Without it the test cannot be trusted to detect anything.
* Fix L2 review F8 on the way: `looptrace-diff.py --segments` must exit non-zero on `hashdiff`/`eqdiff`.
* Run time: the whole property must stay under ~60 s in `core/test`; size the sample accordingly and
  report the numbers.
Acceptance: `sbt -batch -J-Xmx3g core/test` passes with the new properties (expect the known
`disjunction sound` starvation to remain the only failure), the positive control fails when the
injection is enabled, and `tracker/lean/README.md` states the rule: a solver change must keep this
test green, and a model change must keep the corpus replay (L2) green.

## Part B — the parallel loader (the plan's first known scope limit)

Add a THREAD ID to every trace record (append a column at the END of each line so
`keptdef-mints.py`, `splitkey-counts.py` and the L2 replay, which index from the start, keep
working — verify each of them still runs), emit it in `RowTrace.log`, and extend
`looptrace-diff.py --segments` / `looptrace-corpus.sh` to demultiplex by thread before segmenting.
Then run the L2 corpus replay WITHOUT `-Dermine.loadInSeries=true` on `incomplete/gu05` and on the
`Ai` group, and report: segments, agreement, and whether gu05's 1,372-partition solve (the one
`KEYED-SPLIT-STAGE2.md` §B4 describes; nSat 1372 under the parallel loader) now replays and
agrees. Recompile ONCE for this (`sbt -batch core/compile`, after checking `ps`); it is inert without
`-Dermine.rowTrace`. If the demultiplexed traces still cannot be segmented (e.g. a solve migrates
between threads), report exactly why and what would be needed.

## Report
`tracker/loopmodel/L4-TEST.md` (write EARLY, keep current): the test's design and why (in-process vs
child JVM), its sample sizes and run time, the positive control's failure output, core/test totals,
the Part B numbers, files with line counts, and anything you could not do, plainly. Update the plan's
L4 row and the README additively. No commits; delete stray `.ei` files; gzip traces; scratch only
under `/home/dmitry/.claude/jobs/880c725d/tmp/L4/`; `pkill -f` matches itself.
