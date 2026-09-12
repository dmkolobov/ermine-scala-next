# Review brief: S3b -- the 19 signature corrections and the 7 caller changes they forced

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-fix` (branch `sig-fixes`, HEAD 8d6f1dc plus the
implementer's UNCOMMITTED changes -- `git status`; report `tracker/loopmodel/SIG-3b-CORRECTIONS.md`; brief
`tracker/loopmodel/briefs/brief-SIG-3b.md`; the S3 implementer's own corrections patch for comparison
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S3/17-corrections-VERIFIED.diff`
and its report `../ermine-scala-wt-sig/tracker/loopmodel/SIG-3-IMPL.md` §9). You edit nothing except your scratch
`.../scratchpad/review-S3b/` and your report `tracker/loopmodel/SIG-3b-REVIEW.md`. No commits; never `git stash`.
Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; parallel
by default; read the implementer's logs and re-run only targeted things. `Relation.e` and `Layout/Report/Keyed.e`
are CRLF (check the diff did not convert line endings: `git diff --stat` and `file`). Delete every `.ei` you cause.
Budget 2 hours. Verdict ADVANCE / FIX-THEN-ADVANCE (exact edits) / BLOCK.

These edits change SHIPPED LIBRARY SIGNATURES. For each of the 26 changed bindings (19 corrections + 7 forced
callers) answer: (a) is the new signature HONEST (the oracle accepts every obligation; spot-check five by
hand from the probe records); (b) is it MINIMAL -- does it exclude any call the body could serve? Compare each
with the S3 patch's version where they differ and say which is right and why:
1. `unify1`: the implementer rejected the orchestrator's `r2 <- (h,f1,f2,t) / r <- (h,f2,t)` because
   `Algebra/Customer360.e:207` passes the same relation twice (`r = r2` forces `f1 = (||)`), and chose
   `(r2 <- (f1,f2,p), r <- (f2,p,u))`. Verify the Customer360 call, verify the chosen pair is honest for the
   body `join (rename f1 f2 (except {f2} r2)) r`, and check `alg03` is still refused byte-identically.
2. `monthsSince`/`daysSince`/`daysUntil` changed RESULT TYPE from `Op out Int` to `Op r Int` (the `out`
   quantifier dropped) because the `ds` half pins `out` to `r`. Is that a behaviour change for any caller
   (grep the corpus), and is it the minimal honest form or should the signature keep `out` with `RUnion2`?
3. `keyValueTabular`: the honest signature is "degenerate" (forces `pid = cid = r = (||)`). Is the wrapper
   then useless as shipped, and should the report say so more loudly (a ticket)?
4. `cutoffs`: the oracle gives NO VERDICT (an unstatable `ds` member). Under the shipped checker that is
   warn + accept -- confirm the module loads under `error` with a warning, and say whether the signature
   could be made decidable.
5. The 7 forced callers, especially `SoftRelation.e:105`'s re-keyed drilldown call `(dt, dt)` -> `(dtGroup, dt)`:
   is that a BEHAVIOUR change in an example's output (run it before/after and diff the report), or was the
   old call producing a duplicate column that the honest `cons_Bracket` correctly refuses?
6. `.ei`: 29 "other" binding diffs, 25 the corrections, 4 id-shift churn incl. `Relation.lookbackJoin` 8->9
   constraints "the extra member entailed" -- hand-check that one; a published constraint set growing is
   exactly what a caller sees.
7. Gates from the logs: corpus batch 94/74/0 over 168 with `verdict CHANGED` empty; suites 63/63;
   repl-smoke 8/8. Re-run the corpus batch once and `TestSigEntail *TestLetSignatures` once.

Report: verdict first; a 26-row table (binding | honest? | minimal? | agrees with S3 patch? | note); the
edit list. Under 250 lines.
