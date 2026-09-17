# brief-M2 — merge `scala3-migration` (with subsume-termination) into `json-encode`, lift the B1 gate (Opus implementer, 2 h; reviewer 1 h)

Worktree `~/research/ermine/ermine-scala-wt-json`, branch `json-encode` (tip 2afeb426 at the time of writing). Read
`tracker/satterm/briefs/brief-S-common.md` on `scala3-migration` (main checkout `~/research/ermine/ermine-scala`) for
toolchain and rules, then `tracker/satterm/SUBSUME-PLAN.md` (closing sequence) and `SUBSUME-STAGE2.md`. Report:
`tracker/satterm/SUBSUME-M2.md` in the json worktree (create it; the orchestrator pre-creates it if you cannot).

## The user's instruction (2026-09-16)

After the programme lands on `scala3-migration`, merge `scala3-migration` into the active JSON branch. Nothing is
pushed. One full `core/test` on the receiving branch before it counts as done.

## What you do

1. `git merge scala3-migration` in the json worktree. Known divergence on the programme's files (`git diff --stat
   478a369c json-encode -- ...`): `Subst.scala` (10 lines changed on json-encode; S0's instrumentation is +157/−2
   near :365 and :648 — resolve by keeping BOTH sides' intent, and say exactly what json-encode's five-line change
   was), `TestDateAndScan.scala` (+12 on json-encode: the `-Dermine.test.dateDiffReject` gate, commit dd9e0316),
   `tracker/tools/lsp-client.py` (+22 on json-encode; S2 adds RowUnsat checks). Resolve every conflict; list each
   with the resolution in the report. Doc conflicts under `tracker/` too.
2. **Lift the B1 gate**: with S2's `rejects` combinator the refutation property runs once (~10 s), so remove the
   `-Dermine.test.dateDiffReject` gating in `TestDateAndScan.scala`, the quarantine entry in `tracker/GATE-POLICY.md`,
   and close item 12 in `tracker/TICKET-editor-and-solver-followups.md` (cite S0/S2). Make sure the property uses
   `rejects` (not `no`) after the merge.
3. Gates on the merged tree: `sbt core/compile core/copyResources`; the B1 suite alone at the default N (deadline
   10 min; expected ~3 min green); `TestRowRefusals` alone; `TestLoopTrace` with
   `-Dermine.looptrace=~/research/ermine/ermine-scala-wt-json-wrappers/tracker/lean/.lake/build/bin/looptrace`
   (720/720/720); `corpus-run.sh --batch` verdicts (json-encode's own baseline is 89/79/0 over 168 — confirm from
   its tracker if it differs); `repl-smoke.sh`, `lsp-smoke.sh` (expect S2's 578 plus whatever json-encode's own
   LSP cases add — record before/after on json-encode); `client/scripts/check-corpus.sh` (json-encode's own gate,
   60/60 at 2afeb426); then ONE full `core/test` in the background (json-encode baseline 1196/1196 at 5d0a2614 with
   the quarantines) — record count and wall clock (S2 expects a large saving).
4. Commit ONLY after the reviewer's LAND: the orchestrator commits. Leave the merge uncommitted? No — a merge in
   progress cannot be left across a review: complete the merge commit yourself (`git commit` with the default merge
   message plus one line "resolutions in tracker/satterm/SUBSUME-M2.md"), then leave the gate-lift as a separate
   UNCOMMITTED change for the orchestrator to commit after review. Never push.

## Report

Conflicts and resolutions (file:line, both sides, the resolution), the gate-lift diff summary, every gate number
with its log under `~/research/ermine/scratch-subsume/m2/`, the full-run count and wall clock before (from the
JSON trackers) and after. The reviewer re-runs the B1 suite alone, TestRowRefusals, and reads the full-run log.
