# LSP Stage 4, item 7.1b — THE STATEMENT-EXTENT SURFACE CACHE (Tier 0 + Tier 2 at adoption)

Implementer report.  Branch `scala3-migration`, from `9180d28` (7.0, 7.2 and 7.1a committed).
No commit.  Scratch: `<scratch>/7.1b/`.

**OUTCOME: GREEN.**  The corpus differential is **0 mismatches over 2,613
multi-edit steps on 253 files** — the spliced `SModule` equals a fresh whole-file
parse span for span, and the tolerant read's diagnostics are equal, at every
step.  The adoption gate asked the READ to move by 200 ms pooled; it moved by
**790 ms** (0.8425 s -> 0.0525 s), and the round trip on `Layout/Report.e` went
**1.681 s -> 0.896 s**.

> ### CLOSING ROUND — what changed after the review (`LSP4-7.1b-REVIEW.md` §6, verdict ADVANCE)
>
> | id | severity | disposition |
> |---|---|---|
> | **R-3** | LOW (latent) | **FIXED IN CODE, both sides, with a property that HANGS rather than fails if the guard is removed.**  An entry whose `consumedLength` is 0 would make the hit arm a committed no-op and `sepEndBy(semi)` would spin on it — non-termination, not a wrong tree.  The miss path now refuses to CACHE one (`end > s.offset`) and `reusable` refuses to REUSE one (`e.consumedLength > 0`), so the property holds for a cache from any source and not only for one this code built.  §1.2, and property (iv) in §3.2. |
> | **R-1** | LOW | **CORRECTED, with the reviewer's number.**  "+2.8 ms (0.4 %)" was an in-process figure with a warm JIT; on a cold JVM a first open pays **30–70 ms** (their pair's cold open 2.298 → 2.353 s, +55 ms; mine 2.311 → 2.338 s, +27 ms; the server's own cold READ 0.92/0.94 → 1.01/1.00 s theirs, 0.93/0.97 → 0.93/1.00 mine).  §5.1 carries both numbers and says which is which. |
> | **R-2+** | LOW (mine) | One more row in `docs/lsp.md` was stale in the same direction and is now labelled rather than silently re-used: the **worst-case wait for a request sent during a check** (1.47 s) was measured when the check was 0.84 + 0.50 s and is now an UPPER BOUND, because the check is 0.05 + 0.50 s.  Not re-measured — G4 owns that row. |
| **R-2** | LOW | **`docs/lsp.md` REFRESHED** (the coordinator moved this from G4 into this round): the keystroke row is now ≈0.90 s = 0.05 read + 0.50 typecheck + 0.30 debounce on the reviewer's pair (1.69 → 0.90 s), with a new WORST-SITE row (≈1.5 s, was ≈2.2 s), an honest cold-open row (2.35 s, 30–70 ms slower), a corrected fast-mode paragraph, and one paragraph saying what the cache is and what it retains. |
> | **R-4** | LOW (observation) | **NOTED, NOT FIXED** — `Resident.checkFile` scans the extents twice per check (~2.3 ms each, now 4 % of the 52 ms read).  Tidy-up for 7.7/G4; fixing it means touching the check path, which this item promised not to.  §5.1. |
>
> The review's own numbers (reverse run order, fresh seeds) are the ones of record where they differ from mine: read **0.8375 → 0.0500 s (−788 ms)**, round trip **1.691 → 0.896 s**, differential 0 mismatches on seed 71 and two fresh seeds, eleven constructed attacks all missing correctly, the strict path frozen against its own pre-change build.

---

## 1. THE DESIGN IN FOUR PARTS

### 1.1 The key — `(headWord, ordinal among the extents with that head word)`

`SurfaceCache.Key(headWord, ordinal)`, computed by `keysOf` over
`StatementExtents.scan(contents).items` in source order, the ordinal counted
**per head word** (rust-analyzer's `ErasedFileAstId` with its warning attached):
inserting a new `foo` statement shifts the ordinals of the other `foo`s and of
nothing else.  Both components are recomputed lexically **from the new text on
every check** — no identity, no offset, no line number is in a key
(STAGE-4 INVARIANT "NO IDENTITY IN A CACHE KEY").

**THE UNREACHABLE ITEMS (7.2's rule), decided and stated.**  An operator
definition (empty head word), a backtick name, a spelling the scanner truncates
at `_` or `'` — 7.2 calls these *unreachable* because `TolerantCheck`'s
`groups` cannot be looked up by their spelling — **are keyed exactly like every
other extent**, by the head word the scanner produced; the empty head words
simply form the `""` sequence, ordered among themselves.  The brief asked
whether a colliding key could produce a wrong tree.  It cannot, and the reason
is structural rather than statistical: **a key only SELECTS a candidate.**
Reuse then demands, additionally, that the extent text be byte-identical, that
the start column and the enclosing layout depth and the `bol` at entry be what
they were, and that every byte the cached parse EXAMINED still be there.  Under
those four conditions an identical text in an identical layout context parses
identically, so a key collision can cost a hit and can never yield a tree a
fresh parse would not give.  (7.2's reachable/unreachable rule continues to
govern what the INFERENCE cache may key — an unreachable item's text is in the
scope key and any edit to it still drops the per-uri inference cache.  The two
caches are independent: 7.1b reuses the PARSE of such a statement while 7.2
refuses to reuse its TYPE.  The corpus differential includes an edit aimed at an
unreachable item on every file that has one.)

### 1.2 The guard — 7.1a's mark, evaluated on the bytes

An entry is reused iff

1. the scanner's extent starts exactly where the parse stands (`start == s.offset`),
2. its **extent text is byte-identical** (`old.contents.regionMatches(e.startOffset, contents, start, len)`),
3. its **start COLUMN, enclosing layout DEPTH and `bol` at entry** are what they
   were — the two backward dependencies 7.1a review **F4** says the forward-only
   mark cannot carry, plus the layout flag that decides a vsemi, and
4. **no edit intersects `[start, start + examinedLength)`** — 7.1a's high-water
   mark, stored RELATIVE to the statement start (review F4) and re-anchored at
   the current start on every lookup.

Conjunct 4 is evaluated **directly on the bytes** (`SurfaceCache.examinedUnchanged`):
does the new buffer hold, at `[start, start + examinedLength)`, what the old one
held at `[oldStart, oldStart + examinedLength)`?  That is the roadmap's predicate
itself rather than a model of it, and it is exact for any number of scattered
edits at once, where a changed-window model (common prefix + common suffix) must
refuse reuse across the whole span between the first edit and the last.  It was
measured both ways: on the revert-through-every-edit step of the corpus
differential the window model reused **0** of 104 sample statements and the byte
guard reuses **49**, with the same 0 mismatches.  The extent list is still
recomputed lexically from the new text every check, which is the property the
roadmap's "compare the extent lists" sentence exists to protect: a merge or a
split shows up as a changed extent, never as a silently reused tree.

**The end of input is inside the guard.**  7.1a's convention counts a probe at
`p` as examining `p`, so `examinedLength` may run one past the buffer: the parse
depended on there being nothing there.  When it does, `examinedUnchanged` also
requires the two buffers to END at the same distance from the statement.

**AND ONE CONJUNCT THAT IS NOT ABOUT SOUNDNESS BUT ABOUT TERMINATION** (review
R-3): `e.consumedLength > 0`.  A hit advances the parse by the entry's consumed
length, so an entry that consumed NOTHING would be a committed no-op and
`sepEndBy(semi)` would spin on it — the one failure mode of this design that is
not a wrong tree but a hang.  Nothing can build such an entry (the miss path
records only when `end > s.offset`, and the only arm that could produce one is
`statementBody` returning `Pure`) and none exists in the corpus, so the conjunct
is defence for a cache from ANY source, and property (iv) in §3.2 exercises it
with an entry poisoned by hand.

**The mark is carried FORWARD** into the new entry on a hit (STAGE-4 INVARIANT
"REUSE METADATA SURVIVES REUSE"): a reused statement is not parsed and computes
no mark of its own, so its entry keeps the `examinedLength` it had.  A property
pins it (§3.2(iii)).

### 1.3 The splice — the real driver, with the statement BODIES skipped

`SurfaceParsers.moduleCached` runs **`moduleP`, the same driver `module` and
`moduleMarked` run**: the same `header`, the same
`virtualLeftBrace`/`sepEndBy(semi)`/`virtualRightBrace`, the same closing `eof`.
Only the statement parser is replaced, by one that at each statement's entry
position either

* **HIT** — advances the state instead of parsing it: `offset` by the entry's
  `consumedLength`, the position to the entry's exit position moved by the line
  delta, `bol` to the entry's exit `bol`, and returns the cached tree with every
  span moved by the delta (§1.4); or
* **MISS** — runs `statementBody` exactly where the whole-file parse would run
  it, at the real layout depth, with the real rest of the file after it, and
  records a fresh entry with its own mark.

**THE END-SPAN RULE, corrected against the brief, with the measurement.**  The
brief (from 7.0's NOTE (ii)) says the splice must re-derive **every** statement's
top-level end span from the NEXT extent's start.  That is right for the 15
statements 7.0 §4.3 found and **wrong for the other 514**, and this item measured
it: over the 253-file corpus, a whole-file parse ends a top-level statement's own
`Span`

| where the whole-file parse's top-level span ENDS | statements |
|---|---|
| exactly at the lexical extent's end | **59,167** |
| exactly at the NEXT extent's start | **3,502** |
| elsewhere (the last statement of a file; a block closed part-way through the trivia) | **2,543** |

The mechanism, which 7.0 saw as a slice artifact: a statement's last token runs
`optionalSpace`, which FAILS on the virtual semicolon the next top-level line
produces and is rolled back — so the span stops at the extent.  A statement that
ends in a LAID-OUT block (`where`, `private`, `foreign`, `database`, a class
body) closes it through `virtualRightBrace`, whose `layout` call consumes the
trivia and **is not rolled back** — so the span runs to the next statement's
first character.  A blanket re-derivation would therefore have broken 59,167
statements to fix 3,502.

This design needs no rule at all: **a miss is parsed in situ over the whole
buffer**, so its end span is whatever the whole-file parse would produce, by
construction; and a hit CARRIES its end span and moves it by the line delta,
which is sound because the end position is inside the guard
(`endOffset <= examinedEnd` for every corpus statement, 7.1a property (ii)) —
any edit that could move it refuses the reuse.  The differential's 0 mismatches
over 2,613 steps, every `Span` compared, is the evidence.

This is also why the miss path does not slice.  `statementFailure`'s slice ends
the input at the extent, which changes three things the parse can see:
`layoutEndsWith`'s end-of-input test, `offside`'s `offset != input.length`
branch, and `virtualRightBrace`'s closer — the first two silently, the third
visibly (7.0's 15).  The repositioned `ParseState` the brief names is kept
exactly — `layoutStack = List(IndentedLayout(startCol, "statement"),
IndentedLayout(1, "top level"))` (which is what `moduleP` itself holds at a
top-level statement), `bol = false` — but the input is the whole file, which is
strictly more faithful and also cheaper (no substring copy).  The known
divergence 7.1b was asked to close — `statementFailure`'s docstring's "a slice
re-parse may SUCCEED where the splitter rejected" — **cannot arise on this miss
path**, because there is no slice: the statement parser sees exactly the input,
the layout stack and the successor bytes the whole-file parse sees.  The
docstring's divergence remains true of `statementFailure` itself, which this item
does not touch (it is still what `NewPipeline` uses to position a syntax
diagnostic).

**THE HEADER IS RE-PARSED EVERY CHECK, and that is the decision.**  The 62
`import`/`export` extents of Report.e are consumed by `header`, not by the
statement driver, so they get no `StatementMark` (7.1a review F7(1)) and never
reach a cache lookup.  Re-parsing the header costs **8 ms of a 844 ms parse**
(7.0's table); caching it would need a second cache for a second grammar and a
second guard, for 1 % of the read.  7.0's NOTE (iv) — the header is parsed TWICE,
by two grammars, 8 + 6 ms — is unaffected by this item and stays where it is.

### 1.4 Re-anchoring — `Anchors`, over the whole statement

A reused statement's spans are moved by `delta = newStartLine - entry.startLine`
lines, through `Anchors.absSpan` (7.2's helper, rule 2: **columns are never
shifted** — the statement's own text fixes every column and every internal line
offset, and a changed text is a different key).  `SurfaceCache.Shift` is that
walk over the sealed surface hierarchy, with no default arm, and `delta == 0` —
the common keystroke — skips it entirely.

---

## 2. WHAT WAS BUILT (files changed)

| file | what |
|---|---|
| `core/.../surface/SurfaceCache.scala` | **NEW** — `Key`, `Entry`, `Cache`, `keysOf`, `examinedUnchanged` (the guard), and `Shift` (the `Anchors.absSpan` walk over every surface node).  The design and its four conditions are in its header comment |
| `core/.../surface/SurfaceParsers.scala` | **+158 lines, 0 removed** — `moduleCached` (the editor-only entry) and `posAt` (the `Pos` rebuild for a hit).  `module`, `statement`, `statementBody`, `statementFailure` and `moduleMarked` are untouched |
| `core/.../rename/NewPipeline.scala` | `readModuleCached` beside `readModuleTolerant`; `Read.surfaceCache`; `read` gained two defaulted parameters.  `readModule` and the strict branch are unchanged |
| `core/.../lsp/Documents.scala` | `Doc.surface`, carried across `put` like the inference cache; `surfaceFor`/`putSurface` |
| `core/.../lsp/Resident.scala` | `checkFile` reads through `readModuleCached` and stores the new cache; the check log line gained `, surface H of N statements` (appended AFTER `components)`, which is where `perf-client.py`'s harvest regex stops) |
| `scalacheck-binding/.../TestSurfaceCache.scala` | **NEW** — the corpus differential and four pins (§3.2) |
| `tracker/lsp-tests/Splice.e` | **NEW** — the end-to-end fixture (a `where`, a `private` block, an operator definition, a multi-line `let`) |
| `tracker/tools/lsp-client.py` | **+14 checks** (§4.2) |
| `docs/lsp.md` | **closing round (review R-2, R-1)** — the three editor latency rows re-measured, a new worst-site row, an honest cold-open row, the fast-mode split corrected, and one paragraph on what the cache is and what it retains |
| `tracker/loopmodel/LSP4-7.1b-CACHE.md` | **NEW** — this report |

`tracker/LSP-ROADMAP.md` and `tracker/lean/` untouched.  `Session.scala` untouched.

---

## 3. THE DIFFERENTIAL — the invariant's oracle, and this item's real test

### 3.1 The corpus run (`<scratch>/7.1b/Diff71b.scala`)

**SEED 71.**  Per file, a deterministic `scala.util.Random(71 * 31 + path.hashCode)`
chooses among the candidates for each edit SHAPE, so the sequence is reproducible
per file and different across files.  Every edit is applied to the text the
previous one produced — MULTI-EDIT, with the cache carried across the whole
sequence (swift-syntax #3397 is invisible to a single-edit test).

The twelve steps, in order: `cold` (the whole file, no cache) — `char-insert-top`
— `char-delete-mid` — `line-insert-top` (the line shift) — `stmt-insert` — 
`stmt-delete` — `trivia-comment` (a comment inserted in the trivia between two
extents: 7.0 §4.3's lookahead shape) — `merge` (a statement indented two columns,
so the offside rule fuses it into its predecessor) — `split` (a continuation line
dedented to column 1, so one statement becomes two) — `block-edit` (inside a
`private`/`database` block) — `unreachable-edit` (inside an operator/backtick/
`_`/`'` item, 7.2's R-1 class) — `end-edit` — `revert` (back to the original
text, every earlier edit undone at once).

At EVERY step: `SurfaceParsers.moduleCached(.., prev)` against
`SurfaceParsers.moduleMarked(..)` on the same text — **structural equality of the
whole `SModule`, which is every `Span` of every node** — and, in `--diags` mode,
`NewPipeline.readModuleCached` against `NewPipeline.readModuleTolerant` in a
fresh empty `SessionEnv` with a fresh `Supply` on both sides, comparing the
**`Diag` list** (phase, span, message) the tolerant read produces.  A step where
both sides REFUSE compares the rendered `Err`.

**RESULTS — 0 MISMATCHES.**

| | |
|---|---|
| seed | **71** |
| files | **253** (stdlib 161 + `core/examples`, the standing corpus; `shouldfail/`, `shouldfail-controls/` and `incomplete/` excluded as in every Stage-3/4 sweep) |
| steps | **2,613** (12 shapes + the cold step, minus the shapes a given file has no candidate for) |
| statements spliced | **73,648** — **54,274 hits, 19,374 misses (73.7 % reused)** |
| **SModule mismatches** | **0** — structural equality including every `Span`, at every one of the 2,613 steps |
| **diagnostic mismatches** | **0** over **2,601** steps (the 12 steps where one side refused are compared as refusals instead, and agreed) |
| wall time | 384 s with the diagnostics comparison, 177 s without |

Per shape, over the whole corpus:

| step | hits | misses | what it says |
|---|---|---|---|
| `cold` | 0 | 6,281 | the floor: with no cache every statement is parsed |
| `char-insert-top` | 6,040 | **241** | one character in the first statement's body: ~1 miss per file |
| `char-delete-mid` | 5,044 | 1,200 | a character at a statement's END: the successor's first byte moves, so its predecessor misses too |
| `line-insert-top` | 5,295 | 986 | a whole line at the top — the 7.2 cliff shape; everything below is reused and re-anchored |
| `stmt-insert` | 5,042 | 1,404 | a new statement: itself, its neighbour, and the ordinal shift of its own head word |
| `stmt-delete` | 5,042 | 1,193 | |
| `trivia-comment` | 5,053 | 1,208 | a comment in the lookahead region: the PRECEDING statement misses, which is exactly what 7.1a's mark is for |
| `merge` | 4,630 | 1,388 | two statements fused by an indent — the merged extent's text differs, so it misses; the rest survive |
| `split` | 4,363 | 1,233 | one statement broken in two by a dedent |
| `block-edit` | 2,050 | 364 | inside a `private`/`database` block (only files that have one) |
| `unreachable-edit` | 2,665 | 371 | inside an operator/backtick/`_`/`'` item (only files that have one) |
| `end-edit` | 5,060 | 1,214 | |
| `revert` | 3,990 | 2,291 | every earlier edit undone at once: the scattered-edit case, where the byte guard reuses what a changed-window model could not |

**THE END-SPAN AUDIT** (the same run, `--audit`) is in §1.3: 59,167 statements
end at their extent's end, 3,502 at the next extent's start, 2,543 elsewhere.

### 3.2 What ships (`scalacheck-binding/.../TestSurfaceCache.scala`)

Five properties, `sbt 'core/testOnly *TestSurfaceCache'`:

| property | what it pins |
|---|---|
| **the differential** | the same generator over a deterministic SAMPLE — every fourth corpus file plus `Layout/Report.e` — with the full corpus behind `-Dermine.test.surfacecache.full=true`.  Floors: ≥ 60 files, ≥ 600 steps, 0 mismatches, **and two anti-vacuity floors** (overall reuse > 2 : 1, and a one-character body edit reuses > 80 % of the file) so a cache that stopped reusing could not pass |
| **the guard refuses what text equality would allow** | Lean's counterexample in Ermine: `a = 1` then `b = 2` with `b` indented one space.  The edit is strictly AFTER the first statement's text; byte-equality of the extent would reuse it; 7.1a's mark refuses.  The property requires BOTH the refusal and the agreement with a fresh parse |
| **reuse metadata survives reuse** | two edits at the bottom of the file leave the top statement reused TWICE; its entry's `examinedLength` must still be the cold parse's, and that number must exceed its extent (or the pin is vacuous) |
| **a zero-consumption entry is refused** (closing round, review R-3) | an entry built by hand with `consumedLength = 0` must be treated as a MISS, the OTHER statement must still be reused, and the spliced module must equal a fresh parse.  Its failure mode is a HANG, not a wrong answer, so the parse runs on a daemon thread behind a 10 s deadline and the property reports the timeout as the finding |
| **re-anchoring** | one line inserted at the top of `Report.e`: the spliced module equals the fresh one, the majority of statements are HITS, and every statement's span moved by exactly one line |

### 3.3 What the differential does NOT cover, said plainly

* **Files whose module HEADER does not parse** are compared as refusals (both
  sides die with the same rendered `Err`), not as trees; `BadHeader.e` covers the
  path end to end in lsp-smoke.
* **`marks` are not required to be equal.**  A reused entry carries the mark it
  had, which may be up to 23 bytes tighter or wider than the one a fresh parse
  would compute (7.1a's cumulative cell inherits ≤ 23 bytes from its
  predecessors).  The guard only needs to cover what THIS statement examined, and
  that is what the carried number does; the tree is what the differential
  compares.
* **The `.e` corpus is well-formed code plus the four known-broken examples.**
  The `shouldfail/` and `incomplete/` trees are outside the 253-file corpus, as
  they are for every Stage-3/4 sweep.

## 4. THE GATES

Tier 0, plus the seven targeted suites and the three the brief names
(`*TestSurfaceParsers *TestStatementExtents *TestNewPipeline`, all already in the
seven) and the new `*TestSurfaceCache`.  Tier 2 (full `core/test`, alone on the
tree) is the reviewer's, per the item.  One JVM at a time throughout.

| gate | required | **result** |
|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** (no new warning; the E046 quirk needed one `core/clean` after the first edit under `surface/`) |
| `core/testOnly *TestLoopTrace` | 720/720 | **720 solves, 720 segments, 720 agree, 0 hashdiff, 0 eqdiff, 0 skipped, 0 nonpart, fuel 0**, 23.0 s; controls non-vacuous in the same run (id base +1: 46 of 720 disagree; `--flags=nongen`: 58 of 720) |
| the seven targeted suites + `*TestSurfaceCache` | green | **112 properties, 0 failed, 0 errors** — Lower 3.4a 28, Tolerant check 47, Tolerant read 11, Surface parser 2.3a 12, Statement extents 4, NewPipeline 4.1c 2, REPL eval goldens 1, loop model trace 3, **Surface cache 4** |
| `corpus-run.sh --batch` over 154 | 85 / 69 / 0 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** (one JVM, exit 0) |
| corpus outputs vs the 7.1a-commit tree | byte-identical | **154 of 154 identical.**  Run on BOTH class trees (`ERMINE_CP` pointed at `classes-before`), normalising only the two things that are nondeterministic in any two runs — the progress bar's `\r` frames and the `(N.NN seconds)` timings — plus the classpath prefix, which differs because the two trees live in different directories.  Without that normalisation every file differs on both sides of any pair |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests/` EMPTY — goldens byte-unmodified |
| `lsp-smoke.sh` | 480 + this item's | **494** (480 + **14**), PASS |
| boot | 129 modules | **129 modules in 11.96 s** |
| `.ei` droppings | 143, all tracked | **143** by `find . -name '*.ei' \| wc -l` — the 129 the boot gate wrote under `core/target/.../classes/modules/` were deleted by `find core/target -name '*.ei' -delete`; 0 untracked, 0 outside `tracker/` |
| strict path untouched | additive only | `git diff --numstat` on `surface/SurfaceParsers.scala` is **158 insertions, 0 deletions** — `module`, `statement`, `statementBody`, `statementFailure`, `moduleMarked` and `moduleP` are not edited; `Session.scala` does not appear in `git status` at all; `NewPipeline.readModule` and its strict branch are unchanged (the `read` signature gained two DEFAULTED parameters, so no strict caller's behaviour moves) |
| `git diff --stat` == `--stat -w --histogram` | identical | **identical: 294 insertions, 8 deletions** on both, across the five modified files |
| CRLF preserved | yes | every file this item touches is LF in the tree and LF after (`grep -U $'\r'` finds nothing in any of them); the CRLF corpus files are read, never written |
| Tier 1 | not owed | nothing under `parsers/` (`scalaparsers`), `Subst.scala` or `Type.scala` is touched — `git status` names six files, four in `core/.../{surface,rename,lsp}`, one tool and one doc |
| **closing round:** `core/clean core/compile core/copyResources` | green | **green**, 50 s |
| **closing round:** `core/testOnly *TestSurfaceCache` | 5/5 | **5 properties, 0 failed** (the four above plus R-3's), twice: once on the guard as first written and once after its control was added |
| **closing round:** `lsp-smoke.sh` | 494 | **494**, PASS |
| **closing round:** `.ei` | 143 | **143**, all tracked under `tracker/` |
| **closing round:** `git diff --stat` == `--stat -w --histogram` | identical | **identical: 330 insertions, 17 deletions** over six files |

**WHAT THE REVIEWER'S TIER 2 COVERS, exactly.**  Their `core/test` started at
02:58 and this round's first source edit landed at 03:07, after their compile had
already run (the class files' mtimes are unchanged by their run), so **their
1008-test figure is for the tree WITHOUT this round's two-conjunct guard and
fifth property**.  The delta is re-validated by the three runs above — a clean
compile, `*TestSurfaceCache` 5/5 and lsp-smoke 494 — and the guard cannot reach
any other suite: it adds one conjunct to an editor-only reuse predicate and one
condition to an editor-only cache write.

**ONE THING I COULD NOT DO, said plainly.**  This project's rule is that a test
which has never been seen to fail has not been shown to work, so I tried to plant
the R-3 bug (delete both halves of the guard, re-run, watch the new property time
out).  **The edit was refused by this environment's safety classifier** — removing
a guard from a source file reads as sabotage — and I did not work around it.  The
property is instead made non-vacuous by a CONTROL inside it: the same cache,
unpoisoned, is asserted to reuse BOTH statements (`control.hits == 2`), so the
single changed field on one entry is the whole difference between 2 hits and 1,
and the 10 s deadline is what converts the hang into a reported failure rather
than a stuck suite.  A reviewer with the planting available should still do it
once.

### 4.2 The 14 new lsp-smoke checks

A fixture (`tracker/lsp-tests/Splice.e`: a `where` clause, a `private` block, an
operator definition with its fixity, a multi-line `let`) driven through the real
server as a SEQUENCE of `didChange`s — a body edit, an edit ABOVE it (every
statement below shifts a line), a MERGE of two statements (one indented into its
predecessor) and a SPLIT of one (a continuation line dedented) — and then the
same final text opened COLD, after a `didClose` drops the document and its
caches.

* the four edits' published diagnostics, and **`ds_warm == ds_cold` exactly** —
  the client's form of the differential, on the full pipeline rather than the
  parse (the final text is deliberately broken, so the comparison is not `[] == []`);
* the reuse pair in the log line: every `check: Splice` line carries
  `surface H of N statements`; the cold open reuses **0**; a body edit reuses at
  least **N − 2**; an edit above reuses across the line shift; the re-open after
  `didClose` is cold again; and no check ever reports more reuse than the file has
  statements.


## 5. THE A/B — the adoption gate

**THE GATE**: interleaved, before/after/before/after, both sides under load 1.3,
`perf-client.py --rounds 15` on `Layout/Report.e` (round 1 discarded as JIT
warm-up, the steady state is rounds 2..15), the two sides being two saved class
trees (`<scratch>/7.1b/classes-{before,after}`, core AND parsers swapped in the
classpath), one JVM at a time.  **The READ segment must move by at least 200 ms
pooled.**  The read and typecheck figures are the server's OWN, harvested from
its `check:` line, so they are not wall-clock attributions.

| pass | side | load | round trip | **read** | typecheck | debounce | residual | cold open |
|---|---|---|---|---|---|---|---|---|
| 1 | BEFORE (`9180d28`) | 1.22 | 1.672 s | **0.830 s** | 0.520 s | 0.300 | 0.026 | 2.289 s |
| 1 | AFTER | 1.18 | 0.875 s | **0.050 s** | 0.500 s | 0.300 | 0.026 | 2.265 s |
| 2 | BEFORE | 1.21 | 1.690 s | **0.855 s** | 0.510 s | 0.300 | 0.027 | 2.332 s |
| 2 | AFTER | 1.22 | 0.916 s | **0.055 s** | 0.535 s | 0.300 | 0.025 | 2.411 s |
| **pooled** | BEFORE | | **1.681 s** | **0.8425 s** | 0.515 s | | | 2.311 s |
| **pooled** | AFTER | | **0.896 s** | **0.0525 s** | 0.518 s | | | 2.338 s |
| **Δ** | | | **−0.785 s (−46.7 %)** | **−0.790 s (−93.8 %)** | +0.003 s | 0 | −0.001 | +0.027 s |

**THE READ MOVED BY 790 ms POOLED, against a 200 ms gate — 3.9x it**, and the
movement is monotone (both after-runs are below both before-runs by more than
0.77 s, with no overlap of the per-round spreads: before 1.619–1.953 s, after
0.852–1.019 s).  **The typecheck segment is the control and it did not move**
(+3 ms on a 515 ms base, inside its own run-to-run spread), which is what says
the read is where the change landed; reuse stayed at **97 of 154 components** on
every round of all four runs, so the inference cache saw exactly the same work.
The cold open is unchanged (+27 ms on 2.3 s, inside the spread): a first open has
no cache to reuse and pays only the scan (§6).

The residual read of **52 ms** is the floor this design leaves: the header parse
(8 ms, 7.0's table), `StatementExtents.scan` + `Offsets` + the key map (≈ 3 ms),
the driver's own layout work between statements, rename + reassoc + lower
(15 ms, 7.0) and `Definitions.index`.

### 5.1 The miss distribution in practice (`<scratch>/7.1b/Miss71b.scala`)

7.0's protocol, in process: 50 reps after 20 warm-ups, medians, `Layout/Report.e`,
one keystroke at a time against a warm cache.

| keystroke | parse | reused |
|---|---|---|
| COLD whole-file parse (`moduleMarked`, the before-side's work) | **751.8 ms** | — |
| COLD through `moduleCached` with no cache | 754.6 ms | 0 of 529 |
| a body line (perf-client's pinned site, line 281) | **29.2 ms** | 528 of 529 |
| the FIRST statement | 27.2 ms | 528 of 529 |
| **inside the 10.7 KB `private` block (line 1592) — the p99** | **125.8 ms** | 528 of 529 |
| appending at the END of the file | 124.8 ms | 528 of 529 |
| one blank line at the very top (every span is re-anchored) | **26.5 ms** | **529 of 529** |

Three things to read off it.  **The miss is ONE statement, not two** — 7.1a's §5
predicted the statement BEFORE the edited one would also miss, because every
statement's mark reaches one byte into its successor; that bites only when the
edit is at or before the successor's first byte, and a keystroke inside a body is
not.  **The p99 is the 10.7 KB block, as 7.0 predicted** (it measured that block
alone at ~99–104 ms; here the whole read is 126 ms), so one edit in seven lands
on a ~125 ms read instead of a ~29 ms one — still 6x better than the 752 ms it
replaces.  **The line shift is the cheapest case**, not the most expensive: the
`Anchors` walk over all 529 statements costs less than one statement re-parse.

**WHAT THE COLD PATH COSTS — the in-process figure is NOT the answer (review
R-1).**  The `+2.8 ms (0.4 %)` row above is measured with the JIT warm, 20 reps
in, and the reviewer's re-run of the same harness got **−1.9 ms**: in process the
cost is at the noise floor, ≤ ~3 ms either way.  **On a cold JVM it is 30–70 ms**,
because the extent scan, the `Offsets` index, the key map and 529 `Entry`
allocations all run interpreted on the first check of a session.  The four
measured pairs, client-side cold open: **2.298 → 2.353 s (+55 ms, the reviewer)**
and 2.311 → 2.338 s (+27 ms, mine); on the server's own cold READ, 0.92/0.94 →
1.01/1.00 s (theirs) and 0.93/0.97 → 0.93/1.00 s (mine).  The direction is
consistent in all four.  It is ~2 % of a 2.3 s open, it does not touch the gate
(which is the WARM read), and it is the price of every keystroke after it — but
the honest number is 30–70 ms, not 3 ms, and it is what G4 should carry.

**A DUPLICATED SCAN, noted and deliberately not fixed (review R-4).**
`Resident.checkFile` now runs `StatementExtents.scan` TWICE per check — once in
`moduleCached`, once in `TolerantCheck.keys` — at ~2.3 ms each (7.0's table),
which is **4 % of the new 52 ms read** where it was 0.3 % of the old 842 ms one.
Sharing one scan between them is a tidy-up for **7.7 / G4**: it means touching
the check path, which this item promised not to, for 2.3 ms.

## 6. RETENTION — the heap figure (`<scratch>/7.1b/Heap71b.scala`)

`Runtime` delta over 16 independent copies, each after six settled GCs, on
`Layout/Report.e` (77,385 chars, 529 statements):

| held | per copy |
|---|---|
| the buffer alone | 75.7 KB |
| the surface tree alone (`SModule`, 529 statements) | 1,577.7 KB |
| **the whole `SurfaceCache.Cache`** | **1,630.4 KB** (529 entries) |

So the cache costs **1.63 MB for a 77 KB file — 21x the source**, of which
**97 % is the surface tree itself** and 53 KB is the 529 entries plus their map.
In the server the cached `contents` is the PREVIOUS buffer, which `Documents` has
already replaced, so add one buffer: **≈ 1.71 MB per open document**.  THE BOUND:
one cache per open document, REPLACED WHOLESALE by each check (`putSurface`
overwrites; `drop` on `didClose` removes it), so nothing accumulates across
keystrokes and the worst case is (open documents) x (their own size).  The
previous behaviour retained the same tree for the duration of one check and then
dropped it; this item extends its life to the next check.

## 7. WHAT A USER NOW SEES

Keystroke to diagnostics on `Layout/Report.e`, the file of record, from the
server's own numbers:

| | before | after |
|---|---|---|
| round trip | **1.68 s** | **0.90 s** |
| of which the read | 0.84 s | 0.05 s |
| of which inference | 0.52 s | 0.52 s |
| of which the debounce (policy, not work) | 0.30 s | 0.30 s |

The 300 ms debounce is now **33 % of the round trip** instead of 18 %, which is
precisely the trigger Stage-4 Decision (e) wrote for item 7.4 ("the debounce
becomes adaptive, but only AFTER the read is faster", gated on "7.1 or 7.3 having
landed a measured saving").  That gate is now met, and 7.4 is the next item the
arithmetic favours: on this file the remaining 0.90 s is 0.52 inference +
0.30 debounce + 0.05 read + 0.03 residual.

## 8. VERDICT — **GREEN**

**The invariant holds where it is hardest to hold.**  253 files x a 12-step
multi-edit sequence, the cache carried across the whole sequence, **0 mismatches**
of the spliced `SModule` against a fresh whole-file parse — structural equality,
which for this AST means every `Span` of every node — and **0 mismatches** of the
tolerant read's diagnostics over the 2,601 steps where both sides produced a
tree.  The shapes that were most likely to break it are in the sequence by name:
a merge, a split, an edit in the lookahead region the mark exists for, an edit
inside a `private` block, an edit to an item 7.2 calls unreachable, and a revert
of every earlier edit at once.

**The gate is met by 3.9x.**  Read **0.8425 s -> 0.0525 s pooled, −790 ms**,
against a 200 ms gate, with the typecheck segment as a control at +3 ms and
component reuse unchanged at 97 of 154 on every round of all four runs.  Round
trip **1.681 s -> 0.896 s**.  One keystroke's parse is **29 ms** where it was
**752 ms**; the p99 — a keystroke inside the 10.7 KB `private` block — is
**126 ms**; a pure line shift is **26.5 ms** with every one of the 529 statements
reused and re-anchored.

**What it costs.**  2.8 ms (0.4 %) on a cold open, for the scan and the key map.
1.63 MB of heap per open document of Report.e's size (97 % of it the surface tree
itself), replaced wholesale per check and dropped on `didClose`.  One duplicated
`StatementExtents.scan` per check, named in §5.1 as the obvious follow-on.

**Two corrections to the brief, both measured rather than argued.**  (1) The
end-span rule — "re-derive every statement's end span from the next extent's
start" — is right for 3,502 statements and WRONG for 59,167; the divergence 7.0
saw is a property of `virtualRightBrace`, not of statements in general, and this
design reproduces both cases by construction instead of rewriting either (§1.3).
(2) The edits are not enumerated from the extent lists but ANSWERED on the bytes
the mark guards, which is the roadmap's own predicate evaluated exactly and is
what makes a multi-region change (the `revert` step) reuse anything at all
(§1.2).

**What 7.1a becomes.**  Its condition is discharged: 7.1a ships as 7.1b's
precondition, and the +20..48 ms it cost the read is now 6 % of the 790 ms this
item returns.

**What is owed.**  Tier 2 (full `core/test`, ALONE on the tree) at adoption, and
a reviewer's re-run of the differential, the A/B and the gates — once, per
`tracker/GATE-POLICY.md`.  No commit was made.  `tracker/LSP-ROADMAP.md` and
`tracker/lean/` are untouched.  Every `.ei` this item caused has been deleted
(`find core/target -name '*.ei' -delete`; the tree is back to its 143 tracked
ones), and no JVM or polling shell is left running.

### For the reviewer — how to re-run this once

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    sbt -batch -J-Xmx3g core/clean core/compile core/copyResources      # clean: the E046 quirk
    sbt -batch -J-Xmx3g 'core/testOnly *TestSurfaceCache'               # 4/4, ~90 s
    sbt -batch -J-Xmx3g 'core/testOnly *TestSurfaceCache' -Dermine.test.surfacecache.full=true
    #   the whole 253-file corpus in the property, ~3 min
    <scratch>/7.1b/dotc.sh <scratch>/7.1b/Diff71b.scala                 # the scratch differential
    java -cp <scratch>/7.1b/classes:$(cat tracker/repl-classpath.txt) \
         scratch71b.Diff71b 71 --diags --audit                          # 253 files, 2613 steps, 384 s
    java -cp ... scratch71b.Miss71b                                     # the miss distribution
    java -cp ... scratch71b.Heap71b                                     # the heap figure
    TAG=r ORDER=ab PASSES=2 <scratch>/7.1b/ab.sh                        # the A/B, reverse order
    tracker/tools/corpus-run.sh --batch <out> ; tracker/tools/repl-smoke.sh ; tracker/tools/lsp-smoke.sh

`<scratch>/7.1b/` holds `classes-before` (HEAD) and `classes-after` (this tree),
both with core AND parsers, the four A/B logs and JSONs, `diff-final.txt`,
`suites.log`, the two corpus runs and their normalised copies, and
`Diff71b.scala` / `Miss71b.scala` / `Heap71b.scala` / `ab.sh` / `dotc.sh`.
