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

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
bin/ermine core/examples/Ai/Common.e    core/examples/Ai/SalesByRegion.e
bin/ermine core/examples/Wide/Helpers.e core/examples/Wide/Leaderboard.e
```

`tracker/tools/corpus-run.sh` does that for the whole corpus, one JVM per file or
all of it in one with `--batch`.

`shouldfail/` (and `Wide/shouldfail/`) hold modules that must **not** compile,
with the expected diagnostics recorded in the matching `RESULTS.md`;
`incomplete/` holds modules on which row inference is incomplete or slow — read
`incomplete/README.md` before adding a file there, because `core/test` walks
every `.e` under `core/examples`.
