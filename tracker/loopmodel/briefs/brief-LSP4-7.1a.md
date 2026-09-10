# Brief: LSP Stage 4, item 7.1a — the high-water mark (Tier 1: a parser-library change; 7.1b's soundness precondition)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (7.0 and 7.2
are committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells when you
stop. No commits. Do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause (this item's
Tier-1 sweep writes many; delete them all afterwards, never the checked-in `tracker/g1-*`). Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.1a/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", item **7.1a** (inside 7.1), the STAGE-4 INVARIANTS ("REUSE
METADATA SURVIVES REUSE"; Tier 1 for any change inside `scalaparsers`) and Decisions (a)(g); the NOTES carried into 7.1
from 7.0's DONE paragraph; `tracker/loopmodel/LSP4-7.0-READ.md` §4.3 (the 15 of 529 statements whose slice parse
differs from the whole-file parse ONLY in the statement's end span — `atLayoutBoundary` consuming trailing trivia:
these are your anti-vacuity witnesses); `tracker/loopmodel/STAGE4-PRIOR-ART.md` §1.7 (Lean's `private def`
counterexample and its wish for a "high-water mark parser position"), §1.10 (Ohm's `maxExaminedPos`, which INCLUDES
lookahead used only for a decision — five systems converged on that one integer), §1.12(3); `tracker/GATE-POLICY.md`
Tier 1; `tracker/PERF-ROADMAP.md` P5(d) (the reverted parser change and its lesson: a test that has never failed
has not been shown to work).

THE CODE (read before designing): `parsers/src/main/scala/scalaparsers/ParseState.scala` — `ParseState` is an IMMUTABLE
case class `(loc: Pos, input: String, offset: Int, s, layoutStack, bol)` copied on every advance;
`ParsingUtil.scala:52` `rawSatisfy` is the character-consuming primitive (`s.copy(loc = s.loc.bump(c, si, sop),
offset = sop)`); `Parser.scala:139` `attempt` is the backtracking combinator — on failure the state that SURVIVES is
the one from before the branch, so a plain field on the state would LOSE the extent a failed lookahead examined,
which is exactly the position the mark must keep (Ohm §1.10); `notFollowedBy`/`not`, `realEOF`/`eof`
(`ParseState.scala:32`, `ParsingUtil.scala:80`) examine input without consuming; `core/.../surface/SurfaceParsers.scala:853`
`atLayoutBoundary` calls `StatementExtents.skipTrivia(st.input, st.offset, ...)` DIRECTLY on the input, bypassing every
primitive — so the mark must be told about it explicitly; audit every other direct read of `input`/`charAt` in
`scalaparsers` and `surface/` (the layout/vsemi code, `virtualLeftBrace`'s column scan, the Lexer) the same way.

## What to build
7.1a.1 THE MARK. One integer per parse: the furthest input offset EXAMINED (consumed OR looked at for a decision),
      surviving backtracking. Design choice, yours to make and JUSTIFY in the report: (A) a small mutable cell
      (`final class Mark { var furthest: Int }`) referenced by every `ParseState` copy of one parse, bumped with one
      `max` in `rawSatisfy` and at every non-consuming examination site (eof checks, `atLayoutBoundary`'s
      `skipTrivia` end offset, any audited direct read) — survives `attempt` because the cell is shared, not copied;
      or (B) thread the furthest through results (`Fail`/`Commit` carry it, merges take the max) — pure but touches
      every combinator. Prefer (A) unless you find it unsound; state why. It MUST be recorded per statement:
      `examinedLength = furthest − statementStart`, observable from the tolerant reader (an added field on the
      statement-level result 7.1b will consume — e.g. alongside each `SStatement`'s extent in
      `NewPipeline.readModuleTolerant`'s output, or a side table keyed by extent start; say which). BATCH MUST NOT
      OBSERVE IT: the mark is written, never read, on the strict path; no Death message, no position, no ordering,
      no `.ei` byte may depend on it.
7.1a.2 THE AUDIT: list every place the parse examines input without going through `rawSatisfy`, with the line, and
      whether the mark is bumped there (it must be, or the site is proven not to influence any decision). Missing
      one is the Lezer 0.15.0 bug.
7.1a.3 TESTS. (i) ANTI-VACUITY, the roadmap's requirement: a TestSurfaceParsers property over the corpus that the
      mark EXCEEDS the statement's own extent for at least the 15 Report.e statements 7.0 §4.3 named (they are
      precisely where `atLayoutBoundary` looked past the extent) — report the count over all 253 files, and pin a
      floor (≥ 15). A mark that never exceeds the extent has not been shown to work. (ii) the mark never falls
      SHORT: for every statement, `examinedLength ≥ extent length` (a mark below the consumed end is a bug). (iii)
      Lean's counterexample in Ermine: two adjacent statements where editing the SECOND's first token changes how
      the FIRST's trailing boundary is decided — construct one (or show the grammar cannot produce one and why);
      the first statement's mark must reach into the second. (iv) an `attempt` that fails after examining N chars
      leaves the mark at ≥ N.
7.1a.4 TIER 1 GATES — this touches the parser library, so per GATE-POLICY: Tier 0 (`core/compile core/copyResources`;
      `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>` 85/69/0 over 154 AND the verdict outputs
      byte-identical to the 7.0-commit run once timings are normalised; `repl-smoke.sh` 8/66 goldens unmodified;
      `lsp-smoke.sh` at its current count + yours; boot 129); PLUS `tracker/tools/looptrace-corpus.sh`
      (`LOOPTRACE_PAR=3`, ~15 min) with `trace-ab.py` against a pre-change run (build the pre-change compiler from
      HEAD in a scratch worktree; ALL record kinds; expected IDENTICAL); `tracker/tools/ei-diff.sh --batch` with
      `-Dermine.loadInSeries=true` on BOTH sides classified with `ei-classify.py` (expected 0 differences);
      `tracker/tools/g1-validate.sh` 9/9. THE INTERLEAVED A/B ON BOTH TARGETS (the roadmap's "the counter is free"):
      `perf-bench.sh batch -n 3` before/after/before/after (load < 1.3) and `perf-bench.sh editor -k 15` the same —
      report pooled Δ for each; the parse is 844 ms of the editor read and most of the batch load, so a `max` per
      character is where it would show; state whether either Δ clears the noise floor (batch ~1%, editor ~50 ms).
      Also the seven targeted suites (`*TestSurfaceParsers *TestStatementExtents *TestTolerantRead *TestTolerantCheck
      *TestNewPipeline *TestLower *TestReplDifferential`) and `sbt 'core/testOnly *TestSurface*'` for the new
      properties. `git diff --stat` == `--stat -w`; CRLF preserved (the parsers module too — check).
7.1a.5 REPORT `tracker/loopmodel/LSP4-7.1a-MARK.md`: the design and its backtracking argument; the audit table; the
      anti-vacuity count (and the 15 named statements' marks vs extents); the Tier 1 results with the pre/post
      trace comparison and the sweep classification; the two A/Bs; every gate number; the exact shape 7.1b consumes.
      Outcomes: GREEN (mark recorded, batch byte-identical, both A/Bs free) / PARTIAL (which). IT SHIPS ONLY AS
      7.1b's PRECONDITION: if any Tier 1 gate moves, STOP and report — do not tune it into passing. STOP after the
      report — a reviewer re-runs Tier 1 once.
