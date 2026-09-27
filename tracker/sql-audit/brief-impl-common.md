# Rules for every implementer (`impl-<area>`)

Read: `PLAN.md`, `brief-common.md`, `WORKLIST.md` (your items are marked with your role), the
findings files the items cite, and the board. Your worktree is `ermine-scala-wt-sql-<area>`
on branch `sql-<area>`, branched from `sql-audit` after the worklist commit. Compile it first.

## What a fix is

- **A test that fails before and passes after**, next to the fix, in the property style of
  `scalacheck-binding/src/main/scala/` (random values through a generator; a named example is
  a pin beside a property, never instead of one). For a WRONG: the shrunk repro from the
  finding as the pin, and the `TestSqlDifferential` exclusion flag for that class removed so
  the random property covers it from now on. For a WASTE: a property on the SQL SHAPE (the
  emitted text: nesting depth, count of DISTINCT/subqueries/temp tables, rows read via
  `RenderTrace`) plus the unchanged-results evidence (the differential suite, `TestRunner`,
  and where the fixtures touch it `TestDbReports`).
- The fix itself, in the file the finding names, written the way the file is written (see
  the Scala dialect rules in `brief-common.md`). No new dependencies.
- Every dialect: a change to a shared `SqlEmitter` method is checked on all six emitters at
  the text level (`TestSqlEmitters` runs them all); SQLite and SQL Server are also run live.
- Behaviour that a fix changes for a user is named in your report in one plain sentence per
  change (what a report author would notice), because the morning summary is built from it.

## Gates before hand-back (each once; cite the log path and the numbers)

1. `sbt -batch core/compile core/copyResources core/Test/compile`.
2. `sbt -batch 'core/testOnly *TestSqlEmitters* *TestInMemoryScan* *TestSqlDifferential* *TestDateAndScan* *TestRunner* *TestRenderTrace*'` plus any suite your items name.
3. The live SQL Server half: `tracker/tools/db-reports.sh`'s way of passing the password, then
   `sbt -batch 'core/testOnly *TestSqlDifferential* *TestDbReports* *TestMsSqlSmoke*'` with
   `ERMINE_DB_*` set. `TestDbReports` pins tier **xs** totals and the server holds tier **s**:
   run it anyway and report which properties are the xs-total pins (expected red at tier s)
   versus "same document" (must be green). Do NOT reload the database.
4. `tracker/tools/corpus-run.sh --batch <scratch dir>` + `python3 scripts/corpus-check.py <scratch dir> tracker/corpus-verdicts.expected` (unchanged verdicts).
Do not run the full `core/test`; the orchestrator runs it at landing.

## Conduct

- Only your items. If a fix needs a change in another implementer's file, post a `question`
  to the board naming the file and the exact change, and continue with your other items;
  the orchestrator will route it.
- Do not commit. Leave the worktree dirty. Never touch other worktrees.
- Budget in your brief. At the budget: write up, stop.
- Report: `tracker/sql-audit/report-impl-<area>.md` (files touched; per item: what changed,
  the test, the evidence, the plain-language sentence; departures from the worklist with
  reasons; gate numbers with log paths; open issues). Final message at most 40 lines.
