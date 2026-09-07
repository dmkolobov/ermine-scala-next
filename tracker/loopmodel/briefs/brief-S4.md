# Brief: S4 — the projection fan-out cliff: reproduce on the model, explain it, and decide guard vs budget

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the commit the orchestrator
names (S3 and F1 committed; defaults adopted: `rowSound` ON, `dequeuePolicy=smallcanon`, `solveBudget=20000`).
Toolchains: Scala `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time, sbt allowed for gates; Lean `export
PATH=$HOME/.elan/bin:$PATH` in `tracker/lean/` (`LEAN_NUM_THREADS=2`; you may `lake build` if no other agent is
running `looptrace` — check `ps`); long runs under `setsid nohup` with a log; no commits. Part B (a Scala change)
goes behind a flag DEFAULT OFF in a worktree; adoption is the user's.

THE FINDING (ticket B5; `core/examples/Present/ProjectionCost.e`, `Present/shouldfail/proj01_seven_reads.e`,
`core/examples/Lang/ProjectionCliff.slow`; E4-REVIEW M-*, E5 finding 1): N projections `t ! f` of ONE open-row
record parameter in one expression cost 3 / 30 / 212 / 1,232 / 6,804 fresh row variables for N = 2..6 (E5:
0/3/31/207/1,241/6,956; the E4 reviewer's model replay without the budget: 35,923 at N = 7 and 185,848 at
N = 8, i.e. about 5.3-6x per extra read -- so raising the budget cannot keep pace and option (i), the guard, is
the one to prove), every draw a `Resolution` and no split; N = 7 exhausts the adopted 20,000 budget and a
VALID program is rejected with the resource diagnostic. The same reads under one written partition cost 0.
This is the one known shape on which the budget rejects a valid program, and it is a realistic one (a validator
lambda reading five fields of a parameter record). The trace differential already shows the model reproducing
the budget stop at the same count (20,009).

READ: the two example modules and their reports; `tracker/ROW-CONSTRAINT-STATE.md` (the resolution rule, the
`resGuard`/`resRow` guards adopted 2026-09-02/03, and the S2/D1/A1 sections); `Constraints.scala`'s `resolution`
and its guards; `tracker/lean/Rowpartition/Loop/Rules.lean` (`resolution`), `Loop/Depth.lean` (`--depth`),
`Loop/Mints.lean`/`Pump.lean` (the per-key instruments), `ResGuardTerm.lean`/`KeyedRow.lean` (what the guards
prove); `tracker/loopmodel/L5-TERMINATION.md` §R7.3b (the resolution shape: two lone-abstract premises at one
variable with incomparable concrete parts).

## Part A — understand it (Lean model + measurement; no Scala)

A1 Transcode the N = 2..7 ladder into `json:` seeds (`tracker/repro/satterm/seeds/PROJ2..7.json`, from the
   compiler's `sin`/`scon` records) and replay through `lake exe looptrace` with `--depth`/`--mints`/`--cycle`:
   the exact constraint system a projection generates (`Has r f = exists c. r <- (f, c)` per read?), the draw
   ladder on the model, the per-key mint counts (`--mints`, not `--cycle`'s vocabulary size), the chain depth,
   and the rule that fires at every draw. State the mechanism as a formula: why N reads of one record give a
   super-exponential-looking ladder (pairwise resolutions between the N remainder variables c₁..cₙ? each
   resolution minting a new remainder that then resolves against the others?), and what the keyed guards
   (`resGuard`/`resRow`) do and do not catch here.
A2 Where the corpus stands: over the eight old groups plus the five new ones (all wired in
   `looptrace-corpus.sh`), the distribution of "distinct projections of one record variable in one solve"
   (from the `scon` inputs or a static count) and the draws per solve as a function of it — is N = 5..6 present
   in real reports outside the pinned examples? (E4's `ValidationReport` was the cheap case with a concrete
   row.)
A3 Options, each with a Lean statement of what it would make true: (i) a WRITTEN-PARTITION guard — when the
   solver sees k lone-abstract premises `r <- (fᵢ, cᵢ)` at the same `r` with pairwise-distinct concrete parts,
   introduce the single partition `r <- (f₁..fₖ, c)` (one fresh remainder) and reuse it, which is the 0-draw
   form the user could have written (`KeyedSplit`/`resRow` in spirit: "a name, never silence"); (ii) raise the
   budget (what value, from what N; the wall-clock ceiling per solve — D1 measured ~56 s at 20,000); (iii) a
   per-record cap on resolution partners. For (i): the soundness argument (the introduced partition is entailed
   by the premises? or only satisfiability-equivalent — say which, in `Loop/Strict.lean`'s vocabulary), the
   termination argument (does it reduce `drawn`? by how much on the ladder), and the differential consequence
   (a new rule needs a model mirror and a trace record). Recommend one, with the measured ladder under it on
   the model if (i) can be prototyped in the model first (a flag in `Flags`, mirrored later).
A4 Design note `tracker/loopmodel/S4-DESIGN.md`; STOP and report. The orchestrator confirms Part B.

## Part B (only after Part A's go) — the flagged Scala change in a worktree, with the full gate set
(flags OFF byte-identical corpus trace; ON: the ladder on the compiler, the differential with the mirror, the
five example groups' verdicts unchanged, `core/test`, perf-bench, the `Present/ProjectionCost.e` pair
re-measured), report `S4-CHANGE.md`, adoption = the user.

Constraints as always: no silent weakening, audit 0 non-standard axioms if Lean changes, `#print axioms` in
scratch under `/home/dmitry/.claude/jobs/880c725d/tmp/S4/`, report early. Outcomes: (A-done) mechanism +
recommendation; (B-done) flagged change with gates; (NO-GUARD) no sound guard found — budget recommendation with
the number.
