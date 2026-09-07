# Ermine examples

These are examples of Ermine syntax and reports.

To make them available, depend on the artifact, and add to your `s:
SessionEnv`:

```scala
s.loadFile =
  SourceFile.inOrder(others...,
                     SourceFile classloader "com/clarifi/reporting/examples")
```

## Grouped example sets

Some subdirectories are self-contained example *sets*, each with its own
`README.md` and its own shared library that must be loaded first:

| directory | subject | library |
|---|---|---|
| `Ai/` | ten reports over **trees** — drilldowns, hierarchies, date-range calendars | `Ai/Common.e` |
| `Wide/` | nine reports over **wide** fact tables (20–36 columns) — window functions, pivots, unpivots | `Wide/Helpers.e` |
| `Lang/` | ten reports on the **language itself** — parser combinators, accumulating validation, State/Reader/Free monads, do-notation across monads, strings and markdown, trees and maps, foreign bindings, kinds and existentials | `Lang/Helpers.e` |
| `Present/` | nine reports over **presentation** — charts, styled grids, fulcrum reports, validation, drilldown lists, sort strategies, writers | `Present/Helpers.e` |
| `Time/` | eight reports over **dates and money** — as-of lookups, nearest-date joins, fiscal calendars, currency conversion, nullable arithmetic, framed windows, cohorts | `Time/Helpers.e` |
| `Algebra/` | eleven reports over **relational algebra** — outer joins with defaults, set operations, semi/anti-joins, transitive closure, deduplication, key/value schemas, self-joins, scans, comprehensions | `Algebra/Helpers.e` |

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
bin/ermine core/examples/Ai/Common.e    core/examples/Ai/SalesByRegion.e
bin/ermine core/examples/Wide/Helpers.e core/examples/Wide/Leaderboard.e
bin/ermine core/examples/Present/Helpers.e core/examples/Present/SalesDashboard.e
bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/StatementParser.e
bin/ermine core/examples/Time/Helpers.e core/examples/Time/ReadingHistory.e
bin/ermine core/examples/Algebra/Helpers.e core/examples/Algebra/OrderLedger.e
```

`tracker/tools/corpus-run.sh` does that for the whole corpus, one JVM per file or
all of it in one with `--batch`.

`shouldfail/` (and `Wide/shouldfail/`, `Algebra/shouldfail/`, `Time/shouldfail/`, `Present/shouldfail/`, `Lang/shouldfail/`) hold modules that must **not** compile,
with the expected diagnostics recorded in the matching `RESULTS.md`;
`incomplete/` holds modules on which row inference is incomplete or slow — read
`incomplete/README.md` before adding a file there, because `core/test` walks
every `.e` under `core/examples`.
