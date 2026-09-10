# Review brief: LSP Stage 4 item 7.0 — the direct measurement of the read, and the 7.1-vs-7.3 verdict

You are reviewing item 7.0 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `2b72995`
plus the UNCOMMITTED deliverables: new `session/Phases.scala`; `rename/NewPipeline.scala`, `session/TolerantCheck.scala`,
`lsp/Resident.scala`, `lsp/Diagnostics.scala`, `lsp/Definitions.scala`, `lsp/Rpc.scala`; `tracker/tools/lsp-client.py`;
report `tracker/loopmodel/LSP4-7.0-READ.md`; harnesses in the implementer's scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.0/`). Implementer's
brief `tracker/loopmodel/briefs/brief-LSP4-7.0.md`; item of record `tracker/LSP-ROADMAP.md` § "Stage 4", item 7.0, the
premise bullets above it, and Decisions (a)(d)(g); `tracker/loopmodel/STAGE4-PRIOR-ART.md` §0.1, §5(a)/(a′);
`tracker/PERF-ROADMAP.md` P5(a); `tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.0/` and your
report `tracker/loopmodel/LSP4-7.0-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. ONE JVM at a time, no background JVMs, no lingering polling shells; delete every `.ei` you cause; do not
touch `tracker/lean/`; no commits. THIS ITEM'S NUMBERS DECIDE THE STAGE (Decision (g)): your job is to make them yours.

1. **Inertness first.** The timers are behind `-Dermine.lsp.phases=true`, default off. Read every one of the six call
   sites and `Phases.scala`: with the property off, is the cost one boolean test per site (no string formatting, no
   `nanoTime`, no allocation)? `NewPipeline.scala` got "six additive inert lines" — is the strict `readModule` path
   untouched in BEHAVIOUR (the tolerant reader is the editor path; if a timer sits in shared code, show it is
   inert)? `Session.scala` diff empty; `git diff --stat` == `--stat -w`; corpus verdicts identical; REPL goldens
   clean. Where does the output go with the property on — the LSP log, never stdout (Decision 4)? The lsp-smoke
   +2 checks assert the line appears when asked and NOT otherwise: confirm both directions actually test that.
2. **THE PHASE TABLE — re-measure it yourself** on Layout/Report.e through the real server path with the property
   on, 50 reps after 20 warm-ups, load < 1.3 at start (implementer run B: parse 843.6 ms of read 859.6 of check
   1388.0; checkWith 496.4; rename 5.0; lower(+ctx) 9.3; header 8.2; scrub 2.0; keys 3.2; index 10.1; rpc.json
   0.31; reconciliation +0.004%/+0.026%). Yours beside theirs. The reconciliation claim: do the phase timers sum
   to the check total within 0.1% on YOUR run too? The "header is parsed twice" finding (once by `Resident`, once
   inside `SurfaceParsers.module`) — confirm from the code and say whether the 8 ms is worth a Stage-4 line.
3. **THE RATIO — the number the stage turns on.** The implementer found Report.e has 591 extents at mean 110.7 B (not
   the survey's "315 at 245 B" — 294 distinct head words), parsed each extent alone through the repositioned
   `ParseState` (median 0.595 ms, mean 1.174, p90 2.18, max 99.0 ms for the 10,707-byte `private` block), and got
   Σ(591 slice parses) 723.9 ms vs whole-file 751.7 ms in the same JVM: **ratio 0.963**, splitter residual +27.8 ms.
   Re-run their harness (scratch `7.0/`) and then ATTACK it: (a) is a slice parse through `statementFailure`'s
   repositioned ParseState really the same work the whole-file parse does per statement — does the whole-file parse
   do anything per statement the slice does not (the `sepEndBy(semi)`/`.attempt` driver, `virtualRightBrace`,
   prefix-parse checks), or vice versa (the slice re-seeds the layout stack)? A ratio near 1 could hide two
   compensating errors. (b) The 99 ms `private` block: a statement cache keyed by top-level extent would re-parse
   that whole block on any edit inside it — what fraction of Report.e's bytes sit inside `private`/`database`
   blocks, and does 7.1b's expected saving survive if edits land there? (c) the per-byte figure 10.9 µs/byte — is
   the parse linear in bytes across the 591 extents (fit it), or superlinear (which would change 7.3's ranking)?
   (d) The claim "a one-char edit leaves 590/591 extents identical → parse ≈ 38 ms → round trip ≈ 0.88 s" — check
   the arithmetic and its assumptions (the miss costs the slice parse of the edited extent PLUS the splitter
   residual PLUS the cache lookups; where does 38 ms come from?).
4. **The attribution factors** against the survey's §0.1 arithmetic (parse 1.07x under; extents 23x over raw / 2.0x
   over corrected; lower 0.97x; rename 2.5x under; reassoc 1.4x over): recompute two of them from the survey's
   numbers and the table.
5. **The 7.2 cliff** (top-of-file blank line → 0/154 reused, typecheck 1.07 s, round trip 2.29 vs 1.79 s): reproduce
   once. **The Rpc addendum** (dropped: run-based scanner 355 → 286 µs = 1.24x, not the survey's 5x; a first draft was
   not byte-identical because `StringBuilder.append` takes (offset, length)): confirm `Rpc.scala`'s diff is timer-only.
6. **THE VERDICT.** "7.1: per-statement parse work is 58.5% of the check / 47.8% of the round trip; 7.3 re-ranked to
   the batch target; 7.2 lands first." Do you agree? State the strongest case AGAINST 7.1 you can build from the
   data (e.g. the 3.7% splitter residual plus the private-block p100 plus the header duplication; or the machine's
   8% run-to-run drift swallowing part of the win) and whether it changes the ranking. Is "7.2 lands first" right
   (it is independent of the 7.1/7.3 choice and fixes a measured +0.52 s cliff)?
7. **Gates, re-run ONCE:** compile+copyResources; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>` 85/69/0;
   `repl-smoke.sh` 8/66 goldens clean; `lsp-smoke.sh` 456; boot 129; `.ei` 0.

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each — item 3 gets as much as
it needs), your phase table beside the implementer's, your ratio beside theirs, gate table, and a verdict on BOTH the
item (ADVANCE / FIX-THEN-ADVANCE / BLOCK) and the stage direction (agree 7.1 / prefer 7.3 / neither, with the
number). Your numbers enter the roadmap. STOP after the report.
