# Brief: LSP Stage 4, item 7.1b — the statement-extent surface cache (the stage's headline; Tier 0 + Tier 2 at adoption)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (7.0, 7.2 and
7.1a are committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells when you
stop. No commits. Do not touch `tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/7.1b/`.
Item of record: `tracker/LSP-ROADMAP.md` § "Stage 4", item **7.1b** (inside 7.1), with the STAGE-4 INVARIANTS — "A REUSED
SURFACE TREE MUST BE BYTE-FOR-BYTE WHAT A FRESH PARSE WOULD GIVE" (the corpus differential with SYNTHETIC MULTI-EDIT
SEQUENCES, spliced SModule == fresh parse AND diagnostics equal), "REUSE METADATA SURVIVES REUSE", "NO IDENTITY IN A
CACHE KEY" — Decisions (a)(g), and the NOTES carried into 7.1 from 7.0 (reuse unit 529 statements + 62 header
extents; the splice must re-derive each statement's top-level END SPAN from the next extent's start or the
differential fails on 15 of 529 today; 7.1b and 7.3 are not both budgeted; the header is parsed twice). Read
`tracker/loopmodel/LSP4-7.0-READ.md` (§4.3 the divergence; the corrected saving 0.67-0.78 s), `LSP4-7.2-ANCHORS.md`
(the `surface/Anchors.scala` helper you MUST reuse for re-anchoring spans; the reachable/unreachable bind-item rule
in `TolerantCheck.keys`), `LSP4-7.1a-MARK.md` (THE MARK: `NewPipeline.readModuleTolerant(...).marks: List[SurfaceParsers.StatementMark]`, one per top-level statement in order, each `StatementMark(startLine, startCol, startOffset, endOffset, examinedEnd, markAtEntry)` with `examinedLength = examinedEnd − startOffset`; `Nil` on the strict path; the three obligations: carry a reused entry's own mark forward; a mark that reaches its input end (every slice re-parse — `statementFailure` uses `MarkOff`, so a slice re-parse yields NO mark of its own: a miss parsed from its slice must keep the guard it had or be re-guarded from the whole-file mark on the next full parse — decide and state) is TRUNCATED and the guard widens; 7.2's reachable/unreachable rule governs the key, not the mark), `tracker/loopmodel/STAGE4-PRIOR-ART.md` §1.7,
§1.9, §5(a), and `tracker/GATE-POLICY.md` (this is an ADOPTION item: interleaved A/B on the round trip and a full
`core/test` alone are owed; the reviewer runs Tier 2).

THE MEASURED PREMISE (7.0): the whole-file surface parse of Layout/Report.e is 844 ms of a 860 ms read and 61% of
the check; each statement parsed alone through `statementFailure`'s repositioned ParseState sums to 95% of the whole
(residual 43 ms); a one-character edit leaves every other extent identical, so the expected miss is 62/83/173 ms
(byte-weighted mean / p90 / p99 — the p99 is the 10.7 KB `private` block) and the saving 0.67-0.78 s.
THE GATE: interleaved A/B (before/after/before/after, load < 1.3) on Report.e: the READ segment must move by at
least 200 ms pooled or the item is REVERTED and the number recorded (the P5(d) precedent).

THE 7.1a REVIEW'S OBLIGATIONS (LSP4-7.1a-REVIEW.md §7, F4/F6/F7 — conditions, not suggestions):
- carry `examinedLength` (RELATIVE to the statement start), never an absolute offset, into a cache entry; re-anchor
  with `Anchors` at lookup; `markAtEntry` may refine only the END of the guard — using it as the guard's START is the
  one unsound reading;
- the guard is FORWARD-only: the statement's start column and its enclosing layout depth (column 1 at top level; the
  `private`/`database` block context) must stay in the reuse condition — text equality plus the forward guard is not
  enough if the statement could be re-laid-out by what precedes it;
- join marks to statements by POSITION (`startLine`,`startCol`), never by index (the record is built by a flatMap
  and a silent `get`);
- the 62 header extents (import/export) get NO mark; a slice re-parse runs with `MarkOff` and yields no mark of its
  own, so a miss parsed from its slice must either keep the guard it had (if any) or be treated as truncated
  (guard = whole remaining input) until the next whole-file parse refreshes it — state the rule; a rendered caret
  line in a diagnostic lies outside the guard.

## What to build
7.1b.1 A NEW editor-path-only entry beside `NewPipeline.readModuleTolerant` (e.g. `readModuleCached(fileName,
      contents, mh, prev: Option[SurfaceCache])`); `SurfaceParsers.module` and the strict `readModule` are NOT
      touched. THE KEY per top-level extent: `(headWord, ordinal among extents with that head word)` — scoped per head
      word, never a global ordinal — the grouping `TolerantCheck.keys` already computes; for the UNREACHABLE items of
      7.2's rule (empty head word, truncated head) decide and state the key (the raw extent text? an ordinal among
      empty heads?) — a key that collides is a wrong tree, so prefer a miss. WHAT INVALIDATES: an entry is reused iff
      (1) its extent text is byte-identical AND (2) no edit intersects `[start, start + examinedLength)` where
      `examinedLength` is 7.1a's mark for that statement (carried FORWARD into the new entry on reuse — the invariant).
      Edits are found by comparing the old and new statement-extent lists from `StatementExtents.scan` (lexical, from
      the NEW text every check — merges and splits show up as changed extents, never as a silently reused tree).
7.1b.2 THE SPLICE: misses are parsed from their own slice with `statementFailure`'s repositioned `ParseState`
      (`layoutStack = List(IndentedLayout(startCol, "statement"), IndentedLayout(1, "top level"))`, `bol = false`);
      hits are re-anchored with `Anchors` on the two line fields (top-level statements start at column 1, so no
      column arithmetic); EVERY statement's top-level END SPAN is re-derived from the NEXT extent's start (7.0's 15
      divergent statements: the whole-file parse runs the end to the next statement's start; the slice stops at the
      extent) — do this for hits AND misses so the spliced tree is what a whole-file parse gives; then
      `SModule(fileName, header, statements)` is reassembled and handed to the UNCHANGED rename -> reassoc -> lower ->
      check pipeline. The 62 header extents (import/export) are raw-statement fallbacks in the statement grammar:
      decide whether they are cached like statements or re-parsed each time (they are cheap; say which).
      KNOWN DIVERGENCE TO CLOSE: `statementFailure`'s docstring says a slice re-parse may SUCCEED where the splitter
      rejected (context the slice lacks) — the differential decides whether that is a bug to fix or a miss-only path.
7.1b.3 THE DIFFERENTIAL — the invariant's oracle, and the item's real test: over the 253-file corpus (stdlib +
      core/examples), for a GENERATED SEQUENCE of edits per file with a recorded seed — insert/delete a character, a
      line, a whole statement; at the top, the middle and the end; an edit that MERGES two statements and one that
      SPLITS one; an edit inside the lookahead region of the preceding statement (the 7.0 §4.3 shape); an edit inside
      a `private`/`database` block; an edit to an unreachable (operator/backtick) item — apply the sequence
      step by step, and at EVERY step assert the spliced `SModule` == a fresh whole-file parse of the same text
      (structural equality including every Span) AND the diagnostics (the tolerant read's `Diag`s) are equal. Report:
      files × steps, hits/misses per step, 0 mismatches — or every mismatch with its shape. Multi-edit, not
      single-edit (swift-syntax #3397). This is a TestSurfaceParsers/TestTolerantRead-style property that SHIPS (fast
      enough? measure; if > ~2 min, gate the full corpus behind a property and ship a 30-file sample).
7.1b.4 THE A/B (adoption gate): `perf-bench.sh editor -k 15` before/after/before/after on Report.e, load < 1.3; report
      the pooled Δ on the ROUND TRIP and on the READ segment (the phases timers from 7.0 give the split); the gate is
      ≥ 200 ms on the read. Also the MISS distribution in practice: the read time per keystroke over `perf-client.py`'s
      edit sequence (which edits a body line — a typical miss), and one keystroke inside the 10.7 KB private block
      (the p99). RETENTION: a heap figure — the cache holds one surface tree per open document (a GC root); measure
      the retained size for Report.e (a heap histogram or `Runtime` delta) and state the bound (per open document,
      replaced wholesale per check).
7.1b.5 GATES: Tier 0 (`core/compile core/copyResources`; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>`
      85/69/0 over 154 with outputs byte-identical to the 7.2-commit run; `repl-smoke.sh` 8/66 goldens unmodified;
      `lsp-smoke.sh` 480 + yours — add checks that a didChange sequence (edit, edit above, merge two statements,
      split one) publishes the SAME diagnostics as a cold open of the final text, and that the reuse count is
      reported in the log line); the seven targeted suites + `*TestSurfaceParsers *TestStatementExtents
      *TestNewPipeline`; boot 129; `.ei` 0 by `find`; strict path diff empty (`Session.scala`, `SurfaceParsers.module`
      untouched — `git diff -- core/src/main/scala/com/clarifi/reporting/ermine/surface/SurfaceParsers.scala` must
      show only additive, editor-only entry points if any); `git diff --stat` == `--stat -w --histogram`; CRLF
      preserved. Tier 2 (full `core/test` alone) is the reviewer's.
7.1b.6 REPORT `tracker/loopmodel/LSP4-7.1b-CACHE.md`: the key/invalidation/splice design with the end-span rule; the
      differential's numbers (seed, files × steps, hit/miss counts, mismatches); the A/B table with the read Δ against
      the 200 ms gate and the verdict (ADOPT / REVERT with the number); the miss distribution; the heap figure; every
      gate number; what a user now sees (keystroke-to-diagnostics before/after). Outcomes: GREEN (differential 0
      mismatches, read Δ ≥ 200 ms) / REVERTED (the number) / PARTIAL. No silent weakening; STOP after the report — a
      reviewer re-runs the differential, the A/B and Tier 2 once.
