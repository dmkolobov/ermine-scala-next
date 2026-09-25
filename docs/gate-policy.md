# Gate policy

Adopted 2026-09-17. It replaces the tiers in `tracker/GATE-POLICY.md` (2026-09-08), which stays as history.
The evidence for every decision below is in `docs/gate-audit.md`. The executable form of this policy is
`scripts/gates.sh` (the registry) and `scripts/gate.sh` (the runner).

## 1. The rule: a gate never runs twice on the same content

`scripts/gate.sh run <gate|tier>` caches every PASS and FAIL in `.gate-cache/` at the main checkout's root.
Every worktree shares that cache.

- **Key.** The key is the content SHA plus the gate name.
  - The content SHA is the tree SHA of the working tree, including uncommitted and untracked (not ignored)
    files. A commit has exactly one tree, so this satisfies "never twice for the same commit SHA".
  - It also means a run made *before* `git commit` is the run for the commit that follows. An amend or
    rebase that leaves the content unchanged re-uses the result. Keying by commit SHA would instead force
    either committing untested content or testing the same content twice.
  - A gate that reads only part of the tree declares `GATE_KEYPATH` and is keyed by that subtree. Today
    that is only `lean`, keyed by `tracker/lean`.
  - A gate whose answer also depends on state OUTSIDE the tree declares `GATE_KEYFN`, a function whose
    output `gate.sh` hashes into the key (empty or failing: content alone). Today that is only `db`,
    keyed also by ErmineSales's loader stamp (tier, seed, manifest sha256), so reloading the
    database is a new key and the same load is not re-run. The SQLite twin is NOT hashed: the gate
    builds it itself from tier xs, a pure function of the tree's generator and contract, so content
    covers it. A key function that fails or prints nothing gives an uncacheable key and no result is
    written (never a silent content-only key).
- **A cached result is final.** `gate.sh` prints it and does not run the gate again. There is no re-run
  flag. To get a different answer, change the content.
- **UNAVAILABLE is not a result.** The gate did not run (e.g. no Lean binary built from this tree's
  `tracker/lean`), so nothing is cached.
- **Concurrent requests are locked.** A second request for the same key and gate while one is running
  exits 6 instead of running a duplicate.
- **Out of the key, but recorded.** The toolchain and the Lean binary are not part of the key. Each result
  file records them.
- **Environment-dependent checks are not gates.** A check whose answer depends on machine load (timings,
  perf) cannot obey this rule, so it is an instrument (§4).

Consequences, which replace rules in the 2026-09-08 policy:

- **No flake re-runs.** The old "exactly this property red gets ONE re-run" allowance is gone, because a
  re-run is a second run on the same content. A property known to be flaky does not belong in a gate.
  - It is registered only under `-Dermine.test.flaky=true`, next to its ticket, the way
    `disjunction sound` has been registered only under `-Dermine.test.disjunction=true`.
  - It is fixed on its ticket and then returns to the gate. Anyone can run it with the flag; that run is
    an instrument, never a verdict.
  - A property shown to be flaky moves behind the flag in the commit that shows it. "Shown" means the same
    content gave both answers, and the commit message names both logs.
- **Nobody re-runs a gate.** Implementers, reviewers and orchestrators all cite `scripts/gate.sh status
  <commit>` and the log path it prints.
  - A reviewer who doubts a result reads the log, or writes a probe. A probe is an instrument, not a gate.
  - This replaces "the reviewer re-runs that tier once".
- **"Never commit red" is mechanical.** Run `scripts/gate.sh run commit` on the tree you are about to
  commit. It must print PASS or CACHED-PASS for every gate.

## 2. Tiers

A higher tier includes every gate of the tiers below it.

| tier | when | gates | wall clock (measured 2026-09-17, cold cache) |
|---|---|---|---|
| **commit** | before every `git commit` | `compile`, `corpus`, `lsp` | ~2.5 min: compile 5 s incremental / 74 s clean, corpus 42 s, lsp 47 s (640 checks; MEASURED 2026-09-20 after WP-5 stage C added the preview section to `lsp-client.py` -- 44 s / 628 checks before it) |
| **pr** | on the merge result, before a branch lands on `json-encode` or `scala3-migration` | + `suites`, `lean`, `db` (added 2026-09-24, DB-PLAN S1; not in the measured wall clock) | + ~15 min: suites 11.3 min, lean 3.9 min (cached while `tracker/lean` is unchanged) |
| **nightly** | on the tip of each live line | + `looptrace-corpus` | + ~20 min |

Why each gate is where it is (catch rates are real defects caught per machine-hour; see the audit):

- **commit.**
  - `corpus` has the best catch rate of any required gate (0.85/h).
  - `lsp` is cheap and guards the editor that is in daily use.
  - `compile` is the precondition for everything else.
- **pr.**
  - `suites` holds every per-suite catch in the window: 7 real defects (2 UNSURE) and 5 harness defects
    (1 UNSURE).
  - `lean` only matters when `tracker/lean` changes, and its subtree key makes it free when it has not.
  - `db` (2026-09-24) runs `TestMsSqlSmoke` and `TestDbReports` against the local SQL Server
    (`scripts/db.sh`) and the SQLite twin. Without `ERMINE_DB_*` those suites register nothing inside
    `suites` and print a "DB suites: not requested" line, so `suites` stays free of SKIPPED; `db` FAILS
    if that line reaches its own log. UNAVAILABLE, like `lean`, when the container is down, ErmineSales
    is not at tier xs, `data/node_modules` is absent or another sbt is running; it BUILDS the SQLite twin
    itself (tier xs, into its own directory) rather than reading the gitignored `data/out/`. No catch
    record yet.
- **nightly.**
  - `looptrace-corpus` is the only full-corpus model agreement, but at 20 min it caught 0.5 defects in
    16 machine-hours, and it missed both mutants it was given (E20 owes it a seed-drawn run; under
    2 of 4 it goes).
- **deleted 2026-09-17,** on the mutation evidence (`docs/gate-audit.md` §6):
  - `repl` (`repl-smoke.sh`): zero catches on record in 196 runs (6.5 machine-hours), 1 of 4 mutants.
  - `looptrace` (a standalone `TestLoopTrace` run): zero catches in 146 runs, 2 of 4 mutants, and
    redundant — `TestLoopTrace` runs inside `suites`, where a SKIPPED line is a FAIL.
  - `g1` (`g1-validate.sh`): 0 of 8 mutants, in two different scopes. Its two real catches on record
    both came from comparing two builds during an intended change, which is instrument use. Ticket E19
    is the fix that would make it a gate again: record the baseline over `core/examples` too.
  All three stay in `tracker/tools` and anyone can run them; they are just not required, and a green
  one is not evidence.

The 2.11 line (`backport-2.11`, `json-encode-2.11`) has its own toolchain. Its full `core/test` (193 s) is
that line's `pr` gate, run through `backport/env-2.11.sh`. It is not in this registry.

## 3. Budgets

- **commit tier:** 3 min on a warm tree. A gate that would push it past that goes to `pr`.
- **pr tier:** 20 min.
- **Adding a gate:** a new gate enters at `nightly` and moves up on evidence, meaning a recorded catch or a
  mutation score.
- **Ask first:** a gate whose single run exceeds 20 min needs the user's approval before it is added to
  any tier.
- **One heavy gate at a time.** `suites` and `looptrace-corpus` each hold several GB. Running both at
  once on this machine (15 GB) let the kernel OOM-kill the user's language server on 2026-09-17. The
  harness waits for `MUTATE_MIN_MEM_GB` (default 6) free before each build and each gate, and heavy
  gates run with `--lanes 1`.

## 4. Instruments are not gates

These answer a question about a change and put their numbers in the change's report. They are never
required and never cited as gate evidence:

- `ei-diff.sh` + `ei-classify.py`: A/B of published signatures under two flag settings or two builds.
- `trace-ab.py`: compiler-vs-compiler trace A/B.
- `perf-bench.sh`: interleaved perf A/B. It refuses to run while any ermine JVM is alive, the user's
  editor included, and it has never moved in the record.
- `g1-validate.sh` / `g1-diff.sh`: stdlib signature drift against `tracker/g1-baseline` (E19).
- `repl-smoke.sh`: REPL transcripts against `tracker/repl-tests/*.expected`.
- `sql-render.sh`, `sigcheck.py` / `sigentail-*.py`, `keptdef-sweep.sh`, `splitkey-sweep.sh`,
  `res-guard-bench.sh`, `splice-audit.sh`, `corpus-experiments.sh`, `lsp-demo.sh`.

Dead, and removed from any notion of a gate:

- `bitbucket-pipelines.yml`: a 2017 Scala 2.12 sample with no record of ever running.
- The five property files that are entirely commented out: `TestRelations.scala`, `TestAccess.scala`,
  `TestWriters.scala`, `TestAmalgamation.scala` and `TestKeyValueTabular.scala`. They compile to nothing
  and run nothing.

## 5. Gates must catch their mutants

Every gate that declares a mutation scope (`GATE_SCOPE` in `scripts/gates.sh`) must catch the mutants
`scripts/mutate-and-verify.sh` injects into that scope.

- **Bug classes:** off-by-one, swapped operands, removed guard, reordered map keys.
- **Survivors:** a surviving mutant is a silently broken gate. The gate is fixed, meaning a check is added
  that catches that mutant, or it is deleted.
- **Equivalent mutants:** a mutant shown not to change behaviour is listed in
  `scripts/mutations.equivalent` with the reason. It is never used to wave a survivor through.
- **When to run it:** whenever a gate's definition or scope changes, and in the nightly job with a new
  seed.
- **A gate's scope is what it can SEE, not what it runs over.** `g1` boots the stdlib, and the stdlib
  has no concrete-label row constraints, so row-solver mutants are invisible to it: its scope excludes
  `Constraints.scala`, and the corpus gate (which loads `core/examples`, 39% of whose solve inputs
  carry a concrete label) owns that code instead.
- **Not mutation-tested:** `compile` (a type-correct mutant compiles by construction) and `lean` (the
  operators are Scala-only). Each says so in the registry.
- **Scores, 2026-09-17** (one mutant per class per gate, seed 1; `docs/gate-audit.md` §6):
  corpus 2/4 (+1 equivalent), lsp 3/4 (+1 equivalent), suites 3/4. The gates that could not catch their
  own mutants were deleted. Every remaining survivor is listed in `scripts/mutations.equivalent` with
  its reason or ticketed in `tracker/TICKET-stdlib-findings.md` (E17, E18, E19).

## 6. What changed from 2026-09-08

| 2026-09-08 | now | why (audit section) |
|---|---|---|
| Tier 0 = compile, TestLoopTrace, corpus, Lean, repl-smoke, lsp-smoke, every commit | commit = compile, corpus, lsp | TestLoopTrace and repl-smoke: zero catches on record (§3); TestLoopTrace also SKIPPED as PASS wherever the Lean binary was absent (§4.1) |
| Tier 1 = looptrace-corpus, trace-ab, ei-diff, g1 when the solver changes | pr = suites, g1, lean; nightly = looptrace-corpus | trace-ab and ei-diff are A/B instruments with no per-content verdict; looptrace-corpus has a 0.03/h catch rate at 20 min |
| Tier 2 = full core/test + perf A/B on adoption commits | full core/test on every pr; perf is an instrument | every suite catch in the record came from a full or targeted suite run; perf never moved and cannot run while the editor is open |
| implementer runs, reviewer re-runs once, orchestrator runs Tier 0 | one run per content, cited from `.gate-cache/` | the no-re-run rule |
| one re-run for a quarantined red | flaky properties are registered only under `-Dermine.test.flaky=true` until fixed | the no-re-run rule |
| corpus verdicts read by a human against "85 / 69 / 0" | `corpus` compares every module's verdict and refusal text with `tracker/corpus-verdicts.expected` | a count can stay equal while verdicts swap; two runs of one build gave 0 message differences over 168 modules (§4.3) |
| looptrace-corpus.sh read by a human | the gate fails unless all 18 groups agree with 0 skips | the script exits 0 whatever the replay found (§4.2) |
