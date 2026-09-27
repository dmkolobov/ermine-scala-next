# report-impl-scanner (SQL audit, area `scanner`, 2026-09-26/27)

Worktree `ermine-scala-wt-sql-scanner`, branch `sql-scanner`, uncommitted. Items C1-C14 of
`WORKLIST.md` plus two oracle findings that live in my files (marked "extra").

## Files touched

| file | items |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/relational/SqlScanner.scala` (outside lines 64-190) | C1 C2 C3 C4 C5 C6 C7 C9 C10 C11 C12, extra O-2 O-9 |
| `core/src/main/scala/com/clarifi/reporting/sql/SqlExecution.scala` | C7 C13 |
| `core/src/main/scala/com/clarifi/reporting/relational/Mem.scala` | C8 (`Literal.toString`/`contentDigest`), C12 (`Mem.hasMemo`) |
| `scalacheck-binding/src/main/scala/TestSqlScanner.scala` (new) | every item's pin + property |

## Per item

Every test FAILS on the pre-fix compiler (the pre-fix answer is named in each property);
"LIVE" = scanned on in-memory SQLite, "TEXT" = the emitted SQL's shape (`topLevel` = the text with
parenthesised groups removed).

| item | what changed | test | plain-language sentence |
|---|---|---|---|
| C1 (L-2, D5) | `DistinctiveQuery.union`/`minus`: a RIGHT operand that is a set operation of another kind (union) or any set operation (minus) is wrapped in a select (`groupedRight`), dialect-independent. Left operands stay flat (left-to-right reading is right for them). | TEXT: random union/difference trees never mix operators at one level (SQL Server text); pins for right-nested vs left-nested difference; LIVE: results equal a set-semantics reference. | `union r1 (difference r2 r3)` and `difference r1 (union r2 r3)` now answer the set algebra on SQL Server (they answered the left-to-right reading; SQLite was already right). |
| C2 (L-3, O-3; extra oracle O-15) | `squashLiteral` wraps a windowed OR aggregated select before adding the literal's equality; the predicate is a plain WHERE on the wrapper (no more `having` path). | TEXT: no `over` and no `having`/`group by` at the top level next to the `where`. | `filterEq k 1 ranked` ranks first and filters after (it filtered first, so a rank of 2 became 1); `join (relation [{y = 1}]) ranked` no longer fails on SQL Server. |
| C3 (O-4) | `joinOn`: the NULL-padded side of a LEFT/RIGHT/FULL join is merged into the join's select only when its select list is plain column references (`plainColumns`), else it is a subquery. | LIVE: random left join with a constant column on the right: unmatched rows carry NULL; FULL join with coalesce on both sides. | An unmatched row of an outer join now carries NULL in the other side's computed/constant columns (it carried the constant). |
| C4 (L-4) | `Limit` reflexivity: one row iff `t - f < 1`. | LIVE: `project {k} (limit (Just f) (Just f+1) r)` has no duplicates. | A projection over an explicit two-row range dedupes again. |
| C5 (L-7, S-11, O-8, L-9) | `LimitM`: 1-based inclusive (`dropping(start-1)`, `taking(stop-start+1)`); sorts by every column when no order is given (as SQL does); re-sorts to the consumer's order. | LIVE: Mem limit equals the sorted-positions reference for random (start, stop); consumer order honoured. | `limit o (Just 2) (Just 3) m` on an in-memory relation answers rows 2 and 3 (it answered row 3); `(Just 1) (Just 1)` answers one row (it answered none). |
| C6 (L-6, S-09, E-13; D2) | `aggregate`: SUM -> `coalesce(SUM(x), <typed 0>)`; MIN/MAX/AVG/STDDEV/VARIANCE/WMEAN -> `having count(*) > 0`; COUNT unchanged. Grouped aggregates unchanged. | LIVE: over no rows SUM/COUNT = 0, MAX/MIN/AVG = no row; over rows unchanged. | `sumBy x (filter p r)` over nothing answers 0 and `maxBy`/`meanBy` answer an empty relation, instead of a decode error. |
| C7 (L-12, L-11) | `SqlExecution`: the statement is closed when `executeQuery` throws. `scanRel`/`scanMem`: `DB.ensure(..., cleanTempTables)` so temp tables are dropped on failure too (effective once an emitter drops them: E16). | LIVE with a JDBC proxy: a rejected query closes its statement; a failing let-scan leaves 0 temp tables under a dropping emitter. | No user-visible change; one fewer leaked statement per failed render. |
| C8 (L-10, O-23) | `Literal.toString` prints size AND a SHA-1 of the rows (`contentDigest`, lazy); `MemoR` and let-scope hashes are built from `toString`. | `compileRel`: two memo relations differing only in a literal's rows get different `MemoHash_` names; equal rows, equal name. | `memoRel` over relations that differ only in an in-memory literal's rows no longer share a table (the second read the first's rows). |
| C9 (O-25, L-21) | `LetCache` (per scan, an implicit through `compileRel`/`compileMem`/`compileMerge`): a CLOSED `LetR` (its `ext` mentions no bound variable) is materialised once per scan and its statements reused, so `sequenceSql`'s `distinct` runs them once. Scope-dependent lets compile per visit as before. | TEXT+LIVE: a let referenced twice yields one CREATE and the right rows; a nested scope-dependent let still compiles in its scope. | `materialize r` used n times fills one temp table instead of n (the `closure` helper filled 3^depth). |
| C10 (O-12, O-26, L-19) | `project`/`except` ask the inner query for distinctness only when the consumer needs it and the projection passes it on; `minus` asks nothing of its left arm and answers "distinct" (EXCEPT is a set on every dialect but MySQL's join emulation, which keeps the old shape); a projection keeping every GROUP BY column (`keepsGroupKey`) needs no DISTINCT. | TEXT: 0 `distinct` under union arms, except arms and group-key projections (SQL Server); LIVE: those shapes equal the set-semantics reference and deliver each row once. | No visible change; fewer `select distinct` passes (four per `melt`, one per `antiJoin`, one per key projection of a `groupBy`). |
| C11 (O-15) | `filter` over a `UNION` pushes the predicate into every arm. | TEXT: one where per arm, none at the top; LIVE: equals reference. | No visible change. Cost claim UNMEASURED: both live planners probably push it themselves; a D8 call. |
| C12 (S-22) | `GroupByM`: the body is compiled ONCE against a placeholder that reads the current group's rows (`AtomicReference[Literal]`), with reflexivity `r && keys constant`; a body holding `letM`/`MemoMem` (memo on the node) keeps the per-group path (`Mem.hasMemo`). | `compileMem` call count is the same for 2 and 12 groups (a counting subclass); rows right; a `letM` body still answers per group. | No visible change; `groupBy` over many groups compiles its body once. |
| C13 (W-2) | `SqlExecution.nextRecord`: labels and column types resolved once per result set (`columnTypes: IndexedSeq[PrimT]`). | JDBC proxy: `getColumnLabel` called at most 2 x columns for a 40-row scan (was 2 + 2n). | No visible change. |
| C14 (L-8) | NOT DONE, deliberately: the only in-file fix is a full in-memory re-sort of every SQL-backed Mem side whenever the order has a string column (2 M rows for `groupBy {region}` at tier l) to cover a case-collation edge that D9 defers to the user. Left for the collation decision. | | |
| C15 (oracle O-14, wave 2) | `preservesDistinctness.columnDistinctness`: only a bare `ColumnValue` carries a column's distinctness (any other single-column op could be non-injective). | LIVE: `project {p = coalesce s 'b'}` over {b, NULL} answers one row. | A projection through `coalesce`/`if`/`upper`/... dedupes (it could deliver duplicates). |
| C16 (oracle O-28, wave 2) | `joinOn`: an outer join whose join columns include a nullable one never claims distinct output. | LIVE: FULL JOIN of a NULL-keyed row with itself answers one row. | A full join over a nullable key no longer delivers its coalesced padding rows twice. |
| C17 (oracle O-26, wave 2) | `limit`: only `(1, 1)` may take a non-distinct input; every other range asks for one and makes it distinct itself when the inner cannot (a duplicate literal). | LIVE: `limit (Just 2) (Just 2)` over the bag [1,1,2] answers 2. | A one-row `limit` past the first position counts positions in the set. |
| C18 = extra O-9, C19 = extra O-2 (wave 2) | see the two rows below | | |
| C20 (oracle O-19, wave 2) | `LetR` whose body never mentions `RTop` compiles the body alone: no temp table. | TEXT+LIVE: an unused let over a missing table makes no CREATE and the scan answers the body. | An unused `materialize`/`letR` binding costs nothing (it filled a temp table). |
| C21 (orchestrator, after prims P2) | D1 for the in-memory joins: `hashJoin` drops NULL-keyed rows on both sides, `leftHashJoin` treats them as unmatched, `MergeOuterJoin` compares under an order where two NULL-bearing keys are never EQUAL (each side's row comes out padded), `AccumulateM` never looks a NULL id up. | LIVE: hash inner/left joins over NULL keys; the merge outer join answers exactly what SQLite's FULL JOIN answers on the same literals. | A NULL join key never matches in memory, as it never does in SQL (in memory NULL matched NULL). |
| D4 wire (impl-rel's note) | `joinOn`'s header types the padded side's non-join columns nullable (`padded`), so an unmatched outer-join row decodes; a local equivalent of impl-rel's `Typer.joinHeader`, which my tree lacks. | LIVE: an unmatched LEFT JOIN row with a non-nullable constant on the right decodes to null. | `unsafeLeftJoin` with unmatched rows renders (null cells) instead of failing with "Unexpected NULL". Land together with C3. |
| extra oracle O-2 | `DistinctiveQuery.literal` answers distinct only when the rows are (`rows.distinct.size == rows.size`). | TEXT: a duplicate literal gets one DISTINCT, a clean one none. | A `relation [...]` literal with duplicate rows delivers each row once on SQL Server. |
| extra oracle O-2 via aggregates and lets (found by the flagged oracle in gate 3) | `aggregate`/`aggregateByGroup` ask the inner query for distinctness and now HONOUR the answer (`satisfyDistinct` first); `LetR`/`MemoR`/`TableProc` fill their tables from `distinctQuery` (the same). | TEXT: `count` over a duplicate literal and a `let` over one carry a DISTINCT on SQL Server; LIVE: SQLite count = 2 over [(1,1),(1,1),(2,3)]. | `count`/`sumBy`/`groupBy` and `materialize` over a `relation [...]` with duplicate rows treat it as a set on SQL Server (they counted/kept the duplicates). |
| extra oracle O-9 | `project`/`except` wrap an UNGROUPED aggregate select when the projection references none of its columns (`dropsUngroupedAggregate`). | LIVE: `project {p = 3} (count r)` answers ONE row over three rows and over none. | A projection of only constants over an aggregate answers one row (it answered one per input row). |

## Review fixes (review-scanner, 00:52)

- Must-fix: the FULL join header types a shared join column nullable iff EITHER side's is (`Typer.joinHeader`'s
  rule); pinned "(C22) a FULL JOIN's shared key ..." executed on SQLite. Should-fix: `LetCache.key` renders
  Date/Timestamp by `getTime` millis. One run of `TestSqlScanner`: 36/36, `scratch-sql-audit/scanner/review-fix.log`.

## Departures from the worklist

- C2 also stops squashing into an AGGREGATED select (oracle O-15's mechanism, dialect-independent).
- C10 (b) detects the MySQL join emulation with `emitter match { case _: EmitNary_ExceptAsJoin => .. }`
  rather than a new emitter method (the emitter file is another area's).
- C12 falls back to the old per-group compile when the body holds `letM`/`MemoMem`, since the memo
  lives on the node and a once-compiled body would replay the first group's rows.
- C14 left undone (see its row).
- `core/src/test/scala/com/clarifi/reporting/DebugBackend.scala` (not in my list): two `implicit val letCache` lines, needed by the new `compileRel` implicit; CRLF kept.
- `TestSqlDifferential.scala` and `scripts/gates.sh` taken from `sql-audit` unchanged (not edited).

## Gates (each once per final tree; logs under `scratch-sql-audit/scanner/`)

Runs before the last two edits (the O-2-through-aggregate/let fixes) are in `gate12.log` (double JVM, unreliable),
`gate2.log`, `gate3.log`, `gate4.log` (both partly double-written by a chain I failed to kill cleanly: one
worktree ran two sbts for a few minutes twice; results below are from the clean single-sbt runs).

| gate | log | result |
|---|---|---|
| 1 compile + copyResources + Test/compile | `final2-gate2.log` | green (`[success]` for compile, copyResources and Test/compile; started 00:26:47) |
| 2 suites | `final2-gate2.log` | 120 passed / 122 (finished 00:30:50): TestSqlScanner 35/35, TestSqlEmitters 5/5, TestInMemoryScan 5/5, TestDateAndScan 13/13, TestRunner 44/44, TestRenderTrace 8/8, TestSqlDifferential (SQLite) 10/12: the 2 red are the D2 reference (`pin O-4 sumEmpty` and the random property on `Aggregate(RelEmpty, Min)`, see below) |
| 3 live SQL Server (`ERMINE_DB_*` from `~/.config/ermine/db.env`, never printed) | `final2-gate3.log` | 21 passed / 34 (finished 00:31:07): TestMsSqlSmoke 2/2; TestSqlDifferential SQLite 10/12 and SQL Server 9/12: every pin under my flags green on both halves (list below); red = 2x `pin O-4 sumEmpty` (D2), 2x random (both `Aggregate(<empty>, Min/Max)`: D2), `pin O-20` (by design); TestDbReports 0/8 (all tier-xs twins, see below). tempdb: 40 new `##t` tables for 50 let bindings (sharing + unused lets) |
| TestRunner alone (after a load-sensitive red, see below) | `final-runner.log` | 44/44 (started 00:23:55, finished 00:24:34) |
| 4 corpus | `final-gate4.log` | `corpus-run.sh --batch`: 168 files in one JVM; `corpus-check.py`: 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected (run on the tree before the last O-2 edit, which touches only SQL emission; verdicts are typing verdicts) |

Notes on reds that are not mine to fix:
- `TestSqlDifferential` random property, both halves: every remaining red is the D2 rule: the oracle's reference
  answers "one NULL row" for SUM/MAX/AVG over no rows (`Aggregate(Filter(RelEmpty, false), Sum)` etc.); the scanner
  answers 0 for SUM and no row for the others. Its `pin O-4 sumEmpty` reads 0 now for the same reason. The
  orchestrator updates the reference at landing (posted to the board 00:12).
- `pin O-20 (pinned as is)`: asserts one `##t` table per let binding; C9 shares and C20 skips them (42 new for 45
  bindings), so the "as is" pin is red by design; the clean-tempdb pin under `letTemp` stays red until E16 lands.
- `TestDbReports`: all 8 red properties are the "(tier xs)" twins and "the pinned totals"; the server holds tier s,
  every diff is data-level (regions china/france..., headline rowCount 0 for "north"). The suite has no
  tier-independent "same document" property (the SQLite twin is skipped: no `data/out/sales/xs/sales.sqlite`).
- `TestRunner (d) concurrent requests` went red twice under load (once "no module named Rg66", once a 400 with
  another request's params; it passed in the second of two concurrent JVMs and alone: 44/44). Not on the SQL path;
  unverified whether pre-existing on the base tree.

Oracle flags my fixes close (green pins on both halves in `final2-gate3.log`): setOpPrecedence (C1),
outerJoinInlinedExpr (C3), limitTwoRowsDistinct (C4), projectNonInjective (C15), fullJoinNullKey (C16),
limitOneRowOffset (C17), projectOverAggConst (C18), dupLit (C19, incl. the aggregate/let paths), outerNull (C22).
Not closed: sumEmpty/emptyAgg (need the D2 reference and E22), letTemp (needs E16).
