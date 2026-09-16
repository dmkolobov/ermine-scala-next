# Gate policy (adopted 2026-09-08, the user's decision)

Why: an audit of the loop-model programme's gates (2026-09-08) found the model differential, the Lean build +
audit, the corpus batch verdicts and targeted adversarial probes doing the real work, the perf bench never moving
(machine drift 10.9-13.9 s exceeds any plausible effect), the interface sweep skipping half the corpus with a noise
floor as large as its signal until fixed (F3 N-4), and every stage running its gates THREE times (implementer,
reviewer, orchestrator). This replaces "re-measure rather than inherit" as applied to every figure at every step:
re-measurement applies to the numbers that go into the trackers, once, by the reviewer.

## Tiers

**Tier 0 — always, every stage, before any commit (about five minutes).**
- `sbt core/compile core/copyResources` (compile alone does NOT copy the stdlib `.e` into the target tree).
- `sbt 'core/testOnly *TestLoopTrace'` 720/720 (the model-agreement invariant; ten seconds).
- `tracker/tools/corpus-run.sh --batch` verdicts (85 / 69 / 0 over 154 as of F3; forty seconds).
- If any Lean changed: `cd tracker/lean && lake build` (full default target) and `lake env lean Audit.lean`
  (count, 0 non-standard), `#print axioms` for every new or changed declaration.
- `tracker/tools/repl-smoke.sh` and `tracker/tools/lsp-smoke.sh`.

**Tier 1 — when the solver, the row trace, `Type.scala`'s constraint construction, or executable Lean changes.**
- The 18-group differential `tracker/tools/looptrace-corpus.sh` (now replays groups in parallel, `LOOPTRACE_PAR`,
  default 3: about fifteen minutes instead of forty; `Wide` alone is a fifteen-minute model replay).
- The per-group trace comparison against a pre-change run with `tracker/tools/trace-ab.py` (ALL record kinds).
- The interface sweep `tracker/tools/ei-diff.sh --batch` with `-Dermine.loadInSeries=true` on BOTH sides (or
  `--snapshot` for two builds), classified with `ei-classify.py`; the tool hoists all six group libraries.
- `tracker/tools/g1-validate.sh` (the checked-in `tracker/g1-baseline` signature drift check, 9 checks). Added
  2026-09-09 after the S5 review found it red since F3 with nobody running it: it was in no tier. An INTENDED
  signature change refreshes the baseline in the same commit, with the before/after listed in the stage report.

**Tier 2 — adoption commits only (a default flips or shipped behaviour changes).**
- `sbt core/test` in full (939 total after F3; the documented quarantines below are the only allowed misses).
- `tracker/tools/perf-bench.sh batch -n 3` as an INTERLEAVED A/B (old / new / old / new), each side waiting for
  load < 1.3; never a single-side figure, never under load. Not a per-stage gate.

## Who runs what
- The implementer runs the tier its change needs and reports every number.
- The reviewer re-runs that tier once; its numbers are the ones that go into the trackers.
- The orchestrator runs Tier 0 before the commit and re-runs only what the review disputed. NO third full run.

## Quarantines (a green suite must mean green)
- `TestConstraints."disjunction sound"`: generator starvation (0 passed / 501 discarded, every run on record);
  the rule ships OFF. Registered only under `-Dermine.test.disjunction=true`; ticket D3.
- `TestInterfaceRoundTrip`: passes alone; fails roughly one full run in ten when ANOTHER SUITE in the same JVM
  repopulates the process-global `Session.depCache` between the property's clear and its warm load — intra-run
  cross-suite parallelism, not an external process (corrected 2026-09-11 after the third sighting, LSP Stage 4
  item 7.1b's review R-5; the 6.0 determinism fix was for a different flake). Ticket E12. Not quarantined: a
  Tier-2 red that is exactly this property gets ONE re-run, per the standing rule.
- `TestLegend."extra args are ignored"` (writers): a seed-dependent date-formatting flake, ~1 run in 3 alone
  (S2 review V-4; 7.1b's Tier 2). Ticket E13. Same rule: exactly this property red gets ONE re-run.
- `TestTolerantCheck."E11a: four cold checks of one module publish ONE form per constraint set"`: the published
  constraint SET of `reportFor` is run-to-run nondeterministic on an UNCHANGED tree (isolated runs 2026-09-16 gave
  SET 6 / 6 / 5 and KIND 2 / 3 / 2), so its ceiling-3 pin trips now and then -- seen at the J3b landing as
  "SET class grew past its ceiling 3: (reportFor,4)", green on re-run 3/3. The FORM half (0 splits) is the real
  assertion and has never tripped. Ticket E11b (the entailment oracle that deletes the residual), drafted and PARKED
  by the user (LSP-ROADMAP.md): do not "fix" it here. Same rule: exactly this property red gets ONE re-run.

## Standing rules that stay
Never commit red. Never `lake build` while a `looptrace` binary runs.

## Parallelism rules (the user, 2026-09-11: "We pretty much want the *opposite* in most cases: maximum
## parallelism for quick turnaround")
- DEFAULT IS PARALLEL. Agents, JVMs, sbt invocations and corpus runs all run concurrently. Independent
  stages of different programmes run at the same time in their own worktrees. The implementer of stage
  N+1 may start while the reviewer of stage N runs whenever N+1 does not build on N's code.
- The ONE exception: a timing that will be written into a tracker (interleaved perf A/B, an editor latency
  figure) runs alone, briefly, and says so. Everything else tolerates contention.
- Corpus verdicts via `corpus-run.sh --batch` (about 20 s a side); split a per-file run across parallel
  shells when one is really needed (a baseline being recorded), never serially.
- Split suites across parallel sbt invocations rather than chaining them in one; or run the full
  `core/test` once per LANDING and nothing else, never both.
- A reviewer reads the implementer's gate logs (cite the path) and re-runs only the targeted suites for
  the code under review plus anything it disputes. Never a whole-corpus or whole-suite re-run for a review.
- Briefs state a wall-clock budget (hours), and an agent that reaches it writes up and stops.
- In a WORKTREE: `tracker/repl-classpath.txt` is checked in with absolute paths into the main checkout, and
  `repl-smoke.sh`, `g1-validate.sh`, `lsp-smoke.sh`, `g1-diff.sh`, `perf-bench.sh` read it -- regenerate it
  from the worktree's `target/ermine-classpath` (do not commit the result) or the gate tests the wrong build.
