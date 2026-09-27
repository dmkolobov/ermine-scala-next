# Rules for every reviewer (`review-<area>`)

You review an implementer's dirty worktree `ermine-scala-wt-sql-<area>` against
`tracker/sql-audit/WORKLIST.md`, the findings it cites, `brief-impl-common.md` and the
implementer's `report-impl-<area>.md`. You did not write it. Budget 1.5 h.

Verdict file: `scratch-sql-audit/REVIEW-<area>.md`, the DB programme's shape (see
`scratch-widget-preview/db/REVIEW-F1.md`): a verdict table (DESIGN, IMPLEMENTATION: GREEN or
RED, must-fixes), then per item: is the finding really fixed (run the repro), does the test
fail without the fix (revert the fix in a copy or comment it out, run once, restore: the
"reverse mutant"), is any behaviour change beyond the item, is every dialect still
text-correct, is the Scala 2.11-portable dialect kept, are the gate numbers in the report real
(read the cited logs; re-run only the targeted suites for the code under review, never the
whole `core/test` or corpus).

Must-fixes go to the board as `[review-<area>] [finding] MUST-FIX ...` addressed to the
implementer, who fixes them in place; you re-check only the must-fixes. GREEN/GREEN means the
orchestrator may commit. Final message at most 30 lines.
