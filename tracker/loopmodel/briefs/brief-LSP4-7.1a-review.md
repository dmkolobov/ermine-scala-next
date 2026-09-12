# Review brief: LSP Stage 4 item 7.1a — the high-water mark (Tier 1: the parser library changed)

You are reviewing item 7.1a in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `a15a97e`
plus the UNCOMMITTED deliverables: new `parsers/src/main/scala/scalaparsers/Mark.scala`; `parsers/.../ParseState.scala`,
`parsers/.../ParsingUtil.scala`; `core/.../surface/SurfaceParsers.scala`; `core/.../rename/NewPipeline.scala`;
`scalacheck-binding/src/main/scala/TestSurfaceParsers.scala`; report `tracker/loopmodel/LSP4-7.1a-MARK.md`).
Implementer's brief `tracker/loopmodel/briefs/brief-LSP4-7.1a.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 4,
7.1a, the STAGE-4 INVARIANTS ("REUSE METADATA SURVIVES REUSE"; Tier 1 for scalaparsers) and Decisions (a)(g); the 7.0
report §4.3 (the 15 divergent statements); `tracker/GATE-POLICY.md` Tier 1. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-7.1a/` and your
report `tracker/loopmodel/LSP4-7.1a-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. ONE JVM at a time (the looptrace replays are Lean binaries; their compiler side is sequential), no
background JVMs, no lingering polling shells; delete every `.ei` you cause (the sweep writes many); never touch
`tracker/g1-*` or `tracker/lean/`; no commits. NOTE the implementer's build warning: an incremental `core/compile`
after a `Mark.scala`/`ParseState.scala` edit can fail with spurious `E046 Cyclic reference` errors in the legacy
`parsing` package — `sbt core/clean core/compile` (38 s) clears it. THE ORCHESTRATOR'S DECISION you are checking, not
re-making: batch pays nothing (the strict path constructs `MarkOff`); the editor's residual read cost is accepted as
7.1b's precondition, and 7.1a comes out with 7.1b if 7.1b is reverted.

1. **THE SOUNDNESS ARGUMENT.** `Mark` is a shared mutable cell carried as `ParseState`'s seventh field; `copy`
   propagates the reference; `attempt` rolls back the state VALUE, not the cell, so `furthest` is monotone and
   includes failed lookahead. Read `Parser.attempt`, `not`/`notFollowedBy`, `orElse`/`|`, `scope`, `sepEndBy`, the
   layout combinators: is there ANY path where a parse continues from a `ParseState` whose `mark` is a DIFFERENT cell
   (a state constructed fresh mid-parse — `statementFailure`'s repositioned state, `evalInContext`'s, any `ParseState.mk`
   inside a combinator) so that examinations are recorded into a cell nobody reads? Is `Mark.equals/hashCode` keeping
   the cell out of state equality actually relied on anywhere (does anything compare `ParseState`s)? Is `furthest`
   ever READ during the parse (it must not influence parsing)?
2. **THE AUDIT.** 16 sites, 9 bumped, 2 proven non-bumps (`Parser.slice`; `Pos.bump`'s read-ahead to line end), 5
   not-a-parse. Re-do it independently: grep every `input`/`charAt`/`indexOf`/`substring`/`regionMatches`/`startsWith`
   over `parsers/` and `core/.../surface/` and classify each; any site the implementer missed? For the two proven
   non-bumps, re-prove: could `Pos.bump`'s line read-ahead ever reach a decision (a `Span`, a layout column, a
   diagnostic position that the CACHE would splice)? The claim "the grammar always depends on its successor's first
   byte" (every mark is at least one byte into the next extent): why, exactly — which rule looks there?
3. **ANTI-VACUITY.** 6,954 of 6,954 corpus statements have a mark past their extent; the 15 named Report.e statements
   each verified; 0 short of consumed. Re-run `MarkAudit` (their harness in scratch `7.1a/`) and reproduce the counts;
   then the planted-bug matrix: remove the `atLayoutBoundary` bump → only the isolation property (v) fails; make
   `rawSatisfy` bump only on consume → only (iv) fails. Reproduce both plantings (in scratch or by a temporary edit you
   REVERT and hash-check). Are five properties enough — what site could be un-bumped without any property noticing?
4. **BATCH PAYS NOTHING — re-measure.** The strict path constructs `MarkOff` (`reach` empty, `furthest` = Int.MaxValue
   so a wrong strict read refuses every reuse). Confirm from the code that EVERY strict entry gets `MarkOff` (module,
   readModule, REPL typeExpr/expression/replType, interface parsers, the legacy `parsing` entries, `statementFailure`'s
   slice) and that ONLY `SurfaceParsers.moduleMarked` installs a live cell; confirm nothing on the strict path reads
   `furthest`. Then the batch A/B yourself: `perf-bench.sh batch -n 3` before/after/before/after (before = a scratch
   build of HEAD `a15a97e` — the implementer used saved class trees; you may do the same or a worktree; the tracked
   `repl-classpath.txt` trap: it holds absolute paths), load < 1.3; pooled Δ and median-of-medians (implementer: pairs
   −0.36/+0.13/−0.11/+0.14 s, pooled −0.41%, median-of-medians 0.00%). And ONE editor pair (implementer's residual: read
   +5 ms with typecheck control +5; first-round pooled +42.5 ms) — report yours; the honest band enters the roadmap.
5. **TIER 1, RE-RUN ONCE (yours are the numbers of record):** `tracker/tools/looptrace-corpus.sh` (`LOOPTRACE_PAR=3`)
   on the final tree, `trace-ab.py` against the implementer's pre-change run (in `7.1a/lt-before/`, or your own from
   the `a15a97e` build) — ALL record kinds, expected IDENTICAL, `sinmoved=0`, every group rc 0; `tracker/tools/ei-diff.sh
   --snapshot --batch` with `-Dermine.loadInSeries=true` both sides, `ei-classify.py` (expected 268/268, 0 differ);
   `tracker/tools/g1-validate.sh` 9/9. Tier 0: compile (clean if needed) + copyResources; `TestLoopTrace` 720/720;
   `corpus-run.sh --batch <outdir>` 85/69/0 AND byte-identical to a pre-change run once timings are normalised;
   `repl-smoke.sh` 8/66 goldens clean; `lsp-smoke.sh` 480; `*TestSurfaceParsers` 10/10 and the seven targeted suites;
   boot 129; `.ei` 0 by `find` (never `git status`); `git diff --stat` == `--stat -w --histogram`; line endings.
6. **THE RECORD 7.1b CONSUMES**: `readModuleTolerant(...).marks: List[StatementMark(startLine, startCol, startOffset,
   endOffset, examinedEnd, markAtEntry)]`, one per top-level statement in order, `Nil` on the strict path; the guard
   "reuse iff extent text byte-identical AND no edit intersects [startOffset, startOffset+examinedLength)"; three
   obligations (carry forward; a mark at input end is truncated; 7.2's reachable rule governs the key). Is the record
   sufficient for 7.1b as the roadmap describes it, and is `markAtEntry` (the cumulative counter at statement start)
   the right way to de-cumulate a single shared cell — what is the inflation bound (implementer: ≤ 23 bytes
   corpus-wide) and can it ever cause a WRONG reuse (too small a guard) rather than a missed one?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), the Tier 1 table
(implementer vs yours), the two A/Bs beside theirs, verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why), and a
one-line answer: "batch pays nothing: yes/no". STOP after the report.
