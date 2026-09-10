# Brief: LSP Stage 3, item 6.0 — make `core/test` deterministic (pin first, then fix, else serialise)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`. sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time — never two sbt or bin/ermine processes at once, and do not run any
JVM in the background while another runs. Do not touch `tracker/lean/`. No commits. Delete every `.ei` you cause
(never the checked-in ones under `tracker/g1-*`). Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.0/`.
The item of record is `tracker/LSP-ROADMAP.md` § "Stage 3", item **6.0** — read it first, then
`tracker/GATE-POLICY.md`, then `tracker/loopmodel/F4-REVIEW.md` row R-1 (the original sighting) and R-5.

THE FACT. `sbt core/test` on one unchanged tree (F4's reviewer, 2026-09-09) was 943/943 on one run and
`Total 943, Failed 0, Errors 1, Passed 942` on the other — `TestLower :: "3.4a.negation applies primNeg to the whole
chain"` erroring with `scalaparsers.Death: Module not found: 'Test'`. Never reproduced in isolation (TestLower alone
2x; TestLower + TestInterfaceConcreteRow 2x). The suite runs in ONE JVM (`build.sbt`: `Test / fork := false`),
test classes in parallel.

THE MECHANISM IS NOT KNOWN. R-1 blamed six suites using `Session.depCache`/`loadModules` without
`ErmineFixture.literalLock`. A code read (2026-09-09, the orchestrator) does NOT confirm that path, and you must not
write a fix against it unless your probe shows it. What the read established — verify it, do not trust it:
- The message comes from exactly one place: `Session.SourceFile.NotFound.contents` (`Session.scala` ~:342),
  reached via `SourceFile.forModule("Test")` when `s.loadFile("Test")` has nothing. Callers that can ask for "Test":
  `Session.loadModules` → `deps` (when "Test" ∈ moduleNames and ∉ `s.loadedModules`), `depsPrime` (when some cached
  Dep's `imports` names "Test"), `Session.load`'s import loop, `Session.eval` (which calls loadModules with the
  import map — `ErmineFixture.imps` contains `"Test" -> all`).
- Every fixture seeds `"Test" -> CheckMethod.Interface` into `baseEnv.loadedModules` (`TestErmine.scala` ~:44) and
  every property runs on `mkEnv = envLock.synchronized { baseEnv.copy }`. So a failing session LACKED that entry.
- Nothing on the dep-cache path can remove a `loadedModules` key. `SessionEnv.+=` (the forked-make merge,
  `SessionTask.joins`) is a union. The only removers are `SessionEnv.:=` (fixture writeback, under `envLock`) and
  `Session.reloadChangedModules` (`-- scrubbing`; no test calls it). `ErmineFixture.loadStatements` strips "Test"
  from the rendered import lines, so no Literal's Dep imports "Test".
- `Session.Literal` equality is by module NAME (`Session.scala` ~:311) and the dep cache is process-global — real
  shared state, guarded by `literalLock` only where callers remember. Whether it can produce THIS symptom is the
  open question.

## What to do

6.0.1 PROBE (no behaviour change; everything behind `-Dermine.test.probe=true` or equivalent, so the shipped suite is
      byte-for-byte the same when it is off). Instrument, at least: (a) `ErmineFixture.mkEnv` — when the copy
      handed out lacks "Test" in `loadedModules`, dump fixture identity (System.identityHashCode), thread, the
      `loadedModules` keys, and a stack; (b) `ErmineFixture.loadModules`' writeback — when `s` lacks "Test" at
      `baseEnv := s`, same dump; (c) `Session.loadModules`/`deps`/`depsPrime`/`load` — when about to call
      `forModule("Test")`, dump which caller, `s.loadedModules.keySet`, and whether the request came from
      `moduleNames` or from a cached Dep's `imports` (and WHICH Dep/file); (d) `SessionEnv.:=` and `+=` when the
      result lacks "Test" but the receiver had it. Keep a per-fixture writeback counter so a dump can say "the N-th
      writeback". Dumps go to a file in scratch, not stdout.
6.0.2 REPRODUCE, budget one iteration (about a working day of machine time, NOT more): first the module-loading
      suites together — `sbt -batch -J-Xmx3g 'core/testOnly *TestLower *TestNewPipeline *TestTolerantCheck
      *TestTolerantRead *TestStage1Pins *TestEditorBuffers *TestInterface* *TestScopes *TestReplDifferential'` —
      up to five times; you MAY raise ScalaCheck's concurrency for these pinning runs only (`Tests.Argument(
      TestFrameworks.ScalaCheck, "-workers", "4")`, or a `-Dermine.test.workers` property you add) and you must
      say so; then the full `sbt -batch -J-Xmx3g core/test` up to three times (each is ~23 min). Record every run:
      command, wall time, pass/fail totals, any probe dump. A firing probe NAMES the mechanism: write it down with
      the dump, then 6.0.3a. No firing within the budget: 6.0.3b. Also record whether the failure, when it happens,
      is always TestLower or moves.
6.0.3a FIX against what fired — the smallest change that removes the race at its source (a lock taken where it is
      missing, a copy where a shared object was handed out, a key that carries content, ...). Then re-run the
      pinning recipe that fired, with the probe ON: it must not fire again over at least as many runs as it took
      to fire the first time, and the full suite twice.
6.0.3b FALL BACK to determinism BY CONSTRUCTION: run the module-loading suites serially. Prefer tagging just those
      classes (sbt `Test / testGrouping` with a serial group, or `concurrentRestrictions` with a tag on them) over
      `Test / parallelExecution := false` for the whole project, which is the last resort. Measure `core/test`
      wall time before and after, once each, on a machine with load < 1.5, and record both. Explain why the
      mechanism you chose actually serialises the classes you name (sbt's in-process grouping semantics are not
      obvious — show it, e.g. with timestamps in the probe log).
6.0.4 THE TEMP LEAK (R-5): `TestInterfaceConcreteRow.scala` :232 stages the corpus into
      `Files.createTempDirectory("ermine-ei-corpus")` and never deletes it (3.5 MB per run); `TestInterfaceKey`
      :59 (`ermine-key`), `TestInterfaceRoundTrip` :48 (`ermine-rt`) and `TestInterfaceConcreteRow` :78
      (`ermine-row`) — check which of those already delete. Make every one of them delete its tree (a `finally`,
      or a shutdown hook for the `lazy val corpus` shared by two properties). You may delete the existing
      `/tmp/ermine-ei-corpus*`, `/tmp/ermine-key*`, `/tmp/ermine-rt*`, `/tmp/ermine-row*` droppings — nothing
      else under /tmp. Verify: after a full run, `ls -d /tmp/ermine-*` shows nothing new.
6.0.5 GATES (Tier 0, GATE-POLICY): `sbt core/compile core/copyResources`; `TestLoopTrace` 720/720;
      `tracker/tools/corpus-run.sh --batch` 85 / 69 / 0 over 154; `tracker/tools/repl-smoke.sh` 7/7;
      `tracker/tools/lsp-smoke.sh` 185. Plus the item's own: TWO consecutive full `core/test` runs green
      (943 + nothing new, or say what moved); a reviewer will run a third. If your fix is 6.0.3a and lives in
      non-test code (Session/SessionTask/SessionState), say so loudly — that makes it a shipped-behaviour change
      and the reviewer's tier grows.
6.0.6 REPORT `tracker/loopmodel/LSP3-6.0-HYGIENE.md`: the run table (every run), the mechanism (with dump) or the
      statement that none fired and what was tried, the fix or fallback with its measured cost, the diff summary,
      the leak fix, every gate number. Outcomes: (GREEN) pinned and fixed, two full runs green; (GREEN-FALLBACK)
      serialised, two full runs green, cost recorded; (PARTIAL) which step, why. No silent weakening; do not
      remove or skip any property; do not edit `tracker/LSP-ROADMAP.md` (the orchestrator does). STOP after the
      report — a reviewer re-runs the gates once.
