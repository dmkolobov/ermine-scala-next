# Brief: LSP Stage 4, item 7.0 — DIRECT MEASUREMENT of the read's phases (the item every later item is judged against)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (Stage 4 is
open; Stage 3 is complete). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells when you
stop. No commits. Do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.0/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", item **7.0**, with the section's GOAL, "THE PERF PREMISE, with
provenance" (every figure tagged MEASURED or ARITHMETIC — your job is to replace the ARITHMETIC rows), the STAGE-4
INVARIANTS and Decisions (a), (d), (g). Read `tracker/loopmodel/STAGE4-PRIOR-ART.md` §0.1 (the arithmetic you are
testing) and §5(a)/(a′) (what the verdict decides), `tracker/PERF-ROADMAP.md` P5(a) (the 3.5x over-attribution
precedent and the 50-reps-after-20-warm-ups protocol) and P5(c)/(d), and `tracker/GATE-POLICY.md`. The G3 latency
table (roadmap "Gate evidence (G3)") is the reference round trip: 1.69 s = 0.86 read + 0.50 typecheck + 0.30 debounce.

WHAT THIS ITEM IS: measurement, not optimisation. NO behaviour change, NO default flip, NO change to any strict
path; instrumentation goes behind a system property (e.g. `-Dermine.lsp.phases=true`) printing to STDERR (never
stdout — Decision 4, the protocol channel) or to the LSP log, and either ships behind that property or comes out
before you report — say which and why. Tier 0 only. If measuring a phase separately would require changing its
behaviour, do not: report it as unseparable.

## What to do

7.0.1 INSTRUMENT `Resident.checkFile` (and what it calls) with `System.nanoTime` around each phase, reported per
      check: (a) header parse; (b) `StatementExtents.scan` (+ `Offsets`); (c) `SurfaceParsers.module` — the whole-
      file surface parse; (d) the layout/vsemi work inside (c) if separable without changing behaviour, else
      "unseparable"; (e) `Renamer.rename`; (f) `Reassoc`; (g) `Lower` (+ TyLower); (h) `Definitions.index`,
      `Symbols` build, the env copy and the self-scrub, `TolerantCheck.keys`; (i) `TolerantCheck.checkWith` as one
      number (the typecheck half, for the total to reconcile); plus the `Rpc` side of one full-sync `didChange`:
      frame read + JSON parse of Report.e's ~78 KB body (Decision (d) — the survey's out-of-process 369 µs figure
      needs an in-process number). The phase timers must SUM to within a few percent of the check's total as the
      existing log line reports it; if they do not, find what is unaccounted for and name it.
7.0.2 MEASURE on `core/src/main/resources/modules/Layout/Report.e` (1757 lines) through the real server path:
      drive `Resident.checkFile` by the scripted client (`tracker/tools/perf-client.py` / `perf-bench.sh editor`
      shape: didChange round trips) with the property on — **50 reps after 20 warm-up reps, medians AND spread
      (min/max or p10/p90), machine load < 1.3 at start and reported** (wait for it; never under load). Report the
      table with every phase in ms. Repeat ONCE on a small file (a ~50-line fixture) so the fixed costs are visible.
7.0.3 THE SINGLE-STATEMENT NUMBER — the one that ranks 7.1 against 7.3 (Decision (g)): take ONE representative
      top-level statement from Report.e (~245 bytes, the corpus mean; say which and its byte length) and parse it
      alone through `SurfaceParsers.statement` with the repositioned `ParseState` that `statementFailure` already
      uses (seeded layout stack — read `NewPipeline.readModuleTolerant`'s statementFailure path), same 50/20
      protocol, in a JVM-local harness (a test-scope main or a ScalaCheck property that is NOT part of the shipped
      suite). Report: per-statement parse time; the ratio (number of top-level statements in Report.e × per-
      statement time) / (whole-file parse time from 7.0.2) — if the ratio is ≈1 the parse cost is per-statement
      work and a statement cache (7.1) recovers it; if ≪1 the cost is elsewhere (layout, whole-file trampoline
      overhead, the splitter) and 7.1 cannot; if ≫1 something is wrong with the measurement. Also time the
      splitter alone (the `sepEndBy(semi)` driver with `.attempt` per item) if it can be isolated — it is the
      per-file overhead a statement cache would still pay.
7.0.4 COMPARE each MEASURED row against the survey's ARITHMETIC row (§0.1: parse ≈0.70 s / 91.4% of the read;
      extents ≈0.054 s; lower ≈9 ms; rename ≈2 ms; reassoc ≈1 ms) and name the over/under-attribution factor per
      row, the way P5(a) did (it found 3.5x on one pass). Say plainly whether the parse share is honest.
7.0.5 THE Rpc ADDENDUM (Decision (d)): if the in-process frame-read + JSON-parse of a Report.e didChange reproduces
      ~369 µs, a run-based scanner replacing the char-at-a-time one in `Rpc.scala`'s JSON reader is an OPTIONAL
      ten-line change — implement it in scratch, measure it the same way, and adopt ONLY if it is byte-identical
      on every existing framing/JSON test and lsp-smoke (454) and measurably faster; otherwise drop it and say so.
      It is a request-path change, so it needs no perf A/B on the round trip (it is ~0.02% of it) — say that.
7.0.6 VERDICT, one line with the arithmetic that supports it: **"7.1" / "7.3" / "neither"** — 7.1 (statement
      cache) if per-statement parse work is the bulk of the whole-file parse AND the parse is the bulk of the read;
      7.3 (parse constant factor) if the per-statement parse is itself slow in a way a cache cannot amortise (a
      cache still pays it on every miss) or the cost is whole-file overhead; "neither" if the read is not where the
      arithmetic said (then the stage collapses to 7.2 + 7.4 + 7.5, per the roadmap). Also state what 7.2's cliff
      would cost: run ONE measurement where a line is inserted at the top of Report.e and report the reuse count
      and the typecheck time (the roadmap says 0/154 and the full ~0.5 s; measure it).
7.0.7 GATES (Tier 0): `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'` 720/720;
      `tracker/tools/corpus-run.sh --batch <scratch outdir>` 85/69/0 over 154; `tracker/tools/repl-smoke.sh` 8 groups
      / 66 checks, goldens unmodified; `tracker/tools/lsp-smoke.sh` 454 (or grown if you added a check that the
      property-gated timing line appears when asked and not otherwise — do add that one); boot 129; `.ei` 0;
      `git diff --stat` == `--stat -w` (CRLF files: preserve line endings). The strict path must not change:
      `git diff -- core/src/main/scala/com/clarifi/reporting/ermine/session/Session.scala
      core/src/main/scala/com/clarifi/reporting/ermine/rename/NewPipeline.scala` — if you had to touch NewPipeline to
      insert a timer, show that the strict `readModule` is byte-for-byte unaffected in behaviour (the timers are
      inert when the property is off).
7.0.8 REPORT `tracker/loopmodel/LSP4-7.0-READ.md`: the phase table (Report.e and the small file) with reps/spread/
      load; the reconciliation against the check total; the single-statement number and the ratio; the per-row
      attribution factors against the survey's arithmetic; the Rpc addendum outcome; the 7.2 cliff measurement;
      the VERDICT; what ships (the property-gated timers or nothing); every gate number. Outcomes: GREEN (the
      table is complete and the verdict is stated) / PARTIAL (which phase could not be measured and why). No
      behaviour change; STOP after the report — a reviewer re-runs the measurement once.
