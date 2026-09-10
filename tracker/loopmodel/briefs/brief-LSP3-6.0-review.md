# Review brief: LSP Stage 3 item 6.0 — `core/test` determinism (the loadInSeries flip), and the temp-tree leak

You are reviewing item 6.0 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `257f032`
plus the UNCOMMITTED deliverables: `scalacheck-binding/src/main/scala/TestInterfaceKey.scala`, `TestErmine.scala`,
`TestInterfaceRoundTrip.scala`, `TestInterfaceConcreteRow.scala`, and the report
`tracker/loopmodel/LSP3-6.0-HYGIENE.md`). Implementer's brief `tracker/loopmodel/briefs/brief-LSP3-6.0.md`; item of
record `tracker/LSP-ROADMAP.md` § Stage 3, 6.0; gate tiers `tracker/GATE-POLICY.md`. You edit NOTHING except a
scratch directory `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.0/`
and your report `tracker/loopmodel/LSP3-6.0-REVIEW.md`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs; `sbt core/compile core/copyResources` before any
`bin/ermine` gate; delete every `.ei` you cause (never the checked-in ones under `tracker/g1-*`); do not touch
`tracker/lean/`; no commits. The delivered diff is claimed TEST-SIDE ONLY (no `core/src/main` change): verify that
first with `git status`/`git diff --stat` — if anything under `core/src/main` moved, the tier grows to Tier 1 and
you say so at the top of your report.

1. **The mechanism.** The report (§1) says: `TestInterfaceKey`'s second property flipped `ermine.loadInSeries=true`
   process-globally for ~15-30 ms; `Session.loadModules` re-reads the flag per call; `loadModulesInSeries` does not
   subtract `s.loadedModules`; every fixture import map names the sourceless synthetic module `Test`; so a concurrent
   property's load dies with `Module not found: 'Test'`. Re-derive it from the code at HEAD (`Session.scala`
   `loadModules`/`loadModulesInSeries`/`SourceFile.forModule`/`NotFound`, `TestErmine.scala` `baseEnv`/`imps`,
   pre-fix `TestInterfaceKey.withProps` via `git show HEAD:scalacheck-binding/src/main/scala/TestInterfaceKey.scala`).
   Reproduce the deterministic half yourself: `sbt -batch -J-Xmx3g -Dermine.loadInSeries=true 'core/testOnly
   *TestLower'` must error on every property with that message. Then answer: is this the WHOLE explanation of F4
   review R-1, or could a second mechanism produce the same message? Check every other `System.setProperty` /
   `withProps`-like site in the test sources and in `core/src/main` for a process-global flag read per call
   (`loadInSeries`, `rowTrace*`, `useInterface`, `typeCheck`, `tautoDelete`, `topNormalise`, `foreign.tolerant`,
   `test.disjunction`, ...): list each with "read once into a val" or "read per call", and whether any test flips
   it at runtime. The report's rate argument (§1.1c: ~27 Test-naming loads/s against a ~16 ms window ≈ 0.4 deaths
   per run) — is the arithmetic right and are the inputs plausible?
2. **The fix.** (a) The property that flipped the flag now calls `Session.loadModulesInSeries(List("KeyB"))`
   directly: confirm it asserts exactly what it asserted before (compare the pre/post property text and the
   assertion), that the serial schedule really is exercised (not the parallel one), and that nothing was removed,
   skipped or weakened anywhere in the four files (count properties before/after per suite). (b) The `withProps`
   whitelist: read it; can a future caller still flip a per-call-read property by another route? Is forcing
   `RowTrace`'s vals before the window correct and sufficient? (c) The residual: `ermine.rowTrace` /
   `ermine.rowTrace.draws` are still flipped process-globally — are they genuinely read once at class init
   (show the `val`s), and is there any path by which a concurrent suite observes the flipped value?
3. **The leak (6.0.4).** Which temp trees leaked before (the report says `ermine-key`, `ermine-rt`; `ermine-ei-corpus`
   and `ermine-row` already self-deleted) — verify against HEAD. The new `ErmineFixture.deleteTree` and the
   `finally` sites; the shared corpus now deleted from a SHUTDOWN HOOK instead of a refcount: is that hook safe
   when the suite is run under `sbt` with `Test / fork := false` (the hook runs at sbt JVM exit, not at test end
   — so does the tree persist for the life of an interactive sbt session? is that acceptable, and is it stated?),
   and can it delete a tree another property is still reading? After your full run: `ls -d /tmp/ermine-*` must be
   empty (record the count before you start, too), and `find core/examples tracker/lsp-tests -name '*.ei'` empty.
4. **Gates, re-run ONCE (Tier 0 + the item's own).** `sbt core/compile core/copyResources`; `sbt 'core/testOnly
   *TestLoopTrace'` 720/720; `tracker/tools/corpus-run.sh --batch` 85 / 69 / 0 over 154; `tracker/tools/repl-smoke.sh`
   (the implementer reports 8 groups / 66 checks — the tracker's "7/7" is stale; say which is right);
   `tracker/tools/lsp-smoke.sh` 185; then the item's THIRD full run `sbt -batch -J-Xmx3g core/test` ALONE on the tree
   (the implementer's two were 943/943 at 1,533 s and 1,463 s): totals, wall time, exit code. If it is anything but
   943/943 with exit 0, that is the headline of your report. Also run the pinning recipe once at default workers
   (`sbt -batch -J-Xmx3g 'core/testOnly *TestLower *TestNewPipeline *TestTolerantCheck *TestTolerantRead
   *TestStage1Pins *TestEditorBuffers *TestInterface* *TestScopes *TestReplDifferential'`) and record it.
5. **The report and the follow-up.** Is `LSP3-6.0-HYGIENE.md` accurate against what you found (every number you
   re-measured, side by side)? The recommended follow-up ticket — make `loadModulesInSeries` subtract
   `s.loadedModules` — do you agree it is not a live bug today (enumerate the non-test callers of
   `loadModulesInSeries`: `bin/ermine`/REPL under `-Dermine.loadInSeries`, `ei-diff.sh --batch`, `corpus-run.sh`,
   `perf-bench.sh`, the LSP `Resident`?), and is Tier 1 the right tier for it?

Report format: a findings table (id, severity blocker/medium/nit, CONFIRMED/PLAUSIBLE/REFUTED, one paragraph each),
then the gate table (implementer's figure vs yours), then a verdict: ADVANCE (commit as is), FIX-THEN-ADVANCE
(list the fixes), or BLOCK (why). Your numbers are the ones that go into the trackers, so state each once and
exactly. STOP after the report.
