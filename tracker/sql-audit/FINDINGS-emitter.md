# FINDINGS-emitter: the SQL text each dialect emits (2026-09-26, 23:00-00:00)

Scope: `core/src/main/scala/com/clarifi/reporting/sql/*.scala`, `PrimExpr.scala`/`PrimT.scala` where they meet JDBC,
`TestSqlEmitters.scala`. Method: 114 relations dumped through both live scanners from the REPL
(`scratch-sql-audit/emitter/Probe.e`, `Probe2.e`; transcripts `probe.out`, `probe2.out`; the SQL per probe in
`sql/`, `sql2/`), every `_L` query executed on python's SQLite 3.45.1 and the load-bearing ones re-run on the
bundled sqlite-jdbc 3.51.1 (`java/SqlRun.java`, `java/DateRun.java`), every `_M` query executed on the live SQL
Server 2022 (`scripts/db.sh sql ErmineSales`). "MEASURED" = executed as stated; "READ" = reasoned from the code.
Line numbers are `SqlEmitter.scala` unless another file is named.

Counts: WRONG 13, FRAGILE 8, WASTE 3, NOTE 9. Only the SQLite (default runner) and SQL Server findings are
measured; MySQL/Postgres/Vertica findings are READ and have no oracle.

| id | severity | where | claim | repro | proposed fix | blast radius |
|---|---|---|---|---|---|---|
| E-1 | WRONG | SqlEmitter.scala:269-271, 676-683 | every window function on SQLite emits `TODO I don't yet know how to play ...` inside the SELECT -> syntax error | `rankWithin`, running/moving sums: `q_wrank_L`, `q_wsum_L`, `q_wnoord_L`, `q_wframe_L` all `near "I": syntax error` (MEASURED) | mix `EmitOver_UsingOver` into `SqliteEmitter` (+Postgres); add the missing space at :549 | SqliteEmitter, TestSqlEmitters "only MS emitters use literal over", sql-render.sh/tsql2sqlite.py notes |
| E-2 | WRONG | :276-278 | `tryCast` on SQLite emits `TODO I don't yet know how to write try_cast` -> syntax error | `q_trycast_L` (MEASURED) | SQLite: `CASE WHEN typeof(e) IN ('integer','real') THEN CAST(e AS T) WHEN e GLOB '*[^0-9.eE+-]*' OR e='' THEN NULL ELSE CAST(e AS T) END`; base class: `sys.error` instead of TODO text | CastSqlExpr emission (SqlExpr.scala:102) needs an emitter hook taking the whole expr |
| E-3 | WRONG | :699-701, SqlScanner.scala:107-110 | `dateAdd` on SQLite throws `todo - sqlite dateadd function`; `dateDiff` emits `datediff(day, a, b)` -> `no such column: day` | `q_dateadd_L` (REPL error), `q_datediff_L`, `q_datediff_month_L` (MEASURED) | new hooks `emitDateAdd`/`emitDateDiff`; SQLite: `unixepoch(d/1000,'unixepoch','+'||n||' days')*1000`, `cast(julianday(e/1000,'unixepoch')-julianday(s/1000,'unixepoch') as integer)` (verified) | SqlEmitter + SqlScanner:107-110 (lowering's file) |
| E-4 | WRONG | :328-348, SqlScanner.scala:141-143 | `stddev`/`variance` on SQLite -> `no such function: STDDEV_POP`/`VAR_POP` | `q_stddev_L`, `q_var_L` (MEASURED; also absent in sqlite-jdbc 3.51.1) | SQLite overrides: `sqrt(avg(x*x)-avg(x)*avg(x))`, `avg(x*x)-avg(x)*avg(x)` (sqrt verified on 3.51.1; 0.8165 matches STDEVP) | SqliteEmitter only |
| E-5 | WRONG | :38, :676 | SQLite never quotes column names: fields named `group`/`order`/`select`/`user` -> syntax error | `q_kw_L` (MEASURED); `q_kw_M` fine | `SqliteEmitter.emitColumnName = "\"" + s.replace("\"","\"\"") + "\""`; getColumnLabel returns the unquoted label (verified) | every SQLite query text; TestSqlEmitters `idq` hack; any fixture pinning SQLite SQL |
| E-6 | WRONG | :253-263, :676 | right-nested join on SQLite emits `A JOIN B JOIN C on (..) on (..)` -> syntax error | `join ja (join jb jc)`: `q_join_right_L` (MEASURED); SQL Server accepts | lift MySqlEmitter's :817-831 override to a trait; SQLite accepts `A JOIN (B JOIN C on ..) on ..` (verified 3.51.1) | SqliteEmitter |
| E-7 | WRONG | :516-521 | `limit o (Just n) Nothing` on SQLite emits `offset 1` with no LIMIT -> syntax error | `q_offset_L` (MEASURED) | SQLite: `limit -1 offset n` (verified); MySQL needs `limit 18446744073709551615 offset n`; Postgres fine | EmitLimit_AsLimit users |
| E-8 | WRONG | SqlExpr.scala:213 | SQL Server string literals lack the `N` prefix: every non-CP1252 char arrives as `?` | `unicode(substring('☺',1,1))` = 63, `N'☺'` = 9786, `'東'` = 63 (MEASURED, collation SQL_Latin1_General_CP1_CI_AS) | `emitString` hook; MsSql emits `N'...'` | SqlLiteral.emitSql; SQL Server fixtures pinning text; loads via setString are already Unicode, so today >100-row literals are right and <=100-row ones are wrong |
| E-9 | WRONG | :356, :676 | Double `//` on SQLite emits `/` -> `7.5 // 2.0` = 3.75 | `q_floordiv_L` 0.75/50.0/3.75 vs in-memory `floor(floor(x)/floor(y))` (PrimExpr.scala:197) and SQL Server 0/50/3 (MEASURED) | mix `EmitIntDivOp_MsSql` into SQLite: `floor(floor(a)/floor(b))` gives 3, -3, 3.0, -4.0 on SQLite (verified) | SqliteEmitter |
| E-10 | WRONG | SqlExpr.scala:217 | `NaN`/`Infinity` doubles are emitted verbatim -> invalid SQL on both | `relation [{xd = 0.0/0.0}]`: SQLite `no such column: Infinity`, SQL Server Msg 207 (MEASURED) | NaN -> `NULL` (SQLite stores NaN as NULL anyway); Infinity: SQLite `9e999`, SQL Server has no representation -> NULL or `sys.error` (orchestrator's call) | SqlLiteral.emitSql |
| E-11 | WRONG | :203-205, :696 | SQLite timestamp literals are TEXT `'yyyy-MM-dd HH:mm:ss.SSS'` while timestamp columns are INTEGER millis (loads use setTimestamp; `emitDate` is millis) -> TEXT vs INTEGER comparisons/joins wrong (INTEGER < TEXT always) | `q_ts_L` text (MEASURED); comparison outcome READ | `override def emitTimestamp(t) = t.getTime.toString` | SqliteEmitter |
| E-12 | WRONG | SqlExpr.scala:102-103, :716-727 | SQLite `cast s Date` -> `cast(s as integer)` = 2024; `cast d String` -> `'1705276800000'`; `cast d Int` -> millis (SQL Server: Msg 245) | `q_cast2_L`, `q_castdate_L`, `q_castdate_M` (MEASURED); in-memory gives `'2024-01-15'` via `PrimExprs.dateFormatter` | CastSqlExpr must carry the source PrimT (`Op.guessType`) so SQLite can emit `unixepoch(e)*1000` / `strftime('%Y-%m-%d', e/1000, 'unixepoch')` | SqlExpr, SqlScanner:117, emitter hook |
| E-13 | WRONG | :310-311, SqlExecution.scala:95-97 | `emitEmpty` emits untyped `(NULL) [xd]`: SUM/STDEVP over an empty relation fail on SQL Server (Msg 8117); on every dialect SUM over zero rows is NULL while the header is non-nullable -> `Unexpected NULL` sys.error | `q_sum_empty_M`, `q_stddev_empty_M` (MEASURED); `q_sum_empty_L` returns one NULL row (MEASURED), the sys.error path READ | emitter: `cast(NULL as <sqlTypeName>)` per column; lowering/oracle: `COALESCE(SUM(x),0)` or nullable header for aggregates over possibly-empty input | emitEmpty; Typer.aggregateType (handoff) |
| E-14 | WRONG (READ, no oracle) | :286-297, :912-919 | Vertica: `implementLimit`/`emitLimit` are the base no-ops -> `firstK`/`topK`/`limit` return ALL rows | READ | mix `ImplementLimit_AsLimit with EmitLimit_AsLimit` (Vertica supports LIMIT/OFFSET); untested live | VerticaSqlEmitter |
| F-1 | FRAGILE | :199-201, :860-862 | SQL Server date literal `'yyyy-MM-dd'` is converted through the login's language: under `SET LANGUAGE French`/`DATEFORMAT dmy` `dateadd(day,3,'2024-01-15')` -> Msg 242 | MEASURED; works today because `ermine` is us_english | `CAST('yyyy-MM-dd' AS DATE)` as the timestamp path already does | MsSqlEmitter.emitDate; SQL Server fixtures pinning text |
| F-2 | FRAGILE | :549 | `emitOver` glues the sort direction to the key: `[x]desc` | `q_wrank_M` (MEASURED, accepted only because of `]`) | `|+| " " |+|` | folds into E-1 |
| F-3 | FRAGILE | :318-322, :573-576 | `show`/`++` of a Double formats three ways: Scala `100.0`/`1.0E21`, SQLite `100.0`/`1.0e+21`, SQL Server CONCAT of float `100`/`1e+021` (decimal columns print `100.0`) | MEASURED (`q_show_*`, `concat(cast(100.0 as float))`) | differential-oracle target; SQL Server `FORMAT`/`STR` would cost more than it saves | none proposed |
| F-4 | FRAGILE | SqlExpr.scala:88 | `xd / 0.0`: SQLite NULL, SQL Server Msg 8134 (query dies), in-memory Infinity | MEASURED all three (`q_dbldiv_L`, live `1.5/0.0`) | document; or `NULLIF(b, 0)` divisor on SQL Server to match SQLite | DoubleDiv emission |
| F-5 | FRAGILE | :867, :1032 | `StringT(0)` -> `nvarchar(1000)`/`varchar(1000)`: `cast(x as nvarchar(1000))` truncates silently; temp-table loads of >1000-char strings fail "would be truncated" | READ | `nvarchar(max)` when `l == 0` | MsSql casts and CREATE TABLE text |
| F-6 | FRAGILE | :1013-1027, :881-885 | `defaultDecodeType` lacks `Types.NUMERIC` (mssql-jdbc reports `numeric` as 2) -> `SqlInspect` cannot type a numeric column; `uniqueidentifier` decodes as StringT not UuidT | READ | add NUMERIC to the DoubleT arm; MsSql `sqlPrimT`: `"uniqueidentifier" => UuidT()` | SqlInspect users |
| F-7 | FRAGILE (READ, no oracle) | :452-484 | MySQL/Vertica EXCEPT emulation: unquoted column names (`t0.<raw name>`), NULL keys never subtracted (join, not EXCEPT, semantics) | READ | use native EXCEPT (MySQL >= 8.0.31, Vertica); else `emitColumnName` + `<=>` | EmitNary_ExceptAsJoin |
| F-8 | FRAGILE | SqlEmitter.scala:1015-1026 | `T.DECIMAL -> DoubleT`: SQL Server `decimal(19,4)` money-like columns round through double | READ | NOTE for the DB programme; no PrimT for decimals exists | none |
| W-1 | WASTE | :306-307, :740-742, SqlScanner:947-948 | SQLite literals: per row `select * from (select (v) c, ...)` chained with UNION (a DISTINCT sort per step); SQLite >= 3.8.3 takes `select column1 k, column2 s from (values (..),(..))` (verified 3.51.1) | `q_union3_L` text vs `q_union3_M` (MEASURED) | `EmitLiteralTVC`-style override naming `columnN` | SQLite literal text; N-6 cap disappears |
| W-2 | WASTE | SqlExecution.scala:78-94 | per CELL per ROW: `md.getColumnLabel`, `unemitColumnName`, `h(columnName)` and the type match; sqlite-jdbc's label call is native | READ; tier l = 2 M rows x ~10 cols = 20 M metadata calls | precompute `Array[(Int, PrimT)]` once in `setup` | SqlExecution |
| W-3 | WASTE | :431-433, :834-836, SqlScanner.scala:266-274 | SQL Server `##t...` temp tables from >100-row literals are never dropped (`EmitNoDropTempTable`), accumulate in tempdb for the preview's held connection | READ | `EmitDropTempTable_AsDropTable` for MsSql (`drop table ##x` is transaction-safe) | MsSqlEmitter; SqlScanner.cleanTempTables already handles it |
| N-1 | NOTE | TestSqlEmitters.scala | (a) "only MS emitters use literal over" pins the E-1 stub; (b) joinOn generator :80-81 references `left.alias` on both sides, never a right-table column; (c) "sqlite literal syntax valid" only `explain`s; (d) "stays more or less the same" hard-codes no quoting for SQLite/Vertica (E-5); nothing covers limits, strings/dates/NULL literals, casts, frames, EXCEPT, or execution on SQL Server | READ | rewrite with E-1/E-5; add an execution property per dialect | tests only |
| N-2 | NOTE | Relation/Op.e:91 | `(%)` is `a - (b * (a // b))`; SQL `%` is never emitted; inherits E-9 on SQLite | READ | none | none |
| N-3 | NOTE | Relation/Op.e:113 | `negate` is `prim (Some 0.0) - x`: typed `Nullable Double` only | READ (probe had to avoid it) | surface change, out of scope | none |
| N-4 | NOTE | SqlQuery.scala:65-70, :297 | `SqlLimit(None,None)` emits `emitLimit(Some(1),None)` = bare `offset 0` on SQLite; unreachable today (`limit` returns `this` for (1, None)) | READ | keep in mind for E-7 | none |
| N-5 | NOTE | :538-568 | a frame `F (Bounded 2) (Bounded 0)` emits `2 following and current row` -> SQL Server Msg 4193; the convention is negative = preceding (Helpers.e:156 `Bounded (1 - n)`), so it is user error passed through | `q_wsum_M` (MEASURED); `Bounded (-2)` correct (`q_wframe_M`) | `sys.error` when begin > end, as :555 does for frames without order | EmitOver_UsingOver |
| N-6 | NOTE | SqlScanner.scala:947 | SQLite's compound-select cap is 500 terms (501-term UNION fails, 499 ok; MEASURED python 3.45.1): the <=100-row literal path is safe; `unionAll` of >500 relations is not | MEASURED | W-1 removes literals from the count | none |
| N-7 | NOTE | SqlExecution.scala:164 | the `emitBoolean(stmt,..)` hook is unused; `setBoolean` is called directly (fine on both live drivers) | READ | none | none |
| N-8 | NOTE | :655-671 | SQL Server `values` derived tables take >1000 rows (1001 MEASURED) and all-NULL columns (MEASURED): no issue | MEASURED | none | none |
| N-9 | NOTE | SqlExecution.scala:84 | sqlite-jdbc `getDate(i, GMT)` returns exact millis for INTEGER (1705276800000 MEASURED) and throws `Error parsing time stamp` on TEXT `'2024-01-15'`: every SQLite date fix must yield INTEGER millis, never `date()` text | MEASURED (`java/DateRun.java`) | design constraint for E-3/E-12 | none |

## E-1 window functions on SQLite (the default runner)

`SqlEmitter.emitOver` (:269) formats a debug string and every emitter but `MsSqlEmitter` uses it. The scanner
puts window functions into the SELECT list (SqlScanner:115), so the text is spliced into the query:

```
select (t949248.k) k, ..., (TODO I don't yet know how to play RawSql(Vector(RANK, (, , ))) over SqlOver(...)) y from ...
```

MEASURED on python SQLite: `near "I": syntax error` for `rankWithin` (`q_wrank_L`), a framed running sum
(`q_wsum_L`, `q_wframe_L`) and an unordered partition sum (`q_wnoord_L`). Every `Wide/Helpers.e` window
helper and every report using them fails in the preview and in `TestRunner` unless dumped through SQL Server;
`tracker/tools/sql-render.sh` works around it by rewriting T-SQL for SQLite.

SQLite has had window functions since 3.25; the bundled driver is 3.51.1. The `EmitOver_UsingOver` output was
executed on sqlite-jdbc 3.51.1 (`java/SqlRun.java`): `RANK() over (partition by t.k order by t.x desc)` gives
(1,2,1),(1,1,2),(2,3,1) and `SUM(x) over (order by x rows between 2 preceding and current row)` gives 1,3,6,
identical to SQL Server's rows for `q_wrank_M`/`q_wframe_M`. Two things to change: mix `EmitOver_UsingOver` into
`SqliteEmitter` (and `PostgreSqlEmitter`; MySQL 8 and Vertica also take the syntax, untested), and put a space
between the key and its direction at :549 (`e.emitSql(this) |+| " " |+| o.emitSql`), which SQL Server only
tolerates because every key ends in `]` (F-2). `TestSqlEmitters` "only MS emitters use literal `over'" then
inverts. Cost on the Sales corpus: zero rows change; windows move from "impossible" to "in the database".

## E-2 tryCast on SQLite

`emitTryCast(true)` (:276) returns the string `TODO I don't yet know how to write try_cast` for every emitter but
MS SQL, and `CastSqlExpr.emitSql` (SqlExpr.scala:102) concatenates it: `(TODO I don't yet know how to write
try_castt817152.s as real)) n` (`q_trycast_L`, MEASURED syntax error). SQLite has no TRY_CAST and `CAST('abc' AS
REAL)` is 0.0, not NULL, so the emulation must test the text:

```
CASE WHEN typeof(e) IN ('integer','real') THEN CAST(e AS real)
     WHEN CAST(e AS text) GLOB '*[^0-9.eE+-]*' OR e = '' THEN NULL
     ELSE CAST(e AS real) END
```

(the `iif` form of this was executed on python 3.45.1: `'abc'` -> NULL, `'12'` -> 12.0, `'1.5'` -> 1.5). That
needs the whole expression, so `emitTryCast(nullIfFail): RawSql` should become `emitCast(e, ty, nullIfFail):
RawSql`. For text targets a plain cast suffices; for date targets see E-12. The base class should `sys.error`
rather than emit TODO text: an exception names the feature, a driver syntax error does not.

## E-3 dateAdd / dateDiff on SQLite

`SqliteEmitter.emitDateAddName` and `emitInterval` are `sys.error("todo - sqlite dateadd function")` (:699-701);
`dateAdd 3 days d` fails at dump time (REPL: `<error: todo - sqlite dateadd function>`, `q_dateadd_L`).
`dateDiff` has no emitter hook at all: SqlScanner:110 builds `FunSqlExpr("datediff", List(Verbatim(unit), s, e))`
for every dialect, which is T-SQL; SQLite answers `no such column: day` (`q_datediff_L`, `_month_L`, MEASURED).
SQLite dates are epoch millis INTEGERs (`emitDate` = `d.getTime`, `sqlTypeName(DateT)` = integer, and N-9 says
they must stay so). Verified on 3.51.1 and 3.45.1:

```
unixepoch(d/1000, 'unixepoch', '+3 days') * 1000                       -- 1705276800000 -> 1705536000000 (2024-01-18)
cast((julianday(e/1000,'unixepoch') - julianday(s/1000,'unixepoch')) as integer)   -- 2024-01-15 .. 2024-03-01 = 46
```

`unixepoch()` exists since 3.38; the modifier may be an expression (`'+' || (n) || ' days'`). Units: Millisecond
`d + n`, Second `d + n*1000`, Day `'+n days'`, Week `'+' || 7*n || ' days'`, Month `'+n months'`, Year
`'+n years'`. DATEDIFF counts boundaries crossed (SQL Server: 2024-01-15 -> 2024-03-01 is 2 months, 2011-03-13 ->
03-14 is 1 day, MEASURED), so Month = `(strftime('%Y',e)-strftime('%Y',s))*12 + (strftime('%m',e)-strftime('%m',s))`
on the `/1000,'unixepoch'` forms, Year likewise, Week = Day/7 (T-SQL counts week boundaries, Sunday-based; say so).
The in-memory evaluator only supports Millisecond for DateDiff (Op.scala:38-41), so this is SQL-only anyway.
Proposed shape: `emitDateAdd(d: SqlExpr, n: SqlExpr, u: TimeUnit): SqlExpr` and `emitDateDiff(u, s, e): SqlExpr`
on `SqlEmitter` with today's text as the defaults; SqlScanner:107-110 calls them. That is one line in the
lowering role's file.

## E-4 stddev / variance on SQLite

`STDDEV_POP`/`VAR_POP` are not SQLite functions (MEASURED on 3.45.1: `no such function: STDDEV_POP`; the
3.51.1 driver has none either, they live only in the `extension-functions` add-on). SqlScanner:141 already knew
("SQLite does not support STDDEV or VAR"). `sqrt`, `power`, `log`, `log10`, `exp` ARE compiled into sqlite-jdbc
3.51.1 (MEASURED `java/SqlRun.java` "math"), so population forms are one override each:
`sqrt(avg(x*x) - avg(x)*avg(x))` = 0.8164965809277263 on SQLite for 1.5/2.5/3.5, SQL Server STDEVP = 0.816496580927726.
The `_SAMP` variants (unused by the scanner) multiply by `count(x)/(count(x)-1.0)`. Note the one-pass form loses
precision when the mean dwarfs the spread (catastrophic cancellation); acceptable for report data, say so in the
scaladoc.

## E-5 keyword column names on SQLite

`SqliteEmitter` inherits `emitColumnName(s) = s` (:38). `field order, select, group, user : Int` is a legal
Ermine declaration; the SQLite text `select (3) group, (1) order, (2) select, (4) user` is a syntax error
(`q_kw_L`, MEASURED) while SQL Server's `[group]` works (`q_kw_M`). Fix: double-quote with `""` escaping;
sqlite-jdbc's `getColumnLabel` returns the bare label for `select (3) "group"` (MEASURED: labels
group/order/select/user), so `unemitColumnName` stays the identity and `SqlExecution.keyCache` is unaffected.
Blast: every SQLite query text changes, `TestSqlEmitters` "stays more or less the same" sets `idq = ""` for
SQLite and must use `"` instead; any fixture that pins SQLite text (none found under `core/src/test/resources`,
the `(fx4-sql)` pin is SQL Server text).

## E-6 right-nested joins on SQLite

`emitJoinOn` (:261) emits both operands bare, so `join ja (join jb jc)` is `A JOIN B JOIN C on (c2) on (c3)`,
which SQL Server re-associates (SQL-92) and SQLite rejects (`near "on": syntax error`, `q_join_right_L`,
MEASURED; the left-deep `q_join_left_L` is fine). `MySqlEmitter` already overrides `emitJoinOn` to parenthesise
an `r2` that is a `SqlJoinOn` (:817-831); SQLite accepts exactly that text (MEASURED 3.51.1 "parenjoin").
Lift the override into a trait and mix it into SQLite. `sql-render.sh`'s header documents this defect.

## E-7 offset without a bound on SQLite

`EmitLimit_AsLimit` (:518) emits ` offset %d` alone for `(Some(x), None)`; SQLite's grammar requires LIMIT
before OFFSET (`q_offset_L`, MEASURED syntax error). `limit -1 offset 1` is the SQLite idiom (MEASURED 3.51.1).
MySQL has the same rule with `18446744073709551615` as the sentinel; Postgres accepts bare OFFSET. Make the
unbounded case a per-dialect hook. `limit (ordering {x}) (Just 2) (Just 3)`, `firstK`, `topK` and the one-row
case are all correct on both live dialects (`q_range_*`, `q_first_*`, `q_top_*`, `q_onerow_*`, MEASURED).

## E-8 SQL Server string literals without N

Board entry 23:14. `SqlString.emitSql` (SqlExpr.scala:213) is `'...'` for every dialect. On SQL Server a
non-`N` literal is converted through the database collation's code page (ErmineSales is
`SQL_Latin1_General_CP1_CI_AS`, CP1252), so `select unicode(substring('☺',1,1))` = 63 (`?`), `N'☺'` = 9786,
`'東'` = 63 (MEASURED). `q_lit_str_M` shows `uni ? ??`. Any relation literal, filter constant or join key with
CJK, emoji, Cyrillic, etc. is silently corrupted; a join against a real nvarchar column then matches nothing.
Loads go through `setString` (SqlExecution:163) and mssql-jdbc sends those as nvarchar, so a >100-row literal
(temp-table path, SqlScanner:947) is correct while a <=100-row one is wrong. Fix: an `emitString(s): RawSql`
hook on `SqlEmitter`; `MsSqlEmitter` prefixes `N`. Blast: SQL Server fixtures that pin text containing strings.

## E-9 floor division of doubles on SQLite

`emitIntegerDivision` default is plain `/` (:356). Scala `floordiv` (PrimExpr.scala:197) is
`math.floor(math.floor(x) / math.floor(y))` for doubles and truncating `/` for integers; SQL Server emits
`floor(floor(a)/floor(b))`. `xd // 2.0` for 1.5/100.0/7.5: SQLite 0.75/50.0/3.75, SQL Server 0/50/3, in-memory
0.0/50.0/3.0 (`q_floordiv_*`, MEASURED). `floor(int)` stays INTEGER on SQLite, so mixing `EmitIntDivOp_MsSql`
into SQLite gives 3 (7//2), -3 (-7//2, matching Scala's truncation), 3.0 (7.5//2.0), -4.0 (-7.5//2.0, matching
`floor(-8/2)`) (MEASURED 3.45.1). `(%)` (N-2) inherits the fix.

## E-10 NaN and Infinity

`SqlDouble(d).emitSql` is `d.toString` (SqlExpr.scala:217): `relation [{xd = 0.0/0.0}, {xd = 1.0/0.0}]` emits
`(NaN)`, `(Infinity)` -> SQLite `no such column: Infinity`, SQL Server `Invalid column name 'NaN'`
(`q_nan_*`, MEASURED). A NaN reaches a literal whenever a ratio is computed in Ermine before `relation`. Neither
engine can store NaN (SQLite converts it to NULL); SQL Server `float` has no infinity, SQLite accepts `9e999`.
Proposal: NaN -> `NULL`; +/-Infinity -> `9e999`/`-9e999` on SQLite, and on SQL Server either NULL (silent) or
`sys.error("SQL Server cannot represent Infinity")`. Orchestrator's call. Related F-4: `xd / 0.0` is NULL on
SQLite, an error (Msg 8134) on SQL Server and Infinity in memory, so the same report can differ three ways.

## E-11 SQLite timestamp literals are text

`SqliteEmitter` overrides `emitDate` to millis (:696) but not `emitTimestamp`, so a `Timestamp` literal is
`'2024-01-15 10:11:12.123'` (`q_ts_L`, MEASURED) while `sqlTypeName(TimestampT)` is `integer` and
`bulkLoad`/`setTimestamp` store INTEGER millis (sqlite-jdbc default `DateClass=INTEGER`; `getTimestamp` reads
both forms, MEASURED `java/DateRun.java`). Reading the literal back therefore works, which hides the defect;
comparing, joining or ordering it against a loaded timestamp column compares TEXT with INTEGER, and SQLite's
type ordering puts every INTEGER below every TEXT. READ for the wrong rows (no timestamp column was loaded in
this audit), MEASURED for the text. Fix: `override def emitTimestamp(t) = t.getTime.toString`. SQL Server's
`CAST('...' AS DATETIME2)` is right (`q_ts_M`: `2024-01-15 10:11:12.1230000`).

## E-12 casts to and from dates on SQLite

`CastSqlExpr` carries only the target type, and SQLite's target names are storage classes: `cast s Date` ->
`cast(s as integer)` = 2024 for `'2024-01-15'` (`q_cast2_L`), which `getDate` reads as 2024 ms = 1970-01-01
(N-9); `cast d String` -> `cast(d as text)` = `'1705276800000'` (`q_castdate_L`) where memory gives
`PrimExprs.dateFormatter` text and SQL Server gives `2024-01-15` (`q_castdate_M` first column); `cast d Int` ->
millis on SQLite, Msg 245 on SQL Server, `extractInt` in memory (MEASURED / READ as marked). Fix needs the
source type on `CastSqlExpr` (`Op.guessType` is available at SqlScanner:117): text->Date =
`unixepoch(e)*1000`, Date->text = `strftime('%Y-%m-%d', e/1000, 'unixepoch')`, Date->Int = error or millis by
decision. Lower priority than E-1..E-9: the probes are the only known users.

## E-13 aggregates over an empty relation

`emitEmpty` (:310) is `select (NULL) [x], (NULL) [xd] where ('A' = 'B')`. SQL Server refuses to aggregate an
untyped NULL: `SUM` -> Msg 8117 "Operand data type NULL is invalid for sum operator", `STDEVP` likewise
(`q_sum_empty_M`, `q_stddev_empty_M`, MEASURED). SQLite returns one NULL row (`q_sum_empty_L`, MEASURED). Fix in
the emitter: `emitEmpty` has the header, so emit `cast(NULL as float) [xd]` (SQL Server takes it; SQLite takes
`cast(NULL as real)`). The follow-on is not the emitter's: `Typer.aggregateType` (Typer.scala:84-89) types the
result as the declared field type, non-nullable for `field xd : Double`, and SUM/AVG/STDDEV over zero rows is
NULL in every SQL dialect, so `SqlExecution.scala:95-97` raises `Unexpected NULL in field of type
DoubleT(false)` (READ; no runner in an auditor's toolbox). That case is not exotic: `sumBy amount (filter p r)`
where `p` matches nothing. Handoff to lowering/oracle: `COALESCE(SUM(x), 0)` for Sum/WMean (what does `Mem`'s
fold return for an empty group?), nullable results for Avg/Stddev/Variance, or a typed NULL plus a nullable
header.

## E-14 Vertica limits (READ)

`VerticaSqlEmitter` (:912) mixes in neither `ImplementLimit_AsLimit` nor `EmitLimit_AsLimit`; the base
`implementLimit` answers the query unchanged (:286-291, "for implementations with no support") and `emitLimit`
is `""`. So `firstK 5 r` on Vertica scans and returns every row, silently. Vertica documents LIMIT/OFFSET, so
the two MySQL/Postgres traits fit; untested live.

## F-1 SQL Server date literals and the session language

`emitDate` (:199) emits `'2024-01-15'`; a varchar->datetime conversion in T-SQL depends on `SET LANGUAGE` /
`SET DATEFORMAT`. MEASURED: `set language french; select dateadd(day, 3, '2024-01-15')` -> Msg 242 "La
conversion ... a créé une valeur hors limites"; `set dateformat dmy` likewise. It works today because the
`ermine` login is us_english. `date` and `datetime2` parse ISO 8601 independently of language, so emit
`CAST('2024-01-15' AS DATE)`, exactly as `MsSqlEmitter.emitTimestamp` (:860) already casts to DATETIME2.
Blast: SQL Server fixtures pinning text with dates.

## W-2 per-cell metadata calls

`nextRecord` (SqlExecution.scala:77-99) runs `md.getColumnLabel(x)`, `emitter.unemitColumnName`, `h(columnName)`
and a type `match` for every cell of every row although none of it changes between rows; `keyCache` shows the
authors knew. At tier l (2,052,515 fact rows, ~10 columns) that is ~20 M `getColumnLabel` calls per full scan;
sqlite-jdbc answers each from native `sqlite3_column_name`, mssql-jdbc from an array. Precompute
`Array[(String, PrimT)]` in `setup`. READ; the perf harness can put a number on it.

## W-3 SQL Server temp tables never dropped

`MsSqlEmitter` mixes in `EmitNoDropTempTable`, so `cleanTempTables` (SqlScanner.scala:266) is a no-op and each
>100-row literal leaves a global `##t<guid>` table in tempdb for the connection's lifetime; the preview holds
one connection per profile for as long as the panel lives. `DROP TABLE ##x` is transaction-safe on SQL Server,
so `EmitDropTempTable_AsDropTable` applies. READ; `select name from tempdb.sys.tables` after a preview session
would measure it.

## Notes on what was checked and found correct (MEASURED, both dialects)

Booleans as 1/0; embedded quotes and backslashes in strings; longs to +/-2^63-1 (Long.MinValue itself is an
Ermine lexer limit, not the emitter's); `0.1`, `1e21`, `1e-7`; NULL literals (typed and untyped) in TVCs; the
empty relation; single-row literals (squashed into the joined select: `q_join1_*`); UNION of two and three
relations; EXCEPT (SQL Server native, SQLite via the wrapped form) including a NULL-bearing row; DISTINCT
projection; `if` chains as CASE; COALESCE; UPPER/REPLACE/POWER/LOG/ABS; comparisons with NOT/AND/OR; IS NULL;
GROUP BY sums and weighted means; COUNT(*); all four limit shapes except the unbounded offset; left join with
`coalesce` defaults; SQL Server window functions with proper frames; SQL Server `dateadd`/`datediff` for day and
month; `values` with 1001 rows and with all-NULL columns.
