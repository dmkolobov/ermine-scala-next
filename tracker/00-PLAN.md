# ermine-scala → Scala 3 migration

Branch: `scala3-migration`
Goal: Scala 3 build with a **working Ermine REPL**.

## Findings from survey (2026-08-29)

Original build: sbt 0.13.5, Scala 2.11.5, scalaz 7.0.7, sbt 0.13 `<<=` DSL.
Total `core` main+test Scala: ~35k LOC.

### Blocking problem: three deps are gone from Maven Central
`scala-parsers`, `com.clarifi %% f0`, `machines %% machines` do not resolve.
Even the original 2.11 build cannot be built today.

**Resolved**: all three are on GitHub under the `ermine-language` org:
- `ermine-language/ermine-parser`  → the `scalaparsers` lib (v0.2.3, exactly what build.sbt wants), 1449 LOC
- `ermine-language/scala-machines` → `com.clarifi.machines`
- `ermine-language/f0`             → `com.clarifi.analytics.util`
Cloned to `~/.local/ermine-toolchain/upstream/`.
Strategy: **vendor** these into the build as source modules and port them too
(no Scala 3 artifacts are published for any of them).

### Dependency cone of the REPL
The REPL entry point is `com.clarifi.reporting.ermine.session.Console`.
- `com.clarifi.reporting.ermine.**` = 45 files / 11.6k LOC — the actual language.
- `machines` is used **only outside** the ermine package. 
- `f0` is used by exactly one ermine file: `session/foreign/Fold.scala`.
- Only 8 ermine files reach outside the package, mostly into
  `com.clarifi.reporting.{PrimT,PrimExpr,...}` and `relational` (via `Lib.scala`
  builtins) and `backends.{SqlErmine,Runners}` (one line in `Console.scala`).

So the language+REPL is separable from the reporting/SQL/charting stack.

### Target toolchain
- JDK 21 (Temurin) — installed at `~/.local/ermine-toolchain/jdk-21.0.12.1+1`
- sbt 1.x + scala-cli via coursier — `~/.local/ermine-toolchain/bin`
- Scala 3 (LTS line)
- scalaz 7.3.9 (has `_3` artifacts; 7.0.7 API drift must be fixed)
- jline 1.0 → jline 3 (Console.scala uses ConsoleReader/Terminal/completors)

## Staging
1. Toolchain + branch + tracker ✅
2. Vendor + port `scalaparsers` to Scala 3 ✅ (`01-parsers.md`)
3. Port ermine language core to Scala 3 ✅ (`03-core-progress.md`)
4. Port `session` + `Console`, get REPL to start ✅ (`04-repl-working.md`)
5. Load Prelude; expand ported surface as far as needed ✅ — the whole of
   `core` compiles, and all 129 Prelude/Layout modules load and type-check
6. Tests ✅ (`06-tests.md`) — 733/734 properties pass

In the end nothing had to be held out of the build except
`writers/jfx/Process.scala`, which needs `scalaz.concurrent.Promise` on a
JavaFX path the REPL never touches.
