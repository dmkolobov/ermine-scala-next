# Role `oracle`: a differential test that finds the bugs for us (build, 4 h)

Worktree `ermine-scala-wt-sql-oracle`, branch `sql-oracle` (yours alone; compile it first:
`sbt -batch core/compile core/copyResources core/Test/compile`, about 5 min).

Build `scalacheck-binding/src/main/scala/TestSqlDifferential.scala`: random relational
expressions, evaluated three ways, and every disagreement is a finding.

1. **Generator.** Random `Relation[Nothing, Nothing]` values (the algebra in
   `relational/Rel.scala`) over one to three small literal relations (`SmallLit`/literal
   tables of 0-8 rows, 1-4 columns of `IntT`, `DoubleT`, `StringT`, `BooleanT`, `DateT`,
   with and without NULLs, with duplicate rows offered). Constructors: `Filter` (random
   `Predicate` over the columns: comparisons, `And`/`Or`/`Not`, `IsNull`, constants),
   `Project` (random `Op`s: column, arithmetic, `if`, string ops, constants), `JoinOn` (natural
   and on-columns, every `JoinMode`), `Union`, `MinusI`, `Except`, `Combine`, `RenameR`,
   `Limit` (with an order over a key so it is deterministic; without, compare as multisets of
   the first N only when the input has no ties), `AggregateByGroup` and `Aggregate` (sum,
   count, min, max, avg over ints and doubles, groups of 0-2 columns), `LetR`/`MemoR` where
   the scanner supports them. Keep the header typing honest: build with `Typer` and discard
   ill-typed candidates (count discards; a property that passes vacuously is a bug in the test).
   Depth 1-4. Shrinking must work: a failing case must shrink to a small one.
2. **Reference evaluator.** A plain Scala interpreter over `List[Record]` in the test file:
   sets (a relation is a set: dedupe at every step), SQL three-valued logic where Ermine's
   `Predicates.toFn` uses it, aggregates over an empty group as the scanner's SQL would yield
   (state your choice per aggregate and why; where Ermine's in-memory `Mem` semantics and
   SQL's disagree, the finding is the disagreement itself, and the test pins whichever the
   orchestrator decides on the board). Reuse `Op.eval`/`Predicates.toFn` for expressions so
   the test is about relational structure, unless you find them wrong (then a finding).
3. **Backends.** (a) `Scanners.SQLite(dummySmenv)` on `jdbc:sqlite::memory:` through
   `SqlScanner.scanRel` (see `TestInMemoryScan`, `TestDbReports.memory`, `DB.scala`), always
   registered. (b) `Scanners.MicrosoftSQLServer` on the live server, one connection for the
   suite, registered only when `ERMINE_DB_URL`/`ERMINE_DB_USER`/`ERMINE_DB_PASSWORD` are set
   (copy `TestDbReports`' registration and its "not requested" line exactly; run it yourself
   with the password taken from `~/.config/ermine/db.env` into the environment the way
   `tracker/tools/db-reports.sh` does; never print it). Literal relations need no tables, so
   `ErmineSales` at tier s is fine as the database; temp tables land in `tempdb`.
4. **Comparison.** Rows as multisets after normalising doubles (relative 1e-9), dates to
   epoch days, NULLs; report the SQL text and the three row sets on failure. Also assert:
   no `TODO` in emitted SQL, no exception, and after the suite `tempdb` holds no `t...`
   table the suite created (count before/after).
5. **Findings.** For every class of disagreement, shrink, then write it up as a finding
   (`tracker/sql-audit/FINDINGS-oracle.md`, common format) with the exact relation, the SQL, and
   the rows from each side, and post it to the board. Then EXCLUDE that class from the
   generator with a named flag (`-Dermine.test.sqldiff.<class>=true` re-enables), so the
   property is green on the tree you hand back and each exclusion is a ticket. Do not fix
   the compiler yourself: implementers will, and will remove your exclusions.
6. **Gate.** Register the SQLite half in the ordinary `suites` (it must be fast: under 60 s,
   `minSuccessfulTests` chosen accordingly, say the number); add the SQL Server half to the
   `db` gate's `testOnly` list in `scripts/gates.sh`.
7. Handoff: the test compiles and is green with exclusions; the findings file; a one-paragraph
   note in the file header on how to add a constructor to the generator. Leave the worktree
   dirty (do not commit). Final message: 40 lines at most.

Also target the board: if `lowering`, `emitter` or `surface` post a WRONG with a relation,
add a pinned property for it (a named example beside the random one) before generalising.
