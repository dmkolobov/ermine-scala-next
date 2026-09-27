# report-impl-prims: the in-memory evaluator agrees with SQL (worklist area `prims`, P1-P7)

Role `impl-prims`, 2026-09-26 23:33 - 2026-09-27 00:01 (2.5 h budget used of 3).  Worktree `ermine-scala-wt-sql-prims`,
branch `sql-prims`, NOT committed (the orchestrator commits after review).  Decisions applied:
D1 (SQL's three-valued comparisons and NULL-skipping aggregates are the reference), D2 (empty
input: SUM/COUNT 0, the others no row), D3 (strings stay case-insensitive; the hash follows).

## Files touched

| file | why |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/Op.scala` | P1 `builtinSimplify`; P7 `DateDiff` eval, `TimeUnit.boundariesBetween`, GMT calendars |
| `core/src/main/scala/com/clarifi/reporting/PrimExpr.scala` | P2 `hashCode` for every constructor, `NullExpr.equals`, `sumMonoid` skips NULL, string min/max order, P6 cast to Byte, strict cache equality |
| `core/src/main/scala/com/clarifi/reporting/Predicates.scala` | P3 `toFn3` (three-valued) and `toFn` on top of it |
| `core/src/main/scala/com/clarifi/reporting/AggFunc.scala` | P4/P5 avg/min/max/variance/stddev/wmean/whmean: NULL-skipping, no row on empty input, one NULL on all-NULL |
| `core/src/main/scala/com/clarifi/reporting/Cache.scala` | NOT on the worklist: `SetAssociativeCache` takes a `same` comparison. Needed by P2: the cache canonicalizes by `==`, which after D3 ignores case and the nullable flag, so without it `StringExpr(false, "A")` could come back as the cached `"a"` (a latent 1-in-16384 bucket collision today, systematic after P2). 11 lines. |
| `scalacheck-binding/src/main/scala/TestPrimSemantics.scala` | NEW: 23 properties, memory vs the SQLite scanner on the same literal where a twin exists |

## Per item

| item | status | what changed | test (TestPrimSemantics) | what a report author notices |
|---|---|---|---|---|
| P1 (S-04, O-2) | DONE | `builtinSimplify`'s `LogBase` branch (matched only a literal base 1, answered 0, `MatchError` otherwise) deleted; `logBase` folds like every builtin; `asNum` gone | "P1: logBase x b folds and evaluates ..." (100 random x, bases incl. 1.0), "P1 pin: logBase 8 2 = 3, also when the base is a column" | `logBase x b` no longer crashes the compile of any relation that mentions it (every dialect and memory). `logBase x 1` is Infinity/NaN, as `log x / log 1` is, instead of 0. |
| P2 (S-16, L-13, S-29, S-18, D3) | DONE | `PrimExpr.hashCode` is a function of what `equals` compares (string: lower-cased value; no nullable flag; NULL: its type); `NullExpr == NullExpr` of the same type; `minMonoid`/`maxMonoid` compare strings lower-cased; canonicalizing caches compare fields | "P2: equal PrimExprs hash alike", "P2 pin: a/A one key, nullable 1 = strict 1, NULL = NULL of its type", "P2: the string cache never hands back ...", "P2 (S-18): projecting onto a NULL-able key ... in memory as in SQL" (vs SQLite), "P2 (S-29): minBy/maxBy on strings ..." | In-memory `groupBy`, `uniq`/distinct projections and hash joins now treat "a" and "A" as ONE key (they were one key for `==`, `sort`, `min`, `max` already; only the hash split them). NULL keys form ONE group / one distinct row, as SQL's GROUP BY and DISTINCT do (each NULL used to be its own group). `minBy`/`maxBy` on strings agree with `<`. |
| P3 (S-14, D1) | DONE | `Predicates.toFn3: Record => Option[Boolean]` (None = UNKNOWN; Kleene and/or, `not` of unknown is unknown, comparisons with a NULL side unknown); `toFn` keeps only TRUE; `If` in `Op.eval` therefore takes the alternate on unknown, like CASE | "P3: an in-memory filter keeps the rows SQLite keeps" (random rows with NULLs x random predicates, depth 3, vs SQLite), "P3 pin: n < 2 and not (n == 1) drop a NULL row", "P3: if takes the alternate when its test is unknown" | An in-memory filter (`filter` after `groupBy`, or on any `Mem`) on a nullable column DROPS the NULL rows for `<`, `>`, `!=`, `not (..)`, as SQL does; before, `n < 2` and `n != 1` kept them. `isNull` is the way to keep them, on both paths. |
| P4 (S-13, D1, D2) | DONE | `sumMonoid.append` skips NULL; `avg`/`min`/`max`/`wmean`/`whmean` fold with a row count: empty input emits NOTHING, all-NULL emits one NULL, NULL inputs skipped; `Sum`/`Count` answer 0 on empty. The scanner's `AggregateM` case needs no change (interface posted on the board 23:46). `AggFunc.reduce` (StateScanner only) unchanged | "P4: sum/avg/min/max/count in memory equal SQLite's over rows with NULLs" (vs SQLite), "P4 pin: sum and avg skip NULLs", "P4 (D2): over an EMPTY input ...", "P4 (D2): over rows that are all NULL ...", "P4: the weighted mean skips ..." | `sumBy`/`meanBy` over a nullable column evaluated in memory answer the sum/mean of the non-NULL values (before: NULL if any input was NULL). `meanBy`/`minBy`/`maxBy`/`standardDeviationBy`/`varianceBy` over NO rows in memory now answer NO row (before: one row holding NULL, or for `meanBy` over Ints a division-by-zero exception); `sumBy` and `count` still answer 0. |
| P5 (S-12) | DONE | population variance `(Σx²/n) - (Σx/n)²` in doubles over the non-NULL values, typed back with `mkExpr(_, t)` as `stddev` always was; stddev its root | "P5: in-memory variance is the population variance ...", "P5 pin: variance of 1,2,3,4 is 1.25 (was -890)" | `varianceBy`/`standardDeviationBy` evaluated in memory answer the population variance / standard deviation (`VAR_POP`/`VARP`, `STDDEV_POP`/`STDEVP`, what SQL emits). Before, variance was `Σx - (Σx²)²`, a large negative number, and stddev its square root, NaN. |
| P6 (S-17) | DONE | `cast` to `ByteT` builds a `ByteExpr` | "P6: cast x Byte builds a Byte" | `cast x Byte` in memory is a Byte, not a Short. |
| P7 (S-19, S-28) | DONE | `Op.eval` `DateDiff`: every unit via `TimeUnit.boundariesBetween` (SQL Server's `datediff`: unit boundaries crossed on the GMT calendar; day = GMT midnights, week = Sundays, month/year = calendar boundaries, second/ms = floor-division boundaries), NULL in -> NULL out; `incrementTimestamp`/`increment` use a GMT calendar | "P7: dateDiff ... every unit, antisymmetrically, NULL for a NULL end", "P7: dateDiff day = GMT midnights crossed; month/year ...; week = Sundays" (random instants 1860-2079), "P7 pins: SQL Server's datediff answers on known dates", "P7 (S-28): dateAdd by days is exact multiples of 86400000 ms", "P7 pins: dateAdd across the 2024-03-10 DST change, and a month onto January 31st" | `dateDiff days/weeks/months/years` evaluated in memory (a `combine` under a `Mem`) works, answering what SQL Server's `datediff` answers, instead of throwing "datediff is meant to be used from SQL". `dateAdd` in memory no longer shifts by an hour across this machine's DST change (it was computed in the JVM's zone, formatted in GMT). |

## Departures from the worklist, with reasons

- `Cache.scala` edited (see the files table): a fix P2 needs; no one owns the file.
- P7 dateDiff semantics: the worklist says "on the GMT calendar"; SQL Server (production) counts
  boundary crossings, E-3's SQLite formula (`julianday` difference, emitter's item E2) counts whole
  days.  Memory follows SQL Server; for date-typed values (midnight) the two coincide.  Posted for
  impl-emitter on the board (23:46) with the SQLite text that would make the dialects agree.
- The empty-input SQL side (`coalesce`/`having`) is the scanner's C6: `TestPrimSemantics`'s D2
  properties are memory-only pins; the twin comparison (`P4 ... equal SQLite's`) is restricted to
  inputs with at least one non-NULL value, where SQL is settled today.
- No `TestSqlDifferential` exclusion flag removed: the oracle's suite is not in this tree (it lives
  in `ermine-scala-wt-sql-oracle`); nothing in its exclusion list is a `prims` class.

## Gates (each once)

| gate | result | log |
|---|---|---|
| 1 compile + copyResources + Test/compile | PASS (`compile-1.log`, `test-prims-4.log`: `[success]`) | `scratch-sql-audit/prims/compile-1.log`, `test-prims-4.log` |
| 2 suites (TestSqlEmitters, TestInMemoryScan, TestDateAndScan, TestRunner, TestRenderTrace, TestErmine, TestDoc, TestWidgets, TestRecordPrims, TestPrimSemantics) | PASS: `Passed: Total 167, Failed 0, Errors 0, Passed 167`, exit 0 (23:52-23:57) | `scratch-sql-audit/prims/gate2.log` |
| 3 live SQL Server (TestDbReports + TestMsSqlSmoke, ERMINE_DB_* set, server at tier s) | `Failed: Total 10, Failed 8, Passed 2`, exit 1. Green: TestMsSqlSmoke "driver resolves", "live connect". Red: all 8 TestDbReports mssql properties (7 "renders the same document (tier xs)" + "the pinned totals"). ATTRIBUTED BY INSPECTION, not by a baseline run: every twin document carries tier s's regions (`china`, `france`, `germany`, `japan`, `united-kingdom`, `us-midwest`) where the in-memory original carries xs's (`east`, `north`, `south`, `west`), and the headline for `onlyRegion=north` answers rowCount 0 on the twin (tier s has no `north`), so no "same document" property can be green until the database holds tier xs again; the reds are the data, not the evaluator. | `scratch-sql-audit/prims/gate3.log` |
| 4 corpus | PASS: `SUMMARY 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected` (batch, one JVM, exit 0) | `scratch-sql-audit/prims/corpus-run.log`, `prims/corpus/` |
| new suite alone | PASS: `TestPrimSemantics` 23/23 (`test-prims-5.log`) | `scratch-sql-audit/prims/test-prims-5.log` |
| differential oracle (orchestrator's request; `TestSqlDifferential` + `scripts/gates.sh` taken from `sql-audit` a1be6aa2, exclusion list untouched) | PASS on SQLite, plain flags: `random relations: reference == SQLite: OK, passed 300 tests`; coverage OK; 576 generated, 15 discarded; `Passed: Total 2` (23:58-23:59). Its reference reuses `Op.eval`/`Predicates.toFn`, so P2/P3 keep it green. `mixedCase` not attempted (D3/D9). | `scratch-sql-audit/prims/oracle-sqlite.log` |

Note on zinc: the first compile after the edit did NOT recompile `Op.scala` (its class file was
0.6 s older than the source; sbt's stamp missed a write that landed during the warm compile), so
`test-prims-2/3.log` show the OLD dateDiff/logBase behaviour.  A content change forced the
recompile (`test-prims-4.log`, "compiling 1 Scala source ... classes").  Anyone re-running: check
`javap ... TimeUnit | grep boundaries` if a P7 property throws "datediff is meant to be used from SQL".

## Review MUST-FIX 1 (review-prims, board 00:36): P2's tests could not see the hash fix

Done 00:4x: the P2 pin uses `HashSet`/`HashMap` explicitly (a `Set`/`Map` of up to four elements
never hashes) and asserts `NullExpr.equals`/`canEqual` directly; the hash-alike property draws
DELIBERATELY equal pairs (other case, other nullable flag, the one NULL of a type) and then random
pairs; the two properties that hold pre-fix are named "guard" and say why (the string cache is a
post-P2 guard; S-18's NULL grouping was ALREADY one row per NULL key, by `NullExpr`'s one instance
per type and generic `==`'s reference shortcut -- S-18 as READ predicted otherwise; the suite header
says so).  `PrimExpr.equalsIfNonNull` (zero callers after P3) deleted; the `NullExpr` comment now
names `Predicates.compare3` and states what the `equals` change does and does not change.

| run | result | log |
|---|---|---|
| revised suite on the fixed tree | `Passed: Total 23, Failed 0` | `scratch-sql-audit/prims/test-prims-6.log` |
| reverse mutant: unfixed base `ermine-scala-wt-sql-audit` (a1be6aa2) + a temporary copy of the revised test file (removed afterwards; that tree is clean) | `Failed: Total 23, Failed 16, Errors 5, Passed 2`; the two greens are the two "guard" properties | `scratch-sql-audit/prims/mutant-2.log` |

## Properties whose answer changed

None in an existing suite: gate 2 is 167/167 green (TestErmine 27, TestRunner/J3c 44, TestDoc/J3b 22, TestWidgets/J3d 8, TestDateAndScan 13, TestInMemoryScan 5, TestRecordPrims 8, TestRenderTrace 8, TestSqlEmitters 5, TestPrimSemantics 23), the corpus verdicts are unchanged (0 of 168 differ) and the differential oracle is green on SQLite.  No fixture in `core/src/test/resources/doc` runs an aggregate, a filter on a nullable column, `dateDiff` or `logBase` in memory over data that exercises the changed cases, so the behaviour changes above (per-item table, last column) are visible only through `TestPrimSemantics`, whose 23 properties all fail on the pre-fix compiler (each names the old answer).  Gate 3's 8 reds are the tier-s data (see the gate table), not a changed answer.

## Open issues and questions for other areas (all on the board, 23:46)

1. impl-rel (R6, `ReportingUtils.simplifyPredicate:42`): with `NullExpr == NullExpr`,
   `Eq(OpLiteral(NULL), OpLiteral(NULL))` (reachable when `simplEnv` substitutes a column known to be
   constant NULL) folds to `Atom(true)`; the R6 guard must also exclude a NULL literal on either
   side.  Today both evaluators agree on the (wrong) fold, so `TestPrimSemantics` does not see it;
   after rel's fix the SQL side will be right and memory follows through the same `simplifyPredicate`.
2. impl-scanner (`hashJoin`, `HashLeftJoin`, `AccumulateM`): NULL join keys now MATCH each other in
   the hash paths (SQL: never).  `MergeOuterJoin` already matched them through `Order`.  Not pinned.
3. `AggFunc.reduce` (used by `StateScanner` only) still folds to one NULL over an empty input; the
   SQL-backed path (`reduceProcess`) is the one D2 governs.
4. Ints: `sumMonoid` still wraps at 2^31 (section 3 note: SQLite 64-bit, SQL Server raises); not in scope.
