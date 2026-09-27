# Role `lowering`: relation to query, and query to rows (audit, read-mostly, 2.5 h)

Own: `core/src/main/scala/com/clarifi/reporting/relational/SqlScanner.scala` (all of it),
`relational/Scanner.scala`, `relational/package.scala` (`sorting`, `uniq`, the procedures),
`sql/SqlExecution.scala`, `backends/SQLBackend.scala`, `backends/DB.scala`, `Run.scala`,
`RenderTrace.scala` (the counters only), `ermine/json/Runner.scala` (where a render obtains a
scanner and a connection).

Questions to answer, each with a repro:
1. `compileRel` for every `Relation` constructor: `joinOn` (all `JoinMode`s: is a left/outer
   join's NULL side typed nullable? does `squashLiteral` preserve outer semantics?), `union`,
   `minus`, `filter`, `project` (an `Op` referring to a column the subquery renamed; window
   functions inside a projection, `selectWindows`), `rename` (to an existing name), `except`,
   `combine`, `aggregate`, `aggregateByGroup` (grouping by an expression; an aggregate over
   zero rows: SQL gives one NULL row, Ermine's `Mem` gives what?), `limit` (`orderQuery`,
   a limit without an order, `start`/`end` off-by-one, `Limit` on top of `Limit`), `pivot`,
   `LetR`/`MemoR` (temp tables: created where, dropped when, names `t<guid>` and
   `SqlScanner.scala:37-38`'s TODO), `TableProc`, `Note`, `EmptyRel`, `SmallLit`.
2. Distinctness: `DistinctiveQuery`, `satisfyDistinct`, `preservesDistinctness`,
   `megaDistinctness`, `Reflexivity`, `Fundepped`, `joinReflexivity`. A relation is a SET.
   Where does the scanner add `DISTINCT`, where does it omit it wrongly (duplicates delivered
   to Ermine), where does it add it needlessly (a whole extra sort on SQL Server)? Note
   `SqlScanner.scala:1157`'s XXX.
3. `compileMem` and the `Mem` paths that sit on top of SQL results: `HashInnerJoin`,
   `HashLeftJoin`, `MergeOuterJoin` (needs both sides sorted: are they, in the same collation as
   the database? SQL Server's default collation is case-insensitive; Ermine's `Order[Record]` is
   not), `GroupByM`, `AccumulateM`, `ProcessM`, `Pivot`, `LimitM`, `DifferenceM`, `UnionM`,
   `MemoMem`. Which of them pull a whole relation into memory when a SQL form exists?
4. Execution: `SqlExecution` result decoding per `PrimT` (nullable, dates, booleans via
   `getBoolean`, UUIDs), `sys.error("Unexpected NULL...")`, statement and result-set closing on
   exceptions, fetch size, `transaction`, `sequenceSql`'s `p.distinct`, temp-table cleanup on
   failure (`cleanTempTables`), what a render leaves behind in `tempdb` after an exception
   (check the live server: `scripts/db.sh sql ErmineSales "select name from tempdb.sys.tables"`).
5. Ordering: `scanRel`'s `order` argument, `orderQuery`, and `relational.sorting`: when is the
   sort done in SQL and when in Ermine; is an `ORDER BY` inside a subquery (which SQL Server
   rejects without TOP, and SQLite ignores) ever emitted?
6. The `(fx4-sql)` and `TestDbReports` "same document after row sort" note: which reports
   come back in different orders on SQLite vs SQL Server, and is any consumer order-sensitive?

Method: read; then for each suspect, build the relation in Ermine (a module under
`scratch-sql-audit/lowering/`), dump both dialects' SQL through the REPL (see the common brief),
and execute it: SQLite via python3's `sqlite3` in memory, SQL Server via `scripts/db.sh sql`.
For a rows-level WRONG, show the rows. For temp tables, look at the live server before/after.

Deliver `tracker/sql-audit/FINDINGS-lowering.md`. Post each WRONG to the board as you find it,
with the relation, so the `oracle` role can target its generator at it.
