# SQL compilation audit (2026-09-26, overnight, autonomous)

The user's brief, verbatim: "Let's do an audit on the health of our compilation-to-sql features
for Ermine. In particular, we want to look for bugs *and* optimization opportunities. While I
sleep, launch a fleet of agents to coordinate amongst themselves and make this a top-tier
compiler. Do not diverge from the design of ermine as a whole. Avoid user-facing
syntax/signature changes."

Base: branch `widget-preview` at `900cebbc`. Work branch `sql-audit` (worktree
`ermine-scala-wt-sql-audit`), to be fast-forwarded onto `widget-preview` at the end. The user's
uncommitted edits in `ermine-scala-wt-widget-preview` are never touched.

## What "compilation to SQL" is here

An Ermine report's relations (`Relation.e`, `Relation/*.e`, `Layout.Fetch`) are lowered by
`ermine/session/Lib.scala` into the relational algebra of `relational/Rel.scala` (`Relation`),
`relational/Mem.scala` (`Mem`: operations Ermine evaluates itself) and `relational/Ext.scala`.
`relational/Optimizer.scala` rewrites them; `relational/SqlScanner.scala` compiles a `Relation`
to `sql/SqlQuery.scala` + `sql/SqlExpr.scala`; a dialect `sql/SqlEmitter.scala` prints SQL;
`sql/SqlExecution.scala`, `backends/SQLBackend.scala`, `backends/DB.scala` and `Run.scala` execute
it over JDBC; `RenderTrace.scala` counts rows read against rows used. Every relation literal
compiles to a table-value constructor, so most queries need no schema. The default runner (the
preview, TestRunner) executes on in-memory SQLite; the DB programme runs the same reports on the
local SQL Server (`scripts/db.sh`, `tracker/db/`). Nothing in this pipeline has been changed
since the Scala 3 migration except what the migration forced (`TestInMemoryScan` documents three
silent breakages it found).

## Phases

| Phase | Who | Output |
|---|---|---|
| A audit (parallel, read-mostly) | `emitter`, `lowering`, `optimizer`, `surface` | `tracker/sql-audit/FINDINGS-<role>.md` |
| A oracle (parallel, own worktree) | `oracle` | `TestSqlDifferential` + its findings |
| B triage | orchestrator | `tracker/sql-audit/WORKLIST.md`, ranked, file-partitioned |
| C implement (2 at a time, own worktrees) | `impl-*` | fixes + tests, reports |
| D review | `review-*` (never the author) | `scratch-sql-audit/REVIEW-*.md` |
| E land | orchestrator | commits on `sql-audit`, gates, fast-forward |
| F report | orchestrator | the morning artifact |

## Scope rules

- No user-facing syntax or signature change: no `.e` export changes, no new required arguments,
  no renamed bindings. Adding a private helper to a stdlib module is allowed only if a fix
  needs it; say so.
- The design stays: `Relation`/`Mem`/`Ext` split, the scanner's shape, the emitter traits. Within
  it, anything that makes the SQL correct, smaller, or cheaper is in scope.
- An optimisation is adopted only with evidence that results are unchanged: the differential
  oracle, the DB twins (`TestDbReports`), the doc fixtures (`TestRunner`), and, where it claims
  a cost, a rows-read or timing figure from `RenderTrace`/live SQL Server.
- Dialects: SQLite and SQL Server are live and are the bar. MySQL, Postgres and Vertica have no
  oracle here: change their emitters only to fix something demonstrably wrong at the text
  level, and say the change is untested live.
- Findings, not opinions: every finding carries a repro (a relation, the SQL it produced, the
  wrong or wasteful thing about it), a severity, and a proposed fix with its blast radius.
