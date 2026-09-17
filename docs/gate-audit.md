# Gate audit

Written 2026-09-17 on branch `gate-audit` at `836eb61f`, the `json-encode` tip. The policy built on it is
`docs/gate-policy.md`.

**Summary.**
- **Measure used.** Every gate, sweep and test suite is ranked by *real defects caught per machine-hour
  actually spent running it*, over 2026-08-29 to 2026-09-17. That window is when these gates were in daily
  use. Costs were measured today, one gate at a time. Run counts come from the Bash history of every Claude
  session on this project. Catches come from git history and the tracker reports.
- **Load-bearing gates.** Only a handful are. `corpus`, `g1-validate` and three suites (`TestStage1Pins`,
  `TestErmine`, `TestRenamer`) account for most confirmed catches, plus two instruments used as probes.
- **Ritual gates.** These never caught a defect in the window: `repl-smoke` (196 runs), `TestLoopTrace`
  (154 targeted runs plus 181 full runs), `perf-bench` (72) and `trace-ab` (38). Neither did the most
  expensive suite, `TestTolerantCheck`: 21 machine-hours. Neither did `TestReplDifferential` (7.3 h) or
  `TestTolerantRead` (3.9 h). 21 of the 53 suites have no recorded event of any kind. Five suite files are
  commented out entirely, and the CI config has never run.
- **Silently vacuous gates.** Two gates can look green without checking anything, and I reproduced both
  today:
  - `TestLoopTrace` reports PASS when it skipped.
  - `looptrace-corpus.sh` exits 0 whatever its replay found.

Reproduce the ranking with `python3 docs/gate-audit-data/rank.py`. Every input it reads is in
`docs/gate-audit-data/`.

## 1. Method

### 1.1 Cost: wall clock per run

The costs were measured in a fresh worktree of `836eb61f` with `docs/gate-audit-data/measure.sh`. Each gate
ran serially, never alongside another measured gate, and the 1-minute load average was recorded at the
start and end of each run (`measurements.tsv`). The machine also carried the user's idle LSP server and
JSON server throughout, which is its normal state.

- **Suites.** Each suite's own seconds come from running every suite with `core/testOnly` inside **one**
  sbt session, so the JVM start is paid once. JIT warm-up lands on the first suite, which is noted and not
  corrected.
- **Not measured today,** and marked as such in `costs.tsv`:
  - `perf-bench.sh` refused to start because "another ermine JVM is running". That JVM was the user's
    editor.
  - The 2.11 suite is on another branch and toolchain. It is costed from its 2026-09-16 log.
  - The `sql-render` and signature-survey instruments are estimates.

### 1.2 Runs: how often each gate was actually executed

`invocations.py` counts **executions**, not mentions, across 47,512 Bash tool calls from every session and
subagent of this project, 2026-08-29 to 2026-09-17 (`invocations.txt`):
- Heredoc bodies are removed first.
- The tool must be in command position.

Machine-hours are executions multiplied by today's cost:
- **Full `core/test` runs** (181) charge every suite its own seconds.
- **Targeted `testOnly` runs** charge the suite plus 5 s of sbt start.

This is an estimate. An aborted run counts as a full run, and runs the user started by hand are not seen.

### 1.3 Catches

Two read-only agents searched `git log --all` (1,160 commits: 2015-2019 upstream, 2026 this programme),
`tracker/**/*.md` and both 2.11 branches' reports, and classified every evidence item. I spot-checked 8
of their cited commits and quotes against the repository, and all 8 matched. Their full reports, with a
verbatim quote and source for every row, are `docs/gate-audit-data/history-scripts.md` and
`history-suites.md`.

The classes:

- **REAL-DEFECT:** running the gate revealed a product defect nobody knew about, and it was then fixed or
  ticketed.
- **GATE-DEFECT:** it revealed a defect in another test or harness.
- **SELF-DEFECT:** the gate itself was found broken. This is evidence *against* it.
- **Not catches:** EXPECTED-CHANGE (a baseline refresh), FALSE-ALARM, FLAKE, and WRITTEN-WITH-FIX (the
  check was written in the same change as its fix, the most common case: 15 suites).

**Score** = REAL-DEFECT + GATE-DEFECT, each weighted 1 when sure and 0.5 when the agents marked it UNSURE
(`catches.tsv`). Only the 2026 window is scored. The one 2015 catch, `TestRTag` in `c895bf2e`, is listed but
has no run count to divide by.

**One correction to the agents' tally.** They credited `perf-bench` with one UNSURE catch (the 7.1a mark
cost, `d010678f`). Their own row says `perf-bench.sh` *refused* that run and a hand-written replica took
the measurement, so it is scored 0 here.

## 2. Findings verified today, not taken from the record

These were reproduced on `836eb61f` during this audit. Every one is load-bearing for the policy.

### 2.1 `TestLoopTrace` reports PASS when it skipped

With no Lean binary built for the tree, both model properties print `[loop model trace] SKIPPED: the
Lean model executable is absent` and sbt reports `Passed: Total 3, Failed 0`.

- **Cost of the skip.** The skipping run takes 5.1 s; the real run (720 solves, 720 agree) takes 14.9 s.
- **Where the binary exists.** Only two of the 20 checkouts (`git worktree list`) have a Lean binary
  (`wt-json-wrappers`, `wt-subsume`).
- **Reproduced by my own Tier 0 run.** The script I wrote this morning (`gate-tier0.sh`) reported
  `looptrace=3/3` on `subsume-s2`, and its log says SKIPPED.
- **The history agrees.** The record shows the same thing at SIG-1, LET-1, J2a, J3a, J3b and SUBSUME S0.

### 2.2 `looptrace-corpus.sh` cannot fail

Its last lines write `results.txt`, delete `.ei` files and `echo "done"`. Nothing ties its exit status to
agreement.

- **Today's run.** 18/18 groups agreed over 3,210,869 segments, exit 0.
- **A disagreement would also exit 0.** The exit status does not depend on `results.txt` at all: I read
  the script for this, I did not run a doctored replay. A group short by a single segment (`agree=54208` of
  54209) would still exit 0, and only a human reading the table would catch it. The new gate parses every
  group line; it passes today's file and fails that one-segment-short copy.

### 2.3 The corpus sweep had no machine-checked expectation

`corpus-run.sh --batch` + `corpus-verdicts.py` print counts, and humans compared them to a remembered
"85 / 69 / 0". Two failure modes follow:
- A counterbalanced pair of verdict flips leaves the counts unchanged.
- The refusal text is never compared at all.

Determinism check: the S2 landing's corpus run (2026-09-16) and my Tier 0 run today are two runs of the
same build, `d278c900`. After normalising checkout paths they differ in **0 of 168** modules, verdicts
and refusal text both. A per-module expected file is therefore a safe comparison.

### 2.4 Five suites never run

`TestRelations.scala` (with `TestErmineRelations`), `TestAccess.scala`, `TestWriters.scala`,
`TestAmalgamation.scala` and `TestKeyValueTabular.scala` are commented out from their first line. sbt
discovers 48 suite classes, not the 53 `Properties` objects the source contains.

### 2.5 `perf-bench.sh` cannot run while the editor is open

It refused today with `FAIL: another ermine JVM is running: 1199553 ... lsp.Main`, which was the user's
language server. Its record has five SELF-DEFECTs, two of them preflight refusals of runs that should have gone ahead
(`8bdf06e3`, "refused the run silently, printing no median rather than an error"; LSP4-7.0-READ.md:104,
"it refused every run"), and no recorded movement ("10.98 / 11.03 / 10.94 / 10.98 s, UNMOVED",
LOOP-MODEL-HANDOFF.md:1054).

### 2.6 `TestJson."nesting past the depth where nf overflows still encodes"` is environment-dependent

- **Red twice today on `836eb61f`,** both times with `java.lang.StackOverflowError`: once in the full run
  (1-minute load 2.9 to 6.9) and once inside the per-suite session.
- **Same code was green before.** `836eb61f` differs from `ac2606a0` only under `docs/`, and on
  `ac2606a0` the M2 landing recorded `Passed: Total 1199, Failed 0, Errors 0`
  (tracker/satterm/SUBSUME-M2.md:157).
- **Why it flips.** The property's own comment says argonaut's printer "bounds the *rendered* depth at a
  few thousand levels on the default stack", and it renders 2,000. So identical code gives both answers
  depending on thread stack and JIT state.
- **A second flake the same day.** In the per-suite session, `TestLegend."extra args are ignored"` (ticket
  E13) also went red on this content.
- **Consequence for the policy.** Under the old policy this red would get "ONE re-run". Under the new one
  it is a flake by definition (§1 of the policy).

### 2.7 `bitbucket-pipelines.yml` is dead

- **History.** Two commits, 2017 and 2019. It uses an `image: bitbucketpipelines/scala-sbt:scala-2.12`
  sample and runs `sbt test`.
- **No evidence it ran.** Nothing in 2026 records a run.
- **No CI now.** The remote is GitHub, and no branch has a workflow.

## 3. Ranking

Scored gates and suites, highest catch rate first. "runs" = executions in the window; "machine-hours" =
runs × seconds (suites: full runs × seconds + targeted runs × (seconds + 5)).

| rank | gate | seconds/run | runs | machine-hours | real | gate-defect | of which unsure | score | catches/hour |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TestInterfaceRoundTrip | 2.0 | 8 | 0.07 | 1 | 1 | 1 | 1.5 | 22.51 |
| 2 | TestErmine | 6.0 | 3 | 0.16 | 1 | 1 | 0 | 2.0 | 12.31 |
| 3 | sigentail-survey | 30.0 | 19 | 0.16 | 2 | 0 | 1 | 1.5 | 9.47 |
| 4 | sql-render | 60.0 | 13 | 0.22 | 2 | 0 | 0 | 2.0 | 9.23 |
| 5 | TestStage1Pins | 17.0 | 21 | 0.56 | 3 | 0 | 0 | 3.0 | 5.33 |
| 6 | TestDoc | 6.0 | 0 | 0.15 | 0 | 1 | 1 | 0.5 | 3.26 |
| 7 | 2.11-suite | 193.0 | 22 | 1.18 | 3 | 1 | 1 | 3.5 | 2.97 |
| 8 | TestLower | 9.0 | 45 | 0.40 | 0 | 1 | 0 | 1.0 | 2.47 |
| 9 | TestErmineModules | 19.0 | 0 | 0.49 | 1 | 0 | 1 | 0.5 | 1.03 |
| 10 | corpus | 41.9 | 152 | 1.77 | 2 | 0 | 1 | 1.5 | 0.85 |
| 11 | TestRenamer | 27.0 | 69 | 1.30 | 1 | 0 | 0 | 1.0 | 0.77 |
| 12 | g1-validate | 135.2 | 60 | 2.25 | 2 | 0 | 1 | 1.5 | 0.67 |
| 13 | lsp-smoke | 43.9 | 238 | 2.90 | 1 | 0 | 1 | 0.5 | 0.17 |
| 14 | TestDateAndScan | 196.0 | 24 | 6.35 | 0 | 1 | 0 | 1.0 | 0.16 |
| 15 | ei-diff | 891.5 | 58 | 14.36 | 2 | 0 | 0 | 2.0 | 0.14 |
| 16 | lean | 235.5 | 129 | 8.44 | 0 | 1 | 1 | 0.5 | 0.06 |
| 17 | looptrace-corpus | 1198.7 | 49 | 16.32 | 1 | 0 | 1 | 0.5 | 0.03 |
| 18 | TestInMemoryScan | 0.0 | 0 | 0.00 | 0 | 0 | 0 | 0.0 | 0.00 |
| 19 | TestOptimizer | 0.0 | 0 | 0.00 | 0 | 0 | 0 | 0.0 | 0.00 |
| 20 | TestProcessSymbols | 0.0 | 0 | 0.00 | 0 | 0 | 0 | 0.0 | 0.00 |
| 21 | TestReassoc | 0.0 | 2 | 0.00 | 0 | 0 | 0 | 0.0 | 0.00 |
| 22 | TestSurface | 0.0 | 3 | 0.00 | 0 | 0 | 0 | 0.0 | 0.00 |
| 23 | TestQuickFix | 0.0 | 15 | 0.02 | 0 | 0 | 0 | 0.0 | 0.00 |
| 24 | TestSqlEmitters | 1.0 | 0 | 0.03 | 0 | 0 | 0 | 0.0 | 0.00 |
| 25 | TestRTag | 1.0 | 0 | 0.03 | 0 | 0 | 0 | 0.0 | 0.00 |
| 26 | TestInterfaceKey | 1.0 | 11 | 0.04 | 0 | 0 | 0 | 0.0 | 0.00 |
| 27 | TestFlatteners | 2.0 | 0 | 0.05 | 0 | 0 | 0 | 0.0 | 0.00 |
| 28 | TestLenses | 2.0 | 0 | 0.05 | 0 | 0 | 0 | 0.0 | 0.00 |
| 29 | TestMarkdown | 2.0 | 1 | 0.05 | 0 | 0 | 0 | 0.0 | 0.00 |
| 30 | TestSigEntailDiff | 1.0 | 17 | 0.05 | 0 | 0 | 0 | 0.0 | 0.00 |
| 31 | TestLegend | 2.0 | 3 | 0.06 | 0 | 0 | 0 | 0.0 | 0.00 |
| 32 | TestStreamTUtils | 2.0 | 4 | 0.06 | 0 | 0 | 0 | 0.0 | 0.00 |
| 33 | TestConstraints | 2.0 | 8 | 0.07 | 0 | 0 | 0 | 0.0 | 0.00 |
| 34 | TestErmineLegends | 3.0 | 0 | 0.08 | 0 | 0 | 0 | 0.0 | 0.00 |
| 35 | TestNewPipeline | 2.0 | 19 | 0.09 | 0 | 0 | 0 | 0.0 | 0.00 |
| 36 | TestGraph | 5.0 | 0 | 0.13 | 0 | 0 | 0 | 0.0 | 0.00 |
| 37 | TestEditorBuffers | 2.0 | 46 | 0.14 | 0 | 0 | 0 | 0.0 | 0.00 |
| 38 | TestPersistence | 7.0 | 0 | 0.18 | 0 | 0 | 0 | 0.0 | 0.00 |
| 39 | TestSigEntail | 5.0 | 26 | 0.20 | 0 | 0 | 0 | 0.0 | 0.00 |
| 40 | trace-ab | 26.7 | 38 | 0.28 | 0 | 0 | 0 | 0.0 | 0.00 |
| 41 | TestNamedFields | 12.0 | 12 | 0.36 | 0 | 0 | 0 | 0.0 | 0.00 |
| 42 | TestLetSignatures | 13.0 | 15 | 0.41 | 0 | 0 | 0 | 0.0 | 0.00 |
| 43 | TestRunner | 15.0 | 5 | 0.41 | 0 | 0 | 0 | 0.0 | 0.00 |
| 44 | TestRowRefusals | 15.0 | 13 | 0.46 | 0 | 0 | 0 | 0.0 | 0.00 |
| 45 | TestStatementExtents | 16.0 | 15 | 0.50 | 0 | 0 | 0 | 0.0 | 0.00 |
| 46 | TestJson | 18.0 | 9 | 0.52 | 0 | 0 | 0 | 0.0 | 0.00 |
| 47 | TestDecode | 21.0 | 0 | 0.54 | 0 | 0 | 0 | 0.0 | 0.00 |
| 48 | TestWidgets | 21.0 | 0 | 0.54 | 0 | 0 | 0 | 0.0 | 0.00 |
| 49 | TestSchema | 26.0 | 6 | 0.72 | 0 | 0 | 0 | 0.0 | 0.00 |
| 50 | TestScopes | 28.0 | 9 | 0.80 | 0 | 0 | 0 | 0.0 | 0.00 |
| 51 | TestSurfaceParsers | 23.0 | 37 | 0.88 | 0 | 0 | 0 | 0.0 | 0.00 |
| 52 | TestLoopTrace | 10.0 | 154 | 0.90 | 0 | 0 | 0 | 0.0 | 0.00 |
| 53 | TestRecordPrims | 37.0 | 2 | 0.97 | 0 | 0 | 0 | 0.0 | 0.00 |
| 54 | TestSurfaceCache | 56.0 | 16 | 1.70 | 0 | 0 | 0 | 0.0 | 0.00 |
| 55 | TestInterfaceConcreteRow | 83.0 | 14 | 2.46 | 0 | 0 | 0 | 0.0 | 0.00 |
| 56 | perf-bench | 160.0 | 72 | 3.20 | 0 | 0 | 0 | 0.0 | 0.00 |
| 57 | TestTolerantRead | 85.0 | 68 | 3.87 | 0 | 0 | 0 | 0.0 | 0.00 |
| 58 | repl-smoke | 119.7 | 196 | 6.52 | 0 | 0 | 0 | 0.0 | 0.00 |
| 59 | TestReplDifferential | 197.0 | 40 | 7.28 | 0 | 0 | 0 | 0.0 | 0.00 |
| 60 | TestTolerantCheck | 332.0 | 135 | 21.12 | 0 | 0 | 0 | 0.0 | 0.00 |

Reading the table:

- **`sql-render` and `sigentail-survey` rank high because they are probes.** They are run when someone
  already suspects a specific feature, and their rate reflects that selection. They are instruments, not
  gates.
- **Small denominators are noisy.** `TestInterfaceRoundTrip` ranks first on a score of 1.5 in 0.07
  machine-hours. That score is one UNSURE real defect plus one harness defect, and it is also the E12 flake.
  Read the score and hours columns together.
- **Suites at rank ties with 0 catches** are ordered by how few hours they cost. The last rows cost the
  most for nothing.
- **Missing rows.** `compile` is a precondition, not ranked: every development compile is also a compile
  "gate" run. The generic `core/test (full)` run is not a row of its own: its catches are the suites'
  catches, and its own record is 6 FLAKE and 2 SELF-DEFECT.

## 4. Ritual, not load-bearing

Named explicitly, with the evidence that puts each one here.

| gate | runs in window | machine-hours | real catches | evidence it is ritual |
|---|---:|---:|---:|---|
| `repl-smoke.sh` | 196 | 6.5 | 0 | Every commit to `tracker/repl-tests` only adds lines, so no golden was ever rewritten and no red was ever resolved. Its only recorded defect is its own: from a worktree it tested the main checkout's build, "so my 8/8 PASS … was vacuous" (SIG-1-SURVEY.md:702). A Scala 3 regression was "missed" by it and caught by `TestErmine` (06-tests.md:59). |
| `TestLoopTrace` (as a gate) | 146 targeted + 181 full | see table | 0 | Three SELF-DEFECTs: a compiler-side failure read as PASS (L4 F1), a gate-side Lean bug, and skip-as-pass (§2.1). The one solver bug in its territory, PANIC3, was found by the L5 witness hunt, "not by this property". |
| `perf-bench.sh` | 72 | 3.2 (estimate) | 0 | Never moved ("UNMOVED" in every recorded A/B). It refuses whenever any ermine JVM is alive (§2.5). Five SELF-DEFECTs. Its one attributed catch was measured by a replica because it refused. |
| `trace-ab.py` | 38 | 0.3 | 0 | Its record is one SELF-DEFECT (it compared 6 of 16 record kinds) and two expected changes. It is an A/B instrument with no per-content verdict. |
| `looptrace-corpus.sh` | 49 | 16.3 | 0.5 (UNSURE: flag-OFF code) | 20 minutes per run. It cannot fail (§2.2). Its one UNSURE catch was a disagreement in code behind a default-OFF flag. Kept nightly as the only full-corpus model agreement, but near-ritual on this evidence. |
| `Audit.lean` | 292 | 0.2 | 0 | Every recorded run reads "0 non-standard". It is cheap (2.3 s), so it stays inside the `lean` gate. |
| `lake build` (full) | 129 | 8.4 | 0.5 (UNSURE, a proof broke) | Its one red was a Lean proof, not product code. It matters only when `tracker/lean` changes, so it is keyed by that subtree. |
| `TestTolerantCheck` | 135 targeted + 181 full | 21.1 | 0 | The most expensive suite (332 s alone). Its record is one FLAKE (the E11a ceiling pin, re-run rather than fixed) and two WRITTEN-WITH-FIX regression tests. No pre-existing property ever caught anything. |
| `TestReplDifferential`, `TestTolerantRead`, `TestInterfaceConcreteRow`, `TestSurfaceCache` | see table | 7.3, 3.9, 2.5, 1.7 | 0 | The next most expensive zero-catch suites (197 s, 85 s, 83 s, 56 s alone). |
| 21 suites with no event of any kind | inside 181 full runs | see table | 0 | Listed in `history-suites.md` §1. That includes five that never compile (§2.4), and 12 never mentioned in any tracker. |
| `bitbucket-pipelines.yml` | 0 | 0 | 0 | §2.7. |
| instruments `keptdef-sweep`, `splitkey-sweep`, `res-guard-bench`, `splice-audit`, `corpus-experiments`, `lsp-demo` | 13 (sweeps) | small | 0 | Measurement instruments, never gates. |

**Load-bearing on the evidence:**
- **Gates:** `corpus` (0.85 catches/hour), `g1-validate` (0.67/h; its baseline-drift check, not the
  double-run self-agreement), `TestStage1Pins` (3 sure catches, 5.3/h), `TestErmine` (2, 12.3/h) and
  `TestRenamer` (1, 0.77/h).
- **On the 2.11 line:** that line's own suite run.
- **Instruments:** `ei-diff` found two real signature regressions, at 15 minutes a run.
- **`lsp-smoke`:** cheap and guards a tool in daily use, but its one catch is UNSURE (a reviewer's probe
  found it). Its blind spots are documented: "every fixture in lsp-tests is a file the resident session
  has never heard of".

The mutation harness (policy §5) tests the forward-looking half of this: whether a gate *would* catch a
defect in the code it claims to guard, which the record cannot show for a gate that never had the chance.

## 5. Limits

- **Undercounted catches.** Catches come from what people wrote down. A red fixed without a message
  saying which gate went red is invisible, which undercounts every gate. The 2015-2019 upstream history
  has no CI logs, so it is surely undercounted.
- **Agent-written reports.** The 2026 attributions come from reports written by the agents doing the
  work. Where a commit corroborated them, they were taken at face value.
- **Run counts.** They exclude anything the user ran by hand, and count aborted runs as full runs.
- **Costs are from one day on one machine.** Under the parallel load this project normally runs with,
  `core/test` has taken 4 to 20 minutes (SUBSUME-M2.md), so the absolute hours carry roughly 2x
  uncertainty. The ordering is far less sensitive: the top and bottom of the table differ by orders of
  magnitude.
- **The weights are a choice.** UNSURE counts as half and GATE-DEFECT equals REAL-DEFECT. With UNSURE at
  0 or 1, the ritual list is unchanged, because every row on it has zero sure catches.
