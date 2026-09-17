# brief-S2 — the fix, REBRIEFED 2026-09-16 evening (Opus implementer, 4 h)

Worktree `~/research/ermine/ermine-scala-wt-subsume-s2`, branch `subsume-s2` (off `subsume-termination`, which
carries the landed S1a and S1b Lean; S0's instrumentation lands separately and you do not need it). Read
`brief-S-common.md`, Part B of the prompt, then — in the S0 worktree
`~/research/ermine/ermine-scala-wt-subsume-s0/tracker/satterm/` — `SUBSUME-STAGE0.md` and
`SUBSUME-STAGE0-REVIEW.md` (read-only), and in this worktree `SUBSUME-STAGE1A.md`, `SUBSUME-STAGE1B.md` and
their reviews. Report: `tracker/satterm/SUBSUME-STAGE2.md`.

## Licence — why this stage is NOT the one Part C describes

Part C's S2 ("a cheaper / memoised escape check", or "an occurs check at the binding site") is not licensed:

- **S1a** (`Rowpartition/SubsumeEscape.lean`, review LAND): the walk at `Subst.scala:648` follows no binding and
  terminates unconditionally (`runV_steps`, `escs_cost_le_subPass`); `verdict_eq` is verdict-preserving tidying
  only; `no_early_exit_on_empty` kills short-circuiting; the age-stamp restriction would ACCEPT an escaping
  skolem. S1a's §4 says plainly: S1a licenses no asymptotic improvement to `:648`.
- **S1b** (`Loop/RejectTerm.lean`, `Loop/EnvBound.lean`, review LAND): the loop is bounded at the shipped
  defaults (`budgetSP_terminates`), `Subst.solve` terminates (`solveSeedP_terminates`), no cyclic binding is
  reachable (`runsP_noAliasChain`), and the loop leaves at most one small entry per dequeue.
- **S0** (review FIX-THEN-LAND, headline CONFIRMED and strengthened): the B1 program is REFUSED in 0.06–0.09 s
  at 17 `Supply` id bases ("Row partitions are unsatisfiable at field 'Bad.startDate'"); `bin/ermine` refuses it
  in 0.07 s; the reviewer's default-N run of the suite FINISHED green in 1,099 s. The "hang" is the test
  harness: `ErmineFixture.no` (`scalacheck-binding/src/main/scala/TestErmine.scala:220-223`) rewrites a
  result's status `False => True`, so a refutation property is `passed`, never `proved`, and ScalaCheck runs
  `minSuccessfulTests = 100` full checks, each re-type-checking the whole import closure (~9.1 s each, one
  library boot per test; `_useInterface=false`, `onlyTest`). H1 and H2 are refuted; H3 survives only as
  "`:648` is where the sampler landed".

So deliverable 1 of the prompt (the check terminates, with a proof of why) is met by S1a + S1b + S0, and no
budget (S3) is needed. What remains to BUILD is the defect S0 actually found, plus the pins the programme
promised. **No compiler change. Nothing under `core/src/main` changes in this stage.** If you find you need
one, stop and say so in the report.

## What you build

1. **A `proved` refutation combinator** in `ErmineFixture` (`TestErmine.scala:220-223`): e.g. `rejects(p: Prop)`
   (or fix `no` in place — decide, and say why; `no` has 24 call sites in 5 files, listed below) that maps a
   `False` result to `Proof` (with the "must fail" label kept) so ScalaCheck stops after ONE evaluation, and
   maps `Proof`/`True` to `False`. Keep `Exception`/`Undecided` statuses as failures, as `no` does now. Apply it to
   every `no(typeChecks(...))`/`no(defAndEval(...))`-style refutation whose body is deterministic (the 24 sites in
   `TestScopes.scala`, `TestLetSignatures.scala`, `TestStage1Pins.scala`, `TestDateAndScan.scala`,
   `TestSigEntail.scala`); a site whose body is a `forAll` over generated input keeps 100 iterations by design —
   say which are which. Measure: the B1 suite alone at the DEFAULT `minSuccessfulTests` before and after
   (S0/review: 1,099 s before; the after figure is yours), and the full `core/test` once in the background (this
   landing's one full run; the review predicts ~915 s saved per full run — measure, don't inherit).
2. **The deadline pin for B1** (the `(iso)` idiom: `TestRunner.scala:915-947` on branch `json-encode`, worktree
   `~/research/ermine/ermine-scala-wt-json`, read-only): the B1 program checked on a daemon thread joined with a
   deadline (choose it from S0's numbers with margin: the check is ~0.1 s inside a ~9 s closure re-check; a
   60 s deadline says "diverged" loudly instead of wedging a run), required to be REJECTED with the row-label
   message; its positive twin required to CHECK.
3. **A generator of unsatisfiable row programs** (brief Part C: random `field`s, a relation missing a random
   NON-EMPTY subset of them, a `combine_Op`/`col_Op` chain over the missing ones, source built the way
   `TestSchema.shape` does on `json-encode`), each case on a deadline thread, required to be REJECTED never
   accepted never hung; the positive twins required to check. Keep the sample SMALL and say why: each case
   costs a closure re-check (~9 s) unless you can load the cases into one session — try `loadStatements` on a
   shared fixture session first and report which you used. The suite must add no more than ~2 minutes to
   `core/test`; state the number.
4. **An LSP smoke case** (`tracker/tools/lsp-smoke.sh`, `tracker/lsp-tests/`): open the B1 program in the
   resident session and receive a diagnostic within the debounce ceiling (the prompt's Gates section asks for
   it; S0 says the hazard is not reproduced — this pins that). `lsp-smoke.sh` count before/after (577 expected
   before).
5. **Gates, yourself**: Tier 0 (compile+copyResources; `TestLoopTrace` with
   `-Dermine.looptrace=/home/dmitry/research/ermine/ermine-scala-wt-json-wrappers/tracker/lean/.lake/build/bin/looptrace`
   — baseline 720/720/720 per the S0 review; `corpus-run.sh --batch` verdicts 89/79/0 over 168 byte-for-byte
   against S0's baseline listing `scratch-subsume/s0/` — cite the path you compare with; `repl-smoke.sh`;
   `lsp-smoke.sh`). Tier 1 is NOT triggered (no solver/trace/Type.scala/executable Lean change) — say so. The
   B1 suite alone three times at the default N after the change, each under a deadline. One full `core/test`
   in the background with its wall clock.
6. **Do NOT** touch `Subst.scala` (S0's instrumentation lands from its own branch), the `.ei` quarantine on
   `json-encode` (a note in the report that `-Dermine.test.dateDiffReject` on json-encode can be lifted once
   this lands is enough), or the LSP dispatch thread (out of scope, ticketed).

## Deliverables

`SUBSUME-STAGE2.md` per the common brief: the combinator and the 24 sites (before/after semantics per site),
the pins and their counts, every gate number with its log, the before/after suite and full-run timings, the
smoke case, and the stage's answer: YES, with the theorem and measurement it rests on. List every changed file.
No commits.
