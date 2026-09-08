# Review brief: F3 — the seven small library and migration fixes (A1b, B1, A4, A3, C2, C5, K-1)

You are reviewing stage F3 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `9ebe09b`
plus the UNCOMMITTED F3 deliverables). Implementer's brief `tracker/loopmodel/briefs/brief-F3.md`; report
`tracker/loopmodel/F3-FIXES.md` (618 lines; §1 reproductions before, §2 the fixes, §3 the gates incl. §3.3 the twelve
`.ei` bindings and §3.4 what moved in the row trace, §4 the `MapView` sweep, §5 not done + the ONE JUDGEMENT CALL);
changes: `PrimExpr.scala`, `Type.scala` (K-1), `SqlScanner.scala`, `relational/package.scala` (A1b), stdlib
`Date.e`, `Layout/Scan.e`, `Relation.e`, `Relation/Op.e`, `Relation/Scan.e`, examples `Time/FiscalTree.e`,
`Time/Helpers.e` (comment), NEW `Time/shouldfail/date01_datediff_free_row.e`, NEW tests
`scalacheck-binding/src/main/scala/TestDateAndScan.scala`, `TestInMemoryScan.scala`, the ticket entries, plan row,
state-file note, memo K-1 note, `corpus-run.sh` comment. Ticket: `tracker/TICKET-stdlib-findings.md`. You edit
NOTHING except a scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/review-F3/` and your report
`tracker/loopmodel/F3-REVIEW.md`. ONE JVM at a time (`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, sbt
allowed); long runs under `setsid nohup` with a log; `pkill -f` matches itself (kill by PID); delete every `.ei` you
cause; no commits; never `lake build` (`lake exe looptrace --replay` and `lake env lean` only). TRAP the implementer
paid for: `sbt core/compile` does NOT copy `resources/modules` into `target/classes/modules` — run
`sbt core/copyResources` (or `core/compile core/copyResources`) before any `bin/ermine` gate and `grep` the target copy
for a string you expect. The orchestrator is running `sbt core/test` on this tree in parallel.

1. **Each defect, before and after.** Re-reproduce all seven from the ticket text with your own minimal
   probes on the PRE-fix tree (`git stash` is NOT available to you — use `git show HEAD:<path>` into scratch or the
   report's §1 transcripts as the "before"; say which) and confirm each fix on the post tree: A1b (drive the in-memory
   pivot / hash join / sort — the new `TestInMemoryScan` and its negative control), B1 (the deferred failure is now
   static; the new negative module's diagnostic), A4 (twelve months), A3 (accessors under a non-UTC default zone
   give the UTC answer; which published behaviours change — is `Time/FiscalTree.e`'s edit the right response?), C2,
   C5 (three names resolve from `Layout.Scan`; `sumBy'`'s residual shrinks and nothing else), K-1 (the concrete
   identity no longer reaches the solver; AND the added `ss.length == cs.size` — the implementer says it is
   load-bearing because `ss` concatenates every concrete part, so `ss.toSet == cs` alone would also collapse
   `(|Foo,Bar|) <- ((|Foo,Bar|),(|Foo|))`, which is UNSATISFIABLE: verify that with a probe both ways).
2. **THE JUDGEMENT CALL (§3.4 / §5).** The brief said STOP if anything but the disappearance of a concrete-identity
   constraint moves the row trace. Eight segments of 3.2 M (`Present` 3, `Algebra` 5) carry the same constraint
   multiset, counts and supply bounds in a DIFFERENT ORDER; the implementer argues this is the downstream shadow of
   the 2,308 collapses the fixed guard performs before `Subst.solve` in `Algebra` alone (id base shifts), and
   proceeded. Decide it: reproduce the eight (the report names them), show the mechanism (is the order change
   exactly what an id-base shift produces — compare with the known B6 behaviour — or could the guard's collapse
   change WHICH constraints a solve receives?), and say whether the stage should have stopped. If the mechanism is
   not the one claimed, that is a blocking finding.
3. **The `.ei` sweep.** 11 of 224 interfaces move, twelve bindings named, "none weaker" — classify them yourself
   (`ei-classify.py`, `-Dermine.loadInSeries=true` both sides; note the tool gap: `ei-diff.sh` hoists only
   `Ai/Common.e`, so `Wide_Leaderboard` fell off a chunk — reproduce, and say whether any OTHER interface is missing
   or mis-hoisted). Every move must be `sumBy'`'s shorter residual, a K-1 identity deletion, or B1/A3's intended
   change.
4. **Gates, re-run:** `sbt core/test` (937 total / 936 pass, the documented `Constraints.disjunction` failure);
   `TestLoopTrace` 720/720; `corpus-run.sh --batch` 85 / 69 / 0 over 154 (the +1 is the new negative);
   `looptrace-corpus.sh` on `Present`, `Algebra`, `Time` and `top` (agree = segments, 0 skip) plus the per-group
   trace diff against a pre-fix trace of the same groups (build the base tree in scratch from `git worktree`? NO —
   no worktrees; use the report's classification of the delta (+737: +10 stdlib load, +34 `Layout.Scan`, +25 the new
   module) and check it against your own ON-tree trace by counting); `sql-render.sh` byte-identical; `repl-smoke`
   47, `lsp-smoke` 98; `perf-bench batch -n 3` when the load is < 1.3; the `incomplete` group replay if you have
   the time (expect 1,905,718 agree, 0 skip — the implementer skipped it, stated).
5. **The `MapView` sweep (§4):** 115 sites listed — spot-check ten, including any `==`/`hashCode`/`Map`-keyed use of a
   `.view`/`mapValues`/`filterKeys` result that the sweep marks safe.
6. **Prose:** the six ticket entries, the plan row, the state-file note, the memo's K-1 note, the `corpus-run.sh`
   comment; and §5's "not done" list — is `Time/Helpers.e`'s `dayCount` hole (B1's guarantee does not reach the
   example helpers) worth a ticket entry?

Findings prefixed `N-`, ranked, CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE / FIX-THEN-ADVANCE / REDO.
Write the report early and keep it current.
