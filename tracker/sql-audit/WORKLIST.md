# SQL audit worklist (triage of FINDINGS-{emitter,lowering,optimizer,surface}.md, 2026-09-26 23:45)

Four implementers, partitioned by file. Items cite finding ids; read those rows and sections
before touching anything. Priority is the order within each area: WRONG first. An implementer
who runs out of budget stops at a clean point and says which items are undone.

## Decisions taken by the orchestrator (binding for every implementer)

| # | Decision | Why |
|---|---|---|
| D1 | Where the in-memory evaluator (`Op.eval`, `Predicates.toFn`, `AggFunc`, `Mem`) and SQL disagree, **SQL's semantics is the reference**: three-valued comparisons (a comparison with NULL is unknown; a filter drops unknown rows; `not unknown` is unknown), SUM/AVG/MIN/MAX skip NULLs, GROUP BY puts all NULL keys in one group. The in-memory side is changed to agree. | Production runs in SQL; the in-memory paths exist only to finish what SQL cannot, and one report can run both ways (S-14, S-13, S-18). |
| D2 | An aggregate over an empty input: **SUM and COUNT give 0; MIN, MAX, AVG, STDDEV, VARIANCE give no row**, on both paths. SQL: `coalesce(sum(..), 0)`; for the others the ungrouped aggregate gets `having count(*) > 0`. Grouped aggregates are unchanged (an absent group is absent). | Today SQL yields one NULL row into a non-nullable column and the read throws (L-6, S-09, E-13); no visible type changes. |
| D3 | Strings in memory stay **case-insensitive** for equality and ordering (as they are), and `hashCode` is made consistent (hash of the lower-cased value); `minMonoid`/`maxMonoid` use the same order. Nothing language-wide. | equals/hashCode is a broken contract today (S-16, L-13, S-29); the case-insensitive order mirrors SQL Server's default collation, the production database. Making it case-sensitive is the user's call, not ours. |
| D4 | `Typer` marks the nullable side of an outer join **nullable** in the header; a NULL default in `pivot` types nullable. Header-level only; the JSON wire then carries `null` where it used to throw. | O-11, S-27, L-18, S-10. |
| D5 | Nested set operations get explicit grouping in the **scanner** (dialect-independent), not by parenthesising in each emitter. | L-2. |
| D6 | `NaN` and `Infinity` doubles are emitted as `NULL` on every dialect (SQLite already turns x/0.0 into NULL; SQL Server float cannot hold infinity). | E-10, F-4. |
| D7 | `groupBy k (sumBy c)`, `groupBy k count`, `groupBy k (minBy/maxBy/meanBy c)` over a `Relation` operand lower to `AggregateByGroup` when the body is exactly one aggregate over the group and nothing else. No surface change. NULL sums then follow D1. | S-20, OBSERVABILITY §9. |
| D8 | Optimisations that change SQL shape (C9-C12, E16, E17) are adopted only with the unchanged-results evidence `brief-impl-common.md` lists. | PLAN.md scope rules. |
| D9 | Deferred to the user (not worked tonight): language-wide string collation; `firstK` with no order sorting by every column (L-14) and unordered scans carrying dialect order into documents (L-15); pivot `outer` (L-22); `memoRel` persistence design beyond the hash fix (S-26, L-10); the Fetch N+1 and K+1 statement shapes (S-23, S-24) and a headline that aggregates in SQL (O-24), which need surface additions; MySQL/Postgres/Vertica live testing (E-14, F-7 text-only); a decimal type (F-8); `##` vs `#` temp names (L-11). | Each needs a user-visible choice or a surface addition. |

## Area `rel` (impl-rel): `relational/Rel.scala`, `Optimizer.scala`, `Typer.scala`, `Ext.scala`, `ReportingUtils.scala`, `ermine/session/Lib.scala` (relational functions), stdlib `.e` (private helpers only)

| item | findings | what |
|---|---|---|
| R1 | O-1 L-1 S-01 | `JoinOn.bimap/subst/unquote` keep `mode`. Pin: outer join under `letR`/`letRWithPK`/`materialize`, and a mixed Rel/Mem outer join. |
| R2 | O-7 S-02 | `leftJoinOr`/`joinWithDefault`/`rightJoinWithDefault` inside a `letR`/`groupBy`/`accumulate` body panic "header of a quote": let the quote carry the bound relation's header (the binder knows it) or make `projectEach` not need it. |
| R3 | S-03 | outer joins against `relation []` keep the other side's columns. |
| R4 | O-11 S-27 L-18 S-10 | D4 in `Typer` (joins, pivot default). |
| R5 | O-6 S-25 | `Minus.apply`'s `p1 AND NOT p2` rewrite only when `p2`'s columns are non-nullable (else `NOT p2 OR <a column of p2> IS NULL`); then `filterNEq`'s shape `Minus(R, Filter(R, p))` folds to one filter under the same guard. |
| R6 | O-9 S-30 | `x == x` folds to TRUE only over non-nullable columns. |
| R7 | O-10 | aggregate coalescing in `Join.apply` only when the group columns are non-nullable. |
| R8 | S-20 (section 7) | D7 in `groupBy#`. Evidence: a doc fixture that uses `groupBy k (sumBy c)` rendered through `TestRunner` before/after (same document) and its `RenderTrace` rows read. |
| R9 | O-18 | delete helpers with zero callers, last, if time remains. |

## Area `scanner` (impl-scanner): `relational/SqlScanner.scala` EXCEPT lines 64-190, `sql/SqlExecution.scala`, `relational/package.scala`, `Mem.scala`, `Scanner.scala`

| item | findings | what |
|---|---|---|
| C1 | L-2 | D5: wrap a `SqlNaryOp` operand of `union`/`minus` in a select. |
| C2 | L-3 O-3 | `squashLiteral` never pushes into a windowed select. |
| C3 | O-4 | outer joins do not merge the nullable side's select list (constants/coalesces must be NULL on unmatched rows). |
| C4 | L-4 | Limit reflexivity constant iff `t - f < 1`. |
| C5 | L-7 S-11 O-8 L-9 | `LimitM` 1-based inclusive like `Sort.e` and SQL; honours the requested order. |
| C6 | L-6 S-09 E-13 | D2 on the SQL side (`aggregate`); the emitter does `cast(NULL as type)` in `emitEmpty` (E12), you do the coalesce/having. |
| C7 | L-12 | close the statement when `executeQuery` throws; `cleanTempTables` also on failure. |
| C8 | L-10 O-23 | memo/let temp names hash the literal's CONTENTS, not its size. |
| C9 | O-25 L-21 | one temp table per distinct let-bound relation value within a scan (content-keyed like `MemoR`). Evidence: statement count on `Algebra.Helpers.closure` (survey) and the oracle-style equality. |
| C10 | O-12 O-26 L-19 | distinctness requested only when needed; no DISTINCT on an EXCEPT arm; a projection of a group result onto its keys needs none. |
| C11 | O-15 | a filter over a union is pushed into each arm. |
| C12 | S-22 | `GroupByM` compiles its body once. |
| C13 | W-2 | `SqlExecution.nextRecord` resolves column index and type once per result set. |
| C14 | L-8 | merge/difference/group over SQL-backed Mems with string keys: sort in Ermine when the SQL order may differ. If time remains. |

## Area `emitter` (impl-emitter): `sql/*.scala`, `SqlScanner.scala` lines 64-190 (`compileOp`, `compileAggFunc`, `compileWindowFunc`, `compilePredicate`), `core/src/test/.../sql/TestSqlEmitters.scala`

| item | findings | what |
|---|---|---|
| E1 | E-1 F-2 | SQLite window functions: `EmitOver_UsingOver` + the missing space before the direction. |
| E2 | E-3 S-07 | `dateAdd`/`dateDiff` on SQLite through two new emitter hooks called from `compileOp`; results INTEGER millis (N-9); SQL Server text unchanged. |
| E3 | E-4 S-06 | SQLite stddev/variance (population and sample) from `avg`/`count`. |
| E4 | E-5 E-6 | SQLite quotes column names (round trip in `unemitColumnName`); nested joins parenthesised (lift MySQL's override to a trait). |
| E5 | E-7 S-05 L-5 N-4 | offset without a bound: SQLite `limit -1 offset n`, MySQL its max. |
| E6 | E-8 | SQL Server string literals `N'...'`. |
| E7 | E-9 S-15 | SQLite double `//` = `floor(floor(a)/floor(b))` like memory and SQL Server. |
| E8 | E-10 F-4 | D6. |
| E9 | E-11 E-12 | SQLite timestamp literals as INTEGER millis; casts between Date/Timestamp and String/Int agree with `PrimExpr.cast` in memory (state the rule you implement). |
| E10 | E-13 | `emitEmpty` types its NULLs. |
| E11 | F-1 | SQL Server date/timestamp literals via `CAST(... AS DATE/DATETIME2)`. |
| E12 | F-5 F-6 | `nvarchar(max)` for unbounded strings; `NUMERIC` decodes as DoubleT; `uniqueidentifier` as UuidT. |
| E13 | W-1 O-16 N-6 | SQLite literals as `VALUES`. |
| E14 | O-17 | `<=`/`>=` emitted directly for `Or(Lt(a,b), Eq(a,b))` with identical operands (in `compilePredicate`). |
| E15 | O-5 | nested `if` compiles to a faithful nested CASE (no `case when not t` merge). |
| E16 | W-3 L-11 | SQL Server drops its temp tables (`EmitDropTempTable_AsDropTable` on `MsSqlEmitter`). |
| E17 | S-08 | SQLite `\|\|` coalesces nullable operands to `''` so `show`/`++` agree with memory and SQL Server. |
| E18 | E-2 | SQLite `tryCast`. |
| E19 | E-14 | Vertica limit, text-level only, last. |
| E20 | N-1 | `TestSqlEmitters`: rewrite the pins the above move; fix the joinOn generator. |

## Area `prims` (impl-prims): `Op.scala`, `Predicate.scala`, `PrimExpr.scala`, `PrimT.scala`, `AggFunc.scala`

| item | findings | what |
|---|---|---|
| P1 | S-04 O-2 | `logBase` with any base (no MatchError), in memory and in `builtinSimplify`. |
| P2 | S-16 L-13 S-29 S-18 | D3; `NullExpr` equals `NullExpr` of the same type (grouping), comparisons stay 3VL via P3. |
| P3 | S-14 | D1 for `Predicates.toFn` and the comparison builtins. |
| P4 | S-13 | in-memory sum/avg/min/max skip NULLs; empty input per D2 (sum 0, avg/min/max no row: coordinate with `scanner` on where a Mem aggregate yields "no row"; post the interface on the board). |
| P5 | S-12 | in-memory variance/stddev formula. |
| P6 | S-17 | `cast` to Byte. |
| P7 | S-19 S-28 | in-memory `dateDiff` for day/week/month/year on the GMT calendar; `incrementTimestamp` in GMT. |
