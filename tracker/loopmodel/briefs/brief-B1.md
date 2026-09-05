# Brief: B1 — fix the `makeEmpty` self-propagation panic (found by L5's witness hunt)

## The bug
`tracker/loopmodel/L5-TERMINATION.md` (the "compiler bug" section) and `L5-REVIEW.md` §4: the
satisfiable system `v7 <- (v4, v6)`, `v6 <- (v6, v7)`, `v9 <- (v5, (|l100|))` — tracked from now on as
`tracker/repro/satterm/seeds/PANIC3.json`, copy it from `/home/dmitry/.claude/jobs/880c725d/tmp/L5/min/panic3.json` —
makes the shipped `Subst.solve` die with `panic: reinstantiated type v6 to ConcreteRho(-,Set()) but it
was already bound to ConcreteRho(-,Set())` at 11 of 100 id bases (orchestrator: 5 of 40). ROOT CAUSE
(reviewer, traced at base 6): `Constraints.makeEmpty`'s `aux` (≈ line 1564)

    case RHSAbstr(abstr) => s ++ abstr.map(v => Partition(v, RHSEmpty(), PartitionEmpty))

maps over ALL of `abstr`, including the variable being emptied, so a self-referential definition
`v <- (v, w)` manufactures `v <- ()` again, which is dequeued and calls `makeEmpty v` a second time,
and `instantiateType` dies on the double binding. `selfSubstitution` twelve lines away already uses
`(abstr - v)`. Three of the fourteen panicking hunt seeds have no self-referential INPUT — the shape
is derived (`SplitKeyed`) — so this is reachable on ordinary programs; acceptance of a valid program
depends on how many type variables were allocated earlier. The fix is `abstr.map` → `(abstr - v).map`
at that line (the inner lambda's parameter shadows `v` — rename it). Do NOT uncomment the `warn` case
in `Subst.scala:182`: it is the wrong layer (masks the symptom, and the model's lemmas rely on the die).

## Part A — the Scala fix and its gates, in a WORKTREE (do this now, then STOP and report)
Another agent (L5) is editing the Lean tree in the main checkout; the Lean model must mirror this
fix (Part B) but only after that agent is idle, and the orchestrator will message you to start Part B.
    cd /home/dmitry/research/ermine/ermine-scala
    git worktree add /home/dmitry/research/ermine/ermine-scala-wt-b1 -b makeempty-self-fix HEAD
    cd /home/dmitry/research/ermine/ermine-scala-wt-b1
Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
one sbt at a time; verify with `ps` that your `bin/ermine` runs use the WORKTREE's classes. Never
touch the main checkout in Part A.
1. Apply the one-token fix with a comment citing the seed, the root cause and `selfSubstitution`'s
   precedent; add `PANIC3.json` (with its model in the seed: everything empty except `v9 = v5 ⊎ {l100}`)
   to `tracker/repro/satterm/seeds/`.
2. `sbt -batch core/compile`; `sbt -batch -J-Xmx3g core/test` — expect 913/914 with the known
   `disjunction sound` starvation; `TestLoopTrace` will SKIP in the worktree (no Lean binary there) —
   say so.
3. Seeds: `tracker/repro/satterm/sweep.sh json:…/PANIC3.json 0 99` must be SOLVED 100/100 (was 89/11);
   every other tracked seed (all of `tracker/repro/satterm/seeds/*.json`, incl. `G7`, `LBL`, `COLL`, `D1–D4`
   with their flags per `L1-MODEL.md` §6e) at bases 0–19 must give the SAME verdicts and draw counts
   as before the fix — take the "before" from the MAIN checkout's classes (`bin/ermine` there; read-only,
   `-Dermine.useInterface=false`) and diff; `tracker/repro/crule/sweep.sh W 0 99` and `gseed` REJECTED
   100/100. Also the 14 panicking hunt seeds under `/home/dmitry/.claude/jobs/880c725d/tmp/L5/` (find them
   via `L5-TERMINATION.md`): all SOLVED at every base after the fix; report any that still die.
4. Corpus: `tracker/tools/corpus-run.sh --batch <out>` in the worktree vs a `--batch` run of the MAIN
   checkout's classes (batch-vs-batch is the valid comparison), main 66 and `--incomplete` 34:
   verdicts identical, `shouldfail/` 40/40; per-file re-run for any message difference. Never run
   `corpus-run.sh` and `ei-diff.sh` concurrently.
5. Published types: `tracker/tools/ei-diff.sh` per file, worktree classes vs main classes (read its
   header: the second side is expressed as flags; here the two sides are two class sets, so run one
   side per checkout with the same command and classify with `ei-classify.py`), plus a same-checkout
   control; 0 weaker expected, and any attributable binding hand-classified.
6. `tracker/tools/repl-smoke.sh` and `lsp-smoke.sh` (regenerate `tracker/repl-classpath.txt` for the
   worktree if it points at the main checkout's classes — check).
7. Report `tracker/loopmodel/B1-FIX.md` in the worktree (write EARLY): the diff, the gate table, and
   the exact Lean change Part B needs (read `tracker/lean/Rowpartition/Loop/Step.lean`'s `makeEmpty`
   and name the line), then STOP and return. Delete `.ei` files you create; gzip traces; scratch
   under `/home/dmitry/.claude/jobs/880c725d/tmp/B1/`; no commits; `pkill -f` matches itself.

## Part B — the model mirror and the trace property, in the MAIN checkout (only when told)
1. Mirror the fix in `Loop/Step.lean`'s `makeEmpty` (exclude the emptied variable from the
   propagation), rebuild (`lake build Rowpartition`, `lake env lean Audit.lean` — 0 non-standard axioms),
   fix any L3/L5 lemma the change breaks (report which), `lake build looptrace`.
2. Apply the Scala diff from the worktree to the main checkout (`git -C <worktree> diff | git apply`),
   `sbt -batch core/compile` (check `ps` for running replays first), then `sbt -batch 'core/testOnly
   *LoopTrace*'` — must pass with `PANIC3` in the population (it is under `seeds/`), and the two
   positive controls still detected; then the L1 seed sweep (`looptrace-diff.py --sweep`) and the L2
   corpus replay on the `top` group (`looptrace-corpus.sh`) — 0 differing.
3. Full `sbt -batch -J-Xmx3g core/test` in the main checkout: 913/914.
4. Update `tracker/TICKET-editor-and-solver-followups.md` (new item: the bug, the fix, the gates),
   `tracker/ROW-CONSTRAINT-STATE.md` (one paragraph), and finish `B1-FIX.md` (copy it into the main
   tree). No commits.

## Report
Part A: the gate table with every number; the Lean line Part B must change. Part B: the model diff,
which lemmas needed adjusting, the property and replay results, core/test totals. Anything you could
not do, plainly.
