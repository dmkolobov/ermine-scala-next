# Brief: A1 — ADOPTION: flip the three defaults (rowSound ON, dequeuePolicy=smallcanon, solveBudget=20000)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, CLEAN at `c0221fc` (S2 and D1
committed with every flag default OFF). USER'S DECISION (2026-09-06 17:00): "Let's do 20,000" — adopt the
recommended set: `-Dermine.rowSound` default ON, `-Dermine.dequeuePolicy` default `smallcanon`,
`-Dermine.solveBudget` default `20000`. This stage flips the defaults, re-runs the FULL gate set at the new
shipped configuration, and reports; the orchestrator commits on a green report and a reviewer's ADVANCE.
Toolchains: Scala `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
Lean `export PATH=$HOME/.elan/bin:$PATH` in `tracker/lean/` (`LEAN_NUM_THREADS=2`); sbt allowed; one JVM at a
time with `-XX:ActiveProcessorCount=2`; long runs under `setsid nohup` with a log (background shells are capped at
ten minutes); `pkill -f` matches itself (kill by PID); disk tight (gzip traces; `.ei` sweeps write under
`core/examples` — clean up what you cause); no commits.

READ FIRST: `tracker/loopmodel/S2-FIX.md` (§1 flag layout, §2 gates, the post-review subsections),
`tracker/loopmodel/D1-CHANGE.md` (§1 the flags, §2 gates, §8 post-review incl. U-0 and the budget-requires-policy
rule), `tracker/loopmodel/D1B-REVIEW.md` §"adoption recommendations", `tracker/ROW-CONSTRAINT-STATE.md` (the S2
and D1 sections: what is proved, what the gaps are), and the earlier ADOPTED flips for the gate convention
(`tracker/satterm/KEYED-SPLIT-STAGE2.md`; the `ADOPTED` comments in `Constraints.scala` for `splitKey`/`splitRow`/
`resRow`). Gate scripts to reuse: S2's under `/home/dmitry/.claude/jobs/880c725d/tmp/S2/`, D1's under
`/home/dmitry/.claude/jobs/880c725d/tmp/D1/` (`COMMANDS.md`, the drivers, `einorm3.py`, `bindcmp.sh`),
`tracker/tools/{looptrace-corpus.sh,perf-bench.sh,repl-smoke.sh,lsp-smoke.sh,corpus-run.sh,ei-diff.sh}`.

## What to change

A1.1 **Scala defaults** (`Constraints.GenRules`): `rowSound` (and its sub-flags as S2 defined them) default true;
     `dequeuePolicy` default `"smallcanon"`; `solveBudget` default `20000` (the budget-requires-policy rule stays:
     `-Dermine.dequeuePolicy=shipped` on the command line still turns the budget off with the warning). Mark each
     with an `ADOPTED 2026-09-06` comment in the style of the earlier flips, naming the evidence documents. The
     rule fingerprint (`GenRules.toString`) now includes the tokens at defaults — say what the new default string
     is; every `.ei` will regenerate.
A1.2 **Model defaults** (`tracker/lean/Rowpartition/Loop/State.lean`'s `Flags`, `Policy`/`budget` defaults in the
     drivers, `Loop/Main.lean`'s `--flags` parsing, and `Json.lean`/`Seed.lean` if they build a `Flags`): the model's
     defaults must equal the compiler's, so that a `json:` seed run and `TestLoopTrace`'s forwarding agree at
     defaults; the `sin` record already carries the effective policy/budget/rowSound settings for replays. Add the
     OFF tokens (`norowsound`, `pol:shipped`/`--policy=shipped`, `--budget=0`) if they do not exist, so the OLD
     configuration stays reachable on both sides. No theorem statement changes (they take the flag settings as
     hypotheses); rebuild + audit (start figures: 867 jobs, 4115 theorems / 0 non-standard axioms, looptrace 1670).
A1.3 **TestLoopTrace**: forwarding must map the new defaults correctly in both directions (a `-Dermine.rowSound=false`
     or `-Dermine.dequeuePolicy=shipped` on the command line reaches the model as the corresponding OFF token).

## Gates, ALL at the NEW shipped configuration (no flags on the command line), with the OLD configuration
## (`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`) as the control where a before/after is meaningful

A1.4 `core/test` (913/914 known: `Constraints.disjunction sound` starvation); `TestLoopTrace` 714/714 at the new
     defaults AND with the OLD configuration forced (both must agree).
A1.5 The eight-group L2 corpus differential at the new defaults (`-Dermine.loadInSeries=true -Dermine.rowTrace=<file>`
     per group, model `--replay`; the policy/budget/rowSound come from `sin`): 0 skipped / 0 hashdiff / 0 eqdiff;
     report the segment counts next to the OLD configuration's (2,355,430 — the policy changes the counts where
     modules now finish or are refuted earlier; explain every difference).
A1.6 Corpus verdicts: `tracker/tools/corpus-run.sh --batch` (and `--incomplete --batch`), new vs old: list EVERY file
     whose verdict changes, with the reason (expected: `incomplete/gu05` and its four successors now LOAD in the
     batch; nothing else; any REJECTED→LOADED or LOADED→REJECTED beyond that is a finding).
A1.7 `.ei` sweep at the new defaults vs the OLD (`-Dermine.loadInSeries=true`, the deterministic loader; compare
     with D1's `einorm3.py`, up to `Set` order): every interface either identical, alpha-equivalent (say how many),
     or NEW (the six policy-only ones); "0 signatures weaker"; plus the standard `ei-diff.sh` output. Also confirm
     the fingerprint change forces regeneration (an old `.ei` is not reused).
A1.8 Seeds at the new defaults: all `seeds/*.json` (19) × 10 bases — verdicts and substitutions vs the OLD
     configuration (`bindcmp.sh`, fixed version): expected SAME except the known U-0 rows now REJECTED under
     rowSound; all `seeds/unsat/*` × 10 bases: 0 SOLVED; `seeds/slow/GU05.json` × 25 bases: 306 draws each, ~1 s;
     `GU05MIN` 256; the S2 `run.sh env` gate (`cases=9 differ=0` at the new defaults); B1's PANIC3 100/100 bases;
     the budget never fires on any tracked or hunt seed (round-8 hunt seeds, 3,840 × 3 bases: all SOLVED, 0 limit
     hits, substitutions identical to the OLD configuration except where U-0 applies — they are satisfiable so
     none should).
A1.9 Performance: `tracker/tools/perf-bench.sh batch -n 5` new vs old, alternated, load recorded (the P1 baselines;
     the host is a desktop — say whether the comparison is meaningful); `gu05`'s per-file load time new vs old;
     the decision's per-solve maximum on the corpus (S2's instrument) at the new defaults.
A1.10 `repl-smoke.sh` and `lsp-smoke.sh` at the new defaults; the LSP/REPL must show the budget diagnostic and
     the soundness refutation as ordinary diagnostics (run one of each: `seeds/unsat/MIN2` as a module if the
     harness allows, or state how a user would see them).
A1.11 Docs: `tracker/ROW-CONSTRAINT-STATE.md` (a dated ADOPTED section: the three defaults, the gate results, how to
     get the old behaviour back, the open gaps — no `.ei` cache key for the flags, no a-priori fuel number, the
     budget diagnostic's severity); `tracker/PERF-ROADMAP.md` P10 ticked with the adoption; the plan (an A1 section
     + status row); `tracker/lean/README.md`; `tracker/loopmodel/A1-ADOPTION.md` as the report (every gate with
     its command and numbers; anything not green stated plainly).

Outcomes, say which: (GREEN) every gate green, ready to commit; (RED) a gate fails — do NOT work around it: report
the failure with the seed/file and stop. Constraints as always: no silent weakening, never `lake exe cache get`,
no new `require`, no new project, never touch `~/research/leanwork`, `CutSearch.lean` out of the root import list,
audit 0 non-standard axioms. Report early and keep it current.
