# Script-level gate history: did running the gate catch real defects?

Repository: `/home/dmitry/research/ermine/ermine-scala`, all branches, 2026-08-29 .. 2026-09-17.
Read-only audit, written 2026-09-17. Current policy: `tracker/GATE-POLICY.md` (adopted 2026-09-08).

Conventions used below.
- Table columns: class | fix commit (8-char short SHA) | date | one-line defect | verbatim quote (<= 200 chars) | source.
- "found by review" means a reviewer read the script or ran an ad-hoc probe. It did NOT come from running the gate as written. Such items can only be SELF-DEFECT for that gate, never a catch.
- `UNSURE:` marks a tentative classification; the tally counts it under that class. The reason is in the row.
- WRITTEN-WITH-FIX rows are listed for completeness. They are not in the tally line, which has no field for them.
- A defect already ticketed before the gate ran is NOT a catch. Such items are listed under "not counted" where relevant.
- Per-suite `core/test` catches (a named property caught it) belong to the per-suite audit. They are listed but not counted in section 12.

---

## 1. compile: `sbt core/compile core/copyResources`

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| FALSE-ALARM | fc2ce4a5 (worked around with `core/clean`) | 2026-09-11 | zinc incremental compile reports cyclic references that are not real | "an INCREMENTAL `core/compile` after touching `Mark.scala` or `ParseState.scala` can fail with **27 `E046 Cyclic reference involving val <import>`** errors" | tracker/loopmodel/LSP4-7.1a-MARK.md:571 |

No catch attributed to the compile gate was found. The one red compile with consequences (D1-B, "Conflicting definitions") was a correct red. The driver ignored it, which is recorded under section 7.

`compile: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=1 FLAKE=0`

## 2. TestLoopTrace (`sbt 'core/testOnly *TestLoopTrace'`)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| SELF-DEFECT (found by review) | 4aeb4cfc | 2026-09-04 | a failure on the compiler side (child timeout, non-zero exit, empty trace) was reported as PASS | "One required fix, F1: **the property turns a failure of the compiler side into a PASS.**" | tracker/loopmodel/L4-REVIEW.md:26; 4aeb4cfc: "(the review caught the first version reporting those as passes)" |
| SELF-DEFECT | fix commit: not identified (D1 Part B era; 74b49298 likely) | 2026-09-06 | with rule flags forwarded, the gate went red because the gate's own oracle binary had a bug (`looptrace` Main.lean seed path) | "TestLoopTrace with flags forwarded FAILS on a one-line Main.lean seed-path `--trace` bug (fix authorised; looptrace rebuild only after \"D1-T done\")" | tracker/LOOP-MODEL-HANDOFF.md:535-536 |
| SELF-DEFECT | none (by design since L4 F1: a missing binary skips) | 2026-09-11..16 | the model-agreement property SKIPS and reads green when the `looptrace` binary is absent (every fresh worktree). Sightings: SIG-1, LET-1, J2a, J3a, J3b, SUBSUME S0, sig-entail | "a self-skipping property is green precisely when the model is missing" | tracker/satterm/SUBSUME-STAGE0.md:738; also json-stage3/review-J3b.md:381, review-J2a.md:267, loopmodel/LET-1-FIX.md:340, loopmodel/SIG-1-SURVEY.md:691 |

No product-code defect was found that running TestLoopTrace revealed. After 4aeb4cfc every recorded run reads 702/708/714/720 agree. The PANIC3 makeEmpty bug (b0c97b99) was found by the L5 witness hunt, not by this property. The property only carried PANIC3 after the fix.

`TestLoopTrace: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=3 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

## 3. Corpus verdicts: `tracker/tools/corpus-run.sh` (--batch) + `corpus-verdicts.py`

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| SELF-DEFECT | e5158756 | 2026-09-02 | no PATH in a background run, so every file failed with `java: not found`, and the comparison still read "0 differ" | "Without it a background invocation produced 66 files of `exec: java: not found` and a comparison that read \"0 of 66 differ\"." | e5158756 |
| SELF-DEFECT | e5158756 | 2026-09-02 | corpus-verdicts.py returned a clean zero when a side was all UNKNOWN | "corpus-verdicts.py REFUSES to compare when either side is entirely UNKNOWN, rather than returning a clean-looking zero. Three times today a zero has meant \"measured nothing\"" | e5158756 |
| UNSURE: SELF-DEFECT (a scope limit, not breakage) | 779060d4 | 2026-09-02 | a corpus sweep cannot see signatures, yet ticket rows had claimed it would | "So TICKET-row-solver-8abc.md line 599 was false, and false in the direction that makes a zero look stronger than it is" | 779060d4 |
| SELF-DEFECT (found by review) | 42211f70 | 2026-09-07 | per-file library hoist missing for Present/ (and Algebra/Time): the non-batch path fails every module in the group | "**M-10 — `corpus-run.sh`'s per-file hoist for `Present/` is missing** (§8). Without it the non-batch path fails every module in the group." | tracker/loopmodel/E4-REVIEW.md:628-629 |
| SELF-DEFECT (found by review) | f8a7473b | 2026-09-07 | per-file hoist missing for Lang/ | "**The per-file hoist is missing** in the committed `corpus-run.sh` (lines 167–178), exactly as it was for `Present/` when E4's review ran" | tracker/loopmodel/E5-REVIEW.md:894-895 |
| FLAKE | none (ticket B6) | 2026-09-07 | blame clause/field of the same refutation moves run to run; verdicts stable | "`der04` flips between two runs of the *old* script with no `Wide` anywhere, so the clause is not stable even at a fixed command line" | tracker/loopmodel/E1-REVIEW.md:133-134; F1-FIXES.md:16-17 ("nondeterministic run to run on the PRE-FIX build alone (18 runs") |
| EXPECTED-CHANGE | 59d92f22 | 2026-09-01 | labelCheck adoption rejects the four unsatisfiable modules | "per-file over 45 modules exactly four verdicts change, the four unsatisfiable ones, LOAD -> REJECT" | 59d92f22 |
| EXPECTED-CHANGE | 7e06181b | 2026-09-06 | rowSound/smallcanon adoption: nine shouldfail modules blame a different clause | "corpus verdicts unchanged, 23 loaded / 43 rejected and 18 / 16, with nine shouldfail modules blaming a different clause or field of the same refutation" | 7e06181b |
| EXPECTED-CHANGE | 6fc77fac | 2026-09-08 | F3 B1 static rejection adds one REJECTED | "one added line (`date01`), 13 modules with a changed CLAUSE, **zero** changed verdicts" | tracker/loopmodel/F3-REVIEW.md:589 |
| EXPECTED-CHANGE | 75253148 | 2026-09-11 | LET-1 fix: let01..let05 flip to REJECTED | "the five `let0N` flip LOADED→REJECTED (the regression, on the corpus itself), the two paths, **and `mis01`**" | tracker/loopmodel/LET-1-REVIEW.md:137 |
| REAL-DEFECT | fix commit: not identified (followups ticket §4) | 2026-09-03 | first runs of the new --batch mode exposed a cross-module solver accumulation cliff in one JVM | "Also found and recorded: a solver accumulation cliff across modules in one JVM (gu05 1.1 s alone, 27 s after two other modules; the full 110 still do not batch)" | c777cbd6 |
| UNSURE: REAL-DEFECT (the defect class was already ticketed as followups item 1; the root causes, Term.sub and scheme locations, were new) | 1411c6c9 | 2026-09-01/02 | labelCheckEarly measurement: 11 of 26 changed messages blamed a stdlib file | "**11 of the 26 get a worse LOCATION**, moving the blame from the user's file into the stdlib" | tracker/TICKET-row-solver-8abc.md:232-233 |
| WRITTEN-WITH-FIX (defect already ticketed) | c777cbd6 | 2026-09-03 | StreamTUtils stack overflow on batch loads; --batch mode and fix landed in one commit | "a big enough batch of modules overflowed the stack ... and every corpus tool went one file per JVM" | c777cbd6; TICKET-editor-and-solver-followups.md:75 |

The EXPECTED-CHANGE rows are a sample. Every adoption commit re-baselines verdicts or messages.

`corpus verdicts: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=5 EXPECTED-CHANGE=4 FALSE-ALARM=0 FLAKE=1`

## 4. Lean: `lake build` + `lake env lean Audit.lean` + `#print axioms`

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| UNSURE: GATE-DEFECT (the defect is in the Lean proof library, a verification artefact, not product code; the implementer had run only `lake build looptrace`) | eb3a921d (S4 committed after the fix round) | 2026-09-07 | the S4 model mirror broke the S2 no-false-accept chain, so the full default target failed and the axiom audit could not run | "One delivered artefact is broken, and it is the one the stage's own standing constraint names: **`lake build` fails.**" | tracker/loopmodel/S4B-REVIEW.md:14-15, :173-185 ("error: Rowpartition/Loop/NoFalseAccept.lean:946:76: unsolved goals") |

No run of `Audit.lean` or `#print axioms` was found reporting a non-zero non-standard axiom or a `sorryAx`. Every recorded run reads "0 non-standard".

`Lean: REAL-DEFECT=0 GATE-DEFECT=1 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

## 5. `tracker/tools/repl-smoke.sh`

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| SELF-DEFECT (found by review) | none in the script; rule added to GATE-POLICY in 16889be4 | 2026-09-11 | checked-in absolute `tracker/repl-classpath.txt`: from any worktree the smoke tests the MAIN checkout's build | "Run from this worktree it therefore tested the main checkout's build, not the sig-entail build, so my \"8/8 PASS, goldens byte-identical\" was vacuous" | tracker/loopmodel/SIG-1-SURVEY.md:702-704 |
| WRITTEN-WITH-FIX | fac46775 | 2026-09-07 | the piped console looped forever at EOF; the pipedeof golden and timeout guard came with the fix | "repl-tests/pipedeof adds 12 golden checks and repl-smoke.sh a timeout and exit-code guard so the hang cannot return silently." | fac46775 |
| WRITTEN-WITH-FIX | 53216547 | 2026-09-09 | tauto group added for S5 Q-1 | "Q-1 (the LSP path lacked publishing=true, hover disagreed with the .ei) fixed with lsp-smoke and repl-smoke guards that fail with the flag off." | 53216547 |
| WRITTEN-WITH-FIX | 6459cc27 | 2026-09-09 | ffi / ffi-tolerant groups added with the FFI tolerance change | (group files added in the same commit: `git show --stat 6459cc27 -- tracker/repl-tests`) | 6459cc27 |

`git log --all -- tracker/repl-tests` shows only commits that add group lines: d7df298b, 122eb4ee, 61432b0b, 0d9b961e, fac46775, 6459cc27, 53216547, 711448ca, 36eaf0dc (every `--stat` is insertions only). No golden line was ever rewritten or deleted, so no red was ever resolved by a baseline refresh.

`repl-smoke: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=1 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

## 6. `tracker/tools/lsp-smoke.sh` + `lsp-client.py`

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| WRITTEN-WITH-FIX | 14b93738 | 2026-08-30 | editor checks inherited useInterface=on, so type errors went unreported | "Writing it caught a real 0.3 bug: checks ran with useInterface inherited from the boot env (on)" | 14b93738 |
| WRITTEN-WITH-FIX | 1da2c82b | 2026-08-31 | Report.e published 329 shadowing diagnostics; found by a perf baseline, not the smoke; Bool.e check added with the fix | "Found while taking 5.5's baseline measurement on Report.e, which is the only reason it was found at all — every fixture in lsp-tests is a file the resident session has never heard of." | 1da2c82b |
| UNSURE: REAL-DEFECT (found by the S5 reviewer's ad-hoc probe through a scripted LSP client, not by lsp-smoke.sh fixtures; the review does not name lsp-client.py) | 53216547 | 2026-09-09 | the editor path lacked publishing=true, so hover and the .ei disagreed | "Driven with a scripted LSP client against a probe module: hover answers `TautoProbe.pos : forall (r: rho). (exists (h: rho) (t: rho). r <- (t, h)) =>" | tracker/loopmodel/S5-REVIEW.md:30 (Q-1) |
| EXPECTED-CHANGE | bf2f7f80 / e61cc402 (sig-fixes merged) | 2026-09-11 | at the new default sigEntail=error the session cannot boot until the stdlib signature corrections land | "**FAIL, and for the one cause**: the server's session cannot BOOT (`Ermine session failed to boot: DrilldownList.e:20:98 ...`)" | tracker/loopmodel/SIG-3-IMPL.md:449 |
| UNSURE: EXPECTED-CHANGE (the report says "fixed by decision 6, not by changing the check") | d21f304f | 2026-09-16 | J3a changed a refusal message that lsp-client.py asserts on | "`lsp-smoke.sh` failed twice before passing: once on the `ermine/schema` refusal message (fixed by decision 6, not by changing the check)" | tracker/json-stage3/report-J3a.md:81 |
| FALSE-ALARM | d21f304f | 2026-09-16 | debounce timing checks failed under a saturating Lean build | "once on 7.2/7.4 debounce timings while the Lean build saturated the machine." | tracker/json-stage3/report-J3a.md:81 |
| FALSE-ALARM | eb2f4e7a (client timeout 120 -> 240 s) | 2026-09-16 | client hang guard timed out twice under load while the server completed | "it FAILED (timed out) twice at the old 120 s, `SP/gate5-lsp.log` / `SP/gate5-lsp2.log`" | tracker/json-stage3/report-J3e.md:226 |
| SELF-DEFECT (found by review) | 360306c7 | 2026-09-11 | lsp-client.py debounce audit would fail on a correct server | "`lsp-client.py`'s `waited == policy == clamp(150, median, 300)` audit would fail on a correct server the first time a fixture queues two documents." | tracker/loopmodel/LSP4-7.4-REVIEW.md:405-406 |
| SELF-DEFECT (found by review) | none in the script; GATE-POLICY rule | 2026-09-11 | the same worktree classpath trap (`lsp-smoke.sh:12`) | "The review found the same defect in `g1-validate.sh:12`, `lsp-smoke.sh:12`, `g1-diff.sh:17` and `perf-bench.sh:94`" | tracker/loopmodel/SIG-1-SURVEY.md:705-707 |

`lsp-smoke: REAL-DEFECT=1 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=2 FALSE-ALARM=2 FLAKE=0`

## 7. `tracker/tools/looptrace-corpus.sh` (18-group Lean-vs-compiler differential) + `looptrace-diff.py`

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| WRITTEN-WITH-FIX | 6a664bbb | 2026-09-04 | L1: two bugs in the Lean model's CHAMP hash-set emulation (plus two found by the implementer's differential) | "the reviewer's own seeds and fuzzes found two bugs in the model's CHAMP hash-set emulation -- sub-node inlining on removal, and both early returns of concat" | 6a664bbb; L1-MODEL.md:16-17 |
| WRITTEN-WITH-FIX | 75d1c97c | 2026-09-04 | L2: two model gaps (makeEmpty's skolem refusal; Supply.fresh crossing a 1024-id block) | "Two model gaps found and fixed by the replay: makeEmpty's skolem refusal (five shouldfail modules reach it) and Supply.fresh crossing a 1024-id block boundary" | 75d1c97c |
| UNSURE: REAL-DEFECT (in-development Scala behind a default-OFF flag; "defect" = disagreement with the model's chosen tie order, resolved by changing the Scala) | 74b49298 | 2026-09-06 | D1-B: the compiler's smallcanon `canonKey` treated an empty abstract list as a prefix; the model uses a sentinel | "which is exactly where the two implementations disagreed ... Six segments of 92,673, and all six of this one shape." | tracker/loopmodel/D1-CHANGE.md:353-359 |
| FALSE-ALARM | 74b49298 | 2026-09-06 | the driver ran the sweep and differential after a FAILED compile, so a phantom "fix had no effect" | "Cause of the phantom \"fix had no effect\": the driver ran gates after a FAILED compile (stale classes)" | tracker/LOOP-MODEL-HANDOFF.md:517-518 |
| UNSURE: SELF-DEFECT (the bug was in the differential's own streaming replay, introduced the same stage; S2-FIX calls it the differential "doing its job") | c079e951 | 2026-09-06 | the flags-ON run disagreed on 1 of 2,355,430 segments because the streaming replay dropped the new `senv` record | "`senv` had been added to `Replay.lean`'s `parseSegments` (used by the batch path) and not to it, so the streaming path threw the environment facts away." | tracker/loopmodel/S2-FIX.md:919-933 |
| UNSURE: SELF-DEFECT (a documented scope limit found by review, not breakage) | none (accepted-abstraction table) | 2026-09-04 | non-row constraint items arrive pre-reduced to (hash, eq-class), so queue construction from raw input is untested | "**This is a faithfulness gap in the corpus differential, though not in the model, and not one that affects L3**" | tracker/loopmodel/L2-REVIEW.md:290-291 |

`looptrace-corpus: REAL-DEFECT=1 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=0 FALSE-ALARM=1 FLAKE=0`

## 8. `tracker/tools/trace-ab.py` (compiler-vs-compiler trace A/B)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| SELF-DEFECT (found by review) | 6fc77fac | 2026-09-08 | the scratch version compared 6 of 16 record kinds; "8 segments in 2 groups" was an artefact | "the row-trace instrument compared 6 of the trace's 16 record kinds, so \"8 segments in 2 groups\" was an artefact" | tracker/loopmodel/F3-FIXES.md:753 (review N-1) |
| EXPECTED-CHANGE | 6fc77fac | 2026-09-08 | K-1 guard fix blast radius | "402 of 3,205,346 segments in 18/18 groups ... dominated by detm nParts DECREASING 510 times and increasing 0 -- the fix working" | 6fc77fac |
| EXPECTED-CHANGE | 9313d109 | 2026-09-13 | E11a canonical form moves the solver path | "IDENTICAL is not expected: the published order feeds every call site." | tracker/loopmodel/E11a-CANON.md:380 |

Not counted: E11c (d68e564c) used trace-ab to localise the two id-order reads behind the E11 SET class. That defect was already known (E11b parked, TestTolerantCheck quarantine), so this was an investigation, not a catch.

`trace-ab: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=1 EXPECTED-CHANGE=2 FALSE-ALARM=0 FLAKE=0`

## 9. `tracker/tools/ei-diff.sh` + `ei-classify.py` (interface sweep)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| WRITTEN-WITH-FIX (instrument committed with the decision) | cf43dabf | 2026-09-02 | 8b spliceGuard (flag OFF) degrades published signatures; repair declined | "Diffing the published .ei signatures then said not to take it: the guard's precondition fails on 90% of splices, and suppressing them degrades signatures" | cf43dabf |
| REAL-DEFECT | 4c18fa5c (classified quality, not soundness, in 84c2abd0) | 2026-09-02 | cumulative sweep: 4 published types regressed from a concrete row to constrained polymorphic (cut; build order) | "4 SHAPE -- a resolved concrete row becoming a constrained polymorphic type.  Those 4 are a regression" | 52f8df40; fix 4c18fa5c: "Both build orders now publish byte-identical `HeadcountPlan.ei`." |
| SELF-DEFECT | 52f8df40 (decision reopened) | 2026-09-02 | the diff behind the 8b decline was taken under build-order-dependent conditions | "that diff was itself taken in a build-order-dependent regime, so the decision needs re-examining rather than standing." | 52f8df40 |
| SELF-DEFECT | fix commit: not identified (ei-classify.py first committed 932f22e6) | 2026-09-03 | matcher sorted right-hand sides by original names, which the bijection does not preserve (false "other") | "Found only after the matcher stopped sorting right-hand sides by their ORIGINAL names — a sort that is not preserved by the bijection" | tracker/satterm/KEYED-SPLIT-STAGE2.md:372 |
| FLAKE | none (compare "up to order") | 2026-09-03/06 | published .ei not byte-stable at a fixed configuration; batch churn 18 of 185 vs per-file control 6 of 188 | "(1) .ei is NOT byte-stable at a fixed configuration (published constraint lists print in Set/hash/id order)" | tracker/LOOP-MODEL-HANDOFF.md:508-509; c777cbd6 |
| UNSURE: EXPECTED-CHANGE (accepted at adoption; the review corrected a classifier-based "not weaker" claim) | 7e06181b | 2026-09-06 | RevenueShare.shareOfGroup became strictly more general | "it is strictly WEAKER, i.e. the published type is strictly MORE GENERAL." | tracker/loopmodel/A1-REVIEW.md:513; 7e06181b "so no call site regresses" |
| SELF-DEFECT (found by review) | 6fc77fac | 2026-09-08 | sweep hoisted only Ai/Common.e, so ~half the healthy corpus produced no .ei | "**45 of the 92 healthy (non-`shouldfail`, non-`incomplete`) corpus modules produce no `.ei` at all**, on either side" | tracker/loopmodel/F3-REVIEW.md:195-201 (N-4) |
| EXPECTED-CHANGE | 53216547 | 2026-09-09 | S5 tautology deletion moves exactly four Layout.Scan bindings | "3477 identical / 0 order-only / 0 alpha / 4 other -- exactly Layout.Scan's count 1->0, count' 2->0, sumBy 3->2, avgBy' 3->2" | 53216547 |
| SELF-DEFECT (found by review) | 53216547 | 2026-09-09 | headline read "268 of 268 differ" for every flag A/B (key-differs row) | "**`ei-classify.py` now reports \"N of 268 interfaces differ\" as 268 for every flag A/B.**" | tracker/loopmodel/S5-REVIEW.md:35 (Q-6) |
| SELF-DEFECT (found by review) | fix commit: not identified (8bfd7d8e: "the ei-classify fix open") | 2026-09-13 | matcher commits to the first bijection (26 of 47) and split_sig mis-parses unparenthesised contexts (17 of 47) | "**Does `ei-classify.py` need its matcher fixed?**  Yes, and its PARSER too — two separate defects" | tracker/loopmodel/E11a-REVIEW.md:305-310 |
| REAL-DEFECT | fix commit: not identified (ticket B9 filed 202a9110, "filed, not scheduled") | 2026-09-13/14 | ON-vs-OFF sweep diff: stackedPair loses kind binders; follow-up shows OFF's shipped scheme is ill-kinded (published without a kind check). The classifier's verdict missed it; review of the raw diff caught it | "`ChartsExample.e:stackedPair` publishes THREE FEWER implicit kind binders under ON ... the `ei-classify` summary \"no published type got weaker\" does not cover kind generality." | tracker/loopmodel/E11c-REVIEW.md:23; aa2d7bb6 subject: "OFF's (sa: c) is ill-kinded" |

Not counted: the F4 `.ei` round-trip bug (f9266adb, "70 of 241 interfaces were silently rechecked on every load"). It was found by the S5 reviewer's probe (S5-REVIEW.md Q-16), not by the sweep.

`ei-diff: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=5 EXPECTED-CHANGE=2 FALSE-ALARM=0 FLAKE=1`

## 10. `tracker/tools/g1-validate.sh` (+ `g1-diff.sh`, `tracker/g1-baseline`)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| WRITTEN-WITH-FIX | 7ebcbfa6 | 2026-08-30 | first self-agreement run exposed parallel-loader nondeterminism in .ei bytes; loadInSeries and writeInterface sort added in the same commit | "Getting self-agreement to pass surfaced real nondeterminism: parallel module makes draw Supply ids in thread-timing order" | 7ebcbfa6 |
| REAL-DEFECT (in-development pipeline behind -Dermine.pipeline=new) | 6d15c91d | 2026-08-30 | the same-commit old/new .ei oracle found six divergences in the new pipeline | "Six divergences fixed against the same-commit old\|new oracle: literal identifiers strip their backtick delimiters and escapes;" | 6d15c91d |
| SELF-DEFECT | 2a7efaeb | 2026-08-31 | four breakages; not run since D3; baseline referenced by nothing | "THE G1 ORACLE HAD NOT WORKED SINCE POST-G1 D3." ... "tracker/g1-baseline ... was referenced by nothing in tracker/tools and had never once been checked." | 2a7efaeb |
| EXPECTED-CHANGE | 49e63cc7 (baseline re-cut, Step 0) | 2026-08-31 | first arming: 1 of 1447 differing, the documented lookbackJoin residual; baseline stale | "1447 signatures, exactly one differing, and it is lookbackJoin -- the documented solver-order-sensitive residual." | 2a7efaeb |
| UNSURE: REAL-DEFECT (the change is rendered order only, all 1447 alpha-equivalent, in an uncommitted perf change) | 49e63cc7 (the Kind.subKind fast path reverted) | 2026-08-31 | a "no-op" substitution fast path flipped partition RHS rendering order across ChartMode-shaped signatures | "All 1447 signatures stayed alpha-equivalent, so only the browse byte-diff caught it -- the artifact the hard gate had been armed for twenty minutes earlier." | 49e63cc7 |
| SELF-DEFECT (found by review) | 53216547 (re-cut) + 66f3728c (put in Tier 1) | 2026-09-09 | the drift check was red since F3 (intended signature changes) and in no tier, so nobody ran it | "**`tracker/tools/g1-validate.sh`'s baseline-drift check is RED, and has been since F3.** ... it is in no `GATE-POLICY.md` tier, so nobody has run it since." | tracker/loopmodel/S5-REVIEW.md:44 (Q-15) |
| EXPECTED-CHANGE | e61cc402 | 2026-09-11 | sig-entail landing re-cut | "tracker/g1-baseline re-cut from a fresh boot: the only signature drift is the three corrected library contexts (cons_Bracket, partialLookup, unify1)" | e61cc402 |
| EXPECTED-CHANGE | 9313d109 | 2026-09-13 | E11a canonical form re-cut | "Every .ei moves (order/alpha only ...); tracker/g1-baseline re-cut (order, then letters)." | 9313d109 |
| SELF-DEFECT (found by review) | none in the scripts; GATE-POLICY rule | 2026-09-11 | worktree classpath trap (`g1-validate.sh:12`, `g1-diff.sh:17`) | "from any worktree those five gates silently measure another tree, which is worse than a missing gate" | tracker/loopmodel/SIG-1-SURVEY.md:707-708 |

`g1-validate: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=3 EXPECTED-CHANGE=3 FALSE-ALARM=0 FLAKE=0`

## 11. `tracker/tools/perf-bench.sh` (perf A/B)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| SELF-DEFECT | ebcc14b1 | 2026-08-31 | stale-build guard cried stale on a current tree (mtime truncated to ms) | "Two bugs in the harness, both caught by its output rather than by review.  The stale-build guard cried stale on a current tree" | ebcc14b1 |
| SELF-DEFECT | ebcc14b1 | 2026-08-31 | editor run reported a negative residual for didOpen | "the first editor run reported a negative residual for the didOpen round, because it subtracted a debounce that didOpen does not pay." | ebcc14b1 |
| SELF-DEFECT | b265bbf5 | 2026-08-31 | unescaped regex dots in the pgrep preflight matched source paths; the run was refused silently | "It then refused the run silently, printing no median rather than an error, which is the worst failure mode for a measurement tool." | b265bbf5 |
| SELF-DEFECT | fix commit: not identified ("The harness was not modified") | 2026-09-10 | preflight `pgrep -f 'sbt-launch\|xsbt\.boot'` matched an orchestrator shell and refused every run | "its preflight `pgrep -f 'sbt-launch\|xsbt\.boot'` matched an unrelated orchestrator shell whose command line merely NAMES those strings, so it refused every run." | tracker/loopmodel/LSP4-7.0-READ.md:104-106 |
| SELF-DEFECT (found by review) | none; GATE-POLICY rule | 2026-09-11 | worktree classpath trap (`perf-bench.sh:94`) | "The review found the same defect in ... `perf-bench.sh:94`" | tracker/loopmodel/SIG-1-SURVEY.md:705-707 |
| UNSURE: REAL-DEFECT (the cost is at or just above the ~1% floor, and it was measured by an ab.sh replica of perf-bench's shapes because perf-bench.sh's preflight refused) | fc2ce4a5 (MarkOff on the strict path) | 2026-09-11 | the 7.1a high-water mark cost batch loads +0.8..1.9%; fix brought the pooled delta to 0.00% | "THE TWO INTERLEAVED A/Bs — the one gate that moved, and the fix that closed it" | tracker/loopmodel/LSP4-7.1a-MARK.md:397, :490-515 |

`perf-bench: REAL-DEFECT=1 GATE-DEFECT=0 SELF-DEFECT=5 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

## 12. Full `sbt core/test` (generic full-suite runs only)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| FLAKE | 1a6fdc2e (protocol) | 2026-08-30 | cross-suite concurrency flake in one JVM, second sighting | "Second sighting of suites interfering when run concurrently in one JVM ... always green on re-run and in isolation." | 1a6fdc2e |
| UNSURE: FLAKE (one of the two root causes, Dep closures baking session flags, is product code in Session) | be085509 | 2026-08-31 | recurring eval:unbound flake: dep-cache poisoning across suites; shared Supply raced | "Dep closures no longer bake creation-session typeCheck/ useInterface — gated in make() with the live session, ending dep-cache poisoning across suites." | be085509 |
| FLAKE | edb6434f | 2026-09-09 | intermittent "Module not found: 'Test'": a test flipped ermine.loadInSeries process-wide | "The F4-era intermittence (942+1 error one run in two, \"Module not found: 'Test'\") was TestInterfaceKey setting ermine.loadInSeries=true" | edb6434f |
| FLAKE | none (ticket E12; one re-run rule) | 2026-09-11 | TestInterfaceRoundTrip fails ~1 full run in 10 via depCache cross-suite repopulation | "fails roughly one full run in ten when ANOTHER SUITE in the same JVM repopulates the process-global `Session.depCache`" | tracker/GATE-POLICY.md:43-44 |
| FLAKE | none (ticket E13) | 2026-09-06 | TestLegend "extra args are ignored" seed-dependent date formatting | "The second failure is `Legends & presentations.extra args are ignored` (`TestLegend`, failing seed" | tracker/loopmodel/S2-REVIEW.md:555; GATE-POLICY.md:48 |
| FLAKE | none (E11b parked) | 2026-09-16 | E11a SET ceiling pin trips on an unchanged tree | "seen at the J3b landing as \"SET class grew past its ceiling 3: (reportFor,4)\", green on re-run 3/3" | tracker/GATE-POLICY.md:50-54 |
| SELF-DEFECT | 1c8ff562 (quarantined) | 2026-08-30..09-08 | `disjunction sound` red in every full run and carried as "the known failure" | "generator starvation (0 passed / 501 discarded, every run on record); the rule ships OFF." | tracker/GATE-POLICY.md:41 |
| SELF-DEFECT | dcd367de (harness `rejects`), 36c2dcf9 (quarantine lifted) | 2026-09-16 | three landing runs wedged; quarantined as a non-terminating checker (3374deaf); really ScalaCheck re-evaluating a passed refutation | "what ran for twenty minutes was ScalaCheck evaluating a *passed* refutation a hundred times, fixed by `ErmineFixture.rejects`" | tracker/GATE-POLICY.md:60-62; 36c2dcf9 subject |
| WRITTEN-WITH-FIX | 53216547 | 2026-09-09 | S5's first full-run failure was the new TestInterfaceKey flipping process-global properties | "the flip reached `TestInterfaceRoundTrip`'s session and made it fail (940 total, 1 failed)" | tracker/loopmodel/S5-HYGIENE.md:433-434 |

Seen but NOT counted here (a named suite or property caught it; that is the per-suite audit's scope): faa5769e (interleaved equations silently merged, "caught by the Stage-1 pin", LSP-ROADMAP.md:3150); 8f16f913 (LSP symbol tree straddling siblings, "the corpus property first saw it at J3b's landing run (7 straddling pairs)"); 17cdcbd1 (TestDoc import map on the merged tip); 2eee426f (TestRunner GET/HEAD length race at the J3c landing, test-only).

`core/test (full): REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=6`

## 13. The 2.11 back-port test run (sbt 0.13, backport-2.11 / json-encode-2.11)

| class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|
| GATE-DEFECT | 2de40034 (2.11), 84af8a10 (Scala 3) | 2026-09-16 | TestRunner built its request with argonaut `nospaces` (unordered keys), a false failure once Spread made order observable | "The first full `core/test` was **858 with one failure**: `TestRunner.(a)` said \"props differ from the params sent\" and then printed two BYTE-IDENTICAL documents." | json-encode-2.11:tracker/json-stage3/report-P3.md:52; 84af8a10: "Found by the 2.11 port (P3)" |
| REAL-DEFECT | fix commit: not identified (ticketed) | 2026-09-16 | 2.11: Timestamp column does not round-trip through SQLite (INTEGER affinity, text literal, sqlite-jdbc 3.7.2) | "**A Timestamp column does not round-trip through SQLite on this branch.**" | json-encode-2.11:tracker/json-stage3/report-P2.md:55; review-P2.md:124 ("a real DB-layer defect, correctly ticketed") |
| REAL-DEFECT | fix commit: not identified (worked around via SchemaParse.typeExpr; "ticketed not taken") | 2026-09-16 | 2.11 `Session.eval` does not resolve type constructors inside a term (no fixCons) | "`Session.eval(\"[] : List Int\")` infers `forall a. List a`, which is what broke three TestDecode properties." | json-encode-2.11:tracker/json-stage3/report-P1.md:74-75 |
| SELF-DEFECT | 728392d8 (lazy `secure` shadow) | 2026-09-16 | scalacheck 1.11.3 runs property bodies in the static initialiser, so thread-starting properties deadlock | "**On scalacheck 1.11 a property body runs inside the enclosing `object`'s static initialiser, and that deadlocks any property that starts a thread.**" | json-encode-2.11:tracker/json-stage3/report-P2.md:53 |
| SELF-DEFECT | fbd6826a | 2026-09-16 | same deadlock re-hit by the TestRowRefusals port | "it **wedged**: every case timed out at its 180 s deadline, the suite was still running after eleven minutes" | json-encode-2.11:backport/SUBSUME-2.11.md:82-83 |
| SELF-DEFECT (found by review) | fbd6826a | 2026-09-16 | on 1.11.3 a generator failure gives an empty sample, which `Prop.all()` reports as proved | "**An empty sample is therefore reported as `OK, proved property` while asserting nothing at all.**" | json-encode-2.11:backport/SUBSUME-2.11-REVIEW.md:26-35 (F-1) |
| SELF-DEFECT (found by review) | fix commit: not identified ("NOT FIXED here") | 2026-09-16 | `sbt211` in env-2.11.sh silently builds whatever tree the caller is in | "**`sbt211` has the same bug and is SILENT about it** ... `cd \"\"` is a no-op, so it builds whatever tree the caller happens to be in" | json-encode-2.11:backport/SUBSUME-2.11.md:357-359 |
| SELF-DEFECT | 2de40034 (120 -> 300 samples) | 2026-09-16 | (d3) anti-vacuity floor failed 4 of 120 with correct verdicts; correlated per-case java seeds | "Its anti-vacuity floor (at least 10 shapes carrying a relation) failed at **4 of 120** the first time the four suites ran after J2b, while all 120 verdicts were right." | json-encode-2.11:tracker/json-stage3/report-P3.md:46 |
| UNSURE: REAL-DEFECT (the same note says the branch has no loadInSeries, so this may be the test's assumption rather than a 2.11 defect) | not ported (documented decision) | 2026-09-09 | TestInterfaceKey's warm load under loadInSeries deadlocks the 2.11 loader | "its \"warm load under ermine.loadInSeries\" step deadlocks the 2.11 module loader" | backport-2.11:BACKPORT.md:89-92 |

Not counted (known before the run): 85e61b05 "2.11 line still accepts B1: dateDiff sig never back-ported". This is the F3/B1 defect already fixed on scala3-migration.

`2.11 back-port test run: REAL-DEFECT=3 GATE-DEFECT=1 SELF-DEFECT=5 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

## 14. `bitbucket-pipelines.yml` (CI config)

No rows. `git log --all -- bitbucket-pipelines.yml` shows exactly two commits: 4a014e40 (2017-10-19, Dan Doel, "Initial Bitbucket Pipelines configuration") and dc634d3e (2019-11-06). The file is the Atlassian sample: `image: bitbucketpipelines/scala-sbt:scala-2.12`, `sbt test`.

- Nothing in the 2026 commit messages, tracker docs or memory notes records a pipeline run.
- The memory note ermine-push-prep.md says "bitbucket-pipelines.yml is a stale Scala 2.12 sample".
- The only remote now is `origin https://github.com/dmkolobov/ermine-scala-next.git`, and no `.github/` workflow exists on json-encode, scala3-migration, backport-2.11 or json-encode-2.11.
- Whether Bitbucket ever ran it in 2017-2019 cannot be checked from the repository: unverified.

`bitbucket-pipelines: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

## 15. Instruments that may have acted as gates

| instrument | class | fix/commit | date | defect | evidence quote | source |
|---|---|---|---|---|---|---|
| sql-render.sh | REAL-DEFECT | fac46775 | 2026-09-07 (found in E1, 8a6a27a0) | forcing any pivot panicked: `record#` returned a Scala 2.13 MapView | "pivots — **panic** in `Native.Record.scalaRecord#` \| 6" / "### 7.2 `Relation.Pivot.pivot` and `Relation.Predicate.all` panic when forced — a live bug" | tracker/loopmodel/E1-EXAMPLES.md:835, :1112 |
| sql-render.sh | REAL-DEFECT (example corpus, under review) | 0caaba94 | 2026-09-07 | MultiCurrencyPnl's advertised "unrated postings" section always renders zero rows | "**Rendered and run** (`tracker/tools/sql-render.sh`, `probes/TimeRender.e`): the candidate set ... has 21 rows covering **all twelve** `entryId`s" | tracker/loopmodel/E3-REVIEW.md:140-141 |
| sql-render.sh | SELF-DEFECT (found by review) | 8a6a27a0 | 2026-09-07 | name-to-SQL pairing was positional | "`sql-render.sh` — the name↔SQL mapping was positional" | tracker/loopmodel/E1-EXAMPLES.md:1444 (N-7) |
| sigentail-*.py (S1 warn-mode survey) | REAL-DEFECT (purpose-built survey; this was its intended output) | 93c9d1bb | 2026-09-11 | seven shipped stdlib signatures do not entail their bodies' row obligations | "NOT entailed: 12 signatures / 32 wanteds. Seven in the shipped stdlib --" | 16889be4 |
| sigentail-*.py (S1 survey) | UNSURE: REAL-DEFECT (found while explaining pin sig03's outcome during the survey, not by the scripts' output as such) | 75253148 | 2026-09-11 | let-bound signatures silently dropped by rename/Lower.scala since faa5769 (LET-1) | "sig03 explained: the let-bound twin is refused only because rename/Lower.scala DROPS let-bound signatures" | 16889be4 |
| sigentail-entail.py | SELF-DEFECT (found by review) | fix commit: not identified | 2026-09-11 | triage classified shared-choice wanteds as `b`, so five Time/Helpers groups never reached a human | "**Why S1 missed them — a bug in `sigentail-entail.py`, not a judgement call.**" | tracker/loopmodel/SIG-2-REVIEW.md:191 |
| sigcheck.py | SELF-DEFECT | b7dd07cc | 2026-09-11 | the TestSigEntailDiff differential found two bugs in the oracle (closure fixpoint; empty-lhs normalisation) | "### 5.2 What the differential caught (both in the ORACLE, which is now corrected)" | tracker/loopmodel/SIG-3-IMPL.md:231 |

Tallies:
`sql-render: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=1 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`
`sigcheck/sigentail: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`
`keptdef-sweep/splitkey-sweep: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`
`res-guard-bench/splice-audit/corpus-experiments: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`
`lsp-demo: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0`

Notes on the zero rows:
- keptdef-sweep.sh and splitkey-sweep.sh appear only as measurement instruments ("kept-definition mints over a serialized rowTrace (corpus: 156 mints in 27 modules)", 932f22e6).
- res-guard-bench.sh, splice-audit.sh and corpus-experiments.sh were each committed once (cf43dabf) and are named in no tracker .md file.
- lsp-demo.sh records the G3 transcript (aeab94f7, a355b876). No red recorded.

Outside the requested list, recorded because they are the strongest catches in the period:
- the L5 loop-model witness hunt found the makeEmpty self-propagation panic ("The loop model's witness hunt (stage L5) found it on the satisfiable three-constraint system PANIC3", b0c97b99);
- the S5 reviewer's probe found the `.ei` round-trip bug (Q-16, fixed f9266adb);
- the VS Code extension `npm test` load test was written with its fix (331ba605, deactivate() throwing) and later "had been red since 6.6" (aeab94f7).

---

## 2. All tally lines

```
compile: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=1 FLAKE=0
TestLoopTrace: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=3 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
corpus verdicts: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=5 EXPECTED-CHANGE=4 FALSE-ALARM=0 FLAKE=1
Lean: REAL-DEFECT=0 GATE-DEFECT=1 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
repl-smoke: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=1 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
lsp-smoke: REAL-DEFECT=1 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=2 FALSE-ALARM=2 FLAKE=0
looptrace-corpus: REAL-DEFECT=1 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=0 FALSE-ALARM=1 FLAKE=0
trace-ab: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=1 EXPECTED-CHANGE=2 FALSE-ALARM=0 FLAKE=0
ei-diff: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=5 EXPECTED-CHANGE=2 FALSE-ALARM=0 FLAKE=1
g1-validate: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=3 EXPECTED-CHANGE=3 FALSE-ALARM=0 FLAKE=0
perf-bench: REAL-DEFECT=1 GATE-DEFECT=0 SELF-DEFECT=5 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
core/test (full): REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=6
2.11 back-port test run: REAL-DEFECT=3 GATE-DEFECT=1 SELF-DEFECT=5 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
bitbucket-pipelines: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
sql-render: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=1 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
sigcheck/sigentail: REAL-DEFECT=2 GATE-DEFECT=0 SELF-DEFECT=2 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
keptdef-sweep/splitkey-sweep: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
res-guard-bench/splice-audit/corpus-experiments: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
lsp-demo: REAL-DEFECT=0 GATE-DEFECT=0 SELF-DEFECT=0 EXPECTED-CHANGE=0 FALSE-ALARM=0 FLAKE=0
```

UNSURE rows inside the REAL-DEFECT counts:
- corpus 1 of 2 (1411c6c9)
- lsp-smoke 1 of 1 (Q-1)
- looptrace-corpus 1 of 1 (D1-B canonKey)
- g1-validate 1 of 2 (49e63cc7)
- perf-bench 1 of 1 (7.1a)
- 2.11 1 of 3 (TestInterfaceKey deadlock)
- sigentail 1 of 2 (LET-1)

REAL-DEFECT rows that are in-development code, not shipped behaviour:
- g1-validate 6d15c91d (new pipeline behind a flag)
- g1-validate 49e63cc7 (uncommitted change)
- looptrace-corpus 74b49298 (flag default OFF)
- perf-bench fc2ce4a5 (pre-commit)

## 3. Ritual evidence (quotes)

- **The policy itself.** "an audit of the loop-model programme's gates (2026-09-08) found ... the perf bench never moving (machine drift 10.9-13.9 s exceeds any plausible effect), the interface sweep skipping half the corpus" (tracker/GATE-POLICY.md:3-5). The same audit found "every stage running its gates THREE times (implementer, reviewer, orchestrator)" (GATE-POLICY.md:6).
- **User reaction (memory note ermine-gate-policy.md).** "The user (2026-09-08) agreed that the gates had drifted into ritual ... 'especially triple-running lol, why would you do that?'"
- **perf-bench, unmoved and often not run:**
  - "PERF A/B DONE (2026-09-08 00:05): interleaved OFF/ON/OFF/ON = 10.98 / 11.03 / 10.94 / 10.98 s, UNMOVED" (LOOP-MODEL-HANDOFF.md:1054)
  - "perf-bench: DECLINED to run (load average 4.9 > 1.5 while the R3 agent was busy)" (9b5e97b8)
  - "`perf-bench.sh batch -n 3` on a quiet machine, 12.04 s → 12.05 s, unmoved" (S3-SIMPLIFY.md:588)
  - "The interleaved `perf-bench.sh batch -n 3` OFF/ON/OFF/ON — not run" (E11c-SOLVEDET.md:556)
- **g1-validate, not run for weeks, twice:**
  - "It had simply not been run since D3" (2a7efaeb)
  - "it is in no `GATE-POLICY.md` tier, so nobody has run it since" (S5-REVIEW.md:44)
- **TestLoopTrace** is named in 43 commit messages. After L4 there is no recorded product-code red, and it self-skips in worktrees: "a self-skipping property is green precisely when the model is missing" (SUBSUME-STAGE0.md:738).
- **repl-smoke** is named in about 83 commit messages. No golden line was ever rewritten (git log of tracker/repl-tests: insertions only), and no product-caused red was found.
- **lsp-smoke blind spots.** Each of these was found by something other than the smoke while it passed:
  - "every fixture in lsp-tests is a file the resident session has never heard of" (1da2c82b)
  - "No project with a module hierarchy could resolve its own imports in the editor" while "lsp-smoke.sh PASS, 82 checks" (0710e608)
  - "Opening `Relation/Op.e` reported `asOp` as an undefined term" (a7d80e78)
  - "LSP smoke 577 unchanged (its fixtures are all positional)" (8f16f913)
- **Corpus sweeps and trace gates.**
  - "Three times today a zero has meant \"measured nothing\"" (e5158756)
  - "The `boot` and `Wide` trace gates cannot see the deletion" (S5-REVIEW.md Q-12)
  - A seed gate "would not have caught a genuine verdict change of this class" (S4B-REVIEW.md:526)
- **Lean audit.** Every recorded `Audit.lean` / `#print axioms` run found reads 0 non-standard. No red found.
- **compile, a no-op run reported as evidence.** "**§7, \"no new warning\" was a no-op compile.** The implementer's `core/compile` finished in 1 s having compiled nothing." (SIG-1-REVIEW.md:77-78)
- **Worktree classpath trap, five gates.** "from any worktree those five gates silently measure another tree, which is worse than a missing gate" (SIG-1-SURVEY.md:707-708).
- **Commit-message mention counts** (distinct commits since 2026-08-01 whose message matches; approximate regex counts):
  - TestLoopTrace 43
  - repl-smoke 83
  - lsp-smoke 87
  - corpus-run / corpus --batch 30
  - g1-validate 17
  - lake build / Audit 32
  - looptrace-corpus / 18-group 11
  - trace-ab 2
  - ei-diff / interface sweep 12
  - perf-bench / A/B 26
  - core/test 87

## 4. Method and limits

**Commit messages.** `git log --all --since=2026-08-01 --format='@@@COMMIT %h %ad %D%n%B' --date=short` gave 429 commits, dumped to a scratch file. I grepped it for:
- each gate script name;
- catch language: caught, found, went red, exposed, surfaced, regress, stale, broke, flake, timed out;
- the per-gate regexes behind the mention counts.

I read the full message of about 45 commits: 2a7efaeb, 49e63cc7, 53216547, b265bbf5, ebcc14b1, 331ba605, b3d871fc, e5158756, 779060d4, 52f8df40, 14b93738, aeab94f7, 75d1c97c, 6a664bbb, 4aeb4cfc, 6fc77fac, 9b5e97b8, 1c8ff562, b0c97b99, 75253148, 16889be4, edb6434f, 1a6fdc2e, be085509, 21a331a2, 4c18fa5c, 84c2abd0, f9266adb, 7ebcbfa6, 284afe1b, b8f06aec, 6315e322, 6d15c91d, 285d731a, 1b4bf66c, 0b24bb34, 8bca3b75, 3626929a, 932f22e6, c777cbd6, cf43dabf, 4018af56, 360306c7, 59d92f22, 1411c6c9, fc2ce4a5, 84af8a10, d1d92721, 2eee426f, 17cdcbd1, 8f16f913, 3374deaf, f091369a, 0710e608, a7d80e78, 1da2c82b, b7dd07cc, faa5769e, 7e06181b, 74b49298, a7030744, and the 2.11 commits 2de40034, 728392d8, 6743002a, fa30a908, 3f91d030, dad31bc9.

**Per-script history.** `git log --all -- tracker/tools/<script>` for every script named above. `git show --stat` for all commits touching `tracker/repl-tests`.

**Tracker documents** (json-encode checkout). I grepped tracker/*.md, tracker/loopmodel/*.md, tracker/satterm/*.md and tracker/json-stage3/*.md for each gate name combined with failure words. I then read the cited passages of:
- GATE-POLICY.md, S5-REVIEW.md (Q-1..Q-16), S5-HYGIENE.md
- F3-REVIEW.md (N-4), F3-FIXES.md (N-1..N-4)
- S4B-REVIEW.md (H-1), S4-CHANGE.md
- L1-MODEL.md, L2-REVIEW.md, L4-REVIEW.md (F1)
- S2-FIX.md, S2-REVIEW.md (V-4)
- D1-CHANGE.md, LOOP-MODEL-HANDOFF.md (D1-B)
- E1-EXAMPLES.md, E1-REVIEW.md, E3-REVIEW.md, E4-REVIEW.md, E5-REVIEW.md
- E11a-REVIEW.md, E11c-REVIEW.md, E11c-SOLVEDET.md
- A1-REVIEW.md, SIG-1-SURVEY.md, SIG-1-REVIEW.md, SIG-2-REVIEW.md, SIG-3-IMPL.md
- LSP4-7.0-READ.md, LSP4-7.1a-MARK.md, LSP4-7.4-REVIEW.md
- LET-1-FIX.md, LET-1-REVIEW.md
- SUBSUME-STAGE0.md, SUBSUME-STAGE2-REVIEW.md
- report-J3a.md, report-J3e.md, review-J3b.md
- TICKET-row-solver-8abc.md, TICKET-editor-and-solver-followups.md, TICKET-stdlib-findings.md
- KEYED-SPLIT-STAGE2.md, HANDOFF-cumulative-check.md
- LSP-ROADMAP.md (D3 part 2), PERF-ROADMAP.md (G1 repair)

**Back-port branches** (read via `git show <branch>:<path>`):
- backport-2.11: BACKPORT.md
- json-encode-2.11: backport/{REVIEW,SIG-ENTAIL-2.11,SUBSUME-2.11,SUBSUME-2.11-REVIEW,CORRECTIONS}.md and tracker/json-stage3/{report,review}-P{1,2,3}.md

**Memory notes.** ermine-gate-policy.md, ermine-push-prep.md, and the MEMORY.md index.

**CI.** `git log --all -- bitbucket-pipelines.yml`, `git remote -v`, and `git ls-tree` on four branches for `.github/` or other CI files.

**What I could not check.**
- I did not read every one of the ~150 tracker reports end to end. A catch described only deep inside an unread report, and never in a commit message or a grep-matching line, may be missing.
- Tracker docs were read from the json-encode checkout only, plus the named 2.11 files. Docs that exist only on other branches (subsume-*, json-* worktrees) were not searched separately. Their commits were covered by `git log --all`.
- Scratch gate logs outside the repository (`scratch-subsume/`, `/home/dmitry/.claude/jobs/...`, `<scratch>/...`) were not opened. Where a report cites a log, I took the report's statement as written: unverified against the log.
- Several fix SHAs are marked "not identified". A few attributions are marked UNSURE, most often where a review, a probe or a different instrument found the defect and the gate only confirmed it.
- Earlier history (2013-2019) was not searched except for bitbucket-pipelines.yml.
- Nothing was built, run or modified. No git state-changing commands were used.
