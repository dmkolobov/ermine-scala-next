# impl-rel report (SQL audit, area `rel`, 2026-09-26/27)

Worktree `ermine-scala-wt-sql-rel`, branch `sql-rel` (dirty, nothing committed). Items R1-R9 of
`WORKLIST.md`. Every claim below is MEASURED by `TestSqlRel` on in-memory SQLite unless marked READ.

## Files touched

| file | items |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/relational/Rel.scala` | R1 (`JoinOn.bimap/subst/unquote` keep `mode`), R5 (`Minus.apply`), R7 (`Join.apply` guard), R2 (`QuoteR.header` reads a `Typer.Quoted` tag), three false comments corrected (O-18) |
| `core/src/main/scala/com/clarifi/reporting/relational/Typer.scala` | R4 (`joinType` by mode, public `joinHeader`; `HashLeftJoin`/`MergeOuterJoin` typed Left/Full; pivot NULL default nullable), R2 (`Quoted` tag; `QuoteR`/`QuoteMem` tagged quotes type) |
| `core/src/main/scala/com/clarifi/reporting/ReportingUtils.scala` (CRLF kept) | R6 (`x == x` fold guarded by `mayBeNull`; the two Reflexivity-equivalence cases no longer fire for the same column on both sides), R5 (`notTrue`/`notFalse`, the exact 3VL "not TRUE" form), R10 (`simplEnv` skips NULL constants) |
| `scalacheck-binding/src/main/scala/TestSqlDifferential.scala`, `scripts/gates.sh` | taken from `sql-audit` as the coordinator asked (`git checkout sql-audit -- ...`), NOT edited |
| `core/src/main/scala/com/clarifi/reporting/relational/Optimizer.scala` | R5 (`filterNEq` shape `r MINUS (r JOIN lit)` folds to one filter in the `MinusI` case), R9 (ten zero-caller helpers deleted; `literalAsPredicate` now used) |
| `core/src/main/scala/com/clarifi/reporting/ermine/session/Lib.scala` | R2 (binders tag their quotes with the bound header: `letR`, `letRWithPK#`, `letM`, `groupBy#`, `accumulate`), R3 (`projectEach` tolerates the column the erased empty side could not contribute), R8 (`groupBy#` lowers a one-aggregate body to `AggregateByGroup`) |
| `scalacheck-binding/src/main/scala/TestSqlRel.scala` (new) | pins + properties for R1-R8, the R8 document evidence |

No `.e` file changed. No signature or export changed.

## Per item

### R1 (O-1, L-1, S-01) WRONG: outer join under `letR` was an inner join
Change: `JoinOn.bimap`, `subst`, `unquote` pass `mode` (three one-token edits + comment).
Test: `R1 pin: an outer join under letR ...` (Left/Full/Right under `LetR(ExtRel ..)`, the SQL contains LEFT),
`R1 pin: letRWithPK and a Rel/Mem outer join ...` (`LetR(ExtMem(Literal) ..)`, the shape `LeftJoinE(ExtRel, ExtMem)`
builds), property `R1: every mode under letR, letRWithPK and beside a Mem delivers its keys`, property
`R1: bimap, subst and unquote keep a JoinOn's mode` (also through `fromScope`/`toScope`).
Pre-fix answer named in each: the inner join's two keys.
Plain language: a left/right/full join written inside `letR`, `letRWithPK`, `materialize`-then-use, or against
an in-memory relation now keeps the unmatched rows it used to drop (the optimizer's live SQL Server probe
lost 356 of 388 sales this way).

### R2 (O-7, S-02) WRONG: `leftJoinOr`/`joinWithDefault`/`rheader` under `letR`/`groupBy` panicked
Change: `Typer.Quoted(header)` is the object a binder quotes its variable with when the bound relation types
(`Typer.extTyper`/`memTyper`; groupBy's body sees the header minus the key, accumulate's the leaves minus the
node id); `Typer.relTyperAux`/`memTyperAux` answer a tagged quote's header, and `QuoteR.header` does too. An
untypeable bound relation keeps a plain `new Object`, as before. `projectEach` is otherwise unchanged.
Test: `R2 pin: leftJoinOr / joinWithDefault / rheader inside a letR body type and run` (Ermine-level through
`ErmineFixture`, executed on SQLite: three rows, the unmatched one with the default), `R2 pin: leftJoinOr
inside a groupBy body types`.
Plain language: `leftJoinOr`, `joinWithDefault`, `rightJoinWithDefault`, `rheader` and anything else that
asks a relation for its columns now work on a variable bound by `letR`/`materialize`/`groupBy`/`accumulate`
instead of crashing the report with "Asked for the header of a quote".

### R3 (S-03) WRONG: outer join against `relation []` lost the default columns
Change (partial, see open issues): in `projectEach`, a column of the default record that the relation does
not have (the erased empty side) is supplied as a typed NULL literal, and `coalesce(NULL, d)` is folded to `d`.
`unsafeLeftJoin r (relation [])` itself still answers `r` (its extra columns' names are erased at runtime).
Test: `R3 pin: leftJoinOr r (relation []) keeps the default column on every row` (`leftJoinOr` and
`joinWithDefault`, executed: every row carries the default).
Plain language: `leftJoinOr`/`joinWithDefault` against an empty `relation []` now fill in the default instead
of failing "nonexistent column".

### R4 (D4; O-11, S-27, L-18, S-10) FRAGILE: header of an outer join / pivot default
Change: `Typer.joinType(left, right, extras, mode)` widens the columns that come only from a NULL-filled side
(Left: right-only; Right: left-only; Full: both; shared keys keep their type); public `Typer.joinHeader` for
the scanner; `HashLeftJoin`/`MergeOuterJoin` typed as Left/Full; `pivotType` types a column whose default is
NULL as nullable.
Test: property `R4: the NULL-filled side of an outer join is nullable ...` (every mode, random nullability,
`joinHeader` agrees with `relTyper`), `R4 pin: a pivot with a NULL default ... reads NULL where a key is
missing` (executed: the scanner's pivot uses `Typer.pivotType`, so the read returns NULL instead of throwing).
Plain language: a `pivot` over a group missing one key value now delivers `null` for that cell instead of
failing the whole report; an `unsafeLeftJoin`'s NULL-side columns are typed nullable in the header.
OPEN for impl-scanner (posted on the board 23:52): the wire decodes with the scanner's own join header
(`SqlScanner.scala:1163 other.h ++ h`), so an unmatched outer-join row still throws "Unexpected NULL" until
that line uses `Typer.joinHeader(h, other.h, mode)`. One line, their file.

### R4b (review-rel must-fix, board 00:24) nullability is not a type mismatch
Change (`Typer.scala`): `joinType`'s `badCols` compares base types (`withoutNull`); `joinHeader` types a
shared column's nullable flag by mode (Left: the left's, Right: the right's, Inner/Full: nullable only when
both sides are -- a match or a coalesce is NULL only then); new public `Typer.unionHeader(top, bottom)`:
same columns, base types equal, nullable iff either side; `unionType` (union, difference, `UnionM`,
`DifferenceM`) uses it. `joinHeader`/`unionHeader` are public for the scanner (impl-scanner's C22) to call
at landing so the wire header is the same rule.
Test: `R4b pin: union / join of an unsafeLeftJoin result with a non-nullable twin column types` (the two
repros through `ErmineFixture`: union header `u` nullable, join header `u` non-nullable, the join executed:
one row k=1), property `R4b: union types a column nullable iff either side is; a base-type difference is
still an error` (+ `relTyper` agrees).
Run: `gate2d-rel-r4b.log`: 29/29 (`TestSqlRel` 24, oracle SQLite half: random 300/300 with the three
classes re-enabled, pins O-1/O-11/O-25, coverage). (`gate2c-rel-r4b.log` is the same run with an undeclared
`field z` in the probe module; test-only.)
R4b-Full (review-rel re-check, board 00:30): under a FULL join a NULL key never matches and survives as a
row whose coalesced key is NULL, so `joinHeader` types a shared key under Full nullable if EITHER side's is
(Inner stays "both"). The R4 property now draws a nullable left key and checks the key by mode; pin
`R4b-Full pin: a NULL left key under a FULL join survives as a row whose key is NULL` executes
`(NULL,1) FULL JOIN (1,1),(2,2)` on SQLite: keys {NULL, 1, 2}. Run `gate2e-rel-r4b-full.log`: TestSqlRel 25/25.
Plain language: joining or unioning an `unsafeLeftJoin`'s result with an ordinary relation types again; the
combined column is nullable when either input is.

### R5 (O-6, S-25) WRONG + WASTE: `difference` of two filters under three-valued logic; `filterNEq`
Change: `Minus.apply` rewrites `difference (filter p1 r) (filter p2 r)` to `filter (p1 AND notTrue(p2)) r` and
`difference r (filter p2 r)` to `filter (notTrue(p2)) r`, where `ReportingUtils.notTrue` is the exact
"p2 is FALSE or UNKNOWN" predicate (`NOT p2 OR operand IS NULL` per comparison, dualised through AND/OR/NOT,
`IS NULL` itself never unknown); a `Funtest` keeps the set difference. NULL tests are emitted for every
operand that is not a non-NULL literal, whatever the column's declared type says (the surface type is not
nullable after `unsafeLeftJoin`, O-6's repro). The optimizer's `MinusI` case folds `r MINUS (r JOIN lit)`
(what `filterNEq` reaches it as) to `difference r (filter (some literal row matches) r)`, hence one filter.
Test: `R5 pin: difference (filter k>1) (filter b>5) keeps the row whose b is NULL` (executed; no EXCEPT),
`R5 pin: filterNEq's shape ...` (one and two literal rows; no EXCEPT; the IS NULL guard present),
property `R5: notTrue(p) is TRUE exactly when p is not TRUE, and never UNKNOWN` (random predicates over
random NULL rows against a 3VL reference), property `R5: difference of two filters over random NULLs delivers
the set difference` (executed against the reference).
Plain language: `difference` of two filters of the same relation, and `filterNEq`, now keep the rows whose
filtered column is NULL (as `EXCEPT` did) while still running as one pass over the relation; `filterNEq` no
longer scans the relation twice.

### R6 (O-9, S-30) FRAGILE: `x == x` folded to TRUE
Change: `simplifyPredicate` folds `Eq(l, r)` with `l === r` only when `!mayBeNull(l)` (a NULL literal
whatever its declared type -- the coordinator's note: with P2 `NullExpr == NullExpr`; else the guessed type
non-nullable; an untypeable op counts as nullable). The two Reflexivity-equivalence cases below it fire only
for two DIFFERENT column names (a singleton set is trivially "equivalent", which is how the first run of the
property still folded `x == x`). Pin `R6 pin: NULL == NULL never folds to TRUE`.
Test: property `R6: x == x folds to TRUE only for an operand that cannot be NULL`, `R6 pin: filter (inl == inl)
over a NULL drops the row`.
Limit (READ): the guard sees the ColumnValue's declared type; after an `unsafe*` outer join the surface type
still says non-nullable, so `[| b == b |] (unsafeLeftJoin ..)` still folds. By name unsafe.
Plain language: `filter (x == x)` on a nullable column now drops the NULL rows, as the database does.

### R7 (O-10) FRAGILE: coalescing two `aggregateByGroup`s over a nullable key
Change: `Join.apply` coalesces only when every group column (`cs` keys and `group`) is non-nullable.
Test: property `R7: two aggregateByGroups coalesce ... only over non-nullable group columns`, `R7 pin: with a
NULL group key the join of two group results drops the NULL group` (executed).
Plain language: `join (aggregateByGroup ..) (aggregateByGroup ..)` over a nullable key now drops the
NULL-keyed group like every other natural join; over a non-nullable key it is still one GROUP BY.

### R8 (S-20 §7, D7) WASTE: `groupBy k (sumBy c)` fetched every row
Change: in `groupBy#`, when the body is exactly `AggregateM(<the quote>, attr, agg)` with `agg` one of
Count/Sum/Avg/Min/Max and the source is `EmbedMem(ExtRel(rel, db))` (a relation that came from SQL via
`asMem`), the answer is `Rel(ExtMem(EmbedMem(ExtRel(AggregateByGroup(rel, key, [(attr, agg)], key), db))))`.
Ermine type unchanged (`Mem`). Lambda bodies, other aggregates (stddev/variance/wmean: not in D7) and Mem
sources are unchanged.
Test: `R8 pin: groupBy k (sumBy/count/maxBy/minBy/meanBy c) ... is one GROUP BY in SQL` (Ermine-level shape +
executed totals), `R8: a groupBy whose body is not one aggregate still groups in memory`, `R8 evidence:
FetchTopN with groupBy {region} (sumBy amount) renders the same document as with aggregateByGroup and reads 4
rows, not 8` (the fixture rewritten to the pre-F-1 form, rendered through the JSON `Runner` with a
`RenderTrace`; documents byte-identical, `$.fetch[1]` rowsRead 4 = rows delivered, SQL has GROUP BY/SUM).
Plain language: `groupBy k (sumBy c)`, `groupBy k count`, `groupBy k (minBy/maxBy/meanBy c)` over a database
relation now run as one GROUP BY in the database instead of fetching every row; a NULL in the summed column
is skipped (SQL's rule, D1) where the in-memory sum used to answer NULL for the group.

### R10 (wave 2, O-25) WRONG on SQL Server: a NULL constant substituted into a predicate
Change: `simplifyPredicate`'s `simplEnv` no longer substitutes a column whose known constant is NULL (the
column reference is exact; the untyped NULL literal made SQL Server reject `CASE ... THEN NULL ELSE NULL`).
Test: the oracle's pin `O-25` under `-Dermine.test.sqldiff.nullConstSubst=true` (SQLite half; the failure
is SQL Server's), plus `R10: a column known to be NULL is not substituted` in `TestSqlRel`.
Plain language: a filter with an `if` over a one-row relation holding a NULL no longer fails on SQL Server.

### R9 (O-18) NOTE: dead code
Deleted from `Optimizer.scala` (zero callers by grep): `literalAsCases`, `collectJoin`, `joinLiterals`,
`renameAggregate`, `simpleProject`, `projectAggregate`, `exceptAggregate`, `headerOf`, `reverseRename`,
`joinable`. Kept and now used: `literalAsPredicate`. `SqlScanner`'s `megaDistinctness`/`Fundepped` are the
scanner's file, untouched. The three "gets optimized away in the Optimizer" comments in `Rel.scala` replaced
by what happens.

## Departures from the worklist
- R3 is partial: only the `projectEach`-based helpers are fixed; the bare `unsafeLeftJoin r (relation [])`
  needs the row type at runtime (a `relation []` has no header), i.e. a surface addition (D9 territory).
- R5's "else `NOT p2 OR col IS NULL`" is implemented as the exact `notTrue` form (the worklist's form is
  wrong for `OR`s and `IS NULL`s inside `p2`) and the NULL tests are unconditional on column operands.
- R4's effect on the wire needs the scanner's one-line change (board question); Typer alone types.

## Gates
All logs under `/home/dmitry/research/ermine/scratch-sql-audit/logs/`.

| gate | command | result | log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources core/Test/compile` | success (main `compile-rel-1.log` 32 s; Test compile inside `test-rel-3.log`) | `compile-rel-1.log`, `test-rel-3.log` |
| 2 | `sbt -batch <flags> 'core/testOnly *TestSqlEmitters* *TestInMemoryScan* *TestSqlDifferential* *TestDateAndScan* *TestRunner* *TestRenderTrace* *TestSqlRel*'` with `-Dermine.test.sqldiff.{letOuter,eqSelf,nullConstSubst}=true` | 99 of 101 green, 262 s. Red: (a) `TestSqlRel` R10's second assertion (my test expected `k > 0` to fold after substitution; `simplifyPredicate` never folds a literal comparison; the test is corrected, re-run below); (b) the oracle's random property, 120 cases in: `JoinOn(LetR(ExtRel(lit)), AggregateByGroup(lit{ib=0,-1}, [], [(p4, Avg ib)]), Set((inl, p4)), Inner)`: the reference answers `p4 = 0` (integer AVG truncated, as SQL Server does) and SQLite answers `-0.5`, so the join on `inl = p4` matches in the reference and not on SQLite. Inner join, no filter, no simplify, no coalescing: none of R1-R10 is on that path; a reference-vs-SQLite integer-AVG class for the oracle (READ) | `gate2-rel.log` |
| 2 re-run | `sbt -batch <flags> core/Test/compile 'core/testOnly *TestSqlRel* *TestSqlDifferential'` after the R6 NULL-literal guard + R10 test fix | 27/27 green, 48 s (`TestSqlRel` 22 incl. the new R6 NULL-literal pin and R10; oracle random 300/300 with `letOuter`+`eqSelf`+`nullConstSubst` re-enabled, pins O-1/O-11/O-25, coverage) | `gate2b-rel.log` |
| 3 | `ERMINE_DB_*` from `~/.config/ermine/db.env` the way `tracker/tools/db-reports.sh` reads it; `sbt -batch <flags> 'core/testOnly *TestSqlDifferential* *TestDbReports* *TestMsSqlSmoke*'` | 12 of 20 green, 13 s: `TestSqlDifferentialDb` random 150/150 on SQL Server + pins O-1, O-11, O-25 green ON SQL SERVER (R10's actual dialect), O-20 count green; SQLite half 300/300; `TestMsSqlSmoke` 2/2. The 8 red are all `TestDbReports` "(tier xs)" twins and the pinned-totals property: the server holds tier s, so every DB twin renders china/germany/... against the 8-row literal (the label shows `rowCount 0` vs 3, `china -> 11278.65`); expected red at tier s per the brief, no exception, no "same document" property that is tier-independent exists in that suite | `gate3-rel.log` |
| 3b | `sbt -batch -Dermine.test.sqldiff.outerNull=true 'core/testOnly *TestSqlDifferential'` | 2 of 3: pin O-3 `outerNull` still red (`Unexpected NULL in field of type DoubleT(false)`): needs the scanner's join header (board 23:52 / 00:20) | `test-rel-3b-outerNull.log` |
| 4 | `tracker/tools/corpus-run.sh --batch scratch-sql-audit/rel-corpus` + `python3 scripts/corpus-check.py ... tracker/corpus-verdicts.expected` | `SUMMARY 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected` | `gate4-rel-run.log`, `gate4-rel-check.log` |
| pre-gate | `sbt -batch <flags> 'core/testOnly *TestSqlRel* *TestSqlDifferential'` (first green run) | 25/25, 49 s: oracle random 300/300 with the three classes re-enabled, pins O-1, O-11, O-25 green, `TestSqlRel` 20/20 | `test-rel-3.log` |

Oracle flags closed by this tree (name them at landing, do not edit the suite): `letOuter` (R1), `eqSelf` (R6),
`nullConstSubst` (R10). `outerNull` (R4) closes only with the scanner's one line.

## Open issues / questions for other areas
- impl-scanner: `SqlScanner.scala:1163` join header (above). Also `LimitM`/`GroupByM` untouched.
- oracle: drop `letOuter` and `eqSelf` exclusions once this lands; add a NULL-in-summed-column case for
  `groupBy k (sumBy c)` (D7 changes that answer from NULL to the sum of the rest).
- prims: `NullExpr != NullExpr` on this tree (S-18/P2), so `TestSqlRel` compares rows by value through a
  normaliser; nothing here depends on P2.
