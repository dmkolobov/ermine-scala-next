# Role `emitter`: the SQL text each dialect emits (audit, read-mostly, 2.5 h)

Own: `core/src/main/scala/com/clarifi/reporting/sql/*.scala` (`SqlEmitter`, `SqlExpr`, `SqlQuery`,
`SqlStatement`, `RawSql`), `PrimT.scala`, `PrimExpr.scala` where they meet JDBC, and
`core/src/test/scala/com/clarifi/reporting/sql/TestSqlEmitters.scala` (what is already covered).

Questions to answer, each with a repro:
1. Stubs that reach the wire: `emitOver` prints `TODO I don't yet know how to play ...` on every
   emitter but SQL Server (`SqlEmitter.scala:270`), `emitTryCast` likewise, SQLite/Vertica/Postgres
   `emitDateAddName` throw. Which Ermine surface operations reach each stub, on which dialect,
   and what happens (exception, or SQL text with `TODO` inside, executed)? The default runner
   is in-memory **SQLite**, so a stub there is a user-visible failure. SQLite 3.51 (the bundled
   `sqlite-jdbc 3.51.1.0`) supports window functions, `date()`/`julianday` arithmetic, `CAST`,
   `IIF`, `VALUES` row constructors, `EXCEPT`/`INTERSECT`: what can now be emitted properly?
2. Literals and types: quoting and escaping of strings (embedded quotes, backslashes, NUL,
   non-BMP characters), booleans per dialect, dates and timestamps (time zone, precision,
   `emitDate`/`emitTimestamp` vs the prepared-statement path), doubles (NaN, infinity, `-0.0`,
   precision loss through `toString`), longs beyond 2^53, UUIDs, NULL of each type, empty
   literals (`emitEmpty`), one-row and many-row literals (`emitLiteral`, `EmitLiteralTVC`,
   `fallbackEmitLiteral`, SQL Server's 1000-row VALUES limit, SQLite's compound-select limit).
3. Identifiers: `emitColumnName`/`emitTableName` quoting per dialect; column names with spaces,
   keywords, quotes, `#` and `$`; `unemitColumnName` round trip; length limits (SQL Server 128).
4. Type mapping both ways: `sqlTypeName`, `sqlTypeId`, `sqlPrimT`/`defaultDecodeType`; what a
   `Double` becomes on each dialect (SQLite `REAL`, SQL Server `float`), `Int` vs `Long`,
   `Byte`/`Short`, nullable flags; what `SqlExecution` does when the driver reports a different
   type than the header says (`SqlExecution.scala:97` "Unexpected NULL").
5. Operators: integer division per dialect (`emitIntegerDivision`, `EmitIntDivOp_*`), `%`,
   string concatenation, comparison of mixed types, `LIKE` escaping, `IN` with an empty list,
   `NOT` and three-valued logic on nullable columns, `CASE`, `COALESCE`, stddev/variance
   (`SqlScanner.scala:141` says SQLite lacks them: with 3.51?), `emitNaryOp` for
   `UNION`/`EXCEPT`/`INTERSECT` and their `ALL` variants and distinctness semantics.
6. `emitLimit`/`implementLimit` per dialect: `OFFSET ... FETCH` needs an `ORDER BY` on SQL
   Server; what happens without one; LIMIT without ORDER BY as a "top N" is nondeterministic.
7. Anything in `TestSqlEmitters` that is commented out, weakened, or vacuous.

Method: read every emitter method against the SQLite 3.51 and SQL Server 2022 grammars you
know; for each suspect construct, dump the SQL through the REPL for both scanners and, for SQL
Server, execute the dumped text with `scripts/db.sh sql ErmineSales "<sql>"` to see whether
the server accepts it (read-only SELECTs against literal VALUES need no tables). For SQLite,
`python3 -c 'import sqlite3'` executes dumped text in memory (3.x version of python's sqlite may
differ from the bundled driver's: say which you used).

Deliver `tracker/sql-audit/FINDINGS-emitter.md`. Post each WRONG to the board as you find it.
