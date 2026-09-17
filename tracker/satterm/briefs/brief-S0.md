# brief-S0 — diagnosis (Opus implementer, 3 h)

Worktree `~/research/ermine/ermine-scala-wt-subsume-s0`, branch `subsume-s0`. Read `brief-S-common.md` first.
Report: `tracker/satterm/SUBSUME-STAGE0.md`. **No fix in this stage** — measurement and separation only.

## Goal

Reproduce the hang alone and SEPARATE the three hypotheses of Part B (H1 finite-but-explosive, H2 cyclic
substitution, H3 the walk is the victim) by measurement, so that S1a/S1b/S2 build on numbers rather than a
reading of the code. Record which survive, with logs.

## Steps

1. **Reproduce.** `sbt core/compile core/copyResources`, then `sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'`
   in the background with a log. Confirm 11 of 12 properties finish and the B1 rejection property
   (`scalacheck-binding/src/main/scala/TestDateAndScan.scala:192`) does not return within 5 minutes. Take
   `jcmd <pid> Thread.print` every 30 s for five minutes into scratch; confirm the frames of Part B. Kill by PID.
2. **Read the walk before instrumenting it, and say what it does.** `Type.scala:649-660` (`typeHasKindVars.vars`),
   `Kind.scala:58-65` (`ArrowK`/`VarK` `vars`), `Kind.scala:119-136` (`HasKindVars` for `Map`/`List`/`V`),
   `Vars.scala` (`++`, `--`, `contains`, `foreach`, and `ForeachIterable`'s iterator), `Subst.scala:169`
   (`SubstEnv.kindVars`) and `:642-648`. Settle, with line references: does `VarT(v) => v.extract.vars` follow the
   variable's BINDING in `hm.types`, or only its KIND annotation? (The orchestrator's reading: `V[Kind].extract` is
   the kind annotation and `VarK(v).vars = Vars(v)`, so no binding is followed — you confirm or refute this;
   the prompt's H2 wording loses if you refute it.) Where is the traversal actually forced — at view
   construction (`++` is eager in building closures, lazy in traversing) or at `.filter`? Is the `Traversable`
   `++` at `:648` strict? Does anything in that expression re-evaluate `hm.kindVars` more than once?
3. **Instrument** behind `-Dermine.subsumeTrace=true` (default OFF, read once into a `val`), printing to stderr or
   a file named by `-Dermine.subsumeTrace.out=`: on entry to the block at `Subst.scala:642` and again just before
   `:648`, `hm.types.size`, `hm.kinds.size`, the number of `++` nodes the `kindVars` view would contain (count the
   fold), the total syntactic size of the types in `hm.types` (nodes, counting shared subterms EACH time they are
   reached, i.e. tree size) versus their DAG size (distinct object identities, `IdentityHashMap`), the maximum
   `AppT`/`Forall` depth, whether `Type.fskvs(types)` returns and in how long, whether `hm.kindVars.filter(skss)`
   returns and in how long, and the sizes of `sks`/`sts`. Also count how many times `subsumeType` is ENTERED for
   the module and for the binding `bad` (the sampled frames are identical whether one call never returns or
   many calls each return — separate those two).
4. **Separate H1/H2/H3.** From the 30-second samples and the instrumentation: a `types.size` that is still growing
   when the walk begins (or an entry count that keeps rising) is H3; a fixed large size with one walk that never
   returns is H1; a repeating set of `v.extract` targets / a cycle in the object graph (check with an identity
   set on the `vars` recursion) is H2. If the tree-size/DAG-size ratio is large, say so: exponential unfolding of
   a shared type is a fourth mechanism the prompt did not name — report it as such.
5. **Control: the favourable order.** The same program passes inside the full `core/test` (order of `Supply`
   ids). Find a cheap favourable run: e.g. `sbt 'core/testOnly com.clarifi.reporting.TestSchema com.clarifi.reporting.TestDateAndScan'`
   or another suite ahead of it in one JVM, or a seeded `Supply` in a scratch copy of the fixture — whichever
   makes the B1 property REJECT quickly. Record the instrumentation numbers on that run. Then `-Dermine.rowTrace=<file>`
   on both runs and compare with `tracker/tools/trace-ab.py` (and `rowtrace-summary.py`): same rule path that
   merely finishes, or a different path? Does the path go through `labelDecide` (`Constraints.scala:2763`)? Does
   the rowSound budget ever count (`GenRules.rowSoundBudgetHits`, `RowTrace` kind `budget`)? Does the draw budget
   (`-Dermine.solveBudget`, default 20000) fire?
6. **Minimal reproduction.** Try to shrink B1: fewer fields, a single missing field, no `dateDiff_Op`, a plain
   `combine_Op` over a missing column, direct `bin/ermine` on a `.e` file (no scalacheck). Report the smallest
   program that hangs alone and whether it hangs under `bin/ermine` (which is what the LSP runs). Also a
   deadline-bounded reproduction the reviewer and S2 can rerun in under two minutes.
7. **Baselines for later stages** (cheap, one run each, in the background): `tracker/tools/corpus-run.sh --batch
   <scratch>/corpus-base` and its verdict counts (`corpus-verdicts.py`) on this tree — the prompt says
   89 LOADED / 79 REJECTED / 0 UNKNOWN over 168; record the actual numbers; `sbt 'core/testOnly *TestLoopTrace'`
   count.
8. **The E11b connection.** One paragraph: the same id-order dependence that E11b parked (`tracker/loopmodel/
   E11b-ORACLE.md`, `E11c-SOLVEDET.md`, `-Dermine.solveDet`) is why the hang hid; does `-Dermine.solveDet=true`
   change whether B1 hangs alone? (One run, background.) Do not reopen E11b.

## Deliverables

`SUBSUME-STAGE0.md` per the common brief's structure, with: the numbers table (alone vs favourable), the traces'
paths, the surviving hypothesis(es), the minimal reproduction, the baselines, the E11b note, and the paths of
your instrumentation changes (`Subst.scala` only, plus any scratch fixture). List every changed file. No commits.
