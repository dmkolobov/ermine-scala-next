# Review: LSP Stage 3, item 6.0 — `core/test` determinism (the `loadInSeries` flip) and the temp-tree leak

Independent reviewer, 2026-09-09. Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`,
HEAD `c2ed8bb` (= `257f032` + the review brief commit) plus the four UNCOMMITTED test sources and the implementer's
report `tracker/loopmodel/LSP3-6.0-HYGIENE.md`. Brief `tracker/loopmodel/briefs/brief-LSP3-6.0-review.md`.
Scratch `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.0/`
(every log named below is there). ONE JVM at a time; no commits; `tracker/lean/` and `tracker/LSP-ROADMAP.md`
untouched; `/tmp/ermine-*` count and `.ei` count recorded before and after every run.

**TIER: 0.** `git status` and `git diff --stat` show four modified files, all under
`scalacheck-binding/src/main/scala/` (which `build.sbt:90` folds into `core/Test`), and one new tracker file.
`git status --porcelain -- core/src/main` is empty, `git diff --stat -- core/src/main` is empty, and there is no
`session/Probe.scala` in the tree: the delivered diff is TEST-SIDE ONLY as claimed, so the tier does not grow.

**VERDICT: FIX-THEN-ADVANCE.** The mechanism is real, I reproduced it, and I could not find a second one. The fix
is correct, exercises the same schedule, weakens nothing, and every gate is green on my numbers. Two paragraphs of
the report are wrong or missing in ways that matter for the follow-up ticket the orchestrator will open (R-1, R-2);
both are report edits, not code edits. No code change is required to advance.

## Findings

| id | severity | status | one line |
|---|---|---|---|
| R-1 | medium | CONFIRMED (mechanism) / REFUTED (its stated reach) | `Builtin` is a SECOND sourceless module, seeded by SHIPPED code, and is equally lethal in series mode — I measured 4 deaths naming `'Builtin'`; the report's "nothing outside the tests produces such a module" is false |
| R-2 | medium | CONFIRMED (measured) | The shared corpus now dies with the JVM, not with the test run: in one sbt JVM I measured 3.5 MB alive after one test run and 7.0 MB after two, 0 after exit. Acceptable, NOT stated |
| R-3 | nit | CONFIRMED | Step (3) no longer covers the `-Dermine.loadInSeries` property → branch wiring, only the series loader itself |
| R-4 | nit | CONFIRMED | The whitelist is `private` to one file; nothing stops the next suite from calling `System.setProperty` directly |
| R-5 | nit | CONFIRMED | §1.1c's arithmetic is right, its "one run in two" is P(≥1)=35 %, and the rate comes from the load-dense pinning subset, so it is an upper bound for a full run |
| R-6 | nit | CONFIRMED | The stale-tree sweep still covers only `ermine-ei-corpus*`; a `kill -9` still leaks `ermine-key`/`ermine-rt`/`ermine-row` |
| R-7 | nit | PLAUSIBLE | The follow-up ticket's tier: by GATE-POLICY's own wording a loader change is Tier 2 (shipped behaviour) and needs Tier 1's interface sweep + `g1-validate.sh`, not "Tier 1" |

**R-1 — the mechanism is confirmed, its stated reach is not.** Re-derived at HEAD, every link holds:
`Session.scala:664` reads `java.lang.Boolean.getBoolean("ermine.loadInSeries")` INSIDE `loadModules`, i.e. on every
call; the series branch is `loadModulesInSeries` (`:704`) = `for (m <- moduleNames) load(SourceFile.forModule(m),
Some(m))` with no `&~ s.loadedModules`, against the parallel branch's `deps(moduleNames.toSet &~ loaded)` (`:670-672`);
`forModule` (`:382`) is `s.loadFile(module) | NotFound(module)`; `load` (`:845`) misses in `loadedFiles` (the
fixture's `Test` is a `Literal`, `NotFound` is a different case class, so no short-circuit even inside a property
that has already run `loadStatements`), calls `dep`, which cannot hit `cached` (`NotFound.lastModified = None`) and
so evaluates `file.contents` = `die("Module not found: '" + module + "'")` (`:342`). `ErmineFixture` seeds
`"Test" -> CheckMethod.Interface` (`TestErmine.scala:54`) and `imps` names `Test` (`:88`), and there is no `Test.e`
anywhere (`find / -name Test.e` empty). Confirmed, and I reproduced the victim half deterministically: **28 of 28
errors, every one `Module not found: 'Test'`** (log `rD-testlower-series.log`).
WHAT THE REPORT MISSES: `Test` is not the only sourceless module in a session. `SessionState.scala:104` gives
EVERY `SessionEnv` the default `loadedModules = Map("Builtin" -> CheckMethod.Interface)`, and there is no
`Builtin.e` anywhere either (`find / -name Builtin.e` empty — it is installed by `Lib`). So in series mode a
property dies at whichever sourceless name its import map reaches first, and which one that is depends on map
iteration order. I measured it: `-Dermine.loadInSeries=true 'core/testOnly *TestScopes *TestNewPipeline
*TestTolerantCheck'` gives 26 deaths, **22 `'Test'` and 4 `'Builtin'`** (`rD2-series-others.log`). Two consequences.
(i) The victim population is larger than "the 7,600 of 8,414 calls that name `Test`" — calls that name `Builtin`
without `Test` are lethal too, so §1.1c's rate is if anything understated. (ii) §3's reason for the latent
inconsistency not being a live bug — "nothing outside the tests produces such a module" — is FALSE: shipped code
produces exactly such a module in every session ever created. I still agree with the CONCLUSION (see R-7), but for
a different and more fragile reason: no non-test caller ever passes a sourceless *loaded* module in the list
(`Console.scala:782`/`:691` pass user module names, `:373` `:slowerload` passes `loadedFiles.values` — which by
construction all have files — `Resident.scala:230` and `readModule`/`load` subtract `loadedModules` first, and
`G1Compare`/`G1Groups` pass `List("Prelude","Layout")`). `:load Builtin` under `-Dermine.loadInSeries=true` would
die today; nothing does that. The report's §1/§3 should be corrected to name `Builtin` before the paragraph is
copied into `LSP-ROADMAP.md`.

**R-2 — the shutdown hook is safe, and it is a different lifetime.** The refcount really was broken (initialised to
2, one per property, while a `secure` property is evaluated once per WORKER — `Prop.?=` yields `proved`, which stops
ScalaCheck's loop after the first success, so "once per worker" is exactly right), and a hook cannot race a reader.
But `Test / fork := false` (`build.sbt:94`) means the hook is the SBT JVM's: it runs at sbt exit, not at test end.
Under `sbt -batch … core/test` — the gate form, and the form every run in both reports used — that is the same
instant, and I verified 0 `/tmp/ermine-*` after each of my runs. Under an interactive `sbt` shell or `sbt --client`,
the 3.5 MB corpus stays for the life of the session. I MEASURED it: `*TestInterfaceConcreteRow` run twice in one
sbt JVM, with `/tmp` counted between the two, leaves **one 3.5 MB tree alive after the first run and two (7.0 MB,
different names) after the second** — sbt gives each test run a fresh test classloader, so the `lazy val`
re-initialises and stages again — and **0 once the JVM exits**, both hooks having run (`r7-session-lifetime.log`;
both runs 3/3, which is also independent evidence that the refcount race is gone). That is acceptable — R-5's
complaint was about trees surviving the JVM, and none does — but it is a real change of lifetime versus the
refcount it replaced (which deleted at test end, at the default worker count), and §4 does not say it. One sentence
in §4 fixes it.

**R-3 — nothing is weakened, but one thing is no longer covered.** Property counts are identical at HEAD and in the
worktree (`TestInterfaceKey` 2, `TestInterfaceRoundTrip` 1, `TestInterfaceConcreteRow` 3, `TestErmine` 33); no
property is skipped, no generator size or `minSuccessful` touched. The step-(3) assertion block is BYTE-IDENTICAL
to HEAD's (I diffed both assertion lists), and `loadInSeries(dir)` is `load(dir)` with exactly one line changed, so
it runs the same five-load sequence under the same `literalLock`, the same `depCache.clear()`, the same
`useInterface = Some(true)` session. It really is the series schedule: it calls `loadModulesInSeries` itself, which
is precisely what `loadModules` delegates to under the flag (`:664-666`), and the return value is discarded on both
sides. No nested `loadModules` call exists inside that path (`Lib.preamble` does not load modules; the only
`loadModules` callers in `core/src/main` are `Console`, `Resident`, `G1*`, `eval` and `reloadChangedModules`), so
setting the flag process-wide bought the property nothing it has now lost — except one thing: the property used to
prove that `-Dermine.loadInSeries=true` SELECTS that branch. Delete the `getBoolean` at `:664` and no test now
fails. That is a fair trade (the alternative is what caused the flake), but it should be a comment, and a one-line
`Boolean.getBoolean` guard is not a substitute.

**R-4 — the guard is file-local.** `flippable` + the `sys.error` fails closed and is exactly right for
`TestInterfaceKey` (a future edit that flips `ermine.typeCheck` or `ermine.loadInSeries` there fails loudly, with
the reason). It cannot stop a NEW suite from calling `System.setProperty` itself — `withProps` is `private` to this
file. Today `TestInterfaceKey` is the only test that sets a property at all (`grep -rn setProperty` over all Scala
sources: this file, plus `Console.unfixSbtTerminalProperty` for `jline.terminal`, which `core/test` never reaches).
The rule belongs where the next suite author reads it — `ErmineFixture`'s doc comment, or GATE-POLICY's standing
rules — as well as in this file.

**R-5 — the arithmetic.** 8,414 / 277.8 s = 30.29 /s and 7,600 / 277.8 = 27.36 /s (report: 30.3, 27.4 ✓);
27.36 × 0.0158 s = 0.432 expected deaths per run (report: 0.43 ✓). The model is the right one — the flag is read at
the very top of `loadModules`, so what matters is arrivals into that method during the window. Two caveats that do
not change the conclusion: 0.43 expected deaths is P(≥1) = 1 − e^−0.43 = **35 %**, not "roughly one time in two";
and the rate was measured on the nine module-loading suites, which are far denser in `loadModules` calls than the
943-property suite as a whole, so 0.43 is an upper bound for a full run. Order of magnitude and direction match
F4's one-red-in-two observation; the argument stands.

**R-6 — residual leak class.** `sweepStaleCorpusTrees` (`TestInterfaceConcreteRow.scala:206`) globs
`ermine-ei-corpus*` only. The new `finally` blocks cover normal and exceptional exits of the `ermine-key` /
`ermine-rt` / `ermine-row` properties, but a `kill -9` or a cancelled sbt still leaves those (kilobyte) trees, with
nothing to sweep them. Widening the glob to `ermine-*` (same hour cutoff) is a one-character-class change. Optional.

**R-7 — the follow-up ticket.** I agree it is not a live bug today (R-1 enumerates the callers) and that
`for (m <- moduleNames if !s.loadedModules.contains(m))` is the change. I do NOT agree with "Tier 1" as stated:
GATE-POLICY's Tier 1 trigger list is the solver, the row trace, `Type.scala`'s constraint construction and
executable Lean — not the loader — while Tier 2's trigger is "shipped behaviour changes", which this is. And it
must carry Tier 1's `ei-diff.sh --batch` interface sweep *with `-Dermine.loadInSeries=true` on both sides* plus
`g1-validate.sh`, because the series loader's call sequence is what draws `Supply` ids for published existentials
(`Session.scala:152-158`): changing which modules it asks for can change `.ei` bytes and the G1 baseline. Write the
ticket as "Tier 2, and Tier 1's sweep + g1-validate".

### The second-mechanism audit (brief §1, last question)

Every process-global flag, where it is read, and whether any test flips it:

| property | read at | when | flipped by a test? |
|---|---|---|---|
| `ermine.loadInSeries` | `Session.scala:664` | **per call** | pre-fix YES (the mechanism); now no |
| `ermine.typeCheck` | `SessionState.scala:119` | **per `SessionEnv` construction** | no (whitelist refuses) |
| `ermine.useInterface` | `SessionState.scala:121` | **per `SessionEnv` construction** | no (whitelist refuses) |
| `ermine.foreign.tolerant` | `SessionState.scala:130` | **per `SessionEnv` construction** | no (whitelist refuses) |
| `ermine.rowTrace` | `RowTrace.scala:197` (`private val path`) | once, object init | YES, safely |
| `ermine.rowTrace.draws` | `RowTrace.scala:219` (`val drawRecords`) | once, object init | YES, safely |
| `ermine.genRules`, `disjunction`, `labelCheck`, `resGuard`, `labelCheckEarly`, `splitKey`, `splitRow`, `resRow`, `emptyRow`, `rowSound*`, `solveBudget`, `dequeuePolicy`, `topNormalise`, `tautoDelete` | `Constraints.scala:928-1552` | once, object init (`GenRules`) | no |
| `ermine.lsp.log` | `lsp/Main.scala:14` | once at LSP start | no (no test uses the LSP main) |
| `jline.terminal` | `Console.scala:288-292` — the only `setProperty` in shipped code | REPL `main` only | not reached by `core/test` |
| `java.io.tmpdir`, `db.dev.ds.url` | `TestInterfaceConcreteRow:209`, `Backends.scala:43` | per call | no |

The three `SessionState` flags are the interesting near-miss: they are `val`s of a CLASS, not of an object, so they
are re-read every time a `SessionEnv` is constructed — a flip of `ermine.foreign.tolerant` inside a `withProps`
window would reach every session built in it. Nothing flips them, and the new whitelist refuses them by
construction; the file's own `notInKey` comment already knew this. **Is there a second mechanism for the same
message?** No. On the parallel path every caller subtracts `loadedModules` before asking the loader —
`deps` (`:542-544`), `depsPrime` (`:531`, `-- mods`), `load`'s import loop (`:854`), `readModule` (`:795`),
`Resident.scala:229` — so a `NotFound` for a module that IS loaded can only come from `loadModulesInSeries`. The
only code that removes a `loadedModules` key is `Resident.scala:222` (no test constructs a `Resident`; no test
source contains a `module Test` buffer other than the fixture's own `Literal` wrapper) and
`reloadChangedModules` (`:754`, no test calls it) — matching the implementer's probe, which recorded zero
`TESTLOSS`/`MKENV-NO-TEST`/`WRITEBACK-NO-TEST` events over five runs. `SessionEnv.+=` is a union (`:148`).
`ErmineFixture.mkEnv`/writeback run under `envLock`, and `baseEnv` is a `lazy val` (initialised under the JVM's own
lock, so no torn read).

## Gates — re-run once, mine beside the implementer's

Machine: 12 cores, load average 0.7-3.7 at the starts, no other JVM at any point. `/tmp/ermine-*` before I started:
**0**. `find core/examples tracker/lsp-tests -name '*.ei'` before I started: **0** (and 0 `.ei` anywhere outside
`tracker/g1-*` and `*/target/*`).

| gate | expected | implementer | **mine** | log |
|---|---|---|---|---|
| `sbt core/compile core/copyResources` | success | success | **success**, 4.7 s | `g0-compile.log` |
| deterministic repro `-Dermine.loadInSeries=true 'core/testOnly *TestLower'` | 28 errors | Total 28, Errors 28, 18.5 s | **Total 28, Failed 0, Errors 28, Passed 0**, all 28 `Module not found: 'Test'`, 17.4 s | `rD-testlower-series.log` |
| (mine, extra) same flag, `*TestScopes *TestNewPipeline *TestTolerantCheck` | — | — | **Total 46, Failed 1, Errors 25, Passed 20**; 22 `'Test'` + 4 `'Builtin'` (R-1) | `rD2-series-others.log` |
| `sbt 'core/testOnly *TestLoopTrace'` | 720/720 | 720/720/720, `rejected=36 fuel=0`, controls 46 & 58 | **720 solves, 720 segments, 720 agree**; `#summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls 46/720 (+1) and 58/720 (`nongen`); `Passed: Total 3`, 15.1 s | `g1-looptrace.log` |
| `tracker/tools/corpus-run.sh --batch` | 85 / 69 / 0 over 154 | 85 / 69 / 0 / 154 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total**, 42.7 s | `g2-corpus.log` |
| `tracker/tools/repl-smoke.sh` | tracker says 7/7 | 8/8 groups, 66 checks | **8/8 groups PASS, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5), 106.8 s — the implementer is right, **the tracker's "7/7" is stale** | `g3-repl.log` |
| `tracker/tools/lsp-smoke.sh` | 185 | PASS 185 | **PASS lsp (185 checks)**, 17.0 s | `g4-lsp.log` |
| pinning recipe, default workers | 132/132 | 132/132 (300 / 237 / 238 s) | **Passed: Total 132, Failed 0, Errors 0, Passed 132**, 319 s; 0 `/tmp/ermine-*`, 0 stray `.ei` | `g5-pinning.log` |
| **full `sbt -batch -J-Xmx3g core/test`, alone on the tree (run #3)** | 943/943 | 943/943 twice (1,533 s, 1,463 s) | **`Passed: Total 943, Failed 0, Errors 0, Passed 943`, exit 0**, 1,673.5 s wall (sbt 27:50); no `[error]` line, no `Module not found`, 0 `/tmp/ermine-*` and 0 `.ei` after | `g6-full-coretest.log` |
| (mine, extra, R-2) `*TestInterfaceConcreteRow` TWICE in ONE sbt JVM, `/tmp` counted between | — | — | 3/3 and 3/3; **1 tree (3.5 MB) alive after the first run, 2 trees (7.0 MB) after the second, 0 after the JVM exits** | `r7-session-lifetime.log` |

**The third full run is 943/943 with exit 0** — the headline the brief asked for is that there is no headline: the
item's acceptance criterion holds on a third independent run, at 1,673 s against the implementer's 1,533 s and
1,463 s (my machine was at load 1.5-3.7 from nothing but this run; the spread is drift, not signal).

After every run: `ls -d /tmp/ermine-*` **0**, `find core/examples tracker/lsp-tests -name '*.ei'` **0**;
`tracker/g1-baseline` untouched; no `.ei` created anywhere that I did not delete (the corpus script deletes its own).
Tier 1 was not run and is not owed (no solver, row-trace, `Type.scala` or Lean change). One deviation to declare:
the third full run exceeds this session's 10-minute foreground tool limit, so it was started detached and waited on
with nothing else running — one JVM on the machine throughout, verified by `ps` before and during.

## On the report

`LSP3-6.0-HYGIENE.md` is accurate everywhere I could check it except R-1's two sentences and R-2's omission:
the mechanism (§1), the pre/post code read, the leak inventory at HEAD (`ermine-key` at `TestInterfaceKey:59` and
`ermine-rt` at `TestInterfaceRoundTrip:48` had no deleter; `ermine-row` had `try prop1(dir) finally deleteTree(dir)`
at `:103` and the corpus had the refcount — verified against `git show HEAD:`), the probe's removal (no
`Probe.scala`, `Session.scala`/`SessionState.scala` byte-identical to HEAD), the arithmetic (§1.1c, R-5), the
worker-count declaration, and every gate number I re-ran. §6's "the tracker's 7/7 predates the `ffi-tolerant` group"
is correct. The loose end it records — a stray `/tmp/ermine-key*` with no `.ei` appearing while no ScalaCheck JVM
ran — did not recur for me: `ls -d /tmp/ermine-*` was 0 before I started and 0 after every one of my ten JVM runs
(the only trees I ever saw were the two staged INSIDE the live JVM of the R-2 experiment, and they went at its exit).

## Verdict

**FIX-THEN-ADVANCE** — advance on the code as delivered; before the orchestrator copies §1/§3 into
`tracker/LSP-ROADMAP.md`, apply two REPORT edits:

1. **R-1**: name `Builtin` (`SessionState.scala:104`) as the second sourceless module — with the measurement
   22 `'Test'` + 4 `'Builtin'` — and replace §3's "nothing outside the tests produces such a module" with "no
   non-test caller passes a sourceless *loaded* module in its list", which is the real reason the inconsistency is
   not live.
2. **R-2**: state in §4 that the corpus tree now dies with the sbt JVM, not with the test run, and that an
   interactive sbt session therefore keeps it (one tree per `core/test`) until the session ends.

Optional, none of them blocking: R-3's comment, R-4's rule moved somewhere a new suite author sees it, R-6's sweep
glob. R-7 is for the follow-up ticket's wording: Tier 2, plus Tier 1's `ei-diff.sh --batch` sweep with
`-Dermine.loadInSeries=true` on both sides and `g1-validate.sh`.
