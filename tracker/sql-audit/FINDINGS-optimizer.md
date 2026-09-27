# FINDINGS-optimizer (SQL audit, 2026-09-26/27, role `optimizer`)

Scope: `relational/Optimizer.scala`, `Rel.scala` smart constructors, `Predicates.simplify`
(`ReportingUtils.simplifyPredicate`), `Op.scala`, `Typer.scala`, `Ext.scala`, and the SQL shape the
rewrites leave (`SqlScanner.DistinctiveQuery`). Method: code read end to end, then 60 probe relations
dumped through BOTH scanners with `Scanners.dumpQuery` in the audit worktree (probe modules and the
transcript extractor under `scratch-sql-audit/survey/probes/`, SQL under `scratch-sql-audit/survey/sql/`,
`bug-*.sql` for the repros, `<Module>-<binding>.{sqlite,mssql}.sql` for the survey). "MEASURED" =
the SQL text was produced by the compiler in this session; "READ" = reasoned from the code. Nothing
was executed against a database except the 15 `DbFetch*`/`DbSalesReport` SQL Server texts, which
ran read-only on the live ErmineSales at tier s (388 `sales` rows, 8 regions) to count rows.

One structural fact first, because it reframes the brief: **the Optimizer is almost a no-op.**
`optimizeRel` reconstructs every node unchanged except (a) `MinusI` is rebuilt through the `Minus`
smart constructor and (b) a `LetR` over an `ExtMem(Literal)` of at most 31 rows is inlined as a
`SmallLit`. Case (b) is reachable only from `mem`/`asMem`, because `relation [...]` already lowers to
`ExtRel(SmallLit)` (`Runtime.scala:386`). Every other rewrite the brief names lives in the `Join`/`Minus`
smart constructors (applied at lowering time, `Ext.scala`) and in `SqlScanner.DistinctiveQuery`. The
Mem-side optimizer (`optimizeMem`: `flattenProjection`, `AugmentSM`) is exercised only by `groupBy`
subqueries and the dead SM feature (O-21).

## Table

| id | severity | where (file:line) | one-line claim | repro | proposed fix | blast radius |
|---|---|---|---|---|---|---|
| O-1 | WRONG | `relational/Rel.scala:114,115,120` | An outer join inside a `letR`/`letRWithPK` body is emitted as an INNER join: `JoinOn.bimap/subst/unquote` rebuild `JoinOn(fst, snd, cs)` and drop `mode` | MEASURED both dialects: `letR t2 (x -> unsafeLeftJoin t1 x)` -> `t1 JOIN ##tmp on (k = k)`; `unsafeFullJoin` likewise; `letRWithPK {k} t2 (x -> unsafeLeftJoin t1 x)` likewise (`bug-b6_left_in_letRWithPK`); top-level `unsafeLeftJoin t1 t2` -> `LEFT JOIN` (`bug-b1_*`). LIVE on SQL Server tier s: `unsafeLeftJoin sales (filterEq region "france" targets)` returns 388 rows, `letR (filterEq region "france" targets) (x -> unsafeLeftJoin sales x)` returns 32 (`bug-b7_*`, expected 388) | pass `mode` in the three constructors | Rel.scala only; every LetR body is rebuilt by `unquoteR` (Lib.scala:845,868) and by the optimizer's `fromScope/toScope` (Optimizer.scala:381-385), so every outer join under `letR`, `materialize`-then-use, `lookupLatest'`, `Algebra/Helpers.closure` changes answers |
| O-2 | WRONG | `Op.scala:86-89` | Any op containing `logBase` throws `scala.MatchError` at SQL compile time: `builtinSimplify`'s `LogBase` case matches only a literal base equal to 1, no fallback; `compileOp` runs `simplify` on every op | MEASURED: `combine (logBase a (prim 2.0)) c t1` -> `<error: OpLiteral(2.0) (of class ...Op$OpLiteral)>`; `logBase a a` likewise; `pow` fine (`bug-b3_*`) | add `case _ => BuiltinCall(b, args)` (and decide what log base 1 should mean: today it folds to 0 for a literal-1 base, which is not a number) | Op.scala; also fixes in-memory `Op.simplify` |
| O-3 | WRONG | `relational/SqlScanner.scala:1104-1116` (`squashLiteral`; owner lowering, posted) | A one-row literal joined to a windowed relation (`filterEq f v ranked`) puts the WHERE in the SELECT that computes the OVER, so the window sees only the filtered rows | MEASURED: `filterEq k 1 (combine (windowed rank (window {k} (asc a))) c t1)` -> `select ..., RANK() over (...) c, (1) k from t1 where (k = 1)`; `[| k == 1 |] ranked` wraps correctly (`bug-b5_win_filterEq` vs `bug-b5_win_filter`) | give `squashLiteral` the `!v.isWindowed` guard `filter` has at :1169 | SqlScanner; affects `filterEq`, `firstBy`/`lastBy`, any `join r (row {...})` over a windowed relation |
| O-4 | WRONG | `SqlScanner.scala:1133-1160` (`joinOn`; owner lowering, posted) | LEFT/RIGHT/FULL joins merge the nullable side's select list, so a constant or `coalesce`d column of that side survives on unmatched rows instead of NULL | MEASURED: `unsafeLeftJoin t1 ([| c = 1 |] t2)` -> `select ..., (1) c ... from t1 LEFT JOIN t2` (`bug-b5_left_const`); computed `b + 1` is NULL-propagating and so correct by luck (`bug-b5_left_computed`) | on the nullable side(s) require plain `ColumnSqlExpr` attrs in the `asSelect` predicate, else wrap | SqlScanner; `partialLookup'`/`leftJoinOr` put their coalesce OUTSIDE the join and are unaffected |
| O-5 | WRONG | `SqlScanner.scala:97-99` (`compileOp` If merging; owner lowering, posted) | `If(t, If(t2, x, y), z)` compiles to `case when not t then z when t2 then x else y end`; for a NULL `t` operand SQL answers `y` where the unmerged form answers `z` | MEASURED SQL (`bug-b5_nested_if`), semantics READ (3VL) | merge only the alternate-side nesting (:94-96), or emit `when t then (inner) else z` | SqlScanner; any nested `if` on a nullable column |
| O-6 | WRONG (nullable columns) | `relational/Rel.scala:146-150` (`Minus.apply` via `combineFilters`) | `difference (filter p1 r) (filter p2 r)` becomes `filter (p1 AND NOT p2) r`; under three-valued logic a row where `p2` is UNKNOWN belongs to the difference (it is in the left, not in the right) but `p1 AND NOT UNKNOWN` drops it | MEASURED SQL with a truly nullable column: `lj = unsafeLeftJoin t1 t2; difference ([| k > 1 |] lj) ([| b > 5 |] lj)` -> `... LEFT JOIN ... where ((k > 1 and not (b > 5)))` (`bug-b6_minus_nullable`); the same with a projection breaking `r1 == r2` -> `... EXCEPT ...` (`bug-b6_minus_control`); the row-loss on NULL `b` is READ (3VL) | rewrite as `p1 AND (NOT p2 OR p2 IS UNKNOWN)`, i.e. only apply `combineFilters` for Minus when `p2.columnReferences` are all non-nullable in the header, else keep `MinusI` | Rel.scala; only `difference`/`filterNEq` on nullable filter columns |
| O-7 | WRONG | `Lib.scala:845` + `Rel.scala:323` (owner surface, posted) | `letR t2 (x -> leftJoinOr t1 x {b = 0})` panics `Asked for the header of a quote.`: the body is built against `QuoteR(unique)`, which has no header, and `leftJoinOr`/`projectEach`/`rheader` ask for it | MEASURED (`bug-b1_leftJoinOr_letR` ERR) | give `QuoteR` the bound relation's header (Lib.scala knows `ext`'s header via `Typer.extTyper`) | Lib.scala; every header-inspecting helper under `letR` |
| O-8 | WRONG (READ) | `SqlScanner.scala:425-436` vs `:1249` and `Relation/Sort.e:135-140` | `limit` is documented and compiled 1-based for SQL (`from.getOrElse(1)`, `offset from-1`), but `LimitM` drops `start` rows (0-based): `limit o (Just 1) (Just 3)` on a `Mem` answers rows 2..3 | READ (a Mem cannot be dumped; `bug-b2_limit_from1` shows the SQL side treating `Just 1` as identity) | `LimitM`: `drop (start-1) `, `take (stop - start + 1)` | SqlScanner Mem path; owner lowering |
| O-9 | FRAGILE | `ReportingUtils.scala:41-48` (`simplifyPredicate`) | `Eq(l, r)` with `l === r` folds to TRUE (and `Not` of it to FALSE); in SQL `x = x` is UNKNOWN for NULL `x`. Compiled as `where ('A' = 'A')`. Harmless while headers are honest, but `Typer.joinType` (:102-119) never promotes the nullable side of an outer join, so after `unsafeLeftJoin` the header lies and the fold keeps rows SQL would drop | MEASURED: `[| b == b |] (unsafeLeftJoin t1 t2)` -> `... LEFT JOIN ... where ('A' = 'A')` (`bug-b2_eq_self_nullable`) | fold only when both sides' `guessType` is non-nullable; promote nullability in `joinType` for Left/Right/Full | ReportingUtils + Typer; nothing in the corpus writes `x == x` |
| O-10 | FRAGILE | `Rel.scala:95-100` (`Join.apply` aggregate coalescing) | Two `aggregateByGroup`s over the same relation are coalesced into one GROUP BY; the natural join it replaces would DROP groups with a NULL key (SQL `k = k` is UNKNOWN), the coalesced form keeps them. Not wrong in itself, but the rewrite is not semantics-preserving on nullable group keys, and the in-memory `hashJoin` (Record equality, NULL == NULL) already disagrees with SQL on NULL keys | MEASURED SQL: `join (aggregateByGroup (sum a) {k} b t1) (aggregateByGroup (mean a) {k} c t1)` -> one `select SUM(a) b, AVG(a) c, k ... group by k` (`bug-b2_agg_coalesce`); filtered side not coalesced -> two subqueries joined (`bug-b5_two_agg_filtered`) | decide the NULL-key join semantics once (oracle target) and document; keep the rewrite | Rel.scala; oracle `TestSqlDifferential` should include NULL group keys |
| O-11 | FRAGILE | `Typer.scala:102-119,210,259` | Outer joins type as `left ++ right`: no column becomes nullable, so `Nullable` never appears on the joined header and every downstream consumer (`Op.eval` on a `NullExpr` in a non-null slot, JSON encoding, O-9) trusts a wrong type | READ; `bug-b1_left_tables` header non-null | promote the outer side(s) with `withNull` in `joinType` when `mode != Inner`; the surface already calls these `unsafe*` | Typer + surface types; needs the surface role's view |
| O-12 | WASTE | `SqlScanner.scala:1210` (`project`), `:1237` (`except`), `SqlEmitter.scala:383` (`EagerlyDistinct`, both live dialects) | Distinctness is requested eagerly from below whenever a projection preserves it, so a `combine`/`rename` after an `except` forces a `select distinct` at the inner level even when the consumer dedupes anyway. `melt` (UNION of four except+combine arms) emits FOUR `select distinct` subqueries under a UNION that dedupes them again | MEASURED: `Wide-meltedScores_Sp.mssql.sql` (4 x `select distinct`, 3 x UNION); also the survey column DISTINCT | in `project`/`except` pass `needDistinct && preservesDistinct` to the inner query (lazy) instead of `preservesDistinct && distinctEagerly`; the top-level scan still asks `q(true)` so no result changes; `aggregateByGroup` still asks `q(true)` itself | SqlScanner.DistinctiveQuery only; at tier l each dropped DISTINCT is a sort/hash pass over up to 2 M rows; must go through the oracle |
| O-13 | WASTE | `SqlScanner.scala:948` (`SmallLit` threshold 100), `Optimizer.scala:25` (`smallLitSize` 30, unreachable for `relation`) | A literal of 101+ rows costs a `CREATE TABLE` + bulk `SqlLoad` per scan and cannot be dumped; MS SQL's table-value constructor takes 1000 rows and SQLite's VALUES 500 (`SQLITE_MAX_COMPOUND_SELECT`) | MEASURED: 40-row literal -> VALUES (`bug-b4_join_lit40`), 101-row -> `Emission not supported for sql statement SqlLoad` (`bug-b4_join_lit101` ERR) | make the threshold an emitter property (1000 MS SQL, 500 SQLite); delete the dead `smallLitSize` path or point it at `SmallLit` too | SqlScanner + emitter; `Layout.Fetch` reports that write a `relation (withRunning rows)` back into SQL (FetchRunning/FetchFragments) cross 100 rows at tier s |
| O-14 | WASTE | `SqlScanner.scala:1262-1263` (`limit` with empty order) | `firstK n` sorts on EVERY column to make the limit deterministic: `order by k asc, a asc offset 0 rows fetch next 3 rows only` | MEASURED (`bug-b2_limit_noorder`) | keep (determinism is a feature) but document; or order by the relation's PK when `letRWithPK`/`memoRelWithPK` gave one | SqlScanner; 2 M-row sort for a 3-row answer at tier l |
| O-15 | WASTE | `SqlScanner.scala:1167-1177` (`filter` over a `SqlNaryOp`) | A filter over a UNION is applied outside the union (`select ... from (A union B) t where ...`), never pushed into the arms; the union dedupes the full inputs first | MEASURED both dialects (`bug-b4_filter_union`) | push a predicate into every arm of a `SqlNaryOp(SqlUnion)` when it references only header columns | SqlScanner; SQL Server usually does this itself, SQLite's flattener sometimes; measure before adopting |
| O-16 | WASTE | `SqlEmitter.scala:299-307` (`fallbackEmitLiteral`, SQLite has no `emitLiteral` override; owner emitter, posted) | Every literal row is a `select ... UNION select ...` on SQLite: an 8-row literal is 16 SELECTs, Wide's literal-backed relations are 29-56 SELECTs and up to 3 deep | MEASURED: survey `selects` column, e.g. `DbFetchCrosstab-calendar.sqlite.sql` 16 vs `.mssql.sql` 1 | give SqliteEmitter a VALUES emitter (`EmitLiteralTVC` exists for MS SQL) | emitter only |
| O-17 | WASTE | `SqlExpr`/`Predicate` (no `Le`/`Ge`) | `<=` compiles to `(c < 1 or c = 1)` | MEASURED (`bug-b5_win_topn`) | add `SqlLe`/`SqlGe` or emit `<=` for `Or(Lt(a,b),Eq(a,b))` with identical operands | emitter + `Relation.Predicate` |
| O-18 | NOTE | `Optimizer.scala:271-317,405-425,412-413`; `SqlScanner.scala:818-829` | Dead code: `projectAggregate`, `exceptAggregate`, `renameAggregate`, `simpleProject`, `joinable`, `literalAsPredicate`, `literalAsCases`, `collectJoin`, `joinLiterals`, `headerOf`, `reverseRename`, `megaDistinctness`/`Fundepped` (never called); the comments "gets optimized away in the Optimizer" on `Except`/`Combine`/`RenameR` (Rel.scala:174,185,196) are false | READ (grep) | delete or wire up; the aggregate helpers were the start of pushing rename/project THROUGH `AggregateByGroup`, which `bug-b5_rename_after_agg` shows the scanner already does in place | none |
| O-19 | NOTE | `Lib.scala:828` + `SqlScanner.scala:285,304,320` | `Optimizer.optimize` runs at `relation#` and again in every `scanRel`/`dumpRel`; idempotent, cheap | READ | drop one | none |
| O-20 | NOTE | `Typer.scala:317-324`, `Lib.scala:828` | A typing failure surfaces as `sys.error("NonEmptyList(Operation refers to nonexistent column (x) in header.)")` out of `Native.Relation.relation#`: raw Scala text, no source position | READ | format the messages; the Ermine type system makes this nearly unreachable | user-facing text only |
| O-21 | NOTE | `SMEnv.scala:213-220`, `Optimizer.scala:52-64,93-99,143-188` | The whole `AugmentSM`/`LookupSM`/`HistoricalSM` machinery is dead: `Internal.SMEnv.cachedSMEnv` is `dummySmenv`, whose every method is `sys.error("TODO")`, and no stdlib module calls `SM.current#`/`historical#` | READ (grep) | leave; do not spend audit or oracle time on it | none |
| O-22 | NOTE | `Rel.scala:88-105`, `:233-246` | `Note(tags, r)` is opaque to `Join.apply`'s `combineFilters`/coalescing and to `Minus.apply`; `Relation.note` is used nowhere in the stdlib or fixtures | READ | look through `Note` in the smart constructors if `note` gains users | none today |
| O-23 | NOTE | `SqlScanner.scala:961-970` (`MemoR`) | The persistent memo table name is a SHA of `r.toString`; `Map` printing order is insertion order below 5 entries and hash order above, deterministic for String keys, so stable today | READ | none | none |
| O-25 | WASTE (severe) | `SqlScanner.scala:972-998` (`LetR`, `guidName`; owner lowering, posted) | `materialize r` (= `letR r id`) shares nothing when its value is used more than once: each reference compiles its own CREATE + INSERT under a fresh guid, so `Algebra.Helpers.closure` depth 4 emits 40 temp tables, 40 UNIONs, 27 DISTINCTs, 82 KB of SQL (3^n growth) where 4 tables would do | MEASURED `Algebra-reachable_Bo.mssql.sql` (`grep -c 'CREATE  TABLE'` = 40); `calibsOnce_Kd` used once = 1 table | name LetR temp tables by a content hash of `ext` + scope as `MemoR` does (`:965`) so `prg.distinct` collapses copies, or memoise compiled exts by identity per `compileRel` | SqlScanner; at tier l a closure step fills a 2 M-row temp table 3^n times instead of n |
| O-26 | WASTE | `SqlScanner.scala:1094-1102` (`minus`) + O-12 | `antiJoin`/`filterNEq` emit `r EXCEPT select distinct ...`: the DISTINCT on the subtracted arm is redundant (EXCEPT dedupes); it comes from the arm's own eager projection, O-12's root | MEASURED `Algebra-ordersWithNoCustomer_Ol.mssql.sql`, `bug-b2_filterNEq` | same fix as O-12 | same |
| O-24 | NOTE | survey, `DbFetchHeadline-pickedAll` | `headlineOf` over `picked q` fetches every row (388 at tier s, 2 M at tier l) to show one sum; `aggregateByGroup` (F-1) already showed the cure for `byRegion` | MEASURED rows | a `Layout.Fetch` headline that lowers to `Aggregate` (surface/widgets) | outside this role |

## O-1 outer joins under `letR` become inner joins

`Rel.scala:113-121`:

```scala
case class JoinOn[+M, +R](fst, snd, cs: Set[(String, String)], mode: JoinMode = JoinMode.Inner) ... {
  def bimap[N, S](f, g) = JoinOn(fst bimap (f, g), snd bimap (f, g), cs)            // mode lost
  def subst[N, S](f, g) = JoinOn(fst subst (f, g), snd subst (f, g), cs)            // mode lost
  override def unquote[..](f, g) = JoinOn(fst.unquote(f, g), snd.unquote(f, g), cs) // mode lost
```

Paths that call them on every `LetR` body: `Lib.scala:845/868` (`r.unquoteR(...)` when building `letR`/
`letRWithPK`), `Optimizer.scala:381-385` (`Relation.fromScope(e)` / `toScope`, both `flatMap` = `subst`),
`Relation.instantiate` (the small-literal inlining), `LetR.equals/hashCode` (`fromScope`). `LeftJoinE`/
`FullJoinE` for a Mem operand (`Ext.scala:137-138,149-150`) build `LetR(ExtMem(..), JoinOn(.., Left))`
directly, so `unsafeLeftJoin table (asMem ...)` is hit too.

MEASURED (`scratch-sql-audit/survey/sql/bug-b1_left_in_letR.mssql.sql`):

```
CREATE  TABLE [##t...] ( [b] int not null, [k] int not null )
insert into [##t...]([b], [k]) select ([t].[b]) [b], ([t].[k]) [k] from [t2] [t]
select ([t1].[a]) [a], ([t2].[b]) [b], ([t1].[k]) [k] from [t1] [t1] JOIN [##t...] [t2] on ([t1].[k] = [t2].[k])
```

Expected: `LEFT JOIN`, as `bug-b1_left_tables.mssql.sql` (top level) and `bug-b1_left_materialize.mssql.sql`
(join outside the body) show. Observed rows: t1 rows without a t2 match disappear. `unsafeFullJoin`
under `letR` loses both the FULL and the `coalesce(k, k)` key (`bug-b1_full_in_letR`). Fix: add `mode`
to the three constructor calls. Blast radius: `Rel.scala` only; the oracle should add an outer join
under `letR`/`letRWithPK` to `TestSqlDifferential`. No fixture in `core/src/test/resources` exercises
this shape, which is why `TestRunner`/`TestDbReports` are green. LIVE (MEASURED, ErmineSales tier s,
`scripts/db.sh sql ErmineSales -i`): `bug-b7_left_top.mssql.sql` (top-level LEFT JOIN of `sales` to the
france target) answers 388 rows, `bug-b7_left_letR.mssql.sql` (the same under `letR`) answers 32: the
356 non-france sales are gone.

## O-2 `logBase` crashes SQL compilation

`Op.scala:86-89`:

```scala
def builtinSimplify(b: Builtin, args: List[Op]): Op = (b, args) match {
  case (LogBase, List(l,r)) => r match {
    case OpLiteral(pe) if pnum(1)(pe) => OpLiteral(asNum(0)(pe))
  }                                   // no other case: MatchError for every real call
  case _ => ...
```

`SqlScanner.compileOp:119` runs `op.simplify(Map())` on every op, so any `combine`/`filter`/`project`
containing `logBase x b` with `b` not the literal 1 dies before SQL exists. MEASURED:
`bug-b3_logbase_lit2.mssql.sql.ERR` = `<error: OpLiteral(2.0) (of class com.clarifi.reporting.Op$OpLiteral)>`,
`bug-b3_logbase_col` likewise; `bug-b3_pow.mssql.sql` = `POWER([t].[a], 2.0)` is the working control.
`Relation.Op.e:85,93` exports `logBase`. Fix: fall through to the generic literal-folding branch
(`case _ =>`), and drop the base-1 special case (log base 1 is undefined, not 0). In-memory
`Op.eval` (`PrimExpr.logBase`) is unaffected because `eval` does not simplify.

## O-3 / O-4 / O-5 (lowering-owned, posted to the board)

All three are in `SqlScanner.DistinctiveQuery`/`compileOp`, outside this role's files, found while
checking what the rewrites leave. Repros: `bug-b5_win_filterEq` (window computed after the literal's
WHERE), `bug-b5_left_const` (constant survives on unmatched LEFT JOIN rows), `bug-b5_nested_if`
(`case when not test`). Each has a one-guard fix in the file; the lowering role owns them.

## O-6 `Minus` of two filters under three-valued logic

`Rel.scala:146-150` rewrites `difference (filter p1 r) (filter p2 r)` to `filter (p1 AND NOT p2) r`.
MEASURED `bug-b2_minus_filters.mssql.sql`:
`select ... from [t1] [t] where ((([t].[a]) > (1) and not (([t].[a]) > (5))))`. For a row with `a` NULL:
left side (`a > 1` UNKNOWN) does not contain it, so the difference is empty for that row anyway here;
but with `p1` on a non-null column and `p2` on a nullable one (`difference ([| k > 1 |] r) ([| b > 5 |] r)`
after an outer join) the row is in the left, not in the right, and belongs to the answer; `k > 1 AND NOT
(b > 5)` is UNKNOWN and drops it. `EXCEPT` (the unrewritten form, `bug-b2_filterNEq`) treats NULLs as
equal and keeps it. Ermine's in-memory `toFn` (`Predicates.scala:16-25`) is two-valued (`!p2(t)`), so
the memory engine agrees with the REWRITTEN form, not with EXCEPT: whichever way it is fixed, one
engine changes. Proposed: apply the rewrite only when `p2`'s columns are non-nullable in the header
(needs O-11 so the header is honest), else keep `MinusI`. `Join.apply`'s `p1 AND p2` is safe.

## O-9 / O-10 / O-11 the NULL cluster

`simplifyPredicate` folds `Eq(l, r)` to TRUE when `l === r` (MEASURED `where ('A' = 'A')`), the
aggregate coalescing keeps NULL-key groups a natural join would drop, and `Typer.joinType` never marks
an outer join's columns nullable. None of these produces a wrong row on the corpus today because no
fixture has NULL keys and nobody writes `x == x`; they are listed so the oracle targets NULLs
deliberately (join keys, filter columns, group keys) rather than by accident.

## O-12 eager DISTINCT (the systematic waste)

`DistinctiveQuery` is lazy in its distinctness demand (`q: Boolean => (Boolean, query)`), but
`project`/`except` (`:1210`, `:1237`) ask the inner query `q(preservesDistinct && distinctEagerly)`,
i.e. `q(true)` for any distinctness-preserving projection on both live emitters, regardless of what the
CONSUMER needs. So `combine` after `except` = `select distinct` in a subquery, even under a UNION that
dedupes. MEASURED `Wide-meltedScores_Sp.mssql.sql`: four `select distinct (...) from (select ...)` arms
under three UNIONs; `bug-b4_chain`: the flattening itself is good (one SELECT for combine+project+
combine+project) but ends `select distinct`. Proposed: `q(needDistinct && preservesDistinct)`; the
top-level `scanAndUniq` asks `q(true)`, `aggregateByGroup`/`aggregate`/`pivot` ask `q(true)` themselves,
`union` asks `q(false)`, so results are unchanged and only the union arms lose their DISTINCT. Cost
saved at tier l: one hash/sort-distinct over the arm's rows per arm; `melt` over 2 M ledger rows is four
of them. Must be adopted only on the oracle's word (brief: an optimisation needs unchanged results).

Related, not a bug: any projection to a column subset before an aggregate is `select ... from (select
distinct ...) group by` (`bug-b4_project_agg`, `bug-b4_except_agg`, `DbFetchCrosstab-measured*`). That
IS Ermine's set semantics (two sales with equal `(region, month, amount)` collapse to one before the
crosstab sums them); on ErmineSales tier s there are 0 duplicate `(region, day, amount)` groups
(MEASURED) so the twins agree, and the 9 rows the crosstab reads with and without DISTINCT are the
same 9. The only way to remove those DISTINCTs safely is key knowledge (`table`s with a declared key,
`letRWithPK`), which the scanner does not consume today (`DistinctiveQuery.table` marks every base
table distinct but a projection of it forgets that). Surface decision, not an optimizer one.

## Part 1 checklist (each item of the brief, with the verdict)

| item | verdict | evidence |
|---|---|---|
| `Join.apply` aggregate coalescing: group sets differing in order | not coalesced (`a.group == b.group` is a List equality): correct, missed | READ |
| aggregate name equals a group column | typing gives the aggregate the last word (`cols ++ aggs`); coalescing checks only agg-vs-agg names | READ; edge, not reachable from `aggregateByGroup#` (cs = group) |
| one side filtered | `a.rel == b.rel` fails: two GROUP BY subqueries joined, correct | MEASURED `bug-b5_two_agg_filtered` |
| `combineFilters` for Join | `p1 AND p2`, correct | MEASURED `bug-b2_join_filters` |
| `combineFilters` for Minus | O-6 | |
| `Predicates.simplify` on NULLs | O-9; `Not(Not p)`, `And/Or` with constants are 3VL-safe | READ |
| `simpleProject`/`projectAggregate`/`exceptAggregate`/`renameAggregate` | dead code (O-18); the scanner renames/projects in place after GROUP BY correctly | MEASURED `bug-b5_rename_after_agg`, `bug-b5_project_after_agg` |
| `flattenProjection` alias twice / shadowing | post-order replace, inner ops inlined once per reference, no re-traversal: correct; only the Mem path uses it | READ |
| literals under `smallLitSize` | unreachable for `relation`; `SmallLit`/`squashLiteral` handle 1-row (WHERE) and n-row (VALUES) literals; NULL/duplicate rows are passed through VALUES unchanged, zero rows is `RelEmpty` | MEASURED `bug-b2_filterEq`, `bug-b4_join_lit40`, `bug-b5_union_lits` |
| `LetR` of a small literal vs original `pk` | `pk` dropped on inlining, harmless (VALUES has no key) | READ |
| `Limit` through Project/Filter | never pushed; every consumer of a limited query wraps it (`SqlLimit` is not a `SqlSelect`), so filter/aggregate/join after limit are correct | MEASURED `bug-b2_limit_then_filter`, `bug-b5_limit_then_agg`, `bug-b5_limit_in_join` |
| `Note` transparency | O-22 | |
| `AugmentSM` reachability | O-21, dead | |
| `Typer` headers per constructor | correct except outer-join nullability (O-11) and `Limit(from > to)` which errors instead of answering empty (`limitType`) while the scanner answers empty (`:1255`): inconsistent but unreachable through `Relation.Sort.limit` | READ |
| `sys.error` on typing failure | O-20 | |
| `Op.simplify` | `Concat` drops NULL/empty literals (Ermine's concat is NULL-as-empty; SQLite's `\|\|` is not, emitter role); `Cast` literal folding throws at compile time for a bad literal cast instead of at query time; `LogBase` O-2 | READ |
| `guessType` | `LogBase` answers Double while the surface types it `n`; `Concat` non-nullable even over nullable args | READ, NOTE |

## Part 2 missed optimisations (ranked by tier-l cost)

0. O-25 `materialize` re-materialises per reference (3^n temp-table fills for a depth-n closure).
1. O-12 eager DISTINCT under UNION arms (four 2 M-row distinct passes for `melt`).
2. O-24 whole-relation fetch for a headline (2 M rows to the client for one number): surface.
3. O-14 `firstK` sorts every column of 2 M rows for 3 rows.
4. O-15 filter not pushed through UNION (engine-dependent; SQL Server likely does it itself).
5. O-13 literal threshold 100 -> temp table + bulk load for `relation (withRunning rows)` past 100 rows.
6. O-16 SQLite literal as UNION-of-SELECTs (parse cost only, small).
7. O-17 `<=` as two comparisons (negligible).
Not missed (verified present): filter after aggregate is `HAVING` (`bug-b2_having`); ORDER BY of a
scan goes into SQL (`orderQuery`), sorting in Ermine is Mem-only; projection pruning happens (table
selects list only the surviving columns); nested SELECT chains are flattened in place (`bug-b4_chain`:
combine, project, combine, project = one SELECT); self-join of the same filtered table is one filter
(`bug-b2_join_filters`); `Union` of literals joined to a table is `VALUES union VALUES` in place.
Not present and not worth it here: DISTINCT elimination from keys (no key metadata reaches the
scanner), Limit pushdown (nothing to push it through), predicate pushdown into JoinOn sides (the
engines do it; `bug-b4_filter_join` leaves the WHERE on the join, which both planners push).

## The survey

Every named relation of the doc fixtures (`core/src/test/resources/doc/*.e`, `modules/Doc/*.e`) and
the 27 Wide relations of `tracker/tools/wide-render-probe.e` (the E-group relational examples per
`E1-EXAMPLES.md` §7.1), through both scanners: `scratch-sql-audit/survey/sql/<Module>-<binding>.{sqlite,mssql}.sql`.
Relations built inline inside `report`/`Fetch` bodies are approximated by a named binding with the
same shape (`regionHeadline`, `runningTable`, `joined`, `regions`, `tabNorth`) and by both arms of
each `Query`. Not dumpable, and why: `Wide` `groupBy` results (`byCustomerQuarter_Sl`, ...) are `Mem`
("Don't know how to dump a mem", 6 relations), Wide pivots are `Mem` too (6), `withSpread_Bd`/
`withUsd_Bd` materialise a temp table (`SqlLoad`, 2); `TraceReport` needs params; `Sales`/`SalesRaw`
build relations inside `report`. 41 relations, 78 SQL texts, 29 refusals (all `.ERR` files kept).

Columns: `selects` = number of SELECT keywords (SQLite literals inflate it, O-16); `depth` = max
subquery nesting; `DISTINCT` = `select distinct` count; `temp stmts` = CREATE/INSERT statements ahead
of the query; `ORDER BY` = any `order by` (for the window relations it is the one inside OVER; no
survey query has a top-level ORDER BY because `dumpQuery` passes no sort, and MS SQL is the only
emitter that prints OVER at all, so the SQLite window texts contain the `TODO` stub); `GROUP BY`;
`OVER`; `joins`; `chars`.

| file | selects | depth | DISTINCT | temp stmts | ORDER BY | GROUP BY | OVER | joins | chars |
|---|---|---|---|---|---|---|---|---|---|
| DbFetchCrosstab-calendar.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 279 |
| DbFetchCrosstab-calendar.sqlite.sql | 16 | 1 | 0 | 0 | - | - | 0 | 0 | 569 |
| DbFetchCrosstab-measuredAmount.mssql.sql | 2 | 1 | 1 | 0 | - | - | 0 | 1 | 473 |
| DbFetchCrosstab-measuredAmount.sqlite.sql | 17 | 2 | 1 | 0 | - | - | 0 | 1 | 731 |
| DbFetchCrosstab-measuredUnits.mssql.sql | 2 | 1 | 1 | 0 | - | - | 0 | 1 | 472 |
| DbFetchCrosstab-measuredUnits.sqlite.sql | 17 | 2 | 1 | 0 | - | - | 0 | 1 | 730 |
| DbFetchData-sales.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 144 |
| DbFetchData-sales.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 116 |
| DbFetchData-targets.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 92 |
| DbFetchData-targets.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 76 |
| DbFetchFragments-byRegion.mssql.sql | 1 | 0 | 0 | 0 | - | y | 0 | 0 | 123 |
| DbFetchFragments-byRegion.sqlite.sql | 1 | 0 | 0 | 0 | - | y | 0 | 0 | 103 |
| DbFetchFragments-regionHeadline.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 174 |
| DbFetchFragments-regionHeadline.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 146 |
| DbFetchFragments-runningTable.mssql.sql | 2 | 1 | 1 | 0 | - | - | 0 | 1 | 455 |
| DbFetchFragments-runningTable.sqlite.sql | 5 | 2 | 1 | 0 | - | - | 0 | 1 | 431 |
| DbFetchHeadline-pickedAll.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 144 |
| DbFetchHeadline-pickedAll.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 116 |
| DbFetchHeadline-pickedNorth.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 174 |
| DbFetchHeadline-pickedNorth.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 146 |
| DbFetchRunning-joined.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 205 |
| DbFetchRunning-joined.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 179 |
| DbFetchTabs-regions.mssql.sql | 1 | 0 | 1 | 0 | - | - | 0 | 0 | 68 |
| DbFetchTabs-regions.sqlite.sql | 1 | 0 | 1 | 0 | - | - | 0 | 0 | 58 |
| DbFetchTabs-tabNorth.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 174 |
| DbFetchTabs-tabNorth.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 146 |
| DbFetchTopN-byRegion.mssql.sql | 1 | 0 | 0 | 0 | - | y | 0 | 0 | 123 |
| DbFetchTopN-byRegion.sqlite.sql | 1 | 0 | 0 | 0 | - | y | 0 | 0 | 103 |
| DbSalesReport-sales.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 140 |
| DbSalesReport-sales.sqlite.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 118 |
| FetchCrosstab-measuredAmount.mssql.sql | 3 | 1 | 1 | 0 | - | - | 0 | 1 | 850 |
| FetchCrosstab-measuredAmount.sqlite.sql | 33 | 2 | 1 | 0 | - | - | 0 | 1 | 1484 |
| FetchCrosstab-measuredUnits.mssql.sql | 3 | 1 | 1 | 0 | - | - | 0 | 1 | 849 |
| FetchCrosstab-measuredUnits.sqlite.sql | 33 | 2 | 1 | 0 | - | - | 0 | 1 | 1483 |
| FetchData-sales.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 375 |
| FetchData-sales.sqlite.sql | 16 | 1 | 0 | 0 | - | - | 0 | 0 | 749 |
| FetchFragments-regionHeadline.mssql.sql | 2 | 1 | 0 | 0 | - | - | 0 | 0 | 549 |
| FetchFragments-regionHeadline.sqlite.sql | 17 | 2 | 0 | 0 | - | - | 0 | 0 | 897 |
| FetchHeadline-pickedNorth.mssql.sql | 2 | 1 | 0 | 0 | - | - | 0 | 0 | 549 |
| FetchHeadline-pickedNorth.sqlite.sql | 17 | 2 | 0 | 0 | - | - | 0 | 0 | 897 |
| FetchTabs-regions.mssql.sql | 2 | 1 | 1 | 0 | - | - | 0 | 0 | 440 |
| FetchTabs-regions.sqlite.sql | 17 | 2 | 1 | 0 | - | - | 0 | 0 | 806 |
| FetchTopN-byRegion.mssql.sql | 2 | 1 | 0 | 0 | - | y | 0 | 0 | 497 |
| FetchTopN-byRegion.sqlite.sql | 17 | 2 | 0 | 0 | - | y | 0 | 0 | 853 |
| SalesReport-sales.mssql.sql | 1 | 0 | 0 | 0 | - | - | 0 | 0 | 160 |
| SalesReport-sales.sqlite.sql | 6 | 1 | 0 | 0 | - | - | 0 | 0 | 235 |
| Wide-bookWithRegionShare_Rs.mssql.sql | 4 | 1 | 0 | 0 | - | - | 1 | 2 | 3666 |
| Wide-bookWithRegionShare_Rs.sqlite.sql | 37 | 2 | 0 | 0 | - | - | 1 | 2 | 5858 |
| Wide-bookWithShares_Rs.mssql.sql | 4 | 1 | 0 | 0 | - | - | 4 | 2 | 3936 |
| Wide-bookWithShares_Rs.sqlite.sql | 37 | 2 | 0 | 0 | - | - | 4 | 2 | 6466 |
| Wide-claimsWithRatios_Ce.mssql.sql | 5 | 1 | 0 | 0 | - | - | 0 | 3 | 6177 |
| Wide-claimsWithRatios_Ce.sqlite.sql | 39 | 2 | 0 | 0 | - | - | 0 | 3 | 9566 |
| Wide-damagePodium_Lb.mssql.sql | 5 | 2 | 0 | 0 | y | - | 1 | 2 | 6922 |
| Wide-damagePodium_Lb.sqlite.sql | 48 | 3 | 0 | 0 | - | - | 1 | 2 | 10224 |
| Wide-economyTiles_Lb.mssql.sql | 4 | 1 | 0 | 0 | y | - | 1 | 2 | 5340 |
| Wide-economyTiles_Lb.sqlite.sql | 47 | 2 | 0 | 0 | - | - | 1 | 2 | 8888 |
| Wide-fraudRanks_Ce.mssql.sql | 5 | 1 | 0 | 0 | y | - | 1 | 3 | 6064 |
| Wide-fraudRanks_Ce.sqlite.sql | 39 | 2 | 0 | 0 | - | - | 1 | 3 | 9630 |
| Wide-killLeaders_Lb.mssql.sql | 4 | 1 | 0 | 0 | y | - | 1 | 2 | 5323 |
| Wide-killLeaders_Lb.sqlite.sql | 47 | 2 | 0 | 0 | - | - | 1 | 2 | 8869 |
| Wide-ledgerWithBalance_Tb.mssql.sql | 4 | 1 | 0 | 0 | y | - | 1 | 2 | 4264 |
| Wide-ledgerWithBalance_Tb.sqlite.sql | 33 | 2 | 0 | 0 | - | - | 1 | 2 | 6645 |
| Wide-ledgerWithTrend_Tb.mssql.sql | 4 | 1 | 0 | 0 | y | - | 1 | 2 | 4253 |
| Wide-ledgerWithTrend_Tb.sqlite.sql | 33 | 2 | 0 | 0 | - | - | 1 | 2 | 6646 |
| Wide-meltedScores_Sp.mssql.sql | 8 | 1 | 4 | 0 | - | - | 0 | 0 | 7177 |
| Wide-meltedScores_Sp.sqlite.sql | 56 | 3 | 4 | 0 | - | - | 0 | 0 | 11969 |
| Wide-rosterPipeline_Wr.mssql.sql | 4 | 1 | 0 | 0 | y | - | 4 | 2 | 4473 |
| Wide-rosterPipeline_Wr.sqlite.sql | 37 | 2 | 0 | 0 | - | - | 4 | 2 | 7686 |
| Wide-roster_Wr.mssql.sql | 4 | 1 | 0 | 0 | - | - | 0 | 2 | 3869 |
| Wide-roster_Wr.sqlite.sql | 37 | 2 | 0 | 0 | - | - | 0 | 2 | 6620 |
| Wide-severityDeciles_Ce.mssql.sql | 5 | 1 | 0 | 0 | y | - | 1 | 3 | 6072 |
| Wide-severityDeciles_Ce.sqlite.sql | 39 | 2 | 0 | 0 | - | - | 1 | 3 | 9640 |
| Wide-topChannels_Ms.mssql.sql | 5 | 2 | 0 | 0 | y | - | 1 | 2 | 5572 |
| Wide-topChannels_Ms.sqlite.sql | 44 | 3 | 0 | 0 | - | - | 1 | 2 | 9455 |
| Wide-withTrend_Bd.mssql.sql | 4 | 1 | 0 | 0 | y | - | 1 | 2 | 4132 |
| Wide-withTrend_Bd.sqlite.sql | 29 | 2 | 0 | 0 | - | - | 1 | 2 | 6977 |

### Rows read vs rows used (live SQL Server, ErmineSales tier s: 388 `sales` rows, 8 regions, 8 targets; MEASURED 2026-09-26 23:1x via `scripts/db.sh sql ErmineSales "select count(*) from (<mssql text>) x"`)

| module | binding | rows returned | rows the report uses | verdict |
|---|---|---|---|---|
| DbFetchData | sales | 388 | 388 (table widgets) | fine |
| DbFetchData | targets | 8 | 8 | fine |
| DbFetchTopN | byRegion | 8 | 8 (keep N + Other computed client-side) | fine; GROUP BY in SQL (F-1) |
| DbFetchFragments | byRegion | 8 | 8 | fine |
| DbFetchFragments | regionHeadline ("north") | 0 at tier s (region names differ); 388-scale at tier l | 1 number | O-24: a headline fetches every row of the region |
| DbFetchFragments | runningTable (literal join) | 0 (literal days absent at tier s) | all | literal written back as VALUES; past 100 rows becomes a temp table (O-13) |
| DbFetchHeadline | picked (all) | 388 | 1 number for the headline, all for the table | O-24 |
| DbFetchHeadline | picked ("north") | 0 at tier s | idem | idem |
| DbFetchCrosstab | calendar | 8 | 8 | VALUES literal |
| DbFetchCrosstab | measured (units/amount) | 9 (= 9 without DISTINCT) | 9 | DISTINCT is set semantics; 0 duplicate `(region, day, amount)` groups at tier s |
| DbFetchTabs | regions (`sales # {region}`) | 8 | 8 | `select distinct region` in SQL: right |
| DbFetchTabs | tabNorth | 0 at tier s | all | fine |
| DbFetchRunning | joined | 0 at tier s | all | literal squashed into a WHERE on `targets`: right |
| DbSalesReport | sales | 3 | 3 | fine |

The `Fetch*` twins and Wide relations read literals (VALUES) and were not executed live; their SQLite
texts are executable as-is except the window ones (OVER stub) and the pivots/groupBys (Mem).

## What the orchestrator must decide

1. O-1 is a three-token fix in `Rel.scala` with a large semantic blast radius (every outer join under
   `letR`): land first, with an oracle case.
2. O-12 (eager DISTINCT) is the one optimisation with a measurable tier-l cost; adopt only on the
   differential oracle plus a `RenderTrace` row count on `melt`.
3. The NULL cluster (O-6, O-9, O-10, O-11) needs one decision on join/filter semantics for NULLs
   across the SQL and memory engines before any of the four is "fixed".
4. O-3/O-4/O-5/O-8 are lowering's files (posted); O-7 is surface's.

### Algebra examples (E-group relational examples under `core/examples/Algebra/`, the derived relations that use outer joins, set difference and `materialize`; 16 relations, 28 SQL texts, 2 refusals: `frameSuppliers_Bo` and `liveRows_De` are `Mem`)

| file | selects | depth | DISTINCT | temp stmts | ORDER BY | GROUP BY | OVER | joins | chars |
|---|---|---|---|---|---|---|---|---|---|

Reading the Algebra shapes: `lookupOr`/`lookupOrRight`/`enrich` (`withChannel_Ol`, `widened_Ss`) are
LEFT JOIN chains with the `coalesce` OUTSIDE the join (correct, O-4 does not bite); `antiJoin`
(`ordersWithNoCustomer_Ol`, `regionsWithNoName_Co`, `assetsWithNoReadings_Ss`, `unusedCustomers_Ol`)
is `EXCEPT` with a redundant `select distinct` on the right arm (O-26); `exceptRows` of two literals
(`goneByFriday_Iv`) is a bare `EXCEPT`; `materialize`/`materializeWithPK` used once (`calibsOnce_Kd`,
`calibsKeyed_Kd`) is one temp table (with the PRIMARY KEY hint); `closure` (`reachable_Bo`,
`frameParts_Bo`) is O-25. No Algebra relation puts an outer join under `letR`, so O-1 is not visible
in the corpus; `bug-b1`/`bug-b6` are the repros.
