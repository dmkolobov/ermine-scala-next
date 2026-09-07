# Brief: S4 fix round — the S4 Part B review's findings (`tracker/loopmodel/S4B-REVIEW.md`, verdict FIX-THEN-ADVANCE)

Same repository, worktree (`~/research/ermine/ermine-scala-wt-s4`, branch `top-normalise`) and rules as
`brief-S4.md`. The reviewer's scratch is `/home/dmitry/.claude/jobs/880c725d/tmp/review-S4B/` (seeds `H*.json`,
`probes/AdvSelf{2,3}.e`, `Repro1.lean`/`Repro2.lean`, `lake-build-all.log`, `norm.py`, `census.py`). Read the
review in full first, then §6 and §7 again. You are the ONLY agent on the machine now: you may `lake build`
(one at a time, `LEAN_NUM_THREADS=2`), and one JVM at a time as before. No commits. H-13 is explained (the
orchestrator committed the handoff as `2862d14`) — ignore it.

## Required (all before the orchestrator's gate)

F1 **H-1, blocker.** `cd tracker/lean && lake build` must be GREEN (the full default target, not only
   `looptrace`) and `lake env lean Audit.lean` must print its count again with 0 non-standard axioms. Take the
   HONEST minimal repair first: add the hypothesis `fl.topNormalise = false` where `solveSeed_rejects_of_refuted`
   (and anything downstream: `solve_noFalseAccept`, `solve_accepted_faithful`, FlaggedSound) needs it, exactly as
   `Repro2.lean` verified. Then rewrite `S4-CHANGE.md` §1 item 2: the S2 no-false-acceptance chain covers the
   flag-OFF configuration ONLY; covering ON needs the bridge from `reads_of_rewrite` and is deferred to the
   adoption stage (S4c, below). ONLY AFTER the build is green: if the ON bridge falls out of
   `reads_of_rewrite`/`models_rewrite` cheaply, add it as a separate theorem and say so; do not let the attempt
   leave the build red. Record `#print axioms` for every touched theorem in scratch.
F2 **H-12.** Patch the four replay call sites in `Loop/Main.lean` (`replayCycleOne`/`replayDepthOne`/
   `replayPolicyOne`/`replayMintOne`, ~lines 156/172/191/236) to `buildQueueTop fl`. Then `grep -n buildQueue`
   over `tracker/lean/` and list EVERY occurrence with its disposition (executable → patched; theorem statement;
   premise). Measure: `--replay <the ProjectionCost.e(1:1) segment> --depth|--mints|--policy=smallcanon
   --budget=20000 --flags=topnorm` must no longer read 6804/6783 — report the numbers.
F3 **H-2.** Exclude the SELF-READ from the family (a read `v <- (x, C)` with `x == v`) in BOTH the Scala and the
   mirror, one clause each, same place. Re-run: `H8`/`H8c`/`H21` on `--depth` and `--policy=smallcanon
   --budget=20000` ON — must be REJECTED as OFF; `probes/AdvSelf3.e` on the compiler with
   `-Dermine.labelCheck=false -Dermine.rowSound=false` ON — must be rejected; the reviewer's whole seed set (29
   + the S4A review's 8 + your own) ON vs OFF, verdicts; the 15 `tnorm` sites (no corpus family contains a
   self-read, so they must be unchanged — verify). Then write the structural fact into `S4-CHANGE.md` §3 and the
   state file: this is the first rule that DELETES premises the loop can use; `noloss_of_top` is semantic and
   does not carry the loop's syntactic deaths (occurs check, duplicate fields); the self-read exclusion closes the
   one class found; layer (iii) is the net for anything else, with its documented NO-VERDICT escape and its
   `-Dermine.rowSound=false` off-switch. Say whether `S4Top.lean` needs a change (the theorems are about a
   hypothesised family, so narrowing the trigger should need none — confirm).
F4 **H-3.** Document (no code): where the rule fires on an unsatisfiable system the diagnostic CLAUSE, and
   sometimes the FIELD, changes; the position is preserved because `rowUnsat` searches the un-rewritten `cs`.
   Correct §4.9's attribution (the nine corpus clause moves are `--batch` id drift; that is not the general rule).
F5 **H-4.** Put `topNormalise` on the `sin` record (`RowTrace.scala:344-347`) and read it in `Loop/Replay.lean`
   so a replay applies the configuration the trace was taken under (as `dequeuePolicy`/`solveBudget` do); keep
   `--flags=topnorm` as the seed-side override. The OFF byte-identity gate against main is then "identical after
   masking the new `sin` column" — state that, and show the masked diff is empty on two groups.
F6 **H-10.** Re-run the `.ei` A/B with `-Dermine.loadInSeries=true` on BOTH sides (or a same-configuration
   control beside the A/B) so the reported difference is the flag and not the parallel-load churn; rewrite
   §4.10 with the control's floor and what survives it (`ProjectionCost.ei` order-only, `proj01`'s new `.ei`).
F7 **H-5/H-6/H-7/H-8, docs.** `WildChain.e` header sites → (144:8)/(168:8); `proj01_seven_reads.e:9-10` →
   the measured ladder 3/30/207/1,230/6,783 and "about 5.3–6x"; "18 declarations" → "22 declarations, 18
   audited theorems" in §2.3, the plan row and the state file; the offered block in the state file gets the
   "clear the `.ei` cache once at adoption" instruction (the cache is not keyed by the flag,
   `Constraints.scala:1371`), and `proj01_seven_reads.e` must move out of `shouldfail/` at adoption.
F8 **§7 of the review.** Fold the reviewer's closed gates into `S4-CHANGE.md`: `slow/GU05MIN` budgeted
   COMPLETES (963 s OFF / 921 s ON, SAME); `PROJ8` REJECTED@20,009 → SOLVED@1; N = 9, 10 REJECTED OFF; the
   per-file `Present/` sweep 19/20 identical (proj01); the `rsound ok` micros is the SECOND-TO-LAST column.
F9 **H-9 → plan.** Add the adoption-prerequisite stage S4c to `S4-CHANGE.md` §6 and a plan row (not started):
   the correspondence lemma from `Json.topFamilies`/`topNormalise` to `S4Top.lean` (trigger, `F = ⋃ F_i`,
   carrier freshness w.r.t. the whole system, one-pass fold) and the ON coverage of the S2 chain.

## Gates (worktree unless stated; report every number)
`lake build` green (main tree, where the mirror lives) + `Audit.lean` count; `lake env lean
tracker/loopmodel/S4Top.lean`; `TestLoopTrace` 720/720 (`.ei` cleared); differential ON on Present + Lang +
Present-shouldfail (agree = segments, 0 skip, the 15 `tnorm` byte-exact); OFF differential + masked
byte-identity vs main on two groups; `corpus-run.sh --batch` OFF 83/69 and ON 84/68; the compiler ladder ON
N = 2..8 (draws); the seed set. Report: append "## Fix round (S4B)" to `S4-CHANGE.md` with the diffs and the
gates; then STOP and report — the orchestrator verifies, then asks you to apply the Scala diff to main.
