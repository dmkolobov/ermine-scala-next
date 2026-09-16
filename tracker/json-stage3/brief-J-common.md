# Rules for every JSON Stage 2/3 agent (implementer, reviewer, porter)

Read first: `tracker/JSON-STAGE3-PLAN.md` (the wire contract is binding), then the design
note sections your brief names in `tracker/JSON-API-DESIGN.md`, then `tracker/GATE-POLICY.md`.

## Toolchain (Scala 3 branches)

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
sbt -batch core/compile core/copyResources          # compile alone does NOT copy the stdlib .e
sbt -batch 'core/testOnly com.clarifi.reporting.TestJson com.clarifi.reporting.TestSchema'
bin/ermine                                          # REPL, ~7 s boot; `:json <expr>`, `:load file.e`
bin/ermine-schema --help                            # schema exporter CLI
```

- Property tests live in `scalacheck-binding/src/main/scala/` (compiled into core's tests).
  `ErmineFixture` (TestErmine.scala) gives `defAndEval`, `sessionProof`, `session`,
  `loadStatements`; `TestSchema.defAndType`, `TestSchema.shape(depth)` generate random Ermine
  types with random values (reuse them; do not fork copies).
- Piped REPL scripts: never feed a bare `let`/`case` line (it floods `|>` prompts); wrap in
  `:type (...)` or put it in a module and `:load` it.
- Files here are LF, but some older `.scala`/`.e` files are CRLF: check with `file` and keep
  a file's endings (edit byte-wise; python `read_text`/`write_text` rewrites them).
- In a worktree: `cp target/ermine-classpath tracker/repl-classpath.txt` (after `bin/ermine`
  has created it) before `tracker/tools/repl-smoke.sh` / `lsp-smoke.sh`; never commit that
  file (`git checkout tracker/repl-classpath.txt` before reporting).
- Node is at `~/.local/bin/node` (v24). Put any npm scratch install under your scratchpad
  unless your brief says the package is part of the deliverable.

## Scala dialect (the code is copied verbatim to the Scala 2.11 branch)

Implicit parameters and implicit objects only: no `given`/`using`/`enum`/`extension`/
`export`, no top-level definitions, no `derives`, no trailing-comma-only syntax, no
`Either#map`/`flatMap` (use `.right.map`), no `scala.util.Using`, no `LazyList` (2.13+), no
`Seq#sortInPlace`, no `.toSeq` assumptions about mutability, no `CollectionConverters`
(use `scala.collection.JavaConverters._`, deprecated but present on both), no string
interpolation `f""` edge cases -- `s""` is fine. Java APIs: JDK 8 only (no `var`-style Java
11+ calls such as `String#isBlank`, `Files.readString`, `HttpClient`). If in doubt, write it
the way `json/Encode.scala` and `json/Schema.scala` are written.

## Testing standard

Every feature is property-tested with scalacheck generators over RANDOM DECLARATIONS AND
VALUES (generated Ermine source loaded as a module), not hand-picked examples. Example
tests are allowed only as pins beside a property (a fixture, a documented corner). A
property that can pass vacuously must say how it was checked not to (a mutation, a
deliberately broken build run once, a discard count).

## Gates (Tier 0 before handing back; the orchestrator runs the full suite at landing)

1. `sbt -batch core/compile core/copyResources`.
2. Your stage's suites plus `TestJson`, `TestSchema`, `TestNamedFields` (61 on the base).
3. `sbt -batch 'core/testOnly *TestLoopTrace'` (720/720).
4. `tracker/tools/corpus-run.sh --batch <scratch dir>` then
   `python3 tracker/tools/corpus-verdicts.py <scratch dir>`: 89 LOADED / 79 REJECTED /
   0 UNKNOWN over 168, unchanged. Do not add files under `core/examples/` (it moves the
   count); test modules go under `core/src/test/resources/` or are generated.
5. `tracker/tools/repl-smoke.sh` and `tracker/tools/lsp-smoke.sh` green.
Record every number with the log path in your report. Do NOT run the full `core/test`
(the orchestrator runs it once per landing), and never re-run a suite you have a green log
for unless your code changed since.

## Conduct

- Work only in your own worktree and branch. Do not commit: leave the tree dirty; the
  orchestrator commits after review. Never push, never merge, never touch other worktrees
  or the main checkout, never `git stash` bare.
- Parallel is the default: run independent sbt/JVM jobs concurrently.
- Parked, do not work on: the REPL `null` binding quirk; the 2.11 operator-constructor
  fixity divergence.
- Budget: your brief gives hours. At the budget, write up and stop.
- Report (your final message, and the same text in `tracker/json-stage3/report-<id>.md`):
  what was built (files), decisions taken in code that the plan did not fix, departures
  from the plan with reasons, gate numbers with log paths, open issues, and anything the
  next stage must know. Plain prose and tables, no marketing.
