# Role `optimizer`: the rewrites, and the SQL shape they leave (audit, read-mostly, 2.5 h)

Own: `core/src/main/scala/com/clarifi/reporting/relational/Optimizer.scala`, `Rel.scala` (the
smart constructors `Join.apply`, `Minus`, `Annotated`, `Relation.combineFilters`),
`Predicate.scala`/`Predicates.simplify`, `Ext.scala`, `Typer.scala`, `Op.scala` (`Op`
simplification, `columnReferences`, `guessType`).

Part 1, correctness of every rewrite (each with a repro):
- `Join.apply` coalesces two `AggregateByGroup`s over the same relation into one: is the
  natural-join semantics preserved when the two group sets differ only in order, when an
  aggregate name equals a group column, when one side is filtered?
- `combineFilters`, `Predicates.simplify` (three-valued logic with NULLs: `NOT (a = NULL)`,
  `x <> x`, `And`/`Or` with a constant), `simpleProject`/`projectAggregate`/
  `exceptAggregate`/`renameAggregate` (renaming a grouping column; projecting one away),
  `flattenProjection` (composition when an outer op refers to an inner alias twice, or to a
  column shadowed by the inner projection), literals under `smallLitSize` turned into
  predicates (`litrel` to predicate: NULLs, duplicates, a literal with zero rows, one with
  every column), `LetR` of a small literal inlined (`Optimizer.scala:376-385`) versus the
  original `pk`, `Limit` pushed or not pushed through `Project`/`Filter`, `Note` transparency,
  the `AugmentSM` paths (are they reachable? `SMEnv.scala` is all `TODO`: dead code?).
- `Typer`: header computation for every constructor, `sys.error` on a typing failure (who
  catches it? what does a user see?).

Part 2, missed optimisations, ranked by the cost they would save on the Sales corpus at tier l:
- Predicate pushdown through `Project`/`Combine`/`Rename`/`Union`/`JoinOn` (into the smaller
  side), `Limit` through a top-level order-preserving `Project`, projection pruning (columns
  fetched, never used), `DISTINCT` elimination when a key is known, `ORDER BY` pushed into SQL
  instead of `relational.sorting` in Ermine, `Filter` after `AggregateByGroup` as `HAVING`,
  a `Union` of literals as one literal, self-joins on the same table with the same filter,
  nested `SELECT ... FROM (SELECT ...)` chains that a flattening would remove (count the
  nesting depth of real queries), temp tables for a `LetR` used once.
- Then the survey: dump the SQL of EVERY report relation in `core/src/test/resources/doc/*.e`
  (the `Fetch*`/`DbFetch*`/`Sales*` fixtures), `core/src/test/resources/modules/Doc/*.e`, and
  the relational examples under `core/examples/` (the E-group examples; see
  `tracker/loopmodel/E1-EXAMPLES.md` §7.1 for which ones have relations), through BOTH
  scanners. Put the SQL in `scratch-sql-audit/survey/<module>-<binding>.{sqlite,mssql}.sql`
  and a table in your findings: module, binding, nesting depth, subqueries, DISTINCTs, temp
  tables, whether the sort is in SQL, rows the live server returns vs rows the report uses
  (`scripts/db.sh sql ErmineSales` executes the SQL Server text against tier s; the
  `DbFetch*` fixtures name real tables). This table is the optimisation backlog's evidence.

Deliver `tracker/sql-audit/FINDINGS-optimizer.md`. Post each WRONG and each WASTE that another
role's code must change (a new emitter construct, a scanner shape) to the board as found.
