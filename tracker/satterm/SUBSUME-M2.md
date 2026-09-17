# SUBSUME-M2 — merge `scala3-migration` into `json-encode`, and lift the B1 gate

M2 of the closing sequence of the `subsume-termination` programme
(`tracker/satterm/SUBSUME-PLAN.md` "Closing sequence" item 3; brief
`tracker/satterm/briefs/brief-M2-json-encode.md`).

Worktree `~/research/ermine/ermine-scala-wt-json`, branch `json-encode`.
Every log path below is under `<m>` = `/home/dmitry/research/ermine/scratch-subsume/m2/`.

| | |
|---|---|
| receiving branch before | `json-encode` **2afeb426** ("JSON Stage 2/3 plan: the closing handoff entry") |
| merged in | `scala3-migration` **d278c900** ("Merge branch 'subsume-termination' into subsume-s2") — S0 + S1a + S1b + S2 |
| merge base | **478a369c** (the programme's base; `json-encode`'s last common ancestor) |
| **merge commit** | **9ec3406d** — `Merge branch 'scala3-migration' into json-encode` + `resolutions in tracker/satterm/SUBSUME-M2.md` |
| uncommitted after it | the B1 gate lift, 3 files (§3) — for the orchestrator to commit after review |

Nothing was pushed. `tracker/repl-classpath.txt` was regenerated from this worktree's
`target/ermine-classpath` before the smokes and restored with `git checkout --` afterwards; it is
not a change of this stage.

---

## 1. The merge, and every conflict

**`git merge scala3-migration` produced NO textual conflict** (`<m>/merge.log`, exit 0, "Merge made
by the 'ort' strategy", 38 files, +8248/−26). That is the honest headline and it is not the same as
"nothing needed resolving": the three files the brief predicted had diverged, and two of them are
worth stating in full because a clean auto-merge on adjacent hunks is exactly where a merge lies to
you. The third is a semantic conflict that git could not see, and §3 resolves it.

### 1.1 `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala` — both sides kept, verified

| | |
|---|---|
| **json-encode's side** (+5/−5, "the five-line change") | five `DataStatement` patterns gain the JSON named-fields **selector field** `sels`: `:801` `case (b@DataStatement(l, v, kindArgs, typeArgs, cons, _), rk)`; `:831-832` `case DataStatement(l, v, kindArgs, _, cons, sels) => DataStatement(l, v, kindArgs, typeArgs, cons.map{…}, sels)` (the only site that *carries the value through* rather than discarding it); `:1877` and `:1886` two more `_` widenings. `DataStatement` grew a field on `json-encode`, so these are compile-forced, not behavioural. |
| **scala3-migration's side** (+157/−2) | S0's diagnosis instrumentation, all behind `-Dermine.subsumeTrace` (default OFF): `:367` `SubsumeTrace.cse(hm)(fskvs(hm.types -- mask).filter(ss(_)))`, `:618` `val stid = SubsumeTrace.enter(hm, sig)`, `:653` `SubsumeTrace.atEscape(stid, sks, sts, hm)`, `:654-655` the two halves of the escape check wrapped in `SubsumeTrace.phaseFskvs` / `phaseKindVars`, and `object SubsumeTrace` at `:2241`. |
| **resolution** | BOTH, unedited. The hunks are 150+ lines apart and `ort` merged them; the result was then *verified* rather than trusted: `git diff scala3-migration HEAD -- Subst.scala` is exactly the five `sels` lines and nothing else, and `git diff 2afeb426 HEAD -- Subst.scala` is exactly `+157/−2`. Both checks are in this report's audit trail; the compile gate (§4) is the third. |

### 1.2 `tracker/tools/lsp-client.py` — both blocks kept

| | |
|---|---|
| **json-encode's side** (+22; `:442` in the merged file) | the `ermine/schema` block (JSON API Stage 1b): **4 checks** — an enum exported from the resident session, a refusal for an uninstantiated parameterised type, a tagged-union instantiation, and the no-module error object. |
| **scala3-migration's side** (+24; `:197` in the merged file) | S2's `RowUnsat.e` block: **5 checks** — exactly one diagnostic, severity 1, the row-label message, a range inside the file, and arrival within 20 s of the `didOpen`. |
| **resolution** | BOTH; different functions, 200 lines apart. Confirmed by count at the gate: `lsp-smoke.sh` **577 → 582 checks** = json-encode's 577 plus S2's five (§4). |

### 1.3 `scalacheck-binding/src/main/scala/TestDateAndScan.scala` — the one SEMANTIC conflict

This is the file where the auto-merge is wrong, and where git had no way to know it.

| | |
|---|---|
| **json-encode's side** (+12 at `:185-196`, commit dd9e0316) | an eleven-line `QUARANTINED 2026-09-16` comment and the line `if (sys.props.contains("ermine.test.dateDiffReject"))`, immediately above the B1 refutation property, so that the property is registered only when that flag is set. |
| **scala3-migration's side** | S2 rewrote the same property's body `no(typeChecks(…))` → `rejects(typeChecks(…))` and added 81 lines below it: the `(B1-bound)` deadline pin, plus imports. |
| **what `ort` produced** | the union: json-encode's `if (…)` guard **still standing above** S2's `rejects(…)` body — a property that is now fast and still gated off. Textually clean, semantically the opposite of what the closing sequence is for. |
| **resolution** | The merge commit keeps the union verbatim (so the merge is exactly "both sides", auditable), and the **gate lift of §3 is the resolution**, left uncommitted for the orchestrator as the brief requires. `git diff scala3-migration HEAD -- TestDateAndScan.scala` on the merge commit is exactly json-encode's 12 lines; after the gate lift, the working tree differs from `scala3-migration` by 12 lines again — the replacement comment, and no `if`. |

### 1.4 Tracker documents

No conflict: every incoming `tracker/satterm/**` file, `tracker/PROMPT-subsume-termination.md`,
`tracker/lean/**` (`Rowpartition/SubsumeEscape.lean`, `Loop/{RejectTerm,EnvBound}.lean`, the README
rows), `tracker/lsp-tests/RowUnsat.e` and the `tracker/TICKET-perf-type-inference.md` addition are
NEW on `json-encode` and were added as-is. `tracker/GATE-POLICY.md` and
`tracker/TICKET-editor-and-solver-followups.md` were changed on `json-encode` only (dd9e0316) and
not by the programme, so they merged untouched — and both are edited by §3 for the same reason
`TestDateAndScan.scala` is.

Two documents now carry statements that the programme refuted. They are NOT edited here, because
they are the programme's own historical record and the brief does not ask for it:
`tracker/PROMPT-subsume-termination.md:136` ("On `json-encode` the property is gated behind
`-Dermine.test.dateDiffReject=true`") is Part B's statement of the premise, and
`tracker/satterm/SUBSUME-STAGE0.md:721` records the same thing as the state S0 found. Both are
superseded by this stage; SUBSUME-PLAN.md's closing sequence is the place that says so.

---

## 2. What the merge brings to `json-encode`

For the reviewer, in one place: `ErmineFixture.rejects` / `bounded` / `outcomeOf` / `loadNamed`
(`TestErmine.scala`), 20 converted `no(` sites in 6 files, the new `TestRowRefusals` suite (16
generated unsatisfiable row programs + 16 twins), the `(B1-bound)` pin, `tracker/lsp-tests/RowUnsat.e`
and its five smoke checks, S0's `-Dermine.subsumeTrace` instrumentation in `Subst.scala` (default
OFF), three new Lean modules with their audits, and the programme's ten tracker documents.

**One live `no(` site on the json-encode side that S2 never saw** — found here, and CONVERTED as
follow-up F-1 on the orchestrator's instruction (§7): `scalacheck-binding/src/main/scala/TestNamedFields.scala:393`,
`no(typeChecks(src, "nfsecret", imps)) && typeChecks(…) && sessionProof{…}` in *"an existential field
gets no selector, a sibling still does"*. It is a FIXED program (no generator), so it is exactly the
shape `rejects` exists for, and because `Result.&&` maps `Proof && True` to `True` the single `no`
conjunct drags the whole property down to *passed* — which asks ScalaCheck for 100 evaluations of a
three-load property. The conversion is a one-line diff and it is now in the tree (§7).

---

## 3. The gate lift (UNCOMMITTED)

The brief: with S2's `rejects` the refutation runs once, so the `-Dermine.test.dateDiffReject`
quarantine has no reason to exist. Three files, `+51/−22` in total (`git diff --stat`).

| file | change |
|---|---|
| `scalacheck-binding/src/main/scala/TestDateAndScan.scala` | **−12/+12**: the `QUARANTINED` comment and the `if (sys.props.contains("ermine.test.dateDiffReject"))` line are gone; in their place an `UNQUARANTINED 2026-09-17` comment that says what the programme established (refused in 0.06–0.09 s at seventeen `Supply` id bases, the escape check returns on all 492,200 traced calls, `runV_steps` proves the walk total, the hundred evaluations were `no`'s doing) and points at `SUBSUME-STAGE0.md` §1.3/§1.6/§1.8, `SubsumeEscape.lean` and `SUBSUME-STAGE2.md` §1.1. The property body is `rejects(typeChecks(…))` — confirmed after the merge, and confirmed green at the gate as `OK, proved property`. |
| `tracker/GATE-POLICY.md` | the nine-line quarantine bullet under "Quarantines" is REMOVED and replaced by a seven-line `LIFTED 2026-09-17` paragraph outside the bullet list, so that a reader who remembers the entry learns what happened to it rather than finding a silent deletion. The other four quarantines (disjunction, TestInterfaceRoundTrip, TestLegend, TestTolerantCheck E11a) are untouched. |
| `tracker/TICKET-editor-and-solver-followups.md` | item 12's heading gains `— CLOSED 2026-09-17: IT TERMINATES; the test harness did not`, and a closing section is appended: the check returns (S0's measurement), it cannot fail to return (S1a/S1b's theorems), what actually took twenty minutes (`no` → 100 evaluations, fixed by `rejects`), the editor hazard is now a 58 ms gate, and **what remains**: `:648` is still an unmemoised whole-environment walk costing 23 % of a `bin/ermine` boot and 24.7 % of a suite run — a PERFORMANCE item, already filed in `tracker/TICKET-perf-type-inference.md`, and no reason to gate a test. |

**The B1 property runs unconditionally again**, and on this tree, with no flag:

```
[info] + Date, dateDiff and Layout.Scan (F3).a dateDiff combine over a relation WITHOUT the dates
       is now REJECTED (B1): OK, proved property.
```

---

## 4. Gates on the merged tree

All from the worktree root with `PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=4"`. **None of these figures is tracker-grade**,
and the contention is stated exactly rather than waved at: the main checkout's M1 full `core/test` ran
until **20:20:23** (`scratch-subsume/orch/m1-scala3-full-coretest.log`, 1,124 s), so it overlapped the
compile, the B1 suite, the corpus batch, repl-smoke, `TestRowRefusals` and `TestLoopTrace`, which also
overlapped each other (the gate policy's default-parallel rule). It did **not** overlap either full
`core/test` of §4.1 (started 20:23 and 20:56) or the lsp / check-corpus gates. Where it matters — the
B1 suite — the row says so.

| gate | result | wall | log |
|---|---|---|---|
| `sbt core/compile core/copyResources core/Test/compile` | **exit 0**, 0 errors, 8 warnings (pre-existing `Stream`/exhaustivity deprecations) | 38 s | `<m>/compile.log` |
| the B1 suite ALONE at the default `minSuccessfulTests`, `timeout 600` | **13/13 green**, `Passed: Total 13, Failed 0, Errors 0`; both B1 properties and `(B1-bound)` read `OK, proved property` | **519 s**, inside the 10-min deadline. S2 measured 181–195 s on a quieter tree; this run shared the machine with the main checkout's full `core/test`, my corpus batch and repl-smoke, so 519 s is an upper bound and not a regression figure — the same suite's 13 properties appear inside the full run of §4.1, which takes 15–20 minutes for 1,199 | `<m>/gate-b1.log` |
| `sbt 'core/testOnly com.clarifi.reporting.TestRowRefusals'` | **1 property, 48 assertions, green**: *"every unsatisfiable row program is refused, and its twin checks, in bounded time: OK, proved property"* (16 generated programs + 16 twins, 32 loads) | 95 s | `<m>/gate-rowrefusals.log` |
| `sbt -Dermine.looptrace=…/ermine-scala-wt-json-wrappers/tracker/lean/.lake/build/bin/looptrace 'core/testOnly *TestLoopTrace'` | **3/3 properties**; `720 solves; 720 segments; 720 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls detect 46/720 and 58/720 | 43 s | `<m>/gate-looptrace.log` |
| `tracker/tools/corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN, 168 total** — json-encode's own baseline, unmoved | 100 s | `<m>/gate-corpus-run.log`, `<m>/gate-corpus-verdicts.txt`, `<m>/corpus-after/` |
| the same, diffed against S2's landing corpus (`scratch-subsume/s2/corpus-after`) | **0 verdicts differ**; `2 of 168 files differ`, both only in the absolute worktree prefix inside one message of `sk03`/`sk05` (`…-wt-subsume-s2` vs `…-wt-json`) — the same two, for the same reason, that S2's own gate recorded | — | `<m>/gate-corpus-diff.txt` |
| `tracker/tools/repl-smoke.sh` | **PASS, 9 groups / 86 checks**: aliasing 2, ffi 5, ffi-tolerant 9, json 20, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 | 365 s | `<m>/gate-repl-smoke.log` |
| `tracker/tools/lsp-smoke.sh` | **PASS, 582 checks** = json-encode's **577** before the merge (cited, not re-run: `tracker/json-stage3/report-J3e.md`:226 and `review-J3e.md`:30, both on the landed tree; also J3a/J3b/J3d) **+ S2's 5** `RowUnsat.e` checks. The B1 program's diagnostic arrives **129 ms** after the `didOpen` (typecheck 0.10 s), severity 1, *"Row partitions are unsatisfiable at field 'RowUnsat.startDate'"* | 63 s | `<m>/gate-lsp-smoke.log`, `<m>/lsp-server.log` |
| `client/scripts/check-corpus.sh` | **60/60 node tests, 0 fail** over the 200-document corpus — json-encode's own gate at its 2afeb426 figure | 42 s | `<m>/gate-check-corpus-fresh.log` |
| `sbt core/test` in full, **twice** (§4.1) | run 1: **1,199 properties, 1 failed** — `(iso)` of `TestRunner`, a 180 s deadline that measures a lock, diagnosed in §4.2. run 2: **1,199/1,199, fully green** | 891 s / 1,218 s | `<m>/gate-full-core-test.log`, `<m>/gate-full-core-test-2.log` |
| `.ei` hygiene | **7** written by the gates under `core/target/scala-3.3.8/classes/modules/` (all gitignored), all deleted; `find core -name '*.ei' -newer <marker>` = **0** afterwards | — | `<m>/ei-after.txt` |

**On `check-corpus.sh`, a note that changes what the gate means.** Its first run took the corpus
that was already in `target/widget-corpus` — written at 19:28, *before* this merge — and so tested
the node side against pre-merge Scala output (60/60, `<m>/gate-check-corpus.log`, 9 s). That is a
weaker gate than it looks, so the corpus and the report document were deleted and the script re-run
end to end: sbt wrote 200 fresh documents + `sales-report.json` from the MERGED tree, `npm ci`,
`tsc`, then 60/60 (`<m>/gate-check-corpus-fresh.log`). The 60/60 in the table is the fresh one.

### 4.1 The full `core/test`, before and after

Two complete runs, because the first had one red (§4.2) and a red has to be diagnosed rather than
re-run away. **Run 2 is the run of record: 1,199 of 1,199, fully green.**

| | properties | result | wall | log |
|---|---|---|---|---|
| **before** — `json-encode` 5d0a2614, from the branch's own tracker | **1,196** | `1196/1196`, with the B1 refutation **gated off** and twenty other refutations each evaluated 100 times | **not recorded** — `tracker/JSON-STAGE3-PLAN.md`:351 gives the count and no wall clock, and none of the J3 reports records one either | — |
| **after**, run 1 | **1,199** | `Failed: Total 1199, Failed 1, Errors 0, Passed 1198` — the one red is `(iso)` | **891 s (14:47)** | `<m>/gate-full-core-test.log` |
| **after**, run 2 | **1,199** | `Passed: Total 1199, Failed 0, Errors 0, Passed 1199` | **1,218 s (20:14)** | `<m>/gate-full-core-test-2.log` |

**Property count, 1,196 → 1,199, accounted for exactly**: `(B1-bound)` and `(rr)` come in with the
merge, and the third is the B1 refutation itself — it was registered only under the flag on
`json-encode`, so the gate lift of §3 *adds a property to the run* rather than merely speeding one up.
Nothing was removed and no verdict moved.

**No saving is claimed for this branch, because there is no before-number to claim it against.** S2
measured 1,698 s → 524 s on `scala3-migration` with the same change and nothing else moving
(`SUBSUME-STAGE2.md` §4.1); on `json-encode` the two figures that exist are these two AFTER runs, and
they differ from each other by **37 %** (891 s and 1,218 s) on the same tree with the same command —
which is itself the useful fact: a full-run wall clock on this machine is not a measurement unless the
runs are interleaved, and the gate policy already says so.

### 4.2 The one red, diagnosed and not re-run away

```
[info] ! JSON document runner (J3c).(iso) after a Runner has booted, a fixture session still
       type-checks, within a bound: Falsified after 0 passed tests.
[info] > Labels of failing property:
[info] Expected "ok" but got "did not finish"
[info] a fixture type-check after a Runner boot: did not finish, 180004 ms
```

`(iso)` (`TestRunner.scala:915-947`, J3c) runs `fx.loadStatements` on a daemon thread and joins it
with a 180 s deadline. **`loadStatements` takes the process-global `ErmineFixture.literalLock`** (`TestErmine.scala:152`, and `typeChecks` at `:177` goes through it), and
the failure lands, in the log, in the middle of `TestDateAndScan`'s block: line 2763 of
`<m>/gate-full-core-test.log`, with that suite's properties at 2751 and 2787 either side of it and
the B1 refutation at 2838 and `underZone` (*"the same answers under five default zones"*) at 2847 —
the two properties that hold that same lock through library-scale loads. So the deadline expired
**waiting for the lock, not waiting for a check**. That is precisely the red S2 found inside its own
first pin and wrote down as a rule (`SUBSUME-STAGE2.md` §2.3: *"a deadline pin that wraps
`loadStatements` is measuring lock contention"*), and it falsifies, by measurement, the J3c review's
prediction for this very pin (`tracker/json-stage3/review-J3c.md`:407 — *"180 s is far above the real
cost (the entire suite is 22 s), so it will not flake"*).

Three controls, all green, none of which needed the red to be excused:

| control | result | wall | log |
|---|---|---|---|
| `TestRunner` ALONE | **17/17**, `(iso)`: `OK, proved property` | 44 s | `<m>/rerun-testrunner-alone.log` |
| `TestRunner` + `TestDateAndScan` + `TestRowRefusals` in ONE JVM — the three suites that could contend | **31/31**, `(iso)` green | 379 s | `<m>/rerun-trio.log` |
| the full `core/test`, again | **1,199/1,199** | 1,218 s | `<m>/gate-full-core-test-2.log` |

**Is it this merge's doing? Honestly: not settled, and the two ways it could be are worth stating.**
The merge changes the schedule of a full run in two directions that both raise lock pressure in that
window — the B1 refutation now runs *at all* on this branch (one more library-scale load under
`literalLock` inside `TestDateAndScan`), and twenty refutations that each ran 100 times now run once,
so the run is far shorter and more suites overlap in the same minutes. Neither makes `(iso)` wrong;
both make its 180 s more likely to be spent queueing. Two runs cannot separate that from luck.

**The fix, APPLIED as follow-up F-2** on the orchestrator's instruction (§7): `(iso)` now loads
through `ErmineFixture.loadNamed`, which takes no lock, so its 180 s bounds the load and the
type-check rather than the queue. The deadline and every assertion are unchanged. It was **not**
quarantined: this programme exists because a quarantine hid a harness bug for a day, and `(iso)` is a
sound pin with a mis-specified bound, not a flaky assertion.

---

## 5. Uncommitted paths — for the orchestrator to commit after review

```
scalacheck-binding/src/main/scala/TestDateAndScan.scala      (gate lift, §3)          +12/-12
scalacheck-binding/src/main/scala/TestNamedFields.scala      (follow-up F-1, §7)       +1/-1
scalacheck-binding/src/main/scala/TestRunner.scala           (follow-up F-2, §7)      +22/-3
tracker/GATE-POLICY.md                                       (gate lift, §3)           +8/-9
tracker/TICKET-editor-and-solver-followups.md                (gate lift, §3)          +31/-1
tracker/satterm/SUBSUME-M2.md            (this report, was an untracked stub)
```

Not this stage's, and already in the tree before it: `docs/JSON-GUIDE.md` (untracked, pre-existing).
`tracker/repl-classpath.txt` was regenerated for the smokes and restored (`git checkout --`), as the
common brief requires.

Suggested commit message for the gate lift: *"Lift the B1 quarantine: the checker terminates (S0/S1a/S1b),
the harness did not (S2)"*.

---

## 6. What this stage says, and what it does not

* **It says** that `scala3-migration` at d278c900 merges into `json-encode` cleanly, that the
  programme's instrumentation and the JSON branch's selector change coexist in `Subst.scala`, and that
  with `rejects` in the tree the B1 refutation is an ordinary fast property: green at the default
  `minSuccessfulTests`, inside a 10-minute deadline, with no flag.
* **It does not** re-establish the programme's answer to the title question — that is S0's measurement
  and S1a/S1b's theorems, carried over unchanged, with S1b §8's limits (no termination theorem under
  `-Dermine.dequeuePolicy=shipped`; the `runSP_*` soundness family still assumes `rowSoundBare = false`).
* **Open, carried forward**: nothing from §2 or §4.2 — both are fixed in §7, and the reviewer is asked
  to check those two diffs; the LSP smoke's 129-module boot (JSON-STAGE3-PLAN's standing cost); and the `:648` walk as a
  performance item in `tracker/TICKET-perf-type-inference.md`.
* **What the reviewer is asked to re-run** (brief): the B1 suite alone, `TestRowRefusals`, and a read
  of `<m>/gate-full-core-test-2.log`. `<m>/gate-full-core-test.log` is the run with the `(iso)` red and
  is worth reading beside §4.2 rather than instead of it.

---

## 7. Follow-ups, applied after the gates on the orchestrator's instruction (2026-09-17)

Both were findings of this report's own first draft (§2, §4.2); the orchestrator asked for them as
part of the SAME uncommitted change rather than as a separate ticket. The full `core/test` was NOT
re-run: §4.1's 1,199/1,199 stands as the landing run, and neither follow-up can add a property or
change a verdict — F-1 changes how many times one green property is evaluated, F-2 changes which
loader one pin uses.

### F-1 — `TestNamedFields.scala:393`, `no(` → `rejects(`

`property("an existential field gets no selector, a sibling still does")` is a FIXED program, so
`no`'s *passed* status asked ScalaCheck for a hundred evaluations of a three-load property. One word
changed; the verdict is identical and the cause is unchanged. This also puts the line back in parity
with the 2.11 branch, where the P211 port already converted the equivalent site
(`json-encode-2.11`, `TestNamedFields.scala:416`).

**Before and after, from the logs**: `OK, passed 100 tests` in the full run of §4.1
(`<m>/gate-full-core-test-2.log`) → `OK, proved property` alone and in the trio.

### F-2 — `TestRunner.scala`'s `(iso)`: `loadStatements` → `loadNamed`

The pin now takes its own process-unique module name (`"IsoUse" + isoCounter.incrementAndGet()`, a
counter beside the property) and loads through `ErmineFixture.loadNamed`, which takes no lock; the
type-check reads `fx.typeOf("isoUse", Map(mod -> fx.all))` against that module. **The 180 s deadline,
the daemon thread, the `bootedOk` guard and the `answer ?= "ok"` assertion are untouched** — only the
loader changed, so what the deadline bounds changed from the `literalLock` queue to the work. A
twenty-line scaladoc block above the property records why, citing `SUBSUME-STAGE2.md` §2.3 (*"a
deadline pin that wraps `loadStatements` is measuring lock contention"*) and §4.2 of this report for
the measured red and its three controls.

### Gates for the follow-ups

| gate | result | wall | log |
|---|---|---|---|
| `sbt core/compile core/copyResources core/Test/compile` | **exit 0**, 0 errors | 17 s | `<m>/followup-compile.log` |
| `TestNamedFields` ALONE | **16/16**; the converted property reads `OK, proved property` | 30 s | `<m>/followup-testnamedfields-alone.log` |
| `TestRunner` ALONE | **17/17**; `(iso)` reads `OK, proved property` | 29 s (44 s before F-2) | `<m>/followup-testrunner-alone.log` |
| `TestDateAndScan` + `TestRunner` + `TestNamedFields` in ONE JVM — the three suites of §4.2's contention | **46/46**, no red; `(iso)` and the converted property both proved | 277 s | `<m>/followup-trio.log` |
| `.ei` hygiene | 13 written by these runs, all deleted; `find core -name '*.ei' -newer <marker>` = **0** | — | `<m>/ei-after-followups.txt` |

The full `core/test` was deliberately not re-run (orchestrator's instruction); §4.1's run 2 remains
the landing figure.
