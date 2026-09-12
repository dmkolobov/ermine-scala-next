# LSP Stage 4 — GATE G4 evidence

Branch `scala3-migration`, tree at `d8fba0a` (clean, `git status` empty), JDK
21.0.12.1+1, host dmitry-Z370P-D3, max heap 3984 MB.  Measurement only: no source
change, no commit, no doc edit in this phase.

PHASE A (the measurements that need a quiet machine) ran first, in one sitting, on a
machine with nothing else of mine on it.  PHASE B (the demo, the extension, the docs
and the full gate) ran after the orchestrator resumed the run, alongside the user's
own sbt in a separate worktree — no timing was taken in PHASE B, and every PHASE-B
gate is a byte-identity or pass/fail check that does not care about load.

---

# PHASE A — measurements (machine quiet)

## 0. Protocol, and the one caveat about "quiet"

Every run: ONE JVM on the machine, nothing else of mine running, load taken from
`/proc/loadavg` immediately before the client started and again after it exited,
`.ei` counted by `find` afterwards.  The driver is the client of record,
`tracker/tools/perf-client.py`, invoked the way `tracker/tools/perf-bench.sh editor`
invokes it (scratch driver `<scratch>/g4/run.sh`, a copy of 7.4's `ab.sh` with one
side); the 7.0 phase harvest is 7.0's own `harvest.py`; the request-latency probe is
6.7's `latency.py` (`<scratch>/g4/latency2.py`, two changes named in §2.6).

**THE CAVEAT, stated up front.**  The machine's own baseline 1-minute load sat at
**1.18–1.29** for the whole window (it never went below 1.1).  Every measured run
therefore started **under the 1.3 bar and was waited for**, but none started as
quiet as 7.0's runs (load 0.88–0.97).  The calibration control is `checkWith`, the
one phase in the table Stage 4 never touched:

| `checkWith` (Report.e, warm, median) | 7.0 run C | 7.0 run B | **G4** |
|---|---|---|---|
| ms | 492.4 | 496.4 | **528.8** |

**+7.4 % on the untouched phase**, which sits inside the **8 % between-JVM drift band
7.0 measured and documented** (§2 of LSP4-7.0-READ.md: run A vs run B, 8 % on every
compute phase, while inside one JVM the same quantities agree to 0.3 %).  So: read-
side comparisons below (−90 % and more) are far outside that band and safe;
anything in this report smaller than ~80 ms is NOT a verdict, exactly as 7.0's rule
says.  Nothing in PHASE A is an A/B — the per-item A/Bs already exist in the item
reports and are quoted in PHASE B.

`.ei` after PHASE A: **0 new** (`find . -name '*.ei' -newermt <window start>` = 0;
the 143 tracked golden files untouched), no JVM left behind, `git status` clean.

---

## G4.1 — THE PHASE TABLE, AFTER THE STAGE

### 1.1 `Layout/Report.e` (1757 lines, 77,385 bytes) — the big file

`-Dermine.lsp.phases=true`, `perf-client.py --rounds 70` on the pinned edit site
(line 281, `emptyReport`'s body, one digit), **NO debounce pin** (so the window is
what the 7.4 policy sets; harvested by the client from the server's own
`debounce:` line as **0.300 s every round**).  71 `phases:` lines = the `didOpen`
plus 70 rounds; rows **21..70 are the 50 measured reps** after 20 warm-ups, which
is 7.0's protocol exactly.  **load_before = 1.29**, load_after 1.88.  Round trip
**0.925 s** median, reused **97 of 154** components and **528 of 529** statements
every round, cold open 2.568 s, boot 13.73 s.

All figures in **milliseconds**.  7.0's column is its run C, the run of record.

| # | phase | **7.0 (BEFORE)** | **G4 (AFTER)** | min | p10 | p90 | max | share of check | Δ |
|---|---|---|---|---|---|---|---|---|---|
| — | `rpc.frame` (79,628 B) | 0.081 | **0.079** | 0.056 | 0.058 | 0.115 | 0.136 | 0.013 % | — |
| — | `rpc.log` | 0.035 | **0.036** | 0.019 | 0.023 | 0.046 | 0.081 | 0.006 % | — |
| — | `rpc.json` | 0.307 | **0.318** | 0.296 | 0.306 | 0.523 | 0.556 | 0.05 % | — |
| h | `envcopy` | 0.009 | **0.008** | 0.007 | 0.007 | 0.010 | 0.013 | 0.001 % | — |
| a | `header` (`ModuleParsers.moduleHeader`) | 8.053 | **8.819** | 8.277 | 8.382 | 12.402 | 16.798 | **1.45 %** | +0.77 |
| h | `scrub` | 2.058 | **2.131** | 2.023 | 2.033 | 2.603 | 4.251 | 0.35 % | — |
| — | `imports` | 0.039 | **0.042** | 0.033 | 0.037 | 0.052 | 0.075 | 0.007 % | — |
| **c** | **`parse`** (now `SurfaceParsers.moduleCached`) | **829.841** | **36.935** | 32.015 | 33.686 | 41.572 | 54.019 | **6.08 %** | **−792.9 (−95.5 %)** |
| — | `syntax` | 0.036 | **0.018** | 0.017 | 0.017 | 0.021 | 0.039 | 0.003 % | — |
| e | `rename` | 5.043 | **4.454** | 4.062 | 4.151 | 5.024 | 7.164 | 0.73 % | −0.59 |
| f | `reassoc` | 0.677 | **0.489** | 0.421 | 0.438 | 0.668 | 0.849 | 0.08 % | −0.19 |
| g | `lowerctx` | 3.993 | **3.756** | 3.285 | 3.430 | 4.252 | 8.073 | 0.62 % | −0.24 |
| g | `lower` (`assemble`) | 5.076 | **4.998** | 4.394 | 4.635 | 5.972 | 6.877 | 0.82 % | −0.08 |
| | **`read.total`** | **845.371** | **51.594** | 45.661 | 47.382 | 55.612 | 70.527 | **8.49 %** | **−793.8 (−93.9 %)** |
| — | `notes.pre` | 0.080 | **0.115** | 0.075 | 0.079 | 0.135 | 0.167 | 0.019 % | — |
| b | `extents.scan` (ONE of the two, see note) | 0.806 | **0.784** | 0.772 | 0.775 | 0.863 | 1.528 | 0.13 % | — |
| b | `extents.offsets` | 1.551 | **1.554** | 1.532 | 1.538 | 2.302 | 3.472 | 0.26 % | — |
| h | `keys.total` | 3.272 | **3.325** | 3.165 | 3.224 | 4.266 | 5.777 | 0.55 % | — |
| **i** | **`checkWith` (the typecheck)** | 492.377 | **528.768** | 472.330 | 490.631 | 567.531 | 673.369 | **87.03 %** | +36.4 (drift, §0) |
| — | `notes.post` | 0.048 | **0.038** | 0.033 | 0.034 | 0.056 | 0.088 | 0.006 % | — |
| h | ` └ index.symbols` (inside `index`) | 0.417 | **0.457** | 0.378 | 0.393 | 0.699 | 0.928 | 0.08 % | — |
| h | `index` (`Definitions.index`) | 9.953 | **10.680** | 9.512 | 9.587 | 13.392 | 16.552 | 1.76 % | +0.73 |
| | **`check.total`** | **1362.990** | **607.549** | 553.360 | 567.299 | 642.755 | 762.939 | 100 % | **−755.4 (−55.4 %)** |

**What the table says in one line.**  The read is no longer the check: `parse`
went from **60.9 % of the check to 6.1 %**, `read.total` from **62.0 % to 8.5 %**,
and inference — which Stage 3 already said was not the bottleneck — is now **87 %
of everything the check does**.  The whole-file parse that G4 was written around,
**844 ms, is 37 ms**.

**THE `extents` ROW, and the 7.1b R-4 note (this is the one place the brief's
expectation and the code differ, so it is stated precisely).**  `StatementExtents.scan`
runs **twice per check on a clean file** — once in `SurfaceParsers.moduleCached`
and once in `TolerantCheck.keys` — exactly as 7.1b R-4 recorded.  But only the
`TolerantCheck` call is *timed*: the `Phases.add("extents.scan", …)` pair is at
`TolerantCheck.scala:238-239` and there is no timer at `SurfaceParsers.scala:1123`.
So the row above is **one scan (0.78 ms), not the sum of two**; the second scan is
inside the **`parse` row** (it is called within the `parse` timer at
`NewPipeline.scala:133`), i.e. ~0.78 ms of the 36.9 ms parse.  The two other
`scan` call sites — `NewPipeline.scala:160` and `Resident.scala:444` — are on the
ERROR path only (`errs.nonEmpty` / `broken.nonEmpty`) and do not run on Report.e,
which checks clean.  The duplicate is therefore **~1.6 ms of the 51.6 ms read
(3.0 %)**, still the follow-on 7.1b named, and it is visible here only as part of
`parse`.  No change was made to fix it in PHASE A (measurement only).

**RECONCILIATION** (computed per round, then the median — medians do not add):

| | 7.0 run C | **G4** |
|---|---|---|
| read parts vs `read.total` | +0.035 ms (+0.004 %) | **+0.068 ms (+0.132 %)** |
| top-level parts vs `check.total` | +0.359 ms (+0.027 %) | **+0.386 ms (+0.061 %)** |

The table accounts for **99.94 %** of the check.  The absolute unaccounted amount
is unchanged (0.36 → 0.39 ms — the same named code between the timed blocks in
`Resident.checkFile`); its PERCENTAGE grew only because the denominator fell by
more than half.  Sum of medians: read parts 50.651 vs `read.total` 51.594; top
level 605.518 vs `check.total` 607.549.

### 1.2 `Control/Monad/Reader.e` (44 lines, 1,148 B) — the small file

Same protocol, same 70 rounds / rows 21..70, `--mode space` on line 43,
`--allow-no-reuse` (a 44-line module has ONE inference component and the edit
invalidates it: `reused 0 of 1` every round, as 7.0 found).  **load_before = 1.27**,
load_after 2.06.  Round trip **0.170 s**, harvested window **0.150 s every round**
(`debounce: Reader.e waited 150ms (median 13-16ms of 5 checks, policy 150ms)`),
cold open 0.156 s, boot 13.50 s.

| phase | **7.0 (BEFORE)** | **G4 (AFTER)** | min | p10 | p90 | max |
|---|---|---|---|---|---|---|
| `rpc.frame` | 0.012 | **0.013** | 0.010 | 0.011 | 0.017 | 0.026 |
| `rpc.json` | 0.062 | **0.060** | 0.027 | 0.029 | 0.104 | 0.162 |
| `envcopy` | 0.008 | **0.007** | 0.007 | 0.007 | 0.009 | 0.023 |
| `header` | 0.710 | **0.802** | 0.660 | 0.680 | 1.029 | 2.116 |
| `scrub` | 0.002 | **0.002** | 0.001 | 0.001 | 0.002 | 0.006 |
| `imports` | 0.018 | **0.017** | 0.015 | 0.015 | 0.021 | 0.033 |
| **`parse`** | **19.151** | **2.652** | 2.298 | 2.383 | 3.744 | 6.222 |
| `syntax` | — | **0.005** | 0.004 | 0.004 | 0.006 | 0.015 |
| `rename` | 2.639 | **2.558** | 2.386 | 2.425 | 3.320 | 5.208 |
| `reassoc` | 0.173 | **0.171** | 0.150 | 0.153 | 0.245 | 0.337 |
| `lowerctx` | 0.115 | **0.102** | 0.097 | 0.097 | 0.146 | 0.159 |
| `lower` | 0.326 | **0.322** | 0.250 | 0.271 | 0.434 | 0.501 |
| **`read.total`** | **22.695** | **6.152** | 5.354 | 5.528 | 8.030 | 10.397 |
| `extents.scan` + `.offsets` | 0.098 | **0.094** (0.061 + 0.033) | — | — | — | — |
| `keys.total` | 0.282 | **0.285** | 0.202 | 0.236 | 0.481 | 0.658 |
| **`checkWith`** | **6.065** | **6.550** | 5.743 | 5.887 | 9.109 | 10.810 |
| `index` | 0.636 | **0.620** | 0.443 | 0.486 | 0.834 | 1.419 |
| **`check.total`** | **30.670** | **15.448** | 13.088 | 13.500 | 17.992 | 23.122 |

Per-round reconciliation: read **+0.041 ms (+0.737 %)**, check **+0.257 ms
(+1.617 %)** (7.0: +0.098 % and +0.806 % — same absolutes, halved denominator).

Three readings.  (1) **The small file's parse is 7.2x cheaper** (19.2 → 2.7 ms):
one statement re-parses, the rest splice.  (2) **`rename` is now the biggest read
phase on a small file** (2.56 ms of 6.15 ms, 42 %) — it re-runs whole, and 7.0's
table already showed it under-attributed by the JFR survey; it is the obvious next
read target on small files, and it is 0.7 % of the check on the big one.  (3) **The
debounce is no longer 90 % of the small-file round trip**: 0.333 s → **0.170 s**,
of which 0.150 s is the 7.4 floor and 15 ms is work.  7.0 §3's "Decision (e) whole
case" is closed by 7.4 and the number is here.

---

## G4.2 — THE LATENCY TABLE, RE-MEASURED

One JVM per row-group, load recorded per run, `Layout/Report.e` unless stated.

| row | **G4 figure** | method, and the load it was taken at |
|---|---|---|
| session boot, 129 modules | **13.6 s** median of 7 (12.75 / 13.50 / 13.53 / 13.61 / 13.73 / 14.14 / 16.39) | every run in this phase reports its own boot; the 16.39 s outlier is the first probe run, whose load rose during boot |
| **keystroke → diagnostics, UNPINNED** (what a user gets) | **0.925 s** = 0.050 read + 0.540 typecheck + **0.300 debounce** + 0.025 residual; spread 0.855–1.069 | `perf-client.py --rounds 70`, median of rounds 2..70, no `--pin-debounce`; the server's own `debounce:` line says **300 ms every round** (policy: `clamp(150, median check 592–602 ms, 300)` → the ceiling), reused 97/154, surface 528/529. **load_before 1.29** |
| **keystroke → diagnostics, PINNED at 300** (roadmap-comparable) | **0.948 s** = 0.050 + 0.550 + 0.300 + 0.031; spread 0.881–1.132 | `tracker/tools/perf-bench.sh editor -k 15` (which pins `--pin-debounce 300`), median of rounds 2..15, `PERF_MAX_LOAD=1.3`, **load_before 1.24**, load_after 1.94; full `PERFBENCH` line in `<scratch>/g4/perfbench/`. The two numbers agree because on this file the adaptive window IS 300 — the pin changes nothing here, and that is the point of the pair |
| keystroke → diagnostics, **small** file | **0.170 s** = 0.010 read + 0.010 typecheck + **0.150 debounce** + 0.000 | `Control/Monad/Reader.e` (44 lines), `--mode space` line 43, 70 rounds, unpinned; window harvested at **150 ms** (the floor) every round. **load_before 1.27** |
| keystroke → diagnostics, **mid-sized** file | **0.415 s** = 0.020 read + 0.080 typecheck + **0.218 debounce** (median of the harvested per-round windows) + 0.087 residual; spread 0.347–0.517 | `Layout/Report/Keyed/Options.e` (438 lines), line 109, `--mode space`, 15 rounds, unpinned, phases OFF. The window is INSIDE the band and tracks the check: 300 → 258 → 235 → 212 → 192 → … → **173 ms** as the median check time settles. `reused 0 of 0` — this module has no multi-binding group, as 7.4 recorded. **load_before 1.19** |
| **THE WORST SITE** — a keystroke inside Report.e's 10.7 KB `private` block | **1.580 s** = 0.170 read + 1.070 typecheck + 0.300 debounce + 0.030; spread 1.486–1.741 | `perf-client.py --rounds 15 --line 1592 --anchor 'toEither#' --mode space`, phases ON, unpinned. **load_before 1.28**. Phase detail for this site: `parse` **153.7 ms**, `read.total` **173.2 ms**, `checkWith` **1067.3 ms**, `check.total` **1277.3 ms** |
| the cold open of Report.e | **2.47 s** median of 5 (2.374 / 2.381 / 2.469 / 2.568 / 2.995) | each run's round 0 (`didOpen` → `publishDiagnostics`); server-side first check `read 1.07–1.36 s, typecheck 1.30–1.54 s`, `surface 0 of 529` — a first open has no cache and pays the whole-file parse |
| **worst-case request wait DURING a check** | **544 ms** median (n=5: 510 / 529 / 544 / 563 / 616); the answer lands **896 ms** after the keystroke | §2.6 below |
| a hover on an IDLE server (the control) | **0.31 ms** median of 10 (0.3–0.4) | same run, after the worst-case block |
| completion | **1.7 ms server-side** warm (log line, 11.0 → 4.1 → 2.8 → 2.1 → … → 1.6 ms), **6.1 ms client round trip** (median of 10, spread 5.1–21.9) | prefix `f` at line 1504: **97 items of 1332 in scope, `isIncomplete=false`** — identical counts to G3 |
| `workspace/symbol` | **105.9 ms** first query (18 hits), **1.29 ms** warm median of 10 | the first query builds the 2157-name session list; the first-query figure is the noisiest row in the table (G3 got 60.7 ms, the contaminated probe run got 160.6 ms) — it is one `File.isFile` sweep of the module tree and moves with the page cache |
| `documentSymbol` | **21.5 ms** client round trip, median of 10 (18.7–34.4) | **398 top-level, 511 total** — identical counts to G3 |
| code action | **40.5 ms** first request after a check, **0.68–0.73 ms** after | memoised per document version |
| index build | **59.3 ms** cold, **10.6 ms** warm median (9.6–15.4 over 26 samples) | the server's own `index: Report.e 7980 occurrences, 511 symbols in X ms` line — occurrence and symbol counts identical to G3 |

### 2.6 The worst-case wait, and the 500 ms question

**Protocol (6.7's, unchanged where it matters).**  `didChange` on Report.e, then a
`textDocument/hover` sent at **+352 ms** — just past the 300 ms window, so the check
is already running on the dispatch thread — timed send → response; the wait is what
a user's hover costs when it collides with the check.  Two changes from 6.7's
script, both named: **(a)** 20 warm-up round trips before the block instead of 3
(perf-client's protocol; with 3 the check had not settled), and **(b)** the idle-
hover control moved to AFTER the worst-case block instead of before.

**(b) is not cosmetic and is reported as a finding.**  In the first run (6.7's
order, load_before 1.22) the ten idle hovers preceded the worst-case block and the
server's own check line then degraded monotonically — `typecheck` 0.59 → 0.53 →
0.74 → 0.86 → 0.81 → 0.84 → 0.95 s — giving a worst-case wait of **924 ms** (n=3:
869 / 924 / 939).  In the re-ordered run the same check line stayed flat across all
27 checks (0.48–0.69 s, no trend), and the 70-round `big70` run is flat over 70
checks (0.50–0.56 s), so the degradation is not a session leak: it follows the
hover traffic. Whether that is hover-induced GC pressure or machine noise is NOT
settled here — it is a ticket-shaped observation for the reviewer, and the
of-record number below is the one taken with the checks at their steady state.

**THE NUMBER, beside G3's:**

| | G3 (6.7) | **G4** |
|---|---|---|
| the check it waits behind | 0.86 s read + 0.50 typecheck (`check.total` 1.36 s) | **0.05 s read + 0.53 typecheck (`check.total` 0.61 s)** |
| hover sent at | +352 ms | **+352 ms** |
| **worst-case request wait** | **1.45 s** (median of 3: 1450/1477/1468) | **0.544 s** (median of 5: 510/529/544/563/616) |
| answer lands, after the keystroke | 1.82 s | **0.896 s** |
| the same hover on an idle server | 0.61 ms | **0.31 ms** |
| busy / idle ratio | ~2400x | **~1750x** |
| load_before | 1.20 | **1.18** |

**−0.91 s, a 2.7x cut, with no thread and no new code on that path** — it is the
read's 793 ms falling out of the check the request is queued behind, exactly as
7.0's arithmetic predicted (one check minus the 352 ms already elapsed: 0.61 s
`check.total` + 0.30 debounce − 0.352 = 0.55 s predicted, **0.544 s measured**).

**WHICH SIDE OF 7.6's 500 ms TRIGGER IT LANDS.**  **Above it, but only just, and
not by enough to be called safe.**  The median is **544 ms**, and **all five
samples (510–616 ms) are above 500 ms**; the parked worker-thread fork's trigger
would still fire on this file, on every one of these samples.  What changed is the
margin: G3 was 2.9x over the trigger, G4 sits ON it (1.09x here, 1.00x on the reviewer's n=12 run) — the worst case is now
of the same order as the trigger rather than three times it, and on anything
smaller than Report.e (Options.e's check is ~0.10 s, Reader.e's ~0.015 s) it is far
under.  The honest statement for the gate is: **Stage 4 did not take the worst case
below 500 ms on the largest stdlib module; it took it from 1.45 s to 0.54 s, and
the residual is now ~87 % inference** (`checkWith` 529 ms of a 608 ms check), which
is not a read problem and not something 7.6's thread would make faster — it would
only make it interruptible.

### 2.7 The worst site is worst on BOTH axes — the one number that is not obviously good

`1.580 s` for a keystroke inside the 10.7 KB `private` block deserves its own line
because the client's counters say **`reused 0 of 154` components**, not 97 of 154.
That is not a defect and it is not new: `private` is in `TolerantCheck.ScopeWords`
(TolerantCheck.scala:177-180), so the block's TEXT is part of the per-uri SCOPE
key, and any edit inside it drops the whole inference cache — "the answer 5.5
already gives for a `private` block", in the code's own words (TolerantCheck.scala:256).
So this site pays the p99 parse (7.1b measured 126 ms in process; 154 ms here
through the client) AND a full cold typecheck (1.07 s). It is the same family as
7.2's documented residual (edits inside operator / backtick / `_` / `'` definitions
check cold) and belongs in docs/lsp.md beside it in PHASE B. For scale: it is
1.58 s against the **1.69 s** every keystroke anywhere in this file cost at G3.

---

## Scratch, for the reviewer

`<scratch>/g4/`: `run.sh` (the single-run driver, load-guarded), `harvest.py`
(7.0's), `latency.py` (6.7's, verbatim) and `latency2.py` (the two changes in §2.6);
`big70.{log,table,txt,json}`, `small70.*`, `opt15.*`, `worst15.*`, `perfbench/`,
`m2-latency.log` (6.7 order), `m3-latency2.log` (of record), `latency2-lsp.log`.

---

# PHASE B — the demo, the extension, the docs, the full gate

Other load on the machine throughout (the user's sbt in a separate worktree; the
1-minute average reached 60+ at one point).  **No timing was taken in PHASE B.**
One JVM of mine at a time, always; `.ei` counted by `find` after every step.


## G4.3 — THE DEMO TRANSCRIPT

`tracker/lsp-tests/G4-demo.txt`, **313 lines**, regenerated by
`tracker/tools/lsp-demo.sh > tracker/lsp-tests/G4-demo.txt`.  Steps 1–11 are the G3
demo unchanged; **step 12 is new and is the Stage-4 section**; shutdown moved to 13.
`G3-demo.txt` is left in place as the Stage-3 artifact.

Step 12 is the only part of the script that reads the SERVER'S OWN LOG (the file
named by `-Dermine.lsp.log`), because what Stage 4 changed — how much of the file is
re-parsed, how much inference is reused, how long the quiet window is — is reported
there and nowhere in the protocol.  A small `LogTail` class quotes the new
`check:` / `debounce:` / `positions:` lines verbatim after each step.

| the brief asked for | what the transcript shows |
|---|---|
| an edit on Report.e with the `check:` line, the reuse count and the read time | **(a)** the cold open of the real 1757-line `Layout/Report.e` — `check: … read 0.89s, typecheck 1.32s (reused 0 of 154 components), surface 0 of 529 statements` — and **(b)** one keystroke at the pinned body site: `read 0.07s, … reused 97 of 154 …, surface 528 of 529` |
| a top-of-file insertion showing the inference cache holding (7.2) | **(c)** a blank line inserted at line 1: `surface 529 of 529` and **`reused 115 of 154`** — 7.2's own recorded ceiling for a pure shift, where the pre-7.2 tree reused **0 of 154**.  The caption says exactly that, including that the residue of 39 is 7.2 §1's prime-suffixed/operator class — it does NOT claim "nothing is re-inferred" |
| a burst of keystrokes showing one check and the adaptive window (7.4) | **(d)** five `didChange`s 40 ms apart on `Burst.e`: one `debounce:` line, **one `check:` line**, `waited 150ms … policy 150ms` — the FLOOR — printed beside Report.e's `waited 300ms … policy 300ms` from (b)/(c), the CEILING, from the same run |
| a tab-indented file's hover landing on the text (7.5 E8) | **(e)** `Tab.e`: the published diagnostics at **24:6** (the operator, seven characters left of where 6.x put it) and **19:1**; `hover` at (11, 1) answers `go : Bool`; `definition` from the use lands (11,1)-(11,4); `prepareRename` now OFFERS the name that 6.3 refused outright |
| a stdlib definition landing in `core/src/main/resources` (7.5 E9) | **(f)** the boot's own `positions: … stdlib source tree …/core/target/scala-3.3.8/classes/modules -> …/core/src/main/resources/modules` line, then `definition` on `&&` → `core/src/main/resources/modules/Bool.e 7:0-7:2`, with three assertions printed: under the source tree **True**, in the build output **False**, the file exists **True** |

**Reproducible modulo timings, checked rather than asserted.**  Two runs of the
final script, normalised only for wall-clock figures (`N.N ms`, `N.NNs`, `waited
Nms`, `median Nms`, `read Ns, typecheck Ns`), are **IDENTICAL** — `diff` empty.
(The log file's own name used to leak into the header line and was changed to name
the property instead, so the transcript no longer depends on where the log was put.)

## G4.4 — THE EXTENSION

| step | result |
|---|---|
| `npm run test:grammar` | **PASS** — 9 sections, the last tokenising the whole corpus (359 files, 36,800 lines) |
| `npm run test:load` | **PASS** — 9 steps including the LIVE handshake: status bar carries `Ermine session ready: 129 modules in 12.8s`, **9 providers registered** (Completion, Hover, Definition, Reference, DocumentHighlight, DocumentSymbol, WorkspaceSymbol, CodeActions, Rename) |
| leaked JVM after the load test | **none** (`pgrep -af 'com\.clarifi\.reporting\.ermine\.' \| grep '/java '` empty) — the 6.7 fix holds |

**A BUMP IS WARRANTED, and it is 0.1.1 → 0.1.2.**  The reason is user-visible text
that was WRONG, not a feature: `ermine.fastMode`'s settings-UI description said
"takes about a third off the time to diagnostics (measured on a 1757-line module:
0.94s read + 0.60s typecheck)".  After Stage 4 that split is 0.05 read + 0.53
typecheck of a 0.61 s check, so fast mode now takes off most of what is left and
"about a third" understates it by a factor of three.  E8 and E9 also changed what the
extension DOES for a user (ranges on tab-indented lines; where a stdlib definition
opens), without any client change.  `ermine-lang-0.1.2.vsix` built with
`npx @vscode/vsce package` (324 files, 480 KB — 0.1.1 was 479 KB, no new bloat);
`ermine-lang-0.1.1.vsix` removed.  Both vsix files and `package-lock.json` are
gitignored, so the only tracked extension changes are `package.json` and `README.md`.

**NOT DONE, deliberately: the `debounce` initializationOption is NOT exposed as a
VS Code setting.**  The server accepts it (item 7.4, `initializationOptions.debounce`,
1–10000 ms, refused outside that range) and `perf-bench.sh` uses it, but adding
`ermine.debounce` to the extension is a new user-facing feature, and a gate-evidence
run is the wrong place to add one.  It is a ~10-line follow-on (one property, one
line in `initializationOptions`, one line in the settings table) if the user wants it.

README's **"Three things that will surprise you"** rewritten, per the brief:

1. **the cold-open cost and the per-document memory** — the first check of a freshly
   opened file ~2.5 s against ~0.9 s per keystroke after it, ~1.6 MB of heap per open
   document of `Report.e`'s size, and 7.1b's 30–70 ms on the first check;
2. **which edits still check cold** — the scope key (imports, type/data/class/
   instance/field/foreign/fixity/`private`/`database`), and definitions whose name is
   not a plain word (operator, backtick, `_`, `'`), ~1.6 s instead of ~0.9 s;
3. **the 6.2 residual** — `case`/`do`/lambda binders still hover empty (unchanged).

E8 and E9 moved to a new **"Fixed in 0.1.2 (they used to be on this list)"** section
rather than being deleted, so a reader who remembers them sees what happened.  The
per-check paragraph now reads 0.9 s / 0.54 s worst-case wait instead of 1.7 s /
1.5 s, the diagnostics row describes the adaptive window instead of "~300 ms", and
the two `0.1.1.vsix` command lines say `0.1.2`.

## G4.2 (second half) — docs/lsp.md

Every stale editor number replaced from the PHASE-A tables; the greps the brief named
(`1.7`, `1.69`, `1.86`, `0.86`, `0.84`, `1.47`, a fixed 300 ms debounce, `494`, `510`)
come back clean.  What changed:

* **The whole Latency table re-cut** — boot, both keystroke rows (unpinned AND pinned,
  labelled), the small and mid-sized files with their harvested windows, the worst
  site, the cold open, the worst-case wait (1.47 s "upper bound" → **0.54 s measured**),
  the idle hover, completion, `workspace/symbol`, `documentSymbol`, the index and the
  code action.  The intro now states the protocol, the loads, and the `checkWith`
  calibration (+7 % on the untouched phase = this machine's drift) so the deltas can
  be read honestly.
* **A new paragraph, "Where a warm check actually goes, after Stage 4"** — the phase
  split (parse 37 ms, read 52 ms = 8.5 %, typecheck 529 ms = 87 %, index 11 ms)
  against the 845 ms / 1363 ms it replaced.
* **A new paragraph, "Which edits check COLD, and why"** — the group key vs the SCOPE
  key, the `private`/`database` block, and the operator/backtick/`_`/`'` class.  This
  is the explanation the worst-site row needs and it did not exist anywhere in the
  docs; it is 7.2's documented cost, stated where a user meets it.
* **The hover-traffic observation recorded as an observation**, not a claim, in its
  own paragraph: one probe run where ten hovers were followed by checks drifting
  0.59 → 0.95 s while a 70-round run stayed flat; reproduced once, not chased.
* Fast mode's paragraph re-cut (0.05 + 0.53 of 0.61; it also shortens the WAIT now,
  because 7.4's window tracks the check time); the debounce prose's two stale numbers
  (0.58 s, `median 551ms`) corrected; the harness bullet 480 → **542 checks** with the
  7.4 burst fixtures and the 7.5 tab/stdlib pins named; both demo references now point
  at `G4-demo.txt`.

## G4.5 — THE FULL GATE

Run in the brief's order, one JVM of mine at a time, `.ei` counted by `find` after
each step.  The machine also carried the user's own sbt in a separate worktree
throughout; every check below is a pass/fail or a byte-identity, and none of them
is a timing.

| # | gate | result |
|---|---|---|
| 0 | `sbt -batch -J-Xmx3g core/clean core/compile core/copyResources` | **success**, 46 s, 478 warnings (the standing count), `.ei` 143 |
| 1 | `TestLoopTrace` | **720 solves / 720 segments / 720 agree**, `hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`, 3/3 properties; the anti-vacuity controls still fire (id base +1: 46 of 720 disagree; `--flags=nongen`: 58 of 720) |
| 2 | `corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, one JVM, exit 0 |
| 2b | **the same corpus against a build of the G3 commit `ed42f55`** | **154 of 154 BYTE-IDENTICAL** — see below |
| 3 | `repl-smoke.sh` | **8 groups, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` empty — **the goldens are byte-unmodified** |
| 4 | `lsp-smoke.sh` | **PASS, 542 checks** (the count 7.5 left); `.ei` in `tracker/lsp-tests` **0** |
| 5 | `g1-validate.sh` | **9 of 9 PASS** — four comparator fixtures, two type-equivalence fixtures, the 129-module double run (`1447 signatures, EQUIVALENT`, 1301 normalised browse lines both times) and **no drift from `tracker/g1-baseline`**.  Its two full-inference boots wrote **129 `.ei` into the build-output module tree**; deleted by `find`, back to the 143 tracked baseline files |
| 6 | boot | **`Ermine session ready: 129 modules`** through the real LSP handshake |

### The whole stage's batch identity, in one comparison (gate 2b)

`corpus-run.sh --batch` was run TWICE over the same 154 corpus files: once on this
tree, once with `ERMINE_CP` pointed at a **fresh build of `ed42f55`** (the G3
commit) in a scratch worktree.  Verdicts **85/69/0 on both sides**, and the
per-file outputs are **identical for all 154 files** after normalising exactly
three things, each of which differs between ANY two runs or ANY two trees:

1. the progress bar's `\r` frames (they carry elapsed seconds),
2. the `(N.NN seconds)` load timings,
3. the absolute repository root, which differs because the before build lives in
   a worktree (it appears inside REJECTED messages that name a stdlib file).

Nothing else was touched, and the comparison is a pure compiler A/B: **`core/examples`
and every Tier-1 tool are byte-identical between `ed42f55` and HEAD**
(`git diff --stat ed42f55..HEAD -- core/examples tracker/tools/{looptrace-corpus.sh,trace-ab.py,ei-diff.sh,looptrace-diff.py}` is empty), so the only thing that
varies across the pair is the compiler.

### TIER 1, ONCE FOR THE WHOLE STAGE (the parser library changed in 7.1a)

**`looptrace-corpus.sh` on both builds, 18 groups, `LOOPTRACE_PAR=3`,
`-Dermine.loadInSeries=true` (the default):**

| | **before (`ed42f55`)** | **after (this tree)** |
|---|---|---|
| groups | 18/18, **rc 0, 0 timeouts, 0 dropped segments** | 18/18, rc 0, 0 timeouts, 0 dropped |
| solve segments | **3,206,083** | **3,206,083** |
| Lean model agreement | **3,206,083 agree, 0 skips** | **3,206,083 agree, 0 skips** |

**`trace-ab.py` per group, ALL sixteen record kinds** (the F3 review's full
comparison, not the narrowed `KEEP` tuple):

    Ai 83976 IDENTICAL            Algebra 101039 IDENTICAL      Algebra-shouldfail 55401 IDENTICAL
    boot 54209 IDENTICAL          bugs 54245 IDENTICAL          guide 54254 IDENTICAL
    incomplete 1905718 IDENTICAL  Lang 91334 IDENTICAL          Lang-shouldfail 58789 IDENTICAL
    Present 131392 IDENTICAL      Present-shouldfail 59503 IDENTICAL
    shouldfail 56040 IDENTICAL    shouldfail-controls 54749 IDENTICAL
    Time 125134 IDENTICAL         Time-shouldfail 55932 IDENTICAL   top 92707 IDENTICAL
    Wide 115874 IDENTICAL         Wide-shouldfail 55787 IDENTICAL

**3,206,083 paired segments, 3,206,083 IDENTICAL, `sinmoved=0` in every group** —
not one `Supply` bound moved anywhere in the corpus, which is the hazard
`ROW-CONSTRAINT-STATE.md` insists be measured rather than assumed, and the same
total 7.1a's own before/after pair produced.

**ONE NORMALISATION, and it is named.**  The raw comparison first came back
`CONTENT-DIFFERS` on ~46 k segments per group, and the cause is not the compiler:
a trace record carries the ABSOLUTE PATH of the file the solve came from, and the
before build runs out of a worktree.  Every differing pair was
`…/scratchpad/g4/wt-g3/core/target/…/Control/Monoid.e(3:17)` against
`/home/dmitry/research/ermine/ermine-scala/core/target/…/Control/Monoid.e(3:17)`
with every other field — record kinds, ids, counts, `Supply` bounds — equal.
Replacing that one prefix in the before traces (`sed "s|<worktree>|<repo>|g"`,
nothing else) gives the table above.  7.1a did not need this because it swapped
CLASS DIRECTORIES inside one tree; a build of a named commit needs a worktree, and
this is the cost of that.  The substitution is a fixed string and touches no field
the comparison is about.

**`ei-diff.sh --snapshot --batch` in series on BOTH builds** (`EI_BATCH_CHUNK=5`,
`-Dermine.loadInSeries=true`, one side per build, never one batched side against a
per-file side):

| | before (`ed42f55`) | after (this tree) |
|---|---|---|
| interfaces captured | **268** | **268** |
| only on one side | — | — |

`ei-classify.py`: **0 of 268 interfaces differ**, and all **3,481 published
bindings** classify as `identical` — not order-only, not alpha-equivalent,
identical strings.  **No `.ei` byte in the corpus depends on anything Stage 4 did.**

### TIER 2 — `sbt -batch -J-Xmx3g core/test` ALONE among my JVMs

**Both runs reported, per the E12/E13 rule.**

| run | total | result | time |
|---|---|---|---|
| 1 | **1028** | **1 failed** — `TestInterfaceRoundTrip`, property `Interface round-trip.new-pipeline cold write, fresh warm read, same answers`, *Falsified after 0 passed tests* | 1433 s (23:53) |
| 2 (the ONE re-run the rule allows) | **1028** | **1028 passed, Failed 0, Errors 0** | 1726 s (28:46) |

**The red is exactly E12 and nothing else.**  `tracker/GATE-POLICY.md` names this
property by name: it passes alone and fails roughly one full run in ten when
another suite in the same JVM repopulates the process-global `Session.depCache`
between the property's clear and its warm load — intra-run cross-suite
parallelism, corrected to that wording on 2026-09-11 after 7.1b's review R-5 saw
it for the third time.  The policy's standing rule is ONE re-run for exactly this
property, and the re-run is clean.  No other property failed in either run, and
`TestLegend` (E13) did not fire at all.

**The arithmetic on the total.**  1026 at the end of 7.4 **+ 2** = **1028**: item
7.5's two new `TestRenamer` corpus round-trip properties (32 → 34 in that suite).
7.5's other work (E9's path pins, E10(5)'s own-synonym case) went into
`lsp-smoke.sh` and into existing `TestTolerantCheck` properties, so it moves the
smoke count, not the property count.  `TestReplDifferential` and the REPL goldens
are inside this run and are green; `TestTolerantRead`'s 180-file agreement
property is inside it and green.

Seven `.ei` files appeared in the build-output module tree during the test runs
(`Bool`, `Control/Category`, `Control/Monoid`, `Function`, `Function/Endo`, `Ord`,
`Primitive` — `TestInterfaceRoundTrip`'s own writes); deleted by `find`.  **Final
state: `find . -name '*.ei'` = 143, the tracked `tracker/g1-baseline/ei` baseline
and nothing else; 0 in `tracker/lsp-tests`; no JVM of mine left running.**

## G4.6 — THE GATE, LINE BY LINE

### GREEN list

| G4 line | where checked | result |
|---|---|---|
| Tier 0 on every commit: `core/compile core/copyResources` | G4.5 gate 0 | **success** on a clean build |
| `TestLoopTrace` 720/720 | G4.5 gate 1 | **720 / 720 / 720**, controls fire |
| `corpus-run.sh --batch` verdicts unchanged at 85/69/0 over 154 | G4.5 gate 2 | **85 / 69 / 0 over 154**, and **byte-identical to `ed42f55`** |
| `repl-smoke.sh` 8 groups | G4.5 gate 3 | **8 groups, 66 checks**, goldens byte-unmodified |
| `lsp-smoke.sh` at its new grown count | G4.5 gate 4 | **542** (454 at G3 → 456 after 7.0 → 494 after 7.1b → 510 after 7.4 → 542 after 7.5) |
| the seven targeted suites on anything touching TolerantCheck/Lower/Renamer/Definitions | each item's own report; **and all of them inside Tier 2 here** | green in Tier 2 run 2 |
| **Tier 1 for 7.1a and anything reaching into `scalaparsers`** — `looptrace-corpus.sh` + `trace-ab.py` | G4.5 Tier 1 | **3,206,083 segments, all IDENTICAL, `sinmoved=0`**, 18/18 groups rc 0 on both builds |
| … `ei-diff.sh --batch` in series on both sides, classified with `ei-classify.py` | G4.5 Tier 1 | **0 of 268 differ; 3,481 bindings all `identical`** |
| … `g1-validate.sh` | G4.5 gate 5 | **9 / 9**, no baseline drift |
| **Tier 2 = full `core/test` ALONE, green, at the gate** | G4.5 Tier 2 | **1028 / 1028** on the allowed re-run; run 1's single red is E12 by name |
| REPL goldens and `TestReplDifferential` BYTE-UNCHANGED | `repl-smoke.sh` + Tier 2 | **unchanged** (`git status tracker/repl-tests` empty) |
| `TestTolerantRead`'s 180-file agreement property green | Tier 2 | **green** |
| boot 129 modules | G4.5 gate 6 | **129** |
| no `.ei` droppings in `tracker/lsp-tests` | after every step | **0** |

### NUMBERS RECORDED list

| # | what G4 asked for | where | the number |
|---|---|---|---|
| (1) | **7.0's phase table, before AND after the stage** | PHASE A §G4.1 | both tables, row for row, big file and small.  `parse` **829.8 → 36.9 ms**, `read.total` **845.4 → 51.6 ms**, `check.total` **1363.0 → 607.5 ms**; the small file **30.7 → 15.4 ms**.  Reconciliation +0.07 ms read / +0.39 ms check (99.94 % accounted) |
| (1a) | … with the over/under-attribution factor against the survey named per row | **7.0's table, §4.6, unchanged and NOT re-derived here** — parse under-attributed 1.07x, rename under 2.30x, lower over 1.09x, `lowerctx`+`lower` 1.12x under, header absent from the survey.  The survey is a JFR profile of the PRE-stage tree; re-deriving it against the after tree would be comparing a 2026-09-09 profile with a 2026-09-11 build and was not done.  **This line is PARTIAL, stated rather than fudged** |
| (2) | an **interleaved A/B** for every adoption item, pooled Δ, against the ~50 ms noise floor and the 0.795–0.865 s read drift | each item's reviewer of record | **7.1b** (reviewer): read **0.8375 → 0.0500 s, −788 ms**, round trip **1.691 → 0.896 s** — 3.9x the 200 ms gate, far outside both floors.  **7.2** (reviewer): round trip **1.822 → 1.828 s, +6 ms (+0.3 %)** (implementer −1.5 ms) — inside the floor, and the item's gain is the cliff, not the clock.  **7.4** (reviewer): big file **0.941 → 0.956 s, +15 ms (+1.6 %)** (implementer +11 ms) — inside the floor, window provably 300 on both sides; small file **0.3204 → 0.1719 s, −149 ms (−46.4 %)**; `List.e` −146 ms (−40.7 %); `Options.e` −111 ms (−23.5 %).  **7.1a** (reviewer, both targets): batch pooled **+0.065 s mean / +0.040 s median (+0.3…+0.7 %, pairs straddling zero)**; editor read **+20 to +48 ms pooled, +5 to +90 ms per pair, control 0 ms, positive in 5 of 5 pairs (sign test p = 0.03)** — the one residual the stage accepted, and it is the price of 7.1b's −788 ms |
| (3) | the **corpus differential for 7.1b**, with generator and seed | 7.1b report §2 + its review | 180 files x a 12-step multi-edit sequence, **2,613 steps, 54,274 hits / 19,374 misses, 0 `SModule` mismatches, 0 diagnostic mismatches**, **seed 71**, reproduced by the reviewer on seed 71 and on **two fresh seeds (913, 20260911)**, plus eleven constructed attacks all missing correctly |
| (4) | the **reuse counts for 7.2** (0/154 → N on a top-of-file line insertion) | 7.2 report §; reproduced in the demo today | **0 of 154 → 115 of 154** on a pure top-of-file insertion (and top-DELETE the same); mid-insert **83 → 115**; an in-body edit stays **97 of 154** on both sides.  The residue 154 − 115 = 39 is 7.2 §1's three classes, the prime-suffixed one dominant.  **The G4 demo transcript prints `reused 115 of 154` live** |
| (5) | the **worst-case request wait, re-measured, next to 6.7's figure** | PHASE A §2.6 | **1.45 s → 0.544 s** (n=5, 510–616 ms), answer 0.90 s after the keystroke, idle control 0.31 ms; **on 7.6's 500 ms trigger: 544 ms median at n=5 here; the reviewer's n=12 on a quieter machine gave 502 ms median (482-551, 8 of 12 above 500) — a straddle, not a clear exceedance; with fast mode ON, 56 ms worst case** |
| (6) | a **heap figure for 7.1b's retention** | 7.1b report/review | **1.63 MB per open document** of `Report.e`'s size (~20x its source, 97 % the surface tree), **3.44 MB for the ten largest open at once** (~3.6 MB with the previous buffers), replaced per check, dropped on `didClose`; ~0.1 % of a 3 GB editor heap |
| (7) | **every REVERTED item with the number that killed it** | — | **REVERTED items: NONE.**  Nothing adopted in Stage 4 was later withdrawn.  (7.1a's fix round did revert two deliberately planted bugs byte-for-byte as an audit; that is a self-check, not a reverted item.) |

## WHAT IS NOT SATISFIED, PLAINLY

1. **7.3 is handed off, not done.**  The parse constant factor was reopened as an
   investigation and is now `tracker/PERF-ROADMAP.md`'s, not this stage's.  Nothing
   in this report claims it.
2. **7.6 is PARKED, and PHASE A gives the number it was waiting for.**  The
   worst-case wait for a request that arrives during a check is **544 ms** on the
   largest stdlib module — **still above the 500 ms trigger the parked
   worker-thread fork names, on all five samples (510–616 ms)**.  Stage 4 took it
   from 1.45 s to 0.54 s without a thread; the remaining 87 % of the check is
   inference, which a worker thread would make INTERRUPTIBLE but not faster.  The
   decision stays the user's.
3. **The 6.2 fork is still open and still the user's.**  Local binders inside a
   `case`, a `do` or a lambda hover empty (62.4 % of local binders hover); closing
   it needs a flag-gated hook at four hot-path sites in `Subst.scala`, which Stage 4
   is forbidden to touch.
4. **G4's "over/under-attribution factor per row" is PARTIAL** (NUMBERS line 1a
   above): those factors live in 7.0's table against a JFR survey of the pre-stage
   tree and were not re-derived against the after tree, because the survey is not a
   Stage-4 artifact and re-profiling would compare two different builds' profiles.
5. **E12 fired once in Tier 2** (`TestInterfaceRoundTrip`) and was cleared by the
   single re-run the policy allows.  The ticket is open; the flake's cause
   (process-global `Session.depCache` vs intra-run cross-suite parallelism) is
   named in `GATE-POLICY.md` and is not a Stage-4 regression.  E13 did not fire.
6. **Open user-visible tickets that Stage 4 did not take**, all with their reasons
   in 7.5's triage: **E5** (loadInSeries vs loadModules — waits for the first
   Tier-2 code commit), **E6** (lambda blame at the application — moves REPL
   goldens and corpus verdict text; frozen batch semantics forbid it here),
   **E7** (import-failure suppression misses operators and types — half shipped),
   **E10(1)-(3)** (the printer's 48 further add-signature groups).  E8, E9 and
   E10(5) are CLOSED by 7.5 and are demonstrated in the G4 transcript.
7. **The `debounce` option is not exposed in the VS Code extension** (G4.4): a new
   setting is a feature, not gate evidence.
8. **One unexplained observation, recorded and not chased**: in one PHASE-A probe,
   ten hovers between checks were followed by checks drifting 0.59 → 0.95 s, where
   a 70-round run with no hovers stayed flat at 0.50–0.56 s over 70 checks.  It is
   in `docs/lsp.md` as an observation.  It changed no number of record — the
   worst-case wait was re-measured with the checks at steady state.

## OUTCOME

**GREEN**, with the two PARTIALs above stated rather than papered over (the
survey-attribution line, and 7.6's trigger not cleared).  Every GREEN-list gate is
at or above its baseline; every NUMBERS-list item has a number; REVERTED items:
none.

Files this run touched, all outside `core/`: `docs/lsp.md`,
`editor/vscode/README.md`, `editor/vscode/package.json` (0.1.1 → 0.1.2),
`tracker/tools/lsp-demo.py`, `tracker/tools/lsp-demo.sh`, and two new files
`tracker/lsp-tests/G4-demo.txt` and this report.  **No source file changed**
(`git diff --stat -- core parsers machines scalacheck-binding` is empty), and
`git diff --stat --histogram` == `git diff --stat -w --histogram`.  **No commit was
made**, `tracker/LSP-ROADMAP.md` and `tracker/lean/` were not touched, and the
`ermine-lang-0.1.2.vsix` / `ermine-lang-0.1.1.vsix` files are gitignored (0.1.1
deleted from disk).

**STOP.**  A reviewer re-runs the gates once; then the orchestrator writes
"Gate evidence (G4)" into `tracker/LSP-ROADMAP.md` and stops for the user's
sign-off.

### Scratch for the reviewer (PHASE B)

`<scratch>/g4/`: `g0-compile.log`, `g1-looptrace.log`, `g2-corpus.log`,
`g3-build-before.log`, `g3-corpus-before.log`, `g4-repl.log`, `g5-lspsmoke.log`,
`g6-g1validate.log`, `g7-boot.log`, `g8-lt-{after,before}.log`,
`g9-ei-{after,before}.log`, `g10-coretest.log` + `g10-coretest-run2.log`;
`corpus-{after,before}/` and their normalised copies `nn-{after,before}/`;
`lt-after/`, `lt-before/`, `lt-before-norm/` (the path-normalised traces),
`traceab-16.txt`; `ei-after/`, `ei-before/`; `wt-g3/` (the `ed42f55` worktree and
its build); `demo{1,2,5}.txt` + logs; `x-grammar.log`, `x-load.log`, `x-vsce.log`.

**One thing left on disk deliberately**: the `ed42f55` build lives in a registered
git worktree at `<scratch>/g4/wt-g3` (it shows up in `git worktree list`), so a
reviewer can re-run the before side without a ten-minute rebuild.  Remove it with
`git worktree remove --force <scratch>/g4/wt-g3` when the gate is signed off.


## Orchestrator's note at the gate (slimmed review, V-1/V-2/V-4)

V-1: the "all five samples above 500 ms / the trigger would fire on every sample" phrasing overstated a straddling
number. The reviewer's independent measurement (n=12 per offset, load 0.62-0.85, no hover traffic before the block):
hover at +352 ms → **502 ms median (482-551), 8 of 12 above 500**; at +600 ms (mid-check) 277 ms; at +100 ms (inside
the debounce window) 2.2 ms; idle 0.28 ms. The arithmetic model holds exactly (check 0.554 + debounce 0.300 − 0.352 =
0.502 predicted, 0.502 measured); the 544-vs-502 gap is two machines' check times, inside 7.0's 8% drift band. So the
worst case SITS ON 7.6's trigger rather than above it. V-2: 7.6's own precondition — try fastMode first — is now
ANSWERED: with fast mode on, the check is read-only (67 ms) and the 7.4 window drops to its 150 ms floor, so the
worst-case wait is **56 ms** (9x under the trigger) and the fast-mode round trip is 0.23 s; the fastMode-first answer
is yes. V-3: the hover-traffic degradation did NOT recur under the reviewer's 36 interleaved hovers (typecheck flat
0.46-0.59 s over 57 checks) — it stays an observation. V-4: the before side was verified to be `ed42f55` by the
reviewer through a class inventory (0 `SurfaceCache*`/0 `Anchors*` classes vs 10/3 at HEAD; 2,479 vs 2,502 classes)
on the detached worktree, which this report had not stated. V-7: the interface sweep was stronger than claimed — all
268 dumps byte-identical, not merely classified identical.
