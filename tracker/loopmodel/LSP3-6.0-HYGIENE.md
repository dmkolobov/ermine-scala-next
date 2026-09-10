# LSP Stage 3, item 6.0 — `core/test` determinism: the mechanism, the fix, the leak

Implementer, 2026-09-09.  Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`,
from HEAD `257f032`.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.0.md`; item of record `tracker/LSP-ROADMAP.md`
§ Stage 3 item **6.0**; gates per `tracker/GATE-POLICY.md`.  Scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.0/`.
ONE JVM at a time throughout; no commits; `tracker/lean/` untouched and no Lean built;
`tracker/LSP-ROADMAP.md` untouched; every `.ei` caused is deleted and `tracker/g1-baseline` is untouched.

**OUTCOME: GREEN.**  The mechanism is pinned (a process-global `System.setProperty` in
`TestInterfaceKey`, not the dep cache R-1 blamed), demonstrated deterministically, fixed at its source
in test code only, and verified: **two consecutive full `core/test` runs, 943/943 each, 0 failures and
0 errors**, with the temp-tree leak closed and every Tier-0 gate green.

## 1. The mechanism (PINNED, not inferred)

> `TestInterfaceKey`'s second property sets **`ermine.loadInSeries=true` with
> `System.setProperty` — process-globally — for about 15-30 ms in the middle of the run**.
> `Session.loadModules` re-reads that property **on every call**.  The suite runs in ONE JVM
> (`build.sbt`: `Test / fork := false`) with test classes in parallel, so for those milliseconds
> **every other property's `loadModules` takes the series branch**.  `loadModulesInSeries` is
> `for (m <- moduleNames) load(SourceFile.forModule(m), Some(m))` — it does **not** subtract
> `s.loadedModules`, the way the parallel branch does (`moduleNames.toSet &~ loaded`).  Every
> fixture import map names the synthetic module **`Test`**, which is seeded into
> `loadedModules` by `ErmineFixture.baseEnv` and **has no source file anywhere in the tree**
> (`find . -name Test.e` is empty).  So `forModule("Test")` answers `NotFound("Test")`,
> `Session.dep` asks it for `contents`, and `NotFound.contents` is
> `die("Module not found: '" + module + "'")` — `scalaparsers.Death: Module not found: 'Test'`,
> raised inside whichever property happened to be loading modules at that instant.

That is the whole of F4 review R-1.  The victim is *whoever is loading at that moment*, which is why
it was `TestLower` once and had never reproduced in isolation: **`TestLower` alone can never fire it —
nothing sets the flag.**  The R-1 hypothesis (six suites using `Session.depCache`/`loadModules` without
`ErmineFixture.literalLock`) is **wrong as a cause but right as a symptom**: those suites are exactly
the ones loading modules while `TestInterfaceKey` holds `literalLock`, so they are the population of
victims — but no dep-cache interaction is involved and no `loadedModules` key is ever removed.  The
brief's code read is confirmed on every point: `SessionEnv.+=` is a union, `:=` runs under the
fixture's `envLock`, `reloadChangedModules` is never called from a test, and `loadStatements` strips
`Test` from the rendered import lines.  **The session that dies has `Test` in `loadedModules` all
along** — the series loader simply never looks.

### 1.1 Evidence

**(a) The victim half, DETERMINISTIC.**  With the flag on for the whole JVM and nothing else changed:

    sbt -batch -J-Xmx3g -Dermine.loadInSeries=true 'core/testOnly *TestLower'
    -> Failed: Total 28, Failed 0, Errors 28, Passed 0     (18.5 s wall)
       every one: "Exception: scalaparsers.Death: Module not found: 'Test'"

The exact message, on the exact suite R-1 saw, 28 times out of 28.

**(b) The setter half, OBSERVED LIVE.**  Probe (§2) on, pinning recipe, three runs at ScalaCheck's
default worker count.  Every run logged the window and the series-branch call, from
`TestInterfaceKey.withProps` at the line that sets the property:

    90090.844 ms [pool-5-thread-11] WITHPROPS-SET: ermine.loadInSeries=true ermine.rowTrace=false
    90095.395 ms [pool-5-thread-11] LOADMODULES-IN-SERIES: modules=KeyB noSource= env=88375501 loadedModules=Builtin
          com.clarifi.reporting.ermine.session.Session$.loadModules(Session.scala:684)
          com.clarifi.reporting.TestInterfaceKey$.load(TestInterfaceKey.scala:80)
          com.clarifi.reporting.TestInterfaceKey$.$anonfun$2(TestInterfaceKey.scala:164)
          com.clarifi.reporting.TestInterfaceKey$.withProps(TestInterfaceKey.scala:101)
          ...
    90106.622 ms [pool-5-thread-11] WITHPROPS-RESTORE: ermine.loadInSeries ermine.rowTrace

Window widths measured: **15.8 ms** (run 1), **28.2 ms** (run 2), **14.1 ms** (run 3).

**(c) The rate matches the observed flake rate.**  In pinning run 1 the probe counted **8,414**
`Session.loadModules` calls over 277.8 s — **30.3 calls/s**, of which **7,600 (27.4 /s) name `Test`**
in their import map.  A 15.8 ms window therefore has an expected **0.43 deaths per run**, i.e. it
should kill a run roughly one time in two.  F4's reviewer saw exactly that: one run 943/943, the next
942 + 1 error.

**(d) What did NOT fire.**  Over five instrumented pinning runs the probe recorded **zero**
`MKENV-NO-TEST`, **zero** `WRITEBACK-NO-TEST` and **zero** `ENV-*-TESTLOSS` events: no fixture ever
handed out a session missing `Test`, and no `:=`/`+=` ever dropped the key.  The dep-cache/`literalLock`
story is excluded by measurement as well as by reading.  A cross-thread coincidence (a foreign
`LOADMODULES-IN-SERIES`) was **not** caught live in five runs — expected, at ~0.4 per run over
5 runs with 2 of those runs invalidated (see the run table) — which is why (a) and (b) are the
proof rather than a lottery ticket.

## 2. The probe (6.0.1) — and that it does not ship

Everything was behind `-Dermine.test.probe=true` (`Probe.on`, a `val`; every call site guarded, every
message by-name, so with the property off the code is unreachable and nothing is formatted).  Dumps went
to a scratch file named by `-Dermine.test.probe.file`.  Instrumented, per the brief:

| where | tag | fires when |
|---|---|---|
| `ErmineFixture.mkEnv` | `MKENV-NO-TEST` | the copy handed out lacks `Test` (fixture identity, `baseEnv` identity, writeback counter, keys, stack) |
| `ErmineFixture.loadModules` writeback | `WRITEBACK-NO-TEST` | `s` lacks `Test` at `baseEnv := s` (the N-th writeback) |
| `Session.SourceFile.forModule` | `FORMODULE-NOTFOUND` | the answer is `NotFound` — names the caller through the stack, with `loadInSeries` and `loadedModules` |
| `Session.NotFound.contents` | `NOTFOUND-CONTENTS` | the `die` is about to happen |
| `Session.loadModules` | `LOADMODULES-IN-SERIES` / `-PARALLEL` | which branch, which modules, which of them have no source file |
| `SessionEnv.:=` / `+=` | `ENV-ASSIGN-TESTLOSS` / `ENV-PLUSEQ-TESTLOSS` | receiver had `Test`, argument does not |

**The probe is NOT in the delivered tree.**  It lived in `Session.scala`, `SessionState.scala`, a new
`session/Probe.scala` and the fixture; all of it was removed once the mechanism was pinned and the fix
verified, and the two full `core/test` runs below were made on the probe-free tree.  The delivered diff
is **test-side only** — no shipped-behaviour change, so the reviewer's tier does not grow (6.0.5).

## 3. The fix (6.0.3a) — at the source, and test-side

`scalacheck-binding/src/main/scala/TestInterfaceKey.scala`:

1. **Step (3) of `cold write keys, warm read matches…` no longer sets a system property.**  It selected
   the series loader schedule with `withProps("ermine.loadInSeries" -> "true", …)(load(dir))`; it now
   calls that schedule directly, `Session.loadModulesInSeries(List("KeyB"))`, through a new private
   `loadInSeries(dir)` that is `load(dir)` with the one line changed.  **The property still asserts
   exactly what it asserted** — that the other loader schedule reads the warm interfaces and does not
   invalidate the cache (`warmFlipped ?= (Interface, Interface)`); nothing is removed, skipped or
   weakened, and the assertion is now made against the code rather than against a flag that selects it.
2. **`withProps` gained a whitelist**, so the class of mistake cannot come back: it refuses any property
   that is not read once into a `val` at class-initialisation time (`ermine.rowTrace`,
   `ermine.rowTrace.draws` — the two the file legitimately flips), with the reason in the message.  It
   also forces `RowTrace`'s read-once `val`s before opening its window, closing the small residual
   hazard that a concurrent first touch of `RowTrace` inside the 0.4 ms `rowTrace` window would latch
   the flipped value for the rest of the JVM.

No change to `Session.scala`, `SessionTask.scala` or `SessionState.scala`.

**The latent inconsistency, recorded and NOT fixed here.**  `loadModulesInSeries` asks the loader for
every name it is given, while `loadModules` subtracts `s.loadedModules` first; the two schedules
disagree for any module that is in `loadedModules` with no source file.  CORRECTED BY THE REVIEW (R-1):
`Test` is not the only such module — `Builtin` is seeded sourceless by SHIPPED code
(`SessionState.scala:104`, the `loadedModules` default) and is equally lethal in series mode (the
reviewer measured 22 `'Test'` + 4 `'Builtin'` deaths under the flag).  So "nothing outside the tests
produces such a module" is false; the real reason this is not a live bug is that no non-test caller
passes a sourceless LOADED module in its list (`bin/ermine`, the REPL, `ei-diff.sh --batch`,
`corpus-run.sh` and `perf-bench.sh` name real files, and `Session.load` short-circuits on
`loadedFiles`).  It is still the reason a 16 ms property flip could kill a whole suite, and making the
two schedules agree (`for (m <- moduleNames if !s.loadedModules.contains(m))`) is a one-line change to
shipped loader code.  Its tier (review R-7): Tier 2 by GATE-POLICY's wording (shipped behaviour), plus
Tier 1's `ei-diff.sh --batch` sweep with `loadInSeries` on both sides and `g1-validate.sh` — not
"Tier 1" as first written.  **Filed as ticket E5 in `tracker/TICKET-stdlib-findings.md`.**

## 4. The temp-tree leak (6.0.4)

The brief's picture was **out of date on one point**, and I record what I found rather than what it said:

* `TestInterfaceConcreteRow` :232 (`ermine-ei-corpus`, the 3.5 MB one) and :78 (`ermine-row`)
  **already deleted their trees** — a `finally deleteTree(dir)` on the per-property `ermine-row`
  workspace, a reference-counted `releaseCorpus` on the shared corpus, plus a stale-tree sweep for
  anything older than an hour.  `/tmp` held no `ermine-ei-corpus*` or `ermine-row*` tree at any point.
* `TestInterfaceKey` :59 (`ermine-key`) and `TestInterfaceRoundTrip` :48 (`ermine-rt`) **did leak** —
  8 trees were in `/tmp` at the start, and my five pinning runs added 11 of each (30 trees, 160 KB+).

Fixes:

* One `ErmineFixture.deleteTree(path)` in `object ErmineFixture` (deepest-first, failure-tolerant), the
  single place a suite gets tree deletion; `TestInterfaceConcreteRow`'s private copy now delegates to it.
* `TestInterfaceKey` and `TestInterfaceRoundTrip` each wrap their property body in
  `try … finally ErmineFixture.deleteTree(dir)`.  Their workspaces are created **inside** the property,
  once per evaluation, so a `finally` is exactly right there whatever the worker count.
* **`TestInterfaceConcreteRow`'s shared corpus moved from a reference count to a shutdown hook.**  The
  count was initialised to 2, one per property, which assumes each property is evaluated exactly once —
  true only at ScalaCheck's default one worker.  At `-workers 4` (which I used for pinning runs 4 and 5)
  each `secure` property is evaluated once per worker, the count reached zero after the first two
  evaluations, and the tree was deleted under a reader still walking it:
  `java.nio.file.NoSuchFileException: /tmp/ermine-ei-corpus…/examples/Accumulate.ei`, in both those runs
  and in neither of the three default-worker runs.  A `Runtime.getRuntime.addShutdownHook` registered
  where the tree is created cannot race a reader at all, and also survives a property that dies before
  its `finally`.  STATED PLAINLY (review R-2, measured): the hook runs at JVM EXIT, so under
  `Test / fork := false` the corpus tree lives for the life of the sbt JVM — one 3.5 MB tree after one
  `core/test` in an interactive sbt session, 7.0 MB after two, 0 after `exit`.  `sbt -batch` (every gate
  script) exits per run, so the gates leave nothing; a long-lived interactive sbt accumulates one tree per
  run until it exits.  Accepted: it cannot race a reader, and the alternative (a per-property copy of the
  3.5 MB corpus) costs more than it saves.  (The probe's four `WITHPROPS-SET` records per `-workers 4` run are the independent
  confirmation that a `secure` property is evaluated once per worker.)

The pre-existing `/tmp/ermine-key*` and `/tmp/ermine-rt*` droppings were deleted (30 trees); nothing
else under `/tmp` was touched.

## 5. The run table — every run, in order

Machine: 12 cores; load average recorded per run.  Pinning recipe = the brief's
`core/testOnly *TestLower *TestNewPipeline *TestTolerantCheck *TestTolerantRead *TestStage1Pins
*TestEditorBuffers *TestInterface* *TestScopes *TestReplDifferential` (132 properties).
Every run `sbt -batch -J-Xmx3g`, ONE JVM at a time.

| # | what | probe | tree | result | wall | probe findings |
|---|---|---|---|---|---|---|
| D | `-Dermine.loadInSeries=true 'core/testOnly *TestLower'` | off | pre-fix | **Total 28, Errors 28, Passed 0**, every one `Death: Module not found: 'Test'` | 18.5 s | the deterministic victim half |
| 1 | pinning recipe | ON | pre-fix | 132/132 | 291 s | window 15.8 ms; 8,414 `loadModules`, 7,600 naming `Test`; no cross-thread hit |
| 2 | pinning recipe | ON | pre-fix | 132/132 | 211 s | window 28.2 ms; no cross-thread hit |
| 3 | pinning recipe | ON | pre-fix | 132/132 | 363 s | window 14.1 ms; no cross-thread hit |
| 4 | pinning recipe **`-- -workers 4`** | ON | pre-fix | **131/132, 1 error** — `NoSuchFileException .../ermine-ei-corpus…/examples/Accumulate.ei` | 457 s | 4 windows; the error is the corpus REFCOUNT (§4), not the flake under study |
| 5 | pinning recipe **`-- -workers 4`** | ON | pre-fix | **131/132, 1 error** — same `NoSuchFileException` | 593 s | 4 windows; same |
| v1 | pinning recipe | ON | **fixed** | 132/132 | 300 s | **0 `LOADMODULES-IN-SERIES`, 0 windows**; 0 `/tmp` trees left |
| v2 | pinning recipe | ON | fixed | 132/132 | 237 s | 0 in-series, 0 windows; 0 `/tmp` trees |
| v3 | pinning recipe | ON | fixed | 132/132 | 238 s | 0 in-series, 0 windows; 0 `/tmp` trees |
| F1 | **full `core/test`** | removed | fixed | **Passed: Total 943, Failed 0, Errors 0, Passed 943** | 1,533 s | 0 `/tmp/ermine-*`, 0 stray `.ei` |
| F2 | **full `core/test`** | removed | fixed | **Passed: Total 943, Failed 0, Errors 0, Passed 943** | 1,463 s | 0 `/tmp/ermine-*`, 0 stray `.ei` |

Notes on the table.
* Runs 4 and 5 are the only runs at a non-default ScalaCheck worker count; the brief permits raising it
  for pinning runs and this **declares it**.  It bought nothing (the window is bounded by
  `TestInterfaceKey`'s own execution, not by how many other threads exist) and it cost a false failure,
  so it is not a knob to reach for again — but it did expose the corpus refcount bug, which is now
  fixed, and it proved that a `secure` property is evaluated once per worker.
* The verification standard the brief sets for 6.0.3a is "must not fire again over at least as many runs
  as it took to fire the first time".  What fired, every pre-fix run without exception, is the **window**
  (`WITHPROPS-SET: ermine.loadInSeries=true` followed by `LOADMODULES-IN-SERIES` on a process-global
  flag).  Post-fix it fires **zero times in three runs**, versus **five times in five** before — the
  signal is 5/5 → 0/3, not a coin flip.
* **Does the failure move?**  The mechanism says it must: the victim is whichever property is inside
  `Session.loadModules` at that instant, and 7,600 of 8,414 calls in a pinning run name `Test`.  R-1 saw
  `TestLower`; the deterministic run D shows `TestLower` is only a victim, never a cause.

## 6. Gates (6.0.5) — Tier 0, plus the item's own two full runs

Run on the delivered tree (probe removed), one JVM at a time, load average 1.1-3.7.

| gate | expected | got |
|---|---|---|
| `sbt core/compile core/copyResources` | success | **success** |
| `sbt 'core/testOnly *TestLoopTrace'` | 720/720 | **720 solves, 720 segments, 720 agree**; `#summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls still disagree (46/720 at id-base +1, 58/720 at `--flags=nongen`).  sbt line: `Passed: Total 3, Failed 0, Errors 0, Passed 3` (three properties over those 720 segments) |
| `tracker/tools/corpus-run.sh --batch` | 85 / 69 / 0 over 154 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** |
| `tracker/tools/repl-smoke.sh` | 7/7 | **8/8 groups PASS, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5).  The tracker's "7/7" predates the `ffi-tolerant` group; nothing is missing or failing |
| `tracker/tools/lsp-smoke.sh` | 185 | **PASS lsp (185 checks)** |
| **full `core/test` × 2** | 943 + nothing new | **943/943 both**, 0 failed, 0 errors, exit 0 (1,533 s and 1,463 s) |
| stray `.ei` under `core/examples` | 0 | **0** after every run; `tracker/g1-baseline` untouched |
| `/tmp/ermine-*` after a full run | none | **none**, after each of the two full runs |

Tier 1 was **not** run and is not owed: nothing in the diff touches the solver, the row trace,
`Type.scala`'s constraint construction, or executable Lean.  The diff is **test-side only** — see §2 —
so this is not a Tier-2 adoption either; the two full runs are the item's own acceptance criterion, not
GATE-POLICY's Tier 2, and the reviewer runs the third.

**One loose end, recorded rather than buried.**  During the gate window a single
`/tmp/ermine-key<random>/` containing only `KeyA.e` and `KeyB.e` (no `.ei`) appeared at 21:05:24, when no
ScalaCheck JVM was running — `TestInterfaceKey.workspace()` is the only thing in the tree that creates
that name, and I could not attribute it.  It was deleted; **neither full `core/test` run on the fixed
tree left any `/tmp/ermine-*` tree**, which is the acceptance check, and the pinning verification runs
v1-v3 left none either.  If a reviewer sees one appear, it is worth a second look.

## 7. Diff summary

Four files, all test sources under `scalacheck-binding/src/main/scala/` (which `build.sbt` folds into
`core/Test`).  **No shipped (main) code changed.**

| file | change |
|---|---|
| `TestInterfaceKey.scala` | THE FIX: step (3) calls `Session.loadModulesInSeries` through a new private `loadInSeries(dir)` instead of setting `ermine.loadInSeries` process-globally; `withProps` gained a read-once whitelist that refuses any other property, and forces `RowTrace`'s `val`s before its window; the property body wrapped in `try … finally ErmineFixture.deleteTree(dir)`.  Every assertion is unchanged |
| `TestErmine.scala` | added `ErmineFixture.deleteTree(path)`, the one tree-deleter |
| `TestInterfaceRoundTrip.scala` | property body wrapped in `try … finally ErmineFixture.deleteTree(dir)` |
| `TestInterfaceConcreteRow.scala` | shared corpus deleted from a shutdown hook instead of a 2-initialised reference count (which a non-default worker count breaks); its private `deleteTree` delegates to `ErmineFixture.deleteTree` |

Removed before delivery: `core/.../session/Probe.scala`, and every probe hunk in `Session.scala`,
`SessionState.scala` and `ErmineFixture` (`git checkout` on the two main files — they now match HEAD).

## 8. What the roadmap paragraph should become

The item's "THE REVIEW'S MECHANISM IS UNVERIFIED" paragraph can be replaced by §1 above.  In one line:
**`TestInterfaceKey` set `ermine.loadInSeries=true` with `System.setProperty` for ~16 ms mid-run;
`Session.loadModules` re-reads that flag on every call; the series loader does not subtract
`loadedModules`; and the fixtures' synthetic `Test` module has no source file.**  R-1's six lock-free
suites are the victims, not the cause.  The follow-up ticket worth opening is §3's last paragraph: make
`loadModulesInSeries` subtract `s.loadedModules` so the two loader schedules agree (shipped code,
Tier 1).
