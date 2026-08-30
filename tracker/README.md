# Scala 3 migration — tracker

Branch `scala3-migration`. **Status: done and verified.**

```
sbt compile      # all six modules, 0 errors
sbt core/test    # 733 of 734 properties pass (the one failure is pre-existing)
bin/ermine       # the REPL: 129 modules load and type-check
```

## Read in order

| | |
|---|---|
| [00-PLAN.md](00-PLAN.md) | the survey, and the blocker: three dependencies no longer resolve |
| [01-parsers.md](01-parsers.md) | vendoring and porting `scalaparsers` |
| [02-scalaz-and-machines.md](02-scalaz-and-machines.md) | **why scalaz 7.2.36 and not 7.3**; `machines`; `f0` |
| [03-core-progress.md](03-core-progress.md) | porting `core` — every class of change, grouped by cause |
| [04-repl-working.md](04-repl-working.md) | getting the REPL up: jline 3, foreign declarations, `ermine.typeCheck` |
| [05-findings.md](05-findings.md) | two pre-existing bugs found while testing (not migration regressions) |
| [06-tests.md](06-tests.md) | porting the 2.11 test suite, and the real regression it caught |
| [07-ffi-verification.md](07-ffi-verification.md) | what actually verifies the `.e` FFI surface, and the one blind spot |

## What the branch contains

- an sbt 1.10 / Scala 3.3.8 build replacing the sbt 0.13 one (parked in `legacy-build/`)
- three vendored modules for libraries that are no longer published:
  `parsers/` (ermine-parser), `machines/` (scala-machines), `f0/`
- `scalaz-compat/` for two scalaz APIs removed after 7.0 (`IterV`, `concurrent.Promise`)
  plus a reimplementation of `scalaz.std.indexedSeq` against 2.13 collections
- `core/` ported in place — language, REPL, relational engine, SQL, writers
- `bin/ermine`, and REPL tests in `repl-tests/` driven by `tools/repl-smoke.sh`

## The one thing most likely to bite you next

Scala 3 case class companions no longer extend `FunctionN`, and Ermine's `.e`
modules bind companions as functions in 30+ places. `Session.foreignLift` now
re-resolves such calls against the receiver's own class. If you add foreign
bindings, that is the mechanism keeping them working — see
[06-tests.md](06-tests.md).

## Tools written along the way

In `tools/`: `deprocedure.py` (Scala 2 procedure syntax), `force_views.py`
(2.13 lazy `mapValues`/`filterKeys`, driven by the compile log),
`lambda_parens.py`, and `errs.py` (summarises an sbt compile log). They are kept
because they encode which sites were changed and why, not because they are
general-purpose.
