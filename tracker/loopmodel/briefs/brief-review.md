# Review brief (template) — trust nothing you have not re-run

You are reviewing stage `$STAGE` of `tracker/LOOP-MODEL-PLAN.md` in
`/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`). The implementer's brief is
`$BRIEF`, its report is `$REPORT`, and its changes are the uncommitted files `git status` lists
beyond the pre-existing Stage 7 set (`$PREEXISTING`). You do NOT edit anything except a scratch
directory `/home/dmitry/.claude/jobs/880c725d/tmp/review-$STAGE/` and your own report file
`$REVIEW_REPORT`. No commits, no sbt, no Lean edits.

Method, in this order, and record each step's command and result:
1. **Rebuild and re-audit yourself**: `cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH &&
   lake build Rowpartition && lake env lean Audit.lean`; grep the new modules for `sorry`,
   `Classical`, `partial`, `axiom`, `unsafe`, `native_decide`, `opaque`, `implemented_by`.
2. **Re-run the implementer's evidence**: every differential run / test the report cites, with
   the report's own commands, and compare the numbers. Then run something the implementer did
   NOT: two more id bases per seed, one seed of your own construction that exercises a branch the
   report's table marks "exact" but no seed reached, and (if the stage has a corpus harness) a
   random sample of ten corpus solves.
3. **Read side by side**: for every row of the correspondence table, open the Scala function and
   the Lean definition and check the claim (exact / abstracted / not modelled). Pay particular
   attention to: dequeue ORDER (the priority-search queue and the type-variable graph), dedup
   semantics (`trim`, `++!`, `Partition.equals` ignoring the tag), `makeEmpty`'s cascade and
   erasure, `destructiveSub`'s `keepDefs` and `srs`, `unify`'s removal, the lazy lookups in
   `learnPartitions` (what they range over — `proc ++ incm` minus the dequeued premise), and
   error/death paths. Anything the model does in a different order than the Scala, or with a
   different set, is a finding even if the six seeds do not expose it.
4. **Acceptance criteria**: check each criterion of the stage in `tracker/LOOP-MODEL-PLAN.md`
   explicitly, PASS / FAIL / PARTIAL with evidence.

Findings ranked by severity, each with: file:line on both sides, what the Scala does, what the
Lean does, a concrete input that would expose it (construct and run it if you can — then it is
CONFIRMED; otherwise PLAUSIBLE), and the fix you recommend. End with a verdict: ADVANCE /
FIX-THEN-ADVANCE (list the required fixes) / REDO (why). Write `$REVIEW_REPORT` early and keep
it current. Disk is tight; scratch only in your directory; never `lake exe cache get`; delete
any `.ei` files you cause under `core/examples`; `pkill -f` matches itself.
