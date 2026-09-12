# Review: LSP Stage 4 GATE G4 evidence run (independent reviewer, 2026-09-11)

Brief: `tracker/loopmodel/briefs/brief-LSP4-G4-review.md` (the SLIMMED review decided with the
user).  Under review: `tracker/loopmodel/LSP4-G4-GATE.md` plus the uncommitted deliverables
(`docs/lsp.md`, `editor/vscode/{README.md,package.json}`, `tracker/tools/lsp-demo.{py,sh}`,
`tracker/lsp-tests/G4-demo.txt`) on `scala3-migration` at `7b0b0bd` (the brief's `d8fba0a` plus
the brief commit itself; no source file differs).

I edited nothing but this file and my scratch
`<scratch>/review-g4/`.  Two JVMs of mine ran, one at a time, plus the demo and the extension
load test.  `find . -name '*.ei'` = **143** (the tracked `tracker/g1-baseline` set) after every
step, none newer than my session start; no JVM of mine left running; `git status` unchanged.

---

## 1. THE WAIT, MEASURED INDEPENDENTLY  (my one JVM-heavy task)

**Protocol.**  6.7/G4's, driver `<scratch>/review-g4/wait.py` (a rewrite of `latency2.py`, not a
copy): `didChange` at the pinned site on `Layout/Report.e`, a `textDocument/hover` at (280,2)
sent at a fixed offset from the keystroke, timed send → response.  20 warm-up round trips first;
**no hover traffic before any measured block** (the probe order the implementer found degrading);
the idle-hover control LAST.  n = 12 per offset instead of 5.  One JVM, load waited for and
recorded.

**Load.**  `load_before = 0.85`, `load_after = 0.87` (run 1); `0.62 / 0.83` (run 2) — one-minute
average, both well under the brief's 2.0 bar and under the implementer's 1.18–1.29 window.  The
checks in my run were correspondingly ~7 % faster: `typecheck` **0.46–0.59 s, flat over 57
checks, no trend** (theirs: 0.48–0.69).

### Normal mode (full type checking), `Layout/Report.e`, debounce policy 300 ms every round

| hover sent at | n | median | min | max | > 500 ms | edit→answer median |
|---|---|---|---|---|---|---|
| **+352 ms** (just past the window — the of-record offset) | **12** | **502.4 ms** | 482.3 | 551.2 | **8 of 12** | 856 ms |
| +600 ms (mid-check) | 12 | 277.2 ms | 232.5 | 335.8 | 0 of 12 | 878 ms |
| +100 ms (inside the debounce window) | 12 | **2.17 ms** | 1.64 | 4.02 | 0 of 12 | 104 ms |
| idle server (control) | 10 | 0.28 ms | — | — | — | — |

### Fast mode (`initializationOptions.fastMode: true`), same file, same protocol

Server line: `read 0.04–0.05s, typecheck SKIPPED`; the 7.4 policy drops to the **150 ms FLOOR**
(`waited 150ms (median 67ms of 5 checks, policy 150ms)`), so the offsets are re-aimed at the
shorter window.

| hover sent at | n | median | min | max | > 500 ms |
|---|---|---|---|---|---|
| +151 ms (at the fire moment) | 10 | 2.91 ms | 2.43 | 5.79 | 0 |
| **+171 ms (mid-check — the worst)** | 10 | **50.9 ms** | 48.9 | **55.7** | 0 |
| +201 ms | 10 | 21.2 ms | 17.1 | 25.1 | 0 |
| +302 ms | 10 | 0.59 ms | 0.54 | 0.77 | 0 |
| +352 ms (the normal-mode offset) | 10 | 0.61 ms | 0.54 | 0.69 | 0 |

Fast-mode warm round trip: **0.230 s** (normal: 0.885 s).  Fast-mode cold open 1.06 s (normal
2.36 s).

### My verdict, in one sentence

**544 ms is real but is the high end of the band: with n = 12 on a quieter machine the worst-case
wait is 502 ms median (482–551, 8 of 12 above 500), i.e. it sits ON 7.6's 500 ms trigger rather
than above it — and with fast mode ON it is 56 ms at worst, an order of magnitude under, so the
"fastMode-first" answer the roadmap owed is yes: a user who needs bounded request latency today
gets it from fast mode, not from a thread.**

Three things that support reading the number as a mechanism rather than a sample:

* **The arithmetic model holds exactly.**  Wait ≈ `check.total` + debounce − offset.  My
  `check.total` was ≈ 0.554 s, so 0.554 + 0.300 − 0.352 = **0.502 s** predicted, **0.502 s**
  measured.  The implementer's 0.608 + 0.300 − 0.352 = 0.556 predicted, 0.544 measured.  The gap
  between 502 and 544 is the gap between the two machines' check times (7.4 % — inside the 8 %
  between-JVM drift band 7.0 documented and §0 of the report invokes), not a disagreement.
* **The +600 ms block is the same check seen from further in**: the answer still lands ~0.88 s
  after the keystroke at both offsets, so the wait really is "the remainder of the check", exactly
  as §2.6 says.
* **The +100 ms block confirms the window is idle time**: 2.2 ms, because the check has not
  started; the request is answered and the check runs after.  (2.2 ms, not the 0.28 ms of a truly
  idle server — the hover is served while the debounce timer is live.)

The consequence for Stage 5 is a sentence, not a number: on the largest stdlib module a colliding
request costs *about one check*, which is now ~0.5 s of which **87 % is inference**; a worker
thread makes that interruptible, it does not make it shorter, and turning fast mode on removes it
entirely.  Everything smaller than `Report.e` is already far under the trigger
(`Options.e` ~0.10 s, `Reader.e` ~0.015 s).

---

## 2. FINDINGS

### V-1 (MEDIUM, PARTIALLY REFUTED) — "all five samples above 500 ms" overstates a straddling number

§2.6 and the docs' worst-case row say the wait is **above** the trigger "on every one of these
samples" and that "the parked worker-thread fork's trigger would still fire on this file".  With
n = 12 at load 0.85 the median is **502 ms** and **4 of 12 samples are below 500**; the minimum is
482.  Nothing about the report's *conclusion* changes — it already says "above it, but only just,
and not by enough to be called safe", and 1.09x over becomes 1.00x over — but the decision-grade
sentence the user will read should be **"at the trigger, straddling it"**, not "above it on every
sample".  n = 5 on a machine whose baseline load never fell below 1.1 cannot separate 502 from
544; my n = 12 at load 0.85 can, and the difference is fully explained by the check time (§1).
Recommended fix: one sentence in §2.6 and the docs' worst-case row, quoting both runs.

### V-2 (INFO, NEW EVIDENCE) — the fastMode precondition for 7.6 is answered, and it is decisive

The brief asked for the number the roadmap owed before any thread.  With fast mode ON the check
is read-only (**67 ms median**, `typecheck SKIPPED`), which also pulls the adaptive window down to
its **150 ms floor** — so fast mode shortens *both* terms of the round trip, as `docs/lsp.md` now
claims qualitatively.  Worst-case request wait over 50 samples at five offsets: **55.7 ms**.
That is **9x under** the 500 ms trigger and **~1/10** of the normal-mode worst case.  This belongs
in the gate evidence as the precondition it is: 7.6's thread is not the only way to bound request
latency on this file, and the cheap way already ships.

### V-3 (LOW, NOT REPRODUCED) — the hover-degradation observation did not recur

The report and `docs/lsp.md` record, honestly and as unexplained, that ten hovers between checks
were followed by checks drifting 0.59 → 0.95 s.  My run issued **36 hovers interleaved with 36
checks** across three blocks plus 10 idle hovers, and the server's own line stayed **flat at
0.46–0.59 s over all 57 checks with no trend** — including the last block, after 24 hovers had
already gone through.  That is a third data point and it is on the "machine noise" side.  I would
not remove the observation (it costs nothing and it is honest), but the docs paragraph should say
it did not reproduce in an independent n = 12 run.

### V-4 (LOW, CONFIRMED — a gap in the record, not in the work) — the before side is genuinely `ed42f55`, but the report does not say how it was checked

§2b/Tier 1 say "a fresh build of `ed42f55` in a scratch worktree" and stop there; 7.1a's reviewer
set the precedent of proving it.  I verified it three ways and all three hold:
`git -C <scratch>/g4/wt-g3 log` = **`ed42f55` (detached HEAD)**, working tree clean but for the
regenerated `tracker/repl-classpath.txt`; **a class inventory** — the before build's
`core/target/scala-3.3.8/classes` contains **0** `SurfaceCache*` and **0** `Anchors*` classes
against **10** and **3** at HEAD (2479 vs 2502 class files in all), i.e. Stage 4's two new source
files are absent from it; and the before traces' own file paths are the worktree's.  One sentence
in the report would close this; nothing needs re-running.

### V-5 (INFO, CONFIRMED by my own byte check) — the trace normalisation cannot hide a difference, and `boot` is identical field-for-field

I did not take the summary on trust and I did not need a replay: the recorded traces themselves
answer it.  For the `boot` group, gunzipped:

* `lt-before-norm/boot.tsv.gz` **is** `lt-before/traces/boot.tsv.gz` with the single fixed-string
  substitution `<scratch>/g4/wt-g3` → `<repo>` applied and **nothing else**
  (`raw.replace(WT, REPO) == norm` exactly; 147,083 occurrences replaced, 0 left).
* Against the after side: **174,171 lines, 11,193 differ, every one of them of kind `rsound`, and
  in every one of them the ONLY differing field is index 7** — the wall-clock microseconds
  `trace-ab.py`'s header documents as its one mask.  The S2 counters beside it (fields 4–6) are
  equal in every differing line.  So the mask is exactly as narrow as advertised, and every other
  byte of every record — `sin` bounds, `slbl`, `svar`, `scon`, `ex`, `concr`, `splice`, `detm`,
  `ramb` — is identical.

`trace-ab.py`'s own header confirms the comparison is the full sixteen kinds (the F3 N-1
correction), and `traceab-16.txt` shows 18/18 groups IDENTICAL with `sinmoved=0`, totalling
3,206,083 — the same figure as 7.1a's own pair and the same as both `looptrace` runs' segment
counts.

### V-6 (INFO, CONFIRMED by re-derivation) — the corpus byte-identity is real under a normaliser I wrote myself

I re-did gate 2b from the raw per-file outputs with my own three rules — drop progress-bar frames,
replace `(N.NN seconds)`, substitute the worktree root in the BEFORE side only — and got
**154 files, 0 differing**.  The `verdicts.txt` files are identical after the same path
substitution, and counting the per-file outputs directly gives **69 REJECTED / 85 LOADED / 0
UNKNOWN**, the claimed split.  The report's normalisation list is complete and none of the three
rules can mask a compiler difference (a verdict, a message, a position, a type would all survive
all three).

### V-7 (INFO, CONFIRMED and stronger than claimed) — the interface sweep

The report says "0 of 268 interfaces differ, 3,481 bindings all `identical`" via `ei-classify.py`.
I compared the two snapshot directories **byte for byte**: 268 files each, 0 only-on-one-side,
**0 differing bytes** — so the classification never had to make a judgement call.  The dumps carry
real content (1.4 MB; the header line names the full flag set), and the binding count is exactly
**3,481**.

### V-8 (LOW, RECORD) — the roadmap's Baselines line still says 1026

`tracker/LSP-ROADMAP.md` § Baselines reads "`sbt -batch core/test`: 1026/1026 after Stage 4 item
7.4"; the stage's count is **1028** (7.5's two `TestRenamer` properties, and the report's
arithmetic for that is right).  I am forbidden to touch the roadmap; the sign-off commit should
update it, together with the G4 evidence.

### V-9 (INFO, CONFIRMED) — the demo reproduces

One run of `tracker/tools/lsp-demo.sh` in my scratch: **313 lines, exactly matching
`tracker/lsp-tests/G4-demo.txt` under a timing-only normalisation** (`\d+(\.\d+)? ?(ms|s)` → a
placeholder) — `diff` empty.  Every Stage-4 behaviour the brief lists is in MY run, not merely in
the committed transcript: `reused 97 of 154 … surface 528 of 529` on a body keystroke;
**`reused 115 of 154`, `surface 529 of 529`** on the top-of-file insertion; the burst —
`didChange` ×5 40 ms apart, **one** `check:` line, `waited 150ms … policy 150ms` printed beside
Report.e's `waited 300ms … policy 300ms`; `Tab.e` diagnostics at **24:6** and 19:1 with hover,
definition and `prepareRename` all answering; and the boot's `positions:` mapping line followed by
`definition` on `&&` landing in **`core/src/main/resources/modules/Bool.e 7:0-7:2`** with the three
printed assertions.  The largest timing gap between the two runs (16246 ms vs my 91 ms on one
`publishDiagnostics`) is PHASE B's 60+ load, not a behaviour difference.

### V-10 (INFO, CONFIRMED) — the extension

`npm run test:load` → **PASS**, all nine steps, including the LIVE handshake against the real
`bin/ermine-lsp` (`Ermine session ready: 129 modules in 11.8s`, 9 providers registered) and the
fast-mode toggle.  **No JVM leaked** (`pgrep` clean afterwards).  `editor/vscode/` holds
`ermine-lang-0.1.2.vsix` and no 0.1.1; `package.json` is `0.1.2`; the `markdownDescription` for
`ermine.fastMode` carries the new split.  README's "Three things that will surprise you" is still
exactly three (cold first check; edits that check cold; `case`/`do`/lambda binders), with the two
fixed ones moved into a new "Fixed in 0.1.2" section rather than deleted — the honest form.

### V-11 (INFO) — the record against its sources

Every row of the docs' latency table matches PHASE A (0.93/0.95 vs 0.925/0.948 s and 22 vs 21.5 ms
are roundings, stated as such by the table's own precision).  The stale-number grep
(`1.69 1.86 0.86 0.84 1.47 480 494 510`) is **clean**, with one deliberate historical `0.84`
("*before* the surface cache the read was 0.84 s of it") which is correct and labelled.  The G4
table's per-item A/B figures are quoted from the right reviewer of record and are verbatim
correct: 7.1b review (`1.691 → 0.896 s` round trip, `0.8375 → 0.0500 s` read, −788 ms), 7.2 review
(`1.822 → 1.828 s`, +6 ms / +0.3 %, implementer −1.5 ms), 7.4 review (`0.941 → 0.956 s`, +15 ms /
+1.6 %; small file `0.3204 → 0.1719 s`, −149 ms / −46.4 %; `List.e` −146 ms; `Options.e` −111 ms),
7.1a review (pooled `+0.065 s` mean / `+0.040 s` median; editor read "+20 to +48 ms pooled, +5 to
+90 ms per pair, control 0, 5 of 5 positive, sign test p = 0.03").  (3) matches 7.1b's review
table (2,613 steps, 54,274/19,374, seed 71, plus 913 and 20260911); (4) matches 7.2's review
(115 of 154, residue 39 in three classes); (6) matches 7.1b's 1.63 MB/document and 3.44 MB for
ten.  "REVERTED items: NONE" is true — no Stage-4 adoption was withdrawn, and the report's
parenthetical about 7.1a's two planted bugs is the right disclosure.  The not-satisfied list is
complete against what I can see: 7.3 handed off, 7.6 parked with the wait figure, the 6.2 fork,
1a's partial attribution factors, E12, the open E5/E6/E7/E10(1-3) with E8/E9/E10(5) closed, the
un-exposed `debounce` setting, and the unexplained hover observation.  **Tier 2 read, not re-run**:
run 1 `Failed: Total 1028, Failed 1` with the single red being `TestInterfaceRoundTrip`
("Falsified after 0 passed tests"), run 2 `Passed: Total 1028, Failed 0, Errors 0` — exactly the
E12 rule in `tracker/GATE-POLICY.md` (ONE re-run for exactly that property), E13 silent, no third
run.

---

## 3. THE ROADMAP'S GATE G4, LINE BY LINE

GREEN list:

| G4 line | ✓/✗ | where I verified it |
|---|---|---|
| Tier 0 `core/compile core/copyResources` | ✓ | `<scratch>/g4/g0-compile.log`: success, 46 s, 479-warning build |
| `TestLoopTrace` 720/720 | ✓ | `g1-looptrace.log`: 3 properties passed, `Passed: Total 3` |
| `corpus-run.sh --batch` 85/69/0 over 154 | ✓ | re-derived by me from `corpus-after/*.e.out`: 69 rejected of 154 |
| `repl-smoke.sh` 8 groups | ✓ | `g4-repl.log` (8 groups / 66 checks), `git status tracker/repl-tests` empty |
| `lsp-smoke.sh` at its grown count | ✓ | `g5-lspsmoke.log`: `PASS lsp (542 checks)`; roadmap Baselines says 542 |
| seven targeted suites on TolerantCheck/Lower/Renamer/Definitions | ✓ | inside Tier 2 run 2 (1028 passed) |
| Tier 1: `looptrace-corpus.sh` + `trace-ab.py`, both builds | ✓ | 18/18 rc 0 both sides, 3,206,083 segments IDENTICAL, `sinmoved=0`; **method verified byte-wise by me on `boot`** (V-5) |
| Tier 1: `ei-diff.sh --batch` in series both sides + `ei-classify.py` | ✓ | **268/268 byte-identical, verified by me directly** (V-7) |
| Tier 1: `g1-validate.sh` | ✓ | `g6-g1validate.log`: 9/9, `no drift from tracker/g1-baseline` |
| Tier 2 full `core/test` ALONE, green | ✓ | 1028/1028 on the one allowed re-run; run 1's single red is E12 by name (V-11) |
| REPL goldens + `TestReplDifferential` byte-unchanged | ✓ | `git status tracker/repl-tests` empty; the suite is inside Tier 2 |
| `TestTolerantRead` 180-file agreement green | ✓ | inside Tier 2 run 2 |
| boot 129 modules | ✓ | `g7-boot.log`, and again live in my own demo and extension runs |
| no `.ei` in `tracker/lsp-tests` | ✓ | 0 there; 143 repo-wide after all my runs, none new |

NUMBERS RECORDED list:

| # | ✓/✗ | where I verified it |
|---|---|---|
| (1) 7.0's phase table before and after | ✓ | PHASE A §G4.1, both files, reconciled to 99.94 %; the `extents` double-scan caveat is stated precisely and matches 7.1b R-4 |
| (1a) over/under-attribution factor per row | **PARTIAL, declared** | §1a and "not satisfied" item 4: not re-derived against the after tree, and the reason (a JFR survey of the pre-stage tree) is sound.  Accept as declared, do not mark green |
| (2) interleaved A/B per adoption item, pooled Δ vs the noise floors | ✓ | quoted verbatim from 7.1b / 7.2 / 7.4 / 7.1a reviewer reports; I opened each (V-11) |
| (3) corpus differential for 7.1b with generator and seed | ✓ | 7.1b review §, seed 71 + two fresh seeds |
| (4) reuse counts for 7.2 (0/154 → N) | ✓ | 115 of 154, and printed live in MY demo run (V-9) |
| (5) worst-case request wait re-measured next to 6.7's | ✓ (with V-1) | independently re-measured at n = 12 (§1): 502 ms median, 1.45 s → ~0.5 s stands; the "above 500 on every sample" phrasing needs softening |
| (6) heap figure for 7.1b retention | ✓ | 1.63 MB/document, 3.44 MB for ten — 7.1b review |
| (7) every REVERTED item | ✓ | none, and the one near-miss (7.1a's planted bugs) is disclosed |

Also in the gate line: "STOP the loop and summarize for sign-off before any Stage 5 planning" — the
report's OUTCOME does exactly that and plans nothing.

---

## 4. VERDICT

**FIX-THEN-ADVANCE.**  The evidence holds everywhere I checked it, and in the three places I
re-derived it from raw artifacts rather than reading a summary (the corpus, the interfaces, the
`boot` trace) it came back stronger than the report claimed.  One number needs its sentence
corrected before the gate is recorded, and two lines should be added:

1. **V-1** — soften §2.6 and the docs' worst-case row from "above the 500 ms trigger on all five
   samples" to the straddle the larger sample shows: **502 ms median (n = 12, 482–551, 8 of 12
   above 500) at load 0.85 beside 544 ms (n = 5) at load 1.18 — the worst case now sits ON the
   trigger**, the difference between the two runs being the two machines' check times.
2. **V-2** — add the fast-mode precondition to §2.6 and to the "not satisfied" item on 7.6:
   **with fast mode ON the worst-case wait is 56 ms (n = 50 over five offsets), because the check
   is read-only at 67 ms and the window drops to its 150 ms floor.**  That is the answer the
   roadmap owed before any thread, and it changes the shape of the Stage 5 question.
3. **V-4** — one sentence recording how the before side was proved to be `ed42f55` (the class
   inventory in V-5/V-4 above is sufficient and costs nothing to quote).

V-3 (a docs sentence) and V-8 (the roadmap's 1026 → 1028) are for the sign-off commit.  None of
these needs a JVM.  With them, the gate is evidence.

### For whoever cleans up

`<scratch>/g4/wt-g3` is still a registered git worktree (`git worktree list` shows it); remove it
with `git worktree remove --force` at sign-off.  My own scratch is `<scratch>/review-g4/`
(`wait.py`, `run.sh`, `norm.py`, `m1.out`/`m1-lsp.log` normal mode, `m2.out`/`m2-lsp.log` fast
mode, `demo.txt`/`demo.log`).
