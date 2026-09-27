# Role `surface`: what reaches SQL, and what silently stays in Ermine (audit, read-mostly, 2.5 h)

Own: `core/src/main/scala/com/clarifi/reporting/ermine/session/Lib.scala` (the relational
foreign functions, roughly lines 300-1000), the stdlib modules `core/src/main/resources/modules/
{Relation,Native/Relation,Syntax/Relation,Scanners,DB}.e` and `Relation/*.e`, `Layout/Fetch*.e`,
`Layout/Scan*.e`, `relational/Mem.scala` (the in-memory operations), `Op.scala`/`Predicate.scala`
(the builtins available to a relation expression and their in-memory evaluation:
`Op.eval`, `Predicates.toFn`), `PrimExpr.scala` (arithmetic, ordering, `Show`).

Questions to answer, each with a repro:
1. The map: for every relational operation the stdlib exports (`filter`, `join`, `joinOn`,
   `union`, `minus`, `except`, `project`, `rename`, `combine`, `limit`, `sort`/`orderBy`,
   `aggregate`, `aggregateByGroup`, `groupBy`, `sumBy` and friends, `pivot`, `window`/`rank`,
   `accumulate`, `process`, `memo`, `letR`, `letM`, `hashJoin`, `mergeJoin`, `leftJoin`,
   `unifyFields`, the `Relation.Row` operations, `Layout.Fetch`'s `scanRelation`/
   `scanRelationInOrder`/`aggregateByGroup` wrappers), which `Relation`/`Mem` constructor it
   lowers to (file:line), and therefore whether it runs in SQL or in Ermine. Mark every one
   that lands in `Mem` when SQL could do it. `groupBy` is the known case (OBSERVABILITY §9):
   which of its common uses (`groupBy k (sumBy c)`, `groupBy k count`, `groupBy k (maxBy c)`)
   have an exact `AggregateByGroup` form that a lowering could pick WITHOUT changing the
   surface, and what would the rule be?
2. Two evaluators, one meaning: every `Op` builtin and `Predicate` evaluated by `Op.eval`/
   `Predicates.toFn` in memory also gets compiled by `SqlScanner.compileOp`/
   `compilePredicate`. List the builtins; for each, do the two agree on: NULL propagation,
   integer vs double division and `%`, string comparison (case, collation), date arithmetic
   (`Op.scala:319`), `dateDiff`, string functions, `if`/`case`, comparisons across types,
   `-0.0` and NaN, rounding. A report that runs in memory on one path and in SQL on another
   (a `join` of a `Mem` and a `Relation`, a `filter` after a `groupBy`) can see BOTH.
3. `Mem.scala` correctness: `GroupByM`, `AccumulateM`, `Pivot`, `HashLeftJoin` (NULL fill for
   the outer side), `MergeOuterJoin`, `DifferenceM`, `UnionM` (duplicates), `LimitM` with an
   order, `RenameM`'s `b` flag, `ProjectM` flattening. The 2.13 view hazard (`filterKeys`,
   `mapValues`, `keySet` views, `Map#--`) anywhere a record is compared or hashed.
4. The `Fetch` path: `Layout.Fetch`'s `scanRelation` runs one SQL statement per scan and hands
   rows to Ermine; a report that scans the same relation twice (TopN's `sales` and `sales #
   {region}`) issues two queries. Which fixtures do that, and is a `memo`/`letR` available on
   the surface that would fold it (no new syntax)?
5. Types on the boundary: a `Relation`'s row type (Ermine) vs `Header` (`PrimT`): where a
   `Maybe` becomes nullable and back; what an Ermine `Int` is on the wire (`Int` vs `Long`);
   Date/Timestamp; how `Field` evidence (WP-37) names a column.

Method: read `Lib.scala` with the stdlib beside it; write small modules under
`scratch-sql-audit/surface/` and dump their SQL through the REPL (common brief) to confirm the
map; for evaluator disagreements, evaluate the same expression both ways in the REPL (in
memory via a literal relation processed by a `Mem` op; in SQL via `dumpQuery` and python3's
`sqlite3`, or the live server).

Deliver `tracker/sql-audit/FINDINGS-surface.md`. The map (question 1) is a table and is the
first thing in the file. Post each WRONG to the board as found.
