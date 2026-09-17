# brief-review — one Opus reviewer per stage, under 2 h. You did not write the stage.

Stage, worktree and report path are given in your launch message. Read, in order: `tracker/satterm/briefs/
brief-S-common.md`, `tracker/PROMPT-subsume-termination.md` Part B, `tracker/satterm/SUBSUME-PLAN.md`, the stage
brief, the implementer's report, then the diff (`git diff` in the stage worktree — the stage is UNCOMMITTED).
Write your review to the path named in the launch message (it exists, empty). Scratch:
`/home/dmitry/research/ermine/scratch-subsume/review-<stage>/`. Same toolchain and rules as the common brief:
no commits, no nohup, background long jobs with logs, kill by PID, delete the `.ei` you cause.

## Re-run (targeted; cite the implementer's logs for everything else — never a whole-corpus or full-suite re-run)

- Lean stage: `lake build`, `lake env lean Audit.lean` (0 non-standard), `#print axioms` on every new declaration
  — your numbers go into the review. Re-elaborate each new theorem's statement against the BRIEF's wording: was
  anything weakened to pass (a hypothesis added, a quantifier narrowed, a witness that does not satisfy the
  invariant the brief named)? Vacuity: mutate one hypothesis or one case (comment out a side condition, change a
  constant) and confirm the build FAILS, then revert. Is a "terminates" claim a theorem and not an `#eval`?
- Scala stage: `sbt core/compile core/copyResources`, the stage's own suites, and the B1 property alone
  (`sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'`) with a deadline (background + log; kill by PID at
  the deadline). Anything the report claims that you dispute, re-run yourself. Every hypothesis the report
  discharges by measurement must have a log path — open the log and check it says what the report says.
- Corpus verdicts (Scala stages that touch `Subst.scala`/`Constraints.scala`): read the implementer's
  `corpus-run.sh --batch` verdict listing against S0's baseline; a rejection that became an acceptance or the
  reverse is REWORK, full stop.
- Instrumentation and flags default OFF: confirm by reading the `val` and by one run without the flag.

## Verdict

`LAND` / `FIX-THEN-LAND` (numbered findings: file:line, the failure scenario, the fix) / `REWORK` (what is wrong,
what a rework must show). Then, separately: does the stage's answer to the title question (yes / no / bounded)
follow from what is actually proved and measured? State the answer you would sign.
