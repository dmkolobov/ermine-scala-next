# LSP Stage 4, item 7.1a — THE HIGH-WATER MARK (Tier 1; 7.1b's soundness precondition)

Implementer report. Branch `scala3-migration`, from `a15a97e` (7.0 and 7.2 committed).
No commit. Scratch: `<scratch>/7.1a/`.

**OUTCOME: GREEN-CONDITIONAL**, after two fix rounds — §7.4 (the strict path made
free, on the coordinator's decision) and §4.1/§3 (the Tier-1 review's F1 and F3,
FIX-THEN-ADVANCE). The mark is built, recorded, audited and proven to survive
backtracking; every byte-identity gate is green (Tier 1 traces, the interface
sweep, g1, the corpus verdicts, the REPL goldens). **The strict path now pays
NOTHING**: `ParseState`'s default mark is `MarkOff`, whose `reach` is empty, and
only the editor's `moduleMarked` installs a live cell — batch pooled Δ **0.00 %
(median of per-side medians) / −0.41 % (mean)**, inside the ~1 % floor, against
**+0.83 % to +1.87 %** before the fix. The residual EDITOR cost is accepted as
7.1b's precondition, and the REVIEW's band is the number of record: **read +20
to +48 ms pooled, +5 to +90 ms per pair, control 0 ms, positive in 5 of 5
pairs** (my single fix-round pair, +5 ms read / +16 ms round trip, is its lucky
end).
It ships only with 7.1b: if 7.1b is reverted, 7.1a comes out with it. The
review's F1 (the site bumped one byte short of `skipTrivia`'s comment peek) and
F3 (`rawTypeText`'s bump pinned by nothing) are fixed here, with a property
apiece that has been seen to fail; F2 and F5 are corrected in §4.1, §6 and §8;
F4, F6 and F7 are written into §9 verbatim for 7.1b.

---

## 1. THE DESIGN, and why a mutable cell is the only sound shape

`ParseState` is an immutable case class copied on every advance
(`rawSatisfy` does `s.copy(loc = …, offset = sop)`), and `Parser.attempt`
backtracks by DISCARDING the state its branch produced: on failure the state
that survives is the one from BEFORE the branch (`Parser.scala:139`, and the
same for `|`, `race`, `not`, `wouldSucceed`, `handle`). A `var furthest` in the
state would therefore be thrown away together with the branch — losing exactly
the extent a failed lookahead examined, which is the only thing the mark is for
(Ohm defines `maxExaminedPos` to include input "used to make a parsing
decision", and four other systems converged on the same integer:
STAGE4-PRIOR-ART §1.10).

So the mark is **(A) a shared mutable cell**, `scalaparsers.Mark`, one per
parse, referenced by every `ParseState` copy of that parse:

* `final class Mark { def reach(end: Int): Unit = if (end > far) far = end }` —
  one `max`, and `furthest` is the EXCLUSIVE end of the examined region.
* `ParseState` gains `mark: Mark = new Mark` as its last field. `copy` carries
  the same cell, so a discarded state's examination is still recorded; a fresh
  cell is minted exactly where a fresh parse is (`ParseState.mk`, and the
  explicit states `SurfaceParsers.statementFailure` / the REPL entries build).
* `Mark.equals`/`hashCode` ignore the counter, so adding the field changes
  neither `ParseState` equality nor any state's hash — the mark is metadata,
  not state.
* Option (B), threading the furthest through `Fail`/`Commit` and taking maxima
  in every merge, is pure but touches every combinator in `Parser.scala` and
  `Monadic.scala` — a far larger Tier-1 diff for the same integer. Rejected on
  size, not on correctness.

**THE BACKTRACKING ARGUMENT IN THREE SENTENCES.** Every examination of input
position `p` goes through a site that calls `mark.reach(p + 1)` on the state it
was handed, and that state's `mark` is the same object as the enclosing parse's
(`copy` never replaces it). A combinator that backtracks returns an older
`ParseState` value, but it cannot return an older `Mark`, because there is only
one: the cell is outside the value that is rolled back. Therefore
`furthest` is monotone over the whole parse and includes every position any
branch — committed, rolled back, or merely peeked at — ever looked at, which is
precisely Ohm's examined interval and what `Parser.attempt` would otherwise
erase (pinned by the property in §4(iv): after a failed `attempt` the state
reads `offset == 0` and the mark reads 4).

**TWO KINDS, AND WHICH PATH GETS WHICH** (the fix round). The mark exists for
the editor; the strict path must pay nothing for a number it never reads. So
`ParseState`'s default is the sibling object **`MarkOff`**, whose `reach` is
empty and whose `furthest` answers `Int.MaxValue` rather than 0 — a consumer
that reads a mark it should not have read is then refused every reuse instead of
being told the parse examined nothing, so only over-conservatism is available by
accident. `SurfaceParsers.moduleMarked` is the ONE site that installs a live
`new Mark`; `module`, `readModule`, the REPL entries, the interface parser and
`statementFailure`'s slice re-parse all keep `MarkOff`. Two receivers keep the
call sites bimorphic, so the JIT inlines the empty body away — §7.4 measures
that it does.

**THE CONVENTION.** Examining position `p` is `reach(p + 1)`, Ohm's
inclusive-position rule. An end-of-input probe at `p` counts as examining `p`,
because the ABSENCE of a character is as load-bearing as its value: a parse
that stopped because nothing was at `p` depends on nothing being inserted at
`p`. A consequence, deliberate: `furthest` may exceed `input.length` by one,
and for the last statement of a file it does.

## 2. THE RECORD 7.1b CONSUMES

`SurfaceParsers.StatementMark`, one per top-level statement, in statement
order, reachable as `NewPipeline.Read.marks` from `readModuleTolerant`:

    final case class StatementMark(startLine: Int, startCol: Int,
                                   startOffset: Int, endOffset: Int,
                                   examinedEnd: Int, markAtEntry: Int) {
      def examinedLength: Int = examinedEnd - startOffset
      def consumedLength: Int = endOffset - startOffset
    }

* `startOffset`/`startLine`/`startCol` — the statement's own start (the record
  is taken AFTER `statement`'s leading whitespace skip, so it is the position
  every alternative's first `loc` reads, i.e. the statement's `Span` start).
* `endOffset` — where the whole-file parse left the offset (trailing trivia the
  token layer consumed included).
* `examinedEnd` — the parse's mark when the statement finished.
* `markAtEntry` — the mark before it started, so a consumer can see how much of
  `examinedEnd` is inherited (the mark is ONE cumulative counter per parse, so
  `examinedEnd` is an upper bound on what this statement alone examined —
  conservative in the safe direction; §5 measures how loose it is).

**THE REUSE RULE 7.1b gets**: reuse a statement iff its extent text is
byte-identical AND no edit intersects `[startOffset, startOffset + examinedLength)`.
**THE WARNING 7.1b MUST HEED**: a mark at or past the end of the parse's input
means the examination was TRUNCATED by end of input — which is what every
`statementFailure`-style SLICE re-parse does. Such an entry's true dependency
runs past its slice, so 7.1b must extend the guard (to the next extent's start,
or further) rather than trust the number. This is the same fact as 7.0 §4.3's
15 statements, seen from the cache's side.

**BATCH NEITHER OBSERVES IT NOR PAYS FOR IT.** `SurfaceParsers.module` is
untouched and `readModule` still calls it; only the tolerant read calls
`moduleMarked` (`module`'s grammar with an observation wrapper around the
statement parser), and only that entry installs a live cell. On the strict path
the field holds `MarkOff`, so every bump is an empty call: nothing is written,
nothing is read, and no Death message, position, ordering or `.ei` byte can
depend on it. §6 proves the byte-identity and §7.4 the zero cost.

## 3. THE AUDIT (7.1a.2) — every place the parse examines input

"Missing one is the Lezer 0.15.0 bug", so this table is the whole corpus of
direct reads in `parsers/src/main/scala/scalaparsers/` and
`core/.../surface/`, found by grepping `charAt`, `.input`, `substring`,
`indexOf`, `indexWhere`, `.length` and then reading each hit.

| # | site | file:line | what it reads | mark bumped? |
|---|---|---|---|---|
| 1 | `rawSatisfy` — the consuming primitive | `ParsingUtil.scala:52` | `si.charAt(so)`, and `so == si.length` | **YES**, `reach(so + 1)` BEFORE the predicate: the position is examined whether `p` holds (consumed), fails (value used to decide) or the input ran out (absence used to decide) |
| 2 | `skipSatisfy` — the fused skip | `ParsingUtil.scala:68` | `indexWhere(!p, so)`, `si.length` | **YES**, `reach(k + 1)`: `so..k-1` consumed, `k` examined to stop (or `k == length`, the end-of-input case) |
| 3 | `skipSatisfy`, input already exhausted | `ParsingUtil.scala:84` | `so < si.length` | **YES**, `reach(so + 1)` |
| 4 | `realEOF` | `ParsingUtil.scala:87` | `offset == input.length` | **YES**, `reach(offset + 1)` |
| 5 | `offside`'s EQ branch (the vsemi decision) | `ParsingUtil.scala:167` | `offset != input.length` | **YES**, bumped at `offside`'s entry instead of in the branch, which over-approximates by one character on the LT branch (a pure column comparison). Conservative, and it keeps the branch unreindented |
| 6 | `onside` | `ParsingUtil.scala:178` | `offset == input.length` | **YES**, `reach(offset + 1)` at entry — every path takes that test |
| 7 | `ParseState.layoutEndsWith`'s local `eof` | `ParseState.scala:32` | `offset == input.length` | **YES**, `reach(offset + 1)` |
| 8 | **`atLayoutBoundary` → `StatementExtents.skipTrivia`** | `SurfaceParsers.scala:862` | the trivia run after the statement, DIRECTLY on the input, a PEEK at `i + 1` to decide whether `-`/`{` opens a comment, then `charAt(i)` for `;`/`}` and `col <= depth` | **YES**, `reach(far)`, where `far` is the exclusive end `skipTrivia` now returns — every read inside it goes through `advance`, `peek` or `notEnd`, each of which records the position it read. THE site the item exists for, and the one no primitive could see. **Review F1 fixed here**: it used to record `reach(i + 1)`, one byte short of the peek, and property (vi) now pins the four inputs that flip on that byte |
| 9 | `rawTypeTextScan` — `rawTypeText`'s hand-rolled scanner | `SurfaceParsers.scala:156–200` | `charAt(i)`, `charAt(i + 1)` peeks in three branches, a forward scan to the next line's first significant column for the offside test, `lastIndexOf('\n', j-1)` backwards | **YES**, `reach(far)` where `far` tracks the exclusive end of everything touched (at most one character wider than the truth). **Review F3 fixed here**: the scanner was extracted into a named `private[reporting]` parser and property (vii) now runs it ALONE, because inside `rawTypeText` the trailing `optionalSpace` masks it |
| 10 | `Parser.slice` | `Parser.scala:167` | `s.input.substring(s.offset, t.offset)` | **NO, and proven**: the region is exactly what the inner parser consumed, so every character in it was already examined (and bumped) by the primitive that consumed it. `slice` adds no examination |
| 11 | `Pos.bump` / `Pos.bumps` | `Locations.scala:55–86` | `i.indexOf('\n', o)` — reads AHEAD to the end of the new line | **NO, and proven**: the only values derived are `Pos.current` (the caret line, for error RENDERING) and `Pos.ending`. A repo-wide grep for `.current`/`.ending` finds no reader outside `Pos.report` and `Pos.equals`; no parse decision consults either, and neither reaches a `Span` (spans carry line/col only, and `Pos.hashCode`/`Order` use file/line/col). Bumping here would widen every statement's mark to the end of the line following its last newline, for no soundness gain |
| 12 | `sameLine` | `SurfaceParsers.scala:723` | `s.loc.line` only | n/a — no input read |
| 13 | every non-consuming COMBINATOR: `not`, `wouldSucceed`, `|`, `race`, `handle`, `attempt`, `withFilter`, `filterMap` | `Parser.scala` | nothing directly | n/a — they run sub-parsers, whose examination reaches the shared cell and SURVIVES their rollback. That is the design (§1) |
| 14 | `Lexer.lexemeAt` / `isTailChar` | `Lexer.scala:53–67` | `charAt` over the buffer | n/a — **not a parse**: it is the scanner `TolerantCheck.keys` uses for 7.2's reachable-bind-item rule, recomputed from the new text on every check |
| 15 | `StatementExtents.scan` (and `skipTrivia` as the splitter's own helper) | `StatementExtents.scala:52–253` | a direct lexical pass | n/a — **not a parse**, and it must stay that way: 7.1b's whole soundness argument against Lean's "go up two commands" is that the extent list is recomputed lexically FROM THE NEW TEXT each check and never cached |
| 16 | `SurfaceParsers.offsetOf`, `statementFailure` | `SurfaceParsers.scala:872–930` | `contents.charAt` to find the slice, then a parse over the slice | n/a for this item — the slice gets its own `ParseState` and therefore its own cell, which nobody reads. **7.1b WARNING**: a slice parse's mark is truncated by the slice end (§2) |

`core/src/main/scala/.../parsing/` (the legacy fused parser, which the batch
header parse and the interface parser still use) has **no** direct input read —
`grep '\.input\b'` over all of `core/src/main/scala` outside
`surface/SurfaceParsers.scala` returns nothing, and it defines no custom
`new Parser` at all. It goes through the primitives in rows 1–7, so it gets the
mark for free and needs no audit exception.

## 4. THE TESTS (7.1a.3)

Four properties in `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala`
(`sbt 'core/testOnly *TestSurface*'`), each written so it CAN fail — P5(d)'s
lesson, "a test that has never been seen to fail has not been shown to work",
and §4.1 below plants bugs to show each one does.

* **(i) ANTI-VACUITY** — "the mark reaches PAST the statement's extent". Over
  the whole `TestSurfaceParsers` corpus — **358 `.e` files** under
  `core/src/main/resources/modules` and `core/examples` (the 253-file
  `Resident.checkFile` corpus plus the `shouldfail/` and `incomplete/` trees) —
  every recorded mark is joined to `StatementExtents.scan`'s extent for the same
  statement. It asserts (a) a record for every statement of every file
  (`marks.size == statements.size`), (b) a corpus floor of 1000 marked
  statements so a broken sweep cannot pass, (c) **at least 15 statements whose
  mark exceeds their own extent end**, and (d) — the sharp pin — that **each of
  the 15 Report.e statements 7.0 §4.3 named by start line has a mark past its
  extent**. (d) is the non-vacuous half: those 15 are exactly where
  `atLayoutBoundary`'s trivia skip was measured to look past the extent.
* **(ii) NEVER SHORT** — no statement's `examinedEnd` is below either the
  parse's own consumed end or the lexical extent's end, over the whole corpus.
* **(iii) LEAN'S COUNTEREXAMPLE IN ERMINE** — `module T where\na = 1\nb = 2\n`
  against the same buffer with `b` indented one space. The edit is strictly
  AFTER the first statement's text, yet it changes the first statement (the
  offside rule makes `b = 2` a continuation), and the property requires the
  first statement's mark to reach strictly past the offset of `b` — so the edit
  intersects `[start, start + examinedLength)` and 7.1b's guard refuses the
  reuse. This is Lean's `def a := b private def c` in Ermine's layout grammar.
* **(iv) BACKTRACKING** — `rawWord("abcdef").attempt` on `"abcxyz"`: the state
  rolls back to `offset == 0` and the mark still reads ≥ 4. The same lookahead
  inside `(rawWord("abcdef").attempt | rawWord("abc"))`: the winner consumes 3
  and the mark reads ≥ 4 — the character only the LOSER looked at.
* **(v) `atLayoutBoundary` IN ISOLATION** — added after the planted-bug run
  below showed (i) could not see that site. It runs `atLayoutBoundary` ALONE on
  a state sitting in front of a blank-line/comment run, where no primitive is
  involved at all (the parser is a `get` and a direct `skipTrivia`), and
  requires the mark to exceed the offset of the first significant character
  after the trivia.

* **(vi) THE COMMENT PEEK** (review F1). `atLayoutBoundary` alone on the four
  inputs `a = 1\n  -x\n`, `a = 1\n  --\n`, `a = 1\n  {x\n`, `a = 1\n  {-\n`:
  the first of each pair FAILS the boundary check and the second SUCCEEDS, they
  differ in the single byte at offset 9, and the property requires both the
  decisions and `mark > 9` in all four — i.e. the deciding byte inside the
  guard. Under the pre-fix `reach(i + 1)` the failing cases mark 9 and the
  property falsifies.
* **(vii) `rawTypeTextScan` ALONE** (review F3). The scanner extracted from
  `rawTypeText` (inside it the trailing `optionalSpace` examines the same byte
  through the primitives and masks the site — which is why deleting its bump
  left ten properties green and every corpus count unchanged). On `Int\nB\n`
  at depth 1 the scan stops AT the newline, consuming 3 bytes, having read the
  byte at offset 4 to learn that the next line starts at column 1; the property
  requires text `"Int"`, offset 3 and `mark > 4`, and — the flip — that the
  indented variant `Int\n B\n` runs on instead.

### 4.1 All seven pass — AND EACH ONE HAS BEEN SEEN TO FAIL

`sbt 'core/testOnly *TestSurfaceParsers'` — **12 of 12 properties, 0 failed**
(the five that were there plus the seven 7.1a ones), 35 s. Then, P5(d)'s rule
applied literally, five bugs have now been planted in scratch and the suite
re-run after each — two in the first round, three in this one:

| planted bug | (i) anti-vacuity | (ii) never short | (iii) Lean | (iv) attempt | (v) `atLayoutBoundary` | (vi) peek | (vii) `rawTypeTextScan` |
|---|---|---|---|---|---|---|---|
| none (the tree of record) | pass | pass | pass | pass | pass | pass | pass |
| **`rawSatisfy` bumps only when the character is CONSUMED** (the Lezer mistake) | pass | pass | pass | **FAIL** | pass | pass | pass |
| **`atLayoutBoundary`'s `reach` removed** | **FAIL** | pass | pass | pass | **FAIL** | **FAIL** | pass |
| **`atLayoutBoundary` back to the pre-F1 `reach(i + 1)`** | pass | pass | pass | pass | pass | **FAIL** | pass |
| **`rawTypeTextScan`'s `reach` removed** | pass | pass | pass | pass | pass | pass | **FAIL** |

**THE CORRECTION (review F2).** The first round of this report claimed that
deleting the `atLayoutBoundary` bump "changed nothing in the 358-file corpus
counts" and concluded the site was "redundant with respect to the corpus
measurement". **That was wrong, and it was wrong because the property was stated
against the wrong boundary.** The reviewer re-ran `MarkAudit` UNDER the planting
— which the first round did not — and the counts move: `mark INTO the next
extent's text` **6,954 → 6,893** (−61), `mark past the end of the input`
**347 → 336**, mean `examinedLength` 177.2 → 176.7 B. The 61 are the statements
followed by a blank line or a comment run, where the token layer's trailing
`optionalSpace` rolls back over the trivia and `skipTrivia` is the only thing
that reaches the successor. **The site is load-bearing, and the corpus shows
it.** Property (i) now asserts `intoNext == rows.size` (6,954 of 6,954), which is
strictly stronger than the extent-end form, and the planting reproduces the
reviewer's number exactly: with the bump removed the property fails with
`only 6893 of 6954 marks reach into the next extent`.

What survives from the first round's paragraph is the narrower true statement:
the corpus cannot see the LEZER mistake (under that planting the counts barely
move — max inflation 23 → 22 and nothing else), only property (iv) can; and it
could not see `rawTypeTextScan` at all, which is what property (vii) closes.

## 5. THE ANTI-VACUITY NUMBERS (7.1a.3(i)) — `<scratch>/7.1a/MarkAudit.scala`

The in-tree property asserts the floors; this scratch harness prints the
counts. Sweep: every `.e` under `core/src/main/resources/modules` and
`core/examples` — **358 files** (the whole `TestSurfaceParsers` corpus, which is
the 253-file `Resident.checkFile` corpus plus `shouldfail/`, `incomplete/` and
the group `shouldfail` trees; one file, the legacy `examples/Sample.e`, the
surface parser rejects and it is skipped), **6,954 top-level statements**:

| measure | count |
|---|---|
| statements with a mark | **6,954** (and `marks.size == statements.size` for every file, 0 mismatches) |
| mark PAST the statement's own lexical extent end | **6,954** |
| mark past the parse's own consumed end | **6,954** |
| mark INTO the next extent's text | **6,954** — and property (i) now ASSERTS this equality (review F2) |
| mark SHORT of the consumed end | **0** |
| mark SHORT of the extent end | **0** |
| mark past the end of the input (the last statement of a file) | 347 |
| mean `examinedLength` vs mean extent length | **177.2 B vs 130.6 B** (the guard is 36 % wider than the text) |

**The floor is not 15, it is all of them, and that is the finding.** Every
top-level statement's examined region ends one character INTO the following
extent, because `atLayoutBoundary` runs `skipTrivia` over the trivia after the
statement and then decides on the column of the first significant character
after it — which is the next statement's first character. So the mark is not a
rare-case guard: on this grammar a statement always depends on its successor's
first byte, which is exactly Lean's counterexample generalised, and 7.1b must
budget for one extra statement re-parse per edit (the statement BEFORE the
edited one also misses).

**WHAT THE F1 FIX MOVED: NOTHING, AND THAT IS THE POINT.** `MarkAudit` was run
twice, once against the saved pre-F1 build and once against the tree of record,
dumping every statement's `examinedEnd`: the histogram of (new − old) over all
**6,954 statements is `{0: 6954}`** — not one mark grew, not one shrank, and
every aggregate is byte-identical. That is exactly what the review predicted:
the exact `far` is `i + 1` whenever the first significant character after a
statement is not `-` or `{` (the common case), and where it IS, the token
layer's own comment attempt had already reached further. **F1 was latent, and
closing it widens no corpus guard** — it removes an audit gap that property (vi)
can witness in three lines and the corpus cannot.

**THE 15 NAMED STATEMENTS (7.0 §4.3), each individually** — `Layout/Report.e`,
591 extents / 529 real statements / 529 marks; `of the 15 named statements,
marks NOT past their extent: List()`:

| head | start line | extent end | consumed end | MARK | next extent start | examinedLength | extent length |
|---|---|---|---|---|---|---|---|
| `foreign` | 152 | 5540 | 5543 | 5544 | 5543 | 117 | 113 |
| `private` | 391 | 13303 | 13305 | 13306 | 13305 | 117 | 114 |
| `private` | 395 | 13447 | 13449 | 13450 | 13449 | 145 | 142 |
| `private` | 473 | 16312 | 16314 | 16315 | 16314 | 296 | 293 |
| `softRelation` | 642 | 22998 | 23096 | 23097 | 23096 | 240 | 141 |
| `private` | 731 | 27287 | 27289 | 27290 | 27289 | 1077 | 1074 |
| `pivotTabular` | 770 | 28343 | 28345 | **28367** | 28345 | 479 | 455 |
| `drilldownPivotTabular` | 781 | 28890 | 28893 | **28916** | 28893 | 571 | 545 |
| `sequenceSelector` | 908 | 33521 | 33523 | 33524 | 33523 | 193 | 190 |
| `makeSelectorsLateBinding` | 916 | 34013 | 34015 | 34016 | 34015 | 248 | 245 |
| `makeSelectors` | 924 | 34395 | 34397 | 34398 | 34397 | 154 | 151 |
| `private` | 1044 | 42224 | 42226 | 42227 | 42226 | 1942 | 1939 |
| `scaled` | 1110 | 43877 | 43879 | 43880 | 43879 | 147 | 144 |
| `private` | 1148 | 45306 | 45339 | 45340 | 45339 | 356 | 322 |
| `private` | 1586 | 77359 | 77385 | **77386** | 77385 | 10734 | 10707 |

Two rows are worth reading twice. `pivotTabular` (770) and
`drilldownPivotTabular` (781) have a mark **22–23 bytes past** the next extent's
start: a failed lookahead INSIDE the following statement, recorded only because
the cell survives `attempt` — the exact case a `var` on the state would have
lost. And `private` at 1586, the file's last statement, has its mark at 77,386 =
`input.length + 1`: end of input examined, the convention of §1.

**HOW LOOSE THE CUMULATIVE COUNTER IS, MEASURED.** The mark is one counter per
parse, so a statement's `examinedEnd` also covers whatever earlier statements
examined. `markAtEntry − startOffset` is that inheritance: it is positive for
all 6,954 statements (the previous statement's boundary check always read this
statement's first byte) and its **maximum over the corpus is 23 bytes**. So the
simple one-cell design is at most 23 bytes more conservative than a per-statement
child cell would be, against a mean `examinedLength` of 177 — which is why 7.1a
ships the cumulative counter and not the nested one. If 7.1b ever wants the
tighter number, `markAtEntry` is in the record and the refinement is a child
`Mark` merged at the statement boundary.

## 6. TIER 1 (7.1a.4) — the parser library changed, so all of it

The pre-change side is the **compiled tree at `a15a97e`**, saved as
`<scratch>/7.1a/classes-before/{core,parsers}` before a line was edited and run
from the repo while the compiled classes were still the old ones — no scratch
worktree was needed, and the comparison is therefore between two builds of the
same checkout rather than between two checkouts. One JVM at a time throughout
(the `looptrace` replays are Lean binaries, not JVMs; the compiler side of every
group is sequential).

### 6.1 `looptrace-corpus.sh` + `trace-ab.py` — IDENTICAL, all record kinds

18 groups, `LOOPTRACE_PAR=3`, `-Dermine.loadInSeries=true` (the default),
before and after:

| | before | after |
|---|---|---|
| groups | 18/18, rc 0, **0 timeouts, 0 dropped segments** | 18/18, rc 0, 0 timeouts, 0 dropped |
| solve segments (per-group totals) | 3,206,083 | 3,206,083 |
| Lean model agreement | **every segment agrees, 0 skips** | **every segment agrees, 0 skips** |

`trace-ab.py` per group, ALL sixteen record kinds (the F3 review's full
comparison, not the narrowed `KEEP` tuple):

    Ai 83976 IDENTICAL  Algebra 101039 IDENTICAL  Algebra-shouldfail 55401 IDENTICAL
    boot 54209 IDENTICAL  bugs 54245 IDENTICAL  guide 54254 IDENTICAL
    incomplete 1905718 IDENTICAL  Lang 91334 IDENTICAL  Lang-shouldfail 58789 IDENTICAL
    Present 131392 IDENTICAL  Present-shouldfail 59503 IDENTICAL
    shouldfail 56040 IDENTICAL  shouldfail-controls 54749 IDENTICAL
    Time 125134 IDENTICAL  Time-shouldfail 55932 IDENTICAL  top 92707 IDENTICAL
    Wide 115874 IDENTICAL  Wide-shouldfail 55787 IDENTICAL

**3,206,083 paired segments, 3,206,083 IDENTICAL, `sinmoved=0` in every group,
rc 0 in every group** — and the reviewer's independent run of the same
differential reproduces both numbers exactly. Not one `Supply` bound moved, so the mark does not
perturb id draw order — the hazard Decision (b) and `ROW-CONSTRAINT-STATE.md`
insist be measured rather than assumed. (The 3.21 M paired segments are fewer
than the 3.36 M each side reports because `trace-ab.py` pairs by index within a
group and reports the pairs.)

### 6.2 `ei-diff.sh --snapshot --batch` with `-Dermine.loadInSeries=true`, both sides

One side per build, `EI_BATCH_CHUNK=5`, the six group libraries hoisted, in
series on both sides (never one batched side against a per-file side, the
header's rule):

| | before | after |
|---|---|---|
| interfaces captured | **268** | **268** |
| only on one side | — | — |

`ei-classify.py`: **0 of 268 interfaces differ**, and every one of the **3,481
published bindings** classifies as `identical` — not order-only, not
alpha-equivalent, identical strings. No `.ei` byte depends on the mark.

### 6.3 `g1-validate.sh`

**9 of 9 PASS**, both before (run on the pre-change tree for a baseline) and
after: the four comparator fixtures, the two type-equivalence fixtures, the
129-module double run (`1447 signatures, EQUIVALENT` both times) and **no drift
from `tracker/g1-baseline`**. The checked-in baseline is unchanged and needed no
refresh, which is the correct outcome for a change that is not supposed to move
a signature.

## 7. THE TWO INTERLEAVED A/Bs — the one gate that moved, and the fix that closed it

§7.1–§7.3 are the FIRST round, where the counter ran on both paths; §7.4 is the
fix round of record, where the strict path gets a no-op mark. The numbers the
trackers should carry are §7.4's.

`<scratch>/7.1a/ab.sh`: the two sides are the saved `classes-before` /
`classes-after` trees, selected by rewriting **both** the core and the parsers
entry of `tracker/repl-classpath.txt` (7.1a changes both modules, so 7.2's
core-only swap would have measured nothing). `perf-bench.sh` cannot be the
wrapper, for 7.0's reason unchanged (its `pgrep -f 'sbt-launch|xsbt\.boot'`
preflight matches an orchestrator shell that merely names those strings), so the
same shapes are run directly: `perf-bench.sh batch -n 3`'s three cold
interface-free 129-module loads per side, and `perf-bench.sh editor -k 15`'s
`perf-client.py --rounds 15` on `Layout/Report.e`. Each side waits for the
1-minute load to fall under 1.3 first; every side started between 1.12 and 1.26.

**FOUR PASSES, TWO ORDERS.** The first pass ran before/after/before/after as the
brief asks. Its four medians came out strictly increasing in RUN ORDER
(1.676 → 1.715 → 1.743 → 1.831 s), which is the pattern 7.2 recorded as the
harness heating up — and in a b,a,b,a order that drift lands entirely on the
"after" side. So the whole thing was run again in the REVERSE order
(after/before/after/before). Pooling the two orders cancels a linear drift
exactly: the mean run position is 4.5 for each side. **No code was changed
between the passes**; this is more measurement, not tuning.

### 7.1 BATCH — `Loaded 129 modules (N seconds)`, medians of 3 reps per side

| order | before | after | Δ |
|---|---|---|---|
| b,a,b,a | 11.69 / 11.71 | 11.90 / 11.84 | **+0.170 s (+1.45 %)** |
| a,b,a,b | 12.53 / 12.64 | 12.54 / **13.20** | **+0.285 s (+2.26 %)** |
| **pooled, mean of the four per-side medians** | **12.143 s** | **12.370 s** | **+0.227 s (+1.87 %)** |
| pooled, median of the four | 12.120 s | 12.220 s | +0.100 s (+0.83 %) |

The machine was ~7 % slower during the second pass than the first (11.7 → 12.6 s
on the SAME before-side build), which is why the pooled figure matters more than
either pass. One side, `ra2`, has a visible outlier rep (12.89–13.90 s); it is
what separates the mean estimate (+1.87 %) from the median one (+0.83 %). **The
honest reading: +0.1 to +0.23 s on a 12.1 s load, i.e. +0.8 % to +1.9 %, against
a noise floor the roadmap puts at ~1 %.** That is at or just above the floor, and
the sign is positive in all four pairs.

### 7.2 EDITOR — `Layout/Report.e`, 15 rounds, round 1 discarded, median of 14

| metric | pooled before (4 sides) | pooled after (4 sides) | Δ (mean) | Δ (median) |
|---|---|---|---|---|
| **round trip** | **1.7067 s** | **1.7648 s** | **+58.0 ms (+3.40 %)** | +52.5 ms |
| read (parse+rename+lower) | 0.8662 s | 0.9087 s | **+42.5 ms (+4.91 %)** | +50.0 ms |
| typecheck — **the control** | 0.5138 s | 0.5288 s | +15.0 ms (+2.92 %) | +10.0 ms |
| cold `didOpen` | 2.1902 s | 2.2415 s | +51.3 ms | +22.0 ms |
| boot | 12.395 s | 12.643 s | +247.5 ms | +190.0 ms |
| reused | 97/154 | 97/154 | — | — |

Per-pair round-trip Δ: **+39, +88, +109, −4 ms**. Per-pair read Δ: **+40, +30,
+105, −5 ms**.

**THE INTERNAL CONTROL IS WHAT MAKES THIS READABLE.** `typecheck` is pure
inference: it does not parse and it cannot read the mark, so its +15 ms is the
harness's own between-run spread on this sequence. The read moved **+42.5 ms**,
nearly three times that, in the one phase the change touches, and in 3 of 4
pairs. So the editor Δ is **at the roadmap's ~50 ms noise floor and plausibly
just above it** — the read's own drift band is 0.795–0.865 s on an unchanged
tree (G3), and 0.866 → 0.909 s sits at the edge of it.

### 7.3 Where the cost was — the analysis the fix round then tested

Two things on the per-character hot path changed, and only measurement can
apportion them:

1. **`ParseState` gained a seventh field.** `rawSatisfy` copies the state for
   every consumed character, so every character now allocates one extra
   reference slot. Nothing about the counter's VALUE is involved.
2. **The `reach` itself** — one field read, one compare, an occasional write,
   per examined position.

Neither is avoidable in design (A); option (B) trades the field for a merge in
every combinator. Three things the reviewer may want to weigh, none of them done
here because the brief says not to tune a moved gate:

* the batch path does not NEED the counter — the brief requires only that batch
  never observes it — so a `-D`-gated `reach` (or a `Mark.off` singleton whose
  `reach` is empty, installed by `readModule`'s entry and not by the editor's)
  would make the batch and boot numbers exactly zero at the cost of a flag on a
  shared path, which the Stage-4 invariants discourage;
* `onside`'s unconditional bump and `offside`'s (the over-approximating one) are
  the only bumps not on the consuming primitive's path, and both run per layout
  decision;
* the measurement itself is at the harness's limit: 7.0's protocol (50 reps
  after 20 warm-ups, medians, in-process timers via `-Dermine.lsp.phases=true`)
  would settle the read's +42 ms far better than 4 × 15 rounds can, and would
  cost one more JVM-hour.

### 7.4 THE FIX ROUND — the strict path made free, and what that measured

The coordinator's decision: **batch must pay nothing for a mark it never reads**;
the editor's cost is accepted as 7.1b's precondition. THE CHANGE, and it is the
smallest one available: `ParseState`'s default field value becomes `MarkOff`
(empty `reach`), and `SurfaceParsers.moduleMarked` — the editor-only entry —
installs a live `new Mark`. Nothing else moved: no parse behaviour, no
combinator, no other entry point.

**THE CANDIDATE QUESTION, ANSWERED BY MEASUREMENT.** The brief asked whether the
seventh `ParseState` field — copied per character by `rawSatisfy` — is itself the
cost, in which case the field would have to leave `ParseState` (candidate (b):
carry the cell in the `Supply`-like thread instead). **The field is still there
in the fix round, and the batch Δ is zero**, so the field copy is NOT measurable
and candidate (b) was not built. What the pre-fix +1.87 % bought was the `reach`
WORK on the strict path (a getfield, a compare and an occasional putfield per
examined position, on every character of the 129-module stdlib), not the extra
reference slot. Candidate (a) — a no-op `reach` whose receiver keeps the site
bimorphic so the JIT can inline the empty body — is sufficient.

**BATCH A/B, both orders, 3 reps per side, load 1.15–1.28 at every start:**

| order | before | after (fix) | Δ |
|---|---|---|---|
| b,a,b,a pass 1 | 12.14 | 11.78 | **−0.36 s** |
| b,a,b,a pass 2 | 12.04 | 12.17 | +0.13 s |
| a,b,a,b pass 1 | 12.09 | 11.98 | **−0.11 s** |
| a,b,a,b pass 2 | 12.06 | 12.20 | +0.14 s |
| **pooled, mean of the four per-side medians** | **12.082 s** | **12.032 s** | **−0.050 s (−0.41 %)** |
| **pooled, median of the four** | **12.075 s** | **12.075 s** | **0.000 s (0.00 %)** |

The four pairs now straddle zero (−0.36, +0.13, −0.11, +0.14) where before the
fix all four were positive (+0.21, +0.13, +0.01, +0.56). **Inside the ~1 % floor
on both poolings, and by sign as well as by magnitude: the batch pays nothing.**
No `.ei` was written during any interface-free rep (the harness checks).

**EDITOR A/B, one pair (the residual the coordinator asked for):**

| metric | before | after (fix) | Δ |
|---|---|---|---|
| round trip | 1.671 s | 1.687 s | **+16 ms (+0.96 %)** |
| read | 0.835 s | 0.840 s | **+5 ms (+0.6 %)** |
| typecheck — the control | 0.515 s | 0.520 s | +5 ms |
| cold `didOpen` | 2.220 s | 2.153 s | −67 ms |
| boot | 12.45 s | 12.63 s | +180 ms |
| reused | 97/154 | 97/154 | — |

**THE BAND OF RECORD IS THE REVIEWER'S, NOT THIS PAIR (review F5).** One pair is
the lucky end. The reviewer ran five interleaved pairs (two on the tree of
record, three on an equivalent build) and pooled them:

| metric | per-pair Δ (ms) | pooled mean | pooled median |
|---|---|---|---|
| round trip | +97, +73, +45, +42, +14 | **+54 ms (+3.2 %)** | +45 ms |
| **read** | +80, +90, +30, +35, +5 | **+48 ms (+5.7 %)** | +35 ms |
| typecheck — the control | +15, −15, +5, +5, −10 | **0 ms** | +5 ms |
| cold `didOpen` | +92, +91, +73, +19, +31 | +61 ms | +73 ms |

So the number the trackers should carry is **read +20 to +48 ms pooled, +5 to
+90 ms per pair, control 0 ms, positive in 5 of 5 pairs** — the editor's cost is
REAL, my single fix-round pair (+5 ms read) sits at its bottom end, and the
first round's four pairs (+42.5 ms) near its top. The acceptance reasoning is
unchanged and is the coordinator's: ~6 % of the 0.84 s read, inside 7.1b's
200 ms gate with room, and it comes out with 7.1b if 7.1b is reverted.

## 8. TIER 0 — every number

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | **success**, 18 s; 21 warnings, all pre-existing (`Pretty.scala`, `TolerantCheck.scala:685`, the scalaz `Either.right` deprecations) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree, 0 skipped, hashdiff 0, eqdiff 0** (9.76 s); 3 properties passed |
| `corpus-run.sh --batch` verdicts | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, one JVM, exit 0 |
| the same outputs against the pre-change run | **byte-identical, 154 of 154 files**, once the progress-bar frames (`[===...] 42% 1.7s`) and the `(N seconds)` totals are normalised (`diff -r` rc 0, 0 lines). Before the normalisation the only differences are progress frames and timings |
| `repl-smoke.sh` | **8 groups / 66 checks PASS** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status` shows **no golden modified** |
| `lsp-smoke.sh` | **480 checks PASS** — the 7.2 baseline, unchanged. **No check was added, deliberately**: nothing about the mark reaches the protocol (it is written and read by nobody on every path a client can exercise), so an lsp-smoke check could only assert something that is already asserted by §4's properties. The Stage-4 invariant's count therefore stays 480 for this item, and the Baselines note needs no edit |
| boot | **129 modules (11.99 s)**, `bin/ermine` |
| the seven targeted suites (`*TestSurfaceParsers *TestStatementExtents *TestTolerantRead *TestTolerantCheck *TestNewPipeline *TestLower *TestReplDifferential`) | **103 passed, 0 failed, 0 errors** on the final tree (the earlier run, before property (v) was added, was 90 + `TestLoopTrace`'s 3 = 93); `TestTolerantRead`'s strict-vs-tolerant corpus agreement and `TestStatementExtents`' 271-file scanner agreement both still green |
| `git diff --stat` vs `git diff --stat -w --histogram` | **identical**: **460 insertions / 29 deletions** either way, no line differing only in whitespace. Per file (`--numstat`): NewPipeline 17/4, StatementExtents 26/7, SurfaceParsers 139/10, ParseState 11/3, ParsingUtil 19/5, TestSurfaceParsers 248/0. (Review F5: the first round quoted 321/17, which was its own pre-property-(v) patch rather than the tree) |
| line endings | every file this item touches is **LF** in the tree, `parsers/` included (`grep -c $'\r'` is 0 on all 13 `scalaparsers/*.scala`, all 5 `surface/*.scala`, `NewPipeline.scala` and `TestSurfaceParsers.scala`), and they are LF after the edit — all edits were byte-wise, never through a text-mode rewrite |
| **THE FIX ROUND's re-runs** (coordinator's item 3) | `*TestSurfaceParsers` **10/10** (the five 7.1a properties still pass, the editor path keeping its live mark); `TestLoopTrace` **720/720, 0 skipped**; `corpus-run.sh --batch` **85/69/0 over 154** and **byte-identical to the pre-change run again** (normalised `diff -r` rc 0); `g1-validate.sh` **9/9, EQUIVALENT, no drift**; `repl-smoke.sh` **8 groups / 66 checks**, goldens untouched; `MarkAudit` output **byte-identical to the first round** — the editor still records exactly the same 6,954 marks. Tier 1's traces and interface sweep were NOT re-run (the change is which `Mark` the strict path constructs; no parse behaviour can differ) — the reviewer re-runs full Tier 1 once |
| **THE SECOND FIX ROUND's re-runs** (review F1/F3) | `sbt core/clean core/compile core/copyResources` **success** (the E046 quirk below makes the clean mandatory); `*TestSurfaceParsers` **12/12**; three further plantings each falsifying exactly the property that owns the site (§4.1); `MarkAudit` **every aggregate byte-identical, and the per-statement `examinedEnd` histogram `{0: 6954}`** — F1 moved no corpus mark; `TestLoopTrace` **720/720, 0 skipped**; `corpus-run.sh --batch` **85/69/0 over 154** and **byte-identical to the pre-change run** a third time; the seven targeted suites **105 passed / 0 failed** (`TestStatementExtents` among them — `skipTrivia`'s signature changed); `repl-smoke.sh` **8 groups / 66 checks**, goldens untouched; `g1-validate.sh` **9/9, EQUIVALENT, no drift** |
| zinc note for whoever edits these files | an INCREMENTAL `core/compile` after touching `Mark.scala` or `ParseState.scala` can fail with **27 `E046 Cyclic reference involving val <import>`** errors in the legacy `parsing/ParseState.scala`. It is zinc recompiling a subset of the `ermine` package, not a real cycle: `sbt core/clean core/compile` succeeds in 38 s, and the same sources then build incrementally. Recorded in `Mark.scala`'s docstring too |
| `.ei` hygiene | every `.ei` this item caused is deleted; the checked-in `tracker/g1-*` baselines are untouched (`git status` clean apart from the five edited sources, the new `Mark.scala` and this report) |

## 9. VERDICT — **GREEN-CONDITIONAL**: it ships as 7.1b's precondition

**GREEN on the mark itself:**

* recorded per statement, observable from the tolerant reader, total (one per
  statement, 0 mismatches over 358 files);
* it survives backtracking, and **every one of the seven properties has been
  SEEN to fail** — five plantings, each falsifying exactly the property that
  owns its site (§4.1);
* it exceeds the extent for all 6,954 corpus statements and for each of the 15
  Report.e statements 7.0 §4.3 named, two of them by 22–23 bytes of pure failed
  lookahead;
* **the batch path is byte-identical on every gate that can see it**: 3,206,083
  trace segments IDENTICAL with `sinmoved=0`, 268 of 268 interfaces and 3,481 of
  3,481 bindings identical, g1 9/9 twice with no baseline drift, 154 of 154
  corpus verdict outputs byte-identical twice (before and after the fix round),
  REPL goldens untouched twice, lsp-smoke 480;
* the audit found nine examining sites and bumps all nine, with two reasoned
  non-bumps and five non-parse sites excluded — and after the review, the two
  bespoke ones are EXACT and PINNED: `atLayoutBoundary` records the `far`
  `skipTrivia` now returns (F1; it used to stop one byte short of the comment
  peek) and `rawTypeTextScan` has an isolation property of its own (F3).

**GREEN on cost for the path that does not want it.** After the fix round the
strict path constructs `MarkOff` and pays nothing: batch pooled Δ **0.00 %**
(median of per-side medians) / **−0.41 %** (mean), four pairs straddling zero,
where the first round had +0.83 % to +1.87 % with four positive pairs. The
measurement also answers the brief's question about the seventh `ParseState`
field: it is still copied per character and the Δ is zero, so the field is not
the cost and candidate (b) — moving the cell out of `ParseState` — is
unnecessary.

**CONDITIONAL on 7.1b, which is the roadmap's own condition.** The EDITOR still
pays for the counter it uses: **+16 ms round trip / +5 ms read** in the fix
round's pair (control +5 ms), **+58 / +42.5 ms** pooled over the first round's
four pairs — an honest band of **+5 to +42 ms on the read**, accepted by the
coordinator against 7.1b's expected ~0.7 s saving and its 200 ms gate. 7.1a is
useless alone and ships only as 7.1b's precondition: **if 7.1b is reverted, 7.1a
comes out with it.** The one number a reviewer should re-measure is the editor
read, pooled, ideally with 7.0's in-process 50/20 protocol rather than 4 × 15
rounds.

### THE OBLIGATIONS 7.1b INHERITS — the reviewer's F4, F6 and F7, verbatim

> **F4 — what the mark cannot express, and what must therefore stay in the KEY.** The guard is
> forward-only, and a statement's parse also depends on text BEFORE `startOffset`: its own
> start COLUMN (the layout decision that makes the next line a continuation) and the
> enclosing layout depth. `Pos.bump` counts columns from the bytes before the statement on
> its line; `statementFailure` seeds `IndentedLayout(startCol, "statement")` for exactly
> that reason. So 7.1b's reuse condition must include "the statement's `(startLine,
> startCol)` — or at least its column and its enclosing block — is what it was", which it
> gets free if the key is the scanner's extent identity plus `startCol`. This is not a
> gap in 7.1a; it is a condition the mark cannot carry and that must not be forgotten
> because the mark looks like a complete dependency set.

> **F6 — the records are matched to statements by POSITION, silently.** `moduleMarked`
> accumulates records in a `LinkedHashMap` keyed `(loc.line, loc.column)` at statement
> entry and then rebuilds the list as `m.statements.flatMap(st => seen.get(key(st)))`. The
> key is sound (positions are distinct, a rolled-back attempt at the same position is
> overwritten by its retry with a LARGER mark, and the driver's discarded last iteration
> simply never matches a statement), and `marks.size == statements.size` holds for all
> 6,954 statements of 358 files. But `flatMap` + `get` DROPS a record it cannot match
> instead of failing, and the report invites 7.1b to "zip them". If a future grammar change
> ever made one statement's `Span` start differ from its parse's entry position, the list
> would be one short and a positional zip would attach every later statement's mark to the
> WRONG statement — which is the one way this design can hand out a too-small guard.
> OBLIGATION: 7.1b joins by `(startLine, startCol)`, never by index; and `moduleMarked`
> should make a mismatch visible (return the map, or keep the pairing with the statement it
> came from) rather than leaving an in-tree property as the only thing standing between a
> grammar change and a silent misalignment.

> **F7 — two things the record does not cover, which 7.1b must state rather than discover.**
>
> 1. **The 62 header extents have no mark.** `moduleP` parses the header with `header(...)`
>    before the statement loop, and only the statement parser is wrapped, so
>    `import`/`export` lines (62 of Report.e's 591 extents — 7.0's reuse unit was "529
>    statements + 62 header extents") get no record at all. 7.1b must treat header
>    extents as uncacheable, or extend the recording to the header grammar.
> 2. **The truncation warning is prospective, not actual.** No record today can be
>    truncated by a slice end: `statementFailure`'s slice state keeps `MarkOff` and
>    records nothing, and only `moduleMarked` (a whole-file parse) produces records. The
>    347 statements whose mark is `input.length + 1` are last-statements-of-file, where
>    "examined the end of input" is the honest answer. The obligation is real but it binds
>    7.1b's OWN miss path (if it installs a live cell on a slice re-parse), and the
>    implementer's §2 wording reads as though such records already exist.
>
> 3. **A rendered diagnostic is not guarded by the mark.** `Pos.report` embeds the caret
>    LINE (`Pos.current`, read ahead by `Pos.bump` and deliberately not bumped, §2), so
>    any cached RENDERED text can go stale on bytes outside `[startOffset, examinedEnd)`.
>    Today the editor's `Diag` uses `err.message`, not `err.pretty`, so nothing a client
>    sees depends on it; 7.1b must not start caching `pretty`/`report` output without
>    widening the guard.

One correction to §2 that F7(2) earns: this report's "a mark at or past the end
of the parse's input means the examination was TRUNCATED — which is what every
slice re-parse does" is written as though such records exist. They do not
today; slice re-parses keep `MarkOff` and produce no record, and the 347
end-of-input marks are last-statements-of-file. The obligation binds 7.1b's own
miss path, when it installs a live cell on a slice.

### What 7.1b consumes, exactly

1. `NewPipeline.readModuleTolerant(...).marks: List[SurfaceParsers.StatementMark]`
   — one record per top-level statement of `Read.surface.statements`, in the
   same order (the property in §4(i) pins `marks.size == statements.size` over
   the whole corpus, so 7.1b may zip them).
2. Per record: `startLine`, `startCol`, `startOffset`, `endOffset`,
   `examinedEnd`, `markAtEntry`, plus `examinedLength` and `consumedLength`.
   Offsets are absolute in the buffer that was parsed, so they compose with
   `StatementExtents.Offsets` and with `Anchors` (7.2) without conversion —
   `startLine`/`startCol` are the statement's `Span` start, which is what
   `Anchors.relSpan`/`absSpan` re-anchor, and the scanner's extent for the same
   statement is found by `(startLine, startCol)`, the key `TolerantCheck.keys`
   already groups on.
3. The guard: reuse iff the extent text is byte-identical AND no edit
   intersects `[startOffset, startOffset + examinedLength)`.
4. THREE OBLIGATIONS 7.1b inherits with it, each a consequence of §1–§2 and
   none of them optional:
   * **Carry the mark forward.** STAGE-4 INVARIANT "REUSE METADATA SURVIVES
     REUSE" (survey §1.9, swift-syntax #3397): a reused statement's cache entry
     must keep ITS mark, not acquire the mark of the parse that reused it —
     which in the splice is not even computed for a reused statement.
   * **A truncated mark is not a mark.** A record whose `examinedEnd` reaches
     the end of the parse's input examined the boundary and was cut off there.
     No record produced TODAY is of that kind (F7(2): slice re-parses keep
     `MarkOff` and record nothing; the 347 such marks are last-statements-of-
     file) — but the moment 7.1b installs a live cell on a `statementFailure`
     slice for a miss, its guard must be widened to at least the next extent's
     start, or it re-creates the Lezer 0.15.0 bug on its own miss path.
   * **The reachable/unreachable rule still governs the KEY.** 7.2's rule (a
     bind item is reachable iff its head word is the whole identifier lexeme)
     decides what `TolerantCheck` can key at all; the mark decides only when a
     keyed entry may be reused. An unreachable item's text goes into the scope
     key today, and 7.1a changes nothing about that: `StatementMark` is keyed by
     position, not by spelling, so a statement with an empty or truncated head
     word still gets a mark and 7.1b can cache it by extent ordinal even while
     its TYPES stay uncacheable.
5. What 7.1b must NOT do: read the mark on the strict path (it is `Nil` there),
   put `examinedLength` in a cache KEY (it is a property of the parse, not of
   the text — two identical texts in different surroundings have different
   marks), or treat the mark as the statement's extent (it is deliberately
   wider; the extent comes from `StatementExtents.scan`).

## 10. Files changed

| file | what |
|---|---|
| `parsers/src/main/scala/scalaparsers/Mark.scala` | **NEW, 77 lines** — the cell (`reach`, `furthest`, the backtracking argument, the end-of-input convention, `equals`/`hashCode` that keep it out of state equality) **plus `MarkOff`**, the strict path's no-op whose `furthest` is `Int.MaxValue` |
| `parsers/src/main/scala/scalaparsers/ParseState.scala` | `mark: Mark = MarkOff` as the last field (`copy` carries the cell; `ParseState.mk` mints one per parse), and the `reach` in `layoutEndsWith`'s local `eof` |
| `parsers/src/main/scala/scalaparsers/ParsingUtil.scala` | five bumps: `rawSatisfy` (before the predicate), `skipSatisfy` (both branches), `realEOF`, `offside`, `onside` |
| `core/.../surface/StatementExtents.scala` | **review F1**: `skipTrivia` returns `(offset, line, col, examinedEnd)` — every read inside it goes through `advance`, `peek` or the new `notEnd`, each recording the position it read, so the caller gets the exact extent the scan looked at instead of guessing `i + 1`. Its decisions, positions, lines and columns are unchanged, and it has exactly one caller |
| `core/.../surface/SurfaceParsers.scala` | the `reach(far)` in **`atLayoutBoundary`** (F1) and in `rawTypeTextScan`; `rawTypeText`'s anonymous scanner extracted into the named `private[reporting] rawTypeTextScan` so it can be pinned alone (F3); `statement` split into `statement` + `statementBody`; `module`'s driver factored into `moduleP`; **NEW** `StatementMark` and `moduleMarked` (the editor-only entry that records one mark per top-level statement, and the only site that installs a live `new Mark`) |
| `core/.../rename/NewPipeline.scala` | `Read.marks` (defaulted to `Nil`), and the tolerant branch that calls `moduleMarked` while the strict branch keeps calling `module` |
| `scalacheck-binding/src/main/scala/TestSurfaceParsers.scala` | the **seven** 7.1a properties and their corpus join (`markRows`), property (i) now asserting `intoNext == rows.size` (F2); the two that build their own `ParseState` ask for a live `new Mark`, since the default is now the strict path's `MarkOff` |
| `tracker/loopmodel/LSP4-7.1a-MARK.md` | **NEW** — this report |

Scratch, deliberately not in the tree (`<scratch>/7.1a/`): `MarkAudit.scala` (§5's
counts), `ab.sh` (§7), `tier1-after.sh` (§6), `dotc.sh`, the saved
`classes-before` / `classes-after` trees, and every run's raw log.

No commit. `tracker/LSP-ROADMAP.md` and `tracker/lean/` untouched.

---

## 11. For the reviewer — how to re-run Tier 1 once

The pre-change side is already captured, so a re-run needs only the after side:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    sbt -batch -J-Xmx3g core/clean core/compile core/copyResources   # clean: the E046 quirk
    sbt -batch -J-Xmx3g 'core/testOnly *TestSurfaceParsers'    # 12/12, the seven 7.1a properties
    sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'         # 720/720
    tracker/tools/corpus-run.sh --batch <out>                  # 85/69/0 over 154
    tracker/tools/repl-smoke.sh ; tracker/tools/lsp-smoke.sh   # 66 checks ; 480 checks
    LOOPTRACE_PAR=3 tracker/tools/looptrace-corpus.sh <out>    # ~20 min, then per group
    tracker/tools/trace-ab.py <scratch>/7.1a/lt-before/traces/<g>.tsv.gz <out>/traces/<g>.tsv.gz --name <g>
    tracker/tools/ei-diff.sh --snapshot --batch <out> "-Dermine.loadInSeries=true"
    python3 tracker/tools/ei-classify.py <scratch>/7.1a/ei-before <out>
    tracker/tools/g1-validate.sh                               # 9/9
    AFTER=<scratch>/7.1a/classes-after2 <scratch>/7.1a/ab.sh both   # the fix-round build
    #   ORDER=ab for the reverse pass, TAG=<s> to name the logs, PASSES=1 for one pair

`<scratch>/7.1a/` holds `classes-before`, `classes-after` (first round) and
`classes-after2` (**the tree of record, with `MarkOff`**) (core AND parsers —
BOTH classpath entries must be swapped or the parser change is not in the
measurement), the before-side `lt-before/` traces and `ei-before/` snapshot, the
A/B logs (`ab.log` first round, `ab-rev.log` its reverse pass, `ab-fix.log`
the fix round), `MarkAudit.scala` with its outputs (`markaudit.txt` = `markaudit2.txt` = `markaudit3.txt`) and the per-statement dumps `dump-old.tsv` / `dump-new.tsv` whose `examinedEnd` histogram is `{0: 6954}`, `tier1-after.sh`, and
`change.patch` — the diff as it stood before property (v) was added, used to
prove the two planted bugs were reverted byte-for-byte (they were: `--numstat`
identical on all four source files).

Every `.ei` this item caused has been deleted; `tracker/g1-*` is untouched; no
JVM and no polling shell is left running. STOPPED after this report.
