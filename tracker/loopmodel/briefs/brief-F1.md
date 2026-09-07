# Brief: F1 — two runtime fixes from the corpus programme: the MapView panic (A1) and the piped-console loop (A2)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the commit the orchestrator
names (S3 committed; the row-solver defaults adopted; the five example groups committed). Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time; sbt allowed; long runs under `setsid nohup`
with a log and a driver that fails on a non-zero build; delete `.ei` you cause; no commits; do not touch
`tracker/lean/`. Ticket: `tracker/TICKET-stdlib-findings.md` items A1 and A2 (read them and the cited report
sections: E1 §7.2, E1-REVIEW "MapView", E4 §4.6/§4.7, E4-REVIEW, E5 finding 4).

## F1.1 — A1, the MapView panic (Scala 2.13 migration leftover)

`record#` returns a `MapView`; `scalaRecord#` (`Lib.scala:988`, `case Prim(t: Map[...])`) panics when forced and
would itself return a `MapView` (`:1007`); `scalaRecordIn#` (`:1012`, live at `Layout/Report.e:1594,1608`)
matches `Map` the same way. Affected: `Relation.Pivot.pivot`, `Relation.Predicate.all`, `Record.header`,
`Record.anyRecordOrd`, `Relation.Sort.partialRecordOrd`, `Relation.nonEmptyRelation`, `Layout.Chart.srecKeys`,
`Layout.Presentation`, `Native.Record.header#`; `core/examples/PivotTest.e`'s `pivotData` has panicked for years.
`Relation.relation` is NOT affected. (a) Reproduce each named consumer's panic with a one-line REPL forcing
(`PivotTest.pivotData`, `Predicate.all`, `Record.header {a = 1}`), recording the panic text. (b) Fix: `.toMap` at
988, 1007 and 1012 (grep every other `record#`/`MapView` consumer in `Lib.scala` and the `Native/*.e` foreign
bindings for the same pattern; list what you checked). (c) A TEST THAT FORCES A PIVOT (laziness is why nobody
saw this): a `core/test` property that evaluates `PivotTest.pivotData` (or an equivalent inline module) to a
value and checks its rows, plus `Predicate.all` and `Record.header`, so the fix cannot regress silently. (d)
Gates: `core/test` (913/914 known + your new test passing); `TestLoopTrace` 714/714; the row trace byte-identical
on two corpus groups (the loop is untouched); the five example groups' modules still load (`corpus-run.sh
--batch` on the wired 151-file corpus: verdicts unchanged); every module the E-reports listed as panicking when
forced (`Wide/MediaSpend`'s two pivots, `Present/FulcrumPanel`, `Algebra/SoftSchema`'s `Relation.Pivot` use,
`PivotTest`) now evaluates in the REPL — record the before/after; `sql-render.sh` renderings unchanged.

## F1.2 — A2, `Console.other` loops forever on a piped line containing `case`/`let`/`where` as a substring

`Console.scala:149`: `readLine` returns `null` at EOF, `null == ""` is false, so `blank` never flips; the loop
appends `"\n" + null` and re-runs `balanced()` and three `contains` over the growing string. Minimal inputs:
`printf 'staircase\n' | bin/ermine` (thousands of `|>` prompts, never exits) and E5's `printf '"complete"\n' |
bin/ermine`; `printf 'staircas\n' | bin/ermine` exits cleanly; one trailing blank line also ends it. (a)
Reproduce both with a 20 s cap and count the prompts. (b) Fix: treat `null` as EOF (end the continuation and
process what was read); and stop matching the keywords as substrings — match them as tokens (word boundaries)
so `staircase`/`palette`/`complete` do not open a continuation. Say which of the two changes fixes which
symptom and keep both. (c) Gates: `repl-smoke.sh` (35 checks) and `lsp-smoke.sh` (98); a new smoke check for
each minimal input (exit 0, one prompt, the binding evaluates); the multi-line `case`/`let`/`where`
continuation still works interactively (`printf 'f x = case x of\n  1 -> 2\n\nf 1\n' | bin/ermine` — record the
output); `core/test` unchanged.

## Report
`tracker/loopmodel/F1-FIXES.md`: reproductions before/after, the diffs, every gate with numbers, the list of
consumers checked; update `TICKET-stdlib-findings.md`'s A1/A2 entries to "fixed in <commit>" (the orchestrator
fills the hash) and `tracker/ROW-CONSTRAINT-STATE.md` only if anything solver-visible changed (nothing should).
Outcomes: (GREEN) both fixed with the tests; (PARTIAL) one fixed, the other's obstacle stated. No silent
weakening; report early.
