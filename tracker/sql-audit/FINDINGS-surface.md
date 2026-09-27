# FINDINGS-surface: what reaches SQL, and what silently stays in Ermine

Role `surface`, 2026-09-26 22:59-23:35 (budget 2.5 h, used ~40 min of clock). Auditor only: no
source edited, no sbt, nothing committed.

Evidence: `scratch-sql-audit/surface/{Probe,Probe2}.e` dumped through the REPL (`probe*.out`),
the SQL per binding in `surface/sql/<name>.sql`, and the rows python3's `sqlite3` returned for
every SQLite dump in `surface/out/<name>.txt`. "MEASURED" below means that route; "READ" means
reasoned from the code at the cited line. The in-memory (`Mem`) evaluator cannot be driven from
the REPL (`Scanners.e` publishes only `dumpClosed`), so every Mem-side claim is READ, with the
SQL side of the same expression MEASURED where it exists.

## Table 1: the surface-to-constructor map (question 1)

`Rel` = runs in SQL (`relational/Rel.scala` constructor); `Mem` = Ermine evaluates it
(`relational/Mem.scala`, interpreted by `SqlScanner.compileMem`); "follows operand" = the smart
constructor in `relational/Ext.scala` picks `Rel` for an `ExtRel` operand and `Mem` for an
`ExtMem` one (mixed operands: `LetR(ExtMem ..)`, i.e. the Mem is bulk-loaded into a temp table
and the rest runs in SQL). A value is `ExtMem` once `asMem`/`toMem`/`mem`/`groupBy`/`accumulate`/
`medianBy`/`hashJoin`/`mergeJoin`/`hashLeftJoin`/`letM`/`promote` has touched it; the Ermine
type `Mem` tracks this exactly (`Relation` never holds an `ExtMem`, checked: `join r1 (mem ..)`
does not type).

| surface (module) | lowers to (file:line) | runs in | note |
|---|---|---|---|
| `relation` / `row` / `nonEmptyRelation` (Relation.e:23-40) | `SmallLit` via `buildRelation` (Runtime.scala:376) | Rel | `relation []` is the HEADERLESS `EmptyRel` runtime value (S-03) |
| `relationWithHeader r []` (Relation.e:26) | `RelEmpty(header)` (Lib.scala:348) | Rel | the typed empty; MEASURED: `select .. where 0`; use it instead of `relation []` |
| `mem` (Relation.e:36) | `Literal` via `buildMem` (Runtime.scala:391) | Mem | |
| `filter` / `[\| p \|]` (Relation.Predicate, builtin) | `FilterE` (Lib.scala:526) -> `Filter` / `FilterM` | follows operand | |
| `join` / `**` / `&` / `join1` / `joinBy` / `joinBy'` | `JoinE` (Lib.scala:657, Ext.scala:120) -> `Join` / `HashInnerJoin` | follows operand | mixed operands -> `LetR(ExtMem, Join(..))` (temp table + SqlLoad) |
| `joinOn` (Relation.UnifyFields, builtin) | `JoinOn(.., cs, Inner)` (Lib.scala:735) | Rel only | requires both `ExtRel` with the same `db` |
| `unsafeLeftJoin` / `unsafeRightJoin` | `LeftJoinE` (Lib.scala:670, Ext.scala:132) -> `JoinOn(.., Left)` / `HashLeftJoin` | follows operand | right `EmptyRel` returns the LEFT operand unchanged (S-03); MODE LOST inside a `letR` body (S-01) |
| `unsafeFullJoin` | `FullJoinE` (Lib.scala:685) -> `JoinOn(.., Full)` / `MergeOuterJoin` | follows operand | same two holes |
| `leftJoinOr` / `rightJoinOr` / `joinWithDefault` / `rightJoinWithDefault` (Relation.e:84-100) | `LeftJoinE` + `projectEach` (Lib.scala:588 -> `ProjectE` with `coalesce`) | follows operand | MEASURED: `LEFT JOIN .. coalesce(u,'?')`; PANICS inside any quoted body (S-02) |
| `partialLookup` / `partialLookup'` (Relation.e:107-128) | `LeftJoinE` + `CombineE(coalesce)` + `ExceptE` + `RenameE` | follows operand | safe: the only outer column is coalesced |
| `union` / `unionAll` / `unionAllWithHeader` | `UnionE` (Lib.scala:751) -> `Union` / `UnionM` | follows operand | MEASURED: `UNION` (set); `unionAll []` = `EmptyRel` |
| `difference` / `minus` (Relation.e, builtin) | `MinusE` (Lib.scala:764) -> `Minus` / `DifferenceM` | follows operand | MEASURED: `EXCEPT` |
| `project` / `#` (Relation.Row:47) | `ProjectE` (Lib.scala:542) -> `Project` / `ProjectM` | follows operand | MEASURED: `select distinct` |
| `except` / `-#` (Relation.Row:51) | `ExceptE` (Lib.scala:550) -> `Except` / `ExceptM` | follows operand | |
| `projectT` / `exceptT` / `spanT` / `!*` | `projectT#` / `exceptT#` (Lib.scala:577-586) | Ermine record op | not relational; `.toMap` present |
| `rename` / `rename'` / `copyColumn` / `replaceColumn` | `RenameE` (Lib.scala:558) / `CombineE` | follows operand | |
| `promote` (builtin) | `RenameM(.., promote = true)` (Lib.scala:566) | Mem only | 0 uses in stdlib/examples |
| `combine` / `[\| f = op \|]` / `setColumn` (Relation.Op:135) | `CombineE` (Lib.scala:776) -> `Combine` / `CombineM` | follows operand | the `Op` is compiled by `SqlScanner.compileOp:64` or evaluated by `Op.eval:20` (Table 3) |
| `projectEach` (builtin, Lib.scala:588) | `ProjectE` over `Typer.closedExt(e).header` | follows operand | the header call is what panics on a quote (S-02) |
| `limit` / `firstK` / `topK` / `bottomK` (Relation.Sort:139-149) | `limit#` (Lib.scala:536) -> `Limit` / `LimitM` | follows operand | SQL is 1-based inclusive (MEASURED); `LimitM` is 0-based half-open (S-11) |
| `aggregate` / `count` / `sumBy` / `meanBy` / `minBy` / `maxBy` / `standardDeviationBy` / `varianceBy` / `weightedMean` (Relation.Aggregate) | `AggregateE` (Lib.scala:605) -> `Aggregate` / `AggregateM` | follows operand | one row; SQL NULL on empty input into a non-nullable header (S-09) |
| `aggregateByGroup` (Relation.Aggregate:50) | `AggregateByGroup` (Lib.scala:630) | Rel only | MEASURED: `select k, SUM(x) .. group by k`; the only GROUP BY the surface can reach |
| `groupBy` / `topKBy` / `bottomKBy` (Relation.e:130-148) | `groupBy#` (Lib.scala:907) -> `GroupByM(asMem r, key, body)` | Mem ALWAYS | fetches every row; compiles the body once PER GROUP (SqlScanner:576); rule for an exact `AggregateByGroup` lowering in section 9 |
| `nearestDate` / `nearestDateWithin` / `lookupLatest*` / `lookbackJoin` (Relation.e:199-247) | `materialize (groupBy {ffine} (maxRowBy fsparse) (filter (join rsparse rfine)))` | join+filter in SQL, then the WHOLE filtered product to memory, then `SqlLoad` temp table | W-04; MEASURED: dump answers `Emission not supported .. SqlLoad` |
| `accumulate` (Native.Relation, Lib.scala:948) | `AccumulateM` | Mem only | reads leaves and tree fully into memory (SqlScanner:516) |
| `medianBy` / `weightedMeanBy` / `weightedHarmonicMeanBy` (Relation.Process) | `pipe#` -> `ProcessM` (Lib.scala:896) | Mem only | `letM r id` first |
| `memoRel` / `memoRelWithPK` (Lib.scala:618-629) | `MemoE` -> `MemoR` (Rel) / identity (Mem) | Rel | a PERSISTENT table `MemoHash_<sha>` (SqlScanner:961-971); F-01 |
| `letR` / `letRWithPK` / `materialize` / `materializeWithPK` (Native.Relation, Lib.scala:832-876) | `LetR(ext, pk, body)` | Rel (the bound value may be a Mem: it is bulk-loaded) | MEASURED: `CREATE TEMPORARY TABLE` + `insert` + `select`; the body is a QUOTE (S-01, S-02) |
| `letM` (Lib.scala:878) | `LetM` | Mem | |
| `asMem` / `toMem` (Lib.scala:791) | `EmbedMem(ext)` | Mem from here on | the SQL under it still runs in SQL, then `scanAndUniq` |
| `hashJoin` / `mergeJoin` (Lib.scala:702-713) | `HashInnerJoin` / `MergeOuterJoin` | Mem only | 0 uses |
| `hashLeftJoin` (Lib.scala:715) | `HashLeftJoin` | Mem only | 0 uses; NULL-fills the outer side (SqlScanner:493) |
| `unify1` (Relation.UnifyFields) | `join (rename f1 f2 (except {f2} r2)) r` | follows operand | |
| `pivot` / `pivotWithDefault` (Relation.Pivot:110-116) | `PivotE` (Lib.scala:1035) -> `PivotR` / `Pivot` | follows operand | MEASURED: `coalesce(MAX(case when ..), NULL) .. group by`; default `Null Double` into a non-nullable header (S-10) |
| `windowed rank/dense/rowNumber/nTile/windowedAggregate` (Relation.Windowed) | `Op.Windowed` inside a `Combine` | Rel only (SQL Server emitter; SQLite emitter prints a TODO) | `Op.eval` throws for it (Op.scala:44) |
| `filterEq` (Relation.e:45) | `join r (relation [{f = a}])` | Rel | MEASURED: optimizer folds the literal into `where f = a` and a constant column: good |
| `filterNEq` (Relation.e:48) | `difference r (join r lit)` | Rel | MEASURED: `R EXCEPT (select .. from R where f = a)`: two scans (W-02) |
| `firstBy` / `lastBy` / `maxRowBy` / `minRowBy` | `join r (topK f 1 (project f r))` / `join (maxBy f r) r` | Rel | MEASURED: join with an ordered `limit 1` / `MAX` subquery; acceptable |
| `leafRows` (Relation.e:73) | difference of a self-join | Rel | |
| `Layout.Fetch.scanRelation` / `scanRelationInOrder` / `scan` / `scanInOrder` (Layout/Fetch.e:69-92) | `Scan Sort# (relation# r)`: `relation#` = `Optimizer.optimize` + `Typer.closedExt` (Lib.scala:826); the runner executes ONE statement per `Scan` | whatever the plan is | rows come back as `Record#` and are re-typed with `unsafeRecordIn#` |
| `Relation.Scan.groupBy'/groupBy/groupBy1` + `sumBy`/`avgBy`/`count` with `Layout.Fetch.runner` (Relation/Scan.e:95-149) | one scan of `rel # row`, then `join rel (relation [k])` per key, executed by `multiply` | N+1 statements | section 7 |
| `Scanners.dumpQuery` | `Scanner.dumpClosed` | -- | "Don't know how to dump a mem" for every Mem (MEASURED) |

## Table 2: findings, ranked

| id | severity | where (file:line) | one-line claim | repro | proposed fix | blast radius |
|---|---|---|---|---|---|---|
| S-01 | WRONG | Rel.scala:113 `JoinOn` bimap/subst drop `mode`; Optimizer LetR case; surfaced by Lib.scala:842 `letR` | an outer join inside a `letR`/`materialize`/`letRWithPK` body compiles as an INNER join (and the small literal is folded into a predicate) | MEASURED `q2_letR_left_L`: `letR r1 (r -> unsafeLeftJoin r rx)` -> `select (1) k, s, ('one') u, .. from tmp where k = 1`; 2 rows, expected 3 | carry `mode` through `JoinOn.bimap/subst/unquote` (oracle's finding; the oracle owns the test) | every `letR`/`materialize` body with an outer join; `lookbackJoin`, hand-written reports |
| S-02 | WRONG | Lib.scala:591 `projectEach` (`Typer.closedExt(e).header`) | `leftJoinOr`/`joinWithDefault`/`rightJoinWithDefault` PANIC "Asked for the header of a quote" inside any `letR`, `groupBy` or `accumulate` body | MEASURED `q2_letR_leftOr_L`, `q2_groupBy_leftOr_L`; `q_leftMem_L` | compute the header lazily: build `ProjectE` from the row `r`'s keys alone (`Header.proj` of the QUOTE is what fails); or type `projectEach`'s extra columns from `r` and take the rest via `ExceptE`+`CombineE` (no header call) | 2 example files each for `leftJoinOr`/`joinWithDefault`/`rightJoinWithDefault`; any of them under `groupBy` (40 example files use groupBy) |
| S-03 | WRONG | Lib.scala:675, 690 (`unsafeLeftJoin`/`unsafeFullJoin` return the left operand on right `EmptyRel`); Lib.scala:834/856 (`letR` "XXX EmptyRel case is wrong") | `relation []` is headerless; an outer join against it loses the `extra` columns and `leftJoinOr` then fails "nonexistent column (u)" | MEASURED `q_leftEmpty_L`; `q2_leftEmptyH_L` with `relationWithHeader {k,u} []` is correct | in `unsafeLeftJoin`, on right `EmptyRel` build `LeftJoinE(inner, ExtRel(RelEmpty(h)))` where `h` comes from the Ermine row type? (erased at runtime) -- practical fix: make `relation []` a `RelEmpty` by threading the row type's header the way `relationWithHeader` does (`nonEmptyRelation` shows the header can be recovered from a record); short-term: document `relationWithHeader`/`unionAllWithHeader` as the empties | any report that builds an empty relation from an empty list (`unionAll []`, `relation (filter .. [])`) and outer-joins or `letR`s it |
| S-04 | WRONG | Op.scala:87 `builtinSimplify` LogBase branch has no default case | `logBase x b` throws `scala.MatchError(OpLiteral(2.0))` for every base other than the literal 1, on every dialect and in memory (compileOp:119 and simplifyPredicate both call `simplify`) | MEASURED `q_logBase_L`: `<error: OpLiteral(2.0) (of class ..Op$OpLiteral)>` | add `case _ =>` falling through to the generic literal fold; and the `base == 1` branch answering `0` is nonsense (log base 1 is undefined), drop it | `logBase` has 0 example uses; `Relation.Op` exports it |
| S-05 | WRONG | SqlEmitter.scala:518 `EmitLimit_AsLimit` `(Some(x), None) => " offset %d"` | `limit o (Just n) Nothing` is a SQLite syntax error (OFFSET needs LIMIT) | MEASURED `q2_limit_start_L`: `near "offset": syntax error`; SQL Server form `offset 1 rows` is fine | emit ` limit -1 offset %d` | any `limit` with a start and no stop on the default (SQLite) runner |
| S-06 | WRONG | SqlScanner.scala:142 + SqlEmitter.scala:328/341 (SQLite inherits STDDEV_POP/VAR_POP) | `standardDeviationBy`/`varianceBy` fail on SQLite: "no such function: STDDEV_POP" | MEASURED `q_stddev_L` | SQLite: emit `sqrt(avg(x*x) - avg(x)*avg(x))` and `avg(x*x) - avg(x)*avg(x)` (population forms, matching STDEVP/VARP on SQL Server) | 1 example file each |
| S-07 | WRONG | SqlScanner.scala:110 (`datediff(day, ..)` unconditionally), SqlEmitter.scala:699-701 (SQLite dateadd = `sys.error("todo")`) | `dateDiff` and `dateAdd` do not work on SQLite at all | MEASURED `q_dateDiff_L`: `no such column: day`; `q_dateAdd_L`: `todo - sqlite dateadd function` | SQLite stores dates as epoch millis (`emitDate`): `dateDiff days a b` = `(b - a) / 86400000`, weeks `/ 604800000`; months/years need `strftime('%Y', a/1000, 'unixepoch')`; `dateAdd n days d` = `d + n*86400000`, months/years via `strftime(.., '+n months')` | `dateDiff` 8 example files, `dateAdd` 4 |
| S-08 | WRONG | Op.scala:186 (`Concat` typed `StringT(0,false)`), SqlEmitter.scala:322 (SQLite `\|\|`), SqlExecution.scala:97 | `show n` / `a ++ b` over a nullable column: SQLite answers NULL, SQL Server (`Concat`) and memory (`extractNullableString ""`) answer ''; the header says non-nullable so the SQLite row raises "Unexpected NULL in field of type StringT" | MEASURED `q_show_null_L` rows `NULL \| NULL \| 2`; `q_show_null_M` emits `Concat([n], '')` | SQLite: emit `coalesce(x, '')` per Concat term (matches SQL Server `Concat` and memory) | `show` in 19 example files; any nullable column shown in a label |
| S-09 | WRONG | Typer.scala:84 `aggregateType` keeps the field's type; SqlExecution.scala:97 | `sumBy`/`maxBy`/`minBy`/`meanBy` over a relation whose filter matches nothing: SQL returns one NULL row into a non-nullable header and the read throws; memory: `sum` answers 0, `min`/`max` answer `NullExpr` which `fromPrimExpr` rejects | MEASURED `q_sum_empty_L`, `q_max_empty_L`: one row, `NULL` | either type the aggregate's attribute `withNull` for Sum/Avg/Min/Max (surface-visible: `sumBy` would return `Nullable a`; NOT allowed) or make the scanner substitute the monoid zero: `coalesce(SUM(x), 0)` for Sum, and for Min/Max/Avg return ZERO rows (an empty relation, which is what `aggregate` on `EmptyRel` already returns) | every aggregate over a parameter-filtered relation; `count` is safe (`COUNT(*)` = 0) |
| S-10 | WRONG | Relation/Pivot.e:112 (default `Null Double`), Typer.scala:182 (`guessTypeUnsafe`, non-nullable) | `pivot` over a group missing one key value returns NULL in a non-nullable column: SQL read throws; memory `fromPrimExpr` rejects | MEASURED `q_pivot_L`: `30 \| NULL \| 2`; SQL `coalesce(MAX(case ..), NULL)` | `pivot` should pass `defaultValue ftype` (already written for `defaultFulcrumWithDefault`, Pivot.e:50) instead of `Null Double`, i.e. `pivot = pivotWithDefault . withDefaults`; no surface change (a private helper) | `pivot` in 15 example files |
| S-11 | WRONG | SqlScanner.scala:425-436 `LimitM` (drop `start`, take `stop-start`) vs SqlScanner.scala:1248/SqlEmitter.scala:517 (1-based inclusive) | a `limit` on a Mem is off by one at both ends: `(Just 2, Just 3)` gives row 3 in memory, rows 2..3 in SQL; `(Just 2, Nothing)` skips two rows in memory, one in SQL | MEASURED SQL side `q_limit_L`: rows x=2,3; READ Mem side | `drop(start-1)`, `take(stop-start+1)` | `topK`/`bottomK`/`firstK` (start = Nothing) are unaffected, which is why nothing noticed; `topKBy`/`bottomKBy` unaffected; explicit `limit` with a start under `groupBy` |
| S-12 | WRONG | AggFunc.scala:121-129 `variance` | in-memory variance is `Σx - (Σx²)²` (tuple read in the wrong order, never divided by n); `stddev` is its square root | READ | `(Σx² / n) - (Σx / n)²` with the count carried in the tuple | `varianceBy`/`standardDeviationBy` on any Mem (inside `groupBy`) |
| S-13 | WRONG | AggFunc.scala:113 + PrimExpr.scala:163-170 (`+` propagates NULL), PrimExpr.scala:685 (`sumMonoid.zero = 0`) | in-memory `sum`/`avg`/`wmean` answer NULL if ANY input is NULL and 0 on empty input; SQL skips NULLs and answers NULL on empty | MEASURED SQL `q2_sum_null_L` = 4.5 (memory: NULL, READ) | `sumMonoid.append` skips `NullExpr` operands; empty input: see S-09 | `groupBy k (sumBy c)` over a nullable `c` (the pre-F-1 fixture shape) |
| S-14 | WRONG | Predicates.scala:16-25 `toFn` (`lt`/`gt` via `Order`, `not` = `!`), PrimExpr.scala:633 (`NullExpr` sorts before everything) | memory is two-valued, SQL three-valued: `n < 2` keeps NULL rows in memory, drops them in SQL; `n != v` (= `not (n == v)`) keeps NULL rows in memory, drops them in SQL | MEASURED SQL `q_neq_null_L` (1 row), `q_lt_null_L` (1 row); memory READ (2 rows each) | `toFn` returning `Option[Boolean]` (unknown) with `not`/`and`/`or` on 3VL and the filter keeping only `Some(true)`; `lt`/`gt` unknown when either side `isNull` | every filter on a nullable column that runs in memory (`filter` after `groupBy`) |
| S-15 | WRONG | SqlEmitter.scala:356 (SQLite integer division = `/`), PrimExpr.scala:197 (`floordiv` doubles = `floor(floor x / floor y)`), SqlEmitter.scala:631 (MS: `floor(floor(a)/floor(b))`) | `//` on Double columns: SQLite answers the exact quotient, memory and SQL Server the floored one | MEASURED `q_floordiv_dbl_L` = -3.75; `_M` emits `floor((floor(xd))/(floor(2.0)))` = -4 | SQLite: emit the MS form `floor(floor(a)/floor(b))`; note that for Ints all three truncate toward zero (`-7 // 2 = -3`, MEASURED), so `//` is not a floor for negatives anywhere and `%` (= `a - b*(a//b)`) is a truncating remainder (`-7 % 2 = -1`, MEASURED) | `//` in 5 example files |
| S-16 | WRONG | PrimExpr.scala:641 (`Order` on strings is `toLowerCase`), :330 (`hashCode` on the raw value), :309 (`equals` = `Order.equal`) | memory string equality/ordering is case-insensitive while its hashing is case-sensitive: `filter (s == "b")` matches "B" in memory, not on SQLite (0 rows), and does on SQL Server under its default CI collation; `groupBy`/hash join/`uniq` in memory group "B" and "b" apart (hash) while `sort`/`min`/`max`/`==` treat them as one | MEASURED `q_eq_case_L` 0 rows; `q2_eq_case_M` emits `= ('b')` (collation-dependent); memory READ | make `Order`/`equals` case-sensitive (Java `compareTo`), which also repairs the equals/hashCode contract; SQLite then agrees; SQL Server stays collation-dependent (document) | any string filter/groupBy that runs in memory |
| S-17 | WRONG | PrimExpr.scala:287 `cast` to `ByteT` builds a `ShortExpr` | `cast x Byte` in memory yields a Short-typed value at an Ermine `Byte` | READ | `ByteExpr(n, e.extractByte)` | tiny |
| S-18 | WRONG | SqlScanner.scala:559-591 `GroupByM` groups with `Process.groupingBy` on a `Map[String,PrimExpr]` key; PrimExpr.scala:434 `NullExpr.equals` is always false | in-memory `groupBy` over a NULLABLE KEY puts every NULL-keyed row in its own group (SQL `GROUP BY` makes one); same for in-memory `uniq` and `hashJoin` on NULL keys | READ | key comparison via `equalsIfNonNull`-aware structural equality (NULLs equal for grouping, as SQL does) | `groupBy` over a nullable key column |
| S-19 | WRONG | Op.scala:38-42 `DateDiff` in memory only `Millisecond`, else `sys.error` | any `dateDiff days ..` evaluated in memory (a `combine` after `groupBy`) throws "datediff is meant to be used from SQL" | READ | implement day/week/month/year on the GMT calendar `PrimExprs` already pins | `dateDiff` 8 example files, when under a Mem |
| S-20 | WASTE | Lib.scala:907 `groupBy#` (OBSERVABILITY §9) | `groupBy k (aggregateBy agg f) r`, `groupBy k count r`, `groupBy k (maxBy f) r` fetch every row and reduce in memory although each has an exact `AggregateByGroup` form | MEASURED: `q_groupBy_sum_L` is a Mem (cannot even be dumped), `q_aggByGroup_L` is one `group by` | the lowering rule in section 9: detect `AggregateM(VarM(MTop), attr, agg)` as the body and rewrite to `EmbedMem(ExtRel(AggregateByGroup ..))`, keeping the Ermine type `Mem`; no surface change | 40 example files use `groupBy`; tier l: 2 M rows fetched vs a few hundred |
| S-21 | WASTE | Relation.e:234-247 `nearestDate`/`nearestDateWithin` (`materialize ' groupBy {ffine} (maxRowBy fsparse) (filter (join rsparse rfine))`) | `lookupLatest*`/`lookbackJoin` fetch the whole date-filtered cross product `rsparse x rfine` into memory, group it in memory, then bulk-load a temp table | READ; MEASURED that the dump ends in `SqlLoad` | `groupBy {ffine} (maxRowBy fsparse)` = `join (aggregateByGroup (max fsparse) {ffine} fsparse p) p`: exact, all in SQL, no temp table; a private helper in Relation.e, no export change | `lookupLatest` 6 example files, `nearestDate` 7; cost O(sparse x fine) rows over the wire |
| S-22 | WASTE | SqlScanner.scala:570-583 | `GroupByM` calls `compileMem` (and `Typer.groupByType` per body) once PER GROUP, and runs the group body as a separate procedure per group | READ | compile the body once against the group header (it is the same for every group) and instantiate only the literal | proportional to the number of groups |
| S-23 | WASTE | Relation/Scan.e:95-149 with Layout/Fetch.e:100 `runner` | `groupBy_S`/`sumBy_S`/`count_S` over a `Fetch` issue one statement for the keys and then one `join rel (relation [k])` statement per key (N+1) | READ | `aggregateByGroup` for the sum/count forms; for the general form one scan ordered by the key and a split in Ermine | any report using `Layout.Scan`-style grouping |
| S-24 | WASTE | core/src/test/resources/doc/FetchTabs.e:39-42 | the tabs fixture reads `sales # {region}` once and then every tab is `filterEq region r sales`: K+1 statements over `sales`, each a full scan of the fact table filtered on region | READ (fixture) | one `scanRelationInOrder (ordering {region}) sales` and a split of the row list by region in Ermine (`Relation.Scan.groupBy'` shape without the per-key join) | tier l: K extra scans of 2 M rows |
| S-25 | WASTE | Relation.e:48 `filterNEq` | `difference r (join r lit)` compiles to `R EXCEPT (select .. from R where f = a)`: two scans plus a set difference | MEASURED `q_filterNEq_L` | optimizer rule `Minus(R, Filter(R, p)) -> Filter(R, Not(p) or IsNull(cols of p))` (exact, keeps the NULL rows the difference keeps); handed to the optimizer role on the board | `filterNEq` 2 example files; `leafRows` has the same shape |
| S-26 | FRAGILE | SqlScanner.scala:961-971 (`MemoR` = persistent `MemoHash_<sha>` table), :200-222 with SqlEmitter.scala:647 (`checkExists` always false on SQLite, plain `CREATE TABLE`) | `memoRel` is not a way to share a scan between two `Fetch` statements: on SQLite the second `create` of the same memo in one connection throws "table already exists" (unverified live; READ); on SQL Server the table persists across sessions and is never invalidated when the source changes; the name is a SHA over `r.toString` (the literal's rows included) | READ; MEASURED that the dump is `SqlCreateIfNotExists(MemoHash_.., Persistent)` | not a surface matter; note for the emitter/lowering roles; the oracle already excludes MemoR | `memoRel` 1 example file |
| S-27 | FRAGILE | Lib.scala:675 (`unsafeLeftJoin` bare), Typer.scala:102 `joinType` (`left ++ right`, outer columns keep their non-nullable type) | a bare `unsafeLeftJoin`/`unsafeFullJoin` produces NULLs in columns typed non-nullable; SQL read throws, Mem read `fromPrimExpr` rejects | MEASURED `q_unsafeLeft_L` row `2 \| 'c' \| NULL`; READ throw | by name unsafe; `leftJoinOr`/`partialLookup` coalesce correctly; leave, document | 0 bare uses |
| S-28 | FRAGILE | Op.scala:289-305 `incrementTimestamp` uses `Calendar.getInstance` (JVM default zone) while formatting/accessors are pinned to GMT (PrimExpr.scala:499-575) | in-memory `dateAdd` across a DST change in the machine's zone shifts by an hour; SQL `dateadd` is calendar arithmetic | READ | build the calendar on `ymdPivotTimeZone` | `dateAdd` under a Mem |
| S-29 | FRAGILE | PrimExpr.scala:693/712 `minMonoid`/`maxMonoid` compare strings with Java `<=` (case-sensitive) while `Order` is case-insensitive | in-memory `minBy`/`maxBy` on strings disagree with in-memory `<` | READ | one string order | small |
| S-30 | FRAGILE | ReportingUtils.scala:41-42 `simplifyPredicate`: `Eq(l, r)` with `l === r` -> `Atom(true)` | `filter (x == x)` is folded to TRUE before SQL sees it; in SQL `x = x` is unknown for NULL | READ | guard with "no nullable column reference" | idiom is rare |
| S-31 | NOTE | Op.scala:44, Predicates.scala:25 | `Windowed` and `Funcall`/`Funtest` cannot be evaluated in memory (`sys.error`); a window function under `groupBy` throws | READ | by design; document on `Relation.Windowed` | -- |
| S-32 | NOTE | AggFunc.scala:116 `avg` = `sum / mkExpr(n, t)` (Int division for Int columns); SQL Server `AVG(int)` truncates; SQLite `avg` is REAL, read back through `rs.getInt` | `meanBy` on an Int column truncates on all three paths, by three different mechanisms | MEASURED `q2_avg_half_L` SQLite answers 1.5, header `IntT` | consistent, but `meanBy` of an Int column should probably be typed Double (surface change: not now) | -- |
| S-33 | NOTE | Lib.scala:635 (`aggregateByGroup#`), :651 (`note`) match only `Rel(ExtRel ..)` | a `MatchError` would follow for an `ExtMem` operand, but the Ermine type `Relation` cannot hold one (checked) | READ | -- | none |
| S-34 | NOTE | Typer.scala:182, SqlScanner.scala:1282 (`mapValues` views) | the two remaining 2.13 `MapView`s in the owned files are only `++`'d into a Map, never compared or hashed; every compare/hash site in `SqlScanner.compileMem`, `package.sorting/uniq`, `Lib.projectT#` has its `.toMap` | READ (grep) | -- | none |
| S-35 | NOTE | PrimExpr.scala:633 | NULL sorts FIRST ascending in memory; SQLite and SQL Server also put NULLs first ascending | READ | agrees | -- |

## 3. Question 2: two evaluators, one meaning

`compileOp` (SqlScanner.scala:64) and `Op.eval` (Op.scala:20) side by side. "agree" is for the
two live dialects unless a column says otherwise.

| builtin | SQL text (SQLite / SQL Server) | memory | verdict |
|---|---|---|---|
| `+ - *` | `a + b` | `nonpromotingBinOp` (PrimExpr:163): same type both sides or `sys.error`; SQL promotes Int+Double | FRAGILE: mixed Int/Double literal works in SQL, throws in memory (typer usually forbids) |
| `/` (`DoubleDiv`) | `a / b` | `_ / _` per type: Int/Int truncates | agree (both truncate on Ints; the name lies) |
| `//` (`FloorDiv`) | SQLite `a / b`; MS `floor(floor(a)/floor(b))` | Ints truncate; Doubles `floor(floor a / floor b)` | S-15 |
| `%` (surface, `a - b*(a//b)`) | as above | as above | truncating remainder everywhere (`-7 % 2 = -1`) |
| `++`, `show` (`Concat`) | SQLite `\|\|` (NULL-propagating); MS `Concat(..)` (NULL -> '') | `extractNullableString ""` | S-08 |
| `if` | `case when p then c else a end` | `if (p eval t)` two-valued | S-14 applies to `p` |
| `coalesce` | `coalesce(l, r)` | first non-NULL | agree |
| `dateAdd` | MS `dateadd(unit, n, d)`; SQLite `sys.error` | Calendar in the JVM zone | S-07, S-28 |
| `dateDiff` | `datediff(unit, s, e)` (SQLite: no such function) | Millisecond only, else `sys.error` | S-07, S-19; on SQL Server `datediff(day, ..)` counts boundary crossings, memory (if it worked) would count whole units: a further disagreement |
| `cast` / `tryCast` | `cast(x as T)` / MS `TRY_CAST`; SQLite has no TRY_CAST and `cast('abc' as integer)` = 0 | `cast`/`tryCast` -> `NullExpr` on failure; Byte -> Short (S-17) | FRAGILE on SQLite (`tryCast` never yields NULL there) |
| `upper`/`lower` | `UPPER`/`LOWER` (SQLite: ASCII only) | Java `toUpperCase` (Unicode) | FRAGILE for non-ASCII on SQLite |
| `replace` | `REPLACE(x, t, r)` | `String.replace` | agree (argument order checked) |
| `abs`, `exp`, `log`, `log10`, `pow` | `ABS`, `EXP`, `LOG`, `LOG10`, `POWER` | `math.*`; `pow` on Ints truncates to Int, SQLite `power` is REAL read back via `getInt` | agree in value |
| `logBase` | `LOG(x, b)`; note SQLite's `log(B, X)` takes the BASE FIRST | `log a / log b` | S-04 (never reached: MatchError) |
| `==` | `(a) = (b)` | `equalsIfNonNull` (NULL never equal); strings case-insensitive | S-14, S-16 |
| `<`, `>` (`<=`/`>=` are `< or ==`) | `<` / `>` | `Order`: NULL < everything; strings case-insensitive; cross-type by constructor rank | S-14, S-16 |
| `not`, `&&`, `\|\|` | `not (..)`, `and`, `or` | Boolean | S-14 (`not unknown` = true in memory) |
| `isNull` | `is null` | `isNull` | agree |
| aggregates `count/sum/avg/min/max/stddev/variance/wmean` | `COUNT(*)`, `SUM`, `AVG`, `MIN`, `MAX`, `STDDEV_POP`/`STDEVP`, `VAR_POP`/`VARP`, `SUM(x*w)/SUM(w)` | AggFunc.scala:110-148 | S-06, S-09, S-12, S-13; `min`/`max` skip NULLs and answer NULL on empty in both (agree); `count` agrees |
| `rank`, `dense`, `rowNumber`, `nTile`, `windowedAggregate` | MS `RANK() over (..)`; SQLite emitter prints a TODO string | `sys.error` | S-31 |
| `-0.0`, NaN | SQLite/MS have no NaN literal path (emitter role) | `DoubleExpr(0.0)` canonicalises `-0.0` to the shared zero (PrimExpr:493: `value == 0.0` is true for `-0.0`) | NOTE: `-0.0` becomes `0.0` in memory |
| Int width | SQLite `integer` (64-bit; `SUM` of ints is 64-bit, read back with `rs.getInt` which truncates silently); MS `int` (`SUM(int)` raises arithmetic overflow past 2^31) | `IntExpr` is a 32-bit `Int`, `+` wraps | FRAGILE: `sumBy` of an Int column near 2^31 differs three ways |

## 4. Question 3: `Mem.scala` correctness

Read against `SqlScanner.compileMem` (:378-651) and `relational/package.scala`.

- `GroupByM` (:559): sorts by the key, `Process.groupingBy` on the key map, then instantiates
  the body as a `Literal` per group and compiles it per group (S-22). NULL keys split (S-18).
  Header via `Typer.groupByType` (key ++ body header). Body `let`s are rejected
  ("subqueries of groupBy cannot 'let' new temp tables").
- `AccumulateM` (:509): reads tree and leaves fully into two `Map[PrimExpr, Record]` keyed by
  the node id (a NULL node id can never be looked up: `NullExpr.equals` is false), builds
  descendant lists recursively (no cycle guard: a parent pointing at a descendant loops
  forever), then runs the body per node. Result de-duplicated with `uniq`.
- `Pivot` (:654): requires input sorted by the pass-through columns (it sorts), `outer` is a
  TODO and ignored, the default fills a missing key; the first row of a group evaluates the op
  over the WHOLE row (`prime`) while later rows evaluate over the VALUE columns only
  (`collect`, `o.eval(vr)`) -- consistent only because the Fulcrum type restricts the op to
  the value row. S-10 for the default's type.
- `HashLeftJoin` (:489): builds the outer side into a map, NULL-fills non-key outer columns
  (:493), de-duplicates identical consecutive outer rows only (:767-771, "Alexei" short
  circuit) -- two equal outer rows that are not adjacent still both match, which is what a
  relation (set) would NOT produce twice. S-27 for the header's nullability.
- `MergeOuterJoin` (:444): full outer join by a merge on the key prefix, NULL-fills either side.
  Correct given both inputs sorted by the key (it requests that order).
- `DifferenceM`/`UnionM` (:464-465, `compileMerge`): merge on a TOTAL order over all columns;
  `mergeTee` emits one copy on EQ (set union), `diffTee` drops on EQ. Both correct as sets.
  Note `UnionM`'s header is `h1` and `Typer.unionType` demands `h1 == h2` including
  nullability.
- `LimitM` (:425): S-11.
- `RenameM`'s `promote` flag (Optimizer.scala:169-188): a rename that also makes the column
  nullable (`attr.t.withNull`), lowered to a `ProjectM`; only `Relation.promote` uses it.
- `ProjectM` flattening (Optimizer.scala:78, 244): `ProjectM(ProjectM(m, ics), cs)` inlines
  the inner ops into the outer by `postReplace` -- correct because the outer can only name the
  inner's outputs. `needUniq` (`preservesDistinctness`, SqlScanner:796) is answered by a
  comment as "true too often" -> a `ProjectM` that drops the distinguishing column may keep
  duplicates (READ, a set-semantics leak, low).
- 2.13 views: S-34, none left in the compare/hash positions of the owned files.

## 5. Question 4: the `Fetch` path

- `scanRelation`/`scanRelationInOrder` build `Scan Sort# Relation#` (Layout/Fetch.e:80);
  `relation#` (Lib.scala:826) optimises and closes the plan; the runner executes one
  statement per `Scan`. No fixture scans the SAME relation value twice today
  (`FetchTopN` scans `byRegion` then `targets`; `FetchFragments` scans `sales` and `byRegion`,
  the latter an aggregate OF `sales`, so the fact table is read twice by two different
  statements, which is normal SQL).
- The real repeat is `FetchTabs` (S-24): `sales # {region}` once, then `filterEq region r
  sales` per tab -- K+1 statements over the fact table -- and the `Relation.Scan` grouping
  combinators (S-23), which are N+1 by construction (`groupBy'`: keys, then `rel & k` per key).
- Is there a `memo`/`letR` on the surface that folds two scans? No. `letR`/`materialize`
  scope one plan (a temp table lives for one statement sequence); `memoRel` is a persistent
  table keyed by the plan text and is unusable on SQLite for a second scan in the same
  connection (S-26). The fold that needs no new syntax is the one the fixtures already show:
  scan once (`scanRelationInOrder (ordering {region}) sales`) and split the `List {..r}` in
  Ermine; for TopN-style shapes, `aggregateByGroup` (F-1).

## 6. Question 5: types on the boundary

- Row type (Ermine) -> `Header` (`Map[String, PrimT]`): a record's header is computed from its
  VALUES (`recordHeader`, package.scala:34, via `toPrimExpr`, Runtime.scala:310): `Nullable a`
  values (`Some x` / `Null t`) become `PrimT(nullable = true)`; plain values non-nullable. A
  `Literal`'s header is its FIRST record's (Mem.scala:313); the Ermine type guarantees the rest
  agree. `Maybe` never crosses: the relational nullable is `Nullable` (`Builtin.Some`/`Null`).
- Back: `fromPrimExpr` (Runtime.scala:330) rejects a `NullExpr` at a non-nullable type with a
  `Bottom` ("Null encountered for non-nullable column"); `SqlExecution.nextRecord:95-97` rejects
  a SQL NULL at a non-nullable header with `sys.error`. Every S-08/S-09/S-10/S-27 case is one
  of these two lines firing.
- `Int` is a 32-bit `IntExpr` on the wire: SQLite `integer`, SQL Server `int` (fallback
  `sqlTypeName`, SqlEmitter.scala:1036); `Long` -> `bigint`; `Double` -> `float` / `real`;
  `Date` -> `date` on SQL Server, epoch MILLIS in an `integer` on SQLite (`emitDate =
  d.getTime`, read with `rs.getDate(x, gmtCalendar)`); `Timestamp` -> `datetime2` (MS
  override; the fallback `timestamp` would be SQL Server's rowversion) / `integer`.
- `Field c a` evidence (WP-37): a runtime `Data(Global("Field", name), Array(Prim(PrimT)))`;
  `fieldFun`/`fieldTup` (Runtime.scala:300-308) read the column NAME from the Global's name and
  the type from the payload; `existentialF#` (Lib.scala:491) builds one from a String + PrimT
  at runtime, which is how `Relation.Scan.sumBy` mints its `value#` column and how the typed
  column API names a column. The column name on the wire is exactly the field name (no
  escaping: `rk` in the emitter probe with `order`/`select` names is the emitter role's
  concern).

## 7. Question 1, second half: the `groupBy` rewrite rule (no surface change)

Observed lowering of `groupBy (Row k) f r` (Lib.scala:907-928): `r` is `asMem`'d
(`EmbedMem(ExtRel(rel, db))` when it came from SQL), `f` is applied to `Rel(ExtMem(QuoteMem u))`,
and the body Mem is captured with `unquoteM`. For the three common bodies the captured body is
exactly:

- `groupBy k (sumBy c)`      -> `AggregateM(VarM(MTop), Attribute(c, t), Sum(ColumnValue(c, t)))`
- `groupBy k count`          -> `AggregateM(VarM(MTop), Attribute("Count", IntT), Count)`
- `groupBy k (maxBy c)`      -> `AggregateM(VarM(MTop), Attribute(c, t), Max(ColumnValue(c, t)))`
  (likewise `minBy`, `meanBy`, `standardDeviationBy`, `varianceBy`, `aggregate (weightedMean ..)`).

Rule (in `groupBy#`, after the body is captured): if the body is `AggregateM(VarM(MTop), attr,
agg)` and the source is `ExtMem(EmbedMem(ExtRel(rel, db)))` (or `ExtRel` before `asMem`), answer
`Rel(ExtMem(EmbedMem(ExtRel(AggregateByGroup(rel, keyCols.map(a -> a -> ColumnValue(a)).toMap,
List((attr, agg)), keyCols.map(ColumnValue)), db))))`. The Ermine type stays `Mem kv2`, so no
signature moves; `Typer.groupByType` gives `key ++ {attr}`, the same header
`aggregateByGroupType` gives. Semantics are equal where the two agree today and SQL's where
they do not (S-13, S-18: SQL's are the intended ones; note the change is user-visible for a
NULL-containing group: memory NULL -> SQL sum-of-the-rest). Groups with the body's `attr` also
in the key are rejected by both typers. What the rule does NOT cover: bodies with more than one
aggregate (`groupBy k (r -> ...)` lambdas), `topKBy` (= `groupBy by (topK f k)`, which is a
window `ROW_NUMBER() over (partition by by order by f) <= k`: a second rule for the optimizer),
and anything after the `groupBy` (still `FilterM`/`ProjectM` over the `EmbedMem`). The general
follow-up, for the optimizer role: push `FilterM`/`ProjectM`/`ExceptM`/`RenameM`/`CombineM`/
`LimitM` through `EmbedMem(ExtRel r)` into `r` when the op has a Relation twin (every one of
those does), so that everything after a `groupBy` that SQL can express runs in SQL.

## 8. What the orchestrator must decide

1. S-09 (aggregate over empty input) has no fix without either a visible type change
   (`sumBy : .. -> Nullable a`) or a semantic choice (zero rows vs `coalesce(SUM, 0)`); the
   brief forbids the first. Recommend: zero rows for Min/Max/Avg, `coalesce(SUM(x), 0)` for
   Sum, which is what memory already answers for Sum.
2. S-16 (case-insensitive memory strings): making memory case-sensitive changes results for
   any report that relied on it under `groupBy`; SQL Server's default collation stays
   case-insensitive either way. Recommend case-sensitive (matches SQLite, the default runner,
   and repairs the hashCode/equals contract).
3. S-20's rule changes NULL handling in `groupBy k (sumBy c)` from "NULL if any" to SQL's
   "sum of the rest" -- the intended meaning, but a visible change; the differential oracle
   should carry a NULL-in-group case before adoption.
