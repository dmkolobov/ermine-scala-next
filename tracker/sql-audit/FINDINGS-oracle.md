# SQL audit findings: role `oracle` (2026-09-26/27)

The instrument: `scalacheck-binding/src/main/scala/TestSqlDifferential.scala`, two suites.
`TestSqlDifferential` (in-memory SQLite, always registered, runs in `suites`) and
`TestSqlDifferentialDb` (the live SQL Server, registered only with `ERMINE_DB_*` in the
environment; added to the `db` gate's `testOnly` list in `scripts/gates.sh`). Random
`Relation` trees over typed literals (0-8 rows, 1-4 columns of Int/Double/String/Boolean/Date,
nullable and not), depth 1-4, evaluated by a reference interpreter in the test file (sets;
SQL three-valued logic; aggregates ignore NULL; an ungrouped aggregate over no rows is one
row, a grouped one none; expressions delegate to `Op.eval` node by node with NULL propagated
first) and by `SqlScanner.scanRel`; rows compared as multisets after normalisation (doubles to
9 digits, dates to epoch days, every NULL alike); every scan also asserts no `TODO` in the SQL
and the header's columns. Every disagreement class below was found by the random property,
shrunk by ScalaCheck to the relation shown, then EXCLUDED from the generator under a named
flag and PINNED as a named property that runs only under the same flag
(`-Dermine.test.sqldiff.<flag>=true`). The generator has a PROFILE per backend
(`SqlDifferential.Profile`): a class the backend does not exhibit stays enabled for it, so
the SQLite half keeps decimal arithmetic, nested set operations, duplicate literals, empty
aggregates, duplicate ORDER BY expressions and NULL substitution, and the SQL Server half
keeps keyword names, offset-only limits, right-nested joins and concat over NULL. The random
property is green on this tree on both backends and every exclusion is a ticket: the
implementer removes the exclusion (`on("<flag>")` sites in `SqlDifferential.Gens`) together
with the fix and keeps the pin. MEASURED = rows produced by the named backend in this session
(log under `scratch-sql-audit/logs/`); READ = reasoned from the code. The last column of the
matrix below is the pin's verdict with its flag on, per backend (`oracle-pins-sqlite.log`,
`oracle-pins-mssql.log`): FAIL = the finding reproduces there, ok = that backend does not
exhibit it.

Ranking: WRONG first (by how plausible the report shape is), then FRAGILE, WASTE, NOTE.

| id | severity | where (file:line) | one-line claim | repro | proposed fix | blast radius | pin: sqlite / mssql |
|---|---|---|---|---|---|---|---|
| O-1 | WRONG | `relational/Rel.scala:114,115,118` (`JoinOn.bimap/subst/unquote`), `Optimizer.scala:381,385` (`fromScope`/`toScope`), `Lib.scala:845,868` (`unquoteR`) | every `map`/`subst`/`unquote` rebuilds `JoinOn(fst, snd, cs)` WITHOUT `mode`: an outer join inside a `LetR` body compiles as an inner join | §O-1, MEASURED SQLite | pass `mode` in the three rebuilds | every `letR`/`materialize`/`letRWithPK` body holding an outer join (optimizer, lowering and surface measured it from the surface) | FAIL / FAIL |
| O-8 | WRONG | `sql/SqlEmitter.scala:253` `emitJoinOn` (every dialect but MySQL, whose `:818` override parenthesises), `SqlScanner.scala:1133-1160` `joinOn` | a join whose RIGHT operand is a join source is emitted `A JOIN B JOIN C on (..) on (..)`, right-nested, no parentheses; SQLite rejects it | §O-8, MEASURED SQLite | parenthesise a `SqlJoinOn` right operand as MySQL's does, or have `joinOn` wrap a join-shaped right side in a subquery | `join a (join b c)` with non-trivial sides on the default (SQLite) preview runner; SQL Server accepts the form | FAIL* / ok |
| O-10 | WRONG | `relational/SqlScanner.scala:1133-1160` `joinOn` (the `asSelect` conditions) | the side of an outer join that can be unmatched keeps its computed columns INLINED in the join's select list, so they are re-evaluated over NULLs instead of being NULL | §O-10, MEASURED SQLite | for `Left`/`Right`/`Full` wrap a side whose attrs are not all `ColumnSqlExpr` in a subquery, as is done for a side with a `where` | `unsafeLeftJoin`/`unsafeFullJoin` over a projected or combined relation (optimizer's `unsafeLeftJoin t1 ([\| c = 1 \|] t2)` is the same mechanism) | FAIL / FAIL |
| O-14 | WRONG | `relational/SqlScanner.scala:796-814` `preservesDistinctness`/`columnDistinctness` | any op over ONE column plus constants is taken as injective, so a projection through `coalesce`/`if`/`upper`/`lower`/`abs`/`floorDiv`/`x*0` skips DISTINCT and delivers duplicate rows | §O-14, MEASURED SQLite | `columnDistinctness` true only for `ColumnValue`, `Add`/`Sub` with a constant, `DoubleDiv` by a non-zero constant, `Concat` of the column with constants; false otherwise (the `@todo SMRC` at :798 already says it answers true too often) | every `project`/`combine` whose new column is a non-injective function of a column that is dropped | FAIL / FAIL |
| O-15 | WRONG | `sql/SqlQuery.scala:29` (`groupBy.filter(!_.isConstant)`), `SqlScanner.scala:1104,1126-1131` (one-row-literal squash) | a GROUP BY whose expressions are all constants at the select level is dropped, so a grouped aggregate over NO rows answers ONE row instead of none | §O-15, MEASURED SQLite | when every group expression is constant emit `having count(*) > 0`; or do not squash a one-row literal under an aggregate | `groupBy {k} (filterEq k v r)` / `groupBy {k} (join (relation [{k = v}]) r)` with no matching rows: a phantom row of NULL aggregates | FAIL / FAIL |
| O-28 | WRONG | `relational/SqlScanner.scala:1163` `joinOn` (`satisfyDistinct(d1 && d2, ..)`) | a FULL JOIN over a nullable key: the left-only and right-only rows coalesce to equal rows, the join claims distinctness, duplicates come out | §O-28, MEASURED SQLite | `d1 && d2 && mode != JoinMode.Full` (or `&&` no nullable key column) | `unsafeFullJoin` on a nullable key column | FAIL / FAIL |
| O-26 | WRONG | `relational/SqlScanner.scala:1257` `limit` (`isOneRow`, `q(!isOneRow)`) | `Limit(from = to > 1)` takes the one-row shortcut and skips DISTINCT on its input, so it delivers row #from of the NON-deduplicated stream | §O-26, MEASURED SQLite | `q(fromn > 1 \|\| !isOneRow)`: the shortcut is sound for `from == 1` only | `limit o (Just n) (Just n)` for n > 1 over a projection | FAIL / FAIL |
| O-13 | WRONG | `relational/SqlScanner.scala:912` `Limit` (`t-f < 2`) | a two-row inclusive range is taken for one row, `nrx` says all constant, the projection above skips DISTINCT: duplicates | §O-13 (lowering's; reproduced by the random generator), MEASURED SQLite | `t - f < 1` | `project` over `limit o (Just n) (Just (n+1))` | FAIL / FAIL |
| O-9 | WRONG | `relational/SqlScanner.scala:1207-1218` `project` over an `isAggregated` select | a projection over an ungrouped aggregate that keeps none of its columns copies the attrs over the aggregate select: the aggregate is lost, no rows where one row is due | §O-9, MEASURED SQLite | `project`/`except` wrap an aggregated select in a subquery unless a kept op references an aggregate column | rare: `project {const} (aggregate ..)` | FAIL / FAIL |
| O-16 | WRONG | `relational/SqlScanner.scala:93-104` `compileOp` CASE merging (`:98` prepends `Not(test)`) | `If(p, If(q, a, b), c)` merges to `case when not(p) then c when q then a else b end`; with `p` UNKNOWN `not(p)` is UNKNOWN and the row falls to the inner clauses instead of `c` | §O-16 (optimizer's; reproduced), MEASURED SQLite | merge only when the ALTERNATE is a CASE (sound); never prepend `not(test)` | nested `if` over a nullable column | FAIL / FAIL |
| O-11 | WRONG (edge) | `ReportingUtils.scala:42` `simplifyPredicate` (`Eq(l, r) if l === r => Atom(true)`) | `x = x` is rewritten to TRUE; in SQL it is UNKNOWN when `x` is NULL | §O-11, MEASURED SQLite (also reached through `Op.simplify` folding `if true then x else x`) | rewrite to `Not(IsNull(l))` when `l`'s type is nullable, `Atom(true)` otherwise | a self-comparison written by a user or produced by simplification | FAIL / FAIL |
| O-23 | WRONG / decision | `PrimExpr.scala:641` (`PrimExprOrder` lower-cases), `ReportingUtils.scala:42`, `Op.simplify` | string equality is case-insensitive in memory AND in every constant fold the compiler performs (`Eq(upper(sa), sa)` over a one-row literal folds to TRUE), byte-wise on SQLite, collation-bound on SQL Server | §O-23, MEASURED SQL Server (READ for SQLite: the same fold) | decide Ermine's string equality; if case-sensitive, `PrimExprOrder` compares bytes and `Record` dedupe follows | filters/joins on string columns that differ in case only; `uniqSorted`/`hashJoin` keys | FAIL / FAIL |
| O-2 | WRONG | `relational/SqlScanner.scala:1068-1070` `DistinctiveQuery.literal` (`(true, ..)`), `SqlEmitter.scala:658` `EmitLiteralTVC` | a literal with duplicate rows claims distinctness; on SQL Server the TVC keeps the duplicates (SQLite's union-of-selects dedupes by accident) | §O-2, MEASURED SQL Server | `literal` answers `(ts.list.toList.distinct.size == ts.size, ..)` | `relation [..]` with repeated rows on SQL Server | ok / FAIL |
| O-22 | WRONG | `sql/SqlEmitter.scala:310` `emitEmpty`, `SqlExpr.scala:165` `compileLiteral` (`NullExpr` -> bare `NULL`), `:658` `EmitLiteralTVC` | an empty relation (and an all-NULL literal column) is emitted as UNTYPED NULLs; SQL Server infers the NULL type through derived tables and rejects MAX/MIN/SUM/AVG over it ("Operand data type NULL is invalid for max operator") | §O-22, MEASURED SQL Server | `CAST(NULL AS <sqlTypeName(t)>)` for `NullExpr(t)` and in `emitEmpty` (the header is at hand) | `relationWithHeader h []` under `maxBy`/`minBy`/`sumBy`/`meanBy`; a `Limit` with `to < from`; a literal whose column is all NULL | ok / FAIL |
| O-24 | WRONG | `sql/SqlQuery.scala:83-84` `orderBy` (a `SqlSelect` orders by its attrs' EXPRESSIONS) | two columns with the same expression (two `SUM inl`, or `{b = a}` kept beside `a`) make a `Limit` order by the expression twice; SQL Server rejects "column specified more than once in the order by list" | §O-24, MEASURED SQL Server | order by ALIAS (`SqlOrderBy` with column names; SQL Server allows select-list aliases in ORDER BY), or dedupe by expression ignoring direction | a limit ordering by two columns that share an expression | ok / FAIL |
| O-27 | WRONG | `sql/SqlQuery.scala:83-84` `orderBy` (same root as O-24), `SqlEmitter.scala:310` | a `Limit` ordering by an expression over an empty relation's constant NULL columns: SQL Server folds it and rejects "A constant expression was encountered in the ORDER BY list" | §O-27, MEASURED SQL Server | order by alias (fixes O-24 too) | `limit` ordered by a computed column over `relationWithHeader h []` or a one-row literal | ok / FAIL |
| O-25 | WRONG | `ReportingUtils.scala:33-35` `simplEnv` (substitutes `NullExpr` constants), `SqlScanner.scala:884` (`simplifyPredicate(pred, rx)`) | a one-row literal's NULL is substituted into the filter as an untyped NULL literal; SQL Server rejects a CASE whose results are all the NULL constant | §O-25, MEASURED SQL Server | skip `NullExpr` in `simplEnv`, or emit `CAST(NULL AS type)` (O-22's fix) | a filter with an `if` over a one-row relation with a NULL cell | ok / FAIL |
| O-21 | WRONG | `sql/SqlExpr.scala:217` (`SqlDouble(d) => d.toString`) | a double literal without an exponent is DECIMAL on SQL Server: `1.0 / 3.0` answers `0.333333`, and a UNION of a literal double column (scale 2) with a `SUM` over decimals (precision 38) drops the scale: `2.25` comes back `2.3` | §O-21, MEASURED SQL Server | emit `3.0E0` (float) or `CAST(.. AS float)` for `SqlDouble` on MsSql | relation literals with doubles; constants in divisions; unions of literal doubles with aggregates | ok / FAIL |
| O-12 | WRONG | `sql/SqlEmitter.scala:237` `emitNaryOp` (default; SQLite's `:740` override wraps each arm) | nested set operations emit without parentheses and T-SQL evaluates left to right: `A UNION (B EXCEPT C)` is emitted `A UNION B EXCEPT C` | §O-12 (lowering's, live SQL Server), pinned here | parenthesise arms that are themselves `SqlNaryOp`s in the default emitter | every nested set expression on SQL Server/Postgres/Vertica | ok / FAIL |
| O-7 | WRONG | `sql/SqlEmitter.scala:518` `EmitLimit_AsLimit` | `Limit(r, Some(n), None, _)` emits ` offset n-1` with no LIMIT; SQLite (and MySQL) reject OFFSET without LIMIT | §O-7 (also lowering/surface), MEASURED SQLite | `" limit -1 offset %d"` for SQLite; MySQL needs `limit 18446744073709551615 offset n` | `limit o (Just n) Nothing r` on SQLite/MySQL (`Lib.scala:538`) | FAIL / ok |
| O-5 | WRONG | `Op.scala:28` (`Concat`: NULL is `""`), `Op.scala:186` (`guessType` non-null), `SqlEmitter.scala:322` (`\|\|`) | `concat` over a nullable string is NULL on SQLite (`\|\|`), `""` on SQL Server (`CONCAT`) and in memory; the header types it non-null so the SQLite scan throws `Unexpected NULL` | §O-5 (also surface), READ + pinned, MEASURED by the pin on SQLite | emit `coalesce(x, '')` around nullable operands of `\|\|` so all three agree on `""` | string building over nullable columns on the default runner | FAIL / ok |
| O-3 | WRONG | `relational/Typer.scala:102-111` `joinType` (header = `left ++ right`) | an outer join's header does not widen the unmatched side to nullable; the first unmatched row throws `Unexpected NULL in field of type DoubleT(false)` in `SqlExecution.nextRecord` | §O-3, READ + pinned, MEASURED by the pin on both | `joinType` answers `withNull` for the non-key columns of the nullable side(s) (the generator's `widen` does exactly this to keep running) | any `unsafeLeftJoin` etc. whose outer side has a non-nullable column and an unmatched row | FAIL / FAIL |
| O-4 | WRONG / decision | `AggFunc.scala:107` (`reduce` over no rows = monoid zero), `SqlScanner.scala:896-899` | SUM/AVG/MIN/MAX over NO rows is NULL in SQL and the attribute is typed non-null, so the scan throws `Unexpected NULL`; the Mem path answers 0 for SUM | §O-4 (also lowering), READ + pinned, MEASURED by the pin on both | type the aggregate attribute `withNull` in the lowering, or coalesce SUM to 0 in SQL (the Mem semantics): the orchestrator's call | `sumBy`/`meanBy`/`maxBy`/`minBy` over a filtered-empty relation | FAIL / FAIL |
| O-6 | FRAGILE | `sql/SqlEmitter.scala:38` `emitColumnName` (default; SQLite inherits) | identifiers are never quoted on SQLite: a column named `in`, `order`, `group`, `select`, `from` is a syntax error | §O-6, MEASURED SQLite (`(NULL) in`) | `SqliteEmitter.emitColumnName` quotes with `"..."` | any Ermine field named like a SQL keyword on the default runner | FAIL / ok |
| O-20 | WASTE / FRAGILE | `sql/SqlEmitter.scala:431,834` (`MsSqlEmitter` is `EmitNoDropTempTable`), `SqlScanner.scala:266` `cleanTempTables` (a no-op then) | every `LetR` binding creates a GLOBAL temp table `##t<sguid>` in tempdb and never drops it: 45 tables after 39 let-wrapped scans on one connection, gone only when the connection closes; `##` makes them visible to every session | §O-20, MEASURED SQL Server (the DB suite pins the count: one table per binding) | `emitDropTempTable = Some(DROP TABLE ..)` for MsSql (transaction-safe there), or `#`-local names | every `letR`/`materialize` on a pooled or long-lived `Run[DB]` (the preview): tempdb growth per session | -- / FAIL (clean assertion) |
| O-17 | NOTE | `Predicates.scala:16` `toFn` | the in-memory predicate is two-valued: `Lt`/`Gt` order NULL below everything (`NullExpr` ctorOrder 0), `Not` negates, so `Not(Eq(x, 1))` KEEPS a NULL row that SQL drops | READ; the reference is 3VL by the brief; the Mem path is not scanned here (`Scanners.e` publishes no Mem scan) | decide the semantics; if Mem stays, `toFn` answers `Option[Boolean]` | `filter` on a `Mem` (`groupBy` bodies, `hashJoin` arms) | -- |
| O-19 | WASTE | `relational/SqlScanner.scala:972-998` `LetR` | a let whose body never references the bound relation still creates and fills a temp table | READ from the emitted SQL of random cases (§O-1's SQL) | drop the binding when the body has no `RTop` | artificial programs only; cheap insurance | -- |
| O-18 | NOTE | the generator | NOT covered: `MemoR` (creates a PERSISTENT `MemoHash_..` table; `checkExists` always fails on SQLite so a second `memo` of the same relation in one connection throws "table exists": READ, itself a WRONG candidate), `PivotR`, windows, `Funcall`, `DateAdd`/`DateDiff`, `Cast`, `Table`, `TableProc`; strings are lower-case and doubles have one decimal place on SQL Server unless the classes are enabled | -- | a `memo` differential needs its own database | -- | -- |

`*` O-8's pin needs two-row literals (a one-row literal is squashed into the other side and never nests); the first pin shape passed on SQLite for that reason and was corrected (`oracle-pin8.log`).

## O-1 outer join inside a let body compiles as an inner join

MEASURED, SQLite in-memory, shrunk by ScalaCheck (`oracle-run10.log`).

```
LetR(ExtRel(Limit(RelEmpty({sn, sa, ba, tn}), None, Some(3), ..), ""), Nil,
     JoinOn(Project(SmallLit([{tn = 2024-02-29, da = 2.25}]), {tn, da nullable}),
            Project(RelEmpty({sn, sa}), {sn, sa nullable}),
            Set(), Full))
```
SQL (after the temp-table fill of the unused binding):
```
select (t92162.da) da, (t92163.sa) sa, (t92163.sn) sn, (t92162.tn) tn
from (select * from (select (2.25) da, (1709164800000) tn)) t92162
JOIN (select (NULL) sa, (NULL) sn where ('A' = 'B')) t92163 on ('A' = 'A')
```
Reference: one row `{da=2.25, sa=NULL, sn=NULL, tn=2024-02-29}` (a FULL JOIN keeps the left row). SQLite: no rows. The body does not even use the bound relation; the mode is lost by `Relation.fromScope`/`toScope` (`flatMap`/`map`) in `Optimizer.optimizeRel`'s `LetR` case, and by `unquoteR` in `Lib.scala:845`. Pin `O-1`, flag `letOuter`.

## O-8 right-nested join without parentheses (SQLite syntax error)

MEASURED, SQLite (`oracle-run5.log`; the same shape through a `LetR` body in `oracle-run8.log`).

```
JoinOn(Combine(Except(RelEmpty({tn, da}), Set()), p4, ..),
       JoinOn(Limit(RelEmpty({ta, sa, dn}), None, Some(1), ..), Limit(RelEmpty({tn}), Some(2), Some(5), ..), Set(), Inner),
       Set(), Inner)
```
```
select .. from (select (NULL) da, (NULL) tn where ('A' = 'B')) t102406
JOIN (select .. limit 1) t102404 JOIN (select .. limit 4 offset 1) t102405 on ('A' = 'A') on (t102406.tn = t102405.tn)
```
`org.sqlite.SQLiteException: near "on": syntax error`. `joinOn` takes `v2.sources.asSource.get` (a `SqlJoinOn`) as the right operand and `emitJoinOn` prints `r1 JOIN r2 on (..)` with `r2` a join. SQL Server parses `A JOIN B JOIN C ON x ON y`; SQLite needs `(B JOIN C ON x)`. Pin `O-8`, flag `nestedJoinRight`; the generator otherwise puts the nesting side on the left (a symmetric rewrite) or forces the right side into a subquery.

## O-10 computed columns on the unmatched side of an outer join

MEASURED, SQLite (`oracle-run7.log`).

```
JoinOn(Project(Filter(SmallLit([{tn=2024-02-29, sa=x, inl=-1, da=1.0}]), inl + inl < inl), {all nullable}),
       Project(Combine(RelEmpty({sn, ba, inl, ta}), p5, Concat('xx', if ba is null then 'a' else 'c d', 'x')), {all nullable}),
       Set(), Full)
```
```
select (t241665.ba) ba, (t241666.da) da, (coalesce(t241666.inl, t241665.inl)) inl,
       ((('xx') || ((case when (t241665.ba) is null then 'a' else ('c d') end))) || ('x')) p5, ..
from (select .. where ((-2) < (-1))) t241666 FULL JOIN (select (NULL) ba, .. where ('A' = 'B')) t241665 on (t241666.inl = t241665.inl)
```
Reference: `p5 = NULL` on the unmatched left row (the right side is empty). SQLite: `p5 = 'xxax'`: the Combine's expression sits in the join's select list and is evaluated over the NULL-padded right columns. `joinOn`'s `asSelect` condition for an outer side checks `where.isEmpty` only; computed `attrs` need the same subquery. Pin `O-10`, flag `outerJoinInlinedExpr`. Also MEASURED on SQL Server (`oracle-final-mssql.log` of 23:52) through a column-only `Project` over a `JoinOn` whose inner side carried the computed columns (`p1 = ab`, `p5 = ''` on an unmatched row where NULL is due): the join's select merges both sides' attrs, so the expressions travel up through any number of column-only projections and joins.

## O-14 non-injective projection skips DISTINCT

MEASURED, SQLite (`oracle-run11.log`).

```
Project(Project(SmallLit([{sn = b}, {sn = NULL}]), {sn}), {p2 -> coalesce(sn, 'b')})
```
```
select (coalesce(t391168.sn, 'b')) p2 from (select * from (select ('b') sn) UNION select * from (select (NULL) sn)) t391168
```
Reference: one row `p2 = b`. SQLite: `b` twice (no `distinct`; `scanAndUniq` trusts `d = true`). `preservesDistinctness` asks `columnDistinctness(rx, op, "sn")`: `sn` referenced once, no other column, so "preserved". Pin `O-14`, flag `projectNonInjective`.

## O-15 constant GROUP BY dropped

MEASURED, SQLite (`oracle-run13.log`).

```
AggregateByGroup(JoinOn(RelEmpty({sn, sa, inl, da}), SmallLit([{sn = a, tn = 2023-12-31}]), Set(), Inner),
                 {sn -> sn}, [(p5, Min sn)], group [sn])
```
```
select (MIN('a')) p5, ('a') sn from (select (NULL) da, (NULL) inl, (NULL) sa, (NULL) sn where ('A' = 'B')) t63488 where ((t63488.sn) = ('a'))
```
Reference: no rows (no groups). SQLite: one row `{p5 = NULL, sn = a}`. The one-row literal is squashed into the left select (`squashLiteral`), so `sn` is the constant `'a'`; `SqlSelect.emitSql` filters constant group expressions out (`group by 'a'` is illegal on SQL Server), leaving an UNGROUPED aggregate, which answers one row over no input. Same for `AggregateByGroup(Project(r, {k -> 'a'}), .., group [k])`. Pin `O-15`, flag `groupByConst`.

## O-28 FULL JOIN over a nullable key duplicates

MEASURED, SQLite (`oracle-run19.log`, after 861 passing cases).

```
JoinOn(Except(SmallLit([{sn = NULL}]), Set()), SmallLit([{sn = NULL}]), Set(), Full)
```
```
select (coalesce(t1837056.sn, t1837057.sn)) sn from (select * from (select (NULL) sn)) t1837056 FULL JOIN (select * from (select (NULL) sn)) t1837057 on (t1837056.sn = t1837057.sn)
```
Reference: one row `{sn = NULL}`. SQLite: two. The NULL keys do not match, the left-only and right-only rows both coalesce to `{sn = NULL}`, and `joinOn` answers distinct = `d1 && d2`, so nothing dedupes. Pin `O-28`, flag `fullJoinNullKey`.

## O-26 `Limit(from = to > 1)` skips DISTINCT on its input

MEASURED, SQLite (`oracle-run18.log`, after 501 passing cases).

```
Limit(Except(SmallLit([{ta = d, ba = true, inl = 0}, {ta = d, ba = false, inl = -1}]), {ba, inl}), Some(2), Some(2), [(ta, Desc)])
```
```
select (t1050626.ta) ta from (select * from (select (1) ba, (0) inl, (1704153600000) ta) UNION select * from (select (0) ba, (-1) inl, (1704153600000) ta)) t1050626 order by t1050626.ta desc limit 1 offset 1
```
Reference: no rows (the relation under the limit has ONE row, so rows 2..2 are none). SQLite: one row. `limit`'s `isOneRow = (Some(fromn) == to)` asks `q(!isOneRow)`, i.e. no distinctness, on the grounds that "1 row obviates distinct in the inner query": true for `from == 1`, false for an offset. Pin `O-26`, flag `limitOneRowOffset`.

## O-9 projection over an ungrouped aggregate loses the aggregate

MEASURED, SQLite (`oracle-run6.log`).

```
Project(Aggregate(Filter(Filter(RelEmpty({tn, sa, inl, da}), da > 2.25), da is null), p4, Min da), {p2 -> 3.0})
```
```
select (3.0) p2 from (select (NULL) da, (NULL) inl, (NULL) sa, (NULL) tn where ('A' = 'B')) t22528 where ((t22528.da) is null) and ((t22528.da) > (2.25))
```
Reference: one row `p2 = 3.0`. SQLite: no rows. `project` copies the new attrs over the aggregate's `SqlSelect` (`isAggregated` stays true but no aggregate function remains). Pin `O-9`, flag `projectOverAggConst`.

## O-13 two-row Limit taken for one row (lowering's; reproduced by the random generator)

MEASURED, SQLite (`oracle-run12.log`, after 424 passing cases).

```
Project(Except(Limit(LetR(.., AggregateByGroup(SmallLit([{sn=a},{sn=x},{sn=c d}]), {sn}, [(p3, Count), (p6, Count)], [sn])),
                     Some(2), Some(3), [(p3, Asc), (p6, Asc), (sn, Desc)]), Set()), {p1 -> -2})
```
```
select (-2) p1 from (select (COUNT(*)) p3, (COUNT(*)) p6, (t946177.sn) sn from (..) t946177 group by t946177.sn order by COUNT(*) asc, t946177.sn desc limit 2 offset 1) t946180
```
Reference: `p1 = -2` once. SQLite: twice. `Limit`'s `(Some(f), Some(t)) if t-f < 2` treats rows 2..3 (two rows, inclusive) as one and answers an all-constant `Reflexivity`. Pin `O-13`, flag `limitTwoRowsDistinct`.

## O-16 nested `if` merged into one CASE (optimizer's; reproduced)

MEASURED, SQLite (`oracle-run14.log`).

```
Project(RenameR(SmallLit([{sn = NULL, ib = 1}]), ib, p5),
        {sn, p5, p6 -> if (coalesce(sn, 'c d') > sn) then (if p5 is null then sn else sn) else ''})
```
```
.. ((case when not ((coalesce(t512000.sn, 'c d')) > (t512000.sn)) then '' when (t512000.ib) is null then t512000.sn else (t512000.sn) end)) p6 ..
```
Reference (3VL): the test is UNKNOWN (`sn` is NULL), so the alternate `''`. SQLite: `not(UNKNOWN)` is UNKNOWN, the first clause does not fire, the inner clauses answer NULL. Pin `O-16`, flag `ifNestedConsequent`. Merging when the ALTERNATE is a CASE is sound and the generator keeps producing it.

## O-11 `x = x` simplified to TRUE

MEASURED, SQLite (`oracle-run9.log`; again in `oracle-run16.log` as `Eq(if true then inl else inl, inl)`, folded by `Op.simplify` first).

```
Filter(SmallLit([{tn = NULL, ib = -1}]), Not(Not(Eq(tn, tn))))
```
```
select (t141312.ib) ib, (t141312.tn) tn from (select * from (select (-1) ib, (NULL) tn)) t141312 where ('A' = 'A')
```
Reference: no rows (`NULL = NULL` is UNKNOWN). SQLite: the row. Pin `O-11`, flag `eqSelf`.

## O-23 case-insensitive constant folding

MEASURED, SQL Server (`oracle-db-run.log` of 23:35): `Filter(SmallLit([{sn = 'c d', ta = ..}]), Eq(upper(sn), sn))` compiles to `.. where ('A' = 'A')`: the one-row literal's `Reflexivity` consts substitute `sn`, `Op.simplify` folds `upper('c d')` to `'C D'`, and `simplifyPredicate`'s `l === r` uses `PrimExpr` equality, which lower-cases strings. The reference (byte-wise, as SQLite) drops the row; SQL Server's CI collation would keep it anyway, so this fold agrees with SQL Server by accident and disagrees with SQLite by construction. The same order underlies `Record` equality, `uniqSorted` and `hashJoin` keys. Pin `O-23`; the generator's mixed-case values and `upper`/`lower` live under `mixedCase`.

## O-2 duplicate rows in a literal

MEASURED, SQL Server (`oracle-db-run.log` of 23:31): `SmallLit([{sn = NULL, sa = a}, {sn = NULL, sa = a}])` emits `select [sa],[sn] from (values ('a', NULL), ('a', NULL)) as lit([sa],[sn])` and both rows come out; `DistinctiveQuery.literal` answers `(true, ..)`. SQLite's `fallbackEmitLiteral` is a UNION of one-row selects and dedupes by accident (MEASURED equal there over hundreds of literals with a duplicate row). Pin `O-2`, flag `dupLit`.

## O-22 untyped NULLs of an empty relation (and of an all-NULL literal column)

MEASURED, SQL Server (`oracle-db-run.log` of 23:33 and 23:37): `Aggregate(RelEmpty({tn}), p6, Max tn)` emits `select (MAX([t].[tn])) [p6] from (select (NULL) [tn] where ('A' = 'B')) [t]` -> `Operand data type NULL is invalid for max operator`; the same through a LEFT JOIN of an empty side, and for `Aggregate(SmallLit([{sn = NULL}]), p4, Max sn)` (`values (NULL)`: an all-NULL TVC column has no type). Pins `O-22`, `O-22b`, flag `emptyAgg`.

## O-24 / O-27 ORDER BY expressions

MEASURED, SQL Server. O-24 (`oracle-db-run.log` of 23:36): `Limit(AggregateByGroup(lit, [], [(p1, Sum inl), (p6, Sum inl)]), Some(2), Some(2), [(p1, Desc), (p6, Asc)])` emits `order by SUM([t].[inl]) desc, SUM([t].[inl]) asc offset 1 rows fetch next 1 rows only` -> `A column has been specified more than once in the order by list`. O-27 (`oracle-db-run600.log` of 23:44): `Limit(Project(Limit(RelEmpty({tn, sa}), ..), {tn, sa, p5 -> if tn = d then 'c d' else (if ..)}), Some(1), Some(3), [(p5, Asc), (sa, Desc), (tn, Desc)])` -> `A constant expression was encountered in the ORDER BY list, position 1`. Both come from `SqlQuery.orderBy` ordering a `SqlSelect` by its attrs' expressions instead of their aliases. Pins `O-24`, `O-27`, flags `orderDupExpr`, `orderByConstExpr`.

## O-25 NULL constant substituted into a filter

MEASURED, SQL Server (`oracle-db-run.log` of 23:38): `Filter(SmallLit([{tn = NULL}]), Eq(tn, if tn < tn then tn else tn))` emits `where ((NULL) = ((case when (NULL) < (NULL) then NULL else (NULL) end))) and ..` -> `At least one of the result expressions in a CASE specification must be an expression other than the NULL constant`. Pin `O-25`, flag `nullConstSubst`.

## O-21 double literals are DECIMAL on SQL Server

MEASURED, SQL Server (`oracle-db-run.log` of 23:32 and `oracle-db-debug.log`): `Combine(Project(SmallLit([{da = 1.0, ..}]), ..), p4, da / 3.0)` answers `p4 = 0.333333` (numeric scale 6; reference and SQLite `0.3333333333333333`); `Union(RenameR(SmallLit(five rows with da 3.0/NULL/2.25/0.5)), Project(AggregateByGroup(.., [(p2, Sum dn)]), {dn -> p2, ..}))` answers `2.3` for the literal's `2.25` (the UNION of a scale-2 literal column with a precision-38 SUM keeps precision and drops scale). Pin `O-21`, flag `decimalLiteral`; without it the generator's doubles have one decimal place and are only added, subtracted, summed and compared.

## O-20 temp tables never dropped on SQL Server

MEASURED, SQL Server (`oracle-final-mssql.log`): `[sqldiff] mssql: 0 ##t tables in tempdb before, N new after 39 let-wrapped scans holding N let bindings`, N = 44..54 per run; the DB suite's default property pins `new == bindings`, the clean assertion (`tempdb holds no ##t table this suite's scans created`) runs under `letTemp` and FAILS today.

## O-7 OFFSET without LIMIT

MEASURED, SQLite (`oracle-run4.log`): `Limit(RelEmpty({sn, ba}), Some(3), None, [(ba, Asc), (sn, Desc)])` emits `.. order by ba asc, sn desc offset 2` and SQLite answers `near "offset": syntax error`. Pin `O-7`, flag `limitOffsetOnly`.

## O-12 nested set operations without parentheses (lowering's, pinned)

Pinned from the board with the lowering role's relation (`Union(A, MinusI(B, C))`: expected 4 rows on SQL Server, 3 delivered; the pin FAILS on SQL Server and passes on SQLite, whose `emitNaryOp` wraps each arm). Flag `setOpPrecedence`.

## O-5 concat with a NULL

Pinned (flag `concatNull`, FAILS on SQLite): `Project(lit{sn = NULL, sa = a}, {p1 -> concat(sa, sn)})` under `StringT(0, false)`. SQLite `||` answers NULL and the scan throws `Unexpected NULL in field of type StringT(0,false)`; SQL Server's `CONCAT` and `Op.eval` answer `"a"` (the pin passes there).

## O-3 outer join header not widened

Pinned (flag `outerNull`, FAILS on both): `JoinOn(lit{ia=1, ib=7}, lit{ia=2, da=0.5}, Set(), Left)`: the left row is unmatched, `da` is `DoubleT(false)` in the header, `nextRecord` throws `Unexpected NULL in field of type DoubleT(false)`. The generator keeps running outer joins by projecting the outer side onto nullable types first (`widen`), which is what `Typer.joinType` should do.

## O-4 SUM over no rows under a non-nullable attribute

Pinned (flag `sumEmpty`, FAILS on both): `Aggregate(RelEmpty({ia}), Attribute(p1, IntT(false)), Sum ia)`: SQL answers one row with NULL, the scan throws; the Mem path (`AggFunc.reduce`, `sumMonoid.zero`) answers 0. The reference follows SQL (NULL) and types every SUM/AVG/MIN/MAX attribute nullable; which semantics Ermine wants is the orchestrator's decision (the lowering role measured the same from `sumBy`).

## O-6 unquoted identifiers on SQLite

MEASURED, SQLite (`oracle-run1.log`): a literal with a column named `in` emits `select (NULL) in ..` -> `near ",": syntax error`. The generator's nullable-int column was renamed `inl`; pin `O-6` (`{in, order}`), flag `keyword`.

## Coverage and cost

- SQLite half: minSuccessfulTests 300 (`-Dermine.test.sqldiff.n=<int>` overrides); the final default run and its `[sqldiff]` coverage line are quoted in the handoff message; 1500 cases ran green in 25 s of sbt time (`oracle-run20.log`). The coverage property draws 500 candidates without scanning them and fails if any constructor is never generated or more than 10% of candidates are ill-typed.
- SQL Server half: minSuccessfulTests 150; 600 cases ran green (`oracle-db-run600.log`, sbt 4 s after start-up) with the `mssql` profile; plus the O-20 count property.
- Discards: 1-3% of candidates, all "Join of relations with mismatching column types": the two sides of a join minting the same fresh name `p<k>` with different types (a generator limitation, not a compiler finding).
- Constructor histogram of a green 1500-case run (`oracle-run20.log`): SmallLit 857, Project 358, AggregateByGroup 158, Filter 144, Union 131, Limit 126, Combine 116, RenameR 111, RelEmpty 111, JoinOn.Inner 110, Aggregate 102, Except 99, LetR 87, MinusI 79, JoinOn.Left 34, JoinOn.Right 19, JoinOn.Full 15-30.
- A shrunk counterexample can land in an EXCLUDED class (shrinking drops literal rows into `RelEmpty`), so a failure report is read together with its `ARG_0_ORIGINAL`.

## For the orchestrator

1. Decisions, not fixes: O-4 (SQL NULL vs Mem 0 for an empty SUM), O-23 (case-insensitive string equality in memory and in constant folding), O-17 (2VL Mem predicates).
2. One fix each closes several: order-by-alias closes O-24 and O-27; typed NULL literals close O-22, O-22b and O-25; the `joinOn` subquery rule closes O-10 and (with a parenthesised right operand) O-8.
3. The DB-programme shapes most exposed: O-1 (any outer join under `letR`), O-15 (`groupBy` after `filterEq` with no matching rows), O-14 (`project` through `coalesce`/`if`), O-21 (literal doubles on SQL Server), O-20 (tempdb growth per session).
4. Implementers: remove the `on("<flag>")` exclusion in `SqlDifferential.Gens` with the fix, keep the pin, drop the flag from `Profile` if it is there; the pins are registered only under their flag today because they FAIL on this tree.
