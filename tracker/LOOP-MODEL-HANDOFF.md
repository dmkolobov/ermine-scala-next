# Orchestrator handoff — state of the world, 2026-09-04

For whoever orchestrates `tracker/LOOP-MODEL-PLAN.md` next (a new session, a different model, or
this session after compaction). Read this, then the plan, then the memory index. Everything
durable is on disk; nothing lives only in a conversation.

## Where things stand

* **Committed on `scala3-migration`** (newest first): `2411296` Stage 6 (`KeyedEmpty.lean`),
  `39d2e5b` Stage 5 + adoption of `splitRow`/`resRow`, `939c2aa` loader batch-load fix,
  `98e7bf2` Stage 4, `e47a3ae` Stage 3, `d736bf9` correspondence lemma, `1e6f52b` adoption of
  `splitKey`, `94a2074`/`d30c4de` the Lean modules and harnesses. Shipped defaults:
  `cut+label-early+resguard+splitkey+splitrow+resrow`.
* **Uncommitted in the main checkout** (9 entries): Stage 7 — the `emptyRow` flag, DEFAULT OFF,
  with `KeyedEmptyScala.lean`, `seeds/G7.json`, `KEYED-EMPTY-STAGE7.md`, ticket §3j, state-file
  paragraph, README, `keptdef-mints.py`. All gates green except gu05 1.9× slower. The USER has
  not decided whether to commit it; ask before committing. Plus the loop-model files L1 adds.
* **Worktree `~/research/ermine/ermine-scala-wt-prof`** (branch `emptyrow-profiling`, no
  commits): Stage 7 + the Stage 7b variant (guard resolution's empty branch: reuse only if it
  adds a fact, else the shipped mint) + `KEYED-EMPTY-STAGE7B.md`. Variant diff also at
  `~/.claude/jobs/880c725d/tmp/stage7b-variant.diff`. Verdict so far: the regression is the
  branch's intended effect (the suppressed mint was the queue's GC); the variant restores 1.0 s
  but re-opens the empty-row loophole in every order except the loop's; NOT adopted. The
  orchestrator's recommendation to the user was: commit Stage 7 as research with the flag off,
  do an explicit queue-GC performance stage, then re-time Stage 7's proved rule. The user
  answered by starting the loop-model programme instead. Both decisions are still open.
* **Worktree `~/research/ermine/ermine-scala-wt-loader`** (branch `loader-batch-fix`): stale,
  its diff is committed as `939c2aa`; safe to `git worktree remove --force`, ask first.
* **Lean**: build 820 jobs, `Audit.lean` 2378 theorems / 0 non-standard axioms, before L1.

## The programme and its protocol

`tracker/LOOP-MODEL-PLAN.md`: L1 executable loop model → L2 corpus trace equivalence → L3
theorems about the model → L4 trace test in `core/test`. One Opus implementer per stage, then
one Opus reviewer (brief template `~/.claude/jobs/880c725d/tmp/brief-review.md`; the stage
briefs are `brief-L1.md` etc. beside it — copy them into `tracker/loopmodel/briefs/` if the job
directory may be cleaned). A stage advances only on the reviewer's ADVANCE verdict; confirmed
findings go back to the implementer (resumable by SendMessage within the SAME session only —
agents of a finished session cannot be resumed; re-launch with the brief + the report instead).

L1 IMPLEMENTED 2026-09-04 (Opus, ~65 min): `tracker/lean/Rowpartition/Loop/*` (13 files, ~2,500
lines), `lake exe looptrace`, `tracker/tools/looptrace-diff.py`, report `tracker/loopmodel/L1-MODEL.md`.
Orchestrator re-verified: build 832 jobs, Audit 2508/0, looptrace builds, W3/G7/NE6 at bases 3 and 11
agree with the compiler's traces. Implementer's own sweep: 240/240 agree, 60 byte-identical.
L1 REVIEW done (`tracker/loopmodel/L1-REVIEW.md`, 696/701 comparisons agree; verdict FIX-THEN-ADVANCE:
F1 CHAMP inlining in SSet.excl/filter, F2 rightWins early return, F3-F7 docs). Fixes APPLIED by the implementer (SSet.excl/filter re-champ survivors; rightWins takes concat's early
return; 851/851 comparisons agree; 11 regression seeds added under tracker/repro/satterm/seeds/; orchestrator
re-verified build 832 / Audit 2508/0 / LBL, COLL, RR agree). Targeted RE-REVIEW by the same reviewer in
progress (appends a dated section to L1-REVIEW.md with the final verdict); on ADVANCE, launch L2 with
`tracker/loopmodel/briefs/brief-L2.md`. F6 was added to L3's acceptance (iv). If the launching session is gone: read both reports, and if the review verdict
is FIX-THEN-ADVANCE, re-launch an implementer with `briefs/brief-L1.md` + the review's fix list.
L2's brief is not yet written; the plan's L2 section is its specification.

## Standing rules the user set (do not relearn them the hard way)
* Do not commit or merge without asking. Never commit red. Re-measure, never inherit a figure.
* Disk is tight: never `lake exe cache get`, never add a Lean `require`, never create another
  Lean project, never touch `~/research/leanwork`; `Rowpartition/CutSearch.lean` OOMs at 15 GB
  and stays out of the root import list.
* One sbt at a time; never sbt during a `bin/ermine` sweep (the classes change under the JVMs);
  every A/B from ONE compiled class set; `corpus-run.sh` and `ei-diff.sh` never concurrently
  (both delete `.ei` files); batch mode is valid only batch-vs-batch; timing gates on an idle
  machine, one JVM at a time. Background shells in the harness are capped at ten minutes: long
  sweeps under `setsid nohup` with a log and a monitor.
* Label results THEOREM (about a relation, name it) vs MEASUREMENT (about `incorporateAll`,
  name the instrument). State coverage honestly at every flag.
* A guard may replace a mint by a NAME for the same row, never by silence (state file, 2026-09-03).
* `pkill -f` matches its own command line — split the literal.

## Instruments that exist
`tracker/repro/satterm/{run,sweep}.sh` (`json:` seeds, id bases, SOLVED/REJECTED/HANG, draws;
`trace` mode needs `ERMINE_JAVA_OPTS=-Dermine.rowTrace=<file>`), `tracker/repro/crule/`,
`tracker/repro/keepmint/`, `tracker/tools/corpus-run.sh [--batch]`, `ei-diff.sh [--batch]` +
`ei-classify.py`, `corpus-verdicts.py`, `keptdef-sweep.sh` + `keptdef-mints.py`,
`splitkey-counts.py`, `rowclosure.py` (additive explorer + seed generator), `batch-split.py`,
`repl-smoke.sh`, `lsp-smoke.sh`, gate-chain scripts under `~/.claude/jobs/880c725d/tmp/postflip2/`.
