# LSP Stage 4, item 7.1a — INDEPENDENT REVIEW of the high-water mark (Tier 1)

Reviewer report. Branch `scala3-migration`, tree = `a15a97e` + the uncommitted 7.1a
deliverables (5 modified sources, new `parsers/.../Mark.scala`, report
`tracker/loopmodel/LSP4-7.1a-MARK.md`). Implementer report: `LSP4-7.1a-MARK.md`.
Review brief: `briefs/brief-LSP4-7.1a-review.md`. Scratch: `<scratch>/review-7.1a/`.
No commit; the only tree edits were the THREE temporary plantings of §3 (P1, P2, P3),
each reverted and hash-checked (`md5sum -c` over 17 files — all 14 of
`parsers/src/main/scala/scalaparsers/` plus the three other edited sources — and
`git diff --numstat` identical before and after every planting); `tracker/g1-*`,
`tracker/lean/` and `tracker/LSP-ROADMAP.md` untouched. Every `.ei` caused here is
deleted; no JVM and no polling shell of mine is left running.

**VERDICT: FIX-THEN-ADVANCE** — two small fixes (F1, one character in
`atLayoutBoundary`; F3, one property), two corrections to the implementer's report
(F2, F5), three obligations to write into 7.1b's brief (F4, F6, F7). The mechanism is
sound, the batch pays nothing at the gate's resolution, and every byte-identity gate is
green on my own runs. Details in §8.

---

## 1. THE SOUNDNESS ARGUMENT — checked, and it holds

**(1a) No parse ever continues from a state carrying a different cell.** I enumerated
every construction of a `ParseState` in the whole repository
(`grep -rn "ParseState\s*(\|ParseState\.mk\|new ParseState"` over `parsers/src`,
`core/src`, `scalacheck-binding/src`), and every `.copy(` in `parsers/`:

* constructions: `ParseState.mk` (the only one in the library),
  `SurfaceParsers.statementFailure`'s repositioned state (named arguments, `mark`
  omitted → `MarkOff`), `PrimT.scala:288` (positional, 3 args → `MarkOff`),
  `moduleMarked`'s `ParseState.mk(...).copy(mark = new Mark)`, and the two test
  states in `TestSurfaceParsers` which ask for a live `Mark` explicitly. There is
  **no construction inside any combinator or any `Parser` body** — the 12 `.copy(`
  sites in `ParsingUtil.scala` all change `loc`/`offset`/`bol`/`layoutStack` and
  therefore carry the same cell, and `Parser.scala` never builds a state at all
  (every combinator passes on the `s` it was handed or the `t` out of a `Commit`).
  `Monadic.scala` is derived entirely from `flatMap`/`map2`/`|`/`orElse`, so it adds
  no construction either.
* `statementFailure` is the one repositioned state, and it is called from
  `NewPipeline.read`'s POST-PARSE diagnostics loop (`NewPipeline.scala:146`), never
  from inside a parser. Its slice parse therefore gets its own (no-op) cell that
  nobody reads, which is what the report claims.
* **Conclusion:** examinations cannot be recorded into a cell nobody reads, because
  within one `moduleMarked` parse there is exactly one cell and every state in that
  parse is a `copy`-descendant of the one that was minted with it.

**(1b) `furthest` is never read during a parse.** `grep -rn furthest` over the whole
tree finds readers only in `SurfaceParsers.moduleMarked` (`record`, and `val at`) and
in the five properties of `TestSurfaceParsers`. No combinator, no primitive, no layout
rule consults it, so the mark cannot influence parsing. On the strict path nothing
reads it at all (`Read.marks` is `Nil` and has no reader anywhere yet — `grep` for
`\.marks\b` finds only the write).

**(1c) `Mark.equals`/`hashCode` are defensive, not relied on.** Nothing in the repo
compares two `ParseState`s or puts one in a set or map (`grep` for `ParseState` with
`==`/`Set[`/`Map[`/`distinct`/`contains`). The generated `ParseState.equals` does
compare the `mark` field, so the override is what keeps a seventh field from changing
state equality should anyone ever compare states (e.g. via `Commit`, a case class
holding a state); it costs nothing and I would keep it.

**(1d) Monotonicity over backtracking.** `attempt` only rewrites an `Err` into a
`Fail` (`Parser.scala:139`); the rollback is structural — `|`, `race`, `handle`,
`not`, `wouldSucceed` and `flatMap`'s `Pure` case all re-enter the alternative with
the SAME `s` they were given, and `Fail`/`Err` carry no state at all. So the only
state that can survive a failed branch is an older VALUE, never an older cell, and
`reach` is a `max`. Property (iv) pins it and I saw it fail under planting P2 (§3).

**(1e) Thread safety.** `MarkOff.reach` is an empty override and `far` is never
written on it, so the process-wide singleton is read-only under the parallel loader;
a live cell belongs to one `moduleMarked` call on one thread. No hazard.

**(1f) The fail-safe direction is right.** `MarkOff.furthest = Int.MaxValue` makes a
mistaken read refuse every reuse; `startOffset + examinedLength` is then exactly
`Int.MaxValue` and cannot overflow for any `startOffset ≥ 0`.

## 2. THE AUDIT, redone independently

I re-grepped `charAt|\.input\b|substring|indexOf|indexWhere|lastIndexOf|regionMatches|
startsWith|codePointAt|subSequence|\.length` over all 14 files of
`parsers/src/main/scala/scalaparsers/` and all 5 of `core/.../surface/`, and read every
hit. I agree with the implementer's 16 rows: 9 bumped, 2 reasoned non-bumps, 5
not-a-parse, and I found **no site they missed**. Two rows needed real work:

* **`Pos.bump`/`Pos.bumps` (row 11) — non-bump CONFIRMED.** The read-ahead
  (`i.indexOf('\n', o)`) feeds only `Pos.current` and `Pos.ending`. `grep` for
  `\.ending` over `core/src`, `parsers/src`, `scalacheck-binding/src` finds exactly one
  reader, `Pos.equals` (`Locations.scala:101`); `current` is read only in `Pos.report`
  and in `Pos.start`. No parse decision, no `Span` (spans are four `Int`s, taken from
  `loc.line`/`loc.column`), no layout column (columns come from `bump`'s counting, not
  from the line text), and `V.equals`/`hashCode` are the integer id alone, so a
  position never reaches name resolution or unification. NOTE for 7.1b, not for 7.1a:
  `Pos.report` renders the caret LINE, so a rendered `Err.pretty` does depend on bytes
  the mark does not cover. The editor's diagnostics are built from `err.message`, not
  `err.pretty` (`NewPipeline.scala:150`), so nothing the LSP returns depends on it
  today — but a future cache of rendered text would (F7).
* **`Parser.slice` (row 10) — non-bump CONFIRMED.** `s.input.substring(s.offset,
  t.offset)` spans exactly the region the inner parser consumed, and every consumed
  character went through `rawSatisfy`/`skipSatisfy`, which bump before/at the
  predicate. `slice` adds no examination.
* **`rawTypeText`'s `far` (row 9) — checked branch by branch**, including the
  backwards `in.lastIndexOf('\n', j - 1)`: the scan cannot run below `i`, because
  `in.charAt(i) == '\n'` is the loop's entry condition for that branch, so the
  backwards read stays inside `[i, j)` which `far ≥ j + 1` already covers. `i` is
  monotone and the final `far = max(far, i + 1)` covers every consumed position
  (string bodies and line comments included). Over-approximates by ≤ 1; never under.
* **"the grammar always depends on its successor's first byte" — the rule is
  `token`, not `atLayoutBoundary`.** Every token is `p << optionalSpace.skipOptional`,
  and `optionalSpace` → `layout` → `whiteSpace(...).many` can only stop by EXAMINING
  the first non-trivia character (`rawSatisfy` bumps before its predicate), after
  which `offside`/`onside` bump `offset + 1` for the vsemi decision. So the last token
  of a statement already reaches one byte into the successor; `atLayoutBoundary` then
  reaches further when the trivia run contains blank lines or comments that the token
  layer rolled back over (which is exactly the 61 statements of F2 below).

### 2.1 F1 — the one site that is bumped ONE BYTE SHORT

`StatementExtents.skipTrivia` decides whether to keep skipping by PEEKING at `i + 1`:

    else if (c == '-' && peek(1) == '-') { ... }      // line comment
    else if (c == '{' && peek(1) == '-') { ... }      // block comment
    else more = false

so when the first significant character is `-` or `{` and the next character does not
complete a comment opener, the stop decision consumed the value at `i + 1` — and
`atLayoutBoundary` bumps only `st.mark.reach(i + 1)`, whose exclusive end covers
position `i` and not `i + 1`. `peek` also reads the ABSENCE of a character at `i + 1`
(it answers `' '` past the end), which by this item's own convention is an
examination.

WITNESS (scratch `ReviewProbe`, the shape of property (v) — `atLayoutBoundary` run
ALONE on a state at offset 5, depth 1):

| input | `atLayoutBoundary` | mark |
|---|---|---|
| `a = 1\n  -x\n` | FAILS ("does not fill its layout item") | 9 |
| `a = 1\n  --\n` | SUCCEEDS | 12 |
| `a = 1\n  {x\n` | FAILS | 9 |
| `a = 1\n  {-\n` | SUCCEEDS | 12 |

The two inputs of each pair differ in the single byte at offset **9**, i.e. at exactly
`mark`, i.e. the first byte OUTSIDE the guard `[start, examinedEnd)` — and the site's
decision flips. That is the Lezer-0.15.0 shape, one byte wide, in the site the item is
named for, and none of the five properties can see it (property (v) asserts only
`furthest > yAt`, the offset of the first significant character).

It is NOT reachable through `moduleMarked` today, and I measured that rather than
assuming it: a guard probe that mutates the byte AT `examinedEnd` (6 mutant characters
`- { x ; space tab`) for **2,142 statements over 255 corpus files** plus 7 crafted
two-statement files found **0 cases** where an earlier statement's parse changes. The
masking is the token layer again: at a `-`/`{` the `whiteSpace` loop has already tried
`rawWord("--")`/`rawWord("{-")`, whose second `rawSatisfy` examines `i + 1` (visible
in the probe's numbers: for `module T where\na = 1\n-x\n` the first statement's
`examinedEnd` is 23, two bytes past the `-`).

So F1 is LATENT, not live — but the masking is an accident of an unrelated combinator
(`whiteSpace`'s comment alternative, and whether `stillOnside` lets it run), the audit
row claims the site bumps what it examines, and 7.1b's soundness is supposed to rest
on the audit rather than on that accident. **FIX: `st.mark.reach(i + 2)`** (one
character; strictly conservative; cannot change any parse) or, better,
`skipTrivia` returning its own `far`. It should be accompanied by one property in the
shape of the table above.

## 3. ANTI-VACUITY AND THE PLANTED-BUG MATRIX — reproduced, with one correction

`MarkAudit` re-run on my build: **output byte-identical to the implementer's**
(`diff markaudit.txt markaudit-review.txt` → no output), so all of §5 of their report
reproduces exactly: 358 files (+1 rejected), **6,954** statements with a mark,
**6,954** past the lexical extent end / past the consumed end / into the next extent's
text, **0** short of either, 347 past input end, 0 count mismatches, mean
`examinedLength` 177.2 B vs extent 130.6 B, max inflation **23** bytes — and the
15-row Report.e table, including `pivotTabular` 28367 and `private`@1586 = 77386 =
`input.length + 1`, row for row.

The two plantings, each compiled from the tree of record with a byte-wise edit and
reverted byte-for-byte afterwards (`md5sum -c` clean, `--numstat` identical):

| planted bug | (i) | (ii) | (iii) | (iv) | (v) | suite |
|---|---|---|---|---|---|---|
| none | pass | pass | pass | pass | pass | 10/10 |
| `atLayoutBoundary`'s `reach` removed | pass | pass | pass | pass | **FALSIFIED** | 9 + 1 failed |
| `rawSatisfy` bumps only on consume | pass | pass | pass | **FALSIFIED** | pass | 9 + 1 failed |

Matches the implementer's matrix exactly (and their own logs `plant1b.txt` /
`plant2.txt`).

### 3.1 F2 — the report's §4.1 "finding" is wrong: the corpus DOES distinguish site 8

Their §4.1 says that deleting the `atLayoutBoundary` bump "changed **nothing** in the
358-file corpus counts: the mark still reached one byte into the next extent for all
6,954 statements", and concludes the site is "redundant with respect to the corpus
measurement, and required by inspection". I re-ran `MarkAudit` **under the planting**
(they did not — there is no planted `MarkAudit` output in their scratch) and the counts
move:

| measure | tree of record | site-8 bump removed |
|---|---|---|
| mark INTO the next extent's text | 6,954 | **6,893** (−61) |
| mark past the end of the input | 347 | **336** |
| mean `examinedLength` | 177.2 B | 176.7 B |
| mark past the lexical extent end | 6,954 | 6,954 (unchanged) |

61 statements lose their reach into the successor, which is why property (i) — stated
against the EXTENT end, not the next extent's start — stays green and the planting
looked invisible. The 61 are statements followed by a blank line or a comment run
(`Date.e:82 gap='\n\nmon'`, `SortStrategy.e:44` with a comment line, `Syntax.e:21`,
`Yahoo.e:215` …): the token layer's trailing `optionalSpace` rolls back over that
trivia (the vsemi), while `skipTrivia` scans all of it, so site 8 is the only thing
that reaches the successor there. **The site is load-bearing, and the corpus shows
it.** Two consequences: the report's §4.1 paragraph must be corrected (it currently
understates its own work), and the anti-vacuity property would be strictly stronger
stated against the NEXT EXTENT'S START (6,954 of 6,954 today) rather than the extent
end — that version would have caught the planting without needing property (v).

Under the rawSatisfy planting (P2) the corpus counts barely move at all (max
inflation 23 → 22, everything else identical), which confirms the other half of the
implementer's argument: the corpus cannot see the Lezer mistake, only property (iv)
can.

### 3.2 F3 — a THIRD planting: `rawTypeText`'s bump is covered by nothing

The brief asks which site could be un-bumped without any property noticing, so I
planted a third bug: **delete `s.mark.reach(far)` from `rawTypeText` entirely** (the
whole 40-line hand-rolled scanner's contribution, audit row 9), clean-compile, run the
suite and `MarkAudit`.

    *TestSurfaceParsers: 10 of 10 properties passed, 0 failed
    MarkAudit: every corpus count byte-identical to the tree of record

So the item's largest bespoke bump — the one site besides `atLayoutBoundary` that reads
the input directly, with its own hand-computed `far` over five branches including a
backwards `lastIndexOf` — is pinned by **no property and no corpus number**. It is
correct today (I checked it branch by branch, §2), but nothing would notice if it
regressed, which is the same class of exposure property (v) was added to close for site
8. FIX: one isolation property in property (v)'s shape (run `rawTypeText` alone on a
multi-line annotation whose continuation line decides the offside stop, and require the
mark to exceed the offset of the first character of the following line). Reverted
byte-for-byte; `md5sum -c` clean.

## 4. BATCH PAYS NOTHING — re-checked in the code, and re-measured

### 4.1 The code: exactly one live cell, and the strict path never reads it

`ParseState`'s default is `MarkOff`, and there is exactly ONE site in the repository
that installs a live cell: `SurfaceParsers.moduleMarked`'s
`ParseState.mk(...).copy(mark = new scalaparsers.Mark)` (`SurfaceParsers.scala:1057-58`;
`grep -rn "copy(mark"` finds it plus the two test states and nothing else). Every other
entry reaches `ParseState.mk` or an explicit constructor and therefore `MarkOff`:

| strict entry | how it gets `MarkOff` |
|---|---|
| `SurfaceParsers.module` (the batch/strict whole-file parse) | `ParseState.mk`, `:980` |
| `SurfaceParsers.typeExpr`, `expression` (REPL/kindOf) | `ParseState.mk`, `:1072`, `:1082` |
| `SurfaceParsers.statementFailure`'s slice re-parse | explicit `ParseState[Unit](...)`, `mark` argument omitted, `:939` |
| the legacy `parsing` package — REPL `Console.parseState`, `Session` module header + INTERFACE body parse, `Resident`, `G1Compare`, `NewPipeline.readHeaderOnly` | `ErParseState.mk` → `SPPS.mk` → `ParseState.mk` |
| `PrimT.scala:288` (the relational primitive-type parser) | positional `ParseState(Pos, s, s = ())`, `:288` |

`NewPipeline.read` calls `moduleMarked` only when `tolerant`, and `readModuleTolerant`
is called only from `lsp/Resident.checkFile` and from tests; `readModule` (batch, REPL,
interface load) keeps `module` and `marks = Nil`. Nothing on the strict path reads
`furthest` — nothing anywhere does yet except `moduleMarked` itself and the properties
(§1b). CONFIRMED as the report claims.

### 4.2 The batch A/B, my numbers (tree of record vs the `a15a97e` build)

`perf-bench.sh batch`'s shape run directly (`ab.sh`: three cold interface-free
129-module loads per side, `-Dermine.useInterface=false`, `.ei` deleted before each
side, both the core AND the parsers classpath entry swapped), **four pairs in two
orders** (b,a,b,a then a,b,a,b), every side started with the 1-minute load between
**1.11 and 1.28**:

| order | before | after | Δ |
|---|---|---|---|
| b,a,b,a pass 1 | 11.85 | 12.09 | +0.24 s |
| b,a,b,a pass 2 | 11.98 | 11.91 | −0.07 s |
| a,b,a,b pass 1 | 11.81 | 11.99 | +0.18 s |
| a,b,a,b pass 2 | 12.01 | 11.92 | −0.09 s |
| **pooled, mean of the four per-side medians** | **11.912 s** | **11.977 s** | **+0.065 s (+0.55 %)** |
| **pooled, median of the four** | **11.915 s** | **11.955 s** | **+0.040 s (+0.34 %)** |
| all 12 reps per side | 11.908 ± 0.158 | 11.953 ± 0.111 | +0.045 s (+0.38 %), permutation p = 0.44 |

The pairs straddle zero (+0.24, −0.07, +0.18, −0.09) and no pooling is distinguishable
from noise. A second four-pair run earlier in the session, against a build differing
from the tree of record by one line that cannot affect timing (P3's missing
`rawTypeText` bump — see §3.2; if anything it favours the after side), gave
**+0.080 s (+0.67 %)** mean / **+0.085 s (+0.71 %)** median, pairs +0.08, −0.06, +0.14,
+0.16, rep-level p = 0.49. **Eight pairs in total: Δ between +0.04 and +0.09 s on a
~12 s load, i.e. +0.3 % to +0.7 %, inside the ~1 % floor on every pooling, with five of
eight pairs positive.** So: **batch pays nothing at this gate's resolution.** I would
not claim it is exactly zero — the sign is positive in both runs' means and in every
boot sample, and the honest upper bound is about +0.1 s (+0.8 %) — but that is the
floor, and it is a sixth of the pre-fix round's +1.87 %.

### 4.3 The editor residual, five pairs — the number for the roadmap

`perf-client.py --rounds 15` on `Layout/Report.e`, round 1 discarded, median of 14,
interleaved, load 1.11–1.28 at every start. Two pairs are the tree of record (F1, F2
below); three are the P3-build run described above, pooled with them because the one
line that differs cannot move a timing (and biases the after side DOWN, not up):

| metric | per-pair Δ (ms) | pooled mean | pooled median | record-only pairs |
|---|---|---|---|---|
| **round trip** | +97, +73, +45, +42, +14 | **+54 ms (+3.2 %)** | +45 ms | +28 ms |
| **read (parse+rename+lower)** | +80, +90, +30, +35, +5 | **+48 ms (+5.7 %)** | +35 ms | +20 ms |
| typecheck — **the control** | +15, −15, +5, +5, −10 | **0 ms** | +5 ms | −2.5 ms |
| cold `didOpen` | +92, +91, +73, +19, +31 | +61 ms | +73 ms | +25 ms |
| boot (129 modules, LSP harness) | +260, +190, −240, −220, ±0 | ≈ 0 | — | — |
| reused | 97/154 both sides in all five pairs | — | — | — |

**The control makes this readable, and it reads differently from the implementer's
single pair.** `typecheck` is pure inference and cannot see the mark: its pooled Δ is
exactly **0 ms** over five pairs, while `read` — the one phase the change touches — is
positive in **5 of 5** pairs (sign test p = 0.03) at a pooled **+48 ms**, and cold
`didOpen`, which is a full read, is positive in 5 of 5 too. So the editor's cost is
REAL and the honest band is **+5 to +90 ms per pair, ≈ +20 to +50 ms pooled** — which
brackets both of the implementer's figures (their fix-round single pair said +5 ms;
their first-round four pairs said +42.5 ms) and should replace the "+5 to +42 ms" band
in the trackers with **"read +20 to +48 ms pooled, +5 to +90 ms per pair, control 0"**.
Either end is inside 7.1b's 200 ms gate and is ~6 % of the 0.84 s read, which is the
coordinator's accepted precondition — but the roadmap should carry the pooled number,
not the lucky pair.

## 5. TIER 1 — re-run once, on my own build (these are the numbers of record)

The pre-change side is the implementer's saved `classes-before`, which I verified three
independent ways rather than inheriting: (a) `javap` says its `ParseState` constructor
takes **six** arguments and its `SurfaceParsers$` has no `moduleMarked`/`StatementMark`;
(b) the class-file inventories of the two trees differ by **exactly seven** entries —
`Mark`, `Mark$`, `MarkOff`, `MarkOff$`, `SurfaceParsers$StatementMark`,
`StatementMark$`, `SurfaceParsers$$anon$3` — and nothing else, in either module; (c)
every artefact I produced from MY build came out byte-identical to an artefact produced
from THAT tree (the three rows below), which is the comparison the gate is for.

| gate | implementer | **mine** |
|---|---|---|
| `looptrace-corpus.sh`, `LOOPTRACE_PAR=3` | 18/18 groups, rc 0, 0 timeouts, 0 dropped | **18/18, rc 0, 0 timeouts, 0 dropped**, 3,206,083 segments, **every segment agrees with the Lean model, 0 skipped** |
| `trace-ab.py` per group, ALL 16 record kinds, vs the pre-change traces | "3,206,083 paired, IDENTICAL, sinmoved=0" (the report's §6.1 prose says 3,356,073 segments per side; the per-group totals in both logs sum to 3,206,083 — F5) | **3,206,083 of 3,206,083 IDENTICAL in all 18 groups, `sinmoved=0` in every group, rc 0 in every group** |
| `ei-diff.sh --snapshot --batch`, `-Dermine.loadInSeries=true`, `EI_BATCH_CHUNK=5` | 268 captured both sides | **268 captured** (7 m 13 s) |
| `ei-classify.py` vs the pre-change snapshot | 0 of 268 differ, 3,481 bindings identical | **0 of 268 differ, 3,481 of 3,481 bindings `identical`** — and the raw `diff -r` of the two snapshot directories is **empty**, i.e. byte-identical files, not merely equivalent |
| `g1-validate.sh` | 9/9, EQUIVALENT, no drift | **9 of 9 PASS**, `129 files, 1447 signatures, EQUIVALENT`, **no drift from `tracker/g1-baseline`** (2 m 13 s); `tracker/g1-*` untouched |

No `.ei` survived: `find . -name '*.ei'` outside `tracker/g1*` is **0** after every stage.

## 6. TIER 0 — every number, mine

| gate | implementer | **mine** |
|---|---|---|
| `sbt core/clean core/compile core/copyResources` | success, 18 s (incremental) / 38 s (clean) | **success, 37 s** (clean; the documented `E046 Cyclic reference` trap did not appear because every compile here was clean) |
| `*TestSurfaceParsers` | 10/10 | **10 of 10 properties, 0 failed** |
| the seven targeted suites + `TestLoopTrace` | 103 + 3 | **106 passed, 0 failed, 0 errors** (103 + 3), 6 m 38 s |
| `TestLoopTrace` | 720/720, 0 skipped | **720 solves / 720 segments / 720 agree, 0 skipped, hashdiff 0, eqdiff 0** |
| `corpus-run.sh --batch` | 85/69/0 over 154 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, one JVM, exit 0, 39 s |
| corpus outputs vs a pre-change run | byte-identical once progress frames and `(N seconds)` are normalised | **byte-identical, 154 of 154** — my after-side run against the implementer's pre-change run, normalised for progress frames / `(N seconds)` / `took N ms` only (`diff -r` rc 0, 0 bytes of output). Two different builds, two different days, same bytes |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups PASS / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); no golden modified |
| `lsp-smoke.sh` | 480 | **480 checks PASS** |
| boot | 129 modules, 11.99 s | **`Loaded 129 modules (12.05 seconds)`**, `bin/ermine` |
| `git diff --stat` vs `--stat -w --histogram` | identical, 321 / 17 | **identical, 334 insertions / 17 deletions either way**; no line differs only in whitespace; no trailing whitespace introduced. The report's 321/17 is its pre-property-(v), pre-fix-round patch (F5); per file now: NewPipeline 17/4, SurfaceParsers 118/5, ParseState 11/3, ParsingUtil 19/5, TestSurfaceParsers 169/0, plus untracked `Mark.scala` (77 lines) |
| line endings | LF everywhere | **LF everywhere**: `grep -c $'\r'` is 0 on all 14 `scalaparsers/*.scala`, all 5 `surface/*.scala`, `NewPipeline.scala`, `TestSurfaceParsers.scala` |
| `.ei` hygiene | all deleted | **0** by `find`, in the repo and in both saved class trees; `tracker/g1-*` and `tracker/lean/` untouched |
| tree state after the review | — | sources **byte-identical to the tree of record** (`md5sum -c` over 17 files, `git diff --numstat` identical), one fresh clean build in place, no JVM and no polling shell of mine left running |

## 7. IS THE RECORD SUFFICIENT FOR 7.1b? — yes, with three obligations named

`StatementMark(startLine, startCol, startOffset, endOffset, examinedEnd, markAtEntry)`
plus `examinedLength`/`consumedLength`, one per top-level statement in order, `Nil` on
the strict path. My answer: **sufficient for the reuse rule as the roadmap states it,
and the cumulative single cell can never produce a TOO-SMALL guard** — subject to F6
and the two notes below, which belong in 7.1b's brief.

**Why the guard cannot be too small (the proof obligation discharged).** Let `p` be any
input position examined during statement *i*'s own parse, at or after `startOffset`.
Every examination goes through a site that calls `reach(p + 1)` on a state whose cell is
the parse's one cell (§1a), `reach` is a `max`, and the record is taken when
`statementBody` returns — so `examinedEnd ≥ p + 1`, i.e. `p ∈ [startOffset,
examinedEnd)`. Cumulativity can only make `examinedEnd` LARGER than statement *i*
alone needs (`examinedEnd = max(markAtEntry, i's own furthest)`), and `markAtEntry −
startOffset ≤ 23` bytes corpus-wide (measured; its own maximum, reproduced), against a
mean `examinedLength` of 177 B — so the over-approximation is ≤ 23 B and in practice 0,
and it can only refuse a reuse. **`markAtEntry` is the right thing to record** (it is
the only way to see the inheritance at all with one cell), but it must be used ONLY to
refine the END or to diagnose; using it as the guard's START would exclude the
statement's own first bytes and is the one unsound way to read this record. I would say
so in the record's docstring.

**F6 — the records are matched to statements by POSITION, silently.** `moduleMarked`
accumulates records in a `LinkedHashMap` keyed `(loc.line, loc.column)` at statement
entry and then rebuilds the list as `m.statements.flatMap(st => seen.get(key(st)))`. The
key is sound (positions are distinct, a rolled-back attempt at the same position is
overwritten by its retry with a LARGER mark, and the driver's discarded last iteration
simply never matches a statement), and `marks.size == statements.size` holds for all
6,954 statements of 358 files. But `flatMap` + `get` DROPS a record it cannot match
instead of failing, and the report invites 7.1b to "zip them". If a future grammar change
ever made one statement's `Span` start differ from its parse's entry position, the list
would be one short and a positional zip would attach every later statement's mark to the
WRONG statement — which is the one way this design can hand out a too-small guard.
OBLIGATION: 7.1b joins by `(startLine, startCol)`, never by index; and `moduleMarked`
should make a mismatch visible (return the map, or keep the pairing with the statement it
came from) rather than leaving an in-tree property as the only thing standing between a
grammar change and a silent misalignment.

**F4 — what the mark cannot express, and what must therefore stay in the KEY.** The guard is
forward-only, and a statement's parse also depends on text BEFORE `startOffset`: its own
start COLUMN (the layout decision that makes the next line a continuation) and the
enclosing layout depth. `Pos.bump` counts columns from the bytes before the statement on
its line; `statementFailure` seeds `IndentedLayout(startCol, "statement")` for exactly
that reason. So 7.1b's reuse condition must include "the statement's `(startLine,
startCol)` — or at least its column and its enclosing block — is what it was", which it
gets free if the key is the scanner's extent identity plus `startCol`. This is not a
gap in 7.1a; it is a condition the mark cannot carry and that must not be forgotten
because the mark looks like a complete dependency set.

**Re-anchoring.** `startOffset`/`endOffset`/`examinedEnd` are ABSOLUTE offsets in the
buffer that was parsed, and 7.2's `Anchors` re-anchor lines/columns, not byte offsets.
A record carried forward across an edit that shifts text is stale in all three. The
relative field `examinedLength` is the one that survives, and it is in the record — so
7.1b should carry `examinedLength` (and `consumedLength`) forward and re-derive
`startOffset` from the CURRENT `StatementExtents.scan`, never carry an absolute offset.
With that, the record satisfies the Stage-4 invariant "REUSE METADATA SURVIVES REUSE".

**F7 — two things the record does not cover, which 7.1b must state rather than discover.**

1. **The 62 header extents have no mark.** `moduleP` parses the header with `header(...)`
   before the statement loop, and only the statement parser is wrapped, so
   `import`/`export` lines (62 of Report.e's 591 extents — 7.0's reuse unit was "529
   statements + 62 header extents") get no record at all. 7.1b must treat header
   extents as uncacheable, or extend the recording to the header grammar.
2. **The truncation warning is prospective, not actual.** No record today can be
   truncated by a slice end: `statementFailure`'s slice state keeps `MarkOff` and
   records nothing, and only `moduleMarked` (a whole-file parse) produces records. The
   347 statements whose mark is `input.length + 1` are last-statements-of-file, where
   "examined the end of input" is the honest answer. The obligation is real but it binds
   7.1b's OWN miss path (if it installs a live cell on a slice re-parse), and the
   implementer's §2 wording reads as though such records already exist.

3. **A rendered diagnostic is not guarded by the mark.** `Pos.report` embeds the caret
   LINE (`Pos.current`, read ahead by `Pos.bump` and deliberately not bumped, §2), so
   any cached RENDERED text can go stale on bytes outside `[startOffset, examinedEnd)`.
   Today the editor's `Diag` uses `err.message`, not `err.pretty`, so nothing a client
   sees depends on it; 7.1b must not start caching `pretty`/`report` output without
   widening the guard.

## 8. FINDINGS AND VERDICT

| id | severity | status | one line |
|---|---|---|---|
| **F1** | MEDIUM | CONFIRMED | `atLayoutBoundary` bumps `reach(i + 1)` but `skipTrivia` PEEKS at `i + 1` to decide whether a `-`/`{` opens a comment, so the site records one byte less than it examined; witnessed by a decision flip on exactly that byte (§2.1), masked end-to-end today by the token layer's comment attempt (0 violations in a 2,142-statement mutation probe), invisible to all five properties. FIX: `reach(i + 2)`, one character, strictly conservative, cannot change a parse. |
| **F2** | MINOR (report) | CONFIRMED | The report's §4.1 "THE FINDING" — that removing the site-8 bump changes NOTHING in the corpus counts — is false: `MarkAudit` under that planting gives `mark INTO the next extent` **6,893 instead of 6,954** and `past input end` 336 instead of 347 (they re-ran the properties, not the harness). The site IS load-bearing, for 61 statements, all of them followed by blank lines or comment runs. Correct the paragraph, and strengthen property (i) to assert `intoNext` (6,954 of 6,954 today) — that assertion alone would have caught the planting. |
| **F3** | MEDIUM | CONFIRMED | `rawTypeText`'s bump (audit row 9, the other direct-read site, five branches and a backwards `lastIndexOf`) is pinned by NOTHING: deleting it leaves 10/10 properties green and every corpus count byte-identical (§3.2). FIX: one isolation property in property (v)'s shape. |
| **F4** | MINOR (obligation) | CONFIRMED | The guard is forward-only, so the statement's own start COLUMN and enclosing layout depth — dependencies on bytes BEFORE `startOffset`, via `Pos.bump`'s column counting and `statementFailure`'s `IndentedLayout(startCol)` — must stay in 7.1b's reuse condition; the mark cannot carry them and looks like a complete dependency set. |
| **F5** | MINOR (report) | CONFIRMED | Three numbers in the report are off: the editor residual (their fix-round single pair, +5 ms read / +16 ms round trip, is the lucky end of a band my five pairs put at **+5 to +90 ms per pair, +20 to +48 ms pooled, control 0**); "3,356,073 solve segments" (both sides' per-group totals sum to **3,206,083**); and `git diff --stat` "321 insertions / 17 deletions", which is their pre-property-(v) patch — the tree is **334/17**. |
| **F6** | MINOR (obligation) | CONFIRMED | `moduleMarked` matches records to statements by `(line, column)` through a silent `flatMap`+`get`; 7.1b must join by position, never zip by index, and the mismatch should be made visible rather than left to a property (§7). |
| **F7** | MINOR (obligation) | CONFIRMED | Three gaps to state in 7.1b's brief rather than discover: the 62 header (`import`/`export`) extents get NO mark (the header is parsed before the statement loop), the truncation warning is prospective (no record today can be truncated — slice parses keep `MarkOff`), and a rendered diagnostic's caret line is outside the guard (§7). |
| — | — | REFUTED | No site missed in the audit; no path where a parse continues from a different cell; `furthest` never read during a parse; the two reasoned non-bumps (`Parser.slice`, `Pos.bump`) are correct; `Mark.equals`/`hashCode` are defensive only; the batch gates are byte-identical on my own runs. |

### VERDICT: **FIX-THEN-ADVANCE**

Take F1 (`reach(i + 2)` in `atLayoutBoundary`) and F3 (one isolation property for
`rawTypeText`) before the commit — together they are one character and one property, and
neither can change a parse, so Tier 0 plus `*TestSurfaceParsers` and a `MarkAudit` re-run
is the whole re-validation (F1 will move `examinedLength` by ≤ 1 byte for some
statements; nothing else can move). Correct F2 and F5 in `LSP4-7.1a-MARK.md`. Write F4,
F6 and F7 into 7.1b's brief as stated obligations. Then 7.1a advances as 7.1b's
precondition, on the coordinator's standing decision that it ships with 7.1b and comes
out with it.

Everything the item claims about the mechanism holds, and it holds for the reasons
claimed: one shared cell, monotone across backtracking, minted once per parse, read by
nobody during the parse, `MarkOff` on every strict entry, and 6,954 of 6,954 corpus
statements with a mark that reaches into their successor. The two gates the roadmap set
are met — the batch path is byte-identical on every gate that can see it (3,206,083
trace segments IDENTICAL with `sinmoved=0`, 268 of 268 interfaces byte-identical, g1 9/9
with no baseline drift, 154 of 154 corpus outputs byte-identical, REPL goldens untouched,
lsp-smoke 480), and the anti-vacuity floor is not 15 statements but all of them.

**One note on the written acceptance criterion, for the record rather than to re-open
it:** the roadmap's 7.1a asks for "an interleaved A/B on BOTH targets (batch load and
editor round trip) showing the counter is free". Batch is free at the gate's resolution
(+0.3 % to +0.7 %, pairs straddling zero). The EDITOR is not free — +48 ms pooled on the
read, 5 of 5 pairs positive against a control of 0 — and ships only because the
coordinator accepted that residual as 7.1b's precondition against its expected 0.55–0.78 s
saving and its 200 ms gate. That is a decision, not a measurement, and it should be
visible as one in the roadmap line.
